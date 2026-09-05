-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster-worker-setup — OpenOS worker node wizard             ║
-- ║                                                                ║
-- ║  Sets up an OpenOS machine as a cluster worker: writes         ║
-- ║  /etc/cluster-worker.cfg, checks the shared secret actually    ║
-- ║  matches what the HMAC needs, and offers to autostart the      ║
-- ║  daemon from /etc/rc.cfg.                                      ║
-- ║                                                                ║
-- ║  THIS IS AN OPENOS PROGRAM, and the first thing it does is     ║
-- ║  prove it. Worker nodes are OpenOS-native on purpose: OpenOS   ║
-- ║  robots and computers are far more common in OC, and worker    ║
-- ║  code wants the wider library surface. Someone who copies      ║
-- ║  this onto a TOS box is not doing something slightly wrong,    ║
-- ║  they are on the wrong machine entirely — so instead of        ║
-- ║  failing on a missing `require`, it says which OS it is        ║
-- ║  looking at, how it can tell, and what to run instead.         ║
-- ║                                                                ║
-- ║  Deploy: copy next to cluster-worker.lua on the worker, then   ║
-- ║          run it.  (Both files, same directory.)                ║
-- ╚══════════════════════════════════════════════════════════════╝

local M = {}

M.CFG_PATH    = "/etc/cluster-worker.cfg"
M.RC_PATH     = "/etc/rc.cfg"
M.WORKER_NAME = "cluster-worker"
-- The Manager HMACs every frame with this secret; a short one is the
-- difference between authentication and decoration. Matches the length the
-- worker daemon and the installer README both state.
M.MIN_SECRET  = 16

-- ============================================================
-- Which OS is this?
-- ============================================================
-- Capability probes, not a version string: OpenOS and TOS both expose
-- `component` and `computer` (they are the OC machine API), so the honest
-- discriminator is what each one has that the other does NOT.
--
--   TOS-only     _G._TOS            the kernel's global state table
--                kernel.pkg         package manager
--                kernel.users       tier/session system
--                /tos/kernel/init.lua
--   OpenOS-only  filesystem         OpenOS's fs library (TOS calls it kernel.fs)
--                shell / term       OpenOS userland
--                /lib/core/         OpenOS's own library tree
--
-- `probe` is injected so the whole detection is testable off-box against a
-- fake environment; the default probes the real machine.

--- Default environment probe. Returns a table of booleans.
function M.probeEnvironment(probe)
  probe = probe or {}
  local function hasModule(name)
    if probe.hasModule then return probe.hasModule(name) end
    local ok, mod = pcall(require, name)
    return ok and mod ~= nil
  end
  local function hasGlobal(name)
    if probe.hasGlobal then return probe.hasGlobal(name) end
    return _G[name] ~= nil
  end
  local function hasPath(p)
    if probe.hasPath then return probe.hasPath(p) end
    local okF, fsMod = pcall(require, "filesystem")
    if okF and fsMod and fsMod.exists then return fsMod.exists(p) end
    local h = io and io.open and io.open(p, "r")
    if h then h:close(); return true end
    return false
  end
  return {
    tosGlobal   = hasGlobal("_TOS"),
    tosPkg      = hasModule("kernel.pkg"),
    tosUsers    = hasModule("kernel.users"),
    tosKernel   = hasPath("/tos/kernel/init.lua"),
    ooFilesystem = hasModule("filesystem"),
    ooShell     = hasModule("shell"),
    ooTerm      = hasModule("term"),
    ooLibCore   = hasPath("/lib/core/boot.lua"),
  }
end

