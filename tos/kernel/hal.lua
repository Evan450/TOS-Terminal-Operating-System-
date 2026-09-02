local component = require("component")
local computer = require("computer")

local hal = {}

local components = {}

local function detectGPUTier(proxy)
  local ok, maxW = pcall(proxy.maxResolution)
  if not ok or not maxW then return 1 end
  if maxW >= 160 then return 3
  elseif maxW >= 80 then return 2
  else return 1 end
end

local function detectCPUTier()

  local cpus = {}
  for addr in component.list("computer") do
    cpus[#cpus + 1] = addr
  end

  local totalMem = computer.totalMemory()
  if totalMem >= 786432 then return 3
  elseif totalMem >= 262144 then return 2
  else return 1 end
end

local RAM_STICK_TIERS = {
  [192]  = { name = "T1",   num = 1 },
  [256]  = { name = "T1.5", num = 1 },
  [384]  = { name = "T2",   num = 2 },
  [512]  = { name = "T2.5", num = 2 },
  [768]  = { name = "T3",   num = 3 },
  [1024] = { name = "T3.5", num = 3 },
}

function hal.stickTier(kb)
  local e = RAM_STICK_TIERS[math.floor(tonumber(kb) or -1)]
  return e and e.name or nil
end

function hal.ramSticks(deviceInfo)
  if deviceInfo == nil then
    local ok, di = pcall(function() return computer.getDeviceInfo() end)
    if not ok then return nil end
    deviceInfo = di
  end
  if type(deviceInfo) ~= "table" then return nil end
  local raws = {}
  for _, d in pairs(deviceInfo) do
    if type(d) == "table" and d.class == "memory" then
      local cap = tonumber(d.capacity or d.size)
      if cap and cap > 0 then raws[#raws + 1] = cap end
    end
  end
  if #raws == 0 then return nil end

  local sum = 0
  for _, c in ipairs(raws) do sum = sum + c end

  local totalBytes
  do
    local okT, t = pcall(function() return computer.totalMemory() end)
    totalBytes = okT and tonumber(t) or nil
  end

  local function plausible(a, b)

    if not a or not b or a <= 0 or b <= 0 then return false end
    local hi, lo = math.max(a, b), math.min(a, b)
    return (lo / hi) >= 0.75
  end

  local divide
  if totalBytes then
    local asBytes = plausible(sum, totalBytes)
    local asKB    = plausible(sum * 1024, totalBytes)
    if asBytes and not asKB then divide = true
    elseif asKB and not asBytes then divide = false
    elseif asBytes and asKB then

      divide = true
    else

      return nil
    end
  else

    divide = (sum >= 4096)
  end

  local sticks = {}
  for _, c in ipairs(raws) do
    sticks[#sticks + 1] = divide and math.floor(c / 1024) or math.floor(c)
  end
  table.sort(sticks, function(a, b) return a > b end)
  return sticks
end

function hal.ramSummary(sticks, totalKB, modules)
  if sticks == nil then sticks = hal.ramSticks() end
  if type(sticks) == "table" and #sticks > 0 then

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

  if totalKB == nil then
    local okT, t = pcall(function() return computer.totalMemory() end)
    if okT and tonumber(t) then totalKB = math.floor(tonumber(t) / 1024) end
  end
  totalKB = math.floor(tonumber(totalKB) or 0)
  modules = tonumber(modules) or 0
  if totalKB <= 0 then return "?" end
  if modules == 1 then return hal.stickTier(totalKB) or (totalKB .. "K") end
  if modules > 1 then return modules .. " sticks, " .. totalKB .. "K" end
  return totalKB .. "K"
end

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
  if totalMem >= 786432 then return 3
  elseif totalMem >= 262144 then return 2
  else return 1 end
end

local function detectHDDTier(proxy)
  local ok, total = pcall(proxy.spaceTotal)
  if not ok or not total then return 1 end
  if total >= 4194304 then return 3
  elseif total >= 2097152 then return 2
  else return 1 end
end

function hal.scan()
  components = {}

  for addr, ctype in component.list() do
    local entry = {
      address = addr,
      type    = ctype,
      proxy   = nil,
      tier    = nil,
      label   = nil,
    }

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

  components["_cpu_tier"] = detectCPUTier()
  components["_mem_tier"] = detectMemoryTier()
end

function hal.list(ctype)
  return components[ctype] or {}
end

function hal.primary(ctype)
  local list = components[ctype]
  if list and #list > 0 then
    local entry = list[1]

    if not entry.proxy then
      local ok, proxy = pcall(component.proxy, entry.address)
      if ok then entry.proxy = proxy end
    end
    return entry
  end
  return nil
end

function hal.proxy(ctype)
  local entry = hal.primary(ctype)
  return entry and entry.proxy
end

function hal.count(ctype)
  local list = components[ctype]
  return list and #list or 0
end

function hal.has(ctype)
  return hal.count(ctype) > 0
end

function hal.systemInfo()
  local gpuEntry = hal.primary("gpu")
  return {
    cpuTier    = components["_cpu_tier"] or 1,
    memTier    = components["_mem_tier"] or 1,

    memTierName = hal.ramSummary(),
    gpuTier    = gpuEntry and gpuEntry.tier or 0,
    totalMem   = computer.totalMemory(),
    freeMem    = computer.freeMemory(),
    components = hal.componentCount(),

    canEncrypt   = computer.totalMemory() >= 262144,
    canMultiUser = computer.totalMemory() >= 196608,
    canNetwork   = hal.has("modem"),
    hasTunnel    = hal.has("tunnel"),
    hasWireless  = false,
    hasScreen    = hal.has("screen"),
    hasKeyboard  = hal.has("keyboard"),
    isHeadless   = not hal.has("gpu") and not hal.has("screen"),
  }
end

function hal.freeMemory(need)
  local function read()
    return (computer.freeMemory and computer.freeMemory()) or 0
  end
  local free = read()
  if need and free >= need then return free, false end

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

function hal.checkWireless()
  local modem = hal.primary("modem")
  if modem and modem.proxy then

    local ok, wireless = pcall(function()
      return modem.proxy.isWireless()
    end)
    if ok then
      return wireless
    end
  end
  return false
end

function hal.handleComponentAdded(addr, ctype)
  if not components[ctype] then components[ctype] = {} end

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
