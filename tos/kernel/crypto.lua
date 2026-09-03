-- ╔══════════════════════════════════════╗
-- ║  TOS Security - Crypto Module        ║
-- ║  Software hashing + optional HW      ║
-- ╚══════════════════════════════════════╝
-- Priority: RELIABILITY over speed.
-- Uses data card (SHA-256) if available,
-- falls back to software DJB2+FNV1a dual hash.

local component = require("component")
local computer = require("computer")

local crypto = {}

-- ============================================================
-- Hardware detection
-- ============================================================
local dataCard = nil
local hwCrypto = false

function crypto.init()
  -- Check for data card (Tier 1 has md5, Tier 2+ has sha256, encrypt)
  local ok, _ = pcall(function()
    for addr in component.list("data") do
      dataCard = component.proxy(addr)
      hwCrypto = true
      return
    end
  end)
  return hwCrypto
end

function crypto.hasHardware()
  return hwCrypto
end

-- ============================================================
-- Software hash (no dependencies)
-- Combines DJB2 + FNV-1a for reasonable collision resistance.
-- NOT cryptographically secure, but sufficient for password
-- protection in a Minecraft environment.
-- ============================================================

-- DJB2 hash
local function djb2(str)
  local hash = 5381
  for i = 1, #str do
    -- hash * 33 + byte, keep within Lua integer range
    hash = ((hash << 5) + hash + str:byte(i)) & 0xFFFFFFFF
  end
  return hash
end

-- FNV-1a hash
local function fnv1a(str)
  local hash = 0x811C9DC5  -- FNV offset basis (32-bit)
  for i = 1, #str do
    hash = hash ~ str:byte(i)
    hash = (hash * 0x01000193) & 0xFFFFFFFF  -- FNV prime
  end
  return hash
end

--- Software hash: returns 16-char hex string from dual hash
local function softHash(data)
  local h1 = djb2(data)
  local h2 = fnv1a(data)
  return string.format("%08x%08x", h1, h2)
end

-- ============================================================
-- Software SHA-256 (pure Lua) — now lives in kernel.sha256 so the
-- release build can use it without the machine globals. crypto still
-- prefers the data card's hardware SHA-256 (crypto.hash below).
-- ============================================================
local sha256_hex = require("kernel.sha256").hex

-- ============================================================
-- Public hashing API
-- ============================================================

