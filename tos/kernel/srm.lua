local srm = {}

srm.VERSION = 1

srm.DIR        = "/var/srm"
srm.INDEX      = "/var/srm/index.dat"
srm.STORE      = "/var/srm/store"
srm.LAST       = "/var/srm/last.dat"

srm.MAX_STORE_BYTES = 128 * 1024

--! Keep in sync with the F() call sites in bios.lua. The digit is also the
--! number of short beeps SRM Basic emits, so a screenless box is diagnosable
--! by ear; test_bios.lua pins both halves of that contract.
srm.BASIC_CODES = {
  C1 = "CPU architecture is too old — TOS needs a Lua 5.3+ CPU",
  D2 = "no boot device — no /init.lua disk and no TBFS drive was found",
  B3 = "the TBFS boot blob would not compile (raw-drive boot region damaged)",
  K4 = "the kernel was missing — /tos/kernel/init.lua was not on the disk",
  I5 = "/init.lua could not be opened (unreadable or the disk went away)",
  I6 = "/init.lua would not compile (truncated or corrupted write)",
}

local function tryRequire(name)
  local ok, mod = pcall(require, name)
  if ok then return mod end
end

function srm.deps(d)
  d = d or {}
  local TOS = _G._TOS or {}
  local out = {
    fs        = d.fs        or TOS.fs,
    serialize = d.serialize or tryRequire("kernel.serialize"),
    crypto    = d.crypto    or TOS.crypto or tryRequire("kernel.crypto"),
    log       = d.log       or TOS.logObj,
    eeprom    = d.eeprom,
    component = d.component,
  }
  if not out.eeprom then

    local component = out.component or tryRequire("component")
    if component and component.list then
      local ok, addr = pcall(function() return component.list("eeprom")() end)
      if ok and addr then
        local okP, proxy = pcall(component.proxy, addr)
        if okP then out.eeprom = proxy end
      end
    end
  end
  return out
end

local function gc()
  local K = _G._TOS and _G._TOS.kernel
  if K and K.gc then pcall(K.gc); return end
  if type(collectgarbage) == "function" then pcall(collectgarbage, "collect") end
end

--! Cooperative slice between FILES.
--!
--! SRM reads and hashes every file in the manifest. That is the longest
--! job in the OS by a wide margin, and it was the only long job that never
--! yielded -- ten other modules do, including compress, pkg, fs and
--! ed25519. So `srm scan` did not merely run slowly, it FROZE the machine
--! for its whole duration: no other seat drew, no timer fired, nothing.
--! Reported from a real box, and the operator's guess that it might be an
--! outlier rather than just the slowest command was the right one.
--!
--! Between whole files only, never mid-file, so a file is still read and
--! hashed within one resume. yieldCooperative is throttled inside
--! kernel.process (it returns false until the slice is actually spent), so
--! calling it once per file is cheap, and it is a no-op in kernel context
--! and off-box.
--!
--! This matters more here than the freeze alone: OpenComputers kills a
--! machine that goes too long without yielding, and TOS's own preemption
--! cannot save it (see kernel/process.lua -- debug.sethook does not exist
--! on OC). A big enough manifest would take the whole computer down.
--! (test_srm_yields.lua)
local coopProc = nil
local function coopYield()
  if coopProc == nil then
    local okP, m = pcall(require, "kernel.process")
    coopProc = (okP and m and m.yieldCooperative) and m or false
  end
  if coopProc then coopProc.yieldCooperative() end
end

local function newReport(title)
  return {
    title    = title,
    findings = {},
    counts   = { ok = 0, info = 0, warn = 0, err = 0 },
    fixed    = 0,
  }
end
srm.newReport = newReport

