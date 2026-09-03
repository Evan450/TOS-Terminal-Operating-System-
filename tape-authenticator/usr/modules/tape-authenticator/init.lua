-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Module — Tape Authenticator                           ║
-- ║  Keycard identity + encrypted personal log on one tape     ║
-- ╚══════════════════════════════════════════════════════════╝
-- A tape is a lot bigger than a keycard needs, so this module uses the
-- rest of it: the front of the tape carries an HMAC-signed identity
-- block ("this tape is Operator X's key", machine-secret-bound and
-- unforgeable), and the space after it holds a vault-encrypted PERSONAL
-- LOG the operator can add to / remove from at any time — a miniature
-- private notebook fused with an access card.
--
-- The two halves are deliberately independent:
--   * The identity block is signed with a per-package MACHINE secret
--     (crypto.secret(), admin-gated, kernel-managed) — minting and
--     verifying keys is an operator action on the issuing machine.
--   * The log is encrypted with the OPERATOR'S OWN passphrase (vault
--     cap). Editing the log never touches the identity block, needs no
--     admin tier, and the machine secret can't read the log.
--
-- Runs fully inside the pkg sandbox: `crypto` + `vault` capability
-- globals, the component proxy for the tape drive — no kernel.*
-- requires (the 0.1.x build needed kernel.crypto/securefs, which the
-- sandbox blocks, so it could never run under pkg).
--
-- Wire format on tape (TAUTH2):
--   magic      "TAUTH2\0"   7 bytes
--   issuedAt   uint32       computer.uptime() at init (informational)
--   labelLen   uint16
--   label      <labelLen>   display name for the key / operator
--   mac        64 hex       HMAC-SHA256(machine secret, bytes above)
--   logLen     uint32       0 = no log yet
--   log        <logLen>     vault blob (operator-passphrase encrypted)
--
-- The MAC covers ONLY the identity block, so log edits don't need the
-- machine secret. TAUTH1 tapes (the 0.1.x format, identity-only) still
-- verify read-only.

local component = require("component")
local computer  = require("computer")

local MAGIC_V2 = "TAUTH2\0"
local MAGIC_V1 = "TAUTH1\0"
local MAC_LEN  = 64       -- hex HMAC-SHA256
local MAX_LABEL = 200
local BLOCK    = 8192     -- tape I/O chunk size

-- ── Capability checks ────────────────────────────────────────
-- `crypto` and `vault` are sandbox-injected globals (declared in
-- package.lua). Checked lazily so `tape-auth help` works regardless.
local function getCrypto(o)
  if type(crypto) == "table" and crypto.hmac and crypto.ctEquals then
    return crypto
  end
  o("crypto capability unavailable — reinstall tape-authenticator.", 0xFF0000)
  return nil
end
local function getVault(o)
  if type(vault) == "table" and vault.encrypt and vault.decrypt then
    return vault
  end
  o("vault capability unavailable — reinstall tape-authenticator.", 0xFF0000)
  return nil
end

-- The machine secret that signs identity blocks. crypto.secret() is
-- per-package (other packages can't read it) and admin-gated (resolved
-- against the live session), so this surfaces a clear message for
-- non-admin callers instead of a confusing nil.
local function getSecret(o)
  local C = getCrypto(o)
  if not C then return nil end
  if not C.secret then
    o("machine secret unavailable (kernel too old?).", 0xFF0000)
    return nil
  end
  local secret, err = C.secret()
  if not secret then
    o("Cannot access the key secret: " .. tostring(err), 0xFF0000)
    o("(minting and verifying keycards is an admin action)", 0xAAAAAA)
    return nil
  end
  return secret
end

-- ── Tape I/O ─────────────────────────────────────────────────
local function findDrive()
  local addr = component.list("tape_drive")()
  if addr then return component.proxy(addr) end
  return nil
end

local function requireTape(o)
  local drive = findDrive()
  if not drive then o("No tape drive found.", 0xFF0000); return nil end
  if not drive.isReady() then o("No tape inserted.", 0xFF6600); return nil end
  return drive
end

