-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster.placement — which pool members hold a Public key     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- storage-spec-draft.md §5, with the answers the operator approved on
-- 2026-11-07 (§10). Placement is a PURE FUNCTION of the key and the
-- member list: nothing is asked of the network to decide it, so a member
-- that is rebooting can never steer a write somewhere else. That is the
-- whole point (§0): "I could not reach it" must never be read as "it does
-- not have it", and a placement that never asks cannot make that mistake.
--
--   job-<id>/...     the top TWO members by rendezvous hash. Both must
--                    take the write, or the caller keeps the payload
--                    inline (see store_client: a lone replica is less safe
--                    than the inline copy it would replace).
--   shared/...       every member; the write stands once a MAJORITY have
--                    it, and the rest catch up from the Master's repair
--                    sweep. Each write carries a version (counter, writer).
--   domain-<id>/...  the member the operator names as that domain's owner
--                    (§5: "lives on the Manager owning that domain"), or
--                    the top member by hash when no owner is a member.
--   anything else    the top member by hash.
--
-- No coordinator (answer 1): any machine with the same member list
-- computes the same answer, so none has to be asked.

local placement = {}

-- FNV-1a over the bytes, then murmur3's 32-bit finaliser. Not a security
-- hash: it has to spread keys evenly and give every machine the same
-- number. FNV alone mixes the last bytes weakly, and the member string is
-- exactly what sits at the end of each hashed pair, so the finaliser is
-- what makes two members' scores for one key independent.
function placement.hash(s)
  local h = 0x811C9DC5
  for i = 1, #s do
    h = ((h ~ s:byte(i)) * 0x01000193) & 0xFFFFFFFF
  end
  h = h ~ (h >> 16)
  h = (h * 0x85EBCA6B) & 0xFFFFFFFF
  h = h ~ (h >> 13)
  h = (h * 0xC2B2AE35) & 0xFFFFFFFF
  h = h ~ (h >> 16)
  return h
end

--- The namespace of a key and its numeric scope, by the same rule as
--- cluster.protocol.parseKey (§4.6). Kept local so the Master needs no
--- Manager package to place a key; test_storage_pool.lua checks the two
--- agree on every key it places.
function placement.namespace(key)
  if type(key) ~= "string" then return nil end
  local id = key:match("^job%-(%d+)/.")
  if id then return "job", tonumber(id) end
  id = key:match("^domain%-(%d+)/.")
  if id then return "domain", tonumber(id) end
  if key:match("^shared/.") then return "shared" end
  return "other"
end

--- The member list, de-duplicated and sorted, so the same set of
--- addresses gives the same answer whatever order the config listed them.
function placement.members(list)
  local seen, out = {}, {}
  for _, a in ipairs(list or {}) do
    if type(a) == "string" and a ~= "" and not seen[a] then
      seen[a] = true; out[#out + 1] = a
    end
  end
  table.sort(out)
  return out
end

--- Members ranked for one key, best first (rendezvous / highest random
--- weight). Adding or removing a member moves only the keys whose top
--- ranks it enters or leaves, never the rest -- unlike hash(key) % N.
function placement.rank(key, list)
  local scored = {}
  for _, a in ipairs(placement.members(list)) do
    scored[#scored + 1] = { addr = a, score = placement.hash(key .. "\0" .. a) }
  end
  table.sort(scored, function(x, y)
    if x.score ~= y.score then return x.score > y.score end
    return x.addr < y.addr
  end)
  local out = {}
  for i, s in ipairs(scored) do out[i] = s.addr end
  return out
end

placement.REPLICAS_JOB = 2

--- Where a key goes, and how many members must take a write for it to
--- stand. `opts.domainOwners` maps a domain id to the address that owns
--- it (the operator's declaration, as cluster-storage.cfg's `managers`).
--- @return { addrs = {...}, need = n, ns = "job"|"shared"|"domain"|"other" } | nil, err
function placement.targets(key, list, opts)
  opts = opts or {}
  local ns, scope = placement.namespace(key)
  if not ns then return nil, "invalid_key: not a string" end
  local members = placement.members(list)
  if #members == 0 then return nil, "no_storage_node" end

  if ns == "shared" then
    return { addrs = members, need = #members // 2 + 1, ns = ns }
  end

  if ns == "domain" then
    local owner = opts.domainOwners and opts.domainOwners[scope]
    for _, a in ipairs(members) do
      if a == owner then return { addrs = { a }, need = 1, ns = ns } end
    end
  end

  local ranked = placement.rank(key, members)
  if ns == "job" then
    local n = math.min(placement.REPLICAS_JOB, #ranked)
    local addrs = {}
    for i = 1, n do addrs[i] = ranked[i] end
    return { addrs = addrs, need = n, ns = ns }
  end
  return { addrs = { ranked[1] }, need = 1, ns = ns }
end

return placement
