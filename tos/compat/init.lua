local compat = {}

function compat.init(opts)
  opts = opts or {}

  if compat._initCounts then
    if opts.procSleep and compat.setProcSleep then
      compat.setProcSleep(opts.procSleep)
    end
    return compat._initCounts[1], compat._initCounts[2]
  end

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

    ["internet"]      = "compat.internet",
  }

  local loaded = 0
  local failed = 0

  for openosName, tosPath in pairs(shims) do
    local ok, mod = pcall(require, tosPath)
    if ok then

      package.loaded[openosName] = mod
      loaded = loaded + 1
    else

      failed = failed + 1
    end
  end

  if package.loaded["io"] then
    _G.io = package.loaded["io"]
  end

  do
    local rawComp = require("component")

    if not rawComp.isAvailable then
      rawComp.isAvailable = function(ctype)
        local addr = rawComp.list(ctype)()
        return addr ~= nil
      end
    end

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

    if not rawComp.getPrimary then
      rawComp.getPrimary = function(ctype)
        local addr = rawComp.list(ctype)()
        if addr then return rawComp.proxy(addr) end
        return nil, "no primary " .. tostring(ctype) .. " component"
      end
    end

    local proxyCache = setmetatable({}, { __mode = "v" })
    local componentFieldAccess = setmetatable({}, {
      __index = function(_, key)

        if rawComp[key] ~= nil then return rawComp[key] end

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

    package.loaded["compat.component"] = componentFieldAccess
  end

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

  if not _G.os then _G.os = {} end

  do
    local computer2 = require("computer")
    local _procSleep = opts.procSleep

    _G.os.sleep = function(seconds)
      seconds = tonumber(seconds) or 0
      if seconds <= 0 then

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

        local deadline = computer2.uptime() + seconds
        while computer2.uptime() < deadline do
          local remaining = deadline - computer2.uptime()
          computer2.pullSignal(math.min(remaining, 0.5))
        end
      end
    end

    function compat.setProcSleep(fn)
      _procSleep = fn
    end
  end

  if not _G.os.getenv then
    local envVars = {
      HOME = "/home",
      SHELL = "/tos/shell/init.lua",
      TERM = "tos",
      PATH = "/usr/bin:/bin",
    }

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

          rand = tostring(require("computer").uptime() * 1e6)
            .. "_" .. (tostring({}):match("0x(%x+)") or "fallback")
        end
        local path = "/tmp/tos_tmp_" .. rand
        if fsMod and fsMod.exists then
          if not fsMod.exists(path) then

            pcall(fsMod.writeFile, path, "")
            return path
          end
        else
          return path
        end
      end

      error("os.tmpname: could not allocate unique tmp file")
    end
  end

  compat._initCounts = { loaded, failed }
  return loaded, failed
end

function compat.has(name)
  return package.loaded[name] ~= nil
end

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
