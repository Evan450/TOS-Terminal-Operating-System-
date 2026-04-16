-- ╔══════════════════════════════════════╗
-- ║  TOS Remote Shell Daemon (rshd)     ║
-- ║  Accept remote command execution    ║
-- ╚══════════════════════════════════════╝
-- Listens for REMOTE_EXEC packets from TRUSTED peers and
-- executes the requested command in a sandboxed environment.
-- Results are sent back as REMOTE_RES packets.
--
-- Only runs if the kernel.net.remote module is loaded (it
-- registers its own packet handlers). This service just ensures
-- the remote module stays initialized and provides start/stop
-- control for the rc manager.

local running = false

local function start()
  local net = _G._TOS and _G._TOS.net
  if not net then return end

  -- The remote module is initialized during kernel boot (stage 10).
  -- Verify it's actually loaded.
  local ok, remoteMod = pcall(require, "kernel.net.remote")
  if not ok then return end

  running = true
  if _G._TOS and _G._TOS.log then
    _G._TOS.log("rc", "rshd: Remote shell daemon active")
  end
end

local function stop()
  running = false
end

return {
  start   = start,
  stop    = stop,
  deps    = {},
  restart = true,
  caps    = { net = true },
  user    = "_kernel_",
}
