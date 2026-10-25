
local r,n,o,s="no keycard tape data","string","this card has no personal menu","this card's menu is empty"local m={}local p=60;local t=200;local u=400;local v=64;local w=5
function m.normalizeMenu(a,b)b=b or 1
local c={title="Menu",items={}}if type(a)~="table"then return c end
if
type(a.title)==n and#a.title>=1 and#a.title<=p then c.title=a.title end;if type(a.items)~="table"then return c end
for e,d in ipairs(a.items)do
if
type(d)==
"table"and type(d.label)==n and#d.label>=1 and#d.label<=p then
if type(d.run)==n and
#d.run>=1 and#d.run<=t and
not d.run:find("[\n\r]")then
c.items[#c.items+1]={label=d.label,run=d.run}elseif type(d.menu)=="table"and b<w then
local f=m.normalizeMenu(d.menu,b+1)if#f.items>0 then
c.items[#c.items+1]={label=d.label,menu=f}end elseif
type(d.info)==n and#d.info>=1 and#d.info<=u then
c.items[#c.items+1]={label=d.label,info=d.info}end end;if#c.items>=v then break end end;return c end
function m.resolveSelection(a,b)if
type(b)~="number"or not a or type(a.items)~="table"then return{type="none"}end
local c=a.items[b]if not c then return{type="none"}end;if c.run then
return{type="run",cmd=c.run,label=c.label}end
if c.menu then return{type="submenu",menu=c.menu}end
if c.info then return{type="info",text=c.info,label=c.label}end;return{type="none"}end
function m.clusterProfile()
return
m.normalizeMenu({title="Cluster helper",items={{label="Manager status",run="cluster-manager status"},{label="List bridge workers",run="cluster-manager workers"},{label="Drain (stop new work)",run="cluster-manager drain"},{label="Undrain (resume work)",run="cluster-manager undrain"},{label="Command help",run="cluster-manager help"}}})end
function m.readTapeMenu(a,b,c)
if type(a)~=n or#a<7+4+2+64 then return nil,r end
if a:sub(1,7)~="TAUTH2\0"then return nil,"not a tape-authenticator keycard"end
local function i(y,l)return y:byte(l)| (y:byte(l+1)<<8),l+2 end
local function f(y,l)return
y:byte(l)| (y:byte(l+1)<<8)|
(y:byte(l+2)<<16)| (y:byte(l+3)<<24),l+4 end;local d=8;local j;j,d=f(a,d)local g;g,d=i(a,d)d=d+g+64
if d+3 >#a then return nil,o end;local h;h,d=f(a,d)d=d+h;if d+3 >#a then return nil,o end;local e;e,d=f(a,d)if e==0 then
return nil,s end
if d+e-1 >#a then return nil,"menu region truncated"end;local k=a:sub(d,d+e-1)return m.decodeTapeMenuBlob(k,b,c)end
function m.decodeTapeMenuBlob(b,c,a)if
not(a and a.decrypt and a.isEncrypted)then return nil,"vault unavailable"end
if not
a.isEncrypted(b)then return nil,"menu region corrupt (not a vault blob)"end;local e,f=a.decrypt(b,c)
if not e then return nil,
"cannot decrypt menu (wrong passphrase?): "..tostring(f)end;local d={}
for g in e:gmatch("[^\n]+")do local h,i=g:match("^(.-)|(.+)$")if
h and#h>0 and i then d[#d+1]={label=h,run=i}end end;if#d==0 then return nil,s end;return
m.normalizeMenu({title="Tape toolbox",items=d})end;local x=64*1024
function m.readTapeMenuFromDrive(a,b,c)
if not
(a and a.read and a.seek and a.getSize)then return nil,"no tape drive"end;local d=a.getSize()or 0;if d<=0 then return nil,r end;if a.stop then
pcall(a.stop)end;a.seek(-d)
local function g(z)local B,A={},0;while A<z do
local D,C=pcall(a.read,math.min(8192,z-A))if not D or type(C)~=n or#C==0 then break end
B[#B+1]=C;A=A+#C end;return
table.concat(B)end
local function y(z,A)return z:byte(A)| (z:byte(A+1)<<8)end
local function i(z,A)return
z:byte(A)| (z:byte(A+1)<<8)|
(z:byte(A+2)<<16)| (z:byte(A+3)<<24)end;local h=g(13)if#h<13 then return nil,r end;if h:sub(1,7)~="TAUTH2\0"then return nil,
"not a tape-authenticator keycard"end
local j=y(h,12)if j>d then return nil,"label length implausible"end
a.seek(j+64)local e=g(4)if#e<4 then return nil,o end;local k=i(e,1)if k>d then
return nil,"log length implausible"end;a.seek(k)e=g(4)if#e<4 then return nil,o end
local f=i(e,1)if f==0 then return nil,s end
if f>d or f>x then return nil,"menu length implausible"end;local l=g(f)if#l<f then return nil,"menu region truncated"end;return
m.decodeTapeMenuBlob(l,b,c)end
local function q()local a=require("computer")return a.pullSignal(1)end
function m.run(a)a=a or{}local b=a.display;if not b or not b.getSize then return end
local g=a.runLine;local h=m.normalizeMenu(a.profile)
if a.title then h.title=a.title end;local c={h}local d=1;local function e()return b.getTheme()end
local function i(l,y)local z=e()
local A,B=b.getSize()b.clear(z.bg)
b.fill(1,1,A,1," ",z.bar_fg or z.fg,z.bar_bg or z.bg)
b.set(1,1," "..tostring(l):sub(1,A-2),z.bar_fg or z.fg,z.bar_bg or z.bg)local C=3
for E,D in ipairs(y or{})do if C>B-2 then break end;local F=type(D)=="table"and D[1]or
tostring(D)local G=type(D)=="table"and D[2]or
z.fg
b.set(2,C,tostring(F):sub(1,A-3),G,z.bg)C=C+1 end;b.fill(1,B,A,1,"░",z.dim or z.fg,z.bg)b.set(1,B,"▓▒░",z.dim or
z.fg,z.bg)if A>6 then
b.set(A-2,B,"░▒▓",z.dim or z.fg,z.bg)end
b.set(5,B," Press any key to return. ",z.dim or z.fg,z.bg)
while true do local D=q()if D=="key_down"or D=="touch"then return end end end
local function j()local l=e()local y,z=b.getSize()local C=c[#c]b.clear(l.bg)local A={}for G,F in ipairs(c)do A[#A+
1]=F.title end
local D=" "..table.concat(A," / ")
b.fill(1,1,y,1," ",l.bar_fg or l.fg,l.bar_bg or l.bg)
b.set(1,1,D:sub(1,y-1),l.bar_fg or l.fg,l.bar_bg or l.bg)local B=3
for F,G in ipairs(C.items)do local H=B+F-1;if H>z-2 then break end;local K=(F<=9)and
("["..F.."]")or"   "
local L=G.menu and"  >"or""local M=G.label..L;local I,J=l.fg,l.bg;if F==d then
I,J=l.bar_fg or l.bg,l.bar_bg or l.fg end;b.fill(2,H,y-2,1," ",I,J)
b.set(2,H,string.format(" %s %s",K,M):sub(1,
y-3),I,J)end;if#C.items==0 then
b.set(2,B,"(this menu is empty)",l.dim or l.fg,l.bg)end
local E=
(#c>1)and"Up/Down + Enter or click  ·  Backspace: up  ·  Q: quit"or"Up/Down + Enter or click  ·  number keys  ·  Q: quit"b.fill(1,z,y,1,"░",l.dim or l.fg,l.bg)b.set(1,z,"▓▒░",l.dim or
l.fg,l.bg)if y>6 then
b.set(y-2,z,"░▒▓",l.dim or l.fg,l.bg)end
b.set(5,z,(" "..E.." "):sub(1,math.max(0,y-10)),
l.dim or l.fg,l.bg)return B end
local function f(l)local z=c[#c]local y=m.resolveSelection(z,l)
if y.type=="run"then local A
if g then
local C,B=pcall(g,y.cmd)A=C and B or
{{"error: "..tostring(B),e().error or e().fg}}else
A={{"(no command runner wired)",
e().error or e().fg}}end;if type(A)~="table"or#A==0 then
A={{y.cmd,e().dim or e().fg},{"(no output)",
e().dim or e().fg}}end
i(y.label.."  —  $ "..y.cmd,A)elseif y.type=="submenu"then c[#c+1]=y.menu;d=1 elseif y.type=="info"then
i(y.label,{{y.text,e().fg}})end;return true end
local function k()if#c>1 then c[#c]=nil;d=1;return true end;return false end
while true do local A=j()local y,C,B,z=q()local l=c[#c]
if y=="key_down"then local D,E=B,z
if D==4 then return elseif D and
(D==113 or D==81)then return elseif E==200 then
d=(d>1)and(d-1)or math.max(1,#l.items)elseif E==208 then d=(d<#l.items)and(d+1)or 1 elseif E==28 then if
not f(d)then return end elseif E==14 then if not k()then return end elseif D and D>=49 and D<=57 then if
not f(D-48)then return end end elseif y=="touch"then local D=z
if type(D)=="number"then local E=D-A+1;if E>=1 and E<=#l.items then d=E;if not
f(E)then return end end end end end end;return m