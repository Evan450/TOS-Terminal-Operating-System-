local A="unknown"local t=require("computer")local p={}local r={}local q={}local s=1;local u,v=0,0;local w,x=nil,
nil
local function C(a,b)u=u+1;v=v+1;w=tostring(b)x=a and a.source or A end;function p.timerErrors()return v,w,x end;local y=nil
local function z()if not y then
local a,b=pcall(require,"kernel.process")if a then y=b end end;return y end
function p.on(a,b,c)if not r[a]then r[a]={}end;local e=nil;local f=nil;local d=z()if d and d.current then
local h=d.current()
if h then e=h.pid;f=d.genOf and d.genOf(h.pid)or nil end end
local g={callback=b,source=c or A,id=s,regPid=e,regGen=f}s=s+1;r[a][#r[a]+1]=g;return g.id end;function p.once(a,b,c)local d
d=p.on(a,function(...)p.off(a,d)return b(...)end,c)return d end
function p.off(a,b)
if not r[a]then return end;for c,d in ipairs(r[a])do
if d.id==b then table.remove(r[a],c)return true end end;return false end;function p.removeSource(a)
for c,b in pairs(r)do for d=#b,1,-1 do
if b[d].source==a then table.remove(b,d)end end end end
function p.purgeOwner(a)if a==nil then
return 0 end;local b=0;for d,c in pairs(r)do for e=#c,1,-1 do if c[e].regPid==a then table.remove(c,e)
b=b+1 end end
if#c==0 then r[d]=nil end end
for c=#q,1,-1 do if
q[c].regPid==a then table.remove(q,c)b=b+1 end end;return b end
local function B()local a=z()
if a and a.current then local b=a.current()if b then
local c=a.genOf and a.genOf(b.pid)or nil;return b.pid,c end end;return nil,nil end
function p.timer(a,b,c)local d=s;s=s+1;local e,f=B()
q[#q+1]={deadline=t.uptime()+a,callback=b,source=c or A,id=d,interval=nil,regPid=e,regGen=f}return d end
function p.interval(a,b,c)local d=s;s=s+1;local e,f=B()
q[#q+1]={deadline=t.uptime()+a,callback=b,source=c or A,id=d,interval=a,regPid=e,regGen=f}return d end
function p.cancelTimer(a)for b,c in ipairs(q)do
if c.id==a then table.remove(q,b)return true end end;return false end
function p.pull(a)a=a or 0.5
if u>0 then
local h=package.loaded and package.loaded["kernel.log"]if h and h.warn then
pcall(h.warn,"event","timer callback errors: +"..u..
" (total "..v.."), last ["..tostring(x)..
"]: "..tostring(w))u=0 end end;local f=t.uptime()local e=f+a;local b=z()local c=nil;for h=1,#q do local i=q[h]
if f>=i.deadline then c=c or{}c[
#c+1]=i elseif i.deadline<e then e=i.deadline end end
if c then
for i,h in ipairs(c)do local j=nil;for k=1,#q do if
q[k]==h then j=k;break end end
if j then
local k=
h.regPid~=nil and h.regGen~=nil and b and b.genOf and
(b.genOf(h.regPid)~=h.regGen)
if k or not h.interval then table.remove(q,j)else
h.deadline=f+h.interval;if h.deadline<e then e=h.deadline end end
if not k then local l,m
if b and b.withListener and h.regPid then
l,m=pcall(b.withListener,h.regPid,h.callback)else l,m=pcall(h.callback)end;if not l then C(h,m)end end end end end
local g=math.max(0,math.min(a,e-t.uptime()))local d=table.pack(t.pullSignal(g))
if d[1]then local h=d[1]
local function i(j,...)
if
b and b.withListener and j.regPid then
if j.regGen~=nil and b.genOf and
b.genOf(j.regPid)~=j.regGen then return false end;local k=pcall(b.withListener,j.regPid,j.callback,...)return k end;return pcall(j.callback,...)end;if r[h]then local j={table.unpack(r[h])}for l,k in ipairs(j)do
i(k,table.unpack(d,1,d.n))end end end;return table.unpack(d,1,d.n)end
function p.pullFiltered(a,b)local c=t.uptime()+ (b or math.huge)
while true do local e=c-
t.uptime()if e<=0 then return nil end
local d=table.pack(p.pull(e))
if
d[1]and(not a or a(table.unpack(d,1,d.n)))then return table.unpack(d,1,d.n)end end end
local D={key_down=true,key_up=true,clipboard=true,touch=true,drag=true,drop=true,scroll=true,walk=true,modem_message=true,component_added=true,component_removed=true,component_available=true,component_unavailable=true,screen_resized=true,interrupted=true}
function p.reservedSignal(a)if type(a)~="string"then return false end;return D[a]==true or a:sub(1,4)==
"tos_"end;function p.push(...)t.pushSignal(...)end;return p