



















return function(t)
  local okN, net = pcall(require, "kernel.net")
  if not okN or type(net) ~= "table" or type(net.waitFor) ~= "function" then
    return t.skip("net.waitFor", "kernel.net unavailable")
  end
  local okE, event = pcall(require, "kernel.event")
  if not okE or type(event) ~= "table" or type(event.on) ~= "function"
     or type(event.off) ~= "function" then
    return t.skip("net.waitFor", "kernel.event unavailable")
  end

  local NAME = "selftest_waitfor_probe"
  local got = false
  local id = event.on(NAME, function() got = true end, "selftest")
  computer.pushSignal(NAME)
  local t0 = computer.uptime()
  local okW, r = pcall(net.waitFor, function() return got end, 2)
  local dt = computer.uptime() - t0
  event.off(NAME, id)

  t.ok(string.format("net.waitFor in kernel context lets a listener see what it waits for"
    .. " (returned %s after %.1f s%s)", tostring(r), dt,
    okW and "" or (", raised: " .. tostring(r))),
    okW and r == true and got)
end
