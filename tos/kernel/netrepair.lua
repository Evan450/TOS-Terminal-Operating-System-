local netrepair = {}

netrepair.OWNER = "Evan450"
netrepair.REPO  = "TOS-Terminal-Operating-System-"
netrepair.STAGE = "/var/repair"

netrepair.MAX_FILE_BYTES  = 128 * 1024
netrepair.MAX_FILES       = 64
netrepair.SPACE_MARGIN    = 16 * 1024

local function coopYield()
  local P = package.loaded["kernel.process"]
  if P and P.yieldCooperative then pcall(P.yieldCooperative) end
end

function netrepair.deps(d)
  d = d or {}
  local T = rawget(_G, "_TOS") or {}
  d.fs = d.fs or T.fs or package.loaded["kernel.fs"]
  if not d.crypto then
    local ok, c = pcall(require, "kernel.crypto"); d.crypto = ok and c or nil
  end
  if not d.internet then
    local ok, i = pcall(require, "kernel.internet"); d.internet = ok and i or nil
  end
  if d.manifest == nil then
    local ok, m = pcall(require, "system_manifest"); d.manifest = ok and m or nil
  end
  if not d.anchor then
    d.anchor = function()
      local K = T.kernel
      if K and K.verifyManifestHash then return K.verifyManifestHash() end
      return false, "kernel anchor check unavailable"
    end
  end
  if d.build == nil then d.build = T.build end
  d.log = d.log or T.log or package.loaded["kernel.log"]
  return d
end

function netrepair.sourceRef(build, override)
  if type(override) == "string" and override ~= "" then
    return override, "the ref you asked for (" .. override .. ")"
  end
  if type(build) == "string" and build:match("^%x+$") then
    return "build-" .. build, "this machine's own release (build " .. build .. ")"
  end
  return "main", "the latest release -- this machine's build (" .. tostring(build)
    .. ") has no tag of its own, so only files that still match it can be repaired"
end

function netrepair.urlFor(ref, path)
  return string.format("https://raw.githubusercontent.com/%s/%s/%s%s",
    netrepair.OWNER, netrepair.REPO, ref, path)
end

function netrepair.isOperatorState(path)
  return path:sub(1, 5) == "/etc/"
end

