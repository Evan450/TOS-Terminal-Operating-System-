-- ╔═══════════════════════════════════════════════════════════════╗
-- ║  TOS Kernel — Notify: a program's way into the operator's face ║
-- ║                                                                ║
-- ║  TOS has two places to say something, and they are not          ║
-- ║  interchangeable:                                               ║
-- ║                                                                 ║
-- ║    THE OUTPUT AREA   above the command line. Polite. You see it ║
-- ║                      when you look. Perfect for results.        ║
-- ║    THE DIALOG BOX    the DOS-style modal — double frame, title  ║
-- ║                      tab, drop shadow, buttons. It is IN YOUR   ║
-- ║                      FACE and blocks until you answer.          ║
-- ║                                                                 ║
-- ║  The dialog box already existed (shell/panels/dialogs.lua), but ║
-- ║  only SHELL code could raise one, because dialogs.dialog needs  ║
-- ║  the shell state `S`. A background service, an add-on's mesh    ║
-- ║  handler, a sandboxed package command — none of them have `S`,  ║
-- ║  and none of them can draw anyway: they run in contexts where   ║
-- ║  another process may own the screen, so painting would corrupt  ║
-- ║  whatever is on it.                                             ║
-- ║                                                                 ║
-- ║  So they POST here instead, and the shell that owns the display ║
-- ║  raises the box. "Listener marks, tick draws" — the same rule   ║
-- ║  the chat tab already follows, generalised so Mail, chat, the   ║
-- ║  Intercom, a cluster job or a package can all use it.           ║
-- ║                                                                 ║
-- ║  THE RATE LIMITS ARE THE LOAD-BEARING PART. A modal that can be ║
-- ║  raised by any program is a way to lock an operator out of      ║
-- ║  their own computer — accidentally, by a service in a retry     ║
-- ║  loop, or deliberately. So this layer enforces a floor no       ║
-- ║  caller can opt out of: a per-source gap, a global quiet window ║
-- ║  after every dismissal, a queue cap, and a TTL so a notice      ║
-- ║  raised while nobody was looking can't ambush someone twenty    ║
-- ║  minutes later. A program's own policy (the Intercom's severity ║
-- ║  cooldown, say) sits ON TOP of this, never underneath it.       ║
-- ║                                                                 ║
-- ║  Everything here is pure except post/settle, and even those are ║
-- ║  clock-injectable — test_notify.lua drives the whole thing with ║
-- ║  no shell, no display and no waiting.                           ║
-- ╚═══════════════════════════════════════════════════════════════╝

local notify = {}

-- ============================================================
-- Limits
-- ============================================================

--- Minimum seconds between two notices from the SAME source. Stops one
--- chatty program from monopolising the operator without affecting others.
notify.MIN_SOURCE_GAP = 10

--- Minimum seconds of quiet after ANY dialog is dismissed, before another
--- may be raised. This is the "you get your keyboard back" guarantee: an
--- operator who just clicked OK can type for at least this long, no matter
--- how many programs want their attention.
notify.MIN_GAP = 3

--- How many undelivered notices to hold. Past this, posting fails loudly
--- rather than growing a queue that would take minutes to click through.
notify.MAX_QUEUE = 8

--- Seconds a notice stays raiseable. A box that appears long after the
--- thing it describes is worse than no box: the operator can't act on it
--- and learns to dismiss without reading.
notify.DEFAULT_TTL = 120

--- Longest a caller may ask to stay pending.
notify.MAX_TTL = 3600

notify.MAX_TITLE   = 40
notify.MAX_MESSAGE = 400
notify.MAX_BUTTONS = 4

-- Styles the shell's dialog renderer understands (dialogs.lua STYLES).
local VALID_STYLES = {
  info = true, warn = true, danger = true, error = true,
  install = true, general = true,
}

-- ============================================================
-- State
-- ============================================================
-- A ring with a MONOTONIC sequence number. Readers keep their own cursor
-- rather than the queue tracking who has seen what, because TOS is
-- multi-seat: two shells must each be able to raise the same notice
-- exactly once, and a queue that popped on first read would let whichever
-- seat ticked first swallow it. Same shape as the intercom spool's rxSeq.

local queue   = {}     -- array of notices, oldest first
local seq     = 0      -- last assigned sequence number
local lastBy  = {}     -- source -> uptime of its last accepted post
local results = {}     -- id -> button index the operator chose

local function now(clock)
  if clock then return clock end
  local ok, computer = pcall(require, "computer")
  if ok and computer and computer.uptime then return computer.uptime() end
  return 0
end

local function log()
  local TOS = _G._TOS or {}
  if TOS.logObj and TOS.logObj.info then return TOS.logObj end
  local ok, mod = pcall(require, "kernel.log")
  if ok and mod and mod.info then return mod end
end

-- ============================================================
-- Posting
-- ============================================================

