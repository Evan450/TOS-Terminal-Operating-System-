-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Data Card detection (shared)                ║
-- ║                                                            ║
-- ║  ONE place that answers "is there a data card, and what    ║
-- ║  can it do?" — so crypto, compress, sysinfo and the POST   ║
-- ║  screen all agree. A data card is found with                ║
-- ║  component.list("data"); OpenComputers doesn't expose the   ║
-- ║  tier directly, so it's INFERRED from the method set:       ║
-- ║                                                            ║
-- ║    Tier 1: hashing (md5/sha256), base64, crc32,            ║
-- ║            deflate/inflate (compression)                   ║
-- ║    Tier 2: + AES (encrypt/decrypt) + random                ║
-- ║    Tier 3: + ECC (generateKeyPair / ecdsa / ecdh)          ║
-- ║                                                            ║
-- ║  detect() returns a capability table so callers ask for    ║
-- ║  exactly the feature they need (e.g. compress wants        ║
-- ║  caps.deflate) instead of each re-implementing the probe.  ║
-- ╚══════════════════════════════════════════════════════════╝

local component = require("component")

local datacard = {}

-- Tier display names, keyed by inferred tier.
datacard.TIER_NAMES = {
  [0] = "present (unknown tier)",
  [1] = "T1 (hashing / base64 / deflate)",
  [2] = "T2 (AES + random + T1)",
  [3] = "T3 (ECC + AES + T1)",
}

-- Probe a data-card's method set into a capability table. Pass the component
-- ADDRESS when you have it: `component.methods(addr)` is the authoritative
-- method enumeration and works on emulators (Ocelot) where probing the proxy's
-- fields with `type(p.sha256) == "function"` comes back empty even though the
-- card has the methods — which made every card classify as "unknown tier".
-- Falls back to proxy-field probing when no address is given.
-- Pure (no side effects); exposed so sysinfo reuses the exact same logic.
function datacard.capsOf(p, addr)
  local methodSet = nil
  if addr then
    local okM, methods = pcall(component.methods, addr)
    if okM and type(methods) == "table" then
      methodSet = {}
      -- component.methods may return { name = true, ... } or an array of names.
      for k, v in pairs(methods) do
        if type(k) == "string" then methodSet[k] = true
        elseif type(v) == "string" then methodSet[v] = true end
      end
    end
  end
  local function has(m)
    if methodSet then return methodSet[m] == true end
    return type(p) == "table" and type(p[m]) == "function"
  end
  if not methodSet and type(p) ~= "table" then return {} end
  return {
    hash    = has("sha256") or has("md5"),
    sha256  = has("sha256"),
    base64  = has("encode64") or has("decode64"),
    crc32   = has("crc32"),
    deflate = has("deflate") and has("inflate"),
    aes     = has("encrypt") and has("decrypt"),
    random  = has("random"),
    ecc     = has("generateKeyPair") or has("ecdsa") or has("ecdh"),
  }
end

-- Infer a tier (0..3) from a capability table.
function datacard.tierOf(caps)
  caps = caps or {}
  if caps.ecc then return 3 end
  if caps.aes or caps.random then return 2 end
  if caps.hash or caps.deflate or caps.base64 or caps.crc32 then return 1 end
  return 0  -- a card is present but advertises none of the known methods
            -- (some emulators ship a bare `data` proxy) — operator can pin
            -- the tier in Boot Settings; see kernel.sysinfo / dataTier.
end

--- Detect the first data card. Returns a table:
---   { present=, addr=, proxy=, caps={...}, tier=N, name=string }
--- present=false (with tier 0) when no `data` component exists.
function datacard.detect()
  local info = { present = false, addr = nil, proxy = nil, caps = {}, tier = 0 }
  local ok = pcall(function()
    for addr in component.list("data") do
      local okP, p = pcall(component.proxy, addr)
      if okP and p then
        info.present = true
        info.addr    = addr
        info.proxy   = p
        info.caps    = datacard.capsOf(p, addr)
        info.tier    = datacard.tierOf(info.caps)
        return
      end
    end
  end)
  if not ok then info = { present = false, addr = nil, proxy = nil, caps = {}, tier = 0 } end
  info.name = datacard.TIER_NAMES[info.tier] or datacard.TIER_NAMES[0]
  return info
end

return datacard
