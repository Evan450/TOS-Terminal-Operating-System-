
local ag,W,ah,Q,R,X,Y,U,S,Z,ai,aj,ak,al,_,T,am,aa,an,ab,ao,ac,ap,aq,ad,V,ae,af,ar,as,at,P,N,au="  %-20s %s -> %s"," %-16s %s","(--dry-run: nothing was changed)","--allow-unsigned","--allow-unverified","--dry-run","--dryrun","--force","Aborted.","Cancel","Cannot read: ","Error: ","From repos nobody configured: ","Mount failed","No user system","Refused: ","admins","compact","computer","danger","disabled","filesystem","floppy","install","kernel.log","kernel.pkgsign","number","remove","repair","setTier unavailable","shell.panels.tabs","status","string","version"local O=require(an)local M=require("component")
local L=require("shell.panels.helpers")
return
function(b,a,c)local h,av,o,e,j,g=a.K,a.E,a.P,a.F,a.D,a.U;local aw,m,n=a.SC,a.NM,a.st;local d=a.T;local ax=a.tier
local l,k=a.W,a.H;local u=c.rp;local z=c.openViewTab;local G=c.openEditTab;local H=c.refreshBrowser
local ay=c.canRead;local az=c.canWrite;local aA=c.canAccess;local q=c.rootOnly;local f=c.adminOnly
local v=c.makeProgramEnv;local t=L.fmtSz
local aB=function(E)return L.expandBuf(a,E)end;local i=c.promptInput;local r=c.confirm;local s=c.confirmTyped
b.kill=function(aC,E)
if not f(E)then return end
if not aC[1]then E("Usage: kill <pid>",d.dim)return end;local aD=tonumber(aC[1])
if aD then local aE,aF=o.kill(aD)
if aE then
E("Killed PID "..aD,d.highlight)else E(tostring(aF),d.error)end else E("Invalid PID",d.error)end end
b.fg=function(aC,E)if not f(E)then return end
if not aC[1]then E("Usage: fg <pid>",d.dim)return end;local aD=tonumber(aC[1])if not aD or not o.get(aD)then
E("No such process",d.error)return end
local aE,aF=o.setForeground(aD,a.displayIdx)if not aE then
E(tostring(aF or"Cannot foreground that process"),d.error)return end
E("Foreground: PID "..aD,d.highlight)end
b.verify=function(aC,E)if not f(E)then return end;local aD=aC and aC[1]and
tostring(aC[1]):lower()
if aD=="anchor"then local aG=false
for aJ=2,#aC do
local aK=tostring(aC[aJ]):lower()if aK=="--clear"or aK=="clear"then aG=true end end
if aG then if not h.clearManifestAnchor then
E("This TOS build cannot clear the anchor.",d.error)return end
local aJ,aK=h.clearManifestAnchor()
if aJ then
E("Manifest anchor cleared. `doctor` will report it un-anchored.",d.highlight)else
E("Could not clear the anchor: "..tostring(aK),d.error)end;return end;if not h.anchorManifestHash then
E("This TOS build has no manifest anchoring.",d.error)return end
E("Anchoring records THIS system's manifest hash in the EEPROM.",d.dim)
E("Only do it on a system you trust (fresh install, or verified).",d.dim)local aI,aH=h.anchorManifestHash()
if aI then
E("Anchored: "..
tostring(aH):sub(1,32).."...",d.highlight)
E("Your boot address was preserved; changing the boot device clears it.",d.dim)else
E("Anchor failed: "..tostring(aH),d.error)end;return end
E("=== File integrity (every system file vs the manifest) ===",d.title)
E("Checking presence, syntax, and declared hashes...",d.dim)E("")
local aE,aF=pcall(h.verifySystem,function(aG,aH)E(aG,aH)end)
if not aE then E("verify: "..tostring(aF),d.error)end;E("")
E("This checks FILES. For runtime health (memory/power/services), run 'doctor'.",d.dim)
E("It compares against the MANIFEST. To catch a file that changed since you",d.dim)
E("knew the system was good — and to put it back — use 'srm scan' / 'srm repair'.",d.dim)end;local A=1280
local p={tofu="trusted keys, or a new key you approve; never unsigned.",trusted="trusted keys only.",off="nothing; configured repos only."}
local function w(aC,E,aD)local aE=tostring(aC)
if not
(aE:find("not enough memory",1,true)or
aE:find("not enough free memory",1,true)or aE:find("Out of memory",1,true))then return end
local aF=math.floor(
(O.totalMemory and O.totalMemory()or 0)/1024)
if aF<A then
E(string.format("%s needs %d KB of RAM; this machine has %d KB.",aD,A,aF),d.dim)else
E("Something else is holding the memory it needs: close other tabs or ".."programs, or reboot, and try again.",d.dim)end end;local I={list=true,search=true,available=true,info=true}
b.pkg=function(aC,E)if aC[1]and not
I[aC[1]]and not f(E)then return end
local aI,aD=L.requireRoomy(a,"kernel.pkg","admin")if not aI or not aD then local aK=L.loadFailure("pkg",aD)E(aK,d.error)
w(aK,E,"The package manager")return end;local aE=aC[1]
local function aG(aK)
for aM,aL in
ipairs(aK or{})do local aN=aD.info and aD.info(aL)
if type(aN)=="table"and
aN.kind=="service"then local aO={}
for aM,aP in ipairs(aN.files or{})do
local aQ=tostring(aP):match("^/etc/rc%.d/(.+)%.lua$")if aQ then aO[#aO+1]=aQ end end
if#aO>0 then
local aP=type(aN.service)=="table"and aN.service.defaultState==ao
E(string.format(
aP and"  %s's service is installed switched off. To start it: service start %s"or"  %s runs as a service from the next boot. To start it now: service start %s",aL,table.concat(aO,", ")),d.dim)end end end end
local function aH()local aK={}
for aM,aL in
ipairs((aD.list and aD.list())or{})do
local aN=type(aL)=="table"and aL.name or aL;if type(aN)==N then aK[aN]=true end end;return aK end
local function aJ(aK,aL)
local aM=((aK.name or"").." ".. (aK.description or"")..
" ".. (aK.category or"")):lower()return aM:find(aL:lower(),1,true)~=nil end
local function aF(aK,aL)local aM=2
while aM<=#aC do local aN=tostring(aC[aM])
if aK[aN]=="value"then aM=aM+1 elseif
aN:sub(1,2)=="--"and not aK[aN]then
E(string.format("pkg %s: unknown option '%s' -- nothing was done.",tostring(aE),aN),d.error)E("Options: "..aL,d.dim)return true end;aM=aM+1 end;return false end
if not aE or aE=="list"then local aK=aD.list()if#aK==0 then
E("No packages installed.",d.dim)return end
E(string.format(" %-24s %-10s %s","name",au,"kind"),d.title)for aM,aL in ipairs(aK)do
E(string.format(" %-24s %-10s %s",aL.name:sub(1,24),(aL.version or"?"):sub(1,10),
aL.kind or"?"),d.fg)end elseif
aE=="search"or aE=="available"then
local aK=aD.listAllAvailable({includeRemote=true})
if#aK==0 then E("No packages available.",d.dim)
E("Looked on disk under /usr/repo, /var/repo and /mnt/*",d.dim)local aN=aD.repos and aD.repos()or{}
if#aN==0 then
E("No remote repos are configured — add one with:",d.dim)
E("  pkg repo add <name> <https://host/path>",d.dim)else
E(#aN.." remote repo(s) configured but none answered.",d.dim)
E("That usually means no internet card, or the host is",d.dim)
E("unreachable. `pkg repo list` shows what is configured.",d.dim)end;return end;local aL=aC[2]
if aL then local aN={}
for aP,aO in ipairs(aK)do if aJ(aO,aL)then aN[#aN+1]=aO end end;if#aN==0 then
E("Nothing available matches '"..aL.."'. `pkg search` lists everything.",d.dim)return end;aK=aN end
table.sort(aK,function(aN,aO)
if
(aN.category or"misc")~= (aO.category or"misc")then return
(aN.category or"misc")< (aO.category or"misc")end;return(aN.name or"")< (aO.name or"")end)
E(string.format(" %-20s %-10s %s","name",au,"source"),d.title)local aM=nil
for aO,aN in ipairs(aK)do local aP=aN.category or"misc"if aP~=aM then aM=aP
E("  ["..aP.."]",d.dim)end
local aQ=aN.remote and
("repo:"..tostring(aN.repo or"?"))or tostring(aN.root or"?")
E(string.format(" %-20s %-10s %s",(aN.name or"?"):sub(1,20),(aN.version or"?"):sub(1,10),aQ),d.fg)end elseif aE=="trust"then local aK=(aC[2]or"list"):lower()
if
aK=="list"then local aL=aD.trustList()
if#aL==0 then
E("No publisher keys are trusted on this machine.",d.dim)
E("Every package therefore reads as unsigned or as signed-by-an-",d.dim)
E("unknown-key, and your admin privilege is the only gate.",d.dim)
E("Add one:  pkg trust add <name> <64-hex-key>",d.dim)else
E(string.format(W,"name","fingerprint"),d.title)for aN,aM in ipairs(aL)do
E(string.format(W,aM.label:sub(1,16),aM.fingerprint),d.fg)end;E("",d.dim)
E("Compare a fingerprint with the publisher over a channel that is",d.dim)
E("NOT the disk it came on. A key that arrives with the package it",d.dim)E("signs proves nothing at all.",d.dim)end
E(string.format("Unsigned packages are currently %s.",aD.trustRequired()and"REFUSED"or
"allowed (admin gate only)"),
aD.trustRequired()and d.highlight or d.dim)
E(ak..p[aD.discoveredPolicy()].."  (pkg trust discovered)",d.dim)elseif aK=="discovered"then local aL=(aC[3]or""):lower()if aL==""then E(ak..
p[aD.discoveredPolicy()],d.fg)
E("Usage: pkg trust discovered tofu|trusted|off",d.dim)return end
if not p[aL]then
E("Usage: pkg trust discovered tofu|trusted|off",d.dim)E("  tofu     "..p.tofu,d.dim)
E("  trusted  "..p.trusted,d.dim)E("  off      "..p.off,d.dim)return end
local aM,aN=aD.trustDiscovered(aL,{session=L.sessionOf(a)})
if not aM then E(T..tostring(aN),d.error)return end;E(ak..p[aL],d.highlight)elseif aK=="add"then
if
not(aC[3]and aC[4])then
E("Usage: pkg trust add <name> <64-hex-public-key>",d.dim)
E("<name> is YOUR label for the publisher — it is how you will",d.dim)
E("refer to them locally, and has nothing to do with whatever",d.dim)E("name their disk claims.",d.dim)return end
local aL,aM=aD.trustAdd(aC[3],aC[4],{session=L.sessionOf(a)})
if not aL then E(T..tostring(aM),d.error)return end;E("Trusted '"..aC[3].."'.",d.highlight)
E("Packages signed by this key will now install without a fresh",d.dim)
E("judgement call. That is the point, and the cost.",d.dim)elseif aK==af or aK=="rm"then if not aC[3]then
E("Usage: pkg trust remove <name>",d.dim)return end
local aL,aM=aD.trustRemove(aC[3],{session=L.sessionOf(a)})
if not aL then E(T..tostring(aM),d.error)return end
E("Removed '"..aC[3].."'. Already-installed packages are",d.highlight)
E("unaffected — this changes what will be accepted from now on.",d.dim)elseif aK=="require"then local aL=(aC[3]or""):lower()
if
aL~="on"and aL~="off"then E("Usage: pkg trust require on|off",d.dim)
E("`on` refuses unsigned packages outright. Consider what is on",d.dim)
E("your Optional Utilities disks before turning it on.",d.dim)return end
local aM,aN=aD.trustRequire(aL=="on",{session=L.sessionOf(a)})
if not aM then E(T..tostring(aN),d.error)return end
E("Unsigned packages are now "..
(aL=="on"and"REFUSED."or"allowed."),d.highlight)elseif aK=="key"then
if not aC[3]then
E("Usage: pkg trust key <publisher-label>",d.dim)
E("Prints the public key you sign as under that label, and asks",d.dim)
E("for the passphrase without echoing it. Publish the key; never",d.dim)
E("the passphrase. The label is part of the key: the same",d.dim)
E("passphrase under a different label is a different identity.",d.dim)return end
if aC[4]then
E("Too many arguments. Only the publisher label goes here — the",d.error)
E("passphrase is asked for separately, and must never be typed",d.dim)
E("on the command line where it is echoed and recalled.",d.dim)return end;if not i then
E("This needs an interactive prompt for the passphrase.",d.error)return end
local aL=i("Signing passphrase: ",96,true)if not aL or aL==""then E(S,d.dim)return end
local aM,aO=aD.signingKey(aL,aC[3])if not aM then E(tostring(aO),d.error)return end
E(aM,d.highlight)local aP,aN=pcall(require,V)if aP and aN then
E("fingerprint "..aN.fingerprint(aM),d.dim)
E("signing as '"..tostring(aN.normalizeLabel(aC[3])).."'",d.dim)end else
E("Usage: pkg trust [list|add|remove|require|key] ...",d.dim)end elseif aE=="verify-sig"or aE=="checksig"then if not aC[2]then
E("Usage: pkg verify-sig <directory>",d.dim)
E("Says who signed a package WITHOUT installing it.",d.dim)return end
local aK,aL=aD.checkSignature(aC[2])if not aK then E(tostring(aL),d.error)return end
E(
"Package: "..tostring(aL and aL.name or"?"),d.title)local aN,aM=pcall(require,V)
if aN and aM then for aP,aO in ipairs(aM.describe(aK))do
E(aO,aK.state==
"trusted"and d.highlight or(aK.state=="invalid"and d.error or
d.warning))end end elseif aE=="sign"then
if not aC[2]then
E("Usage: pkg sign <directory> --as <publisher-name>",d.dim)
E("Signs the package's manifest with a key derived from a",d.dim)
E("passphrase you will be asked for. The signature covers the",d.dim)
E("MANIFEST, which covers the file hashes, which cover the files —",d.dim)
E("so sign AFTER the hashes are final, not before.",d.dim)return end;local aK
for aQ=3,#aC do if aC[aQ]=="--as"then aK=aC[aQ+1]end end
if not aK or aK==""then
E("Usage: pkg sign <directory> --as <publisher-name>",d.error)
E("--as is required: the label salts your signing key, so the same",d.dim)
E("passphrase under a different label is a different identity.",d.dim)
E("Use the same label every time — it is part of who you are.",d.dim)return end;if not i then
E("Signing needs an interactive prompt for the passphrase.",d.error)return end
local aL=i("Signing passphrase: ",96,true)
if not aL or aL==""then local aR,aQ=pcall(require,V)
E(string.format("Aborted. A signing passphrase is required (%d+ characters).",
aR and aQ and aQ.KDF_MIN_PASS or 20),d.dim)
E("It IS the private key — the same passphrase always produces the",d.dim)
E("same key, on any machine, so make it long and keep it.",d.dim)return end
local aM,aN=aD.signPackage(aC[2],aL,{session=L.sessionOf(a),signer=aK})if not aM then
E("Signing failed: "..tostring(aN),d.error)return end
E("Signed. Wrote "..tostring(aN),d.highlight)E("public key "..aM,d.fg)local aP,aO=pcall(require,V)if
aP and aO then
E("fingerprint "..aO.fingerprint(aM),d.dim)end elseif aE=="repo"or aE=="repos"then
local aK=(aC[2]or"list"):lower()
if aK=="list"then local aL=aD.repos()
if#aL==0 then
E("No remote repositories configured.",d.dim)
E("Add one:  pkg repo add <name> <https://host/path>",d.dim)
E("The URL is the directory holding the repo's programs.cfg.",d.dim)else
E(string.format(" %-14s %s","name","url"),d.title)
for aO,aN in ipairs(aL)do
E(string.format(" %-14s %s",aN.name:sub(1,14),aN.url),d.fg)if aN.description then
E("                "..aN.description,d.dim)end end;E("",d.dim)
E("This list is the allowlist: what these serve installs like a disk.",d.dim)end;local aM=aD.knownRepos()
if#aM>0 then E("",d.dim)
E("Known (named by installed packages; not trusted):",d.title)
for aO,aN in ipairs(aM)do
E(string.format(" %2d %s",aO,aN.url),d.fg)if#aN.from>0 then
E("      from "..table.concat(aN.from,", "),d.dim)end end
E("Read only for what configured repos lack (pkg trust",d.dim)
E("discovered). Forget:  pkg repo forget <number|url|all>",d.dim)end elseif aK=="add"then
if not aC[3]or not aC[4]then
E("Usage: pkg repo add <name> <url> [description]",d.dim)
E("  url = the directory containing programs.cfg",d.dim)return end
local aL=#aC>=5 and table.concat(aC," ",5)or nil
local aM,aN=aD.addRepo(aC[3],aC[4],aL,{session=L.sessionOf(a)})
if aM then
E("Repo '"..aC[3].."' added.",d.highlight)
E("It is now an accepted source of executable code for this",d.warning)
E("machine. 'pkg repo remove "..aC[3].."' undoes that.",d.warning)else E(tostring(aN),d.error)end elseif aK==af or aK=="rm"then if not aC[3]then
E("Usage: pkg repo remove <name>",d.dim)return end
local aL,aM=aD.removeRepo(aC[3],{session=L.sessionOf(a)})
if aL then
E("Repo '"..aC[3].."' removed.",d.highlight)else E(tostring(aM),d.error)end elseif aK=="forget"then if not aC[3]then
E("Usage: pkg repo forget <number|url|all>",d.dim)return end
local aM,aL=aD.forgetRepo(aC[3],{session=L.sessionOf(a)})
if aM then
E(("Forgot %d known repo(s)."):format(aL or 0),d.highlight)else E(tostring(aL),d.error)end else
E("Usage: pkg repo [list|add <name> <url>|remove <name>|forget <n|url|all>]",d.dim)end elseif aE=="remote"then local aK=_G._TOS and _G._TOS.internet
if aK and not
aK.available()then
E(aK.status().reason or"internet is not available",d.warning)E("'internet' shows the details.",d.dim)return end;E("Contacting configured repositories...",d.dim)
local aL=aD.searchRemote({refresh=
aC[2]=="--refresh"})if#aL==0 then
E("Nothing available. Check 'pkg repo list'.",d.dim)return end
E(string.format(" %-22s %-10s %s","name",au,"repo"),d.title)
for aN,aM in ipairs(aL)do
E(string.format(" %-22s %-10s %s",(aM.name or"?"):sub(1,22),(
aM.version or"-"):sub(1,10),tostring(aM.repo)),d.fg)if aM.description then
E("   "..tostring(aM.description):sub(1,60),d.dim)end end;E("",d.dim)
E("Install one with:  pkg fetch <name>",d.dim)elseif aE=="fetch"then if aF({[R]=true,[Q]=true},"--allow-unverified --allow-unsigned")then
return end;local aL,aM,aN=nil,false,false
for aQ=2,#aC do
local aR=tostring(aC[aQ])if aR==R then aM=true elseif aR==Q then aN=true elseif not aL then aL=aR end end
if not aL then
E("Usage: pkg fetch <name> [--allow-unverified] [--allow-unsigned]",d.dim)
E("Downloads from a configured repo, then installs it.",d.dim)return end;E("Fetching '"..aL.."'...",d.dim)
local function aO(aQ)if
not(s and i)then return nil end
local aS="'"..
tostring(aQ.name)..
"' is only in a repo this machine was not "..
"configured with:\n  "..

tostring(aQ.repo)..
"\n"..
(
aQ.by and(tostring(aQ.by).." requires it.\n")or"")..

"\nIts signature is valid, but its key is not trusted here:\n  key "..
tostring(aQ.fingerprint)..
"\n"..

(aQ.signer and
('It calls its publisher "'..tostring(aQ.signer)..
'" -- its own word, not proof.\n')or"")..
"\nCompare the fingerprint with the publisher somewhere that is NOT this repo. ".."Trusted, anything signed with this key installs from now on."
if not
s(aS,"trust",{title="A new publisher key",style="warning",yes="Trust",no="Refuse"})then
E("Refused the key "..

tostring(aQ.fingerprint).." for '"..tostring(aQ.name).."'.",d.dim)return nil end;local aR=i("Name this publisher (Enter refuses): ",48)if aR and
aR~=""then
E("Trusted the key "..
tostring(aQ.fingerprint).." as '"..aR.."' (from "..
tostring(aQ.repo)..").",d.highlight)end;return aR end
local aP,aK=aD.installRemote(aL,{session=L.sessionOf(a),allowUnverified=aM,allowUnsigned=aN,confirmKey=aO})
if aP then
local aQ=aK and aK.discovered and
(tostring(aK.discovered)..", a repo nobody configured")or("repo '"..
tostring(aK and aK.repo).."'")
E(string.format("Installed '%s' from %s (%d files, %d bytes).",aL,aQ,(aK and aK.files)or 0,
(aK and aK.bytes)or 0),d.highlight)local c=aK and aK.dependencies;if type(c)=="table"and#c>0 then
E(
"  ...and what it requires: "..table.concat(c,", "),d.highlight)end else
E(tostring(aK),d.error)
if tostring(aK):find("hash",1,true)or
tostring(aK):find("unverified",1,true)then E("",d.dim)
E("That repo ships no file hashes, so TOS cannot check what it",d.dim)
E("sent. Re-run with --allow-unverified if you trust it.",d.dim)end end elseif aE=="outdated"or aE=="updates"then local aK=aD.outdated()
if#aK==0 then
E("Everything is up to date, against what's mounted and the repos you added.",d.highlight)
E("Insert another disk and re-run to check against it too.",d.dim)return end
E(string.format(" %-20s %-10s %-10s %s","name","installed","available","from"),d.title)
for aM,aL in ipairs(aK)do
E(string.format(" %-20s %-10s %-10s %s",aL.name:sub(1,20),tostring(aL.from):sub(1,10),tostring(aL.to):sub(1,10),
aL.remote and("repo "..tostring(aL.repo))or tostring(
aL.root or"?")),d.fg)end;E("",d.dim)
E("pkg upgrade <name>   or   pkg upgrade --all --yes",d.dim)elseif aE=="upgrade"then
if
aF({["--all"]=true,["--yes"]=true,[U]=true,[X]=true,[Y]=true,[R]=true,[Q]=true},"--all --yes/-y --force --dry-run --allow-unverified --allow-unsigned")then return end;local aO,aP,aQ,aR=false,false,false,false;local aS,aT=false,false;local aL={}
for aU=2,#aC do
local aV=tostring(aC[aU])
if aV=="--all"then aO=true elseif aV=="--yes"or aV=="-y"then aP=true elseif aV==U then aQ=true elseif
aV==X or aV==Y then aR=true elseif aV==R then aS=true elseif aV==Q then aT=true elseif aV:sub(1,2)~="--"then aL[#aL+1]=aV end end;local aK={}
if aO then
for aV,aU in ipairs(aD.outdated())do aK[#aK+1]=aU end elseif#aL>0 then local aU={}
for aW,aV in ipairs(aD.outdated())do aU[aV.name]=aV end;for aW,aV in ipairs(aL)do
aK[#aK+1]=aU[aV]or{name=aV,from="?",to="?"}end else
E("Usage: pkg upgrade <name>… | --all [--yes] [--force] [--dry-run]",d.dim)
E("                   [--allow-unverified] [--allow-unsigned]",d.dim)
E("       pkg outdated   shows what has a newer version available",d.dim)return end
if#aK==0 then E("Nothing to upgrade.",d.highlight)return end
if aR then
E(string.format("Would upgrade %d package(s):",#aK),d.title)for aV,aU in ipairs(aK)do
E(string.format(ag,aU.name,tostring(aU.from),tostring(aU.to)),d.fg)end;E(ah,d.dim)return end
if aO and not aP then
E(string.format("--all would upgrade %d package(s):",#aK),d.warning)for aV,aU in ipairs(aK)do
E(string.format(ag,aU.name,tostring(aU.from),tostring(aU.to)),d.fg)end
E("Add --yes to proceed.",d.dim)return end;local aM,aN=0,0
for aV,aU in ipairs(aK)do
local aX=aU.remote and aD.upgradeRemote or aD.upgrade
local aY,aW=aX(aU.name,{session=L.sessionOf(a),force=aQ,allowUnverified=aS,allowUnsigned=aT})
if aY then aM=aM+1
E(string.format(ag,aU.name,tostring(aW.from),tostring(aW.to)),d.highlight)if aW.dropped and#aW.dropped>0 then
E(string.format("      %d file(s) no longer shipped, removed",#
aW.dropped),d.dim)end
if
aW.enabled==false then E("      (was disabled; left disabled)",d.dim)end else aN=aN+1
E(string.format("  %-20s FAILED: %s",aU.name,tostring(aW)),d.error)end end
E(string.format("%d upgraded, %d failed.",aM,aN),aN>0 and d.warning or d.highlight)
if aM>0 then
E("Services keep their enabled/disabled state; restart them to run the",d.dim)
E("new code ('service stop <svc>' then 'service start <svc>').",d.dim)end elseif aE=="audit"then local aK,aL=aC[2],aC[3]
if not aK then
local aP=aD.audited and aD.audited()or{}if#aP==0 then E("No package is under audit.",d.fg)else
E("Under audit until reboot: "..
table.concat(aP,", "),d.warning)end
E("Usage: pkg audit <name> on|off   (root)   pkg audit <name>   (the report)",d.dim)return end
if aL=="on"or aL=="off"then
local aP,aQ=aD.audit(aK,aL=="on",{session=L.sessionOf(a)})if not aP then E(tostring(aQ),d.error)return end
if
aL=="on"then
E(aK.." runs with every auditable capability until reboot.",d.warning)
E("Use it, then read what it needed: pkg audit "..aK,d.dim)
E("Not seen this way: the peripheral capabilities and ipc.",d.dim)else
E(aK.." runs with what it declared again.",d.highlight)end;return end
if aL then E("Usage: pkg audit <name> on|off",d.dim)return end;local aN=aD.auditReport and aD.auditReport(aK)if not aN then
E(aK..
" is not under audit. Root: pkg audit "..aK.." on",d.dim)return end;if#aN==0 then
E(aK..
" has used nothing it did not declare, so far.",d.highlight)return end
E(string.format(" %-12s %-34s %s","needs","used","times"),d.title)local aO={}
for aQ,aP in ipairs(aN)do
E(string.format(" %-12s %-34s %d",aP.cap,aP.name:sub(1,34),aP.count),d.fg)aO[aP.cap]=true end;local aM={}for aP in pairs(aO)do aM[#aM+1]=aP end;table.sort(aM)
E(
"To grant them, the manifest would declare: "..table.concat(aM,", "),d.dim)elseif aE=="info"then
if not aC[2]then E("Usage: pkg info <name>",d.dim)return end;local aK=aD.info(aC[2])if not aK then
E("Not installed: "..aC[2],d.error)return end
E(string.format(" name:        %s",aK.name),d.title)
E(string.format(" version:     %s",aK.version or"?"),d.fg)
E(string.format(" kind:        %s",aK.kind or"?"),d.fg)
if aK.lua or aK.tos then
E(string.format(" needs:       %s%s%s",
aK.lua and("Lua "..aK.lua.."+")or"",(aK.lua and aK.tos)and", "or"",
aK.tos and("TOS "..aK.tos)or""),d.fg)end;if aK.category then
E(string.format(" category:    %s",aK.category),d.fg)end;if aK.description then
E(string.format(" description: %s",aK.description),d.fg)end;if aK.author then
E(string.format(" author:      %s",aK.author),d.fg)end
E(string.format(" status:      %s",
aD.isEnabled(aK.name)and"enabled"or ao),
aD.isEnabled(aK.name)and d.highlight or d.dim)
if type(aK.commands)=="table"then local aL={}for aM in pairs(aK.commands)do
aL[#aL+1]=aM end
if#aL>0 then table.sort(aL)E(" commands:    "..
table.concat(aL,", "),d.fg)end end
if aK.requires and#aK.requires>0 then E(" requires:",d.fg)
for aM,aL in
ipairs(aK.requires)do local aN,aO;if type(aL)=="table"then aN,aO=aL.name,aL.version else
aN,aO=aL:match("^(%S+)%s*(.*)$")end
E(string.format("   %s %s",aN,aO or""),d.dim)end end;if aK.provides and#aK.provides>0 then
E(" provides:    "..
table.concat(aK.provides,", "),d.fg)end;if aK.recommends and
#aK.recommends>0 then
E(" recommends:  "..table.concat(aK.recommends,", "),d.dim)end;if aK.conflicts and
#aK.conflicts>0 then
E(" conflicts:   "..table.concat(aK.conflicts,", "),d.warning)end
if aK.origin=="openos"then
E(" origin:      OpenOS/OPPM package (runs on the compat layer)",d.warning)if aK.capsFromCompat then
E("              declared no capabilities — granted: "..
table.concat(aK.capabilities or{},", "),d.warning)end end
do local n=aK._sigState or"unsigned"
if n=="trusted"then
E(string.format(" signature:   signed by trusted publisher '%s'",tostring(aK._sigLabel)),d.highlight)elseif n=="unknown"then
E(" signature:   valid, but the key was not trusted at install time",d.warning)else E(" signature:   none (unsigned)",d.dim)end
if aK._sigKey then local aM,aL=pcall(require,V)
local aN=
(aM and aL and aL.fingerprint)and aL.fingerprint(aK._sigKey)or
aK._sigKey:sub(1,16)E("              key "..aN,d.dim)end
E(string.format(" integrity:   %s",
aK._unverified and"NOT verified (installed with --allow-unverified)"or"all files matched their declared hashes"),
aK._unverified and d.warning or d.dim)end elseif aE==aq or aE=="install-dir"or aE=="from-floppy"or aE==
"fromfloppy"then
if
aF({[R]=true,[Q]=true,[U]=true,["--all"]=true,["--yes"]=true,[X]=true,[Y]=true,["--key"]="value",["--prompts"]=true,["--classic"]=true},
"--all --yes/-y --dry-run --force --allow-unverified --allow-unsigned ".."--key <key> --prompts")then return end;local aM,aS,aT,aP=false,false,false,false;local aN,aL=false,false;local aQ={}
for aV=2,#aC do
local aW=tostring(aC[aV])
if aW==R then aM=true elseif aW==Q then aN=true elseif aW==U then aL=true elseif aW=="--all"then aS=true elseif
aW=="--yes"or aW=="-y"then aT=true elseif aW==X or aW==Y then aP=true elseif aW=="--key"then elseif aC[aV-1]=="--key"then elseif
aW:sub(1,2)~="--"then aQ[#aQ+1]=aW end end;local aO=aQ[1]local function aU(aV)return
type(aV)==N and aV:find("/",1,true)~=nil end;local aK
if aS then aK="all"elseif aE==
"install-dir"then aK="dir"elseif aE=="from-floppy"or aE=="fromfloppy"then aK=ap elseif not aO then
aK=ap elseif aU(aO)then aK="dir"elseif#aQ>1 then aK="many"else aK="name"end
local function aR(aV)
if#aV==0 then E("Nothing to install.",d.dim)return end
if aP then
E(string.format("Would install %d package(s):",#aV),d.title)local aY=0
for a_,aZ in ipairs(aV)do local ba,bb
if aD.planByName then ba,bb=aD.planByName(aZ)end
if not ba then E("  "..aZ,d.fg)if bb then aY=aY+1
E("    would fail: "..tostring(bb),d.error)end else E("  "..aZ,d.fg)local bc={}for a_,bd in
ipairs(ba.order or{})do
bc[#bc+1]=(aD.info and aD.info(bd))and
(bd.." (installed)")or bd end
if#bc>1 then E("    order: "..
table.concat(bc,", "),d.dim)end;for a_,bd in ipairs(ba.contradictions or{})do
E("    ! "..tostring(bd.text),d.warning)end
if#
(ba.contradictions or{})>0 then
if aL then
E("    --force: would install past "..
#ba.contradictions.." contradiction(s)",d.warning)else aY=aY+1
E("    would be refused (--force overrides)",d.error)end end end end;if aY>0 then
E(string.format("%d of %d would not install as things stand.",aY,#aV),d.warning)end;E(ah,d.dim)return end;local aX,aW=0,0
for aZ,aY in ipairs(aV)do
local ba,a_=aD.installByName(aY,{session=L.sessionOf(a),allowUnverified=aM,allowUnsigned=aN,force=aL})
if ba then aX=aX+1
E(string.format("  %-20s installed%s",aY,
(#a_.skipped>0)and(" (deps present: "..
table.concat(a_.skipped,", ")..")")or""),d.highlight)else aW=aW+1
E(string.format("  %-20s FAILED: %s",aY,tostring(a_)),d.error)end end
E(string.format("%d installed, %d failed.",aX,aW),aW>0 and d.warning or d.highlight)end
if aP and(aK=="name"or aK=="dir")then aR({aO})return elseif aP and
aK==ap then local aV={}for aX,aW in ipairs(aD.listAllAvailable()or{})do
if not(aD.info and
aD.info(aW.name))then aV[#aV+1]=aW.name end end
table.sort(aV)
if#aV==0 then E("Nothing to install.",d.dim)return end
E(string.format("Would offer %d package(s) to choose from:",#aV),d.title)for aX,aW in ipairs(aV)do E("  "..aW,d.fg)end;E(ah,d.dim)
return end
if aK=="all"then
if not(aT or aP)then
E("--all installs EVERY package on every inserted disk and repo.",d.warning)
E("Add --yes to confirm, or --dry-run to see the list first.",d.dim)return end;local aV={}for aX,aW in ipairs(aD.listAllAvailable()or{})do
if not(aD.info and
aD.info(aW.name))then aV[#aV+1]=aW.name end end
table.sort(aV)aR(aV)return elseif aK=="many"then aR(aQ)return end
if aK=="name"then local aW;for aY=3,#aC do
if aC[aY]=="--key"and aC[aY+1]then aW=aC[aY+1]end end
local aX,aV=aD.installByName(aO,{licenseKey=aW,session=L.sessionOf(a),allowUnverified=aM,allowUnsigned=aN,force=aL})
if aX then
E(string.format("Installed: %s",table.concat(aV.installed,", ")),d.highlight)aG(aV.installed)if#aV.skipped>0 then
E(string.format("Skipped (already present): %s",table.concat(aV.skipped,", ")),d.dim)end else
E("Install failed: "..tostring(aV),d.error)w(aV,E,"Installing packages")end elseif aK=="dir"then
if not aO then E("Usage: pkg install <dir>",d.dim)return end;local aW=aH()
local aX,aV=aD.install(aO,{session=L.sessionOf(a),allowUnverified=aM,allowUnsigned=aN,force=aL})
if aX then local aY={}
for aZ in pairs(aH())do if not aW[aZ]then aY[#aY+1]=aZ end end;table.sort(aY)
E("Installed: "..
(#aY>0 and
(table.concat(aY,", ").." (")or"")..
tostring(aV).. (#aY>0 and")"or""),d.highlight)aG(aY)else
E("Install failed: "..tostring(aV),d.error)w(aV,E,"Installing packages")end else local aW=false;for aZ=2,#aC do if aC[aZ]=="--prompts"or aC[aZ]=="--classic"then
aW=true end end
local aX=false
if not aW and aD.runInstaller then
local a_,aZ=aD.runInstaller({session=L.sessionOf(a),allowUnverified=aM,allowUnsigned=aN,force=aL})
if a_ then aX=true
if a.D and a.D.invalidate then pcall(a.D.invalidate)end;if c.drawAll then pcall(c.drawAll)end elseif aZ then
E("Menu installer unavailable ("..tostring(aZ)..
") — using prompts.",d.dim)end end;if aX then return end
local aY,aV=aD.installFromFloppy({session=L.sessionOf(a),allowUnverified=aM,allowUnsigned=aN,force=aL,confirm=function(bb,ba,a_,aZ)
if r then
local bf={title="Install from media",severity=aq,yes="Install",no="Skip",progress=
(a_ and aZ and aZ>1)and{index=a_,total=aZ}or nil}if a_ and aZ and a_<aZ then bf.redraw=false end;return
r("Install  "..bb.."?".."\n\n".."From:"..
"\n  "..ba,bf)end;if not i then return false end
local bd=ba:match("^(/mnt/[^/]+)")or ba;local be=
(a_ and aZ and aZ>1)and string.format(" (%d/%d)",a_,aZ)or""local bc=
i("Install "..bb..
" from "..bd..be.."? [y/N]: ",4)or""return
bc:lower()=="y"or bc:lower()=="yes"end})
if aY then if#aV.installed>0 then
E(string.format("Installed from media: %s",table.concat(aV.installed,", ")),d.highlight)end;if
#aV.skipped>0 then
E(string.format("Skipped: %s",table.concat(aV.skipped,", ")),d.dim)end;if#aV.installed==0 and
#aV.skipped==0 then
E("No packages found on mounted media. Insert a package disk and retry.",d.dim)end else E("Media scan failed: "..
tostring(aV),d.error)end end elseif aE=="license-hash"then if not aC[2]or not aC[3]then
E("Usage: pkg license-hash <package-name> <license-key>",d.dim)return end
local aK,aL=aD.computeLicenseHash(aC[2],aC[3])
if aK then E(aK,d.fg)else E(aj..tostring(aL),d.error)end elseif aE=="uninstall"or aE==af then if not aC[2]then
E("Usage: pkg uninstall <name>",d.dim)return end
local aK,aL=aD.uninstall(aC[2],{session=L.sessionOf(a)})if aK then E("Uninstalled: "..aC[2],d.highlight)else
E(
"Uninstall failed: "..tostring(aL),d.error)end elseif aE=="make-disk"or
aE=="export-disk"then
if not aC[2]then
E("Usage: pkg make-disk <mount> [name ...]",d.dim)
E("  Builds an Optional Utilities disk from your INSTALLED add-ons so",d.dim)
E("  you can install them on another TOS machine without a dev box.",d.dim)
E("  Name args limit the export; omit to include every add-on.",d.dim)E("  e.g. pkg make-disk /mnt/floppy",d.dim)return end;if not aD.exportDisk then
E("This TOS build has no make-disk support.",d.error)return end;local aL=nil;if aC[3]then aL={}for aN=3,#aC do
aL[#aL+1]=aC[aN]end end
local aM,aK=aD.exportDisk(aC[2],{only=aL,session=L.sessionOf(a)})
if aM then
E(string.format("Built add-on disk on %s: %d package(s), %d file(s)",aK.target,#aK.packages,aK.files),d.highlight)if#aK.packages>0 then
E("  "..table.concat(aK.packages,", "),d.fg)end;if#aK.problems>0 then
E("  Warnings:",d.warning)
for aO,aN in ipairs(aK.problems)do E("   ! "..aN,d.warning)end end
E("On the target machine, insert the disk and run 'pkg install'.",d.dim)else
E("make-disk failed: "..tostring(aK),d.error)end elseif aE==aa or aE=="expand"then
if not aC[2]then
E("Usage: pkg "..
aE.." <name>".. (
aE==aa and" | pkg compact --all"or""),d.dim)local o=package.loaded["kernel.pkgfs"]if
o and#o.list()>0 then
E("Compact now: "..table.concat(o.list(),", "),d.dim)end;return end;local aK={aC[2]}
if aE==aa and aC[2]=="--all"then aK={}for aN,aM in
ipairs(aD.list()or{})do aK[#aK+1]=aM.name end end;local aL=0
for aN,aM in ipairs(aK)do
local aQ=aE==aa and aD.compact or aD.expand;local aP,aO=aQ(aM,{session=L.sessionOf(a)})
if aP and
aE=="expand"then E("Expanded: "..aM,d.highlight)elseif aP then
local aR=aO.before-aO.after;aL=aL+aR
E(string.format("Compact: %s, %d files, %.1f KB -> %.1f KB%s",aM,aO.files,aO.before/1024,aO.after/1024,
aO.packed and"  (needs this data card to read)"or""),d.highlight)else
E(aM..": "..tostring(aO),#aK>1 and d.dim or d.error)end end;if#aK>1 then
E(string.format("Saved %.1f KB.",aL/1024),d.highlight)end elseif aE=="enable"or aE=="disable"then if not
aC[2]then
E("Usage: pkg "..aE.." <name>",d.dim)return end;local aK=(aE=="enable")
local aL,aM=aD.setEnabled(aC[2],aK,{session=L.sessionOf(a)})
if aL then
E((aK and"Enabled: "or"Disabled: ")..aC[2],d.highlight)else E("Failed: "..tostring(aM),d.error)end elseif aE=="commands"then local aL=aD.commands()local aK={}
for aM in pairs(aL)do aK[#aK+1]=aM end;if#aK==0 then
E("No commands provided by installed packages.",d.dim)return end;table.sort(aK)
E("Commands provided by packages:",d.title)for aN,aM in ipairs(aK)do E("  "..aM,d.fg)end else
E("Usage: pkg [list | search | info <name> | install [name|dir] | uninstall <name>",d.dim)
E("           | enable <name> | disable <name> | commands | make-disk <mnt>]",d.dim)
E("  install: a name installs by name; a path installs that dir; no arg",d.dim)
E("           scans mounted media. Shortcuts: 'install <name>', 'uninstall <name>'.",d.dim)
E("  signing: trust [list|add|remove|require|key] · verify-sig <dir> · sign <dir>",d.dim)end end
b.install=function(E,aC)local aD={aq}for aE=1,# (E or{})do aD[#aD+1]=E[aE]end;return
b.pkg(aD,aC)end
b.uninstall=function(E,aC)local aD={"uninstall"}
for aE=1,# (E or{})do aD[#aD+1]=E[aE]end;return b.pkg(aD,aC)end
b.backup=function(aC,E)if not f(E)then return end;local aD=_G._TOS and _G._TOS.backup
if
not aD then E("backup module unavailable",d.error)return end;local aE=aC[1]local aF=L.sessionOf(a)
if aE=="snapshot"or aE=="create"then if not
aC[2]or not aC[3]then
E("Usage: backup snapshot <src> <dest.bak>",d.dim)return end
local aH,aG=aD.snapshot(aC[2],aC[3],{session=aF})
if aH then
E(string.format("Snapshot OK: %d entries, %d bytes -> %s",aG.entries,aG.bytes,aC[3]),d.highlight)
E("  metaHash: "..aG.hash:sub(1,16).."...",d.dim)else
E("Snapshot failed: "..tostring(aG),d.error)end elseif aE=="inspect"then if not aC[2]then
E("Usage: backup inspect <file.bak>",d.dim)return end
local aG,aH=aD.inspect(aC[2],{session=aF})if not aG then
E("Inspect failed: "..tostring(aH),d.error)return end
E(string.format(" magic:    %s",aG.magic),d.fg)
E(string.format(" created:  %s",aG.created>978307200 and
os.date("%Y-%m-%d %H:%M:%S UTC",aG.created)or tostring(aG.created)),d.fg)
E(string.format(" entries:  %d",aG.entries),d.fg)
E(string.format(" root:     %s",aG.root),d.fg)
E(string.format(" metaHash: %s...",aG.metaHash:sub(1,24)),d.fg)
E(string.format(" size:     %d bytes",aG.size),d.fg)elseif aE=="restore"then if not aC[2]then
E("Usage: backup restore <file.bak> [destRoot] [--force]",d.dim)return end;local aH,aI=nil,false
for aK=3,#aC do if
aC[aK]==U or aC[aK]=="-f"then aI=true else aH=aC[aK]end end
local aJ,aG=aD.restore(aC[2],{session=aF,destRoot=aH,force=aI})
if aJ then
E(string.format("Restore OK: %d/%d files -> %s",aG.restored,aG.entries,aG.destRoot),d.highlight)H()else
E("Restore failed: "..tostring(aG),d.error)end else
E("Usage: backup [snapshot|inspect|restore] ...",d.dim)E("  backup snapshot <src> <dest.bak>",d.dim)
E("  backup inspect  <file.bak>",d.dim)
E("  backup restore  <file.bak> [destRoot] [--force]",d.dim)end end
b.kiosk=function(aC,E)if not f(E)then return end
local aE,aD=L.requireRoomy(a,"shell.kiosk","admin")if not aE or not aD then
E(L.loadFailure("kiosk",aD),d.error)return end
E("Kiosk = the LOCKED, guest-facing menu (allow-list + read-only).",d.title)
E("To test: log out, log in as the 'kiosk' user.",d.dim)E("Config: /etc/kiosk.cfg",d.dim)E("",d.fg)
E("Looking for the OPERATOR menu? Run 'desktop': the same kind of",d.highlight)
E("clickable menu, but it runs real commands at YOUR tier (no allow-list).",d.dim)end
b.doctor=function(aC,E)local aF,aE=L.requireRoomy(a,"kernel.diag","admin")if not aF or
not aE then E(L.loadFailure("doctor",aE),d.error)
return end
local aG={ok=d.highlight or d.fg,info=d.dim or d.fg,warn=d.warning or d.fg,err=
d.error or d.fg}local aH=aC[1]
E("=== TOS doctor \226\128\148 runtime health ===",d.title)
local aD=aE.run(function(aK,aL)E(aK,aG[aL]or d.fg)end,{only=aH})E("",d.dim)
local aI=string.format("Summary: %d ok, %d info, %d warn, %d err",aD.ok,aD.info,aD.warn,aD.err)local aJ=aD.err>0 and d.error or aD.warn>0 and d.warning or
d.highlight
E(aI,aJ)
E("This checks RUNTIME health. For a full file-integrity check, run 'verify'.",d.dim)
E("'srm' runs both, plus the known-good baseline check.",d.dim)end;b.diag=b.doctor
b.srm=function(aC,E)
local aK,aE=L.requireRoomy(a,"kernel.srm","admin")if not aK or not aE then
E(L.loadFailure("srm",aE),d.error)return end
local aH={ok=d.highlight or d.fg,info=d.dim or d.fg,warn=d.warning or d.fg,err=
d.error or d.fg}local function aG(aL)
for aN,aM in ipairs(aL.findings)do E(aM.text,aH[aM.sev]or d.fg)end;return aL end
local function aI(aL)local aM=aL.counts
E("",d.dim)
E(string.format("%d ok, %d info, %d warn, %d err%s",aM.ok,aM.info,aM.warn,aM.err,(aL.fixed or 0)>0 and(
"  |  "..aL.fixed.." fixed")or""),
aH[aE.worst(aL)]or d.fg)end;local aF,aD,aJ=aE.parseArgs(aC)if aD.source==true then
E("--source needs a mount point, e.g. --source /mnt/floppy",d.error)return end
if aF==P then
E("=== SRM \226\128\148 System Repair & Maintenance ===",d.title)aI(aG(aE.status()))E("",d.dim)
E("scan = compare files to the baseline   health = runtime   verify = manifest",d.dim)
E("repair = fix what is safe             baseline = record a known-good system",d.dim)elseif aF=="health"then return b.doctor(aJ,E)elseif aF=="verify"then return b.verify(aJ,E)elseif
aF=="scan"then
E("=== SRM scan \226\128\148 files vs the known-good baseline ===",d.title)
E("Hashing every baselined file; this takes a moment.",d.dim)aI(aG(aE.scan()))elseif aF=="baseline"then if not f(E)then return end
E("Recording what THIS system looks like right now as the known-good",d.title)
E("baseline. Only do that on a system you trust — a fresh install, or",d.dim)
E("one that just passed 'srm verify'. Anything already wrong becomes",d.dim)E("the new definition of correct.",d.dim)
E("",d.dim)local aM=aD.full and true or false
local aN,aL=aE.baseline(nil,{content=aM})if not aN then
E("Baseline failed: "..tostring(aL),d.error)return end
E(string.format("Baseline captured from %s: %d file(s) hashed.",tostring(aL.source),aL.hashed),d.highlight)
if aM then
E(string.format("  %d copy(ies) stored, %.1f KB of disk.",aL.stored,aL.bytes/1024),d.fg)
E("  Local repair is now possible: 'srm repair --restore'.",d.fg)else
E("  Hashes only — drift is detectable, but repair will need",d.fg)
E("  '--source <mount>' (e.g. the install floppy). Use --full to",d.dim)
E("  store verified copies locally instead.",d.dim)end
if aL.skipped>0 then
E(string.format("  %d file(s) skipped (over the %d KB store cap or unreadable).",aL.skipped,aE.MAX_STORE_BYTES/1024),d.warning)end;if aL.pruned>0 then
E(string.format("  %d stale copy(ies) from the previous baseline removed.",aL.pruned),d.fg)end
for aP,aO in ipairs(aL.missing)do E(
"  MISSING at capture time: "..aO,d.warning)end elseif aF=="restore"then if not f(E)then return end
E("=== SRM restore ===",d.title)
aI(aG(aE.restore(nil,{source=type(aD.source)==N and aD.source or nil,unverified=
aD.unverified and true or false,paths=#aJ>0 and aJ or nil})))elseif aF==ar and aD.online then if not f(E)then return end
if aD.apply and not q(E)then return end;if aD.ref==true then
E("--ref needs a value, e.g. --ref=build-2603a5b or --ref=main",d.error)return end
local aN,aM=pcall(require,"kernel.netrepair")if not aN or not aM then
E("online repair unavailable: "..tostring(aM),d.error)return end
E("=== SRM repair --online ===",d.title)
local aL=aM.run(nil,{apply=aD.apply and true or false,unanchored=aD.unanchored and true or false,ref=
type(aD.ref)==N and aD.ref or nil})
for aP,aO in ipairs(aL.lines)do E(aO.text,aH[aO.sev]or d.fg)end;if aD.apply then E("",d.dim)
E(string.format("%d repaired, %d rejected.",aL.fixed,aL.rejected),
aL.ok and aH.ok or aH.warn)end elseif aF==ar then if not f(E)then
return end;E("=== SRM repair ===",d.title)
if not aD.restore then
E("Fixing what is mechanically safe (interrupted writes, stale state,",d.dim)
E("oversized logs). Add --restore to also put back system files that",d.dim)
E("are missing or have changed since the baseline.",d.dim)end;E("",d.dim)
aI(aG(aE.repair(nil,{restore=aD.restore and true or false,source=
type(aD.source)==N and aD.source or nil,unverified=aD.unverified and true or false})))E("",d.dim)
E("Some fixes only apply at boot: 'bootsettings repair on' runs this",d.dim)
E("pass before anything reads the files it repairs.",d.dim)elseif aF=="full"then E("=== SRM full report ===",d.title)
E("",d.dim)E("-- status --",d.title)aG(aE.status())
E("",d.dim)E("-- health --",d.title)b.doctor({},E)E("",d.dim)
E("-- integrity --",d.title)b.verify({},E)E("",d.dim)E("-- baseline --",d.title)
aI(aG(aE.scan()))else
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
b.bootsettings=function(aC,E)if not f(E)then return end
local aJ,aH=pcall(require,"kernel.bootcfg")
if not aJ or not aH then E("bootcfg unavailable",d.error)return end;local aI=_G._TOS and _G._TOS.fs;if not aI then
E("fs unavailable",d.error)return end;local aD=aH.load(aI)
local aF=(aC[1]or""):lower()
if aF==""or aF=="show"then
E("=== Boot Settings (/etc/boot.cfg) ===",d.title)
E("  profile    : "..aD.profile..
(aD.profile=="safe"and"   (SAFE MODE)"or"   (what loads)"),d.fg)
E("  verbosity  : ".. (aD.verbosity or"auto").."   (what it says)",d.fg)
local aM=
aD.ui=="cli"and"cli"or aD.ui=="split"and"panels (split)"or aD.ui=="home"and"panels"or
(
"auto (panels from "..aH.PANELS_MIN_KB.." KB, else cli)")
E("  interface  : "..aM.."   (all seats)",d.fg)
E("  repair     : "..
(aD.repair and"RUN on next boot"or"off"),d.fg)
E("  showConfig : ".. (aD.showConfig and"on"or"off"),d.fg)
E("  cpuTier    : "..
(aD.cpuTier and("Tier "..aD.cpuTier)or"auto"),d.fg)
E("  dataTier   : "..
(aD.dataTier and("Tier "..aD.dataTier)or"auto"),d.fg)
E("  ramGate    : "..
(aD.ramGate==nil and"auto (measure)"or
(
aD.ramGate and"always load the extras"or"never load the extras")),d.fg)local aL=false
for aP,aO in ipairs(aH.FEATURES)do
local aQ=aD.advanced and aD.advanced[aO]if aQ~=nil then
E("    +"..aO.." : ".. (aQ and"on"or"off"),d.dim)aL=true end end
if not aL then E("    (no advanced overrides)",d.dim)end
E("Profiles: "..
table.concat(aH.PROFILE_ORDER or{"minimal","normal","full","diagnostic"}," | "),d.dim)
E("Verbosity: silent | splash | text | verbose | auto",d.dim)
E("Set: bootsettings <profile|verbosity|ui|repair|show|cputier|datatier|ramgate|"..table.concat(aH.FEATURES,"/")..
"> <value>",d.dim)
E("DEL during boot opens the full visual editor; S = Safe Mode once.",d.dim)local aN,aK=pcall(require,"kernel.sysinfo")
if aN and aK then E("",d.dim)
for aP,aO in
ipairs(aK.rows(aK.gather(
nil,{cpuTier=aD.cpuTier,dataTier=aD.dataTier})))do if aO.role=="section"then E(aO.value..":",d.title)else
E("  ".. (aO.label~=""and(
aO.label..": ")or"")..
aO.value,d.dim)end end end;return end;local aE=(aC[2]or""):lower()local aG=false
if aF=="profile"then
if
aH.PROFILES[aE]then aD.profile=aE;aG=true else
E("profiles: "..table.concat(aH.PROFILE_ORDER or
{"minimal","normal","full","diagnostic"}," "),d.error)return end elseif aF=="verbosity"then
if aE=="auto"then aD.verbosity=nil;aG=true else local aK=false;for aM,aL in
ipairs(aH.VERBOSITY)do if aL==aE then aK=true end end;if aK then aD.verbosity=aE
aG=true else
E("verbosity: silent splash text verbose (or auto)",d.error)return end end elseif aF=="show"or aF=="showconfig"then aD.showConfig=(aE=="on"or aE=="true"or
aE=="1")aG=true elseif aF=="cputier"or aF==
"cpu"then
if aE=="auto"then aD.cpuTier=nil;aG=true elseif
aE=="1"or aE=="2"or aE=="3"then aD.cpuTier=tonumber(aE)aG=true else
E("cputier: auto | 1 | 2 | 3",d.error)return end elseif aF=="datatier"or aF=="data"then
if aE=="auto"then aD.dataTier=nil;aG=true elseif aE=="1"or
aE=="2"or aE=="3"then aD.dataTier=tonumber(aE)aG=true else
E("datatier: auto | 1 | 2 | 3",d.error)return end elseif aF=="ui"or aF=="interface"then
if
aE=="panels"or aE=="tui"or aE=="home"then aD.ui="home"aG=true elseif aE=="cli"or aE=="split"then aD.ui=aE;aG=true elseif aE=="auto"then aD.ui=
nil;aG=true else
E("ui: auto (by memory) | panels | split | cli",d.error)return end elseif aF==ar then
if aE=="on"or aE=="once"or aE=="1"then aD.repair=true;aG=true elseif aE==
"off"or aE=="0"then aD.repair=false;aG=true else
E("repair: on (runs once next boot, then clears) | off",d.error)return end elseif aF=="ramgate"or aF=="ram"then
if aE=="auto"then aD.ramGate=nil;aG=true elseif aE=="always"or aE==
"plenty"or aE=="on"then aD.ramGate=true;aG=true elseif
aE=="never"or aE=="tight"or aE=="off"then aD.ramGate=false;aG=true else
E("ramgate: auto (measure free RAM) | always | never  (load the optional extras)",d.error)return end elseif aF=="reset"then aD=aH._normalize({})aG=true else local aK=false;for aM,aL in ipairs(aH.FEATURES)do if
aL==aF then aK=true end end
if aK then
aD.advanced=aD.advanced or{}
if aE=="auto"then aD.advanced[aF]=nil elseif aE=="on"then aD.advanced[aF]=true elseif
aE=="off"then aD.advanced[aF]=false else
E(aF..": auto | on | off",d.error)return end;aG=true else
E("Unknown setting: "..aF.." (try: bootsettings show)",d.error)return end end
if aG then local aK,aL=aH.save(aI,aD)if aK then
E("Saved. Applies on next boot (reboot to apply now).",d.highlight)else
E("Save failed: "..tostring(aL),d.error)end end end
local function B()local aD,E=pcall(require,"kernel.bootcfg")
local aC=_G._TOS and _G._TOS.fs;if aD and E and aC then return E,aC end end
local function C(aC,E)local aD=h.getSwap and h.getSwap()
if aC=="now"then
local aK,aJ=pcall(require,at)if not aK or not aJ.sweepCold then
E("tab paging unavailable",d.error)return end;if not aD then
E("Swap not available",d.error)return end;local aL=aJ.sweepCold(a,true)
local aM,aN=aJ.pagedStats(a)
E(string.format("Paged out %d view tab(s) now.",aL),d.highlight)
E(string.format("%d tab(s) on disk, %d lines held there.",aM,aN),d.dim)
E("They page back transparently the next time you open them.",d.dim)return end
if aC==""or aC==P or aC=="keys"or aC=="clear"then if not aD then
E("Swap not available",d.error)return end
if aC=="clear"then if not f(E)then return end
local aM,aL=pcall(require,at)
if aM and aL.isPaged then for aO,aN in ipairs(a.tabs or{})do
if aL.isPaged(aN)then local aO=aN.content end end end;aD.clear()E("Swap cleared.",d.highlight)return end;local aJ=aD.usage()
local aK=(aJ.max and aJ.max>0)and math.floor(aJ.bytes*100/
aJ.max)or 0;E("=== Disk Swap (/var/swap) ===",d.title)
E(string.format("Used:    %s / %s (%d%%)",t(aJ.bytes),t(aJ.max),aK),
aK>90 and d.warning or d.fg)
E(string.format("Entries: %d",aJ.count),d.dim)if aC=="keys"and aD.keys then local aL=aD.keys()
if#aL==0 then
E("(no keys)",d.dim)else for aN,aM in ipairs(aL)do E("  "..aM,d.dim)end end end
do
local aO,aM=pcall(require,at)if aO and aM.pagedStats then local aP,aQ=aM.pagedStats(a)
E(string.format("View tabs paged: %d (%d lines)",aP,aQ),
aP>0 and d.highlight or d.dim)end;local aN,aL=25,(
h.getConfig and h.getConfig())if
aL and aL.get then
aN=tonumber(aL.get("swapPressurePct"))or 25 end
E(string.format("Cold view buffers page out below %d%% free RAM"..
"  (swapPressurePct)",aN),d.dim)end
E("Volatile: cleared on every boot. 'swap clear' wipes now.",d.dim)
E("'swap now' pages cold tabs immediately (ignores pressure).",d.dim)
E("Paging spends disk writes to save RAM — see 'optimize power'.",d.dim)return end;if not f(E)then return end;local aF,aG=B()if not aF then
E("bootcfg/fs unavailable",d.error)return end;local aE=aF.load(aG)
aE.advanced=aE.advanced or{}
if aC=="auto"then aE.advanced.swap=nil elseif aC=="on"then aE.advanced.swap=true elseif
aC=="off"then aE.advanced.swap=false else
E("swap <status|keys|now|clear|on|off|auto>",d.error)return end;local aH,aI=aF.save(aG,aE)if aH then
E("Disk swap set "..aC..". Applies on next boot.",d.highlight)else
E("Save failed: "..tostring(aI),d.error)end end
local function J(aC,aD,E)local aK,aE=pcall(require,"kernel.power")
if
not aK or type(aE)~="table"or not aE.PROFILES then
E("Power control unavailable: "..tostring(aE),d.error)
E("TOS behaves as profile 'off' — nothing is being conserved.",d.dim)return end;local aJ,aG=pcall(require,"kernel.screen")
local aH=h.getConfig and h.getConfig()
if aC==""or aC=="show"or aC==P then local aP=aE.profile()
E("=== Power ===",d.title)local aQ,aM,aN=pcall(aE.energy)
if
aQ and type(aM)==ae and type(aN)==ae and aN>0 then
local aV=math.floor(aM*100/aN+0.5)
E(string.format("  Stored     %d / %d  (%d%%)",math.floor(aM),math.floor(aN),aV),
aV<25 and d.warning or d.fg)local aT=a._pwrSample
local aU=aT and aT.t and(h.uptime()-aT.t)or 0
if aU>=1 then local aW=(aT.e-aM)/aU
if aW>0.05 then
E(string.format("  Draw       %.1f/s over the last %ds",aW,math.floor(aU)),d.fg)if aM>0 then
E(string.format("             ~%d s of buffer left at that rate",math.floor(aM/aW)),d.dim)end elseif aW<-0.05 then
E(string.format("  Draw       charging (+%.1f/s)",
-aW),d.highlight)else
E(string.format("  Draw       level over the last %ds — supply is keeping up",math.floor(aU)),d.fg)end else
E("  Draw       run 'optimize power' again in a few seconds for a rate",d.dim)end;a._pwrSample={t=h.uptime(),e=aM}else
E("  Stored     (this machine reports no energy buffer)",d.dim)end;E("",d.dim)E("  Profile    "..aP,d.highlight)
local aR,aO=aE.idleSeconds(),aE.blankSeconds()
E(string.format("  Idle clock every %ds",aR),d.fg)
E("    a status-bar repaint is a GPU write, which OC bills per cell",d.dim)
E("  Screen blank "..
(aO>0 and("after "..aO.."s idle")or"never"),d.fg)
E("    OC bills a screen per tick per NON-BLANK cell; blank costs ~0",d.dim)local aS=(aJ and aG.bufferMode and aG.bufferMode())or
"?"
E("  Display buffer "..aS,d.fg)
E("    unchanged cells skip the GPU write entirely ('optimize buffer')",d.dim)E("",d.dim)
E("optimize power <off|balanced|save>   off = no conservation",d.dim)
E("optimize power blank <secs|off>      screen blank timeout",d.dim)
E("optimize power idle <secs>           idle repaint cadence",d.dim)return end
if aC=="blank"or aC=="idle"then if not f(E)then return end
local aN=
(aD=="off"or aD=="never")and 0 or tonumber(aD)local aM,aO=aE.setKnob(aC,aN)if not aM and aM~=0 then
E(tostring(aO),d.error)return end
if aC=="blank"then
E(aM>0 and
("Screen blanks after "..aM.."s idle.")or"Screen blanking off.",d.highlight)else
E("Idle repaint every "..aM.."s.",d.highlight)end
E("Profile is now custom (a named profile resets both knobs).",d.dim)return end;if not f(E)then return end;local aI,aL=aE.applyProfile(aC)if not aI then
E(tostring(aL),d.error)
E("Profiles: "..table.concat(aE.PROFILE_ORDER,", "),d.dim)return end
local aF=aE.PROFILES[aI]
if aJ and aG.setBuffer then pcall(aG.setBuffer,aF.buffer)end
if aH and aH.set then aH.set("powerProfile",aI)local aM=pcall(aH.save)if
not aM then
E("(profile applied, but /etc/tos.cfg could not be saved)",d.warning)end end;E("Power profile: "..aI,d.highlight)
E(string.format("  idle repaint %ds · screen blank %s · display buffer %s",aF.idleSec,
aF.blankSec>0 and(aF.blankSec.."s")or"never",aF.buffer),d.dim)
E("Applies now, on every seat, and persists across reboots.",d.dim)end
b.swap=function(E,aC)return C((E[1]or""):lower(),aC)end
b.optimize=function(aC,E)local aD=(aC[1]or""):lower()
local aF=(aC[2]or""):lower()local aG,aE=pcall(require,"kernel.screen")
if aD==""or aD=="show"or
aD==P then E("=== Optimizations ===",d.title)
local aI="auto (profile)"local aJ,aK=B()
if aJ and aK then local aN=aJ.load(aK)
local aO=aN.advanced and aN.advanced.swap;if aO~=nil then aI=aO and"on"or"off"end end;local aH=h.getSwap and h.getSwap()local aL="inactive"
if aH then
local aN=aH.usage()
local aO=(aN.max and aN.max>0)and
math.floor(aN.bytes*100/aN.max)or 0
aL=string.format("active %s/%s (%d%%)",t(aN.bytes),t(aN.max),aO)end
E(string.format("  Disk swap      %-14s [%s]",aI,aL),aH and d.fg or d.dim)
E("    extends usable memory onto /var/swap (boot feature)",d.dim)local aM=(aG and aE.bufferMode and aE.bufferMode())or
"?"
E(string.format("  Display buffer %-14s",aM),d.fg)
E("    skips GPU writes for unchanged cells (auto = memory-gated)",d.dim)
if aG and aE.bufferStats then local n=aE.bufferStats()
if n.total>0 then
E(string.format("    this session: %d of %d cell-draws skipped (%d%%)",n.skipped,n.total,math.floor(
n.ratio*100+0.5)),
n.ratio>0 and d.highlight or d.dim)else E("    (no draws measured yet)",d.dim)end end
do local aO,aN=pcall(require,"kernel.power")
if
aO and type(aN)=="table"and aN.profile then local aP=aN.blankSeconds()
E(string.format("  Power          %-14s [idle %ds, blank %s]",aN.profile(),aN.idleSeconds(),
aP>0 and(aP.."s")or"never"),d.fg)
E("    fewer wake-ups and a blank screen are what OC bills less for",d.dim)else E("  Power          not loaded",d.dim)end end;E("",d.dim)
E("swap [status|keys|now|clear|on|off|auto]  boot toggle needs reboot",d.dim)
E("optimize power  <off|balanced|save>       conservation profile",d.dim)
E("optimize buffer <on|off|auto>             display; applies immediately",d.dim)return end;if aD=="swap"then return C(aF,E)end;if aD=="power"then return
J(aF,(aC[3]or""):lower(),E)end
if
aD=="buffer"or aD=="display"then if not f(E)then return end;if not(aG and aE.setBuffer)then
E("display buffer control unavailable",d.error)return end
local aH,aI=aE.setBuffer(aF)
if aH then
E("Display buffer set "..aF.." (applied now).",d.highlight)else E(tostring(aI)or"invalid",d.error)end;return end
E("Usage: optimize [show | power <off|balanced|save> | buffer <on|off|auto>".." | swap <on|off|auto>]",d.dim)
E("       `swap` on its own is the same as `optimize swap`.",d.dim)end
b.programs=function(aC,E)local aE={"/bin","/usr/bin","/home/"..a.who}
E("Executables:",d.title)local aD=false
for aG,aF in ipairs(aE)do
if e.isDirectory(aF)then local aI,aH=pcall(e.list,aF)
if aI and aH then
local aJ={}if type(aH)=="table"then aJ=aH elseif type(aH)=="function"then
for aL in aH do aJ[#aJ+1]=aL end end;local aK={}for aG,aL in ipairs(aJ)do if
aL:match("%.lua$")then aK[#aK+1]=aL end end
if#
aK>0 then aD=true;E(" "..aF..":",d.dim)for aG,aL in ipairs(aK)do
E("   "..aL,d.file_lua or
d.file_exec or d.highlight)end end end end end;if not aD then
E(" None yet. `help` lists the built-in commands.",d.dim)end end
b.log=function(aC,E)if not f(E)then return end;local aD=h.getLog()if not aD then
E("Logger unavailable",d.error)return end
local aE=

(aC[1]==nil)or(aC[1]=="file")or(aC[1]=="f")or(aC[1]=="all")or(tonumber(aC[1])~=nil)
if aE then local aI="/var/log/kernel.log"
local aH=tonumber(aC[1])or tonumber(aC[2])pcall(aD.flush)
if not e.exists(aI)then
E("No /var/log/kernel.log yet — showing in-memory ring.",d.dim)local aL=aD.recent(aH or 20)if#aL==0 then
E("(log is empty)",d.dim)return end
local aM={{" in-memory log ring ("..#aL.." entries)",d.title}}
for aO,aN in ipairs(aL)do local aP=d.fg;if aN.level>=3 then aP=d.error elseif aN.level>=2 then aP=d.warning elseif aN.level<1 then
aP=d.dim end
aM[#aM+1]={aD.format(aN),aP}end;z(aM,"log (ring)")return end;local aK=e.readFile(aI)if not aK then
E("Cannot read "..aI,d.error)return end;local aF={}for aL in aK:gmatch("([^\n]*)\n?")do if aL~=""then
aF[#aF+1]=aL end end;local aJ=
(aH and aH>0 and#aF-aH+1)or 1;if aJ<1 then aJ=1 end;local aG={}
aG[#aG+1]={
" /var/log/kernel.log  ("..#aF.." lines)",d.title}
for aL=aJ,#aF do local aM=aF[aL]local aN=d.fg
if
aM:find("%[FTL%]")or aM:find("%[ERR%]")then aN=d.error elseif aM:find("%[WRN%]")then aN=d.warning elseif aM:find("%[DBG%]")then aN=d.dim end;aG[#aG+1]={aM,aN}end;z(aG,ad)return end
if aC[1]=="filter"then local aF,aG=aC[2],aC[3]
if not aF then
local aI={[0]="DEBUG","INFO","WARN","ERROR"}local aH=0;for aK,aJ in pairs(aD.getSourceLevels())do aH=aH+1
E(string.format("  %-12s %s+",aK,aI[aJ]or
tostring(aJ)),d.fg)end;if aH==0 then
E("(no per-source filters; global level applies)",d.dim)end
E("Usage: log filter <source> <debug|info|warn|error|off>",d.dim)return end
if aG=="off"or aG=="clear"then aD.setSourceLevel(aF,nil)E(
"Filter cleared for '"..aF.."'.",d.fg)elseif aG then
local aH,aI=aD.setSourceLevel(aF,aG)
if aH then
E("Source '"..aF.."' now logs at "..aG:upper().."+.",d.fg)else E(aI or"Filter update failed",d.error)end else
E("Usage: log filter <source> <debug|info|warn|error|off>",d.dim)end;return end
if aC[1]=="clear"then pcall(aD.flush)
aD.info("log","--- ring cleared on operator request ---")
E("Ring marker recorded; old entries still on disk.",d.dim)return end
if aC[1]=="ring"or aC[1]=="r"or aC[1]=="tail"then local aG=
tonumber(aC[2])or 20;local aF=aD.recent(aG)if#aF==0 then
E("(no log entries in ring)",d.dim)return end
for aI,aH in ipairs(aF)do local aJ=d.dim
if aH.level>=3 then aJ=d.error elseif
aH.level>=2 then aJ=d.warning elseif aH.level>=1 then aJ=d.fg end;E(aD.format(aH),aJ)end
E(#aF.." ring entries (use 'log' for full on-disk history)",d.dim)return end
E("Usage: log [N] | log ring [N] | log clear | log filter ...",d.dim)
E("  log        Open the full on-disk log (last N lines if given)",d.dim)
E("  log ring   Quick peek at the in-memory ring",d.dim)end
b.bg=function(E,aC)if not f(aC)then return end;if not E[1]then
aC("Usage: bg <script.lua> [args...]",d.dim)
aC("  Runs a Lua script in a background tab.",d.dim)return end
local aK=u(E[1])local aL=L.safeModeRefusal(aK)
if aL then aC(aL,d.error)return end;local aE=e.readFile(aK)
if not aE then aC(ai..E[1],d.error)return end;local aN,aO=load(aE,"="..E[1],"t",v{name=E[1]})if not aN then aC(
"Compile error: "..tostring(aO),d.error)
return end;local aI={}
for aS=2,#E do aI[#aI+1]=E[aS]end;local aF=E[1]:match("[^/]+$")or E[1]
local aD=c.createTab("output","bg:"..aF,{content={
"Background task: "..aF,"PID: (starting...)",""},offset=0,pid=nil})local aR=#c.tabs;local aG=500
local function aJ(...)local aS={}for aV=1,select("#",...)do
aS[#aS+1]=tostring(select(aV,...))end;local aU=table.concat(aS,"\t")aD.content[#
aD.content+1]=aU
if#aD.content>aG then
local aV=#aD.content-aG
for aW=1,aG do aD.content[aW]=aD.content[aW+aV]end;for aW=aG+1,#aD.content do aD.content[aW]=nil end;aD.offset=math.max(0,
aD.offset-aV)end;local aT=k-3
if aD.offset>=#aD.content-aT-2 then aD.offset=math.max(0,
#aD.content-aT)end end
local aH=o.spawn("bg:"..aF,function()local aS=v{name=E[1],stdout=aJ}
local aT=load(aE,"="..E[1],"t",aS)aE=nil
if aT then local aU,aV=pcall(aT,table.unpack(aI))L.reportProgramEnd(a,function(aW)
aJ(aW)end,aU,aV,aj,aS)end;aJ("","--- Task finished ---")end,{priority=8,source="user",tsr=true})aD.pid=aH;aD.content[2]="PID: "..aH
aC("Started background task: "..aF..
" (PID "..aH..")",d.highlight)local aP,aM=pcall(require,"shell.panels.home")local aQ=(aP and aM)and
aM.cycleKeyLabel(a)or"F2"
aC(
"Switch to its tab with "..aQ..", or use 'kill "..aH.."' to stop.",d.dim)end
b.run=function(aC,E)if not f(E)then return end;if not aC[1]then
E("Usage: run <file.lua>",d.dim)return end;local aE=u(aC[1])
local aF=L.safeModeRefusal(aE)if aF then E(aF,d.error)return end;local aG=e.readFile(aE)if not aG then
E(ai..aC[1],d.error)return end;local aH,aI=function(aO)E(aO,d.fg)end,nil;if
a.programIO then aH,aI=a.programIO(E)end
local aJ=v{name=aC[1],stdout=aH,beforeRead=aI}local aK,aL=load(aG,"="..aC[1],"t",aJ)if not aK then
E("Compile error: "..tostring(aL),d.error)return end;local aD={}
for aO=2,#aC do aD[#aD+1]=aC[aO]end;local aM,aN=pcall(aK,table.unpack(aD))
L.reportProgramEnd(a,E,aM,aN,"Runtime error: ",aJ)end
b.lua=function(aC,E)if not q(E)then return end
pcall(function()local aN=require(ad)if aN and aN.info then
aN.info("repl",
"REPL session opened by "..tostring(a.who or"?"))end end)local aJ=O.uptime()j.fill(1,1,l,k," ",d.fg,d.bg)
j.fill(1,1,l,1," ",d.bar_fg,d.bar_bg)
j.set(1,1," Lua REPL  type 'exit' to quit",d.bar_fg,d.bar_bg)
j.set(1,1," Lua REPL  'exit' to quit | blank line runs/cancels a block",d.bar_fg,d.bar_bg)local aD=2;local aE={}
local function aG(aN,aO)if aD>k-1 then local aP=j.getGpu()if aP and aP.copy then
aP.copy(1,3,l,k-3,0,-1)end;j.fill(1,k-1,l,1," ",d.fg,d.bg)
aD=k-1 end;j.set(1,aD,tostring(aN):sub(1,l),
aO or d.fg,d.bg)aD=aD+1 end;local function aK(aN)
return type(aN)==N and aN:find("<eof>",1,true)~=nil end;local aF={}local aH
local aL,aM=pcall(require,"shell.quitkey")local aI=false
while true do
if aD>k-1 then j.getGpu().copy(1,3,l,k-3,0,-1)j.fill(1,
k-1,l,1," ",d.fg,d.bg)aD=k-1 end;local aP=#aF>0;local aR=aP and">> "or"> "
j.fill(1,aD,l,1," ",d.fg,d.bg)j.set(1,aD,aR,d.highlight,d.bg)local aN=""local aO=#aE+1
local aQ=#aR+1
while true do j.fill(aQ,aD,l-aQ+1,1," ",d.fg,d.bg)
j.set(aQ,aD,aN.."_",d.fg,d.bg)local aU,aV,aS,aT=c.pullSignal()
if aU=="key_down"then
if aL and aM.is(aS,aT,true)then
aI=true;break elseif aT==28 then break elseif aT==14 then if#aN>0 then aN=aN:sub(1,-2)end elseif aT==200 then if aO>1 then aO=aO-1;aN=
aE[aO]or""end elseif aT==208 then if aO<#aE then aO=aO+1;aN=aE[aO]or""else aO=#aE+
1;aN=""end elseif aS and aS>=32 and aS<127 then aN=aN..
string.char(aS)end elseif aU=="clipboard"and type(aS)==N then
aN=aN..aS:gsub("\r","")local aW=aN:find("\n",1,true)
if aW then aN=aN:gsub("\n"," ")end end end;aD=aD+1;if aI or
((aN=="exit"or aN=="quit")and not aP)then break end
if aN==""and not aP then elseif
aN==""and aP then aF={}aG("(cancelled)",d.dim)else aF[#aF+1]=aN
local aS=table.concat(aF,"\n")local aU,aV=load("return "..aS,"=repl","t")if not aU then
aU,aV=load(aS,"=repl","t")end;if not aU and aK(aV)then goto repl_continue end
aF={}aE[#aE+1]=aS
pcall(function()local aX=require(ad)if aX and aX.info then
aX.info("repl","["..

tostring(a.who or"?").."] "..aS:gsub("\n"," ; "):sub(1,120))end end)
aH=aH or
v{name="repl",caps={["fs.read"]=true,["fs.write"]=true,["compat.io"]=true,["component"]=true,["load"]=true,["net"]=true,["peripheral.modem"]=true,["peripheral.redstone"]=true,["peripheral.robot"]=true,["peripheral.inventory"]=true,["peripheral.tape"]=true},stdout=function(aX)
aG(aX,d.fg)end}local aT,aW=load("return "..aS,"=repl","t",aH)if not aT then
aT,aW=load(aS,"=repl","t",aH)end
if aT then local aY,aX=pcall(aT)
if aY then if aX~=nil then
aG(tostring(aX),d.highlight)end else aG(tostring(aX),d.error)end else aG(aj..tostring(aW),d.error)end end::repl_continue::end
pcall(function()local aN=require(ad)if aN and aN.info then
aN.info("repl",string.format("REPL session closed by %s (%.1fs, %d cmds)",tostring(
a.who or"?"),O.uptime()-aJ,#aE))end end)end
b.edit=function(E,aC)if not f(aC)then return end;if not E[1]then
aC("Usage: edit <file>",d.dim)return end;local aD=u(E[1])G(aD)end
b.protect=function(aC,E)if not q(E)then return end
local aH,aD=pcall(require,"kernel.securefs")if not aH or not aD or not aD.setOperatorOverride then
E("This build has no protected-path override.",d.error)return end
local aE=L.sessionOf(a)
if not aE then
E("Could not identify your session, so there is nothing to arm.",d.error)
E("This is a bug rather than a permission problem — `whoami` should",d.dim)
E("say who you are; if it does, please report it.",d.dim)return end
local aF=aD.operatorOverride and aD.operatorOverride(aE)local aG=(aC[1]or""):lower()
if aG==""or aG==P then
E(
"Protected-path guards are "..
(aF and"STOOD DOWN for this session."or"active."),aF and d.warning or d.highlight)E("",d.dim)
E("They stop even root from writing under /tos, /etc, /usr and",d.dim)
E("/var through securefs — a line against a tampered admin",d.dim)
E("session, not an ACL. You own this machine, so you can stand",d.dim)
E("them down; nobody below root can, and it ends with this",d.dim)E("session.",d.dim)E("",d.dim)
E("  protect off    stand the guards down for this session",d.dim)E("  protect on     put them back",d.dim)return end
if aG=="off"then if aF then
E("Already stood down for this session.",d.dim)return end
local aI,aJ=aD.setOperatorOverride(aE,true)
if not aI then E(T..tostring(aJ),d.error)return end
E("Protected-path guards STOOD DOWN for this session.",d.warning)
E("You can now write and remove under /tos, /etc, /usr and /var.",d.dim)
E("Every path allowed this way is written to the kernel log.",d.dim)
E("Deleting the wrong thing here is how a machine stops booting —",d.dim)E("`protect on` when you are done.",d.dim)elseif aG=="on"then if not aF then
E("Guards are already active.",d.dim)return end
local aI,aJ=aD.setOperatorOverride(aE,false)
if not aI then E(T..tostring(aJ),d.error)return end
E("Protected-path guards active again.",d.highlight)else E("Usage: protect [status|off|on]",d.dim)end end
b.reclaim=function(aC,E)if not q(E)then return end;local aM=false;for aR,aQ in ipairs(aC or{})do
if aQ=="--apply"then aM=true end end
local aP,aD=pcall(require,"kernel.fs")
if not aP or not aD then E("Filesystem unavailable.",d.error)return end;local aF=aD.readFile("/init.lua")if not aF then
E("Cannot read /init.lua — refusing to guess what this machine boots.",d.error)return end
if not
(
aF:find("_TOS",1,true)or aF:find("TOS Kernel",1,true)or
aF:find("tos/kernel",1,true))then
E("/init.lua is not TOS's — this machine boots OpenOS.",d.error)
E("Those files are the operating system here, not leftovers.",d.dim)E("Refusing.",d.dim)return end;local aG={"/bin","/boot","/lib"}local aH={}local aJ="/init.lua.pre-tos"for aR,aQ in
ipairs(aG)do
if aD.exists(aQ)then if aD.exists(aJ)then aH[#aH+1]=aJ end;break end end
local function aN(aQ,aR)
if not aD.exists(aQ)then return end
if aD.isDirectory(aQ)then
for aT,aS in ipairs(aD.list(aQ)or{})do aN(aQ.."/"..
(aS:gsub("/$","")),aR)end;aR.dirs[#aR.dirs+1]=aQ else
aR.files[#aR.files+1]=aQ;aR.bytes=aR.bytes+ (aD.size(aQ)or 0)end end;local aE={files={},dirs={},bytes=0}for aR,aQ in ipairs(aG)do aN(aQ,aE)end
for aR,aQ in
ipairs(aH)do if aD.exists(aQ)and not aD.isDirectory(aQ)then aE.files[
#aE.files+1]=aQ
aE.bytes=aE.bytes+ (aD.size(aQ)or 0)end end;if#aE.files==0 and#aE.dirs==0 then
E("Nothing to reclaim — no OpenOS leftovers found.",d.highlight)return end;local aO=math.floor(
aE.bytes/1024+0.5)
E(string.format("OpenOS leftovers: %d file(s) in %d director(ies), ~%d KB",
#aE.files,#aE.dirs,aO),d.title)
for aR,aQ in ipairs(aG)do if aD.exists(aQ)then E("  "..aQ,d.fg)end end
for aR,aQ in ipairs(aH)do if aD.exists(aQ)then E("  "..aQ,d.fg)end end;E("",d.dim)
E("TOS installs no files into these, but it still looks in them:",d.dim)
E("require() searches /lib, and an unknown command is tried in /bin.",d.dim)
if aD.exists(aJ)then
E("Until this runs, renaming /init.lua.pre-tos back to /init.lua",d.dim)
E("boots OpenOS again; afterwards an OpenOS floppy is the way back.",d.dim)else
E("An OpenOS floppy remains your recovery path — this install",d.dim)
E("stopped being one when TOS replaced /init.lua.",d.dim)end;E("",d.dim)
E("Removing /bin also changes what an unknown command does: today",d.dim)
E("it may run OpenOS's version, afterwards you get 'not a command'.",d.dim)if not aM then E("",d.dim)
E("Dry run. Nothing was removed.",d.highlight)E("Run it for real with:  reclaim --apply",d.dim)
return end
if r then
local aQ=r(string.format(
"Permanently delete %d OpenOS file(s), ~%d KB?\n\n"..
"%s\n\nTOS keeps working; this drive stops being able to boot ".."OpenOS. Your recovery path becomes an OpenOS floppy.",
#aE.files,aO,table.concat(aG,"  ")),{title="Remove OpenOS leftovers",severity=ab,yes="Delete",no=Z})if not aQ then E("Cancelled. Nothing was removed.",d.highlight)
return end end;E("",d.dim)E("Removing...",d.warning)local aK,aI,aL=0,0,0;for aR,aQ in
ipairs(aE.files)do local aS=aD.size(aQ)or 0
if aD.remove(aQ)then aK=aK+1;aL=aL+aS else aI=aI+1 end end;for aR,aQ in ipairs(aE.dirs)do
pcall(aD.remove,aQ)end
E(string.format("Removed %d file(s), ~%d KB reclaimed.",aK,math.floor(aL/1024+0.5)),d.highlight)if aI>0 then
E(aI.." file(s) could not be removed.",d.warning)end
E("Reboot when convenient; nothing running depends on them.",d.dim)end
b.flash=function(aC,E)if not q(E)then return end;local aH,aO=nil,false;for aV,aU in ipairs(aC)do if aU=="--data"then aO=true elseif aH==nil then
aH=aU end end
if
not aH then E("Usage: flash <file> [--data]",d.dim)
E("Flashes the given file to the system EEPROM.",d.dim)
E("--data also writes the chip's data field, asked for and not shown,",d.dim)
E("for a chip going into a robot or drone (rc-pilot's shared secret).",d.dim)return end;local aI=u(aH)local aE=nil;for aU in M.list("eeprom")do aE=aU;break end
if not aE then
E("No EEPROM detected. Insert EEPROM, or press Ctrl+C to abort...",d.warning)local aU=O.uptime()+60
while not aE and O.uptime()<aU do
local aV,aW,aX=c.pullSignal(1)if aV=="component_added"and aX=="eeprom"then aE=aW elseif aV=="interrupted"then
E(S,d.dim)return end end
if not aE then E("Timed out waiting for EEPROM.",d.error)return end;E("EEPROM detected.",d.highlight)end;local aF=M.proxy(aE)local aJ=aF.getSize()
local aK=e.size and e.size(aI)if type(aK)==ae and aK>aJ then
E(string.format("File too large: %d bytes (EEPROM max: %d)",aK,aJ),d.error)return end
local aD,aQ=e.readFile(aI)
if not aD then E(ai..tostring(aQ),d.error)return end;if#aD>aJ then
E(string.format("File too large: %d bytes (EEPROM max: %d)",#aD,aJ),d.error)return end
local aR,aS=load(aD,"=flash-verify","t",{})
if not aR then
E("Refusing to flash: file does not parse as Lua text.",d.error)E("  "..tostring(aS),d.dim)return end
local aL=
aD:find("getBootAddress",1,true)or aD:find("setBootAddress",1,true)or
(aD:find("component.list",1,true)and aD:find("init.lua",1,true))
if not aL then local aU
if s then
aU=s("This file does not look like a BIOS."..
"\n\n"..
"None of the markers a BIOS normally carries were found in it. "..

"Flashing it will very likely leave a machine that cannot boot, "..
"and fixing that means physically replacing the EEPROM."..
"\n\n".."If this chip is going into a robot or a drone, that is expected: "..
"put this computer's own EEPROM back before it restarts.","force",{title="Not a BIOS",severity=ab,yes="Flash anyway",no=Z})else
aU=
(i and i("Doesn't look like a BIOS — type 'force' to flash anyway: ",16))=="force"end
if not aU then E("Aborted (safety check).",d.dim)return end end;local aG=nil
if aO then
if aL then
E("Refusing --data: this file looks like a BIOS, and a BIOS keeps its",d.error)
E("boot address in the data field. --data is for a chip that is going",d.dim)E("into a robot or a drone.",d.dim)return end
if not i then E("--data needs a screen to ask on.",d.error)return end;local aV=256
do
local aY,aX=pcall(function()return aF.getDataSize()end)if aY and type(aX)==ae and aX>0 then aV=aX end end;local aU=i("Data for the chip (not shown): ",aV,true)if aU==nil or
aU==""then E(S,d.dim)return end
local aW=i("The same again, to confirm: ",aV,true)if aW~=aU then
E("The two did not match. Nothing was written.",d.error)return end;aG=aU end
local aT=aF.getLabel and aF.getLabel()or"(no label)"local aP="(unknown)"
do local aV,aU=pcall(O.getBootAddress)if aV and aU then aP=aU:sub(1,8)..
"..."end end;local aM=nil
do local aV,aU=pcall(require,"kernel.crypto")
if
aV and aU and aU.hash then local aX,aW=pcall(aU.hash,aD)if
aX and type(aW)==N and#aW==64 then aM=aW end end end
E(string.format("  Source : %s (%d bytes)",aI,#aD),d.dim)if aM then
E(string.format("  SHA-256: %s",aM),d.dim)else
E("  SHA-256: UNAVAILABLE - integrity cannot be verified",d.warning)end
E(string.format("  EEPROM : %s",aT),d.dim)
E(string.format("  Boot   : %s",aP),d.dim)if aG then
E(string.format("  Data   : %d bytes, as typed (not shown)",#aG),d.dim)end;local aN
if s then
aN=s("Overwrite this machine's EEPROM with "..
tostring(aI or
"this image").."?"..
"\n\n".."The EEPROM is what starts the computer. If the image is wrong, "..
"the machine will not boot and no software fix will reach it.","flash",{title="Flash EEPROM",severity=ab,yes="Flash",no=Z})else aN=(i and i('Type "flash" to confirm: ',16))==
"flash"end
if aN then local aU,aV=pcall(aF.set,aD)
if not aU then
E("Flash failed: "..tostring(aV),d.error)else
E("EEPROM flashed! "..#aD.." bytes written.",d.highlight)
if aG then local aW,aX=pcall(aF.setData,aG)if aW then
E("Data field set: "..#aG.." bytes.",d.highlight)else
E("The code was written, but the data field was NOT: "..tostring(aX),d.error)end end
if aL then E("Reboot for changes to take effect.",d.dim)else
E("This chip is not a BIOS: put this computer's own EEPROM back",d.dim)E("before it restarts.",d.dim)end end else E(S,d.dim)end end
local function D()
local E=a.SC or(_G._TOS and _G._TOS.config)return
E and E.get and E.get("accountAdmins")==true or false end
local function x(E)if L.liveTier(a)>=3 then return true,false end
if not D()then
E("Only root manages accounts on this machine. Root can let admins manage",d.error)
E("ordinary accounts with: users manage admins",d.dim)return false end;if not f(E)then return false end;return true,true end
local function K(E)
for aD,aC in
ipairs(g and
(g.list and g.list()or g.listUsers and g.listUsers())or{})do if(aC.username or aC.user)==E then return
tonumber(aC.tier or aC.accessLevel)end end end
local function F(aC,E)local aD=K(E)if aD and aD>=2 then
aC("An admin manages ordinary accounts only, and '"..E.."' is not one.",d.error)return false end;return true end
b.users=function(aC,E)if not f(E)then return end;if not g then E(_,d.error)return end
if aC[1]==
"manage"then
local aE=a.SC or(_G._TOS and _G._TOS.config)
if not aC[2]then
E("Accounts are managed by: "..
(D()and"root, and admins for ordinary accounts"or"root only"),d.fg)
E("Usage: users manage root|admins   (root only)",d.dim)return end;if not q(E)then return end;if aC[2]~="root"and aC[2]~=am then
E("Usage: users manage root|admins",d.dim)return end
if not
(aE and aE.set and aE.save)then E("No config to change.",d.error)return end;aE.set("accountAdmins",aC[2]==am)aE.save()
E(

aC[2]==am and"Admins may now add, remove and change ordinary accounts. Root still does the rest."or"Only root manages accounts now.",d.highlight)return end
E(string.format(" %-12s %-8s %s","User","Tier","Status"),d.title)E(string.rep("-",34),d.border)
local aD=g.list and g.list()or
g.listUsers and g.listUsers()or{}
for aF,aE in ipairs(aD)do local aG=aE.locked and"LOCKED"or"OK"
E(string.format(" %-12s %-8s %s",
aE.username or aE.user or"?",tostring(aE.tier or aE.accessLevel or"?"),aG),
aE.locked and d.error or d.dim)end end;local function y()if not g then return"root"end;local E=g.getSession(n)return
(E and E.user)or"root"end
b.useradd=function(aC,E)if
not x(E)then return end;if not g then E(_,d.error)return end;local aD=aC[1]if not aD then
E("Usage: useradd <username>",d.dim)return end
local aE=i("Password for "..aD..": ",64,true)if not aE or aE==""then E(S,d.dim)return end
local aF=i("Confirm password: ",64,true)
if aF~=aE then E("Passwords do not match.",d.error)return end;local aG,aH=g.create(y(),aD,aE,1)
if aG then
a.lastOut={"User '"..aD.."' created.",d.highlight}else a.lastOut={tostring(aH),d.error}end end
b.userdel=function(aC,E)local aF,aG=x(E)if not aF then return end
if not g then E(_,d.error)return end;local aD=aC[1]
if not aD then E("Usage: userdel <username>",d.dim)return end;if aG and not F(E,aD)then return end;local aE
if r then
aE=r("Delete the account '"..aD..
"'?\n\n"..
"Their home directory and files are NOT removed, but the account ".."cannot be recovered from here.",{title="Delete user",severity=ab,yes="Delete",no=Z})else
local aJ=i("Delete '"..aD.."'? [y/N]: ",1,false)aE=(aJ=="y"or aJ=="Y")end;if not aE then E(S,d.dim)return end;local aH,aI=g.delete(y(),aD)
if aH then
a.lastOut={
"User '"..aD.."' deleted.",d.highlight}else a.lastOut={tostring(aI),d.error}end end
b.usermod=function(aC,E)local aI,aJ=x(E)if not aI then return end
if not g then E(_,d.error)return end;local aF,aG=aC[1],aC[2]if not aF or not aG then
E("Usage: usermod <username> lock|unlock|admin|user|root",d.dim)return end;if aJ then if
aG=="admin"or aG=="root"then
E("Only root makes an admin or a root account.",d.error)return end
if not F(E,aF)then return end end
local aH=y()local aD,aE
if aG=="lock"then if g.setLocked then aD,aE=g.setLocked(aH,aF,true)else
aD,aE=false,"setLocked unavailable"end
if aD then
a.lastOut={"'"..aF.."' locked.",d.highlight}else a.lastOut={tostring(aE),d.error}end elseif aG=="unlock"then if g.setLocked then aD,aE=g.setLocked(aH,aF,false)else
aD,aE=false,"setLocked unavailable"end
if aD then
a.lastOut={"'"..aF.."' unlocked.",d.highlight}else a.lastOut={tostring(aE),d.error}end elseif aG=="admin"then if aF:lower()==an then
E("Failure. Did you mean 'usermod computer root'?",d.error)return end;if g.setTier then
aD,aE=g.setTier(aH,aF,2)else aD,aE=false,as end;if aD then a.lastOut={"'"..
aF.."' promoted to admin.",d.highlight}else
a.lastOut={tostring(aE),d.error}end elseif aG=="root"then
if
aF:lower()==an and a.D and
not(_G._TOS and _G._TOS._takeoverFired)then _G._TOS=_G._TOS or{}
_G._TOS._takeoverFired=true;local aL,aK=pcall(require,"shell.panels.takeover")
if
aL and aK and aK.run then local aM,aN=pcall(aK.run,a)
if a.D.invalidate then pcall(a.D.invalidate)end
pcall(function()
_G._TOS.logObj.info("kernel","The computer briefly reconsidered its priorities ("..
tostring(aM and aN or"?")..")")end)a.lastOut={"Access control updated.",d.dim}return end end
if g.setTier then aD,aE=g.setTier(aH,aF,3)else aD,aE=false,as end
if aD then
a.lastOut={"'"..aF.."' promoted to root.",d.highlight}else a.lastOut={tostring(aE),d.error}end elseif aG=="user"then
if g.setTier then aD,aE=g.setTier(aH,aF,1)else aD,aE=false,as end
if aD then
a.lastOut={"'"..aF.."' set to user.",d.highlight}else a.lastOut={tostring(aE),d.error}end else E("Unknown action: "..aG,d.error)
E("Valid: lock, unlock, admin, user, root",d.dim)end end
b.lsdev=function(aC,E)local aE=aC[1]=="--full"
E(string.format(" %-16s %-10s %s","Type","Address","Info"),d.title)E(string.rep("-",46),d.dim)local aD=0
for aF,aG in M.list()do local aH=""
if aG==ac then
local aJ,aI=pcall(M.proxy,aF)
if aJ and aI then
local aK=aI.getLabel and aI.getLabel()or""local aL=
aI.spaceTotal and math.floor(aI.spaceTotal()/1024)or 0
aH=(aK~=""and
'"'..aK..'" 'or"")..aL.."K"end elseif aG=="modem"then local aJ,aI=pcall(M.proxy,aF)
if aJ and aI and aI.isWireless then aH=
aI.isWireless()and"wireless"or"wired"end elseif aG=="drive"then local aJ,aI=pcall(M.proxy,aF)
if aJ and aI and aI.getCapacity then aH="raw "..
math.floor((
aI.getCapacity()or 0)/1024).."K"end elseif aG=="openprinter"then local aJ,aI=pcall(M.proxy,aF)
if aJ and aI then local function aK(aL)
if aL==nil then return"?"end;local aN,aM=pcall(aL)
return(aN and tonumber(aM))and
tostring(math.floor(aM))or"?"end
aH="paper "..
aK(aI.getPaperLevel).." ink "..
aK(aI.getBlackInkLevel).."/"..aK(aI.getColorInkLevel)end end
E(string.format(" %-16s %s  %s",aG,aE and aF or(aF:sub(1,8).."..."),aH),d.fg)aD=aD+1 end
if aD==0 then E("  (no peripherals detected)",d.dim)end end;b.devices=b.lsdev
b.mount=function(aC,E)
if aC[1]and aC[2]then if not f(E)then return end
local aF,aI=aC[1],aC[2]local aE={}local aD={}
for aO in M.list(ac)do
if aO:sub(1,#aF)==aF then aD[#aD+1]=aO else
local aQ,aP=pcall(M.proxy,aO)if aQ and aP and aP.getLabel and aP.getLabel()==aF then aE[#aE+
1]=aO end end end;local aG=nil
if#aD==1 then aG=aD[1]elseif#aD>1 then table.sort(aD)
E(string.format("Ambiguous address prefix '%s' matches %d devices (%s, ...); use a longer prefix",aF,
#aD,aD[1]:sub(1,8).."..."),d.error)return end
if not aG and#aE>0 then table.sort(aE)aG=aE[1]
if#aE>1 then
E(string.format("Note: %d disks share label '%s'; mounting %s (use partial address to disambiguate)",
#aE,aF,aG:sub(1,8).."..."),d.warning)end end
if not aG then E("Device not found: "..aF,d.error)return end
local aH=aI:sub(1,1)=="/"and aI or("/"..aI)local aJ,aK=pcall(M.proxy,aG)if not aJ then
E("Cannot proxy device",d.error)return end;if not e.exists(aH)then
pcall(e.makeDirectory,aH)end;local aL=L.sessionOf(a)
local aM,aN=e.mount(aH,aK,aL)
if aM==false then E(tostring(aN or al),d.error)return end;a.lastOut={"Mounted at "..aH,d.highlight}else
local aE=e.mounts()
E(string.format(" %-18s %-14s %s","Mount","Label","Space"),d.title)E(string.rep("-",46),d.dim)
for aH,aG in ipairs(aE)do
local aI=aG.total and math.floor(
aG.total/1024)or 0
local aJ=aG.used and math.floor(aG.used/1024)or 0
E(string.format(" %-18s %-14s %dK/%dK",(aG.mountPoint or"?"):sub(1,18),(
aG.label or""):sub(1,14),aJ,aI),d.fg)end;local aF,aD={},0
for aH,aG in ipairs(aE)do aF[aG.address or""]=true end
for aG in M.list("drive",true)do if not aF[aG]then aD=aD+1 end end
if aD>0 then E("",d.dim)
E(aD.." unmanaged (raw) drive(s) are attached and NOT listed above:",d.warning)
E("they hold no filesystem yet, so there is nothing to mount.",d.dim)E("  drive list           see them",d.dim)
E("  drive format <addr>  make one a TBFS filesystem",d.dim)
E("  drive mount <addr>   then mount it here",d.dim)end end end
b.umount=function(E,aC)
if not E[1]then aC("Usage: umount <mountpoint>",d.dim)return end;if not f(aC)then return end;local aD=E[1]:sub(1,1)=="/"and E[1]or
("/"..E[1])local aE=L.sessionOf(a)
local aF,aG=e.unmount(aD,aE)if aF then a.lastOut={"Unmounted "..aD,d.highlight}else
a.lastOut={tostring(aG or
"Failed to unmount"),d.error}end end
b.jbod=function(aC,E)local aD=h.getJBOD and h.getJBOD()
if not aD then
E("JBOD is disabled. Enable it with: bootsettings jbod on  (then reboot)",d.warning)
E("It pools several disks into one mount. See 'man jbod'.",d.dim)return end;local aE=(aC[1]or"list"):lower()
local function aF(aG)local aH,aI={},{}
for aJ in
M.list(ac)do
if aJ:sub(1,#aG)==aG then aH[#aH+1]=aJ else local aL,aK=pcall(M.proxy,aJ)if
aL and aK and aK.getLabel and aK.getLabel()==aG then
aI[#aI+1]=aJ end end end;table.sort(aH)table.sort(aI)
if#aH==1 then return aH[1]end;if#aH==0 and#aI==1 then return aI[1]end;if#aH>1 then return nil,
"ambiguous address prefix: "..aG end;if#aI>1 then return nil,
"ambiguous label: "..aG end
return nil,"no filesystem matches: "..aG end
if aE=="list"or aE==P then
local aH=aD.loadConfig(e)or{pools={}}local aG=aH.pools or{}if#aG==0 then
E("No JBOD pools configured.",d.dim)end
for aJ,aI in ipairs(aG)do local aK=0
for aJ,aL in ipairs(aI.members or{})do for aM in
M.list(ac)do if aM==aL then aK=aK+1;break end end end
E(string.format(" %-16s %d member(s), %d present",aI.mount,# (aI.members or{}),aK),d.fg)end
E("Free space: df  ·  individual disks: disk  ·  manage: jbod create|destroy",d.dim)elseif aE=="create"then if not f(E)then return end;local aG=aC[2]
if not aG or not aC[3]then
E("Usage: jbod create <mountpoint> <disk> [disk...]",d.dim)
E("  <disk> = fs address prefix or label (see lsdev)",d.dim)return end;if aG:sub(1,1)~="/"then aG="/"..aG end;aG=
(e.normalize and e.normalize(aG))or aG;if not
(aG:sub(1,5)=="/mnt/"and#aG>5)then
E("JBOD mount point must be under /mnt/  (e.g. jbod create /mnt/pool ...)",d.error)return end;local aK=_G._TOS and
_G._TOS.bootAddr;local aJ,aI={},{}
for aP=3,#aC do local aQ,aS=aF(aC[aP])if not aQ then
E(tostring(aS),d.error)return end
if aK and aQ==aK then
E("Refusing to pool the BOOT disk ("..
aQ:sub(1,8).."...).",d.error)
E("It would expose the system files inside the pool. Use data disks.",d.dim)return end;local aT,aR=pcall(M.proxy,aQ)if not aT or not aR then
E("Cannot open disk: "..aC[aP],d.error)return end;aJ[#aJ+1]=aR
aI[#aI+1]=aQ end;pcall(e.makeDirectory,"/mnt")
pcall(e.makeDirectory,aG)local aL=aD.makePool(aJ)local aM=L.sessionOf(a)
local aN,aO=e.mount(aG,aL,aM)
if not aN then E(tostring(aO or al),d.error)return end;local aH=aD.loadConfig(e)or{pools={}}
aH.pools=aH.pools or{}for aP=#aH.pools,1,-1 do if aH.pools[aP].mount==aG then
table.remove(aH.pools,aP)end end;aH.pools[
#aH.pools+1]={mount=aG,members=aI}
aD.saveConfig(e,aH)
a.lastOut={string.format("JBOD pool at %s (%d disks)",aG,#aI),d.highlight}elseif aE=="destroy"or aE==af then if not f(E)then return end;local aG=aC[2]if not aG then
E("Usage: jbod destroy <mountpoint>",d.dim)return end
if aG:sub(1,1)~="/"then aG="/"..aG end;local aJ=L.sessionOf(a)e.unmount(aG,aJ)
local aH=aD.loadConfig(e)or{pools={}}local aI=false
for aK=# (aH.pools or{}),1,-1 do if aH.pools[aK].mount==aG then
table.remove(aH.pools,aK)aI=true end end;if aI then aD.saveConfig(e,aH)end
a.lastOut={aI and
("Destroyed JBOD pool "..aG)or("No JBOD pool at "..aG),
aI and d.highlight or d.warning}else
E("Usage: jbod [list | create <mount> <disk...> | destroy <mount>]",d.dim)end end
b.netfs=function(aC,E)local aG,aD=L.requireRoomy(a,"kernel.netfs","admin")if not aG or
not aD then E(L.loadFailure("netfs",aD),d.error)
return end
local aE=(aC[1]or P):lower()
local function aF()local aH={}for aJ,aI in ipairs(e.mounts()or{})do
if type(aI.address)==N and
aI.address:sub(1,6)=="netfs:"then aH[#aH+1]=aI end end
table.sort(aH,function(aI,aJ)return
aI.mountPoint<aJ.mountPoint end)return aH end
if aE==P or aE=="list"then
local aH=aD.isEnabled and aD.isEnabled()
local aI=aD.getExports and aD.getExports()or{}
local aK=m and m.getServiceArm and m.getServiceArm("netfsd")
E("Serving: "..
(
aH and"yes"or aK and"no (export file rejected; see: netfs exports)"or"no (service netfsd is not running)"),
aH and d.highlight or d.warning)
if#aI==0 then
E("  No exports configured ("..aD.EXPORTS_PATH..").",d.dim)else for aM,aL in ipairs(aI)do
E(string.format("  %-12s %-24s %s  %d peer rule(s)",aL.name,aL.path,aL.mode,# (aL.allow or{})),d.fg)end end;local aJ=aF()E("",d.fg)
if#aJ==0 then E("Mounted: none",d.dim)else
E("Mounted:",d.fg)
for aM,aL in ipairs(aJ)do local aN=(aL.total or 0)>0
E(string.format("  %-16s %-22s %s",aL.mountPoint,aL.label,

aN and t(aL.total- (aL.used or 0)).." free"or"unreachable"),
aN and d.fg or d.warning)end end
E("Manage: netfs mount <host> <share> <mountpoint> · netfs umount <mountpoint>",d.dim)elseif aE=="exports"then local aI,aJ=aD.loadExports(e)if not aI then
E("Export file rejected: "..tostring(aJ),d.error)
E("Nothing is served while the file is invalid.",d.dim)return end
local aH=aD.getExports()
if#aH==0 then
E("No exports in "..aD.EXPORTS_PATH,d.dim)
E("Format: { { name=\"pub\", path=\"/srv/pub\", mode=\"ro\", allow={\"<addr>\"} } }",d.dim)return end
for aL,aK in ipairs(aH)do
E(string.format("%-12s %-24s %s",aK.name,aK.path,aK.mode),d.highlight)
for aL,aM in ipairs(aK.allow or{})do E("    allow "..aM,d.dim)end;if# (aK.allow or{})==0 then
E("    allow (none) — this export is unreachable",d.warning)end end elseif aE=="mount"then if not f(E)then return end;local aL,aJ,aI=aC[2],aC[3],aC[4]
if not
(aL and aJ and aI)then
E("Usage: netfs mount <host> <share> <mountpoint>",d.dim)
E("  <host>  = peer hostname or address prefix (see net peers)",d.dim)
E("  <share> = export name on that machine (ask its operator)",d.dim)return end
if not m then E("Networking is not available.",d.error)return end;local aH=aL;local aO,aM=pcall(require,"shell.ext")
if
aO and type(aM)=="table"and aM.resolvePeer then aH=aM.resolvePeer(aL)end;local aN=m.findPeer and m.findPeer(aH)if aN and aN.addr then
aH=aN.addr end
if m.getTrust or m.getProtocol then
local aU,aT=pcall(require,"kernel.net.trust")
if aU and aT and aT.getLevel and aT.LEVEL then
if aT.getLevel(aH)<
aT.LEVEL.TRUSTED then
E("Peer is not TRUSTED — netfs refuses to mount from it.",d.error)
E("Raise trust first (see 'net trust'), then retry.",d.dim)return end end end;if not(aI:sub(1,5)=="/mnt/"and#aI>5)then
E("Mount point must be under /mnt/  (e.g. netfs mount box pub /mnt/box)",d.error)return end
local aK=aD.attach(aH,aJ)
local aP=aK.spaceTotal and aK.spaceTotal()or 0
if not aK.exists("/")and aP==0 then
E("Cannot reach share '"..aJ.."' on "..
tostring(aH):sub(1,8)..".",d.error)
E("Check the export name, and that netfsd runs there and allows this machine.",d.dim)return end;pcall(e.makeDirectory,"/mnt")
pcall(e.makeDirectory,aI)local aQ=L.sessionOf(a)local aR,aS=e.mount(aI,aK,aQ)if not aR then
E(tostring(aS or al),d.error)return end
E("Mounted "..aJ.." from "..tostring(aH):sub(1,8)..
" at "..aI,d.highlight)
E("This mount is only usable while that machine is online.",d.dim)elseif aE=="umount"then if not f(E)then return end;local aH=aC[2]if not aH then
E("Usage: netfs umount <mountpoint>",d.dim)return end;local aI=false;for aN,aM in ipairs(aF())do if
aM.mountPoint==aH then aI=true;break end end;if not aI then E(
"No netfs mount at "..aH,d.warning)
E("Use 'netfs status' to list them (plain 'umount' handles local disks).",d.dim)return end
local aJ=L.sessionOf(a)local aK,aL=e.unmount(aH,aJ)if aK then
E("Unmounted "..aH,d.highlight)else
E(tostring(aL or"Failed to unmount"),d.error)end else
E("Usage: netfs [status | exports | mount <host> <share> <mount> | umount <mount>]",d.dim)end end
b.theme=function(aC,E)local aD=_G._TOS and _G._TOS.theme;if not aD then
E("Theme manager unavailable (T1 / monochrome or low-RAM boot)",d.warning)return end
do
local aI=(aC[1]or"show"):lower()
local aJ={list=true,ls=true,show=true,current=true,keys=true,[""]=true}local aK={color=true,colour=true}
if aK[aI]then if not f(E)then return end elseif not aJ[aI]then if
L.liveTier(a)<1 then
E("Log in as a user to set a personal theme.",d.error)return end end end
local function aH(aI)if not aI then return nil end
if type(aI)~=N or#aI>16 then return nil end;local aJ=aI:match("^0[xX](%x+)$")or aI:match("^#(%x+)$")or
aI:match("^(%x+)$")if aJ and#
aJ<=6 then return tonumber(aJ,16)end
return tonumber(aI)end;local function aG(aI)return string.format("0x%06X",aI)end;local aE=
aC[1]and aC[1]:lower()or"show"
local aF=L.sessionOf(a)
if aE=="list"or aE=="ls"then E("Available themes:",d.title)for aJ,aI in
ipairs(aD.list())do
local aK=(aI==aD.current().preset)and" *"or"  "
E(string.format(" %s %-10s %s",aK,aI,aD.describe(aI)or""),d.fg)end
E("",d.fg)
E("'*' = currently active.  Use 'theme set <name>' to switch.",d.dim)elseif aE=="show"or aE=="current"then local aI=aD.current()
E("Active theme: "..aI.preset,d.title)
E("  ".. (aD.describe(aI.preset)or""),d.dim)local aJ=0;for aK in pairs(aI.overrides)do aJ=aJ+1 end
if aJ==0 then
E("No color overrides.",d.dim)else E("Overrides:",d.highlight)for aK,aL in pairs(aI.overrides)do
E(string.format("  %-14s %s",aK,aG(aL)),d.fg)end end;E("",d.fg)
E("Try: theme set <name>  |  theme color <key> <0xRRGGBB>  |  theme reset",d.dim)elseif aE=="set"or aE=="use"then local aI=aC[2]if not aI then
E("Usage: theme set <name>  (theme list to see names)",d.warning)return end;local aJ,aK=aD.apply(aI)
if
not aJ then E(aK or"apply failed",d.error)return end;E("Applied theme: "..aI,d.highlight)
if aF then
local aL,aM=aD.saveForUser(aF)if not aL then
E("(not saved: "..tostring(aM)..")",d.dim)end end;c.drawAll()elseif aE=="preview"or aE=="try"then local aI=aC[2]if not aI then
E("Usage: theme preview <name>",d.warning)return end;local aJ,aK=aD.apply(aI)if not aJ then
E(aK or"apply failed",d.error)return end
E("Previewing '"..
aI.."' (not saved). Use 'theme set' to keep it.",d.highlight)c.drawAll()elseif aE=="color"or aE=="colour"then local aI,aJ=aC[2],aC[3]if not aI or
not aJ then
E("Usage: theme color <key> <0xRRGGBB>",d.warning)
E("Keys: "..table.concat(aD.overridableKeys(),", "),d.dim)return end
if not
aD.isOverridable(aI)then
E("Not an overridable color: "..aI,d.error)
E("Run 'theme color' with no args for the full list.",d.dim)return end;local aK=aH(aJ)if not aK then
E("Invalid color value: "..aJ.." (try 0xFF8800)",d.error)return end
local aL,aM=aD.setColor(aI,aK)
if not aL then E(aM or"color set failed",d.error)return end
E(string.format("%s = %s",aI,aG(aK)),d.highlight)if aF then aD.saveForUser(aF)end;c.drawAll()elseif aE=="reset"then
local aI,aJ=aD.resetOverrides()
if not aI then E(aJ or"reset failed",d.error)return end
E("Cleared color overrides; preset '"..aD.current().preset.."' restored.",d.highlight)if aF then aD.saveForUser(aF)end;c.drawAll()elseif aE=="clear"or aE==
"default"then
if not aF then E("Not logged in.",d.error)return end;local aI,aJ=aD.clearForUser(aF)if not aI then
E(aJ or"clear failed",d.error)return end
E("Theme reset to default; saved preference cleared.",d.highlight)c.drawAll()elseif aE=="keys"then
E("Overridable color keys:",d.title)
for aJ,aI in ipairs(aD.overridableKeys())do E("  "..aI,d.fg)end else
E("Usage: theme <list|show|set|preview|color|reset|clear|keys>",d.warning)
E("  list                  Show available themes",d.dim)
E("  show                  Show active theme + overrides",d.dim)
E("  set <name>            Apply preset and save for this user",d.dim)
E("  preview <name>        Apply preset without saving",d.dim)
E("  color <key> <0xRGB>   Override a single color",d.dim)
E("  keys                  List overridable color keys",d.dim)
E("  reset                 Drop overrides, keep preset",d.dim)
E("  clear                 Wipe saved theme, revert to default",d.dim)end end;b.colors=b.theme
b.service=function(E,aC)
if E[1]and E[1]~="list"and not f(aC)then return end;local aE,aD=L.requireRoomy(a,"kernel.rc","admin")if not aE then
aC(L.loadFailure("service",aD),d.error)return end
if not E[1]or E[1]=="list"then
local aF=aD.list()
if#aF==0 then aC("No services registered",d.dim)return end
aC(string.format(W,"Service","Status"),d.title)aC(string.rep("-",28),d.dim)
for aH,aG in ipairs(aF)do
local aI=
aG.running and"running"or
(aG.unavailable and("not loaded: "..aG.unavailable))or
(aG.enabled==false and ao)or"stopped"
aC(string.format(W,aG.name:sub(1,16),aI),
aG.running and d.highlight or d.dim)end elseif E[1]=="start"and E[2]then local aF,aG=aD.start(E[2])
aC(
aF and"Started: "..E[2]or tostring(aG),aF and d.highlight or d.error)
if aF then local aI,aH=pcall(require,"kernel.pkg")
if
aI and type(aH)=="table"and aH.noteServiceStarted then
local aJ=aH.noteServiceStarted(E[2],{session=L.sessionOf(a)})if aJ then
aC("Package '"..aJ.."' enabled with it.",d.dim)end end
if E[2]:find("rshd",1,true)then
local aK,aJ=pcall(require,"kernel.net.remote")
if aK and type(aJ)=="table"and aJ.stepBudgetAvailable and not
aJ.stepBudgetAvailable()then
aC("OpenComputers gives remote commands no CPU or memory limit:",d.warning)
aC("a runaway one stops this whole machine.",d.warning)end end end elseif E[1]=="stop"and E[2]then local aF,aG=aD.stop(E[2])
aC(
aF and"Stopped: "..E[2]or tostring(aG),aF and d.highlight or d.error)else
aC("Usage: service [list | start <name> | stop <name>]",d.dim)end end
b.cron=function(aC,E)if not f(E)then return end
if _G._TOS and _G._TOS.cronDisabled then
E("Cron is off in this boot profile: no job runs.",d.warning)local aH=e.readFile("/etc/cron.dat")
local aK,aI=pcall(require,"kernel.serialize")local aJ,aG=false,nil;if aH and aK and aI then
aJ,aG=pcall(aI.decode,aH,{maxBytes=65536})end;local aF={}
if aJ and type(aG)=="table"and
type(aG.jobs)=="table"then for aM,aL in pairs(aG.jobs)do
if type(aL)=="table"then aF[
#aF+1]={id=aM,name=tostring(aL.name)}end end end
table.sort(aF,function(aL,aM)return tostring(aL.id)<tostring(aM.id)end)
if#aF>0 then
E(#aF.." saved job(s), which run again after a normal boot:",d.dim)for aM,aL in ipairs(aF)do
E(string.format(" %-4s %s",tostring(aL.id),aL.name),d.dim)end end
if aC[1]and aC[1]~="list"then
E("cron: jobs cannot be changed in this boot profile; boot normally to edit them."..
"  [E-404 ERR_SAFE_MODE]",d.error)end;return end;local aE,aD=L.requireRoomy(a,"kernel.cron","admin")if not aE then
E(L.loadFailure("cron",aD),d.error)return end
if not aC[1]or aC[1]=="list"then
local aF=aD.list()
if#aF==0 then E("No scheduled jobs",d.dim)return end
E(string.format(" %-4s %-16s %-8s %s","ID","Name","Every","Enabled"),d.title)
for aH,aG in ipairs(aF)do
E(string.format(" %-4d %-16s %-8s %s",aG.id,aG.name:sub(1,16),aG.interval.."s",aG.enabled and
"yes"or"no"),
aG.enabled and d.fg or d.dim)end elseif aC[1]=="add"and aC[2]and aC[3]and aC[4]then
local aF=aC[2]local aG=tonumber(aC[3])local aI=table.concat(aC," ",4)if not aG then
E("Invalid interval. Usage: cron add <name> <seconds> <script>",d.error)return end
local aH,aJ=aD.add(aF,aG,aI)if not aH then E(tostring(aJ),d.error)return end
E(
"Added job #"..aH..": "..aF,d.highlight)elseif aC[1]=="rm"and aC[2]then local aF=tonumber(aC[2])
if aF then
local aG,aH=aD.remove(aF)if aG then E("Removed job #"..aF,d.highlight)else
E("cron rm: "..tostring(aH or
"no such job"),d.error)end else
E("Invalid ID",d.error)end else
E("Usage: cron [list|add <name> <seconds> <script>|rm <id>]",d.dim)end end end