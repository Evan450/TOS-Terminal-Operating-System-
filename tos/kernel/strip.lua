-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔═══════════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Self-stripping (feature groups off the base image)║
-- ║                                                               ║
-- ║  The operator's 2026-08-11 decision (TODO, SELF-STRIPPING):   ║
-- ║  the choice of what a machine carries is made IN GAME, after  ║
-- ║  the box has done its job for a while, and TOS strips itself. ║
-- ║                                                               ║
-- ║  * FEATURE GROUPS, not files. A group is the manifest entries ║
-- ║    tagged `group = "<name>"`; nothing here keeps a list.      ║
-- ║  * THE FLOOR CANNOT BE STRIPPED. A floor or critical entry    ║
-- ║    never carries a group (test_manifest_groups.lua), and this ║
-- ║    module refuses one anyway.                                 ║
-- ║  * DESTRUCTIVE, AND IT SAYS SO. Stripping refuses unless SRM  ║
-- ║    holds a verified copy of every file, or the operator says  ║
-- ║    out loud that the files come back only from the network or ║
-- ║    an install disk (`strip <group> --no-copy`).               ║
-- ║  * REMOVED ON PURPOSE IS NOT MISSING. /etc/stripped.cfg holds ║
-- ║    what was stripped; verify, srm scan, the online repair and ║
-- ║    deploy read it, so none of them cries deletion or puts the ║
-- ║    files back. The manifest itself is not rewritten: it stays ║
-- ║    the release's exact bytes, so its EEPROM anchor still      ║
-- ║    holds.                                                     ║
-- ╚═══════════════════════════════════════════════════════════════╝
-- Loaded only when asked for (the `strip` command and the checks that
-- consult isStripped); nothing at boot requires it.

local strip = {}

strip.STATE = "/etc/stripped.cfg"

local cache = nil   -- path -> group, for isStripped; nil = not read yet

function strip.deps(d)
  d = d or {}
  local T = rawget(_G, "_TOS") or {}
  d.fs = d.fs or T.fs or package.loaded["kernel.fs"]
  if not d.serialize then
    local ok, s = pcall(require, "kernel.serialize"); d.serialize = ok and s or nil
  end
  if d.manifest == nil then
    local ok, m = pcall(require, "system_manifest"); d.manifest = ok and m or nil
  end
  -- _TOS.log is a function (src, msg), not the module: take the module.
  d.log = d.log or (type(T.log) == "table" and T.log) or package.loaded["kernel.log"]
  return d
end

--- The groups the manifest defines: { name = { {path=, ...entry}, ... } }.
function strip.groups(deps)
  deps = strip.deps(deps)
  local out = {}
  for _, e in ipairs(type(deps.manifest) == "table" and deps.manifest or {}) do
    if type(e) == "table" and type(e.group) == "string" and type(e.path) == "string" then
      out[e.group] = out[e.group] or {}
      table.insert(out[e.group], e)
    end
  end
  return out
end

--- What has been stripped: { groups = { name = { at =, files = {...} } } }.
function strip.state(deps)
  deps = strip.deps(deps)
  local fs, ser = deps.fs, deps.serialize
  local st = { groups = {} }
  if fs and ser and fs.exists and fs.exists(strip.STATE) then
    local raw = fs.readFile(strip.STATE)
    local ok, t = pcall(ser.decode, raw or "", { maxBytes = 64 * 1024 })
    if ok and type(t) == "table" and type(t.groups) == "table" then st = t end
  end
  return st
end

local function save(deps, st)
  local fs, ser = deps.fs, deps.serialize
  if not (fs and ser) then return false, "no filesystem" end
  local data = ser.encode(st)
  local write = fs.writeFileAtomic or fs.writeFile
  local ok, err = write(strip.STATE, data)
  cache = nil
  return ok, err
end

--- Was this path stripped on purpose? Cheap after the first call.
function strip.isStripped(path, deps)
  if cache == nil then
    cache = {}
    local st = strip.state(deps)
    for name, g in pairs(st.groups or {}) do
      for _, p in ipairs(type(g.files) == "table" and g.files or {}) do cache[p] = name end
    end
  end
  return cache[path] ~= nil, cache[path]
end

--- Forget the cached state (after a strip or a restore, or in tests).
function strip.reset() cache = nil end

