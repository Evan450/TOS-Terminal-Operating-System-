-- ╔══════════════════════════════════════╗
-- ║  TOS init.lua - System Bootstrap     ║
-- ║  Terminal Operating System v1.4.0    ║
-- ╚══════════════════════════════════════╝
-- Works with TOS BIOS (receives bootFS as arg)
-- AND with standard Lua BIOS (finds bootFS itself)

-- bootFS may be passed by TOS BIOS, or nil if standard BIOS
local bootFS = ...

-- In OC, component and computer are machine globals.
-- Do NOT use require() here - it doesn't exist yet.
local component = component
local computer = computer

-- ============================================================
-- Lua architecture guard
-- ============================================================
-- Several kernel modules (crypto, net, display, jbod, vault, compress,
-- backup, launcher) use Lua 5.3 bitwise-operator SYNTAX, and the boot
-- chain (BIOS TBFS reader, blockfs) needs string.pack. OC lets players
-- switch a CPU to the Lua 5.2 architecture; there, display.lua — on the
-- mandatory boot path — fails to PARSE, so without this probe the
-- failure mode is a kernel panic showing a raw syntax error from a
-- perfectly healthy disk. Probe the parser itself (this file contains
-- no 5.3 syntax, so it always gets far enough to run) and halt with
-- the actual fix. NOTE: keep this file 5.2-parseable.
-- Lua 5.4 is SUPPORTED on purpose: it parses 5.3 syntax and provides
-- every stdlib feature TOS uses (integers are 64-bit signed in both;
-- code that cares — crypto's unsigned compares — already uses
-- math.ult). A parser-feature probe passes there; keep it that way —
-- never replace this with a version-string or architecture-name
-- compare (test_bios pins the probe in both boot files).
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

