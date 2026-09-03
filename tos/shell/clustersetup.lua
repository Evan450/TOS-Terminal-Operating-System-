-- ╔═══════════════════════════════════════════════════════════════╗
-- ║  TOS Shell — Cluster setup wizard                              ║
-- ║                                                                ║
-- ║  ONE front door for standing up a cluster, and it works with   ║
-- ║  nothing installed — because "what am I supposed to install,   ║
-- ║  and where?" is the question an operator actually has, and no  ║
-- ║  amount of README fixes it if the answer lives in a README.    ║
-- ║                                                                ║
-- ║  The answer, stated once, here:                                ║
-- ║                                                                ║
-- ║    Every cluster machine installs exactly ONE package, from    ║
-- ║    the ordinary Optional Utilities disk. The control machine   ║
-- ║    gets `cluster-master`; every compute machine gets           ║
-- ║    `cluster-manager`. Nothing is copied by hand, ever. The     ║
-- ║    only optional extra is OpenOS worker boxes, which are a     ║
-- ║    separate, later, deliberate step.                           ║
-- ║                                                                ║
-- ║  Lives in the BASE image, not in either package, precisely so  ║
-- ║  it can answer that question BEFORE anything is installed.     ║
-- ║  It is named `cluster-setup`, not `cluster`: a registry        ║
-- ║  command shadows /usr/bin (see executor.lua), so taking the    ║
-- ║  name `cluster` would break the Master's own CLI the moment    ║
-- ║  the package was installed.                                    ║
-- ║                                                                ║
-- ║  EVERYTHING GOES THROUGH AN INJECTED ctx. The wizard never     ║
-- ║  touches io.read, never draws, and never calls a kernel        ║
-- ║  module directly — so the whole flow runs off-box against      ║
-- ║  scripted answers (test_cluster_setup.lua) instead of being    ║
-- ║  the one part of the cluster nobody can test.                  ║
-- ╚═══════════════════════════════════════════════════════════════╝

local M = {}

M.MASTER_PKG  = "cluster-master"
M.MANAGER_PKG = "cluster-manager"
M.MASTER_SVC  = "clusterd"          -- rc.d stem, NOT the package name
M.MANAGER_SVC = "cluster-manager"
M.MASTER_CFG  = "/etc/cluster-master.cfg"
M.MANAGER_CFG = "/etc/cluster-manager.cfg"

-- ============================================================
-- The explainer
-- ============================================================

--- What a cluster is made of, as data so a test can prove the wizard
--- actually names both packages and both roles rather than gesturing at
--- "see the manual".
function M.topology()
  return {
    { role = "Master",
      pkg  = M.MASTER_PKG,
      svc  = M.MASTER_SVC,
      one  = true,
      what = "The control machine. Keeps the cluster's state, decides which "
          .. "Manager runs what, and hands out work. Exactly ONE per cluster "
          .. "— a second Master would accept registrations of its own and the "
          .. "cluster would split in half without telling you." },
    { role = "Manager",
      pkg  = M.MANAGER_PKG,
      svc  = M.MANAGER_SVC,
      one  = false,
      what = "A compute machine. Registers with the Master and runs the work "
          .. "it is given. Install this on as many machines as you want to "
          .. "put to work." },
  }
end

