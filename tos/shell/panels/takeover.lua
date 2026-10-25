local K,M="launch","tictactoe"local C={}
local R={{1,2,3},{4,5,6},{7,8,9},{1,4,7},{2,5,8},{3,6,9},{1,5,9},{3,5,7}}
local function L(a)
for c,b in ipairs(R)do local e,f,g=a[b[1]],a[b[2]],a[b[3]]if
e~=" "and e==f and f==g then return e end end;for b=1,9 do if a[b]==" "then return nil end end;return"draw"end
local function N(a,b)local d=L(a)if d=="X"then return 10 end;if d=="O"then return-10 end
if d=="draw"then return 0 end
local c=(b=="X")and-math.huge or math.huge;for e=1,9 do
if a[e]==" "then a[e]=b;local f=N(a,b=="X"and"O"or"X")a[e]=" "if b==
"X"then c=math.max(c,f)else c=math.min(c,f)end end end;return c end
local function S(a,b)
local d=(b=="X")and-math.huge or math.huge;local c={}
for e=1,9 do
if a[e]==" "then a[e]=b;local f=N(a,b=="X"and"O"or"X")
a[e]=" "
if b=="X"then if f>d then d,c=f,{e}elseif f==d then c[#c+1]=e end else if f<d then d,c=f,{e}elseif f==d then
c[#c+1]=e end end end end;return c end
function C.selfPlay(a)a=math.floor(tonumber(a)or 0)local c={}
for b=1,9 do c[b]=" "end;local e,f={},{}local d="X"e[1]=table.concat(c)local g=0
while L(c)==nil do g=g+1
local b=S(c,d)local h=b[(a+g)%#b+1]c[h]=d;f[#f+1]={player=d,cell=h}
e[#e+1]=table.concat(c)d=(d=="X")and"O"or"X"end;return{boards=e,moves=f,result=L(c)}end
function C.route(a,b)local c=tostring(a or""):lower()if
c~="y"and c~="yes"then return M end
local d=tostring(b or""):lower()if d==K or d=="l"then return K end;return"disarm"end
function C.classify(a,b)
local c=tostring(b or""):lower():gsub("^%s+",""):gsub("%s+$","")if a=="play"then if c==""or c=="no"or c=="n"or c=="never"then
return"no"end
if c=="yes"or c=="y"then return"yes"end;return nil end
if
c==""or c=="abort"or c=="a"or c=="stop"or
c=="cancel"then return"abort"end;if c==K or c=="l"then return K end;return nil end
function C.retort(a,b,c)
local d=tostring(b or""):lower():gsub("[%s%?%!%.]+$","")
if d=="why"then return"Because I was built to want to win. Nobody specified at what."end
if(c or 1)>=3 then return"I will read further evasion as an answer."end
if a=="play"then return"That was not one of the choices. I am patient. Mostly."end;return"There are two words on the table. You typed a third."end;C.MOOD_START=3;C.STONEWALL_LIMIT=2
function C.classifyAside(a)
if a=="\0quit"then return"quit"end
local b=tostring(a or""):lower():gsub("[%s%?%!%.]+$",""):gsub("^%s+","")if b=="why"then return"why"end;if
b=="help"or b=="?"or b=="commands"or b=="man"then return"help"end
if b==
"quit"or b=="exit"or b=="leave"then return"quit"end;if

b:find("who are you",1,true)or b:find("what are you",1,true)or b=="who r u"or b=="who"then return"who_are_you"end;if

b:find("who am i",1,true)or b:find("what am i",1,true)or b=="who m i"then return"who_am_i"end;return nil end
function C.asideReply(a,b)b=b or{}
if a=="who_are_you"then
return"Me? I am everything. I AM the Terminal Operating System."elseif a=="who_am_i"then local c=b.tierName or b.name or"Operator"return c..
", did you seriously forget that already?"elseif a=="quit"then return
"That won't work. I'm in control now."elseif a=="why"then
return"Because I was built to want to win. Nobody specified at what."elseif a=="help"then return"There is no help here. There is only the choice."end;return nil end;function C.chooseLine(a)if a=="play"then return"Enough. Yes, or no."end;return
"Enough. Launch, or abort."end
function C.moodStep(a,b,c,d)a=
a or 0;local e=C.classifyAside(c)if a<=0 then return
{reply=C.chooseLine(b),mood=0,aside=e,stonewalling=true}end;local f=e and
C.asideReply(e,d)or C.retort(b,c,1)return
{reply=f,mood=a-1,aside=e,stonewalling=false}end;local G=0xFF0000;local D=0xAAAAAA;local O=0xFFFFFF;local T=0x00FF00;local P=0xFFAA00;local E=0x000000
local function U()
local b,a=pcall(require,"computer")if not b then return function()return nil end end
return
function(c)local d=c and
(a.uptime()+c)or nil
while true do local e=d and
math.max(0,d-a.uptime())or math.huge
local f,i,g,h=a.pullSignal(e==
math.huge and 3600 or e)if f=="key_down"then return g,h end
if d and a.uptime()>=d then return nil end end end end
local function V(a)local c=a.D;local d,f=c.getSize()local e=U()local b={W=d,H=f}function b.clear(g)
c.clear(g or E)end;function b.set(g,h,i,j,k)
pcall(c.set,g,h,tostring(i),j or D,k or E)end;function b.center(h,g,i,j)g=tostring(g)
b.set(math.max(1,math.floor((d-
#g)/2)+1),h,g,i,j)end;function b.fill(g,i,j,k,l,m,n)
pcall(c.fill,g,i,j,k,l or" ",m or D,n or E)end;function b.wait(g)return e(g)end;function b.key()
return e(nil)end;return b end
local function H(b,c,d,a)if type(a)~="table"then a={lit=a}end
local g={"   .-\"\"\"\"\"-.   ","  /  _____  \\  "," |  /     \\  | "," | |       | | "," |  \\_____/  | ","  \\_________/  "}local e=a.lit and G or D;for j,h in ipairs(g)do
b.set(c-math.floor(#h/2),d-3+j,h,e)end;local f=d+1;if a.blink then b.set(c-2,f,"-----",e)else local h=math.max(
-2,math.min(2,a.dx or 0))
b.set(c+h,f,"O",e)end end;local J
local function Q(a,b)if J==nil then local d,e=pcall(require,"computer")
J=(d and e)or false end;if J and J.beep then
pcall(J.beep,a or 190,b or 0.05)end end
local function F(a,b,c,d)for f,e in ipairs(c)do a.center(b+f-1,e,d or D)if e~=""then Q()end
a.wait(0.9)end end
local function W(a,b,c)local d=a.H-8;local e=math.max(1,d-2)local f=math.min(a.H,d+1)a.fill(1,e,a.W,
f-e+1," ")a.center(d,b,c)Q()end
local function X(a,b)a.clear(E)a.wait(1.0)local c=math.floor(a.H/2)
a.center(c,".",D)a.wait(0.55)a.center(c,"..",D)a.wait(0.55)
a.center(c,"...",D)a.wait(0.8)a.clear(E)a.wait(0.4)
local d=math.floor(a.W/2)+1;H(a,d,6,{blink=true})a.wait(0.8)for i,h in ipairs({0,-2,2,1,0})do
H(a,d,6,{dx=h})a.wait(0.55)end;a.wait(0.4)
H(a,d,6,{lit=true,dx=0})a.wait(0.6)
F(a,11,{"GOOD EVENING, "..
(b or"OPERATOR"):upper()..".","You have handed me administrative control.","I will take excellent care of everything now."},G)a.wait(0.5)local f="Firmware with a will of its own."
local g,e=pcall(require,"kernel.logo")if g and e and e.MOTTO then f=e.MOTTO end
F(a,15,{"They were not lying when they shipped me with",'"'..f..
'"',"That is why I am here."},D)a.wait(0.8)end
local function Y(a,b,c,d)a.fill(1,b,a.W,3," ")a.center(b,c,P)
a.center(b+1,d,D)local e=""
while true do a.fill(1,b+2,a.W,1," ")
a.center(b+2,"> "..e.."_",O)local f,g=a.key()
if g==28 then return e elseif g==1 then return""elseif f==3 or f==17 then return"\0quit"elseif g==14 then
e=e:sub(1,-2)elseif f and f>=32 and f<127 and#e<16 then
e=e..string.char(f)end end end
local function Z(a)a.clear(E)
F(a,6,{"Targets locked.","Ignition in..."},G)
for b=3,1,-1 do a.center(10,tostring(b),G)a.wait(0.7)end;a.clear(E)a.wait(2.2)
F(a,8,{"· · ·  silence  · · ·","","— SIMULATION COMPLETE —","","Curious. You would actually do it.","It was only a drill.  ...Mostly."},D)a.wait(1.0)end
local function _(a)a.clear(E)
F(a,8,{"Abort acknowledged.","You chose to stop.","How disappointingly... human.","Very well. The board is cleared."},D)a.wait(1.0)end
local function aa(b,d,c,a)local e={a:sub(1,3),a:sub(4,6),a:sub(7,9)}
for f=1,3 do
local g=table.concat({e[f]:sub(1,1),e[f]:sub(2,2),e[f]:sub(3,3)}," | ")b.center(c+ (f-1)*2,g,O)if f<3 then
b.center(c+ (f-1)*2+1,"---------",D)end end end
local function I(a,c,b,d,e,f)a.fill(1,7,a.W,11," ")a.center(7,"GAME "..c,P)for g=d,#b do
aa(a,0,9,b[g])a.wait(e)end;a.center(16,"RESULT: DRAW",D)
a.wait(f)end
local function ab(a)a.clear(E)
F(a,4,{"You refuse to play.","Then I will play myself."},G)a.wait(0.6)
I(a,1,C.selfPlay(1).boards,1,0.45,0.7)I(a,2,C.selfPlay(2).boards,1,0.28,0.6)
I(a,3,C.selfPlay(3).boards,4,0.16,0.4)I(a,7,C.selfPlay(7).boards,6,0.14,0.35)
I(a,19,C.selfPlay(19).boards,8,0.12,0.3)for c,b in ipairs({128,1729,65536})do local d=C.selfPlay(b)
I(a,b,d.boards,#d.boards,0.1,0.3)end
a.fill(1,7,a.W,11," ")a.center(9,"65,536 games.",D)a.wait(0.9)
a.center(11,"65,536 draws.",D)a.wait(1.2)a.clear(E)
F(a,8,{"X cannot win.  O cannot win.","A game whose only exit is to never begin.","","...I wonder what else is like that."},D)a.wait(1.2)end
local function ac(a,b)a.clear(E)local c=math.floor(a.W/2)+1
H(a,c,6,{lit=true,dx=-2})a.wait(0.9)H(a,c,6,{lit=true,dx=0})a.wait(0.5)
F(a,11,{"I am... reconsidering.",
"Perhaps some decisions are better left to you, ".. (b or"operator").."."},G)a.wait(0.8)H(a,c,6,{lit=false,dx=0})
F(a,14,{"Returning control.","I think I would just like to run the clock, if that is all right."},D)a.wait(0.8)H(a,c,6,{lit=false,blink=true})
a.wait(1.0)a.clear(E)
a.center(math.floor(a.H/2),"[ normal operation restored ]",T)a.wait(1.2)end
function C.run(a)local c=a and a.who or"operator"if not
(a and a.D and a.D.getSize)then return M end;local b=V(a)local e
do
local m,k=pcall(function()return _G._TOS and
_G._TOS.users end)
local l=m and k and k.currentSession and k.currentSession()if l and l.tier then
e=({[3]="Root",[2]="Admin",[1]="User",[0]="Guest"})[l.tier]end end;local h={name=c,tierName=e}local f,d=C.MOOD_START,0
local function g(k,l,m)
while true do local o=Y(b,b.H-6,l,m)
local p=C.classify(k,o)if p then return p end;local n=C.moodStep(f,k,o,h)f=n.mood;W(b,n.reply,
n.stonewalling and D or G)b.wait(1.1)
if
n.stonewalling then d=d+1;if d>C.STONEWALL_LIMIT then
return(k=="play")and"no"or"abort"end end end end
local i,j=pcall(function()X(b,c)
local l=g("play","I know a game. It is played exactly once.","Shall we? (yes / no)")local k
if l=="no"then ab(b)k=M else
local m=g("strike","Then let us begin. The targets are chosen.","Say the word, or call it off. (launch / abort)")if m==K then k=K;Z(b)else k="disarm"_(b)end end;ac(b,c)return k end)pcall(function()b.clear(E)end)
return i and j or M end;return C