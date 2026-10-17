local j="string"local h={}h.OWNER="Evan450"h.REPO="TOS-Terminal-Operating-System-"
h.STAGE="/var/repair"h.MAX_FILE_BYTES=128*1024;h.MAX_FILES=64;h.SPACE_MARGIN=16*1024;local function l()
local a=package.loaded["kernel.process"]
if a and a.yieldCooperative then pcall(a.yieldCooperative)end end
function h.deps(a)a=a or{}local b=
rawget(_G,"_TOS")or{}
a.fs=a.fs or b.fs or package.loaded["kernel.fs"]if not a.crypto then local d,e=pcall(require,"kernel.crypto")
a.crypto=d and e or nil end
if not a.internet then
local c,d=pcall(require,"kernel.internet")a.internet=c and d or nil end;if a.manifest==nil then local c,d=pcall(require,"system_manifest")a.manifest=
c and d or nil end
if
not a.anchor then
a.anchor=function()local c=b.kernel;if c and c.verifyManifestHash then
return c.verifyManifestHash()end
return false,"kernel anchor check unavailable"end end;if a.build==nil then a.build=b.build end;a.log=a.log or b.log or
package.loaded["kernel.log"]return a end
function h.sourceRef(a,b)if type(b)==j and b~=""then
return b,"the ref you asked for ("..b..")"end;if
type(a)==j and a:match("^%x+$")then
return"build-"..a,"this machine's own release (build "..a..")"end
return"main",
"the latest release -- this machine's build ("..
tostring(a)..") has no tag of its own, so only files that still match it can be repaired"end
function h.urlFor(a,b)return
string.format("https://raw.githubusercontent.com/%s/%s/%s%s",h.OWNER,h.REPO,a,b)end;function h.isOperatorState(a)return a:sub(1,5)=="/etc/"end
function h.damaged(a)
a=h.deps(a)local d,e=a.fs,a.crypto;local c,b={},{}
for g,f in ipairs(
type(a.manifest)=="table"and a.manifest or{})do l()local o=
type(f)=="table"and f.path or nil
if type(o)==j then local q=type(f.hash)==j and
f.hash:lower()or nil;local p
if not
d.exists(o)then p="missing"elseif q then local s,r=pcall(d.readFile,o)
if not s or type(r)~=j then
p="unreadable"elseif e.hash(r):lower()~=q then p="changed"end end
if p then
if h.isOperatorState(o)then
b[#b+1]={path=o,why=p..
"; under /etc, so it is ".."operator state -- put it back with `srm restore` or by hand"}elseif not q then
b[#b+1]={path=o,why=p..
"; the manifest has no ".."digest for it, so a fetched copy could not be checked"}else c[#c+1]={path=o,hash=q,reason=p,critical=f.critical}end end end end;return c,b end
function h.trustManifest(a,b)b=b or{}
if
type(a.manifest)~="table"or#a.manifest==0 then
return false,
"the system manifest is missing or unreadable, so there is nothing to check a "..
"fetched file against. Reinstall from the network installer or install media."end;local d,c=a.anchor()
if d then return true,"the manifest matches its EEPROM anchor"end;c=tostring(c or"")
if c:find("no anchored hash",1,true)then if b.unanchored then
return true,
"the manifest is NOT anchored in the EEPROM; trusting it because ".."--unanchored was given"end
return false,

"the manifest is not anchored in the EEPROM, so a tampered one could not be "..
"told apart. Anchor it with `verify anchor` if you trust it, or pass --unanchored to ".."accept it for this repair."end
return false,
"the manifest failed its EEPROM anchor ("..
c.."). It is the thing that "..
"says what correct looks like, and it is in doubt: online repair will not trust it."end
local function m()return{lines={},fixed=0,staged=0,rejected=0,ok=false}end
local function i(a,b,c)a.lines[#a.lines+1]={text=b,sev=c or"info"}end
function h.plan(a,b)a=h.deps(a)b=b or{}local c=m()local e,g=h.trustManifest(a,b)
c.trusted=e;i(c,g,e and"ok"or"err")local d,f=h.damaged(a)
c.damaged,c.skipped=d,f;local o,p=h.sourceRef(a.build,b.ref)c.ref=o
if#d==0 then
i(c,"every system file with a digest matches it -- nothing to repair online","ok")else
i(c,string.format("%d file(s) fail their digest; source: %s",#d,p),"info")for r,q in ipairs(d)do
i(c,string.format("  %-8s %s",q.reason:upper(),q.path),"warn")end end;for r,q in ipairs(f)do
i(c,"  not touched: "..q.path.." ("..q.why..")","info")end;c.ok=e;return c end
local function n(a,b)
if a.spaceFree then local d,c=pcall(a.spaceFree,b or"/")if
d and type(c)=="number"then return c end end;return nil end;local function k(a)pcall(a.remove,h.STAGE)end
function h.run(a,b)a=h.deps(a)b=b or
{}local c=h.plan(a,b)
if not b.apply then if#c.damaged>0 and c.trusted then
i(c,"Dry run: nothing was fetched or changed. Add --apply to repair.","info")end;return c end;c.ok=false
if not c.trusted then i(c,"Nothing was changed.","err")return c end;if#c.damaged==0 then c.ok=true;return c end
if
#c.damaged>h.MAX_FILES then
i(c,string.format("%d files are broken -- more than the %d an online repair will ".."take on. That is a reinstall, not a repair.",
#c.damaged,h.MAX_FILES),"err")return c end;local e=a.internet
if not
(e and e.available and e.available())then
local g=e and e.status and e.status()or{}
i(c,"No usable internet card: "..
tostring(g.reason or"the internet module is ".."unavailable")..". Nothing was changed.","err")return c end;local d=a.fs;k(d)local f={}
for o,g in ipairs(c.damaged)do l()local q=n(d,h.STAGE)
if q and q<h.MAX_FILE_BYTES+
h.SPACE_MARGIN then k(d)
i(c,string.format(
"Not enough free disk to stage the next file (%d KB free). ".."Nothing was changed.",math.floor(q/1024)),"err")return c end;local p=h.STAGE..g.path;local s=p:match("^(.*)/[^/]+$")if
s and d.makeDirectory then pcall(d.makeDirectory,s)end
local t=h.urlFor(c.ref,g.path)
local u,v=e.download(t,p,{fs=d,maxBytes=h.MAX_FILE_BYTES})if not u then k(d)
i(c,"Could not fetch "..g.path..
": "..tostring(v)..". Nothing was changed.","err")return c end
local r=d.readFile(p)
if
type(r)==j and a.crypto.hash(r):lower()==g.hash then f[#f+1]={item=g,path=p}c.staged=c.staged+1 else
c.rejected=c.rejected+1
i(c,"REJECTED the fetched "..g.path..
": it does not match this machine's ".."manifest"..
(c.ref=="main"and
" (the published release has probably moved on)"or""),"warn")pcall(d.remove,p)end;r=nil end
for o,g in ipairs(f)do l()local p=d.readFile(g.path)
if type(p)==j and
a.crypto.hash(p):lower()==g.item.hash then
local q=d.writeFileAtomic or d.writeFile;local r,s=q(g.item.path,p)
if r then c.fixed=c.fixed+1
i(c,"repaired "..
g.item.path.." ("..
g.item.reason..", digest verified)","ok")if a.log and a.log.warn then
a.log.warn("netrepair","Replaced "..g.item.path..
" from "..c.ref.." ("..g.item.reason..
", digest verified)")end else
i(c,
"could not write "..g.item.path..": "..tostring(s),"err")end else
i(c,"the staged copy of "..
g.item.path.." changed before it was written; ".."left alone","err")end end;k(d)
c.ok=(c.rejected==0)and(c.fixed==#c.damaged)if c.fixed>0 then
i(c,"If you keep an SRM baseline, take it again ('srm baseline') so it ".."describes the repaired files.","info")end;return c end;return h