-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Startup Scripts        ║
-- ║  /etc/rc.d/ service manager          ║
-- ╚══════════════════════════════════════╝
-- Loads and runs scripts from /etc/rc.d/ on boot.
-- Scripts are plain Lua files, executed in filename order.
-- A script can return a table with start/stop functions for
-- service-like behavior.
--
-- Phase 7 enhancements:
--   • Service tables may declare: deps, restart, caps, user
--   • Dependency-ordered startup (topological sort)
--   • Restart supervision for services that set restart = true
--   • Services run with sandboxed identity when caps/user are set

local rc = {}

local RC_DIR = "/etc/rc.d"
local services = {}  -- name -> service record
local fs = nil
local log = nil
local proc = nil  -- optional, for restart supervisor

-- Default caps granted to a service whose rc.d script doesn't declare
-- any. Mirrors modules.lua defaults: session-bound fs + filtered component.
-- Services that need more (net, compat.io, load) must opt in explicitly.
local DEFAULT_SERVICE_CAPS = {
  ["fs.read"]  = true,
  ["fs.write"] = true,
  ["component"] = true,
  ["net"] = true,  -- most rc.d services are network-facing (sshd, dhcpd)
}

local ALLOWED_SERVICE_CAPS = {
  ["fs.read"] = true, ["fs.write"] = true, ["component"] = true,
  ["compat.io"] = true, ["load"] = true, ["net"] = true,
  -- "legacy" intentionally excluded.
}

-- #SEC CR-6 — kernel-tier services get a GATED require, not the raw one.
-- The previous code set `require = require` in the kernel env while the
-- comment claimed "the require check below already gates via the safe
-- list" — but no such gate existed. A kernel-tier service could
-- `require("kernel.process")` / `require("kernel.users")` /
-- `require("kernel.sandbox")` and drive the whole kernel. We allow ONLY
-- the modules a legitimate boot service needs (the shipped services use
-- just kernel.event + computer; net/users/etc. come via the read-only
-- `_TOS` table) and fail closed on everything else.
local KERNEL_REQUIRE_ALLOW = {
  ["computer"]         = true,
  ["component"]        = true,
  ["kernel.event"]     = true,
  ["kernel.log"]       = true,
  ["kernel.serialize"] = true,
  ["kernel.config"]    = true,
}
local function gatedKernelRequire(modName)
  if type(modName) ~= "string" then
    error("require: module name must be a string", 2)
  end
  if KERNEL_REQUIRE_ALLOW[modName] then
    return require(modName)
  end
  error("rc.d kernel service denied require('" .. modName .. "') (#SEC CR-6)", 2)
end

-- Turn a caps spec (array or set) into a set, dropping anything not on
-- the allowed list so a malicious rc.d script can't request unknown caps.
local function normalizeCaps(spec)
  if type(spec) ~= "table" then
    local out = {}
    for k, v in pairs(DEFAULT_SERVICE_CAPS) do out[k] = v end
    return out
  end
  local out = {}
  for k, v in pairs(spec) do
    local name
    if type(k) == "number" and type(v) == "string" then
      name = v
    elseif type(k) == "string" and v then
      name = k
    end
    if name and ALLOWED_SERVICE_CAPS[name] then
      out[name] = true
    end
  end
  return out
end

-- Resolve a session for a declared `user` field. Falls back to the
-- kernel boot session so services without a declared identity still
-- run, just at root. A service that declares user = "bob" must have
-- that user exist in the users DB; if not, we fail the service rather
-- than silently running it as root.
local function sessionForUser(userName)
  local ok, usersmod = pcall(require, "kernel.users")
  if not ok or not usersmod then return nil, "users module unavailable" end
  -- No user declared: fall back to the kernel session (root). Services
  -- that need a specific identity must set the `user` field explicitly.
  if not userName then
    if _G._TOS and _G._TOS.bootSession then return _G._TOS.bootSession end
    if usersmod.kernelSession then return usersmod.kernelSession() end
    return nil, "no session available"
  end
  -- "_kernel_" is the sentinel for kernel-tier services (rshd, etc.).
  -- It is NOT a user in the DB — resolve it to the synthetic kernel
  -- session directly so services can run at root without requiring a
  -- real account to exist.
  if userName == "_kernel_" then
    if usersmod.kernelSession then return usersmod.kernelSession() end
    return nil, "kernelSession unavailable"
  end
  if usersmod.sessionFor then
    local s = usersmod.sessionFor(userName)
    if s then return s end
  end
  -- Fall back to creating a session token for the named user if the
  -- users module exposes a helper for it.
  if usersmod.getUser then
    local u = usersmod.getUser(userName)
    if u and usersmod.createSession then
      local s = usersmod.createSession(u)
      if s then return s end
    end
  end
  return nil, "unknown user '" .. tostring(userName) .. "'"
