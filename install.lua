-- ╔══════════════════════════════════════╗
-- ║  TOS Installer                       ║
-- ║  Terminal Operating System           ║
-- ║  Interactive setup + install disk    ║
-- ╚══════════════════════════════════════╝
-- Version lives ONLY in the INSTALLER_VERSION constant below (the banner
-- reads it) — keep no literal version in this header to avoid drift.
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
--   # install.lua --help        (what it does, and how to choose a drive)
--
-- In install-disk mode, when the machine has more than one writable drive
-- (or the boot drive is too small), it asks which drive TOS goes on instead
-- of assuming the one OpenOS is running from.

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

-- Single source of truth for the version string. Update only the
-- INSTALLER_VERSION constant; the banner reads it. Previously the
-- header comment said v1.2.6 while the banner displayed v0.3.0 —
-- two-place version drift caught in code review.
local INSTALLER_VERSION = "1.5.0"

-- Runtime directories TOS expects at first boot. Keep in sync with
-- /tos/kernel/init.lua's coreDirs list (single source of truth lives
-- in the kernel; this duplicate exists because install.lua runs from
-- OpenOS BEFORE the TOS kernel is reachable). If you add an entry
-- here, also add it there.
local RUNTIME_DIRS = {
  "/tos", "/tos/kernel", "/tos/kernel/net", "/tos/shell",
  "/tos/compat", "/tos/peripheral", "/tos/shell/panels",
  "/etc", "/etc/rc.d",
  "/home", "/public", "/root",
  "/usr", "/usr/bin", "/usr/lib", "/usr/modules",
  "/var", "/var/log", "/var/run", "/var/pkg", "/var/pkg/installed",
  "/tmp",
}

-- Embedded TOS wordmark — kept byte-identical to kernel.logo.MARK. Embedded
-- (not required) because the installer runs from OpenOS before the TOS kernel
-- is reachable.
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

-- ============================================================
-- Install disk detection
-- ============================================================
-- If this script lives on a disk that also contains
-- /tos/kernel/init.lua, we're in install-disk mode.

-- `explicitSrc`, when given, is a caller-supplied source directory that
-- skips detection entirely — the door a scripted or chain-loaded install
-- uses (bootstrap.lua passes the directory it just staged from the
-- network here) instead of relying on path inference, which has no
-- reason to hold for a script that was loadfile()'d rather than run as
-- a shell command.
local function findInstallDisk(explicitSrc)
  if not fs then return nil end

  -- Method 0: explicit override.
  if type(explicitSrc) == "string" and explicitSrc ~= "" then
    local p = explicitSrc:sub(-1) == "/" and explicitSrc:sub(1, -2) or explicitSrc
    if fs.exists(p .. "/tos/kernel/init.lua") then return p end
  end

  -- Method 1: detect from the script's own path (OpenOS sets _ env).
  -- Generalized to any containing directory rather than requiring a
  -- literal /mnt/<name> prefix — that assumption broke for anything not
  -- mounted under /mnt (a devfs path, a loop-mounted directory, a
  -- staged temp folder) even though the same "sibling tos/kernel/init.lua"
  -- check is exactly as valid there.
  local scriptPath = os.getenv and os.getenv("_") or nil
  if scriptPath then
    local dir = scriptPath:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and fs.exists(dir .. "/tos/kernel/init.lua") then
      return dir
    end
  end

  -- Method 2: scan all filesystems for one with both install.lua
  -- and the TOS kernel — but NOT the boot drive. Each proxy call is
  -- pcall-wrapped: a filesystem component can throw (e.g. a disk
  -- ejected mid-scan), and one flaky component must not abort the
  -- whole detection pass for every other one.
  local bootAddr = computer.getBootAddress()
  for addr in component.list("filesystem") do
    if addr ~= bootAddr then
      local okP, px = pcall(component.proxy, addr)
      if not okP then px = nil end
      local okE1, hasKernel = pcall(function() return px and px.exists("/tos/kernel/init.lua") end)
      local okE2, hasInstall = pcall(function() return px and px.exists("/install.lua") end)
      if okE1 and okE2 and hasKernel and hasInstall then
        -- Find its mount point
        if fs.mounts then
          local okM, mounts = pcall(fs.mounts)
          if okM and mounts then
            --! OpenOS's fs.mounts() yields (proxy, path). This read the pair
            --! as (path, proxy), so `proxy.address` indexed a string and the
            --! whole scan matched nothing -- it has never found a disk. Take
            --! either order.
            for a, b in mounts do
              local proxy, path = a, b
              if type(a) == "string" then proxy, path = b, a end
              if type(proxy) == "table" and proxy.address == addr then
                return tostring(path)
              end
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
  -- Measured on a headless OpenComputers machine (`tos.py floorcheck`):
  -- below 1 MB there is no usable shell, and the full interface needs
  -- 1.5 MB (bootcfg.PANELS_MIN_KB), so below that TOS starts at the CLI.
  -- A network card or linked card brings up the network stack and its
  -- services, about 170 KB more: with one, 1 MB starts the command line
  -- but no command loads, so the floor is 1.25 MB. This warned only below
  -- 1 MB, so a 1 MB machine with a network card -- a common build --
  -- installed without a word and could not run a command.
  local networked = hw.hasModem or hw.hasTunnel
  if hw.memKB < 1024 or (networked and hw.memKB < 1280) then
    if networked then
      warn("Not enough memory: with a network card TOS needs 1.25 MB (1 MB without one).")
    else
      warn("Not enough memory: TOS needs at least 1 MB (one Tier 3.5 stick).")
    end
    warn("With less its commands do not load, or it does not boot.")
  elseif hw.memKB < 1536 then
    warn("TOS will start at the command line: the full interface needs 1.5 MB.")
  end
  print()