--- Sanitize a caller's spec into a notice. Pure; returns notice or nil+why.
--- Everything is clamped rather than rejected where clamping is
--- meaningful — a program with a slightly-too-long message should still
--- reach the operator, because the message is usually the point.
function notify.sanitize(spec)
  if type(spec) ~= "table" then return nil, "spec must be a table" end
  local message = spec.message or spec.body
  if type(message) ~= "string" or message == "" then
    return nil, "a notice needs a message"
  end
  local from = tostring(spec.from or "?"):sub(1, 24)
  if from == "" then from = "?" end

  local buttons = {}
  if type(spec.buttons) == "table" then
    for _, b in ipairs(spec.buttons) do
      if type(b) == "string" and b ~= "" and #buttons < notify.MAX_BUTTONS then
        buttons[#buttons + 1] = b:sub(1, 16)
      end
    end
  end
  if #buttons == 0 then buttons = { "OK" } end

  local ttl = tonumber(spec.ttl) or notify.DEFAULT_TTL
  if ttl <= 0 or ttl > notify.MAX_TTL then ttl = notify.DEFAULT_TTL end

  return {
    from    = from,
    title   = tostring(spec.title or from):sub(1, notify.MAX_TITLE),
    message = message:sub(1, notify.MAX_MESSAGE),
    buttons = buttons,
    style   = VALID_STYLES[spec.style or ""] and spec.style or "info",
    ttl     = ttl,
  }
end

--- Raise a dialog on every seat's next idle tick.
---
--- @param spec { message=, title=, from=, buttons=, style=, ttl= }
--- @param clock optional injected uptime (tests)
--- @return id, nil  |  nil, reason
---
--- Failure is NORMAL here and callers must handle it: a refused post means
--- the operator is already being interrupted enough. The message is still
--- logged, so nothing is lost — it just doesn't get to interrupt.
function notify.post(spec, clock)
  local n, why = notify.sanitize(spec)
  if not n then return nil, why end
  local t = now(clock)

  local L = log()
  if L then L.info("notify", "[" .. n.from .. "] " .. n.message) end

  if #queue >= notify.MAX_QUEUE then
    return nil, "too many notices already waiting"
  end
  local last = lastBy[n.from]
  if last and (t - last) < notify.MIN_SOURCE_GAP then
    return nil, string.format("%s posted %.0fs ago (min gap %ds)",
      n.from, t - last, notify.MIN_SOURCE_GAP)
  end

  seq = seq + 1
  n.seq = seq
  n.id  = seq
  n.at  = t
  lastBy[n.from] = t
  queue[#queue + 1] = n
  return n.id
end

-- ============================================================
-- Reading (the shell side)
-- ============================================================

--- Highest sequence number issued. A shell starting mid-life uses this so
--- it doesn't replay a backlog the operator already dealt with elsewhere.
function notify.highWater() return seq end

--- Notices newer than `afterSeq` that are still live. Pure w.r.t. the
--- caller: it does NOT consume anything, so every seat sees each notice.
--- @return list, highSeq
function notify.pending(afterSeq, clock)
  afterSeq = tonumber(afterSeq) or 0
  local t = now(clock)
  local out, high = {}, afterSeq
  for _, n in ipairs(queue) do
    if n.seq > high then high = n.seq end
    if n.seq > afterSeq and (t - n.at) <= n.ttl then out[#out + 1] = n end
  end
  return out, high
end

--- The one notice a shell should raise right now, or nil.
--- Pure given its arguments — this is the whole display policy, so it is
--- testable without a clock or a screen.
--- @return notice|nil, why
function notify.nextToShow(list, lastShownAt, clock)
  local t = now(clock)
  if type(list) ~= "table" or #list == 0 then return nil, "nothing pending" end
  if lastShownAt and (t - lastShownAt) < notify.MIN_GAP then
    return nil, string.format("quiet window (%.0fs of %ds left)",
      notify.MIN_GAP - (t - lastShownAt), notify.MIN_GAP)
  end
  for _, n in ipairs(list) do
    if (t - n.at) <= n.ttl then return n end
  end
  return nil, "everything pending has expired"
end

--- Record which button the operator chose, and drop the notice.
--- Called by the shell that raised it. Dropping here (rather than when it
--- is READ) is what lets several seats show the same notice: the first one
--- answered settles it for everybody, which is the right semantics for
--- "the facility is on fire" and harmless for the rest.
function notify.settle(id, buttonIndex)
  for i, n in ipairs(queue) do
    if n.id == id then
      table.remove(queue, i)
      results[id] = tonumber(buttonIndex) or 1
      return true
    end
  end
  return false
end

--- What the operator picked for a notice this program posted, or nil if
--- they haven't answered (or it expired unanswered). Data, deliberately —
--- not a callback. A callback posted by a service would have to RUN in the
--- shell's context, which is a privilege boundary this facility has no
--- business crossing.
function notify.result(id) return results[id] end

--- Drop expired notices. Called opportunistically by the shell drain; also
--- keeps `results` from growing without bound on a long uptime.
function notify.sweep(clock)
  local t = now(clock)
  local dropped = 0
  for i = #queue, 1, -1 do
    if (t - queue[i].at) > queue[i].ttl then
      table.remove(queue, i); dropped = dropped + 1
    end
  end
  if dropped > 0 then
    local L = log()
    if L then L.info("notify", dropped .. " notice(s) expired unseen") end
  end
  return dropped
end

--- How many notices are waiting (for `doctor` / the Monitor).
function notify.depth() return #queue end

--- Test/reset hook: forget everything.
function notify._reset()
  queue, seq, lastBy, results = {}, 0, {}, {}
end

return notify
