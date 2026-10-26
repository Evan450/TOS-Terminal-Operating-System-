local x,t,o="Message","key_down","number"local n={}
local function p(a,b)
if a and a>=32 and a<127 then return false end;local d,c=pcall(require,"shell.keys")if d and c and c.is then
return c.is("quit",a,b)end;return a==17 or b==1 end;local y=5;local r
local function q()if coroutine.isyieldable and coroutine.isyieldable()then return
coroutine.yield()end
r=r or require("computer")return r.pullSignal(y)end
function n.scrollTail(a,b)b=math.max(0,math.floor(b or 0))
if#a<=b then return a end;return a:sub(#a-b+1)end
function n.fitPrompt(a,b)a=tostring(a or"")
local c=math.max(12,math.floor(b or 80)-10)if#a<=c then return a end;local d=math.min(16,c-8)local e=c-d-3;return a:sub(1,e).."..."..a:sub(
#a-d+1)end
function n.promptInput(a,b,c,d)local h,f,g=a.D,a.T,a.W;local i=a.OUT_ROW;b=n.fitPrompt(b,g)local e=""
while true do
h.fill(1,i,g,1," ",f.fg,f.bg)local m=d and string.rep("*",#e)or e;local A=n.scrollTail(m,
g-#b-1)
h.set(1,i,(b..A.."_"):sub(1,g),f.title,f.bg)local l,B,j,k=q()
if l==t then
if k==28 then return e elseif p(j,k)then return nil elseif k==14 then if#e>0 then e=e:sub(1,-2)end elseif j and
j>=32 and j<127 and#e< (c or 64)then
e=e..string.char(j)end elseif l=="clipboard"and type(j)=="string"and not d then e=(e..
j:gsub("\n","")):sub(1,c or 64)end end end
function n.wrapText(b,a)a=math.max(1,math.floor(a or 40))local c={}
for d in(
tostring(b).."\n"):gmatch("(.-)\n")do
if d==""then c[#c+1]=""else
local e=""
for f in d:gmatch("%S+")do while#f>a do if e~=""then c[#c+1]=e;e=""end
c[#c+1]=f:sub(1,a)f=f:sub(a+1)end;if e==""then e=f elseif
#e+1+#f<=a then e=e.." "..f else c[#c+1]=e;e=f end end;if e~=""then c[#c+1]=e end end end;if#c==0 then c[1]=""end;return c end
function n.layoutButtons(a)local c,d,b={},{},1
for e,f in ipairs(a)do if e>1 then c[#c+1]="   "b=b+3 end;local g="[ "..
f.." ]"c[#c+1]=g;d[e]={s=b,e=b+#g-1}b=b+#g end;return table.concat(c),d, (b-1)end
function n.boxRect(a,b,c,d)local e=math.min(a,math.max(1,c)+4)local f=math.min(b,
math.max(1,d)+2)
local g=math.max(1,math.floor((a-e)/2)+1)
local h=math.max(1,math.floor((b-f)/2)+1)return{x=g,y=h,w=e,h=f}end
local u={info={frame="title",title="title"},install={frame="title",title="title"},warn={frame="warning",title="warning"},danger={frame="error",title="error"},error={frame="error",title="error"},general={frame="border",title="fg"},plain={frame="border",title="fg"}}
local v={info="Information",install="Install",warn="Warning",danger="Warning",error="Error",general=x,plain=x}
local function w(b,e,a,c,d,f,g)local j,i,J,K=b.D,b.T,b.W,b.H;local D=u[e]or u.general;local m=i[D.frame]or i.border or
i.fg;local L=i[D.title]or i.fg;a=a or""
local A=(
a~="")and("╡ "..a.." ╞")or nil;local E=A and(#a+4)or 0;local M,N,F=n.layoutButtons(d)
local B=math.max(E-2,F)for Q,H in ipairs(c)do B=math.max(B,#H)end;local O=#c+2
local h=n.boxRect(J,K,B,O)local l=h.w-2;local k=i.panel_bg or i.bg
if g~=false then local H=0x1A1A1A
j.set(h.x+1,h.y+h.h,string.rep(" ",h.w),H,H)for Q=1,h.h do j.set(h.x+h.w,h.y+Q," ",H,H)end end
j.set(h.x,h.y,"╔"..string.rep("═",l).."╗",m,k)for H=1,h.h-2 do
j.set(h.x,h.y+H,"║"..string.rep(" ",l).."║",m,k)end
j.set(h.x,h.y+h.h-1,"╚"..
string.rep("═",l).."╝",m,k)if A then local H=math.max(0,math.floor((l-E)/2))j.set(
h.x+1+H,h.y,A,L,k)end
for H,Q in
ipairs(c)do j.set(h.x+2,h.y+H,Q:sub(1,l-2),i.fg,k)end;local G=h.y+#c+2
local P=math.max(0,math.floor((l-F)/2))local C=h.x+1+P;local I={}
for H,Q in ipairs(d)do local R=N[H]local T=M:sub(R.s,R.e)
local S=(H==f)
local U=S and(i.selected_fg or k)or i.fg
local V=S and(i.selected_bg or i.highlight)or k;j.set(C+R.s-1,G,T,U,V)
I[H]={x1=C+R.s-1,x2=C+R.e-1,y=G,label=Q}end;return I end
local function s(a,...)local b=a.D
local d=b and b.beginFrame and b.beginFrame()if not d then return w(a,...)end;local e,c=pcall(w,a,...)b.endFrame()if
not e then error(c,0)end;return c end
local function z(c,d,e,f,b,a,i,g,h)local j={}for m,A in ipairs(b)do local l=A:sub(1,1):lower()if l~=""and not j[l]then
j[l]=m end end
local k=s(c,d,e,f,b,a,g)
while true do local B=a;local A,C,l,m=q()if h and h()then return nil end
if A==t then
if m==28 then return a elseif p(l,m)then return i elseif m==203 then a=
(a>1)and(a-1)or#b elseif m==205 or m==15 then
a=(a<#b)and(a+1)or 1 elseif l and l>=32 and l<127 then
local D=j[string.char(l):lower()]if D then return D end end elseif A=="touch"and type(l)==o and type(m)==o then
for E,D in ipairs(k)do if
m==D.y and l>=D.x1 and l<=D.x2 then return E end end end;if a~=B then k=s(c,d,e,f,b,a,g)end end end
function n.confirmTyped(c,d,b,a)a=a or{}
local h=a.style or a.severity or"danger"local l=a.title or v[h]or"Confirm"
local g={a.no or"Cancel",a.yes or"Confirm"}
local m=n.wrapText(a.message or d or"",math.max(16,(c.W or 50)-8))local e,f="",1;local i=math.max(#b+8,16)
local function j()local A={}
for C,B in ipairs(m)do A[#A+1]=B end;A[#A+1]=""A[#A+1]='Type  '..b..'  to confirm:'A[
#A+1]="  "..e.."_"
A[#A+1]=(e==b)and
("  the word matches - choose "..g[2])or
("  ("..g[2].." stays inert until it matches)")return s(c,h,l,A,g,f,a.shadow)end;local k=j()
while true do local E,F=f,e;local D=(e==b)local C,G,A,B=q()
if C==t then
if p(A,B)then
if a.redraw then a.redraw()end;return false elseif B==28 then
if f==1 then if a.redraw then a.redraw()end;return false elseif D then if a.redraw then
a.redraw()end;return true end elseif B==203 then f=(f>1)and(f-1)or#g elseif B==205 or B==15 then f=
(f<#g)and(f+1)or 1 elseif B==14 then if#e>0 then e=e:sub(1,-2)end elseif
A and A>=32 and A<127 and#e<i then e=e..string.char(A)end elseif C=="touch"and type(A)==o and type(B)==o then
for I,H in ipairs(k)do
if
B==H.y and A>=H.x1 and A<=H.x2 then
if I==1 then if a.redraw then a.redraw()end;return
false elseif D then if a.redraw then a.redraw()end;return true else f=2 end end end elseif C=="clipboard"and type(A)=="string"then
e=(e..A:gsub("\n","")):sub(1,i)end;if f~=E or e~=F then k=j()end end end
function n.progressLines(c,a,b)
if type(c)~=o or type(a)~=o or a<1 then return{}end;b=math.max(10,math.min(b or 30,40))
local e=math.max(0,math.min(c,a))local d=math.floor((e/a)*b+0.5)return
{"",string.format("%d of %d   [%s%s]",c,a,string.rep("#",d),string.rep("-",
b-d))}end
function n.dialog(b,a)a=a or{}local d=a.style or a.severity or"general"local f=
a.title or v[d]or x;local e=a.buttons or{"OK"}
local c=n.wrapText(
a.message or a.body or"",math.max(16,(b.W or 50)-8))
if a.progress then for k,j in
ipairs(n.progressLines(a.progress.index,a.progress.total,(b.W or 50)-16))do c[#c+1]=j end end;local g=a.default or 1;local h=a.escIndex or#e
local i=z(b,d,f,c,e,g,h,a.shadow,a.closeIf)if a.redraw and a.redraw~=false then a.redraw()end
return i end
function n.alert(b,c,a)a=a or{}
n.dialog(b,{style=a.style or a.severity or"info",title=a.title,message=a.message or c,buttons={a.ok or
"OK"},default=1,escIndex=1,shadow=a.shadow,redraw=a.redraw})return true end
function n.confirm(b,c,a)a=a or{}
local d=n.dialog(b,{style=a.style or a.severity or"danger",title=a.title,message=a.message or c,buttons={
a.no or"No",a.yes or"Yes"},default=(a.default=="yes")and 2 or 1,escIndex=1,progress=a.progress,shadow=a.shadow,redraw=a.redraw})return d==2 end
function n.promptSearch(a,b)local f,d,e,g=a.D,a.T,a.W,a.H;local c=b or""
while true do
f.fill(1,g,e,1," ",d.fg,d.bg)local j=n.scrollTail(c,e-7)
f.set(1,g,("Find: "..j.."_"):sub(1,e),d.title,d.bg)local k,l,h,i=q()
if k==t then
if i==28 then return#c>0 and c or nil elseif p(h,i)then return b elseif i==14 then if#c>0 then
c=c:sub(1,-2)end elseif h and h>=32 and h<127 then c=c..string.char(h)end end end end;return n