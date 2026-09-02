local sandbox = {}

local KERNEL_MODULE_PREFIX = "kernel."

local ALLOWED_MODULE_PREFIXES = {
  "compat.",
  "shell.ext",
  "peripheral.",
}

local ALLOWED_MODULE_NAMES = {
  compat        = true,
  ["shell.ext"] = true,

  ["shell.keys"] = true,
}

local BLOCKED_MODULE_NAMES = {

  ["debug"]                   = true,
  ["package"]                 = true,
  ["os"]                      = true,
  ["io"]                      = true,
  ["component"]               = true,
  ["computer"]                = true,
  ["filesystem"]              = true,
  ["shell.init"]              = true,
  ["shell.panels.init"]       = true,
  ["shell.panels.commands"]   = true,
  ["shell.panels.events"]     = true,
  ["shell.panels.executor"]   = true,
  ["shell.panels.state"]      = true,
  ["shell.panels.draw"]       = true,
  ["shell.panels.helpers"]    = true,
  ["shell.panels.filebrowser"] = true,
  ["shell.panels.editor"]     = true,
  ["shell.panels.menus"]      = true,
  ["shell.panels.dialogs"]    = true,
  ["shell.panels.context"]    = true,
  ["shell.panels.keymap"]     = true,
  ["shell.panels.tabs"]       = true,
  ["shell.panels.widgets"]    = true,
  ["shell.panels.mouse"]      = true,
  ["shell.panels.ui"]         = true,
  ["shell.panels.desktop"]    = true,
  ["shell.panels.settingsapp"] = true,
  ["shell.panels.apps"]       = true,
  ["shell.panels.monitorapp"] = true,
  ["shell.panels.chatapp"]    = true,

  ["mail"]                    = true,
  ["mailui"]                  = true,
  ["mailapp"]                 = true,

  ["rbmk-cmd"]                = true,
  ["rbmk-controld"]           = true,
  ["rbmk.core"]               = true,
  ["shell.panels.takeover"]   = true,
  ["shell.login"]             = true,
  ["shell.chat"]              = true,
  ["shell.tutorial"]          = true,
  ["shell.syntax"]            = true,
  ["shell.panels"]            = true,
  ["shell"]                   = true,
  ["bios"]                    = true,
  ["init"]                    = true,
  ["install"]                 = true,
  ["system_manifest"]         = true,
}

