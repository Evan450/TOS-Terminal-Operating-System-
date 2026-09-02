local pkgsign = {}

local TRUST_FILE = "/etc/pkg_trust.cfg"
local MAX_SIG_BYTES   = 4096
local MAX_TRUST_BYTES = 8192

local MAX_SIGNED_BYTES = 64 * 1024

local fs, serialize, log

function pkgsign.init(deps)
  deps = deps or {}
  fs        = deps.fs
  serialize = deps.serialize
  log       = deps.log
  return fs ~= nil and serialize ~= nil
end

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

function pkgsign.addKey(label, pubHex)
  if type(label) ~= "string" or not label:match("^[%w%-_%.]+$") or #label > 48 then
    return false, "label must be 1-48 chars of letters, digits, - _ ."
  end
  if not isHex(pubHex, 64) then
    return false, "public key must be 64 hexadecimal characters (32 bytes)"
  end
  pubHex = pubHex:lower()
  local t = loadTrust()

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

function pkgsign.sigPathFor(manifestPath)
  if type(manifestPath) ~= "string" then return nil end
  local stem = manifestPath:match("^(.*)%.[%w]+$")
  if not stem then return manifestPath .. ".sig" end
  return stem .. ".sig"
end

function pkgsign.readSig(sigPath)
  if not fs or not fs.exists or not fs.exists(sigPath) then return nil, "no signature file" end
  local raw = fs.readFile(sigPath)
  if not raw or #raw == 0 then return nil, "signature file is empty" end
  if #raw > MAX_SIG_BYTES then return nil, "signature file is implausibly large" end
  local ok, rec = pcall(serialize.decode, raw, { maxBytes = MAX_SIG_BYTES })
  if not ok or type(rec) ~= "table" then return nil, "signature file did not decode" end
  if rec.alg ~= nil and rec.alg ~= "ed25519" then

    return nil, "unsupported signature algorithm '" .. tostring(rec.alg) .. "'"
  end
  if not isHex(rec.key, 64) then return nil, "signature names no valid public key" end
  if not isHex(rec.sig, 128) then return nil, "signature value is malformed" end
  return {
    alg    = "ed25519",
    key    = rec.key:lower(),
    sig    = rec.sig:lower(),

    signer = type(rec.signer) == "string" and rec.signer:sub(1, 48) or nil,
    covers = type(rec.covers) == "string" and rec.covers:sub(1, 64) or nil,
  }
end

local VERIFIED_STATES = { trusted = true, unknown = true }

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

function pkgsign.isVerified(verdict)
  return verdict ~= nil and VERIFIED_STATES[verdict.state] == true
end

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

function pkgsign.seedFromPassphrase(pass)
  if type(pass) ~= "string" or #pass < 12 then
    return nil, "signing passphrase must be at least 12 characters"
  end
  local okS, sha512 = pcall(require, "kernel.sha512")
  if not okS or not sha512 then return nil, "sha512 unavailable" end
  local seed = sha512.raw("TOS-pkg-signing-key-v1\0" .. pass)

  for _ = 1, 512 do seed = sha512.raw(seed) end
  return seed:sub(1, 32)
end

return pkgsign
