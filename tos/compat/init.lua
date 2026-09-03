-- ╔══════════════════════════════════════╗
-- ║  TOS OpenOS Compatibility Layer      ║
-- ║  Registers shims for OpenOS APIs     ║
-- ╚══════════════════════════════════════╝
-- Allows OpenOS programs (including OPPM) to run on TOS by providing
-- compatible implementations of standard OpenOS libraries.
-- Loaded during kernel boot if sufficient RAM is available.

local compat = {}

--- Register all compatibility modules in the require() cache.
-- After this, require("term"), require("filesystem"), etc. work
-- as OpenOS programs expect.
-- @param opts table: { procSleep = function } (optional, injected post-boot)
function compat.init(opts)
  opts = opts or {}
  -- #MEM — idempotence guard. The layer now loads LAZILY on the first
  -- require() of an OpenOS name (see OPENOS_SHIMS in /init.lua) instead of
  -- at boot, so init can be reached from several call sites; only the first
  -- run may do the work. A repeat call with procSleep still forwards it
  -- (the kernel injects proc.sleep after boot on some paths).
  if compat._initCounts then
    if opts.procSleep and compat.setProcSleep then
      compat.setProcSleep(opts.procSleep)
    end
    return compat._initCounts[1], compat._initCounts[2]
  end
  -- The TOS require system uses a `loaded` table.
  -- We need to pre-register our shims so they're found before
  -- the search path lookup (which wouldn't find "term" etc.)

  -- Map of OpenOS module name -> TOS compat module path
  local shims = {
    ["sides"]         = "compat.sides",
    ["colors"]        = "compat.colors",
    ["keyboard"]      = "compat.keyboard",
    ["text"]          = "compat.text",
    ["serialization"] = "compat.serialization",
    ["buffer"]        = "compat.buffer",
    ["term"]          = "compat.term",
    ["filesystem"]    = "compat.filesystem",
    ["event"]         = "compat.event",
    ["shell"]         = "compat.shell_api",
    ["io"]            = "compat.io",
    -- Registering the name is harmless without a card: the library loads
    -- and every call reports "no primary internet card found", which is
    -- exactly what OpenOS does on a machine without one. Whether a
    -- SANDBOXED caller can reach the card is decided by the `internet`
    -- capability, not by this table.
    ["internet"]      = "compat.internet",
  }

  local loaded = 0
  local failed = 0

  for openosName, tosPath in pairs(shims) do
    local ok, mod = pcall(require, tosPath)
    if ok then
      -- Register under the OpenOS name so require("term") finds it
      package.loaded[openosName] = mod
      loaded = loaded + 1
    else
      -- Non-fatal: some shims may fail on low RAM
      failed = failed + 1
    end
  end

  -- Also register `io` as a global (Lua standard)
  if package.loaded["io"] then
    _G.io = package.loaded["io"]
  end

  -- ── component.* OpenOS extensions ──────────────────────
  -- OpenOS wraps the raw component library with helper functions
  -- that many community programs depend on (isAvailable, get, field access).
  do
    local rawComp = require("component")

    -- component.isAvailable(type): true if at least one component exists
    if not rawComp.isAvailable then
      rawComp.isAvailable = function(ctype)
        local addr = rawComp.list(ctype)()
        return addr ~= nil
      end
    end

    -- component.get(partialAddress, type): resolve partial address to full
    if not rawComp.get then
      rawComp.get = function(address, ctype)
        if type(address) ~= "string" then return nil, "invalid address" end
        for addr in rawComp.list(ctype) do
          if addr:sub(1, #address) == address then
            return addr
          end
        end
        return nil, "no such component"
      end
    end

    -- component.getPrimary(type): get primary proxy (alias for field access)
    if not rawComp.getPrimary then
      rawComp.getPrimary = function(ctype)
        local addr = rawComp.list(ctype)()
        if addr then return rawComp.proxy(addr) end
        return nil, "no primary " .. tostring(ctype) .. " component"
      end
    end

    -- #SEC H14 — DO NOT mutate the global component table's metatable.
    -- The previous code installed `setmetatable(rawComp, {...})` which
    -- changed `require("component")` for EVERY caller in the kernel
    -- (including sandboxed programs that would then see component.<type>
    -- field access bypassing the C4 per-type cap split). Instead, expose
    -- the OpenOS-style field access through a SEPARATE wrapper that
    -- compat-aware code can request explicitly. The raw component module
    -- remains as OC ships it.
    local proxyCache = setmetatable({}, { __mode = "v" })
    local componentFieldAccess = setmetatable({}, {
      __index = function(_, key)
        -- Forward known method names to the raw component module.
        if rawComp[key] ~= nil then return rawComp[key] end
        -- Otherwise treat as component-type access (OpenOS style).
        if proxyCache[key] then
          local ok = pcall(rawComp.type, proxyCache[key].address)
          if ok then return proxyCache[key] end
          proxyCache[key] = nil
        end
        local addr = rawComp.list(key)()
        if addr then
          local proxy = rawComp.proxy(addr)
          proxyCache[key] = proxy
          return proxy
        end
        return nil
      end,
    })
    -- Make the wrapper available to programs that explicitly opt in via
    -- `require("compat.component")` (registered in package.loaded under
    -- the compat namespace, NOT under the bare `component` name).
    package.loaded["compat.component"] = componentFieldAccess
  end

  -- ── print() override ───────────────────────────────────
  -- Route print() through the compat io module so output goes through
  -- term.write() instead of directly to the GPU buffer.
  if package.loaded["io"] then
    local iomod = package.loaded["io"]
    _G.print = function(...)
      local args = table.pack(...)
      for i = 1, args.n do
        if i > 1 then iomod.write("\t") end
        iomod.write(tostring(args[i]))
      end
      iomod.write("\n")
    end
  end

  -- ── os.* extensions (OpenOS compatibility) ──────────────
  -- OpenOS extends Lua's os table with sleep, getenv, setenv, etc.
  -- Many community programs depend on these.
  if not _G.os then _G.os = {} end

  -- os.sleep: yield for N seconds without blocking other processes.
  -- If proc.sleep is available (injected from kernel after boot), uses
  -- coroutine.yield so the TOS scheduler can run other processes.
  -- Falls back to chunked pullSignal for pre-scheduler contexts.
  do
    local computer2 = require("computer")
    local _procSleep = opts.procSleep  -- may be nil during early boot

    _G.os.sleep = function(seconds)
      seconds = tonumber(seconds) or 0
      if seconds <= 0 then
        -- Yield once to let other work happen
        if _procSleep then
          _procSleep(0)
        else
          computer2.pullSignal(0)
        end
        return
      end
      if _procSleep then
        _procSleep(seconds)
      else
        -- Fallback: chunked pullSignal (blocks scheduler but not forever)
        local deadline = computer2.uptime() + seconds
        while computer2.uptime() < deadline do
          local remaining = deadline - computer2.uptime()
          computer2.pullSignal(math.min(remaining, 0.5))
        end
      end
    end

    -- Allow late injection of proc.sleep (called from kernel after boot)
    function compat.setProcSleep(fn)
      _procSleep = fn
    end
  end

  -- os.getenv / os.setenv: environment variables
  if not _G.os.getenv then
    local envVars = {
      HOME = "/home",
      SHELL = "/tos/shell/init.lua",
      TERM = "tos",
      PATH = "/usr/bin:/bin",
    }
    -- Try to load from kernel.env if available
    local ok3, envMod = pcall(require, "kernel.env")
    _G.os.getenv = function(name)
      if ok3 and envMod.read then
        local val = envMod.read(nil, name)
        if val then return val end
      end
      return envVars[name]
    end
    _G.os.setenv = function(name, value)
      if ok3 and envMod.write then
        envMod.write(nil, name, value)
      else
        envVars[name] = value
      end
    end
  end

  -- os.tmpname: return a temporary file path.
  -- #SEC H33 — the old implementation seeded a counter from uptime *100
  -- and incremented; two callers within the same boot got predictable,
  -- adjacent paths, which is a classic TOCTOU symlink-style problem.
  -- New behaviour: use crypto.salt() for 16 hex chars of randomness and
  -- atomically create the file (failing the OC FS exclusivity check on
  -- a collision rather than handing back a path the caller assumes is
  -- unique). Loop a small number of times before giving up.
  if not _G.os.tmpname then
    _G.os.tmpname = function()
      local cryptoMod
      local okC, c = pcall(require, "kernel.crypto")
      if okC then cryptoMod = c end
      local fsMod
      local okF, f = pcall(require, "kernel.fs")
      if okF then fsMod = f end
      for _ = 1, 8 do
        local rand
        if cryptoMod and cryptoMod.salt then
          rand = cryptoMod.salt(16)
        else
          -- Last-resort fallback: combine multiple weak sources rather
          -- than the bare uptime*100 counter. Still not crypto-strong
          -- but at least not collidable on a single boot.
          rand = tostring(require("computer").uptime() * 1e6)
            .. "_" .. (tostring({}):match("0x(%x+)") or "fallback")
        end
        local path = "/tmp/tos_tmp_" .. rand
        if fsMod and fsMod.exists then
          if not fsMod.exists(path) then
            -- Create-empty to "claim" the name. A concurrent caller
            -- looping at the same time will pick a different rand.
            pcall(fsMod.writeFile, path, "")
            return path
          end
        else
          return path
        end
      end
      -- After 8 tries, give up loudly rather than silently colliding.
      error("os.tmpname: could not allocate unique tmp file")
    end
  end

  compat._initCounts = { loaded, failed }
  return loaded, failed
end

--- Check if a specific OpenOS module is available.
function compat.has(name)
  return package.loaded[name] ~= nil
end

--- Get the list of registered shims.
function compat.list()
  local result = {}
  local names = {"sides","colors","keyboard","text","serialization",
                  "buffer","term","filesystem","event","shell","io"}
  for _, name in ipairs(names) do
    result[#result + 1] = {
      name = name,
      loaded = package.loaded[name] ~= nil,
    }
  end
  return result
end

return compat
