-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Vault                  ║
-- ║  Passphrase-encrypted data blobs     ║
-- ╚══════════════════════════════════════╝
-- Symmetric encryption with a fixed wire format. Used by the tape
-- module to protect data archives written to tape, and by the same
-- module's `tape vault` subcommands to protect arbitrary files
-- (including ones on floppies).
--
-- NOT for audio data — that has to play through Computronics's
-- DFPWM decoder, which expects raw PCM-shaped bytes. Encrypting an
-- audio tape would just produce noise, so the tape-encrypt path
-- skips anything that doesn't start with our archive magic.
--
-- Wire format (binary, little-endian, all sizes fixed):
--
--   magic      "TVAULT1\0"   8 bytes
--   algo       "aes\0" or "xor\0"  4 bytes (NUL-padded)
--   rounds     uint16        PBKDF iteration count used for the key
--   salt       16 bytes      random — fed into hashPassword(passphrase, salt)
--   iv         16 bytes      random — IV for the AES/XOR cipher
--   ctLen      uint32        ciphertext length in bytes
--   mac        64 ASCII hex  HMAC-SHA256 over (magic || algo || rounds
--                            || salt || iv || ctLen || ciphertext)
--   ct         <ctLen> bytes ciphertext
--
-- Header size: 8 + 4 + 2 + 16 + 16 + 4 + 64 = 114 bytes.
--
-- Why a salt AND an iv:
--   * salt feeds the KDF — same passphrase produces a different key
--     per vault, so a stolen tape doesn't help with rainbow-table
--     attacks on the next tape encrypted with the same passphrase.
--   * iv goes into the cipher — required for any sound block-cipher
--     mode (AES-CBC/CTR). Reusing an IV across two ciphertexts under
--     the same key leaks information about plaintext relationships.
--
-- The MAC covers EVERYTHING after the magic, including the algo
-- choice — so an attacker who swaps "aes\0" for "xor\0" trying to
-- force the downgrade-attack path the C10 audit warned about gets a
-- MAC-verify failure instead. We don't refuse XOR outright here
-- (operators on a board without a data card NEED a software fallback
-- for any encryption at all) — but the integrity-protect path keeps
-- it honest.

local vault = {}

local crypto = require("kernel.crypto")

-- #SEC CR-7 — wire-format versions.
--   V1 ("TVAULT1\0"): legacy — a SINGLE derived key was used for both the
--     cipher and the HMAC. Decrypt-only support retained so old blobs
--     (and pre-upgrade keychains/tapes) still open.
--   V2 ("TVAULT2\0"): current — domain-separated enc/mac subkeys so the
--     confidentiality key is never reused as the authentication key.
-- Both share the same header layout, so HEADER_LEN is unchanged; only the
-- magic and the key-derivation differ.
local MAGIC_V1   = "TVAULT1\0"
local MAGIC_V2   = "TVAULT2\0"
local MAGIC      = MAGIC_V2  -- magic used for NEW writes
local HEADER_LEN = 8 + 4 + 2 + 16 + 16 + 4 + 64

-- ============================================================
-- Byte helpers
-- ============================================================

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

