
local v,u,A,w,B,x,C,y,D,E,z,s="/bios.lua","/install.lua","Cancel","Drive ","No network available","No removable disks mounted","Status","^(.*)/[^/]+$","danger","kernel.pkg","status","string"local F=require("computer")local q=require("component")
local r=require("shell.panels.helpers")local t=function()end
do local b,a=pcall(require,"kernel.process")if b and a and
a.yieldCooperative then t=a.yieldCooperative end end
return
function(b,a,c)local h,G,o,e,m,M=a.K,a.E,a.P,a.F,a.D,a.U;local P,k,f=a.SC,a.NM,a.st;local d=a.T;local Q=a.tier
local I,R=a.W,a.H;local N=c.rp;local S=c.openViewTab;local T=c.openEditTab;local n=c.refreshBrowser
local U=c.canRead;local V=c.canWrite;local W=c.canAccess;local J=c.rootOnly;local K=c.dialog;local i=c.adminOnly
local X=c.makeProgramEnv;local g=r.fmtSz
local Y=function(H)return r.expandBuf(a,H)end;local j=c.promptInput;local l=c.confirm
local function p(Z,H)
local ab,aa=pcall(require,"shell.panels.diskprobe")if not ab or type(aa)~="table"then return nil end
local ac,_=pcall(aa.probe,Z)if not ac or type(_)~="table"then return nil end
if
_.kind=="tbfs"and H and H.stats then local ad,f=pcall(H.stats,Z)
if ad and
type(f)=="table"then
local ae=tostring(f.label or""):gsub("%c","?"):sub(1,24)return
('a TBFS volume labelled "%s": %d file(s), %d dir(s)'):format(ae,
tonumber(f.files)or 0,tonumber(f.dirs)or 0)end end;return _.text end
b.redstone=function(H,Z)local aa,_=pcall(require,"peripheral.redstone")if not aa then
Z("No redstone module",d.error)return end
if not H[1]then local ab=_.status()if not ab then
Z("No redstone component",d.error)return end
Z(" Side      In  Out",d.title)for ad,ac in ipairs(ab)do
Z(string.format(" %-9s %2d  %2d",ac.name,ac.input,ac.output),d.fg)end elseif
H[1]=="set"and H[2]and H[3]then
local ab,ac=_.setOutput(H[2],tonumber(H[3])or 15)
Z(ab and"Set "..H[2].." = "..H[3]or tostring(ac),
ab and d.highlight or d.error)elseif H[1]=="pulse"and H[2]then
_.pulse(H[2],tonumber(H[3])or 0.5)Z("Pulsed "..H[2],d.highlight)else
Z("Usage: redstone [set <side> <0-15>|pulse <side> [duration]]",d.dim)end end;b.rs=b.redstone
b["cluster-setup"]=function(Z,H)if not J(H)then return end
local ad,ab=pcall(require,"shell.clustersetup")if not ad or not ab then
H("cluster setup module unavailable",d.error)return end
local aa=_G._TOS and _G._TOS.fs
local function ac()local ah,ai=pcall(require,E)return ah and ai or nil end
local ae={ok=d.highlight,warn=d.warning,err=d.error,title=d.title}local _={}
_.say=function(ah,ai)H(ah or"",ae[ai or""]or d.fg)end
_.choose=function(aj,ah,ai)
if not K then _.say(aj,"title")for ap,ao in
ipairs(type(ah)=="table"and ah or{ah})do _.say(ao,nil)end
for ao,ap in ipairs(ai)do _.say("  "..ao..
". "..ap,nil)end
local an=tonumber(j and j("Choice: ",4)or"")return(an and ai[an])and an or#ai end;local ak=type(ah)=="table"and table.concat(ah,"\n")or
tostring(ah or"")
local al,am=pcall(K,{title=aj,message=ak,buttons=ai,style="install"})return al and am or#ai end
_.ask=function(ai,ah)local ak=ai..
(ah and(" ["..ah.."]")or"")..": "
local aj=j and j(ak,64)or nil;if aj==nil then return ah end
aj=tostring(aj):gsub("^%s+",""):gsub("%s+$","")if aj==""then return ah end;return aj end
_.installed=function(ah)local ai=ac()return
(ai and ai.info and ai.info(ah))~=nil end
_.install=function(ah)local ai=ac()if not(ai and ai.installByName)then return false,
"package manager unavailable"end;return
ai.installByName(ah,{session=r.sessionOf(a)})end
_.writeFile=function(ah,ai)if not aa then return false,"filesystem unavailable"end;if
aa.writeFileAtomic then return aa.writeFileAtomic(ah,ai)end;return
aa.writeFile(ah,ai)end
_.startService=function(ah)local al,ai=pcall(require,"kernel.rc")if not
(al and ai and ai.start)then return false,"rc unavailable"end
local aj,ak=ai.start(ah)if
not aj and tostring(ak):find("Already running",1,true)then return true end;return aj,ak end
_.setBootStart=function(ah,ai)if not aa then return false,"filesystem unavailable"end;local aj=
"/etc/rc.d/"..ah..".disabled"if ai then if aa.exists(aj)then return
aa.remove(aj)end;return true end;if
aa.exists(aj)then return true end;return aa.writeFile(aj,"1")end
_.modemCount=function()local ah,ai=0,0
for aj,ak in q.list()do if ak=="modem"then ah=ah+1;local am,al=pcall(q.proxy,aj)
if
am and al and al.isWireless and al.isWireless()then ai=ai+1 end end end;return ah,ai end
_.myModemAddress=function()return(q.list("modem")())end
_.hostname=function()local ah=_G._TOS and _G._TOS.net;if ah and ah.getHostname then return
ah.getHostname()end
if
aa and aa.exists("/etc/hostname")then local ai=aa.readFile("/etc/hostname")if type(ai)==s then return
(ai:match("^[^\n]*"))end end end
_.startPairing=function()local aj,ah=pcall(require,"cluster.api")
if not aj or not ah or not
ah.startPairing then return nil,"the Master daemon is not up yet"end;local ak,ai,al=pcall(ah.startPairing)
if not ak then return nil,tostring(ai)end;return ab.pairingWindow(ai,al)end
_.pairWith=function(ah,ai)local ak,aj=pcall(require,"cluster-manager")
if not ak or not aj or not
aj.pair then return false,"cluster-manager library not loadable"end;return aj.pair(ah,ai)end
if(Z[1]or""):lower()=="explain"then
H("=== What a cluster is made of ===",d.title)for ai,ah in ipairs(ab.explain())do H(ah,d.fg)end;return end;local af,ag=pcall(ab.run,_)if not af then
H("Setup failed: "..tostring(ag),d.error)end;n()end
b.intercom=function(Z,H)local ag,_=pcall(require,"intercom")
if
not ag or type(_)~="table"or not _.announce then
H("The Intercom is an add-on and isn't installed on this machine.",d.error)
H("Install it from the Optional Utilities disk:  pkg install intercom",d.dim)
H("(then `service start intercom` so this box will HEAR announcements)",d.dim)return end;local ad=_G._TOS and _G._TOS.fs
local aa=(Z[1]or""):lower()local ab,ac={},{}
do local ah
for ai=2,#Z do local aj=tostring(Z[ai])
if ai==ah then elseif aj:sub(1,2)=="--"then
local ak,al=aj:match("^%-%-([%w%-]+)=?(.*)$")
if ak then
if al~=""then ab[ak]=al elseif
(ak=="severity"or ak=="to"or ak=="drive")and Z[ai+1]and
tostring(Z[ai+1]):sub(1,2)~="--"then
ab[ak]=tostring(Z[ai+1])ah=ai+1 else ab[ak]=true end end else ac[#ac+1]=aj end end end
local function ae()local ah,ai=_.loadCatalog(ad)for ak,aj in ipairs(ai)do
H(string.format("  catalog line %d: %s",aj.line,aj.why),d.warning)end;return ah end
local function af(ah)
for aj,ai in ipairs(ah.errors or{})do H("  "..ai,d.warning)end;if ah.played then
H(string.format("Playing on the tape (%.1fs).",ah.seconds or 0),d.highlight)end
if ah.sent then
H("Broadcast to the network.",d.highlight)elseif not ah.localOnly then H("Nothing was broadcast.",d.warning)end end
if aa==""then local ai,ah=pcall(require,"intercomapp")if ai and ah and ah.open then
ah.open(a)return end;aa=z end
if aa==z then H("=== Intercom ===",d.title)local ah,aj=_.findDrive()
if ah then
local am=(
ah.getSize and ah.getSize())or 0;local al=(ah.isReady and ah.isReady())and"tape loaded"or
"NO TAPE"
H(string.format("  tape drive : %s, %d bytes",al,am),
al=="NO TAPE"and d.warning or d.fg)else
H("  tape drive : none ("..tostring(aj)..") — text-only announcements",d.warning)end;local ak=ae()
H("  catalog    : "..#ak.." cue(s) in ".._.CUES_PATH,d.fg)local ai=_.loadCfg(ad)
H("  receiving  : ".. (_.running()and"listening"or
"STOPPED (service start intercom)"),
_.running()and d.highlight or d.warning)
H(string.format("  popups     : at %s and above, at most one per %ds",ai.popupLevel,ai.popupCooldown),d.fg)
H(string.format("  filter     : ignore anything below %s",ai.minLevel),d.dim)H("",d.dim)
H("  intercom say \"...\" [--severity warn]   speak now, text only",d.dim)
H("  intercom play <cue>                     tape + text",d.dim)
H("  intercom test <cue>                     play it here, tell nobody",d.dim)H("  intercom cues | log | set <k> <v>",d.dim)elseif
aa=="cues"or aa=="list"then local ah=ae()
if#ah==0 then
H("No cues catalogued yet.",d.warning)
H("Edit ".._.CUES_PATH.." and describe what is on the tape:",d.dim)
H('  fuel-low  [0001] "Warning: Reactor fuel low." [0005]  warn',d.dim)return end
H(string.format(" %-16s %-7s %-7s %-8s %s","name","start","end","severity","says"),d.title)for aj,ai in ipairs(ah)do
H(string.format(" %-16s %-7d %-7d %-8s %s",ai.name,ai.start,ai.stop,ai.severity,ai.text),d.fg)end elseif aa=="say"then
local ai=table.concat(ac," ")
if ai==""then
H('Usage: intercom say "your announcement" [--severity warn] [--to <peer>]',d.dim)
H("Severities: "..table.concat(_.SEVERITIES," "),d.dim)return end
local ah=type(ab.severity)==s and ab.severity or"info"if not _.validSeverity(ah)then
H("Unknown severity: "..ah,d.error)
H("Use one of: "..table.concat(_.SEVERITIES," "),d.dim)return end
H(
"Announcing ("..ah.."): "..ai,d.title)
af(_.announce({text=ai,severity=ah,to=type(ab.to)==s and ab.to or nil}))elseif aa=="play"or aa=="test"then local ai=ac[1]if not ai then
H("Usage: intercom "..
aa.." <cue>   (intercom cues to list them)",d.dim)return end
local ah=_.findCue(ae(),ai)
if not ah then H("No such cue: "..ai,d.error)return end
if aa=="test"then
H("Testing cue '"..ah.name.."' — playing locally, sending nothing.",d.title)H("  should say: "..ah.text,d.dim)
H("  tape "..ah.start..
" -> "..ah.stop,d.dim)else
H("Announcing cue '"..ah.name.."' ("..ah.severity..")",d.title)H("  "..ah.text,d.fg)end
af(_.announce({cue=ah,localOnly=(aa=="test"),driveAddr=type(ab.drive)==s and ab.drive or nil,to=
type(ab.to)==s and ab.to or nil}))elseif aa=="log"then local ah=_.loadSpool(ad)if#ah==0 then
H("Nothing heard yet.",d.dim)return end;local ai=tonumber(ac[1])or 20
for aj=math.max(1,
#ah-ai+1),#ah do local al=ah[aj]local ak=al.severity or"info"
H("  "..
_.formatLine(al),
(ak=="critical"or ak=="alert")and d.error or(ak=="warn")and d.warning or d.fg)end elseif aa=="set"then if not i(H)then return end;local ah,ai=ac[1],ac[2]local aj=_.loadCfg(ad)
if
not ah then
H("Usage: intercom set <popuplevel|minlevel|cooldown|echotape> <value>",d.dim)
H("  popuplevel <sev>   interrupt with a message box at this and above",d.dim)
H("  minlevel   <sev>   ignore anything quieter than this",d.dim)
H("  cooldown   <secs>  minimum quiet between message boxes",d.dim)
H("  echotape   on|off  also play received cues on this box's tape",d.dim)return end;ah=ah:lower()
if ah=="popuplevel"or ah=="minlevel"then if not
_.validSeverity(ai)then
H("Severities: "..table.concat(_.SEVERITIES," "),d.error)return end
aj[
ah=="popuplevel"and"popupLevel"or"minLevel"]=ai elseif ah=="cooldown"then local am=tonumber(ai)if not am or am<0 or am>3600 then
H("cooldown: 0-3600 seconds",d.error)return end;aj.popupCooldown=am elseif
ah=="echotape"then
aj.echoToTape=(ai=="on"or ai=="true"or ai=="1")else H("Unknown setting: "..ah,d.error)return end;local ak,al=_.saveCfg(aj,ad)
if ak then H("Saved.",d.highlight)else H("Save failed: "..
tostring(al),d.error)end else
H("Usage: intercom [status|cues|say|play|test|log|set] ...",d.title)
H("  intercom say \"text\" [--severity <lvl>]  announce text right now",d.dim)
H("  intercom play <cue>                      play a tape cue AND announce it",d.dim)
H("  intercom test <cue>                      play it here only, to check it",d.dim)
H("  intercom cues                            what's catalogued on the tape",d.dim)
H("  intercom log [N]                         what this box has heard",d.dim)
H("  intercom set <key> <value>               receive policy (admin)",d.dim)end end
b.mail=function(Z,H)local ac,_=pcall(require,"mail")
if not ac or type(_)~="table"or not
_.send then
H("Mail is an add-on and isn't installed on this machine.",d.error)
H("Install it from the Optional Utilities disk:  pkg install mail",d.dim)
H("(then `service start mail` so this box can RECEIVE mail)",d.dim)return end;if not _.available()then
H("Mail unavailable (no network hardware?)",d.error)return end;_.tick()
local ab=a.who or"user"local aa=Z[1]
if not aa or aa=="ui"or aa=="tui"then
local ae,ad=pcall(require,"mailapp")if ae and ad and ad.open then ad.open(a)return end end
if not _.running()then
H("Note: the mail service is stopped — this box won't RECEIVE mail.",d.warning)
H("      Start it with:  service start mail",d.dim)end
if aa=="send"then local af=Z[2]if not af then
H("Usage: mail send <peer|alias|user@peer|*> [subject] [body...]",d.dim)return end
local ah,ai=_.resolveRecipient(af,k and k.aliases and
k.aliases.resolve)local aj=Z[3]or""local ad;if Z[4]then ad=table.concat(Z," ",4)elseif j then
ad=j("Body: ",200)end
if not ad then H("Cancelled",d.dim)return end
local ag,ae=_.send({to=ah,user=ai,fromUser=ab,subject=aj,body=ad})
if ag then
H("Queued "..tostring(ag):sub(1,18)..
(ae and"  (sealed)"or"  (PLAINTEXT bulletin)"),
ae and d.highlight or d.warning)else
H("Send failed: "..tostring(ae),d.error)end elseif aa=="read"then local ae=tonumber(Z[2])local af=_.inboxBox(ab)local ad=af and ae and
af:get(ae)if not ad then
H("No message #"..tostring(Z[2]),d.error)return end;af:markRead(ae)
H(string.rep("-",math.min(I,50)),d.dim)
H("From:    "..

(ad.fromUser and(ad.fromUser.." @ ")or"")..tostring(ad.from):sub(1,12),d.fg)
H("Subject: "..
(ad.subject~=""and ad.subject or"(no subject)"),d.title)if not ad.readable then
H("[sealed - no shared secret to open this]",d.warning)end
H(string.rep("-",math.min(I,50)),d.dim)for ag in
(tostring(ad.body).."\n"):gmatch("(.-)\n")do H(ag,d.fg)end elseif
aa=="delete"or aa=="rm"then local ad=tonumber(Z[2])local ae=_.inboxBox(ab)if
ae and ad and ae:delete(ad)then H("Deleted #"..ad,d.highlight)else
H("No message #"..tostring(Z[2]),d.error)end else
local ad,af=_.inbox(ab)if not ad then H(tostring(af),d.error)return end
if
#ad==0 then H("(inbox empty)",d.dim)else
H("Inbox for "..ab..":",d.title)for ah,ag in ipairs(ad)do
H(_.inboxRow(ag,ah,I-1),ag.read and d.dim or d.fg)end end;local ae=_.pending()if ae and ae>0 then
H(ae.." outbound awaiting delivery",d.dim)end
H("Commands: mail send <peer> [subj] [body] | read <n> | delete <n>",d.dim)end end
b.rbmk=function(Z,H)local aa,_=pcall(require,"rbmk-cmd")
if
not aa or type(_)~="table"or not _.run then
H("The RBMK controller add-on isn't installed on this machine.",d.error)
H("Install it from the Optional Utilities disk:  pkg install rbmk-control",d.dim)
H("Then:  rbmk survey   (identifies the console's real API)",d.dim)return end;local ab,ac=pcall(require,"kernel.screen")
_.run(Z,H,{display=m,event=G,screen=ab and ac or nil})end
b.robot=function(Z,H)local ab,_=pcall(require,"peripheral.robot")if not ab then
H("No robot module",d.error)return end;if not _.available()then
H("Not a robot",d.error)return end;local aa=Z[1]
if aa=="forward"or aa=="fwd"then
local ac,ad=_.forward()
H(ac and"Moved forward"or tostring(ad),ac and d.highlight or d.error)elseif aa=="back"then local ac,ad=_.back()
H(ac and"Moved back"or tostring(ad),ac and
d.highlight or d.error)elseif aa=="up"then local ac,ad=_.up()
H(ac and"Moved up"or tostring(ad),
ac and d.highlight or d.error)elseif aa=="down"then local ac,ad=_.down()
H(ac and"Moved down"or tostring(ad),ac and
d.highlight or d.error)elseif aa=="left"then _.turnLeft()H("Turned left",d.highlight)elseif
aa=="right"then _.turnRight()H("Turned right",d.highlight)elseif aa=="swing"then
local ac,ad=_.swing(Z[2])
H(ac and"Swing!"or tostring(ad),ac and d.highlight or d.error)elseif aa=="use"then local ac,ad=_.use(Z[2])
H(ac and"Used!"or tostring(ad),
ac and d.highlight or d.error)elseif aa=="detect"then local ac,ad=_.detect(Z[2])
H(
ac and"Block: "..tostring(ad)or"Nothing",d.fg)elseif aa=="inv"then local ac=_.inventory()if ac then
for ae,ad in ipairs(ac)do if ad.count>0 then
H(string.format(" [%2d] %dx %s",ad.slot,ad.count,
ad.name or"?"),d.fg)end end end else
H("Usage: robot <forward|back|up|down|left|right|swing|use|detect|inv>",d.dim)end end
b.inventory=function(Z,H)local ab,_=pcall(require,"peripheral.inventory")if not ab then
H("No inventory module",d.error)return end;if not _.available()then
H("No inventory controller/transposer",d.error)return end;local ac=Z[1]and
(tonumber(Z[1])or Z[1])or nil
local aa=_.list(ac)
if aa then
H(string.format(" %-4s %-24s %s","Slot","Item","Count"),d.title)
for ae,ad in ipairs(aa)do if ad.count>0 then
H(string.format(" %-4d %-24s %d",ad.slot,(ad.name or"?"):sub(1,24),ad.count),d.fg)end end else H("Cannot read inventory",d.error)end end;b.inv=b.inventory
b.component=function(Z,H)if not i(H)then return end
if not Z[1]then
H("Usage: component <type> [method] [args...]",d.dim)
H("  component list            List all component types",d.dim)
H("  component gpu             Show GPU methods",d.dim)
H("  component gpu getDepth    Call gpu.getDepth()",d.dim)
H("  component reload-caps     Reload the cap configs (see below)",d.dim)return end
if Z[1]=="reload-caps"then local af,ae=pcall(require,"kernel.sandbox")if not af or not
ae.reloadComponentConfig then
H("Sandbox doesn't support reload-caps",d.error)return end
local ag,ah=ae.reloadComponentConfig()local ab,ac=0,0;for aj in pairs(ag or{})do ab=ab+1 end
for aj in pairs(ah or{})do ac=ac+1 end
H(string.format("Reloaded: %d extra base, %d extra gated types",ab,ac),d.highlight)local ai,ad=pcall(require,E)
if ai and ad and ad.reloadCapConfig then
local al,am=ad.reloadCapConfig()local aj,ak=0,0;for an in pairs(al or{})do aj=aj+1 end;for an,ao in pairs(am or{})do for aq in pairs(ao)do ak=
ak+1 end;local ap=an end
H(string.format("Reloaded: %d extra package caps, %d denials",aj,ak),d.highlight)if aj>0 or ak>0 then
H("Packages already loaded this boot keep their old caps.",d.dim)end end;return end
if Z[1]=="list"then local ab={}for ad,ac in q.list()do if not ab[ac]then ab[ac]=0 end
ab[ac]=ab[ac]+1 end;for ac,ad in pairs(ab)do
H(string.format("  %-20s x%d",ac,ad),d.fg)end;return end;if not J(H)then return end;local _=Z[1]
local aa=q.proxy(q.list(_)()or"")
if not aa then H("No component: ".._,d.error)return end
if not Z[2]then local ab={}
for ad,ac in pairs(aa)do
local ae=type(ac)=="table"and getmetatable(ac)
if type(ac)=="function"or
(type(ae)=="table"and ae.__call)then ab[#ab+1]=ad end end;table.sort(ab)
for ad,ac in ipairs(ab)do H("  "..ac.."()",d.fg)end else
if _=="eeprom"and
(Z[2]=="set"or Z[2]=="setData"or Z[2]=="makeReadonly")then
H("Denied: use the 'flash' command to write EEPROM",d.error)return end;local ad=aa[Z[2]]if not ad then
H("Unknown method: "..Z[2],d.error)return end;local ab={}
for ae=3,#Z do local af=Z[ae]
if af=="true"then
ab[#ab+1]=true elseif af=="false"then ab[#ab+1]=false elseif tonumber(af)then ab[#ab+1]=tonumber(af)else ab[
#ab+1]=af end end
local ac=table.pack(pcall(ad,table.unpack(ab)))
if ac[1]then
for ae=2,ac.n do H("  "..tostring(ac[ae]),d.fg)end else H("Error: "..tostring(ac[2]),d.error)end end end
b.internet=function(Z,H)local ab,aa=pcall(require,"kernel.internet")if not ab or not aa then
H("internet module unavailable",d.error)return end
local _=(Z[1]or z):lower()
if _==z then local f=aa.status()
if not f.present then
H("No internet card installed.",d.warning)
H("An Internet Card goes in a card slot; the machine needs no",d.dim)
H("other change. TOS uses it for 'pkg fetch' and nothing else",d.dim)
H("unless a package asks for the 'internet' capability.",d.dim)return end
H("Internet card "..tostring(f.addr),d.title)
H("  HTTP:    "..
(f.http and"available"or"DISABLED by the server"),f.http and d.highlight or d.warning)
H("  TCP:     "..
(f.tcp and"available"or"disabled by the server"),f.tcp and d.fg or d.dim)
H("  Machine: "..
(f.enabled and"enabled"or"DISABLED (config: internet)"),f.enabled and d.highlight or d.warning)
if f.reason then H("  -> "..f.reason,d.warning)end
if not f.http and f.present then H("",d.dim)
H("HTTP is switched off in the SERVER's OpenComputers config,",d.dim)
H("not in TOS. Only the server owner can change it.",d.dim)end elseif _=="on"or _=="off"then if not i(H)then return end
local ad,ac=pcall(require,"kernel.config")
if not ad then H("config unavailable",d.error)return end;ac.set("internet",_=="on")
if ac.save then pcall(ac.save)end
H("Internet access ".. (_=="on"and"enabled"or"disabled")..
" on this machine.",d.highlight)elseif _=="get"then
if not Z[2]then H("Usage: internet get <url>",d.dim)return end;local ac,af,ad=aa.get(Z[2])
if not ac then H(tostring(af),d.error)return end
H(string.format("%d bytes%s",#ac,(ad and ad.status)and("  (HTTP "..
tostring(ad.status)..")")or""),d.dim)local ae=0
for ag in ac:gmatch("([^\n]*)\n?")do
if ae>=20 then H("... (truncated)",d.dim)break end;H(ag,d.fg)ae=ae+1 end else
H("Usage: internet [status|get <url>|on|off]",d.dim)end end
b.compat=function(Z,H)local _,aa=pcall(require,"compat")if not _ then
H("Compat layer not loaded",d.error)return end;local ab=aa.list()
H(" OpenOS Compatibility Layer",d.title)
H(string.format(" %-16s %s","Module",C),d.dim)for ad,ac in ipairs(ab)do
H(string.format(" %-16s %s",ac.name,ac.loaded and"loaded"or"not loaded"),
ac.loaded and d.highlight or d.dim)end end
b.disk=function(Z,H)local _=Z[1]
if not _ or _=="list"then
local aa=e.mounts and e.mounts()or nil
if aa and type(aa)=="table"and#aa>0 then local ab={}
for ad,ac in ipairs(aa)do if
ac.mountPoint~="/"then ab[#ab+1]=ac end end
if#ab==0 then H(x,d.dim)else
H(string.format(" %-16s %-10s %s","Mount","Label",C),d.title)H(string.rep("-",42),d.dim)
for ad,ac in ipairs(ab)do
local ae=ac.mountPoint;local af=r.classifyDisk(e,ae)
local ag=(ac.label or""):sub(1,10)
H(string.format(" %-16s %-10s %s",ae:sub(1,16),ag,af.desc),
af.kind~="data"and d.highlight or d.fg)end end elseif e.exists("/mnt")then local ab=e.list("/mnt")
if ab and#ab==0 then H(x,d.dim)elseif ab then
H(string.format(" %-16s %-8s %s","Mount","Type",C),d.title)H(string.rep("-",42),d.dim)
for ad,ac in ipairs(ab)do local ae="/mnt/"..
ac:gsub("/$","")local af=r.classifyDisk(e,ae)
H(string.format(" %-16s %-8s %s",ae:sub(1,16),"disk",af.desc),
af.kind~="data"and d.highlight or d.fg)end else H(x,d.dim)end else H(x,d.dim)end
do local ab=0;for ac in q.list("drive",true)do ab=ab+1 end
if ab>0 then H("",d.dim)
H(ab..
" unmanaged (raw) drive(s) attached — not filesystems, so",d.warning)
H("they cannot appear above until formatted and mounted.",d.dim)
H("  drive list          see them, with address and capacity",d.dim)
H("  drive format <addr> make one a TBFS filesystem",d.dim)end end
H("disk info <mnt> for details  ·  df for space  ·  jbod to pool disks",d.dim)elseif _=="info"then if not Z[2]then
H("Usage: disk info <mount-point>",d.dim)return end;local aa=e.normalize(Z[2])if not
e.exists(aa)or not e.isDirectory(aa)then
H("Not a valid mount point: "..aa,d.error)return end
local ac=e.spaceTotal(aa)local ad=e.spaceFree(aa)H(" Mount: "..aa,d.title)if
ac and ac>0 then
H(string.format(" Space: %dK free / %dK total",math.floor(ad/1024),math.floor(ac/1024)),d.fg)end
local ab=r.classifyDisk(e,aa)
H(" Contains: "..ab.desc,ab.kind~="data"and d.highlight or d.dim)if ab.hint then H("   -> "..ab.hint,d.dim)end elseif _==
"install"then
H("'disk install' folded into the package manager:",d.warning)
H("  pkg install              scan all mounts, confirm per package",d.dim)
H("  pkg install <mnt>        install one specific directory",d.dim)elseif _=="export"then
H("'disk export' was removed with the legacy module system.",d.warning)
H("To build an install disk for add-ons, use the Optional Utilities",d.dim)
H("builder: TOS-Extras/build/build-disk.lua.",d.dim)
H("For a full TOS image, use 'deploy <mount>' instead.",d.dim)elseif _=="eject"then if not Z[2]then
H("Usage: disk eject <mount-point>",d.dim)return end;local aa=e.normalize(Z[2])
local ab,ac=e.unmount(aa)if ab then H("Ejected: "..aa,d.highlight)else
H("Eject failed: "..tostring(ac),d.error)end else
H("Usage: disk [list|info <mnt>|eject <mnt>]",d.dim)
H("  Removable disks + what's on them.  Install packages: 'pkg'.",d.dim)
H("  Pool several disks into one: 'jbod'.   Free space per mount: 'df'.",d.dim)end end
b.drive=function(Z,H)local _=Z[1]local function ad()local ag,ah=pcall(require,"blockfs")
return ag and ah or nil end
local function ab(ag)local ah={}for al in q.list("drive",true)do
if not ag or al:sub(1,
#ag)==ag then ah[#ah+1]=al end end;table.sort(ah)
if#ah==0 then return nil,

"no unmanaged drive found".. (ag and(" for '"..ag.."'")or"")end;if ag and#ah>1 then return nil,
"ambiguous prefix '"..ag.."' ("..#ah.." drives)"end
local ai=ah[1]local ak,aj=pcall(q.proxy,ai)
if not ak or not aj then return nil,"cannot proxy drive"end;return aj,ai end
if not _ or _=="list"then
H("Unmanaged drives (raw block devices):",d.title)local ag,ah=0,ad()
for ai in q.list("drive",true)do local ak,aj=pcall(q.proxy,ai)
if ak and aj then
ag=ag+1
local am=(aj.getSectorSize and aj.getSectorSize())or 0
local an=(aj.getCapacity and aj.getCapacity())or 0
local ao=(aj.getPlatterCount and aj.getPlatterCount())or 1;local al="unformatted"
if ah then local ap=ah.stats(aj)if ap then
al=string.format('TBFS "%s"  %s used  %d%% frag',ap.label,g(
ap.usedBlocks*ap.sectorSize),math.floor(ap.fragmentation*100+0.5))end end
H(string.format("  %s  %s  %dB/sector  %d platter(s)  %s",ai:sub(1,8).."...",g(an),am,ao,al),d.fg)end end
if ag==0 then H("  (none attached)",d.dim)
H("  Managed disks appear under 'disk' / 'df'; this is for raw drives.",d.dim)elseif not ah then
H("  Install 'blockfs' to format/mount them:  pkg install blockfs",d.dim)else
H("  format | mount | check [--repair] | defrag [--if-over N] | read | write",d.dim)end;return end
if _=="info"then local ag,ah=ab(Z[2])
if not ag then H(tostring(ah),d.error)return end;H(w..ah:sub(1,8).."...",d.title)
H(string.format("  capacity   %s",g((
ag.getCapacity and ag.getCapacity())or 0)),d.fg)
H(string.format("  sector     %d bytes",
(ag.getSectorSize and ag.getSectorSize())or 0),d.fg)
H(string.format("  platters   %d",
(ag.getPlatterCount and ag.getPlatterCount())or 1),d.fg)local ai=ad()
if ai then local aj=ai.stats(ag)
if aj then
H("  TBFS volume:",d.highlight)
H(string.format('    label "%s"   %s / %s used   %d file(s), %d dir(s)',aj.label,g(aj.usedBlocks*aj.sectorSize),g(
aj.dataBlocks*aj.sectorSize),aj.files,aj.dirs),d.fg)
H(string.format("    fragmentation %d%%   %s",math.floor(aj.fragmentation*100+0.5),
aj.clean and"clean"or"DIRTY (mounted or unclean)"),d.fg)else
H("  Not a TBFS volume. It holds "..
(p(ag)or"something unreadable")..".",d.dim)end else
H("  It holds ".. (p(ag)or"something unreadable")..".",d.dim)
H("  (install 'blockfs' to format or mount it)",d.dim)end;return end;local aa=ad()if not aa then
H("The 'blockfs' package is required:  pkg install blockfs",d.error)return end
local function ac(ag)for ai,ah in ipairs(
e.mounts and e.mounts()or{})do
if ah.address==ag then return ah.mountPoint,ah end end;return nil end
local function af(ag)local ah,ai={},false
for an,am in ipairs(e.mounts and e.mounts()or{})do
if
am.mountPoint==ag then if am.openFiles==nil then ai=true elseif am.openFiles>0 then
ah[#ah+1]=string.format("%d open file handle(s)",am.openFiles)end end end
local aj=(ag:sub(-1)=="/")and ag or(ag.."/")
local ak,al=pcall(function()return o and o.list and o.list()or{}end)
for an,am in ipairs(ak and al or{})do local ao=am.cwd
if type(ao)==s and(ao==ag or
ao:sub(1,#aj)==aj)then
ah[#ah+1]=string.format("%s (pid %s) is in %s",tostring(
am.name or"?"),tostring(am.pid or"?"),ao)end end;return ah,ai end
local function ae(ag,aj,ah,ai)local ak=ac(ag)if not ak then return ai()end;local al,ap=af(ak)
if#al>0 or ap then
local ax=
(#al>0)and(
"\n  "..table.concat(al,"\n  "))or"\n  (the driver cannot say what is open)"
local aw=string.format("'%s' has to take %s out of the mount table while it works.\n"..
"Something is using it right now:%s\n\n"..
"Continuing will pull the volume out from under it. It is\n".."remounted at %s afterwards.",ah,ak,ax,ak)local av
if l then
av=l(aw,{title="Unmount "..ak.."?",severity=D,yes="Unmount and continue",no=A})else H(aw,d.warning)
local ay=j and
j("Unmount "..ak.." and continue? [y/N]: ",4)or"n"av=(ay or""):lower()=="y"end;if not av then
H("Cancelled; the drive is still mounted.",d.dim)return false end else
H(string.format("Nothing is using %s — unmounting for the %s.",ak,ah),d.dim)end;local am=r.sessionOf(a)local aq,ar=e.unmount(ak,am)if aq==false then
H("Could not unmount "..ak..
": "..tostring(ar or"?"),d.error)return false end;local as,an=pcall(ai)local at=function()
return math.floor(
h.uptime and h.uptime()or 0)end
local ao,au=aa.mount(aj,{now=at})
if ao then local av,aw=e.mount(ak,ao,am)
if av==false then
H("Remount FAILED at "..ak..
": "..tostring(aw or"?"),d.error)
H("  Mount it by hand:  drive mount "..ag:sub(1,8).." "..ak,d.dim)else H("Remounted at "..ak..".",d.dim)pcall(n)end else
H("Remount FAILED ("..tostring(au).."); the drive is detached.",d.error)
H("  Mount it by hand:  drive mount "..ag:sub(1,8).." "..ak,d.dim)end;if not as then error(an,0)end;return an end
if _=="unmount"or _=="umount"then if not i(H)then return end;local ai,ag=ab(Z[2])if not
ai then H(tostring(ag),d.error)return end
local ah=ac(ag)if not ah then
H(w..ag:sub(1,8).."... is not mounted.",d.dim)return end;local aj=r.sessionOf(a)
local ak,al=e.unmount(ah,aj)if ak==false then
H(tostring(al or"unmount failed"),d.error)return end
H("Unmounted "..ah.." (volume marked clean).",d.highlight)pcall(n)return end
if _=="format"then if not i(H)then return end;local ah,ag=ab(Z[2])if not ah then
H(tostring(ag),d.error)return end
local ak=Z[3]or("disk"..ag:sub(1,4))local ai=p(ah,aa)local aj
if l then
aj=l("Format drive "..
ag:sub(1,8)..
"... as TBFS?"..
"\n\n".. (ai and
("It holds "..ai..".\n")or"")..

"Every file on it is destroyed. There is no undo and no\n".."recovery tool in TOS that can bring it back.",{title="Format drive",severity=D,yes="Format",no=A})else if ai then
H(w..ag:sub(1,8).."... holds "..ai..".",d.warning)end
local al=
j and j("FORMAT "..
ag:sub(1,8).."... as TBFS? destroys all data [y/N]: ",4)or"n"aj=(al or""):lower()=="y"end;if not aj then H("Cancelled.",d.dim)return end
ae(ag,ah,"format",function()
local al,am=aa.format(ah,{label=ak,now=function()
return math.floor(
h.uptime and h.uptime()or 0)end})if al then
H('Formatted as TBFS "'..ak..'".',d.highlight)else
H("Format failed: "..tostring(am),d.error)end end)if not ac(ag)then
H("Mount it with: drive mount "..ag:sub(1,8),d.dim)end;return end
if _=="mount"then if not i(H)then return end;local ai,aj=ab(Z[2])if not ai then
H(tostring(aj),d.error)return end
local al=function()return
math.floor(h.uptime and h.uptime()or 0)end;local ah,am=aa.mount(ai,{now=al})if not ah then
H("Mount failed: "..tostring(am),d.error)return end
local an=r.safeMountName(ah.getLabel and ah.getLabel(),aj)local ag=Z[3]or("/mnt/"..an)if ag:sub(1,1)~="/"then
ag="/mnt/"..ag end;if not e.exists("/mnt")then
pcall(e.makeDirectory,"/mnt")end;if not e.exists(ag)then
pcall(e.makeDirectory,ag)end;local ao=r.sessionOf(a)
local ap,aq=e.mount(ag,ah,ao)if ap==false then
H(tostring(aq or"mount failed"),d.error)return end
H("Mounted TBFS at "..ag,d.highlight)local ak=aa.stats(ai)
if ak and ak.fragmentation>0.30 then
H(string.format("  Note: %d%% fragmented — 'drive defrag %s' to compact.",math.floor(
ak.fragmentation*100+0.5),aj:sub(1,8)),d.warning)end;pcall(n)return end
if _=="check"or _=="fsck"then if not i(H)then return end;local ah,ai=ab(Z[2])if not ah then
H(tostring(ai),d.error)return end
local aj=Z[3]=="--repair"or Z[3]=="-r"local ag
if aj then
local al=ae(ai,ah,"check --repair",function()ag=aa.check(ah,{repair=true,yield=t})end)if al==false then return end else
ag=aa.check(ah,{repair=false,yield=t})end
if not ag then H("Not a TBFS volume.",d.error)return end;local ak=ac(ai)
if ak and not aj then local al={}
for an,am in ipairs(ag.problems)do if
am~="volume was not cleanly unmounted"then al[#al+1]=am end end;ag.problems=al;ag.ok=(#al==0)
H("(mounted at "..
ak..": the dirty flag is expected and not counted)",d.dim)end
if ag.ok then H("TBFS clean: no problems.",d.highlight)else
H((ag.repaired and
"Repaired. Findings:"or"Problems found:"),
ag.repaired and d.highlight or d.warning)
for am,al in ipairs(ag.problems)do H("  - "..al,d.dim)end;if not aj and not ag.ok then
H("  Run 'drive check "..ai:sub(1,8).." --repair' to fix.",d.dim)end end;return end
if _=="defrag"then if not i(H)then return end;local ag,ai=ab(Z[2])if not ag then
H(tostring(ai),d.error)return end;local ah=nil
for aj=3,#Z do if
Z[aj]=="--if-over"and Z[aj+1]then ah=tonumber(Z[aj+1])end end
if ah then local aj=aa.stats(ag)
if
aj and(aj.fragmentation*100)<ah then
H(string.format("Fragmentation %d%% below %d%% — skipped.",math.floor(aj.fragmentation*100+0.5),ah),d.dim)return end end;H("Defragmenting...",d.title)
ae(ai,ag,"defrag",function()
local aj,ak=aa.defrag(ag,{now=function()return math.floor(h.uptime and
h.uptime()or 0)end})if not aj then
H("Defrag failed: "..tostring(ak),d.error)return end
H(string.format("Defragmented %d block(s): %d%% -> %d%% fragmented.",aj.moved,math.floor(
aj.before*100+0.5),math.floor(aj.after*100+0.5)),d.highlight)end)return end
if _=="read"then if not i(H)then return end;local aj,ak=ab(Z[2])if not aj then
H(tostring(ak),d.error)return end;local ag=tonumber(Z[3])if not ag then
H("Usage: drive read <addr> <sector>",d.dim)return end
local al,ah=pcall(aj.readSector,ag+1)if not al then
H("Read failed: "..tostring(ah),d.error)return end;local ai={}for am=1,math.min(64,# (ah or""))
do
ai[#ai+1]=string.format("%02X",(ah):byte(am))end
H("Sector "..ag.." (first 64 bytes):",d.title)H("  "..table.concat(ai," "),d.dim)
return end
if _=="write"then if not i(H)then return end
H("'drive write' is intentionally not exposed as a one-liner (a stray",d.warning)
H("sector write corrupts a filesystem). Use the blockfs API from 'lua'",d.dim)
H("for deliberate raw writes. Format/mount/defrag cover normal use.",d.dim)return end
H("Usage: drive [list | info <addr> | format <addr> [label] | mount <addr> [path]",d.dim)
H("             | unmount <addr> | check <addr> [--repair] | defrag <addr> [--if-over N]",d.dim)
H("             | read <addr> <sec>]   (format/repair/defrag need the drive unmounted)",d.dim)end
b.tape=function(Z,H)local aa,_=pcall(require,E)
if aa and _ and _.getCommand then
local ab=_.getCommand("tape")if ab then ab(Z,H)return end
if _.info and _.info("tape")then
H("The tape package is installed but not enabled.",d.warning)H("Enable it with:  pkg enable tape",d.highlight)
return end end;H("Tape Storage",d.title)H("",d.fg)
H("The 'tape' package isn't installed. To use Computronics tapes:",d.fg)H("",d.fg)
H(" Install from the Optional Utilities disk:",d.highlight)
H("    pkg install              (with the disk inserted)",d.dim)H("  or, if it's in a configured repo:",d.dim)
H("    pkg install tape",d.dim)H("",d.fg)
H(" Build your own: a /usr/modules/<name>/init.lua returning",d.dim)
H("   { commands = { tape = function(args, o) ... end } }",d.dim)
H(" plus a package.lua manifest (kind=\"command\"). See the TOS Manual.",d.dim)end
b.deploy=function(Z,H)if not J(H)then return end
if Z[1]=="drive"then
local aC,al=pcall(require,"blockfs")
if not aC or not al then
H("Cannot deploy to a raw drive: TOS doesn't have the 'blockfs' package.",d.error)
H("blockfs is the filesystem that makes a raw drive usable + bootable.",d.dim)H("Install it first, then retry:",d.dim)
H("    pkg install blockfs",d.highlight)return end
local ay=e.exists("/usr/lib/blockfs.lua")and e.readFile("/usr/lib/blockfs.lua")
if not ay then
H("blockfs is loadable but /usr/lib/blockfs.lua is missing — reinstall it:",d.error)H("    pkg install blockfs",d.highlight)return end;local am={}
for aJ in q.list("drive",true)do if
not Z[2]or aJ:sub(1,#Z[2])==Z[2]then am[#am+1]=aJ end end;table.sort(am)if#am==0 then
H("No unmanaged drive"..
(Z[2]and
(" matching '"..Z[2].."'")or"").." found.",d.error)return end;if Z[2]and#am>1 then
H(
"Ambiguous prefix '"..Z[2].."' ("..#am.." drives).",d.error)return end;local an=am[1]
local aD,ao=pcall(q.proxy,an)if not aD or not ao then
H("Cannot proxy drive "..an:sub(1,8),d.error)return end;local au=al.bootBlob(ay)
local av=#au+4096;local aq={}local aE,az=pcall(require,"system_manifest")if aE and
type(az)=="table"then
for aK,aJ in ipairs(az)do if
type(aJ)=="table"and type(aJ.path)==s then aq[#aq+1]=aJ.path end end end;if#aq==0 then
H("system_manifest not loadable — aborting.",d.error)return end;local aw=nil
if al.plan and al.blocksFor then
local aJ,aN=al.plan(ao,{bootBytes=av})if not aJ then
H("This drive cannot hold TOS: "..tostring(aN)..". Nothing was erased.",d.error)return end
local function aO(aP)local aQ,aR=0,1
local aT,aU={["/"]=0},{}
local function aV(aW,aX)aT[aW]=(aT[aW]or 0)+5+#aX end;local function aS(aW)local aX=aW:match(y)return
(aX==nil or aX=="")and"/"or aX end
for aX,aW in ipairs(aq)do
local aZ,a_=pcall(e.size,aW)aQ=aQ+
al.blocksFor((aZ and tonumber(a_))or 0,aP)aR=aR+1
aV(aS(aW),aW:match("([^/]+)$"))local aY=aS(aW)while aY~="/"and not aU[aY]do aU[aY]=true;aR=aR+1
aV(aS(aY),aY:match("([^/]+)$"))aY=aS(aY)end end
for aX,aW in pairs(aT)do aQ=aQ+al.blocksFor(aW,aP)end;return aQ,aR end;local aL,aK=aO(aJ.ss)
if aK>aJ.inodeCount then local aQ=math.ceil(aK*1.25)
aw=math.max(512,math.floor(
aJ.ss*aJ.totalBlocks/aQ))local aP=al.plan(ao,{bootBytes=av,inodeRatio=aw})
if not aP or
aP.inodeCount<aK then
H(string.format("TOS needs %d inodes and this drive cannot hold that many. ".."Nothing was erased.",aK),d.error)return end
H(string.format("Sizing the inode table for this install: %d inodes (the default ".."would give %d, and TOS needs %d).",aP.inodeCount,aJ.inodeCount,aK),d.dim)aJ=aP end
if aL>aJ.dataBlocks then
H(string.format("TOS will not fit on this drive: it needs %s, and the drive holds "..
"%s once the boot region and metadata are laid out.  [E-306 ERR_DRIVE_TOO_SMALL]",g(
aL*aJ.ss),g(aJ.dataBlocks*aJ.ss)),d.error)
H("Nothing was erased. Use a larger drive, or a managed disk: deploy <mount-point>",d.dim)return end;local aM=(aJ.dataBlocks-aL)*aJ.ss
H(string.format("Fits: %s of %s, leaving %s spare; %d of %d inodes.",g(
aL*aJ.ss),g(aJ.dataBlocks*aJ.ss),g(aM),aK,aJ.inodeCount),d.dim)if aM<64*1024 then
H("Under 64 KB will be free after the install — logs, trash and swap fill that fast.",d.warning)end else
H("(This blockfs cannot check capacity before erasing — 'pkg upgrade blockfs' adds it.)",d.warning)end;local ax;local ar=p(ao,al)
if l then
ax=l("Install TOS onto raw drive "..
an:sub(1,8)..
"...?".."\n\n"..
(ar and
("It holds "..ar..".\n")or"")..
"The drive is erased and reformatted as bootable TBFS.\n".."Anything on it now is gone.",{title="Erase and install",severity=D,yes="Erase",no=A})else if ar then
H(w..an:sub(1,8).."... holds "..ar..".",d.warning)end
local aJ=
j and j("Install TOS onto raw drive "..
an:sub(1,8).."...? ERASES it [y/N]: ",4)or"n"ax=(aJ or""):lower()=="y"end;if not ax then H("Cancelled.",d.dim)return end;local aA=function()
return math.floor((h.uptime and
h.uptime())or 0)end
H("Formatting "..
an:sub(1,8).."... as bootable TBFS...",d.title)
local aF,aG=al.format(ao,{label="tos",bootBytes=av,now=aA,inodeRatio=aw})if not aF then
H("Format failed: "..tostring(aG).." (drive too small?)",d.error)return end
local ap,aH=al.mount(ao,{now=aA})if not ap then
H("Mount failed: "..tostring(aH),d.error)return end;local as,at=0,0
for aK,aJ in ipairs(aq)do t()
local aL=e.open(aJ,"r")
if aL then local aN=aJ:match(y)
if aN and aN~=""then local aP=""for aQ in aN:gmatch("[^/]+")do
aP=aP.."/"..aQ
if not ap.exists(aP)then ap.makeDirectory(aP)end end end;local aM=ap.open(aJ,"w")local aO=aM~=nil
while aO do local aP=aL:read(4096)
if not aP then break end;aO=ap.write(aM,aP)and true or false end;pcall(aL.close,aL)if aM then ap.close(aM)end;if aO then as=as+1 else
at=at+1;H("  FAIL "..aJ,d.error)end end end;local aB,aI=al.writeBoot(ao,au)ap.unmount()H("",d.fg)
if
aB and at==0 then
H(string.format("TBFS install written: %d files + boot blob (%s).",as,g(#au)),d.highlight)
H("The TOS BIOS boots TBFS drives directly. If this box runs an older",d.dim)
H("EEPROM, reflash first: 'flash /bios.lua'.",d.dim)
H("The disk also mounts like any volume: 'drive mount "..an:sub(1,8).."'.",d.dim)else
H(string.format("Wrote %d files, %d failed; boot blob: %s.",as,at,aB and"ok"or
("FAILED ("..tostring(aI)..")")),d.error)end;return end;local _=Z[1]
if not _ then
H("Usage: deploy <mount-point>   |   deploy drive <addr>  (raw disk, needs blockfs)",d.dim)
H("  Creates a TOS install disk on a mounted drive (Tier 2, 2 MB, or larger).",d.dim)H("  e.g. deploy /mnt/disk_ab12",d.dim)
H("  Insert the disk on another OpenOS computer and run:",d.dim)H("    # /mnt/<disk>/install.lua",d.dim)return end;_=e.normalize(_)
if#_>1 and _:sub(-1)=="/"then _=_:sub(1,-2)end
local aj={"/","/tos","/etc","/var","/usr","/home","/root","/public"}
for am,al in ipairs(aj)do
if _==al or _:sub(1,#al+1)==al.."/"then
H(
"Refusing to deploy onto '".._.."' (would overwrite system).",d.error)
H("Deploy only to an external mount, such as a second drive under /mnt.",d.dim)return end end;if not e.exists(_)or not e.isDirectory(_)then
H(
"Target does not exist or is not a directory: ".._,d.error)return end
H(
"Creating TOS install disk on ".._.." ...",d.title)local ae={}
do local am,al=pcall(require,"system_manifest")if am and
type(al)=="table"then
for ao,an in ipairs(al)do if
type(an)=="table"and type(an.path)==s then ae[#ae+1]=an.path end end end
if#ae==0 then
H("  WARN: system_manifest not loadable, using minimal file list",d.warning)
ae={"/init.lua","/tos/kernel/init.lua","/tos/kernel/hal.lua","/tos/kernel/event.lua","/tos/kernel/process.lua","/tos/kernel/fs.lua","/tos/kernel/display.lua","/tos/kernel/log.lua","/tos/kernel/serialize.lua","/tos/shell/init.lua"}end end;local ag=512;local aa,ah=0,{}local ad={}for am,al in ipairs(ae)do ad[#ad+1]=al end;ad[#ad+
1]=v;ad[#ad+1]=u
for am,al in ipairs(ad)do
if e.exists(al)then
local ap,aq=pcall(e.size,al)
aa=aa+ ((ap and tonumber(aq))or 0)local ao=_..al
if e.exists(ao)then local ar,as=pcall(e.size,ao)aa=aa- (
(ar and tonumber(as))or 0)else aa=aa+ag end;local an=al:match(y)
while an and an~=""and not ah[an]do ah[an]=true;if not e.exists(_..
an)then aa=aa+ag end;an=an:match(y)end end end;local af=e.spaceFree and e.spaceFree(_)
if af then
if aa>af then
H(string.format(
"TOS will not fit on %s: it needs %s, and %s is free.  ".."[E-306 ERR_DRIVE_TOO_SMALL]",_,g(aa),g(af)),d.error)
H("Nothing was copied. A Tier 2 drive (2 MB) holds an install disk; a floppy ".."(512 KB) does not.",d.dim)return end
H(string.format(" Needs %s; %s free on the target",g(math.max(0,aa)),g(af)),d.dim)end
local ak={"/tos/","/tos/kernel/","/tos/kernel/net/","/tos/shell/","/tos/compat/","/tos/peripheral/"}for am,al in ipairs(ak)do e.makeDirectory(_..al)end
local ab,ac,ai=0,0,0
for am,al in ipairs(ae)do
if e.exists(al)then local an,ao=e.copy(al,_..al)if an then ab=ab+1 else
H("  FAIL "..al..": "..
tostring(ao),d.error)ac=ac+1 end else ai=ai+1 end end
if e.exists(v)then if e.copy(v,_..v)then ab=ab+1 else ac=ac+1 end end
if e.exists(u)then
do local al,am=e.copy(u,_..u)
if al then ab=ab+1
H("  Copied install.lua (automated installer)",d.highlight)else
H("  FAIL writing install.lua: "..tostring(am),d.error)ac=ac+1 end end else
H("  WARNING: /install.lua not found on boot drive",d.error)
H("  The install disk will not have an automated installer.",d.dim)end;H("",d.fg)
if ac==0 then
H("Install disk created: "..ab.." files",d.highlight)H("",d.fg)
H("On the target machine (OpenOS), run:",d.dim)H("  # ".._..u,d.fg)
H("Or insert the disk and run: /mnt/<disk>/install.lua",d.dim)else
H(ab.." files copied, "..ac.." failed",d.error)end end
b.chat=function(Z,H)if not k then H(B,d.error)return end
local aa,_=pcall(require,"shell.panels.chatapp")if not aa then
H("Chat unavailable: "..tostring(_),d.error)return end;_.open(a)end
local function L(H)
local Z=_G._TOS and _G._TOS.net and _G._TOS.net.aliases;if type(H)==s and Z and Z.resolve then local _=Z.resolve(H)
if _ then return _ end end;return H end
b.rsh=function(Z,H)if not i(H)then return end;if not Z[1]or not Z[2]then
H("Usage: rsh <peer> <lua>   e.g. rsh two print(1+2)",d.dim)return end
if not k then H(B,d.error)return end;local ab,ac=pcall(require,"kernel.net.remote")if not ab then
H("Remote module unavailable",d.error)return end;local _=L(Z[1])
local ad=table.concat(Z," ",2)
H("Executing on ".._:sub(1,8).."...",d.dim)local aa,ae=ac.execute(_,ad)if aa then H(aa,d.fg)else
H("Error: "..tostring(ae),d.error)end end
b.scp=function(Z,H)if not i(H)then return end
if not Z[1]or not Z[2]then
H("Usage: scp <peer>:<remote_path> <local_path>",d.dim)
H("  Copies a file from a TRUSTED peer's /public.",d.dim)return end;if not k then H(B,d.error)return end
local ab,ac=pcall(require,"kernel.net.transfer")
if not ab then H("Transfer module unavailable",d.error)return end;local _,aa=Z[1]:match("^([^:]+):(.+)$")
if _ then local ad=L(_)local ae=N(Z[2])
H(
"Downloading "..aa..
" from ".._..
(ad~=_ and(" ("..ad:sub(1,8)..")")or"").."...",d.dim)local af,ag=ac.request(ad,aa,ae)if af then n()
H("Downloaded: "..aa.." -> "..ae,d.highlight)else
H("Transfer failed: "..tostring(ag),d.error)end else
H("Usage: scp <peer>:<remote_path> <local_path>",d.dim)end end
b.screen=function(Z,H)local aa,_=pcall(require,"kernel.screen")if not aa then
H("Screen module unavailable",d.error)return end
if Z[1]=="res"then
local ac=m.getGpu and m.getGpu()local ae,af=m.getSize()local ah,ai=ae,af
if ac then
local ap,ao,aq=pcall(ac.maxResolution)if ap and ao then ah,ai=ao,aq end end;local ab=h.getConfig and h.getConfig()local aj=Z[2]
if not aj then
H("=== Screen Resolution ===",d.title)
H(string.format("Current : %dx%d",ae or 0,af or 0),d.fg)
H(string.format("Maximum : %dx%d",ah or 0,ai or 0),d.dim)
if ac and ac.getScreen then local ap,ao=pcall(ac.getScreen)
if ap and type(ao)==s then
local ar,aq,as=pcall(require("component").invoke,ao,"getAspectRatio")if ar and aq then
H(string.format("Blocks  : %dx%d (physical)",aq,as),d.dim)end end end
H("Policy  : ".. ((ab and ab.get and ab.get("screenRes"))or
"auto"),d.fg)
H("Set: screen res <auto|max|WxH>   (e.g. screen res 80x25)",d.dim)return end;if not i(H)then return end;local ad=tostring(aj):lower()
if

ad~="auto"and ad~="max"and not ad:match("^%d+%s*[x×]%s*%d+$")then H("Usage: screen res <auto|max|WxH>",d.error)return end;if ab and ab.set then ab.set("screenRes",ad)
if ab.save then ab.save()end end
_.setPolicy(_.specFromConfig(ab))local al,am,ak=_.fitDisplay(a.displayIdx)
local an,ag=pcall(require,"shell.panels.state")
if an and ag and ag.recomputeLayout then ag.recomputeLayout(a)end;if c.drawAll then pcall(c.drawAll)end
H(string.format("Resolution -> %dx%d (policy '%s')",
al or ae or 0,am or af or 0,ad),d.highlight)if ak then H(ak,d.warning)end
H("Applied now and saved for next boot.",d.dim)return end
if Z[1]=="list"or not Z[1]then local ab=_.list()if#ab==0 then
H("No displays",d.dim)return end
for ad,ac in ipairs(ab)do
local ae=ac.active and" * "or"   "
H(string.format("%s%d: %s (%dx%d %d-bit)",ae,ac.index,ac.label,ac.w,ac.h,ac.depth),d.fg)end elseif Z[1]=="next"then _.next()
H("Switched to: ".._.active().label,d.highlight)elseif tonumber(Z[1])then
if _.setActive(tonumber(Z[1]))then
H("Switched to screen "..Z[1],d.highlight)else H("Invalid screen index",d.error)end else
H("Usage: screen [list|next|<index>|res [auto|max|WxH]]",d.dim)end end
local function O(H)
return
function(_,Z)local ab,aa=pcall(require,"shell.ext")
if ab and aa[H]then
aa[H](_,{K=h,E=G,P=o,F=e,D=m,U=M,o=Z,st=f,computer=F,cwd=a.cwd})else if H=="logout"then G.push("tos_logout",a.displayIdx)else
Z("Extension unavailable (low RAM?)",d.error)end end end end;for Z,H in
ipairs({"net","ping","hostname","config","battery","audio"})do b[H]=O(H)end end