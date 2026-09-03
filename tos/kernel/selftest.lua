-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - selftest (in-emulator boot battery)         ║
-- ║                                                            ║
-- ║  Runs checks INSIDE a booted TOS on real OpenComputers,    ║
-- ║  against the real kernel, the real GPU and the real        ║
-- ║  filesystem — the one class of failure the off-box suite   ║
-- ║  structurally cannot see. Hundreds of tests in             ║
-- ║  usr/lib/tests/ are pure Lua with stubbed modules, and     ║
-- ║  not one of them catches "the kernel does not actually     ║
-- ║  boot on a T1", or "gpu.fill ignored the background we     ║
-- ║  thought we set".                                          ║
-- ║                                                            ║
-- ║  Shape is TODO.txt's (2026-08-10), followed as written:    ║
-- ║  gated on a marker file so its bytecode never loads on a   ║
-- ║  production boot, and reporting pass / fail / STALLED —    ║
-- ║  because a hung boot is the failure mode that matters      ║
-- ║  most and it is not a nonzero result, it is no result.     ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- ── HOW A STALL IS CAUGHT ───────────────────────────────────────────
-- Every check writes `RUN <name>` to the results file and FLUSHES IT
-- BEFORE the check body executes. If the machine wedges, the file's
-- last line names the check that wedged it, and there is no
-- `SELFTEST END`. That is the entire mechanism, and it is why results
-- are appended line-by-line rather than buffered and written once: a
-- buffered report is exactly the report you do not get from a hang.
--
-- ── WHERE THE RESULTS GO ────────────────────────────────────────────
-- /var/selftest.log, beside kernel.log. On Ocelot and ocvm the machine's
-- filesystem is an ordinary host directory, so the host reads the file
-- directly — no exit code, no serial port, no screen scraping. That is
-- also how kernel.log is already read during a debugging round.

local selftest = {}

