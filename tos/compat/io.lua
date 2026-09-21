local function fs()
  return (_G._TOS and _G._TOS.securefs) or require("kernel.securefs")
end
local buffer = require("compat.buffer")
local term = require("compat.term")

local io = {}

local function wrapFsHandle(handle, mode)
  local stream = {}
  local isRead = mode:find("r") ~= nil
  local isWrite = mode:find("[wa]") ~= nil

  if isRead then
    function stream:read(n)
      return handle:read(n)
    end
  end

  if isWrite then
    function stream:write(data)
      return handle:write(data)
    end
  end

  function stream:close()
    return handle:close()
  end

  function stream:seek(whence, offset)
    if handle.seek then
      return handle:seek(whence, offset)
    end
    return nil, "not seekable"
  end

  return buffer.new(mode, stream)
end

function io.open(path, mode)
  mode = mode or "r"
  local handle, err = fs().open(path, mode)
  if not handle then
    return nil, err or ("cannot open " .. path)
  end
  return wrapFsHandle(handle, mode)
end

local function makeTermOutput()
  local stream = {}
  function stream:write(data) term.write(data, true) end
  function stream:close() end
  return buffer.new("w", stream)
end

local function makeTermInput()
  local stream = {}
  function stream:read()
    local line = term.read()
    if line then return line .. "\n" end
    return nil
  end
  function stream:close() end
  return buffer.new("r", stream)
end

io.stdout = makeTermOutput()
io.stderr = makeTermOutput()
io.stdin  = makeTermInput()

--! #SEC (AUDIT 5, H-05) — THE DEFAULT STREAMS ARE PER PROCESS, not one
--! pair for the machine. They used to be two module upvalues, and
--! sandbox.lua's isolatedModule() isolates a module's TABLE while handing
--! out the ORIGINAL closures -- so every sandbox on the box shared these.
--! One program calling io.output(f) redirected EVERY other program's
--! io.write into its own file, and io.input(f) fed them its own bytes;
--! safeClose made it worse by closing whatever the previous holder had
--! open. Reproduced with two sandbox.build() envs: B's io.write landed in
--! A's sink.
--!
--! Keyed on the PROCESS TABLE rather than the pid, for two reasons: pids
--! are reused once a process is reaped (see the #SEC M-11 generation
--! counter in kernel/process.lua), so a pid key would hand a dead
--! program's redirections to whoever claims that number next; and a weak
--! key lets the record die with the process instead of leaking one entry
--! per program ever run.
--!
--! No process context -- kernel code, early boot, the off-box suite --
--! falls back to a shared pair, which is exactly the old behaviour and is
--! the same convention screen.callerSeat() uses for an unresolvable seat.
--! (test_compat_io_per_process.lua)
local sharedDefaults = { input = io.stdin, output = io.stdout }
local perProcess = setmetatable({}, { __mode = "k" })

local function defaults()
  local okP, proc = pcall(require, "kernel.process")
  if not okP or type(proc) ~= "table" or type(proc.current) ~= "function" then
    return sharedDefaults
  end
  local okC, p = pcall(proc.current)
  if not okC or type(p) ~= "table" then return sharedDefaults end
  local rec = perProcess[p]
  if not rec then

    rec = { input = sharedDefaults.input, output = sharedDefaults.output }
    perProcess[p] = rec
  end
  return rec
end

local function safeClose(stream)
  if not stream then return end
  if stream == io.stdin or stream == io.stdout or stream == io.stderr then
    return
  end
  if type(stream) == "table" and type(stream.close) == "function" then
    pcall(stream.close, stream)
  end
end

function io.input(file)
  local D = defaults()
  if file then
    if type(file) == "string" then
      local f, err = io.open(file, "r")
      if not f then error(err, 2) end
      safeClose(D.input)
      D.input = f
    else
      if file ~= D.input then safeClose(D.input) end
      D.input = file
    end
  end
  return D.input
end

function io.output(file)
  local D = defaults()
  if file then
    if type(file) == "string" then
      local f, err = io.open(file, "w")
      if not f then error(err, 2) end
      safeClose(D.output)
      D.output = f
    else
      if file ~= D.output then safeClose(D.output) end
      D.output = file
    end
  end
  return D.output
end

function io.read(...)
  local D = defaults()
  return D.input:read(...)
end

function io.write(...)
  local D = defaults()
  return D.output:write(...)
end

function io.lines(path)
  local D = defaults()
  if path then
    local f, err = io.open(path, "r")
    if not f then error(err, 2) end
    local closed = false

    local guard = setmetatable({}, { __gc = function()
      if not closed then pcall(function() f:close() end) closed = true end
    end })
    local iter = function()
      if closed then return nil end

      local ok, line = pcall(f.read, f, "*l")
      if not ok or line == nil then
        pcall(function() f:close() end)
        closed = true
        return nil
      end
      return line
    end

    local refKeeper = { iter = iter, guard = guard }
    return function() local _ = refKeeper; return iter() end
  else
    return D.input:lines()
  end
end

function io.close(file)
  local D = defaults()
  if file then
    return file:close()
  else
    return D.output:close()
  end
end

function io.flush()
  local D = defaults()
  if D.output.flush then
    D.output:flush()
  end
end

function io.tmpfile()
  return nil, "tmpfile not supported"
end

function io.type(obj)
  if type(obj) ~= "table" then return nil end
  if obj.closed then return "closed file" end
  if obj.read or obj.write then return "file" end
  return nil
end

function io.popen()
  return nil, "popen not supported"
end

return io
