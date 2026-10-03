


























local mouse = {}









function mouse.parse(name, screen, x, y, k, player)
  if name == "touch" then
    return { type = "click", x = x, y = y, button = k or 0,
             screen = screen, player = player }
  elseif name == "drag" then
    return { type = "drag", x = x, y = y, button = k or 0,
             screen = screen, player = player }
  elseif name == "drop" then
    return { type = "drop", x = x, y = y, button = k or 0,
             screen = screen, player = player }
  elseif name == "scroll" then
    
    local dir = (k or 0) >= 0 and 1 or -1
    return { type = "scroll", x = x, y = y, dir = dir,
             screen = screen, player = player }
  end
  return nil
end



function mouse.isMouse(name)
  return name == "touch" or name == "drag"
      or name == "drop"  or name == "scroll"
end






function mouse.pull(timeout)
  local computer = require("computer")
  local deadline = computer.uptime() + (timeout or math.huge)
  repeat
    local remaining = deadline - computer.uptime()
    if remaining < 0 then remaining = 0 end
    local sig = table.pack(computer.pullSignal(remaining))
    local ev = mouse.parse(table.unpack(sig, 1, sig.n))
    if ev then return ev end
  until computer.uptime() >= deadline
  return nil
end





function mouse.region(x, y, w, h, payload)
  return { x = x, y = y, w = w, h = h, payload = payload }
end


function mouse.inside(r, px, py)
  return px >= r.x and px <= r.x + r.w - 1
     and py >= r.y and py <= r.y + r.h - 1
end




function mouse.hit(regions, px, py)
  for _, r in ipairs(regions) do
    if mouse.inside(r, px, py) then return r.payload, r end
  end
  return nil
end

mouse._VERSION = "1.1.0"
return mouse
