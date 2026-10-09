-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the picker's G notice has the key bar to     ║
-- ║  itself                                                        ║
-- ║                                                                ║
-- ║  G ticks every package in the cursor's category and says so on ║
-- ║  the key bar. It was painted over the START of the bar, so on  ║
-- ║  the headless machine the bottom row read                      ║
-- ║    "▓ Selected 3 in Games  / Filter · A All · N None ..."      ║
-- ║  -- the notice running into the keys left beside it, and the   ║
-- ║  left cap gone.                                                ║
-- ║                                                                ║
-- ║  Runs the real shell/pkgpicker.lua on a fake 80x25 GPU, presses ║
-- ║  G, reads the bottom row, and quits with Q.                    ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_picker_bar_notice.lua   (from TOS-Dev)

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
local function blank() for y = 1, H do grid[y] = {}; for x = 1, W do grid[y][x] = " " end end end
blank()
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
local function row(y) return table.concat(grid[y]) end

-- ── Keys: G, then (once the bottom row has been read) Q ───────────
local bottomAfterG
local keys = { { 103, 34 }, { 113, 16 } }
local pulls = 0
package.loaded["computer"] = {
  uptime = function() return 0 end,
  pullSignal = function()
    pulls = pulls + 1
    if pulls == 2 then bottomAfterG = row(H) end
    local k = table.remove(keys, 1)
    if not k then error("the picker asked for more keys than the test has") end
    return "key_down", "kb", k[1], k[2]
  end,
}
package.loaded["component"] = {
  list = function(kind) local done = false
    return function() if kind == "gpu" and not done then done = true; return "gpu-1" end end end,
  proxy = function() return gpu end,
}

-- ── Three games and a tool, nothing installed ──────────────────────
local avail = {
  { name = "snake",  version = "1.0.1", category = "games", description = "Snake", root = "/mnt/d/snake" },
  { name = "tetris", version = "1.1.1", category = "games", description = "Tetris", root = "/mnt/d/tetris" },
  { name = "ttt",    version = "1.0.0", category = "games", description = "Tic-tac-toe", root = "/mnt/d/ttt" },
  { name = "calc",   version = "1.0.0", category = "productivity", description = "Calc", root = "/mnt/d/calc" },
}
package.loaded["kernel.pkg"] = {
  installByName = function() return true, { installed = {}, skipped = {} } end,
  listAllAvailable = function() return avail end,
  repoRoots = function() return {} end,
  info = function() return nil end,
}
package.loaded["kernel.users"] = {
  currentSession = function() return { tier = 3, user = "root" } end,
  TIER = { ADMIN = 2 },
}
package.loaded["kernel.fs"] = { exists = function() return false end }

print("=== the picker's G notice has the key bar to itself ===")

local okL, picker = pcall(require, "shell.pkgpicker")
test("shell.pkgpicker loads", okL, picker)
if okL then
  local okR, err = pcall(picker.run, {})
  test("the picker runs and quits on Q", okR, err)
  local bar = bottomAfterG or ""
  test("G's notice is on the key bar", bar:find("Selected 3 in Games", 1, true) ~= nil, bar)
  test("...alone: none of the keys run on beside it", bar:find("Filter", 1, true) == nil, bar)
  test("...between the ramp's caps", bar:sub(1, #"▓▒░") == "▓▒░" and bar:sub(-#"░▒▓") == "░▒▓", bar)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
