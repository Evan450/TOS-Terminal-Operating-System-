local l,m="computer","tablet"local p=require(l)
local n=require("kernel.serialize")local j={}local o="/etc/tos.cfg"
local k={device=l,hostname="tos",compactUI=false,screenRes="auto",screenColsPerBlock=10,screenRowsPerBlock=4,powerProfile="balanced",lowBatWarn=15,critBatWarn=5,showBattery=false,autoLockout=true,maxAttempts=5,sessionTimeout=0,guestAccess=false,encryptComms=true,listenPort=42,internet=true,internetMaxKB=64,internetTimeout=15,headless=false,rackSlot=0,autoServices=true,verbose=false,timezone=0}local i={}
function j.init(a)j._fs=a;for f,g in pairs(k)do i[f]=g end;local b=n.loadFile(a,o)if b then for f,g in
pairs(b)do i[f]=g end end
local c=require("component")
local function e()local f=c.list(m)()if f then return m end
local g=c.list("gpu")()~=nil;local h=c.list("screen")()~=nil;local q=
c.list("keyboard")()~=nil
if not g and not h and not q then return"server"end;return l end;local d=e()i.device=d;if d==m then i.showBattery=true;if
b==nil or b.powerProfile==nil then i.powerProfile="save"end elseif d=="server"then
i.headless=true end
return true end;function j.save()return n.saveFile(j._fs,o,i)end;function j.get(a)if i[a]~=nil then return
i[a]end;return k[a]end
function j.set(a,b)i[a]=b end
function j.getAll()local a={}for b,c in pairs(i)do a[b]=c end;return a end;function j.isTablet()return i.device==m end;function j.isHeadless()
return i.headless==true end
function j.deviceType()return i.device or l end;function j.reset(a)i[a]=k[a]end;j.DEFAULTS=k;return j