--! This shim reaches the internet card DIRECTLY, exactly as the OpenOS
--! library does — an OpenOS program's `internet.request` is expected to
--! stream, and routing it through kernel.internet's bounded string reader
--! would change its semantics. Reaching it at all still requires the
--! `internet` capability: without it the sandbox does not expose the
--! component type, `component.isAvailable("internet")` is false, and this
--! library reports no card. The capability is the gate; this file is the
--! shape.

local component = require("component")

local internet = {}

local function checkArg(n, have, ...)
  local want = { ... }
  local t = type(have)
  for _, w in ipairs(want) do
    if t == w then return end
  end
  error("bad argument #" .. n .. " (" .. table.concat(want, " or ")
    .. " expected, got " .. t .. ")", 3)
end

local function card()
  local addr = component.list and component.list("internet")()
  if not addr then return nil end
  local ok, p = pcall(component.proxy, addr)
  if not ok then return nil end
  return p
end

local function pause()
  local okP, proc = pcall(require, "kernel.process")
  if okP and proc and proc.yieldCooperative then
    proc.yieldCooperative()
    return
  end
  local okE, ev = pcall(require, "kernel.event")
  if okE and ev and ev.pull then pcall(ev.pull, 0) end
end

function internet.request(url, data, headers, method)
  checkArg(1, url, "string")
  checkArg(2, data, "string", "table", "nil")
  checkArg(3, headers, "table", "nil")
  checkArg(4, method, "string", "nil")

  local inet = card()
  if not inet then error("no primary internet card found", 2) end

  local post
  if type(data) == "string" then
    post = data
  elseif type(data) == "table" then
    for k, v in pairs(data) do
      post = post and (post .. "&") or ""
      post = post .. tostring(k) .. "=" .. tostring(v)
    end
  end

  local request, reason = inet.request(url, post, headers, method)
  if not request then error(tostring(reason or "request failed"), 2) end

  return setmetatable({
    close = setmetatable({}, {
      __call = function() return request.close() end,
      __tostring = function() return "function() -- closes the connection" end,
    }),
  }, {
    __call = function()
      while true do
        local chunk, err = request.read()
        if not chunk then
          pcall(function() request.close() end)
          if err then error(err, 2) end
          return nil
        elseif #chunk > 0 then
          return chunk
        end
        pause()
      end
    end,
    __index = request,
  })
end

local socketStream = {}

function socketStream:close()
  if self.socket then
    pcall(function() self.socket.close() end)
    self.socket = nil
  end
end

function socketStream:seek() return nil, "bad file descriptor" end

function socketStream:read(n)
  if not self.socket then return nil, "connection is closed" end
  return self.socket.read(n)
end

function socketStream:write(value)
  if not self.socket then return nil, "connection is closed" end

  while #value > 0 do
    local written, reason = self.socket.write(value)
    if not written then return nil, reason end
    value = string.sub(value, written + 1)
  end
  return true
end

function internet.socket(address, port)
  checkArg(1, address, "string")
  checkArg(2, port, "number", "nil")
  local inet = card()
  if not inet then return nil, "no primary internet card found" end
  if not inet.connect then return nil, "internet card has no TCP support" end
  local target = port and (address .. ":" .. port) or address
  local socket, reason = inet.connect(target)
  if not socket then return nil, reason end
  return setmetatable({ inet = inet, socket = socket },
    { __index = socketStream, __metatable = "socketstream" })
end

function internet.open(address, port)
  local stream, reason = internet.socket(address, port)
  if not stream then return nil, reason end
  local ok, buffer = pcall(require, "buffer")
  if not ok or not buffer or not buffer.new then
    return nil, "buffer library unavailable"
  end
  return buffer.new("rwb", stream)
end

return internet
