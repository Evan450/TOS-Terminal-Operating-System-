local A,C;do local a,b=pcall(require,"term")A=a and b or nil
local c,d=pcall(require,"event")C=c and d or nil end
local y={}local function x(a)
io.stderr:write("cluster: "..tostring(a).."\n")os.exit(1)end
local E="clusterd is not running. Start it with: service start clusterd"
local I=E.." (if it is running, update TOS: this one is too old)"
local function P(a,...)if type(ipc)~="table"then x(I)end
local b=table.pack(ipc.call("cluster",a,...))
if b[1]==nil then local c=tostring(b[2])if c=="not running"or
c:find("not started",1,true)then x(E)end;x(c)end;if b[1]==false then x(b[2])end;return table.unpack(b,2,b.n)end
local z=setmetatable({},{__index=function(b,a)local c=function(...)return P(a,...)end;b[a]=c;return c end})local D;local function Q()D=D or z.now()return D end
local function J(a)if not a then return"-"end
local c=Q()local b=math.floor(c-a)if b<0 then return"-"end
if b<60 then return b.."s ago"end
if b<3600 then return math.floor(b/60).."m ago"end;return math.floor(b/3600).."h ago"end
local function K(a,b)a=tostring(a or"")if#a>=b then return a:sub(1,b)end;return a..string.rep(" ",b-#
a)end
local function L(a,b)a=tostring(a or"")if#a>=b then return a:sub(-b)end;return
string.rep(" ",b-#a)..a end
local function R(a,b)
if b.key=="workers"then local c=a.last_snapshot;if not c then return"-/-"end;return

tostring(c.workers_busy or 0).."/"..tostring(c.workers_active or 0)elseif b.key=="queue"then return
a.last_snapshot and tostring(
a.last_snapshot.queue_depth or 0)or"-"elseif b.key=="storage"then
local c=a.storage or{}local d=c.external_type or"-"
return tostring(d):sub(1,6)elseif b.key=="submitted_at"then return J(a.submitted_at)end;return a[b.key]end
local function F(a,b)if not a or#a==0 then print("(no entries)")return end
local c={}for f,e in ipairs(b)do
local g=(e.align=="right")and L or K
c[#c+1]=g(e[2]or e.header,e[3]or e.width or 10)end
print(table.concat(c,"  "))local d={}for f,e in ipairs(b)do
d[#d+1]=string.rep("-",e[3]or e.width or 10)end
print(table.concat(d,"  "))
for f,e in ipairs(a)do local g={}
for f,h in ipairs(b)do
local i={key=h[1]or h.key,align=h[4]or h.align}local j=(i.align=="right")and L or K
g[#g+1]=j(tostring(
R(e,i)or"-"),h[3]or h.width or 10)end;print(table.concat(g,"  "))end end
local function B(a,b)if not a then print("(nil)")return end;local c={}if b then
for e,d in ipairs(b)do if a[d]~=nil then
print(string.format("%-20s %s",
d..":",tostring(a[d])))c[d]=true end end end
for e,d in pairs(a)do if

not c[e]and type(d)~="table"and type(d)~="function"then
print(string.format("%-20s %s",e..":",tostring(d)))end end end
function y.status(a)local b=z.status()
if not b then x("daemon not responding")end
print(string.format("Managers:  %d active   %d degraded   %d draining   %d offline",b.managers.active or 0,
b.managers.degraded or 0,b.managers.draining or 0,b.managers.offline or 0))
print(string.format("Jobs:      %d pending  %d running    %d done       %d failed   %d cancelled",b.jobs.pending or 0,
b.jobs.running or 0,b.jobs.done or 0,b.jobs.failed or 0,b.jobs.cancelled or 0))
if b.storage then local c=b.storage.used_bytes or 0
local d=b.storage.capacity_bytes or 0
print(string.format("Storage:   configured, %d / %d bytes used",c,d))else print("Storage:   not configured")end
print(string.format("Budget:    host_thread_budget=%s, in_flight=%d",tostring(b.host_thread_budget),
b.compute_bound_in_flight or 0))end
function y.managers(a)
if a[1]then
local c=tonumber(a[1])or x("invalid domain_id: "..a[1])local b=z.getManager(c)
if not b then x("no such domain: "..c)end
B(b,{"hostname","domain_id","state","profile","worker_count","master_path","last_heartbeat","cluster_protocol","software_version"})if b.storage then print("storage:")B(b.storage)end
if
b.last_snapshot then print("last snapshot:")B(b.last_snapshot)end else local b=z.listManagers()
F(b,{{"domain_id","DOM",5,"right"},{"hostname","HOSTNAME",16,"left"},{"state","STATE",10,"left"},{"profile","PROFILE",8,"left"},{"workers","WORKERS",10,"left"},{"queue","QUEUE",6,"right"},{"storage","STOR",6,"left"}})end end
function y.jobs(a)
if a[1]then
local c=tonumber(a[1])or x("invalid job_id: "..a[1])local b=z.getJob(c)
if not b then x("no such job: "..c)end
B(b,{"job_id","state","submitted_by","compute_profile","retry_policy","result_sink","storage_preference"})print("")print("Assignments:")
F(b.assignments_list or{},{{"assignment_id","AID",5,"right"},{"state","STATE",12,"left"},{"attempts","ATT",4,"right"},{"assigned_to","MGR",18,"left"},{"dispatched_at","START",12,"left"}})else local b=z.listJobs()
F(b,{{"job_id","JOB",5,"right"},{"state","STATE",11,"left"},{"submitted_by","USER",10,"left"},{"submitted_at","AT",12,"left"},{"assignments","A",7,"left"}})end end
function y.storage(a)local b=z.storageStatus()if not b then
print("Public storage: not configured")return end
B(b,{"address","used_bytes","capacity_bytes","last_seen"})end
function y.submit(a)
local b=a[1]or x("usage: cluster submit <job-file>")if type(ipc)~="table"then x(I)end
local e,h=ipc.call("cluster","may","submit")if e==nil then x(E)end;if not e then x(h)end;local c,i=io.open(b,"r")if not c then
x(
"cannot read "..b..": "..tostring(i))end;local j=c:read("*a")c:close()
local f,k=load(j,"="..b,"t")if not f then
x("job file failed to load: "..tostring(k))end;local l,d=pcall(f)if not l then
x("job file threw: "..tostring(d))end;if type(d)~="table"then
x("job file must return a table")end;local g,m=z.submit(d)if not g then
x(tostring(m))end
print("Submitted job "..tostring(g))end
function y.cancel(a)
local b=tonumber(a[1])or x("usage: cluster cancel <job_id>")local c,d=z.cancelJob(b)if not c then x(tostring(d))end;print(
"Cancelled job "..tostring(b))end
function y.retry(a)
local c=tonumber(a[1])or x("usage: cluster retry <job_id>")local b,d=z.retryJob(c)if not b then x(tostring(d))end;print(
"Retried as job "..tostring(b))end
function y.drain(a)
local b=tonumber(a[1])or x("usage: cluster drain <domain_id>")local c,d=z.drainManager(b)if not c then x(tostring(d))end;print(
"Draining domain "..tostring(b))end
function y.undrain(a)
local b=tonumber(a[1])or x("usage: cluster undrain <domain_id>")local c,d=z.undrainManager(b)
if not c then x(tostring(d))end
print("Domain "..tostring(b).." active")end
function y.forget(a)
local b=tonumber(a[1])or x("usage: cluster forget <domain_id>")local c,d=z.forgetManager(b)if not c then x(tostring(d))end;print(
"Forgot domain "..tostring(b))end
function y.pair(a)local b=a[1]or"start"
if b=="start"then local c,d=z.startPairing()if not c then
x(
"pair start failed: "..tostring(d or"unknown"))end
print("Pairing window open.")print("")print("  Code: "..c.code)print("")
print(string.format("Expires in %d seconds. On each Manager run:",math.floor(c.expires_in)))
print("  cluster-manager pair <master-addr> "..c.code)print("")
print("Use `cluster pair status` to check progress, `cluster pair close` to end.")elseif b=="status"then local c=z.pairingInfo()if not c then
print("No pairing window open.")return end
print(string.format("Pairing window open: %d seconds remaining",math.floor(c.expires_in)))
print(string.format("Managers paired so far: %d",c.paired or 0))elseif b=="close"then if z.closePairing()then print("Pairing window closed.")else
print("No pairing window was open.")end else
print("Usage: cluster pair [start|status|close]")
print("  start   open a 5-minute pairing window and print the code")
print("  status  show remaining time + how many managers paired")print("  close   close the active window early")end end
function y.watch(a)
if not A or not A.clear then x("watch requires a terminal")end;local b=1.0;local d=8;for f=1,#a do
if a[f]=="--interval"and a[f+1]then
b=tonumber(a[f+1])or 1.0 elseif a[f]=="--events"and a[f+1]then d=tonumber(a[f+1])or 8 end end;if
b<0.2 then b=0.2 end;if b>60 then b=60 end;local e=print;print=function(f)
A.write(tostring(f or"").."\n")end;local function c(f)
print(
string.format("── %s ",f)..string.rep("─",56-#f))end
print("Watching cluster. Refresh = "..
b.."s. Press 'q' to quit.")
while true do A.clear()D=nil;local f=z.status()local g=f.managers or{}
local h=f.jobs or{}
print(string.format("Cluster | mgrs: active=%d degr=%d drain=%d off=%d | jobs: pend=%d run=%d done=%d fail=%d | cb_in_flight=%d budget=%s",
g.active or 0,g.degraded or 0,g.draining or 0,g.offline or 0,h.pending or 0,h.running or 0,
h.done or 0,h.failed or 0,f.compute_bound_in_flight or 0,tostring(f.host_thread_budget or"?")))
if f.storage then
print(string.format("Storage | %s used=%s/%s last_seen=%s",f.storage.address and
f.storage.address:sub(1,8).."..."or"?",tostring(
f.storage.used_bytes or"?"),tostring(f.storage.capacity_bytes or"?"),tostring(
f.storage.last_seen or"?")))end;print("")c("Managers")y.managers({})print("")
c("Recent jobs")y.jobs({})print("")c("Events (newest last)")local i=
z.recentEvents(d)or{}
if#i==0 then print("  (no recent events)")else
for l,k in
ipairs(i)do local m=""
if type(k.detail)=="table"then local n={}for o,p in pairs(k.detail)do n[#n+1]=o..
"="..tostring(p)end;m=" "..
table.concat(n," ")end
print(string.format("  [%.1fs] %s%s",k.time or 0,tostring(k.kind),m))end end;print("")
print("  q=quit | --interval Ns | --events N")local j=false
if C and C.pull then local l,m,k=C.pull(b,"key_down")if l=="key_down"and
(k==113 or k==81)then j=true end end;if j then break end end;print=e;if A and A.clear then A.clear()end end
function y.config(a)
if a[1]=="set"then local b,d=a[2],a[3]if not b or d==nil then
x("usage: cluster config set <key> <value>")end;local e,c=z.setConfig(b,d)if not e then
x(tostring(c))end
if c and c.restart_required then
print("Set "..
b.."; restart required for the change to take effect.")else print("Set "..b..".")end else local b=z.getConfig()B(b)end end
function y.log(a)local c=tonumber(a[1])or 20;local b=z.recentEvents(c)
if not b or
#b==0 then print("(no recent events)")return end
for e,d in ipairs(b)do local f=""
if type(d.detail)=="table"then local g={}for h,i in pairs(d.detail)do g[#g+1]=h.."="..
tostring(i)end;f=" "..
table.concat(g," ")end
print(string.format("[%s] %s%s",J(d.time),tostring(d.kind),f))end end
local S={status=y.status,managers=y.managers,jobs=y.jobs,storage=y.storage,submit=y.submit,cancel=y.cancel,retry=y.retry,drain=y.drain,undrain=y.undrain,forget=y.forget,watch=y.watch,config=y.config,log=y.log,pair=y.pair}
local function M()print("Usage: cluster <subcommand> [args...]")
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
print("                        Trust-bootstrap helper for new Managers")os.exit(0)end;local N={...}local G=table.remove(N,1)if not G then M()end;local O=S[G]
if not O then io.stderr:write(
"unknown subcommand: "..G.."\n")M()end;local T,H=pcall(O,N)if not T then if type(H)=="table"then error(H,0)end
io.stderr:write(
"cluster: "..tostring(H).."\n")os.exit(1)end