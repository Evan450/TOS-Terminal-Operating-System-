-- TOS System Manifest - Single source of truth for system files.
-- Used by:
--   /init.lua (boot verification, critical files only)
--   kernel.verifySystem() (full integrity check via `verify` command)
--   deploy/install tooling (panels deploy, install.lua)
--
-- Fields:
--   path     = absolute path on the OC filesystem
--   critical = true if the system cannot boot without this file
--
-- Coverage rule: every runtime .lua file under /tos, /etc/rc.d,
-- /usr/bin, /usr/modules and the bootstrap files at the root MUST
-- appear here. /usr/lib/tests is intentionally excluded — those are
-- unit tests for development, not part of a deployed install.
--
-- After the Dev/Release/Extras split (see ../../README.md): the
-- master-skeleton, OpenOS-side cluster worker, and PaneUI now live
-- under ../../TOS-Extras/ rather than inside the source tree, and
-- ship via the Optional Utilities installer instead of /tos/deploy.
-- The bundled-modules entries (tape-storage, tetris) remain listed
-- here for now because the Dev manifest is intentionally inclusive;
-- the Release build's strip pass auto-prunes any entry whose target
-- file isn't present in the dist tree, so the Release manifest stays
-- accurate without a manual edit.
--
-- A coverage test under /usr/lib/tests/test_manifest_completeness.lua
-- enforces this; if you add a runtime file, also add it here, or the
-- test will fail and `deploy` will silently ship an incomplete image.

