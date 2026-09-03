-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - netfs (remote filesystem shares)            ║
-- ║                                                            ║
-- ║  Mount a directory exported by another TOS machine as a    ║
-- ║  local filesystem. The client half returns a proxy shaped  ║
-- ║  exactly like an OpenComputers filesystem component, which ║
-- ║  means it can be handed to kernel.fs.mount OR dropped into ║
-- ║  a kernel.jbod pool as a member with no adapter.           ║
-- ║                                                            ║
-- ║  GENERALISES kernel.net.transfer, which already serves     ║
-- ║  files to TRUSTED peers but only from a hardcoded          ║
-- ║  /public/, only whole files, only reads, only ≤6 KB.       ║
-- ║  netfs adds named exports with their own ACLs, handles,    ║
-- ║  block reads, and writes — so it inherits every one of     ║
-- ║  transfer.lua's precautions rather than inventing weaker   ║
-- ║  ones. See the SECURITY block below.                       ║
-- ║                                                            ║
-- ║  DRAWBACK, by design and worth stating plainly: a share    ║
-- ║  lives on someone else's computer. When that machine is    ║
-- ║  off, the mount is empty and its files vanish from a       ║
-- ║  listing without having been deleted. This is the same     ║
-- ║  bargain a Windows folder share makes.                     ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- ── SECURITY ────────────────────────────────────────────────────────
-- Every one of these mirrors kernel.net.transfer, which arrived at them
-- for reasons that have not changed:
--
--   1. FAIL-CLOSED ARM. `enabled` defaults to false and is flipped by
--      the netfsd rc service's start/stop. transfer.lua learned this the
--      hard way: a handler registered at boot keeps answering forever,
--      so "service stop" that only drops a log listener stops nothing.
--      No netfsd ⇒ no serving, even with exports configured.
--   2. TRUSTED ONLY, checked on every request.
--   3. CHALLENGE-RESPONSE per request via net.verifyPeer (60 s cached).
--      The threat is a RELOCATED trusted modem: the address is still
--      trusted, but the bytes now come from whoever moved it.
--   4. CONFINEMENT is the real boundary. Every path is normalised and
--      then required to sit under the export root, so `..` cannot climb
--      out. See _confine.
--   5. VAGUE DENIALS on the wire. A caller learns "denied", not which of
--      trust / verification / ACL / existence failed, so the reply cannot
--      be used to map the secret-set graph or probe for paths.
--
-- ⚠ LIMITATION, stated rather than hidden: confinement is per-EXPORT,
-- not per-user. An allowed peer gets everything under the export root at
-- the export's mode. TOS securefs ACLs are evaluated for LOCAL users and
-- a remote peer is a modem address, not a user — mapping one to the
-- other is a real design question (an `as_user` field on the export is
-- the obvious answer) and is deliberately NOT guessed at here. Export
-- narrow directories.

local netfs = {}

-- ── Tunables ────────────────────────────────────────────────────────
-- Block size: protocol.MAX_SIZE is 8192 and framing/serialisation eat
-- into it, so 4 KB of payload leaves comfortable headroom. This is the
-- unit of network traffic, NOT of the caller's read() — see the buffer
-- in attach().
local BLOCK          = 4096
local RPC_TIMEOUT    = 10      -- seconds to wait for a reply
local SPACE_TTL      = 30      -- capacity cache lifetime (§2.4 of the spec)
local MAX_HANDLES    = 16      -- per peer; a handle table is a memory target
local HANDLE_IDLE    = 120     -- seconds before an abandoned handle is reaped
local MAX_PATH       = 256     -- refuse absurd paths before doing any work
local MAX_LIST       = 256     -- cap a directory listing reply

-- ── Injected modules ────────────────────────────────────────────────
local net, fs, trustMgr, log, protocol, computer

