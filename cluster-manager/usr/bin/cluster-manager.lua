local e=require("cluster-manager")local f={...}
local d=f[1]or"status"
if d=="status"then local a=e.status()if not a.running then
print("cluster-manager: not running")return end
print(string.format(" registered:           %s",tostring(a.registered)))
print(string.format(" domain_id:            %s",tostring(a.domain_id)))
print(string.format(" master:               %s",a.master_addr and
a.master_addr:sub(1,12).."..."or"(unknown)"))
print(string.format(" state:                %s",a.state))
print(string.format(" workers (active/busy): %d / %d",a.workers_active or 0,a.workers_busy or 0))
print(string.format(" worker bridge:        %s",a.bridge_enabled and
(tostring(a.bridge_workers).." OpenOS worker(s)")or"off (inline)"))
print(string.format(" inflight assignments: %d",a.inflight_assignments))
print(string.format(" uptime:               %.1fs",a.uptime))
print(string.format(" errors last min:      %d",a.errors_last_min))elseif d=="workers"then local a=e.workers and e.workers()or{}
if
#a==0 then
print("No OpenOS workers registered (bridge off or none have joined).")
print("Enable it in /etc/cluster-manager.cfg (worker_bridge_enabled +")
print("worker_bridge_secret), then start each worker with a matching secret.")return end
print(string.format(" %-12s %-4s %-12s %s","address","id","state","host"))
for c,b in ipairs(a)do
print(string.format(" %-12s %-4s %-12s %s",tostring(b.addr):sub(1,12),tostring(b.id),tostring(b.state),tostring(
b.hostname or"?")))end elseif d=="drain"then e.drain()
print("draining (Master will be notified on next heartbeat)")elseif d=="undrain"then e.undrain()
print("undrained (resumed accepting work)")elseif d=="pair"then local a=f[2]local b=f[3]
if not a or not b then
print("Usage: cluster-manager pair <master-addr> <code>")
print("  Run `cluster pair start` on the Master first to get the code.")os.exit(1)end;local g,c=e.pair(a,b)
if g then
print("Paired: "..tostring(c))
print("This Manager will register on the next service start.")print("Run: service start cluster-manager")else
io.stderr:write(
"pair failed: "..tostring(c).."\n")os.exit(1)end elseif d=="help"or d=="--help"or d=="-h"then
print("Usage: cluster-manager [status|workers|drain|undrain|pair]")
print("  status                       show local Manager state (default)")
print("  workers                      list registered OpenOS bridge workers")
print("  drain                        stop accepting new assignments")
print("  undrain                      resume accepting assignments")
print("  pair <master-addr> <code>    pair with a Master (trust bootstrap)")else
io.stderr:write("cluster-manager: unknown subcommand: "..d.."\n")io.stderr:write("try: cluster-manager help\n")
os.exit(1)end