function netrepair.damaged(deps)
  deps = netrepair.deps(deps)
  local fs, crypto = deps.fs, deps.crypto
  local damaged, skipped = {}, {}
  for _, e in ipairs(type(deps.manifest) == "table" and deps.manifest or {}) do
    coopYield()
    local p = type(e) == "table" and e.path or nil
    if type(p) == "string" then
      local want = type(e.hash) == "string" and e.hash:lower() or nil
      local reason
      if not fs.exists(p) then
        reason = "missing"
      elseif want then
        local okR, data = pcall(fs.readFile, p)
        if not okR or type(data) ~= "string" then reason = "unreadable"
        elseif crypto.hash(data):lower() ~= want then reason = "changed" end
      end
      if reason then
        if netrepair.isOperatorState(p) then
          skipped[#skipped + 1] = { path = p, why = reason .. "; under /etc, so it is "
            .. "operator state -- put it back with `srm restore` or by hand" }
        elseif not want then
          skipped[#skipped + 1] = { path = p, why = reason .. "; the manifest has no "
            .. "digest for it, so a fetched copy could not be checked" }
        else
          damaged[#damaged + 1] = { path = p, hash = want, reason = reason, critical = e.critical }
        end
      end
    end
  end
  return damaged, skipped
end

function netrepair.trustManifest(deps, opts)
  opts = opts or {}
  if type(deps.manifest) ~= "table" or #deps.manifest == 0 then
    return false, "the system manifest is missing or unreadable, so there is nothing to check a "
      .. "fetched file against. Reinstall from the network installer or install media."
  end
  local okA, why = deps.anchor()
  if okA then return true, "the manifest matches its EEPROM anchor" end
  why = tostring(why or "")
  if why:find("no anchored hash", 1, true) then
    if opts.unanchored then
      return true, "the manifest is NOT anchored in the EEPROM; trusting it because "
        .. "--unanchored was given"
    end
    return false, "the manifest is not anchored in the EEPROM, so a tampered one could not be "
      .. "told apart. Anchor it with `verify anchor` if you trust it, or pass --unanchored to "
      .. "accept it for this repair."
  end
  return false, "the manifest failed its EEPROM anchor (" .. why .. "). It is the thing that "
    .. "says what correct looks like, and it is in doubt: online repair will not trust it."
end

local function newReport()
  return { lines = {}, fixed = 0, staged = 0, rejected = 0, ok = false }
end
local function say(rep, text, sev) rep.lines[#rep.lines + 1] = { text = text, sev = sev or "info" } end

function netrepair.plan(deps, opts)
  deps = netrepair.deps(deps)
  opts = opts or {}
  local rep = newReport()
  local okT, why = netrepair.trustManifest(deps, opts)
  rep.trusted = okT
  say(rep, why, okT and "ok" or "err")
  local damaged, skipped = netrepair.damaged(deps)
  rep.damaged, rep.skipped = damaged, skipped
  local ref, refWhy = netrepair.sourceRef(deps.build, opts.ref)
  rep.ref = ref
  if #damaged == 0 then
    say(rep, "every system file with a digest matches it -- nothing to repair online", "ok")
  else
    say(rep, string.format("%d file(s) fail their digest; source: %s", #damaged, refWhy), "info")
    for _, d in ipairs(damaged) do
      say(rep, string.format("  %-8s %s", d.reason:upper(), d.path), "warn")
    end
  end
  for _, s in ipairs(skipped) do say(rep, "  not touched: " .. s.path .. " (" .. s.why .. ")", "info") end
  rep.ok = okT
  return rep
end

local function freeSpace(fs, path)
  if fs.spaceFree then
    local ok, n = pcall(fs.spaceFree, path or "/")
    if ok and type(n) == "number" then return n end
  end
  return nil
end

local function cleanStage(fs)
  pcall(fs.remove, netrepair.STAGE)
end

function netrepair.run(deps, opts)
  deps = netrepair.deps(deps)
  opts = opts or {}
  local rep = netrepair.plan(deps, opts)
  if not opts.apply then
    if #rep.damaged > 0 and rep.trusted then
      say(rep, "Dry run: nothing was fetched or changed. Add --apply to repair.", "info")
    end
    return rep
  end
  rep.ok = false
  if not rep.trusted then say(rep, "Nothing was changed.", "err"); return rep end
  if #rep.damaged == 0 then rep.ok = true; return rep end
  if #rep.damaged > netrepair.MAX_FILES then
    say(rep, string.format("%d files are broken -- more than the %d an online repair will "
      .. "take on. That is a reinstall, not a repair.", #rep.damaged, netrepair.MAX_FILES), "err")
    return rep
  end
  local net = deps.internet
  if not (net and net.available and net.available()) then
    local st = net and net.status and net.status() or {}
    say(rep, "No usable internet card: " .. tostring(st.reason or "the internet module is "
      .. "unavailable") .. ". Nothing was changed.", "err")
    return rep
  end

  local fs = deps.fs
  cleanStage(fs)
  local staged = {}
  for _, d in ipairs(rep.damaged) do
    coopYield()
    local free = freeSpace(fs, netrepair.STAGE)
    if free and free < netrepair.MAX_FILE_BYTES + netrepair.SPACE_MARGIN then
      cleanStage(fs)
      say(rep, string.format("Not enough free disk to stage the next file (%d KB free). "
        .. "Nothing was changed.", math.floor(free / 1024)), "err")
      return rep
    end
    local dest = netrepair.STAGE .. d.path
    local parent = dest:match("^(.*)/[^/]+$")
    if parent and fs.makeDirectory then pcall(fs.makeDirectory, parent) end
    local url = netrepair.urlFor(rep.ref, d.path)
    local okD, err = net.download(url, dest, { fs = fs, maxBytes = netrepair.MAX_FILE_BYTES })
    if not okD then
      cleanStage(fs)
      say(rep, "Could not fetch " .. d.path .. ": " .. tostring(err) .. ". Nothing was changed.", "err")
      return rep
    end
    local data = fs.readFile(dest)
    if type(data) == "string" and deps.crypto.hash(data):lower() == d.hash then
      staged[#staged + 1] = { item = d, path = dest }
      rep.staged = rep.staged + 1
    else
      rep.rejected = rep.rejected + 1
      say(rep, "REJECTED the fetched " .. d.path .. ": it does not match this machine's "
        .. "manifest" .. (rep.ref == "main" and " (the published release has probably moved on)"
        or ""), "warn")
      pcall(fs.remove, dest)
    end
    data = nil
  end

  for _, s in ipairs(staged) do
    coopYield()
    local data = fs.readFile(s.path)

    if type(data) == "string" and deps.crypto.hash(data):lower() == s.item.hash then
      local write = fs.writeFileAtomic or fs.writeFile
      local okW, errW = write(s.item.path, data)
      if okW then
        rep.fixed = rep.fixed + 1
        say(rep, "repaired " .. s.item.path .. " (" .. s.item.reason .. ", digest verified)", "ok")
        if deps.log and deps.log.warn then
          deps.log.warn("netrepair", "Replaced " .. s.item.path .. " from " .. rep.ref
            .. " (" .. s.item.reason .. ", digest verified)")
        end
      else
        say(rep, "could not write " .. s.item.path .. ": " .. tostring(errW), "err")
      end
    else
      say(rep, "the staged copy of " .. s.item.path .. " changed before it was written; "
        .. "left alone", "err")
    end
  end
  cleanStage(fs)
  rep.ok = (rep.rejected == 0) and (rep.fixed == #rep.damaged)
  if rep.fixed > 0 then
    say(rep, "If you keep an SRM baseline, take it again ('srm baseline') so it "
      .. "describes the repaired files.", "info")
  end
  return rep
end

return netrepair
