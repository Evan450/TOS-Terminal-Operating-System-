-- compat.keyboard on a machine that HAS a keyboard (AUDIT 5, H-03).
--
-- The bug: compat.keyboard.isKeyDown called component.keyboard.isKeyDown,
-- and the OC keyboard component has no such method -- it only emits
-- key_down / key_up -- so it RAISED on every machine with a keyboard, and
-- isControlDown (OpenOS's own Ctrl-C test) crashed a ported program on its
-- interrupt path. That premise was read off Ocelot's Keyboard.class; this
-- asks the live component. The fix (kernel.process records held keys from
-- the signals proc.tick routes) is driven off-box by
-- test_compat_keyboard.lua. What only a real machine can say is that these
-- calls return booleans here, with a real keyboard attached, under the
-- real Lua -- the string form goes through utf8.codepoint, which the
-- machine's Lua has to provide.
--
-- Read-only. It pushes no signals: a key_down sent now would reach the
-- login screen as a phantom keystroke, and it does not call proc.tick,
-- which would resume whatever processes exist mid-boot.
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

  -- Nothing is held while the battery runs, so the answer is false. A true
  -- here is a wedged key: the case the 15 s stale rule exists for.
  local okC, ctrl = pcall(keyboard.isControlDown)
  t.ok("no key reads as held during boot", okC and ctrl == false)
end
