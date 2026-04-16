-- TOS System Manifest - Single source of truth for system files.
-- Used by:
--   /init.lua (boot verification, critical files only)
--   kernel.verifySystem() (full integrity check via `verify` command)
--   deploy/install tooling
--
-- Fields:
--   path     = absolute path on the OC filesystem
--   critical = true if the system cannot boot without this file

return {
  -- Boot
  { path = "/init.lua",                       critical = true  },

  -- Kernel core
  { path = "/tos/kernel/init.lua",            critical = true  },
  { path = "/tos/kernel/log.lua",             critical = true  },
  { path = "/tos/kernel/hal.lua",             critical = true  },
  { path = "/tos/kernel/event.lua",           critical = true  },
  { path = "/tos/kernel/process.lua",         critical = true  },
  { path = "/tos/kernel/fs.lua",              critical = true  },
  { path = "/tos/kernel/serialize.lua",       critical = true  },
  { path = "/tos/kernel/display.lua",         critical = true  },

  -- Kernel optional
  { path = "/tos/kernel/screen.lua",          critical = false },
  { path = "/tos/kernel/config.lua",          critical = false },
  { path = "/tos/kernel/users.lua",           critical = false },
  { path = "/tos/kernel/securefs.lua",        critical = false },
  { path = "/tos/kernel/sandbox.lua",         critical = false },
  { path = "/tos/kernel/power.lua",           critical = false },
  { path = "/tos/kernel/rc.lua",              critical = false },
  { path = "/tos/kernel/modules.lua",         critical = false },
  { path = "/tos/kernel/crypto.lua",          critical = false },
  { path = "/tos/kernel/pipe.lua",            critical = false },
  { path = "/tos/kernel/env.lua",             critical = false },
  { path = "/tos/kernel/cron.lua",            critical = false },

  -- Networking
  { path = "/tos/kernel/net/init.lua",        critical = false },
  { path = "/tos/kernel/net/protocol.lua",    critical = false },
  { path = "/tos/kernel/net/trust.lua",       critical = false },
  { path = "/tos/kernel/net/transfer.lua",    critical = false },
  { path = "/tos/kernel/net/remote.lua",      critical = false },

  -- Shell
  { path = "/tos/shell/init.lua",             critical = true  },
  { path = "/tos/shell/ext.lua",              critical = false },
  { path = "/tos/shell/login.lua",            critical = false },
  { path = "/tos/shell/panels.lua",           critical = false },
  { path = "/tos/shell/panels/init.lua",      critical = false },
  { path = "/tos/shell/chat.lua",             critical = false },
  { path = "/tos/shell/tutorial.lua",         critical = false },

  -- Compat layer
  { path = "/tos/compat/init.lua",            critical = false },
  { path = "/tos/compat/filesystem.lua",      critical = false },
  { path = "/tos/compat/io.lua",              critical = false },
  { path = "/tos/compat/shell_api.lua",       critical = false },

  -- Self-reference
  { path = "/tos/system_manifest.lua",        critical = false },
}
