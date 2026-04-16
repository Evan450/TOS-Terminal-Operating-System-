-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Hardware Abstraction   ║
-- ╚══════════════════════════════════════╝

local component = require("component")
local computer = require("computer")

local hal = {}

-- Component registry: type -> { address, proxy, tier, label }
local components = {}
-- Listeners for hot-plug events
local hotplugCallbacks = {}

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
  -- OC doesn't expose CPU tier directly; infer from architecture
  -- Tier 1: Lua 5.2, Tier 2: Lua 5.3, Tier 3: Lua 5.3
  -- We can also infer from max components
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

local function detectMemoryTier()
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
function hal.onHotplug(callback)
  hotplugCallbacks[#hotplugCallbacks + 1] = callback
end

function hal.handleComponentAdded(addr, ctype)
  if not components[ctype] then components[ctype] = {} end
  local entry = {
    address = addr,
    type    = ctype,
    proxy   = nil,
    tier    = nil,
  }
  components[ctype][#components[ctype] + 1] = entry
  for _, cb in ipairs(hotplugCallbacks) do
    pcall(cb, "added", addr, ctype)
  end
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
  for _, cb in ipairs(hotplugCallbacks) do
    pcall(cb, "removed", addr, ctype)
  end
end

-- Get a human-readable hardware report
function hal.report()
  local lines = {}
  lines[#lines + 1] = "=== TOS Hardware Report ==="
  local info = hal.systemInfo()
  lines[#lines + 1] = string.format("CPU Tier: %d | GPU Tier: %d | RAM Tier: %d",
    info.cpuTier, info.gpuTier, info.memTier)
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
