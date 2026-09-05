-- ╔══════════════════════════════════════════════════════════════╗
-- ║  cluster-manager — Manager CLI                               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Thin wrapper over the daemon's API. Operators use this to inspect
-- the local Manager and trigger drain/undrain without going through
-- the full Master CLI.

local mgr = require("cluster-manager")

local args = {...}
local sub = args[1] or "status"

if sub == "status" then
  local s = mgr.status()
  if not s.running then print("cluster-manager: not running"); return end
  print(string.format(" registered:           %s", tostring(s.registered)))
  print(string.format(" domain_id:            %s", tostring(s.domain_id)))
  print(string.format(" master:               %s",
    s.master_addr and s.master_addr:sub(1, 12) .. "..." or "(unknown)"))
  print(string.format(" state:                %s", s.state))
  print(string.format(" workers (active/busy): %d / %d",
    s.workers_active or 0, s.workers_busy or 0))
  print(string.format(" worker bridge:        %s",
    s.bridge_enabled and (tostring(s.bridge_workers) .. " OpenOS worker(s)") or "off (inline)"))
  print(string.format(" inflight assignments: %d", s.inflight_assignments))
  print(string.format(" uptime:               %.1fs", s.uptime))
  print(string.format(" errors last min:      %d", s.errors_last_min))

elseif sub == "workers" then
  -- CLUSTER v2 — registered OpenOS workers on the bridge.
  local list = mgr.workers and mgr.workers() or {}
  if #list == 0 then
    print("No OpenOS workers registered (bridge off or none have joined).")
    print("Enable it in /etc/cluster-manager.cfg (worker_bridge_enabled +")
    print("worker_bridge_secret), then start each worker with a matching secret.")
    return
  end
  print(string.format(" %-12s %-4s %-12s %s", "address", "id", "state", "host"))
  for _, w in ipairs(list) do
    print(string.format(" %-12s %-4s %-12s %s",
      tostring(w.addr):sub(1, 12), tostring(w.id),
      tostring(w.state), tostring(w.hostname or "?")))
  end

elseif sub == "drain" then
  mgr.drain()
  print("draining (Master will be notified on next heartbeat)")

elseif sub == "undrain" then
  mgr.undrain()
  print("undrained (resumed accepting work)")

elseif sub == "pair" then
  -- CLUSTER-6 — pair this Manager with a Master using the code shown
  -- by `cluster pair start` on the Master side.
  local masterAddr = args[2]
  local code       = args[3]
  if not masterAddr or not code then
    print("Usage: cluster-manager pair <master-addr> <code>")
    print("  Run `cluster pair start` on the Master first to get the code.")
    os.exit(1)
  end
  local ok, msg = mgr.pair(masterAddr, code)
  if ok then
    print("Paired: " .. tostring(msg))
    print("This Manager will register on the next service start.")
    print("Run: service start cluster-manager")
  else
    io.stderr:write("pair failed: " .. tostring(msg) .. "\n")
    os.exit(1)
  end

elseif sub == "help" or sub == "--help" or sub == "-h" then
  print("Usage: cluster-manager [status|workers|drain|undrain|pair]")
  print("  status                       show local Manager state (default)")
  print("  workers                      list registered OpenOS bridge workers")
  print("  drain                        stop accepting new assignments")
  print("  undrain                      resume accepting assignments")
  print("  pair <master-addr> <code>    pair with a Master (trust bootstrap)")

else
  io.stderr:write("cluster-manager: unknown subcommand: " .. sub .. "\n")
  io.stderr:write("try: cluster-manager help\n")
  os.exit(1)
end