local function isKernelModule(name)
  return type(name) == "string" and name:sub(1, #KERNEL_MODULE_PREFIX) == KERNEL_MODULE_PREFIX
end

local function isAllowedPrefix(name)
  for _, p in ipairs(ALLOWED_MODULE_PREFIXES) do
    if name:sub(1, #p) == p then return true end
  end
  return false
end

local function isUserLibName(name)
  if name:find("[^%w_.-]") then return false end
  if name:sub(1, 1) == "." then return false end
  return true
end

local function shallowCopy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function makeSafeOs()
  return {
    time     = os.time,
    date     = os.date,
    clock    = os.clock,
    difftime = os.difftime,

  }
end

local DANGEROUS_SIGNALS = {
  tos_shutdown = true, tos_logout = true,
  tos_login_complete = true, tos_seat_changed = true,
  tos_shell_exited = true,
}

local PULL_DROP = {
  modem_message      = true,
  tos_shutdown       = true, tos_logout        = true,
  tos_login_complete = true, tos_seat_changed  = true,
  tos_shell_exited   = true,
}

local function safePullSignal(timeout)
  local computer = require("computer")
  local deadline
  if type(timeout) == "number" and timeout >= 0 and timeout ~= math.huge then
    deadline = computer.uptime() + timeout
  end
  if coroutine.isyieldable and coroutine.isyieldable() then
    while true do
      local sig = table.pack(coroutine.yield())
      local name = sig[1]
      if name ~= nil and not PULL_DROP[name] then
        return table.unpack(sig, 1, sig.n)
      end

      if deadline and computer.uptime() >= deadline then return nil end
    end
  end

  local CEIL = 3
  local stop = computer.uptime()
    + ((type(timeout) == "number" and timeout >= 0 and timeout < CEIL) and timeout or CEIL)
  while true do
    local remaining = stop - computer.uptime()
    if remaining < 0 then return nil end
    local sig = table.pack(computer.pullSignal(remaining))
    local name = sig[1]
    if name == nil then return nil end
    if not PULL_DROP[name] then return table.unpack(sig, 1, sig.n) end
  end
end

local function makeSafeComputer()
  local computer = require("computer")
  return {
    uptime      = computer.uptime,
    freeMemory  = computer.freeMemory,
    totalMemory = computer.totalMemory,
    address     = computer.address,
    pullSignal  = safePullSignal,
    pushSignal  = function(name, ...)
      if type(name) == "string" and DANGEROUS_SIGNALS[name] then
        return
      end
      return computer.pushSignal(name, ...)
    end,
    energy      = computer.energy,
    maxEnergy   = computer.maxEnergy,
  }
end

sandbox._safePullSignal = safePullSignal

local BASE_COMPONENT_TYPES = {
  gpu = true, screen = true, keyboard = true,
  crafting = true, navigation = true, geolyzer = true,
  note_block = true, sign = true,
}

local GATED_COMPONENT_TYPES = {
  modem                = "peripheral.modem",
  tunnel               = "peripheral.modem",
  redstone             = "peripheral.redstone",
  robot                = "peripheral.robot",
  inventory_controller = "peripheral.inventory",
  transposer           = "peripheral.inventory",
  tank_controller      = "peripheral.inventory",
  tape_drive           = "peripheral.tape",
  --! An internet card reaches OUTSIDE the Minecraft world: it is both an
  --! exfiltration channel for anything the program can read and an inbound
  --! channel of bytes a stranger wrote. Gated behind its own cap rather
  --! than folded into the generic `component` grant, so a package that
  --! wants a screen and a keyboard does not silently get the network.
  internet             = "internet",
  tractor_beam         = "peripheral.tractor",
  piston               = "peripheral.piston",
  hologram             = "peripheral.hologram",
  --! OpenPrinter (PC-Logix) — the ONLY non-vanilla component type named in
  --! this file, and it is here on purpose rather than left to
  --! /etc/component_caps.cfg below. FEAT-5's config exists so an operator
  --! can add types WE do not ship code for; TOS ships a first-party
  --! `printer` driver package, and a package capability has to clear
  --! pkg.lua's PKG_RUN_CAPS allowlist as well as this table. A cap an
  --! operator can add to one side but not the other is a cap that silently
  --! does nothing (see the package-cap overrides in pkg.lua, which close
  --! that asymmetry for every OTHER mod). Costs nothing on a world without
  --! the mod: the type simply never appears in component.list.
  --! GATED, not base: a printer WRITES to the world — it consumes the
  --! player's paper and ink and drops physical pages into a chest. That is
  --! real-world actuation with a consumable cost, which is the same reason
  --! piston and robot are gated.
  openprinter          = "peripheral.printer",
}

local _extraBase  = {}
local _extraGated = {}
local _extraLoaded = false

local function loadComponentConfig()
  if _extraLoaded then return end
  _extraLoaded = true
  local okF, fsMod = pcall(require, "kernel.fs")
  local okS, serMod = pcall(require, "kernel.serialize")
  if not (okF and okS) then return end
  local path = "/etc/component_caps.cfg"
  if not fsMod.exists(path) then return end
  local raw = fsMod.readFile(path)
  if not raw or #raw == 0 or #raw > 8192 then return end
  local ok, cfg = pcall(serMod.decode, raw, { maxBytes = 8192 })
  if not ok or type(cfg) ~= "table" then return end

  if type(cfg.base) == "table" then
    for _, t in ipairs(cfg.base) do
      if type(t) == "string" and #t <= 64 and t:match("^[%w_]+$") then
        _extraBase[t] = true
      end
    end
  end
  if type(cfg.gated) == "table" then
    for ctype, cap in pairs(cfg.gated) do
      if type(ctype) == "string" and #ctype <= 64 and ctype:match("^[%w_]+$")
         and type(cap) == "string" and #cap <= 64 and cap:match("^[%w_%.]+$") then
        _extraGated[ctype] = cap
      end
    end
  end
end

function sandbox.reloadComponentConfig()
  _extraBase  = {}
  _extraGated = {}
  _extraLoaded = false
  loadComponentConfig()
  return _extraBase, _extraGated
end

local function isAllowedComponentType(ctype, caps)
  if not ctype then return false end
  loadComponentConfig()
  if BASE_COMPONENT_TYPES[ctype] or _extraBase[ctype] then return true end
  local gated = GATED_COMPONENT_TYPES[ctype] or _extraGated[ctype]
  if gated and caps and caps[gated] then return true end
  return false
end

local ALLOWED_COMPONENT_TYPES = BASE_COMPONENT_TYPES

local SEAT_SCOPED_TYPES = { gpu = true, screen = true, keyboard = true }

local function seatDeviceFilter()
  local okS, scr = pcall(require, "kernel.screen")
  if not okS or type(scr) ~= "table" or not scr.callerDevices then return nil end
  local okD, dev = pcall(scr.callerDevices)
  if not okD or type(dev) ~= "table" then return nil end

  if not dev.gpu then return nil end
  local allow = { [dev.gpu] = true }
  if dev.screen then allow[dev.screen] = true end
  for _, kb in ipairs(dev.keyboards or {}) do allow[kb] = true end
  return allow, dev
end

local function seatOwnAddress(ctype)
  local allow, dev = seatDeviceFilter()
  if not allow then return nil end
  if ctype == "gpu"      then return dev.gpu end
  if ctype == "screen"   then return dev.screen end
  if ctype == "keyboard" then return (dev.keyboards or {})[1] end
  return nil
end

local function makeSafeComponent(caps)
  caps = caps or {}
  local comp = require("component")
  local safe = {}

  local function seatDenies(addr, ctype)
    if not SEAT_SCOPED_TYPES[ctype] then return false end
    local allow = seatDeviceFilter()
    if not allow then return false end
    return not allow[addr]
  end

  function safe.list(filter, exact)
    local raw = comp.list(filter, exact)

    local allow = seatDeviceFilter()
    return function()
      while true do
        local addr, ctype = raw()
        if addr == nil then return nil end
        local denied = allow and SEAT_SCOPED_TYPES[ctype] and not allow[addr]
        if isAllowedComponentType(ctype, caps) and not denied then
          return addr, ctype
        end
      end
    end
  end

  function safe.proxy(addr)
    local ctype = comp.type(addr)
    if not isAllowedComponentType(ctype, caps) then
      return nil, "access denied"
    end
    if seatDenies(addr, ctype) then return nil, "not your seat" end
    return comp.proxy(addr)
  end

  function safe.type(addr) return comp.type(addr) end
  function safe.slot(addr) return comp.slot(addr) end

  function safe.get(addr, ctype)
    local result = comp.get(addr, ctype)
    if result then
      local t = comp.type(result)
      if isAllowedComponentType(t, caps) then return result end
    end
    return nil, "access denied"
  end

  function safe.invoke(addr, method, ...)
    local ctype = comp.type(addr)
    if not isAllowedComponentType(ctype, caps) then
      error("sandbox: access denied to " .. tostring(ctype))
    end
    if seatDenies(addr, ctype) then
      error("sandbox: " .. tostring(ctype) .. " belongs to another seat")
    end
    return comp.invoke(addr, method, ...)
  end

  function safe.isAvailable(ctype)
    if not isAllowedComponentType(ctype, caps) then return false end
    return comp.isAvailable(ctype)
  end

  function safe.getPrimary(ctype)
    if not isAllowedComponentType(ctype, caps) then
      return nil, "access denied"
    end

    if SEAT_SCOPED_TYPES[ctype] then
      local mine = seatOwnAddress(ctype)
      if mine then return comp.proxy(mine) end
    end
    return comp.getPrimary(ctype)
  end

  return safe
end

local USER_LIB_ROOTS = { "/usr/lib", "/usr/modules" }

local function nameToCandidatePaths(name)
  local rel = name:gsub("%.", "/")
  return {
    rel .. ".lua",
    rel .. "/init.lua",
  }
end

local function resolveUserLibPath(name)
  local fs = nil
  local ok, mod = pcall(require, "kernel.fs")
  if ok then fs = mod end
  if not fs then return nil end
  for _, root in ipairs(USER_LIB_ROOTS) do
    for _, rel in ipairs(nameToCandidatePaths(name)) do
      local path = root .. "/" .. rel
      if fs.exists(path) then return path end
    end
  end
  return nil
end

local COMPAT_COPY_NAMES = {
  ["compat"]               = true,
  ["compat.event"]         = true,
  ["compat.filesystem"]    = true,
  ["compat.io"]            = true,
  ["compat.term"]          = true,
  ["compat.keyboard"]      = true,
  ["compat.serialization"] = true,
  ["compat.sides"]         = true,
  ["compat.colors"]        = true,
  ["compat.text"]          = true,
  ["compat.buffer"]        = true,
  ["shell.ext"]            = true,
}

local function shallowCopyModule(mod)
  if type(mod) ~= "table" then return mod end
  local copy = {}
  for k, v in pairs(mod) do copy[k] = v end
  return copy
end

local function makeSafeRequire(opts, prebound)
  local cache = {}
  if prebound then
    for k, v in pairs(prebound) do cache[k] = v end
  end
  return function(name)
    if type(name) ~= "string" then
      error("bad argument #1 to 'require' (string expected)", 2)
    end
    if cache[name] ~= nil then return cache[name] end

    if isKernelModule(name) then
      error("sandbox: cannot require kernel module '" .. name .. "'", 2)
    end

    if BLOCKED_MODULE_NAMES[name] then

      if not (opts and opts.allowUserLibs and resolveUserLibPath(name)) then
        error("sandbox: module '" .. name .. "' is not available to sandboxed code", 2)
      end
    end

    if ALLOWED_MODULE_NAMES[name] or isAllowedPrefix(name) then
      local mod = require(name)

      if COMPAT_COPY_NAMES[name] then
        mod = shallowCopyModule(mod)

        if name == "compat.term" and type(mod._gpuForCaps) == "function" then
          local sbCaps = opts and opts.caps
          mod.gpu = function() return mod._gpuForCaps(sbCaps) end
        end
      end
      cache[name] = mod
      return mod
    end

    if isUserLibName(name) then
      local resolved = resolveUserLibPath(name)
      if resolved then

        local usersMod = _G._TOS and _G._TOS.users
        if opts.session and usersMod and usersMod.canAccessAs then
          local okR = usersMod.canAccessAs(opts.session, resolved, "r")
          if not okR then
            error("sandbox: access denied loading user lib '" .. name .. "'", 2)
          end
        end
        local mod = require(name)
        cache[name] = mod
        return mod
      end
    end

    error("sandbox: module '" .. name .. "' is not on the allowed list", 2)
  end
end

function sandbox.build(opts)
  opts = opts or {}
  local caps = opts.caps or {}
  local session = opts.session

  local secfs = _G._TOS and _G._TOS.securefs
  if not secfs then
    local ok, mod = pcall(require, "kernel.securefs")
    if ok then secfs = mod end
  end
  local boundFs = nil
  if secfs and (caps["fs.read"] or caps["fs.write"]) then
    boundFs = secfs.forSession(session)
  end

  local function readOnlyFsView(fsImpl)
    local READERS = {
      "exists", "isDirectory", "list", "readFile", "size", "lastModified",
      "normalize", "split", "join", "spaceTotal", "spaceUsed", "spaceFree",
      "mounts", "home", "resolve",
    }
    local view = {}
    for _, name in ipairs(READERS) do
      local fn = fsImpl[name]
      if type(fn) == "function" then
        view[name] = function(...) return fn(...) end
      end
    end
    if type(fsImpl.open) == "function" then
      view.open = function(path, mode, ...)
        mode = mode or "r"
        if type(mode) ~= "string" or mode:find("[wa+]") then
          return nil, "fs.write capability required"
        end
        return fsImpl.open(path, mode, ...)
      end
    end
    return view
  end

  local function sandboxPrint(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring(select(i, ...))
    end
    local line = table.concat(parts, "\t")
    if opts.stdout then
      opts.stdout(line)
    else
      print(line)
    end
  end

  local stringMT = getmetatable("")
  local realStringLib = string
  local function refersToString(v)
    return v == stringMT or v == realStringLib
  end
  local function safeGetMetatable(v)
    if type(v) == "string" then
      return nil
    end
    local mt = getmetatable(v)
    if mt == stringMT then return nil end
    return mt
  end
  local function safeSetMetatable(t, mt)
    if type(t) ~= "table" then
      error("bad argument #1 to 'setmetatable' (table expected)", 2)
    end
    if mt ~= nil then
      if type(mt) ~= "table" then
        error("bad argument #2 to 'setmetatable' (nil or table expected)", 2)
      end

      if refersToString(mt)
         or refersToString(rawget(mt, "__index"))
         or refersToString(rawget(mt, "__newindex"))
         or refersToString(rawget(mt, "__metatable")) then
        error("setmetatable: metatable referencing protected library denied", 2)
      end
    end
    return setmetatable(t, mt)
  end

  local sandboxedStringCopy = shallowCopy(string)

  local safeComp, safeCompr
  if caps["component"] then
    safeComp  = makeSafeComponent(caps)
    safeCompr = makeSafeComputer()
  end
  local prebound = {}
  if safeComp  then prebound.component = safeComp  end
  if safeCompr then prebound.computer  = safeCompr end

  local env = {

    assert      = assert,
    error       = error,
    pcall       = pcall,
    xpcall      = xpcall,
    type        = type,
    tostring    = tostring,
    tonumber    = tonumber,
    pairs       = pairs,
    ipairs      = ipairs,
    next        = next,
    select      = select,
    unpack      = table.unpack,
    rawequal    = rawequal,
    rawlen      = rawlen,

    setmetatable = safeSetMetatable,
    getmetatable = safeGetMetatable,

    math        = shallowCopy(math),
    string      = sandboxedStringCopy,
    table       = shallowCopy(table),
    utf8        = utf8 and shallowCopy(utf8) or nil,
    coroutine   = shallowCopy(coroutine),

    print       = sandboxPrint,
    require     = makeSafeRequire(opts, prebound),
  }

  env._G = env
  env._ENV = env
  env._VERSION = _VERSION

  if boundFs then
    if caps["fs.write"] then
      env.fs = boundFs
    else
      env.fs = readOnlyFsView(boundFs)
    end
  end

  if caps["compat.io"] then
    local ok, compatIo = pcall(require, "compat.io")
    if ok then env.io = compatIo end
    env.os = makeSafeOs()
    local okFs, compatFs = pcall(require, "compat.filesystem")
    if okFs then env.filesystem = compatFs end
  end

  if caps["legacy"] then
    env.os = os
    env.io = io

    local okLog, logMod = pcall(require, "kernel.log")
    if okLog and logMod and logMod.warn then
      logMod.warn("sandbox", "Built env with legacy cap — full os/io exposed")
    end
  end

  if caps["component"] then
    env.component = safeComp
    env.computer  = safeCompr
  end

  if caps["load"] then
    env.load = function(chunk, name, _mode, _e)
      return load(chunk, name, "t", env)
    end
    env.loadstring = env.load
  end

  if caps["notify"] then
    local okN, nf = pcall(require, "kernel.notify")
    if okN and nf and nf.post then
      env.notify = {
        post = function(spec)
          if type(spec) ~= "table" then return nil, "spec must be a table" end

          local copy = {}
          for k, v in pairs(spec) do copy[k] = v end
          local pkgName = opts.pkgName
          copy.from = (type(pkgName) == "string"
            and pkgName:match("^[%w][%w%-]*$")) and pkgName or "package"
          return nf.post(copy)
        end,
        result = function(id) return nf.result(id) end,
      }
    end
  end

  if caps["net"] then
    local ok, net = pcall(require, "kernel.net")
    if ok then env.net = net end
  end

  --! Exposes the KERNEL WRAPPER (bounded reads, timeouts, http/https only),
  --! which is what well-behaved code and TOS's own callers should use. It
  --! does NOT make those bounds a containment boundary: this same cap is
  --! what unlocks the raw `internet` component type above, because an
  --! OpenOS program doing require("internet") reaches for the card
  --! directly and compat would be a fiction without it. The capability
  --! grant is the boundary; the bounds are there so honest code cannot
  --! accidentally OOM a 192 KB machine on somebody's web page.
  if caps["internet"] then
    local ok, inet = pcall(require, "kernel.internet")
    if ok and inet then
      env.internet = {
        get      = function(url, o) return inet.get(url, o) end,
        download = function(url, dest, o) return inet.download(url, dest, o) end,
        socket   = function(addr, port) return inet.socket(addr, port) end,
        status   = function() return inet.status() end,
        available = function() return inet.available() end,
      }
    end
  end

  if caps["swap"] then
    local ok, sw = pcall(require, "kernel.swap")
    if ok and sw and sw.table then
      env.swap = {
        table     = function(o) return sw.table(o) end,
        freeTable = function(p) return sw.freeTable(p) end,
        usage     = sw.usage,
      }
    end
  end

  if caps["vault"] then
    local ok, v = pcall(require, "kernel.vault")
    if ok and v and v.encrypt and v.decrypt then
      env.vault = {
        encrypt     = function(plaintext, passphrase, o) return v.encrypt(plaintext, passphrase, o) end,
        decrypt     = function(blob, passphrase) return v.decrypt(blob, passphrase) end,
        isEncrypted = function(s) return v.isEncrypted(s) end,
      }
    end
  end

  if caps["crypto"] then
    local okC, kcrypto = pcall(require, "kernel.crypto")
    if okC and kcrypto and kcrypto.hmac then
      env.crypto = {
        hash     = function(s) return kcrypto.hash(s) end,
        hmac     = function(key, msg) return kcrypto.hmac(key, msg) end,
        ctEquals = function(a, b) return kcrypto.ctEquals(a, b) end,
        random   = function(n) return kcrypto.salt(n) end,
      }
      local pkgName = opts.pkgName
      if type(pkgName) == "string" and pkgName:match("^[%w][%w%-]*$") then
        env.crypto.secret = function()

          local sess = nil
          local okP, procMod = pcall(require, "kernel.process")
          if okP and procMod and procMod.currentSession then
            sess = procMod.currentSession()
          end
          if not sess then
            local usersMod = _G._TOS and _G._TOS.users
            if not usersMod then
              local okU, u = pcall(require, "kernel.users")
              if okU then usersMod = u end
            end
            if usersMod and usersMod.currentSession then
              sess = usersMod.currentSession()
            end
          end
          local allowed = sess and (sess.isKernel or sess.isLogin
            or (type(sess.tier) == "number" and sess.tier >= 2))
          if not allowed then
            return nil, "crypto.secret requires an admin session"
          end
          local okF, kfs = pcall(require, "kernel.fs")
          if not okF or not kfs then return nil, "fs unavailable" end
          local dir  = "/var/pkg/secrets"
          local path = dir .. "/" .. pkgName
          if kfs.exists(path) then
            local data = kfs.readFile(path)
            if data and #data >= 16 then return data end
            return nil, "secret unreadable"
          end
          if not kfs.exists(dir) then kfs.makeDirectory(dir) end
          local secret = kcrypto.salt(32)
          local wOk, wErr = kfs.writeFile(path, secret)
          if not wOk then return nil, "cannot store secret: " .. tostring(wErr) end
          return secret
        end
      end
    end
  end

  return env
end

function sandbox.run(src, chunkname, opts, ...)
  local env = sandbox.build(opts)
  local fn, err = load(src, chunkname, "t", env)
  if not fn then
    return false, "compile error: " .. tostring(err)
  end
  return pcall(fn, ...)
end

return sandbox
