-- ╔══════════════════════════════════════╗
-- ║  TOS Network - Remote Shell          ║
-- ║  Execute commands on TRUSTED peers   ║
-- ╚══════════════════════════════════════╝
-- Allows TRUSTED peers to send Lua commands for execution.
-- Commands run in a sandboxed environment with a captured
-- print() function so output can be returned to the caller.

local computer = require("computer")

local remote = {}

-- Protocol type constants (to be registered in protocol.lua)
local REMOTE_EXEC = "remote_exec"
local REMOTE_RES  = "remote_res"

-- Timeout for waiting on a response (seconds)
local TIMEOUT = 30

-- Upper bound on command size we'll accept or send. Parsing a huge string
-- under load() is itself a DoS vector, so cap it conservatively.
local CMD_LIMIT = 8192

-- Minimum free memory (bytes) required to enter sandbox execution. If the
-- host is under pressure we refuse to load and run attacker-supplied code.
local MIN_FREE_MEM = 32 * 1024

-- Step budget: total VM instructions before we abort the sandbox. Tuned so
-- that legitimate "print a few lines" workloads succeed comfortably while
-- `while true do end` or similar pin attempts die quickly.
local STEP_BUDGET = 1e6
-- How often the hook fires while we're below the budget. Smaller = faster
-- detection, higher overhead. 100k is a reasonable middle ground.
local STEP_TICK   = 1e5

-- Module references (set during init)
local net      = nil
local fs       = nil
local trustMgr = nil
local log      = nil
local event    = nil

-- #SEC L — runtime enable switch. The REMOTE_EXEC handler is registered
-- once at boot and stays registered, so the rshd rc service's stop() must
-- have a real way to make incoming exec requests be ignored — otherwise
-- "service stop rshd" gives a false sense of having disabled remote
-- command execution while packets are still handled. handleExec consults
-- this flag; the rshd service toggles it via remote.setEnabled().
--
-- #SEC — default DISABLED (fail-closed). The handler must not honor exec
-- requests until the rshd service explicitly starts and calls
-- setEnabled(true). Previously this defaulted to true, so remote code
-- execution was armed by boot init even on a machine whose operator never
-- ran (or deliberately removed) rshd — the only thing that ever turned it
-- off was `service stop rshd`. Now enablement tracks the service lifecycle:
-- no rshd running ⇒ no remote exec. (Requests still also require a TRUSTED,
-- challenge-verified peer regardless of this flag.)
local enabled = false
function remote.setEnabled(v) enabled = v and true or false end
function remote.isEnabled() return enabled end

--! THE STEP BUDGET BELOW DOES NOT EXIST ON OPENCOMPUTERS.
--!
--! It is installed with debug.sethook, and OC's sandbox does not hand that
--! out. Its machine.lua exports exactly four debug functions -- getinfo,
--! traceback, getlocal, getupvalue -- and deliberately withholds sethook,
--! because the machine uses its own hook to enforce the "too long without
--! yielding" deadline and guest code that could call sethook could disarm
--! it. (Read it yourself: assets/opencomputers/lua/machine.lua, the `debug =
--! {` table. OpenOS, which is real OC code, only ever calls debug.traceback.)
--!
--! So `if debug and debug.sethook then` is FALSE on every real machine, the
--! hook is never installed, and both the CPU bound AND the memory-pressure
--! abort inside it silently do not run. The code reads exactly as though
--! they do, which is why this notice is here and not in a commit message.
--!
--! WHAT STILL PROTECTS THE HOST, so the actual position is written down:
--!   * a peer must be TRUSTED *and* pass challenge-response, per request;
--!   * rshd must be running (`enabled`), and it defaults off;
--!   * CMD_LIMIT caps the source fed to load();
--!   * MIN_FREE_MEM is checked once, BEFORE entry (that check is outside
--!     the hook and does still happen);
--!   * OUTPUT_LIMIT caps what comes back;
--!   * OC's own machine deadline still kills a runaway -- but it kills the
--!     WHOLE COMPUTER, which is a far worse outcome than the clean "step
--!     budget exceeded" this module was written to return.
--!
--! Not turned into a refusal-to-run here: that would disable rsh outright on
--! the only platform TOS ships for, and whether that trade is worth making
--! is an operator's decision, not a bug fix. It is recorded in TODO.txt.
--! (test_sethook_absent.lua)
local function sethookAvailable()
  return type(debug) == "table" and type(debug.sethook) == "function"
end

--- Can the CPU/memory budget actually be enforced on this host?
--- False on OpenComputers. Exposed so diagnostics can say so out loud
--- rather than implying a guarantee that is not there.
function remote.stepBudgetAvailable() return sethookAvailable() end

