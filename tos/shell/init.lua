-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Shell — the launcher                                    ║
-- ║                                                              ║
-- ║  Picks an interface and hands the seat to it. TOS has two,   ║
-- ║  and they run the SAME commands:                             ║
-- ║                                                              ║
-- ║    shell/panels/   the full panels TUI (default)             ║
-- ║    shell/cli.lua   the command line                          ║
-- ║                                                              ║
-- ║  Either can hand over to the other at any time — `cli` and   ║
-- ║  `tui`, or the quit menu's CLI Mode — so this file loops     ║
-- ║  between them until one of them actually exits.              ║
-- ║                                                              ║
-- ║  THE CLI USED TO LIVE HERE, as ~1,150 lines of hand-rolled   ║
-- ║  commands: a second implementation of ls, cat, pkg, useradd  ║
-- ║  and eighty more, sitting alongside the panels shell's own.  ║
-- ║  Measured before this change it had 85 commands against the  ║
-- ║  TUI's 124, so 45 things you could do in the full interface  ║
-- ║  simply did not exist at the prompt.                         ║
-- ║                                                              ║
-- ║  The gap was the symptom; two command tables was the cause,  ║
-- ║  and hand-writing 45 more entries would have re-armed it for ║
-- ║  the next commit. shell/cli.lua now dispatches through the   ║
-- ║  same registry the panels shell uses, loading its categories ║
-- ║  on first touch — so the CLI came out both fully capable AND ║
-- ║  cheaper to start than the copy it replaced.                 ║
-- ╚══════════════════════════════════════════════════════════════╝

local computer = require("computer")
local S, K, E, P, F, D, U, SC, NM = {}, nil, nil, nil, nil, nil, nil, nil, nil
local W, H, cwd, who, st = 80, 25, "/", "root", nil
-- #FIX (round 4) — MODULE-level, assigned in S.run. This used to be a
-- `local` inside S.run, declared AFTER the CLI's definition — so every
-- use inside it (logout's tos_logout push, fg's setForeground) silently
-- read a nil GLOBAL instead. A seatless tos_logout is what turned
-- "logout" into a full power-off.
local myDisplayIdx = nil

-- Boot Settings → Interface, resolved once per session. "split" asks for
-- the pre-merge panels: a Shell tab and a separate Desktop tab, with F2
-- cycling between them. It is an escape hatch, not a second design — the
-- merged Home is the default and everything is written against it.
local function uiShape()
  local okB, bcM = pcall(require, "kernel.bootcfg")
  local cfg = _G._TOS and _G._TOS.bootcfg
  if okB and bcM and bcM.ui then return bcM.ui(cfg) end
  return "home"
end

local function ctx()
  return { K = K, E = E, P = P, F = F, D = D, U = U, SC = SC, NM = NM,
           cwd = cwd, who = who, W = W, H = H, st = st,
           uiSplit = uiShape() == "split",
           -- #FIX (round 4) — thread the seat index. Without it the
           -- panels state had S.displayIdx = nil, so `logout` pushed a
           -- seatless tos_logout, which the kernel used to treat as a
           -- GLOBAL logout -> kernel loop exit -> POWER OFF.
           displayIdx = myDisplayIdx }
end

--- Run the command-line shell. Returns "tui" to hand back, or anything
--- else to end the session.
local function runCLI()
  local okC, cliMod = pcall(require, "shell.cli")
  if not okC then
    -- There is nothing to fall back TO from here: the CLI IS the
    -- fallback. Say what broke and end the session — the emergency
    -- terminal is the layer below this one, it shares none of these
    -- dependencies, and that is exactly why it exists.
    D.clear(D.c("bg"))
    D.set(1, 2, "CLI unavailable: " .. tostring(cliMod), D.c("error"), D.c("bg"))
    D.set(1, 3, "Reboot and hold S at POST for Safe Mode.", D.c("warning"), D.c("bg"))
    computer.pullSignal(5)
    return "logout"
  end
  return cliMod.run(ctx())
end

--- Run the panels TUI. Returns "cli" to hand over, nil if it could not
--- load at all, or anything else to end the session.
local function runTUI()
  local ok, pm = pcall(require, "shell.panels")
  if not ok then
    D.clear(D.c("bg"))
    D.set(1, 2, "WARNING: TUI unavailable (" .. tostring(pm) .. ")", D.c("error"), D.c("bg"))
    D.set(1, 3, "Falling back to the command line.", D.c("warning"), D.c("bg"))
    computer.pullSignal(2)
    return nil
  end
  return pm.run(ctx())
end

-- ── Entry point ──────────────────────────────────────────
function S.run(k, token)
  K = k;  st = token
  E = k.getEvent();  P = k.getProc()
  -- Use securefs so every user-initiated FS op goes through ACL checks.
  F = k.getSecureFS() or k.getFS();     D = k.getDisplay()
  U = k.getUsers();  SC = k.getConfig();  NM = k.getNet()
  -- Capture this seat's display index (nil on single-display / global kernel).
  myDisplayIdx = k.getDisplayIdx and k.getDisplayIdx() or nil
  W, H = D.getSize()
  who = "root"
  if U and st then local s = U.getSession(st); if s then who = s.user end end
  cwd = "/home/" .. who
  if not F.exists(cwd) then cwd = "/" end

  -- Operator startup-interface knob (Boot Settings → Interface): "cli"
  -- boots every seat straight to the command line — no panels parse or
  -- load at login, which is the lightest-RAM startup there is. `tui`
  -- still opens the full interface on demand, so it is a default and
  -- never a lockout.
  local mode = (uiShape() == "cli") and "cli" or "tui"

  -- Bounce between the two interfaces until one of them ends the
  -- session. A guard on the count because a handoff loop with no exit
  -- would spin the seat forever with nothing on screen to say why —
  -- and the operator would have no way to interrupt it.
  for _ = 1, 64 do
    local code
    if mode == "cli" then
      code = runCLI()
      if code == "tui" then mode = "tui" else return end
    else
      code = runTUI()
      if code == "cli" or code == nil then mode = "cli" else return end
    end
  end
  -- Fell out of the bounce guard: treat as end of session rather than
  -- leaving the seat in an interface nobody asked for.
end

return S
