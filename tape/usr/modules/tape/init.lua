
local bb,av,aP,bc,bd,be,aQ=" %-6s  %-8s  %s","No tape inserted.","Truncated header","encrypt","tape_drive","vault module unavailable","volume"local aA=require("component")local aw=require("computer")local ar=fs
local aB={}local ay="TOS\x01"local az="TOS\x00"local aJ=1;local bf=1;local au=8192;local aR="TVAULT1\0"
local aS="TVAULT2\0"local aK=114;local aT=47
local function at(a)if a then for c in aA.list(bd)do
if c:sub(1,#a)==a then return aA.proxy(c)end end
return nil,"No tape drive matching: "..a end
local b=aA.list(bd)()if b then return aA.proxy(b)end;return nil,"No tape drive found"end;local aF={}local function aU(a,b,c)local d=a and a.address;if not d then return end;aF[d]=aF[d]or{}
aF[d][b]=c end
local function aG(a,b)
local c=a and a.address;local d=c and aF[c]return d and d[b]or nil end;local function bg(a)
return string.char(math.floor(a/256)%256,a%256)end;local function aL(a)
return a:byte(1)*256+a:byte(2)end
local function aV(a)
local b=math.floor(a/16777216)%256;local c=math.floor(a/65536)%256
local d=math.floor(a/256)%256;local e=a%256;return string.char(b,c,d,e)end
local function aH(a)return
a:byte(1)*16777216+a:byte(2)*65536+a:byte(3)*256+a:byte(4)end;local function aW(a)local b=0
for c=1,#a do b=(b+a:byte(c))%4294967296 end;return b end
local function as(a,b)local d={}local c=b
while c>0 do
local e=a.read(math.min(c,au))if not e or#e==0 then return nil end;d[#d+1]=e;c=c-#e end;return table.concat(d)end;local function aC(b,a)local c=0
while c<#a do local d=a:sub(c+1,c+au)b.write(d)c=c+#d end end;local function aq(a)
a.seek(-a.getSize())end
local function aD(a,b)aq(a)if b>0 then a.seek(b)end end
local function ap(a)
if a>=1048576 then return string.format("%.1fMB",a/1048576)elseif a>=1024 then return string.format("%.1fKB",
a/1024)end;return a.."B"end;local function aX(a)return a/262144 end
local function aE(a)local b=aX(a)if b>=1 then
return string.format("%s (%d-minute tape)",ap(a),math.floor(
b+0.5))end;return ap(a)end;local aM=16;local ax=4;local function aY(a,b)return aM+a+b end
local function aZ(b,a)if
#b>1 and a:sub(1,#b)==b then a=a:sub(#b+1)end;a=a:gsub("^/+","")if a==""then
a="."end;return a end
local function aN(a)aq(a)local b={used=0,files=0,dirs=0,dataBytes=0}
while true do local c=as(a,4)if
not c or#c<4 then break end;if c==az then b.used=b.used+ax;break end
if c~=ay then break end;local e=as(a,2)if not e then break end;local j=e:byte(2)local f=as(a,2)
if not f then break end;local g=aL(f)local k=as(a,g)if not k then break end;local h=as(a,4)if not h then break end
local d=aH(h)as(a,4)local l=(j%2)==1;local i=aM+g
if l then b.dirs=b.dirs+1;b.used=b.used+i else b.files=
b.files+1;b.dataBytes=b.dataBytes+d;b.used=b.used+i+d end;if d>0 then a.seek(d)end;if(b.files+b.dirs)%10 ==0 then
aw.pullSignal(0)end end;aq(a)return b end
local function bh(b,a)local c=0
for d in aA.list(bd)do c=c+1;local e=aA.proxy(d)local f=e.isReady()
local g=f and(e.getLabel()or
"(unlabeled)")or"(no tape)"local h=e.getState()
a(string.format(" %d. %s",c,d:sub(1,8)),0xFFFF00)
if f then local i=e.getSize()
a(string.format("    Label: %s  Capacity: %s  State: %s",g,aE(i),h),0xFFFFFF)else
a(string.format("    %s  State: %s",g,h),0xFFFFFF)end end;if c==0 then a("No tape drives found.",0xFF6600)
a("Install a Computronics Tape Drive to use this module.",0xAAAAAA)end end
local function bi(b,a)local c,f=at(b[2])if not c then a(f,0xFF0000)return end;if
not c.isReady()then
a("No tape inserted in drive "..c.address:sub(1,8),0xFF6600)return end;local d=c.getSize()
local g=aX(d)a(" Tape Drive Info",0xFFFF00)
a("  Address:  "..c.address:sub(1,8),0xFFFFFF)
a("  Label:    ".. (c.getLabel()or"(none)"),0xFFFFFF)a("  Capacity: "..aE(d),0xFFFFFF)
a("  Bytes:    "..d,0xAAAAAA)
a("  State:    "..c.getState(),0xFFFFFF)aq(c)local e=as(c,4)aq(c)
if e==ay then
a("  Format:   TOS archive",0x00FF00)local h=aN(c)local i=d-h.used;local j=h.used*100/d;a("",0xFFFFFF)
a("  Archive:",0xFFFF00)
a(string.format("    Files:    %d files, %d directories",h.files,h.dirs),0xFFFFFF)
a(string.format("    Data:     %s (file content)",ap(h.dataBytes)),0xFFFFFF)
a(string.format("    Overhead: %s (headers + index)",ap(h.used-h.dataBytes)),0xAAAAAA)
a(string.format("    Used:     %s (%.1f%%)",ap(h.used),j),0xFFFFFF)
a(string.format("    Free:     %s (%.1f%%)",ap(i),100-j),
i<d*0.1 and 0xFF6600 or 0x00FF00)elseif e==az then a("  Format:   TOS archive (empty)",0xAAAAAA)
local h=d-ax
a(string.format("  Free:     %s (entire tape)",ap(h)),0x00FF00)elseif e then a("  Format:   Unknown / raw data",0xAAAAAA)
a("  Use 'tape dump 0 64' to inspect contents.",0xAAAAAA)else a("  Format:   Blank",0xAAAAAA)
a(string.format("  Free:     %s (entire tape)",ap(d)),0x00FF00)end end
local function bj(b,a)local c,d=at(nil)if not c then a(d,0xFF0000)return end;if not c.isReady()then
a(av,0xFF6600)return end
if b[2]then local e=table.concat(b," ",2)
c.setLabel(e)a("Label set: "..e,0x00FF00)else local e=c.getLabel()if
e and e~=""then a("Current label: "..e,0xFFFFFF)else
a("Tape has no label. Use: tape label <name>",0xAAAAAA)end end end
local function bk(b,a)local c=b[2]
if not c then
a("Usage: tape store <path> [--overwrite]",0xAAAAAA)
a("  Archives a file or directory to the tape.",0xAAAAAA)
a("  Appends after existing archive data by default.",0xAAAAAA)
a("  Use --overwrite to replace the entire archive.",0xAAAAAA)return end;local p=false;local l=nil
for v=2,#b do if b[v]=="--overwrite"then p=true else l=b[v]end end;if l then c=l end;if not c or c==""then
a("Usage: tape store <path> [--overwrite]",0xAAAAAA)return end;local d,u=at(nil)if not d then
a(u,0xFF0000)return end
if not d.isReady()then a(av,0xFF6600)return end;d.stop()c=ar.normalize(c)if not ar.exists(c)then
a("Path not found: "..c,0xFF0000)return end;local f={}local m=c
local function q(v)
f[#f+1]={path=v,isDir=true}local w=ar.list(v)if not w then return end
for y,x in ipairs(w)do local z=ar.join(v,x)if
ar.isDirectory(z)then q(z)else f[#f+1]={path=z,isDir=false}end end end;if ar.isDirectory(c)then q(c)else f[#f+1]={path=c,isDir=false}
m=ar.split(c)or"/"end;local h=d.getSize()local n=0;local g=0
if not p then
aq(d)local v=as(d,4)aq(d)
if v==ay then local w=aN(d)
if w.used>ax then g=w.used-ax;n=g
a(string.format("Existing archive: %d files, %d dirs (%s)",w.files,w.dirs,ap(w.used)),0x00AAFF)a("Appending after existing entries...",0xAAAAAA)end elseif v==az then g=0;n=0 end end;local e=ax;local r=0;local k=0;for w,v in ipairs(f)do local x=aZ(m,v.path)
if v.isDir then e=e+aY(#x,0)else local y=
ar.size(v.path)or 0;e=e+aY(#x,y)k=k+y;r=r+1 end end
local o=h-g
a(string.format("Archiving %d entries from %s",#f,c),0x00AAFF)
a(string.format("  New data size:  %s (%s data + %s overhead)",ap(e),ap(k),ap(e-k-ax)),0xAAAAAA)if g>0 then
a(string.format("  Existing data:  %s",ap(g)),0xAAAAAA)end
a(string.format("  Tape capacity:  %s",aE(h)),0xAAAAAA)
if e>o then local v=e-o
a(string.format("  WARNING: Data exceeds available space by %s!",ap(v)),0xFF6600)
a("  Some files will not fit. Writing what we can...",0xFF6600)else local v=o-e;local w=g+e
a(string.format("  After write:    %s free (%.1f%% used)",ap(v),w*100/h),0x00FF00)end;a("",0xFFFFFF)aD(d,n)local i=0;local j=0
for w,v in ipairs(f)do local B=aZ(m,v.path)local C=
v.isDir and bf or 0;local x=""if not v.isDir then
x=ar.readFile(v.path)or""j=j+1 end;local y=B;local z=ay..
string.char(aJ)..string.char(C)..
bg(#y)..y..aV(#x)..aV(aW(x))
local A=#z+#x;if g+i+A+ax>h then
a("WARNING: Tape full after "..j.." files.",0xFF6600)break end;aC(d,z)
if#x>0 then aC(d,x)end;i=i+A;if j%5 ==0 then aw.pullSignal(0)end end;aC(d,az)i=i+ax;aq(d)local s=g+i;local t=h-s
a(string.format("Done: %d files, %s written",j,ap(i)),0x00FF00)
a(string.format("Tape: %s free (%.1f%% used)",ap(t),s*100/h),t<h*0.1 and
0xFF6600 or 0x00FF00)end
local function bl(b,a)local d=b[2]or"/home"d=ar.normalize(d)local c,h=at(nil)if not c then
a(h,0xFF0000)return end
if not c.isReady()then a(av,0xFF6600)return end;c.stop()aq(c)
a("Restoring from tape to "..d.." ...",0x00AAFF)local f=0;local g=0;local e=0
while true do local m=as(c,4)if not m or#m<4 then
a("Unexpected end of tape",0xFF6600)break end;if m==az then break end;if m~=ay then
a(
"Not a TOS archive (bad magic at byte "..e..")",0xFF0000)aq(c)return end;local n=as(c,2)if not n then
a(aP,0xFF0000)break end;local p=n:byte(1)local v=n:byte(2)if p>aJ then
a("Archive version "..p..
" not supported (max "..aJ..")",0xFF0000)aq(c)return end;local q=as(c,2)if not q then
a(aP,0xFF0000)break end;local r=aL(q)local j=as(c,r)if not j then
a("Truncated path",0xFF0000)break end;local s=as(c,4)
if not s then a(aP,0xFF0000)break end;local o=aH(s)local t=as(c,4)if not t then a(aP,0xFF0000)break end
local u=aH(t)e=e+4+2+2+r+4+4;local w=(v%2)==1;if type(j)~="string"or
j==""then
a("Skipping entry with empty path",0xFF6600)break end;if j:find("\0",1,true)then a(
"REFUSING tainted path from tape: "..j,0xFF0000)
aq(c)return end;j=j:gsub("^/+","")if j==
""then j="."end
do local x=false;for y in j:gmatch("[^/\\]+")do
if y==".."then x=true;break end end;if x then
a("REFUSING traversal path from tape: "..j,0xFF0000)aq(c)return end end;local k=ar.join(d,j)local l=d;if l:sub(-1)~="/"then l=l.."/"end;if k~=d and k:sub(1,
#l)~=l then
a("REFUSING path that escapes destBase: "..k,0xFF0000)aq(c)return end
if w then if
not ar.exists(k)then ar.makeDirectory(k)end;g=g+1 else local x=""if o>0 then
x=as(c,o)
if not x then a("Truncated data for: "..j,0xFF0000)break end end;e=e+o;local z=aW(x)if z~=u then
a("CHECKSUM MISMATCH: "..j,0xFF6600)
a("  Expected: "..u.." Got: "..z,0xFF6600)end;local y=ar.split(k)
if
y and y~="/"and not ar.exists(y)then ar.makeDirectory(y)end;ar.writeFile(k,x)f=f+1 end;if(f+g)%5 ==0 then aw.pullSignal(0)end end;aq(c)local i=c.getSize()
a(string.format("Restored: %d files, %d dirs (%s read from %s tape)",f,g,ap(e),aE(i)),0x00FF00)end
local function bm(b,a)local c,k=at(nil)if not c then a(k,0xFF0000)return end;if not c.isReady()then
a(av,0xFF6600)return end;local e=c.getSize()c.stop()aq(c)
local i=as(c,4)
if i==az then a("Tape archive is empty.",0xAAAAAA)
a(string.format("Tape: %s available (%s)",ap(
e-ax),aE(e)),0x00FF00)aq(c)return end
if i~=ay then
a("Tape does not contain a TOS archive.",0xFF6600)
a("Use 'tape dump 0 64' to inspect raw data.",0xAAAAAA)aq(c)return end;aq(c)
a(string.format(bb,"Type","Size","Path"),0xFFFF00)a(string.rep("-",40),0xAAAAAA)local f=0;local g=0;local h=0;local d=0
while
true do local o=as(c,4)if not o or o==az then d=d+ax;break end;if o~=ay then break end
local q=as(c,2)if not q then break end;local v=q:byte(2)local r=as(c,2)if not r then break end;local s=aL(r)
local p=as(c,s)if not p then break end;local t=as(c,4)if not t then break end;local n=aH(t)as(c,4)
local w=(v%2)==1;local u=aM+s
if w then
a(string.format(bb,"DIR","",p),0x55FF55)g=g+1;d=d+u else
a(string.format(bb,"FILE",ap(n),p),0xFFFFFF)f=f+1;h=h+n;d=d+u+n end;if n>0 then c.seek(n)end
if(f+g)%10 ==0 then aw.pullSignal(0)end end;aq(c)local j=e-d;local l=d*100/e;local m=d-h-ax;a("",0xFFFFFF)
a(string.format(" %d files, %d dirs | %s data + %s overhead",f,g,ap(h),ap(m)),0xAAAAAA)
a(string.format(" Tape: %s used (%.1f%%) | %s free",ap(d),l,ap(j)),
j<e*0.1 and 0xFF6600 or 0x00FF00)end
local function bn(b,a)local c,d=at(nil)if not c then a(d,0xFF0000)return end;if not c.isReady()then
a(av,0xFF6600)return end;local e=b[2]=="full"c.stop()aq(c)
if e then
a(
"Full erase: wiping "..ap(c.getSize()).." ...",0x00AAFF)local h=string.rep("\0",au)local g=c.getSize()local f=0
while f<g do
local i=math.min(au,g-f)
if i<au then c.write(string.rep("\0",i))else c.write(h)end;f=f+i;if f% (au*16)==0 then aw.pullSignal(0)end end;aq(c)
a("Tape erased ("..ap(g).." zeroed)",0x00FF00)else aC(c,az)aq(c)
a("Tape quick-erased (archive header cleared)",0x00FF00)
a("Use 'tape erase full' to zero all bytes",0xAAAAAA)end end
local function bo(b,a)local e=tonumber(b[2])or 0
local f=tonumber(b[3])or 128
if f>1024 then f=1024;a("(clamped to 1024 bytes)",0xAAAAAA)end;local c,g=at(nil)if not c then a(g,0xFF0000)return end;if not c.isReady()then
a(av,0xFF6600)return end;c.stop()aD(c,e)local d=as(c,f)if not d then a(
"Could not read tape at offset "..e,0xFF0000)
aq(c)return end
a(string.format(" Tape dump: offset %d, %d bytes",e,#d),0xFFFF00)a("",0xFFFFFF)
for h=0,#d-1,16 do local i={}local j={}
for l=0,15 do local m=h+l+1
if m<=#d then local n=d:byte(m)
i[#i+1]=string.format("%02X",n)
j[#j+1]=(n>=32 and n<127)and string.char(n)or"."else i[#i+1]="  "j[#j+1]=" "end end;local k=e+h
a(string.format(" %06X  %s  %s",k,table.concat(i," "),table.concat(j)),0xFFFFFF)end;aq(c)end
local function bp(b,a)local c=tonumber(b[2])if not c then
a("Usage: tape seek <position>",0xAAAAAA)
a("  Moves the tape head to the given byte position.",0xAAAAAA)return end
local d,e=at(nil)if not d then a(e,0xFF0000)return end;if not d.isReady()then
a(av,0xFF6600)return end;aD(d,c)
a("Tape head at byte "..c,0x00FF00)end
local function bq(b,a)local f=tonumber(b[3])local g=tonumber(b[4])local h=b[5]
if
not f or not g or not h then
a("Usage: tape raw read <offset> <length> <file>",0xAAAAAA)
a("  Read raw bytes from tape and save to a file.",0xAAAAAA)return end;local c,j=at(nil)if not c then a(j,0xFF0000)return end;if not c.isReady()then
a(av,0xFF6600)return end;c.stop()aD(c,f)
a("Reading "..ap(g)..
" from tape at "..f.." ...",0x00AAFF)local i,k=ar.open(h,"w")if not i then
a("Cannot open file: "..tostring(k),0xFF0000)aq(c)return end;local e=g;local d=0
while e>0 do
local l=c.read(math.min(e,au))if not l or#l==0 then
a("Tape ended after "..ap(d),0xFF6600)break end;i:write(l)d=d+#l;e=e-#l;if
d% (au*8)==0 then aw.pullSignal(0)end end;i:close()aq(c)
a("Saved "..ap(d).." to "..h,0x00FF00)end
local function br(b,a)local f=tonumber(b[3])local c=b[4]
if not f or not c then
a("Usage: tape raw write <offset> <file>",0xAAAAAA)
a("  Write raw file contents to tape at the given offset.",0xAAAAAA)return end;local d,g=at(nil)if not d then a(g,0xFF0000)return end;if not d.isReady()then
a(av,0xFF6600)return end;if not ar.exists(c)then
a("File not found: "..c,0xFF0000)return end;local e=ar.readFile(c)
if not e then a("Cannot read file: "..
c,0xFF0000)return end;d.stop()aD(d,f)
a("Writing "..
ap(#e).." to tape at "..f.." ...",0x00AAFF)aC(d,e)aq(d)
a("Wrote "..ap(#e).." from "..c,0x00FF00)end
local function bs(b,a)local c,d=at(nil)if not c then a(d,0xFF0000)return end;if not c.isReady()then
a(av,0xFF6600)return end;local e,f=pcall(c.play)if not e then
a("Play failed: "..tostring(f),0xFF0000)return end;a("Playing.",0x00FF00)end
local function bt(b,a)local c,d=at(nil)if not c then a(d,0xFF0000)return end
pcall(c.stop)a("Stopped.",0x00FF00)end
local function bu(b,a)local c,j=at(nil)if not c then a(j,0xFF0000)return end;if not c.isReady()then
a("State: NO_TAPE",0xFF6600)return end;local f="?"local k,g=pcall(c.getState)if k and g then
f=g end;local l,e=pcall(c.getPosition)local m,d=pcall(c.getSize)a(
"State:    "..f,0xFFFFFF)if
l and m and e and d and d>0 then
a(string.format("Position: %s / %s (%d%%)",ap(e),ap(d),math.floor(e*100/d)),0xFFFFFF)end
local h=aG(c,"speed")
if h then
a(string.format("Speed:    %.2fx (set here)",h),0xFFFFFF)else a("Speed:    not reported by the drive",0xAAAAAA)end;local i=aG(c,aQ)
if i then
a(string.format("Volume:   %.2f (set here)",i),0xFFFFFF)else a("Volume:   not reported by the drive",0xAAAAAA)end end
local function bv(b,a)local d,e=at(nil)if not d then a(e,0xFF0000)return end
if not b[2]then
local h=aG(d,"speed")if h then
a(string.format("Speed set here: %.2fx",h),0xFFFFFF)else
a("The drive does not report its speed (setter only).",0xAAAAAA)end;return end;local c=tonumber(b[2])if not c or c<0.25 or c>2.0 then
a("Speed must be 0.25..2.0 (got "..
tostring(b[2])..")",0xFF0000)return end
local f,g=pcall(d.setSpeed,c)if not f then
a("setSpeed failed: "..tostring(g),0xFF0000)return end;aU(d,"speed",c)
a(string.format("Speed set to %.2fx",c),0x00FF00)end
local function bw(b,a)local d,e=at(nil)if not d then a(e,0xFF0000)return end
if not b[2]then
local h=aG(d,aQ)if h then
a(string.format("Volume set here: %.2f",h),0xFFFFFF)else
a("The drive does not report its volume (setter only).",0xAAAAAA)end;return end;local c=tonumber(b[2])if not c or c<0 or c>1 then
a("Volume must be 0..1 (got "..
tostring(b[2])..")",0xFF0000)return end
local f,g=pcall(d.setVolume,c)if not f then
a("setVolume failed: "..tostring(g),0xFF0000)return end;aU(d,aQ,c)
a(string.format("Volume set to %.2f",c),0x00FF00)end
local function bx(b,a)local c,e=at(nil)if not c then a(e,0xFF0000)return end;if not c.isReady()then
a(av,0xFF6600)return end;pcall(c.stop)
local d=c.getSize()or 0;if d>0 then pcall(c.seek,-d)end;a("Rewound.",0x00FF00)end
local function by(b,a)local e=b[2]if not e then a("Usage: tape load <file.dfpwm>",0xAAAAAA)
return end;if not ar or not ar.exists or
not ar.exists(e)then
a("Cannot read: "..tostring(e),0xFF0000)return end
local f=ar.readFile(e)
if not f then a("Empty or unreadable: "..e,0xFF0000)return end;local d,h=at(nil)if not d then a(h,0xFF0000)return end;if not d.isReady()then
a(av,0xFF6600)return end;local g=d.getSize()or 0;if#f>g then
a(string.format("File too large for tape (%s > %s)",ap(
#f),ap(g)),0xFF0000)return end;pcall(d.stop)pcall(d.seek,
-g)local c=0
while c<#f do local i=f:sub(c+1,c+au)
local j,k=pcall(d.write,i)if not j then
a("write failed at "..c..": "..tostring(k),0xFF0000)return end;c=c+#i;if(c/au)%8 ==0 then
aw.pullSignal(0)end end;pcall(d.seek,-g)
a(string.format("Loaded %s onto tape. Run `tape play` to listen.",ap(c)),0x00FF00)end
local function aO()if
type(vault)=="table"and vault.encrypt and vault.decrypt then return vault end
local b,a=pcall(require,"kernel.vault")if b and a then return a end;return nil end
local function a_()
local a=aw.freeMemory and aw.freeMemory()or 0;if a<=0 then return math.huge end;return math.floor(a/3)end
local function aI(b,a)local d,c,e={},0,0
while c<a do local g,f=pcall(b.read,math.min(au,a-c))if not g or
type(f)~="string"or#f==0 then break end;d[
#d+1]=f;c=c+#f;e=e+1
if(e%8)==0 then aw.pullSignal(0)end end;if c<a then return nil end;return table.concat(d)end
function aB.readArchiveFromDrive(a)
if not
(a and a.read and a.seek and a.getSize)then return nil,"no tape drive"end;local c=a.getSize()or 0
if c<=0 then return nil,"No tape data."end;if a.stop then pcall(a.stop)end;local f=aN(a)local b=f.used or 0
if
b<=0 or b>c then return nil,"No TOS data archive found on this tape."end;local d=a_()
if b>d then return nil,
string.format("Archive is %s but only ~%s of RAM is safely usable. Free memory first.",ap(b),ap(d))end;aq(a)local e=aI(a,b)
if not e then return nil,"Short read while loading the archive."end;return e,nil end
function aB.readVaultBlobFromDrive(a)
if not
(a and a.read and a.seek and a.getSize)then return nil,"no tape drive"end;local c=a.getSize()or 0
if c<=0 then return nil,"No tape data."end;if a.stop then pcall(a.stop)end;aq(a)
local b=c>=aK and aI(a,aK)or nil
if not b then return nil,"Tape is not encrypted (no TOS vault header)."end;local f=b:sub(1,8)if f~=aR and f~=aS then
return nil,"Tape is not encrypted (no TOS vault header)."end;local i,j,k,l=b:byte(aT,aT+3)local d=i|
(j<<8)| (k<<16)| (l<<24)local e=aK+d
if
d<=0 or e>c then return nil,"Vault blob is truncated or its length field is corrupt."end;local g=a_()
if e>g then return nil,
string.format("Encrypted blob is %s but only ~%s of RAM is safely usable.",ap(e),ap(g))end;local h=aI(a,d)
if not h then return nil,"Short read while loading the encrypted blob."end;return b..h,nil end
local function ba(a,b)a.stop()
a.seek(- (a.getSize()or 0))local c=0
while c<#b do local e=b:sub(c+1,c+au)local f,g=pcall(a.write,e)if not f then
return false,
"write failed at "..c..": "..tostring(g)end;c=c+#e;if(c/au)%8 ==0 then
aw.pullSignal(0)end end;local d=(a.getSize()or 0)-c
if d>0 then
local e=string.rep("\0",math.min(d,au))
while d>0 do local f=math.min(#e,d)pcall(a.write,e:sub(1,f))d=d-f;if(d/
au)%8 ==0 then aw.pullSignal(0)end end end;a.stop()
a.seek(- (a.getSize()or 0))return true end
local function bz(a)if not a or#a<8 then return"empty"end
if a:sub(1,4)==ay then return"tos-archive"end;local b=a:sub(1,8)if b==aR or b==aS then return"tos-vault"end
return"unknown"end
local function bA(b,a)local d=b[2]
if not d or#d<1 then
a("Usage: tape encrypt <passphrase>",0xAAAAAA)
a("  Encrypts the tape's data archive in place. Refuses if the",0xAAAAAA)
a("  tape doesn't start with a TOS archive header (we don't want",0xAAAAAA)
a("  to encrypt an audio tape by accident).",0xAAAAAA)return end;local g=aO()if not g then a(be,0xFF0000)return end;local c,j=at(nil)if not c then
a(j,0xFF0000)return end
if not c.isReady()then a(av,0xFF6600)return end;aq(c)
local k=aI(c,math.min(8,c.getSize()or 0))or""local h=bz(k)if h=="tos-vault"then
a("Tape is already encrypted. Use 'tape decrypt' first.",0xFF6600)return end
if h~="tos-archive"then
a("Tape does not start with a TOS data archive header.",0xFF6600)
a("Refusing to encrypt — audio tapes would become unplayable.",0xFF6600)a("Use 'tape store' first, then encrypt.",0xAAAAAA)
return end;local e,l=aB.readArchiveFromDrive(c)if not e then
a(tostring(l),0xFF0000)return end;local f,i=g.encrypt(e,d)if not f then
a("encrypt failed: "..tostring(i),0xFF0000)return end;local m,n=ba(c,f)if not m then
a(tostring(n),0xFF0000)return end
a(string.format("Encrypted %s -> %s on tape (algo=%s).",ap(#e),ap(#f),i.algo),0x00FF00)end
local function bB(b,a)local d=b[2]if not d or#d<1 then
a("Usage: tape decrypt <passphrase>",0xAAAAAA)return end;local g=aO()if not g then a(be,0xFF0000)
return end;local c,h=at(nil)
if not c then a(h,0xFF0000)return end;if not c.isReady()then a(av,0xFF6600)return end
local e,i=aB.readVaultBlobFromDrive(c)if not e then a(tostring(i),0xFF6600)return end
local f,j=g.decrypt(e,d)if not f then
a("Decrypt failed: "..tostring(j),0xFF0000)return end;local k,l=ba(c,f)if not k then
a(tostring(l),0xFF0000)return end
a(string.format("Decrypted %s -> %s on tape.",ap(#e),ap(#f)),0x00FF00)end
local function bC(b,a)local f=b[2]
if f~=bc and f~="decrypt"then
a("Usage: tape vault encrypt <src> <dst> <passphrase>",0xAAAAAA)
a("       tape vault decrypt <src> <dst> <passphrase>",0xAAAAAA)
a("  Encrypt or decrypt a file (works on /mnt/<floppy>/ paths too).",0xAAAAAA)return end;local d,g,h=b[3],b[4],b[5]if not d or not g or not h then
a("Need src, dst, and passphrase.",0xFF0000)return end;local e=aO()if not e then
a(be,0xFF0000)return end;if not ar.exists(d)then
a("No such file: "..d,0xFF0000)return end;local c=ar.readFile(d)if not c then
a("Cannot read: "..d,0xFF0000)return end
if f==bc then local i,j=e.encrypt(c,h)
if not i then a("encrypt failed: "..
tostring(j),0xFF0000)return end;local k,l=ar.writeFile(g,i)if not k then
a("write failed: "..tostring(l),0xFF0000)return end
a(string.format("Encrypted %s -> %s (algo=%s).",ap(#c),ap(#i),j.algo),0x00FF00)else if not e.isEncrypted(c)then
a("Source is not a TOS vault blob.",0xFF6600)return end;local i,j=e.decrypt(c,h)if not i then a(
"Decrypt failed: "..tostring(j),0xFF0000)
return end;local k,l=ar.writeFile(g,i)
if not k then a(
"write failed: "..tostring(l),0xFF0000)return end
a(string.format("Decrypted %s -> %s.",ap(#c),ap(#i)),0x00FF00)end end
local function bD(b,a)local c=b[1]
if not c or c=="help"then
a("=== Tape Module ===",0xFFFF00)a("",0xFFFFFF)a(" Discovery & Info",0x00FF00)
a("  tape detect           List tape drives and status",0xFFFFFF)
a("  tape info             Tape details (label, size, format)",0xFFFFFF)
a("  tape state            Current head position, speed, volume",0xFFFFFF)
a("  tape label [name]     Get or set tape label",0xFFFFFF)a("",0xFFFFFF)a(" Archive Operations",0x00FF00)
a("  tape store <path>     Archive file/directory to tape",0xFFFFFF)
a("  tape restore [path]   Restore archive to path (default /home)",0xFFFFFF)
a("  tape list             List entries in tape archive",0xFFFFFF)a("",0xFFFFFF)a(" Audio Playback (EXP-1)",0x00FF00)
a("  tape play             Start playback from current position",0xFFFFFF)a("  tape stop             Stop playback",0xFFFFFF)
a("  tape rewind           Stop and seek to start of tape",0xFFFFFF)
a("  tape speed [0.25-2.0] Get or set playback speed",0xFFFFFF)
a("  tape volume [0-1]     Get or set playback volume",0xFFFFFF)
a("  tape load <file>      Rewind, write file (DFPWM) to tape",0xFFFFFF)a("",0xFFFFFF)a(" Low-Level Tools",0x00FF00)
a("  tape dump [off] [len] Hex dump (default: 0, 128)",0xFFFFFF)
a("  tape seek <pos>       Move tape head to byte position",0xFFFFFF)
a("  tape erase [full]     Quick-erase or full zero-wipe",0xFFFFFF)a("",0xFFFFFF)a(" Raw I/O",0x00FF00)
a("  tape raw read <off> <len> <file>",0xFFFFFF)
a("     Read raw bytes from tape into a file",0xAAAAAA)a("  tape raw write <off> <file>",0xFFFFFF)
a("     Write raw file bytes to tape at offset",0xAAAAAA)a("",0xFFFFFF)a(" Encryption (FEAT-10)",0x00FF00)
a("  tape encrypt <passphrase>      Encrypt the tape's data archive",0xFFFFFF)
a("  tape decrypt <passphrase>      Decrypt the tape's data archive",0xFFFFFF)
a("  tape vault encrypt <src> <dst> <passphrase>",0xFFFFFF)
a("     Encrypt any file (works on floppy paths too)",0xAAAAAA)
a("  tape vault decrypt <src> <dst> <passphrase>",0xFFFFFF)a("     Decrypt any vault file",0xAAAAAA)return end
if c=="detect"then bh(b,a)elseif c=="info"then bi(b,a)elseif c=="state"then bu(b,a)elseif c=="label"then bj(b,a)elseif c==
"store"then bk(b,a)elseif c=="restore"then bl(b,a)elseif c=="list"then bm(b,a)elseif c=="erase"then bn(b,a)elseif
c=="dump"then bo(b,a)elseif c=="seek"then bp(b,a)elseif c=="play"then bs(b,a)elseif c=="stop"then bt(b,a)elseif c=="rewind"then
bx(b,a)elseif c=="speed"then bv(b,a)elseif c==aQ then bw(b,a)elseif c=="load"then by(b,a)elseif c==bc then bA(b,a)elseif c=="decrypt"then
bB(b,a)elseif c=="vault"then bC(b,a)elseif c=="raw"then local d=b[2]
if d=="read"then bq(b,a)elseif d=="write"then br(b,a)else
a("Usage: tape raw read|write ...",0xAAAAAA)
a("  tape raw read <offset> <length> <file>",0xAAAAAA)a("  tape raw write <offset> <file>",0xAAAAAA)end else
a("Unknown subcommand: "..tostring(c),0xFF6600)a("Type 'tape help' for usage.",0xAAAAAA)end end;aB.commands={tape=bD}return aB