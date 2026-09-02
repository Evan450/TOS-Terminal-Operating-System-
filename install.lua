local component = require("component")
local computer = require("computer")
local term = require("term")

local fs = nil
pcall(function() fs = require("filesystem") end)

local gpu = component.gpu

local function color(fg)
  if gpu and gpu.setForeground then
    pcall(gpu.setForeground, fg)
  end
end

local function ok(msg)
  color(0x00FF00); print("  + " .. msg); color(0xFFFFFF)
end

local function warn(msg)
  color(0xFFFF00); print("  ! " .. msg); color(0xFFFFFF)
end

local function fail(msg)
  color(0xFF0000); print("  X " .. msg); color(0xFFFFFF)
end

local function ask(question, options, default)
  color(0xFFFF00)
  io.write(question)
  if options then
    color(0xAAAAAA)
    io.write(" [" .. table.concat(options, "/") .. "]")
  end
  if default then
    color(0x888888)
    io.write(" (default: " .. default .. ")")
  end
  color(0xFFFFFF)
  io.write(": ")

  local answer
  if term and term.read then
    local ok2, result = pcall(term.read)
    if ok2 then
      answer = result
      if answer then answer = answer:gsub("\n$", "") end
    end
  else
    answer = io.read()
  end
  if not answer or answer == "" then return default end
  return answer
end

local function confirm(question)
  local answer = ask(question, {"y", "n"}, "y")
  return answer and (answer:lower() == "y" or answer:lower() == "yes")
end

local INSTALLER_VERSION = "1.4.0"

local RUNTIME_DIRS = {
  "/tos", "/tos/kernel", "/tos/kernel/net", "/tos/shell",
  "/tos/compat", "/tos/peripheral", "/tos/shell/panels",
  "/etc", "/etc/rc.d",
  "/home", "/public", "/root",
  "/usr", "/usr/bin", "/usr/lib", "/usr/modules",
  "/var", "/var/log", "/var/run", "/var/pkg", "/var/pkg/installed",
  "/tmp",
}

local LOGO_MARK = {
  "████████  ████████  ████████",
  "   ██     ██    ██  ██      ",
  "   ██     ██    ██  ████████",
  "   ██     ██    ██        ██",
  "   ██     ████████  ████████",
}

local function header()
  color(0x00AAFF)
  for _, ln in ipairs(LOGO_MARK) do print("   " .. ln) end
  color(0xFFFFFF); print()
  color(0x00FF66); print("   Strata Systems LLC"); color(0xFFFFFF)
  color(0xAAAAAA)
  print("   Terminal Operating System — Setup v" .. INSTALLER_VERSION)
  color(0xFFFFFF)
  print()
end

local function findInstallDisk(explicitSrc)
  if not fs then return nil end

  if type(explicitSrc) == "string" and explicitSrc ~= "" then
    local p = explicitSrc:sub(-1) == "/" and explicitSrc:sub(1, -2) or explicitSrc
    if fs.exists(p .. "/tos/kernel/init.lua") then return p end
  end

  local scriptPath = os.getenv and os.getenv("_") or nil
  if scriptPath then
    local dir = scriptPath:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and fs.exists(dir .. "/tos/kernel/init.lua") then
      return dir
    end
  end

  local bootAddr = computer.getBootAddress()
  for addr in component.list("filesystem") do
    if addr ~= bootAddr then
      local okP, px = pcall(component.proxy, addr)
      if not okP then px = nil end
      local okE1, hasKernel = pcall(function() return px and px.exists("/tos/kernel/init.lua") end)
      local okE2, hasInstall = pcall(function() return px and px.exists("/install.lua") end)
      if okE1 and okE2 and hasKernel and hasInstall then

        if fs.mounts then
          local okM, mounts = pcall(fs.mounts)
          if okM and mounts then
            for mnt, proxy in mounts do
              if proxy.address == addr then
                return tostring(mnt)
              end
            end
          end
        end
      end
    end
  end

  return nil
end

