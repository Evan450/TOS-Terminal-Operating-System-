-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Shell - Program environment builder                 ║
-- ║                                                            ║
-- ║  `makeProgramEnv` used to live inside shell/panels/init.lua ║
-- ║  as a closure. It is one of the seventeen deps the command  ║
-- ║  registry takes, and the CLI needs exactly the same builder ║
-- ║  — so leaving it there would have meant either loading the  ║
-- ║  whole panels TUI to reach it, or writing a second one.     ║
-- ║  A second sandbox-env builder is the last thing this        ║
-- ║  codebase should have: it is a security surface, and two    ║
-- ║  copies drift.                                              ║
-- ║                                                            ║
-- ║  Behaviour is byte-for-byte what panels/init.lua did,       ║
-- ║  including the no-sandbox fallback — that path exists for   ║
-- ║  early boot and for a machine whose kernel.sandbox failed   ║
-- ║  to load, and narrowing it here would change what a         ║
-- ║  recovery shell can run.                                   ║
-- ╚══════════════════════════════════════════════════════════╝

local M = {}

--- Build a makeProgramEnv(opts) bound to shell state `S`.
-- @param S  shell state; only S.cwd and S.U are read, and both are read
--           at CALL time so a `cd` between program runs is honoured.
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
      -- No kernel.sandbox: hand back a bare, pure-Lua environment. No
      -- component, no computer, no fs — a program gets arithmetic and
      -- its own stdout, which is the correct amount of authority to
      -- grant when the thing that enforces authority did not load.
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
