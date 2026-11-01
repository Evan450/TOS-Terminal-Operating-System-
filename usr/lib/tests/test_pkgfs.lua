-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: packages as archives                         ║
-- ║                                                                ║
-- ║  `pkg compact` deletes a package's files and serves them from  ║
-- ║  one archive, so the failure that matters is losing them.      ║
-- ║  Nothing loose may go until every entry has read back byte for ║
-- ║  byte. Real kernel.fs and overlay over a fake disk, with a     ║
-- ║  fake data card.                                               ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkgfs.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 4e6 end,
  totalMemory = function() return 8e6 end, beep = function() end, pullSignal = function() end }
package.loaded["component"] = { list = function() return function() end end,
  isAvailable = function() return false end, proxy = function() end }

local function newDisk(files)
  local px = { address = "disk", files = files, dirs = { ["/"] = true } }
  local handles, nextH = {}, 1
  local function addDirs(p)
    local d = p:match("^(.*)/[^/]*$")
    while d and d ~= "" do px.dirs[d] = true; d = d:match("^(.*)/[^/]*$") end
  end
  for p in pairs(files) do addDirs(p) end
  function px.getLabel() return "disk" end
  function px.exists(p) p = p == "" and "/" or p; return files[p] ~= nil or px.dirs[p] == true end
  function px.isDirectory(p) p = p == "" and "/" or p; return px.dirs[p] == true end
  function px.size(p) return files[p] and #files[p] or 0 end
  function px.lastModified() return 1 end
  function px.spaceTotal() return 4000000 end
  function px.spaceUsed() return 0 end
  function px.isReadOnly() return false end
  function px.makeDirectory(p) addDirs(p); px.dirs[p] = true; return true end
  function px.remove(p)
    if files[p] then files[p] = nil; return true end
    if px.dirs[p] then px.dirs[p] = nil; return true end
    return false
  end
  function px.rename(a, b)
    if px.exists(b) or not files[a] then return false end
    files[b], files[a] = files[a], nil
    return true
  end
  function px.list(p)
    p = p == "" and "/" or p
    local prefix, seen, out = p == "/" and "/" or (p .. "/"), {}, {}
    local function add(path, slash)
      local rest = path:sub(#prefix + 1)
      if path:sub(1, #prefix) == prefix and rest ~= "" then
        local name = rest:match("^[^/]+")
        if not seen[name] then
          seen[name] = true
          out[#out + 1] = name .. ((slash or rest:find("/", 1, true)) and "/" or "")
        end
      end
    end
    for f in pairs(files) do add(f, false) end
    for d in pairs(px.dirs) do if d ~= "/" then add(d, true) end end
    return out
  end
  function px.open(p, mode)
    mode = mode or "r"
    if mode == "r" and not files[p] then return nil, p end
    if mode ~= "r" then
      addDirs(p)
      if mode == "w" or not files[p] then files[p] = "" end
    end
    local id = nextH
    nextH = nextH + 1
    handles[id] = { p = p, pos = 1 }
    return id
  end
  function px.read(id, n)
    local st = handles[id]
    local data = files[st.p]
    if not data or st.pos > #data then return nil end
    local c = data:sub(st.pos, st.pos + n - 1)
    st.pos = st.pos + #c
    return c
  end
  function px.write(id, d)
    if px.failWrites then return nil, "disk full" end
    local st = handles[id]
    files[st.p] = files[st.p] .. d
    return true
  end
  function px.seek(id, whence, off)
    local st = handles[id]
    local base = whence == "set" and 0 or whence == "end" and #files[st.p] or st.pos - 1
    st.pos = base + off + 1
    return st.pos - 1
  end
  function px.close(id) handles[id] = nil; return true end
  return px
end

local BODY_A = string.rep("alpha library line\n", 200)
local BODY_B = string.rep("beta module line\n", 200)
local function world(card)
  for _, m in ipairs({ "kernel.fs", "kernel.pkgfs", "kernel.cowfs" }) do package.loaded[m] = nil end
  local disk = newDisk({
    ["/usr/lib/a.lua"] = BODY_A,
    ["/usr/modules/m/init.lua"] = BODY_B,
    ["/usr/lib/other.lua"] = "someone else's file",
    ["/etc/keep.cfg"] = "config",
    ["/var/pkg/installed/x"] = "state",
  })
  local fs = require("kernel.fs")
  fs.init(disk)
  _G._TOS = { kernel = { getCompress = function() return card end } }
  local pkgfs = require("kernel.pkgfs")
  pkgfs.init({ fs = fs })
  return disk, fs, pkgfs
end
local TARGETS = { "/usr/lib/a.lua", "/usr/modules/m/init.lua" }

print("=== the format ===")
print()
do
  local _, _, pkgfs = world()
  local e = pkgfs.entry("/lib/a.lua", "hi")
  test("an entry is mtar v1", e:sub(1, 3) == "\255\255\1"
    and string.unpack(">I2", e, 4) == 10 and e:sub(6, 15) == "/lib/a.lua"
    and string.unpack(">I8", e, 16) == 2 and e:sub(24) == "hi")
end

print()
print("=== compact ===")
print()
do
  local disk, fs, pkgfs = world()
  local ok, r = pkgfs.compact("demo", TARGETS)
  test("it compacts", ok == true, r)
  test("and says what it saved", type(r) == "table" and r.after < r.before and r.files == 2, r)
  test("the loose files are gone from the disk", disk.files["/usr/lib/a.lua"] == nil
    and disk.files["/usr/modules/m/init.lua"] == nil)
  test("one archive is there", disk.files["/var/pkg/archive/demo.mtar"] ~= nil)
  test("the paths still read", fs.readFile("/usr/lib/a.lua") == BODY_A)
  test("byte for byte", fs.readFile("/usr/modules/m/init.lua") == BODY_B)
  test("listings still show them", (function()
    for _, n in ipairs(fs.list("/usr/lib")) do if n == "a.lua" then return true end end
  end)())
  test("the size is the file's, not the archive's", fs.size("/usr/lib/a.lua") == #BODY_A)
  test("a neighbour in /usr is untouched", fs.readFile("/usr/lib/other.lua") == "someone else's file")
  fs.writeFile("/usr/lib/new.lua", "written after")
  test("/usr still takes writes", fs.readFile("/usr/lib/new.lua") == "written after")
  test("and they land on the real disk", disk.files["/usr/lib/new.lua"] == "written after")
  test("/etc never moved", fs.readFile("/etc/keep.cfg") == "config")
  test("it knows what is compact", pkgfs.has("demo") and pkgfs.list()[1] == "demo")
  test("twice is refused", pkgfs.compact("demo", TARGETS) == nil)
end

print()
print("=== with a data card ===")
print()
do
  local card = {
    pack = function(d) return "TCZ1" .. d:sub(1, 20) .. "|" .. #d, "deflate" end,
    isPacked = function(b) return b:sub(1, 4) == "TCZ1" end,
    unpack = function(b) return b:sub(5, 5) == "a" and BODY_A or BODY_B end,
  }
  local disk, fs, pkgfs = world(card)
  local ok, r = pkgfs.compact("demo", TARGETS)
  test("it compacts, compressed", ok == true and r.packed == true, r)
  test("and reads through the card", fs.readFile("/usr/lib/a.lua") == BODY_A)
  test("the archive really is smaller than one file",
    #disk.files["/var/pkg/archive/demo.mtar"] < #BODY_A)
end

print()
print("=== nothing is lost when it goes wrong ===")
print()
do
  -- A card that cannot give back what it took: the worst case.
  local liar = {
    pack = function() return "TCZ1garbled", "deflate" end,
    isPacked = function(b) return b:sub(1, 4) == "TCZ1" end,
    unpack = function() return "not the same bytes" end,
  }
  local disk, _, pkgfs = world(liar)
  local ok, why = pkgfs.compact("demo", TARGETS)
  test("a read-back that differs refuses", ok == nil and tostring(why):find("read-back", 1, true), why)
  test("the loose files are all still there", disk.files["/usr/lib/a.lua"] == BODY_A
    and disk.files["/usr/modules/m/init.lua"] == BODY_B)
  test("and no archive is left behind", disk.files["/var/pkg/archive/demo.mtar"] == nil
    and not pkgfs.has("demo"))
end
do
  local disk, _, pkgfs = world()
  disk.failWrites = true
  local ok = pkgfs.compact("demo", TARGETS)
  disk.failWrites = false
  test("a full disk refuses", ok == nil)
  test("with the files where they were", disk.files["/usr/lib/a.lua"] == BODY_A)
  test("and no temp file", disk.files["/var/pkg/archive/demo.mtar.tmp"] == nil)
end
do
  local _, _, pkgfs = world()
  local ok, why = pkgfs.compact("demo", { "/usr/lib/nothing-here.lua" })
  test("a missing file refuses", ok == nil and tostring(why):find("cannot read", 1, true), why)
end
do
  local disk, _, pkgfs = world()
  disk.files["/usr/lib/tiny.lua"] = "x"
  local _, why = pkgfs.compact("tiny", { "/usr/lib/tiny.lua" })
  test("no saving, no archive", tostring(why):find("not be smaller", 1, true), why)
  test("and the file stays", disk.files["/usr/lib/tiny.lua"] == "x")
end

print()
print("=== after a reboot ===")
print()
do
  local disk, fs, pkgfs = world()
  pkgfs.compact("demo", TARGETS)
  disk.files["/var/pkg/archive/broken.mtar"] = "this is not an archive"
  package.loaded["kernel.fs"], package.loaded["kernel.pkgfs"] = nil, nil
  local logged = {}
  fs = require("kernel.fs")
  fs.init(disk)
  pkgfs = require("kernel.pkgfs")
  local n = pkgfs.boot({ fs = fs, log = { error = function(_, m) logged[#logged + 1] = m end } })
  test("boot finds the archive", n == 1, n)
  test("and the package is back", fs.readFile("/usr/lib/a.lua") == BODY_A)
  test("a damaged archive costs only itself, and says so", #logged == 1
    and logged[1]:find("broken", 1, true), logged[1])
  test("and is not listed as if it were there", not pkgfs.has("broken") and #pkgfs.list() == 1)
end
do
  local _, fs, pkgfs = world()
  test("with no archive, boot mounts nothing", pkgfs.boot({ fs = fs }) == 0
    and fs.readFile("/usr/lib/a.lua") == BODY_A)
end

print()
print("=== a name left on the disk ===")
print()
do
  -- Before there is an overlay nothing refuses this name.
  local disk, fs, pkgfs = world()
  disk.files["/usr/lib/.cfsdel.a.lua"] = ""
  disk.files["/usr/.cfsdel.modules"] = ""
  pkgfs.compact("demo", TARGETS)
  test("it cannot hide a package that is then compacted", fs.readFile("/usr/lib/a.lua") == BODY_A)
  test("nor can one on a directory above it", fs.readFile("/usr/modules/m/init.lua") == BODY_B)
end

print()
print("=== the disk afterwards ===")
print()
do
  local disk, _, pkgfs = world()
  pkgfs.compact("demo", TARGETS)
  test("a directory it emptied goes, and costs nothing",
    disk.dirs["/usr/modules/m"] == nil and disk.dirs["/usr/modules"] == nil)
  test("one with something else in it stays", disk.dirs["/usr/lib"] == true)
  test("/usr itself stays", disk.dirs["/usr"] == true)
end

print()
print("=== going back ===")
print()
do
  local disk, fs, pkgfs = world()
  pkgfs.compact("demo", TARGETS)
  local ok, err = pkgfs.expand("demo")
  test("it expands", ok == true, err)
  test("the loose files are back on the disk", disk.files["/usr/lib/a.lua"] == BODY_A
    and disk.files["/usr/modules/m/init.lua"] == BODY_B)
  test("the archive is gone", disk.files["/var/pkg/archive/demo.mtar"] == nil and not pkgfs.has("demo"))
  test("and they still read", fs.readFile("/usr/lib/a.lua") == BODY_A)
end
do
  local disk, fs, pkgfs = world()
  pkgfs.compact("demo", TARGETS)
  disk.failWrites = true
  local ok = pkgfs.expand("demo")
  disk.failWrites = false
  test("an expand that cannot write refuses", ok == nil)
  test("and the archive survives it", disk.files["/var/pkg/archive/demo.mtar"] ~= nil
    and fs.readFile("/usr/lib/a.lua") == BODY_A)
end
do
  local disk, fs, pkgfs = world()
  pkgfs.compact("demo", TARGETS)
  fs.writeFile("/usr/lib/a.lua", "edited since")
  fs.remove("/usr/modules/m/init.lua")
  test("a removed file is hidden with a whiteout",
    disk.files["/usr/modules/m/.cfsdel.init.lua"] ~= nil)
  local ok, err = pkgfs.expand("demo")
  test("expand keeps an edit", ok == true and disk.files["/usr/lib/a.lua"] == "edited since", err)
  test("and does not bring back what was removed", disk.files["/usr/modules/m/init.lua"] == nil
    and not fs.exists("/usr/modules/m/init.lua"))
  test("and leaves no whiteout behind", disk.files["/usr/modules/m/.cfsdel.init.lua"] == nil)
  test("and no temp file", disk.files["/usr/lib/a.lua.tmp"] == nil)
end
do
  local disk, fs, pkgfs = world()
  pkgfs.compact("demo", TARGETS)
  pkgfs.drop("demo")
  test("drop forgets it, for uninstall", not fs.exists("/usr/lib/a.lua")
    and disk.files["/var/pkg/archive/demo.mtar"] == nil)
end

print()
print("=== a hostile archive ===")
print()
do
  local disk, fs, pkgfs = world()
  disk.makeDirectory("/var/pkg/archive")
  disk.files["/var/pkg/archive/evil.mtar"] = pkgfs.entry("/../etc/passwd", "x")
  local logged = {}
  local n = pkgfs.boot({ fs = fs, log = { error = function(_, m) logged[#logged + 1] = m end } })
  test("a path that climbs out is refused", n == 0 and logged[1]
    and logged[1]:find("unsafe path", 1, true), logged[1])
end

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
