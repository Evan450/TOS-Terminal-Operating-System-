-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the kernel-panic stop screen (init.lua)       ║
-- ║                                                                 ║
-- ║  /init.lua is a top-level chunk with side effects the moment it  ║
-- ║  runs, so the two stop-screen functions are LIFTED OUT of the    ║
-- ║  file and executed -- the shipped bytes, not a copy.             ║
-- ║                                                                  ║
-- ║  What matters on a crash screen is what survives a small one:    ║
-- ║  a Tier 1 box is 50x16. The STOP line and the error's own first  ║
-- ║  line must always fit; spacers, the hex and the traceback's tail ║
-- ║  are what give way. And the colours are per tier, because OC's   ║
-- ║  Tier 2 palette is not VGA's and Tier 1 has no blue at all.       ║
-- ╚═════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_stop_screen.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end
local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end

local src = readAll("init.lua") or readAll("TOS-Dev/init.lua")
test("init.lua is readable", src ~= nil)
if not src then print("*** TESTS FAILED ***"); os.exit(1) end

local function lift(name)
  local body = src:match("(local function " .. name .. ".-end)%s*%-%-%[%[/TEST%-EXTRACT%]%]")
  if not body then return nil, "not found" end
  local chunk, err = load(body .. "\nreturn " .. name, "=" .. name, "t")
  if not chunk then return nil, err end
  return chunk(), body
end
local stopScreenLines, linesBody = lift("stopScreenLines")
local drawStopScreen, drawBody = lift("drawStopScreen")
test("stopScreenLines lifts out of init.lua and loads", type(stopScreenLines) == "function", linesBody)
test("drawStopScreen lifts out of init.lua and loads", type(drawStopScreen) == "function", drawBody)
if type(stopScreenLines) ~= "function" or type(drawStopScreen) ~= "function" then
  print("*** TESTS FAILED ***"); os.exit(1)
end

print("=== stop screen ===")

local TRACE = table.concat({
  "tos/kernel/fs.lua:204: attempt to index a nil value (field 'proxy')",
  "stack traceback:",
  "\t[C]: in function 'error'",
  "\ttos/kernel/fs.lua:204: in function 'kernel.fs.mount'",
  "\ttos/kernel/init.lua:311: in function 'kernel.boot'",
  "\ttos/kernel/init.lua:290: in upvalue 'stage'",
  "\ttos/kernel/init.lua:120: in function <tos/kernel/init.lua:100>",
  "\t[C]: in function 'xpcall'",
  "\t/init.lua:1204: in main chunk",
  "\t(...tail calls...)",
}, "\n")
local INFO = { code = "E-201", sym = "ERR_KERNEL_PANIC", hex = "0x00020001", detail = TRACE,
               report = "/var/crash/crash-412.txt",
               status = "uptime 412s | 187 KB free | TOS 1.5.0" }

local function texts(lines) local t = {}; for i, l in ipairs(lines) do t[i] = l[1] end; return t end
local function has(lines, needle)
  for _, l in ipairs(lines) do if l[1]:find(needle, 1, true) then return true end end
  return false
