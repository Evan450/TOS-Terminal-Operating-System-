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
-- #SEC H32 — close the previous default stream before swapping it out.
-- The old implementation just reassigned the local, leaking the underlying
-- filesystem handle each time. OC has a tight fd ceiling per FS proxy, so
-- a loop of io.input("x"); io.input("y") would exhaust handles fast.
-- We skip closing the built-in stdin/stdout/stderr handles since those
-- are terminal-backed and the close is a no-op (or worse, marks them
-- dead for the rest of the session).
local function safeClose(stream)
  if not stream then return end
  if stream == io.stdin or stream == io.stdout or stream == io.stderr then
    return  -- never close the well-known terminals
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
    -- #SEC H32 — attach a finalizer so an abandoned iterator (program
    -- breaks out of `for line in io.lines(p)` early) still releases the
    -- underlying fd. Lua 5.3 honours __gc on tables; the iterator's own
    -- closure is unreachable so __close (5.4) isn't useful here, but a
    -- container table with __gc works for both.
    local guard = setmetatable({}, { __gc = function()
      if not closed then pcall(function() f:close() end) closed = true end
    end })
    local iter = function()
      if closed then return nil end
      -- #SEC L — close the fd eagerly on EOF *or* a read error, instead of
      -- leaving an errored handle to the non-deterministic __gc finalizer
      -- (the fragile path). The guard's __gc remains a backstop for the
      -- early-break case (program leaves the for-loop before EOF).
      local ok, line = pcall(f.read, f, "*l")
      if not ok or line == nil then
        pcall(function() f:close() end)
        closed = true
        return nil
      end
      return line
    end
    -- Keep `guard` alive as long as `iter` is reachable.
    local refKeeper = { iter = iter, guard = guard }
    return function() local _ = refKeeper; return iter() end
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
