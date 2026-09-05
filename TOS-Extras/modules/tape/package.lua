-- FEAT-7 native package manifest for tape.
return {
  -- 2.2.1 — `tape decrypt` can read what `tape encrypt` writes again.
  -- kernel.vault has written TVAULT2 since the CR-7 split while still
  -- reading TVAULT1; the tape format sniffer only matched TVAULT1, so
  -- decrypt refused every tape encrypt had just produced. (Nothing was
  -- lost — the blob on the tape was always valid — but the command that
  -- recovers it declined to run.) Same release drops the whole-cartridge
  -- read: encrypt now reads exactly the archive scanArchive() measures,
  -- decrypt exactly the header's ctLen, so a 4 MB tape no longer has to
  -- fit in RAM. No manifest or command surface change.
  --
  -- 2.2.0 — the module finally LIVES at its real name: the source dir
  -- moved from modules/tape-storage/ to modules/tape/ and the install
  -- path from /usr/modules/tape-storage/ to /usr/modules/tape/. The
  -- "tape-storage" name dates from when the module only did data
  -- archival; it has been the general tape tool (data + audio + raw
  -- I/O + encryption) since 2.0. The legacy name is still published
  -- via `provides` so older `requires` entries keep resolving.
  -- (Upgrading from <=2.1: `pkg uninstall tape` first — pkg refuses
  -- in-place reinstalls, and the old build's files live at the old
  -- install path.)
  name        = "tape",
  version     = "2.2.1",
  kind        = "command",
  category    = "storage",
  description = "General Computronics tape control: data archive/restore + audio playback + raw I/O + device state.",
  author      = "Strata Systems",
  files       = {
    "/usr/modules/tape/init.lua",
  },
  commands     = { tape = "/usr/modules/tape/init.lua" },
  -- `vault` grants ONLY encrypt/decrypt/isEncrypted on caller-supplied
  -- strings — see kernel.sandbox. Needed by `tape encrypt|decrypt|vault`.
  capabilities = { "fs.read", "fs.write", "component", "peripheral.tape", "vault" },
  -- EXP-1 — `provides` lets us be drop-in compatible with consumers
  -- that depended on the older "tape-storage" name. pkg.checkRequires
  -- treats `provides` entries as alternate names this package satisfies.
  provides    = { "tape-storage" },
  requires    = {},
}
