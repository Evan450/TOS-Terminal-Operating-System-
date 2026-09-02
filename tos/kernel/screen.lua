local component = require("component")
local computer = require("computer")

local screen = {}

local displays = {}

local seatIndexByScreen = {}
local activeIdx = 1
local initialized = false

local policySpec = nil

local kbToDisplay = {}

local screenToDisplay = {}

local bufferMode = "auto"
local bufferGen  = 0

local _drawSkipped, _drawEmitted = 0, 0

local function liveIndices()
  local idxs = {}
  for i in pairs(displays) do idxs[#idxs + 1] = i end
  table.sort(idxs)
  return idxs
end

local function findKeyboards(scrAddr)
  local kbs = {}

  local okList, kbList = pcall(component.invoke, scrAddr, "getKeyboards")
  if okList and type(kbList) == "table" then
    for _, kb in ipairs(kbList) do kbs[#kbs + 1] = kb end
    return kbs
  end

  return kbs
end

local function isLocalComponent(addr)
  if not addr then return false end
  local okS, slot = pcall(component.slot, addr)
  if not okS then return true end
  return slot ~= nil and slot >= 0
end

local function listLocalThenRemote(ctype)
  local locals, remotes = {}, {}
  for addr in component.list(ctype) do
    if isLocalComponent(addr) then locals[#locals + 1] = addr
    else remotes[#remotes + 1] = addr end
  end

  table.sort(locals)
  table.sort(remotes)
  if #locals > 0 then return locals, remotes end
  return remotes, {}
end

function screen._pair(gpuScreens, screenAddrs)
  local avail = {}
  for _, a in ipairs(screenAddrs) do avail[a] = true end
  local claimed, result = {}, {}

  for i, cur in ipairs(gpuScreens) do
    if cur and avail[cur] and not claimed[cur] then
      claimed[cur] = true
      result[i] = cur
    end
  end

  local free = {}
  for _, a in ipairs(screenAddrs) do if not claimed[a] then free[#free + 1] = a end end
  local fi = 1
  for i = 1, #gpuScreens do
    if not result[i] and fi <= #free then
      result[i] = free[fi]; fi = fi + 1
    end
  end
  return result
end

function screen.init()
  displays = {}
  kbToDisplay = {}
  screenToDisplay = {}

  local gpuAddrs, gpuRemotes    = listLocalThenRemote("gpu")
  local screenAddrs, scrRemotes = listLocalThenRemote("screen")

  local gpus = {}
  for _, addr in ipairs(gpuAddrs) do
    gpus[#gpus + 1] = component.proxy(addr)
  end

  local gpuScreens = {}
  for i, gpu in ipairs(gpus) do
    local okS, s = pcall(gpu.getScreen)
    gpuScreens[i] = (okS and type(s) == "string") and s or false
  end
  local pairing = screen._pair(gpuScreens, screenAddrs)

  local paired = {}
  for i = 1, #gpus do
    if pairing[i] then paired[#paired + 1] = { gpu = gpus[i], scr = pairing[i] } end
  end
  if #paired == 0 then

    local gpuAddr = component.list("gpu")()
    local scrAddr = component.list("screen")()
    if gpuAddr and scrAddr then
      paired[1] = { gpu = component.proxy(gpuAddr), scr = scrAddr, label = "Primary" }
    end
  end
  local taken = {}
  for _, pr in ipairs(paired) do
    local idx = seatIndexByScreen[pr.scr]
    if idx and not taken[idx] then pr.idx = idx; taken[idx] = true end
  end
  for _, pr in ipairs(paired) do
    if not pr.idx then
      local idx = 1
      while taken[idx] do idx = idx + 1 end
      pr.idx = idx; taken[idx] = true
    end
    seatIndexByScreen[pr.scr] = pr.idx
  end

  for _, pr in ipairs(paired) do
    local gpu, scrAddr, idx = pr.gpu, pr.scr, pr.idx

    pcall(gpu.bind, scrAddr)

    do
      local tw, th = screen.gpuTarget(gpu, scrAddr, policySpec or { mode = "auto" })
      screen.applyResolution(gpu, tw, th)
    end
    local w, h = gpu.getResolution()
    local depth = gpu.getDepth()
    local kbs = findKeyboards(scrAddr)
    displays[idx] = {
      gpu       = gpu,
      screen    = scrAddr,
      w         = w,
      h         = h,
      depth     = depth,
      label     = pr.label or ("Screen " .. idx),
      keyboards = kbs,
    }

    screenToDisplay[scrAddr] = idx
    for _, kb in ipairs(kbs) do
      kbToDisplay[kb] = idx
    end
  end

  local live = liveIndices()
  if #live > 0 then
    local rr = 0
    local kbAddrs = listLocalThenRemote("keyboard")
    for _, addr in ipairs(kbAddrs) do
      if not kbToDisplay[addr] then
        rr = rr + 1

        local idx = live[((rr - 1) % #live) + 1]
        kbToDisplay[addr] = idx
        displays[idx].keyboards = displays[idx].keyboards or {}
        displays[idx].keyboards[#displays[idx].keyboards + 1] = addr
      end
    end
  end

  do
    local okL, logMod = pcall(require, "kernel.log")
    if okL and logMod and logMod.info then
      logMod.info("screen", string.format(
        "Seat init: %d displays paired from %d GPUs and %d screens (local-only)",
        #live, #gpus, #screenAddrs))
      if #gpus < #screenAddrs then
        logMod.warn("screen", string.format(
          "Detected %d screens but only %d GPUs — %d screen(s) will sit unused. " ..
          "Add a GPU card per additional seat.",
          #screenAddrs, #gpus, #screenAddrs - #gpus))
      elseif #screenAddrs < #gpus then
        logMod.warn("screen", string.format(
          "Detected %d GPUs but only %d screens — %d GPU(s) idle.",
          #gpus, #screenAddrs, #gpus - #screenAddrs))
      end

      if #scrRemotes > 0 or #gpuRemotes > 0 then
        logMod.warn("screen", string.format(
          "Component network is SHARED: %d remote screen(s) and %d remote GPU(s) " ..
          "belong to another computer cabled to this one.",
          #scrRemotes, #gpuRemotes))
        logMod.warn("screen",
          "TOS uses only its own local hardware, but the other machine's OS " ..
          "may bind to THIS screen — OC has no ownership lock. Symptom: two " ..
          "systems drawing over each other. Fix: unplug the link, or give " ..
          "each machine its own screen and keyboard.")
      end
    end
  end

  if not displays[activeIdx] then activeIdx = live[1] or 1 end
  initialized = true
  return #live
end

local function ensureInit()
  if not initialized then screen.init() end
end

function screen.count()
  ensureInit()
  return #liveIndices()
end

function screen.indices()
  ensureInit()
  return liveIndices()
end

function screen.active()
  ensureInit()
  if not displays[activeIdx] then activeIdx = liveIndices()[1] or 1 end
  return displays[activeIdx]
end

function screen.get(idx)
  ensureInit()
  return displays[idx]
end

function screen.setActive(idx)
  ensureInit()
  if displays[idx] then
    activeIdx = idx
    return true
  end
  return false
end

function screen.rebuild()
  local oldScreens = {}
  for i, d in pairs(displays) do oldScreens[d.screen] = i end

  screen.init()

  local newScreens = {}
  for i, d in pairs(displays) do newScreens[d.screen] = i end

  local added, removed = {}, {}
  for scrAddr, idx in pairs(newScreens) do
    if not oldScreens[scrAddr] then added[#added + 1] = idx end
  end
  for scrAddr, idx in pairs(oldScreens) do
    if not newScreens[scrAddr] then removed[#removed + 1] = idx end
  end
  return added, removed
end

function screen.next()
  ensureInit()
  local live = liveIndices()
  if #live == 0 then return nil end
  local pos = 1
  for i, idx in ipairs(live) do
    if idx == activeIdx then pos = i; break end
  end
  activeIdx = live[(pos % #live) + 1]
  return displays[activeIdx]
end

function screen.gpu()
  local d = screen.active()
  return d and d.gpu
end

function screen.getResolution()
  local d = screen.active()
  if d then return d.w, d.h end
  return 50, 16
end

--! The screen changed size without TOS asking it to.
--!
--! d.w/d.h were only ever written in two places: screen.init(), and
--! screen.fitDisplay when TOS itself sets a resolution. Both are cases where
--! TOS is the one doing the resizing. OpenComputers resizes the glass on its
--! own as well -- add or break a screen block in-world and the GPU resolution
--! is clamped to the new maximum -- and it announces that with a
--! `screen_resized` signal that nothing in TOS was listening for.
--!
--! Everything downstream then describes a screen that no longer exists. The
--! seat proxy's syncSize compares against d.w/d.h, so with both stale it sees
--! no change and keeps a shadow indexed for the old width, happily eliding
--! repaints of cells that are not where it thinks. The panels layout derives
--! STAT_ROW from S.H, so on a screen that SHRANK the status bar is drawn at a
--! row past the bottom, where the GPU clips it -- another way for the status
--! bar to vanish, and this one takes the prompt row with it.
--!
--! OpenOS treats this as load-bearing: lib/tty.lua listens for the signal AND
--! intercepts gpu.setResolution, with the comment "the gpu can change
--! resolution before we get a chance to call events and handle
--! screen_resized".
--!
--! Kept as a plain function rather than a listener registered here, because
--! this module deliberately requires only component and computer -- the
--! kernel wires the signal to it at boot. Pass addr = nil to re-sync every
--! seat. (test_screen_resize.lua)
function screen.onResized(addr, w, h)
  ensureInit()
  local changed = false
  for _, d in ipairs(displays) do
    if addr == nil or d.screen == addr then

      local nw, nh = w, h
      if d.gpu then
        local okR, gw, gh = pcall(d.gpu.getResolution)
        if okR and gw and gh then nw, nh = gw, gh end
      end
      if type(nw) == "number" and type(nh) == "number"
         and nw > 0 and nh > 0 and (nw ~= d.w or nh ~= d.h) then
        d.w, d.h = nw, nh
        changed = true
      end
    end
  end
  if changed then

    screen.invalidateAll()
    local okD, disp = pcall(require, "kernel.display")
    if okD and disp and disp.refreshSize then pcall(disp.refreshSize) end
  end
  return changed
end

local RES_DEFAULTS = {
  colsPerBlock = 10, rowsPerBlock = 4,
  prefW = 80, prefH = 25,
}

local function clampN(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

function screen.specFromConfig(cfg)
  local spec = {
    mode = "auto",
    colsPerBlock = RES_DEFAULTS.colsPerBlock, rowsPerBlock = RES_DEFAULTS.rowsPerBlock,
    prefW = RES_DEFAULTS.prefW, prefH = RES_DEFAULTS.prefH,
  }
  if not (cfg and cfg.get) then return spec end
  local r = cfg.get("screenRes")
  if type(r) == "string" then
    local rl = r:lower()
    if rl == "max" then spec.mode = "max"
    elseif rl == "auto" then spec.mode = "auto"
    else
      local w, h = rl:match("^(%d+)%s*[x×]%s*(%d+)$")
      if w then spec.mode = "size"; spec.w = tonumber(w); spec.h = tonumber(h) end
    end
  end
  local cpb = tonumber(cfg.get("screenColsPerBlock")); if cpb and cpb > 0 then spec.colsPerBlock = cpb end
  local rpb = tonumber(cfg.get("screenRowsPerBlock")); if rpb and rpb > 0 then spec.rowsPerBlock = rpb end
  return spec
end

function screen.chooseResolution(spec, maxW, maxH, blocksW, blocksH)
  spec = spec or { mode = "auto" }
  maxW = (type(maxW) == "number" and maxW > 0) and maxW or 50
  maxH = (type(maxH) == "number" and maxH > 0) and maxH or 16
  local mode = spec.mode or "auto"

  if mode == "max" then
    return maxW, maxH, nil
  end

  if mode == "size" then
    local rw, rh = spec.w or maxW, spec.h or maxH
    local w, h = clampN(rw, 1, maxW), clampN(rh, 1, maxH)
    local note
    if rw > maxW or rh > maxH then
      note = string.format("requested %dx%d exceeds max %dx%d (using %dx%d)",
        rw, rh, maxW, maxH, w, h)
    end
    return w, h, note
  end

  local floorW = math.min(spec.prefW or RES_DEFAULTS.prefW, maxW)
  local floorH = math.min(spec.prefH or RES_DEFAULTS.prefH, maxH)
  local tw, th
  if blocksW and blocksH and blocksW > 0 and blocksH > 0 then
    tw = math.floor(blocksW * (spec.colsPerBlock or RES_DEFAULTS.colsPerBlock) + 0.5)
    th = math.floor(blocksH * (spec.rowsPerBlock or RES_DEFAULTS.rowsPerBlock) + 0.5)
  else
    tw = spec.prefW or RES_DEFAULTS.prefW
    th = spec.prefH or RES_DEFAULTS.prefH
  end
  return clampN(tw, floorW, maxW), clampN(th, floorH, maxH), nil
end

function screen.gpuTarget(gpu, scrAddr, spec)
  if not gpu then return 50, 16, "no gpu" end
  local maxW, maxH = 50, 16
  local okM, mw, mh = pcall(gpu.maxResolution)
  if okM and mw and mh then maxW, maxH = mw, mh end
  if not scrAddr and gpu.getScreen then
    local okS, s = pcall(gpu.getScreen)
    if okS and type(s) == "string" then scrAddr = s end
  end
  local bw, bh
  if scrAddr then
    local okA, aw, ah = pcall(component.invoke, scrAddr, "getAspectRatio")
    if okA and type(aw) == "number" and type(ah) == "number" then bw, bh = aw, ah end
  end
  return screen.chooseResolution(spec, maxW, maxH, bw, bh)
end

function screen.applyResolution(gpu, w, h)
  if not gpu then return false end
  local ok = (pcall(gpu.setResolution, w, h)) == true
  if ok then
    local okD, disp = pcall(require, "kernel.display")
    if okD and disp and disp.refreshSize then pcall(disp.refreshSize) end
  end
  return ok
end

function screen.setPolicy(spec) policySpec = spec end
function screen.getPolicy() return policySpec end

function screen.setBuffer(mode)
  if mode ~= "auto" and mode ~= "on" and mode ~= "off" then
    return false, "mode must be auto, on, or off"
  end
  bufferMode = mode
  bufferGen  = bufferGen + 1
  return true
end

function screen.invalidateAll()
  bufferGen = bufferGen + 1
end

function screen.bufferMode() return bufferMode end

function screen.bufferStats()
  local total = _drawSkipped + _drawEmitted
  return {
    skipped = _drawSkipped,
    emitted = _drawEmitted,
    total   = total,
    ratio   = total > 0 and (_drawSkipped / total) or 0,
  }
end
function screen.resetBufferStats() _drawSkipped, _drawEmitted = 0, 0 end

function screen._shadowWanted(mode, freeMem, baseNeed, reserve)
  if mode == "off" then return false end
  if mode == "on" then return (freeMem or 0) > (baseNeed or 0) end
  return (freeMem or 0) > (baseNeed or 0) + (reserve or 0)
end

function screen.fitDisplay(idx, spec)
  ensureInit()
  local d = displays[idx] or screen.active()
  if not d or not d.gpu then return nil, nil, "no display" end
  spec = spec or policySpec or { mode = "auto" }
  local w, h, note = screen.gpuTarget(d.gpu, d.screen, spec)
  if screen.applyResolution(d.gpu, w, h) then
    d.w, d.h = w, h
  end
  return w, h, note
end

function screen.fit(spec)
  return screen.fitDisplay(activeIdx, spec)
end

function screen.restore(idx)
  return screen.fitDisplay(idx or activeIdx, policySpec or { mode = "auto" })
end

function screen.list()
  ensureInit()
  local result = {}
  for _, i in ipairs(liveIndices()) do
    local d = displays[i]
    result[#result + 1] = {
      index  = i,
      label  = d.label,
      w      = d.w,
      h      = d.h,
      depth  = d.depth,
      screen = d.screen,
      active = (i == activeIdx),
    }
  end
  return result
end

function screen.setLabel(idx, label)
  if displays[idx] then
    displays[idx].label = label
    return true
  end
  return false
end

function screen.displayForKeyboard(kbAddr)
  ensureInit()
  return kbToDisplay[kbAddr]
end

function screen.displayForScreen(scrAddr)
  ensureInit()
  return screenToDisplay[scrAddr]
end

function screen.seatDevices(idx)
  ensureInit()
  local d = displays[idx]
  if not d then return nil end
  local gpuAddr
  if d.gpu then
    local ok, a = pcall(function() return d.gpu.address end)
    if ok and type(a) == "string" then gpuAddr = a end
  end
  return { gpu = gpuAddr, screen = d.screen, keyboards = d.keyboards or {} }
end

function screen.callerSeat()
  local okP, proc = pcall(require, "kernel.process")
  if not okP or type(proc) ~= "table" or not proc.current then return nil end
  local okC, p = pcall(proc.current)
  if not okC or type(p) ~= "table" then return nil end
  return p.display
end

function screen.callerDevices()
  local idx = screen.callerSeat()
  if not idx then return nil end
  return screen.seatDevices(idx)
end

function screen._spanMatches(shC, shF, shB, base, x, chars, fg, bg, W)
  for i = 1, #chars do
    local cx = x + i - 1
    if cx < 1 or cx > W then return false end
    local k = base + cx
    if shC[k] ~= chars[i] or shF[k] ~= fg or shB[k] ~= bg then return false end
  end
  return true
end

function screen._diffWindow(shC, shF, shB, base, x, chars, fg, bg, W)
  local n = #chars
  local first, last
  for i = 1, n do
    local cx = x + i - 1
    if cx < 1 or cx > W then return 1, n end
    local k = base + cx
    if shC[k] ~= chars[i] or shF[k] ~= fg or shB[k] ~= bg then
      first = first or i
      last = i
    end
  end
  return first, last
end

function screen._fillWindow(shC, shF, shB, x1, y1, x2, y2, ch, fg, bg, W)
  local fx1, fy1, fx2, fy2
  for yy = y1, y2 do
    local b = (yy - 1) * W
    for xx = x1, x2 do
      local k = b + xx
      if shC[k] ~= ch or shF[k] ~= fg or shB[k] ~= bg then
        if not fx1 then fx1, fy1, fx2, fy2 = xx, yy, xx, yy
        else
          if xx < fx1 then fx1 = xx end
          if xx > fx2 then fx2 = xx end
          fy2 = yy
        end
      end
    end
  end
  return fx1, fy1, fx2, fy2
end

function screen.displayProxy(idx)
  ensureInit()
  local d = displays[idx]
  if not d then return nil end

  local proxy = {}

  local lastFg, lastBg = nil, nil

  local W2, H2 = d.w, d.h
  local shC, shF, shB = {}, {}, {}
  local UTF8 = "[\0-\127\194-\255][\128-\191]*"

  local function invalidateShadow()
    shC, shF, shB = {}, {}, {}
    lastFg, lastBg = nil, nil
  end

  d._writerGen = d._writerGen or 0
  local myWriterGen = d._writerGen

  local frameDepth = 0
  local pageStale  = true
  local function claimGlass()

    if frameDepth == 0 then pageStale = true end
    if d._lastWriter ~= proxy then
      d._lastWriter = proxy
      d._writerGen  = d._writerGen + 1
    end
    if myWriterGen ~= d._writerGen then
      myWriterGen = d._writerGen
      invalidateShadow()
    end
  end

  local function disownGlass()
    d._lastWriter = nil
    d._writerGen  = d._writerGen + 1
    myWriterGen   = d._writerGen
    invalidateShadow()

    pageStale = true
  end

  local releaseBackbuffer = function() end
  local function syncSize()
    if d.w ~= W2 or d.h ~= H2 then
      W2, H2 = d.w, d.h
      invalidateShadow()
      releaseBackbuffer()
    end
  end

  local SHADOW_RESERVE = 384 * 1024
  local baseNeed = d.w * d.h * 128

  local freeMem
  do
    local okH, hal = pcall(require, "kernel.hal")
    if okH and hal and hal.freeMemory then
      freeMem = hal.freeMemory(baseNeed + SHADOW_RESERVE)
    else
      freeMem = (computer.freeMemory and computer.freeMemory()) or 0
    end
  end

  local myBufferGen = bufferGen
  local function shadowEnabled()
    if bufferGen ~= myBufferGen then myBufferGen = bufferGen; invalidateShadow() end
    return screen._shadowWanted(bufferMode, freeMem, baseNeed, SHADOW_RESERVE)
  end

  local backIdx     = nil
  local backBroken  = false

  --!
  --! The shadow describes THE SCREEN. Inside a frame, draws land on the
  --! PAGE. Those are the same surface only for as long as nothing has been
  --! drawn since the last blit — and in TOS most drawing happens OUTSIDE a
  --! frame, because drawMod.all is the only thing that opens one. Every
  --! applyDraw level 1 and 2, the once-a-second status-bar tick, the
  --! file-list fast path and every dialog paint straight to the glass.
  --!
  --! When those two disagree, the elision inverts: the frame's redraw skips
  --! every cell whose SCREEN content already matches, so those cells are
  --! never written to the page — and then endFrame blits the page over the
  --! glass and they revert to whatever the page was carrying. On a page
  --! that was just allocated, "whatever it was carrying" is black.
  --!
  --! That is BOTH of the bugs the operator reported, from one cause: the
  --! status bar (repainted on a timer, outside any frame, so it is always
  --! "already correct" when the frame opens) turns background-black and
  --! never heals, because the shadow goes on insisting it is painted; and
  --! the command-line cursor duplicates, because the page still holds the
  --! inverse-video block from where the cursor USED to be while the live
  --! one is drawn where it is now.
  --! (test_screen_frame.lua)
  local function backbufferSupported()
    local g = d.gpu
    return not backBroken and g and g.allocateBuffer and g.setActiveBuffer
       and g.bitblt and g.freeBuffer
  end
  releaseBackbuffer = function()
    if backIdx then
      pcall(d.gpu.setActiveBuffer, 0)
      pcall(d.gpu.freeBuffer, backIdx)
      backIdx = nil
    end
    frameDepth = 0
    pageStale  = true
  end

  local function setFgCached(fg)
    if fg ~= lastFg then
      local ok = pcall(d.gpu.setForeground, fg)
      if ok then lastFg = fg else lastFg, lastBg = nil, nil end
    end
  end
  local function setBgCached(bg)
    if bg ~= lastBg then
      local ok = pcall(d.gpu.setBackground, bg)
      if ok then lastBg = bg else lastFg, lastBg = nil, nil end
    end
  end

  --! Every mechanism protecting the shadow -- the writer generation, the
  --! disownGlass declarations, pageStale -- works only when the thing that
  --! moved the glass ANNOUNCES ITSELF. That covers the writers TOS knows
  --! about. It cannot cover a GPU that drops a call, an emulator quirk, a
  --! blit that reports success and copies nothing, or a code path nobody
  --! has found yet. And when the shadow is wrong, the elision makes it
  --! PERMANENT: the row it believes is painted is never repainted, so the
  --! fault outlives every redraw and cannot heal.
  --!
  --! Measured on the operator's machine, five rounds in: the status row
  --! black on the glass while the shadow -- and the off-screen page --
  --! both held the correct 336699. Each round found a real declaration
  --! bug, fixed it, and the bar went black again for a different reason.
  --! Chasing writers one at a time is losing to a mechanism that turns any
  --! single missed declaration into a permanent wrong row.
  --!
  --! So stop trying to enumerate the writers. Before skipping a draw --
  --! at most once a second, and only when something is actually being
  --! elided -- read ONE cell back and find out whether the screen really
  --! holds what we are about to not draw. If it does not, the shadow is
  --! lying: drop it and let the draw through. The bar repairs itself
  --! within a second of going wrong, whatever caused it.
  --!
  --! Cost: one gpu.get per second, and only while eliding. A full redraw
  --! makes 40-80 calls, so this is under a percent of what the shadow
  --! saves. NEVER inside a frame -- gpu.get would read the PAGE, not the
  --! glass, and the two are legitimately different there.
  --! (test_shadow_audit.lua)
  --! TWO caches sit over this glass and EITHER can lie. shC/shF/shB say
  --! "that cell already reads like this"; lastFg/lastBg say "the GPU is
  --! already set to that colour". The captured machine had both wrong at
  --! once -- the shadow holding 336699 for a row the screen showed black,
  --! and the colour cache holding 336699 while the hardware was on black,
  --! which is what made the repaints land in the wrong colour AND get
  --! filed as correct. So the check is of a CELL, against the glass, and
  --! the repair drops both caches together.
  --!
  --! Checked on any draw rather than only on an elided one. The status bar
  --! rarely elides outright -- the clock digits differ every second -- so
  --! hooking the elision path would almost never look at the one row that
  --! actually goes wrong.
  local lastAudit  = 0
  local auditHits  = 0
  local AUDIT_GAP  = 1
  local function auditCell(x, y)
    if frameDepth > 0 then return false end
    if not (d.gpu and d.gpu.get) then return false end
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    if x < 1 or x > W2 or y < 1 or y > H2 then return false end

    local k = (y - 1) * W2 + x
    local ch, bg = shC[k], shB[k]
    if ch == nil or bg == nil then return false end
    local now = (computer.uptime and computer.uptime()) or 0
    if now - lastAudit < AUDIT_GAP then return false end
    lastAudit = now
    local okG, gch, _, gbg = pcall(d.gpu.get, x, y)
    if not okG then return false end
    if gch == ch and gbg == bg then return false end

    invalidateShadow()
    auditHits = auditHits + 1

    if auditHits == 1 then
      local okL, logMod = pcall(require, "kernel.log")
      if okL and logMod and logMod.warn then
        pcall(logMod.warn, "screen", string.format(
          "Display cache was wrong at col %d row %d (screen=%s, cache=%s) — "
          .. "dropped it and repainted. Something moved the glass without "
          .. "declaring it.", x, y,
          gbg and string.format("%06X", gbg) or "?",
          bg and string.format("%06X", bg) or "?"))
      end
    end
    return true
  end

  function proxy.auditHits() return auditHits end

  local dumpProc = nil
  local function coopYieldScreen()
    if dumpProc == nil then
      local okP, m = pcall(require, "kernel.process")
      dumpProc = (okP and m and m.yieldCooperative) and m or false
    end
    if dumpProc then dumpProc.yieldCooperative() end
  end

  function proxy.set(x, y, text, fg, bg)
    if type(x) ~= "number" or type(y) ~= "number" or type(text) ~= "string" then return end
    syncSize(); claimGlass()

    if not shadowEnabled() or y < 1 or y > H2 then
      if fg then setFgCached(fg) end
      if bg then setBgCached(bg) end
      local ok = pcall(d.gpu.set, x, y, text)
      if not ok then lastFg, lastBg = nil, nil end
      _drawEmitted = _drawEmitted + 1
      return
    end
    auditCell(x, y)
    local efg, ebg = fg or lastFg, bg or lastBg
    local chars = {}
    for ch in text:gmatch(UTF8) do chars[#chars + 1] = ch end
    local base = (y - 1) * W2
    local first, last = screen._diffWindow(shC, shF, shB, base, x, chars, efg, ebg, W2)
    if not first then
      _drawSkipped = _drawSkipped + 1
      return
    end
    if fg then setFgCached(fg) end
    if bg then setBgCached(bg) end

    local sub = (first == 1 and last == #chars) and text
      or table.concat(chars, "", first, last)
    local ok = pcall(d.gpu.set, x + first - 1, y, sub)
    if not ok then lastFg, lastBg = nil, nil; invalidateShadow(); return end
    _drawEmitted = _drawEmitted + 1
    for i = first, last do
      local cx = x + i - 1
      if cx >= 1 and cx <= W2 then
        local k = base + cx
        shC[k] = chars[i]; shF[k] = efg; shB[k] = ebg
      end
    end
  end
  function proxy.fill(x, y, w, h, ch, fg, bg)
    if type(x) ~= "number" or type(y) ~= "number"
       or type(w) ~= "number" or type(h) ~= "number" then return end
    syncSize(); claimGlass()
    ch = ch or " "
    if not shadowEnabled() then
      if fg then setFgCached(fg) end
      if bg then setBgCached(bg) end
      local ok = pcall(d.gpu.fill, x, y, w, h, ch)
      if not ok then lastFg, lastBg = nil, nil end
      _drawEmitted = _drawEmitted + 1
      return
    end
    auditCell(math.max(1, x), math.max(1, y))
    local efg, ebg = fg or lastFg, bg or lastBg
    local x1, y1 = math.max(1, x), math.max(1, y)
    local x2, y2 = math.min(W2, x + w - 1), math.min(H2, y + h - 1)
    if x1 > x2 or y1 > y2 then

      if fg then setFgCached(fg) end
      if bg then setBgCached(bg) end
      local okOff = pcall(d.gpu.fill, x, y, w, h, ch)
      if not okOff then lastFg, lastBg = nil, nil end
      _drawEmitted = _drawEmitted + 1
      return
    end

    local fx1, fy1, fx2, fy2 =
      screen._fillWindow(shC, shF, shB, x1, y1, x2, y2, ch, efg, ebg, W2)
    if not fx1 then
      _drawSkipped = _drawSkipped + 1; return
    end
    if fg then setFgCached(fg) end
    if bg then setBgCached(bg) end
    local ok = pcall(d.gpu.fill, fx1, fy1, fx2 - fx1 + 1, fy2 - fy1 + 1, ch)
    if not ok then lastFg, lastBg = nil, nil; invalidateShadow(); return end
    _drawEmitted = _drawEmitted + 1

    for yy = fy1, fy2 do
      local b = (yy - 1) * W2
      for xx = fx1, fx2 do
        local k = b + xx
        shC[k] = ch; shF[k] = efg; shB[k] = ebg
      end
    end
  end
  function proxy.clear(bg)
    syncSize(); claimGlass()
    if bg then setBgCached(bg) end
    local ok = pcall(d.gpu.fill, 1, 1, W2, H2, " ")
    if not ok then lastFg, lastBg = nil, nil; invalidateShadow(); return end
    if shadowEnabled() then
      local efg, ebg = lastFg, bg or lastBg
      for k = 1, W2 * H2 do shC[k] = " "; shF[k] = efg; shB[k] = ebg end
    end
  end
  function proxy.getSize() return d.w, d.h end

  function proxy.beginFrame()
    if not backbufferSupported() then return false end
    syncSize()
    frameDepth = frameDepth + 1
    if frameDepth > 1 then return true end
    if not backIdx then
      local okA, idx = pcall(d.gpu.allocateBuffer, W2, H2)
      if not okA or type(idx) ~= "number" or idx <= 0 then

        backBroken = true; frameDepth = 0; return false
      end
      backIdx = idx
    end
    local okS = pcall(d.gpu.setActiveBuffer, backIdx)
    if not okS then
      releaseBackbuffer(); backBroken = true; return false
    end

    if pageStale then
      if pcall(d.gpu.bitblt, backIdx, 1, 1, W2, H2, 0, 1, 1) then
        pageStale = false
      else
        invalidateShadow()
      end
    end
    return true
  end

  function proxy.endFrame()
    if frameDepth == 0 then return false end
    frameDepth = frameDepth - 1
    if frameDepth > 0 then return true end
    local blitted = false
    if backIdx then
      blitted = pcall(d.gpu.bitblt, 0, 1, 1, W2, H2, backIdx, 1, 1)
    end

    local okR = pcall(d.gpu.setActiveBuffer, 0)
    if not okR then releaseBackbuffer(); backBroken = true end
    if not blitted then

      lastFg, lastBg = nil, nil
      invalidateShadow()
      pageStale = true
      return false
    end

    pageStale = false
    return true
  end

  function proxy.hasBackbuffer() return backIdx ~= nil end

  function proxy.getGpu() disownGlass(); releaseBackbuffer(); return d.gpu end

  function proxy.invalidate() invalidateShadow() end
  function proxy.getGpuTier()
    local dp = d.depth or 1
    if dp >= 8 then return 3
    elseif dp >= 4 then return 2
    else return 1 end
  end
  function proxy.getGpuDepth() return d.depth or 1 end

  --! A capture of what is ON THE GLASS, for bug reports.
  --!
  --! It used to read the SHADOW whenever the shadow was enabled, which is to
  --! say: the tool whose entire purpose is diagnosing display bugs reported
  --! the display cache's own opinion of the screen. For the one class of bug
  --! TOS keeps having -- the shadow and the glass disagreeing -- that is
  --! precisely the wrong witness. A stale row would dump as perfect.
  --!
  --! It also captured characters only, so a fault that changes COLOUR and not
  --! text -- "the status bar went black" is exactly that -- left no trace in
  --! the dump at all.
  --!
  --! So: gpu.get is the ground truth and is used whenever it exists, colours
  --! come back with the text, and the shadow is a labelled fallback rather
  --! than the default. The `source` field says which one answered, because a
  --! capture that cannot say where it came from is the same trap again.
  --!
  --! COST: one component call per cell, ~2000 on an 80x25 screen, which will
  --! spend the per-tick call budget and make OpenComputers sleep. That is
  --! acceptable for a deliberate, rare diagnostic -- but not while holding the
  --! machine, so it yields between rows the way everything else long does.
  --! (test_screendump_truth.lua)
  function proxy.dump()
    syncSize()

    local sC, sF, sB = shC, shF, shB
    local st = {
      lastFg     = lastFg,     lastBg     = lastBg,
      frameDepth = frameDepth, pageStale  = pageStale,
      backbuffer = backIdx ~= nil,         backBroken = backBroken and true or false,
      writerGen  = d._writerGen,           myWriterGen = myWriterGen,
      lastWriterIsMe = (d._lastWriter == proxy),
      w = W2, h = H2,
    }
    st.shadow = shadowEnabled()

    local canGet = false
    if d.gpu and d.gpu.get then
      local okProbe = pcall(d.gpu.get, 1, 1)
      canGet = okProbe and true or false
    end
    local useShadow = (not canGet) and st.shadow

    local function pushRun(runs, x, c)
      local last = runs[#runs]
      if last and last.c == c then last.to = x
      else runs[#runs + 1] = { from = x, to = x, c = c } end
    end

    local lines, bgRuns, fgRuns = {}, {}, {}
    for y = 1, H2 do
      coopYieldScreen()
      local row, base = {}, (y - 1) * W2
      local brun, frun = {}, {}
      for x = 1, W2 do
        local chr, fg, bg
        if canGet then
          local ok, c, f, b = pcall(d.gpu.get, x, y)
          if ok then chr, fg, bg = c, f, b end
        elseif useShadow then
          chr, fg, bg = sC[base + x], sF[base + x], sB[base + x]
        end
        row[x] = (chr == nil or chr == "") and " " or chr

        pushRun(brun, x, bg)
        pushRun(frun, x, fg)
      end
      lines[y] = (table.concat(row):gsub("%s+$", ""))
      bgRuns[y], fgRuns[y] = brun, frun
    end

    local shadowBg = nil
    if st.shadow and next(sB) ~= nil then
      shadowBg = {}
      for y = 1, H2 do
        local base, runs = (y - 1) * W2, {}
        for x = 1, W2 do pushRun(runs, x, sB[base + x]) end
        shadowBg[y] = runs
      end
    end

    local function firstMismatch(gRuns, sRuns)
      if not (gRuns and sRuns) then return nil end
      local gi, si = 1, 1
      for x = 1, W2 do
        while gRuns[gi] and gRuns[gi].to < x do gi = gi + 1 end
        while sRuns[si] and sRuns[si].to < x do si = si + 1 end
        local gc = gRuns[gi] and gRuns[gi].c
        local sc = sRuns[si] and sRuns[si].c
        if sc ~= nil and gc ~= sc then return x, gc, sc end
      end
      return nil
    end
    local disagree = nil
    if shadowBg and canGet then
      for y = 1, H2 do
        local x, gc, sc = firstMismatch(bgRuns[y], shadowBg[y])
        if x then
          disagree = disagree or {}
          disagree[#disagree + 1] = { row = y, col = x, glass = gc, shadow = sc }
        end
      end
    end

    local pageBg = nil
    if disagree and backIdx and canGet then
      if pcall(d.gpu.setActiveBuffer, backIdx) then
        pageBg = {}
        for i = 1, math.min(#disagree, 8) do
          local y = disagree[i].row
          local runs = {}
          for x = 1, W2 do
            local okG, _, _, b = pcall(d.gpu.get, x, y)
            pushRun(runs, x, okG and b or nil)
          end
          pageBg[y] = runs
        end

        if not pcall(d.gpu.setActiveBuffer, 0) then
          releaseBackbuffer(); backBroken = true
        end
      end
    end

    return { lines = lines, w = W2, h = H2,
             source = canGet and "glass" or (useShadow and "shadow" or "empty"),
             bg = bgRuns, fg = fgRuns,
             shadowBg = shadowBg, disagree = disagree, pageBg = pageBg,
             state = st }
  end

  proxy.getTheme = function()
    local ok, disp = pcall(require, "kernel.display")
    if ok and disp and disp.getTheme then return disp.getTheme() end
    return setmetatable({}, { __index = function() return 0xFFFFFF end })
  end
  proxy.c = function(name)
    local theme = proxy.getTheme()
    return theme[name] or 0xFFFFFF
  end

  local ok, disp = pcall(require, "kernel.display")
  if ok and disp and disp.withContext then
    local FORWARDED = {
      "scrollUp", "box", "dbox", "hdivider", "menuBar", "statusBar",
      "fkeyBar", "fit", "writeWrapped", "dialog", "menuBarEx", "dropdown",
      "isMonochrome", "setTheme",
    }
    for _, name in ipairs(FORWARDED) do
      if disp[name] then
        proxy[name] = function(...)
          local args = table.pack(...)
          local r = disp.withContext(d.gpu, d.w, d.h, function()
            return disp[name](table.unpack(args, 1, args.n))
          end)

          lastFg, lastBg = nil, nil
          disownGlass()
          return r
        end
      end
    end
    proxy.contextMenu = proxy.dropdown
    proxy.BOX = disp.BOX
    proxy.THEME = disp.THEME
  end

  return proxy
end

return screen
