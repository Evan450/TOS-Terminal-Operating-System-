-- TOS OpenOS Compatibility - Buffered Streams
-- Minimal buffer wrapper compatible with OpenOS stream interface
-- Wraps a raw stream (with read/write/close/seek) into a buffered handle

local buffer = {}

function buffer.new(mode, stream)
  local buf = {
    mode = mode or "r",
    stream = stream,
    readBuf = "",
    closed = false,
  }

  function buf:read(fmt)
    if self.closed then return nil, "closed" end
    fmt = fmt or "*l"
    if fmt == "*a" or fmt == "a" then
      local parts = {self.readBuf}
      self.readBuf = ""
      while true do
        local chunk = self.stream:read(4096)
        if not chunk then break end
        parts[#parts + 1] = chunk
      end
      return table.concat(parts)
    elseif fmt == "*l" or fmt == "l" then
      while true do
        local nl = self.readBuf:find("\n", 1, true)
        if nl then
          local line = self.readBuf:sub(1, nl - 1)
          self.readBuf = self.readBuf:sub(nl + 1)
          return line
        end
        local chunk = self.stream:read(4096)
        if not chunk then
          if #self.readBuf > 0 then
            local rest = self.readBuf
            self.readBuf = ""
            return rest
          end
          return nil
        end
        self.readBuf = self.readBuf .. chunk
      end
    elseif fmt == "*n" or fmt == "n" then
      -- Read a number: accumulate digits from the buffer
      -- Skip leading whitespace, return nil immediately for non-numeric input
      while true do
        -- Strip leading whitespace for inspection
        local stripped = self.readBuf:match("^%s*(.*)")
        if stripped and #stripped > 0 then
          -- Check if the first non-whitespace char could start a number
          local firstCh = stripped:sub(1, 1)
          if not firstCh:match("[%d%+%-%.eE]") then
            return nil  -- Non-numeric input, return nil immediately
          end
          local s = self.readBuf:match("^%s*([%+%-]?%d[%d%.eE%+%-]*)")
          if s then
            local num = tonumber(s)
            if num then
              local _, endpos = self.readBuf:find("^%s*[%+%-]?%d[%d%.eE%+%-]*")
              self.readBuf = self.readBuf:sub((endpos or 0) + 1)
              return num
            end
            return nil
          end
          -- Have non-whitespace chars but no full number yet -- may need more data
          -- if buffer is already large enough, give up
          if #stripped > 64 then return nil end
        end
        local chunk = self.stream:read(256)
        if not chunk then return nil end
        self.readBuf = self.readBuf .. chunk
      end
    elseif type(fmt) == "number" then
      local want = fmt
      while #self.readBuf < want do
        local chunk = self.stream:read(want - #self.readBuf)
        if not chunk then break end
        self.readBuf = self.readBuf .. chunk
      end
      if #self.readBuf == 0 then return nil end
      local data = self.readBuf:sub(1, want)
      self.readBuf = self.readBuf:sub(want + 1)
      return data
    end
  end

  function buf:write(...)
    if self.closed then return nil, "closed" end
    for i = 1, select("#", ...) do
      local s = tostring(select(i, ...))
      self.stream:write(s)
    end
    return self
  end

  function buf:lines()
    return function()
      return self:read("*l")
    end
  end

  function buf:close()
    if self.closed then return nil, "closed" end
    self.closed = true
    if self.stream.close then self.stream:close() end
    return true
  end

  function buf:seek(whence, offset)
    if self.stream.seek then
      self.readBuf = ""
      return self.stream:seek(whence, offset)
    end
    return nil, "not seekable"
  end

  function buf:flush()
    -- No write buffering in this minimal implementation
    return self
  end

  return buf
end

return buffer
