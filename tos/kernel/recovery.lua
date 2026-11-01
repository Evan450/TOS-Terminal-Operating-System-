local f={}
function f.fsOver(a)local b={}
function b.exists(c)local d,e=pcall(a.exists,c)return d and e==true end;function b.size(c)return a.size(c)end
function b.remove(c)return a.remove(c)end;function b.makeDirectory(c)return a.makeDirectory(c)end
function b.readFile(c)
local d,k=a.open(c,"r")if not d then return nil,k end;local e={}while true do local l=a.read(d,4096)if not l then break end;e[
#e+1]=l end;a.close(d)return
table.concat(e)end
function b.writeFile(c,d)local e=c:match("^(.*)/[^/]*$")if
e and e~=""and not b.exists(e)then pcall(a.makeDirectory,e)end
local k,l=a.open(c,"w")if not k then return false,l end;local m,n=a.write(k,d)a.close(k)if not m then
return false,n end;return true end
function b.writeFileAtomic(c,d)local e=c..".tos-tmp"local k,l=b.writeFile(e,d)if k and
a.size(e)~=#d then k,l=false,"short write"end
if not k then
pcall(a.remove,e)return false,l or"temp write failed"end
if b.exists(c)then pcall(a.remove,c)if b.exists(c)then pcall(a.remove,e)return false,
"cannot replace target"end end;if not a.rename(e,c)then return false,"rename failed"end
return true end;return b end
function f.items(a,b)local d={}local function c(e,k)d[#d+1]={label=e,action=k}end;if not a then
c("Carry on booting","continue")c("Safe Mode, this boot only","safe")
c("Boot Settings","settings")end
c("Check system files","check")
c("Restore changed files from the baseline","restore")if b then c("Boot another disk","disk")end
c("Reboot","reboot")c("Power off","off")return d end
local function g(a,c,b)local e=a.color;local k=math.max(1,(a.H or 16)-4)local d=1
repeat
a.clear()a.set(2,1,c,e("title"))for l=1,k do local m=b[d]if not m then break end
a.set(2,l+2,tostring(m.text):sub(1,(
a.W or 50)-2),e(m.role or"value"))d=d+1 end
a.set(2,
a.H or 16,b[d]and"Any key: more"or"Any key: back",e("dim"))a.readKey()until not b[d]end;local i={ok="ok",info="dim",warn="warn",err="warn"}
local function h(a,b)local function k(r)
g(a,"Recovery",{{text="The repair tools did not load:",role="warn"},{text=tostring(r),role="dim"}})end
local n,c=pcall(require,"kernel.srm")if not n or type(c)~="table"then return k(c)end
local o,d=pcall(require,"kernel.crypto")if not o or type(d)~="table"then return k(d)end;if d.init then
pcall(d.init)end;a.clear()
a.set(2,1,b and"Restoring..."or"Checking...",a.color("title"))
a.set(2,3,"Hashing every file in the baseline. This takes a while.",a.color("dim"))local l=0
c.beat=function()l=l+1
a.set(2,4,tostring(l).." files",a.color("value"))if a.tick then a.tick()end end;local p={fs=f.fsOver(a.px),crypto=d,component=a.component}
local q,m=pcall(
b and c.restore or c.scan,p,{checkStore=false})c.beat=nil;if not q then return k(m)end;local e={}
for s,r in ipairs(m.findings or{})do e[#e+1]={text=r.text,role=
i[r.sev]or"value"}end
if#e==0 then e[1]={text="Nothing to report.",role="ok"}end;g(a,b and"Restore"or"System files",e)
return m end
local function j(a)local b=a.color;a.clear()
a.set(2,1,"Restore changed files",b("title"))
a.set(2,3,"Files that differ from the baseline go back to the copies",b("value"))
a.set(2,4,"it verified. Anything you changed on purpose is lost.",b("value"))
a.set(2,6,"Y goes ahead. Any other key goes back.",b("warn"))local d,c=a.readKey()return c==89 or c==121 end
function f.run(a)local b=a.color
local c=f.items(a.failed,a.otherDisk~=nil)
while true do a.clear()a.set(2,1,"TOS Recovery",b("title"))
local d=2;if a.why then
a.set(2,d,tostring(a.why):sub(1,(a.W or 50)-2),b("warn"))d=d+1 end;d=d+1
for m,n in ipairs(c)do a.set(3,d,m..
"  "..n.label,b("value"))d=d+1 end;a.set(2,d+1,"Press a number.",b("dim"))
local l,k=a.readKey()local e=c[(tonumber(k)or 0)-48]
if e then
if
e.action=="check"then h(a,false)elseif e.action=="restore"then if j(a)then h(a,true)end elseif e.action=="disk"then
a.clear()a.otherDisk()else return e.action end end end end;return f