--- Every group with its size and whether it is here.
--- @return { { name, files, bytes, stripped, present } } sorted by name
function strip.list(deps)
  deps = strip.deps(deps)
  local fs = deps.fs
  local st = strip.state(deps)
  local rows = {}
  for name, entries in pairs(strip.groups(deps)) do
    local bytes, present = 0, 0
    for _, e in ipairs(entries) do
      if fs.exists(e.path) then
        present = present + 1
        bytes = bytes + (tonumber(fs.size(e.path)) or 0)
      end
    end
    rows[#rows + 1] = { name = name, files = #entries, bytes = bytes, present = present,
                        stripped = st.groups[name] ~= nil }
  end
  table.sort(rows, function(a, b) return a.name < b.name end)
  return rows
end

--- Which of the group's files SRM holds a verified copy of.
local function storedCopies(paths)
  local okS, srm = pcall(require, "kernel.srm")
  if not okS or type(srm) ~= "table" or not srm.loadIndex then return {}, 0 end
  local idx = srm.loadIndex()
  local have, n = {}, 0
  for _, p in ipairs(paths) do
    local f = idx and idx.files and idx.files[p]
    if f and f.stored then have[p] = true; n = n + 1 end
  end
  return have, n
end

--- Would strip(name, opts) go ahead? The same refusals, touching nothing,
--- so a shell can refuse BEFORE asking the operator to confirm.
--- @return paths | nil, why
function strip.check(deps, name, opts)
  deps = strip.deps(deps)
  opts = opts or {}
  local entries = strip.groups(deps)[name]
  if not entries then return nil, "no feature group called '" .. tostring(name) .. "'" end
  local st = strip.state(deps)
  if st.groups[name] then return nil, "'" .. name .. "' is already stripped" end
  local paths = {}
  for _, e in ipairs(entries) do
    if e.floor or e.critical then
      return nil, e.path .. " is in the floor, and the floor is never stripped"
    end
    paths[#paths + 1] = e.path
  end
  --! An SRM baseline stores copies of the CRITICAL files only, and a copy on
  --! this same disk would cancel what stripping saves, so for a group the
  --! way back is media: an install disk (`strip restore --from`) or the
  --! network (`--online`). The operator says they know that with --no-copy;
  --! only a group SRM happens to hold every file of goes without it.
  local _, stored = storedCopies(paths)
  if stored < #paths and not opts.noCopy then
    return nil, string.format("SRM holds a copy of %d of %d files in '%s', so the rest "
      .. "come back only from an install disk ('strip restore %s --from <mount>') or the "
      .. "network ('--online'). Say you accept that with --no-copy.", stored, #paths, name, name)
  end
  return paths
end

--- Strip one group. opts.noCopy: the operator accepts that the files come
--- back only from the network or an install disk. The caller gates on root.
--- @return ok, report { removed, freed, failed = {...} } | false, why
function strip.strip(deps, name, opts)
  deps = strip.deps(deps)
  opts = opts or {}
  local fs = deps.fs
  local paths, why = strip.check(deps, name, opts)
  if not paths then return false, why end
  local st = strip.state(deps)
  -- The record goes first: a strip cut off half way leaves files marked as
  -- stripped that are still here, never files gone that nothing explains.
  st.groups[name] = { at = math.floor((os.time and os.time()) or 0), files = paths }
  local okW, werr = save(deps, st)
  if not okW then return false, "could not record the strip: " .. tostring(werr) end
  local rep = { removed = 0, freed = 0, failed = {} }
  for _, p in ipairs(paths) do
    if fs.exists(p) then
      local sz = tonumber(fs.size(p)) or 0
      local okR = fs.remove(p)
      if okR and not fs.exists(p) then
        rep.removed = rep.removed + 1
        rep.freed = rep.freed + sz + 512   -- OC charges 512 B a file
      else
        rep.failed[#rep.failed + 1] = p
      end
    end
  end
  -- A directory the strip emptied costs what a file does: it goes too.
  -- (writeFile recreates parents, so a restore needs nothing back.)
  for _, p in ipairs(paths) do
    local dir = p:match("^(.+)/[^/]+$")
    if dir and dir ~= "" and fs.exists(dir) and fs.list then
      local okL, list = pcall(fs.list, dir)
      if okL and type(list) == "table" and #list == 0 then
        fs.remove(dir)
        rep.freed = rep.freed + 512
      end
    end
  end
  if deps.log and deps.log.info then
    pcall(deps.log.info, "strip", string.format("Stripped '%s': %d file(s), %d bytes", name,
      rep.removed, rep.freed))
  end
  return true, rep
end

--- Put a stripped group back. From SRM's verified copies where it holds
--- them; with opts.online, the rest through the online repair, which
--- checks every byte against the manifest's digest. A group is unmarked
--- only once every file is here again.
--- @return ok, report { restored, missing = {...}, lines = {...} } | false, why
function strip.restore(deps, name, opts)
  deps = strip.deps(deps)
  opts = opts or {}
  local fs = deps.fs
  local st = strip.state(deps)
  local g = st.groups[name]
  if not g then return false, "'" .. tostring(name) .. "' is not stripped" end
  local paths = type(g.files) == "table" and g.files or {}
  local rep = { restored = 0, missing = {}, lines = {} }

  local have = storedCopies(paths)
  local fromStore = {}
  for _, p in ipairs(paths) do
    if not fs.exists(p) and have[p] then fromStore[#fromStore + 1] = p end
  end
  if #fromStore > 0 then
    local okS, srm = pcall(require, "kernel.srm")
    if okS and srm and srm.restore then
      local r = srm.restore(nil, { paths = fromStore })
      for _, l in ipairs(r and r.findings or {}) do rep.lines[#rep.lines + 1] = l end
    end
  end

  -- From a mounted TOS disk (the install disk, a `deploy`ed drive): each file
  -- is checked against this machine's manifest digest before it is written,
  -- so a disk of another build, or a damaged one, cannot put back the wrong
  -- bytes. A manifest entry with no digest is copied only with --unverified.
  if opts.from then
    local digest = {}
    for _, e in ipairs(type(deps.manifest) == "table" and deps.manifest or {}) do
      if type(e) == "table" and e.path then digest[e.path] = e.hash end
    end
    local okC, crypto = pcall(require, "kernel.crypto")
    local base = tostring(opts.from):gsub("/+$", "")
    for _, p in ipairs(paths) do
      if not fs.exists(p) then
        local src = base .. p
        local data = fs.exists(src) and fs.readFile(src) or nil
        local want = digest[p]
        if not data then
          rep.lines[#rep.lines + 1] = { text = "not on " .. base .. ": " .. p, sev = "warn" }
        elseif want and not (okC and crypto and crypto.hash
            and crypto.hash(data):lower() == tostring(want):lower()) then
          rep.lines[#rep.lines + 1] = { text = "NOT the release's bytes, left alone: " .. src, sev = "err" }
        elseif not want and not opts.unverified then
          rep.lines[#rep.lines + 1] = { text = "no digest to check " .. p .. " against (--unverified copies it)", sev = "warn" }
        else
          local write = fs.writeFileAtomic or fs.writeFile
          if write(p, data) then
            rep.lines[#rep.lines + 1] = { text = "from " .. base .. ": " .. p, sev = "ok" }
          end
        end
      end
    end
  end

  local still = {}
  for _, p in ipairs(paths) do if not fs.exists(p) then still[#still + 1] = p end end
  if #still > 0 and opts.online then
    -- The online repair sees a stripped file as stripped, not damaged, so it
    -- is handed a manifest of exactly these entries.
    local want = {}
    for _, p in ipairs(still) do want[p] = true end
    local sub = {}
    for _, e in ipairs(type(deps.manifest) == "table" and deps.manifest or {}) do
      if type(e) == "table" and want[e.path] then sub[#sub + 1] = e end
    end
    local okN, nr = pcall(require, "kernel.netrepair")
    if okN and nr and nr.run then
      local r = nr.run({ manifest = sub, stripAware = false },
        { apply = true, unanchored = opts.unanchored, ref = opts.ref })
      for _, l in ipairs(r and r.lines or {}) do rep.lines[#rep.lines + 1] = l end
    else
      rep.lines[#rep.lines + 1] = { text = "the online repair is not on this machine", sev = "err" }
    end
  end

  for _, p in ipairs(paths) do
    if fs.exists(p) then rep.restored = rep.restored + 1 else rep.missing[#rep.missing + 1] = p end
  end
  if #rep.missing == 0 then
    st.groups[name] = nil
    local okW, werr = save(deps, st)
    if not okW then return false, "files are back, but the record was not updated: " .. tostring(werr) end
    if deps.log and deps.log.info then
      pcall(deps.log.info, "strip", "Restored '" .. name .. "': " .. rep.restored .. " file(s)")
    end
  end
  return #rep.missing == 0, rep
end

return strip
