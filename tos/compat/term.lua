local display = require("kernel.display")

local function markGlassDirty()
  local ok, screenMod = pcall(require, "kernel.screen")
  if ok and screenMod and screenMod.invalidateAll then
    pcall(screenMod.invalidateAll)
  end
  if display.invalidateColors then pcall(display.invalidateColors) end
end
local computer = require("computer")
local component = require("component")

local term = {}

--! #SEC (AUDIT 5, H-06) — the cursor was three module upvalues, one copy
--! for the whole machine. Every sandbox gets its own VIEW of this module,
--! but the functions are the same closures, so one program's setCursor
--! moved every other program's: after A set (40,12), B's getCursor said
--! (40,12) and B's write landed there -- on B's own screen, at A's spot.
--! H-05 fixed the same leak for io's default streams by keying them per
--! PROCESS. A cursor is not a process property, it is a property of the
--! glass: one terminal per seat, so programs taking turns on one seat
--! share it, as they would on one real terminal, and two seats never do.
--! A caller with no seat (kernel, boot, off-box) keeps the old single
--! cursor, so nothing outside a seat changes. (test_compat_term_seat.lua)
local sharedCursor = { x = 1, y = 1, blink = false }
local seatCursors  = {}

local screenMod = nil
local function getScreen()
  if screenMod == nil then
    local ok, m = pcall(require, "kernel.screen")
    screenMod = (ok and type(m) == "table") and m or false
  end
  return screenMod or nil
end

local function callerSeat()
  local scr = getScreen()
  if not (scr and scr.callerSeat) then return nil end
  local ok, idx = pcall(scr.callerSeat)
  return ok and idx or nil
end

local function cursor()
  local seat = callerSeat()
  if seat == nil then return sharedCursor end
  local c = seatCursors[seat]
  if not c then
    c = { x = 1, y = 1, blink = false }
    seatCursors[seat] = c
  end
  return c
end

local function seatDevices()
  local seat = callerSeat()
  if seat == nil then return nil end
  local scr = getScreen()
  local ok, dev = pcall(scr.seatDevices, seat)
  return (ok and type(dev) == "table") and dev or {}
end

function term.isAvailable()
  return true
end

function term.getViewport()
  return display.getSize()
end

function term.clear()
  display.clear()
  local c = cursor()
  c.x, c.y = 1, 1
  markGlassDirty()
end

function term.setCursor(x, y)
  local c = cursor()
  c.x = math.floor(tonumber(x) or 1)
  c.y = math.floor(tonumber(y) or 1)
end

function term.getCursor()
  local c = cursor()
  return c.x, c.y
end

function term.setCursorBlink(b)
  cursor().blink = not not b
end

function term.getCursorBlink()
  return cursor().blink
end

