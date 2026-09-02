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

local defaultInput  = io.stdin
local defaultOutput = io.stdout

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
  if file then
    if type(file) == "string" then
      local f, err = io.open(file, "r")
      if not f then error(err, 2) end
      safeClose(defaultInput)
      defaultInput = f
    else
      if file ~= defaultInput then safeClose(defaultInput) end
      defaultInput = file
    end
  end
  return defaultInput
end

function io.output(file)
  if file then
    if type(file) == "string" then
      local f, err = io.open(file, "w")
      if not f then error(err, 2) end
      safeClose(defaultOutput)
      defaultOutput = f
    else
      if file ~= defaultOutput then safeClose(defaultOutput) end
      defaultOutput = file
    end
  end
  return defaultOutput
end

function io.read(...)
  return defaultInput:read(...)
end

function io.write(...)
  return defaultOutput:write(...)
end

function io.lines(path)
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
    return defaultInput:lines()
  end
end

function io.close(file)
  if file then
    return file:close()
  else
    return defaultOutput:close()
  end
end

function io.flush()
  if defaultOutput.flush then
    defaultOutput:flush()
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
