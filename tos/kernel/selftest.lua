local selftest = {}

selftest.MARKER  = "/etc/selftest.on"
selftest.RESULTS = "/var/selftest.log"
selftest.DIRS    = { "/usr/lib/selftest" }

local fs, computer, log

function selftest.init(deps)
  deps     = deps or {}
  fs       = deps.fs or nil
  computer = deps.computer or nil
  log      = deps.log or { info = function() end, warn = function() end,
                           error = function() end }
  return true
end

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

  if fsMod and fsMod.exists and fsMod.list and fsMod.exists("/mnt") then
    for _, label in ipairs(fsMod.list("/mnt") or {}) do
      local clean = tostring(label):gsub("/$", "")
      if clean ~= "" then add("/mnt/" .. clean) end
    end
  end
  return out
end

function selftest.markerPaths(fsMod)
  fsMod = fsMod or fs
  local out = { selftest.MARKER }
  for _, root in ipairs(mountRoots(fsMod)) do
    out[#out + 1] = root .. "/selftest.on"
    out[#out + 1] = root .. "/selftest/selftest.on"
  end
  return out
end

function selftest.enabled(fsMod)
  fsMod = fsMod or fs
  if not (fsMod and fsMod.exists) then return false end
  for _, p in ipairs(selftest.markerPaths(fsMod)) do
    if fsMod.exists(p) then return true end
  end
  return false
end

function selftest.activeMarker(fsMod)
  fsMod = fsMod or fs
  if not (fsMod and fsMod.exists) then return nil end
  for _, p in ipairs(selftest.markerPaths(fsMod)) do
    if fsMod.exists(p) then return p end
  end
  return nil
end

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

function selftest.discover(fsMod)
  fsMod = fsMod or fs
  local out = {}
  if not (fsMod and fsMod.exists and fsMod.list) then return out end

  local roots = {}
  for _, d in ipairs(selftest.DIRS) do roots[#roots + 1] = d end
  for _, m in ipairs(mountRoots(fsMod)) do
    roots[#roots + 1] = m .. "/selftest"

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
  table.sort(out)
  return out
end

local function makeT(state)
  local t = {}

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

  function t.skip(name, why)
    state.n = state.n + 1
    state.skip = state.skip + 1
    state.skips[#state.skips + 1] = name .. " :: " .. tostring(why or "n/a")
    return true
  end
  return t
end

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

local function appendLine(fsMod, line)
  if not fsMod then return end

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

      appendLine(fsMod, "RUN  " .. short)
      local before = { state.pass, state.fail, state.skip }

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
