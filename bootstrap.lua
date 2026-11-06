local bp,bq,br,aL=" more)","/bios.lua","/install.lua","string"
local ba=require("component")local aI=require("computer")local aR=require("term")local ax=nil;pcall(function()
ax=require("filesystem")end)
local bb=ba.gpu;local function av(a)
if bb and bb.setForeground then pcall(bb.setForeground,a)end end;local function aB(a)av(0x00FF00)
print("  + "..a)av(0xFFFFFF)end;local function au(a)av(0xFFFF00)
print("  ! "..a)av(0xFFFFFF)end;local function ay(a)av(0xFF0000)
print("  X "..a)av(0xFFFFFF)end
local function bs(c,b,a)av(0xFFFF00)
io.write(c)if b then av(0xAAAAAA)
io.write(" ["..table.concat(b,"/").."]")end;if a then av(0x888888)
io.write(" (default: "..a..")")end;av(0xFFFFFF)io.write(": ")local d
if aR and
aR.read then local e,f=pcall(aR.read)if e then d=f
if d then d=d:gsub("\n$","")end end else d=io.read()end;if not d or d==""then return a end;return d end
local function bt(a)local b=bs(a,{"y","n"},"y")return b and
(b:lower()=="y"or b:lower()=="yes")end
local function bc(a)if os.sleep then pcall(os.sleep,a)end end;local bh="1.0.0"
local bu={"████████  ████████  ████████","   ██     ██    ██  ██      ","   ██     ██    ██  ████████","   ██     ██    ██        ██","   ██     ████████  ████████"}
local function bv()av(0x00AAFF)for b,a in ipairs(bu)do print("   "..a)end
av(0xFFFFFF)print()av(0x00FF66)print("   Strata Systems LLC")
av(0xFFFFFF)av(0xAAAAAA)
print("   Terminal Operating System — Network Bootstrap v"..bh)av(0xFFFFFF)print()end;local bd="Evan450"local be="TOS-Terminal-Operating-System-"
local bw={"main","master"}local bx="dcdafa5342333048be0ad519911a6bd1ecffefcffde73879a4e246fc20d7fd8b"
local by={["/tos/kernel/sha512.lua"]="434b03d1676e9eb7e02aca53400987a2a7f62a29f0a6d8065b52658af160a65a",["/tos/kernel/curve25519field.lua"]="a615df822af8d4e4cbabda79975352a5dcedc8de0ef576b5d673fbd9bdc4bb40",["/tos/kernel/ed25519.lua"]="e40ecec313398328aa7e20ff8e454660c7b611b91096495edf980e48e23985b1"}local bz={"","TOS-Release"}
local function aS(a)return
type(a)==aL and a~=""and
not a:find("[%c]")and a:match("^[%w%.%-_/]+$")~=nil end
local function bA()local a=ba.list("internet")()if not a then return nil end
local b,c=pcall(ba.proxy,a)if not b then return nil end;return c end;local bi=256*1024;local bf=20;local bB=3;local bj=2
local function aT(c,d,a,b)a=a or bB
local function e()if b then pcall(b)end end
for f=1,a do
local h,g,i=pcall(c.request,d,nil,{["user-agent"]="TOS-Bootstrap/"..bh})
if h and g then local m,n,j={},0,nil;local k,l=false,nil;local o=aI.uptime()+bf
while true do
local r,p,q=pcall(g.read)if not r then k=true;l=tostring(p)break end;if g.response and not j then
local t,s=pcall(g.response)if t and s then j=s end end;if p==nil then if q then k=true
l=tostring(q)end;break end
if#p>0 then n=n+#p
if n>bi then k=true;l=
"response exceeds "..bi.." bytes"break end;m[#m+1]=p;o=aI.uptime()+bf else e()bc(0)end
if aI.uptime()>o then k=true;l="timed out after "..bf.."s"break end end;pcall(function()g.close()end)if not k then if j and j~=200 then return nil,"HTTP "..
tostring(j),j end;return table.concat(m),
nil,j end;if f<a then
bc(1)end else if f<a then bc(1)end end end;return nil,"request failed after "..a.." attempt(s)"end
local function aU(b,c,d,a,e)local f=(a~=""and("/"..a)or"")return
string.format("https://raw.githubusercontent.com/%s/%s/%s%s%s",b,c,d,f,e)end
local function bC(a)
if#a>256*1024 then return nil,"manifest exceeds 256 KB sanity cap"end;local c,d=load(a,"=manifest","t",{})if not c then return nil,
"manifest parse error: "..tostring(d)end;local e,b=pcall(c)
if
not e then return nil,"manifest run error: "..tostring(b)end
if type(b)~="table"then return nil,"manifest did not return a table"end;return b end
local function bD(a)local b={positional={}}
for d,c in ipairs(a)do
if
c=="-h"or c=="--help"or c=="-?"or c=="/?"then b.help=true elseif c=="--allow-unsigned"then
b.allowUnsigned=true elseif type(c)==aL and c:sub(1,1)=="-"then
b.unknown=b.unknown or c else b.positional[#b.positional+1]=c end end;return b end
local function bE()
print("Downloads TOS over the internet and installs it.")print()print("Usage:")
print("  bootstrap.lua [owner/repo [branch [subdir]]]")print("  bootstrap.lua --help")print()
print("With no arguments it uses the official repo")print("("..bd.."/"..be..").")
print("A fork or another branch can be named instead.")print()print("You need:")
print("  - an Internet Card in this computer")
print("  - about 1.4 MB free for the download (it picks")print("    the drive with the most room)")print()
print("It checks every file against the release's")
print("digests, then runs the installer. The installer")
print("asks which drive TOS goes on (the boot drive is")
print("only the default), asks a few setup questions,")
print("and offers to flash the TOS BIOS. Nothing is")print("installed until you confirm.")print()
print("Run it by its full path, e.g. /bootstrap.lua.")end;local aG=bD({...})aR.clear()bv()
if aG.help or aG.unknown then if aG.unknown and
not aG.help then
ay("Unknown option: "..tostring(aG.unknown))print()end;bE()return end
if not ax then
ay("OpenOS filesystem library unavailable — cannot stage a download.")
au("Run this from OpenOS, not a bare Lua interpreter.")return end;local aM=bA()
if not aM then
ay("No Internet Card found on this computer.")
au("Craft one (Tier 1 is enough) and place it in this computer or")
au("server, or install from a physical disk with install.lua instead.")return end;aB("Internet Card found")print()local aA=aG.positional;local aC,aD=bd,be
if
aA[1]then local a,b=aA[1]:match("^([^/]+)/(.+)$")if
a and b and aS(a)and aS(b)then aC,aD=a,b else
au("Ignoring malformed owner/repo argument: "..tostring(aA[1]))end end;local aV=bw
if aA[2]then if aS(aA[2])then aV={aA[2]}else
au("Ignoring malformed branch argument: "..tostring(aA[2]))end end;local bk=bz
if aA[3]~=nil then if aA[3]==""or aS(aA[3])then bk={aA[3]}else
au(
"Ignoring malformed subdir argument: "..tostring(aA[3]))end end;aB("Repository: "..aC.."/"..aD)print()
if not
bt("Download TOS from the internet and run the installer?")then print("Cancelled.")return end;print()av(0x00AAFF)
print("--- Locating release files ---")av(0xFFFFFF)local aJ,aH,aK
for b,a in ipairs(aV)do
for b,c in ipairs(bk)do local g=a..
(c~=""and("/"..c)or"")
io.write("  probing "..g.." ")local d=0;local f=aI.uptime()local function h()local k=aI.uptime()if k-f>=0.3 and d<40 then f=k;d=d+1
io.write(".")end end
local i=aU(aC,aD,a,c,"/tos/system_manifest.lua")local e,j=aT(aM,i,bj,h)io.write(" ")
if e and#e>0 then av(0x00FF00)
print("found")av(0xFFFFFF)aJ,aH,aK=a,c,e;break else av(0xAAAAAA)print("not there ("..
tostring(j)..")")av(0xFFFFFF)end end;if aK then break end end;print()
if not aK then
local a=aT(aM,aU(aC,aD,aV[1],"","/system_manifest.lua"),bj)
if a and#a>0 then
ay("This repo has a FLAT layout — no directory structure.")
au("system_manifest.lua is at the root, but the files it declares")
au("(/tos/kernel/init.lua and the rest) have no directories to live")
au("in. That cannot be installed from, and it cannot be repaired by")
au("downloading harder: TOS ships six separate init.lua files, and a")au("flat repo can only hold one of them.")
au("Fix: push the release tree WITH its directories (tos/, etc/,")au("usr/) to the repo, then re-run this script.")
return end
ay("Could not find a TOS release under "..aC.."/"..
aD.." on any of: "..table.concat(aV,", "))
au("If this is a fork or the layout changed, point at it directly:")
au("  bootstrap.lua "..aC.."/"..aD.." <branch> <subdir>")return end;local aN,bF=bC(aK)if not aN then
ay("Cannot parse the downloaded manifest: "..tostring(bF))return end
aB("Using "..
aC.."/"..
aD.."@"..aJ..
(
aH~=""and("/"..aH)or"").." ("..#aN.." files declared)")print()
local function bl(a)
local g={0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}local c=0xFFFFFFFF;local function d(h,i)
return((h>>i)| (h<< (32-i)))&c end;local f=#a
a=a.."\128"..string.rep("\0",(55-f)%64)..string.pack(">I8",
f*8)
local b={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}local e={}
for h=1,#a,64 do
for q=0,15 do e[q+1]=string.unpack(">I4",a,h+q*4)end;for q=17,64 do local r,s=e[q-15],e[q-2]
e[q]=(e[q-16]+
(d(r,7)~d(r,18)~ (r>>3))+e[q-7]+
(d(s,17)~d(s,19)~ (s>>10)))&c end
local i,k,l,o,j,m,n,p=b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8]
for q=1,64 do local r=
(p+ (d(j,6)~d(j,11)~d(j,25))+
((j&m)~ (~j&n))+g[q]+e[q])&c;local s=
((
d(i,2)~d(i,13)~d(i,22))+ ((i&k)~ (i&l)~ (k&l)))&c;p,n,m,j,o,l,k,i=n,m,j,(o+r)&c,l,k,i,
(r+s)&c end
b[1],b[2],b[3],b[4]=(b[1]+i)&c,(b[2]+k)&c,(b[3]+l)&c,(b[4]+o)&c
b[5],b[6],b[7],b[8]=(b[5]+j)&c,(b[6]+m)&c,(b[7]+n)&c,(b[8]+p)&c end;return
(string.format("%08x%08x%08x%08x%08x%08x%08x%08x",table.unpack(b)))end;local aW={}for b,a in ipairs(aN)do
if
type(a)=="table"and type(a.path)==aL and
type(a.hash)==aL and#a.hash==64 then aW[a.path]=a.hash:lower()end end
local bG={string=string,table=table,math=math,tonumber=tonumber,tostring=tostring,type=type,select=select,ipairs=ipairs,pairs=pairs,pcall=pcall,error=error,assert=assert,setmetatable=setmetatable}
local function bH(aK,a,b,c,d,e,f)if type(c)~="table"then
return nil,"this copy of bootstrap.lua is not from a release build"end
local i=a("/tos/system_manifest.sig")if not i then return nil,"the release has no signature"end
local j=load(i,"=signature","t",{})local k,g=false,nil;if j then k,g=pcall(j)end
if not k or type(g)~="table"or
type(g.sig)~=aL then return nil,"its signature cannot be read"end
if g.key~=b then return nil,"it is signed with a different key"end
local h={["kernel.process"]={yieldCooperative=f or function()end}}
local l={require=function(p)return
h[p]or error("verifier wants "..tostring(p))end}for p,q in pairs(d)do l[p]=q end
for q,p in
ipairs({{"kernel.sha512","/tos/kernel/sha512.lua"},{"kernel.curve25519field","/tos/kernel/curve25519field.lua"},{"kernel.ed25519","/tos/kernel/ed25519.lua"}})do local r=a(p[2])
if not r then return nil,"could not fetch "..p[2]end;if e(r)~=c[p[2]]then
return nil,p[2].." is not the file this bootstrap was built with"end
local t=load(r,"="..p[2],"t",l)local u,s=false,nil;if t then u,s=pcall(t)end;if not u or type(s)~="table"then return nil,
"the verifier did not load"end;h[p[1]]=s end
local function m(p)return
(p:gsub("%x%x",function(q)return string.char(tonumber(q,16))end))end
local n,o=pcall(h["kernel.ed25519"].verify,aK,m(g.sig),m(b))if n and o then return true end
return nil,"its signature does not match its manifest"end
do local b=aC==bd and aD==be and aJ=="main"
io.write("  checking the publisher's signature... ")
local c,a=bH(aK,function(d)return aT(aM,aU(aC,aD,aJ,aH,d))end,bx,by,bG,bl,function()
aI.pullSignal(0)end)
if c then av(0x00FF00)print("valid")av(0xFFFFFF)
aB("This release is the one the publisher signed.")elseif b and not aG.allowUnsigned then av(0xFF0000)print("REFUSED")
av(0xFFFFFF)
ay("This release cannot be trusted: "..tostring(a)..".")
ay("Nothing was downloaded or installed. Try again later: a release")
ay("is signed by hand. --allow-unsigned goes ahead anyway, and then")ay("nothing vouches for what this machine runs.")
return else av(0xFFFF00)print("none")av(0xFFFFFF)
au("Not the publisher's signed release: "..
tostring(a)..".")
au("Nothing vouches for this code but the place it came from.")end;print()end;local bI,bm={hex=bl},next(aW)~=nil
if bm then local a=0;for b in pairs(aW)do a=a+1 end
aB(a..

" of "..#aN.." files carry a digest and will be verified")print()else
au("This release ships no digests, so downloads cannot be verified.")print()end
local function aX(a)local e,b=pcall(ax.get,a)if not e or not b then return nil end
local f,c=pcall(b.spaceTotal)local g,d=pcall(b.spaceUsed)
if
not(f and g)or type(c)~="number"or type(d)~="number"then return nil end;if c<=0 then return nil end;return c-d end
local function aO(a)return string.format("%.0f KB",a/1024)end
local function aP(a)if not ax.exists(a)then return true end
if ax.isDirectory(a)then local c={}
local e,d=pcall(ax.list,a)if e and d then
if type(d)=="function"then for f in d do c[#c+1]=f end elseif type(d)=="table"then for g,f in
ipairs(d)do c[#c+1]=f end end end;for g,f in
ipairs(c)do
local h=a.."/"..tostring(f):gsub("/$","")aP(h)end end;local b=pcall(ax.remove,a)
return b and not ax.exists(a)end;local bg=1400*1024;local aw,aQ
do local a={}if ax.isDirectory("/tmp")then
a[#a+1]={"/tmp/tos-netinstall","/tmp"}end;if ax.isDirectory("/home")then
a[#a+1]={"/home/tos-netinstall","/home"}end
a[#a+1]={"/tos-netinstall-tmp","/"}local c,b;for e,d in ipairs(a)do local f=aX(d[2])
if f and(not b or f>b)then c,b=d[1],f end end
aw=c or
((ax.isDirectory("/tmp")and
"/tmp/tos-netinstall")or"/tos-netinstall-tmp")aQ=b
if aQ then
aB("Staging in "..aw.." ("..aO(aQ).." free)")
if aQ<bg then
au("That is under the ~"..aO(bg).." the release needs.")
au("The download will likely run out of space partway through.")
au("Free some room, or install from a disk instead. Continuing.")end end end;if ax.exists(aw)then
au("Removing a stale staging directory from a previous run: "..aw)aP(aw)end;if not
ax.makeDirectory(aw)then
ay("Cannot create staging directory: "..aw)return end;local aE,aY={},{}for b,a in ipairs(aN)do
if

type(a)=="table"and type(a.path)==aL and not aY[a.path]then aY[a.path]=true;aE[#aE+1]=a.path end end;if not aY[br]then aE[#
aE+1]=br end
if not aY[bq]then aE[#aE+1]=bq end;av(0x00AAFF)
print("--- Downloading "..#aE.." files ---")av(0xFFFFFF)local aZ,aF=0,0;local az={}local bn=false
for b,a in ipairs(aE)do
local d=a:match("^(.+)/[^/]+$")if d then local g=""
for h in d:gmatch("[^/]+")do g=g.."/"..h;if not ax.isDirectory(aw..g)then ax.makeDirectory(
aw..g)end end end
local f=aU(aC,aD,aJ,aH,a)local c,e=aT(aM,f)
if c then local g=bm and aW[a]or nil;if
g and bI.hex(c)~=g then aF=aF+1
az[#az+1]=a..": DIGEST MISMATCH (corrupt or tampered)"c=nil end end
if c then local g=io.open(aw..a,"w")
if g then g:write(c)g:close()aZ=aZ+1 else
aF=aF+1;local h=aX(aw)
if h and h<4096 then bn=true;az[#az+1]=a..
": OUT OF SPACE ("..aO(h).." free)"break end
az[#az+1]=a..": cannot open staging file for write"end elseif e==nil then else
if a==bq then else aF=aF+1;az[#az+1]=a..": "..tostring(e)end end;if b%10 ==0 or b==#aE then
io.write(string.format("\r  %d/%d files (%d failed)   ",b,#aE,aF))end end;print()print()
if bn then
ay("Ran out of space in "..
aw.." after "..aZ.." file(s).")print()
au("The release needs roughly "..aO(bg).." of scratch space, and")
au("this filesystem does not have it. Nothing was written outside")
au(aw..", and the target disk was never touched.")print()au("Options, in the order worth trying:")
au("  - Install from a floppy or install disk: no scratch space needed.")
au("  - Free space on a larger drive; bootstrap stages wherever there")
au("    is the most room, so it will pick it up automatically.")
au("  - On a machine with only a small tmpfs, an installed HDD with")
au("    free space is enough -- it does not have to be the target.")aP(aw)return end
if aF==0 then aB("Downloaded "..aZ.." files")else ay(aF..
" file(s) failed to download:")for a=1,math.min(5,#az)do au(
"  "..az[a])end;if#az>5 then
au("  (+".. (#az-5)..bp)end end;print()
do local a={}
for c,b in ipairs(az)do if not b:find("DIGEST MISMATCH",1,true)then a[#a+
1]=b end end
if#a>0 then
ay(#a.." file(s) never made it into the staging tree:")for b=1,math.min(8,#a)do au("  "..a[b])end;if#a>8 then au("  (+"..
(#a-8)..bp)end;print()
ay("Refusing to install an incomplete release.")
au("Installing anyway would produce a machine that boots and is")
au("quietly missing pieces -- that is how a release once shipped")
au("without the file holding most of the shell's commands.")print()
au("Retry: these are usually transient. If the same file fails")
au("every time, the release is broken; install from a disk and")au("report which file.")aP(aw)return end end
do local a={}for c,b in ipairs(az)do
if b:find("DIGEST MISMATCH",1,true)then a[#a+1]=b end end
if#a>0 then
ay(#a..
" file(s) did not match the digest the manifest declares:")for b=1,math.min(8,#a)do au("  "..a[b])end;if#a>8 then au("  (+"..
(#a-8)..bp)end;print()
ay(
"Refusing to install. Nothing was written outside "..aw..".")
au("Most likely: a release was published in the last few minutes and")
au("the download caught it half-updated — the host serves cached files")
au("for a while after a push. Wait five minutes and retry; that fixes")
au("this on its own, and no wait is needed for a disk install.")print()
au("If it repeats after that, treat it as real: a mangling proxy or a")
au("truncated transfer looks the same as tampering from here, and so")
au("does a release that is not what it claims. Install from a disk.")return end end;local a_=aw..br
local bJ=ax.exists(a_)and(ax.size(a_)or 0)>0
if not bJ then
ay("install.lua did not download successfully — nothing to hand off to.")
au("Retry, or point at the release directly if the layout is nonstandard:")
au("  bootstrap.lua "..
aC.."/"..aD.." "..
aJ.. (aH~=""and(" "..aH)or" \"\""))return end;av(0x00AAFF)
print("--- Handing off to install.lua ---")av(0xFFFFFF)aB("Staged at "..aw)print()
local bo,bK=loadfile(a_)
if not bo then
ay("Downloaded install.lua does not parse: "..tostring(bK))
au("The file may have been corrupted in transit — try again.")return end
local function bL(a)if type(a)~=aL or a==""then return nil end;local b=a;if
b:sub(1,1)~="/"then b="/"..b end;if b:find("/",2,true)then return nil end;return b end
do local a=bL((arg and arg[0])or nil)
if a and
ax.exists(a)and not ax.isDirectory(a)then
if
pcall(ax.remove,a)and not ax.exists(a)then
aB("Removed "..
a.." (re-download it with the same one-liner)")else
au("Could not remove "..a.."; delete it when convenient.")end end end;local bM,bN=pcall(bo,aw,"--temporary")
if not bM then
ay("install.lua exited with an error: "..
tostring(bN))au("You can retry it directly:")
au("  "..a_.." "..aw)
au("Leaving the staging tree in place so a retry needs no re-download.")return end
do local a=aQ and aX(aw)
if aP(aw)then local b=aX("/")if b and a then
aB("Removed the staging copy ("..
aO(b).." free now)")else
aB("Removed the staging copy from "..aw)end else
au(
"Could not remove the staging copy at "..aw..".")
au("It is a full second copy of the release; delete it to reclaim")au("the space: rm -r "..aw)end end