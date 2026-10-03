


















return function(t)
  local fs = _G._TOS and _G._TOS.fs
  if not fs then return t.skip("rename truth", "no filesystem module") end

  local dir = "/var/selftest-rename-" .. tostring(math.floor(computer.uptime() * 100))
  if not fs.makeDirectory(dir) then
    return t.skip("rename truth", "could not make " .. dir)
  end
  local a, b = dir .. "/a.txt", dir .. "/b.txt"

  local okRun, err = pcall(function()
    fs.writeFile(a, "from a")
    fs.writeFile(b, "from b")
    local okR, r = pcall(fs.rename, a, b)
    local answered = (okR and r) and true or false
    local aGone, bNow = not fs.exists(a), fs.readFile(b)
    local truthful
    if answered then truthful = aGone and bNow == "from a"
    else truthful = (not aGone) and bNow == "from b" end
    t.ok("rename onto an existing file answered " .. tostring(answered)
      .. (answered and ", and did overwrite" or ", and left both files alone")
      .. ": the answer matches the disk", truthful)

    local target = dir .. "/atomic.txt"
    fs.writeFile(target, "old")
    local okW, werr = fs.writeFileAtomic(target, "new")
    t.ok("writeFileAtomic replaces an existing file on this disk"
      .. (okW and "" or (" (" .. tostring(werr) .. ")")),
      okW and fs.readFile(target) == "new")
    t.ok("...and leaves no .tos-tmp behind", not fs.exists(target .. ".tos-tmp"))
  end)

  for _, p in ipairs({ a, b, dir .. "/atomic.txt", dir .. "/atomic.txt.tos-tmp" }) do
    if fs.exists(p) then fs.remove(p) end
  end
  fs.remove(dir)
  t.ok("cleaned up", not fs.exists(dir))
  if not okRun then error(err, 0) end
end
