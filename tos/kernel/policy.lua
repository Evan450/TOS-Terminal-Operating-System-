-- ╔═══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Security policy                              ║
-- ║                                                            ║
-- ║  What this system allows, in one sitting. These are the    ║
-- ║  DECISIONS only. The enforcement stays where it was, in    ║
-- ║  sandbox.lua, pkg.lua, rc.lua and securefs.lua, because    ║
-- ║  that is where the #SEC history lives. The sandbox holds   ║
-- ║  no authority of its own to add to this: the operator's    ║
-- ║  own additions are /etc/component_caps.cfg and             ║
-- ║  /etc/pkg_caps.cfg, read on top of the defaults here.      ║
-- ║                                                            ║
-- ║  CRITICAL, IN ONE DIRECTION. If this file will not load,   ║
-- ║  kernel/policyload.lua denies everything non-kernel and    ║
-- ║  says so. Programs stop working; nothing opens up. The     ║
-- ║  shell is not sandboxed, so an admin can still repair it.  ║
-- ╚═══════════════════════════════════════════════════════════╝

local policy = {}

--- Is this session an admin, as far as a privileged kernel call goes? The
--- installer's kernel session and the login principal count; so does ADMIN+.
function policy.isAdmin(session)
  if type(session) ~= "table" then return false end
  if session.isKernel or session.isLogin then return true end
  return type(session.tier) == "number" and session.tier >= 2
end

-- ============================================================
-- What a sandboxed program may require
-- ============================================================

-- Modules whose names have any of these prefixes are allowed through
-- makeSafeRequire without per-name vetting. Everything else must match
-- one of the exact names in ALLOWED_MODULE_NAMES, or be installed under
-- /usr/lib or /usr/modules (user-installed libraries, already gated by
-- securefs when the install happens).
policy.MODULE_PREFIXES = {
  "compat.",
  "peripheral.",
}

-- Narrow whitelist of bare module names sandboxed programs may require.
-- Extend with care — anything added here runs OUTSIDE the sandbox with
-- full unsandboxed require, so it must be safe to expose unconditionally.
policy.MODULE_NAMES = {
  compat        = true,
  -- The shared keybind table. Exposed to package code deliberately: a
  -- standard that only the base image can read standardises nothing, and
  -- the whole point is that a bundled package and the shell agree on
  -- what ^Q means and follow the operator when they change it.
  -- Safe to hand out — it reads two keybind config files and returns key
  -- MATCHERS. No filesystem handle, no component, no authority of any
  -- kind passes through it.
  ["shell.keys"] = true,
}

