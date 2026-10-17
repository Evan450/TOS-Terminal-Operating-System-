local v=require("kernel.display")
local function y()
local b,a=pcall(require,"kernel.screen")
if b and a and a.invalidateAll then pcall(a.invalidateAll)end;if v.invalidateColors then pcall(v.invalidateColors)end end;local J=require("computer")local z=require("component")local u={}
local K={x=1,y=1,blink=false}local C={}local A=nil
local function D()if A==nil then local b,a=pcall(require,"kernel.screen")
A=(b and type(a)==
"table")and a or false end;return A or nil end
local function E()local a=D()if not(a and a.callerSeat)then return nil end
local b,c=pcall(a.callerSeat)return b and c or nil end;local function w()local b=E()if b==nil then return K end;local a=C[b]
if not a then a={x=1,y=1,blink=false}C[b]=a end;return a end;local function B()
local a=E()if a==nil then return nil end;local c=D()local d,b=pcall(c.seatDevices,a)
return(d and
type(b)=="table")and b or{}end
local F={}
local function L(a)local b={}
function b.getSize()local d,c,e=pcall(a.getResolution)if
d and type(c)=="number"then return c,e end;return v.getSize()end;function b.set(c,d,e)pcall(a.set,c,d,e)end;function b.fill(c,d,e,f,g)
pcall(a.fill,c,d,e,f,g or" ")end
function b.clear()local d,e=b.getSize()
local c=v.getTheme and v.getTheme()
pcall(a.setBackground,c and c.bg or 0x000000)pcall(a.fill,1,1,d,e," ")end
function b.scrollUp(c,d)local e,f=b.getSize()c,d=c or 1,d or f;if d-c<1 then return end;pcall(a.copy,1,c+1,e,d-c,0,
-1)
pcall(a.setBackground,0x000000)pcall(a.setForeground,0xFFFFFF)
pcall(a.fill,1,d,e,1," ")end;function b.getGpu()return a end;return b end
local function x()local a=B()if not(a and a.gpu)then return v end;local c,d=pcall(function()
return v.getGpu().address end)if c and d==
a.gpu then return v end;local b=F[a.gpu]
if not b then
local f,e=pcall(z.proxy,a.gpu)if not(f and e)then return v end;b=L(e)F[a.gpu]=b end;return b end;function u.isAvailable()return true end
function u.getViewport()return x().getSize()end;function u.clear()x().clear()local a=w()a.x,a.y=1,1;y()end
function u.setCursor(a,b)
local d=w()d.x=math.floor(tonumber(a)or 1)d.y=math.floor(tonumber(b)or
1)end;function u.getCursor()local a=w()return a.x,a.y end;function u.setCursorBlink(a)
w().blink=not not a end;function u.getCursorBlink()return w().blink end
function u.write(a,b)
a=tostring(a)local g=x()local i,j=g.getSize()local d=w()local function l()
while d.y>j do g.scrollUp(1,j)d.y=d.y-1 end end;local k=nil;local e=nil
local function f()if e and#e>0 then
g.set(k,d.y,table.concat(e))e=nil;k=nil end end
for c=1,#a do local h=a:sub(c,c)
if h=="\n"then f()d.x=1;d.y=d.y+1;l()elseif h=="\r"then f()d.x=1 elseif h=="\t"then f()local n=8- ((
d.x-1)%8)
local m=string.rep(" ",math.min(n,i-d.x+1))
if#m>0 and d.x<=i then g.set(d.x,d.y,m)d.x=d.x+#m end else if d.x>i and b then f()d.x=1;d.y=d.y+1;l()end
if
d.x<=i and d.y<=j then if not e then k=d.x;e={}end;e[#e+1]=h;d.x=d.x+1 end end end;f()y()end;function u.clearLine()local a=x()local c=a.getSize()local b=w()a.fill(1,b.y,c,1," ")
b.x=1;y()end
local G={set=true,fill=true,copy=true,bitblt=true,setBackground=true,setForeground=true,setPaletteColor=true,setResolution=true,setViewport=true,setDepth=true,bind=true,setActiveBuffer=true,allocateBuffer=true,freeBuffer=true,freeAllBuffers=true}
local function H()local b=nil
pcall(function()b=x().getGpu()end)if b then return b end;local c=B()local a
if c then a=c.gpu else a=z.list("gpu")()end;if not a then return nil end;local d,e=pcall(z.proxy,a)if d then return e end;return nil end
local function M(a)if type(a)=="function"then return true end;local b=type(a)=="table"and
getmetatable(a)return
type(b)=="table"and b.__call~=nil end
local function I(a)if not H()then return nil end
return
setmetatable({},{__index=function(c,b)
if G[b]and not a then return
function()return false,"gpu."..
b.." requires a display capability"end end;local d=H()if not d then return nil end;local e=d[b]
if M(e)then
if G[b]then return
function(...)
local f=table.pack(d[b](...))y()return table.unpack(f,1,f.n)end end;return function(...)return d[b](...)end end;return e end,__newindex=function()
error("term.gpu() proxy is read-only",2)end,__metatable=false})end;function u.gpu()return I(false)end;function u._gpuForCaps(a)
local b=(a and
(a["gpu"]or a["display"]))and true or false;return I(b)end
function u.screen()local a=B()if a then
return a.screen end;local b=z.list("screen")()return b end;local function N()if coroutine.isyieldable and coroutine.isyieldable()then return
coroutine.yield()end
return J.pullSignal(0.5)end
function u.read(c,a,d,b)if a==nil then
a=true end;local e=""local f=w()local g,h=f.x,f.y;local i=x()local l=i.getSize()
local function j()f.x=g
f.y=h;local m=b and string.rep(b,#e)or e;local n=l-g+1;if n>0 then
i.fill(g,h,n,1," ")end;i.set(g,h,m)f.x=g+#m end;local k=nil
while true do if k~=e then j()k=e end;local m=table.pack(N())local n=m[1]
if
n=="key_down"then local o=m[3]or 0;local p=m[4]or 0
if o==13 or o==10 then
if a then f.x=1;f.y=f.y+1 end;if b then local q=e;e=""
pcall(function()if type(collectgarbage)=="function"then
collectgarbage("collect")end end)return q end;return e elseif o==8 or
p==14 then if#e>0 then e=e:sub(1,-2)end elseif o==3 then
if a then f.x=1;f.y=f.y+1 end;return nil elseif o==4 then if#e==0 then return nil end elseif o>=32 and o<127 then
e=e..string.char(o)end elseif n=="clipboard"then local o=m[3]
if o then o=o:gsub("\0","")
local p=o:find("\n",1,true)if p then e=e..o:sub(1,p-1)j()if a then f.x=1;f.y=f.y+1 end;return e else
e=e..o end end end end end;return u