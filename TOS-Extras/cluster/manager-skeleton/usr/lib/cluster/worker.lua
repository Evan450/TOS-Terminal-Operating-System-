-- ╔══════════════════════════════════════╗
-- ║  TOS Cluster Worker Bridge           ║
-- ║  Manager ↔ OpenOS Worker comms       ║
-- ╚══════════════════════════════════════╝
-- OpenOS workers don't speak the TOS protocol. Per the cluster spec §2.1
-- the Manager ↔ Worker channel uses raw OC modem traffic on port
-- `2001 + domain_id`. This module implements the Manager side: register
-- incoming workers, track their lifecycle, dispatch tasks, collect
-- results, and ping idle workers.
--
-- Wire format (Lua table literal via kernel.serialize — OpenOS can encode
-- and decode this with its stock serialization.serialize):
--
--   Worker → Manager:
--     { magic="WRK", op="REGISTER",   hostname=<s>, capabilities=<t> }
--     { magic="WRK", op="RESULT",     task_id=<n>, status=<s>,
--                                     output=<s>, err=<s|nil> }
--     { magic="WRK", op="PROGRESS",   task_id=<n>, progress=<0..1>, msg=<s> }
--     { magic="WRK", op="PONG",       time=<n> }
--
--   Manager → Worker:
--     { magic="WRK", op="REGISTER_ACK", worker_id=<n>, accepted=<b>, reason=<s|nil> }
--     { magic="WRK", op="TASK",         task_id=<n>, code=<s>, inputs=<t>,
--                                       timeout=<n> }
--     { magic="WRK", op="CANCEL",       task_id=<n> }
--     { magic="WRK", op="PING",         time=<n> }
--
-- Trust model: per spec §1.2, Workers are identified by modem address.
-- TOS trust levels do NOT apply — workers are OpenOS, outside the trust
-- system. During the bootstrap window any address that registers is
-- accepted. After the window, only addresses already in the worker list
-- are accepted.

local computer = require("computer")
local component = require("component")
local serialize = require("kernel.serialize")
local cluster   = require("cluster.protocol")

local cworker = {}

-- Module refs (set in init)
local log, event = nil, nil

-- ============================================================
-- State
-- ============================================================

local MAGIC = "WRK"

local domainId     = nil            -- set via setDomainId
local workerPort   = nil            -- 2001 + domainId
local nextWorkerId = 1
local nextTaskId   = 1

-- workers[addr] = {
--   id              = <n>,
--   state           = "idle"|"busy"|"unresponsive",
--   hostname        = <s>,
--   capabilities    = <t>,
--   last_seen       = <uptime>,
--   pings_missed    = <n>,
--   current_task    = <task_id|nil>,
--   last_ping_sent  = <uptime|nil>,
-- }
local workers = {}

-- tasks[task_id] = {
--   worker_addr = <addr>,
--   sent_at     = <uptime>,
--   timeout     = <n>,
--   code        = <s>,  -- kept for re-dispatch if needed
--   on_result   = <fn|nil>,  -- per-task callback
-- }
local tasks = {}

-- Bootstrap window end (uptime). nil = closed, workers are rejected.
local bootstrapUntil = nil

-- #SEC H21 — shared-secret HMAC over every WRK frame. The audit flagged
-- that "any device on the OC net can REGISTER" and that result handlers
-- run `pcall(cb, ...)` on attacker-supplied output. We add an optional
-- (recommended) shared secret per cluster: when set, every incoming
-- frame must carry a valid HMAC over (op || task_id || nonce) and
-- duplicate nonces are rejected. Operators configure the secret via
-- cluster_worker.setSecret().
local sharedSecret = nil
local seenNonces   = {}        -- ring buffer of accepted nonces
local seenOrder    = {}
local SEEN_MAX     = 1024

