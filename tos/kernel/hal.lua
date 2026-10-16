-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Hardware Abstraction   ║
-- ╚══════════════════════════════════════╝

local component = require("component")
local computer = require("computer")

local hal = {}

-- Component registry: type -> { address, proxy, tier, label }
local components = {}

-- ============================================================
-- Tier detection heuristics
-- ============================================================
local function detectGPUTier(proxy)
  local ok, maxW = pcall(proxy.maxResolution)
  if not ok or not maxW then return 1 end
  if maxW >= 160 then return 3
  elseif maxW >= 80 then return 2
  else return 1 end
end

local function detectCPUTier()
  -- OC doesn't expose CPU tier directly; infer from what we can see.
  -- NOTE: architecture is NOT a usable signal — every CPU tier can be
  -- switched between Lua 5.2/5.3 by the player, and TOS requires the
  -- 5.3 architecture outright (guarded at the top of /init.lua and in
  -- the BIOS; kernel modules use 5.3 bitwise syntax).
  local cpus = {}
  for addr in component.list("computer") do
    cpus[#cpus + 1] = addr
  end
  -- Best heuristic: check total memory + component count limits
  local totalMem = computer.totalMemory()
  if totalMem >= 786432 then return 3       -- 768KB+ = likely Tier 3 setup
  elseif totalMem >= 262144 then return 2   -- 256KB+ = Tier 2
  else return 1 end
end

-- ── Memory tiers ────────────────────────────────────────────
-- Stock OpenComputers memory sticks: KB per stick -> tier name. These are
-- the default `ramSizes`; a pack that rescales them simply won't match and
-- we report raw capacity rather than inventing a tier. There is NO Tier 4
-- memory in standard OC — T3.5 (1024K) is the top, never extrapolate past it.
local RAM_STICK_TIERS = {
  [192]  = { name = "T1",   num = 1 },
  [256]  = { name = "T1.5", num = 1 },
  [384]  = { name = "T2",   num = 2 },
  [512]  = { name = "T2.5", num = 2 },
  [768]  = { name = "T3",   num = 3 },
  [1024] = { name = "T3.5", num = 3 },
}

--- Tier name for a SINGLE stick of `kb`, or nil when it isn't a stock size.
function hal.stickTier(kb)
  local e = RAM_STICK_TIERS[math.floor(tonumber(kb) or -1)]
  return e and e.name or nil
end

-- What a memory stick tells the machine about itself. Neither host reports
-- a capacity: OpenComputers' bank is {class="memory", description="Memory
-- bank", product="Multipurpose RAM Type", clock=...}, Ocelot's the same with
-- product "MRAM 1x<level>". The only class-"memory" device that carries a
-- capacity is the EEPROM (4096 bytes), and that is the "RAM 4K" a real
-- machine once printed in its boot log: reading capacities found the EEPROM
-- and never a stick. What a bank does report is its clock, the call budget
-- of its tier times 1000 -- callBudgets[stickLevel // 2], so 500 / 1000 /
-- 1500 with the default budgets, one value for each PAIR of stock sizes.
local BAND_SIZES = { ["500"] = { 192, 256 }, ["1000"] = { 384, 512 },
                     ["1500"] = { 768, 1024 } }

local function memoryBanks(deviceInfo)
  if deviceInfo == nil then
    local ok, di = pcall(function() return computer.getDeviceInfo() end)
    if not ok then return nil end
    deviceInfo = di
  end
  if type(deviceInfo) ~= "table" then return nil end
  local banks = {}
  for _, d in pairs(deviceInfo) do
    if type(d) == "table" and d.class == "memory" and d.description == "Memory bank" then
      banks[#banks + 1] = d
    end
  end
  return banks
end

--- How many memory sticks are installed, or nil when the host can't say.
--- Sticks are not components, so component.list("memory") is always empty;
--- getDeviceInfo is the only place they appear.
function hal.ramBanks(deviceInfo)
  local banks = memoryBanks(deviceInfo)
  return banks and #banks or nil
end

--- Per-stick capacities in KB, largest first -- or nil when they can't be
--- worked out. totalMemory() alone cannot tell 2x768K from 1024K+512K (both
--- 1536K over two sticks), which is how a T3.5+T2.5 machine got reported as
--- "tier 3". The clock narrows each stick to two sizes; the machine's total
--- picks between them, since totalMemory() is the plain sum of the installed
--- sizes (OC scales its 64-bit allowance back out of what it reports). The
--- answer must be the ONLY combination that adds up: two sticks always
--- resolve, but from three on two different sets can share a total
--- (2x256 + 2x384 = 2x192 + 512 + 384), and then this says nothing rather
--- than pick one. Non-default call budgets or ramSizes match nothing, and
--- likewise give nil. (test_boot_screen_and_ram.lua)
--- @param deviceInfo table|nil  injected for tests; defaults to the live call
function hal.ramSticks(deviceInfo)
  local banks = memoryBanks(deviceInfo)
  if not banks or #banks == 0 then return nil end
  local pairsOf = {}
  for i, d in ipairs(banks) do
    pairsOf[i] = BAND_SIZES[tostring(d.clock)]
    if not pairsOf[i] then return nil end
  end
  local okT, t = pcall(function() return computer.totalMemory() end)
  local totalKB = okT and tonumber(t) and tonumber(t) / 1024
  if not totalKB then return nil end

  local found, foundKey
  for mask = 0, 2 ^ #pairsOf - 1 do
    local pick, sum, m = {}, 0, mask
    for i, pr in ipairs(pairsOf) do
      pick[i] = pr[m % 2 + 1]; sum = sum + pick[i]; m = math.floor(m / 2)
    end
    if math.abs(sum - totalKB) < 1 then
      table.sort(pick, function(a, b) return a > b end)
      local key = table.concat(pick, ",")
      if foundKey and foundKey ~= key then return nil end
      found, foundKey = pick, key
    end
  end
  return found
end

--- Human summary of installed memory: "2x T3.5", "T3.5 + T2.5", or an honest
--- capacity when the sticks aren't stock sizes / can't be enumerated.
--- MIXED TIERS ARE THE POINT — never average them into one tier.
function hal.ramSummary(sticks, totalKB, modules)
  if sticks == nil then sticks = hal.ramSticks() end
  if type(sticks) == "table" and #sticks > 0 then
    -- Sort a COPY, largest first: grouping only collapses ADJACENT equal
    -- tiers, so an unsorted {1024,512,1024} would read "T3.5 + T2.5 + T3.5".
    -- Copy because the caller's table (e.g. inv.memory.sticks) is not ours.
    local list = {}
    for i = 1, #sticks do list[i] = sticks[i] end
    table.sort(list, function(a, b) return a > b end)
    local parts, label, count = {}, nil, 0
    local function flush()
      if label then
        parts[#parts + 1] = (count > 1 and (count .. "x ") or "") .. label
      end
    end
    for _, kb in ipairs(list) do
      local l = hal.stickTier(kb) or (kb .. "K")
      if l == label then count = count + 1 else flush(); label, count = l, 1 end
    end
    flush()
    return table.concat(parts, " + ")
  end
  -- No per-stick data. Report honestly instead of dividing the total by the
  -- stick count: that average lands on a real tier often enough to be
  -- convincing and wrong (1024+512 over 2 sticks "is" 2x T3).
  --
  -- #FIX (real Minecraft, 2026-08-11) — fall back to the machine's own
  -- total when the caller did not pass one. hal.systemInfo calls this
  -- with no arguments at all, so an unreadable stick list used to render
  -- as "?" — and before the ramSticks fix it rendered as an outright
  -- wrong "4K" on a machine with megabytes. A total is always knowable;
  -- there is no reason for this to be the one line of the boot banner
  -- that gives up.
  -- Only when the caller supplied NOTHING. An explicit 0 is a caller
  -- saying "I know the total and it is zero" — overriding that would be
  -- second-guessing a fact we were handed.
  if totalKB == nil then
    local okT, t = pcall(function() return computer.totalMemory() end)
    if okT and tonumber(t) then totalKB = math.floor(tonumber(t) / 1024) end
  end
  totalKB = math.floor(tonumber(totalKB) or 0)
  modules = tonumber(modules) or hal.ramBanks() or 0
  if totalKB <= 0 then return "?" end
  if modules == 1 then return hal.stickTier(totalKB) or (totalKB .. "K") end
  if modules > 1 then return modules .. " sticks, " .. totalKB .. "K" end
  return totalKB .. "K"
end

-- Legacy NUMERIC tier (systemInfo.memTier). Kept an integer because callers
-- format it with %d, which errors on a fractional tier in Lua 5.3+. Displays
-- should prefer systemInfo().memTierName, which can say "T3.5 + T2.5".
local function detectMemoryTier()
  local sticks = hal.ramSticks()
  if sticks and #sticks > 0 then
    local best = 1
    for _, kb in ipairs(sticks) do
      local e = RAM_STICK_TIERS[kb]
      if e and e.num > best then best = e.num end
    end
    return best
  end
  local totalMem = computer.totalMemory()
  if totalMem >= 786432 then return 3       -- 768KB+
  elseif totalMem >= 262144 then return 2   -- 256KB+
  else return 1 end
end

local function detectHDDTier(proxy)
  local ok, total = pcall(proxy.spaceTotal)
  if not ok or not total then return 1 end
  if total >= 4194304 then return 3         -- 4MB
  elseif total >= 2097152 then return 2     -- 2MB
  else return 1 end
end

-- ============================================================
-- Component scanning
-- ============================================================
function hal.scan()
  components = {}

  for addr, ctype in component.list() do
    local entry = {
      address = addr,
      type    = ctype,
      proxy   = nil,  -- Lazy-load to save memory
      tier    = nil,
      label   = nil,
    }

    -- Only proxy components we need tier info from
    if ctype == "gpu" then
      entry.proxy = component.proxy(addr)
      entry.tier = detectGPUTier(entry.proxy)
    elseif ctype == "filesystem" then
      entry.proxy = component.proxy(addr)
      entry.tier = detectHDDTier(entry.proxy)
      local okL, lbl = pcall(entry.proxy.getLabel)
      entry.label = (okL and lbl) or "Unnamed"
      local okT, tot = pcall(entry.proxy.spaceTotal)
      entry.spaceTotal = (okT and tot) or 0
      local okU, usd = pcall(entry.proxy.spaceUsed)
      entry.spaceUsed = (okU and usd) or 0
    elseif ctype == "drive" then
      -- Unmanaged raw block device: no filesystem API, so it needs the
      -- blockfs driver (TBFS) before it can hold files. Record geometry
      -- so `hw`/POST can show it instead of leaving it invisible.
      entry.proxy = component.proxy(addr)
      entry.unmanaged = true
      local okC, cap = pcall(entry.proxy.getCapacity); entry.capacity = (okC and cap) or 0
      local okS, ss  = pcall(entry.proxy.getSectorSize); entry.sectorSize = (okS and ss) or 0
      local okP, pl  = pcall(entry.proxy.getPlatterCount); entry.platters = (okP and pl) or 1
    end

    if not components[ctype] then
      components[ctype] = {}
    end
    components[ctype][#components[ctype] + 1] = entry
  end

  -- Infer CPU and memory tiers
  components["_cpu_tier"] = detectCPUTier()
  components["_mem_tier"] = detectMemoryTier()
end

-- Get all components of a type
function hal.list(ctype)
  return components[ctype] or {}
end

-- Get the primary (first) component of a type
function hal.primary(ctype)
  local list = components[ctype]
  if list and #list > 0 then
    local entry = list[1]
    -- Lazy proxy creation with error guard (component may have been removed)
    if not entry.proxy then
      local ok, proxy = pcall(component.proxy, entry.address)
      if ok then entry.proxy = proxy end
    end
    return entry
  end
  return nil
end

-- Get a proxy directly
function hal.proxy(ctype)
  local entry = hal.primary(ctype)
  return entry and entry.proxy
end

-- Count components of a type
function hal.count(ctype)
  local list = components[ctype]
  return list and #list or 0
end

-- Check if a component type exists
function hal.has(ctype)
  return hal.count(ctype) > 0
end

-- Get system tier summary
function hal.systemInfo()
  local gpuEntry = hal.primary("gpu")
  return {
    cpuTier    = components["_cpu_tier"] or 1,
    memTier    = components["_mem_tier"] or 1,
    -- Display-friendly memory tier: names half-tiers and mixed sticks
    -- ("T3.5 + T2.5") that the numeric memTier above cannot express.
    memTierName = hal.ramSummary(),
    gpuTier    = gpuEntry and gpuEntry.tier or 0,
    totalMem   = computer.totalMemory(),
    freeMem    = computer.freeMemory(),
    components = hal.componentCount(),
    -- Feature flags based on hardware
    canEncrypt   = computer.totalMemory() >= 262144,   -- Need 256KB+ for crypto
    canMultiUser = computer.totalMemory() >= 196608,   -- Need 192KB+ for user system
    canNetwork   = hal.has("modem"),
    hasTunnel    = hal.has("tunnel"),
    hasWireless  = false, -- Set below
    hasScreen    = hal.has("screen"),
    hasKeyboard  = hal.has("keyboard"),
    isHeadless   = not hal.has("gpu") and not hal.has("screen"),
  }
end

--- Free memory you can act on, rather than the first number offered.
---
--- computer.freeMemory() counts UNCOLLECTED GARBAGE as used, so it only ever
--- UNDERSTATES what is available -- never the reverse. On a real machine that
--- is a factor of four at the end of boot: the kernel logged "Free memory:
--- 322KB" and the same box, eighteen seconds later with nothing freed in
--- between, reported 1268KB.
---
--- Harmless in a log line. Not harmless in a GATE, and four of them read it as
--- fact: whether the optional boot stages load, whether to shout LOW MEMORY,
--- whether the display's dirty-cell shadow is affordable, and what the splash
--- tells the operator they have to work with. Each one was free to answer "no"
--- because of garbage that a collection would have thrown away.
---
--- The one-directional error is what makes the fix cheap. A reading that
--- ALREADY clears `need` is true -- that memory really is free, and no
--- collection can produce less of it -- so the common case pays nothing. Only
--- a reading that falls short might be an artefact, and only then is it worth
--- collecting and asking again. Pass no `need` to mean "I want the honest
--- number" (a report, not a gate) and always collect.
---
--- Returns (bytes, collected).
function hal.freeMemory(need)
  local function read()
    return (computer.freeMemory and computer.freeMemory()) or 0
  end
  local free = read()
  if need and free >= need then return free, false end
  -- OC sandboxes do not always expose collectgarbage, and calling it bare
  -- where it is absent panics rather than erroring. Guarded, no-op otherwise.
  if type(collectgarbage) == "function" then pcall(collectgarbage, "collect") end
  local after = read()
  return (after > free) and after or free, true
end

function hal.componentCount()
  local count = 0
  for ctype, list in pairs(components) do
    if type(list) == "table" then
      count = count + #list
    end
  end
  return count
end

-- Check if modem is wireless
function hal.checkWireless()
  local modem = hal.primary("modem")
  if modem and modem.proxy then
    -- Wireless modems have isWireless()
    local ok, wireless = pcall(function()
      return modem.proxy.isWireless()
    end)
    if ok then
      return wireless
    end
  end
  return false
end

-- ============================================================
-- Hot-plug support (component_added / component_removed)
-- ============================================================
function hal.handleComponentAdded(addr, ctype)
  if not components[ctype] then components[ctype] = {} end
  -- #SEC L — dedup by address. A repeated component_added for an address we
  -- already track (duplicate OC signals or hot-plug churn) must not append
  -- a second entry, which would grow this list without bound over long
  -- uptimes and leave stale duplicates after a single remove.
  for _, e in ipairs(components[ctype]) do
    if e.address == addr then return end
  end
  local entry = {
    address = addr,
    type    = ctype,
    proxy   = nil,
    tier    = nil,
  }
  components[ctype][#components[ctype] + 1] = entry
end

function hal.handleComponentRemoved(addr, ctype)
  if components[ctype] then
    for i, entry in ipairs(components[ctype]) do
      if entry.address == addr then
        table.remove(components[ctype], i)
        break
      end
    end
  end
end

-- Get a human-readable hardware report
function hal.report()
  local lines = {}
  lines[#lines + 1] = "=== TOS Hardware Report ==="
  local info = hal.systemInfo()
  lines[#lines + 1] = string.format("CPU Tier: %d | GPU Tier: %d | RAM: %s",
    info.cpuTier, info.gpuTier, info.memTierName or ("Tier " .. info.memTier))
  lines[#lines + 1] = string.format("Memory: %dKB / %dKB",
    math.floor(info.freeMem / 1024), math.floor(info.totalMem / 1024))
  lines[#lines + 1] = string.format("Total components: %d", info.components)
  lines[#lines + 1] = ""

  for ctype, list in pairs(components) do
    if type(list) == "table" and #list > 0 then
      lines[#lines + 1] = string.format("  %-16s x%d", ctype, #list)
      for _, entry in ipairs(list) do
        local extra = ""
        if entry.tier then extra = extra .. " T" .. entry.tier end
        if entry.label then extra = extra .. ' "' .. entry.label .. '"' end
        lines[#lines + 1] = string.format("    %s%s", entry.address:sub(1, 8) .. "...", extra)
      end
    end
  end
  return table.concat(lines, "\n")
end

return hal
