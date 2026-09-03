-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - System Information / Inventory             ║
-- ║                                                          ║
-- ║  Enumerates the machine's hardware and assigns a TIER to ║
-- ║  each piece, then renders the TOS-ified "System          ║
-- ║  Configuration" POST screen (an AMIBIOS-style boxed      ║
-- ║  table — useful identifiables, not flavor text).         ║
-- ║                                                          ║
-- ║  gather() is pure-ish (component/computer injectable) so ║
-- ║  the tier logic is unit-testable; render() draws via an  ║
-- ║  abstract ctx so the same screen works in early boot     ║
-- ║  (raw GPU) and in the boot-settings viewer (display).    ║
-- ╚══════════════════════════════════════════════════════════╝

local sysinfo = {}

-- ============================================================
-- Tier heuristics
-- ============================================================
-- OC doesn't expose most component tiers directly, so we infer them from
-- capability (data card method set) or capacity (RAM/disk/resolution).

-- Memory tier naming lives in kernel.hal — ONE table, one implementation.
-- It has to read per-stick capacities from getDeviceInfo, because a total
-- alone cannot tell 2x768K from 1024K+512K (both 1536K over two sticks),
-- and guessing from the average reported a real T3.5+T2.5 box as "tier 3".
-- These thin delegations keep sysinfo's own API (and its tests) intact.
local halMod = nil
local function hal()
  if halMod == nil then
    local ok, m = pcall(require, "kernel.hal")
    halMod = (ok and m) or false
  end
  return halMod or nil
end

--- Tier name for a SINGLE stick of `perStickKB`, or nil if not a stock size.
function sysinfo.stickTier(perStickKB)
  local h = hal()
  return h and h.stickTier and h.stickTier(perStickKB) or nil
end

--- Human summary of installed memory: "2x T3.5", "T3.5 + T2.5", or an honest
--- capacity when the sticks can't be enumerated / aren't stock sizes.
--- @param sticks table|nil  per-stick KB; nil asks hal to probe the hardware
function sysinfo.ramSummary(totalKB, modules, sticks)
  local h = hal()
  if not (h and h.ramSummary) then return tostring(math.floor(totalKB or 0)) .. "K" end
  return h.ramSummary(sticks, totalKB, modules)
end

-- Legacy coarse label, kept for callers that only have a total. Prefer
-- sysinfo.ramSummary (it knows the stick count and so can name the real tier).
local function memTier(totalKB)
  if totalKB >= 512 then return "T2+"
  elseif totalKB >= 256 then return "T1.5"
  else return "T1" end
end

local function gpuTier(depth)
  if not depth or depth <= 1 then return 1 end
  if depth <= 4 then return 2 end
  return 3
end

-- Screen tier from its max resolution (T1 50x16, T2 80x25, T3 160x50).
local function screenTier(w, h)
  w, h = w or 0, h or 0
  if w >= 160 or h >= 50 then return 3 end
  if w >= 80  or h >= 25 then return 2 end
  return 1
end

-- Managed disks: floppy ~512K, T1 ~1MB, T2 ~2MB, T3 ~4MB.
local function diskTier(totalKB)
  if totalKB <= 600  then return "Floppy" end
  if totalKB <= 1100 then return "T1" end
  if totalKB <= 2200 then return "T2" end
  return "T3"
end

