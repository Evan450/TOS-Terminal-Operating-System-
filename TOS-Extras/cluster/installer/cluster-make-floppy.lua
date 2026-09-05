-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster-make-floppy — build a cluster install disk          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- One command. Picks a target floppy, copies the cluster install
-- wizard + the two cluster packages (master + manager) onto it with
-- the layout the installer expects to find:
--
--   /                cluster-install.lua  (the wizard)
--   /cluster/        cluster-master/      (package src)
--   /cluster/        cluster-manager/     (package src)
--
-- After running this, the workshop's floppy is ready to bring to any
-- TOS machine — boot it, mount, `run /mnt/<label>/cluster-install.lua`.
--
-- Run as: cluster-make-floppy [--source <src-root>] [--target <addr>]
--   --source  defaults to the workshop's `/usr/repo` plus the
--             installed locations of cluster-master + cluster-manager.
--             Pass an explicit path when you're building from a TOS
--             tree mounted somewhere unusual (e.g. /mnt/host).
--   --target  exact floppy modem address. Defaults to the first
--             floppy-shaped (capacity < 2 MB) filesystem component
--             that isn't the boot disk.

local component = require("component")
local computer  = require("computer")

-- Compat: try kernel.fs (TOS) first, then OpenOS "filesystem".
local fs
do
  local okT, m = pcall(require, "kernel.fs")
  if okT and m then fs = m
  else fs = require("filesystem") end
end

local function ok(m)   io.write("  \027[32mok\027[0m   " .. m .. "\n") end
local function fail(m) io.write("  \027[31mfail\027[0m " .. m .. "\n") end
local function warn(m) io.write("  \027[33mwarn\027[0m " .. m .. "\n") end
local function info(m) io.write("       " .. m .. "\n") end

-- ============================================================
-- Argument parsing
-- ============================================================

local args = {...}
local opts = { source = nil, target = nil, force = false }
local i = 1
while i <= #args do
  local a = args[i]
  if a == "--source" and args[i + 1] then opts.source = args[i + 1]; i = i + 2
  elseif a == "--target" and args[i + 1] then opts.target = args[i + 1]; i = i + 2
  elseif a == "--force"  then opts.force = true; i = i + 1
  elseif a == "--help" or a == "-h" then
    print("Usage: cluster-make-floppy [--source <dir>] [--target <addr>] [--force]")
    print("  Builds a cluster install disk on a mounted floppy.")
    print("  --source defaults to /usr/repo (or whichever local mount has the")
    print("           cluster packages).")
    print("  --target defaults to the first non-boot floppy-sized filesystem.")
    print("  --force  overwrite an existing /cluster/ tree on the target.")
    os.exit(0)
  else
    io.stderr:write("unknown arg: " .. a .. "\n"); os.exit(1)
  end
end

-- ============================================================
-- Find the package source
-- ============================================================

