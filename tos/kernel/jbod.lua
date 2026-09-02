local serialize = require("kernel.serialize")
local jbod = {}

local function hashPath(p)
  local h = 0x811C9DC5
  for i = 1, #p do
    h = (h ~ p:byte(i)) & 0xFFFFFFFF
    h = (h * 0x01000193) & 0xFFFFFFFF
  end
  return h
end

function jbod.makePool(members)
  local proxy = {}

  proxy.address = members[1] and members[1].address or "jbod"

  function proxy.getLabel()
    return "JBOD(" .. tostring(#members) .. ")"
  end

  function proxy.isReadOnly()
    for _, m in ipairs(members) do
      if m.isReadOnly() then return true end
    end
    return false
  end

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

    local latest = 0
    for _, m in ipairs(members) do
      if m.exists(rel) then
        local ts = m.lastModified(rel) or 0
        if ts > latest then latest = ts end
      end
    end
    return latest
  end

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

    if srcMember == dstMember then
      return srcMember.rename(from, to)
    end

    if srcMember.isDirectory(from) then
      return false, "cross-member directory rename not supported"
    end

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
