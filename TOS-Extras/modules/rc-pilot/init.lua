-- ╔══════════════════════════════════════╗
-- ║  TOS Module — rc-pilot (host side)   ║
-- ╚══════════════════════════════════════╝
-- Pairs with /TOS-Extras/robot/eeprom-rc-pilot.lua. Run `rc <addr>`
-- on a TOS computer with a wireless modem; the screen goes into
-- piloting mode and WASD / arrow keys / Space / Shift drive the
-- robot. ^Q or F10 exits (Esc belongs to Minecraft — it closes the
-- screen GUI and never reaches the computer).
--
-- Key bindings (covers both flat robots and Computronics drones):
--   W / Up      forward
--   S / Down    back
--   A / Left    strafe left (drone) OR turn-left+forward+turn-right (robot)
--   D / Right   strafe right (drone) OR turn-right+forward+turn-left (robot)
--   Q           turn left in place
--   E           turn right in place
--   Space       up (drone)
--   LShift      down (drone)
--   F           use (right-click in front)
--   X           swing (break block in front)
--   B           place (place block from selected slot)
--   1..9        select inventory slot 1..9
--   P           ping (round-trip test)
--   Esc / Ctrl+C  exit pilot mode

local component = require("component")
local computer  = require("computer")

-- Standard TOS shortcuts, shared with the shell (tos/shell/keys.lua): ^Q
-- closes this the same way it closes everything else TOS ships, and an
-- operator rebinding `quit` with `keys set` reaches here too. Falls back
-- to the coded defaults when the module is unavailable.
local KEYS do local okK, m = pcall(require, "shell.keys"); KEYS = okK and m or nil end
local function stdQuit(ch, code)
  if KEYS and KEYS.is then return KEYS.is("quit", ch, code) end
  return ch == 17 or code == 68 or code == 1
end
local function quitLabel()
  if KEYS and KEYS.label then
    local l = KEYS.label("quit")
    if l ~= "" then return l end
  end
  return "^Q"
end

local mod = {}

local PORT  = 7777
local MAGIC = "RCPILOT1"

-- ============================================================
-- Helpers (HMAC + CSPRNG)
-- ============================================================
-- The package sandbox injects a narrow `crypto` GLOBAL when the manifest
-- declares the "crypto" capability (hash/hmac/ctEquals/random). It does NOT
-- allow require("kernel.crypto"), so prefer the injected global and only fall
-- back to the kernel module when run un-sandboxed (e.g. a smoke test).
local crypto = crypto
if not (crypto and crypto.hmac) then
  local ok, kc = pcall(require, "kernel.crypto")
  if ok then crypto = kc end
end
-- The injected surface exposes CSPRNG bytes as `random(n)`; the raw kernel
-- module spells the same thing `salt(n)`. Bridge both so this runs either way.
local function randBytes(n) return (crypto.random or crypto.salt)(n) end

