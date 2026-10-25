local x=require("cluster.api")local B=require("users")local z,C;do
local a,b=pcall(require,"term")z=a and b or nil;local c,d=pcall(require,"event")
C=c and d or nil end;local v={}local function w(a)
io.stderr:write(
"cluster: "..tostring(a).."\n")os.exit(1)end
local function L(a)
local b={[0]="GUEST",[1]="USER",[2]="ADMIN",[3]="ROOT"}return b[a]or("tier"..tostring(a))end
local function y(a)if not B or not B.TIER or not B.currentSession then
w("users subsystem unavailable; refusing to run")end;local b=B.TIER[a]
if not b then w(
"internal: unknown tier "..tostring(a))end;local c=B.currentSession()
if not c then w("not logged in")end;local d=c.tier or 0;if d<b then
io.stderr:write(string.format("cluster: permission denied (need %s, have %s)\n",a,L(d)))os.exit(1)end end
local function F(a)if not a then return"-"end
local c=require("computer").uptime()local b=math.floor(c-a)if b<0 then return"-"end
if b<60 then return b.."s ago"end
if b<3600 then return math.floor(b/60).."m ago"end;return math.floor(b/3600).."h ago"end
local function G(a,b)a=tostring(a or"")if#a>=b then return a:sub(1,b)end;return a..string.rep(" ",b-#
a)end
local function H(a,b)a=tostring(a or"")if#a>=b then return a:sub(-b)end;return
string.rep(" ",b-#a)..a end
local function M(a,b)
if b.key=="workers"then local c=a.last_snapshot;if not c then return"-/-"end;return

tostring(c.workers_busy or 0).."/"..tostring(c.workers_active or 0)elseif b.key=="queue"then return
a.last_snapshot and tostring(
a.last_snapshot.queue_depth or 0)or"-"elseif b.key=="storage"then
local c=a.storage or{}local d=c.external_type or"-"
return tostring(d):sub(1,6)elseif b.key=="submitted_at"then return F(a.submitted_at)end;return a[b.key]end
local function D(a,b)if not a or#a==0 then print("(no entries)")return end
local c={}for f,e in ipairs(b)do
local g=(e.align=="right")and H or G
c[#c+1]=g(e[2]or e.header,e[3]or e.width or 10)end
print(table.concat(c,"  "))local d={}for f,e in ipairs(b)do
d[#d+1]=string.rep("-",e[3]or e.width or 10)end
print(table.concat(d,"  "))
for f,e in ipairs(a)do local g={}
for f,h in ipairs(b)do
local i={key=h[1]or h.key,align=h[4]or h.align}local j=(i.align=="right")and H or G
g[#g+1]=j(tostring(
M(e,i)or"-"),h[3]or h.width or 10)end;print(table.concat(g,"  "))end end
local function A(a,b)if not a then print("(nil)")return end;local c={}if b then
for e,d in ipairs(b)do if a[d]~=nil then
print(string.format("%-20s %s",
d..":",tostring(a[d])))c[d]=true end end end
for e,d in pairs(a)do if

not c[e]and type(d)~="table"and type(d)~="function"then
print(string.format("%-20s %s",e..":",tostring(d)))end end end
function v.status(a)y("ADMIN")local b=x.status()if not b then
w("daemon not responding")end
print(string.format("Managers:  %d active   %d degraded   %d draining   %d offline",
b.managers.active or 0,b.managers.degraded or 0,b.managers.draining or 0,
b.managers.offline or 0))
print(string.format("Jobs:      %d pending  %d running    %d done       %d failed   %d cancelled",b.jobs.pending or 0,
b.jobs.running or 0,b.jobs.done or 0,b.jobs.failed or 0,b.jobs.cancelled or 0))
if b.storage then local c=b.storage.used_bytes or 0
local d=b.storage.capacity_bytes or 0
print(string.format("Storage:   configured, %d / %d bytes used",c,d))else print("Storage:   not configured")end
print(string.format("Budget:    host_thread_budget=%s, in_flight=%d",tostring(b.host_thread_budget),
b.compute_bound_in_flight or 0))end
function v.managers(a)y("ADMIN")
if a[1]then local c=tonumber(a[1])or
w("invalid domain_id: "..a[1])
local b=x.getManager(c)if not b then w("no such domain: "..c)end
A(b,{"hostname","domain_id","state","profile","worker_count","master_path","last_heartbeat","cluster_protocol","software_version"})if b.storage then print("storage:")A(b.storage)end
if
b.last_snapshot then print("last snapshot:")A(b.last_snapshot)end else local b=x.listManagers()
D(b,{{"domain_id","DOM",5,"right"},{"hostname","HOSTNAME",16,"left"},{"state","STATE",10,"left"},{"profile","PROFILE",8,"left"},{"workers","WORKERS",10,"left"},{"queue","QUEUE",6,"right"},{"storage","STOR",6,"left"}})end end
function v.jobs(a)y("ADMIN")
if a[1]then
local c=tonumber(a[1])or w("invalid job_id: "..a[1])local b=x.getJob(c)
if not b then w("no such job: "..c)end
A(b,{"job_id","state","submitted_by","compute_profile","retry_policy","result_sink","storage_preference"})print("")print("Assignments:")
D(b.assignments_list or{},{{"assignment_id","AID",5,"right"},{"state","STATE",12,"left"},{"attempts","ATT",4,"right"},{"assigned_to","MGR",18,"left"},{"dispatched_at","START",12,"left"}})else local b=x.listJobs()
D(b,{{"job_id","JOB",5,"right"},{"state","STATE",11,"left"},{"submitted_by","USER",10,"left"},{"submitted_at","AT",12,"left"},{"assignments","A",7,"left"}})end end
function v.storage(a)y("ADMIN")local b=x.storageStatus()if not b then
print("Public storage: not configured")return end
A(b,{"address","used_bytes","capacity_bytes","last_seen"})end
function v.submit(a)y("ROOT")
local e=a[1]or w("usage: cluster submit <job-file>")local c,f=loadfile(e,"t")if not c then
w("loadfile failed: "..tostring(f))end;local g,b=pcall(c)if not g then
w("job file threw: "..tostring(b))end;if type(b)~="table"then
w("job file must return a table")end;local d,h=x.submit(b)if not d then
w(tostring(h))end
print("Submitted job "..tostring(d))end
function v.cancel(a)y("ROOT")
local b=tonumber(a[1])or w("usage: cluster cancel <job_id>")local c,d=x.cancelJob(b)if not c then w(tostring(d))end;print(
"Cancelled job "..tostring(b))end
function v.retry(a)y("ROOT")
local c=tonumber(a[1])or w("usage: cluster retry <job_id>")local b,d=x.retryJob(c)if not b then w(tostring(d))end;print(
"Retried as job "..tostring(b))end
function v.drain(a)y("ROOT")
local b=tonumber(a[1])or w("usage: cluster drain <domain_id>")local c,d=x.drainManager(b)if not c then w(tostring(d))end;print(
"Draining domain "..tostring(b))end
function v.undrain(a)y("ROOT")
local b=tonumber(a[1])or w("usage: cluster undrain <domain_id>")local c,d=x.undrainManager(b)
if not c then w(tostring(d))end
print("Domain "..tostring(b).." active")end
function v.forget(a)y("ROOT")
local b=tonumber(a[1])or w("usage: cluster forget <domain_id>")local c,d=x.forgetManager(b)if not c then w(tostring(d))end;print(
"Forgot domain "..tostring(b))end
function v.pair(a)y("ROOT")local b=a[1]or"start"
if b=="start"then
local c,d=x.startPairing()if not c then
w("pair start failed: "..tostring(d or"unknown"))end
print("Pairing window open.")print("")print("  Code: "..c.code)print("")
print(string.format("Expires in %d seconds. On each Manager run:",math.floor(c.expires_in)))
print("  cluster-manager pair <master-addr> "..c.code)print("")
print("Use `cluster pair status` to check progress, `cluster pair close` to end.")elseif b=="status"then local c=x.pairingInfo()if not c then
print("No pairing window open.")return end
print(string.format("Pairing window open: %d seconds remaining",math.floor(c.expires_in)))
print(string.format("Managers paired so far: %d",c.paired or 0))elseif b=="close"then if x.closePairing()then print("Pairing window closed.")else
print("No pairing window was open.")end else
print("Usage: cluster pair [start|status|close]")
print("  start   open a 5-minute pairing window and print the code")
print("  status  show remaining time + how many managers paired")print("  close   close the active window early")end end
function v.watch(a)y("ADMIN")if not z or not z.clear then
w("watch requires a terminal")end;local b=1.0;local e=8;for f=1,#a do
if
a[f]=="--interval"and a[f+1]then b=tonumber(a[f+1])or 1.0 elseif
a[f]=="--events"and a[f+1]then e=tonumber(a[f+1])or 8 end end;if
b<0.2 then b=0.2 end;if b>60 then b=60 end;local c=require("computer")local function d(f)
print(
string.format("── %s ",f)..string.rep("─",56-#f))end
print("Watching cluster. Refresh = "..
b.."s. Press 'q' to quit.")
while true do z.clear()local f=x.status()local g=f.managers or{}
local h=f.jobs or{}
print(string.format("Cluster | mgrs: active=%d degr=%d drain=%d off=%d | jobs: pend=%d run=%d done=%d fail=%d | cb_in_flight=%d budget=%s",
g.active or 0,g.degraded or 0,g.draining or 0,g.offline or 0,h.pending or 0,h.running or 0,
h.done or 0,h.failed or 0,f.compute_bound_in_flight or 0,tostring(f.host_thread_budget or"?")))
if f.storage then
print(string.format("Storage | %s used=%s/%s last_seen=%s",f.storage.address and
f.storage.address:sub(1,8).."..."or"?",tostring(
f.storage.used_bytes or"?"),tostring(f.storage.capacity_bytes or"?"),tostring(
f.storage.last_seen or"?")))end;print("")d("Managers")v.managers({})print("")
d("Recent jobs")v.jobs({})print("")d("Events (newest last)")local i=
x.recentEvents(e)or{}
if#i==0 then print("  (no recent events)")else
for l,k in
ipairs(i)do local m=""
if type(k.detail)=="table"then local n={}for o,p in pairs(k.detail)do n[#n+1]=o..
"="..tostring(p)end;m=" "..
table.concat(n," ")end
print(string.format("  [%.1fs] %s%s",k.time or 0,tostring(k.kind),m))end end;print("")
print("  q=quit | --interval Ns | --events N")local j=false
if C and C.pull then local k=c.uptime()
while c.uptime()-k<b do local l=b-
(c.uptime()-k)if l<=0 then break end
local n,o,m=C.pull(math.min(0.25,l),"key_down")
if n=="key_down"then if m==113 or m==81 then j=true;break end end end end;if j then break end end;if z and z.clear then z.clear()end end
function v.config(a)
if a[1]=="set"then y("ROOT")local b,d=a[2],a[3]if not b or d==nil then
w("usage: cluster config set <key> <value>")end;local e,c=x.setConfig(b,d)if not e then
w(tostring(c))end
if c and c.restart_required then
print("Set "..
b.."; restart required for the change to take effect.")else print("Set "..b..".")end else y("ADMIN")local b=x.getConfig()A(b)end end
function v.log(a)y("ADMIN")local c=tonumber(a[1])or 20
local b=x.recentEvents(c)
if not b or#b==0 then print("(no recent events)")return end
for e,d in ipairs(b)do local f=""
if type(d.detail)=="table"then local g={}for h,i in pairs(d.detail)do g[#g+1]=h.."="..
tostring(i)end;f=" "..
table.concat(g," ")end
print(string.format("[%s] %s%s",F(d.time),tostring(d.kind),f))end end
local N={status=v.status,managers=v.managers,jobs=v.jobs,storage=v.storage,submit=v.submit,cancel=v.cancel,retry=v.retry,drain=v.drain,undrain=v.undrain,forget=v.forget,watch=v.watch,config=v.config,log=v.log,pair=v.pair}
local function I()print("Usage: cluster <subcommand> [args...]")
print("Subcommands:")print("  status                Cluster summary")
print("  managers [domain_id]  List managers / show one")
print("  jobs [job_id]         List jobs / show one")
print("  storage               Public storage status")print("  submit <file>         Submit a job")
print("  cancel <job_id>       Cancel a running job")
print("  retry <job_id>        Retry a failed job")
print("  drain <domain_id>     Drain a manager (stop new work)")
print("  undrain <domain_id>   Resume a drained manager")
print("  forget <domain_id>    Remove an offline manager")print("  watch                 Live dashboard")
print("  config [set k v]      View or edit config")
print("  log [n]               Show recent cluster events")print("  pair [start|status|close]")
print("                        Trust-bootstrap helper for new Managers")os.exit(0)end;local J={...}local E=table.remove(J,1)if not E then I()end;local K=N[E]
if not K then io.stderr:write(
"unknown subcommand: "..E.."\n")I()end;local O,P=pcall(K,J)if not O then
io.stderr:write("cluster: "..tostring(P).."\n")os.exit(1)end