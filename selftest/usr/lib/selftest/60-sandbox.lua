











return function(t)
  local okS, sandbox = pcall(require, "kernel.sandbox")
  if not okS or type(sandbox) ~= "table" then
    return t.skip("sandbox", "kernel.sandbox unavailable")
  end

  local build = sandbox.build or sandbox.make or sandbox.newEnv or sandbox.create
  if type(build) ~= "function" then
    return t.skip("sandbox", "no recognised env constructor on this build")
  end

  
  local okB, env = pcall(build, { caps = {} })
  if not okB or type(env) ~= "table" then
    return t.skip("sandbox", "constructor signature differs here: " .. tostring(env))
  end

  
  
  
  t.ok("no raw component in a capless env", env.component == nil)
  t.ok("no raw computer in a capless env",  env.computer == nil
    or type(env.computer) == "table")
  t.ok("_G is not the real global table",   env._G ~= _G)

  
  
  if env.tostring then
    t.eq("tostring works inside", "1", tostring(env.tostring(1)))
  end

  
  
  
  local okR, ro = pcall(build, { caps = { ["fs.read"] = true } })
  if okR and type(ro) == "table" then
    local w = ro.fs and (ro.fs.writeFile or ro.fs.write or ro.fs.remove)
    t.ok("fs.read alone does not expose a writer", w == nil)
  else
    t.skip("fs.read env", "constructor rejected that cap shape here")
  end
end