-- Data card tier by method availability, with an operator override
-- (mirrors the CPU-tier path). T1: md5/crc32/deflate. T2 adds sha256 +
-- AES encrypt/decrypt. T3 adds ECC (ecdsa/ecdh/generateKeyPair). Some OC
-- builds/emulators hand back a `data` proxy whose method set doesn't probe
-- cleanly — the card is present but classifies as "unknown" — so an
-- operator can pin the tier in Boot Settings just like the CPU tier.
-- Returns (tier, name, source) where source is "override"|"detected"|"unknown".
local DATA_TIER_NAMES = {
  [1] = "T1 (MD5 / CRC / deflate)",
  [2] = "T2 (AES + SHA-256)",
  [3] = "T3 (ECC + AES + SHA-256)",
}
local function dataCardTier(p, overrides, addr)
  if overrides and tonumber(overrides.dataTier) then
    local t = tonumber(overrides.dataTier)
    return t, DATA_TIER_NAMES[t] or ("T" .. t), "override"
  end
  -- Delegate the method-probe to the shared kernel.datacard classifier so
  -- the POST screen, crypto, and compress all agree on the tier. Pass the
  -- address so it can use component.methods() (the field-probe alone returns
  -- empty on Ocelot, which is what made every card read as "unknown tier").
  local okD, dc = pcall(require, "kernel.datacard")
  if okD and dc and dc.capsOf then
    local tier = dc.tierOf(dc.capsOf(p, addr))
    if tier >= 1 then return tier, DATA_TIER_NAMES[tier], "detected" end
    return 0, "present (unknown tier)", "unknown"
  end
  -- Fallback (datacard module unavailable): inline probe.
  local function has(m) return type(p[m]) == "function" end
  if has("generateKeyPair") or has("ecdsa") or has("ecdh") then
    return 3, DATA_TIER_NAMES[3], "detected"
  elseif has("sha256") or has("encrypt") then
    return 2, DATA_TIER_NAMES[2], "detected"
  elseif has("md5") or has("crc32") then
    return 1, DATA_TIER_NAMES[1], "detected"
  end
  return 0, "present (unknown tier)", "unknown"
end

sysinfo._memTier    = memTier
sysinfo._gpuTier    = gpuTier
sysinfo._screenTier = screenTier
sysinfo._diskTier   = diskTier