-- Stream exactly N bytes from the current tape position (drive.read may return
-- short, so loop). Returns "" on N<=0.
local function readN(drive, n)
  if n <= 0 then return "" end
  local parts, need = {}, n
  while need > 0 do
    local ok, c = pcall(drive.read, math.min(BLOCK, need))
    if not ok or not c or #c == 0 then break end
    parts[#parts + 1] = c
    need = need - #c
  end
  return table.concat(parts)
end

local function writeImage(drive, data)
  drive.stop()
  drive.seek(-(drive.getSize() or 0))
  local written = 0
  while written < #data do
    local chunk = data:sub(written + 1, written + BLOCK)
    local ok, werr = pcall(drive.write, chunk)
    if not ok then return false, "write failed at " .. written .. ": " .. tostring(werr) end
    written = written + #chunk
    if (written / BLOCK) % 8 == 0 then computer.pullSignal(0) end
  end
  -- Terminate any stale bytes left behind by a longer previous image.
  pcall(drive.write, string.rep("\0", 16))
  drive.stop()
  drive.seek(-(drive.getSize() or 0))
  return true
end

-- ── Wire-format helpers ──────────────────────────────────────
local function packU16(n) return string.char(n & 0xFF, (n >> 8) & 0xFF) end
local function packU32(n)
  return string.char(n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF)
end
local function unpackU16(s, off) return s:byte(off) | (s:byte(off + 1) << 8), off + 2 end
local function unpackU32(s, off)
  return s:byte(off)
    | (s:byte(off + 1) << 8)
    | (s:byte(off + 2) << 16)
    | (s:byte(off + 3) << 24), off + 4
end

-- Parse a raw tape image. Returns a table or (nil, reason):
--   { version=1|2, label=, issuedAt=, body= (MACed bytes), mac=,
--     logLen=, logBlob= ("" when absent), identityEnd= }
local function parseImage(raw)
  if not raw or #raw < 7 + 4 + 2 + MAC_LEN then return nil, "tape unreadable or too short" end
  local magic = raw:sub(1, 7)
  local version
  if magic == MAGIC_V2 then version = 2
  elseif magic == MAGIC_V1 then version = 1
  else return nil, "not a tape-auth keycard (bad magic)" end

  local off = 8
  local issuedAt; issuedAt, off = unpackU32(raw, off)
  local labelLen; labelLen, off = unpackU16(raw, off)
  if labelLen > MAX_LABEL then return nil, "label length implausible" end
  if off + labelLen + MAC_LEN - 1 > #raw then return nil, "tape truncated" end
  local label = raw:sub(off, off + labelLen - 1); off = off + labelLen
  local body  = raw:sub(1, off - 1)
  local mac   = raw:sub(off, off + MAC_LEN - 1); off = off + MAC_LEN

  local logLen, logBlob = 0, ""
  local menuLen, menuBlob = 0, ""
  if version == 2 then
    if off + 3 <= #raw then
      logLen, off = unpackU32(raw, off)
      if logLen > 0 then
        if off + logLen - 1 > #raw then return nil, "log region truncated" end
        logBlob = raw:sub(off, off + logLen - 1)
        off = off + logLen
      end
      -- Optional trailing MENU region — the operator's personal launcher menu
      -- (vault-encrypted, like the log). Older TAUTH2 tapes that predate it
      -- simply end after the log, so a missing region is not an error.
      if off + 3 <= #raw then
        menuLen, off = unpackU32(raw, off)
        if menuLen > 0 then
          if off + menuLen - 1 > #raw then return nil, "menu region truncated" end
          menuBlob = raw:sub(off, off + menuLen - 1)
          off = off + menuLen
        end
      end
    end
  end
  return {
    version = version, label = label, issuedAt = issuedAt,
    body = body, mac = mac, logLen = logLen, logBlob = logBlob,
    menuLen = menuLen, menuBlob = menuBlob,
  }
end

-- Rebuild a full V2 image from parts. The log region is always present (length
-- prefix, possibly 0); the menu region is appended only when non-empty.
local function buildImage(body, mac, logBlob, menuBlob)
  local img = body .. mac .. packU32(#logBlob) .. logBlob
  if menuBlob and #menuBlob > 0 then
    img = img .. packU32(#menuBlob) .. menuBlob
  end
  return img
end

-- Read + parse a keycard by STREAMING only the bytes the structure needs
-- (header, label, mac, log, menu) — never the whole tape. Reading a whole 4 MB+
-- tape into one Lua string OOMs even tier-3.5 RAM, which is what made
-- "configuring a tape" fail. Returns the same shape as parseImage, or
-- (nil, reason). Lengths are bounded by the tape size so a corrupt prefix can't
-- trigger a multi-GB read.
local function readCard(drive)
  local size = drive.getSize() or 0
  drive.stop()
  drive.seek(-size)
  local magic = readN(drive, 7)
  local version
  if magic == MAGIC_V2 then version = 2
  elseif magic == MAGIC_V1 then version = 1
  else return nil, "not a tape-auth keycard (bad magic)" end

  local issuedRaw   = readN(drive, 4)
  local labelLenRaw = readN(drive, 2)
  if #issuedRaw < 4 or #labelLenRaw < 2 then return nil, "tape truncated" end
  local issuedAt = unpackU32(issuedRaw, 1)
  local labelLen = unpackU16(labelLenRaw, 1)
  if labelLen > MAX_LABEL then return nil, "label length implausible" end
  local label = readN(drive, labelLen)
  if #label < labelLen then return nil, "tape truncated" end
  local mac = readN(drive, MAC_LEN)
  if #mac < MAC_LEN then return nil, "tape truncated" end
  local body = magic .. issuedRaw .. labelLenRaw .. label

  local logLen, logBlob, menuLen, menuBlob = 0, "", 0, ""
  if version == 2 then
    local logLenRaw = readN(drive, 4)
    if #logLenRaw == 4 then
      logLen = unpackU32(logLenRaw, 1)
      if logLen > size then return nil, "log length implausible" end
      if logLen > 0 then
        logBlob = readN(drive, logLen)
        if #logBlob < logLen then return nil, "log region truncated" end
      end
      local menuLenRaw = readN(drive, 4)
      if #menuLenRaw == 4 then
        menuLen = unpackU32(menuLenRaw, 1)
        if menuLen > size then return nil, "menu length implausible" end
        if menuLen > 0 then
          menuBlob = readN(drive, menuLen)
          if #menuBlob < menuLen then return nil, "menu region truncated" end
        end
      end
    end
  end
  return {
    version = version, label = label, issuedAt = issuedAt,
    body = body, mac = mac, logLen = logLen, logBlob = logBlob,
    menuLen = menuLen, menuBlob = menuBlob,
  }
end

-- Read + parse + verify capacity for a mutation. Returns (drive, img).
local function openCard(o, forWrite, extraBytes)
  local drive = requireTape(o)
  if not drive then return nil end
  local img, err = readCard(drive)
  if not img then o(tostring(err), 0xFF0000); return nil end
  if forWrite then
    if img.version ~= 2 then
      o("This is a TAUTH1 (identity-only) tape; re-run `tape-auth init` to upgrade.", 0xFF6600)
      return nil
    end
    local projected = #img.body + MAC_LEN + 4 + (img.logLen or 0)
      + 4 + (img.menuLen or 0) + (extraBytes or 0)
    if projected > (drive.getSize() or 0) then
      o("Tape too small for that change.", 0xFF0000)
      return nil
    end
  end
  return drive, img
end

-- ── Log plaintext helpers ────────────────────────────────────
-- The decrypted log is newline-separated single-line entries, each
-- prefixed with the uptime it was added at: "[t1234] text".
local function splitEntries(plain)
  local entries = {}
  for line in (plain or ""):gmatch("[^\n]+") do entries[#entries + 1] = line end
  return entries
end

local function decryptLog(img, passphrase, o)
  local V = getVault(o)
  if not V then return nil end
  if img.logLen == 0 or img.logBlob == "" then return {} end
  if not V.isEncrypted(img.logBlob) then
    o("Log region is corrupt (not a vault blob).", 0xFF0000)
    return nil
  end
  local plain, derr = V.decrypt(img.logBlob, passphrase)
  if not plain then
    o("Cannot decrypt log: " .. tostring(derr), 0xFF0000)
    return nil
  end
  return splitEntries(plain)
end

local function writeLog(drive, img, entries, passphrase, o)
  local V = getVault(o)
  if not V then return false end
  local blob = ""
  if #entries > 0 then
    local b, eerr = V.encrypt(table.concat(entries, "\n"), passphrase)
    if not b then o("encrypt failed: " .. tostring(eerr), 0xFF0000); return false end
    blob = b
  end
  -- Preserve the menu region when rewriting the log (and vice versa).
  local image = buildImage(img.body, img.mac, blob, img.menuBlob)
  if #image > (drive.getSize() or 0) then
    o("Tape too small for the updated log.", 0xFF0000)
    return false
  end
  local ok, werr = writeImage(drive, image)
  if not ok then o(tostring(werr), 0xFF0000); return false end
  return true
end

-- ── Personal menu helpers ────────────────────────────────────
-- The personal menu is a vault-encrypted list (like the log) of "Label|command"
-- lines. The LAUNCHER reads + decrypts this region itself (it knows the
-- operator's home and has tape + vault access), so the menu travels on the
-- card without this sandboxed package needing filesystem access.
local function decryptMenu(img, passphrase, o)
  local V = getVault(o)
  if not V then return nil end
  if img.menuLen == 0 or img.menuBlob == "" then return {} end
  if not V.isEncrypted(img.menuBlob) then
    o("Menu region is corrupt (not a vault blob).", 0xFF0000)
    return nil
  end
  local plain, derr = V.decrypt(img.menuBlob, passphrase)
  if not plain then
    o("Cannot decrypt menu: " .. tostring(derr), 0xFF0000)
    return nil
  end
  return splitEntries(plain)
end

local function writeMenu(drive, img, entries, passphrase, o)
  local V = getVault(o)
  if not V then return false end
  local blob = ""
  if #entries > 0 then
    local b, eerr = V.encrypt(table.concat(entries, "\n"), passphrase)
    if not b then o("encrypt failed: " .. tostring(eerr), 0xFF0000); return false end
    blob = b
  end
  -- Preserve the log region while rewriting the menu.
  local image = buildImage(img.body, img.mac, img.logBlob, blob)
  if #image > (drive.getSize() or 0) then
    o("Tape too small for the updated menu.", 0xFF0000)
    return false
  end
  local ok, werr = writeImage(drive, image)
  if not ok then o(tostring(werr), 0xFF0000); return false end
  return true
end

-- ── Commands ─────────────────────────────────────────────────

local function cmdInit(args, o)
  local label = args[2]
  if not label then o("Usage: tape-auth init <label>", 0xAAAAAA); return end
  if #label > MAX_LABEL then o("Label too long (max " .. MAX_LABEL .. ").", 0xFF0000); return end
  local drive = requireTape(o)
  if not drive then return end
  local secret = getSecret(o)
  if not secret then return end
  local C = getCrypto(o)

  -- Refuse to silently destroy an existing card's log.
  local existing = readCard(drive)
  if existing and existing.logLen > 0 then
    o("Tape already holds a keycard WITH a personal log.", 0xFF6600)
    o("`tape-auth log clear <passphrase>` it first, or use a fresh tape.", 0xAAAAAA)
    return
  end

  local now  = math.floor(computer.uptime())
  local body = MAGIC_V2 .. packU32(now) .. packU16(#label) .. label
  local mac  = C.hmac(secret, body)
  local ok, werr = writeImage(drive, buildImage(body, mac, ""))
  if not ok then o(tostring(werr), 0xFF0000); return end
  o(("Keycard initialized: label=%s (%d bytes identity, log empty)")
    :format(label, #body + MAC_LEN + 4), 0x00FF00)
  o("Add private notes with: tape-auth log add <passphrase> <text>", 0xAAAAAA)
end

local function cmdVerify(args, o)
  local drive = requireTape(o)
  if not drive then return false end
  local secret = getSecret(o)
  if not secret then return false end
  local C = getCrypto(o)

  local img, err = readCard(drive)
  if not img then o(tostring(err), 0xFF0000); return false end
  local expected = C.hmac(secret, img.body)
  if not C.ctEquals(expected, img.mac) then
    o("INVALID: MAC mismatch — tape is not a valid key.", 0xFF0000)
    return false
  end
  o(("VALID: label=%s issuedAt=%d%s"):format(img.label, img.issuedAt,
    img.version == 1 and "  (TAUTH1 legacy card)" or ""), 0x00FF00)
  return true, img.label
end

local function cmdInfo(args, o)
  -- Unauthenticated peek: shows what the tape CLAIMS without the
  -- machine secret (so any operator can identify a card). Says so.
  local drive = requireTape(o)
  if not drive then return end
  local img, err = readCard(drive)
  if not img then o(tostring(err), 0xFF6600); return end

  -- If the machine secret is reachable (admin session), AUTHENTICATE inline and
  -- report the real verdict — so `info` is self-sufficient instead of always
  -- telling the operator to "run verify" even right after they verified. For a
  -- non-admin, crypto.secret() returns nil quietly and we keep the peek + hint.
  local C = (type(crypto) == "table" and crypto.hmac and crypto.ctEquals) and crypto or nil
  local secret = nil
  if C and C.secret then local ok, s = pcall(C.secret); if ok then secret = s end end
  local authed = secret and C.ctEquals(C.hmac(secret, img.body), img.mac)

  o(("Keycard (TAUTH%d%s): label=%s issuedAt=%d"):format(
    img.version,
    secret and (authed and ", VALID" or ", INVALID") or ", unverified",
    img.label, img.issuedAt),
    secret and (authed and 0x00FF00 or 0xFF0000) or 0xFFFF55)
  if img.version == 2 then
    if img.logLen > 0 then
      o(("Personal log: %d bytes (encrypted)"):format(img.logLen), 0xAAAAAA)
    else
      o("Personal log: empty", 0xAAAAAA)
    end
  else
    o("No log region (legacy card; `tape-auth init` to upgrade).", 0xAAAAAA)
  end
  if not secret then
    o("Run `tape-auth verify` (admin) to authenticate it.", 0x555555)
  end
end

local function cmdLog(args, o)
  local action = args[2]
  local pass   = args[3]
  if not action or not pass then
    o("Usage: tape-auth log <add|list|remove|clear|passwd> <passphrase> [...]", 0xAAAAAA)
    return
  end

  if action == "add" then
    local text = table.concat(args, " ", 4)
    if #text == 0 then o("Usage: tape-auth log add <passphrase> <text>", 0xAAAAAA); return end
    text = text:gsub("[\r\n]", " ")
    local drive, img = openCard(o, true, #text + 96)
    if not drive then return end
    local entries = decryptLog(img, pass, o)
    if not entries then return end
    entries[#entries + 1] = ("[t%d] %s"):format(math.floor(computer.uptime()), text)
    if writeLog(drive, img, entries, pass, o) then
      o(("Logged entry #%d."):format(#entries), 0x00FF00)
    end

  elseif action == "list" then
    local drive, img = openCard(o, false)
    if not drive then return end
    if img.version ~= 2 or img.logLen == 0 then o("Log is empty.", 0xAAAAAA); return end
    local entries = decryptLog(img, pass, o)
    if not entries then return end
    o(("Personal log — %s (%d entries)"):format(img.label, #entries), 0xFFFF55)
    for i, e in ipairs(entries) do
      o(("  %2d. %s"):format(i, e), 0xFFFFFF)
    end

  elseif action == "remove" or action == "rm" then
    local n = tonumber(args[4])
    if not n then o("Usage: tape-auth log remove <passphrase> <entry#>", 0xAAAAAA); return end
    local drive, img = openCard(o, true)
    if not drive then return end
    local entries = decryptLog(img, pass, o)
    if not entries then return end
    if not entries[n] then o("No entry #" .. n .. ".", 0xFF6600); return end
    local removed = table.remove(entries, n)
    if writeLog(drive, img, entries, pass, o) then
      o("Removed: " .. removed, 0x00FF00)
    end

  elseif action == "clear" then
    local drive, img = openCard(o, true)
    if not drive then return end
    -- Validate the passphrase before destroying anything.
    if img.logLen > 0 and not decryptLog(img, pass, o) then return end
    if writeLog(drive, img, {}, pass, o) then
      o("Log cleared.", 0x00FF00)
    end

  elseif action == "passwd" then
    local newPass = args[4]
    if not newPass then o("Usage: tape-auth log passwd <old> <new>", 0xAAAAAA); return end
    local drive, img = openCard(o, true)
    if not drive then return end
    local entries = decryptLog(img, pass, o)
    if not entries then return end
    if writeLog(drive, img, entries, newPass, o) then
      o("Log passphrase changed.", 0x00FF00)
    end

  else
    o("Unknown: tape-auth log " .. tostring(action), 0xFF6600)
  end
end

-- Personal menu: a vault-encrypted list of "Label | command" entries that the
-- launcher (`launcher tape`) reads off the card so your toolbox travels with
-- your keycard. Items run at YOUR tier — the launcher shows the real command
-- before running it.
local function cmdMenu(args, o)
  local action = args[2]
  local pass   = args[3]
  if not action or not pass then
    o("Usage: tape-auth menu <add|list|remove|passwd|clear> <passphrase> [...]", 0xAAAAAA)
    return
  end

  if action == "add" then
    local rest = table.concat(args, " ", 4)
    -- #FIX (emulator round 7) — "|" CANNOT be the separator on a command
    -- line. The TOS shell parses an unquoted "|" as a PIPE before this
    -- package ever sees the arguments, so the usage text we printed
    -- ("... Reactor status | doctor") split into two commands and ran the
    -- second one on the spot: the operator typed `tape-auth menu add
    -- 111111 test | doctor` and watched `doctor` run. "--" is the
    -- separator now — the shell has no meaning for it — and a quoted "|"
    -- still works for anyone who already learned the old form.
    local label, cmd = rest:match("^(.-)%s+%-%-%s+(.+)$")
    if not label then label, cmd = rest:match("^(.-)%s*|%s*(.+)$") end
    if not label or #label == 0 or not cmd then
      o("Usage: tape-auth menu add <pass> <Label> -- <command>", 0xAAAAAA)
      o("  e.g. tape-auth menu add hunter2 Reactor status -- doctor", 0xAAAAAA)
      if #rest > 0 then
        -- Almost always what just happened: the shell ate everything from
        -- the "|" onwards, so we were handed a bare label.
        o("Note: an unquoted | is a shell PIPE — it never reaches this", 0xFFAA00)
        o("command. Use -- , or quote it: \"" .. rest .. " | <command>\"", 0xFFAA00)
      end
      return
    end
    label = label:gsub("[\r\n|]", " ")
    cmd   = cmd:gsub("[\r\n]", " ")
    local drive, img = openCard(o, true, #label + #cmd + 96)
    if not drive then return end
    -- An EMPTY menu decrypts under any passphrase (there is nothing to
    -- decrypt), so this first write is what actually SETS the tape's
    -- passphrase. That was silent, and silence reads as "it already knew
    -- my password" — say it out loud instead.
    local fresh = (img.menuLen == 0 or img.menuBlob == "")
    local entries = decryptMenu(img, pass, o)
    if not entries then return end
    entries[#entries + 1] = label .. "|" .. cmd
    if writeMenu(drive, img, entries, pass, o) then
      o(("Added menu item #%d."):format(#entries), 0x00FF00)
      if fresh then
        o("This tape had no menu, so the passphrase you just used is now", 0xFFAA00)
        o("ITS passphrase. Anyone holding the tape can try it: don't", 0xFFAA00)
        o("reuse your login password. Change it with 'menu passwd'.", 0xFFAA00)
      end
    end

  elseif action == "passwd" then
    local newPass = args[4]
    if not newPass then o("Usage: tape-auth menu passwd <old> <new>", 0xAAAAAA); return end
    local drive, img = openCard(o, true)
    if not drive then return end
    if img.menuLen == 0 or img.menuBlob == "" then
      o("This tape has no menu yet — its passphrase is set by the first", 0xAAAAAA)
      o("'menu add'.", 0xAAAAAA)
      return
    end
    local entries = decryptMenu(img, pass, o)
    if not entries then return end
    if writeMenu(drive, img, entries, newPass, o) then
      o("Menu passphrase changed.", 0x00FF00)
    end

  elseif action == "list" then
    local drive, img = openCard(o, false)
    if not drive then return end
    if img.menuLen == 0 then o("Tape menu is empty.", 0xAAAAAA); return end
    local entries = decryptMenu(img, pass, o)
    if not entries then return end
    o(("Tape menu — %s (%d items)"):format(img.label, #entries), 0xFFFF55)
    for i, e in ipairs(entries) do
      local label, cmd = e:match("^(.-)|(.+)$")
      o(("  %2d. %-18s %s"):format(i, label or e, cmd or ""), 0xFFFFFF)
    end

  elseif action == "remove" or action == "rm" then
    local n = tonumber(args[4])
    if not n then o("Usage: tape-auth menu remove <pass> <#>", 0xAAAAAA); return end
    local drive, img = openCard(o, true)
    if not drive then return end
    local entries = decryptMenu(img, pass, o)
    if not entries then return end
    if not entries[n] then o("No menu item #" .. n .. ".", 0xFF6600); return end
    local removed = table.remove(entries, n)
    if writeMenu(drive, img, entries, pass, o) then
      o("Removed: " .. removed, 0x00FF00)
    end

  elseif action == "clear" then
    local drive, img = openCard(o, true)
    if not drive then return end
    if img.menuLen > 0 and not decryptMenu(img, pass, o) then return end
    if writeMenu(drive, img, {}, pass, o) then
      o("Tape menu cleared.", 0x00FF00)
    end

  else
    o("Unknown: tape-auth menu " .. tostring(action), 0xFF6600)
  end
end

-- ── Dispatcher ───────────────────────────────────────────────
return {
  commands = {
    ["tape-auth"] = function(args, o)
      o = o or print
      local sub = args[1]
      if sub == "init" or sub == "write" then return cmdInit(args, o)
      elseif sub == "verify" then return cmdVerify(args, o)
      elseif sub == "info"   then return cmdInfo(args, o)
      elseif sub == "log"    then return cmdLog(args, o)
      elseif sub == "menu"   then return cmdMenu(args, o)
      else
        o("=== Tape Authenticator ===", 0xFFFF00)
        o("A tape as a keycard + private notebook.", 0xAAAAAA)
        o("", 0xFFFFFF)
        o("  tape-auth init <label>     Bless the tape as a keycard (admin)", 0xFFFFFF)
        o("  tape-auth verify           Authenticate the inserted tape (admin)", 0xFFFFFF)
        o("  tape-auth info             Identify the card (no secret needed)", 0xFFFFFF)
        o("", 0xFFFFFF)
        o(" Personal log (operator-passphrase encrypted, lives on the card):", 0x00FF00)
        o("  tape-auth log add <pass> <text>      Append an entry", 0xFFFFFF)
        o("  tape-auth log list <pass>            Show all entries", 0xFFFFFF)
        o("  tape-auth log remove <pass> <n>      Delete entry n", 0xFFFFFF)
        o("  tape-auth log clear <pass>           Wipe the log", 0xFFFFFF)
        o("  tape-auth log passwd <old> <new>     Change the passphrase", 0xFFFFFF)
        o("", 0xFFFFFF)
        o(" Personal menu (your launcher toolbox, travels on the card):", 0x00FF00)
        o("  tape-auth menu add <pass> <Label> -- <cmd> Add a menu item", 0xFFFFFF)
        o("  tape-auth menu list <pass>                Show items", 0xFFFFFF)
        o("  tape-auth menu remove <pass> <n>          Delete item n", 0xFFFFFF)
        o("  tape-auth menu passwd <old> <new>         Change the passphrase", 0xFFFFFF)
        o("  tape-auth menu clear <pass>               Wipe the menu", 0xFFFFFF)
        o("  (-- separates label from command; an unquoted | is a pipe)", 0xAAAAAA)
        o("  Then open it with:  launcher tape", 0xAAAAAA)
      end
    end,
  },
  -- Test hooks (pure wire-format functions). pkg only reads `.commands`, so
  -- exposing these for off-box format tests is harmless at runtime.
  _format = {
    parseImage = parseImage,
    buildImage = buildImage,
    makeBody   = function(label, issuedAt)
      return MAGIC_V2 .. packU32(issuedAt or 0) .. packU16(#label) .. label
    end,
  },
}
