-- ╔══════════════════════════════════════════════════════════════╗
-- ║  selftest — drive the boot self-test battery from the shell     ║
-- ║                                                                ║
-- ║  The runner is in the base image (tos/kernel/selftest.lua): an  ║
-- ║  ARMED machine runs every check it finds, inside the kernel, at ║
-- ║  the next boot, and writes /var/selftest.log. This command is   ║
-- ║  the operator's side of that: arm and disarm (root), see what   ║
-- ║  would run, and read what happened.                             ║
-- ║                                                                ║
-- ║  It does not RUN checks. Several of them exist to test kernel   ║
-- ║  context before the shell is up; run from here they would be    ║
-- ║  testing a different thing and reporting it as the same one.   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Runs in the package sandbox with fs.read/fs.write. Arming writes
-- /etc/selftest.on, which securefs lets ROOT write and nobody else
-- (users.lua ROOT_WRITE_PATHS): a check runs as the kernel, which is
-- more than an admin holds. A refusal is passed on as securefs words it.

local MARKER   = "/etc/selftest.on"
local RESULTS  = "/var/selftest.log"
local DIRS     = { "/usr/lib/selftest" }   -- kernel/selftest.lua's DIRS

local RED, YELLOW, GREEN, DIM, FG, TITLE = 0xFF5555, 0xFFFF55, 0x55FF55, 0xAAAAAA, 0xFFFFFF, 0x55FFFF

local M = {}

-- ── Marker options, read the way the kernel reads them ─────────────
--! Lenient on purpose, like selftest.readMarker: a typo in the marker
--! must never be what stops a machine from booting.
function M.parseMarker(body)
  local cfg = {}
  for line in tostring(body or ""):gmatch("[^\r\n]+") do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k == "shutdown" or k == "screen" then cfg[k] = (v == "true" or v == "1")
    elseif k == "only" and v ~= "" then cfg[k] = v end
  end
  return cfg
end

