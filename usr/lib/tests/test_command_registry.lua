-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: command registry + help coverage         ║
-- ║                                                            ║
-- ║  Guards the "every command has its own help" property the  ║
-- ║  registry-driven `help <cmd>` fallback relies on, and the  ║
-- ║  command prune (mod/launch removed; monitor/top added).    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_command_registry.lua

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

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local Cmds = require("shell.panels.commands")

-- ── M.entry: focused metadata per command ───────────────────────────
test("entry(ps) has help text", true,
  type(Cmds.entry("ps")) == "table" and (Cmds.entry("ps").help or "") ~= "")
test("entry(monitor) exists", true, Cmds.entry("monitor") ~= nil)
test("entry(pkg) exists", true, Cmds.entry("pkg") ~= nil)
test("entry(unknown) is nil", nil, Cmds.entry("definitely-not-a-command"))

-- ── Prune: mod + launch removed; monitor/top added; aliases kept ─────
test("mod was pruned", nil, Cmds.entry("mod"))
test("launch was pruned", nil, Cmds.entry("launch"))
-- v1.4.0 consolidation: launcher/apps retired (Desktop is the menu
-- surface); the keycard menu survives as tape-menu. ver/device/swap/
-- restore folded into about/hostname/optimize/trash.
test("launcher was retired", nil, Cmds.entry("launcher"))
test("apps was retired", nil, Cmds.entry("apps"))
test("tape-menu added", true, Cmds.entry("tape-menu") ~= nil)
-- `ver` was folded into `about` but help kept advertising it and the
-- lazy-loader no longer knew it ("unknown command"). Restored as an alias.
test("ver restored as an about alias", "about", (Cmds.entry("ver") or {}).alias)
test("device folded into hostname", nil, Cmds.entry("device"))
test("swap folded into optimize", nil, Cmds.entry("swap"))
test("restore folded into trash", nil, Cmds.entry("restore"))
test("alias entries carry their canonical", "ls", (Cmds.entry("dir") or {}).alias)
test("monitor added", true, Cmds.entry("monitor") ~= nil)
test("top alias added", true, Cmds.entry("top") ~= nil)

-- ── Top-level package shortcuts (v1.4.0) ────────────────────────────
-- `install`/`uninstall` dispatch on their own but collapse onto pkg's
-- help row (alias = "pkg"), so a new operator can type `install <name>`.
test("install shortcut exists", true, Cmds.entry("install") ~= nil)
test("uninstall shortcut exists", true, Cmds.entry("uninstall") ~= nil)
test("install collapses onto pkg", "pkg", (Cmds.entry("install") or {}).alias)
test("uninstall collapses onto pkg", "pkg", (Cmds.entry("uninstall") or {}).alias)
-- pkg's help row names its shortcuts; install/uninstall get no own row.
do
  local groups = Cmds.helpList(3)   -- root sees admin commands
  local pkgRow, standalone = nil, false
  for _, e in ipairs(groups.admin or {}) do
    if e.name:match("^pkg") then pkgRow = e.name end
    if e.name == "install" or e.name == "uninstall" then standalone = true end
  end
  test("help lists pkg with its shortcuts", true,
    (pkgRow ~= nil) and pkgRow:find("install", 1, true) ~= nil)
  test("help does NOT give install/uninstall their own row", false, standalone)
end

-- ── Every dispatchable command has its own help line ────────────────
-- This is what lets `help <cmd>` always produce a focused entry.
local names = Cmds.commandNames()
test("commandNames is non-empty", true, #names > 0)
local missing = {}
for _, n in ipairs(names) do
  local e = Cmds.entry(n)
  if not (e and type(e.help) == "string" and #e.help > 0) then missing[#missing + 1] = n end
end
for _, n in ipairs(missing) do print("    no help text: " .. n) end
test("every command has help text", 0, #missing)

-- ── commandNames reflects the prune ─────────────────────────────────
local set = {}
for _, n in ipairs(names) do set[n] = true end
test("monitor in commandNames", true, set["monitor"] == true)
test("top in commandNames", true, set["top"] == true)
test("pkg in commandNames", true, set["pkg"] == true)
test("mod NOT in commandNames", nil, set["mod"])
test("launch NOT in commandNames", nil, set["launch"])

-- ── Every command `help` names must actually dispatch ───────────
-- The checks above go command -> help line. This is the OTHER direction, and
-- it is the one that rots: a command gets retired or folded into another, its
-- registry entry goes, and the hand-written reference table in core.lua keeps
-- advertising it. Typing it then answers "unknown command", which reads to an
-- operator as a broken install.
--
-- Three times now. `ver` was folded into `about` and help kept listing it.
-- `swap` was folded into `optimize swap` and `device` into `hostname`, and
-- both stayed in the reference until an operator typed one -- which is how
-- this check came to exist.
do
  local fh
  for _, pth in ipairs({ "tos/shell/panels/commands/core.lua",
      "../../../tos/shell/panels/commands/core.lua",
      "TOS-Dev/tos/shell/panels/commands/core.lua" }) do
    fh = io.open(pth, "r"); if fh then break end
  end
  test("core.lua is readable for the help audit", true, fh ~= nil)
  if fh then
    local src = fh:read("*a"); fh:close()
    -- ONLY the main reference table. The per-command `help <cmd>` sections
    -- below it list SUBcommands, which are not dispatchable names.
    local from = src:find("=== TOS Command Reference ===", 1, true)
    -- The table ends at its own closing line. Getting this boundary wrong
    -- is not harmless: with `to` nil the range ran to end-of-file and the
    -- audit started reading `man` and `keys` prose as command rows.
    local to   = src:find("Showing only what's installed here", from or 1, true)
    test("found the reference table", true, from ~= nil and to ~= nil)
    local body = src:sub(from or 1, to or #src)

    -- Syntax examples, not command names. Everything else must dispatch.
    local NOT_COMMANDS = { cmd1 = true, cmd = true }

    local rows, bad, seen = 0, {}, {}
    -- string.char(10) rather than an escape: this file is edited through
    -- enough layers that a backslash-n has already been eaten once.
    local NL = string.char(10)
    for line in body:gmatch("[^" .. NL .. "]+") do
      local text = line:match('o%("  (%S[^"]*)"')
      if text then
        -- A reference ROW is "<name><space-or-end>...". A name is never
        -- followed by punctuation here, which is what separates a real row
        -- from prose that happens to start lowercase ("fields: ...",
        -- "e.g. keys set quit F4").
        local first, after = text:match("^([a-z][a-z0-9%-]*)(.?)")
        if after == ":" or after == "." then first = nil end
        if first and not seen[first] then
          seen[first] = true; rows = rows + 1
          if not NOT_COMMANDS[first] and not Cmds.entry(first) then
            bad[#bad + 1] = first .. '  ("' .. text:sub(1, 48) .. '")'
          end
        end
      end
    end
    -- Sanity: if the pattern stops matching, the audit would pass vacuously.
    test("the audit actually read rows", true, rows > 40)
    if #bad > 0 then
      print("       help advertises commands that do not dispatch:")
      for _, b in ipairs(bad) do print("         " .. b) end
    end
    test("every command help names is dispatchable", 0, #bad)
  end
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
