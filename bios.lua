local c,p=component,computer

local G,D,R=0x00ff00,0xaaaaaa,0xff0000
local l=c.list
local e=l("eeprom")()

local function E(m,...)local o,v=pcall(c.invoke,e,m,...)if o then return v end end

p.getBootAddress=function()return(E("getData")or""):match("^[^\n]*")end

p.setBootAddress=function(a)return E("setData",a)end

local function X(a)local o,x=pcall(c.proxy,a)return o and x end

local g,s=X(l("gpu")()),l("screen")()
if not s then g=nil end
local w,h,d,y=50,16,1,1
if g then
 pcall(g.bind,s)

 local o,a,b=pcall(g.maxResolution)
 if o and a and b then w,h=math.min(80,a),math.min(25,b)end
 pcall(g.setResolution,w,h)
 o,a=pcall(g.getDepth)if o and a then d=a end
 pcall(g.setBackground,0)
 pcall(g.setForeground,d<2 and 0xffffff or G)
 pcall(g.fill,1,1,w,h," ")
end

local function P(t,f)
 if not g then return end
 if not pcall(function()
  g.setForeground(d<2 and 0xffffff or f)
  if y>h then g.copy(1,2,w,h-1,0,-1)y=h end
  g.fill(1,y,w,1," ")g.set(1,y,tostring(t):sub(1,w))y=y+1
 end)then g=nil end
end

local function K()while p.pullSignal(1e9)~="key_down"do end p.shutdown(true)end

local function F(n,t)

 local x=(E("getData")or""):gsub("\nSRM:%S*","")
 E("setData",x.."\nSRM:"..n)
 P("SRM "..n.." - POST FAILED",R)
 if t then P(t,0xff6600)end
 P("Any key reboots. Then run 'srm'",D)
 p.beep(400,.4)
 for _=1,n:byte(2)-48 do p.beep(900,.1)end
 K()
end

local function T(x)
 local v=X(x)
 if not v or not v.readSector then return end
 local o,sc=pcall(v.readSector,1)
 if not o or type(sc)~="string"or #sc<40 or sc:sub(1,4)~="TBFS"or sc:byte(5)~=1 then return end
 local bs,bb=("<I4"):unpack(sc,32),("<I4"):unpack(sc,36)
 if bb<1 then return end
 local r={}
 for i=bs+1,bs+bb do
  local k,dd=pcall(v.readSector,i)
  r[#r+1]=k and type(dd)=="string"and dd or""
 end
 r=table.concat(r)
 if #r<5 then return end
 local n=("<I4"):unpack(r)
 if n>0 and n<=#r-4 then return r:sub(5,4+n)end
end

P("TOS BIOS",G)

if not load("return 1<<1")then F("C1","Lua 5.3+ CPU: sneak-click it to switch")end

local function ex(z)
 local k,r=pcall(z.exists,"/init.lua")
 return k and r
end
local a=p.getBootAddress()
local f,b,blob
if a and a~=""then
 local px=X(a)
 if px then
  if px.readSector then blob=T(a)
  elseif px.exists and ex(px)then f=px end
 end
end
if not f and not blob then
 for x in l("filesystem")do
  local z=X(x)
  if z and ex(z)then f,b,a=z,x,x break end
 end
end
if not f and not blob then

 for x in l("drive",true)do
  local z=T(x)
  if z then blob,b,a=z,x,x break end
 end
end
if not f and not blob then F("D2","Need an /init.lua disk or a TBFS drive")end

local one=false
if b then
 P("Boot drive changed: "..b:sub(1,8),0xffaa00)
 P("Save it? Y=yes Shift+Enter=once other=halt",D)
 local t=p.uptime()+30
 local sh
 repeat
  local ev,_,ch,k=p.pullSignal(t-p.uptime())
  if ev=="key_down"then
   if k==42 or k==54 then sh=true
   elseif ch==89 or ch==121 then
    p.setBootAddress(b)P("Boot drive saved",G)b=nil
   elseif k==28 and sh then
    one=true P("One-time boot",G)b=nil
   else break end
  elseif ev=="key_up"and(k==42 or k==54)then sh=false end
 until not b or p.uptime()>=t
 if b then P("Boot cancelled",R)K()end
end

_G._BIOS_DEPTH=d
_G._BIOS_ONETIME=one

P("POST...",D)

if blob then

 local fn,er=load(blob,"=tbfs-boot","t")
 if not fn then F("B3",er)end

 P("POST OK",G)p.beep()
 P("Booting: raw drive "..a:sub(1,8),D)
 _G._BIOS_CY=y

 _G._TBFS_BOOT_DRIVE=a
 local o2,e2=pcall(fn)
 if not o2 then P("TBFS boot failed: "..tostring(e2),R)end
 K()
end

if not f.exists("/tos/kernel/init.lua")then F("K4","/tos/kernel/init.lua is missing")end
local q=f.open("/init.lua","r")
if not q then F("I5","cannot open /init.lua")end

local z={}
repeat local x=f.read(q,4096)if x then z[#z+1]=x end until not x
f.close(q)

local fn,er=load(table.concat(z),"=init.lua","t")
if not fn then F("I6",er)end

P("POST OK",G)pcall(p.beep)
P("Booting: "..(f.getLabel()or a:sub(1,8)),D)
_G._BIOS_CY=y
fn(f)
