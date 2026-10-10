-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the picker panel's indented notes wrap       ║
-- ║                                                                ║
-- ║  For a package on a floppy that is not in the drive, the detail ║
-- ║  panel says "selectable — the installer will ask for it" at     ║
-- ║  column 10 of a 40-column panel. At 80x25 it was cut to         ║
-- ║  "selectable — the installer will as…" (headless machine,       ║
-- ║  2026-10-09); "not on any inserted disk: ..." had the same      ║
-- ║  shape. Both wrap now.                                          ║
-- ║                                                                ║
-- ║  Runs the real shell/pkgpicker.lua on a fake 80x25 GPU.         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_picker_panel_wrap.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local W, H = 80, 25
local grid
local function blank()
  grid = {}
  for y = 1, H do grid[y] = {}; for x = 1, W do grid[y][x] = " " end end
end
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
-- The right pane: everything right of the divider, row by row, trimmed.
local function panel()
  local out = {}
  for y = 1, H do
    local row = table.concat(grid[y])
    local div = row:find("│", 1, true)
    if div then out[#out + 1] = (row:sub(div + #"│"):gsub("%s+$", "")) end
  end
  return out
end

local snapshot
package.loaded["computer"] = {
  uptime = function() return 0 end,
  pullSignal = function()
    snapshot = panel()
    return "key_down", "kb", 113, 16   -- q
  end,
}
package.loaded["component"] = {
  list = function(kind) local done = false
    return function() if kind == "gpu" and not done then done = true; return "gpu-1" end end end,
  proxy = function() return gpu end,
}
package.loaded["kernel.users"] = {
  currentSession = function() return { tier = 3, user = "root" } end,
  TIER = { ADMIN = 2 },
}

local avail, SET = {}, nil
package.loaded["kernel.pkg"] = {
  listAllAvailable = function() local out = {}; for i, e in ipairs(avail) do out[i] = e end; return out end,
  installByName = function() return true, {} end,
  repoRoots = function() return { "/mnt/d1" } end,
  info = function() return nil end,
}
package.loaded["kernel.fs"] = {
  exists = function(p) return SET ~= nil and p == "/mnt/d1/optutil-set.lua" end,
  readFile = function(p) if p == "/mnt/d1/optutil-set.lua" then return SET end end,
}

local function joined(lines) return table.concat(lines, " "):gsub("%s+", " ") end

print("=== the picker panel's indented notes wrap ===")

local okL, picker = pcall(require, "shell.pkgpicker")
test("shell.pkgpicker loads", okL, picker)
if okL then
  -- 1. snake is on disk 2, which is not in the drive; it sorts first.
  avail = { { name = "calc", version = "1.0.0", category = "productivity", description = "Calc", root = "/mnt/d1/calc" } }
  SET = [[return { set = "optional-utilities", disks = 2, packages = {
    calc  = { disk = 1, version = "1.0.0", category = "productivity", description = "Calc" },
    snake = { disk = 2, version = "1.0.1", category = "games", description = "Snake" },
  } }]]
  blank()
  local okR, err = pcall(picker.run, {})
  test("the picker runs", okR, err)
  local p = snapshot or {}
  local text = joined(p)
  test("the panel shows snake", p[1] == "snake", p[1])
  test("the whole note is there", text:find("selectable — the installer will ask for it", 1, true) ~= nil, text)
  local cut = false
  for _, l in ipairs(p) do if l:find("…", 1, true) then cut = true end end
  test("...and nothing in the panel is cut short", not cut, text)

  -- 2. write needs printer, which no disk carries.
  avail = { { name = "write", version = "1.0.0", category = "productivity", description = "Word processor",
              root = "/mnt/d1/write", requires = { "printer", "printerfmt-extras" } } }
  SET = nil
  blank()
  okR, err = pcall(picker.run, {})
  test("the picker runs again", okR, err)
  text = joined(snapshot or {})
  test("the missing-dependency warning is whole",
    text:find("not on any inserted disk: printer, printerfmt-extras", 1, true) ~= nil, text)
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
