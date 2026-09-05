-- FEAT-7 native package manifest for tape-authenticator.
-- 1.0.1 — streaming reads: parse only the keycard region instead of slurping
-- the whole multi-MB tape (the old readWholeTape OOM'd even tier-3.5 RAM when
-- configuring a tape). `info` now authenticates inline for admins instead of
-- always nagging to run `verify`.
-- 1.0.0 — full rebuild for the pkg sandbox. A tape is now a keycard
-- AND a notebook: the front carries an HMAC-signed identity block
-- (machine-secret-bound via the narrow `crypto` capability's
-- per-package secret) and the rest holds a vault-encrypted personal
-- log the operator can edit at any time with their own passphrase.
-- The 0.1.x build required kernel.crypto/securefs (sandbox-blocked)
-- and its commands map used the dead pre-pivot array shape, so it
-- could never run under pkg and was kept off the Optional Utilities
-- disk; it now ships.
return {
  name        = "tape-authenticator",
  version     = "1.0.1",
  kind        = "command",
  category    = "security",
  description = "Tape keycard + encrypted personal log: HMAC identity for access control, private notes you can edit any time.",
  author      = "Strata Systems",
  files       = {
    "/usr/modules/tape-authenticator/init.lua",
  },
  commands     = { ["tape-auth"] = "/usr/modules/tape-authenticator/init.lua" },
  -- `crypto` = hash/hmac/ctEquals/random + the admin-gated per-package
  -- machine secret that signs identity blocks; `vault` = the
  -- passphrase encryption for the personal log. Both are narrow
  -- data-in/data-out facets (see kernel.sandbox). No fs caps needed —
  -- the secret store is kernel-managed.
  capabilities = { "component", "peripheral.tape", "crypto", "vault" },
  requires    = {},
  -- `tape` is how you inspect and manage the keycard tapes this package
  -- writes — not needed to authenticate, very useful to have alongside.
  recommends  = { "tape" },
}
