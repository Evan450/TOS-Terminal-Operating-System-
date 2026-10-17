local o=require("component")local n=require("computer")local l={}
local m={}
local function r(a)local c,b=pcall(a.maxResolution)if not c or not b then return 1 end;if
b>=160 then return 3 elseif b>=80 then return 2 else return 1 end end
local function s()local a={}for c in o.list("computer")do a[#a+1]=c end
local b=n.totalMemory()if b>=786432 then return 3 elseif b>=262144 then return 2 else return 1 end end
local p={[192]={name="T1",num=1},[256]={name="T1.5",num=1},[384]={name="T2",num=2},[512]={name="T2.5",num=2},[768]={name="T3",num=3},[1024]={name="T3.5",num=3}}
function l.stickTier(a)
local b=p[math.floor(tonumber(a)or-1)]return b and b.name or nil end
local t={["500"]={192,256},["1000"]={384,512},["1500"]={768,1024}}
local function q(a)
if a==nil then
local c,d=pcall(function()return n.getDeviceInfo()end)if not c then return nil end;a=d end;if type(a)~="table"then return nil end;local b={}
for d,c in pairs(a)do if
type(c)=="table"and
c.class=="memory"and c.description=="Memory bank"then b[#b+1]=c end end;return b end;function l.ramBanks(a)local b=q(a)return b and#b or nil end
function l.ramSticks(a)
local c=q(a)if not c or#c==0 then return nil end;local b={}for j,k in ipairs(c)do
b[j]=t[tostring(k.clock)]if not b[j]then return nil end end
local h,e=pcall(function()return
n.totalMemory()end)
local f=h and tonumber(e)and tonumber(e)/1024;if not f then return nil end;local g,d
for i=0,2^#b-1 do local j,k,w={},0,i;for x,y in ipairs(b)do j[x]=y[w%2+1]k=
k+j[x]w=math.floor(w/2)end
if math.abs(
k-f)<1 then
table.sort(j,function(y,z)return y>z end)local x=table.concat(j,",")if d and d~=x then return nil end;g,d=j,x end end;return g end
function l.ramSummary(b,a,c)if b==nil then b=l.ramSticks()end
if
type(b)=="table"and#b>0 then local f={}for j=1,#b do f[j]=b[j]end
table.sort(f,function(i,j)return i>j end)local g,e,d={},nil,0;local function h()if e then
g[#g+1]=(d>1 and(d.."x ")or"")..e end end
for j,i in ipairs(f)do local k=
l.stickTier(i)or(i.."K")if k==e then d=d+1 else h()e,d=k,1 end end;h()return table.concat(g," + ")end
if a==nil then
local e,d=pcall(function()return n.totalMemory()end)if e and tonumber(d)then
a=math.floor(tonumber(d)/1024)end end;a=math.floor(tonumber(a)or 0)c=tonumber(c)or
l.ramBanks()or 0;if a<=0 then return"?"end;if c==1 then return
l.stickTier(a)or(a.."K")end;if c>1 then return c..
" sticks, "..a.."K"end;return a.."K"end
local function u()local a=l.ramSticks()
if a and#a>0 then local c=1;for e,d in ipairs(a)do local f=p[d]
if f and f.num>c then c=f.num end end;return c end;local b=n.totalMemory()
if b>=786432 then return 3 elseif b>=262144 then return 2 else return 1 end end
local function v(a)local c,b=pcall(a.spaceTotal)if not c or not b then return 1 end;if
b>=4194304 then return 3 elseif b>=2097152 then return 2 else return 1 end end
function l.scan()m={}
for b,a in o.list()do local c={address=b,type=a,proxy=nil,tier=nil,label=nil}
if
a=="gpu"then c.proxy=o.proxy(b)c.tier=r(c.proxy)elseif a=="filesystem"then
c.proxy=o.proxy(b)c.tier=v(c.proxy)local d,e=pcall(c.proxy.getLabel)c.label=
(d and e)or"Unnamed"local f,g=pcall(c.proxy.spaceTotal)c.spaceTotal=(
f and g)or 0;local h,i=pcall(c.proxy.spaceUsed)c.spaceUsed=(
h and i)or 0 elseif a=="drive"then c.proxy=o.proxy(b)
c.unmanaged=true;local d,e=pcall(c.proxy.getCapacity)
c.capacity=(d and e)or 0;local f,g=pcall(c.proxy.getSectorSize)
c.sectorSize=(f and g)or 0;local h,i=pcall(c.proxy.getPlatterCount)
c.platters=(h and i)or 1 end;if not m[a]then m[a]={}end;m[a][#m[a]+1]=c end;m["_cpu_tier"]=s()m["_mem_tier"]=u()end;function l.list(a)return m[a]or{}end
function l.primary(a)local b=m[a]if b and#b>0 then local c=b[1]
if
not c.proxy then local d,e=pcall(o.proxy,c.address)if d then c.proxy=e end end;return c end;return nil end
function l.proxy(a)local b=l.primary(a)return b and b.proxy end;function l.count(a)local b=m[a]return b and#b or 0 end;function l.has(a)return
l.count(a)>0 end
function l.systemInfo()local a=l.primary("gpu")
return
{cpuTier=
m["_cpu_tier"]or 1,memTier=m["_mem_tier"]or 1,memTierName=l.ramSummary(),gpuTier=a and a.tier or 0,totalMem=n.totalMemory(),freeMem=n.freeMemory(),components=l.componentCount(),canEncrypt=
n.totalMemory()>=262144,canMultiUser=n.totalMemory()>=196608,canNetwork=l.has("modem"),hasTunnel=l.has("tunnel"),hasWireless=false,hasScreen=l.has("screen"),hasKeyboard=l.has("keyboard"),isHeadless=
not l.has("gpu")and not l.has("screen")}end
function l.freeMemory(a)local function c()return
(n.freeMemory and n.freeMemory())or 0 end;local b=c()if a and b>=a then
return b,false end;if type(collectgarbage)=="function"then
pcall(collectgarbage,"collect")end;local d=c()
return(d>b)and d or b,true end;function l.componentCount()local a=0
for c,b in pairs(m)do if type(b)=="table"then a=a+#b end end;return a end
function l.checkWireless()
local a=l.primary("modem")if a and a.proxy then
local b,c=pcall(function()return a.proxy.isWireless()end)if b then return c end end
return false end
function l.handleComponentAdded(b,a)if not m[a]then m[a]={}end;for e,d in ipairs(m[a])do
if d.address==b then return end end
local c={address=b,type=a,proxy=nil,tier=nil}m[a][#m[a]+1]=c end;function l.handleComponentRemoved(b,a)
if m[a]then for c,d in ipairs(m[a])do
if d.address==b then table.remove(m[a],c)break end end end end
function l.report()
local a={}a[#a+1]="=== TOS Hardware Report ==="local b=l.systemInfo()
a[#a+1]=string.format("CPU Tier: %d | GPU Tier: %d | RAM: %s",b.cpuTier,b.gpuTier,
b.memTierName or("Tier "..b.memTier))
a[#a+1]=string.format("Memory: %dKB / %dKB",math.floor(b.freeMem/1024),math.floor(b.totalMem/
1024))
a[#a+1]=string.format("Total components: %d",b.components)a[#a+1]=""
for d,c in pairs(m)do
if type(c)=="table"and#c>0 then a[#a+1]=string.format("  %-16s x%d",d,
#c)
for f,e in ipairs(c)do local g=""if e.tier then
g=g.." T"..e.tier end
if e.label then g=g..' "'..e.label..'"'end
a[#a+1]=string.format("    %s%s",e.address:sub(1,8).."...",g)end end end;return table.concat(a,"\n")end;return l