--- What `selftest arm` writes. Only the options given are written, so an
--- option a test disk's own marker sets still applies (the machine's
--- marker wins per option, and an absent option is not an override).
function M.markerBody(opts, who)
  local lines = { "# armed by `selftest arm`" .. (who and (" (" .. who .. ")") or "") }
  if opts.shutdown then lines[#lines + 1] = "shutdown=true" end
  if opts.screen then lines[#lines + 1] = "screen=true" end
  if opts.only then lines[#lines + 1] = "only=" .. opts.only end
  return table.concat(lines, "\n") .. "\n"
end

-- ── Discovery, the way kernel/selftest.lua discovers ───────────────
local function mountRoots(F)
  local out, seen = {}, {}
  local function add(p)
    if p and p ~= "" and p ~= "/" and not seen[p] then seen[p] = true; out[#out + 1] = p end
  end
  if F.mounts then
    local ok, list = pcall(F.mounts)
    if ok and type(list) == "table" then
      for _, m in ipairs(list) do add(m.mountPoint) end
    end
  end
  if F.exists("/mnt") then
    for _, label in ipairs(F.list("/mnt") or {}) do
      local clean = tostring(label):gsub("/$", "")
      if clean ~= "" then add("/mnt/" .. clean) end
    end
  end
  return out
end

--- Every check an armed boot would run: { path=, source= }, in run order.
function M.discover(F)
  local roots = {}
  for _, d in ipairs(DIRS) do roots[#roots + 1] = { dir = d, source = "installed" } end
  for _, m in ipairs(mountRoots(F)) do
    -- A selftest/ holding package.lua is this package on an Optional
    -- Utilities disk, not a test disk's checks.
    if not F.exists(m .. "/selftest/package.lua") then
      roots[#roots + 1] = { dir = m .. "/selftest", source = "disk " .. m }
    end
    -- A disk root counts only when the disk says it is a test disk.
    if F.exists(m .. "/selftest.on") then
      roots[#roots + 1] = { dir = m, source = "disk " .. m }
    end
  end
  local out = {}
  for _, r in ipairs(roots) do
    if F.exists(r.dir) then
      for _, entry in ipairs(F.list(r.dir) or {}) do
        local name = tostring(entry):gsub("/$", "")
        if name:match("%.lua$") then
          out[#out + 1] = { path = r.dir .. "/" .. name, name = name, source = r.source }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.path < b.path end)
  return out
end

-- ── The last result ────────────────────────────────────────────────
--- Summarise /var/selftest.log: the BEGIN line, the outcome, and the
--- lines worth reading. A run with no END line STALLED, and the last RUN
--- line names the check it stalled in -- that is the runner's whole
--- stall-detection design (kernel/selftest.lua's header).
--- The runner's lines (tos/kernel/selftest.lua): "RUN  <check>" before
--- each body, "PASS|FAIL <check>  pass=.. fail=.. skip=.." after it (or
--- "FAIL <check> :: <error>"), then every failure name as "  - ", every
--- skip as "  ~ " and every note as "  i ".
function M.summarise(body)
  local s = { fails = {}, skips = {}, notes = {} }
  for line in tostring(body or ""):gmatch("[^\r\n]+") do
    if line:match("^SELFTEST BEGIN") then s.begin = line
    elseif line:match("^SELFTEST END") then s.finish = line
    elseif line:match("^RUN%s") then s.lastRun = line:match("^RUN%s+(.-)%s*$")
    elseif line:match("^FAIL%s") or line:match("^  %- ") then s.fails[#s.fails + 1] = line
    elseif line:match("^  ~ ") then s.skips[#s.skips + 1] = line
    elseif line:match("^  i ") then s.notes[#s.notes + 1] = line end
  end
  if not s.begin then s.state = "none"
  elseif s.finish then s.state = (#s.fails > 0) and "failed" or "passed"
  else s.state = "stalled" end
  return s
end

-- ── The command ────────────────────────────────────────────────────
local TEMPLATE = [[
-- What this checks, and why only a real machine can answer it.
--
-- A check is a file that returns one function. The battery calls it with
-- `t` and records whatever it reports:
--   t.ok(name, cond)            pass when cond is true
--   t.eq(name, expected, got)   the same, naming both values on a failure
--   t.skip(name, why)           cannot run here (no card, no printer):
--                               a skip is never a failure
--   t.note(text)                an observation, kept in the log, no verdict
--   t.cfg.screen                true when the round allows drawing on
--                               the boot console -- ask before you draw
-- It runs INSIDE the kernel, at boot, before the shell: `computer`,
-- `component` and require("kernel.*") are all there. package.loaded is
-- restored after each check, so stub what you like; anything else you
-- change on the machine, put back.
return function(t)
  t.ok("the machine has memory to spare", computer.freeMemory() > 0)
end
]]

local function usage(o)
  o("selftest -- the boot self-test battery", TITLE)
  o("  selftest [status]            armed?  what will run?  how did the last run go?", DIM)
  o("  selftest arm [shutdown] [screen] [only=<prefix>]   run it at the next boot (root)", DIM)
  o("  selftest disarm              stop running it at boot (root)", DIM)
  o("  selftest list                every check an armed boot would run, and where from", DIM)
  o("  selftest log [all]           the last run: failures, skips, notes (all: every line)", DIM)
  o("  selftest template [file]     a starting point for a check of your own", DIM)
end

local function readOr(F, path)
  if not F.exists(path) then return nil end
  local ok, body = pcall(F.readFile, path)
  return ok and body or nil
end

local function status(F, o)
  local armedBody = readOr(F, MARKER)
  if F.exists(MARKER) then
    local cfg = M.parseMarker(armedBody)
    local opts = {}
    if cfg.shutdown then opts[#opts + 1] = "powers off after" end
    if cfg.screen then opts[#opts + 1] = "screen checks on" end
    if cfg.only then opts[#opts + 1] = "only " .. cfg.only .. "*" end
    o("ARMED: the battery runs at the next boot" .. (#opts > 0 and (" (" .. table.concat(opts, ", ") .. ")") or ""), YELLOW)
  else
    o("Not armed: boots run normally.  (selftest arm, as root)", DIM)
  end
  local checks = M.discover(F)
  o(string.format("%d check(s) found.  (selftest list)", #checks), FG)
  local s = M.summarise(readOr(F, RESULTS))
  if s.state == "none" then
    o("No run recorded in " .. RESULTS .. ".", DIM)
  else
    if s.begin then o("Last run: " .. s.begin:gsub("^SELFTEST BEGIN%s*", ""), DIM) end
    if s.state == "stalled" then
      o("STALLED in " .. tostring(s.lastRun or "?") .. " -- the run never finished.", RED)
    else
      o(s.finish:gsub("^SELFTEST END%s*", "Result: "), s.state == "passed" and GREEN or RED)
    end
  end
end

function M.run(args, o, F)
  o = o or print
  F = F or fs
  if type(F) ~= "table" then o("selftest needs the fs capability", RED); return end
  local sub = args[1] or "status"

  if sub == "status" then
    status(F, o)

  elseif sub == "arm" then
    local opts = {}
    for i = 2, #args do
      local a = tostring(args[i])
      if a == "shutdown" or a == "--shutdown" then opts.shutdown = true
      elseif a == "screen" or a == "--screen" then opts.screen = true
      elseif a:match("^%-?%-?only=") then opts.only = a:gsub("^%-?%-?only=", "")
      else o("selftest arm: unknown option '" .. a .. "' -- nothing was changed.", RED); usage(o); return end
    end
    local okW, err = F.writeFile(MARKER, M.markerBody(opts))
    if not okW then
      o("Not armed: " .. tostring(err or "write refused"), RED)
      o("Arming runs code inside the kernel at the next boot, so only root may do it.", DIM)
      return
    end
    o("Armed. The battery runs at the next boot and writes " .. RESULTS .. ".", GREEN)
    if opts.shutdown then o("The machine powers itself off when the run finishes.", YELLOW) end
    o("Disarm with:  selftest disarm", DIM)

  elseif sub == "disarm" then
    if not F.exists(MARKER) then o("Not armed.", DIM); return end
    local okR, err = F.remove(MARKER)
    if not okR then o("Still armed: " .. tostring(err or "remove refused"), RED); return end
    o("Disarmed. Boots run normally.", GREEN)

  elseif sub == "list" then
    local checks = M.discover(F)
    if #checks == 0 then
      o("No checks found. Install them with `pkg install selftest`, or insert a test", DIM)
      o("disk carrying a selftest/ folder.", DIM)
      return
    end
    local only = M.parseMarker(readOr(F, MARKER)).only
    for _, c in ipairs(checks) do
      local skipped = only and c.name:sub(1, #only) ~= only
      o(string.format("  %-24s %s%s", c.name, c.source, skipped and "  (not run: only=" .. only .. ")" or ""),
        skipped and DIM or FG)
    end

  elseif sub == "log" then
    local body = readOr(F, RESULTS)
    if not body or body == "" then o("No run recorded in " .. RESULTS .. ".", DIM); return end
    if args[2] == "all" then
      for line in body:gmatch("[^\r\n]+") do
        o(line, (line:match("^FAIL") or line:match("^  %- ")) and RED
          or line:match("^  ~ ") and YELLOW or FG)
      end
      return
    end
    local s = M.summarise(body)
    if s.begin then o(s.begin, DIM) end
    for _, l in ipairs(s.fails) do o(l, RED) end
    for _, l in ipairs(s.skips) do o(l, YELLOW) end
    for _, l in ipairs(s.notes) do o(l, FG) end
    if s.state == "stalled" then
      o("STALLED in " .. tostring(s.lastRun or "?") .. " -- no SELFTEST END line.", RED)
    elseif s.finish then
      o(s.finish, s.state == "passed" and GREEN or RED)
    end

  elseif sub == "template" then
    if args[2] then
      local okW, err = F.writeFile(args[2], TEMPLATE)
      if not okW then o("Could not write " .. args[2] .. ": " .. tostring(err), RED); return end
      o("Wrote " .. args[2] .. ". Put it in a test disk's selftest/ folder, or ship it in", GREEN)
      o("a package that installs it under /usr/lib/selftest/ (a root install).", DIM)
    else
      for line in TEMPLATE:gmatch("([^\n]*)\n") do o(line, FG) end
    end

  else
    usage(o)
  end
end

M.TEMPLATE = TEMPLATE
return { commands = { selftest = function(args, o) return M.run(args or {}, o) end }, lib = M }
