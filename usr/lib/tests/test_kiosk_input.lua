-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: what a kiosk user can type, and what        ║
-- ║  happens when the kiosk cannot load                           ║
-- ║                                                               ║
-- ║  kiosk.lua treated every key from 1 to 9 as a menu shortcut,  ║
-- ║  so a digit never reached the line: `cat /public/map2.txt`    ║
-- ║  ran as `cat /public/map.txt` with no menu, and with one a    ║
-- ║  digit mid-word threw the line away and ran that menu item.   ║
-- ║  test_kiosk_acl.lua stops before the input loop, so nothing   ║
-- ║  had ever typed at it. This drives the real loop with real    ║
-- ║  key signals.                                                 ║
-- ║                                                               ║
-- ║  The second half runs kernel/init.lua's own kiosk block: when ║
-- ║  shell.kiosk failed to load, the `kiosk` account was handed   ║
-- ║  the full panels shell, the thing kiosk mode exists to keep   ║
-- ║  it out of. A locked shell has to fail closed.                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_kiosk_input.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_kiosk_input.lua"
local base = here:gsub("[^/\\]*$", "")
local function readSource(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local f = io.open(p, "rb")
    -- CRLF folded to LF: a Windows checkout (core.autocrlf) has CRLF, and the
    -- patterns below are written with \n.
    if f then local d = f:read("a"):gsub("\r\n", "\n"); f:close(); return d, p end
  end
end

-- ── The real input loop ──────────────────────────────────────────
local session = { user = "kiosk", tier = 1, home = "/public" }
local loggedOut = false
local USERS = {
  getSession = function() return session end,
  currentSession = function() return session end,
  logout = function() loggedOut = true end,
}
local DISPLAY = {
  getTheme = function() return { fg = 1, bg = 0 } end,
  getSize  = function() return 80, 25 end,
  clear = function() end, fill = function() end, set = function() end,
}
local keys = {}
local function keyOf(ch)
  if ch == "\r" then return { "key_down", "kb", 13, 28 } end
  if ch == "\4" then return { "key_down", "kb", 4, 32 } end
  return { "key_down", "kb", ch:byte(), 0 }
end
package.loaded["computer"] = {
  uptime = function() return 0 end,
  pullSignal = function()
    local k = table.remove(keys, 1)
    if not k then error("the kiosk asked for a key after the script ended") end
    return table.unpack(k)
  end,
}
package.loaded["shell.panels.helpers"] = {}

local ran = {}
package.loaded["shell.panels.commands"] = {
  build = function()
    return setmetatable({}, { __index = function(_, name)
      return function(args) ran[#ran + 1] = name .. " " .. table.concat(args, " ") end
    end })
  end,
}

local src, path = readSource("tos/shell/kiosk.lua")
test("kiosk.lua is readable", src ~= nil)
if not src then print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); os.exit(1) end
local kiosk = assert(load(src, "@" .. path))()

local logged = {}
package.loaded["kernel.log"] = { error = function(_, m) logged[#logged + 1] = m end }
-- `cfg` is what /etc/kiosk.cfg holds; `typed` is what the user types. `rawText`
-- is the file's bytes instead, or false for a file that cannot be read.
local function session_of(cfg, typed, rawText)
  ran, loggedOut, keys = {}, false, {}
  for ch in typed:gmatch(".") do keys[#keys + 1] = keyOf(ch) end
  keys[#keys + 1] = keyOf("\4")
  local raw = rawText or (cfg and require("kernel.serialize").encode(cfg)) or nil
  local exists = raw ~= nil
  if rawText == false then raw, exists = nil, true end
  _G._TOS = { users = USERS, display = DISPLAY, net = {}, config = {},
    -- A function, as on a machine: _TOS.log is a write-only adapter, and the
    -- module is kernel.log. A table here hid a crash the runner found.
    log = function() end,
    securefs = {
      exists = function() return exists end,
      readFile = function() return raw end,
    } }
  local kernel = { getDisplay = function() return DISPLAY end }
  local ok, err = pcall(kiosk.run, kernel, "tok")
  return ok, err
end

package.path = base .. "../../../tos/?.lua;tos/?.lua;" .. package.path

print("=== Kiosk input ===")
local everything = { allowed = { "echo", "cat", "date" },
  menu = { { label = "Date", cmd = "date" }, { label = "Map", cmd = "cat /public/map.txt" } } }

local ok, err = session_of({ allowed = { "cat" } }, "cat map2.txt\r")
test("a digit in a command, with no menu configured, is typed",
  ok and ran[1] == "cat map2.txt", ran[1] or err)

ok, err = session_of(everything, "cat a1\r")
test("a digit that has a menu item, mid-word, is typed rather than run",
  ok and #ran == 1 and ran[1] == "cat a1", ran[1] or err)

ok, err = session_of(everything, "2")
test("on an empty line, a digit with a menu item is still the shortcut",
  ok and ran[1] == "cat /public/map.txt", ran[1] or err)

ok, err = session_of(everything, "9")
test("on an empty line, a digit with no menu item starts the line",
  ok and #ran == 0, ran[1] or err)

ok, err = session_of(everything, "echo 123\r")
test("every digit of a number reaches the line",
  ok and ran[1] == "echo 123", ran[1] or err)

-- ── A config it cannot use ───────────────────────
-- These fell back to the defaults, which are wider than most configs: one
-- missing brace gave a guest `cat`. Seen on a booted machine.
print("=== A broken config allows nothing ===")
ok, err = session_of(nil, "cat x\r", '{ allowed = { "date" ')
test("a file that does not parse runs nothing", ok and #ran == 0, ran[1] or err)
test("and says why, in the log", #logged > 0 and logged[#logged]:find("kiosk.cfg", 1, true), logged[#logged])
logged = {}
ok, err = session_of(nil, "cat x\r", false)
test("nor does one that cannot be read", ok and #ran == 0 and #logged == 1, ran[1] or err)
logged = {}
ok, err = session_of(nil, "cat x\r", string.rep(" ", 9000))
test("nor one too large to read", ok and #ran == 0 and #logged == 1, ran[1] or err)
ok, err = session_of(nil, "cat x\r", '{ allowed = "cat" }')
test("nor one whose allow-list is not a list", ok and #ran == 0, ran[1] or err)
ok, err = session_of(nil, "date\r", '{ allowed = "date" }')
test("Ctrl+D still logs out of it", ok and loggedOut, err)

logged = {}
ok, err = session_of(nil, "cat x\r")
test("with no file at all the defaults still apply", ok and ran[1] == "cat x" and #logged == 0, ran[1] or err)
ok, err = session_of({ banner = "Hello" }, "cat x\r")
test("and so they do for a field left out", ok and ran[1] == "cat x", ran[1] or err)

-- ── kernel/init.lua's own block, run rather than read ────────────
print("=== Kiosk fails closed ===")
local init = readSource("tos/kernel/init.lua")
test("kernel/init.lua is readable", init ~= nil)
local block = init and init:match('(local shellRunner = shellModule%.run\n.-)\n%s*%-%- #OOM')
test("the kiosk block is where this test expects it", block ~= nil)
if block then
  local function runBlock(req)
    local chunk = assert(load(block .. "\nreturn shellRunner", "=kioskblock", "t",
      setmetatable({
        shellModule = { run = "PANELS" },
        userName = "kiosk", dIdx = 1,
        log = { info = function() end, error = function() end },
        require = req,
      }, { __index = _G })))
    return chunk()
  end
  local real = function() end
  test("a kiosk that loads runs the kiosk",
    runBlock(function() return { run = real } end) == real)
  local got = runBlock(function() error("not enough memory", 0) end)
  test("a kiosk that will not load does not get the panels shell", got ~= "PANELS", got)
  test("...and ends the seat with an error the shell crash path reports",
    type(got) == "function" and pcall(got) == false)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed."); return true
