local bootFS = ...

local component = component
local computer = computer

if not load("return 1<<1") then
  local g
  for a in component.list("gpu") do
    local ok, px = pcall(component.proxy, a)
    if ok and px then g = px break end
  end
  local scr
  for a in component.list("screen") do scr = a break end
  if g and scr then
    pcall(g.bind, scr)
    pcall(g.setBackground, 0x000000)
    pcall(g.setForeground, 0xFFFFFF)
    pcall(g.fill, 1, 1, 80, 25, " ")
    pcall(g.set, 2, 2, "TOS requires the Lua 5.3 or 5.4 CPU architecture.")
    pcall(g.set, 2, 3, "This CPU is running an older one (Lua 5.2).")
    pcall(g.set, 2, 5, "Fix: sneak-click (crouch + right-click) the CPU in its")
    pcall(g.set, 2, 6, "computer-case slot to cycle architectures, then reboot.")
    pcall(g.set, 2, 8, "Press any key to power off.")
  end
  pcall(computer.beep, 800, 0.3)
  while true do
    local ev = computer.pullSignal(math.huge)
    if ev == "key_down" then computer.shutdown() end
  end
end

if not bootFS and _G._TOS_UNMANAGED_ROOT then
  bootFS = _G._TOS_UNMANAGED_ROOT
end

if not bootFS then

  local getBA = computer.getBootAddress
  if getBA then
    local addr = getBA()
    if addr and addr ~= "" then
      local ok, px = pcall(component.proxy, addr)
      if ok and px then bootFS = px end
    end
  end
end

local function safeExists(px, path)
  local ok, r = pcall(px.exists, path)
  return ok and r
end
--! #FIX (in-game, 2026-08-11) — TOS needs a WRITABLE root. It writes
--! /etc/users.dat before an operator has even finished the First Boot
--! password prompt, plus /var/log, /home and the whole package tree.
--! Nothing checked, so a read-only device booted "successfully" and the
--! first symptom was `Persist failed: read-only filesystem` in the
--! middle of setting the root password — with no hint of which disk was
--! at fault or that the disk was the fault at all.
local function safeReadOnly(px)
  if type(px) ~= "table" or type(px.isReadOnly) ~= "function" then return false end
  local ok, ro = pcall(px.isReadOnly)
  return ok and ro == true
end
--! Both scans below now run TWICE: once accepting only writable
--! filesystems, then once accepting anything. A read-only disk carrying
--! /tos is a fine thing to READ an OS from and a hopeless thing to run
--! one on, so it is the last choice rather than the first one that
--! happens to enumerate — but it is still better than not booting.
local function scanFor(marker)
  for _, requireWritable in ipairs({ true, false }) do
    for addr in component.list("filesystem") do
      local ok, px = pcall(component.proxy, addr)
      if ok and px and px.exists and safeExists(px, marker) then
        if not (requireWritable and safeReadOnly(px)) then return px end
      end
    end
  end
end
if not bootFS then bootFS = scanFor("/tos/kernel/init.lua") end
if not bootFS then bootFS = scanFor("/init.lua") end

if not bootFS then
  error("FATAL: Cannot find boot filesystem!")
end

--! Said HERE, at boot, rather than discovered later by whichever write
--! happened to come first. A machine that cannot write its own user
--! database cannot be set up, and the operator needs to know that before
--! they type a password into a prompt that is going to throw it away.
--!
--! Not fatal: a read-only root still boots to a usable read-only system,
--! and being able to look around is exactly what you want when
--! diagnosing this. But it is announced, loudly, once.
_G._TOS_ROOT_READONLY = safeReadOnly(bootFS)
if _G._TOS_ROOT_READONLY then
  local gpuAddr = component.list("gpu")()
  local scrAddr = component.list("screen")()
  if gpuAddr and scrAddr then
    local okG, gpu = pcall(component.proxy, gpuAddr)
    if okG and gpu then
      pcall(gpu.bind, scrAddr)
      pcall(gpu.setBackground, 0x000000)
      pcall(gpu.setForeground, 0xFF5555)
      local okR, w = pcall(gpu.getResolution)
      pcall(gpu.fill, 1, 1, (okR and w) or 80, 6, " ")
      pcall(gpu.set, 2, 2, "WARNING: the boot filesystem is READ-ONLY.")
      pcall(gpu.setForeground, 0xAAAAAA)
      pcall(gpu.set, 2, 3, "Disk " .. tostring(bootFS.address or "?"):sub(1, 8)
        .. "...  Nothing TOS writes will survive, and First Boot Setup")
      pcall(gpu.set, 2, 4, "cannot set a root password at all.")
      pcall(gpu.set, 2, 5, "Install to a writable drive (run install.lua), or unprotect this one.")
      pcall(computer.pullSignal, 5)
    end
  end
