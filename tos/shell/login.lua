-- ╔══════════════════════════════════════╗
-- ║  TOS Login Screen                    ║
-- ║  Authentication before shell access  ║
-- ╚══════════════════════════════════════╝

local computer = require("computer")

local login = {}

-- ── Seat-safe input primitive (#FIX round-4 "two-screen boot binds one
-- session") ──────────────────────────────────────────────────────────
-- Login runs as a per-seat kernel PROCESS. Reading input with raw
-- computer.pullSignal here drained the GLOBAL hardware queue on the main
-- thread: it BLOCKED the whole kernel loop while this seat's login waited
-- (the other seat froze until this login finished — "must log in twice"),
-- and it ate EVERY seat's keystrokes (whichever keyboard you typed on fed
-- whichever login was currently blocked) — so a 2-seat boot behaved like
-- one shared session. Inside the process coroutine the only correct read
-- is coroutine.yield(): proc.tick resumes us with our OWN seat's routed
-- input (or nothing on an idle tick), exactly like the shells' pullSignal.
-- The raw-pullSignal fallback stays for non-process callers (emergency
-- flows, off-box tests) where there is no scheduler to yield to.
local function pull(timeout)
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
  return computer.pullSignal(timeout or 0.5)
end

-- Cooperative sleep. Yield-based pulls resume every scheduler tick, so a
-- single pull(sec) can't be used as a delay ("show this message for 1.5s").
local function sleep(sec)
  local dl = computer.uptime() + sec
  while computer.uptime() < dl do pull(dl - computer.uptime()) end
end

-- Module references
local display, event, usermod, proc, log
local W, H

-- ── i18n (proof-of-concept surface) ──────────────────────────
-- The login screen is the framework's demonstration conversion: every
-- string keeps its English inline and a /usr/lang catalog may override
-- it. ustr does the width math — translated text is multi-byte UTF-8,
-- so byte-based centring/truncation would drift or split characters.
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

-- Field geometry for the two labelled inputs. The label column is sized
-- from the (possibly translated) labels, so a long translation like
-- "Имя пользователя:" widens the column instead of overlapping the
-- input; over-long labels are fitted so the input keeps >= 8 columns.
-- English resolves to exactly the historical layout (inputX = boxX+12).
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

  -- TOS banner — the shared kernel.logo wordmark, theme-coloured so it stays
  -- palette-safe. Falls back to a text banner on tight screens or if the logo
  -- module can't load.
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

  -- Login box
  local boxW = math.min(40, W - 4)
  local boxH = 8
  local boxX = math.floor((W - boxW) / 2) + 1
  local boxY = bannerY + 1

  -- Draw box with theme-safe colors
  local boxBg = theme.panel_bg
  display.dbox(boxX, boxY, boxW, boxH, t("login.title", "Authentication"), {
    bg = boxBg,
    border = borderColor,
    title = titleColor,
  })

  -- Field labels (translated; column width follows the labels)
  local uLbl, pLbl, lblW = fieldGeom(boxX, boxW)
  display.set(boxX + 2, boxY + 2, ufit(uLbl, lblW), dimColor, boxBg)
  display.set(boxX + 2, boxY + 4, ufit(pLbl, lblW), dimColor, boxBg)

  -- Message area (below box)
  if message then
    local msgColor = isError and theme.error or theme.highlight
    local msgX = math.floor((W - uw(message)) / 2)
    display.set(math.max(1, msgX), boxY + boxH + 1, ufit(message, W - 2), msgColor, bgColor)
  end

  -- Unsafe-shutdown complaint: TOS noticed the previous session was cut
  -- off (power toggled / battery died) rather than shut down cleanly.
  if _G._TOS and _G._TOS.unsafeShutdown then
    local warn = ufit(t("login.unsafe",
      "! Last shutdown was unsafe (power loss) - data verified"), W - 2)
    local wColor = theme.warning or theme.error
    local wX = math.floor((W - uw(warn)) / 2)
    display.set(math.max(1, wX), boxY + boxH + 2, warn, wColor, bgColor)
  end

  -- Hint at bottom
  local hint = t("login.hint", "Enter credentials (Ctrl+Q to cancel)")
  display.set(math.max(1, math.floor((W - uw(hint)) / 2)), H - 1, hint, dimColor, bgColor)

  return boxX, boxY, boxW
end

