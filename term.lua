-- TOS OpenOS Compatibility - Terminal API
-- Maps OpenOS term calls to TOS kernel.display and kernel.event

local display = require("kernel.display")
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

  -- Buffer runs of normal characters to reduce GPU calls
  local runStart = nil  -- X position where current run started
  local runChars = nil  -- table of chars in current run

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
end

function term.clearLine()
  local w = display.getSize()
  display.fill(1, curY, w, 1, " ")
  curX = 1
end

function term.gpu()
  local addr = component.list("gpu")()
  if addr then
    return component.proxy(addr)
  end
  return nil
end

function term.screen()
  local addr = component.list("screen")()
  return addr
end

--- Read a line of input from the terminal.
-- @param history  table of previous input strings (optional, unused in minimal impl)
-- @param dobreak  if true, print newline after enter (default true)
-- @param hint     hint callback (optional, unused in minimal impl)
-- @param pwchar   password mask character (optional)
-- @return string  the entered line, or nil on ctrl-d/ctrl-c
function term.read(history, dobreak, hint, pwchar)
  if dobreak == nil then dobreak = true end
  local line = ""
  local startX, startY = curX, curY
  local w = display.getSize()

  local function redraw()
    -- Redraw the input area
    curX = startX
    curY = startY
    local show = pwchar and string.rep(pwchar, #line) or line
    -- Clear from startX to end of line
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
        -- Enter
        if dobreak then
          curX = 1
          curY = curY + 1
        end
        return line
      elseif char == 8 or code == 14 then
        -- Backspace
        if #line > 0 then
          line = line:sub(1, -2)
        end
      elseif char == 3 then
        -- Ctrl-C
        if dobreak then
          curX = 1
          curY = curY + 1
        end
        return nil
      elseif char == 4 then
        -- Ctrl-D
        if #line == 0 then
          return nil
        end
      elseif char >= 32 and char < 127 then
        line = line .. string.char(char)
      end
    elseif evType == "clipboard" then
      -- Paste from clipboard
      local text = ev[3]
      if text then
        -- Only take up to first newline
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
