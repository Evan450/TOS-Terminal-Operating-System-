-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Addressable local IPC                        ║
-- ║                                                            ║
-- ║  A service registers a named endpoint; a sandboxed program ║
-- ║  that holds the `ipc:<name>` capability calls it. This is  ║
-- ║  how a package's CLI reaches its own running daemon: since ║
-- ║  a library a sandboxed program requires loads inside that  ║
-- ║  sandbox, one instance each, the two share no state.       ║
-- ║                                                            ║
-- ║  Never raw PIDs, and not the compat event queue, whose     ║
-- ║  filter on sensitive signal names this must not go around. ║
-- ╚══════════════════════════════════════════════════════════╝

local ipc = {}

--! #SEC — a call crosses from sandboxed code into a service, which runs
--! through the kernel loader. So the only things that cross are PLAIN DATA,
--! copied, in both directions: a table from a program with a __index or
--! __gc would otherwise run the program's code as the service, and a table
--! handed back would let a program edit the service's live state. The walk
--! uses next, never pairs, so a metatable is never consulted, and it is
--! capped, because the copy runs at the kernel's expense.
local MAX_DEPTH = 16
local MAX_NODES = 8192

local function plain(v, st, depth)
  local t = type(v)
  if t == "nil" or t == "boolean" or t == "number" or t == "string" then return v end
  if t ~= "table" then error("a " .. t .. " cannot cross ipc", 0) end
  if depth >= MAX_DEPTH then error("too deep to cross ipc", 0) end
  if st.seen[v] then error("a cycle cannot cross ipc", 0) end
  st.seen[v] = true
  local out = {}
  for k, val in next, v do
    st.nodes = st.nodes + 1
    if st.nodes > MAX_NODES then error("too large to cross ipc", 0) end
    local kt = type(k)
    if kt ~= "string" and kt ~= "number" and kt ~= "boolean" then
      error("a " .. kt .. " key cannot cross ipc", 0)
    end
    out[k] = plain(val, st, depth + 1)
  end
  st.seen[v] = nil
  return out
end

local function packPlain(...)
  local st = { seen = {}, nodes = 0 }
  local n = select("#", ...)
  local out = { n = n }
  for i = 1, n do out[i] = plain((select(i, ...)), st, 0) end
  return out
end

local endpoints = {}

--- Register a named endpoint. Kernel-side only: a service reaches this
--- because its libraries load through the kernel loader, and a sandbox
--- has no way to it, so a program cannot squat a name.
-- @param name     lowercase name, letters digits and hyphens
-- @param handler  function(caller, ...) -> ...; caller = { user, tier }.
--                 THE HANDLER CHECKS THE TIER: the capability says which
--                 programs may knock, not what their user may ask for.
-- @param owner    who holds it; the same owner may register again
-- @return true, or false and a reason
function ipc.register(name, handler, owner)
  if type(name) ~= "string" or not name:match("^[%l%d][%l%d%-]*$") then
    return false, "bad endpoint name"
  end
  if type(handler) ~= "function" then return false, "handler must be a function" end
  local ep = endpoints[name]
  if ep and ep.owner ~= owner then
    return false, "endpoint '" .. name .. "' is held by " .. tostring(ep.owner)
  end
  endpoints[name] = { handler = handler, owner = owner }
  return true
end

--- Give up an endpoint. Only its owner can.
function ipc.unregister(name, owner)
  local ep = endpoints[name]
  if not ep or ep.owner ~= owner then return false end
  endpoints[name] = nil
  return true
end

--- Call an endpoint. Kernel-side: the sandbox's ipc.call fills in `session`
--- from what the program was built with, so a program cannot name another
--- user. Runs in the caller's coroutine, so a slow handler is the caller's
--- wait, and a handler's error comes back as nil, message.
function ipc.call(name, session, ...)
  local ep = endpoints[name]
  if not ep then return nil, "not running" end
  local okA, args = pcall(packPlain, ...)
  if not okA then return nil, args end
  local caller = {
    user = type(session) == "table" and session.user or nil,
    tier = type(session) == "table" and tonumber(session.tier) or 0,
  }
  local res = table.pack(pcall(ep.handler, caller, table.unpack(args, 1, args.n)))
  if not res[1] then return nil, tostring(res[2]) end
  local okR, out = pcall(packPlain, table.unpack(res, 2, res.n))
  if not okR then return nil, out end
  return table.unpack(out, 1, out.n)
end

return ipc
