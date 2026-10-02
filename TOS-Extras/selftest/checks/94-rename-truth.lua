-- What a rename onto an existing file really does on this disk, and
-- whether the answer it gives is the truth (fermi import, d918beb).
--
-- fs.remove and a filesystem rename report failure as a RETURN value and
-- never raise, so `pcall(...)` around them is always true. Two places used
-- the pcall as the verdict:
--   * fs.writeFileAtomic's "cannot replace target" guard could never fire;
--   * PaneUI's Move said "Moved to" for a rename that answered false, which
--     on a host that will not overwrite on rename is every Move onto an
--     existing name.
-- Both now judge by the result and by what is on disk. Off-box, what a
-- rename does to an existing destination is whatever the stub says. This
-- asks the real boot disk -- a host-backed directory, unlike /tmp, which
-- is an in-memory filesystem with its own rename rules -- and checks that
-- the answer matches the files. It also runs writeFileAtomic over an
-- existing file here, which is the path the remove-then-rename guard is on.
--
-- Not covered: a target that will not go (read-only disk, pinned file).
-- That needs a disk in a state the battery cannot safely make.
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
