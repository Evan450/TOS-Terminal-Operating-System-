local D,E,F="[^\r\n]+","passed","stalled"local v="/etc/selftest.on"
local w="/var/selftest.log"local G={"/usr/lib/selftest"}
local u,z,x,s,y,H=0xFF5555,0xFFFF55,0x55FF55,0xAAAAAA,0xFFFFFF,0x55FFFF;local t={}
function t.parseMarker(a)local b={}
for c in tostring(a or""):gmatch(D)do
local d,e=c:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
if d=="shutdown"or d=="screen"then
b[d]=(e=="true"or e=="1")elseif d=="only"and e~=""then b[d]=e end end;return b end
function t.markerBody(a,b)
local c={"# armed by `selftest arm`".. (b and(" ("..b..")")or"")}if a.shutdown then c[#c+1]="shutdown=true"end;if a.screen then
c[#c+1]="screen=true"end
if a.only then c[#c+1]="only="..a.only end;return table.concat(c,"\n").."\n"end
local function I(a)local b,c={},{}
local function d(e)if e and e~=""and e~="/"and not c[e]then c[e]=true
b[#b+1]=e end end
if a.mounts then local f,e=pcall(a.mounts)if f and type(e)=="table"then for h,g in ipairs(e)do
d(g.mountPoint)end end end;if a.exists("/mnt")then
for f,e in ipairs(a.list("/mnt")or{})do
local g=tostring(e):gsub("/$","")if g~=""then d("/mnt/"..g)end end end;return b end
function t.discover(a)local b={}
for f,e in ipairs(G)do b[#b+1]={dir=e,source="installed"}end
for e,d in ipairs(I(a))do
if
not a.exists(d.."/selftest/package.lua")then b[#b+1]={dir=d.."/selftest",source="disk "..d}end;if a.exists(d.."/selftest.on")then
b[#b+1]={dir=d,source="disk "..d}end end;local c={}
for e,d in ipairs(b)do
if a.exists(d.dir)then
for e,f in ipairs(a.list(d.dir)or{})do
local g=tostring(f):gsub("/$","")if g:match("%.lua$")then
c[#c+1]={path=d.dir.."/"..g,name=g,source=d.source}end end end end
table.sort(c,function(d,e)return d.path<e.path end)return c end
function t.summarise(a)local b={fails={},skips={},notes={}}
for c in
tostring(a or""):gmatch(D)do
if c:match("^SELFTEST BEGIN")then b.begin=c elseif c:match("^SELFTEST END")then b.finish=c elseif
c:match("^RUN%s")then b.lastRun=c:match("^RUN%s+(.-)%s*$")elseif c:match("^FAIL%s")or
c:match("^  %- ")then b.fails[#b.fails+1]=c elseif c:match("^  ~ ")then b.skips[
#b.skips+1]=c elseif c:match("^  i ")then
b.notes[#b.notes+1]=c end end;if not b.begin then b.state="none"elseif b.finish then
b.state=(#b.fails>0)and"failed"or E else b.state=F end;return b end
local B=[[
-- What this checks, and why only a real machine can answer it.
--
-- A check is a file that returns one function. The battery calls it with
-- `t` and records whatever it reports:
--   t.ok(name, cond)            pass when cond is true
--   t.eq(name, expected, got)   the same, naming both values on a failure
--   t.skip(name, why)           cannot run here (no card, no printer):
--                               a skip is never a failure
--   t.note(text)                an observation, kept in the log, no verdict
--   t.cfg.screen                true when the round allows drawing on
--                               the boot console -- ask before you draw
-- It runs INSIDE the kernel, at boot, before the shell: `computer`,
-- `component` and require("kernel.*") are all there. package.loaded is
-- restored after each check, so stub what you like; anything else you
-- change on the machine, put back.
return function(t)
  t.ok("the machine has memory to spare", computer.freeMemory() > 0)
end
]]
local function C(a)a("selftest -- the boot self-test battery",H)
a("  selftest [status]            armed?  what will run?  how did the last run go?",s)
a("  selftest arm [shutdown] [screen] [only=<prefix>]   run it at the next boot (root)",s)
a("  selftest disarm              stop running it at boot (root)",s)
a("  selftest list                every check an armed boot would run, and where from",s)
a("  selftest log [all]           the last run: failures, skips, notes (all: every line)",s)
a("  selftest template [file]     a starting point for a check of your own",s)end
local function A(a,b)if not a.exists(b)then return nil end
local c,d=pcall(a.readFile,b)return c and d or nil end
local function J(b,a)local d=A(b,v)
if b.exists(v)then local g=t.parseMarker(d)local f={}if g.shutdown then
f[#f+1]="powers off after"end
if g.screen then f[#f+1]="screen checks on"end;if g.only then f[#f+1]="only "..g.only.."*"end
a(
"ARMED: the battery runs at the next boot".. (
#f>0 and(" ("..table.concat(f,", ")..")")or""),z)else
a("Not armed: boots run normally.  (selftest arm, as root)",s)end;local e=t.discover(b)
a(string.format("%d check(s) found.  (selftest list)",#e),y)local c=t.summarise(A(b,w))
if c.state=="none"then
a("No run recorded in "..w..".",s)else if c.begin then
a("Last run: "..c.begin:gsub("^SELFTEST BEGIN%s*",""),s)end
if c.state==F then
a("STALLED in "..
tostring(c.lastRun or"?").." -- the run never finished.",u)else
a(c.finish:gsub("^SELFTEST END%s*","Result: "),c.state==E and x or u)end end end
function t.run(c,a,b)a=a or print;b=b or fs;if type(b)~="table"then
a("selftest needs the fs capability",u)return end;local d=c[1]or"status"
if d=="status"then
J(b,a)elseif d=="arm"then local e={}
for h=2,#c do local i=tostring(c[h])
if
i=="shutdown"or i=="--shutdown"then e.shutdown=true elseif i=="screen"or i=="--screen"then e.screen=true elseif
i:match("^%-?%-?only=")then e.only=i:gsub("^%-?%-?only=","")else
a("selftest arm: unknown option '"..
i.."' -- nothing was changed.",u)C(a)return end end;local f,g=b.writeFile(v,t.markerBody(e))
if not f then
a("Not armed: "..tostring(g or
"write refused"),u)
a("Arming runs code inside the kernel at the next boot, so only root may do it.",s)return end
a("Armed. The battery runs at the next boot and writes "..w..".",x)if e.shutdown then
a("The machine powers itself off when the run finishes.",z)end
a("Disarm with:  selftest disarm",s)elseif d=="disarm"then
if not b.exists(v)then a("Not armed.",s)return end;local e,f=b.remove(v)if not e then
a("Still armed: "..tostring(f or"remove refused"),u)return end
a("Disarmed. Boots run normally.",x)elseif d=="list"then local f=t.discover(b)
if#f==0 then
a("No checks found. Install them with `pkg install selftest`, or insert a test",s)a("disk carrying a selftest/ folder.",s)return end;local e=t.parseMarker(A(b,v)).only
for h,g in ipairs(f)do local i=e and
g.name:sub(1,#e)~=e
a(string.format("  %-24s %s%s",g.name,g.source,i and"  (not run: only="..e..
")"or""),
i and s or y)end elseif d=="log"then local f=A(b,w)if not f or f==""then
a("No run recorded in "..w..".",s)return end
if c[2]=="all"then for g in f:gmatch(D)do
a(g,(g:match("^FAIL")or
g:match("^  %- "))and u or
g:match("^  ~ ")and z or y)end;return end;local e=t.summarise(f)if e.begin then a(e.begin,s)end;for h,g in
ipairs(e.fails)do a(g,u)end;for h,g in ipairs(e.skips)do a(g,z)end;for h,g in
ipairs(e.notes)do a(g,y)end
if e.state==F then
a("STALLED in "..tostring(e.lastRun or"?")..
" -- no SELFTEST END line.",u)elseif e.finish then a(e.finish,e.state==E and x or u)end elseif d=="template"then
if c[2]then local e,f=b.writeFile(c[2],B)if not e then
a("Could not write "..c[2]..": "..
tostring(f),u)return end
a("Wrote "..c[2]..
". Put it in a test disk's selftest/ folder, or ship it in",x)
a("a package that installs it under /usr/lib/selftest/ (a root install).",s)else for e in B:gmatch("([^\n]*)\n")do a(e,y)end end else C(a)end end;t.TEMPLATE=B;return
{commands={selftest=function(a,b)return t.run(a or{},b)end},lib=t}