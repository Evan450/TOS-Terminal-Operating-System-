-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: TOS still fits the drive the README names    ║
-- ║                                                                ║
-- ║  The README says a Tier 2 drive (2 MB) holds TOS. On           ║
-- ║  2026-10-09 the release was 2,068 KB on an OpenComputers disk  ║
-- ║  (content + 512 B per file) -- past 2,048 KB before a byte of  ║
-- ║  /etc or /var -- and First Boot Setup on a 2 MB drive failed   ║
-- ║  with "Persist failed: not enough space". Nothing measured it: ║
-- ║  the September review's "~353 KB free" was the last number.    ║
-- ║  Minify now drops indentation (1,874 KB). This holds the built ║
-- ║  release to a budget that leaves a Tier 2 drive room to run,   ║
-- ║  so the next growth fails a test instead of a first boot.      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_release_budget.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function size(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local n = h:seek("end"); h:close(); return n
end

print("=== The release fits a Tier 2 drive ===")
print()

local REL = nil
for _, base in ipairs({ "../TOS-Release", "TOS-Release", "../../TOS-Release" }) do
  if size(base .. "/tos/system_manifest.lua") then REL = base break end
end
if not REL then
  print("  SKIP: no built TOS-Release (python tos.py build)")
  print("Results: 0 passed, 0 failed")
  print("All tests passed.")
  return true
end

local h = io.open(REL .. "/tos/system_manifest.lua", "rb")
local src = h:read("*a"); h:close()
local manifest = assert(load(src, "=manifest", "t", {}))()

-- Every file the release ships: the manifest's, plus the five it does not
-- list (it cannot list itself-adjacent boot and licence files usefully).
local paths, seen = {}, {}
local function add(p) if not seen[p] then seen[p] = true; paths[#paths + 1] = p end end
for _, e in ipairs(manifest.files or manifest) do
  if type(e) == "table" and type(e.path) == "string" then add(e.path) end
end
for _, p in ipairs({ "/LICENSE.txt", "/bios.lua", "/bootstrap.lua",
                     "/etc/component_caps.cfg.example", "/etc/kiosk.cfg.example" }) do
  add(p)
end

local FILE_COST = 512           -- OpenComputers charges each file this much
local T2_DRIVE  = 2048 * 1024   -- a Tier 2 hard drive
-- What TOS needs once it runs: First Boot Setup's users.dat and keys, the
-- logs, /var/run, a few configs. 158 KB was free after first boot at 1,874
-- KB; hold at least 128 KB back.
local HEADROOM  = 128 * 1024
local BUDGET    = T2_DRIVE - HEADROOM

local total, files, missing = 0, 0, {}
for _, p in ipairs(paths) do
  local n = size(REL .. p)
  if n then total = total + n + FILE_COST; files = files + 1
  else missing[#missing + 1] = p end
end

test("every shipped file was found (" .. #missing .. " missing" ..
  (#missing > 0 and (": " .. table.concat(missing, ", ")) or "") .. ")", #missing == 0)
test(string.format("the release is %.1f KB on disk in %d files, within %.0f KB "
  .. "(a 2 MB drive less %.0f KB to run in)", total / 1024, files, BUDGET / 1024,
  HEADROOM / 1024), total <= BUDGET)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
