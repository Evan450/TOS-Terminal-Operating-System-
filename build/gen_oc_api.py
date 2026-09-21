#!/usr/bin/env python3
"""Generate Reference/oc-component-api/oc_api.lua from mod SOURCE.

Why this exists: a component method that does not exist fails only on real
hardware, because an off-box mock proxy answers to any method name with any
arguments. Three such bugs shipped in TOS -- robot.durabilityLevel,
robot.use passing a boolean where the mod declares an integer, and
tape.getSpeed/getVolume, which Computronics never had. Each was found by
reading the mod's own @Callback declarations, and each was invisible to the
test suite.

So the declarations are extracted once, vendored as a Lua table, and checked
by an ordinary offline test (usr/lib/tests/test_component_api.lua). The
alternative -- having the test clone 14 MB of Scala -- is a test that skips
on most runs, and a check nobody trusts.

    python build/gen_oc_api.py <opencomputers-clone> [options]

      --computronics <path>   Computronics clone (tape_drive, chat boxes)
      --openprinter  <path>   OpenPrinter clone (printer)
      --out <path>            default: ../Reference/oc-component-api/oc_api.lua

HOW IT RESOLVES A COMPONENT TYPE, because it is not one file per component:
  * `withComponent("gpu")` in a class names the Lua-visible type.
  * A class inherits callbacks from what it extends -- `class Robot extends
    prefab.ManagedEnvironment with Agent`, and `trait Agent extends
    traits.WorldControl with ...`. So parents are followed transitively and
    their callbacks unioned in.
  * Anything that declares a type but resolves to no callbacks is emitted
    with an empty set rather than dropped: "this type exists and exposes
    nothing we found" is a different statement from "unknown type", and the
    checker treats them differently.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from datetime import date

CALLBACK = re.compile(r"@Callback")
NAMEARG = re.compile(r'name\s*=\s*"([A-Za-z0-9_]+)"')
DOCARG = re.compile(r'doc\s*=\s*"([^"]*)"')
SCALA_DEF = re.compile(r"\bdef\s+([A-Za-z0-9_]+)")
JAVA_DEF = re.compile(r"\b(?:public|private|protected)?\s*Object\[\]\s+([A-Za-z0-9_]+)")
DECL = re.compile(
    r"^\s*(?:public\s+|private\s+|protected\s+|static\s+|final\s+"
    r"|abstract\s+|sealed\s+|case\s+)*"
    r"(class|trait|object|interface)\s+([A-Za-z0-9_]+)([^{]*)")
COMPONENT = re.compile(r'withComponent\(\s*"([a-z_0-9]+)"')
# `extends A with B with C` -- strip type params and constructor args.
EXTENDS = re.compile(r"extends\s+(.+)")


def signature(doc: str) -> str:
    """Keep the signature, drop the prose after the `--` or `;`."""
    if not doc:
        return ""
    sig = doc.split(" -- ")[0].split("; ")[0].strip()
    return sig[:180]


def parse_parents(tail: str) -> list[str]:
    m = EXTENDS.search(tail)
    if not m:
        return []
    names = []
    for part in re.split(r"\bwith\b", m.group(1)):
        part = part.split("{")[0]
        part = re.sub(r"\[.*?\]", "", part)
        part = re.sub(r"\(.*", "", part)
        part = part.strip()
        if not part:
            continue
        # A parent is ONE identifier. Anything after whitespace is body text
        # that leaked in, and must never become a parent name.
        part = part.split()[0].split(".")[-1].strip(",")
        if re.fullmatch(r"[A-Za-z0-9_]+", part or ""):
            names.append(part)
    return names


def scan_tree(root: str, ext: str, defre: re.Pattern):
    """type-decl name -> {parents, callbacks{name: sig}, component, file}"""
    decls: dict[str, dict] = {}
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if not fn.endswith(ext):
                continue
            path = os.path.join(dp, fn)
            lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
            # Track the innermost declaration seen so far by indentation.
            stack: list[tuple[int, str]] = []
            i = 0
            while i < len(lines):
                line = lines[i]
                dm = DECL.match(line)
                if dm:
                    indent = len(line) - len(line.lstrip())
                    while stack and stack[-1][0] >= indent:
                        stack.pop()
                    name = dm.group(2)
                    #! A declaration wraps. Redstone.scala puts every `extends`
                    #! on the NEXT line:
                    #!   class Bundled(val redstone: ...)
                    #!     extends component.RedstoneVanilla with ...
                    #! so reading only the first line lost the parents and the
                    #! redstone type came out with 2 methods instead of 14.
                    #!   Join on the LINE's brace, not the captured tail's:
                    #! DECL captures `([^{]*)`, so the tail never contains `{`
                    #! and a "join until {" test could never be satisfied. It
                    #! swallowed following lines instead, and DataCard's parent
                    #! came out as
                    #! 'DataCard  private final lazy val deviceInfo = Map',
                    #! which is why the data card had one method, not fifteen.
                    tail = dm.group(3)
                    if "{" not in line:
                        look = i
                        while look + 1 < len(lines) and look - i < 5:
                            look += 1
                            nxt = lines[look]
                            if DECL.match(nxt) or re.match(
                                    r"\s*(@|def |val |var |private |protected "
                                    r"|override |lazy )", nxt):
                                break
                            tail += " " + nxt.strip()
                            if "{" in nxt:
                                break
                    key = name
                    n = 2
                    while key in decls and decls[key]["file"] != path:
                        key = f"{name}#{n}"
                        n += 1
                    decls.setdefault(key, {"parents": [], "callbacks": {},
                                           "component": None, "file": path,
                                           "name": name})
                    decls[key]["parents"] = parse_parents(tail)
                    stack.append((indent, key))
                cm = COMPONENT.search(line)
                if cm and stack:
                    decls[stack[-1][1]]["component"] = cm.group(1)
                elif cm and not stack:
                    pass
                if CALLBACK.search(line):
                    txt, j, depth = "", i, 0
                    while j < len(lines):
                        txt += lines[j]
                        depth += lines[j].count("(") - lines[j].count(")")
                        if depth <= 0:
                            break
                        j += 1
                    k, dname = j, None
                    while k < min(j + 8, len(lines)):
                        m = defre.search(lines[k])
                        if m:
                            dname = m.group(1)
                            break
                        k += 1
                    explicit = NAMEARG.search(txt)
                    lua_name = explicit.group(1) if explicit else dname
                    if lua_name and stack:
                        doc = DOCARG.search(txt)
                        decls[stack[-1][1]]["callbacks"].setdefault(
                            lua_name, signature(doc.group(1) if doc else ""))
                    i = k
                i += 1
    return decls


#! Only these trees implement components. `integration/` holds one driver per
#! supported mod and reuses a handful of class names -- twenty files declare
#! `class Environment` -- so resolving a parent by bare name across the whole
#! source pulled every integration driver's callbacks into `robot`, which came
#! out with 111 methods including getBrewTime. A checker that accepts anything
#! is worse than no checker, so parent lookup is restricted to the component
#! implementations and to names that are UNAMBIGUOUS there. An ambiguous or
#! unknown parent is skipped and named in `unresolved_parents`, so the gap is
#! visible in the table rather than silently widening a type.
COMPONENT_TREES = ("server/component/", "common/component/",
                   "common/tileentity/", "server/machine/")


def resolve(decls: dict[str, dict]):
    """component type -> {method: signature}, parents unioned in."""
    def in_component_tree(path: str) -> bool:
        p = path.replace(os.sep, "/")
        return any(t in p for t in COMPONENT_TREES)

    counts: dict[str, int] = {}
    for d in decls.values():
        if in_component_tree(d["file"]):
            counts[d["name"]] = counts.get(d["name"], 0) + 1
    by_name: dict[str, list[str]] = {}
    for key, d in decls.items():
        if in_component_tree(d["file"]) and counts.get(d["name"], 0) == 1:
            by_name.setdefault(d["name"], []).append(key)
    #! Same-file parents win, and are exempt from the ambiguity rule. A
    #! component is often one file of nested classes -- DataCard.scala is
    #! `object DataCard { abstract class Common; class Tier1 extends Common }`
    #! -- and names like Tier1 and Common recur across a dozen component
    #! files, so the global unambiguous map dropped them and the data card came
    #! out with one method instead of eighteen. Inside one file the reference
    #! is unambiguous by construction.
    by_file_name: dict[tuple[str, str], list[str]] = {}
    for key, d in decls.items():
        by_file_name.setdefault((d["file"], d["name"]), []).append(key)

    def parents_of(key: str, parent: str) -> list[str]:
        same = by_file_name.get((decls[key]["file"], parent))
        if same:
            return [k for k in same if k != key]
        return by_name.get(parent, [])

    unresolved: set[str] = set()

    def collect(key: str, seen: set[str]) -> dict[str, str]:
        if key in seen:
            return {}
        seen.add(key)
        d = decls[key]
        out = dict(d["callbacks"])
        for p in d["parents"]:
            keys = parents_of(key, p)
            if not keys:
                unresolved.add(p)
                continue
            for pk in keys:
                for k, v in collect(pk, seen).items():
                    out.setdefault(k, v)
        return out

    #! The component NAME can live in an ancestor. withComponent("redstone")
    #! is declared once, in the RedstoneSignaller trait, and the classes that
    #! actually carry getInput/setOutput/getBundledInput only inherit it -- so
    #! attributing a type solely from the class that declares the name found
    #! almost nothing for redstone. Walk up for the name as well as for the
    #! callbacks.
    def component_of(key: str, seen: set[str]):
        if key in seen:
            return None
        seen.add(key)
        d = decls[key]
        if d["component"]:
            return d["component"]
        for p in d["parents"]:
            for pk in parents_of(key, p):
                c = component_of(pk, seen)
                if c:
                    return c
        return None

    types: dict[str, dict[str, str]] = {}
    # A type whose own class declares the name exists even with no callbacks
    # (keyboard, memory): "exists and exposes nothing" is not "unknown".
    for d in decls.values():
        if d["component"]:
            types.setdefault(d["component"], {})
    for key, d in decls.items():
        comp_name = component_of(key, set())
        if not comp_name:
            continue
        d = dict(d)
        d["component"] = comp_name
        got = collect(key, set())
        cur = types.setdefault(d["component"], {})
        for k, v in got.items():
            if k not in cur or (not cur[k] and v):
                cur[k] = v
    return types, sorted(unresolved)


def machine_api(oc_root: str) -> tuple[list[str], list[str]]:
    path = os.path.join(oc_root, "src", "main", "resources", "assets",
                        "opencomputers", "lua", "machine.lua")
    try:
        src = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return [], []

    def keys(var: str) -> list[str]:
        #! libcomputer is `local libcomputer = {`, but libcomponent is
        #! forward-declared (`local libcomponent`) and assigned later, so the
        #! `local` form finds nothing and the table came out empty. Match the
        #! assignment either way.
        m = (re.search(r"local\s+" + var + r"\s*=\s*\{", src)
             or re.search(r"^" + var + r"\s*=\s*\{", src, re.M))
        if not m:
            return []
        i, depth, buf = m.end(), 1, ""
        while i < len(src) and depth > 0:
            ch = src[i]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    break
            buf += ch
            i += 1
        return sorted({k for k in re.findall(r"^\s{2}([A-Za-z_]+)\s*=", buf,
                                             re.M)})

    return keys("libcomputer"), keys("libcomponent")


def rev(path: str) -> str:
    try:
        out = subprocess.run(["git", "-C", path, "rev-parse", "--short", "HEAD"],
                             capture_output=True, text=True, timeout=30)
        return out.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    oc = sys.argv[1]
    comp = printer = None
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.normpath(os.path.join(here, "..", "..", "Reference",
                                        "oc-component-api", "oc_api.lua"))
    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--computronics":
            comp = args[i + 1]; i += 2
        elif args[i] == "--openprinter":
            printer = args[i + 1]; i += 2
        elif args[i] == "--out":
            out = args[i + 1]; i += 2
        else:
            print(f"unknown option: {args[i]}")
            return 2

    scala_root = os.path.join(oc, "src", "main", "scala")
    if not os.path.isdir(scala_root):
        print(f"error: {scala_root} not found -- is that an OpenComputers clone?")
        return 1
    decls = scan_tree(scala_root, ".scala", SCALA_DEF)
    types, unresolved = resolve(decls)
    all_names = {n for d in decls.values() for n in d["callbacks"]}
    sources = {"opencomputers": rev(oc)}

    for label, path, ext in (("computronics", comp, ".java"),
                             ("openprinter", printer, ".java")):
        if not path:
            continue
        jroot = os.path.join(path, "src", "main", "java")
        if not os.path.isdir(jroot):
            print(f"warning: {jroot} not found, skipping {label}")
            continue
        jdecls = scan_tree(jroot, ext, JAVA_DEF)
        # Java side declares no withComponent(); attribute by file name, which
        # is stable for these two mods and is stated in the README.
        JMAP = {"TileTapeDrive": "tape_drive", "PrinterTE": "printer"}
        for key, d in jdecls.items():
            base = os.path.basename(d["file"]).replace(".java", "")
            t = JMAP.get(base)
            if t and d["callbacks"]:
                cur = types.setdefault(t, {})
                for k, v in d["callbacks"].items():
                    cur.setdefault(k, v)
                all_names |= set(d["callbacks"])
        sources[label] = rev(path)

    libcomputer, libcomponent = machine_api(oc)

    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- OpenComputers component API, extracted from mod SOURCE.\n")
        f.write("-- GENERATED by TOS-Dev/build/gen_oc_api.py -- do not hand-edit.\n")
        f.write("-- Regenerate when the mods update; see the README beside this file.\n")
        f.write("--\n")
        f.write("-- types[<component type>][<method>] = the declared signature\n")
        f.write("-- all_names = every callback name seen anywhere, so a checker can\n")
        f.write("--   tell 'wrong component' from 'exists nowhere'.\n")
        f.write("return {\n")
        f.write(f"  generated_on = {lua_str(date.today().isoformat())},\n")
        f.write("  sources = {\n")
        for k in sorted(sources):
            f.write(f"    {k} = {lua_str(sources[k])},\n")
        f.write("  },\n")
        f.write("  libcomputer = {\n")
        for n in libcomputer:
            f.write(f"    {lua_str(n)},\n")
        f.write("  },\n")
        f.write("  libcomponent = {\n")
        for n in libcomponent:
            f.write(f"    {lua_str(n)},\n")
        f.write("  },\n")
        f.write("  all_names = {\n")
        for n in sorted(all_names):
            f.write(f"    {lua_str(n)},\n")
        f.write("  },\n")
        f.write("  -- Parent names the resolver could not pin to exactly one\n")
        f.write("  -- declaration in the component trees. Listed so a missing\n")
        f.write("  -- method can be explained rather than puzzled over.\n")
        f.write("  unresolved_parents = {\n")
        for n in unresolved:
            f.write(f"    {lua_str(n)},\n")
        f.write("  },\n")
        f.write("  types = {\n")
        for t in sorted(types):
            f.write(f"    [{lua_str(t)}] = {{\n")
            for m in sorted(types[t]):
                f.write(f"      [{lua_str(m)}] = {lua_str(types[t][m])},\n")
            f.write("    },\n")
        f.write("  },\n")
        f.write("}\n")
    # Write-then-rename: never leave a truncated table behind (CLAUDE.md).
    if os.path.exists(out):
        os.remove(out)
    os.rename(tmp, out)
    print(f"wrote {out}")
    print(f"  {len(types)} component types, {len(all_names)} distinct callback "
          f"names, {len(libcomputer)} computer.* and {len(libcomponent)} "
          f"component.* API names")
    print("  sources: " + ", ".join(f"{k}@{v}" for k, v in sorted(sources.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
