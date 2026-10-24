
local ac,ad,T,ae,N,U,O,R,P,Q,S,V,W,af,ag,ah,K,ai,aj,M,ak,al,X,Y,am,Z,_,aa,an,ab,ao="computer","version"," %-16s %s","From repos nobody configured: ","Refused: ","remove","Aborted.","kernel.pkgsign","--allow-unverified","--allow-unsigned","--force","--dry-run","--dryrun","  %-20s %s -> %s","(--dry-run: nothing was changed)","install","string","floppy","Error: ","status","repair","shell.panels.tabs","number","kernel.log","Cannot read: ","danger","Cancel","No user system","setTier unavailable","filesystem","Mount failed"local L=require(ac)local J=require("component")
local I=require("shell.panels.helpers")
return
function(b,a,c)local h,G,t,e,j,g=a.K,a.E,a.P,a.F,a.D,a.U;local H,m,n=a.SC,a.NM,a.st;local d=a.T;local ap=a.tier
local l,k=a.W,a.H;local u=c.rp;local y=c.openViewTab;local C=c.openEditTab;local D=c.refreshBrowser
local aq=c.canRead;local ar=c.canWrite;local as=c.canAccess;local o=c.rootOnly;local f=c.adminOnly
local v=c.makeProgramEnv;local s=I.fmtSz
local at=function(E)return I.expandBuf(a,E)end;local i=c.promptInput;local q=c.confirm;local r=c.confirmTyped
b.kill=function(au,E)
if not f(E)then return end
if not au[1]then E("Usage: kill <pid>",d.dim)return end;local av=tonumber(au[1])
if av then local aw,ax=t.kill(av)
if aw then
E("Killed PID "..av,d.highlight)else E(tostring(ax),d.error)end else E("Invalid PID",d.error)end end
b.fg=function(au,E)if not f(E)then return end
if not au[1]then E("Usage: fg <pid>",d.dim)return end;local av=tonumber(au[1])if not av or not t.get(av)then
E("No such process",d.error)return end
local aw,ax=t.setForeground(av,a.displayIdx)if not aw then
E(tostring(ax or"Cannot foreground that process"),d.error)return end
E("Foreground: PID "..av,d.highlight)end
b.verify=function(au,E)if not f(E)then return end;local av=au and au[1]and
tostring(au[1]):lower()
if av=="anchor"then local ay=false
for aB=2,#au do
local aC=tostring(au[aB]):lower()if aC=="--clear"or aC=="clear"then ay=true end end
if ay then if not h.clearManifestAnchor then
E("This TOS build cannot clear the anchor.",d.error)return end
local aB,aC=h.clearManifestAnchor()
if aB then
E("Manifest anchor cleared. `doctor` will report it un-anchored.",d.highlight)else
E("Could not clear the anchor: "..tostring(aC),d.error)end;return end;if not h.anchorManifestHash then
E("This TOS build has no manifest anchoring.",d.error)return end
E("Anchoring records THIS system's manifest hash in the EEPROM.",d.dim)
E("Only do it on a system you trust (fresh install, or verified).",d.dim)local aA,az=h.anchorManifestHash()
if aA then
E("Anchored: "..
tostring(az):sub(1,32).."...",d.highlight)
E("Your boot address was preserved; changing the boot device clears it.",d.dim)else
E("Anchor failed: "..tostring(az),d.error)end;return end
E("=== File integrity (every system file vs the manifest) ===",d.title)
E("Checking presence, syntax, and declared hashes...",d.dim)E("")
local aw,ax=pcall(h.verifySystem,function(ay,az)E(ay,az)end)
if not aw then E("verify: "..tostring(ax),d.error)end;E("")
E("This checks FILES. For runtime health (memory/power/services), run 'doctor'.",d.dim)
E("It compares against the MANIFEST. To catch a file that changed since you",d.dim)
E("knew the system was good — and to put it back — use 'srm scan' / 'srm repair'.",d.dim)end;local z=1280
local p={tofu="trusted keys, or a new key you approve; never unsigned.",trusted="trusted keys only.",off="nothing; configured repos only."}
local function w(au,E,av)local aw=tostring(au)
if not
(aw:find("not enough memory",1,true)or
aw:find("not enough free memory",1,true)or aw:find("Out of memory",1,true))then return end
local ax=math.floor(
(L.totalMemory and L.totalMemory()or 0)/1024)
if ax<z then
E(string.format("%s needs %d KB of RAM; this machine has %d KB.",av,z,ax),d.dim)else
E("Something else is holding the memory it needs: close other tabs or ".."programs, or reboot, and try again.",d.dim)end end
b.pkg=function(au,E)if not f(E)then return end
local ay,av=I.requireRoomy(a,"kernel.pkg","admin")if not ay or not av then local az=I.loadFailure("pkg",av)E(az,d.error)
w(az,E,"The package manager")return end;local aw=au[1]
local function ax(az,aA)local aB=2
while
aB<=#au do local aC=tostring(au[aB])
if az[aC]=="value"then aB=aB+1 elseif
aC:sub(1,2)=="--"and not az[aC]then
E(string.format("pkg %s: unknown option '%s' -- nothing was done.",tostring(aw),aC),d.error)E("Options: "..aA,d.dim)return true end;aB=aB+1 end;return false end
if not aw or aw=="list"then local az=av.list()if#az==0 then
E("No packages installed.",d.dim)return end
E(string.format(" %-24s %-10s %s","name",ad,"kind"),d.title)for aB,aA in ipairs(az)do
E(string.format(" %-24s %-10s %s",aA.name:sub(1,24),(aA.version or"?"):sub(1,10),
aA.kind or"?"),d.fg)end elseif
aw=="search"or aw=="available"then
local az=av.listAllAvailable({includeRemote=true})
if#az==0 then E("No packages available.",d.dim)
E("Looked on disk under /usr/repo, /var/repo and /mnt/*",d.dim)local aB=av.repos and av.repos()or{}
if#aB==0 then
E("No remote repos are configured — add one with:",d.dim)
E("  pkg repo add <name> <https://host/path>",d.dim)else
E(#aB.." remote repo(s) configured but none answered.",d.dim)
E("That usually means no internet card, or the host is",d.dim)
E("unreachable. `pkg repo list` shows what is configured.",d.dim)end;return end
table.sort(az,function(aB,aC)
if
(aB.category or"misc")~= (aC.category or"misc")then return
(aB.category or"misc")< (aC.category or"misc")end;return(aB.name or"")< (aC.name or"")end)
E(string.format(" %-20s %-10s %s","name",ad,"source"),d.title)local aA=nil
for aC,aB in ipairs(az)do local aD=aB.category or"misc"if aD~=aA then aA=aD
E("  ["..aD.."]",d.dim)end
local aE=aB.remote and
("repo:"..tostring(aB.repo or"?"))or tostring(aB.root or"?")
E(string.format(" %-20s %-10s %s",(aB.name or"?"):sub(1,20),(aB.version or"?"):sub(1,10),aE),d.fg)end elseif aw=="trust"then local az=(au[2]or"list"):lower()
if
az=="list"then local aA=av.trustList()
if#aA==0 then
E("No publisher keys are trusted on this machine.",d.dim)
E("Every package therefore reads as unsigned or as signed-by-an-",d.dim)
E("unknown-key, and your admin privilege is the only gate.",d.dim)
E("Add one:  pkg trust add <name> <64-hex-key>",d.dim)else
E(string.format(T,"name","fingerprint"),d.title)for aC,aB in ipairs(aA)do
E(string.format(T,aB.label:sub(1,16),aB.fingerprint),d.fg)end;E("",d.dim)
E("Compare a fingerprint with the publisher over a channel that is",d.dim)
E("NOT the disk it came on. A key that arrives with the package it",d.dim)E("signs proves nothing at all.",d.dim)end
E(string.format("Unsigned packages are currently %s.",av.trustRequired()and"REFUSED"or
"allowed (admin gate only)"),
av.trustRequired()and d.highlight or d.dim)
E(ae..p[av.discoveredPolicy()].."  (pkg trust discovered)",d.dim)elseif az=="discovered"then local aA=(au[3]or""):lower()if aA==""then E(ae..
p[av.discoveredPolicy()],d.fg)
E("Usage: pkg trust discovered tofu|trusted|off",d.dim)return end
if not p[aA]then
E("Usage: pkg trust discovered tofu|trusted|off",d.dim)E("  tofu     "..p.tofu,d.dim)
E("  trusted  "..p.trusted,d.dim)E("  off      "..p.off,d.dim)return end
local aB,aC=av.trustDiscovered(aA,{session=I.sessionOf(a)})
if not aB then E(N..tostring(aC),d.error)return end;E(ae..p[aA],d.highlight)elseif az=="add"then
if
not(au[3]and au[4])then
E("Usage: pkg trust add <name> <64-hex-public-key>",d.dim)
E("<name> is YOUR label for the publisher — it is how you will",d.dim)
E("refer to them locally, and has nothing to do with whatever",d.dim)E("name their disk claims.",d.dim)return end
local aA,aB=av.trustAdd(au[3],au[4],{session=I.sessionOf(a)})
if not aA then E(N..tostring(aB),d.error)return end;E("Trusted '"..au[3].."'.",d.highlight)
E("Packages signed by this key will now install without a fresh",d.dim)
E("judgement call. That is the point, and the cost.",d.dim)elseif az==U or az=="rm"then if not au[3]then
E("Usage: pkg trust remove <name>",d.dim)return end
local aA,aB=av.trustRemove(au[3],{session=I.sessionOf(a)})
if not aA then E(N..tostring(aB),d.error)return end
E("Removed '"..au[3].."'. Already-installed packages are",d.highlight)
E("unaffected — this changes what will be accepted from now on.",d.dim)elseif az=="require"then local aA=(au[3]or""):lower()
if
aA~="on"and aA~="off"then E("Usage: pkg trust require on|off",d.dim)
E("`on` refuses unsigned packages outright. Consider what is on",d.dim)
E("your Optional Utilities disks before turning it on.",d.dim)return end
local aB,aC=av.trustRequire(aA=="on",{session=I.sessionOf(a)})
if not aB then E(N..tostring(aC),d.error)return end
E("Unsigned packages are now "..
(aA=="on"and"REFUSED."or"allowed."),d.highlight)elseif az=="key"then
if not au[3]then
E("Usage: pkg trust key <publisher-label>",d.dim)
E("Prints the public key you sign as under that label, and asks",d.dim)
E("for the passphrase without echoing it. Publish the key; never",d.dim)
E("the passphrase. The label is part of the key: the same",d.dim)
E("passphrase under a different label is a different identity.",d.dim)return end
if au[4]then
E("Too many arguments. Only the publisher label goes here — the",d.error)
E("passphrase is asked for separately, and must never be typed",d.dim)
E("on the command line where it is echoed and recalled.",d.dim)return end;if not i then
E("This needs an interactive prompt for the passphrase.",d.error)return end
local aA=i("Signing passphrase: ",96,true)if not aA or aA==""then E(O,d.dim)return end
local aB,aD=av.signingKey(aA,au[3])if not aB then E(tostring(aD),d.error)return end
E(aB,d.highlight)local aE,aC=pcall(require,R)if aE and aC then
E("fingerprint "..aC.fingerprint(aB),d.dim)
E("signing as '"..tostring(aC.normalizeLabel(au[3])).."'",d.dim)end else
E("Usage: pkg trust [list|add|remove|require|key] ...",d.dim)end elseif aw=="verify-sig"or aw=="checksig"then if not au[2]then
E("Usage: pkg verify-sig <directory>",d.dim)
E("Says who signed a package WITHOUT installing it.",d.dim)return end
local az,aA=av.checkSignature(au[2])if not az then E(tostring(aA),d.error)return end
E(
"Package: "..tostring(aA and aA.name or"?"),d.title)local aC,aB=pcall(require,R)
if aC and aB then for aE,aD in ipairs(aB.describe(az))do
E(aD,az.state==
"trusted"and d.highlight or(az.state=="invalid"and d.error or
d.warning))end end elseif aw=="sign"then
if not au[2]then
E("Usage: pkg sign <directory> --as <publisher-name>",d.dim)
E("Signs the package's manifest with a key derived from a",d.dim)
E("passphrase you will be asked for. The signature covers the",d.dim)
E("MANIFEST, which covers the file hashes, which cover the files —",d.dim)
E("so sign AFTER the hashes are final, not before.",d.dim)return end;local az
for aF=3,#au do if au[aF]=="--as"then az=au[aF+1]end end
if not az or az==""then
E("Usage: pkg sign <directory> --as <publisher-name>",d.error)
E("--as is required: the label salts your signing key, so the same",d.dim)
E("passphrase under a different label is a different identity.",d.dim)
E("Use the same label every time — it is part of who you are.",d.dim)return end;if not i then
E("Signing needs an interactive prompt for the passphrase.",d.error)return end
local aA=i("Signing passphrase: ",96,true)
if not aA or aA==""then local aG,aF=pcall(require,R)
E(string.format("Aborted. A signing passphrase is required (%d+ characters).",
aG and aF and aF.KDF_MIN_PASS or 20),d.dim)
E("It IS the private key — the same passphrase always produces the",d.dim)
E("same key, on any machine, so make it long and keep it.",d.dim)return end
local aB,aC=av.signPackage(au[2],aA,{session=I.sessionOf(a),signer=az})if not aB then
E("Signing failed: "..tostring(aC),d.error)return end
E("Signed. Wrote "..tostring(aC),d.highlight)E("public key "..aB,d.fg)local aE,aD=pcall(require,R)if
aE and aD then
E("fingerprint "..aD.fingerprint(aB),d.dim)end elseif aw=="repo"or aw=="repos"then
local az=(au[2]or"list"):lower()
if az=="list"then local aA=av.repos()
if#aA==0 then
E("No remote repositories configured.",d.dim)
E("Add one:  pkg repo add <name> <https://host/path>",d.dim)
E("The URL is the directory holding the repo's programs.cfg.",d.dim)else
E(string.format(" %-14s %s","name","url"),d.title)
for aD,aC in ipairs(aA)do
E(string.format(" %-14s %s",aC.name:sub(1,14),aC.url),d.fg)if aC.description then
E("                "..aC.description,d.dim)end end;E("",d.dim)
E("This list is the allowlist: what these serve installs like a disk.",d.dim)end;local aB=av.knownRepos()
if#aB>0 then E("",d.dim)
E("Known (named by installed packages; not trusted):",d.title)
for aD,aC in ipairs(aB)do
E(string.format(" %2d %s",aD,aC.url),d.fg)if#aC.from>0 then
E("      from "..table.concat(aC.from,", "),d.dim)end end
E("Read only for what configured repos lack (pkg trust",d.dim)
E("discovered). Forget:  pkg repo forget <number|url|all>",d.dim)end elseif az=="add"then
if not au[3]or not au[4]then
E("Usage: pkg repo add <name> <url> [description]",d.dim)
E("  url = the directory containing programs.cfg",d.dim)return end
local aA=#au>=5 and table.concat(au," ",5)or nil
local aB,aC=av.addRepo(au[3],au[4],aA,{session=I.sessionOf(a)})
if aB then
E("Repo '"..au[3].."' added.",d.highlight)
E("It is now an accepted source of executable code for this",d.warning)
E("machine. 'pkg repo remove "..au[3].."' undoes that.",d.warning)else E(tostring(aC),d.error)end elseif az==U or az=="rm"then if not au[3]then
E("Usage: pkg repo remove <name>",d.dim)return end
local aA,aB=av.removeRepo(au[3],{session=I.sessionOf(a)})
if aA then
E("Repo '"..au[3].."' removed.",d.highlight)else E(tostring(aB),d.error)end elseif az=="forget"then if not au[3]then
E("Usage: pkg repo forget <number|url|all>",d.dim)return end
local aB,aA=av.forgetRepo(au[3],{session=I.sessionOf(a)})
if aB then
E(("Forgot %d known repo(s)."):format(aA or 0),d.highlight)else E(tostring(aA),d.error)end else
E("Usage: pkg repo [list|add <name> <url>|remove <name>|forget <n|url|all>]",d.dim)end elseif aw=="remote"then local az=_G._TOS and _G._TOS.internet
if az and not
az.available()then
E(az.status().reason or"internet is not available",d.warning)E("'internet' shows the details.",d.dim)return end;E("Contacting configured repositories...",d.dim)
local aA=av.searchRemote({refresh=
au[2]=="--refresh"})if#aA==0 then
E("Nothing available. Check 'pkg repo list'.",d.dim)return end
E(string.format(" %-22s %-10s %s","name",ad,"repo"),d.title)
for aC,aB in ipairs(aA)do
E(string.format(" %-22s %-10s %s",(aB.name or"?"):sub(1,22),(
aB.version or"-"):sub(1,10),tostring(aB.repo)),d.fg)if aB.description then
E("   "..tostring(aB.description):sub(1,60),d.dim)end end;E("",d.dim)
E("Install one with:  pkg fetch <name>",d.dim)elseif aw=="fetch"then if ax({[P]=true,[Q]=true},"--allow-unverified --allow-unsigned")then
return end;local aA,aB,aC=nil,false,false
for aF=2,#au do
local aG=tostring(au[aF])if aG==P then aB=true elseif aG==Q then aC=true elseif not aA then aA=aG end end
if not aA then
E("Usage: pkg fetch <name> [--allow-unverified] [--allow-unsigned]",d.dim)
E("Downloads from a configured repo, then installs it.",d.dim)return end;E("Fetching '"..aA.."'...",d.dim)
local function aD(aF)if
not(r and i)then return nil end
local aH="'"..
tostring(aF.name)..
"' is only in a repo this machine was not "..
"configured with:\n  "..

tostring(aF.repo)..
"\n"..
(
aF.by and(tostring(aF.by).." requires it.\n")or"")..

"\nIts signature is valid, but its key is not trusted here:\n  key "..
tostring(aF.fingerprint)..
"\n"..

(aF.signer and
('It calls its publisher "'..tostring(aF.signer)..
'" -- its own word, not proof.\n')or"")..
"\nCompare the fingerprint with the publisher somewhere that is NOT this repo. ".."Trusted, anything signed with this key installs from now on."
if not
r(aH,"trust",{title="A new publisher key",style="warning",yes="Trust",no="Refuse"})then
E("Refused the key "..

tostring(aF.fingerprint).." for '"..tostring(aF.name).."'.",d.dim)return nil end;local aG=i("Name this publisher (Enter refuses): ",48)if aG and
aG~=""then
E("Trusted the key "..
tostring(aF.fingerprint).." as '"..aG.."' (from "..
tostring(aF.repo)..").",d.highlight)end;return aG end
local aE,az=av.installRemote(aA,{session=I.sessionOf(a),allowUnverified=aB,allowUnsigned=aC,confirmKey=aD})
if aE then
local aF=az and az.discovered and
(tostring(az.discovered)..", a repo nobody configured")or("repo '"..
tostring(az and az.repo).."'")
E(string.format("Installed '%s' from %s (%d files, %d bytes).",aA,aF,(az and az.files)or 0,
(az and az.bytes)or 0),d.highlight)local c=az and az.dependencies;if type(c)=="table"and#c>0 then
E(
"  ...and what it requires: "..table.concat(c,", "),d.highlight)end else
E(tostring(az),d.error)
if tostring(az):find("hash",1,true)or
tostring(az):find("unverified",1,true)then E("",d.dim)
E("That repo ships no file hashes, so TOS cannot check what it",d.dim)
E("sent. Re-run with --allow-unverified if you trust it.",d.dim)end end elseif aw=="outdated"or aw=="updates"then local az=av.outdated()
if#az==0 then
E("Everything is up to date (against what's mounted right now).",d.highlight)
E("Insert another disk and re-run to check against it too.",d.dim)return end
E(string.format(" %-20s %-10s %-10s %s","name","installed","available","from"),d.title)
for aB,aA in ipairs(az)do
E(string.format(" %-20s %-10s %-10s %s",aA.name:sub(1,20),tostring(aA.from):sub(1,10),tostring(aA.to):sub(1,10),tostring(
aA.root or"?")),d.fg)end;E("",d.dim)
E("pkg upgrade <name>   or   pkg upgrade --all --yes",d.dim)elseif aw=="upgrade"then
if
ax({["--all"]=true,["--yes"]=true,[S]=true,[V]=true,[W]=true,[P]=true,[Q]=true},"--all --yes/-y --force --dry-run --allow-unverified --allow-unsigned")then return end;local aD,aE,aF,aG=false,false,false,false;local aH,aI=false,false;local aA={}
for aJ=2,#au do
local aK=tostring(au[aJ])
if aK=="--all"then aD=true elseif aK=="--yes"or aK=="-y"then aE=true elseif aK==S then aF=true elseif
aK==V or aK==W then aG=true elseif aK==P then aH=true elseif aK==Q then aI=true elseif aK:sub(1,2)~="--"then aA[#aA+1]=aK end end;local az={}
if aD then
for aK,aJ in ipairs(av.outdated())do az[#az+1]=aJ end elseif#aA>0 then local aJ={}
for aL,aK in ipairs(av.outdated())do aJ[aK.name]=aK end;for aL,aK in ipairs(aA)do
az[#az+1]=aJ[aK]or{name=aK,from="?",to="?"}end else
E("Usage: pkg upgrade <name>… | --all [--yes] [--force] [--dry-run]",d.dim)
E("                   [--allow-unverified] [--allow-unsigned]",d.dim)
E("       pkg outdated   shows what has a newer version available",d.dim)return end
if#az==0 then E("Nothing to upgrade.",d.highlight)return end
if aG then
E(string.format("Would upgrade %d package(s):",#az),d.title)for aK,aJ in ipairs(az)do
E(string.format(af,aJ.name,tostring(aJ.from),tostring(aJ.to)),d.fg)end;E(ag,d.dim)return end
if aD and not aE then
E(string.format("--all would upgrade %d package(s):",#az),d.warning)for aK,aJ in ipairs(az)do
E(string.format(af,aJ.name,tostring(aJ.from),tostring(aJ.to)),d.fg)end
E("Add --yes to proceed.",d.dim)return end;local aB,aC=0,0
for aK,aJ in ipairs(az)do
local aM,aL=av.upgrade(aJ.name,{session=I.sessionOf(a),force=aF,allowUnverified=aH,allowUnsigned=aI})
if aM then aB=aB+1
E(string.format(af,aJ.name,tostring(aL.from),tostring(aL.to)),d.highlight)if aL.dropped and#aL.dropped>0 then
E(string.format("      %d file(s) no longer shipped, removed",#
aL.dropped),d.dim)end
if
aL.enabled==false then E("      (was disabled; left disabled)",d.dim)end else aC=aC+1
E(string.format("  %-20s FAILED: %s",aJ.name,tostring(aL)),d.error)end end
E(string.format("%d upgraded, %d failed.",aB,aC),aC>0 and d.warning or d.highlight)
if aB>0 then
E("Services keep their enabled/disabled state; restart them to run the",d.dim)
E("new code ('service stop <svc>' then 'service start <svc>').",d.dim)end elseif aw=="info"then
if not au[2]then E("Usage: pkg info <name>",d.dim)return end;local az=av.info(au[2])if not az then
E("Not installed: "..au[2],d.error)return end
E(string.format(" name:        %s",az.name),d.title)
E(string.format(" version:     %s",az.version or"?"),d.fg)
E(string.format(" kind:        %s",az.kind or"?"),d.fg)
if az.lua or az.tos then
E(string.format(" needs:       %s%s%s",
az.lua and("Lua "..az.lua.."+")or"",(az.lua and az.tos)and", "or"",
az.tos and("TOS "..az.tos)or""),d.fg)end;if az.category then
E(string.format(" category:    %s",az.category),d.fg)end;if az.description then
E(string.format(" description: %s",az.description),d.fg)end;if az.author then
E(string.format(" author:      %s",az.author),d.fg)end
E(string.format(" status:      %s",
av.isEnabled(az.name)and"enabled"or"disabled"),
av.isEnabled(az.name)and d.highlight or d.dim)
if type(az.commands)=="table"then local aA={}for aB in pairs(az.commands)do
aA[#aA+1]=aB end
if#aA>0 then table.sort(aA)E(" commands:    "..
table.concat(aA,", "),d.fg)end end
if az.requires and#az.requires>0 then E(" requires:",d.fg)
for aB,aA in
ipairs(az.requires)do local aC,aD;if type(aA)=="table"then aC,aD=aA.name,aA.version else
aC,aD=aA:match("^(%S+)%s*(.*)$")end
E(string.format("   %s %s",aC,aD or""),d.dim)end end;if az.provides and#az.provides>0 then
E(" provides:    "..
table.concat(az.provides,", "),d.fg)end;if az.recommends and
#az.recommends>0 then
E(" recommends:  "..table.concat(az.recommends,", "),d.dim)end;if az.conflicts and
#az.conflicts>0 then
E(" conflicts:   "..table.concat(az.conflicts,", "),d.warning)end
if az.origin=="openos"then
E(" origin:      OpenOS/OPPM package (runs on the compat layer)",d.warning)if az.capsFromCompat then
E("              declared no capabilities — granted: "..
table.concat(az.capabilities or{},", "),d.warning)end end
do local n=az._sigState or"unsigned"
if n=="trusted"then
E(string.format(" signature:   signed by trusted publisher '%s'",tostring(az._sigLabel)),d.highlight)elseif n=="unknown"then
E(" signature:   valid, but the key was not trusted at install time",d.warning)else E(" signature:   none (unsigned)",d.dim)end
if az._sigKey then local aB,aA=pcall(require,R)
local aC=
(aB and aA and aA.fingerprint)and aA.fingerprint(az._sigKey)or
az._sigKey:sub(1,16)E("              key "..aC,d.dim)end
E(string.format(" integrity:   %s",
az._unverified and"NOT verified (installed with --allow-unverified)"or"all files matched their declared hashes"),
az._unverified and d.warning or d.dim)end elseif aw==ah or aw=="install-dir"or aw=="from-floppy"or aw==
"fromfloppy"then
if
ax({[P]=true,[Q]=true,[S]=true,["--all"]=true,["--yes"]=true,[V]=true,[W]=true,["--key"]="value",["--prompts"]=true,["--classic"]=true},
"--all --yes/-y --dry-run --force --allow-unverified --allow-unsigned ".."--key <key> --prompts")then return end;local aB,aH,aI,aE=false,false,false,false;local aC,aA=false,false;local aF={}
for aK=2,#au do
local aL=tostring(au[aK])
if aL==P then aB=true elseif aL==Q then aC=true elseif aL==S then aA=true elseif aL=="--all"then aH=true elseif
aL=="--yes"or aL=="-y"then aI=true elseif aL==V or aL==W then aE=true elseif aL=="--key"then elseif au[aK-1]=="--key"then elseif
aL:sub(1,2)~="--"then aF[#aF+1]=aL end end;local aD=aF[1]local function aJ(aK)return
type(aK)==K and aK:find("/",1,true)~=nil end;local az
if aH then az="all"elseif aw==
"install-dir"then az="dir"elseif aw=="from-floppy"or aw=="fromfloppy"then az=ai elseif not aD then
az=ai elseif aJ(aD)then az="dir"elseif#aF>1 then az="many"else az="name"end
local function aG(aK)
if#aK==0 then E("Nothing to install.",d.dim)return end
if aE then
E(string.format("Would install %d package(s):",#aK),d.title)local aN=0
for aP,aO in ipairs(aK)do local aQ,aR
if av.planByName then aQ,aR=av.planByName(aO)end
if not aQ then E("  "..aO,d.fg)if aR then aN=aN+1
E("    would fail: "..tostring(aR),d.error)end else E("  "..aO,d.fg)local aS={}for aP,aT in
ipairs(aQ.order or{})do
aS[#aS+1]=(av.info and av.info(aT))and
(aT.." (installed)")or aT end
if#aS>1 then E("    order: "..
table.concat(aS,", "),d.dim)end;for aP,aT in ipairs(aQ.contradictions or{})do
E("    ! "..tostring(aT.text),d.warning)end
if#
(aQ.contradictions or{})>0 then
if aA then
E("    --force: would install past "..
#aQ.contradictions.." contradiction(s)",d.warning)else aN=aN+1
E("    would be refused (--force overrides)",d.error)end end end end;if aN>0 then
E(string.format("%d of %d would not install as things stand.",aN,#aK),d.warning)end;E(ag,d.dim)return end;local aM,aL=0,0
for aO,aN in ipairs(aK)do
local aQ,aP=av.installByName(aN,{session=I.sessionOf(a),allowUnverified=aB,allowUnsigned=aC,force=aA})
if aQ then aM=aM+1
E(string.format("  %-20s installed%s",aN,
(#aP.skipped>0)and(" (deps present: "..
table.concat(aP.skipped,", ")..")")or""),d.highlight)else aL=aL+1
E(string.format("  %-20s FAILED: %s",aN,tostring(aP)),d.error)end end
E(string.format("%d installed, %d failed.",aM,aL),aL>0 and d.warning or d.highlight)end
if aE and(az=="name"or az=="dir")then aG({aD})return elseif aE and
az==ai then local aK={}for aM,aL in ipairs(av.listAllAvailable()or{})do
if not(av.info and
av.info(aL.name))then aK[#aK+1]=aL.name end end
table.sort(aK)
if#aK==0 then E("Nothing to install.",d.dim)return end
E(string.format("Would offer %d package(s) to choose from:",#aK),d.title)for aM,aL in ipairs(aK)do E("  "..aL,d.fg)end;E(ag,d.dim)
return end
if az=="all"then
if not(aI or aE)then
E("--all installs EVERY package on every inserted disk and repo.",d.warning)
E("Add --yes to confirm, or --dry-run to see the list first.",d.dim)return end;local aK={}for aM,aL in ipairs(av.listAllAvailable()or{})do
if not(av.info and
av.info(aL.name))then aK[#aK+1]=aL.name end end
table.sort(aK)aG(aK)return elseif az=="many"then aG(aF)return end
if az=="name"then local aL;for aN=3,#au do
if au[aN]=="--key"and au[aN+1]then aL=au[aN+1]end end
local aM,aK=av.installByName(aD,{licenseKey=aL,session=I.sessionOf(a),allowUnverified=aB,allowUnsigned=aC,force=aA})
if aM then
E(string.format("Installed: %s",table.concat(aK.installed,", ")),d.highlight)if#aK.skipped>0 then
E(string.format("Skipped (already present): %s",table.concat(aK.skipped,", ")),d.dim)end else
E("Install failed: "..tostring(aK),d.error)w(aK,E,"Installing packages")end elseif az=="dir"then
if not aD then E("Usage: pkg install <dir>",d.dim)return end
local aL,aK=av.install(aD,{session=I.sessionOf(a),allowUnverified=aB,allowUnsigned=aC,force=aA})
if aL then
E("Installed: "..tostring(aK),d.highlight)else
E("Install failed: "..tostring(aK),d.error)w(aK,E,"Installing packages")end else local aL=false;for aO=2,#au do if au[aO]=="--prompts"or au[aO]=="--classic"then
aL=true end end
local aM=false
if not aL and av.runInstaller then
local aP,aO=av.runInstaller({session=I.sessionOf(a),allowUnverified=aB,allowUnsigned=aC,force=aA})
if aP then aM=true
if a.D and a.D.invalidate then pcall(a.D.invalidate)end;if c.drawAll then pcall(c.drawAll)end elseif aO then
E("Menu installer unavailable ("..tostring(aO)..
") — using prompts.",d.dim)end end;if aM then return end
local aN,aK=av.installFromFloppy({session=I.sessionOf(a),allowUnverified=aB,allowUnsigned=aC,force=aA,confirm=function(aR,aQ,aP,aO)
if q then
local aV={title="Install from media",severity=ah,yes="Install",no="Skip",progress=
(aP and aO and aO>1)and{index=aP,total=aO}or nil}if aP and aO and aP<aO then aV.redraw=false end;return
q("Install  "..aR.."?".."\n\n".."From:"..
"\n  "..aQ,aV)end;if not i then return false end
local aT=aQ:match("^(/mnt/[^/]+)")or aQ;local aU=
(aP and aO and aO>1)and string.format(" (%d/%d)",aP,aO)or""local aS=
i("Install "..aR..
" from "..aT..aU.."? [y/N]: ",4)or""return
aS:lower()=="y"or aS:lower()=="yes"end})
if aN then if#aK.installed>0 then
E(string.format("Installed from media: %s",table.concat(aK.installed,", ")),d.highlight)end;if
#aK.skipped>0 then
E(string.format("Skipped: %s",table.concat(aK.skipped,", ")),d.dim)end;if#aK.installed==0 and
#aK.skipped==0 then
E("No packages found on mounted media. Insert a package disk and retry.",d.dim)end else E("Media scan failed: "..
tostring(aK),d.error)end end elseif aw=="license-hash"then if not au[2]or not au[3]then
E("Usage: pkg license-hash <package-name> <license-key>",d.dim)return end
local az,aA=av.computeLicenseHash(au[2],au[3])
if az then E(az,d.fg)else E(aj..tostring(aA),d.error)end elseif aw=="uninstall"or aw==U then if not au[2]then
E("Usage: pkg uninstall <name>",d.dim)return end
local az,aA=av.uninstall(au[2],{session=I.sessionOf(a)})if az then E("Uninstalled: "..au[2],d.highlight)else
E(
"Uninstall failed: "..tostring(aA),d.error)end elseif aw=="make-disk"or
aw=="export-disk"then
if not au[2]then
E("Usage: pkg make-disk <mount> [name ...]",d.dim)
E("  Builds an Optional Utilities disk from your INSTALLED add-ons so",d.dim)
E("  you can install them on another TOS machine without a dev box.",d.dim)
E("  Name args limit the export; omit to include every add-on.",d.dim)E("  e.g. pkg make-disk /mnt/floppy",d.dim)return end;if not av.exportDisk then
E("This TOS build has no make-disk support.",d.error)return end;local aA=nil;if au[3]then aA={}for aC=3,#au do
aA[#aA+1]=au[aC]end end
local aB,az=av.exportDisk(au[2],{only=aA,session=I.sessionOf(a)})
if aB then
E(string.format("Built add-on disk on %s: %d package(s), %d file(s)",az.target,#az.packages,az.files),d.highlight)if#az.packages>0 then
E("  "..table.concat(az.packages,", "),d.fg)end;if#az.problems>0 then
E("  Warnings:",d.warning)
for aD,aC in ipairs(az.problems)do E("   ! "..aC,d.warning)end end
E("On the target machine, insert the disk and run 'pkg install'.",d.dim)else
E("make-disk failed: "..tostring(az),d.error)end elseif aw=="enable"or aw=="disable"then if not au[2]then
E("Usage: pkg "..aw.." <name>",d.dim)return end;local az=(aw=="enable")
local aA,aB=av.setEnabled(au[2],az,{session=I.sessionOf(a)})
if aA then
E((az and"Enabled: "or"Disabled: ")..au[2],d.highlight)else E("Failed: "..tostring(aB),d.error)end elseif aw=="commands"then local aA=av.commands()local az={}
for aB in pairs(aA)do az[#az+1]=aB end;if#az==0 then
E("No commands provided by installed packages.",d.dim)return end;table.sort(az)
E("Commands provided by packages:",d.title)for aC,aB in ipairs(az)do E("  "..aB,d.fg)end else
E("Usage: pkg [list | search | info <name> | install [name|dir] | uninstall <name>",d.dim)
E("           | enable <name> | disable <name> | commands | make-disk <mnt>]",d.dim)
E("  install: a name installs by name; a path installs that dir; no arg",d.dim)
E("           scans mounted media. Shortcuts: 'install <name>', 'uninstall <name>'.",d.dim)
E("  signing: trust [list|add|remove|require|key] · verify-sig <dir> · sign <dir>",d.dim)end end
b.install=function(E,au)local av={ah}for aw=1,# (E or{})do av[#av+1]=E[aw]end;return
b.pkg(av,au)end
b.uninstall=function(E,au)local av={"uninstall"}
for aw=1,# (E or{})do av[#av+1]=E[aw]end;return b.pkg(av,au)end
b.backup=function(au,E)if not f(E)then return end;local av=_G._TOS and _G._TOS.backup
if
not av then E("backup module unavailable",d.error)return end;local aw=au[1]local ax=I.sessionOf(a)
if aw=="snapshot"or aw=="create"then if not
au[2]or not au[3]then
E("Usage: backup snapshot <src> <dest.bak>",d.dim)return end
local az,ay=av.snapshot(au[2],au[3],{session=ax})
if az then
E(string.format("Snapshot OK: %d entries, %d bytes -> %s",ay.entries,ay.bytes,au[3]),d.highlight)
E("  metaHash: "..ay.hash:sub(1,16).."...",d.dim)else
E("Snapshot failed: "..tostring(ay),d.error)end elseif aw=="inspect"then if not au[2]then
E("Usage: backup inspect <file.bak>",d.dim)return end
local ay,az=av.inspect(au[2],{session=ax})if not ay then
E("Inspect failed: "..tostring(az),d.error)return end
E(string.format(" magic:    %s",ay.magic),d.fg)
E(string.format(" created:  %d",ay.created),d.fg)
E(string.format(" entries:  %d",ay.entries),d.fg)
E(string.format(" root:     %s",ay.root),d.fg)
E(string.format(" metaHash: %s...",ay.metaHash:sub(1,24)),d.fg)
E(string.format(" size:     %d bytes",ay.size),d.fg)elseif aw=="restore"then if not au[2]then
E("Usage: backup restore <file.bak> [destRoot] [--force]",d.dim)return end;local az,aA=nil,false
for aC=3,#au do if
au[aC]==S or au[aC]=="-f"then aA=true else az=au[aC]end end
local aB,ay=av.restore(au[2],{session=ax,destRoot=az,force=aA})
if aB then
E(string.format("Restore OK: %d/%d files -> %s",ay.restored,ay.entries,ay.destRoot),d.highlight)D()else
E("Restore failed: "..tostring(ay),d.error)end else
E("Usage: backup [snapshot|inspect|restore] ...",d.dim)E("  backup snapshot <src> <dest.bak>",d.dim)
E("  backup inspect  <file.bak>",d.dim)
E("  backup restore  <file.bak> [destRoot] [--force]",d.dim)end end
b.kiosk=function(au,E)if not f(E)then return end
local aw,av=I.requireRoomy(a,"shell.kiosk","admin")if not aw or not av then
E(I.loadFailure("kiosk",av),d.error)return end
E("Kiosk = the LOCKED, guest-facing menu (allow-list + read-only).",d.title)
E("To test: log out, log in as the 'kiosk' user.",d.dim)E("Config: /etc/kiosk.cfg",d.dim)E("",d.fg)
E("Looking for the OPERATOR menu? Run 'desktop': the same kind of",d.highlight)
E("clickable menu, but it runs real commands at YOUR tier (no allow-list).",d.dim)end
b.doctor=function(au,E)local ax,aw=I.requireRoomy(a,"kernel.diag","admin")if not ax or
not aw then E(I.loadFailure("doctor",aw),d.error)
return end
local ay={ok=d.highlight or d.fg,info=d.dim or d.fg,warn=d.warning or d.fg,err=
d.error or d.fg}local az=au[1]
E("=== TOS doctor \226\128\148 runtime health ===",d.title)
local av=aw.run(function(aC,aD)E(aC,ay[aD]or d.fg)end,{only=az})E("",d.dim)
local aA=string.format("Summary: %d ok, %d info, %d warn, %d err",av.ok,av.info,av.warn,av.err)local aB=av.err>0 and d.error or av.warn>0 and d.warning or
d.highlight
E(aA,aB)
E("This checks RUNTIME health. For a full file-integrity check, run 'verify'.",d.dim)
E("'srm' runs both, plus the known-good baseline check.",d.dim)end;b.diag=b.doctor
b.srm=function(au,E)
local aC,aw=I.requireRoomy(a,"kernel.srm","admin")if not aC or not aw then
E(I.loadFailure("srm",aw),d.error)return end
local az={ok=d.highlight or d.fg,info=d.dim or d.fg,warn=d.warning or d.fg,err=
d.error or d.fg}local function ay(aD)
for aF,aE in ipairs(aD.findings)do E(aE.text,az[aE.sev]or d.fg)end;return aD end
local function aA(aD)local aE=aD.counts
E("",d.dim)
E(string.format("%d ok, %d info, %d warn, %d err%s",aE.ok,aE.info,aE.warn,aE.err,(aD.fixed or 0)>0 and(
"  |  "..aD.fixed.." fixed")or""),
az[aw.worst(aD)]or d.fg)end;local ax,av,aB=aw.parseArgs(au)if av.source==true then
E("--source needs a mount point, e.g. --source /mnt/floppy",d.error)return end
if ax==M then
E("=== SRM \226\128\148 System Repair & Maintenance ===",d.title)aA(ay(aw.status()))E("",d.dim)
E("scan = compare files to the baseline   health = runtime   verify = manifest",d.dim)
E("repair = fix what is safe             baseline = record a known-good system",d.dim)elseif ax=="health"then return b.doctor(aB,E)elseif ax=="verify"then return b.verify(aB,E)elseif
ax=="scan"then
E("=== SRM scan \226\128\148 files vs the known-good baseline ===",d.title)
E("Hashing every baselined file; this takes a moment.",d.dim)aA(ay(aw.scan()))elseif ax=="baseline"then if not f(E)then return end
E("Recording what THIS system looks like right now as the known-good",d.title)
E("baseline. Only do that on a system you trust — a fresh install, or",d.dim)
E("one that just passed 'srm verify'. Anything already wrong becomes",d.dim)E("the new definition of correct.",d.dim)
E("",d.dim)local aE=av.full and true or false
local aF,aD=aw.baseline(nil,{content=aE})if not aF then
E("Baseline failed: "..tostring(aD),d.error)return end
E(string.format("Baseline captured from %s: %d file(s) hashed.",tostring(aD.source),aD.hashed),d.highlight)
if aE then
E(string.format("  %d copy(ies) stored, %.1f KB of disk.",aD.stored,aD.bytes/1024),d.fg)
E("  Local repair is now possible: 'srm repair --restore'.",d.fg)else
E("  Hashes only — drift is detectable, but repair will need",d.fg)
E("  '--source <mount>' (e.g. the install floppy). Use --full to",d.dim)
E("  store verified copies locally instead.",d.dim)end
if aD.skipped>0 then
E(string.format("  %d file(s) skipped (over the %d KB store cap or unreadable).",aD.skipped,aw.MAX_STORE_BYTES/1024),d.warning)end;if aD.pruned>0 then
E(string.format("  %d stale copy(ies) from the previous baseline removed.",aD.pruned),d.fg)end
for aH,aG in ipairs(aD.missing)do E(
"  MISSING at capture time: "..aG,d.warning)end elseif ax=="restore"then if not f(E)then return end
E("=== SRM restore ===",d.title)
aA(ay(aw.restore(nil,{source=type(av.source)==K and av.source or nil,unverified=
av.unverified and true or false,paths=#aB>0 and aB or nil})))elseif ax==ak and av.online then if not f(E)then return end
if av.apply and not o(E)then return end;if av.ref==true then
E("--ref needs a value, e.g. --ref=build-2603a5b or --ref=main",d.error)return end
local aF,aE=pcall(require,"kernel.netrepair")if not aF or not aE then
E("online repair unavailable: "..tostring(aE),d.error)return end
E("=== SRM repair --online ===",d.title)
local aD=aE.run(nil,{apply=av.apply and true or false,unanchored=av.unanchored and true or false,ref=
type(av.ref)==K and av.ref or nil})
for aH,aG in ipairs(aD.lines)do E(aG.text,az[aG.sev]or d.fg)end;if av.apply then E("",d.dim)
E(string.format("%d repaired, %d rejected.",aD.fixed,aD.rejected),
aD.ok and az.ok or az.warn)end elseif ax==ak then if not f(E)then
return end;E("=== SRM repair ===",d.title)
if not av.restore then
E("Fixing what is mechanically safe (interrupted writes, stale state,",d.dim)
E("oversized logs). Add --restore to also put back system files that",d.dim)
E("are missing or have changed since the baseline.",d.dim)end;E("",d.dim)
aA(ay(aw.repair(nil,{restore=av.restore and true or false,source=
type(av.source)==K and av.source or nil,unverified=av.unverified and true or false})))E("",d.dim)
E("Some fixes only apply at boot: 'bootsettings repair on' runs this",d.dim)
E("pass before anything reads the files it repairs.",d.dim)elseif ax=="full"then E("=== SRM full report ===",d.title)
E("",d.dim)E("-- status --",d.title)ay(aw.status())
E("",d.dim)E("-- health --",d.title)b.doctor({},E)E("",d.dim)
E("-- integrity --",d.title)b.verify({},E)E("",d.dim)E("-- baseline --",d.title)
aA(ay(aw.scan()))else
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
b.bootsettings=function(au,E)if not f(E)then return end
local aB,az=pcall(require,"kernel.bootcfg")
if not aB or not az then E("bootcfg unavailable",d.error)return end;local aA=_G._TOS and _G._TOS.fs;if not aA then
E("fs unavailable",d.error)return end;local av=az.load(aA)
local ax=(au[1]or""):lower()
if ax==""or ax=="show"then
E("=== Boot Settings (/etc/boot.cfg) ===",d.title)
E("  profile    : "..av.profile..
(av.profile=="safe"and"   (SAFE MODE)"or"   (what loads)"),d.fg)
E("  verbosity  : ".. (av.verbosity or"auto").."   (what it says)",d.fg)
local aE=
av.ui=="cli"and"cli"or av.ui=="split"and"panels (split)"or av.ui=="home"and"panels"or
(
"auto (panels from "..az.PANELS_MIN_KB.." KB, else cli)")
E("  interface  : "..aE.."   (all seats)",d.fg)
E("  repair     : "..
(av.repair and"RUN on next boot"or"off"),d.fg)
E("  showConfig : ".. (av.showConfig and"on"or"off"),d.fg)
E("  cpuTier    : "..
(av.cpuTier and("Tier "..av.cpuTier)or"auto"),d.fg)
E("  dataTier   : "..
(av.dataTier and("Tier "..av.dataTier)or"auto"),d.fg)
E("  ramGate    : "..
(av.ramGate==nil and"auto (measure)"or
(
av.ramGate and"always load the extras"or"never load the extras")),d.fg)local aD=false
for aH,aG in ipairs(az.FEATURES)do
local aI=av.advanced and av.advanced[aG]if aI~=nil then
E("    +"..aG.." : ".. (aI and"on"or"off"),d.dim)aD=true end end
if not aD then E("    (no advanced overrides)",d.dim)end
E("Profiles: "..
table.concat(az.PROFILE_ORDER or{"minimal","normal","full","diagnostic"}," | "),d.dim)
E("Verbosity: silent | splash | text | verbose | auto",d.dim)
E("Set: bootsettings <profile|verbosity|ui|repair|show|cputier|datatier|ramgate|"..table.concat(az.FEATURES,"/")..
"> <value>",d.dim)
E("DEL during boot opens the full visual editor; S = Safe Mode once.",d.dim)local aF,aC=pcall(require,"kernel.sysinfo")
if aF and aC then E("",d.dim)
for aH,aG in
ipairs(aC.rows(aC.gather(
nil,{cpuTier=av.cpuTier,dataTier=av.dataTier})))do if aG.role=="section"then E(aG.value..":",d.title)else
E("  ".. (aG.label~=""and(
aG.label..": ")or"")..
aG.value,d.dim)end end end;return end;local aw=(au[2]or""):lower()local ay=false
if ax=="profile"then
if
az.PROFILES[aw]then av.profile=aw;ay=true else
E("profiles: "..table.concat(az.PROFILE_ORDER or
{"minimal","normal","full","diagnostic"}," "),d.error)return end elseif ax=="verbosity"then
if aw=="auto"then av.verbosity=nil;ay=true else local aC=false;for aE,aD in
ipairs(az.VERBOSITY)do if aD==aw then aC=true end end;if aC then av.verbosity=aw
ay=true else
E("verbosity: silent splash text verbose (or auto)",d.error)return end end elseif ax=="show"or ax=="showconfig"then av.showConfig=(aw=="on"or aw=="true"or
aw=="1")ay=true elseif ax=="cputier"or ax==
"cpu"then
if aw=="auto"then av.cpuTier=nil;ay=true elseif
aw=="1"or aw=="2"or aw=="3"then av.cpuTier=tonumber(aw)ay=true else
E("cputier: auto | 1 | 2 | 3",d.error)return end elseif ax=="datatier"or ax=="data"then
if aw=="auto"then av.dataTier=nil;ay=true elseif aw=="1"or
aw=="2"or aw=="3"then av.dataTier=tonumber(aw)ay=true else
E("datatier: auto | 1 | 2 | 3",d.error)return end elseif ax=="ui"or ax=="interface"then
if
aw=="panels"or aw=="tui"or aw=="home"then av.ui="home"ay=true elseif aw=="cli"or aw=="split"then av.ui=aw;ay=true elseif aw=="auto"then av.ui=
nil;ay=true else
E("ui: auto (by memory) | panels | split | cli",d.error)return end elseif ax==ak then
if aw=="on"or aw=="once"or aw=="1"then av.repair=true;ay=true elseif aw==
"off"or aw=="0"then av.repair=false;ay=true else
E("repair: on (runs once next boot, then clears) | off",d.error)return end elseif ax=="ramgate"or ax=="ram"then
if aw=="auto"then av.ramGate=nil;ay=true elseif aw=="always"or aw==
"plenty"or aw=="on"then av.ramGate=true;ay=true elseif
aw=="never"or aw=="tight"or aw=="off"then av.ramGate=false;ay=true else
E("ramgate: auto (measure free RAM) | always | never  (load the optional extras)",d.error)return end elseif ax=="reset"then av=az._normalize({})ay=true else local aC=false;for aE,aD in ipairs(az.FEATURES)do if
aD==ax then aC=true end end
if aC then
av.advanced=av.advanced or{}
if aw=="auto"then av.advanced[ax]=nil elseif aw=="on"then av.advanced[ax]=true elseif
aw=="off"then av.advanced[ax]=false else
E(ax..": auto | on | off",d.error)return end;ay=true else
E("Unknown setting: "..ax.." (try: bootsettings show)",d.error)return end end
if ay then local aC,aD=az.save(aA,av)if aC then
E("Saved. Applies on next boot (reboot to apply now).",d.highlight)else
E("Save failed: "..tostring(aD),d.error)end end end
local function A()local av,E=pcall(require,"kernel.bootcfg")
local au=_G._TOS and _G._TOS.fs;if av and E and au then return E,au end end
local function B(au,E)local av=h.getSwap and h.getSwap()
if au=="now"then
local aC,aB=pcall(require,al)if not aC or not aB.sweepCold then
E("tab paging unavailable",d.error)return end;if not av then
E("Swap not available",d.error)return end;local aD=aB.sweepCold(a,true)
local aE,aF=aB.pagedStats(a)
E(string.format("Paged out %d view tab(s) now.",aD),d.highlight)
E(string.format("%d tab(s) on disk, %d lines held there.",aE,aF),d.dim)
E("They page back transparently the next time you open them.",d.dim)return end
if au==""or au==M or au=="keys"or au=="clear"then if not av then
E("Swap not available",d.error)return end
if au=="clear"then if not f(E)then return end
local aE,aD=pcall(require,al)
if aE and aD.isPaged then for aG,aF in ipairs(a.tabs or{})do
if aD.isPaged(aF)then local aG=aF.content end end end;av.clear()E("Swap cleared.",d.highlight)return end;local aB=av.usage()
local aC=(aB.max and aB.max>0)and math.floor(aB.bytes*100/
aB.max)or 0;E("=== Disk Swap (/var/swap) ===",d.title)
E(string.format("Used:    %s / %s (%d%%)",s(aB.bytes),s(aB.max),aC),
aC>90 and d.warning or d.fg)
E(string.format("Entries: %d",aB.count),d.dim)if au=="keys"and av.keys then local aD=av.keys()
if#aD==0 then
E("(no keys)",d.dim)else for aF,aE in ipairs(aD)do E("  "..aE,d.dim)end end end
do
local aG,aE=pcall(require,al)if aG and aE.pagedStats then local aH,aI=aE.pagedStats(a)
E(string.format("View tabs paged: %d (%d lines)",aH,aI),
aH>0 and d.highlight or d.dim)end;local aF,aD=25,(
h.getConfig and h.getConfig())if
aD and aD.get then
aF=tonumber(aD.get("swapPressurePct"))or 25 end
E(string.format("Cold view buffers page out below %d%% free RAM"..
"  (swapPressurePct)",aF),d.dim)end
E("Volatile: cleared on every boot. 'swap clear' wipes now.",d.dim)
E("'swap now' pages cold tabs immediately (ignores pressure).",d.dim)
E("Paging spends disk writes to save RAM — see 'optimize power'.",d.dim)return end;if not f(E)then return end;local ax,ay=A()if not ax then
E("bootcfg/fs unavailable",d.error)return end;local aw=ax.load(ay)
aw.advanced=aw.advanced or{}
if au=="auto"then aw.advanced.swap=nil elseif au=="on"then aw.advanced.swap=true elseif
au=="off"then aw.advanced.swap=false else
E("swap <status|keys|now|clear|on|off|auto>",d.error)return end;local az,aA=ax.save(ay,aw)if az then
E("Disk swap set "..au..". Applies on next boot.",d.highlight)else
E("Save failed: "..tostring(aA),d.error)end end
local function F(au,av,E)local aC,aw=pcall(require,"kernel.power")
if
not aC or type(aw)~="table"or not aw.PROFILES then
E("Power control unavailable: "..tostring(aw),d.error)
E("TOS behaves as profile 'off' — nothing is being conserved.",d.dim)return end;local aB,ay=pcall(require,"kernel.screen")
local az=h.getConfig and h.getConfig()
if au==""or au=="show"or au==M then local aH=aw.profile()
E("=== Power ===",d.title)local aI,aE,aF=pcall(aw.energy)
if
aI and type(aE)==X and type(aF)==X and aF>0 then
local aN=math.floor(aE*100/aF+0.5)
E(string.format("  Stored     %d / %d  (%d%%)",math.floor(aE),math.floor(aF),aN),
aN<25 and d.warning or d.fg)local aL=a._pwrSample
local aM=aL and aL.t and(h.uptime()-aL.t)or 0
if aM>=1 then local aO=(aL.e-aE)/aM
if aO>0.05 then
E(string.format("  Draw       %.1f/s over the last %ds",aO,math.floor(aM)),d.fg)if aE>0 then
E(string.format("             ~%d s of buffer left at that rate",math.floor(aE/aO)),d.dim)end elseif aO<-0.05 then
E(string.format("  Draw       charging (+%.1f/s)",
-aO),d.highlight)else
E(string.format("  Draw       level over the last %ds — supply is keeping up",math.floor(aM)),d.fg)end else
E("  Draw       run 'optimize power' again in a few seconds for a rate",d.dim)end;a._pwrSample={t=h.uptime(),e=aE}else
E("  Stored     (this machine reports no energy buffer)",d.dim)end;E("",d.dim)E("  Profile    "..aH,d.highlight)
local aJ,aG=aw.idleSeconds(),aw.blankSeconds()
E(string.format("  Idle clock every %ds",aJ),d.fg)
E("    a status-bar repaint is a GPU write, which OC bills per cell",d.dim)
E("  Screen blank "..
(aG>0 and("after "..aG.."s idle")or"never"),d.fg)
E("    OC bills a screen per tick per NON-BLANK cell; blank costs ~0",d.dim)local aK=(aB and ay.bufferMode and ay.bufferMode())or
"?"
E("  Display buffer "..aK,d.fg)
E("    unchanged cells skip the GPU write entirely ('optimize buffer')",d.dim)E("",d.dim)
E("optimize power <off|balanced|save>   off = no conservation",d.dim)
E("optimize power blank <secs|off>      screen blank timeout",d.dim)
E("optimize power idle <secs>           idle repaint cadence",d.dim)return end
if au=="blank"or au=="idle"then if not f(E)then return end
local aF=
(av=="off"or av=="never")and 0 or tonumber(av)local aE,aG=aw.setKnob(au,aF)if not aE and aE~=0 then
E(tostring(aG),d.error)return end
if au=="blank"then
E(aE>0 and
("Screen blanks after "..aE.."s idle.")or"Screen blanking off.",d.highlight)else
E("Idle repaint every "..aE.."s.",d.highlight)end
E("Profile is now custom (a named profile resets both knobs).",d.dim)return end;if not f(E)then return end;local aA,aD=aw.applyProfile(au)if not aA then
E(tostring(aD),d.error)
E("Profiles: "..table.concat(aw.PROFILE_ORDER,", "),d.dim)return end
local ax=aw.PROFILES[aA]
if aB and ay.setBuffer then pcall(ay.setBuffer,ax.buffer)end
if az and az.set then az.set("powerProfile",aA)local aE=pcall(az.save)if
not aE then
E("(profile applied, but /etc/tos.cfg could not be saved)",d.warning)end end;E("Power profile: "..aA,d.highlight)
E(string.format("  idle repaint %ds · screen blank %s · display buffer %s",ax.idleSec,
ax.blankSec>0 and(ax.blankSec.."s")or"never",ax.buffer),d.dim)
E("Applies now, on every seat, and persists across reboots.",d.dim)end
b.swap=function(E,au)return B((E[1]or""):lower(),au)end
b.optimize=function(au,E)local av=(au[1]or""):lower()
local ax=(au[2]or""):lower()local ay,aw=pcall(require,"kernel.screen")
if av==""or av=="show"or
av==M then E("=== Optimizations ===",d.title)
local aA="auto (profile)"local aB,aC=A()
if aB and aC then local aF=aB.load(aC)
local aG=aF.advanced and aF.advanced.swap;if aG~=nil then aA=aG and"on"or"off"end end;local az=h.getSwap and h.getSwap()local aD="inactive"
if az then
local aF=az.usage()
local aG=(aF.max and aF.max>0)and
math.floor(aF.bytes*100/aF.max)or 0
aD=string.format("active %s/%s (%d%%)",s(aF.bytes),s(aF.max),aG)end
E(string.format("  Disk swap      %-14s [%s]",aA,aD),az and d.fg or d.dim)
E("    extends usable memory onto /var/swap (boot feature)",d.dim)local aE=(ay and aw.bufferMode and aw.bufferMode())or
"?"
E(string.format("  Display buffer %-14s",aE),d.fg)
E("    skips GPU writes for unchanged cells (auto = memory-gated)",d.dim)
if ay and aw.bufferStats then local n=aw.bufferStats()
if n.total>0 then
E(string.format("    this session: %d of %d cell-draws skipped (%d%%)",n.skipped,n.total,math.floor(
n.ratio*100+0.5)),
n.ratio>0 and d.highlight or d.dim)else E("    (no draws measured yet)",d.dim)end end
do local aG,aF=pcall(require,"kernel.power")
if
aG and type(aF)=="table"and aF.profile then local aH=aF.blankSeconds()
E(string.format("  Power          %-14s [idle %ds, blank %s]",aF.profile(),aF.idleSeconds(),
aH>0 and(aH.."s")or"never"),d.fg)
E("    fewer wake-ups and a blank screen are what OC bills less for",d.dim)else E("  Power          not loaded",d.dim)end end;E("",d.dim)
E("swap [status|keys|now|clear|on|off|auto]  boot toggle needs reboot",d.dim)
E("optimize power  <off|balanced|save>       conservation profile",d.dim)
E("optimize buffer <on|off|auto>             display; applies immediately",d.dim)return end;if av=="swap"then return B(ax,E)end;if av=="power"then return
F(ax,(au[3]or""):lower(),E)end
if
av=="buffer"or av=="display"then if not f(E)then return end;if not(ay and aw.setBuffer)then
E("display buffer control unavailable",d.error)return end
local az,aA=aw.setBuffer(ax)
if az then
E("Display buffer set "..ax.." (applied now).",d.highlight)else E(tostring(aA)or"invalid",d.error)end;return end
E("Usage: optimize [show | power <off|balanced|save> | buffer <on|off|auto>".." | swap <on|off|auto>]",d.dim)
E("       `swap` on its own is the same as `optimize swap`.",d.dim)end
b.programs=function(au,E)local av={"/bin","/usr/bin","/home/"..a.who}
E("Executables:",d.title)
for ax,aw in ipairs(av)do
if e.isDirectory(aw)then local az,ay=pcall(e.list,aw)
if az and ay then local aA={}
if type(ay)==
"table"then aA=ay elseif type(ay)=="function"then for aC in ay do aA[#aA+1]=aC end end;local aB={}
for ax,aC in ipairs(aA)do if aC:match("%.lua$")then aB[#aB+1]=aC end end
if#aB>0 then E(" "..aw..":",d.dim)for ax,aC in ipairs(aB)do
E("   "..aC,
d.file_lua or d.file_exec or d.highlight)end end end end end end
b.log=function(au,E)if not f(E)then return end;local av=h.getLog()if not av then
E("Logger unavailable",d.error)return end
local aw=

(au[1]==nil)or(au[1]=="file")or(au[1]=="f")or(au[1]=="all")or(tonumber(au[1])~=nil)
if aw then local aA="/var/log/kernel.log"
local az=tonumber(au[1])or tonumber(au[2])pcall(av.flush)
if not e.exists(aA)then
E("No /var/log/kernel.log yet — showing in-memory ring.",d.dim)local aD=av.recent(az or 20)if#aD==0 then
E("(log is empty)",d.dim)return end
local aE={{" in-memory log ring ("..#aD.." entries)",d.title}}
for aG,aF in ipairs(aD)do local aH=d.fg;if aF.level>=3 then aH=d.error elseif aF.level>=2 then aH=d.warning elseif aF.level<1 then
aH=d.dim end
aE[#aE+1]={av.format(aF),aH}end;y(aE,"log (ring)")return end;local aC=e.readFile(aA)if not aC then
E("Cannot read "..aA,d.error)return end;local ax={}for aD in aC:gmatch("([^\n]*)\n?")do if aD~=""then
ax[#ax+1]=aD end end;local aB=
(az and az>0 and#ax-az+1)or 1;if aB<1 then aB=1 end;local ay={}
ay[#ay+1]={
" /var/log/kernel.log  ("..#ax.." lines)",d.title}
for aD=aB,#ax do local aE=ax[aD]local aF=d.fg
if
aE:find("%[FTL%]")or aE:find("%[ERR%]")then aF=d.error elseif aE:find("%[WRN%]")then aF=d.warning elseif aE:find("%[DBG%]")then aF=d.dim end;ay[#ay+1]={aE,aF}end;y(ay,Y)return end
if au[1]=="filter"then local ax,ay=au[2],au[3]
if not ax then
local aA={[0]="DEBUG","INFO","WARN","ERROR"}local az=0;for aC,aB in pairs(av.getSourceLevels())do az=az+1
E(string.format("  %-12s %s+",aC,aA[aB]or
tostring(aB)),d.fg)end;if az==0 then
E("(no per-source filters; global level applies)",d.dim)end
E("Usage: log filter <source> <debug|info|warn|error|off>",d.dim)return end
if ay=="off"or ay=="clear"then av.setSourceLevel(ax,nil)E(
"Filter cleared for '"..ax.."'.",d.fg)elseif ay then
local az,aA=av.setSourceLevel(ax,ay)
if az then
E("Source '"..ax.."' now logs at "..ay:upper().."+.",d.fg)else E(aA or"Filter update failed",d.error)end else
E("Usage: log filter <source> <debug|info|warn|error|off>",d.dim)end;return end
if au[1]=="clear"then pcall(av.flush)
av.info("log","--- ring cleared on operator request ---")
E("Ring marker recorded; old entries still on disk.",d.dim)return end
if au[1]=="ring"or au[1]=="r"or au[1]=="tail"then local ay=
tonumber(au[2])or 20;local ax=av.recent(ay)if#ax==0 then
E("(no log entries in ring)",d.dim)return end
for aA,az in ipairs(ax)do local aB=d.dim
if az.level>=3 then aB=d.error elseif
az.level>=2 then aB=d.warning elseif az.level>=1 then aB=d.fg end;E(av.format(az),aB)end
E(#ax.." ring entries (use 'log' for full on-disk history)",d.dim)return end
E("Usage: log [N] | log ring [N] | log clear | log filter ...",d.dim)
E("  log        Open the full on-disk log (last N lines if given)",d.dim)
E("  log ring   Quick peek at the in-memory ring",d.dim)end
b.bg=function(E,au)if not f(au)then return end;if not E[1]then
au("Usage: bg <script.lua> [args...]",d.dim)
au("  Runs a Lua script in a background tab.",d.dim)return end
local aC=u(E[1])local aD=I.safeModeRefusal(aC)
if aD then au(aD,d.error)return end;local aw=e.readFile(aC)
if not aw then au(am..E[1],d.error)return end;local aF,aG=load(aw,"="..E[1],"t",v{name=E[1]})if not aF then au(
"Compile error: "..tostring(aG),d.error)
return end;local aA={}
for aK=2,#E do aA[#aA+1]=E[aK]end;local ax=E[1]:match("[^/]+$")or E[1]
local av=c.createTab("output","bg:"..ax,{content={
"Background task: "..ax,"PID: (starting...)",""},offset=0,pid=nil})local aJ=#c.tabs;local ay=500
local function aB(...)local aK={}for aN=1,select("#",...)do
aK[#aK+1]=tostring(select(aN,...))end;local aM=table.concat(aK,"\t")av.content[#
av.content+1]=aM
if#av.content>ay then
local aN=#av.content-ay
for aO=1,ay do av.content[aO]=av.content[aO+aN]end;for aO=ay+1,#av.content do av.content[aO]=nil end;av.offset=math.max(0,
av.offset-aN)end;local aL=k-3
if av.offset>=#av.content-aL-2 then av.offset=math.max(0,
#av.content-aL)end end
local az=t.spawn("bg:"..ax,function()local aK=v{name=E[1],stdout=aB}
local aL=load(aw,"="..E[1],"t",aK)aw=nil
if aL then local aM,aN=pcall(aL,table.unpack(aA))I.reportProgramEnd(a,function(aO)
aB(aO)end,aM,aN,aj,aK)end;aB("","--- Task finished ---")end,{priority=8,source="user",tsr=true})av.pid=az;av.content[2]="PID: "..az
au("Started background task: "..ax..
" (PID "..az..")",d.highlight)local aH,aE=pcall(require,"shell.panels.home")local aI=(aH and aE)and
aE.cycleKeyLabel(a)or"F2"
au(
"Switch to its tab with "..aI..", or use 'kill "..az.."' to stop.",d.dim)end
b.run=function(E,au)if not f(au)then return end;if not E[1]then
au("Usage: run <file.lua>",d.dim)return end;local aw=u(E[1])
local ax=I.safeModeRefusal(aw)if ax then au(ax,d.error)return end;local ay=e.readFile(aw)if not ay then au(am..
E[1],d.error)return end
local az=v{name=E[1],stdout=function(aE)au(aE,d.fg)end}local aA,aB=load(ay,"="..E[1],"t",az)if not aA then
au("Compile error: "..tostring(aB),d.error)return end;local av={}
for aE=2,#E do av[#av+1]=E[aE]end;local aC,aD=pcall(aA,table.unpack(av))
I.reportProgramEnd(a,au,aC,aD,"Runtime error: ",az)end
b.lua=function(au,E)if not o(E)then return end
pcall(function()local aB=require(Y)if aB and aB.info then
aB.info("repl",
"REPL session opened by "..tostring(a.who or"?"))end end)local az=L.uptime()j.fill(1,1,l,k," ",d.fg,d.bg)
j.fill(1,1,l,1," ",d.bar_fg,d.bar_bg)
j.set(1,1," Lua REPL  type 'exit' to quit",d.bar_fg,d.bar_bg)
j.set(1,1," Lua REPL  'exit' to quit | blank line runs/cancels a block",d.bar_fg,d.bar_bg)local av=2;local aw={}
local function ay(aB,aC)if av>k-1 then local aD=j.getGpu()if aD and aD.copy then
aD.copy(1,3,l,k-3,0,-1)end;j.fill(1,k-1,l,1," ",d.fg,d.bg)
av=k-1 end;j.set(1,av,tostring(aB):sub(1,l),
aC or d.fg,d.bg)av=av+1 end;local function aA(aB)
return type(aB)==K and aB:find("<eof>",1,true)~=nil end;local ax={}
while true do if av>k-1 then j.getGpu().copy(1,3,l,k-3,0,-
1)
j.fill(1,k-1,l,1," ",d.fg,d.bg)av=k-1 end;local aD=#ax>0
local aF=aD and">> "or"> "j.fill(1,av,l,1," ",d.fg,d.bg)
j.set(1,av,aF,d.highlight,d.bg)local aB=""local aC=#aw+1;local aE=#aF+1
while true do
j.fill(aE,av,l-aE+1,1," ",d.fg,d.bg)j.set(aE,av,aB.."_",d.fg,d.bg)
local aI,aJ,aG,aH=c.pullSignal()
if aI=="key_down"then
if aH==28 then break elseif aH==14 then if#aB>0 then aB=aB:sub(1,-2)end elseif aH==200 then if
aC>1 then aC=aC-1;aB=aw[aC]or""end elseif aH==208 then if aC<#aw then aC=aC+1
aB=aw[aC]or""else aC=#aw+1;aB=""end elseif aG and aG>=32 and aG<127 then aB=
aB..string.char(aG)end elseif aI=="clipboard"and type(aG)==K then
aB=aB..aG:gsub("\r","")local aK=aB:find("\n",1,true)
if aK then aB=aB:gsub("\n"," ")end end end;av=av+1
if(aB=="exit"or aB=="quit")and not aD then break end
if aB==""and not aD then elseif aB==""and aD then ax={}ay("(cancelled)",d.dim)else
ax[#ax+1]=aB;local aG=table.concat(ax,"\n")
local aI,aJ=load("return "..aG,"=repl","t")if not aI then aI,aJ=load(aG,"=repl","t")end;if
not aI and aA(aJ)then goto repl_continue end;ax={}aw[#aw+1]=aG
pcall(function()
local aM=require(Y)if aM and aM.info then
aM.info("repl","["..tostring(a.who or"?").."] "..
aG:gsub("\n"," ; "):sub(1,120))end end)
local aK=v{name="repl",caps={["fs.read"]=true,["fs.write"]=true,["compat.io"]=true,["component"]=true,["load"]=true,["net"]=true,["peripheral.modem"]=true,["peripheral.redstone"]=true,["peripheral.robot"]=true,["peripheral.inventory"]=true,["peripheral.tape"]=true},stdout=function(aM)
ay(aM,d.fg)end}local aH,aL=load("return "..aG,"=repl","t",aK)if not aH then
aH,aL=load(aG,"=repl","t",aK)end
if aH then local aN,aM=pcall(aH)
if aN then if aM~=nil then
ay(tostring(aM),d.highlight)end else ay(tostring(aM),d.error)end else ay(aj..tostring(aL),d.error)end end::repl_continue::end
pcall(function()local aB=require(Y)if aB and aB.info then
aB.info("repl",string.format("REPL session closed by %s (%.1fs, %d cmds)",tostring(
a.who or"?"),L.uptime()-az,#aw))end end)end
b.edit=function(E,au)if not f(au)then return end;if not E[1]then
au("Usage: edit <file>",d.dim)return end;local av=u(E[1])C(av)end
b.protect=function(au,E)if not o(E)then return end
local az,av=pcall(require,"kernel.securefs")if not az or not av or not av.setOperatorOverride then
E("This build has no protected-path override.",d.error)return end
local aw=I.sessionOf(a)
if not aw then
E("Could not identify your session, so there is nothing to arm.",d.error)
E("This is a bug rather than a permission problem — `whoami` should",d.dim)
E("say who you are; if it does, please report it.",d.dim)return end
local ax=av.operatorOverride and av.operatorOverride(aw)local ay=(au[1]or""):lower()
if ay==""or ay==M then
E(
"Protected-path guards are "..
(ax and"STOOD DOWN for this session."or"active."),ax and d.warning or d.highlight)E("",d.dim)
E("They stop even root from writing under /tos, /etc, /usr and",d.dim)
E("/var through securefs — a line against a tampered admin",d.dim)
E("session, not an ACL. You own this machine, so you can stand",d.dim)
E("them down; nobody below root can, and it ends with this",d.dim)E("session.",d.dim)E("",d.dim)
E("  protect off    stand the guards down for this session",d.dim)E("  protect on     put them back",d.dim)return end
if ay=="off"then if ax then
E("Already stood down for this session.",d.dim)return end
local aA,aB=av.setOperatorOverride(aw,true)
if not aA then E(N..tostring(aB),d.error)return end
E("Protected-path guards STOOD DOWN for this session.",d.warning)
E("You can now write and remove under /tos, /etc, /usr and /var.",d.dim)
E("Every path allowed this way is written to the kernel log.",d.dim)
E("Deleting the wrong thing here is how a machine stops booting —",d.dim)E("`protect on` when you are done.",d.dim)elseif ay=="on"then if not ax then
E("Guards are already active.",d.dim)return end
local aA,aB=av.setOperatorOverride(aw,false)
if not aA then E(N..tostring(aB),d.error)return end
E("Protected-path guards active again.",d.highlight)else E("Usage: protect [status|off|on]",d.dim)end end
b.reclaim=function(au,E)if not o(E)then return end;local aE=false;for aJ,aI in ipairs(au or{})do
if aI=="--apply"then aE=true end end
local aH,av=pcall(require,"kernel.fs")
if not aH or not av then E("Filesystem unavailable.",d.error)return end;local ax=av.readFile("/init.lua")if not ax then
E("Cannot read /init.lua — refusing to guess what this machine boots.",d.error)return end
if not
(
ax:find("_TOS",1,true)or ax:find("TOS Kernel",1,true)or
ax:find("tos/kernel",1,true))then
E("/init.lua is not TOS's — this machine boots OpenOS.",d.error)
E("Those files are the operating system here, not leftovers.",d.dim)E("Refusing.",d.dim)return end;local ay={"/bin","/boot","/lib"}local az={}local aB="/init.lua.pre-tos"for aJ,aI in
ipairs(ay)do
if av.exists(aI)then if av.exists(aB)then az[#az+1]=aB end;break end end
local function aF(aI,aJ)
if not av.exists(aI)then return end
if av.isDirectory(aI)then
for aL,aK in ipairs(av.list(aI)or{})do aF(aI.."/"..
(aK:gsub("/$","")),aJ)end;aJ.dirs[#aJ.dirs+1]=aI else
aJ.files[#aJ.files+1]=aI;aJ.bytes=aJ.bytes+ (av.size(aI)or 0)end end;local aw={files={},dirs={},bytes=0}for aJ,aI in ipairs(ay)do aF(aI,aw)end
for aJ,aI in
ipairs(az)do if av.exists(aI)and not av.isDirectory(aI)then aw.files[
#aw.files+1]=aI
aw.bytes=aw.bytes+ (av.size(aI)or 0)end end;if#aw.files==0 and#aw.dirs==0 then
E("Nothing to reclaim — no OpenOS leftovers found.",d.highlight)return end;local aG=math.floor(
aw.bytes/1024+0.5)
E(string.format("OpenOS leftovers: %d file(s) in %d director(ies), ~%d KB",
#aw.files,#aw.dirs,aG),d.title)
for aJ,aI in ipairs(ay)do if av.exists(aI)then E("  "..aI,d.fg)end end
for aJ,aI in ipairs(az)do if av.exists(aI)then E("  "..aI,d.fg)end end;E("",d.dim)
E("TOS installs no files into these, but it still looks in them:",d.dim)
E("require() searches /lib, and an unknown command is tried in /bin.",d.dim)
if av.exists(aB)then
E("Until this runs, renaming /init.lua.pre-tos back to /init.lua",d.dim)
E("boots OpenOS again; afterwards an OpenOS floppy is the way back.",d.dim)else
E("An OpenOS floppy remains your recovery path — this install",d.dim)
E("stopped being one when TOS replaced /init.lua.",d.dim)end;E("",d.dim)
E("Removing /bin also changes what an unknown command does: today",d.dim)
E("it may run OpenOS's version, afterwards you get 'not a command'.",d.dim)if not aE then E("",d.dim)
E("Dry run. Nothing was removed.",d.highlight)E("Run it for real with:  reclaim --apply",d.dim)
return end
if q then
local aI=q(string.format(
"Permanently delete %d OpenOS file(s), ~%d KB?\n\n"..
"%s\n\nTOS keeps working; this drive stops being able to boot ".."OpenOS. Your recovery path becomes an OpenOS floppy.",
#aw.files,aG,table.concat(ay,"  ")),{title="Remove OpenOS leftovers",severity=Z,yes="Delete",no=_})if not aI then E("Cancelled. Nothing was removed.",d.highlight)
return end end;E("",d.dim)E("Removing...",d.warning)local aC,aA,aD=0,0,0;for aJ,aI in
ipairs(aw.files)do local aK=av.size(aI)or 0
if av.remove(aI)then aC=aC+1;aD=aD+aK else aA=aA+1 end end;for aJ,aI in ipairs(aw.dirs)do
pcall(av.remove,aI)end
E(string.format("Removed %d file(s), ~%d KB reclaimed.",aC,math.floor(aD/1024+0.5)),d.highlight)if aA>0 then
E(aA.." file(s) could not be removed.",d.warning)end
E("Reboot when convenient; nothing running depends on them.",d.dim)end
b.flash=function(au,E)if not o(E)then return end;local az,aG=nil,false;for aN,aM in ipairs(au)do if aM=="--data"then aG=true elseif az==nil then
az=aM end end
if
not az then E("Usage: flash <file> [--data]",d.dim)
E("Flashes the given file to the system EEPROM.",d.dim)
E("--data also writes the chip's data field, asked for and not shown,",d.dim)
E("for a chip going into a robot or drone (rc-pilot's shared secret).",d.dim)return end;local aA=u(az)local aw=nil;for aM in J.list("eeprom")do aw=aM;break end
if not aw then
E("No EEPROM detected. Insert EEPROM, or press Ctrl+C to abort...",d.warning)local aM=L.uptime()+60
while not aw and L.uptime()<aM do
local aN,aO,aP=c.pullSignal(1)if aN=="component_added"and aP=="eeprom"then aw=aO elseif aN=="interrupted"then
E(O,d.dim)return end end
if not aw then E("Timed out waiting for EEPROM.",d.error)return end;E("EEPROM detected.",d.highlight)end;local ax=J.proxy(aw)local aB=ax.getSize()
local aC=e.size and e.size(aA)if type(aC)==X and aC>aB then
E(string.format("File too large: %d bytes (EEPROM max: %d)",aC,aB),d.error)return end
local av,aI=e.readFile(aA)
if not av then E(am..tostring(aI),d.error)return end;if#av>aB then
E(string.format("File too large: %d bytes (EEPROM max: %d)",#av,aB),d.error)return end
local aJ,aK=load(av,"=flash-verify","t",{})
if not aJ then
E("Refusing to flash: file does not parse as Lua text.",d.error)E("  "..tostring(aK),d.dim)return end
local aD=
av:find("getBootAddress",1,true)or av:find("setBootAddress",1,true)or
(av:find("component.list",1,true)and av:find("init.lua",1,true))
if not aD then local aM
if r then
aM=r("This file does not look like a BIOS."..
"\n\n"..
"None of the markers a BIOS normally carries were found in it. "..

"Flashing it will very likely leave a machine that cannot boot, "..
"and fixing that means physically replacing the EEPROM."..
"\n\n".."If this chip is going into a robot or a drone, that is expected: "..
"put this computer's own EEPROM back before it restarts.","force",{title="Not a BIOS",severity=Z,yes="Flash anyway",no=_})else
aM=
(i and i("Doesn't look like a BIOS — type 'force' to flash anyway: ",16))=="force"end
if not aM then E("Aborted (safety check).",d.dim)return end end;local ay=nil
if aG then
if aD then
E("Refusing --data: this file looks like a BIOS, and a BIOS keeps its",d.error)
E("boot address in the data field. --data is for a chip that is going",d.dim)E("into a robot or a drone.",d.dim)return end
if not i then E("--data needs a screen to ask on.",d.error)return end;local aN=256
do
local aQ,aP=pcall(function()return ax.getDataSize()end)if aQ and type(aP)==X and aP>0 then aN=aP end end;local aM=i("Data for the chip (not shown): ",aN,true)if aM==nil or
aM==""then E(O,d.dim)return end
local aO=i("The same again, to confirm: ",aN,true)if aO~=aM then
E("The two did not match. Nothing was written.",d.error)return end;ay=aM end
local aL=ax.getLabel and ax.getLabel()or"(no label)"local aH="(unknown)"
do local aN,aM=pcall(L.getBootAddress)if aN and aM then aH=aM:sub(1,8)..
"..."end end;local aE=nil
do local aN,aM=pcall(require,"kernel.crypto")
if
aN and aM and aM.hash then local aP,aO=pcall(aM.hash,av)if
aP and type(aO)==K and#aO==64 then aE=aO end end end
E(string.format("  Source : %s (%d bytes)",aA,#av),d.dim)if aE then
E(string.format("  SHA-256: %s",aE),d.dim)else
E("  SHA-256: UNAVAILABLE - integrity cannot be verified",d.warning)end
E(string.format("  EEPROM : %s",aL),d.dim)
E(string.format("  Boot   : %s",aH),d.dim)if ay then
E(string.format("  Data   : %d bytes, as typed (not shown)",#ay),d.dim)end;local aF
if r then
aF=r("Overwrite this machine's EEPROM with "..
tostring(aA or
"this image").."?"..
"\n\n".."The EEPROM is what starts the computer. If the image is wrong, "..
"the machine will not boot and no software fix will reach it.","flash",{title="Flash EEPROM",severity=Z,yes="Flash",no=_})else aF=(i and i('Type "flash" to confirm: ',16))==
"flash"end
if aF then local aM,aN=pcall(ax.set,av)
if not aM then
E("Flash failed: "..tostring(aN),d.error)else
E("EEPROM flashed! "..#av.." bytes written.",d.highlight)
if ay then local aO,aP=pcall(ax.setData,ay)if aO then
E("Data field set: "..#ay.." bytes.",d.highlight)else
E("The code was written, but the data field was NOT: "..tostring(aP),d.error)end end
if aD then E("Reboot for changes to take effect.",d.dim)else
E("This chip is not a BIOS: put this computer's own EEPROM back",d.dim)E("before it restarts.",d.dim)end end else E(O,d.dim)end end
b.users=function(au,E)if not f(E)then return end;if not g then E(aa,d.error)return end
E(string.format(" %-12s %-8s %s","User","Tier","Status"),d.title)E(string.rep("-",34),d.border)
local av=g.list and g.list()or
g.listUsers and g.listUsers()or{}
for ax,aw in ipairs(av)do local ay=aw.locked and"LOCKED"or"OK"
E(string.format(" %-12s %-8s %s",
aw.username or aw.user or"?",tostring(aw.tier or aw.accessLevel or"?"),ay),
aw.locked and d.error or d.dim)end end;local function x()if not g then return"root"end;local E=g.getSession(n)return
(E and E.user)or"root"end
b.useradd=function(au,E)if
not o(E)then return end;if not g then E(aa,d.error)return end;local av=au[1]if not av then
E("Usage: useradd <username>",d.dim)return end
local aw=i("Password for "..av..": ",64,true)if not aw or aw==""then E(O,d.dim)return end
local ax=i("Confirm password: ",64,true)
if ax~=aw then E("Passwords do not match.",d.error)return end;local ay,az=g.create(x(),av,aw,1)
if ay then
a.lastOut={"User '"..av.."' created.",d.highlight}else a.lastOut={tostring(az),d.error}end end
b.userdel=function(au,E)if not o(E)then return end;if not g then E(aa,d.error)return end
local av=au[1]
if not av then E("Usage: userdel <username>",d.dim)return end;local aw
if q then
aw=q("Delete the account '"..
av.."'?\n\n"..
"Their home directory and files are NOT removed, but the account ".."cannot be recovered from here.",{title="Delete user",severity=Z,yes="Delete",no=_})else
local az=i("Delete '"..av.."'? [y/N]: ",1,false)aw=(az=="y"or az=="Y")end;if not aw then E(O,d.dim)return end;local ax,ay=g.delete(x(),av)
if ax then
a.lastOut={
"User '"..av.."' deleted.",d.highlight}else a.lastOut={tostring(ay),d.error}end end
b.usermod=function(au,E)if not o(E)then return end;if not g then E(aa,d.error)return end
local ax,ay=au[1],au[2]if not ax or not ay then
E("Usage: usermod <username> lock|unlock|admin|user|root",d.dim)return end;local az=x()local av,aw
if ay=="lock"then
if
g.setLocked then av,aw=g.setLocked(az,ax,true)else av,aw=false,"setLocked unavailable"end
if av then
a.lastOut={"'"..ax.."' locked.",d.highlight}else a.lastOut={tostring(aw),d.error}end elseif ay=="unlock"then if g.setLocked then av,aw=g.setLocked(az,ax,false)else
av,aw=false,"setLocked unavailable"end
if av then
a.lastOut={"'"..ax.."' unlocked.",d.highlight}else a.lastOut={tostring(aw),d.error}end elseif ay=="admin"then if ax:lower()==ac then
E("Failure. Did you mean 'usermod computer root'?",d.error)return end;if g.setTier then
av,aw=g.setTier(az,ax,2)else av,aw=false,an end;if av then a.lastOut={"'"..
ax.."' promoted to admin.",d.highlight}else
a.lastOut={tostring(aw),d.error}end elseif ay=="root"then
if
ax:lower()==ac and a.D and
not(_G._TOS and _G._TOS._takeoverFired)then _G._TOS=_G._TOS or{}
_G._TOS._takeoverFired=true;local aB,aA=pcall(require,"shell.panels.takeover")
if
aB and aA and aA.run then local aC,aD=pcall(aA.run,a)
if a.D.invalidate then pcall(a.D.invalidate)end
pcall(function()
_G._TOS.logObj.info("kernel","The computer briefly reconsidered its priorities ("..
tostring(aC and aD or"?")..")")end)a.lastOut={"Access control updated.",d.dim}return end end
if g.setTier then av,aw=g.setTier(az,ax,3)else av,aw=false,an end
if av then
a.lastOut={"'"..ax.."' promoted to root.",d.highlight}else a.lastOut={tostring(aw),d.error}end elseif ay=="user"then
if g.setTier then av,aw=g.setTier(az,ax,1)else av,aw=false,an end
if av then
a.lastOut={"'"..ax.."' set to user.",d.highlight}else a.lastOut={tostring(aw),d.error}end else E("Unknown action: "..ay,d.error)
E("Valid: lock, unlock, admin, user",d.dim)end end
b.lsdev=function(au,E)
E(string.format(" %-16s %-10s %s","Type","Address","Info"),d.title)E(string.rep("-",46),d.dim)local av=0
for aw,ax in J.list()do local ay=""
if ax==ab then
local aA,az=pcall(J.proxy,aw)
if aA and az then
local aB=az.getLabel and az.getLabel()or""local aC=
az.spaceTotal and math.floor(az.spaceTotal()/1024)or 0
ay=(aB~=""and
'"'..aB..'" 'or"")..aC.."K"end elseif ax=="modem"then local aA,az=pcall(J.proxy,aw)
if aA and az and az.isWireless then ay=
az.isWireless()and"wireless"or"wired"end elseif ax=="drive"then local aA,az=pcall(J.proxy,aw)
if aA and az and az.getCapacity then ay="raw "..
math.floor((
az.getCapacity()or 0)/1024).."K"end elseif ax=="openprinter"then local aA,az=pcall(J.proxy,aw)
if aA and az then local function aB(aC)
if aC==nil then return"?"end;local aE,aD=pcall(aC)
return(aE and tonumber(aD))and
tostring(math.floor(aD))or"?"end
ay="paper "..
aB(az.getPaperLevel).." ink "..
aB(az.getBlackInkLevel).."/"..aB(az.getColorInkLevel)end end
E(string.format(" %-16s %s  %s",ax,aw:sub(1,8).."...",ay),d.fg)av=av+1 end
if av==0 then E("  (no peripherals detected)",d.dim)end end;b.devices=b.lsdev
b.mount=function(au,E)
if au[1]and au[2]then if not f(E)then return end
local ax,aA=au[1],au[2]local aw={}local av={}
for aG in J.list(ab)do
if aG:sub(1,#ax)==ax then av[#av+1]=aG else
local aI,aH=pcall(J.proxy,aG)if aI and aH and aH.getLabel and aH.getLabel()==ax then aw[#aw+
1]=aG end end end;local ay=nil
if#av==1 then ay=av[1]elseif#av>1 then table.sort(av)
E(string.format("Ambiguous address prefix '%s' matches %d devices (%s, ...); use a longer prefix",ax,
#av,av[1]:sub(1,8).."..."),d.error)return end
if not ay and#aw>0 then table.sort(aw)ay=aw[1]
if#aw>1 then
E(string.format("Note: %d disks share label '%s'; mounting %s (use partial address to disambiguate)",
#aw,ax,ay:sub(1,8).."..."),d.warning)end end
if not ay then E("Device not found: "..ax,d.error)return end
local az=aA:sub(1,1)=="/"and aA or("/"..aA)local aB,aC=pcall(J.proxy,ay)if not aB then
E("Cannot proxy device",d.error)return end;if not e.exists(az)then
pcall(e.makeDirectory,az)end;local aD=I.sessionOf(a)
local aE,aF=e.mount(az,aC,aD)
if aE==false then E(tostring(aF or ao),d.error)return end;a.lastOut={"Mounted at "..az,d.highlight}else
local aw=e.mounts()
E(string.format(" %-18s %-14s %s","Mount","Label","Space"),d.title)E(string.rep("-",46),d.dim)
for ay,ax in ipairs(aw)do
local az=ax.total and math.floor(
ax.total/1024)or 0
local aA=ax.used and math.floor(ax.used/1024)or 0
E(string.format(" %-18s %-14s %dK/%dK",(ax.mountPoint or"?"):sub(1,18),(
ax.label or""):sub(1,14),aA,az),d.fg)end;local av=0;for ax in J.list("drive",true)do av=av+1 end
if av>0 then E("",d.dim)
E(av..
" unmanaged (raw) drive(s) are attached and NOT listed above:",d.warning)
E("they hold no filesystem yet, so there is nothing to mount.",d.dim)E("  drive list           see them",d.dim)
E("  drive format <addr>  make one a TBFS filesystem",d.dim)
E("  drive mount <addr>   then mount it here",d.dim)end end end
b.umount=function(E,au)
if not E[1]then au("Usage: umount <mountpoint>",d.dim)return end;if not f(au)then return end;local av=E[1]:sub(1,1)=="/"and E[1]or
("/"..E[1])local aw=I.sessionOf(a)
local ax,ay=e.unmount(av,aw)if ax then a.lastOut={"Unmounted "..av,d.highlight}else
a.lastOut={tostring(ay or
"Failed to unmount"),d.error}end end
b.jbod=function(au,E)local av=h.getJBOD and h.getJBOD()
if not av then
E("JBOD is disabled. Enable it with: bootsettings jbod on  (then reboot)",d.warning)
E("It pools several disks into one mount. See 'man jbod'.",d.dim)return end;local aw=(au[1]or"list"):lower()
local function ax(ay)local az,aA={},{}
for aB in
J.list(ab)do
if aB:sub(1,#ay)==ay then az[#az+1]=aB else local aD,aC=pcall(J.proxy,aB)if
aD and aC and aC.getLabel and aC.getLabel()==ay then
aA[#aA+1]=aB end end end;table.sort(az)table.sort(aA)
if#az==1 then return az[1]end;if#az==0 and#aA==1 then return aA[1]end;if#az>1 then return nil,
"ambiguous address prefix: "..ay end;if#aA>1 then return nil,
"ambiguous label: "..ay end
return nil,"no filesystem matches: "..ay end
if aw=="list"or aw==M then
local az=av.loadConfig(e)or{pools={}}local ay=az.pools or{}if#ay==0 then
E("No JBOD pools configured.",d.dim)end
for aB,aA in ipairs(ay)do local aC=0
for aB,aD in ipairs(aA.members or{})do for aE in
J.list(ab)do if aE==aD then aC=aC+1;break end end end
E(string.format(" %-16s %d member(s), %d present",aA.mount,# (aA.members or{}),aC),d.fg)end
E("Free space: df  ·  individual disks: disk  ·  manage: jbod create|destroy",d.dim)elseif aw=="create"then if not f(E)then return end;local ay=au[2]
if not ay or not au[3]then
E("Usage: jbod create <mountpoint> <disk> [disk...]",d.dim)
E("  <disk> = fs address prefix or label (see lsdev)",d.dim)return end;if ay:sub(1,1)~="/"then ay="/"..ay end;ay=
(e.normalize and e.normalize(ay))or ay;if not
(ay:sub(1,6)=="/mnt/"and#ay>6)then
E("JBOD mount point must be under /mnt/  (e.g. jbod create /mnt/pool ...)",d.error)return end;local aC=_G._TOS and
_G._TOS.bootAddr;local aB,aA={},{}
for aH=3,#au do local aI,aK=ax(au[aH])if not aI then
E(tostring(aK),d.error)return end
if aC and aI==aC then
E("Refusing to pool the BOOT disk ("..
aI:sub(1,8).."...).",d.error)
E("It would expose the system files inside the pool. Use data disks.",d.dim)return end;local aL,aJ=pcall(J.proxy,aI)if not aL or not aJ then
E("Cannot open disk: "..au[aH],d.error)return end;aB[#aB+1]=aJ
aA[#aA+1]=aI end;pcall(e.makeDirectory,"/mnt")
pcall(e.makeDirectory,ay)local aD=av.makePool(aB)local aE=I.sessionOf(a)
local aF,aG=e.mount(ay,aD,aE)
if not aF then E(tostring(aG or ao),d.error)return end;local az=av.loadConfig(e)or{pools={}}
az.pools=az.pools or{}for aH=#az.pools,1,-1 do if az.pools[aH].mount==ay then
table.remove(az.pools,aH)end end;az.pools[
#az.pools+1]={mount=ay,members=aA}
av.saveConfig(e,az)
a.lastOut={string.format("JBOD pool at %s (%d disks)",ay,#aA),d.highlight}elseif aw=="destroy"or aw==U then if not f(E)then return end;local ay=au[2]if not ay then
E("Usage: jbod destroy <mountpoint>",d.dim)return end
if ay:sub(1,1)~="/"then ay="/"..ay end;local aB=I.sessionOf(a)e.unmount(ay,aB)
local az=av.loadConfig(e)or{pools={}}local aA=false
for aC=# (az.pools or{}),1,-1 do if az.pools[aC].mount==ay then
table.remove(az.pools,aC)aA=true end end;if aA then av.saveConfig(e,az)end
a.lastOut={aA and
("Destroyed JBOD pool "..ay)or("No JBOD pool at "..ay),
aA and d.highlight or d.warning}else
E("Usage: jbod [list | create <mount> <disk...> | destroy <mount>]",d.dim)end end
b.netfs=function(au,E)local ay,av=I.requireRoomy(a,"kernel.netfs","admin")if not ay or
not av then E(I.loadFailure("netfs",av),d.error)
return end
local aw=(au[1]or M):lower()
local function ax()local az={}for aB,aA in ipairs(e.mounts()or{})do
if type(aA.address)==K and
aA.address:sub(1,6)=="netfs:"then az[#az+1]=aA end end
table.sort(az,function(aA,aB)return
aA.mountPoint<aB.mountPoint end)return az end
if aw==M or aw=="list"then
local az=av.isEnabled and av.isEnabled()
local aA=av.getExports and av.getExports()or{}
local aC=m and m.getServiceArm and m.getServiceArm("netfsd")
E("Serving: "..
(
az and"yes"or aC and"no (export file rejected; see: netfs exports)"or"no (service netfsd is not running)"),
az and d.highlight or d.warning)
if#aA==0 then
E("  No exports configured ("..av.EXPORTS_PATH..").",d.dim)else for aE,aD in ipairs(aA)do
E(string.format("  %-12s %-24s %s  %d peer rule(s)",aD.name,aD.path,aD.mode,# (aD.allow or{})),d.fg)end end;local aB=ax()E("",d.fg)
if#aB==0 then E("Mounted: none",d.dim)else
E("Mounted:",d.fg)
for aE,aD in ipairs(aB)do local aF=(aD.total or 0)>0
E(string.format("  %-16s %-22s %s",aD.mountPoint,aD.label,

aF and s(aD.total- (aD.used or 0)).." free"or"unreachable"),
aF and d.fg or d.warning)end end
E("Manage: netfs mount <host> <share> <mountpoint> · netfs umount <mountpoint>",d.dim)elseif aw=="exports"then local aA,aB=av.loadExports(e)if not aA then
E("Export file rejected: "..tostring(aB),d.error)
E("Nothing is served while the file is invalid.",d.dim)return end
local az=av.getExports()
if#az==0 then
E("No exports in "..av.EXPORTS_PATH,d.dim)
E("Format: { { name=\"pub\", path=\"/srv/pub\", mode=\"ro\", allow={\"<addr>\"} } }",d.dim)return end
for aD,aC in ipairs(az)do
E(string.format("%-12s %-24s %s",aC.name,aC.path,aC.mode),d.highlight)
for aD,aE in ipairs(aC.allow or{})do E("    allow "..aE,d.dim)end;if# (aC.allow or{})==0 then
E("    allow (none) — this export is unreachable",d.warning)end end
E("Changes take effect on: service restart netfsd",d.dim)elseif aw=="mount"then if not f(E)then return end;local aD,aB,az=au[2],au[3],au[4]
if not
(aD and aB and az)then
E("Usage: netfs mount <host> <share> <mountpoint>",d.dim)
E("  <host>  = peer hostname or address prefix (see net peers)",d.dim)
E("  <share> = export name on that machine (ask its operator)",d.dim)return end
if not m then E("Networking is not available.",d.error)return end;local aA=aD;local aE=m.findPeer and m.findPeer(aD)if aE and aE.addr then
aA=aE.addr end
if m.getTrust or m.getProtocol then
local aK,aJ=pcall(require,"kernel.net.trust")
if aK and aJ and aJ.getLevel and aJ.LEVEL then
if aJ.getLevel(aA)<
aJ.LEVEL.TRUSTED then
E("Peer is not TRUSTED — netfs refuses to mount from it.",d.error)
E("Raise trust first (see 'net trust'), then retry.",d.dim)return end end end;if not(az:sub(1,5)=="/mnt/"and#az>5)then
E("Mount point must be under /mnt/  (e.g. netfs mount box pub /mnt/box)",d.error)return end
local aC=av.attach(aA,aB)
local aF=aC.spaceTotal and aC.spaceTotal()or 0
if not aC.exists("/")and aF==0 then
E("Cannot reach share '"..aB.."' on "..
tostring(aA):sub(1,8)..".",d.error)
E("Check the export name, and that netfsd runs there and allows this machine.",d.dim)return end;pcall(e.makeDirectory,"/mnt")
pcall(e.makeDirectory,az)local aG=I.sessionOf(a)local aH,aI=e.mount(az,aC,aG)if not aH then
E(tostring(aI or ao),d.error)return end
E("Mounted "..aB.." from "..tostring(aA):sub(1,8)..
" at "..az,d.highlight)
E("This mount is only usable while that machine is online.",d.dim)elseif aw=="umount"then if not f(E)then return end;local az=au[2]if not az then
E("Usage: netfs umount <mountpoint>",d.dim)return end;local aA=false;for aF,aE in ipairs(ax())do if
aE.mountPoint==az then aA=true;break end end;if not aA then E(
"No netfs mount at "..az,d.warning)
E("Use 'netfs status' to list them (plain 'umount' handles local disks).",d.dim)return end
local aB=I.sessionOf(a)local aC,aD=e.unmount(az,aB)if aC then
E("Unmounted "..az,d.highlight)else
E(tostring(aD or"Failed to unmount"),d.error)end else
E("Usage: netfs [status | exports | mount <host> <share> <mount> | umount <mount>]",d.dim)end end
b.theme=function(au,E)local av=_G._TOS and _G._TOS.theme;if not av then
E("Theme manager unavailable (T1 / monochrome or low-RAM boot)",d.warning)return end
do
local aA=(au[1]or"show"):lower()
local aB={list=true,ls=true,show=true,current=true,keys=true,[""]=true}local aC={color=true,colour=true}
if aC[aA]then if not f(E)then return end elseif not aB[aA]then if
I.liveTier(a)<1 then
E("Log in as a user to set a personal theme.",d.error)return end end end
local function az(aA)if not aA then return nil end
if type(aA)~=K or#aA>16 then return nil end;local aB=aA:match("^0[xX](%x+)$")or aA:match("^#(%x+)$")or
aA:match("^(%x+)$")if aB and#
aB<=6 then return tonumber(aB,16)end
return tonumber(aA)end;local function ay(aA)return string.format("0x%06X",aA)end;local aw=
au[1]and au[1]:lower()or"show"
local ax=I.sessionOf(a)
if aw=="list"or aw=="ls"then E("Available themes:",d.title)for aB,aA in
ipairs(av.list())do
local aC=(aA==av.current().preset)and" *"or"  "
E(string.format(" %s %-10s %s",aC,aA,av.describe(aA)or""),d.fg)end
E("",d.fg)
E("'*' = currently active.  Use 'theme set <name>' to switch.",d.dim)elseif aw=="show"or aw=="current"then local aA=av.current()
E("Active theme: "..aA.preset,d.title)
E("  ".. (av.describe(aA.preset)or""),d.dim)local aB=0;for aC in pairs(aA.overrides)do aB=aB+1 end
if aB==0 then
E("No color overrides.",d.dim)else E("Overrides:",d.highlight)for aC,aD in pairs(aA.overrides)do
E(string.format("  %-14s %s",aC,ay(aD)),d.fg)end end;E("",d.fg)
E("Try: theme set <name>  |  theme color <key> <0xRRGGBB>  |  theme reset",d.dim)elseif aw=="set"or aw=="use"then local aA=au[2]if not aA then
E("Usage: theme set <name>  (theme list to see names)",d.warning)return end;local aB,aC=av.apply(aA)
if
not aB then E(aC or"apply failed",d.error)return end;E("Applied theme: "..aA,d.highlight)
if ax then
local aD,aE=av.saveForUser(ax)if not aD then
E("(not saved: "..tostring(aE)..")",d.dim)end end;c.drawAll()elseif aw=="preview"or aw=="try"then local aA=au[2]if not aA then
E("Usage: theme preview <name>",d.warning)return end;local aB,aC=av.apply(aA)if not aB then
E(aC or"apply failed",d.error)return end
E("Previewing '"..
aA.."' (not saved). Use 'theme set' to keep it.",d.highlight)c.drawAll()elseif aw=="color"or aw=="colour"then local aA,aB=au[2],au[3]if not aA or
not aB then
E("Usage: theme color <key> <0xRRGGBB>",d.warning)
E("Keys: "..table.concat(av.overridableKeys(),", "),d.dim)return end
if not
av.isOverridable(aA)then
E("Not an overridable color: "..aA,d.error)
E("Run 'theme color' with no args for the full list.",d.dim)return end;local aC=az(aB)if not aC then
E("Invalid color value: "..aB.." (try 0xFF8800)",d.error)return end
local aD,aE=av.setColor(aA,aC)
if not aD then E(aE or"color set failed",d.error)return end
E(string.format("%s = %s",aA,ay(aC)),d.highlight)if ax then av.saveForUser(ax)end;c.drawAll()elseif aw=="reset"then
local aA,aB=av.resetOverrides()
if not aA then E(aB or"reset failed",d.error)return end
E("Cleared color overrides; preset '"..av.current().preset.."' restored.",d.highlight)if ax then av.saveForUser(ax)end;c.drawAll()elseif aw=="clear"or aw==
"default"then
if not ax then E("Not logged in.",d.error)return end;local aA,aB=av.clearForUser(ax)if not aA then
E(aB or"clear failed",d.error)return end
E("Theme reset to default; saved preference cleared.",d.highlight)c.drawAll()elseif aw=="keys"then
E("Overridable color keys:",d.title)
for aB,aA in ipairs(av.overridableKeys())do E("  "..aA,d.fg)end else
E("Usage: theme <list|show|set|preview|color|reset|clear|keys>",d.warning)
E("  list                  Show available themes",d.dim)
E("  show                  Show active theme + overrides",d.dim)
E("  set <name>            Apply preset and save for this user",d.dim)
E("  preview <name>        Apply preset without saving",d.dim)
E("  color <key> <0xRGB>   Override a single color",d.dim)
E("  keys                  List overridable color keys",d.dim)
E("  reset                 Drop overrides, keep preset",d.dim)
E("  clear                 Wipe saved theme, revert to default",d.dim)end end;b.colors=b.theme
b.service=function(E,au)if not f(au)then return end
local aw,av=I.requireRoomy(a,"kernel.rc","admin")if not aw then au(I.loadFailure("service",av),d.error)
return end
if not E[1]then local ax=av.list()if#ax==0 then
au("No services registered",d.dim)return end
au(string.format(T,"Service","Status"),d.title)au(string.rep("-",28),d.dim)
for az,ay in ipairs(ax)do
local aA=
ay.running and"running"or
(ay.unavailable and("not loaded: "..ay.unavailable))or
(ay.enabled==false and"disabled")or"stopped"
au(string.format(T,ay.name:sub(1,16),aA),
ay.running and d.highlight or d.dim)end elseif E[1]=="start"and E[2]then local ax,ay=av.start(E[2])
au(
ax and"Started: "..E[2]or tostring(ay),ax and d.highlight or d.error)
if ax then local aA,az=pcall(require,"kernel.pkg")
if
aA and type(az)=="table"and az.noteServiceStarted then
local aB=az.noteServiceStarted(E[2],{session=I.sessionOf(a)})if aB then
au("Package '"..aB.."' enabled with it.",d.dim)end end end elseif E[1]=="stop"and E[2]then local ax,ay=av.stop(E[2])
au(
ax and"Stopped: "..E[2]or tostring(ay),ax and d.highlight or d.error)else au("Usage: service [start|stop <name>]",d.dim)end end
b.cron=function(au,E)if not f(E)then return end
if _G._TOS and _G._TOS.cronDisabled then
E("Cron is off in this boot profile: no job runs.",d.warning)local az=e.readFile("/etc/cron.dat")
local aC,aA=pcall(require,"kernel.serialize")local aB,ay=false,nil;if az and aC and aA then
aB,ay=pcall(aA.decode,az,{maxBytes=65536})end;local ax={}
if aB and type(ay)=="table"and
type(ay.jobs)=="table"then for aE,aD in pairs(ay.jobs)do
if type(aD)=="table"then ax[
#ax+1]={id=aE,name=tostring(aD.name)}end end end
table.sort(ax,function(aD,aE)return tostring(aD.id)<tostring(aE.id)end)
if#ax>0 then
E(#ax.." saved job(s), which run again after a normal boot:",d.dim)for aE,aD in ipairs(ax)do
E(string.format(" %-4s %s",tostring(aD.id),aD.name),d.dim)end end
if au[1]and au[1]~="list"then
E("cron: jobs cannot be changed in this boot profile; boot normally to edit them."..
"  [E-404 ERR_SAFE_MODE]",d.error)end;return end;local aw,av=I.requireRoomy(a,"kernel.cron","admin")if not aw then
E(I.loadFailure("cron",av),d.error)return end
if not au[1]or au[1]=="list"then
local ax=av.list()
if#ax==0 then E("No scheduled jobs",d.dim)return end
E(string.format(" %-4s %-16s %-8s %s","ID","Name","Every","Enabled"),d.title)
for az,ay in ipairs(ax)do
E(string.format(" %-4d %-16s %-8s %s",ay.id,ay.name:sub(1,16),ay.interval.."s",ay.enabled and
"yes"or"no"),
ay.enabled and d.fg or d.dim)end elseif au[1]=="add"and au[2]and au[3]and au[4]then
local ax=au[2]local ay=tonumber(au[3])local az=table.concat(au," ",4)if not ay then
E("Invalid interval",d.error)return end;local aA=av.add(ax,ay,az)E("Added job #"..
aA..": "..ax,d.highlight)elseif au[1]=="rm"and
au[2]then local ax=tonumber(au[2])
if ax then local ay,az=av.remove(ax)if ay then
E("Removed job #"..ax,d.highlight)else
E("cron rm: "..tostring(az or"no such job"),d.error)end else
E("Invalid ID",d.error)end else
E("Usage: cron [list|add <name> <seconds> <script>|rm <id>]",d.dim)end end end