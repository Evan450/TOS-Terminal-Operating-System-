-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: rc.d kernel-tier claims match #SEC C2    ║
-- ║                                                            ║
-- ║  Bug: 20-netfsd.lua shipped declaring user = "_kernel_",   ║
-- ║  copied from 20-fileshare.lua, but was never added to      ║
-- ║  rc.lua's KERNEL_SERVICE_ALLOWLIST. Every boot logged      ║
-- ║  "Refusing kernel-tier service ...: not in C2 allowlist;   ║
-- ║  demoting to user-tier" and the service ran at a tier its  ║
-- ║  own manifest disagreed with.                              ║
-- ║                                                            ║
-- ║  Nothing broke, which is what made it worth pinning: a     ║
-- ║  service whose declared privilege silently differs from    ║
-- ║  its actual one is a lie that only shows up in a log line  ║
-- ║  nobody reads until something else goes wrong.             ║
-- ║                                                            ║
-- ║  The rule: a shipped service either does NOT claim kernel  ║
-- ║  tier, or it is on the allowlist. Never one without the    ║
-- ║  other, in either direction.                               ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_rc_kernel_claim.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_rc_kernel_claim.lua"
local base = here:gsub("[^/\\]*$", "")

local function readFile(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local fh = io.open(p, "r")
    if fh then local s = fh:read("*a"); fh:close(); return s end
  end
end

local function listRcd()
  -- No filesystem module off-box; the manifest is the authoritative list
  -- of what ships, which is exactly the set this rule governs.
  local manifest = readFile("tos/system_manifest.lua")
  if not manifest then return nil end
  local out = {}
  for path in manifest:gmatch('path%s*=%s*"(/etc/rc%.d/[^"]+)"') do
    -- 20-rshd.disabled ships beside 20-rshd.lua and is deliberately not
    -- loadable, so it carries no tier claim to check.
    if path:match("%.lua$") then out[#out + 1] = path end
  end
  table.sort(out)
  return out
end

local rcSource = readFile("tos/kernel/rc.lua")
local services = listRcd()

if not rcSource or not services then
  print("FAIL: could not read rc.lua or the manifest")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- Pull the allowlist straight out of rc.lua, so the test tracks the real
-- table rather than a copy of it that would drift.
local allow = {}
do
  local block = rcSource:match("KERNEL_SERVICE_ALLOWLIST%s*=%s*{(.-)}")
  if block then
    for name in block:gmatch('%["([^"]+)"%]%s*=%s*true') do allow[name] = true end
  end
end

print("=== rc.d kernel-tier claim Tests ===")
print()

local n = 0
for _ in pairs(allow) do n = n + 1 end
test("allowlist was parsed from rc.lua", true, n > 0)
test("...and lists 20-fileshare",        true, allow["20-fileshare"] == true)

print()
print("-- every shipped service --")
local checked = 0
for _, path in ipairs(services) do
  local name = path:match("([^/]+)%.lua$")
  local src  = readFile("etc/rc.d/" .. name .. ".lua")
  if src then
    checked = checked + 1
    -- Match the manifest's own `user = "..."` field, ignoring comments:
    -- the fix for this bug is itself a comment mentioning "_kernel_",
    -- so a naive substring search would report the fixed file as broken.
    local claimed = nil
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
      local code = line:match("^(.-)%-%-") or line
      local u = code:match('user%s*=%s*"([^"]+)"')
      if u then claimed = u end
    end
    local isKernel = (claimed == "_kernel_")
    if isKernel then
      test(name .. " claims kernel tier -> must be allowlisted",
        true, allow[name] == true)
    else
      test(name .. " runs as '" .. tostring(claimed) .. "' (no claim to gate)",
        false, isKernel)
    end
  end
end
test("checked every manifest rc.d entry", #services, checked)

-- The other direction: an allowlist entry for a service that no longer
-- claims kernel tier is stale permission sitting in a security table.
print()
print("-- no stale allowlist entries --")
for name in pairs(allow) do
  local src = readFile("etc/rc.d/" .. name .. ".lua")
  if src then
    local claimed = nil
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
      local code = line:match("^(.-)%-%-") or line
      local u = code:match('user%s*=%s*"([^"]+)"')
      if u then claimed = u end
    end
    test(name .. " is allowlisted and does claim it", "_kernel_", claimed)
  else
    -- 20-rshd ships alongside a .disabled twin; a missing file here would
    -- mean the allowlist names something that is not in the tree at all.
    test(name .. " exists in the tree", true, false)
  end
end

-- The specific regression.
print()
print("-- the netfsd case --")
do
  local src = readFile("etc/rc.d/20-netfsd.lua")
  test("20-netfsd ships", true, src ~= nil)
  if src then
    local claimed = nil
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
      local code = line:match("^(.-)%-%-") or line
      local u = code:match('user%s*=%s*"([^"]+)"')
      if u then claimed = u end
    end
    test("...as root, not _kernel_", "root", claimed)
    test("...so it needs no allowlist entry", nil, allow["20-netfsd"])
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
