-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Copy-on-write overlay                       ║
-- ║                                                           ║
-- ║  Two filesystems as one. Reads come from `upper` when it  ║
-- ║  has the file and `lower` when it does not. Every write   ║
-- ║  lands on `upper`, so `lower` is never touched and can be ║
-- ║  read-only: a floppy, a package archive, a disk you want  ║
-- ║  back as it was. Remove what a lower file shows and a     ║
-- ║  whiteout hides it. Empty `upper` and you are back where  ║
-- ║  you started.                                             ║
-- ║                                                           ║
-- ║  The result is filesystem-component-shaped, like a netfs  ║
-- ║  or a jbod proxy, so fs.mount takes it and securefs       ║
-- ║  mediates it the same way: this is a transport, not an    ║
-- ║  access layer.                                            ║
-- ╚══════════════════════════════════════════════════════════╝

local cowfs = {}

--! A whiteout is a file on `upper`, named WHITEOUT .. name beside where the
--! file was. That makes the name a hazard: anything able to create
--! ".cfsdel.config" could hide "config" without ever touching it. Through
--! the overlay it cannot, because the prefix is refused on every path that
--! creates or renames anything. The names never appear in a listing, and a
--! file of that name on `lower` is not a whiteout: only `upper` can hide.
local WHITEOUT = ".cfsdel."
cowfs.WHITEOUT = WHITEOUT

local function split(path)
  local dir, name = path:match("^(.*)/([^/]*)$")
  if not dir then return "", path end
  return dir, name
end

