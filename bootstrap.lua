local aS,bf,bg,bh="string","/install.lua","/bios.lua"," more)"
local aT=require("component")local az=require("computer")local aI=require("term")local aq=nil;pcall(function()
aq=require("filesystem")end)
local aU=aT.gpu;local function ao(a)
if aU and aU.setForeground then pcall(aU.setForeground,a)end end;local function au(a)ao(0x00FF00)
print("  + "..a)ao(0xFFFFFF)end;local function an(a)ao(0xFFFF00)
print("  ! "..a)ao(0xFFFFFF)end;local function ar(a)ao(0xFF0000)
print("  X "..a)ao(0xFFFFFF)end
local function bi(c,b,a)ao(0xFFFF00)
io.write(c)if b then ao(0xAAAAAA)
io.write(" ["..table.concat(b,"/").."]")end;if a then ao(0x888888)
io.write(" (default: "..a..")")end;ao(0xFFFFFF)io.write(": ")local d
if aI and
aI.read then local e,f=pcall(aI.read)if e then d=f
if d then d=d:gsub("\n$","")end end else d=io.read()end;if not d or d==""then return a end;return d end
local function bj(a)local b=bi(a,{"y","n"},"y")return b and
(b:lower()=="y"or b:lower()=="yes")end
local function aV(a)if os.sleep then pcall(os.sleep,a)end end;local aY="1.0.0"
local bk={"████████  ████████  ████████","   ██     ██    ██  ██      ","   ██     ██    ██  ████████","   ██     ██    ██        ██","   ██     ████████  ████████"}
local function bl()ao(0x00AAFF)for b,a in ipairs(bk)do print("   "..a)end
ao(0xFFFFFF)print()ao(0x00FF66)print("   Strata Systems LLC")
ao(0xFFFFFF)ao(0xAAAAAA)
print("   Terminal Operating System — Network Bootstrap v"..aY)ao(0xFFFFFF)print()end;local bm="Evan450"local bn="TOS-Terminal-Operating-System-"
local bo={"main","master"}local bp={"","TOS-Release"}
local function aJ(a)return
type(a)==aS and a~=""and
not a:find("[%c]")and a:match("^[%w%.%-_/]+$")~=nil end
local function bq()local a=aT.list("internet")()if not a then return nil end
local b,c=pcall(aT.proxy,a)if not b then return nil end;return c end;local aZ=256*1024;local aW=20;local br=3;local a_=2
local function aK(c,d,a,b)a=a or br
local function e()if b then pcall(b)end end
for f=1,a do
local h,g,i=pcall(c.request,d,nil,{["user-agent"]="TOS-Bootstrap/"..aY})
if h and g then local m,n,j={},0,nil;local k,l=false,nil;local o=az.uptime()+aW
while true do
local r,p,q=pcall(g.read)if not r then k=true;l=tostring(p)break end;if g.response and not j then
local t,s=pcall(g.response)if t and s then j=s end end;if p==nil then if q then k=true
l=tostring(q)end;break end
if#p>0 then n=n+#p
if n>aZ then k=true;l=
"response exceeds "..aZ.." bytes"break end;m[#m+1]=p;o=az.uptime()+aW else e()aV(0)end
if az.uptime()>o then k=true;l="timed out after "..aW.."s"break end end;pcall(function()g.close()end)if not k then if j and j~=200 then return nil,"HTTP "..
tostring(j),j end;return table.concat(m),
nil,j end;if f<a then
aV(1)end else if f<a then aV(1)end end end;return nil,"request failed after "..a.." attempt(s)"end
local function aL(b,c,d,a,e)local f=(a~=""and("/"..a)or"")return
string.format("https://raw.githubusercontent.com/%s/%s/%s%s%s",b,c,d,f,e)end
local function bs(a)
if#a>256*1024 then return nil,"manifest exceeds 256 KB sanity cap"end;local c,d=load(a,"=manifest","t",{})if not c then return nil,
"manifest parse error: "..tostring(d)end;local e,b=pcall(c)
if
not e then return nil,"manifest run error: "..tostring(b)end
if type(b)~="table"then return nil,"manifest did not return a table"end;return b end;aI.clear()bl()
if not aq then
ar("OpenOS filesystem library unavailable — cannot stage a download.")
an("Run this from OpenOS, not a bare Lua interpreter.")return end;local aB=bq()
if not aB then
ar("No Internet Card found on this computer.")
an("Craft one (Tier 1 is enough) and place it in this computer or")
an("server, or install from a physical disk with install.lua instead.")return end;au("Internet Card found")print()local at={...}local av,aw=bm,bn
if at[1]then
local a,b=at[1]:match("^([^/]+)/(.+)$")if a and b and aJ(a)and aJ(b)then av,aw=a,b else
an("Ignoring malformed owner/repo argument: "..
tostring(at[1]))end end;local aM=bo
if at[2]then if aJ(at[2])then aM={at[2]}else
an("Ignoring malformed branch argument: "..tostring(at[2]))end end;local ba=bp
if at[3]~=nil then if at[3]==""or aJ(at[3])then ba={at[3]}else
an(
"Ignoring malformed subdir argument: "..tostring(at[3]))end end;au("Repository: "..av.."/"..aw)print()
if not
bj("Download TOS from the internet and install it here?")then print("Cancelled.")return end;print()ao(0x00AAFF)
print("--- Locating release files ---")ao(0xFFFFFF)local aC,aA,aN
for b,a in ipairs(aM)do
for b,c in ipairs(ba)do local g=a..
(c~=""and("/"..c)or"")
io.write("  probing "..g.." ")local d=0;local f=az.uptime()local function h()local k=az.uptime()if k-f>=0.3 and d<40 then f=k;d=d+1
io.write(".")end end
local i=aL(av,aw,a,c,"/tos/system_manifest.lua")local e,j=aK(aB,i,a_,h)io.write(" ")
if e and#e>0 then ao(0x00FF00)
print("found")ao(0xFFFFFF)aC,aA,aN=a,c,e;break else ao(0xAAAAAA)print("not there ("..
tostring(j)..")")ao(0xFFFFFF)end end;if aN then break end end;print()
if not aN then
local a=aK(aB,aL(av,aw,aM[1],"","/system_manifest.lua"),a_)
if a and#a>0 then
ar("This repo has a FLAT layout — no directory structure.")
an("system_manifest.lua is at the root, but the files it declares")
an("(/tos/kernel/init.lua and the rest) have no directories to live")
an("in. That cannot be installed from, and it cannot be repaired by")
an("downloading harder: TOS ships six separate init.lua files, and a")an("flat repo can only hold one of them.")
an("Fix: push the release tree WITH its directories (tos/, etc/,")an("usr/) to the repo, then re-run this script.")
return end
ar("Could not find a TOS release under "..av.."/"..
aw.." on any of: "..table.concat(aM,", "))
an("If this is a fork or the layout changed, point at it directly:")
an("  bootstrap.lua "..av.."/"..aw.." <branch> <subdir>")return end;local aD,bt=bs(aN)if not aD then
ar("Cannot parse the downloaded manifest: "..tostring(bt))return end
au("Using "..
av.."/"..
aw.."@"..aC..
(
aA~=""and("/"..aA)or"").." ("..#aD.." files declared)")print()local aE={}for b,a in ipairs(aD)do
if

type(a)=="table"and type(a.path)==aS and type(a.hash)==aS and#a.hash==64 then aE[a.path]=a.hash:lower()end end
local bu={string=string,table=table,math=math,tonumber=tonumber,tostring=tostring,type=type,select=select,ipairs=ipairs,pairs=pairs,error=error,assert=assert,setmetatable=setmetatable}local bb,bc=nil,false
do local a=0;for b in pairs(aE)do a=a+1 end
if a==0 then
an("This release ships no digests — downloads cannot be verified.")
an("Older releases predate them; the install will still work, but a")an("corrupted transfer will not be caught here.")
print()else io.write("  fetching the hasher ")
local b="/tos/kernel/sha256.lua"local c,e=0,az.uptime()
local d=aK(aB,aL(av,aw,aC,aA,b),nil,function()local f=az.uptime()if
f-e>=0.3 and c<40 then e=f;c=c+1;io.write(".")end end)io.write(" ")
if not d then ao(0xFFFF00)print("unavailable")
ao(0xFFFFFF)
an("Could not fetch "..b.."; downloads will NOT be verified.")print()else local h=load(d,"=sha256","t",bu)local g,f=false,nil
if h then g,f=pcall(h)end
if
g and type(f)=="table"and type(f.hex)=="function"then local i,j=pcall(f.hex,"abc")
if not
(i and
j=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")then g=false;f=nil end end
if g and type(f)=="table"and f.hex then
if
aE[b]and f.hex(d)~=aE[b]then ao(0xFF0000)print("CORRUPT")ao(0xFFFFFF)
ar("sha256.lua does not match its own manifest entry.")
ar("Refusing to install from a repository that is inconsistent")
ar("with itself. Retry; if it persists, the release is broken.")return end;bb,bc=f,true;ao(0x00FF00)print("ok")ao(0xFFFFFF)
au(a.." of "..#aD..
" files carry a digest and will be verified")print()else ao(0xFFFF00)print("unusable")ao(0xFFFFFF)
an("sha256.lua did not load; downloads will NOT be verified.")print()end end end end
local function aO(a)local e,b=pcall(aq.get,a)if not e or not b then return nil end
local f,c=pcall(b.spaceTotal)local g,d=pcall(b.spaceUsed)
if
not(f and g)or type(c)~="number"or type(d)~="number"then return nil end;if c<=0 then return nil end;return c-d end
local function aF(a)return string.format("%.0f KB",a/1024)end
local function aG(a)if not aq.exists(a)then return true end
if aq.isDirectory(a)then local c={}
local e,d=pcall(aq.list,a)if e and d then
if type(d)=="function"then for f in d do c[#c+1]=f end elseif type(d)=="table"then for g,f in
ipairs(d)do c[#c+1]=f end end end;for g,f in
ipairs(c)do
local h=a.."/"..tostring(f):gsub("/$","")aG(h)end end;local b=pcall(aq.remove,a)
return b and not aq.exists(a)end;local aX=1400*1024;local ap,aH
do local a={}if aq.isDirectory("/tmp")then
a[#a+1]={"/tmp/tos-netinstall","/tmp"}end;if aq.isDirectory("/home")then
a[#a+1]={"/home/tos-netinstall","/home"}end
a[#a+1]={"/tos-netinstall-tmp","/"}local c,b;for e,d in ipairs(a)do local f=aO(d[2])
if f and(not b or f>b)then c,b=d[1],f end end
ap=c or
((aq.isDirectory("/tmp")and
"/tmp/tos-netinstall")or"/tos-netinstall-tmp")aH=b
if aH then
au("Staging in "..ap.." ("..aF(aH).." free)")
if aH<aX then
an("That is under the ~"..aF(aX).." the release needs.")
an("The download will likely run out of space partway through.")
an("Free some room, or install from a disk instead. Continuing.")end end end;if aq.exists(ap)then
an("Removing a stale staging directory from a previous run: "..ap)aG(ap)end;if not
aq.makeDirectory(ap)then
ar("Cannot create staging directory: "..ap)return end;local ax,aP={},{}for b,a in ipairs(aD)do
if

type(a)=="table"and type(a.path)==aS and not aP[a.path]then aP[a.path]=true;ax[#ax+1]=a.path end end;if not aP[bf]then ax[#
ax+1]=bf end
if not aP[bg]then ax[#ax+1]=bg end;ao(0x00AAFF)
print("--- Downloading "..#ax.." files ---")ao(0xFFFFFF)local aQ,ay=0,0;local as={}local bd=false
for b,a in ipairs(ax)do
local d=a:match("^(.+)/[^/]+$")if d then local g=""
for h in d:gmatch("[^/]+")do g=g.."/"..h;if not aq.isDirectory(ap..g)then aq.makeDirectory(
ap..g)end end end
local f=aL(av,aw,aC,aA,a)local c,e=aK(aB,f)
if c then local g=bc and aE[a]or nil;if
g and bb.hex(c)~=g then ay=ay+1
as[#as+1]=a..": DIGEST MISMATCH (corrupt or tampered)"c=nil end end
if c then local g=io.open(ap..a,"w")
if g then g:write(c)g:close()aQ=aQ+1 else
ay=ay+1;local h=aO(ap)
if h and h<4096 then bd=true;as[#as+1]=a..
": OUT OF SPACE ("..aF(h).." free)"break end
as[#as+1]=a..": cannot open staging file for write"end elseif e==nil then else
if a==bg then else ay=ay+1;as[#as+1]=a..": "..tostring(e)end end;if b%10 ==0 or b==#ax then
io.write(string.format("\r  %d/%d files (%d failed)   ",b,#ax,ay))end end;print()print()
if bd then
ar("Ran out of space in "..
ap.." after "..aQ.." file(s).")print()
an("The release needs roughly "..aF(aX).." of scratch space, and")
an("this filesystem does not have it. Nothing was written outside")
an(ap..", and the target disk was never touched.")print()an("Options, in the order worth trying:")
an("  - Install from a floppy or install disk: no scratch space needed.")
an("  - Free space on a larger drive; bootstrap stages wherever there")
an("    is the most room, so it will pick it up automatically.")
an("  - On a machine with only a small tmpfs, an installed HDD with")
an("    free space is enough -- it does not have to be the target.")aG(ap)return end
if ay==0 then au("Downloaded "..aQ.." files")else ar(ay..
" file(s) failed to download:")for a=1,math.min(5,#as)do an(
"  "..as[a])end;if#as>5 then
an("  (+".. (#as-5)..bh)end end;print()
do local a={}
for c,b in ipairs(as)do if not b:find("DIGEST MISMATCH",1,true)then a[#a+
1]=b end end
if#a>0 then
ar(#a.." file(s) never made it into the staging tree:")for b=1,math.min(8,#a)do an("  "..a[b])end;if#a>8 then an("  (+"..
(#a-8)..bh)end;print()
ar("Refusing to install an incomplete release.")
an("Installing anyway would produce a machine that boots and is")
an("quietly missing pieces -- that is how a release once shipped")
an("without the file holding most of the shell's commands.")print()
an("Retry: these are usually transient. If the same file fails")
an("every time, the release is broken; install from a disk and")an("report which file.")aG(ap)return end end
do local a={}for c,b in ipairs(as)do
if b:find("DIGEST MISMATCH",1,true)then a[#a+1]=b end end
if#a>0 then
ar(#a..
" file(s) did not match the digest the manifest declares:")for b=1,math.min(8,#a)do an("  "..a[b])end;if#a>8 then an("  (+"..
(#a-8)..bh)end;print()
ar(
"Refusing to install. Nothing was written outside "..ap..".")
an("Most likely: a release was published in the last few minutes and")
an("the download caught it half-updated — the host serves cached files")
an("for a while after a push. Wait five minutes and retry; that fixes")
an("this on its own, and no wait is needed for a disk install.")print()
an("If it repeats after that, treat it as real: a mangling proxy or a")
an("truncated transfer looks the same as tampering from here, and so")
an("does a release that is not what it claims. Install from a disk.")return end end;local aR=ap..bf
local bv=aq.exists(aR)and(aq.size(aR)or 0)>0
if not bv then
ar("install.lua did not download successfully — nothing to hand off to.")
an("Retry, or point at the release directly if the layout is nonstandard:")
an("  bootstrap.lua "..
av.."/"..aw.." "..
aC.. (aA~=""and(" "..aA)or" \"\""))return end;ao(0x00AAFF)
print("--- Handing off to install.lua ---")ao(0xFFFFFF)au("Staged at "..ap)print()
local be,bw=loadfile(aR)
if not be then
ar("Downloaded install.lua does not parse: "..tostring(bw))
an("The file may have been corrupted in transit — try again.")return end;local bx,by=pcall(be,ap)
if not bx then
ar("install.lua exited with an error: "..tostring(by))an("You can retry it directly:")
an("  "..aR.." "..ap)
an("Leaving the staging tree in place so a retry needs no re-download.")return end
do local a=aH and aO(ap)
if aG(ap)then local b=aO("/")if b and a then
au("Removed the staging copy ("..
aF(b).." free now)")else
au("Removed the staging copy from "..ap)end else
an(
"Could not remove the staging copy at "..ap..".")
an("It is a full second copy of the release; delete it to reclaim")an("the space: rm -r "..ap)end end
local function bz(a)if type(a)~=aS or a==""then return nil end;local b=a;if
b:sub(1,1)~="/"then b="/"..b end;if b:find("/",2,true)then return nil end;return b end
do local a=bz((arg and arg[0])or nil)
if a and
aq.exists(a)and not aq.isDirectory(a)then
if
pcall(aq.remove,a)and not aq.exists(a)then
au("Removed "..
a.." (re-download it with the same one-liner)")else
an("Could not remove "..a.."; delete it when convenient.")end end end