local sandbox = {}

local KERNEL_MODULE_PREFIX = "kernel."

local ALLOWED_MODULE_PREFIXES = {
  "compat.",
  "peripheral.",
}

local ALLOWED_MODULE_NAMES = {
  compat        = true,

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
  --! #SEC (pentest, Sep 2026) — shell.ext is not an extension API; it is
  --! the lazy-loaded body of the net/ping/hostname/config/audio commands,
  --! and the unsandboxed shell (commands/extras.lua) is its only caller.
  --! It sat on the ALLOWED list under a stale description, and parts of it
  --! reach _G._TOS directly (the peer-alias table, audio) instead of going
  --! through a capability the program was granted. The alias writers do
  --! re-check the live principal's tier; nothing else about it belongs in
  --! a sandbox either.
  ["shell.ext"]               = true,
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

  ["rbmk-skala"]              = true,
  ["rbmk.skala"]              = true,
  ["rbmk.wall"]               = true,
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

--! #SEC — signals a sandboxed program must never SYNTHESIZE via
--! computer.pushSignal. The old wrapper dropped only the tos_* control set,
--! which left every HARDWARE INPUT signal pushable:
--! a program holding the `component` cap could push("key_down", kbAddr,
--! char, code) — or touch/clipboard/scroll — and proc.tick routes an input
--! signal to the FOREGROUND process of the seat that owns that address, or
--! to the GLOBAL foreground when the address doesn't resolve. That is
--! keystroke/pointer injection into another seat's (or another user's)
--! session: a guest could type a command into a root shell on another seat.
--! modem_message is here too, so a program can't forge inbound network
--! traffic other processes' listeners trust. Input arrives from real
--! hardware and the kernel — never from a guest program — so refusing to
--! re-emit it costs honest code nothing (custom app signals still push).
--! (test_sandbox_push.lua)
local PUSH_DROP = {

  key_down = true, key_up = true, clipboard = true,
  touch = true, drag = true, drop = true, scroll = true,

  modem_message = true,

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

      if type(name) == "string" and PUSH_DROP[name] then
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

--! #SEC (pentest, Sep 2026) — EVERY module table a sandbox receives is its
--! own view, not only the compat.* names H4 listed. The rest came back as
--! the very table the kernel and the shell use: shell.keys (every seat's
--! shell calls keys.is on each keystroke), peripheral.*, compat.shell_api
--! and compat.internet, every installed library (blockfs, whose mount()
--! the `drive` command hands a raw drive proxy), and -- through build()
--! below -- compat.io, compat.filesystem and kernel.net themselves.
--! `require("shell.keys").is = f` made f run inside every other seat's
--! shell process, as that seat's principal, seeing its keystrokes;
--! `net.send = f` did the same inside kernel services running as _kernel_.
--! A view reads through to the real module (so it never goes stale, unlike
--! a copy) and keeps its own writes; its metatable is locked, and pairs()
--! walks the module without ever handing the original table back.
--! (test_sandbox_module_isolation.lua)
local function isolatedModule(mod)
  if type(mod) ~= "table" then return mod end
  return setmetatable({}, {
    __index = mod,
    __len   = function() return #mod end,
    __pairs = function()
      local k
      return function()
        local v
        k, v = next(mod, k)
        return k, v
      end
    end,
    __call  = function(_, ...) return mod(...) end,
    __metatable = false,
  })
end

--! #SEC (pentest, Sep 2026) — what the `net` capability means for a
--! program: send and receive, find peers, ask to be trusted. It used to be
--! the whole kernel.net module, which also carries getTrust() (the trust
--! manager: setLevel/setSecret/getSecret), handleIncoming() (inject a
--! packet "from" any address), setServiceArm() (arm rshd), shutdown(), and
--! the _-prefixed internals. And the peer lookups returned the LIVE
--! discovery records, so `findPeer("server").addr = me` redirected every
--! other user's ssh/share. A program now gets an allowlist, and copies.
local NET_FACADE = {
  "send", "broadcast", "on", "off", "onceFrom", "offAll", "waitFor",
  "sendMessage", "requestTrust", "discover", "getAddress", "getHostname",
  "isAvailable", "modemCount",
}
local function copyPeer(p)
  if type(p) ~= "table" then return p end
  return { addr = p.addr, lastSeen = p.lastSeen, hostname = p.hostname,
           device = p.device, trust = p.trust }
end
local function netFacade(net)
  local f = {}
  for _, k in ipairs(NET_FACADE) do
    if type(net[k]) == "function" then f[k] = net[k] end
  end
  local function copyList(list)
    local out = {}
    for i, p in ipairs(type(list) == "table" and list or {}) do out[i] = copyPeer(p) end
    return out
  end
  if type(net.peers) == "function" then f.peers = function() return copyList(net.peers()) end end
  if type(net.scan) == "function" then f.scan = function(t) return copyList(net.scan(t)) end end
  if type(net.findPeer) == "function" then
    f.findPeer = function(q) return copyPeer(net.findPeer(q)) end
  end
  if type(net.getProtocol) == "function" then
    f.getProtocol = function() return isolatedModule(net.getProtocol()) end
  end
  if type(net.status) == "function" then
    f.status = function()
      local s, out = net.status(), {}
      for k, v in pairs(type(s) == "table" and s or {}) do
        if type(v) ~= "table" then out[k] = v end
      end
      return out
    end
  end
  return f
end

local function makeSafeRequire(opts, prebound, envRef)
  local cache = {}
  local loading = {}
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

    --! #SEC (pentest, Sep 2026) — two compat names are CAPABILITIES, not
    --! libraries, and the "compat." prefix below admitted both for anyone:
    --!   compat.component  OpenOS-style field access built over the RAW
    --!     component library: .proxy, .list, and a raw proxy for any type
    --!     (`.filesystem.remove("/init.lua")`, `.eeprom.set(...)`), with no
    --!     cap consulted -- the whole C4 component split, undone by one
    --!     require. It is now the same shape over THIS sandbox's filtered
    --!     component table, and needs the `component` cap.
    --!   compat.internet  reaches the card through the real component
    --!     library; "the capability is the gate" held only for the
    --!     component route. It now needs the `internet` cap.
    --! (test_sandbox_compat_caps.lua)
    if name == "compat.component" then
      local safeC = prebound and prebound.component
      if not safeC then
        error("sandbox: 'compat.component' needs the component capability", 2)
      end
      local view = setmetatable({}, {
        __index = function(_, key)
          local v = safeC[key]
          if v ~= nil then return v end
          if type(key) == "string" then
            local okP, px = pcall(safeC.getPrimary, key)
            if okP then return px end
          end
          return nil
        end,
        __newindex  = function() error("component view is read-only", 2) end,
        __metatable = false,
      })
      cache[name] = view
      return view
    end
    if name == "compat.internet" and not (opts.caps and opts.caps["internet"]) then
      error("sandbox: 'compat.internet' needs the internet capability", 2)
    end
    --! #SEC (pentest, Sep 2026) — `compat` itself is the layer's LOADER.
    --! init() re-run after boot forwards opts.procSleep into the os.sleep
    --! that every real-`os` caller shares, and setProcSleep() does it
    --! outright, so a sandbox could make its function run inside whichever
    --! process next slept. A sandbox gets the read-only part: has(), list().
    if name == "compat" then
      local okC, cm = pcall(require, "compat")
      if not okC or type(cm) ~= "table" then
        error("sandbox: the compat layer is unavailable", 2)
      end
      local view = { has = cm.has, list = cm.list }
      cache[name] = view
      return view
    end

    if BLOCKED_MODULE_NAMES[name] then

      if not (opts and opts.allowUserLibs and resolveUserLibPath(name)) then
        error("sandbox: module '" .. name .. "' is not available to sandboxed code", 2)
      end
    end

    if ALLOWED_MODULE_NAMES[name] or isAllowedPrefix(name) then

      local mod = isolatedModule(require(name))

      if name == "compat.term" and type(mod) == "table"
         and type(mod._gpuForCaps) == "function" then
        local sbCaps = opts and opts.caps
        mod.gpu = function() return mod._gpuForCaps(sbCaps) end
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

        if opts.allowUserLibs then
          local mod = require(name)
          cache[name] = mod
          return mod
        end
        --! #SEC (pentest, Sep 2026) — everyone else loads the library INSIDE
        --! this sandbox. require(name) is the kernel loader, which compiles
        --! the file with no environment -- the real _G -- so any package
        --! could ship /usr/lib/x.lua beside a command that says require("x")
        --! and have x run as the kernel: its declared capabilities, the
        --! legacy ban and securefs all bypassed by one require. A library
        --! now runs with exactly the authority of the code that required it,
        --! one instance per sandbox, so it also cannot be shared and
        --! poisoned. The first-party libraries reached this way (mouse,
        --! printer, printerfmt) use only what a sandbox provides.
        --! (test_sandbox_userlib_env.lua)
        local env = envRef and envRef.env
        if type(env) ~= "table" then
          error("sandbox: no environment to load user lib '" .. name .. "' into", 2)
        end
        if loading[name] then
          error("sandbox: circular require of '" .. name .. "'", 2)
        end
        local okF, kfs = pcall(require, "kernel.fs")
        local src = okF and type(kfs) == "table" and kfs.readFile and kfs.readFile(resolved)
        if type(src) ~= "string" then
          error("sandbox: cannot read user lib '" .. name .. "'", 2)
        end
        local fn, lerr = load(src, "=" .. resolved, "t", env)
        if not fn then
          error("sandbox: cannot load user lib '" .. name .. "': " .. tostring(lerr), 2)
        end
        loading[name] = true
        local okR, result = pcall(fn, name)
        loading[name] = nil
        if not okR then
          error("sandbox: user lib '" .. name .. "' failed: " .. tostring(result), 2)
        end
        if result == nil then result = true end
        cache[name] = result
        return result
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
    elseif type(print) == "function" then

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

  local envRef = {}

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
    require     = makeSafeRequire(opts, prebound, envRef),
  }

  envRef.env = env
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
    if ok then env.io = isolatedModule(compatIo) end
    env.os = makeSafeOs()
    local okFs, compatFs = pcall(require, "compat.filesystem")
    if okFs then env.filesystem = isolatedModule(compatFs) end
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

      local ownIds = {}
      env.notify = {
        post = function(spec)
          if type(spec) ~= "table" then return nil, "spec must be a table" end

          local copy = {}
          for k, v in pairs(spec) do copy[k] = v end
          local pkgName = opts.pkgName
          copy.from = (type(pkgName) == "string"
            and pkgName:match("^[%w][%w%-]*$")) and pkgName or "package"
          local id, err = nf.post(copy)
          if id ~= nil then ownIds[id] = true end
          return id, err
        end,
        result = function(id)
          if not ownIds[id] then return nil end
          return nf.result(id)
        end,
      }
    end
  end

  if caps["net"] then
    local ok, net = pcall(require, "kernel.net")
    if ok then

      env.net = opts.allowUserLibs and isolatedModule(net) or netFacade(net)
    end
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
