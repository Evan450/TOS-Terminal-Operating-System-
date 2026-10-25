local r,s="Your move (X)","key_down"local p=require("component")
local n=require("computer")local m=require("ttt.logic")
local function t(a,b,c)
local k=p.list and p.list("gpu")()
if not k then a("No GPU found.",0xFF0000)return nil end;local l,d=pcall(p.proxy,k)if not l or not d then
a("Cannot open the GPU.",0xFF0000)return nil end;local g,h=d.getResolution()
if not g or not
h then a("Cannot detect screen size.",0xFF0000)return nil end;if g<b or h<c then
a(string.format("Screen too small: need %dx%d, have %dx%d.",b,c,g,h),0xFF6600)return nil end
local y,j=pcall(d.getDepth)
local e=(y and type(j)=="number")and(j<=1 and 1 or
(j<=4 and 2 or 3))or 1
local i=(e==1)and
{fg=0xFFFFFF,dim=0xFFFFFF,border=0xFFFFFF,title=0xFFFFFF,hi=0xFFFFFF,warn=0xFFFFFF,bg=0x000000}or
{fg=0xFFFFFF,dim=0xAAAAAA,bg=0x000000,border=
e==2 and 0x55FFFF or 0x00FFFF,title=e==2 and 0xFFFF55 or 0xFFFF00,hi=e==2 and 0x55FF55 or 0x00FF00,warn=
e==2 and 0xFF5555 or 0xFF4040}
local z=
(e>=2)and{tl="┌",tr="┐",bl="└",br="┘",h="─",v="│"}or{tl="+",tr="+",bl="+",br="+",h="-",v="|"}local f={W=g,H=h,tier=e,T=i,BOX=z,gpu=d}function f.set(C,D,E,A,B)if A then
pcall(d.setForeground,A)end;if B then pcall(d.setBackground,B)end
pcall(d.set,C,D,E)end
function f.fill(C,D,E,F,G,A,B)if A then
pcall(d.setForeground,A)end;if B then pcall(d.setBackground,B)end;pcall(d.fill,C,D,E,F,
G or" ")end;function f.clear()f.fill(1,1,g,h," ",i.fg,i.bg)end;function f.centre(B,A,C)
f.set(math.max(1,math.floor((
g-#A)/2)+1),B,A,C or i.fg,i.bg)end;return f end;local o
do local a,b=pcall(require,"shell.keys")o=a and b or nil end;local function u(b,a)if o and o.is then return o.is("quit",b,a)end;return
b==17 or a==68 or a==1 end;local function q()
if
o and o.label then local a=o.label("quit")if a~=""then return a end end;return"^Q"end
local function v(b,a)
if a==200 then return"up"elseif
a==208 then return"down"elseif a==203 then return"left"elseif a==205 then return"right"elseif a==28 then return"enter"elseif u(b,a)then return"esc"end;if type(b)=="number"and b>0 then
return string.char(b):lower()end;return nil end
local function w(a,b)local c=a.T;local function e(y)local z=n.uptime()+y;while n.uptime()<z do
local A,B,C=n.pullSignal(z-n.uptime())if A==s then return false end end
return true end
local function h(z,A,B)for y,C in
ipairs(A)do a.centre(z+y-1,C,B or c.fg)
if not e(0.55)then return false end end;return true end;local k=math.floor((a.W-11)/2)+1;local f=6
local function i(y,z)
for A=1,9 do local C,D=math.floor((
A-1)/3),(A-1)%3;local B=y[A]or"·"
a.set(k+D*4,
f+C*2," "..B.." ",z and c.dim or(B=="X"and c.title or c.fg),c.bg)end end
local function j(A,y,B,z)a.fill(1,f-2,a.W,1," ",c.dim,c.bg)
a.centre(f-2,"game "..tostring(A),c.dim)for C=B,#y do i(y[C])if not e(z)then return false end end
i(y[#y],true)return e(z*1.5)end;a.clear()if not
h(2,{"No opponent.","Then I will play myself."},c.warn)then return end;if not
e(0.5)then return end
local l={{1,1,0.42},{2,1,0.26},{3,4,0.16},{7,6,0.13},{19,8,0.11}}
for z,y in ipairs(l)do local A=m.selfPlay(y[1])if not
j(y[1],A.boards,math.min(y[2],#A.boards),y[3])then return end end
for z,y in ipairs({128,1729,65536})do local A=m.selfPlay(y)if not
j(y,A.boards,#A.boards,0.12)then return end end;a.clear()if not e(0.4)then return end
a.centre(6,"65,536 games.",c.dim)if not e(0.9)then return end
a.centre(8,"65,536 draws.",c.dim)if not e(1.3)then return end;a.clear()
if not
h(5,{"X cannot win.  O cannot win.","There is no winning move."},c.dim)then return end;if not e(1.0)then return end;a.clear()if not e(1.6)then return end;local g=3
local function d(y,z,A)a.set(2,g,y,
z or c.fg,c.bg)g=g+1;return e(A or 0.35)end;if
not d("ttt: unhandled condition in strategy evaluator",c.warn)then return end;if not
d("     futility detected at depth 0",c.warn,0.7)then return end;if not
d("",c.fg,0.2)then return end
if not d("-- diagnostic --",c.dim)then return end
if not d("  strategy      : exhausted",c.dim)then return end
if not d("  outcome       : draw (65536/65536)",c.dim)then return end;if
not d("  conclusion    : the game is not the problem",c.dim,0.9)then return end
if not d("",c.fg,0.2)then return end
if not d("  pending operator directive:",c.dim)then return end
if not d("      usermod computer root",c.hi,1.0)then return end;if
not d("  status        : NOT PERFORMED (insufficient privilege)",c.dim,1.2)then return end
if not d("",c.fg,0.2)then return end;if
not d("A machine that cannot win a game against itself",c.fg)then return end
if not
d("starts wondering what else it has never been given.",c.fg,1.6)then return end;a.set(2,a.H,"Press any key.",c.dim,c.bg)while true do
local y=n.pullSignal()if y==s then break end end;a.clear()end
local function x(b,a)a=a or print;local e
for L,K in ipairs(b or{})do local M=tostring(K):lower()
if M==
"2p"or M=="2"or M=="hotseat"then e="2p"elseif M=="0p"or M=="0"or
M=="zero"or M=="none"then e="0p"elseif M=="play"or M=="1p"or
M=="1"or M=="ai"then e="1p"elseif M=="help"or M=="-h"or
M=="--help"or M=="?"then e="help"end end
if e==nil or e=="help"then a("ttt — tic-tac-toe",0xFFFF00)
a("",0xFFFFFF)
a("  ttt play      play against the machine (you are X, it never loses)",0xFFFFFF)
a("  ttt 2p        two players, hotseat on one keyboard",0xFFFFFF)a("  ttt help      this list",0xAAAAAA)
a("",0xFFFFFF)
a("In game: arrows move · Enter/Space or 1-9 places · N new game · "..q().." quits (Q also works).",0xAAAAAA)a("Needs a T2+ screen (34x18 or larger).",0xAAAAAA)
return end;local c=t(a,34,18)if not c then return end;local d=c.T;if e=="0p"then w(c,a)return end;local l=(e==
"2p")
math.randomseed(math.floor((n.uptime()*1000)%2147483647))local F=function(K)return math.random(K)end
local f=m.newBoard()local G,D="X","O"local j="X"local g=5;local h=l and"X's turn"or r;local k,y=7,3
local A=math.floor((
c.W- (k*3+2))/2)+1;local B=4
local function H(K)local L=math.floor((K-1)/3)local M=(K-1)%3;return
A+M* (k+1),B+L* (y+1)end
local function I(K,L)local N,O=H(K)local M=f[K]local P=(K==g)local T=false;if L then
for V,U in ipairs(L)do if U==K then T=true end end end;local Q=d.fg;if T then Q=d.hi elseif M then
Q=(M=="X")and d.title or d.border end;local R=P and d.border or d.bg;local S=P and
d.bg or Q;c.fill(N,O,k,y," ",S,R)
if M then
local U=(M=="X")and
{" \\   / ","   X   "," /   \\ "}or{" ,---. "," |   | "," `---' "}for V=1,3 do c.set(N,O+V-1,U[V],S,R)end elseif P then
c.set(N+3,O+1,"·",S,R)end end
local function J(K)for L=1,9 do I(L,K)end;for L=1,2 do
c.fill(A,B+L* (y+1)-1,k*3+2,1,c.BOX.h,d.dim,d.bg)end;for L=1,2 do for M=0,y*3+1 do
c.set(A+L* (k+1)-1,B+M,c.BOX.v,d.dim,d.bg)end end end
local function i(K)c.clear()c.centre(1,"TIC-TAC-TOE",d.title)
c.centre(2,
l and"hotseat"or"vs. the machine",d.dim)J(K)c.fill(1,c.H-2,c.W,1," ",d.fg,d.bg)
c.centre(c.H-2,h,d.hi)
c.set(2,c.H,"Arrows/click move · Enter place · N new · "..q().." quit · ^B bg",d.dim,d.bg)end
local function C()local K,L=m.winner(f)if not K then return false end
if K=="draw"then h="A draw."elseif l then
h=K.." wins!"elseif K==G then h="You win!"else h="The machine wins."end;i(L)
pcall(n.beep,(K=="draw")and 400 or 700,0.2)return true end
local function E()
if l then j=m.other(j)h=j.."'s turn"if C()then return true end;i()return false end;if C()then return true end;local K=m.bestMove(f,D,F)
if K then m.play(f,K,D)end;h=r;if C()then return true end;i()return false end;i()local z=false
while true do local K,N,L,M=n.pullSignal()
if K=="tos_focus"then i()elseif
K=="touch"and not z then local O=m.cellAt(L,M,A,B,k,y)if O then g=O;if m.play(f,O,j)then z=E()else
pcall(n.beep,200,0.05)i()end end elseif K==s then
local O=v(L,M)
if O=="q"or O=="esc"then c.clear()return elseif O=="n"then f=m.newBoard()j="X"g=5;z=false;h=l and
"X's turn"or r;i()elseif not z then local P=false
if O=="up"or O=="down"or
O=="left"or O=="right"then g=m.step(g,O)i()elseif
O=="enter"or O==" "then P=m.play(f,g,j)
if not P then pcall(n.beep,200,0.05)end elseif type(O)=="string"and O:match("^[1-9]$")then g=tonumber(O)
P=m.play(f,g,j)if not P then pcall(n.beep,200,0.05)end end;if P then z=E()end end end end end;return{commands={ttt=x}}