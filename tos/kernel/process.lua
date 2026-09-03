-- TOS Kernel - Process Manager
-- Cooperative multitasking with foreground/background

local computer = require("computer")
local proc = {}

local STATE = {
  RUNNING  = "running",
  READY    = "ready",
  SLEEPING = "sleeping",
  TSR      = "tsr",
  DEAD     = "dead",
}

local processes = {}
local pidCounter = 0
-- #SEC M-11 — monotonic spawn generation. PIDs are reused once a process
-- is reaped; a stale event listener that captured a now-dead PID would
-- otherwise run under whatever NEW process later claims that PID. Each
-- spawn gets a unique, never-reused generation token so the event
-- dispatcher can detect "this PID is no longer the process that
-- registered me" and refuse to run the callback.
local genCounter = 0
local currentPID = nil
local foregroundPID = nil

-- Per-display foreground mapping: display index → PID.
-- When a keyboard event arrives from display N, we deliver it to
-- displayForeground[N] instead of the global foregroundPID.
-- Falls back to foregroundPID if unmapped.
local displayForeground = {}

-- Input signals that only go to foreground process
local INPUT_SIGNALS = {
  key_down = true, key_up = true, clipboard = true,
  touch = true, drag = true, drop = true, scroll = true,
}

-- Screen module reference (lazy-loaded to avoid circular deps at boot)
local screenMod = nil
local function getScreen()
  if screenMod == nil then
    local ok, mod = pcall(require, "kernel.screen")
    screenMod = ok and mod or false
  end
  return screenMod or nil
end

-- ============================================================
-- Runnable-PID cache
-- ============================================================
-- proc.tick used to rebuild and re-sort the full PID list every call.
-- With a couple of processes that's cheap; with a dozen TSR + service
-- processes (rc.d entries, cron, fileshare, chatrelay, plus the shell)
-- it adds up to noticeable per-tick overhead since the table.sort
-- comparator does a property lookup per comparison.
--
-- Cache strategy: maintain a sorted list of non-DEAD PIDs, invalidate
-- via a single boolean (`runnableDirty`) on spawn / kill / mid-tick
-- death. Rebuild only when dirty. Priority changes are rare and would
-- need an explicit setPriority that flips the bit; for now there's no
-- such API, so the cache is correct as long as priority is set at
-- spawn time and never mutated.

local runnableCache = nil
local runnableDirty = true

local function invalidateRunnable() runnableDirty = true end

-- #SEC H13 — listener-dispatch context. When the kernel's main loop
-- pulls a signal and fires user-registered listeners, currentPID is nil
-- (no process is "running" the callback). The old behaviour was to
-- treat nil currentPID as kernel-initiated and skip every permission
-- check — but listener callbacks are registrable by ANY process via
-- compat.event.listen, so an attacker could `proc.signal(anyPid,
-- "key_down", ...)` from a callback to inject keystrokes into another
-- user's foreground process.
--
-- We expose a tri-state for the callers of proc.signal / proc.kill /
-- proc.goTSR:
--   nil           — true kernel-initiated (boot path, scheduler)
--   listenerPID   — a listener callback; uses the registering process's
--                   privileges, not kernel's
--   <real pid>    — normal process context (currentPID)
--
-- The event dispatcher in kernel.event.pull is responsible for setting
-- listenerPID via proc.withListener(pid, fn) before invoking each
-- callback. Code paths that aren't dispatcher-wrapped fall back to
-- currentPID == nil, which kill/signal treat as "no caller" and deny
-- (fail closed — every legitimate kernel path carries a PID).
local listenerPID = nil

function proc.withListener(pid, fn, ...)
  -- Run `fn` with listenerPID bound. Always clears on exit, even on
  -- error, so a buggy listener can't leave the binding "stuck".
  local prev = listenerPID
  listenerPID = pid
  local ok, a, b, c, d = pcall(fn, ...)
  listenerPID = prev
  if not ok then error(a, 0) end
  return a, b, c, d
end

-- #SEC M-11 — current spawn-generation token for `pid`, or nil if no
-- process currently holds that PID. The event dispatcher captures this at
-- listener-registration time and re-checks it before re-entering the
-- callback, so a listener whose registering process has died (and whose
-- PID may have been reused by a different principal) is not run.
function proc.genOf(pid)
  local p = processes[pid]
  return p and p.gen or nil
end

--- Returns the PID that should be charged with the current call, or
--- nil if the call is truly kernel-initiated (scheduler).
local function effectiveCallerPID()
  if currentPID then return currentPID end
  if listenerPID then return listenerPID end
  return nil
end

