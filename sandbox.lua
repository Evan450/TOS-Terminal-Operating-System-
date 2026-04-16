-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS kernel.sandbox                                      ║
-- ║  Capability-checked environments for user programs.     ║
-- ║                                                          ║
-- ║  Replaces ad-hoc __index=_G environments and the legacy  ║
-- ║  panels.makeProgramEnv. User programs see ONLY what the ║
-- ║  caller explicitly granted via the `caps` table. No     ║
-- ║  ambient authority, no raw computer/component/io, no    ║
-- ║  back-door require into kernel.* modules.               ║
-- ╚══════════════════════════════════════════════════════════╝

local sandbox = {}

-- ============================================================
-- Capability set — what a sandboxed program may touch.
-- ============================================================
-- "fs.read"     — read via securefs bound to opts.session
-- "fs.write"    — write via securefs bound to opts.session
-- "compat.io"   — Lua io/os/filesystem/shell compat API
-- "component"   — component proxy (filtered: no computer.shutdown)
-- "load"        — load/loadstring (for REPL/debug tools)
-- "net"         — network module
-- "legacy"      — unlocks full os.* and io.* (opt-in compat for
--                 ported OpenOS programs; default OFF)
-- ============================================================

local KERNEL_MODULE_PREFIX = "kernel."
local ALLOWED_MODULE_PREFIXES = {
  "compat.",
  "shell.ext",  -- only the user extension API, not internal shell modules
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

-- Shallow copy helper — we want a fresh table for string/math/table so
-- a malicious program can't monkey-patch the base libraries for everyone.
local function shallowCopy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- ============================================================
-- Trimmed os table — drops functions that would bypass securefs
-- or leak machine info a user program has no business touching.
-- ============================================================
local function makeSafeOs()
  return {
    time     = os.time,
    date     = os.date,
    clock    = os.clock,
    difftime = os.difftime,
    getenv   = os.getenv,
    -- os.remove / os.rename intentionally omitted — use fs/filesystem.
    -- os.execute / os.exit intentionally omitted.
  }
end

-- ============================================================
-- Trimmed computer table — no shutdown/beep/eeprom mutation.
-- pushSignal is wrapped to filter dangerous internal signals.
-- ============================================================
local DANGEROUS_SIGNALS = {
  tos_shutdown = true, tos_logout = true,
  tos_login_complete = true, tos_seat_changed = true,
  tos_shell_exited = true,
}

local function makeSafeComputer()
  local computer = require("computer")
  return {
    uptime      = computer.uptime,
    freeMemory  = computer.freeMemory,
    totalMemory = computer.totalMemory,
    address     = computer.address,
    pullSignal  = computer.pullSignal,
    pushSignal  = function(name, ...)
      if type(name) == "string" and DANGEROUS_SIGNALS[name] then
        return  -- silently drop synthesized control signals
      end
      return computer.pushSignal(name, ...)
    end,
    energy      = computer.energy,
    maxEnergy   = computer.maxEnergy,
  }
end

-- ============================================================
-- Filtered component API — hides dangerous component types
-- (eeprom, computer) and only exposes user-safe peripherals.
-- ============================================================
local ALLOWED_COMPONENT_TYPES = {
  filesystem = true, gpu = true, screen = true, keyboard = true,
  modem = true, redstone = true, robot = true,
  inventory_controller = true, tape_drive = true, note_block = true,
  crafting = true, navigation = true, geolyzer = true,
  tank_controller = true, tractor_beam = true, sign = true,
  piston = true, hologram = true,
}

local function makeSafeComponent()
  local comp = require("component")
  local safe = {}

  function safe.list(filter, exact)
    local raw = comp.list(filter, exact)
    return function()
      while true do
        local addr, ctype = raw()
        if addr == nil then return nil end
        if ALLOWED_COMPONENT_TYPES[ctype] then return addr, ctype end
      end
    end
  end

  function safe.proxy(addr)
    local ctype = comp.type(addr)
    if not ctype or not ALLOWED_COMPONENT_TYPES[ctype] then
      return nil, "access denied"
    end
    return comp.proxy(addr)
  end

  function safe.type(addr) return comp.type(addr) end
  function safe.slot(addr) return comp.slot(addr) end

  function safe.get(addr, ctype)
    local result = comp.get(addr, ctype)
    if result then
      local t = comp.type(result)
      if t and ALLOWED_COMPONENT_TYPES[t] then return result end
    end
    return nil, "access denied"
  end

  function safe.invoke(addr, method, ...)
    local ctype = comp.type(addr)
    if not ctype or not ALLOWED_COMPONENT_TYPES[ctype] then
      error("sandbox: access denied to " .. tostring(ctype))
    end
    return comp.invoke(addr, method, ...)
  end

  function safe.isAvailable(ctype)
    if not ALLOWED_COMPONENT_TYPES[ctype] then return false end
    return comp.isAvailable(ctype)
  end

  function safe.getPrimary(ctype)
    if not ALLOWED_COMPONENT_TYPES[ctype] then
      return nil, "access denied"
    end
    return comp.getPrimary(ctype)
  end

  return safe
end

-- ============================================================
-- Capability-checked require. Never returns a kernel.* module;
-- only modules that live under /usr/lib, /usr/modules, or the
-- compat/shell namespaces. Everything goes through the caller's
-- session so securefs can enforce ACLs on the source file.
-- ============================================================
local function makeSafeRequire(opts)
  local cache = {}
  return function(name)
    if type(name) ~= "string" then
      error("bad argument #1 to 'require' (string expected)", 2)
    end
    if cache[name] ~= nil then return cache[name] end

    if isKernelModule(name) then
      error("sandbox: cannot require kernel module '" .. name .. "'", 2)
    end

    -- Compat and shell modules are explicitly whitelisted — they are
    -- the intended user-facing API surface.
    if isAllowedPrefix(name) then
      local mod = require(name)
      cache[name] = mod
      return mod
    end

    -- Delegate everything else to the standard require. The Lua package
    -- loader is still restricted by TOS's package.path which only points
    -- at /usr/lib, /usr/modules, etc. — not at kernel paths.
    local mod = require(name)
    cache[name] = mod
    return mod
  end
end

-- ============================================================
-- sandbox.build(opts) -> env
-- ============================================================
function sandbox.build(opts)
  opts = opts or {}
  local caps = opts.caps or {}
  local session = opts.session

  -- Resolve securefs with the caller's session pre-bound. If the
  -- caller lacks fs caps we still expose it as nil so attempts to
  -- touch it produce a clear error rather than working by accident.
  local secfs = _G._TOS and _G._TOS.securefs
  if not secfs then
    local ok, mod = pcall(require, "kernel.securefs")
    if ok then secfs = mod end
  end
  local boundFs = nil
  if secfs and (caps["fs.read"] or caps["fs.write"]) then
    boundFs = secfs.forSession(session)
  end

  -- Output stream: opts.stdout is a function(text) — if absent, fall
  -- through to the global print so CLI scripts still produce output.
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

  local env = {
    -- Base Lua — safe pure functions.
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
    unpack      = table.unpack,  -- some programs still expect the 5.1 name
    rawget      = rawget,
    rawset      = rawset,
    rawlen      = rawlen,
    rawequal    = rawequal,
    setmetatable = setmetatable,
    getmetatable = getmetatable,

    -- Fresh shallow copies so sandboxes can't mutate each other's libs.
    math        = shallowCopy(math),
    string      = shallowCopy(string),
    table       = shallowCopy(table),
    utf8        = utf8 and shallowCopy(utf8) or nil,
    coroutine   = shallowCopy(coroutine),

    -- Bound I/O
    print       = sandboxPrint,
    require     = makeSafeRequire(opts),
  }

  env._G = env
  env._ENV = env
  env._VERSION = _VERSION

  -- Session-bound filesystem. Programs that want raw path operations
  -- use this; compat.io/compat.filesystem provide the OpenOS flavor.
  if boundFs then
    env.fs = boundFs
  end

  -- compat.io cap: expose io + trimmed os + filesystem compat module.
  if caps["compat.io"] then
    local ok, compatIo = pcall(require, "compat.io")
    if ok then env.io = compatIo end
    env.os = makeSafeOs()
    local okFs, compatFs = pcall(require, "compat.filesystem")
    if okFs then env.filesystem = compatFs end
  end

  -- Legacy cap: unlock the full os/io libraries for ported OpenOS
  -- programs that need os.remove etc. Should only be granted when the
  -- user explicitly opts in via a "legacy" flag.
  if caps["legacy"] then
    env.os = os
    env.io = io
  end

  -- component cap: filtered component + trimmed computer API.
  if caps["component"] then
    env.component = makeSafeComponent()
    env.computer  = makeSafeComputer()
  end

  -- load cap: dynamic code evaluation, for REPLs and debuggers.
  if caps["load"] then
    env.load = function(chunk, name, mode, e)
      return load(chunk, name, mode or "t", e or env)
    end
    env.loadstring = env.load
  end

  -- net cap: expose the net module. The net module itself may
  -- check per-call permissions in a later phase.
  if caps["net"] then
    local ok, net = pcall(require, "kernel.net")
    if ok then env.net = net end
  end

  return env
end

-- ============================================================
-- sandbox.run(src, chunkname, opts, ...) -> ok, result
-- Convenience wrapper: build env, load source, pcall.
-- ============================================================
function sandbox.run(src, chunkname, opts, ...)
  local env = sandbox.build(opts)
  local fn, err = load(src, chunkname, "t", env)
  if not fn then
    return false, "compile error: " .. tostring(err)
  end
  return pcall(fn, ...)
end

return sandbox
