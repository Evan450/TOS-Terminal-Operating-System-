local C="setData"local o,c=component,computer;local i,j,t=0x00ff00,0xaaaaaa,0xff0000
local p=o.list;local u=p("eeprom")()local function q(F,...)local G,H=pcall(o.invoke,u,F,...)
if G then return H end end
c.getBootAddress=function()return
(q("getData")or""):match("^[^\n]*")end;c.setBootAddress=function(F)return q(C,F)end;local function r(F)
local G,H=pcall(o.proxy,F)return G and H end
local b,x=r(p("gpu")()),p("screen")()if not x then b=nil end;local k,l,s,g=50,16,1,1
if b then pcall(b.bind,x)
local G,F,H=pcall(b.maxResolution)
if G and F and H then k,l=math.min(80,F),math.min(25,H)end;pcall(b.setResolution,k,l)G,F=pcall(b.getDepth)
if G and F then s=F end;pcall(b.setBackground,0)
pcall(b.setForeground,s<2 and 0xffffff or i)pcall(b.fill,1,1,k,l," ")end
local function a(F,G)if not b then return end
if
not
pcall(function()
b.setForeground(s<2 and 0xffffff or G)if g>l then b.copy(1,2,k,l-1,0,-1)g=l end
b.fill(1,g,k,1," ")b.set(1,g,tostring(F):sub(1,k))g=g+1 end)then b=nil end end
local function v(F)local u,G,o;repeat u,G,o=c.pullSignal(1e9)until u=="key_down"if F and
o==100 then q(C,"SKP:"..F)end;c.shutdown(true)end
local function m(F,G,H)
local I=(q("getData")or""):gsub("\nSRM:%S*","")q(C,I.."\nSRM:"..F)
a("SRM "..F.." - POST FAILED",t)if G then a(G,0xff6600)end
a("Any key reboots. Then run 'srm'",j)if H then a("d: other disk",j)end;c.beep(400,.4)for J=1,F:byte(2)-
48 do c.beep(900,.1)end;v(H)end
local function y(F)local I=r(F)if not I or not I.readSector then return end
local M,H=pcall(I.readSector,1)if
not M or type(H)~="string"or#H<40 or
H:sub(1,4)~="TBFS"or H:byte(5)~=1 then return end
local K,L=("<I4"):unpack(H,32),("<I4"):unpack(H,36)if L<1 then return end;local G={}for N=K+1,K+L do local P,O=pcall(I.readSector,N)
G[#G+1]=P and
type(O)=="string"and O or""end;G=table.concat(G)if
#G<5 then return end;local J=("<I4"):unpack(G)if J>0 and J<=#G-4 then return
G:sub(5,4+J)end end;a("TOS BIOS",i)if not load("return 1<<1")then
m("C1","Lua 5.3+ CPU: sneak-click it to switch")end;local function z(F)
local G,H=pcall(F.exists,"/init.lua")return G and H end
local d=c.getBootAddress()local D=d:match"^SKP:(.+)"local e,f,h
if d and d~=""then local F=r(d)if F then if F.readSector then h=y(d)elseif
F.exists and z(F)then e=F end end end
if not e and not h then for F in p("filesystem")do local G=r(F)
if G and z(G)then e,f,d=G,F,F;if F~=D then break end end end end;if not e and not h then
for F in p("drive",true)do local G=y(F)if G then h,f,d=G,F,F;break end end end;if not e and not h then
m("D2","Need an /init.lua disk or a TBFS drive")end;local A=false
if f then
a("Boot drive changed: "..f:sub(1,8),0xffaa00)a("Save it? Y=yes Shift+Enter=once other=halt",j)local G=
c.uptime()+30;local F
repeat
local I,K,J,H=c.pullSignal(G-c.uptime())
if I=="key_down"then
if H==42 or H==54 then F=true elseif J==89 or J==121 then
c.setBootAddress(f)a("Boot drive saved",i)f=nil elseif H==28 and F then A=true
a("One-time boot",i)f=nil else break end elseif I=="key_up"and(H==42 or H==54)then F=false end until not f or c.uptime()>=G;if f then a("Boot cancelled",t)v()end end;_G._BIOS_DEPTH=s;_G._BIOS_ONETIME=A;a("POST...",j)
if h then
local F,G=load(h,"=tbfs-boot","t")if not F then m("B3",G)end;a("POST OK",i)c.beep()a("Booting: raw drive "..
d:sub(1,8),j)_G._BIOS_CY=g
_G._TBFS_BOOT_DRIVE=d;local H,I=pcall(F)if not H then
a("TBFS boot failed: "..tostring(I),t)end;v()end;local w=e.open("/init.lua","r")if not w then
m("I5","cannot open /init.lua",d)end;local n={}repeat local F=e.read(w,4096)
if F then n[#n+1]=F end until not F;e.close(w)
n=table.concat(n)
if
n:find("TOS",1,true)and not e.exists("/tos/kernel/init.lua")then m("K4","/tos/kernel/init.lua is missing",d)end;local B,E=load(n,"=init.lua","t")if not B then m("I6",E,d)end
a("POST OK",i)pcall(c.beep)
a("Booting: ".. (e.getLabel()or d:sub(1,8)),j)_G._BIOS_CY=g;B(e)