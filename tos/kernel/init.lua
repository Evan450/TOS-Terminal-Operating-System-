-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Main Module            ║
-- ║  Orchestrates boot and main loop     ║
-- ╚══════════════════════════════════════╝

local computer = require("computer")
local component = require("component")

local kernel = {}

-- Kernel state
local running = false
local shuttingDown = false

-- Sub-modules (loaded during boot)
local log, hal, event, proc, fs, display

-- Per-display Monitor HOST: display index → pid of a shell that hosts the
-- System Monitor as a full-screen TAB (the panels shell registers via
-- kernel.setMonitorHost). Ctrl+T focuses + signals that shell instead of
-- spawning the modal task-switcher process; seats without a registered
-- host (CLI shell, emergency) keep the process fallback.
local monitorHosts = {}

-- ============================================================
-- Boot sequence
-- ============================================================

function kernel.boot(opts)
  opts = opts or {}
  local earlyPrint = opts.earlyPrint or function() end
  -- Boot "chrome" lines that DON'T go through the log (they fire before log
  -- is up, or are cosmetic) must still respect the verbosity muter, or a
  -- "silent"/"splash" boot leaks stray text the log level would hide. Echo
  -- these only at INFO-and-louder (text=1 / verbose=0); splash(2)/silent(4)
  -- skip them — splash shows its bar instead, silent shows nothing.
  local _earlyMinLevel = opts.earlyMinLevel or 1
  local function bootEcho(text, color)
    if _earlyMinLevel <= 1 then earlyPrint(text, color) end
  end

  -- ── Boot spectrum (#4) ──────────────────────────────────
  -- Gate optional subsystems by the operator's profile / advanced toggles,
  -- falling back to the RAM check (today's behavior) when no boot config is
  -- present. `wants(feature, ramOK)` is the single decision point every
  -- optional stage consults.
  local bootCfg    = opts.bootcfg
  local bootcfgMod = opts.bootcfgMod
  local function wants(feature, ramOK)
    if bootcfgMod and bootCfg and bootcfgMod.wants then
      return bootcfgMod.wants(bootCfg, feature, ramOK)
    end
    return ramOK
  end
  -- Free-RAM floor for the optional stages (hoisted from Stage 6 so the
  -- ramOK closure below captures the LOCAL, not a nil global).
  local MIN_FREE_FOR_OPTIONAL = 40960  -- 40KB
  -- The measured "is there RAM headroom" gate, overridable by the operator
  -- declaring their memory situation (Boot Settings → RAM gate): "plenty"
  -- forces optional stages on, "tight" forces them off, auto measures.
  local function ramOK()
    -- Measured against a COLLECTED heap when it matters, not a raw reading.
    -- freeMemory() counts garbage as used, and this gate fires mid-boot --
    -- exactly when module loading has produced the most transient garbage it
    -- ever will -- so a raw reading can answer "no room for optional stages"
    -- on a box with room to spare. hal.freeMemory only pays for the
    -- collection when the cheap answer would have been no.
    local free = (hal and hal.freeMemory and hal.freeMemory(MIN_FREE_FOR_OPTIONAL))
      or computer.freeMemory()
    local detected = free > MIN_FREE_FOR_OPTIONAL
    if bootcfgMod and bootCfg and bootcfgMod.ramOK then
      return bootcfgMod.ramOK(bootCfg, detected)
    end
    return detected
  end

  -- ── Stage 1: Core modules ──────────────────────────────
  bootEcho("  Loading kernel modules...", 0xAAAAAA)
  log = require("kernel.log")
  -- earlyMinLevel = the verbosity "muter" (#3): which log levels echo to the
  -- boot screen. Absent => INFO (today's behavior).
  log.init({ earlyPrint = earlyPrint, earlyMinLevel = opts.earlyMinLevel,
    bootProgress = opts.bootProgress })
  log.info("kernel", "TOS Kernel v" .. _G._TOS.version .. " starting")

  -- Convenience wrapper used by kernel-tier rc.d services that want to
  -- write to the system log without having to require() it themselves.
  -- Signature matches log.info(source, msg) for drop-in use.
  _G._TOS.log    = function(src, msg) log.info(src, msg) end
  _G._TOS.logObj = log

  -- ── Stage 2: Hardware detection ────────────────────────
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

  -- ── Stage 3: Filesystem ────────────────────────────────
  log.info("kernel", "Initializing filesystem...")
  fs = require("kernel.fs")
  fs.init(opts.bootFS)

  -- Sanitize a disk's user-supplied label into a safe mount-point name.
  -- Labels are attacker-controllable (any player with a filesystem can
  -- set one to "../etc" or "../../tos") so we MUST strip path separators
  -- and traversal sequences before joining into /mnt/<label>. Fallback
  -- to an address-derived stub if sanitization leaves nothing usable.
  local function sanitizeLabel(raw, addr)
    local fallback = "disk_" .. addr:sub(1, 4)
    if type(raw) ~= "string" then return fallback end
    -- Keep only alphanumerics, underscore, hyphen, and space. Any other
    -- byte (including "/", "\\", ".", control chars, UTF-8) becomes "_".
    local cleaned = raw:gsub("[^%w_%- ]", "_")
    -- Collapse runs of whitespace/underscores and trim.
    cleaned = cleaned:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if cleaned == "" then return fallback end
    -- Length cap: keep mount paths short and predictable.
    if #cleaned > 32 then cleaned = cleaned:sub(1, 32) end
    -- Refuse labels that would shadow a system directory even after
    -- the /mnt/ prefix is applied.
    if cleaned == "." or cleaned == ".." then return fallback end
    return cleaned
  end

  -- Auto-mount additional filesystems
  local fsList = hal.list("filesystem")
  local bootAddr = opts.bootFS and opts.bootFS.address
  local usedMountPoints = {}
  for _, entry in ipairs(fsList) do
    if entry.address ~= bootAddr then
      local rawLabel
      if entry.proxy then
        -- getLabel can error on some proxies; always pcall.
        local okL, lbl = pcall(entry.proxy.getLabel)
        if okL then rawLabel = lbl end
      end
      local label = sanitizeLabel(rawLabel, entry.address)
      local mountPoint = "/mnt/" .. label
      -- De-dup: if two disks sanitize to the same name, suffix with the
      -- address stub so each gets its own mount point.
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

  -- Ensure core directories exist
  local coreDirs = {
    "/tmp", "/var", "/var/log", "/var/run", "/var/pkg", "/var/pkg/installed",
    "/var/swap", "/etc", "/usr", "/usr/bin", "/usr/modules",
  }
  for _, dir in ipairs(coreDirs) do
    if not fs.exists(dir) then
      fs.makeDirectory(dir)
    end
  end

  -- Attach the persistent kernel log NOW (right after fs is ready)
  -- so any later boot stage that warns/errors lands on disk too.
  -- log.flush is called periodically once event timers exist (Stage 5);
  -- log.fatal flushes synchronously, no timer required.
  pcall(log.attachFile, fs, "/var/log/kernel.log", { rotateBytes = 16384 })

  -- ── Unsafe-shutdown detection + write-crash recovery ──────
  -- A marker at /var/run/pwrstate records how the previous session ended.
  -- kernel.shutdown stamps it "clean" ('C'); we stamp it "running" ('R')
  -- here. A 'running' or corrupt/unreadable marker at boot means the last
  -- session was cut off (power toggled, battery died, world unloaded) —
  -- record that so we can complain and so the integrity machinery runs.
  local PWRSTATE = "/var/run/pwrstate"
  do
    local prev = fs.exists(PWRSTATE) and fs.readFile(PWRSTATE) or nil
    local boots = 0
    if type(prev) == "string" and #prev > 0 then
      boots = tonumber(prev:match("\n(%d+)")) or 0
      -- 'C' = clean; anything else (incl. 'R' or garbage) = unsafe.
      _G._TOS.unsafeShutdown = prev:sub(1, 1) ~= "C"
    else
      -- No marker at all = first boot on this disk, not an unsafe shutdown.
      _G._TOS.unsafeShutdown = false
    end
    _G._TOS.bootCount = boots + 1

    -- Repair any half-finished atomic writes of critical state BEFORE the
    -- config/users/trust loaders read those files.
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

    -- Stamp the marker "running" for THIS session.
    pcall(fs.writeFile, PWRSTATE,
      "R\n" .. _G._TOS.bootCount .. "\n" .. tostring((os.time and os.time()) or 0))

    if _G._TOS.unsafeShutdown then
      log.warn("kernel",
        "PREVIOUS SHUTDOWN WAS UNSAFE (power loss / forced off) — state verified on boot")
      pcall(computer.beep, 880, 0.1); pcall(computer.beep, 660, 0.1)
    end
  end

  -- ── SRM: collect the POST fault SRM Basic parked, if any ──
  -- The EEPROM half of SRM (bios.lua) writes an "SRM:<code>" line into the
  -- EEPROM data field when POST fails, because a machine that can't reach
  -- its disk has nowhere else to leave a note. THIS boot succeeded, so the
  -- previous one is the one being explained — report it loudly, then clear
  -- it so it is reported exactly once.
  --
  -- #MEM — the peek is a bare substring test on 256 bytes, deliberately NOT
  -- a kernel.srm load: this runs on every boot and a parked code is a rare
  -- event, so the module is only pulled in when there is actually something
  -- for it to explain. (Boot-time module loading is what the memory round
  -- moved to first-use; this keeps that promise.) The peek only decides
  -- WHETHER to look — srm owns the parsing, the wording and the clear, so
  -- the format lives in exactly one place.
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

  -- ── Self-repair (one-shot, Boot Settings → "Self-repair next boot") ──
  -- Runs right after the filesystem is up and the atomic-write sweep
  -- above finished, BEFORE any config/users/services consume the files it
  -- fixes. The flag clears itself first — even if a repair step crashes,
  -- the next boot is a normal one, never a repair loop. Fully pcall'd;
  -- repair must never be able to block boot.
  if bootCfg and bootCfg.repair then
    log.warn("kernel", "SELF-REPAIR requested — checking system state...")
    bootCfg.repair = false
    pcall(function()
      if bootcfgMod and bootcfgMod.save then bootcfgMod.save(fs, bootCfg) end
    end)
    -- Runs THROUGH SRM so the boot-time pass and the shell's `srm repair`
    -- are the same code producing the same report, instead of two dumps that
    -- drifted apart. SRM adds nothing dangerous here: its file-restore stage
    -- is opt-in and deliberately NOT enabled at boot — overwriting a system
    -- file is a decision an operator makes, not a fix that is "mechanically
    -- safe" in the sense this pass means (see the philosophy note at the top
    -- of kernel/repair.lua, which still governs stage 1).
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
      -- kernel.srm itself missing or unloadable is exactly the sort of
      -- partial install a repair boot exists to survive, so fall back to the
      -- fixer module directly and shape its output the same way.
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
      -- bootEcho, NOT earlyPrint: the repair report is a per-line dump, and
      -- on a splash/silent boot the screen belongs to the loading bar (or to
      -- nothing at all). Writing raw here scrolled the splash apart — it is
      -- exactly what bootEcho's muter exists to prevent. On a text or verbose
      -- boot this still prints every line, now coloured by severity.
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

  -- ── Stage 4: System configuration ─────────────────────
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

  -- ── Stage 4b: Disk swap (spill-to-disk "slow RAM") ────────
  -- Cheap, so it loads in every profile except `minimal` (which strips the
  -- machine to a bare shell). ramOK=true: it relieves RAM rather than costing
  -- it. Volatile by design — swap.init() wipes /var/swap on every boot.
  if wants("swap", true) then
    -- Disk compression (data-card deflate/inflate) loads alongside swap so
    -- spilled "slow RAM" is compressed when a card is present. Detection-
    -- gated inside the module — safe (and a no-op) on a card-less box.
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

  -- ── Stage 4b2: Internet card transport ────────────────────
  -- Detection-gated inside the module and essentially free to load: it
  -- opens nothing, listens for nothing, and holds no state. A machine
  -- with no card gets a module whose every call answers "no internet card
  -- installed", which is what `internet` and `doctor` want to report.
  -- Loading it does NOT grant anything: reaching it from a sandboxed
  -- program still needs the `internet` capability.
  do
    local okI, inetMod = pcall(require, "kernel.internet")
    if okI and inetMod then
      pcall(inetMod.init, { log = log, config = sysconfig })
      _G._TOS.internet = inetMod
    end
  end

  -- ── Stage 4c: JBOD disk pooling (opt-in) ──────────────────
  -- OFF in every profile; loads only when /etc/boot.cfg has
  -- advanced.jbod = true. ramOK=false so it never loads by RAM gate — a
  -- deliberate operator choice, since pooling reshapes the mount tree.
  if wants("jbod", false) then
    local okJ, jbodMod = pcall(require, "kernel.jbod")
    if okJ and jbodMod then
      _G._TOS.jbod = jbodMod
      log.info("kernel", "JBOD disk pooling enabled")
      -- Restore configured pools: build each member proxy from its
      -- filesystem-component address and mount the pool at its path.
      -- Missing members are skipped (a pulled disk loses only its slice);
      -- a pool with no surviving members is left unmounted with a warning.
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

  -- ── Stage 5: Event system ──────────────────────────────
  log.info("kernel", "Starting event system...")
  event = require("kernel.event")

  -- Register hardware hot-plug handlers
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

  -- The glass changed size and TOS was not the one that changed it: a screen
  -- block added or broken in-world, and OpenComputers clamping the resolution
  -- to the new maximum. Nothing was listening for this, so kernel.screen went
  -- on describing the old size -- see screen.onResized for what that costs.
  -- The shell relayouts off the same signal (panels/events.lua); this half is
  -- the one that has to happen even when no shell is running.
  event.on("screen_resized", function(_, addr, w, h)
    local okS, screenMod = pcall(require, "kernel.screen")
    if not (okS and screenMod and screenMod.onResized) then return end
    if screenMod.onResized(addr, w, h) then
      local nw, nh = screenMod.getResolution()
      log.info("screen", string.format("Screen resized externally -> %dx%d", nw or 0, nh or 0))
    end
  end, "kernel")

  -- ── Stage 6: Process manager ───────────────────────────
  log.info("kernel", "Starting process manager...")
  proc = require("kernel.process")

  -- ── Stage 7: Display system ────────────────────────────
  local isHeadless = sysconfig and sysconfig.isHeadless()
  if isHeadless then
    log.info("kernel", "Headless mode — skipping display init")
    -- Provide a stub display so code that calls display.* unconditionally
    -- doesn't crash. The stub silently discards all draw calls.
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
    -- Resolution policy: compute a readable working resolution (density-based
    -- "auto" by default) instead of forcing the hardware max, and share the
    -- policy with the multi-seat manager so every seat uses it too.
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

  -- ── Stage 8: Power monitor (optional) ─────────────────
  -- Only load optional modules if we have enough RAM (MIN_FREE_FOR_OPTIONAL,
  -- hoisted next to the ramOK() helper above). Shell needs ~30KB to load,
  -- so keep at least 40KB free. ramOK() honors the operator's Boot Settings
  -- RAM-gate declaration.

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
            -- Convert an imminent battery-death into a CLEAN shutdown so
            -- state is flushed and the dirty-bit cleared, rather than the
            -- abrupt cut corrupting an in-flight write. Operator can opt out
            -- via critBatShutdown=false in /etc/tos.cfg.
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
      -- Say WHY. wants() answers "profile" or "RAM", and blaming memory
      -- unconditionally produced the nonsense line "Skipping power module
      -- (low memory: 994KB free)" on a Safe Mode boot, where the profile —
      -- not the heap — turned the module off.
      log.warn("kernel", ramOK()
        and "Skipping power module (boot profile)"
        or ("Skipping power module (low memory: " ..
            math.floor(computer.freeMemory() / 1024) .. "KB free)"))
    end
  end

  -- #MEM — defer a kernel module to FIRST USE. Boot used to require+init
  -- several subsystems most sessions never touch (backup, keychain, trash,
  -- pkg, …); on a 512–1024KB box their loaded code was the difference
  -- between the shell fitting or OOMing at login. The proxy placed at
  -- _TOS[slot] is truthy, so callers' availability checks still pass; the
  -- first field access loads the real module and REPLACES _TOS[slot] so
  -- later lookups are direct.
  --
  -- `makeDeps` is for modules with no self-init of their own (backup,
  -- keychain); pass nil for the ones that wire themselves from _TOS on
  -- load (pkg, cron, trash) so they aren't initialized twice.
  --
  -- The resolved module is also cached in an upvalue, because every caller
  -- grabs the slot into a local first (`local km = _TOS.keychain` … then
  -- several `km.foo()` calls). Those later accesses still hit THIS proxy,
  -- not the replaced slot — without the cache each one would re-enter and
  -- re-init the module (for cron, that would cancel and re-register its
  -- tick timer on every field read).
  --
  -- A failed load logs ONCE and returns nil (reads as "unavailable" to the
  -- caller, the same as the old skipped-at-boot case) but is not cached as
  -- permanent: an OOM here is transient, so a later access can still
  -- succeed once memory frees up — matching the retry posture the shell's
  -- command loader already takes.
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

  -- ── Stage 9: Security subsystem (optional) ────────────
  do
    if computer.freeMemory() > MIN_FREE_FOR_OPTIONAL then
      local ok1, crypto = pcall(require, "kernel.crypto")
      if ok1 then
        crypto.init()
        log.info("kernel", "Crypto: " .. (crypto.hasHardware() and "Hardware" or "Software"))

        -- #SEC H-6 — cross-boot entropy. Feed the persisted pool into the
        -- RNG, then immediately write a fresh pool back for next boot so
        -- seed unpredictability accumulates across reboots. Fully guarded:
        -- a missing/unwritable entropy file must never block boot, and on
        -- hardware-RNG boxes this is a cheap no-op safety net.
        pcall(function()
          if not (crypto.addEntropy and crypto.exportEntropy and fs) then return end
          local EPATH = "/etc/entropy"
          if fs.makeDirectory and not fs.exists("/etc") then fs.makeDirectory("/etc") end
          if fs.exists(EPATH) then
            local blob = fs.readFile(EPATH)
            if type(blob) == "string" and #blob > 0 then crypto.addEntropy(blob) end
          end
          -- Mix in a little boot-time live entropy, then persist a fresh pool.
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
            -- Kernel-boot session for securefs callers running before any
            -- user logs in. Cleared once a real user session exists.
            _G._TOS.bootSession = usersmod.kernelSession()
            log.info("kernel", "Security: users + securefs ready")

            -- FEAT-1 — trash module piggybacks on securefs for ACL.
            -- #MEM — lazy: loads on the first rm/trash use. trash.lua
            -- self-initializes from _TOS on load (the CLI shell requires it
            -- directly), so no makeDeps here — both routes end up with the
            -- same one-time wiring.
            lazySlot("trash", "kernel.trash")

            -- FEAT-3 — profile module. Theme dependency is resolved
            -- below at stage 4 (display+theme); we wire profile.init
            -- now with whatever modules are already loaded, and the
            -- theme dep gets back-filled when applyPreset is first
            -- called (themeMod is read fresh from _G._TOS.theme each
            -- apply, so the late wiring is fine).
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

            -- i18n — language catalogs (/usr/lang/<code>.lang). Pure
            -- DATA files; English defaults live inline at every call
            -- site, so a missing or corrupt catalog can never take the
            -- UI down. Applies the /etc/tos.cfg `language` default now
            -- so even the login screen renders translated.
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

            -- FEAT-6 — backup module. Needs crypto for content hashes
            -- and securefs for ACL-checked reads/writes.
            -- #MEM — lazy: only explicit backup commands touch it.
            lazySlot("backup", "kernel.backup", function()
              return {
                securefs = securefs,
                fs       = fs,
                crypto   = crypto,
                log      = log,
              }
            end)

            -- FEAT-12 — keychain. Layered on vault (FEAT-10) so the
            -- on-disk slot table is master-password-encrypted.
            -- #MEM — lazy: keychain (and vault underneath it, which only
            -- keychain requires) now load on the first keychain command.
            lazySlot("keychain", "kernel.keychain", function()
              return {
                securefs  = securefs,
                users     = usersmod,
                log       = log,
                serialize = require("kernel.serialize"),
              }
            end)

            -- Periodic session sweep (every 5 minutes)
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

  -- ── Stage 9b: Theme manager (optional) ────────────────
  -- Lives between security and network because (a) it needs securefs
  -- to persist to /home/<user>/.theme.cfg under the right ACL, and
  -- (b) it must exist before the login event fires so the kernel
  -- main loop can call theme.applyForUser() on tos_login_complete.
  -- Skipped on monochrome systems and on low-RAM boots — the display
  -- already chose a sensible monochrome theme in those cases.
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

  -- ── Stage 10: Network (optional) ──────────────────────
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

        -- NET-1 — peer aliases. Loaded alongside net so any first-use
        -- (resolve, list) has the alias table ready.
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

        -- File transfer + remote shell handlers.
        -- #MEM — no longer loaded at boot. Both modules now self-initialize
        -- (building the same deps table this stage used to build) from _TOS
        -- when they load, and they load on demand from any entry route:
        --   inbound:  net's dispatch lazy-loads on the first FILE_REQ /
        --             REMOTE_EXEC packet (see loadLazyInbound, net/init.lua);
        --   outbound: scp/rsh commands pcall(require, ...) as before;
        --   services: fileshare/rshd arm/disarm via net.setServiceArm and
        --             never force the backend into RAM themselves.
        -- The daemons' enable gates stay fail-closed: an unloaded module
        -- refuses requests exactly like a loaded-but-disabled one.

        -- NOTE: the Cluster Manager↔Worker bridge is NOT started here. The
        -- cluster protocol core + worker bridge moved to the optional cluster
        -- package (TOS-Extras/cluster/manager-skeleton/usr/lib/cluster/) — the
        -- base kernel no longer ships or auto-starts cluster code. The
        -- cl_*/CLUSTER_* wire types stay in protocol.lua + trust.lua so a
        -- machine that later installs the cluster package can route them. The
        -- cluster-manager service owns bridge startup.
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
      -- Same fix as the power module: on a Safe Mode boot the profile is the
      -- reason, and "low memory" with ~1MB free just reads as a bug.
      log.warn("kernel", "Skipping network (boot profile)")
    else
      log.warn("kernel", "Skipping network (low memory: " ..
        math.floor(computer.freeMemory() / 1024) .. "KB free)")
    end
  end

  -- ── Stage 11: Startup services & compatibility ─────────
  -- Run startup scripts from /etc/rc.d/. Now a gateable FEATURE
  -- ("services") so Safe Mode / minimal can refuse to run third-party
  -- service code at boot; the normal profile stays RAM-gated as before.
  if wants("services", ramOK()) then
    local ok, rcMod = pcall(require, "kernel.rc")
    if ok then
      rcMod.init({ fs = fs, log = log, proc = proc })
      rcMod.runAll()
      _G._TOS.rc = rcMod
      log.info("kernel", "Startup services loaded")
      -- Service restart supervisor: check every 30s for crashed services
      if event then
        event.interval(30, function() rcMod.supervise() end, "kernel:rc_supervise")
      end
    end
  else
    log.warn("kernel", "Startup services skipped (boot profile)")
  end

  -- Initialize cron scheduler — same deal: a Safe Mode boot must not run
  -- scheduled jobs either.
  -- #MEM — only load the scheduler at boot when there ARE saved jobs to
  -- tick (/etc/cron.dat, the module's own store). A box with no jobs gets
  -- a lazy slot instead: the first `cron` command loads + initializes the
  -- module (whose init registers its tick interval), so adding a job
  -- starts the scheduler without a reboot — same behavior, no boot cost.
  if wants("cron", ramOK()) then
    if fs.exists("/etc/cron.dat") then
      local ok, cronMod = pcall(require, "kernel.cron")
      if ok then
        cronMod.init({ fs = fs, log = log, event = event })
        _G._TOS.cron = cronMod
        log.info("kernel", "Cron scheduler initialized")
      end
    else
      -- No makeDeps: cron.lua self-initializes from _TOS on load, which is
      -- also what the shell's direct require path relies on.
      lazySlot("cron", "kernel.cron")
    end
  else
    -- #MEM/#SEC — cron.lua now self-initializes from _TOS when required,
    -- and the shell's `cron` command require()s it directly. Without this
    -- flag a Safe Mode boot (cron=false) would be silently defeated: the
    -- first `cron` command would bring the scheduler up and start running
    -- saved jobs. Record the profile's refusal where the self-init sees it.
    _G._TOS.cronDisabled = true
    log.warn("kernel", "Cron scheduler skipped (boot profile)")
  end

  -- (The legacy module manager was retired in v1.3.1 — the package manager
  -- below owns install/enable/uninstall, command dispatch runs via
  -- pkg.getCommand, and service packages start through their own /etc/rc.d
  -- entry. Nothing auto-starts here anymore.)

  -- Initialize the new package manager. Phase-1 plumbing: lives ALONGSIDE
  -- the legacy modules system above (commit 2 will migrate in-tree
  -- subsystems and retire kernel.modules). On a fresh disk
  -- /var/pkg/installed/ is empty, so pkg.scan() returns 0 and no behavior
  -- changes; it just exposes the new API for subsequent commits.
  do
    -- #MEM — pkg (the second-largest module in the OS) no longer loads at
    -- boot. It self-initializes from _TOS when require()d — the executor's
    -- command dispatch, the `pkg` command, and floppy handling all already
    -- reach it via pcall(require, "kernel.pkg"). Its boot-time work moved
    -- with it: scan() and syncCriticalBackup() run in the self-init.
    -- Safe Mode / packages gated off: record the boot profile's decision
    -- where the self-init can see it, so package-provided commands still
    -- stop dispatching — no third-party code runs. The admin verbs keep
    -- working either way, exactly as before.
    if not wants("packages", true) then
      _G._TOS.pkgDispatchDisabled = true
      log.warn("kernel", "Package command dispatch disabled (boot profile)")
    end
    -- No makeDeps: pkg.lua self-initializes from _TOS on load (scan +
    -- critical-backup sync + the dispatch gate recorded above), which is
    -- the path every existing pcall(require, "kernel.pkg") caller takes.
    lazySlot("pkg", "kernel.pkg")
  end

  -- Periodic kernel-log flush. Every 30s we append new entries to
  -- /var/log/kernel.log (rotation handled by log.lua at 16 KB). Cheap
  -- enough — appendFile is one open/write/close call and the cursor
  -- ensures we never re-write entries.
  if event then
    event.interval(30, function() pcall(log.flush) end, "kernel:log_flush")
  end

  -- OpenOS compatibility layer (allows OPPM and OpenOS programs to run).
  -- #MEM — no longer loaded at boot (~12 modules of code that only OpenOS
  -- programs use). /init.lua's require() now lazy-loads the whole layer on
  -- the first require of an OpenOS library name (term, filesystem, io, …).
  -- The boot profile gate is preserved: when compat is off, the flag below
  -- makes the lazy path refuse too, so Safe Mode still can't run OpenOS
  -- code. RAM gating is inherent — nothing loads unless something asks.
  if not wants("compat", true) then
    _G._TOS.compatDisabled = true
    log.warn("kernel", "OpenOS compat disabled (boot profile)")
  else
    log.info("kernel", "OpenOS compat: lazy (loads on first use)")
  end

  -- ── Stage 12: Audio feedback system ─────────────────────
  -- Cheap (a couple of beep helpers); loads in every profile but `minimal`.
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

  -- FEAT-2 — expose a few extra hooks so the diag module can introspect
  -- without scraping internals. kernel.fs surface for disk reporting,
  -- and the kernel module itself for verifyManifestHash. The structured
  -- log module is already at _G._TOS.logObj (the bare _G._TOS.log stays
  -- as the write-shortcut function that existing callers depend on).
  -- A guarded GC nudge the shell can reach (_G._TOS.kernel.gc). OC sandboxes
  -- don't always expose `collectgarbage`; when the host does, callers about to
  -- make a big allocation (e.g. the shell loading a large command category on a
  -- low-memory box) can free transient garbage first. A no-op otherwise.
  function kernel.gc()
    if type(collectgarbage) == "function" then return pcall(collectgarbage, "collect") end
    return false
  end
  _G._TOS.fs     = fs
  _G._TOS.kernel = kernel
  -- REV-1: kiosk and a few other shell-side helpers read _TOS.proc;
  -- it was never exposed. Surface it now alongside the other
  -- kernel-module handles.
  _G._TOS.proc   = proc
  _G._TOS.event  = event

  -- ── Stage 13: Boot complete ─────────────────────────────
  -- #MEM — keep the collector tight on small heaps. Lua's default GC pause
  -- (200%) lets garbage accumulate to twice the live set before a full
  -- cycle runs; on a 512KB–1MB box that float alone can eat the headroom
  -- the shell needs to load. 120% trades a little CPU for a much smaller
  -- steady-state heap. Not every OC host exposes collectgarbage (or its
  -- tuning verbs) inside the sandbox — guarded, no-op where absent.
  if type(collectgarbage) == "function" then
    pcall(collectgarbage, "setpause", 120)
  end

  -- The honest number, not the first one offered. At this exact point the
  -- heap carries every scrap of garbage thirteen stages of module loading
  -- produced, and a raw reading here is what the operator sees in the boot
  -- log, on the splash, and what the LOW MEMORY warning below tests. On a
  -- real 2MB box it read 322KB while 1268KB was actually free. No `need`
  -- argument: this is a report, so always collect and tell the truth.
  local freeNow = (hal and hal.freeMemory and hal.freeMemory()) or computer.freeMemory()
  local bootDuration = computer.uptime() - _G._TOS.bootTime
  log.info("kernel", "Boot complete! Free memory: " ..
    math.floor(freeNow / 1024) .. "KB")
  log.info("kernel", string.format("Boot time: %.1fs", bootDuration))

  -- Flight-recorder: if the previous run left a crash marker, report it now.
  pcall(kernel.checkLastCrash)

  if freeNow < 20480 then
    log.warn("kernel", "LOW MEMORY: " .. math.floor(freeNow / 1024) .. "KB free!")
  end

  bootEcho(string.format("  Boot complete: %.1fs, %dK free",
    bootDuration, math.floor(freeNow / 1024)), 0x00FF00)

  -- Boot success sound
  if _G._TOS.audio then _G._TOS.audio.bootComplete() end

  -- ── In-emulator self-test battery (opt-in) ──────────────────────
  -- Gated on /etc/selftest.on EXISTING, and the require sits inside the
  -- gate on purpose: a production boot never loads the module, so it
  -- costs nothing but the bytes on disk. See kernel/selftest.lua.
  --
  -- Everything here is pcall'd twice over. A battery that could stop a
  -- machine booting would be worse than the bugs it exists to find.
  do
    local okS, st = pcall(function()
      local fsMod = _G._TOS and _G._TOS.fs
      if not (fsMod and fsMod.exists) then return nil end
      -- /etc/selftest.on OR selftest.on on any inserted disk. /etc is
      -- securefs-protected, so the disk-side marker is the one an
      -- operator can actually create; see selftest.markerPaths.
      -- Mount points come from the MOUNT TABLE, not from listing /mnt.
      -- Boot-time mounts are virtual: fs.mount records them without
      -- creating a real /mnt/<label> directory, so fs.list("/mnt") is
      -- empty and a test disk sitting in the drive is invisible. That is
      -- what blocked every attempted round.
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
    -- Boot-message read pause. Only applied when the user asked for
    -- verbose boot — otherwise the kernel.log file (written
    -- continuously by log.flush since the /var/log wire-up) is the
    -- canonical record and a 1.5s tax on every boot is unjustified.
    --
    -- To restore the old "always pause" behaviour: set verbose=true
    -- in /etc/tos.cfg, or add bootPause=N for a custom pause length.
    local bootPause = 0
    if sysconfig then
      bootPause = tonumber(sysconfig.get("bootPause")) or
                  (sysconfig.get("verbose") and 1.5 or 0)
    end
    if bootPause > 0 then computer.pullSignal(bootPause) end
  end

  -- Stop routing log messages to the GPU (shell owns the screen now)
  log.detachEarlyPrint()

  -- ── Stage 14: Login → Shell / Headless Loop ─────────────
  -- #MEM — boot() is one-shot: /init.lua calls it exactly once per power-on
  -- (kernel.reboot goes through computer.shutdown, which restarts from the
  -- BIOS). Dropping the reference lets the GC reclaim boot's compiled chunk
  -- and constants once it returns; the interval callbacks registered above
  -- (log flush, rc supervise, session sweep) hold their own prototypes and
  -- survive independently.
  kernel.boot = nil

  if isHeadless then
    kernel.headlessMain()
  else
    kernel.loginAndStartShell()
  end
end

-- ============================================================
-- Login + Shell launcher
-- ============================================================

function kernel.loginAndStartShell()
  running = true

  local usersmod = _G._TOS.users
  local securefs = _G._TOS.securefs
  local freeMem = computer.freeMemory()

  -- #OOM — OC sandboxes do NOT expose `collectgarbage` as a global (calling
  -- it bare panics: "attempt to call a nil value (global 'collectgarbage')").
  -- The runtime GCs on its own; this just nudges a collection before a big
  -- allocation when the host happens to provide it. Always go through here.
  local function forceGC()
    if type(collectgarbage) == "function" then pcall(collectgarbage, "collect") end
  end

  -- ── Minimal auth (works even with no login module) ────
  -- SECURITY: Always require password. RAM removal must NOT
  -- grant access. If usersmod is missing we FAIL CLOSED — the old
  -- "type 'root' to get in" branch was an unauthenticated backdoor
  -- reachable by inducing enough RAM pressure to skip Stage 9.
  local function minimalAuth()
    local W, H = display.getSize()
    local T = display.getTheme()
    display.clear(T.bg)
    display.set(2, 2, "TOS - Authentication Required", T.title, T.bg)

    if not usersmod then
      -- No auth module available — refuse to log anyone in rather than
      -- falling through to a hardcoded emergency password.
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

    -- #128 — persistent lockout gate. Without this, an attacker could
    -- reboot-to-clear the in-memory attempt counter and brute-force
    -- the root password at normal typing speed. We persist the next
    -- allowed time under /var/lockout.dat; securefs-or-raw-fs, because
    -- in low-memory minimal-auth we may not even have a usable securefs.
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
    -- Stored timestamp is in uptime seconds — which resets on reboot.
    -- We conservatively treat any stored value > now as "still locked,
    -- sleep for the residual". In practice an attacker who reboots
    -- resets uptime to 0, so they still pay the wait.
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

      -- #BUG-1 — minimalAuth is single-seat by definition (emergency
      -- recovery on a single display), so setCurrent=true is correct
      -- here — but mark it explicit for the grep'er.
      local token = usersmod.login("root", buf, { setCurrent = true })
      if token then
        -- Clear any residual lockout on success.
        writeLockout(0)
        display.set(2, 7, "Access granted.", T.success, T.bg)
        computer.pullSignal(0.5)
        return token
      end

      -- Loud audit trail and exponential backoff per failed try.
      -- 1 -> 2s, 2 -> 4s, 3 -> 8s, 4 -> 16s, 5 -> 32s
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

    -- Persist a 60-second cool-down so reboot-to-retry doesn't help.
    writeLockout(computer.uptime() + 60)
    display.set(2, 7, "Too many attempts. Rebooting (locked 60s)...", T.error, T.bg)
    if _G._TOS.audio then _G._TOS.audio.critical() else computer.beep(400, 0.5) end
    computer.pullSignal(3)
    kernel.reboot()
    return nil
  end

  -- ── Decide auth path ──────────────────────────────────
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
    -- Use "shell.init" (not "shell") to avoid collision with the OpenOS
    -- compat shim, which registers package.loaded["shell"] = shell_api.
    local ok, mod = pcall(require, "shell.init")
    if ok then
      shellModule = mod
    else
      log.error("kernel", "Shell module failed: " .. tostring(mod))
    end
  end

  -- ── Per-seat helpers ──────────────────────────────────
  local screenMod = require("kernel.screen")
  local shellCaps = {
    ["fs.read"]   = true,
    ["fs.write"]  = true,
    ["compat.io"] = true,
    ["component"] = true,
    ["load"]      = true,
    ["net"]       = true,
    -- #FIX (in-game, 2026-08-11) — the peripheral caps were absent, and
    -- the consequence was invisible until someone attached hardware: the
    -- kernel's peripheral modules gate on the running PROCESS's caps, so
    -- `redstone`, `robot` and `inventory` typed at a shell could never
    -- open their gate. They reported "no component" or "cap required" on
    -- a machine where the device was attached and had been logged by
    -- hotplug seconds earlier.
    --
    -- Safe to grant here because these are FIRST-PARTY shell commands
    -- and every one of them is tier-gated in the command registry
    -- (redstone/robot/inventory are tier 1, `component` is tier 2), so a
    -- guest cannot reach them regardless of what this process holds.
    --
    -- PACKAGE code never sees this set: kernel.pkg wraps every package
    -- command in a cap scope that replaces the process's caps with the
    -- MANIFEST's for the duration of the call — strictly narrower than
    -- this for anything the package did not declare. See the #SEC CAP
    -- SCOPE note in pkg.lua.
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

  -- Per-seat state: session tokens and shell PIDs indexed by display
  local sessionTokens = {}
  local shellPIDs = {}

  -- Forward-declare spawnShellForSeat so spawnLoginProcess (below) can
  -- close over it. Without the `local` the assignment at definition
  -- time leaked to _G, exposing the shell spawner to any sandboxed
  -- program that peeked at globals (#131/#132).
  local spawnShellForSeat

  --- Spawn a login process on a specific display.
  -- On successful auth, pushes tos_login_complete(dIdx, token).
  local function spawnLoginProcess(dIdx)
    local dProxy = screenMod.displayProxy(dIdx)
    if not dProxy then return nil end
    -- #135 — explicit guest-tier principal for the login seat. Without
    -- this the login process would inherit the boot/root session, which
    -- means a compromised login UI would run as root. Bind an isolated
    -- "_login_" principal (tier 0) per seat instead. Auth code still
    -- gets real credentials via minimalAuth / loginScreen.run, which
    -- issue full-tier tokens on success.
    local loginPrincipal = usersmod and usersmod.loginSession
                           and usersmod.loginSession(dIdx) or nil
    local loginPid = proc.spawn("login@" .. dIdx, function()
      local token = nil
      if useMinimalAuth then
        token = minimalAuth()
      elseif loginScreen then
        -- loginScreen.run returns (token, reason). The reason carries operator
        -- intents like "shutdown" (F10 on the cancel screen). pcall prefixes its
        -- own success bool, so capture BOTH returns — previously only `token`
        -- was kept and the "shutdown" reason was dropped, so F10 just looped
        -- back to the login screen instead of powering off.
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
        -- (Removed REV-1: the `_G._TOS.shellPID` singleton was write-
        -- only — nothing read it, but it suggested "the active shell"
        -- which is the wrong shape for multi-seat. Per-display lookup
        -- via shellPIDs[dIdx] is the canonical answer.)
      end
    end, {
      display   = dIdx,
      priority  = 2,
      source    = "kernel",
      principal = loginPrincipal,
    })
    -- #FIX (multi-seat input) — claim THIS seat's foreground for the login
    -- broker. Without it displayForeground[dIdx] stays nil, so the seat's
    -- keystrokes fall back to the GLOBAL foregroundPID (shared across seats) —
    -- a 2nd seat's login then captured the 1st seat's input and froze it. The
    -- later login→shell handoff (spawnShellForSeat) re-claims the same seat.
    if loginPid then pcall(proc.setForeground, loginPid, dIdx) end
    return loginPid
  end

  --- Spawn a shell for a seat that has completed login.
  spawnShellForSeat = function(dIdx, token)
    local dProxy = screenMod.displayProxy(dIdx)
    if not dProxy or not shellModule then return nil end

    -- #131 — require a valid post-login token. Previously a nil token
    -- quietly fell through to usersmod.kernelSession(), which meant any
    -- caller that reached this function (e.g. via the old _G leak, or
    -- minimalAuth paths that returned without issuing a token) spawned
    -- a ROOT shell. Fail closed instead.
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

    -- REV-1 — apply the user's saved theme + profile at shell-spawn
    -- time. Previously this was wired to a `tos_login_complete` signal
    -- that nothing pushed, so the FEAT-3 profile integration never
    -- actually ran. Theme first (visible immediately on first draw),
    -- then profile (which may layer additional env vars).
    if _G._TOS.theme and _G._TOS.theme.applyForUser then
      pcall(_G._TOS.theme.applyForUser, shellSession)
    end
    if _G._TOS.profile and _G._TOS.profile.load and _G._TOS.profile.apply then
      pcall(function()
        local p = _G._TOS.profile.load(shellSession)
        -- profile.apply also returns the startup-command list, but
        -- the shell-side dispatcher is responsible for running them
        -- (the kernel doesn't know how to invoke shell commands).
        -- The profile module stashes the result on the session so the
        -- shell can pick it up.
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

    -- FEAT-4 — If the logged-in user is "kiosk", launch the locked-down
    -- kiosk shell instead of the regular panels shell. Admins can also
    -- opt any user into kiosk by setting their profile.startup to
    -- "exec_kiosk" (future enhancement); for now, the username is the
    -- canonical opt-in.
    local shellRunner = shellModule.run
    if userName == "kiosk" then
      local okK, kioskMod = pcall(require, "shell.kiosk")
      if okK and kioskMod and kioskMod.run then
        shellRunner = kioskMod.run
        log.info("kernel", "Seat " .. dIdx .. ": KIOSK mode")
      end
    end

    -- #OOM — reclaim before handing the shell its heap. Boot leaves a lot of
    -- transient garbage (module load, compat shims, rc.d); GC'ing here gives
    -- the panels shell the maximum contiguous free memory and turns a lot of
    -- marginal "just barely OOMs at login" boxes into ones that load. The
    -- free-memory line makes a genuine shortfall visible in the log.
    forceGC()
    log.info("kernel", string.format("Seat %d: loading shell (%dKB free)",
      dIdx, math.floor(computer.freeMemory() / 1024)))

    local pid = proc.spawn("shell:" .. userName .. "@" .. dIdx, function()
      local ok2, err2 = pcall(shellRunner, kernelCopy, token)
      if not ok2 then
        local msg = tostring(err2)
        -- An OOM crash can leave the heap too starved to even format the
        -- message; GC first so the log + on-screen notice can allocate.
        forceGC()
        log.error("kernel", "Shell crashed on display " .. dIdx .. ": " .. msg)
        -- Draw the crash notice defensively — under OOM the draw itself can
        -- throw, and an unhandled error here would escape the process body.
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
      -- Shell exited naturally — signal kernel to respawn login for this seat
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
    -- #REV-3 — surface a failed handoff instead of ignoring the return:
    -- if the seat's input isn't routed to this shell, the seat is dead
    -- (shell draws, input goes nowhere). The H13 ownership gate silently
    -- denying this exact call is how the post-login "bricked" state
    -- shipped; process.lua now permits the own-child-same-seat handoff,
    -- and this log line makes any future regression visible.
    local fgOk, fgErr = proc.setForeground(pid, dIdx)
    if not fgOk then
      log.error("kernel", "Seat " .. dIdx .. ": foreground handoff FAILED ("
        .. tostring(fgErr) .. ") — input will not reach the shell")
    end
    return pid
  end

  -- ── Main session loop ──────────────────────────────────
  if shellModule then
    -- #134/#122 — narrow bootSession lifetime. We only needed this
    -- synthetic root session during early init (pre-login securefs,
    -- rc.d, cron bootstrap). Once logins start, leaving it live means
    -- any sandboxed code that peeks at _G._TOS.bootSession gets a
    -- root-tier fallback it wasn't entitled to. Callers that still
    -- need privileged access should now request usersmod.kernelSession()
    -- explicitly (and be audited when doing so).
    _G._TOS.bootSession   = nil
    _G._TOS.bootCompleted = true

    local displayCount = screenMod.count()
    -- (spawnShellForSeat is already declared above — do NOT re-local
    -- it here or the assignment inside spawnLoginProcess binds to a
    -- different upvalue.)
    -- Spawn initial login process on each display. #FIX (stable seat
    -- indices) — iterate the REAL seat indices, not 1..count: indices are
    -- stable across hot-plug rebuilds and may have holes.
    -- One log line per seat (gpu/screen/keyboards/login pid): the 2-seat
    -- "no login on the other screen" report was undiagnosable without
    -- knowing what each seat actually bound — `log` now answers it.
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
    -- (REV-1: shellPID singleton removed — see comment in spawnShellForSeat.)

    if displayCount > 1 then
      log.info("kernel", "Multi-seat: " .. displayCount .. " displays active")
    end

    -- Main kernel loop
    local lastCtrlC = {}  -- per-display Ctrl+C timing
    local lastEntropyFeed = 0  -- keypress-timing RNG feed throttle (#REV #12)
    local monitorPIDs = {}     -- per-display live System Monitor process (#REV multi-seat)
    -- #OOM — consecutive unexpected "all processes gone" recoveries. A clean
    -- logout/exit respawns login (count never hits 0), so this only climbs on
    -- real crashes (typically OOM at login on a tight box). Bounded so an
    -- OOM-crash-loop drops to the emergency shell instead of spinning.
    local crashRespawns = 0
    while running do
      -- 0.1s idle tick (was 0.05). pull() returns IMMEDIATELY on any
      -- real signal, so input latency is untouched — the timeout only
      -- sets how often the machine wakes with nothing to do. Halving
      -- the idle wake-ups halves TOS's standing cost to the host
      -- (relevant on a laggy emulator), and 0.1s matches the shell
      -- event loop's own cadence.
      local signal = table.pack(event.pull(0.1))

      if signal[1] == "tos_shutdown" then
        running = false
        break
      end

      -- REV-1: the `tos_login_complete` handler used to live here but
      -- nothing ever pushed the signal — the login process at line
      -- ~800 calls spawnShellForSeat directly. Theme/profile
      -- application moved INTO spawnShellForSeat so it actually fires.
      -- Logout still flows through tos_logout below; that signal IS
      -- pushed (by the shell's logout command).

      -- ── Per-seat logout: kill shell, respawn login ──
      if signal[1] == "tos_logout" then
        local logoutIdx = signal[2]
        -- #FIX (round 4) — a nil seat index used to mean "global logout",
        -- which killed every shell and BROKE the kernel loop -> fell into
        -- kernel.shutdown() -> the "logout powers off the machine"
        -- operator repro. No shipped code pushes a global logout on
        -- purpose (every site passes its seat), so a nil here is always
        -- a caller bug (a shell spawned without its seat index). Resolve
        -- it to the only live seat when that's unambiguous; otherwise
        -- refuse loudly. Logging out must never halt the machine.
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
          -- Seat-local logout
          if shellPIDs[logoutIdx] then
            proc.kill(shellPIDs[logoutIdx], { kernel = true })  -- #FIX reap on logout
            shellPIDs[logoutIdx] = nil
          end
          if usersmod and sessionTokens[logoutIdx] then
            usersmod.logout(sessionTokens[logoutIdx])
            sessionTokens[logoutIdx] = nil
          end
          log.info("kernel", "Seat " .. logoutIdx .. ": logged out")
          spawnLoginProcess(logoutIdx)
          crashRespawns = 0   -- clean logout: a shell ran fine here
        end
        signal = table.pack(nil)
      end

      -- ── Shell exited naturally on a seat: respawn login ──
      if signal[1] == "tos_shell_exited" then
        local dIdx = signal[2]
        if dIdx and not shellPIDs[dIdx] then
          -- Shell already cleaned up (logout handled it); skip
        elseif dIdx then
          shellPIDs[dIdx] = nil
          if usersmod and sessionTokens[dIdx] then
            usersmod.logout(sessionTokens[dIdx])
            sessionTokens[dIdx] = nil
          end
          log.info("kernel", "Seat " .. dIdx .. ": shell exited, respawning login")
          spawnLoginProcess(dIdx)
        end
        -- A clean exit means the shell ran fine; reset the OOM-recovery
        -- budget so a much-later, unrelated crash gets its full retries.
        crashRespawns = 0
        signal = table.pack(nil)
      end

      -- ── Seat-local hotkey: Ctrl+C = interrupt foreground ──
      -- ── RNG: fold human keypress TIMING into the entropy pool ──
      -- (#REV review finding #12) Human timing jitter is the best free
      -- entropy OC offers, and session tokens hang off this RNG.
      -- Deliberately timing-ONLY — key chars/codes include passwords,
      -- and the pool is exported to /etc/entropy. Throttled to ~1/s so
      -- the hot loop stays hot; resolved lazily (no boot-order dep).
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

      -- Ctrl+C sends char=3 in OC; signal[2] = keyboard address
      if signal[1] == "key_down" and signal[3] == 3 then
        local ctrlDIdx = 1
        if screenMod.displayForKeyboard then
          ctrlDIdx = screenMod.displayForKeyboard(signal[2]) or 1
        end
        local fg = proc.getForeground(ctrlDIdx)
        local now = computer.uptime()
        if fg then
          if lastCtrlC[ctrlDIdx] and (now - lastCtrlC[ctrlDIdx]) < 1.5 then
            proc.kill(fg, { kernel = true })  -- #FIX double-Ctrl+C reaps foreground
            lastCtrlC[ctrlDIdx] = nil
            log.warn("kernel", "Killed PID " .. fg .. " via double Ctrl+C on display " .. ctrlDIdx)
          else
            proc.signal(fg, "tos_interrupt")
            lastCtrlC[ctrlDIdx] = now
          end
        end
        signal = table.pack(nil)
      end

      -- ── Seat-local hotkey: Ctrl+T = System Monitor ──
      -- Ctrl+T sends char=20 in OC.
      -- #REV multi-seat — this used to run kernel.taskSwitcher MODALLY
      -- right here, so while ANY seat had the monitor open the kernel
      -- loop was blocked and every other seat (and services/timers) was
      -- frozen. Now it spawns the monitor as a seat-bound PROCESS: the
      -- kernel loop keeps ticking, other seats stay live, and the seat's
      -- input is routed to it as foreground like any full-screen program.
      if signal[1] == "key_down" and signal[3] == 20 then
        local ctrlTIdx = 1
        if screenMod.displayForKeyboard then
          ctrlTIdx = screenMod.displayForKeyboard(signal[2]) or 1
        end
        -- A registered Monitor HOST (the panels shell) shows the Monitor as
        -- a full-screen TAB — roomy and scrollable where the modal truncated.
        -- Focus the shell and tell it; it opens/focuses the tab. Guarded so
        -- a stale registration (shell died / logged out) falls through to
        -- the process fallback below instead of signalling a corpse.
        local host = monitorHosts[ctrlTIdx]
        local hp = host and proc.get and proc.get(host)
        if hp and hp.state ~= proc.STATE.DEAD and shellPIDs[ctrlTIdx] == host then
          proc.setForeground(host, ctrlTIdx, { kernel = true })
          ;(proc.signalKernel or proc.signal)(host, "tos_monitor")
          signal = table.pack(nil)
        else
        -- One monitor per seat: a second Ctrl+T while it's open is a no-op
        -- (the live one already has the seat's input). A dead-but-unreaped
        -- pid (body errored) must NOT wedge Ctrl+T, so check the state.
        local existing = monitorPIDs[ctrlTIdx]
        local ep = existing and proc.get and proc.get(existing)
        if ep and ep.state ~= proc.STATE.DEAD then
          signal = table.pack(nil)
        else
          -- #137/#138 — thread the seat's live session so the monitor's
          -- canAct policy sees the real principal.
          local seatSess = nil
          if usersmod and sessionTokens[ctrlTIdx] then
            seatSess = usersmod.getSession(sessionTokens[ctrlTIdx])
          end
          local seatToken = sessionTokens[ctrlTIdx]
          local shellPid  = shellPIDs[ctrlTIdx]
          local mp
          mp = proc.spawn("monitor@" .. ctrlTIdx, function()
            -- Run the switcher loop cooperatively (pull = yield); highlight
            -- and protect the SHELL, not ourselves; hide our own pid.
            local switched = kernel.taskSwitcher(ctrlTIdx, seatSess, {
              pull    = function() return coroutine.yield() end,
              fgPID   = shellPid,
              selfPid = mp,
            })
            -- Restore foreground: to the process we switched to (already
            -- set + focused inside), else back to the shell with a repaint.
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
          -- Route the seat's input to the monitor (kernel-authorized: the
          -- kernel loop has no caller PID anyway).
          proc.setForeground(mp, ctrlTIdx, { kernel = true })
          signal = table.pack(nil)
        end
        end -- host tab vs process fallback
      end

      -- ── Seat-local hotkey: Ctrl+B = send the program to the background ──
      -- Ctrl+B sends char=2 in OC. Intercepted HERE, in the kernel loop,
      -- for the same reason Ctrl+T and Ctrl+C are: a full-screen program
      -- holds the seat's input as foreground, so a key it is meant to
      -- obey can never be a key it receives. (It is also why the suspend
      -- key had to be one nothing else binds — Ctrl+Z is the editor's
      -- Undo, Ctrl+S/Q/E/O/X/V are all taken. Ctrl+B is free, and reads
      -- as "background".)
      --
      -- Suspending is just: hand the seat back to the shell. The program
      -- keeps its process — the scheduler's background lifecycle drops it
      -- to a reduced rate and eventually freezes it (see proc.bgShouldResume)
      -- — and Ctrl+T's switcher brings it back.
      if signal[1] == "key_down" and signal[3] == 2 then
        local bgIdx = 1
        if screenMod.displayForKeyboard then
          bgIdx = screenMod.displayForKeyboard(signal[2]) or 1
        end
        local fg = proc.getForeground(bgIdx)
        local shellPid = shellPIDs[bgIdx]
        -- Only meaningful when the foreground is something OTHER than the
        -- seat's own shell; Ctrl+B at a shell prompt must stay a no-op so
        -- it can't strand a seat with nothing in front.
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

      -- ── Hot-plug: seat added/removed ──
      if signal[1] == "tos_seat_changed" then
        -- Seat indices are STABLE across rebuild (screen.lua keeps a
        -- screen→index memory), so `removed` names exactly the seats to
        -- tear down and every surviving seat's shellPIDs/sessionTokens/
        -- monitorPIDs/displayForeground entries stay valid — previously
        -- rebuild() renumbered survivors and the survivor seat froze.
        local added, removed = screenMod.rebuild()
        for _, dIdx in ipairs(removed) do
          if shellPIDs[dIdx] then
            proc.kill(shellPIDs[dIdx], { kernel = true })  -- #FIX reap on seat unplug
            shellPIDs[dIdx] = nil
          end
          -- Full seat teardown: the per-seat Monitor process (Ctrl+T
          -- fallback) died with its display too — reap it or it lingers
          -- as an input-less orphan the supervisor can't explain.
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
        -- Clear in place (NOT rebind) — _G._TOS.shellPIDs aliases this table.
        for k in pairs(sessionTokens) do sessionTokens[k] = nil end
        for k in pairs(shellPIDs) do shellPIDs[k] = nil end

        -- #OOM — a machine with a display should NEVER reach zero processes
        -- unless we were told to power off (tos_shutdown sets running=false
        -- and breaks before here; global logout breaks too). Reaching here
        -- with `running` still true means the shell/login died unexpectedly —
        -- almost always OOM while loading the shell at login on a tight box.
        -- The old behaviour just powered off, which the operator sees as a
        -- crash. Instead: reclaim memory and recover. Try a bounded number of
        -- clean login respawns; if it keeps failing (no memory to even load
        -- the shell), fall back to the EMERGENCY shell so the operator can
        -- free space / read logs rather than being dropped to a dead machine.
        forceGC()
        local seats = (screenMod.count and screenMod.count()) or 0
        if running and seats > 0 then
          crashRespawns = crashRespawns + 1
          if crashRespawns <= 3 and computer.freeMemory() >= 64 * 1024 then
            log.warn("kernel", string.format(
              "Unexpected shell exit — recovering login on %d seat(s) [try %d/3, %dKB free]",
              seats, crashRespawns, math.floor(computer.freeMemory() / 1024)))
            -- #FIX (stable seat indices) — real indices, not 1..count.
            for _, dIdx in ipairs(screenMod.indices()) do spawnLoginProcess(dIdx) end
            -- Loop again instead of powering off.
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
    -- Emergency shell - run directly on main thread
    -- (NOT as a coroutine - signal delivery is unreliable through proc.tick)
    kernel.emergencyShell()
    running = false
  end

  kernel.shutdown()
end

-- ============================================================
-- Crash flight-recorder
-- ============================================================
-- OC kernel panics are opaque and vanish on reboot. crashDump persists a
-- post-mortem (reason, uptime, free RAM, the dmesg ring, an optional traceback)
-- to /var/crash so the operator can read it AFTER recovering — and drops a tiny
-- "NEW" marker that the next boot surfaces (checkLastCrash) then clears. Called
-- from the kernel's unrecoverable-shell path and the top-level panic handler.
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
  -- One-line unacknowledged-crash marker the next boot reports + clears.
  pcall(fs.writeFile, "/var/crash/NEW", tostring(reason or "unknown") .. " @ uptime " .. up .. "s")
  if okL and logMod and logMod.warn then logMod.warn("kernel", "Crash report saved: " .. path) end
  return wrote and path or false
end

-- At boot: if the last run left an unacknowledged crash marker, surface it once
-- (into the log / splash narration) and clear the marker. The full reports stay
-- in /var/crash for `crash` to read.
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

-- Data feed for the shell's scrollable `monitor` live tab: the SAME privilege-
-- filtered process + service view the Ctrl+T switcher shows, returned as
-- preformatted { text=, tone= } rows. The shell sandbox can't require kernel.*,
-- so the gathering + labelling happen here. Read-only (no kill/TSR — that stays
-- on Ctrl+T, which has the seat ACL checks).
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

-- The panels shell calls this (via _TOS.kernel) to declare that it hosts the
-- System Monitor as a full-screen TAB on its seat; Ctrl+T then focuses the
-- shell and signals "tos_monitor" instead of spawning the modal switcher.
-- Kernel-verified: only the seat's OWN shell process may register itself
-- (checked against the canonical shellPIDs map), so a user program can't
-- capture the hotkey. Pass false to unregister (panels → CLI handoff).
function kernel.setMonitorHost(enable)
  if not proc then return false end
  local p = proc.current and proc.current()
  if not (p and p.display and p.pid) then return false end
  local shells = _G._TOS and _G._TOS.shellPIDs
  if not (shells and shells[p.display] == p.pid) then return false end
  monitorHosts[p.display] = (enable ~= false) and p.pid or nil
  return true
end

-- Is the CALLING process the foreground on its own display? Lets a shell
-- suppress idle-timer repaints (status bar, live-tab refresh) while a
-- switched-to process owns the screen — background processes still get
-- nil resumes, so without this check their timers would paint over the
-- foreground program.
function kernel.isForeground()
  if not proc then return true end
  local p = proc.current and proc.current()
  if not p then return true end
  return proc.getForeground(p.display) == p.pid
end

-- Structured feed for the shell's INTERACTIVE Monitor tab: the same
-- privilege-filtered process + service view as monitorSnapshot, but with
-- the fields the tab needs for selection and actions (pid/state/canAct)
-- instead of preformatted text. The shell sandbox can't require kernel.*,
-- so assembly happens here. canAct is advisory (for greying the UI);
-- kernel.monitorAct re-checks policy against the caller's real principal.
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

-- Privileged actions for the Monitor tab: switch / kill / tsr (id = pid)
-- and svc start-stop toggle (id = service name). The caller's identity is
-- the CALLING PROCESS's kernel-stamped principal and display — nothing
-- privilege-bearing is accepted as an argument, so no forged session can
-- act above the seat it runs on. Policy is monitor.canAct, the same rules
-- the Ctrl+T switcher enforces. Returns (true) or (false, reason).
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
  -- Visibility gate, mirroring the list filter: below admin you can only
  -- name your own (or kernel/unowned) processes at all.
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
    -- Suspending the CALLER (the shell hosting the Monitor tab) would
    -- freeze the seat instantly — the shell stops being scheduled with
    -- nothing left to wake it. Kill and switch already refuse self.
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

-- ============================================================
-- Task Switcher Dialog (Ctrl+T)
-- ============================================================

function kernel.taskSwitcher(displayIdx, seatSession, opts)
  opts = opts or {}
  -- #REV multi-seat — `opts.pull` lets this run as a SEAT PROCESS instead
  -- of modally in the kernel loop (where it froze every other seat while
  -- open). In process mode pull = coroutine.yield (proc.tick routes the
  -- seat's input here as foreground) and the kernel loop keeps ticking.
  -- Default = the old blocking pull, so any legacy caller is unchanged.
  local procMode = opts.pull ~= nil
  local pull = opts.pull or function() return computer.pullSignal(0.5) end
  local selfPid = opts.selfPid   -- monitor's own pid: hide it from its list
  -- Resolve the display to draw on: seat-local proxy or global display
  local screenMod = require("kernel.screen")
  local dsp = displayIdx and screenMod.displayProxy(displayIdx) or display
  if not dsp or not proc then return end

  -- #137/#138 — identify the principal that opened the switcher. Without
  -- this the switcher defaulted to kernel-initiated privileges (because
  -- proc.kill() checks currentPID, which is nil inside the kernel loop),
  -- letting any seat kill/TSR any process system-wide. Resolve the seat's
  -- live session; fall back to the boot session only when nothing is
  -- logged in (emergency / pre-auth).
  local usersmod = _G._TOS.users
  local seatUser = seatSession and seatSession.user or nil
  local seatTier = seatSession and seatSession.tier or 0

  local mon = require("kernel.monitor")
  local okRC, rcMod = pcall(require, "kernel.rc")
  local W, H = dsp.getSize()
  local T = dsp.getTheme()

  -- The visible PROCESS set, with the same privilege filtering the old task
  -- switcher used: seat-local processes (+ unowned kernel ones); non-admins see
  -- only their own (and kernel) processes; admin+ sees everything on the seat.
  -- A function (not a one-shot) so the monitor can re-snapshot live.
  local function visibleProcs()
    local procs = proc.list()
    if displayIdx then
      local f = {}
      for _, p in ipairs(procs) do
        -- Hide the monitor's OWN process from its list (switching to /
        -- killing yourself is meaningless and confusing).
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

  -- rc.d services — shown (and controllable) for admin+ only, so a guest seat
  -- can't enumerate the machine's service topology.
  local function visibleServices()
    if seatTier < 2 or not (okRC and rcMod and rcMod.list) then return {} end
    local ok, svcs = pcall(rcMod.list)
    return (ok and type(svcs) == "table") and svcs or {}
  end

  -- Kill/TSR policy: shared with the Monitor tab (kernel.monitorAct) via
  -- monitor.canAct so the two surfaces can't drift.
  local function canAct(pEntry)
    return mon.canAct(seatTier, seatUser, displayIdx, pEntry)
  end

  -- FULL-SCREEN layout (polish round 4): the old centred 66-column box
  -- truncated process names and left stale shell content peeking around
  -- its edges when it closed. The modal now covers the whole screen like
  -- the Monitor tab; whoever regains the foreground afterwards repaints
  -- over it (tos_focus — the CLI shell full-redraws on it, panels
  -- repaint their chrome). Below the vitals header + column header sits
  -- the unified, scrollable list (processes, then a Services section);
  -- a help line runs along the bottom inside the border.
  local dx, dy = 1, 1
  local dw, dh = W, H
  -- Column budget: everything but the process name is fixed width
  -- (mark 1 + pid 4 + owner 8 + state 7 + cpu 6 + gaps = 30 inside the
  -- borders), so the name column absorbs the extra screen width instead
  -- of clipping at the old hard-coded 26.
  local nameW = math.max(20, dw - 2 - 30)
  local svcW  = math.max(27, dw - 2 - 22)
  local listTop = dy + 4               -- vitals(dy+1), blank(dy+2), colhdr(dy+3)
  local listH   = math.max(1, dh - 6)  -- rows available for the unified list

  -- The foreground to HIGHLIGHT/protect: in process mode the seat's real
  -- foreground is the monitor itself, so the caller passes the shell pid.
  local fgPID  = opts.fgPID or proc.getForeground(displayIdx)
  local switchedPid = nil   -- set if the operator switches to a process
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

  -- Re-snapshot processes + services into the unified row list, keeping the
  -- selection valid (and never resting on a header). False = nothing to show.
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
    -- Vitals.
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
          -- COLUMN math, not byte math: "─" is 3 UTF-8 bytes but ONE
          -- column, so the old #bar under-counted the prefix by 4 and
          -- dsp.fit then byte-sliced a ─ in half — the "▓…" artifact
          -- on the Services rule (operator screenshot, v1.4.0 round).
          -- r.text is ASCII (a section name), so its # is its columns.
          local width = dw - 2
          local prefixCols = 4 + #r.text + 1        -- " ── " + text + " "
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
        else  -- svc
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
      if ch == 17 or ch == 113 then            -- Ctrl+Q / q = close
        break
      elseif co == 200 then                    -- Up
        sel = mon.nextSelectable(rows, sel, -1); clampScroll(); drawContent()
      elseif co == 208 then                    -- Down
        sel = mon.nextSelectable(rows, sel, 1); clampScroll(); drawContent()
      elseif co == 201 then                    -- PgUp
        for _ = 1, listH do sel = mon.nextSelectable(rows, sel, -1) end; clampScroll(); drawContent()
      elseif co == 209 then                    -- PgDn
        for _ = 1, listH do sel = mon.nextSelectable(rows, sel, 1) end; clampScroll(); drawContent()
      else
        local r = rows[sel]
        if r and r.kind == "proc" then
          local p = r.p
          if co == 28 then                     -- Enter = switch to this process
            -- Kernel-authorized (opts.kernel): the monitor's own canAct
            -- gate is the policy; the underlying call stays god-mode as it
            -- was when this ran modally in the kernel loop.
            proc.setForeground(p.pid, displayIdx, { kernel = true })
            -- Kernel context (no caller PID): proc.signal would be denied, so use
            -- the kernel-acknowledged path or the switched-to process won't repaint.
            (proc.signalKernel or proc.signal)(p.pid, "tos_focus")
            log.info("kernel", "Switched to PID " .. p.pid .. " (" .. tostring(p.name) .. ")")
            switchedPid = p.pid
            break
          elseif ch == 107 or ch == 75 then    -- k/K = kill (not the shell you're in)
            if p.pid ~= fgPID and canAct(p) then
              -- canAct() enforced the seat principal's privilege; the kernel-loop
              -- kill has no currentPID, so acknowledge kernel.
              proc.kill(p.pid, { kernel = true })
              log.warn("kernel", "Killed PID " .. p.pid .. " (" .. tostring(p.name)
                .. ") from monitor by " .. tostring(seatUser or "kernel"))
              if not rebuild() then break end
              drawContent()
            end
          elseif ch == 116 or ch == 84 then    -- t/T = toggle TSR (suspend/resume)
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
          if co == 28 or ch == 115 or ch == 83 then    -- Enter / s/S = start-stop
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
      -- Idle tick (pull timeout / nil resume): refresh live vitals +
      -- CPU/state so the monitor updates without a keypress. This is what
      -- makes it "live".
      rebuild(); drawContent()
    end
  end

  if procMode then
    -- The spawning wrapper owns foreground restoration + redraw (it knows
    -- the shell pid and whether we switched). Just report what happened.
    return switchedPid
  end

  -- Modal (legacy) path: signal whatever is foreground now to redraw over
  -- where the switcher drew. Kernel loop has no caller PID, so use the
  -- kernel-acknowledged signal path.
  local fg = proc.getForeground(displayIdx)
  if fg then (proc.signalKernel or proc.signal)(fg, "tos_focus") end
  return switchedPid
end

-- ============================================================
-- Emergency Shell (when main shell can't load)
-- ============================================================

function kernel.emergencyShell()
  if not display then return end

  -- ── Emergency auth gate ───────────────────────────────
  local usersmod = _G._TOS.users
  local W0, H0 = display.getSize()
  local T0 = display.getTheme()

  display.clear(T0.bg)
  display.set(2, 2, "TOS EMERGENCY - Auth Required", T0.error, T0.bg)

  -- Same principle as minimalAuth: without the user subsystem we have
  -- no way to verify a password, so we refuse to enter the shell rather
  -- than granting unauthenticated access.
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
    -- #BUG-1 — emergency shell is single-seat, setCurrent=true is correct.
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

  -- ── Emergency shell ───────────────────────────────────

  local W, H = display.getSize()
  local T = display.getTheme()
  -- Line buffer: stores {text, color} for every line ever printed
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
        if code == 28 then  -- Enter
          return buf
        elseif code == 14 then  -- Backspace
          if #buf > 0 then buf = buf:sub(1, -2) end
        elseif char and char >= 32 and char < 127 then
          buf = buf .. string.char(char)
        end
      end
    end
  end

  -- #SEC M17 — the emergency shell ran ls/cat through raw kernel.fs,
  -- which bypassed every ACL. The shell IS root-authenticated (the
  -- minimalAuth gate above forces a root password check before we get
  -- here) so it has the privilege to read anything, but we want the
  -- same audit posture as the regular shell: writes go through the
  -- protected-target gate, /etc/users.dat reads are logged, etc.
  -- Resolve securefs lazily so this code stays callable even when the
  -- shell falls through to emergency very early in boot.
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
      -- #SEC M17 — prefer securefs; fall through to raw fs only when
      -- securefs isn't loaded yet (very early boot).
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
        -- #SEC M17 — securefs.readFile applies ACL + audit logging
        -- just like the normal shell. Root tier reads through cleanly.
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

-- ============================================================
-- System verification (checks all expected files)
-- ============================================================

function kernel.verifySystem(printFn)
  printFn = printFn or function() end

  -- Resolve colors via display theme if available
  local cOK  = display and display.c("success") or 0xFFFFFF
  local cWrn = display and display.c("warning") or 0xFFFFFF
  local cErr = display and display.c("error") or 0xFFFFFF
  local cDim = display and display.c("dim") or 0xFFFFFF

  -- Load file list from centralized manifest (single source of truth)
  local allFiles
  do
    local ok2, manifest = pcall(require, "system_manifest")
    if ok2 and type(manifest) == "table" then
      allFiles = manifest
    else
      -- Fallback: minimal list if manifest missing
      allFiles = {
        { path = "/init.lua",              critical = true },
        { path = "/tos/kernel/init.lua",   critical = true },
        { path = "/tos/shell/init.lua",    critical = true },
      }
      printFn("  WARN: system_manifest.lua not found, using minimal verify list", cWrn)
    end
  end

  local ok, missing, damaged = 0, 0, 0

  -- #SEC C1 — manifest entries may declare a SHA-256 `hash` field
  -- (64 hex). When present, verifySystem checks every listed file's
  -- on-disk content against the manifest claim. Mismatches are counted
  -- as `damaged`, just like a syntax error. Combined with the manifest
  -- hash anchored in EEPROM (kernel.anchorManifestHash / kernel.verifyManifestHash),
  -- this gives a checkable chain: BIOS verifies /init.lua parses, kernel
  -- verifies the manifest matches its EEPROM anchor, manifest verifies
  -- every other file's content.
  local cryptoMod = nil
  do local okC, c = pcall(require, "kernel.crypto"); if okC then cryptoMod = c end end
  local hashMismatch = 0

  -- #MEM — STREAM wherever possible. Reading a file whole costs ~2x its
  -- size transiently (chunk table + table.concat) and this sweep runs at
  -- the WORST times (emergency shell, `verify` on a wedged box) — the old
  -- whole-file fs.readFile here is what escalated a low-memory shell
  -- failure into a kernel panic (crash-24/41). Only the manifest-hash
  -- case still holds full content (the data card's hash API is one-shot);
  -- syntax and readability checks now peak at one 4KB chunk.
  -- #BUG (emulator round) — read fully FIRST, then compile from memory. The
  -- reader handed to load() must never perform I/O: component calls can
  -- yield (OC's direct-call budget), load() is a C function, and a yield
  -- inside its reader is a fatal "attempt to yield across a C-call
  -- boundary". Same fix as /init.lua's loadModuleFile; see the long note
  -- there. We still skip the table.concat, so the joined second copy of the
  -- file never exists.
  local function streamLoad(path)
    local h = fs.open(path, "r")
    if not h then return nil, nil, "unreadable" end
    local chunks, n = {}, 0
    local readOk, readErr = pcall(function()
      while true do
        local chunk = h:read(4096)
        if chunk == nil then break end
        if #chunk > 0 then n = n + 1; chunks[n] = chunk end  -- "" would end it early
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
    if not okL then return nil, fn, "raised" end  -- compile RAISED (OOM)
    return fn, lerr, nil
  end

  for _, file in ipairs(allFiles) do
    if fs.exists(file.path) then
      do
        -- #SEC C1 — content hash check, if the manifest claims one. The
        -- one case that must read the file whole (one-shot hash API).
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
        -- #REV — only Lua files get a SYNTAX check. The manifest also lists
        -- data files (man pages /usr/man/*.man, configs, etc.); running
        -- load() on those reported every one as "BAD (syntax)" even though
        -- a manual page is supposed to be prose, not code. For non-.lua
        -- files, existence + readability (+ the optional hash check above)
        -- is the whole integrity story.
        if not file.path:match("%.lua$") then
          -- Full-read probe in discarded 4KB chunks: same "entire file is
          -- readable" guarantee fs.readFile gave, without holding it.
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
      -- Reclaim transient garbage before the next (potentially large) file.
      -- OC sandboxes don't expose collectgarbage by default, so guard the
      -- call rather than assuming it's present — otherwise verify blows up
      -- with "attempt to call a nil value (global 'collectgarbage')".
      if type(collectgarbage) == "function" then
        pcall(collectgarbage, "collect")
      end
    else
      local tag = file.critical and "MISS" or "skip"
      local color = file.critical and cErr or cWrn
      printFn("  " .. tag .. " " .. file.path, color)
      missing = missing + 1
    end
    ::continue_verify::
  end

  printFn("", cDim)
  if hashMismatch > 0 then
    printFn(string.format(
      "Result: %d OK, %d missing, %d damaged (incl. %d HASH MISMATCH)",
      ok, missing, damaged, hashMismatch), cErr)
  else
    printFn(string.format("Result: %d OK, %d missing, %d damaged", ok, missing, damaged), cDim)
  end

  return missing == 0 and damaged == 0
end

-- ============================================================
-- #SEC C1 — manifest hash anchoring in EEPROM data field
-- ============================================================
-- The EEPROM exposes a 256-byte `data` field that BIOS code can read at
-- boot (via component.eeprom.getData / setData). We use the first 64
-- bytes of it to anchor the running system's manifest hash. On next
-- boot, kernel.verifyManifestHash() reads the EEPROM data, computes the
-- live manifest's hash, and refuses to continue boot if they don't
-- match (unless a held-key recovery override is asserted).

local function readManifestSource()
  -- Manifest lives at /tos/system_manifest.lua. Read raw bytes (not
  -- the parsed table) so the hash covers exactly what's on disk.
  local path = "/tos/system_manifest.lua"
  if not fs.exists(path) then return nil, "manifest missing" end
  return fs.readFile(path)
end

--- Compute the running manifest's SHA-256 hex digest. Returns
--- (hexDigest, nil) on success, (nil, errMsg) on failure.
function kernel.computeManifestHash()
  local source, err = readManifestSource()
  if not source then return nil, err end
  local okC, cryptoMod = pcall(require, "kernel.crypto")
  if not okC or not cryptoMod or not cryptoMod.hash then
    return nil, "crypto unavailable"
  end
  return cryptoMod.hash(source)
end

--- Write the current manifest hash into the EEPROM data field. Operator
--- runs this once after a clean install (or after a verified upgrade).
--- On subsequent boots, verifyManifestHash() refuses to continue on
--- mismatch.
function kernel.anchorManifestHash()
  local digest, err = kernel.computeManifestHash()
  if not digest then return false, err end
  local component = require("component")
  local eepromAddr = component.list("eeprom")()
  if not eepromAddr then return false, "no EEPROM" end
  local ep = component.proxy(eepromAddr)
  if not ep.setData then return false, "EEPROM has no setData" end
  -- LAYOUT (#SEC C1): the EEPROM data field's FIRST LINE is the BIOS boot
  -- address; our anchor goes on a second line as "TOS1:<64 hex>".
  --
  -- This used to write the anchor at the FRONT, which silently destroyed
  -- the stored boot address — the BIOS reads that field verbatim as the
  -- address, so anchoring left the machine unable to find its own boot
  -- device and prompting "Boot drive changed" on every power-on. The
  -- doctor was recommending it, so the advice was a trap; nobody hit it
  -- only because there was no way to run the function.
  local existing = ep.getData() or ""
  local bootAddr = existing:match("^[^\n]*") or ""
  local payload = bootAddr .. "\nTOS1:" .. digest
  if #payload > 256 then return false, "EEPROM data field too small" end
  ep.setData(payload)
  return true, digest
end

--- Remove the anchor, keeping the boot address. Used when an operator is
--- about to upgrade (the hash will legitimately change) or wants to drop
--- the check entirely.
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

--- Verify the running manifest's hash against the EEPROM-anchored
--- value. Returns (true) on match, (false, reason) on mismatch or
--- absence. The kernel boot path calls this once and either continues
--- or halts based on the result.
function kernel.verifyManifestHash()
  local component = require("component")
  local eepromAddr = component.list("eeprom")()
  if not eepromAddr then return false, "no EEPROM" end
  local ep = component.proxy(eepromAddr)
  if not ep.getData then return false, "EEPROM has no getData" end
  local existing = ep.getData() or ""
  -- The anchor lives on its own line after the boot address (see
  -- anchorManifestHash). Accept a legacy front-of-field anchor too, so a
  -- machine written by the older layout still verifies.
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

-- ============================================================
-- Kernel API (exposed to processes)
-- ============================================================

function kernel.getLog()      return log end
function kernel.getHAL()      return hal end
function kernel.getEvent()    return event end
function kernel.getProc()     return proc end
--- Return the user-facing filesystem (permission-checked).
-- Historically this returned the raw `kernel.fs`; as of Phase 1 it
-- returns securefs so every caller inherits ACL enforcement.
function kernel.getFS()
  return _G._TOS.securefs or fs
end
function kernel.getDisplay()  return display end
function kernel.getDisplayIdx() return nil end  -- global kernel has no specific display
function kernel.getUsers()    return _G._TOS.users end
function kernel.getSecureFS() return _G._TOS.securefs end
function kernel.getConfig()   return _G._TOS.config end
function kernel.getPower()    return _G._TOS.power end
function kernel.getSwap()     return _G._TOS.swap end
function kernel.getJBOD()     return _G._TOS.jbod end  -- nil unless advanced.jbod
function kernel.getNet()      return _G._TOS.net end
function kernel.getCompress()
  -- Prefer the boot-inited instance; lazily load+detect on a minimal box
  -- (where the swap/compress stage was skipped) so the command still works.
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

  -- Stop cron scheduler.
  -- #MEM — _TOS.cron may be a LAZY PROXY (the kernel defers the scheduler on
  -- a box with no saved jobs), and the proxy is truthy. Reading `.shutdown`
  -- off it would LOAD and initialise cron — registering a tick timer — purely
  -- to stop it again, during shutdown, on the machines least able to afford
  -- it. Ask package.loaded instead: only a scheduler that actually ran needs
  -- stopping. Same reasoning for any other lazily-slotted subsystem here.
  local cronMod = package and package.loaded and package.loaded["kernel.cron"]
  if type(cronMod) == "table" and cronMod.shutdown then
    pcall(cronMod.shutdown)
  end

  -- Stop startup services
  if _G._TOS.rc then
    pcall(_G._TOS.rc.stopAll)
  end

  -- Every stage below is pcall'd (#REV review finding #4): an error in
  -- any of them — modem pulled mid-net.shutdown, screen yanked before
  -- the farewell draw — used to propagate OUT of kernel.shutdown before
  -- the clean-shutdown stamp and computer.shutdown() ran. Result: a
  -- half-dead machine (processes killed, still "running") and a spurious
  -- "PREVIOUS SHUTDOWN WAS UNSAFE" on the next boot. Nothing between
  -- here and the stamp may be allowed to throw.

  -- Kill all processes
  if proc then
    for _, p in ipairs(proc.list()) do
      pcall(proc.kill, p.pid, { kernel = true })  -- #FIX reap on shutdown
    end
  end

  -- Shut down network
  if _G._TOS.net then
    pcall(_G._TOS.net.shutdown)
  end

  -- Flush + detach the persistent log so the final 30s of entries
  -- (whatever didn't make the last interval tick) land on disk before
  -- we yank the filesystem.
  pcall(log.flush)
  pcall(log.detachFile)

  -- Clear screen
  if display then
    pcall(function()
      local T = display.getTheme()
      display.clear(T.bg)
      display.set(2, 2, reboot and "Rebooting TOS..." or "TOS shut down.", T.success, T.bg)
      display.set(2, 3, "Goodbye!", T.dim, T.bg)
    end)
  end

  -- Shutdown audio feedback
  if _G._TOS.audio then pcall(_G._TOS.audio.shutdown) end

  -- Mark a CLEAN shutdown as the very last persistent act, after every
  -- other subsystem has flushed. The next boot reads this and knows the
  -- machine was powered off deliberately rather than cut off.
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

-- ============================================================
-- Headless Main Loop (server blades / dedicated service hosts)
-- ============================================================
-- Runs in place of loginAndStartShell when the device has no GPU/screen.
-- No login screen, no shell TUI. The kernel auto-starts as _kernel_ and
-- enters a service-tick loop. Network commands (rsh / remote) are the
-- primary way to interact with a headless server.
--
-- Recovery: if a screen+keyboard are hot-plugged, the loop detects it
-- and offers to switch to interactive mode.

function kernel.headlessMain()
  running = true

  local usersmod = _G._TOS.users

  -- Bind the kernel session so all service processes inherit root
  -- permissions (securefs, securefs.forSession, etc.)
  if usersmod then
    _G._TOS.bootSession = usersmod.kernelSession()
  end

  log.info("kernel", "Entering headless service loop")

  -- Ensure network is up — a server without a modem is user-error.
  if not _G._TOS.net then
    log.warn("kernel", "WARNING: headless server has no network!")
    log.warn("kernel", "Install a modem or linked card so the server can be reached.")
  end

  -- Headless tick: pump events, run process scheduler, handle signals.
  while running do
    local signal = table.pack(event.pull(0.5))

    if signal[1] == "tos_shutdown" then
      running = false
      break
    end

    -- Hot-plug recovery: if a screen+gpu+keyboard appear, offer to
    -- switch to interactive mode. This handles the case where a user
    -- physically attaches a terminal to diagnose issues.
    if signal[1] == "component_added" then
      local ctype = signal[3]
      if ctype == "screen" or ctype == "gpu" or ctype == "keyboard" then
        log.info("kernel", "Display hardware detected — checking for interactive switch")
        -- No settle-wait here (#REV review finding #8): the old bare
        -- computer.pullSignal(0.5) swallowed one signal RAW — bypassing
        -- listeners, timers, and process queues. It's also unnecessary:
        -- the check below reads live component.list, and if a piece is
        -- still missing, ITS component_added re-triggers this branch.
        local component2 = require("component")
        local hasGPU    = component2.list("gpu")() ~= nil
        local hasScreen = component2.list("screen")() ~= nil
        local hasKB     = component2.list("keyboard")() ~= nil
        if hasGPU and hasScreen and hasKB then
          log.info("kernel", "Full display hardware present — switching to interactive mode")
          running = false
          -- Re-init display for real this time
          display = require("kernel.display")
          local gpu = component2.proxy(component2.list("gpu")())
          if gpu then
            -- Honor the screen resolution policy (density-based auto by
            -- default) rather than forcing the hardware max.
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

    -- Tick processes (services, background tasks, net handlers)
    proc.tick(signal.n > 0 and signal or nil)
  end

  kernel.shutdown()
end

return kernel
