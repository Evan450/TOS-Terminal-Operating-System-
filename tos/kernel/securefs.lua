
local U,V,S,M="  [E-401 ERR_PERM_DENIED]","Permission denied: ","securefs not initialized","securefs"local E={}local F=nil;local G=nil;local H=nil;local P=nil
function E.init(a)F=a.fs;G=a.users;H=a.log;P=a.process end
local function I(a)if a then return a end;if P and P.currentSession then local c=P.currentSession()
if c then return c end end;if G and G.currentSession then
local c=G.currentSession()if c then return c end end;local b=_G._TOS
if b and
b.bootSession and not b.bootCompleted then return b.bootSession end;return nil end;local N="Permission denied: invalid path  [E-401 ERR_PERM_DENIED]"
local function K(a,b)if not F or not G then return
false,S end;a=F.normalize(a)
if not a then return false,N end;local d=I(b)local e,c=G.canAccessAs(d,a,"r")
if not e then if H then
H.warn(M,"READ denied: "..a.." ("..
(c or"?")..")")end;return false,V..
(c or"access denied")..U,a end;return true,nil,a end;local Q;local L
local function J(a,b)if not F or not G then return false,S end;a=F.normalize(a)if
not a then return false,N end;local c=I(b)
if Q then local f=Q(a,c)
if f then if H then
H.warn(M,"WRITE denied (protected system path "..
f.."): "..a..
" -- root can lift this for one session with `protect off`")end;local g=""if
f==
"/usr/lib"or f=="/usr/modules"or f=="/usr/bin"or f=="/var/pkg"then
g=" — install add-ons with 'pkg install', not by copying files here"end;return
false,L("writing to",f,c)..g,a end end;local e,d=G.canAccessAs(c,a,"w")
if not e then if H then
H.warn(M,"WRITE denied: "..a..
" (".. (d or"?")..")")end;return false,V..
(d or"access denied")..U,a end;return true,nil,a end
function E.exists(a,b)local c,e,d=K(a,b)if not c then return false end;return F.exists(d)end
function E.isDirectory(a,b)local c,e,d=K(a,b)if not c then return false end;return F.isDirectory(d)end
function E.list(a,b)local g,h,e=K(a,b)if not g then return{},h end;a=e;local d=F.list(e)local c=I(b)local f=G.pathKey and
G.pathKey(a)or a
if f=="/home"then
if not c or
c.tier<G.TIER.ADMIN then local i={}if type(d)=="table"and c and c.user then
for k,j in
ipairs(d)do local l=j:gsub("/$","")if l==c.user then i[#i+1]=j end end end;return i end end
if f=="/var/mail"then
if not c or c.tier<G.TIER.ADMIN then local i={}
if
type(d)=="table"and c and c.user then for k,j in ipairs(d)do if j:gsub("/$","")==c.user then
i[#i+1]=j end end end;return i end end;return d end
function E.readFile(a,b)local c,d,e=K(a,b)if not c then return nil,d end;return F.readFile(e)end
function E.size(a,b)local c,e,d=K(a,b)if not c then return 0 end;return F.size(d)end
function E.lastModified(a,b)local c,e,d=K(a,b)if not c then return 0 end;return F.lastModified(d)end
function E.writeFile(a,b,c)local d,e,f=J(a,c)if not d then return false,e end;return F.writeFile(f,b)end
function E.writeFileAtomic(b,a,c)local e,f,d=J(b,c)if not e then return false,f end;if not F.writeFileAtomic then return
F.writeFile(d,a)end;return F.writeFileAtomic(d,a)end;function E.appendFile(a,b,c)local d,e,f=J(a,c)if not d then return false,e end
return F.appendFile(f,b)end
function E.makeDirectory(a,b)local c,d,e=J(a,b)if
not c then return false,d end;return F.makeDirectory(e)end
local _={"/tos","/etc","/init.lua","/bios.lua","/install.lua","/var","/usr","/var/pkg","/var/pkg/installed","/usr/modules","/usr/lib","/usr/bin","/lib","/bin"}local aa={"/home","/root","/public"}
local ab={["/etc/users.dat"]=true,["/etc/tos.cfg"]=true,["/etc/hostname"]=true,["/etc/motd"]=true,["/etc/profile"]=true,["/etc/critical.bak"]=true,["/etc/.tutorial_done"]=true,["/etc/peer_aliases.dat"]=true,["/etc/selftest.on"]=true,["/etc/cluster-master.cfg"]=true,["/etc/cluster-manager.cfg"]=true,["/etc/kiosk.cfg"]=true,["/etc/component_caps.cfg"]=true,["/etc/pkg_caps.cfg"]=true,["/etc/pkg_trust.cfg"]=true,["/etc/menu.cfg"]=true,["/etc/keys.cfg"]=true,["/etc/open.cfg"]=true,["/etc/chat-groups.cfg"]=true,["/etc/intercom.cues"]=true,["/etc/intercom.cfg"]=true,["/etc/jbod.cfg"]=true,["/etc/widgets"]=true,["/var/log"]=true,["/var/run"]=true,["/var/lib"]=true,["/var/cluster"]=true}local T=setmetatable({},{__mode="k"})local function W(a)if not a then return false end;return
T[a]==true end
function E.setOperatorOverride(a,b)if not G then
return false,S end;if not a then return false,"no session"end;local c=G.TIER
local d=a.tier;if not(c and d and d>=c.ROOT)then
return false,"Operator override requires root"end
if b then T[a]=true;if H then
H.warn(M,"Operator override ARMED by '"..

tostring(a.user).."' — protected system paths are writable ".."for this session")end else
T[a]=nil;if H then
H.info(M,"Operator override disarmed for '"..tostring(a.user).."'")end end;return true end;function E.operatorOverride(a)return W(a)end
function L(b,c,a)
local d="Refused: "..
b..
" "..c..

" is a protected system path. This guard sits above the permission ".."model and stops even an admin overwriting the kernel or its libraries."local e=G and G.TIER
local f=e and a and a.tier and a.tier>=e.ROOT
if f then
return
d..
"  You own this machine: `protect off` stands the guard ".."down for THIS SESSION ONLY (it ends at logout, and every path it "..
"allows is logged).  [E-402 ERR_PATH_PROTECTED]"end
return d..
"  Only root can lift it, with `protect off`, and only ".."for their own session.  [E-402 ERR_PATH_PROTECTED]"end
local ac={"/var/log/","/var/run/","/var/lib/","/var/cluster/","/etc/widgets/"}
local function X(a)if ab[a]then return nil end;for c,b in ipairs(ac)do
if a:sub(1,#b)==b then return nil end end
for c,b in ipairs(aa)do if a==b then return b end end;for c,b in ipairs(_)do
if a==b or a:sub(1,#b+1)==b.."/"then return b end end;return nil end
local function O(a,b)if type(a)~="string"then return"(invalid path)"end
if W(b)then if H then
H.warn(M,
"Operator override: allowing protected path "..tostring(a))end;return nil end;local d=X(a)if d then return d end
local c=G and G.pathKey and G.pathKey(a)if c and c~=a then return X(c)end;return nil end;Q=O
function E.removeRefusal(a,b)a=F.normalize(a)if not a then return N end;local c=O(a,I(b))if c then return
L("removing",c,I(b))end;return nil end
function E.remove(a,b)a=F.normalize(a)if not a then return false,N end;local c=O(a,I(b))if c then return
false,L("removing",c,I(b))end;local d,e=J(a,b)if not d then return
false,e end;return F.remove(a)end
function E.rename(b,c,a)local d=F.normalize(b)local e=F.normalize(c)if not d or not e then
return false,N end;local f=O(d,I(a))if f then
return false,L("renaming",f,I(a))end;local g=O(e,I(a))if g then
return false,L("renaming onto",g,I(a))end;local h,i,j=J(d,a)if not h then return false,i end
local k,l,m=J(e,a)if not k then return false,l end;return F.rename(j,m)end;local R=nil
local function ad()
if R==nil then local b,a=pcall(require,"kernel.process")R=
(b and
type(a)=="table"and a.yieldCooperative)and a or false end;if R then R.yieldCooperative()end end;local function ae(b,a)
return b==a or a=="/"or b:sub(1,#a+1)==a.."/"end
local function af(b,a,c)if ae(a,b)then
return false,"Cannot copy a directory into itself"end
if not F.exists(a)then
local f,g=F.makeDirectory(a)if not f then
return false,"Cannot create directory: "..tostring(g)end end;local e,d=0,0
for g,f in ipairs(E.list(b,c))do ad()
local h=f:match("^(.-)/?$")or f;if h~=""then
if E.copy(F.join(b,h),F.join(a,h),c)then e=e+1 else d=d+1 end end end;if d>0 then
return false,string.format("Copied %d items, %d failed",e,d)end;return true end
function E.copy(b,c,a)local g,h,d=K(b,a)if not g then return false,h end;local i,j,e=J(c,a)
if not i then return false,j end;if F.isDirectory(d)then return af(d,e,a)end;if F.copyFile then
return F.copyFile(d,e)end;local f,k=F.readFile(d)if not f then return false,k end;return
F.writeFile(e,f)end;local ag={r=true,rb=true}local Y={w=true,wb=true,a=true,ab=true}
function E.open(b,a,c)
a=a or"r"if not(ag[a]or Y[a])then
return nil,"Unsupported open mode: "..tostring(a)end;local e,f,g
if Y[a]then e,f,g=J(b,c)else e,f,g=K(b,c)end;if not e then return nil,f end;local d,h=F.open(g,a)if not d then return nil,h end
return
{read=function(j,i)return
d:read(i)end,write=function(j,i)return d:write(i)end,seek=function(k,i,j)
return d:seek(i,j)end,close=function()return d:close()end}end;function E.normalize(a)return F.normalize(a)end;function E.split(a)
return F.split(a)end;function E.join(...)return F.join(...)end;function E.spaceTotal(a)return
F.spaceTotal(a)end
function E.spaceUsed(a)return F.spaceUsed(a)end;function E.spaceFree(a)return F.spaceFree(a)end;function E.mounts()
return F.mounts()end
local function Z(a)
if not G or not G.TIER then return nil,"users module unavailable"end;local b=I(a)if not b then return nil,"no session"end;if b.tier<G.TIER.ADMIN then return nil,
"mount requires admin"end;return b end
function E.mount(a,b,c)if not F then return false,S end;local e,g=Z(c)
if not e then if H then
H.warn(M,"MOUNT denied: "..tostring(a).." ("..
g..")")end;return false,V..g..U end;local d=F.normalize(a)if not d then return false,N end;local f=O(d,e)if f then if H then
H.warn(M,
"MOUNT denied (protected system path "..f.."): "..d)end
return false,L("mounting over",f,e)end
return F.mount(d,b)end
function E.unmount(a,b)if not F then return false,S end;local d,c=Z(b)
if not d then if H then
H.warn(M,"UNMOUNT denied: "..tostring(a).." ("..
c..")")end;return false,V..c..U end;return F.unmount(a)end
function E.home(a)local b=I(a)if b then return b.home end;return"/tmp"end
function E.resolve(a,b)if a=="~"or a:sub(1,2)=="~/"then
return E.home(b)..a:sub(2)end;return a end
function E.forSession(a)local b={}
local c={"exists","isDirectory","list","readFile","makeDirectory","remove","size","lastModified","resolve"}
for f,e in ipairs(c)do local g=E[e]b[e]=function(h)return g(h,a)end end;local d={"writeFile","appendFile","open","rename","copy"}
for f,e in
ipairs(d)do local g=E[e]b[e]=function(h,i)return g(h,i,a)end end;b.home=function()return E.home(a)end
b.normalize=E.normalize;b.split=E.split;b.join=E.join;b.spaceTotal=E.spaceTotal
b.spaceUsed=E.spaceUsed;b.spaceFree=E.spaceFree
b.mounts=function()local g=E.mounts()or{}local e=I(a)
local h=
e and G and G.TIER and(e.tier or 0)>= (G.TIER.ADMIN or 2)local f={}
for k,j in ipairs(g)do local i={}for l,m in pairs(j)do i[l]=m end;if not h then
i.address=E.opaqueMountId(j.mountPoint,j.address)end;f[k]=i end;return f end;return b end
function E.opaqueMountId(a,b)local d,c=pcall(require,"kernel.crypto")
if d and c and c.hash then return
"fs:"..
c.hash(tostring(a).."|"..tostring(b)):sub(1,16)end;return"fs:"..tostring(a)end;E._isProtectedTarget=function(a,b)return Q(a,b)end;E._protectedMsg=function(a,b,c)
return L(a,b,c)end;return E