-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Package signatures & the publisher trust store ║
-- ║                                                              ║
-- ║  THE GAP THIS CLOSES. pkg has verified file HASHES for a     ║
-- ║  long time, and hashes answer a different question than the  ║
-- ║  one an operator is actually asking. Whoever hands you the   ║
-- ║  floppy writes the files AND the digests, so a matching      ║
-- ║  hash proves the disk is not CORRUPT — never that it is from ║
-- ║  who it claims. What has really been holding the line is     ║
-- ║  CR-5's admin gate, and an admin gate is per-DISK consent:   ║
-- ║  you make the same judgement call again for every floppy.    ║
-- ║  A signature makes it per-PUBLISHER — accept a key once, and ║
-- ║  everything from that key verifies without a fresh call.     ║
-- ║                                                              ║
-- ║  THE CHAIN, and it only works whole:                         ║
-- ║      signature → manifest → hashes → files                   ║
-- ║  A signature over a manifest that declares no hashes proves  ║
-- ║  the manifest's origin and says nothing about the code, so   ║
-- ║  pkg treats "signed" and "hashed" as two gates, not one.     ║
-- ║                                                              ║
-- ║  WHAT IS SIGNED: the RAW BYTES of the manifest file as it    ║
-- ║  sits on the disk. Not a re-serialization of the parsed      ║
-- ║  table — kernel.serialize walks the table with pairs(),      ║
-- ║  whose order is not defined, so re-encoding a manifest can   ║
-- ║  produce different bytes than were signed and the signature  ║
-- ║  would fail for no reason anyone could debug. Signing the    ║
-- ║  file removes the whole question.                            ║
-- ║                                                              ║
-- ║  The signature file sits beside the manifest with its        ║
-- ║  extension swapped: package.lua → package.sig, and likewise  ║
-- ║  programs.cfg → programs.sig for an OPPM repo index. It is   ║
-- ║  DECODED AS DATA, never load()ed. A signature file is a      ║
-- ║  table written by a stranger, by definition.                 ║
-- ╚══════════════════════════════════════════════════════════════╝

local pkgsign = {}

local TRUST_FILE = "/etc/pkg_trust.cfg"
local MAX_SIG_BYTES   = 4096
local MAX_TRUST_BYTES = 8192
-- A manifest is metadata, not a payload. Anything larger than this is
-- not a manifest and does not deserve seconds of field arithmetic spent
-- proving it — refuse before verifying, never after.
local MAX_SIGNED_BYTES = 64 * 1024

local fs, serialize, log

function pkgsign.init(deps)
  deps = deps or {}
  fs        = deps.fs
  serialize = deps.serialize
  log       = deps.log
  return fs ~= nil and serialize ~= nil
end

-- ============================================================
-- Hex
-- ============================================================
local function isHex(s, n)
  return type(s) == "string" and #s == n and s:match("^%x+$") ~= nil
end

