-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `watch` does not lift a command's tier        ║
-- ║                                                                ║
-- ║  The executor enforces the registry tier of the command it      ║
-- ║  dispatches (Sep 2026 pentest). Through `watch` that command is ║
-- ║  `watch` itself, tier 0, and the watched one ran through        ║
-- ║  C[name] with no gate: a GUEST could `watch redstone set left   ║
-- ║  15`, drive a robot or list raw drives. The watched command now ║
-- ║  meets its own tier, when the tab opens and on every refresh.   ║
-- ║                                                                ║
-- ║  Drives the REAL watch (commands/core.lua) and the REAL         ║
-- ║  registry and helpers.liveTier, with recording stand-ins for    ║
-- ║  the watched commands.                                         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_watch_tier.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_watch_tier.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 1 end, freeMemory = function() return 1e6 end }
-- A tape drive with a card in it, for the tape toolbox below.
local TAPE = { isReady = function() return true end, getSize = function() return 4096 end }
package.loaded["component"] = {
  list = function(kind)
    local done = false
    return function()
      if done or kind ~= "tape_drive" then return nil end
      done = true; return "tape0"
    end
  end,
  proxy = function(a) return a == "tape0" and TAPE or nil end,
}
package.loaded["kernel.vault"] = {}
local toolboxRun
package.loaded["shell.launcher"] = {
  readTapeMenuFromDrive = function() return { items = {} } end,
  run = function(opts) toolboxRun = opts.runLine end,
}
package.loaded["kernel.pkg"] = {
  getCommand = function(name)
    if name == "fakegame" then return function(_, o) o("game frame") end end
  end,
}

local commands = require("shell.panels.commands")
test("the registry is the real one", (commands.entry("redstone") or {}).tier == 1
  and (commands.entry("disk") or {}).tier == 2 and (commands.entry("flash") or {}).tier == 3
  and (commands.entry("watch") or {}).tier == 0)

-- ── A seat, and the people who might sit at it ─────────────────────
local sessions = {
  guest = { user = "guest", tier = 0 }, alice = { user = "alice", tier = 1 },
  adam = { user = "adam", tier = 2 }, root = { user = "root", tier = 3 },
  elev = { user = "alice", tier = 2, elevated = true },
}
local S = { K = {}, E = {}, P = {}, F = {}, SC = {}, NM = {}, st = "guest",
            D = { getSize = function() return 80, 25 end },
            U = { getSession = function(tok) return sessions[tok] end },
            T = setmetatable({ error = "ERR" }, { __index = function() return 0 end }),
            W = 80, H = 25, cmdHistory = {} }
local opened
local deps = {
  rp = function(p) return p end, openViewTab = function() end, openEditTab = function() end,
  refreshBrowser = function() end, canRead = function() return true end,
  canWrite = function() return true end, canAccess = function() return true end,
  rootOnly = function() return true end, adminOnly = function() return true end,
  makeProgramEnv = function() end, dialog = function() end, drawAll = function() end,
  openLiveTab = function(label, fn) opened = { label = label, refresh = fn } end,
  promptInput = function() return "card passphrase" end,
}
local C = {}
local chunk
for _, p in ipairs({ base .. "../../../tos/shell/panels/commands/core.lua",
                     "tos/shell/panels/commands/core.lua" }) do
  chunk = loadfile(p); if chunk then break end
end
test("commands/core.lua loads", chunk ~= nil)
if not chunk then print("*** TESTS FAILED ***"); os.exit(1) end
chunk()(C, S, deps)

-- Recording stand-ins for the commands being watched.
local ran = {}
for _, n in ipairs({ "redstone", "disk", "flash", "ps" }) do
  C[n] = function(args) ran[#ran + 1] = n .. " " .. table.concat(args, " ") end
end

local said
local function watchAs(tok, ...)
  S.st, opened, ran, said, S.lastDenial = tok, nil, {}, {}, nil
  C.watch({ ... }, function(t) said[#said + 1] = tostring(t) end)
  return opened
end
local function refresh()
  ran = {}
  local out = opened.refresh()
  local text = {}
  for _, l in ipairs(out) do text[#text + 1] = l[1] end
  return table.concat(text, "\n")
end
local function saidAny(needle) return table.concat(said, "\n"):find(needle, 1, true) ~= nil end

print("=== watch does not lift a command's tier ===")
print()

test("a GUEST cannot watch a tier-1 command (redstone set)",
  watchAs("guest", "redstone", "set", "left", "15") == nil and #ran == 0)
test("...told why, with the code", saidAny("E-403") and saidAny("'redstone'"))
test("...and `why` can explain it", S.lastDenial and S.lastDenial.cmd == "redstone"
  and S.lastDenial.need == 1 and S.lastDenial.have == 0)

test("a GUEST can still watch a tier-0 command (ps)", watchAs("guest", "ps") ~= nil)
refresh()
test("...and it runs on refresh", ran[1] == "ps ")

test("a USER can watch a tier-1 command", watchAs("alice", "redstone", "status") ~= nil)
refresh()
test("...and it runs", ran[1] == "redstone status")
test("a USER cannot watch a tier-2 command (disk)", watchAs("alice", "disk", "list") == nil)
test("an ADMIN cannot watch a tier-3 command (flash)", watchAs("adam", "flash", "x") == nil)
test("ROOT can", watchAs("root", "flash", "x") ~= nil)

-- sudo's elevated token, and what happens when it lapses mid-watch.
test("an elevated (sudo) seat can watch a tier-2 command", watchAs("elev", "disk", "list") ~= nil)
refresh()
test("...and it runs", ran[1] == "disk list")
sessions.elev = nil
local text = refresh()
test("once the token lapses, the next refresh refuses", #ran == 0 and text:find("E-403", 1, true) ~= nil, text)

-- A package command is not in the registry and runs sandboxed anyway.
test("a package command can still be watched", watchAs("guest", "fakegame") ~= nil)
test("...and runs", refresh():find("game frame", 1, true) ~= nil)

-- The tape toolbox runs the card's items by name as well: "at your tier"
-- has to include the registry's tier.
print()
print("--- the tape toolbox ---")
do
  S.st = "alice"
  C["tape-menu"]({}, function() end)
  test("the toolbox opens for a USER", type(toolboxRun) == "function")
  if toolboxRun then
    local function lines(out)
      local t = {}
      for _, l in ipairs(out) do t[#t + 1] = l[1] end
      return table.concat(t, "\n")
    end
    local text = lines(toolboxRun("disk eject /mnt/data"))
    test("a card item cannot run a tier-2 command for a USER", text:find("E-403", 1, true) ~= nil, text)
    text = lines(toolboxRun("netfs mount host share /mnt/s"))
    test("...nor mount a remote share", text:find("E-403", 1, true) ~= nil, text)
    text = lines(toolboxRun("echo hello from the card"))
    test("a tier-0 item still runs", text:find("hello from the card", 1, true) ~= nil, text)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