-- CPU tier is NOT cleanly exposed by OC. We try, in order:
--   1. an operator override (corrects a wrong/undetected guess),
--   2. computer.getDeviceInfo() — some builds name the tier in the
--      processor entry's product/description/clock,
--   3. give up → "unknown", and let boot-settings ask the operator (or run
--      the opt-in behavioral benchmark below).
-- Returns (tier|nil, source) where source is
-- "override" | "detected" | "estimated" | "unknown".
--   override  — operator pinned it (corrects a wrong/undetected guess)
--   detected  — getDeviceInfo named the tier
--   estimated — indirect inference from installed RAM (OC ties CPU+RAM
--               tiers in practice); a best guess the operator should confirm
--   unknown   — nothing to go on (no deviceInfo, no RAM figure)
local function detectCpuTier(deviceInfo, overrides, ramKB)
  if overrides and tonumber(overrides.cpuTier) then
    return tonumber(overrides.cpuTier), "override"
  end
  if type(deviceInfo) == "table" then
    for _, d in pairs(deviceInfo) do
      if type(d) == "table" then
        local class = tostring(d.class or ""):lower()
        if class == "processor" then
          local hay = ((d.product or "") .. " " .. (d.description or "") .. " " ..
            tostring(d.clock or "")):lower()
          local t = hay:match("tier%s*(%d)")
          if t then return tonumber(t), "detected" end
        end
      end
    end
  end
  -- Indirect estimate from RAM (mirrors hal.detectCPUTier's heuristic).
  if type(ramKB) == "number" and ramKB > 0 then
    if ramKB >= 768 then return 3, "estimated"
    elseif ramKB >= 256 then return 2, "estimated"
    else return 1, "estimated" end
  end
  return nil, "unknown"
end
sysinfo._detectCpuTier = detectCpuTier

--- Opt-in behavioral CPU estimate. NOT run at boot (it burns ~one game tick).
--- Counts how many cheap direct calls complete before the tick advances —
--- a rough proxy for the CPU's per-tick call budget, which scales with tier.
--- Returns (calls, tierGuess). The operator can still override; this is a
--- "best guess" for the boot-settings "detect" action when getDeviceInfo
--- can't name the tier.
function sysinfo.benchmarkCallBudget(computer)
  computer = computer or require("computer")
  local t0 = computer.uptime()
  local n = 0
  while computer.uptime() == t0 and n < 1e7 do n = n + 1 end
  local tier = (n > 2.5e5) and 3 or (n > 1.0e5) and 2 or 1
  return n, tier
end

-- ============================================================
-- gather() — build the structured inventory
-- ============================================================
-- @param deps      table|nil  { component=, computer=, deviceInfo= } injection
-- @param overrides table|nil  operator corrections (e.g. { cpuTier = 2 })
-- @param onProgress fn|nil     called with a short status string per phase, so
--                              the caller can show "Standby — detecting ..."
function sysinfo.gather(deps, overrides, onProgress)
  deps = deps or {}
  overrides = overrides or {}
  onProgress = onProgress or function() end
  local component = deps.component or require("component")
  local computer  = deps.computer  or require("computer")

  -- getDeviceInfo() gives richer, non-hardcoded hardware detail when the OC
  -- build supports it (vendor/product/class/clock). Optional everywhere.
  local deviceInfo = deps.deviceInfo
  if deviceInfo == nil then
    pcall(function()
      if computer.getDeviceInfo then deviceInfo = computer.getDeviceInfo() end
    end)
  end

  local inv = {
    cpu = {}, memory = {}, gpu = {}, screen = {}, disks = {},
    modems = {}, dataCard = { present = false },
    eeprom = {}, tunnel = { present = false }, other = {},
    internet = { present = false },
    deviceInfo = deviceInfo,
  }

  -- Processor / architecture + tier (detected / overridden / unknown).
  onProgress("Detecting processor and memory")
  local arch = "Lua 5.3"
  pcall(function()
    if computer.getArchitecture then arch = computer.getArchitecture() end
  end)
  inv.cpu.arch = arch

  -- Memory
  local total = (computer.totalMemory and computer.totalMemory()) or 0
  local free  = (computer.freeMemory  and computer.freeMemory())  or 0
  inv.memory.totalKB = math.floor(total / 1024)
  inv.memory.freeKB  = math.floor(free / 1024)
  inv.memory.tier    = memTier(inv.memory.totalKB)
  -- Honest module count: each installed RAM stick is a "memory" component.
  -- Reported exactly when listable; the tier above is the educated fallback.
  inv.memory.modules = 0
  for _ in component.list("memory") do inv.memory.modules = inv.memory.modules + 1 end
  -- Name the memory ACTUALLY installed ("2x T3.5", "T3.5 + T2.5") instead of
  -- the coarse total-only guess ("T2+" read the same for 512K and 2048K).
  -- Per-stick capacities come from deviceInfo — the only source that can tell
  -- mixed tiers apart; without it we report capacity rather than guess.
  local h = hal()
  inv.memory.sticks  = h and h.ramSticks and h.ramSticks(deviceInfo) or nil
  inv.memory.summary = sysinfo.ramSummary(inv.memory.totalKB, inv.memory.modules,
                                          inv.memory.sticks)

  -- CPU component count (OC exposes the processor as a component).
  inv.cpu.count = 0
  for _ in component.list("cpu") do inv.cpu.count = inv.cpu.count + 1 end

  -- CPU tier: detect / override / estimate-from-RAM / unknown.
  inv.cpu.tier, inv.cpu.tierSource =
    detectCpuTier(deviceInfo, overrides, inv.memory.totalKB)

  -- GPU(s) — report the best depth/resolution available
  onProgress("Detecting display")
  local gpuCount, bestDepth, bestW, bestH = 0, 1, 0, 0
  for addr in component.list("gpu") do
    gpuCount = gpuCount + 1
    pcall(function()
      local g = component.proxy(addr)
      local d = (g.getDepth and g.getDepth()) or 1
      if d > bestDepth then bestDepth = d end
      local mw, mh = g.maxResolution()
      if mw and mw > bestW then bestW, bestH = mw, mh end
    end)
  end
  inv.gpu = { count = gpuCount, tier = gpuTier(bestDepth),
              depth = bestDepth, maxW = bestW, maxH = bestH }

  -- Screens
  local screenCount = 0
  for _ in component.list("screen") do screenCount = screenCount + 1 end
  inv.screen = { count = screenCount, tier = screenTier(bestW, bestH) }

  -- Filesystems (disks)
  onProgress("Detecting storage")
  -- OC's built-in scratch filesystem (mounted at /tmp) is a COMPONENT
  -- like any disk, so without this flag it masqueraded as hardware —
  -- the operator counted "two disks + a floppy" and the POST screen
  -- showed four drives. Tag it here so every renderer can be honest.
  local tmpAddr = computer.tmpAddress and computer.tmpAddress() or nil
  for addr in component.list("filesystem") do
    pcall(function()
      local p = component.proxy(addr)
      local tkb = math.floor(((p.spaceTotal and p.spaceTotal()) or 0) / 1024)
      local ukb = math.floor(((p.spaceUsed  and p.spaceUsed())  or 0) / 1024)
      local isTmp = (addr == tmpAddr)
      inv.disks[#inv.disks + 1] = {
        addr     = addr:sub(1, 8),
        label    = (p.getLabel and p.getLabel()) or "",
        usedKB   = ukb, totalKB = tkb,
        tier     = isTmp and "RAM" or diskTier(tkb),
        tmpfs    = isTmp or nil,
        readonly = (p.isReadOnly and p.isReadOnly()) or false,
      }
    end)
  end
  -- Unmanaged raw drives (no filesystem component). Listed alongside disks
  -- so the operator sees ALL storage; diskRole names them "Raw Drive".
  --
  -- EXACT match (the `true`): OC's component.list does a SUBSTRING match by
  -- default, so a bare "drive" filter also catches `tape_drive`
  -- (Computronics) and `disk_drive` (OC's floppy drive block) — which is
  -- how a tape drive ended up in the storage table as "Raw Drive … 0KB"
  -- (operator report). Neither is an unmanaged block device, and one of
  -- them is a *formattable* target in the `drive` command.
  for addr in component.list("drive", true) do
    pcall(function()
      local p = component.proxy(addr)
      local cap = (p.getCapacity and p.getCapacity()) or 0
      inv.disks[#inv.disks + 1] = {
        addr = addr:sub(1, 8), label = "",
        usedKB = 0, totalKB = math.floor(cap / 1024),
        tier = "Raw", unmanaged = true,
        sectorSize = (p.getSectorSize and p.getSectorSize()) or 0,
      }
    end)
  end
  -- Tape drives get an honest row of their own: they ARE storage the
  -- operator cares about, but they're sequential media, not a filesystem.
  -- Report whether a tape is actually loaded rather than implying a 0KB
  -- volume.
  for addr in component.list("tape_drive", true) do
    pcall(function()
      local p = component.proxy(addr)
      local loaded = false
      pcall(function() loaded = p.isReady and p.isReady() or false end)
      local sizeKB = 0
      if loaded then
        pcall(function() sizeKB = math.floor(((p.getSize and p.getSize()) or 0) / 1024) end)
      end
      local label
      if loaded then pcall(function() label = p.getLabel and p.getLabel() end) end
      inv.disks[#inv.disks + 1] = {
        addr = addr:sub(1, 8),
        label = (label ~= nil and label ~= "") and label or (loaded and "" or "(no tape)"),
        usedKB = 0, totalKB = sizeKB,
        tier = "Tape", tape = true, loaded = loaded,
      }
    end)
  end
  table.sort(inv.disks, function(a, b) return a.totalKB > b.totalKB end)

  -- Modems
  onProgress("Detecting network and peripherals")
  for addr in component.list("modem") do
    pcall(function()
      local p = component.proxy(addr)
      local wireless = (p.isWireless and p.isWireless()) or false
      local strength = (wireless and p.getStrength) and p.getStrength() or nil
      inv.modems[#inv.modems + 1] =
        { addr = addr:sub(1, 8), wireless = wireless, strength = strength }
    end)
  end
  for addr in component.list("tunnel") do
    inv.tunnel = { present = true, addr = addr:sub(1, 8) }
  end

  -- Internet card. Promoted out of the generic `other` counts because the
  -- interesting part is not that one is installed but whether the SERVER
  -- lets it do anything: HTTP and TCP are separately switchable in the
  -- mod's config, so a card can be present and completely useless. An
  -- operator seeing "Internet Card  present, HTTP off" knows to go argue
  -- with the server owner instead of debugging TOS.
  for addr in component.list("internet") do
    pcall(function()
      local p = component.proxy(addr)
      inv.internet = {
        present = true,
        addr    = addr:sub(1, 8),
        http    = (p.isHttpEnabled and p.isHttpEnabled()) or false,
        tcp     = (p.isTcpEnabled and p.isTcpEnabled()) or false,
      }
    end)
    break
  end

  -- Data card (crypto capability). The tier honors an operator override
  -- (overrides.dataTier), same as the CPU tier above.
  for addr in component.list("data") do
    pcall(function()
      local p = component.proxy(addr)
      local tier, name, source = dataCardTier(p, overrides, addr)
      inv.dataCard = { present = true, addr = addr:sub(1, 8),
                       tier = tier, name = name, tierSource = source }
    end)
    break
  end

  -- EEPROM (BIOS)
  for addr in component.list("eeprom") do
    pcall(function()
      local p = component.proxy(addr)
      inv.eeprom = {
        addr     = addr:sub(1, 8),
        label    = (p.getLabel and p.getLabel()) or "EEPROM",
        size     = (p.getSize and p.getSize()) or nil,
        bootAddr = (computer.getBootAddress and (computer.getBootAddress() or "")
                     :sub(1, 8)) or nil,
      }
    end)
    break
  end

  -- Everything else — counts by type (redstone, robot, hologram, …)
  local KNOWN = {
    gpu = true, screen = true, filesystem = true, modem = true,
    tunnel = true, data = true, eeprom = true, keyboard = true,
    internet = true,   -- reported above, with its HTTP/TCP state
  }
  local counts = {}
  for addr, ctype in component.list() do
    if not KNOWN[ctype] then counts[ctype] = (counts[ctype] or 0) + 1 end
  end
  for t, n in pairs(counts) do inv.other[#inv.other + 1] = { type = t, count = n } end
  table.sort(inv.other, function(a, b) return a.type < b.type end)

  return inv
end

-- ============================================================
-- rows() — flatten the inventory into label/value display rows
-- ============================================================
-- Returns an array of { label=, value=, role= }. role colors the value
-- ("ok"/"warn"/"dim"/"value") or marks a "section" header. The layout
-- separates what's installed IN the computer (System) from drives (Storage)
-- and from external blocks (Peripherals) — a disk drive is not RAM.
-- render() lays these out; tests assert on them directly without a screen.
function sysinfo.rows(inv)
  local r = {}
  local function add(label, value, role)
    r[#r + 1] = { label = label, value = value, role = role or "value" }
  end
  local function section(name) r[#r + 1] = { label = "", value = name, role = "section" } end

  -- ── System (internal: CPU, RAM, cards) ──────────────────
  section("System")
  do
    local s = inv.cpu.tierSource
    local tierStr, role
    if not inv.cpu.tier then
      tierStr, role = "  [Tier ? - set in boot settings]", "warn"
    elseif s == "override" then
      tierStr, role = "  [Tier " .. inv.cpu.tier .. "*]", "value"        -- pinned
    elseif s == "estimated" then
      tierStr, role = "  [~Tier " .. inv.cpu.tier .. " est - confirm in settings]", "warn"
    else  -- detected
      tierStr, role = "  [Tier " .. inv.cpu.tier .. "]", "value"
    end
    add("Processor", (inv.cpu.arch or "?") .. tierStr, role)
  end
  add("Memory", string.format("%dK free / %dK total  [%s]",
    inv.memory.freeKB or 0, inv.memory.totalKB or 0,
    inv.memory.summary or inv.memory.tier or "?"),
    (inv.memory.totalKB or 0) < 192 and "warn" or "value")
  if (inv.gpu.count or 0) > 0 then
    add("Graphics", string.format("GPU T%d, %d-bit, max %dx%d%s",
      inv.gpu.tier or 1, inv.gpu.depth or 1, inv.gpu.maxW or 0, inv.gpu.maxH or 0,
      (inv.gpu.count or 0) > 1 and ("  (x" .. inv.gpu.count .. ")") or ""), "value")
  else
    add("Graphics", "no GPU card", "warn")
  end
  if inv.dataCard.present then
    local label = inv.dataCard.name or "data card"
    local s, role = inv.dataCard.tierSource, "ok"
    if s == "unknown" then
      label, role = label .. "  [tier ? - set in boot settings]", "warn"
    elseif s == "override" then
      label = label .. "*"  -- operator-pinned
    end
    add("Crypto", label, role)
  else
    add("Crypto", "software fallback (no data card)", "warn")
  end
  if #inv.modems > 0 then
    local parts = {}
    for _, m in ipairs(inv.modems) do
      parts[#parts + 1] = m.wireless
        and ("wireless" .. (m.strength and (" " .. math.floor(m.strength)) or ""))
        or "wired"
    end
    add("Network", table.concat(parts, ", ") .. " card", "value")
  elseif inv.tunnel.present then
    add("Network", "linked card (tunnel)", "value")
  else
    add("Network", "none", "dim")
  end
  -- Internet card. Reported only when installed — a machine without one is
  -- the norm, and a "none" row for every optional card would bury the rows
  -- that matter. When present, say what the SERVER allows: a card with HTTP
  -- switched off is the confusing case worth a warning colour.
  if inv.internet and inv.internet.present then
    local caps = {}
    if inv.internet.http then caps[#caps + 1] = "HTTP" end
    if inv.internet.tcp  then caps[#caps + 1] = "TCP"  end
    if #caps > 0 then
      add("Internet", table.concat(caps, " + ") .. " card", "value")
    else
      add("Internet", "card present, disabled by the server", "warn")
    end
  end
  if inv.eeprom.addr then
    add("EEPROM", string.format("%s%s", inv.eeprom.label or "EEPROM",
      inv.eeprom.bootAddr and ("  boot:" .. inv.eeprom.bootAddr) or ""), "dim")
  end

  -- ── Storage (drives) ────────────────────────────────────
  section("Storage")
  if #inv.disks == 0 then
    add("", "(no drives)", "dim")
  else
    for _, d in ipairs(inv.disks) do
      local name = (d.label ~= "" and d.label) or d.addr
      local sz = string.format("%d/%dKB", d.usedKB, d.totalKB)
      add("", string.format("%-12s %-13s [%s]%s", name, sz, d.tier,
        d.readonly and " ro" or ""), "dim")
    end
  end

  -- ── Peripherals (external blocks) ───────────────────────
  section("Peripherals")
  add("Screens", tostring(inv.screen.count or 0) ..
    ((inv.screen.count or 0) > 0 and ("  [T" .. (inv.screen.tier or 1) .. "]") or ""),
    (inv.screen.count or 0) == 0 and "warn" or "dim")
  if #inv.other > 0 then
    local parts = {}
    for _, o in ipairs(inv.other) do
      parts[#parts + 1] = o.type .. (o.count > 1 and ("x" .. o.count) or "")
    end
    add("Attached", table.concat(parts, ", "), "dim")
  else
    add("Attached", "(none)", "dim")
  end

  return r
end

-- ============================================================
-- Storage roles (pure — unit-tested)
-- ============================================================
--- The honest role name for one drive row. The old rule collapsed
--- everything small into "RAM Disk", which mislabeled a real 512KB
--- floppy (the Optional Utilities disk!) and hid what tmpfs actually
--- is. Now: the boot disk, OC's built-in scratch fs (named by its
--- mount point, /tmp), AMIBIOS-style lettered floppies, and numbered
--- data drives. `state` carries the running counters across a listing.
function sysinfo.diskRole(d, isBoot, state)
  state = state or {}
  if isBoot then return "Boot Drive" end
  if d.tape then return "Tape Drive" end         -- sequential media, not an fs
  if d.unmanaged then return "Raw Drive" end     -- unmanaged block device
  if d.tmpfs or d.label == "tmpfs" then return "Temp /tmp" end
  if d.tier == "Floppy" or (d.totalKB or 0) <= 600 then
    state.floppy = (state.floppy or 0) + 1
    return "Floppy " .. string.char(64 + math.min(state.floppy, 26))
  end
  state.data = (state.data or 0) + 1
  return "Data Drive " .. state.data
end

-- ============================================================
-- render() — draw the boxed POST screen via an abstract ctx
-- ============================================================
-- ctx = {
--   W, H,                              screen dimensions
--   set   = function(x, y, text, fg, bg) end,   write text
--   fill  = function(x, y, w, ch, fg, bg) end,  fill a run (optional)
--   color = function(role) return rgb end,      role -> color (optional)
--   title = "TOS System Configuration",         optional override
-- }
-- Returns the y of the line after the box (so the caller can print "Starting…").
-- AMIBIOS-style POST screen: a rigid two-column "Main Processor : … | Base
-- Memory Size : …" grid over a storage table, with retro labels and pseudo
-- drive names (Primary Master / Floppy Drive A) — TOS facts in an AMI suit.
-- ctx = { W, H, set(x,y,text,fg,bg), color(role)->rgb, title }. Returns the y
-- of the line after the screen (for the caller's "Press DEL…" / "Starting…").
-- sysinfo.rows() is unchanged (the Boot Settings hardware view still uses it).
function sysinfo.render(inv, ctx)
  local W, H = ctx.W or 50, ctx.H or 16
  local set  = ctx.set
  local col  = ctx.color or function() return 0xFFFFFF end
  local bg   = col("bg")
  -- Clipped, role-coloured write (everything here is ASCII → byte==cell).
  local function put(x, y, text, role)
    if not text or y < 1 or y > H or x > W then return end
    local maxLen = W - x + 1
    if maxLen < 1 then return end
    set(x, y, tostring(text):sub(1, maxLen), col(role or "value"), bg)
  end
  local function rule(y) put(2, y, string.rep("-", math.max(0, W - 2)), "border") end

  local cpu  = inv.cpu or {}
  local mem  = inv.memory or {}
  local gpu  = inv.gpu or {}
  local total = mem.totalKB or 0
  local free  = mem.freeKB or 0

  -- Every field below reports something REAL — no invented PC-BIOS facts
  -- (no base/extended memory split, no fake numeric coprocessor). Components
  -- are named for what they are (CPU, Data Card, GPU, …); when a thing isn't
  -- present we say so rather than dressing it up.
  local function cpuTier()
    if not cpu.tier then return "Tier ?  (set in Boot Settings)" end
    local s = cpu.tierSource
    return "Tier " .. cpu.tier ..
      (s == "override" and "  *" or (s == "estimated" and "  (est)" or ""))
  end
  local function gpuStr()
    if (gpu.count or 0) == 0 then return "none" end
    return "GPU T" .. (gpu.tier or 1) .. " / " .. (gpu.depth or 1) .. "-bit"
      .. ((gpu.count or 0) > 1 and ("  (x" .. gpu.count .. ")") or "")
  end
  local function dataCardStr()
    if not (inv.dataCard and inv.dataCard.present) then return "not installed" end
    local t, s = inv.dataCard.tier, inv.dataCard.tierSource
    if t and t >= 1 then return "Tier " .. t .. (s == "override" and "  *" or "") end
    return "present (tier ? - set in Boot Settings)"
  end
  local function netStr()
    if inv.modems and #inv.modems > 0 then
      local m = inv.modems[1]
      if m.wireless then
        return "Wireless" .. (m.strength and (" " .. math.floor(m.strength)) or "")
      end
      return "Wired"
    end
    if inv.tunnel and inv.tunnel.present then return "Linked (tunnel)" end
    return "none"
  end
  -- RAM: report the exact installed-stick count when listable; otherwise the
  -- educated guess (the memory TIER) rather than a made-up number.
  local ramLabel, ramVal
  if (mem.modules or 0) > 0 then
    ramLabel, ramVal = "RAM Modules", tostring(mem.modules)
  else
    ramLabel, ramVal = "Memory Tier", (mem.tier or "?") .. "  (est)"
  end

  -- ── Frame (wide screens get the full AMIBIOS-style box) ──────────
  -- Double-line outer frame with the title as a top-border tab, a
  -- ╠═╡ Storage ╞═╣ section divider, and a │ column divider through
  -- the grid — the reference look the screen was modeled on. Border
  -- rows are composed to EXACT width (box chars are multi-byte; they
  -- never pass through put()'s byte-clipping). Narrow (T1) screens
  -- keep the plain dashed layout.
  local wide = W >= 72
  local bx1, bx2 = 2, W - 1
  local binner = bx2 - bx1 - 1
  local function boxRow(yy, l, m, r2, tab)
    if yy < 1 or yy > H then return end
    set(bx1, yy, l .. string.rep(m, binner) .. r2, col("border"), bg)
    if tab then set(bx1 + 2, yy, "╡ " .. tab .. " ╞", col("title"), bg) end
  end
  local function walls(yy)
    if yy < 1 or yy > H then return end
    set(bx1, yy, "║", col("border"), bg)
    set(bx2, yy, "║", col("border"), bg)
  end

  local LEFT = {
    { "Processor",  (cpu.arch or "Lua 5.3") .. ((cpu.count or 0) > 1 and ("  (x" .. cpu.count .. ")") or "") },
    { "CPU Tier",   cpuTier() },
    { "Graphics",   gpuStr() },
    { "Data Card",  dataCardStr() },
    { "Network",    netStr() },
    { "EEPROM",     (inv.eeprom and inv.eeprom.label) or "Lua BIOS" },
  }
  local RIGHT = {
    { "Total Memory", total .. "KB" },
    { "Free Memory",  free .. "KB" },
    { ramLabel,       ramVal },
    { "Max Text Mode", (gpu.maxW or 0) .. "x" .. (gpu.maxH or 0) },
    { "Screens",      tostring(inv.screen and inv.screen.count or 0)
                      .. ((inv.screen and (inv.screen.count or 0) > 0)
                          and ("  (T" .. (inv.screen.tier or 1) .. ")") or "") },
    { "Boot ID",      (inv.eeprom and inv.eeprom.bootAddr) or "(unknown)" },
  }
  local function kv(x, y, label, value, lw)
    put(x, y, label .. string.rep(" ", math.max(0, lw - #label)) .. " : ", "dim")
    put(x + lw + 3, y, value, "value")
  end
  local y
  if wide then     -- boxed two-column layout
    boxRow(1, "╔", "═", "╗", ctx.title or "TOS System Configuration")
    y = 2
    local mid = math.floor(W / 2) + 1
    for i = 1, math.max(#LEFT, #RIGHT) do
      walls(y)
      if LEFT[i]  then kv(4,   y, LEFT[i][1],  LEFT[i][2],  13) end
      if RIGHT[i] then kv(mid, y, RIGHT[i][1], RIGHT[i][2], 13) end
      set(mid - 2, y, "│", col("border"), bg)
      y = y + 1
    end
    boxRow(y, "╠", "═", "╣", "Storage"); y = y + 1
  else             -- narrow (T1): plain stacked column, dashed rules
    put(2, 1, ctx.title or "TOS System Configuration", "title")
    rule(2)
    y = 4
    for _, e in ipairs(LEFT)  do kv(2, y, e[1], e[2], 13); y = y + 1 end
    for _, e in ipairs(RIGHT) do kv(2, y, e[1], e[2], 13); y = y + 1 end
    rule(y); y = y + 1
    put(2, y, "Storage", "title"); y = y + 1
  end

  -- ── Storage (honest role names + real labels/addresses) ───────────
  if wide then
    walls(y)
    put(4, y, string.format("%-12s %-10s %-13s %-6s %s",
      "Role", "Label", "Used/Size", "Tier", "Boot"), "dim")
    y = y + 1
  end
  local bootAddr = inv.eeprom and inv.eeprom.bootAddr
  local disks = {}
  for _, d in ipairs(inv.disks or {}) do disks[#disks + 1] = d end
  table.sort(disks, function(a, b)         -- boot drive first, then by size
    local ab, bb = (a.addr == bootAddr), (b.addr == bootAddr)
    if ab ~= bb then return ab end
    return (a.totalKB or 0) > (b.totalKB or 0)
  end)
  local roleState = {}
  for _, d in ipairs(disks) do
    if y >= H then break end
    local isBoot = (d.addr == bootAddr)
    local role = sysinfo.diskRole(d, isBoot, roleState)
    local label = (d.label ~= "" and d.label or d.addr)
    local size  = string.format("%d/%dKB", d.usedKB or 0, d.totalKB or 0)
    local rowText = wide
      and string.format("%-12s %-10s %-13s %-6s %s",
            role, label:sub(1, 10), size, tostring(d.tier or "?"), isBoot and "Yes" or "No")
      or  string.format("%-11s %-11s %s%s", role, label:sub(1, 11), size, isBoot and "  *" or "")
    if wide then walls(y) end
    put(4, y, rowText, isBoot and "ok" or "value")
    y = y + 1
  end
  if #disks == 0 then
    if wide then walls(y) end
    put(4, y, "(no drives)", "dim"); y = y + 1
  end
  if wide then boxRow(y, "╚", "═", "╝") else rule(y) end
  y = y + 1

  -- ── Footer (honest one-line summary) ──────────────────────────────
  put(2, y, string.format("Memory %d/%dKB free    Display GPU T%d  %dx%d",
    free, total, gpu.tier or 1, gpu.maxW or 0, gpu.maxH or 0), "ok")
  y = y + 1
  return y
end

return sysinfo
