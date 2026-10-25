local G=require("rbmk.core")local H=require("rbmk-cmd")
local _=require("rbmk.skala")
local function Q(...)for a=1,select("#",...)do local c,b=pcall(require,(select(a,...)))if
c and b then return b end end end;local M=Q("component")local J=Q("computer")
local K=Q("kernel.event","event")local D
do local a=Q("kernel.log","log")if a and a.info then D=a else
D={info=function()end,warn=function()end,error=function()end}end end;local E="rbmk"local N={}local I=false;local R,S,L,C,V;local W,X,Y;local O,T,P,U=0,nil,false,nil;local F,Z
local function aa(a)
if not F then
F,Z={},tonumber(C and
C.telemetryPort)or G.TELEMETRY_PORT;if M and M.list then
for c in M.list("modem")do local e,d=pcall(M.proxy,c)if e and d and d.broadcast then F[#
F+1]=d end end end
if#F==0 then
D.warn(E,"no modem: supervising locally, but no display can see this")else
D.info(E,string.format("telemetry on port %d (%d modem%s)",Z,#F,#F==1 and""or"s"))end end;if#F==0 then return end;local b=G.encodeWire(a)for d,c in ipairs(F)do
pcall(c.broadcast,Z,b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9])end end
local function ab(a)if P then return end;local b,c=H.scram(S,L,C)P=true;if b then
D.error(E,"SCRAM fired ("..tostring(c).."): "..
tostring(a))else
D.error(E,"SCRAM REQUESTED BUT NO PATH WORKED: "..tostring(a))end
if
J and J.beep then pcall(J.beep,1400,0.2)pcall(J.beep,1000,0.4)end end
local function ac()if not I then return end;local a=J and J.uptime()or 0
local c,f=H.read(S,L)local d;if c.temp~=nil then T=a;d=0 else
d=T and(a-T)or(V.staleAfter+1)end;local b,e=G.evaluate(c,V,d)O=O+1
if a>=
(X or 0)then
X=a+ (tonumber(C.mapInterval)or 1)local g=f or H.readColumns(S,L,W)Y=(#g>0)and
G.packColumns(g,W,_.PARAMS)or nil end;aa(G.frame(c,b,O,a,C.name,Y,e))
if b=="scram"then
ab(table.concat(e,"; "))elseif b=="warn"then if U~="warn"then
D.warn(E,"warning: "..table.concat(e,"; "))end elseif P and b=="ok"then
D.info(E,"conditions normal (SCRAM latch still set — restart to clear)")end;U=b end
function N.start()if I then return true end;C=H.loadCfg()
V=G.mergeLimits(C.limits)W=G.mergeGrid(C.grid)F,X,Y=nil,0,nil;local d=H.activeProfile(C)
local c=H.candidates(d)
if#c==0 then
D.error(E,"no RBMK console component found — run `rbmk survey`")return false,"no console found"end;local a=c[1]if C.address then
for k,j in ipairs(c)do if
tostring(j.address):sub(1,#C.address)==C.address then a=j end end end
local g=H.methodsOf(a.address)L=G.bind(d,g)
local h,e=G.bindingUsable(L,C.az5RedstoneSide~=nil)if not h then
D.error(E,"refusing to start: "..
tostring(e).." (run `rbmk survey` and fix /etc/rbmk.cfg)")return false,e end
local i,f=pcall(M.proxy,a.address)if not i or not f then D.error(E,"cannot open the console proxy")return
false,"proxy failed"end;S=f;O,P,T,U=0,false,
nil,nil;local b=tonumber(C.pollInterval)or 1;if
b<0.25 then b=0.25 end
R=K and K.interval and K.interval(b,ac,"rbmk.poll")I=true
D.info(E,string.format("supervising %s (%s) every %.2fs",tostring(a.type),tostring(a.address):sub(1,8),b))return true end
function N.stop()if not I then return true end;if R and K and K.cancelTimer then
pcall(K.cancelTimer,R)end;R,I=nil,false
D.info(E,"stopped (reactor is NO LONGER SUPERVISED)")return true end;function N.running()return I end;function N.state()
return{running=I,seq=O,scrammed=P,level=U,binding=L}end;return N