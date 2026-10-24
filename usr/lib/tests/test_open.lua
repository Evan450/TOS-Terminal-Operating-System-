-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: which program opens a file                 ║
-- ║                                                              ║
-- ║  shell/open.lua ranks every program that could open a file   ║
-- ║  by a fixed rule, and the point of the rule is that it does  ║
-- ║  NOT depend on install order: the first package to claim     ║
-- ║  .txt must not own every text file on the machine. These     ║
-- ║  pin the ladder (the operator, the machine, the package's    ║
-- ║  own format, content markers, "can open", edit), the tie     ║
-- ║  break, that markers are plain prefixes and never patterns,  ║
-- ║  the choices file, and pkg's validation of `handles` --      ║
-- ║  including against the REAL calc and write manifests.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_open.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local OP = dofile("tos/shell/open.lua")

-- Manifests as pkg keeps them: calc and write as they ship, plus two
-- made-up ones to probe the rules.
local MANIFESTS = {
  calc = { name = "calc", commands = { calc = "/usr/modules/calc/init.lua" },
           handles = { { ext = { "calc" }, as = "native" }, { ext = { "csv" } } } },
  write = { name = "write", commands = { write = "/usr/modules/write/init.lua" },
            handles = { { ext = { "wri" }, as = "native" },
                        { ext = { "txt", "doc", "text" },
                          markers = { ".title ", ".page", ".center", ".left", ".color ", ".nf" } } } },
  -- A greedy package claiming text: installed FIRST, it must still lose
  -- plain .txt to nothing special and lose a write document to write.
  aardvark = { name = "aardvark", commands = { aard = "/x" },
               handles = { { ext = { "txt", "csv", "log", "md", "cfg", "ini", "doc", "rtf" } } } },
  off = { name = "off", enabled = false, commands = { off = "/y" },
          handles = { { ext = { "calc" }, as = "native" } } },
}
local decls = OP.declarations({ manifests = MANIFESTS })

local function best(path, head, extra)
  local opts = { decls = decls, head = head }
  for k, v in pairs(extra or {}) do opts[k] = v end
  local b = OP.best(path, opts)
  return b and b.cmd, b
end

