-- ╔══════════════════════════════════════╗
-- ║  OpenOS TOS-Cluster Worker Daemon    ║
-- ║  Talks to a TOS Manager over raw     ║
-- ║  OC modem on port 2001 + domain_id   ║
-- ╚══════════════════════════════════════╝
--
-- Deploy to: /home/cluster-worker.lua on each OpenOS worker machine.
-- Config:    /etc/cluster-worker.cfg — Lua table literal:
--              return {
--                domain_id     = 3,
--                hostname      = "wk-a",
--                shared_secret = "set-me-to-match-the-manager",  -- 16+ bytes
--              }
--
-- shared_secret is REQUIRED. Set it to the SAME value the Manager uses; every
-- WRK frame is then HMAC-authenticated (#SEC H21/CR-3). Without it this worker
-- refuses to run tasks and a hardened Manager rejects it.
--
-- Start at boot by adding to /etc/rc.cfg:
--   enabled = { "cluster-worker", ... }
--   cluster-worker = { autostart = true }
--
-- Wire format (Lua table literal via serialization.serialize). See
-- TOS/tos/kernel/net/cluster_worker.lua for the full protocol table.

local component     = require("component")
local computer      = require("computer")
local event         = require("event")
local serialization = require("serialization")
local fs            = require("filesystem")

local MAGIC              = "WRK"
local CFG_PATH           = "/etc/cluster-worker.cfg"
local REGISTER_RETRY     = 5    -- seconds between registration attempts
local REGISTER_TIMEOUT   = 10   -- seconds to wait for REGISTER_ACK
local MAX_FRAME          = 8192 -- bytes
local MAX_OUTPUT         = 5120 -- bytes per task
local STEP_BUDGET        = 1e6
local STEP_TICK          = 1e5

-- ============================================================
-- #SEC H21/H2/CR-3 — frame authentication (matches the Manager)
-- ============================================================
-- The Manager side (TOS kernel.net.cluster_worker / cluster.worker) refuses
-- to bind without a shared secret and HMAC-verifies every WRK frame, signing
-- its own with a fresh nonce. This OpenOS worker — the side that actually
-- RUNS Manager-supplied `code` — must do the same, for two reasons:
--   1. Security: without it, a spoofed REGISTER_ACK makes us adopt any
--      sender as "manager", after which their TASK frames drive runTask().
--   2. Interop: a hardened Manager DROPS our unsigned frames, so an
--      unauthenticated worker can never register at all.
-- We carry our own software SHA-256 + HMAC because OpenOS has no kernel.crypto;
-- the digests are standard SHA-256, identical to the Manager's, so the MACs
-- match. The shared secret comes from /etc/cluster-worker.cfg's `shared_secret`
-- (16+ bytes), which the operator sets to the SAME value as the Manager.

local function rrot(x, n) return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF end
local SHA_K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}
local function tohex32(x) return string.format("%08x", x & 0xFFFFFFFF) end
local function sha256_hex(msg)
  local bytes = { msg:byte(1, #msg) }
  local bitLen = (#bytes) * 8
  bytes[#bytes + 1] = 0x80
  while (#bytes % 64) ~= 56 do bytes[#bytes + 1] = 0 end
  local hi = math.floor(bitLen / 2^32)
  local lo = bitLen & 0xFFFFFFFF
  bytes[#bytes + 1] = (hi >> 24) & 0xFF; bytes[#bytes + 1] = (hi >> 16) & 0xFF
  bytes[#bytes + 1] = (hi >>  8) & 0xFF; bytes[#bytes + 1] = (hi      ) & 0xFF
  bytes[#bytes + 1] = (lo >> 24) & 0xFF; bytes[#bytes + 1] = (lo >> 16) & 0xFF
  bytes[#bytes + 1] = (lo >>  8) & 0xFF; bytes[#bytes + 1] = (lo      ) & 0xFF
  local h0,h1,h2,h3,h4,h5,h6,h7 =
    0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
  local w = {}
  for chunk = 1, #bytes, 64 do
    for i = 0, 15 do
      local j = chunk + i*4
      w[i+1] = ((bytes[j] << 24) | (bytes[j+1] << 16) | (bytes[j+2] << 8) | (bytes[j+3])) & 0xFFFFFFFF
    end
    for i = 16, 63 do
      local s0 = (rrot(w[i-15+1], 7) ~ rrot(w[i-15+1], 18) ~ (w[i-15+1] >> 3)) & 0xFFFFFFFF
      local s1 = (rrot(w[i-2+1], 17) ~ rrot(w[i-2+1], 19) ~ (w[i-2+1] >> 10)) & 0xFFFFFFFF
      w[i+1] = (w[i-16+1] + s0 + w[i-7+1] + s1) & 0xFFFFFFFF
    end
    local a,b,c,d,e,f,g,h = h0,h1,h2,h3,h4,h5,h6,h7
    for i = 0, 63 do
      local S1  = (rrot(e, 6) ~ rrot(e,11) ~ rrot(e,25)) & 0xFFFFFFFF
      local ch  = ((e & f) ~ ((~e) & g)) & 0xFFFFFFFF
      local t1  = (h + S1 + ch + SHA_K[i+1] + w[i+1]) & 0xFFFFFFFF
      local S0  = (rrot(a, 2) ~ rrot(a,13) ~ rrot(a,22)) & 0xFFFFFFFF
      local maj = ((a & b) ~ (a & c) ~ (b & c)) & 0xFFFFFFFF
      local t2  = (S0 + maj) & 0xFFFFFFFF
      h=g; g=f; f=e; e=(d+t1)&0xFFFFFFFF; d=c; c=b; b=a; a=(t1+t2)&0xFFFFFFFF
    end
    h0=(h0+a)&0xFFFFFFFF; h1=(h1+b)&0xFFFFFFFF; h2=(h2+c)&0xFFFFFFFF; h3=(h3+d)&0xFFFFFFFF
    h4=(h4+e)&0xFFFFFFFF; h5=(h5+f)&0xFFFFFFFF; h6=(h6+g)&0xFFFFFFFF; h7=(h7+h)&0xFFFFFFFF
  end
  return tohex32(h0)..tohex32(h1)..tohex32(h2)..tohex32(h3)..tohex32(h4)..tohex32(h5)..tohex32(h6)..tohex32(h7)
end

local HMAC_BLOCK = 64
local function hmacSha256(key, msg)
  if #key > HMAC_BLOCK then
    local hexed = sha256_hex(key)
    local raw = {}
    for i = 1, 32 do raw[i] = string.char(tonumber(hexed:sub(i*2-1, i*2), 16)) end
    key = table.concat(raw)
  end
  if #key < HMAC_BLOCK then key = key .. string.rep("\0", HMAC_BLOCK - #key) end
  local ipad, opad = {}, {}
  for i = 1, HMAC_BLOCK do
    local kb = key:byte(i)
    ipad[i] = string.char(kb ~ 0x36)
    opad[i] = string.char(kb ~ 0x5C)
  end
  local innerHex = sha256_hex(table.concat(ipad) .. msg)
  local innerRaw = {}
  for i = 1, 32 do innerRaw[i] = string.char(tonumber(innerHex:sub(i*2-1, i*2), 16)) end
  return sha256_hex(table.concat(opad) .. table.concat(innerRaw))
end

-- Constant-time hex-digest compare (both are 64-char hex from our HMAC).
local function ctEquals(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  local la, lb = #a, #b
  local n = la > lb and la or lb
  local diff = la ~ lb
  for i = 1, n do
    local ba = i <= la and a:byte(i) or 0
    local bb = i <= lb and b:byte(i) or 0
    diff = diff | (ba ~ bb)
  end
  return diff == 0
end

-- Canonical, length-prefixed frame encoding for the MAC. MUST byte-match the
-- Manager's canonicalFrame: sort keys, length-prefix scalars, exclude `mac`.
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
    for k in pairs(v) do if k ~= "mac" then keys[#keys + 1] = k end end
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
  return "z"
end

-- Per-frame nonce. Uniqueness (not unpredictability) is what the replay ring
-- needs; mix uptime + address + a monotonic counter so back-to-back frames
-- differ even within one tick.
local _nonceCounter = 0
local function makeNonce()
  _nonceCounter = _nonceCounter + 1
  return sha256_hex(tostring(computer.uptime()) .. "|" ..
    tostring(computer.address()) .. "|" .. tostring(_nonceCounter)):sub(1, 32)
end

-- Shared secret + inbound replay ring (populated from cfg below).
local sharedSecret = nil
local seenNonces, seenOrder, SEEN_MAX = {}, {}, 1024

-- ============================================================
-- Config
-- ============================================================

local function loadConfig()
  local cfg = {
    domain_id    = 0,
    hostname     = "worker-" .. (computer.address():sub(1, 4)),
    capabilities = {},
  }
  if fs.exists(CFG_PATH) then
    local f = io.open(CFG_PATH, "r")
    if f then
      local body = f:read("*a")
      f:close()
      -- Accept both "return {...}" and bare "{...}" forms.
      local code = body:match("^%s*return%s+(.+)$") or body
      local chunk, err = load("return " .. code, "=cluster-worker.cfg", "t", {})
      if chunk then
        local ok, parsed = pcall(chunk)
        if ok and type(parsed) == "table" then
          for k, v in pairs(parsed) do cfg[k] = v end
        else
          io.stderr:write("cluster-worker: malformed cfg: " ..
            tostring(parsed) .. "\n")
        end
      else
        io.stderr:write("cluster-worker: cfg parse error: " ..
          tostring(err) .. "\n")
      end
    end
  end
  return cfg
end

-- ============================================================
-- Modem
-- ============================================================

local modem = component.isAvailable("modem") and component.modem or nil
if not modem then
  io.stderr:write("cluster-worker: no modem component available\n")
  return
end

local cfg        = loadConfig()
local workerPort = 2001 + (tonumber(cfg.domain_id) or 0)
modem.open(workerPort)

-- #SEC CR-3 — install the shared secret from cfg. Default-deny: with no
-- (valid) secret we can neither sign frames the hardened Manager will accept
-- nor verify the ones it sends, so we refuse to execute tasks at all.
if type(cfg.shared_secret) == "string" and #cfg.shared_secret >= 16 then
  sharedSecret = cfg.shared_secret
else
  if cfg.shared_secret ~= nil then
    io.stderr:write("cluster-worker: shared_secret too short (need 16+ bytes); ignoring\n")
  end
  io.stderr:write("cluster-worker: WARNING — no shared_secret set in " .. CFG_PATH .. ".\n")
  io.stderr:write("  A hardened Manager will reject this worker, and tasks are\n")
  io.stderr:write("  refused until you set shared_secret to match the Manager.\n")
end

-- Manager address — discovered during registration. Until we know it we
-- broadcast REGISTER on workerPort; the Manager listening on that port
-- replies directly to our address.
local managerAddr = nil
local workerId    = nil

local function sendFrame(addr, frame)
  frame.magic = MAGIC
  -- #SEC H2/H21 — sign the WHOLE frame (every field but `mac`) with a fresh
  -- nonce so the Manager accepts it and a captured frame can't be replayed.
  if sharedSecret then
    frame.nonce = makeNonce()
    frame.mac   = hmacSha256(sharedSecret, canonicalFrame(frame))
  end
  local data = serialization.serialize(frame)
  if #data > MAX_FRAME then return false, "frame too large" end
  if addr then
    return modem.send(addr, workerPort, data)
  else
    return modem.broadcast(workerPort, data)
  end
end

-- ============================================================
-- Sandbox for executing Manager-supplied code
-- ============================================================

-- Shallow-copy a library, optionally dropping specified keys.
local function copyLib(lib, deny)
  local c = {}
  for k, v in pairs(lib) do
    if not (deny and deny[k]) then c[k] = v end
  end
  return c
end

--- Execute `code` under a restricted environment with a step-budget hook.
-- Returns (status, output, err). `status` is "ok"|"fail"|"budget".
local function runTask(code, inputs)
  local outputBuf  = {}
  local outputSize = 0

  local sandbox = {
    print = function(...)
      if outputSize >= MAX_OUTPUT then return end
      local parts = {}
      for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
      end
      local line = table.concat(parts, "\t")
      local remaining = MAX_OUTPUT - outputSize
      if #line > remaining then line = line:sub(1, math.max(0, remaining)) end
      outputSize = outputSize + #line + 1
      outputBuf[#outputBuf + 1] = line
    end,
    tostring = tostring,
    tonumber = tonumber,
    type     = type,
    pairs    = pairs,
    ipairs   = ipairs,
    select   = select,
    pcall    = pcall,
    xpcall   = xpcall,
    error    = error,
    assert   = assert,
    unpack   = table.unpack or unpack,
    table    = copyLib(table),
    string   = copyLib(string, { dump = true }),
    math     = copyLib(math),
    os       = { clock = os.clock, time = os.time, date = os.date },
    inputs   = type(inputs) == "table" and inputs or {},
  }

  local fn, loadErr = load(code, "=task", "t", sandbox)
  if not fn then
    return "fail", "", "load error: " .. tostring(loadErr)
  end

  -- Step-budget hook: same logic as TOS's remote.lua. After the budget
  -- trips we switch the hook to fire every instruction so in-task pcall
  -- can't swallow the abort and loop forever.
  local priorHook, priorMask, priorCount
  local stepsRun, tripped = 0, false
  local hookInstalled = false

  if debug and debug.sethook then
    if debug.gethook then
      local ok, h, m, c = pcall(debug.gethook)
      if ok then priorHook, priorMask, priorCount = h, m, c end
    end
    local hook
    hook = function()
      if tripped then
        error("task: step budget exceeded", 0)
      end
      stepsRun = stepsRun + STEP_TICK
      if stepsRun >= STEP_BUDGET then
        tripped = true
        pcall(debug.sethook, hook, "", 1)
        error("task: step budget exceeded", 0)
      end
    end
    local ok = pcall(debug.sethook, hook, "", STEP_TICK)
    if ok then hookInstalled = true end
  end

  local okRun, runErr = pcall(fn)

  if hookInstalled then
    if priorHook then
      pcall(debug.sethook, priorHook, priorMask or "", priorCount or 0)
    else
      pcall(debug.sethook)
    end
  end

  local output = table.concat(outputBuf, "\n")
  if #output > MAX_OUTPUT then
    output = output:sub(1, MAX_OUTPUT) .. "\n... (truncated)"
  end

  if not okRun then
    local msg = tostring(runErr)
    local status = msg:find("step budget exceeded", 1, true) and "budget" or "fail"
    return status, output, msg
  end

  return "ok", output, nil
end

-- ============================================================
-- Frame handlers
-- ============================================================

-- Currently running task (cooperative — only one at a time). CANCEL sets
-- this to nil; in-flight execution keeps running but its RESULT will be
-- dropped by the check inside runCurrentTask.
local currentTask = nil

local function handleRegisterAck(addr, frame)
  if frame.accepted then
    managerAddr = addr
    workerId    = tonumber(frame.worker_id)
    print("[cluster-worker] registered as id=" .. tostring(workerId) ..
      " with manager " .. addr:sub(1, 8))
  else
    io.stderr:write("[cluster-worker] registration rejected: " ..
      tostring(frame.reason) .. "\n")
  end
end

local function handleTask(addr, frame)
  -- Per spec, tasks come from our Manager. Ignore TASK from anyone else.
  if managerAddr and addr ~= managerAddr then return end

  local tid = tonumber(frame.task_id)
  if not tid then return end
  if type(frame.code) ~= "string" then
    sendFrame(addr, {
      op = "RESULT", task_id = tid,
      status = "fail", output = "", err = "no code provided",
    })
    return
  end

  currentTask = tid
  local status, output, err = runTask(frame.code, frame.inputs)

  -- If cancelled mid-run we still send the result — the Manager discards
  -- late results for unknown task IDs anyway.
  sendFrame(addr, {
    op       = "RESULT",
    task_id  = tid,
    status   = status,
    output   = output,
    err      = err,
  })

  if currentTask == tid then currentTask = nil end
end

local function handleCancel(_, frame)
  local tid = tonumber(frame.task_id)
  if tid and currentTask == tid then
    -- Flip currentTask so the RESULT we're about to send gets labeled
    -- with the cancelled task; Manager-side bookkeeping already discarded
    -- it, but this at least short-circuits any further local work.
    currentTask = nil
  end
end

local function handlePing(addr, frame)
  if managerAddr and addr ~= managerAddr then return end
  sendFrame(addr, { op = "PONG", time = computer.uptime() })
end

local DISPATCH = {
  REGISTER_ACK = handleRegisterAck,
  TASK         = handleTask,
  CANCEL       = handleCancel,
  PING         = handlePing,
}

local function handleIncoming(_, _, remoteAddr, port, _, data)
  if port ~= workerPort then return end
  if type(data) ~= "string" then return end
  if #data > MAX_FRAME then return end
  local ok, frame = pcall(serialization.unserialize, data)
  if not ok or type(frame) ~= "table" then return end
  if frame.magic ~= MAGIC then return end

  -- #SEC H21 — authenticate every inbound frame against the shared secret
  -- before dispatch. A frame missing/with a bad nonce or MAC, or replaying a
  -- nonce we've already accepted, is dropped silently. Without a configured
  -- secret we cannot verify the Manager at all, so we drop everything (the
  -- startup warning told the operator to set shared_secret).
  if not sharedSecret then return end
  local nonce, mac = frame.nonce, frame.mac
  if type(nonce) ~= "string" or #nonce < 8 or #nonce > 64 then return end
  if type(mac) ~= "string" or #mac ~= 64 then return end
  if not ctEquals(hmacSha256(sharedSecret, canonicalFrame(frame)), mac) then return end
  if seenNonces[nonce] then return end
  seenNonces[nonce] = true
  seenOrder[#seenOrder + 1] = nonce
  if #seenOrder > SEEN_MAX then
    local stale = table.remove(seenOrder, 1)
    seenNonces[stale] = nil
  end

  local handler = DISPATCH[frame.op]
  if handler then handler(remoteAddr, frame) end
end

-- ============================================================
-- Registration loop
-- ============================================================

event.listen("modem_message", handleIncoming)

-- Initial registration: broadcast REGISTER until we get a REGISTER_ACK.
-- Repeat every REGISTER_RETRY seconds until managerAddr is known, then
-- fall silent.
local function tryRegister()
  if managerAddr then return end
  sendFrame(nil, {
    op           = "REGISTER",
    hostname     = cfg.hostname,
    capabilities = cfg.capabilities,
  })
end

tryRegister()
local regTimer = event.timer(REGISTER_RETRY, function()
  if not managerAddr then tryRegister() end
end, math.huge)

print("[cluster-worker] listening on port " .. workerPort ..
  " (domain=" .. tostring(cfg.domain_id) .. ", host=" .. cfg.hostname .. ")")

-- ============================================================
-- Main loop — stays alive; Ctrl+Alt+C or the process scheduler kills it.
-- ============================================================

local running = true
while running do
  -- event.pull returns nil on timeout; we just loop and keep the process
  -- alive so the modem_message listener keeps firing.
  local sig = event.pull(1)
  if sig == "interrupted" then running = false end
end

event.ignore("modem_message", handleIncoming)
if regTimer then event.cancel(regTimer) end
modem.close(workerPort)
print("[cluster-worker] shut down")