local function drawInput(boxX, boxY, boxW, field, value, active)
  local theme = display.getTheme()
  local fieldY = (field == "username") and (boxY + 2) or (boxY + 4)
  -- Shared geometry with drawLoginScreen so labels and fields can't drift.
  local _, _, _, inputX, inputW = fieldGeom(boxX, boxW)

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

    -- Seat-routed pull (see the header note) — raw pullSignal here froze
    -- and cross-wired the other seat on a 2-seat boot.
    local sig, _, char, code = pull(0.5)

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
  end
end

-- ============================================================
-- First-boot password change
-- ============================================================

local function firstBootSetup(username, oldPassword)
  -- #SEC H-8 — operate on the principal that actually has firstBoot set,
  -- rather than hardcoding "root". The caller passes the username and its
  -- current (pre-change) password so changePassword can verify ownership.
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

    -- Confirm password
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

    -- #FIX (in-game, 2026-08-11) — messages here used to be written as
    -- ONE display.set at boxY+9, which clips at the SCREEN edge and not
    -- the BOX edge. A long error ran out through the border and was cut
    -- mid-word: the operator saw "read-only filesystem; cannot open for
    -- wr" and lost the part that would have told them what to do.
    -- Wrapped to the box's inner width across the two free rows instead.
    local msgW = boxW - 4
    local function say(text, color)
      local rows, line = {}, ""
      for word in tostring(text):gmatch("%S+") do
        local cand = (line == "") and word or (line .. " " .. word)
        if #cand <= msgW then line = cand
        else
          if line ~= "" then rows[#rows + 1] = line end
          -- A single word longer than the box still has to go somewhere;
          -- cut it rather than push the row through the border.
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

    -- Validate
    if #pass1 < 6 then
      say("Password must be 6+ characters!", theme.error)
    elseif pass1 ~= pass2 then
      say("Passwords don't match! Try again.", theme.error)
    else
      -- Success
      local ok, err = usermod.changePassword(username, username, oldPassword, pass1)
      if ok then
        say("Password set! Starting TOS...", theme.highlight)
        sleep(1.5)
        return true
      else
        local msg = tostring(err)
        -- A read-only disk is not something retrying fixes, and looping
        -- the prompt forever taught the operator nothing. Name the real
        -- problem and the actual remedy.
        if msg:lower():find("read%-only") or _G._TOS_ROOT_READONLY then
          say("Disk is READ-ONLY — install to a writable drive (install.lua).",
            theme.error)
          sleep(4)
        else
          say("Error: " .. msg, theme.error)
        end
      end
    end

    -- Clear inputs for retry (wait full duration so user can read error)
    display.fill(inputX, boxY + 5, inputW, 1, " ", theme.input_fg, boxBg)
    display.fill(inputX, boxY + 7, inputW, 1, " ", theme.input_fg, boxBg)
    sleep(1.5)
  end
end

-- ============================================================
-- Guest login option
-- ============================================================

local function showGuestOption(boxX, boxY, boxW)
  local theme = display.getTheme()
  local hint = t("login.guest", "F2: Guest access")
  local hx = boxX + math.floor((boxW - uw(hint)) / 2)
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

  -- Per-ACCOUNT now, not per-machine: shouldShow needs to know whose login
  -- this is, because the marker lives in that account's home.
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

  -- Check for first boot
  -- #BUG-1 — pass setCurrent=false so this seat's login doesn't
  -- mutate the module-global `currentSession`. Multi-seat boots
  -- otherwise race: seat B's login overwrites seat A's session as
  -- "the current one", and downstream code that falls back to the
  -- legacy global path gets the wrong principal. Each seat's shell
  -- process binds its principal explicitly via spawnShellForSeat.
  local rootUser = usermod.getUser("root")
  if rootUser and rootUser.firstBoot then
    local token = usermod.login("root", "root", { setCurrent = false })
    if token then
      local ok = firstBootSetup("root", "root")
      if ok then
        -- #SEC C11 — promote the restricted-tier token to its real tier
        -- once the password has been changed. promoteAfterFirstBoot
        -- verifies the user record's firstBoot flag is now cleared
        -- (changePassword does this) before unlocking the real tier.
        if usermod.promoteAfterFirstBoot then
          local okP, errP = usermod.promoteAfterFirstBoot(token)
          if not okP and log then
            log.warn("auth", "First-boot promotion refused: " .. tostring(errP))
          end
        else
          -- Fallback for older kernels: clear the per-session flag manually.
          local s = usermod.getSession(token)
          if s then s.firstBoot = nil end
        end
        -- Show first-boot tutorial
        tryTutorial(token)
        return token
      end
    end
  end

  -- Check if guest access is enabled
  local guestOk = usermod.guestEnabled and usermod.guestEnabled() or false

  -- #SEC — Per-username consecutive-failure counter for exponential
  -- backoff. The auto-lockout in users.lua is the primary defence
  -- (5 strikes → account locked), but root is intentionally exempt
  -- so a stuck root account can't brick recovery — and that exemption
  -- combined with the previous fixed 2s delay let an attacker do
  -- ~1800 root attempts/hour. Per-user backoff keeps the recovery
  -- ergonomics for a fat-fingering admin while making sustained
  -- brute force impractical.
  --
  -- Schedule: 2 → 5 → 15 → 60 seconds (capped), reset on any
  -- successful login by that user.
  --
  -- #SEC M6 — persist the counter to disk so a reboot doesn't reset
  -- the backoff. Previously the counter was RAM-only; an attacker who
  -- could reboot the box (open the chassis, pull power, anything that
  -- triggers a kernel restart) reset to attempt #1 each cycle, which
  -- defeated the schedule entirely. We persist to /var/lib/login_backoff.dat
  -- (admin-protected via securefs's standard /var ACL).
  local BACKOFF_SCHEDULE = { 2, 5, 15, 60 }
  local BACKOFF_PATH     = "/var/lib/login_backoff.dat"
  local failsByUser = {}
  local lastFailTs  = {}  -- username → uptime of last failure (for sanity drift)

  -- Load persisted state (best-effort; first boot is empty).
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
    -- Best-effort write; failures are non-fatal (we'll just lose
    -- persistence for this cycle).
    local okF, fs = pcall(require, "kernel.fs")
    local okS, ser = pcall(require, "kernel.serialize")
    if not (okF and okS) then return end
    -- Ensure /var/lib exists.
    if not fs.exists("/var/lib") then pcall(fs.makeDirectory, "/var/lib") end
    pcall(fs.writeFile, BACKOFF_PATH,
      ser.encode({ fails = failsByUser, lastFailTs = lastFailTs }))
  end

  local function backoffSeconds(user)
    local n = failsByUser[user] or 0
    return BACKOFF_SCHEDULE[math.min(n, #BACKOFF_SCHEDULE)] or BACKOFF_SCHEDULE[#BACKOFF_SCHEDULE]
  end

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
      local sig, _, char, code = pull(0.5)
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
      -- Escape pressed - show options
      drawLoginScreen(t("login.retry", "Enter to retry, F10 to shut down"), false)
      while true do
        local sig2, _, _, code2 = pull(1)
        if sig2 == "key_down" then
          if code2 == 28 then break
          elseif code2 == 68 then return nil, "shutdown" end
        end
      end
    elseif username == "" then
      -- An empty name still asks for a password. It can never log anyone
      -- in — usermod is not consulted at all on this branch — but it is
      -- the door to shell/colophon.lua. Anyone who just pressed Enter by
      -- mistake types nothing, gets nothing, and is back here in a
      -- second, which is what used to happen anyway.
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
      -- Either way: no token, no session, straight back to the login
      -- screen on the next pass of the loop.

    elseif username and username ~= "" then
      -- Password input
      drawInput(boxX, boxY, boxW, "username", username, false)
      local password = readInput(boxX, boxY, boxW, "password", 30)

      if password then
        -- Attempt login
        drawLoginScreen(t("login.authenticating", "Authenticating..."), false)

        -- #BUG-1 — multi-seat: don't trample the global currentSession.
        local token, err = usermod.login(username, password, { setCurrent = false })
        if token then
          -- Success — reset this user's backoff counter.
          -- #SEC M6 — persist the reset so the next reboot doesn't
          -- carry forward a stale fail count from before this
          -- successful login.
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
          -- Failure: bump the per-user counter, then sleep for the
          -- escalating delay. The current schedule is { 2, 5, 15, 60 }
          -- seconds; after the fourth failure we hold at 60 indefinitely.
          failsByUser[username] = (failsByUser[username] or 0) + 1
          lastFailTs[username]  = computer.uptime()
          persistBackoff()  -- #SEC M6 — survive reboots
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