print("=== The ladder ===")
test(".calc is calc's own format", best("/h/budget.calc", "TOSCALC2") == "calc")
test("a disabled package claims nothing", select(2, best("/h/budget.calc", "x")).score == OP.SCORE.native
  and #OP.rank("/h/b.calc", { decls = decls, head = "x" }) == 2)
test(".csv: calc (it opens CSV) over edit", best("/h/data.csv", "a,b") == "calc")
do
  local _, b = best("/h/data.csv", "a,b")
  test("...and a tie with the greedy package goes to the more specific claim", b.pkg == "calc", b.pkg)
end
test("a plain .txt stays edit's (40): the greedy package's 'can open' (20) does not take it",
  best("/h/notes.txt", "hello") == "edit")
test("...but the greedy package does get a type nobody owns, like .rtf",
  best("/h/notes.rtf", "x") == "aard")
test("a .txt that IS a write document goes to write (60: content over name)",
  best("/h/report.txt", "Intro\n.title Report\nbody") == "write")
test("markers are line PREFIXES: in the middle of a line they do nothing",
  best("/h/report.txt", "this line mentions .title in passing") == "edit")
test("markers are not patterns: a '.' in one matches only a '.'",
  best("/h/r.txt", "Xtitle Report") == "edit")
test(".wri is write's own", best("/h/old.wri", "x") == "write")
test("an unknown type that is text: edit", best("/h/x.lua", "print(1)") == "edit")
test("a binary file with no claim: nothing", best("/h/blob.bin", "MZ\0\0") == nil)
test("no extension: edit for text", best("/h/README", "hi") == "edit")

do
  local user = OP.parseDefaults("csv aard\n")
  local system = OP.parseDefaults("csv edit\ntxt write\n")
  test("the machine's choice beats every package (90)", best("/h/d.txt", "x", { system = system }) == "write")
  test("the user's beats the machine's (100)", best("/h/d.csv", "x", { system = system, user = user }) == "aard")
  local _, b = best("/h/d.csv", "x", { system = system, user = user })
  test("and says whose choice it was", b.why:find("your choice", 1, true) ~= nil, b.why)
  test("a choice naming a program with no claim still counts",
    best("/h/x.log", "x", { user = OP.parseDefaults("log write") }) == "write")
end

do
  -- The point of the exercise: the same packages in any order rank the
  -- same. declarations() sorts, and rank() breaks ties by rule.
  local orders = { { "calc", "write", "aardvark" }, { "aardvark", "write", "calc" } }
  local results = {}
  for i, order in ipairs(orders) do
    local m = {}
    for _, name in ipairs(order) do m[name] = MANIFESTS[name] end
    local r = OP.rank("/h/data.csv", { decls = OP.declarations({ manifests = m }), head = "a" })
    local names = {}
    for _, c in ipairs(r) do names[#names + 1] = c.cmd end
    results[i] = table.concat(names, ",")
  end
  test("install order changes nothing", results[1] == results[2], results[1] .. " vs " .. results[2])
end

print()
print("=== edit's suggestion ===")
test("a write document in edit: suggest write",
  (OP.suggestion("/h/r.txt", { decls = decls, head = ".page\nx" }) or {}).cmd == "write")
test("plain Lua in edit: no suggestion",
  OP.suggestion("/h/x.lua", { decls = decls, head = "x" }) == nil)
test("hints off: no suggestion", OP.suggestion("/h/r.txt",
  { decls = decls, head = ".page", user = OP.parseDefaults("hints off") }) == nil)

print()
print("=== The choices file ===")
do
  local t = OP.parseDefaults(".csv calc\nTXT write\nnonsense line here\nhints off\n")
  test("an entry, with or without the dot, case aside", t.ext.csv == "calc" and t.ext.txt == "write")
  test("a line that does not parse is skipped, not fatal", t.ext.nonsense == nil)
  test("hints off is read", t.hints == false)
  local back = OP.parseDefaults(OP.serializeDefaults(t))
  test("it round-trips", back.ext.csv == "calc" and back.ext.txt == "write" and back.hints == false)
  test("a missing file is no choices, hints on", OP.parseDefaults(nil).hints == true)
end

print()
print("=== Declarations are checked again on the way in ===")
test("a marker with a control character is dropped",
  OP.cleanDecl("x", { commands = { x = "/x" } }, { ext = { "txt" }, markers = { "\27[" } }) == nil)
test("cmd must be one of the package's commands",
  OP.cleanDecl("x", { commands = { x = "/x" } }, { ext = { "txt" }, cmd = "rm" }) == nil)
test("with two commands, cmd must be named",
  OP.cleanDecl("x", { commands = { a = "/a", b = "/b" } }, { ext = { "txt" } }) == nil)
test("an extension with a dot or slash is not one",
  OP.cleanDecl("x", { commands = { x = "/x" } }, { ext = { "../etc" } }) == nil)
test("quote() wraps a path with a space", OP.quote("/home/a b.txt") == '"/home/a b.txt"')

print()
print("=== pkg validates `handles` ===")
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.process"] = { currentSession = function() return nil end, yieldCooperative = function() end }
package.loaded["kernel.sandbox"] = { build = function() return {} end }
package.loaded["kernel.users"] = { TIER = { ADMIN = 2, ROOT = 3 }, currentSession = function() return nil end }
package.loaded["kernel.sha256"] = dofile("tos/kernel/sha256.lua")
package.loaded["kernel.serialize"] = dofile("tos/kernel/serialize.lua")
local okP, pkg = pcall(dofile, "tos/kernel/pkg.lua")
if not okP then
  test("kernel/pkg.lua loads off-box", false, pkg)
else
  local V = pkg._validateManifest
  local function base(extra)
    local m = { name = "t", version = "1.0.0", kind = "command", files = { "/usr/modules/t/init.lua" },
                commands = { t = "/usr/modules/t/init.lua" } }
    for k, v in pairs(extra) do m[k] = v end
    return m
  end
  test("a good declaration passes", (V(base({ handles = { { ext = { "tx" }, as = "native" } } }))))
  test("as must be native or open", not V(base({ handles = { { ext = { "tx" }, as = "always" } } })))
  test("markers make it not a native format", not V(base({ handles = { { ext = { "tx" }, as = "native", markers = { ".x" } } } })))
  test("a one-character marker is refused", not V(base({ handles = { { ext = { "tx" }, markers = { "." } } } })))
  test("a marker with a newline is refused", not V(base({ handles = { { ext = { "tx" }, markers = { ".x\n" } } } })))
  test("cmd must be the package's", not V(base({ handles = { { ext = { "tx" }, cmd = "rm" } } })))
  test("more than 8 entries is refused", not V(base({ handles = { {ext={"a"}},{ext={"b"}},{ext={"c"}},
    {ext={"d"}},{ext={"e"}},{ext={"f"}},{ext={"g"}},{ext={"h"}},{ext={"i"}} } })))
  -- The real manifests, as they ship.
  local function shipped(name)
    for _, root in ipairs({ "../TOS-Extras/modules/", "TOS-Extras/modules/" }) do
      local chunk = loadfile(root .. name .. "/package.lua")
      if chunk then return chunk() end
    end
  end
  for _, name in ipairs({ "calc", "write" }) do
    local m = shipped(name)
    if m then
      local ok, why = V(m)
      test(name .. "'s shipped manifest passes with its `handles`", ok, why)
      test(name .. " declares what it opens", type(m.handles) == "table" and #m.handles > 0)
    else
      print("  SKIP: " .. name .. "'s manifest not found beside TOS-Dev")
    end
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
print("All tests passed.")