local warnedNoBudget = false
local function warnBudgetOnce()
  if warnedNoBudget or sethookAvailable() then return end
  warnedNoBudget = true
  if log and log.warn then
    log.warn("remote", "debug.sethook is unavailable here (OpenComputers does "
      .. "not expose it): remote commands run with NO step or memory budget. "
      .. "Trust + challenge-response and the OC watchdog are the only limits.")
  end
end
local protocol = nil

-- ============================================================
-- Initialization
-- ============================================================

function remote.init(modules)
  net      = modules.net
  fs       = modules.fs
  trustMgr = modules.trust
  log      = modules.log
  event    = modules.event

  protocol = require("kernel.net.protocol")

  -- Register handler for incoming remote_exec packets
  if net then
    net.on(REMOTE_EXEC, function(packet, fromAddr)
      remote.handleExec(packet, fromAddr)
    end)
  end

  if log then
    log.info("remote", "Remote shell module initialized")
  end

  return true
end

-- ============================================================
-- Execute a command on a remote peer
-- ============================================================

--- Send a Lua command to a TRUSTED peer and wait for the result.
-- @param address string: Remote peer's modem address
-- @param command string: Lua code to execute on the remote machine
-- @return string, number: Output string and exit code, or nil + error
function remote.execute(address, command)
  if not net then return nil, "Network not available" end
  if not protocol then return nil, "Protocol not loaded" end

  -- Verify peer is TRUSTED
  local level = trustMgr.getLevel(address)
  if level < trustMgr.LEVEL.TRUSTED then
    return nil, "Peer is not TRUSTED"
  end

  -- #SEC — Challenge-response binds trust to possession of the
  -- shared secret, not just the modem address. Without this a
  -- physically-relocated trusted modem (or any node that learned
  -- a trusted address through a side channel) could ask us to
  -- run arbitrary code. The first verification per peer pays a
  -- round-trip; subsequent calls hit the 60s positive cache.
  if net.verifyPeer then
    local vOk, vErr = net.verifyPeer(address)
    if not vOk then
      return nil, "Peer verification failed: " .. tostring(vErr)
    end
  end

  if not command or command == "" then
    return nil, "No command specified"
  end

  if type(command) ~= "string" then
    return nil, "Command must be a string"
  end

  if #command > CMD_LIMIT then
    return nil, "Command too large (max " .. CMD_LIMIT .. " bytes)"
  end

  -- Register response listener BEFORE sending. net.onceFrom does the
  -- peer-address filter and one-shot de-dup so late duplicates from
  -- retransmits — or a malicious peer flooding responses — can't
  -- overwrite the captured output after we've already returned.
  local received = false
  local output   = nil
  local exitCode = nil

  local listeners = {
    { type = REMOTE_RES,
      id   = net.onceFrom(REMOTE_RES, address, function(rpkt)
        local payload = rpkt.payload or {}
        output   = type(payload.output) == "string" and payload.output or ""
        exitCode = type(payload.exitCode) == "number" and payload.exitCode or 0
        received = true
      end) },
  }

  -- Build and send remote_exec packet
  local pkt = protocol.makePacket(REMOTE_EXEC, {
    cmd = command,
  }, { to = address })

  local ok, sendErr = net.send(address, pkt)
  if not ok then
    net.offAll(listeners)
    return nil, "Send failed: " .. tostring(sendErr)
  end

  if log then
    log.info("remote", "Sent command to " .. address:sub(1, 8) ..
      "...: " .. command:sub(1, 40))
  end

  net.waitFor(function() return received end, TIMEOUT)
  net.offAll(listeners)

  if not received then
    return nil, "Timeout waiting for response"
  end

  return output, exitCode
end

-- ============================================================
-- Handle incoming remote_exec from a remote peer
-- ============================================================

