
















return function(t)
  local okS, srm = pcall(require, "kernel.srm")
  if not okS or type(srm) ~= "table" then
    return t.skip("srm", "kernel.srm unavailable")
  end
  local fs = _G._TOS and _G._TOS.fs
  if not fs then return t.skip("srm", "no filesystem") end

  local scratch  = "/tmp/srm-selftest-" .. tostring(math.floor(computer.uptime() * 100))
  local subject  = scratch .. "/subject.lua"
  local ORIGINAL = "-- v1\nreturn 1\n"

  local saved = { DIR = srm.DIR, INDEX = srm.INDEX, STORE = srm.STORE, LAST = srm.LAST }
  local function restorePaths()
    srm.DIR, srm.INDEX, srm.STORE, srm.LAST = saved.DIR, saved.INDEX, saved.STORE, saved.LAST
  end

  local ok, err = pcall(function()
    fs.makeDirectory(scratch)
    fs.writeFile(subject, ORIGINAL)
    srm.DIR   = scratch .. "/srm"
    srm.INDEX = srm.DIR .. "/index.dat"
    srm.STORE = srm.DIR .. "/store"
    srm.LAST  = srm.DIR .. "/last.dat"

    
    local bok, berr = srm.baseline(nil, { paths = { subject }, content = true })
    t.ok("baseline succeeds (" .. tostring(berr) .. ")", bok and true or false)
    t.ok("index was written", fs.exists(srm.INDEX))

    
    if srm.storeUsage then
      local used = srm.storeUsage(nil)
      t.ok("store usage is a number", type(used) == "number" or type(used) == "table")
    end

    
    local rep = srm.scan(nil)
    t.ok("scan returns a report", type(rep) == "table")
    t.eq("no drift before the edit", 0, #(rep.drift or {}))

    
    fs.writeFile(subject, "-- v2 TAMPERED\nreturn 2\n")
    local rep2 = srm.scan(nil)
    t.ok("scan detects the edit", #(rep2.drift or {}) > 0)

    
    if srm.restore then
      srm.restore(nil, { paths = { subject } })
      t.eq("restore returns the original content", ORIGINAL, fs.readFile(subject))
      local rep3 = srm.scan(nil)
      t.eq("and the scan is clean again", 0, #(rep3.drift or {}))
    else
      t.skip("srm.restore", "not present in this build")
    end
  end)

  restorePaths()
  
  pcall(function()
    for _, p in ipairs({ subject }) do if fs.exists(p) then fs.remove(p) end end
    if fs.exists(scratch) then fs.remove(scratch) end
  end)
  t.ok("srm paths restored to the real ones", srm.INDEX == saved.INDEX)
  if not ok then t.ok("srm check body: " .. tostring(err), false) end
end