end

-- ============================================================
-- File copy (install disk mode)
-- ============================================================

-- Load the install disk's manifest. The manifest is the canonical
-- file list — drives copy AND post-copy verification. Previously the
-- copy was a directory walk filtered to *.lua, which silently skipped
-- non-Lua files including the bundled module.cfg files (and would
-- also miss any future binary asset, theme file, README, etc.). The
-- manifest is the single source of truth.
local function loadManifest(srcDisk)
  local path = srcDisk .. "/tos/system_manifest.lua"
  if not fs.exists(path) then return nil, "no manifest at " .. path end
  local h = io.open(path, "r")
  if not h then return nil, "cannot open manifest" end
  local source = h:read("*a")
  h:close()
  if not source then return nil, "empty manifest" end
  -- #SEC H3 — parse manifest as DATA via serialize.decode, not as
  -- executable Lua. The old loader did `load(source); pcall()` which
  -- ran the manifest body in the installer process — anything in the
  -- file's top-level statements executed before we even checked the
  -- return type. We try serialize.decode first (the manifest's normal
  -- format is `return { ... }` table literal), and only if that fails
  -- do we fall back to the load() path with a warning. A defensive
  -- size cap blocks pathological inputs.
  if #source > 256 * 1024 then
    return nil, "manifest exceeds 256 KB sanity cap"
  end
  local okS, ser = pcall(require, "kernel.serialize")
  if okS and ser and ser.decode then
    local data, derr = ser.decode(source, { maxBytes = 256 * 1024 })
    if data and type(data) == "table" then
      return data
    elseif data == nil then
      -- Fall through to load() — older manifests that used non-literal
      -- expressions (string concat for paths, etc.) won't parse via
      -- serialize.decode but ARE legitimate.
      warn("manifest serialize.decode failed (" .. tostring(derr) ..
        "); falling back to constrained load()")
    end
  end
  -- Text-only mode: never load bytecode from the install disk.
  local fn, err = load(source, "=manifest", "t", { })  -- empty env: no globals reachable
  if not fn then return nil, "manifest parse error: " .. tostring(err) end
  local ok2, result = pcall(fn)
  if not ok2 then return nil, "manifest run error: " .. tostring(result) end
  if type(result) ~= "table" then return nil, "manifest did not return a table" end
  return result
end

-- #SEC H3 — refuse to overwrite an existing TOS install without a root
-- password check (or an explicit --force-wipe flag). The audit's worst
-- case is a malicious install disk inserted into a working machine; if
-- the operator is at the BIOS prompt with no password yet (firstBoot
-- root account), the install proceeds unrestricted. We can't ask for
-- the password from inside the BIOS chain-load path, but we CAN refuse
-- to silently overwrite a populated /etc/users.dat — the operator must
-- type FORCE-WIPE to acknowledge.
local function preInstallSafetyCheck(forceWipe, root)
  if forceWipe then return true end
  root = root or ""
  if fs.exists(root .. "/etc/users.dat") then
    local h = io.open(root .. "/etc/users.dat", "r")
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

