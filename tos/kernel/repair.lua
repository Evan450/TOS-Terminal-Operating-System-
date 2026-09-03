-- ╔═══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Self-repair (one-shot boot pass)            ║
-- ║                                                           ║
-- ║  Requested from Boot Settings ("Self-repair next boot")   ║
-- ║  or `bootsettings repair on`. Runs VERY early in kernel   ║
-- ║  boot — right after the filesystem is up, before configs/ ║
-- ║  users/services consume the files it fixes — and exactly  ║
-- ║  once: the kernel clears the flag before running, so a    ║
-- ║  crashing repair can never loop.                          ║
-- ║                                                           ║
-- ║  Philosophy: FIX what is mechanically safe to fix         ║
-- ║  (interrupted writes, stale runtime state, oversized      ║
-- ║  logs, a corrupt boot.cfg — which already fail-safes to   ║
-- ║  defaults anyway), and only REPORT what isn't (a corrupt  ║
-- ║  users.dat is a warning, never an auto-quarantine — the   ║
-- ║  wrong "fix" there locks every operator out).             ║
-- ║                                                           ║
-- ║  Everything goes through injected deps {fs, serialize},   ║
-- ║  so the whole pass is unit-testable off-box and each      ║
-- ║  step is pcall'd — repair must never block boot.          ║
-- ╚═══════════════════════════════════════════════════════════╝

local repair = {}

-- Files whose half-finished atomic writes we sweep (mirrors the boot
-- recoverAtomic set) and whose syntax we sanity-check.
local CRITICAL_STATE = {
  "/etc/users.dat", "/etc/trust.dat", "/etc/tos.cfg",
  "/etc/cron.db", "/etc/critical.bak",
}

-- Runtime files under /var/run are per-session state; everything except
-- the power-state marker is stale by definition at boot time.
local RUN_KEEP = { pwrstate = true }

local LOG_DIR   = "/var/log"
local LOG_MAX   = 32 * 1024   -- trim any log file larger than this...
local LOG_KEEP  = 16 * 1024   -- ...down to its last this-many bytes

