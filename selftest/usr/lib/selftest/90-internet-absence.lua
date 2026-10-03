


















return function(t)
  local okI, internet = pcall(require, "kernel.internet")
  if not okI or type(internet) ~= "table" then
    return t.skip("internet", "kernel.internet unavailable")
  end

  local st = internet.status()
  t.ok("status() returns a table", type(st) == "table")

  if type(st) == "table" and not st.present then
    t.ok("no card -> a real reason is given, not a bare false",
      type(st.reason) == "string" and #st.reason > 0)
    t.ok("no card -> available() agrees", internet.available() == false)

    
    
    
    local okG, body, err = pcall(internet.get, "http://example.invalid/probe")
    t.ok("get() with no card does not throw", okG)
    if okG then
      t.eq("...and returns no body", nil, body)
      t.ok("...with a reason", type(err) == "string" and #err > 0)
    end
  else
    
    
    
    
    t.skip("no-card path", "a real internet card is present on this machine")
  end

  
  
  
  local okC, config = pcall(require, "kernel.config")
  if not (okC and config and config.get and config.set) then
    return t.skip("kill switch", "kernel.config unavailable")
  end

  
  
  
  local had = config.get("internet")
  local ok, err = pcall(function()
    config.set("internet", false)
    t.ok("isEnabled() honours the switch turned off", internet.isEnabled() == false)
    t.ok("...and available() agrees", internet.available() == false)
    local stOff = internet.status()
    if stOff.present then
      t.ok("switched off -> the reason names the switch, not the card",
        type(stOff.reason) == "string"
          and stOff.reason:find("disabled on this machine", 1, true) ~= nil)
    end

    config.set("internet", true)
    t.ok("isEnabled() flips back on", internet.isEnabled() == true)
  end)
  config.set("internet", had)
  t.eq("config left exactly as found", had, config.get("internet"))
  if not ok then t.ok("kill-switch check: " .. tostring(err), false) end
end