selftest.MARKER  = "/etc/selftest.on"
selftest.RESULTS = "/var/selftest.log"
selftest.DIRS    = { "/usr/lib/selftest" }   -- plus every /mnt/*/selftest

-- Injected so the pure parts are testable off-box.
local fs, computer, log

function selftest.init(deps)
  deps     = deps or {}
  fs       = deps.fs or nil
  computer = deps.computer or nil
  log      = deps.log or { info = function() end, warn = function() end,
                           error = function() end }
  return true
end

-- ============================================================
-- Mount points
-- ============================================================

--- Every mounted filesystem root.
---
--- MUST come from fs.mounts(), not from listing /mnt. A disk mounted by
--- the KERNEL at boot is a VIRTUAL mount point: fs.mount records it in
--- the mount table but never creates a real /mnt/<label> directory. So
--- fs.exists("/mnt") is false, fs.list("/mnt") is empty, and `cd /mnt`
--- answers "Not a directory" while `cd /mnt/disk_a5b2` works fine.
---
--- kernel/pkg.lua's mountedRepoRoots already documents this exact trap,
--- having been caught by it once. This module walked straight into it
--- anyway: discovery listed /mnt, found nothing, and the battery could
--- not see a test disk that was sitting right there with the checks and
--- the marker on it. Every attempted round was blocked by this.
local function mountRoots(fsMod)
  local out, seen = {}, {}
  local function add(p)
    if p and p ~= "" and p ~= "/" and not seen[p] then
      seen[p] = true; out[#out + 1] = p
    end
  end
  if fsMod and fsMod.mounts then
    local ok, list = pcall(fsMod.mounts)
    if ok and type(list) == "table" then
      for _, m in ipairs(list) do add(m.mountPoint) end
    end
  end
  -- A real /mnt subdirectory (an operator-made mount) still counts.
  if fsMod and fsMod.exists and fsMod.list and fsMod.exists("/mnt") then
    for _, label in ipairs(fsMod.list("/mnt") or {}) do
      local clean = tostring(label):gsub("/$", "")
      if clean ~= "" then add("/mnt/" .. clean) end
    end
  end
  return out
end

-- ============================================================
-- Gate
-- ============================================================

--- Every place a marker may live, in priority order.
---
--- /etc is securefs-PROTECTED. `echo > /etc/selftest.on` is denied, and
--- the first real round found exactly that -- the shell reported the
--- write as fine, no file appeared, and the battery never ran. /etc
--- gained a WRITE_PROTECTED_EXEMPT entry so the documented procedure
--- works, but a marker that needs an exemption to create is a bad
--- marker.
---
--- So the DISK arms it. Drop selftest.on beside the checks and inserting
--- the disk is the entire procedure: no protected write, no root shell,
--- and the disk that carries the checks is the disk that says "run
--- them", which is one fact instead of two that can disagree.
function selftest.markerPaths(fsMod)
  fsMod = fsMod or fs
  local out = { selftest.MARKER }
  for _, root in ipairs(mountRoots(fsMod)) do
    out[#out + 1] = root .. "/selftest.on"
    out[#out + 1] = root .. "/selftest/selftest.on"
  end
  return out
end

--- Is the battery armed? Absent marker means this module is never even
--- required, so a production image pays nothing for shipping it.
function selftest.enabled(fsMod)
  fsMod = fsMod or fs
  if not (fsMod and fsMod.exists) then return false end
  for _, p in ipairs(selftest.markerPaths(fsMod)) do
    if fsMod.exists(p) then return true end
  end
  return false
end

--- Which marker actually armed it, or nil.
function selftest.activeMarker(fsMod)
  fsMod = fsMod or fs
  if not (fsMod and fsMod.exists) then return nil end
  for _, p in ipairs(selftest.markerPaths(fsMod)) do
    if fsMod.exists(p) then return p end
  end
  return nil
end

--- Marker contents are optional config, parsed leniently: a machine
--- that boots the battery must not fail to boot because the marker had
--- a typo in it.
---   shutdown=true   power off when the run finishes (for CI)
---   only=<prefix>   run only checks whose name starts with this
---   screen=true     allow checks that DRAW on the boot console
---
--- `screen` is off by default because the console is a scrolling log
--- and the battery logs while it runs, so a drawing check cannot win:
--- a row saved at one moment shows different content two seconds later,
--- and restoring it puts stale text back. Save/restore cannot beat a
--- race against the log. Turning the screen checks on is choosing to
--- accept a messy console for the round, which is a fair trade when
--- they are the ones answering the question.
function selftest.readMarker(fsMod)
  fsMod = fsMod or fs
  local cfg = { shutdown = false, only = nil, screen = false }
  local marker = selftest.activeMarker(fsMod)
  if not marker then return cfg end
  local body = fsMod.readFile and fsMod.readFile(marker) or ""
  for line in tostring(body or ""):gmatch("[^\r\n]+") do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k == "shutdown" then cfg.shutdown = (v == "true" or v == "1")
    elseif k == "screen" then cfg.screen = (v == "true" or v == "1")
    elseif k == "only" and v ~= "" then cfg.only = v end
  end
  return cfg
end

-- ============================================================
-- Discovery
-- ============================================================

--- Check files live on a TEST DISK, not in the base image: the runner is
--- small enough to ship dormant, but a battery of checks is not. Any
--- mounted /mnt/<label>/selftest/ is searched, so inserting the disk is
--- the whole install step.
function selftest.discover(fsMod)
  fsMod = fsMod or fs
  local out = {}
  if not (fsMod and fsMod.exists and fsMod.list) then return out end

  local roots = {}
  for _, d in ipairs(selftest.DIRS) do roots[#roots + 1] = d end
  for _, m in ipairs(mountRoots(fsMod)) do
    roots[#roots + 1] = m .. "/selftest"
    -- Checks loose at a disk ROOT are accepted too -- requiring the
    -- folder is a rule nobody can see from the disk, and getting it
    -- wrong looks exactly like the battery being broken.
    --
    -- But ONLY when that disk carries selftest.on at its own root, which
    -- is the disk declaring itself a test disk. Without that condition
    -- this would scan EVERY mount, and the boot disk's root holds
    -- init.lua, bios.lua and install.lua -- loading those as "checks"
    -- during boot is a far worse outcome than a battery that does not
    -- start.
    if fsMod.exists(m .. "/selftest.on") then
      roots[#roots + 1] = m
    end
  end

  for _, root in ipairs(roots) do
    if fsMod.exists(root) then
      for _, entry in ipairs(fsMod.list(root) or {}) do
        local name = tostring(entry):gsub("/$", "")
        if name:match("%.lua$") then out[#out + 1] = root .. "/" .. name end
      end
    end
  end
  table.sort(out)   -- deterministic order, so a stall is reproducible
  return out
end

-- ============================================================
-- The check API handed to each file
-- ============================================================

local function makeT(state)
  local t = {}
  -- Checks can read the marker's options. `t.cfg.screen` is the one
  -- that matters: a check that paints the console must ask first.
  t.cfg = state.cfg or {}
  function t.ok(name, cond)
    state.n = state.n + 1
    if cond then state.pass = state.pass + 1
    else state.fail = state.fail + 1
      state.failures[#state.failures + 1] = name end
    return cond and true or false
  end
  function t.eq(name, expected, actual)
    local same = (expected == actual)
    if not same then
      name = name .. " (expected " .. tostring(expected)
           .. ", got " .. tostring(actual) .. ")"
    end
    return t.ok(name, same)
  end
  -- A check that cannot run here (no printer, no second GPU) SKIPS
  -- rather than fails. A skip that reads as a failure trains people to
  -- ignore failures.
  function t.skip(name, why)
    state.n = state.n + 1
    state.skip = state.skip + 1
    state.skips[#state.skips + 1] = name .. " :: " .. tostring(why or "n/a")
    return true
  end
  return t
end

-- ============================================================
-- Isolation
-- ============================================================

--- A check running inside a LIVE system can do real damage: stubbing
--- package.loaded["kernel.fs"] the way the off-box tests freely do would
--- break the machine it is running on. Snapshot the module table before
--- each check and restore it after, so a check can stub whatever it
--- likes without the next check — or the shell — inheriting it.
local function withIsolatedModules(fn)
  local snapshot = {}
  for k, v in pairs(package.loaded) do snapshot[k] = v end
  local ok, err = pcall(fn)
  for k in pairs(package.loaded) do
    if snapshot[k] == nil then package.loaded[k] = nil end
  end
  for k, v in pairs(snapshot) do package.loaded[k] = v end
  return ok, err
end

-- ============================================================
-- The run
-- ============================================================

local function appendLine(fsMod, line)
  if not fsMod then return end
  -- Append, never buffer. See the stall note in the header.
  if fsMod.appendFile then pcall(fsMod.appendFile, selftest.RESULTS, line .. "\n")
  elseif fsMod.writeFile then
    local prev = (fsMod.readFile and fsMod.readFile(selftest.RESULTS)) or ""
    pcall(fsMod.writeFile, selftest.RESULTS, prev .. line .. "\n")
  end
end

function selftest.run(opts)
  opts = opts or {}
  local fsMod = opts.fs or fs
  local comp  = opts.computer or computer
  local cfg   = opts.cfg or selftest.readMarker(fsMod)
  local files = opts.files or selftest.discover(fsMod)

  local state = { n = 0, pass = 0, fail = 0, skip = 0, failures = {}, skips = {},
                  cfg = cfg }
  local t = makeT(state)
  local started = comp and comp.uptime() or 0

  -- Fresh file each run; a stale previous result read as a current one
  -- is worse than no result.
  if fsMod and fsMod.writeFile then pcall(fsMod.writeFile, selftest.RESULTS, "") end
  appendLine(fsMod, string.format("SELFTEST BEGIN at=%.1f files=%d", started, #files))
  if comp and comp.freeMemory then
    appendLine(fsMod, string.format("ENV mem_free=%dK", math.floor(comp.freeMemory() / 1024)))
  end

  for _, path in ipairs(files) do
    local short = path:match("([^/]+)%.lua$") or path
    if cfg.only and short:sub(1, #cfg.only) ~= cfg.only then
      appendLine(fsMod, "SKIPFILE " .. short)
    else
      -- BEFORE the body runs. This line is the stall report.
      appendLine(fsMod, "RUN  " .. short)
      local before = { state.pass, state.fail, state.skip }
      -- Read + load(), never loadfile().
      --
      -- loadfile is a stdlib function backed by io, and OpenComputers
      -- does not provide io in the kernel environment -- it is simply
      -- nil. The first real round proved it: all seven checks failed
      -- with "could not load: attempt to call a nil value", which is
      -- pcall reporting an attempt to CALL loadfile itself. Every module
      -- in this tree that loads Lua from disk (pkg, rc, cron, sandbox)
      -- reads the source and calls load(); this now does the same.
      --
      -- A missing file and a syntax error are reported separately: they
      -- have completely different fixes and "could not load" covering
      -- both is how the first round cost a boot to diagnose.
      local src = fsMod and fsMod.readFile and fsMod.readFile(path)
      local chunk, lerr
      if type(src) ~= "string" or src == "" then
        lerr = "unreadable or empty"
      else
        chunk, lerr = load(src, "=" .. path, "t")
      end
      if not chunk then
        state.fail = state.fail + 1
        appendLine(fsMod, "FAIL " .. short .. " :: could not load: " .. tostring(lerr))
      else
        local okRun, err = withIsolatedModules(function()
          local mod = chunk()
          if type(mod) == "function" then mod(t)
          elseif type(mod) == "table" and type(mod.run) == "function" then mod.run(t)
          else error("check file returned neither a function nor { run = f }", 0) end
        end)
        if not okRun then
          state.fail = state.fail + 1
          appendLine(fsMod, "FAIL " .. short .. " :: " .. tostring(err))
        else
          local dp = state.pass - before[1]
          local df = state.fail - before[2]
          local ds = state.skip - before[3]
          appendLine(fsMod, string.format("%s %s  pass=%d fail=%d skip=%d",
            df > 0 and "FAIL" or "PASS", short, dp, df, ds))
        end
      end
    end
  end

  for _, f in ipairs(state.failures) do appendLine(fsMod, "  - " .. f) end
  for _, s in ipairs(state.skips)    do appendLine(fsMod, "  ~ " .. s) end

  local dur = (comp and comp.uptime() or 0) - started
  appendLine(fsMod, string.format(
    "SELFTEST END pass=%d fail=%d skip=%d checks=%d secs=%.1f",
    state.pass, state.fail, state.skip, state.n, dur))

  if log and log.info then
    log.info("selftest", string.format("battery: %d passed, %d failed, %d skipped",
      state.pass, state.fail, state.skip))
  end

  if cfg.shutdown and comp and comp.shutdown then
    appendLine(fsMod, "SHUTDOWN requested by marker")
    -- Go through the REAL shutdown path when it's reachable, not a raw
    -- computer.shutdown(). kernel.shutdown (tos/kernel/init.lua) stamps
    -- /var/run/pwrstate "C" (clean) as its last persistent act before
    -- powering off; a raw computer.shutdown() skips that entirely, so
    -- the marker is left reading "R" (running) from boot start. Found on
    -- the first real round to use shutdown=true: every armed battery
    -- powered the machine off "successfully" and then reported its OWN
    -- shutdown as unsafe (warning + beeps) on the very next boot. A
    -- battery whose own exit path corrupts the signal it exists to keep
    -- trustworthy is worse than not shutting down at all.
    --
    -- By the time this runs, _G._TOS.kernel is always set (selftest
    -- only ever runs from inside kernel.boot(), well after that
    -- assignment) — except in the off-box harness, which has no kernel
    -- table at all, so the raw fallback below is what keeps this
    -- testable without a full boot.
    local kernelShutdown = _G._TOS and _G._TOS.kernel and _G._TOS.kernel.shutdown
    if type(kernelShutdown) == "function" then
      pcall(kernelShutdown, false)
    else
      pcall(comp.shutdown, false)
    end
  end

  return state
end

selftest._internal = {
  makeT = makeT,
  withIsolatedModules = withIsolatedModules,
}

return selftest
