local computer = require("computer")

local login = {}

local function pull(timeout)
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
  return computer.pullSignal(timeout or 0.5)
end

local function sleep(sec)
  local dl = computer.uptime() + sec
  while computer.uptime() < dl do pull(dl - computer.uptime()) end
end

local display, event, usermod, proc, log
local W, H

local i18nMod, ustrMod
do
  local ok, m = pcall(require, "kernel.i18n"); if ok then i18nMod = m end
  local ok2, m2 = pcall(require, "kernel.ustr"); if ok2 then ustrMod = m2 end
end
local function t(key, default, ...)
  if i18nMod and i18nMod.t then return i18nMod.t(key, default, ...) end
  if select("#", ...) > 0 then
    local ok, s = pcall(string.format, default, ...)
    if ok then return s end
  end
  return default
end
local function uw(s)
  if ustrMod then return ustrMod.width(s) end
  return #tostring(s or "")
end
local function ufit(s, cols)
  if ustrMod then return ustrMod.fit(s, cols) end
  return tostring(s or ""):sub(1, cols)
end

local function fieldGeom(boxX, boxW)
  local uLbl = t("login.username", "Username:")
  local pLbl = t("login.password", "Password:")
  local lblW = math.max(uw(uLbl), uw(pLbl))
  local maxLblW = boxW - 13
  if lblW > maxLblW then lblW = maxLblW end
  local inputX = boxX + 2 + lblW + 1
  local inputW = boxW - (2 + lblW + 1) - 2
  return uLbl, pLbl, lblW, inputX, inputW
end

