
local ad,U,ae,O,P,V,W,S,Q,X,af,ag,ah,ai,Y,R,aj,Z,ak,_,al,am,aa,T,ab,ac,an,ao,ap,N,L,aq="  %-20s %s -> %s"," %-16s %s","(--dry-run: nothing was changed)","--allow-unsigned","--allow-unverified","--dry-run","--dryrun","--force","Aborted.","Cancel","Cannot read: ","Error: ","From repos nobody configured: ","Mount failed","No user system","Refused: ","computer","danger","disabled","filesystem","floppy","install","kernel.log","kernel.pkgsign","number","remove","repair","setTier unavailable","shell.panels.tabs","status","string","version"local M=require(aj)local K=require("component")
local J=require("shell.panels.helpers")
return
function(b,a,c)local h,H,t,e,j,g=a.K,a.E,a.P,a.F,a.D,a.U;local I,m,n=a.SC,a.NM,a.st;local d=a.T;local ar=a.tier
local l,k=a.W,a.H;local u=c.rp;local y=c.openViewTab;local C=c.openEditTab;local D=c.refreshBrowser
local as=c.canRead;local at=c.canWrite;local au=c.canAccess;local o=c.rootOnly;local f=c.adminOnly
local v=c.makeProgramEnv;local s=J.fmtSz
local av=function(E)return J.expandBuf(a,E)end;local i=c.promptInput;local q=c.confirm;local r=c.confirmTyped
b.kill=function(aw,E)
if not f(E)then return end
if not aw[1]then E("Usage: kill <pid>",d.dim)return end;local ax=tonumber(aw[1])
if ax then local ay,az=t.kill(ax)
if ay then
E("Killed PID "..ax,d.highlight)else E(tostring(az),d.error)end else E("Invalid PID",d.error)end end
b.fg=function(aw,E)if not f(E)then return end
if not aw[1]then E("Usage: fg <pid>",d.dim)return end;local ax=tonumber(aw[1])if not ax or not t.get(ax)then
E("No such process",d.error)return end
local ay,az=t.setForeground(ax,a.displayIdx)if not ay then
E(tostring(az or"Cannot foreground that process"),d.error)return end
E("Foreground: PID "..ax,d.highlight)end
b.verify=function(aw,E)if not f(E)then return end;local ax=aw and aw[1]and
tostring(aw[1]):lower()
if ax=="anchor"then local aA=false
for aD=2,#aw do
local aE=tostring(aw[aD]):lower()if aE=="--clear"or aE=="clear"then aA=true end end
if aA then if not h.clearManifestAnchor then
E("This TOS build cannot clear the anchor.",d.error)return end
local aD,aE=h.clearManifestAnchor()
if aD then
E("Manifest anchor cleared. `doctor` will report it un-anchored.",d.highlight)else
E("Could not clear the anchor: "..tostring(aE),d.error)end;return end;if not h.anchorManifestHash then
E("This TOS build has no manifest anchoring.",d.error)return end
E("Anchoring records THIS system's manifest hash in the EEPROM.",d.dim)
E("Only do it on a system you trust (fresh install, or verified).",d.dim)local aC,aB=h.anchorManifestHash()
if aC then
E("Anchored: "..
tostring(aB):sub(1,32).."...",d.highlight)
E("Your boot address was preserved; changing the boot device clears it.",d.dim)else
E("Anchor failed: "..tostring(aB),d.error)end;return end
E("=== File integrity (every system file vs the manifest) ===",d.title)
E("Checking presence, syntax, and declared hashes...",d.dim)E("")
local ay,az=pcall(h.verifySystem,function(aA,aB)E(aA,aB)end)
if not ay then E("verify: "..tostring(az),d.error)end;E("")
E("This checks FILES. For runtime health (memory/power/services), run 'doctor'.",d.dim)
E("It compares against the MANIFEST. To catch a file that changed since you",d.dim)
E("knew the system was good — and to put it back — use 'srm scan' / 'srm repair'.",d.dim)end;local z=1280
local p={tofu="trusted keys, or a new key you approve; never unsigned.",trusted="trusted keys only.",off="nothing; configured repos only."}
local function w(aw,E,ax)local ay=tostring(aw)
if not
(ay:find("not enough memory",1,true)or
ay:find("not enough free memory",1,true)or ay:find("Out of memory",1,true))then return end
local az=math.floor(
(M.totalMemory and M.totalMemory()or 0)/1024)
if az<z then
E(string.format("%s needs %d KB of RAM; this machine has %d KB.",ax,z,az),d.dim)else
E("Something else is holding the memory it needs: close other tabs or ".."programs, or reboot, and try again.",d.dim)end end;local F={list=true,search=true,available=true,info=true}
b.pkg=function(aw,E)if aw[1]and not
F[aw[1]]and not f(E)then return end
local aC,ax=J.requireRoomy(a,"kernel.pkg","admin")if not aC or not ax then local aE=J.loadFailure("pkg",ax)E(aE,d.error)
w(aE,E,"The package manager")return end;local ay=aw[1]
local function aA(aE)
for aG,aF in
ipairs(aE or{})do local aH=ax.info and ax.info(aF)
if type(aH)=="table"and
aH.kind=="service"then local aI={}
for aG,aJ in ipairs(aH.files or{})do
local aK=tostring(aJ):match("^/etc/rc%.d/(.+)%.lua$")if aK then aI[#aI+1]=aK end end
if#aI>0 then
local aJ=type(aH.service)=="table"and aH.service.defaultState==ak
E(string.format(
aJ and"  %s's service is installed switched off. To start it: service start %s"or"  %s runs as a service from the next boot. To start it now: service start %s",aF,table.concat(aI,", ")),d.dim)end end end end
local function aB()local aE={}
for aG,aF in
ipairs((ax.list and ax.list())or{})do
local aH=type(aF)=="table"and aF.name or aF;if type(aH)==L then aE[aH]=true end end;return aE end
local function aD(aE,aF)
local aG=((aE.name or"").." ".. (aE.description or"")..
" ".. (aE.category or"")):lower()return aG:find(aF:lower(),1,true)~=nil end
local function az(aE,aF)local aG=2
while aG<=#aw do local aH=tostring(aw[aG])
if aE[aH]=="value"then aG=aG+1 elseif
aH:sub(1,2)=="--"and not aE[aH]then
E(string.format("pkg %s: unknown option '%s' -- nothing was done.",tostring(ay),aH),d.error)E("Options: "..aF,d.dim)return true end;aG=aG+1 end;return false end
if not ay or ay=="list"then local aE=ax.list()if#aE==0 then
E("No packages installed.",d.dim)return end
E(string.format(" %-24s %-10s %s","name",aq,"kind"),d.title)for aG,aF in ipairs(aE)do
E(string.format(" %-24s %-10s %s",aF.name:sub(1,24),(aF.version or"?"):sub(1,10),
aF.kind or"?"),d.fg)end elseif
ay=="search"or ay=="available"then
local aE=ax.listAllAvailable({includeRemote=true})
if#aE==0 then E("No packages available.",d.dim)
E("Looked on disk under /usr/repo, /var/repo and /mnt/*",d.dim)local aH=ax.repos and ax.repos()or{}
if#aH==0 then
E("No remote repos are configured — add one with:",d.dim)
E("  pkg repo add <name> <https://host/path>",d.dim)else
E(#aH.." remote repo(s) configured but none answered.",d.dim)
E("That usually means no internet card, or the host is",d.dim)
E("unreachable. `pkg repo list` shows what is configured.",d.dim)end;return end;local aF=aw[2]
if aF then local aH={}
for aJ,aI in ipairs(aE)do if aD(aI,aF)then aH[#aH+1]=aI end end;if#aH==0 then
E("Nothing available matches '"..aF.."'. `pkg search` lists everything.",d.dim)return end;aE=aH end
table.sort(aE,function(aH,aI)
if
(aH.category or"misc")~= (aI.category or"misc")then return
(aH.category or"misc")< (aI.category or"misc")end;return(aH.name or"")< (aI.name or"")end)
E(string.format(" %-20s %-10s %s","name",aq,"source"),d.title)local aG=nil
for aI,aH in ipairs(aE)do local aJ=aH.category or"misc"if aJ~=aG then aG=aJ
E("  ["..aJ.."]",d.dim)end
local aK=aH.remote and
("repo:"..tostring(aH.repo or"?"))or tostring(aH.root or"?")
E(string.format(" %-20s %-10s %s",(aH.name or"?"):sub(1,20),(aH.version or"?"):sub(1,10),aK),d.fg)end elseif ay=="trust"then local aE=(aw[2]or"list"):lower()
if
aE=="list"then local aF=ax.trustList()
if#aF==0 then
E("No publisher keys are trusted on this machine.",d.dim)
E("Every package therefore reads as unsigned or as signed-by-an-",d.dim)
E("unknown-key, and your admin privilege is the only gate.",d.dim)
E("Add one:  pkg trust add <name> <64-hex-key>",d.dim)else
E(string.format(U,"name","fingerprint"),d.title)for aH,aG in ipairs(aF)do
E(string.format(U,aG.label:sub(1,16),aG.fingerprint),d.fg)end;E("",d.dim)
E("Compare a fingerprint with the publisher over a channel that is",d.dim)
E("NOT the disk it came on. A key that arrives with the package it",d.dim)E("signs proves nothing at all.",d.dim)end
E(string.format("Unsigned packages are currently %s.",ax.trustRequired()and"REFUSED"or
"allowed (admin gate only)"),
ax.trustRequired()and d.highlight or d.dim)
E(ah..p[ax.discoveredPolicy()].."  (pkg trust discovered)",d.dim)elseif aE=="discovered"then local aF=(aw[3]or""):lower()if aF==""then E(ah..
p[ax.discoveredPolicy()],d.fg)
E("Usage: pkg trust discovered tofu|trusted|off",d.dim)return end
if not p[aF]then
E("Usage: pkg trust discovered tofu|trusted|off",d.dim)E("  tofu     "..p.tofu,d.dim)
E("  trusted  "..p.trusted,d.dim)E("  off      "..p.off,d.dim)return end
local aG,aH=ax.trustDiscovered(aF,{session=J.sessionOf(a)})
if not aG then E(R..tostring(aH),d.error)return end;E(ah..p[aF],d.highlight)elseif aE=="add"then
if
not(aw[3]and aw[4])then
E("Usage: pkg trust add <name> <64-hex-public-key>",d.dim)
E("<name> is YOUR label for the publisher — it is how you will",d.dim)
E("refer to them locally, and has nothing to do with whatever",d.dim)E("name their disk claims.",d.dim)return end
local aF,aG=ax.trustAdd(aw[3],aw[4],{session=J.sessionOf(a)})
if not aF then E(R..tostring(aG),d.error)return end;E("Trusted '"..aw[3].."'.",d.highlight)
E("Packages signed by this key will now install without a fresh",d.dim)
E("judgement call. That is the point, and the cost.",d.dim)elseif aE==ac or aE=="rm"then if not aw[3]then
E("Usage: pkg trust remove <name>",d.dim)return end
local aF,aG=ax.trustRemove(aw[3],{session=J.sessionOf(a)})
if not aF then E(R..tostring(aG),d.error)return end
E("Removed '"..aw[3].."'. Already-installed packages are",d.highlight)
E("unaffected — this changes what will be accepted from now on.",d.dim)elseif aE=="require"then local aF=(aw[3]or""):lower()
if
aF~="on"and aF~="off"then E("Usage: pkg trust require on|off",d.dim)
E("`on` refuses unsigned packages outright. Consider what is on",d.dim)
E("your Optional Utilities disks before turning it on.",d.dim)return end
local aG,aH=ax.trustRequire(aF=="on",{session=J.sessionOf(a)})
if not aG then E(R..tostring(aH),d.error)return end
E("Unsigned packages are now "..
(aF=="on"and"REFUSED."or"allowed."),d.highlight)elseif aE=="key"then
if not aw[3]then
E("Usage: pkg trust key <publisher-label>",d.dim)
E("Prints the public key you sign as under that label, and asks",d.dim)
E("for the passphrase without echoing it. Publish the key; never",d.dim)
E("the passphrase. The label is part of the key: the same",d.dim)
E("passphrase under a different label is a different identity.",d.dim)return end
if aw[4]then
E("Too many arguments. Only the publisher label goes here — the",d.error)
E("passphrase is asked for separately, and must never be typed",d.dim)
E("on the command line where it is echoed and recalled.",d.dim)return end;if not i then
E("This needs an interactive prompt for the passphrase.",d.error)return end
local aF=i("Signing passphrase: ",96,true)if not aF or aF==""then E(Q,d.dim)return end
local aG,aI=ax.signingKey(aF,aw[3])if not aG then E(tostring(aI),d.error)return end
E(aG,d.highlight)local aJ,aH=pcall(require,T)if aJ and aH then
E("fingerprint "..aH.fingerprint(aG),d.dim)
E("signing as '"..tostring(aH.normalizeLabel(aw[3])).."'",d.dim)end else
E("Usage: pkg trust [list|add|remove|require|key] ...",d.dim)end elseif ay=="verify-sig"or ay=="checksig"then if not aw[2]then
E("Usage: pkg verify-sig <directory>",d.dim)
E("Says who signed a package WITHOUT installing it.",d.dim)return end
local aE,aF=ax.checkSignature(aw[2])if not aE then E(tostring(aF),d.error)return end
E(
"Package: "..tostring(aF and aF.name or"?"),d.title)local aH,aG=pcall(require,T)
if aH and aG then for aJ,aI in ipairs(aG.describe(aE))do
E(aI,aE.state==
"trusted"and d.highlight or(aE.state=="invalid"and d.error or
d.warning))end end elseif ay=="sign"then
if not aw[2]then
E("Usage: pkg sign <directory> --as <publisher-name>",d.dim)
E("Signs the package's manifest with a key derived from a",d.dim)
E("passphrase you will be asked for. The signature covers the",d.dim)
E("MANIFEST, which covers the file hashes, which cover the files —",d.dim)
E("so sign AFTER the hashes are final, not before.",d.dim)return end;local aE
for aK=3,#aw do if aw[aK]=="--as"then aE=aw[aK+1]end end
if not aE or aE==""then
E("Usage: pkg sign <directory> --as <publisher-name>",d.error)
E("--as is required: the label salts your signing key, so the same",d.dim)
E("passphrase under a different label is a different identity.",d.dim)
E("Use the same label every time — it is part of who you are.",d.dim)return end;if not i then
E("Signing needs an interactive prompt for the passphrase.",d.error)return end
local aF=i("Signing passphrase: ",96,true)
if not aF or aF==""then local aL,aK=pcall(require,T)
E(string.format("Aborted. A signing passphrase is required (%d+ characters).",
aL and aK and aK.KDF_MIN_PASS or 20),d.dim)
E("It IS the private key — the same passphrase always produces the",d.dim)
E("same key, on any machine, so make it long and keep it.",d.dim)return end
local aG,aH=ax.signPackage(aw[2],aF,{session=J.sessionOf(a),signer=aE})if not aG then
E("Signing failed: "..tostring(aH),d.error)return end
E("Signed. Wrote "..tostring(aH),d.highlight)E("public key "..aG,d.fg)local aJ,aI=pcall(require,T)if
aJ and aI then
E("fingerprint "..aI.fingerprint(aG),d.dim)end elseif ay=="repo"or ay=="repos"then
local aE=(aw[2]or"list"):lower()
if aE=="list"then local aF=ax.repos()
if#aF==0 then
E("No remote repositories configured.",d.dim)
E("Add one:  pkg repo add <name> <https://host/path>",d.dim)
E("The URL is the directory holding the repo's programs.cfg.",d.dim)else
E(string.format(" %-14s %s","name","url"),d.title)
for aI,aH in ipairs(aF)do
E(string.format(" %-14s %s",aH.name:sub(1,14),aH.url),d.fg)if aH.description then
E("                "..aH.description,d.dim)end end;E("",d.dim)
E("This list is the allowlist: what these serve installs like a disk.",d.dim)end;local aG=ax.knownRepos()
if#aG>0 then E("",d.dim)
E("Known (named by installed packages; not trusted):",d.title)
for aI,aH in ipairs(aG)do
E(string.format(" %2d %s",aI,aH.url),d.fg)if#aH.from>0 then
E("      from "..table.concat(aH.from,", "),d.dim)end end
E("Read only for what configured repos lack (pkg trust",d.dim)
E("discovered). Forget:  pkg repo forget <number|url|all>",d.dim)end elseif aE=="add"then
if not aw[3]or not aw[4]then
E("Usage: pkg repo add <name> <url> [description]",d.dim)
E("  url = the directory containing programs.cfg",d.dim)return end
local aF=#aw>=5 and table.concat(aw," ",5)or nil
local aG,aH=ax.addRepo(aw[3],aw[4],aF,{session=J.sessionOf(a)})
if aG then
E("Repo '"..aw[3].."' added.",d.highlight)
E("It is now an accepted source of executable code for this",d.warning)
E("machine. 'pkg repo remove "..aw[3].."' undoes that.",d.warning)else E(tostring(aH),d.error)end elseif aE==ac or aE=="rm"then if not aw[3]then
E("Usage: pkg repo remove <name>",d.dim)return end
local aF,aG=ax.removeRepo(aw[3],{session=J.sessionOf(a)})
if aF then
E("Repo '"..aw[3].."' removed.",d.highlight)else E(tostring(aG),d.error)end elseif aE=="forget"then if not aw[3]then
E("Usage: pkg repo forget <number|url|all>",d.dim)return end
local aG,aF=ax.forgetRepo(aw[3],{session=J.sessionOf(a)})
if aG then
E(("Forgot %d known repo(s)."):format(aF or 0),d.highlight)else E(tostring(aF),d.error)end else
E("Usage: pkg repo [list|add <name> <url>|remove <name>|forget <n|url|all>]",d.dim)end elseif ay=="remote"then local aE=_G._TOS and _G._TOS.internet
if aE and not
aE.available()then
E(aE.status().reason or"internet is not available",d.warning)E("'internet' shows the details.",d.dim)return end;E("Contacting configured repositories...",d.dim)
local aF=ax.searchRemote({refresh=
aw[2]=="--refresh"})if#aF==0 then
E("Nothing available. Check 'pkg repo list'.",d.dim)return end
E(string.format(" %-22s %-10s %s","name",aq,"repo"),d.title)
for aH,aG in ipairs(aF)do
E(string.format(" %-22s %-10s %s",(aG.name or"?"):sub(1,22),(
aG.version or"-"):sub(1,10),tostring(aG.repo)),d.fg)if aG.description then
E("   "..tostring(aG.description):sub(1,60),d.dim)end end;E("",d.dim)
E("Install one with:  pkg fetch <name>",d.dim)elseif ay=="fetch"then if az({[P]=true,[O]=true},"--allow-unverified --allow-unsigned")then
return end;local aF,aG,aH=nil,false,false
for aK=2,#aw do
local aL=tostring(aw[aK])if aL==P then aG=true elseif aL==O then aH=true elseif not aF then aF=aL end end
if not aF then
E("Usage: pkg fetch <name> [--allow-unverified] [--allow-unsigned]",d.dim)
E("Downloads from a configured repo, then installs it.",d.dim)return end;E("Fetching '"..aF.."'...",d.dim)
local function aI(aK)if
not(r and i)then return nil end
local aM="'"..
tostring(aK.name)..
"' is only in a repo this machine was not "..
"configured with:\n  "..

tostring(aK.repo)..
"\n"..
(
aK.by and(tostring(aK.by).." requires it.\n")or"")..

"\nIts signature is valid, but its key is not trusted here:\n  key "..
tostring(aK.fingerprint)..
"\n"..

(aK.signer and
('It calls its publisher "'..tostring(aK.signer)..
'" -- its own word, not proof.\n')or"")..
"\nCompare the fingerprint with the publisher somewhere that is NOT this repo. ".."Trusted, anything signed with this key installs from now on."
if not
r(aM,"trust",{title="A new publisher key",style="warning",yes="Trust",no="Refuse"})then
E("Refused the key "..

tostring(aK.fingerprint).." for '"..tostring(aK.name).."'.",d.dim)return nil end;local aL=i("Name this publisher (Enter refuses): ",48)if aL and
aL~=""then
E("Trusted the key "..
tostring(aK.fingerprint).." as '"..aL.."' (from "..
tostring(aK.repo)..").",d.highlight)end;return aL end
local aJ,aE=ax.installRemote(aF,{session=J.sessionOf(a),allowUnverified=aG,allowUnsigned=aH,confirmKey=aI})
if aJ then
local aK=aE and aE.discovered and
(tostring(aE.discovered)..", a repo nobody configured")or("repo '"..
tostring(aE and aE.repo).."'")
E(string.format("Installed '%s' from %s (%d files, %d bytes).",aF,aK,(aE and aE.files)or 0,
(aE and aE.bytes)or 0),d.highlight)local c=aE and aE.dependencies;if type(c)=="table"and#c>0 then
E(
"  ...and what it requires: "..table.concat(c,", "),d.highlight)end else
E(tostring(aE),d.error)
if tostring(aE):find("hash",1,true)or
tostring(aE):find("unverified",1,true)then E("",d.dim)
E("That repo ships no file hashes, so TOS cannot check what it",d.dim)
E("sent. Re-run with --allow-unverified if you trust it.",d.dim)end end elseif ay=="outdated"or ay=="updates"then local aE=ax.outdated()
if#aE==0 then
E("Everything is up to date (against what's mounted right now).",d.highlight)
E("Insert another disk and re-run to check against it too.",d.dim)return end
E(string.format(" %-20s %-10s %-10s %s","name","installed","available","from"),d.title)
for aG,aF in ipairs(aE)do
E(string.format(" %-20s %-10s %-10s %s",aF.name:sub(1,20),tostring(aF.from):sub(1,10),tostring(aF.to):sub(1,10),tostring(
aF.root or"?")),d.fg)end;E("",d.dim)
E("pkg upgrade <name>   or   pkg upgrade --all --yes",d.dim)elseif ay=="upgrade"then
if
az({["--all"]=true,["--yes"]=true,[S]=true,[V]=true,[W]=true,[P]=true,[O]=true},"--all --yes/-y --force --dry-run --allow-unverified --allow-unsigned")then return end;local aI,aJ,aK,aL=false,false,false,false;local aM,aN=false,false;local aF={}
for aO=2,#aw do
local aP=tostring(aw[aO])
if aP=="--all"then aI=true elseif aP=="--yes"or aP=="-y"then aJ=true elseif aP==S then aK=true elseif
aP==V or aP==W then aL=true elseif aP==P then aM=true elseif aP==O then aN=true elseif aP:sub(1,2)~="--"then aF[#aF+1]=aP end end;local aE={}
if aI then
for aP,aO in ipairs(ax.outdated())do aE[#aE+1]=aO end elseif#aF>0 then local aO={}
for aQ,aP in ipairs(ax.outdated())do aO[aP.name]=aP end;for aQ,aP in ipairs(aF)do
aE[#aE+1]=aO[aP]or{name=aP,from="?",to="?"}end else
E("Usage: pkg upgrade <name>… | --all [--yes] [--force] [--dry-run]",d.dim)
E("                   [--allow-unverified] [--allow-unsigned]",d.dim)
E("       pkg outdated   shows what has a newer version available",d.dim)return end
if#aE==0 then E("Nothing to upgrade.",d.highlight)return end
if aL then
E(string.format("Would upgrade %d package(s):",#aE),d.title)for aP,aO in ipairs(aE)do
E(string.format(ad,aO.name,tostring(aO.from),tostring(aO.to)),d.fg)end;E(ae,d.dim)return end
if aI and not aJ then
E(string.format("--all would upgrade %d package(s):",#aE),d.warning)for aP,aO in ipairs(aE)do
E(string.format(ad,aO.name,tostring(aO.from),tostring(aO.to)),d.fg)end
E("Add --yes to proceed.",d.dim)return end;local aG,aH=0,0
for aP,aO in ipairs(aE)do
local aR,aQ=ax.upgrade(aO.name,{session=J.sessionOf(a),force=aK,allowUnverified=aM,allowUnsigned=aN})
if aR then aG=aG+1
E(string.format(ad,aO.name,tostring(aQ.from),tostring(aQ.to)),d.highlight)if aQ.dropped and#aQ.dropped>0 then
E(string.format("      %d file(s) no longer shipped, removed",#
aQ.dropped),d.dim)end
if
aQ.enabled==false then E("      (was disabled; left disabled)",d.dim)end else aH=aH+1
E(string.format("  %-20s FAILED: %s",aO.name,tostring(aQ)),d.error)end end
E(string.format("%d upgraded, %d failed.",aG,aH),aH>0 and d.warning or d.highlight)
if aG>0 then
E("Services keep their enabled/disabled state; restart them to run the",d.dim)
E("new code ('service stop <svc>' then 'service start <svc>').",d.dim)end elseif ay=="info"then
if not aw[2]then E("Usage: pkg info <name>",d.dim)return end;local aE=ax.info(aw[2])if not aE then
E("Not installed: "..aw[2],d.error)return end
E(string.format(" name:        %s",aE.name),d.title)
E(string.format(" version:     %s",aE.version or"?"),d.fg)
E(string.format(" kind:        %s",aE.kind or"?"),d.fg)
if aE.lua or aE.tos then
E(string.format(" needs:       %s%s%s",
aE.lua and("Lua "..aE.lua.."+")or"",(aE.lua and aE.tos)and", "or"",
aE.tos and("TOS "..aE.tos)or""),d.fg)end;if aE.category then
E(string.format(" category:    %s",aE.category),d.fg)end;if aE.description then
E(string.format(" description: %s",aE.description),d.fg)end;if aE.author then
E(string.format(" author:      %s",aE.author),d.fg)end
E(string.format(" status:      %s",
ax.isEnabled(aE.name)and"enabled"or ak),
ax.isEnabled(aE.name)and d.highlight or d.dim)
if type(aE.commands)=="table"then local aF={}for aG in pairs(aE.commands)do
aF[#aF+1]=aG end
if#aF>0 then table.sort(aF)E(" commands:    "..
table.concat(aF,", "),d.fg)end end
if aE.requires and#aE.requires>0 then E(" requires:",d.fg)
for aG,aF in
ipairs(aE.requires)do local aH,aI;if type(aF)=="table"then aH,aI=aF.name,aF.version else
aH,aI=aF:match("^(%S+)%s*(.*)$")end
E(string.format("   %s %s",aH,aI or""),d.dim)end end;if aE.provides and#aE.provides>0 then
E(" provides:    "..
table.concat(aE.provides,", "),d.fg)end;if aE.recommends and
#aE.recommends>0 then
E(" recommends:  "..table.concat(aE.recommends,", "),d.dim)end;if aE.conflicts and
#aE.conflicts>0 then
E(" conflicts:   "..table.concat(aE.conflicts,", "),d.warning)end
if aE.origin=="openos"then
E(" origin:      OpenOS/OPPM package (runs on the compat layer)",d.warning)if aE.capsFromCompat then
E("              declared no capabilities — granted: "..
table.concat(aE.capabilities or{},", "),d.warning)end end
do local n=aE._sigState or"unsigned"
if n=="trusted"then
E(string.format(" signature:   signed by trusted publisher '%s'",tostring(aE._sigLabel)),d.highlight)elseif n=="unknown"then
E(" signature:   valid, but the key was not trusted at install time",d.warning)else E(" signature:   none (unsigned)",d.dim)end
if aE._sigKey then local aG,aF=pcall(require,T)
local aH=
(aG and aF and aF.fingerprint)and aF.fingerprint(aE._sigKey)or
aE._sigKey:sub(1,16)E("              key "..aH,d.dim)end
E(string.format(" integrity:   %s",
aE._unverified and"NOT verified (installed with --allow-unverified)"or"all files matched their declared hashes"),
aE._unverified and d.warning or d.dim)end elseif ay==am or ay=="install-dir"or ay=="from-floppy"or ay==
"fromfloppy"then
if
az({[P]=true,[O]=true,[S]=true,["--all"]=true,["--yes"]=true,[V]=true,[W]=true,["--key"]="value",["--prompts"]=true,["--classic"]=true},
"--all --yes/-y --dry-run --force --allow-unverified --allow-unsigned ".."--key <key> --prompts")then return end;local aG,aM,aN,aJ=false,false,false,false;local aH,aF=false,false;local aK={}
for aP=2,#aw do
local aQ=tostring(aw[aP])
if aQ==P then aG=true elseif aQ==O then aH=true elseif aQ==S then aF=true elseif aQ=="--all"then aM=true elseif
aQ=="--yes"or aQ=="-y"then aN=true elseif aQ==V or aQ==W then aJ=true elseif aQ=="--key"then elseif aw[aP-1]=="--key"then elseif
aQ:sub(1,2)~="--"then aK[#aK+1]=aQ end end;local aI=aK[1]local function aO(aP)return
type(aP)==L and aP:find("/",1,true)~=nil end;local aE
if aM then aE="all"elseif ay==
"install-dir"then aE="dir"elseif ay=="from-floppy"or ay=="fromfloppy"then aE=al elseif not aI then
aE=al elseif aO(aI)then aE="dir"elseif#aK>1 then aE="many"else aE="name"end
local function aL(aP)
if#aP==0 then E("Nothing to install.",d.dim)return end
if aJ then
E(string.format("Would install %d package(s):",#aP),d.title)local aS=0
for aU,aT in ipairs(aP)do local aV,aW
if ax.planByName then aV,aW=ax.planByName(aT)end
if not aV then E("  "..aT,d.fg)if aW then aS=aS+1
E("    would fail: "..tostring(aW),d.error)end else E("  "..aT,d.fg)local aX={}for aU,aY in
ipairs(aV.order or{})do
aX[#aX+1]=(ax.info and ax.info(aY))and
(aY.." (installed)")or aY end
if#aX>1 then E("    order: "..
table.concat(aX,", "),d.dim)end;for aU,aY in ipairs(aV.contradictions or{})do
E("    ! "..tostring(aY.text),d.warning)end
if#
(aV.contradictions or{})>0 then
if aF then
E("    --force: would install past "..
#aV.contradictions.." contradiction(s)",d.warning)else aS=aS+1
E("    would be refused (--force overrides)",d.error)end end end end;if aS>0 then
E(string.format("%d of %d would not install as things stand.",aS,#aP),d.warning)end;E(ae,d.dim)return end;local aR,aQ=0,0
for aT,aS in ipairs(aP)do
local aV,aU=ax.installByName(aS,{session=J.sessionOf(a),allowUnverified=aG,allowUnsigned=aH,force=aF})
if aV then aR=aR+1
E(string.format("  %-20s installed%s",aS,
(#aU.skipped>0)and(" (deps present: "..
table.concat(aU.skipped,", ")..")")or""),d.highlight)else aQ=aQ+1
E(string.format("  %-20s FAILED: %s",aS,tostring(aU)),d.error)end end
E(string.format("%d installed, %d failed.",aR,aQ),aQ>0 and d.warning or d.highlight)end
if aJ and(aE=="name"or aE=="dir")then aL({aI})return elseif aJ and
aE==al then local aP={}for aR,aQ in ipairs(ax.listAllAvailable()or{})do
if not(ax.info and
ax.info(aQ.name))then aP[#aP+1]=aQ.name end end
table.sort(aP)
if#aP==0 then E("Nothing to install.",d.dim)return end
E(string.format("Would offer %d package(s) to choose from:",#aP),d.title)for aR,aQ in ipairs(aP)do E("  "..aQ,d.fg)end;E(ae,d.dim)
return end
if aE=="all"then
if not(aN or aJ)then
E("--all installs EVERY package on every inserted disk and repo.",d.warning)
E("Add --yes to confirm, or --dry-run to see the list first.",d.dim)return end;local aP={}for aR,aQ in ipairs(ax.listAllAvailable()or{})do
if not(ax.info and
ax.info(aQ.name))then aP[#aP+1]=aQ.name end end
table.sort(aP)aL(aP)return elseif aE=="many"then aL(aK)return end
if aE=="name"then local aQ;for aS=3,#aw do
if aw[aS]=="--key"and aw[aS+1]then aQ=aw[aS+1]end end
local aR,aP=ax.installByName(aI,{licenseKey=aQ,session=J.sessionOf(a),allowUnverified=aG,allowUnsigned=aH,force=aF})
if aR then
E(string.format("Installed: %s",table.concat(aP.installed,", ")),d.highlight)aA(aP.installed)if#aP.skipped>0 then
E(string.format("Skipped (already present): %s",table.concat(aP.skipped,", ")),d.dim)end else
E("Install failed: "..tostring(aP),d.error)w(aP,E,"Installing packages")end elseif aE=="dir"then
if not aI then E("Usage: pkg install <dir>",d.dim)return end;local aQ=aB()
local aR,aP=ax.install(aI,{session=J.sessionOf(a),allowUnverified=aG,allowUnsigned=aH,force=aF})
if aR then local aS={}
for aT in pairs(aB())do if not aQ[aT]then aS[#aS+1]=aT end end;table.sort(aS)
E("Installed: "..
(#aS>0 and
(table.concat(aS,", ").." (")or"")..
tostring(aP).. (#aS>0 and")"or""),d.highlight)aA(aS)else
E("Install failed: "..tostring(aP),d.error)w(aP,E,"Installing packages")end else local aQ=false;for aT=2,#aw do if aw[aT]=="--prompts"or aw[aT]=="--classic"then
aQ=true end end
local aR=false
if not aQ and ax.runInstaller then
local aU,aT=ax.runInstaller({session=J.sessionOf(a),allowUnverified=aG,allowUnsigned=aH,force=aF})
if aU then aR=true
if a.D and a.D.invalidate then pcall(a.D.invalidate)end;if c.drawAll then pcall(c.drawAll)end elseif aT then
E("Menu installer unavailable ("..tostring(aT)..
") — using prompts.",d.dim)end end;if aR then return end
local aS,aP=ax.installFromFloppy({session=J.sessionOf(a),allowUnverified=aG,allowUnsigned=aH,force=aF,confirm=function(aW,aV,aU,aT)
if q then
local a_={title="Install from media",severity=am,yes="Install",no="Skip",progress=
(aU and aT and aT>1)and{index=aU,total=aT}or nil}if aU and aT and aU<aT then a_.redraw=false end;return
q("Install  "..aW.."?".."\n\n".."From:"..
"\n  "..aV,a_)end;if not i then return false end
local aY=aV:match("^(/mnt/[^/]+)")or aV;local aZ=
(aU and aT and aT>1)and string.format(" (%d/%d)",aU,aT)or""local aX=
i("Install "..aW..
" from "..aY..aZ.."? [y/N]: ",4)or""return
aX:lower()=="y"or aX:lower()=="yes"end})
if aS then if#aP.installed>0 then
E(string.format("Installed from media: %s",table.concat(aP.installed,", ")),d.highlight)end;if
#aP.skipped>0 then
E(string.format("Skipped: %s",table.concat(aP.skipped,", ")),d.dim)end;if#aP.installed==0 and
#aP.skipped==0 then
E("No packages found on mounted media. Insert a package disk and retry.",d.dim)end else E("Media scan failed: "..
tostring(aP),d.error)end end elseif ay=="license-hash"then if not aw[2]or not aw[3]then
E("Usage: pkg license-hash <package-name> <license-key>",d.dim)return end
local aE,aF=ax.computeLicenseHash(aw[2],aw[3])
if aE then E(aE,d.fg)else E(ag..tostring(aF),d.error)end elseif ay=="uninstall"or ay==ac then if not aw[2]then
E("Usage: pkg uninstall <name>",d.dim)return end
local aE,aF=ax.uninstall(aw[2],{session=J.sessionOf(a)})if aE then E("Uninstalled: "..aw[2],d.highlight)else
E(
"Uninstall failed: "..tostring(aF),d.error)end elseif ay=="make-disk"or
ay=="export-disk"then
if not aw[2]then
E("Usage: pkg make-disk <mount> [name ...]",d.dim)
E("  Builds an Optional Utilities disk from your INSTALLED add-ons so",d.dim)
E("  you can install them on another TOS machine without a dev box.",d.dim)
E("  Name args limit the export; omit to include every add-on.",d.dim)E("  e.g. pkg make-disk /mnt/floppy",d.dim)return end;if not ax.exportDisk then
E("This TOS build has no make-disk support.",d.error)return end;local aF=nil;if aw[3]then aF={}for aH=3,#aw do
aF[#aF+1]=aw[aH]end end
local aG,aE=ax.exportDisk(aw[2],{only=aF,session=J.sessionOf(a)})
if aG then
E(string.format("Built add-on disk on %s: %d package(s), %d file(s)",aE.target,#aE.packages,aE.files),d.highlight)if#aE.packages>0 then
E("  "..table.concat(aE.packages,", "),d.fg)end;if#aE.problems>0 then
E("  Warnings:",d.warning)
for aI,aH in ipairs(aE.problems)do E("   ! "..aH,d.warning)end end
E("On the target machine, insert the disk and run 'pkg install'.",d.dim)else
E("make-disk failed: "..tostring(aE),d.error)end elseif ay=="enable"or ay=="disable"then if not aw[2]then
E("Usage: pkg "..ay.." <name>",d.dim)return end;local aE=(ay=="enable")
local aF,aG=ax.setEnabled(aw[2],aE,{session=J.sessionOf(a)})
if aF then
E((aE and"Enabled: "or"Disabled: ")..aw[2],d.highlight)else E("Failed: "..tostring(aG),d.error)end elseif ay=="commands"then local aF=ax.commands()local aE={}
for aG in pairs(aF)do aE[#aE+1]=aG end;if#aE==0 then
E("No commands provided by installed packages.",d.dim)return end;table.sort(aE)
E("Commands provided by packages:",d.title)for aH,aG in ipairs(aE)do E("  "..aG,d.fg)end else
E("Usage: pkg [list | search | info <name> | install [name|dir] | uninstall <name>",d.dim)
E("           | enable <name> | disable <name> | commands | make-disk <mnt>]",d.dim)
E("  install: a name installs by name; a path installs that dir; no arg",d.dim)
E("           scans mounted media. Shortcuts: 'install <name>', 'uninstall <name>'.",d.dim)
E("  signing: trust [list|add|remove|require|key] · verify-sig <dir> · sign <dir>",d.dim)end end
b.install=function(E,aw)local ax={am}for ay=1,# (E or{})do ax[#ax+1]=E[ay]end;return
b.pkg(ax,aw)end
b.uninstall=function(E,aw)local ax={"uninstall"}
for ay=1,# (E or{})do ax[#ax+1]=E[ay]end;return b.pkg(ax,aw)end
b.backup=function(aw,E)if not f(E)then return end;local ax=_G._TOS and _G._TOS.backup
if
not ax then E("backup module unavailable",d.error)return end;local ay=aw[1]local az=J.sessionOf(a)
if ay=="snapshot"or ay=="create"then if not
aw[2]or not aw[3]then
E("Usage: backup snapshot <src> <dest.bak>",d.dim)return end
local aB,aA=ax.snapshot(aw[2],aw[3],{session=az})
if aB then
E(string.format("Snapshot OK: %d entries, %d bytes -> %s",aA.entries,aA.bytes,aw[3]),d.highlight)
E("  metaHash: "..aA.hash:sub(1,16).."...",d.dim)else
E("Snapshot failed: "..tostring(aA),d.error)end elseif ay=="inspect"then if not aw[2]then
E("Usage: backup inspect <file.bak>",d.dim)return end
local aA,aB=ax.inspect(aw[2],{session=az})if not aA then
E("Inspect failed: "..tostring(aB),d.error)return end
E(string.format(" magic:    %s",aA.magic),d.fg)
E(string.format(" created:  %s",aA.created>978307200 and
os.date("%Y-%m-%d %H:%M:%S UTC",aA.created)or tostring(aA.created)),d.fg)
E(string.format(" entries:  %d",aA.entries),d.fg)
E(string.format(" root:     %s",aA.root),d.fg)
E(string.format(" metaHash: %s...",aA.metaHash:sub(1,24)),d.fg)
E(string.format(" size:     %d bytes",aA.size),d.fg)elseif ay=="restore"then if not aw[2]then
E("Usage: backup restore <file.bak> [destRoot] [--force]",d.dim)return end;local aB,aC=nil,false
for aE=3,#aw do if
aw[aE]==S or aw[aE]=="-f"then aC=true else aB=aw[aE]end end
local aD,aA=ax.restore(aw[2],{session=az,destRoot=aB,force=aC})
if aD then
E(string.format("Restore OK: %d/%d files -> %s",aA.restored,aA.entries,aA.destRoot),d.highlight)D()else
E("Restore failed: "..tostring(aA),d.error)end else
E("Usage: backup [snapshot|inspect|restore] ...",d.dim)E("  backup snapshot <src> <dest.bak>",d.dim)
E("  backup inspect  <file.bak>",d.dim)
E("  backup restore  <file.bak> [destRoot] [--force]",d.dim)end end
b.kiosk=function(aw,E)if not f(E)then return end
local ay,ax=J.requireRoomy(a,"shell.kiosk","admin")if not ay or not ax then
E(J.loadFailure("kiosk",ax),d.error)return end
E("Kiosk = the LOCKED, guest-facing menu (allow-list + read-only).",d.title)
E("To test: log out, log in as the 'kiosk' user.",d.dim)E("Config: /etc/kiosk.cfg",d.dim)E("",d.fg)
E("Looking for the OPERATOR menu? Run 'desktop': the same kind of",d.highlight)
E("clickable menu, but it runs real commands at YOUR tier (no allow-list).",d.dim)end
b.doctor=function(aw,E)local az,ay=J.requireRoomy(a,"kernel.diag","admin")if not az or
not ay then E(J.loadFailure("doctor",ay),d.error)
return end
local aA={ok=d.highlight or d.fg,info=d.dim or d.fg,warn=d.warning or d.fg,err=
d.error or d.fg}local aB=aw[1]
E("=== TOS doctor \226\128\148 runtime health ===",d.title)
local ax=ay.run(function(aE,aF)E(aE,aA[aF]or d.fg)end,{only=aB})E("",d.dim)
local aC=string.format("Summary: %d ok, %d info, %d warn, %d err",ax.ok,ax.info,ax.warn,ax.err)local aD=ax.err>0 and d.error or ax.warn>0 and d.warning or
d.highlight
E(aC,aD)
E("This checks RUNTIME health. For a full file-integrity check, run 'verify'.",d.dim)
E("'srm' runs both, plus the known-good baseline check.",d.dim)end;b.diag=b.doctor
b.srm=function(aw,E)
local aE,ay=J.requireRoomy(a,"kernel.srm","admin")if not aE or not ay then
E(J.loadFailure("srm",ay),d.error)return end
local aB={ok=d.highlight or d.fg,info=d.dim or d.fg,warn=d.warning or d.fg,err=
d.error or d.fg}local function aA(aF)
for aH,aG in ipairs(aF.findings)do E(aG.text,aB[aG.sev]or d.fg)end;return aF end
local function aC(aF)local aG=aF.counts
E("",d.dim)
E(string.format("%d ok, %d info, %d warn, %d err%s",aG.ok,aG.info,aG.warn,aG.err,(aF.fixed or 0)>0 and(
"  |  "..aF.fixed.." fixed")or""),
aB[ay.worst(aF)]or d.fg)end;local az,ax,aD=ay.parseArgs(aw)if ax.source==true then
E("--source needs a mount point, e.g. --source /mnt/floppy",d.error)return end
if az==N then
E("=== SRM \226\128\148 System Repair & Maintenance ===",d.title)aC(aA(ay.status()))E("",d.dim)
E("scan = compare files to the baseline   health = runtime   verify = manifest",d.dim)
E("repair = fix what is safe             baseline = record a known-good system",d.dim)elseif az=="health"then return b.doctor(aD,E)elseif az=="verify"then return b.verify(aD,E)elseif
az=="scan"then
E("=== SRM scan \226\128\148 files vs the known-good baseline ===",d.title)
E("Hashing every baselined file; this takes a moment.",d.dim)aC(aA(ay.scan()))elseif az=="baseline"then if not f(E)then return end
E("Recording what THIS system looks like right now as the known-good",d.title)
E("baseline. Only do that on a system you trust — a fresh install, or",d.dim)
E("one that just passed 'srm verify'. Anything already wrong becomes",d.dim)E("the new definition of correct.",d.dim)
E("",d.dim)local aG=ax.full and true or false
local aH,aF=ay.baseline(nil,{content=aG})if not aH then
E("Baseline failed: "..tostring(aF),d.error)return end
E(string.format("Baseline captured from %s: %d file(s) hashed.",tostring(aF.source),aF.hashed),d.highlight)
if aG then
E(string.format("  %d copy(ies) stored, %.1f KB of disk.",aF.stored,aF.bytes/1024),d.fg)
E("  Local repair is now possible: 'srm repair --restore'.",d.fg)else
E("  Hashes only — drift is detectable, but repair will need",d.fg)
E("  '--source <mount>' (e.g. the install floppy). Use --full to",d.dim)
E("  store verified copies locally instead.",d.dim)end
if aF.skipped>0 then
E(string.format("  %d file(s) skipped (over the %d KB store cap or unreadable).",aF.skipped,ay.MAX_STORE_BYTES/1024),d.warning)end;if aF.pruned>0 then
E(string.format("  %d stale copy(ies) from the previous baseline removed.",aF.pruned),d.fg)end
for aJ,aI in ipairs(aF.missing)do E(
"  MISSING at capture time: "..aI,d.warning)end elseif az=="restore"then if not f(E)then return end
E("=== SRM restore ===",d.title)
aC(aA(ay.restore(nil,{source=type(ax.source)==L and ax.source or nil,unverified=
ax.unverified and true or false,paths=#aD>0 and aD or nil})))elseif az==an and ax.online then if not f(E)then return end
if ax.apply and not o(E)then return end;if ax.ref==true then
E("--ref needs a value, e.g. --ref=build-2603a5b or --ref=main",d.error)return end
local aH,aG=pcall(require,"kernel.netrepair")if not aH or not aG then
E("online repair unavailable: "..tostring(aG),d.error)return end
E("=== SRM repair --online ===",d.title)
local aF=aG.run(nil,{apply=ax.apply and true or false,unanchored=ax.unanchored and true or false,ref=
type(ax.ref)==L and ax.ref or nil})
for aJ,aI in ipairs(aF.lines)do E(aI.text,aB[aI.sev]or d.fg)end;if ax.apply then E("",d.dim)
E(string.format("%d repaired, %d rejected.",aF.fixed,aF.rejected),
aF.ok and aB.ok or aB.warn)end elseif az==an then if not f(E)then
return end;E("=== SRM repair ===",d.title)
if not ax.restore then
E("Fixing what is mechanically safe (interrupted writes, stale state,",d.dim)
E("oversized logs). Add --restore to also put back system files that",d.dim)
E("are missing or have changed since the baseline.",d.dim)end;E("",d.dim)
aC(aA(ay.repair(nil,{restore=ax.restore and true or false,source=
type(ax.source)==L and ax.source or nil,unverified=ax.unverified and true or false})))E("",d.dim)
E("Some fixes only apply at boot: 'bootsettings repair on' runs this",d.dim)
E("pass before anything reads the files it repairs.",d.dim)elseif az=="full"then E("=== SRM full report ===",d.title)
E("",d.dim)E("-- status --",d.title)aA(ay.status())
E("",d.dim)E("-- health --",d.title)b.doctor({},E)E("",d.dim)
E("-- integrity --",d.title)b.verify({},E)E("",d.dim)E("-- baseline --",d.title)
aC(aA(ay.scan()))else
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
b.bootsettings=function(aw,E)if not f(E)then return end
local aD,aB=pcall(require,"kernel.bootcfg")
if not aD or not aB then E("bootcfg unavailable",d.error)return end;local aC=_G._TOS and _G._TOS.fs;if not aC then
E("fs unavailable",d.error)return end;local ax=aB.load(aC)
local az=(aw[1]or""):lower()
if az==""or az=="show"then
E("=== Boot Settings (/etc/boot.cfg) ===",d.title)
E("  profile    : "..ax.profile..
(ax.profile=="safe"and"   (SAFE MODE)"or"   (what loads)"),d.fg)
E("  verbosity  : ".. (ax.verbosity or"auto").."   (what it says)",d.fg)
local aG=
ax.ui=="cli"and"cli"or ax.ui=="split"and"panels (split)"or ax.ui=="home"and"panels"or
(
"auto (panels from "..aB.PANELS_MIN_KB.." KB, else cli)")
E("  interface  : "..aG.."   (all seats)",d.fg)
E("  repair     : "..
(ax.repair and"RUN on next boot"or"off"),d.fg)
E("  showConfig : ".. (ax.showConfig and"on"or"off"),d.fg)
E("  cpuTier    : "..
(ax.cpuTier and("Tier "..ax.cpuTier)or"auto"),d.fg)
E("  dataTier   : "..
(ax.dataTier and("Tier "..ax.dataTier)or"auto"),d.fg)
E("  ramGate    : "..
(ax.ramGate==nil and"auto (measure)"or
(
ax.ramGate and"always load the extras"or"never load the extras")),d.fg)local aF=false
for aJ,aI in ipairs(aB.FEATURES)do
local aK=ax.advanced and ax.advanced[aI]if aK~=nil then
E("    +"..aI.." : ".. (aK and"on"or"off"),d.dim)aF=true end end
if not aF then E("    (no advanced overrides)",d.dim)end
E("Profiles: "..
table.concat(aB.PROFILE_ORDER or{"minimal","normal","full","diagnostic"}," | "),d.dim)
E("Verbosity: silent | splash | text | verbose | auto",d.dim)
E("Set: bootsettings <profile|verbosity|ui|repair|show|cputier|datatier|ramgate|"..table.concat(aB.FEATURES,"/")..
"> <value>",d.dim)
E("DEL during boot opens the full visual editor; S = Safe Mode once.",d.dim)local aH,aE=pcall(require,"kernel.sysinfo")
if aH and aE then E("",d.dim)
for aJ,aI in
ipairs(aE.rows(aE.gather(
nil,{cpuTier=ax.cpuTier,dataTier=ax.dataTier})))do if aI.role=="section"then E(aI.value..":",d.title)else
E("  ".. (aI.label~=""and(
aI.label..": ")or"")..
aI.value,d.dim)end end end;return end;local ay=(aw[2]or""):lower()local aA=false
if az=="profile"then
if
aB.PROFILES[ay]then ax.profile=ay;aA=true else
E("profiles: "..table.concat(aB.PROFILE_ORDER or
{"minimal","normal","full","diagnostic"}," "),d.error)return end elseif az=="verbosity"then
if ay=="auto"then ax.verbosity=nil;aA=true else local aE=false;for aG,aF in
ipairs(aB.VERBOSITY)do if aF==ay then aE=true end end;if aE then ax.verbosity=ay
aA=true else
E("verbosity: silent splash text verbose (or auto)",d.error)return end end elseif az=="show"or az=="showconfig"then ax.showConfig=(ay=="on"or ay=="true"or
ay=="1")aA=true elseif az=="cputier"or az==
"cpu"then
if ay=="auto"then ax.cpuTier=nil;aA=true elseif
ay=="1"or ay=="2"or ay=="3"then ax.cpuTier=tonumber(ay)aA=true else
E("cputier: auto | 1 | 2 | 3",d.error)return end elseif az=="datatier"or az=="data"then
if ay=="auto"then ax.dataTier=nil;aA=true elseif ay=="1"or
ay=="2"or ay=="3"then ax.dataTier=tonumber(ay)aA=true else
E("datatier: auto | 1 | 2 | 3",d.error)return end elseif az=="ui"or az=="interface"then
if
ay=="panels"or ay=="tui"or ay=="home"then ax.ui="home"aA=true elseif ay=="cli"or ay=="split"then ax.ui=ay;aA=true elseif ay=="auto"then ax.ui=
nil;aA=true else
E("ui: auto (by memory) | panels | split | cli",d.error)return end elseif az==an then
if ay=="on"or ay=="once"or ay=="1"then ax.repair=true;aA=true elseif ay==
"off"or ay=="0"then ax.repair=false;aA=true else
E("repair: on (runs once next boot, then clears) | off",d.error)return end elseif az=="ramgate"or az=="ram"then
if ay=="auto"then ax.ramGate=nil;aA=true elseif ay=="always"or ay==
"plenty"or ay=="on"then ax.ramGate=true;aA=true elseif
ay=="never"or ay=="tight"or ay=="off"then ax.ramGate=false;aA=true else
E("ramgate: auto (measure free RAM) | always | never  (load the optional extras)",d.error)return end elseif az=="reset"then ax=aB._normalize({})aA=true else local aE=false;for aG,aF in ipairs(aB.FEATURES)do if
aF==az then aE=true end end
if aE then
ax.advanced=ax.advanced or{}
if ay=="auto"then ax.advanced[az]=nil elseif ay=="on"then ax.advanced[az]=true elseif
ay=="off"then ax.advanced[az]=false else
E(az..": auto | on | off",d.error)return end;aA=true else
E("Unknown setting: "..az.." (try: bootsettings show)",d.error)return end end
if aA then local aE,aF=aB.save(aC,ax)if aE then
E("Saved. Applies on next boot (reboot to apply now).",d.highlight)else
E("Save failed: "..tostring(aF),d.error)end end end
local function A()local ax,E=pcall(require,"kernel.bootcfg")
local aw=_G._TOS and _G._TOS.fs;if ax and E and aw then return E,aw end end
local function B(aw,E)local ax=h.getSwap and h.getSwap()
if aw=="now"then
local aE,aD=pcall(require,ap)if not aE or not aD.sweepCold then
E("tab paging unavailable",d.error)return end;if not ax then
E("Swap not available",d.error)return end;local aF=aD.sweepCold(a,true)
local aG,aH=aD.pagedStats(a)
E(string.format("Paged out %d view tab(s) now.",aF),d.highlight)
E(string.format("%d tab(s) on disk, %d lines held there.",aG,aH),d.dim)
E("They page back transparently the next time you open them.",d.dim)return end
if aw==""or aw==N or aw=="keys"or aw=="clear"then if not ax then
E("Swap not available",d.error)return end
if aw=="clear"then if not f(E)then return end
local aG,aF=pcall(require,ap)
if aG and aF.isPaged then for aI,aH in ipairs(a.tabs or{})do
if aF.isPaged(aH)then local aI=aH.content end end end;ax.clear()E("Swap cleared.",d.highlight)return end;local aD=ax.usage()
local aE=(aD.max and aD.max>0)and math.floor(aD.bytes*100/
aD.max)or 0;E("=== Disk Swap (/var/swap) ===",d.title)
E(string.format("Used:    %s / %s (%d%%)",s(aD.bytes),s(aD.max),aE),
aE>90 and d.warning or d.fg)
E(string.format("Entries: %d",aD.count),d.dim)if aw=="keys"and ax.keys then local aF=ax.keys()
if#aF==0 then
E("(no keys)",d.dim)else for aH,aG in ipairs(aF)do E("  "..aG,d.dim)end end end
do
local aI,aG=pcall(require,ap)if aI and aG.pagedStats then local aJ,aK=aG.pagedStats(a)
E(string.format("View tabs paged: %d (%d lines)",aJ,aK),
aJ>0 and d.highlight or d.dim)end;local aH,aF=25,(
h.getConfig and h.getConfig())if
aF and aF.get then
aH=tonumber(aF.get("swapPressurePct"))or 25 end
E(string.format("Cold view buffers page out below %d%% free RAM"..
"  (swapPressurePct)",aH),d.dim)end
E("Volatile: cleared on every boot. 'swap clear' wipes now.",d.dim)
E("'swap now' pages cold tabs immediately (ignores pressure).",d.dim)
E("Paging spends disk writes to save RAM — see 'optimize power'.",d.dim)return end;if not f(E)then return end;local az,aA=A()if not az then
E("bootcfg/fs unavailable",d.error)return end;local ay=az.load(aA)
ay.advanced=ay.advanced or{}
if aw=="auto"then ay.advanced.swap=nil elseif aw=="on"then ay.advanced.swap=true elseif
aw=="off"then ay.advanced.swap=false else
E("swap <status|keys|now|clear|on|off|auto>",d.error)return end;local aB,aC=az.save(aA,ay)if aB then
E("Disk swap set "..aw..". Applies on next boot.",d.highlight)else
E("Save failed: "..tostring(aC),d.error)end end
local function G(aw,ax,E)local aE,ay=pcall(require,"kernel.power")
if
not aE or type(ay)~="table"or not ay.PROFILES then
E("Power control unavailable: "..tostring(ay),d.error)
E("TOS behaves as profile 'off' — nothing is being conserved.",d.dim)return end;local aD,aA=pcall(require,"kernel.screen")
local aB=h.getConfig and h.getConfig()
if aw==""or aw=="show"or aw==N then local aJ=ay.profile()
E("=== Power ===",d.title)local aK,aG,aH=pcall(ay.energy)
if
aK and type(aG)==ab and type(aH)==ab and aH>0 then
local aP=math.floor(aG*100/aH+0.5)
E(string.format("  Stored     %d / %d  (%d%%)",math.floor(aG),math.floor(aH),aP),
aP<25 and d.warning or d.fg)local aN=a._pwrSample
local aO=aN and aN.t and(h.uptime()-aN.t)or 0
if aO>=1 then local aQ=(aN.e-aG)/aO
if aQ>0.05 then
E(string.format("  Draw       %.1f/s over the last %ds",aQ,math.floor(aO)),d.fg)if aG>0 then
E(string.format("             ~%d s of buffer left at that rate",math.floor(aG/aQ)),d.dim)end elseif aQ<-0.05 then
E(string.format("  Draw       charging (+%.1f/s)",
-aQ),d.highlight)else
E(string.format("  Draw       level over the last %ds — supply is keeping up",math.floor(aO)),d.fg)end else
E("  Draw       run 'optimize power' again in a few seconds for a rate",d.dim)end;a._pwrSample={t=h.uptime(),e=aG}else
E("  Stored     (this machine reports no energy buffer)",d.dim)end;E("",d.dim)E("  Profile    "..aJ,d.highlight)
local aL,aI=ay.idleSeconds(),ay.blankSeconds()
E(string.format("  Idle clock every %ds",aL),d.fg)
E("    a status-bar repaint is a GPU write, which OC bills per cell",d.dim)
E("  Screen blank "..
(aI>0 and("after "..aI.."s idle")or"never"),d.fg)
E("    OC bills a screen per tick per NON-BLANK cell; blank costs ~0",d.dim)local aM=(aD and aA.bufferMode and aA.bufferMode())or
"?"
E("  Display buffer "..aM,d.fg)
E("    unchanged cells skip the GPU write entirely ('optimize buffer')",d.dim)E("",d.dim)
E("optimize power <off|balanced|save>   off = no conservation",d.dim)
E("optimize power blank <secs|off>      screen blank timeout",d.dim)
E("optimize power idle <secs>           idle repaint cadence",d.dim)return end
if aw=="blank"or aw=="idle"then if not f(E)then return end
local aH=
(ax=="off"or ax=="never")and 0 or tonumber(ax)local aG,aI=ay.setKnob(aw,aH)if not aG and aG~=0 then
E(tostring(aI),d.error)return end
if aw=="blank"then
E(aG>0 and
("Screen blanks after "..aG.."s idle.")or"Screen blanking off.",d.highlight)else
E("Idle repaint every "..aG.."s.",d.highlight)end
E("Profile is now custom (a named profile resets both knobs).",d.dim)return end;if not f(E)then return end;local aC,aF=ay.applyProfile(aw)if not aC then
E(tostring(aF),d.error)
E("Profiles: "..table.concat(ay.PROFILE_ORDER,", "),d.dim)return end
local az=ay.PROFILES[aC]
if aD and aA.setBuffer then pcall(aA.setBuffer,az.buffer)end
if aB and aB.set then aB.set("powerProfile",aC)local aG=pcall(aB.save)if
not aG then
E("(profile applied, but /etc/tos.cfg could not be saved)",d.warning)end end;E("Power profile: "..aC,d.highlight)
E(string.format("  idle repaint %ds · screen blank %s · display buffer %s",az.idleSec,
az.blankSec>0 and(az.blankSec.."s")or"never",az.buffer),d.dim)
E("Applies now, on every seat, and persists across reboots.",d.dim)end
b.swap=function(E,aw)return B((E[1]or""):lower(),aw)end
b.optimize=function(aw,E)local ax=(aw[1]or""):lower()
local az=(aw[2]or""):lower()local aA,ay=pcall(require,"kernel.screen")
if ax==""or ax=="show"or
ax==N then E("=== Optimizations ===",d.title)
local aC="auto (profile)"local aD,aE=A()
if aD and aE then local aH=aD.load(aE)
local aI=aH.advanced and aH.advanced.swap;if aI~=nil then aC=aI and"on"or"off"end end;local aB=h.getSwap and h.getSwap()local aF="inactive"
if aB then
local aH=aB.usage()
local aI=(aH.max and aH.max>0)and
math.floor(aH.bytes*100/aH.max)or 0
aF=string.format("active %s/%s (%d%%)",s(aH.bytes),s(aH.max),aI)end
E(string.format("  Disk swap      %-14s [%s]",aC,aF),aB and d.fg or d.dim)
E("    extends usable memory onto /var/swap (boot feature)",d.dim)local aG=(aA and ay.bufferMode and ay.bufferMode())or
"?"
E(string.format("  Display buffer %-14s",aG),d.fg)
E("    skips GPU writes for unchanged cells (auto = memory-gated)",d.dim)
if aA and ay.bufferStats then local n=ay.bufferStats()
if n.total>0 then
E(string.format("    this session: %d of %d cell-draws skipped (%d%%)",n.skipped,n.total,math.floor(
n.ratio*100+0.5)),
n.ratio>0 and d.highlight or d.dim)else E("    (no draws measured yet)",d.dim)end end
do local aI,aH=pcall(require,"kernel.power")
if
aI and type(aH)=="table"and aH.profile then local aJ=aH.blankSeconds()
E(string.format("  Power          %-14s [idle %ds, blank %s]",aH.profile(),aH.idleSeconds(),
aJ>0 and(aJ.."s")or"never"),d.fg)
E("    fewer wake-ups and a blank screen are what OC bills less for",d.dim)else E("  Power          not loaded",d.dim)end end;E("",d.dim)
E("swap [status|keys|now|clear|on|off|auto]  boot toggle needs reboot",d.dim)
E("optimize power  <off|balanced|save>       conservation profile",d.dim)
E("optimize buffer <on|off|auto>             display; applies immediately",d.dim)return end;if ax=="swap"then return B(az,E)end;if ax=="power"then return
G(az,(aw[3]or""):lower(),E)end
if
ax=="buffer"or ax=="display"then if not f(E)then return end;if not(aA and ay.setBuffer)then
E("display buffer control unavailable",d.error)return end
local aB,aC=ay.setBuffer(az)
if aB then
E("Display buffer set "..az.." (applied now).",d.highlight)else E(tostring(aC)or"invalid",d.error)end;return end
E("Usage: optimize [show | power <off|balanced|save> | buffer <on|off|auto>".." | swap <on|off|auto>]",d.dim)
E("       `swap` on its own is the same as `optimize swap`.",d.dim)end
b.programs=function(aw,E)local ay={"/bin","/usr/bin","/home/"..a.who}
E("Executables:",d.title)local ax=false
for aA,az in ipairs(ay)do
if e.isDirectory(az)then local aC,aB=pcall(e.list,az)
if aC and aB then
local aD={}if type(aB)=="table"then aD=aB elseif type(aB)=="function"then
for aF in aB do aD[#aD+1]=aF end end;local aE={}for aA,aF in ipairs(aD)do if
aF:match("%.lua$")then aE[#aE+1]=aF end end
if#
aE>0 then ax=true;E(" "..az..":",d.dim)for aA,aF in ipairs(aE)do
E("   "..aF,d.file_lua or
d.file_exec or d.highlight)end end end end end;if not ax then
E(" None yet. `help` lists the built-in commands.",d.dim)end end
b.log=function(aw,E)if not f(E)then return end;local ax=h.getLog()if not ax then
E("Logger unavailable",d.error)return end
local ay=

(aw[1]==nil)or(aw[1]=="file")or(aw[1]=="f")or(aw[1]=="all")or(tonumber(aw[1])~=nil)
if ay then local aC="/var/log/kernel.log"
local aB=tonumber(aw[1])or tonumber(aw[2])pcall(ax.flush)
if not e.exists(aC)then
E("No /var/log/kernel.log yet — showing in-memory ring.",d.dim)local aF=ax.recent(aB or 20)if#aF==0 then
E("(log is empty)",d.dim)return end
local aG={{" in-memory log ring ("..#aF.." entries)",d.title}}
for aI,aH in ipairs(aF)do local aJ=d.fg;if aH.level>=3 then aJ=d.error elseif aH.level>=2 then aJ=d.warning elseif aH.level<1 then
aJ=d.dim end
aG[#aG+1]={ax.format(aH),aJ}end;y(aG,"log (ring)")return end;local aE=e.readFile(aC)if not aE then
E("Cannot read "..aC,d.error)return end;local az={}for aF in aE:gmatch("([^\n]*)\n?")do if aF~=""then
az[#az+1]=aF end end;local aD=
(aB and aB>0 and#az-aB+1)or 1;if aD<1 then aD=1 end;local aA={}
aA[#aA+1]={
" /var/log/kernel.log  ("..#az.." lines)",d.title}
for aF=aD,#az do local aG=az[aF]local aH=d.fg
if
aG:find("%[FTL%]")or aG:find("%[ERR%]")then aH=d.error elseif aG:find("%[WRN%]")then aH=d.warning elseif aG:find("%[DBG%]")then aH=d.dim end;aA[#aA+1]={aG,aH}end;y(aA,aa)return end
if aw[1]=="filter"then local az,aA=aw[2],aw[3]
if not az then
local aC={[0]="DEBUG","INFO","WARN","ERROR"}local aB=0;for aE,aD in pairs(ax.getSourceLevels())do aB=aB+1
E(string.format("  %-12s %s+",aE,aC[aD]or
tostring(aD)),d.fg)end;if aB==0 then
E("(no per-source filters; global level applies)",d.dim)end
E("Usage: log filter <source> <debug|info|warn|error|off>",d.dim)return end
if aA=="off"or aA=="clear"then ax.setSourceLevel(az,nil)E(
"Filter cleared for '"..az.."'.",d.fg)elseif aA then
local aB,aC=ax.setSourceLevel(az,aA)
if aB then
E("Source '"..az.."' now logs at "..aA:upper().."+.",d.fg)else E(aC or"Filter update failed",d.error)end else
E("Usage: log filter <source> <debug|info|warn|error|off>",d.dim)end;return end
if aw[1]=="clear"then pcall(ax.flush)
ax.info("log","--- ring cleared on operator request ---")
E("Ring marker recorded; old entries still on disk.",d.dim)return end
if aw[1]=="ring"or aw[1]=="r"or aw[1]=="tail"then local aA=
tonumber(aw[2])or 20;local az=ax.recent(aA)if#az==0 then
E("(no log entries in ring)",d.dim)return end
for aC,aB in ipairs(az)do local aD=d.dim
if aB.level>=3 then aD=d.error elseif
aB.level>=2 then aD=d.warning elseif aB.level>=1 then aD=d.fg end;E(ax.format(aB),aD)end
E(#az.." ring entries (use 'log' for full on-disk history)",d.dim)return end
E("Usage: log [N] | log ring [N] | log clear | log filter ...",d.dim)
E("  log        Open the full on-disk log (last N lines if given)",d.dim)
E("  log ring   Quick peek at the in-memory ring",d.dim)end
b.bg=function(E,aw)if not f(aw)then return end;if not E[1]then
aw("Usage: bg <script.lua> [args...]",d.dim)
aw("  Runs a Lua script in a background tab.",d.dim)return end
local aE=u(E[1])local aF=J.safeModeRefusal(aE)
if aF then aw(aF,d.error)return end;local ay=e.readFile(aE)
if not ay then aw(af..E[1],d.error)return end;local aH,aI=load(ay,"="..E[1],"t",v{name=E[1]})if not aH then aw(
"Compile error: "..tostring(aI),d.error)
return end;local aC={}
for aM=2,#E do aC[#aC+1]=E[aM]end;local az=E[1]:match("[^/]+$")or E[1]
local ax=c.createTab("output","bg:"..az,{content={
"Background task: "..az,"PID: (starting...)",""},offset=0,pid=nil})local aL=#c.tabs;local aA=500
local function aD(...)local aM={}for aP=1,select("#",...)do
aM[#aM+1]=tostring(select(aP,...))end;local aO=table.concat(aM,"\t")ax.content[#
ax.content+1]=aO
if#ax.content>aA then
local aP=#ax.content-aA
for aQ=1,aA do ax.content[aQ]=ax.content[aQ+aP]end;for aQ=aA+1,#ax.content do ax.content[aQ]=nil end;ax.offset=math.max(0,
ax.offset-aP)end;local aN=k-3
if ax.offset>=#ax.content-aN-2 then ax.offset=math.max(0,
#ax.content-aN)end end
local aB=t.spawn("bg:"..az,function()local aM=v{name=E[1],stdout=aD}
local aN=load(ay,"="..E[1],"t",aM)ay=nil
if aN then local aO,aP=pcall(aN,table.unpack(aC))J.reportProgramEnd(a,function(aQ)
aD(aQ)end,aO,aP,ag,aM)end;aD("","--- Task finished ---")end,{priority=8,source="user",tsr=true})ax.pid=aB;ax.content[2]="PID: "..aB
aw("Started background task: "..az..
" (PID "..aB..")",d.highlight)local aJ,aG=pcall(require,"shell.panels.home")local aK=(aJ and aG)and
aG.cycleKeyLabel(a)or"F2"
aw(
"Switch to its tab with "..aK..", or use 'kill "..aB.."' to stop.",d.dim)end
b.run=function(aw,E)if not f(E)then return end;if not aw[1]then
E("Usage: run <file.lua>",d.dim)return end;local ay=u(aw[1])
local az=J.safeModeRefusal(ay)if az then E(az,d.error)return end;local aA=e.readFile(ay)if not aA then
E(af..aw[1],d.error)return end;local aB,aC=function(aI)E(aI,d.fg)end,nil;if
a.programIO then aB,aC=a.programIO(E)end
local aD=v{name=aw[1],stdout=aB,beforeRead=aC}local aE,aF=load(aA,"="..aw[1],"t",aD)if not aE then
E("Compile error: "..tostring(aF),d.error)return end;local ax={}
for aI=2,#aw do ax[#ax+1]=aw[aI]end;local aG,aH=pcall(aE,table.unpack(ax))
J.reportProgramEnd(a,E,aG,aH,"Runtime error: ",aD)end
b.lua=function(aw,E)if not o(E)then return end
pcall(function()local aH=require(aa)if aH and aH.info then
aH.info("repl",
"REPL session opened by "..tostring(a.who or"?"))end end)local aD=M.uptime()j.fill(1,1,l,k," ",d.fg,d.bg)
j.fill(1,1,l,1," ",d.bar_fg,d.bar_bg)
j.set(1,1," Lua REPL  type 'exit' to quit",d.bar_fg,d.bar_bg)
j.set(1,1," Lua REPL  'exit' to quit | blank line runs/cancels a block",d.bar_fg,d.bar_bg)local ax=2;local ay={}
local function aA(aH,aI)if ax>k-1 then local aJ=j.getGpu()if aJ and aJ.copy then
aJ.copy(1,3,l,k-3,0,-1)end;j.fill(1,k-1,l,1," ",d.fg,d.bg)
ax=k-1 end;j.set(1,ax,tostring(aH):sub(1,l),
aI or d.fg,d.bg)ax=ax+1 end;local function aE(aH)
return type(aH)==L and aH:find("<eof>",1,true)~=nil end;local az={}local aB
local aF,aG=pcall(require,"shell.quitkey")local aC=false
while true do
if ax>k-1 then j.getGpu().copy(1,3,l,k-3,0,-1)j.fill(1,
k-1,l,1," ",d.fg,d.bg)ax=k-1 end;local aJ=#az>0;local aL=aJ and">> "or"> "
j.fill(1,ax,l,1," ",d.fg,d.bg)j.set(1,ax,aL,d.highlight,d.bg)local aH=""local aI=#ay+1
local aK=#aL+1
while true do j.fill(aK,ax,l-aK+1,1," ",d.fg,d.bg)
j.set(aK,ax,aH.."_",d.fg,d.bg)local aO,aP,aM,aN=c.pullSignal()
if aO=="key_down"then
if aF and aG.is(aM,aN,true)then
aC=true;break elseif aN==28 then break elseif aN==14 then if#aH>0 then aH=aH:sub(1,-2)end elseif aN==200 then if aI>1 then aI=aI-1;aH=
ay[aI]or""end elseif aN==208 then if aI<#ay then aI=aI+1;aH=ay[aI]or""else aI=#ay+
1;aH=""end elseif aM and aM>=32 and aM<127 then aH=aH..
string.char(aM)end elseif aO=="clipboard"and type(aM)==L then
aH=aH..aM:gsub("\r","")local aQ=aH:find("\n",1,true)
if aQ then aH=aH:gsub("\n"," ")end end end;ax=ax+1;if aC or
((aH=="exit"or aH=="quit")and not aJ)then break end
if aH==""and not aJ then elseif
aH==""and aJ then az={}aA("(cancelled)",d.dim)else az[#az+1]=aH
local aM=table.concat(az,"\n")local aO,aP=load("return "..aM,"=repl","t")if not aO then
aO,aP=load(aM,"=repl","t")end;if not aO and aE(aP)then goto repl_continue end
az={}ay[#ay+1]=aM
pcall(function()local aR=require(aa)if aR and aR.info then
aR.info("repl","["..

tostring(a.who or"?").."] "..aM:gsub("\n"," ; "):sub(1,120))end end)
aB=aB or
v{name="repl",caps={["fs.read"]=true,["fs.write"]=true,["compat.io"]=true,["component"]=true,["load"]=true,["net"]=true,["peripheral.modem"]=true,["peripheral.redstone"]=true,["peripheral.robot"]=true,["peripheral.inventory"]=true,["peripheral.tape"]=true},stdout=function(aR)
aA(aR,d.fg)end}local aN,aQ=load("return "..aM,"=repl","t",aB)if not aN then
aN,aQ=load(aM,"=repl","t",aB)end
if aN then local aS,aR=pcall(aN)
if aS then if aR~=nil then
aA(tostring(aR),d.highlight)end else aA(tostring(aR),d.error)end else aA(ag..tostring(aQ),d.error)end end::repl_continue::end
pcall(function()local aH=require(aa)if aH and aH.info then
aH.info("repl",string.format("REPL session closed by %s (%.1fs, %d cmds)",tostring(
a.who or"?"),M.uptime()-aD,#ay))end end)end
b.edit=function(E,aw)if not f(aw)then return end;if not E[1]then
aw("Usage: edit <file>",d.dim)return end;local ax=u(E[1])C(ax)end
b.protect=function(aw,E)if not o(E)then return end
local aB,ax=pcall(require,"kernel.securefs")if not aB or not ax or not ax.setOperatorOverride then
E("This build has no protected-path override.",d.error)return end
local ay=J.sessionOf(a)
if not ay then
E("Could not identify your session, so there is nothing to arm.",d.error)
E("This is a bug rather than a permission problem — `whoami` should",d.dim)
E("say who you are; if it does, please report it.",d.dim)return end
local az=ax.operatorOverride and ax.operatorOverride(ay)local aA=(aw[1]or""):lower()
if aA==""or aA==N then
E(
"Protected-path guards are "..
(az and"STOOD DOWN for this session."or"active."),az and d.warning or d.highlight)E("",d.dim)
E("They stop even root from writing under /tos, /etc, /usr and",d.dim)
E("/var through securefs — a line against a tampered admin",d.dim)
E("session, not an ACL. You own this machine, so you can stand",d.dim)
E("them down; nobody below root can, and it ends with this",d.dim)E("session.",d.dim)E("",d.dim)
E("  protect off    stand the guards down for this session",d.dim)E("  protect on     put them back",d.dim)return end
if aA=="off"then if az then
E("Already stood down for this session.",d.dim)return end
local aC,aD=ax.setOperatorOverride(ay,true)
if not aC then E(R..tostring(aD),d.error)return end
E("Protected-path guards STOOD DOWN for this session.",d.warning)
E("You can now write and remove under /tos, /etc, /usr and /var.",d.dim)
E("Every path allowed this way is written to the kernel log.",d.dim)
E("Deleting the wrong thing here is how a machine stops booting —",d.dim)E("`protect on` when you are done.",d.dim)elseif aA=="on"then if not az then
E("Guards are already active.",d.dim)return end
local aC,aD=ax.setOperatorOverride(ay,false)
if not aC then E(R..tostring(aD),d.error)return end
E("Protected-path guards active again.",d.highlight)else E("Usage: protect [status|off|on]",d.dim)end end
b.reclaim=function(aw,E)if not o(E)then return end;local aG=false;for aL,aK in ipairs(aw or{})do
if aK=="--apply"then aG=true end end
local aJ,ax=pcall(require,"kernel.fs")
if not aJ or not ax then E("Filesystem unavailable.",d.error)return end;local az=ax.readFile("/init.lua")if not az then
E("Cannot read /init.lua — refusing to guess what this machine boots.",d.error)return end
if not
(
az:find("_TOS",1,true)or az:find("TOS Kernel",1,true)or
az:find("tos/kernel",1,true))then
E("/init.lua is not TOS's — this machine boots OpenOS.",d.error)
E("Those files are the operating system here, not leftovers.",d.dim)E("Refusing.",d.dim)return end;local aA={"/bin","/boot","/lib"}local aB={}local aD="/init.lua.pre-tos"for aL,aK in
ipairs(aA)do
if ax.exists(aK)then if ax.exists(aD)then aB[#aB+1]=aD end;break end end
local function aH(aK,aL)
if not ax.exists(aK)then return end
if ax.isDirectory(aK)then
for aN,aM in ipairs(ax.list(aK)or{})do aH(aK.."/"..
(aM:gsub("/$","")),aL)end;aL.dirs[#aL.dirs+1]=aK else
aL.files[#aL.files+1]=aK;aL.bytes=aL.bytes+ (ax.size(aK)or 0)end end;local ay={files={},dirs={},bytes=0}for aL,aK in ipairs(aA)do aH(aK,ay)end
for aL,aK in
ipairs(aB)do if ax.exists(aK)and not ax.isDirectory(aK)then ay.files[
#ay.files+1]=aK
ay.bytes=ay.bytes+ (ax.size(aK)or 0)end end;if#ay.files==0 and#ay.dirs==0 then
E("Nothing to reclaim — no OpenOS leftovers found.",d.highlight)return end;local aI=math.floor(
ay.bytes/1024+0.5)
E(string.format("OpenOS leftovers: %d file(s) in %d director(ies), ~%d KB",
#ay.files,#ay.dirs,aI),d.title)
for aL,aK in ipairs(aA)do if ax.exists(aK)then E("  "..aK,d.fg)end end
for aL,aK in ipairs(aB)do if ax.exists(aK)then E("  "..aK,d.fg)end end;E("",d.dim)
E("TOS installs no files into these, but it still looks in them:",d.dim)
E("require() searches /lib, and an unknown command is tried in /bin.",d.dim)
if ax.exists(aD)then
E("Until this runs, renaming /init.lua.pre-tos back to /init.lua",d.dim)
E("boots OpenOS again; afterwards an OpenOS floppy is the way back.",d.dim)else
E("An OpenOS floppy remains your recovery path — this install",d.dim)
E("stopped being one when TOS replaced /init.lua.",d.dim)end;E("",d.dim)
E("Removing /bin also changes what an unknown command does: today",d.dim)
E("it may run OpenOS's version, afterwards you get 'not a command'.",d.dim)if not aG then E("",d.dim)
E("Dry run. Nothing was removed.",d.highlight)E("Run it for real with:  reclaim --apply",d.dim)
return end
if q then
local aK=q(string.format(
"Permanently delete %d OpenOS file(s), ~%d KB?\n\n"..
"%s\n\nTOS keeps working; this drive stops being able to boot ".."OpenOS. Your recovery path becomes an OpenOS floppy.",
#ay.files,aI,table.concat(aA,"  ")),{title="Remove OpenOS leftovers",severity=Z,yes="Delete",no=X})if not aK then E("Cancelled. Nothing was removed.",d.highlight)
return end end;E("",d.dim)E("Removing...",d.warning)local aE,aC,aF=0,0,0;for aL,aK in
ipairs(ay.files)do local aM=ax.size(aK)or 0
if ax.remove(aK)then aE=aE+1;aF=aF+aM else aC=aC+1 end end;for aL,aK in ipairs(ay.dirs)do
pcall(ax.remove,aK)end
E(string.format("Removed %d file(s), ~%d KB reclaimed.",aE,math.floor(aF/1024+0.5)),d.highlight)if aC>0 then
E(aC.." file(s) could not be removed.",d.warning)end
E("Reboot when convenient; nothing running depends on them.",d.dim)end
b.flash=function(aw,E)if not o(E)then return end;local aB,aI=nil,false;for aP,aO in ipairs(aw)do if aO=="--data"then aI=true elseif aB==nil then
aB=aO end end
if
not aB then E("Usage: flash <file> [--data]",d.dim)
E("Flashes the given file to the system EEPROM.",d.dim)
E("--data also writes the chip's data field, asked for and not shown,",d.dim)
E("for a chip going into a robot or drone (rc-pilot's shared secret).",d.dim)return end;local aC=u(aB)local ay=nil;for aO in K.list("eeprom")do ay=aO;break end
if not ay then
E("No EEPROM detected. Insert EEPROM, or press Ctrl+C to abort...",d.warning)local aO=M.uptime()+60
while not ay and M.uptime()<aO do
local aP,aQ,aR=c.pullSignal(1)if aP=="component_added"and aR=="eeprom"then ay=aQ elseif aP=="interrupted"then
E(Q,d.dim)return end end
if not ay then E("Timed out waiting for EEPROM.",d.error)return end;E("EEPROM detected.",d.highlight)end;local az=K.proxy(ay)local aD=az.getSize()
local aE=e.size and e.size(aC)if type(aE)==ab and aE>aD then
E(string.format("File too large: %d bytes (EEPROM max: %d)",aE,aD),d.error)return end
local ax,aK=e.readFile(aC)
if not ax then E(af..tostring(aK),d.error)return end;if#ax>aD then
E(string.format("File too large: %d bytes (EEPROM max: %d)",#ax,aD),d.error)return end
local aL,aM=load(ax,"=flash-verify","t",{})
if not aL then
E("Refusing to flash: file does not parse as Lua text.",d.error)E("  "..tostring(aM),d.dim)return end
local aF=
ax:find("getBootAddress",1,true)or ax:find("setBootAddress",1,true)or
(ax:find("component.list",1,true)and ax:find("init.lua",1,true))
if not aF then local aO
if r then
aO=r("This file does not look like a BIOS."..
"\n\n"..
"None of the markers a BIOS normally carries were found in it. "..

"Flashing it will very likely leave a machine that cannot boot, "..
"and fixing that means physically replacing the EEPROM."..
"\n\n".."If this chip is going into a robot or a drone, that is expected: "..
"put this computer's own EEPROM back before it restarts.","force",{title="Not a BIOS",severity=Z,yes="Flash anyway",no=X})else
aO=
(i and i("Doesn't look like a BIOS — type 'force' to flash anyway: ",16))=="force"end
if not aO then E("Aborted (safety check).",d.dim)return end end;local aA=nil
if aI then
if aF then
E("Refusing --data: this file looks like a BIOS, and a BIOS keeps its",d.error)
E("boot address in the data field. --data is for a chip that is going",d.dim)E("into a robot or a drone.",d.dim)return end
if not i then E("--data needs a screen to ask on.",d.error)return end;local aP=256
do
local aS,aR=pcall(function()return az.getDataSize()end)if aS and type(aR)==ab and aR>0 then aP=aR end end;local aO=i("Data for the chip (not shown): ",aP,true)if aO==nil or
aO==""then E(Q,d.dim)return end
local aQ=i("The same again, to confirm: ",aP,true)if aQ~=aO then
E("The two did not match. Nothing was written.",d.error)return end;aA=aO end
local aN=az.getLabel and az.getLabel()or"(no label)"local aJ="(unknown)"
do local aP,aO=pcall(M.getBootAddress)if aP and aO then aJ=aO:sub(1,8)..
"..."end end;local aG=nil
do local aP,aO=pcall(require,"kernel.crypto")
if
aP and aO and aO.hash then local aR,aQ=pcall(aO.hash,ax)if
aR and type(aQ)==L and#aQ==64 then aG=aQ end end end
E(string.format("  Source : %s (%d bytes)",aC,#ax),d.dim)if aG then
E(string.format("  SHA-256: %s",aG),d.dim)else
E("  SHA-256: UNAVAILABLE - integrity cannot be verified",d.warning)end
E(string.format("  EEPROM : %s",aN),d.dim)
E(string.format("  Boot   : %s",aJ),d.dim)if aA then
E(string.format("  Data   : %d bytes, as typed (not shown)",#aA),d.dim)end;local aH
if r then
aH=r("Overwrite this machine's EEPROM with "..
tostring(aC or
"this image").."?"..
"\n\n".."The EEPROM is what starts the computer. If the image is wrong, "..
"the machine will not boot and no software fix will reach it.","flash",{title="Flash EEPROM",severity=Z,yes="Flash",no=X})else aH=(i and i('Type "flash" to confirm: ',16))==
"flash"end
if aH then local aO,aP=pcall(az.set,ax)
if not aO then
E("Flash failed: "..tostring(aP),d.error)else
E("EEPROM flashed! "..#ax.." bytes written.",d.highlight)
if aA then local aQ,aR=pcall(az.setData,aA)if aQ then
E("Data field set: "..#aA.." bytes.",d.highlight)else
E("The code was written, but the data field was NOT: "..tostring(aR),d.error)end end
if aF then E("Reboot for changes to take effect.",d.dim)else
E("This chip is not a BIOS: put this computer's own EEPROM back",d.dim)E("before it restarts.",d.dim)end end else E(Q,d.dim)end end
b.users=function(aw,E)if not f(E)then return end;if not g then E(Y,d.error)return end
E(string.format(" %-12s %-8s %s","User","Tier","Status"),d.title)E(string.rep("-",34),d.border)
local ax=g.list and g.list()or
g.listUsers and g.listUsers()or{}
for az,ay in ipairs(ax)do local aA=ay.locked and"LOCKED"or"OK"
E(string.format(" %-12s %-8s %s",
ay.username or ay.user or"?",tostring(ay.tier or ay.accessLevel or"?"),aA),
ay.locked and d.error or d.dim)end end;local function x()if not g then return"root"end;local E=g.getSession(n)return
(E and E.user)or"root"end
b.useradd=function(aw,E)if
not o(E)then return end;if not g then E(Y,d.error)return end;local ax=aw[1]if not ax then
E("Usage: useradd <username>",d.dim)return end
local ay=i("Password for "..ax..": ",64,true)if not ay or ay==""then E(Q,d.dim)return end
local az=i("Confirm password: ",64,true)
if az~=ay then E("Passwords do not match.",d.error)return end;local aA,aB=g.create(x(),ax,ay,1)
if aA then
a.lastOut={"User '"..ax.."' created.",d.highlight}else a.lastOut={tostring(aB),d.error}end end
b.userdel=function(aw,E)if not o(E)then return end;if not g then E(Y,d.error)return end
local ax=aw[1]
if not ax then E("Usage: userdel <username>",d.dim)return end;local ay
if q then
ay=q("Delete the account '"..
ax.."'?\n\n"..
"Their home directory and files are NOT removed, but the account ".."cannot be recovered from here.",{title="Delete user",severity=Z,yes="Delete",no=X})else
local aB=i("Delete '"..ax.."'? [y/N]: ",1,false)ay=(aB=="y"or aB=="Y")end;if not ay then E(Q,d.dim)return end;local az,aA=g.delete(x(),ax)
if az then
a.lastOut={
"User '"..ax.."' deleted.",d.highlight}else a.lastOut={tostring(aA),d.error}end end
b.usermod=function(aw,E)if not o(E)then return end;if not g then E(Y,d.error)return end
local az,aA=aw[1],aw[2]if not az or not aA then
E("Usage: usermod <username> lock|unlock|admin|user|root",d.dim)return end;local aB=x()local ax,ay
if aA=="lock"then
if
g.setLocked then ax,ay=g.setLocked(aB,az,true)else ax,ay=false,"setLocked unavailable"end
if ax then
a.lastOut={"'"..az.."' locked.",d.highlight}else a.lastOut={tostring(ay),d.error}end elseif aA=="unlock"then if g.setLocked then ax,ay=g.setLocked(aB,az,false)else
ax,ay=false,"setLocked unavailable"end
if ax then
a.lastOut={"'"..az.."' unlocked.",d.highlight}else a.lastOut={tostring(ay),d.error}end elseif aA=="admin"then if az:lower()==aj then
E("Failure. Did you mean 'usermod computer root'?",d.error)return end;if g.setTier then
ax,ay=g.setTier(aB,az,2)else ax,ay=false,ao end;if ax then a.lastOut={"'"..
az.."' promoted to admin.",d.highlight}else
a.lastOut={tostring(ay),d.error}end elseif aA=="root"then
if
az:lower()==aj and a.D and
not(_G._TOS and _G._TOS._takeoverFired)then _G._TOS=_G._TOS or{}
_G._TOS._takeoverFired=true;local aD,aC=pcall(require,"shell.panels.takeover")
if
aD and aC and aC.run then local aE,aF=pcall(aC.run,a)
if a.D.invalidate then pcall(a.D.invalidate)end
pcall(function()
_G._TOS.logObj.info("kernel","The computer briefly reconsidered its priorities ("..
tostring(aE and aF or"?")..")")end)a.lastOut={"Access control updated.",d.dim}return end end
if g.setTier then ax,ay=g.setTier(aB,az,3)else ax,ay=false,ao end
if ax then
a.lastOut={"'"..az.."' promoted to root.",d.highlight}else a.lastOut={tostring(ay),d.error}end elseif aA=="user"then
if g.setTier then ax,ay=g.setTier(aB,az,1)else ax,ay=false,ao end
if ax then
a.lastOut={"'"..az.."' set to user.",d.highlight}else a.lastOut={tostring(ay),d.error}end else E("Unknown action: "..aA,d.error)
E("Valid: lock, unlock, admin, user, root",d.dim)end end
b.lsdev=function(aw,E)local ay=aw[1]=="--full"
E(string.format(" %-16s %-10s %s","Type","Address","Info"),d.title)E(string.rep("-",46),d.dim)local ax=0
for az,aA in K.list()do local aB=""
if aA==_ then
local aD,aC=pcall(K.proxy,az)
if aD and aC then
local aE=aC.getLabel and aC.getLabel()or""local aF=
aC.spaceTotal and math.floor(aC.spaceTotal()/1024)or 0
aB=(aE~=""and
'"'..aE..'" 'or"")..aF.."K"end elseif aA=="modem"then local aD,aC=pcall(K.proxy,az)
if aD and aC and aC.isWireless then aB=
aC.isWireless()and"wireless"or"wired"end elseif aA=="drive"then local aD,aC=pcall(K.proxy,az)
if aD and aC and aC.getCapacity then aB="raw "..
math.floor((
aC.getCapacity()or 0)/1024).."K"end elseif aA=="openprinter"then local aD,aC=pcall(K.proxy,az)
if aD and aC then local function aE(aF)
if aF==nil then return"?"end;local aH,aG=pcall(aF)
return(aH and tonumber(aG))and
tostring(math.floor(aG))or"?"end
aB="paper "..
aE(aC.getPaperLevel).." ink "..
aE(aC.getBlackInkLevel).."/"..aE(aC.getColorInkLevel)end end
E(string.format(" %-16s %s  %s",aA,ay and az or(az:sub(1,8).."..."),aB),d.fg)ax=ax+1 end
if ax==0 then E("  (no peripherals detected)",d.dim)end end;b.devices=b.lsdev
b.mount=function(aw,E)
if aw[1]and aw[2]then if not f(E)then return end
local az,aC=aw[1],aw[2]local ay={}local ax={}
for aI in K.list(_)do
if aI:sub(1,#az)==az then ax[#ax+1]=aI else
local aK,aJ=pcall(K.proxy,aI)if aK and aJ and aJ.getLabel and aJ.getLabel()==az then ay[#ay+
1]=aI end end end;local aA=nil
if#ax==1 then aA=ax[1]elseif#ax>1 then table.sort(ax)
E(string.format("Ambiguous address prefix '%s' matches %d devices (%s, ...); use a longer prefix",az,
#ax,ax[1]:sub(1,8).."..."),d.error)return end
if not aA and#ay>0 then table.sort(ay)aA=ay[1]
if#ay>1 then
E(string.format("Note: %d disks share label '%s'; mounting %s (use partial address to disambiguate)",
#ay,az,aA:sub(1,8).."..."),d.warning)end end
if not aA then E("Device not found: "..az,d.error)return end
local aB=aC:sub(1,1)=="/"and aC or("/"..aC)local aD,aE=pcall(K.proxy,aA)if not aD then
E("Cannot proxy device",d.error)return end;if not e.exists(aB)then
pcall(e.makeDirectory,aB)end;local aF=J.sessionOf(a)
local aG,aH=e.mount(aB,aE,aF)
if aG==false then E(tostring(aH or ai),d.error)return end;a.lastOut={"Mounted at "..aB,d.highlight}else
local ay=e.mounts()
E(string.format(" %-18s %-14s %s","Mount","Label","Space"),d.title)E(string.rep("-",46),d.dim)
for aA,az in ipairs(ay)do
local aB=az.total and math.floor(
az.total/1024)or 0
local aC=az.used and math.floor(az.used/1024)or 0
E(string.format(" %-18s %-14s %dK/%dK",(az.mountPoint or"?"):sub(1,18),(
az.label or""):sub(1,14),aC,aB),d.fg)end;local ax=0;for az in K.list("drive",true)do ax=ax+1 end
if ax>0 then E("",d.dim)
E(ax..
" unmanaged (raw) drive(s) are attached and NOT listed above:",d.warning)
E("they hold no filesystem yet, so there is nothing to mount.",d.dim)E("  drive list           see them",d.dim)
E("  drive format <addr>  make one a TBFS filesystem",d.dim)
E("  drive mount <addr>   then mount it here",d.dim)end end end
b.umount=function(E,aw)
if not E[1]then aw("Usage: umount <mountpoint>",d.dim)return end;if not f(aw)then return end;local ax=E[1]:sub(1,1)=="/"and E[1]or
("/"..E[1])local ay=J.sessionOf(a)
local az,aA=e.unmount(ax,ay)if az then a.lastOut={"Unmounted "..ax,d.highlight}else
a.lastOut={tostring(aA or
"Failed to unmount"),d.error}end end
b.jbod=function(aw,E)local ax=h.getJBOD and h.getJBOD()
if not ax then
E("JBOD is disabled. Enable it with: bootsettings jbod on  (then reboot)",d.warning)
E("It pools several disks into one mount. See 'man jbod'.",d.dim)return end;local ay=(aw[1]or"list"):lower()
local function az(aA)local aB,aC={},{}
for aD in
K.list(_)do
if aD:sub(1,#aA)==aA then aB[#aB+1]=aD else local aF,aE=pcall(K.proxy,aD)if
aF and aE and aE.getLabel and aE.getLabel()==aA then
aC[#aC+1]=aD end end end;table.sort(aB)table.sort(aC)
if#aB==1 then return aB[1]end;if#aB==0 and#aC==1 then return aC[1]end;if#aB>1 then return nil,
"ambiguous address prefix: "..aA end;if#aC>1 then return nil,
"ambiguous label: "..aA end
return nil,"no filesystem matches: "..aA end
if ay=="list"or ay==N then
local aB=ax.loadConfig(e)or{pools={}}local aA=aB.pools or{}if#aA==0 then
E("No JBOD pools configured.",d.dim)end
for aD,aC in ipairs(aA)do local aE=0
for aD,aF in ipairs(aC.members or{})do for aG in
K.list(_)do if aG==aF then aE=aE+1;break end end end
E(string.format(" %-16s %d member(s), %d present",aC.mount,# (aC.members or{}),aE),d.fg)end
E("Free space: df  ·  individual disks: disk  ·  manage: jbod create|destroy",d.dim)elseif ay=="create"then if not f(E)then return end;local aA=aw[2]
if not aA or not aw[3]then
E("Usage: jbod create <mountpoint> <disk> [disk...]",d.dim)
E("  <disk> = fs address prefix or label (see lsdev)",d.dim)return end;if aA:sub(1,1)~="/"then aA="/"..aA end;aA=
(e.normalize and e.normalize(aA))or aA;if not
(aA:sub(1,6)=="/mnt/"and#aA>6)then
E("JBOD mount point must be under /mnt/  (e.g. jbod create /mnt/pool ...)",d.error)return end;local aE=_G._TOS and
_G._TOS.bootAddr;local aD,aC={},{}
for aJ=3,#aw do local aK,aM=az(aw[aJ])if not aK then
E(tostring(aM),d.error)return end
if aE and aK==aE then
E("Refusing to pool the BOOT disk ("..
aK:sub(1,8).."...).",d.error)
E("It would expose the system files inside the pool. Use data disks.",d.dim)return end;local aN,aL=pcall(K.proxy,aK)if not aN or not aL then
E("Cannot open disk: "..aw[aJ],d.error)return end;aD[#aD+1]=aL
aC[#aC+1]=aK end;pcall(e.makeDirectory,"/mnt")
pcall(e.makeDirectory,aA)local aF=ax.makePool(aD)local aG=J.sessionOf(a)
local aH,aI=e.mount(aA,aF,aG)
if not aH then E(tostring(aI or ai),d.error)return end;local aB=ax.loadConfig(e)or{pools={}}
aB.pools=aB.pools or{}for aJ=#aB.pools,1,-1 do if aB.pools[aJ].mount==aA then
table.remove(aB.pools,aJ)end end;aB.pools[
#aB.pools+1]={mount=aA,members=aC}
ax.saveConfig(e,aB)
a.lastOut={string.format("JBOD pool at %s (%d disks)",aA,#aC),d.highlight}elseif ay=="destroy"or ay==ac then if not f(E)then return end;local aA=aw[2]if not aA then
E("Usage: jbod destroy <mountpoint>",d.dim)return end
if aA:sub(1,1)~="/"then aA="/"..aA end;local aD=J.sessionOf(a)e.unmount(aA,aD)
local aB=ax.loadConfig(e)or{pools={}}local aC=false
for aE=# (aB.pools or{}),1,-1 do if aB.pools[aE].mount==aA then
table.remove(aB.pools,aE)aC=true end end;if aC then ax.saveConfig(e,aB)end
a.lastOut={aC and
("Destroyed JBOD pool "..aA)or("No JBOD pool at "..aA),
aC and d.highlight or d.warning}else
E("Usage: jbod [list | create <mount> <disk...> | destroy <mount>]",d.dim)end end
b.netfs=function(aw,E)local aA,ax=J.requireRoomy(a,"kernel.netfs","admin")if not aA or
not ax then E(J.loadFailure("netfs",ax),d.error)
return end
local ay=(aw[1]or N):lower()
local function az()local aB={}for aD,aC in ipairs(e.mounts()or{})do
if type(aC.address)==L and
aC.address:sub(1,6)=="netfs:"then aB[#aB+1]=aC end end
table.sort(aB,function(aC,aD)return
aC.mountPoint<aD.mountPoint end)return aB end
if ay==N or ay=="list"then
local aB=ax.isEnabled and ax.isEnabled()
local aC=ax.getExports and ax.getExports()or{}
local aE=m and m.getServiceArm and m.getServiceArm("netfsd")
E("Serving: "..
(
aB and"yes"or aE and"no (export file rejected; see: netfs exports)"or"no (service netfsd is not running)"),
aB and d.highlight or d.warning)
if#aC==0 then
E("  No exports configured ("..ax.EXPORTS_PATH..").",d.dim)else for aG,aF in ipairs(aC)do
E(string.format("  %-12s %-24s %s  %d peer rule(s)",aF.name,aF.path,aF.mode,# (aF.allow or{})),d.fg)end end;local aD=az()E("",d.fg)
if#aD==0 then E("Mounted: none",d.dim)else
E("Mounted:",d.fg)
for aG,aF in ipairs(aD)do local aH=(aF.total or 0)>0
E(string.format("  %-16s %-22s %s",aF.mountPoint,aF.label,

aH and s(aF.total- (aF.used or 0)).." free"or"unreachable"),
aH and d.fg or d.warning)end end
E("Manage: netfs mount <host> <share> <mountpoint> · netfs umount <mountpoint>",d.dim)elseif ay=="exports"then local aC,aD=ax.loadExports(e)if not aC then
E("Export file rejected: "..tostring(aD),d.error)
E("Nothing is served while the file is invalid.",d.dim)return end
local aB=ax.getExports()
if#aB==0 then
E("No exports in "..ax.EXPORTS_PATH,d.dim)
E("Format: { { name=\"pub\", path=\"/srv/pub\", mode=\"ro\", allow={\"<addr>\"} } }",d.dim)return end
for aF,aE in ipairs(aB)do
E(string.format("%-12s %-24s %s",aE.name,aE.path,aE.mode),d.highlight)
for aF,aG in ipairs(aE.allow or{})do E("    allow "..aG,d.dim)end;if# (aE.allow or{})==0 then
E("    allow (none) — this export is unreachable",d.warning)end end elseif ay=="mount"then if not f(E)then return end;local aF,aD,aC=aw[2],aw[3],aw[4]
if not
(aF and aD and aC)then
E("Usage: netfs mount <host> <share> <mountpoint>",d.dim)
E("  <host>  = peer hostname or address prefix (see net peers)",d.dim)
E("  <share> = export name on that machine (ask its operator)",d.dim)return end
if not m then E("Networking is not available.",d.error)return end;local aB=aF;local aI,aG=pcall(require,"shell.ext")
if
aI and type(aG)=="table"and aG.resolvePeer then aB=aG.resolvePeer(aF)end;local aH=m.findPeer and m.findPeer(aB)if aH and aH.addr then
aB=aH.addr end
if m.getTrust or m.getProtocol then
local aO,aN=pcall(require,"kernel.net.trust")
if aO and aN and aN.getLevel and aN.LEVEL then
if aN.getLevel(aB)<
aN.LEVEL.TRUSTED then
E("Peer is not TRUSTED — netfs refuses to mount from it.",d.error)
E("Raise trust first (see 'net trust'), then retry.",d.dim)return end end end;if not(aC:sub(1,5)=="/mnt/"and#aC>5)then
E("Mount point must be under /mnt/  (e.g. netfs mount box pub /mnt/box)",d.error)return end
local aE=ax.attach(aB,aD)
local aJ=aE.spaceTotal and aE.spaceTotal()or 0
if not aE.exists("/")and aJ==0 then
E("Cannot reach share '"..aD.."' on "..
tostring(aB):sub(1,8)..".",d.error)
E("Check the export name, and that netfsd runs there and allows this machine.",d.dim)return end;pcall(e.makeDirectory,"/mnt")
pcall(e.makeDirectory,aC)local aK=J.sessionOf(a)local aL,aM=e.mount(aC,aE,aK)if not aL then
E(tostring(aM or ai),d.error)return end
E("Mounted "..aD.." from "..tostring(aB):sub(1,8)..
" at "..aC,d.highlight)
E("This mount is only usable while that machine is online.",d.dim)elseif ay=="umount"then if not f(E)then return end;local aB=aw[2]if not aB then
E("Usage: netfs umount <mountpoint>",d.dim)return end;local aC=false;for aH,aG in ipairs(az())do if
aG.mountPoint==aB then aC=true;break end end;if not aC then E(
"No netfs mount at "..aB,d.warning)
E("Use 'netfs status' to list them (plain 'umount' handles local disks).",d.dim)return end
local aD=J.sessionOf(a)local aE,aF=e.unmount(aB,aD)if aE then
E("Unmounted "..aB,d.highlight)else
E(tostring(aF or"Failed to unmount"),d.error)end else
E("Usage: netfs [status | exports | mount <host> <share> <mount> | umount <mount>]",d.dim)end end
b.theme=function(aw,E)local ax=_G._TOS and _G._TOS.theme;if not ax then
E("Theme manager unavailable (T1 / monochrome or low-RAM boot)",d.warning)return end
do
local aC=(aw[1]or"show"):lower()
local aD={list=true,ls=true,show=true,current=true,keys=true,[""]=true}local aE={color=true,colour=true}
if aE[aC]then if not f(E)then return end elseif not aD[aC]then if
J.liveTier(a)<1 then
E("Log in as a user to set a personal theme.",d.error)return end end end
local function aB(aC)if not aC then return nil end
if type(aC)~=L or#aC>16 then return nil end;local aD=aC:match("^0[xX](%x+)$")or aC:match("^#(%x+)$")or
aC:match("^(%x+)$")if aD and#
aD<=6 then return tonumber(aD,16)end
return tonumber(aC)end;local function aA(aC)return string.format("0x%06X",aC)end;local ay=
aw[1]and aw[1]:lower()or"show"
local az=J.sessionOf(a)
if ay=="list"or ay=="ls"then E("Available themes:",d.title)for aD,aC in
ipairs(ax.list())do
local aE=(aC==ax.current().preset)and" *"or"  "
E(string.format(" %s %-10s %s",aE,aC,ax.describe(aC)or""),d.fg)end
E("",d.fg)
E("'*' = currently active.  Use 'theme set <name>' to switch.",d.dim)elseif ay=="show"or ay=="current"then local aC=ax.current()
E("Active theme: "..aC.preset,d.title)
E("  ".. (ax.describe(aC.preset)or""),d.dim)local aD=0;for aE in pairs(aC.overrides)do aD=aD+1 end
if aD==0 then
E("No color overrides.",d.dim)else E("Overrides:",d.highlight)for aE,aF in pairs(aC.overrides)do
E(string.format("  %-14s %s",aE,aA(aF)),d.fg)end end;E("",d.fg)
E("Try: theme set <name>  |  theme color <key> <0xRRGGBB>  |  theme reset",d.dim)elseif ay=="set"or ay=="use"then local aC=aw[2]if not aC then
E("Usage: theme set <name>  (theme list to see names)",d.warning)return end;local aD,aE=ax.apply(aC)
if
not aD then E(aE or"apply failed",d.error)return end;E("Applied theme: "..aC,d.highlight)
if az then
local aF,aG=ax.saveForUser(az)if not aF then
E("(not saved: "..tostring(aG)..")",d.dim)end end;c.drawAll()elseif ay=="preview"or ay=="try"then local aC=aw[2]if not aC then
E("Usage: theme preview <name>",d.warning)return end;local aD,aE=ax.apply(aC)if not aD then
E(aE or"apply failed",d.error)return end
E("Previewing '"..
aC.."' (not saved). Use 'theme set' to keep it.",d.highlight)c.drawAll()elseif ay=="color"or ay=="colour"then local aC,aD=aw[2],aw[3]if not aC or
not aD then
E("Usage: theme color <key> <0xRRGGBB>",d.warning)
E("Keys: "..table.concat(ax.overridableKeys(),", "),d.dim)return end
if not
ax.isOverridable(aC)then
E("Not an overridable color: "..aC,d.error)
E("Run 'theme color' with no args for the full list.",d.dim)return end;local aE=aB(aD)if not aE then
E("Invalid color value: "..aD.." (try 0xFF8800)",d.error)return end
local aF,aG=ax.setColor(aC,aE)
if not aF then E(aG or"color set failed",d.error)return end
E(string.format("%s = %s",aC,aA(aE)),d.highlight)if az then ax.saveForUser(az)end;c.drawAll()elseif ay=="reset"then
local aC,aD=ax.resetOverrides()
if not aC then E(aD or"reset failed",d.error)return end
E("Cleared color overrides; preset '"..ax.current().preset.."' restored.",d.highlight)if az then ax.saveForUser(az)end;c.drawAll()elseif ay=="clear"or ay==
"default"then
if not az then E("Not logged in.",d.error)return end;local aC,aD=ax.clearForUser(az)if not aC then
E(aD or"clear failed",d.error)return end
E("Theme reset to default; saved preference cleared.",d.highlight)c.drawAll()elseif ay=="keys"then
E("Overridable color keys:",d.title)
for aD,aC in ipairs(ax.overridableKeys())do E("  "..aC,d.fg)end else
E("Usage: theme <list|show|set|preview|color|reset|clear|keys>",d.warning)
E("  list                  Show available themes",d.dim)
E("  show                  Show active theme + overrides",d.dim)
E("  set <name>            Apply preset and save for this user",d.dim)
E("  preview <name>        Apply preset without saving",d.dim)
E("  color <key> <0xRGB>   Override a single color",d.dim)
E("  keys                  List overridable color keys",d.dim)
E("  reset                 Drop overrides, keep preset",d.dim)
E("  clear                 Wipe saved theme, revert to default",d.dim)end end;b.colors=b.theme
b.service=function(E,aw)
if E[1]and E[1]~="list"and not f(aw)then return end;local ay,ax=J.requireRoomy(a,"kernel.rc","admin")if not ay then
aw(J.loadFailure("service",ax),d.error)return end
if not E[1]or E[1]=="list"then
local az=ax.list()
if#az==0 then aw("No services registered",d.dim)return end
aw(string.format(U,"Service","Status"),d.title)aw(string.rep("-",28),d.dim)
for aB,aA in ipairs(az)do
local aC=
aA.running and"running"or
(aA.unavailable and("not loaded: "..aA.unavailable))or
(aA.enabled==false and ak)or"stopped"
aw(string.format(U,aA.name:sub(1,16),aC),
aA.running and d.highlight or d.dim)end elseif E[1]=="start"and E[2]then local az,aA=ax.start(E[2])
aw(
az and"Started: "..E[2]or tostring(aA),az and d.highlight or d.error)
if az then local aC,aB=pcall(require,"kernel.pkg")
if
aC and type(aB)=="table"and aB.noteServiceStarted then
local aD=aB.noteServiceStarted(E[2],{session=J.sessionOf(a)})if aD then
aw("Package '"..aD.."' enabled with it.",d.dim)end end
if E[2]:find("rshd",1,true)then
local aE,aD=pcall(require,"kernel.net.remote")
if aE and type(aD)=="table"and aD.stepBudgetAvailable and not
aD.stepBudgetAvailable()then
aw("OpenComputers gives remote commands no CPU or memory limit:",d.warning)
aw("a runaway one stops this whole machine.",d.warning)end end end elseif E[1]=="stop"and E[2]then local az,aA=ax.stop(E[2])
aw(
az and"Stopped: "..E[2]or tostring(aA),az and d.highlight or d.error)else
aw("Usage: service [list | start <name> | stop <name>]",d.dim)end end
b.cron=function(aw,E)if not f(E)then return end
if _G._TOS and _G._TOS.cronDisabled then
E("Cron is off in this boot profile: no job runs.",d.warning)local aB=e.readFile("/etc/cron.dat")
local aE,aC=pcall(require,"kernel.serialize")local aD,aA=false,nil;if aB and aE and aC then
aD,aA=pcall(aC.decode,aB,{maxBytes=65536})end;local az={}
if aD and type(aA)=="table"and
type(aA.jobs)=="table"then for aG,aF in pairs(aA.jobs)do
if type(aF)=="table"then az[
#az+1]={id=aG,name=tostring(aF.name)}end end end
table.sort(az,function(aF,aG)return tostring(aF.id)<tostring(aG.id)end)
if#az>0 then
E(#az.." saved job(s), which run again after a normal boot:",d.dim)for aG,aF in ipairs(az)do
E(string.format(" %-4s %s",tostring(aF.id),aF.name),d.dim)end end
if aw[1]and aw[1]~="list"then
E("cron: jobs cannot be changed in this boot profile; boot normally to edit them."..
"  [E-404 ERR_SAFE_MODE]",d.error)end;return end;local ay,ax=J.requireRoomy(a,"kernel.cron","admin")if not ay then
E(J.loadFailure("cron",ax),d.error)return end
if not aw[1]or aw[1]=="list"then
local az=ax.list()
if#az==0 then E("No scheduled jobs",d.dim)return end
E(string.format(" %-4s %-16s %-8s %s","ID","Name","Every","Enabled"),d.title)
for aB,aA in ipairs(az)do
E(string.format(" %-4d %-16s %-8s %s",aA.id,aA.name:sub(1,16),aA.interval.."s",aA.enabled and
"yes"or"no"),
aA.enabled and d.fg or d.dim)end elseif aw[1]=="add"and aw[2]and aw[3]and aw[4]then
local az=aw[2]local aA=tonumber(aw[3])local aC=table.concat(aw," ",4)if not aA then
E("Invalid interval. Usage: cron add <name> <seconds> <script>",d.error)return end
local aB,aD=ax.add(az,aA,aC)if not aB then E(tostring(aD),d.error)return end
E(
"Added job #"..aB..": "..az,d.highlight)elseif aw[1]=="rm"and aw[2]then local az=tonumber(aw[2])
if az then
local aA,aB=ax.remove(az)if aA then E("Removed job #"..az,d.highlight)else
E("cron rm: "..tostring(aB or
"no such job"),d.error)end else
E("Invalid ID",d.error)end else
E("Usage: cron [list|add <name> <seconds> <script>|rm <id>]",d.dim)end end end