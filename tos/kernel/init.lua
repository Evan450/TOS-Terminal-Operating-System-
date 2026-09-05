local computer = require("computer")
local component = require("component")

local kernel = {}

local running = false
local shuttingDown = false

local log, hal, event, proc, fs, display

local monitorHosts = {}

function kernel.boot(opts)
  opts = opts or {}
  local earlyPrint = opts.earlyPrint or function() end

  local _earlyMinLevel = opts.earlyMinLevel or 1
  local function bootEcho(text, color)
    if _earlyMinLevel <= 1 then earlyPrint(text, color) end
  end

  local bootCfg    = opts.bootcfg
  local bootcfgMod = opts.bootcfgMod
  local function wants(feature, ramOK)
    if bootcfgMod and bootCfg and bootcfgMod.wants then
      return bootcfgMod.wants(bootCfg, feature, ramOK)
    end
    return ramOK
  end

  local MIN_FREE_FOR_OPTIONAL = 40960

  local function ramOK()

    local free = (hal and hal.freeMemory and hal.freeMemory(MIN_FREE_FOR_OPTIONAL))
      or computer.freeMemory()
    local detected = free > MIN_FREE_FOR_OPTIONAL
    if bootcfgMod and bootCfg and bootcfgMod.ramOK then
      return bootcfgMod.ramOK(bootCfg, detected)
    end
    return detected
  end

  bootEcho("  Loading kernel modules...", 0xAAAAAA)
  log = require("kernel.log")

  log.init({ earlyPrint = earlyPrint, earlyMinLevel = opts.earlyMinLevel,
    bootProgress = opts.bootProgress })
  log.info("kernel", "TOS Kernel v" .. _G._TOS.version .. " starting")

  _G._TOS.log    = function(src, msg) log.info(src, msg) end
  _G._TOS.logObj = log

  log.info("kernel", "Scanning hardware...")
  hal = require("kernel.hal")
  hal.scan()

  local info = hal.systemInfo()
  log.info("kernel", string.format("CPU T%d | GPU T%d | RAM %s | %d components",
    info.cpuTier, info.gpuTier,
    info.memTierName or ("T" .. info.memTier), info.components))

  if info.canNetwork then
    local wl = hal.checkWireless()
    info.hasWireless = wl
    log.info("kernel", "Network: " .. (wl and "Wireless" or "Wired") .. " modem detected")
  end
  if info.hasTunnel then
    log.info("kernel", "Linked card (tunnel) detected")
  end

  log.info("kernel", "Initializing filesystem...")
  fs = require("kernel.fs")
  fs.init(opts.bootFS)

  local function sanitizeLabel(raw, addr)
    local fallback = "disk_" .. addr:sub(1, 4)
    if type(raw) ~= "string" then return fallback end

    local cleaned = raw:gsub("[^%w_%- ]", "_")

    cleaned = cleaned:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then return fallback end

    if #cleaned > 32 then cleaned = cleaned:sub(1, 32) end

    if cleaned == "." or cleaned == ".." then return fallback end
    return cleaned
  end

  local fsList = hal.list("filesystem")
  local bootAddr = opts.bootFS and opts.bootFS.address
  local usedMountPoints = {}
  for _, entry in ipairs(fsList) do
    if entry.address ~= bootAddr then
      local rawLabel
      if entry.proxy then

        local okL, lbl = pcall(entry.proxy.getLabel)
        if okL then rawLabel = lbl end
      end
      local label = sanitizeLabel(rawLabel, entry.address)
      local mountPoint = "/mnt/" .. label

      if usedMountPoints[mountPoint] then
        mountPoint = mountPoint .. "_" .. entry.address:sub(1, 4)
      end
      usedMountPoints[mountPoint] = true
      if not entry.proxy then
        entry.proxy = component.proxy(entry.address)
      end
      fs.mount(mountPoint, entry.proxy)
      log.info("kernel", "Mounted " .. entry.address:sub(1, 8) .. " at " .. mountPoint)
    end
  end

  local coreDirs = {
    "/tmp", "/var", "/var/log", "/var/run", "/var/pkg", "/var/pkg/installed",
    "/var/swap", "/etc", "/usr", "/usr/bin", "/usr/modules",
  }
  for _, dir in ipairs(coreDirs) do
    if not fs.exists(dir) then
      fs.makeDirectory(dir)
    end
  end

  pcall(log.attachFile, fs, "/var/log/kernel.log", { rotateBytes = 16384 })

  local PWRSTATE = "/var/run/pwrstate"
  do
    local prev = fs.exists(PWRSTATE) and fs.readFile(PWRSTATE) or nil
    local boots = 0
    if type(prev) == "string" and #prev > 0 then
      boots = tonumber(prev:match("\n(%d+)")) or 0

      _G._TOS.unsafeShutdown = prev:sub(1, 1) ~= "C"
    else

      _G._TOS.unsafeShutdown = false
    end
    _G._TOS.bootCount = boots + 1

    if fs.recoverAtomic then
      local rec = fs.recoverAtomic({
        "/etc/users.dat", "/etc/trust.dat", "/etc/tos.cfg",
        "/etc/cron.db", "/etc/critical.bak",
      })
      if rec > 0 then
        log.warn("kernel", "Recovered " .. rec ..
          " interrupted critical write(s) from a prior crash")
      end
    end

    pcall(fs.writeFile, PWRSTATE,
      "R\n" .. _G._TOS.bootCount .. "\n" .. tostring((os.time and os.time()) or 0))

    if _G._TOS.unsafeShutdown then
      log.warn("kernel",
        "PREVIOUS SHUTDOWN WAS UNSAFE (power loss / forced off) — state verified on boot")
      pcall(computer.beep, 880, 0.1); pcall(computer.beep, 660, 0.1)
    end
  end

  pcall(function()
    local addr = component.list("eeprom")()
    if not addr then return end
    local ep = component.proxy(addr)
    if not (ep and ep.getData) then return end
    local data = ep.getData()
    if type(data) ~= "string" or not data:find("SRM:", 1, true) then return end
    local okS, srmMod = pcall(require, "kernel.srm")
    if not (okS and srmMod) then
      log.warn("srm", "A POST fault is parked in the EEPROM but kernel.srm "
        .. "would not load: " .. tostring(srmMod))
      return
    end
    local fault = srmMod.readFault({ eeprom = ep })
    if not fault then return end
    log.error("srm", "LAST BOOT FAILED POST — SRM " .. fault.code .. ": " .. fault.why)
    bootEcho("  SRM " .. fault.code .. ": last boot failed POST", 0xFF6600)
    bootEcho("    " .. fault.why, 0xFFAA00)
    bootEcho("    (run 'srm' for the full report)", 0xAAAAAA)
    local okC, errC = srmMod.clearFault({ eeprom = ep })
    if not okC then log.warn("srm", "could not clear the parked code: " .. tostring(errC)) end
  end)

  local diskFree = math.floor(fs.spaceFree("/") / 1024)
  local diskTotal = math.floor(fs.spaceTotal("/") / 1024)
  log.info("kernel", string.format("Boot disk: %dKB free / %dKB total", diskFree, diskTotal))
  if diskFree < 32 then
    log.warn("kernel", "WARNING: Very low disk space!")
  end

  if bootCfg and bootCfg.repair then
    log.warn("kernel", "SELF-REPAIR requested — checking system state...")
    bootCfg.repair = false
    pcall(function()
      if bootcfgMod and bootcfgMod.save then bootcfgMod.save(fs, bootCfg) end
    end)

    local deps = { fs = fs, log = log,
      serialize = (function() local o, m = pcall(require, "kernel.serialize"); return o and m or nil end)() }
    local findings, fixed, warned = nil, 0, 0

    local okS, srmMod = pcall(require, "kernel.srm")
    if okS and type(srmMod) == "table" then
      local ok2, rep = pcall(srmMod.repair, deps)
      if ok2 and type(rep) == "table" then
        findings = rep.findings
        fixed    = rep.fixed or 0
        warned   = (rep.counts.warn or 0) + (rep.counts.err or 0)
      else
        log.warn("repair", "self-repair failed: " .. tostring(rep))
      end
    else

      log.warn("repair", "kernel.srm unavailable (" .. tostring(srmMod)
        .. ") — falling back to kernel.repair")
      local okR, repairMod = pcall(require, "kernel.repair")
      if okR and repairMod then
        local ok2, rep = pcall(repairMod.run, deps)
        if ok2 and type(rep) == "table" then
          findings = {}
          for _, line in ipairs(rep.lines or {}) do
            findings[#findings + 1] = { text = line,
              sev = line:sub(1, 5) == "WARN:" and "warn" or "info" }
          end
          fixed, warned = rep.fixed or 0, rep.warned or 0
        else
          log.warn("repair", "self-repair failed: " .. tostring(rep))
        end
      else
        log.warn("repair", "kernel.repair unavailable: " .. tostring(repairMod))
      end
    end

    if findings then

      local SEV = { ok = 0x00FF00, info = 0xAAAAAA, warn = 0xFFAA00, err = 0xFF6600 }
      for _, f in ipairs(findings) do
        log.info("repair", f.text)
        bootEcho("  " .. f.text, SEV[f.sev] or 0xAAAAAA)
      end
      local sum = string.format("Self-repair: %d fixed, %d warning(s)", fixed, warned)
      log.warn("repair", sum)
      bootEcho("  " .. sum, warned > 0 and 0xFFAA00 or 0x00FF00)
    end
  end

  local sysconfig = nil
  do
    log.info("kernel", "Loading configuration...")
    local ok, mod = pcall(require, "kernel.config")
    if ok then
      sysconfig = mod
      sysconfig.init(fs)
      _G._TOS.config = sysconfig
      log.info("kernel", "Device profile: " .. sysconfig.deviceType())
      if sysconfig.get("verbose") then
        log.setLevel("DEBUG")
      end
    else
      log.warn("kernel", "Config module not available: " .. tostring(mod))
    end
  end

  if wants("swap", true) then

    local czMod
    do
      local okZ, mod = pcall(require, "kernel.compress")
      if okZ and mod then
        pcall(mod.init, { log = log })
        _G._TOS.compress = mod
        czMod = mod
      end
    end
    local okS, swapMod = pcall(require, "kernel.swap")
    if okS and swapMod then
      local iok, ierr = pcall(swapMod.init, {
        fs = fs, serialize = require("kernel.serialize"),
        log = log, config = sysconfig, compress = czMod,
      })
      if iok then
        _G._TOS.swap = swapMod
      else
        log.warn("kernel", "Swap init failed: " .. tostring(ierr))
      end
    else
      log.warn("kernel", "Swap module not available: " .. tostring(swapMod))
    end
  end

  do
    local okI, inetMod = pcall(require, "kernel.internet")
    if okI and inetMod then
      pcall(inetMod.init, { log = log, config = sysconfig })
      _G._TOS.internet = inetMod
    end
  end

  if wants("jbod", false) then
    local okJ, jbodMod = pcall(require, "kernel.jbod")
    if okJ and jbodMod then
      _G._TOS.jbod = jbodMod
      log.info("kernel", "JBOD disk pooling enabled")

      local cfg = jbodMod.loadConfig(fs)
      if cfg and type(cfg.pools) == "table" then
        for _, p in ipairs(cfg.pools) do
          if type(p) == "table" and type(p.mount) == "string"
             and type(p.members) == "table" then
            local members = {}
            for _, addr in ipairs(p.members) do
              local ok2, px = pcall(component.proxy, addr)
              if ok2 and px then members[#members + 1] = px end
            end
            if #members == 0 then
              log.warn("kernel", "JBOD pool " .. p.mount ..
                ": no members present, not mounted")
            else
              local proxy = jbodMod.makePool(members)
              local mok, merr = fs.mount(p.mount, proxy)
              if mok then
                log.info("kernel", string.format(
                  "JBOD mounted %s (%d/%d members)",
                  p.mount, #members, #p.members))
              else
                log.warn("kernel", "JBOD mount " .. p.mount ..
                  " failed: " .. tostring(merr))
              end
            end
          end
        end
      end
    else
      log.warn("kernel", "JBOD enabled but module unavailable: " .. tostring(jbodMod))
    end
  end

  log.info("kernel", "Starting event system...")
  event = require("kernel.event")

  local SEAT_COMPONENT_TYPES = { screen = true, gpu = true, keyboard = true }

  event.on("component_added", function(_, addr, ctype)
    hal.handleComponentAdded(addr, ctype)
    log.info("hotplug", "Added: " .. ctype .. " [" .. addr:sub(1, 8) .. "]")
    if SEAT_COMPONENT_TYPES[ctype] then
      event.push("tos_seat_changed", "added", ctype, addr)
    end
  end, "kernel")

  event.on("component_removed", function(_, addr, ctype)
    hal.handleComponentRemoved(addr, ctype)
    log.info("hotplug", "Removed: " .. ctype .. " [" .. addr:sub(1, 8) .. "]")
    if SEAT_COMPONENT_TYPES[ctype] then
      event.push("tos_seat_changed", "removed", ctype, addr)
    end
  end, "kernel")

  event.on("screen_resized", function(_, addr, w, h)
    local okS, screenMod = pcall(require, "kernel.screen")
    if not (okS and screenMod and screenMod.onResized) then return end
    if screenMod.onResized(addr, w, h) then
      local nw, nh = screenMod.getResolution()
      log.info("screen", string.format("Screen resized externally -> %dx%d", nw or 0, nh or 0))
    end
  end, "kernel")

  log.info("kernel", "Starting process manager...")
  proc = require("kernel.process")

  local isHeadless = sysconfig and sysconfig.isHeadless()
  if isHeadless then
    log.info("kernel", "Headless mode — skipping display init")

    display = {
      init = function() end, clear = function() end,
      fill = function() end, set = function() end,
      getSize = function() return 0, 0 end,
      getGpuTier = function() return 0 end,
      getGpuDepth = function() return 1 end,
      getTheme = function()
        return setmetatable({}, { __index = function() return 0xFFFFFF end })
      end,
      getGpu = function() return nil end,
      fit = function(s) return s or "" end,
      c = function() return 0xFFFFFF end,
    }
  else
    log.info("kernel", "Initializing display...")
    display = require("kernel.display")

    local targetW, targetH, resNote = opts.screenW, opts.screenH
    do
      local okSc, screenMod = pcall(require, "kernel.screen")
      if okSc and screenMod and screenMod.specFromConfig then
        local spec = screenMod.specFromConfig(sysconfig)
        screenMod.setPolicy(spec)
        local tw, th, note = screenMod.gpuTarget(opts.gpu, nil, spec)
        if tw and th then targetW, targetH = tw, th end
        resNote = note
      end
    end
    display.init(opts.gpu, targetW, targetH)
    local dW, dH = display.getSize()
    log.info("kernel", string.format("Display: %dx%d, GPU Tier %d (%d-bit color)",
      dW or 0, dH or 0, display.getGpuTier(), display.getGpuDepth()))
    if resNote then log.warn("screen", resNote) end
  end

  do
    if wants("power", ramOK()) then
      local ok, powerMod = pcall(require, "kernel.power")
      if ok then
        powerMod.init({ log = log, config = sysconfig })
        _G._TOS.power = powerMod
        if sysconfig and sysconfig.isTablet() then
          event.interval(10, function() powerMod.check() end, "kernel:power")
          powerMod.onLow(function(level)
            if _G._TOS.audio then _G._TOS.audio.warning() else computer.beep(800, 0.3) end
          end)
          powerMod.onCritical(function(level)
            if _G._TOS.audio then _G._TOS.audio.critical() else computer.beep(400, 0.5) end
            log.fatal("power", "Battery critical!")

            if not sysconfig or sysconfig.get("critBatShutdown") ~= false then
              log.warn("power", "Critical battery — clean shutdown to protect data")
              pcall(log.flush)
              kernel.shutdown(false)
            end
          end)
          log.info("kernel", "Tablet mode: battery monitoring active")
        end
      else
        log.warn("kernel", "Power module not available: " .. tostring(powerMod))
      end
    else

      log.warn("kernel", ramOK()
        and "Skipping power module (boot profile)"
        or ("Skipping power module (low memory: " ..
            math.floor(computer.freeMemory() / 1024) .. "KB free)"))
    end
  end

  local function lazySlot(slot, modname, makeDeps)
    local resolved, warned = nil, false
    _G._TOS[slot] = setmetatable({}, {
      __index = function(_, key)
        if resolved then return resolved[key] end
        local okL, mod = pcall(require, modname)
        if not okL or type(mod) ~= "table" then
          if not warned then
            warned = true
            log.warn("kernel", slot .. ": lazy load failed: " .. tostring(mod))
          end
          return nil
        end
        if mod.init and makeDeps then pcall(mod.init, makeDeps()) end
        resolved = mod
        _G._TOS[slot] = mod
        log.info("kernel", slot .. " module ready (on demand)")
        return mod[key]
      end,
    })
  end

  do
    if computer.freeMemory() > MIN_FREE_FOR_OPTIONAL then
      local ok1, crypto = pcall(require, "kernel.crypto")
      if ok1 then
        crypto.init()
        log.info("kernel", "Crypto: " .. (crypto.hasHardware() and "Hardware" or "Software"))

        pcall(function()
          if not (crypto.addEntropy and crypto.exportEntropy and fs) then return end
          local EPATH = "/etc/entropy"
          if fs.makeDirectory and not fs.exists("/etc") then fs.makeDirectory("/etc") end
          if fs.exists(EPATH) then
            local blob = fs.readFile(EPATH)
            if type(blob) == "string" and #blob > 0 then crypto.addEntropy(blob) end
          end

          crypto.addEntropy(tostring(computer.uptime()) .. "|" ..
            tostring(computer.freeMemory()) .. "|" .. tostring({}))
          fs.writeFile(EPATH, crypto.exportEntropy(64))
        end)

        local ok2, usersmod = pcall(require, "kernel.users")
        if ok2 then
          usersmod.init({ fs = fs, crypto = crypto, log = log, config = sysconfig })
          _G._TOS.users = usersmod

          local ok3, securefs = pcall(require, "kernel.securefs")
          if ok3 then
            securefs.init({ fs = fs, users = usersmod, log = log, process = proc })
            _G._TOS.securefs = securefs

            _G._TOS.bootSession = usersmod.kernelSession()
            log.info("kernel", "Security: users + securefs ready")

            lazySlot("trash", "kernel.trash")

            local okP, profileMod = pcall(require, "kernel.profile")
            if okP and profileMod and profileMod.init then
              profileMod.init({
                securefs  = securefs,
                users     = usersmod,
                log       = log,
                serialize = require("kernel.serialize"),
              })
              _G._TOS.profile = profileMod
              log.info("kernel", "Profile module ready")
            end

            local okI18n, i18nMod = pcall(require, "kernel.i18n")
            if okI18n and i18nMod and i18nMod.init then
              i18nMod.init({
                fs        = fs,
                log       = log,
                serialize = require("kernel.serialize"),
                config    = _G._TOS.config,
              })
              _G._TOS.i18n = i18nMod
              if i18nMod.language() ~= "en" then
                log.info("kernel", "Language: " .. i18nMod.language())
              end
            end

            lazySlot("backup", "kernel.backup", function()
              return {
                securefs = securefs,
                fs       = fs,
                crypto   = crypto,
                log      = log,
              }
            end)

            lazySlot("keychain", "kernel.keychain", function()
              return {
                securefs  = securefs,
                users     = usersmod,
                log       = log,
                serialize = require("kernel.serialize"),
              }
            end)

            if event then
              event.interval(300, function() usersmod.sweepSessions() end, "kernel:session_sweep")
            end
          else
            log.warn("kernel", "SecureFS not available: " .. tostring(securefs))
          end
        else
          log.warn("kernel", "User system not available: " .. tostring(usersmod))
        end
      else
        log.warn("kernel", "Crypto not available: " .. tostring(crypto))
      end
    else
      log.warn("kernel", "Skipping security (low memory: " ..
        math.floor(computer.freeMemory() / 1024) .. "KB free)")
    end
  end

  if display and display.isMonochrome and not display.isMonochrome()
     and wants("theme", ramOK()) then
    local okT, themeMod = pcall(require, "kernel.theme")
    if okT then
      themeMod.init({
        display  = display,
        securefs = _G._TOS.securefs,
        log      = log,
      })
      _G._TOS.theme = themeMod
      log.info("kernel", "Theme manager ready (" .. #themeMod.list() .. " presets)")
    else
      log.warn("kernel", "Theme module not available: " .. tostring(themeMod))
    end
  end

  if (hal.has("modem") or hal.has("tunnel"))
     and wants("net", ramOK()) then
    local ok, netMod = pcall(require, "kernel.net")
    if ok then
      local initOk = pcall(netMod.init, {
        log    = log,
        config = sysconfig,
        event  = event,
        fs     = fs,
      })
      if initOk then
        _G._TOS.net = netMod
        log.info("kernel", "Network ready (" .. (netMod.getHostname()) .. ")")

        local okAl, aliasesMod = pcall(require, "kernel.net.aliases")
        if okAl and aliasesMod and aliasesMod.init then
          aliasesMod.init({
            fs        = fs,
            securefs  = securefs,
            users     = usersmod,
            log       = log,
            serialize = require("kernel.serialize"),
          })
          _G._TOS.net.aliases = aliasesMod
          log.info("kernel", "Peer aliases ready")
        end

      else
        log.warn("kernel", "Network init failed")
      end
    else
      log.warn("kernel", "Network module not available: " .. tostring(netMod))
    end
  else
    if not (hal.has("modem") or hal.has("tunnel")) then
      log.info("kernel", "No network hardware - skipping")
    elseif ramOK() then

      log.warn("kernel", "Skipping network (boot profile)")
    else
      log.warn("kernel", "Skipping network (low memory: " ..
        math.floor(computer.freeMemory() / 1024) .. "KB free)")
    end
  end

  if wants("services", ramOK()) then
    local ok, rcMod = pcall(require, "kernel.rc")
    if ok then
      rcMod.init({ fs = fs, log = log, proc = proc })
      rcMod.runAll()
      _G._TOS.rc = rcMod
      log.info("kernel", "Startup services loaded")

      if event then
        event.interval(30, function() rcMod.supervise() end, "kernel:rc_supervise")
      end
    end
  else
    log.warn("kernel", "Startup services skipped (boot profile)")
  end

  if wants("cron", ramOK()) then
    if fs.exists("/etc/cron.dat") then
      local ok, cronMod = pcall(require, "kernel.cron")
      if ok then
        cronMod.init({ fs = fs, log = log, event = event })
        _G._TOS.cron = cronMod
        log.info("kernel", "Cron scheduler initialized")
      end
    else

      lazySlot("cron", "kernel.cron")
    end
  else

    _G._TOS.cronDisabled = true
    log.warn("kernel", "Cron scheduler skipped (boot profile)")
  end

  do

    if not wants("packages", true) then
      _G._TOS.pkgDispatchDisabled = true
      log.warn("kernel", "Package command dispatch disabled (boot profile)")
    end

    lazySlot("pkg", "kernel.pkg")
  end

  if event then
    event.interval(30, function() pcall(log.flush) end, "kernel:log_flush")
  end

  if not wants("compat", true) then
    _G._TOS.compatDisabled = true
    log.warn("kernel", "OpenOS compat disabled (boot profile)")
  else
    log.info("kernel", "OpenOS compat: lazy (loads on first use)")
  end

  if wants("audio", true) then
    local ok, audioMod = pcall(require, "kernel.audio")
    if ok then
      audioMod.init(sysconfig)
      _G._TOS.audio = audioMod
      log.info("kernel", "Audio feedback: " .. (audioMod.isEnabled() and "enabled" or "disabled"))
    else
      log.info("kernel", "Audio module not available")
    end
  end

  function kernel.gc()
    if type(collectgarbage) == "function" then return pcall(collectgarbage, "collect") end
    return false
  end
  _G._TOS.fs     = fs
  _G._TOS.kernel = kernel

  _G._TOS.proc   = proc
  _G._TOS.event  = event

  if type(collectgarbage) == "function" then
    pcall(collectgarbage, "setpause", 120)
  end

  local freeNow = (hal and hal.freeMemory and hal.freeMemory()) or computer.freeMemory()
  local bootDuration = computer.uptime() - _G._TOS.bootTime
  log.info("kernel", "Boot complete! Free memory: " ..
    math.floor(freeNow / 1024) .. "KB")
  log.info("kernel", string.format("Boot time: %.1fs", bootDuration))

  pcall(kernel.checkLastCrash)

  if freeNow < 20480 then
    log.warn("kernel", "LOW MEMORY: " .. math.floor(freeNow / 1024) .. "KB free!")
  end

  bootEcho(string.format("  Boot complete: %.1fs, %dK free",
    bootDuration, math.floor(freeNow / 1024)), 0x00FF00)

  if _G._TOS.audio then _G._TOS.audio.bootComplete() end

  do
    local okS, st = pcall(function()
      local fsMod = _G._TOS and _G._TOS.fs
      if not (fsMod and fsMod.exists) then return nil end

      local armed = fsMod.exists("/etc/selftest.on")
      if not armed and fsMod.mounts then
        local okM, list = pcall(fsMod.mounts)
        if okM and type(list) == "table" then
          for _, m in ipairs(list) do
            local mp = m.mountPoint
            if mp and mp ~= "/" and (fsMod.exists(mp .. "/selftest.on")
               or fsMod.exists(mp .. "/selftest/selftest.on")) then
              armed = true; break
            end
          end
        end
      end
      if not armed then return nil end
      return require("kernel.selftest")
    end)
    if okS and st then
      log.info("kernel", "selftest marker present - running boot battery")
      bootEcho("  Running self-test battery...", 0xFFFF00)
      pcall(st.init, { fs = _G._TOS.fs, computer = computer, log = log })
      local okR, res = pcall(st.run, { fs = _G._TOS.fs, computer = computer })
      if okR and res then
        bootEcho(string.format("  Self-test: %d passed, %d failed, %d skipped",
          res.pass, res.fail, res.skip), res.fail > 0 and 0xFF0000 or 0x00FF00)
      else
        log.error("kernel", "selftest battery errored: " .. tostring(res))
        bootEcho("  Self-test ERRORED (see /var/selftest.log)", 0xFF0000)
      end
    end
  end

  if not isHeadless then

    local bootPause = 0
    if sysconfig then
      bootPause = tonumber(sysconfig.get("bootPause")) or
                  (sysconfig.get("verbose") and 1.5 or 0)
    end
    if bootPause > 0 then computer.pullSignal(bootPause) end
  end

  log.detachEarlyPrint()

  kernel.boot = nil

  if isHeadless then
    kernel.headlessMain()
  else
    kernel.loginAndStartShell()
  end
end

function kernel.loginAndStartShell()
  running = true

  local usersmod = _G._TOS.users
  local securefs = _G._TOS.securefs
  local freeMem = computer.freeMemory()

  local function forceGC()
    if type(collectgarbage) == "function" then pcall(collectgarbage, "collect") end
  end

  local function minimalAuth()
    local W, H = display.getSize()
    local T = display.getTheme()
    display.clear(T.bg)
    display.set(2, 2, "TOS - Authentication Required", T.title, T.bg)

    if not usersmod then

      display.set(2, 3, "User system unavailable (low memory).", T.error, T.bg)
      display.set(2, 4, "Cannot authenticate; rebooting with more RAM", T.dim, T.bg)
      display.set(2, 5, "should restore normal login.", T.dim, T.bg)
      if _G._TOS.audio then _G._TOS.audio.critical() else computer.beep(400, 0.5) end
      computer.pullSignal(5)
      kernel.reboot()
      return nil
    end

    display.set(2, 3, "Low memory mode. Enter root password.", T.dim, T.bg)
    display.set(2, 5, "Password: ", T.dim, T.bg)

    local LOCKOUT_PATH = "/var/lockout.dat"
    local function readLockout()
      local ok, pFs = pcall(require, "kernel.fs")
      local fs = (ok and pFs) or nil
      if not fs or not fs.exists or not fs.exists(LOCKOUT_PATH) then return 0 end
      local data = fs.readFile(LOCKOUT_PATH)
      local n = tonumber(data or "") or 0
      return n
    end
    local function writeLockout(t)
      local ok, pFs = pcall(require, "kernel.fs")
      local fs = (ok and pFs) or nil
      if not fs or not fs.writeFile then return end
      if fs.exists and not fs.exists("/var") and fs.makeDirectory then
        fs.makeDirectory("/var")
      end
      pcall(fs.writeFile, LOCKOUT_PATH, tostring(t))
    end

    local now = computer.uptime()
    local lockUntil = readLockout()

    if lockUntil > 0 and lockUntil > now and (lockUntil - now) < 3600 then
      local wait = lockUntil - now
      display.set(2, 4, string.format("Locked: wait %ds before retrying.", math.ceil(wait)),
        T.error, T.bg)
      local deadline = now + wait
      while computer.uptime() < deadline do
        computer.pullSignal(math.min(1, deadline - computer.uptime()))
      end
      display.fill(2, 4, W - 3, 1, " ", T.fg, T.bg)
    end

    local maxAttempts = 5
    for attempt = 1, maxAttempts do
      display.fill(12, 5, W - 13, 1, " ", T.fg, T.bg)
      local buf = ""
      while true do
        display.set(12, 5, string.rep("*", #buf) .. "_ ", T.fg, T.bg)
        local sig, _, ch, co = computer.pullSignal(0.5)
        if sig == "key_down" then
          if co == 28 then break
          elseif co == 14 then if #buf > 0 then buf = buf:sub(1, -2) end
          elseif ch and ch >= 32 and ch < 127 then buf = buf .. string.char(ch)
          end
        end
      end

      local token = usersmod.login("root", buf, { setCurrent = true })
      if token then

        writeLockout(0)
        display.set(2, 7, "Access granted.", T.success, T.bg)
        computer.pullSignal(0.5)
        return token
      end

      local backoff = 2 ^ attempt
      if log then
        log.warn("auth", string.format(
          "minimalAuth: bad root password (attempt %d/%d), backoff %ds",
          attempt, maxAttempts, backoff))
      end
      local remain = maxAttempts - attempt
      if remain > 0 then
        display.set(2, 7, string.format(
          "Wrong password. Wait %ds. (%d attempts left)", backoff, remain),
          T.error, T.bg)
        display.fill(12, 5, W - 13, 1, " ", T.fg, T.bg)
        local deadline = computer.uptime() + backoff
        while computer.uptime() < deadline do
          computer.pullSignal(math.min(1, deadline - computer.uptime()))
        end
        display.fill(2, 7, W - 3, 1, " ", T.fg, T.bg)
      end
    end

    writeLockout(computer.uptime() + 60)
    display.set(2, 7, "Too many attempts. Rebooting (locked 60s)...", T.error, T.bg)
    if _G._TOS.audio then _G._TOS.audio.critical() else computer.beep(400, 0.5) end
    computer.pullSignal(3)
    kernel.reboot()
    return nil
  end

  local loginScreen = nil
  local useMinimalAuth = false

  if freeMem < 32768 then
    log.warn("kernel", "Low memory - using minimal auth")
    useMinimalAuth = true
  else
    local ok, mod = pcall(require, "shell.login")
    if ok then
      loginScreen = mod
    else
      log.warn("kernel", "Login module not available: " .. tostring(mod))
      useMinimalAuth = true
    end
  end

  local shellModule = nil
  do

    local ok, mod = pcall(require, "shell.init")
    if ok then
      shellModule = mod
    else
      log.error("kernel", "Shell module failed: " .. tostring(mod))
    end
  end

  local screenMod = require("kernel.screen")
  local shellCaps = {
    ["fs.read"]   = true,
    ["fs.write"]  = true,
    ["compat.io"] = true,
    ["component"] = true,
    ["load"]      = true,
    ["net"]       = true,

    ["peripheral.redstone"]  = true,
    ["peripheral.robot"]     = true,
    ["peripheral.inventory"] = true,
    ["peripheral.tape"]      = true,
    ["peripheral.printer"]   = true,
    ["peripheral.modem"]     = true,
    ["peripheral.tractor"]   = true,
    ["peripheral.piston"]    = true,
    ["peripheral.hologram"]  = true,
  }

  local sessionTokens = {}
  local shellPIDs = {}

  local spawnShellForSeat

  local function spawnLoginProcess(dIdx)
    local dProxy = screenMod.displayProxy(dIdx)
    if not dProxy then return nil end

    local loginPrincipal = usersmod and usersmod.loginSession
                           and usersmod.loginSession(dIdx) or nil
    local loginPid = proc.spawn("login@" .. dIdx, function()
      local token = nil
      if useMinimalAuth then
        token = minimalAuth()
      elseif loginScreen then

        local ok, result, reason = pcall(loginScreen.run, {
          display = dProxy,
          event   = event,
          users   = usersmod,
          proc    = proc,
          log     = log,
        })
        if ok then
          if reason == "shutdown" then
            log.info("kernel", "Operator chose shutdown at the login screen (display " .. dIdx .. ")")
            if kernel and kernel.shutdown then kernel.shutdown() else computer.shutdown(false) end
            return
          end
          token = result
        else
          log.error("kernel", "Login error on display " .. dIdx .. ": " .. tostring(result))
          token = minimalAuth()
        end
      end
      if token then
        sessionTokens[dIdx] = token
        shellPIDs[dIdx] = spawnShellForSeat(dIdx, token)
        _G._TOS.shellPIDs = shellPIDs

      end
    end, {
      display   = dIdx,
      priority  = 2,
      source    = "kernel",
      principal = loginPrincipal,
    })

    if loginPid then pcall(proc.setForeground, loginPid, dIdx) end
    return loginPid
  end

  spawnShellForSeat = function(dIdx, token)
    local dProxy = screenMod.displayProxy(dIdx)
    if not dProxy or not shellModule then return nil end

    local shellSession = nil
    if token and usersmod then
      shellSession = usersmod.getSession(token)
    end
    if not shellSession then
      if log then
        log.error("kernel", "Refusing to spawn shell on display " ..
          tostring(dIdx) .. ": no valid session token")
      end
      return nil
    end
    local userName = shellSession.user or "?"

    if _G._TOS.theme and _G._TOS.theme.applyForUser then
      pcall(_G._TOS.theme.applyForUser, shellSession)
    end
    if _G._TOS.profile and _G._TOS.profile.load and _G._TOS.profile.apply then
      pcall(function()
        local p = _G._TOS.profile.load(shellSession)

        local startup = _G._TOS.profile.apply(p, { session = shellSession })
        shellSession.startupCommands = startup
      end)
    end

    local kernelCopy = setmetatable(
      {
        display = dProxy,
        displayIdx = dIdx,
        getDisplay = function() return dProxy end,
        getDisplayIdx = function() return dIdx end,
      },
      { __index = kernel }
    )

    log.info("kernel", "Seat " .. dIdx .. ": shell for " .. userName)

    local shellRunner = shellModule.run
    if userName == "kiosk" then
      local okK, kioskMod = pcall(require, "shell.kiosk")
      if okK and kioskMod and kioskMod.run then
        shellRunner = kioskMod.run
        log.info("kernel", "Seat " .. dIdx .. ": KIOSK mode")
      end
    end

    forceGC()
    log.info("kernel", string.format("Seat %d: loading shell (%dKB free)",
      dIdx, math.floor(computer.freeMemory() / 1024)))

    local pid = proc.spawn("shell:" .. userName .. "@" .. dIdx, function()
      local ok2, err2 = pcall(shellRunner, kernelCopy, token)
      if not ok2 then
        local msg = tostring(err2)

        forceGC()
        log.error("kernel", "Shell crashed on display " .. dIdx .. ": " .. msg)

        pcall(function()
          if dProxy then
            local sW, sH = dProxy.getSize()
            local sT = dProxy.getTheme()
            dProxy.fill(1, 2, sW, 3, " ", sT.fg, sT.bg)
            dProxy.set(2, 2, "Shell crashed:", sT.error, sT.bg)
            dProxy.set(2, 3, dProxy.fit(msg, sW - 2), sT.dim, sT.bg)
            computer.pullSignal(2)
          end
        end)
      end

      event.push("tos_shell_exited", dIdx)
    end, {
      priority  = 1,
      source    = "kernel",
      tsr       = false,
      principal = shellSession,
      token     = token,
      cwd       = shellSession and shellSession.home or "/",
      caps      = shellCaps,
      display   = dIdx,
    })

    local fgOk, fgErr = proc.setForeground(pid, dIdx)
    if not fgOk then
      log.error("kernel", "Seat " .. dIdx .. ": foreground handoff FAILED ("
        .. tostring(fgErr) .. ") — input will not reach the shell")
    end
    return pid
  end

  if shellModule then

    _G._TOS.bootSession   = nil
    _G._TOS.bootCompleted = true

    local displayCount = screenMod.count()

    for _, dIdx in ipairs(screenMod.indices()) do
      local pid = spawnLoginProcess(dIdx)
      local d = screenMod.get(dIdx)
      log.info("kernel", string.format(
        "Seat %d: gpu=%s screen=%s keyboards=%d login pid=%s",
        dIdx,
        tostring(d and d.gpu and d.gpu.address or "?"):sub(1, 8),
        tostring(d and d.screen or "?"):sub(1, 8),
        (d and d.keyboards and #d.keyboards) or 0,
        tostring(pid or "FAILED")))
    end

    _G._TOS.shellPIDs = shellPIDs

    if displayCount > 1 then
      log.info("kernel", "Multi-seat: " .. displayCount .. " displays active")
    end

    local lastCtrlC = {}
    local lastEntropyFeed = 0
    local monitorPIDs = {}

    local crashRespawns = 0
    while running do

      local signal = table.pack(event.pull(0.1))

      if signal[1] == "tos_shutdown" then
        running = false
        break
      end

      if signal[1] == "tos_logout" then
        local logoutIdx = signal[2]

        if not logoutIdx then
          local only, count = nil, 0
          for dIdx in pairs(shellPIDs) do count = count + 1; only = dIdx end
          if count == 1 then
            logoutIdx = only
            log.warn("kernel", "tos_logout without a seat index — assuming seat " .. only)
          else
            log.warn("kernel", "tos_logout without a seat index ignored ("
              .. count .. " seats live)")
          end
        end
        if logoutIdx then

          if shellPIDs[logoutIdx] then
            proc.kill(shellPIDs[logoutIdx], { kernel = true })
            shellPIDs[logoutIdx] = nil
          end
          if usersmod and sessionTokens[logoutIdx] then
            usersmod.logout(sessionTokens[logoutIdx])
            sessionTokens[logoutIdx] = nil
          end
          log.info("kernel", "Seat " .. logoutIdx .. ": logged out")
          spawnLoginProcess(logoutIdx)
          crashRespawns = 0
        end
        signal = table.pack(nil)
      end

      if signal[1] == "tos_shell_exited" then
        local dIdx = signal[2]
        if dIdx and not shellPIDs[dIdx] then

        elseif dIdx then
          shellPIDs[dIdx] = nil
          if usersmod and sessionTokens[dIdx] then
            usersmod.logout(sessionTokens[dIdx])
            sessionTokens[dIdx] = nil
          end
          log.info("kernel", "Seat " .. dIdx .. ": shell exited, respawning login")
          spawnLoginProcess(dIdx)
        end

        crashRespawns = 0
        signal = table.pack(nil)
      end

      if signal[1] == "key_down" then
        local nowE = computer.uptime()
        if nowE - lastEntropyFeed > 1 then
          lastEntropyFeed = nowE
          local cr = package.loaded and package.loaded["kernel.crypto"]
          if cr and cr.addEntropy then
            pcall(cr.addEntropy, tostring(nowE) .. "|" ..
              tostring(computer.freeMemory()))
          end
        end
      end

      if signal[1] == "key_down" and signal[3] == 3 then
        local ctrlDIdx = 1
        if screenMod.displayForKeyboard then
          ctrlDIdx = screenMod.displayForKeyboard(signal[2]) or 1
        end
        local fg = proc.getForeground(ctrlDIdx)
        local now = computer.uptime()
        if fg then
          if lastCtrlC[ctrlDIdx] and (now - lastCtrlC[ctrlDIdx]) < 1.5 then
            proc.kill(fg, { kernel = true })
            lastCtrlC[ctrlDIdx] = nil
            log.warn("kernel", "Killed PID " .. fg .. " via double Ctrl+C on display " .. ctrlDIdx)
          else
            proc.signal(fg, "tos_interrupt")
            lastCtrlC[ctrlDIdx] = now
          end
        end
        signal = table.pack(nil)
      end

      if signal[1] == "key_down" and signal[3] == 20 then
        local ctrlTIdx = 1
        if screenMod.displayForKeyboard then
          ctrlTIdx = screenMod.displayForKeyboard(signal[2]) or 1
        end

        local host = monitorHosts[ctrlTIdx]
        local hp = host and proc.get and proc.get(host)
        if hp and hp.state ~= proc.STATE.DEAD and shellPIDs[ctrlTIdx] == host then
          proc.setForeground(host, ctrlTIdx, { kernel = true })
          ;(proc.signalKernel or proc.signal)(host, "tos_monitor")
          signal = table.pack(nil)
        else

        local existing = monitorPIDs[ctrlTIdx]
        local ep = existing and proc.get and proc.get(existing)
        if ep and ep.state ~= proc.STATE.DEAD then
          signal = table.pack(nil)
        else

          local seatSess = nil
          if usersmod and sessionTokens[ctrlTIdx] then
            seatSess = usersmod.getSession(sessionTokens[ctrlTIdx])
          end
          local seatToken = sessionTokens[ctrlTIdx]
          local shellPid  = shellPIDs[ctrlTIdx]
          local mp
          mp = proc.spawn("monitor@" .. ctrlTIdx, function()

            local switched = kernel.taskSwitcher(ctrlTIdx, seatSess, {
              pull    = function() return coroutine.yield() end,
              fgPID   = shellPid,
              selfPid = mp,
            })

            monitorPIDs[ctrlTIdx] = nil
            if not (switched and proc.get and proc.get(switched)) then
              if shellPid and proc.get and proc.get(shellPid) then
                proc.setForeground(shellPid, ctrlTIdx, { kernel = true })
                (proc.signalKernel or proc.signal)(shellPid, "tos_focus")
              end
            end
          end, {
            priority  = 2,
            source    = "kernel",
            principal = seatSess,
            token     = seatToken,
            display   = ctrlTIdx,
          })
          monitorPIDs[ctrlTIdx] = mp

          proc.setForeground(mp, ctrlTIdx, { kernel = true })
          signal = table.pack(nil)
        end
        end
      end

      if signal[1] == "key_down" and signal[3] == 2 then
        local bgIdx = 1
        if screenMod.displayForKeyboard then
          bgIdx = screenMod.displayForKeyboard(signal[2]) or 1
        end
        local fg = proc.getForeground(bgIdx)
        local shellPid = shellPIDs[bgIdx]

        if fg and shellPid and fg ~= shellPid then
          local sp = proc.get and proc.get(shellPid)
          if sp and sp.state ~= proc.STATE.DEAD then
            proc.setForeground(shellPid, bgIdx, { kernel = true })
            ;(proc.signalKernel or proc.signal)(shellPid, "tos_focus")
            log.info("kernel", "Backgrounded PID " .. tostring(fg)
              .. " on display " .. bgIdx .. " (Ctrl+B)")
          end
        end
        signal = table.pack(nil)
      end

      if signal[1] == "tos_seat_changed" then

        local added, removed = screenMod.rebuild()
        for _, dIdx in ipairs(removed) do
          if shellPIDs[dIdx] then
            proc.kill(shellPIDs[dIdx], { kernel = true })
            shellPIDs[dIdx] = nil
          end

          if monitorPIDs[dIdx] then
            proc.kill(monitorPIDs[dIdx], { kernel = true })
            monitorPIDs[dIdx] = nil
          end
          if monitorHosts[dIdx] then monitorHosts[dIdx] = nil end
          if sessionTokens[dIdx] then
            if usersmod then usersmod.logout(sessionTokens[dIdx]) end
            sessionTokens[dIdx] = nil
          end
          log.warn("hotplug", "Display " .. dIdx .. " removed")
        end
        for _, dIdx in ipairs(added) do
          spawnLoginProcess(dIdx)
          log.info("hotplug", "Display " .. dIdx .. " added, spawning login")
        end
        signal = table.pack(nil)
      end

      proc.tick(signal.n > 0 and signal or nil)

      if proc.count() == 0 then
        log.warn("kernel", "All processes terminated")
        for dIdx, token in pairs(sessionTokens) do
          if usersmod then usersmod.logout(token) end
        end

        for k in pairs(sessionTokens) do sessionTokens[k] = nil end
        for k in pairs(shellPIDs) do shellPIDs[k] = nil end

        forceGC()
        local seats = (screenMod.count and screenMod.count()) or 0
        if running and seats > 0 then
          crashRespawns = crashRespawns + 1
          if crashRespawns <= 3 and computer.freeMemory() >= 64 * 1024 then
            log.warn("kernel", string.format(
              "Unexpected shell exit — recovering login on %d seat(s) [try %d/3, %dKB free]",
              seats, crashRespawns, math.floor(computer.freeMemory() / 1024)))

            for _, dIdx in ipairs(screenMod.indices()) do spawnLoginProcess(dIdx) end

          else
            log.error("kernel", string.format(
              "Shell unrecoverable (%dKB free after GC) — dropping to emergency shell",
              math.floor(computer.freeMemory() / 1024)))
            pcall(kernel.crashDump, string.format(
              "shell unrecoverable (%dKB free after GC)",
              math.floor(computer.freeMemory() / 1024)))
            kernel.emergencyShell()
            break
          end
        else
          break
        end
      end
    end
  else

    kernel.emergencyShell()
    running = false
  end

  kernel.shutdown()
end

function kernel.crashDump(reason, detail)
  local fs = _G._TOS and _G._TOS.fs
  if not (fs and fs.writeFile) then return false end
  local up    = math.floor((computer.uptime and computer.uptime()) or 0)
  local free  = math.floor(((computer.freeMemory and computer.freeMemory()) or 0) / 1024)
  local total = math.floor(((computer.totalMemory and computer.totalMemory()) or 0) / 1024)
  local lines = {
    "=== TOS CRASH REPORT ===",
    "reason : " .. tostring(reason or "unknown"),
    "uptime : " .. up .. "s",
    "memory : " .. free .. "KB free / " .. total .. "KB",
  }
  if detail then
    lines[#lines + 1] = "detail :"
    for l in tostring(detail):gmatch("[^\n]+") do lines[#lines + 1] = "  " .. l end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "--- recent log ---"
  local okL, logMod = pcall(require, "kernel.log")
  if okL and logMod and logMod.recent then
    local ok2, entries = pcall(logMod.recent, 40)
    if ok2 and type(entries) == "table" then
      for _, e in ipairs(entries) do
        lines[#lines + 1] = string.format("[%8.1f][%s] %s",
          tonumber(e.time) or 0, tostring(e.source or "?"), tostring(e.msg or ""))
      end
    end
  end
  local path = "/var/crash/crash-" .. up .. ".txt"
  local _, wrote = pcall(fs.writeFile, path, table.concat(lines, "\n") .. "\n")

  pcall(fs.writeFile, "/var/crash/NEW", tostring(reason or "unknown") .. " @ uptime " .. up .. "s")
  if okL and logMod and logMod.warn then logMod.warn("kernel", "Crash report saved: " .. path) end
  return wrote and path or false
end

function kernel.checkLastCrash()
  local fs = _G._TOS and _G._TOS.fs
  if not (fs and fs.exists) or not fs.exists("/var/crash/NEW") then return end
  local summary
  if fs.readFile then
    local ok, s = pcall(fs.readFile, "/var/crash/NEW")
    if ok and s then summary = tostring(s) end
  end
  summary = (summary or "a previous run"):gsub("%s+$", "")
  local okL, logMod = pcall(require, "kernel.log")
  if okL and logMod and logMod.warn then
    logMod.warn("kernel", "Last run crashed: " .. summary .. " — see /var/crash (`crash`)")
  end
  if fs.remove then pcall(fs.remove, "/var/crash/NEW") end
end

function kernel.monitorSnapshot(displayIdx, seatSession)
  if not proc then return { rows = {} } end
  local mon = require("kernel.monitor")
  local seatUser = seatSession and seatSession.user or nil
  local seatTier = (seatSession and seatSession.tier) or 0
  local procs = proc.list()
  if displayIdx then
    local f = {}
    for _, p in ipairs(procs) do
      if not p.display or p.display == displayIdx then f[#f + 1] = p end
    end
    procs = f
  end
  if seatSession and seatTier < 2 then
    local f = {}
    for _, p in ipairs(procs) do
      if not p.user or p.user == seatUser or p.user == "_kernel_" then f[#f + 1] = p end
    end
    procs = f
  end
  local services = {}
  if seatTier >= 2 then
    local okRC, rcMod = pcall(require, "kernel.rc")
    if okRC and rcMod and rcMod.list then
      local ok, svcs = pcall(rcMod.list)
      if ok and type(svcs) == "table" then services = svcs end
    end
  end
  local free  = (computer.freeMemory and computer.freeMemory()) or 0
  local total = (computer.totalMemory and computer.totalMemory()) or 0
  local up    = (computer.uptime and computer.uptime()) or 0
  local rows = {
    { text = string.format("Uptime %s   RAM %dK/%dK [%s]   Processes %d",
        mon.fmtUptime(up), math.floor((total - free) / 1024),
        math.floor(total / 1024), mon.memBar(total - free, total, 12), #procs),
      tone = "vitals" },
    { text = "", tone = "dim" },
  }
  for _, line in ipairs(mon.textRows(procs, services)) do rows[#rows + 1] = line end
  return { rows = rows }
end

function kernel.setMonitorHost(enable)
  if not proc then return false end
  local p = proc.current and proc.current()
  if not (p and p.display and p.pid) then return false end
  local shells = _G._TOS and _G._TOS.shellPIDs
  if not (shells and shells[p.display] == p.pid) then return false end
  monitorHosts[p.display] = (enable ~= false) and p.pid or nil
  return true
end

function kernel.isForeground()
  if not proc then return true end
  local p = proc.current and proc.current()
  if not p then return true end
  return proc.getForeground(p.display) == p.pid
end

function kernel.monitorList(displayIdx, seatSession)
  if not proc then return { rows = {}, vitals = nil } end
  local mon = require("kernel.monitor")
  local seatUser = seatSession and seatSession.user or nil
  local seatTier = (seatSession and seatSession.tier) or 0
  local fgPID = displayIdx and proc.getForeground(displayIdx) or nil
  local procs = proc.list()
  if displayIdx then
    local f = {}
    for _, p in ipairs(procs) do
      if not p.display or p.display == displayIdx then f[#f + 1] = p end
    end
    procs = f
  end
  if seatSession and seatTier < 2 then
    local f = {}
    for _, p in ipairs(procs) do
      if not p.user or p.user == seatUser or p.user == "_kernel_" then f[#f + 1] = p end
    end
    procs = f
  end
  local services = {}
  if seatTier >= 2 then
    local okRC, rcMod = pcall(require, "kernel.rc")
    if okRC and rcMod and rcMod.list then
      local ok, svcs = pcall(rcMod.list)
      if ok and type(svcs) == "table" then services = svcs end
    end
  end
  local rows = {}
  for _, p in ipairs(procs) do
    rows[#rows + 1] = {
      kind = "proc", pid = p.pid, label = mon.describe(p),
      owner = p.user or "kernel", state = p.tsr and "TSR" or (p.state or ""),
      tsr = p.tsr or false, cpu = p.cpuTime or 0, isFg = (p.pid == fgPID),
      canAct = mon.canAct(seatTier, seatUser, displayIdx, p),
    }
  end
  if #services > 0 then
    rows[#rows + 1] = { kind = "header", text = "Services" }
    for _, s in ipairs(services) do
      rows[#rows + 1] = {
        kind = "svc", name = s.name, running = s.running or false,
        enabled = s.enabled ~= false, canAct = seatTier >= 2,
      }
    end
  end
  local free  = (computer.freeMemory and computer.freeMemory()) or 0
  local total = (computer.totalMemory and computer.totalMemory()) or 0
  local vitals = string.format("up %s  ·  mem [%s] %dK/%dK free %dK  ·  %d proc",
    mon.fmtUptime((computer.uptime and computer.uptime()) or 0),
    mon.memBar(total - free, total, 12), math.floor((total - free) / 1024),
    math.floor(total / 1024), math.floor(free / 1024), #procs)
  return { rows = rows, vitals = vitals }
end

function kernel.monitorAct(action, id)
  if not proc then return false, "scheduler unavailable" end
  local caller = proc.current and proc.current()
  if not caller then return false, "no calling process" end
  local displayIdx = caller.display
  local sess = caller.principal
  local seatUser = sess and sess.user or nil
  local seatTier = (sess and sess.tier) or 0
  local mon = require("kernel.monitor")

  if action == "svc" then
    if seatTier < 2 then return false, "admin only" end
    local okRC, rcMod = pcall(require, "kernel.rc")
    if not (okRC and rcMod and rcMod.list) then return false, "rc unavailable" end
    local svc = nil
    local ok, svcs = pcall(rcMod.list)
    if ok and type(svcs) == "table" then
      for _, s in ipairs(svcs) do if s.name == id then svc = s; break end end
    end
    if not svc then return false, "no such service" end
    local act = svc.running and rcMod.stop or rcMod.start
    local ok2, err = pcall(act, svc.name)
    log.info("kernel", (svc.running and "Stopped " or "Started ")
      .. tostring(svc.name) .. " from monitor by " .. tostring(seatUser or "kernel")
      .. ((ok2 ~= false) and "" or (" (" .. tostring(err) .. ")")))
    if ok2 == false then return false, tostring(err) end
    return true
  end

  local p = proc.get(tonumber(id) or -1)
  if not p or p.state == proc.STATE.DEAD then return false, "no such process" end
  if displayIdx and p.display and p.display ~= displayIdx then
    return false, "not on this seat"
  end

  local pUser = p.principal and p.principal.user or nil
  if sess and seatTier < 2
     and pUser ~= nil and pUser ~= seatUser and pUser ~= "_kernel_" then
    return false, "not permitted"
  end
  local pEntry = { pid = p.pid, user = pUser, display = p.display }

  if action == "switch" then
    if p.pid == caller.pid then return false, "already in front" end
    proc.setForeground(p.pid, displayIdx, { kernel = true })
    ;(proc.signalKernel or proc.signal)(p.pid, "tos_focus")
    log.info("kernel", "Switched to PID " .. p.pid .. " (" .. tostring(p.name)
      .. ") from monitor tab")
    return true
  elseif action == "kill" then
    if p.pid == caller.pid then return false, "that is this shell" end
    if not mon.canAct(seatTier, seatUser, displayIdx, pEntry) then
      return false, "not permitted"
    end
    proc.kill(p.pid, { kernel = true })
    log.warn("kernel", "Killed PID " .. p.pid .. " (" .. tostring(p.name)
      .. ") from monitor by " .. tostring(seatUser or "kernel"))
    return true
  elseif action == "tsr" then

    if p.pid == caller.pid then return false, "that is this shell" end
    if not mon.canAct(seatTier, seatUser, displayIdx, pEntry) then
      return false, "not permitted"
    end
    if p.tsr then p.tsr = false; p.state = proc.STATE.READY
    else proc.goTSR(p.pid) end
    return true
  end
  return false, "unknown action"
end

function kernel.taskSwitcher(displayIdx, seatSession, opts)
  opts = opts or {}

  local procMode = opts.pull ~= nil
  local pull = opts.pull or function() return computer.pullSignal(0.5) end
  local selfPid = opts.selfPid

  local screenMod = require("kernel.screen")
  local dsp = displayIdx and screenMod.displayProxy(displayIdx) or display
  if not dsp or not proc then return end

  local usersmod = _G._TOS.users
  local seatUser = seatSession and seatSession.user or nil
  local seatTier = seatSession and seatSession.tier or 0

  local mon = require("kernel.monitor")
  local okRC, rcMod = pcall(require, "kernel.rc")
  local W, H = dsp.getSize()
  local T = dsp.getTheme()

  local function visibleProcs()
    local procs = proc.list()
    if displayIdx then
      local f = {}
      for _, p in ipairs(procs) do

        if p.pid ~= selfPid and (not p.display or p.display == displayIdx) then
          f[#f + 1] = p
        end
      end
      procs = f
    end
    if seatSession and seatTier < 2 then
      local f = {}
      for _, p in ipairs(procs) do
        if not p.user or p.user == seatUser or p.user == "_kernel_" then f[#f + 1] = p end
      end
      procs = f
    end
    return procs
  end

  local function visibleServices()
    if seatTier < 2 or not (okRC and rcMod and rcMod.list) then return {} end
    local ok, svcs = pcall(rcMod.list)
    return (ok and type(svcs) == "table") and svcs or {}
  end

  local function canAct(pEntry)
    return mon.canAct(seatTier, seatUser, displayIdx, pEntry)
  end

  local dx, dy = 1, 1
  local dw, dh = W, H

  local nameW = math.max(20, dw - 2 - 30)
  local svcW  = math.max(27, dw - 2 - 22)
  local listTop = dy + 4
  local listH   = math.max(1, dh - 6)

  local fgPID  = opts.fgPID or proc.getForeground(displayIdx)
  local switchedPid = nil
  local rows   = {}
  local sel    = 1
  local scroll = 0

  local function clampScroll()
    if #rows == 0 then scroll = 0; return end
    if sel <= scroll then scroll = sel - 1 end
    if sel > scroll + listH then scroll = sel - listH end
    local maxScroll = math.max(0, #rows - listH)
    if scroll > maxScroll then scroll = maxScroll end
    if scroll < 0 then scroll = 0 end
  end

  local function rebuild()
    rows = mon.buildRows(visibleProcs(), visibleServices())
    if #rows == 0 then return false end
    if sel > #rows then sel = #rows end
    if sel < 1 or (rows[sel] and rows[sel].kind == "header") then
      sel = mon.firstSelectable(rows)
    end
    clampScroll()
    return true
  end

  if not rebuild() then return end
  for i, r in ipairs(rows) do
    if r.kind == "proc" and r.p.pid == fgPID then sel = i; clampScroll(); break end
  end

  local function drawFrame()
    dsp.dbox(dx, dy, dw, dh, "System Monitor",
      { border = T.border, bg = T.panel_bg, title = T.title })
  end

  local function drawContent()

    local total = computer.totalMemory() or 0
    local free  = computer.freeMemory() or 0
    local used  = total - free
    local pcount = 0
    for _, r in ipairs(rows) do if r.kind == "proc" then pcount = pcount + 1 end end
    local vit = string.format(" up %s  ·  mem [%s] %dK/%dK free %dK  ·  %d proc",
      mon.fmtUptime(computer.uptime()), mon.memBar(used, total, 12),
      math.floor(used / 1024), math.floor(total / 1024), math.floor(free / 1024), pcount)
    dsp.set(dx + 1, dy + 1, dsp.fit(vit, dw - 2), T.fg, T.panel_bg)
    dsp.fill(dx + 1, dy + 2, dw - 2, 1, " ", T.fg, T.panel_bg)
    local hdr = string.format(" %-4s %-" .. nameW .. "s %-8s %-7s %5s",
      "PID", "Process", "Owner", "State", "CPU")
    dsp.set(dx + 1, dy + 3, dsp.fit(hdr, dw - 2), T.dim, T.panel_bg)

    for row = 1, listH do
      local idx = scroll + row
      local y = listTop + row - 1
      if idx <= #rows then
        local r = rows[idx]
        local selected = (idx == sel)
        if r.kind == "header" then

          local width = dw - 2
          local prefixCols = 4 + #r.text + 1
          local bar
          if prefixCols <= width then
            bar = " ── " .. r.text .. " "
              .. string.rep("─", width - prefixCols)
          else
            bar = " ── " .. r.text:sub(1, math.max(0, width - 5)) .. " "
          end
          dsp.set(dx + 1, y, bar, T.title, T.panel_bg)
        elseif r.kind == "proc" then
          local p = r.p
          local mark  = (p.pid == fgPID) and "*" or " "
          local state = p.tsr and "TSR" or (p.state or ""):sub(1, 7)
          local owner = (p.user or "kernel"):sub(1, 8)
          local line  = string.format("%s%-4d %-" .. nameW .. "s %-8s %-7s %4.1fs",
            mark, p.pid, mon.describe(p):sub(1, nameW), owner, state, p.cpuTime or 0)
          if selected then
            dsp.set(dx + 1, y, dsp.fit(line, dw - 2), T.sel_fg, T.sel_bg)
          else
            local color = T.fg
            if p.tsr then color = T.dim elseif p.pid == fgPID then color = T.highlight end
            dsp.set(dx + 1, y, dsp.fit(line, dw - 2), color, T.panel_bg)
          end
        else
          local s = r.s
          local status = s.running and "running"
            or (s.enabled == false and "disabled" or "stopped")
          local line = string.format("   %-" .. svcW .. "s %s", (s.name or "?"):sub(1, svcW), status)
          if selected then
            dsp.set(dx + 1, y, dsp.fit(line, dw - 2), T.sel_fg, T.sel_bg)
          else
            dsp.set(dx + 1, y, dsp.fit(line, dw - 2), s.running and T.highlight or T.dim, T.panel_bg)
          end
        end
      else
        dsp.fill(dx + 1, y, dw - 2, 1, " ", T.fg, T.panel_bg)
      end
    end

    local r = rows[sel]
    local help
    if r and r.kind == "svc" then
      help = " [Enter/S] start-stop   up/down move   [^Q] close"
    else
      help = " [Enter] switch  [K]ill  [T]SR   up/down move   [^Q] close"
    end
    dsp.set(dx + 1, dy + dh - 2, dsp.fit(help, dw - 2), T.dim, T.panel_bg)
  end

  drawFrame()
  drawContent()

  while true do
    local sig, _, ch, co = pull()
    if sig == "key_down" then
      if ch == 17 or ch == 113 then
        break
      elseif co == 200 then
        sel = mon.nextSelectable(rows, sel, -1); clampScroll(); drawContent()
      elseif co == 208 then
        sel = mon.nextSelectable(rows, sel, 1); clampScroll(); drawContent()
      elseif co == 201 then
        for _ = 1, listH do sel = mon.nextSelectable(rows, sel, -1) end; clampScroll(); drawContent()
      elseif co == 209 then
        for _ = 1, listH do sel = mon.nextSelectable(rows, sel, 1) end; clampScroll(); drawContent()
      else
        local r = rows[sel]
        if r and r.kind == "proc" then
          local p = r.p
          if co == 28 then

            proc.setForeground(p.pid, displayIdx, { kernel = true })

            (proc.signalKernel or proc.signal)(p.pid, "tos_focus")
            log.info("kernel", "Switched to PID " .. p.pid .. " (" .. tostring(p.name) .. ")")
            switchedPid = p.pid
            break
          elseif ch == 107 or ch == 75 then
            if p.pid ~= fgPID and canAct(p) then

              proc.kill(p.pid, { kernel = true })
              log.warn("kernel", "Killed PID " .. p.pid .. " (" .. tostring(p.name)
                .. ") from monitor by " .. tostring(seatUser or "kernel"))
              if not rebuild() then break end
              drawContent()
            end
          elseif ch == 116 or ch == 84 then
            if canAct(p) then
              local pObj = proc.get(p.pid)
              if pObj then
                if pObj.tsr then pObj.tsr = false; pObj.state = proc.STATE.READY
                else proc.goTSR(p.pid) end
                rebuild(); drawContent()
              end
            end
          end
        elseif r and r.kind == "svc" then
          if co == 28 or ch == 115 or ch == 83 then
            if seatTier >= 2 and okRC and rcMod then
              local s = r.s
              local act = s.running and rcMod.stop or rcMod.start
              local ok2, err = pcall(act, s.name)
              log.info("kernel", ((s.running and "Stopped ") or "Started ")
                .. tostring(s.name) .. " from monitor by " .. tostring(seatUser or "kernel")
                .. ((ok2 ~= false) and "" or (" (" .. tostring(err) .. ")")))
              rebuild(); drawContent()
            end
          end
        end
      end
    elseif sig == nil then

      rebuild(); drawContent()
    end
  end

  if procMode then

    return switchedPid
  end

  local fg = proc.getForeground(displayIdx)
  if fg then (proc.signalKernel or proc.signal)(fg, "tos_focus") end
  return switchedPid
end

function kernel.emergencyShell()
  if not display then return end

  local usersmod = _G._TOS.users
  local W0, H0 = display.getSize()
  local T0 = display.getTheme()

  display.clear(T0.bg)
  display.set(2, 2, "TOS EMERGENCY - Auth Required", T0.error, T0.bg)

  if not usersmod then
    display.set(2, 3, "User system unavailable - cannot authenticate.", T0.error, T0.bg)
    display.set(2, 4, "Rebooting...", T0.dim, T0.bg)
    computer.pullSignal(3)
    kernel.reboot()
    return
  end

  display.set(2, 3, "Password: ", T0.dim, T0.bg)

  local authed = false
  for attempt = 1, 3 do
    display.fill(12, 3, W0 - 13, 1, " ", T0.fg, T0.bg)
    local buf = ""
    while true do
      display.set(12, 3, string.rep("*", #buf) .. "_ ", T0.fg, T0.bg)
      local sig, _, ch, co = computer.pullSignal(0.5)
      if sig == "key_down" then
        if co == 28 then break
        elseif co == 14 then if #buf > 0 then buf = buf:sub(1, -2) end
        elseif ch and ch >= 32 and ch < 127 then buf = buf .. string.char(ch) end
      end
    end

    local token = usersmod.login("root", buf, { setCurrent = true })
    if token then authed = true break end
    if attempt < 3 then
      display.set(2, 5, "Wrong. " .. (3 - attempt) .. " left.", T0.error, T0.bg)
      computer.pullSignal(1.5)
      display.fill(2, 5, W0 - 3, 1, " ", T0.fg, T0.bg)
    end
  end
  if not authed then
    display.set(2, 5, "Locked. Rebooting...", T0.error, T0.bg)
    computer.pullSignal(3)
    kernel.reboot()
    return
  end

  local W, H = display.getSize()
  local T = display.getTheme()

  local lines = {}
  local scrollOff = 0
  local HEADER = 3
  local viewH = H - HEADER - 1

  local function redraw()
    display.clear(T.bg)
    display.set(2, 1, "TOS EMERGENCY SHELL", T.error, T.bg)
    display.set(2, 2, "Main shell could not load.", T.warning, T.bg)
    display.set(2, 3, "'help' for list.", T.dim, T.bg)
    local startIdx = #lines - viewH - scrollOff + 1
    if startIdx < 1 then startIdx = 1 end
    for row = 1, viewH do
      local idx = startIdx + row - 1
      local y = HEADER + row
      if idx >= 1 and idx <= #lines then
        local ln = lines[idx]
        display.fill(1, y, W, 1, " ", T.fg, T.bg)
        display.set(1, y, ln[1]:sub(1, W), ln[2] or T.dim, T.bg)
      else
        display.fill(1, y, W, 1, " ", T.fg, T.bg)
      end
    end
  end

  local function ePrint(text, color)
    lines[#lines + 1] = {tostring(text), color or T.dim}
    scrollOff = 0
    redraw()
  end

  local function prompt()
    local promptY = H
    display.fill(1, promptY, W, 1, " ", T.fg, T.bg)
    display.set(1, promptY, "> ", T.prompt, T.bg)
    local buf = ""
    while true do
      display.fill(3, promptY, W - 3, 1, " ", T.fg, T.bg)
      display.set(3, promptY, buf, T.fg, T.bg)
      display.set(3 + #buf, promptY, "_", T.prompt, T.bg)
      local sig, _, char, code = computer.pullSignal(0.5)
      if sig == "key_down" then
        if code == 28 then
          return buf
        elseif code == 14 then
          if #buf > 0 then buf = buf:sub(1, -2) end
        elseif char and char >= 32 and char < 127 then
          buf = buf .. string.char(char)
        end
      end
    end
  end

  local secfs = _G._TOS and _G._TOS.securefs
  local rootSess = usersmod.kernelSession and usersmod.kernelSession() or nil

  while true do
    local input = prompt()
    local parts = {}
    for w in input:gmatch("%S+") do parts[#parts + 1] = w end
    local cmd = parts[1] and parts[1]:lower() or ""

    if cmd == "help" then
      ePrint("Emergency commands:", T.title)
      ePrint("  ls [path]   - List files")
      ePrint("  cat <file>  - Show file")
      ePrint("  mem         - Memory info")
      ePrint("  verify      - Check system files")
      ePrint("  reboot      - Reboot system")
      ePrint("  shutdown    - Shut down")
    elseif cmd == "ls" then
      local path = parts[2] or "/"

      local list
      if secfs and secfs.list then
        list = secfs.list(path, rootSess)
      else
        local ok2, raw = pcall(fs.list, path)
        if ok2 then list = raw end
      end
      if list then
        if type(list) == "table" then
          for _, name in ipairs(list) do ePrint("  " .. name) end
        elseif type(list) == "function" then
          for name in list do ePrint("  " .. name) end
        end
      else
        ePrint("Cannot list: " .. path, T.error)
      end
    elseif cmd == "cat" then
      if parts[2] then

        local content
        if secfs and secfs.readFile then
          content = secfs.readFile(parts[2], rootSess)
        else
          content = fs.readFile(parts[2])
        end
        if content then
          for line in content:gmatch("[^\n]*") do ePrint(line) end
        else
          ePrint("Cannot read: " .. parts[2], T.error)
        end
      end
    elseif cmd == "mem" then
      ePrint(string.format("Free: %dKB / Total: %dKB",
        math.floor(computer.freeMemory() / 1024),
        math.floor(computer.totalMemory() / 1024)))
    elseif cmd == "verify" then
      kernel.verifySystem(ePrint)
    elseif cmd == "reboot" then
      kernel.reboot()
      return
    elseif cmd == "shutdown" then
      kernel.shutdown()
      return
    elseif cmd ~= "" then
      ePrint("Unknown: " .. cmd, T.warning)
    end
  end
end

function kernel.verifySystem(printFn)
  printFn = printFn or function() end

  local cOK  = display and display.c("success") or 0xFFFFFF
  local cWrn = display and display.c("warning") or 0xFFFFFF
  local cErr = display and display.c("error") or 0xFFFFFF
  local cDim = display and display.c("dim") or 0xFFFFFF

  local allFiles
  do
    local ok2, manifest = pcall(require, "system_manifest")
    if ok2 and type(manifest) == "table" then
      allFiles = manifest
    else

      allFiles = {
        { path = "/init.lua",              critical = true },
        { path = "/tos/kernel/init.lua",   critical = true },
        { path = "/tos/shell/init.lua",    critical = true },
      }
      printFn("  WARN: system_manifest.lua not found, using minimal verify list", cWrn)
    end
  end

  local ok, missing, damaged = 0, 0, 0
  --! Split out so the summary can say whether anything that matters is
  --! gone. "3 missing" reads the same whether they are man pages or the
  --! command registry, and those are not the same news.
  local missingCritical = 0

  local cryptoMod = nil
  do local okC, c = pcall(require, "kernel.crypto"); if okC then cryptoMod = c end end
  local hashMismatch = 0

  local function streamLoad(path)
    local h = fs.open(path, "r")
    if not h then return nil, nil, "unreadable" end
    local chunks, n = {}, 0
    local readOk, readErr = pcall(function()
      while true do
        local chunk = h:read(4096)
        if chunk == nil then break end
        if #chunk > 0 then n = n + 1; chunks[n] = chunk end
      end
    end)
    pcall(h.close, h)
    if not readOk then return nil, readErr, "raised" end
    local i = 0
    local okL, fn, lerr = pcall(load, function()
      i = i + 1
      local c = chunks[i]
      chunks[i] = nil
      return c
    end, "=" .. path, "t")
    if not okL then return nil, fn, "raised" end
    return fn, lerr, nil
  end

  for _, file in ipairs(allFiles) do
    if fs.exists(file.path) then
      do

        if file.hash and cryptoMod and cryptoMod.hash then
          if type(file.hash) ~= "string" or #file.hash ~= 64 or file.hash:find("[^%x]") then
            printFn("  BAD " .. file.path .. " (malformed hash in manifest)", cWrn)
            damaged = damaged + 1
            if type(collectgarbage) == "function" then pcall(collectgarbage, "collect") end
            goto continue_verify
          end
          local content = fs.readFile(file.path)
          if not content then
            printFn("  BAD " .. file.path .. " (unreadable)", cErr)
            damaged = damaged + 1
            if type(collectgarbage) == "function" then pcall(collectgarbage, "collect") end
            goto continue_verify
          end
          local actual = cryptoMod.hash(content)
          content = nil
          if not cryptoMod.ctEquals(actual, file.hash) then
            printFn("  HASH " .. file.path .. " (manifest=" .. file.hash:sub(1, 12) ..
              " actual=" .. actual:sub(1, 12) .. ")", cErr)
            hashMismatch = hashMismatch + 1
            damaged = damaged + 1
            if type(collectgarbage) == "function" then pcall(collectgarbage, "collect") end
            goto continue_verify
          end
        end

        if not file.path:match("%.lua$") then

          local readable = false
          local h = fs.open(file.path, "r")
          if h then
            readable = pcall(function()
              repeat local c = h:read(4096) until c == nil
            end)
            pcall(h.close, h)
          end
          if readable then
            printFn("  OK  " .. file.path, cOK)
            ok = ok + 1
          else
            printFn("  BAD " .. file.path .. " (unreadable)", cErr)
            damaged = damaged + 1
          end
        else
          local fn, loadErr, failMode = streamLoad(file.path)
          if fn then
            printFn("  OK  " .. file.path, cOK)
            ok = ok + 1
          elseif failMode == "unreadable" then
            printFn("  BAD " .. file.path .. " (unreadable)", cErr)
            damaged = damaged + 1
          else
            local reason
            if failMode == "raised" then
              reason = "OOM"
            else
              reason = "error"
              if loadErr then
                if loadErr:find("memory") then reason = "low RAM"
                else reason = "syntax" end
              end
            end
            printFn("  BAD " .. file.path .. " (" .. reason .. ")", cWrn)
            if failMode ~= "raised" and loadErr then
              printFn("      " .. tostring(loadErr), cDim)
            end
            damaged = damaged + 1
          end
        end
      end

      if type(collectgarbage) == "function" then
        pcall(collectgarbage, "collect")
      end
    else

      local tag   = file.critical and "MISS" or "GONE"
      local color = file.critical and cErr or cWrn
      printFn("  " .. tag .. " " .. file.path ..
        (file.critical and " (critical, not installed)" or " (not installed)"), color)
      missing = missing + 1
      if file.critical then missingCritical = missingCritical + 1 end
    end
    ::continue_verify::

    --! Let the rest of the machine breathe. This sweep hashes and
    --! compiles ~150 files; without a yield the shell is simply frozen
    --! until it finishes, with no output reaching the screen, which
    --! looks like a hang rather than like work. Every iteration, because
    --! a single large file is already the slow unit here.
    if proc and proc.yieldCooperative then pcall(proc.yieldCooperative) end
  end

  printFn("", cDim)
  --! MISSING and DAMAGED are deliberately separate totals and always
  --! have been: a file that is absent has nothing to be broken. The
  --! critical breakdown is new, so "2 missing" cannot hide the
  --! difference between two man pages and the command registry.
  local missText = tostring(missing)
  if missingCritical > 0 then
    missText = string.format("%d missing (%d CRITICAL)", missing, missingCritical)
  else
    missText = string.format("%d missing", missing)
  end
  if hashMismatch > 0 then
    printFn(string.format("Result: %d OK, %s, %d damaged (incl. %d HASH MISMATCH)",
      ok, missText, damaged, hashMismatch), cErr)
  elseif missingCritical > 0 or damaged > 0 then
    printFn(string.format("Result: %d OK, %s, %d damaged", ok, missText, damaged), cErr)
  elseif missing > 0 then
    printFn(string.format("Result: %d OK, %s, %d damaged", ok, missText, damaged), cWrn)
    printFn("Missing files are absent, not corrupt — reinstall to restore them.", cDim)
  else
    printFn(string.format("Result: %d OK, %s, %d damaged", ok, missText, damaged), cDim)
  end

  return missing == 0 and damaged == 0
end

local function readManifestSource()

  local path = "/tos/system_manifest.lua"
  if not fs.exists(path) then return nil, "manifest missing" end
  return fs.readFile(path)
end

function kernel.computeManifestHash()
  local source, err = readManifestSource()
  if not source then return nil, err end
  local okC, cryptoMod = pcall(require, "kernel.crypto")
  if not okC or not cryptoMod or not cryptoMod.hash then
    return nil, "crypto unavailable"
  end
  return cryptoMod.hash(source)
end

function kernel.anchorManifestHash()
  local digest, err = kernel.computeManifestHash()
  if not digest then return false, err end
  local component = require("component")
  local eepromAddr = component.list("eeprom")()
  if not eepromAddr then return false, "no EEPROM" end
  local ep = component.proxy(eepromAddr)
  if not ep.setData then return false, "EEPROM has no setData" end

  local existing = ep.getData() or ""
  local bootAddr = existing:match("^[^\n]*") or ""
  local payload = bootAddr .. "\nTOS1:" .. digest
  if #payload > 256 then return false, "EEPROM data field too small" end
  ep.setData(payload)
  return true, digest
end

function kernel.clearManifestAnchor()
  local component = require("component")
  local eepromAddr = component.list("eeprom", true)()
  if not eepromAddr then return false, "no EEPROM" end
  local ep = component.proxy(eepromAddr)
  if not (ep.getData and ep.setData) then return false, "EEPROM has no data field" end
  local existing = ep.getData() or ""
  ep.setData(existing:match("^[^\n]*") or "")
  return true
end

function kernel.verifyManifestHash()
  local component = require("component")
  local eepromAddr = component.list("eeprom")()
  if not eepromAddr then return false, "no EEPROM" end
  local ep = component.proxy(eepromAddr)
  if not ep.getData then return false, "EEPROM has no getData" end
  local existing = ep.getData() or ""

  local anchored = existing:match("\nTOS1:(%x+)") or existing:match("^TOS1:(%x+)")
  if not anchored then
    return false, "no anchored hash (run `verify anchor` as admin)"
  end
  anchored = anchored:sub(1, 64)
  if #anchored ~= 64 or anchored:find("[^%x]") then
    return false, "anchored value malformed"
  end
  local live, err = kernel.computeManifestHash()
  if not live then return false, err end
  local okC, cryptoMod = pcall(require, "kernel.crypto")
  if not okC or not cryptoMod or not cryptoMod.ctEquals then return false, "crypto unavailable" end
  if cryptoMod.ctEquals(live, anchored) then return true end
  return false, "manifest hash mismatch (live=" .. live:sub(1, 12) ..
    " anchored=" .. anchored:sub(1, 12) .. ")"
end

function kernel.getLog()      return log end
function kernel.getHAL()      return hal end
function kernel.getEvent()    return event end
function kernel.getProc()     return proc end

function kernel.getFS()
  return _G._TOS.securefs or fs
end
function kernel.getDisplay()  return display end
function kernel.getDisplayIdx() return nil end
function kernel.getUsers()    return _G._TOS.users end
function kernel.getSecureFS() return _G._TOS.securefs end
function kernel.getConfig()   return _G._TOS.config end
function kernel.getPower()    return _G._TOS.power end
function kernel.getSwap()     return _G._TOS.swap end
function kernel.getJBOD()     return _G._TOS.jbod end
function kernel.getNet()      return _G._TOS.net end
function kernel.getCompress()

  if _G._TOS.compress then return _G._TOS.compress end
  local ok, mod = pcall(require, "kernel.compress")
  if ok and mod then
    pcall(mod.init, {})
    _G._TOS.compress = mod
    return mod
  end
  return nil
end

function kernel.uptime()
  return computer.uptime() - _G._TOS.bootTime
end

function kernel.shutdown(reboot)
  running = false
  shuttingDown = true

  if log then
    log.info("kernel", reboot and "Rebooting..." or "Shutting down...")
  end

  local cronMod = package and package.loaded and package.loaded["kernel.cron"]
  if type(cronMod) == "table" and cronMod.shutdown then
    pcall(cronMod.shutdown)
  end

  if _G._TOS.rc then
    pcall(_G._TOS.rc.stopAll)
  end

  if proc then
    for _, p in ipairs(proc.list()) do
      pcall(proc.kill, p.pid, { kernel = true })
    end
  end

  if _G._TOS.net then
    pcall(_G._TOS.net.shutdown)
  end

  pcall(log.flush)
  pcall(log.detachFile)

  if display then
    pcall(function()
      local T = display.getTheme()
      display.clear(T.bg)
      display.set(2, 2, reboot and "Rebooting TOS..." or "TOS shut down.", T.success, T.bg)
      display.set(2, 3, "Goodbye!", T.dim, T.bg)
    end)
  end

  if _G._TOS.audio then pcall(_G._TOS.audio.shutdown) end

  pcall(function()
    local f = _G._TOS.fs
    if f and f.writeFile then
      f.writeFile("/var/run/pwrstate",
        "C\n" .. tostring(_G._TOS.bootCount or 0) .. "\n" ..
        tostring((os.time and os.time()) or 0))
    end
  end)

  computer.pullSignal(0.5)
  computer.shutdown(reboot or false)
end

function kernel.reboot()
  kernel.shutdown(true)
end

function kernel.version()
  return _G._TOS.version, _G._TOS.codename
end

function kernel.headlessMain()
  running = true

  local usersmod = _G._TOS.users

  if usersmod then
    _G._TOS.bootSession = usersmod.kernelSession()
  end

  log.info("kernel", "Entering headless service loop")

  if not _G._TOS.net then
    log.warn("kernel", "WARNING: headless server has no network!")
    log.warn("kernel", "Install a modem or linked card so the server can be reached.")
  end

  while running do
    local signal = table.pack(event.pull(0.5))

    if signal[1] == "tos_shutdown" then
      running = false
      break
    end

    if signal[1] == "component_added" then
      local ctype = signal[3]
      if ctype == "screen" or ctype == "gpu" or ctype == "keyboard" then
        log.info("kernel", "Display hardware detected — checking for interactive switch")

        local component2 = require("component")
        local hasGPU    = component2.list("gpu")() ~= nil
        local hasScreen = component2.list("screen")() ~= nil
        local hasKB     = component2.list("keyboard")() ~= nil
        if hasGPU and hasScreen and hasKB then
          log.info("kernel", "Full display hardware present — switching to interactive mode")
          running = false

          display = require("kernel.display")
          local gpu = component2.proxy(component2.list("gpu")())
          if gpu then

            local w, h = gpu.maxResolution()
            local okSc, screenMod = pcall(require, "kernel.screen")
            if okSc and screenMod and screenMod.gpuTarget then
              local spec = screenMod.getPolicy()
              or screenMod.specFromConfig(_G._TOS and _G._TOS.config)
              screenMod.setPolicy(spec)
              local tw, th = screenMod.gpuTarget(gpu, nil, spec)
              if tw and th then w, h = tw, th end
            end
            display.init(gpu, w, h)
          end
          kernel.loginAndStartShell()
          return
        end
      end
    end

    proc.tick(signal.n > 0 and signal or nil)
  end

  kernel.shutdown()
end

return kernel