--- Run the whole pass. deps = { fs, serialize, log? }.
--- @return { fixed = N, warned = N, lines = { "...", ... } }
function repair.run(deps)
  local fs = deps and deps.fs
  local serialize = deps and deps.serialize
  local rep = { fixed = 0, warned = 0, lines = {} }
  local function line(s) rep.lines[#rep.lines + 1] = s end
  local function fixed(s) rep.fixed = rep.fixed + 1; line(s) end
  local function warn(s) rep.warned = rep.warned + 1; line("WARN: " .. s) end
  if not fs then
    warn("no filesystem module — nothing repairable")
    return rep
  end

  -- ── 1. Finish interrupted atomic writes ─────────────────
  -- (Boot already swept these once; re-sweeping is idempotent and covers
  -- a crash BETWEEN that sweep and this pass.)
  pcall(function()
    if fs.recoverAtomic then
      local n = fs.recoverAtomic(CRITICAL_STATE)
      if n and n > 0 then
        fixed("finished " .. n .. " interrupted critical write(s)")
      else
        line("atomic writes: clean")
      end
    end
  end)

  -- ── 2. Orphaned atomic temp files ────────────────────────
  -- recoverAtomic only knows the critical list; sweep the common state
  -- dirs for leftover *.tos-tmp from OTHER interrupted writes. The
  -- original file (if any) is intact — the temp is garbage by contract
  -- (rename is the commit point), so removing it is always safe.
  pcall(function()
    local removed = 0
    for _, dir in ipairs({ "/etc", "/var", "/var/lib", "/var/pkg", "/home" }) do
      local ok, names = pcall(fs.list, dir)
      if ok and type(names) == "table" then
        for _, name in ipairs(names) do
          local clean = name:gsub("/$", "")
          if clean:sub(-8) == ".tos-tmp" then
            if pcall(fs.remove, dir .. "/" .. clean) then removed = removed + 1 end
          end
        end
      end
    end
    if removed > 0 then fixed("removed " .. removed .. " orphaned temp file(s)")
    else line("temp files: clean") end
  end)

  -- ── 3. boot.cfg syntax ───────────────────────────────────
  -- bootcfg.load already fail-safes a corrupt file to defaults at every
  -- boot; repair goes one further and REWRITES it clean so the corruption
  -- stops being re-reported forever.
  pcall(function()
    local okB, bootcfg = pcall(require, "kernel.bootcfg")
    if not (okB and bootcfg) then return end
    local path = bootcfg.PATH or "/etc/boot.cfg"
    if not fs.exists(path) then line("boot.cfg: absent (defaults)") return end
    local raw = fs.readFile(path)
    local parsed = nil
    if serialize and serialize.decode and type(raw) == "string" then
      parsed = serialize.decode(raw, { maxBytes = 8192 })
    end
    if type(parsed) == "table" then
      line("boot.cfg: OK")
    else
      local cfg = bootcfg.load(fs)   -- fail-safe defaults + whatever survived
      if bootcfg.save(fs, cfg) then
        fixed("rewrote corrupt /etc/boot.cfg (normalized)")
      else
        warn("/etc/boot.cfg is corrupt and could not be rewritten")
      end
    end
  end)

  -- ── 4. Critical state syntax (report-only) ───────────────
  -- These are load-bearing (accounts, trust, config): a corrupt one is
  -- surfaced loudly but NEVER auto-replaced — the wrong fix locks
  -- operators out. Each subsystem has its own fail-safe path.
  pcall(function()
    if not (serialize and serialize.decode) then return end
    for _, path in ipairs(CRITICAL_STATE) do
      if path ~= "/etc/boot.cfg" and fs.exists(path) then
        local raw = fs.readFile(path)
        local parsed = type(raw) == "string"
          and serialize.decode(raw, { maxBytes = 512 * 1024 }) or nil
        if type(parsed) ~= "table" then
          warn(path .. " does not parse — inspect/restore it manually")
        end
      end
    end
    line("critical state: checked")
  end)

  -- ── 5. Stale runtime state ───────────────────────────────
  pcall(function()
    local removed = 0
    local ok, names = pcall(fs.list, "/var/run")
    if ok and type(names) == "table" then
      for _, name in ipairs(names) do
        local clean = name:gsub("/$", "")
        if not RUN_KEEP[clean] then
          if pcall(fs.remove, "/var/run/" .. clean) then removed = removed + 1 end
        end
      end
    end
    if removed > 0 then fixed("cleared " .. removed .. " stale runtime file(s) from /var/run")
    else line("/var/run: clean") end
  end)

  -- ── 6. Oversized logs ────────────────────────────────────
  -- Rotation normally handles this; repair catches a log that grew past
  -- the cap while rotation was broken (or before a crash). Keeps the
  -- TAIL — the newest entries are the ones that explain the problem.
  pcall(function()
    local trimmed = 0
    local ok, names = pcall(fs.list, LOG_DIR)
    if ok and type(names) == "table" then
      for _, name in ipairs(names) do
        local clean = name:gsub("/$", "")
        local path = LOG_DIR .. "/" .. clean
        local okS, size = pcall(fs.size, path)
        if okS and type(size) == "number" and size > LOG_MAX then
          local raw = fs.readFile(path)
          if type(raw) == "string" then
            local tail = raw:sub(-LOG_KEEP)
            -- Start at a line boundary so the first kept entry is whole.
            local nl = tail:find("\n", 1, true)
            if nl then tail = tail:sub(nl + 1) end
            local writer = fs.writeFileAtomic or fs.writeFile
            if writer(path, "[trimmed by self-repair]\n" .. tail) then
              trimmed = trimmed + 1
            end
          end
        end
      end
    end
    if trimmed > 0 then fixed("trimmed " .. trimmed .. " oversized log(s)")
    else line("logs: within limits") end
  end)

  -- ── 7. Boot-critical files present? (report-only) ────────
  pcall(function()
    if not (serialize and serialize.decode) then return end
    if not fs.exists("/etc/critical.bak") then
      line("critical.bak: absent (resyncs at boot)")
      return
    end
    local raw = fs.readFile("/etc/critical.bak")
    local list = type(raw) == "string"
      and serialize.decode(raw, { maxBytes = 64 * 1024 }) or nil
    if type(list) ~= "table" then return end   -- step 4 already warned
    local missing = 0
    for _, p in ipairs(list) do
      if type(p) == "string" and not fs.exists(p) then
        missing = missing + 1
        warn("missing critical file: " .. p)
      end
    end
    if missing == 0 then line("critical files: all present") end
  end)

  return rep
end

return repair
