-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the floor is closed under require            ║
-- ║                                                                ║
-- ║  SELF-STRIPPING's first step. The floor is what TOS has to     ║
-- ║  keep if it strips itself: Safe Mode must boot and the         ║
-- ║  emergency terminal must exist, whatever else goes. It is      ║
-- ║  marked `floor = true` in the manifest, and a hand-kept list   ║
-- ║  drifts and tells you on the boot where you needed it, so      ║
-- ║  this test is the feature: nothing in the floor may need       ║
-- ║  anything outside it.                                          ║
-- ║                                                                ║
-- ║  A require inside pcall is optional and does not count. That   ║
-- ║  it boots is build/floorboot.py's half, which needs a machine. ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_manifest_floor.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function read(p)
  local h = io.open(p, "rb")
  if not h then return nil end
  local s = h:read("a"); h:close()
  return (s:gsub("\r\n", "\n"))
end

local entries = assert(load(assert(read("tos/system_manifest.lua")), "=manifest", "t", {}))()
local files = entries.files or entries
local inManifest, inFloor, floorList = {}, {}, {}
for _, e in ipairs(files) do
  if type(e) == "table" and e.path then
    inManifest[e.path] = e
    if e.floor then inFloor[e.path] = true; floorList[#floorList + 1] = e.path end
  end
end

local function toPath(mod)
  local base = mod:gsub("%.", "/")
  for _, cand in ipairs({ "/tos/" .. base .. ".lua", "/tos/" .. base .. "/init.lua" }) do
    if inManifest[cand] then return cand end
  end
end

-- Comments out, so a require in prose does not count.
local function strip(src)
  src = src:gsub("%-%-%[%[.-%]%]", "")
  return (src:gsub("%-%-[^\n]*", ""))
end

print("=== the floor is marked ===")
test("it has files", #floorList > 0, #floorList)
test("the boot loader is in it", inFloor["/init.lua"])
test("so is the kernel", inFloor["/tos/kernel/init.lua"])
test("and the command line", inFloor["/tos/shell/cli.lua"])
test("and login", inFloor["/tos/shell/login.lua"])
for path, e in pairs(inManifest) do
  if e.critical and not inFloor[path] then
    test("critical means floor: " .. path, false)
  end
end

print("=== nothing in the floor needs what is not ===")
local outside, seen = {}, 0
for _, path in ipairs(floorList) do
  local src = read(path:sub(2))
  test("the release builds it: " .. path, src ~= nil)
  if src then
    seen = seen + 1
    src = strip(src)
    for mod in src:gmatch("[^%w_.]require%s*%(?%s*[\"']([%w_.%-]+)[\"']") do
      local target = toPath(mod)
      if target and not inFloor[target] then
        outside[#outside + 1] = path .. " needs " .. target
      end
    end
  end
end
test("every floor file was read", seen == #floorList, seen)
test("the floor is closed under require", #outside == 0, outside[1])

print("=== it fits the machine it is for ===")
do
  local size = 0
  for _, path in ipairs(floorList) do
    local h = io.open("../TOS-Release" .. path, "rb")
    if h then size = size + h:seek("end"); h:close() end
  end
  if size > 0 then
    local cost = size + 512 * #floorList
    test("a built floor fits a 1 MB drive (" .. (cost // 1024) .. " KB)", cost < 1024 * 1024, cost)
  end
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