local function surveyHardware()
  local hw = {}
  hw.totalMem = computer.totalMemory()
  hw.freeMem = computer.freeMemory()
  hw.memKB = math.floor(hw.totalMem / 1024)

  if gpu then
    local w, h = gpu.maxResolution()
    hw.maxW, hw.maxH = w, h
    if w >= 160 then hw.gpuTier = 3
    elseif w >= 80 then hw.gpuTier = 2
    else hw.gpuTier = 1 end
  end

  local bootAddr = computer.getBootAddress()
  local ok, bootFS = pcall(component.proxy, bootAddr)
  if not ok or not bootFS then bootFS = { spaceTotal = function() return 0 end, spaceUsed = function() return 0 end } end
  hw.diskTotal = bootFS.spaceTotal()
  hw.diskFree = math.max(0, hw.diskTotal - bootFS.spaceUsed())
  hw.diskKB = math.floor(hw.diskTotal / 1024)
  hw.diskFreeKB = math.floor(hw.diskFree / 1024)

  hw.hasModem, hw.hasWireless, hw.hasTunnel, hw.hasDataCard = false, false, false, false
  hw.hasGPU, hw.hasScreen, hw.hasKeyboard = false, false, false
  for addr, ctype in component.list() do
    if ctype == "modem" then
      hw.hasModem = true
      pcall(function() hw.hasWireless = component.proxy(addr).isWireless() end)
    elseif ctype == "tunnel" then hw.hasTunnel = true
    elseif ctype == "data" then hw.hasDataCard = true
    elseif ctype == "gpu" then hw.hasGPU = true
    elseif ctype == "screen" then hw.hasScreen = true
    elseif ctype == "keyboard" then hw.hasKeyboard = true
    end
  end
  return hw
end

local function printHardwareReport(hw)
  color(0x00AAFF)
  print("--- Hardware Detected ---")
  color(0xAAAAAA)
  print(string.format("  RAM:      %dKB total (%dKB free)", hw.memKB, math.floor(hw.freeMem / 1024)))
  print(string.format("  GPU:      Tier %d (%dx%d max)", hw.gpuTier or 1, hw.maxW or 50, hw.maxH or 16))
  print(string.format("  Disk:     %dKB total (%dKB free)", hw.diskKB, hw.diskFreeKB))
  print(string.format("  Network:  %s", hw.hasModem and (hw.hasWireless and "Wireless" or "Wired") or "None"))
  if hw.hasTunnel then print("  Tunnel:   Linked card detected") end
  print(string.format("  Crypto:   %s", hw.hasDataCard and "Hardware (data card)" or "Software"))
  color(0xFFFFFF)
  print()
  if hw.memKB < 128 then warn("Critically low memory! TOS may be unstable.")
  elseif hw.memKB < 256 then warn("Low memory. Some features may be limited.") end
  if hw.diskFreeKB < 80 then warn("Low disk space. TOS needs ~80KB minimum.") end
  print()
end

local function loadManifest(srcDisk)
  local path = srcDisk .. "/tos/system_manifest.lua"
  if not fs.exists(path) then return nil, "no manifest at " .. path end
  local h = io.open(path, "r")
  if not h then return nil, "cannot open manifest" end
  local source = h:read("*a")
  h:close()
  if not source then return nil, "empty manifest" end

  if #source > 256 * 1024 then
    return nil, "manifest exceeds 256 KB sanity cap"
  end
  local okS, ser = pcall(require, "kernel.serialize")
  if okS and ser and ser.decode then
    local data, derr = ser.decode(source, { maxBytes = 256 * 1024 })
    if data and type(data) == "table" then
      return data
    elseif data == nil then

      warn("manifest serialize.decode failed (" .. tostring(derr) ..
        "); falling back to constrained load()")
    end
  end

  local fn, err = load(source, "=manifest", "t", { })
  if not fn then return nil, "manifest parse error: " .. tostring(err) end
  local ok2, result = pcall(fn)
  if not ok2 then return nil, "manifest run error: " .. tostring(result) end
  if type(result) ~= "table" then return nil, "manifest did not return a table" end
  return result
