local s=require("component")local p=require("computer")
local q=require("snake.logic")
local function u(a,b,c)local l=s.list and s.list("gpu")()if not l then
a("No GPU found.",0xFF0000)return nil end;local m,f=pcall(s.proxy,l)if not m or not f then
a("Cannot open the GPU.",0xFF0000)return nil end;local i,j=f.getResolution()
if not i or not
j then a("Cannot detect screen size.",0xFF0000)return nil end;if i<b or j<c then
a(string.format("Screen too small: need %dx%d, have %dx%d.",b,c,i,j),0xFF6600)return nil end
local n,k=pcall(f.getDepth)
local h=(n and type(k)=="number")and(k<=1 and 1 or
(k<=4 and 2 or 3))or 1
local d=(h==1)and
{fg=0xFFFFFF,dim=0xFFFFFF,border=0xFFFFFF,title=0xFFFFFF,hi=0xFFFFFF,warn=0xFFFFFF,bg=0x000000}or
{fg=0xFFFFFF,dim=0xAAAAAA,bg=0x000000,border=
h==2 and 0x55FFFF or 0x00FFFF,title=h==2 and 0xFFFF55 or 0xFFFF00,hi=h==2 and 0x55FF55 or 0x00FF00,warn=
h==2 and 0xFF5555 or 0xFF4040}
local g=
(h>=2)and{tl="┌",tr="┐",bl="└",br="┘",h="─",v="│"}or{tl="+",tr="+",bl="+",br="+",h="-",v="|"}local e={W=i,H=j,tier=h,T=d,BOX=g,gpu=f}function e.set(F,G,H,o,E)if o then
pcall(f.setForeground,o)end;if E then pcall(f.setBackground,E)end
pcall(f.set,F,G,H)end
function e.fill(F,G,H,I,J,o,E)if o then
pcall(f.setForeground,o)end;if E then pcall(f.setBackground,E)end;pcall(f.fill,F,G,H,I,
J or" ")end;function e.clear()e.fill(1,1,i,j," ",d.fg,d.bg)end
function e.box(o,E,F,H,G)
e.set(o,E,
g.tl..string.rep(g.h,F-2)..g.tr,d.border,d.bg)for I=1,H-2 do e.set(o,E+I,g.v,d.border,d.bg)
e.set(o+F-1,E+I,g.v,d.border,d.bg)end
e.set(o,E+H-1,g.bl..string.rep(g.h,F-2)..
g.br,d.border,d.bg)if G then
e.set(o+math.floor((F-#G-2)/2),E," "..G.." ",d.title,d.bg)end end;function e.centre(E,o,F)
e.set(math.max(1,math.floor((i-#o)/2)+1),E,o,F or d.fg,d.bg)end;return e end;local t=5;local v=".snake_hs"
local function w()
if not(fs and fs.home)then return nil end;local b,a=pcall(fs.home)
if not b or type(a)~="string"then return nil end;if a=="/tmp"then return nil end;return a.."/"..v end
local function x(a)if
not(fs and fs.exists and fs.exists(a))then return{}end;local d,c=pcall(fs.readFile,a)if not d or
type(c)~="string"then return{}end;local b={}
for e in
(c.."\n"):gmatch("(.-)\n")do local f,g=e:match("^(%d+)%s+(.*)$")if f then
b[#b+1]={score=tonumber(f),when=g}end end;return b end
local function y(a,b)if not(fs and fs.writeFile)then return end;local c={}
for e,d in
ipairs(b)do if e>t then break end;c[#c+1]=tostring(d.score)..
" "..tostring(d.when or"")end;pcall(fs.writeFile,a,table.concat(c,"\n"))end
local function z(a,b)local c=x(a)
c[#c+1]={score=b,when=string.format("up %.0fs",p.uptime())}
table.sort(c,function(d,e)
return(d.score or 0)> (e.score or 0)end)while#c>t do c[#c]=nil end;y(a,c)return c end;local r
do local a,b=pcall(require,"shell.keys")r=a and b or nil end;local function A(b,a)if r and r.is then return r.is("quit",b,a)end;return
b==17 or a==68 or a==1 end;local function B()
if
r and r.label then local a=r.label("quit")if a~=""then return a end end;return"^Q"end
local function C(b,a)
if a==200 then return"up"elseif
a==208 then return"down"elseif a==203 then return"left"elseif a==205 then return"right"elseif a==28 then return"enter"elseif A(b,a)then return"esc"end;if type(b)=="number"and b>0 then
return string.char(b):lower()end;return nil end
local function D(b,a)a=a or print;local h,g=40,16;local d=u(a,h+4,g+6)if not d then return end;local e=d.T
math.randomseed(math.floor((
p.uptime()*1000)%2147483647))local I=function(K)return math.random(K)end;local n=math.floor(
(d.W-h)/2)local i=3;local c=q.newSnake(h,g)
q.placeFood(c,I)local o=(d.tier>=2)and"█"or"@"local E=
(d.tier>=2)and"▒"or"o"
local F=(d.tier>=2)and"♦"or"*"
local function G()d.clear()d.box(n-1,i-1,h+2,g+2,"Snake")
d.centre(1,"SNAKE",e.title)
d.set(2,d.H,"Arrows/WASD move · P pause · "..B().." quit",e.dim,e.bg)end;local function m()local K=string.format(" Score %d ",c.score)
d.set(d.W-#K-1,1,K,e.hi,e.bg)end;local function f(K,L,M,N)
d.set(n+K-1,i+L-1,M,N,e.bg)end;G()m()
for K,L in ipairs(c.body)do f(L.x,L.y,K==1 and o or E,
K==1 and e.hi or e.fg)end
if c.food then f(c.food.x,c.food.y,F,e.warn)end;local j=false;local k=p.uptime()+q.snakeDelay(0)
while true do local L=math.max(0,k-
p.uptime())local K,O,M,N=p.pullSignal(L)
if
K=="tos_focus"then j=true;G()m()
d.centre(i+math.floor(g/2)," PAUSED ",e.warn)k=p.uptime()+q.snakeDelay(0)elseif K=="key_down"then local P=C(M,N)
if
P=="q"or P=="esc"then d.clear()return elseif P=="p"then j=not j
if j then
d.centre(i+math.floor(g/2)," PAUSED ",e.warn)else G()m()for Q,R in ipairs(c.body)do
f(R.x,R.y,Q==1 and o or E,Q==1 and e.hi or e.fg)end;if c.food then
f(c.food.x,c.food.y,F,e.warn)end end;k=p.uptime()+q.snakeDelay(c.score)elseif
P=="up"or P=="w"then q.turn(c,"up")elseif P=="down"or P=="s"then q.turn(c,"down")elseif P=="left"or
P=="a"then q.turn(c,"left")elseif P=="right"or P=="d"then
q.turn(c,"right")end end
if not j and p.uptime()>=k then local P=c.body[#c.body]
local Q=c.body[1]q.step(c,I)if not c.alive then break end;if not c.grew and P then
f(P.x,P.y," ",e.fg)end;if Q then f(Q.x,Q.y,E,e.fg)end
local R=c.body[1]f(R.x,R.y,o,e.hi)
if c.grew then m()if c.food then
f(c.food.x,c.food.y,F,e.warn)end;pcall(p.beep,800,0.05)end;k=p.uptime()+q.snakeDelay(c.score)end end;pcall(p.beep,200,0.4)local J=w()local H=J and z(J,c.score)or
{{score=c.score}}
local l=i+math.floor(g/2)-3;d.box(n+4,l,h-8,8,"Game Over")
d.centre(l+2,"Score: "..c.score,e.hi)d.centre(l+3,"Best scores",e.dim)for K=1,math.min(3,#H)do
d.centre(l+3+K,string.format("%d. %d",K,H[K].score),(
H[K].score==c.score)and e.hi or e.fg)end
d.centre(l+7,"Press any key",e.dim)
while true do local K=p.pullSignal()if K=="key_down"then break end end;d.clear()end;return{commands={snake=D}}