return {
  -- ── Boot ─────────────────────────────────────────────────
  { path = "/init.lua",                       critical = true  },
  { path = "/install.lua",                    critical = false },

  -- ── Kernel core ──────────────────────────────────────────
  { path = "/tos/kernel/init.lua",            critical = true  },
  { path = "/tos/kernel/log.lua",             critical = true  },
  { path = "/tos/kernel/hal.lua",             critical = true  },
  { path = "/tos/kernel/event.lua",           critical = true  },
  { path = "/tos/kernel/process.lua",         critical = true  },
  { path = "/tos/kernel/fs.lua",              critical = true  },
  { path = "/tos/kernel/serialize.lua",       critical = true  },
  { path = "/tos/kernel/display.lua",         critical = true  },

  -- ── Kernel optional ──────────────────────────────────────
  { path = "/tos/kernel/screen.lua",          critical = false },
  { path = "/tos/kernel/clipboard.lua",       critical = false },
  { path = "/tos/kernel/config.lua",          critical = false },
  { path = "/tos/kernel/users.lua",           critical = false },
  { path = "/tos/kernel/securefs.lua",        critical = false },
  { path = "/tos/kernel/sandbox.lua",         critical = false },
  { path = "/tos/kernel/power.lua",           critical = false },
  { path = "/tos/kernel/rc.lua",              critical = false },
  { path = "/tos/kernel/crypto.lua",          critical = false },
  { path = "/tos/kernel/datacard.lua",        critical = false },
  { path = "/tos/kernel/logo.lua",            critical = false },
  { path = "/tos/kernel/pipe.lua",            critical = false },
  { path = "/tos/kernel/env.lua",             critical = false },
  { path = "/tos/kernel/cron.lua",            critical = false },
  { path = "/tos/kernel/audio.lua",           critical = false },
  { path = "/tos/kernel/theme.lua",           critical = false },
  { path = "/tos/kernel/monitor.lua",         critical = false },
  { path = "/tos/kernel/pkg.lua",             critical = false },
  { path = "/tos/kernel/swap.lua",            critical = false },
  { path = "/tos/kernel/compress.lua",        critical = false },
  { path = "/tos/kernel/sysinfo.lua",         critical = false },
  { path = "/tos/kernel/bootcfg.lua",         critical = false },
  { path = "/tos/kernel/bootsettings.lua",    critical = false },
  { path = "/tos/kernel/bootsteps.lua",       critical = false },
  { path = "/tos/kernel/repair.lua",          critical = false },
  { path = "/tos/kernel/srm.lua",             critical = false },
  { path = "/tos/kernel/notify.lua",          critical = false },
  { path = "/tos/kernel/sha256.lua",          critical = false },
  -- Package signing. All three are LAZILY loaded — nothing requires them
  -- until a signature is actually present to check — but they are listed
  -- here because the manifest is what `verify` walks. A file the image
  -- ships and the manifest omits is a file tampering cannot be detected
  -- in, and ed25519.lua is precisely the file an attacker would want to
  -- edit: make verify() return true and every other gate opens.
  { path = "/tos/kernel/sha512.lua",          critical = false },
  { path = "/tos/kernel/ed25519.lua",         critical = false },
  { path = "/tos/kernel/pkgsign.lua",         critical = false },
  { path = "/tos/kernel/backup.lua",          critical = false },
  { path = "/tos/kernel/diag.lua",            critical = false },
  { path = "/tos/kernel/internet.lua",        critical = false },
  { path = "/tos/kernel/pkgremote.lua",       critical = false },
  { path = "/tos/kernel/jbod.lua",            critical = false },
  { path = "/tos/kernel/netfs.lua",           critical = false },
  { path = "/tos/kernel/selftest.lua",        critical = false },
  { path = "/tos/kernel/keychain.lua",        critical = false },
  { path = "/tos/kernel/profile.lua",         critical = false },
  { path = "/tos/kernel/i18n.lua",            critical = false },
  { path = "/tos/kernel/ustr.lua",            critical = false },
  { path = "/tos/kernel/trash.lua",           critical = false },
  { path = "/tos/kernel/vault.lua",           critical = false },

  -- ── Networking ───────────────────────────────────────────
  { path = "/tos/kernel/net/init.lua",        critical = false },
  { path = "/tos/kernel/net/protocol.lua",    critical = false },
  { path = "/tos/kernel/net/trust.lua",       critical = false },
  { path = "/tos/kernel/net/transfer.lua",    critical = false },
  { path = "/tos/kernel/net/remote.lua",      critical = false },
  { path = "/tos/kernel/net/aliases.lua",     critical = false },
  { path = "/tos/kernel/net/chatpair.lua",    critical = false },
  { path = "/tos/kernel/net/mesh.lua",        critical = false },
  { path = "/tos/kernel/net/meshctl.lua",     critical = false },

  -- ── Shell ────────────────────────────────────────────────
  { path = "/tos/shell/init.lua",             critical = true  },
  -- CRITICAL, like the launcher above it and unlike the panels tree: the
  -- CLI is the interface a seat falls back to when the TUI will not
  -- load, and `ui=cli` boots straight into it. A machine that has lost
  -- this has lost both of its shells and is down to the emergency
  -- terminal.
  { path = "/tos/shell/cli.lua",              critical = true  },
  -- The sandbox-environment builder both shells hand to every program
  -- they run. Not critical to REACH a prompt, but a shell that cannot
  -- build a program env cannot run anything from it.
  { path = "/tos/shell/progenv.lua",          critical = false },
  -- The shared keybind table. Not critical to reach a prompt, but a
  -- machine that lost it falls back to the coded defaults rather than
  -- to no keys at all — see the module.
  { path = "/tos/shell/keys.lua",             critical = false },
  { path = "/tos/shell/ext.lua",              critical = false },
  { path = "/tos/shell/login.lua",            critical = false },
  { path = "/tos/shell/colophon.lua",         critical = false },
  { path = "/tos/shell/syntax.lua",           critical = false },
  { path = "/tos/shell/chat.lua",             critical = false },
  { path = "/tos/shell/clustersetup.lua",     critical = false },
  { path = "/tos/shell/pkgpicker.lua",        critical = false },
  { path = "/tos/shell/tutorial.lua",         critical = false },
  { path = "/tos/shell/kiosk.lua",            critical = false },
  { path = "/tos/shell/launcher.lua",         critical = false },

  -- ── Panels (Norton Commander UI) ─────────────────────────
  { path = "/tos/shell/panels.lua",           critical = false },
  { path = "/tos/shell/panels/init.lua",      critical = false },
  { path = "/tos/shell/panels/commands.lua",  critical = false },
  { path = "/tos/shell/panels/context.lua",   critical = false },
  { path = "/tos/shell/panels/dialogs.lua",   critical = false },
  { path = "/tos/shell/panels/draw.lua",      critical = false },
  { path = "/tos/shell/panels/apps.lua",      critical = false },
  { path = "/tos/shell/panels/takeover.lua",  critical = false },
  { path = "/tos/shell/panels/editor.lua",    critical = false },
  { path = "/tos/shell/panels/events.lua",    critical = false },
  { path = "/tos/shell/panels/executor.lua",  critical = false },
  { path = "/tos/shell/panels/filebrowser.lua", critical = false },
  { path = "/tos/shell/panels/helpers.lua",   critical = false },
  { path = "/tos/shell/panels/keymap.lua",    critical = false },
  { path = "/tos/shell/panels/menus.lua",     critical = false },
  { path = "/tos/shell/panels/mouse.lua",     critical = false },
  { path = "/tos/shell/panels/state.lua",     critical = false },
  { path = "/tos/shell/panels/tabs.lua",      critical = false },
  { path = "/tos/shell/panels/widgets.lua",   critical = false },
  { path = "/tos/shell/panels/ui.lua",        critical = false },
  { path = "/tos/shell/panels/desktop.lua",   critical = false },
  { path = "/tos/shell/panels/home.lua",      critical = false },
  { path = "/tos/shell/panels/selection.lua", critical = false },
  { path = "/tos/shell/panels/settingsapp.lua", critical = false },
  { path = "/tos/shell/panels/monitorapp.lua", critical = false },
  { path = "/tos/shell/panels/chatapp.lua",   critical = false },
  -- (mailapp.lua left with the mail package — stage 5. The app registry
  -- pcall-requires "mailapp" from /usr/lib when the add-on is installed.)

  -- Command-table subfiles (v1.3 split — see panels/commands.lua header)
  { path = "/tos/shell/panels/commands/core.lua",   critical = false },
  { path = "/tos/shell/panels/commands/admin.lua",  critical = false },
  { path = "/tos/shell/panels/commands/extras.lua", critical = false },

  -- ── Compat layer (OpenOS-compatible APIs) ────────────────
  { path = "/tos/compat/init.lua",            critical = false },
  { path = "/tos/compat/buffer.lua",          critical = false },
  { path = "/tos/compat/colors.lua",          critical = false },
  { path = "/tos/compat/event.lua",           critical = false },
  { path = "/tos/compat/filesystem.lua",      critical = false },
  { path = "/tos/compat/internet.lua",        critical = false },
  { path = "/tos/compat/io.lua",              critical = false },
  { path = "/tos/compat/keyboard.lua",        critical = false },
  { path = "/tos/compat/serialization.lua",   critical = false },
  { path = "/tos/compat/shell_api.lua",       critical = false },
  { path = "/tos/compat/sides.lua",           critical = false },
  { path = "/tos/compat/term.lua",            critical = false },
  { path = "/tos/compat/text.lua",            critical = false },

  -- ── Peripheral helpers ───────────────────────────────────
  { path = "/tos/peripheral/inventory.lua",   critical = false },
  { path = "/tos/peripheral/redstone.lua",    critical = false },
  { path = "/tos/peripheral/robot.lua",       critical = false },

  -- ── Boot services (rc.d) ─────────────────────────────────
  { path = "/etc/rc.d/10-discoveryd.lua",     critical = false },
  { path = "/etc/rc.d/20-chatrelay.lua",      critical = false },
  { path = "/etc/rc.d/20-fileshare.lua",      critical = false },
  { path = "/etc/rc.d/20-netfsd.lua",         critical = false },
  { path = "/etc/rc.d/20-rshd.lua",           critical = false },
  -- Ships DISABLED by default (security): rshd registers but doesn't
  -- auto-start unless an admin runs `service start 20-rshd`. This marker
  -- must ship so fresh installs stay opt-in.
  { path = "/etc/rc.d/20-rshd.disabled",      critical = false },

  -- ── /usr/bin tools ───────────────────────────────────────
  { path = "/usr/bin/share.lua",              critical = false },
  { path = "/usr/bin/ssh.lua",                critical = false },

  -- (Bundled modules moved to the optional cluster/Optional-Utilities
  --  packages in v1.3.1 — they are no longer part of the base image and
  --  install via `pkg`. See TOS-Extras/.)

  -- ── /usr/man manual pages (read by the `man` command) ────
  { path = "/usr/man/boot.man",               critical = false },
  { path = "/usr/man/bootsettings.man",       critical = false },
  { path = "/usr/man/compress.man",           critical = false },
  { path = "/usr/man/decompress.man",         critical = false },
  { path = "/usr/man/edit.man",               critical = false },
  { path = "/usr/man/filesystem.man",         critical = false },
  { path = "/usr/man/intercom.man",           critical = false },
  { path = "/usr/man/jbod.man",               critical = false },
  { path = "/usr/man/netfs.man",              critical = false },
  { path = "/usr/man/man.man",                critical = false },
  { path = "/usr/man/memory.man",             critical = false },
  { path = "/usr/man/net.man",                critical = false },
  { path = "/usr/man/networking.man",         critical = false },
  { path = "/usr/man/notify.man",             critical = false },
  { path = "/usr/man/packages.man",           critical = false },
  { path = "/usr/man/pkg.man",                critical = false },
  { path = "/usr/man/screen.man",             critical = false },
  { path = "/usr/man/srm.man",                critical = false },
  { path = "/usr/man/swap.man",               critical = false },
  { path = "/usr/man/vault.man",              critical = false },

  -- ── Language catalogs (kernel.i18n DATA files) ───────────
  -- Common languages ship in the base image; rarer ones install as
  -- ordinary packages that drop a file here.
  { path = "/usr/lang/ru.lang",               critical = false },

  -- ── Self-reference ───────────────────────────────────────
  { path = "/tos/system_manifest.lua",        critical = false },
}