-- Chunked file copy. Reads the source in 4 KiB blocks instead of
-- pulling the whole thing into RAM with `*a` first — important on
-- 192 KB machines where a large module + a partial copy of itself
-- can OOM the install. Mirrors the same pattern init.lua's
-- in-bootloader copier already uses (line 143).
local function copyFileChunked(src, dst)
  local ih = io.open(src, "r")
  if not ih then return false, "open source" end
  local oh = io.open(dst, "w")
  if not oh then ih:close(); return false, "open dest" end
  while true do
    local chunk = ih:read(4096)
    if not chunk then break end
    --! OpenOS answers a full disk with nil, "not enough space" rather than
    --! raising, so a write that RETURNS a failure is one too -- the loop
    --! used to carry on writing until verifyCopy noticed the short file.
    --! fs.writeAll's twin (AUDIT 5). The last buffered block is written by
    --! the flush, and OpenOS's buffer:close() drops what its own flush
    --! answers, so the flush is made here, where it can be checked: it
    --! returns the buffer, or nil and the reason. (test_install_copy_write.lua)
    local wOk, wRes, wErr = pcall(oh.write, oh, chunk)
    if not wOk or not wRes then
      ih:close(); pcall(oh.close, oh)
      return false, "write: " .. tostring(wOk and (wErr or "failed") or wRes)
    end
  end
  ih:close()
  if oh.flush then
    local fOk, fRes, fErr = pcall(oh.flush, oh)
    if not fOk or not fRes then
      pcall(oh.close, oh)
      return false, "write: " .. tostring(fOk and (fErr or "flush failed") or fRes)
    end
  end
  oh:close()
  return true
end

