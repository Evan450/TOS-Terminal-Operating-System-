local f=require("component")local h=require("computer")
local e=require("mouse")local g={}
g.commands={mousetest=function(b,a)a=a or print;local q=f.list("gpu")()if not q then
a("No GPU found — mousetest needs a screen.")return end;local c=f.proxy(q)local r=c.getScreen and
c.getScreen()or nil
local d,j=c.getResolution()if not d or d<28 or j<10 then
a("Screen too small for mousetest (need ~28x10).")return end;local u=
(c.getDepth and c.getDepth())or 1;local l=u>1
local function i(x,y)
pcall(c.setForeground,x or 0xFFFFFF)pcall(c.setBackground,y or 0x000000)end
local function s()i(0xFFFFFF,0x000000)c.fill(1,1,d,j," ")end
local t={{x=3,y=6,w=9,h=3,label="  RED  ",fg=0xFFFFFF,bg=l and 0xAA0000 or 0x000000,id="red"},{x=14,y=6,w=9,h=3,label=" GREEN ",fg=0x000000,bg=
l and 0x00AA00 or 0x000000,id="green"},{x=25,y=6,w=9,h=3,label="  QUIT ",fg=0xFFFFFF,bg=
l and 0x0000AA or 0x000000,id="quit"}}local m={}
for y,x in ipairs(t)do m[#m+1]=e.region(x.x,x.y,x.w,x.h,x.id)end
local function v(x)i(x.fg,x.bg)
for z=0,x.h-1 do c.fill(x.x,x.y+z,x.w,1," ")end;local y=x.x+
math.max(0,math.floor((x.w-#x.label)/2))
c.set(y,x.y+math.floor(x.h/2),x.label)end;local n="Click a button, scroll, or drag. (QUIT / q / ^Q to exit)"local o=0
local function w()s()
i(0x55FFFF,0x000000)c.set(2,2,"TOS Mouse Driver — demo")
i(0xAAAAAA,0x000000)
c.set(2,3,"require(\"mouse\") turns OC touch/scroll into clean events")for y,x in ipairs(t)do v(x)end;i(0xFFFFFF,0x000000)
c.fill(1,j,d,1," ")c.set(2,j,n:sub(1,d-2))end;local function k(x)n=x;i(0xFFFFFF,0x000000)c.fill(1,j,d,1," ")
c.set(2,j,n:sub(1,d-2))end;w()local p=true
while p do
local x=table.pack(h.pullSignal(1))local y=x[1]
if y=="key_down"then local z,A=x[3],x[4]if
A==1 or z==113 or z==81 or z==17 or A==68 then p=false end else
local z=e.parse(table.unpack(x,1,x.n))
if
z and(not r or not z.screen or z.screen==r)then
if z.type=="click"then local A=e.hit(m,z.x,z.y)
if A=="quit"then p=false elseif A then
k(("Clicked %s button  (cell %d,%d, mouse btn %d)"):format(A:upper(),z.x,z.y,z.button))else
k(("Click @ %d,%d  (button %d) — not on a button"):format(z.x,z.y,z.button))end elseif z.type=="scroll"then o=o+z.dir
k(("Scroll %s @ %d,%d  (net %d)"):format(
z.dir>0 and"up"or"down",z.x,z.y,o))elseif z.type=="drag"then
k(("Drag @ %d,%d  (button %d)"):format(z.x,z.y,z.button))elseif z.type=="drop"then
k(("Drop @ %d,%d"):format(z.x,z.y))end end end end;s()i(0xFFFFFF,0x000000)
c.set(1,1,"mousetest exited.")
a("mousetest exited. require(\"mouse\") is installed for your own tools.")end}return g