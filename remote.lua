-- ╔══════════════════════════════════════╗
-- ║  TOS Network - Remote Shell         ║
-- ║  Execute commands on TRUSTED peers  ║
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

-- Module references (set during init)
local net      = nil
local fs       = nil
local trustMgr = nil
local log      = nil
local event    = nil
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

  if not command or command == "" then
    return nil, "No command specified"
  end

  -- Build and send remote_exec packet
  local pkt = protocol.makePacket(REMOTE_EXEC, {
    cmd = command,
  }, { to = address })

  local ok, sendErr = net.send(address, pkt)
  if not ok then
    return nil, "Send failed: " .. tostring(sendErr)
  end

  if log then
    log.info("remote", "Sent command to " .. address:sub(1, 8) ..
      "...: " .. command:sub(1, 40))
  end

  -- Wait for remote_res response via net listener
  local received = false
  local output   = nil
  local exitCode = nil
  local errMsg   = "Timeout waiting for response"

  local resID = net.on(REMOTE_RES, function(rpkt, from)
    if from == address then
      received = true
      local payload = rpkt.payload or {}
      output   = payload.output or ""
      exitCode = payload.exitCode or 0
    end
  end)

  -- Poll until we get a response or timeout
  -- event.pull pumps the OC event loop, which triggers modem_message -> net dispatch
  local deadline = computer.uptime() + TIMEOUT
  while not received and computer.uptime() < deadline do
    event.pull(0.5)
  end

  -- Clean up temporary listener
  net.off(REMOTE_RES, resID)

  if not received then
    return nil, errMsg
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

  local payload = packet.payload or {}
  local cmd = payload.cmd

  if not cmd or cmd == "" then
    local res = protocol.makePacket(REMOTE_RES, {
      output   = "Error: no command provided",
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

  -- Shallow-copy shared libraries so the sandbox cannot poison the host
  local function copyLib(lib)
    local c = {}
    for k, v in pairs(lib) do c[k] = v end
    return c
  end

  local sandbox = {
    print = function(...)
      if outputSize >= OUTPUT_LIMIT then return end
      local args = {...}
      local parts = {}
      for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(args[i])
      end
      local line = table.concat(parts, "\t")
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
    string   = copyLib(string),
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
    local execOk, execErr = pcall(fn)
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

return remote