--- Hash a string. Uses SHA-256 if data card available, else software hash.
-- @param data string: Data to hash
-- @return string: Hex-encoded hash
function crypto.hash(data)
  if dataCard then
    local ok, result = pcall(function()
      local raw = dataCard.sha256(data)
      local hex = {}
      for i = 1, #raw do
        hex[#hex + 1] = string.format("%02x", raw:byte(i))
      end
      return table.concat(hex)
    end)
    if ok and result then return result end
  end

  -- Software SHA-256 fallback (stable across boots)
  return sha256_hex(data)
end

--- Constant-time string comparison (#37).
-- Avoids early-exit timing leaks that let attackers byte-by-byte a
-- comparison. Both operands must be non-nil strings; unequal lengths
-- still compare in constant time over max(#a, #b).
local function ctEquals(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  local la, lb = #a, #b
  local n = la > lb and la or lb
  local diff = la ~ lb
  for i = 1, n do
    local ba = i <= la and a:byte(i) or 0
    local bb = i <= lb and b:byte(i) or 0
    diff = diff | (ba ~ bb)
  end
  return diff == 0
end
crypto.ctEquals = ctEquals

-- Password stretch iterations.
-- #SEC H17 / #PERF — a single, modest round count for ALL boxes.
--
-- History: an earlier build bumped data-card boxes to 10000 rounds on the
-- theory that hardware SHA made iteration "almost free." That was wrong on
-- two counts:
--   1. In OpenComputers the expensive thing is the *component call*, not the
--      hash. Each dataCard.sha256() draws from a per-tick call budget; once
--      it's spent the computer SLEEPS until the next server tick (~50 ms). A
--      10000-round v3 verify makes ~20000 such calls, so it stalled boot/login
--      to ~150 s. The iterated KDF therefore runs in pure Lua (see shaHex
--      below) — no component calls, no tick-sleeps.
--   2. Round count buys offline-cracking resistance proportional to the
--      attacker's per-guess cost. A real attacker who steals /etc/users.dat
--      cracks on GPUs doing billions of SHA-256/s, where even 10^5 rounds is
--      microseconds. No round count *computable on an OC box* meaningfully
--      slows that. The salt (anti-rainbow-table) is the protection that
--      actually holds; rounds beyond a token amount are theater that only
--      taxes legitimate login.
-- So: one count, fast in pure Lua, same on every box. The stored hash still
-- carries its round count, so older records (incl. legacy 10000-round ones)
-- keep verifying and are rehashed to the current count on next login.
local PW_ROUNDS = 256
local function effectiveRounds()
  return PW_ROUNDS
end

-- Legacy 2-round hash (pre-1.2.6). Kept ONLY so existing user DBs still
-- verify; new writes always use hashPassword() below.
local function hashPasswordLegacy(password, salt)
  local pass1 = crypto.hash(salt .. password)
  local pass2 = crypto.hash(pass1 .. salt .. "tos")
  return pass2
end

-- Legacy software-only stretched form (the bare 64-hex that software-only
-- boxes wrote before v3 became universal): SHA-256 of (salt||password||"tos")
-- iterated PW_ROUNDS times. Kept ONLY for verification of pre-upgrade
-- accounts; a match flags the record for rehash to v3. Uses software
-- sha256_hex (identical output to dataCard.sha256, but no per-call component
-- budget / tick-sleeps even during this one-time migration verify).
local function hashPasswordSw256(password, salt, rounds)
  local h = sha256_hex(salt .. password .. "tos")
  for _ = 2, (rounds or PW_ROUNDS) do
    h = sha256_hex(h .. salt)
  end
  return h
end

-- Forward-declared HMAC-SHA256 helper, defined further down. We use it
-- inside the password KDF as the per-round primitive (PBKDF2-ish).
local hmacSha256
local function pwInner(password, salt, rounds)
  -- HMAC(secret=salt||"tos", msg=password) seeded; chain via HMAC over
  -- (h || counter) for each round. Same output shape (64 hex) as the
  -- legacy iterated-hash form so callers don't notice.
  local key = salt .. "tos"
  local h = hmacSha256(key, password)
  for i = 2, rounds do
    h = hmacSha256(key, h .. string.char(i & 0xFF, (i >> 8) & 0xFF))
  end
  return h
end

-- #SEC M9 — v3 KDF with explicit NUL delimiter between salt and password.
-- The previous formula `salt..password` was ambiguous in principle: for
-- some pair (saltA||passA) == (saltB||passB), the hash would collide. The
-- 16-char fixed salt bounded the practical attack, but a future variable-
-- length salt would re-open it. v3 inserts an unambiguous delimiter so
-- the construction is delimiter-injection-safe regardless of salt length.
local function pwInnerV3(password, salt, rounds)
  -- Distinct domain-separation key from v2 so existing v2 hashes can
  -- never collide with v3 outputs even for the same (password, salt).
  local key = salt .. "\0tos.v3"
  local h = hmacSha256(key, password .. "\0" .. salt)
  for i = 2, rounds do
    h = hmacSha256(key, h .. "\0" .. string.char(i & 0xFF, (i >> 8) & 0xFF))
  end
  return h
end

--- Hash a password with a salt.
-- Output is 64-hex chars (legacy) or "vN$rounds$hex".
-- @param password string: The password
-- @param salt string: The salt (use crypto.salt() to generate)
-- @return string: Salted hash
function crypto.hashPassword(password, salt)
  local rounds = effectiveRounds()
  -- v3 (delimiter-injection-safe KDF) is now the universal write format on
  -- every box. The KDF runs in pure Lua at a modest round count (see the
  -- PW_ROUNDS note), so login latency stays low whether or not a data card
  -- is present, and all new accounts get the stronger construction. Older
  -- bare-hex / v2 / high-round records still verify and are rehashed to this
  -- form on next successful login.
  return "v3$" .. tostring(rounds) .. "$" .. pwInnerV3(password, salt, rounds)
end

--- Verify a password against a stored hash.
-- Returns (ok, needsRehash). needsRehash = true when the stored hash
-- is in a legacy format and the caller should upgrade it via
-- hashPassword() + write-back on successful auth.
function crypto.verifyPassword(password, salt, storedHash)
  -- Nil-safe input gating: a corrupted users DB (missing salt/hash) must
  -- not crash login — we just fail the verify and let the caller emit
  -- the normal "invalid credentials" error. password = nil is also
  -- treated as a failed attempt rather than a runtime error.
  if type(storedHash) ~= "string" then return false, false end
  if type(password) ~= "string"   then return false, false end
  if type(salt) ~= "string"       then return false, false end

  -- #SEC M9 — v3 tagged format with delimiter-safe KDF.
  -- "v3$<rounds>$<64hex>".
  local v3Rounds, v3Hex = storedHash:match("^v3%$(%d+)%$(%x+)$")
  if v3Rounds and v3Hex and #v3Hex == 64 then
    local rounds = tonumber(v3Rounds)
    if rounds and rounds >= 1 and rounds <= 100000 then
      if ctEquals(pwInnerV3(password, salt, rounds), v3Hex) then
        -- needsRehash whenever the stored round count differs from the
        -- current one — in EITHER direction. This both raises older
        -- low-round records and, importantly, lowers the legacy 10000-round
        -- records written by the old "hardware-accelerated" build down to
        -- the current fast count, so a one-time slow verify becomes a fast
        -- one on every subsequent login.
        local cur = effectiveRounds()
        return true, (rounds ~= cur)
      end
    end
    return false, false
  end

  -- #SEC H17 — v2 tagged format: "v2$<rounds>$<64hex>" (deprecated
  -- but still accepted for back-compat). v2 matches are ALWAYS flagged
  -- as needing rehash, so the next successful login upgrades to v3.
  local roundsStr, hex = storedHash:match("^v2%$(%d+)%$(%x+)$")
  if roundsStr and hex and #hex == 64 then
    local rounds = tonumber(roundsStr)
    if rounds and rounds >= 1 and rounds <= 100000 then
      if ctEquals(pwInner(password, salt, rounds), hex) then
        return true, true  -- always rehash v2 → v3
      end
    end
    return false, false
  end

  -- Bare 64-hex (pre-v3) records. hashPassword() now always emits "v3$…",
  -- so a bare hash can only be one of the older forms. Try them in turn;
  -- any match flags the record for rehash to v3.
  if #storedHash == 64 then
    -- Software-only stretched form: iterated SHA-256 of (salt||pw||"tos").
    if ctEquals(hashPasswordSw256(password, salt, PW_ROUNDS), storedHash) then
      return true, true
    end
    -- Pre-1.2.6 two-round legacy form.
    if ctEquals(hashPasswordLegacy(password, salt), storedHash) then
      return true, true
    end
    return false, false
  end

  -- Very old: softHash-based (16 hex). The audit flagged this as
  -- preimage-attackable in a few minutes of CPU (DJB2+FNV-1a is two
  -- 32-bit linear hashes; meet-in-the-middle reveals the password).
  -- #SEC C12 — refuse outright. Any account still on this format gets
  -- a deliberate authentication failure; the operator must run a root
  -- password-reset (or, for non-root accounts, an admin can clear the
  -- hash and prompt the user). Continuing to accept these would make
  -- the rest of the password-security stack meaningless.
  if #storedHash == 16 then
    -- log isn't a module-level upvalue in crypto.lua; opportunistic require.
    pcall(function()
      local logMod = require("kernel.log")
      if logMod and logMod.warn then
        logMod.warn("crypto", "Refused legacy 16-hex hash; account must be reset")
      end
    end)
    return false, false
  end

  return false, false
end

-- ============================================================
-- Salt / token generation
-- ============================================================

-- ============================================================
-- Local RNG (#32) — never touches math.randomseed.
-- The old fallback reseeded the global math.random every call,
-- which is both unpredictable for clients that rely on math.random
-- and, in a loop, can produce correlated output when uptime moves
-- slower than the call rate. This is a tiny xorshift64* driven by
-- a one-time entropy pool, plus hash-mixing of the live entropy
-- sources on every byte.
local _rngState = 0
local _rngCounter = 0
local function rngMixEntropy()
  _rngCounter = _rngCounter + 1
  -- Combine as much live entropy as we can grab into a string, then
  -- SHA-256 it to get a 256-bit seed. Cheap but much better than
  -- seeding a single 31-bit value from `uptime*1e6`.
  local pool = table.concat({
    tostring(computer.uptime()),
    tostring(computer.freeMemory()),
    tostring(computer.totalMemory and computer.totalMemory() or 0),
    tostring(_rngCounter),
    tostring(_rngState),
    tostring({}),  -- table address changes each call
  }, "|")
  local h = sha256_hex(pool)
  -- Fold the 256-bit hash down into a 64-bit state
  local s = 0
  for i = 1, 16 do
    s = ((s << 4) | tonumber(h:sub(i, i), 16)) & 0xFFFFFFFFFFFFFFFF
  end
  if s == 0 then s = 0xDEADBEEFCAFEBABE end
  _rngState = s
end

local function rngNext()
  if _rngState == 0 then rngMixEntropy() end
  -- xorshift64*
  local x = _rngState
  x = x ~ (x >> 12); x = x & 0xFFFFFFFFFFFFFFFF
  x = x ~ (x << 25); x = x & 0xFFFFFFFFFFFFFFFF
  x = x ~ (x >> 27); x = x & 0xFFFFFFFFFFFFFFFF
  _rngState = x
  return (x * 0x2545F4914F6CDD1D) & 0xFFFFFFFFFFFFFFFF
end

-- ============================================================
-- #SEC H-6 — persistent cross-boot entropy + degraded-mode notice.
-- On a box with no data card the RNG seed is mixed only from live,
-- partly-observable values (uptime, freeMemory) plus a heap-address
-- sample — adequate, but NOT a true CSPRNG. Session tokens derive from
-- this RNG, so a predictable seed risks token guessing / session
-- hijack. Two mitigations:
--   * The kernel feeds a persisted entropy blob in at boot via
--     crypto.addEntropy() and writes a fresh one back with
--     crypto.exportEntropy(), so seed unpredictability accumulates
--     across reboots (an attacker who can't read the on-disk pool
--     can't reconstruct the seed from public timing alone).
--   * A one-time warning marks software-only boxes as cryptographically
--     degraded so operators of security-grade deployments know to add a
--     data card.
-- ============================================================

--- Fold externally-supplied entropy into the RNG pool. Never weakens the
-- pool: the hash-derived value is XORed into the state, so a low-quality
-- (or even attacker-known) seed cannot reduce existing entropy.
function crypto.addEntropy(seed)
  if type(seed) ~= "string" or seed == "" then return false end
  local mixed = sha256_hex(seed .. "|" .. tostring(_rngState) .. "|" .. tostring(_rngCounter))
  local s = 0
  for i = 1, 16 do
    s = ((s << 4) | tonumber(mixed:sub(i, i), 16)) & 0xFFFFFFFFFFFFFFFF
  end
  _rngState = (_rngState ~ s) & 0xFFFFFFFFFFFFFFFF
  if _rngState == 0 then _rngState = (s ~= 0) and s or 0xA5A5A5A5A5A5A5A5 end
  _rngCounter = _rngCounter + 1
  return true
end

--- Export raw random bytes for the kernel to persist for the next boot.
-- Default 32 bytes (256 bits). Re-mixes live entropy first so each export
-- is independent.
function crypto.exportEntropy(n)
  n = (type(n) == "number" and n > 0) and math.floor(n) or 32
  rngMixEntropy()
  local out = {}
  for i = 1, n do
    out[i] = string.char(rngNext() & 0xFF)
  end
  return table.concat(out)
end

-- One-time degraded-RNG warning (software-only box minting security
-- material). Emitted lazily so headless/test loads don't depend on log.
local _rngDegradedWarned = false
local function warnDegradedRng()
  if _rngDegradedWarned or dataCard then return end
  _rngDegradedWarned = true
  pcall(function()
    local logMod = require("kernel.log")
    if logMod and logMod.warn then
      logMod.warn("crypto",
        "No data card — session tokens/salts use the software RNG (degraded; not a CSPRNG)")
    end
  end)
end

--- Generate a random salt string
-- Uses data card random() for hardware entropy when available,
-- falls back to the local xorshift64* RNG seeded from system entropy.
function crypto.salt(length)
  length = length or 16
  local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local nChars = #chars  -- 62
  -- #SEC M10 — rejection-sampling helper. The naive `b % 62` over a
  -- uniform 8-bit byte (0..255) maps 256 inputs onto 62 slots; slots
  -- 0..7 each receive 5 hits while slots 8..61 receive 4. That's a
  -- ~25% over-representation of the first 8 chars. We reject bytes
  -- outside the largest multiple of 62 that fits in 256 (i.e. 248)
  -- and resample. Same idea over the 64-bit RNG output: reject
  -- anything above the largest multiple of 62 that fits in 2^64.
  local function pickFromByte(b)
    -- 248 = 62 * 4 — the largest multiple of nChars that fits in 256.
    if b >= 248 then return nil end
    return chars:sub((b % nChars) + 1, (b % nChars) + 1)
  end
  -- Largest multiple of nChars (62) that fits in 2^64. 2^64 mod 62 = 16, so
  -- the limit is 2^64 - 16 = 0xFFFFFFFFFFFFFFF0. Draws below it map onto the
  -- 62 slots uniformly; draws at or above it are rejected and resampled.
  --
  -- TWO subtleties, both of which the previous constant got wrong:
  --   1. Lua 5.4 integers are signed 64-bit, so a literal above 2^63 (like
  --      this limit) is a NEGATIVE value. rngNext() likewise returns signed
  --      results, so a plain `r < RNG_LIMIT` is a SIGNED compare that rejects
  --      ~half of all draws (every non-negative one). We must compare
  --      UNSIGNED via math.ult.
  --   2. The old value (0xFFFFFFFFFFFFFE1C) encoded 2^64-484, from a wrong
  --      `2^64 mod 62` of 372/484. Combined with the signed compare it threw
  --      away half the RNG output AND skewed the surviving distribution —
  --      defeating this very rejection-sampling step on software-only boxes.
  local RNG_LIMIT = 0xFFFFFFFFFFFFFFF0  -- 2^64 - (2^64 mod 62) = 2^64 - 16
  local function pickFromRng()
    while true do
      local r = rngNext()
      if math.ult(r, RNG_LIMIT) then
        return chars:sub((r % nChars) + 1, (r % nChars) + 1)
      end
    end
  end
  -- If data card is available, use its hardware random bytes (with
  -- rejection sampling).
  if dataCard then
    local result = {}
    local idx = 1
    while idx <= length do
      local ok, raw = pcall(dataCard.random, length * 2)  -- over-fetch to amortize
      if not ok or not raw then break end
      for i = 1, #raw do
        if idx > length then break end
        local pick = pickFromByte(raw:byte(i))
        if pick then result[idx] = pick; idx = idx + 1 end
      end
    end
    if idx > length then return table.concat(result) end
    -- Fall through to software path if data card path didn't fill.
  end
  -- Fallback: local RNG. Re-mix live entropy on every salt() call so
  -- back-to-back calls with no timer tick in between still diverge
  -- (table address + counter changes each call).
  rngMixEntropy()
  local result = {}
  for i = 1, length do
    result[i] = pickFromRng()
  end
  return table.concat(result)
end

--- Generate a session token (#35). Mixes two independent salt() calls
-- plus uptime and a monotonic counter; hashing makes the token
-- length-stable and hides the internal entropy mixing.
local _tokenCounter = 0
function crypto.token()
  warnDegradedRng()  -- #SEC H-6 — surface software-only RNG once.
  _tokenCounter = _tokenCounter + 1
  return crypto.hash(crypto.salt(32)
    .. crypto.salt(16)
    .. tostring(computer.uptime())
    .. tostring(_tokenCounter))
end

-- ============================================================
-- Simple XOR cipher for network messages
-- NOT secure against determined attackers, but prevents
-- casual packet sniffing on MC servers.
-- On Tier 2+ data card, uses real AES if available.
-- ============================================================

--- XOR encrypt/decrypt (symmetric)
local function xorCipher(data, key)
  local result = {}
  local keyLen = #key
  for i = 1, #data do
    local keyByte = key:byte(((i - 1) % keyLen) + 1)
    result[i] = string.char(data:byte(i) ~ keyByte)
  end
  return table.concat(result)
end

-- Track whether we've already logged the XOR-fallback warning for a
-- given boot — we only want to tell the operator once per session.
local _xorWarned = false

-- #SEC C13 — produce a 16-byte raw-bytes IV. The old implementation used
-- crypto.salt(16) which returns an alphanumeric string (62-char alphabet),
-- shrinking IV space from 2^128 to ~2^95 and fingerprinting TOS traffic
-- as all-printable on the wire. With a data card we use its hardware RNG;
-- otherwise we pack two 64-bit xorshift64* outputs into raw bytes.
local function makeIv16()
  if dataCard then
    local ok, raw = pcall(dataCard.random, 16)
    if ok and type(raw) == "string" and #raw == 16 then
      return raw
    end
  end
  rngMixEntropy()
  local out = {}
  for i = 1, 2 do
    local n = rngNext()
    for shift = 56, 0, -8 do
      out[#out + 1] = string.char((n >> shift) & 0xFF)
    end
  end
  return table.concat(out)
end
crypto._makeIv16 = makeIv16  -- exposed for tests; not part of the public API

--- Encrypt data with a shared key
function crypto.encrypt(data, key)
  if dataCard then
    -- Try hardware encryption (Tier 2 data card)
    local ok, result = pcall(function()
      -- Data card encrypt uses AES; IV is 16 raw random bytes (#SEC C13).
      local iv = makeIv16()
      local encrypted = dataCard.encrypt(data, key, iv)
      -- Prepend IV so we can decrypt later
      return iv .. encrypted
    end)
    if ok and result then
      return result, "aes"
    end
  end
  -- Fallback: XOR cipher with hashed key (#34). This is NOT secure
  -- against a motivated attacker; log a loud warning the first time
  -- we fall back so operators know they're running without real
  -- confidentiality.
  if not _xorWarned then
    _xorWarned = true
    pcall(function()
      local log = require("kernel.log")
      if log then
        log.warn("crypto", "No data card — encryption falling back to XOR (not secure)")
      end
    end)
  end
  local hashedKey = crypto.hash(key)
  return xorCipher(data, hashedKey), "xor"
end

--- Decrypt data with a shared key.
-- Strict method dispatch: an "aes" packet must decrypt via the data
-- card, a "xor" packet must decrypt via xorCipher. Any other method
-- value (or an AES packet on a box without a data card) returns nil
-- so the net layer's #46 drop path can reject it cleanly. Silent
-- cross-algorithm fallback produced attacker-controlled garbage that
-- then had to be caught downstream.
function crypto.decrypt(data, key, method)
  if type(data) ~= "string" or type(key) ~= "string" then
    return nil
  end
  if method == "aes" then
    if not dataCard then return nil end
    if #data < 17 then return nil end  -- needs at least IV + 1 byte
    local ok, result = pcall(function()
      local iv = data:sub(1, 16)
      local ciphertext = data:sub(17)
      return dataCard.decrypt(ciphertext, key, iv)
    end)
    if ok and result then return result end
    return nil
  end
  if method == "xor" then
    local hashedKey = crypto.hash(key)
    return xorCipher(data, hashedKey)
  end
  -- Unknown or missing method — refuse.
  return nil
end

-- ============================================================
-- Data integrity
-- ============================================================

--- Compute a checksum for data integrity verification (#36).
-- Returns a 64-char SHA-256 hex digest. The old FNV-1a 32-bit result
-- collided once every ~65k inputs (birthday bound) — fine for
-- accidental corruption, useless against a crafted payload. We keep
-- the name but upgrade the algorithm.
function crypto.checksum(data)
  return crypto.hash(data)
end

-- ── HMAC-SHA256 (#33) ────────────────────────────────────────
-- H(K ⊕ opad || H(K ⊕ ipad || msg)). Protects against
-- length-extension attacks that plague plain H(msg||key). 64-byte
-- block size, as per SHA-256.
local HMAC_BLOCK = 64

-- #PERF — SHA primitive for the HMAC (and therefore the iterated password
-- KDF and every per-packet network MAC). This MUST be the in-process software
-- sha256_hex, NOT the data card.
--
-- Why: in OpenComputers a component call (dataCard.sha256) is the costly
-- operation — each draws from a per-tick call budget and, once spent, sleeps
-- the computer until the next server tick (~50 ms). HMAC calls this twice per
-- round and the KDF runs it hundreds of times, so routing it through the data
-- card turned login into thousands of tick-sleeps (measured: ~150 s boot on a
-- data-card box). A pure-Lua hash burns CPU but never yields, so the whole
-- chain completes in well under a second.
--
-- This is purely a speed choice: sha256_hex and dataCard.sha256 produce the
-- identical standard SHA-256 digest, so stored password hashes verify
-- unchanged and a data-card box's MACs still match a software-only peer's.
-- The data card is still used where the call count is tiny and the payload
-- can be large — one-shot crypto.hash (checksums/verify), AES encrypt/decrypt,
-- and hardware RNG.
local function shaHex(s)
  return sha256_hex(s)
end

-- Assign to the forward-declared upvalue (don't re-`local` it — that
-- would shadow the forward decl and leave pwInner with nil).
hmacSha256 = function(key, msg)
  -- Shorten over-long keys via a plain hash round first.
  if #key > HMAC_BLOCK then
    local hexed = shaHex(key)
    -- Convert the hex digest back to raw bytes (32 bytes).
    local raw = {}
    for i = 1, 32 do
      raw[i] = string.char(tonumber(hexed:sub(i * 2 - 1, i * 2), 16))
    end
    key = table.concat(raw)
  end
  if #key < HMAC_BLOCK then
    key = key .. string.rep("\0", HMAC_BLOCK - #key)
  end
  local ipad, opad = {}, {}
  for i = 1, HMAC_BLOCK do
    local kb = key:byte(i)
    ipad[i] = string.char(kb ~ 0x36)
    opad[i] = string.char(kb ~ 0x5C)
  end
  local ipadS, opadS = table.concat(ipad), table.concat(opad)
  -- Inner: hex digest → convert to raw bytes → prepend opad → hash.
  local innerHex = shaHex(ipadS .. msg)
  local innerRaw = {}
  for i = 1, 32 do
    innerRaw[i] = string.char(tonumber(innerHex:sub(i * 2 - 1, i * 2), 16))
  end
  return shaHex(opadS .. table.concat(innerRaw))
end
crypto.hmac = hmacSha256

--- Sign data with HMAC-SHA256 (#33). Replaces H(data||secret), which
-- was vulnerable to length-extension forgery.
function crypto.sign(data, secret)
  return hmacSha256(secret or "", data or "")
end

return crypto