--- Configure the cluster-wide shared secret used to authenticate WRK
-- frames. Pass nil to disable authentication (legacy mode — not
-- recommended; the audit flagged this as a remote-code-execution
-- vector via the result callback path).
function cworker.setSecret(secret)
  if secret == nil then
    sharedSecret = nil
    return true
  end
  if type(secret) ~= "string" or #secret < 16 then
    return false, "secret must be a string of at least 16 bytes"
  end
  sharedSecret = secret
  return true
end

-- Registered listener IDs so we can unbind cleanly on stop.
local listenerIds   = {}
local pingTimerId   = nil
local timeoutTimerId = nil

-- Global result callback (optional). Called as cb(workerAddr, taskId, result).
local resultCb = nil

-- Modem proxies collected at init() time.
local modems = {}

-- ============================================================
-- Helpers
-- ============================================================

local function logf(lvl, fmt, ...)
  if not log then return end
  local msg = string.format(fmt, ...)
  if lvl == "warn" and log.warn then log.warn("cworker", msg)
  elseif lvl == "info" and log.info then log.info("cworker", msg)
  elseif lvl == "debug" and log.debug then log.debug("cworker", msg)
  end
end

-- #SEC H2 — canonical, length-prefixed serialization for the frame
-- HMAC. The previous MAC only covered op||task_id||nonce, leaving every
-- other field (payload, result, accepted, reason, hostname, ...)
-- unauthenticated: an attacker who observed those three values could
-- forge a frame with arbitrary payload/result that still passed the MAC
-- check, and that payload is later pcall'd into TOS handlers.
--
-- We cannot MAC serialize.compact() directly because it iterates with
-- pairs() (non-deterministic key order), so sender and receiver would
-- disagree. canonicalFrame sorts keys and length-prefixes every scalar
-- so the encoding is unambiguous (no delimiter-injection collisions)
-- and identical on both ends regardless of table iteration order.
local function canonicalFrame(v)
  local t = type(v)
  if t == "string" then
    return "s" .. #v .. ":" .. v
  elseif t == "number" then
    local s = tostring(v)
    return "n" .. #s .. ":" .. s
  elseif t == "boolean" then
    return v and "bT" or "bF"
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do
      if k ~= "mac" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      return a < b
    end)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = canonicalFrame(k) .. canonicalFrame(v[k])
    end
    return "{" .. table.concat(parts) .. "}"
  end
  return "z"  -- nil / unsupported type
end

--- Send a frame to a specific modem address on the worker port. We loop
-- over every modem NIC so multi-modem Managers (server racks) reach the
-- worker regardless of which NIC physically sees them.
local function sendFrame(address, frame)
  if not workerPort then return false, "domain_id not set" end
  frame.magic = MAGIC
  -- #SEC H2/H21 — sign outgoing frames when a shared secret is set. The
  -- HMAC now covers the WHOLE frame (canonicalFrame, every field except
  -- `mac` itself), not just op||task_id||nonce, so payload/result fields
  -- can't be tampered past the MAC. A fresh per-frame nonce stops a
  -- captured frame being replayed.
  if sharedSecret then
    local okC, cryptoMod = pcall(require, "kernel.crypto")
    if okC and cryptoMod and cryptoMod.hmac and cryptoMod.salt then
      frame.nonce = cryptoMod.salt(16)
      frame.mac   = cryptoMod.hmac(sharedSecret, canonicalFrame(frame))
    end
  end
  local data = serialize.compact(frame)
  local anyOk = false
  for _, m in ipairs(modems) do
    local ok = pcall(m.send, address, workerPort, data)
    anyOk = anyOk or ok
  end
  if not anyOk then return false, "send failed on all NICs" end
  return true
end

