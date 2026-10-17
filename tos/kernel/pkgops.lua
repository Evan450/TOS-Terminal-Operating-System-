
local r,x,y,z,A,s,B,t,C,u,D,E,F,v,w,G,H="string","command","package.lua","cluster-manager","trusted","unknown","no signature","kernel.pkgsign","the installed ","refusing to upgrade '","/etc/rc.d/",".disabled","kernel.crypto","unsigned","refusing to install '","no manifest in ","function"
return
function(a,b)local R,f,K=b.PKG_ROOT,b.adminGate,b.findProvider
local S,m=b.serviceInstallGate,b.targetKey;local aa,L=b.validRepoHint,b.validateManifest
local c,d,k,e=b.fs,b.log,b.serialize,b.installed;local i
local function M(al)local am={}if type(al)~="table"then return am end
for ao,an in pairs(al)do
if type(ao)==r and
ao~=""then local ap=nil;if
type(an)==r and an~=""and an:sub(1,1)~="/"then ap=an end
am[#am+1]={name=ao,version=ap,optional=false}end end;return am end;local ab="/usr"
local function ac(al)if type(al)~=r or al==""then return nil end
if
al:sub(1,2)=="//"then return"/"..al:gsub("^/+","")end;return ab.."/"..al:gsub("^/+","")end;local function T(al)return
(tostring(al):gsub("/+$",""):match("([^/]+)$"))end
local function ad(am,al,an)
if type(al)~=
"table"then return nil,"programs.cfg entry is not a table"end
local ao={name=am,version=al.version or"0.0.0",kind=al.kind or x,files={},fileMap={},requires=M(al.dependencies),commands=al.commands,capabilities=al.capabilities,description=al.description or
al.note,author=al.author or al.authors,hashes=al.hashes,_srcBase=an}
if type(al.files)~="table"then return nil,"programs.cfg entry '"..
tostring(am).."' has no files table"end;local ap={}
for aq,ar in pairs(al.files)do
if type(aq)==r and type(ar)==r then
if
aq:sub(1,1)==":"then ap[#ap+1]=aq:sub(2)else local at=ac(ar)local as=T(aq)
if at and as and as~=""then local au=
(at:gsub("/+$","")).."/"..as
ao.files[#ao.files+1]=au;ao.fileMap[au]=aq:gsub("^/+","")end end end end
if#ap>0 then
return nil,
"package '"..tostring(am)..
"' uses OPPM directory-copy entries ("..table.concat(ap,", ")..
"); TOS installs a declared file list — list the files individually"end
if#ao.files==0 then return nil,"programs.cfg entry '"..
tostring(am).."' lists no installable files"end;return ao end;local N=64*1024;local ae=64*1024
local function p(al)local am=c.size and c.size(al)
if type(am)==
"number"and am>N then return nil,"manifest too large ("..
am.." bytes; at most "..N..")"end;local an,ao=c.readFile(al)if type(an)~=r then return nil,ao end
local ap,aq=k.decode(an,{maxBytes=N,maxCost=ae,maxKeys=1024})return ap,aq,an end
local function af(al)local an=T(al)if not an then return nil end
local ao=al:gsub("/+$",""):match("^(.*)/[^/]+$")local am={}if ao and ao~=""then
am[#am+1]={path=c.join(ao,"programs.cfg"),root=ao}end
am[#am+1]={path=c.join(al,"programs.cfg"),root=al}
for aq,ap in ipairs(am)do
if c.exists(ap.path)then local ar,at,au=p(ap.path)
if type(ar)~="table"then return nil,
"programs.cfg parse error: "..tostring(at)end;local as=ar[an]
if type(as)~="table"then local av,aw=nil,0
for ax,ay in pairs(ar)do if type(ax)==r and
type(ay)=="table"then av,aw=ax,aw+1 end end;if aw==1 and ap.root==al then an,as=av,ar[av]end end
if type(as)=="table"then local av,aw=ad(an,as,ap.root)
if not av then return nil,aw end;return av,nil,ap.path,au end end end;return nil end
local function j(al)
local function an(au,av,aw,ax)if type(au)=="table"then au._srcBase=nil
au._sigState,au._sigKey,au._sigLabel=nil,nil,nil end;return au,av,aw,ax end;local ao=c.join(al,y)if c.exists(ao)then local au,av,aw=p(ao)if au then
return an(au,"native",ao,aw)end
return nil,"package.lua parse error: "..tostring(av)end
local ap=c.join(al,"package.oppm.lua")
if c.exists(ap)then local aw,ax,ay=p(ap)if not aw then return nil,
"package.oppm.lua parse error: "..tostring(ax)end
local az,au=next(aw)if not au or type(au)~="table"then
return nil,"OPPM manifest has no top-level package entry"end
local av={name=az,version=au.version or"0.0.0",kind=au.kind or x,files={},requires={},commands=au.commands,capabilities=au.capabilities,description=au.description,author=au.author,critical=au.critical,hashes=au.hashes}
if type(au.files)=="table"then
for aB,aA in pairs(au.files)do
if type(aB)=="number"and
type(aA)==r then av.files[#av.files+1]=aA elseif type(aB)==r and
type(aA)==r then av.files[#av.files+1]=aA end end end;av.requires=M(au.dependencies)return an(av,"oppm",ap,ay)end;local am=al:match("([^/]+)/?$")
if am then
local au=c.join(al,am..".cfg")
if c.exists(au)then local aw,az,aA=p(au)if not aw then return nil,
am..".cfg parse error: "..tostring(az)end;local av,ay=aw,am
if aw[am]and
type(aw[am])=="table"then av=aw[am]elseif not aw.files then local aC,aB=next(aw)if
type(aB)=="table"then ay,av=aC,aB end end
if type(av)~="table"then return nil,am..".cfg has no package table"end
local ax={name=av.name or ay,version=av.version or"0.0.0",kind=av.kind or x,files={},requires={},commands=av.commands,capabilities=av.capabilities,description=av.description,author=av.author,hashes=av.hashes}
if type(av.files)=="table"then for aB,aC in pairs(av.files)do
if type(aC)==r then
ax.files[#ax.files+1]=aC elseif type(aB)==r then ax.files[#ax.files+1]=aB end end end;ax.requires=M(av.dependencies)return an(ax,"oppm",au,aA)end end;local aq,ar,as,at=af(al)if aq then return aq,"oppm",as,at end
if ar then return nil,ar end;return nil,
"no package.lua, package.oppm.lua, <name>.cfg or programs.cfg entry for "..al end;local ag={"compat.io","fs.read","fs.write","component"}
function a.foreignDefaultCaps()
local al={}for am,an in ipairs(ag)do al[am]=an end;return al end
function a.findConflicts(al,am)local an={}if type(al)~="table"then return an end
for aq,ap in
ipairs(al.conflicts or{})do if ap~=am and e[ap]then
an[#an+1]={kind="declared",other=ap,detail=tostring(al.name)..
" declares a conflict with "..ap}end end
for ap,aq in pairs(e)do
if ap~=al.name and ap~=am then
for as,ar in ipairs(aq.conflicts or{})do if
ar==al.name then
an[#an+1]={kind="declared",other=ap,detail=ap.." declares a conflict with "..tostring(al.name)}end end end end;local ao={}
for ap,aq in pairs(e)do if ap~=al.name and ap~=am then for as,ar in ipairs(aq.files or{})do
ao[m(ar)]=ap end end end
for aq,ap in ipairs(al.files or{})do local ar=ao[m(ap)]if ar then
an[#an+1]={kind="file",other=ar,detail=ap,path=ap}end end;return an end;local U="/tos/system_manifest.lua"
local ah={kernel=true,shell=true,compat=true,peripheral=true,system_manifest=true}
local ai={mail={mail=true},mailapp={mail=true},intercom={intercom=true},intercomapp={intercom=true},blockfs={blockfs=true},mouse={mouse=true},[z]={[z]=true},cluster={[z]=true,["cluster-master"]=true,["cluster-storage"]=true},["rbmk-cmd"]={["rbmk-control"]=true}}local aj={"/usr/lib/","/usr/modules/"}
local function O(al,am)
if type(al)~="table"or
type(al.files)~="table"then return nil end;local ao={}local ap=k and k.loadFile(c,U)
if type(ap)=="table"then
for ar,aq in ipairs(ap)do if
type(aq)=="table"and type(aq.path)==r then
ao[m(aq.path)]=true end end elseif d then
d.warn("pkg","cannot read "..U.."; system files are not protected from packages")end;local an={}for ar,aq in pairs(e)do
for ar,as in ipairs(aq.files or{})do an[m(as)]=true end end;for ar,aq in ipairs(am or{})do
an[m(aq)]=true end
for ar,aq in ipairs(al.files)do local as=m(aq)if ao[as]then return tostring(aq)..
" is a TOS system file"end
for ar,at in
ipairs(aj)do
if as:sub(1,#at)==at then
local au=(as:sub(#at+1):match("^([^/]+)")or""):gsub("%.lua$","")if ah[au]then
return tostring(aq)..
" would be loaded by the kernel as its own '"..au.."' module"end;local av=ai[au]
if av and
not av[al.name]then local aw={}for ax in pairs(av)do aw[#aw+1]=ax end
table.sort(aw)
return tostring(aq)..
" is the '"..au..
"' library, which the shell ".."runs with full system authority; only "..table.concat(aw," / ")..
" may provide it"end end end;if
as:sub(1,5)=="/etc/"and not an[as]and c.exists(aq)then
return tostring(aq).." already exists and no installed package owns it"end end;return nil end;a._protectedTargetRefusal=O
local function n(al)if
type(al)~="table"or type(al.key)~=r then return nil end;if al.state~=A and al.state~=s then
return nil end;return al.key:lower()end
local function g(al,am)if type(al)~=r then return B end;local ao,an=pcall(require,t)local ap=(ao and an and
an.fingerprint)and an.fingerprint(al)or
al:sub(1,16)if
ao and an and an.labelForKey and not am then
am=an.labelForKey(al)end;return
(am and("'"..am.."'")or
"an untrusted key").." ("..ap..")"end
local function o(al)
if type(al)=="table"then
local am=(type(al.key)==r and#al.key==64 and not
al.key:find("[^%x]"))and
al.key:lower()or nil
return al.name,al.version,al.optional and true or false,am elseif type(al)==r then local am,an=al:match("^(%S+)%s+(.+)$")if am then
return am,an,false,nil end;return al,nil,false,nil end;return nil end
local function P(al)if type(al)~=r then return nil end;local ap,am=pcall(require,t)
if not ap or
type(am)~="table"or not am.readSig or
not am.sigPathFor then return nil end
if am.init then am.init({fs=c,serialize=k,log=d})end;local an=am.sigPathFor(al)
local ao=an and am.readSig(an)or nil;return ao and ao.key or nil end;local function Q(al)
return type(al)=="table"and type(al._sigKey)==r and
al._sigKey:lower()or nil end
local function q(an,ap,al,am,ao)local ar={}local aq,as,au,at=o(ap)if
not aq or type(al)~="table"then return ar end
if
as and not a.satisfiesConstraint(
al.version or"0.0.0",as)then
ar[#ar+1]={kind="version",name=aq,id="version|"..aq.."|"..as,text=string.format("%s requires '%s' %s, and %s is %s",an,aq,as,ao,tostring(al.version))}end
if at and am~=at then
ar[#ar+1]={kind="publisher",name=aq,id="publisher|"..aq.."|"..at,text=string.format("%s requires '%s' signed by %s, and %s has %s",an,aq,g(at),ao,
am and g(am)or B)}end;return ar end
local function V(al,am)local ao,an={},{}local ap={[al.name]=true}
for ar,aq in ipairs(type(al.provides)=="table"and
al.provides or{})do if not
e[aq]then ap[aq]=true end end;for aq in pairs(e)do an[#an+1]=aq end;table.sort(an)
for ar,aq in ipairs(an)do
local as=e[aq]
if aq~=al.name and type(as.requires)=="table"then
for ar,at in
ipairs(as.requires)do local au=o(at)
if au and ap[au]then for ar,av in
ipairs(q(C..aq,at,al,am,"the "..
tostring(al.name).." being put in"))do av.kind,av.id="breaks","breaks|"..aq.."|"..av.id
ao[#ao+1]=av end end end end end;return ao end
function a.outdated(al)al=al or{}local am={}
for ao,an in ipairs(a.listAllAvailable()or{})do
local ap=e[an.name]
if ap and an.version and ap.version then if
a.compareVersion(an.version,ap.version)>0 then
am[#am+1]={name=an.name,from=ap.version,to=an.version,dir=an.dir,root=an.root}end end end
table.sort(am,function(an,ao)return an.name<ao.name end)return am end
function a.upgrade(al,am)am=am or{}local aB,aC=f(am)if not aB then return false,aC end;local an=e[al]
if
not an then return false,"not installed: "..tostring(al)end;local aq,aS=a.findInRepos(al,am.extraRoots)if not aq then
return false,"no source for "..al..
" on any repo or inserted disk"end;local ao,aD,aE,aF=j(aq)if not ao then return false,
"unreadable manifest for "..al end
local as=a.compareVersion(
ao.version or"0.0.0",an.version or"0.0.0")
if as==0 and not am.force then return false,
string.format("%s is already at %s",al,tostring(an.version))end
if as<0 and not am.force then return false,
string.format("%s on the disk is OLDER (%s < %s) — pass force to downgrade",al,tostring(ao.version),tostring(an.version))end;local aG,aH=a._verificationGate(ao,am.allowUnverified)if not aG then return
false,aH end
local aI,aJ=a.verifyLicenseKey(ao,am.licenseKey)
if not aI then return false,"license check failed: "..tostring(aJ)end;local at=a.findConflicts(ao,al)
if#at>0 and not am.force then return false,
"conflicts: "..
a.describeConflicts(at).."  [E-613 ERR_PKG_CONFLICT]"end;local aK,aL=L(ao)if not aK then
return false,"invalid manifest: "..tostring(aL)end;local aM,aN=S(ao,am)if not aM then return false,
u..al.."': "..aN end;local au=O(ao)
if au then return false,
u..al.."': "..au..
"  [E-612 ERR_PKG_PROTECTED_TARGET]"end;local av,aw=a._signGate(aE,am,aF)if aw then
return false,u..al.."': "..aw end;local ax;local ap=
type(an._sigKey)==r and an._sigKey:lower()or nil
if ap then local aT=n(av)
if aT~=ap then
if not
am.force then
return false,

string.format("refusing to upgrade '%s': the installed version is signed by %s, and the "..

"candidate in %s has %s. An upgrade does not change who publishes a package; "..
"if the publisher really changed keys, confirm the new fingerprint with them ".."over another channel, then use --force.",al,g(ap,an._sigLabel),tostring(aq),
aT and("a different key: "..g(aT))or"no valid signature").."  [E-611 ERR_PKG_WRONG_PUBLISHER]"end;if d then
d.warn("pkg","Upgrading '"..
al.."' to a different publisher (--force): "..
g(ap,an._sigLabel).." -> "..g(aT))end else ax=ap end end
do
local function aU(aW,aX)local aY={}
for a_,aZ in
ipairs(type(aW.requires)=="table"and aW.requires or{})do local ba,a_,bb=o(aZ)
if ba and ba~=al then local bc=K(ba)
if bc then for a_,bd in
ipairs(q(al..
" "..tostring(aW.version),aZ,bc,Q(bc),C..tostring(bc.name)))do aY[#aY+1]=bd end elseif not bb then
aY[
#aY+1]={kind="missing",name=ba,id="missing|"..ba,text=string.format("%s %s requires '%s', which is not installed (install it first)",al,tostring(aW.version),ba)}end end end;for a_,aZ in ipairs(V(aW,aX))do aY[#aY+1]=aZ end;return aY end;local aV={}
for aX,aW in ipairs(aU(an,Q(an)))do aV[aW.id]=true end;local aT={}for aX,aW in ipairs(aU(ao,n(av)))do
if not aV[aW.id]then aT[#aT+1]=aW end end
if#aT>0 then
local aW=a.describeContradictions(aT)
if not am.force then return false,u..al.."': "..aW end;if d then
d.warn("pkg","Upgrading '"..al.."' past contradictions (--force): "..aW)end end end;local ay=a.isEnabled(al)local az={}
for aU,aT in ipairs(an.files or{})do
local aV=tostring(aT):match("^/etc/rc%.d/(.+)%.lua$")if aV then az[aV]=c.exists(D..aV..E)end end;local aA={}for aU,aT in ipairs(ao.files or{})do aA[aT]=true end
local ar={}
for aU,aT in ipairs(an.files or{})do if not aA[aT]then ar[#ar+1]=aT end end
local aO,aP=a.uninstall(al,{session=am.session,_internalUpgrade=true})if not aO then
return false,"could not remove the old version: "..tostring(aP)end
local aQ,aR=a.install(aq,{session=am.session,upgrading=true,force=am.force,allowUnverified=am.allowUnverified,licenseKey=am.licenseKey,allowUnsigned=am.allowUnsigned,expectKey=ax,_priorFiles=an.files})
if not aQ then return false,
"upgrade FAILED after removing "..al..": "..
tostring(aR).." — reinstall it from the disk"end;pcall(a.setEnabled,al,ay,{session=am.session})
for aU,aT in
pairs(az)do local aV=D..aU..E
if aT and not c.exists(aV)then
pcall(c.writeFile,aV,"1")elseif not aT and c.exists(aV)then pcall(c.remove,aV)end end;if d then
d.info("pkg",string.format("Upgraded %s %s -> %s (%d file(s) dropped)",al,tostring(an.version),tostring(ao.version),
#ar))end;return true,
{name=al,from=an.version,to=ao.version,dropped=ar,origin=aD,enabled=ay}end
function a.forgetModules(al)local am=package and package.loadedFrom;if
type(am)~="table"or type(al)~="table"then return 0 end
local ao={}for aq,ap in ipairs(al)do ao[ap]=true end;local an=0
for ap,aq in pairs(am)do if ao[aq]then package.loaded[ap]=
nil;am[ap]=nil;an=an+1 end end;return an end
function a.describeConflicts(al)local am={}
for ao,an in ipairs(al or{})do
if an.kind=="file"then
am[#am+1]=string.format("%s is already installed by %s",an.path,an.other)else am[#am+1]=an.detail end end;return table.concat(am,"; ")end
function a.verifyLicenseKey(al,am)if
type(al)~="table"or type(al.license)~="table"then return true end;if not al.license.requireKey then
return true end;if type(am)~=r or am==""then
return false,"license key required"end;local an;do local aq,ar=pcall(require,F)
if aq then an=ar end end
if
not an or not an.hash or not an.ctEquals then return false,"crypto unavailable for license verification"end;local ao=an.hash(al.name.."|"..am)
local ap=al.license.keys or{}
for ar,aq in ipairs(ap)do if an.ctEquals(ao,aq)then return true end end;return false,"license key rejected (no matching hash)"end
local function W(al,am,an)
if not al then return{state=v,reason="manifest path unknown"},nil end;local aq,ap=pcall(require,t)if not aq or not ap then return
{state=v,reason="signature support unavailable"},nil end
ap.init({fs=c,serialize=k,log=d})local ao=ap.verifyManifest(al,an)
if ao.state=="invalid"then
return ao,
w..
tostring(al)..

"': its signature does not verify ("..
tostring(ao.reason).."). This is tampering or corruption, not a missing signature, and there is no override."..
"  [E-609 ERR_PKG_SIGNATURE_INVALID]"end
if ap.requiresSignature()and not am.allowUnsigned then
if ao.state==v then
return
ao,
"refusing to install an unsigned package: this machine is set to ".."require signatures (pkg trust require off, or --allow-unsigned for one install)."..
"  [E-610 ERR_PKG_SIGNATURE_REQUIRED]"end
if ao.state==s then
return ao,
w..
tostring(al)..
"': its signature is valid but the key is not trusted here, and this machine "..

"is set to require signatures. Trust the publisher with 'pkg trust add <name> "..
tostring(ao.key)..
"' (fingerprint "..
tostring(ao.fingerprint)..

" -- compare it with the publisher over a channel that is NOT this package), "..
"or use --allow-unsigned for one install.".."  [E-610 ERR_PKG_SIGNATURE_REQUIRED]"end end;return ao,nil end;a._signGate=W
function a._verificationGate(al,am)local ap=(al and al.files)or{}local an=type(al and
al.hashes)=="table"local ao=an;if an then
for as,ar in ipairs(ap)do if
type(al.hashes[ar])~=r then ao=false;break end end end
if ao then return true,nil,true end;if am then return true,nil,false end
local aq=
an and"manifest is missing hashes for some files"or"manifest declares no file hashes"
return false,
"refusing to install unverified package '"..
tostring(al and al.name).."' ("..
aq..
"). Re-run with --allow-unverified to override.".."  [E-607 ERR_PKG_UNVERIFIED]",false end
function a.install(am,al)al=al or{}local ay,az=f(al)if not ay then return false,az end
if type(am)~=r or am==
""then return false,"invalid source directory"end;am=c.normalize(am)local an,at,aA,aB=j(am)if not an then return false,G..
am..": "..tostring(at)end
if at=="oppm"then
an.origin="openos"
if
type(an.capabilities)~="table"or#an.capabilities==0 then an.capabilities=a.foreignDefaultCaps()an.capsFromCompat=true
if d then
d.warn("pkg",
"Foreign (OpenOS/OPPM) package '"..
tostring(an.name).."' declared no capabilities — granting the compat surface: "..
table.concat(an.capabilities,", "))end end;if d then
d.info("pkg","Loaded OPPM-compat manifest for "..tostring(an.name))end end;local aC,aD=a.verifyLicenseKey(an,al.licenseKey)
if not aC then return false,
"license check failed: "..tostring(aD)end;local aE,aF=L(an)
if not aE then return false,"invalid manifest: "..aF end;local aG,aH=S(an,al)if not aG then return false,aH end
do
local aK=a.runtimeRefusal(an)if aK and not al.force then return false,aK end;if aK and d then
d.warn("pkg",
"Installing past a runtime requirement (force): "..aK)end end
if e[an.name]and not al.upgrading then local aK=e[an.name].version
local aL=a.compareVersion(
an.version or"0.0.0",aK or"0.0.0")
if aL>0 then return false,
string.format("%s %s is already installed and %s is newer — use `pkg upgrade %s`",an.name,tostring(aK),tostring(an.version),an.name)end
return false,"already installed (uninstall first): "..an.name end
do local aK=O(an,al._priorFiles)if aK then
return false,w..
tostring(an.name).."': "..aK..
"  [E-612 ERR_PKG_PROTECTED_TARGET]"end end
local aq=a.findConflicts(an,al.upgrading and an.name or nil)if#aq>0 and not al.force then
return false,"conflicts: "..
a.describeConflicts(aq).."  [E-613 ERR_PKG_CONFLICT]"end;if#aq>0 and d then
d.warn("pkg",
"Installing "..tostring(an.name)..
" over conflicts (--force): "..a.describeConflicts(aq))end
do
local aK,aL,aM=a._verificationGate(an,al.allowUnverified)if not aK then return false,aL end
if
not aM and al.allowUnverified and d then
d.warn("pkg","Installing UNVERIFIED package '"..
tostring(an.name).."' (no/partial hashes) — operator override")end end;local ap
do local aK,aL=W(aA,al,aB)if aL then return false,aL end
if
type(al.expectKey)==r and n(aK)~=al.expectKey:lower()then
return false,

string.format(
"refusing to install '%s': it must be signed by %s, ".."and this copy has %s",tostring(an.name),g(al.expectKey),
n(aK)and g(n(aK))or"no valid signature").."  [E-611 ERR_PKG_WRONG_PUBLISHER]"end;ap=aK
if d then
if aK.state==A then
d.info("pkg","'"..
tostring(an.name).."' signed by trusted publisher '"..
tostring(aK.label)..
"' ("..tostring(aK.fingerprint)..")")elseif aK.state==s then
d.warn("pkg","'"..
tostring(an.name).."' is signed by an UNTRUSTED key "..

tostring(aK.fingerprint).." — 'pkg trust add <name> "..tostring(aK.key).."'")else
d.warn("pkg","'"..
tostring(an.name).."' is UNSIGNED — installed on admin privilege alone")end end end;local ar=nil
if type(an.hashes)=="table"then local aL,aK=pcall(require,F)
if
not aL or not aK or not aK.hash or not aK.ctEquals then return false,
"crypto unavailable; cannot verify install hashes"end;ar=aK end;local ao={}
for aL,aK in ipairs(an.files)do do local aT,aS=pcall(require,"kernel.process")
if aT and
aS and aS.yieldCooperative then aS.yieldCooperative()end end;local aN=an.fileMap and
an.fileMap[aK]local aM
if aN then aM=c.normalize((an._srcBase or am)..
"/"..aN)
if an._srcBase and not
c.exists(aM)then local aS=aN:match("^[^/]+/(.+)$")if aS then local aT=c.normalize(
an._srcBase.."/"..aS)
if c.exists(aT)then aM=aT end end end else aM=c.normalize(am..aK)end;local aO,aP=c.readFile(aM)
if not aO then
for aL,aS in ipairs(ao)do pcall(c.remove,aS)end;if c.exists(aM)then
return false,"cannot read source file "..
aM..": "..tostring(aP or"read failed")..
"  [E-605 ERR_PKG_FILE_UNREADABLE]"end
return false,
"missing source file: "..aM.."  [E-604 ERR_PKG_FILE_MISSING]"end
if ar then local aS=an.hashes[aK]
if aS then
if not ar.ctEquals(ar.hash(aO),aS)then for aL,aT in
ipairs(ao)do pcall(c.remove,aT)end
return false,"hash mismatch on "..aK..
"  [E-608 ERR_PKG_HASH_MISMATCH]"end end end;local aQ,aR=c.writeFile(aK,aO)if not aQ then
for aL,aS in ipairs(ao)do pcall(c.remove,aS)end
return false,"write failed for "..aK..": "..tostring(aR)end
ao[#ao+1]=aK end;local as=c.join(R,an.name)if not c.exists(as)then
c.makeDirectory(as)end;an._unverified=(type(an.hashes)~="table")and
true or nil
do
local aK=an.files or{}if type(an.hashes)=="table"then
for aM,aL in ipairs(aK)do if
type(an.hashes[aL])~=r then an._unverified=true;break end end end end;an._installedFrom=tostring(am)
an._sigState=ap and ap.state or v;an._sigKey=ap and ap.key or nil
an._sigLabel=ap and ap.label or nil;local aI,aJ=k.saveFile(c,c.join(as,y),an)if not aI then for aL,aK in ipairs(ao)do
pcall(c.remove,aK)end
return false,"manifest write failed: "..tostring(aJ)end;local au="e"
if

type(an.service)=="table"and an.service.defaultState=="disabled"then au="d"
for aL,aK in ipairs(an.files)do
local aM=tostring(aK):match("^/etc/rc%.d/(.+)%.lua$")if aM then pcall(c.writeFile,D..aM..E,"1")end end end;c.writeFile(c.join(as,"state"),au)
e[an.name]=an;local av=a.repoHints(an)if#av>0 then local aK=i()if aK and aK.learn then
pcall(aK.learn,av,an.name)end end
a.syncCriticalBackup()if d then
d.info("pkg",string.format("Installed %s v%s (%d files)",an.name,an.version,#ao))end
local aw,ax=a.checkRequires(an.name)if not aw and d then
d.warn("pkg",string.format("%s installed with unmet requires: %s",an.name,table.concat(ax,", ")))end
if not aw then return true,
#ao..
" files (unmet requires: "..table.concat(ax,", ")..")"end;return true,#ao.." files"end
function a.runtimeRefusal(al)if type(al)~="table"then return nil end
local am=tostring(al.name or"this package")
if type(al.lua)==r then local an=al.lua:match("^(%d+%.%d+)$")
local ao=tostring(
_VERSION or""):match("(%d+%.%d+)")
if an and ao and a.compareVersion(ao,an)<0 then
return
string.format(
"'%s' needs the Lua %s architecture; this CPU runs Lua %s. ".."Sneak-right-click the CPU (or APU) to switch its architecture, then reboot.",am,an,ao)end end
if type(al.tos)==r then local ao=rawget(_G,"_TOS")
local an=ao and ao.version
if an and not a.satisfiesConstraint(an,al.tos)then return
string.format("'%s' needs TOS %s; this is TOS %s.",am,al.tos,an)end end;return nil end
function a.describeContradictions(al)local am={}for ao,an in ipairs(al or{})do
am[#am+1]=tostring(an.text)end;return table.concat(am,"; ")end
function a.plan(al,an,am)am=am or{}
if type(al)~=r or al==""then return nil,"invalid repo dir"end
if type(an)~=r or an==""then return nil,"invalid target name"end;al=c.normalize(al)
if
not c.exists(al)or not c.isDirectory(al)then return nil,"repo dir not found: "..al end;local at,aw={},{}
local function au(aD)if type(aD)~=r or aD==""then return end
aD=c.normalize(aD)if not aw[aD]then aw[aD]=true;at[#at+1]=aD end end;au(al)if type(am.extraRoots)=="table"then
for aE,aD in ipairs(am.extraRoots)do au(aD)end end
local aB,ax=pcall(a.repoRoots)
if aB and type(ax)=="table"then for aE,aD in ipairs(ax)do au(aD)end end;local ap,aq,ar,av={},{},{},{}
local function aC(aD,aF,aE)if e[aD]then return e[aD]end
if ap[aD]then return ap[aD]end;local aJ,aI,aJ,aH=o(aF)local aG
for aJ,aK in ipairs(at)do local aL=c.join(aK,aD)
if c.exists(aL)then
local aM,aJ,aN=j(aL)
if aM and aM.name==aD then local aO=aH and P(aN)or nil
if aH and aO~=aH then av[aD]=
av[aD]or{dir=aL,have=aO,want=aH,by=aE}if d then
d.warn("pkg",
"Passing over '"..
aD.."' in "..aK..
": "..tostring(aE).." requires it signed by another key")end elseif
aI and not a.satisfiesConstraint(
aM.version or"0.0.0",aI)then aG=aG or{m=aM,dir=aL,path=aN}else
ap[aD],aq[aD],ar[aD]=aM,aL,aN;return aM end elseif aM and d then
d.warn("pkg","Ignoring '"..tostring(aD)..
"' in "..aK..": manifest name '"..
tostring(aM.name).."' does not match directory")end end end
if aG then ap[aD],aq[aD],ar[aD]=aG.m,aG.dir,aG.path;return aG.m end;return nil end;local as,ay=a.resolveInstallOrder(an,aC)
if not as then
local aE=tostring(ay):match("^unknown package: (.+)$")local aD=aE and av[aE]
if aD then
return nil,
string.format("%s requires '%s' signed by %s; no copy signed by that "..
"key was found (the one in %s has %s)",tostring(aD.by),aE,g(aD.want),aD.dir,
aD.have and g(aD.have)or B)end;return nil,"resolve failed: "..tostring(ay)end
for aE,aD in ipairs(as)do local aF=ap[aD]if aF then local aG,aH=L(aF)
if not aG then return nil,"invalid manifest for '"..aD..
"': "..tostring(aH)end end end;local ao={order=as,dirs=aq,expectKey={},contradictions={}}local function az(aD,aE,aF)
ao.contradictions[#
ao.contradictions+1]={kind=aD,name=aE,text=aF,id=aD.."|"..tostring(aE)}end;local aA={}
for aE,aD in
ipairs(as)do local aF=ap[aD]
if aF and type(aF.requires)=="table"then
for aE,aG in
ipairs(aF.requires)do local aH,aE,aE,aI=o(aG)
if aH and aI then local aL=aA[aH]
if not aL then aA[aH]={key=aI,by=aD}elseif aL.key~=aI then
az("pins",aH,string.format("%s requires '%s' signed by %s, but %s requires it signed by %s",aL.by,aH,g(aL.key),aD,g(aI)))end end;local aJ=aH and K(aH)local aK={}
if aJ then
aK=q(aD,aG,aJ,Q(aJ),C..tostring(aJ.name))elseif aH and ap[aH]then local aL=P(ar[aH])
aK=q(aD,aG,ap[aH],aL,"the copy in "..tostring(aq[aH]))if aI and aL==aI and not ao.expectKey[aH]then
ao.expectKey[aH]=aI end end;for aE,aL in ipairs(aK)do
ao.contradictions[#ao.contradictions+1]=aL end end end
if aF then for aE,aG in ipairs(V(aF,P(ar[aD])))do
ao.contradictions[#ao.contradictions+1]=aG end
if not e[aD]then
local aG=a.runtimeRefusal(aF)if aG then az("runtime",aD,aG)end end end end;return ao end
function a.installWithDeps(an,am,al)al=al or{}local ar,as=f(al)if not ar then return false,as end
local ao,at=a.plan(an,am,al)if not ao then return false,at end
if#ao.contradictions>0 then
local au=a.describeContradictions(ao.contradictions)
if not al.force then return false,w..am.."': "..au end;if d then
d.warn("pkg","Installing '"..am.."' past contradictions (force): "..au)end end;local ap,aq={},{}
for av,au in ipairs(ao.order)do
if e[au]then aq[#aq+1]=au else local ax=ao.dirs[au]or
c.join(c.normalize(an),au)local aw=al.licenseKey
if al.licenseKeys and
al.licenseKeys[au]then aw=al.licenseKeys[au]elseif au~=am then aw=nil end
local ay,az=a.install(ax,{licenseKey=aw,session=al.session,allowUnverified=al.allowUnverified,allowUnsigned=al.allowUnsigned,force=al.force,expectKey=ao.expectKey[au]})
if not ay then for av,aA in ipairs(ap)do
pcall(a.uninstall,aA,{session=al.session})end;return false,"install of "..
au.." failed: "..tostring(az)end;ap[#ap+1]=au end end;return true,{installed=ap,skipped=aq}end
function a.uninstall(al,am)local ap,aq=f(am)if not ap then return false,aq end;if al=="tos-core"then return false,
"refusing to uninstall tos-core"end;local an=e[al]if not an then return
false,"not installed: "..al end
if not am or not
am._internalUpgrade then
for as,at in pairs(e)do
if
as~=al and type(at.requires)=="table"then for av,au in ipairs(at.requires)do
if type(au)=="table"and au.name==al and
not au.optional then return false,"required by "..as end end end end end
for at,as in ipairs(an.files or{})do local au,av=pcall(c.remove,as)if not au and d then
d.warn("pkg",
"Could not remove "..as..": "..tostring(av))end end;a.forgetModules(an.files)local ar=c.join(R,al)
local function ao(as)
if
c.isDirectory(as)then local at=c.list(as)or{}for av,au in ipairs(at)do local aw=au:gsub("/$","")if aw~=""then
ao(c.join(as,aw))end end end;pcall(c.remove,as)end;ao(ar)e[al]=nil;a.syncCriticalBackup()if d then
d.info("pkg","Uninstalled "..al)end;return true end;local I={"/usr/repo","/var/repo"}
local function J()local al,an={},{}local function ao(ar)
if
ar and ar~=""and ar~="/"and not an[ar]then an[ar]=true;al[#al+1]=ar end end
if c.mounts then
local as,ar=pcall(c.mounts)if as and type(ar)=="table"then
for au,at in ipairs(ar)do ao(at.mountPoint)end end end;if c.exists("/mnt")then
for as,ar in ipairs(c.list("/mnt")or{})do
local at=ar:gsub("/$","")if at~=""then ao("/mnt/"..at)end end end
local am,ap={},{}local function aq(ar)
if ar and not ap[ar]then ap[ar]=true;am[#am+1]=ar end end
for as,ar in ipairs(al)do aq(ar)
for as,at in
ipairs(c.list(ar)or{})do local au=at:gsub("/$","")
if au~=""and not au:find("[/\\]")then
local av=c.join(ar,au)
local aw,ax=pcall(function()return c.isDirectory(av)end)if aw and ax then aq(av)end end end end;return am end
function a.repoRoots()local al={}for an,am in ipairs(I)do al[#al+1]=am end;for an,am in ipairs(J())do
al[#al+1]=am end;return al end
function a.listRepo(al)if type(al)~=r or al==""then return{}end
al=c.normalize(al)
if not c.exists(al)or not c.isDirectory(al)then return{}end;local am={}local an=c.list(al)or{}
for ap,ao in ipairs(an)do local aq=ao:gsub("/$","")
if
aq~=""then local ar=c.join(al,aq)
if c.isDirectory(ar)then local as,at=j(ar)
if as then
am[#am+1]={name=as.name,version=as.version,description=as.description,category=
(
type(as.category)==r and as.category~="")and as.category or"misc",author=as.author,kind=as.kind,source=at,dir=ar,requires=as.requires,recommends=as.recommends}end end end end
table.sort(am,function(ao,ap)
return(ao.name or"")< (ap.name or"")end)return am end
function a.findInRepos(al,am)local an={}for ap,ao in ipairs(I)do an[#an+1]=ao end
if
type(am)=="table"then for ap,ao in ipairs(am)do an[#an+1]=ao end end;for ap,ao in ipairs(J())do an[#an+1]=ao end
for ap,ao in ipairs(an)do
local aq=c.join(ao,al)
if c.exists(aq)and c.isDirectory(aq)then local ar=j(aq)if
ar and ar.name==al then return aq,ao end;if ar and d then
d.warn("pkg","Ignoring '"..
tostring(al).."' in "..
ao..": manifest name '"..
tostring(ar.name).."' does not match directory")end end end;return nil end
local function X(al,am)
if type(al)==r and al:find("/")then
local ap=c.normalize(al:gsub("/$",""))local aq=ap:match("[^/]+$")
if
aq and c.exists(ap)and c.isDirectory(ap)then local ar=j(ap)if ar and ar.name==aq then local as=ap:match("^(.*)/[^/]+$")if
as==""then as="/"end;return as,aq end
return
nil,"not a package directory (or name mismatch): "..al end;return nil,"package not found in any repo: "..al end;local an,ao=a.findInRepos(al,am)if not an then return nil,
"package not found in any repo: "..tostring(al)end
return ao,al end
function a.planByName(am,al)al=al or{}local ap,an=X(am,al.extraRoots)
if not ap then return nil,an end;local ao,aq=a.plan(ap,an,{extraRoots=al.extraRoots})if
not ao then return nil,aq end;ao.target=an;return ao end
function a.installByName(am,al)al=al or{}local ap,aq=f(al)if not ap then return false,aq end
local an,ao=X(am,al.extraRoots)if not an then return false,ao end;am=ao
return
a.installWithDeps(an,am,{licenseKey=al.licenseKey,licenseKeys=al.licenseKeys,session=al.session,allowUnverified=al.allowUnverified,allowUnsigned=al.allowUnsigned,extraRoots=al.extraRoots,force=al.force})end
function a.computeLicenseHash(al,am)if type(al)~=r or type(am)~=r then
return nil,"package name and key must be strings"end;local ao,an=pcall(require,F)
if
not ao or not an or not an.hash then return nil,"crypto unavailable"end;return an.hash(al.."|"..am)end
function a.listAllAvailable(al)al=al or{}local an={}local am={}
local function ao(ap)if not c.exists(ap)or
not c.isDirectory(ap)then return end;for ar,aq in
ipairs(a.listRepo(ap))do
if not an[aq.name]then an[aq.name]=true;aq.root=ap;am[#am+1]=aq end end end;for aq,ap in ipairs(I)do ao(ap)end;for aq,ap in ipairs(J())do ao(ap)end;if
al.includeRemote then
for aq,ap in ipairs(a.listRemoteAvailable(al))do if not an[ap.name]then
an[ap.name]=true;am[#am+1]=ap end end end;return am end
function a.listRemoteAvailable(al)local am=i()
if not am or type(am.search)~=H then return{}end;local ap,ao=pcall(am.search,al or{})if
not ap or type(ao)~="table"then return{}end;local an={}
for ar,aq in ipairs(ao)do
if type(aq)=="table"and
type(aq.name)==r then
an[#an+1]={name=aq.name,version=aq.version,description=aq.description,category=aq.category or"remote",repo=aq.repo,remote=true}end end;return an end
function a.installFromFloppy(al)al=al or{}local ap,aq=f(al)if not ap then return false,aq end
local ar=(
type(al.confirm)==H)and al.confirm or function()return false end;local ao={}local am={}local an={}
for au,at in ipairs(J())do for au,av in ipairs(a.listRepo(at))do
an[#an+1]={name=av.name,dir=av.dir,mount=at}end end;local as=#an
for au,at in ipairs(an)do
if ar(at.name,at.dir,au,as)then
local av,aw=a.installByName(at.name,{extraRoots={at.mount},session=al.session,allowUnverified=al.allowUnverified,allowUnsigned=al.allowUnsigned,force=al.force})if av then ao[#ao+1]=at.name else
am[#am+1]=at.name.." ("..tostring(aw)..")"end else
am[#am+1]=at.name.." (declined)"end end;return true,{installed=ao,skipped=am}end
function a.runInstaller(al)pcall(require,"io")
local ao,am=pcall(require,"shell.pkgpicker")
if not ao or type(am)~="table"or not am.run then return false,
"picker unavailable: "..tostring(am)end;local ap,an,aq=pcall(am.run,al)if not ap then
return false,"installer error: "..tostring(an)end;if an==false then return false,
aq or"no installable packages found"end;return true end;local Y={["tos-core"]=true}
function a.exportDisk(al,am)am=am or{}local as,at=f(am)if not as then
return false,at end;if type(al)~=r or al==""then
return false,"invalid target directory"end;al=c.normalize(al)if not al then return false,
"invalid target path"end
local au={"/","/tos","/etc","/var","/usr","/home","/root","/public","/init.lua","/bios.lua"}for aw,av in ipairs(au)do
if al==av or al:sub(1,#av+1)==av.."/"then return false,
"refusing to export into a system path: "..al end end
if not
c.exists(al)or not c.isDirectory(al)then return false,
"target does not exist or is not a directory: "..al end;local ao=nil
if type(am.only)=="table"and#am.only>0 then ao={}for aw,av in
ipairs(am.only)do ao[av]=true end end;local ap,aq,an={},0,{}local ar={}for av in pairs(e)do ar[#ar+1]=av end
table.sort(ar)
for aw,av in ipairs(ar)do local ax=e[av]
if not Y[av]and(not ao or ao[av])then
local ay=c.join(al,av)local az,aA=k.saveFile(c,c.join(ay,y),ax)
if not az then
an[#an+1]=av..
": manifest write failed ("..tostring(aA)..")"else local aB=true
for aw,aC in ipairs(ax.files or{})do local aD,aE=c.readFile(aC)
if not aD then
an[#an+1]=
av..
(c.exists(aC)and
(": cannot read installed file "..aC..
": "..tostring(aE or"read failed"))or
(": missing installed file "..aC))aB=false else local aF,aG=c.writeFile(c.join(ay,aC),aD)if not aF then
an[#an+1]=
av..": write "..aC.." ("..tostring(aG)..")"aB=false else aq=aq+1 end end end;if aB then ap[#ap+1]=av end end end end
if ao then
for av in pairs(ao)do if not e[av]then
an[#an+1]=av..": not installed (skipped)"elseif Y[av]then
an[#an+1]=av..": is the OS core, not an add-on (skipped)"end end end
do
local av={"-- Optional Utilities set manifest — generated by `pkg make-disk`.","return {","  set = \"optional-utilities\",","  disks = 1,","  packages = {"}
for az,ay in ipairs(ap)do local aA=e[ay]or{}local aB,aC={},{}
for az,aD in ipairs(aA.requires or{})do local aE=(
type(aD)=="table")and aD.name or
tostring(aD):match("^(%S+)")if aE then
aB[#aB+1]=string.format("%q",aE)end end;for az,aD in ipairs(aA.recommends or{})do
aC[#aC+1]=string.format("%q",tostring(aD))end
av[#av+1]=string.format("    [%q] = { disk = 1, version = %q, category = %q, kind = %q,",ay,tostring(
aA.version or"?"),tostring(aA.category or"misc"),tostring(aA.kind or"?"))
av[#av+1]=string.format("      description = %q,",tostring(aA.description or""))
av[#av+1]=string.format("      requires = { %s }, recommends = { %s } },",table.concat(aB,", "),table.concat(aC,", "))end;av[#av+1]="  },"av[#av+1]="}"av[#av+1]=""
local aw,ax=c.writeFile(c.join(al,"optutil-set.lua"),table.concat(av,"\n"))
if not aw then an[#an+1]="optutil-set.lua: "..tostring(ax)end end
do
local av=table.concat({"TOS Optional Utilities","","Insert this disk on a TOS machine and run, as admin:","","    pkg install","","That opens the picker: tick what you want, press Enter.","","Non-interactive (scripts):","    pkg install <name> [<name>...]","    pkg install --all --yes",""},"\n")local aw,ax=c.writeFile(c.join(al,"README.txt"),av)
if
not aw then an[#an+1]="README.txt: "..tostring(ax)end end;if d then
d.info("pkg",string.format("Exported %d package(s), %d file(s) to %s",#ap,aq,al))end
return true,{packages=ap,files=aq,problems=an,target=al}end;a.DEFAULT_REPO_ROOTS=I;a._loadAnyManifest=j
function i()
local am,al=pcall(require,"kernel.pkgremote")if not am or type(al)~="table"then
return nil,"remote package support unavailable"end;if al.init then
pcall(al.init,{log=d,validRepoHint=aa})end;return al end;function a.knownRepos()local al=i()if not al or not al.known then return{}end;return
al.known()end
function a.forgetRepo(al,am)
local ao,ap=f(am)if not ao then return false,ap end;local an,aq=i()if not an then return false,aq end;return
an.forget(al)end
local function h()local am,al=pcall(require,t)if not am or not al then
return nil,"signature support unavailable"end
al.init({fs=c,serialize=k,log=d})return al end
function a.trustList()local al=h()if not al then return{}end;return al.listKeys()end
function a.trustAdd(al,am,an)local ap,aq=f(an)if not ap then return false,aq end;local ao,ar=h()
if not ao then return false,ar end;return ao.addKey(al,am)end
function a.trustRemove(al,am)local ao,ap=f(am)if not ao then return false,ap end;local an,aq=h()if not an then
return false,aq end;return an.removeKey(al)end
function a.trustRequire(al,am)local ao,ap=f(am)if not ao then return false,ap end;local an,aq=h()if not an then
return false,aq end;return an.setRequireSignature(al)end;function a.trustRequired()local al=h()if not al then return false end
return al.requiresSignature()end
function a.discoveredPolicy()local al=h()if not al or not
al.discoveredPolicy then return"off"end;return
al.discoveredPolicy()end
function a.trustDiscovered(al,am)local ao,ap=f(am)if not ao then return false,ap end;local an,aq=h()if not an then
return false,aq end;return an.setDiscoveredPolicy(al)end
function a.checkSignature(al)
if type(al)~=r or al==""then return nil,"invalid directory"end;local am,ao=h()if not am then return nil,ao end
local an,ap,aq,ar=j(c.normalize(al))
if not an then return nil,G..al..": "..tostring(ap)end;return am.verifyManifest(aq,ar),an end
function a.signPackage(am,an,al)al=al or{}local aq,ar=f(al)if not aq then return nil,ar end;local ao,as=h()if not ao then return nil,
as end;if type(am)~=r or am==""then
return nil,"invalid directory"end;local at,au,av=j(c.normalize(am))
if
not at then return nil,G..am..": "..tostring(au)end;local ap,aw=ao.seedFromPassphrase(an,al.signer)
if not ap then return nil,aw end;return
ao.signManifest(av,ap,{signer=ao.normalizeLabel(al.signer)})end
function a.signingKey(al,am)local an,ar=h()if not an then return nil,ar end
local ao,as=an.seedFromPassphrase(al,am)if not ao then return nil,as end
local at,ap=pcall(require,"kernel.ed25519")
if not at or not ap then return nil,"ed25519 support unavailable"end;local aq=ap.publickey(ao)
if not aq then return nil,"cannot derive the key"end;return an.binToHex(aq)end
function a.repos()local al=i()if not al then return{}end;return al.repos()end
function a.addRepo(al,am,an,ao)local aq,ar=f(ao)if not aq then return false,ar end;local ap,as=i()
if not ap then return false,as end;return ap.addRepo(al,am,an)end
function a.removeRepo(al,am)local ao,ap=f(am)if not ao then return false,ap end;local an,aq=i()if not an then
return false,aq end;return an.removeRepo(al)end
function a.searchRemote(al)local am=i()if not am then return{}end;return am.search(al)end;local Z,_=8,16;local function l(al)
return
(tostring(al):gsub("%s*%[E%-%d%d%d ERR_[%w_]+%]","")).."  [E-603 ERR_PKG_DEPENDENCY]"end
local function ak(al)
if
type(al)=="table"then return al.name,al.version,al.optional==true end;if type(al)==r then local am,an=al:match("^(%S+)%s+(.+)$")
if am then return am,an,false end;return al,nil,false end end
function a.installRemote(am,al)al=al or{}local ay,az=f(al)if not ay then return false,az end;local as,aA=i()if
not as then return false,aA end
local function av(aE)local aF={}for aG,aH in pairs(al)do aF[aG]=aH end;for aG,aH in
pairs(aE)do aF[aG]=aH end;return aF end;local aq=a.discoveredPolicy()local an="  [E-606 ERR_PKG_UNTRUSTED_SOURCE]"
local function aB(aE,aF,aH,aI,aG,aJ)
local aN=h()local aL="'"..
aE.."' is only in an unconfigured repo ("..tostring(aG)..")"if not aN then
return
false,aL..", and signatures cannot be checked here"..an end
local aK=aN.verifyManifest(aH,aI)if aK.state==A then return true end
if aK.state=="invalid"then return false,
aL..
", and its signature does not verify ("..tostring(aK.reason)..")"..an end
if aK.state~=s then return false,
aL..", and it is unsigned. An unsigned package installs only from a "..
"repo an admin added (pkg repo add)"..an end;local aO="pkg trust add <name> "..tostring(aK.key)
if
aF.kind=="service"or aF.kind=="driver"then
return false,
aL..
". It is a "..
aF.kind..
", which runs outside the sandbox, and "..
"its key ("..tostring(aK.fingerprint)..
") is not trusted here: trust it first, ".."with  "..aO..an end
if aq~="tofu"or type(al.confirmKey)~=H then
return false,
aL..
", and its key ("..

tostring(aK.fingerprint)..") is not trusted "..
"here"..
(aq~="tofu"and
(" (pkg trust discovered is "..aq..")")or"")..". To trust it:  "..aO..an end
local aM=al.confirmKey({name=aE,repo=aG,by=aJ,kind=aF.kind,key=aK.key,fingerprint=aK.fingerprint,signer=aK.signer})if type(aM)~=r or aM==""then
return false,"not installed: the key of '"..
aE.."' ("..tostring(aK.fingerprint)..
") was not trusted"..an end
local aP,aQ=a.trustAdd(aM,aK.key,al)
if not aP then return false,
"could not trust the key of '"..aE.."': "..tostring(aQ)..an end;if d then
d.info("pkg","Trusted key "..
tostring(aK.fingerprint).." as '"..
aM.."' (first use, for '"..aE.."' from "..
tostring(aG)..")")end
return true end;local ar,at,aw={},{},{}
local function au()for aF,aE in ipairs(ar)do as.cleanup(aE.dir)end end
local function ax(aE,aH,aG,aF,aI,aJ)if aw[aE]then return true end;local aL=
aF and("dependency '"..
tostring(aE).."' of '"..aF.."': ")or""if aH>Z then return false,
l(
aL.."dependencies nest deeper than "..Z)end;if#ar>=_ then
return false,l(
"the fetch would bring in more than ".._.." packages")end;aw[aE]=true
local aN,aO,aM=as.fetch(aE,av({hints=aI,discoveredPolicy=aq}))
if not aN then
if aF then return false,
l(aL..tostring(aO)..
" (if you have it on a disk, `pkg install "..tostring(aE).."` it first)")end;return false,aO end;local aP={name=aE,dir=aN,meta=aM,expectKey=aJ}ar[#ar+1]=aP
local aK,aS,aQ,aR=j(aN)
if type(aK)~="table"then return false,aL.."no readable manifest"end
if aM and aM.discovered then local aU,aT=aB(aE,aK,aQ,aR,aM.discovered,aF)if not aU then return
false,aF and l(aL..aT)or aT end end
if aG and
not a.satisfiesConstraint(aK.version or"0.0.0",aG)then return false,
l(aL..
"needs "..aG..", and the repo has "..
tostring(aK.version or"no version"))end
for aS,aT in
ipairs(type(aK.requires)=="table"and aK.requires or{})do local aU,aV,aW=ak(aT)
if aU and not aW then local aX=K(aU)
if aX then
if aV and not
a.satisfiesConstraint(aX.version or"0.0.0",aV)then return false,
l(("'%s' needs %s %s, and %s is installed -- `pkg upgrade %s` first"):format(aE,aU,aV,tostring(
aX.version or"?"),aU))end else local aY=
type(aT)=="table"and type(aT.repos)=="table"and aT.repos or nil;local aZ=

type(aT)=="table"and type(aT.key)==r and aT.key:lower()or nil
local a_,ba=ax(aU,aH+1,aV,aE,aY,aZ)if not a_ then return false,ba end end end end;at[#at+1]=aP;return true end;local aC,aD=ax(am,0)if not aC then au()return false,aD end;local ao,ap={},nil
for aF,aE in
ipairs(at)do
local aG,aH=a.install(aE.dir,aE.expectKey and av({expectKey=aE.expectKey})or al)
if not aG then au()
local aI=(
aE.name~=am and("dependency '"..aE.name.."': ")or"")..tostring(aH)..
(#ao>0 and
(
" (installed before it stopped: "..table.concat(ao,", ")..")")or"")return false,aE.name~=am and l(aI)or aI end
if d then
d.info("pkg","Installed '"..
tostring(aE.name)..
"' from "..

(
aE.meta and aE.meta.discovered and(
tostring(aE.meta.discovered)..", a repo nobody configured")or
("repo '"..tostring(aE.meta and aE.meta.repo).."'")).. (
aE.name~=am and(" as a dependency of '"..am.."'")or""))end;if aE.name==am then ap=aE.meta else ao[#ao+1]=aE.name end end;au()ap=ap or{}ap.dependencies=ao;return true,ap end end