local function add(rep, text, sev)
  sev = sev or "info"
  rep.findings[#rep.findings + 1] = { text = text, sev = sev }
  rep.counts[sev] = (rep.counts[sev] or 0) + 1
  return rep
end
srm.add = add

function srm.worst(rep)
  local c = rep and rep.counts or {}
  if (c.err or 0) > 0 then return "err" end
  if (c.warn or 0) > 0 then return "warn" end
  return "ok"
end

function srm.parseFault(data)
  if type(data) ~= "string" then return nil end

  local code = data:match("^SRM:(%S+)") or data:match("\nSRM:(%S+)")
  if not code or code == "" then return nil end
  return code
end

function srm.stripFault(data)
  if type(data) ~= "string" then return "" end
  local out = data:gsub("\nSRM:%S*", ""):gsub("^SRM:%S*\n?", "")
  return out
end

function srm.readFault(deps)
  deps = srm.deps(deps)
  local ep = deps.eeprom
  if not ep or not ep.getData then return nil end
  local ok, data = pcall(ep.getData)
  if not ok then return nil end
  local code = srm.parseFault(data)
  if not code then return nil end
  return {
    code = code,
    why  = srm.BASIC_CODES[code] or "unrecognised SRM Basic code (newer BIOS?)",
  }
end

function srm.clearFault(deps)
  deps = srm.deps(deps)
  local ep = deps.eeprom
  if not ep or not ep.getData or not ep.setData then return false, "no EEPROM" end
  local ok, data = pcall(ep.getData)
  if not ok then return false, "EEPROM unreadable" end
  if not srm.parseFault(data) then return true end
  local okW = pcall(ep.setData, srm.stripFault(data))
  if not okW then return false, "EEPROM write failed" end
  return true
end

local FALLBACK_CRITICAL = {
  "/init.lua",
  "/tos/kernel/init.lua",
  "/tos/kernel/log.lua",
  "/tos/kernel/hal.lua",
  "/tos/kernel/event.lua",
  "/tos/kernel/process.lua",
  "/tos/kernel/fs.lua",
  "/tos/kernel/serialize.lua",
  "/tos/kernel/display.lua",
  "/tos/shell/init.lua",
}

function srm.criticalPaths(deps)
  deps = srm.deps(deps)
  local fs, ser = deps.fs, deps.serialize

  local function fromTableFile(path, pick)
    if not (fs and ser and fs.exists and fs.exists(path)) then return nil end
    local raw = fs.readFile(path)
    if type(raw) ~= "string" then return nil end
    local tbl = ser.decode(raw, { maxBytes = 64 * 1024 })
    if type(tbl) ~= "table" then return nil end
    local out = pick(tbl)
    if type(out) == "table" and #out > 0 then return out end
  end

  local list = fromTableFile("/var/pkg/installed/tos-core/package.lua", function(t)
    local o = {}
    if type(t.critical) == "table" then
      for _, p in ipairs(t.critical) do if type(p) == "string" then o[#o + 1] = p end end
    end
    return o
  end)
  if list then return list, "tos-core/package.lua" end

  list = fromTableFile("/etc/critical.bak", function(t)
    local o = {}
    for _, p in ipairs(t) do if type(p) == "string" then o[#o + 1] = p end end
    return o
  end)
  if list then return list, "critical.bak" end

  local manifest = tryRequire("system_manifest")
  if type(manifest) == "table" then
    local o = {}
    for _, e in ipairs(manifest) do
      if type(e) == "table" and e.critical and type(e.path) == "string" then
        o[#o + 1] = e.path
      end
    end
    if #o > 0 then return o, "system_manifest.lua" end
  end

  return FALLBACK_CRITICAL, "built-in fallback"
end

function srm.storePathFor(path)
  return srm.STORE .. path
end

local function readHashed(deps, path, keep)
  local fs, crypto = deps.fs, deps.crypto
  if not (fs and crypto and crypto.hash) then return nil, "crypto unavailable" end
  local content, err = fs.readFile(path)
  if type(content) ~= "string" then return nil, err or "unreadable" end
  local size = #content
  local ok, hash = pcall(crypto.hash, content)
  if not keep then content = nil; gc() end
  if not ok or type(hash) ~= "string" then return nil, "hash failed" end
  return hash, size, content
end

local function hashFile(deps, path)
  return readHashed(deps, path)
end
srm.hashFile = hashFile

local function writeSafely(fs, path, content)
  if fs.writeFileAtomic then return fs.writeFileAtomic(path, content) end
  return fs.writeFile(path, content)
end

function srm.loadIndex(deps)
  deps = srm.deps(deps)
  local fs, ser = deps.fs, deps.serialize
  if not (fs and ser and fs.exists and fs.exists(srm.INDEX)) then return nil end
  local raw = fs.readFile(srm.INDEX)
  if type(raw) ~= "string" then return nil end
  local idx = ser.decode(raw, { maxBytes = 256 * 1024 })
  if type(idx) ~= "table" or type(idx.files) ~= "table" then return nil end
  return idx
end

local function saveIndex(deps, idx)
  local fs, ser = deps.fs, deps.serialize
  if not (fs and ser) then return false, "fs/serialize unavailable" end
  if fs.makeDirectory and not (fs.exists and fs.exists(srm.DIR)) then
    pcall(fs.makeDirectory, srm.DIR)
  end
  return ser.saveFile(fs, srm.INDEX, idx)
end

function srm.baseline(deps, opts)
  deps = srm.deps(deps)
  opts = opts or {}
  local fs = deps.fs
  if not fs then return false, "no filesystem" end
  if not (deps.crypto and deps.crypto.hash) then return false, "crypto unavailable" end

  local paths, source = opts.paths, "caller"
  if not paths then paths, source = srm.criticalPaths(deps) end

  local idx = {
    version = srm.VERSION,
    created = (os.time and os.time()) or 0,
    boot    = (_G._TOS and _G._TOS.bootCount) or 0,
    content = opts.content and true or false,
    source  = source,
    files   = {},
  }

  local summary = { hashed = 0, stored = 0, skipped = 0, bytes = 0, missing = {},
                    pruned = 0, source = source }

  local prev = srm.loadIndex(deps)

  for _, path in ipairs(paths) do
    coopYield()
    if not (fs.exists and fs.exists(path)) then
      summary.missing[#summary.missing + 1] = path
    else

      local hash, size, content = readHashed(deps, path, opts.content and true or false)
      if not hash then
        summary.skipped = summary.skipped + 1
      else
        local rec = { hash = hash, size = size, stored = false }
        summary.hashed = summary.hashed + 1
        if opts.content then
          if size > srm.MAX_STORE_BYTES then

            summary.skipped = summary.skipped + 1
          elseif content and writeSafely(fs, srm.storePathFor(path), content) then
            rec.stored = true
            summary.stored = summary.stored + 1
            summary.bytes = summary.bytes + size
          else
            summary.skipped = summary.skipped + 1
          end
        end
        content = nil
        gc()
        idx.files[path] = rec
      end
    end
  end

  if prev and type(prev.files) == "table" and fs.remove then
    for path, rec in pairs(prev.files) do
      if rec.stored and not (idx.files[path] and idx.files[path].stored) then
        local sp = srm.storePathFor(path)
        if fs.exists and fs.exists(sp) and pcall(fs.remove, sp) then
          summary.pruned = summary.pruned + 1
        end
      end
    end
  end

  local ok, err = saveIndex(deps, idx)
  if not ok then return false, "could not write the index: " .. tostring(err) end
  if deps.log and deps.log.info then
    deps.log.info("srm", string.format(
      "Baseline captured: %d hashed, %d stored (%d bytes), %d pruned, from %s",
      summary.hashed, summary.stored, summary.bytes, summary.pruned, source))
  end
  return true, summary
end

function srm.scan(deps, opts)
  deps = srm.deps(deps)
  opts = opts or {}
  local rep = newReport("baseline scan")
  rep.drift, rep.missing, rep.unbaselined = {}, {}, {}

  local fs = deps.fs
  if not fs then add(rep, "no filesystem — nothing to scan", "err"); return rep end

  local idx = srm.loadIndex(deps)
  if not idx then
    add(rep, "no baseline captured yet — run 'srm baseline' on a system you trust", "warn")
    return rep
  end

  local paths = {}
  for p in pairs(idx.files) do paths[#paths + 1] = p end
  table.sort(paths)

  add(rep, string.format("baseline: %d file(s), captured from %s%s",
    #paths, tostring(idx.source or "?"),
    idx.content and ", with stored copies" or ", hashes only"), "info")

  for _, path in ipairs(paths) do
    coopYield()
    local rec = idx.files[path]
    if not (fs.exists and fs.exists(path)) then
      rep.missing[#rep.missing + 1] = path
      add(rep, "MISSING  " .. path, "err")
    else
      local hash = hashFile(deps, path)
      if not hash then
        add(rep, "UNREADABLE  " .. path, "err")
        rep.drift[#rep.drift + 1] = path
      elseif hash ~= rec.hash then
        rep.drift[#rep.drift + 1] = path
        add(rep, "CHANGED  " .. path .. "  (baseline " ..
          tostring(rec.hash):sub(1, 12) .. ", now " .. hash:sub(1, 12) .. ")", "err")
      end
    end
  end

  if idx.content and opts.checkStore ~= false then
    local rotted = 0
    for _, path in ipairs(paths) do
      coopYield()
      local rec = idx.files[path]
      if rec.stored then
        local sp = srm.storePathFor(path)
        if not (fs.exists and fs.exists(sp)) then
          rotted = rotted + 1
          add(rep, "store copy gone: " .. path, "warn")
        else
          local sh = hashFile(deps, sp)
          if sh ~= rec.hash then
            rotted = rotted + 1
            add(rep, "store copy is corrupt: " .. path, "warn")
          end
        end
      end
    end
    if rotted == 0 then add(rep, "store: every copy verifies", "ok") end
  end

  local crit = srm.criticalPaths(deps)
  for _, path in ipairs(crit) do
    coopYield()
    if not idx.files[path] then
      rep.unbaselined[#rep.unbaselined + 1] = path
      add(rep, "not in baseline: " .. path .. " (re-run 'srm baseline')", "warn")
    end
  end

  if #rep.missing == 0 and #rep.drift == 0 then
    add(rep, "all baselined files match", "ok")
  else

    add(rep, "", "info")
    add(rep, "Changed files mean one of two things: damage, or an upgrade you", "info")
    add(rep, "meant to install. After a deliberate upgrade, re-run", "info")
    add(rep, "'srm baseline' to bless the new files. Otherwise 'srm repair", "info")
    add(rep, "--restore' puts them back.", "info")
  end
  return rep
end

function srm.restore(deps, opts)
  deps = srm.deps(deps)
  opts = opts or {}
  local rep = newReport("restore")
  local fs = deps.fs
  if not fs then add(rep, "no filesystem", "err"); return rep end

  local idx = srm.loadIndex(deps)
  local targets = opts.paths
  if not targets then
    local scan = srm.scan(deps, { checkStore = false })
    targets = {}
    for _, p in ipairs(scan.missing) do targets[#targets + 1] = p end
    for _, p in ipairs(scan.drift) do targets[#targets + 1] = p end
  end

  if #targets == 0 then
    add(rep, "nothing to restore — no missing or changed files", "ok")
    return rep
  end

  if not idx and not opts.unverified then
    add(rep, "no baseline to verify a restore against.", "err")
    add(rep, "  capture one first ('srm baseline'), or accept an unchecked", "info")
    add(rep, "  copy explicitly with --unverified.", "info")
    return rep
  end

  for _, path in ipairs(targets) do
    coopYield()
    local want = idx and idx.files[path] and idx.files[path].hash or nil
    local candidates = {}

    if idx and idx.files[path] and idx.files[path].stored then
      candidates[#candidates + 1] = { src = srm.storePathFor(path), what = "store" }
    end
    if opts.source then
      candidates[#candidates + 1] = { src = opts.source .. path, what = opts.source }
    end

    if #candidates == 0 then
      add(rep, "no source for " .. path ..
        (idx and " (baseline is hashes-only — pass --source <mount>)" or ""), "err")
    else
      local done = false
      for _, c in ipairs(candidates) do
        if not done and fs.exists and fs.exists(c.src) then

          local hash, _, content = readHashed(deps, c.src, true)
          if want and hash ~= want then
            add(rep, "rejected " .. c.what .. " copy of " .. path ..
              " — hash does not match the baseline", "warn")
          elseif not want and not opts.unverified then
            add(rep, "skipped " .. path .. " — no baseline hash to check against", "warn")
            done = true
          elseif not content then
            add(rep, "unreadable source for " .. path .. " at " .. c.what, "warn")
          else
            local okC, errC = writeSafely(fs, path, content)
            if okC then
              rep.fixed = rep.fixed + 1
              add(rep, "restored " .. path .. " from " .. c.what ..
                (want and " (hash verified)" or " (UNVERIFIED)"),
                want and "ok" or "warn")
            else
              add(rep, "write failed for " .. path .. ": " .. tostring(errC), "err")
            end
            done = true
          end
          content = nil
          gc()
        end
      end
      if not done then
        add(rep, "no usable source for " .. path, "err")
      end
    end
  end

  if deps.log and deps.log.warn and rep.fixed > 0 then
    deps.log.warn("srm", "Restored " .. rep.fixed .. " system file(s) from a verified source")
  end
  return rep
end

function srm.storeUsage(deps)
  deps = srm.deps(deps)
  local idx = srm.loadIndex(deps)
  local out = { files = 0, bytes = 0 }
  if not idx then return out end
  local fs = deps.fs
  for path, rec in pairs(idx.files) do
    if rec.stored then
      out.files = out.files + 1
      local sz = rec.size or 0
      if fs and fs.size then
        local okS, live = pcall(fs.size, srm.storePathFor(path))
        if okS and type(live) == "number" then sz = live end
      end
      out.bytes = out.bytes + sz
    end
  end
  return out
end

function srm.repair(deps, opts)
  deps = srm.deps(deps)
  opts = opts or {}
  local rep = newReport("repair")

  local repairMod = tryRequire("kernel.repair")
  if repairMod and repairMod.run then
    local ok, sub = pcall(repairMod.run, {
      fs = deps.fs, serialize = deps.serialize, log = deps.log,
    })
    if ok and type(sub) == "table" then
      for _, line in ipairs(sub.lines or {}) do

        add(rep, line, line:sub(1, 5) == "WARN:" and "warn" or "info")
      end
      rep.fixed = rep.fixed + (sub.fixed or 0)
    else
      add(rep, "fixer pass failed: " .. tostring(sub), "err")
    end
  else
    add(rep, "kernel.repair unavailable — skipping the fixer pass", "warn")
  end

  if opts.restore then
    local sub = srm.restore(deps, { source = opts.source, unverified = opts.unverified })
    for _, f in ipairs(sub.findings) do add(rep, f.text, f.sev) end
    rep.fixed = rep.fixed + (sub.fixed or 0)
  end

  return rep
end

function srm.parseArgs(args)
  local verb, flags, paths = nil, {}, {}
  local consumed = nil
  for i = 1, #(args or {}) do
    local a = tostring(args[i])
    if i == consumed then
    elseif a:sub(1, 2) == "--" then
      local k, v = a:match("^%-%-([%w%-]+)=?(.*)$")
      if k then
        if v ~= "" then
          flags[k] = v
        elseif k == "source" then
          local nxt = args[i + 1]
          if nxt and tostring(nxt):sub(1, 2) ~= "--" then
            flags.source = tostring(nxt); consumed = i + 1
          else
            flags[k] = true
          end
        else
          flags[k] = true
        end
      end
    elseif not verb then verb = a:lower()
    else paths[#paths + 1] = a end
  end
  return verb or "status", flags, paths
end

function srm.status(deps, opts)
  deps = srm.deps(deps)
  opts = opts or {}
  local rep = newReport("status")

  local fault = srm.readFault(deps)
  if fault then
    add(rep, "LAST BOOT FAILED POST — SRM " .. fault.code, "err")
    add(rep, "  " .. fault.why, "err")
    if opts.clearFault then
      local okC = srm.clearFault(deps)
      add(rep, okC and "  (fault code cleared)" or "  (could not clear the fault code)",
        okC and "info" or "warn")
    else
      add(rep, "  clears automatically on the next successful boot", "info")
    end
  else
    add(rep, "POST: no parked fault from SRM Basic", "ok")
  end

  local TOS = _G._TOS or {}
  if TOS.unsafeShutdown then
    add(rep, "last shutdown was UNSAFE (power loss / forced off)", "warn")
  end

  local idx = srm.loadIndex(deps)
  if not idx then
    add(rep, "no baseline — 'srm baseline' records what a good system looks like", "warn")
  else
    local n = 0
    for _ in pairs(idx.files) do n = n + 1 end
    add(rep, string.format("baseline: %d file(s) from %s (boot #%s)",
      n, tostring(idx.source or "?"), tostring(idx.boot or "?")), "info")
    if idx.content then
      local u = srm.storeUsage(deps)
      add(rep, string.format("store: %d copies, %.1f KB — local repair available",
        u.files, u.bytes / 1024), "ok")
    else
      add(rep, "store: hashes only — repair needs --source <mount>", "info")
    end
  end

  return rep
end

return srm
