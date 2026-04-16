-- ╔══════════════════════════════════════╗
-- ║  TOS Installer v1.2.5                ║
-- ║  Terminal Operating System           ║
-- ║  Interactive setup + install disk    ║
-- ╚══════════════════════════════════════╝
-- Two modes:
--   1. Install disk: auto-detects source disk, copies files,
--      runs questionnaire, offers BIOS flash.
--      (Created by the `deploy` command in TOS)
--   2. Standalone: just runs the questionnaire to configure
--      an existing TOS installation.
--
-- Run from OpenOS:
--   # /mnt/<disk>/install.lua   (install disk mode)
--   # install.lua               (standalone mode)

local component = require("component")
local computer = require("computer")
local term = require("term")

-- Try to load OpenOS modules
local fs = nil
pcall(function() fs = require("filesystem") end)

-- ============================================================
-- Helpers
-- ============================================================

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
  -- Use term.read if available (OpenOS provides it), fall back to io.read
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

local function header()
  color(0x00AAFF)
  print("╔═══════════════════════════════════════════╗")
  print("║         TOS Installer v0.3.0              ║")
  print("║   Terminal Operating System Setup          ║")
  print("╚═══════════════════════════════════════════╝")
  color(0xFFFFFF)
  print()
end

-- ============================================================
-- Install disk detection
-- ============================================================
-- If this script lives on a disk that also contains
-- /tos/kernel/init.lua, we're in install-disk mode.

local function findInstallDisk()
  if not fs then return nil end

  -- Method 1: detect from the script's own path (OpenOS sets _ env)
  local scriptPath = os.getenv and os.getenv("_") or nil
  if scriptPath then
    local mount = scriptPath:match("^(/mnt/[^/]+)")
    if mount and fs.exists(mount .. "/tos/kernel/init.lua") then
      return mount
    end
  end

  -- Method 2: scan all filesystems for one with both install.lua
  -- and the TOS kernel — but NOT the boot drive
  local bootAddr = computer.getBootAddress()
  for addr in component.list("filesystem") do
    if addr ~= bootAddr then
      local ok, px = pcall(component.proxy, addr)
      if not ok then px = nil end
      if px and px.exists("/tos/kernel/init.lua") and px.exists("/install.lua") then
        -- Find its mount point
        if fs.mounts then
          for mnt, proxy in fs.mounts() do
            if proxy.address == addr then
              return tostring(mnt)
            end
          end
        end
      end
    end
  end

  return nil
end

-- ============================================================
-- Hardware survey
-- ============================================================

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

-- ============================================================
-- File copy (install disk mode)
-- ============================================================

local function copyFromDisk(srcDisk)
  -- Create directory structure on boot drive
  color(0x00AAFF); print("--- Creating directories ---"); color(0xFFFFFF)
  local dirs = {
    "/tos", "/tos/kernel", "/tos/kernel/net", "/tos/shell",
    "/tos/compat", "/tos/peripheral",
    "/etc", "/etc/rc.d", "/home", "/public", "/root",
    "/usr", "/usr/bin", "/usr/lib",
    "/var", "/var/log", "/var/run", "/tmp",
  }
  for _, d in ipairs(dirs) do
    if not fs.isDirectory(d) then fs.makeDirectory(d) end
  end
  ok("Directory structure created")
  print()

  -- Recursively copy all .lua files (except install.lua itself)
  color(0x00AAFF); print("--- Copying system files ---"); color(0xFFFFFF)

  local function copyRecursive(srcDir, dstDir)
    local copied, failed = 0, 0
    local iter = fs.list(srcDir)
    if not iter then return 0, 0 end
    for name in iter do
      local srcPath = srcDir .. "/" .. name
      local dstPath = dstDir .. "/" .. name
      -- Directory entries have trailing slash
      if name:sub(-1) == "/" then
        name = name:sub(1, -2)
        srcPath = srcDir .. "/" .. name
        dstPath = dstDir .. "/" .. name
        if not fs.isDirectory(dstPath) then fs.makeDirectory(dstPath) end
        local c2, f2 = copyRecursive(srcPath, dstPath)
        copied = copied + c2; failed = failed + f2
      elseif name:match("%.lua$") and name ~= "install.lua" then
        local h = io.open(srcPath, "r")
        if h then
          local content = h:read("*a"); h:close()
          if content then
            local w = io.open(dstPath, "w")
            if w then
              w:write(content); w:close()
              copied = copied + 1
            else failed = failed + 1 end
          end
        else failed = failed + 1 end
      end
    end
    return copied, failed
  end

  local totalCopied, totalFailed = copyRecursive(srcDisk, "")
  print()
  if totalFailed == 0 then
    ok("Copied " .. totalCopied .. " files successfully")
  else
    warn("Copied " .. totalCopied .. " files, " .. totalFailed .. " failed")
  end
  print()
  return totalFailed == 0
