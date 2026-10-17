local r="function"local j={}j.MARKER="/etc/selftest.on"
j.RESULTS="/var/selftest.log"j.DIRS={"/usr/lib/selftest"}local l,n,m
function j.init(a)a=a or{}l=a.fs or nil;n=
a.computer or nil
m=a.log or{info=function()end,warn=function()end,error=function()end}return true end
local function o(a)local b,c={},{}
local function d(e)if e and e~=""and e~="/"and not c[e]then c[e]=true
b[#b+1]=e end end;if a and a.mounts then local f,e=pcall(a.mounts)
if f and type(e)=="table"then for h,g in
ipairs(e)do d(g.mountPoint)end end end
if
a and a.exists and a.list and a.exists("/mnt")then for f,e in
ipairs(a.list("/mnt")or{})do local g=tostring(e):gsub("/$","")if g~=""then
d("/mnt/"..g)end end end;return b end
function j.markerPaths(a)a=a or l;local b={j.MARKER}
for d,c in ipairs(o(a))do
b[#b+1]=c.."/selftest.on"b[#b+1]=c.."/selftest/selftest.on"end;return b end
function j.diskMarkers(a)a=a or l;local b={}if not(a and a.exists)then return b end
for d,c in
ipairs(j.markerPaths(a))do if c~=j.MARKER and a.exists(c)then b[#b+1]=c end end;return b end
function j.enabled(a)a=a or l;if not(a and a.exists)then return false end;return
a.exists(j.MARKER)and true or false end
function j.activeMarker(a)return j.enabled(a)and j.MARKER or nil end
function j.readMarker(a)a=a or l;local b={shutdown=false,only=nil,screen=false}if not
(a and a.exists)then return b end;local c={}
for e,d in ipairs(j.markerPaths(a))do
if
a.exists(d)then local g=a.readFile and a.readFile(d)or""local f={}
for h in tostring(
g or""):gmatch("[^\r\n]+")do
local i,s=h:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
if i=="shutdown"or i=="screen"then
f[i]=(s=="true"or s=="1")elseif i=="only"and s~=""then f[i]=s end end
for h,i in pairs(f)do if not c[h]then b[h]=i;c[h]=true end end end end;return b end
function j.discover(a)a=a or l;local c={}if
not(a and a.exists and a.list)then return c end;local b={}
for f,e in ipairs(j.DIRS)do b[#b+1]=e end
for e,d in ipairs(o(a))do if
not a.exists(d.."/selftest/package.lua")then b[#b+1]=d.."/selftest"end;if a.exists(d..
"/selftest.on")then b[#b+1]=d end end
for e,d in ipairs(b)do if a.exists(d)then
for e,f in ipairs(a.list(d)or{})do
local g=tostring(f):gsub("/$","")if g:match("%.lua$")then c[#c+1]=d.."/"..g end end end end;table.sort(c)return c end
local function p(a)local b={}b.cfg=a.cfg or{}
function b.ok(d,c)a.n=a.n+1
if c then a.pass=a.pass+1 else
a.fail=a.fail+1;a.failures[#a.failures+1]=d end;return c and true or false end
function b.eq(c,d,e)local f=(d==e)if not f then
c=c.." (expected "..
tostring(d)..", got "..tostring(e)..")"end;return b.ok(c,f)end
function b.skip(c,d)a.n=a.n+1;a.skip=a.skip+1;a.skips[#a.skips+1]=c.." :: "..
tostring(d or"n/a")return true end
function b.note(c)a.notes[#a.notes+1]=tostring(c)return true end;return b end
local function q(a)local b={}for e,f in pairs(package.loaded)do b[e]=f end;local c,d=pcall(a)
for e in
pairs(package.loaded)do if b[e]==nil then package.loaded[e]=nil end end;for e,f in pairs(b)do package.loaded[e]=f end;return c,d end
local function k(a,b)if not a then return end
if a.appendFile then
pcall(a.appendFile,j.RESULTS,b.."\n")elseif a.writeFile then
local c=(a.readFile and a.readFile(j.RESULTS))or""pcall(a.writeFile,j.RESULTS,c..b.."\n")end end
function j.run(a)a=a or{}local c=a.fs or l;local d=a.computer or n
local e=a.cfg or j.readMarker(c)local g=a.files or j.discover(c)
local b={n=0,pass=0,fail=0,skip=0,failures={},skips={},notes={},cfg=e}local h=p(b)local i=d and d.uptime()or 0;if c and c.writeFile then
pcall(c.writeFile,j.RESULTS,"")end;local f=rawget(_G,"_TOS")or{}
k(c,string.format("SELFTEST BEGIN at=%.1f files=%d version=%s build=%s variant=%s",i,
#g,tostring(f.version or"?"),tostring(f.build or"?"),tostring(f.variant or"?")))if d and d.freeMemory then
k(c,string.format("ENV mem_free=%dK",math.floor(d.freeMemory()/1024)))end
for u,t in ipairs(g)do local v=
t:match("([^/]+)%.lua$")or t
if
e.only and v:sub(1,#e.only)~=e.only then k(c,"SKIPFILE "..v)else k(c,"RUN  "..v)
local w={b.pass,b.fail,b.skip}local x=c and c.readFile and c.readFile(t)local y,z;if type(x)~=
"string"or x==""then z="unreadable or empty"else
y,z=load(x,"="..t,"t")end
if not y then b.fail=b.fail+1
k(c,"FAIL "..v..
" :: could not load: "..tostring(z))else
local A,B=q(function()local C=y()
if type(C)==r then C(h)elseif
type(C)=="table"and type(C.run)==r then C.run(h)else
error("check file returned neither a function nor { run = f }",0)end end)
if not A then b.fail=b.fail+1
k(c,"FAIL "..v.." :: "..tostring(B))else local D=b.pass-w[1]local C=b.fail-w[2]local E=b.skip-w[3]
k(c,string.format("%s %s  pass=%d fail=%d skip=%d",
C>0 and"FAIL"or"PASS",v,D,C,E))end end end end;for u,t in ipairs(b.failures)do k(c,"  - "..t)end;for u,t in
ipairs(b.skips)do k(c,"  ~ "..t)end;for u,t in ipairs(b.notes)do
k(c,"  i "..t)end
local s=(d and d.uptime()or 0)-i
k(c,string.format("SELFTEST END pass=%d fail=%d skip=%d checks=%d secs=%.1f",b.pass,b.fail,b.skip,b.n,s))if m and m.info then
m.info("selftest",string.format("battery: %d passed, %d failed, %d skipped",b.pass,b.fail,b.skip))end
if e.shutdown and d and
d.shutdown then k(c,"SHUTDOWN requested by marker")
local t=_G._TOS and
_G._TOS.kernel and _G._TOS.kernel.shutdown
if type(t)==r then pcall(t,false)else pcall(d.shutdown,false)end end;return b end;j._internal={makeT=p,withIsolatedModules=q}return j