--- Collect every modem proxy we can see. This mirrors net/init.lua's
-- multi-NIC logic but owns its own modem.open(workerPort) so we don't
-- rely on the main net layer to have opened this port.
local function collectModems()
  modems = {}
  for addr in component.list("modem") do
    local ok, proxy = pcall(component.proxy, addr)
    if ok and proxy then
      modems[#modems + 1] = proxy
    end
  end
end

local function openPortOnAllModems(port)
  for _, m in ipairs(modems) do
    pcall(m.open, port)
  end
end

local function closePortOnAllModems(port)
  for _, m in ipairs(modems) do
    pcall(m.close, port)
  end
end

-- ============================================================
-- Incoming frame handlers
-- ============================================================

local function handleRegister(addr, frame)
  local existing = workers[addr]

  if not existing then
    -- Brand-new address: only accept during bootstrap window.
    if not bootstrapUntil or computer.uptime() > bootstrapUntil then
      sendFrame(addr, {
        op       = "REGISTER_ACK",
        accepted = false,
        reason   = "bootstrap window closed",
      })
      logf("warn", "Rejected worker %s: bootstrap closed", addr:sub(1, 8))
      return
    end

    local wid = nextWorkerId
    nextWorkerId = nextWorkerId + 1
    workers[addr] = {
      id             = wid,
      state          = "idle",
      hostname       = tostring(frame.hostname or "worker-" .. wid),
      capabilities   = type(frame.capabilities) == "table" and frame.capabilities or {},
      last_seen      = computer.uptime(),
      pings_missed   = 0,
      current_task   = nil,
      last_ping_sent = nil,
    }
    sendFrame(addr, {
      op        = "REGISTER_ACK",
      accepted  = true,
      worker_id = wid,
    })
    logf("info", "Registered worker %d (%s) at %s",
      wid, workers[addr].hostname, addr:sub(1, 8))
    return
  end

  -- #SEC H21 — refuse re-REGISTER while a task is in flight. The old
  -- behaviour cleared `current_task` and called the task lost, which
  -- meant any attacker spoofing the worker's address could abort
  -- in-flight work and force a re-dispatch they could then influence.
  -- A genuinely rebooted worker will not have an in-flight task from
  -- our side's perspective once the timeout fires; until then, hold
  -- the slot.
  if existing.current_task then
    sendFrame(addr, {
      op       = "REGISTER_ACK",
      accepted = false,
      reason   = "task in flight; reboot will be honored after timeout",
    })
    logf("warn", "Refusing re-REGISTER from %s: task %s still in flight",
      addr:sub(1, 8), tostring(existing.current_task))
    return
  end

  -- Re-registration (worker rebooted). Keep the old worker_id so in-flight
  -- bookkeeping on our side stays coherent. Reset liveness counters.
  existing.state          = "idle"
  existing.last_seen      = computer.uptime()
  existing.pings_missed   = 0
  existing.current_task   = nil
  existing.last_ping_sent = nil
  existing.hostname       = tostring(frame.hostname or existing.hostname)
  if type(frame.capabilities) == "table" then
    existing.capabilities = frame.capabilities
  end
  sendFrame(addr, {
    op        = "REGISTER_ACK",
    accepted  = true,
    worker_id = existing.id,
  })
  logf("info", "Re-registered worker %d at %s", existing.id, addr:sub(1, 8))
end

local function handleResult(addr, frame)
  local w = workers[addr]
  if not w then return end

  w.last_seen = computer.uptime()
  w.pings_missed = 0

  local tid = tonumber(frame.task_id)
  if not tid then return end

  local task = tasks[tid]
  if not task or task.worker_addr ~= addr then
    -- Result for a task we don't know about (or wrong worker). Ignore.
    return
  end

  -- Clear worker task binding and mark idle.
  if w.current_task == tid then
    w.current_task = nil
    w.state = "idle"
  end

  local result = {
    task_id = tid,
    status  = tostring(frame.status or "ok"),
    output  = type(frame.output) == "string" and frame.output or "",
    err     = type(frame.err) == "string" and frame.err or nil,
  }

  local cb = task.on_result
  tasks[tid] = nil

  if cb then pcall(cb, addr, tid, result) end
  if resultCb then pcall(resultCb, addr, tid, result) end
end

local function handleProgress(addr, frame)
  local w = workers[addr]
  if not w then return end
  w.last_seen = computer.uptime()
  w.pings_missed = 0
  -- Progress is informational; we don't surface it by default. Logging
  -- at debug keeps the signal available without spamming the console.
  logf("debug", "Worker %s task %s: progress=%s %s",
    addr:sub(1, 8), tostring(frame.task_id),
    tostring(frame.progress), tostring(frame.msg or ""))
end

local function handlePong(addr, frame)
  local w = workers[addr]
  if not w then return end
  w.last_seen = computer.uptime()
  w.pings_missed = 0
  if w.state == "unresponsive" then
    w.state = w.current_task and "busy" or "idle"
    logf("info", "Worker %s recovered", addr:sub(1, 8))
  end
end

local DISPATCH = {
  REGISTER = handleRegister,
  RESULT   = handleResult,
  PROGRESS = handleProgress,
  PONG     = handlePong,
}

local function onModemMessage(_, _, remoteAddr, port, _, data)
  if port ~= workerPort then return end
  if type(data) ~= "string" then return end

  -- Defensive: reject anything too large to be a legitimate frame.
  if #data > 8192 then
    logf("debug", "Oversized frame from %s (%d bytes) dropped",
      remoteAddr:sub(1, 8), #data)
    return
  end

  local ok, frame = pcall(serialize.decode, data)
  if not ok or type(frame) ~= "table" then return end
  if frame.magic ~= MAGIC then return end

  -- #SEC H21 — verify HMAC when a shared secret is configured. A frame
  -- missing nonce/mac or carrying a bad MAC is dropped silently. Without
  -- this, anyone on the OC network can REGISTER and then feed the result
  -- callback (pcall'd attacker output) into TOS handlers.
  if sharedSecret then
    local nonce, mac = frame.nonce, frame.mac
    if type(nonce) ~= "string" or #nonce < 8 or #nonce > 64 then
      logf("warn", "WRK frame from %s missing/bad nonce", remoteAddr:sub(1, 8))
      return
    end
    if type(mac) ~= "string" or #mac ~= 64 then
      logf("warn", "WRK frame from %s missing/bad mac", remoteAddr:sub(1, 8))
      return
    end
    local okC, cryptoMod = pcall(require, "kernel.crypto")
    if not okC or not cryptoMod or not cryptoMod.hmac then
      logf("warn", "crypto unavailable; dropping WRK frame from %s",
        remoteAddr:sub(1, 8))
      return
    end
    local expected = cryptoMod.hmac(sharedSecret, canonicalFrame(frame))
    if not cryptoMod.ctEquals(expected, mac) then
      logf("warn", "WRK frame from %s failed MAC", remoteAddr:sub(1, 8))
      return
    end
    -- Replay protection: ring buffer of accepted nonces.
    if seenNonces[nonce] then
      logf("warn", "WRK frame from %s replayed nonce", remoteAddr:sub(1, 8))
      return
    end
    seenNonces[nonce] = true
    seenOrder[#seenOrder + 1] = nonce
    if #seenOrder > SEEN_MAX then
      local stale = table.remove(seenOrder, 1)
      seenNonces[stale] = nil
    end
  end

  local op = frame.op
  local handler = DISPATCH[op]
  if not handler then return end

  handler(remoteAddr, frame)
end

-- ============================================================
-- Ping / liveness loop
-- ============================================================

local function pingTick()
  local now = computer.uptime()
  local pingInterval = cluster.TIMING.WORKER_PING

  for addr, w in pairs(workers) do
    -- Idle-only ping per spec §6.2. Busy workers prove liveness via task
    -- results + progress messages.
    if w.state == "idle" then
      -- Send a ping if we haven't pinged recently.
      if not w.last_ping_sent or (now - w.last_ping_sent) >= pingInterval then
        sendFrame(addr, { op = "PING", time = now })
        w.last_ping_sent = now
      end

      -- Two missed pings (~20s) → unresponsive per §7.
      local silent = now - (w.last_seen or 0)
      if silent >= (2 * pingInterval) and w.state ~= "unresponsive" then
        w.state = "unresponsive"
        w.pings_missed = (w.pings_missed or 0) + 1
        logf("warn", "Worker %s unresponsive (%.0fs silent)",
          addr:sub(1, 8), silent)
      end
    end
  end
end

local function timeoutTick()
  local now = computer.uptime()
  for tid, t in pairs(tasks) do
    if (now - t.sent_at) > t.timeout then
      -- Synthesize a timeout result and hand it to the caller.
      local w = workers[t.worker_addr]
      if w and w.current_task == tid then
        w.current_task = nil
        w.state = "idle"
      end
      local cb = t.on_result
      tasks[tid] = nil
      local result = {
        task_id = tid,
        status  = "timeout",
        output  = "",
        err     = string.format("task timed out after %ds", t.timeout),
      }
      if cb then pcall(cb, t.worker_addr, tid, result) end
      if resultCb then pcall(resultCb, t.worker_addr, tid, result) end
      logf("warn", "Task %d on %s timed out", tid, t.worker_addr:sub(1, 8))
    end
  end
end

-- ============================================================
-- Public API
-- ============================================================

function cworker.init(modules)
  log   = modules.log
  event = modules.event
  return true
end

--- Bind this Manager to the given domain, opening the appropriate port
-- on every modem NIC. Idempotent: changing the domain_id closes the old
-- port and opens the new one.
function cworker.setDomainId(id)
  if type(id) ~= "number" or id < 0 then
    return false, "invalid domain_id"
  end

  -- #SEC CR-3 — default-deny. Refuse to open the worker port unless a
  -- shared secret has been installed. Dispatched WRK frames carry
  -- attacker-supplied `code` and result `output` that flow into
  -- pcall(cb, ...); without HMAC authentication on every frame, any
  -- device on the OC network could REGISTER and drive that path
  -- (remote code execution). The operator must call cworker.setSecret()
  -- — wired from cluster.cfg's `shared_secret` — BEFORE binding.
  if sharedSecret == nil then
    return false, "refusing to bind: cluster shared secret not set "
      .. "(set 'shared_secret' (16+ bytes) in /etc/cluster.cfg)"
  end

  -- If we're already bound, unbind first. Workers registered under the
  -- previous domain are discarded — they belong to a different
  -- organizational unit and must re-register under the new domain.
  if workerPort and workerPort ~= cluster.workerPort(id) then
    closePortOnAllModems(workerPort)
    workers = {}
    tasks = {}
    nextWorkerId = 1
  end

  domainId   = id
  workerPort = cluster.workerPort(id)

  collectModems()
  openPortOnAllModems(workerPort)

  -- Register modem_message listener (once).
  if event and #listenerIds == 0 then
    local lid = event.on("modem_message", onModemMessage, "cworker")
    listenerIds[#listenerIds + 1] = lid
  end

  -- Register periodic ticks (once).
  if event and not pingTimerId and event.interval then
    pingTimerId = event.interval(cluster.TIMING.WORKER_PING, pingTick, "cworker:ping")
  end
  if event and not timeoutTimerId and event.interval then
    timeoutTimerId = event.interval(2, timeoutTick, "cworker:timeout")
  end

  logf("info", "Bound to domain %d on port %d", id, workerPort)
  return true
end

--- Open the bootstrap window so unknown worker addresses can register.
-- @param seconds number|nil Window length; nil = default 180s (§7).
function cworker.setBootstrap(seconds)
  seconds = seconds or cluster.TIMING.BOOTSTRAP_WINDOW
  if type(seconds) ~= "number" or seconds <= 0 then
    bootstrapUntil = nil
    logf("info", "Bootstrap window closed")
    return true
  end
  bootstrapUntil = computer.uptime() + seconds
  logf("info", "Bootstrap window open for %ds", seconds)
  return true
end

function cworker.isBootstrapOpen()
  return bootstrapUntil ~= nil and computer.uptime() <= bootstrapUntil
end

--- Return a shallow snapshot of worker state for UI/status queries.
function cworker.list()
  local out = {}
  for addr, w in pairs(workers) do
    out[#out + 1] = {
      addr         = addr,
      id           = w.id,
      state        = w.state,
      hostname     = w.hostname,
      last_seen    = w.last_seen,
      current_task = w.current_task,
    }
  end
  return out
end

function cworker.domainId() return domainId end
function cworker.workerPort() return workerPort end

--- Dispatch a Lua task to a specific worker.
-- @param addr string: worker modem address
-- @param code string: Lua source to execute on the worker
-- @param opts table|nil: { inputs=<t>, timeout=<s>, on_result=<fn> }
-- @return number task_id on success; nil,err on failure.
function cworker.dispatch(addr, code, opts)
  if type(addr) ~= "string" then return nil, "addr required" end
  if type(code) ~= "string" or code == "" then return nil, "code required" end
  opts = opts or {}

  local w = workers[addr]
  if not w then return nil, "unknown worker" end
  if w.state ~= "idle" then
    return nil, "worker not idle: " .. tostring(w.state)
  end

  local timeout = tonumber(opts.timeout) or cluster.TIMING.TASK_TIMEOUT
  local tid = nextTaskId
  nextTaskId = nextTaskId + 1

  local ok, err = sendFrame(addr, {
    op       = "TASK",
    task_id  = tid,
    code     = code,
    inputs   = type(opts.inputs) == "table" and opts.inputs or {},
    timeout  = timeout,
  })
  if not ok then return nil, err end

  w.state = "busy"
  w.current_task = tid
  tasks[tid] = {
    worker_addr = addr,
    sent_at     = computer.uptime(),
    timeout     = timeout,
    code        = code,
    on_result   = type(opts.on_result) == "function" and opts.on_result or nil,
  }
  return tid
end

--- Cancel a previously-dispatched task. The worker may still reply with
-- a final RESULT/TIMEOUT, which we then discard.
function cworker.cancel(tid)
  local t = tasks[tid]
  if not t then return false, "unknown task" end
  sendFrame(t.worker_addr, { op = "CANCEL", task_id = tid })
  local w = workers[t.worker_addr]
  if w and w.current_task == tid then
    w.current_task = nil
    w.state = "idle"
  end
  tasks[tid] = nil
  return true
end

--- Register a global result callback (in addition to per-task callbacks).
function cworker.onResult(cb)
  if type(cb) ~= "function" and cb ~= nil then
    return false, "callback must be function or nil"
  end
  resultCb = cb
  return true
end

--- Forcibly forget a worker (operator action).
function cworker.forget(addr)
  local w = workers[addr]
  if not w then return false, "unknown worker" end
  if w.current_task then
    tasks[w.current_task] = nil
  end
  workers[addr] = nil
  logf("info", "Forgot worker %d (%s)", w.id, addr:sub(1, 8))
  return true
end

function cworker.stop()
  if workerPort then closePortOnAllModems(workerPort) end
  if event then
    if event.off then
      for _, id in ipairs(listenerIds) do pcall(event.off, "modem_message", id) end
    end
    listenerIds = {}
    -- Interval timers are cancelled via cancelTimer (not event.off).
    if event.cancelTimer then
      if pingTimerId    then pcall(event.cancelTimer, pingTimerId);    pingTimerId    = nil end
      if timeoutTimerId then pcall(event.cancelTimer, timeoutTimerId); timeoutTimerId = nil end
    end
  end
  workers = {}
  tasks = {}
  workerPort = nil
  domainId = nil
  bootstrapUntil = nil
end

return cworker
