local sysinfo = {}

local halMod = nil
local function hal()
  if halMod == nil then
    local ok, m = pcall(require, "kernel.hal")
    halMod = (ok and m) or false
  end
  return halMod or nil
end

function sysinfo.stickTier(perStickKB)
  local h = hal()
  return h and h.stickTier and h.stickTier(perStickKB) or nil
end

function sysinfo.ramSummary(totalKB, modules, sticks)
  local h = hal()
  if not (h and h.ramSummary) then return tostring(math.floor(totalKB or 0)) .. "K" end
  return h.ramSummary(sticks, totalKB, modules)
end

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

local function screenTier(w, h)
  w, h = w or 0, h or 0
  if w >= 160 or h >= 50 then return 3 end
  if w >= 80  or h >= 25 then return 2 end
  return 1
end

local function diskTier(totalKB)
  if totalKB <= 600  then return "Floppy" end
  if totalKB <= 1100 then return "T1" end
  if totalKB <= 2200 then return "T2" end
  return "T3"
end

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

  local okD, dc = pcall(require, "kernel.datacard")
  if okD and dc and dc.capsOf then
    local tier = dc.tierOf(dc.capsOf(p, addr))
    if tier >= 1 then return tier, DATA_TIER_NAMES[tier], "detected" end
    return 0, "present (unknown tier)", "unknown"
  end

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

  if type(ramKB) == "number" and ramKB > 0 then
    if ramKB >= 768 then return 3, "estimated"
    elseif ramKB >= 256 then return 2, "estimated"
    else return 1, "estimated" end
  end
  return nil, "unknown"
end
sysinfo._detectCpuTier = detectCpuTier

function sysinfo.benchmarkCallBudget(computer)
  computer = computer or require("computer")
  local t0 = computer.uptime()
  local n = 0
  while computer.uptime() == t0 and n < 1e7 do n = n + 1 end
  local tier = (n > 2.5e5) and 3 or (n > 1.0e5) and 2 or 1
  return n, tier
end

function sysinfo.gather(deps, overrides, onProgress)
  deps = deps or {}
  overrides = overrides or {}
  onProgress = onProgress or function() end
  local component = deps.component or require("component")
  local computer  = deps.computer  or require("computer")

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

  onProgress("Detecting processor and memory")
  local arch = "Lua 5.3"
  pcall(function()
    if computer.getArchitecture then arch = computer.getArchitecture() end
  end)
  inv.cpu.arch = arch

  local total = (computer.totalMemory and computer.totalMemory()) or 0
  local free  = (computer.freeMemory  and computer.freeMemory())  or 0
  inv.memory.totalKB = math.floor(total / 1024)
  inv.memory.freeKB  = math.floor(free / 1024)
  inv.memory.tier    = memTier(inv.memory.totalKB)

  inv.memory.modules = 0
  for _ in component.list("memory") do inv.memory.modules = inv.memory.modules + 1 end

  local h = hal()
  inv.memory.sticks  = h and h.ramSticks and h.ramSticks(deviceInfo) or nil
  inv.memory.summary = sysinfo.ramSummary(inv.memory.totalKB, inv.memory.modules,
                                          inv.memory.sticks)

  inv.cpu.count = 0
  for _ in component.list("cpu") do inv.cpu.count = inv.cpu.count + 1 end

  inv.cpu.tier, inv.cpu.tierSource =
    detectCpuTier(deviceInfo, overrides, inv.memory.totalKB)

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

  local screenCount = 0
  for _ in component.list("screen") do screenCount = screenCount + 1 end
  inv.screen = { count = screenCount, tier = screenTier(bestW, bestH) }

  onProgress("Detecting storage")

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

  for addr in component.list("data") do
    pcall(function()
      local p = component.proxy(addr)
      local tier, name, source = dataCardTier(p, overrides, addr)
      inv.dataCard = { present = true, addr = addr:sub(1, 8),
                       tier = tier, name = name, tierSource = source }
    end)
    break
  end

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

  local KNOWN = {
    gpu = true, screen = true, filesystem = true, modem = true,
    tunnel = true, data = true, eeprom = true, keyboard = true,
    internet = true,
  }
  local counts = {}
  for addr, ctype in component.list() do
    if not KNOWN[ctype] then counts[ctype] = (counts[ctype] or 0) + 1 end
  end
  for t, n in pairs(counts) do inv.other[#inv.other + 1] = { type = t, count = n } end
  table.sort(inv.other, function(a, b) return a.type < b.type end)

  return inv
end

function sysinfo.rows(inv)
  local r = {}
  local function add(label, value, role)
    r[#r + 1] = { label = label, value = value, role = role or "value" }
  end
  local function section(name) r[#r + 1] = { label = "", value = name, role = "section" } end

  section("System")
  do
    local s = inv.cpu.tierSource
    local tierStr, role
    if not inv.cpu.tier then
      tierStr, role = "  [Tier ? - set in boot settings]", "warn"
    elseif s == "override" then
      tierStr, role = "  [Tier " .. inv.cpu.tier .. "*]", "value"
    elseif s == "estimated" then
      tierStr, role = "  [~Tier " .. inv.cpu.tier .. " est - confirm in settings]", "warn"
    else
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
      label = label .. "*"
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

function sysinfo.diskRole(d, isBoot, state)
  state = state or {}
  if isBoot then return "Boot Drive" end
  if d.tape then return "Tape Drive" end
  if d.unmanaged then return "Raw Drive" end
  if d.tmpfs or d.label == "tmpfs" then return "Temp /tmp" end
  if d.tier == "Floppy" or (d.totalKB or 0) <= 600 then
    state.floppy = (state.floppy or 0) + 1
    return "Floppy " .. string.char(64 + math.min(state.floppy, 26))
  end
  state.data = (state.data or 0) + 1
  return "Data Drive " .. state.data
end

function sysinfo.render(inv, ctx)
  local W, H = ctx.W or 50, ctx.H or 16
  local set  = ctx.set
  local col  = ctx.color or function() return 0xFFFFFF end
  local bg   = col("bg")

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

  local ramLabel, ramVal
  if (mem.modules or 0) > 0 then
    ramLabel, ramVal = "RAM Modules", tostring(mem.modules)
  else
    ramLabel, ramVal = "Memory Tier", (mem.tier or "?") .. "  (est)"
  end

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
  if wide then
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
  else
    put(2, 1, ctx.title or "TOS System Configuration", "title")
    rule(2)
    y = 4
    for _, e in ipairs(LEFT)  do kv(2, y, e[1], e[2], 13); y = y + 1 end
    for _, e in ipairs(RIGHT) do kv(2, y, e[1], e[2], 13); y = y + 1 end
    rule(y); y = y + 1
    put(2, y, "Storage", "title"); y = y + 1
  end

  if wide then
    walls(y)
    put(4, y, string.format("%-12s %-10s %-13s %-6s %s",
      "Role", "Label", "Used/Size", "Tier", "Boot"), "dim")
    y = y + 1
  end
  local bootAddr = inv.eeprom and inv.eeprom.bootAddr
  local disks = {}
  for _, d in ipairs(inv.disks or {}) do disks[#disks + 1] = d end
  table.sort(disks, function(a, b)
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

  put(2, y, string.format("Memory %d/%dKB free    Display GPU T%d  %dx%d",
    free, total, gpu.tier or 1, gpu.maxW or 0, gpu.maxH or 0), "ok")
  y = y + 1
  return y
end

return sysinfo
