local computer = require("computer")

local remote = {}

local REMOTE_EXEC = "remote_exec"
local REMOTE_RES  = "remote_res"

local TIMEOUT = 30

local CMD_LIMIT = 8192

local MIN_FREE_MEM = 32 * 1024

local STEP_BUDGET = 1e6

local STEP_TICK   = 1e5

local net      = nil
local fs       = nil
local trustMgr = nil
local log      = nil
local event    = nil

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

function remote.init(modules)
  net      = modules.net
  fs       = modules.fs
  trustMgr = modules.trust
  log      = modules.log
  event    = modules.event

  protocol = require("kernel.net.protocol")

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

function remote.execute(address, command)
  if not net then return nil, "Network not available" end
  if not protocol then return nil, "Protocol not loaded" end

  local level = trustMgr.getLevel(address)
  if level < trustMgr.LEVEL.TRUSTED then
    return nil, "Peer is not TRUSTED"
  end

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

function remote.handleExec(packet, fromAddr)
  if not net or not protocol then return end
  if not enabled then return end

  local level = trustMgr.getLevel(fromAddr)
  if level < trustMgr.LEVEL.TRUSTED then
    if log then
      log.warn("remote", "Remote exec denied from non-trusted peer: " ..
        fromAddr:sub(1, 8) .. "...")
    end

    return
  end

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

  local outputLines = {}
  local outputSize = 0
  local OUTPUT_LIMIT = 5120

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

  local fn, loadErr = load(cmd, "=remote", "t", sandbox)
  local exitCode = 0

  if not fn then
    outputLines[#outputLines + 1] = "Load error: " .. tostring(loadErr)
    exitCode = 1
  else

    local priorHook, priorMask, priorCount = nil, nil, nil
    local hookInstalled = false
    local stepsRun = 0
    local tripped  = false

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

        if computer.freeMemory and computer.freeMemory() < MIN_FREE_MEM then
          tripped = true
          pcall(debug.sethook, hook, "", 1)
          error("remote exec: aborted (host low on memory)", 0)
        end
        stepsRun = stepsRun + STEP_TICK
        if stepsRun >= STEP_BUDGET then
          tripped = true

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

  if #output > OUTPUT_LIMIT then
    output = output:sub(1, OUTPUT_LIMIT) .. "\n... (output truncated)"
  end

  if log then
    log.info("remote", "Command finished (exit=" .. exitCode ..
      ", output=" .. #output .. " bytes)")
  end

  local res = protocol.makePacket(REMOTE_RES, {
    output   = output,
    exitCode = exitCode,
  }, { to = fromAddr })

  local ok, err = net.send(fromAddr, res)
  if not ok and log then
    log.warn("remote", "Failed to send result: " .. tostring(err))
  end
end

remote.TYPE_EXEC = REMOTE_EXEC
remote.TYPE_RES  = REMOTE_RES

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
