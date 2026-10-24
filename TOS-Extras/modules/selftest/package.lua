-- The boot self-test battery, as a package.
--
-- The runner has always been in the base image (tos/kernel/selftest.lua);
-- the checks lived on a test disk. This installs them into
-- /usr/lib/selftest/, which the runner already searches, plus the
-- `selftest` command that arms, disarms, lists and reads a run.
--
-- Installing it needs ROOT: an armed machine runs every check in
-- /usr/lib/selftest/ inside the kernel, so pkg holds any package that
-- puts a file there to the service package's root gate.
return {
  name        = "selftest",
  -- 1.0.0 -- the battery as it stood on 2026-10-02: sixteen checks, 10-boot
  -- through 97-inprocess, and the `selftest` command.
  version     = "1.0.0",
  kind        = "command",
  category    = "dev",
  -- One string literal, not "a" .. "b": pkg reads this file with the
  -- kernel's data-only decoder, which refuses any expression.
  description = "Boot self-test battery: checks that run inside the booted kernel on real hardware, and `selftest` to arm, list and read them. For testing your own additions to TOS. Root install.",
  author      = "Strata Systems",
  files       = {
    "/usr/modules/selftest/init.lua",
    "/usr/lib/selftest/10-boot.lua",
    "/usr/lib/selftest/20-display.lua",
    "/usr/lib/selftest/30-hash-at-size.lua",
    "/usr/lib/selftest/40-fs-roundtrip.lua",
    "/usr/lib/selftest/50-srm.lua",
    "/usr/lib/selftest/60-sandbox.lua",
    "/usr/lib/selftest/70-screen-truth.lua",
    "/usr/lib/selftest/80-pkg-signing.lua",
    "/usr/lib/selftest/90-internet-absence.lua",
    "/usr/lib/selftest/91-keyboard.lua",
    "/usr/lib/selftest/92-term.lua",
    "/usr/lib/selftest/93-audio.lua",
    "/usr/lib/selftest/94-rename-truth.lua",
    "/usr/lib/selftest/95-utf8-tokens.lua",
    "/usr/lib/selftest/96-waitfor.lua",
    "/usr/lib/selftest/97-inprocess.lua",
  },
  commands     = { selftest = "/usr/modules/selftest/init.lua" },
  -- fs.read for the log, the checks and the marker; fs.write for the
  -- marker, which securefs lets only root write.
  capabilities = { "fs.read", "fs.write" },
}