function term.write(text, wrap)
  text = tostring(text)
  local w, h = display.getSize()
  local c = cursor()

  local function scroll()
    while c.y > h do
      display.scrollUp(1, h)
      c.y = c.y - 1
    end
  end

  local runStart = nil
  local runChars = nil

  local function flushRun()
    if runChars and #runChars > 0 then
      display.set(runStart, c.y, table.concat(runChars))
      runChars = nil
      runStart = nil
    end
  end

  for i = 1, #text do
    local ch = text:sub(i, i)
    if ch == "\n" then
      flushRun()
      c.x = 1
      c.y = c.y + 1
      scroll()
    elseif ch == "\r" then
      flushRun()
      c.x = 1
    elseif ch == "\t" then
      flushRun()
      local spaces = 8 - ((c.x - 1) % 8)
      local tabStr = string.rep(" ", math.min(spaces, w - c.x + 1))
      if #tabStr > 0 and c.x <= w then
        display.set(c.x, c.y, tabStr)
        c.x = c.x + #tabStr
      end
    else
      if c.x > w and wrap then
        flushRun()
        c.x = 1
        c.y = c.y + 1
        scroll()
      end
      if c.x <= w and c.y <= h then
        if not runChars then
          runStart = c.x
          runChars = {}
        end
        runChars[#runChars + 1] = ch
        c.x = c.x + 1
      end
    end
  end
  flushRun()
  markGlassDirty()
end

function term.clearLine()
  local w = display.getSize()
  local c = cursor()
  display.fill(1, c.y, w, 1, " ")
  c.x = 1
  markGlassDirty()
end

local GPU_MUTATING = {
  set = true, fill = true, copy = true, bitblt = true,
  setBackground = true, setForeground = true, setPaletteColor = true,
  setResolution = true, setViewport = true, setDepth = true, bind = true,
  setActiveBuffer = true, allocateBuffer = true,
  freeBuffer = true, freeAllBuffers = true,
}

--! #SEC (AUDIT 5, H-07) — and that fallback is the caller SEAT's GPU. It
--! was component.list("gpu")(), the machine's first -- seat 1's -- for a
--! program on any seat. Only a caller with no seat at all still gets it.
local function resolveSeatGpu()
  local g = nil
  pcall(function() g = display.getGpu and display.getGpu() end)
  if g then return g end
  local dev = seatDevices()
  local addr
  if dev then addr = dev.gpu else addr = component.list("gpu")() end
  if not addr then return nil end
  local ok, raw = pcall(component.proxy, addr)
  if ok then return raw end
  return nil
end

local function makeGpuProxy(allowMutate)
  if not resolveSeatGpu() then return nil end
  return setmetatable({}, {
    __index = function(_, key)
      if GPU_MUTATING[key] and not allowMutate then
        return function()
          return false, "gpu." .. key .. " requires a display capability"
        end
      end
      local g = resolveSeatGpu()
      if not g then return nil end
      local v = g[key]
      if type(v) == "function" then

        if GPU_MUTATING[key] then

          return function(...)
            local r = table.pack(g[key](...))
            markGlassDirty()
            return table.unpack(r, 1, r.n)
          end
        end
        return function(...) return g[key](...) end
      end
      return v
    end,
    __newindex = function() error("term.gpu() proxy is read-only", 2) end,
    __metatable = false,
  })
end

function term.gpu()

  return makeGpuProxy(false)
end

function term._gpuForCaps(caps)
  local allow = (caps and (caps["gpu"] or caps["display"])) and true or false
  return makeGpuProxy(allow)
end

--! #SEC (AUDIT 5, H-07) — the caller seat's screen, not the machine's
--! first one. A caller with no seat (single-seat machine, kernel) keeps the
--! old answer.
function term.screen()
  local dev = seatDevices()
  if dev then return dev.screen end
  local addr = component.list("screen")()
  return addr
end

--! #SEC (AUDIT 5, H-04) — input arrives the way the shells read it, not
--! off the machine's queue. This was `computer.pullSignal()`, raw and
--! untimed, from a module that loads OUTSIDE the sandbox (so the real
--! computer) and is reachable with no capability through `compat.`:
--!   * it POPPED the next signal before proc.tick could route it -- a key
--!     typed on another seat, a modem packet another process was waiting
--!     for -- and consumed it here;
--!   * with no timeout, it blocked in C inside the coroutine, so the
--!     scheduler never got control back and every seat on the machine
--!     froze until a key was pressed somewhere.
--! Inside a process it now YIELDS: proc.tick resumes it with this seat's
--! routed input (and broadcasts, each process its own copy), exactly as
--! sandbox.safePullSignal and the panels shell do. Only with no scheduler
--! to yield to (boot, off-box) does it fall back to a raw pull, bounded.
local function nextSignal()
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
  return computer.pullSignal(0.5)
end

function term.read(history, dobreak, hint, pwchar)
  if dobreak == nil then dobreak = true end
  local line = ""
  local c = cursor()
  local startX, startY = c.x, c.y
  local w = display.getSize()

  local function redraw()

    c.x = startX
    c.y = startY
    local show = pwchar and string.rep(pwchar, #line) or line

    local clearLen = w - startX + 1
    if clearLen > 0 then
      display.fill(startX, startY, clearLen, 1, " ")
    end
    display.set(startX, startY, show)
    c.x = startX + #show
  end

  local shown = nil
  while true do
    if shown ~= line then redraw(); shown = line end
    local ev = table.pack(nextSignal())
    local evType = ev[1]

    if evType == "key_down" then
      local char = ev[3] or 0
      local code = ev[4] or 0

      if char == 13 or char == 10 then

        if dobreak then
          c.x = 1
          c.y = c.y + 1
        end

        if pwchar then
          local result = line
          line = ""
          pcall(function() if type(collectgarbage) == "function" then collectgarbage("collect") end end)
          return result
        end
        return line
      elseif char == 8 or code == 14 then

        if #line > 0 then
          line = line:sub(1, -2)
        end
      elseif char == 3 then

        if dobreak then
          c.x = 1
          c.y = c.y + 1
        end
        return nil
      elseif char == 4 then

        if #line == 0 then
          return nil
        end
      elseif char >= 32 and char < 127 then
        line = line .. string.char(char)
      end
    elseif evType == "clipboard" then

      local text = ev[3]
      if text then

        text = text:gsub("\0", "")

        local nl = text:find("\n", 1, true)
        if nl then
          line = line .. text:sub(1, nl - 1)
          redraw()
          if dobreak then
            c.x = 1
            c.y = c.y + 1
          end
          return line
        else
          line = line .. text
        end
      end
    end
  end
end

return term