local function rebuildRunnable()
  local pids = {}
  for pid, p in pairs(processes) do
    if p.state ~= STATE.DEAD then pids[#pids + 1] = pid end
  end
  -- Cache priority during sort so the comparator doesn't do a table
  -- lookup on every comparison (sort is O(n log n) on the comparator).
  local prio = {}
  for _, pid in ipairs(pids) do prio[pid] = processes[pid].priority or 5 end
  table.sort(pids, function(a, b) return prio[a] < prio[b] end)
  runnableCache = pids
  runnableDirty = false
end

-- ============================================================
-- Process creation
-- ============================================================

-- Accept both list-form { "modem_message", "tos_mail" } and set-form
-- { modem_message = true } interest declarations; nil/invalid → nil
-- (= interested in everything, the safe default).
local function buildInterestSet(decl)
  if type(decl) ~= "table" then return nil end
  local set = {}
  local any = false
  for k, v in pairs(decl) do
    if type(k) == "number" and type(v) == "string" then
      set[v] = true; any = true
    elseif type(k) == "string" and v == true then
      set[k] = true; any = true
    end
  end
  return any and set or nil
end

function proc.spawn(name, func, opts)
  opts = opts or {}
  -- #SEC M24 — walk past any PID that's still recorded (defence
  -- against latent counter wrap or a manual `pidCounter = N` from a
  -- debug-tier caller). In practice pidCounter is monotonic and this
  -- loop runs zero times; on the rare day someone does shenanigans
  -- we still won't reuse a live PID.
  repeat
    pidCounter = pidCounter + 1
  until processes[pidCounter] == nil
  local pid = pidCounter
  genCounter = genCounter + 1
  local gen = genCounter  -- #SEC M-11 — unique per-spawn token
  local co = coroutine.create(func)

  -- Identity inheritance from parent (phase 4).
  -- A child cannot gain caps its parent lacked — intersection only.
  local parentProc = currentPID and processes[currentPID] or nil
  local inherit = (opts.inherit ~= false)

  local principal = opts.principal
  local token     = opts.token
  local cwd       = opts.cwd
  local stdin     = opts.stdin
  local stdout    = opts.stdout
  local stderr    = opts.stderr
  local display   = opts.display

  if inherit and parentProc then
    principal = principal or parentProc.principal
    token     = token     or parentProc.token
    cwd       = cwd       or parentProc.cwd
    stdin     = stdin     or parentProc.stdin
    stdout    = stdout    or parentProc.stdout
    stderr    = stderr    or parentProc.stderr
    display   = display   or parentProc.display
  end

  -- Capability intersection. Start from parent caps (or full when we are
  -- the root process) and remove anything the caller didn't request. A
  -- child never gains a cap its parent lacks.
  -- #SEC M23 — when parent exists but has nil caps, treat that as an
  -- empty set: a process with no declared caps should not be a source
  -- of caps for its children. The previous code skipped the intersection
  -- step in that case, so an `opts.caps = { component = true }` request
  -- from a capless parent yielded a child WITH component cap.
  local caps = {}
  if opts.caps then
    for k, v in pairs(opts.caps) do caps[k] = v end
  elseif inherit and parentProc and parentProc.caps then
    for k, v in pairs(parentProc.caps) do caps[k] = v end
  end
  if inherit and parentProc then
    local parentCaps = parentProc.caps or {}
    for k in pairs(caps) do
      if not parentCaps[k] then caps[k] = nil end
    end
  end

  processes[pid] = {
    pid       = pid,
    gen       = gen,  -- #SEC M-11
    name      = name or ("proc_" .. pid),
    coroutine = co,
    state     = STATE.READY,
    tsr       = opts.tsr or false,
    priority  = opts.priority or 5,
    source    = opts.source or "user",
    created   = computer.uptime(),
    lastRun   = 0,
    cpuTime   = 0,
    -- #SEC M31/CORE3 — per-resume Lua-instruction budget. nil = use
    -- scheduler default. math.huge = disable preemption (rare; kernel
    -- daemons that legitimately spin). The scheduler's debug.sethook
    -- in proc.tick reads this field on each resume.
    cpuBudget = opts.cpuBudget,
    -- #REV review finding #9 — optional signal-type interests. nil =
    -- wake on every broadcast signal (the default; nothing changes for
    -- processes that don't declare). A set means: do NOT burn a resume
    -- on a non-input broadcast signal whose type isn't in the set (a
    -- modem flood used to cost one resume per live process per packet).
    -- Directed wakes are never filtered: queued proc.signal deliveries
    -- and foreground input always resume the process.
    signalInterest = buildInterestSet(opts.signalInterest),
    -- Background lifecycle (multitasking pass). nil = the historical
    -- behaviour: a backgrounded process is resumed every tick, exactly
    -- as it always was. Services, shells and daemons leave this unset.
    -- Only full-screen PROGRAMS declare one; see proc.bgShouldResume.
    background = opts.background,
    bgSince    = nil,   -- uptime when it lost the foreground
    bgTicks    = 0,     -- background resumes considered (drives the divisor)
    -- Signal queue implemented as a ring via head/tail pointers so
    -- enqueue/dequeue are both O(1). table.remove(t, 1) would be O(n)
    -- and with 256-entry queues × many processes this dominated the
    -- scheduler on busy seats.
    signals   = {},
    sigHead   = 1,   -- index of next signal to deliver
    sigTail   = 0,   -- index of last enqueued signal (0 = empty)
    env       = {},
    parent    = currentPID,

    -- Phase 4 identity fields
    principal = principal,
    token     = token,
    caps      = caps,
    cwd       = cwd or "/",
    stdin     = stdin,
    stdout    = stdout,
    stderr    = stderr,
    display   = display,
  }
  invalidateRunnable()  -- new process changes the runnable set
  return pid
end