end
local function widest(lines) local w = 0; for _, l in ipairs(lines) do w = math.max(w, #l[1]) end; return w end

-- ── A roomy screen (T2/T3, 80x25) ───────────────────────────────────
print("\n-- 80x25 --")
do
  local L = stopScreenLines(INFO, 80, 25)
  test("fits the height", #L <= 25, #L)
  test("fits the width", widest(L) <= 80, widest(L))
  test("the STOP line: E-number and symbol", has(L, "*** STOP: E-201  ERR_KERNEL_PANIC"))
  test("the hex reference line", has(L, "0x00020001"))
  test("the error's own first line", has(L, "attempt to index a nil value"))
  test("where the report went", has(L, "/var/crash/crash-412.txt"))
  test("how to read the code afterwards", has(L, "why E-201"))
  test("the way out", has(L, "Press any key to reboot"))
  test("tabs from the traceback are not drawn raw", not table.concat(texts(L)):find("\t"))
end

-- ── A Tier 1 screen (50x16): what gives way, and what does not ──────
print("\n-- 50x16 (Tier 1) --")
do
  local L = stopScreenLines(INFO, 50, 16)
  test("fits the height", #L <= 16, #L)
  test("fits the width", widest(L) <= 50, widest(L))
  test("the STOP line survives", has(L, "*** STOP: E-201"))
  test("the error's first line survives", has(L, "attempt to index a nil"))
  test("the way out survives", has(L, "Press any key to reboot"))
  -- The traceback's HEAD outlives its tail.
  local head, tail = has(L, "kernel.fs.mount"), has(L, "tail calls")
  test("a cut traceback keeps its first frames, not its last", head or not tail)
end

-- ── Absurdly small: the code and the error are the last to go ───────
print("\n-- 40x4 --")
do
  local L = stopScreenLines(INFO, 40, 4)
  test("fits the height", #L <= 4, #L)
  test("even here, the STOP line", has(L, "STOP: E-201"))
  test("and the start of the error", has(L, "attempt to"))
end

-- No report path is not an error: the crash dump can fail too.
do
  local info = {}
  for k, v in pairs(INFO) do info[k] = v end
  info.report = nil
  local L = stopScreenLines(info, 80, 25)
  test("no report: still says reboot, names no path", has(L, "1. Reboot.") and not has(L, "crash report is"))
end

-- ── Colours, per tier, against a fake GPU ───────────────────────────
print("\n-- colours --")
local function fakeGpu()
  local g = { calls = {}, bg = nil, rows = {} }
  g.setBackground = function(c) g.bg = c; g.calls[#g.calls + 1] = "bg" end
  g.setForeground = function(c) g.fg = g.fg or c end
  g.fill = function(x, y, w, h, ch) g.filled = { x, y, w, h, ch } end
  g.set = function(x, y, t) g.rows[y] = t end
  return g
end
local L = stopScreenLines(INFO, 80, 25)
do
  local g = fakeGpu(); drawStopScreen(g, L, 80, 25, 4)
  test("Tier 2 paints OC's own palette blue, 0x333399 (not VGA's)", g.bg == 0x333399,
    string.format("0x%06X", g.bg or 0))
  test("...over the whole screen", g.filled and g.filled[3] == 80 and g.filled[4] == 25)
  local maxRow = 0; for y in pairs(g.rows) do maxRow = math.max(maxRow, y) end
  test("...and never draws below the last row", maxRow <= 25, maxRow)
end
do
  local g = fakeGpu(); drawStopScreen(g, L, 80, 25, 8)
  test("Tier 3 paints the classic 0x0000AA", g.bg == 0x0000AA, string.format("0x%06X", g.bg or 0))
end
do
  local g = fakeGpu(); drawStopScreen(g, L, 50, 16, 1)
  test("Tier 1 has no blue: inverse video (white ground)", g.bg == 0xFFFFFF)
  test("...with black text", g.fg == 0x000000)
end

-- ── The literal fallback agrees with the registry ───────────────────
--! init.lua carries E-201/E-202 as literals for the case where the
--! registry itself is what failed to load. A literal can drift from the
--! table it copies; this is what stops it.
print("\n-- fallback --")
do
  package.path = "tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
  local okE, errors = pcall(require, "kernel.errors")
  test("kernel.errors loads", okE)
  local tbl = src:match("local STOP_FALLBACK = (%b{})")
  test("init.lua declares STOP_FALLBACK", tbl ~= nil)
  local fb = tbl and load("return " .. tbl, "=fb", "t")()
  if okE and fb then
    for sym, pair in pairs(fb) do
      local e = errors.find(sym)
      test(sym .. " exists in the registry", e ~= nil)
      if e then
        test(sym .. ": fallback E-number matches", errors.code(e) == pair[1], pair[1])
        test(sym .. ": fallback hex matches", errors.hex(e) == pair[2], pair[2])
      end
    end
  end
end

-- ── init.lua must stay Lua 5.2-parseable ────────────────────────────
--! The architecture guard at the top of init.lua has to RUN on a 5.2 CPU
--! to tell the operator to switch; one 5.3 operator anywhere in the file
--! and it dies at parse time instead, with nothing on screen. There is no
--! 5.2 interpreter here to check with, so the new code is checked for the
--! 5.3-only operators directly.
print("\n-- Lua 5.2 --")
for name, body in pairs({ stopScreenLines = linesBody, drawStopScreen = drawBody }) do
  local code = body:gsub("%-%-[^\n]*", ""):gsub('"[^"\n]*"', '""')   -- comments and strings out
  local bad = code:find("//", 1, true) or code:find("<<", 1, true) or code:find(">>", 1, true)
    or code:find("[^~<>=]&[^&]") or code:find("[^|]|[^|]")
  test(name .. " uses no 5.3-only operator", not bad)
end

-- ── [wiring] the panic path really uses them ────────────────────────
test("[wiring] the panic path draws the stop screen",
  src:find("drawStopScreen(gpu, stopScreenLines(", 1, true) ~= nil)
test("[wiring] and resets the GPU to the visible buffer first",
  src:find("pcall(gpu.setActiveBuffer, 0)", 1, true) ~= nil)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