--- Lines for the "I don't know what to install" screen. Pure.
function M.explain()
  local out = {
    "A cluster is one Master and any number of Managers.",
    "",
  }
  for _, t in ipairs(M.topology()) do
    out[#out + 1] = t.role .. "  ->  pkg install " .. t.pkg
    for line in (t.what):gmatch("[^\n]+") do
      -- Wrapped by the caller; keep the data as one paragraph per role.
      out[#out + 1] = "    " .. line
    end
    out[#out + 1] = ""
  end
  out[#out + 1] = "Both packages are on the ordinary Optional Utilities disk."
  out[#out + 1] = "You never copy files by hand. Install the one package this"
  out[#out + 1] = "machine needs, then run 'cluster-setup' again to configure it."
  return out
end

-- ============================================================
-- Validation (pure)
-- ============================================================

--- An OC component address is 36 chars of hex and dashes. Operators
--- routinely paste a TRUNCATED one (every TOS listing abbreviates to 8),
--- so the check exists to catch that specific, very common mistake with a
--- message that says what went wrong rather than "invalid".
function M.checkMasterAddress(s)
  if type(s) ~= "string" then return false, "no address given" end
  s = s:gsub("%s+", "")
  if s == "" then return false, "no address given" end
  if s:find("%.%.%.") then
    return false, "that looks like a shortened address (it contains '...') — "
      .. "the Master prints its full address during setup; use that"
  end
  if #s < 32 then
    return false, "too short for a full modem address (" .. #s
      .. " chars; a real one is 36)"
  end
  if not s:match("^[%x%-]+$") then
    return false, "an address is only hex digits and dashes"
  end
  return true, s
end

--- Pairing codes come from `cluster pair start` on the Master.
function M.checkPairingCode(s)
  if type(s) ~= "string" or s:gsub("%s+", "") == "" then
    return false, "no pairing code given"
  end
  s = s:gsub("%s+", "")
  if #s < 6 then
    return false, "pairing codes are longer than that — run 'cluster pair start'"
      .. " on the Master and copy what it prints"
  end
  return true, s
end

local function clampNumber(v, lo, hi, dflt)
  v = tonumber(v)
  if not v then return dflt end
  return math.max(lo, math.min(hi, math.floor(v)))
end

--- Build the Master's config from raw answers. Pure, so the defaults and
--- the clamping are checkable without running an install.
function M.masterConfig(a)
  a = a or {}
  return {
    host_thread_budget       = clampNumber(a.threads, 1, 64, 4),
    heartbeat_interval       = clampNumber(a.heartbeat, 1, 60, 5),
    heartbeat_degraded_after = clampNumber(a.degraded, 2, 300, 15),
    heartbeat_offline_after  = clampNumber(a.offline, 3, 600, 30),
  }
end

--- Build the Manager's config. `master` must already be validated.
function M.managerConfig(a)
  a = a or {}
  local profile = a.profile
  if profile ~= "compute_bound" and profile ~= "io_bound" then profile = "mixed" end
  return {
    master_address         = a.master,
    hostname               = a.hostname,
    compute_profile        = profile,
    worker_count           = clampNumber(a.workers, 1, 16, 4),
    min_heartbeat_seconds  = 2,
    max_heartbeat_seconds  = 30,
    register_retry_seconds = 10,
  }
end

--- Serialize a config table to the `return { ... }` form the daemons
--- loadfile() back. Pure. Keys are sorted so a regenerated config diffs
--- cleanly against the previous one instead of reordering randomly.
function M.encodeConfig(tbl)
  local keys = {}
  for k in pairs(tbl) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = { "-- Generated by cluster-setup. Safe to edit by hand.\nreturn {\n" }
  for _, k in ipairs(keys) do
    local v = tbl[k]
    local vs
    if type(v) == "string" then vs = string.format("%q", v)
    elseif type(v) == "number" or type(v) == "boolean" then vs = tostring(v)
    else vs = string.format("%q", tostring(v)) end
    out[#out + 1] = string.format("  %s = %s,\n", k, vs)
  end
  out[#out + 1] = "}\n"
  return table.concat(out)
end

-- ============================================================
-- The flow
-- ============================================================
-- ctx supplies every side effect, so this function is pure control flow:
--   say(text, kind)            kind = nil|"ok"|"warn"|"err"|"title"
--   choose(title, lines, opts) -> index (1-based) into opts
--   ask(prompt, default)       -> string or nil (nil = operator cancelled)
--   installed(pkgName)         -> bool
--   install(pkgName)           -> ok, err
--   writeFile(path, data)      -> ok, err        (caller makes it atomic)
--   startService(svcName)      -> ok, err
--   setBootStart(svcName, on)  -> ok, err
--   modemCount()               -> total, wireless
--   myModemAddress()           -> addr or nil
--   startPairing()             -> code, secondsRemaining  (Master only)
--   pairWith(addr, code)       -> ok, message              (Manager only)
--   hostname()                 -> string or nil

local function report(ctx, ok, what, err)
  if ok then ctx.say(what, "ok") else ctx.say(what .. ": " .. tostring(err), "err") end
  return ok
end

--- Stage 0 — hardware. A cluster with no modem is not a cluster, and
--- finding that out AFTER installing and configuring is a waste of the
--- operator's time.
function M.checkHardware(ctx)
  local total, wireless = ctx.modemCount()
  if (total or 0) == 0 then
    ctx.say("No modem on this machine.", "err")
    ctx.say("Every cluster node needs one — install a modem card and re-run.", nil)
    return false
  end
  if (wireless or 0) == 0 then
    ctx.say("Only a wired modem found. That works, but every node must be"
      .. " cabled to the Master.", "warn")
  end
  return true
end

--- The whole wizard. Returns true when the machine ended up configured.
function M.run(ctx)
  ctx.say("Cluster setup", "title")

  local topo = M.topology()
  local haveMaster  = ctx.installed(M.MASTER_PKG)
  local haveManager = ctx.installed(M.MANAGER_PKG)

  -- If both are installed something is wrong: one machine is one role.
  if haveMaster and haveManager then
    ctx.say("Both cluster packages are installed on this machine.", "warn")
    ctx.say("A machine is either the Master or a Manager, not both. Uninstall"
      .. " the one this box shouldn't be ('pkg uninstall <name>').", nil)
    return false
  end

  local role
  if haveMaster then role = "master"
  elseif haveManager then role = "manager"
  else
    -- Nothing installed: this is the case the operator is actually stuck in.
    local lines = M.explain()
    local pick = ctx.choose("What is this machine?", lines,
      { "Master (control)", "Manager (compute)", "Cancel" })
    if pick == 1 then role = "master"
    elseif pick == 2 then role = "manager"
    else ctx.say("Nothing changed.", nil); return false end
  end

  if not M.checkHardware(ctx) then return false end

  local pkg = (role == "master") and M.MASTER_PKG or M.MANAGER_PKG
  local svc = (role == "master") and M.MASTER_SVC or M.MANAGER_SVC

  if not ctx.installed(pkg) then
    ctx.say("Installing " .. pkg .. " ...", nil)
    local okI, err = ctx.install(pkg)
    if not report(ctx, okI, "Installed " .. pkg, err) then
      ctx.say("Insert the Optional Utilities disk and try again — both cluster"
        .. " packages are on it.", nil)
      return false
    end
  else
    ctx.say(pkg .. " is already installed.", "ok")
  end

  local cfg, cfgPath
  if role == "master" then
    cfg = M.masterConfig({
      threads   = ctx.ask("Jobs this Master may run at once", "4"),
      heartbeat = ctx.ask("Heartbeat interval (seconds)", "5"),
      degraded  = ctx.ask("Call a Manager degraded after (seconds)", "15"),
      offline   = ctx.ask("Call a Manager offline after (seconds)", "30"),
    })
    cfgPath = M.MASTER_CFG
  else
    -- Manager: the Master's address is the one answer with a real failure
    -- mode, so it is checked and re-asked rather than written wrong.
    local addr
    while true do
      local raw = ctx.ask("The Master's FULL modem address", nil)
      if raw == nil then ctx.say("Cancelled.", nil); return false end
      local okA, res = M.checkMasterAddress(raw)
      if okA then addr = res; break end
      ctx.say(res, "err")
    end
    cfg = M.managerConfig({
      master   = addr,
      hostname = ctx.hostname(),
      profile  = ctx.ask("Compute profile (compute_bound/io_bound/mixed)", "mixed"),
      workers  = ctx.ask("How many workers", "4"),
    })
    cfgPath = M.MANAGER_CFG
  end

  local okW, werr = ctx.writeFile(cfgPath, M.encodeConfig(cfg))
  if not report(ctx, okW, "Wrote " .. cfgPath, werr) then return false end

  -- Boot behaviour BEFORE starting: rc.start persists the enable by
  -- clearing the service's .disabled marker, so asking afterwards and then
  -- writing a different file (which is what the old installer did) left the
  -- operator's answer with no effect at all.
  local atBoot = ctx.choose("Start " .. svc .. " automatically at boot?", {
    "Answer now — starting the service also decides this.",
  }, { "Yes, start at boot", "No, I'll start it by hand" }) == 1

  local okS, serr = ctx.startService(svc)
  report(ctx, okS, "Started " .. svc, serr)
  local okB, berr = ctx.setBootStart(svc, atBoot)
  report(ctx, okB, atBoot and "Enabled at boot" or "Left disabled at boot", berr)

  -- Pairing: the step that actually joins the machines together, and the
  -- one the old flow made hardest by printing a truncated address.
  if role == "master" then
    ctx.say("Pairing", "title")
    local code, secs = ctx.startPairing()
    if not code then
      ctx.say("Could not open a pairing window: " .. tostring(secs), "warn")
      ctx.say("Run 'cluster pair start' once the daemon is up.", nil)
    else
      local addr = ctx.myModemAddress()
      ctx.say("Pairing window open for " .. math.floor(secs or 0) .. "s.", "ok")
      ctx.say("On EACH Manager, run cluster-setup and give it:", nil)
      ctx.say("", nil)
      -- The full address, deliberately. The old installer truncated it to 12
      -- characters and printed it as a command line, which read as
      -- copy-pasteable and was not — so every operator typed a broken
      -- command once before working out why.
      ctx.say("  Master address:  " .. tostring(addr or "(no modem address?)"), "title")
      ctx.say("  Pairing code:    " .. code, "title")
      ctx.say("", nil)
      ctx.say("Watch them arrive with 'cluster pair status'.", nil)
    end
  else
    ctx.say("Pairing", "title")
    local code
    while true do
      local raw = ctx.ask("Pairing code from the Master", nil)
      if raw == nil then
        ctx.say("Skipped pairing. Run 'cluster-manager pair <addr> <code>' later.", "warn")
        code = nil; break
      end
      local okC, res = M.checkPairingCode(raw)
      if okC then code = res; break end
      ctx.say(res, "err")
    end
    if code then
      local okP, msg = ctx.pairWith(cfg.master_address, code)
      if okP then ctx.say("Paired with the Master.", "ok")
      else
        ctx.say("Pair round-trip failed: " .. tostring(msg), "warn")
        ctx.say("The local trust entry was still written. If the Manager shows"
          .. " up on the Master, it worked; if not, re-run cluster-setup.", nil)
      end
    end
  end

  ctx.say("Done", "title")
  if role == "master" then
    ctx.say("cluster status      overview", nil)
    ctx.say("cluster managers    who has joined", nil)
    ctx.say("cluster pair status pairing window", nil)
  else
    ctx.say("cluster-manager status    check this node", nil)
    ctx.say("Ask the Master operator to run 'cluster managers' to confirm.", nil)
  end
  return true
end

return M
