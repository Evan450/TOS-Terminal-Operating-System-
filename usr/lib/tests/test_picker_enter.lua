-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: Enter adds the package you are on            ║
-- ║                                                                ║
-- ║  Enter went straight to install, so an operator pressing it   ║
-- ║  to pick a package left the picker with nothing done, and one  ║
-- ║  who had picked something started the install while still     ║
-- ║  choosing. Enter now adds the row you are on, and installs    ║
-- ║  only once that row is already going in. The key bar says      ║
-- ║  which it will do, and anything a pick brought along.          ║
-- ║                                                                ║
-- ║  Runs the real shell/pkgpicker.lua on a fake 80x25 GPU.        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_picker_enter.lua   (from TOS-Dev)

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
local function bar() return table.concat(grid[H]) end
local function screen()
  local t = {}
  for y = 1, H do t[y] = table.concat(grid[y]) end
  return table.concat(t, "\n")
end

-- ── A machine: games, and a writer that needs a printer ────────────
local AVAIL = {
  { name = "snake",  version = "1.0.1", category = "games", description = "Snake", root = "/mnt/d" },
  { name = "tetris", version = "1.1.1", category = "games", description = "Tetris", root = "/mnt/d",
    recommends = { "mouse" } },
  { name = "mouse",  version = "1.0.0", category = "drivers", description = "Mouse", root = "/mnt/d" },
  { name = "printer", version = "1.0.0", category = "productivity", description = "Printer", root = "/mnt/d" },
  { name = "write",  version = "1.1.0", category = "productivity", description = "Word processor",
    root = "/mnt/d", requires = { "printer" } },
}
local installedNow, calls = {}, {}
package.loaded["kernel.pkg"] = {
  installByName = function(n) calls[#calls + 1] = n; return true, {} end,
  listAllAvailable = function() return AVAIL end,
  repoRoots = function() return {} end,
  info = function(n) return installedNow[n] and { name = n } or nil end,
}
package.loaded["kernel.users"] = {
  currentSession = function() return { tier = 3, user = "root" } end,
  TIER = { ADMIN = 2 },
}
package.loaded["kernel.fs"] = { exists = function() return false end }

local UP, DOWN = { 0, 200 }, { 0, 208 }
local ENTER, SPACE, QUIT, ANY = { 13, 28 }, { 32, 57 }, { 113, 16 }, { 120, 45 }
local R = { 114, 19 }

local script, shots
package.loaded["computer"] = {
  uptime = function() return 0 end,
  pullSignal = function()
    shots[#shots + 1] = { bar = bar(), screen = screen() }
    local k = table.remove(script, 1)
    if not k then error("the picker asked for more keys than the test has") end
    return "key_down", "kb", k[1], k[2]
  end,
}
package.loaded["component"] = {
  list = function(kind) local done = false
    return function() if kind == "gpu" and not done then done = true; return "gpu-1" end end end,
  proxy = function() return gpu end,
}

local picker = require("shell.pkgpicker")

--- Press these keys in a fresh picker. shots[1] is the first screen;
--- shots[n + 1] is the screen after the nth key.
local function run(keys)
  for y = 1, H do grid[y] = {}; for x = 1, W do grid[y][x] = " " end end
  script, shots, calls = keys, {}, {}
  local ok, err = pcall(picker.run, {})
  test("the picker ran the keys through", ok, err)
  return shots
end
local function has(s, needle) return s:find(needle, 1, true) ~= nil end

print("=== Enter adds the package you are on ===")
print()

-- The list opens on the first package row: games comes first, so snake.
local s = run({ ENTER, QUIT })
test("the opening bar says Enter adds", has(s[1].bar, "Space/Enter Add"), s[1].bar)
test("Enter on an unpicked package stays in the picker", #s == 2)
test("...and ticks it", has(s[2].screen, "[x] snake"), s[2].screen)
test("...and installs nothing", #calls == 0)
test("...and says what happens next", has(s[2].bar, "snake selected · Enter installs"), s[2].bar)

s = run({ ENTER, ENTER, ANY })
test("Enter again installs what was picked", calls[1] == "snake" and #calls == 1, table.concat(calls, ","))

s = run({ ENTER, DOWN, ENTER, ENTER, ANY })
test("a second Enter on another package adds that too, without installing",
  has(s[4].screen, "[x] snake") and has(s[4].screen, "[x] tetris"), s[4].screen)
test("...and the next Enter installs both", #calls == 2, table.concat(calls, ","))

s = run({ SPACE, QUIT })
test("Space still ticks, and the bar then offers install",
  has(s[2].screen, "[x] snake") and has(s[2].bar, "Enter Install"), s[2].bar)
test("...with every key still on the bar at 80 columns", has(s[2].bar, "R +Suggested"), s[2].bar)

s = run({ SPACE, SPACE, QUIT })
test("Space unticks, and the bar goes back to adding", has(s[3].bar, "Space/Enter Add"), s[3].bar)

print()
print("=== What a pick brings along is named ===")
print()

-- Sorted by category: games (snake, tetris), productivity (printer, write),
-- drivers (mouse).
s = run({ DOWN, SPACE, QUIT })
test("a pick with a suggestion names it, and the key", has(s[3].bar, "R adds mouse"), s[3].bar)

s = run({ DOWN, SPACE, R, QUIT })
test("R adds it, and says so", has(s[4].bar, "Added 1 suggested"), s[4].bar)
test("...ticked", has(s[4].screen, "[x] mouse"), s[4].screen)

s = run({ R, QUIT })
test("R with nothing to add says that too", has(s[2].bar, "suggests nothing more"), s[2].bar)

s = run({ DOWN, DOWN, DOWN, ENTER, QUIT })
test("Enter on a package with a dependency names it",
  has(s[5].bar, "write + printer selected"), s[5].bar)
test("...and marks it [+]", has(s[5].screen, "[+] printer"), s[5].screen)
test("...and the rail counts both", has(s[5].screen, "2 selected"), s[5].screen)

s = run({ DOWN, DOWN, DOWN, ENTER, UP, ENTER, ANY })
test("Enter on a [+] row installs: it is already going in",
  #calls == 2 and calls[1] == "printer" and calls[2] == "write", table.concat(calls, ","))

print()
print("=== Nothing to add, nothing selected ===")
print()

for _, e in ipairs(AVAIL) do installedNow[e.name] = true end
s = run({ ENTER, QUIT })
test("Enter on an installed package with nothing selected stays", #s == 2)
test("...and says what to do", has(s[2].bar, "Nothing selected"), s[2].bar)
test("...and installs nothing", #calls == 0)
test("the bar never offers to add an installed package", has(s[1].bar, "Enter Install"), s[1].bar)
installedNow = {}

print()
print("=== The line-mode list is the same ===")
print()

do
  -- No GPU: the numbered list, driven through io.
  package.loaded["component"] = { list = function() return function() end end }
  local realRead, realWrite = io.read, io.write
  local lines, said = { "i", "1", "i" }, {}
  io.read = function() return table.remove(lines, 1) end
  io.write = function(...)
    for _, v in ipairs({ ... }) do said[#said + 1] = tostring(v) end
    return io.stdout
  end
  calls = {}
  local ok, err = pcall(picker.run, {})
  io.read, io.write = realRead, realWrite
  local text = table.concat(said)
  test("the list ran", ok, err)
  test("i with nothing selected says so and asks again", has(text, "Nothing selected"), text)
  test("...and the next i installs", #calls == 1, table.concat(calls, ","))
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
