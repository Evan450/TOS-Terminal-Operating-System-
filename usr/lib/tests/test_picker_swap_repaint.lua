-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the "Next disk" box goes away on Continue    ║
-- ║                                                                ║
-- ║  Installing across the two Optional Utilities floppies, the    ║
-- ║  picker asks for the next disk in a framed modal. After        ║
-- ║  Continue it went on installing with the box still painted     ║
-- ║  over its progress rows, and it stayed there until the run     ║
-- ║  ended (headless machine, 2026-10-09). The progress screen now ║
-- ║  remembers what it shows and paints it again under the box.    ║
-- ║                                                                ║
-- ║  Runs the real shell/pkgpicker.lua and shell/panels/dialogs    ║
-- ║  on a fake 80x25 GPU: calc is in the drive, snake is on disk 2.║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_picker_swap_repaint.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

-- ── An 80x25 screen that remembers every cell ──────────────────────
local W, H = 80, 25
local grid = {}
for y = 1, H do grid[y] = {}; for x = 1, W do grid[y][x] = " " end end
local function chars(s)
  local out = {}
  for ch in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end
local gpu = {
  getResolution = function() return W, H end,
  getDepth = function() return 8 end,
  setForeground = function() end, setBackground = function() end,
  set = function(x, y, s)
    if not grid[y] then return end
    for i, ch in ipairs(chars(s)) do
      if x + i - 1 >= 1 and x + i - 1 <= W then grid[y][x + i - 1] = ch end
    end
  end,
  fill = function(x, y, w, h, ch)
    for yy = y, y + h - 1 do
      for xx = x, x + w - 1 do if grid[yy] and xx >= 1 and xx <= W then grid[yy][xx] = ch end end
    end
  end,
}
local function screen()
  local rows = {}
  for y = 1, H do rows[y] = table.concat(grid[y]) end
  return table.concat(rows, "\n")
end

-- ── The disks: calc in the drive, snake on disk 2 until the swap ──
local inserted = false
local calc  = { name = "calc", version = "1.0.0", category = "productivity", description = "Calc", root = "/mnt/d1/calc" }
local snake = { name = "snake", version = "1.0.1", category = "games", description = "Snake", root = "/mnt/d2/snake" }
local installed = {}
package.loaded["kernel.pkg"] = {
  listAllAvailable = function()
    local out = { { name = calc.name, version = calc.version, category = calc.category,
                    description = calc.description, root = calc.root } }
    if inserted then
      out[#out + 1] = { name = snake.name, version = snake.version, category = snake.category,
                        description = snake.description, root = snake.root }
    end
    return out
  end,
  installByName = function(name) installed[#installed + 1] = name; return true, {} end,
  repoRoots = function() return { "/mnt/d1" } end,
  info = function() return nil end,
}
local SET = [[return { set = "optional-utilities", disks = 2, packages = {
  calc  = { disk = 1, version = "1.0.0", category = "productivity", description = "Calc" },
  snake = { disk = 2, version = "1.0.1", category = "games", description = "Snake" },
} }]]
package.loaded["kernel.fs"] = {
  exists = function(p) return p == "/mnt/d1/optutil-set.lua" end,
  readFile = function(p) if p == "/mnt/d1/optutil-set.lua" then return SET end end,
}
package.loaded["kernel.users"] = {
  currentSession = function() return { tier = 3, user = "root" } end,
  TIER = { ADMIN = 2 },
}

-- ── Keys: A (all), Enter (install), then C at the swap box once disk 2
-- is "in", then any key at the end -- reading the screen there first.
local atEnd, sawBox
local step = 0
package.loaded["computer"] = {
  uptime = function() return 0 end,
  pullSignal = function()
    step = step + 1
    if step == 1 then return "key_down", "kb", 97, 30 end        -- a
    if step == 2 then return "key_down", "kb", 13, 28 end        -- Enter
    if step == 3 then
      sawBox = screen():find("Next disk", 1, true) ~= nil
      inserted = true                                            -- the swap
      return "key_down", "kb", 99, 46                            -- c = Continue
    end
    if step == 4 then
      atEnd = screen()
      return "key_down", "kb", 32, 57
    end
    error("the picker asked for more keys than the test has")
  end,
}
package.loaded["component"] = {
  list = function(kind) local done = false
    return function() if kind == "gpu" and not done then done = true; return "gpu-1" end end end,
  proxy = function() return gpu end,
}

print("=== the Next disk box goes away on Continue ===")

local okL, picker = pcall(require, "shell.pkgpicker")
test("shell.pkgpicker loads", okL, picker)
if okL then
  local okR, err = pcall(picker.run, {})
  test("the picker runs to the end", okR, err)
  test("the swap box was shown, asking for disk 2", sawBox == true)
  test("both packages installed", #installed == 2 and installed[1] == "calc" and installed[2] == "snake",
    table.concat(installed, ","))
  local s = atEnd or ""
  test("at the end the box is gone", s:find("Next disk", 1, true) == nil and s:find("Continue", 1, true) == nil, s)
  test("...and both progress rows are there to read",
    s:find("calc", 1, true) ~= nil and s:find("snake", 1, true) ~= nil)
  local _, marks = s:gsub("installed", "")
  test("...each marked installed", marks >= 2, marks)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