-- ============================================================
-- Stage 0: Find boot filesystem
-- ============================================================
-- TBFS unmanaged boot: the stage-2 bootstrap (blockfs.BOOTSTRAP, run by
-- the TOS BIOS from a raw drive's boot region) already mounted the volume
-- and left the root proxy here. Prefer it — on that path getBootAddress
-- points at a `drive` component, which must NOT be proxied as a
-- filesystem (no exists/open; every fallback below would misfire).
if not bootFS and _G._TOS_UNMANAGED_ROOT then
  bootFS = _G._TOS_UNMANAGED_ROOT
end
-- If TOS BIOS passed it, great. Otherwise find it ourselves.
if not bootFS then
  -- Try computer.getBootAddress (added by standard Lua BIOS or TOS BIOS)
  local getBA = computer.getBootAddress
  if getBA then
    local addr = getBA()
    if addr and addr ~= "" then
      local ok, px = pcall(component.proxy, addr)
      if ok and px then bootFS = px end
    end
  end
end
-- exists() is pcall'd in both scans (#REV review finding #6): a floppy
-- yanked between the proxy and the invoke makes the component call
-- RAISE, which otherwise kills the whole scan instead of skipping the
-- dead device.
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

-- ============================================================
-- Stage 0a: is the root writable?
-- ============================================================
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

-- ============================================================
-- Floppy detection: If booting from a small/removable disk
-- while a larger drive exists, offer to install there instead.
-- ============================================================
do
  local bootTotal = bootFS.spaceTotal()
  local FLOPPY_THRESHOLD = 524288  -- 512KB (floppies are ~512KB)
  -- #SEC H1 — a one-time boot (operator chose Shift+Enter at the BIOS for a
  -- changed/fallback drive) explicitly declined to touch boot config. The
  -- migration flow below can re-flash the EEPROM via setBootAddress, so honour
  -- that intent: skip the offer entirely on a one-time boot. The operator can
  -- still migrate deliberately on a normal (EEPROM-committed) boot.
  if _G._BIOS_ONETIME then
    bootTotal = nil
  end
  if bootTotal and bootTotal <= FLOPPY_THRESHOLD then
    -- Look for a larger disk to install onto
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
      -- We're booting from a floppy but a hard drive exists.
      -- Show a choice to the user.
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
        -- #SEC H2 — surface both component addresses so the operator
        -- can confirm what's about to happen before approving an
        -- irreversible disk overwrite + EEPROM reflash.
        gp(7, "1. Install TOS to the hard drive (recommended)", 0x00FF00)
        gp(8, "2. Continue booting from floppy (limited space)", 0xAAAAAA)
        gp(10, "Press 1 or 2:", 0xFFFFFF)
        -- Wait for keypress
        while true do
          local sig, _, char = computer.pullSignal(60)
          if sig == "key_down" then
            if char == 49 then  -- "1"
              -- Run install.lua if available on the floppy
              if bootFS.exists("/install.lua") then
                -- Load and execute install.lua, passing the floppy's bootFS
                g2.fill(1, 1, sw, sh, " ")
                gp(2, "Starting installer...", 0x00AAFF)
                -- install.lua needs OpenOS require which we don't have
                -- yet. Instead of loading it here (the source is never
                -- actually executed — the old code read ~17 KB into a
                -- buffer and then threw it away), we copy the TOS tree
                -- directly to the target disk and chain-load from there.
                g2.fill(1, 1, sw, sh, " ")
                gp(2, "Copying TOS to hard drive...", 0x00AAFF)
                local y2 = 4
                local copied2 = 0
                -- Recursive copy from floppy to target disk.
                -- #107 — previously this silently ignored write failures,
                -- truncated reads, and partial files. We now surface the
                -- first failure up to the caller so the installer can
                -- refuse to flash the BIOS when the copy didn't complete.
                local copyFailed = nil
                -- Fail FAST on space (#REV review finding #5): sum the
                -- source tree before copying instead of half-copying and
                -- then failing verification.
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
                      -- Stream chunk-by-chunk (#REV finding #5): the old
                      -- whole-file write buffered everything in RAM and a
                      -- mid-file out-of-space surfaced only at the end —
                      -- and its `wOk == false` check let a nil-shaped
                      -- write failure through as success. `not wOk`
                      -- catches both failure shapes at the failing chunk.
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
                -- Space fail-fast: refuse before the first write, not
                -- after a half-copy fails verification. (+8KB slack for
                -- directory/metadata overhead.)
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
                -- Create core directories on target
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
                -- #107 — verify critical boot files before flashing BIOS.
                -- If the copy truncated mid-file, the machine would otherwise
                -- brick on next boot.
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
                -- #SEC H2 — require an explicit second confirmation
                -- before re-flashing the EEPROM. Auto-setBootAddress
                -- was the audit's main floppy-bootkit lever: any floppy
                -- left in the drive could silently permanently rebind
                -- the boot device. Operator must type Y now; otherwise
                -- the install stays on disk but the EEPROM still points
                -- at the floppy and the operator can reboot with the
                -- floppy removed to switch drives manually.
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
            elseif char == 50 then  -- "2"
              break  -- Continue booting from floppy
            end
          elseif not sig then
            break  -- Timeout: continue booting from floppy
          end
        end
      end
    end
  end
end

-- ============================================================
-- Global TOS state
-- ============================================================
_G._TOS = {
  version    = "1.4.0",
  codename   = "Iris",
  bootFS     = bootFS,
  -- #REV (#8) — the boot filesystem's component address. The shell's
  -- auto-mount gate (shell.panels autoMount, #SEC H26) refuses to mount
  -- anything until this is set (fail-closed so an inserted disk can't
  -- shadow the boot FS). It was NEVER set, so EVERY inserted floppy was
  -- silently refused ("inserting a disk does nothing"). Set it here from
  -- the boot proxy so removable-media auto-mount works.
  bootAddr   = bootFS and bootFS.address or nil,
  bootTime   = computer.uptime(),
  startMem   = computer.freeMemory(),
  totalMem   = computer.totalMemory(),
}

-- ============================================================
-- Stage 1: Build require() system
-- ============================================================
local loaded = {}
local loading = {}

-- Kernel /tos first so a package can never shadow a kernel module by name;
-- user-installed roots after it, in the order pkg uses them.
--
-- /usr/modules MUST be here: kernel.sandbox's USER_LIB_ROOTS already lists
-- it as a place package code may require from, and its resolver checks the
-- file exists there before handing off to THIS require. Without the entry
-- the two disagreed — the sandbox authorized the require, then the load
-- failed with "Module not found" (emulator round: a package with a
-- multi-file module under /usr/modules, e.g. `calc` requiring calc.sheet,
-- could not start at all). Single-file packages never noticed because pkg
-- loads a command's entry by absolute PATH, not by module name.
-- test_require_roots pins the two lists together.
local searchPaths = {
  "/tos/?.lua",
  "/tos/?/init.lua",
  "/lib/?.lua",
  "/usr/lib/?.lua",
  "/usr/bin/?.lua",
  "/usr/modules/?.lua",
  "/usr/modules/?/init.lua",
}

-- Package compat: loaded table accessible as package.loaded
-- (needed by compat/init.lua to register OpenOS shims)
_G.package = { loaded = nil }  -- Set after loaded table creation

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

-- #MEM — compile a module without ever holding TWO full copies of it.
-- The original path built a table of 4KB chunks, table.concat'd them into
-- one string, and load()ed that: source-in-pieces + joined copy + compiled
-- chunk all live at once (~2x the file plus the chunk). On low-RAM boxes
-- that peak was the "not enough memory for buffer allocation" shell-load
-- crash. We drop the joined copy by feeding load() from the chunk table and
-- releasing each piece as it is consumed.
--
-- #BUG (emulator round, 2026-07-24) — the reader must NOT touch the
-- filesystem. An earlier version read 4KB per reader call, which is the
-- textbook streaming form and would have kept the peak at one chunk; in
-- OpenComputers it panics the kernel outright:
--
--   Syntax error in 'kernel': attempt to yield across a C-call boundary
--
-- Component calls can YIELD — OC gives each machine a direct-call budget
-- and forces a yield when it runs out — and load() is a C function, so a
-- yield inside its reader crosses a C-call boundary and is fatal. It is not
-- RAM-dependent or intermittent: it killed boot on every machine. So do all
-- I/O FIRST (yielding there is fine, it's ordinary Lua), then compile from
-- memory, where the reader can only do table lookups.
--
-- Returns (found, fn, err, mode): found=false → no such file, keep
-- searching; found=true with fn=nil → the file exists but could not be
-- turned into a chunk, with `mode` saying which half failed ("read" or
-- "compile"). The caller words the error from that: reporting a failed
-- READ as a syntax error is how this very bug wasted diagnosis time — the
-- boot panic read "Syntax error in 'kernel'" when the file was fine and
-- the real fault was a yield during loading.
local function loadModuleFile(path)
  if not bootFS.exists(path) then return false end
  local h = bootFS.open(path, "r")
  if not h then return false end
  local chunks, n = {}, 0
  local readOk, readErr = pcall(function()
    while true do
      local chunk = bootFS.read(h, 4096)
      if chunk == nil then break end
      -- Lua treats "" from a reader as end-of-chunk, so a short read must
      -- never reach load() — it would compile a silent PREFIX of the module.
      if #chunk > 0 then n = n + 1; chunks[n] = chunk end
    end
  end)
  bootFS.close(h)
  if not readOk then return true, nil, readErr, "read" end
  -- Force text-only mode ("t"). Bytecode (mode "b" or "bt") is accepted
  -- by load() if bit5.band was ever compiled in, and loading
  -- attacker-crafted bytecode bypasses all Lua validity checks
  -- (arbitrary memory access, type-confusion, etc). Only source
  -- text may enter the kernel boot path.
  local i = 0
  local okL, fn, err = pcall(load, function()
    i = i + 1
    local c = chunks[i]
    chunks[i] = nil   -- release as we go; source frees while compiling
    return c          -- nil past the end ends the chunk
  end, "=" .. path, "t")
  if not okL then return true, nil, fn, "compile" end  -- compile RAISED (e.g. OOM)
  return true, fn, err, "compile"
end

-- OpenOS library names served by the compat layer (tos/compat/init.lua).
-- The layer used to be loaded whole at boot; now it loads on the FIRST
-- require() of one of these names (see the fallback in tosRequireBody).
-- Checked BEFORE the search paths so precedence matches the old behavior,
-- where compat pre-registered these names in the require cache at boot
-- (e.g. a /usr/lib/text.lua add-on must not shadow the OpenOS shim).
local OPENOS_SHIMS = {
  sides = true, colors = true, keyboard = true, text = true,
  serialization = true, buffer = true, term = true, filesystem = true,
  event = true, shell = true, io = true,
}

local function tosRequireBody(name)
  -- Lazy OpenOS compat: first touch of a shim name loads + initializes the
  -- whole layer (the shims cross-register each other, so per-module lazy
  -- loading isn't meaningful). The kernel sets _TOS.compatDisabled when the
  -- boot profile gates compat off — honor it so Safe Mode still refuses to
  -- run OpenOS code, exactly as when the layer wasn't loaded at boot.
  if OPENOS_SHIMS[name] and not loaded[name] then
    local T = _G._TOS
    if not (T and T.compatDisabled) then
      -- _G.require is tosRequire (assigned right after these definitions);
      -- called through the global because tosRequire's local isn't in
      -- scope yet at this point in the file.
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
  -- #REV (v1.4.0 emulator round) — the body can RAISE from places the
  -- old inline code didn't guard: on a low-RAM box, bootFS.read inside
  -- readFile (or load() itself) propagates "not enough memory" BEFORE
  -- any of the explicit `loading[name] = nil` lines ran. The marker
  -- then stayed set, so the shell's OOM-nudge-GC-and-retry hit a bogus
  -- "Circular dependency: shell.panels.commands.core" — which the
  -- command loader rightly treats as a permanent code error and caches,
  -- walling off every core command for the session. Run the body under
  -- pcall and ALWAYS clear the marker, so a transient failure stays
  -- transient and "Circular dependency" again means only actual cycles.
  local ok, result = pcall(tosRequireBody, name)
  loading[name] = nil
  if not ok then error(result, 0) end
  return result
end

_G.require = tosRequire

-- Pre-register machine globals as modules so require("computer") etc. works
loaded["component"] = component
loaded["computer"] = computer
if unicode then loaded["unicode"] = unicode end

-- Expose loaded table as package.loaded for OpenOS compat
_G.package.loaded = loaded

-- ============================================================
-- Stage 1b: Boot configuration (the everything → nothing spectrum)
-- ============================================================
-- Read VERY early and FAIL-SAFE: a missing/corrupt /etc/boot.cfg yields the
-- 'normal' profile so boot always proceeds. Drives the verbosity "muter",
-- the System Configuration POST screen, and the optional-stage gates (#4).
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
-- Verbosity → log early-echo threshold (DEBUG=0 … FATAL=4). Canonical mapping
-- lives in kernel.bootcfg (single source of truth, unit-tested); fall back to
-- a local copy if bootcfg didn't load.
local earlyMinLevel
if bootcfgMod and bootcfgMod.echoMinLevel then
  earlyMinLevel = bootcfgMod.echoMinLevel(verbosity)
else
  earlyMinLevel = ({ silent = 4, splash = 2, text = 1, verbose = 0 })[verbosity] or 1
end

-- ============================================================
-- Stage 2: GPU + Early Display
-- ============================================================
local gpuAddr
for addr in component.list("gpu") do gpuAddr = addr break end
local screenAddr
for addr in component.list("screen") do screenAddr = addr break end
local gpu

if gpuAddr and screenAddr then
  gpu = component.proxy(gpuAddr)
  -- Skip bind() if TOS BIOS already did it: gpu.bind() resets the GPU buffer
  -- (clears screen) in OC even when re-binding the same screen.
  if not _G._BIOS_CY then
    gpu.bind(screenAddr)
  end
  _G._TOS.gpu = gpu
end

local screenW, screenH = 50, 16
if gpu then
  screenW, screenH = gpu.getResolution()
end

-- Detect GPU color depth for tier-safe rendering
local gpuDepth = _G._BIOS_DEPTH or 1
if gpu then
  local ok, d = pcall(gpu.getDepth)
  if ok and d then gpuDepth = d end
end
local isMonochrome = gpuDepth <= 1

--- Map a color to a tier-safe value (T1 → white only)
local function tc(color)
  if isMonochrome then return 0xFFFFFF end
  return color
end

local cursorY = 1

-- Boot reference time for the verbose timing prefix. _G._TOS.bootTime was
-- captured at the top of this file; fall back to "now" if it's missing.
local bootT0 = (_G._TOS and _G._TOS.bootTime) or computer.uptime()

local function earlyPrint(text, color)
  if not gpu then return end
  text = tostring(text)
  -- "verbose" promises timings (see kernel.bootcfg's VERBOSITY note): on a
  -- verbose boot, stamp every early line with ms-since-boot so verbose is
  -- visibly distinct from text instead of identical to it.
  if verbosity == "verbose" then
    local ms = math.floor((computer.uptime() - bootT0) * 1000)
    text = string.format("[%6dms] %s", ms, text)
  end
  if color then gpu.setForeground(tc(color)) end
  if cursorY > screenH then
    gpu.copy(1, 2, screenW, screenH - 1, 0, -1)
    cursorY = screenH
  end
  -- Clear full line then write text (prevents remnant chars from longer lines)
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

-- Splash composition helper: on a "splash" boot the wordmark + status lines
-- + progress bar are CENTRED so the screen reads as a designed splash, not a
-- left-aligned boot log. Pads an ASCII line to the screen centre; the UTF-8
-- wordmark centres via logo.banner's width option instead (#string would
-- over-count its 3-byte block glyphs). Every other verbosity keeps the
-- classic indented log look.
local function splashPad(s)
  if verbosity ~= "splash" then return "  " .. s end
  return string.rep(" ", math.max(0, math.floor((screenW - #s) / 2))) .. s
end

-- ============================================================
-- Stage 3: Boot splash
-- ============================================================
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

-- The splash banner is "splash"-level output — suppressed only on a fully
-- silent boot. (Warnings below still show regardless.)
--
-- #FIX (emulator round 7) — this is a FUNCTION, not a straight-line block,
-- because the System Configuration POST screen below owns the whole screen
-- and earlyClear()s on the way out. The wordmark used to be painted once,
-- here, and then wiped: a splash boot showed a bare progress bar with no
-- branding at all (the operator: "the System Configuration screen removes
-- the logo"). The header is re-drawn after the POST screen closes so the
-- composition the splash is supposed to be actually survives to the
-- kernel hand-off.
local function drawBootHeader()
if verbosity ~= "silent" then
  -- Branded splash: the shared kernel.logo wordmark. On a "splash" boot the
  -- whole composition (wordmark, status lines, progress bar below) is
  -- CENTRED; every other verbosity keeps the left-aligned boot-log look.
  -- pcall-required with a graceful fallback to the old thin banner so a
  -- logo-load hiccup can never block boot.
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
-- #SEC H1 — visible confirmation that the operator's Shift+Enter one-time
-- boot took effect: this session runs from the fallback drive but the EEPROM
-- was left untouched, and the floppy→HDD migration offer is suppressed.
if _G._BIOS_ONETIME then
  earlyPrint("  ONE-TIME BOOT: EEPROM unchanged, boot config preserved", tc(0xFFAA00))
end
-- Safe Mode is LOUD on purpose: the operator must never wonder why their
-- services/packages aren't running. (A one-time safe boot chosen at the
-- POST screen prints its own notice there — this covers the saved profile.)
if bootCfg and bootCfg.profile == "safe" then
  earlyPrint("  SAFE MODE: services, cron, packages, net, themes are OFF", tc(0xFFAA00))
  earlyPrint("  (Boot Settings -> Profile to leave Safe Mode)", tc(0xAAAAAA))
end
if totalKB < 128 then
  earlyPrint("  WARNING: Low memory - features limited!", tc(0xFF0000))
elseif totalKB < 256 then
  earlyPrint("  NOTE: Limited memory - some features may be skipped", tc(0xFFFF00))
end
end   -- drawBootHeader

drawBootHeader()

-- ── System Configuration POST screen + DEL-to-setup (#3/#5) ──
-- Shown briefly when showConfig is on (default) — the TOS-ified AMIBIOS
-- screen: installed hardware + tiers. Press DEL during the window to enter
-- Boot Settings; any other key skips ahead. Fully guarded so a detection
-- hiccup or setup error never blocks boot.
--
-- showConfig — NOT verbosity — gates this screen. The old code also
-- required verbosity ~= "silent", which meant a silent boot hid the only
-- DEL-to-setup entry point: an operator who set "silent" could no longer
-- reach Boot Settings at all (recoverable only via the shell `bootsettings`
-- command, if they could still log in). verbosity is the boot-LOG muter;
-- showConfig is the master switch for this interactive screen. For a truly
-- silent boot, turn showConfig off as well.
-- showConfig is the master switch for this screen; a "verbose" boot ALSO
-- forces it, since the bootcfg contract lists "the hardware table" as part of
-- verbose (and a diagnostic boot should show diagnostics). Either trigger,
-- plus a GPU, opens it.
if ((bootCfg and bootCfg.showConfig) or verbosity == "verbose") and gpu then
  pcall(function()
    local sysinfo = require("kernel.sysinfo")
    -- Shared palette + GPU draw primitives (raw GPU; pre-kernel).
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

    -- Pass BOTH operator tier overrides so the POST screen honours a manually
    -- set Data Card tier (Boot Settings) instead of reporting "unknown tier".
    local inv = sysinfo.gather(nil,
      { cpuTier = bootCfg.cpuTier, dataTier = bootCfg.dataTier },
      function(msg) earlyPrint("  Standby - " .. msg .. "...", tc(0xAAAAAA)) end)
    earlyClear()
    -- Title line. sysinfo.render lays the screen out as a rigid two-column
    -- config table showing only REAL hardware (no PC-BIOS flavor). Vendor
    -- comes from kernel.logo (one source of truth); render clips to the screen.
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

    -- Wait up to 3s for a key. DEL (code 211) opens setup; S boots Safe
    -- Mode for THIS session only (config untouched — the operator's way
    -- to get a trustworthy shell after installing something that breaks
    -- boot, without editing anything first); any other key skips ahead;
    -- non-key signals are ignored until the deadline.
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
    -- The POST screen owned the whole display; put the branded header back
    -- so the rest of the boot (verify / load / progress bar) composes with
    -- it instead of floating on a blank screen.
    drawBootHeader()
    if safeOnce and bootCfg then
      bootCfg.profile = "safe"          -- in-memory only; NOT saved
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
            drawBootHeader()   -- Boot Settings owned the screen too
          end
        end
      end
    end
  end)
end

-- ============================================================
-- Stage 4: Verify & load kernel
-- ============================================================
-- Boot-critical file list resolution. Three layers, tried in order:
--
--   1. /var/pkg/installed/tos-core/package.lua
--        Primary source post-migration (commit 3). The kernel pkg
--        manager keeps this in sync with the source tree on every
--        install/uninstall.
--
--   2. /etc/critical.bak
--        Mirror written by pkg.syncCriticalBackup() after every
--        critical-set change. Lives under a different parent so
--        griefing or corruption that takes out /var/pkg/ doesn't
--        also wipe the backup.
--
--   3. /tos/system_manifest.lua  (legacy)
--        The pre-pkg-manager source of truth. Still consulted in
--        commit 1; will be deleted in commit 3 once tos-core is the
--        canonical home.
--
--   4. Hardcoded minimal list
--        Last resort if every on-disk source is missing or corrupt.
--        Just enough files to detect a totally borked install.
--
-- Anything that returns a non-empty list wins; later layers are skipped.

-- Read a file via bootFS into a single string. Used by all three
-- on-disk layers below; bootFS doesn't yet have helpers like
-- fs.readFile, so we inline the open/read/close loop.
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

-- Load + run a serialized Lua-table file in text-only mode (no
-- bytecode — see Stage 1 require for the rationale). Returns the
-- table on success, nil on parse/run failure.
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

-- Layer 1: tos-core's package.lua → manifest.critical
do
  local mf = loadTableFile("/var/pkg/installed/tos-core/package.lua", "tos-core/package")
  if mf and type(mf.critical) == "table" then
    for _, p in ipairs(mf.critical) do
      if type(p) == "string" then criticalFiles[#criticalFiles + 1] = p end
    end
    if #criticalFiles > 0 then criticalSource = "tos-core/package.lua" end
  end
end

-- Layer 2: /etc/critical.bak → flat array of paths
if #criticalFiles == 0 then
  local mf = loadTableFile("/etc/critical.bak", "critical.bak")
  if mf then
    for _, p in ipairs(mf) do
      if type(p) == "string" then criticalFiles[#criticalFiles + 1] = p end
    end
    if #criticalFiles > 0 then criticalSource = "critical.bak" end
  end
end

-- Layer 3: /tos/system_manifest.lua → entries with critical=true (legacy)
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

-- Layer 4: hardcoded minimal list. Just enough to recognize that the
-- kernel itself is intact. If even these are missing the box can't
-- boot anyway, so the goal is a clear error message rather than a
-- precise list.
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
  -- Wait for an actual key press, not any signal. Component/network
  -- events would otherwise reboot immediately (#118/#99/#101).
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

-- Splash-mode boot progress bar. In "splash" verbosity the per-stage boot
-- log is muted (log.lua), so without this the screen would just sit on the
-- wordmark / "Loading kernel..." until login. Drive a simple fill bar from
-- the kernel's boot chatter so the operator sees real progress. It's nil in
-- every other mode — the bar only earns its keep when the text log is hidden.
-- (The "text" option still shows the live log for free; this is the visual
-- counterpart the operator asked for.)
local bootProgress = nil
if verbosity == "splash" and gpu then
  -- Centre the bar (and the narration column below it, which shares barX)
  -- under the centred wordmark -- the splash reads as one designed
  -- composition.
  --
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
  -- Required BEFORE geom() below, not after: a local declared under a
  -- closure is not an upvalue of it, it is a nil global read -- and geom
  -- would then silently take its fallback branch forever.
  -- pcall so a load hiccup can never block boot; we lose the narration,
  -- not the bar.
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
  local LOG_ROWS = 3                            -- rolling high-level narration
  local stagesShown = 0                         -- distinct boot stages reached
  local stageTotal  = 16                        -- denominator (set once bootsteps loads)
  local fillCh   = isMonochrome and "#" or "█"
  local logLines = {}                           -- { {text, color}, ... } last N
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
  cursorY = math.min(screenH, barRow + LOG_ROWS + 1)  -- earlyPrint goes below

  bootProgress = function(msg, level)
    msg = tostring(msg or "")
    -- level: INFO=1, WARN=2, ERROR=3, FATAL=4 (kernel.log numbering).
    if level and level >= 2 then
      -- Never simplify or hide a problem — show it verbatim, coloured, so the
      -- bar can't paper over a warning/error.
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
    -- Not every boot reaches every stage (a minimal box skips networking,
    -- themes, compat…), so snap to full on the final line rather than relying
    -- on the count — the bar always lands at 100% exactly when boot completes.
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
    -- Boot-reorg: the spectrum config + verbosity muter (#3/#4).
    bootcfg      = bootCfg,
    bootcfgMod   = bootcfgMod,
    earlyMinLevel = earlyMinLevel,
    bootProgress = bootProgress,   -- splash-mode loading bar (nil otherwise)
  })
end, function(e)
  return tostring(e) .. "\n" .. debug.traceback("", 2)
end)

if not ok then
  earlyClear()
  earlyPrint("", tc(0xFF0000))
  earlyPrint("======= KERNEL PANIC =======", tc(0xFF0000))
  earlyPrint("", tc(0xFF6600))
  -- Split error into visible lines. Wrap at screen width instead of
  -- truncating so operators don't lose the tail of a long trace where
  -- the actual source file:line usually lives.
  local errStr = tostring(err) or "Unknown error"
  -- Flight-recorder: persist the panic so the next boot can surface it and the
  -- operator can read the full trace AFTER rebooting. Prefer the kernel helper
  -- (if boot got far enough to expose it); otherwise write via the boot FS
  -- directly, since the kernel may have died before _G._TOS.kernel existed.
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
  -- Kernel panic beep code: three low beeps
  computer.beep(400, 0.15)
  computer.pullSignal(0.05)
  computer.beep(400, 0.15)
  computer.pullSignal(0.05)
  computer.beep(400, 0.15)
  -- Wait for a real key press so stray signals don't auto-reboot the
  -- operator past the panic message (#118/#99/#101).
  while true do
    local ev = computer.pullSignal(math.huge)
    if ev == "key_down" then break end
  end
  computer.shutdown(true)
end