local function drawLoginScreen(message, isError)
  local theme = display.getTheme()
  local bgColor = theme.bg
  local fgColor = theme.fg
  local borderColor = theme.border
  local titleColor = theme.title
  local dimColor = theme.dim

  display.clear(bgColor)

  local bannerY = 2
  local ver = display.fit((_G._TOS and _G._TOS.version) or "?", 9)
  local okLogo, logo = pcall(require, "kernel.logo")
  if okLogo and logo and logo.MARK and H >= 20 and W >= (logo.MARK_W + 2) then
    local mx = math.floor((W - logo.MARK_W) / 2) + 1
    for i, ln in ipairs(logo.MARK) do
      display.set(mx, bannerY + i - 1, ln, titleColor, bgColor)
    end
    bannerY = bannerY + #logo.MARK
    local tag = logo.TAGLINE .. "  v" .. ver
    display.set(math.floor((W - #tag) / 2) + 1, bannerY, tag, dimColor, bgColor)
    bannerY = bannerY + 2
  elseif H >= 20 then
    display.set(math.floor(W / 2) - 12, bannerY,     "========================", borderColor, bgColor)
    display.set(math.floor(W / 2) - 12, bannerY + 1,  "    T O S  Login        ", titleColor, bgColor)
    display.set(math.floor(W / 2) - 12, bannerY + 2,  "  Terminal OS v" .. ver, dimColor, bgColor)
    display.set(math.floor(W / 2) - 12, bannerY + 3,  "========================", borderColor, bgColor)
    bannerY = bannerY + 5
  else
    display.set(math.floor(W / 2) - 8, bannerY, "=== TOS Login ===", borderColor, bgColor)
    bannerY = bannerY + 2
  end

  local boxW = math.min(40, W - 4)
  local boxH = 8
  local boxX = math.floor((W - boxW) / 2) + 1
  local boxY = bannerY + 1

  local boxBg = theme.panel_bg
  display.dbox(boxX, boxY, boxW, boxH, t("login.title", "Authentication"), {
    bg = boxBg,
    border = borderColor,
    title = titleColor,
  })

  local uLbl, pLbl, lblW = fieldGeom(boxX, boxW)
  display.set(boxX + 2, boxY + 2, ufit(uLbl, lblW), dimColor, boxBg)
  display.set(boxX + 2, boxY + 4, ufit(pLbl, lblW), dimColor, boxBg)

  if message then
    local msgColor = isError and theme.error or theme.highlight
    local msgX = math.floor((W - uw(message)) / 2)
    display.set(math.max(1, msgX), boxY + boxH + 1, ufit(message, W - 2), msgColor, bgColor)
  end

  if _G._TOS and _G._TOS.unsafeShutdown then
    local warn = ufit(t("login.unsafe",
      "! Last shutdown was unsafe (power loss) - data verified"), W - 2)
    local wColor = theme.warning or theme.error
    local wX = math.floor((W - uw(warn)) / 2)
    display.set(math.max(1, wX), boxY + boxH + 2, warn, wColor, bgColor)
  end

  local hint = t("login.hint", "Enter credentials (Ctrl+Q to cancel)")
  display.set(math.max(1, math.floor((W - uw(hint)) / 2)), H - 1, hint, dimColor, bgColor)

  return boxX, boxY, boxW
end

local function drawInput(boxX, boxY, boxW, field, value, active)
  local theme = display.getTheme()
  local fieldY = (field == "username") and (boxY + 2) or (boxY + 4)

  local _, _, _, inputX, inputW = fieldGeom(boxX, boxW)

  local bg = active and theme.input_bg or theme.panel_bg
  local fg = active and theme.input_fg or theme.dim

  display.fill(inputX, fieldY, inputW, 1, " ", fg, bg)

  local shown = value
  if field == "password" then
    shown = string.rep("*", #value)
  end
  shown = display.fit(shown, inputW - 1)
  display.set(inputX, fieldY, shown, fg, bg)

  if active then
    local cursorPos = inputX + math.min(#value, inputW - 1)
    display.set(cursorPos, fieldY, "_", theme.highlight, bg)
  end
end

local function readInput(boxX, boxY, boxW, field, maxLen)
  maxLen = maxLen or 20
  local value = ""

  while true do
    drawInput(boxX, boxY, boxW, field, value, true)

    local sig, _, char, code = pull(0.5)

    if sig == "key_down" then
      if code == 28 then
        return value
      elseif code == 14 then
        if #value > 0 then
          value = value:sub(1, -2)
        end
      elseif char == 17 then
        return nil
      elseif char and char >= 32 and char < 127 and #value < maxLen then
        value = value .. string.char(char)
      end
    elseif sig == "clipboard" then

      local pastedText = char
      if type(pastedText) == "string" then
        value = value .. pastedText:sub(1, maxLen - #value)
      end
    end
  end
end

local function firstBootSetup(username, oldPassword)

  username = (type(username) == "string" and username ~= "") and username or "root"
  oldPassword = type(oldPassword) == "string" and oldPassword or ""
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
  display.set(boxX + 2, boxY + 3, "Please set a new password for " .. username .. ".", theme.dim, boxBg)
  display.set(boxX + 2, boxY + 5, "New password:", theme.dim, boxBg)
  display.set(boxX + 2, boxY + 7, "Confirm:", theme.dim, boxBg)

  local inputX = boxX + 16
  local inputW = boxW - 18

  local pass1, pass2

  while true do

    display.fill(inputX, boxY + 5, inputW, 1, " ", theme.input_fg, theme.input_bg)
    display.set(inputX, boxY + 5, "_", theme.highlight, theme.input_bg)

    pass1 = ""
    while true do
      display.fill(inputX, boxY + 5, inputW, 1, " ", theme.input_fg, theme.input_bg)
      display.set(inputX, boxY + 5, string.rep("*", #pass1), theme.input_fg, theme.input_bg)
      display.set(inputX + #pass1, boxY + 5, "_", theme.highlight, theme.input_bg)

      local sig, _, char, code = pull(0.5)
      if sig == "key_down" then
        if code == 28 then break
        elseif code == 14 then
          if #pass1 > 0 then pass1 = pass1:sub(1, -2) end
        elseif char and char >= 32 and char < 127 and #pass1 < 30 then
          pass1 = pass1 .. string.char(char)
        end
      end
    end

    pass2 = ""
    while true do
      display.fill(inputX, boxY + 7, inputW, 1, " ", theme.input_fg, theme.input_bg)
      display.set(inputX, boxY + 7, string.rep("*", #pass2), theme.input_fg, theme.input_bg)
      display.set(inputX + #pass2, boxY + 7, "_", theme.highlight, theme.input_bg)

      local sig, _, char, code = pull(0.5)
      if sig == "key_down" then
        if code == 28 then break
        elseif code == 14 then
          if #pass2 > 0 then pass2 = pass2:sub(1, -2) end
        elseif char and char >= 32 and char < 127 and #pass2 < 30 then
          pass2 = pass2 .. string.char(char)
        end
      end
    end

    local msgW = boxW - 4
    local function say(text, color)
      local rows, line = {}, ""
      for word in tostring(text):gmatch("%S+") do
        local cand = (line == "") and word or (line .. " " .. word)
        if #cand <= msgW then line = cand
        else
          if line ~= "" then rows[#rows + 1] = line end

          line = (#word <= msgW) and word or word:sub(1, msgW)
        end
      end
      if line ~= "" then rows[#rows + 1] = line end
      for i = 0, 1 do
        display.fill(boxX + 2, boxY + 9 + i, msgW, 1, " ", theme.dim, boxBg)
        if rows[i + 1] then
          display.set(boxX + 2, boxY + 9 + i, rows[i + 1], color, boxBg)
        end
      end
    end

    if #pass1 < 6 then
      say("Password must be 6+ characters!", theme.error)
    elseif pass1 ~= pass2 then
      say("Passwords don't match! Try again.", theme.error)
    else

      local ok, err = usermod.changePassword(username, username, oldPassword, pass1)
      if ok then
        say("Password set! Starting TOS...", theme.highlight)
        sleep(1.5)
        return true
      else
        local msg = tostring(err)

        if msg:lower():find("read%-only") or _G._TOS_ROOT_READONLY then
          say("Disk is READ-ONLY — install to a writable drive (install.lua).",
            theme.error)
          sleep(4)
        else
          say("Error: " .. msg, theme.error)
        end
      end
    end

    display.fill(inputX, boxY + 5, inputW, 1, " ", theme.input_fg, boxBg)
    display.fill(inputX, boxY + 7, inputW, 1, " ", theme.input_fg, boxBg)
    sleep(1.5)
  end
end

local function showGuestOption(boxX, boxY, boxW)
  local theme = display.getTheme()
  local hint = t("login.guest", "F2: Guest access")
  local hx = boxX + math.floor((boxW - uw(hint)) / 2)
  display.set(math.max(1, hx), boxY + 9, hint, theme.dim, theme.bg)
end

local function tryTutorial(token)

  local fs = (_G._TOS and _G._TOS.securefs) or nil
  if not fs then
    pcall(function() fs = require("kernel.fs") end)
  end
  if not fs then return end

  local session = nil
  if usermod and usermod.getSession and token then
    session = usermod.getSession(token)
  end

  local ok2, tut = pcall(require, "shell.tutorial")
  if ok2 and tut.shouldShow(fs, session) then
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

  local rootUser = usermod.getUser("root")
  if rootUser and rootUser.firstBoot then
    local token = usermod.login("root", "root", { setCurrent = false })
    if token then
      local ok = firstBootSetup("root", "root")
      if ok then

        if usermod.promoteAfterFirstBoot then
          local okP, errP = usermod.promoteAfterFirstBoot(token)
          if not okP and log then
            log.warn("auth", "First-boot promotion refused: " .. tostring(errP))
          end
        else

          local s = usermod.getSession(token)
          if s then s.firstBoot = nil end
        end

        tryTutorial(token)
        return token
      end
    end
  end

  local guestOk = usermod.guestEnabled and usermod.guestEnabled() or false

  local BACKOFF_SCHEDULE = { 2, 5, 15, 60 }
  local BACKOFF_PATH     = "/var/lib/login_backoff.dat"
  local failsByUser = {}
  local lastFailTs  = {}

  do
    local okF, fs = pcall(require, "kernel.fs")
    local okS, ser = pcall(require, "kernel.serialize")
    if okF and okS and fs.exists(BACKOFF_PATH) then
      local raw = fs.readFile(BACKOFF_PATH)
      if raw then
        local ok2, data = pcall(ser.decode, raw, { maxBytes = 8192 })
        if ok2 and type(data) == "table" and type(data.fails) == "table" then
          for u, n in pairs(data.fails) do
            if type(u) == "string" and type(n) == "number" and n >= 0 then
              failsByUser[u] = math.floor(n)
            end
          end
          if type(data.lastFailTs) == "table" then
            for u, t in pairs(data.lastFailTs) do
              if type(u) == "string" and type(t) == "number" then lastFailTs[u] = t end
            end
          end
        end
      end
    end
  end

  local function persistBackoff()

    local okF, fs = pcall(require, "kernel.fs")
    local okS, ser = pcall(require, "kernel.serialize")
    if not (okF and okS) then return end

    if not fs.exists("/var/lib") then pcall(fs.makeDirectory, "/var/lib") end
    pcall(fs.writeFile, BACKOFF_PATH,
      ser.encode({ fails = failsByUser, lastFailTs = lastFailTs }))
  end

  local function backoffSeconds(user)
    local n = failsByUser[user] or 0
    return BACKOFF_SCHEDULE[math.min(n, #BACKOFF_SCHEDULE)] or BACKOFF_SCHEDULE[#BACKOFF_SCHEDULE]
  end

  while true do
    local boxX, boxY, boxW = drawLoginScreen()

    if guestOk then showGuestOption(boxX, boxY, boxW) end

    drawInput(boxX, boxY, boxW, "password", "", false)

    local username = nil
    local guestRequested = false
    local cancelRequested = false
    local value = ""

    while true do
      drawInput(boxX, boxY, boxW, "username", value, true)
      local sig, _, char, code = pull(0.5)
      if sig == "key_down" then
        if code == 28 then
          username = value
          break
        elseif code == 14 then
          if #value > 0 then value = value:sub(1, -2) end
        elseif char == 17 then
          cancelRequested = true
          break
        elseif code == 60 and guestOk then
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

    if guestRequested then
      drawLoginScreen(t("login.guest_auth", "Logging in as Guest..."), false)
      local token, err = usermod.guestLogin()
      if token then
        local session = usermod.getSession(token)
        drawLoginScreen(t("login.welcome_guest", "Welcome, Guest!"), false)
        if _G._TOS and _G._TOS.audio then _G._TOS.audio.confirm() end
        sleep(1)
        tryTutorial(token)
        return token
      else
        drawLoginScreen(err or "Guest login failed", true)
        if _G._TOS and _G._TOS.audio then _G._TOS.audio.error() end
        sleep(2)
      end
    elseif cancelRequested then

      drawLoginScreen(t("login.retry", "Enter to retry, F10 to shut down"), false)
      while true do
        local sig2, _, _, code2 = pull(1)
        if sig2 == "key_down" then
          if code2 == 28 then break
          elseif code2 == 68 then return nil, "shutdown" end
        end
      end
    elseif username == "" then

      drawInput(boxX, boxY, boxW, "username", username, false)
      local password = readInput(boxX, boxY, boxW, "password", 30)
      local okC, colophon = pcall(require, "shell.colophon")
      if okC and colophon and colophon.isTrigger(username, password) then
        pcall(colophon.run, {
          W = W, H = H, theme = display.getTheme(),
          clear = function(bg) display.clear(bg) end,
          set = function(x, y, s, fg, bg) display.set(x, y, s, fg, bg) end,
          pull = function(timeout) return (pull(timeout)) end,
          sleep = sleep,
          uptime = computer.uptime,
          width = uw,
        })
      end

    elseif username and username ~= "" then

      drawInput(boxX, boxY, boxW, "username", username, false)
      local password = readInput(boxX, boxY, boxW, "password", 30)

      if password then

        drawLoginScreen(t("login.authenticating", "Authenticating..."), false)

        local token, err = usermod.login(username, password, { setCurrent = false })
        if token then

          failsByUser[username] = 0
          lastFailTs[username]  = nil
          persistBackoff()
          local session = usermod.getSession(token)
          if not session then
            drawLoginScreen(t("login.session_error", "Session error - please retry"), true)
            sleep(2)
          else
            local msg = t("login.welcome", "Welcome, %s!", session.displayName or username)
            drawLoginScreen(msg, false)
            if _G._TOS and _G._TOS.audio then _G._TOS.audio.confirm() end
            sleep(1)

            if session.firstBoot then
              firstBootSetup(username, password)
            end

            tryTutorial(token)
            return token
          end
        else

          failsByUser[username] = (failsByUser[username] or 0) + 1
          lastFailTs[username]  = computer.uptime()
          persistBackoff()
          local wait = backoffSeconds(username)
          local msg = (err or t("login.failed", "Login failed")) ..
            (wait > 2 and t("login.wait", " — wait %ds", wait) or "")
          drawLoginScreen(msg, true)
          if _G._TOS and _G._TOS.audio then _G._TOS.audio.error() end
          if log and log.warn then
            log.warn("auth", string.format(
              "Failed login for %q (consecutive %d, backoff %ds)",
              username, failsByUser[username], wait))
          end
          sleep(wait)
        end
      end
    end
  end
end

return login
