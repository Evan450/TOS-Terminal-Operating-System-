-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS mouse driver  (require("mouse"))                      ║
-- ║                                                            ║
-- ║  TOS, like MS-DOS, has no baked-in mouse support: the      ║
-- ║  shell only reads the keyboard. OpenComputers screens DO   ║
-- ║  emit touch/drag/drop/scroll signals, though, so this is   ║
-- ║  a small DOS-style "mouse driver": a library a program     ║
-- ║  require()s to turn those raw signals into clean mouse     ║
-- ║  events, plus rectangle hit-testing for click targets.     ║
-- ║                                                            ║
-- ║  It is pure userspace — it only reads computer.pullSignal  ║
-- ║  (granted by the `component` capability) and never touches  ║
-- ║  the kernel. Install it from the Optional Utilities disk.   ║
-- ║                                                            ║
-- ║  The panels shell auto-detects this driver (see TOS's      ║
-- ║  shell.panels.mouse): once installed, menus, tabs, the     ║
-- ║  file list, dialogs and the editor become click/scroll-    ║
-- ║  able. No configuration needed — install and click.        ║
-- ║                                                            ║
-- ║  Quick use:                                                ║
-- ║    local mouse = require("mouse")                          ║
-- ║    local ev = mouse.pull(0.5)   -- nil on timeout          ║
-- ║    if ev and ev.type == "click" then                      ║
-- ║      print(("click @ %d,%d btn %d"):format(ev.x,ev.y,ev.button)) ║
-- ║    end                                                     ║
-- ╚══════════════════════════════════════════════════════════╝

local mouse = {}

-- OpenComputers mouse signal shapes (1-based character-cell coords):
--   touch  (screen, x, y, button, player)   button 0=left 1=right
--   drag   (screen, x, y, button, player)
--   drop   (screen, x, y, button, player)
--   scroll (screen, x, y, direction, player) direction 1=up -1=down
-- mouse.parse maps a raw signal tuple to a normalized event, or nil for
-- any non-mouse signal. It is PURE (no I/O), so it can be unit-tested
-- off-box and reused by callers that run their own pullSignal loop.
function mouse.parse(name, screen, x, y, k, player)
  if name == "touch" then
    return { type = "click", x = x, y = y, button = k or 0,
             screen = screen, player = player }
  elseif name == "drag" then
    return { type = "drag", x = x, y = y, button = k or 0,
             screen = screen, player = player }
  elseif name == "drop" then
    return { type = "drop", x = x, y = y, button = k or 0,
             screen = screen, player = player }
  elseif name == "scroll" then
    -- Normalize direction to +1 (up / away) or -1 (down / toward).
    local dir = (k or 0) >= 0 and 1 or -1
    return { type = "scroll", x = x, y = y, dir = dir,
             screen = screen, player = player }
  end
  return nil
end

-- True if this event type carries pointer coordinates (everything we emit
-- does — provided for callers that compose their own filters).
function mouse.isMouse(name)
  return name == "touch" or name == "drag"
      or name == "drop"  or name == "scroll"
end

-- Block until a MOUSE event arrives or `timeout` seconds elapse. Non-mouse
-- signals (key_down, timers, modem traffic) are swallowed so the caller
-- gets a clean stream — but if you also need keyboard input, run your own
-- pullSignal loop and feed each signal to mouse.parse instead (see the
-- `mousetest` demo). Returns the event table, or nil on timeout.
function mouse.pull(timeout)
  local computer = require("computer")
  local deadline = computer.uptime() + (timeout or math.huge)
  repeat
    local remaining = deadline - computer.uptime()
    if remaining < 0 then remaining = 0 end
    local sig = table.pack(computer.pullSignal(remaining))
    local ev = mouse.parse(table.unpack(sig, 1, sig.n))
    if ev then return ev end
  until computer.uptime() >= deadline
  return nil
end

-- ── Hit-testing for click targets ──────────────────────────
-- A "region" is an inclusive rectangle in screen cells. Build a list of
-- them (each with your own payload) and ask which one an event landed in —
-- the basic primitive behind clickable buttons/menus.
function mouse.region(x, y, w, h, payload)
  return { x = x, y = y, w = w, h = h, payload = payload }
end

-- True if point (px,py) is inside region r.
function mouse.inside(r, px, py)
  return px >= r.x and px <= r.x + r.w - 1
     and py >= r.y and py <= r.y + r.h - 1
end

-- Return the payload of the FIRST region containing (px,py), or nil.
-- Later-added regions are checked last, so draw back-to-front and the
-- topmost overlapping target should be added first.
function mouse.hit(regions, px, py)
  for _, r in ipairs(regions) do
    if mouse.inside(r, px, py) then return r.payload, r end
  end
  return nil
end

mouse._VERSION = "1.1.0"
return mouse