-- ── Cooperative mid-work yield (#REV multi-seat freeze) ─────
-- TOS is a cooperative scheduler: a command that runs to completion in
-- one resume freezes every OTHER seat for its whole duration (and
-- risks the 0.5s wall-budget preempt-kill). Long loops call this every
-- iteration; it only actually yields once the current resume has been
-- running longer than one slice, so the cost of calling it eagerly is
-- a table lookup + uptime compare. The scheduler resumes a
-- cooperatively-yielded process with NOTHING and leaves its signal
-- queue untouched — typed-ahead keys stay queued for the shell's real
-- event loop instead of being eaten by the command's yield point.
local COOP_SLICE = 0.05   -- ~one MC tick of work per slice

-- "Can the current coroutine yield?" — `coroutine.isyieldable` is Lua 5.3+,
-- so on a Lua 5.2 architecture it's nil and a bare check would make
-- yieldCooperative a permanent no-op. TOS already refuses to boot on 5.2
-- (the arch guard in /init.lua), so this is defence-in-depth: fall back to
-- the 5.2-available `coroutine.running()` (returns co, isMain) — yieldable
-- iff we're in a non-main coroutine.
local function canYield()
  if coroutine.isyieldable then return coroutine.isyieldable() end
  local co, isMain = coroutine.running()
  -- 5.2: (co, isMain). 5.1: running() returns nil on the main thread.
  if isMain == true then return false end
  return co ~= nil
end

function proc.yieldCooperative()
  local p = currentPID and processes[currentPID]
  if not p then return false end   -- kernel context: nothing to slice
  if not canYield() then return false end
  if computer.uptime() - (p._resumeStart or 0) < COOP_SLICE then return false end
  p._coopYield = true
  coroutine.yield()
  return true
end

-- Exposed for the regression test (drives the 5.2 fallback with isyieldable
-- temporarily nil'd).
proc._canYield = canYield

--- Declare (or clear, with nil) the CALLING process's signal interests
--- at runtime — same forms as opts.signalInterest at spawn. Self-service
--- only: a process may narrow its own wakes, never another's.
function proc.setSignalInterest(decl)
  local p = currentPID and processes[currentPID]
  if not p then return false, "no current process" end
  p.signalInterest = buildInterestSet(decl)
  return true
end

-- Return the session (principal) of the currently-running process, or
-- nil if none. Wired into securefs.sessionOf() in phase 1 so permission
-- checks follow the process's identity, not a global.
function proc.currentSession()
  local p = proc.current()
  return p and p.principal or nil
end

-- Return the token of the currently-running process.
function proc.currentToken()
  local p = proc.current()
  return p and p.token or nil
end

function proc.current()
  return currentPID and processes[currentPID] or nil
end

function proc.get(pid) return processes[pid] end

function proc.list()
  local result = {}
  for pid, p in pairs(processes) do
    if p.state ~= STATE.DEAD then
      result[#result + 1] = {
        pid = p.pid, name = p.name, state = p.state,
        tsr = p.tsr, priority = p.priority,
        cpuTime = p.cpuTime, source = p.source,
        parent = p.parent,
        -- Phase 4 identity fields
        user = p.principal and p.principal.user or nil,
        cwd  = p.cwd,
        display = p.display,
        sigDropped = p.sigDropped or 0,
      }
    end
  end
  table.sort(result, function(a, b) return a.pid < b.pid end)
  return result
end

-- #SEC H13/H16 — decide whether `caller` (a non-nil process table) may
-- control target process `p` (kill/signal/freeze). A nil principal is a
-- distinct identity that never matches another nil principal, so a
-- principal-less, non-root caller cannot reach principal-less system
-- processes via the old `nil == nil` path. Root (tier 3) and the real
-- kernel path (caller == nil, handled by each call site) bypass this.
local function callerMayControl(caller, p)
  local callerTier = caller.principal and caller.principal.tier or 0
  if callerTier >= 3 then return true end  -- root
  local callerUser = caller.principal and caller.principal.user
  local targetUser = p.principal and p.principal.user
  if callerUser == nil or targetUser == nil then
    -- Either side lacks an identity: only an admin acting strictly
    -- within its own (non-nil) display may proceed.
    return callerTier >= 2 and caller.display ~= nil
       and caller.display == p.display
  end
  if callerTier >= 2 then  -- admin: same-user or same-display
    return callerUser == targetUser or caller.display == p.display
  end
  return callerUser == targetUser  -- regular user / guest: same-user only
end

function proc.kill(pid, opts)
  local p = processes[pid]
  if not p then return false, "No such process" end

  -- #SEC H13 — Permission check: enforce process ownership. A call with
  -- no attributable caller is denied (fail closed); listener callbacks
  -- carry their registering PID's privileges via effectiveCallerPID.
  local callerPid = effectiveCallerPID()
  if not callerPid then
    -- #FIX (logout flicker) — effectiveCallerPID() is nil ONLY in genuine
    -- kernel top-level code (the main loop / scheduler); listener callbacks
    -- always carry a listenerPID. The kernel's OWN lifecycle reaping —
    -- logout, shutdown, hot-unplug, Ctrl+C, the task switcher AFTER its
    -- canAct check — must be able to kill a seat's shell. H13's blanket
    -- no-caller deny left the old shell alive and still drawing over the
    -- new session (the multi-user status-bar flicker the operator saw).
    -- Require an EXPLICIT opts.kernel acknowledgement, so any accidental or
    -- future no-caller path STILL fails closed by default. This is reachable
    -- only from kernel-side code that already holds the proc module
    -- (sandboxes can't require kernel.process; listeners have a listenerPID
    -- and so take the privilege-checked branch below regardless of opts).
    if not (type(opts) == "table" and opts.kernel) then
      return false, "Permission denied (no caller)"
    end
  else
    local caller = processes[callerPid]
    if caller and not callerMayControl(caller, p) then
      return false, "Permission denied"
    end
  end

  p.state = STATE.DEAD
  invalidateRunnable()
  -- If killed process was global foreground, switch to parent or first live
  if pid == foregroundPID then
    if p.parent and processes[p.parent] and processes[p.parent].state ~= STATE.DEAD then
      foregroundPID = p.parent
    else
      proc.cycleForeground()
    end
  end
  -- Clean per-display foreground refs to dead process
  for dIdx, fgPid in pairs(displayForeground) do
    if fgPid == pid then
      if p.parent and processes[p.parent]
         and processes[p.parent].state ~= STATE.DEAD
         and processes[p.parent].display == dIdx then
        displayForeground[dIdx] = p.parent
      else
        displayForeground[dIdx] = nil
      end
    end
  end
  local event = require("kernel.event")
  event.removeSource("proc:" .. pid)
  return true
end

function proc.goTSR(pid)
  local targetPid = pid or currentPID
  local p = processes[targetPid]
  if not p then return false end

  -- #SEC H13 — Permission check: same rules as proc.kill — a non-admin
  -- must not be able to freeze another user's process. Kernel-initiated
  -- calls (scheduler) skip the check; listener callbacks do NOT.
  local callerPid = effectiveCallerPID()
  if pid and callerPid and pid ~= callerPid then
    local caller = processes[callerPid]
    if caller and not callerMayControl(caller, p) then
      return false, "Permission denied"
    end
  end

  p.tsr = true; p.state = STATE.TSR
  return true
end

local MAX_SIGNAL_QUEUE = 256

local function sigCount(p)
  return p.sigTail - p.sigHead + 1
end

-- Enqueue a packed signal into a process's ring buffer (no permission check).
-- Shared by proc.signal (checked) and proc.signalKernel (kernel-context).
local function enqueueSignal(p, ...)
  -- Backfill head/tail for processes created before the ring upgrade.
  if p.sigHead == nil then p.sigHead, p.sigTail = 1, #p.signals end
  -- Drop oldest when the ring is full. Advancing the head is O(1). We
  -- keep a per-process counter so `proc.stats()` surfaces chronic drops
  -- instead of them disappearing silently under sustained load.
  if sigCount(p) >= MAX_SIGNAL_QUEUE then
    p.signals[p.sigHead] = nil
    p.sigHead = p.sigHead + 1
    p.sigDropped = (p.sigDropped or 0) + 1
  end
  p.sigTail = p.sigTail + 1
  p.signals[p.sigTail] = table.pack(...)
  -- Periodically compact the ring so the array doesn't grow unboundedly
  -- under a sustained producer. When the head has advanced past a
  -- threshold and everything before it is empty, rebase to 1.
  if p.sigHead > 256 and p.sigHead <= p.sigTail + 1 then
    local newSignals = {}
    local j = 1
    for i = p.sigHead, p.sigTail do
      newSignals[j] = p.signals[i]
      j = j + 1
    end
    p.signals = newSignals
    p.sigTail = j - 1
    p.sigHead = 1
  elseif p.sigHead > p.sigTail then
    -- Queue drained; reset pointers.
    p.signals = {}
    p.sigHead, p.sigTail = 1, 0
  end
end

function proc.signal(pid, ...)
  local p = processes[pid]
  if not p or p.state == STATE.DEAD then return false end

  -- #SEC H13 — Permission check: a non-root user must not be able to
  -- inject synthetic signals (like "key_down") into another user's
  -- process. A call with no attributable caller is denied (fail
  -- closed); listener callbacks carry their registering PID's tier.
  local callerPid = effectiveCallerPID()
  if not callerPid then
    return false, "Permission denied (no caller)"
  end
  if pid ~= callerPid then
    local caller = processes[callerPid]
    if caller and not callerMayControl(caller, p) then
      return false, "Permission denied"
    end
  end

  enqueueSignal(p, ...)
  return true
end

-- Kernel-context signal: enqueue WITHOUT the no-caller permission check.
-- Reachable only from kernel-side code that already holds the raw proc module
-- (sandboxes can't require kernel.process), mirroring proc.kill{kernel=true}.
-- The kernel loop has no attributable caller PID, so proc.signal() denies it —
-- which is why a kernel dialog (the task switcher) signalling a seat's shell to
-- repaint after it closes did nothing, leaving the dialog drawn over the shell.
function proc.signalKernel(pid, ...)
  local p = processes[pid]
  if not p or p.state == STATE.DEAD then return false end
  enqueueSignal(p, ...)
  return true
end

function proc.setForeground(pid, displayIdx, opts)
  -- #REV multi-seat — kernel bypass, mirroring proc.kill({kernel=true}).
  -- The System Monitor now runs AS a seat process (so it no longer
  -- freezes the box), but its own canAct policy is what gates its
  -- switch/kill/TSR actions — the underlying proc calls must stay
  -- kernel-authorized exactly as they were when the monitor ran modally
  -- in the kernel loop. Only kernel-side code can pass this (proc isn't
  -- reachable from the package sandbox), so it doesn't widen H13.
  if opts and opts.kernel then
    if displayIdx then displayForeground[displayIdx] = pid
    else foregroundPID = pid end
    return true
  end
  -- Permission: caller can only change foreground on their own display (unless root)
  local caller = currentPID and processes[currentPID] or nil
  if caller and displayIdx then
    local callerTier = caller.principal and caller.principal.tier or 0
    if callerTier < 3 and caller.display ~= displayIdx then
      return false, "Permission denied (wrong seat)"
    end
  end
  -- #SEC H13 — also gate the TARGET process. proc.tick routes this seat's
  -- input signals (key_down/touch/...) to displayForeground[dIdx], so a
  -- caller that can name an arbitrary `pid` here can have its OWN keystrokes
  -- delivered to a process it doesn't own — i.e. inject input into another
  -- user's foreground program (privilege escalation). kill/signal/goTSR
  -- already gate the target via callerMayControl; setForeground was the one
  -- H13 entry point that only checked the seat, not the target. Mirror them.
  -- True kernel-initiated calls (boot seat-spawn, kernel.taskSwitcher — both
  -- run with currentPID nil) have `caller == nil` and skip the check, exactly
  -- as the other three do.
  if caller and pid then
    local target = processes[pid]
    -- #REV-3 (critical) — a process may foreground its OWN CHILD on its
    -- OWN seat. This is the login→shell handoff: the seat's login broker
    -- runs as a tier-0 "_login_" principal by design (#135) and spawns
    -- the shell as the authenticated (higher-tier, different-user)
    -- session, so the plain callerMayControl gate denied the handoff —
    -- silently, since the call site ignored the return — leaving the
    -- seat's input routed at the soon-dead login process. The shell
    -- drew its UI but never received a single keystroke: the machine
    -- looked bricked after login. Scope stays narrow (direct child +
    -- same display only); H13's exploit — pointing a seat at an
    -- ARBITRARY victim process — remains blocked.
    local ownChildSameSeat = target ~= nil
      and target.parent == currentPID
      and caller.display ~= nil
      and target.display == caller.display
    if target and not ownChildSameSeat
       and not callerMayControl(caller, target) then
      return false, "Permission denied (not your process)"
    end
  end
  if displayIdx then
    displayForeground[displayIdx] = pid
  else
    foregroundPID = pid
  end
  return true
end

function proc.getForeground(displayIdx)
  if displayIdx then
    return displayForeground[displayIdx] or foregroundPID
  end
  return foregroundPID
end

--- Cycle foreground to next live process
function proc.cycleForeground()
  local pids = {}
  for pid, p in pairs(processes) do
    if p.state ~= STATE.DEAD then pids[#pids + 1] = pid end
  end
  table.sort(pids)
  if #pids == 0 then foregroundPID = nil return end
  -- Find current index and advance
  local idx = 1
  for i, pid in ipairs(pids) do
    if pid == foregroundPID then idx = i break end
  end
  idx = (idx % #pids) + 1
  foregroundPID = pids[idx]
  return foregroundPID
end

-- ============================================================
-- Scheduler
-- ============================================================

-- Preemption watchdog breadcrumb (#REV review finding #2). Written the
-- FIRST time a process blows its wall-clock budget, removed as soon as
-- the scheduler regains control. If it still exists at next boot, the
-- machine died to OC's "too long without yielding" watchdog and this
-- names the culprit (doctor's power section surfaces it). Best-effort:
-- raw writes, fully pcall'd — a failed write just loses attribution.
local PREEMPT_CRUMB = "/var/crash/preempt.txt"

--- Can the scheduler actually preempt on this host?
---
--- False on OpenComputers, which does not export debug.sethook (see the long
--- note at the resume site). Exposed so `doctor`, `ps` and the tests can
--- state the real position instead of inheriting an assumption: a caller that
--- wants to promise "a runaway process gets killed" has to ask first.
function proc.preemptionAvailable()
  return type(debug) == "table" and type(debug.sethook) == "function"
end

local function preemptCrumb(p)
  pcall(function()
    local f = _G._TOS and _G._TOS.fs
    if not f or not f.writeFile then return end
    pcall(f.makeDirectory, "/var/crash")
    f.writeFile(PREEMPT_CRUMB,
      "pid=" .. tostring(p.pid) .. " name=" .. tostring(p.name or "?") ..
      " user=" .. tostring(p.principal and p.principal.user or "?") ..
      " uptime=" .. tostring(computer.uptime()) .. "\n" ..
      "This process exceeded its CPU budget and trapped the preemption\n" ..
      "error; if the machine then rebooted via the OC watchdog, it was\n" ..
      "the likely cause.\n")
  end)
end

local function clearPreemptCrumb()
  pcall(function()
    local f = _G._TOS and _G._TOS.fs
    if f and f.remove and f.exists and f.exists(PREEMPT_CRUMB) then
      f.remove(PREEMPT_CRUMB)
    end
  end)
end

-- Once a process has blown its budget AND trapped the kill error, this
-- replaces the counting hook at count=1: every instruction raises, so
-- the trap loop starves instead of computing (see the hook body below).
local function starveHook()
  error("scheduler: preempted (wall-clock budget exceeded)", 0)
end

-- ============================================================
-- Background lifecycle for full-screen PROGRAMS
-- ============================================================
-- A program launched from the shell (calc, tetris, a game) used to own
-- the seat until it exited, because it ran inside the shell's own loop.
-- Run as its own process it can instead be pushed to the background —
-- but "background" for a program should not mean "runs flat out forever
-- drawing nothing".
--
-- Operator's policy, three states:
--   live    — it has the foreground: full rate, every tick.
--   drowsy  — just backgrounded: every Nth tick, so stepping away for a
--             moment and coming back finds it still running.
--   frozen  — backgrounded long enough that nobody is watching: not
--             resumed at all, costing exactly nothing.
--
-- A package may override the middle: "always" never freezes (it stays
-- drowsy indefinitely), "freeze" skips drowsy and stops the moment you
-- leave. No declaration at all (`background == nil`) means the process
-- is not a program — services, shells and daemons keep the historical
-- every-tick behaviour untouched.
--
-- A frozen process is NOT unreachable: queued/directed signals always
-- resume it, which is how tos_focus wakes it when you switch back.

proc.BG_DIVISOR = 2     -- drowsy: resume on every 2nd background tick
proc.BG_GRACE   = 30    -- seconds of drowsy before freezing

--- PURE — the background decision, split out so it can be tested without
--- a scheduler. Returns (resume, state) where state is "drowsy"|"frozen".
--- `policy` nil is handled by the caller (no policy = always resume).
function proc.bgShouldResume(policy, bgSeconds, bgTicks)
  bgSeconds = bgSeconds or 0
  bgTicks   = bgTicks or 0
  if policy == "freeze" then return false, "frozen" end
  -- "drowsy" (the default) freezes once nobody has come back for a while;
  -- "always" keeps the reduced rate forever.
  if policy ~= "always" and bgSeconds >= proc.BG_GRACE then
    return false, "frozen"
  end
  return (bgTicks % proc.BG_DIVISOR) == 0, "drowsy"
end

--- Mark a program foregrounded/backgrounded. The policy clock starts the
--- moment the seat looks away.
local function markBackground(p, isForeground, now)
  if not p or not p.background then return end
  if isForeground then
    p.bgSince, p.bgTicks = nil, 0
  elseif not p.bgSince then
    p.bgSince, p.bgTicks = now or computer.uptime(), 0
  end
end

--- The lifecycle state of a process, for `ps` and the Monitor: "live"
--- for anything without a background policy or currently in front.
function proc.bgState(pid, now)
  local p = processes[pid]
  if not p or not p.background or not p.bgSince then return "live" end
  local _, state = proc.bgShouldResume(p.background,
    (now or computer.uptime()) - p.bgSince, p.bgTicks)
  return state
end

--- Should this tick skip a backgrounded program? Advances the process's
--- own background tick counter as a side effect, so the divisor counts
--- ticks the program was ELIGIBLE for rather than wall time.
--- Never skips a process with queued signals: that is the wake path
--- (tos_focus, tos_kill) and it must survive a freeze.
local function bgSkipped(p, pid, inputFgPID)
  if not p.background then return false end          -- not a program
  -- "Is it in front?" must be asked of the process's OWN SEAT. Checking
  -- inputFgPID alone was wrong: on a tick carrying no input (or input
  -- for another seat) that variable falls back to the GLOBAL foreground,
  -- so a program in front on seat 2 read as backgrounded and ran at half
  -- rate while the operator was looking straight at it.
  local seatFg = p.display and displayForeground[p.display] or nil
  if pid == seatFg or (not p.display and pid == foregroundPID)
     or pid == inputFgPID then
    markBackground(p, true)
    return false
  end
  -- Directed wake pending (tos_focus / tos_kill): never skip. sigHead is
  -- normalised lazily in proc.tick, so tolerate it being unset here.
  if (p.sigTail or 0) >= (p.sigHead or 1) then return false end
  markBackground(p, false)
  local resume = proc.bgShouldResume(p.background,
    computer.uptime() - (p.bgSince or 0), p.bgTicks)
  p.bgTicks = p.bgTicks + 1
  return not resume
end

-- #REV review finding #9 — should this wake be skipped entirely? True
-- only when ALL of: the process declared interests, the tick carries a
-- non-input broadcast signal, that signal's type isn't in the set, and
-- no directed signals are queued (those must always deliver). Input
-- ticks are exempt — the input path already routes them to the
-- foreground only, and background processes rely on those nil resumes
-- to do cooperative work.
local function wakeSkipped(p, signal, isInput)
  if not p.signalInterest then return false end
  if p._coopYield then return false end  -- mid-work slice: must resume
  if isInput or not signal or signal[1] == nil then return false end
  if p.sigHead == nil then p.sigHead, p.sigTail = 1, #p.signals end
  if p.sigTail >= p.sigHead then return false end
  return not p.signalInterest[signal[1]]
end

function proc.tick(signal)
  -- Pull the cached PID list, rebuilding only if something invalidated
  -- it since last tick (spawn / kill / mid-tick death).
  if runnableDirty then rebuildRunnable() end
  local pids = runnableCache

  -- Determine if this is an input signal (keyboard/mouse)
  local isInput = signal and signal[1] and INPUT_SIGNALS[signal[1]]

  -- Multi-screen: resolve which display this input belongs to, and
  -- which process is foreground on that display.
  -- OC signal layout: key_down/key_up/clipboard have keyboard addr in [2],
  -- while touch/drag/drop/scroll have screen addr in [2].
  local inputFgPID = foregroundPID
  if isInput and signal[2] then
    local scr = getScreen()
    if scr then
      local dIdx
      local sigType = signal[1]
      if sigType == "key_down" or sigType == "key_up" or sigType == "clipboard" then
        dIdx = scr.displayForKeyboard(signal[2])
      elseif sigType == "touch" or sigType == "drag" or sigType == "drop" or sigType == "scroll" then
        dIdx = scr.displayForScreen(signal[2])
      end
      if dIdx then
        inputFgPID = displayForeground[dIdx] or foregroundPID
      end
    end
  end

  for _, pid in ipairs(pids) do
    local p = processes[pid]
    if p and p.state ~= STATE.DEAD then
      local co = p.coroutine
      -- Cache coroutine.status: it crosses the C/Lua boundary on each
      -- call, so doing it once per process per tick (vs the original
      -- two calls in the dead-or-suspended branch) is a small but free
      -- improvement.
      local coStatus = coroutine.status(co)
      if coStatus == "dead" then
        p.state = STATE.DEAD
        invalidateRunnable()
      elseif coStatus == "suspended" and wakeSkipped(p, signal, isInput) then
        -- Declared interests exclude this broadcast type — don't burn a
        -- resume. (Queued/directed signals and input ticks still wake.)
      elseif coStatus == "suspended" and bgSkipped(p, pid, inputFgPID) then
        -- A backgrounded PROGRAM that is drowsy-between-ticks or frozen.
        -- Its counter advanced inside bgSkipped; a queued signal would
        -- have overridden this, so it can always be woken by tos_focus.
      elseif coStatus == "suspended" then
        currentPID = pid
        p.state = STATE.RUNNING
        local startTime = computer.uptime()
        -- Slice reference for proc.yieldCooperative (elapsed-this-resume).
        p._resumeStart = startTime

        -- Determine what data to pass to this process
        local resumeData = nil
        if p.sigHead == nil then p.sigHead, p.sigTail = 1, #p.signals end
        if p._coopYield then
          -- Mid-work cooperative slice: resume with NOTHING and leave
          -- the signal queue alone (see proc.yieldCooperative). The
          -- command picks up exactly where it left off.
          p._coopYield = false
        elseif p.sigTail >= p.sigHead then
          -- Process has queued signals - deliver those first. O(1) pop
          -- from the head of the ring; compaction handled in proc.signal.
          resumeData = p.signals[p.sigHead]
          p.signals[p.sigHead] = nil
          p.sigHead = p.sigHead + 1
        elseif isInput then
          -- Input signals: ONLY to the foreground process on the
          -- relevant display (multi-screen) or the global foreground.
          if pid == inputFgPID then
            resumeData = signal
          end
          -- Background processes get nil (still resumed to do work)
        else
          -- Non-input signals (modem, component, timer): everyone
          resumeData = signal
        end

        --! PREEMPTION DOES NOT HAPPEN ON OPENCOMPUTERS. Everything below
        --! hangs off debug.sethook, and OC's sandbox does not export it:
        --! machine.lua's `debug = {` table is exactly getinfo, traceback,
        --! getlocal and getupvalue. The machine keeps sethook for its own
        --! "too long without yielding" deadline and does not hand guest code
        --! a way to disarm that. So `debug.sethook` is nil, the guard below
        --! is false, and no budget is ever armed.
        --!
        --! The comment that follows was written believing otherwise: it said
        --! the hook was available "on every Lua version OC ships" and that
        --! the wall-clock fallback therefore worked here. The reasoning about
        --! yielding across a C boundary is correct and worth keeping; the
        --! conclusion drawn from it is not.
        --!
        --! What actually bounds a runaway process on OC is the machine
        --! watchdog, which kills the WHOLE COMPUTER rather than the process
        --! -- which is precisely the "blast radius" this code was written to
        --! shrink, and does not. The preemptCrumb breadcrumb below still
        --! earns its keep for exactly that reason: on OC the watchdog reboot
        --! IS the outcome, so a note naming the culprit is the only thing
        --! that survives to explain it -- except that it too is only written
        --! from inside the hook, so it never fires either.
        --!
        --! Kept rather than deleted: it is correct on any host that does
        --! export sethook (every off-box test run, and the suite exercises
        --! it), and TOS is not exclusively an OC target in principle. But
        --! nothing may describe this as a live guarantee. (test_sethook_absent.lua)
        --
        -- #SEC M31/CORE3 — Preemptive scheduling, wall-clock variant.
        -- The original plan was to install a `debug.sethook` count hook
        -- that yielded the coroutine after N instructions, but Lua's
        -- `coroutine.yield` raises "attempt to yield across a C-call
        -- boundary" from inside a hook on every Lua version OC ships
        -- (the hook runs in the C VM's instruction loop). We fall back
        -- to a wall-clock approach that works wherever sethook exists:
        --
        --   1. Record start time before the resume.
        --   2. Use debug.sethook to install a hook that, after the
        --      coroutine has been running for too long, calls
        --      error("preempted") — that's allowed from a hook on
        --      every Lua version.
        --   3. The coroutine dies; the scheduler sees state=DEAD on
        --      next tick and reclaims the slot. The user gets a clear
        --      "process killed: scheduler preemption" entry in the log.
        --
        -- This is heavier-handed than instruction preemption (the
        -- process dies rather than yielding), but it's defensive of
        -- LAST RESORT: a well-behaved process voluntarily yields long
        -- before the budget.
        --
        -- WHAT THIS COMMENT USED TO SAY, AND WHY IT WAS WRONG.
        -- It concluded "real preemption (no kill) needs C-side support
        -- OC doesn't provide." The premise above is true — you cannot
        -- yield from inside a debug hook — but the conclusion does not
        -- follow, and Ocawesome101's Cynosure 2 is the counter-example:
        -- it gets yield-not-kill preemption with no hook at all. Its
        -- loader REWRITES THE SOURCE before loading, injecting a
        -- sysyield() call at every loop header, function entry and goto
        -- label, so the yield happens in ordinary Lua and never crosses
        -- a C boundary. The hook was never the only way in.
        --
        -- We are NOT adopting it, on three counts and none of them is
        -- "impossible":
        --   * the rewriter is a regex approximation of a Lua lexer. It
        --     does not handle comments at all — they survive by
        --     accident, because --[[ happens to look like a long string
        --     to its scanner;
        --   * every load() pays a full-source rewrite, slow enough that
        --     Cynosure has to yield INSIDE the rewriter to dodge OC's
        --     5-second watchdog;
        --   * every function entry pays a call plus an uptime compare,
        --     forever, on a box where the memory gate is already tight.
        --
        -- It is recorded rather than deleted because there is one class
        -- where the trade might invert later: untrusted PACKAGE code,
        -- where killing something mid-write is worse than slowing it
        -- down. If that day comes, this is the technique — the option is
        -- open, and the old comment claimed it was closed.
        --
        --   * Budget is per RESUME wall-clock time, in seconds.
        --   * Per-process tunable via opts.cpuBudget at spawn time
        --     (in seconds — different unit from the design-doc draft
        --     since we're wall-clock not instruction count).
        --   * math.huge disables preemption for kernel daemons.
        local PROC_WALL_BUDGET = 0.5  -- 500 ms — well above any
                                       -- legitimate cooperative resume.
        local budget = (p.cpuBudget == nil) and PROC_WALL_BUDGET or p.cpuBudget
        local hookInstalled = false
        local hookFired = false
        if budget ~= math.huge and type(debug) == "table" and debug.sethook then
          local deadline = startTime + budget
          local ok2 = pcall(debug.sethook, co, function()
            if computer.uptime() > deadline then
              -- #REV review finding #2 — the raised error is an ordinary
              -- Lua error, so a process spinning inside its OWN pcall
              -- traps it and never returns control; the whole machine
              -- then dies to OC's "too long without yielding" watchdog.
              -- Full preemption isn't achievable in pure Lua (yield
              -- can't cross the C hook boundary), so shrink the blast
              -- radius instead, once, on the first firing:
              --   1. persist a breadcrumb naming the culprit, so the
              --      otherwise-unattributed watchdog reboot can be
              --      pinned on this process next boot (doctor reads it);
              --   2. re-arm the hook at count=1 — every subsequent
              --      instruction raises, so a pcall trap makes ~zero
              --      forward progress (hostile → merely wasteful).
              if not hookFired then
                hookFired = true
                p._preempted = true
                preemptCrumb(p)
                pcall(debug.sethook, starveHook, "", 1)
              end
              error("scheduler: process exceeded wall-clock budget (" ..
                budget .. "s)", 0)
            end
          end, "", 10000)  -- check every 10k instructions; cheap
          if ok2 then hookInstalled = true end
        end

        local ok, result
        if resumeData then
          ok, result = coroutine.resume(co, table.unpack(resumeData, 1, resumeData.n or #resumeData))
        else
          ok, result = coroutine.resume(co)
        end

        -- Tear down the hook so its budget doesn't leak across resumes.
        if hookInstalled then
          pcall(debug.sethook, co)
        end
        if hookFired then
          -- Control came back — the preemption resolved cleanly (the
          -- process died or finally yielded), no watchdog reboot. Drop
          -- the breadcrumb: it must only survive when the machine died
          -- before this line ran, so its presence at next boot MEANS
          -- "watchdog death, and here's who caused it".
          clearPreemptCrumb()
        end

        p.cpuTime = p.cpuTime + (computer.uptime() - startTime)
        p.lastRun = computer.uptime()

        if not ok then
          p.state = STATE.DEAD
          p.error = tostring(result)
          invalidateRunnable()
        elseif coroutine.status(co) == "dead" then
          p.state = STATE.DEAD
          invalidateRunnable()
        else
          p.state = p.tsr and STATE.TSR or STATE.READY
        end
        currentPID = nil
      end
    end
  end

  -- Free coroutine refs on dead processes so they can be GC'd immediately
  for _, p in pairs(processes) do
    if p.state == STATE.DEAD and p.coroutine then
      p.coroutine = nil
    end
  end
  -- GC dead processes (keep last 3)
  local deadPIDs = {}
  for pid, p in pairs(processes) do
    if p.state == STATE.DEAD then deadPIDs[#deadPIDs + 1] = pid end
  end
  if #deadPIDs > 3 then
    table.sort(deadPIDs)
    for i = 1, #deadPIDs - 3 do
      processes[deadPIDs[i]] = nil
    end
  end

  -- Clean stale displayForeground entries pointing to dead/GC'd processes
  for dIdx, fgPid in pairs(displayForeground) do
    if not processes[fgPid] or processes[fgPid].state == STATE.DEAD then
      local deadP = processes[fgPid]
      if deadP and deadP.parent and processes[deadP.parent]
         and processes[deadP.parent].state ~= STATE.DEAD
         and processes[deadP.parent].display == dIdx then
        displayForeground[dIdx] = deadP.parent
      else
        displayForeground[dIdx] = nil
      end
    end
  end
end

--- Yield current process (safe from main thread)
function proc.yield()
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
end

--- Sleep (yields repeatedly until deadline)
function proc.sleep(seconds)
  local deadline = computer.uptime() + seconds
  while computer.uptime() < deadline do
    if coroutine.isyieldable and coroutine.isyieldable() then
      coroutine.yield()
    else
      computer.pullSignal(math.min(0.05, deadline - computer.uptime()))
    end
  end
end

function proc.count()
  local alive = 0
  for _, p in pairs(processes) do
    if p.state ~= STATE.DEAD then alive = alive + 1 end
  end
  return alive
end

proc.STATE = STATE
return proc
