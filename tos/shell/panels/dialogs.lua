local v,r,n="Message","key_down","number"local m={}local w=5;local p
local function o()
if coroutine.isyieldable and
coroutine.isyieldable()then return coroutine.yield()end;p=p or require("computer")return p.pullSignal(w)end
function m.scrollTail(a,b)b=math.max(0,math.floor(b or 0))
if#a<=b then return a end;return a:sub(#a-b+1)end
function m.fitPrompt(a,b)a=tostring(a or"")
local c=math.max(12,math.floor(b or 80)-10)if#a<=c then return a end;local d=math.min(16,c-8)local e=c-d-3;return a:sub(1,e).."..."..a:sub(
#a-d+1)end
function m.promptInput(a,b,c,d)local h,f,g=a.D,a.T,a.W;local i=a.OUT_ROW;b=m.fitPrompt(b,g)local e=""
while true do
h.fill(1,i,g,1," ",f.fg,f.bg)local y=d and string.rep("*",#e)or e;local z=m.scrollTail(y,
g-#b-1)
h.set(1,i,(b..z.."_"):sub(1,g),f.title,f.bg)local k,A,j,l=o()
if k==r then
if l==28 then return e elseif j==17 then return nil elseif l==14 then if#e>0 then e=e:sub(1,-2)end elseif j and
j>=32 and j<127 and#e< (c or 64)then
e=e..string.char(j)end elseif k=="clipboard"and type(j)=="string"and not d then e=(e..
j:gsub("\n","")):sub(1,c or 64)end end end
function m.wrapText(b,a)a=math.max(1,math.floor(a or 40))local c={}
for d in(
tostring(b).."\n"):gmatch("(.-)\n")do
if d==""then c[#c+1]=""else
local e=""
for f in d:gmatch("%S+")do while#f>a do if e~=""then c[#c+1]=e;e=""end
c[#c+1]=f:sub(1,a)f=f:sub(a+1)end;if e==""then e=f elseif
#e+1+#f<=a then e=e.." "..f else c[#c+1]=e;e=f end end;if e~=""then c[#c+1]=e end end end;if#c==0 then c[1]=""end;return c end
function m.layoutButtons(a)local c,d,b={},{},1
for e,f in ipairs(a)do if e>1 then c[#c+1]="   "b=b+3 end;local g="[ "..
f.." ]"c[#c+1]=g;d[e]={s=b,e=b+#g-1}b=b+#g end;return table.concat(c),d, (b-1)end
function m.boxRect(a,b,c,d)local e=math.min(a,math.max(1,c)+4)local f=math.min(b,
math.max(1,d)+2)
local g=math.max(1,math.floor((a-e)/2)+1)
local h=math.max(1,math.floor((b-f)/2)+1)return{x=g,y=h,w=e,h=f}end
local s={info={frame="title",title="title"},install={frame="title",title="title"},warn={frame="warning",title="warning"},danger={frame="error",title="error"},error={frame="error",title="error"},general={frame="border",title="fg"},plain={frame="border",title="fg"}}
local t={info="Information",install="Install",warn="Warning",danger="Warning",error="Error",general=v,plain=v}
local function u(b,e,a,c,d,f,g)local j,i,I,J=b.D,b.T,b.W,b.H;local C=s[e]or s.general;local y=i[C.frame]or i.border or
i.fg;local K=i[C.title]or i.fg;a=a or""
local z=(
a~="")and("╡ "..a.." ╞")or nil;local D=z and(#a+4)or 0;local L,M,E=m.layoutButtons(d)
local A=math.max(D-2,E)for P,H in ipairs(c)do A=math.max(A,#H)end;local N=#c+2
local h=m.boxRect(I,J,A,N)local l=h.w-2;local k=i.panel_bg or i.bg
if g~=false then local H=0x1A1A1A
j.set(h.x+1,h.y+h.h,string.rep(" ",h.w),H,H)for P=1,h.h do j.set(h.x+h.w,h.y+P," ",H,H)end end
j.set(h.x,h.y,"╔"..string.rep("═",l).."╗",y,k)for H=1,h.h-2 do
j.set(h.x,h.y+H,"║"..string.rep(" ",l).."║",y,k)end
j.set(h.x,h.y+h.h-1,"╚"..
string.rep("═",l).."╝",y,k)if z then local H=math.max(0,math.floor((l-D)/2))j.set(
h.x+1+H,h.y,z,K,k)end
for H,P in
ipairs(c)do j.set(h.x+2,h.y+H,P:sub(1,l-2),i.fg,k)end;local F=h.y+#c+2
local O=math.max(0,math.floor((l-E)/2))local B=h.x+1+O;local G={}
for H,P in ipairs(d)do local Q=M[H]local S=L:sub(Q.s,Q.e)
local R=(H==f)
local T=R and(i.selected_fg or k)or i.fg
local U=R and(i.selected_bg or i.highlight)or k;j.set(B+Q.s-1,F,S,T,U)
G[H]={x1=B+Q.s-1,x2=B+Q.e-1,y=F,label=P}end;return G end
local function q(a,...)local b=a.D
local d=b and b.beginFrame and b.beginFrame()if not d then return u(a,...)end;local e,c=pcall(u,a,...)b.endFrame()if
not e then error(c,0)end;return c end
local function x(c,d,e,f,b,a,i,g,h)local j={}for y,z in ipairs(b)do local l=z:sub(1,1):lower()if l~=""and not j[l]then
j[l]=y end end
local k=q(c,d,e,f,b,a,g)
while true do local A=a;local z,B,l,y=o()if h and h()then return nil end
if z==r then
if y==28 then return a elseif y==1 or l==17 then
return i elseif y==203 then a=(a>1)and(a-1)or#b elseif y==205 or y==15 then a=
(a<#b)and(a+1)or 1 elseif l and l>=32 and l<127 then
local C=j[string.char(l):lower()]if C then return C end end elseif z=="touch"and type(l)==n and type(y)==n then
for D,C in ipairs(k)do if
y==C.y and l>=C.x1 and l<=C.x2 then return D end end end;if a~=A then k=q(c,d,e,f,b,a,g)end end end
function m.confirmTyped(c,d,b,a)a=a or{}
local h=a.style or a.severity or"danger"local l=a.title or t[h]or"Confirm"
local g={a.no or"Cancel",a.yes or"Confirm"}
local y=m.wrapText(a.message or d or"",math.max(16,(c.W or 50)-8))local e,f="",1;local i=math.max(#b+8,16)
local function j()local z={}
for B,A in ipairs(y)do z[#z+1]=A end;z[#z+1]=""z[#z+1]='Type  '..b..'  to confirm:'z[
#z+1]="  "..e.."_"
z[#z+1]=(e==b)and
("  the word matches - choose "..g[2])or
("  ("..g[2].." stays inert until it matches)")return q(c,h,l,z,g,f,a.shadow)end;local k=j()
while true do local D,E=f,e;local C=(e==b)local B,F,z,A=o()
if B==r then
if A==1 or z==17 then if a.redraw then
a.redraw()end;return false elseif A==28 then
if f==1 then if a.redraw then a.redraw()end;return false elseif C then if
a.redraw then a.redraw()end;return true end elseif A==203 then f=(f>1)and(f-1)or#g elseif A==205 or A==15 then f=
(f<#g)and(f+1)or 1 elseif A==14 then if#e>0 then e=e:sub(1,-2)end elseif
z and z>=32 and z<127 and#e<i then e=e..string.char(z)end elseif B=="touch"and type(z)==n and type(A)==n then
for H,G in ipairs(k)do
if
A==G.y and z>=G.x1 and z<=G.x2 then
if H==1 then if a.redraw then a.redraw()end;return
false elseif C then if a.redraw then a.redraw()end;return true else f=2 end end end elseif B=="clipboard"and type(z)=="string"then
e=(e..z:gsub("\n","")):sub(1,i)end;if f~=D or e~=E then k=j()end end end
function m.progressLines(c,a,b)
if type(c)~=n or type(a)~=n or a<1 then return{}end;b=math.max(10,math.min(b or 30,40))
local e=math.max(0,math.min(c,a))local d=math.floor((e/a)*b+0.5)return
{"",string.format("%d of %d   [%s%s]",c,a,string.rep("#",d),string.rep("-",
b-d))}end
function m.dialog(b,a)a=a or{}local d=a.style or a.severity or"general"local f=
a.title or t[d]or v;local e=a.buttons or{"OK"}
local c=m.wrapText(
a.message or a.body or"",math.max(16,(b.W or 50)-8))
if a.progress then for k,j in
ipairs(m.progressLines(a.progress.index,a.progress.total,(b.W or 50)-16))do c[#c+1]=j end end;local g=a.default or 1;local h=a.escIndex or#e
local i=x(b,d,f,c,e,g,h,a.shadow,a.closeIf)if a.redraw and a.redraw~=false then a.redraw()end
return i end
function m.alert(b,c,a)a=a or{}
m.dialog(b,{style=a.style or a.severity or"info",title=a.title,message=a.message or c,buttons={a.ok or
"OK"},default=1,escIndex=1,shadow=a.shadow,redraw=a.redraw})return true end
function m.confirm(b,c,a)a=a or{}
local d=m.dialog(b,{style=a.style or a.severity or"danger",title=a.title,message=a.message or c,buttons={
a.no or"No",a.yes or"Yes"},default=(a.default=="yes")and 2 or 1,escIndex=1,progress=a.progress,shadow=a.shadow,redraw=a.redraw})return d==2 end
function m.promptSearch(a,b)local f,d,e,g=a.D,a.T,a.W,a.H;local c=b or""
while true do
f.fill(1,g,e,1," ",d.fg,d.bg)local j=m.scrollTail(c,e-7)
f.set(1,g,("Find: "..j.."_"):sub(1,e),d.title,d.bg)local k,l,h,i=o()
if k==r then
if i==28 then return#c>0 and c or nil elseif h==17 then return b elseif i==14 then if#c>0 then
c=c:sub(1,-2)end elseif h and h>=32 and h<127 then c=c..string.char(h)end end end end;return m