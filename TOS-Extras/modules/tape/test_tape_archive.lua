-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: tape store → restore, the whole round trip   ║
-- ║                                                                ║
-- ║  test_tape_vault covers the READ bounds. Nothing covered the   ║
-- ║  archive round trip, and it was broken for directories:        ║
-- ║                                                                ║
-- ║  `tape store /home/docs` writes each entry's path relative to  ║
-- ║  the base by string-stripping the prefix — "/home/docs/a.txt"  ║
-- ║  minus "/home/docs" leaves "/a.txt", WITH the slash, and the   ║
-- ║  base directory itself leaves "" which the code turns into     ║
-- ║  "/". Restore's #SEC C16 guard then refuses every one of them  ║
-- ║  as an absolute path — and refusing means `rewind and return`, ║
-- ║  so the FIRST entry aborts the whole restore. A directory      ║
-- ║  archive restored exactly nothing, and said so only as         ║
-- ║  "REFUSING absolute/tainted path from tape: /".                ║
-- ║                                                                ║
-- ║  Single files happened to work: fs.split returns "/home/" WITH ║
-- ║  a trailing slash, so the strip leaves "foo.txt" clean. That   ║
-- ║  asymmetry is why it survived — the obvious manual test passes.║
-- ║                                                                ║
-- ║  The guard itself was right to exist. It now STRIPS a leading  ║
-- ║  slash instead of refusing (the join + destBase check is what  ║
-- ║  actually contains the path), so tapes written by the old code ║
-- ║  restore too, while `..`, NUL and any path that escapes        ║
-- ║  destBase are still refused.                                   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/tape/test_tape_archive.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "modules/tape/test_tape_archive.lua"
local base = here:gsub("[^/\\]*$", "")

