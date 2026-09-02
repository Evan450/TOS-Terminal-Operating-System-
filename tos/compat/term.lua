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

local curX, curY = 1, 1
local curBlink = false

function term.isAvailable()
  return true
end

function term.getViewport()
  return display.getSize()
end

function term.clear()
  display.clear()
  curX, curY = 1, 1
  markGlassDirty()
end

function term.setCursor(x, y)
  curX = math.floor(x or 1)
  curY = math.floor(y or 1)
end

function term.getCursor()
  return curX, curY
end

function term.setCursorBlink(b)
  curBlink = not not b
end

function term.getCursorBlink()
  return curBlink
end

function term.write(text, wrap)
  text = tostring(text)
  local w, h = display.getSize()

  local function scroll()
    while curY > h do
      display.scrollUp(1, h)
      curY = curY - 1
    end
  end

  local runStart = nil
  local runChars = nil

  local function flushRun()
    if runChars and #runChars > 0 then
      display.set(runStart, curY, table.concat(runChars))
      runChars = nil
      runStart = nil
    end
  end

  for i = 1, #text do
    local ch = text:sub(i, i)
    if ch == "\n" then
      flushRun()
      curX = 1
      curY = curY + 1
      scroll()
    elseif ch == "\r" then
      flushRun()
      curX = 1
    elseif ch == "\t" then
      flushRun()
      local spaces = 8 - ((curX - 1) % 8)
      local tabStr = string.rep(" ", math.min(spaces, w - curX + 1))
      if #tabStr > 0 and curX <= w then
        display.set(curX, curY, tabStr)
        curX = curX + #tabStr
      end
    else
      if curX > w and wrap then
        flushRun()
        curX = 1
        curY = curY + 1
        scroll()
      end
      if curX <= w and curY <= h then
        if not runChars then
          runStart = curX
          runChars = {}
        end
        runChars[#runChars + 1] = ch
        curX = curX + 1
      end
    end
  end
  flushRun()
  markGlassDirty()
end

function term.clearLine()
  local w = display.getSize()
  display.fill(1, curY, w, 1, " ")
  curX = 1
  markGlassDirty()
end

local GPU_MUTATING = {
  set = true, fill = true, copy = true, bitblt = true,
  setBackground = true, setForeground = true, setPaletteColor = true,
  setResolution = true, setViewport = true, setDepth = true, bind = true,
  setActiveBuffer = true, allocateBuffer = true,
  freeBuffer = true, freeAllBuffers = true,
}

local function resolveSeatGpu()
  local g = nil
  pcall(function() g = display.getGpu and display.getGpu() end)
  if g then return g end
  local addr = component.list("gpu")()
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

function term.screen()
  local addr = component.list("screen")()
  return addr
end

function term.read(history, dobreak, hint, pwchar)
  if dobreak == nil then dobreak = true end
  local line = ""
  local startX, startY = curX, curY
  local w = display.getSize()

  local function redraw()

    curX = startX
    curY = startY
    local show = pwchar and string.rep(pwchar, #line) or line

    local clearLen = w - startX + 1
    if clearLen > 0 then
      display.fill(startX, startY, clearLen, 1, " ")
    end
    display.set(startX, startY, show)
    curX = startX + #show
  end

  while true do
    redraw()
    local ev = {computer.pullSignal()}
    local evType = ev[1]

    if evType == "key_down" then
      local char = ev[3] or 0
      local code = ev[4] or 0

      if char == 13 or char == 10 then

        if dobreak then
          curX = 1
          curY = curY + 1
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
          curX = 1
          curY = curY + 1
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
            curX = 1
            curY = curY + 1
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
