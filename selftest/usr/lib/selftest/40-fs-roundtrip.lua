







return function(t)
  local fs = _G._TOS and _G._TOS.fs
  if not fs then return t.skip("fs", "no filesystem module") end

  local dir  = "/tmp/selftest-" .. tostring(math.floor(computer.uptime() * 100))
  local file = dir .. "/probe.txt"
  local body = "the quick brown fox\nsecond line\n"

  t.ok("makeDirectory", (fs.makeDirectory(dir)) and true or false)
  t.ok("directory exists after creation", fs.exists(dir))
  t.ok("isDirectory agrees", fs.isDirectory(dir))

  t.ok("writeFile", (fs.writeFile(file, body)) and true or false)
  t.ok("file exists", fs.exists(file))
  t.eq("read round-trips exactly", body, fs.readFile(file))
  t.eq("size matches the bytes written", #body, fs.size(file))
  t.ok("isDirectory is false for a file", not fs.isDirectory(file))

  
  
  
  local found = false
  for _, e in ipairs(fs.list(dir) or {}) do
    if tostring(e):gsub("/$", "") == "probe.txt" then found = true end
  end
  t.ok("list() finds the file we just wrote", found)

  
  
  if fs.writeFileAtomic then
    local atomic = dir .. "/atomic.txt"
    t.ok("writeFileAtomic", (fs.writeFileAtomic(atomic, "x")) and true or false)
    t.eq("atomic content", "x", fs.readFile(atomic))
    
    
    t.ok("no .tos-tmp left behind", not fs.exists(atomic .. ".tos-tmp"))
    fs.remove(atomic)
  else
    t.skip("writeFileAtomic", "not present in this build")
  end

  t.ok("rename", (fs.rename(file, dir .. "/moved.txt")) and true or false)
  t.ok("old path gone after rename", not fs.exists(file))
  t.ok("new path present", fs.exists(dir .. "/moved.txt"))

  fs.remove(dir .. "/moved.txt")
  fs.remove(dir)
  t.ok("cleaned up", not fs.exists(dir))
end
