-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Pipes & Streams        ║
-- ╚══════════════════════════════════════╝
-- Lightweight stream abstraction for shell piping and redirection.

local pipe = {}

-- ============================================================
-- Stream base: read/write/close interface
-- ============================================================

--- Create an in-memory pipe connecting a writer to a reader.
-- Writer puts data into a buffer; reader pulls from it.
-- Small fixed-size buffer to stay within OC memory limits.
function pipe.create()
  local buffer = {}
  local head = 1  -- Index of next item to read (avoids O(n) table.remove)
  local tail = 0  -- Index of last written item
  local closed = false
  -- #SEC M2 — soft cap on bytes pending in the pipe. A producer that
  -- never yields can otherwise grow the buffer indefinitely until the
  -- VM runs out of memory. Once we hit the cap, further writes return
  -- false instead of inserting. Readers drain naturally.
  local MAX_PIPE_BYTES = 64 * 1024
  local pendingBytes = 0

  local function bufferEmpty() return head > tail end

  local function bufferPop()
    if head > tail then return nil end
    local val = buffer[head]
    buffer[head] = nil  -- Allow GC
    head = head + 1
    if type(val) == "string" then
      pendingBytes = math.max(0, pendingBytes - #val)
    end
    -- Reset indices when buffer drains to prevent unbounded growth
    if head > tail then head = 1; tail = 0 end
    return val
  end

  local function bufferPush(val)
    tail = tail + 1
    buffer[tail] = val
    if type(val) == "string" then
      pendingBytes = pendingBytes + #val
    end
  end

  local function bufferPushFront(val)
    head = head - 1
    buffer[head] = val
    if type(val) == "string" then
      pendingBytes = pendingBytes + #val
    end
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
      local s = tostring(data)
      -- #SEC M2 — refuse to grow past the cap. The caller is expected
      -- to yield so the reader can drain; if the caller can't yield
      -- (sync context), they get a write failure and can react.
      if pendingBytes + #s > MAX_PIPE_BYTES then
        return false, "pipe full"
      end
      bufferPush(s)
      return true
    end,
    close = function(self) closed = true end,
  }

  return reader, writer
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

  -- #SEC M3 — quote-aware redirect detection. The previous patterns
  -- searched the raw segment for ">" / ">>" / "<" anywhere, which
  -- meant `echo "x > y"` redirected output to file `y` instead of
  -- printing `x > y`. We now find the FIRST redirect operator
  -- outside of any quotes and split there.
  local function findRedirOutsideQuotes(seg)
    local inQ, qc = false, nil
    local i = 1
    while i <= #seg do
      local c = seg:sub(i, i)
      if inQ then
        if c == qc then inQ = false end
        i = i + 1
      elseif c == '"' or c == "'" then
        inQ = true; qc = c; i = i + 1
      elseif c == "\\" and i < #seg then
        i = i + 2
      elseif c == ">" and seg:sub(i + 1, i + 1) == ">" then
        return i, ">>"
      elseif c == ">" then
        return i, ">"
      elseif c == "<" then
        return i, "<"
      else
        i = i + 1
      end
    end
    return nil
  end

  -- Parse redirections from each segment
  local commands = {}
  for i, seg in ipairs(segments) do
    local cmd = seg
    local stdout_spec = nil
    local stdin_spec = nil

    -- Repeatedly carve off redirects until no more are found OUTSIDE quotes.
    while true do
      local pos, kind = findRedirOutsideQuotes(cmd)
      if not pos then break end
      local before = cmd:sub(1, pos - 1)
      local after  = cmd:sub(pos + #kind):match("^%s*(.-)%s*$") or ""
      -- The filename is the first whitespace-delimited token in `after`.
      local fname = after:match("^(%S+)") or ""
      local rest  = after:sub(#fname + 1):match("^%s*(.-)%s*$") or ""
      if kind == ">>" then
        stdout_spec = { type = "file", path = fname, append = true }
      elseif kind == ">" then
        stdout_spec = { type = "file", path = fname, append = false }
      elseif kind == "<" then
        stdin_spec = { type = "file", path = fname }
      end
      -- The command continues with whatever was BEFORE the redirect,
      -- plus whatever non-filename text trailed (rare; usually empty).
      cmd = before .. (rest ~= "" and (" " .. rest) or "")
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
