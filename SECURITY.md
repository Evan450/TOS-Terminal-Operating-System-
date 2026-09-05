# Security Policy

TOS is an operating system for the OpenComputers Minecraft mod. Nothing it
protects is real: the "machines" are blocks in a game world and the worst
outcome of a break is a griefed base. It is written as though the stakes were
real anyway, because that is the interesting part of the exercise, and because
an OS that teaches sloppy habits is worse than no OS.

Read that as calibration, not as a shrug. Reports are welcome and get taken
seriously.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting: the **Security** tab on this
repository → **Report a vulnerability**. That opens a private thread visible
only to the maintainer.

If that is not available, open a public issue saying only that you have a
security report and asking for a private channel — no details in the issue
itself.

What helps, in rough order of usefulness:

- The branch and commit you looked at (`dev` is the source; `main` is a
  generated build, so line numbers differ between them).
- A reproduction. Off-box is fine and often better — most of TOS can be driven
  from plain Lua against fakes, which is how the test suite works.
- What an attacker gets. "An admin can overwrite the kernel" is a finding;
  "this function does not validate its argument" may not be, if nothing
  reachable passes it anything interesting.

## Scope

In scope: the kernel, the sandbox and its capability gates, `securefs`, the
network stack and its trust tiers, the package manager and its signature
handling, the boot chain, and the installers.

Known and documented, so not news — but a concrete escalation *through* one of
these still is:

- **The boot chain is not cryptographically anchored.** Write access to
  `/init.lua`, the manifest, or `/etc/critical.bak` is code execution before
  login. Documented in the manual's security model.
- **`securefs` ACLs are not a physical boundary.** Move the disk to another
  machine and they are gone. They are a policy inside a running TOS, not
  encryption.
- **The software RNG is not a CSPRNG.** Without a data card the pool is mixed
  from weak sources and says so; secret-bearing stores refuse rather than
  fall back to it.
- **`bootstrap.lua` does not verify what it downloads.** It trusts TLS and the
  integrity of the GitHub account. This is tracked work, not a decision.

Out of scope: anything requiring the attacker to already be the operator at
the physical machine, and anything in the OpenComputers mod itself (report
those upstream).

## Supported versions

The current release on `main`. This is a hobby project with one maintainer;
there is no backport branch and no patch-window promise.
