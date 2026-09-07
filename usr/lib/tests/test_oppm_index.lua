-- ╔═══════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the OPPM index on the `master` branch             ║
-- ║                                                                     ║
-- ║  OPPM hardcodes the branch name `master` when it fetches a repo's   ║
-- ║  programs.cfg, so TOS — whose branches are main/dev/optional-       ║
-- ║  utilities — is invisible to `oppm register` and `oppm install`     ║
-- ║  without a stub branch that exists only to be found.                ║
-- ║                                                                      ║
-- ║  build/oppm/programs.cfg IS that index, and it is published to a     ║
-- ║  branch nothing else in this repo builds or tests. So it is pinned   ║
-- ║  from both ends:                                                     ║
-- ║                                                                       ║
-- ║   1. It must parse the way OPENOS parses it — `load("return "..data)` ║
-- ║      in a restricted env — not merely the way Lua would.              ║
-- ║   2. TOS's OWN programs.cfg reader must accept it. TOS reads OPPM     ║
-- ║      repos as one of its four manifest formats, so the index we       ║
-- ║      publish and the parser we ship have to agree; using our own      ║
-- ║      reader as the checker is the only way that stays true.           ║
-- ║   3. The source path it advertises must name a file that really       ║
-- ║      exists here, or the branch ships an index pointing at nothing.   ║
-- ╚════════════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_oppm_index.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local PREFIXES = { "", "../", "../../", "../../../", "TOS-Dev/" }
local function findUp(rel)
  for _, pre in ipairs(PREFIXES) do
    local s = readAll(pre .. rel); if s then return s, pre end
  end
end

print("=== OPPM index (build/oppm/programs.cfg) ===")
print()

local raw, prefix = findUp("build/oppm/programs.cfg")
test("build/oppm/programs.cfg is readable", raw ~= nil)
if not raw then
  print(string.format("\n%d passed, %d failed", passed, failed + 1))
  print("*** TESTS FAILED ***"); os.exit(1)
end

-- ── 1. Parses the way OpenOS does ───────────────────────────────────
--! OpenOS's serialization.unserialize is `load("return " .. data, "=data",
--! nil, { math = { huge = math.huge } })`. Two things follow that a plain
--! `loadfile` would not catch: the file is a BARE TABLE (no `return`), and
--! it is evaluated with almost no environment, so anything that calls a
--! function at load time is unparseable on a real machine.
local index
do
  local chunk, err = load("return " .. raw, "=data", "t",
    { math = { huge = math.huge } })
  test("parses as OpenOS's serialization.unserialize does", chunk ~= nil)
  if not chunk then print("    " .. tostring(err)) end
  if chunk then
    local ok, t = pcall(chunk)
    test("...and evaluates in a function-less environment", ok and type(t) == "table")
    if ok then index = t end
  end
end
if not index then
  print(string.format("\n%d passed, %d failed", passed, failed + 1))
  print("*** TESTS FAILED ***"); os.exit(1)
end

-- ── 2. Shape ────────────────────────────────────────────────────────
local names = {}
for k in pairs(index) do names[#names + 1] = k end
table.sort(names)
eq("advertises exactly one package", 1, #names)
eq("named 'tos' (what an operator types after `oppm install`)", "tos", names[1])

local entry = index.tos
test("the entry is a table", type(entry) == "table")
test("it has a files table", type(entry.files) == "table")
test("it names an author", type(entry.authors) == "string" and #entry.authors > 0)
test("it has a description", type(entry.description) == "string" and #entry.description > 20)

--! The description is the ONLY text an operator sees in `oppm list`, and
--! the reviewer's point about the repo was that nobody can tell what this
--! is. It must answer "what is this" and "what will it cost me".
test("the description says what TOS is, not just that it is an OS",
  entry.description:lower():find("opencomputers", 1, true) ~= nil)
test("the note warns that this installs the installer, not the OS",
  type(entry.note) == "string" and entry.note:lower():find("bootstrap", 1, true) ~= nil)
test("...and states the hardware it needs",
  entry.note:find("1%.7%.5") ~= nil and entry.note:lower():find("tier 2", 1, true) ~= nil)

-- ── 3. The files table, and the branch layout it implies ────────────
local srcs = {}
for src, dest in pairs(entry.files) do srcs[#srcs + 1] = { src = src, dest = dest } end
eq("ships exactly one file", 1, #srcs)
local one = srcs[1]

--! The `master/` prefix is the BRANCH SEGMENT of the raw URL that OPPM
--! builds, not a directory. Get this wrong and oppm 404s on every install.
test("the source key is rooted at the master branch",
  one.src:sub(1, 7) == "master/")
eq("...and points at the bootstrap", "master/tos/bootstrap.lua", one.src)

--! Destination `/bin` is prefix-relative in OPPM: it lands in /usr/bin,
--! which IS on OpenOS's PATH. `//bin` would mean the absolute /bin, which
--! is not on PATH -- the same trap the wget one-liner documents.
eq("installs to a directory on OpenOS's PATH", "/bin", one.dest)

