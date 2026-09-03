-- ╔══════════════════════════════════════╗
-- ║  TOS Remote Shell Daemon (rshd)      ║
-- ║  Accept remote command execution     ║
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

  -- #SEC L — arm the handler. The daemon's arm state is what gates exec.
  -- #MEM — via net.setServiceArm instead of require()ing the remote
  -- module: requiring it here forced it into RAM on every boot just to
  -- flip a flag. net records the arm state and applies it when the module
  -- loads (first REMOTE_EXEC packet / first outbound rsh). Fail-closed:
  -- an unloaded backend refuses exec exactly like a disabled one.
  if net.setServiceArm then
    net.setServiceArm("rshd", true)
  else
    -- Older kernel without the arm API: keep the original direct path.
    local ok, remoteMod = pcall(require, "kernel.net.remote")
    if not ok then return end
    if remoteMod.setEnabled then remoteMod.setEnabled(true) end
  end

  running = true
  if _G._TOS and _G._TOS.log then
    _G._TOS.log("rc", "rshd: Remote shell daemon active")
  end
end

local function stop()
  -- #SEC L — disable the handler for real, not just flip a local flag.
  -- #MEM — through the arm API when available (also disables the backend
  -- immediately if it is loaded); direct module fallback otherwise.
  local net0 = _G._TOS and _G._TOS.net
  if net0 and net0.setServiceArm then
    net0.setServiceArm("rshd", false)
  else
    local ok, remoteMod = pcall(require, "kernel.net.remote")
    if ok and remoteMod.setEnabled then remoteMod.setEnabled(false) end
  end
  running = false
  if _G._TOS and _G._TOS.log then
    _G._TOS.log("rc", "rshd: Remote shell daemon stopped (exec requests now refused)")
  end
end

return {
  start   = start,
  stop    = stop,
  deps    = {},
  restart = true,
  caps    = { net = true },
  user    = "_kernel_",
}