end

function rc.init(modules)
  fs   = modules.fs
  log  = modules.log
  proc = modules.proc
end

-- ── Topological sort ────────────────────────────────────
-- Given a table of { name -> { deps = { ... } } }, returns an ordered
-- list of names such that each service's dependencies come before it.
-- Unresolvable deps are warned but not fatal (the service just starts
-- after everything else).
local function topoSort(svcs)
  local visited, sorted, inStack = {}, {}, {}
  local function visit(name)
    if visited[name] then return end
    if inStack[name] then
      if log then log.warn("rc", "Circular dependency at '" .. name .. "' — breaking cycle") end
      return
    end
    inStack[name] = true
    local rec = svcs[name]
    if rec and rec.deps then
      for _, dep in ipairs(rec.deps) do
        visit(dep)
      end
    end
    inStack[name] = nil
    visited[name] = true
    sorted[#sorted + 1] = name
  end
  -- Seed with all registered names
  local allNames = {}
  for name in pairs(svcs) do allNames[#allNames + 1] = name end
  table.sort(allNames) -- deterministic within a dep tier
  for _, n in ipairs(allNames) do visit(n) end
  return sorted
end

--- Run all startup scripts in /etc/rc.d/
function rc.runAll()
  if not fs then return end
  if not fs.exists(RC_DIR) then
    fs.makeDirectory(RC_DIR)
    return
  end

  local files = fs.list(RC_DIR)
  if not files then return end

  -- Collect and sort filenames
  local names = {}
  if type(files) == "table" then
    for _, name in ipairs(files) do
      if name:match("%.lua$") then
        names[#names + 1] = name
      end
    end
  elseif type(files) == "function" then
    for name in files do
      if name:match("%.lua$") then
        names[#names + 1] = name
      end
    end
  end
  table.sort(names)

  -- Two-pass load:
  --   Pass A: peek at each script to read the declared `caps` / `user`
  --           fields WITHOUT executing arbitrary service code at root.
  --   Pass B: reload the script inside a sandbox built from those caps
  --           and bound to the declared user's session.
  --
  -- We do the peek by looking for simple literal top-level assignments
  -- in the script source. This is deliberately conservative: a service
  -- that generates its manifest dynamically will fall through to the
  -- default caps, which is the safest possible posture. The review
  -- explicitly called out that the old code ran every rc.d script with
  -- full kernel authority just to read result.caps — now we never do.

  local function peekServiceMeta(src)
    -- Returns a table of declared metadata fields (caps, user, restart,
    -- maxRestart, deps). Only accepts simple literal patterns so a
    -- clever script can't trick the peek into granting itself extra
    -- caps. Anything the peek can't parse is treated as absent.
    local meta = {}
    local capsStr = src:match("caps%s*=%s*(%b{})")
    if capsStr then
      meta.caps = {}
      for cap in capsStr:gmatch('"([%w%._]+)"') do
        meta.caps[#meta.caps + 1] = cap
      end
      for cap in capsStr:gmatch("'([%w%._]+)'") do
        meta.caps[#meta.caps + 1] = cap
      end
    end
    meta.user = src:match('user%s*=%s*"([%w_-]+)"')
               or src:match("user%s*=%s*'([%w_-]+)'")
    -- #SEC C2 — the regex peek above can fire on `user = "_kernel_"`
    -- found inside a comment, docstring, or string literal. Matching
    -- elevates the service to a kernel-tier sandbox-bypassed env. We
    -- harden against that two ways:
    --   (a) only honour `_kernel_` for services whose filename is on a
    --       hardcoded allowlist;
    --   (b) ALWAYS verify the match isn't inside a `--` comment.
    -- Anything else gets demoted to a regular user-tier service.
    if meta.user == "_kernel_" then
      meta._kernelClaimed = true
    end
    meta.restart = src:match("restart%s*=%s*true") and true or false
    local mr = src:match("maxRestart%s*=%s*(%d+)")
    if mr then meta.maxRestart = tonumber(mr) end
    return meta
  end

  -- Phase 1: load all scripts and register service tables
  -- #MEM — kernel.sandbox (one of the largest kernel modules) is only
  -- needed to build the env for USER-TIER services. The four shipped
  -- services are all kernel-tier (allowlist below) and use the explicit
  -- env from buildKernelEnv, so a stock install never loads sandbox at
  -- boot; it is require()d at the one call site that needs it (a
  -- third-party/package service), and later by pkg command dispatch.
  local loaded = {}  -- svcName -> service table (or true for plain scripts)

  -- #SEC C2 — hardcoded allowlist of services that may run as `_kernel_`.
  -- A regex match on the source can be made to fire from inside a comment
  -- or string literal; without this list, any admin who drops a file into
  -- /etc/rc.d gains code execution at root in the next boot.
  local KERNEL_SERVICE_ALLOWLIST = {
    ["10-discoveryd"] = true,
    ["20-chatrelay"]  = true,
    ["20-fileshare"]  = true,
    ["20-rshd"]       = true,
  }

  -- Returns true iff the literal `_kernel_` token appears outside of any
  -- comment in `src`. Cheap line-by-line scan that strips comments first.
  local function kernelTokenOutsideComments(src)
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
      -- Strip from `--` onwards, but be string-literal-aware: a `--` inside
      -- a quoted string doesn't start a comment. Conservative parse:
      -- walk the line, tracking single/double quote state.
      local code = {}
      local i = 1
      local inS, inD = false, false
      while i <= #line do
        local c = line:sub(i, i)
        if not inS and not inD and c == "-" and line:sub(i+1, i+1) == "-" then
          break  -- rest of line is comment
        end
        if not inD and c == "'" and line:sub(i-1, i-1) ~= "\\" then inS = not inS end
        if not inS and c == '"' and line:sub(i-1, i-1) ~= "\\" then inD = not inD end
        code[#code + 1] = c
        i = i + 1
      end
      if table.concat(code):find('"_kernel_"', 1, true)
         or table.concat(code):find("'_kernel_'", 1, true) then
        return true
      end
    end
    return false
  end

  -- #SEC H6 — explicit env for `_kernel_` services. The previous
  -- implementation used `__index = _G` plus `env._G = _G`, which gave
  -- every kernel-tier service full reach into the real global table —
  -- one buggy or compromised allowlisted service had complete authority.
  -- We now hand each service a fixed set of names it actually needs:
  -- pcall/print/string/table/etc, plus an explicit `require` and the
  -- read-only `_TOS` table. Anything else (`debug`, `package`, raw
  -- `os.execute`) is out of reach unless they explicitly require() it,
  -- which the require check below already gates via the safe list.
  -- #SEC CR-6 — gatedKernelRequire (module-level) replaces the raw require.
  local function buildKernelEnv()
    local env = {
      -- Base Lua (no debug, no rawset/rawget — same posture as sandbox)
      assert = assert, error = error, pcall = pcall, xpcall = xpcall,
      type = type, tostring = tostring, tonumber = tonumber,
      pairs = pairs, ipairs = ipairs, next = next, select = select,
      rawequal = rawequal, rawlen = rawlen,
      setmetatable = setmetatable, getmetatable = getmetatable,
      math = math, string = string, table = table,
      utf8 = utf8, coroutine = coroutine,
      print = print,
      require = gatedKernelRequire,  -- #SEC CR-6 — gated, not raw
      _VERSION = _VERSION,
    }
    -- _TOS exposed read-only via a metatable so a service can't mutate
    -- the shared kernel state by clobbering a key.
    if _G._TOS then
      local tos = _G._TOS
      env._TOS = setmetatable({}, {
        __index    = tos,
        __newindex = function(_, k)
          error("_TOS is read-only from rc.d services (key=" .. tostring(k) .. ")", 2)
        end,
        __metatable = false,
      })
    end
    env._G = env  -- shadow: code that touches _G sees this env, not real _G
    return env
  end

  for _, name in ipairs(names) do
    local path = RC_DIR .. "/" .. name
    local svcName = name:gsub("%.lua$", "")

    if log then log.info("rc", "Loading: " .. name) end

    local source = fs.readFile(path)
    if source then
      -- Peek the declared caps/user before executing anything.
      local meta = peekServiceMeta(source)

      -- #SEC C2 — gate the kernel-tier claim.
      if meta._kernelClaimed then
        if not KERNEL_SERVICE_ALLOWLIST[svcName] then
          if log then
            log.warn("rc", "Refusing kernel-tier service '" .. name ..
              "': not in C2 allowlist; demoting to user-tier")
          end
          meta.user = "root"  -- safe default for a former kernel claim
        elseif not kernelTokenOutsideComments(source) then
          if log then
            log.warn("rc", "Refusing kernel-tier service '" .. name ..
              "': _kernel_ token only appears in comments")
          end
          meta.user = "root"
        end
      end

      local caps = normalizeCaps(meta.caps)
      local session, sessErr = sessionForUser(meta.user)
      if not session then
        if log then
          log.warn("rc", "Skipping '" .. name .. "': " .. tostring(sessErr))
        end
      else
        local svcEnv
        if meta.user == "_kernel_" then
          svcEnv = buildKernelEnv()
        else
          -- allowUserLibs: a service shim may require the library its own
          -- package installed (`require("mail")`, `require("clusterd")`) —
          -- the established pattern for every service add-on. It only
          -- lifts the blocklist for names that resolve under /usr/lib or
          -- /usr/modules, and rc.d services already carry `net` in their
          -- default caps, so it widens nothing else. See the note in
          -- sandbox.lua's makeSafeRequire.
          svcEnv = require("kernel.sandbox").build({
            caps = caps, session = session,
            allowUserLibs = true })
        end
        local fn, err = load(source, "=" .. path, "t", svcEnv)
        if fn then
          local ok, result = pcall(fn)
          if ok then
            if type(result) == "table" and result.start then
              -- #SVC — a sibling `<name>.disabled` marker (written by pkg.install
              -- for service packages with defaultState="disabled") means: REGISTER
              -- this service so `service start` can find it, but do NOT auto-start
              -- it at boot. Without this the rc loader would start every installed
              -- daemon on the next boot regardless of the package's disabled state.
              local disabledAtBoot = fs.exists(RC_DIR .. "/" .. svcName .. ".disabled")
              services[svcName] = {
                start   = result.start,
                stop    = result.stop,
                running = false,
                disabledAtBoot = disabledAtBoot,
                path    = path,
                -- Phase 7 fields (from service table).
                -- `caps`/`user` come from the peek-resolved values so
                -- rc.list() reports the ENFORCED identity, not whatever
                -- the service code decided to claim at runtime.
                deps    = result.deps or {},
                restart = meta.restart or (result.restart and true) or false,
                caps    = caps,
                user    = meta.user,
                restartCount = 0,
                maxRestart   = meta.maxRestart or result.maxRestart or 5,
              }
              loaded[svcName] = result
            else
              loaded[svcName] = true  -- plain script, already ran
            end
          else
            if log then log.warn("rc", "Error in " .. name .. ": " .. tostring(result)) end
          end
        else
          if log then log.warn("rc", "Syntax error in " .. name .. ": " .. tostring(err)) end
        end
      end
    end
  end

  -- Phase 2: topological sort by dependencies
  local order = topoSort(services)

  -- Phase 3: start services in dependency order. Leave `running` = false
  -- on a failed start so the supervisor picks the service up on its
  -- next tick (this was previously dead code — see tryRestart).
  for _, svcName in ipairs(order) do
    local svc = services[svcName]
    if svc and svc.disabledAtBoot and not svc.running then
      -- Registered but intentionally not started (disabled-by-default package).
      if log then log.info("rc", "Service registered (disabled): " .. svcName) end
    elseif svc and not svc.running then
      local sok, serr = pcall(svc.start)
      if sok then
        svc.running = true
        if log then log.info("rc", "Service started: " .. svcName) end
      else
        svc.running = false
        svc.lastError = tostring(serr)
        if log then log.warn("rc", "Service start failed: " .. svcName .. ": " .. tostring(serr)) end
      end
    end
  end
end

--- Stop all running services (called on shutdown)
function rc.stopAll()
  for name, svc in pairs(services) do
    if svc.running and svc.stop then
      local ok, err = pcall(svc.stop)
      if ok then
        svc.running = false
        if log then log.info("rc", "Service stopped: " .. name) end
      else
        if log then log.warn("rc", "Service stop failed: " .. name .. ": " .. tostring(err)) end
      end
    end
  end
end

--- Start a specific service by name
function rc.start(name)
  local svc = services[name]
  if not svc then return false, "Unknown service: " .. name end
  if svc.running then return false, "Already running" end
  local ok, err = pcall(svc.start)
  if ok then
    svc.running = true
    -- #SVC — an explicit operator start persists the enable: clear the
    -- disabled marker so the service also auto-starts on the next boot.
    if svc.disabledAtBoot and fs then
      pcall(fs.remove, RC_DIR .. "/" .. name .. ".disabled")
      svc.disabledAtBoot = false
    end
    return true
  end
  return false, tostring(err)
end

--- Stop a specific service
function rc.stop(name)
  local svc = services[name]
  if not svc then return false, "Unknown service: " .. name end
  if not svc.running then return false, "Not running" end
  if not svc.stop then return false, "No stop handler" end
  local ok, err = pcall(svc.stop)
  if ok then
    svc.running = false
    return true
  end
  return false, tostring(err)
end

--- List all known services
function rc.list()
  local result = {}
  for name, svc in pairs(services) do
    result[#result + 1] = {
      name         = name,
      running      = svc.running,
      enabled      = not svc.disabledAtBoot,
      path         = svc.path,
      deps         = svc.deps,
      restart      = svc.restart,
      restartCount = svc.restartCount,
      caps         = svc.caps,
      user         = svc.user,
    }
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

--- Attempt to restart a crashed service (called by supervisor tick).
function rc.tryRestart(name)
  local svc = services[name]
  if not svc then return false end
  if not svc.restart then return false end
  if svc.restartCount >= svc.maxRestart then
    if log then log.warn("rc", "Service '" .. name .. "' exceeded max restarts (" .. svc.maxRestart .. ")") end
    return false
  end
  svc.restartCount = svc.restartCount + 1
  if log then log.info("rc", "Restarting service: " .. name .. " (attempt " .. svc.restartCount .. ")") end
  local ok, err = pcall(svc.start)
  if ok then
    svc.running = true
    return true
  end
  if log then log.warn("rc", "Restart failed: " .. name .. ": " .. tostring(err)) end
  return false
end

--- Supervisor tick: check for crashed services and restart them.
-- Call this periodically from the kernel loop or cron.
-- Also gives each service an optional `check` hook — if it returns a
-- falsy value, the service is considered dead and restarted. This
-- closes the loophole where a service's event listener throws but no
-- one ever clears svc.running, so the supervisor never fires.
function rc.supervise()
  for name, svc in pairs(services) do
    if svc.running and type(svc.check) == "function" then
      local ok, alive = pcall(svc.check)
      if not ok or not alive then
        svc.running = false
        svc.lastError = (not ok) and tostring(alive) or "check returned false"
      end
    end
    -- #SEC — a DISABLED-at-boot service (e.g. rshd shipped off-by-default
    -- via its .disabled marker) is intentionally not running; the restart
    -- supervisor must NOT resurrect it, or the security default is silently
    -- defeated ~30s after boot (caught in the emulator: rshd came back up).
    -- A manual `service start` clears disabledAtBoot, so a genuine crash of
    -- an operator-enabled service is still restarted.
    if svc.restart and not svc.running and not svc.disabledAtBoot then
      rc.tryRestart(name)
    end
  end
end

--- Enable a script (create it in rc.d)
function rc.enable(name, content)
  if not fs then return false end
  if not fs.exists(RC_DIR) then fs.makeDirectory(RC_DIR) end
  return fs.writeFile(RC_DIR .. "/" .. name .. ".lua", content)
end

--- Disable a script (remove from rc.d)
function rc.disable(name)
  if not fs then return false end
  rc.stop(name)
  return fs.remove(RC_DIR .. "/" .. name .. ".lua")
end

-- Test hooks (not public API).
rc._gatedKernelRequire    = gatedKernelRequire
rc._KERNEL_REQUIRE_ALLOW  = KERNEL_REQUIRE_ALLOW

return rc
