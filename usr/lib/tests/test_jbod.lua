-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: JBOD disk pooling                   ║
-- ║                                                        ║
-- ║   1. The pool proxy unions reads across members,       ║
-- ║      sums capacity, routes writes to the member with    ║
-- ║      the most free space, and overwrites in place.      ║
-- ║   2. The boot gate is DEFAULT-OFF in every profile —    ║
-- ║      jbod loads only when advanced.jbod = true.         ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_jbod.lua

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_jbod.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

-- serialize is require()'d by jbod.lua at top level.
package.loaded["kernel.serialize"] = tryload("tos/kernel/serialize.lua")()

local jbod = tryload("tos/kernel/jbod.lua")()
local bootcfg = tryload("tos/kernel/bootcfg.lua")()

-- ── In-memory fake filesystem member ────────────────────────────────
-- Each member is a tiny RAM filesystem with a fixed capacity so we can
-- exercise the free-space write routing.
local function fakeMember(addr, total, seed)
  local files = {}        -- rel -> string
  for k, v in pairs(seed or {}) do files[k] = v end
  local function used()
    local u = 0; for _, v in pairs(files) do u = u + #v end; return u
  end
  local m = { address = addr }
  function m.isReadOnly() return false end
  function m.spaceTotal() return total end
  function m.spaceUsed() return used() end
  function m.exists(p) return files[p] ~= nil end
  function m.isDirectory(p) return false end
  function m.size(p) return files[p] and #files[p] or 0 end
  function m.lastModified(p) return files[p] and 1 or 0 end
  function m.list(p) local out = {}; for k in pairs(files) do out[#out+1] = k end; return out end
  function m.makeDirectory(p) return true end
  function m.remove(p) local had = files[p] ~= nil; files[p] = nil; return had end
  function m.rename(a, b) files[b] = files[a]; files[a] = nil; return true end
  -- Handles are OPAQUE, and read/write/close/seek live on the MEMBER
  -- with the handle as their first argument. This is what an
  -- OpenComputers filesystem component does, and what admin.lua's
  -- `component.proxy(addr)` members really are.
  --
  -- This stub used to return a method-bearing table from open(), which no
  -- component does. That mismatch is exactly why jbod.lua could ship a
  -- handle-forwarding path that errored on every real read and write
  -- while this suite stayed green -- a test is only as honest as the
  -- contract its fakes implement.
  local handles, nextH = {}, 1
  function m.open(p, mode)
    mode = mode or "r"
    if mode:find("[wa]") then
      if mode:find("w") then files[p] = "" end
      files[p] = files[p] or ""
    elseif files[p] == nil then
      return nil, "nf"
    end
    local id = nextH; nextH = nextH + 1
    handles[id] = { path = p, pos = 1 }
    return id
  end
  function m.read(h, n)
    local st = handles[h]; if not st then return nil end
    local data = files[st.path] or ""
    if st.pos > #data then return nil end
    local c = data:sub(st.pos, st.pos + n - 1)
    st.pos = st.pos + #c
    return c
  end
  function m.write(h, d)
    local st = handles[h]; if not st then return false end
    files[st.path] = (files[st.path] or "") .. d
    return true
  end
  function m.close(h) handles[h] = nil; return true end
  function m.seek(h, whence, off) return handles[h] and handles[h].pos or 0 end
  m._files = files
  return m
end

print("=== JBOD Tests ===")
print()

-- Member A is nearly full; member B is empty. A holds "alpha".
local A = fakeMember("aaaa", 1000, { ["/alpha"] = string.rep("x", 900) })
local B = fakeMember("bbbb", 1000, {})
local proxy, pool = jbod.makePool({ A, B })

-- 1. Capacity is the sum.
test("spaceTotal sums members", 2000, proxy.spaceTotal())

-- 2. Reads union across members.
test("exists finds file on member A", true, proxy.exists("/alpha"))
do
  local h = proxy.open("/alpha", "r")
  local data = ""
  while true do local c = h:read(4096); if not c then break end; data = data .. c end
  h:close()
  test("read pulls /alpha content", 900, #data)
end

-- 3. A NEW file routes to the member with the most free space (B, since A
--    is nearly full).
do
  local h = proxy.open("/beta", "w")
  h:write("hello"); h:close()
  test("new file landed on emptiest member (B)", "hello", B._files["/beta"])
  test("new file NOT on near-full member (A)", nil, A._files["/beta"])
end

-- 4. Overwrite goes in place (the member already holding it), not by free space.
do
  local h = proxy.open("/alpha", "w")
  h:write("Z"); h:close()
  test("overwrite stayed on A", "Z", A._files["/alpha"])
  test("overwrite did NOT copy to B", nil, B._files["/alpha"])
end

-- 5. list() unions + dedups.
do
  A._files["/shared"] = "1"; B._files["/shared"] = "2"
  local names = {}
  for _, n in ipairs(proxy.list("/")) do names[n] = (names[n] or 0) + 1 end
  test("list dedups a path present on both members", 1, names["/shared"])
end

-- 6. pool.stats reflects member count + summed capacity.
local s = pool.stats()
test("pool.stats member count", 2, s.members)
test("pool.stats total capacity", 2000, s.total)

-- ── Boot gate: default OFF in every profile ─────────────────────────
print()
for _, prof in ipairs({ "minimal", "normal", "full", "diagnostic" }) do
  -- No advanced override: jbod must NOT load, even on full/diagnostic.
  local cfg = bootcfg._normalize({ profile = prof })
  test("jbod default-off in profile '" .. prof .. "'",
    false, bootcfg.wants(cfg, "jbod", false))
end
-- Explicit opt-in flips it on regardless of profile.
do
  local cfg = bootcfg._normalize({ profile = "minimal", advanced = { jbod = true } })
  test("advanced.jbod=true enables it", true, bootcfg.wants(cfg, "jbod", false))
end
-- normalize must PRESERVE the advanced.jbod flag (it's a known FEATURE now).
do
  local cfg = bootcfg._normalize({ advanced = { jbod = true } })
  test("normalize keeps advanced.jbod", true, cfg.advanced.jbod)
end

-- ── Handle routing (the shipped member contract) ────────────────
-- kernel/fs.lua drives a mounted proxy component-style: it calls
-- `proxy.open(rel, mode)` and then `proxy.read(h, n)` -- handle first.
-- Everything above exercises the pool through the handle's convenience
-- methods; this section goes through the path fs.lua actually uses, and
-- pins that a handle routes back to the member that opened it.
print()
print("-- handle routing --")
do
  local C = fakeMember("cccc", 1000, { ["/gamma"] = string.rep("g", 120) })
  local D = fakeMember("dddd", 1000, {})
  local px = jbod.makePool({ C, D })

  local h = px.open("/gamma", "r")
  test("open returns a handle", true, h ~= nil)
  local ok, chunk = pcall(px.read, h, 4096)
  test("proxy.read(handle, n) does not error", true, ok)
  test("...and returns the bytes", 120, ok and chunk and #chunk or -1)
  pcall(px.close, h)

  local wh = px.open("/delta", "w")
  local wok = pcall(px.write, wh, "hello")
  test("proxy.write(handle, data) does not error", true, wok)
  pcall(px.close, wh)
  test("...and the bytes landed on the empty member", "hello", D._files["/delta"])

  -- Both members holding the same path is the case that makes routing
  -- load-bearing: a handle cannot be re-resolved by searching, because
  -- the search would find the wrong copy.
  C._files["/both"] = "from-C"
  D._files["/both"] = "from-D"
  local h2 = px.open("/both", "r")
  local ok2, c2 = pcall(px.read, h2, 64)
  test("handle routes to its owning member", "from-C", ok2 and c2 or nil)
  pcall(px.close, h2)

  -- A read handle and a write handle open at once must not collide.
  local rh = px.open("/gamma", "r")
  local wh2 = px.open("/epsilon", "w")
  px.write(wh2, "zzz")
  local rc = px.read(rh, 10)
  test("concurrent handles stay independent", "gggggggggg", rc)
  px.close(rh); px.close(wh2)
  test("...and the write still landed", "zzz", D._files["/epsilon"])
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
