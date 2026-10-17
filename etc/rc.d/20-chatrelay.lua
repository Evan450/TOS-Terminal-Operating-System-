local o=false;local l=nil;local m=64;local p={}local n=1;local k=0;local function q(a,b,c)p[n]={from=a,text=b,time=c}
n=(n%m)+1;if k<m then k=k+1 end end
local function r()local b=_G._TOS and
_G._TOS.net;if not b then return end;o=true
local c=b.getProtocol()local e=require("computer")local a={}local f=5;local g=20;local d=512
l=b.on(c.TYPE.MSG,function(i,h)
if not o then return end;local v=e.uptime()local j=a[h]
if not j then a.__order=a.__order or{}
if
#a.__order>=256 then local y=table.remove(a.__order,1)if y~=nil then a[y]=nil end end;a.__order[#a.__order+1]=h;j={windowStart=v,count=0}
a[h]=j end
if(v-j.windowStart)>f then j.windowStart=v;j.count=0 end;j.count=j.count+1;if j.count>g then return end;local u=""if i.payload then
u=type(i.payload)==
"string"and i.payload or
(i.payload.text or tostring(i.payload))end;if type(u)~="string"then u=tostring(
u or"")end
if#u>d then u=u:sub(1,d)end;local w="?"local x=b.findPeer(h)
if x and x.hostname then w=x.hostname end
q(w.." ("..h:sub(1,8)..")",u,v)
pcall(b.send,h,c.makePacket(c.TYPE.MSG_ACK,{ref=i.seq},{to=h}))if _G._TOS and _G._TOS.log then
_G._TOS.log("chat","["..w.."] "..u)end end)end;local function s()o=false
if l then local a=_G._TOS and _G._TOS.net;if a then local b=a.getProtocol()
a.off(b.TYPE.MSG,l)end;l=nil end end
local function t()if k==0 then
return{}end;local a={}local b=k<m and 1 or n;for c=0,k-1 do
local d=((b-1+c)%m)+1;if p[d]then a[#a+1]=p[d]end end;return a end
return{start=r,stop=s,deps={},restart=true,caps={net=true},needs="net",user="_kernel_",getHistory=t}