-- require names that must be rejected outright even if they'd otherwise
-- fall under a user-lib path. Loading any of these gives the caller the
-- real kernel.* surface via their own require.
policy.BLOCKED_MODULES = {
  -- #SEC H5 — `debug` exposes sethook, getlocal, getupvalue, and the
  -- whole introspection surface. A sandboxed program with require()
  -- access to it can rip out any upvalue in the calling closure
  -- (including the secret-bound `fs` proxy or the `caps` table),
  -- bypassing every other guard. The OC Lua stdlib ships `debug`
  -- so it's reachable via the host's package.loaded["debug"]; block
  -- it explicitly here so the user-lib resolver also refuses.
  ["debug"]                   = true,
  ["package"]                 = true,  -- and the package resolver itself
  ["os"]                      = true,  -- raw os.execute/remove/exit
  ["io"]                      = true,  -- raw io.popen/io.open
  ["component"]               = true,  -- raw component (sandbox shadows it)
  ["computer"]                = true,  -- raw computer.shutdown/eeprom
  ["filesystem"]              = true,  -- raw FS bypasses securefs
  ["shell.init"]              = true,
  --! #SEC (pentest, Sep 2026) — shell.ext is not an extension API; it is
  --! the lazy-loaded body of the net/ping/hostname/config/audio commands,
  --! and the unsandboxed shell (commands/extras.lua) is its only caller.
  --! It sat on the ALLOWED list under a stale description, and parts of it
  --! reach _G._TOS directly (the peer-alias table, audio) instead of going
  --! through a capability the program was granted. The alias writers do
  --! re-check the live principal's tier; nothing else about it belongs in
  --! a sandbox either.
  ["shell.ext"]               = true,
  ["shell.panels.init"]       = true,
  ["shell.panels.commands"]   = true,
  ["shell.panels.events"]     = true,
  ["shell.panels.executor"]   = true,
  ["shell.panels.state"]      = true,
  ["shell.panels.draw"]       = true,
  ["shell.panels.helpers"]    = true,
  ["shell.panels.filebrowser"] = true,
  ["shell.panels.editor"]     = true,
  ["shell.panels.menus"]      = true,
  ["shell.panels.dialogs"]    = true,
  ["shell.panels.context"]    = true,
  ["shell.panels.keymap"]     = true,
  ["shell.panels.tabs"]       = true,
  ["shell.panels.widgets"]    = true,
  ["shell.panels.mouse"]      = true,
  ["shell.panels.ui"]         = true,
  ["shell.panels.desktop"]    = true,
  ["shell.panels.settingsapp"] = true,
  ["shell.panels.apps"]       = true,
  ["shell.panels.monitorapp"] = true,
  ["shell.panels.chatapp"]    = true,
  -- Stage 5 — the mail ADD-ON's libraries live in /usr/lib, which the
  -- user-lib resolver below would otherwise load through the REAL
  -- require (that's how a full-priv add-on works). Blocking them by name
  -- preserves the exact posture mail had as a kernel module: sandboxed
  -- package code can't reach the mesh transport (bypassing its `net`
  -- capability) or another user's mailbox through it.
  ["mail"]                    = true,
  ["mailui"]                  = true,
  ["mailapp"]                 = true,
  -- The RBMK controller's libraries, for the same reason and then some:
  -- they hold raw console access and the SCRAM path. A sandboxed package
  -- must not be able to require its way to a reactor.
  ["rbmk-cmd"]                = true,
  ["rbmk-controld"]           = true,
  ["rbmk.core"]               = true,
  -- The SKALA panel is only a renderer, but it is blocked with the
  -- rest anyway: it reaches kernel.screen and can paint every seat on
  -- the machine, which is not something sandboxed package code should
  -- be able to require its way into.
  ["rbmk-skala"]              = true,
  ["rbmk.skala"]              = true,
  ["rbmk.wall"]               = true,
  ["shell.panels.takeover"]   = true,
  ["shell.login"]             = true,
  ["shell.chat"]              = true,
  ["shell.tutorial"]          = true,
  ["shell.syntax"]            = true,
  ["shell.panels"]            = true,
  ["shell"]                   = true,
  ["bios"]                    = true,
  ["init"]                    = true,
  ["install"]                 = true,
  ["system_manifest"]         = true,
}

-- ============================================================
-- What hardware a sandboxed program may touch
-- ============================================================

policy.BASE_COMPONENTS = {
  gpu = true, screen = true, keyboard = true,
  crafting = true, navigation = true, geolyzer = true,
  note_block = true, sign = true,
}

policy.GATED_COMPONENTS = {
  modem                = "peripheral.modem",
  tunnel               = "peripheral.modem",
  redstone             = "peripheral.redstone",
  robot                = "peripheral.robot",
  inventory_controller = "peripheral.inventory",
  transposer           = "peripheral.inventory",
  tank_controller      = "peripheral.inventory",
  tape_drive           = "peripheral.tape",
  --! An internet card reaches OUTSIDE the Minecraft world: it is both an
  --! exfiltration channel for anything the program can read and an inbound
  --! channel of bytes a stranger wrote. Gated behind its own cap rather
  --! than folded into the generic `component` grant, so a package that
  --! wants a screen and a keyboard does not silently get the network.
  internet             = "internet",
  tractor_beam         = "peripheral.tractor",
  piston               = "peripheral.piston",
  hologram             = "peripheral.hologram",
  --! OpenPrinter (PC-Logix) — the ONLY non-vanilla component type named in
  --! this file, and it is here on purpose rather than left to
  --! /etc/component_caps.cfg below. FEAT-5's config exists so an operator
  --! can add types WE do not ship code for; TOS ships a first-party
  --! `printer` driver package, and a package capability has to clear
  --! pkg.lua's PKG_RUN_CAPS allowlist as well as this table. A cap an
  --! operator can add to one side but not the other is a cap that silently
  --! does nothing (see the package-cap overrides in pkg.lua, which close
  --! that asymmetry for every OTHER mod). Costs nothing on a world without
  --! the mod: the type simply never appears in component.list.
  --! GATED, not base: a printer WRITES to the world — it consumes the
  --! player's paper and ink and drops physical pages into a chest. That is
  --! real-world actuation with a consumable cost, which is the same reason
  --! piston and robot are gated.
  openprinter          = "peripheral.printer",
}

-- ============================================================
-- Which modem ports a program may not open
-- ============================================================

