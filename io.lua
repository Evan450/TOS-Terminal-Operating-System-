-- TOS OpenOS Compatibility - io Library
-- Provides standard Lua io interface backed by TOS kernel.fs and term

-- Deferred filesystem accessor. Resolves to securefs (permission-checked)
-- when available, so io.open() honors ACLs for non-root users.
local function fs()
  return (_G._TOS and _G._TOS.securefs) or require("kernel.securefs")
end
local buffer = require("compat.buffer")
local term = require("compat.term")

local io = {}

---------------------------------------------------------------------------
-- Internal: wrap an fs file handle into a stream for buffer.new
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- io.open(path, mode) -> file handle or nil, error
---------------------------------------------------------------------------
function io.open(path, mode)
  mode = mode or "r"
  local handle, err = fs().open(path, mode)
  if not handle then
    return nil, err or ("cannot open " .. path)
  end
  return wrapFsHandle(handle, mode)
end

---------------------------------------------------------------------------
-- Stdout / stderr streams backed by term.write
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- io.input / io.output - get or set default streams
---------------------------------------------------------------------------
function io.input(file)
  if file then
    if type(file) == "string" then
      local f, err = io.open(file, "r")
      if not f then error(err, 2) end
      defaultInput = f
    else
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
      defaultOutput = f
    else
      defaultOutput = file
    end
  end
  return defaultOutput
end

---------------------------------------------------------------------------
-- io.read(...) - read from default input
---------------------------------------------------------------------------
function io.read(...)
  return defaultInput:read(...)
end

---------------------------------------------------------------------------
-- io.write(...) - write to default output
---------------------------------------------------------------------------
function io.write(...)
  return defaultOutput:write(...)
end

---------------------------------------------------------------------------
-- io.lines(path) - iterate lines of a file, or default input
---------------------------------------------------------------------------
function io.lines(path)
  if path then
    local f, err = io.open(path, "r")
    if not f then error(err, 2) end
    local closed = false
    return function()
      if closed then return nil end
      local line = f:read("*l")
      if not line then
        f:close()
        closed = true
        return nil
      end
      return line
    end
  else
    return defaultInput:lines()
  end
end

---------------------------------------------------------------------------
-- io.close(file) - close a file, or default output
---------------------------------------------------------------------------
function io.close(file)
  if file then
    return file:close()
  else
    return defaultOutput:close()
  end
end

---------------------------------------------------------------------------
-- io.flush() - flush default output
---------------------------------------------------------------------------
function io.flush()
  if defaultOutput.flush then
    defaultOutput:flush()
  end
end

---------------------------------------------------------------------------
-- io.tmpfile() - not supported on OC, return nil
---------------------------------------------------------------------------
function io.tmpfile()
  return nil, "tmpfile not supported"
end

---------------------------------------------------------------------------
-- io.type(obj) - check if obj is a file handle
---------------------------------------------------------------------------
function io.type(obj)
  if type(obj) ~= "table" then return nil end
  if obj.closed then return "closed file" end
  if obj.read or obj.write then return "file" end
  return nil
end

---------------------------------------------------------------------------
-- io.popen - not supported
---------------------------------------------------------------------------
function io.popen()
  return nil, "popen not supported"
end

return io
