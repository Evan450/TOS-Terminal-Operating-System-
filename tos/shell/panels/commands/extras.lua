
local x,t,y,u,z,v,A,B,C,w,r="/bios.lua","/install.lua","Cancel","Drive ","No network available","No removable disks mounted","Status","danger","kernel.pkg","status","string"local D=require("computer")local p=require("component")
local q=require("shell.panels.helpers")local s=function()end
do local b,a=pcall(require,"kernel.process")if b and a and
a.yieldCooperative then s=a.yieldCooperative end end
return
function(b,a,c)local g,G,o,e,m,M=a.K,a.E,a.P,a.F,a.D,a.U;local P,k,f=a.SC,a.NM,a.st;local d=a.T;local Q=a.tier
local I,R=a.W,a.H;local N=c.rp;local S=c.openViewTab;local T=c.openEditTab;local n=c.refreshBrowser
local U=c.canRead;local V=c.canWrite;local W=c.canAccess;local J=c.rootOnly;local K=c.dialog;local h=c.adminOnly
local X=c.makeProgramEnv;local j=q.fmtSz
local Y=function(E)return q.expandBuf(a,E)end;local i=c.promptInput;local l=c.confirm
local function F(H,E)
local aa,_=pcall(require,"shell.panels.diskprobe")if not aa or type(_)~="table"then return nil end
local ab,Z=pcall(_.probe,H)if not ab or type(Z)~="table"then return nil end
if
Z.kind=="tbfs"and E and E.stats then local ac,f=pcall(E.stats,H)
if ac and
type(f)=="table"then
local ad=tostring(f.label or""):gsub("%c","?"):sub(1,24)return
('a TBFS volume labelled "%s": %d file(s), %d dir(s)'):format(ad,
tonumber(f.files)or 0,tonumber(f.dirs)or 0)end end;return Z.text end
b.redstone=function(E,H)local _,Z=pcall(require,"peripheral.redstone")if not _ then
H("No redstone module",d.error)return end
if not E[1]then local aa=Z.status()if not aa then
H("No redstone component",d.error)return end
H(" Side      In  Out",d.title)for ac,ab in ipairs(aa)do
H(string.format(" %-9s %2d  %2d",ab.name,ab.input,ab.output),d.fg)end elseif
E[1]=="set"and E[2]and E[3]then
local aa,ab=Z.setOutput(E[2],tonumber(E[3])or 15)
H(aa and"Set "..E[2].." = "..E[3]or tostring(ab),
aa and d.highlight or d.error)elseif E[1]=="pulse"and E[2]then
Z.pulse(E[2],tonumber(E[3])or 0.5)H("Pulsed "..E[2],d.highlight)else
H("Usage: redstone [set <side> <0-15>|pulse <side> [duration]]",d.dim)end end;b.rs=b.redstone
b["cluster-setup"]=function(H,E)if not J(E)then return end
local ac,aa=pcall(require,"shell.clustersetup")if not ac or not aa then
E("cluster setup module unavailable",d.error)return end
local _=_G._TOS and _G._TOS.fs
local function ab()local ag,ah=pcall(require,C)return ag and ah or nil end
local ad={ok=d.highlight,warn=d.warning,err=d.error,title=d.title}local Z={}
Z.say=function(ag,ah)E(ag or"",ad[ah or""]or d.fg)end
Z.choose=function(ai,ag,ah)
if not K then Z.say(ai,"title")for ao,an in
ipairs(type(ag)=="table"and ag or{ag})do Z.say(an,nil)end
for an,ao in ipairs(ah)do Z.say("  "..an..
". "..ao,nil)end
local am=tonumber(i and i("Choice: ",4)or"")return(am and ah[am])and am or#ah end;local aj=type(ag)=="table"and table.concat(ag,"\n")or
tostring(ag or"")
local ak,al=pcall(K,{title=ai,message=aj,buttons=ah,style="install"})return ak and al or#ah end
Z.ask=function(ah,ag)local aj=ah..
(ag and(" ["..ag.."]")or"")..": "
local ai=i and i(aj,64)or nil;if ai==nil then return ag end
ai=tostring(ai):gsub("^%s+",""):gsub("%s+$","")if ai==""then return ag end;return ai end
Z.installed=function(ag)local ah=ab()return
(ah and ah.info and ah.info(ag))~=nil end
Z.install=function(ag)local ah=ab()if not(ah and ah.installByName)then return false,
"package manager unavailable"end;return
ah.installByName(ag,{session=q.sessionOf(a)})end
Z.writeFile=function(ag,ah)if not _ then return false,"filesystem unavailable"end;if
_.writeFileAtomic then return _.writeFileAtomic(ag,ah)end;return
_.writeFile(ag,ah)end
Z.startService=function(ag)local ak,ah=pcall(require,"kernel.rc")if not
(ak and ah and ah.start)then return false,"rc unavailable"end
local ai,aj=ah.start(ag)if
not ai and tostring(aj):find("Already running",1,true)then return true end;return ai,aj end
Z.setBootStart=function(ag,ah)if not _ then return false,"filesystem unavailable"end;local ai=
"/etc/rc.d/"..ag..".disabled"if ah then if _.exists(ai)then
return _.remove(ai)end;return true end;if _.exists(ai)then return
true end;return _.writeFile(ai,"1")end
Z.modemCount=function()local ag,ah=0,0
for ai,aj in p.list()do if aj=="modem"then ag=ag+1;local al,ak=pcall(p.proxy,ai)
if
al and ak and ak.isWireless and ak.isWireless()then ah=ah+1 end end end;return ag,ah end
Z.myModemAddress=function()return(p.list("modem")())end
Z.hostname=function()local ag=_G._TOS and _G._TOS.net;if ag and ag.getHostname then return
ag.getHostname()end
if
_ and _.exists("/etc/hostname")then local ah=_.readFile("/etc/hostname")if type(ah)==r then return
(ah:match("^[^\n]*"))end end end
Z.startPairing=function()local ai,ag=pcall(require,"cluster.api")
if not ai or not ag or not
ag.startPairing then return nil,"the Master daemon is not up yet"end;local aj,ah,ak=pcall(ag.startPairing)
if not aj then return nil,tostring(ah)end;return aa.pairingWindow(ah,ak)end
Z.pairWith=function(ag,ah)local aj,ai=pcall(require,"cluster-manager")
if not aj or not ai or not
ai.pair then return false,"cluster-manager library not loadable"end;return ai.pair(ag,ah)end
if(H[1]or""):lower()=="explain"then
E("=== What a cluster is made of ===",d.title)for ah,ag in ipairs(aa.explain())do E(ag,d.fg)end;return end;local ae,af=pcall(aa.run,Z)if not ae then
E("Setup failed: "..tostring(af),d.error)end;n()end
b.intercom=function(H,E)local af,Z=pcall(require,"intercom")
if
not af or type(Z)~="table"or not Z.announce then
E("The Intercom is an add-on and isn't installed on this machine.",d.error)
E("Install it from the Optional Utilities disk:  pkg install intercom",d.dim)
E("(then `service start intercom` so this box will HEAR announcements)",d.dim)return end;local ac=_G._TOS and _G._TOS.fs
local _=(H[1]or""):lower()local aa,ab={},{}
do local ag
for ah=2,#H do local ai=tostring(H[ah])
if ah==ag then elseif ai:sub(1,2)=="--"then
local aj,ak=ai:match("^%-%-([%w%-]+)=?(.*)$")
if aj then
if ak~=""then aa[aj]=ak elseif
(aj=="severity"or aj=="to"or aj=="drive")and H[ah+1]and
tostring(H[ah+1]):sub(1,2)~="--"then
aa[aj]=tostring(H[ah+1])ag=ah+1 else aa[aj]=true end end else ab[#ab+1]=ai end end end
local function ad()local ag,ah=Z.loadCatalog(ac)for aj,ai in ipairs(ah)do
E(string.format("  catalog line %d: %s",ai.line,ai.why),d.warning)end;return ag end
local function ae(ag)
for ai,ah in ipairs(ag.errors or{})do E("  "..ah,d.warning)end;if ag.played then
E(string.format("Playing on the tape (%.1fs).",ag.seconds or 0),d.highlight)end
if ag.sent then
E("Broadcast to the network.",d.highlight)elseif not ag.localOnly then E("Nothing was broadcast.",d.warning)end end
if _==""then local ah,ag=pcall(require,"intercomapp")if ah and ag and ag.open then
ag.open(a)return end;_=w end
if _==w then E("=== Intercom ===",d.title)local ag,ai=Z.findDrive()
if ag then
local al=(
ag.getSize and ag.getSize())or 0;local ak=(ag.isReady and ag.isReady())and"tape loaded"or
"NO TAPE"
E(string.format("  tape drive : %s, %d bytes",ak,al),
ak=="NO TAPE"and d.warning or d.fg)else
E("  tape drive : none ("..tostring(ai)..") — text-only announcements",d.warning)end;local aj=ad()
E("  catalog    : "..#aj.." cue(s) in "..Z.CUES_PATH,d.fg)local ah=Z.loadCfg(ac)
E("  receiving  : ".. (Z.running()and"listening"or
"STOPPED (service start intercom)"),
Z.running()and d.highlight or d.warning)
E(string.format("  popups     : at %s and above, at most one per %ds",ah.popupLevel,ah.popupCooldown),d.fg)
E(string.format("  filter     : ignore anything below %s",ah.minLevel),d.dim)E("",d.dim)
E("  intercom say \"...\" [--severity warn]   speak now, text only",d.dim)
E("  intercom play <cue>                     tape + text",d.dim)
E("  intercom test <cue>                     play it here, tell nobody",d.dim)E("  intercom cues | log | set <k> <v>",d.dim)elseif
_=="cues"or _=="list"then local ag=ad()
if#ag==0 then
E("No cues catalogued yet.",d.warning)
E("Edit "..Z.CUES_PATH.." and describe what is on the tape:",d.dim)
E('  fuel-low  [0001] "Warning: Reactor fuel low." [0005]  warn',d.dim)return end
E(string.format(" %-16s %-7s %-7s %-8s %s","name","start","end","severity","says"),d.title)for ai,ah in ipairs(ag)do
E(string.format(" %-16s %-7d %-7d %-8s %s",ah.name,ah.start,ah.stop,ah.severity,ah.text),d.fg)end elseif _=="say"then
local ah=table.concat(ab," ")
if ah==""then
E('Usage: intercom say "your announcement" [--severity warn] [--to <peer>]',d.dim)
E("Severities: "..table.concat(Z.SEVERITIES," "),d.dim)return end
local ag=type(aa.severity)==r and aa.severity or"info"if not Z.validSeverity(ag)then
E("Unknown severity: "..ag,d.error)
E("Use one of: "..table.concat(Z.SEVERITIES," "),d.dim)return end
E(
"Announcing ("..ag.."): "..ah,d.title)
ae(Z.announce({text=ah,severity=ag,to=type(aa.to)==r and aa.to or nil}))elseif _=="play"or _=="test"then local ah=ab[1]if not ah then
E("Usage: intercom "..
_.." <cue>   (intercom cues to list them)",d.dim)return end
local ag=Z.findCue(ad(),ah)
if not ag then E("No such cue: "..ah,d.error)return end
if _=="test"then
E("Testing cue '"..ag.name.."' — playing locally, sending nothing.",d.title)E("  should say: "..ag.text,d.dim)
E("  tape "..ag.start..
" -> "..ag.stop,d.dim)else
E("Announcing cue '"..ag.name.."' ("..ag.severity..")",d.title)E("  "..ag.text,d.fg)end
ae(Z.announce({cue=ag,localOnly=(_=="test"),driveAddr=type(aa.drive)==r and aa.drive or nil,to=
type(aa.to)==r and aa.to or nil}))elseif _=="log"then local ag=Z.loadSpool(ac)if#ag==0 then
E("Nothing heard yet.",d.dim)return end;local ah=tonumber(ab[1])or 20
for ai=math.max(1,
#ag-ah+1),#ag do local ak=ag[ai]local aj=ak.severity or"info"
E("  "..
Z.formatLine(ak),
(aj=="critical"or aj=="alert")and d.error or(aj=="warn")and d.warning or d.fg)end elseif _=="set"then if not h(E)then return end;local ag,ah=ab[1],ab[2]local ai=Z.loadCfg(ac)
if
not ag then
E("Usage: intercom set <popuplevel|minlevel|cooldown|echotape> <value>",d.dim)
E("  popuplevel <sev>   interrupt with a message box at this and above",d.dim)
E("  minlevel   <sev>   ignore anything quieter than this",d.dim)
E("  cooldown   <secs>  minimum quiet between message boxes",d.dim)
E("  echotape   on|off  also play received cues on this box's tape",d.dim)return end;ag=ag:lower()
if ag=="popuplevel"or ag=="minlevel"then if not
Z.validSeverity(ah)then
E("Severities: "..table.concat(Z.SEVERITIES," "),d.error)return end
ai[
ag=="popuplevel"and"popupLevel"or"minLevel"]=ah elseif ag=="cooldown"then local al=tonumber(ah)if not al or al<0 or al>3600 then
E("cooldown: 0-3600 seconds",d.error)return end;ai.popupCooldown=al elseif
ag=="echotape"then
ai.echoToTape=(ah=="on"or ah=="true"or ah=="1")else E("Unknown setting: "..ag,d.error)return end;local aj,ak=Z.saveCfg(ai,ac)
if aj then E("Saved.",d.highlight)else E("Save failed: "..
tostring(ak),d.error)end else
E("Usage: intercom [status|cues|say|play|test|log|set] ...",d.title)
E("  intercom say \"text\" [--severity <lvl>]  announce text right now",d.dim)
E("  intercom play <cue>                      play a tape cue AND announce it",d.dim)
E("  intercom test <cue>                      play it here only, to check it",d.dim)
E("  intercom cues                            what's catalogued on the tape",d.dim)
E("  intercom log [N]                         what this box has heard",d.dim)
E("  intercom set <key> <value>               receive policy (admin)",d.dim)end end
b.mail=function(H,E)local ab,Z=pcall(require,"mail")
if not ab or type(Z)~="table"or not
Z.send then
E("Mail is an add-on and isn't installed on this machine.",d.error)
E("Install it from the Optional Utilities disk:  pkg install mail",d.dim)
E("(then `service start mail` so this box can RECEIVE mail)",d.dim)return end;if not Z.available()then
E("Mail unavailable (no network hardware?)",d.error)return end;Z.tick()
local aa=a.who or"user"local _=H[1]
if not _ or _=="ui"or _=="tui"then
local ad,ac=pcall(require,"mailapp")if ad and ac and ac.open then ac.open(a)return end end
if not Z.running()then
E("Note: the mail service is stopped — this box won't RECEIVE mail.",d.warning)
E("      Start it with:  service start mail",d.dim)end
if _=="send"then local ae=H[2]if not ae then
E("Usage: mail send <peer|alias|user@peer|*> [subject] [body...]",d.dim)return end
local ag,ah=Z.resolveRecipient(ae,k and k.aliases and
k.aliases.resolve)local ai=H[3]or""local ac;if H[4]then ac=table.concat(H," ",4)elseif i then
ac=i("Body: ",200)end
if not ac then E("Cancelled",d.dim)return end
local af,ad=Z.send({to=ag,user=ah,fromUser=aa,subject=ai,body=ac})
if af then
E("Queued "..tostring(af):sub(1,18)..
(ad and"  (sealed)"or"  (PLAINTEXT bulletin)"),
ad and d.highlight or d.warning)else
E("Send failed: "..tostring(ad),d.error)end elseif _=="read"then local ad=tonumber(H[2])local ae=Z.inboxBox(aa)
local ac=ae and ad and ae:get(ad)if not ac then
E("No message #"..tostring(H[2]),d.error)return end;ae:markRead(ad)
E(string.rep("-",math.min(I,50)),d.dim)
E("From:    "..

(ac.fromUser and(ac.fromUser.." @ ")or"")..tostring(ac.from):sub(1,12),d.fg)
E("Subject: "..
(ac.subject~=""and ac.subject or"(no subject)"),d.title)if not ac.readable then
E("[sealed - no shared secret to open this]",d.warning)end
E(string.rep("-",math.min(I,50)),d.dim)for af in
(tostring(ac.body).."\n"):gmatch("(.-)\n")do E(af,d.fg)end elseif _=="delete"or _=="rm"then
local ac=tonumber(H[2])local ad=Z.inboxBox(aa)if ad and ac and ad:delete(ac)then
E("Deleted #"..ac,d.highlight)else
E("No message #"..tostring(H[2]),d.error)end else
local ac,ae=Z.inbox(aa)if not ac then E(tostring(ae),d.error)return end
if
#ac==0 then E("(inbox empty)",d.dim)else
E("Inbox for "..aa..":",d.title)for ag,af in ipairs(ac)do
E(Z.inboxRow(af,ag,I-1),af.read and d.dim or d.fg)end end;local ad=Z.pending()if ad and ad>0 then
E(ad.." outbound awaiting delivery",d.dim)end
E("Commands: mail send <peer> [subj] [body] | read <n> | delete <n>",d.dim)end end
b.rbmk=function(H,E)local _,Z=pcall(require,"rbmk-cmd")
if
not _ or type(Z)~="table"or not Z.run then
E("The RBMK controller add-on isn't installed on this machine.",d.error)
E("Install it from the Optional Utilities disk:  pkg install rbmk-control",d.dim)
E("Then:  rbmk survey   (identifies the console's real API)",d.dim)return end;local aa,ab=pcall(require,"kernel.screen")
Z.run(H,E,{display=m,event=G,screen=aa and ab or nil})end
b.robot=function(H,E)local aa,Z=pcall(require,"peripheral.robot")if not aa then
E("No robot module",d.error)return end;if not Z.available()then
E("Not a robot",d.error)return end;local _=H[1]
if _=="forward"or _=="fwd"then
local ab,ac=Z.forward()
E(ab and"Moved forward"or tostring(ac),ab and d.highlight or d.error)elseif _=="back"then local ab,ac=Z.back()
E(ab and"Moved back"or tostring(ac),ab and
d.highlight or d.error)elseif _=="up"then local ab,ac=Z.up()
E(ab and"Moved up"or tostring(ac),
ab and d.highlight or d.error)elseif _=="down"then local ab,ac=Z.down()
E(ab and"Moved down"or tostring(ac),ab and
d.highlight or d.error)elseif _=="left"then Z.turnLeft()E("Turned left",d.highlight)elseif
_=="right"then Z.turnRight()E("Turned right",d.highlight)elseif _=="swing"then
local ab,ac=Z.swing(H[2])
E(ab and"Swing!"or tostring(ac),ab and d.highlight or d.error)elseif _=="use"then local ab,ac=Z.use(H[2])
E(ab and"Used!"or tostring(ac),
ab and d.highlight or d.error)elseif _=="detect"then local ab,ac=Z.detect(H[2])
E(
ab and"Block: "..tostring(ac)or"Nothing",d.fg)elseif _=="inv"then local ab=Z.inventory()if ab then
for ad,ac in ipairs(ab)do if ac.count>0 then
E(string.format(" [%2d] %dx %s",ac.slot,ac.count,
ac.name or"?"),d.fg)end end end else
E("Usage: robot <forward|back|up|down|left|right|swing|use|detect|inv>",d.dim)end end
b.inventory=function(H,E)local aa,Z=pcall(require,"peripheral.inventory")if not aa then
E("No inventory module",d.error)return end;if not Z.available()then
E("No inventory controller/transposer",d.error)return end;local ab=H[1]and
(tonumber(H[1])or H[1])or nil
local _=Z.list(ab)
if _ then
E(string.format(" %-4s %-24s %s","Slot","Item","Count"),d.title)
for ad,ac in ipairs(_)do if ac.count>0 then
E(string.format(" %-4d %-24s %d",ac.slot,(ac.name or"?"):sub(1,24),ac.count),d.fg)end end else E("Cannot read inventory",d.error)end end;b.inv=b.inventory
b.component=function(H,E)if not h(E)then return end
if not H[1]then
E("Usage: component <type> [method] [args...]",d.dim)
E("  component list            List all component types",d.dim)
E("  component gpu             Show GPU methods",d.dim)
E("  component gpu getDepth    Call gpu.getDepth()",d.dim)
E("  component reload-caps     Reload the cap configs (see below)",d.dim)return end
if H[1]=="reload-caps"then local ae,ad=pcall(require,"kernel.sandbox")if not ae or not
ad.reloadComponentConfig then
E("Sandbox doesn't support reload-caps",d.error)return end
local af,ag=ad.reloadComponentConfig()local aa,ab=0,0;for ai in pairs(af or{})do aa=aa+1 end
for ai in pairs(ag or{})do ab=ab+1 end
E(string.format("Reloaded: %d extra base, %d extra gated types",aa,ab),d.highlight)local ah,ac=pcall(require,C)
if ah and ac and ac.reloadCapConfig then
local ak,al=ac.reloadCapConfig()local ai,aj=0,0;for am in pairs(ak or{})do ai=ai+1 end;for am,an in pairs(al or{})do for ap in pairs(an)do aj=
aj+1 end;local ao=am end
E(string.format("Reloaded: %d extra package caps, %d denials",ai,aj),d.highlight)if ai>0 or aj>0 then
E("Packages already loaded this boot keep their old caps.",d.dim)end end;return end
if H[1]=="list"then local aa={}for ac,ab in p.list()do if not aa[ab]then aa[ab]=0 end
aa[ab]=aa[ab]+1 end;for ab,ac in pairs(aa)do
E(string.format("  %-20s x%d",ab,ac),d.fg)end;return end;if not J(E)then return end;local Z=H[1]
local _=p.proxy(p.list(Z)()or"")
if not _ then E("No component: "..Z,d.error)return end
if not H[2]then local aa={}
for ac,ab in pairs(_)do
local ad=type(ab)=="table"and getmetatable(ab)
if type(ab)=="function"or
(type(ad)=="table"and ad.__call)then aa[#aa+1]=ac end end;table.sort(aa)
for ac,ab in ipairs(aa)do E("  "..ab.."()",d.fg)end else
if Z=="eeprom"and
(H[2]=="set"or H[2]=="setData"or H[2]=="makeReadonly")then
E("Denied: use the 'flash' command to write EEPROM",d.error)return end;local ac=_[H[2]]if not ac then
E("Unknown method: "..H[2],d.error)return end;local aa={}
for ad=3,#H do local ae=H[ad]
if ae=="true"then
aa[#aa+1]=true elseif ae=="false"then aa[#aa+1]=false elseif tonumber(ae)then aa[#aa+1]=tonumber(ae)else aa[
#aa+1]=ae end end
local ab=table.pack(pcall(ac,table.unpack(aa)))
if ab[1]then
for ad=2,ab.n do E("  "..tostring(ab[ad]),d.fg)end else E("Error: "..tostring(ab[2]),d.error)end end end
b.internet=function(H,E)local aa,_=pcall(require,"kernel.internet")if not aa or not _ then
E("internet module unavailable",d.error)return end
local Z=(H[1]or w):lower()
if Z==w then local f=_.status()
if not f.present then
E("No internet card installed.",d.warning)
E("An Internet Card goes in a card slot; the machine needs no",d.dim)
E("other change. TOS uses it for 'pkg fetch' and nothing else",d.dim)
E("unless a package asks for the 'internet' capability.",d.dim)return end
E("Internet card "..tostring(f.addr),d.title)
E("  HTTP:    "..
(f.http and"available"or"DISABLED by the server"),f.http and d.highlight or d.warning)
E("  TCP:     "..
(f.tcp and"available"or"disabled by the server"),f.tcp and d.fg or d.dim)
E("  Machine: "..
(f.enabled and"enabled"or"DISABLED (config: internet)"),f.enabled and d.highlight or d.warning)
if f.reason then E("  -> "..f.reason,d.warning)end
if not f.http and f.present then E("",d.dim)
E("HTTP is switched off in the SERVER's OpenComputers config,",d.dim)
E("not in TOS. Only the server owner can change it.",d.dim)end elseif Z=="on"or Z=="off"then if not h(E)then return end
local ac,ab=pcall(require,"kernel.config")
if not ac then E("config unavailable",d.error)return end;ab.set("internet",Z=="on")
if ab.save then pcall(ab.save)end
E("Internet access ".. (Z=="on"and"enabled"or"disabled")..
" on this machine.",d.highlight)elseif Z=="get"then
if not H[2]then E("Usage: internet get <url>",d.dim)return end;local ab,ae,ac=_.get(H[2])
if not ab then E(tostring(ae),d.error)return end
E(string.format("%d bytes%s",#ab,(ac and ac.status)and("  (HTTP "..
tostring(ac.status)..")")or""),d.dim)local ad=0
for af in ab:gmatch("([^\n]*)\n?")do
if ad>=20 then E("... (truncated)",d.dim)break end;E(af,d.fg)ad=ad+1 end else
E("Usage: internet [status|get <url>|on|off]",d.dim)end end
b.compat=function(H,E)local Z,_=pcall(require,"compat")if not Z then
E("Compat layer not loaded",d.error)return end;local aa=_.list()
E(" OpenOS Compatibility Layer",d.title)
E(string.format(" %-16s %s","Module",A),d.dim)for ac,ab in ipairs(aa)do
E(string.format(" %-16s %s",ab.name,ab.loaded and"loaded"or"not loaded"),
ab.loaded and d.highlight or d.dim)end end
b.disk=function(H,E)local Z=H[1]
if not Z or Z=="list"then
local _=e.mounts and e.mounts()or nil
if _ and type(_)=="table"and#_>0 then local aa={}for ac,ab in ipairs(_)do if
ab.mountPoint~="/"then aa[#aa+1]=ab end end
if#
aa==0 then E(v,d.dim)else
E(string.format(" %-16s %-10s %s","Mount","Label",A),d.title)E(string.rep("-",42),d.dim)
for ac,ab in ipairs(aa)do
local ad=ab.mountPoint;local ae=q.classifyDisk(e,ad)
local af=(ab.label or""):sub(1,10)
E(string.format(" %-16s %-10s %s",ad:sub(1,16),af,ae.desc),
ae.kind~="data"and d.highlight or d.fg)end end elseif e.exists("/mnt")then local aa=e.list("/mnt")
if aa and#aa==0 then E(v,d.dim)elseif aa then
E(string.format(" %-16s %-8s %s","Mount","Type",A),d.title)E(string.rep("-",42),d.dim)
for ac,ab in ipairs(aa)do local ad="/mnt/"..
ab:gsub("/$","")local ae=q.classifyDisk(e,ad)
E(string.format(" %-16s %-8s %s",ad:sub(1,16),"disk",ae.desc),
ae.kind~="data"and d.highlight or d.fg)end else E(v,d.dim)end else E(v,d.dim)end
do local aa=0;for ab in p.list("drive",true)do aa=aa+1 end
if aa>0 then E("",d.dim)
E(aa..
" unmanaged (raw) drive(s) attached — not filesystems, so",d.warning)
E("they cannot appear above until formatted and mounted.",d.dim)
E("  drive list          see them, with address and capacity",d.dim)
E("  drive format <addr> make one a TBFS filesystem",d.dim)end end
E("disk info <mnt> for details  ·  df for space  ·  jbod to pool disks",d.dim)elseif Z=="info"then if not H[2]then
E("Usage: disk info <mount-point>",d.dim)return end;local _=e.normalize(H[2])if not
e.exists(_)or not e.isDirectory(_)then
E("Not a valid mount point: ".._,d.error)return end
local ab=e.spaceTotal(_)local ac=e.spaceFree(_)E(" Mount: ".._,d.title)if
ab and ab>0 then
E(string.format(" Space: %dK free / %dK total",math.floor(ac/1024),math.floor(ab/1024)),d.fg)end
local aa=q.classifyDisk(e,_)
E(" Contains: "..aa.desc,aa.kind~="data"and d.highlight or d.dim)if aa.hint then E("   -> "..aa.hint,d.dim)end elseif Z==
"install"then
E("'disk install' folded into the package manager:",d.warning)
E("  pkg install              scan all mounts, confirm per package",d.dim)
E("  pkg install <mnt>        install one specific directory",d.dim)elseif Z=="export"then
E("'disk export' was removed with the legacy module system.",d.warning)
E("To build an install disk for add-ons, use the Optional Utilities",d.dim)
E("builder: TOS-Extras/build/build-disk.lua.",d.dim)
E("For a full TOS image, use 'deploy <mount>' instead.",d.dim)elseif Z=="eject"then if not H[2]then
E("Usage: disk eject <mount-point>",d.dim)return end;local _=e.normalize(H[2])
local aa,ab=e.unmount(_)if aa then E("Ejected: ".._,d.highlight)else
E("Eject failed: "..tostring(ab),d.error)end else
E("Usage: disk [list|info <mnt>|eject <mnt>]",d.dim)
E("  Removable disks + what's on them.  Install packages: 'pkg'.",d.dim)
E("  Pool several disks into one: 'jbod'.   Free space per mount: 'df'.",d.dim)end end
b.drive=function(H,E)local Z=H[1]local function ac()local af,ag=pcall(require,"blockfs")
return af and ag or nil end
local function aa(af)local ag={}for ak in p.list("drive",true)do
if not af or ak:sub(1,
#af)==af then ag[#ag+1]=ak end end;table.sort(ag)
if#ag==0 then return nil,

"no unmanaged drive found".. (af and(" for '"..af.."'")or"")end;if af and#ag>1 then return nil,
"ambiguous prefix '"..af.."' ("..#ag.." drives)"end
local ah=ag[1]local aj,ai=pcall(p.proxy,ah)
if not aj or not ai then return nil,"cannot proxy drive"end;return ai,ah end
if not Z or Z=="list"then
E("Unmanaged drives (raw block devices):",d.title)local af,ag=0,ac()
for ah in p.list("drive",true)do local aj,ai=pcall(p.proxy,ah)
if aj and ai then
af=af+1
local al=(ai.getSectorSize and ai.getSectorSize())or 0
local am=(ai.getCapacity and ai.getCapacity())or 0
local an=(ai.getPlatterCount and ai.getPlatterCount())or 1;local ak="unformatted"
if ag then local ao=ag.stats(ai)if ao then
ak=string.format('TBFS "%s"  %s used  %d%% frag',ao.label,j(
ao.usedBlocks*ao.sectorSize),math.floor(ao.fragmentation*100+0.5))end end
E(string.format("  %s  %s  %dB/sector  %d platter(s)  %s",ah:sub(1,8).."...",j(am),al,an,ak),d.fg)end end
if af==0 then E("  (none attached)",d.dim)
E("  Managed disks appear under 'disk' / 'df'; this is for raw drives.",d.dim)elseif not ag then
E("  Install 'blockfs' to format/mount them:  pkg install blockfs",d.dim)else
E("  format | mount | check [--repair] | defrag [--if-over N] | read | write",d.dim)end;return end
if Z=="info"then local af,ag=aa(H[2])
if not af then E(tostring(ag),d.error)return end;E(u..ag:sub(1,8).."...",d.title)
E(string.format("  capacity   %s",j((
af.getCapacity and af.getCapacity())or 0)),d.fg)
E(string.format("  sector     %d bytes",
(af.getSectorSize and af.getSectorSize())or 0),d.fg)
E(string.format("  platters   %d",
(af.getPlatterCount and af.getPlatterCount())or 1),d.fg)local ah=ac()
if ah then local ai=ah.stats(af)
if ai then
E("  TBFS volume:",d.highlight)
E(string.format('    label "%s"   %s / %s used   %d file(s), %d dir(s)',ai.label,j(ai.usedBlocks*ai.sectorSize),j(
ai.dataBlocks*ai.sectorSize),ai.files,ai.dirs),d.fg)
E(string.format("    fragmentation %d%%   %s",math.floor(ai.fragmentation*100+0.5),
ai.clean and"clean"or"DIRTY (mounted or unclean)"),d.fg)else
E("  Not a TBFS volume. It holds "..
(F(af)or"something unreadable")..".",d.dim)end else
E("  It holds ".. (F(af)or"something unreadable")..".",d.dim)
E("  (install 'blockfs' to format or mount it)",d.dim)end;return end;local _=ac()if not _ then
E("The 'blockfs' package is required:  pkg install blockfs",d.error)return end
local function ab(af)for ah,ag in ipairs(
e.mounts and e.mounts()or{})do
if ag.address==af then return ag.mountPoint,ag end end;return nil end
local function ae(af)local ag,ah={},false
for am,al in ipairs(e.mounts and e.mounts()or{})do
if
al.mountPoint==af then if al.openFiles==nil then ah=true elseif al.openFiles>0 then
ag[#ag+1]=string.format("%d open file handle(s)",al.openFiles)end end end
local ai=(af:sub(-1)=="/")and af or(af.."/")
local aj,ak=pcall(function()return o and o.list and o.list()or{}end)
for am,al in ipairs(aj and ak or{})do local an=al.cwd
if type(an)==r and(an==af or
an:sub(1,#ai)==ai)then
ag[#ag+1]=string.format("%s (pid %s) is in %s",tostring(
al.name or"?"),tostring(al.pid or"?"),an)end end;return ag,ah end
local function ad(af,ai,ag,ah)local aj=ab(af)if not aj then return ah()end;local ak,ao=ae(aj)
if#ak>0 or ao then
local aw=
(#ak>0)and(
"\n  "..table.concat(ak,"\n  "))or"\n  (the driver cannot say what is open)"
local av=string.format("'%s' has to take %s out of the mount table while it works.\n"..
"Something is using it right now:%s\n\n"..
"Continuing will pull the volume out from under it. It is\n".."remounted at %s afterwards.",ag,aj,aw,aj)local au
if l then
au=l(av,{title="Unmount "..aj.."?",severity=B,yes="Unmount and continue",no=y})else E(av,d.warning)
local ax=i and
i("Unmount "..aj.." and continue? [y/N]: ",4)or"n"au=(ax or""):lower()=="y"end;if not au then
E("Cancelled; the drive is still mounted.",d.dim)return false end else
E(string.format("Nothing is using %s — unmounting for the %s.",aj,ag),d.dim)end;local al=q.sessionOf(a)local ap,aq=e.unmount(aj,al)if ap==false then
E("Could not unmount "..aj..
": "..tostring(aq or"?"),d.error)return false end;local ar,am=pcall(ah)local as=function()
return math.floor(
g.uptime and g.uptime()or 0)end
local an,at=_.mount(ai,{now=as})
if an then local au,av=e.mount(aj,an,al)
if au==false then
E("Remount FAILED at "..aj..
": "..tostring(av or"?"),d.error)
E("  Mount it by hand:  drive mount "..af:sub(1,8).." "..aj,d.dim)else E("Remounted at "..aj..".",d.dim)pcall(n)end else
E("Remount FAILED ("..tostring(at).."); the drive is detached.",d.error)
E("  Mount it by hand:  drive mount "..af:sub(1,8).." "..aj,d.dim)end;if not ar then error(am,0)end;return am end
if Z=="unmount"or Z=="umount"then if not h(E)then return end;local ah,af=aa(H[2])if not
ah then E(tostring(af),d.error)return end
local ag=ab(af)if not ag then
E(u..af:sub(1,8).."... is not mounted.",d.dim)return end;local ai=q.sessionOf(a)
local aj,ak=e.unmount(ag,ai)if aj==false then
E(tostring(ak or"unmount failed"),d.error)return end
E("Unmounted "..ag.." (volume marked clean).",d.highlight)pcall(n)return end
if Z=="format"then if not h(E)then return end;local ag,af=aa(H[2])if not ag then
E(tostring(af),d.error)return end
local aj=H[3]or("disk"..af:sub(1,4))local ah=F(ag,_)local ai
if l then
ai=l("Format drive "..
af:sub(1,8)..
"... as TBFS?"..
"\n\n".. (ah and
("It holds "..ah..".\n")or"")..

"Every file on it is destroyed. There is no undo and no\n".."recovery tool in TOS that can bring it back.",{title="Format drive",severity=B,yes="Format",no=y})else if ah then
E(u..af:sub(1,8).."... holds "..ah..".",d.warning)end
local ak=
i and i("FORMAT "..
af:sub(1,8).."... as TBFS? destroys all data [y/N]: ",4)or"n"ai=(ak or""):lower()=="y"end;if not ai then E("Cancelled.",d.dim)return end
ad(af,ag,"format",function()
local ak,al=_.format(ag,{label=aj,now=function()
return math.floor(
g.uptime and g.uptime()or 0)end})if ak then
E('Formatted as TBFS "'..aj..'".',d.highlight)else
E("Format failed: "..tostring(al),d.error)end end)if not ab(af)then
E("Mount it with: drive mount "..af:sub(1,8),d.dim)end;return end
if Z=="mount"then if not h(E)then return end;local ah,ai=aa(H[2])if not ah then
E(tostring(ai),d.error)return end
local ak=function()return
math.floor(g.uptime and g.uptime()or 0)end;local ag,al=_.mount(ah,{now=ak})if not ag then
E("Mount failed: "..tostring(al),d.error)return end
local am=q.safeMountName(ag.getLabel and ag.getLabel(),ai)local af=H[3]or("/mnt/"..am)if af:sub(1,1)~="/"then
af="/mnt/"..af end;if not e.exists("/mnt")then
pcall(e.makeDirectory,"/mnt")end;if not e.exists(af)then
pcall(e.makeDirectory,af)end;local an=q.sessionOf(a)
local ao,ap=e.mount(af,ag,an)if ao==false then
E(tostring(ap or"mount failed"),d.error)return end
E("Mounted TBFS at "..af,d.highlight)local aj=_.stats(ah)
if aj and aj.fragmentation>0.30 then
E(string.format("  Note: %d%% fragmented — 'drive defrag %s' to compact.",math.floor(
aj.fragmentation*100+0.5),ai:sub(1,8)),d.warning)end;pcall(n)return end
if Z=="check"or Z=="fsck"then if not h(E)then return end;local ag,ah=aa(H[2])if not ag then
E(tostring(ah),d.error)return end
local ai=H[3]=="--repair"or H[3]=="-r"local af
if ai then
local ak=ad(ah,ag,"check --repair",function()af=_.check(ag,{repair=true,yield=s})end)if ak==false then return end else
af=_.check(ag,{repair=false,yield=s})end
if not af then E("Not a TBFS volume.",d.error)return end;local aj=ab(ah)
if aj and not ai then local ak={}
for am,al in ipairs(af.problems)do if
al~="volume was not cleanly unmounted"then ak[#ak+1]=al end end;af.problems=ak;af.ok=(#ak==0)
E("(mounted at "..
aj..": the dirty flag is expected and not counted)",d.dim)end
if af.ok then E("TBFS clean: no problems.",d.highlight)else
E((af.repaired and
"Repaired. Findings:"or"Problems found:"),
af.repaired and d.highlight or d.warning)
for al,ak in ipairs(af.problems)do E("  - "..ak,d.dim)end;if not ai and not af.ok then
E("  Run 'drive check "..ah:sub(1,8).." --repair' to fix.",d.dim)end end;return end
if Z=="defrag"then if not h(E)then return end;local af,ah=aa(H[2])if not af then
E(tostring(ah),d.error)return end;local ag=nil
for ai=3,#H do if
H[ai]=="--if-over"and H[ai+1]then ag=tonumber(H[ai+1])end end
if ag then local ai=_.stats(af)
if
ai and(ai.fragmentation*100)<ag then
E(string.format("Fragmentation %d%% below %d%% — skipped.",math.floor(ai.fragmentation*100+0.5),ag),d.dim)return end end;E("Defragmenting...",d.title)
ad(ah,af,"defrag",function()
local ai,aj=_.defrag(af,{now=function()return math.floor(g.uptime and
g.uptime()or 0)end})if not ai then
E("Defrag failed: "..tostring(aj),d.error)return end
E(string.format("Defragmented %d block(s): %d%% -> %d%% fragmented.",ai.moved,math.floor(
ai.before*100+0.5),math.floor(ai.after*100+0.5)),d.highlight)end)return end
if Z=="read"then if not h(E)then return end;local ai,aj=aa(H[2])if not ai then
E(tostring(aj),d.error)return end;local af=tonumber(H[3])if not af then
E("Usage: drive read <addr> <sector>",d.dim)return end
local ak,ag=pcall(ai.readSector,af+1)if not ak then
E("Read failed: "..tostring(ag),d.error)return end;local ah={}for al=1,math.min(64,# (ag or""))
do
ah[#ah+1]=string.format("%02X",(ag):byte(al))end
E("Sector "..af.." (first 64 bytes):",d.title)E("  "..table.concat(ah," "),d.dim)
return end
if Z=="write"then if not h(E)then return end
E("'drive write' is intentionally not exposed as a one-liner (a stray",d.warning)
E("sector write corrupts a filesystem). Use the blockfs API from 'lua'",d.dim)
E("for deliberate raw writes. Format/mount/defrag cover normal use.",d.dim)return end
E("Usage: drive [list | info <addr> | format <addr> [label] | mount <addr> [path]",d.dim)
E("             | unmount <addr> | check <addr> [--repair] | defrag <addr> [--if-over N]",d.dim)
E("             | read <addr> <sec>]   (format/repair/defrag need the drive unmounted)",d.dim)end
b.tape=function(H,E)local _,Z=pcall(require,C)
if _ and Z and Z.getCommand then
local aa=Z.getCommand("tape")if aa then aa(H,E)return end
if Z.info and Z.info("tape")then
E("The tape package is installed but not enabled.",d.warning)E("Enable it with:  pkg enable tape",d.highlight)
return end end;E("Tape Storage",d.title)E("",d.fg)
E("The 'tape' package isn't installed. To use Computronics tapes:",d.fg)E("",d.fg)
E(" Install from the Optional Utilities disk:",d.highlight)
E("    pkg install              (with the disk inserted)",d.dim)E("  or, if it's in a configured repo:",d.dim)
E("    pkg install tape",d.dim)E("",d.fg)
E(" Build your own: a /usr/modules/<name>/init.lua returning",d.dim)
E("   { commands = { tape = function(args, o) ... end } }",d.dim)
E(" plus a package.lua manifest (kind=\"command\"). See the TOS Manual.",d.dim)end
b.deploy=function(H,E)if not J(E)then return end
if H[1]=="drive"then
local ay,ah=pcall(require,"blockfs")
if not ay or not ah then
E("Cannot deploy to a raw drive: TOS doesn't have the 'blockfs' package.",d.error)
E("blockfs is the filesystem that makes a raw drive usable + bootable.",d.dim)E("Install it first, then retry:",d.dim)
E("    pkg install blockfs",d.highlight)return end
local au=e.exists("/usr/lib/blockfs.lua")and e.readFile("/usr/lib/blockfs.lua")
if not au then
E("blockfs is loadable but /usr/lib/blockfs.lua is missing — reinstall it:",d.error)E("    pkg install blockfs",d.highlight)return end;local ai={}
for aF in p.list("drive",true)do if
not H[2]or aF:sub(1,#H[2])==H[2]then ai[#ai+1]=aF end end;table.sort(ai)if#ai==0 then
E("No unmanaged drive"..
(H[2]and
(" matching '"..H[2].."'")or"").." found.",d.error)return end;if H[2]and#ai>1 then
E(
"Ambiguous prefix '"..H[2].."' ("..#ai.." drives).",d.error)return end;local aj=ai[1]
local az,ak=pcall(p.proxy,aj)if not az or not ak then
E("Cannot proxy drive "..aj:sub(1,8),d.error)return end;local aq=ah.bootBlob(au)
local ar=#aq+4096;local am={}local aA,av=pcall(require,"system_manifest")if aA and
type(av)=="table"then
for aG,aF in ipairs(av)do if
type(aF)=="table"and type(aF.path)==r then am[#am+1]=aF.path end end end;if#am==0 then
E("system_manifest not loadable — aborting.",d.error)return end;local as=nil
if ah.plan and ah.blocksFor then
local aF,aJ=ah.plan(ak,{bootBytes=ar})if not aF then
E("This drive cannot hold TOS: "..tostring(aJ)..". Nothing was erased.",d.error)return end
local function aK(aL)local aM,aN=0,1
local aP,aQ={["/"]=0},{}
local function aR(aS,aT)aP[aS]=(aP[aS]or 0)+5+#aT end
local function aO(aS)local aT=aS:match("^(.*)/[^/]+$")return
(aT==nil or aT=="")and"/"or aT end
for aT,aS in ipairs(am)do local aV,aW=pcall(e.size,aS)
aM=aM+ah.blocksFor(
(aV and tonumber(aW))or 0,aL)aN=aN+1;aR(aO(aS),aS:match("([^/]+)$"))
local aU=aO(aS)while aU~="/"and not aQ[aU]do aQ[aU]=true;aN=aN+1
aR(aO(aU),aU:match("([^/]+)$"))aU=aO(aU)end end
for aT,aS in pairs(aP)do aM=aM+ah.blocksFor(aS,aL)end;return aM,aN end;local aH,aG=aK(aF.ss)
if aG>aF.inodeCount then local aM=math.ceil(aG*1.25)
as=math.max(512,math.floor(
aF.ss*aF.totalBlocks/aM))local aL=ah.plan(ak,{bootBytes=ar,inodeRatio=as})
if not aL or
aL.inodeCount<aG then
E(string.format("TOS needs %d inodes and this drive cannot hold that many. ".."Nothing was erased.",aG),d.error)return end
E(string.format("Sizing the inode table for this install: %d inodes (the default ".."would give %d, and TOS needs %d).",aL.inodeCount,aF.inodeCount,aG),d.dim)aF=aL end
if aH>aF.dataBlocks then
E(string.format("TOS will not fit on this drive: it needs %s, and the drive holds "..
"%s once the boot region and metadata are laid out.  [E-306 ERR_DRIVE_TOO_SMALL]",j(
aH*aF.ss),j(aF.dataBlocks*aF.ss)),d.error)
E("Nothing was erased. Use a larger drive, or a managed disk: deploy <mount-point>",d.dim)return end;local aI=(aF.dataBlocks-aH)*aF.ss
E(string.format("Fits: %s of %s, leaving %s spare; %d of %d inodes.",j(
aH*aF.ss),j(aF.dataBlocks*aF.ss),j(aI),aG,aF.inodeCount),d.dim)if aI<64*1024 then
E("Under 64 KB will be free after the install — logs, trash and swap fill that fast.",d.warning)end else
E("(This blockfs cannot check capacity before erasing — 'pkg upgrade blockfs' adds it.)",d.warning)end;local at;local an=F(ak,ah)
if l then
at=l("Install TOS onto raw drive "..
aj:sub(1,8)..
"...?".."\n\n"..
(an and
("It holds "..an..".\n")or"")..
"The drive is erased and reformatted as bootable TBFS.\n".."Anything on it now is gone.",{title="Erase and install",severity=B,yes="Erase",no=y})else if an then
E(u..aj:sub(1,8).."... holds "..an..".",d.warning)end
local aF=
i and i("Install TOS onto raw drive "..
aj:sub(1,8).."...? ERASES it [y/N]: ",4)or"n"at=(aF or""):lower()=="y"end;if not at then E("Cancelled.",d.dim)return end;local aw=function()
return math.floor((g.uptime and
g.uptime())or 0)end
E("Formatting "..
aj:sub(1,8).."... as bootable TBFS...",d.title)
local aB,aC=ah.format(ak,{label="tos",bootBytes=ar,now=aw,inodeRatio=as})if not aB then
E("Format failed: "..tostring(aC).." (drive too small?)",d.error)return end
local al,aD=ah.mount(ak,{now=aw})if not al then
E("Mount failed: "..tostring(aD),d.error)return end;local ao,ap=0,0
for aG,aF in ipairs(am)do s()
local aH=e.open(aF,"r")
if aH then local aJ=aF:match("^(.*)/[^/]+$")
if aJ and aJ~=""then local aL=""for aM in
aJ:gmatch("[^/]+")do aL=aL.."/"..aM
if not al.exists(aL)then al.makeDirectory(aL)end end end;local aI=al.open(aF,"w")local aK=aI~=nil
while aK do local aL=aH:read(4096)
if not aL then break end;aK=al.write(aI,aL)and true or false end;pcall(aH.close,aH)if aI then al.close(aI)end;if aK then ao=ao+1 else
ap=ap+1;E("  FAIL "..aF,d.error)end end end;local ax,aE=ah.writeBoot(ak,aq)al.unmount()E("",d.fg)
if
ax and ap==0 then
E(string.format("TBFS install written: %d files + boot blob (%s).",ao,j(#aq)),d.highlight)
E("The TOS BIOS boots TBFS drives directly. If this box runs an older",d.dim)
E("EEPROM, reflash first: 'flash /bios.lua'.",d.dim)
E("The disk also mounts like any volume: 'drive mount "..aj:sub(1,8).."'.",d.dim)else
E(string.format("Wrote %d files, %d failed; boot blob: %s.",ao,ap,ax and"ok"or
("FAILED ("..tostring(aE)..")")),d.error)end;return end;local Z=H[1]
if not Z then
E("Usage: deploy <mount-point>   |   deploy drive <addr>  (raw disk, needs blockfs)",d.dim)
E("  Creates a TOS install disk on a floppy or drive.",d.dim)E("  e.g. deploy /mnt/floppy",d.dim)
E("  Insert the disk on another OpenOS computer and run:",d.dim)E("    # /mnt/<disk>/install.lua",d.dim)return end;Z=e.normalize(Z)
if#Z>1 and Z:sub(-1)=="/"then Z=Z:sub(1,-2)end
local ae={"/","/tos","/etc","/var","/usr","/home","/root","/public"}
for ai,ah in ipairs(ae)do
if Z==ah or Z:sub(1,#ah+1)==ah.."/"then
E(
"Refusing to deploy onto '"..Z.."' (would overwrite system).",d.error)
E("Deploy only to an external mount such as /mnt/floppy.",d.dim)return end end;if not e.exists(Z)or not e.isDirectory(Z)then
E(
"Target does not exist or is not a directory: "..Z,d.error)return end
E(
"Creating TOS install disk on "..Z.." ...",d.title)local ac=e.spaceTotal(Z)local af=e.spaceFree(Z)if ac and ac>0 then
E(string.format(" Target disk: %dK total, %dK free",math.floor(
ac/1024),math.floor(af/1024)),d.dim)end
local ag={"/tos/","/tos/kernel/","/tos/kernel/net/","/tos/shell/","/tos/compat/","/tos/peripheral/"}for ai,ah in ipairs(ag)do e.makeDirectory(Z..ah)end;local ab={}
do
local ai,ah=pcall(require,"system_manifest")
if ai and type(ah)=="table"then for ak,aj in ipairs(ah)do
if type(aj)=="table"and
type(aj.path)==r then ab[#ab+1]=aj.path end end end
if#ab==0 then
E("  WARN: system_manifest not loadable, using minimal file list",d.warning)
ab={"/init.lua","/tos/kernel/init.lua","/tos/kernel/hal.lua","/tos/kernel/event.lua","/tos/kernel/process.lua","/tos/kernel/fs.lua","/tos/kernel/display.lua","/tos/kernel/log.lua","/tos/kernel/serialize.lua","/tos/shell/init.lua"}end end;local _,aa,ad=0,0,0
for ai,ah in ipairs(ab)do
if e.exists(ah)then local aj,ak=e.copy(ah,Z..ah)if aj then _=_+1 else
E("  FAIL "..ah..
": "..tostring(ak),d.error)aa=aa+1 end else ad=ad+1 end end
if e.exists(x)then if e.copy(x,Z..x)then _=_+1 else aa=aa+1 end end
if e.exists(t)then
do local ah,ai=e.copy(t,Z..t)
if ah then _=_+1
E("  Copied install.lua (automated installer)",d.highlight)else
E("  FAIL writing install.lua: "..tostring(ai),d.error)aa=aa+1 end end else
E("  WARNING: /install.lua not found on boot drive",d.error)
E("  The install disk will not have an automated installer.",d.dim)end;E("",d.fg)
if aa==0 then
E("Install disk created: ".._.." files",d.highlight)E("",d.fg)
E("On the target machine (OpenOS), run:",d.dim)E("  # "..Z..t,d.fg)
E("Or insert the disk and run: /mnt/<disk>/install.lua",d.dim)else
E(_.." files copied, "..aa.." failed",d.error)end end
b.chat=function(H,E)if not k then E(z,d.error)return end
local _,Z=pcall(require,"shell.panels.chatapp")if not _ then
E("Chat unavailable: "..tostring(Z),d.error)return end;Z.open(a)end
local function L(E)
local H=_G._TOS and _G._TOS.net and _G._TOS.net.aliases;if type(E)==r and H and H.resolve then local Z=H.resolve(E)
if Z then return Z end end;return E end
b.rsh=function(H,E)if not h(E)then return end;if not H[1]or not H[2]then
E("Usage: rsh <peer> <lua>   e.g. rsh two print(1+2)",d.dim)return end
if not k then E(z,d.error)return end;local aa,ab=pcall(require,"kernel.net.remote")if not aa then
E("Remote module unavailable",d.error)return end;local Z=L(H[1])
local ac=table.concat(H," ",2)
E("Executing on "..Z:sub(1,8).."...",d.dim)local _,ad=ab.execute(Z,ac)if _ then E(_,d.fg)else
E("Error: "..tostring(ad),d.error)end end
b.scp=function(H,E)if not h(E)then return end
if not H[1]or not H[2]then
E("Usage: scp <peer>:<remote_path> <local_path>",d.dim)
E("  Copies a file from a TRUSTED peer's /public.",d.dim)return end;if not k then E(z,d.error)return end
local aa,ab=pcall(require,"kernel.net.transfer")
if not aa then E("Transfer module unavailable",d.error)return end;local Z,_=H[1]:match("^([^:]+):(.+)$")
if Z then local ac=L(Z)local ad=N(H[2])
E(
"Downloading ".._..
" from "..Z..
(ac~=Z and(" ("..ac:sub(1,8)..")")or"").."...",d.dim)local ae,af=ab.request(ac,_,ad)if ae then n()
E("Downloaded: ".._.." -> "..ad,d.highlight)else
E("Transfer failed: "..tostring(af),d.error)end else
E("Usage: scp <peer>:<remote_path> <local_path>",d.dim)end end
b.screen=function(H,E)local _,Z=pcall(require,"kernel.screen")if not _ then
E("Screen module unavailable",d.error)return end
if H[1]=="res"then
local ab=m.getGpu and m.getGpu()local ad,ae=m.getSize()local ag,ah=ad,ae
if ab then
local ao,an,ap=pcall(ab.maxResolution)if ao and an then ag,ah=an,ap end end;local aa=g.getConfig and g.getConfig()local ai=H[2]
if not ai then
E("=== Screen Resolution ===",d.title)
E(string.format("Current : %dx%d",ad or 0,ae or 0),d.fg)
E(string.format("Maximum : %dx%d",ag or 0,ah or 0),d.dim)
if ab and ab.getScreen then local ao,an=pcall(ab.getScreen)
if ao and type(an)==r then
local aq,ap,ar=pcall(require("component").invoke,an,"getAspectRatio")if aq and ap then
E(string.format("Blocks  : %dx%d (physical)",ap,ar),d.dim)end end end
E("Policy  : ".. ((aa and aa.get and aa.get("screenRes"))or
"auto"),d.fg)
E("Set: screen res <auto|max|WxH>   (e.g. screen res 80x25)",d.dim)return end;if not h(E)then return end;local ac=tostring(ai):lower()
if

ac~="auto"and ac~="max"and not ac:match("^%d+%s*[x×]%s*%d+$")then E("Usage: screen res <auto|max|WxH>",d.error)return end;if aa and aa.set then aa.set("screenRes",ac)
if aa.save then aa.save()end end
Z.setPolicy(Z.specFromConfig(aa))local ak,al,aj=Z.fitDisplay(a.displayIdx)
local am,af=pcall(require,"shell.panels.state")
if am and af and af.recomputeLayout then af.recomputeLayout(a)end;if c.drawAll then pcall(c.drawAll)end
E(string.format("Resolution -> %dx%d (policy '%s')",
ak or ad or 0,al or ae or 0,ac),d.highlight)if aj then E(aj,d.warning)end
E("Applied now and saved for next boot.",d.dim)return end
if H[1]=="list"or not H[1]then local aa=Z.list()if#aa==0 then
E("No displays",d.dim)return end
for ac,ab in ipairs(aa)do
local ad=ab.active and" * "or"   "
E(string.format("%s%d: %s (%dx%d %d-bit)",ad,ab.index,ab.label,ab.w,ab.h,ab.depth),d.fg)end elseif H[1]=="next"then Z.next()
E("Switched to: "..Z.active().label,d.highlight)elseif tonumber(H[1])then
if Z.setActive(tonumber(H[1]))then
E("Switched to screen "..H[1],d.highlight)else E("Invalid screen index",d.error)end else
E("Usage: screen [list|next|<index>|res [auto|max|WxH]]",d.dim)end end
local function O(E)
return
function(Z,H)local aa,_=pcall(require,"shell.ext")
if aa and _[E]then
_[E](Z,{K=g,E=G,P=o,F=e,D=m,U=M,o=H,st=f,computer=D,cwd=a.cwd})else if E=="logout"then G.push("tos_logout",a.displayIdx)else
H("Extension unavailable (low RAM?)",d.error)end end end end;for H,E in
ipairs({"net","ping","hostname","config","battery","audio"})do b[E]=O(E)end end