-- ── An in-memory filesystem with the kernel's own path semantics ──
local function normalize(path)
  if path == nil or path == "" then return "/" end
  if type(path) ~= "string" or path:find("\0", 1, true) then return nil end
  path = path:gsub("\\", "/")
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  local parts = {}
  for seg in path:gmatch("[^/]+") do
    if seg == ".." then parts[#parts] = nil
    elseif seg ~= "." then parts[#parts + 1] = seg end
  end
  return "/" .. table.concat(parts, "/")
end

local function newFS()
  local files, dirs = {}, { ["/"] = true }
  local F = {}
  function F.normalize(p) return normalize(p) end
  function F.join(...) return normalize(table.concat({ ... }, "/")) end
  function F.split(p)
    p = normalize(p); if not p then return nil end
    local dir, name = p:match("^(.-)([^/]+)$")
    if not dir or dir == "" then dir = "/" end
    return dir, name or ""
  end
  function F.exists(p) p = normalize(p); return files[p] ~= nil or dirs[p] == true end
  function F.isDirectory(p) p = normalize(p); return dirs[normalize(p)] == true end
  function F.size(p) local d = files[normalize(p)]; return d and #d or 0 end
  function F.readFile(p) return files[normalize(p)] end
  function F.writeFile(p, data) files[normalize(p)] = data; return true end
  function F.makeDirectory(p)
    p = normalize(p)
    local acc = ""
    for seg in p:gmatch("[^/]+") do acc = acc .. "/" .. seg; dirs[acc] = true end
    dirs["/"] = true
    return true
  end
  function F.list(p)
    p = normalize(p)
    local prefix = (p == "/") and "/" or (p .. "/")
    local seen, out = {}, {}
    local function add(full)
      if full:sub(1, #prefix) ~= prefix or full == p then return end
      local rest = full:sub(#prefix + 1)
      local name = rest:match("^([^/]+)")
      if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
    end
    for f in pairs(files) do add(f) end
    for d in pairs(dirs) do add(d) end
    table.sort(out)
    return out
  end
  F._files, F._dirs = files, dirs
  return F
end

-- ── A writable fake tape ─────────────────────────────────────────
local function fakeDrive(size)
  size = size or (1024 * 1024)
  local d, pos, img = { label = "" }, 0, ""
  local function pad(n) if #img < n then img = img .. string.rep("\0", n - #img) end end
  function d.getSize() return size end
  function d.isReady() return true end
  function d.stop() end
  function d.getLabel() return d.label end
  function d.setLabel(l) d.label = l end
  function d.seek(n)
    local want = pos + n
    if want < 0 then want = 0 elseif want > size then want = size end
    local moved = want - pos; pos = want; return moved
  end
  function d.read(n)
    n = n or 1
    if pos >= size then return "" end
    local avail = math.min(n, size - pos)
    pad(pos + avail)
    local out = img:sub(pos + 1, pos + avail)
    pos = pos + avail
    return out
  end
  function d.write(data)
    if type(data) ~= "string" then data = string.char(data) end
    pad(pos)
    img = img:sub(1, pos) .. data .. img:sub(pos + #data + 1)
    pos = pos + #data
    return true
  end
  function d._image() return img end
  function d._pos() return pos end
  return d
end

-- ── Load the module under sandbox-shaped stubs ───────────────────
local drive = fakeDrive()
local componentStub = {
  list = function(t)
    local done = false
    return function()
      if done or t ~= "tape_drive" then return nil end
      done = true; return "tape-addr-1", "tape_drive"
    end
  end,
  proxy = function() return drive end,
}
local computerStub = { pullSignal = function() end, freeMemory = function() return 0 end,
                       uptime = function() return 0 end }
local realRequire = require
local function stubRequire(name)
  if name == "component" then return componentStub end
  if name == "computer"  then return computerStub  end
  error("require blocked in sandbox: " .. tostring(name), 0)
end

local FS = newFS()
_G.fs = FS

local src
for _, p in ipairs({ base .. "init.lua", "modules/tape/init.lua",
                     "TOS-Extras/modules/tape/init.lua" }) do
  local f = io.open(p, "rb")
  if f then src = f:read("a"); f:close(); break end
end
if not src then print("FAIL: could not read tape/init.lua"); print("*** TESTS FAILED ***"); return false end

local env = setmetatable({ require = stubRequire, fs = FS }, { __index = _G })
local chunk = load(src, "=tape/init.lua", "t", env)
if not chunk then print("FAIL: tape/init.lua does not parse"); print("*** TESTS FAILED ***"); return false end
local mod = chunk()
local tape = mod.commands and mod.commands.tape
if not tape then print("FAIL: no tape command"); print("*** TESTS FAILED ***"); return false end

local out = {}
local function o(s) out[#out + 1] = tostring(s) end
local function reset() out = {} end
local function said(needle)
  for _, l in ipairs(out) do if l:find(needle, 1, true) then return true end end
  return false
end

print("=== tape archive round-trip Tests ===")
print()

-- ── A directory tree ─────────────────────────────────────────────
print("-- store a directory, restore it --")
FS.makeDirectory("/home/docs/sub")
FS.writeFile("/home/docs/a.txt", "alpha")
FS.writeFile("/home/docs/sub/b.txt", "bravo bravo")
FS.writeFile("/home/docs/empty.txt", "")

reset(); tape({ "store", "/home/docs" }, o)
test("store reports it wrote files", true, said("Done:"))
test("...and did not warn the tape was full", false, said("Tape full"))

reset(); tape({ "list" }, o)
test("list sees the archive", true, said("a.txt"))
test("...including the nested file", true, said("b.txt"))

reset(); tape({ "restore", "/restored" }, o)
test("restore did NOT refuse an absolute path", false, said("REFUSING absolute"))
test("restore reports files", true, said("Restored:"))
test("a.txt is back", "alpha", FS.readFile("/restored/a.txt"))
test("the nested file is back", "bravo bravo", FS.readFile("/restored/sub/b.txt"))
test("the empty file is back", "", FS.readFile("/restored/empty.txt"))
test("the subdirectory exists", true, FS.isDirectory("/restored/sub"))
test("no checksum complaints", false, said("CHECKSUM MISMATCH"))

-- ── A single file (the case that always worked) ──────────────────
print()
print("-- store a single file --")
drive = fakeDrive()
reset(); tape({ "store", "/home/docs/a.txt" }, o)
test("single-file store completes", true, said("Done:"))
reset(); tape({ "restore", "/single" }, o)
test("single file restored", "alpha", FS.readFile("/single/a.txt"))

-- ── Append, then restore both ────────────────────────────────────
print()
print("-- append a second tree --")
drive = fakeDrive()
FS.makeDirectory("/home/more")
FS.writeFile("/home/more/c.txt", "charlie")
reset(); tape({ "store", "/home/docs" }, o)
reset(); tape({ "store", "/home/more" }, o)
test("the second store appended", true, said("Appending after existing"))
reset(); tape({ "restore", "/both" }, o)
test("the first tree is there", "alpha", FS.readFile("/both/a.txt"))
test("the second tree is there", "charlie", FS.readFile("/both/c.txt"))

-- ── --overwrite really replaces ──────────────────────────────────
print()
print("-- overwrite --")
reset(); tape({ "store", "/home/more", "--overwrite" }, o)
test("overwrite does not append", false, said("Appending after existing"))
reset(); tape({ "restore", "/over" }, o)
test("only the second tree is present", "charlie", FS.readFile("/over/c.txt"))
test("...and the first is gone", nil, FS.readFile("/over/a.txt"))

-- ── The guard still guards ───────────────────────────────────────
print()
print("-- a hostile tape --")
local function enc16(n) return string.char(math.floor(n / 256) % 256, n % 256) end
local function enc32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
                     math.floor(n / 256) % 256, n % 256)
end
local function sum(s) local t = 0; for i = 1, #s do t = t + s:byte(i) end; return t % 4294967296 end
local function entry(path, data, isDir)
  data = data or ""
  return "TOS\x01" .. string.char(1) .. string.char(isDir and 1 or 0)
    .. enc16(#path) .. path .. enc32(#data) .. enc32(sum(data)) .. data
end
local function loadTape(img)
  drive = fakeDrive()
  drive.write(img)
  drive.seek(-drive._pos())
end

loadTape(entry("../../etc/users.dat", "pwned") .. "TOS\x00")
reset(); tape({ "restore", "/victim" }, o)
test("a .. traversal is refused", true, said("REFUSING traversal"))
test("...and nothing was written", nil, FS.readFile("/etc/users.dat"))

loadTape(entry("/etc/users.dat", "pwned") .. "TOS\x00")
reset(); tape({ "restore", "/victim" }, o)
test("an absolute path is contained, not obeyed", nil, FS.readFile("/etc/users.dat"))
test("...it lands under the destination instead", "pwned", FS.readFile("/victim/etc/users.dat"))

-- A tape written by the OLD code: every path carries a leading slash.
loadTape(entry("/", nil, true) .. entry("/a.txt", "old-format") .. "TOS\x00")
reset(); tape({ "restore", "/legacy" }, o)
test("a tape written by the old code still restores", "old-format", FS.readFile("/legacy/a.txt"))
test("...without refusing anything", false, said("REFUSING"))

-- ── Checksum damage is reported ──────────────────────────────────
print()
print("-- a corrupted entry --")
local good = entry("a.txt", "hello")
local bad = good:sub(1, #good - 5) .. "HELLO"     -- data changed, checksum not
loadTape(bad .. "TOS\x00")
reset(); tape({ "restore", "/corrupt" }, o)
test("a checksum mismatch is reported", true, said("CHECKSUM MISMATCH"))
test("...and the bytes are still written (with the warning)", "HELLO", FS.readFile("/corrupt/a.txt"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
