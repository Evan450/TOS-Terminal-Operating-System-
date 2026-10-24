
local aB,al,bc,aC,aN,bd,be,aO,bf="number","string","service","files[","requires[","^%s*(.-)%s*$","^[%w%.]+$","function","drowsy"local ak={}local aP,ay,au,aD;local ap="/var/pkg/installed"local aE="/etc/critical.bak"local an=nil
local am=nil;local av=nil;local ar=nil;local ao={}local bg=2;local bh=3
local function aF(a)if not ar then return true end
local b=(
type(a)=="table"and a.session)or nil
if not b and ar.currentSession then b=ar.currentSession()end
if not b then return false,"Insufficient privileges: admin required"end;if b.isKernel or b.isLogin then return true end;if type(b.tier)==aB and
b.tier>=bg then return true end;return false,
"Insufficient privileges: admin required"end;local aQ="/usr/lib/selftest/"
local function bi(a)if
type(a)~="table"or type(a.files)~="table"then return false end;for c,b in ipairs(a.files)do
if type(b)==al and b:lower():sub(1,
#aQ)==aQ then return true end end;return false end
local function aR(a,b)local d=bi(a)if
type(a)~="table"or(a.kind~=bc and not d)then return true end;if not ar then return true end
local c=(
type(b)=="table"and b.session)or nil
if not c and ar.currentSession then c=ar.currentSession()end;if c and c.isKernel then return true end;if c and type(c.tier)==aB and
c.tier>=bh then return true end
if a.kind~=bc then return false,

"this package installs a boot self-test check, which runs inside the ".."kernel when the battery is armed; only root may install one"end
return false,
"installing a service package runs its code as root at boot; ".."only root may install a service (this one runs outside the package sandbox)"end;ak._serviceInstallGate=aR
local aS={app=true,command=true,program=true,lib=true,service=true,runtime=true,driver=true,theme=true}
local function aG(a)if type(a)~=al then return false end
if a==""or#a>64 then return false end;if a=="."or a==".."then return false end;if#a==1 then return
a:match("^[%w]$")~=nil end;return
a:match("^[%w][%w%-]*[%w]$")~=nil end
local function aH(a)if type(a)~=al then return true end
if a:find("\0",1,true)then return true end;if a:find("\\",1,true)then return true end;for b in a:gmatch("[^/]+")do if
b=="."or b==".."then return true end end;return false end
local function bj(a)
if a:find("//",1,true)or a:sub(-1)=="/"then return false end
for b in a:gmatch("[^/]+")do if
not b:match("^[%w_%.%+%-]+$")or b:sub(-1)=="."then return false end end;return true end
local function az(a)return(tostring(a):lower())end;local aI={"/usr/","/var/pkg/"}
local bk={"/var/pkg/installed","/var/pkg/secrets","/var/pkg/remote"}
local function aT(a)local b=az(a)for d,c in ipairs(bk)do
if b==c or b:sub(1,#c+1)==c.."/"then return true end end;return false end
local function aU(a)if type(a)~=al or a==""then return false end
if aT(a)then return false end
for c,b in ipairs(aI)do if a:sub(1,#b)==b and#a>#b then return true end end;return false end
local bl={["10-discoveryd"]=true,["20-chatrelay"]=true,["20-fileshare"]=true,["20-rshd"]=true}
local bm={["tos"]=true,["boot"]=true,["pkg_trust"]=true,["pkg_caps"]=true,["pkg-repos"]=true,["component_caps"]=true,["netfs-exports"]=true,["kiosk"]=true,["menu"]=true,["keys"]=true,["jbod"]=true,["chat-groups"]=true}
local function aV(a)if type(a)~=al then return false end
local b=a:match("^/etc/rc%.d/([%w_%-]+)%.lua$")if b then return not bl[b:lower()]end
local c=a:match("^/etc/([%w_%-]+)%.cfg$")if c then return not bm[c:lower()]end;return false end
local function bn(a)return type(a)==al and a~=""and#a<=32 and
a:match("^[%w%.%-]+$")~=nil end;local aW=4
local function aX(a)if type(a)~=al or#a>200 then return false end
local c,b=a:match("^https?://([%w%.%-]+)(.*)$")
if not c or c:sub(1,1)=="."or c:sub(1,1)=="-"or
c:find("..",1,true)then return false end;local d,e=b:match("^:(%d+)(.*)$")
if d then if#d>5 then return false end;b=e end;if b==""then return true end;if not b:match("^/[%w%-%._~/%%+]*$")then
return false end;for f in b:gmatch("[^/]+")do
if f=="."or f==".."then return false end end;return true end
function ak.repoHints(a)local b,c={},{}
local function d(e)if type(e)~="table"then return end
for g,f in ipairs(e)do local h=type(f)==al and
(f:gsub("/+$",""))or nil;if
h and not c[h]then c[h]=true;b[#b+1]=h end end end;if type(a)~="table"then return b end;d(a.repos)
for f,e in
ipairs(type(a.requires)==
"table"and a.requires or{})do if type(e)=="table"then d(e.repos)end end;return b end
local function aJ(a)
if type(a)~="table"then return false,"manifest is not a table"end;if not aG(a.name)then
return false,"invalid name: "..tostring(a.name)end
if not bn(a.version)then return false,"invalid version: "..
tostring(a.version)end;if not aS[a.kind]then
return false,"invalid kind: "..tostring(a.kind)end;if type(a.files)~="table"then return false,
"missing files array"end
for d,c in ipairs(a.files)do if
type(c)~=al or c:sub(1,1)~="/"then return false,
aC..d.."] is not an absolute path"end;if aH(c)then
return false,
aC..d.."] contains an unsafe path segment"end
if not bj(c)then return false,
aC..d..
"] must use only letters, digits and _ . + - "..
"with no empty segment or trailing dot (got "..c..")"end
if aT(c)then
return false,aC..
d.."] is the package manager's own space ("..
c.."): installed manifests, package secrets and remote staging are not a package's to write"end
if not aU(c)and not(a.kind==bc and aV(c))then
return
false,aC..
d.."] must be under "..
table.concat(aI," or ").." (service packages may also write /etc/rc.d/<f>.lua and /etc/<name>.cfg) (got "..c..
")"end end
if a.fileMap~=nil then if type(a.fileMap)~="table"then
return false,"fileMap must be a table if present"end;local c={}
for e,d in ipairs(a.files)do c[d]=true end
for e,d in pairs(a.fileMap)do if type(e)~=al or type(d)~=al then return false,
"fileMap entries must be string -> string"end;if not
c[e]then
return false,"fileMap names a target not in files[]: "..e end
if d==""or d:sub(1,1)=="/"then return false,
"fileMap source must be a relative path: "..d end;if aH(d)then
return false,"fileMap source contains an unsafe path segment: "..d end end end;if a.lua~=nil and
(type(a.lua)~=al or not a.lua:match("^%d+%.%d+$"))then
return false,'lua must be a Lua version like "5.3" if present'end
if
a.tos~=nil and
(type(a.tos)~=al or not a.tos:match("^%s*[<>=~%^]*%s*%d"))then
return false,'tos must be a version constraint like ">=1.5.0" if present'end
if a.hashes~=nil then if type(a.hashes)~="table"then
return false,"hashes must be a table if present"end
for d,c in pairs(a.hashes)do
if
type(d)~=al or
type(c)~=al or#c~=64 or c:find("[^%x]")then return false,
"hashes['"..tostring(d).."'] is not a 64-hex digest"end end end
if a.critical~=nil then if type(a.critical)~="table"then
return false,"critical must be an array if present"end;for d,c in ipairs(a.critical)do
if type(c)~=al or
c:sub(1,1)~="/"or aH(c)then return false,"critical["..
d.."] is not a safe absolute path"end end end
if a.commands~=nil and type(a.commands)~="table"then return false,
"commands must be a table if present"end
if a.requires~=nil and type(a.requires)~="table"then return false,
"requires must be an array if present"end
if type(a.requires)=="table"then
for d,c in ipairs(a.requires)do
if type(c)=="table"and
c.key~=nil then
if type(c.key)~=al or#c.key~=64 or
c.key:find("[^%x]")then return false,
aN..d.."].key is not a 64-hex public key"end
if type(c.name)~=al or c.name==""then return false,aN..
d.."] pins a key but names no package"end end end end
local function b(c,d)if c==nil then return true end;if type(c)~="table"then return false,
d.." must be an array of repo URLs"end;local e=0
for f,g in pairs(c)do e=
e+1;if type(f)~=aB or not aX(g)then
return false,d.."["..
tostring(f).."] is not an http(s) repo URL"end end;if e>aW then
return false,d.." names more than "..aW.." repos"end;return true end
do local c,d=b(a.repos,"repos")if not c then return false,d end
for f,e in
ipairs(
type(a.requires)=="table"and a.requires or{})do
if type(e)=="table"and e.repos~=nil then if
type(e.name)~=al or e.name==""then
return false,aN..f.."] names repos but no package"end
local g,h=b(e.repos,aN..f.."].repos")if not g then return false,h end end end end
if a.recommends~=nil then
if type(a.recommends)~="table"then return false,
"recommends must be an array of package names if present"end;for d,c in ipairs(a.recommends)do
if type(c)~=al or c==""then return false,"recommends["..
d.."] is not a package name"end end end
if a.conflicts~=nil then
if type(a.conflicts)~="table"then return false,
"conflicts must be an array of package names if present"end
for e,d in ipairs(a.conflicts)do
if type(d)~=al or d==""then return false,"conflicts["..
e.."] is not a package name"end;if d==a.name then
return false,"conflicts["..e.."] lists the package itself"end end end
if a.handles~=nil then
if
type(a.handles)~="table"or#a.handles>8 then return false,"handles must be an array of at most 8 entries if present"end;local c=0;for d in
pairs(type(a.commands)=="table"and a.commands or{})do c=c+1 end
for e,d in ipairs(a.handles)do
local f="handles["..e.."]"
if
type(d)~="table"or type(d.ext)~="table"or#d.ext==0 or#d.ext>8 then return false,
f..".ext must list 1 to 8 extensions"end
for h,g in ipairs(d.ext)do
if type(g)~=al or not g:match("^[%w]+$")or
#g>8 then return false,
f.." names an extension that is not 1-8 letters or digits"end end
if d.as~=nil and d.as~="native"and d.as~="open"then return false,f..
'.as must be "native" or "open"'end
if d.markers~=nil then
if
type(d.markers)~="table"or#d.markers==0 or#d.markers>8 then return false,
f..".markers must list 1 to 8 line prefixes"end;if d.as=="native"then
return false,f.." has markers, so it is not the package's own format"end
for h,g in ipairs(d.markers)do
if
type(g)~=al or#g<2 or#g>24 or g:find("[%c]")then return false,f..
" has a marker that is not 2-24 plain characters"end end end
if d.cmd~=nil then
if
type(d.cmd)~=al or type(a.commands)~="table"or not a.commands[d.cmd]then return false,f..
".cmd is not one of the package's commands"end elseif c~=1 then return false,
f.." names no cmd, and the package has "..c.." commands"end end end
if
a.capabilities~=nil and type(a.capabilities)~="table"then return false,"capabilities must be an array if present"end
if a.screen~=nil then if type(a.screen)~="table"then
return false,"screen must be a table { width=, height= } if present"end
local c,d=a.screen.width,a.screen.height;if type(c)~=aB or c<1 or c~=math.floor(c)or
type(d)~=aB or d<1 or
d~=math.floor(d)then
return false,"screen.width/height must be positive integers"end;if
a.screen.mode~=nil and a.screen.mode~="exact"and
a.screen.mode~="min"then
return false,"screen.mode must be 'exact' or 'min'"end end
if a.provides~=nil then if type(a.provides)~="table"then
return false,"provides must be an array if present"end;for c,d in ipairs(a.provides)do
if not aG(d)then return false,
"provides["..c.."] is not a valid name"end end end
if a.license~=nil then if type(a.license)~="table"then
return false,"license must be a table if present"end
if a.license.requireKey~=nil and
type(a.license.requireKey)~="boolean"then return false,
"license.requireKey must be boolean"end
if a.license.keys~=nil then if type(a.license.keys)~="table"then return false,
"license.keys must be an array"end;for d,c in
ipairs(a.license.keys)do
if type(c)~=al or#c~=64 or c:find("[^%x]")then return false,"license.keys["..d..
"] is not a 64-hex digest"end end end end;return true end
function ak.parseCap(a)if type(a)~=al then return nil,"not a string"end
a=a:match(bd)if a==""then return nil,"empty"end;local c=a:find(":",1,true)
if not c then if
a:match(be)then return{facet=a}end;return nil,"invalid facet: "..a end;local b=a:sub(1,c-1)local d=a:sub(c+1)if b==""then
return nil,"empty facet before ':'"end;if not b:match(be)then
return nil,"invalid facet: "..b end
if d==""then return nil,"empty scope after ':'"end;return{facet=b,scope=d}end
function ak.init(a)an=a.fs;am=a.log;ar=a.users;av=require("kernel.serialize")if ay then
ay=false
for b,c in pairs(aD)do if rawget(ak,b)==c then rawset(ak,b,nil)end end end;if not an then
return false,"fs module required"end
if not an.exists(ap)then
local b,c=an.makeDirectory(ap)if not b and am then
am.warn("pkg","Could not create "..ap..": "..tostring(c))end end;ak.scan()if am then local b=0;for c in pairs(ao)do b=b+1 end
am.info("pkg","Package manager initialized ("..b..
" installed)")end;return true end
function ak.scan()for c in pairs(ao)do ao[c]=nil end
if not an.exists(ap)then return 0 end;local b=an.list(ap)or{}local a=0
for d,c in ipairs(b)do local e=c:gsub("/$","")
if e~=""and
aG(e)then local g=an.join(ap,e,"package.lua")
local f,h=av.loadFile(an,g)
if type(f)=="table"then local i,j=aJ(f)
if i then if f.name==e then ao[f.name]=f;a=a+1 elseif am then
am.warn("pkg",
"Manifest name '"..f.name.."' does not match dir '"..e.."'")end elseif am then
am.warn("pkg",
"Invalid manifest at "..g..": "..tostring(j))end elseif h and am then
am.warn("pkg","Failed to load "..g..": "..tostring(h))end end end;return a end
function ak.list()local a={}for c,b in pairs(ao)do
a[#a+1]={name=b.name,version=b.version,kind=b.kind,description=b.description,enabled=ak.isEnabled(c)}end
table.sort(a,function(c,d)return c.name<
d.name end)return a end;function ak.info(a)return ao[a]end
function ak.isEnabled(a)if not ao[a]then return false end
local b=an.join(ap,a,"state")if not an.exists(b)then return true end;local c=an.readFile(b)if not c then return
true end;return c:sub(1,1)~="d"end
function ak.setEnabled(a,b,c)local d,e=aF(c)if not d then return false,e end;if not ao[a]then return false,
"not installed: "..a end
local f=an.join(ap,a,"state")return an.writeFile(f,b and"e"or"d")end
function ak.commands()local a={}
for c,b in pairs(ao)do
if
ak.isEnabled(c)and type(b.commands)=="table"then for d,e in pairs(b.commands)do
if type(d)==al and type(e)==al then a[d]=e end end end end;return a end
function ak.ownerOfCommand(a)if type(a)~=al then return nil end;for b,c in pairs(ao)do
if
type(c.commands)=="table"and type(c.commands[a])==al and
ak.isEnabled(b)then return b end end;return nil end;local as={}local bo=2;local bp=48*1024;local at,aw={},0;local function bq()
local b,a=pcall(require,"computer")
return
b and type(a)=="table"and type(a.freeMemory)==aO and a.freeMemory()<bp end
local function br(a)local b={}for c in
pairs(as)do b[#b+1]=c end;if#b<=a then return end
table.sort(b,function(c,d)return(at[c]or 0)> (
at[d]or 0)end)for c=a+1,#b do as[b[c]]=nil;at[b[c]]=nil end end
local aY={["fs.read"]=true,["fs.write"]=true,component=true,["compat.io"]=true,load=true,net=true,swap=true,internet=true,vault=true,crypto=true,notify=true,["peripheral.modem"]=true,["peripheral.redstone"]=true,["peripheral.robot"]=true,["peripheral.inventory"]=true,["peripheral.tape"]=true,["peripheral.tractor"]=true,["peripheral.piston"]=true,["peripheral.hologram"]=true,["peripheral.printer"]=true}local aZ="/etc/pkg_caps.cfg"local aA={}local aq={}local aK=false
local function a_()if aK then return end;aK=true
if not an or not
an.exists or not an.exists(aZ)then return end;local b=an.readFile(aZ)
if not b or#b==0 or#b>8192 then if am then
am.warn("pkg","pkg_caps.cfg unreadable or oversized — overrides NOT in force")end;return end;local d=av or require("kernel.serialize")
local e,a=pcall(d.decode,b,{maxBytes=8192})
if not e or type(a)~="table"then if am then
am.warn("pkg","pkg_caps.cfg did not decode — overrides NOT in force")end;return end;local function c(g)
return type(g)==al and#g<=64 and g:match(be)~=nil end;if type(a.allow)=="table"then
for h,g in
ipairs(a.allow)do if c(g)and g~="legacy"then aA[g]=true end end end
if
type(a.deny)=="table"then
for f,g in pairs(a.deny)do if
type(f)==al and#f<=64 and type(g)=="table"then local h=aq[f]or{}
for j,i in ipairs(g)do if c(i)then h[i]=true end end;aq[f]=h end end end end
function ak.runCaps()local a={}for b in pairs(aY)do a[b]=true end;return a end
function ak.reloadCapConfig()aA,aq,aK={},{},false;a_()return aA,aq end
function ak.capAllowed(b,a)if type(a)~=al then return false,"invalid facet"end;a_()local c=(
aq["*"]and aq["*"][a])or
(b and aq[b]and aq[b][a])if c then
return false,"denied by /etc/pkg_caps.cfg"end;if aY[a]then return true end
if aA[a]then return true end;return false,"not a package-grantable capability"end
local function ba(a,b)local c={}
if type(b.capabilities)=="table"then
for e,d in ipairs(b.capabilities)do
local f=ak.parseCap(d)
if f and f.facet then local g,h=ak.capAllowed(a,f.facet)if g then c[f.facet]=true elseif am then
am.warn("pkg",
"capability '"..
f.facet.."' refused for "..a..": "..tostring(h))end end end end;return c end
function ak.capsForFile(a)local b=ak.ownerOfFile(a)if b and ak.isEnabled(b)then
return ba(b,ao[b]),b end;return nil end
function ak.ownerOfFile(a)if type(a)~=al or a==""then return nil end
local b=az(an.normalize and
an.normalize(a)or a)for d,c in pairs(ao)do
if type(c.files)=="table"then for f,e in ipairs(c.files)do if
type(e)==al and az(e)==b then return d end end end end
return nil end
function ak.noteServiceStarted(a,b)local d=aF(b)if not d then return nil end;if type(a)~=al or not
a:match("^[%w_%-%.]+$")then return nil end;local c=ak.ownerOfFile(
"/etc/rc.d/"..a..".lua")if not c or
ak.isEnabled(c)then return nil end
if ak.setEnabled(c,true,b)then return c end;return nil end
local function bs(a,c,b)if as[a]then aw=aw+1;at[a]=aw;return as[a]end
br(bq()and 0 or(bo-1))if not an.exists(b)then return nil end;local f=an.readFile(b)if not f then
return nil end;local g=ba(a,c)
local j,e=pcall(require,"kernel.sandbox")if not j or not e or not e.build then return nil end
local k=e.build({caps=g,pkgName=a})local h,l=load(f,"=pkg:"..a,"t",k)
if not h then if am then
am.warn("pkg","command load error in "..a..": "..
tostring(l))end;return nil end;local m,d=pcall(h)
if not m or type(d)~="table"then if am then
am.warn("pkg","entry failed in "..a..": "..
tostring(d))end;return nil end;local i={}
for o,n in pairs(d.commands or{})do
if type(n)==aO then
i[o]=function(...)
local s,r=pcall(require,"kernel.process")
local p=(s and r and r.current)and r.current()or nil;if not p then return n(...)end;local t=p.caps;p.caps=g
local q=table.pack(pcall(n,...))p.caps=t;if not q[1]then error(q[2],0)end
return table.unpack(q,2,q.n)end end end;d.commands=i;as[a]=d;aw=aw+1;at[a]=aw;return d end;local aL=true
function ak.setDispatchEnabled(a)aL=a and true or false end;function ak.dispatchEnabled()return aL end
function ak.getCommand(a)if not aL then return nil end;if type(a)~=
al then return nil end
for c,b in pairs(ao)do
if type(b.commands)=="table"then
local d=b.commands[a]
if type(d)==al and ak.isEnabled(c)then local e=bs(c,b,d)if
e and type(e.commands)==
"table"and type(e.commands[a])==aO then return e.commands[a]end end end end;return nil end
function ak.getCommandScreen(a)if type(a)~=al then return nil end
for c,b in pairs(ao)do
if

type(b.commands)=="table"and b.commands[a]~=nil and
type(b.screen)=="table"and ak.isEnabled(c)then return
{width=b.screen.width,height=b.screen.height,mode=b.screen.mode or"exact"}end end;return nil end
function ak.getCommandFullscreen(a)if type(a)~=al then return false end;for c,b in pairs(ao)do
if
type(b.commands)==
"table"and b.commands[a]~=nil and ak.isEnabled(c)then return b.fullscreen==true end end;return false end;local bt={drowsy=true,always=true,freeze=true}
function ak.getCommandBackground(a)if type(a)~=al then
return bf end
for c,b in pairs(ao)do
if type(b.commands)=="table"and
b.commands[a]~=nil and ak.isEnabled(c)then
local d=b.background;if type(d)==al and bt[d]then return d end;return bf end end;return bf end
function ak.flushCommandCache(a)if a then as[a]=nil;at[a]=nil else as={}at={}end end
function ak.capabilities(a)local b=ao[a]if
not b or type(b.capabilities)~="table"then return{}end;local c={}
for e,d in ipairs(b.capabilities)do
local f,g=ak.parseCap(d)if f then c[#c+1]=f elseif am then
am.warn("pkg","Bad capability '"..tostring(d)..
"' in "..a..": "..tostring(g))end end;return c end
local function ax(a)if type(a)~=al then return nil end
local c,d=a:match("^([%d%.]+)%-?(.*)$")if not c then return nil end;local b={}for e in c:gmatch("[^%.]+")do
b[#b+1]=tonumber(e)or 0 end;return b,d end
function ak.compareVersion(c,d)local e,a=ax(c)local f,b=ax(d)if not e or not f then return 0 end;local g=math.max(#e,#
f)for h=1,g do local i,j=e[h]or 0,f[h]or 0;if i<j then return-1 end;if i>j then
return 1 end end;if a==""and b==""then
return 0 end;if a==""then return 1 end;if b==""then return-1 end
if a<b then return-1 end;if a>b then return 1 end;return 0 end
function ak.satisfiesConstraint(b,a)if not a or a==""then return true end;a=a:match(bd)
local c,d=a:match("^(>=?)(.+)$")if not c then c,d=a:match("^(<=?)(.+)$")end;if not c then
c,d=a:match("^(==?)(.+)$")end
if not c then c,d=a:match("^(%^)(.+)$")end;if not c then c,d=a:match("^(~)(.+)$")end
if not c then c="=="d=a end;d=d:match(bd)local e=ak.compareVersion(b,d)
if c==">"then return e>0 end;if c==">="then return e>=0 end;if c=="<"then return e<0 end
if c=="<="then return e<=0 end;if c=="="or c=="=="then return e==0 end
if c=="^"then
if e<0 then return false end;local f=ax(b)local g=ax(d)if not f or not g then return false end;return(f[1]or 0)== (
g[1]or 0)end
if c=="~"then if e<0 then return false end;local f=ax(b)local g=ax(d)
if not f or not g then return false end;return
(f[1]or 0)== (g[1]or 0)and(f[2]or 0)== (g[2]or 0)end;return false end
local function aM(a)if ao[a]then return ao[a]end;for c,b in pairs(ao)do
if type(b.provides)=="table"then for c,d in
ipairs(b.provides)do if d==a then return b end end end end;return nil end
function ak.checkRequires(a)local c=ao[a]if not c then return false,{a}end;if
type(c.requires)~="table"then return true,{}end;local b={}
for e,d in ipairs(c.requires)do local g,f,h
if
type(d)=="table"then g=d.name;f=d.version;h=d.optional elseif type(d)==al then
local i,j=d:match("^(%S+)%s+(.+)$")if i then g,f=i,j else g,f=d,nil end;h=false end
if g then local i=aM(g)
if not i then if not h then b[#b+1]=g..
(f and(" ("..f..")")or"")end elseif f then if not ak.satisfiesConstraint(
i.version or"0.0.0",f)then
b[#b+1]=g..
" "..f..
" (have "..
(i.version or"?").." via ".. (i.name or"?")..")"end end end end;return#b==0,b end
function ak.resolveInstallOrder(b,a)local d={}local e={}local c={}
local function f(i,j,k)if c[i]then return true end;if e[i]then return false,
"dependency cycle through "..i end;local l=a(i,j,k)if not l then return false,
"unknown package: "..i end;e[i]=true
if
type(l.requires)=="table"then
for n,j in ipairs(l.requires)do local o,p
if type(j)=="table"then
o,p=j.name,j.optional elseif type(j)==al then o=j:match("^(%S+)")end;if o then
if not aM(o)and not(p and not a(o,j,i))then
local q,r=f(o,j,i)if not q then return false,r end end end end end;e[i]=nil;c[i]=true
local m=(l.name and l.name~="")and l.name or i;if not c[m]or m==i then c[m]=true;d[#d+1]=m end;return true end;local g,h=f(b)if not g then return nil,h end;return d end
function ak.criticalFiles()local b={}local a={}
for d,c in pairs(ao)do
if type(c.critical)=="table"then for d,e in
ipairs(c.critical)do
if type(e)==al and not b[e]then b[e]=true;a[#a+1]=e end end end end;table.sort(a)return a end
function ak.syncCriticalBackup()local a=ak.criticalFiles()if#a==0 then
return false,"no critical files declared by any package"end;local b=av.loadFile(an,aE)
if type(b)==
"table"and#b==#a then local e=true
for f=1,#a do if b[f]~=a[f]then e=false;break end end;if e then return true,"already in sync"end end;local c,d=av.saveFile(an,aE,a)
if c and am then
am.info("pkg","Critical-files backup updated: "..
#a.." entries")elseif not c and am then
am.warn("pkg","Failed to update critical backup: "..tostring(d))end;return c,d end;ak.PKG_ROOT=ap;ak.CRITICAL_BACKUP=aE;ak.VALID_KINDS=aS
ak._validateManifest=aJ;ak._isUnderPkgWriteRoot=aU;ak._isServiceEtcTarget=aV;ak.PKG_WRITE_ROOTS=aI
au={}
for a in
([[
DEFAULT_REPO_ROOTS _loadAnyManifest _protectedTargetRefusal _signGate
_verificationGate addRepo checkSignature computeLicenseHash
describeConflicts describeContradictions discoveredPolicy exportDisk
findConflicts findInRepos foreignDefaultCaps forgetModules forgetRepo
install installByName installFromFloppy installRemote installWithDeps
knownRepos listAllAvailable listRemoteAvailable listRepo outdated plan
planByName removeRepo repoRoots repos runInstaller runtimeRefusal
searchRemote signPackage signingKey trustAdd trustDiscovered trustList
trustRemove trustRequire trustRequired uninstall upgrade
verifyLicenseKey
]]):gmatch("%S+")do au[a]=true end;ak._OPS_NAMES=au
local bb=
(debug and debug.getinfo and
(debug.getinfo(1,"S").source or""):match("^@(.*[/\\])"))or nil
function aP()local b,a=pcall(require,"kernel.pkgops")
if not b and bb and
tostring(a):find("not found",1,true)then
local d=loadfile(bb.."pkgops.lua")if d then b,a=pcall(d)end end;if not b or type(a)~=aO then
error(tostring(a or"kernel.pkgops did not load"),0)end;local c={}for d in pairs(au)do
c[d]=rawget(ak,d)end
a(ak,{PKG_ROOT=ap,adminGate=aF,findProvider=aM,serviceInstallGate=aR,targetKey=az,validRepoHint=aX,validateManifest=aJ,fs=an,log=am,serialize=av,installed=ao})aD={}for d in pairs(au)do
if c[d]~=nil then rawset(ak,d,c[d])else aD[d]=rawget(ak,d)end end;ay=true end
setmetatable(ak,{__index=function(b,a)if not au[a]or ay then return nil end;local c,d=pcall(aP)if c then return
rawget(b,a)end;if a:match("^[%u_]+$")then return nil end
return function()
return false,
"the package manager's operations could not load: "..tostring(d)end end})
do local a=rawget(_G,"_TOS")
if a and a.fs and not an then if a.pkgDispatchDisabled then
ak.setDispatchEnabled(false)end
if
pcall(ak.init,{fs=a.fs,log=a.logObj,event=a.event,users=a.users})then pcall(ak.syncCriticalBackup)end end end;return ak