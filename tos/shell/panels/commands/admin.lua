
local ae,af,P,Q,V,W,T,R,X,ag,ah,ai,aj,Y,S,ak,Z,al,_,am,aa,an,ao,ab,U,ac,ad,ap,aq,ar,O,M,as="  %-20s %s -> %s","(--dry-run: nothing was changed)","--allow-unsigned","--allow-unverified","--dry-run","--dryrun","--force","Aborted.","Cancel","Cannot read: ","Error: ","From repos nobody configured: ","Mount failed","No user system","Refused: ","admins","compact","computer","danger","disabled","filesystem","floppy","install","kernel.log","kernel.pkgsign","number","remove","repair","setTier unavailable","shell.panels.tabs","status","string","version"local N=require(al)local L=require("component")
local K=require("shell.panels.helpers")
return
function(b,a,c)local h,au,o,e,j,g=a.K,a.E,a.P,a.F,a.D,a.U;local av,m,n=a.SC,a.NM,a.st;local d=a.T;local aw=a.tier
local l,k=a.W,a.H;local u=c.rp;local z=c.openViewTab;local G=c.openEditTab;local H=c.refreshBrowser
local ax=c.canRead;local ay=c.canWrite;local az=c.canAccess;local q=c.rootOnly;local f=c.adminOnly
local v=c.makeProgramEnv;local t=K.fmtSz
local aA=function(E)return K.expandBuf(a,E)end;local i=c.promptInput;local r=c.confirm;local s=c.confirmTyped
b.kill=function(aB,E)
if not f(E)then return end
if not aB[1]then E("Usage: kill <pid>",d.dim)return end;local aC=tonumber(aB[1])
if aC then local aD,aE=o.kill(aC)
if aD then
E("Killed PID "..aC,d.highlight)else E(tostring(aE),d.error)end else E("Invalid PID",d.error)end end
b.fg=function(aB,E)if not f(E)then return end
if not aB[1]then E("Usage: fg <pid>",d.dim)return end;local aC=tonumber(aB[1])if not aC or not o.get(aC)then
E("No such process",d.error)return end
local aD,aE=o.setForeground(aC,a.displayIdx)if not aD then
E(tostring(aE or"Cannot foreground that process"),d.error)return end
E("Foreground: PID "..aC,d.highlight)end
b.verify=function(aB,E)if not f(E)then return end;local aC=aB and aB[1]and
tostring(aB[1]):lower()
if aC=="anchor"then local aF=false
for aI=2,#aB do
local aJ=tostring(aB[aI]):lower()if aJ=="--clear"or aJ=="clear"then aF=true end end
if aF then if not h.clearManifestAnchor then
E("This TOS build cannot clear the anchor.",d.error)return end
local aI,aJ=h.clearManifestAnchor()
if aI then
E("Manifest anchor cleared. `doctor` will report it un-anchored.",d.highlight)else
E("Could not clear the anchor: "..tostring(aJ),d.error)end;return end;if not h.anchorManifestHash then
E("This TOS build has no manifest anchoring.",d.error)return end
E("Anchoring records THIS system's manifest hash in the EEPROM.",d.dim)
E("Only do it on a system you trust (fresh install, or verified).",d.dim)local aH,aG=h.anchorManifestHash()
if aH then
E("Anchored: "..
tostring(aG):sub(1,32).."...",d.highlight)
E("Your boot address was preserved; changing the boot device clears it.",d.dim)else
E("Anchor failed: "..tostring(aG),d.error)end;return end
E("=== File integrity (every system file vs the manifest) ===",d.title)
E("Checking presence, syntax, and declared hashes...",d.dim)E("")
local aD,aE=pcall(h.verifySystem,function(aF,aG)E(aF,aG)end)
if not aD then E("verify: "..tostring(aE),d.error)end;E("")
E("This checks FILES. For runtime health (memory/power/services), run 'doctor'.",d.dim)
E("It compares against the MANIFEST. To catch a file that changed since you",d.dim)
E("knew the system was good — and to put it back — use 'srm scan' / 'srm repair'.",d.dim)end;local A=1280
local p={tofu="trusted keys, or a new key you approve; never unsigned.",trusted="trusted keys only.",off="nothing; configured repos only."}
local function w(aB,E,aC)local aD=tostring(aB)
if not
(aD:find("not enough memory",1,true)or
aD:find("not enough free memory",1,true)or aD:find("Out of memory",1,true))then return end
local aE=math.floor(
(N.totalMemory and N.totalMemory()or 0)/1024)
if aE<A then
E(string.format("%s needs %d KB of RAM; this machine has %d KB.",aC,A,aE),d.dim)else
E("Something else is holding the memory it needs: close other tabs or ".."programs, or reboot, and try again.",d.dim)end end;local I={list=true,search=true,available=true,info=true}
b.pkg=function(aB,E)if aB[1]and not
I[aB[1]]and not f(E)then return end
local aH,aC=K.requireRoomy(a,"kernel.pkg","admin")if not aH or not aC then local aJ=K.loadFailure("pkg",aC)E(aJ,d.error)
w(aJ,E,"The package manager")return end;local aD=aB[1]
local function aF(aJ)
for aL,aK in
ipairs(aJ or{})do local aM=aC.info and aC.info(aK)
if type(aM)=="table"and
aM.kind=="service"then local aN={}
for aL,aO in ipairs(aM.files or{})do
local aP=tostring(aO):match("^/etc/rc%.d/(.+)%.lua$")if aP then aN[#aN+1]=aP end end
if#aN>0 then
local aO=type(aM.service)=="table"and aM.service.defaultState==am
E(string.format(
aO and"  %s's service is installed switched off. To start it: service start %s"or"  %s runs as a service from the next boot. To start it now: service start %s",aK,table.concat(aN,", ")),d.dim)end end end end
local function aG()local aJ={}
for aL,aK in
ipairs((aC.list and aC.list())or{})do
local aM=type(aK)=="table"and aK.name or aK;if type(aM)==M then aJ[aM]=true end end;return aJ end
local function aI(aJ,aK)
local aL=((aJ.name or"").." ".. (aJ.description or"")..
" ".. (aJ.category or"")):lower()return aL:find(aK:lower(),1,true)~=nil end
local function aE(aJ,aK)local aL=2
while aL<=#aB do local aM=tostring(aB[aL])
if aJ[aM]=="value"then aL=aL+1 elseif
aM:sub(1,2)=="--"and not aJ[aM]then
E(string.format("pkg %s: unknown option '%s' -- nothing was done.",tostring(aD),aM),d.error)E("Options: "..aK,d.dim)return true end;aL=aL+1 end;return false end
if not aD or aD=="list"then local aJ=aC.list()if#aJ==0 then
E("No packages installed.",d.dim)return end
E(string.format(" %-24s %-10s %s","name",as,"kind"),d.title)for aL,aK in ipairs(aJ)do
E(string.format(" %-24s %-10s %s",aK.name:sub(1,24),(aK.version or"?"):sub(1,10),
aK.kind or"?"),d.fg)end elseif
aD=="search"or aD=="available"then
local aJ=aC.listAllAvailable({includeRemote=true})
if#aJ==0 then E("No packages available.",d.dim)
E("Looked on disk under /usr/repo, /var/repo and /mnt/*",d.dim)local aM=aC.repos and aC.repos()or{}
if#aM==0 then
E("No remote repos are configured — add one with:",d.dim)
E("  pkg repo add <name> <https://host/path>",d.dim)else
E(#aM.." remote repo(s) configured but none answered.",d.dim)
E("That usually means no internet card, or the host is",d.dim)
E("unreachable. `pkg repo list` shows what is configured.",d.dim)end;return end;local aK=aB[2]
if aK then local aM={}
for aO,aN in ipairs(aJ)do if aI(aN,aK)then aM[#aM+1]=aN end end;if#aM==0 then
E("Nothing available matches '"..aK.."'. `pkg search` lists everything.",d.dim)return end;aJ=aM end
table.sort(aJ,function(aM,aN)
if
(aM.category or"misc")~= (aN.category or"misc")then return
(aM.category or"misc")< (aN.category or"misc")end;return(aM.name or"")< (aN.name or"")end)
E(string.format(" %-20s %-10s %s","name",as,"source"),d.title)local aL=nil
for aN,aM in ipairs(aJ)do local aO=aM.category or"misc"if aO~=aL then aL=aO
E("  ["..aO.."]",d.dim)end
local aP=aM.remote and
("repo:"..tostring(aM.repo or"?"))or tostring(aM.root or"?")
E(string.format(" %-20s %-10s %s",(aM.name or"?"):sub(1,20),(aM.version or"?"):sub(1,10),aP),d.fg)end elseif aD=="trust"then local aJ=(aB[2]or"list"):lower()
if
aJ=="list"then local aK=aC.trustList()
if#aK==0 then
E("No publisher keys are trusted on this machine.",d.dim)
E("Every package therefore reads as unsigned or as signed-by-an-",d.dim)
E("unknown-key, and your admin privilege is the only gate.",d.dim)
E("Add one:  pkg trust add <name> <64-hex-key>",d.dim)else local aL=16
for aO,aN in ipairs(aK)do aL=math.max(aL,#aN.label)end;local aM=" %-"..aL.."s %s"
E(string.format(aM,"name","fingerprint"),d.title)for aO,aN in ipairs(aK)do
E(string.format(aM,aN.label,aN.fingerprint),d.fg)end;E("",d.dim)
E("Compare a fingerprint with the publisher over a channel that is",d.dim)
E("NOT the disk it came on. A key that arrives with the package it",d.dim)E("signs proves nothing at all.",d.dim)end
E(string.format("Unsigned packages are currently %s.",aC.trustRequired()and"REFUSED"or
"allowed (admin gate only)"),
aC.trustRequired()and d.highlight or d.dim)
E(ai..p[aC.discoveredPolicy()].."  (pkg trust discovered)",d.dim)elseif aJ=="discovered"then local aK=(aB[3]or""):lower()if aK==""then E(ai..
p[aC.discoveredPolicy()],d.fg)
E("Usage: pkg trust discovered tofu|trusted|off",d.dim)return end
if not p[aK]then
E("Usage: pkg trust discovered tofu|trusted|off",d.dim)E("  tofu     "..p.tofu,d.dim)
E("  trusted  "..p.trusted,d.dim)E("  off      "..p.off,d.dim)return end
local aL,aM=aC.trustDiscovered(aK,{session=K.sessionOf(a)})
if not aL then E(S..tostring(aM),d.error)return end;E(ai..p[aK],d.highlight)elseif aJ=="add"then
if
not(aB[3]and aB[4])then
E("Usage: pkg trust add <name> <64-hex-public-key>",d.dim)
E("<name> is YOUR label for the publisher — it is how you will",d.dim)
E("refer to them locally, and has nothing to do with whatever",d.dim)E("name their disk claims.",d.dim)return end
local aK,aL=aC.trustAdd(aB[3],aB[4],{session=K.sessionOf(a)})
if not aK then E(S..tostring(aL),d.error)return end;E("Trusted '"..aB[3].."'.",d.highlight)
E("Packages signed by this key will now install without a fresh",d.dim)
E("judgement call. That is the point, and the cost.",d.dim)elseif aJ==ad or aJ=="rm"then if not aB[3]then
E("Usage: pkg trust remove <name>",d.dim)return end
local aK,aL=aC.trustRemove(aB[3],{session=K.sessionOf(a)})
if not aK then E(S..tostring(aL),d.error)return end
E("Removed '"..aB[3].."'. Already-installed packages are",d.highlight)
E("unaffected — this changes what will be accepted from now on.",d.dim)elseif aJ=="require"then local aK=(aB[3]or""):lower()
if
aK~="on"and aK~="off"then E("Usage: pkg trust require on|off",d.dim)
E("`on` refuses unsigned packages outright. Consider what is on",d.dim)
E("your Optional Utilities disks before turning it on.",d.dim)return end
local aL,aM=aC.trustRequire(aK=="on",{session=K.sessionOf(a)})
if not aL then E(S..tostring(aM),d.error)return end
E("Unsigned packages are now "..
(aK=="on"and"REFUSED."or"allowed."),d.highlight)elseif aJ=="key"then
if not aB[3]then
E("Usage: pkg trust key <publisher-label>",d.dim)
E("Prints the public key you sign as under that label, and asks",d.dim)
E("for the passphrase without echoing it. Publish the key; never",d.dim)
E("the passphrase. The label is part of the key: the same",d.dim)
E("passphrase under a different label is a different identity.",d.dim)return end
if aB[4]then
E("Too many arguments. Only the publisher label goes here — the",d.error)
E("passphrase is asked for separately, and must never be typed",d.dim)
E("on the command line where it is echoed and recalled.",d.dim)return end;if not i then
E("This needs an interactive prompt for the passphrase.",d.error)return end
local aK=i("Signing passphrase: ",96,true)if not aK or aK==""then E(R,d.dim)return end
local aL,aN=aC.signingKey(aK,aB[3])if not aL then E(tostring(aN),d.error)return end
E(aL,d.highlight)local aO,aM=pcall(require,U)if aO and aM then
E("fingerprint "..aM.fingerprint(aL),d.dim)
E("signing as '"..tostring(aM.normalizeLabel(aB[3])).."'",d.dim)end else
E("Usage: pkg trust [list|add|remove|require|key] ...",d.dim)end elseif aD=="verify-sig"or aD=="checksig"then if not aB[2]then
E("Usage: pkg verify-sig <directory>",d.dim)
E("Says who signed a package WITHOUT installing it.",d.dim)return end
local aJ,aK=aC.checkSignature(aB[2])if not aJ then E(tostring(aK),d.error)return end
E(
"Package: "..tostring(aK and aK.name or"?"),d.title)local aM,aL=pcall(require,U)
if aM and aL then for aO,aN in ipairs(aL.describe(aJ))do
E(aN,aJ.state==
"trusted"and d.highlight or(aJ.state=="invalid"and d.error or
d.warning))end end elseif aD=="sign"then
if not aB[2]then
E("Usage: pkg sign <directory> --as <publisher-name>",d.dim)
E("Signs the package's manifest with a key derived from a",d.dim)
E("passphrase you will be asked for. The signature covers the",d.dim)
E("MANIFEST, which covers the file hashes, which cover the files —",d.dim)
E("so sign AFTER the hashes are final, not before.",d.dim)return end;local aJ
for aP=3,#aB do if aB[aP]=="--as"then aJ=aB[aP+1]end end
if not aJ or aJ==""then
E("Usage: pkg sign <directory> --as <publisher-name>",d.error)
E("--as is required: the label salts your signing key, so the same",d.dim)
E("passphrase under a different label is a different identity.",d.dim)
E("Use the same label every time — it is part of who you are.",d.dim)return end;if not i then
E("Signing needs an interactive prompt for the passphrase.",d.error)return end
local aK=i("Signing passphrase: ",96,true)
if not aK or aK==""then local aQ,aP=pcall(require,U)
E(string.format("Aborted. A signing passphrase is required (%d+ characters).",
aQ and aP and aP.KDF_MIN_PASS or 20),d.dim)
E("It IS the private key — the same passphrase always produces the",d.dim)
E("same key, on any machine, so make it long and keep it.",d.dim)return end
local aL,aM=aC.signPackage(aB[2],aK,{session=K.sessionOf(a),signer=aJ})if not aL then
E("Signing failed: "..tostring(aM),d.error)return end
E("Signed. Wrote "..tostring(aM),d.highlight)E("public key "..aL,d.fg)local aO,aN=pcall(require,U)if
aO and aN then
E("fingerprint "..aN.fingerprint(aL),d.dim)end elseif aD=="repo"or aD=="repos"then
local aJ=(aB[2]or"list"):lower()
if aJ=="list"then local aK=aC.repos()
if#aK==0 then
E("No remote repositories configured.",d.dim)
E("Add one:  pkg repo add <name> <https://host/path>",d.dim)
E("The URL is the directory holding the repo's programs.cfg.",d.dim)else local aM=14
for aP,aO in ipairs(aK)do aM=math.max(aM,#aO.name)end;local aN=" %-"..aM.."s %s"
E(string.format(aN,"name","url"),d.title)
for aP,aO in ipairs(aK)do
E(string.format(aN,aO.name,aO.url),d.fg)if aO.description then
E(string.rep(" ",aM+2)..aO.description,d.dim)end end;E("",d.dim)
E("This list is the allowlist: what these serve installs like a disk.",d.dim)end;local aL=aC.knownRepos()
if#aL>0 then E("",d.dim)
E("Known (named by installed packages; not trusted):",d.title)
for aN,aM in ipairs(aL)do
E(string.format(" %2d %s",aN,aM.url),d.fg)if#aM.from>0 then
E("      from "..table.concat(aM.from,", "),d.dim)end end
E("Read only for what configured repos lack (pkg trust",d.dim)
E("discovered). Forget:  pkg repo forget <number|url|all>",d.dim)end elseif aJ=="add"then
if not aB[3]or not aB[4]then
E("Usage: pkg repo add <name> <url> [description]",d.dim)
E("  url = the directory containing programs.cfg",d.dim)return end
local aK=#aB>=5 and table.concat(aB," ",5)or nil
local aL,aM=aC.addRepo(aB[3],aB[4],aK,{session=K.sessionOf(a)})
if aL then
E("Repo '"..aB[3].."' added.",d.highlight)
E("It is now an accepted source of executable code for this",d.warning)
E("machine. 'pkg repo remove "..aB[3].."' undoes that.",d.warning)else E(tostring(aM),d.error)end elseif aJ==ad or aJ=="rm"then if not aB[3]then
E("Usage: pkg repo remove <name>",d.dim)return end
local aK,aL=aC.removeRepo(aB[3],{session=K.sessionOf(a)})
if aK then
E("Repo '"..aB[3].."' removed.",d.highlight)else E(tostring(aL),d.error)end elseif aJ=="forget"then if not aB[3]then
E("Usage: pkg repo forget <number|url|all>",d.dim)return end
local aL,aK=aC.forgetRepo(aB[3],{session=K.sessionOf(a)})
if aL then
E(("Forgot %d known repo(s)."):format(aK or 0),d.highlight)else E(tostring(aK),d.error)end else
E("Usage: pkg repo [list|add <name> <url>|remove <name>|forget <n|url|all>]",d.dim)end elseif aD=="remote"then local aJ=_G._TOS and _G._TOS.internet
if aJ and not
aJ.available()then
E(aJ.status().reason or"internet is not available",d.warning)E("'internet' shows the details.",d.dim)return end;E("Contacting configured repositories...",d.dim)
local aK=aC.searchRemote({refresh=
aB[2]=="--refresh"})if#aK==0 then
E("Nothing available. Check 'pkg repo list'.",d.dim)return end
E(string.format(" %-22s %-10s %s","name",as,"repo"),d.title)
for aM,aL in ipairs(aK)do
E(string.format(" %-22s %-10s %s",(aL.name or"?"):sub(1,22),(
aL.version or"-"):sub(1,10),tostring(aL.repo)),d.fg)if aL.description then
E("   "..tostring(aL.description):sub(1,60),d.dim)end end;E("",d.dim)
E("Install one with:  pkg fetch <name>",d.dim)elseif aD=="fetch"then if aE({[Q]=true,[P]=true},"--allow-unverified --allow-unsigned")then
return end;local aK,aL,aM=nil,false,false
for aP=2,#aB do
local aQ=tostring(aB[aP])if aQ==Q then aL=true elseif aQ==P then aM=true elseif not aK then aK=aQ end end
if not aK then
E("Usage: pkg fetch <name> [--allow-unverified] [--allow-unsigned]",d.dim)
E("Downloads from a configured repo, then installs it.",d.dim)return end;E("Fetching '"..aK.."'...",d.dim)
local function aN(aP)if
not(s and i)then return nil end
local aR="'"..
tostring(aP.name)..
"' is only in a repo this machine was not "..
"configured with:\n  "..

tostring(aP.repo)..
"\n"..
(
aP.by and(tostring(aP.by).." requires it.\n")or"")..

"\nIts signature is valid, but its key is not trusted here:\n  key "..
tostring(aP.fingerprint)..
"\n"..

(aP.signer and
('It calls its publisher "'..tostring(aP.signer)..
'" -- its own word, not proof.\n')or"")..
"\nCompare the fingerprint with the publisher somewhere that is NOT this repo. ".."Trusted, anything signed with this key installs from now on."
if not
s(aR,"trust",{title="A new publisher key",style="warning",yes="Trust",no="Refuse"})then
E("Refused the key "..

tostring(aP.fingerprint).." for '"..tostring(aP.name).."'.",d.dim)return nil end;local aQ=i("Name this publisher (Enter refuses): ",48)if aQ and
aQ~=""then
E("Trusted the key "..
tostring(aP.fingerprint).." as '"..aQ.."' (from "..
tostring(aP.repo)..").",d.highlight)end;return aQ end
local aO,aJ=aC.installRemote(aK,{session=K.sessionOf(a),allowUnverified=aL,allowUnsigned=aM,confirmKey=aN})
if aO then
local aP=aJ and aJ.discovered and
(tostring(aJ.discovered)..", a repo nobody configured")or("repo '"..
tostring(aJ and aJ.repo).."'")
E(string.format("Installed '%s' from %s (%d files, %d bytes).",aK,aP,(aJ and aJ.files)or 0,
(aJ and aJ.bytes)or 0),d.highlight)local c=aJ and aJ.dependencies;if type(c)=="table"and#c>0 then
E(
"  ...and what it requires: "..table.concat(c,", "),d.highlight)end else
E(tostring(aJ),d.error)
if tostring(aJ):find("hash",1,true)or
tostring(aJ):find("unverified",1,true)then E("",d.dim)
E("That repo ships no file hashes, so TOS cannot check what it",d.dim)
E("sent. Re-run with --allow-unverified if you trust it.",d.dim)end end elseif aD=="outdated"or aD=="updates"then local aJ=aC.outdated()
if#aJ==0 then
E("Everything is up to date, against what's mounted and the repos you added.",d.highlight)
E("Insert another disk and re-run to check against it too.",d.dim)return end
E(string.format(" %-20s %-10s %-10s %s","name","installed","available","from"),d.title)
for aL,aK in ipairs(aJ)do
E(string.format(" %-20s %-10s %-10s %s",aK.name:sub(1,20),tostring(aK.from):sub(1,10),tostring(aK.to):sub(1,10),
aK.remote and("repo "..tostring(aK.repo))or tostring(
aK.root or"?")),d.fg)end;E("",d.dim)
E("pkg upgrade <name>   or   pkg upgrade --all --yes",d.dim)elseif aD=="upgrade"then
if
aE({["--all"]=true,["--yes"]=true,[T]=true,[V]=true,[W]=true,[Q]=true,[P]=true},"--all --yes/-y --force --dry-run --allow-unverified --allow-unsigned")then return end;local aN,aO,aP,aQ=false,false,false,false;local aR,aS=false,false;local aK={}
for aT=2,#aB do
local aU=tostring(aB[aT])
if aU=="--all"then aN=true elseif aU=="--yes"or aU=="-y"then aO=true elseif aU==T then aP=true elseif
aU==V or aU==W then aQ=true elseif aU==Q then aR=true elseif aU==P then aS=true elseif aU:sub(1,2)~="--"then aK[#aK+1]=aU end end;local aJ={}
if aN then
for aU,aT in ipairs(aC.outdated())do aJ[#aJ+1]=aT end elseif#aK>0 then local aT={}
for aV,aU in ipairs(aC.outdated())do aT[aU.name]=aU end;for aV,aU in ipairs(aK)do
aJ[#aJ+1]=aT[aU]or{name=aU,from="?",to="?"}end else
E("Usage: pkg upgrade <name>… | --all [--yes] [--force] [--dry-run]",d.dim)
E("                   [--allow-unverified] [--allow-unsigned]",d.dim)
E("       pkg outdated   shows what has a newer version available",d.dim)return end
if#aJ==0 then E("Nothing to upgrade.",d.highlight)return end
if aQ then
E(string.format("Would upgrade %d package(s):",#aJ),d.title)for aU,aT in ipairs(aJ)do
E(string.format(ae,aT.name,tostring(aT.from),tostring(aT.to)),d.fg)end;E(af,d.dim)return end
if aN and not aO then
E(string.format("--all would upgrade %d package(s):",#aJ),d.warning)for aU,aT in ipairs(aJ)do
E(string.format(ae,aT.name,tostring(aT.from),tostring(aT.to)),d.fg)end
E("Add --yes to proceed.",d.dim)return end;local aL,aM=0,0
for aU,aT in ipairs(aJ)do
local aW=aT.remote and aC.upgradeRemote or aC.upgrade
local aX,aV=aW(aT.name,{session=K.sessionOf(a),force=aP,allowUnverified=aR,allowUnsigned=aS})
if aX then aL=aL+1
E(string.format(ae,aT.name,tostring(aV.from),tostring(aV.to)),d.highlight)if aV.dropped and#aV.dropped>0 then
E(string.format("      %d file(s) no longer shipped, removed",#
aV.dropped),d.dim)end
if
aV.enabled==false then E("      (was disabled; left disabled)",d.dim)end else aM=aM+1
E(string.format("  %-20s FAILED: %s",aT.name,tostring(aV)),d.error)end end
E(string.format("%d upgraded, %d failed.",aL,aM),aM>0 and d.warning or d.highlight)
if aL>0 then
E("Services keep their enabled/disabled state; restart them to run the",d.dim)
E("new code ('service stop <svc>' then 'service start <svc>').",d.dim)end elseif aD=="audit"then local aJ,aK=aB[2],aB[3]
if not aJ then
local aO=aC.audited and aC.audited()or{}if#aO==0 then E("No package is under audit.",d.fg)else
E("Under audit until reboot: "..
table.concat(aO,", "),d.warning)end
E("Usage: pkg audit <name> on|off   (root)   pkg audit <name>   (the report)",d.dim)return end
if aK=="on"or aK=="off"then
local aO,aP=aC.audit(aJ,aK=="on",{session=K.sessionOf(a)})if not aO then E(tostring(aP),d.error)return end
if
aK=="on"then
E(aJ.." runs with every auditable capability until reboot.",d.warning)
E("Use it, then read what it needed: pkg audit "..aJ,d.dim)
E("Not seen this way: the peripheral capabilities and ipc.",d.dim)else
E(aJ.." runs with what it declared again.",d.highlight)end;return end
if aK then E("Usage: pkg audit <name> on|off",d.dim)return end;local aM=aC.auditReport and aC.auditReport(aJ)if not aM then
E(aJ..
" is not under audit. Root: pkg audit "..aJ.." on",d.dim)return end;if#aM==0 then
E(aJ..
" has used nothing it did not declare, so far.",d.highlight)return end
E(string.format(" %-12s %-34s %s","needs","used","times"),d.title)local aN={}
for aP,aO in ipairs(aM)do
E(string.format(" %-12s %-34s %d",aO.cap,aO.name:sub(1,34),aO.count),d.fg)aN[aO.cap]=true end;local aL={}for aO in pairs(aN)do aL[#aL+1]=aO end;table.sort(aL)
E(
"To grant them, the manifest would declare: "..table.concat(aL,", "),d.dim)elseif aD=="info"then
if not aB[2]then E("Usage: pkg info <name>",d.dim)return end;local aJ=aC.info(aB[2])if not aJ then
E("Not installed: "..aB[2],d.error)return end
E(string.format(" name:        %s",aJ.name),d.title)
E(string.format(" version:     %s",aJ.version or"?"),d.fg)
E(string.format(" kind:        %s",aJ.kind or"?"),d.fg)
if aJ.lua or aJ.tos then
E(string.format(" needs:       %s%s%s",
aJ.lua and("Lua "..aJ.lua.."+")or"",(aJ.lua and aJ.tos)and", "or"",
aJ.tos and("TOS "..aJ.tos)or""),d.fg)end;if aJ.category then
E(string.format(" category:    %s",aJ.category),d.fg)end;if aJ.description then
E(string.format(" description: %s",aJ.description),d.fg)end;if aJ.author then
E(string.format(" author:      %s",aJ.author),d.fg)end
E(string.format(" status:      %s",
aC.isEnabled(aJ.name)and"enabled"or am),
aC.isEnabled(aJ.name)and d.highlight or d.dim)
if type(aJ.commands)=="table"then local aK={}for aL in pairs(aJ.commands)do
aK[#aK+1]=aL end
if#aK>0 then table.sort(aK)E(" commands:    "..
table.concat(aK,", "),d.fg)end end
if aJ.requires and#aJ.requires>0 then E(" requires:",d.fg)
for aL,aK in
ipairs(aJ.requires)do local aM,aN;if type(aK)=="table"then aM,aN=aK.name,aK.version else
aM,aN=aK:match("^(%S+)%s*(.*)$")end
E(string.format("   %s %s",aM,aN or""),d.dim)end end;if aJ.provides and#aJ.provides>0 then
E(" provides:    "..
table.concat(aJ.provides,", "),d.fg)end;if aJ.recommends and
#aJ.recommends>0 then
E(" recommends:  "..table.concat(aJ.recommends,", "),d.dim)end;if aJ.conflicts and
#aJ.conflicts>0 then
E(" conflicts:   "..table.concat(aJ.conflicts,", "),d.warning)end
if aJ.origin=="openos"then
E(" origin:      OpenOS/OPPM package (runs on the compat layer)",d.warning)if aJ.capsFromCompat then
E("              declared no capabilities — granted: "..
table.concat(aJ.capabilities or{},", "),d.warning)end end
do local n=aJ._sigState or"unsigned"
if n=="trusted"then
E(string.format(" signature:   signed by trusted publisher '%s'",tostring(aJ._sigLabel)),d.highlight)elseif n=="unknown"then
E(" signature:   valid, but the key was not trusted at install time",d.warning)else E(" signature:   none (unsigned)",d.dim)end
if aJ._sigKey then local aL,aK=pcall(require,U)
local aM=
(aL and aK and aK.fingerprint)and aK.fingerprint(aJ._sigKey)or
aJ._sigKey:sub(1,16)E("              key "..aM,d.dim)end
E(string.format(" integrity:   %s",
aJ._unverified and"NOT verified (installed with --allow-unverified)"or"all files matched their declared hashes"),
aJ._unverified and d.warning or d.dim)end elseif aD==ao or aD=="install-dir"or aD=="from-floppy"or aD==
"fromfloppy"then
if
aE({[Q]=true,[P]=true,[T]=true,["--all"]=true,["--yes"]=true,[V]=true,[W]=true,["--key"]="value",["--prompts"]=true,["--classic"]=true},
"--all --yes/-y --dry-run --force --allow-unverified --allow-unsigned ".."--key <key> --prompts")then return end;local aL,aR,aS,aO=false,false,false,false;local aM,aK=false,false;local aP={}
for aU=2,#aB do
local aV=tostring(aB[aU])
if aV==Q then aL=true elseif aV==P then aM=true elseif aV==T then aK=true elseif aV=="--all"then aR=true elseif
aV=="--yes"or aV=="-y"then aS=true elseif aV==V or aV==W then aO=true elseif aV=="--key"then elseif aB[aU-1]=="--key"then elseif
aV:sub(1,2)~="--"then aP[#aP+1]=aV end end;local aN=aP[1]local function aT(aU)return
type(aU)==M and aU:find("/",1,true)~=nil end;local aJ
if aR then aJ="all"elseif aD==
"install-dir"then aJ="dir"elseif aD=="from-floppy"or aD=="fromfloppy"then aJ=an elseif not aN then
aJ=an elseif aT(aN)then aJ="dir"elseif#aP>1 then aJ="many"else aJ="name"end
local function aQ(aU)
if#aU==0 then E("Nothing to install.",d.dim)return end
if aO then
E(string.format("Would install %d package(s):",#aU),d.title)local aX=0
for aZ,aY in ipairs(aU)do local a_,ba
if aC.planByName then a_,ba=aC.planByName(aY)end
if not a_ then E("  "..aY,d.fg)if ba then aX=aX+1
E("    would fail: "..tostring(ba),d.error)end else E("  "..aY,d.fg)local bb={}for aZ,bc in
ipairs(a_.order or{})do
bb[#bb+1]=(aC.info and aC.info(bc))and
(bc.." (installed)")or bc end
if#bb>1 then E("    order: "..
table.concat(bb,", "),d.dim)end;for aZ,bc in ipairs(a_.contradictions or{})do
E("    ! "..tostring(bc.text),d.warning)end
if#
(a_.contradictions or{})>0 then
if aK then
E("    --force: would install past "..
#a_.contradictions.." contradiction(s)",d.warning)else aX=aX+1
E("    would be refused (--force overrides)",d.error)end end end end;if aX>0 then
E(string.format("%d of %d would not install as things stand.",aX,#aU),d.warning)end;E(af,d.dim)return end;local aW,aV=0,0
for aY,aX in ipairs(aU)do
local a_,aZ=aC.installByName(aX,{session=K.sessionOf(a),allowUnverified=aL,allowUnsigned=aM,force=aK})
if a_ then aW=aW+1
E(string.format("  %-20s installed%s",aX,
(#aZ.skipped>0)and(" (deps present: "..
table.concat(aZ.skipped,", ")..")")or""),d.highlight)else aV=aV+1
E(string.format("  %-20s FAILED: %s",aX,tostring(aZ)),d.error)end end
E(string.format("%d installed, %d failed.",aW,aV),aV>0 and d.warning or d.highlight)end
if aO and(aJ=="name"or aJ=="dir")then aQ({aN})return elseif aO and
aJ==an then local aU={}for aW,aV in ipairs(aC.listAllAvailable()or{})do
if not(aC.info and
aC.info(aV.name))then aU[#aU+1]=aV.name end end
table.sort(aU)
if#aU==0 then E("Nothing to install.",d.dim)return end
E(string.format("Would offer %d package(s) to choose from:",#aU),d.title)for aW,aV in ipairs(aU)do E("  "..aV,d.fg)end;E(af,d.dim)
return end
if aJ=="all"then
if not(aS or aO)then
E("--all installs EVERY package on every inserted disk and repo.",d.warning)
E("Add --yes to confirm, or --dry-run to see the list first.",d.dim)return end;local aU={}for aW,aV in ipairs(aC.listAllAvailable()or{})do
if not(aC.info and
aC.info(aV.name))then aU[#aU+1]=aV.name end end
table.sort(aU)aQ(aU)return elseif aJ=="many"then aQ(aP)return end
if aJ=="name"then local aV;for aX=3,#aB do
if aB[aX]=="--key"and aB[aX+1]then aV=aB[aX+1]end end
local aW,aU=aC.installByName(aN,{licenseKey=aV,session=K.sessionOf(a),allowUnverified=aL,allowUnsigned=aM,force=aK})
if aW then
E(string.format("Installed: %s",table.concat(aU.installed,", ")),d.highlight)aF(aU.installed)if#aU.skipped>0 then
E(string.format("Skipped (already present): %s",table.concat(aU.skipped,", ")),d.dim)end else
E("Install failed: "..tostring(aU),d.error)w(aU,E,"Installing packages")end elseif aJ=="dir"then
if not aN then E("Usage: pkg install <dir>",d.dim)return end;local aV=aG()
local aW,aU=aC.install(aN,{session=K.sessionOf(a),allowUnverified=aL,allowUnsigned=aM,force=aK})
if aW then local aX={}
for aY in pairs(aG())do if not aV[aY]then aX[#aX+1]=aY end end;table.sort(aX)
E("Installed: "..
(#aX>0 and
(table.concat(aX,", ").." (")or"")..
tostring(aU).. (#aX>0 and")"or""),d.highlight)aF(aX)else
E("Install failed: "..tostring(aU),d.error)w(aU,E,"Installing packages")end else local aV=false;for aY=2,#aB do if aB[aY]=="--prompts"or aB[aY]=="--classic"then
aV=true end end
local aW=false
if not aV and aC.runInstaller then
local aZ,aY=aC.runInstaller({session=K.sessionOf(a),allowUnverified=aL,allowUnsigned=aM,force=aK})
if aZ then aW=true
if a.D and a.D.invalidate then pcall(a.D.invalidate)end;if c.drawAll then pcall(c.drawAll)end elseif aY then
E("Menu installer unavailable ("..tostring(aY)..
") — using prompts.",d.dim)end end;if aW then return end
local aX,aU=aC.installFromFloppy({session=K.sessionOf(a),allowUnverified=aL,allowUnsigned=aM,force=aK,confirm=function(ba,a_,aZ,aY)
if r then
local be={title="Install from media",severity=ao,yes="Install",no="Skip",progress=
(aZ and aY and aY>1)and{index=aZ,total=aY}or nil}if aZ and aY and aZ<aY then be.redraw=false end;return
r("Install  "..ba.."?".."\n\n".."From:"..
"\n  "..a_,be)end;if not i then return false end
local bc=a_:match("^(/mnt/[^/]+)")or a_;local bd=
(aZ and aY and aY>1)and string.format(" (%d/%d)",aZ,aY)or""local bb=
i("Install "..ba..
" from "..bc..bd.."? [y/N]: ",4)or""return
bb:lower()=="y"or bb:lower()=="yes"end})
if aX then if#aU.installed>0 then
E(string.format("Installed from media: %s",table.concat(aU.installed,", ")),d.highlight)end;if
#aU.skipped>0 then
E(string.format("Skipped: %s",table.concat(aU.skipped,", ")),d.dim)end;if#aU.installed==0 and
#aU.skipped==0 then
E("No packages found on mounted media. Insert a package disk and retry.",d.dim)end else E("Media scan failed: "..
tostring(aU),d.error)end end elseif aD=="license-hash"then if not aB[2]or not aB[3]then
E("Usage: pkg license-hash <package-name> <license-key>",d.dim)return end
local aJ,aK=aC.computeLicenseHash(aB[2],aB[3])
if aJ then E(aJ,d.fg)else E(ah..tostring(aK),d.error)end elseif aD=="uninstall"or aD==ad then if not aB[2]then
E("Usage: pkg uninstall <name>",d.dim)return end
local aJ,aK=aC.uninstall(aB[2],{session=K.sessionOf(a)})if aJ then E("Uninstalled: "..aB[2],d.highlight)else
E(
"Uninstall failed: "..tostring(aK),d.error)end elseif aD=="make-disk"or
aD=="export-disk"then
if not aB[2]then
E("Usage: pkg make-disk <mount> [name ...]",d.dim)
E("  Builds an Optional Utilities disk from your INSTALLED add-ons so",d.dim)
E("  you can install them on another TOS machine without a dev box.",d.dim)
E("  Name args limit the export; omit to include every add-on.",d.dim)E("  e.g. pkg make-disk /mnt/floppy",d.dim)return end;if not aC.exportDisk then
E("This TOS build has no make-disk support.",d.error)return end;local aK=nil;if aB[3]then aK={}for aM=3,#aB do
aK[#aK+1]=aB[aM]end end
local aL,aJ=aC.exportDisk(aB[2],{only=aK,session=K.sessionOf(a)})
if aL then
E(string.format("Built add-on disk on %s: %d package(s), %d file(s)",aJ.target,#aJ.packages,aJ.files),d.highlight)if#aJ.packages>0 then
E("  "..table.concat(aJ.packages,", "),d.fg)end;if#aJ.problems>0 then
E("  Warnings:",d.warning)
for aN,aM in ipairs(aJ.problems)do E("   ! "..aM,d.warning)end end
E("On the target machine, insert the disk and run 'pkg install'.",d.dim)else
E("make-disk failed: "..tostring(aJ),d.error)end elseif aD==Z or aD=="expand"then
if not aB[2]then
E("Usage: pkg "..
aD.." <name>".. (
aD==Z and" | pkg compact --all"or""),d.dim)local o=package.loaded["kernel.pkgfs"]if
o and#o.list()>0 then
E("Compact now: "..table.concat(o.list(),", "),d.dim)end;return end;local aJ={aB[2]}
if aD==Z and aB[2]=="--all"then aJ={}for aM,aL in
ipairs(aC.list()or{})do aJ[#aJ+1]=aL.name end end;local aK=0
for aM,aL in ipairs(aJ)do
local aP=aD==Z and aC.compact or aC.expand;local aO,aN=aP(aL,{session=K.sessionOf(a)})
if aO and
aD=="expand"then E("Expanded: "..aL,d.highlight)elseif aO then
local aQ=aN.before-aN.after;aK=aK+aQ
E(string.format("Compact: %s, %d files, %.1f KB -> %.1f KB%s",aL,aN.files,aN.before/1024,aN.after/1024,
aN.packed and"  (needs this data card to read)"or""),d.highlight)else
E(aL..": "..tostring(aN),#aJ>1 and d.dim or d.error)end end;if#aJ>1 then
E(string.format("Saved %.1f KB.",aK/1024),d.highlight)end elseif aD=="enable"or aD=="disable"then if not
aB[2]then
E("Usage: pkg "..aD.." <name>",d.dim)return end;local aJ=(aD=="enable")
local aK,aL=aC.setEnabled(aB[2],aJ,{session=K.sessionOf(a)})
if aK then
E((aJ and"Enabled: "or"Disabled: ")..aB[2],d.highlight)else E("Failed: "..tostring(aL),d.error)end elseif aD=="commands"then local aK=aC.commands()local aJ={}
for aL in pairs(aK)do aJ[#aJ+1]=aL end;if#aJ==0 then
E("No commands provided by installed packages.",d.dim)return end;table.sort(aJ)
E("Commands provided by packages:",d.title)for aM,aL in ipairs(aJ)do E("  "..aL,d.fg)end else
E("Usage: pkg [list | search | info <name> | install [name|dir] | uninstall <name>",d.dim)
E("           | enable <name> | disable <name> | commands | make-disk <mnt>]",d.dim)
E("  install: a name installs by name; a path installs that dir; no arg",d.dim)
E("           scans mounted media. Shortcuts: 'install <name>', 'uninstall <name>'.",d.dim)
E("  signing: trust [list|add|remove|require|key] · verify-sig <dir> · sign <dir>",d.dim)end end
b.install=function(E,aB)local aC={ao}for aD=1,# (E or{})do aC[#aC+1]=E[aD]end;return
b.pkg(aC,aB)end
b.uninstall=function(E,aB)local aC={"uninstall"}
for aD=1,# (E or{})do aC[#aC+1]=E[aD]end;return b.pkg(aC,aB)end
b.backup=function(aB,E)if not f(E)then return end;local aC=_G._TOS and _G._TOS.backup
if
not aC then E("backup module unavailable",d.error)return end;local aD=aB[1]local aE=K.sessionOf(a)
if aD=="snapshot"or aD=="create"then if not
aB[2]or not aB[3]then
E("Usage: backup snapshot <src> <dest.bak>",d.dim)return end
local aG,aF=aC.snapshot(aB[2],aB[3],{session=aE})
if aG then
E(string.format("Snapshot OK: %d entries, %d bytes -> %s",aF.entries,aF.bytes,aB[3]),d.highlight)
E("  metaHash: "..aF.hash:sub(1,16).."...",d.dim)else
E("Snapshot failed: "..tostring(aF),d.error)end elseif aD=="inspect"then if not aB[2]then
E("Usage: backup inspect <file.bak>",d.dim)return end
local aF,aG=aC.inspect(aB[2],{session=aE})if not aF then
E("Inspect failed: "..tostring(aG),d.error)return end
E(string.format(" magic:    %s",aF.magic),d.fg)
E(string.format(" created:  %s",aF.created>978307200 and
os.date("%Y-%m-%d %H:%M:%S UTC",aF.created)or tostring(aF.created)),d.fg)
E(string.format(" entries:  %d",aF.entries),d.fg)
E(string.format(" root:     %s",aF.root),d.fg)
E(string.format(" metaHash: %s...",aF.metaHash:sub(1,24)),d.fg)
E(string.format(" size:     %d bytes",aF.size),d.fg)elseif aD=="restore"then if not aB[2]then
E("Usage: backup restore <file.bak> [destRoot] [--force]",d.dim)return end;local aG,aH=nil,false
for aJ=3,#aB do if
aB[aJ]==T or aB[aJ]=="-f"then aH=true else aG=aB[aJ]end end
local aI,aF=aC.restore(aB[2],{session=aE,destRoot=aG,force=aH})
if aI then
E(string.format("Restore OK: %d/%d files -> %s",aF.restored,aF.entries,aF.destRoot),d.highlight)H()else
E("Restore failed: "..tostring(aF),d.error)end else
E("Usage: backup [snapshot|inspect|restore] ...",d.dim)E("  backup snapshot <src> <dest.bak>",d.dim)
E("  backup inspect  <file.bak>",d.dim)
E("  backup restore  <file.bak> [destRoot] [--force]",d.dim)end end
b.kiosk=function(aB,E)if not f(E)then return end
local aD,aC=K.requireRoomy(a,"shell.kiosk","admin")if not aD or not aC then
E(K.loadFailure("kiosk",aC),d.error)return end
E("Kiosk = the LOCKED, guest-facing menu (allow-list + read-only).",d.title)
E("To test: log out, log in as the 'kiosk' user.",d.dim)E("Config: /etc/kiosk.cfg",d.dim)E("",d.fg)
E("Looking for the OPERATOR menu? Run 'desktop': the same kind of",d.highlight)
E("clickable menu, but it runs real commands at YOUR tier (no allow-list).",d.dim)end
b.doctor=function(aB,E)local aE,aD=K.requireRoomy(a,"kernel.diag","admin")if not aE or
not aD then E(K.loadFailure("doctor",aD),d.error)
return end
local aF={ok=d.highlight or d.fg,info=d.dim or d.fg,warn=d.warning or d.fg,err=
d.error or d.fg}local aG=aB[1]
E("=== TOS doctor \226\128\148 runtime health ===",d.title)
local aC=aD.run(function(aJ,aK)E(aJ,aF[aK]or d.fg)end,{only=aG})E("",d.dim)
local aH=string.format("Summary: %d ok, %d info, %d warn, %d err",aC.ok,aC.info,aC.warn,aC.err)local aI=aC.err>0 and d.error or aC.warn>0 and d.warning or
d.highlight
E(aH,aI)
E("This checks RUNTIME health. For a full file-integrity check, run 'verify'.",d.dim)
E("'srm' runs both, plus the known-good baseline check.",d.dim)end;b.diag=b.doctor
b.srm=function(aB,E)
local aJ,aD=K.requireRoomy(a,"kernel.srm","admin")if not aJ or not aD then
E(K.loadFailure("srm",aD),d.error)return end
local aG={ok=d.highlight or d.fg,info=d.dim or d.fg,warn=d.warning or d.fg,err=
d.error or d.fg}local function aF(aK)
for aM,aL in ipairs(aK.findings)do E(aL.text,aG[aL.sev]or d.fg)end;return aK end
local function aH(aK)local aL=aK.counts
E("",d.dim)
E(string.format("%d ok, %d info, %d warn, %d err%s",aL.ok,aL.info,aL.warn,aL.err,(aK.fixed or 0)>0 and(
"  |  "..aK.fixed.." fixed")or""),
aG[aD.worst(aK)]or d.fg)end;local aE,aC,aI=aD.parseArgs(aB)if aC.source==true then
E("--source needs a mount point, e.g. --source /mnt/floppy",d.error)return end
if aE==O then
E("=== SRM \226\128\148 System Repair & Maintenance ===",d.title)aH(aF(aD.status()))E("",d.dim)
E("scan = compare files to the baseline   health = runtime   verify = manifest",d.dim)
E("repair = fix what is safe             baseline = record a known-good system",d.dim)elseif aE=="health"then return b.doctor(aI,E)elseif aE=="verify"then return b.verify(aI,E)elseif
aE=="scan"then
E("=== SRM scan \226\128\148 files vs the known-good baseline ===",d.title)
E("Hashing every baselined file; this takes a moment.",d.dim)aH(aF(aD.scan()))elseif aE=="baseline"then if not f(E)then return end
E("Recording what THIS system looks like right now as the known-good",d.title)
E("baseline. Only do that on a system you trust — a fresh install, or",d.dim)
E("one that just passed 'srm verify'. Anything already wrong becomes",d.dim)E("the new definition of correct.",d.dim)
E("",d.dim)local aL=aC.full and true or false
local aM,aK=aD.baseline(nil,{content=aL})if not aM then
E("Baseline failed: "..tostring(aK),d.error)return end
E(string.format("Baseline captured from %s: %d file(s) hashed.",tostring(aK.source),aK.hashed),d.highlight)
if aL then
E(string.format("  %d copy(ies) stored, %.1f KB of disk.",aK.stored,aK.bytes/1024),d.fg)
E("  Local repair is now possible: 'srm repair --restore'.",d.fg)else
E("  Hashes only — drift is detectable, but repair will need",d.fg)
E("  '--source <mount>' (e.g. the install floppy). Use --full to",d.dim)
E("  store verified copies locally instead.",d.dim)end
if aK.skipped>0 then
E(string.format("  %d file(s) skipped (over the %d KB store cap or unreadable).",aK.skipped,aD.MAX_STORE_BYTES/1024),d.warning)end;if aK.pruned>0 then
E(string.format("  %d stale copy(ies) from the previous baseline removed.",aK.pruned),d.fg)end
for aO,aN in ipairs(aK.missing)do E(
"  MISSING at capture time: "..aN,d.warning)end elseif aE=="restore"then if not f(E)then return end
E("=== SRM restore ===",d.title)
aH(aF(aD.restore(nil,{source=type(aC.source)==M and aC.source or nil,unverified=
aC.unverified and true or false,paths=#aI>0 and aI or nil})))elseif aE==ap and aC.online then if not f(E)then return end
if aC.apply and not q(E)then return end;if aC.ref==true then
E("--ref needs a value, e.g. --ref=build-2603a5b or --ref=main",d.error)return end
local aM,aL=pcall(require,"kernel.netrepair")if not aM or not aL then
E("online repair unavailable: "..tostring(aL),d.error)return end
E("=== SRM repair --online ===",d.title)
local aK=aL.run(nil,{apply=aC.apply and true or false,unanchored=aC.unanchored and true or false,ref=
type(aC.ref)==M and aC.ref or nil})
for aO,aN in ipairs(aK.lines)do E(aN.text,aG[aN.sev]or d.fg)end;if aC.apply then E("",d.dim)
E(string.format("%d repaired, %d rejected.",aK.fixed,aK.rejected),
aK.ok and aG.ok or aG.warn)end elseif aE==ap then if not f(E)then
return end;E("=== SRM repair ===",d.title)
if not aC.restore then
E("Fixing what is mechanically safe (interrupted writes, stale state,",d.dim)
E("oversized logs). Add --restore to also put back system files that",d.dim)
E("are missing or have changed since the baseline.",d.dim)end;E("",d.dim)
aH(aF(aD.repair(nil,{restore=aC.restore and true or false,source=
type(aC.source)==M and aC.source or nil,unverified=aC.unverified and true or false})))E("",d.dim)
E("Some fixes only apply at boot: 'bootsettings repair on' runs this",d.dim)
E("pass before anything reads the files it repairs.",d.dim)elseif aE=="full"then E("=== SRM full report ===",d.title)
E("",d.dim)E("-- status --",d.title)aF(aD.status())
E("",d.dim)E("-- health --",d.title)b.doctor({},E)E("",d.dim)
E("-- integrity --",d.title)b.verify({},E)E("",d.dim)E("-- baseline --",d.title)
aH(aF(aD.scan()))else
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
b.bootsettings=function(aB,E)if not f(E)then return end
local aI,aG=pcall(require,"kernel.bootcfg")
if not aI or not aG then E("bootcfg unavailable",d.error)return end;local aH=_G._TOS and _G._TOS.fs;if not aH then
E("fs unavailable",d.error)return end;local aC=aG.load(aH)
local aE=(aB[1]or""):lower()
if aE==""or aE=="show"then
E("=== Boot Settings (/etc/boot.cfg) ===",d.title)
E("  profile    : "..aC.profile..
(aC.profile=="safe"and"   (SAFE MODE)"or"   (what loads)"),d.fg)
E("  verbosity  : ".. (aC.verbosity or"auto").."   (what it says)",d.fg)
local aL=
aC.ui=="cli"and"cli"or aC.ui=="split"and"panels (split)"or aC.ui=="home"and"panels"or
(
"auto (panels from "..aG.PANELS_MIN_KB.." KB, else cli)")
E("  interface  : "..aL.."   (all seats)",d.fg)
E("  repair     : "..
(aC.repair and"RUN on next boot"or"off"),d.fg)
E("  showConfig : ".. (aC.showConfig and"on"or"off"),d.fg)
E("  cpuTier    : "..
(aC.cpuTier and("Tier "..aC.cpuTier)or"auto"),d.fg)
E("  dataTier   : "..
(aC.dataTier and("Tier "..aC.dataTier)or"auto"),d.fg)
E("  ramGate    : "..
(aC.ramGate==nil and"auto (measure)"or
(
aC.ramGate and"always load the extras"or"never load the extras")),d.fg)local aK=false
for aO,aN in ipairs(aG.FEATURES)do
local aP=aC.advanced and aC.advanced[aN]if aP~=nil then
E("    +"..aN.." : ".. (aP and"on"or"off"),d.dim)aK=true end end
if not aK then E("    (no advanced overrides)",d.dim)end
E("Profiles: "..
table.concat(aG.PROFILE_ORDER or{"minimal","normal","full","diagnostic"}," | "),d.dim)
E("Verbosity: silent | splash | text | verbose | auto",d.dim)
E("Set: bootsettings <profile|verbosity|ui|repair|show|cputier|datatier|ramgate|"..table.concat(aG.FEATURES,"/")..
"> <value>",d.dim)
E("DEL during boot opens the full visual editor; S = Safe Mode once.",d.dim)local aM,aJ=pcall(require,"kernel.sysinfo")
if aM and aJ then E("",d.dim)
for aO,aN in
ipairs(aJ.rows(aJ.gather(
nil,{cpuTier=aC.cpuTier,dataTier=aC.dataTier})))do if aN.role=="section"then E(aN.value..":",d.title)else
E("  ".. (aN.label~=""and(
aN.label..": ")or"")..
aN.value,d.dim)end end end;return end;local aD=(aB[2]or""):lower()local aF=false
if aE=="profile"then
if
aG.PROFILES[aD]then aC.profile=aD;aF=true else
E("profiles: "..table.concat(aG.PROFILE_ORDER or
{"minimal","normal","full","diagnostic"}," "),d.error)return end elseif aE=="verbosity"then
if aD=="auto"then aC.verbosity=nil;aF=true else local aJ=false;for aL,aK in
ipairs(aG.VERBOSITY)do if aK==aD then aJ=true end end;if aJ then aC.verbosity=aD
aF=true else
E("verbosity: silent splash text verbose (or auto)",d.error)return end end elseif aE=="show"or aE=="showconfig"then aC.showConfig=(aD=="on"or aD=="true"or
aD=="1")aF=true elseif aE=="cputier"or aE==
"cpu"then
if aD=="auto"then aC.cpuTier=nil;aF=true elseif
aD=="1"or aD=="2"or aD=="3"then aC.cpuTier=tonumber(aD)aF=true else
E("cputier: auto | 1 | 2 | 3",d.error)return end elseif aE=="datatier"or aE=="data"then
if aD=="auto"then aC.dataTier=nil;aF=true elseif aD=="1"or
aD=="2"or aD=="3"then aC.dataTier=tonumber(aD)aF=true else
E("datatier: auto | 1 | 2 | 3",d.error)return end elseif aE=="ui"or aE=="interface"then
if
aD=="panels"or aD=="tui"or aD=="home"then aC.ui="home"aF=true elseif aD=="cli"or aD=="split"then aC.ui=aD;aF=true elseif aD=="auto"then aC.ui=
nil;aF=true else
E("ui: auto (by memory) | panels | split | cli",d.error)return end elseif aE==ap then
if aD=="on"or aD=="once"or aD=="1"then aC.repair=true;aF=true elseif aD==
"off"or aD=="0"then aC.repair=false;aF=true else
E("repair: on (runs once next boot, then clears) | off",d.error)return end elseif aE=="ramgate"or aE=="ram"then
if aD=="auto"then aC.ramGate=nil;aF=true elseif aD=="always"or aD==
"plenty"or aD=="on"then aC.ramGate=true;aF=true elseif
aD=="never"or aD=="tight"or aD=="off"then aC.ramGate=false;aF=true else
E("ramgate: auto (measure free RAM) | always | never  (load the optional extras)",d.error)return end elseif aE=="reset"then aC=aG._normalize({})aF=true else local aJ=false;for aL,aK in ipairs(aG.FEATURES)do if
aK==aE then aJ=true end end
if aJ then
aC.advanced=aC.advanced or{}
if aD=="auto"then aC.advanced[aE]=nil elseif aD=="on"then aC.advanced[aE]=true elseif
aD=="off"then aC.advanced[aE]=false else
E(aE..": auto | on | off",d.error)return end;aF=true else
E("Unknown setting: "..aE.." (try: bootsettings show)",d.error)return end end
if aF then local aJ,aK=aG.save(aH,aC)if aJ then
E("Saved. Applies on next boot (reboot to apply now).",d.highlight)else
E("Save failed: "..tostring(aK),d.error)end end end
local function B()local aC,E=pcall(require,"kernel.bootcfg")
local aB=_G._TOS and _G._TOS.fs;if aC and E and aB then return E,aB end end
local function C(aB,E)local aC=h.getSwap and h.getSwap()
if aB=="now"then
local aJ,aI=pcall(require,ar)if not aJ or not aI.sweepCold then
E("tab paging unavailable",d.error)return end;if not aC then
E("Swap not available",d.error)return end;local aK=aI.sweepCold(a,true)
local aL,aM=aI.pagedStats(a)
E(string.format("Paged out %d view tab(s) now.",aK),d.highlight)
E(string.format("%d tab(s) on disk, %d lines held there.",aL,aM),d.dim)
E("They page back transparently the next time you open them.",d.dim)return end
if aB==""or aB==O or aB=="keys"or aB=="clear"then if not aC then
E("Swap not available",d.error)return end
if aB=="clear"then if not f(E)then return end
local aL,aK=pcall(require,ar)
if aL and aK.isPaged then for aN,aM in ipairs(a.tabs or{})do
if aK.isPaged(aM)then local aN=aM.content end end end;aC.clear()E("Swap cleared.",d.highlight)return end;local aI=aC.usage()
local aJ=(aI.max and aI.max>0)and math.floor(aI.bytes*100/
aI.max)or 0;E("=== Disk Swap (/var/swap) ===",d.title)
E(string.format("Used:    %s / %s (%d%%)",t(aI.bytes),t(aI.max),aJ),
aJ>90 and d.warning or d.fg)
E(string.format("Entries: %d",aI.count),d.dim)if aB=="keys"and aC.keys then local aK=aC.keys()
if#aK==0 then
E("(no keys)",d.dim)else for aM,aL in ipairs(aK)do E("  "..aL,d.dim)end end end
do
local aN,aL=pcall(require,ar)if aN and aL.pagedStats then local aO,aP=aL.pagedStats(a)
E(string.format("View tabs paged: %d (%d lines)",aO,aP),
aO>0 and d.highlight or d.dim)end;local aM,aK=25,(
h.getConfig and h.getConfig())if
aK and aK.get then
aM=tonumber(aK.get("swapPressurePct"))or 25 end
E(string.format("Cold view buffers page out below %d%% free RAM"..
"  (swapPressurePct)",aM),d.dim)end
E("Volatile: cleared on every boot. 'swap clear' wipes now.",d.dim)
E("'swap now' pages cold tabs immediately (ignores pressure).",d.dim)
E("Paging spends disk writes to save RAM — see 'optimize power'.",d.dim)return end;if not f(E)then return end;local aE,aF=B()if not aE then
E("bootcfg/fs unavailable",d.error)return end;local aD=aE.load(aF)
aD.advanced=aD.advanced or{}
if aB=="auto"then aD.advanced.swap=nil elseif aB=="on"then aD.advanced.swap=true elseif
aB=="off"then aD.advanced.swap=false else
E("swap <status|keys|now|clear|on|off|auto>",d.error)return end;local aG,aH=aE.save(aF,aD)if aG then
E("Disk swap set "..aB..". Applies on next boot.",d.highlight)else
E("Save failed: "..tostring(aH),d.error)end end
local function J(aB,aC,E)local aJ,aD=pcall(require,"kernel.power")
if
not aJ or type(aD)~="table"or not aD.PROFILES then
E("Power control unavailable: "..tostring(aD),d.error)
E("TOS behaves as profile 'off' — nothing is being conserved.",d.dim)return end;local aI,aF=pcall(require,"kernel.screen")
local aG=h.getConfig and h.getConfig()
if aB==""or aB=="show"or aB==O then local aO=aD.profile()
E("=== Power ===",d.title)local aP,aL,aM=pcall(aD.energy)
if
aP and type(aL)==ac and type(aM)==ac and aM>0 then
local aU=math.floor(aL*100/aM+0.5)
E(string.format("  Stored     %d / %d  (%d%%)",math.floor(aL),math.floor(aM),aU),
aU<25 and d.warning or d.fg)local aS=a._pwrSample
local aT=aS and aS.t and(h.uptime()-aS.t)or 0
if aT>=1 then local aV=(aS.e-aL)/aT
if aV>0.05 then
E(string.format("  Draw       %.1f/s over the last %ds",aV,math.floor(aT)),d.fg)if aL>0 then
E(string.format("             ~%d s of buffer left at that rate",math.floor(aL/aV)),d.dim)end elseif aV<-0.05 then
E(string.format("  Draw       charging (+%.1f/s)",
-aV),d.highlight)else
E(string.format("  Draw       level over the last %ds — supply is keeping up",math.floor(aT)),d.fg)end else
E("  Draw       run 'optimize power' again in a few seconds for a rate",d.dim)end;a._pwrSample={t=h.uptime(),e=aL}else
E("  Stored     (this machine reports no energy buffer)",d.dim)end;E("",d.dim)E("  Profile    "..aO,d.highlight)
local aQ,aN=aD.idleSeconds(),aD.blankSeconds()
E(string.format("  Idle clock every %ds",aQ),d.fg)
E("    a status-bar repaint is a GPU write, which OC bills per cell",d.dim)
E("  Screen blank "..
(aN>0 and("after "..aN.."s idle")or"never"),d.fg)
E("    OC bills a screen per tick per NON-BLANK cell; blank costs ~0",d.dim)local aR=(aI and aF.bufferMode and aF.bufferMode())or
"?"
E("  Display buffer "..aR,d.fg)
E("    unchanged cells skip the GPU write entirely ('optimize buffer')",d.dim)E("",d.dim)
E("optimize power <off|balanced|save>   off = no conservation",d.dim)
E("optimize power blank <secs|off>      screen blank timeout",d.dim)
E("optimize power idle <secs>           idle repaint cadence",d.dim)return end
if aB=="blank"or aB=="idle"then if not f(E)then return end
local aM=
(aC=="off"or aC=="never")and 0 or tonumber(aC)local aL,aN=aD.setKnob(aB,aM)if not aL and aL~=0 then
E(tostring(aN),d.error)return end
if aB=="blank"then
E(aL>0 and
("Screen blanks after "..aL.."s idle.")or"Screen blanking off.",d.highlight)else
E("Idle repaint every "..aL.."s.",d.highlight)end
E("Profile is now custom (a named profile resets both knobs).",d.dim)return end;if not f(E)then return end;local aH,aK=aD.applyProfile(aB)if not aH then
E(tostring(aK),d.error)
E("Profiles: "..table.concat(aD.PROFILE_ORDER,", "),d.dim)return end
local aE=aD.PROFILES[aH]
if aI and aF.setBuffer then pcall(aF.setBuffer,aE.buffer)end
if aG and aG.set then aG.set("powerProfile",aH)local aL=pcall(aG.save)if
not aL then
E("(profile applied, but /etc/tos.cfg could not be saved)",d.warning)end end;E("Power profile: "..aH,d.highlight)
E(string.format("  idle repaint %ds · screen blank %s · display buffer %s",aE.idleSec,
aE.blankSec>0 and(aE.blankSec.."s")or"never",aE.buffer),d.dim)
E("Applies now, on every seat, and persists across reboots.",d.dim)end
b.swap=function(E,aB)return C((E[1]or""):lower(),aB)end
b.optimize=function(aB,E)local aC=(aB[1]or""):lower()
local aE=(aB[2]or""):lower()local aF,aD=pcall(require,"kernel.screen")
if aC==""or aC=="show"or
aC==O then E("=== Optimizations ===",d.title)
local aH="auto (profile)"local aI,aJ=B()
if aI and aJ then local aM=aI.load(aJ)
local aN=aM.advanced and aM.advanced.swap;if aN~=nil then aH=aN and"on"or"off"end end;local aG=h.getSwap and h.getSwap()local aK="inactive"
if aG then
local aM=aG.usage()
local aN=(aM.max and aM.max>0)and
math.floor(aM.bytes*100/aM.max)or 0
aK=string.format("active %s/%s (%d%%)",t(aM.bytes),t(aM.max),aN)end
E(string.format("  Disk swap      %-14s [%s]",aH,aK),aG and d.fg or d.dim)
E("    extends usable memory onto /var/swap (boot feature)",d.dim)local aL=(aF and aD.bufferMode and aD.bufferMode())or
"?"
E(string.format("  Display buffer %-14s",aL),d.fg)
E("    skips GPU writes for unchanged cells (auto = memory-gated)",d.dim)
if aF and aD.bufferStats then local n=aD.bufferStats()
if n.total>0 then
E(string.format("    this session: %d of %d cell-draws skipped (%d%%)",n.skipped,n.total,math.floor(
n.ratio*100+0.5)),
n.ratio>0 and d.highlight or d.dim)else E("    (no draws measured yet)",d.dim)end end
do local aN,aM=pcall(require,"kernel.power")
if
aN and type(aM)=="table"and aM.profile then local aO=aM.blankSeconds()
E(string.format("  Power          %-14s [idle %ds, blank %s]",aM.profile(),aM.idleSeconds(),
aO>0 and(aO.."s")or"never"),d.fg)
E("    fewer wake-ups and a blank screen are what OC bills less for",d.dim)else E("  Power          not loaded",d.dim)end end;E("",d.dim)
E("swap [status|keys|now|clear|on|off|auto]  boot toggle needs reboot",d.dim)
E("optimize power  <off|balanced|save>       conservation profile",d.dim)
E("optimize buffer <on|off|auto>             display; applies immediately",d.dim)return end;if aC=="swap"then return C(aE,E)end;if aC=="power"then return
J(aE,(aB[3]or""):lower(),E)end
if
aC=="buffer"or aC=="display"then if not f(E)then return end;if not(aF and aD.setBuffer)then
E("display buffer control unavailable",d.error)return end
local aG,aH=aD.setBuffer(aE)
if aG then
E("Display buffer set "..aE.." (applied now).",d.highlight)else E(tostring(aH)or"invalid",d.error)end;return end
E("Usage: optimize [show | power <off|balanced|save> | buffer <on|off|auto>".." | swap <on|off|auto>]",d.dim)
E("       `swap` on its own is the same as `optimize swap`.",d.dim)end
b.programs=function(aB,E)local aD={"/bin","/usr/bin","/home/"..a.who}
E("Executables:",d.title)local aC=false
for aF,aE in ipairs(aD)do
if e.isDirectory(aE)then local aH,aG=pcall(e.list,aE)
if aH and aG then
local aI={}if type(aG)=="table"then aI=aG elseif type(aG)=="function"then
for aK in aG do aI[#aI+1]=aK end end;local aJ={}for aF,aK in ipairs(aI)do if
aK:match("%.lua$")then aJ[#aJ+1]=aK end end
if#
aJ>0 then aC=true;E(" "..aE..":",d.dim)for aF,aK in ipairs(aJ)do
E("   "..aK,d.file_lua or
d.file_exec or d.highlight)end end end end end;if not aC then
E(" None yet. `help` lists the built-in commands.",d.dim)end end
b.log=function(aB,E)if not f(E)then return end;local aC=h.getLog()if not aC then
E("Logger unavailable",d.error)return end
local aD=

(aB[1]==nil)or(aB[1]=="file")or(aB[1]=="f")or(aB[1]=="all")or(tonumber(aB[1])~=nil)
if aD then local aH="/var/log/kernel.log"
local aG=tonumber(aB[1])or tonumber(aB[2])pcall(aC.flush)
if not e.exists(aH)then
E("No /var/log/kernel.log yet — showing in-memory ring.",d.dim)local aK=aC.recent(aG or 20)if#aK==0 then
E("(log is empty)",d.dim)return end
local aL={{" in-memory log ring ("..#aK.." entries)",d.title}}
for aN,aM in ipairs(aK)do local aO=d.fg;if aM.level>=3 then aO=d.error elseif aM.level>=2 then aO=d.warning elseif aM.level<1 then
aO=d.dim end
aL[#aL+1]={aC.format(aM),aO}end;z(aL,"log (ring)")return end;local aJ=e.readFile(aH)if not aJ then
E("Cannot read "..aH,d.error)return end;local aE={}for aK in aJ:gmatch("([^\n]*)\n?")do if aK~=""then
aE[#aE+1]=aK end end;local aI=
(aG and aG>0 and#aE-aG+1)or 1;if aI<1 then aI=1 end;local aF={}
aF[#aF+1]={
" /var/log/kernel.log  ("..#aE.." lines)",d.title}
for aK=aI,#aE do local aL=aE[aK]local aM=d.fg
if
aL:find("%[FTL%]")or aL:find("%[ERR%]")then aM=d.error elseif aL:find("%[WRN%]")then aM=d.warning elseif aL:find("%[DBG%]")then aM=d.dim end;aF[#aF+1]={aL,aM}end;z(aF,ab)return end
if aB[1]=="filter"then local aE,aF=aB[2],aB[3]
if not aE then
local aH={[0]="DEBUG","INFO","WARN","ERROR"}local aG=0;for aJ,aI in pairs(aC.getSourceLevels())do aG=aG+1
E(string.format("  %-12s %s+",aJ,aH[aI]or
tostring(aI)),d.fg)end;if aG==0 then
E("(no per-source filters; global level applies)",d.dim)end
E("Usage: log filter <source> <debug|info|warn|error|off>",d.dim)return end
if aF=="off"or aF=="clear"then aC.setSourceLevel(aE,nil)E(
"Filter cleared for '"..aE.."'.",d.fg)elseif aF then
local aG,aH=aC.setSourceLevel(aE,aF)
if aG then
E("Source '"..aE.."' now logs at "..aF:upper().."+.",d.fg)else E(aH or"Filter update failed",d.error)end else
E("Usage: log filter <source> <debug|info|warn|error|off>",d.dim)end;return end
if aB[1]=="clear"then pcall(aC.flush)
aC.info("log","--- ring cleared on operator request ---")
E("Ring marker recorded; old entries still on disk.",d.dim)return end
if aB[1]=="ring"or aB[1]=="r"or aB[1]=="tail"then local aF=
tonumber(aB[2])or 20;local aE=aC.recent(aF)if#aE==0 then
E("(no log entries in ring)",d.dim)return end
for aH,aG in ipairs(aE)do local aI=d.dim
if aG.level>=3 then aI=d.error elseif
aG.level>=2 then aI=d.warning elseif aG.level>=1 then aI=d.fg end;E(aC.format(aG),aI)end
E(#aE.." ring entries (use 'log' for full on-disk history)",d.dim)return end
E("Usage: log [N] | log ring [N] | log clear | log filter ...",d.dim)
E("  log        Open the full on-disk log (last N lines if given)",d.dim)
E("  log ring   Quick peek at the in-memory ring",d.dim)end
b.bg=function(E,aB)if not f(aB)then return end;if not E[1]then
aB("Usage: bg <script.lua> [args...]",d.dim)
aB("  Runs a Lua script in a background tab.",d.dim)return end
local aJ=u(E[1])local aK=K.safeModeRefusal(aJ)
if aK then aB(aK,d.error)return end;local aD=e.readFile(aJ)
if not aD then aB(ag..E[1],d.error)return end;local aM,aN=load(aD,"="..E[1],"t",v{name=E[1]})if not aM then aB(
"Compile error: "..tostring(aN),d.error)
return end;local aH={}
for aR=2,#E do aH[#aH+1]=E[aR]end;local aE=E[1]:match("[^/]+$")or E[1]
local aC=c.createTab("output","bg:"..aE,{content={
"Background task: "..aE,"PID: (starting...)",""},offset=0,pid=nil})local aQ=#c.tabs;local aF=500
local function aI(...)local aR={}for aU=1,select("#",...)do
aR[#aR+1]=tostring(select(aU,...))end;local aT=table.concat(aR,"\t")aC.content[#
aC.content+1]=aT
if#aC.content>aF then
local aU=#aC.content-aF
for aV=1,aF do aC.content[aV]=aC.content[aV+aU]end;for aV=aF+1,#aC.content do aC.content[aV]=nil end;aC.offset=math.max(0,
aC.offset-aU)end;local aS=k-3
if aC.offset>=#aC.content-aS-2 then aC.offset=math.max(0,
#aC.content-aS)end end
local aG=o.spawn("bg:"..aE,function()local aR=v{name=E[1],stdout=aI}
local aS=load(aD,"="..E[1],"t",aR)aD=nil
if aS then local aT,aU=pcall(aS,table.unpack(aH))K.reportProgramEnd(a,function(aV)
aI(aV)end,aT,aU,ah,aR)end;aI("","--- Task finished ---")end,{priority=8,source="user",tsr=true})aC.pid=aG;aC.content[2]="PID: "..aG
aB("Started background task: "..aE..
" (PID "..aG..")",d.highlight)local aO,aL=pcall(require,"shell.panels.home")local aP=(aO and aL)and
aL.cycleKeyLabel(a)or"F2"
aB(
"Switch to its tab with "..aP..", or use 'kill "..aG.."' to stop.",d.dim)end
b.run=function(aB,E)if not f(E)then return end;if not aB[1]then
E("Usage: run <file.lua>",d.dim)return end;local aD=u(aB[1])
local aE=K.safeModeRefusal(aD)if aE then E(aE,d.error)return end;local aF=e.readFile(aD)if not aF then
E(ag..aB[1],d.error)return end;local aG,aH=function(aN)E(aN,d.fg)end,nil;if
a.programIO then aG,aH=a.programIO(E)end
local aI=v{name=aB[1],stdout=aG,beforeRead=aH}local aJ,aK=load(aF,"="..aB[1],"t",aI)if not aJ then
E("Compile error: "..tostring(aK),d.error)return end;local aC={}
for aN=2,#aB do aC[#aC+1]=aB[aN]end;local aL,aM=pcall(aJ,table.unpack(aC))
K.reportProgramEnd(a,E,aL,aM,"Runtime error: ",aI)end
b.lua=function(aB,E)if not q(E)then return end
pcall(function()local aM=require(ab)if aM and aM.info then
aM.info("repl",
"REPL session opened by "..tostring(a.who or"?"))end end)local aI=N.uptime()j.fill(1,1,l,k," ",d.fg,d.bg)
j.fill(1,1,l,1," ",d.bar_fg,d.bar_bg)
j.set(1,1," Lua REPL  type 'exit' to quit",d.bar_fg,d.bar_bg)
j.set(1,1," Lua REPL  'exit' to quit | blank line runs/cancels a block",d.bar_fg,d.bar_bg)local aC=2;local aD={}
local function aF(aM,aN)if aC>k-1 then local aO=j.getGpu()if aO and aO.copy then
aO.copy(1,3,l,k-3,0,-1)end;j.fill(1,k-1,l,1," ",d.fg,d.bg)
aC=k-1 end;j.set(1,aC,tostring(aM):sub(1,l),
aN or d.fg,d.bg)aC=aC+1 end;local function aJ(aM)
return type(aM)==M and aM:find("<eof>",1,true)~=nil end;local aE={}local aG
local aK,aL=pcall(require,"shell.quitkey")local aH=false
while true do
if aC>k-1 then j.getGpu().copy(1,3,l,k-3,0,-1)j.fill(1,
k-1,l,1," ",d.fg,d.bg)aC=k-1 end;local aO=#aE>0;local aQ=aO and">> "or"> "
j.fill(1,aC,l,1," ",d.fg,d.bg)j.set(1,aC,aQ,d.highlight,d.bg)local aM=""local aN=#aD+1
local aP=#aQ+1
while true do j.fill(aP,aC,l-aP+1,1," ",d.fg,d.bg)
j.set(aP,aC,aM.."_",d.fg,d.bg)local aT,aU,aR,aS=c.pullSignal()
if aT=="key_down"then
if aK and aL.is(aR,aS,true)then
aH=true;break elseif aS==28 then break elseif aS==14 then if#aM>0 then aM=aM:sub(1,-2)end elseif aS==200 then if aN>1 then aN=aN-1;aM=
aD[aN]or""end elseif aS==208 then if aN<#aD then aN=aN+1;aM=aD[aN]or""else aN=#aD+
1;aM=""end elseif aR and aR>=32 and aR<127 then aM=aM..
string.char(aR)end elseif aT=="clipboard"and type(aR)==M then
aM=aM..aR:gsub("\r","")local aV=aM:find("\n",1,true)
if aV then aM=aM:gsub("\n"," ")end end end;aC=aC+1;if aH or
((aM=="exit"or aM=="quit")and not aO)then break end
if aM==""and not aO then elseif
aM==""and aO then aE={}aF("(cancelled)",d.dim)else aE[#aE+1]=aM
local aR=table.concat(aE,"\n")local aT,aU=load("return "..aR,"=repl","t")if not aT then
aT,aU=load(aR,"=repl","t")end;if not aT and aJ(aU)then goto repl_continue end
aE={}aD[#aD+1]=aR
pcall(function()local aW=require(ab)if aW and aW.info then
aW.info("repl","["..

tostring(a.who or"?").."] "..aR:gsub("\n"," ; "):sub(1,120))end end)
aG=aG or
v{name="repl",caps={["fs.read"]=true,["fs.write"]=true,["compat.io"]=true,["component"]=true,["load"]=true,["net"]=true,["peripheral.modem"]=true,["peripheral.redstone"]=true,["peripheral.robot"]=true,["peripheral.inventory"]=true,["peripheral.tape"]=true},stdout=function(aW)
aF(aW,d.fg)end}local aS,aV=load("return "..aR,"=repl","t",aG)if not aS then
aS,aV=load(aR,"=repl","t",aG)end
if aS then local aY,aW=pcall(aS)
local aZ,aX=pcall(require,"kernel.sandbox")
local a_=
not aY and aZ and type(aX)=="table"and aX.exitStatus and aX.exitStatus(aW)~=nil;if a_ then break end
if aY then
if aW~=nil then aF(tostring(aW),d.highlight)end else aF(tostring(aW),d.error)end else aF(ah..tostring(aV),d.error)end end::repl_continue::end
pcall(function()local aM=require(ab)if aM and aM.info then
aM.info("repl",string.format("REPL session closed by %s (%.1fs, %d cmds)",tostring(
a.who or"?"),N.uptime()-aI,#aD))end end)end
b.edit=function(E,aB)if not f(aB)then return end;if not E[1]then
aB("Usage: edit <file>",d.dim)return end;local aC=u(E[1])G(aC)end
b.protect=function(aB,E)if not q(E)then return end
local aG,aC=pcall(require,"kernel.securefs")if not aG or not aC or not aC.setOperatorOverride then
E("This build has no protected-path override.",d.error)return end
local aD=K.sessionOf(a)
if not aD then
E("Could not identify your session, so there is nothing to arm.",d.error)
E("This is a bug rather than a permission problem — `whoami` should",d.dim)
E("say who you are; if it does, please report it.",d.dim)return end
local aE=aC.operatorOverride and aC.operatorOverride(aD)local aF=(aB[1]or""):lower()
if aF==""or aF==O then
E(
"Protected-path guards are "..
(aE and"STOOD DOWN for this session."or"active."),aE and d.warning or d.highlight)E("",d.dim)
E("They stop even root from writing under /tos, /etc, /usr and",d.dim)
E("/var through securefs — a line against a tampered admin",d.dim)
E("session, not an ACL. You own this machine, so you can stand",d.dim)
E("them down; nobody below root can, and it ends with this",d.dim)E("session.",d.dim)E("",d.dim)
E("  protect off    stand the guards down for this session",d.dim)E("  protect on     put them back",d.dim)return end
if aF=="off"then if aE then
E("Already stood down for this session.",d.dim)return end
local aH,aI=aC.setOperatorOverride(aD,true)
if not aH then E(S..tostring(aI),d.error)return end
E("Protected-path guards STOOD DOWN for this session.",d.warning)
E("You can now write and remove under /tos, /etc, /usr and /var.",d.dim)
E("Every path allowed this way is written to the kernel log.",d.dim)
E("Deleting the wrong thing here is how a machine stops booting —",d.dim)E("`protect on` when you are done.",d.dim)elseif aF=="on"then if not aE then
E("Guards are already active.",d.dim)return end
local aH,aI=aC.setOperatorOverride(aD,false)
if not aH then E(S..tostring(aI),d.error)return end
E("Protected-path guards active again.",d.highlight)else E("Usage: protect [status|off|on]",d.dim)end end
b.reclaim=function(aB,E)if not q(E)then return end;local aL=false;for aQ,aP in ipairs(aB or{})do
if aP=="--apply"then aL=true end end
local aO,aC=pcall(require,"kernel.fs")
if not aO or not aC then E("Filesystem unavailable.",d.error)return end;local aE=aC.readFile("/init.lua")if not aE then
E("Cannot read /init.lua — refusing to guess what this machine boots.",d.error)return end
if not
(
aE:find("_TOS",1,true)or aE:find("TOS Kernel",1,true)or
aE:find("tos/kernel",1,true))then
E("/init.lua is not TOS's — this machine boots OpenOS.",d.error)
E("Those files are the operating system here, not leftovers.",d.dim)E("Refusing.",d.dim)return end;local aF={"/bin","/boot","/lib"}local aG={}local aI="/init.lua.pre-tos"for aQ,aP in
ipairs(aF)do
if aC.exists(aP)then if aC.exists(aI)then aG[#aG+1]=aI end;break end end
local function aM(aP,aQ)
if not aC.exists(aP)then return end
if aC.isDirectory(aP)then
for aS,aR in ipairs(aC.list(aP)or{})do aM(aP.."/"..
(aR:gsub("/$","")),aQ)end;aQ.dirs[#aQ.dirs+1]=aP else
aQ.files[#aQ.files+1]=aP;aQ.bytes=aQ.bytes+ (aC.size(aP)or 0)end end;local aD={files={},dirs={},bytes=0}for aQ,aP in ipairs(aF)do aM(aP,aD)end
for aQ,aP in
ipairs(aG)do if aC.exists(aP)and not aC.isDirectory(aP)then aD.files[
#aD.files+1]=aP
aD.bytes=aD.bytes+ (aC.size(aP)or 0)end end;if#aD.files==0 and#aD.dirs==0 then
E("Nothing to reclaim — no OpenOS leftovers found.",d.highlight)return end;local aN=math.floor(
aD.bytes/1024+0.5)
E(string.format("OpenOS leftovers: %d file(s) in %d director(ies), ~%d KB",
#aD.files,#aD.dirs,aN),d.title)
for aQ,aP in ipairs(aF)do if aC.exists(aP)then E("  "..aP,d.fg)end end
for aQ,aP in ipairs(aG)do if aC.exists(aP)then E("  "..aP,d.fg)end end;E("",d.dim)
E("TOS installs no files into these, but it still looks in them:",d.dim)
E("require() searches /lib, and an unknown command is tried in /bin.",d.dim)
if aC.exists(aI)then
E("Until this runs, renaming /init.lua.pre-tos back to /init.lua",d.dim)
E("boots OpenOS again; afterwards an OpenOS floppy is the way back.",d.dim)else
E("An OpenOS floppy remains your recovery path — this install",d.dim)
E("stopped being one when TOS replaced /init.lua.",d.dim)end;E("",d.dim)
E("Removing /bin also changes what an unknown command does: today",d.dim)
E("it may run OpenOS's version, afterwards you get 'not a command'.",d.dim)if not aL then E("",d.dim)
E("Dry run. Nothing was removed.",d.highlight)E("Run it for real with:  reclaim --apply",d.dim)
return end
if r then
local aP=r(string.format(
"Permanently delete %d OpenOS file(s), ~%d KB?\n\n"..
"%s\n\nTOS keeps working; this drive stops being able to boot ".."OpenOS. Your recovery path becomes an OpenOS floppy.",
#aD.files,aN,table.concat(aF,"  ")),{title="Remove OpenOS leftovers",severity=_,yes="Delete",no=X})if not aP then E("Cancelled. Nothing was removed.",d.highlight)
return end end;E("",d.dim)E("Removing...",d.warning)local aJ,aH,aK=0,0,0;for aQ,aP in
ipairs(aD.files)do local aR=aC.size(aP)or 0
if aC.remove(aP)then aJ=aJ+1;aK=aK+aR else aH=aH+1 end end;for aQ,aP in ipairs(aD.dirs)do
pcall(aC.remove,aP)end
E(string.format("Removed %d file(s), ~%d KB reclaimed.",aJ,math.floor(aK/1024+0.5)),d.highlight)if aH>0 then
E(aH.." file(s) could not be removed.",d.warning)end
E("Reboot when convenient; nothing running depends on them.",d.dim)end
b.flash=function(aB,E)if not q(E)then return end;local aG,aN=nil,false;for aU,aT in ipairs(aB)do if aT=="--data"then aN=true elseif aG==nil then
aG=aT end end
if
not aG then E("Usage: flash <file> [--data]",d.dim)
E("Flashes the given file to the system EEPROM.",d.dim)
E("--data also writes the chip's data field, asked for and not shown,",d.dim)
E("for a chip going into a robot or drone (rc-pilot's shared secret).",d.dim)return end;local aH=u(aG)local aD=nil;for aT in L.list("eeprom")do aD=aT;break end
if not aD then
E("No EEPROM detected. Insert EEPROM, or press Ctrl+C to abort...",d.warning)local aT=N.uptime()+60
while not aD and N.uptime()<aT do
local aU,aV,aW=c.pullSignal(1)if aU=="component_added"and aW=="eeprom"then aD=aV elseif aU=="interrupted"then
E(R,d.dim)return end end
if not aD then E("Timed out waiting for EEPROM.",d.error)return end;E("EEPROM detected.",d.highlight)end;local aE=L.proxy(aD)local aI=aE.getSize()
local aJ=e.size and e.size(aH)if type(aJ)==ac and aJ>aI then
E(string.format("File too large: %d bytes (EEPROM max: %d)",aJ,aI),d.error)return end
local aC,aP=e.readFile(aH)
if not aC then E(ag..tostring(aP),d.error)return end;if#aC>aI then
E(string.format("File too large: %d bytes (EEPROM max: %d)",#aC,aI),d.error)return end
local aQ,aR=load(aC,"=flash-verify","t",{})
if not aQ then
E("Refusing to flash: file does not parse as Lua text.",d.error)E("  "..tostring(aR),d.dim)return end
local aK=
aC:find("getBootAddress",1,true)or aC:find("setBootAddress",1,true)or
(aC:find("component.list",1,true)and aC:find("init.lua",1,true))
if not aK then local aT
if s then
aT=s("This file does not look like a BIOS."..
"\n\n"..
"None of the markers a BIOS normally carries were found in it. "..

"Flashing it will very likely leave a machine that cannot boot, "..
"and fixing that means physically replacing the EEPROM."..
"\n\n".."If this chip is going into a robot or a drone, that is expected: "..
"put this computer's own EEPROM back before it restarts.","force",{title="Not a BIOS",severity=_,yes="Flash anyway",no=X})else
aT=
(i and i("Doesn't look like a BIOS — type 'force' to flash anyway: ",16))=="force"end
if not aT then E("Aborted (safety check).",d.dim)return end end;local aF=nil
if aN then
if aK then
E("Refusing --data: this file looks like a BIOS, and a BIOS keeps its",d.error)
E("boot address in the data field. --data is for a chip that is going",d.dim)E("into a robot or a drone.",d.dim)return end
if not i then E("--data needs a screen to ask on.",d.error)return end;local aU=256
do
local aX,aW=pcall(function()return aE.getDataSize()end)if aX and type(aW)==ac and aW>0 then aU=aW end end;local aT=i("Data for the chip (not shown): ",aU,true)if aT==nil or
aT==""then E(R,d.dim)return end
local aV=i("The same again, to confirm: ",aU,true)if aV~=aT then
E("The two did not match. Nothing was written.",d.error)return end;aF=aT end
local aS=aE.getLabel and aE.getLabel()or"(no label)"local aO="(unknown)"
do local aU,aT=pcall(N.getBootAddress)if aU and aT then aO=aT:sub(1,8)..
"..."end end;local aL=nil
do local aU,aT=pcall(require,"kernel.crypto")
if
aU and aT and aT.hash then local aW,aV=pcall(aT.hash,aC)if
aW and type(aV)==M and#aV==64 then aL=aV end end end
E(string.format("  Source : %s (%d bytes)",aH,#aC),d.dim)if aL then
E(string.format("  SHA-256: %s",aL),d.dim)else
E("  SHA-256: UNAVAILABLE - integrity cannot be verified",d.warning)end
E(string.format("  EEPROM : %s",aS),d.dim)
E(string.format("  Boot   : %s",aO),d.dim)if aF then
E(string.format("  Data   : %d bytes, as typed (not shown)",#aF),d.dim)end;local aM
if s then
aM=s("Overwrite this machine's EEPROM with "..
tostring(aH or
"this image").."?"..
"\n\n".."The EEPROM is what starts the computer. If the image is wrong, "..
"the machine will not boot and no software fix will reach it.","flash",{title="Flash EEPROM",severity=_,yes="Flash",no=X})else aM=(i and i('Type "flash" to confirm: ',16))==
"flash"end
if aM then local aT,aU=pcall(aE.set,aC)
if not aT then
E("Flash failed: "..tostring(aU),d.error)else
E("EEPROM flashed! "..#aC.." bytes written.",d.highlight)
if aF then local aV,aW=pcall(aE.setData,aF)if aV then
E("Data field set: "..#aF.." bytes.",d.highlight)else
E("The code was written, but the data field was NOT: "..tostring(aW),d.error)end end
if aK then E("Reboot for changes to take effect.",d.dim)else
E("This chip is not a BIOS: put this computer's own EEPROM back",d.dim)E("before it restarts.",d.dim)end end else E(R,d.dim)end end
local function D()
local E=a.SC or(_G._TOS and _G._TOS.config)return
E and E.get and E.get("accountAdmins")==true or false end
local function x(E)if K.liveTier(a)>=3 then return true,false end
if not D()then
E("Only root manages accounts on this machine. Root can let admins manage",d.error)
E("ordinary accounts with: users manage admins",d.dim)return false end;if not f(E)then return false end;return true,true end
local function at(E)
for aC,aB in
ipairs(g and
(g.list and g.list()or g.listUsers and g.listUsers())or{})do if(aB.username or aB.user)==E then return
tonumber(aB.tier or aB.accessLevel)end end end
local function F(aB,E)local aC=at(E)if aC and aC>=2 then
aB("An admin manages ordinary accounts only, and '"..E.."' is not one.",d.error)return false end;return true end
b.users=function(aB,E)if not f(E)then return end;if not g then E(Y,d.error)return end
if aB[1]==
"manage"then
local aD=a.SC or(_G._TOS and _G._TOS.config)
if not aB[2]then
E("Accounts are managed by: "..
(D()and"root, and admins for ordinary accounts"or"root only"),d.fg)
E("Usage: users manage root|admins   (root only)",d.dim)return end;if not q(E)then return end;if aB[2]~="root"and aB[2]~=ak then
E("Usage: users manage root|admins",d.dim)return end
if not
(aD and aD.set and aD.save)then E("No config to change.",d.error)return end;aD.set("accountAdmins",aB[2]==ak)aD.save()
E(

aB[2]==ak and"Admins may now add, remove and change ordinary accounts. Root still does the rest."or"Only root manages accounts now.",d.highlight)return end
E(string.format(" %-12s %-8s %s","User","Tier","Status"),d.title)E(string.rep("-",34),d.border)
local aC=g.list and g.list()or
g.listUsers and g.listUsers()or{}
for aE,aD in ipairs(aC)do local aF=aD.locked and"LOCKED"or"OK"
E(string.format(" %-12s %-8s %s",
aD.username or aD.user or"?",tostring(aD.tier or aD.accessLevel or"?"),aF),
aD.locked and d.error or d.dim)end end;local function y()if not g then return"root"end;local E=g.getSession(n)return
(E and E.user)or"root"end
b.useradd=function(aB,E)if
not x(E)then return end;if not g then E(Y,d.error)return end;local aC=aB[1]if not aC then
E("Usage: useradd <username>",d.dim)return end
local aD=i("Password for "..aC..": ",64,true)if not aD or aD==""then E(R,d.dim)return end
local aE=i("Confirm password: ",64,true)
if aE~=aD then E("Passwords do not match.",d.error)return end;local aF,aG=g.create(y(),aC,aD,1)
if aF then
a.lastOut={"User '"..aC.."' created.",d.highlight}else a.lastOut={tostring(aG),d.error}end end
b.userdel=function(aB,E)local aE,aF=x(E)if not aE then return end
if not g then E(Y,d.error)return end;local aC=aB[1]
if not aC then E("Usage: userdel <username>",d.dim)return end;if aF and not F(E,aC)then return end;local aD
if r then
aD=r("Delete the account '"..aC..
"'?\n\n"..
"Their home directory and files are NOT removed, but the account ".."cannot be recovered from here.",{title="Delete user",severity=_,yes="Delete",no=X})else
local aI=i("Delete '"..aC.."'? [y/N]: ",1,false)aD=(aI=="y"or aI=="Y")end;if not aD then E(R,d.dim)return end;local aG,aH=g.delete(y(),aC)
if aG then
a.lastOut={
"User '"..aC.."' deleted.",d.highlight}else a.lastOut={tostring(aH),d.error}end end
b.usermod=function(aB,E)local aH,aI=x(E)if not aH then return end
if not g then E(Y,d.error)return end;local aE,aF=aB[1],aB[2]if not aE or not aF then
E("Usage: usermod <username> lock|unlock|admin|user|root",d.dim)return end;if aI then if
aF=="admin"or aF=="root"then
E("Only root makes an admin or a root account.",d.error)return end
if not F(E,aE)then return end end
local aG=y()local aC,aD
if aF=="lock"then if g.setLocked then aC,aD=g.setLocked(aG,aE,true)else
aC,aD=false,"setLocked unavailable"end
if aC then
a.lastOut={"'"..aE.."' locked.",d.highlight}else a.lastOut={tostring(aD),d.error}end elseif aF=="unlock"then if g.setLocked then aC,aD=g.setLocked(aG,aE,false)else
aC,aD=false,"setLocked unavailable"end
if aC then
a.lastOut={"'"..aE.."' unlocked.",d.highlight}else a.lastOut={tostring(aD),d.error}end elseif aF=="admin"then if aE:lower()==al then
E("Failure. Did you mean 'usermod computer root'?",d.error)return end;if g.setTier then
aC,aD=g.setTier(aG,aE,2)else aC,aD=false,aq end;if aC then a.lastOut={"'"..
aE.."' promoted to admin.",d.highlight}else
a.lastOut={tostring(aD),d.error}end elseif aF=="root"then
if
aE:lower()==al and a.D and
not(_G._TOS and _G._TOS._takeoverFired)then _G._TOS=_G._TOS or{}
_G._TOS._takeoverFired=true;local aK,aJ=pcall(require,"shell.panels.takeover")
if
aK and aJ and aJ.run then local aL,aM=pcall(aJ.run,a)
if a.D.invalidate then pcall(a.D.invalidate)end
pcall(function()
_G._TOS.logObj.info("kernel","The computer briefly reconsidered its priorities ("..
tostring(aL and aM or"?")..")")end)a.lastOut={"Access control updated.",d.dim}return end end
if g.setTier then aC,aD=g.setTier(aG,aE,3)else aC,aD=false,aq end
if aC then
a.lastOut={"'"..aE.."' promoted to root.",d.highlight}else a.lastOut={tostring(aD),d.error}end elseif aF=="user"then
if g.setTier then aC,aD=g.setTier(aG,aE,1)else aC,aD=false,aq end
if aC then
a.lastOut={"'"..aE.."' set to user.",d.highlight}else a.lastOut={tostring(aD),d.error}end else E("Unknown action: "..aF,d.error)
E("Valid: lock, unlock, admin, user, root",d.dim)end end
b.lsdev=function(aB,E)local aD=aB[1]=="--full"
E(string.format(" %-16s %-10s %s","Type","Address","Info"),d.title)E(string.rep("-",46),d.dim)local aC=0
for aE,aF in L.list()do local aG=""
if aF==aa then
local aI,aH=pcall(L.proxy,aE)
if aI and aH then
local aJ=aH.getLabel and aH.getLabel()or""local aK=
aH.spaceTotal and math.floor(aH.spaceTotal()/1024)or 0
aG=(aJ~=""and
'"'..aJ..'" 'or"")..aK.."K"end elseif aF=="modem"then local aI,aH=pcall(L.proxy,aE)
if aI and aH and aH.isWireless then aG=
aH.isWireless()and"wireless"or"wired"end elseif aF=="drive"then local aI,aH=pcall(L.proxy,aE)
if aI and aH and aH.getCapacity then aG="raw "..
math.floor((
aH.getCapacity()or 0)/1024).."K"end elseif aF=="openprinter"then local aI,aH=pcall(L.proxy,aE)
if aI and aH then local function aJ(aK)
if aK==nil then return"?"end;local aM,aL=pcall(aK)
return(aM and tonumber(aL))and
tostring(math.floor(aL))or"?"end
aG="paper "..
aJ(aH.getPaperLevel).." ink "..
aJ(aH.getBlackInkLevel).."/"..aJ(aH.getColorInkLevel)end end
E(string.format(" %-16s %s  %s",aF,aD and aE or(aE:sub(1,8).."..."),aG),d.fg)aC=aC+1 end
if aC==0 then E("  (no peripherals detected)",d.dim)end end;b.devices=b.lsdev
b.mount=function(aB,E)
if aB[1]and aB[2]then if not f(E)then return end
local aE,aH=aB[1],aB[2]local aD={}local aC={}
for aN in L.list(aa)do
if aN:sub(1,#aE)==aE then aC[#aC+1]=aN else
local aP,aO=pcall(L.proxy,aN)if aP and aO and aO.getLabel and aO.getLabel()==aE then aD[#aD+
1]=aN end end end;local aF=nil
if#aC==1 then aF=aC[1]elseif#aC>1 then table.sort(aC)
E(string.format("Ambiguous address prefix '%s' matches %d devices (%s, ...); use a longer prefix",aE,
#aC,aC[1]:sub(1,8).."..."),d.error)return end
if not aF and#aD>0 then table.sort(aD)aF=aD[1]
if#aD>1 then
E(string.format("Note: %d disks share label '%s'; mounting %s (use partial address to disambiguate)",
#aD,aE,aF:sub(1,8).."..."),d.warning)end end
if not aF then E("Device not found: "..aE,d.error)return end
local aG=aH:sub(1,1)=="/"and aH or("/"..aH)local aI,aJ=pcall(L.proxy,aF)if not aI then
E("Cannot proxy device",d.error)return end;if not e.exists(aG)then
pcall(e.makeDirectory,aG)end;local aK=K.sessionOf(a)
local aL,aM=e.mount(aG,aJ,aK)
if aL==false then E(tostring(aM or aj),d.error)return end;a.lastOut={"Mounted at "..aG,d.highlight}else
local aD=e.mounts()
E(string.format(" %-18s %-14s %s","Mount","Label","Space"),d.title)E(string.rep("-",46),d.dim)
for aG,aF in ipairs(aD)do
local aH=aF.total and math.floor(
aF.total/1024)or 0
local aI=aF.used and math.floor(aF.used/1024)or 0
E(string.format(" %-18s %-14s %dK/%dK",(aF.mountPoint or"?"):sub(1,18),(
aF.label or""):sub(1,14),aI,aH),d.fg)end;local aE,aC={},0
for aG,aF in ipairs(aD)do aE[aF.address or""]=true end
for aF in L.list("drive",true)do if not aE[aF]then aC=aC+1 end end
if aC>0 then E("",d.dim)
E(aC.." unmanaged (raw) drive(s) are attached and NOT listed above:",d.warning)
E("they hold no filesystem yet, so there is nothing to mount.",d.dim)E("  drive list           see them",d.dim)
E("  drive format <addr>  make one a TBFS filesystem",d.dim)
E("  drive mount <addr>   then mount it here",d.dim)end end end
b.umount=function(E,aB)
if not E[1]then aB("Usage: umount <mountpoint>",d.dim)return end;if not f(aB)then return end;local aC=E[1]:sub(1,1)=="/"and E[1]or
("/"..E[1])local aD=K.sessionOf(a)
local aE,aF=e.unmount(aC,aD)if aE then a.lastOut={"Unmounted "..aC,d.highlight}else
a.lastOut={tostring(aF or
"Failed to unmount"),d.error}end end
b.jbod=function(aB,E)local aC=h.getJBOD and h.getJBOD()
if not aC then
E("JBOD is disabled. Enable it with: bootsettings jbod on  (then reboot)",d.warning)
E("It pools several disks into one mount. See 'man jbod'.",d.dim)return end;local aD=(aB[1]or"list"):lower()
local function aE(aF)local aG,aH={},{}
for aI in
L.list(aa)do
if aI:sub(1,#aF)==aF then aG[#aG+1]=aI else local aK,aJ=pcall(L.proxy,aI)if
aK and aJ and aJ.getLabel and aJ.getLabel()==aF then
aH[#aH+1]=aI end end end;table.sort(aG)table.sort(aH)
if#aG==1 then return aG[1]end;if#aG==0 and#aH==1 then return aH[1]end;if#aG>1 then return nil,
"ambiguous address prefix: "..aF end;if#aH>1 then return nil,
"ambiguous label: "..aF end
return nil,"no filesystem matches: "..aF end
if aD=="list"or aD==O then
local aG=aC.loadConfig(e)or{pools={}}local aF=aG.pools or{}if#aF==0 then
E("No JBOD pools configured.",d.dim)end
for aI,aH in ipairs(aF)do local aJ=0
for aI,aK in ipairs(aH.members or{})do for aL in
L.list(aa)do if aL==aK then aJ=aJ+1;break end end end
E(string.format(" %-16s %d member(s), %d present",aH.mount,# (aH.members or{}),aJ),d.fg)end
E("Free space: df  ·  individual disks: disk  ·  manage: jbod create|destroy",d.dim)elseif aD=="create"then if not f(E)then return end;local aF=aB[2]
if not aF or not aB[3]then
E("Usage: jbod create <mountpoint> <disk> [disk...]",d.dim)
E("  <disk> = fs address prefix or label (see lsdev)",d.dim)return end;if aF:sub(1,1)~="/"then aF="/"..aF end;aF=
(e.normalize and e.normalize(aF))or aF;if not
(aF:sub(1,5)=="/mnt/"and#aF>5)then
E("JBOD mount point must be under /mnt/  (e.g. jbod create /mnt/pool ...)",d.error)return end;local aJ=_G._TOS and
_G._TOS.bootAddr;local aI,aH={},{}
for aO=3,#aB do local aP,aR=aE(aB[aO])if not aP then
E(tostring(aR),d.error)return end
if aJ and aP==aJ then
E("Refusing to pool the BOOT disk ("..
aP:sub(1,8).."...).",d.error)
E("It would expose the system files inside the pool. Use data disks.",d.dim)return end;local aS,aQ=pcall(L.proxy,aP)if not aS or not aQ then
E("Cannot open disk: "..aB[aO],d.error)return end;aI[#aI+1]=aQ
aH[#aH+1]=aP end;pcall(e.makeDirectory,"/mnt")
pcall(e.makeDirectory,aF)local aK=aC.makePool(aI)local aL=K.sessionOf(a)
local aM,aN=e.mount(aF,aK,aL)
if not aM then E(tostring(aN or aj),d.error)return end;local aG=aC.loadConfig(e)or{pools={}}
aG.pools=aG.pools or{}for aO=#aG.pools,1,-1 do if aG.pools[aO].mount==aF then
table.remove(aG.pools,aO)end end;aG.pools[
#aG.pools+1]={mount=aF,members=aH}
aC.saveConfig(e,aG)
a.lastOut={string.format("JBOD pool at %s (%d disks)",aF,#aH),d.highlight}elseif aD=="destroy"or aD==ad then if not f(E)then return end;local aF=aB[2]if not aF then
E("Usage: jbod destroy <mountpoint>",d.dim)return end
if aF:sub(1,1)~="/"then aF="/"..aF end;local aI=K.sessionOf(a)e.unmount(aF,aI)
local aG=aC.loadConfig(e)or{pools={}}local aH=false
for aJ=# (aG.pools or{}),1,-1 do if aG.pools[aJ].mount==aF then
table.remove(aG.pools,aJ)aH=true end end;if aH then aC.saveConfig(e,aG)end
a.lastOut={aH and
("Destroyed JBOD pool "..aF)or("No JBOD pool at "..aF),
aH and d.highlight or d.warning}else
E("Usage: jbod [list | create <mount> <disk...> | destroy <mount>]",d.dim)end end
b.netfs=function(aB,E)local aF,aC=K.requireRoomy(a,"kernel.netfs","admin")if not aF or
not aC then E(K.loadFailure("netfs",aC),d.error)
return end
local aD=(aB[1]or O):lower()
local function aE()local aG={}for aI,aH in ipairs(e.mounts()or{})do
if type(aH.address)==M and
aH.address:sub(1,6)=="netfs:"then aG[#aG+1]=aH end end
table.sort(aG,function(aH,aI)return
aH.mountPoint<aI.mountPoint end)return aG end
if aD==O or aD=="list"then
local aG=aC.isEnabled and aC.isEnabled()
local aH=aC.getExports and aC.getExports()or{}
local aJ=m and m.getServiceArm and m.getServiceArm("netfsd")
E("Serving: "..
(
aG and"yes"or aJ and"no (export file rejected; see: netfs exports)"or"no (service netfsd is not running)"),
aG and d.highlight or d.warning)
if#aH==0 then
E("  No exports configured ("..aC.EXPORTS_PATH..").",d.dim)else for aL,aK in ipairs(aH)do
E(string.format("  %-12s %-24s %s  %d peer rule(s)",aK.name,aK.path,aK.mode,# (aK.allow or{})),d.fg)end end;local aI=aE()E("",d.fg)
if#aI==0 then E("Mounted: none",d.dim)else
E("Mounted:",d.fg)
for aL,aK in ipairs(aI)do local aM=(aK.total or 0)>0
E(string.format("  %-16s %-22s %s",aK.mountPoint,aK.label,

aM and t(aK.total- (aK.used or 0)).." free"or"unreachable"),
aM and d.fg or d.warning)end end
E("Manage: netfs mount <host> <share> <mountpoint> · netfs umount <mountpoint>",d.dim)elseif aD=="exports"then local aH,aI=aC.loadExports(e)if not aH then
E("Export file rejected: "..tostring(aI),d.error)
E("Nothing is served while the file is invalid.",d.dim)return end
local aG=aC.getExports()
if#aG==0 then
E("No exports in "..aC.EXPORTS_PATH,d.dim)
E("Format: { { name=\"pub\", path=\"/srv/pub\", mode=\"ro\", allow={\"<addr>\"} } }",d.dim)return end
for aK,aJ in ipairs(aG)do
E(string.format("%-12s %-24s %s",aJ.name,aJ.path,aJ.mode),d.highlight)
for aK,aL in ipairs(aJ.allow or{})do E("    allow "..aL,d.dim)end;if# (aJ.allow or{})==0 then
E("    allow (none) — this export is unreachable",d.warning)end end elseif aD=="mount"then if not f(E)then return end;local aK,aI,aH=aB[2],aB[3],aB[4]
if not
(aK and aI and aH)then
E("Usage: netfs mount <host> <share> <mountpoint>",d.dim)
E("  <host>  = peer hostname or address prefix (see net peers)",d.dim)
E("  <share> = export name on that machine (ask its operator)",d.dim)return end
if not m then E("Networking is not available.",d.error)return end;local aG=aK;local aN,aL=pcall(require,"shell.ext")
if
aN and type(aL)=="table"and aL.resolvePeer then aG=aL.resolvePeer(aK)end;local aM=m.findPeer and m.findPeer(aG)if aM and aM.addr then
aG=aM.addr end
if m.getTrust or m.getProtocol then
local aT,aS=pcall(require,"kernel.net.trust")
if aT and aS and aS.getLevel and aS.LEVEL then
if aS.getLevel(aG)<
aS.LEVEL.TRUSTED then
E("Peer is not TRUSTED — netfs refuses to mount from it.",d.error)
E("Raise trust first (see 'net trust'), then retry.",d.dim)return end end end;if not(aH:sub(1,5)=="/mnt/"and#aH>5)then
E("Mount point must be under /mnt/  (e.g. netfs mount box pub /mnt/box)",d.error)return end
local aJ=aC.attach(aG,aI)
local aO=aJ.spaceTotal and aJ.spaceTotal()or 0
if not aJ.exists("/")and aO==0 then
E("Cannot reach share '"..aI.."' on "..
tostring(aG):sub(1,8)..".",d.error)
E("Check the export name, and that netfsd runs there and allows this machine.",d.dim)return end;pcall(e.makeDirectory,"/mnt")
pcall(e.makeDirectory,aH)local aP=K.sessionOf(a)local aQ,aR=e.mount(aH,aJ,aP)if not aQ then
E(tostring(aR or aj),d.error)return end
E("Mounted "..aI.." from "..tostring(aG):sub(1,8)..
" at "..aH,d.highlight)
E("This mount is only usable while that machine is online.",d.dim)elseif aD=="umount"then if not f(E)then return end;local aG=aB[2]if not aG then
E("Usage: netfs umount <mountpoint>",d.dim)return end;local aH=false;for aM,aL in ipairs(aE())do if
aL.mountPoint==aG then aH=true;break end end;if not aH then E(
"No netfs mount at "..aG,d.warning)
E("Use 'netfs status' to list them (plain 'umount' handles local disks).",d.dim)return end
local aI=K.sessionOf(a)local aJ,aK=e.unmount(aG,aI)if aJ then
E("Unmounted "..aG,d.highlight)else
E(tostring(aK or"Failed to unmount"),d.error)end else
E("Usage: netfs [status | exports | mount <host> <share> <mount> | umount <mount>]",d.dim)end end
b.theme=function(aB,E)local aC=_G._TOS and _G._TOS.theme;if not aC then
E("Theme manager unavailable (T1 / monochrome or low-RAM boot)",d.warning)return end
do
local aH=(aB[1]or"show"):lower()
local aI={list=true,ls=true,show=true,current=true,keys=true,[""]=true}local aJ={color=true,colour=true}
if aJ[aH]then if not f(E)then return end elseif not aI[aH]then if
K.liveTier(a)<1 then
E("Log in as a user to set a personal theme.",d.error)return end end end
local function aG(aH)if not aH then return nil end
if type(aH)~=M or#aH>16 then return nil end;local aI=aH:match("^0[xX](%x+)$")or aH:match("^#(%x+)$")or
aH:match("^(%x+)$")if aI and#
aI<=6 then return tonumber(aI,16)end
return tonumber(aH)end;local function aF(aH)return string.format("0x%06X",aH)end;local aD=
aB[1]and aB[1]:lower()or"show"
local aE=K.sessionOf(a)
if aD=="list"or aD=="ls"then E("Available themes:",d.title)for aI,aH in
ipairs(aC.list())do
local aJ=(aH==aC.current().preset)and" *"or"  "
E(string.format(" %s %-10s %s",aJ,aH,aC.describe(aH)or""),d.fg)end
E("",d.fg)
E("'*' = currently active.  Use 'theme set <name>' to switch.",d.dim)elseif aD=="show"or aD=="current"then local aH=aC.current()
E("Active theme: "..aH.preset,d.title)
E("  ".. (aC.describe(aH.preset)or""),d.dim)local aI=0;for aJ in pairs(aH.overrides)do aI=aI+1 end
if aI==0 then
E("No color overrides.",d.dim)else E("Overrides:",d.highlight)for aJ,aK in pairs(aH.overrides)do
E(string.format("  %-14s %s",aJ,aF(aK)),d.fg)end end;E("",d.fg)
E("Try: theme set <name>  |  theme color <key> <0xRRGGBB>  |  theme reset",d.dim)elseif aD=="set"or aD=="use"then local aH=aB[2]if not aH then
E("Usage: theme set <name>  (theme list to see names)",d.warning)return end;local aI,aJ=aC.apply(aH)
if
not aI then E(aJ or"apply failed",d.error)return end;E("Applied theme: "..aH,d.highlight)
if aE then
local aK,aL=aC.saveForUser(aE)if not aK then
E("(not saved: "..tostring(aL)..")",d.dim)end end;c.drawAll()elseif aD=="preview"or aD=="try"then local aH=aB[2]if not aH then
E("Usage: theme preview <name>",d.warning)return end;local aI,aJ=aC.apply(aH)if not aI then
E(aJ or"apply failed",d.error)return end
E("Previewing '"..
aH.."' (not saved). Use 'theme set' to keep it.",d.highlight)c.drawAll()elseif aD=="color"or aD=="colour"then local aH,aI=aB[2],aB[3]if not aH or
not aI then
E("Usage: theme color <key> <0xRRGGBB>",d.warning)
E("Keys: "..table.concat(aC.overridableKeys(),", "),d.dim)return end
if not
aC.isOverridable(aH)then
E("Not an overridable color: "..aH,d.error)
E("Run 'theme color' with no args for the full list.",d.dim)return end;local aJ=aG(aI)if not aJ then
E("Invalid color value: "..aI.." (try 0xFF8800)",d.error)return end
local aK,aL=aC.setColor(aH,aJ)
if not aK then E(aL or"color set failed",d.error)return end
E(string.format("%s = %s",aH,aF(aJ)),d.highlight)if aE then aC.saveForUser(aE)end;c.drawAll()elseif aD=="reset"then
local aH,aI=aC.resetOverrides()
if not aH then E(aI or"reset failed",d.error)return end
E("Cleared color overrides; preset '"..aC.current().preset.."' restored.",d.highlight)if aE then aC.saveForUser(aE)end;c.drawAll()elseif aD=="clear"or aD==
"default"then
if not aE then E("Not logged in.",d.error)return end;local aH,aI=aC.clearForUser(aE)if not aH then
E(aI or"clear failed",d.error)return end
E("Theme reset to default; saved preference cleared.",d.highlight)c.drawAll()elseif aD=="keys"then
E("Overridable color keys:",d.title)
for aI,aH in ipairs(aC.overridableKeys())do E("  "..aH,d.fg)end else
E("Usage: theme <list|show|set|preview|color|reset|clear|keys>",d.warning)
E("  list                  Show available themes",d.dim)
E("  show                  Show active theme + overrides",d.dim)
E("  set <name>            Apply preset and save for this user",d.dim)
E("  preview <name>        Apply preset without saving",d.dim)
E("  color <key> <0xRGB>   Override a single color",d.dim)
E("  keys                  List overridable color keys",d.dim)
E("  reset                 Drop overrides, keep preset",d.dim)
E("  clear                 Wipe saved theme, revert to default",d.dim)end end;b.colors=b.theme
b.service=function(E,aB)
if E[1]and E[1]~="list"and not f(aB)then return end;local aD,aC=K.requireRoomy(a,"kernel.rc","admin")if not aD then
aB(K.loadFailure("service",aC),d.error)return end
if not E[1]or E[1]=="list"then
local aE=aC.list()
if#aE==0 then aB("No services registered",d.dim)return end
aB(string.format(" %-16s %s","Service","Status"),d.title)aB(string.rep("-",28),d.dim)
for aG,aF in ipairs(aE)do
local aH=
aF.running and"running"or
(aF.unavailable and("not loaded: "..aF.unavailable))or
(aF.enabled==false and am)or"stopped"
aB(string.format(" %-16s %s",aF.name:sub(1,16),aH),
aF.running and d.highlight or d.dim)end elseif E[1]=="start"and E[2]then local aE,aF=aC.start(E[2])
aB(
aE and"Started: "..E[2]or tostring(aF),aE and d.highlight or d.error)
if aE then local aH,aG=pcall(require,"kernel.pkg")
if
aH and type(aG)=="table"and aG.noteServiceStarted then
local aI=aG.noteServiceStarted(E[2],{session=K.sessionOf(a)})if aI then
aB("Package '"..aI.."' enabled with it.",d.dim)end end
if E[2]:find("rshd",1,true)then
local aJ,aI=pcall(require,"kernel.net.remote")
if aJ and type(aI)=="table"and aI.stepBudgetAvailable and not
aI.stepBudgetAvailable()then
aB("OpenComputers gives remote commands no CPU or memory limit:",d.warning)
aB("a runaway one stops this whole machine.",d.warning)end end end elseif E[1]=="stop"and E[2]then local aE,aF=aC.stop(E[2])
aB(
aE and"Stopped: "..E[2]or tostring(aF),aE and d.highlight or d.error)else
aB("Usage: service [list | start <name> | stop <name>]",d.dim)end end
b.cron=function(aB,E)if not f(E)then return end
if _G._TOS and _G._TOS.cronDisabled then
E("Cron is off in this boot profile: no job runs.",d.warning)local aG=e.readFile("/etc/cron.dat")
local aJ,aH=pcall(require,"kernel.serialize")local aI,aF=false,nil;if aG and aJ and aH then
aI,aF=pcall(aH.decode,aG,{maxBytes=65536})end;local aE={}
if aI and type(aF)=="table"and
type(aF.jobs)=="table"then for aL,aK in pairs(aF.jobs)do
if type(aK)=="table"then aE[
#aE+1]={id=aL,name=tostring(aK.name)}end end end
table.sort(aE,function(aK,aL)return tostring(aK.id)<tostring(aL.id)end)
if#aE>0 then
E(#aE.." saved job(s), which run again after a normal boot:",d.dim)for aL,aK in ipairs(aE)do
E(string.format(" %-4s %s",tostring(aK.id),aK.name),d.dim)end end
if aB[1]and aB[1]~="list"then
E("cron: jobs cannot be changed in this boot profile; boot normally to edit them."..
"  [E-404 ERR_SAFE_MODE]",d.error)end;return end;local aD,aC=K.requireRoomy(a,"kernel.cron","admin")if not aD then
E(K.loadFailure("cron",aC),d.error)return end
if not aB[1]or aB[1]=="list"then
local aE=aC.list()
if#aE==0 then E("No scheduled jobs",d.dim)return end
E(string.format(" %-4s %-16s %-8s %s","ID","Name","Every","Enabled"),d.title)
for aG,aF in ipairs(aE)do
E(string.format(" %-4d %-16s %-8s %s",aF.id,aF.name:sub(1,16),aF.interval.."s",aF.enabled and
"yes"or"no"),
aF.enabled and d.fg or d.dim)end elseif aB[1]=="add"and aB[2]and aB[3]and aB[4]then
local aE=aB[2]local aF=tonumber(aB[3])local aH=table.concat(aB," ",4)if not aF then
E("Invalid interval. Usage: cron add <name> <seconds> <script>",d.error)return end
local aG,aI=aC.add(aE,aF,aH)if not aG then E(tostring(aI),d.error)return end
E(
"Added job #"..aG..": "..aE,d.highlight)elseif aB[1]=="rm"and aB[2]then local aE=tonumber(aB[2])
if aE then
local aF,aG=aC.remove(aE)if aF then E("Removed job #"..aE,d.highlight)else
E("cron rm: "..tostring(aG or
"no such job"),d.error)end else
E("Invalid ID",d.error)end else
E("Usage: cron [list|add <name> <seconds> <script>|rm <id>]",d.dim)end end end