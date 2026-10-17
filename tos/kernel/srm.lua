local p="string"local n={}n.VERSION=1;n.DIR="/var/srm"n.INDEX="/var/srm/index.dat"
n.STORE="/var/srm/store"n.LAST="/var/srm/last.dat"n.MAX_STORE_BYTES=128*1024;do
local b,a=pcall(require,"kernel.errors")
n.errors=(b and type(a)=="table")and a or nil
n.BASIC_CODES=n.errors and n.errors.biosTable()or{}end;local function q(a)
local b,c=pcall(require,a)if b then return c end end
function n.deps(a)a=a or{}
local c=_G._TOS or{}
local b={fs=a.fs or c.fs,serialize=a.serialize or q("kernel.serialize"),crypto=a.crypto or c.crypto or
q("kernel.crypto"),log=a.log or c.logObj,eeprom=a.eeprom,component=a.component}
if not b.eeprom then local d=b.component or q("component")
if d and d.list then
local f,e=pcall(function()return
d.list("eeprom")()end)
if f and e then local g,h=pcall(d.proxy,e)if g then b.eeprom=h end end end end;return b end
local function u()local a=_G._TOS and _G._TOS.kernel
if a and a.gc then pcall(a.gc)return end;if type(collectgarbage)=="function"then
pcall(collectgarbage,"collect")end end;local t=nil
local function r()if t==nil then local b,a=pcall(require,"kernel.process")
t=(b and a and
a.yieldCooperative)and a or false end;if t then
t.yieldCooperative()end end;local function s(a)
return{title=a,findings={},counts={ok=0,info=0,warn=0,err=0},fixed=0}end;n.newReport=s
local function o(a,c,b)b=b or"info"a.findings[
#a.findings+1]={text=c,sev=b}a.counts[b]=(
a.counts[b]or 0)+1;return a end;n.add=o;function n.worst(a)local b=a and a.counts or{}if(b.err or 0)>0 then
return"err"end;if(b.warn or 0)>0 then return"warn"end
return"ok"end
function n.parseFault(a)if
type(a)~=p then return nil end
local b=a:match("^SRM:(%S+)")or a:match("\nSRM:(%S+)")if not b or b==""then return nil end;return b end;function n.stripFault(a)if type(a)~=p then return""end
local b=a:gsub("\nSRM:%S*",""):gsub("^SRM:%S*\n?","")return b end
function n.readFault(a)
a=n.deps(a)local c=a.eeprom;if not c or not c.getData then return nil end
local e,f=pcall(c.getData)if not e then return nil end;local b=n.parseFault(f)if not b then return nil end;local d=
n.errors and n.errors.find(b)return
{code=b,why=n.BASIC_CODES[b]or
"unrecognised SRM Basic code (newer BIOS?)",err=d and n.errors.label(d)or nil}end
function n.clearFault(a)a=n.deps(a)local b=a.eeprom;if
not b or not b.getData or not b.setData then return false,"no EEPROM"end
local d,c=pcall(b.getData)if not d then return false,"EEPROM unreadable"end;if
not n.parseFault(c)then return true end
local e=pcall(b.setData,n.stripFault(c))if not e then return false,"EEPROM write failed"end;return true end
local y={"/init.lua","/tos/kernel/init.lua","/tos/kernel/log.lua","/tos/kernel/hal.lua","/tos/kernel/event.lua","/tos/kernel/process.lua","/tos/kernel/fs.lua","/tos/kernel/serialize.lua","/tos/kernel/display.lua","/tos/shell/init.lua"}
function n.criticalPaths(a)a=n.deps(a)local c,d=a.fs,a.serialize
local function e(g,h)if not
(c and d and c.exists and c.exists(g))then return nil end
local j=c.readFile(g)if type(j)~=p then return nil end
local k=d.decode(j,{maxBytes=64*1024})if type(k)~="table"then return nil end;local i=h(k)if
type(i)=="table"and#i>0 then return i end end
local b=e("/var/pkg/installed/tos-core/package.lua",function(g)local h={}
if type(g.critical)=="table"then for j,i in
ipairs(g.critical)do if type(i)==p then h[#h+1]=i end end end;return h end)if b then return b,"tos-core/package.lua"end
b=e("/etc/critical.bak",function(g)local h={}for j,i in ipairs(g)do if
type(i)==p then h[#h+1]=i end end;return h end)if b then return b,"critical.bak"end;local f=q("system_manifest")
if
type(f)=="table"then local g={}for i,h in ipairs(f)do
if type(h)=="table"and h.critical and
type(h.path)==p then g[#g+1]=h.path end end;if#g>0 then
return g,"system_manifest.lua"end end;return y,"built-in fallback"end;function n.storePathFor(a)return n.STORE..a end
local function v(a,b,c)local g,e=a.fs,a.crypto
if not(g and e and
e.hash)then return nil,"crypto unavailable"end;local d,h=g.readFile(b)
if type(d)~=p then return nil,h or"unreadable"end;local i=#d;local j,f=pcall(e.hash,d)if not c then d=nil;u()end
if
not j or type(f)~=p then return nil,"hash failed: "..tostring(f)end;return f,i,d end;local function w(a,b)return v(a,b)end;n.hashFile=w
local function x(a,b,c)if a.writeFileAtomic then
return a.writeFileAtomic(b,c)end;return a.writeFile(b,c)end
function n.loadIndex(a)a=n.deps(a)local b,d=a.fs,a.serialize
if not(b and d and b.exists and
b.exists(n.INDEX))then return nil end;local e=b.readFile(n.INDEX)if type(e)~=p then return nil end;local c=d.decode(e,{maxBytes=256*
1024})if type(c)~="table"or
type(c.files)~="table"then return nil end
return c end
local function z(a,b)local c,d=a.fs,a.serialize
if not(c and d)then return false,"fs/serialize unavailable"end
if
c.makeDirectory and not(c.exists and c.exists(n.DIR))then pcall(c.makeDirectory,n.DIR)end;return d.saveFile(c,n.INDEX,b)end
function n.baseline(a,b)a=n.deps(a)b=b or{}local d=a.fs
if not d then return false,"no filesystem"end;if not(a.crypto and a.crypto.hash)then
return false,"crypto unavailable"end;local g,e=b.paths,"caller"if not g then
g,e=n.criticalPaths(a)end
local f={version=n.VERSION,created=(os.time and os.time())or 0,boot=(
_G._TOS and _G._TOS.bootCount)or 0,content=
b.content and true or false,source=e,files={}}local c={hashed=0,stored=0,skipped=0,bytes=0,missing={},pruned=0,source=e}
local h=n.loadIndex(a)
for l,k in ipairs(g)do r()
if not(d.exists and d.exists(k))then c.missing[#
c.missing+1]=k else
local B,m,A=v(a,k,b.content and true or false)
if not B then c.skipped=c.skipped+1 else local C={hash=B,size=m,stored=false}
c.hashed=c.hashed+1
if b.content then
if m>n.MAX_STORE_BYTES then c.skipped=c.skipped+1 elseif A and
x(d,n.storePathFor(k),A)then C.stored=true;c.stored=c.stored+1;c.bytes=c.bytes+m else c.skipped=
c.skipped+1 end end;A=nil;u()f.files[k]=C end end end
if h and type(h.files)=="table"and d.remove then
for k,l in
pairs(h.files)do
if l.stored and
not(f.files[k]and f.files[k].stored)then local m=n.storePathFor(k)
if
d.exists and d.exists(m)and pcall(d.remove,m)then c.pruned=c.pruned+1 end end end end;local i,j=z(a,f)if not i then
return false,"could not write the index: "..tostring(j)end
if a.log and a.log.info then
a.log.info("srm",string.format("Baseline captured: %d hashed, %d stored (%d bytes), %d pruned, from %s",c.hashed,c.stored,c.bytes,c.pruned,e))end;return true,c end
function n.scan(a,b)a=n.deps(a)b=b or{}local c=s("baseline scan")
c.drift,c.missing,c.unbaselined={},{},{}local f=a.fs;if not f then
o(c,"no filesystem — nothing to scan","err")return c end;local d=n.loadIndex(a)if not d then
o(c,"no baseline captured yet — run 'srm baseline' on a system you trust","warn")return c end;local e={}for h in
pairs(d.files)do e[#e+1]=h end;table.sort(e)
o(c,string.format("baseline: %d file(s), captured from %s%s",
#e,tostring(d.source or"?"),d.content and", with stored copies"or", hashes only"),"info")
for i,h in ipairs(e)do r()local j=d.files[h]
if
not(f.exists and f.exists(h))then c.missing[#c.missing+1]=h
o(c,"MISSING  "..h,"err")else local k,l=w(a,h)
if not k then
o(c,"UNREADABLE  "..h.."  ("..
tostring(l or"no reason given")..")","err")c.drift[#c.drift+1]=h elseif k~=j.hash then
c.drift[#c.drift+1]=h
o(c,"CHANGED  "..h..
"  (baseline "..tostring(j.hash):sub(1,12)..", now "..
k:sub(1,12)..")","err")end end end
if d.content and b.checkStore~=false then local h=0
for j,i in ipairs(e)do r()local k=d.files[i]
if
k.stored then local l=n.storePathFor(i)
if
not(f.exists and f.exists(l))then h=h+1;o(c,"store copy gone: "..i,"warn")else
local m=w(a,l)if m~=k.hash then h=h+1
o(c,"store copy is corrupt: "..i,"warn")end end end end
if h==0 then o(c,"store: every copy verifies","ok")end end;local g=n.criticalPaths(a)
for i,h in ipairs(g)do r()if not d.files[h]then c.unbaselined[
#c.unbaselined+1]=h
o(c,"not in baseline: "..
h.." (re-run 'srm baseline')","warn")end end
if#c.missing==0 and#c.drift==0 then
o(c,"all baselined files match","ok")else o(c,"","info")
o(c,"Changed files mean one of two things: damage, or an upgrade you","info")
o(c,"meant to install. After a deliberate upgrade, re-run","info")
o(c,"'srm baseline' to bless the new files. Otherwise 'srm repair","info")o(c,"--restore' puts them back.","info")end;return c end
function n.restore(a,b)a=n.deps(a)b=b or{}local c=s("restore")local f=a.fs;if not f then
o(c,"no filesystem","err")return c end;local d=n.loadIndex(a)local e=b.paths
if not e then
local g=n.scan(a,{checkStore=false})e={}for i,h in ipairs(g.missing)do e[#e+1]=h end;for i,h in ipairs(g.drift)do
e[#e+1]=h end end;if#e==0 then
o(c,"nothing to restore — no missing or changed files","ok")return c end
if
not d and not b.unverified then
o(c,"no baseline to verify a restore against.","err")
o(c,"  capture one first ('srm baseline'), or accept an unchecked","info")o(c,"  copy explicitly with --unverified.","info")
return c end
for h,g in ipairs(e)do r()
local j=d and d.files[g]and d.files[g].hash or nil;local i={}if d and d.files[g]and d.files[g].stored then
i[#i+1]={src=n.storePathFor(g),what="store"}end;if b.source then
i[#i+1]={src=b.source..g,what=b.source}end
if#i==0 then
o(c,"no source for "..
g.. (
d and" (baseline is hashes-only — pass --source <mount>)"or""),"err")else local k=false
for h,l in ipairs(i)do
if not k and f.exists and f.exists(l.src)then
local A,h,m=v(a,l.src,true)
if j and A~=j then
o(c,"rejected "..l.what..
" copy of "..g.." — hash does not match the baseline","warn")elseif not j and not b.unverified then
o(c,"skipped "..
g.." — no baseline hash to check against","warn")k=true elseif not m then
o(c,"unreadable source for "..g.." at "..l.what,"warn")else local B,C=x(f,g,m)
if B then c.fixed=c.fixed+1
o(c,"restored "..g..
" from "..l.what.. (j and" (hash verified)"or
" (UNVERIFIED)"),
j and"ok"or"warn")else
o(c,"write failed for "..g..": "..tostring(C),"err")end;k=true end;m=nil;u()end end
if not k then o(c,"no usable source for "..g,"err")end end end;if a.log and a.log.warn and c.fixed>0 then
a.log.warn("srm","Restored "..c.fixed..
" system file(s) from a verified source")end;return c end
function n.storeUsage(a)a=n.deps(a)local d=n.loadIndex(a)local b={files=0,bytes=0}
if not d then return b end;local c=a.fs
for f,e in pairs(d.files)do
if e.stored then b.files=b.files+1;local g=e.size or 0
if
c and c.size then local i,h=pcall(c.size,n.storePathFor(f))if i and
type(h)=="number"then g=h end end;b.bytes=b.bytes+g end end;return b end
function n.repair(a,b)a=n.deps(a)b=b or{}local c=s("repair")
local d=q("kernel.repair")
if d and d.run then
local f,e=pcall(d.run,{fs=a.fs,serialize=a.serialize,log=a.log})
if f and type(e)=="table"then for h,g in ipairs(e.lines or{})do
o(c,g,
g:sub(1,5)=="WARN:"and"warn"or"info")end
c.fixed=c.fixed+ (e.fixed or 0)else
o(c,"fixer pass failed: "..tostring(e),"err")end else
o(c,"kernel.repair unavailable — skipping the fixer pass","warn")end
if b.restore then
local e=n.restore(a,{source=b.source,unverified=b.unverified})for h,g in ipairs(e.findings)do o(c,g.text,g.sev)end;c.fixed=
c.fixed+ (e.fixed or 0)end;return c end
function n.parseArgs(a)local c,b,d=nil,{},{}local e=nil
for f=1,# (a or{})do local g=tostring(a[f])
if f==e then elseif
g:sub(1,2)=="--"then local h,i=g:match("^%-%-([%w%-]+)=?(.*)$")
if h then
if i~=""then b[h]=i elseif h==
"source"then local j=a[f+1]
if
j and tostring(j):sub(1,2)~="--"then b.source=tostring(j)e=f+1 else b[h]=true end else b[h]=true end end elseif not c then c=g:lower()else d[#d+1]=g end end;return c or"status",b,d end
function n.status(a,b)a=n.deps(a)b=b or{}local c=s("status")local g=_G._TOS or{}
local f=n.readFault(a)local d=
not f and type(g.postFault)=="table"and g.postFault or nil
if f then
o(c,
"LAST BOOT FAILED POST — SRM "..f.code,"err")o(c,"  "..f.why,"err")
if b.clearFault then local h=n.clearFault(a)
o(c,h and
"  (fault code cleared)"or"  (could not clear the fault code)",
h and"info"or"warn")else
o(c,"  clears automatically on the next successful boot","info")end elseif d and d.code then
o(c,"THE BOOT BEFORE THIS ONE FAILED POST — SRM "..tostring(d.code).. (
d.err and(" / "..d.err)or""),"warn")
o(c,"  "..tostring(d.why or"?"),"warn")
o(c,"  this boot reported it and cleared it from the EEPROM","info")else o(c,"POST: no parked fault from SRM Basic","ok")end;if g.unsafeShutdown then
o(c,"last shutdown was UNSAFE (power loss / forced off)","warn")end;local e=n.loadIndex(a)
if not e then
o(c,"no baseline — 'srm baseline' records what a good system looks like","warn")else local h=0;for i in pairs(e.files)do h=h+1 end
o(c,string.format("baseline: %d file(s) from %s (boot #%s)",h,tostring(
e.source or"?"),tostring(e.boot or"?")),"info")
if e.content then local i=n.storeUsage(a)
o(c,string.format("store: %d copies, %.1f KB — local repair available",i.files,
i.bytes/1024),"ok")else
o(c,"store: hashes only — repair needs --source <mount>","info")end end;return c end;return n