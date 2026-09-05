-- Signed manifests, against real ed25519 and the real trust store.
--
-- Ports the automatable half of the SIGNED MANIFESTS round's emulator
-- checklist (TODO.txt, "Emulator checklist:" under that round): hand-edit
-- one byte of a signed manifest and confirm the refusal names tampering,
-- `pkg trust add` a key and confirm the package now reads trusted, and
-- `pkg trust require on` + an unsigned disk's refusal naming the setting
-- (with --allow-unsigned still working). The other bullets there --
-- timing verify-sig on a T1 vs a T3, confirming no 5-second watchdog
-- stall, and interop with a second machine -- are not a single boot's
-- worth of proof and stay manual.
--
-- kernel.pkgsign is fully covered off-box against a FAKE filesystem
-- (usr/lib/tests/test_pkg_signing.lua). What that cannot exercise is the
-- REAL kernel.ed25519 field arithmetic on this machine's actual Lua VM,
-- and the REAL /etc/pkg_trust.cfg write path through securefs's
-- protected-path table -- the fake fs in the off-box test has no ACL to
-- get wrong.
--
-- SAFETY. addKey/setRequireSignature write the OPERATOR'S real trust
-- store. This snapshots it, uses a throwaway label and a throwaway
-- keypair, and puts every setting back -- including on the throw path --
-- so a round of this battery never leaves an admin trusting a key they
-- never asked to trust.
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
  -- Re-init with the REAL structured log module, never _G._TOS.log: that
  -- global is a one-arg convenience wrapper (kernel/init.lua: `function(src,
  -- msg) log.info(src, msg) end`), not the {info=,warn=,error=} table every
  -- kernel module (including pkgsign itself) expects to call .warn()/.error()
  -- on. Passing the wrapper here doesn't fail until loadTrust() actually
  -- hits its log.warn() branch, which is exactly what happened the first
  -- time this check ran on real hardware: "attempt to index a function
  -- value (upvalue 'log')".
  local okLog, kernelLog = pcall(require, "kernel.log")
  pkgsign.init({ fs = fs, serialize = serialize, log = okLog and kernelLog or nil })

  -- Snapshot the REAL policy so it can be restored byte-for-byte. There
  -- is no injectable path table here the way srm.DIR/INDEX/STORE gives
  -- 50-srm.lua one -- the trust file path is a local constant in
  -- kernel.pkgsign -- so save-then-restore is the only safe shape.
  local wasRequire = pkgsign.requiresSignature()
  local LABEL = "tos-selftest-probe"

  local scratch  = "/tmp/pkgsign-selftest-" .. tostring(math.floor(computer.uptime() * 100))
  local manifest = scratch .. "/package.lua"

  local ok, err = pcall(function()
    fs.makeDirectory(scratch)
    fs.writeFile(manifest, "return { name = 'selftest-probe', version = '1.0.0' }\n")

    -- A throwaway keypair, fixed so a re-run of this check is deterministic.
    -- It is never added to the trust store before the "unknown" assertion.
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

    -- `pkg trust add`, on the real trust store, then confirm the SAME
    -- manifest now reads as trusted. This is the exact call the shell
    -- command makes -- pkgsign.addKey is what it's a thin wrapper over.
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

    -- THE TAMPER CHECK. One byte, hand-edited, on a disk whose signature
    -- covers exactly this file. There is no override for this state --
    -- unlike "unsigned", it must never be reachable via a flag.
    local body = fs.readFile(manifest)
    fs.writeFile(manifest, (body:gsub("selftest%-probe", "tampered!!!!!")))
    local verdict3 = pkgsign.verifyManifest(manifest)
    t.eq("a hand-edited manifest is INVALID, not unsigned and not silently accepted",
      "invalid", verdict3.state)
    t.ok("...and the reason says so",
      type(verdict3.reason) == "string" and #verdict3.reason > 0)

    -- THE REQUIRE-SIGNATURE GATE, via pkg._signGate -- the exact function
    -- pkg.install calls, exercised without installing anything. Restore
    -- the manifest to something that reads as clean unsigned first.
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
      local v6, refusal6 = pkg._signGate(unsigned, {})
      t.eq("require=off: the same unsigned manifest passes through", nil, refusal6)
      _ = v6
    else
      t.skip("require-signature gate", "kernel.pkg._signGate unavailable")
    end
  end)

  -- Restore the real policy exactly, and remove the probe key, even if
  -- an assertion above threw partway through.
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