end

do
  local bootTotal = bootFS.spaceTotal()
  local FLOPPY_THRESHOLD = 524288

  if _G._BIOS_ONETIME then
    bootTotal = nil
  end
  if bootTotal and bootTotal <= FLOPPY_THRESHOLD then

    local largerDisk = nil
    local largerTotal = 0
    for addr in component.list("filesystem") do
      if addr ~= bootFS.address then
        local ok2, px = pcall(component.proxy, addr)
        if ok2 and px then
          local t2 = px.spaceTotal()
          if t2 and t2 > bootTotal and t2 > largerTotal then
            largerDisk = px
            largerTotal = t2
          end
        end
      end
    end
    if largerDisk then

      local g2
      for addr in component.list("gpu") do g2 = component.proxy(addr) break end
      local s2
      for addr in component.list("screen") do s2 = addr break end
      if g2 and s2 then
        pcall(g2.bind, s2)
        g2.setBackground(0x000000)
        g2.setForeground(0xFFFFFF)
        local sw, sh = g2.getResolution()
        g2.fill(1, 1, sw, sh, " ")
        local function gp(y, text, fg)
          g2.setForeground(fg or 0xFFFFFF)
          g2.set(2, y, tostring(text))
        end
        local bKB = math.floor(bootTotal / 1024)
        local dKB = math.floor(largerTotal / 1024)
        gp(2, "TOS is running from a floppy disk (" .. bKB .. "KB)", 0xFFFF00)
        gp(3, "A larger drive was detected (" .. dKB .. "KB)", 0xFFFF00)
        gp(4, "  source:  " .. (bootFS.address or "?"):sub(1, 12) .. "...", 0xAAAAAA)
        gp(5, "  target:  " .. (largerDisk.address or "?"):sub(1, 12) .. "...", 0xAAAAAA)

        gp(7, "1. Install TOS to the hard drive (recommended)", 0x00FF00)
        gp(8, "2. Continue booting from floppy (limited space)", 0xAAAAAA)
        gp(10, "Press 1 or 2:", 0xFFFFFF)

        while true do
          local sig, _, char = computer.pullSignal(60)
          if sig == "key_down" then
            if char == 49 then

              if bootFS.exists("/install.lua") then

                g2.fill(1, 1, sw, sh, " ")
                gp(2, "Starting installer...", 0x00AAFF)

                g2.fill(1, 1, sw, sh, " ")
                gp(2, "Copying TOS to hard drive...", 0x00AAFF)
                local y2 = 4
                local copied2 = 0

                local copyFailed = nil

                local function treeSize(srcFS, dir)
                  local total = 0
                  local iter = srcFS.list(dir)
                  if not iter then return total end
                  for _, name in ipairs(iter) do
                    local p = dir .. name
                    if srcFS.isDirectory(p) then
                      total = total + treeSize(srcFS, p)
                    else
                      total = total + (srcFS.size(p) or 0)
                    end
                  end
                  return total
                end
                local function copyDir(srcFS, dstFS, dir)
                  if copyFailed then return end
                  local iter = srcFS.list(dir)
                  if not iter then return end
                  for _, name in ipairs(iter) do
                    if copyFailed then return end
                    local srcPath = dir .. name
                    if srcFS.isDirectory(srcPath) then
                      dstFS.makeDirectory(srcPath)
                      copyDir(srcFS, dstFS, srcPath)
                    else
                      local fh = srcFS.open(srcPath, "r")
                      if not fh then
                        copyFailed = "open-src " .. srcPath; return
                      end
                      local wh = dstFS.open(srcPath, "w")
                      if not wh then
                        srcFS.close(fh)
                        copyFailed = "open-dst " .. srcPath; return
                      end

                      while true do
                        local chunk = srcFS.read(fh, 4096)
                        if not chunk then break end
                        local wOk, wErr = dstFS.write(wh, chunk)
                        if not wOk then
                          copyFailed = "write " .. srcPath .. ": " .. tostring(wErr)
                          break
                        end
                      end
                      srcFS.close(fh)
                      dstFS.close(wh)
                      if copyFailed then return end
                      copied2 = copied2 + 1
                    end
                  end
                end

                local needed = treeSize(bootFS, "/") + 8192
                local dstFree = (largerDisk.spaceTotal() or 0)
                  - (largerDisk.spaceUsed() or 0)
                if dstFree < needed then
                  gp(y2, "Target too full: need " .. math.floor(needed / 1024)
                    .. "KB, only " .. math.floor(dstFree / 1024) .. "KB free", 0xFF0000)
                  y2 = y2 + 1
                  gp(y2, "Nothing was written. Free up the disk and retry.", 0xFFAA00)
                  while true do local ev = computer.pullSignal(1e9)
                    if ev == "key_down" then computer.shutdown(true) end
                  end
                end

                local coreDirs = {
                  "/tos/", "/tos/kernel/", "/tos/kernel/net/", "/tos/shell/",
                  "/tos/compat/", "/tos/peripheral/",
                  "/etc/", "/etc/rc.d/", "/home/", "/root/", "/public/",
                  "/usr/", "/usr/bin/", "/usr/lib/", "/usr/modules/",
                  "/var/", "/var/log/", "/var/run/", "/tmp/",
                }
                for _, d in ipairs(coreDirs) do
                  largerDisk.makeDirectory(d)
                end
                copyDir(bootFS, largerDisk, "/")
                if copyFailed then
                  gp(y2, "Copy FAILED: " .. copyFailed, 0xFF0000)
                  y2 = y2 + 1
                  gp(y2, "BIOS not updated. Remove disk to try again.", 0xFFAA00)
                  while true do local ev = computer.pullSignal(1e9)
                    if ev == "key_down" then computer.shutdown(true) end
                  end
                end
                gp(y2, "Copied " .. copied2 .. " files", 0x00FF00)
                y2 = y2 + 1

                local ok1 = largerDisk.exists("/init.lua")
                local ok2 = largerDisk.exists("/tos/kernel/init.lua")
                local sz1 = ok1 and largerDisk.size("/init.lua") or 0
                local sz2 = ok2 and largerDisk.size("/tos/kernel/init.lua") or 0
                if not (ok1 and ok2 and sz1 > 0 and sz2 > 0) then
                  gp(y2, "Verification FAILED — BIOS not updated", 0xFF0000)
                  y2 = y2 + 1
                  gp(y2, "  init.lua=" .. tostring(sz1) .. " kernel=" .. tostring(sz2), 0xFF6600)
                  while true do local ev = computer.pullSignal(1e9)
                    if ev == "key_down" then computer.shutdown(true) end
                  end
                end

                gp(y2, "Files copied. Update EEPROM to boot from hard drive?", 0xFFAA00)
                y2 = y2 + 1
                gp(y2, "  [Y] update EEPROM   [N] leave EEPROM alone", 0xAAAAAA)
                y2 = y2 + 1
                gp(y2, "  Target: " .. (largerDisk.address or "?"):sub(1, 12) .. "...", 0xAAAAAA)
                y2 = y2 + 1
                local doFlash = false
                local t0 = computer.uptime()
                while computer.uptime() - t0 < 30 do
                  local s3, _, ch3 = computer.pullSignal(30)
                  if s3 == "key_down" then
                    if ch3 == 121 or ch3 == 89 then doFlash = true end
                    break
                  end
                end
                if doFlash then
                  gp(y2, "Setting boot drive...", 0x00AAFF)
                  computer.setBootAddress(largerDisk.address)
                  y2 = y2 + 1
                else
                  gp(y2, "EEPROM unchanged — remove floppy and reboot to use HD", 0xFFAA00)
                  y2 = y2 + 1
                end
                gp(y2, "", 0xFFFFFF)
                y2 = y2 + 1
                gp(y2, "TOS installed to hard drive!", 0x00FF00)
                y2 = y2 + 1
                gp(y2, "Rebooting in 3 seconds...", 0xAAAAAA)
                computer.pullSignal(3)
                computer.shutdown(true)
              else
                gp(10, "install.lua not found on floppy!", 0xFF0000)
                gp(11, "Booting from floppy instead...", 0xAAAAAA)
                computer.pullSignal(2)
              end
              break
            elseif char == 50 then
              break
            end
          elseif not sig then
            break
          end
        end
      end
    end
  end