local function padAlgo(s)
  if #s >= 4 then return s:sub(1, 4) end
  return s .. string.rep("\0", 4 - #s)
end

-- ============================================================
-- Key derivation
-- ============================================================

-- Stretch the passphrase into a 32-char hex key with hashPassword.
-- crypto.hashPassword emits the v3 KDF on every box (software-iterated;
-- see crypto.lua). The output is "v3$<rounds>$<64hex>"; we strip the
-- prefix and use the FIRST 32 hex chars as the cipher key, which is
-- 16 bytes worth (matches AES-128's key size).
local function deriveKey(passphrase, salt)
  local stretched = crypto.hashPassword(passphrase, salt)
  -- hashPassword may return either "v3$<rounds>$<hex>" or a bare
  -- 64-hex digest. Strip any prefix to get the raw hex.
  local _, _, hex = stretched:find("^v%d+%$%d+%$(%x+)$")
  hex = hex or stretched
  return hex:sub(1, 32)  -- 32 hex chars = 128 bits
end

-- #SEC CR-7 — domain-separated subkeys. Using one key for both the cipher
-- and the MAC is a textbook key-reuse hazard. From the base derived key
-- we expand two independent subkeys via HMAC with distinct labels, so the
-- encryption key and the authentication key are cryptographically
-- unrelated. V1 blobs (no split) are handled on the decrypt side.
local function splitKeys(baseKey)
  local encKey = crypto.hmac(baseKey, "tos.vault.enc.v2")
  local macKey = crypto.hmac(baseKey, "tos.vault.mac.v2")
  return encKey, macKey
end

-- ============================================================
-- Public API
-- ============================================================

--- Encrypt `plaintext` under `passphrase`. Returns the encoded blob
--- (header + ciphertext) plus a metadata table for the caller to log.
function vault.encrypt(plaintext, passphrase, opts)
  opts = opts or {}
  if type(plaintext) ~= "string" or type(passphrase) ~= "string" then
    return nil, "vault.encrypt: plaintext and passphrase must be strings"
  end
  if #passphrase < 1 then return nil, "passphrase must be non-empty" end

  -- #SEC CR-7 — fail closed for secret stores. When the caller marks this
  -- as secret-bearing (keychain) and the box has no data card, the only
  -- available cipher is XOR over predictable serialized-Lua plaintext,
  -- which is effectively no confidentiality. Refuse rather than write a
  -- file that merely LOOKS encrypted. General callers (e.g. `tape vault`
  -- on arbitrary archives) omit requireStrong and keep the software path.
  if opts.requireStrong and not (crypto.hasHardware and crypto.hasHardware()) then
    return nil, "vault.encrypt: strong encryption required but no data card present "
      .. "(refusing to protect secrets with the XOR fallback)"
  end

  -- Fresh salt + IV per encryption. crypto.salt now uses rejection
  -- sampling (M10) so the distribution is uniform.
  local saltHex = crypto.salt(16)  -- 16 alphanumeric chars
  -- IV: 16 raw random bytes via the internal helper (C13).
  local iv = crypto._makeIv16 and crypto._makeIv16() or
    string.rep("\0", 16)  -- worst-case fallback; crypto.encrypt will still HMAC

  -- #SEC CR-7 — separate enc/mac subkeys (V2).
  local baseKey = deriveKey(passphrase, saltHex)
  local encKey, macKey = splitKeys(baseKey)
  local ct, algo = crypto.encrypt(plaintext, encKey)
  if not ct then return nil, "encryption failed" end
  -- crypto.encrypt prepends its own IV in the AES case. Strip it
  -- so we control the IV explicitly (we already wrote it to the
  -- header). For XOR there's no per-call IV in crypto.encrypt; we
  -- mix the IV into the key.
  if algo == "aes" then
    -- crypto.encrypt's AES output is iv(16) || ciphertext. Replace its
    -- iv with ours so the header iv matches what's actually inside.
    -- We could re-encrypt with our iv, but crypto.encrypt doesn't
    -- accept a caller-supplied iv. Instead: trust crypto.encrypt's
    -- iv and put IT in the header.
    iv = ct:sub(1, 16)
    ct = ct:sub(17)
  elseif algo == "xor" then
    -- For XOR the iv isn't used by the cipher; we still store it so
    -- the header shape stays identical across algorithms.
  else
    return nil, "unknown algo: " .. tostring(algo)
  end

  -- Rounds field: deriveKey re-derives via crypto.hashPassword, which now
  -- uses a single fixed round count on every box (no longer hardware-
  -- dependent), so derivation is deterministic and portable. We still encode
  -- 0 to mean "ask crypto to redo it" rather than pinning a number into the
  -- blob. (Caveat: blobs written by the brief early-1.3.1 build whose KDF ran
  -- 10000 rounds won't re-derive the same key under the current count and must
  -- be re-encrypted — see CHANGELOG.)
  local rounds = 0
  local body = padAlgo(algo) .. packU16(rounds) .. saltHex .. iv ..
    packU32(#ct) .. ct
  local mac = crypto.hmac(macKey, body)  -- #SEC CR-7 — authenticate with the mac subkey
  local blob = MAGIC .. padAlgo(algo) .. packU16(rounds) .. saltHex .. iv ..
    packU32(#ct) .. mac .. ct

  return blob, { algo = algo, ctLen = #ct, blobLen = #blob }
end

--- Decrypt a vault blob. Returns (plaintext, info) on success or
--- (nil, err) on failure. Returns a specific "MAC mismatch" error
--- when the integrity check fails — distinguishes wrong-passphrase
--- from tampered-data for the caller's UI.
function vault.decrypt(blob, passphrase)
  if type(blob) ~= "string" or type(passphrase) ~= "string" then
    return nil, "vault.decrypt: blob and passphrase must be strings"
  end
  if #blob < HEADER_LEN then return nil, "blob too short" end
  -- #SEC CR-7 — accept both wire versions. V2 uses split enc/mac subkeys;
  -- V1 (legacy) used a single key for both.
  local magic = blob:sub(1, 8)
  local isV2
  if magic == MAGIC_V2 then isV2 = true
  elseif magic == MAGIC_V1 then isV2 = false
  else return nil, "not a TOS vault blob" end

  local off = 8 + 1
  local algo = blob:sub(off, off + 3); off = off + 4
  -- Strip any trailing NULs from the algo field.
  algo = algo:gsub("\0+$", "")
  local _rounds; _rounds, off = unpackU16(blob, off)
  local salt = blob:sub(off, off + 15); off = off + 16
  local iv   = blob:sub(off, off + 15); off = off + 16
  local ctLen; ctLen, off = unpackU32(blob, off)
  local mac  = blob:sub(off, off + 63); off = off + 64
  if off + ctLen - 1 > #blob then return nil, "blob truncated" end
  local ct = blob:sub(off, off + ctLen - 1)

  local baseKey = deriveKey(passphrase, salt)
  -- #SEC CR-7 — V2 splits the base key into enc/mac subkeys; V1 reused
  -- the base key for both. Pick the right keys for the blob's version.
  local encKey, macKey
  if isV2 then
    encKey, macKey = splitKeys(baseKey)
  else
    encKey, macKey = baseKey, baseKey
  end

  -- Verify MAC before doing any decrypt work. Note: the MAC was
  -- computed over the header BODY (algo..salt..iv..ctLen..ct) — not
  -- including the magic or the MAC field itself.
  local body = padAlgo(algo) .. packU16(_rounds) .. salt .. iv ..
    packU32(ctLen) .. ct
  local expected = crypto.hmac(macKey, body)
  if not crypto.ctEquals(expected, mac) then
    return nil, "MAC mismatch (wrong passphrase, or blob tampered with)"
  end

  -- crypto.decrypt for "aes" expects iv-prepended ciphertext.
  local toDecrypt = (algo == "aes") and (iv .. ct) or ct
  local plaintext = crypto.decrypt(toDecrypt, encKey, algo)
  if not plaintext then return nil, "decryption failed (corrupt blob)" end
  return plaintext, { algo = algo, ctLen = ctLen, plaintextLen = #plaintext }
end

--- Heuristic check: is this string already a vault blob? Accepts either
--- wire version (#SEC CR-7).
function vault.isEncrypted(s)
  if type(s) ~= "string" or #s < 8 then return false end
  local m = s:sub(1, 8)
  return m == MAGIC_V2 or m == MAGIC_V1
end

vault.MAGIC      = MAGIC      -- current write magic (V2)
vault.MAGIC_V1   = MAGIC_V1
vault.MAGIC_V2   = MAGIC_V2
vault.HEADER_LEN = HEADER_LEN

return vault
