-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Diagnostics            ║
-- ╚══════════════════════════════════════╝
-- Health-check unit. Single function `diag.run(report)` walks the
-- system, calling `report(line, severity)` for each finding. The shell
-- `diag` command formats this with colors; cron / scripted callers
-- can pass any collector they want.
--
-- Sections:
--   * memory   — free/total/headroom
--   * disks    — per-mount used/total, low-space warnings
--   * peripherals — count + types, missing critical components
--   * services — rc.d running/stopped/error
--   * users    — locked accounts, failed-attempt counts
--   * log      — recent ERROR/FATAL entries
--   * security — first-boot still set, anchored manifest hash, etc.
--   * trash    — usage vs cap (per-user)

local computer  = require("computer")
local component = require("component")

local diag = {}

local SEVERITY = {
  ok   = "ok",
  info = "info",
  warn = "warn",
  err  = "err",
}
diag.SEVERITY = SEVERITY

-- ============================================================
-- Internal helpers
-- ============================================================

local function fmtBytes(n)
  if n >= 1048576 then return string.format("%.1f MB", n / 1048576) end
  if n >= 1024 then return string.format("%.1f KB", n / 1024) end
  return tostring(n) .. " B"
end

local function pctUsed(total, used)
  if not total or total <= 0 then return 0 end
  return math.floor((used or 0) * 100 / total)
end

-- ============================================================
-- Section runners
-- ============================================================

local function checkMemory(R)
  local total = computer.totalMemory() or 0
  local free  = computer.freeMemory() or 0
  local used  = total - free
  local p     = pctUsed(total, used)
  local sev = "ok"
  if p > 90 then sev = "err"
  elseif p > 75 then sev = "warn" end
  R(string.format("memory: %s used / %s total (%d%%)",
    fmtBytes(used), fmtBytes(total), p), sev)
  -- Free below 16 KB is the OC danger zone where any allocation can
  -- throw out-of-memory.
  if free < 16384 then
    R("  free memory critically low (< 16 KB)", "err")
  end
end

