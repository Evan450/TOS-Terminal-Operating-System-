-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Power-loss corruption guard         ║
-- ║  - fs.writeFileAtomic: temp-then-replace, no leftover  ║
-- ║  - fs.recoverAtomic: promote orphan temp / drop stale  ║
-- ║  - dirty-bit marker convention (clean vs unsafe)       ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_power_state.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- fs.lua requires("component") but never calls it for path ops (mounts
-- hold proxies passed via fs.init). An empty stub is enough.
package.loaded["component"] = {}

local here = (arg and arg[0]) or "usr/lib/tests/test_power_state.lua"
local base = here:gsub("[^/\\]*$", "")
local fs
for _, p in ipairs({ base .. "../../../tos/kernel/fs.lua", "tos/kernel/fs.lua",
    "TOS-Dev/tos/kernel/fs.lua" }) do
  local chunk = loadfile(p)
  if chunk then fs = chunk(); break end
end
if not fs then
  print("FAIL: could not load fs.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- ── In-memory filesystem proxy (OC component.filesystem shape) ──────
local function newMemFS()
  local files, dirs = {}, { ["/"] = true }
  local handles, hid = {}, 0
  return {
    address = "mem", getLabel = function() return "mem" end,
    spaceTotal = function() return 1 << 20 end,
    spaceUsed  = function() return 0 end,
    exists      = function(p) return files[p] ~= nil or dirs[p] == true end,
    isDirectory = function(p) return dirs[p] == true end,
    list        = function() return {} end,
    size        = function(p) return files[p] and #files[p] or 0 end,
    lastModified = function() return 0 end,
    makeDirectory = function(p) dirs[p] = true; return true end,
    remove = function(p)
      if files[p] ~= nil then files[p] = nil; return true end
      if dirs[p] then dirs[p] = nil; return true end
      return false
    end,
    rename = function(a, b)
      if files[a] == nil then return false end
      files[b] = files[a]; files[a] = nil; return true
    end,
    open = function(p, mode)
      hid = hid + 1
      if mode == "r" then
        if not files[p] then return nil, "not found" end
        handles[hid] = { mode = "r", data = files[p], pos = 1 }
      else
        handles[hid] = { mode = "w", buf = {}, path = p }
      end
      return hid
    end,
    read = function(h, n)
      local H = handles[h]; if not H or H.mode ~= "r" then return nil end
      if H.pos > #H.data then return nil end
      local c = H.data:sub(H.pos, H.pos + n - 1); H.pos = H.pos + #c
      return #c > 0 and c or nil
    end,
    write = function(h, data)
      local H = handles[h]; if not H or H.mode ~= "w" then return false end
      H.buf[#H.buf + 1] = data; return true
    end,
    close = function(h)
      local H = handles[h]; if not H then return end
      if H.mode == "w" then files[H.path] = table.concat(H.buf) end
      handles[h] = nil; return true
    end,
    _files = files,  -- test introspection
  }
end

local mem = newMemFS()
fs.init(mem)

print("=== Power-loss Corruption Guard Tests ===")
print()

-- ── writeFileAtomic ────────────────────────────────────────────────
test("writeFileAtomic returns true", true, (fs.writeFileAtomic("/etc/users.dat", "v1")))
test("content written", "v1", fs.readFile("/etc/users.dat"))
test("no leftover temp after write", false, fs.exists("/etc/users.dat.tos-tmp"))

-- Overwrite must replace atomically, still no temp residue.
fs.writeFileAtomic("/etc/users.dat", "v2-longer-content")
test("content overwritten", "v2-longer-content", fs.readFile("/etc/users.dat"))
test("no temp residue after overwrite", false, fs.exists("/etc/users.dat.tos-tmp"))

-- ── recoverAtomic: orphan temp (crash mid-replace) ─────────────────
-- Simulate a crash AFTER the old file was removed but BEFORE the rename:
-- only the temp survives. Recovery must promote it to the base path.
mem._files["/etc/trust.dat"] = nil
mem._files["/etc/trust.dat.tos-tmp"] = "recovered-trust"
local rec, cleaned = fs.recoverAtomic({ "/etc/trust.dat" })
test("orphan temp recovered (count)", 1, rec)
test("base promoted from temp", "recovered-trust", fs.readFile("/etc/trust.dat"))
test("temp gone after promote", false, fs.exists("/etc/trust.dat.tos-tmp"))

-- ── recoverAtomic: stale temp (base intact) ────────────────────────
-- Crash AFTER a successful replace left a stale temp from a prior op;
-- the base is intact, so the temp must be discarded, not promoted.
mem._files["/etc/tos.cfg"] = "good-config"
mem._files["/etc/tos.cfg.tos-tmp"] = "stale-junk"
local rec2, cleaned2 = fs.recoverAtomic({ "/etc/tos.cfg" })
test("stale temp not recovered", 0, rec2)
test("stale temp cleaned (count)", 1, cleaned2)
test("base left intact", "good-config", fs.readFile("/etc/tos.cfg"))
test("stale temp removed", false, fs.exists("/etc/tos.cfg.tos-tmp"))

-- ── Dirty-bit marker convention ────────────────────────────────────
-- Mirrors the logic inlined in kernel/init.lua (kernel.boot): the first
-- byte of /var/run/pwrstate is 'C' for a clean shutdown; anything else
-- (a 'running' 'R' marker or corrupt bytes) means unsafe; a missing
-- marker is a first boot, NOT an unsafe shutdown.
local function wasUnsafe(marker)
  if type(marker) ~= "string" or #marker == 0 then return false end  -- missing = first boot
  return marker:sub(1, 1) ~= "C"
end
test("clean marker -> safe",        false, wasUnsafe("C\n3\n1700000000"))
test("running marker -> unsafe",    true,  wasUnsafe("R\n3\n1700000000"))
test("corrupt marker -> unsafe",    true,  wasUnsafe("\0garbage"))
test("missing marker -> first boot", false, wasUnsafe(nil))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
