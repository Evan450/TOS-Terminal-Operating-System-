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

      local env = {
        assert = assert, error = error, pcall = pcall, xpcall = xpcall,
        type = type, tostring = tostring, tonumber = tonumber,
        pairs = pairs, ipairs = ipairs, next = next, select = select,
        setmetatable = setmetatable, getmetatable = getmetatable,
        math = math, string = string, table = table,
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