local function checkDisks(R)
  local fs = _G._TOS and _G._TOS.fs
  if not fs or not fs.mounts then
    R("disks: kernel.fs not available", "warn"); return
  end
  local mounts = fs.mounts()
  if not mounts or #mounts == 0 then
    R("disks: no mounts visible", "warn"); return
  end
  R(string.format("disks: %d mount(s)", #mounts), "info")
  -- #FIX (in-game, 2026-08-11) — a read-only root is the single fault
  -- that makes every other diagnosis a lie: everything reports fine and
  -- nothing you do about it persists. It surfaced as "Persist failed"
  -- halfway through the First Boot password prompt, which named neither
  -- the disk nor the cause. `doctor` should lead with it.
  if _G._TOS_ROOT_READONLY then
    R("  ROOT FILESYSTEM IS READ-ONLY — no change made here survives a reboot", "err")
    R("  (users, logs, packages and settings are all discarded; install to a", "err")
    R("   writable drive with install.lua, or unprotect this one)", "err")
  end
  for _, m in ipairs(mounts) do
    local p = pctUsed(m.total, m.used)
    local sev = "ok"
    if p > 95 then sev = "err"
    elseif p > 85 then sev = "warn" end
    R(string.format("  %-16s %s / %s (%d%%)",
      m.mountPoint, fmtBytes(m.used or 0), fmtBytes(m.total or 0), p), sev)
  end
end

local function checkPeripherals(R)
  local counts = {}
  local total = 0
  for _, ctype in component.list() do
    counts[ctype] = (counts[ctype] or 0) + 1
    total = total + 1
  end
  R(string.format("peripherals: %d connected", total), "info")
  -- Sort alphabetically for stable output.
  local types = {}
  for t in pairs(counts) do types[#types + 1] = t end
  table.sort(types)
  for _, t in ipairs(types) do
    R(string.format("  %-22s x %d", t, counts[t]), "ok")
  end
  -- Critical components for a TOS boot:
  if not counts.gpu       then R("  no GPU detected", "err") end
  if not counts.screen    then R("  no screen detected", "err") end
  if not counts.eeprom    then R("  no EEPROM detected (BIOS reflash blocked)", "warn") end
  if not counts.filesystem then R("  no filesystem detected", "err") end
end

local function checkServices(R)
  local rc = _G._TOS and _G._TOS.rc
  if not rc or not rc.list then
    R("services: rc module not available", "info"); return
  end
  local services = rc.list()
  if not services or #services == 0 then
    R("services: none registered", "info"); return
  end
  R(string.format("services: %d registered", #services), "info")
  for _, s in ipairs(services) do
    local sev = s.running and "ok" or "warn"
    R(string.format("  %-20s %s", s.name or "?",
      s.running and "running" or "stopped"), sev)
  end
end

local function checkUsers(R)
  local U = _G._TOS and _G._TOS.users
  if not U or not U.list then
    R("users: user module not available", "warn"); return
  end
  local list = U.list()
  R(string.format("users: %d account(s)", #list), "info")
  local locked, firstBoot = 0, 0
  for _, u in ipairs(list) do
    if u.locked then locked = locked + 1 end
    -- firstBoot may not be in the public projection; query via getUser.
    if U.getUser then
      local rec = U.getUser(u.username)
      if rec and rec.firstBoot then firstBoot = firstBoot + 1 end
    end
  end
  if locked > 0 then
    R("  " .. locked .. " account(s) locked", "warn")
  end
  if firstBoot > 0 then
    R("  " .. firstBoot .. " account(s) still on firstBoot (password unchanged)", "err")
  end
end

local function checkLog(R)
  -- _G._TOS.log is a write-only adapter; the full module is at logObj.
  local log = _G._TOS and _G._TOS.logObj
  if not log or not log.recent then
    R("log: kernel.log not available", "warn"); return
  end
  local recent = log.recent(50)
  local errs, warns = 0, 0
  for _, e in ipairs(recent) do
    if e.level and e.level >= 3 then errs = errs + 1
    elseif e.level == 2 then warns = warns + 1 end
  end
  local sev = "ok"
  if errs > 0 then sev = "err"
  elseif warns > 0 then sev = "warn" end
  R(string.format("log: %d errors, %d warnings in last 50 entries",
    errs, warns), sev)
end

local function checkSecurity(R)
  local U = _G._TOS and _G._TOS.users
  if not U then R("security: users unavailable", "warn"); return end
  -- BIOS-anchored manifest hash (C1). Only meaningful if anchored.
  local kernel = _G._TOS and _G._TOS.kernel
  if kernel and kernel.verifyManifestHash then
    local ok, why = kernel.verifyManifestHash()
    if ok then
      R("security: manifest hash matches EEPROM anchor", "ok")
    elseif why and why:find("no anchored hash") then
      -- Name a command the operator can actually TYPE. This used to say
      -- "run kernel.anchorManifestHash()", which is a kernel function with
      -- no shell surface — advice nobody could follow.
      R("security: manifest hash not anchored in EEPROM " ..
        "(optional hardening — run 'verify anchor' as admin)", "warn")
    else
      R("security: manifest hash MISMATCH — " .. tostring(why), "err")
    end
  end
  -- Trust DB summary.
  local trust = _G._TOS and _G._TOS.net and _G._TOS.net.trust
  if trust and trust.list then
    local peers = trust.list()
    local n = #peers
    R(string.format("security: %d trust-DB peers", n), "info")
  end
end

local function checkNotices(R)
  -- Pending dialog boxes. On a CLI-shell or headless box nothing drains
  -- them, so a queue that only grows is worth surfacing here — it means
  -- some program has been trying to get an operator's attention and
  -- failing.
  local ok, nf = pcall(require, "kernel.notify")
  if not ok or not nf or not nf.depth then return end
  local n = nf.depth()
  if n == 0 then return end
  R(string.format("notices: %d dialog(s) waiting to be shown", n),
    n >= nf.MAX_QUEUE and "warn" or "info")
end

local function checkTrash(R)
  local trash = _G._TOS and _G._TOS.trash
  local U = _G._TOS and _G._TOS.users
  if not trash or not U then return end
  local sess = U.currentSession and U.currentSession() or nil
  if not sess then return end
  local u = trash.usage(sess)
  if not u then return end
  local sev = "ok"
  if u.count > u.max_count * 0.9 then sev = "warn" end
  if u.bytes > u.max_bytes * 0.9 then sev = "warn" end
  R(string.format("trash: %d/%d items, %d/%d bytes",
    u.count, u.max_count, u.bytes, u.max_bytes), sev)
end

local function checkPower(R)
  local tos = _G._TOS or {}
  R(string.format("boot: session #%d", tos.bootCount or 0), "info")
  -- Unsafe-shutdown detection (dirty bit at /var/run/pwrstate).
  if tos.unsafeShutdown then
    R("  last shutdown was UNSAFE (power loss / forced off)", "warn")
  else
    R("  last shutdown clean", "ok")
  end
  -- Preemption watchdog breadcrumb (#REV finding #2): the scheduler
  -- removes this the moment it regains control, so its survival means
  -- the machine died to OC's yield watchdog — and names the culprit.
  local f = tos.fs
  if f and f.exists and f.readFile and f.exists("/var/crash/preempt.txt") then
    local crumb = f.readFile("/var/crash/preempt.txt")
    local head = crumb and crumb:match("^[^\n]*") or "?"
    R("  runaway process before last reboot: " .. head, "warn")
    R("    (details: /var/crash/preempt.txt — delete after reviewing)", "info")
  end
  -- Battery state (tablets only; power.statusString returns nil on AC).
  local pw = tos.power
  if pw and pw.statusString then
    local s = pw.statusString()
    if s then
      local lvl = pw.level and pw.level() or 100
      R("  battery: " .. s, lvl <= 5 and "err" or (lvl <= 15 and "warn" or "ok"))
    end
  end
end

-- ============================================================
-- Public API
-- ============================================================

local SECTIONS = {
  { name = "memory",      fn = checkMemory      },
  { name = "power",       fn = checkPower       },
  { name = "disks",       fn = checkDisks       },
  { name = "peripherals", fn = checkPeripherals },
  { name = "services",    fn = checkServices    },
  { name = "users",       fn = checkUsers       },
  { name = "log",         fn = checkLog         },
  { name = "notices",     fn = checkNotices     },
  { name = "security",    fn = checkSecurity    },
  { name = "trash",       fn = checkTrash       },
}

--- Run every check, calling `report(line, severity)` for each line.
--- Returns an aggregate { ok = N, info = N, warn = N, err = N }.
function diag.run(report, opts)
  opts = opts or {}
  local counts = { ok = 0, info = 0, warn = 0, err = 0 }
  local function R(line, sev)
    sev = sev or "info"
    counts[sev] = (counts[sev] or 0) + 1
    report(line, sev)
  end
  for _, sect in ipairs(SECTIONS) do
    if not opts.only or opts.only == sect.name then
      local ok, err = pcall(sect.fn, R)
      if not ok then
        R(sect.name .. ": check failed: " .. tostring(err), "err")
      end
    end
  end
  return counts
end

return diag
