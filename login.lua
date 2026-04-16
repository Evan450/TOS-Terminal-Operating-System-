-- ╔══════════════════════════════════════╗
-- ║  TOS Login Screen                    ║
-- ║  Authentication before shell access  ║
-- ╚══════════════════════════════════════╝

local computer = require("computer")

local login = {}

-- Module references
local display, event, usermod, proc, log
local W, H

-- ============================================================
-- Login screen rendering
-- ============================================================

local function drawLoginScreen(message, isError)
  local theme = display.getTheme()
  local bgColor = theme.bg       -- Use theme bg (palette-safe)
  local fgColor = theme.fg
  local borderColor = theme.border
  local titleColor = theme.title
  local dimColor = theme.dim

  display.clear(bgColor)

  -- TOS banner (compact)
  local bannerY = 2
  if H >= 20 then
    display.set(math.floor(W / 2) - 12, bannerY,     "========================", borderColor, bgColor)
    display.set(math.floor(W / 2) - 12, bannerY + 1,  "    T O S  Login        ", titleColor, bgColor)
    display.set(math.floor(W / 2) - 12, bannerY + 2,  "  Terminal OS v" ..
      display.fit((_G._TOS and _G._TOS.version) or "?", 9), dimColor, bgColor)
    display.set(math.floor(W / 2) - 12, bannerY + 3,  "========================", borderColor, bgColor)
    bannerY = bannerY + 5
  else
    display.set(math.floor(W / 2) - 8, bannerY, "=== TOS Login ===", borderColor, bgColor)
    bannerY = bannerY + 2
  end

  -- Login box
  local boxW = math.min(40, W - 4)
  local boxH = 8
  local boxX = math.floor((W - boxW) / 2) + 1
  local boxY = bannerY + 1

  -- Draw box with theme-safe colors
  local boxBg = theme.panel_bg
  display.dbox(boxX, boxY, boxW, boxH, "Authentication", {
    bg = boxBg,
    border = borderColor,
    title = titleColor,
  })

  -- Username label
  display.set(boxX + 2, boxY + 2, "Username:", dimColor, boxBg)
  -- Password label
  display.set(boxX + 2, boxY + 4, "Password:", dimColor, boxBg)

  -- Message area (below box)
  if message then
    local msgColor = isError and theme.error or theme.highlight
    local msgX = math.floor((W - #message) / 2)
    display.set(math.max(1, msgX), boxY + boxH + 1, message, msgColor, bgColor)
  end

  -- Hint at bottom
  local hint = "Enter credentials (Ctrl+Q to cancel)"
  display.set(math.floor((W - #hint) / 2), H - 1, hint, dimColor, bgColor)

  return boxX, boxY, boxW
end

local function drawInput(boxX, boxY, boxW, field, value, active)
  local theme = display.getTheme()
  local fieldY = (field == "username") and (boxY + 2) or (boxY + 4)
  local inputX = boxX + 12
  local inputW = boxW - 14

  local bg = active and theme.input_bg or theme.panel_bg
  local fg = active and theme.input_fg or theme.dim

  -- Clear field area
  display.fill(inputX, fieldY, inputW, 1, " ", fg, bg)

  -- Show value (mask password)
  local shown = value
  if field == "password" then
    shown = string.rep("*", #value)
  end
  shown = display.fit(shown, inputW - 1)
  display.set(inputX, fieldY, shown, fg, bg)

  -- Cursor
  if active then
    local cursorPos = inputX + math.min(#value, inputW - 1)
    display.set(cursorPos, fieldY, "_", theme.highlight, bg)
  end
end

-- ============================================================
-- Input handling
-- ============================================================

local function readInput(boxX, boxY, boxW, field, maxLen)
  maxLen = maxLen or 20
  local value = ""

  while true do
    drawInput(boxX, boxY, boxW, field, value, true)

    -- Use computer.pullSignal directly - most reliable on OC
    local sig, _, char, code = computer.pullSignal(0.5)

    if sig == "key_down" then
      if code == 28 then  -- Enter
        return value
      elseif code == 14 then  -- Backspace
        if #value > 0 then
          value = value:sub(1, -2)
        end
      elseif char == 17 then  -- Ctrl+Q = cancel
        return nil
      elseif char and char >= 32 and char < 127 and #value < maxLen then
        value = value .. string.char(char)
      end
    elseif sig == "clipboard" then
      -- Handle paste (OC clipboard signal)
      local pastedText = char  -- Third argument is the pasted string
      if type(pastedText) == "string" then
        value = value .. pastedText:sub(1, maxLen - #value)
      end
    end
    -- NO proc.yield here - it eats keyboard signals on main thread!
  end
end

-- ============================================================
-- First-boot password change
-- ============================================================

local function firstBootSetup()
  local theme = display.getTheme()
  local bgColor = theme.bg
  local boxBg = theme.panel_bg
  display.clear(bgColor)

  local boxW = math.min(50, W - 4)
  local boxH = 12
  local boxX = math.floor((W - boxW) / 2) + 1
  local boxY = math.floor((H - boxH) / 2) + 1

  display.dbox(boxX, boxY, boxW, boxH, "First Boot Setup", {
    bg = boxBg,
    border = theme.title,
    title = theme.title,
  })

  display.set(boxX + 2, boxY + 2, "Welcome to TOS!", theme.highlight, boxBg)
  display.set(boxX + 2, boxY + 3, "Please set a new root password.", theme.dim, boxBg)
  display.set(boxX + 2, boxY + 5, "New password:", theme.dim, boxBg)
  display.set(boxX + 2, boxY + 7, "Confirm:", theme.dim, boxBg)

  -- Read new password
  local inputX = boxX + 16
  local inputW = boxW - 18

  local pass1, pass2

  while true do
    -- First password
    display.fill(inputX, boxY + 5, inputW, 1, " ", theme.input_fg, theme.input_bg)
    display.set(inputX, boxY + 5, "_", theme.highlight, theme.input_bg)

    pass1 = ""
    while true do
      display.fill(inputX, boxY + 5, inputW, 1, " ", theme.input_fg, theme.input_bg)
      display.set(inputX, boxY + 5, string.rep("*", #pass1), theme.input_fg, theme.input_bg)
      display.set(inputX + #pass1, boxY + 5, "_", theme.highlight, theme.input_bg)

      local sig, _, char, code = computer.pullSignal(0.5)
      if sig == "key_down" then
        if code == 28 then break
        elseif code == 14 then
          if #pass1 > 0 then pass1 = pass1:sub(1, -2) end
        elseif char and char >= 32 and char < 127 and #pass1 < 30 then
          pass1 = pass1 .. string.char(char)
        end
      end
    end

    -- Confirm password
    pass2 = ""
    while true do
      display.fill(inputX, boxY + 7, inputW, 1, " ", theme.input_fg, theme.input_bg)
      display.set(inputX, boxY + 7, string.rep("*", #pass2), theme.input_fg, theme.input_bg)
      display.set(inputX + #pass2, boxY + 7, "_", theme.highlight, theme.input_bg)

      local sig, _, char, code = computer.pullSignal(0.5)
      if sig == "key_down" then
        if code == 28 then break
        elseif code == 14 then
          if #pass2 > 0 then pass2 = pass2:sub(1, -2) end
        elseif char and char >= 32 and char < 127 and #pass2 < 30 then
          pass2 = pass2 .. string.char(char)
        end
      end
    end

    -- Validate
    if #pass1 < 6 then
      display.set(boxX + 2, boxY + 9, "Password must be 6+ characters!   ", theme.error, boxBg)
    elseif pass1 ~= pass2 then
      display.set(boxX + 2, boxY + 9, "Passwords don't match! Try again.  ", theme.error, boxBg)
    else
      -- Success
      local ok, err = usermod.changePassword("root", "root", "root", pass1)
      if ok then
        display.set(boxX + 2, boxY + 9, "Password set! Starting TOS...      ", theme.highlight, boxBg)
        local dl = computer.uptime() + 1.5
        while computer.uptime() < dl do computer.pullSignal(dl - computer.uptime()) end
        return true
      else
        display.set(boxX + 2, boxY + 9, "Error: " .. tostring(err), theme.error, boxBg)
      end
    end

    -- Clear inputs for retry (wait full duration so user can read error)
    display.fill(inputX, boxY + 5, inputW, 1, " ", theme.input_fg, boxBg)
    display.fill(inputX, boxY + 7, inputW, 1, " ", theme.input_fg, boxBg)
    local dl = computer.uptime() + 1.5
    while computer.uptime() < dl do computer.pullSignal(dl - computer.uptime()) end
  end
end

-- ============================================================
-- Guest login option
-- ============================================================

local function showGuestOption(boxX, boxY, boxW)
  local theme = display.getTheme()
  local hint = "F2: Guest access"
  local hx = boxX + math.floor((boxW - #hint) / 2)
  display.set(math.max(1, hx), boxY + 9, hint, theme.dim, theme.bg)
end

-- ============================================================
-- Main login flow
-- ============================================================

-- Run the first-boot tutorial if it hasn't been seen yet
local function tryTutorial(token)
  -- Prefer securefs so the marker write (/etc/.tutorial_done) goes through
  -- permission checks; fall back to raw fs only if securefs isn't ready.
  local fs = (_G._TOS and _G._TOS.securefs) or nil
  if not fs then
    pcall(function() fs = require("kernel.fs") end)
  end
  if not fs then return end

  local ok2, tut = pcall(require, "shell.tutorial")
  if ok2 and tut.shouldShow(fs) then
    tut.run({
      D  = display,
      F  = fs,
      U  = usermod,
      st = token,
      W  = W,
      H  = H,
    })
  end
end

function login.run(modules)
  display = modules.display
  event   = modules.event
  usermod = modules.users
  proc    = modules.proc
  log     = modules.log

  W, H = display.getSize()

  -- Check for first boot
  local rootUser = usermod.getUser("root")
  if rootUser and rootUser.firstBoot then
    local token = usermod.login("root", "root")
    if token then
      local ok = firstBootSetup()
      if ok then
        -- Optional: clear the session flag too, so you don't re-trigger off the token
        local s = usermod.getSession(token)
        if s then s.firstBoot = nil end
        -- Show first-boot tutorial
        tryTutorial(token)
        return token
      end
    end
  end

  -- Check if guest access is enabled
  local guestOk = usermod.guestEnabled and usermod.guestEnabled() or false

  -- Main login loop
  while true do
    local boxX, boxY, boxW = drawLoginScreen()

    -- Show guest hint if enabled
    if guestOk then showGuestOption(boxX, boxY, boxW) end

    -- Username input
    drawInput(boxX, boxY, boxW, "password", "", false)

    -- Custom read loop that also watches for F2 (guest login)
    local username = nil
    local guestRequested = false
    local cancelRequested = false
    local value = ""

    while true do
      drawInput(boxX, boxY, boxW, "username", value, true)
      local sig, _, char, code = computer.pullSignal(0.5)
      if sig == "key_down" then
        if code == 28 then  -- Enter
          username = value
          break
        elseif code == 14 then  -- Backspace
          if #value > 0 then value = value:sub(1, -2) end
        elseif char == 17 then  -- Ctrl+Q
          cancelRequested = true
          break
        elseif code == 60 and guestOk then  -- F2 = guest login
          guestRequested = true
          break
        elseif char and char >= 32 and char < 127 and #value < 20 then
          value = value .. string.char(char)
        end
      elseif sig == "clipboard" then
        if type(char) == "string" then
          value = value .. char:sub(1, 20 - #value)
        end
      end
    end

    -- Handle guest login via F2
    if guestRequested then
      drawLoginScreen("Logging in as Guest...", false)
      local token, err = usermod.guestLogin()
      if token then
        local session = usermod.getSession(token)
        drawLoginScreen("Welcome, Guest!", false)
        if _G._TOS and _G._TOS.audio then _G._TOS.audio.confirm() end
        computer.pullSignal(1)
        tryTutorial(token)
        return token
      else
        drawLoginScreen(err or "Guest login failed", true)
        if _G._TOS and _G._TOS.audio then _G._TOS.audio.error() end
        local deadline = computer.uptime() + 2
        while computer.uptime() < deadline do
          computer.pullSignal(deadline - computer.uptime())
        end
      end
    elseif cancelRequested then
      -- Escape pressed - show options
      drawLoginScreen("Enter to retry, F10 to shut down", false)
      while true do
        local sig2, _, _, code2 = computer.pullSignal(1)
        if sig2 == "key_down" then
          if code2 == 28 then break
          elseif code2 == 68 then return nil, "shutdown" end
        end
      end
    elseif username and username ~= "" then
      -- Password input
      drawInput(boxX, boxY, boxW, "username", username, false)
      local password = readInput(boxX, boxY, boxW, "password", 30)

      if password then
        -- Attempt login
        drawLoginScreen("Authenticating...", false)

        local token, err = usermod.login(username, password)
        if token then
          -- Success!
          local session = usermod.getSession(token)
          if not session then
            drawLoginScreen("Session error - please retry", true)
            local deadline = computer.uptime() + 2
            while computer.uptime() < deadline do
              computer.pullSignal(deadline - computer.uptime())
            end
          else
            local msg = "Welcome, " .. (session.displayName or username) .. "!"
            drawLoginScreen(msg, false)
            if _G._TOS and _G._TOS.audio then _G._TOS.audio.confirm() end
            computer.pullSignal(1)

            if session.firstBoot then
              firstBootSetup()
            end

            tryTutorial(token)
            return token
          end
        else
          -- Failure
          drawLoginScreen(err or "Login failed", true)
          if _G._TOS and _G._TOS.audio then _G._TOS.audio.error() end
          local deadline = computer.uptime() + 2
          while computer.uptime() < deadline do
            computer.pullSignal(deadline - computer.uptime())
          end
        end
      end
    end
    -- NO proc.yield() - computer.pullSignal already yields
  end
end

--- Quick login for single-user / recovery mode
function login.autoLogin(username, password)
  return usermod.login(username, password)
end

return login