local function probeSource()
  if opts.source then
    if fs.exists(opts.source) and fs.isDirectory(opts.source) then
      return opts.source
    end
    fail("--source path doesn't exist or isn't a directory: " .. opts.source)
    os.exit(1)
  end
  -- Try the standard repo locations + any /mnt/<label>/cluster/ tree
  -- (an already-built floppy can re-seed another).
  local candidates = { "/usr/repo", "/var/repo" }
  if fs.exists and fs.exists("/mnt") then
    local list = fs.list("/mnt") or {}
    for _, label in ipairs(list) do
      local clean = label:gsub("/$", "")
      if clean ~= "" then
        candidates[#candidates + 1] = "/mnt/" .. clean
        candidates[#candidates + 1] = "/mnt/" .. clean .. "/cluster"
      end
    end
  end
  for _, c in ipairs(candidates) do
    if fs.exists(c) and fs.isDirectory(c) then
      -- A valid source has BOTH cluster-master and cluster-manager (or
      -- their *-skeleton equivalents) as subdirs.
      local entries = fs.list(c) or {}
      local has_master, has_manager = false, false
      for _, e in ipairs(entries) do
        local n = e:gsub("/$", "")
        if n == "cluster-master" or n == "master-skeleton" then has_master = true end
        if n == "cluster-manager" or n == "manager-skeleton" then has_manager = true end
      end
      if has_master and has_manager then return c end
    end
  end
  return nil
end

-- ============================================================
-- Find the target floppy
-- ============================================================

local function probeTarget()
  if opts.target then
    local ok2, prx = pcall(component.proxy, opts.target)
    if not ok2 or not prx then
      fail("--target component not reachable: " .. opts.target)
      os.exit(1)
    end
    return opts.target, prx
  end
  -- Look for a filesystem component whose capacity < 2 MB (a "floppy"
  -- by OC sizing) and which isn't the boot drive.
  local bootAddr
  local okB, addr = pcall(computer.getBootAddress)
  if okB then bootAddr = addr end
  local best, bestProxy
  for addr in component.list("filesystem") do
    if addr ~= bootAddr then
      local ok2, prx = pcall(component.proxy, addr)
      if ok2 and prx then
        local cap = (prx.spaceTotal and prx.spaceTotal()) or 0
        -- OC floppies are 512 KB; <2 MB filters out HDDs (8+ MB).
        if cap > 0 and cap < 2 * 1024 * 1024 then
          best, bestProxy = addr, prx; break
        end
      end
    end
  end
  return best, bestProxy
end

-- ============================================================
-- File copy
-- ============================================================

local function copyDirTree(srcAbs, dstAbs, opts2)
  opts2 = opts2 or {}
  local function visit(rel)
    local s = srcAbs .. rel
    local d = dstAbs .. rel
    if fs.isDirectory(s) then
      if not fs.exists(d) then fs.makeDirectory(d) end
      local list = fs.list(s) or {}
      for _, name in ipairs(list) do
        local clean = name:gsub("/$", "")
        if clean ~= "" then visit(rel .. "/" .. clean) end
      end
    else
      -- Skip the directory entry / archive metadata files that some
      -- editors leave behind. Real source files don't have these names.
      if rel:find("/%.swp$") or rel:find("/%.bak$") then return end
      local data = fs.readFile(s)
      if data then
        local parentDir = d:match("^(.+)/[^/]+$")
        if parentDir and not fs.exists(parentDir) then
          fs.makeDirectory(parentDir)
        end
        fs.writeFile(d, data)
        if opts2.onFile then opts2.onFile(rel, #data) end
      end
    end
  end
  visit("")
end

-- ============================================================
-- Main
-- ============================================================

print("\027[1;36mcluster-make-floppy\027[0m")
print("")
print("Looking for cluster source...")
local sourceDir = probeSource()
if not sourceDir then
  fail("No cluster package source found.")
  info("Tried: /usr/repo, /var/repo, /mnt/<label>/, /mnt/<label>/cluster/")
  info("Pass --source <path> if the cluster tree is somewhere else.")
  os.exit(1)
end
ok("Source: " .. sourceDir)

print("Looking for target floppy...")
local targetAddr, targetProxy = probeTarget()
if not targetAddr then
  fail("No suitable floppy found. Insert a blank floppy and rerun.")
  info("Pass --target <addr> if your floppy isn't detected automatically.")
  os.exit(1)
end
ok("Target: " .. targetAddr:sub(1, 12) .. "... (" ..
   math.floor((targetProxy.spaceTotal() or 0) / 1024) .. " KB)")

-- Determine a mount label so the rest of the script can use a path,
-- not the raw component proxy. The TOS auto-mount picks up new floppies
-- under /mnt/<label>/; if it hasn't yet, mount manually.
local label = (targetProxy.getLabel and targetProxy.getLabel()) or "cluster-disk"
if not label or label == "" then label = "cluster-disk" end
-- Set the label so the target is recognisable when re-inserted.
pcall(targetProxy.setLabel, label)
local mountPath = "/mnt/" .. label
-- Ensure the floppy is mounted at /mnt/<label>. If TOS's auto-mount
-- already did this we're a no-op; otherwise mount via fs.mount.
if not fs.exists(mountPath) then
  if fs.mount then
    local mok, merr = pcall(fs.mount, mountPath, targetProxy)
    if not mok then
      warn("could not auto-mount target: " .. tostring(merr))
      info("Eject and reinsert the floppy so TOS's auto-mount picks it up,")
      info("then rerun this command.")
      os.exit(1)
    end
  end
end
ok("Mounted at " .. mountPath)

-- Refuse to clobber a populated /cluster/ unless --force.
local destClusterDir = mountPath .. "/cluster"
if fs.exists(destClusterDir) and not opts.force then
  local existing = fs.list(destClusterDir) or {}
  if #existing > 0 then
    fail("Target already has a /cluster/ tree (" .. #existing .. " entries).")
    info("Pass --force to overwrite.")
    os.exit(1)
  end
end

-- Copy the wizard.
print("Copying installer...")
local wizardSrcCandidates = {
  sourceDir .. "/installer/cluster-install.lua",
  sourceDir .. "/cluster-install.lua",
  -- The wizard may also live alongside the cluster source dir if the
  -- operator's workshop layout has them as siblings.
  (sourceDir:match("^(.*)/cluster$") or sourceDir) .. "/installer/cluster-install.lua",
}
local wizardSrc
for _, c in ipairs(wizardSrcCandidates) do
  if fs.exists(c) then wizardSrc = c; break end
end
if not wizardSrc then
  fail("Wizard not found. Tried:")
  for _, c in ipairs(wizardSrcCandidates) do info("  " .. c) end
  os.exit(1)
end
local data = fs.readFile(wizardSrc)
fs.writeFile(mountPath .. "/cluster-install.lua", data)
ok("cluster-install.lua  (" .. #data .. " bytes)")

-- Copy the cluster packages.
if not fs.exists(destClusterDir) then fs.makeDirectory(destClusterDir) end
local fileCount, byteTotal = 0, 0
local function tally(rel, n)
  fileCount = fileCount + 1
  byteTotal = byteTotal + n
end

for _, pkg in ipairs({ "cluster-master", "cluster-manager",
                       "master-skeleton", "manager-skeleton" }) do
  local pkgSrc = sourceDir .. "/" .. pkg
  if fs.exists(pkgSrc) and fs.isDirectory(pkgSrc) then
    print("Copying " .. pkg .. " ...")
    -- Normalize the destination name: master-skeleton → cluster-master
    -- so the installer's repo-discovery sees the canonical name. The
    -- skeleton dirs are dev-side convention; on the floppy we want the
    -- runtime names that match the package.lua's `name` field.
    local destName = pkg
    if pkg == "master-skeleton"  then destName = "cluster-master"  end
    if pkg == "manager-skeleton" then destName = "cluster-manager" end
    local destPkg = destClusterDir .. "/" .. destName
    if fs.exists(destPkg) and opts.force then
      -- Recursive remove via a walk (kernel.fs.remove is single-entry).
      local function rmrf(p)
        if fs.isDirectory(p) then
          for _, n in ipairs(fs.list(p) or {}) do
            local c = n:gsub("/$", "")
            if c ~= "" then rmrf(p .. "/" .. c) end
          end
        end
        pcall(fs.remove, p)
      end
      rmrf(destPkg)
    end
    copyDirTree(pkgSrc, destPkg, { onFile = tally })
    ok(destName)
  end
end

-- Floppy capacity check.
local used = (targetProxy.spaceUsed and targetProxy.spaceUsed()) or 0
local total = (targetProxy.spaceTotal and targetProxy.spaceTotal()) or 0
print("")
print(string.format("Wrote %d files (%d KB) — disk %d / %d KB used",
  fileCount, math.floor(byteTotal / 1024),
  math.floor(used / 1024), math.floor(total / 1024)))
print("")
print("\027[32mFloppy ready.\027[0m Insert it into a TOS machine and run:")
print("  \027[1mrun /mnt/" .. label .. "/cluster-install.lua\027[0m")
