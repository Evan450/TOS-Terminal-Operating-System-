local m,i="/etc/critical.bak","string"local j={}
local k={"/etc/users.dat","/etc/trust.dat","/etc/tos.cfg","/etc/cron.db",m}local n={pwrstate=true}local l="/var/log"local o=32*1024;local p=16*1024
function j.run(a)
local b=a and a.fs;local d=a and a.serialize;local e={fixed=0,warned=0,lines={}}local function c(h)
e.lines[#e.lines+1]=h end;local function f(h)e.fixed=e.fixed+1;c(h)end;local function g(h)e.warned=
e.warned+1;c("WARN: "..h)end;if not b then
g("no filesystem module — nothing repairable")return e end
pcall(function()
if b.recoverAtomic then
local h=b.recoverAtomic(k)
if h and h>0 then
f("finished "..h.." interrupted critical write(s)")else c("atomic writes: clean")end end end)
pcall(function()local h=0
for r,q in
ipairs({"/etc","/var","/var/lib","/var/pkg","/home"})do local t,s=pcall(b.list,q)
if t and type(s)=="table"then
for r,u in ipairs(s)do
local v=u:gsub("/$","")if v:sub(-8)==".tos-tmp"then
if pcall(b.remove,q.."/"..v)then h=h+1 end end end end end;if h>0 then
f("removed "..h.." orphaned temp file(s)")else c("temp files: clean")end end)
pcall(function()local t,h=pcall(require,"kernel.bootcfg")
if not(t and h)then return end;local q=h.PATH or"/etc/boot.cfg"if not b.exists(q)then
c("boot.cfg: absent (defaults)")return end;local r=b.readFile(q)local s=nil
if
d and d.decode and type(r)==i then s=d.decode(r,{maxBytes=8192})end
if type(s)=="table"then c("boot.cfg: OK")else local u=h.load(b)if h.save(b,u)then
f("rewrote corrupt /etc/boot.cfg (normalized)")else
g("/etc/boot.cfg is corrupt and could not be rewritten")end end end)
pcall(function()if not(d and d.decode)then return end
for q,h in ipairs(k)do
if
h~="/etc/boot.cfg"and b.exists(h)then local r=b.readFile(h)
local s=type(r)==i and
d.decode(r,{maxBytes=512*1024})or nil;if type(s)~="table"then
g(h.." does not parse — inspect/restore it manually")end end end;c("critical state: checked")end)
pcall(function()local h=0;local r,q=pcall(b.list,"/var/run")
if
r and type(q)=="table"then
for t,s in ipairs(q)do local u=s:gsub("/$","")if not n[u]then if
pcall(b.remove,"/var/run/"..u)then h=h+1 end end end end
if h>0 then
f("cleared "..h.." stale runtime file(s) from /var/run")else c("/var/run: clean")end end)
pcall(function()local h=0;local r,q=pcall(b.list,l)
if r and type(q)=="table"then
for t,s in ipairs(q)do
local w=s:gsub("/$","")local u=l.."/"..w;local x,v=pcall(b.size,u)
if
x and type(v)=="number"and v>o then local y=b.readFile(u)
if type(y)==i then local z=y:sub(-p)
local A=z:find("\n",1,true)if A then z=z:sub(A+1)end
local B=b.writeFileAtomic or b.writeFile
if B(u,"[trimmed by self-repair]\n"..z)then h=h+1 end end end end end
if h>0 then
f("trimmed "..h.." oversized log(s)")else c("logs: within limits")end end)
pcall(function()if not(d and d.decode)then return end;if not b.exists(m)then
c("critical.bak: absent (resyncs at boot)")return end;local q=b.readFile(m)
local r=
type(q)==i and d.decode(q,{maxBytes=64*1024})or nil;if type(r)~="table"then return end;local h=0
for t,s in ipairs(r)do if type(s)==i and
not b.exists(s)then h=h+1
g("missing critical file: "..s)end end;if h==0 then c("critical files: all present")end end)return e end;return j