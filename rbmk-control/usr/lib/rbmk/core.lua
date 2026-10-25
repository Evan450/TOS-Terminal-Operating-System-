local m,n,l="number","rodDepth","string"local k={}k.VERSION="1.0.0"k.FRAME_V=2
k.FRAME_VERSIONS={[1]=true,[2]=true}k.MAX_REASONS=8
k.PROFILES={["hbm-ntm"]={driver="ntm-console",componentTypes={"rbmk_console"}},["hbm-generic"]={componentTypes={"rbmk_console","rbmk_control","ntm_rbmk_console"},temp={"getTemp","getTemperature","getCoreTemp"},flux={"getFlux","getNeutronFlux"},rodDepth={"getRodDepth","getControlRodLevel","getRods"},steam={"getSteam","getSteamProduction"},water={"getWater","getWaterLevel"},fuel={"getFuel","getFuelLevel","getCoreFuel"},scram={"setAZ5","scram","az5","shutdown"},bulk={"getInfo","getStats","getData"},columns={"getColumnData","getColumns","getFluxData","getRodData"}}}
k.NTM={columns="getColumnData",scram="pressAZ5",pos="getRBMKPos",size=15,hullMax=1500,boilerWater=10000,boilerSteam=1000000}k.DEFAULT_GRID={w=15,h=15,shape="square"}
function k.mergeGrid(a)
local b={w=k.DEFAULT_GRID.w,h=k.DEFAULT_GRID.h,shape=k.DEFAULT_GRID.shape}if type(a)~="table"then return b end
local c,d=tonumber(a.w),tonumber(a.h)
if c and c>=1 and c<=64 and math.floor(c)==c then b.w=c end
if d and d>=1 and d<=64 and math.floor(d)==d then b.h=d end
if a.shape=="circle"or a.shape=="square"then b.shape=a.shape end;if type(a.mask)=="table"then b.mask=a.mask end;return b end
function k.bind(a,b)local c={}if type(b)=="table"then
for i,j in pairs(b)do if type(i)==l then c[i]=true elseif type(j)==l then
c[j]=true end end end
if
a.driver=="ntm-console"then local i=k.NTM;local u,j={},{}if c[i.columns]then for w,v in
ipairs({"temp","flux",n,"steam","water","fuel"})do u[v]=i.columns end else
j[#j+1]=i.columns end;if c[i.scram]then
u.scram=i.scram else j[#j+1]=i.scram end;return
{bound=u,missing=j,driver=a.driver,columns=
c[i.columns]and i.columns or nil,pos=c[i.pos]and i.pos or nil}end;local e,d={},{}
local h={"temp","flux",n,"steam","water","fuel","scram"}
for j,i in ipairs(h)do local v=a[i]or{}local u
for j,w in ipairs(v)do if c[w]then u=w;break end end;if u then e[i]=u else d[#d+1]=i end end;local f
for j,i in ipairs(a.bulk or{})do if c[i]then f=i;break end end;local g
for j,i in ipairs(a.columns or{})do if c[i]then g=i;break end end;return{bound=e,missing=d,bulk=f,columns=g}end
function k.bindingUsable(a,b)
if not a or not a.bound then return false,"no binding"end
if not(a.bound.temp or a.bulk)then return false,
"no temperature reading — refusing to supervise blind"end;if not(a.bound.scram or b)then
return false,"no SCRAM path (no console method and no redstone AZ-5)"end;return true end
function k.normalize(a)local b={}local function c(d)if type(d)==m then return d end
if type(d)==l then return tonumber(d)end;return nil end;a=a or{}
b.temp=c(a.temp)b.flux=c(a.flux)b.rodDepth=c(a.rodDepth)b.steam=c(a.steam)
b.water=c(a.water)b.fuel=c(a.fuel)b.melt=c(a.melt)b.unread=c(a.unread)return b end
k.DEFAULT_LIMITS={tempWarn=800,tempScram=1000,meltWarn=80,meltScram=90,fluxWarn=8000,fluxScram=10000,waterMin=10,staleAfter=5}
function k.evaluate(b,a,c)a=a or k.DEFAULT_LIMITS;local f={}local e="ok"
local function d(g,h)f[#f+1]=h;if g=="scram"then
e="scram"elseif e~="scram"then e="warn"end end;if c~=nil and a.staleAfter and c>a.staleAfter then
d("scram",string.format("telemetry stale (%.1fs > %.1fs)",c,a.staleAfter))end;b=b or{}
if
b.temp==nil then d("scram","no temperature reading")else
if a.tempScram and
b.temp>=a.tempScram then
d("scram",string.format("core %.0f >= scram limit %.0f",b.temp,a.tempScram))elseif a.tempWarn and b.temp>=a.tempWarn then
d("warn",string.format("core %.0f >= warn limit %.0f",b.temp,a.tempWarn))end end
if b.melt~=nil then
if a.meltScram and b.melt>=a.meltScram then
d("scram",string.format("fuel at %.0f%% of melting point >= scram limit %.0f%%",b.melt,a.meltScram))elseif a.meltWarn and b.melt>=a.meltWarn then
d("warn",string.format("fuel at %.0f%% of melting point >= warn limit %.0f%%",b.melt,a.meltWarn))end end;if b.unread~=nil and b.unread>0 then
d("warn",string.format("%d channel%s could not be read",b.unread,
b.unread==1 and""or"s"))end
if
b.flux~=nil then
if a.fluxScram and b.flux>=a.fluxScram then
d("scram",string.format("flux %.0f >= scram limit %.0f",b.flux,a.fluxScram))elseif a.fluxWarn and b.flux>=a.fluxWarn then
d("warn",string.format("flux %.0f >= warn limit %.0f",b.flux,a.fluxWarn))end end;if b.water~=nil and a.waterMin and b.water<a.waterMin then
d("scram",string.format("coolant %.0f%% < minimum %.0f%%",b.water,a.waterMin))end
return e,f end
function k.mergeLimits(a)local b={}for c,d in pairs(k.DEFAULT_LIMITS)do b[c]=d end;if
type(a)~="table"then return b end
for c,d in pairs(a)do if k.DEFAULT_LIMITS[c]~=nil then
local e=tonumber(d)if e and e>0 then b[c]=e end end end;return b end
k.KINDS={blank="_",fuel="F",control="C",moderator="M",reflector="R",absorber="A",coolant="W",boiler="B",outgasser="O",breeder="D",storage="S",heatex="H",cooler="K"}k.KIND_UNKNOWN="?"k.KIND_ABSENT="."
local o="0123456789abcdefghijklmnopqrstuvwxyz"local p=36*36*36-1
local function q(a)local b=""for c=1,3 do
b=o:sub((a%36)+1,(a%36)+1)..b;a=math.floor(a/36)end;return b end
local function r(a)local b=0;for c=1,#a do local d=o:find(a:sub(c,c),1,true)if not d then return nil end;b=
b*36+ (d-1)end;return b end
function k.normalizeColumns(a,b)local d={}if type(a)~="table"then return d end;b=b or{}
local e=b.w or 15;local function c(g)if type(g)==m then return g end
if type(g)==l then return tonumber(g)end;return nil end
local function f(g,h,i)if
type(g)~="table"then return end;local j=g.kind or g.type or g.name
d[#d+1]={x=
c(g.x)or h,y=c(g.y)or i,kind=(type(j)==l)and j:lower()or nil,temp=c(
g.temp or g.heat or g.temperature),flux=c(g.flux or g.power or
g.neutronFlux),steam=c(g.steam),water=c(g.water or g.coolant),rodDepth=c(
g.rodDepth or g.depth or g.level)}end
if type(a[1])=="table"and a[1][1]~=nil and
type(a[1][1])=="table"then
for g,h in ipairs(a)do for i,j in ipairs(h)do f(j,i,g)end end;return d end;for g,h in ipairs(a)do
f(h,((g-1)%e)+1,math.floor((g-1)/e)+1)end;return d end
local s={BLANK="blank",FUEL="fuel",FUEL_SIM="fuel",BREEDER="breeder",CONTROL="control",CONTROL_AUTO="control",BOILER="boiler",MODERATOR="moderator",ABSORBER="absorber",REFLECTOR="reflector",OUTGASSER="outgasser",STORAGE="storage",COOLER="cooler",HEATEX="heatex"}
function k.scanCore(a)local z=k.NTM.size;local function b(B)
if
type(B)==m and B==B and B>-math.huge and B<math.huge then return B end end;local j,c,u={},0,0;local d,e;local v;local w,f=0,0
local g,x,h=nil,0,0;local y,i=0,0
for B=0,z-1 do
for C=0,z-1 do local E,D=pcall(a,C,B)
if not E then c=c+1 elseif type(D)=="table"then u=u+1
local F={x=C+1,y=B+1,kind=s[tostring(D.type)]}local H=b(D.hullTemp)
if H then F.temp=H;if not d or H>d then d=H end end;local K,I=b(D.coreTemp),b(D.coreMaxTemp)
if K and I and I>0 then
F.melt=K/I*100;if not e or F.melt>e then e=F.melt end end;local L=b(D.enrichment)if L then y=y+L;i=i+1 end
local J=b(D.fluxQuantity)if J then F.flux=J;v=(v or 0)+J end;local G=b(D.level)
if G then
if G<0 then G=0 elseif G>1 then G=1 end;F.rodDepth=(1-G)*100;w=w+G;f=f+1 end
if F.kind=="boiler"then local M,N=b(D.water),b(D.steam)if M then F.water=
M/k.NTM.boilerWater*100
if not g or F.water<g then g=F.water end end;if N then
F.steam=N/k.NTM.boilerSteam*100;x=x+F.steam;h=h+1 end end;j[#j+1]=F end end end
local A={temp=d,melt=e,flux=v,water=g,rodDepth=(f>0)and((1-w/f)*100)or nil,steam=(h>0)and(x/h)or nil,fuel=(
i>0)and(y/i*100)or nil,unread=c}return A,j,{read=u,unread=c}end
function k.columnIndex(a)local b={}for e,d in ipairs(a or{})do
if d.x and d.y then b[d.x..","..d.y]=d end end;return b end
function k.packColumns(b,a,c)a=a or{}local g,h=a.w or 15,a.h or 15;local i=k.columnIndex(b)
local d,e={},{}
for j=1,h do
for u=1,g do local v=i[u..","..j]if not v then d[#d+1]=k.KIND_ABSENT else
d[#d+1]=(v.kind and
k.KINDS[v.kind])or k.KIND_UNKNOWN;e[#e+1]=v end end end;local f={"2",g..","..h,table.concat(d)}
for u,j in
ipairs(c or{})do local v={j.key}
for u,w in ipairs(e)do local x=w[j.field]
if type(x)~=m or x~=x then
v[#v+1]="---"else
local y=math.floor(x/ (j.step or 1)+0.5)if y<0 then y=0 elseif y>p then y=p end;v[#v+1]=q(y)end end;f[#f+1]=table.concat(v)end;return table.concat(f,";")end
function k.unpackColumns(a,b)if type(a)~=l then return nil,"not a string"end;local d={}for j in
(a..";"):gmatch("([^;]*);")do d[#d+1]=j end;if d[1]~="2"then
return nil,"unsupported column format"end
if type(d[2])~=l then return nil,"bad grid size"end;local c,e=d[2]:match("^(%d+),(%d+)$")
c,e=tonumber(c),tonumber(e)if
not(c and e)or c<1 or e<1 or c>64 or e>64 then return nil,"bad grid size"end
local h=d[3]or""if#h~=c*e then return nil,"kind map is the wrong length"end
local i={}for j,u in pairs(k.KINDS)do i[u]=j end;local g,f={},{}for j=1,e do
for u=1,c do local v=h:sub((j-1)*c+u,
(j-1)*c+u)if v~=k.KIND_ABSENT then
local w={x=u,y=j,kind=i[v]}g[#g+1]=w;f[#f+1]=w end end end
for j=4,#d do
local v=d[j]local w=v:sub(1,1)local x=v:sub(2)local u
for z,y in ipairs(b or{})do if y.key==w then u=y end end
if u then if#x~=#f*3 then
return nil,"value run for "..w.." is the wrong length"end
for y,z in ipairs(f)do
local A=x:sub((y-1)*3+1,y*3)if A~="---"then local B=r(A)
if B then z[u.field]=B* (u.step or 1)end end end end end;return g,{w=c,h=e}end
function k.frame(a,d,e,f,g,c,b)local h
if type(b)=="table"and#b>0 then h={}for j=1,math.min(#b,k.MAX_REASONS)do
h[j]=tostring(b[j]):sub(1,120)end end
return
{magic="RBMK",v=k.FRAME_V,name=g or"rbmk",seq=e or 0,uptime=f or 0,level=d or"ok",temp=a and a.temp,flux=a and a.flux,rodDepth=a and a.rodDepth,steam=a and a.steam,water=
a and a.water,fuel=a and a.fuel,melt=a and a.melt,cols=
(type(c)==l and#c>0)and c or nil,why=h}end
function k.validateFrame(a)if type(a)~="table"then return false,"not a table"end;if
a.magic~="RBMK"then return false,"bad magic"end;if not
k.FRAME_VERSIONS[a.v]then
return false,"unsupported version "..tostring(a.v)end;if type(a.seq)~=m then
return false,"no sequence"end;if a.cols~=nil and type(a.cols)~=l then return false,
"cols is not a packed string"end
if a.why~=nil then if
type(a.why)~="table"then return false,"why is not a list"end
for c,b in
ipairs(a.why)do if type(b)~=l then return false,"why holds a non-string"end end end
for c,b in ipairs({"cmd","command","setRod","rod","scram","exec"})do if
a[b]~=nil then
return false,"frame carries a control field ("..b..") — refused"end end;return true end;k.TELEMETRY_PORT=2200;k.WIRE_ARGS=9
local function t(a)local b={}
for d,c in
ipairs({"temp","flux",n,"steam","water","fuel","melt"})do if type(a[c])==m then
b[#b+1]=c.."="..string.format("%.4g",a[c])end end;return table.concat(b,",")end
function k.encodeWire(a)
return
{"RBMK",a.v or k.FRAME_V,tostring(a.name or"rbmk"),tonumber(a.seq)or 0,
tonumber(a.uptime)or 0,tostring(a.level or"ok"),t(a),tostring(a.cols or""),(
type(a.why)=="table")and table.concat(a.why,"|")or
""}end
function k.decodeWire(...)local b=table.pack(...)
if b.n<k.WIRE_ARGS then return nil,"short frame"end;if b[1]~="RBMK"then return nil,"not ours"end
local c={magic="RBMK",v=tonumber(b[2]),name=tostring(b[3]):sub(1,32),seq=tonumber(b[4]),uptime=
tonumber(b[5])or 0,level=tostring(b[6])}
if type(b[7])==l then
for a,f in b[7]:gmatch("([%a]+)=([%-%d%.eE+]+)")do
local g=tonumber(f)
if g and
(
a=="temp"or a=="flux"or a==n or a=="steam"or a==
"water"or a=="fuel"or a=="melt")then c[a]=g end end end;if type(b[8])==l and#b[8]>0 then c.cols=b[8]end
if
type(b[9])==l and#b[9]>0 then c.why={}for a in b[9]:gmatch("[^|]+")do
if
#c.why<k.MAX_REASONS then c.why[#c.why+1]=a:sub(1,120)end end end;local d,e=k.validateFrame(c)if not d then return nil,e end;return c end;function k.frameStale(b,a,c,d)if b==nil or a==nil then return true end
return(c-a)> (d or
k.DEFAULT_LIMITS.staleAfter)end;return k