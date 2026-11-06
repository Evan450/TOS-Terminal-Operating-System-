
local B,C,D,E,F,G,H,I,v,J,K,w,L,x,y,u,M,N,z,A=".disabled","/etc/rc.d/","^(.*)/[^/]+$","cluster-manager","command","function","kernel.crypto","kernel.pkgfs","kernel.pkgsign","no manifest in ","no signature","not installed: ","package.lua","refusing to install '","refusing to upgrade '","string","the installed ","trusted","unknown","unsigned"
return
function(a,b)local U,f,t=b.PKG_ROOT,b.adminGate,b.findProvider
local V,m=b.serviceInstallGate,b.targetKey;local ad,O=b.validRepoHint,b.validateManifest
local c,d,k,e=b.fs,b.log,b.serialize,b.installed;local g
local function P(ao)local ap={}if type(ao)~="table"then return ap end
for ar,aq in pairs(ao)do
if type(ar)==u and
ar~=""then local as=nil;if
type(aq)==u and aq~=""and aq:sub(1,1)~="/"then as=aq end
ap[#ap+1]={name=ar,version=as,optional=false}end end;return ap end;local ae="/usr"
local function af(ao)if type(ao)~=u or ao==""then return nil end
if
ao:sub(1,2)=="//"then return"/"..ao:gsub("^/+","")end;return ae.."/"..ao:gsub("^/+","")end;local function W(ao)return
(tostring(ao):gsub("/+$",""):match("([^/]+)$"))end
local function ag(ap,ao,aq)
if type(ao)~=
"table"then return nil,"programs.cfg entry is not a table"end
local ar={name=ap,version=ao.version or"0.0.0",kind=ao.kind or F,files={},fileMap={},requires=P(ao.dependencies),commands=ao.commands,capabilities=ao.capabilities,description=ao.description or
ao.note,author=ao.author or ao.authors,hashes=ao.hashes,_srcBase=aq}
if type(ao.files)~="table"then return nil,"programs.cfg entry '"..
tostring(ap).."' has no files table"end;local as={}
for at,au in pairs(ao.files)do
if type(at)==u and type(au)==u then
if
at:sub(1,1)==":"then as[#as+1]=at:sub(2)else local aw=af(au)local av=W(at)
if aw and av and av~=""then local ax=
(aw:gsub("/+$","")).."/"..av
ar.files[#ar.files+1]=ax;ar.fileMap[ax]=at:gsub("^/+","")end end end end
if#as>0 then
return nil,
"package '"..tostring(ap)..
"' uses OPPM directory-copy entries ("..table.concat(as,", ")..
"); TOS installs a declared file list — list the files individually"end
if#ar.files==0 then return nil,"programs.cfg entry '"..
tostring(ap).."' lists no installable files"end;return ar end;local Q=64*1024;local ah=64*1024
local function p(ao)local ap=c.size and c.size(ao)
if type(ap)==
"number"and ap>Q then return nil,"manifest too large ("..
ap.." bytes; at most "..Q..")"end;local aq,ar=c.readFile(ao)if type(aq)~=u then return nil,ar end
local as,at=k.decode(aq,{maxBytes=Q,maxCost=ah,maxKeys=1024})return as,at,aq end
local function ai(ao)local aq=W(ao)if not aq then return nil end
local ar=ao:gsub("/+$",""):match(D)local ap={}if ar and ar~=""then
ap[#ap+1]={path=c.join(ar,"programs.cfg"),root=ar}end
ap[#ap+1]={path=c.join(ao,"programs.cfg"),root=ao}
for at,as in ipairs(ap)do
if c.exists(as.path)then local au,aw,ax=p(as.path)
if type(au)~="table"then return nil,
"programs.cfg parse error: "..tostring(aw)end;local av=au[aq]
if type(av)~="table"then local ay,az=nil,0
for aA,aB in pairs(au)do if type(aA)==u and
type(aB)=="table"then ay,az=aA,az+1 end end;if az==1 and as.root==ao then aq,av=ay,au[ay]end end
if type(av)=="table"then local ay,az=ag(aq,av,as.root)
if not ay then return nil,az end;return ay,nil,as.path,ax end end end;return nil end
local function j(ao)
local function aq(ax,ay,az,aA)if type(ax)=="table"then ax._srcBase=nil
ax._sigState,ax._sigKey,ax._sigLabel=nil,nil,nil end;return ax,ay,az,aA end;local ar=c.join(ao,L)if c.exists(ar)then local ax,ay,az=p(ar)if ax then
return aq(ax,"native",ar,az)end
return nil,"package.lua parse error: "..tostring(ay)end
local as=c.join(ao,"package.oppm.lua")
if c.exists(as)then local az,aA,aB=p(as)if not az then return nil,
"package.oppm.lua parse error: "..tostring(aA)end
local aC,ax=next(az)if not ax or type(ax)~="table"then
return nil,"OPPM manifest has no top-level package entry"end
local ay={name=aC,version=ax.version or"0.0.0",kind=ax.kind or F,files={},requires={},commands=ax.commands,capabilities=ax.capabilities,description=ax.description,author=ax.author,critical=ax.critical,hashes=ax.hashes}
if type(ax.files)=="table"then
for aE,aD in pairs(ax.files)do
if type(aE)=="number"and
type(aD)==u then ay.files[#ay.files+1]=aD elseif type(aE)==u and
type(aD)==u then ay.files[#ay.files+1]=aD end end end;ay.requires=P(ax.dependencies)return aq(ay,"oppm",as,aB)end;local ap=ao:match("([^/]+)/?$")
if ap then
local ax=c.join(ao,ap..".cfg")
if c.exists(ax)then local az,aC,aD=p(ax)if not az then return nil,
ap..".cfg parse error: "..tostring(aC)end;local ay,aB=az,ap
if az[ap]and
type(az[ap])=="table"then ay=az[ap]elseif not az.files then local aF,aE=next(az)if
type(aE)=="table"then aB,ay=aF,aE end end
if type(ay)~="table"then return nil,ap..".cfg has no package table"end
local aA={name=ay.name or aB,version=ay.version or"0.0.0",kind=ay.kind or F,files={},requires={},commands=ay.commands,capabilities=ay.capabilities,description=ay.description,author=ay.author,hashes=ay.hashes}
if type(ay.files)=="table"then for aE,aF in pairs(ay.files)do
if type(aF)==u then
aA.files[#aA.files+1]=aF elseif type(aE)==u then aA.files[#aA.files+1]=aE end end end;aA.requires=P(ay.dependencies)return aq(aA,"oppm",ax,aD)end end;local at,au,av,aw=ai(ao)if at then return at,"oppm",av,aw end
if au then return nil,au end;return nil,
"no package.lua, package.oppm.lua, <name>.cfg or programs.cfg entry for "..ao end;local aj={"compat.io","fs.read","fs.write","component"}
function a.foreignDefaultCaps()
local ao={}for ap,aq in ipairs(aj)do ao[ap]=aq end;return ao end
function a.findConflicts(ao,ap)local aq={}if type(ao)~="table"then return aq end
for at,as in
ipairs(ao.conflicts or{})do if as~=ap and e[as]then
aq[#aq+1]={kind="declared",other=as,detail=tostring(ao.name)..
" declares a conflict with "..as}end end
for as,at in pairs(e)do
if as~=ao.name and as~=ap then
for av,au in ipairs(at.conflicts or{})do if
au==ao.name then
aq[#aq+1]={kind="declared",other=as,detail=as.." declares a conflict with "..tostring(ao.name)}end end end end;local ar={}
for as,at in pairs(e)do if as~=ao.name and as~=ap then for av,au in ipairs(at.files or{})do
ar[m(au)]=as end end end
for at,as in ipairs(ao.files or{})do local au=ar[m(as)]if au then
aq[#aq+1]={kind="file",other=au,detail=as,path=as}end end;return aq end;local X="/tos/system_manifest.lua"
local ak={kernel=true,shell=true,compat=true,peripheral=true,system_manifest=true}
local al={mail={mail=true},mailapp={mail=true},intercom={intercom=true},intercomapp={intercom=true},blockfs={blockfs=true},mouse={mouse=true},[E]={[E]=true},cluster={[E]=true,["cluster-master"]=true,["cluster-storage"]=true},["rbmk-cmd"]={["rbmk-control"]=true}}local am={"/usr/lib/","/usr/modules/"}
local function R(ao,ap)
if type(ao)~="table"or
type(ao.files)~="table"then return nil end;local ar={}local as=k and k.loadFile(c,X)
if type(as)=="table"then
for au,at in ipairs(as)do if
type(at)=="table"and type(at.path)==u then
ar[m(at.path)]=true end end elseif d then
d.warn("pkg","cannot read "..X.."; system files are not protected from packages")end;local aq={}for au,at in pairs(e)do
for au,av in ipairs(at.files or{})do aq[m(av)]=true end end;for au,at in ipairs(ap or{})do
aq[m(at)]=true end
for au,at in ipairs(ao.files)do local av=m(at)if ar[av]then return tostring(at)..
" is a TOS system file"end
for au,aw in
ipairs(am)do
if av:sub(1,#aw)==aw then
local ax=(av:sub(#aw+1):match("^([^/]+)")or""):gsub("%.lua$","")if ak[ax]then
return tostring(at)..
" would be loaded by the kernel as its own '"..ax.."' module"end;local ay=al[ax]
if ay and
not ay[ao.name]then local az={}for aA in pairs(ay)do az[#az+1]=aA end
table.sort(az)
return tostring(at)..
" is the '"..ax..
"' library, which the shell ".."runs with full system authority; only "..table.concat(az," / ")..
" may provide it"end end end;if
av:sub(1,5)=="/etc/"and not aq[av]and c.exists(at)then
return tostring(at).." already exists and no installed package owns it"end end;return nil end;a._protectedTargetRefusal=R
local function n(ao)if
type(ao)~="table"or type(ao.key)~=u then return nil end;if ao.state~=N and ao.state~=z then
return nil end;return ao.key:lower()end
local function h(ao,ap)if type(ao)~=u then return K end;local ar,aq=pcall(require,v)local as=(ar and aq and
aq.fingerprint)and aq.fingerprint(ao)or
ao:sub(1,16)if
ar and aq and aq.labelForKey and not ap then
ap=aq.labelForKey(ao)end;return
(ap and("'"..ap.."'")or
"an untrusted key").." ("..as..")"end
local function o(ao)
if type(ao)=="table"then
local ap=(type(ao.key)==u and#ao.key==64 and not
ao.key:find("[^%x]"))and
ao.key:lower()or nil
return ao.name,ao.version,ao.optional and true or false,ap elseif type(ao)==u then local ap,aq=ao:match("^(%S+)%s+(.+)$")if ap then
return ap,aq,false,nil end;return ao,nil,false,nil end;return nil end
local function S(ao)if type(ao)~=u then return nil end;local as,ap=pcall(require,v)
if not as or
type(ap)~="table"or not ap.readSig or
not ap.sigPathFor then return nil end
if ap.init then ap.init({fs=c,serialize=k,log=d})end;local aq=ap.sigPathFor(ao)
local ar=aq and ap.readSig(aq)or nil;return ar and ar.key or nil end;local function T(ao)
return type(ao)=="table"and type(ao._sigKey)==u and
ao._sigKey:lower()or nil end
local function q(aq,as,ao,ap,ar)local au={}local at,av,ax,aw=o(as)if
not at or type(ao)~="table"then return au end
if
av and not a.satisfiesConstraint(
ao.version or"0.0.0",av)then
au[#au+1]={kind="version",name=at,id="version|"..at.."|"..av,text=string.format("%s requires '%s' %s, and %s is %s",aq,at,av,ar,tostring(ao.version))}end
if aw and ap~=aw then
au[#au+1]={kind="publisher",name=at,id="publisher|"..at.."|"..aw,text=string.format("%s requires '%s' signed by %s, and %s has %s",aq,at,h(aw),ar,
ap and h(ap)or K)}end;return au end
local function Y(ao,ap)local ar,aq={},{}local as={[ao.name]=true}
for au,at in ipairs(type(ao.provides)=="table"and
ao.provides or{})do if not
e[at]then as[at]=true end end;for at in pairs(e)do aq[#aq+1]=at end;table.sort(aq)
for au,at in ipairs(aq)do
local av=e[at]
if at~=ao.name and type(av.requires)=="table"then
for au,aw in
ipairs(av.requires)do local ax=o(aw)
if ax and as[ax]then for au,ay in
ipairs(q(M..at,aw,ao,ap,"the "..
tostring(ao.name).." being put in"))do ay.kind,ay.id="breaks","breaks|"..at.."|"..ay.id
ar[#ar+1]=ay end end end end end;return ar end
function a.outdated(ao)ao=ao or{}local ap,ar={},{}
local function as(at,au)local av=e[at.name]if not
(av and at.version and av.version)then return end;if
a.compareVersion(at.version,av.version)<=0 then return end
local aw=ar[at.name]if
aw and a.compareVersion(at.version,ap[aw].to)<=0 then return end
au.name,au.from,au.to=at.name,av.version,at.version
if aw then ap[aw]=au else ap[#ap+1]=au;ar[at.name]=#ap end end;for au,at in ipairs(a.listAllAvailable()or{})do
as(at,{dir=at.dir,root=at.root})end
local aq=ao.remote~=false and g()or nil;if aq and aq.online and aq.online()then
for au,at in
ipairs(a.listRemoteAvailable()or{})do as(at,{repo=at.repo,remote=true})end end
table.sort(ap,function(at,au)return
at.name<au.name end)return ap end
function a.upgradeRemote(ao,ap)ap=ap or{}local at,au=f(ap)if not at then return false,au end;if not e[ao]then return false,
w..tostring(ao)end;local ar,av=g()if not ar then
return false,av end;local aq,aw=ar.fetch(ao,{})if not aq then
return false,"could not fetch "..tostring(ao)..": "..
tostring(aw)end;local as={}
for az,aA in pairs(ap)do as[az]=aA end;as._candidate={dir=aq,root=aq:match(D)}
local ax,ay=a.upgrade(ao,as)ar.cleanup(aq)return ax,ay end
function a.compact(ao,ap)local at,au=f(ap)if not at then return false,au end;local ar=e[ao]if not ar then return false,w..
tostring(ao)end;local aq={}for ax,aw in
ipairs(ar.files or{})do
if aw:sub(1,5)=="/usr/"and c.exists(aw)then aq[#aq+1]=aw end end
if#aq==0 then return false,"nothing of "..
ao.." is under /usr"end;local av,as=pcall(require,I)if not av then
return false,"package archives are not on this install"end;as.init({fs=c,log=d})return
as.compact(ao,aq)end
function a.expand(ao,ap)local ar,as=f(ap)if not ar then return false,as end
local aq=package.loaded[I]if not(aq and aq.has(ao))then return false,
"not compact: "..tostring(ao)end
return aq.expand(ao)end
function a.upgrade(ao,ap)ap=ap or{}local aF,aG=f(ap)if not aF then return false,aG end;local aq=e[ao]if
not aq then return false,w..tostring(ao)end;local as,av;if
type(ap._candidate)=="table"then as,av=ap._candidate.dir,ap._candidate.root else
as,av=a.findInRepos(ao,ap.extraRoots)end;if not as then
return false,
"no source for "..ao.." on any repo or inserted disk"end;local ar,aH,aI,aJ=j(as)if not ar then return false,
"unreadable manifest for "..ao end
local aw=a.compareVersion(
ar.version or"0.0.0",aq.version or"0.0.0")
if aw==0 and not ap.force then return false,
string.format("%s is already at %s",ao,tostring(aq.version))end
if aw<0 and not ap.force then return false,
string.format("%s on the disk is OLDER (%s < %s) — pass force to downgrade",ao,tostring(ar.version),tostring(aq.version))end;local aK,aL=a._verificationGate(ar,ap.allowUnverified)if not aK then return
false,aL end
local aM,aN=a.verifyLicenseKey(ar,ap.licenseKey)
if not aM then return false,"license check failed: "..tostring(aN)end;local ax=a.findConflicts(ar,ao)
if#ax>0 and not ap.force then return false,
"conflicts: "..
a.describeConflicts(ax).."  [E-613 ERR_PKG_CONFLICT]"end;local aO,aP=O(ar)if not aO then
return false,"invalid manifest: "..tostring(aP)end;local aQ,aR=V(ar,ap)if not aQ then return false,
y..ao.."': "..aR end;local ay=R(ar)
if ay then return false,
y..ao.."': "..ay..
"  [E-612 ERR_PKG_PROTECTED_TARGET]"end;local az,aA=a._signGate(aI,ap,aJ)if aA then
return false,y..ao.."': "..aA end;local aB;local at=
type(aq._sigKey)==u and aq._sigKey:lower()or nil
if at then local aW=n(az)
if aW~=at then
if not
ap.force then
return false,

string.format("refusing to upgrade '%s': the installed version is signed by %s, and the "..

"candidate in %s has %s. An upgrade does not change who publishes a package; "..
"if the publisher really changed keys, confirm the new fingerprint with them ".."over another channel, then use --force.",ao,h(at,aq._sigLabel),tostring(as),
aW and("a different key: "..h(aW))or"no valid signature").."  [E-611 ERR_PKG_WRONG_PUBLISHER]"end;if d then
d.warn("pkg","Upgrading '"..
ao.."' to a different publisher (--force): "..
h(at,aq._sigLabel).." -> "..h(aW))end else aB=at end end
do
local function aX(aZ,a_)local ba={}
for bc,bb in
ipairs(type(aZ.requires)=="table"and aZ.requires or{})do local bd,bc,be=o(bb)
if bd and bd~=ao then local bf=t(bd)
if bf then for bc,bg in
ipairs(q(ao..
" "..tostring(aZ.version),bb,bf,T(bf),M..tostring(bf.name)))do ba[#ba+1]=bg end elseif not be then
ba[
#ba+1]={kind="missing",name=bd,id="missing|"..bd,text=string.format("%s %s requires '%s', which is not installed (install it first)",ao,tostring(aZ.version),bd)}end end end;for bc,bb in ipairs(Y(aZ,a_))do ba[#ba+1]=bb end;return ba end;local aY={}
for a_,aZ in ipairs(aX(aq,T(aq)))do aY[aZ.id]=true end;local aW={}for a_,aZ in ipairs(aX(ar,n(az)))do
if not aY[aZ.id]then aW[#aW+1]=aZ end end
if#aW>0 then
local aZ=a.describeContradictions(aW)
if not ap.force then return false,y..ao.."': "..aZ end;if d then
d.warn("pkg","Upgrading '"..ao.."' past contradictions (--force): "..aZ)end end end;local aC=a.isEnabled(ao)local aD={}
for aX,aW in ipairs(aq.files or{})do
local aY=tostring(aW):match("^/etc/rc%.d/(.+)%.lua$")if aY then aD[aY]=c.exists(C..aY..B)end end;local aE={}for aX,aW in ipairs(ar.files or{})do aE[aW]=true end
local au={}
for aX,aW in ipairs(aq.files or{})do if not aE[aW]then au[#au+1]=aW end end
local aS,aT=a.uninstall(ao,{session=ap.session,_internalUpgrade=true})if not aS then
return false,"could not remove the old version: "..tostring(aT)end
local aU,aV=a.install(as,{session=ap.session,upgrading=true,force=ap.force,allowUnverified=ap.allowUnverified,licenseKey=ap.licenseKey,allowUnsigned=ap.allowUnsigned,expectKey=aB,_priorFiles=aq.files})
if not aU then return false,
"upgrade FAILED after removing "..ao..": "..
tostring(aV).." — reinstall it from the disk"end;pcall(a.setEnabled,ao,aC,{session=ap.session})
for aX,aW in
pairs(aD)do local aY=C..aX..B
if aW and not c.exists(aY)then
pcall(c.writeFile,aY,"1")elseif not aW and c.exists(aY)then pcall(c.remove,aY)end end;if d then
d.info("pkg",string.format("Upgraded %s %s -> %s (%d file(s) dropped)",ao,tostring(aq.version),tostring(ar.version),
#au))end;return true,
{name=ao,from=aq.version,to=ar.version,dropped=au,origin=aH,enabled=aC}end
function a.forgetModules(ao)local ap=package and package.loadedFrom;if
type(ap)~="table"or type(ao)~="table"then return 0 end
local ar={}for at,as in ipairs(ao)do ar[as]=true end;local aq=0
for as,at in pairs(ap)do if ar[at]then package.loaded[as]=
nil;ap[as]=nil;aq=aq+1 end end;return aq end
function a.describeConflicts(ao)local ap={}
for ar,aq in ipairs(ao or{})do
if aq.kind=="file"then
ap[#ap+1]=string.format("%s is already installed by %s",aq.path,aq.other)else ap[#ap+1]=aq.detail end end;return table.concat(ap,"; ")end
function a.verifyLicenseKey(ao,ap)if
type(ao)~="table"or type(ao.license)~="table"then return true end;if not ao.license.requireKey then
return true end;if type(ap)~=u or ap==""then
return false,"license key required"end;local aq;do local at,au=pcall(require,H)
if at then aq=au end end
if
not aq or not aq.hash or not aq.ctEquals then return false,"crypto unavailable for license verification"end;local ar=aq.hash(ao.name.."|"..ap)
local as=ao.license.keys or{}
for au,at in ipairs(as)do if aq.ctEquals(ar,at)then return true end end;return false,"license key rejected (no matching hash)"end
local function Z(ao,ap,aq)
if not ao then return{state=A,reason="manifest path unknown"},nil end;local at,as=pcall(require,v)if not at or not as then return
{state=A,reason="signature support unavailable"},nil end
as.init({fs=c,serialize=k,log=d})local ar=as.verifyManifest(ao,aq)
if ar.state=="invalid"then
return ar,
x..
tostring(ao)..

"': its signature does not verify ("..
tostring(ar.reason).."). This is tampering or corruption, not a missing signature, and there is no override."..
"  [E-609 ERR_PKG_SIGNATURE_INVALID]"end
if as.requiresSignature()and not ap.allowUnsigned then
if ar.state==A then
return
ar,
"refusing to install an unsigned package: this machine is set to ".."require signatures (pkg trust require off, or --allow-unsigned for one install)."..
"  [E-610 ERR_PKG_SIGNATURE_REQUIRED]"end
if ar.state==z then
return ar,
x..
tostring(ao)..
"': its signature is valid but the key is not trusted here, and this machine "..

"is set to require signatures. Trust the publisher with 'pkg trust add <name> "..
tostring(ar.key)..
"' (fingerprint "..
tostring(ar.fingerprint)..

" -- compare it with the publisher over a channel that is NOT this package), "..
"or use --allow-unsigned for one install.".."  [E-610 ERR_PKG_SIGNATURE_REQUIRED]"end end;return ar,nil end;a._signGate=Z
function a._verificationGate(ao,ap)local as=(ao and ao.files)or{}local aq=type(ao and
ao.hashes)=="table"local ar=aq;if aq then
for av,au in ipairs(as)do if
type(ao.hashes[au])~=u then ar=false;break end end end
if ar then return true,nil,true end;if ap then return true,nil,false end
local at=
aq and"manifest is missing hashes for some files"or"manifest declares no file hashes"
return false,
"refusing to install unverified package '"..
tostring(ao and ao.name).."' ("..
at..
"). Re-run with --allow-unverified to override.".."  [E-607 ERR_PKG_UNVERIFIED]",false end
function a.install(ap,ao)ao=ao or{}local aB,aC=f(ao)if not aB then return false,aC end
if type(ap)~=u or ap==
""then return false,"invalid source directory"end;ap=c.normalize(ap)local aq,aw,aD,aE=j(ap)if not aq then return false,J..
ap..": "..tostring(aw)end
if aw=="oppm"then
aq.origin="openos"
if
type(aq.capabilities)~="table"or#aq.capabilities==0 then aq.capabilities=a.foreignDefaultCaps()aq.capsFromCompat=true
if d then
d.warn("pkg",
"Foreign (OpenOS/OPPM) package '"..
tostring(aq.name).."' declared no capabilities — granting the compat surface: "..
table.concat(aq.capabilities,", "))end end;if d then
d.info("pkg","Loaded OPPM-compat manifest for "..tostring(aq.name))end end;local aF,aG=a.verifyLicenseKey(aq,ao.licenseKey)
if not aF then return false,
"license check failed: "..tostring(aG)end;local aH,aI=O(aq)
if not aH then return false,"invalid manifest: "..aI end;local aJ,aK=V(aq,ao)if not aJ then return false,aK end
do
local aN=a.runtimeRefusal(aq)if aN and not ao.force then return false,aN end;if aN and d then
d.warn("pkg",
"Installing past a runtime requirement (force): "..aN)end end
if e[aq.name]and not ao.upgrading then local aN=e[aq.name].version
local aO=a.compareVersion(
aq.version or"0.0.0",aN or"0.0.0")
if aO>0 then return false,
string.format("%s %s is already installed and %s is newer — use `pkg upgrade %s`",aq.name,tostring(aN),tostring(aq.version),aq.name)end
return false,"already installed (uninstall first): "..aq.name end
do local aN=R(aq,ao._priorFiles)if aN then
return false,x..
tostring(aq.name).."': "..aN..
"  [E-612 ERR_PKG_PROTECTED_TARGET]"end end
local at=a.findConflicts(aq,ao.upgrading and aq.name or nil)if#at>0 and not ao.force then
return false,"conflicts: "..
a.describeConflicts(at).."  [E-613 ERR_PKG_CONFLICT]"end;if#at>0 and d then
d.warn("pkg",
"Installing "..tostring(aq.name)..
" over conflicts (--force): "..a.describeConflicts(at))end
do
local aN,aO,aP=a._verificationGate(aq,ao.allowUnverified)if not aN then return false,aO end
if
not aP and ao.allowUnverified and d then
d.warn("pkg","Installing UNVERIFIED package '"..
tostring(aq.name).."' (no/partial hashes) — operator override")end end;local as
do local aN,aO=Z(aD,ao,aE)if aO then return false,aO end
if
type(ao.expectKey)==u and n(aN)~=ao.expectKey:lower()then
return false,

string.format(
"refusing to install '%s': it must be signed by %s, ".."and this copy has %s",tostring(aq.name),h(ao.expectKey),
n(aN)and h(n(aN))or"no valid signature").."  [E-611 ERR_PKG_WRONG_PUBLISHER]"end;as=aN
if d then
if aN.state==N then
d.info("pkg","'"..
tostring(aq.name).."' signed by trusted publisher '"..
tostring(aN.label)..
"' ("..tostring(aN.fingerprint)..")")elseif aN.state==z then
d.warn("pkg","'"..
tostring(aq.name).."' is signed by an UNTRUSTED key "..

tostring(aN.fingerprint).." — 'pkg trust add <name> "..tostring(aN.key).."'")else
d.warn("pkg","'"..
tostring(aq.name).."' is UNSIGNED — installed on admin privilege alone")end end end;local au=nil
if type(aq.hashes)=="table"then local aO,aN=pcall(require,H)
if
not aO or not aN or not aN.hash or not aN.ctEquals then return false,
"crypto unavailable; cannot verify install hashes"end;au=aN end;local ar={}
for aO,aN in ipairs(aq.files)do do local aW,aV=pcall(require,"kernel.process")
if aW and
aV and aV.yieldCooperative then aV.yieldCooperative()end end;local aQ=aq.fileMap and
aq.fileMap[aN]local aP
if aQ then aP=c.normalize((aq._srcBase or ap)..
"/"..aQ)
if aq._srcBase and not
c.exists(aP)then local aV=aQ:match("^[^/]+/(.+)$")if aV then local aW=c.normalize(
aq._srcBase.."/"..aV)
if c.exists(aW)then aP=aW end end end else aP=c.normalize(ap..aN)end;local aR,aS=c.readFile(aP)
if not aR then
for aO,aV in ipairs(ar)do pcall(c.remove,aV)end;if c.exists(aP)then
return false,"cannot read source file "..
aP..": "..tostring(aS or"read failed")..
"  [E-605 ERR_PKG_FILE_UNREADABLE]"end
return false,
"missing source file: "..aP.."  [E-604 ERR_PKG_FILE_MISSING]"end
if au then local aV=aq.hashes[aN]
if aV then
if not au.ctEquals(au.hash(aR),aV)then for aO,aW in
ipairs(ar)do pcall(c.remove,aW)end
return false,"hash mismatch on "..aN..
"  [E-608 ERR_PKG_HASH_MISMATCH]"end end end;local aT,aU=c.writeFile(aN,aR)if not aT then
for aO,aV in ipairs(ar)do pcall(c.remove,aV)end
return false,"write failed for "..aN..": "..tostring(aU)end
ar[#ar+1]=aN end;local av=c.join(U,aq.name)if not c.exists(av)then
c.makeDirectory(av)end;aq._unverified=(type(aq.hashes)~="table")and
true or nil
do
local aN=aq.files or{}if type(aq.hashes)=="table"then
for aP,aO in ipairs(aN)do if
type(aq.hashes[aO])~=u then aq._unverified=true;break end end end end;aq._installedFrom=tostring(ap)
aq._sigState=as and as.state or A;aq._sigKey=as and as.key or nil
aq._sigLabel=as and as.label or nil;local aL,aM=k.saveFile(c,c.join(av,L),aq)if not aL then for aO,aN in ipairs(ar)do
pcall(c.remove,aN)end
return false,"manifest write failed: "..tostring(aM)end;local ax="e"
if

type(aq.service)=="table"and aq.service.defaultState=="disabled"then ax="d"
for aO,aN in ipairs(aq.files)do
local aP=tostring(aN):match("^/etc/rc%.d/(.+)%.lua$")if aP then pcall(c.writeFile,C..aP..B,"1")end end end;c.writeFile(c.join(av,"state"),ax)
e[aq.name]=aq;local ay=a.repoHints(aq)if#ay>0 then local aN=g()if aN and aN.learn then
pcall(aN.learn,ay,aq.name)end end
a.syncCriticalBackup()if d then
d.info("pkg",string.format("Installed %s v%s (%d files)",aq.name,aq.version,#ar))end
local az,aA=a.checkRequires(aq.name)if not az and d then
d.warn("pkg",string.format("%s installed with unmet requires: %s",aq.name,table.concat(aA,", ")))end
if not az then return true,
#ar..
" files (unmet requires: "..table.concat(aA,", ")..")"end;return true,#ar.." files"end
function a.runtimeRefusal(ao)if type(ao)~="table"then return nil end
local ap=tostring(ao.name or"this package")
if type(ao.lua)==u then local aq=ao.lua:match("^(%d+%.%d+)$")
local ar=tostring(
_VERSION or""):match("(%d+%.%d+)")
if aq and ar and a.compareVersion(ar,aq)<0 then
return
string.format(
"'%s' needs the Lua %s architecture; this CPU runs Lua %s. ".."Sneak-right-click the CPU (or APU) to switch its architecture, then reboot.",ap,aq,ar)end end
if type(ao.tos)==u then local ar=rawget(_G,"_TOS")
local aq=ar and ar.version
if aq and not a.satisfiesConstraint(aq,ao.tos)then return
string.format("'%s' needs TOS %s; this is TOS %s.",ap,ao.tos,aq)end end;return nil end
function a.describeContradictions(ao)local ap={}for ar,aq in ipairs(ao or{})do
ap[#ap+1]=tostring(aq.text)end;return table.concat(ap,"; ")end
function a.plan(ao,aq,ap)ap=ap or{}
if type(ao)~=u or ao==""then return nil,"invalid repo dir"end
if type(aq)~=u or aq==""then return nil,"invalid target name"end;ao=c.normalize(ao)
if
not c.exists(ao)or not c.isDirectory(ao)then return nil,"repo dir not found: "..ao end;local aw,az={},{}
local function ax(aG)if type(aG)~=u or aG==""then return end
aG=c.normalize(aG)if not az[aG]then az[aG]=true;aw[#aw+1]=aG end end;ax(ao)if type(ap.extraRoots)=="table"then
for aH,aG in ipairs(ap.extraRoots)do ax(aG)end end
local aE,aA=pcall(a.repoRoots)
if aE and type(aA)=="table"then for aH,aG in ipairs(aA)do ax(aG)end end;local as,at,au,ay={},{},{},{}
local function aF(aG,aI,aH)if e[aG]then return e[aG]end
if as[aG]then return as[aG]end;local aM,aL,aM,aK=o(aI)local aJ
for aM,aN in ipairs(aw)do local aO=c.join(aN,aG)
if c.exists(aO)then
local aP,aM,aQ=j(aO)
if aP and aP.name==aG then local aR=aK and S(aQ)or nil
if aK and aR~=aK then ay[aG]=
ay[aG]or{dir=aO,have=aR,want=aK,by=aH}if d then
d.warn("pkg",
"Passing over '"..
aG.."' in "..aN..
": "..tostring(aH).." requires it signed by another key")end elseif
aL and not a.satisfiesConstraint(
aP.version or"0.0.0",aL)then aJ=aJ or{m=aP,dir=aO,path=aQ}else
as[aG],at[aG],au[aG]=aP,aO,aQ;return aP end elseif aP and d then
d.warn("pkg","Ignoring '"..tostring(aG)..
"' in "..aN..": manifest name '"..
tostring(aP.name).."' does not match directory")end end end
if aJ then as[aG],at[aG],au[aG]=aJ.m,aJ.dir,aJ.path;return aJ.m end;return nil end;local av,aB=a.resolveInstallOrder(aq,aF)
if not av then
local aH=tostring(aB):match("^unknown package: (.+)$")local aG=aH and ay[aH]
if aG then
return nil,
string.format("%s requires '%s' signed by %s; no copy signed by that "..
"key was found (the one in %s has %s)",tostring(aG.by),aH,h(aG.want),aG.dir,
aG.have and h(aG.have)or K)end;return nil,"resolve failed: "..tostring(aB)end
for aH,aG in ipairs(av)do local aI=as[aG]if aI then local aJ,aK=O(aI)
if not aJ then return nil,"invalid manifest for '"..aG..
"': "..tostring(aK)end end end;local ar={order=av,dirs=at,expectKey={},contradictions={}}local function aC(aG,aH,aI)
ar.contradictions[#
ar.contradictions+1]={kind=aG,name=aH,text=aI,id=aG.."|"..tostring(aH)}end;local aD={}
for aH,aG in
ipairs(av)do local aI=as[aG]
if aI and type(aI.requires)=="table"then
for aH,aJ in
ipairs(aI.requires)do local aK,aH,aH,aL=o(aJ)
if aK and aL then local aO=aD[aK]
if not aO then aD[aK]={key=aL,by=aG}elseif aO.key~=aL then
aC("pins",aK,string.format("%s requires '%s' signed by %s, but %s requires it signed by %s",aO.by,aK,h(aO.key),aG,h(aL)))end end;local aM=aK and t(aK)local aN={}
if aM then
aN=q(aG,aJ,aM,T(aM),M..tostring(aM.name))elseif aK and as[aK]then local aO=S(au[aK])
aN=q(aG,aJ,as[aK],aO,"the copy in "..tostring(at[aK]))if aL and aO==aL and not ar.expectKey[aK]then
ar.expectKey[aK]=aL end end;for aH,aO in ipairs(aN)do
ar.contradictions[#ar.contradictions+1]=aO end end end
if aI then for aH,aJ in ipairs(Y(aI,S(au[aG])))do
ar.contradictions[#ar.contradictions+1]=aJ end
if not e[aG]then
local aJ=a.runtimeRefusal(aI)if aJ then aC("runtime",aG,aJ)end end end end;return ar end
function a.installWithDeps(aq,ap,ao)ao=ao or{}local au,av=f(ao)if not au then return false,av end
local ar,aw=a.plan(aq,ap,ao)if not ar then return false,aw end
if#ar.contradictions>0 then
local ax=a.describeContradictions(ar.contradictions)
if not ao.force then return false,x..ap.."': "..ax end;if d then
d.warn("pkg","Installing '"..ap.."' past contradictions (force): "..ax)end end;local as,at={},{}
for ay,ax in ipairs(ar.order)do
if e[ax]then at[#at+1]=ax else local aA=ar.dirs[ax]or
c.join(c.normalize(aq),ax)local az=ao.licenseKey
if ao.licenseKeys and
ao.licenseKeys[ax]then az=ao.licenseKeys[ax]elseif ax~=ap then az=nil end
local aB,aC=a.install(aA,{licenseKey=az,session=ao.session,allowUnverified=ao.allowUnverified,allowUnsigned=ao.allowUnsigned,force=ao.force,expectKey=ar.expectKey[ax]})
if not aB then for ay,aD in ipairs(as)do
pcall(a.uninstall,aD,{session=ao.session})end;return false,"install of "..
ax.." failed: "..tostring(aC)end;as[#as+1]=ax end end;return true,{installed=as,skipped=at}end
function a.uninstall(ao,ap)local as,at=f(ap)if not as then return false,at end;if ao=="tos-core"then return false,
"refusing to uninstall tos-core"end;local aq=e[ao]if not aq then return
false,w..ao end
if not ap or not ap._internalUpgrade then
for av,aw in
pairs(e)do
if av~=ao and type(aw.requires)=="table"then for ay,ax in
ipairs(aw.requires)do
if
type(ax)=="table"and ax.name==ao and not ax.optional then return false,"required by "..av end end end end end;do local av=package.loaded[I]
if av and av.has(ao)then av.drop(ao)end end
for aw,av in ipairs(aq.files or{})do
local ax,ay=pcall(c.remove,av)if not ax and d then
d.warn("pkg","Could not remove "..av..": "..tostring(ay))end end
for aw,av in ipairs(aq.files or{})do
local ax=tostring(av):match("^(.*)/[^/]*$")
while ax and select(2,ax:gsub("/",""))>2 do local ay=
c.isDirectory(ax)and c.list(ax)
if not ay or#ay>0 then break end;pcall(c.remove,ax)ax=ax:match("^(.*)/[^/]*$")end end;a.forgetModules(aq.files)local au=c.join(U,ao)
local function ar(av)
if
c.isDirectory(av)then local aw=c.list(av)or{}for ay,ax in ipairs(aw)do local az=ax:gsub("/$","")if az~=""then
ar(c.join(av,az))end end end;pcall(c.remove,av)end;ar(au)e[ao]=nil;a.syncCriticalBackup()if d then
d.info("pkg","Uninstalled "..ao)end;return true end;local r={"/usr/repo","/var/repo"}
local function s()local ao,aq={},{}local function ar(au)
if
au and au~=""and au~="/"and not aq[au]then aq[au]=true;ao[#ao+1]=au end end
if c.mounts then
local av,au=pcall(c.mounts)if av and type(au)=="table"then
for ax,aw in ipairs(au)do ar(aw.mountPoint)end end end;if c.exists("/mnt")then
for av,au in ipairs(c.list("/mnt")or{})do
local aw=au:gsub("/$","")if aw~=""then ar("/mnt/"..aw)end end end
local ap,as={},{}local function at(au)
if au and not as[au]then as[au]=true;ap[#ap+1]=au end end
for av,au in ipairs(ao)do at(au)
for av,aw in
ipairs(c.list(au)or{})do local ax=aw:gsub("/$","")
if ax~=""and not ax:find("[/\\]")then
local ay=c.join(au,ax)
local az,aA=pcall(function()return c.isDirectory(ay)end)if az and aA then at(ay)end end end end;return ap end
function a.repoRoots()local ao={}for aq,ap in ipairs(r)do ao[#ao+1]=ap end;for aq,ap in ipairs(s())do
ao[#ao+1]=ap end;return ao end
function a.listRepo(ao)if type(ao)~=u or ao==""then return{}end
ao=c.normalize(ao)
if not c.exists(ao)or not c.isDirectory(ao)then return{}end;local ap={}local aq=c.list(ao)or{}
for as,ar in ipairs(aq)do local at=ar:gsub("/$","")
if
at~=""then local au=c.join(ao,at)
if c.isDirectory(au)then local av,aw=j(au)
if av then
ap[#ap+1]={name=av.name,version=av.version,description=av.description,category=
(
type(av.category)==u and av.category~="")and av.category or"misc",author=av.author,kind=av.kind,source=aw,dir=au,requires=av.requires,recommends=av.recommends}end end end end
table.sort(ap,function(ar,as)
return(ar.name or"")< (as.name or"")end)return ap end
function a.findInRepos(ao,ap)local aq={}for as,ar in ipairs(r)do aq[#aq+1]=ar end
if
type(ap)=="table"then for as,ar in ipairs(ap)do aq[#aq+1]=ar end end;for as,ar in ipairs(s())do aq[#aq+1]=ar end
for as,ar in ipairs(aq)do
local at=c.join(ar,ao)
if c.exists(at)and c.isDirectory(at)then local au=j(at)if
au and au.name==ao then return at,ar end;if au and d then
d.warn("pkg","Ignoring '"..
tostring(ao).."' in "..
ar..": manifest name '"..
tostring(au.name).."' does not match directory")end end end;return nil end
local function _(ao,ap)
if type(ao)==u and ao:find("/")then
local as=c.normalize(ao:gsub("/$",""))local at=as:match("[^/]+$")
if
at and c.exists(as)and c.isDirectory(as)then local au=j(as)if au and au.name==at then local av=as:match(D)if av==""then av="/"end;return
av,at end;return nil,"not a package directory (or name mismatch): "..
ao end;return nil,"package not found in any repo: "..ao end;local aq,ar=a.findInRepos(ao,ap)if not aq then return nil,
"package not found in any repo: "..tostring(ao)end
return ar,ao end
function a.planByName(ap,ao)ao=ao or{}local as,aq=_(ap,ao.extraRoots)
if not as then return nil,aq end;local ar,at=a.plan(as,aq,{extraRoots=ao.extraRoots})if
not ar then return nil,at end;ar.target=aq;return ar end
function a.installByName(ap,ao)ao=ao or{}local as,at=f(ao)if not as then return false,at end
local aq,ar=_(ap,ao.extraRoots)if not aq then return false,ar end;ap=ar
return
a.installWithDeps(aq,ap,{licenseKey=ao.licenseKey,licenseKeys=ao.licenseKeys,session=ao.session,allowUnverified=ao.allowUnverified,allowUnsigned=ao.allowUnsigned,extraRoots=ao.extraRoots,force=ao.force})end
function a.computeLicenseHash(ao,ap)if type(ao)~=u or type(ap)~=u then
return nil,"package name and key must be strings"end;local ar,aq=pcall(require,H)
if
not ar or not aq or not aq.hash then return nil,"crypto unavailable"end;return aq.hash(ao.."|"..ap)end
function a.listAllAvailable(ao)ao=ao or{}local aq={}local ap={}
local function ar(as)if not c.exists(as)or
not c.isDirectory(as)then return end;for au,at in
ipairs(a.listRepo(as))do
if not aq[at.name]then aq[at.name]=true;at.root=as;ap[#ap+1]=at end end end;for at,as in ipairs(r)do ar(as)end;for at,as in ipairs(s())do ar(as)end;if
ao.includeRemote then
for at,as in ipairs(a.listRemoteAvailable(ao))do if not aq[as.name]then
aq[as.name]=true;ap[#ap+1]=as end end end;return ap end
function a.listRemoteAvailable(ao)local ap=g()
if not ap or type(ap.search)~=G then return{}end;local as,ar=pcall(ap.search,ao or{})if
not as or type(ar)~="table"then return{}end;local aq={}
for au,at in ipairs(ar)do
if type(at)=="table"and
type(at.name)==u then
aq[#aq+1]={name=at.name,version=at.version,description=at.description,category=at.category or"remote",kind=at.kind,author=at.author,requires=at.requires,recommends=at.recommends,repo=at.repo,remote=true}end end;return aq end
function a.installFromFloppy(ao)ao=ao or{}local as,at=f(ao)if not as then return false,at end
local au=(
type(ao.confirm)==G)and ao.confirm or function()return false end;local ar={}local ap={}local aq={}
for ax,aw in ipairs(s())do for ax,ay in ipairs(a.listRepo(aw))do
aq[#aq+1]={name=ay.name,dir=ay.dir,mount=aw}end end;local av=#aq
for ax,aw in ipairs(aq)do
if au(aw.name,aw.dir,ax,av)then
local ay,az=a.installByName(aw.name,{extraRoots={aw.mount},session=ao.session,allowUnverified=ao.allowUnverified,allowUnsigned=ao.allowUnsigned,force=ao.force})if ay then ar[#ar+1]=aw.name else
ap[#ap+1]=aw.name.." ("..tostring(az)..")"end else
ap[#ap+1]=aw.name.." (declined)"end end;return true,{installed=ar,skipped=ap}end
function a.runInstaller(ao)pcall(require,"io")
local ar,ap=pcall(require,"shell.pkgpicker")
if not ar or type(ap)~="table"or not ap.run then return false,
"picker unavailable: "..tostring(ap)end;local as,aq,at=pcall(ap.run,ao)if not as then
return false,"installer error: "..tostring(aq)end;if aq==false then return false,
at or"no installable packages found"end;return true end;local aa={["tos-core"]=true}
function a.exportDisk(ao,ap)ap=ap or{}local av,aw=f(ap)if not av then
return false,aw end;if type(ao)~=u or ao==""then
return false,"invalid target directory"end;ao=c.normalize(ao)if not ao then return false,
"invalid target path"end
local ax={"/","/tos","/etc","/var","/usr","/home","/root","/public","/init.lua","/bios.lua"}for az,ay in ipairs(ax)do
if ao==ay or ao:sub(1,#ay+1)==ay.."/"then return false,
"refusing to export into a system path: "..ao end end
if not
c.exists(ao)or not c.isDirectory(ao)then return false,
"target does not exist or is not a directory: "..ao end;local ar=nil
if type(ap.only)=="table"and#ap.only>0 then ar={}for az,ay in
ipairs(ap.only)do ar[ay]=true end end;local as,at,aq={},0,{}local au={}for ay in pairs(e)do au[#au+1]=ay end
table.sort(au)
for az,ay in ipairs(au)do local aA=e[ay]
if not aa[ay]and(not ar or ar[ay])then
local aB=c.join(ao,ay)local aC,aD=k.saveFile(c,c.join(aB,L),aA)
if not aC then
aq[#aq+1]=ay..
": manifest write failed ("..tostring(aD)..")"else local aE=true
for az,aF in ipairs(aA.files or{})do local aG,aH=c.readFile(aF)
if not aG then
aq[#aq+1]=
ay..
(c.exists(aF)and
(": cannot read installed file "..aF..
": "..tostring(aH or"read failed"))or
(": missing installed file "..aF))aE=false else local aI,aJ=c.writeFile(c.join(aB,aF),aG)if not aI then
aq[#aq+1]=
ay..": write "..aF.." ("..tostring(aJ)..")"aE=false else at=at+1 end end end;if aE then as[#as+1]=ay end end end end
if ar then
for ay in pairs(ar)do if not e[ay]then
aq[#aq+1]=ay..": not installed (skipped)"elseif aa[ay]then
aq[#aq+1]=ay..": is the OS core, not an add-on (skipped)"end end end
do
local ay={"-- Optional Utilities set manifest — generated by `pkg make-disk`.","return {","  set = \"optional-utilities\",","  disks = 1,","  packages = {"}
for aC,aB in ipairs(as)do local aD=e[aB]or{}local aE,aF={},{}
for aC,aG in ipairs(aD.requires or{})do local aH=(
type(aG)=="table")and aG.name or
tostring(aG):match("^(%S+)")if aH then
aE[#aE+1]=string.format("%q",aH)end end;for aC,aG in ipairs(aD.recommends or{})do
aF[#aF+1]=string.format("%q",tostring(aG))end
ay[#ay+1]=string.format("    [%q] = { disk = 1, version = %q, category = %q, kind = %q,",aB,tostring(
aD.version or"?"),tostring(aD.category or"misc"),tostring(aD.kind or"?"))
ay[#ay+1]=string.format("      description = %q,",tostring(aD.description or""))
ay[#ay+1]=string.format("      requires = { %s }, recommends = { %s } },",table.concat(aE,", "),table.concat(aF,", "))end;ay[#ay+1]="  },"ay[#ay+1]="}"ay[#ay+1]=""
local az,aA=c.writeFile(c.join(ao,"optutil-set.lua"),table.concat(ay,"\n"))
if not az then aq[#aq+1]="optutil-set.lua: "..tostring(aA)end end
do
local ay=table.concat({"TOS Optional Utilities","","Insert this disk on a TOS machine and run, as admin:","","    pkg install","","That opens the picker: tick what you want, press Enter.","","Non-interactive (scripts):","    pkg install <name> [<name>...]","    pkg install --all --yes",""},"\n")local az,aA=c.writeFile(c.join(ao,"README.txt"),ay)
if
not az then aq[#aq+1]="README.txt: "..tostring(aA)end end;if d then
d.info("pkg",string.format("Exported %d package(s), %d file(s) to %s",#as,at,ao))end
return true,{packages=as,files=at,problems=aq,target=ao}end;a.DEFAULT_REPO_ROOTS=r;a._loadAnyManifest=j
function g()
local ap,ao=pcall(require,"kernel.pkgremote")if not ap or type(ao)~="table"then
return nil,"remote package support unavailable"end;if ao.init then
pcall(ao.init,{log=d,validRepoHint=ad})end;return ao end;function a.knownRepos()local ao=g()if not ao or not ao.known then return{}end;return
ao.known()end
function a.forgetRepo(ao,ap)
local ar,as=f(ap)if not ar then return false,as end;local aq,at=g()if not aq then return false,at end;return
aq.forget(ao)end
local function i()local ap,ao=pcall(require,v)if not ap or not ao then
return nil,"signature support unavailable"end
ao.init({fs=c,serialize=k,log=d})return ao end
function a.trustList()local ao=i()if not ao then return{}end;return ao.listKeys()end
function a.trustAdd(ao,ap,aq)local as,at=f(aq)if not as then return false,at end;local ar,au=i()
if not ar then return false,au end;return ar.addKey(ao,ap)end
function a.trustRemove(ao,ap)local ar,as=f(ap)if not ar then return false,as end;local aq,at=i()if not aq then
return false,at end;return aq.removeKey(ao)end
function a.trustRequire(ao,ap)local ar,as=f(ap)if not ar then return false,as end;local aq,at=i()if not aq then
return false,at end;return aq.setRequireSignature(ao)end;function a.trustRequired()local ao=i()if not ao then return false end
return ao.requiresSignature()end
function a.discoveredPolicy()local ao=i()if not ao or not
ao.discoveredPolicy then return"off"end;return
ao.discoveredPolicy()end
function a.trustDiscovered(ao,ap)local ar,as=f(ap)if not ar then return false,as end;local aq,at=i()if not aq then
return false,at end;return aq.setDiscoveredPolicy(ao)end
function a.checkSignature(ao)
if type(ao)~=u or ao==""then return nil,"invalid directory"end;local ap,ar=i()if not ap then return nil,ar end
local aq,as,at,au=j(c.normalize(ao))
if not aq then return nil,J..ao..": "..tostring(as)end;return ap.verifyManifest(at,au),aq end
function a.signPackage(ap,aq,ao)ao=ao or{}local at,au=f(ao)if not at then return nil,au end;local ar,av=i()if not ar then return nil,
av end;if type(ap)~=u or ap==""then
return nil,"invalid directory"end;local aw,ax,ay=j(c.normalize(ap))
if
not aw then return nil,J..ap..": "..tostring(ax)end;local as,az=ar.seedFromPassphrase(aq,ao.signer)
if not as then return nil,az end;return
ar.signManifest(ay,as,{signer=ar.normalizeLabel(ao.signer)})end
function a.signingKey(ao,ap)local aq,au=i()if not aq then return nil,au end
local ar,av=aq.seedFromPassphrase(ao,ap)if not ar then return nil,av end
local aw,as=pcall(require,"kernel.ed25519")
if not aw or not as then return nil,"ed25519 support unavailable"end;local at=as.publickey(ar)
if not at then return nil,"cannot derive the key"end;return aq.binToHex(at)end
function a.repos()local ao=g()if not ao then return{}end;return ao.repos()end
function a.addRepo(ao,ap,aq,ar)local at,au=f(ar)if not at then return false,au end;local as,av=g()
if not as then return false,av end;return as.addRepo(ao,ap,aq)end
function a.removeRepo(ao,ap)local ar,as=f(ap)if not ar then return false,as end;local aq,at=g()if not aq then
return false,at end;return aq.removeRepo(ao)end
function a.searchRemote(ao)local ap=g()if not ap then return{}end;return ap.search(ao)end;local ab,ac=8,16;local function l(ao)
return
(tostring(ao):gsub("%s*%[E%-%d%d%d ERR_[%w_]+%]","")).."  [E-603 ERR_PKG_DEPENDENCY]"end
local function an(ao)
if
type(ao)=="table"then return ao.name,ao.version,ao.optional==true end;if type(ao)==u then local ap,aq=ao:match("^(%S+)%s+(.+)$")
if ap then return ap,aq,false end;return ao,nil,false end end
function a.installRemote(ap,ao)ao=ao or{}local aB,aC=f(ao)if not aB then return false,aC end;local av,aD=g()if
not av then return false,aD end
local function ay(aH)local aI={}for aJ,aK in pairs(ao)do aI[aJ]=aK end;for aJ,aK in
pairs(aH)do aI[aJ]=aK end;return aI end;local at=a.discoveredPolicy()local aq="  [E-606 ERR_PKG_UNTRUSTED_SOURCE]"
local function aE(aH,aI,aK,aL,aJ,aM)
local aQ=i()local aO="'"..
aH.."' is only in an unconfigured repo ("..tostring(aJ)..")"if not aQ then
return
false,aO..", and signatures cannot be checked here"..aq end
local aN=aQ.verifyManifest(aK,aL)if aN.state==N then return true end
if aN.state=="invalid"then return false,
aO..
", and its signature does not verify ("..tostring(aN.reason)..")"..aq end
if aN.state~=z then return false,
aO..", and it is unsigned. An unsigned package installs only from a "..
"repo an admin added (pkg repo add)"..aq end;local aR="pkg trust add <name> "..tostring(aN.key)
if
aI.kind=="service"or aI.kind=="driver"then
return false,
aO..
". It is a "..
aI.kind..
", which runs outside the sandbox, and "..
"its key ("..tostring(aN.fingerprint)..
") is not trusted here: trust it first, ".."with  "..aR..aq end
if at~="tofu"or type(ao.confirmKey)~=G then
return false,
aO..
", and its key ("..

tostring(aN.fingerprint)..") is not trusted "..
"here"..
(at~="tofu"and
(" (pkg trust discovered is "..at..")")or"")..". To trust it:  "..aR..aq end
local aP=ao.confirmKey({name=aH,repo=aJ,by=aM,kind=aI.kind,key=aN.key,fingerprint=aN.fingerprint,signer=aN.signer})if type(aP)~=u or aP==""then
return false,"not installed: the key of '"..
aH.."' ("..tostring(aN.fingerprint)..
") was not trusted"..aq end
local aS,aT=a.trustAdd(aP,aN.key,ao)
if not aS then return false,
"could not trust the key of '"..aH.."': "..tostring(aT)..aq end;if d then
d.info("pkg","Trusted key "..
tostring(aN.fingerprint).." as '"..
aP.."' (first use, for '"..aH.."' from "..
tostring(aJ)..")")end
return true end;local au,aw,az={},{},{}
local function ax()for aI,aH in ipairs(au)do av.cleanup(aH.dir)end end
local function aA(aH,aK,aJ,aI,aL,aM)if az[aH]then return true end;local aO=
aI and("dependency '"..
tostring(aH).."' of '"..aI.."': ")or""if aK>ab then return
false,
l(aO.."dependencies nest deeper than "..ab)end;if#au>=ac then
return false,l(
"the fetch would bring in more than "..ac.." packages")end;az[aH]=true
local aQ,aR,aP=av.fetch(aH,ay({hints=aL,discoveredPolicy=at}))
if not aQ then
if aI then return false,
l(aO..tostring(aR)..
" (if you have it on a disk, `pkg install "..tostring(aH).."` it first)")end;return false,aR end;local aS={name=aH,dir=aQ,meta=aP,expectKey=aM}au[#au+1]=aS
local aN,aV,aT,aU=j(aQ)
if type(aN)~="table"then return false,aO.."no readable manifest"end
if aP and aP.discovered then local aX,aW=aE(aH,aN,aT,aU,aP.discovered,aI)if not aX then return
false,aI and l(aO..aW)or aW end end
if aJ and
not a.satisfiesConstraint(aN.version or"0.0.0",aJ)then return false,
l(aO..
"needs "..aJ..", and the repo has "..
tostring(aN.version or"no version"))end
for aV,aW in
ipairs(type(aN.requires)=="table"and aN.requires or{})do local aX,aY,aZ=an(aW)
if aX and not aZ then local a_=t(aX)
if a_ then
if aY and not
a.satisfiesConstraint(a_.version or"0.0.0",aY)then return false,
l(("'%s' needs %s %s, and %s is installed -- `pkg upgrade %s` first"):format(aH,aX,aY,tostring(
a_.version or"?"),aX))end else local ba=
type(aW)=="table"and type(aW.repos)=="table"and aW.repos or nil;local bb=

type(aW)=="table"and type(aW.key)==u and aW.key:lower()or nil
local bc,bd=aA(aX,aK+1,aY,aH,ba,bb)if not bc then return false,bd end end end end;aw[#aw+1]=aS;return true end;local aF,aG=aA(ap,0)if not aF then ax()return false,aG end;local ar,as={},nil
for aI,aH in
ipairs(aw)do
local aJ,aK=a.install(aH.dir,aH.expectKey and ay({expectKey=aH.expectKey})or ao)
if not aJ then ax()
local aL=(
aH.name~=ap and("dependency '"..aH.name.."': ")or"")..tostring(aK)..
(#ar>0 and
(
" (installed before it stopped: "..table.concat(ar,", ")..")")or"")return false,aH.name~=ap and l(aL)or aL end
if d then
d.info("pkg","Installed '"..
tostring(aH.name)..
"' from "..

(
aH.meta and aH.meta.discovered and(
tostring(aH.meta.discovered)..", a repo nobody configured")or
("repo '"..tostring(aH.meta and aH.meta.repo).."'")).. (
aH.name~=ap and(" as a dependency of '"..ap.."'")or""))end;if aH.name==ap then as=aH.meta else ar[#ar+1]=aH.name end end;ax()as=as or{}as.dependencies=ar;return true,as end end