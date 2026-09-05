-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster-install — SUPERSEDED by the base `cluster-setup`     ║
-- ║                                                              ║
-- ║  This file used to be a standalone install wizard driven by   ║
-- ║  io.read/io.write with ANSI colour codes. Both assumptions    ║
-- ║  were wrong for TOS:                                          ║
-- ║                                                              ║
-- ║   * TOS's display is GPU-driven, not a terminal emulator.     ║
-- ║     Nothing anywhere in TOS interprets ANSI escapes, so       ║
-- ║     `\027[32m` printed as literal garbage.                    ║
-- ║   * `io.read` resolves to term.read, which paints DIRECTLY to ║
-- ║     the display and pulls raw signals. Under the panels shell ║
-- ║     — where almost every operator actually is — that draws    ║
-- ║     over the UI and steals the event loop. The wizard was     ║
-- ║     unusable in the shell it was written for.                 ║
-- ║                                                              ║
-- ║  It also had three logic faults worth recording, all of them  ║
-- ║  now fixed in the replacement:                                ║
-- ║                                                              ║
-- ║   1. It printed the Master's address TRUNCATED to 12 chars    ║
-- ║      inside a command line, so the "copy this" line was not   ║
-- ║      copyable and every operator typed a broken command once. ║
-- ║   2. Its "start at boot?" question did nothing. rc.start()    ║
-- ║      already clears the service's `.disabled` marker (that is ║
-- ║      how an explicit start persists), and the installer then  ║
-- ║      wrote `/var/pkg/installed/<pkg>/state`, which is the     ║
-- ║      PACKAGE-enable byte and is never read by rc. Answering   ║
-- ║      "no" left the service enabled at boot regardless.        ║
-- ║   3. It wrote /etc/*.cfg with a truncating write, so a crash  ║
-- ║      mid-write left a daemon's config unparseable.            ║
-- ║                                                              ║
-- ║  The replacement, `cluster-setup`, ships in the BASE image —  ║
-- ║  so it is present before either cluster package is, which is  ║
-- ║  what lets it answer "which one does this machine need?".     ║
-- ║  This file stays so that an operator holding an older install ║
-- ║  floppy is told where to go instead of running something      ║
-- ║  broken.                                                     ║
-- ╚══════════════════════════════════════════════════════════════╝

local lines = {
  "",
  "cluster-install has been replaced by:  cluster-setup",
  "",
  "Run it from any TOS admin shell. It works BEFORE anything is",
  "installed -- its first job is telling you which of the two cluster",
  "packages this machine needs, and it installs that one for you.",
  "",
  "  cluster-setup            set this machine up (guided)",
  "  cluster-setup explain    just describe the parts, change nothing",
  "",
  "You do not need this floppy. Both cluster packages ship on the",
  "ordinary Optional Utilities disk, and cluster-setup installs from it.",
  "",
}

-- print() is routed to the shell's output area when this is run via `run`;
-- io.write is the fallback for a bare CLI context. No ANSI, deliberately.
local emit = print
if type(emit) ~= "function" then
  emit = function(s) io.write(tostring(s) .. "\n") end
end
for _, l in ipairs(lines) do emit(l) end

return "cluster-install is superseded by cluster-setup"