--! Ports the add-on daemons listen on: cluster's workers and storage tier, and
--! rbmk telemetry. Reserved even while nothing has them open, because a
--! program that got there first would hear that traffic and stop the daemon
--! starting. The daemons themselves do not come through here today: a
--! service's libraries load through the kernel loader, with the raw component
--! (allowUserLibs in sandbox.lua). A service env may open these all the same,
--! should one ever hold peripheral.modem.
policy.SERVICE_PORTS = {
  [2001] = "cluster", [2002] = "cluster", [2003] = "cluster", [2004] = "cluster",
  [2100] = "cluster", [2101] = "cluster", [2200] = "rbmk telemetry",
}

-- ============================================================
-- What a package may ask for
-- ============================================================

-- #SEC — capability allowlist for package-run code. ONLY these facets may be
-- requested by a manifest; anything else (notably "legacy", which unlocks raw
-- os/io and is "do anything") is silently dropped. Mirrors the old
-- kernel.modules ALLOWED_MANIFEST_CAPS exactly so the pivot doesn't reopen the
-- hole that allowlist closed.
policy.PKG_RUN_CAPS = {
  ["fs.read"] = true, ["fs.write"] = true, component = true,
  ["compat.io"] = true, load = true, net = true, swap = true,
  -- Outbound access to the real world (internet card). Allowed to be
  -- REQUESTED by a manifest — a package that fetches anything needs it —
  -- but it is not implied by `component`, so an operator installing a game
  -- is not also granting it the network. See sandbox.lua's threat note.
  internet = true,
  vault = true,  -- narrow passphrase-crypto surface (encrypt/decrypt/isEncrypted)
  crypto = true, -- hash/hmac/ctEquals/random + the per-package machine secret
  notify = true, -- raise a modal dialog box (post/result only; kernel.notify
                 -- rate-limits it and stamps the source from the pkg name)
  ipc = true,    -- "ipc:<name>": call one service's endpoint (kernel/ipc.lua).
                 -- The service still decides what the caller's user may do.
  ["peripheral.modem"] = true, ["peripheral.redstone"] = true,
  ["peripheral.robot"] = true, ["peripheral.inventory"] = true,
  ["peripheral.tape"] = true, ["peripheral.tractor"] = true,
  ["peripheral.piston"] = true, ["peripheral.hologram"] = true,
  -- OpenPrinter, for the first-party `printer` driver package. Paired with
  -- sandbox.lua's `openprinter` gated component type — see the note there
  -- for why this one mod type is coded rather than left to config.
  ["peripheral.printer"] = true,
  -- "legacy" deliberately excluded — a manifest can never opt into raw os/io.
}

-- ============================================================
-- What an rc.d service gets
-- ============================================================

-- Default caps granted to a service whose rc.d script doesn't declare
-- any. Mirrors modules.lua defaults: session-bound fs + filtered component.
-- Services that need more (net, compat.io, load) must opt in explicitly.
policy.SERVICE_DEFAULT_CAPS = {
  ["fs.read"]  = true,
  ["fs.write"] = true,
  ["component"] = true,
  ["net"] = true,  -- most rc.d services are network-facing (sshd, dhcpd)
}

policy.SERVICE_CAPS = {
  ["fs.read"] = true, ["fs.write"] = true, ["component"] = true,
  ["compat.io"] = true, ["load"] = true, ["net"] = true,
  -- "legacy" intentionally excluded.
}

-- #SEC CR-6 — kernel-tier services get a GATED require, not the raw one.
-- The previous code set `require = require` in the kernel env while the
-- comment claimed "the require check below already gates via the safe
-- list" — but no such gate existed. A kernel-tier service could
-- `require("kernel.process")` / `require("kernel.users")` /
-- `require("kernel.sandbox")` and drive the whole kernel. We allow ONLY
-- the modules a legitimate boot service needs (the shipped services use
-- just kernel.event + computer; net/users/etc. come via the read-only
-- `_TOS` table) and fail closed on everything else.
policy.KERNEL_REQUIRE_ALLOW = {
  ["computer"]         = true,
  ["component"]        = true,
  ["kernel.event"]     = true,
  ["kernel.log"]       = true,
  ["kernel.serialize"] = true,
  ["kernel.config"]    = true,
}

-- #SEC C2 — hardcoded allowlist of services that may run as `_kernel_`.
-- A regex match on the source can be made to fire from inside a comment
-- or string literal; without this list, any admin who drops a file into
-- /etc/rc.d gains code execution at root in the next boot.
policy.KERNEL_SERVICES = {
  ["10-discoveryd"] = true,
  ["20-chatrelay"]  = true,
  ["20-fileshare"]  = true,
  ["20-rshd"]       = true,
}

return policy
