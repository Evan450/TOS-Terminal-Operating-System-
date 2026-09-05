-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Module: mouse  —  `mousetest` driver demo            ║
-- ║                                                            ║
-- ║  A small interactive proof that the mouse driver works:    ║
-- ║  draws a few clickable buttons and reports every click,    ║
-- ║  drag, drop, and scroll the screen reports. Mostly it is   ║
-- ║  a worked example of require("mouse") for your own tools.  ║
-- ║                                                            ║
-- ║  Controls: click the buttons; scroll; drag. Click QUIT or  ║
-- ║  press q / Esc to leave.                                   ║
-- ╚══════════════════════════════════════════════════════════╝

local component = require("component")
local computer  = require("computer")
local mouse     = require("mouse")

local mod = {}

mod.commands = {
  mousetest = function(args, o)
    o = o or print

    -- Bind to this seat's GPU (granted by the `component` capability). The
    -- gpu is already attached to this seat's screen, so its coordinate
    -- space matches the touch/drag coordinates we'll receive.
    local gpuAddr = component.list("gpu")()
    if not gpuAddr then o("No GPU found — mousetest needs a screen."); return end
    local gpu = component.proxy(gpuAddr)
    local myScreen = gpu.getScreen and gpu.getScreen() or nil

    local W, H = gpu.getResolution()
    if not W or W < 28 or H < 10 then
      o("Screen too small for mousetest (need ~28x10)."); return
    end

    -- Colour only if the GPU has the depth for it; fall back to mono.
    local depth = (gpu.getDepth and gpu.getDepth()) or 1
    local color = depth > 1
    local function setColors(fg, bg)
      pcall(gpu.setForeground, fg or 0xFFFFFF)
      pcall(gpu.setBackground, bg or 0x000000)
    end

    -- Save nothing fancy — we clear on entry and on exit.
    local function clear()
      setColors(0xFFFFFF, 0x000000)
      gpu.fill(1, 1, W, H, " ")
    end

    -- ── Buttons (each a click region with a payload) ───────
    local buttons = {
      { x = 3,  y = 6, w = 9, h = 3, label = "  RED  ", fg = 0xFFFFFF, bg = color and 0xAA0000 or 0x000000, id = "red"  },
      { x = 14, y = 6, w = 9, h = 3, label = " GREEN ", fg = 0x000000, bg = color and 0x00AA00 or 0x000000, id = "green" },
      { x = 25, y = 6, w = 9, h = 3, label = "  QUIT ", fg = 0xFFFFFF, bg = color and 0x0000AA or 0x000000, id = "quit" },
    }
    local regions = {}
    for _, b in ipairs(buttons) do
      regions[#regions + 1] = mouse.region(b.x, b.y, b.w, b.h, b.id)
    end

    local function drawButton(b)
      setColors(b.fg, b.bg)
      for row = 0, b.h - 1 do gpu.fill(b.x, b.y + row, b.w, 1, " ") end
      local lx = b.x + math.max(0, math.floor((b.w - #b.label) / 2))
      gpu.set(lx, b.y + math.floor(b.h / 2), b.label)
    end

    local status = "Click a button, scroll, or drag. (QUIT / q / ^Q to exit)"
    local scrolls = 0

    local function drawFrame()
      clear()
      setColors(0x55FFFF, 0x000000)
      gpu.set(2, 2, "TOS Mouse Driver — demo")
      setColors(0xAAAAAA, 0x000000)
      gpu.set(2, 3, "require(\"mouse\") turns OC touch/scroll into clean events")
      for _, b in ipairs(buttons) do drawButton(b) end
      setColors(0xFFFFFF, 0x000000)
      gpu.fill(1, H, W, 1, " ")
      gpu.set(2, H, status:sub(1, W - 2))
    end

    local function setStatus(s)
      status = s
      setColors(0xFFFFFF, 0x000000)
      gpu.fill(1, H, W, 1, " ")
      gpu.set(2, H, status:sub(1, W - 2))
    end

    drawFrame()

    -- ── Event loop ─────────────────────────────────────────
    -- We pull RAW signals ourselves (so we can also catch key_down to
    -- quit) and hand each to mouse.parse — the recommended pattern when a
    -- tool needs both mouse and keyboard.
    local running = true
    while running do
      local sig = table.pack(computer.pullSignal(1))
      local name = sig[1]
      if name == "key_down" then
        local ch, code = sig[3], sig[4]
        -- q / Q / ^Q / F10. Esc is still accepted but never relied on:
        -- it closes the screen GUI, so it does not reach the computer.
        if code == 1 or ch == 113 or ch == 81 or ch == 17 or code == 68 then
          running = false
        end
      else
        local ev = mouse.parse(table.unpack(sig, 1, sig.n))
        -- Ignore events from other seats' screens on a multi-seat rig.
        if ev and (not myScreen or not ev.screen or ev.screen == myScreen) then
          if ev.type == "click" then
            local hit = mouse.hit(regions, ev.x, ev.y)
            if hit == "quit" then running = false
            elseif hit then
              setStatus(("Clicked %s button  (cell %d,%d, mouse btn %d)")
                :format(hit:upper(), ev.x, ev.y, ev.button))
            else
              setStatus(("Click @ %d,%d  (button %d) — not on a button")
                :format(ev.x, ev.y, ev.button))
            end
          elseif ev.type == "scroll" then
            scrolls = scrolls + ev.dir
            setStatus(("Scroll %s @ %d,%d  (net %d)")
              :format(ev.dir > 0 and "up" or "down", ev.x, ev.y, scrolls))
          elseif ev.type == "drag" then
            setStatus(("Drag @ %d,%d  (button %d)"):format(ev.x, ev.y, ev.button))
          elseif ev.type == "drop" then
            setStatus(("Drop @ %d,%d"):format(ev.x, ev.y))
          end
        end
      end
    end

    clear()
    setColors(0xFFFFFF, 0x000000)
    gpu.set(1, 1, "mousetest exited.")
    o("mousetest exited. require(\"mouse\") is installed for your own tools.")
  end,
}

return mod