-- Post-copy verification: every file declared in the manifest must
-- exist on the target with size matching the source. A truncated
-- write (out-of-space, partial buffer) makes the file present but
-- short; without this check, the BIOS flash would proceed onto a
-- silently broken install and brick the box on next boot.
local function verifyCopy(srcDisk, manifest, root)
  root = root or ""
  local missing, sized = {}, {}
  for _, entry in ipairs(manifest) do
    local target = root .. entry.path
    if not fs.exists(target) then
      missing[#missing + 1] = target
    else
      local srcSize = fs.size(srcDisk .. entry.path) or 0
      local dstSize = fs.size(target) or 0
      if srcSize ~= dstSize then
        sized[#sized + 1] = string.format("%s (src=%d dst=%d)", target, srcSize, dstSize)
      end
    end
  end
  return missing, sized
end

-- Bytes the copy will ADD to the target: each file's size, less what a file
-- already at that path takes (a re-install overwrites it), plus
-- OpenComputers' per-entry cost (`fileCost`, 512 bytes by default) for every
-- file and directory that is new. Pure: `size(path)` and `exists(path)` are
-- passed in, so test_install_space.lua runs it without a machine.
--
-- Checked BEFORE anything is written. Without it an install onto a drive
-- that is too small -- a Tier 2 drive that already holds OpenOS is the
-- common one -- copied until the drive filled and stopped halfway, which
-- the README warned about and nothing on screen did.
local FILE_COST = 512
-- `root` is the mount point of the drive being installed onto ("" for the
-- drive OpenOS booted from, whose root is "/"), so the same arithmetic prices
-- any candidate drive before anything is written to it.
local function spaceNeeded(srcDisk, manifest, size, exists, root)   --[[TEST-EXTRACT]]
  root = root or ""
  local need, dirs = 0, {}
  for _, entry in ipairs(manifest) do
    local bytes = size(srcDisk .. entry.path) or 0
    if exists(root .. entry.path) then
      need = need + math.max(0, bytes - (size(root .. entry.path) or 0))
    else
      need = need + bytes + FILE_COST
    end
    local dir = entry.path:match("^(.+)/[^/]+$")
    while dir and dir ~= "" and not dirs[dir] do
      dirs[dir] = true
      if not exists(root .. dir) then need = need + FILE_COST end
      dir = dir:match("^(.+)/[^/]+$")
    end
  end
  return need
end                                                           --[[/TEST-EXTRACT]]

local function freeOnTarget(root)
  local okG, proxy = pcall(fs.get, (root == nil or root == "") and "/" or root)
  if not okG or not proxy then return nil end
  local okT, total = pcall(proxy.spaceTotal)
  local okU, used = pcall(proxy.spaceUsed)
  if not (okT and okU) or type(total) ~= "number" or total <= 0 then return nil end
  return total - used
end

-- ============================================================
-- Which drive does TOS go on?
-- ============================================================
-- The installer used to write to "/" and nothing else: the drive OpenOS
-- booted from. That is the wrong drive whenever the machine has a second
-- one the player means to use (a bigger drive, a fresh one, the one in the
-- rack), and a dead end when the boot drive is too small, because the only
-- option on offer was to stop. Every candidate drive is priced with the same
-- spaceNeeded() the copy uses, so what is offered here is what will fit.

--- Which candidate is the default, and which of them have room. `cands` is a
--- list of { isBoot, free, need }; an unknown `free` is let through, the way
--- freeOnTarget() returning nil already is. The boot drive stays the default
--- when it fits, so a machine with one drive behaves exactly as before.
local function rankTargets(cands)   --[[TEST-EXTRACT]]
  local fits, default = {}, nil
  for i, c in ipairs(cands) do
    fits[i] = (c.free == nil) or (c.free >= c.need)
  end
  for i, c in ipairs(cands) do
    if c.isBoot and fits[i] then default = i; break end
  end
  if not default then
    for i = 1, #cands do
      if fits[i] then default = i; break end
    end
  end
  return default, fits
end                                  --[[/TEST-EXTRACT]]

--- Split the arguments into help requests, unknown options and positionals.
--- "-h" and "--help" used to be taken as a source directory (here) or a
--- malformed owner/repo (bootstrap.lua), so a player who typed the obvious
--- thing got a confusing warning instead of help.
local function classifyArgs(args)   --[[TEST-EXTRACT]]
  local out = { positional = {} }
  for _, a in ipairs(args) do
    if a == "-h" or a == "--help" or a == "-?" or a == "/?" then
      out.help = true
    elseif type(a) == "string" and a:sub(1, 1) == "-" then
      out.unknown = out.unknown or a
    else
      out.positional[#out.positional + 1] = a
    end
  end
  return out
end                                 --[[/TEST-EXTRACT]]

-- Every path the mounted drives are reachable at, by component address.
-- OpenOS's fs.mounts() yields (proxy, path); findInstallDisk below read the
-- pair the other way round for as long as it has existed, so tolerate both.
local function mountPaths()
  local byAddr = {}
  if not (fs and fs.mounts) then return byAddr end
  local okM, it = pcall(fs.mounts)
  if not okM or type(it) ~= "function" then return byAddr end
  for a, b in it do
    local proxy, path = a, b
    if type(a) == "string" then proxy, path = b, a end
    local addr = type(proxy) == "table" and proxy.address or nil
    if addr and type(path) == "string" then
      byAddr[addr] = byAddr[addr] or {}
      byAddr[addr][#byAddr[addr] + 1] = path
    end
  end
  return byAddr
end

local function bestMount(paths)
  for _, p in ipairs(paths) do if p:sub(1, 5) == "/mnt/" then return p end end
  for _, p in ipairs(paths) do if p ~= "/" then return p end end
  return nil
end

local function kbText(n)
  if n >= 1024 * 1024 then return string.format("%.1f MB", n / 1024 / 1024) end
  return string.format("%d KB", math.floor(n / 1024))
end

-- Writable drives TOS could go on. Left out: the scratch tmpfs, anything
-- read-only, and the install disk itself (installing a disk onto itself is
-- never the intent). Boot drive first, then by mount point.
local function listTargets(srcDisk, manifest)
  local mounts = mountPaths()
  local bootAddr = computer.getBootAddress()
  local tmpAddr = computer.tmpAddress and computer.tmpAddress() or nil
  local src = srcDisk:sub(-1) == "/" and srcDisk:sub(1, -2) or srcDisk
  local cands, unmounted = {}, 0
  for addr in component.list("filesystem") do
    local okP, px = pcall(component.proxy, addr)
    local okR, ro = false, true
    if okP and px then okR, ro = pcall(px.isReadOnly) end
    if addr ~= tmpAddr and okP and px and okR and not ro then
      local paths = mounts[addr] or {}
      local isBoot = addr == bootAddr
      local prefix = isBoot and "" or bestMount(paths)
      local isSource = false
      for _, p in ipairs(paths) do if p == src then isSource = true end end
      if isSource then
        -- the install disk
      elseif not prefix then
        unmounted = unmounted + 1
      else
        local c = { address = addr, prefix = prefix, isBoot = isBoot }
        local okL, label = pcall(px.getLabel)
        c.label = okL and label or nil
        local okT, total = pcall(px.spaceTotal)
        local okU, used = pcall(px.spaceUsed)
        if okT and okU and type(total) == "number" and total > 0 then
          c.total, c.free = total, total - used
        end
        local okI, hasInit = pcall(px.exists, "/init.lua")
        local okK, hasTos = pcall(px.exists, "/tos/kernel/init.lua")
        c.hasInit = okI and hasInit or false
        c.hasTos = okK and hasTos or false
        c.need = manifest and spaceNeeded(srcDisk, manifest, fs.size, fs.exists, prefix) or 0
        cands[#cands + 1] = c
      end
    end
  end
  table.sort(cands, function(a, b)
    if a.isBoot ~= b.isBoot then return a.isBoot end
    return a.prefix < b.prefix
  end)
  return cands, unmounted
end

local function describeTarget(c)
  local name = c.isBoot and "the boot drive" or ("the drive at " .. c.prefix)
  if c.label and c.label ~= "" then name = name .. ' "' .. c.label .. '"' end
  return name
end

--- Ask which drive. Returns the chosen candidate, or nil when none has room
--- (with "space" as the second value, so the caller does not call it a
--- cancellation) or the player cancels. With a single drive that fits nothing is asked, so
--- the common one-drive machine sees no change.
local function chooseTarget(srcDisk, manifest)
  local cands, unmounted = listTargets(srcDisk, manifest)
  if #cands == 0 then return { address = computer.getBootAddress(), prefix = "", isBoot = true, need = 0 } end
  local default, fits = rankTargets(cands)
  if #cands == 1 and default == 1 then return cands[1] end

  color(0x00AAFF); print("--- Where should TOS go? ---"); color(0xFFFFFF)
  for _, c in ipairs(cands) do
    if c.isBoot and c.free and c.free < c.need then
      warn(string.format("The boot drive has %s free; TOS needs %s.",
        kbText(c.free), kbText(c.need)))
    end
  end
  for i, c in ipairs(cands) do
    local head = string.format("  %d. %s%s", i, c.isBoot and "Boot drive" or c.prefix,
      (c.label and c.label ~= "") and ('  "' .. c.label .. '"') or "")
    if fits[i] then color(0xFFFFFF) else color(0x888888) end
    print(head .. (i == default and "   <- default" or ""))
    local size = c.total and string.format("%s, %s free", kbText(c.total), kbText(c.free)) or "size unknown"
    local note = {}
    if c.hasTos then note[#note + 1] = "has TOS" elseif c.hasInit then note[#note + 1] = "has an OS" else note[#note + 1] = "empty" end
    if not fits[i] then note[#note + 1] = "too small: needs " .. kbText(c.need) end
    color(0xAAAAAA)
    print("     " .. size .. "; " .. table.concat(note, ", "))
  end
  color(0xFFFFFF)
  if unmounted > 0 then
    warn(unmounted .. " more drive(s) are not mounted, so they are not listed.")
  end
  if not default then
    print()
    fail("None of these drives has room for TOS.")
    warn("Install onto a bigger drive: a Tier 3 drive (4 MB) holds OpenOS and")
    warn("TOS together; a Tier 2 drive (2 MB) only holds TOS on its own.")
    return nil, "space"
  end
  print()
  while true do
    local pick = ask("Install on which drive? (0 = cancel)", nil, tostring(default))
    local n = tonumber(pick)
    if n == 0 then return nil end
    if n and cands[n] then
      if fits[n] then return cands[n] end
      warn("That drive is too small: TOS needs " .. kbText(cands[n].need) .. ".")
    else
      warn("Type a number from the list.")
    end
  end
end

local function copyFromDisk(srcDisk, root, preloaded)
  root = root or ""
  -- Load manifest first — installer is useless without it. (The drive
  -- picker already read it to price each drive; reuse that rather than
  -- repeating its warnings.)
  local manifest, mErr = preloaded, nil
  if not manifest then manifest, mErr = loadManifest(srcDisk) end
  if not manifest then
    fail("Cannot load install manifest: " .. tostring(mErr))
    return false
  end
  ok("Manifest loaded: " .. #manifest .. " files declared")

  local need = spaceNeeded(srcDisk, manifest, fs.size, fs.exists, root)
  local free = freeOnTarget(root)
  if free and need > free then
    print()
    fail(string.format("Not enough space: TOS needs %d KB on this drive, and %d KB is free.",
      math.ceil(need / 1024), math.floor(free / 1024)))
    warn("Nothing was copied. Install onto a bigger drive: a Tier 3 drive")
    warn("(4 MB) holds OpenOS and TOS together; a Tier 2 drive (2 MB) only")
    warn("holds TOS on its own.")
    return false, "space"
  end
  if free then
    ok(string.format("Space: TOS needs %d KB, and %d KB is free", math.ceil(need / 1024),
      math.floor(free / 1024)))
  end
  print()

  -- Pre-create every directory mentioned in the manifest. fs.writeFile
  -- on the boot proxy creates parents but io.open does not, so we walk
  -- the manifest paths and ensure the dirname of each is present
  -- before the copy.
  color(0x00AAFF); print("--- Creating directories ---"); color(0xFFFFFF)
  local dirSeen = {}
  for _, entry in ipairs(manifest) do
    local dir = entry.path:match("^(.+)/[^/]+$")
    while dir and dir ~= "" and not dirSeen[dir] do
      dirSeen[dir] = true
      if not fs.isDirectory(root .. dir) then fs.makeDirectory(root .. dir) end
      dir = dir:match("^(.+)/[^/]+$")
    end
  end
  -- Plus the runtime directories TOS expects to find at boot. Single
  -- source instead of duplicating across install-disk + standalone.
  for _, d in ipairs(RUNTIME_DIRS) do
    if not fs.isDirectory(root .. d) then fs.makeDirectory(root .. d) end
  end
  ok("Directory structure created")
  print()

  -- Copy every manifest entry. Track failures explicitly — on any
  -- failure the BIOS flash gate later refuses to proceed.
  color(0x00AAFF); print("--- Copying system files ---"); color(0xFFFFFF)
  local copied, failed = 0, 0
  local errs = {}
  for _, entry in ipairs(manifest) do
    local src = srcDisk .. entry.path
    local dst = root .. entry.path
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

  -- Post-copy size verification. Catches truncated writes that
  -- copyFileChunked thought succeeded.
  if failed == 0 then
    color(0x00AAFF); print("--- Verifying copy ---"); color(0xFFFFFF)
    local missing, sized = verifyCopy(srcDisk, manifest, root)
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

-- ============================================================
-- Clean install — shed OpenOS leftovers
-- ============================================================
-- The operator boots OpenOS only as a bootstrap host; once TOS is copied
-- onto the same drive, the OpenOS *libraries* are dead weight (TOS never
-- requires them) and clutter the new system tree. A clean install removes
-- the two top-level trees OpenOS owns that TOS never uses — /bin and /lib.
--
-- DELIBERATELY conservative:
--   * Only /bin and /lib. /etc, /usr, /home, /tmp, /mnt, /var, /tos and
--     /init.lua are shared, TOS-owned, or user data and are NEVER touched
--     (a blind manifest-diff of /etc would delete the /etc/tos.cfg we just
--     wrote and the /etc/users.dat TOS mints on first boot).
--   * Caller gates this on a fully-verified copy. Removing OpenOS's runtime
--     before TOS is safely in place would brick the box (no working OS).
--   * Run as the LAST action before reboot: the still-running OpenOS lazy-
--     loads from /lib, so we pull it only when nothing else will need it.
--! Must stay identical to the TREES list in the `reclaim` command
--! (tos/shell/panels/commands/admin.lua). Two lists, two files, same
--! job: this one runs at install time, reclaim runs later for a machine
--! that said no then or was never asked. test_reclaim.lua compares them
--! and fails on any divergence.
--!
--! /boot was missing here. The installer's clean-install offer removed
--! /bin and /lib and left OpenOS's twelve boot scripts sitting there, so
--! a "clean install" was not one.
--!
--! Verified safe against the manifest rather than assumed: TOS installs
--! 152 files and none of them land in any of these trees.
local OPENOS_ONLY_TREES = { "/bin", "/boot", "/lib" }

--! INSTALLING TOS REPLACES /init.lua, and nothing used to put the old one
--! back: a shared disk that had another OS on it did not become bootable
--! again by deleting /tos. The displaced loader is kept as
--! /init.lua.pre-tos (OpenOS's is 843 bytes), so renaming it back restores
--! the old boot as long as that OS's own files are still there. Kept ONCE
--! and only when it is not TOS's own loader: a re-install over TOS must not
--! replace the real backup with a copy of TOS. It is a NEW file, never an
--! overwrite. (test_install_preinit.lua)
local PRE_TOS = "/init.lua.pre-tos"
--! `root` is the mount point of the drive TOS went onto ("" = the boot
--! drive). These three act on THAT drive: with a second drive chosen, "/bin"
--! must mean its /bin, never the boot drive's.
local function preserveForeignInit(root)
  root = root or ""
  if not fs or not fs.exists(root .. "/init.lua") or fs.exists(root .. PRE_TOS) then return false end
  local h = io.open(root .. "/init.lua", "r")
  if not h then return false end
  local body = h:read("*a"); h:close()
  if not body or body == "" or body:find("_TOS", 1, true) then return false end
  local w = io.open(root .. PRE_TOS, "w")
  if not w then return false end
  w:write(body); w:close()
  return fs.exists(root .. PRE_TOS)
end

local function hasOpenOsLeftovers(root)
  root = root or ""
  if not fs then return false end
  for _, d in ipairs(OPENOS_ONLY_TREES) do
    if fs.exists(root .. d) then return true end
  end
  return false
end
local function cleanOpenOsLeftovers(root)
  root = root or ""
  local removed = {}
  if not fs then return removed end
  for _, d in ipairs(OPENOS_ONLY_TREES) do
    if fs.exists(root .. d) then
      -- OpenOS filesystem.remove deletes directories recursively.
      local okR = pcall(fs.remove, root .. d)
      if okR and not fs.exists(root .. d) then removed[#removed + 1] = d end
    end
  end
  -- Without its /lib the old loader boots nothing; keeping it would only
  -- suggest it still could.
  if #removed > 0 and fs.exists(root .. PRE_TOS) then
    pcall(fs.remove, root .. PRE_TOS)
    if not fs.exists(root .. PRE_TOS) then removed[#removed + 1] = PRE_TOS end
  end
  return removed
end

-- ============================================================
-- BIOS flash
-- ============================================================

local function offerBiosFlash(srcDisk)
  local biosPath = srcDisk .. "/bios.lua"
  if not fs.exists(biosPath) then return end

  -- #SEC H3 — surface a fingerprint of the BIOS we're about to flash
  -- and require an explicit typed confirmation, not just a y/N.
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

local function writeConfig(cfg, root)
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
  local f = io.open((root or "") .. "/etc/tos.cfg", "w")
  if f then f:write(table.concat(lines, "\n")); f:close(); return true end
  return false
end

-- ============================================================
-- Main
-- ============================================================

-- The first positional argument, when given, is an explicit source directory
-- override (see findInstallDisk's Method 0) — bootstrap.lua uses this to
-- hand off a network-staged directory that has no reason to sit under /mnt
-- or bear any fixed relation to this script's own path. A leading "-" is an
-- option, not a directory: --help explains, anything else is refused rather
-- than being treated as a path that does not exist.
local parsed = classifyArgs({...})

term.clear()
header()

if parsed.help or parsed.unknown then
  if parsed.unknown and not parsed.help then
    fail("Unknown option: " .. tostring(parsed.unknown))
    print()
  end
  print("Copies TOS onto a drive, asks a few setup questions, and")
  print("offers to flash the TOS BIOS.")
  print()
  print("Usage:")
  print("  install.lua [source-dir]")
  print("  install.lua --help")
  print()
  print("Run it from an install disk (/mnt/<disk>/install.lua), or")
  print("let bootstrap.lua stage a download for it.")
  print()
  print("With more than one writable drive it asks which one TOS")
  print("goes on; the boot drive is only the default. If the boot")
  print("drive is too small it offers the others. TOS can then be")
  print("made the boot drive at the end.")
  print()
  print("source-dir  a directory holding a TOS release, for")
  print("            scripted installs. Normally found by itself.")
  print()
  print("With no install disk it only changes the settings of a")
  print("TOS that is already installed.")
  return
end

local hw = surveyHardware()
printHardwareReport(hw)

-- Detect install disk.
local srcDisk = findInstallDisk(parsed.positional[1])
local diskMode = srcDisk ~= nil

-- The drive TOS goes on: "" is the drive OpenOS booted from (root "/"),
-- anything else is the mount point of another drive (set in disk mode).
local TARGET, targetDrive = "", nil
local preloadedManifest

-- A copy-success flag carried through the whole install.
-- Set true only when the file copy AND the post-copy size verification
-- both pass. Gates the BIOS flash later — no opt-out.
local copyOk = false
-- Clean-install intent: when set, shed OpenOS's /bin + /lib at the very
-- end so TOS doesn't inherit the bootstrap host's filesystem. Captured
-- only in disk mode, only after a verified copy, only with leftovers present.
local cleanInstall = false

if diskMode then
  ok("Install disk found at: " .. srcDisk)
  print()

  -- Which drive? Asked only when there is a choice to make (see
  -- chooseTarget); a one-drive machine goes straight on as before.
  preloadedManifest = loadManifest(srcDisk)
  local chooseWhy
  targetDrive, chooseWhy = chooseTarget(srcDisk, preloadedManifest)
  if not targetDrive then
    print()
    if chooseWhy ~= "space" then print("Cancelled.") end
    return
  end
  TARGET = targetDrive.prefix
  print()

  color(0xFFFF00)
  if targetDrive.isBoot then
    print("TOS will be installed on the current boot drive.")
    print("Your /init.lua will be replaced (the current one is kept as")
    print("/init.lua.pre-tos; rename it back to boot the old system).")
  else
    print("TOS will be installed on " .. describeTarget(targetDrive) .. ".")
    print("Its /init.lua will be replaced (the current one, if any, is kept")
    print("there as /init.lua.pre-tos). The drive this machine boots from")
    print("is not changed unless you choose that at the end.")
  end
  color(0xFFFFFF)
  print()
  if not confirm("Continue?") then print("Cancelled."); return end
  print()

  -- #SEC H3 — refuse to overwrite an existing install without typed
  -- confirmation. --force-wipe on the command line bypasses (for
  -- scripted installs); without it the operator must type FORCE-WIPE.
  if not preInstallSafetyCheck(_G._FORCE_WIPE or false, TARGET) then return end

  if preserveForeignInit(TARGET) then ok("Kept the previous /init.lua as " .. TARGET .. PRE_TOS) end

  -- Copy system files from install disk. On failure we still allow
  -- the user to proceed to the questionnaire (so config can be saved
  -- against whatever copied successfully), but the BIOS flash gate
  -- below refuses unconditionally.
  local copyWhy
  copyOk, copyWhy = copyFromDisk(srcDisk, TARGET, preloadedManifest)
  if copyWhy == "space" then print(); return end
  if not copyOk then
    fail("Install file copy/verify did NOT fully succeed.")
    warn("BIOS flash will be skipped to avoid bricking the boot.")
    warn("You can retry installation; the partial files won't conflict.")
    if not confirm("Continue to questionnaire anyway?") then print("Cancelled."); return end
    print()
  end

  -- Clean install: offer to shed OpenOS leftovers, but only when TOS is
  -- safely in place (copyOk) and there's actually something to remove.
  if copyOk and hasOpenOsLeftovers(TARGET) then
    color(0x00AAFF); print("--- Clean install ---"); color(0xFFFFFF)
    color(0xAAAAAA)
    print("OpenOS's own files (/bin, /boot, /lib) are still on this drive.")
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
  -- Standalone mode: just configure an existing installation
  color(0xFFFF00)
  print("No install disk detected - running in configuration mode.")
  print("TOS system files must already be present on the boot drive.")
  color(0xFFFFFF)
  print()
  if not confirm("Continue?") then print("Cancelled."); return end
  print()
end

-- Run the setup questionnaire BEFORE any BIOS flash. Previously the
-- BIOS flash happened first, so a user who Ctrl+C'd during the
-- questionnaire was left with the BIOS pointing at an unconfigured
-- install and no /etc/tos.cfg. Reordered so the point-of-no-return
-- (BIOS flash) is the very last action.
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
if diskMode and copyOk then
  print("  Clean inst: " .. (cleanInstall and "Yes (remove /bin, /boot, /lib)" or "No"))
end
color(0xFFFFFF)
print()
if not confirm("Apply these settings?") then print("Cancelled."); return end
print()

-- Create directories (standalone mode may need this too).
-- Uses the same RUNTIME_DIRS list as the install-disk path so the
-- two flows can't diverge.
color(0x00AAFF); print("--- Applying configuration ---"); color(0xFFFFFF)
if fs then
  for _, d in ipairs(RUNTIME_DIRS) do
    if not fs.isDirectory(TARGET .. d) then fs.makeDirectory(TARGET .. d) end
  end
end

if writeConfig(cfg, TARGET) then
  ok("Configuration saved to " .. TARGET .. "/etc/tos.cfg")
else
  warn("Could not save config (defaults will be used)")
end
ok("Device profile: " .. cfg.device)
print()

-- BIOS flash (install-disk mode only, and only if the copy fully
-- verified). This is the last action before reboot — if the user
-- bails out from here, /etc/tos.cfg is already on disk and the
-- existing BIOS still points at the previous installation, so they
-- can rerun install.lua without bricking anything.
if diskMode then
  if copyOk then
    offerBiosFlash(srcDisk)
  else
    warn("Skipping BIOS flash: file copy did not fully verify.")
    warn("Re-run install.lua to retry before flashing.")
    print()
  end
end

-- TOS went onto a drive the machine does not boot from, so it would come
-- up in OpenOS again. The boot address lives on the EEPROM and both the
-- stock Lua BIOS and the TOS BIOS honour it; setting it is the normal way
-- to move the boot, and it needs no flash.
local switchedBoot = false
if diskMode and copyOk and targetDrive and not targetDrive.isBoot then
  color(0x00AAFF); print("--- Boot drive ---"); color(0xFFFFFF)
  print("TOS is on " .. describeTarget(targetDrive) .. ", but this machine")
  print("boots from a different drive, so it would start that system.")
  if confirm("Boot from the TOS drive from now on?") then
    local okB, errB = pcall(computer.setBootAddress, targetDrive.address)
    if okB then
      switchedBoot = true
      ok("Boot drive set to " .. targetDrive.address:sub(1, 8))
    else
      warn("Could not set the boot drive: " .. tostring(errB))
    end
  end
  if not switchedBoot then
    warn("The boot drive is unchanged. To switch later, run `lua` and type:")
    print("  require('computer').setBootAddress('" .. targetDrive.address .. "')")
  end
  print()
end

-- Clean install (the VERY last filesystem action before reboot). Gated on
-- a verified copy so we never strip OpenOS's runtime out from under a
-- half-installed box. Run here — after every other write — because the
-- still-running OpenOS lazy-loads from /lib until the moment we reboot.
if diskMode and copyOk and cleanInstall then
  color(0x00AAFF); print("--- Cleaning OpenOS leftovers ---"); color(0xFFFFFF)
  local removed = cleanOpenOsLeftovers(TARGET)
  if #removed > 0 then
    ok("Removed: " .. table.concat(removed, ", "))
    warn("OpenOS is no longer bootable on this drive — reboot into TOS.")
  else
    warn("Nothing to remove (already clean).")
  end
  print()
end

-- Done
color(0x00AAFF); print("--- Installation Complete ---"); color(0xFFFFFF)
print()
color(0x00FF00)
if diskMode and copyOk then
  if targetDrive and not targetDrive.isBoot and not switchedBoot then
    print("TOS is installed, but this machine still boots from another drive.")
  else
    print("TOS is installed! Reboot to start.")
  end
elseif diskMode then
  print("Partial install — re-run from the install disk to retry.")
else
  print("Configuration applied!")
end
print("First boot asks you to set the root password before anything else.")
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
