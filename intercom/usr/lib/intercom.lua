local r,y="intercom","string"local n={}n._VERSION="1.0.1"local function p(a)local b,c=pcall(require,a)if
b then return c end end;local x=p("component")
local q=p("computer")local o=p("kernel.net")local s=p("kernel.fs")
local v=p("kernel.serialize")local u=p("kernel.event")local t=p("kernel.log")or{}
for b,a in
ipairs({"info","warn","error"})do if type(t[a])~="function"then t[a]=function()end end end;n.SVC=r;n.CUES_PATH="/etc/intercom.cues"n.CFG_PATH="/etc/intercom.cfg"
n.SPOOL_PATH="/var/intercom/log.dat"n.MAX_TEXT=240;n.MAX_CUES=64;n.MAX_SPOOL=100
n.SEVERITIES={"info","notice","warn","alert","critical"}n.RANK={}for a,b in ipairs(n.SEVERITIES)do n.RANK[b]=a end
n.DEFAULT_CFG={popupLevel="alert",popupCooldown=60,minLevel="info",echoToTape=false}
function n.validSeverity(a)return n.RANK[a or""]~=nil end;function n.rank(a)return n.RANK[a or""]or 0 end;function n.atLeast(a,b)return
n.rank(a)>=n.rank(b)end
function n.parseCueLine(a)if
type(a)~=y then return nil,"not a string"end
local d=a:match("^%s*(.-)%s*$")if d==""or d:sub(1,1)=="#"then return nil end
local g,b,i,e,c,h=d:match('^(%S+)%s+%[(%d+)%]%s*(["\'])(.-)%3%s*%[(%d+)%]%s*(.*)$')
if not g then return nil,"expected:  <name> [start] \"text\" [end] [severity]"end;b,c=tonumber(b),tonumber(c)if c<=b then
return nil,"end position must be after the start position"end;if#e==0 then
return nil,"the announcement text is empty"end
if#e>n.MAX_TEXT then return nil,"text is longer than "..
n.MAX_TEXT.." characters"end
local f=(h:match("^(%S+)")or"info"):lower()
if not n.validSeverity(f)then return nil,
"unknown severity '"..f.."' (use: "..
table.concat(n.SEVERITIES," ")..")"end;return{name=g:lower(),start=b,stop=c,text=e,severity=f}end
function n.formatCueLine(a)
local b=a.text:find('"',1,true)and"'"or'"'return
string.format('%-16s [%04d] %s%s%s [%04d]  %s',a.name,a.start,b,a.text,b,a.stop,a.severity)end
function n.parseCatalog(a)local d,b,e={},{},{}local c=0
for f in
tostring(a or""):gmatch("([^\n]*)\n?")do c=c+1;if c>4096 then break end;local g,h=n.parseCueLine(f)
if g then
if e[g.name]then
b[#b+1]={line=c,why=
"duplicate cue name '"..g.name.."' (the earlier one wins)"}elseif#d>=n.MAX_CUES then
b[#b+1]={line=c,why="more than "..n.MAX_CUES.." cues; ignored"}else e[g.name]=true;d[#d+1]=g end elseif h then b[#b+1]={line=c,why=h}end end;return d,b end
function n.formatCatalog(a)
local b={"# TOS Intercom announcement catalog","#","#   <name>  [start] \"what the recording says\" [end]  <severity>","#","# Positions are tape byte offsets. Severity is one of:",
"#   "..table.concat(n.SEVERITIES,"  "),"# Check a cue with:  intercom test <name>   (plays it, sends nothing)",""}
for e,d in ipairs(a or{})do b[#b+1]=n.formatCueLine(d)end;return table.concat(b,"\n").."\n"end
function n.findCue(b,a)a=tostring(a or""):lower()for e,d in ipairs(b or{})do if
d.name==a then return d end end end
function n.loadCatalog(a)a=a or s;if not
(a and a.exists and a.exists(n.CUES_PATH))then return{},{}end
local b=a.readFile(n.CUES_PATH)if type(b)~=y then return{},{}end;return n.parseCatalog(b)end
function n.saveCatalog(b,a)a=a or s;if not a then return false,"no filesystem"end
local c=n.formatCatalog(b)
if a.writeFileAtomic then return a.writeFileAtomic(n.CUES_PATH,c)end;return a.writeFile(n.CUES_PATH,c)end
function n.normalizeCfg(a)local b={}for c,d in pairs(n.DEFAULT_CFG)do b[c]=d end
if
type(a)=="table"then
if n.validSeverity(a.popupLevel)then b.popupLevel=a.popupLevel end
if n.validSeverity(a.minLevel)then b.minLevel=a.minLevel end;if
type(a.popupCooldown)=="number"and a.popupCooldown>=0 and a.popupCooldown<=3600 then
b.popupCooldown=math.floor(a.popupCooldown)end
if
type(a.echoToTape)=="boolean"then b.echoToTape=a.echoToTape end end;return b end
function n.loadCfg(a,b)a,b=a or s,b or v
if not
(a and b and a.exists and a.exists(n.CFG_PATH))then return n.normalizeCfg(nil)end;local c=a.readFile(n.CFG_PATH)if type(c)~=y then
return n.normalizeCfg(nil)end
local d,e=pcall(b.decode,c,{maxBytes=8*1024})return n.normalizeCfg(d and e or nil)end
function n.saveCfg(c,a,b)a,b=a or s,b or v
if not(a and b)then return false,"fs/serialize unavailable"end;return b.saveFile(a,n.CFG_PATH,n.normalizeCfg(c))end
function n.findDrive(a)
if not(x and x.list)then return nil,"no component API"end
for b in x.list("tape_drive")do if not a or b:sub(1,#a)==a then
local c,d=pcall(x.proxy,b)if c then return d end end end;return nil,
a and("no tape drive matching "..a)or"no tape drive attached"end
function n.seekTo(a,b)if not(a and a.seek and a.getSize)then
return false,"no drive"end;if a.stop then pcall(a.stop)end;local c=
a.getSize()or 0
if b<0 or b>c then return false,
string.format("position %d is off the tape (size %d)",b,c)end;a.seek(-c)if b>0 then a.seek(b)end;return true end;n.BYTES_PER_SECOND=4096
function n.playCue(a,c,b)b=b or{}
if not a then return false,"no tape drive"end
if a.isReady and not a.isReady()then return false,"no tape in the drive"end;local i,j=n.seekTo(a,c.start)if not i then return false,j end;if
a.setVolume and b.volume then pcall(a.setVolume,b.volume)end
if
a.setSpeed and b.speed then pcall(a.setSpeed,b.speed)end;local k=pcall(a.play)
if not k then return false,"the drive refused to play"end;local l=b.bytesPerSecond or n.BYTES_PER_SECOND;local d=
(c.stop-c.start)/l;local function e()pcall(a.stop)
if b.onDone then pcall(b.onDone)end end;local f=b.interval or
(not b.timer and u and u.interval)local g=b.cancelTimer or
(u and u.cancelTimer)
local h=b.timer or(u and u.timer)
if f and a.getPosition then
local A=b.clock or(q and q.uptime)or function()return 0 end
local C=A()+ (c.stop-c.start)/1024+2;local m,B=nil,false
m=f(0.05,function()if B then return end;local F,D=pcall(a.getPosition)local E=false
if
a.getState then local G,H=pcall(a.getState)E=G and H~="PLAYING"end;if
(F and type(D)=="number"and D>=c.stop)or E or A()>=C then B=true;if g and m then
pcall(g,m)end;e()end end,r)elseif h then h(d,e,r)end;return true,d end
function n.spoolAppend(a,b)a=type(a)=="table"and a or{}
a[#a+1]=b;while#a>n.MAX_SPOOL do table.remove(a,1)end;return a end
function n.loadSpool(a,b)a,b=a or s,b or v;if not
(a and b and a.exists and a.exists(n.SPOOL_PATH))then return{}end
local c=a.readFile(n.SPOOL_PATH)if type(c)~=y then return{}end
local e,d=pcall(b.decode,c,{maxBytes=128*1024})if e and type(d)=="table"then return d end;return{}end
function n.saveSpool(c,a,b)a,b=a or s,b or v
if not(a and b)then return false,"fs/serialize unavailable"end
if
a.makeDirectory and a.exists and not a.exists("/var/intercom")then pcall(a.makeDirectory,"/var/intercom")end;return b.saveFile(a,n.SPOOL_PATH,c)end
function n.since(a,b,c)a=tonumber(a)or 0;local d,e={},a
for g,f in ipairs(n.loadSpool(b,c))do local h=
tonumber(f.rxSeq)or 0;if h>a then d[#d+1]=f end;if h>e then e=h end end;return d,e end;function n.highWater(a,b)local d,c=n.since(0,a,b)return c end
function n.receivePlan(a,b,c,d)
a=n.normalizeCfg(a)
local e=(type(b)=="table"and b.severity)or"info"if not n.atLeast(e,a.minLevel)then
return{accept=false,popup=false,why="below minLevel"}end;if
not n.atLeast(e,a.popupLevel)then
return{accept=true,popup=false,why="logged (below popupLevel)"}end;local f=(d or 0)-
(c or-math.huge)
if c and f<a.popupCooldown then return
{accept=true,popup=false,why=string.format("popup on cooldown (%ds left)",math.ceil(
a.popupCooldown-f))}end;return{accept=true,popup=true,why="interrupting"}end
function n.formatLine(a)
local b=(type(a)=="table"and a.severity)or"info"
local c=(type(a)=="table"and a.from)or"?"
local d=(type(a)=="table"and a.text)or""return string.format("[%s] %s: %s",b:upper(),c,d)end
function n.newAnnouncement(a)
local b=tostring(a.text or""):sub(1,n.MAX_TEXT)
return
{text=b,severity=n.validSeverity(a.severity)and a.severity or"info",from=
a.from or"?",cue=a.cue,at=
a.at or(q and q.uptime and q.uptime())or 0}end
function n.announce(a)a=a or{}local b={played=false,sent=false,errors={}}local function d(k)
b.errors[#b.errors+1]=k end;local c=a.cue
local e=a.text or(c and c.text)if not e or e==""then d("nothing to say")return b end
local f=
a.severity or(c and c.severity)or"info"
if c then local k=a.drive
if k==nil then k=n.findDrive(a.driveAddr)end
if not k then d("no tape drive — announcing by text only")else
local m,l=n.playCue(k,c,a)
if m then b.played=true;b.seconds=l else d("tape: "..tostring(l))end end end;if a.localOnly then b.localOnly=true;return b end;if not(o and o.meshAvailable and
o.meshAvailable())then
d("no mesh network — nobody was told")return b end
local g=n.newAnnouncement({text=e,severity=f,cue=
c and c.name or nil,from=(o.getHostname and o.getHostname())or"?"})local h=a.to or"*"
local i,j=o.meshSend({svc=n.SVC,to=h,payload=g,allowPlaintext=(h=="*")or nil})
if i then b.sent=true;b.id=i;b.announcement=g
t.info(r,"Announced ("..f.."): "..e)else d("send failed: "..tostring(j))end;return b end;local w=false;local z=nil
function n.raise(b,a)a=a or p("kernel.notify")if not
(a and a.post)then return nil,"no notify facility"end;local c=tostring(
b.severity or"alert")
return
a.post({from=r,style=(c=="critical")and
"danger"or"warn",title="ANNOUNCEMENT \226\128\148 "..c:upper(),message=tostring(
b.text or"")..
(b.cue and
("\n\n(tape cue: "..tostring(b.cue)..")")or""),buttons={"Acknowledge"},ttl=120})end
function n.deliver(b,c,a)a=a or{}local f=a.fs or s;local g=a.serialize or v
local h=a.cfg or n.loadCfg(f,g)
c=c or(q and q.uptime and q.uptime())or 0;local d=n.receivePlan(h,b,a.lastPopupAt or z,c)if
not d.accept then return d end;local e=n.loadSpool(f,g)
b.rxSeq=(
tonumber(e[#e]and e[#e].rxSeq)or 0)+1;n.saveSpool(n.spoolAppend(e,b),f,g)
if d.popup then
local i,j=n.raise(b,a.notify)d.raised=i~=nil
if not i then d.why="popup refused: "..tostring(j)end;z=c;if a.setLastPopup then a.setLastPopup(c)end end;if h.echoToTape and b.cue then local j=n.loadCatalog(f)
local i=n.findCue(j,b.cue)
if i then pcall(n.playCue,n.findDrive(),i)end end;t.info(r,"Heard "..
n.formatLine(b))return d end
function n.start()if w then return true end
if not(o and o.meshOn)then
t.warn(r,"no mesh transport — the receiver cannot start")return false,"mesh unavailable"end
o.meshOn(n.SVC,function(a,b)if type(a)~="table"then return false end;local c=a.payload
if type(c)~=
"table"or type(c.text)~=y then return false end
c.from=c.from or
(a.from and tostring(a.from):sub(1,8))or
(b and b.from and tostring(b.from):sub(1,8))or"?"local e,d=pcall(n.deliver,c)
return e and d and d.accept or false end)w=true;t.info(r,"Announcement receiver listening")
return true end
function n.stop()if not w then return true end
if o and o.meshOff then o.meshOff(n.SVC)end;w=false;t.info(r,"Announcement receiver stopped")return true end;function n.running()return w end;function n._reset()z=nil end;return n