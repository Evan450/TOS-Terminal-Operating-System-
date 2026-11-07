-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster.store_client — Master → Storage Node(s)              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- The Master's half of the Public storage tier. Speaks §4.5's STORE_PUT
-- / STORE_LEASE_EXTEND / STORE_RELEASE to whichever node answers on the
-- write port, so `jobs.lua` can hand out pointers instead of payloads —
-- design principle 5: "Data movement prefers pointers over payloads. The
-- 6 KB packet ceiling is never routed around with heroic chunking when a
-- scratch tier exists."
--
-- ONE NODE OR A POOL. `storage_node_address` names one Storage Node, as
-- before. `storage_pool` (cluster-master.cfg) names several, and then the
-- Public tier is the distributed back end of storage-spec-draft.md §5,
-- built 2026-11-07 on the answers the operator approved (§10):
--
--   * where a key lives is cluster.placement's pure function of the key,
--     so no member is ever asked "do you have it?" (answer 1: no
--     coordinator). Every member is an ordinary Storage Node running
--     cluster-storaged; none of them knows it is in a pool.
--   * job-<id>/ goes to two members, and BOTH must take it. One replica
--     is less safe than the inline payload it would replace, so a short
--     write is released and the caller stays inline.
--   * shared/ goes to every member and stands at a majority (answer 2).
--     Each write is versioned (counter, this Master's address), recorded
--     in the Master's state, and `repair()` brings every member to it.
--   * leases belong to the member that issued them (answer 4): a pool
--     write returns one lease per member, and each is released there.
--   * `list()` asks every member, and names the ones that did not answer
--     instead of returning a short list as if it were whole (answer 1's
--     cost, paid honestly).
--
-- EVERY OPERATION IS OPTIONAL. A cluster with no Storage Node configured
-- is the normal case today, and it must keep working exactly as it did:
-- callers get `nil, "no_storage_node"` and fall back to inline. Nothing
-- here may turn a missing scratch tier into a failed job.
--
-- Error strings follow error-conventions.md §4.

local computer = require("computer")

local store_client = {}

local RPC_TIMEOUT = 10       -- seconds to wait for STORE_PUT_ACK
local WRITE_PORT  = 2101     -- §2.1: writes are TOS protocol, TRUSTED
local LIST_LIMIT  = 128      -- rows per member per STORE_LIST
--! repair() runs on the Master's own timer, and a wait there holds up the
--! scheduler, so a member that does not answer has to cost seconds, not
--! RPC_TIMEOUT. It is retried on the next sweep anyway.
local REPAIR_TIMEOUT = 3

local net, protocol, serialize, stateRef, log, placement
local _pool                  -- operator-declared member addresses, or nil
local _sharedMem = {}        -- shared/ records when the state has no store

local function firstRequire(...)
  for i = 1, select("#", ...) do
    local ok, mod = pcall(require, (select(i, ...)))
    if ok and mod then return mod end
  end
end

function store_client.init(deps)
  deps      = deps or {}
  net       = deps.net or firstRequire("kernel.net")
  stateRef  = deps.state or firstRequire("cluster.state")
  serialize = deps.serialize or firstRequire("kernel.serialize")
  log       = deps.log or firstRequire("kernel.log", "log")
    or { info = function() end, warn = function() end, error = function() end }
  protocol  = deps.protocol or (net and net.getProtocol and net.getProtocol())
    or firstRequire("kernel.net.protocol")
  placement = deps.placement or firstRequire("cluster.placement")
  _pool     = type(deps.pool) == "table" and deps.pool or nil
  _sharedMem = {}
  if _pool and #_pool > 0 and not placement then
    log.error("cluster.store", "storage_pool is set but cluster.placement is missing; "
      .. "using storage_node_address only")
  end
  return true
end

--- True when the Public tier is a pool rather than one node.
function store_client.isPool()
  return _pool ~= nil and #_pool > 0 and placement ~= nil
end

--- Every member, sorted (a pool), or the one node, or nothing.
function store_client.members()
  if store_client.isPool() then return placement.members(_pool) end
  local sn = stateRef and stateRef._data and stateRef._data.storage_node
  if sn and sn.address then return { sn.address } end
  return {}
end

--- Address of the configured Storage Node (a pool's first member), or nil.
function store_client.address()
  return store_client.members()[1]
end

function store_client.available()
  return store_client.address() ~= nil and net ~= nil and protocol ~= nil
end

-- One request, one reply, keyed by the key we asked about. The Storage
-- Node answers STORE_PUT_ACK on success and STORE_ERROR on refusal, so
-- both are listened for and whichever names our key wins.
local function rpc(addr, kind, payload, key, timeout)
  if not addr then return nil, "no_storage_node" end
  if not (net and protocol) then return nil, "no_network" end

  local done, ack, errReason = false, nil, nil
  local ids = {}
  local function listen(t, fn)
    ids[#ids + 1] = { t = t, id = net.on(t, fn) }
  end
  listen(protocol.TYPE.STORE_PUT_ACK, function(pkt, from)
    if from ~= addr then return end
    local p = pkt.payload or {}
    if p.key ~= key then return end
    done, ack = true, p
  end)
  listen(protocol.TYPE.STORE_ERROR, function(pkt, from)
    if from ~= addr then return end
    local p = pkt.payload or {}
    if p.key ~= nil and p.key ~= key then return end
    done, errReason = true, p.reason or "store_error"
  end)

  local sent = net.send(addr, protocol.makePacket(kind, payload, { to = addr }),
    WRITE_PORT)
  if sent == false then
    for _, e in ipairs(ids) do pcall(net.off, e.t, e.id) end
    return nil, "send_failed"
  end

  if net.waitFor then net.waitFor(function() return done end, timeout or RPC_TIMEOUT) end
  for _, e in ipairs(ids) do pcall(net.off, e.t, e.id) end

  if errReason then return nil, errReason end
  if not done then return nil, "timeout" end
  return ack
end

-- STORE_LIST to one member. Its reply has no key, so it is matched on the
-- sender and the prefix asked for.
local function listAt(addr, prefix, limit, timeout)
  if not (net and protocol) then return nil, "no_network" end
  local done, res = false, nil
  local id = net.on(protocol.TYPE.STORE_LIST_RES, function(pkt, from)
    if from ~= addr then return end
    local p = pkt.payload or {}
    if (p.prefix or "") ~= prefix then return end
    done, res = true, p
  end)
  local sent = net.send(addr, protocol.makePacket(protocol.TYPE.STORE_LIST,
    { prefix = prefix, limit = limit or LIST_LIMIT }, { to = addr }), WRITE_PORT)
  if sent ~= false and net.waitFor then
    net.waitFor(function() return done end, timeout or RPC_TIMEOUT)
  end
  pcall(net.off, protocol.TYPE.STORE_LIST_RES, id)
  if sent == false then return nil, "send_failed" end
  if not done then return nil, "timeout" end
  return res.keys or {}, res.truncated
end

-- ============================================================
-- Versions, for a pool's shared/ keys
-- ============================================================

--- 1 if version a is newer than b, -1 if older, 0 if the same. The same
--- rule as cluster.store.compareVersions on the node, which is the one
--- that decides; this copy only decides what is worth sending.
local function compareVersions(a, b)
  if not b then return a and 1 or 0 end
  if not a then return -1 end
  local an, bn = tonumber(a.n) or 0, tonumber(b.n) or 0
  if an ~= bn then return an > bn and 1 or -1 end
  if a.writer == b.writer then return 0 end
  return tostring(a.writer) > tostring(b.writer) and 1 or -1
end
store_client.compareVersions = compareVersions

local function sharedGet(key)
  if stateRef and stateRef.sharedRecord then return stateRef.sharedRecord(key) end
  return _sharedMem[key]
end

local function sharedSet(key, rec)
  if stateRef and stateRef.setSharedRecord then return stateRef.setSharedRecord(key, rec) end
  _sharedMem[key] = rec
end

local function sharedAll()
  if stateRef and stateRef.sharedRecords then return stateRef.sharedRecords() end
  return _sharedMem
end

local function selfAddr()
  local a = net and net.getAddress and net.getAddress()
  return type(a) == "string" and a ~= "" and a or "master"
end

-- "stale_version: have 7 from abcd1234" -> 7
local function staleHave(err)
  return tonumber(tostring(err):match("^stale_version: have (%d+)"))
end

-- ============================================================
-- Operations
-- ============================================================

local function plan(key)
  local members = store_client.members()
  if #members == 0 then return nil, "no_storage_node" end
  if placement then return placement.targets(key, members) end
  return { addrs = { members[1] }, need = 1, ns = "other" }
end

local function short(addr) return tostring(addr):sub(1, 8) end

--- STORE_PUT. `value` is any serializable Lua value; it is encoded here
--- so callers deal in tables, not blobs.
--- @return { key, lease_id, expires_at, size_bytes, members, leases } | nil, err
---   `members` lists the members that took the write and `leases` maps
---   each to the lease IT issued; release with releaseAll(key, leases).
function store_client.put(key, value, opts)
  opts = opts or {}
  if not store_client.available() then return nil, "no_storage_node" end
  local p, perr = plan(key)
  if not p then return nil, perr end
  local blob = (type(value) == "string") and value or serialize.encode(value)
  local payload = {
    key = key, data = blob,
    ttl = opts.ttl or 0,
    overwrite = opts.overwrite ~= false,
  }

  local rec
  if p.ns == "shared" then
    local prev = sharedGet(key)
    rec = { n = ((prev and tonumber(prev.n)) or 0) + 1, writer = selfAddr(),
            blob = blob, ttl = payload.ttl, leases = {} }
    payload.version = { n = rec.n, writer = rec.writer }
  end

  local function sendAll()
    local acks, okAddrs, leases, errs, have = {}, {}, {}, {}, 0
    for _, addr in ipairs(p.addrs) do
      local ack, err = rpc(addr, protocol.TYPE.STORE_PUT, payload, key)
      if ack then
        okAddrs[#okAddrs + 1] = addr; leases[addr] = ack.lease_id; acks[#acks + 1] = ack
      else
        errs[#errs + 1] = { addr = addr, err = err }
        have = math.max(have, staleHave(err) or 0)
      end
    end
    return acks, okAddrs, leases, errs, have
  end

  local acks, okAddrs, leases, errs, have = sendAll()
  --! A member holding a NEWER shared/ version than this Master's record
  --! means the record was lost (a restored or fresh Master state). Every
  --! write from the old counter would be refused forever, so step past
  --! what the members hold and send once more.
  if rec and #okAddrs < p.need and have >= rec.n then
    rec.n = have + 1
    payload.version = { n = rec.n, writer = rec.writer }
    acks, okAddrs, leases, errs = sendAll()
  end
  if rec then
    -- Recorded whether or not it reached a majority: this is the value
    -- the Master means, and repair() keeps offering it to every member.
    rec.leases = leases
    sharedSet(key, rec)
  end

  if #okAddrs < p.need then
    if not rec then
      -- A job- key short of its replicas is released where it landed: the
      -- caller keeps the payload inline, which is safer than one copy.
      for addr, lease in pairs(leases) do
        pcall(rpc, addr, protocol.TYPE.STORE_RELEASE, { key = key, lease_id = lease }, key)
      end
    end
    if #p.addrs == 1 then return nil, errs[1] and errs[1].err or "store_error" end
    local first = errs[1] and (short(errs[1].addr) .. ": " .. tostring(errs[1].err)) or "?"
    return nil, string.format("%s: %d of %d (%s)",
      rec and "no_quorum" or "replicas_short", #okAddrs, p.need, first)
  end

  local out = {}
  for k, v in pairs(acks[1]) do out[k] = v end
  out.members, out.leases, out.replicas = okAddrs, leases, #okAddrs
  if #errs > 0 then
    out.missed = {}
    for i, e in ipairs(errs) do out.missed[i] = e.addr end
    log.warn("cluster.store", string.format("%s: %d of %d members took it; %s will catch up",
      key, #okAddrs, #p.addrs, rec and "the rest" or "none"))
  end
  return out
end

--- STORE_RELEASE. Deleting a key needs the lease that created it, which
--- is what stops a stale release from removing someone else's rewrite.
--- `addr` is the member that issued the lease (default: the one node).
function store_client.release(key, lease_id, addr)
  if not store_client.available() then return nil, "no_storage_node" end
  return rpc(addr or store_client.address(), protocol.TYPE.STORE_RELEASE,
    { key = key, lease_id = lease_id }, key)
end

--- Release a pool write on every member that took it: `leases` is the
--- { [addr] = lease_id } a pool put() returned. Best-effort: a member that
--- does not answer keeps the key until its TTL ends it.
--- @return number released, { {addr, err}... } failures
function store_client.releaseAll(key, leases)
  local n, fails = 0, {}
  if not store_client.available() then return 0, { { err = "no_storage_node" } } end
  for addr, lease in pairs(leases or {}) do
    local ok, err = rpc(addr, protocol.TYPE.STORE_RELEASE, { key = key, lease_id = lease }, key)
    if ok then n = n + 1 else fails[#fails + 1] = { addr = addr, err = err } end
  end
  return n, fails
end

function store_client.extend(key, lease_id, seconds, addr)
  if not store_client.available() then return nil, "no_storage_node" end
  return rpc(addr or store_client.address(), protocol.TYPE.STORE_LEASE_EXTEND,
    { key = key, lease_id = lease_id, extend_by = seconds }, key)
end

--- STORE_LIST on every member, merged. With no coordinator nobody holds
--- the whole list, so this is a scatter-gather (storage-spec §10, answer
--- 1), and a member that does not answer is NAMED: a short list returned
--- as if it were whole is the §0 mistake in another form.
--- @return { keys = rows, truncated = bool, missing = {addr...}, incomplete = bool } | nil, err
function store_client.list(prefix, limit)
  if not store_client.available() then return nil, "no_storage_node" end
  prefix = prefix or ""
  local byKey, missing, truncated = {}, {}, false
  for _, addr in ipairs(store_client.members()) do
    local rows, more = listAt(addr, prefix, limit)
    if not rows then
      missing[#missing + 1] = addr
    else
      truncated = truncated or more == true
      for _, r in ipairs(rows) do
        local seen = byKey[r.key]
        if not seen then
          byKey[r.key] = { key = r.key, size = r.size, expires_at = r.expires_at,
                           version = r.version, holders = { addr } }
        else
          seen.holders[#seen.holders + 1] = addr
          if compareVersions(r.version, seen.version) > 0 then
            seen.version, seen.size, seen.expires_at = r.version, r.size, r.expires_at
          end
        end
      end
    end
  end
  local keys = {}
  for _, r in pairs(byKey) do keys[#keys + 1] = r end
  table.sort(keys, function(a, b) return a.key < b.key end)
  return { keys = keys, truncated = truncated, missing = missing, incomplete = #missing > 0 }
end

--- Bring every reachable member up to this Master's shared/ records
--- (storage-spec §10, answer 2: "the rest catch up in the background").
--- Each member is asked what it holds and sent only what it lacks or holds
--- older; a member holding NEWER than the record teaches the counter, so
--- this Master's next write lands above it. Run on an interval by clusterd.
--- @return { repaired = n, failed = n, unreachable = {addr...}, members = n }
function store_client.repair()
  local out = { repaired = 0, failed = 0, unreachable = {}, members = 0 }
  if not store_client.available() then return out end
  local records = sharedAll()
  if next(records) == nil then return out end
  for _, addr in ipairs(store_client.members()) do
    out.members = out.members + 1
    local rows = listAt(addr, "shared/", LIST_LIMIT, REPAIR_TIMEOUT)
    if not rows then
      out.unreachable[#out.unreachable + 1] = addr
    else
      local has = {}
      for _, r in ipairs(rows) do has[r.key] = r.version or false end
      for key, rec in pairs(records) do
        local mine = { n = rec.n, writer = rec.writer }
        local theirs = has[key] or nil
        local cmp = compareVersions(mine, theirs)
        if cmp > 0 then
          local ack = rpc(addr, protocol.TYPE.STORE_PUT, {
            key = key, data = rec.blob, ttl = rec.ttl or 0, overwrite = true, version = mine,
          }, key, REPAIR_TIMEOUT)
          if ack then
            out.repaired = out.repaired + 1
            rec.leases = rec.leases or {}
            rec.leases[addr] = ack.lease_id
            sharedSet(key, rec)
          else
            out.failed = out.failed + 1
          end
        elseif cmp < 0 and theirs and (tonumber(theirs.n) or 0) > (tonumber(rec.n) or 0) then
          rec.n = tonumber(theirs.n)
          sharedSet(key, rec)
        end
      end
    end
  end
  if out.repaired > 0 or out.failed > 0 then
    log.info("cluster.store", string.format("repair: %d sent, %d failed, %d member(s) unreachable",
      out.repaired, out.failed, #out.unreachable))
  end
  return out
end

--- Remove a shared/ key from the pool, and stop repairing it.
function store_client.dropShared(key)
  local rec = sharedGet(key)
  if not rec then return 0 end
  local n = store_client.releaseAll(key, rec.leases or {})
  sharedSet(key, nil)
  return n
end

-- ============================================================
-- Key naming (§4.6)
-- ============================================================
-- The convention is the spec's, not ours: assignment task lists and
-- collected results live under job-<id>/ rather than domain-<id>/,
-- "so that if a Manager dies mid-assignment the task list survives and
-- Master can redistribute to a replacement Manager without copying."

function store_client.tasksKey(job_id, split_index)
  return string.format("job-%d/tasks/assignment-%d", job_id, split_index)
end

function store_client.inputsKey(job_id, split_index)
  return string.format("job-%d/inputs/assignment-%d", job_id, split_index)
end

function store_client.resultsPrefix(job_id)
  return string.format("public://job-%d/results/", job_id)
end

store_client._internal = {
  WRITE_PORT  = WRITE_PORT,
  RPC_TIMEOUT = RPC_TIMEOUT,
  REPAIR_TIMEOUT = REPAIR_TIMEOUT,
  rpc         = function(...) return rpc(...) end,
  listAt      = function(...) return listAt(...) end,
}

return store_client
