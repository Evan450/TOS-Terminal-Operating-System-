-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Disk mounting                              ║
-- ║                                                          ║
-- ║  Every disk that is not the boot disk is mounted at      ║
-- ║  /mnt/<label>, at boot AND when it is plugged in later.  ║
-- ║  One module so both follow one naming rule.              ║
-- ╚══════════════════════════════════════════════════════════╝
--
--! WHY THE KERNEL MOUNTS HOT-PLUGGED DISKS. A disk inserted after boot was
--! mounted by the panels shell's event loop, and by nothing else. So:
--!   * while the package picker held the seat, the shell's loop was not
--!     running, and the floppy the picker's own "Insert disk 1" modal asked
--!     for was never mounted -- Continue could only ask again, forever
--!     (headless machine, 2026-10-09, the two Optional Utilities floppies);
--!   * the CLI shell has no hot-plug handling at all, so on a CLI box an
--!     inserted floppy was never mounted, whatever was running.
--! The kernel's component_added listener runs whoever holds the seat, so
--! it mounts here and then tells the shells (tos_disk_added /
--! tos_disk_removed), which only have to announce it.
--! (test_diskmount.lua)

local diskmount = {}

local fs, log = nil, nil
local bootAddr = nil
-- address -> { mountPoint = ..., label = ... } for every disk mounted here.
local mounted = {}

function diskmount.init(deps)
  fs, log = deps.fs, deps.log
  bootAddr = deps.bootAddr
  mounted = {}
end

--- A disk's user-supplied label as a safe mount-point name. Labels are
--- attacker-controllable (any player can label a disk "../etc"), so only
--- alphanumerics, underscore, hyphen and space survive, runs of spaces
--- collapse, at most 32 characters, and anything left empty (or "." / "..")
--- falls back to "disk_" plus the address stub.
function diskmount.sanitizeLabel(raw, addr)
  local fallback = "disk_" .. tostring(addr or "????"):sub(1, 4)
  if type(raw) ~= "string" then return fallback end
  local cleaned = raw:gsub("[^%w_%- ]", "_")
  cleaned = cleaned:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if cleaned == "" then return fallback end
  if #cleaned > 32 then cleaned = cleaned:sub(1, 32) end
  if cleaned == "." or cleaned == ".." then return fallback end
  return cleaned
end

-- A mount point is taken by another mount, a file, or a directory with
-- something in it. An EMPTY directory is not: fs.mount mounts over one, as
-- boot always did (the shell's old hot-plug mount created /mnt/<label> on
-- the boot disk and left it behind, so the same floppy came back as
-- /mnt/<label>_<stub> on its second insert).
local function taken(path)
  for _, m in ipairs(fs.mounts and fs.mounts() or {}) do
    if m.mountPoint == path then return true end
  end
  if not fs.exists(path) then return false end
  if not fs.isDirectory(path) then return true end
  local items = fs.list(path)
  return type(items) == "table" and #items > 0
end

--- Mount disk `addr` (its filesystem `proxy`) at /mnt/<label>. Two disks
--- with one label get the second one suffixed with its address stub, and
--- then a number. Never the boot disk; a disk already mounted here answers
--- where it is.
--- @return mountPoint, label | nil, reason
function diskmount.mount(addr, proxy)
  if type(addr) ~= "string" or not proxy then return nil, "no disk" end
  --! #SEC H26 -- never the boot disk under /mnt, which would shadow the
  --! protected tree; and with no known boot address, mount nothing.
  if not bootAddr then return nil, "boot disk unknown" end
  if addr == bootAddr then return nil, "the boot disk" end
  if mounted[addr] then return mounted[addr].mountPoint, mounted[addr].label end
  --! No type() test on getLabel: an OpenComputers component method is a
  --! CALLABLE TABLE (machine.lua), so `type(proxy.getLabel) == "function"`
  --! is false on every real disk -- which is how this module was first
  --! committed (a310346), mounting every labelled floppy as /mnt/disk_<stub>
  --! on the headless machine. pcall answers both
  --! "no such method" and "it errored".
  local rawLabel = nil
  local okL, lbl = pcall(function() return proxy.getLabel() end)
  if okL and type(lbl) == "string" and lbl ~= "" then rawLabel = lbl end
  local mountPoint = "/mnt/" .. diskmount.sanitizeLabel(rawLabel, addr)
  if taken(mountPoint) then
    local stubbed = mountPoint .. "_" .. addr:sub(1, 4)
    local candidate, n = stubbed, 2
    while taken(candidate) and n < 100 do
      candidate = stubbed .. "_" .. n
      n = n + 1
    end
    mountPoint = candidate
  end
  local ok, err = fs.mount(mountPoint, proxy)
  if ok == false then return nil, err end
  local label = rawLabel or mountPoint:match("[^/]+$")
  mounted[addr] = { mountPoint = mountPoint, label = label }
  if log then log.info("kernel", "Mounted " .. addr:sub(1, 8) .. " at " .. mountPoint) end
  return mountPoint, label
end

--- Unmount the disk at `addr`, if it was mounted here.
--- @return mountPoint, label | nil
function diskmount.unmount(addr)
  local m = mounted[addr]
  if not m then return nil end
  mounted[addr] = nil
  pcall(fs.unmount, m.mountPoint)
  if log then log.info("kernel", "Unmounted " .. tostring(addr):sub(1, 8) .. " from " .. m.mountPoint) end
  return m.mountPoint, m.label
end

--- Where disk `addr` is mounted, and the label it was mounted under.
function diskmount.mountPointOf(addr)
  local m = mounted[addr]
  if m then return m.mountPoint, m.label end
  return nil
end

return diskmount
