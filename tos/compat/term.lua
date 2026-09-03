-- TOS OpenOS Compatibility - Terminal API
-- Maps OpenOS term calls to TOS kernel.display and kernel.event

local display = require("kernel.display")

-- Everything below draws through kernel.display, which writes STRAIGHT
-- to the GPU. A seat proxy watching that same GPU keeps a dirty-cell
-- shadow and elides any repaint of cells it believes are already
-- correct -- so a compat program writing output here silently poisons
-- the shell's shadow, and the next status-bar or output-row repaint in
-- a matching colour is skipped and leaves whatever the program left.
--
-- The boot battery measured this: after a write behind the proxy's
-- back, a full-row repaint in the "already correct" colour landed on 0
-- of 80 columns. Bumping the generation counter makes every live proxy
-- re-sync on its next draw, which costs one integer.
--
-- There are TWO caches over one piece of glass and they fail
-- differently. The seat proxy's shadow says "this cell already reads
-- like that"; kernel.display's _lastFg/_lastBg says "the hardware is
-- already set to that colour". A write behind either one leaves it
-- asserting something that stopped being true. Compat's own term.*
-- calls go through display, so only the shadow is at risk there -- but
-- term.gpu() hands a program the raw GPU, and then both are. Clear both:
-- being wrong here is a black status bar, being redundant here is one
-- extra setForeground.
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
  markGlassDirty()
end

function term.clearLine()
  local w = display.getSize()
  display.fill(1, curY, w, 1, " ")
  curX = 1
  markGlassDirty()
end

-- #SEC CR-8 — GPU methods that change what's on screen or rebind
-- hardware. These are denied to callers without a display capability,
-- because the old passthrough handed out a RAW proxy resolved via
-- component.list("gpu")() — the FIRST GPU, not the caller's seat — so a
-- sandboxed program on a multi-seat rig could draw onto (and rebind)
-- another seat's screen. Read-only queries (getResolution, getDepth,
-- get, getBackground, getForeground, maxResolution, getPaletteColor, …)
-- always pass through.
local GPU_MUTATING = {
  set = true, fill = true, copy = true, bitblt = true,
  setBackground = true, setForeground = true, setPaletteColor = true,
  setResolution = true, setViewport = true, setDepth = true, bind = true,
  setActiveBuffer = true, allocateBuffer = true,
  freeBuffer = true, freeAllBuffers = true,
}

-- Resolve the GPU bound to the caller's seat. Prefer the kernel display's
-- currently-bound GPU (inside a seat's draw context this IS that seat's
-- GPU); only fall back to the first component GPU when display has none.
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

-- Build a term.gpu() proxy. `allowMutate` gates the mutating methods
-- above; without it, mutating calls return (false, reason) and only
-- read-only queries work. The GPU is resolved lazily on every access so
-- the proxy tracks the active seat's GPU rather than capturing the first.
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
        -- OC component methods take args directly (no self); forward as-is.
        if GPU_MUTATING[key] then
          -- ...but a mutating call moves the hardware behind kernel.display's
          -- back. Its colour cache would go on asserting a colour that is no
          -- longer set, and the next display.fill would skip itself as
          -- redundant -- which is how the status bar ends up painted in
          -- whatever the last compat program left behind. Tell both layers
          -- the truth changed: the colour cache, and the seat's shadow.
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
  -- Default (no caps context, e.g. kernel-side require): read-only.
  return makeGpuProxy(false)
end

-- #SEC CR-8 — caps-aware builder. The sandbox overrides `.gpu` on each
-- per-sandbox compat.term copy with a closure that calls this, granting a
-- mutation-capable proxy ONLY to processes that hold a display capability
-- (caps["gpu"] or caps["display"]).
function term._gpuForCaps(caps)
  local allow = (caps and (caps["gpu"] or caps["display"])) and true or false
  return makeGpuProxy(allow)
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
        -- #SEC L (term.read password retention) — when in password
        -- mode, run a GC pass after capturing the result so the
        -- intermediate `line` substring is reclaimed promptly rather
        -- than lingering in the Lua string-interning table for the
        -- next allocation cycle. Best-effort: collectgarbage may not
        -- be present in OC sandboxes; pcall keeps it safe.
        if pwchar then
          local result = line
          line = ""  -- drop our local ref
          pcall(function() if type(collectgarbage) == "function" then collectgarbage("collect") end end)
          return result
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
        -- #SEC L — strip NUL bytes; downstream consumers truncate at \0
        -- and the user's "what I see" no longer matches "what I typed".
        text = text:gsub("\0", "")
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