--- Process an incoming remote execution request.
-- @param packet table: The deserialized remote_exec packet
-- @param fromAddr string: The sender's modem address
function remote.handleExec(packet, fromAddr)
  if not net or not protocol then return end
  if not enabled then return end  -- #SEC L — rshd stopped: ignore exec requests

  -- Trust check: must be TRUSTED
  local level = trustMgr.getLevel(fromAddr)
  if level < trustMgr.LEVEL.TRUSTED then
    if log then
      log.warn("remote", "Remote exec denied from non-trusted peer: " ..
        fromAddr:sub(1, 8) .. "...")
    end
    -- Don't respond to untrusted peers (avoid information leak)
    return
  end

  -- #SEC — Verify the sender via challenge-response BEFORE running
  -- their code. Without this an attacker with a relocated trusted
  -- modem could send REMOTE_EXEC and we'd execute it (the trust
  -- check above only proves the modem address is in our trust
  -- table, not that the modem is in genuine hands). The 60s
  -- positive cache means a back-to-back stream of commands from
  -- the same peer pays one round-trip.
  if net.verifyPeer then
    local vOk, vErr = net.verifyPeer(fromAddr)
    if not vOk then
      if log then
        log.warn("remote", "Refusing remote exec from " ..
          fromAddr:sub(1, 8) .. ": " .. tostring(vErr))
      end
      return
    end
  end

  local payload = packet.payload or {}
  local cmd = payload.cmd

  if type(cmd) ~= "string" or cmd == "" then
    local res = protocol.makePacket(REMOTE_RES, {
      output   = "Error: no command provided",
      exitCode = 1,
    }, { to = fromAddr })
    net.send(fromAddr, res)
    return
  end

  -- Refuse oversized commands outright: a big attacker-controlled string
  -- fed straight into load() is a parser-side DoS vector.
  if #cmd > CMD_LIMIT then
    if log then
      log.warn("remote", "Oversized remote cmd from " ..
        fromAddr:sub(1, 8) .. "... (" .. #cmd .. " bytes)")
    end
    local res = protocol.makePacket(REMOTE_RES, {
      output   = "Error: command too large (max " .. CMD_LIMIT .. " bytes)",
      exitCode = 1,
    }, { to = fromAddr })
    net.send(fromAddr, res)
    return
  end

  -- Memory-pressure gate: refuse to execute attacker code when the host is
  -- already low on memory. Better to bail early than OOM the kernel.
  if computer.freeMemory and computer.freeMemory() < MIN_FREE_MEM then
    if log then
      log.warn("remote", "Refusing remote exec: low memory")
    end
    local res = protocol.makePacket(REMOTE_RES, {
      output   = "Error: host low on memory, retry later",
      exitCode = 1,
    }, { to = fromAddr })
    net.send(fromAddr, res)
    return
  end

  if log then
    log.info("remote", "Executing remote command from " ..
      fromAddr:sub(1, 8) .. "...: " .. cmd:sub(1, 60))
  end

  -- Build a sandboxed environment with captured output
  local outputLines = {}
  local outputSize = 0
  local OUTPUT_LIMIT = 5120

  -- Shallow-copy shared libraries so the sandbox cannot poison the host.
  -- `deny` lets us drop entries we don't want inside the sandbox (string.dump
  -- can exfiltrate bytecode; debug.* would defeat the step-budget hook).
  local function copyLib(lib, deny)
    local c = {}
    for k, v in pairs(lib) do
      if not (deny and deny[k]) then c[k] = v end
    end
    return c
  end

  local sandbox = {
    print = function(...)
      if outputSize >= OUTPUT_LIMIT then return end
      local parts = {}
      for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
      end
      local line = table.concat(parts, "\t")
      -- Truncate lines that alone would blow the budget so a single call
      -- like print(string.rep("x", 1e6)) can't bypass OUTPUT_LIMIT.
      local remaining = OUTPUT_LIMIT - outputSize
      if #line > remaining then line = line:sub(1, math.max(0, remaining)) end
      outputSize = outputSize + #line + 1
      outputLines[#outputLines + 1] = line
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
    computer = {
      uptime      = computer.uptime,
      freeMemory  = computer.freeMemory,
      totalMemory = computer.totalMemory,
    },
  }

  -- Provide restricted fs access: only /public/ is readable
  if fs then
    sandbox.fs = {
      exists = function(path)
        path = fs.normalize(path)
        if path == "/public" or path:sub(1, 8) == "/public/" then return fs.exists(path) end
        return false
      end,
      list = function(path)
        path = fs.normalize(path)
        if path == "/public" or path:sub(1, 8) == "/public/" then return fs.list(path) end
        return {}
      end,
      isDirectory = function(path)
        path = fs.normalize(path)
        if path == "/public" or path:sub(1, 8) == "/public/" then return fs.isDirectory(path) end
        return false
      end,
      readFile = function(path)
        path = fs.normalize(path)
        if path == "/public" or path:sub(1, 8) == "/public/" then return fs.readFile(path) end
        return nil, "Access denied: only /public/ is accessible remotely"
      end,
    }
  end

  -- Load and execute the command in the sandbox
  local fn, loadErr = load(cmd, "=remote", "t", sandbox)
  local exitCode = 0

  if not fn then
    outputLines[#outputLines + 1] = "Load error: " .. tostring(loadErr)
    exitCode = 1
  else
    -- CPU/step budget via debug.sethook. Two subtleties worth noting:
    --
    -- 1. We preserve and restore any prior hook. Overwriting a hook set by
    --    another TOS component (profiler, scheduler) and then clearing it
    --    blind would break that component silently.
    -- 2. Once the budget trips we switch the hook to fire every single
    --    instruction and keep erroring. Otherwise a trusted peer can do
    --    `while true do pcall(function() while true do end end) end` and
    --    swallow the budget error in user-level pcall every burst, running
    --    forever. With count=1 post-trip, every instruction (including
    --    the one right after pcall returns) raises again, so forward
    --    progress collapses to the pcall-overhead floor.
    local priorHook, priorMask, priorCount = nil, nil, nil
    local hookInstalled = false
    local stepsRun = 0
    local tripped  = false

    -- Say so, once, when the budget cannot be installed. Silence here is
    -- what made this look like a working control for so long.
    warnBudgetOnce()

    if debug and debug.sethook then
      if debug.gethook then
        local ok, h, m, c = pcall(debug.gethook)
        if ok then priorHook, priorMask, priorCount = h, m, c end
      end

      local hook
      hook = function()
        if tripped then
          error("remote exec: step budget exceeded", 0)
        end
        -- #SEC — memory-pressure abort. The step counter bounds CPU but not
        -- allocation: a loop that grows a table/string (e.g.
        -- `local t={} while true do t[#t+1]=("x"):rep(1024) end`) would pin
        -- RAM and can OOM the kernel before the step budget trips. Sample
        -- free memory each tick and trip the budget if it falls below the
        -- same floor we required to ENTER the sandbox. (A single huge
        -- allocation in one instruction can still slip between ticks; the
        -- pcall around fn catches a recoverable "not enough memory" error,
        -- and the entry-gate MIN_FREE_MEM keeps the starting headroom.)
        if computer.freeMemory and computer.freeMemory() < MIN_FREE_MEM then
          tripped = true
          pcall(debug.sethook, hook, "", 1)
          error("remote exec: aborted (host low on memory)", 0)
        end
        stepsRun = stepsRun + STEP_TICK
        if stepsRun >= STEP_BUDGET then
          tripped = true
          -- Fire every instruction from here on; pcall can't outlast it.
          pcall(debug.sethook, hook, "", 1)
          error("remote exec: step budget exceeded", 0)
        end
      end

      local ok = pcall(debug.sethook, hook, "", STEP_TICK)
      if ok then hookInstalled = true end
    end

    local execOk, execErr = pcall(fn)

    if hookInstalled then
      if priorHook then
        pcall(debug.sethook, priorHook, priorMask or "", priorCount or 0)
      else
        pcall(debug.sethook)
      end
    end

    if not execOk then
      outputLines[#outputLines + 1] = "Runtime error: " .. tostring(execErr)
      exitCode = 1
    end
  end

  local output = table.concat(outputLines, "\n")

  -- Truncate output if it would exceed safe packet size
  if #output > OUTPUT_LIMIT then
    output = output:sub(1, OUTPUT_LIMIT) .. "\n... (output truncated)"
  end

  if log then
    log.info("remote", "Command finished (exit=" .. exitCode ..
      ", output=" .. #output .. " bytes)")
  end

  -- Send the result back
  local res = protocol.makePacket(REMOTE_RES, {
    output   = output,
    exitCode = exitCode,
  }, { to = fromAddr })

  local ok, err = net.send(fromAddr, res)
  if not ok and log then
    log.warn("remote", "Failed to send result: " .. tostring(err))
  end
end

-- Export type constants for external use
remote.TYPE_EXEC = REMOTE_EXEC
remote.TYPE_RES  = REMOTE_RES

-- #MEM — lazy self-initialization. Mirrors kernel.net.transfer: the kernel
-- no longer initializes this module at boot; it loads on demand (first
-- inbound REMOTE_EXEC via net's dispatch, or an outbound rsh) and wires
-- itself from the live _TOS handles. The rshd service records its arm
-- state in net; apply it here so a daemon started before this module
-- loaded still governs it. Fail-closed: no recorded arm ⇒ disabled, the
-- same default the module ships with. Off-box tests keep explicit init().
do
  local T = rawget(_G, "_TOS")
  if T and T.net and not net then
    local okI = pcall(remote.init, {
      net   = T.net,
      fs    = T.fs,
      trust = T.net.getTrust and T.net.getTrust() or nil,
      log   = T.logObj,
      event = T.event,
    })
    if okI and T.net.getServiceArm and T.net.getServiceArm("rshd") then
      remote.setEnabled(true)
    end
  end
end

return remote