--- Classify an environment table. Returns (os, confidence, reasons) where
--- os is "openos" | "tos" | "unknown" and reasons is an array of the
--- specific observations behind the verdict — so the operator is told HOW
--- it can tell, not just what it decided.
function M.classify(env)
  local tosHits, ooHits, reasons = 0, 0, {}
  local function tos(cond, why)
    if cond then tosHits = tosHits + 1; reasons[#reasons + 1] = "TOS: " .. why end
  end
  local function oo(cond, why)
    if cond then ooHits = ooHits + 1; reasons[#reasons + 1] = "OpenOS: " .. why end
  end

  tos(env.tosGlobal, "the _TOS kernel global is present")
  tos(env.tosPkg,    "kernel.pkg (TOS package manager) loads")
  tos(env.tosUsers,  "kernel.users (TOS tier system) loads")
  tos(env.tosKernel, "/tos/kernel/init.lua exists on disk")

  oo(env.ooFilesystem, "the 'filesystem' library loads (TOS calls it kernel.fs)")
  oo(env.ooShell,      "the 'shell' library loads")
  oo(env.ooTerm,       "the 'term' library loads")
  oo(env.ooLibCore,    "/lib/core/boot.lua exists on disk")

  -- Absences are evidence too, and on a bare machine they may be the ONLY
  -- evidence — say so rather than reporting "unknown" with an empty list.
  if ooHits == 0 and tosHits == 0 then
    reasons[#reasons + 1] = "neither OS's libraries are reachable from here"
    return "unknown", 0, reasons
  end
  if tosHits > ooHits then return "tos", tosHits - ooHits, reasons end
  if ooHits > tosHits then return "openos", ooHits - tosHits, reasons end
  -- A tie is genuinely ambiguous (a TOS box with the compat layer loaded can
  -- answer to some OpenOS names). Report it rather than guessing.
  return "unknown", 0, reasons
end

--- The message shown when this lands on a TOS machine. Data, so a test can
--- assert it actually names the right command instead of just "wrong OS".
function M.wrongOsMessage(osName, reasons)
  local out = {
    "This is the OpenOS worker setup, but this machine is running "
      .. (osName == "tos" and "TOS" or "an OS I can't identify") .. ".",
    "",
    "How I can tell:",
  }
  for _, r in ipairs(reasons or {}) do out[#out + 1] = "  - " .. r end
  out[#out + 1] = ""
  if osName == "tos" then
    out[#out + 1] = "Worker nodes are OpenOS-native by design: OpenOS machines are"
    out[#out + 1] = "far more common in OC and worker code wants the wider library"
    out[#out + 1] = "surface. TOS machines join a cluster as a MANAGER instead."
    out[#out + 1] = ""
    out[#out + 1] = "On this machine, run:   cluster-setup"
    out[#out + 1] = "and choose Manager. It installs and configures everything."
    out[#out + 1] = ""
    out[#out + 1] = "A Manager can then offload work to OpenOS workers — set up"
    out[#out + 1] = "those boxes with THIS script, on the OpenOS side."
  else
    out[#out + 1] = "Run this on an OpenOS machine. If this IS OpenOS, its"
    out[#out + 1] = "libraries aren't reachable — check the install."
  end
  return out
end

-- ============================================================
-- Config
-- ============================================================

--- Validate a shared secret. The HMAC is only as good as this, and it must
--- match the Manager's byte for byte.
function M.checkSecret(s)
  if type(s) ~= "string" or s == "" then return false, "no secret given" end
  if #s < M.MIN_SECRET then
    return false, string.format(
      "too short: %d characters, needs at least %d (it is the HMAC key, "
      .. "not a password)", #s, M.MIN_SECRET)
  end
  if s:find("%s") then
    return false, "no spaces — it has to match the Manager's value exactly, "
      .. "and a stray space is invisible in a config file"
  end
  return true, s
end

--- Domain id: picks the port (2001 + domain). Must match the Manager.
function M.checkDomain(s)
  local n = tonumber(s)
  if not n or n ~= math.floor(n) then return false, "domain id is a whole number" end
  if n < 0 or n > 999 then return false, "domain id is 0-999" end
  return true, n
end

function M.checkHostname(s)
  if type(s) ~= "string" or s:gsub("%s+", "") == "" then
    return false, "a hostname makes this worker identifiable in 'cluster-manager workers'"
  end
  -- Trim the ENDS only. Stripping interior whitespace would quietly turn
  -- "wk a" into "wka" — a name the operator never typed, appearing in the
  -- Manager's worker list. Reject it instead and let them retype.
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if #s > 24 then return false, "keep it under 24 characters" end
  if not s:match("^[%w_%-]+$") then
    return false, "letters, digits, _ and - only (no spaces)"
  end
  return true, s
end

--- Render the config file. Pure, and it round-trips through the loadfile()
--- the worker daemon uses.
function M.encodeConfig(cfg)
  return table.concat({
    "-- Generated by cluster-worker-setup.",
    "-- domain_id and shared_secret MUST match the Manager's",
    "-- /etc/cluster-manager.cfg exactly, or every frame fails its HMAC",
    "-- check and this worker never registers.",
    "return {",
    string.format("  domain_id     = %d,", cfg.domain_id),
    string.format("  hostname      = %q,", cfg.hostname),
    string.format("  shared_secret = %q,", cfg.shared_secret),
    "}",
    "",
  }, "\n")
end

--- Add the worker to OpenOS's rc autostart list, preserving whatever is
--- already there. Pure string surgery so it is testable; the caller does
--- the reading and writing.
function M.addToRc(existing, name)
  existing = existing or ""
  if existing:find('"' .. name .. '"', 1, true) then
    return existing, false            -- already listed; change nothing
  end
  if existing:match("enabled%s*=%s*{") then
    local out = existing:gsub("(enabled%s*=%s*{)", '%1 "' .. name .. '",', 1)
    return out, true
  end
  local add = 'enabled = { "' .. name .. '" }\n'
  if existing:gsub("%s+", "") == "" then return add, true end
  return existing .. "\n" .. add, true
end

-- ============================================================
-- The flow
-- ============================================================
-- ctx supplies every side effect (same shape as the TOS cluster wizard):
--   say(text, kind)  ask(prompt, default)  confirm(prompt) -> bool
--   readFile(path) -> string|nil     writeFile(path, data) -> ok, err
--   probe  (optional) -> passed to probeEnvironment

function M.run(ctx)
  local env = M.probeEnvironment(ctx.probe)
  local osName, _, reasons = M.classify(env)

  if osName ~= "openos" then
    for _, line in ipairs(M.wrongOsMessage(osName, reasons)) do
      ctx.say(line, "err")
    end
    return false, osName
  end

  ctx.say("OpenOS cluster worker setup", "title")
  ctx.say("", nil)
  ctx.say("This worker takes tasks from a TOS cluster MANAGER. Three answers,", nil)
  ctx.say("and two of them have to match that Manager exactly.", nil)
  ctx.say("", nil)

  local domain
  while true do
    local raw = ctx.ask("Domain id (must match the Manager)", "0")
    if raw == nil then ctx.say("Cancelled.", nil); return false end
    local okD, res = M.checkDomain(raw)
    if okD then domain = res; break end
    ctx.say(res, "err")
  end

  local hostname
  while true do
    local raw = ctx.ask("A name for this worker", "wk-a")
    if raw == nil then ctx.say("Cancelled.", nil); return false end
    local okH, res = M.checkHostname(raw)
    if okH then hostname = res; break end
    ctx.say(res, "err")
  end

  local secret
  while true do
    local raw = ctx.ask("Shared secret (copy it from the Manager)", nil)
    if raw == nil then ctx.say("Cancelled.", nil); return false end
    local okS, res = M.checkSecret(raw)
    if okS then secret = res; break end
    ctx.say(res, "err")
  end

  local cfg = { domain_id = domain, hostname = hostname, shared_secret = secret }
  local okW, werr = ctx.writeFile(M.CFG_PATH, M.encodeConfig(cfg))
  if not okW then
    ctx.say("Could not write " .. M.CFG_PATH .. ": " .. tostring(werr), "err")
    return false
  end
  ctx.say("Wrote " .. M.CFG_PATH, "ok")
  ctx.say("Worker port: " .. (2001 + domain) .. "  (2001 + domain id)", nil)

  if ctx.confirm("Start this worker automatically at boot?") then
    local rc = ctx.readFile(M.RC_PATH) or ""
    local newRc, changed = M.addToRc(rc, M.WORKER_NAME)
    if not changed then
      ctx.say("Already in " .. M.RC_PATH .. " — left alone.", "ok")
    else
      local okR, rerr = ctx.writeFile(M.RC_PATH, newRc)
      if okR then ctx.say("Added to " .. M.RC_PATH, "ok")
      else ctx.say("Could not update " .. M.RC_PATH .. ": " .. tostring(rerr), "warn") end
    end
  end

  ctx.say("", nil)
  ctx.say("Done", "title")
  ctx.say("On the MANAGER, /etc/cluster-manager.cfg needs:", nil)
  ctx.say("  worker_bridge_enabled = true,", nil)
  ctx.say("  worker_bridge_domain  = " .. domain .. ",", nil)
  ctx.say("  worker_bridge_secret  = \"" .. ("*"):rep(#secret) .. "\",  (the same secret)", nil)
  ctx.say("", nil)
  ctx.say("Then 'cluster-manager workers' on the Manager should list " .. hostname .. ".", nil)
  return true
end

-- ============================================================
-- Entry point (skipped when loaded as a library by the tests)
-- ============================================================

if not (...) then
  local ctx = {}
  function ctx.say(text, kind)
    local prefix = (kind == "err" and "  !! ") or (kind == "ok" and "  ok ")
      or (kind == "warn" and "  ?  ") or (kind == "title" and "== ") or ""
    print(prefix .. tostring(text or ""))
  end
  function ctx.ask(prompt, default)
    io.write("  " .. prompt .. (default and (" [" .. default .. "]") or "") .. ": ")
    local s = io.read()
    if s == nil then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return default end
    return s
  end
  function ctx.confirm(prompt)
    io.write("  " .. prompt .. " [y/N]: ")
    local s = (io.read() or ""):gsub("%s+", ""):lower()
    return s == "y" or s == "yes"
  end
  function ctx.readFile(path)
    local h = io.open(path, "r")
    if not h then return nil end
    local s = h:read("*a"); h:close(); return s
  end
  function ctx.writeFile(path, data)
    -- Temp + rename, so a failure part-way cannot leave a worker holding a
    -- half-written config it will refuse to parse at boot.
    local tmp = path .. ".tmp"
    local h, err = io.open(tmp, "w")
    if not h then return false, err end
    h:write(data)
    h:close()
    local okF, fsMod = pcall(require, "filesystem")
    if okF and fsMod and fsMod.rename then
      if fsMod.exists(path) then pcall(fsMod.remove, path) end
      return fsMod.rename(tmp, path)
    end
    return os.rename(tmp, path)
  end
  M.run(ctx)
end

return M
