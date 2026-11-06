local p="string"local k={}local i,l=nil,nil;local m=nil;local n=nil;local j={}function k.init(a)i,l=a.fs,a.log
m=a.bootAddr;n=a.layerAddr;j={}end
function k.sanitizeLabel(a,b)local d="disk_"..
tostring(b or"????"):sub(1,4)if type(a)~=p then return d end
local c=a:gsub("[^%w_%- ]","_")
c=c:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")if c==""then return d end;if#c>32 then c=c:sub(1,32)end;if
c=="."or c==".."then return d end;return c end
local function o(a)for d,c in ipairs(i.mounts and i.mounts()or{})do if c.mountPoint==a then return
true end end;if not
i.exists(a)then return false end
if not i.isDirectory(a)then return true end;local b=i.list(a)return type(b)=="table"and#b>0 end
function k.mount(a,b)if type(a)~=p or not b then return nil,"no disk"end;if not m then return nil,
"boot disk unknown"end
if a==m then return nil,"the boot disk"end;if a==n then return nil,"the overlay's write layer"end;if j[a]then return
j[a].mountPoint,j[a].label end;local d=nil;local g,e=pcall(function()
return b.getLabel()end)if
g and type(e)==p and e~=""then d=e end
local c="/mnt/"..k.sanitizeLabel(d,a)
if o(c)then local t=c.."_"..a:sub(1,4)local s,r=t,2;while o(s)and r<100 do
s=t.."_"..r;r=r+1 end;c=s end;local h,q=i.mount(c,b)if h==false then return nil,q end
local f=d or c:match("[^/]+$")j[a]={mountPoint=c,label=f}if l then
l.info("kernel","Mounted "..a:sub(1,8).." at "..c)end;return c,f end
function k.unmount(a)local b=j[a]if not b then return nil end;j[a]=nil
pcall(i.unmount,b.mountPoint)if l then
l.info("kernel","Unmounted "..
tostring(a):sub(1,8).." from "..b.mountPoint)end;return b.mountPoint,b.label end
function k.mountPointOf(a)local b=j[a]if b then return b.mountPoint,b.label end;return nil end;return k