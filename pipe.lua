-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Pipes & Streams      ║
-- ╚══════════════════════════════════════╝
-- Lightweight stream abstraction for shell piping and redirection.

local pipe = {}

-- ============================================================
-- Stream base: read/write/close interface
-- ============================================================

--- Create a string-backed read stream.
function pipe.fromString(str)
  local pos = 1
  return {
    read = function(self, n)
      if pos > #str then return nil end
      local chunk = str:sub(pos, pos + (n or 4096) - 1)
      pos = pos + #chunk
      return chunk
    end,
    readLine = function(self)
      if pos > #str then return nil end
      local nl = str:find("\n", pos, true)
      local line
      if nl then
        line = str:sub(pos, nl - 1)
        pos = nl + 1
      else
        line = str:sub(pos)
        pos = #str + 1
      end
      return line
    end,
    close = function(self) end,
  }
end

--- Create a string-collecting write stream.
-- Call stream:result() after closing to get the accumulated string.
function pipe.toString()
  local parts = {}
  return {
    write = function(self, data)
      parts[#parts + 1] = tostring(data)
      return true
    end,
    close = function(self) end,
    result = function(self)
      return table.concat(parts)
    end,
  }
end

--- Create an in-memory pipe connecting a writer to a reader.
-- Writer puts data into a buffer; reader pulls from it.
-- Small fixed-size buffer to stay within OC memory limits.
function pipe.create()
  local buffer = {}
  local head = 1  -- Index of next item to read (avoids O(n) table.remove)
  local tail = 0  -- Index of last written item
  local closed = false

  local function bufferEmpty() return head > tail end

  local function bufferPop()
    if head > tail then return nil end
    local val = buffer[head]
    buffer[head] = nil  -- Allow GC
    head = head + 1
    -- Reset indices when buffer drains to prevent unbounded growth
    if head > tail then head = 1; tail = 0 end
    return val
  end

  local function bufferPush(val)
    tail = tail + 1
    buffer[tail] = val
  end

  local function bufferPushFront(val)
    head = head - 1
    buffer[head] = val
  end

  local reader = {
    read = function(self, n)
      while bufferEmpty() and not closed do
        if coroutine.isyieldable and coroutine.isyieldable() then
          coroutine.yield()
        else
          return nil
        end
      end
      return bufferPop()
    end,
    readLine = function(self)
      local acc = {}
      while true do
        while bufferEmpty() and not closed do
          if coroutine.isyieldable and coroutine.isyieldable() then
            coroutine.yield()
          else
            if #acc > 0 then return table.concat(acc) end
            return nil
          end
        end
        if bufferEmpty() then
          if #acc > 0 then return table.concat(acc) end
          return nil
        end
        local chunk = bufferPop()
        local nl = chunk:find("\n", 1, true)
        if nl then
          acc[#acc + 1] = chunk:sub(1, nl - 1)
          if nl < #chunk then
            bufferPushFront(chunk:sub(nl + 1))
          end
          return table.concat(acc)
        else
          acc[#acc + 1] = chunk
        end
      end
    end,
    close = function(self) closed = true end,
  }

  local writer = {
    write = function(self, data)
      if closed then return false end
      bufferPush(tostring(data))
      return true
    end,
    close = function(self) closed = true end,
  }

  return reader, writer
end

--- Create a file-backed read stream.
function pipe.fromFile(fsModule, path)
  local content = fsModule.readFile(path)
  if not content then return nil, "Cannot read: " .. path end
  return pipe.fromString(content)
end

--- Create a file-backed write stream (overwrite or append).
function pipe.toFile(fsModule, path, append)
  local parts = {}
  return {
    write = function(self, data)
      parts[#parts + 1] = tostring(data)
      return true
    end,
    close = function(self)
      local content = table.concat(parts)
      if append then
        fsModule.appendFile(path, content)
      else
        fsModule.writeFile(path, content)
      end
    end,
  }
end

--- Parse a command string for pipe/redirect operators.
-- Returns a list of { cmd=string, stdin=spec, stdout=spec }
-- where spec is nil (inherit), or {type="pipe"}, {type="file",path=...,append=bool}
function pipe.parse(input)
  local segments = {}
  local parts = {}

  -- Split on | (pipe operator) respecting quotes
  local inQuote = false
  local quoteChar = nil
  for i = 1, #input do
    local ch = input:sub(i, i)
    if inQuote then
      parts[#parts + 1] = ch
      if ch == quoteChar then inQuote = false end
    elseif ch == '"' or ch == "'" then
      inQuote = true
      quoteChar = ch
      parts[#parts + 1] = ch
    elseif ch == "|" then
      segments[#segments + 1] = table.concat(parts)
      parts = {}
    else
      parts[#parts + 1] = ch
    end
  end
  if #parts > 0 then
    segments[#segments + 1] = table.concat(parts)
  end

  -- Parse redirections from each segment
  local commands = {}
  for i, seg in ipairs(segments) do
    local cmd = seg
    local stdout_spec = nil
    local stdin_spec = nil

    -- Check for >> (append redirect)
    local appendFile = cmd:match(">>%s*(%S+)%s*$")
    if appendFile then
      cmd = cmd:gsub(">>%s*%S+%s*$", "")
      stdout_spec = { type = "file", path = appendFile, append = true }
    else
      -- Check for > (overwrite redirect)
      local outFile = cmd:match(">%s*(%S+)%s*$")
      if outFile then
        cmd = cmd:gsub(">%s*%S+%s*$", "")
        stdout_spec = { type = "file", path = outFile, append = false }
      end
    end

    -- Check for < (input redirect)
    local inFile = cmd:match("<%s*(%S+)")
    if inFile then
      cmd = cmd:gsub("<%s*%S+", "")
      stdin_spec = { type = "file", path = inFile }
    end

    -- Inter-command pipes
    if i > 1 and not stdin_spec then
      stdin_spec = { type = "pipe", index = i - 1 }
    end
    if i < #segments and not stdout_spec then
      stdout_spec = { type = "pipe", index = i + 1 }
    end

    commands[#commands + 1] = {
      cmd    = cmd:match("^%s*(.-)%s*$"),  -- trim
      stdin  = stdin_spec,
      stdout = stdout_spec,
    }
  end

  return commands
end

return pipe
