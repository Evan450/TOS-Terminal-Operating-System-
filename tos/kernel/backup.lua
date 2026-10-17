local C,L,M,G="backup","backup not initialized","no session","entry "local z={}
local A="TOSBAK1\0"local H=256;local D=1024*1024;local E=4096
local N={[".trash"]=true,["tmp"]=true}local w=nil;local I=nil;local x=nil;local y=nil
function z.init(a)w=a.securefs;I=a.fs;x=a.crypto;y=a.log end;local function O(a)return string.char(a&0xFF)end
local function J(a)return string.char(a&0xFF,(a>>
8)&0xFF)end
local function B(a)a=math.floor(a)return
string.char(a&0xFF,(a>>8)&0xFF,(a>>16)&0xFF,(a>>24)&0xFF)end;local function P(b,a)return b:byte(a),a+1 end;local function K(b,a)return b:byte(a)|
(b:byte(a+1)<<8),a+2 end;local function F(b,a)
return
b:byte(a)| (b:byte(
a+1)<<8)| (b:byte(a+2)<<16)| (b:byte(a+3)<<24),a+4 end
local function Q(c,a,b)local e={}b=b or N;local d=0
local function f(g)if d>=E then
return end;local h=(g=="")and c or(c..g)if
not w.exists(h,a)then return end
if w.isDirectory(h,a)then
if g~=""then d=d+1;e[d]={rel=g,isDir=true}end;local i=w.list(h,a)if type(i)=="table"then
for k,j in ipairs(i)do local l=j:gsub("/$","")if
not b[l]then f(g.."/"..l)end end end else d=d+1
local i=w.size(h,a)or 0
if i>D then if y then
y.warn(C,"Skipping oversized file: "..h.." ("..i.." > "..D..")")end;d=d-1;return end;e[d]={rel=g,isDir=false,size=i}end end;f("")return e end
local function R(a,b,c)local f={}local function e(l)f[#f+1]=l end;local g={}local function d(l)g[#g+1]=l end
for m,l in
ipairs(b)do local n=l.isDir and 1 or 0;d(O(n))d(J(#l.rel))
d(l.rel)
if l.isDir then d(B(0))d(string.rep("0",64))else local o=
w.readFile(a..l.rel,c)or""d(B(#o))d(o)d(x and x.hash(o)or
string.rep("0",64))end end;local h=table.concat(g)local i=a;local j=math.floor(
(os.time and os.time())or 0)e(A)e(B(j))e(B(#
b))e(J(#i))e(i)
local k=x and x.hash(h)or string.rep("0",64)e(k)e(h)
return table.concat(f),{entries=#b,bytes=0,root=a,created=j,hash=k}end
function z.snapshot(a,b,c)if not w or not I then return false,L end;c=c or{}
local d=c.session or
(_G._TOS and
_G._TOS.users and _G._TOS.users.currentSession())or nil;if not d then return false,M end;a=w.normalize(a)
if a=="/"then return false,
"backup of / is not supported (use the tape package for full images)"end
if not w.exists(a,d)then return false,"source not found: "..a end;if not w.isDirectory(a,d)then
return false,"source is not a directory: "..a end;b=w.normalize(b)
if
w.isDirectory(b,d)then return false,"destination is a directory; pass a file path"end
if b:sub(1,#a+1)==a.."/"then return false,"destination must be outside source"end;local f=Q(a,d,c.exclude)if#f==0 then
return false,"no files to back up under "..a end;if#f>=E then
return false,"tree exceeds "..E.." entries"end;local g,e=R(a,f,d)e.bytes=#g
local h,i=w.writeFile(b,g,d)
if not h then return false,"write failed: "..tostring(i)end;if y then
y.info(C,string.format("Snapshot %s -> %s (%d entries, %d bytes)",a,b,e.entries,e.bytes))end;return true,e end
function z.inspect(b,a)if not w then return nil,L end;a=a or{}
local f=
a.session or(_G._TOS and _G._TOS.users and
_G._TOS.users.currentSession())or nil;if not f then return nil,M end;local d=w.readFile(b,f)if not d then
return nil,"cannot read: "..b end;if#d<#A+4+4+2+64 then
return nil,"truncated header"end;if d:sub(1,#A)~=A then
return nil,"bad magic (not a TOS backup)"end;local c=#A+1;local g;g,c=F(d,c)local h;h,c=F(d,c)local e
e,c=K(d,c)if e>H then return nil,"header: root path too long"end
local i=d:sub(c,c+e-1)c=c+e;local j=d:sub(c,c+63)c=c+64
return{magic=A,created=g,entries=h,root=i,metaHash=j,bodyOff=c,size=#d}end
function z.restore(b,a)if not w then return false,L end;a=a or{}
local d=a.session or
(
_G._TOS and _G._TOS.users and _G._TOS.users.currentSession())or nil;if not d then return false,M end;local g,j=z.inspect(b,{session=d})if not g then return false,
j end
local e=w.normalize(a.destRoot or g.root)if e=="/"then return false,"refusing to restore to /"end
if
w.exists(e,d)and not a.force then
if w.isDirectory(e,d)then local k=w.list(e,d)if
type(k)=="table"and#k>0 then
return false,"destRoot non-empty; pass force=true to overwrite: "..e end end end;if not w.exists(e,d)then w.makeDirectory(e,d)end
local i=w.readFile(b,d)if not i then return false,"cannot read: "..b end
local f=i:sub(g.bodyOff)if x then local k=x.hash(f)
if not x.ctEquals(k,g.metaHash)then return false,
"backup integrity check failed (metaHash mismatch)"end end;local c=1
local h=0
for k=1,g.entries do
if c>#f then return false,"truncated body at entry "..k end;local q;q,c=P(f,c)local n;n,c=K(f,c)if n>H then
return false,G..k..": path too long"end;local m=f:sub(c,c+n-1)c=c+n
if
m:sub(1,1)~="/"then return false,G..k..": unsafe path "..m end;local o;o,c=F(f,c)
if o>D then return false,G..k..": data too large"end;local p=f:sub(c,c+o-1)c=c+o;local r=f:sub(c,c+63)c=c+64
local l=w.normalize(e..m)
if l~=e and l:sub(1,#e+1)~=e.."/"then return false,G..k..
": path escapes destRoot: "..m end;local s=(q&1)==1
if s then
if not w.exists(l,d)then w.makeDirectory(l,d)end else
if x and#p>0 then local t=x.hash(p)
if not x.ctEquals(t,r)then if y then
y.warn(C,"Skipping entry with bad hash: "..m)end else local u=l:match("^(.+)/[^/]+$")if
u and u~=""and not w.exists(u,d)then local T=""
for U in u:gmatch("[^/]+")do
T=T.."/"..U;if not w.exists(T,d)then w.makeDirectory(T,d)end end end
local v,S=w.writeFile(l,p,d)if v then h=h+1 elseif y then
y.warn(C,"Restore write failed: "..l..": "..tostring(S))end end end end end;if y then
y.info(C,string.format("Restored %d files from %s -> %s",h,b,e))end
return true,{entries=g.entries,restored=h,destRoot=e}end;return z