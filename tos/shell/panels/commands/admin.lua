
local ad,U,ae,O,P,V,W,S,Q,X,af,ag,ah,ai,Y,R,aj,Z,ak,_,al,am,aa,T,ab,ac,an,ao,ap,N,L,aq="  %-20s %s -> %s"," %-16s %s","(--dry-run: nothing was changed)","--allow-unsigned","--allow-unverified","--dry-run","--dryrun","--force","Aborted.","Cancel","Cannot read: ","Error: ","From repos nobody configured: ","Mount failed","No user system","Refused: ","computer","danger","disabled","filesystem","floppy","install","kernel.log","kernel.pkgsign","number","remove","repair","setTier unavailable","shell.panels.tabs","status","string","version"local M=require(aj)local K=require("component")
local J=require("shell.panels.helpers")
return
function(b,a,c)local h,G,t,e,j,g=a.K,a.E,a.P,a.F,a.D,a.U;local H,m,n=a.SC,a.NM,a.st;local d=a.T;local I=a.tier
local l,k=a.W,a.H;local u=c.rp;local y=c.openViewTab;local C=c.openEditTab;local D=c.refreshBrowser
local ar=c.canRead;local as=c.canWrite;local at=c.canAccess;local o=c.rootOnly;local f=c.adminOnly
local v=c.makeProgramEnv;local s=J.fmtSz
local au=function(E)return J.expandBuf(a,E)end;local i=c.promptInput;local q=c.confirm;local r=c.confirmTyped
b.kill=function(av,E)
if not f(E)then return end
if not av[1]then E("Usage: kill <pid>",d.dim)return end;local aw=tonumber(av[1])
if aw then local ax,ay=t.kill(aw)
if ax then
E("Killed PID "..aw,d.highlight)else E(tostring(ay),d.error)end else E("Invalid PID",d.error)end end
b.fg=function(av,E)if not f(E)then return end
if not av[1]then E("Usage: fg <pid>",d.dim)return end;local aw=tonumber(av[1])if not aw or not t.get(aw)then
E("No such process",d.error)return end
local ax,ay=t.setForeground(aw,a.displayIdx)if not ax then
E(tostring(ay or"Cannot foreground that process"),d.error)return end
E("Foreground: PID "..aw,d.highlight)end
b.verify=function(av,E)if not f(E)then return end;local aw=av and av[1]and
tostring(av[1]):lower()
if aw=="anchor"then local az=false
for aC=2,#av do
local aD=tostring(av[aC]):lower()if aD=="--clear"or aD=="clear"then az=true end end
if az then if not h.clearManifestAnchor then
E("This TOS build cannot clear the anchor.",d.error)return end
local aC,aD=h.clearManifestAnchor()
if aC then
E("Manifest anchor cleared. `doctor` will report it un-anchored.",d.highlight)else
E("Could not clear the anchor: "..tostring(aD),d.error)end;return end;if not h.anchorManifestHash then
E("This TOS build has no manifest anchoring.",d.error)return end
E("Anchoring records THIS system's manifest hash in the EEPROM.",d.dim)
E("Only do it on a system you trust (fresh install, or verified).",d.dim)local aB,aA=h.anchorManifestHash()
if aB then
E("Anchored: "..
tostring(aA):sub(1,32).."...",d.highlight)
E("Your boot address was preserved; changing the boot device clears it.",d.dim)else
E("Anchor failed: "..tostring(aA),d.error)end;return end
E("=== File integrity (every system file vs the manifest) ===",d.title)
E("Checking presence, syntax, and declared hashes...",d.dim)E("")
local ax,ay=pcall(h.verifySystem,function(az,aA)E(az,aA)end)
if not ax then E("verify: "..tostring(ay),d.error)end;E("")
E("This checks FILES. For runtime health (memory/power/services), run 'doctor'.",d.dim)
E("It compares against the MANIFEST. To catch a file that changed since you",d.dim)
E("knew the system was good — and to put it back — use 'srm scan' / 'srm repair'.",d.dim)end;local z=1280
local p={tofu="trusted keys, or a new key you approve; never unsigned.",trusted="trusted keys only.",off="nothing; configured repos only."}
local function w(av,E,aw)local ax=tostring(av)
if not
(ax:find("not enough memory",1,true)or
ax:find("not enough free memory",1,true)or ax:find("Out of memory",1,true))then return end
local ay=math.floor(
(M.totalMemory and M.totalMemory()or 0)/1024)
if ay<z then
E(string.format("%s needs %d KB of RAM; this machine has %d KB.",aw,z,ay),d.dim)else
E("Something else is holding the memory it needs: close other tabs or ".."programs, or reboot, and try again.",d.dim)end end
b.pkg=function(av,E)if not f(E)then return end
local aB,aw=J.requireRoomy(a,"kernel.pkg","admin")if not aB or not aw then local aC=J.loadFailure("pkg",aw)E(aC,d.error)
w(aC,E,"The package manager")return end;local ax=av[1]
local function az(aC)
for aE,aD in
ipairs(aC or{})do local aF=aw.info and aw.info(aD)
if type(aF)=="table"and
aF.kind=="service"then local aG={}
for aE,aH in ipairs(aF.files or{})do
local aI=tostring(aH):match("^/etc/rc%.d/(.+)%.lua$")if aI then aG[#aG+1]=aI end end
if#aG>0 then
local aH=type(aF.service)=="table"and aF.service.defaultState==ak
E(string.format(
aH and"  %s's service is installed switched off. To start it: service start %s"or"  %s runs as a service from the next boot. To start it now: service start %s",aD,table.concat(aG,", ")),d.dim)end end end end
local function aA()local aC={}
for aE,aD in
ipairs((aw.list and aw.list())or{})do
local aF=type(aD)=="table"and aD.name or aD;if type(aF)==L then aC[aF]=true end end;return aC end
local function ay(aC,aD)local aE=2
while aE<=#av do local aF=tostring(av[aE])
if aC[aF]=="value"then aE=aE+1 elseif
aF:sub(1,2)=="--"and not aC[aF]then
E(string.format("pkg %s: unknown option '%s' -- nothing was done.",tostring(ax),aF),d.error)E("Options: "..aD,d.dim)return true end;aE=aE+1 end;return false end
if not ax or ax=="list"then local aC=aw.list()if#aC==0 then
E("No packages installed.",d.dim)return end
E(string.format(" %-24s %-10s %s","name",aq,"kind"),d.title)for aE,aD in ipairs(aC)do
E(string.format(" %-24s %-10s %s",aD.name:sub(1,24),(aD.version or"?"):sub(1,10),
aD.kind or"?"),d.fg)end elseif
ax=="search"or ax=="available"then
local aC=aw.listAllAvailable({includeRemote=true})
if#aC==0 then E("No packages available.",d.dim)
E("Looked on disk under /usr/repo, /var/repo and /mnt/*",d.dim)local aE=aw.repos and aw.repos()or{}
if#aE==0 then
E("No remote repos are configured — add one with:",d.dim)
E("  pkg repo add <name> <https://host/path>",d.dim)else
E(#aE.." remote repo(s) configured but none answered.",d.dim)
E("That usually means no internet card, or the host is",d.dim)
E("unreachable. `pkg repo list` shows what is configured.",d.dim)end;return end
table.sort(aC,function(aE,aF)
if
(aE.category or"misc")~= (aF.category or"misc")then return
(aE.category or"misc")< (aF.category or"misc")end;return(aE.name or"")< (aF.name or"")end)
E(string.format(" %-20s %-10s %s","name",aq,"source"),d.title)local aD=nil
for aF,aE in ipairs(aC)do local aG=aE.category or"misc"if aG~=aD then aD=aG
E("  ["..aG.."]",d.dim)end
local aH=aE.remote and
("repo:"..tostring(aE.repo or"?"))or tostring(aE.root or"?")
E(string.format(" %-20s %-10s %s",(aE.name or"?"):sub(1,20),(aE.version or"?"):sub(1,10),aH),d.fg)end elseif ax=="trust"then local aC=(av[2]or"list"):lower()
if
aC=="list"then local aD=aw.trustList()
if#aD==0 then
E("No publisher keys are trusted on this machine.",d.dim)
E("Every package therefore reads as unsigned or as signed-by-an-",d.dim)
E("unknown-key, and your admin privilege is the only gate.",d.dim)
E("Add one:  pkg trust add <name> <64-hex-key>",d.dim)else
E(string.format(U,"name","fingerprint"),d.title)for aF,aE in ipairs(aD)do
E(string.format(U,aE.label:sub(1,16),aE.fingerprint),d.fg)end;E("",d.dim)
E("Compare a fingerprint with the publisher over a channel that is",d.dim)
E("NOT the disk it came on. A key that arrives with the package it",d.dim)E("signs proves nothing at all.",d.dim)end
E(string.format("Unsigned packages are currently %s.",aw.trustRequired()and"REFUSED"or
"allowed (admin gate only)"),
aw.trustRequired()and d.highlight or d.dim)
E(ah..p[aw.discoveredPolicy()].."  (pkg trust discovered)",d.dim)elseif aC=="discovered"then local aD=(av[3]or""):lower()if aD==""then E(ah..
p[aw.discoveredPolicy()],d.fg)
E("Usage: pkg trust discovered tofu|trusted|off",d.dim)return end
if not p[aD]then
E("Usage: pkg trust discovered tofu|trusted|off",d.dim)E("  tofu     "..p.tofu,d.dim)
E("  trusted  "..p.trusted,d.dim)E("  off      "..p.off,d.dim)return end
local aE,aF=aw.trustDiscovered(aD,{session=J.sessionOf(a)})
if not aE then E(R..tostring(aF),d.error)return end;E(ah..p[aD],d.highlight)elseif aC=="add"then
if
not(av[3]and av[4])then
E("Usage: pkg trust add <name> <64-hex-public-key>",d.dim)
E("<name> is YOUR label for the publisher — it is how you will",d.dim)
E("refer to them locally, and has nothing to do with whatever",d.dim)E("name their disk claims.",d.dim)return end
local aD,aE=aw.trustAdd(av[3],av[4],{session=J.sessionOf(a)})
if not aD then E(R..tostring(aE),d.error)return end;E("Trusted '"..av[3].."'.",d.highlight)
E("Packages signed by this key will now install without a fresh",d.dim)
E("judgement call. That is the point, and the cost.",d.dim)elseif aC==ac or aC=="rm"then if not av[3]then
E("Usage: pkg trust remove <name>",d.dim)return end
local aD,aE=aw.trustRemove(av[3],{session=J.sessionOf(a)})
if not aD then E(R..tostring(aE),d.error)return end
E("Removed '"..av[3].."'. Already-installed packages are",d.highlight)
E("unaffected — this changes what will be accepted from now on.",d.dim)elseif aC=="require"then local aD=(av[3]or""):lower()
if
aD~="on"and aD~="off"then E("Usage: pkg trust require on|off",d.dim)
E("`on` refuses unsigned packages outright. Consider what is on",d.dim)
E("your Optional Utilities disks before turning it on.",d.dim)return end
local aE,aF=aw.trustRequire(aD=="on",{session=J.sessionOf(a)})
if not aE then E(R..tostring(aF),d.error)return end
E("Unsigned packages are now "..
(aD=="on"and"REFUSED."or"allowed."),d.highlight)elseif aC=="key"then
if not av[3]then
E("Usage: pkg trust key <publisher-label>",d.dim)
E("Prints the public key you sign as under that label, and asks",d.dim)
E("for the passphrase without echoing it. Publish the key; never",d.dim)
E("the passphrase. The label is part of the key: the same",d.dim)
E("passphrase under a different label is a different identity.",d.dim)return end
if av[4]then
E("Too many arguments. Only the publisher label goes here — the",d.error)
E("passphrase is asked for separately, and must never be typed",d.dim)
E("on the command line where it is echoed and recalled.",d.dim)return end;if not i then
E("This needs an interactive prompt for the passphrase.",d.error)return end
local aD=i("Signing passphrase: ",96,true)if not aD or aD==""then E(Q,d.dim)return end
local aE,aG=aw.signingKey(aD,av[3])if not aE then E(tostring(aG),d.error)return end
E(aE,d.highlight)local aH,aF=pcall(require,T)if aH and aF then
E("fingerprint "..aF.fingerprint(aE),d.dim)
E("signing as '"..tostring(aF.normalizeLabel(av[3])).."'",d.dim)end else
E("Usage: pkg trust [list|add|remove|require|key] ...",d.dim)end elseif ax=="verify-sig"or ax=="checksig"then if not av[2]then
E("Usage: pkg verify-sig <directory>",d.dim)
E("Says who signed a package WITHOUT installing it.",d.dim)return end
local aC,aD=aw.checkSignature(av[2])if not aC then E(tostring(aD),d.error)return end
E(
"Package: "..tostring(aD and aD.name or"?"),d.title)local aF,aE=pcall(require,T)
if aF and aE then for aH,aG in ipairs(aE.describe(aC))do
E(aG,aC.state==
"trusted"and d.highlight or(aC.state=="invalid"and d.error or
d.warning))end end elseif ax=="sign"then
if not av[2]then
E("Usage: pkg sign <directory> --as <publisher-name>",d.dim)
E("Signs the package's manifest with a key derived from a",d.dim)
E("passphrase you will be asked for. The signature covers the",d.dim)
E("MANIFEST, which covers the file hashes, which cover the files —",d.dim)
E("so sign AFTER the hashes are final, not before.",d.dim)return end;local aC
for aI=3,#av do if av[aI]=="--as"then aC=av[aI+1]end end
if not aC or aC==""then
E("Usage: pkg sign <directory> --as <publisher-name>",d.error)
E("--as is required: the label salts your signing key, so the same",d.dim)
E("passphrase under a different label is a different identity.",d.dim)
E("Use the same label every time — it is part of who you are.",d.dim)return end;if not i then
E("Signing needs an interactive prompt for the passphrase.",d.error)return end
local aD=i("Signing passphrase: ",96,true)
if not aD or aD==""then local aJ,aI=pcall(require,T)
E(string.format("Aborted. A signing passphrase is required (%d+ characters).",
aJ and aI and aI.KDF_MIN_PASS or 20),d.dim)
E("It IS the private key — the same passphrase always produces the",d.dim)
E("same key, on any machine, so make it long and keep it.",d.dim)return end
local aE,aF=aw.signPackage(av[2],aD,{session=J.sessionOf(a),signer=aC})if not aE then
E("Signing failed: "..tostring(aF),d.error)return end
E("Signed. Wrote "..tostring(aF),d.highlight)E("public key "..aE,d.fg)local aH,aG=pcall(require,T)if
aH and aG then
E("fingerprint "..aG.fingerprint(aE),d.dim)end elseif ax=="repo"or ax=="repos"then
local aC=(av[2]or"list"):lower()
if aC=="list"then local aD=aw.repos()
if#aD==0 then
E("No remote repositories configured.",d.dim)
E("Add one:  pkg repo add <name> <https://host/path>",d.dim)
E("The URL is the directory holding the repo's programs.cfg.",d.dim)else
E(string.format(" %-14s %s","name","url"),d.title)
for aG,aF in ipairs(aD)do
E(string.format(" %-14s %s",aF.name:sub(1,14),aF.url),d.fg)if aF.description then
E("                "..aF.description,d.dim)end end;E("",d.dim)
E("This list is the allowlist: what these serve installs like a disk.",d.dim)end;local aE=aw.knownRepos()
if#aE>0 then E("",d.dim)
E("Known (named by installed packages; not trusted):",d.title)
for aG,aF in ipairs(aE)do
E(string.format(" %2d %s",aG,aF.url),d.fg)if#aF.from>0 then
E("      from "..table.concat(aF.from,", "),d.dim)end end
E("Read only for what configured repos lack (pkg trust",d.dim)
E("discovered). Forget:  pkg repo forget <number|url|all>",d.dim)end elseif aC=="add"then
if not av[3]or not av[4]then
E("Usage: pkg repo add <name> <url> [description]",d.dim)
E("  url = the directory containing programs.cfg",d.dim)return end
local aD=#av>=5 and table.concat(av," ",5)or nil
local aE,aF=aw.addRepo(av[3],av[4],aD,{session=J.sessionOf(a)})
if aE then
E("Repo '"..av[3].."' added.",d.highlight)
E("It is now an accepted source of executable code for this",d.warning)
E("machine. 'pkg repo remove "..av[3].."' undoes that.",d.warning)else E(tostring(aF),d.error)end elseif aC==ac or aC=="rm"then if not av[3]then
E("Usage: pkg repo remove <name>",d.dim)return end
local aD,aE=aw.removeRepo(av[3],{session=J.sessionOf(a)})
if aD then
E("Repo '"..av[3].."' removed.",d.highlight)else E(tostring(aE),d.error)end elseif aC=="forget"then if not av[3]then
E("Usage: pkg repo forget <number|url|all>",d.dim)return end
local aE,aD=aw.forgetRepo(av[3],{session=J.sessionOf(a)})
if aE then
E(("Forgot %d known repo(s)."):format(aD or 0),d.highlight)else E(tostring(aD),d.error)end else
E("Usage: pkg repo [list|add <name> <url>|remove <name>|forget <n|url|all>]",d.dim)end elseif ax=="remote"then local aC=_G._TOS and _G._TOS.internet
if aC and not
aC.available()then
E(aC.status().reason or"internet is not available",d.warning)E("'internet' shows the details.",d.dim)return end;E("Contacting configured repositories...",d.dim)
local aD=aw.searchRemote({refresh=
av[2]=="--refresh"})if#aD==0 then
E("Nothing available. Check 'pkg repo list'.",d.dim)return end
E(string.format(" %-22s %-10s %s","name",aq,"repo"),d.title)
for aF,aE in ipairs(aD)do
E(string.format(" %-22s %-10s %s",(aE.name or"?"):sub(1,22),(
aE.version or"-"):sub(1,10),tostring(aE.repo)),d.fg)if aE.description then
E("   "..tostring(aE.description):sub(1,60),d.dim)end end;E("",d.dim)
E("Install one with:  pkg fetch <name>",d.dim)elseif ax=="fetch"then if ay({[P]=true,[O]=true},"--allow-unverified --allow-unsigned")then
return end;local aD,aE,aF=nil,false,false
for aI=2,#av do
local aJ=tostring(av[aI])if aJ==P then aE=true elseif aJ==O then aF=true elseif not aD then aD=aJ end end
if not aD then
E("Usage: pkg fetch <name> [--allow-unverified] [--allow-unsigned]",d.dim)
E("Downloads from a configured repo, then installs it.",d.dim)return end;E("Fetching '"..aD.."'...",d.dim)
local function aG(aI)if
not(r and i)then return nil end
local aK="'"..
tostring(aI.name)..
"' is only in a repo this machine was not "..
"configured with:\n  "..

tostring(aI.repo)..
"\n"..
(
aI.by and(tostring(aI.by).." requires it.\n")or"")..

"\nIts signature is valid, but its key is not trusted here:\n  key "..
tostring(aI.fingerprint)..
"\n"..

(aI.signer and
('It calls its publisher "'..tostring(aI.signer)..
'" -- its own word, not proof.\n')or"")..
"\nCompare the fingerprint with the publisher somewhere that is NOT this repo. ".."Trusted, anything signed with this key installs from now on."
if not
r(aK,"trust",{title="A new publisher key",style="warning",yes="Trust",no="Refuse"})then
E("Refused the key "..

tostring(aI.fingerprint).." for '"..tostring(aI.name).."'.",d.dim)return nil end;local aJ=i("Name this publisher (Enter refuses): ",48)if aJ and
aJ~=""then
E("Trusted the key "..
tostring(aI.fingerprint).." as '"..aJ.."' (from "..
tostring(aI.repo)..").",d.highlight)end;return aJ end
local aH,aC=aw.installRemote(aD,{session=J.sessionOf(a),allowUnverified=aE,allowUnsigned=aF,confirmKey=aG})
if aH then
local aI=aC and aC.discovered and
(tostring(aC.discovered)..", a repo nobody configured")or("repo '"..
tostring(aC and aC.repo).."'")
E(string.format("Installed '%s' from %s (%d files, %d bytes).",aD,aI,(aC and aC.files)or 0,
(aC and aC.bytes)or 0),d.highlight)local c=aC and aC.dependencies;if type(c)=="table"and#c>0 then
E(
"  ...and what it requires: "..table.concat(c,", "),d.highlight)end else
E(tostring(aC),d.error)
if tostring(aC):find("hash",1,true)or
tostring(aC):find("unverified",1,true)then E("",d.dim)
E("That repo ships no file hashes, so TOS cannot check what it",d.dim)
E("sent. Re-run with --allow-unverified if you trust it.",d.dim)end end elseif ax=="outdated"or ax=="updates"then local aC=aw.outdated()
if#aC==0 then
E("Everything is up to date (against what's mounted right now).",d.highlight)
E("Insert another disk and re-run to check against it too.",d.dim)return end
E(string.format(" %-20s %-10s %-10s %s","name","installed","available","from"),d.title)
for aE,aD in ipairs(aC)do
E(string.format(" %-20s %-10s %-10s %s",aD.name:sub(1,20),tostring(aD.from):sub(1,10),tostring(aD.to):sub(1,10),tostring(
aD.root or"?")),d.fg)end;E("",d.dim)
E("pkg upgrade <name>   or   pkg upgrade --all --yes",d.dim)elseif ax=="upgrade"then
if
ay({["--all"]=true,["--yes"]=true,[S]=true,[V]=true,[W]=true,[P]=true,[O]=true},"--all --yes/-y --force --dry-run --allow-unverified --allow-unsigned")then return end;local aG,aH,aI,aJ=false,false,false,false;local aK,aL=false,false;local aD={}
for aM=2,#av do
local aN=tostring(av[aM])
if aN=="--all"then aG=true elseif aN=="--yes"or aN=="-y"then aH=true elseif aN==S then aI=true elseif
aN==V or aN==W then aJ=true elseif aN==P then aK=true elseif aN==O then aL=true elseif aN:sub(1,2)~="--"then aD[#aD+1]=aN end end;local aC={}
if aG then
for aN,aM in ipairs(aw.outdated())do aC[#aC+1]=aM end elseif#aD>0 then local aM={}
for aO,aN in ipairs(aw.outdated())do aM[aN.name]=aN end;for aO,aN in ipairs(aD)do
aC[#aC+1]=aM[aN]or{name=aN,from="?",to="?"}end else
E("Usage: pkg upgrade <name>… | --all [--yes] [--force] [--dry-run]",d.dim)
E("                   [--allow-unverified] [--allow-unsigned]",d.dim)
E("       pkg outdated   shows what has a newer version available",d.dim)return end
if#aC==0 then E("Nothing to upgrade.",d.highlight)return end
if aJ then
E(string.format("Would upgrade %d package(s):",#aC),d.title)for aN,aM in ipairs(aC)do
E(string.format(ad,aM.name,tostring(aM.from),tostring(aM.to)),d.fg)end;E(ae,d.dim)return end
if aG and not aH then
E(string.format("--all would upgrade %d package(s):",#aC),d.warning)for aN,aM in ipairs(aC)do
E(string.format(ad,aM.name,tostring(aM.from),tostring(aM.to)),d.fg)end
E("Add --yes to proceed.",d.dim)return end;local aE,aF=0,0
for aN,aM in ipairs(aC)do
local aP,aO=aw.upgrade(aM.name,{session=J.sessionOf(a),force=aI,allowUnverified=aK,allowUnsigned=aL})
if aP then aE=aE+1
E(string.format(ad,aM.name,tostring(aO.from),tostring(aO.to)),d.highlight)if aO.dropped and#aO.dropped>0 then
E(string.format("      %d file(s) no longer shipped, removed",#
aO.dropped),d.dim)end
if
aO.enabled==false then E("      (was disabled; left disabled)",d.dim)end else aF=aF+1
E(string.format("  %-20s FAILED: %s",aM.name,tostring(aO)),d.error)end end
E(string.format("%d upgraded, %d failed.",aE,aF),aF>0 and d.warning or d.highlight)
if aE>0 then
E("Services keep their enabled/disabled state; restart them to run the",d.dim)
E("new code ('service stop <svc>' then 'service start <svc>').",d.dim)end elseif ax=="info"then
if not av[2]then E("Usage: pkg info <name>",d.dim)return end;local aC=aw.info(av[2])if not aC then
E("Not installed: "..av[2],d.error)return end
E(string.format(" name:        %s",aC.name),d.title)
E(string.format(" version:     %s",aC.version or"?"),d.fg)
E(string.format(" kind:        %s",aC.kind or"?"),d.fg)
if aC.lua or aC.tos then
E(string.format(" needs:       %s%s%s",
aC.lua and("Lua "..aC.lua.."+")or"",(aC.lua and aC.tos)and", "or"",
aC.tos and("TOS "..aC.tos)or""),d.fg)end;if aC.category then
E(string.format(" category:    %s",aC.category),d.fg)end;if aC.description then
E(string.format(" description: %s",aC.description),d.fg)end;if aC.author then
E(string.format(" author:      %s",aC.author),d.fg)end
E(string.format(" status:      %s",
aw.isEnabled(aC.name)and"enabled"or ak),
aw.isEnabled(aC.name)and d.highlight or d.dim)
if type(aC.commands)=="table"then local aD={}for aE in pairs(aC.commands)do
aD[#aD+1]=aE end
if#aD>0 then table.sort(aD)E(" commands:    "..
table.concat(aD,", "),d.fg)end end
if aC.requires and#aC.requires>0 then E(" requires:",d.fg)
for aE,aD in
ipairs(aC.requires)do local aF,aG;if type(aD)=="table"then aF,aG=aD.name,aD.version else
aF,aG=aD:match("^(%S+)%s*(.*)$")end
E(string.format("   %s %s",aF,aG or""),d.dim)end end;if aC.provides and#aC.provides>0 then
E(" provides:    "..
table.concat(aC.provides,", "),d.fg)end;if aC.recommends and
#aC.recommends>0 then
E(" recommends:  "..table.concat(aC.recommends,", "),d.dim)end;if aC.conflicts and
#aC.conflicts>0 then
E(" conflicts:   "..table.concat(aC.conflicts,", "),d.warning)end
if aC.origin=="openos"then
E(" origin:      OpenOS/OPPM package (runs on the compat layer)",d.warning)if aC.capsFromCompat then
E("              declared no capabilities — granted: "..
table.concat(aC.capabilities or{},", "),d.warning)end end
do local n=aC._sigState or"unsigned"
if n=="trusted"then
E(string.format(" signature:   signed by trusted publisher '%s'",tostring(aC._sigLabel)),d.highlight)elseif n=="unknown"then
E(" signature:   valid, but the key was not trusted at install time",d.warning)else E(" signature:   none (unsigned)",d.dim)end
if aC._sigKey then local aE,aD=pcall(require,T)
local aF=
(aE and aD and aD.fingerprint)and aD.fingerprint(aC._sigKey)or
aC._sigKey:sub(1,16)E("              key "..aF,d.dim)end
E(string.format(" integrity:   %s",
aC._unverified and"NOT verified (installed with --allow-unverified)"or"all files matched their declared hashes"),
aC._unverified and d.warning or d.dim)end elseif ax==am or ax=="install-dir"or ax=="from-floppy"or ax==
"fromfloppy"then
if
ay({[P]=true,[O]=true,[S]=true,["--all"]=true,["--yes"]=true,[V]=true,[W]=true,["--key"]="value",["--prompts"]=true,["--classic"]=true},
"--all --yes/-y --dry-run --force --allow-unverified --allow-unsigned ".."--key <key> --prompts")then return end;local aE,aK,aL,aH=false,false,false,false;local aF,aD=false,false;local aI={}
for aN=2,#av do
local aO=tostring(av[aN])
if aO==P then aE=true elseif aO==O then aF=true elseif aO==S then aD=true elseif aO=="--all"then aK=true elseif
aO=="--yes"or aO=="-y"then aL=true elseif aO==V or aO==W then aH=true elseif aO=="--key"then elseif av[aN-1]=="--key"then elseif
aO:sub(1,2)~="--"then aI[#aI+1]=aO end end;local aG=aI[1]local function aM(aN)return
type(aN)==L and aN:find("/",1,true)~=nil end;local aC
if aK then aC="all"elseif ax==
"install-dir"then aC="dir"elseif ax=="from-floppy"or ax=="fromfloppy"then aC=al elseif not aG then
aC=al elseif aM(aG)then aC="dir"elseif#aI>1 then aC="many"else aC="name"end
local function aJ(aN)
if#aN==0 then E("Nothing to install.",d.dim)return end
if aH then
E(string.format("Would install %d package(s):",#aN),d.title)local aQ=0
for aS,aR in ipairs(aN)do local aT,aU
if aw.planByName then aT,aU=aw.planByName(aR)end
if not aT then E("  "..aR,d.fg)if aU then aQ=aQ+1
E("    would fail: "..tostring(aU),d.error)end else E("  "..aR,d.fg)local aV={}for aS,aW in
ipairs(aT.order or{})do
aV[#aV+1]=(aw.info and aw.info(aW))and
(aW.." (installed)")or aW end
if#aV>1 then E("    order: "..
table.concat(aV,", "),d.dim)end;for aS,aW in ipairs(aT.contradictions or{})do
E("    ! "..tostring(aW.text),d.warning)end
if#
(aT.contradictions or{})>0 then
if aD then
E("    --force: would install past "..
#aT.contradictions.." contradiction(s)",d.warning)else aQ=aQ+1
E("    would be refused (--force overrides)",d.error)end end end end;if aQ>0 then
E(string.format("%d of %d would not install as things stand.",aQ,#aN),d.warning)end;E(ae,d.dim)return end;local aP,aO=0,0
for aR,aQ in ipairs(aN)do
local aT,aS=aw.installByName(aQ,{session=J.sessionOf(a),allowUnverified=aE,allowUnsigned=aF,force=aD})
if aT then aP=aP+1
E(string.format("  %-20s installed%s",aQ,
(#aS.skipped>0)and(" (deps present: "..
table.concat(aS.skipped,", ")..")")or""),d.highlight)else aO=aO+1
E(string.format("  %-20s FAILED: %s",aQ,tostring(aS)),d.error)end end
E(string.format("%d installed, %d failed.",aP,aO),aO>0 and d.warning or d.highlight)end
if aH and(aC=="name"or aC=="dir")then aJ({aG})return elseif aH and
aC==al then local aN={}for aP,aO in ipairs(aw.listAllAvailable()or{})do
if not(aw.info and
aw.info(aO.name))then aN[#aN+1]=aO.name end end
table.sort(aN)
if#aN==0 then E("Nothing to install.",d.dim)return end
E(string.format("Would offer %d package(s) to choose from:",#aN),d.title)for aP,aO in ipairs(aN)do E("  "..aO,d.fg)end;E(ae,d.dim)
return end
if aC=="all"then
if not(aL or aH)then
E("--all installs EVERY package on every inserted disk and repo.",d.warning)
E("Add --yes to confirm, or --dry-run to see the list first.",d.dim)return end;local aN={}for aP,aO in ipairs(aw.listAllAvailable()or{})do
if not(aw.info and
aw.info(aO.name))then aN[#aN+1]=aO.name end end
table.sort(aN)aJ(aN)return elseif aC=="many"then aJ(aI)return end
if aC=="name"then local aO;for aQ=3,#av do
if av[aQ]=="--key"and av[aQ+1]then aO=av[aQ+1]end end
local aP,aN=aw.installByName(aG,{licenseKey=aO,session=J.sessionOf(a),allowUnverified=aE,allowUnsigned=aF,force=aD})
if aP then
E(string.format("Installed: %s",table.concat(aN.installed,", ")),d.highlight)az(aN.installed)if#aN.skipped>0 then
E(string.format("Skipped (already present): %s",table.concat(aN.skipped,", ")),d.dim)end else
E("Install failed: "..tostring(aN),d.error)w(aN,E,"Installing packages")end elseif aC=="dir"then
if not aG then E("Usage: pkg install <dir>",d.dim)return end;local aO=aA()
local aP,aN=aw.install(aG,{session=J.sessionOf(a),allowUnverified=aE,allowUnsigned=aF,force=aD})
if aP then local aQ={}
for aR in pairs(aA())do if not aO[aR]then aQ[#aQ+1]=aR end end;table.sort(aQ)
E("Installed: "..
(#aQ>0 and
(table.concat(aQ,", ").." (")or"")..
tostring(aN).. (#aQ>0 and")"or""),d.highlight)az(aQ)else
E("Install failed: "..tostring(aN),d.error)w(aN,E,"Installing packages")end else local aO=false;for aR=2,#av do if av[aR]=="--prompts"or av[aR]=="--classic"then
aO=true end end
local aP=false
if not aO and aw.runInstaller then
local aS,aR=aw.runInstaller({session=J.sessionOf(a),allowUnverified=aE,allowUnsigned=aF,force=aD})
if aS then aP=true
if a.D and a.D.invalidate then pcall(a.D.invalidate)end;if c.drawAll then pcall(c.drawAll)end elseif aR then
E("Menu installer unavailable ("..tostring(aR)..
") — using prompts.",d.dim)end end;if aP then return end
local aQ,aN=aw.installFromFloppy({session=J.sessionOf(a),allowUnverified=aE,allowUnsigned=aF,force=aD,confirm=function(aU,aT,aS,aR)
if q then
local aY={title="Install from media",severity=am,yes="Install",no="Skip",progress=
(aS and aR and aR>1)and{index=aS,total=aR}or nil}if aS and aR and aS<aR then aY.redraw=false end;return
q("Install  "..aU.."?".."\n\n".."From:"..
"\n  "..aT,aY)end;if not i then return false end
local aW=aT:match("^(/mnt/[^/]+)")or aT;local aX=
(aS and aR and aR>1)and string.format(" (%d/%d)",aS,aR)or""local aV=
i("Install "..aU..
" from "..aW..aX.."? [y/N]: ",4)or""return
aV:lower()=="y"or aV:lower()=="yes"end})
if aQ then if#aN.installed>0 then
E(string.format("Installed from media: %s",table.concat(aN.installed,", ")),d.highlight)end;if
#aN.skipped>0 then
E(string.format("Skipped: %s",table.concat(aN.skipped,", ")),d.dim)end;if#aN.installed==0 and
#aN.skipped==0 then
E("No packages found on mounted media. Insert a package disk and retry.",d.dim)end else E("Media scan failed: "..
tostring(aN),d.error)end end elseif ax=="license-hash"then if not av[2]or not av[3]then
E("Usage: pkg license-hash <package-name> <license-key>",d.dim)return end
local aC,aD=aw.computeLicenseHash(av[2],av[3])
if aC then E(aC,d.fg)else E(ag..tostring(aD),d.error)end elseif ax=="uninstall"or ax==ac then if not av[2]then
E("Usage: pkg uninstall <name>",d.dim)return end
local aC,aD=aw.uninstall(av[2],{session=J.sessionOf(a)})if aC then E("Uninstalled: "..av[2],d.highlight)else
E(
"Uninstall failed: "..tostring(aD),d.error)end elseif ax=="make-disk"or
ax=="export-disk"then
if not av[2]then
E("Usage: pkg make-disk <mount> [name ...]",d.dim)
E("  Builds an Optional Utilities disk from your INSTALLED add-ons so",d.dim)
E("  you can install them on another TOS machine without a dev box.",d.dim)
E("  Name args limit the export; omit to include every add-on.",d.dim)E("  e.g. pkg make-disk /mnt/floppy",d.dim)return end;if not aw.exportDisk then
E("This TOS build has no make-disk support.",d.error)return end;local aD=nil;if av[3]then aD={}for aF=3,#av do
aD[#aD+1]=av[aF]end end
local aE,aC=aw.exportDisk(av[2],{only=aD,session=J.sessionOf(a)})
if aE then
E(string.format("Built add-on disk on %s: %d package(s), %d file(s)",aC.target,#aC.packages,aC.files),d.highlight)if#aC.packages>0 then
E("  "..table.concat(aC.packages,", "),d.fg)end;if#aC.problems>0 then
E("  Warnings:",d.warning)
for aG,aF in ipairs(aC.problems)do E("   ! "..aF,d.warning)end end
E("On the target machine, insert the disk and run 'pkg install'.",d.dim)else
E("make-disk failed: "..tostring(aC),d.error)end elseif ax=="enable"or ax=="disable"then if not av[2]then
E("Usage: pkg "..ax.." <name>",d.dim)return end;local aC=(ax=="enable")
local aD,aE=aw.setEnabled(av[2],aC,{session=J.sessionOf(a)})
if aD then
E((aC and"Enabled: "or"Disabled: ")..av[2],d.highlight)else E("Failed: "..tostring(aE),d.error)end elseif ax=="commands"then local aD=aw.commands()local aC={}
for aE in pairs(aD)do aC[#aC+1]=aE end;if#aC==0 then
E("No commands provided by installed packages.",d.dim)return end;table.sort(aC)
E("Commands provided by packages:",d.title)for aF,aE in ipairs(aC)do E("  "..aE,d.fg)end else
E("Usage: pkg [list | search | info <name> | install [name|dir] | uninstall <name>",d.dim)
E("           | enable <name> | disable <name> | commands | make-disk <mnt>]",d.dim)
E("  install: a name installs by name; a path installs that dir; no arg",d.dim)
E("           scans mounted media. Shortcuts: 'install <name>', 'uninstall <name>'.",d.dim)
E("  signing: trust [list|add|remove|require|key] · verify-sig <dir> · sign <dir>",d.dim)end end
b.install=function(E,av)local aw={am}for ax=1,# (E or{})do aw[#aw+1]=E[ax]end;return
b.pkg(aw,av)end
b.uninstall=function(E,av)local aw={"uninstall"}
for ax=1,# (E or{})do aw[#aw+1]=E[ax]end;return b.pkg(aw,av)end
b.backup=function(av,E)if not f(E)then return end;local aw=_G._TOS and _G._TOS.backup
if
not aw then E("backup module unavailable",d.error)return end;local ax=av[1]local ay=J.sessionOf(a)
if ax=="snapshot"or ax=="create"then if not
av[2]or not av[3]then
E("Usage: backup snapshot <src> <dest.bak>",d.dim)return end
local aA,az=aw.snapshot(av[2],av[3],{session=ay})
if aA then
E(string.format("Snapshot OK: %d entries, %d bytes -> %s",az.entries,az.bytes,av[3]),d.highlight)
E("  metaHash: "..az.hash:sub(1,16).."...",d.dim)else
E("Snapshot failed: "..tostring(az),d.error)end elseif ax=="inspect"then if not av[2]then
E("Usage: backup inspect <file.bak>",d.dim)return end
local az,aA=aw.inspect(av[2],{session=ay})if not az then
E("Inspect failed: "..tostring(aA),d.error)return end
E(string.format(" magic:    %s",az.magic),d.fg)
E(string.format(" created:  %d",az.created),d.fg)
E(string.format(" entries:  %d",az.entries),d.fg)
E(string.format(" root:     %s",az.root),d.fg)
E(string.format(" metaHash: %s...",az.metaHash:sub(1,24)),d.fg)
E(string.format(" size:     %d bytes",az.size),d.fg)elseif ax=="restore"then if not av[2]then
E("Usage: backup restore <file.bak> [destRoot] [--force]",d.dim)return end;local aA,aB=nil,false
for aD=3,#av do if
av[aD]==S or av[aD]=="-f"then aB=true else aA=av[aD]end end
local aC,az=aw.restore(av[2],{session=ay,destRoot=aA,force=aB})
if aC then
E(string.format("Restore OK: %d/%d files -> %s",az.restored,az.entries,az.destRoot),d.highlight)D()else
E("Restore failed: "..tostring(az),d.error)end else
E("Usage: backup [snapshot|inspect|restore] ...",d.dim)E("  backup snapshot <src> <dest.bak>",d.dim)
E("  backup inspect  <file.bak>",d.dim)
E("  backup restore  <file.bak> [destRoot] [--force]",d.dim)end end
b.kiosk=function(av,E)if not f(E)then return end
local ax,aw=J.requireRoomy(a,"shell.kiosk","admin")if not ax or not aw then
E(J.loadFailure("kiosk",aw),d.error)return end
E("Kiosk = the LOCKED, guest-facing menu (allow-list + read-only).",d.title)
E("To test: log out, log in as the 'kiosk' user.",d.dim)E("Config: /etc/kiosk.cfg",d.dim)E("",d.fg)
E("Looking for the OPERATOR menu? Run 'desktop': the same kind of",d.highlight)
E("clickable menu, but it runs real commands at YOUR tier (no allow-list).",d.dim)end
b.doctor=function(av,E)local ay,ax=J.requireRoomy(a,"kernel.diag","admin")if not ay or
not ax then E(J.loadFailure("doctor",ax),d.error)
return end
local az={ok=d.highlight or d.fg,info=d.dim or d.fg,warn=d.warning or d.fg,err=
d.error or d.fg}local aA=av[1]
E("=== TOS doctor \226\128\148 runtime health ===",d.title)
local aw=ax.run(function(aD,aE)E(aD,az[aE]or d.fg)end,{only=aA})E("",d.dim)
local aB=string.format("Summary: %d ok, %d info, %d warn, %d err",aw.ok,aw.info,aw.warn,aw.err)local aC=aw.err>0 and d.error or aw.warn>0 and d.warning or
d.highlight
E(aB,aC)
E("This checks RUNTIME health. For a full file-integrity check, run 'verify'.",d.dim)
E("'srm' runs both, plus the known-good baseline check.",d.dim)end;b.diag=b.doctor
b.srm=function(av,E)
local aD,ax=J.requireRoomy(a,"kernel.srm","admin")if not aD or not ax then
E(J.loadFailure("srm",ax),d.error)return end
local aA={ok=d.highlight or d.fg,info=d.dim or d.fg,warn=d.warning or d.fg,err=
d.error or d.fg}local function az(aE)
for aG,aF in ipairs(aE.findings)do E(aF.text,aA[aF.sev]or d.fg)end;return aE end
local function aB(aE)local aF=aE.counts
E("",d.dim)
E(string.format("%d ok, %d info, %d warn, %d err%s",aF.ok,aF.info,aF.warn,aF.err,(aE.fixed or 0)>0 and(
"  |  "..aE.fixed.." fixed")or""),
aA[ax.worst(aE)]or d.fg)end;local ay,aw,aC=ax.parseArgs(av)if aw.source==true then
E("--source needs a mount point, e.g. --source /mnt/floppy",d.error)return end
if ay==N then
E("=== SRM \226\128\148 System Repair & Maintenance ===",d.title)aB(az(ax.status()))E("",d.dim)
E("scan = compare files to the baseline   health = runtime   verify = manifest",d.dim)
E("repair = fix what is safe             baseline = record a known-good system",d.dim)elseif ay=="health"then return b.doctor(aC,E)elseif ay=="verify"then return b.verify(aC,E)elseif
ay=="scan"then
E("=== SRM scan \226\128\148 files vs the known-good baseline ===",d.title)
E("Hashing every baselined file; this takes a moment.",d.dim)aB(az(ax.scan()))elseif ay=="baseline"then if not f(E)then return end
E("Recording what THIS system looks like right now as the known-good",d.title)
E("baseline. Only do that on a system you trust — a fresh install, or",d.dim)
E("one that just passed 'srm verify'. Anything already wrong becomes",d.dim)E("the new definition of correct.",d.dim)
E("",d.dim)local aF=aw.full and true or false
local aG,aE=ax.baseline(nil,{content=aF})if not aG then
E("Baseline failed: "..tostring(aE),d.error)return end
E(string.format("Baseline captured from %s: %d file(s) hashed.",tostring(aE.source),aE.hashed),d.highlight)
if aF then
E(string.format("  %d copy(ies) stored, %.1f KB of disk.",aE.stored,aE.bytes/1024),d.fg)
E("  Local repair is now possible: 'srm repair --restore'.",d.fg)else
E("  Hashes only — drift is detectable, but repair will need",d.fg)
E("  '--source <mount>' (e.g. the install floppy). Use --full to",d.dim)
E("  store verified copies locally instead.",d.dim)end
if aE.skipped>0 then
E(string.format("  %d file(s) skipped (over the %d KB store cap or unreadable).",aE.skipped,ax.MAX_STORE_BYTES/1024),d.warning)end;if aE.pruned>0 then
E(string.format("  %d stale copy(ies) from the previous baseline removed.",aE.pruned),d.fg)end
for aI,aH in ipairs(aE.missing)do E(
"  MISSING at capture time: "..aH,d.warning)end elseif ay=="restore"then if not f(E)then return end
E("=== SRM restore ===",d.title)
aB(az(ax.restore(nil,{source=type(aw.source)==L and aw.source or nil,unverified=
aw.unverified and true or false,paths=#aC>0 and aC or nil})))elseif ay==an and aw.online then if not f(E)then return end
if aw.apply and not o(E)then return end;if aw.ref==true then
E("--ref needs a value, e.g. --ref=build-2603a5b or --ref=main",d.error)return end
local aG,aF=pcall(require,"kernel.netrepair")if not aG or not aF then
E("online repair unavailable: "..tostring(aF),d.error)return end
E("=== SRM repair --online ===",d.title)
local aE=aF.run(nil,{apply=aw.apply and true or false,unanchored=aw.unanchored and true or false,ref=
type(aw.ref)==L and aw.ref or nil})
for aI,aH in ipairs(aE.lines)do E(aH.text,aA[aH.sev]or d.fg)end;if aw.apply then E("",d.dim)
E(string.format("%d repaired, %d rejected.",aE.fixed,aE.rejected),
aE.ok and aA.ok or aA.warn)end elseif ay==an then if not f(E)then
return end;E("=== SRM repair ===",d.title)
if not aw.restore then
E("Fixing what is mechanically safe (interrupted writes, stale state,",d.dim)
E("oversized logs). Add --restore to also put back system files that",d.dim)
E("are missing or have changed since the baseline.",d.dim)end;E("",d.dim)
aB(az(ax.repair(nil,{restore=aw.restore and true or false,source=
type(aw.source)==L and aw.source or nil,unverified=aw.unverified and true or false})))E("",d.dim)
E("Some fixes only apply at boot: 'bootsettings repair on' runs this",d.dim)
E("pass before anything reads the files it repairs.",d.dim)elseif ay=="full"then E("=== SRM full report ===",d.title)
E("",d.dim)E("-- status --",d.title)az(ax.status())
E("",d.dim)E("-- health --",d.title)b.doctor({},E)E("",d.dim)
E("-- integrity --",d.title)b.verify({},E)E("",d.dim)E("-- baseline --",d.title)
aB(az(ax.scan()))else
E("Usage: srm [status|scan|health|verify|repair|baseline|restore|full]",d.title)
E("  srm                      what SRM knows right now (instant)",d.dim)
E("  srm scan                 compare files to the known-good baseline",d.dim)
E("  srm health               runtime health  (same as 'doctor')",d.dim)
E("  srm verify               files vs the manifest  (same as 'verify')",d.dim)
E("  srm full                 all of the above, in one report",d.dim)
E("  srm baseline [--full]    record a known-good system (--full stores copies)",d.dim)
E("  srm repair [--restore]   fix what is safe; --restore puts files back",d.dim)
E("  srm repair --online [--apply] [--unanchored] [--ref=<tag>]",d.dim)
E("                           put back broken system files from the published release",d.dim)
E("  srm restore [--source <mount>] [--unverified] [path...]",d.dim)E("",d.dim)
E("SRM has two halves. The EEPROM one runs at POST and catches the",d.dim)
E("faults that stop a boot; this one catches everything the EEPROM has",d.dim)
E("no room for. 'srm status' reports what the EEPROM half saw.",d.dim)end end
b.bootsettings=function(av,E)if not f(E)then return end
local aC,aA=pcall(require,"kernel.bootcfg")
if not aC or not aA then E("bootcfg unavailable",d.error)return end;local aB=_G._TOS and _G._TOS.fs;if not aB then
E("fs unavailable",d.error)return end;local aw=aA.load(aB)
local ay=(av[1]or""):lower()
if ay==""or ay=="show"then
E("=== Boot Settings (/etc/boot.cfg) ===",d.title)
E("  profile    : "..aw.profile..
(aw.profile=="safe"and"   (SAFE MODE)"or"   (what loads)"),d.fg)
E("  verbosity  : ".. (aw.verbosity or"auto").."   (what it says)",d.fg)
local aF=
aw.ui=="cli"and"cli"or aw.ui=="split"and"panels (split)"or aw.ui=="home"and"panels"or
(
"auto (panels from "..aA.PANELS_MIN_KB.." KB, else cli)")
E("  interface  : "..aF.."   (all seats)",d.fg)
E("  repair     : "..
(aw.repair and"RUN on next boot"or"off"),d.fg)
E("  showConfig : ".. (aw.showConfig and"on"or"off"),d.fg)
E("  cpuTier    : "..
(aw.cpuTier and("Tier "..aw.cpuTier)or"auto"),d.fg)
E("  dataTier   : "..
(aw.dataTier and("Tier "..aw.dataTier)or"auto"),d.fg)
E("  ramGate    : "..
(aw.ramGate==nil and"auto (measure)"or
(
aw.ramGate and"always load the extras"or"never load the extras")),d.fg)local aE=false
for aI,aH in ipairs(aA.FEATURES)do
local aJ=aw.advanced and aw.advanced[aH]if aJ~=nil then
E("    +"..aH.." : ".. (aJ and"on"or"off"),d.dim)aE=true end end
if not aE then E("    (no advanced overrides)",d.dim)end
E("Profiles: "..
table.concat(aA.PROFILE_ORDER or{"minimal","normal","full","diagnostic"}," | "),d.dim)
E("Verbosity: silent | splash | text | verbose | auto",d.dim)
E("Set: bootsettings <profile|verbosity|ui|repair|show|cputier|datatier|ramgate|"..table.concat(aA.FEATURES,"/")..
"> <value>",d.dim)
E("DEL during boot opens the full visual editor; S = Safe Mode once.",d.dim)local aG,aD=pcall(require,"kernel.sysinfo")
if aG and aD then E("",d.dim)
for aI,aH in
ipairs(aD.rows(aD.gather(
nil,{cpuTier=aw.cpuTier,dataTier=aw.dataTier})))do if aH.role=="section"then E(aH.value..":",d.title)else
E("  ".. (aH.label~=""and(
aH.label..": ")or"")..
aH.value,d.dim)end end end;return end;local ax=(av[2]or""):lower()local az=false
if ay=="profile"then
if
aA.PROFILES[ax]then aw.profile=ax;az=true else
E("profiles: "..table.concat(aA.PROFILE_ORDER or
{"minimal","normal","full","diagnostic"}," "),d.error)return end elseif ay=="verbosity"then
if ax=="auto"then aw.verbosity=nil;az=true else local aD=false;for aF,aE in
ipairs(aA.VERBOSITY)do if aE==ax then aD=true end end;if aD then aw.verbosity=ax
az=true else
E("verbosity: silent splash text verbose (or auto)",d.error)return end end elseif ay=="show"or ay=="showconfig"then aw.showConfig=(ax=="on"or ax=="true"or
ax=="1")az=true elseif ay=="cputier"or ay==
"cpu"then
if ax=="auto"then aw.cpuTier=nil;az=true elseif
ax=="1"or ax=="2"or ax=="3"then aw.cpuTier=tonumber(ax)az=true else
E("cputier: auto | 1 | 2 | 3",d.error)return end elseif ay=="datatier"or ay=="data"then
if ax=="auto"then aw.dataTier=nil;az=true elseif ax=="1"or
ax=="2"or ax=="3"then aw.dataTier=tonumber(ax)az=true else
E("datatier: auto | 1 | 2 | 3",d.error)return end elseif ay=="ui"or ay=="interface"then
if
ax=="panels"or ax=="tui"or ax=="home"then aw.ui="home"az=true elseif ax=="cli"or ax=="split"then aw.ui=ax;az=true elseif ax=="auto"then aw.ui=
nil;az=true else
E("ui: auto (by memory) | panels | split | cli",d.error)return end elseif ay==an then
if ax=="on"or ax=="once"or ax=="1"then aw.repair=true;az=true elseif ax==
"off"or ax=="0"then aw.repair=false;az=true else
E("repair: on (runs once next boot, then clears) | off",d.error)return end elseif ay=="ramgate"or ay=="ram"then
if ax=="auto"then aw.ramGate=nil;az=true elseif ax=="always"or ax==
"plenty"or ax=="on"then aw.ramGate=true;az=true elseif
ax=="never"or ax=="tight"or ax=="off"then aw.ramGate=false;az=true else
E("ramgate: auto (measure free RAM) | always | never  (load the optional extras)",d.error)return end elseif ay=="reset"then aw=aA._normalize({})az=true else local aD=false;for aF,aE in ipairs(aA.FEATURES)do if
aE==ay then aD=true end end
if aD then
aw.advanced=aw.advanced or{}
if ax=="auto"then aw.advanced[ay]=nil elseif ax=="on"then aw.advanced[ay]=true elseif
ax=="off"then aw.advanced[ay]=false else
E(ay..": auto | on | off",d.error)return end;az=true else
E("Unknown setting: "..ay.." (try: bootsettings show)",d.error)return end end
if az then local aD,aE=aA.save(aB,aw)if aD then
E("Saved. Applies on next boot (reboot to apply now).",d.highlight)else
E("Save failed: "..tostring(aE),d.error)end end end
local function A()local aw,E=pcall(require,"kernel.bootcfg")
local av=_G._TOS and _G._TOS.fs;if aw and E and av then return E,av end end
local function B(av,E)local aw=h.getSwap and h.getSwap()
if av=="now"then
local aD,aC=pcall(require,ap)if not aD or not aC.sweepCold then
E("tab paging unavailable",d.error)return end;if not aw then
E("Swap not available",d.error)return end;local aE=aC.sweepCold(a,true)
local aF,aG=aC.pagedStats(a)
E(string.format("Paged out %d view tab(s) now.",aE),d.highlight)
E(string.format("%d tab(s) on disk, %d lines held there.",aF,aG),d.dim)
E("They page back transparently the next time you open them.",d.dim)return end
if av==""or av==N or av=="keys"or av=="clear"then if not aw then
E("Swap not available",d.error)return end
if av=="clear"then if not f(E)then return end
local aF,aE=pcall(require,ap)
if aF and aE.isPaged then for aH,aG in ipairs(a.tabs or{})do
if aE.isPaged(aG)then local aH=aG.content end end end;aw.clear()E("Swap cleared.",d.highlight)return end;local aC=aw.usage()
local aD=(aC.max and aC.max>0)and math.floor(aC.bytes*100/
aC.max)or 0;E("=== Disk Swap (/var/swap) ===",d.title)
E(string.format("Used:    %s / %s (%d%%)",s(aC.bytes),s(aC.max),aD),
aD>90 and d.warning or d.fg)
E(string.format("Entries: %d",aC.count),d.dim)if av=="keys"and aw.keys then local aE=aw.keys()
if#aE==0 then
E("(no keys)",d.dim)else for aG,aF in ipairs(aE)do E("  "..aF,d.dim)end end end
do
local aH,aF=pcall(require,ap)if aH and aF.pagedStats then local aI,aJ=aF.pagedStats(a)
E(string.format("View tabs paged: %d (%d lines)",aI,aJ),
aI>0 and d.highlight or d.dim)end;local aG,aE=25,(
h.getConfig and h.getConfig())if
aE and aE.get then
aG=tonumber(aE.get("swapPressurePct"))or 25 end
E(string.format("Cold view buffers page out below %d%% free RAM"..
"  (swapPressurePct)",aG),d.dim)end
E("Volatile: cleared on every boot. 'swap clear' wipes now.",d.dim)
E("'swap now' pages cold tabs immediately (ignores pressure).",d.dim)
E("Paging spends disk writes to save RAM — see 'optimize power'.",d.dim)return end;if not f(E)then return end;local ay,az=A()if not ay then
E("bootcfg/fs unavailable",d.error)return end;local ax=ay.load(az)
ax.advanced=ax.advanced or{}
if av=="auto"then ax.advanced.swap=nil elseif av=="on"then ax.advanced.swap=true elseif
av=="off"then ax.advanced.swap=false else
E("swap <status|keys|now|clear|on|off|auto>",d.error)return end;local aA,aB=ay.save(az,ax)if aA then
E("Disk swap set "..av..". Applies on next boot.",d.highlight)else
E("Save failed: "..tostring(aB),d.error)end end
local function F(av,aw,E)local aD,ax=pcall(require,"kernel.power")
if
not aD or type(ax)~="table"or not ax.PROFILES then
E("Power control unavailable: "..tostring(ax),d.error)
E("TOS behaves as profile 'off' — nothing is being conserved.",d.dim)return end;local aC,az=pcall(require,"kernel.screen")
local aA=h.getConfig and h.getConfig()
if av==""or av=="show"or av==N then local aI=ax.profile()
E("=== Power ===",d.title)local aJ,aF,aG=pcall(ax.energy)
if
aJ and type(aF)==ab and type(aG)==ab and aG>0 then
local aO=math.floor(aF*100/aG+0.5)
E(string.format("  Stored     %d / %d  (%d%%)",math.floor(aF),math.floor(aG),aO),
aO<25 and d.warning or d.fg)local aM=a._pwrSample
local aN=aM and aM.t and(h.uptime()-aM.t)or 0
if aN>=1 then local aP=(aM.e-aF)/aN
if aP>0.05 then
E(string.format("  Draw       %.1f/s over the last %ds",aP,math.floor(aN)),d.fg)if aF>0 then
E(string.format("             ~%d s of buffer left at that rate",math.floor(aF/aP)),d.dim)end elseif aP<-0.05 then
E(string.format("  Draw       charging (+%.1f/s)",
-aP),d.highlight)else
E(string.format("  Draw       level over the last %ds — supply is keeping up",math.floor(aN)),d.fg)end else
E("  Draw       run 'optimize power' again in a few seconds for a rate",d.dim)end;a._pwrSample={t=h.uptime(),e=aF}else
E("  Stored     (this machine reports no energy buffer)",d.dim)end;E("",d.dim)E("  Profile    "..aI,d.highlight)
local aK,aH=ax.idleSeconds(),ax.blankSeconds()
E(string.format("  Idle clock every %ds",aK),d.fg)
E("    a status-bar repaint is a GPU write, which OC bills per cell",d.dim)
E("  Screen blank "..
(aH>0 and("after "..aH.."s idle")or"never"),d.fg)
E("    OC bills a screen per tick per NON-BLANK cell; blank costs ~0",d.dim)local aL=(aC and az.bufferMode and az.bufferMode())or
"?"
E("  Display buffer "..aL,d.fg)
E("    unchanged cells skip the GPU write entirely ('optimize buffer')",d.dim)E("",d.dim)
E("optimize power <off|balanced|save>   off = no conservation",d.dim)
E("optimize power blank <secs|off>      screen blank timeout",d.dim)
E("optimize power idle <secs>           idle repaint cadence",d.dim)return end
if av=="blank"or av=="idle"then if not f(E)then return end
local aG=
(aw=="off"or aw=="never")and 0 or tonumber(aw)local aF,aH=ax.setKnob(av,aG)if not aF and aF~=0 then
E(tostring(aH),d.error)return end
if av=="blank"then
E(aF>0 and
("Screen blanks after "..aF.."s idle.")or"Screen blanking off.",d.highlight)else
E("Idle repaint every "..aF.."s.",d.highlight)end
E("Profile is now custom (a named profile resets both knobs).",d.dim)return end;if not f(E)then return end;local aB,aE=ax.applyProfile(av)if not aB then
E(tostring(aE),d.error)
E("Profiles: "..table.concat(ax.PROFILE_ORDER,", "),d.dim)return end
local ay=ax.PROFILES[aB]
if aC and az.setBuffer then pcall(az.setBuffer,ay.buffer)end
if aA and aA.set then aA.set("powerProfile",aB)local aF=pcall(aA.save)if
not aF then
E("(profile applied, but /etc/tos.cfg could not be saved)",d.warning)end end;E("Power profile: "..aB,d.highlight)
E(string.format("  idle repaint %ds · screen blank %s · display buffer %s",ay.idleSec,
ay.blankSec>0 and(ay.blankSec.."s")or"never",ay.buffer),d.dim)
E("Applies now, on every seat, and persists across reboots.",d.dim)end
b.swap=function(E,av)return B((E[1]or""):lower(),av)end
b.optimize=function(av,E)local aw=(av[1]or""):lower()
local ay=(av[2]or""):lower()local az,ax=pcall(require,"kernel.screen")
if aw==""or aw=="show"or
aw==N then E("=== Optimizations ===",d.title)
local aB="auto (profile)"local aC,aD=A()
if aC and aD then local aG=aC.load(aD)
local aH=aG.advanced and aG.advanced.swap;if aH~=nil then aB=aH and"on"or"off"end end;local aA=h.getSwap and h.getSwap()local aE="inactive"
if aA then
local aG=aA.usage()
local aH=(aG.max and aG.max>0)and
math.floor(aG.bytes*100/aG.max)or 0
aE=string.format("active %s/%s (%d%%)",s(aG.bytes),s(aG.max),aH)end
E(string.format("  Disk swap      %-14s [%s]",aB,aE),aA and d.fg or d.dim)
E("    extends usable memory onto /var/swap (boot feature)",d.dim)local aF=(az and ax.bufferMode and ax.bufferMode())or
"?"
E(string.format("  Display buffer %-14s",aF),d.fg)
E("    skips GPU writes for unchanged cells (auto = memory-gated)",d.dim)
if az and ax.bufferStats then local n=ax.bufferStats()
if n.total>0 then
E(string.format("    this session: %d of %d cell-draws skipped (%d%%)",n.skipped,n.total,math.floor(
n.ratio*100+0.5)),
n.ratio>0 and d.highlight or d.dim)else E("    (no draws measured yet)",d.dim)end end
do local aH,aG=pcall(require,"kernel.power")
if
aH and type(aG)=="table"and aG.profile then local aI=aG.blankSeconds()
E(string.format("  Power          %-14s [idle %ds, blank %s]",aG.profile(),aG.idleSeconds(),
aI>0 and(aI.."s")or"never"),d.fg)
E("    fewer wake-ups and a blank screen are what OC bills less for",d.dim)else E("  Power          not loaded",d.dim)end end;E("",d.dim)
E("swap [status|keys|now|clear|on|off|auto]  boot toggle needs reboot",d.dim)
E("optimize power  <off|balanced|save>       conservation profile",d.dim)
E("optimize buffer <on|off|auto>             display; applies immediately",d.dim)return end;if aw=="swap"then return B(ay,E)end;if aw=="power"then return
F(ay,(av[3]or""):lower(),E)end
if
aw=="buffer"or aw=="display"then if not f(E)then return end;if not(az and ax.setBuffer)then
E("display buffer control unavailable",d.error)return end
local aA,aB=ax.setBuffer(ay)
if aA then
E("Display buffer set "..ay.." (applied now).",d.highlight)else E(tostring(aB)or"invalid",d.error)end;return end
E("Usage: optimize [show | power <off|balanced|save> | buffer <on|off|auto>".." | swap <on|off|auto>]",d.dim)
E("       `swap` on its own is the same as `optimize swap`.",d.dim)end
b.programs=function(av,E)local aw={"/bin","/usr/bin","/home/"..a.who}
E("Executables:",d.title)
for ay,ax in ipairs(aw)do
if e.isDirectory(ax)then local aA,az=pcall(e.list,ax)
if aA and az then local aB={}
if type(az)==
"table"then aB=az elseif type(az)=="function"then for aD in az do aB[#aB+1]=aD end end;local aC={}
for ay,aD in ipairs(aB)do if aD:match("%.lua$")then aC[#aC+1]=aD end end
if#aC>0 then E(" "..ax..":",d.dim)for ay,aD in ipairs(aC)do
E("   "..aD,
d.file_lua or d.file_exec or d.highlight)end end end end end end
b.log=function(av,E)if not f(E)then return end;local aw=h.getLog()if not aw then
E("Logger unavailable",d.error)return end
local ax=

(av[1]==nil)or(av[1]=="file")or(av[1]=="f")or(av[1]=="all")or(tonumber(av[1])~=nil)
if ax then local aB="/var/log/kernel.log"
local aA=tonumber(av[1])or tonumber(av[2])pcall(aw.flush)
if not e.exists(aB)then
E("No /var/log/kernel.log yet — showing in-memory ring.",d.dim)local aE=aw.recent(aA or 20)if#aE==0 then
E("(log is empty)",d.dim)return end
local aF={{" in-memory log ring ("..#aE.." entries)",d.title}}
for aH,aG in ipairs(aE)do local aI=d.fg;if aG.level>=3 then aI=d.error elseif aG.level>=2 then aI=d.warning elseif aG.level<1 then
aI=d.dim end
aF[#aF+1]={aw.format(aG),aI}end;y(aF,"log (ring)")return end;local aD=e.readFile(aB)if not aD then
E("Cannot read "..aB,d.error)return end;local ay={}for aE in aD:gmatch("([^\n]*)\n?")do if aE~=""then
ay[#ay+1]=aE end end;local aC=
(aA and aA>0 and#ay-aA+1)or 1;if aC<1 then aC=1 end;local az={}
az[#az+1]={
" /var/log/kernel.log  ("..#ay.." lines)",d.title}
for aE=aC,#ay do local aF=ay[aE]local aG=d.fg
if
aF:find("%[FTL%]")or aF:find("%[ERR%]")then aG=d.error elseif aF:find("%[WRN%]")then aG=d.warning elseif aF:find("%[DBG%]")then aG=d.dim end;az[#az+1]={aF,aG}end;y(az,aa)return end
if av[1]=="filter"then local ay,az=av[2],av[3]
if not ay then
local aB={[0]="DEBUG","INFO","WARN","ERROR"}local aA=0;for aD,aC in pairs(aw.getSourceLevels())do aA=aA+1
E(string.format("  %-12s %s+",aD,aB[aC]or
tostring(aC)),d.fg)end;if aA==0 then
E("(no per-source filters; global level applies)",d.dim)end
E("Usage: log filter <source> <debug|info|warn|error|off>",d.dim)return end
if az=="off"or az=="clear"then aw.setSourceLevel(ay,nil)E(
"Filter cleared for '"..ay.."'.",d.fg)elseif az then
local aA,aB=aw.setSourceLevel(ay,az)
if aA then
E("Source '"..ay.."' now logs at "..az:upper().."+.",d.fg)else E(aB or"Filter update failed",d.error)end else
E("Usage: log filter <source> <debug|info|warn|error|off>",d.dim)end;return end
if av[1]=="clear"then pcall(aw.flush)
aw.info("log","--- ring cleared on operator request ---")
E("Ring marker recorded; old entries still on disk.",d.dim)return end
if av[1]=="ring"or av[1]=="r"or av[1]=="tail"then local az=
tonumber(av[2])or 20;local ay=aw.recent(az)if#ay==0 then
E("(no log entries in ring)",d.dim)return end
for aB,aA in ipairs(ay)do local aC=d.dim
if aA.level>=3 then aC=d.error elseif
aA.level>=2 then aC=d.warning elseif aA.level>=1 then aC=d.fg end;E(aw.format(aA),aC)end
E(#ay.." ring entries (use 'log' for full on-disk history)",d.dim)return end
E("Usage: log [N] | log ring [N] | log clear | log filter ...",d.dim)
E("  log        Open the full on-disk log (last N lines if given)",d.dim)
E("  log ring   Quick peek at the in-memory ring",d.dim)end
b.bg=function(E,av)if not f(av)then return end;if not E[1]then
av("Usage: bg <script.lua> [args...]",d.dim)
av("  Runs a Lua script in a background tab.",d.dim)return end
local aD=u(E[1])local aE=J.safeModeRefusal(aD)
if aE then av(aE,d.error)return end;local ax=e.readFile(aD)
if not ax then av(af..E[1],d.error)return end;local aG,aH=load(ax,"="..E[1],"t",v{name=E[1]})if not aG then av(
"Compile error: "..tostring(aH),d.error)
return end;local aB={}
for aL=2,#E do aB[#aB+1]=E[aL]end;local ay=E[1]:match("[^/]+$")or E[1]
local aw=c.createTab("output","bg:"..ay,{content={
"Background task: "..ay,"PID: (starting...)",""},offset=0,pid=nil})local aK=#c.tabs;local az=500
local function aC(...)local aL={}for aO=1,select("#",...)do
aL[#aL+1]=tostring(select(aO,...))end;local aN=table.concat(aL,"\t")aw.content[#
aw.content+1]=aN
if#aw.content>az then
local aO=#aw.content-az
for aP=1,az do aw.content[aP]=aw.content[aP+aO]end;for aP=az+1,#aw.content do aw.content[aP]=nil end;aw.offset=math.max(0,
aw.offset-aO)end;local aM=k-3
if aw.offset>=#aw.content-aM-2 then aw.offset=math.max(0,
#aw.content-aM)end end
local aA=t.spawn("bg:"..ay,function()local aL=v{name=E[1],stdout=aC}
local aM=load(ax,"="..E[1],"t",aL)ax=nil
if aM then local aN,aO=pcall(aM,table.unpack(aB))J.reportProgramEnd(a,function(aP)
aC(aP)end,aN,aO,ag,aL)end;aC("","--- Task finished ---")end,{priority=8,source="user",tsr=true})aw.pid=aA;aw.content[2]="PID: "..aA
av("Started background task: "..ay..
" (PID "..aA..")",d.highlight)local aI,aF=pcall(require,"shell.panels.home")local aJ=(aI and aF)and
aF.cycleKeyLabel(a)or"F2"
av(
"Switch to its tab with "..aJ..", or use 'kill "..aA.."' to stop.",d.dim)end
b.run=function(E,av)if not f(av)then return end;if not E[1]then
av("Usage: run <file.lua>",d.dim)return end;local ax=u(E[1])
local ay=J.safeModeRefusal(ax)if ay then av(ay,d.error)return end;local az=e.readFile(ax)if not az then av(af..
E[1],d.error)return end
local aA=v{name=E[1],stdout=function(aF)av(aF,d.fg)end}local aB,aC=load(az,"="..E[1],"t",aA)if not aB then
av("Compile error: "..tostring(aC),d.error)return end;local aw={}
for aF=2,#E do aw[#aw+1]=E[aF]end;local aD,aE=pcall(aB,table.unpack(aw))
J.reportProgramEnd(a,av,aD,aE,"Runtime error: ",aA)end
b.lua=function(av,E)if not o(E)then return end
pcall(function()local aC=require(aa)if aC and aC.info then
aC.info("repl",
"REPL session opened by "..tostring(a.who or"?"))end end)local aA=M.uptime()j.fill(1,1,l,k," ",d.fg,d.bg)
j.fill(1,1,l,1," ",d.bar_fg,d.bar_bg)
j.set(1,1," Lua REPL  type 'exit' to quit",d.bar_fg,d.bar_bg)
j.set(1,1," Lua REPL  'exit' to quit | blank line runs/cancels a block",d.bar_fg,d.bar_bg)local aw=2;local ax={}
local function az(aC,aD)if aw>k-1 then local aE=j.getGpu()if aE and aE.copy then
aE.copy(1,3,l,k-3,0,-1)end;j.fill(1,k-1,l,1," ",d.fg,d.bg)
aw=k-1 end;j.set(1,aw,tostring(aC):sub(1,l),
aD or d.fg,d.bg)aw=aw+1 end;local function aB(aC)
return type(aC)==L and aC:find("<eof>",1,true)~=nil end;local ay={}
while true do if aw>k-1 then j.getGpu().copy(1,3,l,k-3,0,-
1)
j.fill(1,k-1,l,1," ",d.fg,d.bg)aw=k-1 end;local aE=#ay>0
local aG=aE and">> "or"> "j.fill(1,aw,l,1," ",d.fg,d.bg)
j.set(1,aw,aG,d.highlight,d.bg)local aC=""local aD=#ax+1;local aF=#aG+1
while true do
j.fill(aF,aw,l-aF+1,1," ",d.fg,d.bg)j.set(aF,aw,aC.."_",d.fg,d.bg)
local aJ,aK,aH,aI=c.pullSignal()
if aJ=="key_down"then
if aI==28 then break elseif aI==14 then if#aC>0 then aC=aC:sub(1,-2)end elseif aI==200 then if
aD>1 then aD=aD-1;aC=ax[aD]or""end elseif aI==208 then if aD<#ax then aD=aD+1
aC=ax[aD]or""else aD=#ax+1;aC=""end elseif aH and aH>=32 and aH<127 then aC=
aC..string.char(aH)end elseif aJ=="clipboard"and type(aH)==L then
aC=aC..aH:gsub("\r","")local aL=aC:find("\n",1,true)
if aL then aC=aC:gsub("\n"," ")end end end;aw=aw+1
if(aC=="exit"or aC=="quit")and not aE then break end
if aC==""and not aE then elseif aC==""and aE then ay={}az("(cancelled)",d.dim)else
ay[#ay+1]=aC;local aH=table.concat(ay,"\n")
local aJ,aK=load("return "..aH,"=repl","t")if not aJ then aJ,aK=load(aH,"=repl","t")end;if
not aJ and aB(aK)then goto repl_continue end;ay={}ax[#ax+1]=aH
pcall(function()
local aN=require(aa)if aN and aN.info then
aN.info("repl","["..tostring(a.who or"?").."] "..
aH:gsub("\n"," ; "):sub(1,120))end end)
local aL=v{name="repl",caps={["fs.read"]=true,["fs.write"]=true,["compat.io"]=true,["component"]=true,["load"]=true,["net"]=true,["peripheral.modem"]=true,["peripheral.redstone"]=true,["peripheral.robot"]=true,["peripheral.inventory"]=true,["peripheral.tape"]=true},stdout=function(aN)
az(aN,d.fg)end}local aI,aM=load("return "..aH,"=repl","t",aL)if not aI then
aI,aM=load(aH,"=repl","t",aL)end
if aI then local aO,aN=pcall(aI)
if aO then if aN~=nil then
az(tostring(aN),d.highlight)end else az(tostring(aN),d.error)end else az(ag..tostring(aM),d.error)end end::repl_continue::end
pcall(function()local aC=require(aa)if aC and aC.info then
aC.info("repl",string.format("REPL session closed by %s (%.1fs, %d cmds)",tostring(
a.who or"?"),M.uptime()-aA,#ax))end end)end
b.edit=function(E,av)if not f(av)then return end;if not E[1]then
av("Usage: edit <file>",d.dim)return end;local aw=u(E[1])C(aw)end
b.protect=function(av,E)if not o(E)then return end
local aA,aw=pcall(require,"kernel.securefs")if not aA or not aw or not aw.setOperatorOverride then
E("This build has no protected-path override.",d.error)return end
local ax=J.sessionOf(a)
if not ax then
E("Could not identify your session, so there is nothing to arm.",d.error)
E("This is a bug rather than a permission problem — `whoami` should",d.dim)
E("say who you are; if it does, please report it.",d.dim)return end
local ay=aw.operatorOverride and aw.operatorOverride(ax)local az=(av[1]or""):lower()
if az==""or az==N then
E(
"Protected-path guards are "..
(ay and"STOOD DOWN for this session."or"active."),ay and d.warning or d.highlight)E("",d.dim)
E("They stop even root from writing under /tos, /etc, /usr and",d.dim)
E("/var through securefs — a line against a tampered admin",d.dim)
E("session, not an ACL. You own this machine, so you can stand",d.dim)
E("them down; nobody below root can, and it ends with this",d.dim)E("session.",d.dim)E("",d.dim)
E("  protect off    stand the guards down for this session",d.dim)E("  protect on     put them back",d.dim)return end
if az=="off"then if ay then
E("Already stood down for this session.",d.dim)return end
local aB,aC=aw.setOperatorOverride(ax,true)
if not aB then E(R..tostring(aC),d.error)return end
E("Protected-path guards STOOD DOWN for this session.",d.warning)
E("You can now write and remove under /tos, /etc, /usr and /var.",d.dim)
E("Every path allowed this way is written to the kernel log.",d.dim)
E("Deleting the wrong thing here is how a machine stops booting —",d.dim)E("`protect on` when you are done.",d.dim)elseif az=="on"then if not ay then
E("Guards are already active.",d.dim)return end
local aB,aC=aw.setOperatorOverride(ax,false)
if not aB then E(R..tostring(aC),d.error)return end
E("Protected-path guards active again.",d.highlight)else E("Usage: protect [status|off|on]",d.dim)end end
b.reclaim=function(av,E)if not o(E)then return end;local aF=false;for aK,aJ in ipairs(av or{})do
if aJ=="--apply"then aF=true end end
local aI,aw=pcall(require,"kernel.fs")
if not aI or not aw then E("Filesystem unavailable.",d.error)return end;local ay=aw.readFile("/init.lua")if not ay then
E("Cannot read /init.lua — refusing to guess what this machine boots.",d.error)return end
if not
(
ay:find("_TOS",1,true)or ay:find("TOS Kernel",1,true)or
ay:find("tos/kernel",1,true))then
E("/init.lua is not TOS's — this machine boots OpenOS.",d.error)
E("Those files are the operating system here, not leftovers.",d.dim)E("Refusing.",d.dim)return end;local az={"/bin","/boot","/lib"}local aA={}local aC="/init.lua.pre-tos"for aK,aJ in
ipairs(az)do
if aw.exists(aJ)then if aw.exists(aC)then aA[#aA+1]=aC end;break end end
local function aG(aJ,aK)
if not aw.exists(aJ)then return end
if aw.isDirectory(aJ)then
for aM,aL in ipairs(aw.list(aJ)or{})do aG(aJ.."/"..
(aL:gsub("/$","")),aK)end;aK.dirs[#aK.dirs+1]=aJ else
aK.files[#aK.files+1]=aJ;aK.bytes=aK.bytes+ (aw.size(aJ)or 0)end end;local ax={files={},dirs={},bytes=0}for aK,aJ in ipairs(az)do aG(aJ,ax)end
for aK,aJ in
ipairs(aA)do if aw.exists(aJ)and not aw.isDirectory(aJ)then ax.files[
#ax.files+1]=aJ
ax.bytes=ax.bytes+ (aw.size(aJ)or 0)end end;if#ax.files==0 and#ax.dirs==0 then
E("Nothing to reclaim — no OpenOS leftovers found.",d.highlight)return end;local aH=math.floor(
ax.bytes/1024+0.5)
E(string.format("OpenOS leftovers: %d file(s) in %d director(ies), ~%d KB",
#ax.files,#ax.dirs,aH),d.title)
for aK,aJ in ipairs(az)do if aw.exists(aJ)then E("  "..aJ,d.fg)end end
for aK,aJ in ipairs(aA)do if aw.exists(aJ)then E("  "..aJ,d.fg)end end;E("",d.dim)
E("TOS installs no files into these, but it still looks in them:",d.dim)
E("require() searches /lib, and an unknown command is tried in /bin.",d.dim)
if aw.exists(aC)then
E("Until this runs, renaming /init.lua.pre-tos back to /init.lua",d.dim)
E("boots OpenOS again; afterwards an OpenOS floppy is the way back.",d.dim)else
E("An OpenOS floppy remains your recovery path — this install",d.dim)
E("stopped being one when TOS replaced /init.lua.",d.dim)end;E("",d.dim)
E("Removing /bin also changes what an unknown command does: today",d.dim)
E("it may run OpenOS's version, afterwards you get 'not a command'.",d.dim)if not aF then E("",d.dim)
E("Dry run. Nothing was removed.",d.highlight)E("Run it for real with:  reclaim --apply",d.dim)
return end
if q then
local aJ=q(string.format(
"Permanently delete %d OpenOS file(s), ~%d KB?\n\n"..
"%s\n\nTOS keeps working; this drive stops being able to boot ".."OpenOS. Your recovery path becomes an OpenOS floppy.",
#ax.files,aH,table.concat(az,"  ")),{title="Remove OpenOS leftovers",severity=Z,yes="Delete",no=X})if not aJ then E("Cancelled. Nothing was removed.",d.highlight)
return end end;E("",d.dim)E("Removing...",d.warning)local aD,aB,aE=0,0,0;for aK,aJ in
ipairs(ax.files)do local aL=aw.size(aJ)or 0
if aw.remove(aJ)then aD=aD+1;aE=aE+aL else aB=aB+1 end end;for aK,aJ in ipairs(ax.dirs)do
pcall(aw.remove,aJ)end
E(string.format("Removed %d file(s), ~%d KB reclaimed.",aD,math.floor(aE/1024+0.5)),d.highlight)if aB>0 then
E(aB.." file(s) could not be removed.",d.warning)end
E("Reboot when convenient; nothing running depends on them.",d.dim)end
b.flash=function(av,E)if not o(E)then return end;local aA,aH=nil,false;for aO,aN in ipairs(av)do if aN=="--data"then aH=true elseif aA==nil then
aA=aN end end
if
not aA then E("Usage: flash <file> [--data]",d.dim)
E("Flashes the given file to the system EEPROM.",d.dim)
E("--data also writes the chip's data field, asked for and not shown,",d.dim)
E("for a chip going into a robot or drone (rc-pilot's shared secret).",d.dim)return end;local aB=u(aA)local ax=nil;for aN in K.list("eeprom")do ax=aN;break end
if not ax then
E("No EEPROM detected. Insert EEPROM, or press Ctrl+C to abort...",d.warning)local aN=M.uptime()+60
while not ax and M.uptime()<aN do
local aO,aP,aQ=c.pullSignal(1)if aO=="component_added"and aQ=="eeprom"then ax=aP elseif aO=="interrupted"then
E(Q,d.dim)return end end
if not ax then E("Timed out waiting for EEPROM.",d.error)return end;E("EEPROM detected.",d.highlight)end;local ay=K.proxy(ax)local aC=ay.getSize()
local aD=e.size and e.size(aB)if type(aD)==ab and aD>aC then
E(string.format("File too large: %d bytes (EEPROM max: %d)",aD,aC),d.error)return end
local aw,aJ=e.readFile(aB)
if not aw then E(af..tostring(aJ),d.error)return end;if#aw>aC then
E(string.format("File too large: %d bytes (EEPROM max: %d)",#aw,aC),d.error)return end
local aK,aL=load(aw,"=flash-verify","t",{})
if not aK then
E("Refusing to flash: file does not parse as Lua text.",d.error)E("  "..tostring(aL),d.dim)return end
local aE=
aw:find("getBootAddress",1,true)or aw:find("setBootAddress",1,true)or
(aw:find("component.list",1,true)and aw:find("init.lua",1,true))
if not aE then local aN
if r then
aN=r("This file does not look like a BIOS."..
"\n\n"..
"None of the markers a BIOS normally carries were found in it. "..

"Flashing it will very likely leave a machine that cannot boot, "..
"and fixing that means physically replacing the EEPROM."..
"\n\n".."If this chip is going into a robot or a drone, that is expected: "..
"put this computer's own EEPROM back before it restarts.","force",{title="Not a BIOS",severity=Z,yes="Flash anyway",no=X})else
aN=
(i and i("Doesn't look like a BIOS — type 'force' to flash anyway: ",16))=="force"end
if not aN then E("Aborted (safety check).",d.dim)return end end;local az=nil
if aH then
if aE then
E("Refusing --data: this file looks like a BIOS, and a BIOS keeps its",d.error)
E("boot address in the data field. --data is for a chip that is going",d.dim)E("into a robot or a drone.",d.dim)return end
if not i then E("--data needs a screen to ask on.",d.error)return end;local aO=256
do
local aR,aQ=pcall(function()return ay.getDataSize()end)if aR and type(aQ)==ab and aQ>0 then aO=aQ end end;local aN=i("Data for the chip (not shown): ",aO,true)if aN==nil or
aN==""then E(Q,d.dim)return end
local aP=i("The same again, to confirm: ",aO,true)if aP~=aN then
E("The two did not match. Nothing was written.",d.error)return end;az=aN end
local aM=ay.getLabel and ay.getLabel()or"(no label)"local aI="(unknown)"
do local aO,aN=pcall(M.getBootAddress)if aO and aN then aI=aN:sub(1,8)..
"..."end end;local aF=nil
do local aO,aN=pcall(require,"kernel.crypto")
if
aO and aN and aN.hash then local aQ,aP=pcall(aN.hash,aw)if
aQ and type(aP)==L and#aP==64 then aF=aP end end end
E(string.format("  Source : %s (%d bytes)",aB,#aw),d.dim)if aF then
E(string.format("  SHA-256: %s",aF),d.dim)else
E("  SHA-256: UNAVAILABLE - integrity cannot be verified",d.warning)end
E(string.format("  EEPROM : %s",aM),d.dim)
E(string.format("  Boot   : %s",aI),d.dim)if az then
E(string.format("  Data   : %d bytes, as typed (not shown)",#az),d.dim)end;local aG
if r then
aG=r("Overwrite this machine's EEPROM with "..
tostring(aB or
"this image").."?"..
"\n\n".."The EEPROM is what starts the computer. If the image is wrong, "..
"the machine will not boot and no software fix will reach it.","flash",{title="Flash EEPROM",severity=Z,yes="Flash",no=X})else aG=(i and i('Type "flash" to confirm: ',16))==
"flash"end
if aG then local aN,aO=pcall(ay.set,aw)
if not aN then
E("Flash failed: "..tostring(aO),d.error)else
E("EEPROM flashed! "..#aw.." bytes written.",d.highlight)
if az then local aP,aQ=pcall(ay.setData,az)if aP then
E("Data field set: "..#az.." bytes.",d.highlight)else
E("The code was written, but the data field was NOT: "..tostring(aQ),d.error)end end
if aE then E("Reboot for changes to take effect.",d.dim)else
E("This chip is not a BIOS: put this computer's own EEPROM back",d.dim)E("before it restarts.",d.dim)end end else E(Q,d.dim)end end
b.users=function(av,E)if not f(E)then return end;if not g then E(Y,d.error)return end
E(string.format(" %-12s %-8s %s","User","Tier","Status"),d.title)E(string.rep("-",34),d.border)
local aw=g.list and g.list()or
g.listUsers and g.listUsers()or{}
for ay,ax in ipairs(aw)do local az=ax.locked and"LOCKED"or"OK"
E(string.format(" %-12s %-8s %s",
ax.username or ax.user or"?",tostring(ax.tier or ax.accessLevel or"?"),az),
ax.locked and d.error or d.dim)end end;local function x()if not g then return"root"end;local E=g.getSession(n)return
(E and E.user)or"root"end
b.useradd=function(av,E)if
not o(E)then return end;if not g then E(Y,d.error)return end;local aw=av[1]if not aw then
E("Usage: useradd <username>",d.dim)return end
local ax=i("Password for "..aw..": ",64,true)if not ax or ax==""then E(Q,d.dim)return end
local ay=i("Confirm password: ",64,true)
if ay~=ax then E("Passwords do not match.",d.error)return end;local az,aA=g.create(x(),aw,ax,1)
if az then
a.lastOut={"User '"..aw.."' created.",d.highlight}else a.lastOut={tostring(aA),d.error}end end
b.userdel=function(av,E)if not o(E)then return end;if not g then E(Y,d.error)return end
local aw=av[1]
if not aw then E("Usage: userdel <username>",d.dim)return end;local ax
if q then
ax=q("Delete the account '"..
aw.."'?\n\n"..
"Their home directory and files are NOT removed, but the account ".."cannot be recovered from here.",{title="Delete user",severity=Z,yes="Delete",no=X})else
local aA=i("Delete '"..aw.."'? [y/N]: ",1,false)ax=(aA=="y"or aA=="Y")end;if not ax then E(Q,d.dim)return end;local ay,az=g.delete(x(),aw)
if ay then
a.lastOut={
"User '"..aw.."' deleted.",d.highlight}else a.lastOut={tostring(az),d.error}end end
b.usermod=function(av,E)if not o(E)then return end;if not g then E(Y,d.error)return end
local ay,az=av[1],av[2]if not ay or not az then
E("Usage: usermod <username> lock|unlock|admin|user|root",d.dim)return end;local aA=x()local aw,ax
if az=="lock"then
if
g.setLocked then aw,ax=g.setLocked(aA,ay,true)else aw,ax=false,"setLocked unavailable"end
if aw then
a.lastOut={"'"..ay.."' locked.",d.highlight}else a.lastOut={tostring(ax),d.error}end elseif az=="unlock"then if g.setLocked then aw,ax=g.setLocked(aA,ay,false)else
aw,ax=false,"setLocked unavailable"end
if aw then
a.lastOut={"'"..ay.."' unlocked.",d.highlight}else a.lastOut={tostring(ax),d.error}end elseif az=="admin"then if ay:lower()==aj then
E("Failure. Did you mean 'usermod computer root'?",d.error)return end;if g.setTier then
aw,ax=g.setTier(aA,ay,2)else aw,ax=false,ao end;if aw then a.lastOut={"'"..
ay.."' promoted to admin.",d.highlight}else
a.lastOut={tostring(ax),d.error}end elseif az=="root"then
if
ay:lower()==aj and a.D and
not(_G._TOS and _G._TOS._takeoverFired)then _G._TOS=_G._TOS or{}
_G._TOS._takeoverFired=true;local aC,aB=pcall(require,"shell.panels.takeover")
if
aC and aB and aB.run then local aD,aE=pcall(aB.run,a)
if a.D.invalidate then pcall(a.D.invalidate)end
pcall(function()
_G._TOS.logObj.info("kernel","The computer briefly reconsidered its priorities ("..
tostring(aD and aE or"?")..")")end)a.lastOut={"Access control updated.",d.dim}return end end
if g.setTier then aw,ax=g.setTier(aA,ay,3)else aw,ax=false,ao end
if aw then
a.lastOut={"'"..ay.."' promoted to root.",d.highlight}else a.lastOut={tostring(ax),d.error}end elseif az=="user"then
if g.setTier then aw,ax=g.setTier(aA,ay,1)else aw,ax=false,ao end
if aw then
a.lastOut={"'"..ay.."' set to user.",d.highlight}else a.lastOut={tostring(ax),d.error}end else E("Unknown action: "..az,d.error)
E("Valid: lock, unlock, admin, user",d.dim)end end
b.lsdev=function(av,E)
E(string.format(" %-16s %-10s %s","Type","Address","Info"),d.title)E(string.rep("-",46),d.dim)local aw=0
for ax,ay in K.list()do local az=""
if ay==_ then
local aB,aA=pcall(K.proxy,ax)
if aB and aA then
local aC=aA.getLabel and aA.getLabel()or""local aD=
aA.spaceTotal and math.floor(aA.spaceTotal()/1024)or 0
az=(aC~=""and
'"'..aC..'" 'or"")..aD.."K"end elseif ay=="modem"then local aB,aA=pcall(K.proxy,ax)
if aB and aA and aA.isWireless then az=
aA.isWireless()and"wireless"or"wired"end elseif ay=="drive"then local aB,aA=pcall(K.proxy,ax)
if aB and aA and aA.getCapacity then az="raw "..
math.floor((
aA.getCapacity()or 0)/1024).."K"end elseif ay=="openprinter"then local aB,aA=pcall(K.proxy,ax)
if aB and aA then local function aC(aD)
if aD==nil then return"?"end;local aF,aE=pcall(aD)
return(aF and tonumber(aE))and
tostring(math.floor(aE))or"?"end
az="paper "..
aC(aA.getPaperLevel).." ink "..
aC(aA.getBlackInkLevel).."/"..aC(aA.getColorInkLevel)end end
E(string.format(" %-16s %s  %s",ay,ax:sub(1,8).."...",az),d.fg)aw=aw+1 end
if aw==0 then E("  (no peripherals detected)",d.dim)end end;b.devices=b.lsdev
b.mount=function(av,E)
if av[1]and av[2]then if not f(E)then return end
local ay,aB=av[1],av[2]local ax={}local aw={}
for aH in K.list(_)do
if aH:sub(1,#ay)==ay then aw[#aw+1]=aH else
local aJ,aI=pcall(K.proxy,aH)if aJ and aI and aI.getLabel and aI.getLabel()==ay then ax[#ax+
1]=aH end end end;local az=nil
if#aw==1 then az=aw[1]elseif#aw>1 then table.sort(aw)
E(string.format("Ambiguous address prefix '%s' matches %d devices (%s, ...); use a longer prefix",ay,
#aw,aw[1]:sub(1,8).."..."),d.error)return end
if not az and#ax>0 then table.sort(ax)az=ax[1]
if#ax>1 then
E(string.format("Note: %d disks share label '%s'; mounting %s (use partial address to disambiguate)",
#ax,ay,az:sub(1,8).."..."),d.warning)end end
if not az then E("Device not found: "..ay,d.error)return end
local aA=aB:sub(1,1)=="/"and aB or("/"..aB)local aC,aD=pcall(K.proxy,az)if not aC then
E("Cannot proxy device",d.error)return end;if not e.exists(aA)then
pcall(e.makeDirectory,aA)end;local aE=J.sessionOf(a)
local aF,aG=e.mount(aA,aD,aE)
if aF==false then E(tostring(aG or ai),d.error)return end;a.lastOut={"Mounted at "..aA,d.highlight}else
local ax=e.mounts()
E(string.format(" %-18s %-14s %s","Mount","Label","Space"),d.title)E(string.rep("-",46),d.dim)
for az,ay in ipairs(ax)do
local aA=ay.total and math.floor(
ay.total/1024)or 0
local aB=ay.used and math.floor(ay.used/1024)or 0
E(string.format(" %-18s %-14s %dK/%dK",(ay.mountPoint or"?"):sub(1,18),(
ay.label or""):sub(1,14),aB,aA),d.fg)end;local aw=0;for ay in K.list("drive",true)do aw=aw+1 end
if aw>0 then E("",d.dim)
E(aw..
" unmanaged (raw) drive(s) are attached and NOT listed above:",d.warning)
E("they hold no filesystem yet, so there is nothing to mount.",d.dim)E("  drive list           see them",d.dim)
E("  drive format <addr>  make one a TBFS filesystem",d.dim)
E("  drive mount <addr>   then mount it here",d.dim)end end end
b.umount=function(E,av)
if not E[1]then av("Usage: umount <mountpoint>",d.dim)return end;if not f(av)then return end;local aw=E[1]:sub(1,1)=="/"and E[1]or
("/"..E[1])local ax=J.sessionOf(a)
local ay,az=e.unmount(aw,ax)if ay then a.lastOut={"Unmounted "..aw,d.highlight}else
a.lastOut={tostring(az or
"Failed to unmount"),d.error}end end
b.jbod=function(av,E)local aw=h.getJBOD and h.getJBOD()
if not aw then
E("JBOD is disabled. Enable it with: bootsettings jbod on  (then reboot)",d.warning)
E("It pools several disks into one mount. See 'man jbod'.",d.dim)return end;local ax=(av[1]or"list"):lower()
local function ay(az)local aA,aB={},{}
for aC in
K.list(_)do
if aC:sub(1,#az)==az then aA[#aA+1]=aC else local aE,aD=pcall(K.proxy,aC)if
aE and aD and aD.getLabel and aD.getLabel()==az then
aB[#aB+1]=aC end end end;table.sort(aA)table.sort(aB)
if#aA==1 then return aA[1]end;if#aA==0 and#aB==1 then return aB[1]end;if#aA>1 then return nil,
"ambiguous address prefix: "..az end;if#aB>1 then return nil,
"ambiguous label: "..az end
return nil,"no filesystem matches: "..az end
if ax=="list"or ax==N then
local aA=aw.loadConfig(e)or{pools={}}local az=aA.pools or{}if#az==0 then
E("No JBOD pools configured.",d.dim)end
for aC,aB in ipairs(az)do local aD=0
for aC,aE in ipairs(aB.members or{})do for aF in
K.list(_)do if aF==aE then aD=aD+1;break end end end
E(string.format(" %-16s %d member(s), %d present",aB.mount,# (aB.members or{}),aD),d.fg)end
E("Free space: df  ·  individual disks: disk  ·  manage: jbod create|destroy",d.dim)elseif ax=="create"then if not f(E)then return end;local az=av[2]
if not az or not av[3]then
E("Usage: jbod create <mountpoint> <disk> [disk...]",d.dim)
E("  <disk> = fs address prefix or label (see lsdev)",d.dim)return end;if az:sub(1,1)~="/"then az="/"..az end;az=
(e.normalize and e.normalize(az))or az;if not
(az:sub(1,6)=="/mnt/"and#az>6)then
E("JBOD mount point must be under /mnt/  (e.g. jbod create /mnt/pool ...)",d.error)return end;local aD=_G._TOS and
_G._TOS.bootAddr;local aC,aB={},{}
for aI=3,#av do local aJ,aL=ay(av[aI])if not aJ then
E(tostring(aL),d.error)return end
if aD and aJ==aD then
E("Refusing to pool the BOOT disk ("..
aJ:sub(1,8).."...).",d.error)
E("It would expose the system files inside the pool. Use data disks.",d.dim)return end;local aM,aK=pcall(K.proxy,aJ)if not aM or not aK then
E("Cannot open disk: "..av[aI],d.error)return end;aC[#aC+1]=aK
aB[#aB+1]=aJ end;pcall(e.makeDirectory,"/mnt")
pcall(e.makeDirectory,az)local aE=aw.makePool(aC)local aF=J.sessionOf(a)
local aG,aH=e.mount(az,aE,aF)
if not aG then E(tostring(aH or ai),d.error)return end;local aA=aw.loadConfig(e)or{pools={}}
aA.pools=aA.pools or{}for aI=#aA.pools,1,-1 do if aA.pools[aI].mount==az then
table.remove(aA.pools,aI)end end;aA.pools[
#aA.pools+1]={mount=az,members=aB}
aw.saveConfig(e,aA)
a.lastOut={string.format("JBOD pool at %s (%d disks)",az,#aB),d.highlight}elseif ax=="destroy"or ax==ac then if not f(E)then return end;local az=av[2]if not az then
E("Usage: jbod destroy <mountpoint>",d.dim)return end
if az:sub(1,1)~="/"then az="/"..az end;local aC=J.sessionOf(a)e.unmount(az,aC)
local aA=aw.loadConfig(e)or{pools={}}local aB=false
for aD=# (aA.pools or{}),1,-1 do if aA.pools[aD].mount==az then
table.remove(aA.pools,aD)aB=true end end;if aB then aw.saveConfig(e,aA)end
a.lastOut={aB and
("Destroyed JBOD pool "..az)or("No JBOD pool at "..az),
aB and d.highlight or d.warning}else
E("Usage: jbod [list | create <mount> <disk...> | destroy <mount>]",d.dim)end end
b.netfs=function(av,E)local az,aw=J.requireRoomy(a,"kernel.netfs","admin")if not az or
not aw then E(J.loadFailure("netfs",aw),d.error)
return end
local ax=(av[1]or N):lower()
local function ay()local aA={}for aC,aB in ipairs(e.mounts()or{})do
if type(aB.address)==L and
aB.address:sub(1,6)=="netfs:"then aA[#aA+1]=aB end end
table.sort(aA,function(aB,aC)return
aB.mountPoint<aC.mountPoint end)return aA end
if ax==N or ax=="list"then
local aA=aw.isEnabled and aw.isEnabled()
local aB=aw.getExports and aw.getExports()or{}
local aD=m and m.getServiceArm and m.getServiceArm("netfsd")
E("Serving: "..
(
aA and"yes"or aD and"no (export file rejected; see: netfs exports)"or"no (service netfsd is not running)"),
aA and d.highlight or d.warning)
if#aB==0 then
E("  No exports configured ("..aw.EXPORTS_PATH..").",d.dim)else for aF,aE in ipairs(aB)do
E(string.format("  %-12s %-24s %s  %d peer rule(s)",aE.name,aE.path,aE.mode,# (aE.allow or{})),d.fg)end end;local aC=ay()E("",d.fg)
if#aC==0 then E("Mounted: none",d.dim)else
E("Mounted:",d.fg)
for aF,aE in ipairs(aC)do local aG=(aE.total or 0)>0
E(string.format("  %-16s %-22s %s",aE.mountPoint,aE.label,

aG and s(aE.total- (aE.used or 0)).." free"or"unreachable"),
aG and d.fg or d.warning)end end
E("Manage: netfs mount <host> <share> <mountpoint> · netfs umount <mountpoint>",d.dim)elseif ax=="exports"then local aB,aC=aw.loadExports(e)if not aB then
E("Export file rejected: "..tostring(aC),d.error)
E("Nothing is served while the file is invalid.",d.dim)return end
local aA=aw.getExports()
if#aA==0 then
E("No exports in "..aw.EXPORTS_PATH,d.dim)
E("Format: { { name=\"pub\", path=\"/srv/pub\", mode=\"ro\", allow={\"<addr>\"} } }",d.dim)return end
for aE,aD in ipairs(aA)do
E(string.format("%-12s %-24s %s",aD.name,aD.path,aD.mode),d.highlight)
for aE,aF in ipairs(aD.allow or{})do E("    allow "..aF,d.dim)end;if# (aD.allow or{})==0 then
E("    allow (none) — this export is unreachable",d.warning)end end
E("Changes take effect on: service restart netfsd",d.dim)elseif ax=="mount"then if not f(E)then return end;local aE,aC,aA=av[2],av[3],av[4]
if not
(aE and aC and aA)then
E("Usage: netfs mount <host> <share> <mountpoint>",d.dim)
E("  <host>  = peer hostname or address prefix (see net peers)",d.dim)
E("  <share> = export name on that machine (ask its operator)",d.dim)return end
if not m then E("Networking is not available.",d.error)return end;local aB=aE;local aF=m.findPeer and m.findPeer(aE)if aF and aF.addr then
aB=aF.addr end
if m.getTrust or m.getProtocol then
local aL,aK=pcall(require,"kernel.net.trust")
if aL and aK and aK.getLevel and aK.LEVEL then
if aK.getLevel(aB)<
aK.LEVEL.TRUSTED then
E("Peer is not TRUSTED — netfs refuses to mount from it.",d.error)
E("Raise trust first (see 'net trust'), then retry.",d.dim)return end end end;if not(aA:sub(1,5)=="/mnt/"and#aA>5)then
E("Mount point must be under /mnt/  (e.g. netfs mount box pub /mnt/box)",d.error)return end
local aD=aw.attach(aB,aC)
local aG=aD.spaceTotal and aD.spaceTotal()or 0
if not aD.exists("/")and aG==0 then
E("Cannot reach share '"..aC.."' on "..
tostring(aB):sub(1,8)..".",d.error)
E("Check the export name, and that netfsd runs there and allows this machine.",d.dim)return end;pcall(e.makeDirectory,"/mnt")
pcall(e.makeDirectory,aA)local aH=J.sessionOf(a)local aI,aJ=e.mount(aA,aD,aH)if not aI then
E(tostring(aJ or ai),d.error)return end
E("Mounted "..aC.." from "..tostring(aB):sub(1,8)..
" at "..aA,d.highlight)
E("This mount is only usable while that machine is online.",d.dim)elseif ax=="umount"then if not f(E)then return end;local aA=av[2]if not aA then
E("Usage: netfs umount <mountpoint>",d.dim)return end;local aB=false;for aG,aF in ipairs(ay())do if
aF.mountPoint==aA then aB=true;break end end;if not aB then E(
"No netfs mount at "..aA,d.warning)
E("Use 'netfs status' to list them (plain 'umount' handles local disks).",d.dim)return end
local aC=J.sessionOf(a)local aD,aE=e.unmount(aA,aC)if aD then
E("Unmounted "..aA,d.highlight)else
E(tostring(aE or"Failed to unmount"),d.error)end else
E("Usage: netfs [status | exports | mount <host> <share> <mount> | umount <mount>]",d.dim)end end
b.theme=function(av,E)local aw=_G._TOS and _G._TOS.theme;if not aw then
E("Theme manager unavailable (T1 / monochrome or low-RAM boot)",d.warning)return end
do
local aB=(av[1]or"show"):lower()
local aC={list=true,ls=true,show=true,current=true,keys=true,[""]=true}local aD={color=true,colour=true}
if aD[aB]then if not f(E)then return end elseif not aC[aB]then if
J.liveTier(a)<1 then
E("Log in as a user to set a personal theme.",d.error)return end end end
local function aA(aB)if not aB then return nil end
if type(aB)~=L or#aB>16 then return nil end;local aC=aB:match("^0[xX](%x+)$")or aB:match("^#(%x+)$")or
aB:match("^(%x+)$")if aC and#
aC<=6 then return tonumber(aC,16)end
return tonumber(aB)end;local function az(aB)return string.format("0x%06X",aB)end;local ax=
av[1]and av[1]:lower()or"show"
local ay=J.sessionOf(a)
if ax=="list"or ax=="ls"then E("Available themes:",d.title)for aC,aB in
ipairs(aw.list())do
local aD=(aB==aw.current().preset)and" *"or"  "
E(string.format(" %s %-10s %s",aD,aB,aw.describe(aB)or""),d.fg)end
E("",d.fg)
E("'*' = currently active.  Use 'theme set <name>' to switch.",d.dim)elseif ax=="show"or ax=="current"then local aB=aw.current()
E("Active theme: "..aB.preset,d.title)
E("  ".. (aw.describe(aB.preset)or""),d.dim)local aC=0;for aD in pairs(aB.overrides)do aC=aC+1 end
if aC==0 then
E("No color overrides.",d.dim)else E("Overrides:",d.highlight)for aD,aE in pairs(aB.overrides)do
E(string.format("  %-14s %s",aD,az(aE)),d.fg)end end;E("",d.fg)
E("Try: theme set <name>  |  theme color <key> <0xRRGGBB>  |  theme reset",d.dim)elseif ax=="set"or ax=="use"then local aB=av[2]if not aB then
E("Usage: theme set <name>  (theme list to see names)",d.warning)return end;local aC,aD=aw.apply(aB)
if
not aC then E(aD or"apply failed",d.error)return end;E("Applied theme: "..aB,d.highlight)
if ay then
local aE,aF=aw.saveForUser(ay)if not aE then
E("(not saved: "..tostring(aF)..")",d.dim)end end;c.drawAll()elseif ax=="preview"or ax=="try"then local aB=av[2]if not aB then
E("Usage: theme preview <name>",d.warning)return end;local aC,aD=aw.apply(aB)if not aC then
E(aD or"apply failed",d.error)return end
E("Previewing '"..
aB.."' (not saved). Use 'theme set' to keep it.",d.highlight)c.drawAll()elseif ax=="color"or ax=="colour"then local aB,aC=av[2],av[3]if not aB or
not aC then
E("Usage: theme color <key> <0xRRGGBB>",d.warning)
E("Keys: "..table.concat(aw.overridableKeys(),", "),d.dim)return end
if not
aw.isOverridable(aB)then
E("Not an overridable color: "..aB,d.error)
E("Run 'theme color' with no args for the full list.",d.dim)return end;local aD=aA(aC)if not aD then
E("Invalid color value: "..aC.." (try 0xFF8800)",d.error)return end
local aE,aF=aw.setColor(aB,aD)
if not aE then E(aF or"color set failed",d.error)return end
E(string.format("%s = %s",aB,az(aD)),d.highlight)if ay then aw.saveForUser(ay)end;c.drawAll()elseif ax=="reset"then
local aB,aC=aw.resetOverrides()
if not aB then E(aC or"reset failed",d.error)return end
E("Cleared color overrides; preset '"..aw.current().preset.."' restored.",d.highlight)if ay then aw.saveForUser(ay)end;c.drawAll()elseif ax=="clear"or ax==
"default"then
if not ay then E("Not logged in.",d.error)return end;local aB,aC=aw.clearForUser(ay)if not aB then
E(aC or"clear failed",d.error)return end
E("Theme reset to default; saved preference cleared.",d.highlight)c.drawAll()elseif ax=="keys"then
E("Overridable color keys:",d.title)
for aC,aB in ipairs(aw.overridableKeys())do E("  "..aB,d.fg)end else
E("Usage: theme <list|show|set|preview|color|reset|clear|keys>",d.warning)
E("  list                  Show available themes",d.dim)
E("  show                  Show active theme + overrides",d.dim)
E("  set <name>            Apply preset and save for this user",d.dim)
E("  preview <name>        Apply preset without saving",d.dim)
E("  color <key> <0xRGB>   Override a single color",d.dim)
E("  keys                  List overridable color keys",d.dim)
E("  reset                 Drop overrides, keep preset",d.dim)
E("  clear                 Wipe saved theme, revert to default",d.dim)end end;b.colors=b.theme
b.service=function(E,av)if not f(av)then return end
local ax,aw=J.requireRoomy(a,"kernel.rc","admin")if not ax then av(J.loadFailure("service",aw),d.error)
return end
if not E[1]then local ay=aw.list()if#ay==0 then
av("No services registered",d.dim)return end
av(string.format(U,"Service","Status"),d.title)av(string.rep("-",28),d.dim)
for aA,az in ipairs(ay)do
local aB=
az.running and"running"or
(az.unavailable and("not loaded: "..az.unavailable))or
(az.enabled==false and ak)or"stopped"
av(string.format(U,az.name:sub(1,16),aB),
az.running and d.highlight or d.dim)end elseif E[1]=="start"and E[2]then local ay,az=aw.start(E[2])
av(
ay and"Started: "..E[2]or tostring(az),ay and d.highlight or d.error)
if ay then local aB,aA=pcall(require,"kernel.pkg")
if
aB and type(aA)=="table"and aA.noteServiceStarted then
local aC=aA.noteServiceStarted(E[2],{session=J.sessionOf(a)})if aC then
av("Package '"..aC.."' enabled with it.",d.dim)end end end elseif E[1]=="stop"and E[2]then local ay,az=aw.stop(E[2])
av(
ay and"Stopped: "..E[2]or tostring(az),ay and d.highlight or d.error)else av("Usage: service [start|stop <name>]",d.dim)end end
b.cron=function(av,E)if not f(E)then return end
if _G._TOS and _G._TOS.cronDisabled then
E("Cron is off in this boot profile: no job runs.",d.warning)local aA=e.readFile("/etc/cron.dat")
local aD,aB=pcall(require,"kernel.serialize")local aC,az=false,nil;if aA and aD and aB then
aC,az=pcall(aB.decode,aA,{maxBytes=65536})end;local ay={}
if aC and type(az)=="table"and
type(az.jobs)=="table"then for aF,aE in pairs(az.jobs)do
if type(aE)=="table"then ay[
#ay+1]={id=aF,name=tostring(aE.name)}end end end
table.sort(ay,function(aE,aF)return tostring(aE.id)<tostring(aF.id)end)
if#ay>0 then
E(#ay.." saved job(s), which run again after a normal boot:",d.dim)for aF,aE in ipairs(ay)do
E(string.format(" %-4s %s",tostring(aE.id),aE.name),d.dim)end end
if av[1]and av[1]~="list"then
E("cron: jobs cannot be changed in this boot profile; boot normally to edit them."..
"  [E-404 ERR_SAFE_MODE]",d.error)end;return end;local ax,aw=J.requireRoomy(a,"kernel.cron","admin")if not ax then
E(J.loadFailure("cron",aw),d.error)return end
if not av[1]or av[1]=="list"then
local ay=aw.list()
if#ay==0 then E("No scheduled jobs",d.dim)return end
E(string.format(" %-4s %-16s %-8s %s","ID","Name","Every","Enabled"),d.title)
for aA,az in ipairs(ay)do
E(string.format(" %-4d %-16s %-8s %s",az.id,az.name:sub(1,16),az.interval.."s",az.enabled and
"yes"or"no"),
az.enabled and d.fg or d.dim)end elseif av[1]=="add"and av[2]and av[3]and av[4]then
local ay=av[2]local az=tonumber(av[3])local aA=table.concat(av," ",4)if not az then
E("Invalid interval",d.error)return end;local aB=aw.add(ay,az,aA)E("Added job #"..
aB..": "..ay,d.highlight)elseif av[1]=="rm"and
av[2]then local ay=tonumber(av[2])
if ay then local az,aA=aw.remove(ay)if az then
E("Removed job #"..ay,d.highlight)else
E("cron rm: "..tostring(aA or"no such job"),d.error)end else
E("Invalid ID",d.error)end else
E("Usage: cron [list|add <name> <seconds> <script>|rm <id>]",d.dim)end end end