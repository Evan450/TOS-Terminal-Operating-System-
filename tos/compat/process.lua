-- TOS OpenOS Compatibility - process
-- The read-only half of OpenOS's lib/process: info() and running().
--
--! WHAT PROGRAMS ACTUALLY USE THIS FOR, because it decides the whole
--! design: not introspection, but FINDING THEIR OWN FILES. Every real use
--! measured across the OpenComputers loot disks and the OpenPrograms
--! corpus is some spelling of
--!     fs.path(process.running())            -- builder/build.lua
--!     fs.concat(fs.path(shell.resolve(process.running())), "/data")
--!     shell.resolve(process.info().path, "lua")
--! i.e. "where is the script I am, so I can read the file next to it".
--! That makes `path` the ONLY field worth getting right, and it makes a
--! WRONG path worse than no path: a program handed a plausible-but-wrong
--! path writes its state file somewhere the operator will never find it,
--! where nil makes it fail at the call that needed the answer.
--!
--! So: `path` is the program path the shell launched, threaded in by
--! sandbox.lua (which holds it as opts.name) through _forProgram below.
--! Outside a sandbox -- the kernel, a recovery shell -- there is no
--! launcher to ask and `path` is nil. TOS does not otherwise record a
--! per-process program path; the process record carries a NAME
--! ("prog:tetris@1"), which is not a path and is not offered as one.
--!
--! NOT PROVIDED, deliberately: load(), internal.*, addHandle/removeHandle
--! and the `list` weak table. Those are how OpenOS's own shell spawns and
--! reaps coroutines; ours is kernel.process, and a compat shim that let a
--! program create processes through a second, unsupervised path would put
--! coroutines outside the scheduler's budgets and outside the cap system.
--! A program that calls process.load() on TOS gets a clear nil-call error
--! at the call site, which is the honest answer. (test_compat_process.lua)

local process = {}

local function currentProc()
  local okP, procMod = pcall(require, "kernel.process")
  if not okP or type(procMod) ~= "table" or not procMod.current then return nil end
  local ok, cur = pcall(procMod.current)
  if not ok then return nil end
  return cur
end

--- Information about a running program.
-- @param levelOrThread number|thread  stack level (1 = caller) or coroutine
-- @return table|nil  { path, env, command, data } as OpenOS shapes it
function process.info(levelOrThread)
  local t = type(levelOrThread)
  if t ~= "nil" and t ~= "number" and t ~= "thread" then
    error("bad argument #1 (thread, number or nil expected, got " .. t .. ")", 2)
  end
  --! A LEVEL is accepted and IGNORED past level 1, and a thread is only
  --! answered for when it is the running one. OpenOS walks a parent chain
  --! of its own process records to answer "who called my caller"; our
  --! processes are scheduler entries, and inventing a parent walk that
  --! returned a DIFFERENT program's path would feed the path-finding use
  --! above with the wrong answer. Level 1 (the default, and what every
  --! measured caller passes) is exact; deeper levels return the same
  --! record rather than a guess.
  local cur = currentProc()
  if not cur then return nil end
  return {
    path    = cur.progPath,      -- nil unless a launcher recorded one
    command = cur.name,
    env     = nil,               -- rebound per sandbox by _forProgram
    data    = { vars = {} },
  }
end

--- Legacy accessor: path, env, command.
function process.running(level)
  local info = process.info(level)
  if info then return info.path, info.env, info.command end
  return nil
end

--! Kernel-only builder. sandbox.lua calls this with the program name it
--! was constructed with and overrides .info/.running on that sandbox's
--! module view, so a program asks about ITSELF and gets its own launch
--! path. Masked from the sandbox view (HIDDEN_MODULE_KEYS) for the same
--! reason every other kernel hook on a compat module is: a hook a
--! sandboxed program can call is part of the sandbox's API whether it was
--! meant to be or not (#SEC AUDIT 5, H-01).
--!   Forging a path would not BE authority -- every file access still
--! goes through securefs with the caller's own ACLs, so a program that
--! lied to itself about its path would only mislead itself -- but the
--! uniform rule is cheaper to keep than the exception is to argue.
function process._forProgram(name, env)
  --! Only a path-shaped launch name becomes a path. The executor names
  --! seat-bound processes "prog:<cmd>@<seat>" and the CLI may pass a bare
  --! command word; neither is a path, and returning one would be the
  --! wrong-answer failure this module exists to avoid.
  local path = nil
  if type(name) == "string" and name:find("/", 1, true)
     and not name:find("^prog:") then
    path = name
  end
  local bound = {}
  function bound.info(levelOrThread)
    local info = process.info(levelOrThread)
    if not info then return nil end
    info.path = path or info.path
    info.env  = env
    if path then info.command = path end
    return info
  end
  function bound.running(level)
    local info = bound.info(level)
    if info then return info.path, info.env, info.command end
    return nil
  end
  return bound
end

return process
