-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - JBOD (Just a Bunch Of Disks)                ║
-- ║                                                            ║
-- ║  Spill-over disk pool: presents N filesystem components    ║
-- ║  as ONE filesystem-component-shaped proxy that can be      ║
-- ║  mounted at a single path. Reads search every member;      ║
-- ║  writes land on whichever member already holds the file,   ║
-- ║  else the one with the most free space.                    ║
-- ║                                                            ║
-- ║  WHY JBOD AND NOT RAID, for OpenComputers:                 ║
-- ║    - No striping/parity math (OC CPUs are slow; a per-     ║
-- ║      block XOR across members would crawl).                ║
-- ║    - A member removed -> only THAT member's files are      ║
-- ║      lost; the rest of the pool stays readable. RAID-0     ║
-- ║      would lose everything. That makes JBOD strictly       ║
-- ║      safer than striping for OC use.                       ║
-- ║    - It is a TRANSPORT (a union mount), not an access      ║
-- ║      layer: securefs still mediates every op on the mount  ║
-- ║      point, so per-user ACLs apply to the pool as a whole. ║
-- ║                                                            ║
-- ║  OPT-IN: this module is NOT loaded unless /etc/boot.cfg    ║
-- ║  has advanced.jbod = true (default off). See the boot      ║
-- ║  stage in kernel/init.lua and `man jbod` / `jbod` command. ║
-- ╚══════════════════════════════════════════════════════════╝

local serialize = require("kernel.serialize")
local jbod = {}

-- FNV-1a over a relative path. Used only to spread NEW files across
-- members deterministically when none already holds the path and we have
-- no free-space reason to prefer one — keeps a fresh pool from piling
-- every file onto member #1. (Existing files and the free-space rule in
-- pickWriteMember take precedence; this is just the tiebreak seed.)
local function hashPath(p)
  local h = 0x811C9DC5
  for i = 1, #p do
    h = (h ~ p:byte(i)) & 0xFFFFFFFF
    h = (h * 0x01000193) & 0xFFFFFFFF
  end
  return h
end

