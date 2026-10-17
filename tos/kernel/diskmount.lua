local n="string"local j={}local h,k=nil,nil;local l=nil;local i={}
function j.init(a)h,k=a.fs,a.log;l=a.bootAddr;i={}end
function j.sanitizeLabel(a,b)
local d="disk_"..tostring(b or"????"):sub(1,4)if type(a)~=n then return d end;local c=a:gsub("[^%w_%- ]","_")
c=c:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")if c==""then return d end;if#c>32 then c=c:sub(1,32)end;if
c=="."or c==".."then return d end;return c end
local function m(a)for d,c in ipairs(h.mounts and h.mounts()or{})do if c.mountPoint==a then return
true end end;if not
h.exists(a)then return false end
if not h.isDirectory(a)then return true end;local b=h.list(a)return type(b)=="table"and#b>0 end
function j.mount(a,b)if type(a)~=n or not b then return nil,"no disk"end;if not l then return nil,
"boot disk unknown"end
if a==l then return nil,"the boot disk"end;if i[a]then return i[a].mountPoint,i[a].label end;local d=nil;local g,e=pcall(function()return
b.getLabel()end)if g and
type(e)==n and e~=""then d=e end;local c="/mnt/"..
j.sanitizeLabel(d,a)
if m(c)then
local s=c.."_"..a:sub(1,4)local r,q=s,2;while m(r)and q<100 do r=s.."_"..q;q=q+1 end;c=r end;local o,p=h.mount(c,b)if o==false then return nil,p end
local f=d or c:match("[^/]+$")i[a]={mountPoint=c,label=f}if k then
k.info("kernel","Mounted "..a:sub(1,8).." at "..c)end;return c,f end
function j.unmount(a)local b=i[a]if not b then return nil end;i[a]=nil
pcall(h.unmount,b.mountPoint)if k then
k.info("kernel","Unmounted "..
tostring(a):sub(1,8).." from "..b.mountPoint)end;return b.mountPoint,b.label end
function j.mountPointOf(a)local b=i[a]if b then return b.mountPoint,b.label end;return nil end;return j