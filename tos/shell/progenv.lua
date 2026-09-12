local M = {}

function M.builder(S)
  local sandboxMod = nil
  local function getSandbox()
    if sandboxMod == nil then
      local ok, mod = pcall(require, "kernel.sandbox")
      sandboxMod = ok and mod or false
    end
    return sandboxMod or nil
  end

  return function(opts)
    opts = opts or {}
    local sb = getSandbox()
    if not sb then

      --! #SEC (pentest, Sep 2026) — and its OWN copies of math/string/table,
      --! with no getmetatable. This handed over the real libraries and the
      --! real getmetatable, so getmetatable("").__index was the VM-wide
      --! string library: `string.format = f` ran f inside the kernel on its
      --! next log line. It is also the path taken when kernel.sandbox fails
      --! to load -- which on a 192 KB box can simply be memory -- and the
      --! failure is cached for the life of the shell.
      local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end
      local env = {
        assert = assert, error = error, pcall = pcall, xpcall = xpcall,
        type = type, tostring = tostring, tonumber = tonumber,
        pairs = pairs, ipairs = ipairs, next = next, select = select,
        setmetatable = setmetatable,
        math = copy(math), string = copy(string), table = copy(table),
        print = opts.stdout or print,
      }
      env._G = env
      return env
    end
    local caps = {
      ["fs.read"]   = true,
      ["fs.write"]  = true,
      ["compat.io"] = true,
    }
    if opts.caps then
      for k, v in pairs(opts.caps) do caps[k] = v end
    end
    return sb.build{
      name    = opts.name or "shell:program",
      cwd     = S.cwd,
      session = (S.U and S.U.currentSession and S.U.currentSession()) or nil,
      caps    = caps,
      stdout  = opts.stdout,
    }
  end
end

return M