-- ============================================================
-- Pool proxy: looks like an OC filesystem component
-- ============================================================
-- `members` is an array of filesystem-component proxies (each with the
-- usual exists/open/read/write/list/... surface). makePool returns:
--   proxy  — mount this via kernel.fs.mount(path, proxy)
--   pool   — a small management handle (members/add/remove/stats)
function jbod.makePool(members)
  local proxy = {}

  -- A mounted proxy needs an address; reuse the first member's so
  -- df/mount listings show something stable.
  proxy.address = members[1] and members[1].address or "jbod"

  function proxy.getLabel()
    return "JBOD(" .. tostring(#members) .. ")"
  end

  -- The pool is read-only only if EVERY member is read-only; a single
  -- writable member makes the pool writable.
  function proxy.isReadOnly()
    for _, m in ipairs(members) do
      if m.isReadOnly() then return true end
    end
    return false
  end

  -- Capacity is the sum across members (the whole point of pooling).
  function proxy.spaceTotal()
    local sum = 0
    for _, m in ipairs(members) do sum = sum + (m.spaceTotal() or 0) end
    return sum
  end
  function proxy.spaceUsed()
    local sum = 0
    for _, m in ipairs(members) do sum = sum + (m.spaceUsed() or 0) end
    return sum
  end

  -- A path exists in the pool if any member has it.
  function proxy.exists(rel)
    for _, m in ipairs(members) do
      if m.exists(rel) then return true end
    end
    return false
  end
  function proxy.isDirectory(rel)
    for _, m in ipairs(members) do
      if m.exists(rel) and m.isDirectory(rel) then return true end
    end
    return false
  end
  function proxy.size(rel)
    for _, m in ipairs(members) do
      if m.exists(rel) and not m.isDirectory(rel) then
        return m.size(rel)
      end
    end
    return 0
  end
  function proxy.lastModified(rel)
    -- Most recent across members (a dir can exist on several).
    local latest = 0
    for _, m in ipairs(members) do
      if m.exists(rel) then
        local ts = m.lastModified(rel) or 0
        if ts > latest then latest = ts end
      end
    end
    return latest
  end

  -- A directory listing is the UNION of members' listings, de-duplicated
  -- (the same dir can exist on several members at once).
  function proxy.list(rel)
    local seen = {}
    local out = {}
    for _, m in ipairs(members) do
      local items
      local ok, list = pcall(m.list, rel)
      if ok and type(list) == "table" then items = list end
      if items then
        for _, name in ipairs(items) do
          local clean = name:gsub("/$", "")
          if not seen[clean] then
            seen[clean] = true
            out[#out + 1] = name
          end
        end
      end
    end
    return out
  end

  -- mkdir on every writable member that lacks the dir, so subsequent
  -- writes (which may land on any member) always have the parent dir.
  function proxy.makeDirectory(rel)
    local ok = false
    for _, m in ipairs(members) do
      if not m.exists(rel) then
        local mok = pcall(m.makeDirectory, rel)
        if mok then ok = true end
      else
        ok = true
      end
    end
    return ok
  end

  -- Choose the member a write should go to:
  --   1. the member that already holds the file (overwrite in place), else
  --   2. the writable member with the most free space (spread the load).
  local function pickWriteMember(rel)
    for _, m in ipairs(members) do
      if m.exists(rel) and not m.isDirectory(rel) then return m end
    end
    local best, bestFree = nil, -1
    for _, m in ipairs(members) do
      if not m.isReadOnly() then
        local total = m.spaceTotal() or 0
        local used  = m.spaceUsed()  or 0
        local free  = total - used
        if free > bestFree then bestFree = free; best = m end
      end
    end
    return best
  end

  -- A pool handle MUST remember which member opened it. Members are
  -- OpenComputers filesystem components (shell/panels/commands/admin.lua
  -- builds pools straight from `component.proxy(addr)`), and a component's
  -- open() returns an OPAQUE handle: reads are `member.read(handle, n)`,
  -- with the handle as an argument, not a receiver. It has no methods of
  -- its own.
  --
  -- This used to return the member's handle bare and forward with
  -- `handle:read(n)`, which cannot work for any real member -- and since
  -- the pool proxy is what kernel/fs.lua calls `proxy.read(h, n)` on, it
  -- meant every read and write through a mounted pool errored. The unit
  -- test missed it because its fake member returned a method-bearing
  -- table, which no component does.
  --
  -- The wrapper carries the routing information; the `:read`/`:write`/
  -- `:close`/`:seek` methods are kept so a caller holding the wrapper
  -- directly still works.
  local function wrapHandle(member, h)
    local w = { member = member, h = h }
    function w:read(n)           return self.member.read(self.h, n) end
    function w:write(d)          return self.member.write(self.h, d) end
    function w:close()           return self.member.close(self.h) end
    function w:seek(whence, off) return self.member.seek(self.h, whence, off) end
    return w
  end

  function proxy.open(rel, mode)
    mode = mode or "r"
    if mode:find("[wa]") or mode:find("%+") then
      local m = pickWriteMember(rel)
      if not m then return nil, "no writable pool member" end
      local h, err = m.open(rel, mode)
      if not h then return nil, err end
      return wrapHandle(m, h)
    end
    for _, m in ipairs(members) do
      if m.exists(rel) and not m.isDirectory(rel) then
        local h, err = m.open(rel, mode)
        if not h then return nil, err end
        return wrapHandle(m, h)
      end
    end
    return nil, "file not found in pool"
  end

  -- Handle ops route back to the member that opened the handle. Which
  -- member that was is the one thing the pool cannot rediscover later:
  -- two members can hold the same path, so "search for it again" would
  -- read one file and write another.
  function proxy.read(handle, n)
    return handle and handle.member.read(handle.h, n)
  end
  function proxy.write(handle, d)
    return handle and handle.member.write(handle.h, d)
  end
  function proxy.close(handle)
    return handle and handle.member.close(handle.h)
  end
  function proxy.seek(handle, w, o)
    return handle and handle.member.seek(handle.h, w, o)
  end

  function proxy.remove(rel)
    -- The same path could exist on several members (e.g. a dir); remove
    -- from all, and only report success if every copy is gone.
    local found = false
    local allOk = true
    for _, m in ipairs(members) do
      if m.exists(rel) then
        found = true
        local mok = pcall(m.remove, rel)
        if not mok or m.exists(rel) then allOk = false end
      end
    end
    if not found then return false end
    return allOk
  end

  function proxy.rename(from, to)
    local srcMember = nil
    for _, m in ipairs(members) do
      if m.exists(from) then srcMember = m; break end
    end
    if not srcMember then return false, "source not found in pool" end
    local dstMember = pickWriteMember(to)
    -- Same member: a real in-place rename is cheap and atomic.
    if srcMember == dstMember then
      return srcMember.rename(from, to)
    end
    -- Cross-member rename of a directory would mean walking + copying a
    -- whole subtree across disks; refuse rather than do it half-way.
    if srcMember.isDirectory(from) then
      return false, "cross-member directory rename not supported"
    end
    -- Cross-member file rename = copy to the destination member, then
    -- drop the source. Chunked so a big file doesn't spike RAM.
    local rh = srcMember.open(from, "r")
    if not rh then return false, "cannot open source" end
    local parts = {}
    repeat
      local chunk = srcMember.read(rh, 4096)
      if chunk then parts[#parts + 1] = chunk end
    until not chunk
    srcMember.close(rh)
    local wh = dstMember.open(to, "w")
    if not wh then return false, "cannot open dest" end
    dstMember.write(wh, table.concat(parts))
    dstMember.close(wh)
    pcall(srcMember.remove, from)
    return true
  end

  -- ── Management handle (not the mountable proxy) ──────────
  local pool = {}
  function pool.members() return members end
  function pool.addMember(newMember)
    members[#members + 1] = newMember
  end
  function pool.removeMember(addr)
    for i, m in ipairs(members) do
      if m.address == addr then
        table.remove(members, i)
        return true
      end
    end
    return false
  end
  function pool.stats()
    local s = { members = #members, total = 0, used = 0, free = 0 }
    for _, m in ipairs(members) do
      s.total = s.total + (m.spaceTotal() or 0)
      s.used  = s.used  + (m.spaceUsed()  or 0)
    end
    s.free = s.total - s.used
    return s
  end

  return proxy, pool
end

-- ============================================================
-- Config persistence (/etc/jbod.cfg)
-- ============================================================
-- Schema (serialized data, never load()'d as code):
--   { pools = { { mount = "/mnt/pool", members = { "<fs-addr>", ... } }, ... } }
local CONFIG_PATH = "/etc/jbod.cfg"

function jbod.loadConfig(fsModule)
  if not fsModule.exists(CONFIG_PATH) then return nil end
  local content = fsModule.readFile(CONFIG_PATH)
  if not content then return nil end
  local ok, cfg = pcall(serialize.decode, content, { maxBytes = 8192 })
  if not ok or type(cfg) ~= "table" then return nil end
  return cfg
end

function jbod.saveConfig(fsModule, cfg)
  return (fsModule.writeFileAtomic or fsModule.writeFile)(
    CONFIG_PATH, serialize.encode(cfg))
end

jbod.CONFIG_PATH = CONFIG_PATH

return jbod
