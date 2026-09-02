local notify = {}

notify.MIN_SOURCE_GAP = 10

notify.MIN_GAP = 3

notify.MAX_QUEUE = 8

notify.DEFAULT_TTL = 120

notify.MAX_TTL = 3600

notify.MAX_TITLE   = 40
notify.MAX_MESSAGE = 400
notify.MAX_BUTTONS = 4

local VALID_STYLES = {
  info = true, warn = true, danger = true, error = true,
  install = true, general = true,
}

local queue   = {}
local seq     = 0
local lastBy  = {}
local results = {}

local function now(clock)
  if clock then return clock end
  local ok, computer = pcall(require, "computer")
  if ok and computer and computer.uptime then return computer.uptime() end
  return 0
end

local function log()
  local TOS = _G._TOS or {}
  if TOS.logObj and TOS.logObj.info then return TOS.logObj end
  local ok, mod = pcall(require, "kernel.log")
  if ok and mod and mod.info then return mod end
end

function notify.sanitize(spec)
  if type(spec) ~= "table" then return nil, "spec must be a table" end
  local message = spec.message or spec.body
  if type(message) ~= "string" or message == "" then
    return nil, "a notice needs a message"
  end
  local from = tostring(spec.from or "?"):sub(1, 24)
  if from == "" then from = "?" end

  local buttons = {}
  if type(spec.buttons) == "table" then
    for _, b in ipairs(spec.buttons) do
      if type(b) == "string" and b ~= "" and #buttons < notify.MAX_BUTTONS then
        buttons[#buttons + 1] = b:sub(1, 16)
      end
    end
  end
  if #buttons == 0 then buttons = { "OK" } end

  local ttl = tonumber(spec.ttl) or notify.DEFAULT_TTL
  if ttl <= 0 or ttl > notify.MAX_TTL then ttl = notify.DEFAULT_TTL end

  return {
    from    = from,
    title   = tostring(spec.title or from):sub(1, notify.MAX_TITLE),
    message = message:sub(1, notify.MAX_MESSAGE),
    buttons = buttons,
    style   = VALID_STYLES[spec.style or ""] and spec.style or "info",
    ttl     = ttl,
  }
end

function notify.post(spec, clock)
  local n, why = notify.sanitize(spec)
  if not n then return nil, why end
  local t = now(clock)

  local L = log()
  if L then L.info("notify", "[" .. n.from .. "] " .. n.message) end

  if #queue >= notify.MAX_QUEUE then
    return nil, "too many notices already waiting"
  end
  local last = lastBy[n.from]
  if last and (t - last) < notify.MIN_SOURCE_GAP then
    return nil, string.format("%s posted %.0fs ago (min gap %ds)",
      n.from, t - last, notify.MIN_SOURCE_GAP)
  end

  seq = seq + 1
  n.seq = seq
  n.id  = seq
  n.at  = t
  lastBy[n.from] = t
  queue[#queue + 1] = n
  return n.id
end

function notify.highWater() return seq end

function notify.pending(afterSeq, clock)
  afterSeq = tonumber(afterSeq) or 0
  local t = now(clock)
  local out, high = {}, afterSeq
  for _, n in ipairs(queue) do
    if n.seq > high then high = n.seq end
    if n.seq > afterSeq and (t - n.at) <= n.ttl then out[#out + 1] = n end
  end
  return out, high
end

function notify.nextToShow(list, lastShownAt, clock)
  local t = now(clock)
  if type(list) ~= "table" or #list == 0 then return nil, "nothing pending" end
  if lastShownAt and (t - lastShownAt) < notify.MIN_GAP then
    return nil, string.format("quiet window (%.0fs of %ds left)",
      notify.MIN_GAP - (t - lastShownAt), notify.MIN_GAP)
  end
  for _, n in ipairs(list) do
    if (t - n.at) <= n.ttl then return n end
  end
  return nil, "everything pending has expired"
end

function notify.settle(id, buttonIndex)
  for i, n in ipairs(queue) do
    if n.id == id then
      table.remove(queue, i)
      results[id] = tonumber(buttonIndex) or 1
      return true
    end
  end
  return false
end

function notify.result(id) return results[id] end

function notify.sweep(clock)
  local t = now(clock)
  local dropped = 0
  for i = #queue, 1, -1 do
    if (t - queue[i].at) > queue[i].ttl then
      table.remove(queue, i); dropped = dropped + 1
    end
  end
  if dropped > 0 then
    local L = log()
    if L then L.info("notify", dropped .. " notice(s) expired unseen") end
  end
  return dropped
end

function notify.depth() return #queue end

function notify._reset()
  queue, seq, lastBy, results = {}, 0, {}, {}
end

return notify