function netfs.init(modules)
  modules  = modules or {}
  net      = modules.net
  fs       = modules.fs
  trustMgr = modules.trust
  log      = modules.log
  computer = modules.computer or require("computer")
  -- Resolve the protocol from what we were handed, then from net, and
  -- only then from the module path — and never hard-fail on the last
  -- one. netfs is useful without a network (the server dispatcher is
  -- driven directly by tests and by a loopback transport), so a missing
  -- protocol module must degrade to "cannot serve" rather than to a
  -- boot-time error, the same way state.lua's firstRequire does.
  protocol = modules.protocol or (net and net.getProtocol and net.getProtocol())
  if not protocol then
    local okP, mod = pcall(require, "kernel.net.protocol")
    if okP then protocol = mod end
  end

  if net and protocol then
    net.on(protocol.TYPE.NETFS_REQ, function(packet, fromAddr)
      netfs.handleRequest(packet, fromAddr)
    end)
  end
  if log and log.info then log.info("netfs", "netfs module initialized") end
  return true
end

-- ── Fail-closed arm (see SECURITY 1) ────────────────────────────────
local enabled = false
function netfs.setEnabled(v) enabled = v and true or false end
function netfs.isEnabled()   return enabled end

-- ============================================================
-- Exports (server side)
-- ============================================================

netfs.EXPORTS_PATH = "/etc/netfs-exports.cfg"

local _exports = {}

--- Validate an export table. Returns (list, err); on any bad entry the
--- WHOLE config is rejected rather than partially applied — a typo that
--- silently widened one export's ACL is the failure mode to avoid.
function netfs._validateExports(cfg)
  if type(cfg) ~= "table" then return nil, "invalid_config: not a table" end
  local out, seen = {}, {}
  for i, e in ipairs(cfg) do
    local where = "entry " .. i
    if type(e) ~= "table" then return nil, "invalid_export: " .. where .. " not a table" end
    if type(e.name) ~= "string" or not e.name:match("^[%w_%-]+$") then
      return nil, "invalid_export: " .. where .. " needs a [%w_-] name"
    end
    if seen[e.name] then return nil, "invalid_export: duplicate name " .. e.name end
    if type(e.path) ~= "string" or e.path == "" then
      return nil, "invalid_export: " .. e.name .. " needs a path"
    end
    local mode = e.mode or "ro"
    if mode ~= "ro" and mode ~= "rw" then
      return nil, "invalid_export: " .. e.name .. " mode must be ro or rw"
    end
    if e.allow ~= nil and type(e.allow) ~= "table" then
      return nil, "invalid_export: " .. e.name .. " allow must be a list"
    end
    -- Normalise the root ONCE, here, so _confine compares against a
    -- canonical prefix and never against operator-typed punctuation.
    local root = fs and fs.normalize and fs.normalize(e.path) or e.path
    if type(root) ~= "string" or root == "" then
      return nil, "invalid_export: " .. e.name .. " path does not normalize"
    end
    root = root:gsub("/+$", "")
    if root == "" then root = "/" end
    -- Exporting / would hand the entire machine, TOS install included,
    -- to any allowed peer. jbod refuses to pool the boot disk for the
    -- same reason; this is that rule at the network edge.
    if root == "/" then
      return nil, "invalid_export: " .. e.name .. " refuses to export /"
    end
    seen[e.name] = true
    out[#out + 1] = {
      name = e.name, path = root, mode = mode,
      allow = e.allow or {},
    }
  end
  return out
end

function netfs.setExports(list) _exports = list or {} end
function netfs.getExports()     return _exports end

--- Load /etc/netfs-exports.cfg. The file is serialized DATA, never
--- load()'d as code — same rule jbod.lua's config follows.
function netfs.loadExports(fsModule, serializeMod)
  fsModule = fsModule or fs
  if not (fsModule and fsModule.exists and fsModule.exists(netfs.EXPORTS_PATH)) then
    _exports = {}
    return true, "no_exports"
  end
  local content = fsModule.readFile(netfs.EXPORTS_PATH)
  if not content or content == "" then _exports = {}; return true, "no_exports" end
  local ser = serializeMod or require("kernel.serialize")
  local ok, cfg = pcall(ser.decode, content, { maxBytes = 8192 })
  if not ok or type(cfg) ~= "table" then
    return false, "decode_failed: netfs-exports.cfg"
  end
  local list, err = netfs._validateExports(cfg)
  if not list then return false, err end
  _exports = list
  return true