local function hexToBin(h)
  return (h:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
end

local function binToHex(b)
  return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

pkgsign.hexToBin = hexToBin
pkgsign.binToHex = binToHex

-- ============================================================
-- Fingerprints
-- ============================================================
--- A short, readable stand-in for a 64-hex-character public key.
-- Operators compare fingerprints; nobody compares 64 hex characters
-- honestly, and a check people skip is not a check. Grouped in fours
-- because that is how a human actually reads a string back to someone.
function pkgsign.fingerprint(pubHex)
  if not isHex(pubHex, 64) then return "(invalid key)" end
  local okC, crypto = pcall(require, "kernel.crypto")
  local digest
  if okC and crypto and crypto.hash then
    digest = crypto.hash(hexToBin(pubHex))
  else
    local okS, sha = pcall(require, "kernel.sha256")
    if not (okS and sha) then return pubHex:sub(1, 16) end
    digest = sha.hex(hexToBin(pubHex))
  end
  local short = tostring(digest):sub(1, 16):upper()
  return (short:gsub("(....)", "%1 "):gsub("%s+$", ""))
end

-- ============================================================
-- The trust store
-- ============================================================
-- /etc/pkg_trust.cfg — admin-writable (securefs), decoded as data:
--   {
--     requireSignature = false,   -- refuse unsigned packages outright
--     keys = { ["strata"] = "<64 hex>", ["a-friend"] = "<64 hex>" },
--   }
--
-- The LABEL is not the identity. A publisher's name in a signature file
-- is a string a stranger typed; the KEY is what is actually being
-- trusted, and the label is only how the operator refers to it locally.
-- Everything user-facing says the label the OPERATOR chose, never the
-- one the disk supplied — otherwise a floppy calling itself "Strata
-- Systems" is trusted by reading.
local _trust, _trustLoaded = nil, false

local function emptyTrust()
  return { requireSignature = false, keys = {} }
end

local function loadTrust()
  if _trustLoaded then return _trust end
  _trustLoaded = true
  _trust = emptyTrust()
  if not fs or not fs.exists or not fs.exists(TRUST_FILE) then return _trust end
  local raw = fs.readFile(TRUST_FILE)
  if not raw or #raw == 0 or #raw > MAX_TRUST_BYTES then
    if log then log.warn("pkgsign", "trust store unreadable or oversized — NO publisher keys are in force") end
    return _trust
  end
  local ok, cfg = pcall(serialize.decode, raw, { maxBytes = MAX_TRUST_BYTES })
  if not ok or type(cfg) ~= "table" then
    if log then log.warn("pkgsign", "trust store did not decode — NO publisher keys are in force") end
    return _trust
  end
  -- FAIL-CLOSED, and note which direction that is. Losing the key list
  -- makes every package read as signed-by-an-UNKNOWN-key, which needs
  -- the admin override — inconvenient, never permissive. Losing
  -- requireSignature would be the permissive direction, so a store that
  -- will not decode keeps the flag it could not read only if it is the
  -- strict value; there is nothing to read here, so it stays false and
  -- the warning above is the operator's cue.
  if cfg.requireSignature == true then _trust.requireSignature = true end
  if type(cfg.keys) == "table" then
    for label, key in pairs(cfg.keys) do
      if type(label) == "string" and #label <= 48 and label:match("^[%w%-_%.]+$")
         and isHex(key, 64) then
        _trust.keys[label] = key:lower()
      elseif log then
        log.warn("pkgsign", "ignoring malformed trust entry '" .. tostring(label) .. "'")
      end
    end
  end
  return _trust
end

function pkgsign.reloadTrust()
  _trustLoaded = false
  _trust = nil
  return loadTrust()
end

--- Trusted publishers as { {label=, key=, fingerprint=}, ... }, sorted.
function pkgsign.listKeys()
  local t = loadTrust()
  local out = {}
  for label, key in pairs(t.keys) do
    out[#out + 1] = { label = label, key = key, fingerprint = pkgsign.fingerprint(key) }
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end

function pkgsign.requiresSignature()
  return loadTrust().requireSignature == true
end

--- The label this key is trusted under, or nil.
function pkgsign.labelForKey(pubHex)
  if not isHex(pubHex, 64) then return nil end
  pubHex = pubHex:lower()
  local t = loadTrust()
  for label, key in pairs(t.keys) do
    if key == pubHex then return label end
  end
  return nil
end

local function saveTrust(t)
  if not fs or not fs.writeFile then return false, "no filesystem" end
  local body = serialize.encode({ requireSignature = t.requireSignature == true,
                                  keys = t.keys })
  local ok, err = fs.writeFile(TRUST_FILE, body)
  if not ok then return false, tostring(err or "write failed") end
  return true
end

--- Trust `pubHex` under `label`. The CALLER is responsible for the admin
--- gate — see pkg.trustAdd, which owns it so there is one gate and not
--- two implementations of the same rule.
function pkgsign.addKey(label, pubHex)
  if type(label) ~= "string" or not label:match("^[%w%-_%.]+$") or #label > 48 then
    return false, "label must be 1-48 chars of letters, digits, - _ ."
  end
  if not isHex(pubHex, 64) then
    return false, "public key must be 64 hexadecimal characters (32 bytes)"
  end
  pubHex = pubHex:lower()
  local t = loadTrust()
  -- Refuse to silently re-point an existing label at a different key.
  -- Overwriting is how a trust store quietly stops meaning what the
  -- operator thinks it means; removing and re-adding is a deliberate act.
  if t.keys[label] and t.keys[label] ~= pubHex then
    return false, "'" .. label .. "' already names a different key — remove it first"
  end
  local existing = pkgsign.labelForKey(pubHex)
  if existing and existing ~= label then
    return false, "that key is already trusted as '" .. existing .. "'"
  end
  t.keys[label] = pubHex
  local ok, err = saveTrust(t)
  if not ok then t.keys[label] = nil; return false, err end
  if log then log.info("pkgsign", "trusted publisher key '" .. label .. "' " .. pkgsign.fingerprint(pubHex)) end
  return true
end

function pkgsign.removeKey(label)
  local t = loadTrust()
  if not t.keys[label] then return false, "no trusted key named '" .. tostring(label) .. "'" end
  local old = t.keys[label]
  t.keys[label] = nil
  local ok, err = saveTrust(t)
  if not ok then t.keys[label] = old; return false, err end
  if log then log.info("pkgsign", "removed publisher key '" .. label .. "'") end
  return true
end

function pkgsign.setRequireSignature(on)
  local t = loadTrust()
  t.requireSignature = on and true or false
  return saveTrust(t)
end

-- ============================================================
-- Reading a signature file
-- ============================================================
--- Signature path for a manifest path: the extension is swapped for
--- .sig. package.lua → package.sig, programs.cfg → programs.sig.
function pkgsign.sigPathFor(manifestPath)
  if type(manifestPath) ~= "string" then return nil end
  local stem = manifestPath:match("^(.*)%.[%w]+$")
  if not stem then return manifestPath .. ".sig" end
  return stem .. ".sig"
end

--- Read and shape-check a signature file. Returns the record or nil+err.
function pkgsign.readSig(sigPath)
  if not fs or not fs.exists or not fs.exists(sigPath) then return nil, "no signature file" end
  local raw = fs.readFile(sigPath)
  if not raw or #raw == 0 then return nil, "signature file is empty" end
  if #raw > MAX_SIG_BYTES then return nil, "signature file is implausibly large" end
  local ok, rec = pcall(serialize.decode, raw, { maxBytes = MAX_SIG_BYTES })
  if not ok or type(rec) ~= "table" then return nil, "signature file did not decode" end
  if rec.alg ~= nil and rec.alg ~= "ed25519" then
    -- Named so an operator can tell "I cannot check this" from "this is
    -- wrong". A future algorithm must be a refusal here, not a silent
    -- pass and not a crash.
    return nil, "unsupported signature algorithm '" .. tostring(rec.alg) .. "'"
  end
  if not isHex(rec.key, 64) then return nil, "signature names no valid public key" end
  if not isHex(rec.sig, 128) then return nil, "signature value is malformed" end
  return {
    alg    = "ed25519",
    key    = rec.key:lower(),
    sig    = rec.sig:lower(),
    -- A LABEL THE PUBLISHER CHOSE. Display only, and never matched
    -- against the trust store: a disk that calls itself "strata" must
    -- not be trusted for saying so.
    signer = type(rec.signer) == "string" and rec.signer:sub(1, 48) or nil,
    covers = type(rec.covers) == "string" and rec.covers:sub(1, 64) or nil,
  }
end

-- ============================================================
-- The verdict
-- ============================================================
-- FOUR states, and none of them is silently any of the others:
--
--   "trusted"  signed, verified, key in the operator's store.
--   "unknown"  signed, verified, key NOT in the store. This is NOT the
--              same as unsigned and must never be shown as though it
--              were: the operator can turn it into "trusted" with one
--              `pkg trust add`, which is the entire point of the feature.
--   "unsigned" no signature file. Keeps working, because a floppy from
--              a friend is the normal case and always will be — but on
--              the admin gate it already required, and now SAYING that
--              is what is holding the line rather than leaving the
--              operator to assume something stronger.
--   "invalid"  a signature file exists and does NOT verify. The TODO's
--              three-state list does not name this one, and it is the
--              state that matters most: it is evidence, not an absence.
--              There is no override. Treating it as "unsigned" would
--              mean corrupting a signature DOWNGRADES a package to the
--              permissive path, which hands an attacker the gate.

local VERIFIED_STATES = { trusted = true, unknown = true }

--- Verify the signature (if any) over `manifestPath`.
-- @return verdict { state=, key=, fingerprint=, label=, signer=, reason= }
function pkgsign.verifyManifest(manifestPath)
  local verdict = { state = "unsigned" }
  if not fs then verdict.reason = "no filesystem"; return verdict end

  local sigPath = pkgsign.sigPathFor(manifestPath)
  if not sigPath or not fs.exists(sigPath) then
    verdict.reason = "no signature file alongside " .. tostring(manifestPath)
    return verdict
  end

  local rec, err = pkgsign.readSig(sigPath)
  if not rec then
    -- A signature file that will not parse is a BROKEN signature, not an
    -- absent one. Same reasoning as a failing one.
    return { state = "invalid", reason = err }
  end

  local body = fs.readFile(manifestPath)
  if not body then
    return { state = "invalid", reason = "cannot read the manifest the signature covers" }
  end
  if #body > MAX_SIGNED_BYTES then
    return { state = "invalid", reason = "manifest is implausibly large to be signed" }
  end
  if rec.covers then
    local base = manifestPath:match("[^/]+$")
    if base and rec.covers ~= base then
      return { state = "invalid",
               reason = "signature covers '" .. rec.covers .. "', not " .. base }
    end
  end

  -- ed25519 is required HERE and nowhere earlier. It is several hundred
  -- lines of field arithmetic that a machine with no signed packages
  -- should never pay to load, so the require sits behind the existence
  -- of an actual signature.
  local okE, ed = pcall(require, "kernel.ed25519")
  if not okE or not ed or not ed.verify then
    return { state = "invalid",
             reason = "signature present but ed25519 support is unavailable" }
  end

  local good, why = ed.verify(body, hexToBin(rec.sig), hexToBin(rec.key))
  if not good then
    return { state = "invalid", key = rec.key, signer = rec.signer,
             fingerprint = pkgsign.fingerprint(rec.key),
             reason = why or "signature does not verify" }
  end

  local label = pkgsign.labelForKey(rec.key)
  return {
    state       = label and "trusted" or "unknown",
    key         = rec.key,
    fingerprint = pkgsign.fingerprint(rec.key),
    label       = label,
    signer      = rec.signer,
  }
end

--- True when this verdict means the bytes really came from the holder of
--- that key (whether or not the operator has decided to trust them).
function pkgsign.isVerified(verdict)
  return verdict ~= nil and VERIFIED_STATES[verdict.state] == true
end

--- Operator-facing lines for a verdict. One place, so `pkg install`,
--- `pkg info` and the picker cannot describe the same state differently.
function pkgsign.describe(verdict)
  if not verdict then return { "Signature: not checked" } end
  local out = {}
  if verdict.state == "trusted" then
    out[#out + 1] = "Signature: VALID, from trusted publisher '" .. tostring(verdict.label) .. "'"
    out[#out + 1] = "  key " .. tostring(verdict.fingerprint)
  elseif verdict.state == "unknown" then
    out[#out + 1] = "Signature: VALID, but this key is NOT in your trust store."
    out[#out + 1] = "  key " .. tostring(verdict.fingerprint)
    if verdict.signer then
      -- Quoted and labelled as a claim, because that is what it is.
      out[#out + 1] = "  the disk calls this publisher \"" .. verdict.signer .. "\" (its own word, not proof)"
    end
    out[#out + 1] = "  Trust it with:  pkg trust add <yourname> " .. tostring(verdict.key)
  elseif verdict.state == "invalid" then
    out[#out + 1] = "Signature: DOES NOT VERIFY — " .. tostring(verdict.reason)
    out[#out + 1] = "  This is tampering or corruption, not a missing signature."
  else
    out[#out + 1] = "Signature: none. This package is unsigned."
    out[#out + 1] = "  Hashes prove the disk is intact, never who wrote it."
    out[#out + 1] = "  Your admin privilege is what is authorising this install."
  end
  return out
end

-- ============================================================
-- Signing
-- ============================================================
--- Sign `manifestPath` with a 32-byte raw seed, writing the .sig beside
--- it. Returns the public key hex on success.
-- The seed never reaches disk and never reaches the log — the caller
-- fetches it from the keychain and hands it over for the length of this
-- call.
function pkgsign.signManifest(manifestPath, seedRaw, opts)
  opts = opts or {}
  if type(seedRaw) ~= "string" or #seedRaw ~= 32 then
    return nil, "signing key must be 32 raw bytes"
  end
  if not fs or not fs.exists(manifestPath) then
    return nil, "no manifest at " .. tostring(manifestPath)
  end
  local body = fs.readFile(manifestPath)
  if not body then return nil, "cannot read " .. manifestPath end
  if #body > MAX_SIGNED_BYTES then return nil, "manifest is too large to sign" end

  local okE, ed = pcall(require, "kernel.ed25519")
  if not okE or not ed or not ed.sign then return nil, "ed25519 support unavailable" end

  local pub = ed.publickey(seedRaw)
  if not pub then return nil, "cannot derive the public key" end
  local sig = ed.sign(body, seedRaw, pub)
  if not sig then return nil, "signing failed" end

  local rec = {
    v      = 1,
    alg    = "ed25519",
    key    = binToHex(pub),
    sig    = binToHex(sig),
    covers = manifestPath:match("[^/]+$"),
  }
  if type(opts.signer) == "string" and opts.signer ~= "" then
    rec.signer = opts.signer:sub(1, 48)
  end
  local sigPath = pkgsign.sigPathFor(manifestPath)
  local wOk, wErr = fs.writeFile(sigPath, serialize.encode(rec))
  if not wOk then return nil, "cannot write " .. sigPath .. ": " .. tostring(wErr) end
  return rec.key, sigPath
end

-- ============================================================
-- Key derivation
-- ============================================================
--! The key is DERIVED from the passphrase, never stored, so the
--! passphrase IS the private key. Everything below follows from that.
--
--! v2 (was v1: no salt, 512 rounds, 12-char floor). Three changes, and it
--! is worth being honest about which one is load-bearing:
--!
--!  * SALT = the publisher label. Stops ONE precomputed passphrase->key
--!    table from yielding every publisher's key at once; each identity
--!    now has to be attacked on its own. It adds no secrecy — the label
--!    is public, it is printed in the repo README — so it does nothing
--!    against someone targeting one specific publisher.
--!
--!  * 4096 rounds, was 512. Three bits. That is the honest size of it:
--!    a KDF that could actually defend a guessable passphrase needs
--!    ~1e5-1e6 rounds, and this runs on a 192 KB machine sharing one CPU
--!    with every other seat. Defence in depth, not a defence.
--!
--!  * THE ONE THAT MATTERS: the passphrase floor below. Against a
--!    generated 32-byte passphrase the round count is irrelevant; against
--!    "correcthorsebattery" no round count reachable here saves it. So
--!    the entropy is the whole defence, and it is enforced rather than
--!    advised.
--
--! Changing any of these three changes every derived key, which is why
--! the domain string carries a version. A publisher whose key came from
--! v1 gets a DIFFERENT key here: that is a re-key, not a bug. Already
--! published signatures still verify — verification reads the public key
--! out of the signature record and never runs this function.
local KDF_DOMAIN     = "TOS-pkg-signing-key-v2"
local KDF_ROUNDS     = 4096
local KDF_MIN_PASS   = 20
local KDF_MIN_UNIQUE = 10
pkgsign.KDF_DOMAIN, pkgsign.KDF_ROUNDS = KDF_DOMAIN, KDF_ROUNDS
pkgsign.KDF_MIN_PASS, pkgsign.KDF_MIN_UNIQUE = KDF_MIN_PASS, KDF_MIN_UNIQUE

--! Resolved lazily and tolerated absent, exactly as ed25519.lua does:
--! this module has to load under plain Lua for the off-box signer and
--! during early boot, where kernel.process does not exist yet.
local yieldCoop
do
  local okP, procMod = pcall(require, "kernel.process")
  if okP and type(procMod) == "table" and type(procMod.yieldCooperative) == "function" then
    yieldCoop = procMod.yieldCooperative
  else
    yieldCoop = function() end
  end
end

--- Normalize a publisher label into the form the KDF salts with.
-- Trimmed and lowercased on purpose. The label is typed by a human, on
-- more than one machine, months apart; "Discover", "discover " and
-- "discover" MUST derive the same key or a publisher silently acquires a
-- second identity and cannot work out why their key changed.
function pkgsign.normalizeLabel(label)
  if type(label) ~= "string" then return nil end
  local s = label:gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if s == "" then return nil end
  return s
end

--- Derive a 32-byte signing seed from a passphrase and a publisher label.
-- Both are required. The label is the salt, so deriving without one would
-- silently produce a different key than deriving with one — the exact
-- footgun of an optional salt, and the reason this refuses rather than
-- defaulting to "".
function pkgsign.seedFromPassphrase(pass, label)
  local salt = pkgsign.normalizeLabel(label)
  if not salt then
    return nil, "a publisher label is required: it salts the key, so the same " ..
                "passphrase under a different label is a different identity"
  end
  if type(pass) ~= "string" or #pass < KDF_MIN_PASS then
    return nil, "signing passphrase must be at least " .. KDF_MIN_PASS ..
                " characters (it IS the private key; generate it, do not invent it)"
  end
  --! A length floor alone passes "aaaaaaaaaaaaaaaaaaaaaa". This is a
  --! crude floor, NOT an entropy measure, and is not sold as one: it
  --! rejects the obviously degenerate and nothing more.
  local seen, distinct = {}, 0
  for i = 1, #pass do
    local c = pass:sub(i, i)
    if not seen[c] then seen[c] = true; distinct = distinct + 1 end
  end
  if distinct < KDF_MIN_UNIQUE then
    return nil, "signing passphrase uses only " .. distinct .. " distinct characters; " ..
                "need " .. KDF_MIN_UNIQUE .. ". Generate one rather than composing it."
  end

  local okS, sha512 = pcall(require, "kernel.sha512")
  if not okS or not sha512 then return nil, "sha512 unavailable" end

  local seed = sha512.raw(KDF_DOMAIN .. "\0" .. salt .. "\0" .. pass)
  --! Yield periodically or OpenComputers' watchdog kills the process
  --! partway through ("too long without yielding"), which at 4096 rounds
  --! on a shared CPU is a real risk rather than a theoretical one. The
  --! hash chain is unaffected by being suspended between rounds.
  for i = 1, KDF_ROUNDS do
    seed = sha512.raw(seed)
    if i % 256 == 0 then yieldCoop() end
  end
  return seed:sub(1, 32)
end

return pkgsign
