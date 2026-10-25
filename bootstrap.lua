local bl,bm,bn,aM=" more)","/bios.lua","/install.lua","string"
local aX=require("component")local aC=require("computer")local aN=require("term")local at=nil;pcall(function()
at=require("filesystem")end)
local aY=aX.gpu;local function ar(a)
if aY and aY.setForeground then pcall(aY.setForeground,a)end end;local function ax(a)ar(0x00FF00)
print("  + "..a)ar(0xFFFFFF)end;local function aq(a)ar(0xFFFF00)
print("  ! "..a)ar(0xFFFFFF)end;local function au(a)ar(0xFF0000)
print("  X "..a)ar(0xFFFFFF)end
local function bo(c,b,a)ar(0xFFFF00)
io.write(c)if b then ar(0xAAAAAA)
io.write(" ["..table.concat(b,"/").."]")end;if a then ar(0x888888)
io.write(" (default: "..a..")")end;ar(0xFFFFFF)io.write(": ")local d
if aN and
aN.read then local e,f=pcall(aN.read)if e then d=f
if d then d=d:gsub("\n$","")end end else d=io.read()end;if not d or d==""then return a end;return d end
local function bp(a)local b=bo(a,{"y","n"},"y")return b and
(b:lower()=="y"or b:lower()=="yes")end
local function aZ(a)if os.sleep then pcall(os.sleep,a)end end;local bb="1.0.0"
local bq={"████████  ████████  ████████","   ██     ██    ██  ██      ","   ██     ██    ██  ████████","   ██     ██    ██        ██","   ██     ████████  ████████"}
local function br()ar(0x00AAFF)for b,a in ipairs(bq)do print("   "..a)end
ar(0xFFFFFF)print()ar(0x00FF66)print("   Strata Systems LLC")
ar(0xFFFFFF)ar(0xAAAAAA)
print("   Terminal Operating System — Network Bootstrap v"..bb)ar(0xFFFFFF)print()end;local bc="Evan450"local bd="TOS-Terminal-Operating-System-"
local bs={"main","master"}local bt={"","TOS-Release"}
local function aO(a)return
type(a)==aM and a~=""and
not a:find("[%c]")and a:match("^[%w%.%-_/]+$")~=nil end
local function bu()local a=aX.list("internet")()if not a then return nil end
local b,c=pcall(aX.proxy,a)if not b then return nil end;return c end;local be=256*1024;local a_=20;local bv=3;local bf=2
local function aP(c,d,a,b)a=a or bv
local function e()if b then pcall(b)end end
for f=1,a do
local h,g,i=pcall(c.request,d,nil,{["user-agent"]="TOS-Bootstrap/"..bb})
if h and g then local m,n,j={},0,nil;local k,l=false,nil;local o=aC.uptime()+a_
while true do
local r,p,q=pcall(g.read)if not r then k=true;l=tostring(p)break end;if g.response and not j then
local t,s=pcall(g.response)if t and s then j=s end end;if p==nil then if q then k=true
l=tostring(q)end;break end
if#p>0 then n=n+#p
if n>be then k=true;l=
"response exceeds "..be.." bytes"break end;m[#m+1]=p;o=aC.uptime()+a_ else e()aZ(0)end
if aC.uptime()>o then k=true;l="timed out after "..a_.."s"break end end;pcall(function()g.close()end)if not k then if j and j~=200 then return nil,"HTTP "..
tostring(j),j end;return table.concat(m),
nil,j end;if f<a then
aZ(1)end else if f<a then aZ(1)end end end;return nil,"request failed after "..a.." attempt(s)"end
local function aQ(b,c,d,a,e)local f=(a~=""and("/"..a)or"")return
string.format("https://raw.githubusercontent.com/%s/%s/%s%s%s",b,c,d,f,e)end
local function bw(a)
if#a>256*1024 then return nil,"manifest exceeds 256 KB sanity cap"end;local c,d=load(a,"=manifest","t",{})if not c then return nil,
"manifest parse error: "..tostring(d)end;local e,b=pcall(c)
if
not e then return nil,"manifest run error: "..tostring(b)end
if type(b)~="table"then return nil,"manifest did not return a table"end;return b end
local function bx(a)local b={positional={}}
for d,c in ipairs(a)do
if
c=="-h"or c=="--help"or c=="-?"or c=="/?"then b.help=true elseif
type(c)==aM and c:sub(1,1)=="-"then b.unknown=b.unknown or c else
b.positional[#b.positional+1]=c end end;return b end
local function by()
print("Downloads TOS over the internet and installs it.")print()print("Usage:")
print("  bootstrap.lua [owner/repo [branch [subdir]]]")print("  bootstrap.lua --help")print()
print("With no arguments it uses the official repo")print("("..bc.."/"..bd..").")
print("A fork or another branch can be named instead.")print()print("You need:")
print("  - an Internet Card in this computer")
print("  - about 1.4 MB free for the download (it picks")print("    the drive with the most room)")print()
print("It checks every file against the release's")
print("digests, then runs the installer. The installer")
print("asks which drive TOS goes on (the boot drive is")
print("only the default), asks a few setup questions,")
print("and offers to flash the TOS BIOS. Nothing is")print("installed until you confirm.")print()
print("Run it by its full path, e.g. /bootstrap.lua.")end;local aE=bx({...})aN.clear()br()
if aE.help or aE.unknown then if aE.unknown and
not aE.help then
au("Unknown option: "..tostring(aE.unknown))print()end;by()return end
if not at then
au("OpenOS filesystem library unavailable — cannot stage a download.")
aq("Run this from OpenOS, not a bare Lua interpreter.")return end;local aF=bu()
if not aF then
au("No Internet Card found on this computer.")
aq("Craft one (Tier 1 is enough) and place it in this computer or")
aq("server, or install from a physical disk with install.lua instead.")return end;ax("Internet Card found")print()local aw=aE.positional;local ay,az=bc,bd
if
aw[1]then local a,b=aw[1]:match("^([^/]+)/(.+)$")if
a and b and aO(a)and aO(b)then ay,az=a,b else
aq("Ignoring malformed owner/repo argument: "..tostring(aw[1]))end end;local aR=bs
if aw[2]then if aO(aw[2])then aR={aw[2]}else
aq("Ignoring malformed branch argument: "..tostring(aw[2]))end end;local bg=bt
if aw[3]~=nil then if aw[3]==""or aO(aw[3])then bg={aw[3]}else
aq(
"Ignoring malformed subdir argument: "..tostring(aw[3]))end end;ax("Repository: "..ay.."/"..az)print()
if not
bp("Download TOS from the internet and run the installer?")then print("Cancelled.")return end;print()ar(0x00AAFF)
print("--- Locating release files ---")ar(0xFFFFFF)local aG,aD,aS
for b,a in ipairs(aR)do
for b,c in ipairs(bg)do local g=a..
(c~=""and("/"..c)or"")
io.write("  probing "..g.." ")local d=0;local f=aC.uptime()local function h()local k=aC.uptime()if k-f>=0.3 and d<40 then f=k;d=d+1
io.write(".")end end
local i=aQ(ay,az,a,c,"/tos/system_manifest.lua")local e,j=aP(aF,i,bf,h)io.write(" ")
if e and#e>0 then ar(0x00FF00)
print("found")ar(0xFFFFFF)aG,aD,aS=a,c,e;break else ar(0xAAAAAA)print("not there ("..
tostring(j)..")")ar(0xFFFFFF)end end;if aS then break end end;print()
if not aS then
local a=aP(aF,aQ(ay,az,aR[1],"","/system_manifest.lua"),bf)
if a and#a>0 then
au("This repo has a FLAT layout — no directory structure.")
aq("system_manifest.lua is at the root, but the files it declares")
aq("(/tos/kernel/init.lua and the rest) have no directories to live")
aq("in. That cannot be installed from, and it cannot be repaired by")
aq("downloading harder: TOS ships six separate init.lua files, and a")aq("flat repo can only hold one of them.")
aq("Fix: push the release tree WITH its directories (tos/, etc/,")aq("usr/) to the repo, then re-run this script.")
return end
au("Could not find a TOS release under "..ay.."/"..
az.." on any of: "..table.concat(aR,", "))
aq("If this is a fork or the layout changed, point at it directly:")
aq("  bootstrap.lua "..ay.."/"..az.." <branch> <subdir>")return end;local aH,bz=bw(aS)if not aH then
au("Cannot parse the downloaded manifest: "..tostring(bz))return end
ax("Using "..
ay.."/"..
az.."@"..aG..
(
aD~=""and("/"..aD)or"").." ("..#aH.." files declared)")print()local aI={}for b,a in ipairs(aH)do
if

type(a)=="table"and type(a.path)==aM and type(a.hash)==aM and#a.hash==64 then aI[a.path]=a.hash:lower()end end
local bA={string=string,table=table,math=math,tonumber=tonumber,tostring=tostring,type=type,select=select,ipairs=ipairs,pairs=pairs,error=error,assert=assert,setmetatable=setmetatable}local bh,bi=nil,false
do local a=0;for b in pairs(aI)do a=a+1 end
if a==0 then
aq("This release ships no digests — downloads cannot be verified.")
aq("Older releases predate them; the install will still work, but a")aq("corrupted transfer will not be caught here.")
print()else io.write("  fetching the hasher ")
local b="/tos/kernel/sha256.lua"local c,e=0,aC.uptime()
local d=aP(aF,aQ(ay,az,aG,aD,b),nil,function()local f=aC.uptime()if
f-e>=0.3 and c<40 then e=f;c=c+1;io.write(".")end end)io.write(" ")
if not d then ar(0xFFFF00)print("unavailable")
ar(0xFFFFFF)
aq("Could not fetch "..b.."; downloads will NOT be verified.")print()else local h=load(d,"=sha256","t",bA)local g,f=false,nil
if h then g,f=pcall(h)end
if
g and type(f)=="table"and type(f.hex)=="function"then local i,j=pcall(f.hex,"abc")
if not
(i and
j=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")then g=false;f=nil end end
if g and type(f)=="table"and f.hex then
if
aI[b]and f.hex(d)~=aI[b]then ar(0xFF0000)print("CORRUPT")ar(0xFFFFFF)
au("sha256.lua does not match its own manifest entry.")
au("Refusing to install from a repository that is inconsistent")
au("with itself. Retry; if it persists, the release is broken.")return end;bh,bi=f,true;ar(0x00FF00)print("ok")ar(0xFFFFFF)
ax(a.." of "..#aH..
" files carry a digest and will be verified")print()else ar(0xFFFF00)print("unusable")ar(0xFFFFFF)
aq("sha256.lua did not load; downloads will NOT be verified.")print()end end end end
local function aT(a)local e,b=pcall(at.get,a)if not e or not b then return nil end
local f,c=pcall(b.spaceTotal)local g,d=pcall(b.spaceUsed)
if
not(f and g)or type(c)~="number"or type(d)~="number"then return nil end;if c<=0 then return nil end;return c-d end
local function aJ(a)return string.format("%.0f KB",a/1024)end
local function aK(a)if not at.exists(a)then return true end
if at.isDirectory(a)then local c={}
local e,d=pcall(at.list,a)if e and d then
if type(d)=="function"then for f in d do c[#c+1]=f end elseif type(d)=="table"then for g,f in
ipairs(d)do c[#c+1]=f end end end;for g,f in
ipairs(c)do
local h=a.."/"..tostring(f):gsub("/$","")aK(h)end end;local b=pcall(at.remove,a)
return b and not at.exists(a)end;local ba=1400*1024;local as,aL
do local a={}if at.isDirectory("/tmp")then
a[#a+1]={"/tmp/tos-netinstall","/tmp"}end;if at.isDirectory("/home")then
a[#a+1]={"/home/tos-netinstall","/home"}end
a[#a+1]={"/tos-netinstall-tmp","/"}local c,b;for e,d in ipairs(a)do local f=aT(d[2])
if f and(not b or f>b)then c,b=d[1],f end end
as=c or
((at.isDirectory("/tmp")and
"/tmp/tos-netinstall")or"/tos-netinstall-tmp")aL=b
if aL then
ax("Staging in "..as.." ("..aJ(aL).." free)")
if aL<ba then
aq("That is under the ~"..aJ(ba).." the release needs.")
aq("The download will likely run out of space partway through.")
aq("Free some room, or install from a disk instead. Continuing.")end end end;if at.exists(as)then
aq("Removing a stale staging directory from a previous run: "..as)aK(as)end;if not
at.makeDirectory(as)then
au("Cannot create staging directory: "..as)return end;local aA,aU={},{}for b,a in ipairs(aH)do
if

type(a)=="table"and type(a.path)==aM and not aU[a.path]then aU[a.path]=true;aA[#aA+1]=a.path end end;if not aU[bn]then aA[#
aA+1]=bn end
if not aU[bm]then aA[#aA+1]=bm end;ar(0x00AAFF)
print("--- Downloading "..#aA.." files ---")ar(0xFFFFFF)local aV,aB=0,0;local av={}local bj=false
for b,a in ipairs(aA)do
local d=a:match("^(.+)/[^/]+$")if d then local g=""
for h in d:gmatch("[^/]+")do g=g.."/"..h;if not at.isDirectory(as..g)then at.makeDirectory(
as..g)end end end
local f=aQ(ay,az,aG,aD,a)local c,e=aP(aF,f)
if c then local g=bi and aI[a]or nil;if
g and bh.hex(c)~=g then aB=aB+1
av[#av+1]=a..": DIGEST MISMATCH (corrupt or tampered)"c=nil end end
if c then local g=io.open(as..a,"w")
if g then g:write(c)g:close()aV=aV+1 else
aB=aB+1;local h=aT(as)
if h and h<4096 then bj=true;av[#av+1]=a..
": OUT OF SPACE ("..aJ(h).." free)"break end
av[#av+1]=a..": cannot open staging file for write"end elseif e==nil then else
if a==bm then else aB=aB+1;av[#av+1]=a..": "..tostring(e)end end;if b%10 ==0 or b==#aA then
io.write(string.format("\r  %d/%d files (%d failed)   ",b,#aA,aB))end end;print()print()
if bj then
au("Ran out of space in "..
as.." after "..aV.." file(s).")print()
aq("The release needs roughly "..aJ(ba).." of scratch space, and")
aq("this filesystem does not have it. Nothing was written outside")
aq(as..", and the target disk was never touched.")print()aq("Options, in the order worth trying:")
aq("  - Install from a floppy or install disk: no scratch space needed.")
aq("  - Free space on a larger drive; bootstrap stages wherever there")
aq("    is the most room, so it will pick it up automatically.")
aq("  - On a machine with only a small tmpfs, an installed HDD with")
aq("    free space is enough -- it does not have to be the target.")aK(as)return end
if aB==0 then ax("Downloaded "..aV.." files")else au(aB..
" file(s) failed to download:")for a=1,math.min(5,#av)do aq(
"  "..av[a])end;if#av>5 then
aq("  (+".. (#av-5)..bl)end end;print()
do local a={}
for c,b in ipairs(av)do if not b:find("DIGEST MISMATCH",1,true)then a[#a+
1]=b end end
if#a>0 then
au(#a.." file(s) never made it into the staging tree:")for b=1,math.min(8,#a)do aq("  "..a[b])end;if#a>8 then aq("  (+"..
(#a-8)..bl)end;print()
au("Refusing to install an incomplete release.")
aq("Installing anyway would produce a machine that boots and is")
aq("quietly missing pieces -- that is how a release once shipped")
aq("without the file holding most of the shell's commands.")print()
aq("Retry: these are usually transient. If the same file fails")
aq("every time, the release is broken; install from a disk and")aq("report which file.")aK(as)return end end
do local a={}for c,b in ipairs(av)do
if b:find("DIGEST MISMATCH",1,true)then a[#a+1]=b end end
if#a>0 then
au(#a..
" file(s) did not match the digest the manifest declares:")for b=1,math.min(8,#a)do aq("  "..a[b])end;if#a>8 then aq("  (+"..
(#a-8)..bl)end;print()
au(
"Refusing to install. Nothing was written outside "..as..".")
aq("Most likely: a release was published in the last few minutes and")
aq("the download caught it half-updated — the host serves cached files")
aq("for a while after a push. Wait five minutes and retry; that fixes")
aq("this on its own, and no wait is needed for a disk install.")print()
aq("If it repeats after that, treat it as real: a mangling proxy or a")
aq("truncated transfer looks the same as tampering from here, and so")
aq("does a release that is not what it claims. Install from a disk.")return end end;local aW=as..bn
local bB=at.exists(aW)and(at.size(aW)or 0)>0
if not bB then
au("install.lua did not download successfully — nothing to hand off to.")
aq("Retry, or point at the release directly if the layout is nonstandard:")
aq("  bootstrap.lua "..
ay.."/"..az.." "..
aG.. (aD~=""and(" "..aD)or" \"\""))return end;ar(0x00AAFF)
print("--- Handing off to install.lua ---")ar(0xFFFFFF)ax("Staged at "..as)print()
local bk,bC=loadfile(aW)
if not bk then
au("Downloaded install.lua does not parse: "..tostring(bC))
aq("The file may have been corrupted in transit — try again.")return end;local bD,bE=pcall(bk,as)
if not bD then
au("install.lua exited with an error: "..tostring(bE))aq("You can retry it directly:")
aq("  "..aW.." "..as)
aq("Leaving the staging tree in place so a retry needs no re-download.")return end
do local a=aL and aT(as)
if aK(as)then local b=aT("/")if b and a then
ax("Removed the staging copy ("..
aJ(b).." free now)")else
ax("Removed the staging copy from "..as)end else
aq(
"Could not remove the staging copy at "..as..".")
aq("It is a full second copy of the release; delete it to reclaim")aq("the space: rm -r "..as)end end
local function bF(a)if type(a)~=aM or a==""then return nil end;local b=a;if
b:sub(1,1)~="/"then b="/"..b end;if b:find("/",2,true)then return nil end;return b end
do local a=bF((arg and arg[0])or nil)
if a and
at.exists(a)and not at.isDirectory(a)then
if
pcall(at.remove,a)and not at.exists(a)then
ax("Removed "..
a.." (re-download it with the same one-liner)")else
aq("Could not remove "..a.."; delete it when convenient.")end end end