local function reserved(path)
  for seg in path:gmatch("[^/]+") do
    if seg:sub(1, #WHITEOUT) == WHITEOUT then return true end
  end
  return false
end

--- The overlay of `lower` and `upper`. opts.label names it in `mount`.
function cowfs.new(lower, upper, opts)
  opts = opts or {}
  local px = {}
  local handles, nextId = {}, 1

  px.type = "filesystem"
  px.address = opts.address or ("cowfs:" .. tostring(lower.address or "?"):sub(1, 8))

  function px.getLabel() return opts.label or "overlay" end
  function px.spaceTotal() return upper.spaceTotal() end
  function px.spaceUsed() return upper.spaceUsed() end
  function px.isReadOnly() return upper.isReadOnly and upper.isReadOnly() or false end

  local function whiteoutPath(path)
    local dir, name = split(path)
    return dir .. "/" .. WHITEOUT .. name
  end

  --- Hidden, by this path or by a directory above it.
  local function hidden(path)
    local p = path
    while p ~= "" and p ~= "/" do
      if upper.exists(whiteoutPath(p)) then return true end
      p = split(p)
    end
    return false
  end

  local function onLower(path)
    return not hidden(path) and lower.exists(path) == true
  end

  function px.exists(path)
    if path == "/" or path == "" then return true end
    if reserved(path) then return false end
    return upper.exists(path) == true or onLower(path)
  end

  function px.isDirectory(path)
    if path == "/" or path == "" then return true end
    if upper.exists(path) then return upper.isDirectory(path) end
    return onLower(path) and lower.isDirectory(path) == true
  end

  function px.size(path)
    if upper.exists(path) then return upper.size(path) end
    if onLower(path) then return lower.size(path) end
    return 0
  end

  function px.lastModified(path)
    if upper.exists(path) then return upper.lastModified(path) end
    if onLower(path) then return lower.lastModified(path) end
    return 0
  end

  function px.list(path)
    if not px.exists(path) then return nil, "no such directory" end
    local seen, out, gone = {}, {}, {}
    if upper.exists(path) and upper.isDirectory(path) then
      for _, name in ipairs(upper.list(path) or {}) do
        local bare = name:gsub("/$", "")
        if bare:sub(1, #WHITEOUT) == WHITEOUT then
          gone[bare:sub(#WHITEOUT + 1)] = true
        elseif not seen[bare] then
          seen[bare] = true
          out[#out + 1] = name
        end
      end
    end
    if onLower(path) and lower.isDirectory(path) then
      for _, name in ipairs(lower.list(path) or {}) do
        local bare = name:gsub("/$", "")
        if not gone[bare] and not seen[bare] then
          seen[bare] = true
          out[#out + 1] = name
        end
      end
    end
    table.sort(out)
    return out
  end

  --- Make the parents of `path` on upper, however many lower has and upper
  --- does not. A write under a lower-only directory has to land somewhere.
  local function parents(path)
    local dir = split(path)
    if dir == "" or dir == "/" or upper.exists(dir) then return end
    parents(dir)
    upper.makeDirectory(dir)
    if upper.exists(whiteoutPath(dir)) then upper.remove(whiteoutPath(dir)) end
  end

  local function unhide(path)
    if upper.exists(whiteoutPath(path)) then upper.remove(whiteoutPath(path)) end
  end

  function px.makeDirectory(path)
    if reserved(path) then return false, "reserved name" end
    if px.exists(path) then return false end
    parents(path)
    unhide(path)
    return upper.makeDirectory(path)
  end

  --- Bring a lower file up, so that it can be changed. Whole, through the
  --- handle API, because that is what a filesystem proxy has.
  local function copyUp(path)
    if upper.exists(path) or not onLower(path) then return true end
    local src, err = lower.open(path, "r")
    if not src then return nil, err end
    parents(path)
    local dst, derr = upper.open(path, "w")
    if not dst then
      lower.close(src)
      return nil, derr
    end
    while true do
      local chunk = lower.read(src, 4096)
      if not chunk then break end
      upper.write(dst, chunk)
    end
    lower.close(src)
    upper.close(dst)
    return true
  end

  function px.open(path, mode)
    mode = mode or "r"
    if reserved(path) then return nil, "reserved name" end
    local fs, h, err
    if mode:sub(1, 1) == "r" then
      if upper.exists(path) then fs = upper
      elseif onLower(path) then fs = lower
      else return nil, path end
      h, err = fs.open(path, mode)
    else
      if mode:sub(1, 1) == "a" then
        local ok, cerr = copyUp(path)
        if not ok then return nil, cerr end
      end
      parents(path)
      fs = upper
      h, err = upper.open(path, mode)
      if h then unhide(path) end
    end
    if not h then return nil, err end
    local id = nextId
    nextId = nextId + 1
    handles[id] = { fs = fs, h = h }
    return id
  end

  function px.read(id, n)
    local st = handles[id]
    if not st then return nil, "bad file handle" end
    return st.fs.read(st.h, n)
  end
  function px.write(id, data)
    local st = handles[id]
    if not st then return nil, "bad file handle" end
    return st.fs.write(st.h, data)
  end
  function px.seek(id, whence, offset)
    local st = handles[id]
    if not st then return nil, "bad file handle" end
    return st.fs.seek(st.h, whence, offset)
  end
  function px.close(id)
    local st = handles[id]
    if not st then return false end
    handles[id] = nil
    return st.fs.close(st.h)
  end
  function px.openHandles()
    local n = 0
    for _ in pairs(handles) do n = n + 1 end
    return n
  end

  function px.remove(path)
    if path == "/" or path == "" then return false end
    if reserved(path) then return false, "reserved name" end
    local there = onLower(path)
    local isDir = px.isDirectory(path)
    if isDir then
      local list = px.list(path)
      if list and #list > 0 then return false, "directory not empty" end
    end
    local gone = false
    if upper.exists(path) then gone = upper.remove(path) == true end
    if there then
      parents(path)
      local h = upper.open(whiteoutPath(path), "w")
      if not h then return false end
      upper.close(h)
      gone = true
    end
    return gone
  end

  function px.rename(from, to)
    if reserved(from) or reserved(to) then return false, "reserved name" end
    if not px.exists(from) or px.exists(to) then return false end
    if px.isDirectory(from) then
      -- A lower directory has no cheap rename: every file would come up.
      if onLower(from) then return false, "cannot rename a directory on the lower layer" end
      return upper.rename(from, to)
    end
    local ok, err = copyUp(from)
    if not ok then return false, err end
    parents(to)
    if not upper.rename(from, to) then return false end
    unhide(to)
    if lower.exists(from) and not hidden(from) then
      local h = upper.open(whiteoutPath(from), "w")
      if h then upper.close(h) end
    end
    return true
  end

  --- The files this overlay has changed, and the ones it hides: what a merge
  --- or a reset has to look at. Whiteouts come back as { path, removed = true }.
  function px.changes()
    local out = {}
    local function walk(dir)
      for _, name in ipairs(upper.list(dir) or {}) do
        local bare = name:gsub("/$", "")
        local child = (dir == "/" and "" or dir:gsub("/$", "")) .. "/" .. bare
        if bare:sub(1, #WHITEOUT) == WHITEOUT then
          local d = split(child)
          out[#out + 1] = { path = d .. "/" .. bare:sub(#WHITEOUT + 1), removed = true }
        elseif upper.isDirectory(child) then
          walk(child)
        else
          out[#out + 1] = { path = child }
        end
      end
    end
    walk("/")
    table.sort(out, function(a, b) return a.path < b.path end)
    return out
  end

  return px
end

--- `upper` emptied, for an overlay that starts clean each boot. Everything
--- under it goes, so this is only ever called on a directory of its own.
function cowfs.wipe(upper, dir)
  dir = dir or "/"
  for _, name in ipairs(upper.list(dir) or {}) do
    local bare = name:gsub("/$", "")
    local child = (dir == "/" and "" or dir:gsub("/$", "")) .. "/" .. bare
    if upper.isDirectory(child) then cowfs.wipe(upper, child) end
    upper.remove(child)
  end
end

--- Take away whatever on `upper` would hide `path`. A name that was refused
--- through the overlay was an ordinary file before there was one, so anything
--- that makes an overlay out of a used directory clears the way for what it
--- means to show.
function cowfs.unhide(upper, path)
  local p = path
  while p ~= "" and p ~= "/" do
    local dir, name = split(p)
    local w = dir .. "/" .. WHITEOUT .. name
    if upper.exists(w) then upper.remove(w) end
    p = dir
  end
end

--- Whiteouts that no longer hide anything, once `lower` has lost what they hid.
function cowfs.sweep(upper, lower, dir)
  dir = dir or "/"
  for _, name in ipairs(upper.list(dir) or {}) do
    local bare = name:gsub("/$", "")
    local child = (dir == "/" and "" or dir:gsub("/$", "")) .. "/" .. bare
    if bare:sub(1, #WHITEOUT) == WHITEOUT then
      local target = (dir == "/" and "" or dir:gsub("/$", "")) .. "/" .. bare:sub(#WHITEOUT + 1)
      if not lower.exists(target) then upper.remove(child) end
    elseif upper.isDirectory(child) then
      cowfs.sweep(upper, lower, child)
    end
  end
end

--- A directory of one disk, as a proxy of its own. This is the real /usr under
--- the package overlay: it goes straight to the disk, because fs would resolve
--- /usr back to the overlay it is part of.
function cowfs.sub(px, base)
  local function at(path)
    if path == "/" or path == "" then return base end
    return base .. (path:sub(1, 1) == "/" and "" or "/") .. path
  end
  local v = { address = tostring(px.address) .. ":" .. base }
  function v.exists(p) return px.exists(at(p)) end
  function v.isDirectory(p) return px.isDirectory(at(p)) end
  function v.size(p) return px.size(at(p)) end
  function v.lastModified(p) return px.lastModified(at(p)) end
  function v.list(p) return px.list(at(p)) end
  function v.makeDirectory(p) return px.makeDirectory(at(p)) end
  function v.remove(p) return px.remove(at(p)) end
  function v.rename(a, b) return px.rename(at(a), at(b)) end
  function v.open(p, mode) return px.open(at(p), mode) end
  v.read, v.write, v.seek, v.close = px.read, px.write, px.seek, px.close
  v.spaceTotal, v.spaceUsed = px.spaceTotal, px.spaceUsed
  function v.isReadOnly() return px.isReadOnly and px.isReadOnly() or false end
  return v
end

-- ── The root ─────────────────────────────────────────────────

--! Three things come from this: running from a read-only disk with the writes
--! on another; a kiosk that forgets everything at each boot, because `reset`
--! empties the layer; and trying something, then merging it or dropping it.
--! The layer can shadow /tos/kernel, so whoever can write to it can run code as
--! the kernel. That is why it is never mounted: diskmount passes over this disk
--! and securefs.mount refuses it, and a disk at /mnt is one a user can write to.
--! Take the disk out and the machine boots from the real root, which is the way
--! back from a layer that broke something.

cowfs.CONFIG = "/etc/overlay.cfg"
local LAYERS = "/tos-overlay"

local function layerDir(lower)
  return LAYERS .. "/" .. tostring(lower.address):sub(1, 8)
end

local function readAll(px, path)
  local h = px.open(path, "r")
  if not h then return nil end
  local parts = {}
  while true do
    local chunk = px.read(h, 4096)
    if not chunk then break end
    parts[#parts + 1] = chunk
  end
  px.close(h)
  return table.concat(parts)
end

--- What /etc/overlay.cfg asks for: the disk's address, and whether to reset.
function cowfs.parseConfig(text)
  if type(text) ~= "string" then return nil end
  local disk = text:match("disk=([%x%-]+)")
  return disk, disk ~= nil and text:match("reset=1") ~= nil
end

--- Written to the real disk, past any overlay: a boot reads it from there.
function cowfs.saveConfig(lower, disk, reset)
  local tmp = cowfs.CONFIG .. ".tmp"
  local h, err = lower.open(tmp, "w")
  if not h then return nil, err end
  local ok = lower.write(h, "disk=" .. disk .. "\n" .. (reset and "reset=1\n" or ""))
  lower.close(h)
  if not ok then
    lower.remove(tmp)
    return nil, "disk full"
  end
  if lower.exists(cowfs.CONFIG) then lower.remove(cowfs.CONFIG) end
  if not lower.rename(tmp, cowfs.CONFIG) then
    lower.remove(tmp)
    return nil, "could not write " .. cowfs.CONFIG
  end
  return true
end

--- The root for this boot. `chosen` is a disk picked at the read-only offer,
--- else /etc/overlay.cfg names one. Returns the overlay and what to keep in
--- _TOS.overlay, or nil and that, when there is no overlay to run on. The
--- layer is a directory named for the lower disk, so nothing else on the disk
--- is touched and one disk can serve several machines.
function cowfs.boot(lower, chosen, proxyOf)
  local disk, reset = chosen, false
  if not disk then disk, reset = cowfs.parseConfig(readAll(lower, cowfs.CONFIG)) end
  if not disk then return nil end
  local ok, px = pcall(proxyOf, disk)
  if not ok or not px then return nil, { missing = disk, reset = reset } end

  local dir = layerDir(lower)
  if not px.exists(dir) then px.makeDirectory(dir) end
  local upper = cowfs.sub(px, dir)
  local mark = dir .. ".drop"
  local dropped = reset or px.exists(mark)
  if dropped then
    cowfs.wipe(upper)
    px.remove(mark)
  end
  local root = cowfs.new(lower, upper, { address = lower.address,
    label = lower.getLabel and lower.getLabel() or nil })
  return root, { disk = disk, reset = reset, lower = lower, upper = upper,
                 root = root, layerDisk = px, mark = mark }
end

--- Forget the layer at the next boot. Not now: the system is running on it.
function cowfs.drop(state)
  local h, err = state.layerDisk.open(state.mark, "w")
  if not h then return nil, err end
  state.layerDisk.close(h)
  return true
end

--- Everything in the layer, onto the real disk. Each file goes to a temp name
--- first, and the layer still wins until it is dropped, so stopping half way
--- loses nothing and running it again finishes the job.
function cowfs.merge(state)
  local lower, upper = state.lower, state.upper
  local n = 0
  for _, c in ipairs(state.root.changes()) do
    if c.removed then
      if lower.exists(c.path) then lower.remove(c.path) end
    else
      local dir = split(c.path)
      if dir ~= "" and not lower.exists(dir) then lower.makeDirectory(dir) end
      local data = readAll(upper, c.path)
      if not data then return nil, "cannot read " .. c.path end
      local tmp = c.path .. ".tmp"
      local h, err = lower.open(tmp, "w")
      if not h then return nil, tostring(err) end
      local ok = lower.write(h, data)
      lower.close(h)
      if not ok or lower.size(tmp) ~= #data then
        lower.remove(tmp)
        return nil, "disk full at " .. c.path
      end
      if lower.exists(c.path) then lower.remove(c.path) end
      if not lower.rename(tmp, c.path) then return nil, "cannot replace " .. c.path end
    end
    n = n + 1
  end
  return n
end

return cowfs