end

local function preInstallSafetyCheck(forceWipe)
  if forceWipe then return true end
  if fs.exists("/etc/users.dat") then
    local h = io.open("/etc/users.dat", "r")
    if h then
      local content = h:read("*a"); h:close()
      if content and #content > 0 then
        warn("Existing TOS install detected (/etc/users.dat is populated).")
        warn("Re-installing will overwrite users, configuration, and the")
        warn("system tree but will NOT delete user data under /home or /tmp.")
        color(0xFFFF00); io.write("Type FORCE-WIPE to confirm: "); color(0xFFFFFF)
        local typed = io.read() or ""
        if typed ~= "FORCE-WIPE" then
          fail("Install aborted by safety check.")
          return false
        end
      end
    end
  end
  return true
end

local function copyFileChunked(src, dst)
  local ih = io.open(src, "r")
  if not ih then return false, "open source" end
  local oh = io.open(dst, "w")
  if not oh then ih:close(); return false, "open dest" end
  while true do
    local chunk = ih:read(4096)
    if not chunk then break end
    local wOk, wErr = pcall(function() oh:write(chunk) end)
    if not wOk then ih:close(); oh:close(); return false, "write: " .. tostring(wErr) end
  end
  ih:close(); oh:close()
  return true
end

local function verifyCopy(srcDisk, manifest)
  local missing, sized = {}, {}
  for _, entry in ipairs(manifest) do
    local target = entry.path
    if not fs.exists(target) then
      missing[#missing + 1] = target
    else
      local srcSize = fs.size(srcDisk .. target) or 0
      local dstSize = fs.size(target) or 0
      if srcSize ~= dstSize then
        sized[#sized + 1] = string.format("%s (src=%d dst=%d)", target, srcSize, dstSize)
      end
    end
  end
  return missing, sized
end

local function copyFromDisk(srcDisk)

  local manifest, mErr = loadManifest(srcDisk)
  if not manifest then
    fail("Cannot load install manifest: " .. tostring(mErr))
    return false
  end
  ok("Manifest loaded: " .. #manifest .. " files declared")
  print()

  color(0x00AAFF); print("--- Creating directories ---"); color(0xFFFFFF)
  local dirSeen = {}
  for _, entry in ipairs(manifest) do
    local dir = entry.path:match("^(.+)/[^/]+$")
    while dir and dir ~= "" and not dirSeen[dir] do
      dirSeen[dir] = true
      if not fs.isDirectory(dir) then fs.makeDirectory(dir) end
      dir = dir:match("^(.+)/[^/]+$")
    end
  end

  for _, d in ipairs(RUNTIME_DIRS) do
    if not fs.isDirectory(d) then fs.makeDirectory(d) end
  end
  ok("Directory structure created")
  print()

  color(0x00AAFF); print("--- Copying system files ---"); color(0xFFFFFF)
  local copied, failed = 0, 0
  local errs = {}
  for _, entry in ipairs(manifest) do
    local src = srcDisk .. entry.path
    local dst = entry.path
    if not fs.exists(src) then
      failed = failed + 1
      errs[#errs + 1] = "missing on disk: " .. entry.path
    else
      local cok, cerr = copyFileChunked(src, dst)
      if cok then copied = copied + 1
      else failed = failed + 1; errs[#errs + 1] = entry.path .. ": " .. tostring(cerr) end
    end
  end

  print()
  if failed == 0 then
    ok("Copied " .. copied .. " files")
  else
    fail("Copied " .. copied .. " files, " .. failed .. " FAILED:")
    for i = 1, math.min(5, #errs) do warn("  " .. errs[i]) end
    if #errs > 5 then warn("  (+" .. (#errs - 5) .. " more)") end
  end
  print()

  if failed == 0 then
    color(0x00AAFF); print("--- Verifying copy ---"); color(0xFFFFFF)
    local missing, sized = verifyCopy(srcDisk, manifest)
    if #missing == 0 and #sized == 0 then
      ok("All " .. #manifest .. " files verified")
    else
      if #missing > 0 then
        fail(#missing .. " files MISSING after copy:")
        for i = 1, math.min(5, #missing) do warn("  " .. missing[i]) end
        failed = failed + #missing
      end
      if #sized > 0 then
        fail(#sized .. " files have WRONG SIZE after copy:")
        for i = 1, math.min(5, #sized) do warn("  " .. sized[i]) end
        failed = failed + #sized
      end
    end
    print()
  end

  return failed == 0
end

local OPENOS_ONLY_TREES = { "/bin", "/lib" }
local function hasOpenOsLeftovers()
  if not fs then return false end
  for _, d in ipairs(OPENOS_ONLY_TREES) do
    if fs.exists(d) then return true end
  end
  return false
end
local function cleanOpenOsLeftovers()
  local removed = {}
  if not fs then return removed end
  for _, d in ipairs(OPENOS_ONLY_TREES) do
    if fs.exists(d) then

      local okR = pcall(fs.remove, d)
      if okR and not fs.exists(d) then removed[#removed + 1] = d end
    end
  end
  return removed
end

local function offerBiosFlash(srcDisk)
  local biosPath = srcDisk .. "/bios.lua"
  if not fs.exists(biosPath) then return end

  local h = io.open(biosPath, "r")
  if not h then warn("Could not read bios.lua"); print(); return end
  local biosCode = h:read("*a"); h:close()
  if not biosCode or #biosCode == 0 then warn("Empty bios.lua"); print(); return end

  local fingerprint = "(unavailable)"
  do
    local okC, cryptoMod = pcall(require, "kernel.crypto")
    if okC and cryptoMod and cryptoMod.hash then
      local digest = cryptoMod.hash(biosCode)
      if digest then fingerprint = digest:sub(1, 16) .. "..." end
    end
  end

  color(0xFFFF00)
  print("A TOS BIOS was found on the install disk.")
  print("Flashing it replaces your current EEPROM code.")
  print("  size:        " .. #biosCode .. " bytes")
  print("  SHA-256:     " .. fingerprint)
  color(0xFFFFFF)
  color(0xFFFF00); io.write('Type "flash" to confirm BIOS reflash: '); color(0xFFFFFF)
  local typed = io.read() or ""
  if typed ~= "flash" then ok("Skipped BIOS flash"); print(); return end

  local eeprom = component.list("eeprom")()
  if eeprom then
    local ep = component.proxy(eeprom)
    ep.set(biosCode)
    ep.setLabel("TOS BIOS")
    ok("BIOS flashed! Label set to 'TOS BIOS'")
  else warn("No EEPROM found") end
  print()
end

local function runQuestionnaire(hw)
  local cfg = {}

  color(0x00AAFF)
  print("--- Device Setup ---")
  color(0xFFFFFF)
  print()
  print("What type of device is this?")
  color(0xAAAAAA)
  print("  1. Computer  (desktop, tower with screen)")
  print("  2. Tablet    (portable, battery-powered)")
  print("  3. Server    (rack blade, typically headless)")
  color(0xFFFFFF)
  local dc = ask("Choice", {"1", "2", "3"}, "1")
  if dc == "2" then
    cfg.device = "tablet"
    cfg.showBattery = true
    cfg.powerSave = true
    ok("Tablet mode (battery monitoring on)")
  elseif dc == "3" then
    cfg.device = "server"
    cfg.headless = true
    cfg.autoServices = true
    ok("Server mode (headless boot, services auto-start)")

    print()
    color(0xFFFF00)
    print("  Server rack checklist:")
    color(0xAAAAAA)
    if hw.hasModem or hw.hasTunnel then
      ok("Network card detected")
    else
      warn("No modem or linked card! The server will be unreachable.")
      warn("Insert a network card in the rack before rebooting.")
    end
    if not hw.hasGPU and not hw.hasScreen then
      ok("Headless (no GPU/screen) — normal for servers")
    else
      warn("GPU or screen detected — will boot headless anyway.")
      warn("Remove them to free rack slots, or choose Computer mode.")
    end
    color(0xFFFFFF)
  else
    cfg.device = "computer"
    cfg.showBattery = false
    cfg.powerSave = false
    ok("Computer mode")
  end
  print()

  math.randomseed(math.floor(computer.uptime() * 1000) + computer.freeMemory())
  cfg.hostname = ask("Hostname", nil, "tos-" .. string.format("%04x", math.random(0, 0xFFFF)))
  ok("Hostname: " .. cfg.hostname)
  print()

  color(0x00AAFF)
  print("--- Security ---")
  color(0xFFFFFF)
  print()
  print("Security level:")
  color(0xAAAAAA)
  print("  1. Standard  (login + lockout after 5 failures)")
  print("  2. Relaxed   (login, no lockout)")
  print("  3. Open      (allows guest access)")
  color(0xFFFFFF)
  local sc = ask("Choice", {"1", "2", "3"}, "1")
  if sc == "3" then
    cfg.guestAccess = true; cfg.autoLockout = false; cfg.maxAttempts = 999
    ok("Security: Open")
  elseif sc == "2" then
    cfg.guestAccess = false; cfg.autoLockout = false; cfg.maxAttempts = 999
    ok("Security: Relaxed")
  else
    cfg.guestAccess = false; cfg.autoLockout = true; cfg.maxAttempts = 5
    ok("Security: Standard")
  end
  print()

  if hw.hasModem or hw.hasTunnel then
    color(0x00AAFF)
    print("--- Network ---")
    color(0xFFFFFF)
    print()
    cfg.encryptComms = confirm("Encrypt network communications?")
    ok("Encryption: " .. (cfg.encryptComms and "on" or "off"))
    local port = ask("Listen port", nil, "42")
    cfg.listenPort = tonumber(port) or 42
    ok("Port: " .. cfg.listenPort)
    print()
  else
    cfg.encryptComms = true
    cfg.listenPort = 42
  end

  if cfg.device == "tablet" then
    color(0x00AAFF)
    print("--- Tablet Options ---")
    color(0xFFFFFF)
    print()
    cfg.lowBatWarn = tonumber(ask("Low battery warning %", nil, "15")) or 15
    cfg.critBatWarn = tonumber(ask("Critical battery warning %", nil, "5")) or 5
    ok("Battery warnings: " .. cfg.lowBatWarn .. "% / " .. cfg.critBatWarn .. "%")
    print()
  end

  cfg.verbose = confirm("Verbose boot? (shows debug messages)")
  print()

  return cfg
end

local function writeConfig(cfg)
  local lines = { "return {" }
  local keys = {}
  for k in pairs(cfg) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = cfg[k]
    if type(v) == "string" then
      lines[#lines + 1] = string.format('  [%q] = %q,', k, v)
    else
      lines[#lines + 1] = string.format('  [%q] = %s,', k, tostring(v))
    end
  end
  lines[#lines + 1] = "}"
  local f = io.open("/etc/tos.cfg", "w")
  if f then f:write(table.concat(lines, "\n")); f:close(); return true end
  return false
end

term.clear()
header()

local hw = surveyHardware()
printHardwareReport(hw)

local args = {...}
local srcDisk = findInstallDisk(args[1])
local diskMode = srcDisk ~= nil

local copyOk = false

local cleanInstall = false

if diskMode then
  ok("Install disk found at: " .. srcDisk)
  print()
  color(0xFFFF00)
  print("TOS will be installed on the current boot drive.")
  print("Your /init.lua will be replaced.")
  color(0xFFFFFF)
  print()
  if not confirm("Continue?") then print("Cancelled."); return end
  print()

  if not preInstallSafetyCheck(_G._FORCE_WIPE or false) then return end

  copyOk = copyFromDisk(srcDisk)
  if not copyOk then
    fail("Install file copy/verify did NOT fully succeed.")
    warn("BIOS flash will be skipped to avoid bricking the boot.")
    warn("You can retry installation; the partial files won't conflict.")
    if not confirm("Continue to questionnaire anyway?") then print("Cancelled."); return end
    print()
  end

  if copyOk and hasOpenOsLeftovers() then
    color(0x00AAFF); print("--- Clean install ---"); color(0xFFFFFF)
    color(0xAAAAAA)
    print("OpenOS library files (/bin, /lib) are still on this drive.")
    print("TOS doesn't use them. Removing them gives a pristine TOS tree;")
    print("your data (/home, /tmp, /mnt) and config are left untouched.")
    print("This happens last, right before reboot — OpenOS won't be")
    print("bootable afterward, but TOS will be.")
    color(0xFFFFFF)
    cleanInstall = confirm("Remove OpenOS leftovers for a clean install?")
    ok(cleanInstall and "Will clean OpenOS leftovers before reboot"
       or "Leaving OpenOS files in place")
    print()
  end
else

  color(0xFFFF00)
  print("No install disk detected - running in configuration mode.")
  print("TOS system files must already be present on the boot drive.")
  color(0xFFFFFF)
  print()
  if not confirm("Continue?") then print("Cancelled."); return end
  print()
end

local cfg = runQuestionnaire(hw)

color(0x00AAFF)
print("--- Summary ---")
color(0xAAAAAA)
print("  Device:     " .. cfg.device)
print("  Hostname:   " .. cfg.hostname)
print("  Security:   " .. (cfg.autoLockout and "Standard" or (cfg.guestAccess and "Open" or "Relaxed")))
print("  Encryption: " .. (cfg.encryptComms and "Yes" or "No"))
if cfg.device == "tablet" then
  print("  Battery:    Warn at " .. cfg.lowBatWarn .. "% / " .. cfg.critBatWarn .. "%")
elseif cfg.device == "server" then
  print("  Headless:   " .. (cfg.headless and "Yes" or "No"))
  print("  Services:   " .. (cfg.autoServices and "Auto-start" or "Manual"))
end
print("  Verbose:    " .. (cfg.verbose and "Yes" or "No"))
if diskMode and copyOk then
  print("  Clean inst: " .. (cleanInstall and "Yes (remove /bin, /lib)" or "No"))
end
color(0xFFFFFF)
print()
if not confirm("Apply these settings?") then print("Cancelled."); return end
print()

color(0x00AAFF); print("--- Applying configuration ---"); color(0xFFFFFF)
if fs then
  for _, d in ipairs(RUNTIME_DIRS) do
    if not fs.isDirectory(d) then fs.makeDirectory(d) end
  end
end

if writeConfig(cfg) then
  ok("Configuration saved to /etc/tos.cfg")
else
  warn("Could not save config (defaults will be used)")
end
ok("Device profile: " .. cfg.device)
print()

if diskMode then
  if copyOk then
    offerBiosFlash(srcDisk)
  else
    warn("Skipping BIOS flash: file copy did not fully verify.")
    warn("Re-run install.lua to retry before flashing.")
    print()
  end
end

if diskMode and copyOk and cleanInstall then
  color(0x00AAFF); print("--- Cleaning OpenOS leftovers ---"); color(0xFFFFFF)
  local removed = cleanOpenOsLeftovers()
  if #removed > 0 then
    ok("Removed: " .. table.concat(removed, ", "))
    warn("OpenOS is no longer bootable on this drive — reboot into TOS.")
  else
    warn("Nothing to remove (already clean).")
  end
  print()
end

color(0x00AAFF); print("--- Installation Complete ---"); color(0xFFFFFF)
print()
color(0x00FF00)
if diskMode and copyOk then
  print("TOS is installed! Reboot to start.")
elseif diskMode then
  print("Partial install — re-run from the install disk to retry.")
else
  print("Configuration applied!")
end
print("First boot: login as root/root — TOS forces a password change before")
print("anything else, so set your new root password when prompted.")
if cleanInstall then
  color(0xFFFF00)
  print("Clean install: reboot now — OpenOS libraries were removed.")
  color(0xFFFFFF)
end
color(0xFFFFFF)
print()
if confirm("Reboot now?") then
  computer.shutdown(true)
end
