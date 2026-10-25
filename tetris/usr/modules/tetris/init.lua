local R=require("component")local I=require("computer")local K;do
local a,b=pcall(require,"shell.keys")K=a and b or nil end
local function S(b,a)if K and K.is then
return K.is("quit",b,a)end;return b==17 or a==68 or a==1 end;local function ab()
if K and K.label then local a=K.label("quit")if a~=""then return a end end;return"^Q"end;local Q={}local H=10
local J=20;local L=2;local P=18;local N=H*L+2;local M=J+2;local T=N+1+P;local U=M+2
local O={{{{0,1},{1,1},{2,1},{3,1}},{{2,0},{2,1},{2,2},{2,3}},{{0,2},{1,2},{2,2},{3,2}},{{1,0},{1,1},{1,2},{1,3}}},{{{1,0},{2,0},{1,1},{2,1}},{{1,0},{2,0},{1,1},{2,1}},{{1,0},{2,0},{1,1},{2,1}},{{1,0},{2,0},{1,1},{2,1}}},{{{1,0},{0,1},{1,1},{2,1}},{{1,0},{1,1},{2,1},{1,2}},{{0,1},{1,1},{2,1},{1,2}},{{1,0},{0,1},{1,1},{1,2}}},{{{1,0},{2,0},{0,1},{1,1}},{{1,0},{1,1},{2,1},{2,2}},{{1,1},{2,1},{0,2},{1,2}},{{0,0},{0,1},{1,1},{1,2}}},{{{0,0},{1,0},{1,1},{2,1}},{{2,0},{1,1},{2,1},{1,2}},{{0,1},{1,1},{1,2},{2,2}},{{1,0},{0,1},{1,1},{0,2}}},{{{0,0},{0,1},{1,1},{2,1}},{{1,0},{2,0},{1,1},{1,2}},{{0,1},{1,1},{2,1},{2,2}},{{1,0},{1,1},{0,2},{1,2}}},{{{2,0},{0,1},{1,1},{2,1}},{{1,0},{1,1},{1,2},{2,2}},{{0,1},{1,1},{2,1},{0,2}},{{0,0},{1,0},{1,1},{1,2}}}}
local V={[3]={0x00FFFF,0xFFFF00,0xFF00FF,0x00FF00,0xFF0000,0x5555FF,0xFF8800},[2]={0x55FFFF,0xFFFF55,0xFF55FF,0x55FF55,0xFF5555,0x5555FF,0xFFAA00},[1]={0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFFF}}
local G={LEFT=203,RIGHT=205,UP=200,DOWN=208,SPACE=57,ESC=1,ENTER=28,Q=16,W=17,A=30,S=31,D=32,P=25,R=19,Z=44,X=45}local ac={{0,0},{-1,0},{1,0},{-2,0},{2,0},{0,-1}}
local W={100,300,500,800}
local function ad(a)return math.max(0.05,0.75- (a-1)*0.07)end
local function X(a,b,c)local d={}
for e=1,c do local f=true
for g=1,b do if a[e][g]==0 then f=false;break end end;if f then d[#d+1]=e end end;return d end
local function Y(b,c,a)if#a==0 then return end;local d={}for e,f in ipairs(a)do d[e]=f end
table.sort(d,function(e,f)return e>f end)for f,e in ipairs(d)do table.remove(b,e)end;for e=1,#a do local f={}
for g=1,c do f[g]=0 end;table.insert(b,1,f)end end;Q._test={fullRows=X,removeRows=Y}local ae=".tetris_hs"local af=5
local function Z()if type(fs)~="table"or not
fs.home then return nil end
local b,a=pcall(fs.home)if not b or type(a)~="string"then return nil end;if a=="/tmp"then
return nil end;return a.."/"..ae end
local function _()local b,a=pcall(require,"compat.serialization")if b and
type(a)=="table"then return a end;return nil end
local function aa(a)if not a or type(fs)~="table"then return{}end;if
not fs.exists(a)then return{}end;local b=fs.readFile(a)if not b then return{}end
local c=_()if not c then return{}end;local d=c.unserialize(b)return
type(d)=="table"and d or{}end
local function ag(a,b)if not a or type(fs)~="table"then return end;local c=_()if c then
fs.writeFile(a,c.serialize(b))end end
local function ah(a,b,c,d)local e=aa(a)
e[#e+1]={score=b,lines=c,level=d,t=math.floor(I.uptime())}
table.sort(e,function(f,g)return f.score>g.score end)while#e>af do e[#e]=nil end;ag(a,e)return e end
local function ai(a)local z=R.list("gpu")()if not z then a("No GPU found.",0xFF0000)
return end;local b=R.proxy(z)local o,p=b.getResolution()
if
not o or not p then a("Cannot detect screen size.",0xFF0000)return end;local am,s=pcall(b.getDepth)
if not am or type(s)~="number"then s=1 end;local e=s<=1 and 1 or(s<=4 and 2 or 3)
if
o<T or p<U then
a(string.format("Screen too small: need %dx%d, have %dx%d.",T,U,o,p),0xFF6600)
a("A Tier 2+ screen (80×24 minimum) is required.",0xAAAAAA)return end
local i=
(e==1)and{fg=0xFFFFFF,dim=0xFFFFFF,border=0xFFFFFF,title=0xFFFFFF,highlight=0xFFFFFF}or
{fg=0xFFFFFF,dim=0xAAAAAA,border=e==2 and 0x55FFFF or 0x00FFFF,title=e==2 and 0xFFFF55 or 0xFFFF00,highlight=
e==2 and 0x55FF55 or 0x00FF00}
local g=e>=2 and
{tl="┌",tr="┐",bl="└",br="┘",h="─",v="│",DTL="╔",DTR="╗",DBL="╚",DBR="╝",DH="═",DV="║"}or
{tl="+",tr="+",bl="+",br="+",h="-",v="|",DTL="+",DTR="+",DBL="+",DBR="+",DH="=",DV="|"}local c={}
function c.set(ay,az,aA,aw,ax)if aw then b.setForeground(aw)end;if ax then
b.setBackground(ax)end;b.set(ay,az,aA)end
function c.fill(ay,az,aA,aB,aC,aw,ax)if aw then b.setForeground(aw)end;if ax then
b.setBackground(ax)end;b.fill(ay,az,aA,aB,aC or" ")end
function c.clear()c.fill(1,1,o,p," ",i.fg,0x000000)end;function c.fit(aw,ax)aw=tostring(aw or"")if#aw>ax then
return aw:sub(1,ax-1).."…"end
return aw..string.rep(" ",ax-#aw)end
local function A(aw,ax,az,aB,aC,aA,ay)aA=aA or{}local aE=
aA.border or i.border;local aD=aA.bg or 0x000000
local aH=ay and g.DTL or g.tl;local aI=ay and g.DTR or g.tr;local aJ=ay and g.DBL or g.bl;local aK=ay and
g.DBR or g.br;local aF=ay and g.DH or g.h;local aG=
ay and g.DV or g.v;c.fill(aw,ax,az,aB," ",i.fg,aD)
c.set(aw,ax,aH..string.rep(aF,
az-2)..aI,aE,aD)
c.set(aw,ax+aB-1,aJ..string.rep(aF,az-2)..aK,aE,aD)for aL=ax+1,ax+aB-2 do c.set(aw,aL,aG,aE,aD)
c.set(aw+az-1,aL,aG,aE,aD)end;if aC then local aL=" "..aC.." "
c.set(aw+math.floor((az-
#aL)/2),ax,aL,aA.title or i.title,aD)end end;function c.box(aw,ax,ay,az,aA,aB)A(aw,ax,ay,az,aA,aB,false)end;function c.dbox(aw,ax,ay,az,aA,aB)
A(aw,ax,ay,az,aA,aB,true)end
local w={pull=function(aw)return I.pullSignal(aw)end}local q=V[e]or V[1]
local d={ghost=e>=3 and 0x1A1A3A or
(e==2 and 0x222255 or 0x555555),empty=0x000000,border=e>=2 and i.border or 0xFFFFFF,title=
e>=2 and i.title or 0xFFFFFF,text=i.fg,dim=i.dim,hi=e>=2 and i.highlight or 0xFFFFFF,score=
e==3 and 0xFFFF00 or(e==2 and 0xFFFF55 or 0xFFFFFF),danger=
e>=2 and 0xFF5555 or 0xFFFFFF}local an=N+1+P
local r=math.max(1,math.floor((o-an)/2)+1)
local k=math.max(1,math.floor((p-M)/2)+1)local B=r+1;local C=k+1;local D=r+N+1;local f=D+1;local h=k+1;local l=P-2;local ao=Z()local function E(aw,ax)
return B+aw*L,C+ax end
local function t(ax,ay,aw)local az,aA=E(ax,ay)
if e==1 then
b.setForeground(aw~=0 and 0xFFFFFF or 0x000000)b.setBackground(0x000000)
b.set(az,aA,aw~=0 and"[]"or"  ")else b.setBackground(aw)b.fill(az,aA,L,1," ")end end
local function ap(aw,ax)local ay,az=E(aw,ax)if e==1 then b.setForeground(d.dim)
b.setBackground(d.empty)b.set(ay,az,"::")else b.setBackground(d.ghost)
b.fill(ay,az,L,1," ")end end;local function F(aw)
for ax=1,J do for ay=1,H do t(ay-1,ax-1,aw[ax][ay])end end end
local function u(aw,ax,ay,az,aA)
for aC,aB in ipairs(O[aw][ax])do local aD,aE=ay+aB[1],az+
aB[2]if aE>=0 and aE<J and aD>=0 and aD<H then t(aD,aE,aA[aE+1][
aD+1])end end end
local function m(aw,ax,ay,az,aA,aB)
for aD,aC in ipairs(O[aw][ax])do local aE,aF=ay+aC[1],az+aC[2]
if
aF>=0 and aF<J and aE>=0 and aE<H then if aB then ap(aE,aF)else t(aE,aF,aA)end end end end
local function aq()c.clear()
c.box(r,k,N,M,"TETRIS",{border=d.border,bg=d.empty,title=d.title})
c.box(D,k,P,M,nil,{border=d.border,bg=d.empty})b.setBackground(d.empty)b.setForeground(d.score)
b.set(f,h,"SCORE")b.set(f,h+3,"LINES")b.set(f,h+6,"LEVEL")
b.set(f,h+9,"NEXT")local aw=h+14
if aw+5 <=k+M-1 then b.setForeground(d.dim)
b.set(f,aw,"LR/AD: move")b.set(f,aw+1,"U/W/X: rot")
b.set(f,aw+2,"Z: rot CCW")b.set(f,aw+3,"D/dn: soft")
b.set(f,aw+4,"SPC: drop")local ay=ab()local ax="P:pause "..ay..":quit"if#ax>l then
ax="P:pause ".. (
ay:match("^(.-) / ")or ay)..":quit"end
if#ax>l then ax="P:pause Q:quit"end;b.set(f,aw+5,ax)end end
local function x(ax,ay,az,aw)b.setBackground(d.empty)b.setForeground(d.text)
b.set(f,h+1,c.fit(tostring(ax),l))b.set(f,h+4,c.fit(tostring(ay),l))
b.set(f,h+7,c.fit(tostring(az),l))for aA=0,3 do b.setBackground(d.empty)
b.fill(f,h+10+aA,l,1," ")end
if aw then
for aB,aA in ipairs(O[aw][1])do
local aC=f+aA[1]*L;local aD=h+10+aA[2]if e==1 then b.setForeground(0xFFFFFF)
b.setBackground(d.empty)b.set(aC,aD,"[]")else b.setBackground(q[aw])
b.fill(aC,aD,L,1," ")end end end end;local function ar()local aw={}
for ax=1,J do aw[ax]={}for ay=1,H do aw[ax][ay]=0 end end;return aw end
local function v(aw,ax,ay,az,aA)
for aC,aB in
ipairs(O[ax][ay])do local aD,aE=az+aB[1],aA+aB[2]if aD<0 or aD>=H then return false end;if aE>=
J then return false end;if aE>=0 and aw[aE+1][aD+1]~=0 then
return false end end;return true end
local function y(aw,ax,ay,az,aA)local aB=aA;while v(aw,ax,ay,az,aB+1)do aB=aB+1 end;return aB end;local j,n={},0
local function al()
if n>=#j then j={1,2,3,4,5,6,7}for aw=#j,2,-1 do local ax=math.random(aw)
j[aw],j[ax]=j[ax],j[aw]end;n=0 end;n=n+1;return j[n]end
local function as()local aA=ar()local aC,aD,aE=0,0,1;j,n={},0
math.randomseed(
math.floor(I.uptime()*7331)%2147483647)local ax,az,ay,aw,aB;local aH=al()local function aL()local aP=14
local aQ=r+math.floor((N-aP)/2)local aR=k+math.floor(M/2)-1
c.dbox(aQ,aR,aP,3,"PAUSED",{border=d.title,bg=d.empty})end;local function aJ()
aq()F(aA)x(aC,aD,aE,aH)
if ax then
if aB~=aw then m(ax,az,ay,aB,nil,true)end;m(ax,az,ay,aw,q[ax],false)end end
local function aM(aP,aQ,aR,aS,aT)if aT~=aS then
u(aP,aQ,aR,aT,aA)end;u(aP,aQ,aR,aS,aA)if aB~=aw then
m(ax,az,ay,aB,nil,true)end;m(ax,az,ay,aw,q[ax],false)end
local function aN()ax=aH;aH=al()az=1;ay=math.floor(H/2)-2;aw=-2
aB=y(aA,ax,az,ay,aw)return v(aA,ax,az,ay,aw)end
local function aK()local aQ=q[ax]local aR=false
for aT,aS in ipairs(O[ax][az])do local aU,aV=ay+aS[1],aw+aS[2]if aV<
0 then aR=true elseif aV<J and aU>=0 and aU<H then aA[aV+1][aU+1]=aQ
t(aU,aV,aQ)end end;if aR then return false end;local aP=X(aA,H,J)
if#aP>0 then
for aU,aT in ipairs(aP)do
b.setBackground(0xFFFFFF)b.fill(B,C+aT-1,H*L,1," ")end;w.pull(0.07)Y(aA,H,aP)local aS=#aP
aC=aC+ (W[aS]or W[4])*aE;aD=aD+aS;aE=math.floor(aD/10)+1;F(aA)end;if not aN()then return false end;x(aC,aD,aE,aH)if aB~=aw then
m(ax,az,ay,aB,nil,true)end;m(ax,az,ay,aw,q[ax],false)return true end
local function aI(aP,aQ)if not v(aA,ax,az,ay+aP,aw+aQ)then return false end
local aR,aS,aT,aU,aV=ax,az,ay,aw,aB;ay=ay+aP;aw=aw+aQ;aB=y(aA,ax,az,ay,aw)aM(aR,aS,aT,aU,aV)
return true end
local function aO(aP)local aQ=((az-1+aP)%4)+1
for aS,aR in ipairs(ac)do
if
v(aA,ax,aQ,ay+aR[1],aw+aR[2])then local aT,aU,aV,aW,aX=ax,az,ay,aw,aB;az=aQ;ay=ay+aR[1]aw=aw+aR[2]
aB=y(aA,ax,az,ay,aw)aM(aT,aU,aV,aW,aX)return true end end;return false end;if not aN()then return 0,0,1,false end;aJ()local aF=I.uptime()local aG=false
while true do
local aR=ad(aE)local aQ=I.uptime()
local aT=aG and 1.0 or math.max(0,aR- (aQ-aF))local aS,aV,aU,aP=w.pull(aT)
if aS=="tos_focus"then aG=true;aJ()aL()aF=I.uptime()elseif aS==
"key_down"then
if aP==G.Q or S(aU,aP)then return aC,aD,aE,true elseif aP==G.P then aG=not aG
if aG then aL()else aJ()end elseif not aG then
if aP==G.LEFT or aP==G.A then aI(-1,0)elseif aP==G.RIGHT or aP==G.D then
aI(1,0)elseif aP==G.UP or aP==G.W or aP==G.X then aO(1)elseif aP==G.Z then aO(-1)elseif
aP==G.DOWN or aP==G.S then
if aI(0,1)then aC=aC+1;x(aC,aD,aE,aH)aF=I.uptime()else if not aK()then return aC,
aD,aE,false end;aF=I.uptime()end elseif aP==G.SPACE then if aB~=aw then u(ax,az,ay,aB,aA)end
u(ax,az,ay,aw,aA)aC=aC+2*math.max(0,aB-aw)aw=aB;if not aK()then
return aC,aD,aE,false end;aF=I.uptime()end end end;if not aG then aQ=I.uptime()
if aQ-aF>=aR then aF=aQ;if not aI(0,1)then
if not aK()then return aC,aD,aE,false end end end end end end
local function at(ax,ay,az,aw)local aD=N;local aE=10;local aC=aD-4;local aA=r
local aB=k+math.floor((M-aE)/2)
c.dbox(aA,aB,aD,aE,"GAME OVER",{border=d.danger,bg=d.empty})b.setBackground(d.empty)b.setForeground(d.text)
b.set(aA+2,
aB+2,c.fit(string.format("Score: %d",ax),aC))
b.set(aA+2,aB+3,c.fit(string.format("Ln: %d  Lv: %d",ay,az),aC))
if aw and#aw>0 then b.setForeground(d.score)
b.set(aA+2,aB+4,c.fit(string.format("Best: %d",aw[1].score),aC))local aF=ax>0 and ax==aw[1].score and
(#aw==1 or ax>aw[2].score)if aF then
b.setForeground(d.hi)
b.set(aA+2,aB+5,c.fit("* NEW HIGH SCORE! *",aC))end end;b.setForeground(d.dim)
b.set(aA+2,aB+7,c.fit("[R] Play Again",aC))b.set(aA+2,aB+8,c.fit("[Q] Quit",aC))
while true do
local aG,aI,aH,aF=w.pull(120)
if aG=="key_down"then if aF==G.R or aF==G.ENTER then return true end;if
aF==G.Q or S(aH,aF)then return false end elseif not aG then return false end end end
local au,av=pcall(function()local aw=true
while aw do local ax,ay,az,aA=as()if aA then aw=false else local aB=ah(ao,ax,ay,az)
aw=at(ax,ay,az,aB)end end end)c.clear()if not au then
a("Tetris crashed: "..tostring(av),0xFF0000)end end
local function aj(a)local b=Z()if not b then
a("Not logged in — no personal score file to read.",0xFF6600)return end
local c=b:match("^/home/([^/]+)/")or
b:match("^/([^/]+)/")or"?"local d=aa(b)
if#d==0 then
a("No high scores yet for "..c..".",0xAAAAAA)a("Play your first game:  tetris",0x555555)return end
a(string.format("  High scores — %s",c),0xFFFF00)a(string.rep("─",42),0x444444)
a(string.format("  %-3s  %-12s  %-8s  %s","#","SCORE","LINES","LEVEL"),0xAAAAAA)
for e,f in ipairs(d)do local g=(e==1)and" ★"or"  "
a(string.format("  %-3d  %-12d  %-8d  %d%s",e,f.score,f.lines,f.level,g),
e==1 and 0xFFFF00 or 0xFFFFFF)end end
local function ak(b,a)local c=b[1]
if c==nil then ai(a)elseif c=="scores"or c=="hs"then aj(a)elseif
c=="help"or c=="--help"or c=="-h"then a("=== Tetris ===",0xFFFF00)
a("",0xFFFFFF)
a("  tetris           Launch the game (requires T2+ screen, 80×24+)",0xFFFFFF)
a("  tetris scores    Show your personal high-score table",0xFFFFFF)a("",0xFFFFFF)a(" In-game controls:",0xAAAAAA)
a("  ← → / A D       Move left / right",0xFFFFFF)a("  ↑ / W / X       Rotate clockwise",0xFFFFFF)
a("  Z               Rotate counter-clockwise",0xFFFFFF)
a("  ↓ / S           Soft drop  (+1 pt per row)",0xFFFFFF)
a("  Space           Hard drop  (+2 pts per row)",0xFFFFFF)a("  P               Pause / unpause",0xFFFFFF)
a("  Q / Esc         Quit to shell",0xFFFFFF)a("",0xFFFFFF)a(" Scoring:",0xAAAAAA)
a("  1 line  = 100 × level    2 lines = 300 × level",0xFFFFFF)
a("  3 lines = 500 × level    4 lines = 800 × level  (Tetris!)",0xFFFFFF)
a("  Level increases every 10 lines; speed increases with level.",0xAAAAAA)a("",0xFFFFFF)
a(" High scores are stored in ~/.tetris_hs (one file per user).",0x555555)else
a("Unknown subcommand: "..tostring(c),0xFF6600)a("Usage: tetris [scores | help]",0xAAAAAA)end end;Q.commands={tetris=ak}return Q