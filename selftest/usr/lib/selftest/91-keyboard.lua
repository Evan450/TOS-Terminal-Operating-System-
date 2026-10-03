
















return function(t)
  local kb = component.list("keyboard")()
  if not kb then return t.skip("keyboard", "no keyboard on this machine") end

  local okM, methods = pcall(component.methods, kb)
  if okM and type(methods) == "table" then
    t.ok("the keyboard component has no isKeyDown method (H-03's premise)",
      methods.isKeyDown == nil)
  else
    t.skip("keyboard methods", "component.methods failed: " .. tostring(methods))
  end

  local okK, keyboard = pcall(require, "compat.keyboard")
  if not okK or type(keyboard) ~= "table" then
    return t.skip("compat.keyboard", "does not load here: " .. tostring(keyboard))
  end

  local function answers(name, f, ...)
    local ok, v = pcall(f, ...)
    t.ok(name .. " returns a boolean and does not raise"
      .. (ok and "" or (" (raised: " .. tostring(v) .. ")")),
      ok and type(v) == "boolean")
  end
  answers("isKeyDown(scancode)", keyboard.isKeyDown, keyboard.keys.c or 46)
  answers("isKeyDown(\"c\")", keyboard.isKeyDown, "c")
  answers("isControlDown()", keyboard.isControlDown)
  answers("isAltDown()", keyboard.isAltDown)
  answers("isShiftDown()", keyboard.isShiftDown)

  
  
  local okC, ctrl = pcall(keyboard.isControlDown)
  t.ok("no key reads as held during boot", okC and ctrl == false)
end