end

-- ============================================================
-- BIOS flash
-- ============================================================

local function offerBiosFlash(srcDisk)
  local biosPath = srcDisk .. "/bios.lua"
  if not fs.exists(biosPath) then return end

  color(0xFFFF00)
  print("A TOS BIOS was found on the install disk.")
  print("Flashing it replaces your current EEPROM code.")
  color(0xFFFFFF)
  if confirm("Flash TOS BIOS to EEPROM?") then
    local h = io.open(biosPath, "r")
    if h then
      local biosCode = h:read("*a"); h:close()
      local eeprom = component.list("eeprom")()
      if eeprom then
        local ep = component.proxy(eeprom)
        ep.set(biosCode)
        ep.setLabel("TOS BIOS")
        ok("BIOS flashed! Label set to 'TOS BIOS'")
      else warn("No EEPROM found") end
    else warn("Could not read bios.lua") end
  else ok("Skipped BIOS flash") end
  print()
end

-- ============================================================
-- Questionnaire
-- ============================================================

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
    -- Rack user-error checks
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

  -- Security
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

  -- Network
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

  -- Tablet extras
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

-- ============================================================
-- Write config
-- ============================================================

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

-- ============================================================
-- Main
-- ============================================================

term.clear()
header()

local hw = surveyHardware()
printHardwareReport(hw)

-- Detect install disk
local srcDisk = findInstallDisk()
local diskMode = srcDisk ~= nil

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

  -- Copy system files from install disk
  local copyOk = copyFromDisk(srcDisk)
  if not copyOk then
    warn("Some files failed to copy. Installation may be incomplete.")
    if not confirm("Continue anyway?") then print("Cancelled."); return end
    print()
  end

  -- Offer BIOS flash
  offerBiosFlash(srcDisk)
else
  -- Standalone mode: just configure an existing installation
  color(0xFFFF00)
  print("No install disk detected - running in configuration mode.")
  print("TOS system files must already be present on the boot drive.")
  color(0xFFFFFF)
  print()
  if not confirm("Continue?") then print("Cancelled."); return end
  print()
end

-- Run the setup questionnaire
local cfg = runQuestionnaire(hw)

-- Summary
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
color(0xFFFFFF)
print()
if not confirm("Apply these settings?") then print("Cancelled."); return end
print()

-- Create directories (standalone mode may need this too)
color(0x00AAFF); print("--- Applying configuration ---"); color(0xFFFFFF)
if fs then
  local dirs = {
    "/etc", "/etc/rc.d", "/home", "/public", "/root",
    "/usr", "/usr/bin", "/usr/lib", "/usr/modules",
    "/var", "/var/log", "/var/run", "/tmp",
  }
  for _, d in ipairs(dirs) do
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

-- Done
color(0x00AAFF); print("--- Installation Complete ---"); color(0xFFFFFF)
print()
color(0x00FF00)
if diskMode then
  print("TOS is installed! Reboot to start.")
else
  print("Configuration applied!")
end
print("First boot: login as root/root, then set a new password.")
color(0xFFFFFF)
print()
if confirm("Reboot now?") then
  computer.shutdown(true)
end
