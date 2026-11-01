-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the copy-on-write overlay                    ║
-- ║                                                                ║
-- ║  Two filesystems as one: reads fall through, every write lands ║
-- ║  on upper, and lower is never touched. The hazard is the       ║
-- ║  whiteout, a file that hides another, so a name that could     ║
-- ║  forge one has to be refused. Two in-memory proxies shaped     ║
-- ║  like OC's filesystem component, including its refusal to      ║
-- ║  rename over an existing file.                                 ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cowfs.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path
local cowfs = require("kernel.cowfs")

local function disk(files, dirs, label)
  local px = { address = label, files = files, dirs = dirs or {}, writes = 0 }
  px.dirs["/"] = true
  local handles, nextH = {}, 1
  local function isDir(p) return px.dirs[p] == true end
  function px.exists(p) return files[p] ~= nil or isDir(p) end
  function px.isDirectory(p) return isDir(p) end
  function px.size(p) return files[p] and #files[p] or 0 end
  function px.lastModified() return 1000 end
  function px.spaceTotal() return 1000000 end
  function px.spaceUsed() return 0 end
  function px.makeDirectory(p) px.dirs[p] = true; px.writes = px.writes + 1; return true end
  function px.remove(p)
    px.writes = px.writes + 1
    if files[p] then files[p] = nil; return true end
    if isDir(p) then px.dirs[p] = nil; return true end
    return false
  end
  function px.rename(a, b)
    if px.exists(b) or not files[a] then return false end
    files[b], files[a] = files[a], nil
    px.writes = px.writes + 1
    return true
  end
  function px.list(p)
    local out, prefix = {}, p == "/" and "/" or (p .. "/")
    local seen = {}
    local function add(path, slash)
      local rest = path:sub(#prefix + 1)
      if path:sub(1, #prefix) == prefix and rest ~= "" then
        local name = rest:match("^[^/]+")
        local nested = rest:find("/", 1, true) ~= nil
        local e = name .. ((slash or nested) and "/" or "")
        if not seen[name] then seen[name] = true; out[#out + 1] = e end
      end
    end
    for f in pairs(files) do add(f, false) end
    for d in pairs(px.dirs) do if d ~= "/" then add(d, true) end end
    return out
  end
  function px.open(p, mode)
    if mode == "r" and not files[p] then return nil, p end
    if mode ~= "r" then
      px.writes = px.writes + 1
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
    if st.pos > #data then return nil end
    local c = data:sub(st.pos, st.pos + n - 1)
    st.pos = st.pos + #c
    return c
  end
  function px.write(id, d)
    local st = handles[id]
    files[st.p] = files[st.p] .. d
    return true
  end
  function px.seek(id, _, off) handles[id].pos = off + 1; return off end
  function px.close(id) handles[id] = nil; return true end
  return px
end

local function read(px, p)
  local h = px.open(p, "r")
  if not h then return nil end
  local parts = {}
  while true do
    local c = px.read(h, 4096)
    if not c then break end
    parts[#parts + 1] = c
  end
  px.close(h)
  return table.concat(parts)
end
local function write(px, p, text, mode)
  local h, err = px.open(p, mode or "w")
  if not h then return nil, err end
  px.write(h, text)
  px.close(h)
  return true
end
local function has(list, name)
  for _, n in ipairs(list or {}) do if n == name or n == name .. "/" then return true end end
  return false
end
local function fresh()
  local lower = disk({ ["/base.txt"] = "from lower", ["/lib/a.lua"] = "A", ["/lib/b.lua"] = "B" },
    { ["/lib"] = true }, "lower")
  local upper = disk({}, {}, "upper")
  return lower, upper, cowfs.new(lower, upper)
end

print("=== reads fall through ===")
print()
do
  local lower, upper, ov = fresh()
  test("a lower file is there", ov.exists("/base.txt"))
  test("and reads", read(ov, "/base.txt") == "from lower")
  test("its size is lower's", ov.size("/base.txt") == 10)
  test("a lower directory is a directory", ov.isDirectory("/lib"))
  test("a listing shows it", has(ov.list("/"), "lib") and has(ov.list("/"), "base.txt"))
  test("a missing file is missing", not ov.exists("/nope"))
  test("and does not open", ov.open("/nope", "r") == nil)
  test("reading wrote nothing", lower.writes == 0 and upper.writes == 0)
end

print()
print("=== writes land on upper ===")
print()
do
  local lower, upper, ov = fresh()
  write(ov, "/new.txt", "fresh")
  test("a new file is readable", read(ov, "/new.txt") == "fresh")
  test("it is on upper", upper.files["/new.txt"] == "fresh")
  test("and not on lower", lower.files["/new.txt"] == nil)

  write(ov, "/base.txt", "changed")
  test("changing a lower file shows the change", read(ov, "/base.txt") == "changed")
  test("and lower still has the original", lower.files["/base.txt"] == "from lower")

  write(ov, "/lib/a.lua", "++", "a")
  test("append brings the file up first", read(ov, "/lib/a.lua") == "A++", read(ov, "/lib/a.lua"))
  test("lower is not touched by it", lower.files["/lib/a.lua"] == "A" and lower.writes == 0)
  test("a write under a lower-only directory makes it on upper", upper.dirs["/lib"] == true)
  test("a listing merges both, once each", #ov.list("/lib") == 2, #ov.list("/lib"))
end

print()
print("=== removing ===")
print()
do
  local lower, upper, ov = fresh()
  test("a lower file can be removed", ov.remove("/base.txt") == true)
  test("it is gone from the overlay", not ov.exists("/base.txt") and read(ov, "/base.txt") == nil)
  test("from the listing too", not has(ov.list("/"), "base.txt"))
  test("lower still has it", lower.files["/base.txt"] == "from lower")
  test("the whiteout never shows", not has(ov.list("/"), cowfs.WHITEOUT .. "base.txt"))

  write(ov, "/base.txt", "again")
  test("writing it again brings it back", read(ov, "/base.txt") == "again")
  test("and the whiteout is gone", upper.files["/" .. cowfs.WHITEOUT .. "base.txt"] == nil)

  test("a directory with files in it is refused", ov.remove("/lib") ~= true)
  ov.remove("/lib/a.lua"); ov.remove("/lib/b.lua")
  test("emptied, it goes", ov.remove("/lib") == true and not ov.exists("/lib"))
  test("and hides what was under it", not ov.exists("/lib/a.lua") and lower.files["/lib/a.lua"] == "A")
end

print()
print("=== the whiteout hazard ===")
print()
do
  local lower, upper, ov = fresh()
  local forged = "/" .. cowfs.WHITEOUT .. "base.txt"
  test("a whiteout cannot be created by name", ov.open(forged, "w") == nil)
  test("so the file it would hide is still there", ov.exists("/base.txt"))
  test("nor by makeDirectory", ov.makeDirectory(forged) ~= true and ov.exists("/base.txt"))
  write(ov, "/plain.txt", "x")
  test("nor by rename", ov.rename("/plain.txt", forged) ~= true and ov.exists("/base.txt"))
  test("nor through a directory of that name",
    ov.open("/" .. cowfs.WHITEOUT .. "d/x", "w") == nil)
  test("a read of one finds nothing", ov.open(forged, "r") == nil and not ov.exists(forged))

  -- On lower it is an ordinary file, and it hides nothing.
  local low2 = disk({ ["/.cfsdel.x"] = "just a file", ["/x"] = "real" }, {}, "low")
  local ov2 = cowfs.new(low2, disk({}, {}, "up"))
  test("a lower file of that name hides nothing", read(ov2, "/x") == "real")
end

print()
print("=== rename ===")
print()
do
  local lower, upper, ov = fresh()
  test("a lower file can be renamed", ov.rename("/base.txt", "/moved.txt") == true)
  test("it is at the new name", read(ov, "/moved.txt") == "from lower")
  test("and not at the old", not ov.exists("/base.txt"))
  test("lower did not change", lower.files["/base.txt"] == "from lower")
  test("onto something that exists is refused, as OC does", ov.rename("/moved.txt", "/lib/a.lua") ~= true)
  test("a lower directory is refused with a reason",
    select(2, ov.rename("/lib", "/lib2")) ~= nil)
end

print()
print("=== going back ===")
print()
do
  local lower, upper, ov = fresh()
  write(ov, "/base.txt", "changed")
  write(ov, "/new.txt", "added")
  ov.remove("/lib/a.lua")
  local ch = ov.changes()
  local seen = {}
  for _, c in ipairs(ch) do seen[c.path] = c.removed and "removed" or "changed" end
  test("it can say what changed", seen["/base.txt"] == "changed" and seen["/new.txt"] == "changed")
  test("and what it hides", seen["/lib/a.lua"] == "removed", seen["/lib/a.lua"])
  cowfs.wipe(upper)
  test("wiped, the lower file is back", read(ov, "/base.txt") == "from lower")
  test("the removed one too", read(ov, "/lib/a.lua") == "A")
  test("and the new one is gone", not ov.exists("/new.txt"))
end

print()
print("=== a handle is a handle ===")
print()
do
  local _, _, ov = fresh()
  test("a bad handle is an error, not a crash", ov.read(99, 10) == nil)
  local h = ov.open("/base.txt", "r")
  test("open handles are counted", ov.openHandles() == 1)
  ov.close(h)
  test("and closed", ov.openHandles() == 0)
end

print()
print("=== the root, at boot ===")
print()
local function machine(cfg, readOnly)
  local lower = disk({ ["/base.txt"] = "from lower", ["/tos/kernel/k.lua"] = "kernel" },
    { ["/etc"] = true, ["/tos"] = true, ["/tos/kernel"] = true }, "aaaaaaaa-1111")
  if cfg then lower.files[cowfs.CONFIG] = cfg end
  lower.isReadOnly = function() return readOnly == true end
  lower.getLabel = function() return "system" end
  local scratch = disk({ ["/mine.txt"] = "not the layer's" }, {}, "bbbbbbbb-2222")
  return lower, scratch, function(addr) return addr == "bbbbbbbb-2222" and scratch or nil end
end
do
  local lower, _, proxyOf = machine(nil)
  test("no config and no choice is no overlay", cowfs.boot(lower, nil, proxyOf) == nil)
end
do
  local lower, scratch, proxyOf = machine("disk=bbbbbbbb-2222\n")
  local root, st = cowfs.boot(lower, nil, proxyOf)
  test("the config names the disk", root ~= nil and st.disk == "bbbbbbbb-2222" and st.reset == false)
  test("the root keeps the boot disk's address", root.address == "aaaaaaaa-1111")
  test("and its label", root.getLabel() == "system")
  test("and is the shape fs and hal look for", root.type == "filesystem")
  write(root, "/new.txt", "kept")
  test("a write lands in the layer", scratch.files["/tos-overlay/aaaaaaaa/new.txt"] == "kept")
  test("not on the real disk", lower.files["/new.txt"] == nil)
  test("nothing else on the disk is touched", scratch.files["/mine.txt"] == "not the layer's")
  root.remove("/base.txt")
  test("the real file is still there", lower.files["/base.txt"] == "from lower")

  local again = cowfs.boot(lower, nil, proxyOf)
  test("the layer survives a reboot", read(again, "/new.txt") == "kept")
  test("and so does a removal", not again.exists("/base.txt"))
end
do
  local lower, scratch, proxyOf = machine("disk=bbbbbbbb-2222\nreset=1\n")
  local root, st = cowfs.boot(lower, nil, proxyOf)
  test("reset is read", st.reset == true)
  write(root, "/new.txt", "gone next boot")
  root.remove("/base.txt")
  local again = cowfs.boot(lower, nil, proxyOf)
  test("reset forgets a write", not again.exists("/new.txt"))
  test("and a removal", read(again, "/base.txt") == "from lower")
  test("and nothing else on that disk", scratch.files["/mine.txt"] == "not the layer's")
end
do
  local lower, _, proxyOf = machine("disk=bbbbbbbb-2222\n")
  local root, st = cowfs.boot(lower, nil, proxyOf)
  write(root, "/new.txt", "x")
  test("drop asks for the next boot", cowfs.drop(st) == true)
  test("and leaves this one alone", read(root, "/new.txt") == "x")
  local again, st2 = cowfs.boot(lower, nil, proxyOf)
  test("the layer goes once", not again.exists("/new.txt"))
  write(again, "/later.txt", "y")
  local third = cowfs.boot(lower, nil, proxyOf)
  test("and only once", read(third, "/later.txt") == "y" and st2.reset == false)
end
do
  local lower, _, proxyOf = machine("disk=cccccccc-3333\n")
  local root, st = cowfs.boot(lower, nil, proxyOf)
  test("a disk that is gone boots on the real root", root == nil)
  test("and says which, and whether it was a reset", st.missing == "cccccccc-3333" and st.reset == false)
end
do
  local lower, _, proxyOf = machine(nil, true)
  local root = cowfs.boot(lower, "bbbbbbbb-2222", proxyOf)
  test("the read-only offer needs no config", root ~= nil)
  test("a read-only disk runs writable", root.isReadOnly() == false and write(root, "/etc/users.dat", "x"))
  test("and the disk was never written", lower.writes == 0)
end
do
  test("a config is parsed, not run", cowfs.parseConfig("disk=abc-1\nreset=1\n") == "abc-1"
    and select(2, cowfs.parseConfig("disk=abc-1\n")) == false)
  test("rubbish names no disk", cowfs.parseConfig("os.execute('x')") == nil
    and cowfs.parseConfig(nil) == nil)
  local lower = machine(nil)
  test("a config can be saved", cowfs.saveConfig(lower, "bbbb", true) == true)
  test("and read back", cowfs.parseConfig(lower.files[cowfs.CONFIG]) == "bbbb"
    and select(2, cowfs.parseConfig(lower.files[cowfs.CONFIG])) == true)
  test("over an old one, with no temp file left", cowfs.saveConfig(lower, "cccc") == true
    and cowfs.parseConfig(lower.files[cowfs.CONFIG]) == "cccc"
    and lower.files[cowfs.CONFIG .. ".tmp"] == nil)
end

print()
print("=== merge ===")
print()
do
  local lower, _, proxyOf = machine("disk=bbbbbbbb-2222\n")
  local root, st = cowfs.boot(lower, nil, proxyOf)
  write(root, "/base.txt", "changed")
  write(root, "/lib/new.lua", "fresh")
  root.remove("/tos/kernel/k.lua")
  local n = cowfs.merge(st)
  test("every change is counted", n == 3, n)
  test("a change reaches the real disk", lower.files["/base.txt"] == "changed")
  test("a new file, directory and all", lower.files["/lib/new.lua"] == "fresh")
  test("and a removal", lower.files["/tos/kernel/k.lua"] == nil)
  test("no temp file", lower.files["/base.txt.tmp"] == nil)
end
do
  local lower, _, proxyOf = machine("disk=bbbbbbbb-2222\n")
  local root, st = cowfs.boot(lower, nil, proxyOf)
  write(root, "/base.txt", "changed")
  local realWrite = lower.write
  lower.write = function() return nil, "disk full" end
  local n, err = cowfs.merge(st)
  lower.write = realWrite
  test("a merge that cannot write says so", n == nil and tostring(err):find("disk full", 1, true), err)
  test("and leaves the real file", lower.files["/base.txt"] == "from lower")
  test("and no temp file", lower.files["/base.txt.tmp"] == nil)
  test("and the change where it was", read(root, "/base.txt") == "changed")
  test("so it can be run again", cowfs.merge(st) == 1 and lower.files["/base.txt"] == "changed")
end

print()
print("=== the layer is never mounted ===")
print()
do
  --! Whoever can write the layer can shadow /tos/kernel, and a disk at /mnt is
  --! one a user can write to. Read from the source, because both refusals sit
  --! in modules this test has no kernel to run.
  local function source(rel)
    for _, base in ipairs({ "", "TOS-Dev/" }) do
      local h = io.open(base .. rel, "rb")
      if h then local s = h:read("a"); h:close(); return s end
    end
  end
  local dm = source("tos/kernel/diskmount.lua")
  test("diskmount passes over it", dm:find('if addr == layerAddr then return nil', 1, true) ~= nil)
  local kern = source("tos/kernel/init.lua")
  test("and is told which it is", kern:find("layerAddr = overlay and overlay.disk", 1, true) ~= nil)
  local sf = source("tos/kernel/securefs.lua")
  test("securefs.mount refuses it", sf:find("proxy.address == overlay.disk", 1, true) ~= nil)
  local cmd = source("tos/shell/panels/commands.lua")
  test("the command is root's", cmd:find('overlay  = { category = "extras", tier = 3', 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
