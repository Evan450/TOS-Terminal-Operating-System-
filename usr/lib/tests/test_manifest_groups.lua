-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a feature group can be stripped safely       ║
-- ║                                                                ║
-- ║  SELF-STRIPPING (TODO, the operator's 2026-08-11 decision):    ║
-- ║  `strip <group>` deletes a group's files from the base image.  ║
-- ║  That is only safe if nothing OUTSIDE the group needs them to  ║
-- ║  load, so this test is the feature, as the design says of its  ║
-- ║  floor twin (test_manifest_floor.lua):                         ║
-- ║    - a group's files are never floor or critical;              ║
-- ║    - a file outside a group reaches the group's modules only   ║
-- ║      through pcall(require, ...), never a bare require, which  ║
-- ║      is the boot that panics after a strip;                    ║
-- ║    - the strip module itself is in no group.                   ║
-- ║  Found writing it: ed25519.lua requires curve25519field bare,  ║
-- ║  so that file is not in NETWORK although x25519 uses it too.   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_manifest_groups.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function readSrc(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("a"); h:close(); return (s:gsub("\r\n", "\n"))
end

local manifest = dofile("tos/system_manifest.lua")
test("the manifest loads", type(manifest) == "table")

-- "/tos/kernel/net/init.lua" -> "kernel.net"; "/tos/shell/chat.lua" -> "shell.chat"
local function moduleOf(path)
  if not path:match("%.lua$") then return nil end
  local m = path:sub(2, -5):gsub("/", ".")
  m = m:gsub("^tos%.", ""):gsub("%.init$", "")
  return m
end

local groups, groupOfModule, nGrouped = {}, {}, 0
print("=== groups are never the floor ===")
for _, e in ipairs(manifest) do
  if e.group then
    nGrouped = nGrouped + 1
    groups[e.group] = groups[e.group] or {}
    table.insert(groups[e.group], e.path)
    test(e.path .. " (" .. e.group .. ") is not floor or critical", not e.floor and not e.critical)
    local m = moduleOf(e.path)
    if m then groupOfModule[m] = e.group end
  end
end
test("there are groups to strip", nGrouped >= 20, nGrouped)
for _, name in ipairs({ "network", "internet", "jbod", "i18n", "cluster" }) do
  test("group " .. name .. " exists", groups[name] ~= nil and #groups[name] > 0)
end
local stripEntry
for _, e in ipairs(manifest) do if e.path == "/tos/kernel/strip.lua" then stripEntry = e end end
test("kernel/strip.lua ships", stripEntry ~= nil)
test("and is in no group (it is what brings a group back)", stripEntry and stripEntry.group == nil)
local curve
for _, e in ipairs(manifest) do if e.path == "/tos/kernel/curve25519field.lua" then curve = e end end
test("curve25519field is not in a group (package signatures need it)", curve and curve.group == nil)

print("=== nothing outside a group needs it to load ===")
local bare, scanned = {}, 0
for _, e in ipairs(manifest) do
  if e.path:match("%.lua$") then
    local src = readSrc("." .. e.path)
    if src then
      scanned = scanned + 1
      local pos = 1
      while true do
        local s, f, name = src:find("require%s*%(?%s*[\"']([%w_%.]+)[\"']", pos)
        if not s then break end
        pos = f + 1
        local g = groupOfModule[name]
        if g and g ~= e.group then
          local ls = src:sub(1, s):match(".*\n()") or 1
          local le = src:find("\n", f, true) or #src
          local line = src:sub(ls, le)
          if not line:find("pcall", 1, true) then
            bare[#bare + 1] = e.path .. " requires " .. name .. " (" .. g .. ") bare"
          end
        end
      end
    end
  end
end
test("scanned the shipped Lua files", scanned > 100, scanned)
for _, b in ipairs(bare) do print("    " .. b) end
test("every reach into a group from outside it is a pcall", #bare == 0, #bare)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
