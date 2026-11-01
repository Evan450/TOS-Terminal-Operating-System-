-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  /etc/rc.d/cluster-manager.lua — TOS service shim            ║
-- ╚══════════════════════════════════════════════════════════════╝
local mgr = require("cluster-manager")
return {
  start = mgr.start,
  stop  = mgr.stop,
}
