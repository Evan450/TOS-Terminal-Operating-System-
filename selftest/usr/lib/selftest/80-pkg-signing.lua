























return function(t)
  local okS, pkgsign = pcall(require, "kernel.pkgsign")
  if not okS or type(pkgsign) ~= "table" then
    return t.skip("pkg signing", "kernel.pkgsign unavailable")
  end
  local okP, pkg = pcall(require, "kernel.pkg")
  local fs = _G._TOS and _G._TOS.fs
  if not fs then return t.skip("pkg signing", "no filesystem") end

  local okE, ed = pcall(require, "kernel.ed25519")
  if not okE or not ed or not ed.sign or not ed.publickey then
    return t.skip("pkg signing", "kernel.ed25519 unavailable")
  end

  local okSer, serialize = pcall(require, "kernel.serialize")
  if not okSer then return t.skip("pkg signing", "kernel.serialize unavailable") end
  
  
  
  
  
  
  
  
  local okLog, kernelLog = pcall(require, "kernel.log")
  pkgsign.init({ fs = fs, serialize = serialize, log = okLog and kernelLog or nil })

  
  
  
  
  local wasRequire = pkgsign.requiresSignature()
  local LABEL = "tos-selftest-probe"

  local scratch  = "/tmp/pkgsign-selftest-" .. tostring(math.floor(computer.uptime() * 100))
  local manifest = scratch .. "/package.lua"

  local ok, err = pcall(function()
    fs.makeDirectory(scratch)
    fs.writeFile(manifest, "return { name = 'selftest-probe', version = '1.0.0' }\n")

    
    
    local seed = string.rep("\7", 32)
    local pub = ed.publickey(seed)
    t.ok("ed25519 derives a public key on this machine", type(pub) == "string" and #pub == 32)

    local key, sigPath = pkgsign.signManifest(manifest, seed, { signer = "selftest" })
    t.ok("signManifest succeeds (" .. tostring(sigPath) .. ")", type(key) == "string")
    t.ok("a .sig file lands beside the manifest",
      fs.exists(pkgsign.sigPathFor(manifest)))

    local verdict = pkgsign.verifyManifest(manifest)
    t.eq("a real signature from an untrusted key verifies as unknown",
      "unknown", verdict.state)

    
    
    
    local aok, aerr = pkgsign.addKey(LABEL, key)
    t.ok("trust add succeeds (" .. tostring(aerr) .. ")", aok and true or false)
    pkgsign.reloadTrust()
    local verdict2 = pkgsign.verifyManifest(manifest)
    t.eq("once trusted, the same bytes verify as trusted", "trusted", verdict2.state)
    t.eq("...under the label we just added", LABEL, verdict2.label)

    local rok = pkgsign.removeKey(LABEL)
    t.ok("trust remove succeeds", rok and true or false)
    pkgsign.reloadTrust()
    local verdict2b = pkgsign.verifyManifest(manifest)
    t.eq("removing the key drops it back to unknown", "unknown", verdict2b.state)

    
    
    
    local body = fs.readFile(manifest)
    fs.writeFile(manifest, (body:gsub("selftest%-probe", "tampered!!!!!")))
    local verdict3 = pkgsign.verifyManifest(manifest)
    t.eq("a hand-edited manifest is INVALID, not unsigned and not silently accepted",
      "invalid", verdict3.state)
    t.ok("...and the reason says so",
      type(verdict3.reason) == "string" and #verdict3.reason > 0)

    
    
    
    if okP and pkg and pkg._signGate then
      local unsigned = scratch .. "/unsigned.lua"
      fs.writeFile(unsigned, "return { name = 'unsigned-probe', version = '1.0.0' }\n")

      pkgsign.setRequireSignature(true)
      local v4, refusal4 = pkg._signGate(unsigned, {})
      t.eq("require=on: an unsigned manifest is refused", "unsigned", v4.state)
      t.ok("...and the refusal names the require-signature setting",
        type(refusal4) == "string" and refusal4:find("require signatures", 1, true) ~= nil)

      local v5, refusal5 = pkg._signGate(unsigned, { allowUnsigned = true })
      t.eq("--allow-unsigned still reads as unsigned...", "unsigned", v5.state)
      t.eq("...but is NOT refused", nil, refusal5)

      pkgsign.setRequireSignature(false)
      local _, refusal6 = pkg._signGate(unsigned, {})
      t.eq("require=off: the same unsigned manifest passes through", nil, refusal6)
    else
      t.skip("require-signature gate", "kernel.pkg._signGate unavailable")
    end
  end)

  
  
  pcall(function()
    pkgsign.removeKey(LABEL)
    pkgsign.setRequireSignature(wasRequire)
    pkgsign.reloadTrust()
  end)
  pcall(function()
    for _, p in ipairs({ manifest, pkgsign.sigPathFor(manifest), scratch .. "/unsigned.lua" }) do
      if p and fs.exists(p) then fs.remove(p) end
    end
    if fs.exists(scratch) then fs.remove(scratch) end
  end)
  t.eq("require-signature setting restored to what we found",
    wasRequire, pkgsign.requiresSignature())
  if not ok then t.ok("pkg signing check body: " .. tostring(err), false) end
end