end

_G._TOS = {
  version    = "1.4.0",
  codename   = "Iris",
  bootFS     = bootFS,

  bootAddr   = bootFS and bootFS.address or nil,
  bootTime   = computer.uptime(),
  startMem   = computer.freeMemory(),
  totalMem   = computer.totalMemory(),
}

local loaded = {}
local loading = {}

local searchPaths = {
  "/tos/?.lua",
  "/tos/?/init.lua",
  "/lib/?.lua",
  "/usr/lib/?.lua",
  "/usr/bin/?.lua",
  "/usr/modules/?.lua",
  "/usr/modules/?/init.lua",
}

_G.package = { loaded = nil }

local function readFile(path)
  if not bootFS.exists(path) then return nil end
  local h = bootFS.open(path, "r")
  if not h then return nil end

  local parts = {}
  while true do
    local chunk = bootFS.read(h, 4096)
    if not chunk then break end
    parts[#parts + 1] = chunk
  end
  bootFS.close(h)
  return table.concat(parts)
end

local function loadModuleFile(path)
  if not bootFS.exists(path) then return false end
  local h = bootFS.open(path, "r")
  if not h then return false end
  local chunks, n = {}, 0
  local readOk, readErr = pcall(function()
    while true do
      local chunk = bootFS.read(h, 4096)
      if chunk == nil then break end

      if #chunk > 0 then n = n + 1; chunks[n] = chunk end
    end
  end)
  bootFS.close(h)
  if not readOk then return true, nil, readErr, "read" end

  local i = 0
  local okL, fn, err = pcall(load, function()
    i = i + 1
    local c = chunks[i]
    chunks[i] = nil
    return c
  end, "=" .. path, "t")
  if not okL then return true, nil, fn, "compile" end
  return true, fn, err, "compile"
end

--! MUST list every name compat.init registers, or that name's first
--! require falls past this hook into the search path.
--!
--! `internet` was missing. compat.init registers it, but nothing here
--! triggered on it, so require("internet") went to the path search and
--! found OpenOS's /lib/internet.lua -- TOS quietly running OpenOS's
--! library instead of its own shim. Worse, it was ORDER-DEPENDENT: touch
--! any other shim name first and compat is already initialized, so
--! package.loaded has "internet" and it resolves correctly. Touch
--! `internet` first, on a disk with no OpenOS underneath it, and the
--! require fails outright.
--!
--! Two lists that have to agree, with nothing checking. Now checked:
--! test_openos_compat.lua compares them and fails on any divergence.
local OPENOS_SHIMS = {
  sides = true, colors = true, keyboard = true, text = true,
  serialization = true, buffer = true, term = true, filesystem = true,
  event = true, shell = true, io = true, internet = true,
}

local function tosRequireBody(name)

  if OPENOS_SHIMS[name] and not loaded[name] then
    local T = _G._TOS
    if not (T and T.compatDisabled) then

      local okC, compatMod = pcall(_G.require, "compat")
      if okC and compatMod and compatMod.init then
        pcall(compatMod.init, { procSleep = T and T.proc and T.proc.sleep })
      end
      if loaded[name] then return loaded[name] end
    end
  end

  local modName = name:gsub("%.", "/")
  local tried = {}
  for _, pattern in ipairs(searchPaths) do
    local path = pattern:gsub("%?", modName)
    local found, fn, err, mode = loadModuleFile(path)
    if found then
      if not fn then
        error((mode == "read" and "Read error in '" or "Syntax error in '")
          .. name .. "' (" .. path .. "): " .. tostring(err), 2)
      end
      local ok, result = pcall(fn, name)
      if not ok then
        error("Runtime error in '" .. name .. "': " .. tostring(result), 2)
      end
      if result == nil then result = true end
      loaded[name] = result
      return result
    end
    tried[#tried + 1] = path
  end
  error("Module not found: " .. name .. "\nSearched:\n  " .. table.concat(tried, "\n  "), 2)
end

local function tosRequire(name)
  if loaded[name] then return loaded[name] end
  if loading[name] then
    error("Circular dependency: " .. name, 2)
  end
  loading[name] = true

  local ok, result = pcall(tosRequireBody, name)
  loading[name] = nil
  if not ok then error(result, 0) end
  return result
end

_G.require = tosRequire

loaded["component"] = component
loaded["computer"] = computer
if unicode then loaded["unicode"] = unicode end

_G.package.loaded = loaded

local bootcfgMod, bootCfg, verbosity
do
  local okB, m = pcall(require, "kernel.bootcfg")
  if okB and m then
    bootcfgMod = m
    local ok2, cfg = pcall(m.load, {
      exists   = function(p) return bootFS.exists(p) end,
      readFile = function(p) return readFile(p) end,
    })
    bootCfg = ok2 and cfg or nil
  end
  verbosity = (bootcfgMod and bootCfg) and bootcfgMod.verbosity(bootCfg) or "text"
  _G._TOS.bootcfg    = bootCfg
  _G._TOS.bootcfgMod = bootcfgMod
end

local earlyMinLevel
if bootcfgMod and bootcfgMod.echoMinLevel then
  earlyMinLevel = bootcfgMod.echoMinLevel(verbosity)
else
  earlyMinLevel = ({ silent = 4, splash = 2, text = 1, verbose = 0 })[verbosity] or 1
end

local gpuAddr
for addr in component.list("gpu") do gpuAddr = addr break end
local screenAddr
for addr in component.list("screen") do screenAddr = addr break end
local gpu

if gpuAddr and screenAddr then
  gpu = component.proxy(gpuAddr)

  if not _G._BIOS_CY then
    gpu.bind(screenAddr)
  end
  _G._TOS.gpu = gpu
end

local screenW, screenH = 50, 16
if gpu then
  screenW, screenH = gpu.getResolution()
end

local gpuDepth = _G._BIOS_DEPTH or 1
if gpu then
  local ok, d = pcall(gpu.getDepth)
  if ok and d then gpuDepth = d end
end
local isMonochrome = gpuDepth <= 1

local function tc(color)
  if isMonochrome then return 0xFFFFFF end
  return color
end

local cursorY = 1

local bootT0 = (_G._TOS and _G._TOS.bootTime) or computer.uptime()

local function earlyPrint(text, color)
  if not gpu then return end
  text = tostring(text)

  if verbosity == "verbose" then
    local ms = math.floor((computer.uptime() - bootT0) * 1000)
    text = string.format("[%6dms] %s", ms, text)
  end
  if color then gpu.setForeground(tc(color)) end
  if cursorY > screenH then
    gpu.copy(1, 2, screenW, screenH - 1, 0, -1)
    cursorY = screenH
  end

  gpu.fill(1, cursorY, screenW, 1, " ")
  gpu.set(1, cursorY, text)
  cursorY = cursorY + 1
end

local function earlyClear()
  if not gpu then return end
  gpu.setBackground(0x000000)
  gpu.setForeground(tc(0x00FF00))
  gpu.fill(1, 1, screenW, screenH, " ")
  cursorY = 1
end

local function splashPad(s)
  if verbosity ~= "splash" then return "  " .. s end
  return string.rep(" ", math.max(0, math.floor((screenW - #s) / 2))) .. s
end

if _G._BIOS_CY then
  cursorY = _G._BIOS_CY
  if gpu then
    gpu.setBackground(0x000000)
    gpu.setForeground(tc(0x00FF00))
  end
else
  earlyClear()
end

local totalKB = math.floor(_G._TOS.totalMem / 1024)
local freeKB  = math.floor(computer.freeMemory() / 1024)

local function drawBootHeader()
if verbosity ~= "silent" then

  local okLogo, logo = pcall(require, "kernel.logo")
  if okLogo and logo and logo.banner then
    local bopts = { ascii = isMonochrome, compact = screenW < 34 }
    if verbosity == "splash" then bopts.width = screenW
    else bopts.indent = 2 end
    for _, ln in ipairs(logo.banner(bopts)) do
      earlyPrint(ln[1], tc((logo.COLORS and logo.COLORS[ln[2]]) or 0x00AAFF))
    end
  else
    local bar = string.rep(isMonochrome and "=" or "═", math.min(38, screenW))
    earlyPrint(bar, tc(0x00AAFF))
    earlyPrint("  TOS", tc(0x00AAFF))
    earlyPrint(bar, tc(0x00AAFF))
  end
  earlyPrint(splashPad("TOS v" .. _G._TOS.version .. " [" .. _G._TOS.codename .. "]"), tc(0x00AAFF))
  earlyPrint(splashPad("Memory: " .. freeKB .. "K free / " .. totalKB .. "K total"), tc(0xAAAAAA))
end

if _G._BIOS_ONETIME then
  earlyPrint("  ONE-TIME BOOT: EEPROM unchanged, boot config preserved", tc(0xFFAA00))
end

if bootCfg and bootCfg.profile == "safe" then
  earlyPrint("  SAFE MODE: services, cron, packages, net, themes are OFF", tc(0xFFAA00))
  earlyPrint("  (Boot Settings -> Profile to leave Safe Mode)", tc(0xAAAAAA))
end
if totalKB < 128 then
  earlyPrint("  WARNING: Low memory - features limited!", tc(0xFF0000))
elseif totalKB < 256 then
  earlyPrint("  NOTE: Limited memory - some features may be skipped", tc(0xFFFF00))
end
end

drawBootHeader()

if ((bootCfg and bootCfg.showConfig) or verbosity == "verbose") and gpu then
  pcall(function()
    local sysinfo = require("kernel.sysinfo")

    local function postColor(role)
      local map = {
        bg = 0x000000, border = tc(0x00AAFF), title = tc(0x00FFFF),
        dim = tc(0xAAAAAA), value = tc(0xFFFFFF), ok = tc(0x00FF00),
        warn = tc(0xFFAA00), section = tc(0x00FFFF),
      }
      return map[role] or tc(0xFFFFFF)
    end
    local function gset(x, y, text, fgc, bgc)
      if bgc then gpu.setBackground(bgc) end
      gpu.setForeground(fgc or 0xFFFFFF)
      gpu.set(x, y, text)
    end

    local inv = sysinfo.gather(nil,
      { cpuTier = bootCfg.cpuTier, dataTier = bootCfg.dataTier },
      function(msg) earlyPrint("  Standby - " .. msg .. "...", tc(0xAAAAAA)) end)
    earlyClear()

    local cfgTitle = "TOS System Configuration"
    if screenW >= 60 then
      local okLogo, logo = pcall(require, "kernel.logo")
      if okLogo and logo and logo.VENDOR then
        cfgTitle = logo.VENDOR .. "  -  System Configuration"
      end
    end
    local after = sysinfo.render(inv, { W = screenW, H = screenH, color = postColor,
      set = gset, title = cfgTitle })
    gset(2, math.min(screenH, (after or screenH) + 1),
      "Press DEL for Boot Settings, S for Safe Mode (once)...", tc(0xFFAA00))

    local enterSetup = false
    local safeOnce = false
    local deadline = computer.uptime() + 3
    while computer.uptime() < deadline do
      local ev, _, ch, code = computer.pullSignal(deadline - computer.uptime())
      if ev == "key_down" then
        if code == 211 then enterSetup = true
        elseif ch == 115 or ch == 83 then safeOnce = true end
        break
      end
    end
    earlyClear()

    drawBootHeader()
    if safeOnce and bootCfg then
      bootCfg.profile = "safe"
      earlyPrint("  SAFE MODE (one-time): services, cron, packages, net, themes OFF",
        tc(0xFFAA00))
      earlyPrint("  Boot config untouched - the next boot is normal.", tc(0xAAAAAA))
    end

    if enterSetup then
      local okBS, bootsettings = pcall(require, "kernel.bootsettings")
      if okBS and bootsettings then
        local ctx = {
          W = screenW, H = screenH, color = postColor, set = gset,
          sysinfo = sysinfo, clear = earlyClear,
          readKey = function()
            while true do
              local e, _, ch, code = computer.pullSignal()
              if e == "key_down" then return e, ch, code end
            end
          end,
        }
        local action, newCfg = bootsettings.run(bootCfg, ctx)
        if action == "save" or action == "reboot" then
          local cfgFS = {
            exists   = function(p) return bootFS.exists(p) end,
            readFile = readFile,
            writeFile = function(p, d)
              if not bootFS.exists("/etc") then pcall(bootFS.makeDirectory, "/etc") end
              local h = bootFS.open(p, "w"); if not h then return false end
              bootFS.write(h, d); bootFS.close(h); return true
            end,
          }
          pcall(function() require("kernel.bootcfg").save(cfgFS, newCfg) end)
          earlyClear()
          if action == "reboot" then
            gset(2, 2, "Saved. Rebooting to apply...", tc(0x00FF00))
            computer.pullSignal(1)
            computer.shutdown(true)
          else
            gset(2, 2, "Saved. Changes apply on next boot. Continuing...", tc(0x00FF00))
            computer.pullSignal(1)
            earlyClear()
            drawBootHeader()
          end
        end
      end
    end
  end)
end

local function bootRead(path)
  if not bootFS.exists(path) then return nil end
  local h = bootFS.open(path, "r")
  if not h then return nil end
  local parts = {}
  repeat
    local chunk = bootFS.read(h, 4096)
    if chunk then parts[#parts + 1] = chunk end
  until not chunk
  bootFS.close(h)
  return table.concat(parts)
end

local function loadTableFile(path, chunkName)
  local source = bootRead(path)
  if not source then return nil end
  local fn = load(source, "=" .. chunkName, "t")
  if not fn then return nil end
  local ok, result = pcall(fn)
  if not ok or type(result) ~= "table" then return nil end
  return result
end

local criticalFiles = {}
local criticalSource = "(none)"

do
  local mf = loadTableFile("/var/pkg/installed/tos-core/package.lua", "tos-core/package")
  if mf and type(mf.critical) == "table" then
    for _, p in ipairs(mf.critical) do
      if type(p) == "string" then criticalFiles[#criticalFiles + 1] = p end
    end
    if #criticalFiles > 0 then criticalSource = "tos-core/package.lua" end
  end
end

if #criticalFiles == 0 then
  local mf = loadTableFile("/etc/critical.bak", "critical.bak")
  if mf then
    for _, p in ipairs(mf) do
      if type(p) == "string" then criticalFiles[#criticalFiles + 1] = p end
    end
    if #criticalFiles > 0 then criticalSource = "critical.bak" end
  end
end

if #criticalFiles == 0 then
  local mf = loadTableFile("/tos/system_manifest.lua", "system_manifest")
  if mf then
    for _, entry in ipairs(mf) do
      if entry.critical and type(entry.path) == "string" then
        criticalFiles[#criticalFiles + 1] = entry.path
      end
    end
    if #criticalFiles > 0 then criticalSource = "system_manifest.lua" end
  end
end

if #criticalFiles == 0 then
  criticalFiles = {
    "/tos/kernel/init.lua",
    "/tos/kernel/log.lua",
    "/tos/kernel/hal.lua",
    "/tos/kernel/event.lua",
    "/tos/kernel/process.lua",
    "/tos/kernel/fs.lua",
    "/tos/kernel/serialize.lua",
    "/tos/kernel/display.lua",
    "/tos/shell/init.lua",
  }
  criticalSource = "hardcoded fallback"
end
local missingFiles = {}
for _, path in ipairs(criticalFiles) do
  if not bootFS.exists(path) then
    missingFiles[#missingFiles + 1] = path
  end
end
if #missingFiles > 0 then
  earlyPrint("MISSING " .. #missingFiles .. " FILES:", tc(0xFF0000))
  for _, path in ipairs(missingFiles) do
    earlyPrint("  " .. path, tc(0xFF6600))
  end
  earlyPrint("Press any key to reboot...", tc(0xAAAAAA))
  computer.beep(400, 0.5)

  while true do
    local ev = computer.pullSignal(math.huge)
    if ev == "key_down" then break end
  end
  computer.shutdown(true)
end

if verbosity ~= "silent" then
  earlyPrint(splashPad("Verifying: " .. (#criticalFiles - #missingFiles) .. "/" .. #criticalFiles
    .. " system files OK [" .. criticalSource .. "]"), tc(0x00FF00))
  earlyPrint(splashPad("Loading kernel..."), tc(0x00FF00))
end

local bootProgress = nil
if verbosity == "splash" and gpu then

  --! RECOMPUTED, never measured once. gpu.bind() above leaves the screen at
  --! its MAXIMUM, and the kernel applies the resolution policy (kernel/
  --! screen.lua, density-based, floored at 80x25) part-way through
  --! kernel.boot() -- while this bar is live, because bootProgress is the
  --! callback driving it. On a Tier 3 GPU with a multi-block screen that is
  --! a real reduction, 160x50 -> 80x25, and geometry measured beforehand
  --! put the bar at column 60 of a screen 80 wide: pushed right, running
  --! off the edge, with the wordmark above it going the same way. Tier 2
  --! (max 80x25) and a single Tier 3 block (max 50x16) never move, which is
  --! why it only ever showed on a resized Tier 3 screen.
  --! (test_splash_resize.lua)

  local okSteps, bootsteps = pcall(require, "kernel.bootsteps")
  local headerBottom = cursorY
  local barRow, barW, barX
  local function geom()
    if okSteps and bootsteps and bootsteps.splashGeometry then
      barRow, barW, barX = bootsteps.splashGeometry(screenW, screenH, headerBottom)
    else
      barW   = math.max(10, math.min(40, screenW - 6))
      barX   = math.max(1, math.floor((screenW - (barW + 2)) / 2) + 1)
      barRow = math.max(1, math.min(screenH - 4, headerBottom + 1))
    end
  end
  local LOG_ROWS = 3
  local stagesShown = 0
  local stageTotal  = 16
  local fillCh   = isMonochrome and "#" or "█"
  local logLines = {}
  local lastStage = nil
  if okSteps and bootsteps and bootsteps.STAGE_COUNT then stageTotal = bootsteps.STAGE_COUNT end
  local function stageFor(msg)
    if okSteps and bootsteps then return bootsteps.stageFor(msg) end
    return nil
  end

  --! Has the glass changed size under us? Re-read it, and if it moved,
  --! rebuild the whole splash rather than just moving the bar: the wordmark
  --! and status lines above were centred for the old width too, and
  --! OpenComputers clears the screen on setResolution, so there is nothing
  --! up there to keep. Cheap enough -- one getResolution per progress
  --! message, a few dozen over a boot, and only on a splash boot.
  local function resync()
    local okR, w, h = pcall(gpu.getResolution)
    if not okR or not w or not h then return false end
    if w == screenW and h == screenH then return false end
    screenW, screenH = w, h
    earlyClear()
    cursorY = 1
    drawBootHeader()
    headerBottom = cursorY
    geom()
    cursorY = math.min(screenH, barRow + LOG_ROWS + 1)
    return true
  end

  local function redraw()
    resync()
    gpu.setBackground(0x000000)
    local fill = math.floor(barW * math.min(1, stagesShown / stageTotal) + 0.5)
    gpu.setForeground(tc(0x00AAFF))
    gpu.set(barX, barRow, "[" .. string.rep(fillCh, fill)
      .. string.rep(" ", barW - fill) .. "]")
    for i = 1, LOG_ROWS do
      local e = logLines[i]
      gpu.setForeground((e and e[2]) or tc(0xAAAAAA))
      gpu.set(barX, barRow + i, (((e and e[1]) or "")
        .. string.rep(" ", barW + 2)):sub(1, barW + 2))
    end
  end
  local function pushLine(text, color)
    logLines[#logLines + 1] = { text, color }
    while #logLines > LOG_ROWS do table.remove(logLines, 1) end
  end

  geom()
  redraw()
  cursorY = math.min(screenH, barRow + LOG_ROWS + 1)

  bootProgress = function(msg, level)
    msg = tostring(msg or "")

    if level and level >= 2 then

      local mark = (level == 2) and "! " or "!! "
      pushLine((mark .. msg):sub(1, barW + 2),
        (level == 2) and tc(0xFFAA00) or tc(0xFF4040))
    else
      local stage = stageFor(msg)
      if stage and stage ~= lastStage then
        lastStage = stage
        stagesShown = stagesShown + 1
        pushLine(stage, tc(0xAAAAAA))
      end
    end

    if msg:find("Boot complete", 1, true) then stagesShown = stageTotal end
    redraw()
  end
end

local ok, err = xpcall(function()
  local kernel = require("kernel")
  kernel.boot({
    gpu          = gpu,
    gpuDepth     = gpuDepth,
    screenW      = screenW,
    screenH      = screenH,
    earlyPrint   = earlyPrint,
    bootFS       = bootFS,

    bootcfg      = bootCfg,
    bootcfgMod   = bootcfgMod,
    earlyMinLevel = earlyMinLevel,
    bootProgress = bootProgress,
  })
end, function(e)
  return tostring(e) .. "\n" .. debug.traceback("", 2)
end)

if not ok then
  earlyClear()
  earlyPrint("", tc(0xFF0000))
  earlyPrint("======= KERNEL PANIC =======", tc(0xFF0000))
  earlyPrint("", tc(0xFF6600))

  local errStr = tostring(err) or "Unknown error"

  pcall(function()
    local K = _G._TOS and _G._TOS.kernel
    if K and K.crashDump then K.crashDump("KERNEL PANIC", errStr); return end
    if bootFS and bootFS.open then
      pcall(bootFS.makeDirectory, "/var/crash")
      local h = bootFS.open("/var/crash/crash-panic.txt", "w")
      if h then
        bootFS.write(h, "=== TOS KERNEL PANIC ===\n" .. errStr
          .. "\nFree RAM: " .. math.floor(computer.freeMemory() / 1024) .. "KB\n")
        bootFS.close(h)
      end
      local hm = bootFS.open("/var/crash/NEW", "w")
      if hm then bootFS.write(hm, "KERNEL PANIC"); bootFS.close(hm) end
    end
  end)
  for line in errStr:gmatch("[^\n]+") do
    while #line > screenW do
      earlyPrint(line:sub(1, screenW), tc(0xFF6600))
      line = line:sub(screenW + 1)
    end
    earlyPrint(line, tc(0xFF6600))
  end
  earlyPrint("", tc(0xAAAAAA))
  earlyPrint("Free RAM: " .. math.floor(computer.freeMemory() / 1024) .. "KB", tc(0xAAAAAA))
  earlyPrint("", tc(0xFFFF00))
  earlyPrint("Press any key to reboot...", tc(0xFFFF00))

  computer.beep(400, 0.15)
  computer.pullSignal(0.05)
  computer.beep(400, 0.15)
  computer.pullSignal(0.05)
  computer.beep(400, 0.15)

  while true do
    local ev = computer.pullSignal(math.huge)
    if ev == "key_down" then break end
  end
  computer.shutdown(true)
end
