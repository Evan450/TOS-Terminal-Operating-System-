-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `jbod create`, the command itself            ║
-- ║                                                                ║
-- ║  Its mount check was s:sub(1, 6) == "/mnt/", six characters    ║
-- ║  against five, so it could never match: every pool was refused ║
-- ║  with "must be under /mnt/ (e.g. jbod create /mnt/pool ...)",  ║
-- ║  an example of what it had just refused. test_jbod.lua proved  ║
-- ║  the pool and never called the command, so the feature `man    ║
-- ║  jbod` opens with had not worked since that check was added.   ║
-- ║  This runs the real admin.lua, and pins that the check still   ║
-- ║  refuses what it is there to refuse.                           ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_jbod_create.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;TOS-Dev/tos/?.lua;TOS-Dev/tos/?/init.lua;" .. package.path

local DISKS = { ["aaaa0000-1"] = "data", ["bbbb0000-2"] = "more", ["boot0000-3"] = "system" }
package.loaded["computer"] = {
  uptime = function() return 10 end,
  totalMemory = function() return 2048 * 1024 end,
  freeMemory = function() return 1024 * 1024 end,
}
package.loaded["component"] = {
  list = function(kind)
    local names = {}
    if kind == "filesystem" then
      for addr in pairs(DISKS) do names[#names + 1] = addr end
    end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
  end,
  proxy = function(addr)
    return { address = addr, getLabel = function() return DISKS[addr] end }
  end,
}

local function run(...)
  local mounted, saved, dirs = {}, nil, {}
  local jb = {
    makePool = function(members) return { members = members } end,
    loadConfig = function() return nil end,
    saveConfig = function(_, cfg) saved = cfg end,
  }
  local F = {
    normalize = function(p) return (p:gsub("/+", "/")) end,
    exists = function() return false end,
    makeDirectory = function(p) dirs[p] = true; return true end,
    mount = function(path, proxy) mounted[path] = proxy; return true end,
  }
  local S = {
    T = setmetatable({}, { __index = function(_, k) return k end }),
    F = F, K = { getJBOD = function() return jb end },
  }
  local deps = {
    rp = function(p) return p end,
    rootOnly = function() return true end, adminOnly = function() return true end,
    promptInput = function() return nil end,
    confirm = function() return false end, confirmTyped = function() return false end,
  }
  local C = {}
  assert(loadfile("tos/shell/panels/commands/admin.lua"))()(C, S, deps)
  local out = {}
  C.jbod({ ... }, function(line) out[#out + 1] = tostring(line) end)
  return { mounted = mounted, saved = saved, dirs = dirs, S = S,
           text = table.concat(out, "\n") }
end

_G._TOS = { bootAddr = "boot0000-3" }

print("=== the check lets a pool through ===")
print()
do
  local r = run("create", "/mnt/pool", "aaaa", "bbbb")
  test("a pool under /mnt/ is made", r.mounted["/mnt/pool"] ~= nil, r.text)
  test("of both disks", r.mounted["/mnt/pool"] and #r.mounted["/mnt/pool"].members == 2)
  test("and it is remembered for the next boot", r.saved and r.saved.pools[1].mount == "/mnt/pool"
    and #r.saved.pools[1].members == 2)
  test("the mount point is a real directory", r.dirs["/mnt/pool"] == true)
  test("and the shell says so", r.S.lastOut and tostring(r.S.lastOut[1]):find("2 disks", 1, true))
  test("a label names a disk too", run("create", "/mnt/p2", "data", "more").mounted["/mnt/p2"] ~= nil)
  test("a path with no leading slash is taken as one",
    run("create", "mnt/p3", "data").mounted["/mnt/p3"] ~= nil)
end

print()
print("=== and still refuses what it is there to refuse ===")
print()
for _, path in ipairs({ "/etc/pool", "/mntx/pool", "/mnt", "/mnt/", "/usr/pool" }) do
  local r = run("create", path, "aaaa", "bbbb")
  test("refused: " .. path, next(r.mounted) == nil and r.text:find("must be under", 1, true), r.text)
end
do
  local r = run("create", "/mnt/pool", "boot", "aaaa")
  test("the boot disk cannot join a pool", next(r.mounted) == nil
    and r.text:find("Refusing to pool the BOOT disk", 1, true), r.text)
  test("a disk that is not there is named", run("create", "/mnt/pool", "nope").text
    :find("no filesystem matches", 1, true) ~= nil)
end

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
