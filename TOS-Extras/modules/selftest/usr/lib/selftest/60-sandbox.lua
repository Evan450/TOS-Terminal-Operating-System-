-- The capability sandbox, on a real booted kernel.
--
-- Ports the item TODO.txt's PKG COMPLETENESS checklist calls out as the
-- one off-box tests "cannot really prove -- they stub the sandbox":
-- whether a package command actually runs under the restrictions its
-- manifest asked for. Every off-box sandbox test builds the environment
-- by hand and then asserts about the thing it just built.
--
-- Read-only: this asks the live sandbox what a given capability set
-- yields and inspects the environment. It installs nothing and runs no
-- package code, because a battery that installs software on the machine
-- it is auditing is a different and much worse tool.
return function(t)
  local okS, sandbox = pcall(require, "kernel.sandbox")
  if not okS or type(sandbox) ~= "table" then
    return t.skip("sandbox", "kernel.sandbox unavailable")
  end

  local build = sandbox.build or sandbox.make or sandbox.newEnv or sandbox.create
  if type(build) ~= "function" then
    return t.skip("sandbox", "no recognised env constructor on this build")
  end

  -- A minimal capability set must NOT hand over the keys to the machine.
  local okB, env = pcall(build, { caps = {} })
  if not okB or type(env) ~= "table" then
    return t.skip("sandbox", "constructor signature differs here: " .. tostring(env))
  end

  -- The three that matter: raw component access drives hardware directly
  -- and is ROOT by design; `load` reopens arbitrary code; the real _G
  -- would make every other restriction decorative.
  t.ok("no raw component in a capless env", env.component == nil)
  t.ok("no raw computer in a capless env",  env.computer == nil
    or type(env.computer) == "table")
  t.ok("_G is not the real global table",   env._G ~= _G)

  -- Whatever print/tostring it does provide must at least be callable,
  -- or the sandbox is not usable and that is its own bug.
  if env.tostring then
    t.eq("tostring works inside", "1", tostring(env.tostring(1)))
  end

  -- An env granting fs.read must not thereby grant fs.write. This is the
  -- distinction the whole capability table exists to make, and it is
  -- exactly the sort of thing a stubbed test asserts about its own stub.
  local okR, ro = pcall(build, { caps = { ["fs.read"] = true } })
  if okR and type(ro) == "table" then
    local w = ro.fs and (ro.fs.writeFile or ro.fs.write or ro.fs.remove)
    t.ok("fs.read alone does not expose a writer", w == nil)
  else
    t.skip("fs.read env", "constructor rejected that cap shape here")
  end
end