-- The file the index promises must exist in this tree, since the branch is
-- assembled by copying it. An index pointing at a file nobody ships is the
-- exact failure this whole stub exists to avoid.
local onBranch = one.src:gsub("^master/", "")          -- tos/bootstrap.lua
local leaf     = onBranch:match("([^/]+)$")
test("the file it advertises exists in this repo", findUp(leaf) ~= nil)

-- ── 4. TOS's OWN OPPM reader accepts it ─────────────────────────────
--! The seam. TOS reads OPPM repos as one of four manifest formats, so the
--! index we PUBLISH and the parser we SHIP must agree -- and the only way
--! to keep that true is to check the published bytes with the shipped
--! parser. Driven through pkg's real translator, not a copy of the rules.
do
  package.path = prefix .. "tos/?.lua;" .. prefix .. "tos/?/init.lua;" .. package.path
  package.loaded["computer"]  = { uptime = function() return 0 end,
                                  freeMemory = function() return 1e6 end,
                                  pullSignal = function() end, beep = function() end }
  package.loaded["component"] = { list = function() return function() end end,
                                  isAvailable = function() return false end }

  -- The smallest kernel.fs the manifest loader touches, over a memory disk
  -- holding the real index bytes at the layout a repo checkout would have.
  local files = { ["/repo/programs.cfg"] = raw }
  local dirs  = { ["/repo"] = true, ["/repo/tos"] = true }
  local fs = {}
  function fs.join(a, b) return (a:gsub("/+$", "")) .. "/" .. (b:gsub("^/+", "")) end
  function fs.exists(p) return files[p] ~= nil or dirs[p] == true end
  function fs.isDirectory(p) return dirs[p] == true end
  function fs.readFile(p) return files[p] end
  function fs.writeFile(p, d) files[p] = d; return true end
  function fs.makeDirectory(p) dirs[p] = true; return true end
  function fs.list(p) return {} end
  function fs.remove(p) files[p] = nil; return true end
  function fs.size(p) return files[p] and #files[p] or 0 end
  function fs.normalize(p) return p end

  local okS, serialize = pcall(require, "kernel.serialize")
  local okP, pkg = pcall(require, "kernel.pkg")
  test("kernel.serialize and kernel.pkg load", okS and okP)
  if okS and okP then
    pkg.init({ fs = fs, serialize = serialize })
    -- The package directory is /repo/tos; the index sits in its PARENT,
    -- which is where a real OPPM checkout keeps it.
    test("kernel.pkg exports its manifest reader for this check",
      type(pkg._loadAnyManifest) == "function")
    local m, kind, path = pkg._loadAnyManifest("/repo/tos")
    if m then
      test("TOS's own reader accepts the published index", true)
      eq("...recognised as a programs.cfg index", "/repo/programs.cfg", path)
      eq("...resolving to the install target OPPM would use",
        "/usr/bin/bootstrap.lua", m.files and m.files[1])
      --! [KNOWN GAP] — recorded, not endorsed. TOS resolves the source with
      --! the `master/` segment intact, i.e. it expects a directory literally
      --! named `master` inside the repo. A git CHECKOUT of the master branch
      --! has no such directory: the segment is part of the raw URL OPPM
      --! builds, not part of the tree. So TOS can read this index but would
      --! look for the file one level too deep if someone cloned an OPPM repo
      --! and pointed `pkg install` at it.
      --!
      --! It costs nothing HERE (OPPM fetches by URL, where the key is right)
      --! and the index we publish is correct for OPPM. It is pinned so that
      --! fixing kernel.pkg fails this line and prompts an update rather than
      --! passing silently. See TODO/ROADMAP: "OPPM checkout source paths".
      eq("[known gap] source keeps the branch segment (see the note above)",
        "master/tos/bootstrap.lua",
        m.fileMap and m.fileMap["/usr/bin/bootstrap.lua"])
      test("...carrying the description through",
        type(m.description) == "string" and #m.description > 20)
    else
      test("TOS's own reader accepts the published index -- " .. tostring(kind), false)
    end
  end
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
