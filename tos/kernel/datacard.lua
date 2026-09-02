local component = require("component")

local datacard = {}

datacard.TIER_NAMES = {
  [0] = "present (unknown tier)",
  [1] = "T1 (hashing / base64 / deflate)",
  [2] = "T2 (AES + random + T1)",
  [3] = "T3 (ECC + AES + T1)",
}

function datacard.capsOf(p, addr)
  local methodSet = nil
  if addr then
    local okM, methods = pcall(component.methods, addr)
    if okM and type(methods) == "table" then
      methodSet = {}

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

function datacard.tierOf(caps)
  caps = caps or {}
  if caps.ecc then return 3 end
  if caps.aes or caps.random then return 2 end
  if caps.hash or caps.deflate or caps.base64 or caps.crc32 then return 1 end
  return 0

end

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
