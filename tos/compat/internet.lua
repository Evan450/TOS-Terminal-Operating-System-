-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Compat - OpenOS `internet` library                   ║
-- ║                                                            ║
-- ║  require("internet") as OpenOS programs expect it:          ║
-- ║    internet.request(url, [data], [headers], [method])       ║
-- ║        -> iterator function; call it for the next chunk,    ║
-- ║           nil at end of stream                              ║
-- ║    internet.socket(address, [port])  -> stream              ║
-- ║    internet.open(address, [port])    -> buffered stream     ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- Faithful to OpenOS's contract, including the parts that are awkward:
-- `request` ERRORS (rather than returning nil, err) when there is no card
-- or the request is refused, because that is what OpenOS does and porting
-- a program should not mean rewriting its error handling.
--
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

-- Cooperative slice: an OpenOS read loop polls until bytes arrive, and on
-- one shared CPU that would otherwise starve every other seat.
local function pause()
  local okP, proc = pcall(require, "kernel.process")
  if okP and proc and proc.yieldCooperative then
    proc.yieldCooperative()
    return
  end
  local okE, ev = pcall(require, "kernel.event")
  if okE and ev and ev.pull then pcall(ev.pull, 0) end
end

--- OpenOS internet.request. Returns a callable that yields body chunks and
--- nil at end of stream; the handle's own methods (read/close/response)
--- remain reachable through __index, as in OpenOS.
function internet.request(url, data, headers, method)
  checkArg(1, url, "string")
  checkArg(2, data, "string", "table", "nil")
  checkArg(3, headers, "table", "nil")
  checkArg(4, method, "string", "nil")

  local inet = card()
  if not inet then error("no primary internet card found", 2) end

  -- OpenOS accepts POST data as a table and form-encodes it.
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
          return nil                    -- end of stream
        elseif #chunk > 0 then
          return chunk
        end
        pause()                         -- no data yet: let other seats run
      end
    end,
    __index = request,
  })
end

-- ── Socket streams ──────────────────────────────────────────
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
  -- A socket write is not guaranteed to take the whole buffer; loop until
  -- it does (OpenOS does the same) or the far end refuses.
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