--! HEX, never raw bytes. The frame is a Lua-literal string the EEPROM
--! parses with  nonce="([^"]+)"  -- a raw 0x22 in the nonce (one frame in
--! sixteen, with 16 random bytes) truncated it on the robot, the MAC was
--! then computed over a different body than the host's, and the
--! keystroke was silently dropped. (test_rc_pilot.lua)
local function nonce()
  return (randBytes(16):gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

local function packFrame(op, arg, secret)
  local n = nonce()
  local body = op .. "|" .. tostring(arg or "") .. "|" .. n
  local mac  = crypto.hmac(secret, body)
  -- Serialize as minimal Lua so the EEPROM's pattern parser can read it.
  local argPart = arg and ("arg=" .. tostring(arg) .. ",") or ""
  return string.format(
    '{magic="%s",op="%s",%snonce="%s",mac="%s"}',
    MAGIC, op, argPart, n, mac)
end

-- ============================================================
-- Resolve target + secret
-- ============================================================

local function resolveSecret(target, sess)
  -- Prefer keychain slot "rc:<addr>" if present + unlocked.
  local km = _G._TOS and _G._TOS.keychain
  if km and km.isUnlocked and km.isUnlocked(sess) then
    local k = "rc:" .. (target or ""):sub(1, 8)
    local pass = km.get(k, sess)
    if pass then return pass end
  end
  return nil
end

-- ============================================================
-- Main command
-- ============================================================

mod.commands = {
  rc = function(args, o)
    o = o or print
    local target = args[1]
    if not target then
      o("Usage: rc <robot-address-prefix>")
      o("  The robot must be running the rc-pilot EEPROM and have a")
      o("  shared secret either in your keychain (slot 'rc:<addr>')")
      o("  or passed via 'rc <addr> --secret <secret>'.")
      return
    end

    -- Find a local modem.
    local modemAddr = component.list("modem")()
    if not modemAddr then o("No modem"); return end
    local modem = component.proxy(modemAddr)
    if not modem.isWireless or not modem.isWireless() then
      o("Modem is not wireless. RC pilot needs a wireless modem.")
      return
    end

    -- Resolve a prefix against the peers TOS knows. This used to call
    -- net.listPeers, which does not exist (trust.listPeers does), so the
    -- prefix form advertised in the usage never resolved anything. A
    -- robot on a bare EEPROM is not a TOS peer and will usually not be in
    -- that list either -- so the honest instruction is the full address,
    -- and a prefix is a convenience when it happens to be known.
    local full = nil
    local tos = _G._TOS or {}
    local tm = tos.trust or (tos.net and tos.net.trust)
    if tm and tm.listPeers then
      local okL, peers = pcall(tm.listPeers)
      for _, m in ipairs(okL and peers or {}) do
        local a = m.address or m.addr
        if type(a) == "string" and a:sub(1, #target) == target then full = a; break end
      end
    end
    full = full or target  -- accept full address verbatim
    if #full < 16 then
      o("Target address looks too short. Give the robot's full modem address")
      o("(a prefix only works for a peer TOS already knows about).")
      return
    end

    -- Resolve secret: keychain, then --secret <s>, then a masked prompt.
    local secret
    for i = 2, #args do
      if args[i] == "--secret" and args[i + 1] then
        secret = args[i + 1]
        --! argv is shell history. The same reason `pkg trust key` stopped
        --! taking its passphrase this way; kept for scripts, said out loud.
        o("Note: --secret puts the shared secret in this seat's command history.")
        o("      Prefer the keychain:  keychain set rc:" .. full:sub(1, 8))
      end
    end
    if not secret then
      local sess = tos.users and tos.users.currentSession and tos.users.currentSession()
      secret = resolveSecret(full, sess)
    end
    if not secret then
      -- Ask for it, masked, when the compat term is available to us.
      local okT, term = pcall(require, "compat.term")
      if okT and type(term) == "table" and type(term.read) == "function" then
        o("Shared secret for " .. full:sub(1, 8) .. "... (not echoed): ")
        local okR, line = pcall(term.read, nil, false, nil, "*")
        if okR and type(line) == "string" then secret = line:gsub("[\r\n]+$", "") end
      end
    end
    if not secret or #secret < 16 then
      o("No shared secret (16+ characters). Either add it to the keychain:")
      o("  keychain set rc:" .. full:sub(1, 8))
      o("or, for a script only:  rc <addr> --secret <secret>")
      return
    end

    modem.open(PORT)
    o("RC pilot active. Target: " .. full:sub(1, 12) .. "...")
    o("Keys: WASD/arrows | Q/E turn | Space/Shift up/down | F use | X break | B place | 1-9 slot | P ping | "
      .. quitLabel() .. " quit")

    -- Key→op map. OC key codes (LWJGL):
    --   17=W  31=S  30=A  32=D  16=Q  18=E
    --   200=Up 208=Down 203=Left 205=Right
    --   57=Space  42=LShift
    --   33=F  45=X  48=B  25=P  1=Esc
    --   2..10=number keys 1..9
    local function dispatchKey(ch, code)
      if code == 17 or code == 200 then return "move:f" end
      if code == 31 or code == 208 then return "move:b" end
      if code == 30 or code == 203 then return "move:l" end
      if code == 32 or code == 205 then return "move:r" end
      if code == 16 then return "turn:l" end
      if code == 18 then return "turn:r" end
      if code == 57 then return "up"    end
      if code == 42 then return "down"  end
      if code == 33 then return "use:f" end
      if code == 45 then return "swing:f" end
      if code == 48 then return "place:f" end
      if code == 25 then return "ping"  end
      if code >= 2 and code <= 10 then
        return "select", code - 1   -- code 2 → slot 1, code 10 → slot 9
      end
      return nil
    end

    while true do
      --! One pull, all of it. This used to take four values, and on a
      --! modem_message call pullSignal() AGAIN -- with no timeout -- to
      --! read the payload from whatever signal came next: the pong was
      --! lost and the pilot hung until the operator pressed a key.
      local sig, _, a3, a4, _, a6 = computer.pullSignal(0.5)
      if sig == "key_down" then
        local char, code = a3, a4          -- (name, keyboard, char, code, player)
        -- #FIX (real Minecraft, 2026-08-11) — ^Q or F10, not Esc: Esc
        -- closes the screen GUI and never reaches the computer, and a
        -- pilot you cannot exit keeps flying a robot. Plain Q is TURN
        -- LEFT here, so it cannot be the quit key. Esc and ^C stay
        -- accepted in case anything ever delivers them.
        if stdQuit(char, code) or char == 3 then
          modem.close(PORT)
          o("RC pilot exited.")
          return
        end
        local op, arg = dispatchKey(char, code)
        if op then
          modem.send(full, PORT, packFrame(op, arg, secret))
        end
      elseif sig == "modem_message" then
        -- (name, local, remote, port, distance, data): the reply is a6.
        local data = a6
        if type(data) == "string" then
          local pongAt = data:match('op="pong",arg=(%d+)')
          if pongAt then o("  pong @ uptime=" .. pongAt) end
        end
      end
    end
  end,
}

return mod
