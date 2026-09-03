-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Multi-Screen Manager   ║
-- ║  GPU ↔ Screen binding & switching    ║
-- ╚══════════════════════════════════════╝
-- OC allows multiple GPU+Screen pairs. This module manages bindings
-- and provides switching between displays.

local component = require("component")
local computer = require("computer")

local screen = {}

-- Active displays: SPARSE table keyed by STABLE seat index →
-- { gpu=proxy, screen=addr, w=num, h=num, depth=num, label=str, keyboards={addr,...} }
--
-- #FIX (stable seat indices, round-4 seat-binding bug) — indices used to be
-- positional (displays[#displays+1] on every init), so screen.rebuild() after
-- a hot-unplug RENUMBERED the survivors: remove screen 1 of 2 and the
-- surviving seat silently shifted 2→1 while every per-seat table keyed by the
-- old index (kernel sessionTokens/shellPIDs/monitorPIDs, process `display`
-- fields, displayForeground routing) still said 2 — the survivor's input then
-- routed to a dead seat's foreground and the seat froze ("logging out the alt
-- seat froze the survivor", round 1). A seat index is now STABLE for the
-- lifetime of the boot: a screen keeps its index across rebuilds, removed
-- seats leave holes, and a new screen takes the lowest FREE index.
local displays = {}
-- Stable screen-address → seat-index memory. Never cleared: it must survive
-- screen.init() re-runs (that's the whole point).
local seatIndexByScreen = {}
local activeIdx = 1  -- Currently focused display index
local initialized = false
-- Active resolution policy (set at boot from config; reused by restore()).
-- Declared here so screen.init() captures it as an upvalue.
local policySpec = nil
-- Reverse map: keyboard address → display index
local kbToDisplay = {}
-- Reverse map: screen address → display index
local screenToDisplay = {}

-- #PERF — operator override for the dirty-cell shadow buffer (see the gate in
-- displayProxy). "auto" = memory-gated (default), "off" = always direct draws,
-- "on" = enable whenever the shadow merely fits (skip the working-reserve
-- headroom). Bumping bufferGen on a change makes live proxies re-sync — and
-- invalidate their now-stale shadow — on the very next draw, so a toggle takes
-- effect immediately AND safely (no stale-cell artifacts on re-enable).
local bufferMode = "auto"
local bufferGen  = 0
-- #PERF — session counters for the dirty-cell buffer's payoff: cell-draw calls
-- the shadow ELIDED (never reached the GPU) vs those that hit it. `optimize`
-- surfaces the ratio so an operator can SEE the buffer working. Two int bumps
-- per draw — negligible next to the GPU bridge crossing they measure.
local _drawSkipped, _drawEmitted = 0, 0

-- Sorted list of the LIVE seat indices (displays is sparse — see the stable-
-- index note above; `#displays`/ipairs would stop at the first hole).
local function liveIndices()
  local idxs = {}
  for i in pairs(displays) do idxs[#idxs + 1] = i end
  table.sort(idxs)
  return idxs
end

--- Discover which keyboards belong to a screen.
-- In OC, keyboards are sub-components of screens. We check via
-- component.invoke(screen, "getKeyboards") if available, or fall
-- back to scanning all keyboard addresses.
local function findKeyboards(scrAddr)
  local kbs = {}
  -- Method 1: screen proxy has getKeyboards()
  local okList, kbList = pcall(component.invoke, scrAddr, "getKeyboards")
  if okList and type(kbList) == "table" then
    for _, kb in ipairs(kbList) do kbs[#kbs + 1] = kb end
    return kbs
  end
  -- Method 2: iterate keyboards and match by attached screen.
  -- In OC 1.7+, keyboards list their attached screen via the event
  -- address. As a fallback, just collect all keyboards — the first
  -- display gets them all (single-screen default).
  return kbs
end

-- #BUG-2 — OC's cable / adapter system makes every component on the
-- other side of a cable visible via `component.list()`. If TWO TOS
-- machines boot at the same time over a shared cable, both call
-- `gpu.bind(<first-screen-addr>)` in screen.init() — and the last
-- bind wins, so both machines fight over the same physical screens
-- and visibly "mirror" each other.
--
-- The fix: only enumerate LOCAL components. OC distinguishes via
-- `component.slot(addr)`:
--   * slot >= 0  → physically slotted into this case (LOCAL)
--   * slot == -1 → indirectly reachable via cable / adapter (REMOTE)
-- We prefer locals; if no locals exist (rare — a headless server
-- driving a remote screen rack), we fall back to all visible.
local function isLocalComponent(addr)
  if not addr then return false end
  local okS, slot = pcall(component.slot, addr)
  if not okS then return true end  -- can't tell → assume local (safe default)
  return slot ~= nil and slot >= 0
end

local function listLocalThenRemote(ctype)
  local locals, remotes = {}, {}
  for addr in component.list(ctype) do
    if isLocalComponent(addr) then locals[#locals + 1] = addr
    else remotes[#remotes + 1] = addr end
  end
  -- #REV — sort by address so GPU/screen pairing is DETERMINISTIC across
  -- boots. component.list() iteration order is not stable in OC, so the
  -- old code paired gpu[i] with screen[i] in whatever order they happened
  -- to enumerate — which meant the active screen could swap to a different
  -- physical panel on every reboot (the operator-reported "screens swap
  -- when rebooting" on a multi-screen rig). Sorting pins each seat to the
  -- same hardware run-to-run.
  table.sort(locals)
  table.sort(remotes)
  if #locals > 0 then return locals, remotes end
  return remotes, {}  -- headless / cable-only case
end

-- #FIX (seat↔screen binding) — PURE pairing decision, unit-tested.
-- gpuScreens[i] = the screen GPU i is CURRENTLY bound to, or `false` if none,
-- in sorted GPU order (dense — `false`, never nil, so a middle hole can't
-- truncate the array). screenAddrs = the available local screens (sorted).
-- Returns result[i] = the screen GPU i should drive.
--
-- We PREFER each GPU's current binding: at boot that's the panel the
-- BIOS/EEPROM drew the splash on (so the session stays there instead of
-- jumping to the sorted-first screen), and on hot-plug it keeps every live
-- seat on its own panel instead of yanking it onto the newly-attached screen.
-- GPUs with no valid/available current screen get the remaining screens in
-- sorted order (deterministic across boots).
function screen._pair(gpuScreens, screenAddrs)
  local avail = {}
  for _, a in ipairs(screenAddrs) do avail[a] = true end
  local claimed, result = {}, {}
  -- Pass 1 — keep current bindings where the screen is local + unclaimed.
  for i, cur in ipairs(gpuScreens) do
    if cur and avail[cur] and not claimed[cur] then
      claimed[cur] = true
      result[i] = cur
    end
  end
  -- Pass 2 — hand out the remaining screens (sorted) to still-unbound GPUs.
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

--- Scan for all GPU+Screen pairs and create display entries.
function screen.init()
  displays = {}
  kbToDisplay = {}
  screenToDisplay = {}

  -- #BUG-2 — prefer LOCAL components. Remotes (other machines reachable
  -- via cable) are skipped unless we have no locals at all.
  local gpuAddrs, gpuRemotes    = listLocalThenRemote("gpu")
  local screenAddrs, scrRemotes = listLocalThenRemote("screen")

  local gpus = {}
  for _, addr in ipairs(gpuAddrs) do
    gpus[#gpus + 1] = component.proxy(addr)
  end

  -- #FIX (seat↔screen binding) — pair each GPU to a screen PREFERRING the one
  -- it is already bound to (the boot/splash panel, and each live seat's panel
  -- on hot-plug), instead of the old gpu[i]↔sorted-screen[i] which yanked the
  -- session onto a different screen than the splash and jumped live seats when
  -- a screen was attached. See screen._pair.
  -- Dense array (false = "no current binding") so a GPU with no screen in the
  -- middle doesn't truncate the array via Lua's nil-hole length rule.
  local gpuScreens = {}
  for i, gpu in ipairs(gpus) do
    local okS, s = pcall(gpu.getScreen)
    gpuScreens[i] = (okS and type(s) == "string") and s or false
  end
  local pairing = screen._pair(gpuScreens, screenAddrs)

  -- Collect the (gpu, screen) pairs first, then assign STABLE seat indices:
  -- a screen that had an index in a previous init() keeps it; new screens
  -- take the lowest free index (in sorted-screen order, deterministic).
  local paired = {}
  for i = 1, #gpus do
    if pairing[i] then paired[#paired + 1] = { gpu = gpus[i], scr = pairing[i] } end
  end
  if #paired == 0 then
    -- Fallback: try to use the primary GPU/screen from boot
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
    -- Bind GPU to screen (no-op when it's already the current binding).
    pcall(gpu.bind, scrAddr)
    -- Apply the resolution policy for this seat (density-based auto by
    -- default). #REV-3 — go through applyResolution (NOT a raw
    -- setResolution): it refreshes kernel.display's cached W/H so nothing
    -- keeps drawing at a stale size (off-screen / invisible).
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
    -- Build reverse maps
    screenToDisplay[scrAddr] = idx
    for _, kb in ipairs(kbs) do
      kbToDisplay[kb] = idx
    end
  end

  -- Adopt any keyboard the system knows about that no display claimed
  -- via getKeyboards(). Two failure modes drove this:
  --
  --   1. OC version (or emulator) has no getKeyboards() at all — every
  --      screen returned {} and the old fallback dumped ALL keyboards
  --      onto display 1, so a 2-seat boot rendered both screens but
  --      only seat 1 ever received key_down events. The user perceived
  --      this as "screens switching" because typing on seat 2's
  --      keyboard drove seat 1's shell.
  --
  --   2. getKeyboards() works for some screens but not others (mixed
  --      hardware, partial emulator support). The old code's
  --      `if next(kbToDisplay) == nil` guard skipped the fallback
  --      whenever any screen succeeded, leaving the others input-dead.
  --
  -- Round-robin distribution by enumeration order is a best-effort:
  -- in practice OC enumerates keyboards in the same order as their
  -- attached screens, so kbs[i] usually lands on displays[i]. When
  -- it doesn't, at least every seat gets a working keyboard.
  -- #BUG-2 — only adopt LOCAL keyboards. Otherwise a cable-attached
  -- neighbour's keystrokes would land on our seats (the symmetric
  -- counterpart to the GPU bind issue).
  local live = liveIndices()
  if #live > 0 then
    local rr = 0
    local kbAddrs = listLocalThenRemote("keyboard")
    for _, addr in ipairs(kbAddrs) do
      if not kbToDisplay[addr] then
        rr = rr + 1
        -- Round-robin over the LIVE seat indices (sparse-safe).
        local idx = live[((rr - 1) % #live) + 1]
        kbToDisplay[addr] = idx
        displays[idx].keyboards = displays[idx].keyboards or {}
        displays[idx].keyboards[#displays[idx].keyboards + 1] = addr
      end
    end
  end

  -- #BUG-1 — diagnostic logging at init. When GPU count != screen
  -- count, the operator gets a clear note about WHY only some screens
  -- come up. (With 1 GPU + 2 screens, only one display can be active
  -- — OC GPUs drive one screen at a time. The other screen sits dark
  -- until the operator adds a second GPU.)
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

      -- Cabling two computer cases together MERGES their component
      -- networks: every screen, GPU and keyboard on either machine is
      -- then visible to both. #BUG-2 above already makes TOS prefer its
      -- own local hardware, so TOS does not go and grab a neighbour's
      -- panel — but nothing stops the neighbour's OS from grabbing OURS.
      -- OpenOS binds to whatever screen it enumerates first, and in
      -- vanilla OC there is no ownership lock to stop it, so both
      -- systems draw to the same display and neither is wrong.
      --
      -- We cannot prevent that. We CAN stop it being a mystery: an
      -- operator who cabled two boxes together and never touched their
      -- screens has no reason to suspect the screens are now shared.
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

  -- Snap the active display to a live seat (index 1 may be a hole after a
  -- hot-unplug rebuild — stable indices leave holes on purpose).
  if not displays[activeIdx] then activeIdx = live[1] or 1 end
  initialized = true
  return #live
end

-- Ensure init has been called
local function ensureInit()
  if not initialized then screen.init() end
end

--- Get the number of available displays.
function screen.count()
  ensureInit()
  return #liveIndices()
end

--- Sorted list of the live STABLE seat indices. Callers that iterate seats
--- must use this (not `for i = 1, count()`): indices are stable across
--- hot-plug rebuilds, so the sequence can have holes.
function screen.indices()
  ensureInit()
  return liveIndices()
end

--- Get the active display info.
function screen.active()
  ensureInit()
  if not displays[activeIdx] then activeIdx = liveIndices()[1] or 1 end
  return displays[activeIdx]
end

--- Get display by index.
function screen.get(idx)
  ensureInit()
  return displays[idx]
end

--- Switch active display.
function screen.setActive(idx)
  ensureInit()
  if displays[idx] then
    activeIdx = idx
    return true
  end
  return false
end

--- Rebuild display list (for hot-plug). Returns added, removed indices.
--- Indices are STABLE: a surviving screen keeps its index, so `removed`
--- names exactly the seats whose per-seat state (shell, session, monitor)
--- the kernel must tear down, and every other seat's state stays valid.
function screen.rebuild()
  local oldScreens = {}
  for i, d in pairs(displays) do oldScreens[d.screen] = i end

  screen.init()  -- re-enumerates everything (index-stable via seatIndexByScreen)

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

--- Cycle to next display (sparse-safe: cycles the live indices).
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

--- Get the GPU proxy for the active display.
function screen.gpu()
  local d = screen.active()
  return d and d.gpu
end

--- Get the resolution of the active display.
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
      -- Prefer the GPU's own answer over the signal's numbers: the signal
      -- reports the SCREEN's new size, and the resolution is a separate
      -- thing that OC may have clamped to something else entirely.
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
    -- Every proxy re-syncs on its next draw: syncSize sees d.w/d.h move and
    -- drops both the shadow and the now wrong-sized backbuffer, and the
    -- generation bump catches any proxy that does not draw for a while.
    screen.invalidateAll()
    local okD, disp = pcall(require, "kernel.display")
    if okD and disp and disp.refreshSize then pcall(disp.refreshSize) end
  end
  return changed
end

-- ============================================================
-- Resolution policy / dynamic screen sizing
-- ============================================================
-- TOS does not force the GPU to its max resolution any more. Max resolution
-- on a tier-3 GPU + large screen is 160x50, which renders the TUI in tiny
-- text. We can't scale glyphs, but we CAN lower the resolution: fewer cells
-- over the same physical blocks = bigger text. So a "screen size policy"
-- decides the working resolution:
--
--   max          — use the hardware maximum (old behavior; opt-in).
--   <W>x<H>       — an explicit resolution (clamped to max, warns if clamped).
--   auto (default)— density-based: target ~colsPerBlock × the screen's physical
--                   block size (from getAspectRatio) so text stays a readable
--                   size on any screen; falls back to an ~80x25 cap when the
--                   block size can't be read. Both clamped to max.
--
-- Programs declare a size the same way (manifest `screen={width=,height=}` or
-- the runtime API below); TOS fits the screen to it or warns if it can't.

local RES_DEFAULTS = {
  colsPerBlock = 10, rowsPerBlock = 4,  -- ~half of T3-max density => readable
  prefW = 80, prefH = 25,               -- baseline floor + no-block fallback
}

local function clampN(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

--- Build a resolution spec from the system config (safe with no config).
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

--- PURE: decide a resolution given a spec, the hardware max, and (optional)
--- the screen's physical block dimensions. Returns appliedW, appliedH, note.
--- `note` is a human-readable warning (e.g. a requested size didn't fit) or nil.
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

  -- auto: density-based, but NEVER below the ~80x25 baseline (clamped to
  -- the hardware max). The density rule exists to keep glyphs readable on
  -- LARGE multiblock walls — where the hardware max means tiny text — so
  -- it may only RAISE the resolution above the baseline, never lower it.
  --
  -- #REV-3 (critical) — the previous floor was a 40x12 minimum, which
  -- collapsed every screen up to 4 blocks wide (including the standard
  -- 1x1 and 3x2 builds) to 40x12 at boot: the login screen rendered at a
  -- fraction of the screen's real resolution, and anything that drew
  -- with a stale cached size painted off-screen — the machine looked
  -- bricked/headless after login.
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

--- Read a GPU's max resolution and its screen's physical block size, then
--- choose a resolution per `spec`. Returns appliedW, appliedH, note.
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

--- Apply a resolution to a GPU (pcall-guarded). Returns ok. Also refreshes the
--- single-seat display.lua cache so display.clear()/getSize() don't keep using
--- the old dimensions after a resize.
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

-- Operator control of the dirty-cell display buffer optimization.
-- mode = "auto" (memory-gated default) | "on" (force when it fits) | "off"
-- (always direct draws). Takes effect on the next draw across all seats.
function screen.setBuffer(mode)
  if mode ~= "auto" and mode ~= "on" and mode ~= "off" then
    return false, "mode must be auto, on, or off"
  end
  bufferMode = mode
  bufferGen  = bufferGen + 1   -- live proxies re-sync + invalidate on next draw
  return true
end
--- Tell every LIVE seat proxy that the glass changed behind it.
---
--- A proxy's dirty-cell shadow is only correct while every write goes
--- through that proxy. Anything drawing on the same GPU another way --
--- kernel.display directly, compat/term.lua, the login screen, a raw
--- getGpu() handout -- moves the glass without the shadow knowing, and
--- the proxy then ELIDES the next repaint of those cells because it
--- believes they already hold what is being asked for.
---
--- Measured on real hardware by the boot battery (70-screen-truth):
--- after a raw write, asking the proxy to repaint a row in the colour
--- it thought was already there left 0 of 80 columns correct. That is
--- the reported status bar staying black.
---
--- Proxies are created per call and not tracked, so this reuses the
--- generation counter they already consult on every draw: bump it and
--- each one invalidates itself the next time it is used. Cheap -- one
--- integer, no bookkeeping, and it cannot leak a reference to a proxy
--- whose seat has gone away.
function screen.invalidateAll()
  bufferGen = bufferGen + 1
end

function screen.bufferMode() return bufferMode end

-- Session stats for the dirty-cell buffer: how many cell-draw calls were elided
-- (never crossed to the GPU) vs emitted. ratio = elided / total. With the buffer
-- off (or RAM-gated off) nothing is elided, so ratio stays 0 — an honest "not
-- saving anything" signal. `optimize` shows this.
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

-- Pure decision for the shadow gate (unit-tested): should the buffer be active
-- given the operator `mode`, the free memory at proxy creation, the shadow's
-- own size (`baseNeed`), and the working-reserve headroom?
--   off  → never            on   → whenever it merely FITS (free > baseNeed)
--   auto → only with headroom (free > baseNeed + reserve) — the safe default
function screen._shadowWanted(mode, freeMem, baseNeed, reserve)
  if mode == "off" then return false end
  if mode == "on" then return (freeMem or 0) > (baseNeed or 0) end
  return (freeMem or 0) > (baseNeed or 0) + (reserve or 0)
end

--- Fit a specific display (seat) to a spec, applying the new resolution and
--- syncing the cached size. `idx` defaults to the active display; an unknown
--- idx falls back to the active one. Returns appliedW, appliedH, note. This is
--- the seat-aware primitive the shell uses (so resizing on seat 2 doesn't
--- resize seat 1).
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

--- Fit the ACTIVE display to a spec (or the boot policy if nil).
function screen.fit(spec)
  return screen.fitDisplay(activeIdx, spec)
end

--- Restore a display (default active) to the boot resolution policy, e.g. after
--- a program that requested a custom size exits.
function screen.restore(idx)
  return screen.fitDisplay(idx or activeIdx, policySpec or { mode = "auto" })
end

--- List all displays (sorted by stable seat index; sparse-safe).
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

--- Set label for a display.
function screen.setLabel(idx, label)
  if displays[idx] then
    displays[idx].label = label
    return true
  end
  return false
end

--- Look up which display index owns a keyboard address.
-- Returns the display index (1-based) or nil if unknown.
function screen.displayForKeyboard(kbAddr)
  ensureInit()
  return kbToDisplay[kbAddr]
end

--- Look up which display index owns a screen address.
function screen.displayForScreen(scrAddr)
  ensureInit()
  return screenToDisplay[scrAddr]
end

-- ============================================================
-- Seat ownership of display hardware
-- ============================================================
-- #FIX (emulator round 7) — a program that opens "the GPU" by hand
--   component.list("gpu")()
-- always gets the FIRST GPU on the bus, which is seat 1's. On a two-seat
-- machine that means a game launched from seat 2 renders on seat 1's
-- SCREEN, on top of whatever that operator was doing. The sandbox already
-- routes INPUT per seat (see sandbox.safePullSignal); these two helpers are
-- the output half of the same idea, and let the sandbox scope a program's
-- view of the display hardware to the seat it was launched from.
--
-- Both return nil when the seat can't be resolved (kernel context, boot,
-- off-box tests) — callers must fall back to their old behaviour then,
-- since a single-seat machine must keep working exactly as before.

--- The raw component ADDRESSES owned by one seat.
--- @return { gpu = addr|nil, screen = addr, keyboards = { addr, ... } } | nil
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

--- The seat index that owns the CALLING process, via its scheduler
--- principal. nil outside a process (kernel loop, boot, tests).
function screen.callerSeat()
  local okP, proc = pcall(require, "kernel.process")
  if not okP or type(proc) ~= "table" or not proc.current then return nil end
  local okC, p = pcall(proc.current)
  if not okC or type(p) ~= "table" then return nil end
  return p.display
end

--- Convenience: the seat devices of the calling process (nil if unknown).
function screen.callerDevices()
  local idx = screen.callerSeat()
  if not idx then return nil end
  return screen.seatDevices(idx)
end

-- #PERF — PURE: is the shadow span (cells base+x .. base+x+#chars-1) already
-- exactly (chars[i], fg, bg) for every i? If so the gpu.set is redundant and
-- can be skipped. An off-screen column counts as a mismatch so the real write
-- happens (gpu.set clips it). Shadow arrays are parallel char/fg/bg, 1-D
-- indexed as (y-1)*W + x. Unit-tested via test_screen_shadow.
function screen._spanMatches(shC, shF, shB, base, x, chars, fg, bg, W)
  for i = 1, #chars do
    local cx = x + i - 1
    if cx < 1 or cx > W then return false end
    local k = base + cx
    if shC[k] ~= chars[i] or shF[k] ~= fg or shB[k] ~= bg then return false end
  end
  return true
end

-- #PERF — PURE: the changed sub-window of a span. Returns (first, last)
-- indices into `chars`, or nil when every cell already matches (the
-- whole gpu.set is redundant). Perf-playbook item "batched runs within
-- a changed row": a status-bar clock tick used to resend the whole
-- 80-col row for a 5-char change; trimming the matching prefix/suffix
-- sends only the changed window across the OC bridge (still ONE
-- gpu.set — splitting interior runs would ADD calls, and calls are the
-- expensive part). Any off-screen cell returns the full span: gpu.set
-- clips it and the shadow can't track it, so no trimming games there.
-- Unit-tested via test_screen_shadow.
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

-- #PERF — PURE: the changed BOUNDING BOX of a fill rect. Returns
-- (fx1, fy1, fx2, fy2) in screen coords, or nil when every cell in the
-- rect already holds exactly (ch, fg, bg) — the whole gpu.fill is
-- redundant.
--
-- This is the fill analogue of _diffWindow. proxy.fill used to be
-- all-or-nothing: one differing cell re-filled the ENTIRE requested
-- rect, so a status-bar row whose last five columns changed re-painted
-- all 80. Shrinking to the changed bounding box keeps it ONE gpu.fill
-- (splitting into several would ADD calls, and calls are the expensive
-- part) while cutting the cells that call has to touch.
--
-- Deliberately a bounding box and not a set of runs: scattered changes
-- (two opposite corners) degrade to roughly the original rect, which is
-- exactly today's behaviour and never worse. Callers pass an ALREADY-
-- CLIPPED, non-empty rect (1 <= x1 <= x2 <= W, 1 <= y1 <= y2 <= H).
-- Unit-tested via test_screen_shadow.
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

--- Create a display proxy for index `idx`: a table that looks like
--- the kernel.display API but draws to a specific GPU/screen pair.
--- Core drawing methods (set/fill/clear) are implemented directly for
--- performance; higher-level TUI methods delegate to display.withContext.
function screen.displayProxy(idx)
  ensureInit()
  local d = displays[idx]
  if not d then return nil end

  local proxy = {}

  -- Per-proxy fg/bg cache. Mirrors the cache in kernel.display but
  -- scoped to this seat's GPU so two seats don't poison each other's
  -- cached state. Set/fill/clear all share the same lastFg/lastBg
  -- since they target the same GPU.
  local lastFg, lastBg = nil, nil
  -- #PERF — dirty-cell shadow buffer (see screen._spanMatches). A TUI redraws
  -- mostly-unchanged rows every frame; each gpu.set/fill (and its
  -- setForeground/Background) crosses the OC bridge. We remember what every
  -- cell currently holds and SKIP the GPU call when the target already matches
  -- exactly. Reset whenever the screen could change behind our back: a resize
  -- (syncSize), a forwarded withContext draw, a raw getGpu() handout, or a GPU
  -- error.
  local W2, H2 = d.w, d.h
  local shC, shF, shB = {}, {}, {}
  local UTF8 = "[\0-\127\194-\255][\128-\191]*"
  -- Both caches describe the same glass, so they have to die together.
  -- shC/shF/shB say "this cell already reads like that"; lastFg/lastBg say
  -- "the GPU is already set to that colour". Clearing only the first is
  -- WORSE than clearing neither: the shadow now says every cell needs
  -- repainting, so the fill IS emitted -- but the colour cache still
  -- claims a colour the outsider moved away from, setBgCached skips its
  -- call, and the whole repaint lands in the OUTSIDER's colour. The proxy
  -- then records the colour it meant to use, so glass and shadow disagree
  -- permanently and nothing ever corrects it.
  --
  -- Measured on hardware: after screen.invalidateAll() a full-row fill in
  -- blue put 0 of 80 cells blue. It painted black and filed it as blue.
  -- Visible as the menu bar wearing the status bar's colour after a
  -- repaint, and as a status bar that turns black on its own schedule.
  --
  -- This made every declaration of a foreign write actively harmful,
  -- which is the opposite of what invalidateAll is for.
  local function invalidateShadow()
    shC, shF, shB = {}, {}, {}
    lastFg, lastBg = nil, nil
  end

  -- Who touched this glass last?
  --
  -- screen.displayProxy builds a FRESH proxy on every call -- private
  -- shadow, private colour cache -- and the kernel calls it more than
  -- once per display: for the login process, for the shell, and again
  -- each time the task switcher opens. They all drive the same screen
  -- while each believes its shadow describes it.
  --
  -- None of the declaration machinery fires for this, because a proxy
  -- drawing normally is not a "foreign write" -- that was all built for
  -- raw gpu access. But it invalidates every OTHER proxy's shadow just
  -- as thoroughly, and those proxies go on eliding repaints of cells
  -- they believe are already correct.
  --
  -- So track the last writer per display. When it changes the newcomer
  -- bumps a generation, and any proxy that finds a generation it did not
  -- write drops its shadow. Two integer compares per draw; a proxy alone
  -- on its screen -- the normal case -- never pays anything at all.
  d._writerGen = d._writerGen or 0
  local myWriterGen = d._writerGen
  -- Backbuffer bookkeeping, declared HERE rather than beside the rest of it
  -- further down because claimGlass has to see them: a local declared below
  -- a closure is not an upvalue of it, it is a nil global read. The long
  -- explanation of what pageStale is for lives with the frame code.
  local frameDepth = 0        -- reentrancy: only the outermost pair blits
  local pageStale  = true     -- does the off-screen page still match the glass?
  local function claimGlass()
    -- A draw with no frame open lands on the GLASS, not on the page — so the
    -- page no longer describes what is on screen, and the next frame has to
    -- re-seed before its elisions can be trusted. This is the chokepoint for
    -- every write (set/fill/clear all call it), so a future drawing method
    -- cannot forget to say so.
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

  -- The glass is about to be written by something that is not a proxy at
  -- all (a raw getGpu handout, a forwarded display.* draw). Nobody owns
  -- it afterwards, so EVERY proxy re-syncs on its next draw, this one
  -- included.
  local function disownGlass()
    d._lastWriter = nil
    d._writerGen  = d._writerGen + 1
    myWriterGen   = d._writerGen
    invalidateShadow()
    -- Said explicitly rather than left to follow from the line above. An
    -- emptied shadow does happen to force the next frame to emit every cell,
    -- which incidentally repairs the page — but that is a coincidence of two
    -- separate mechanisms, and the writer here bypassed claimGlass (it drew
    -- through kernel.display, not through this proxy), so nothing else was
    -- going to say the page had fallen behind.
    pageStale = true
  end
  -- #PERF — hardware backbuffer state (see proxy.beginFrame). Forward-
  -- declared so syncSize can drop a buffer whose size no longer matches
  -- the screen; the real definitions live below.
  local releaseBackbuffer = function() end
  local function syncSize()
    if d.w ~= W2 or d.h ~= H2 then
      W2, H2 = d.w, d.h
      invalidateShadow()
      releaseBackbuffer()   -- wrong size now; the next frame reallocates
    end
  end
  -- Memory gate. The shadow is ~W*H*3 table slots — a large fraction of RAM on
  -- a small box (TOS runs on machines as tight as ~128 KB). Only enable it with
  -- comfortable headroom; tight boxes fall back to DIRECT draws (the old path),
  -- so they pay no memory for an optimization they can't afford. When off, the
  -- shadow arrays never grow (set/fill/clear skip the shadow bookkeeping).
  --
  -- #OOM — the gate used to be `free > W*H*128`, i.e. free just had to exceed
  -- the shadow's OWN size (~256 KB at 80x25) with ZERO headroom for the thing
  -- doing the drawing. On a box that booted with ~330 KB free, the shadow
  -- claimed most of it and the panels shell then OOM'd at login. Require real
  -- headroom: free must exceed the shadow size PLUS a working reserve, so the
  -- shell that the shadow exists to accelerate still has room to load + run.
  local SHADOW_RESERVE = 384 * 1024   -- working headroom left for the shell
  local baseNeed = d.w * d.h * 128
  -- Sampled against a COLLECTED heap when the cheap reading falls short.
  -- freeMemory() counts uncollected garbage as used, and a proxy is built at
  -- the worst possible moment for that -- right after the shell has finished
  -- loading. Answering "no room" here does not fail; it silently drops the
  -- dirty-cell elision for the life of the seat, so the shell runs slow on a
  -- box that could have afforded it. (hal.freeMemory collects only when the
  -- answer would otherwise have been no.)
  local freeMem
  do
    local okH, hal = pcall(require, "kernel.hal")
    if okH and hal and hal.freeMemory then
      freeMem = hal.freeMemory(baseNeed + SHADOW_RESERVE)
    else
      freeMem = (computer.freeMemory and computer.freeMemory()) or 0
    end
  end
  -- Live gate: honours the operator override (screen.setBuffer) each draw and,
  -- on a toggle, re-syncs by invalidating the now-stale shadow so re-enabling
  -- can't leave ghost cells. `freeMem` is sampled once (per proxy) — re-reading
  -- it every draw would cross the OC bridge, defeating the optimization. The
  -- mode→on/off decision is the pure, unit-tested screen._shadowWanted.
  local myBufferGen = bufferGen
  local function shadowEnabled()
    if bufferGen ~= myBufferGen then myBufferGen = bufferGen; invalidateShadow() end
    return screen._shadowWanted(bufferMode, freeMem, baseNeed, SHADOW_RESERVE)
  end
  -- ============================================================
  -- #PERF — hardware backbuffer (OC 1.7.5+ video RAM)
  -- ============================================================
  -- A GPU with allocateBuffer/setActiveBuffer/bitblt can hand us an
  -- OFF-SCREEN page. Drawing a whole frame into it and bitblt-ing once
  -- costs a single screen-touching call instead of one per set/fill,
  -- and lands atomically — no partial-row tearing while a redraw is in
  -- flight. This is COMPLEMENTARY to the shadow buffer, not a rival:
  -- the shadow still decides the minimum set of cells to draw, the
  -- backbuffer decides how those cells reach the glass.
  --
  -- Deliberate choices:
  --   * FEATURE-DETECTED, never tier-guessed. Video RAM is a separate
  --     budget from system RAM and pre-1.7.5 GPUs lack the methods
  --     entirely, so we pcall-probe and fall back silently.
  --   * ALLOCATED LAZILY, on the first frame. A proxy that never frames
  --     (a headless seat, a test) pays no video RAM.
  --   * FAIL-SAFE. If anything goes wrong mid-frame the active buffer
  --     MUST return to 0, or every later draw lands on an invisible
  --     page and the seat looks dead. endFrame restores unconditionally,
  --     and a failed bitblt invalidates the shadow — the screen did not
  --     get what the shadow now claims it has.
  local backIdx     = nil     -- allocated buffer index, nil = none/unsupported
  local backBroken  = false   -- probe failed once; don't retry every frame
  -- frameDepth and pageStale are declared further up, next to claimGlass,
  -- which has to be able to see them. What pageStale is FOR:
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
    pageStale  = true   -- the next page is a NEW one, and a new page is blank
  end

  -- #SEC M27 — invalidate the fg/bg cache on any pcall failure. If a
  -- transient GPU error (rebind, hot-unplug, kernel reschedule) drops
  -- a setForeground call, we must NOT trust the cached value next
  -- time — otherwise the next set/fill silently runs against the
  -- wrong GPU state until the colour finally changes.
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

  -- ============================================================
  -- Trust, but verify: an ELIDED draw is a claim about the glass
  -- ============================================================
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
  local AUDIT_GAP  = 1        -- seconds between checks
  local function auditCell(x, y)
    if frameDepth > 0 then return false end
    if not (d.gpu and d.gpu.get) then return false end
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    if x < 1 or x > W2 or y < 1 or y > H2 then return false end
    -- Only a cell the cache actually claims to know. A nil is "never drawn
    -- there", which is not a belief and cannot be wrong.
    local k = (y - 1) * W2 + x
    local ch, bg = shC[k], shB[k]
    if ch == nil or bg == nil then return false end
    local now = (computer.uptime and computer.uptime()) or 0
    if now - lastAudit < AUDIT_GAP then return false end
    lastAudit = now
    local okG, gch, _, gbg = pcall(d.gpu.get, x, y)
    if not okG then return false end
    if gch == ch and gbg == bg then return false end
    -- The screen does not hold what we were about to skip drawing.
    invalidateShadow()
    auditHits = auditHits + 1
    -- Say so, ONCE per seat. A silent self-repair would hide the very
    -- thing five rounds of this bug needed: a timestamp to correlate
    -- against what the operator was doing. Once, because a repeating
    -- warning in a redraw path is its own denial of service.
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
  --- How many times this proxy caught its own shadow lying (diagnostics).
  function proxy.auditHits() return auditHits end

  -- Between ROWS of a dump only. proxy.dump makes one component call per
  -- cell, and holding the machine for 2000 of them is the SRM mistake.
  local dumpProc = nil
  local function coopYieldScreen()
    if dumpProc == nil then
      local okP, m = pcall(require, "kernel.process")
      dumpProc = (okP and m and m.yieldCooperative) and m or false
    end
    if dumpProc then dumpProc.yieldCooperative() end
  end

  -- Core drawing calls (direct GPU access for performance)
  function proxy.set(x, y, text, fg, bg)
    if type(x) ~= "number" or type(y) ~= "number" or type(text) ~= "string" then return end
    syncSize(); claimGlass()
    -- Direct path: shadow disabled (tight RAM / operator override) or an
    -- off-screen row that can't be tracked coherently.
    if not shadowEnabled() or y < 1 or y > H2 then
      if fg then setFgCached(fg) end
      if bg then setBgCached(bg) end
      local ok = pcall(d.gpu.set, x, y, text)
      if not ok then lastFg, lastBg = nil, nil end
      _drawEmitted = _drawEmitted + 1
      return
    end
    auditCell(x, y)   -- at most one read-back per second; see auditCell
    local efg, ebg = fg or lastFg, bg or lastBg
    local chars = {}
    for ch in text:gmatch(UTF8) do chars[#chars + 1] = ch end
    local base = (y - 1) * W2
    local first, last = screen._diffWindow(shC, shF, shB, base, x, chars, efg, ebg, W2)
    if not first then
      _drawSkipped = _drawSkipped + 1
      return  -- every target cell already holds this — skip the GPU entirely
    end
    if fg then setFgCached(fg) end
    if bg then setBgCached(bg) end
    -- Emit only the changed window (matching prefix/suffix trimmed).
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
    auditCell(math.max(1, x), math.max(1, y))   -- see auditCell
    local efg, ebg = fg or lastFg, bg or lastBg
    local x1, y1 = math.max(1, x), math.max(1, y)
    local x2, y2 = math.min(W2, x + w - 1), math.min(H2, y + h - 1)
    if x1 > x2 or y1 > y2 then
      -- Entirely off-screen: the shadow can't track it, so emit the raw
      -- rect unchanged and let the GPU clip (exactly the old behaviour).
      if fg then setFgCached(fg) end
      if bg then setBgCached(bg) end
      local okOff = pcall(d.gpu.fill, x, y, w, h, ch)
      if not okOff then lastFg, lastBg = nil, nil end
      _drawEmitted = _drawEmitted + 1
      return
    end
    -- Trim to the changed bounding box (see screen._fillWindow). nil means
    -- every cell already holds this — skip the GPU entirely.
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
    -- Only the emitted window needs recording: cells outside it were left
    -- alone precisely BECAUSE they already held (ch, efg, ebg).
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

  --- Open a frame: subsequent draws go to the off-screen page (when the
  --- GPU has one) and reach the screen on the matching endFrame. Always
  --- safe to call — a GPU without buffer support makes both a no-op and
  --- drawing stays direct. Nestable; only the outermost pair blits.
  --- ALWAYS pair with endFrame, including on an error path.
  function proxy.beginFrame()
    if not backbufferSupported() then return false end
    syncSize()
    frameDepth = frameDepth + 1
    if frameDepth > 1 then return true end       -- already inside a frame
    if not backIdx then
      local okA, idx = pcall(d.gpu.allocateBuffer, W2, H2)
      if not okA or type(idx) ~= "number" or idx <= 0 then
        -- Out of video RAM, or the GPU lied about the method. Never ask
        -- again for this proxy: a failing probe every frame would cost
        -- more than the buffer would have saved.
        backBroken = true; frameDepth = 0; return false
      end
      backIdx = idx
    end
    local okS = pcall(d.gpu.setActiveBuffer, backIdx)
    if not okS then
      releaseBackbuffer(); backBroken = true; return false
    end
    -- Make the page hold what the glass holds, so the dirty-cell elision
    -- stays valid across the flip.
    --
    -- This used to be an ASSUMPTION — "the page holds the previous frame's
    -- pixels" — and it was wrong twice over. A page that was just allocated
    -- holds nothing at all (OC hands back a blank one), and even a page that
    -- has been blitted before is only current up to the moment of that blit:
    -- everything TOS draws outside a frame, which is most of what it draws,
    -- has landed on the glass alone since. Either way the frame then elides
    -- exactly the cells the page is wrong about, and the closing blit paints
    -- that wrongness onto the screen — where the shadow, still insisting
    -- those cells are correct, guarantees nothing ever repaints them.
    --
    -- One blit, and only when something has actually drawn outside a frame
    -- (claimGlass sets the flag), against the ~40-80 gpu.set calls a full
    -- redraw makes. Cheap, and it makes the invariant true instead of hoped
    -- for. If the seeding blit fails we cannot know what the page holds, so
    -- drop the shadow and let this frame emit every cell.
    if pageStale then
      if pcall(d.gpu.bitblt, backIdx, 1, 1, W2, H2, 0, 1, 1) then
        pageStale = false
      else
        invalidateShadow()
      end
    end
    return true
  end

  --- Close a frame: blit the off-screen page to the screen and restore
  --- buffer 0. Safe to call unpaired (no-ops when no frame is open).
  function proxy.endFrame()
    if frameDepth == 0 then return false end
    frameDepth = frameDepth - 1
    if frameDepth > 0 then return true end       -- inner frame; defer
    local blitted = false
    if backIdx then
      blitted = pcall(d.gpu.bitblt, 0, 1, 1, W2, H2, backIdx, 1, 1)
    end
    -- Restore buffer 0 UNCONDITIONALLY. Leaving the active buffer on the
    -- off-screen page is the one failure here that looks like a dead seat.
    local okR = pcall(d.gpu.setActiveBuffer, 0)
    if not okR then releaseBackbuffer(); backBroken = true end
    if not blitted then
      -- The screen did NOT receive what the shadow now believes it has.
      lastFg, lastBg = nil, nil
      invalidateShadow()
      pageStale = true
      return false
    end
    -- Page and glass are identical again, so the next frame can skip its
    -- seeding blit — until the first draw outside a frame says otherwise.
    pageStale = false
    return true
  end

  --- Whether this proxy actually has an off-screen page (diagnostics —
  --- `optimize` reports it alongside the shadow-buffer ratio).
  function proxy.hasBackbuffer() return backIdx ~= nil end

  -- A raw GPU handout may draw outside our shadow — invalidate so the next
  -- proxy draw re-emits rather than trusting a now-uncertain cell. It may
  -- also leave the active buffer somewhere we don't control, so drop ours.
  function proxy.getGpu() disownGlass(); releaseBackbuffer(); return d.gpu end
  -- Exposed so the kernel/shell can force a full repaint after drawing to the
  -- GPU by another route (panic screen, raw component draw, …).
  function proxy.invalidate() invalidateShadow() end
  function proxy.getGpuTier()
    local dp = d.depth or 1
    if dp >= 8 then return 3
    elseif dp >= 4 then return 2
    else return 1 end
  end
  function proxy.getGpuDepth() return d.depth or 1 end

  -- Capture the current screen as plain text (one trimmed string per row) for
  -- the `screendump` command / bug reports. Reads the shadow buffer when it's
  -- active (free — it already mirrors every drawn cell); otherwise falls back to
  -- gpu.get per cell (slower, but always correct and only run on demand). Never
  -- throws — a read hiccup or never-drawn cell becomes a space.
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
    -- Snapshot the CACHES FIRST, before anything that could swap them out.
    -- shadowEnabled() invalidates on a generation change, and an
    -- invalidated shadow is a destroyed alibi: the entire value of this
    -- capture is comparing what the cache BELIEVED against what the glass
    -- actually holds, so the belief has to be read before it can be lost.
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

    -- Run-length one more cell onto a row. Shared by every surface read
    -- below so the three accounts line up column for column.
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
        -- Run-length the colours: a full-width bar is one entry, and a row
        -- that is wrong in one place says so in two.
        pushRun(brun, x, bg)
        pushRun(frun, x, fg)
      end
      lines[y] = (table.concat(row):gsub("%s+$", ""))
      bgRuns[y], fgRuns[y] = brun, frun
    end

    -- ── The cache's own account, always, even when the glass answered ──
    -- Free (no component calls) and it is the half that makes the capture
    -- diagnostic rather than merely descriptive.
    local shadowBg = nil
    if st.shadow and next(sB) ~= nil then
      shadowBg = {}
      for y = 1, H2 do
        local base, runs = (y - 1) * W2, {}
        for x = 1, W2 do pushRun(runs, x, sB[base + x]) end
        shadowBg[y] = runs
      end
    end

    -- ── Where the two part company ────────────────────────────────────
    -- A row listed here is a row the shadow will go on eliding repaints
    -- for, because it believes it is already correct. That is the fault
    -- mechanism itself, not a symptom of it. A nil in the shadow means
    -- "never drawn there" and is not a disagreement.
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

    -- ── And what the off-screen page is carrying ──────────────────────
    -- Only for the disagreeing rows. Reading the page means making it the
    -- ACTIVE buffer, and this must not yield while it is: a yield there
    -- lets another process draw into an off-screen page where its output
    -- silently vanishes. Bounding the read to the rows already known to be
    -- wrong keeps that window a few dozen calls wide instead of 2000.
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
        -- Restore buffer 0 UNCONDITIONALLY. Leaving the active buffer on
        -- the page is the one failure here that looks like a dead seat.
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

  -- Theme access
  proxy.getTheme = function()
    local ok, disp = pcall(require, "kernel.display")
    if ok and disp and disp.getTheme then return disp.getTheme() end
    return setmetatable({}, { __index = function() return 0xFFFFFF end })
  end
  proxy.c = function(name)
    local theme = proxy.getTheme()
    return theme[name] or 0xFFFFFF
  end

  -- Delegate higher-level TUI methods via display.withContext so we
  -- don't duplicate complex drawing logic (box-drawing, menus, etc.)
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
          -- #PERF/#FIX — the forwarded method drew via kernel.display on OUR
          -- gpu, OUTSIDE this proxy's shadow and colour cache. Both are now
          -- stale: reset the shadow (so the next set/fill re-emits those cells)
          -- AND the colour cache (display.lua left the GPU at colours we never
          -- tracked — without this the next colour-elided set could paint in
          -- the wrong colour).
          lastFg, lastBg = nil, nil
          disownGlass()   -- it drew outside EVERY proxy's shadow, not just ours
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
