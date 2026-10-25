local l,m="active","degraded"local i={}local n=2
local function k(a,b)if not a.storage_preference or
a.storage_preference==""then return true end;local c=
b.storage or{}
return c.external_type==a.storage_preference end;local function p(a,b)return 0 end
local function j(a)local b=a.last_snapshot;if not b then return 0 end
local d=b.workers_active or 0;local e=b.workers_busy or 0;local c=d-e;if c<0 then c=0 end;return c end
local function o(b,a,c)local e=a.last_snapshot or{}local f=j(a)local d=0;d=d+f*10;d=d+ (
a.state==l and 50 or 0)d=d+
(a.state==m and 10 or 0)if k(b,a)and b.storage_preference and
b.storage_preference~=""then d=d+25 end;local g=
e.storage_used or 0;d=d-g*20;local h=e.queue_depth or 0;d=d-h*2;local q=
e.errors_last_min or 0;d=d-q*5;d=d+p(b,a)return d end
function i.pickDomain(b,c,a)a=a or{}local f=a.host_thread_budget or 4
local g=a.compute_bound_in_flight or 0;if b.compute_profile=="compute_bound"then
if g>=f*n then return nil,"thread_budget_saturated"end end;local d={}local e=false
for q,h in
pairs(c or{})do e=true;local t=h.last_snapshot;local r=true;local s=nil
if h.state~=l and h.state~=m then
r=false;s="state:"..tostring(h.state)elseif not t then r=false;s="no_snapshot"elseif
j(h)<=0 then r=false;s="no_free_workers"elseif(t.storage_used or 0)>=0.95 then
r=false;s="storage_full"elseif not k(b,h)then r=false;s="storage_pref_mismatch"end
if r then d[#d+1]={address=q,manager=h}else d._last_reject=s end end
if#d==0 then if not e then return nil,"no_managers_registered"end;return nil,d._last_reject or
"no_eligible_manager"end;for q,h in ipairs(d)do h.score=o(b,h.manager,a)end
table.sort(d,function(h,q)if
h.score~=q.score then return h.score>q.score end
local r=
(
h.manager.last_snapshot and h.manager.last_snapshot.queue_depth)or 0;local s=
(q.manager.last_snapshot and q.manager.last_snapshot.queue_depth)or 0;if r~=
s then return r<s end;return
tostring(h.address)<tostring(q.address)end)return d[1].address end
function i.hasAnyActiveCapacity(a)
for c,b in pairs(a or{})do if(b.state==l or b.state==m)and
j(b)>0 then return true end end;return false end
function i.totalFreeCapacity(a)local b=0;for d,c in pairs(a or{})do
if c.state==l or c.state==m then b=b+j(c)end end;return b end
i._internal={scoreDomain=o,storagePreferenceMatches=k,freeCapacity=j,COMPUTE_BOUND_SOFT_MULTIPLIER=n}return i