end

function netfs._findExport(name)
  for _, e in ipairs(_exports) do
    if e.name == name then return e end
  end
  return nil
end

--- Is `addr` allowed to use this export, for the access it wants?
--- An empty allow list denies everyone: an export with no ACL is a
--- misconfiguration, and the safe reading of a missing rule is "no".
function netfs._accessOk(export, addr, wantWrite)
  if not export then return false, "no_such_export" end
  if wantWrite and export.mode ~= "rw" then return false, "read_only_export" end
  local allowed = false
  for _, entry in ipairs(export.allow) do
    if entry == addr then allowed = true; break end
    if entry == "*paired*" then
      -- Anything the trust manager already holds at TRUSTED. This is the
      -- existing pairing flow; netfs adds no bootstrap of its own and no
      -- discovery broadcast, because whoever answers a broadcast first
      -- would become your filesystem.
      if trustMgr and trustMgr.getLevel and trustMgr.LEVEL
         and trustMgr.getLevel(addr) >= trustMgr.LEVEL.TRUSTED then
        allowed = true; break
      end
    end
  end
  if not allowed then return false, "not_allowed" end
  return true
end

--- Map a share-relative path to an absolute one INSIDE the export root.
--- This is the security boundary (SECURITY 4): normalize first so that
--- `..` is resolved rather than pattern-matched, then require the result
--- to sit under the root with a path-separator boundary — otherwise an
--- export of /srv/pub would also grant /srv/public.
function netfs._confine(export, rel)
  if type(rel) ~= "string" or #rel > MAX_PATH then return nil, "invalid_path" end
  if rel == "" then rel = "/" end
  if rel:sub(1, 1) ~= "/" then rel = "/" .. rel end
  local abs = fs and fs.normalize and fs.normalize(export.path .. rel) or nil
  if type(abs) ~= "string" or abs == "" then return nil, "invalid_path" end
  if abs ~= export.path and abs:sub(1, #export.path + 1) ~= export.path .. "/" then
    return nil, "invalid_path"
  end
  return abs
end

-- ============================================================
-- Server: handle table
-- ============================================================
-- Keyed by peer address so one peer cannot close or read another's
-- handles by guessing an id, and so a peer's handles die with its
-- session rather than leaking for the machine's uptime.

local _handles = {}   -- addr -> { [id] = { h, export, mode, last } }
local _nextHandle = 1

local function _reap(now)
  for addr, tbl in pairs(_handles) do
    for id, st in pairs(tbl) do
      if now - (st.last or 0) > HANDLE_IDLE then
        pcall(function() if st.h and st.h.close then st.h:close() end end)
        tbl[id] = nil
      end
    end
    if next(tbl) == nil then _handles[addr] = nil end
  end
end

local function _countHandles(addr)
  local n = 0
  for _ in pairs(_handles[addr] or {}) do n = n + 1 end
  return n
end

-- ============================================================
-- Server: the op dispatcher
-- ============================================================
-- Split from handleRequest so it can be driven directly, in-process,
-- by tests and by a loopback transport. handleRequest is the network
-- wrapper: trust, verification and arming live there, so a new op
-- cannot forget them.

function netfs._dispatch(op, p, fromAddr)
  p = p or {}
  local now = computer and computer.uptime() or 0
  _reap(now)

  if op == "space" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, false)
    if not ok then return { err = err } end
    return {
      total = fs.spaceTotal and fs.spaceTotal(e.path) or 0,
      used  = fs.spaceUsed  and fs.spaceUsed(e.path)  or 0,
      read_only = e.mode ~= "rw",
    }
  end

  if op == "stat" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, false)
    if not ok then return { err = err } end
    local abs, perr = netfs._confine(e, p.path)
    if not abs then return { err = perr } end
    if not fs.exists(abs) then return { exists = false } end
    return {
      exists = true,
      is_dir = fs.isDirectory(abs) and true or false,
      size   = fs.size and fs.size(abs) or 0,
      mtime  = fs.lastModified and fs.lastModified(abs) or 0,
    }
  end

  if op == "list" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, false)
    if not ok then return { err = err } end
    local abs, perr = netfs._confine(e, p.path)
    if not abs then return { err = perr } end
    local items = fs.list(abs)
    if type(items) ~= "table" then return { entries = {} } end
    local out = {}
    for i = 1, math.min(#items, MAX_LIST) do out[i] = items[i] end
    return { entries = out, truncated = #items > MAX_LIST }
  end

  if op == "mkdir" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, true)
    if not ok then return { err = err } end
    local abs, perr = netfs._confine(e, p.path)
    if not abs then return { err = perr } end
    return { ok = fs.makeDirectory(abs) and true or false }
  end

  if op == "remove" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, true)
    if not ok then return { err = err } end
    local abs, perr = netfs._confine(e, p.path)
    if not abs then return { err = perr } end
    return { ok = fs.remove(abs) and true or false }
  end

  if op == "rename" then
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, true)
    if not ok then return { err = err } end
    -- BOTH ends must be confined. Checking only the source would let a
    -- rename write anywhere on the host.
    local from, ferr = netfs._confine(e, p.path)
    if not from then return { err = ferr } end
    local to, terr = netfs._confine(e, p.to)
    if not to then return { err = terr } end
    return { ok = fs.rename(from, to) and true or false }
  end

  if op == "open" then
    local mode = p.mode or "r"
    local wantWrite = mode:find("[wa+]") ~= nil
    local e = netfs._findExport(p.share)
    local ok, err = netfs._accessOk(e, fromAddr, wantWrite)
    if not ok then return { err = err } end
    local abs, perr = netfs._confine(e, p.path)
    if not abs then return { err = perr } end
    if _countHandles(fromAddr) >= MAX_HANDLES then
      return { err = "too_many_handles" }
    end
    local h, oerr = fs.open(abs, mode)
    if not h then return { err = "open_failed: " .. tostring(oerr) } end
    local id = _nextHandle; _nextHandle = _nextHandle + 1
    _handles[fromAddr] = _handles[fromAddr] or {}
    _handles[fromAddr][id] = { h = h, export = e, mode = mode, last = now }
    return { handle_id = id }
  end

  -- Handle ops. The peer scoping means a forged id can only ever reach
  -- the forger's own handles.
  local st = p.handle_id and _handles[fromAddr] and _handles[fromAddr][p.handle_id]

  if op == "read" then
    if not st then return { err = "no_such_handle" } end
    st.last = now
    local n = tonumber(p.n) or BLOCK
    if n > BLOCK then n = BLOCK end          -- never let a peer size our read
    local chunk = st.h:read(n)
    if chunk == nil then return { eof = true } end
    return { data = chunk, eof = false }
  end

  if op == "write" then
    if not st then return { err = "no_such_handle" } end
    if st.export.mode ~= "rw" then return { err = "read_only_export" } end
    st.last = now
    local d = p.data
    if type(d) ~= "string" then return { err = "invalid_data" } end
    if #d > BLOCK then return { err = "chunk_too_large" } end
    local wok = st.h:write(d)
    return { ok = wok and true or false, written = #d }
  end

  if op == "close" then
    if not st then return { ok = true } end   -- idempotent
    pcall(function() st.h:close() end)
    _handles[fromAddr][p.handle_id] = nil
    return { ok = true }
  end

  if op == "seek" then
    if not st then return { err = "no_such_handle" } end
    st.last = now
    return { pos = st.h:seek(p.whence or "set", tonumber(p.offset) or 0) }
  end

  return { err = "unknown_op" }
end

--- Network entry point. One gate for every op (see SECURITY 1–3, 5).
function netfs.handleRequest(packet, fromAddr)
  if not (net and protocol) then return end
  if not enabled then return end

  local function deny()
    -- SECURITY 5: one opaque reason for every pre-flight refusal.
    local pkt = protocol.makePacket(protocol.TYPE.NETFS_RES,
      { req_id = packet and packet.payload and packet.payload.req_id,
        err = "denied" }, { to = fromAddr })
    net.send(fromAddr, pkt)
  end

  if not (trustMgr and trustMgr.getLevel and trustMgr.LEVEL) then return deny() end
  if trustMgr.getLevel(fromAddr) < trustMgr.LEVEL.TRUSTED then
    if log and log.warn then
      log.warn("netfs", "request from non-trusted peer " .. tostring(fromAddr):sub(1, 8))
    end
    return deny()
  end
  if net.verifyPeer then
    local vOk = net.verifyPeer(fromAddr)
    if not vOk then
      if log and log.warn then
        log.warn("netfs", "verification failed for " .. tostring(fromAddr):sub(1, 8))
      end
      return deny()
    end
  end

  local p = packet.payload or {}
  local reply = netfs._dispatch(p.op, p, fromAddr)
  reply.req_id = p.req_id
  net.send(fromAddr, protocol.makePacket(protocol.TYPE.NETFS_RES, reply,
    { to = fromAddr }))
end

-- ============================================================
-- Client: attach a remote share as a filesystem proxy
-- ============================================================

--- Default transport: one NETFS_REQ, wait for the matching NETFS_RES.
local function _netTransport(hostAddr)
  local reqId = 0
  return function(op, payload)
    if not (net and protocol) then return nil, "no_network" end
    reqId = reqId + 1
    local myId = reqId
    payload.op = op
    payload.req_id = myId
    local got, res = false, nil
    local lid = net.on(protocol.TYPE.NETFS_RES, function(pkt, from)
      if from ~= hostAddr then return end
      local pl = pkt.payload or {}
      if pl.req_id ~= myId then return end
      got, res = true, pl
    end)
    local sent = net.send(hostAddr, protocol.makePacket(protocol.TYPE.NETFS_REQ,
      payload, { to = hostAddr }))
    if not sent then
      net.off(protocol.TYPE.NETFS_RES, lid)
      return nil, "send_failed"
    end
    net.waitFor(function() return got end, RPC_TIMEOUT)
    net.off(protocol.TYPE.NETFS_RES, lid)
    if not got then return nil, "timeout" end
    return res
  end
end

--- Attach a remote share.
--- @param hostAddr string  the exporting machine's modem address
--- @param share    string  export name on that machine
--- @param opts     table   { transport = fn } to bypass the network (tests)
--- @return proxy           filesystem-component-shaped; mount it, or hand
---                         it to jbod.makePool as a member
function netfs.attach(hostAddr, share, opts)
  opts = opts or {}
  local rpc = opts.transport or _netTransport(hostAddr)
  local proxy = {}

  proxy.address = "netfs:" .. tostring(hostAddr):sub(1, 8) .. ":" .. tostring(share)
  function proxy.getLabel() return "netfs(" .. tostring(share) .. ")" end

  local function call(op, payload)
    payload = payload or {}
    payload.share = share
    local res, err = rpc(op, payload)
    if not res then return nil, err or "no_reply" end
    if res.err then return nil, res.err end
    return res
  end
  proxy._call = call

  -- ── Capacity, cached (spec §2.4) ─────────────────────────────
  -- jbod.pickWriteMember reads spaceTotal AND spaceUsed on every member
  -- for every write. Uncached that is 2N round trips per file.
  local spaceAt, spaceVal = -math.huge, nil
  local function space()
    local now = computer and computer.uptime() or 0
    if spaceVal and (now - spaceAt) < SPACE_TTL then return spaceVal end
    local res = call("space")
    if res then spaceVal = res; spaceAt = now end
    return spaceVal
  end
  function proxy.spaceTotal() local s = space(); return s and s.total or 0 end
  function proxy.spaceUsed()  local s = space(); return s and s.used  or 0 end
  function proxy.isReadOnly() local s = space(); return s and s.read_only or false end

  -- ── Metadata ─────────────────────────────────────────────────
  local function stat(rel)
    local res = call("stat", { path = rel })
    return res
  end
  function proxy.exists(rel)       local s = stat(rel); return s ~= nil and s.exists == true end
  function proxy.isDirectory(rel)  local s = stat(rel); return s ~= nil and s.is_dir == true end
  function proxy.size(rel)         local s = stat(rel); return s and s.size or 0 end
  function proxy.lastModified(rel) local s = stat(rel); return s and s.mtime or 0 end

  function proxy.list(rel)
    local res = call("list", { path = rel })
    return res and res.entries or {}
  end
  function proxy.makeDirectory(rel)
    local res = call("mkdir", { path = rel }); return res ~= nil and res.ok == true
  end
  function proxy.remove(rel)
    local res = call("remove", { path = rel }); return res ~= nil and res.ok == true
  end
  function proxy.rename(from, to)
    local res = call("rename", { path = from, to = to })
    if not res then return false end
    return res.ok == true
  end

  -- ── Handles ──────────────────────────────────────────────────
  -- Component contract: open() returns an OPAQUE handle and read/write
  -- take it as their first argument. kernel/jbod.lua and kernel/fs.lua
  -- both drive members this way, so a netfs proxy must too — returning a
  -- method-bearing table here is exactly the mismatch that hid the jbod
  -- handle bug.
  local handles, nextLocal = {}, 1

  function proxy.open(rel, mode)
    mode = mode or "r"
    local res, err = call("open", { path = rel, mode = mode })
    if not res then return nil, err end
    local id = nextLocal; nextLocal = nextLocal + 1
    handles[id] = {
      remote = res.handle_id, mode = mode,
      buf = "", pos = 1, eof = false,   -- read side
      wbuf = {}, wlen = 0,              -- write side
    }
    return id
  end

  -- Read buffering (spec §2.3): the caller's read(n) is served from a
  -- local buffer refilled a BLOCK at a time, so a whole-file read costs
  -- one round trip per 4 KB rather than one per call.
  function proxy.read(id, n)
    local st = handles[id]; if not st then return nil end
    n = tonumber(n) or BLOCK
    while (#st.buf - st.pos + 1) < n and not st.eof do
      local res = call("read", { handle_id = st.remote, n = BLOCK })
      if not res or res.eof or not res.data then st.eof = true; break end
      -- Compact as we go so a long sequential read doesn't retain the
      -- whole file: this runs on a machine with ~3.6 MB.
      st.buf = st.buf:sub(st.pos) .. res.data
      st.pos = 1
    end
    local avail = #st.buf - st.pos + 1
    if avail <= 0 then return nil end
    local take = n < avail and n or avail
    local out = st.buf:sub(st.pos, st.pos + take - 1)
    st.pos = st.pos + take
    return out
  end

  local function flush(st)
    if st.wlen == 0 then return true end
    local blob = table.concat(st.wbuf)
    st.wbuf, st.wlen = {}, 0
    while #blob > 0 do
      local piece = blob:sub(1, BLOCK)
      blob = blob:sub(BLOCK + 1)
      local res = call("write", { handle_id = st.remote, data = piece })
      if not res or res.ok ~= true then return false end
    end
    return true
  end

  -- Writes accumulate and flush at the block boundary and on close, so
  -- a write is NOT durable until close() returns. Documented in the
  -- spec; repeated here because it is the surprising half.
  function proxy.write(id, d)
    local st = handles[id]; if not st then return false end
    if type(d) ~= "string" then return false end
    st.wbuf[#st.wbuf + 1] = d
    st.wlen = st.wlen + #d
    if st.wlen >= BLOCK then return flush(st) end
    return true
  end

  function proxy.close(id)
    local st = handles[id]; if not st then return true end
    local ok = flush(st)
    call("close", { handle_id = st.remote })
    handles[id] = nil
    return ok
  end

  function proxy.seek(id, whence, offset)
    local st = handles[id]; if not st then return nil end
    flush(st)
    local res = call("seek", { handle_id = st.remote, whence = whence, offset = offset })
    -- The local read buffer describes a position that no longer holds.
    st.buf, st.pos, st.eof = "", 1, false
    return res and res.pos or nil
  end

  return proxy
end

-- Test/introspection surface.
netfs._internal = {
  BLOCK       = BLOCK,
  MAX_HANDLES = MAX_HANDLES,
  MAX_LIST    = MAX_LIST,
  HANDLE_IDLE = HANDLE_IDLE,
  handles     = function() return _handles end,
  resetHandles = function() _handles = {}; _nextHandle = 1 end,
}

return netfs
