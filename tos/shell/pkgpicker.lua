local j,k,o,l,p="cancel","install","installed","key_down","string"local m={}
local function i(a,b,c)if
c and a and a>=32 and a<127 then return false end
local e,d=pcall(require,"shell.keys")if e and d and d.is then return d.is("quit",a,b)end;return
a==17 or b==1 end
local function n()local c,a=pcall(require,"shell.keys")local b=c and a and a.label and
a.label("quit")or""return
b~=""and b or"^Q"end
function m.run(a)a=a or{}local J=io and io.read and io.write;local function b(ak)
if J then io.write(
(ak or"").."\n")else print(ak or"")end end;local function x(ak)
if J then io.write(ak or"")end end
local function D(ak)b("ERROR: "..ak)return end;local V,f=pcall(require,"kernel.pkg")if
not V or not f or not f.installByName then
return D("kernel.pkg unavailable — run this on a TOS machine.")end
local W,y=pcall(require,"kernel.users")if not W or not y then
return D("kernel.users unavailable — run this on a TOS machine.")end
local E=select(1,y.currentSession and
y.currentSession()or nil)local X=(y.TIER and y.TIER.ADMIN)or 2
if not E then return
D("no logged-in session. Log in (admin/root), then re-run.")end;if(E.tier or 0)<X then
return D("installing packages requires admin/root.")end
local Y,K=pcall(require,"kernel.fs")local Z,Q=pcall(require,"kernel.serialize")
local function _()if not
(Y and Z and K and Q)then return nil end
local ak=
(f.repoRoots and f.repoRoots())or{"/usr/repo","/var/repo"}
for am,al in ipairs(ak)do local an=al.."/optutil-set.lua"
if K.exists(an)then
local x=K.readFile(an)
if type(x)==p then
local ap,ao=pcall(Q.decode,x:gsub("^%s*%-%-[^\n]*\n",""),{maxBytes=64*1024})if
ap and type(ao)=="table"and type(ao.packages)=="table"then return ao end end end end end;local R=_()local d=
(f.listAllAvailable and f.listAllAvailable({includeRemote=true}))or{}
local S={}
for al,ak in ipairs(d)do ak.reachable=true;S[ak.name]=true end
if R then
for al,ak in pairs(R.packages)do
if not S[al]then
d[#d+1]={name=al,version=ak.version,description=ak.description,category=
(
type(ak.category)==p and ak.category~="")and ak.category or"misc",kind=ak.kind,requires=ak.requires,recommends=ak.recommends,disk=ak.disk,reachable=false}else
for an,am in ipairs(d)do if am.name==al then am.disk=ak.disk end end end end end
if#d==0 then b("No installable packages found.")
b("Insert the Optional Utilities disk (it auto-mounts under /mnt) and re-run.")return false,"no installable packages found"end
local aa={games=1,productivity=2,network=3,storage=4,security=5,drivers=6,control=7,misc=99}local function T(ak)return aa[ak or"misc"]or 50 end
table.sort(d,function(ak,al)
local am,an=T(ak.category),T(al.category)if am~=an then return am<an end;if(ak.category or"")~=
(al.category or"")then return
(ak.category or"")< (al.category or"")end;return
(ak.name or"")< (al.name or"")end)
local ab={games="Games",productivity="Productivity",network="Network",storage="Storage",security="Security",drivers="Drivers",control="Control",hbm="HBM Nuclear Tech",misc="Other"}
local function z(ak)return ab[ak or"misc"]or
((ak or"misc"):gsub("^%l",string.upper))end;local e={}local h=""
local function ac(al,ak)if ak==""then return true end;ak=ak:lower()
local function am(an)return an and
tostring(an):lower():find(ak,1,true)~=nil end;return
am(al.name)or am(al.description)or am(al.category)end
local function F()e={}local ak=nil
for am,al in ipairs(d)do if ac(al,h)then if al.category~=ak then ak=al.category
e[#e+1]={header=z(al.category),cat=al.category}end
e[#e+1]={ai=am,cat=al.category}end end end;F()local c={}local r={}
local function g(ak)return f.info and f.info(ak)~=nil end
local function L(ak)if type(ak)=="table"then return ak.name end;if type(ak)==p then return
(ak:match("^(%S+)"))end end;local A={}for ak,al in ipairs(d)do A[al.name]=ak end;local v={}
for al,ak in ipairs(d)do for al,am in ipairs(
ak.recommends or{})do v[am]=v[am]or{}
v[am][#v[am]+1]=ak.name end end;for al,ak in pairs(v)do table.sort(ak)end
local function M(am,ak,al)ak,al=ak or{},al or{}
local an=d[am]if not an or al[am]then return ak end;al[am]=true
for ap,ao in
ipairs(an.requires or{})do local ar=L(ao)local aq=ar and A[ar]if aq and not g(d[aq].name)then
ak[aq]=true;M(aq,ak,al)end end;return ak end
local function s()r={}for ak in pairs(c)do
for al in pairs(M(ak))do if not c[al]then r[al]=true end end end end
local function ad(ak)local b={}
for am,al in ipairs(ak.requires or{})do local an=L(al)if
an and not A[an]and not g(an)then b[#b+1]=an end end;return b end
local function ae(ak)local al={}local am=f.info and f.info(ak)
if
am and am.kind=="service"then
for ao,an in ipairs(am.files or{})do
local ap=tostring(an):match("^/etc/rc%.d/(.+)%.lua$")if ap then al[#al+1]=ap end end;if#al==0 then al[1]=ak end end;return al end
local function af()local aX,aL=pcall(require,"component")
local aY,aC=pcall(require,"computer")
if not(aX and aY and aL and aC)then return nil end;local aD
do local bi,bh=pcall(require,"kernel.screen")
if
bi and type(bh)=="table"and bh.callerDevices then local bk,bj=pcall(bh.callerDevices)if bk and
type(bj)=="table"then aD=bj.gpu end end end
aD=aD or(aL.list and aL.list("gpu")())if not aD then return nil end;local aZ,au=pcall(aL.proxy,aD)if not aZ or not au or not
au.getResolution then return nil end
local al,ap=au.getResolution()
if not al or not ap or al<40 or ap<12 then return nil end;local aP=8
pcall(function()aP=au.getDepth()end)local ar=(aP or 8)<=1
local ak={bg=0x000000,fg=0xC0C0C0,dim=0x555555,title=0x00AAFF,sel_fg=0x000000,sel_bg=0x00AAFF,ok=0x00FF00,warn=0xFFAA00,err=0xFF0000,panel=0x1A1A1A}local a_,aM=pcall(require,"kernel.display")
if
a_ and aM and aM.getTheme then local bh=aM.getTheme()
if type(bh)=="table"then ak.bg=bh.bg or ak.bg;ak.fg=
bh.fg or ak.fg;ak.dim=bh.dim or ak.dim
ak.title=bh.title or ak.title;ak.sel_fg=bh.sel_fg or ak.sel_fg
ak.sel_bg=bh.sel_bg or ak.sel_bg;ak.ok=bh.highlight or ak.ok
ak.warn=bh.warning or ak.warn;ak.err=bh.error or ak.err
ak.panel=bh.panel_bg or ak.panel end end
if ar then
ak={bg=0x000000,fg=0xFFFFFF,dim=0xFFFFFF,title=0xFFFFFF,sel_fg=0x000000,sel_bg=0xFFFFFF,ok=0xFFFFFF,warn=0xFFFFFF,err=0xFFFFFF,panel=0x000000}end
local function am(bj,bk,bl,bh,bi)if bh then pcall(au.setForeground,bh)end;if bi then
pcall(au.setBackground,bi)end;pcall(au.set,bj,bk,bl)end
local function aq(bj,bk,bl,bm,bn,bh,bi)if bh then pcall(au.setForeground,bh)end;if bi then
pcall(au.setBackground,bi)end;pcall(au.fill,bj,bk,bl,bm,bn or" ")end;local aE=nil
do local bh,bi=pcall(require,"unicode")if bh then aE=bi end end
local function ba(bh)local bi=0;for bj=1,#bh do local bk=bh:byte(bj)
if bk<0x80 or bk>=0xC0 then bi=bi+1 end end;return bi end
local function bb(bh,bi,bj)local bl,bk={},0;for bm=1,#bh do local bn=bh:byte(bm)
if bn<0x80 or bn>=0xC0 then bk=bk+1;bl[bk]=bm end end;bl[bk+1]=#bh+1
bi=math.max(1,bi or 1)bj=math.min(bk,bj or bk)if bi>bj then return""end;return bh:sub(bl[bi],
bl[bj+1]-1)end
local function ay(bh)return aE and aE.len(bh)or ba(bh)end;local function aQ(bh,bi,bj)
return aE and aE.sub(bh,bi,bj)or bb(bh,bi,bj)end
local function an(bh,bi)bh=tostring(bh or"")if
ay(bh)<=bi then return bh end;if bi<=1 then return aQ(bh,1,bi)end;return aQ(bh,1,bi-1).. (ar and
">"or"…")end;local av=4;local az=ap;local aA=al>=60;local aw=
aA and math.max(26,math.floor(al*0.42))or al;local aF=aw+2;local aG=al-aF;local aH=aA and
(ap-1)or(ap-2)local as=math.max(1,aH-av)
local at=0
local function aI()for bh,bi in ipairs(e)do if bi.ai then return bh end end;return 1 end
local function aJ(bh,bi)local bj=bh
while true do local bk=bj+bi;if bk<1 or bk>#e then return bj end;bj=bk;if
e[bj]and e[bj].ai then return bj end end end;local ao=aI()
local function aB()local bh=e[ao]return bh and bh.ai and d[bh.ai]or nil,
bh and bh.ai or nil end
local function bc()local bh=0;for bi in pairs(c)do bh=bh+1 end;for bi in pairs(r)do bh=bh+1 end;return bh end
local function aR()local bh,bi=aB()return bh~=nil and not g(bh.name)and not c[bi]and not
r[bi]end;local function aS()local b={}
for bi,bh in ipairs(e)do if bh.ai then b[#b+1]=bh.ai end end;return b end;local function bd(bh)local b={}
for bj,bi in ipairs(e)do if bi.ai and
bi.cat==bh then b[#b+1]=bi.ai end end;return b end
local function be(bh)
local bi=bd(bh)local bj=false;for bl,bk in ipairs(bi)do
if not g(d[bk].name)and not c[bk]then bj=true end end
for bl,bk in ipairs(bi)do if not g(d[bk].name)then c[bk]=
bj and true or nil end end;s()return bj,#bi end;local function bf()local bh=e[ao]return bh and bh.cat end
local function aT()
aq(1,1,al,ap," ",ak.fg,ak.bg)local bl=" TOS Optional Utilities "local bq=(ar and"="or"═")
am(1,1,string.rep(bq,al),ak.title,ak.bg)
am(math.max(1,math.floor((al-#bl)/2)),1,bl,ak.title,ak.bg)local bi=0;for bt,bs in ipairs(e)do if bs.ai then bi=bi+1 end end;local bh;if h~=""then bh=string.format("%d of %d match '%s'",bi,
#d,h)else
bh=string.format("%d add-ons",#d)end
local bm=string.format("%d selected",bc())local bj=(ar and"-"or"─")local bn,bo=(ar and"|"or"┤"),(ar and"|"or
"├")local bp=bj..
bn.." "..bh.." "..bo
local bk=bn.." "..bm.." "..bo..bj;local br=al-ay(bp)-ay(bk)
am(1,2,bp..
string.rep(bj,math.max(0,br))..bk,ak.dim,ak.bg)am(4,2,bh,ak.fg,ak.bg)
am(al-ay(bk)+3,2,bm,ak.fg,ak.bg)
am(2,3,an("[*] installed  [x] selected  [+] needed by one  [ ] available",al-3),ak.dim,ak.bg)end
local function aN()if ao<at+1 then at=ao-1 end;if ao>at+as then at=ao-as end
if at<0 then at=0 end
for bh=0,as-1 do local bk=at+bh+1;local bi=av+bh;local bj=e[bk]
aq(1,bi,aw,1," ",ak.fg,ak.bg)
if bj and bj.header then local bl=(ar and"-"or"─")
local bm=" "..bj.header.." "
am(1,bi,bl..bl..
bm..string.rep(bl,math.max(0,aw-3-ay(bm))),ak.dim,ak.bg)am(4,bi,bj.header,ak.title,ak.bg)elseif bj and bj.ai then local bq=bj.ai
local bm=d[bq]local br=g(bm.name)
local bs=br and"[*]"or(c[bq]and"[x]"or
(r[bq]and"[+]"or"[ ]"))local bl=(bk==ao)
local bn=bl and ak.sel_fg or(
(br or bm.reachable==false)and ak.dim or ak.fg)local bo=bl and ak.sel_bg or ak.bg;if bl then
aq(1,bi,aw,1," ",bn,bo)end
local bt=bl and bn or
(br and ak.ok or(c[bq]and ak.warn or
(r[bq]and ak.title or ak.dim)))am(3,bi,bs,bt,bo)local bu=aA and(aw-16)or 17
am(7,bi,an(bm.name or"?",math.max(4,bu)),bn,bo)
local bp=bm.version and tostring(bm.version)or""if bp~=""and ay(bp)<8 then bp="v"..bp end
if aA then am(aw-8,bi,an(bp,8),
bl and bn or ak.dim,bo)else am(25,bi,an(bp,8),bl and bn or
ak.dim,bo)
am(34,bi,an(bm.description or"",math.max(0,
al-35)),bl and bn or ak.dim,bo)end end end
if#e>as then local bh=math.floor(
(at/math.max(1,#e-as))* (as-1)+0.5)for bi=0,as-1 do
am(aw,
av+bi,(bi==bh)and(ar and"#"or"█")or
(ar and"|"or"│"),ak.dim,ak.bg)end end;if#e==0 then
am(2,av,an("Nothing matches '"..h.."'.",aw-3),ak.warn,ak.bg)
am(2,av+1,an("Esc clears the filter, / edits it.",aw-3),ak.dim,ak.bg)end;if aA then for bh=0,
as-1 do
am(aw+1,av+bh,ar and"|"or"│",ak.dim,ak.bg)end end end
local function aO()if not aA then return end;local bh=aB()for br=0,as-1 do
aq(aF,av+br,aG,1," ",ak.fg,ak.bg)end;if not bh then return end;local bj=av;local function bk(bs,bt,br)
if bj>=av+as then return end
am(aF+ (br or 0),bj,an(bs or"",aG- (br or 0)),bt or ak.fg,ak.bg)bj=bj+1 end
local function bi(bs,br,bt)if br==
nil or br==""then return end;if bj>=av+as then return end
am(aF,bj,an(bs,10),ak.dim,ak.bg)
am(aF+10,bj,an(tostring(br),aG-10),bt or ak.fg,ak.bg)bj=bj+1 end
local function bn(bt,bs,br)local bv=aG- (br or 0)local bu=""
for bw in
tostring(bt or""):gmatch("%S+")do if bu==""then bu=bw elseif ay(bu)+1+ay(bw)<=bv then bu=bu.." "..bw else
bk(bu,bs,br)bu=bw end end;if bu~=""then bk(bu,bs,br)end end;bk(bh.name or"?",ak.title)
bk(string.rep(ar and"-"or"─",math.min(aG,40)),ak.dim)
bn(bh.description or"(no description)",ak.fg)bk("",nil)local bp=g(bh.name)local bl=select(2,aB())
local bq=
bp and"already installed"or
(c[bl]and"selected to install"or
(r[bl]and"needed by another choice"or"available"))
bi("Status",bq,bp and ak.ok or
((c[bl]or r[bl])and ak.warn or ak.dim))bi("Version",bh.version)
bi("Category",z(bh.category))bi("Kind",bh.kind)bi("Author",bh.author)
if bh.remote then
bi("From","repo "..tostring(
bh.repo or"?").."  (downloads on install)")elseif bh.reachable then
bi("From",bh.root or(bh.disk and("disk "..bh.disk)))else
bi("On disk",tostring(bh.disk or"?").."  (not inserted)",ak.warn)
bn("selectable — the installer will ask for it",ak.dim,10)end;local bm={}for bs,br in ipairs(bh.requires or{})do local bt=L(br)
if bt then bm[#bm+1]=bt end end
if#bm>0 then
bi("Needs",table.concat(bm,", "))local br=ad(bh)if#br>0 then
bn("not on any inserted disk: "..table.concat(br,", "),ak.err,10)end end;if bh.recommends and#bh.recommends>0 then
bi("Suggests",table.concat(bh.recommends,", "),ak.dim)end;local bo=v[bh.name]if bo and
#bo>0 then
bi("Wanted by",table.concat(bo,", "),ak.dim)end end
local function aU()aq(1,az,al,1,ar and" "or"░",ak.dim,ak.bg)
if
not ar then am(1,az,"▓▒░",ak.dim,ak.bg)if al>6 then
am(al-2,az,"░▒▓",ak.dim,ak.bg)end end end
local function aV()
if not aA then local bj=aB()aq(1,aH,al,1," ",ak.fg,ak.bg)
aq(1,aH+1,al,1," ",ak.fg,ak.bg)
if bj then local bl=bj.description or"(no description)"
am(2,aH,an(bl,al-3),ak.fg,ak.bg)local bk={}if bj.category then bk[#bk+1]=z(bj.category)end;if
g(bj.name)then bk[#bk+1]="already installed"end;if bj.root then
bk[#bk+1]=tostring(bj.root)end
if bj.kind then bk[#bk+1]=tostring(bj.kind)end;if#bk>0 then
am(2,aH+1,an(table.concat(bk,"  ·  "),al-3),ak.dim,ak.bg)end end end;aU()
local bh={n():gsub(" / .*","").." Quit","/ Filter","G Group","A All","N None","R +Suggested"}
if aR()then table.insert(bh,1,"Space/Enter Add")else
table.insert(bh,1,"Enter Install")table.insert(bh,1,"Space")end
local bi=" "..table.concat(bh," · ").." "if ay(bi)>al-9 then bi=table.concat(bh,"·")end;am(5,az,an(bi,
al-9),ak.fg,ak.bg)end;local function ax()aT()aN()aO()aV()end;local function aK(bh)aU()
am(5,az,an(" "..bh.." ",al-9),ak.title,ak.bg)end
local function aW(bh,bi)local bj,bk={},{}for bm in pairs(M(bi))do
bj[#bj+1]=d[bm].name end
for bn,bm in ipairs(bh.recommends or{})do local bo=A[bm]if bo and
not g(bm)and not c[bo]and not r[bo]then
bk[#bk+1]=bm end end;if#bj==0 and#bk==0 then return nil end
local bl=bh.name..
(#bj>0 and(" + "..
table.concat(bj," + "))or"").." selected · Enter installs"if#bk>0 then
bl=bl.." · R adds "..table.concat(bk,", ")end;return bl end
local function bg()local bi=h;local bh=h
while true do F()ao=aI()at=0;aT()aN()aO()
aq(1,az,al,1," ",ak.fg,ak.bg)
am(2,az,an("Filter: "..bh.."_",al-22),ak.title,ak.bg)
local bl="Enter=keep "..n():gsub(" / .*","").."=undo"am(math.max(2,al-#bl),az,bl,ak.dim,ak.bg)
local bm,bn,bj,bk=aC.pullSignal()
if bm==l then
if bk==28 then h=bh;break elseif i(bj,bk,true)then h=bi;break elseif bk==14 then bh=bh:sub(1,-2)h=bh elseif bj and bj>=32 and bj<
127 then bh=bh..string.char(bj)h=bh end end end;F()ao=aI()at=0;ax()end;ax()
while true do local bj,bk,bh,bi=aC.pullSignal()
if bj==l then
local function bl(bm)bm()aN()aO()aV()end
if bi==200 then bl(function()ao=aJ(ao,-1)end)elseif bi==208 then bl(function()
ao=aJ(ao,1)end)elseif bi==201 then bl(function()
for bk=1,as do ao=aJ(ao,-1)end end)elseif
bi==209 then
bl(function()for bk=1,as do ao=aJ(ao,1)end end)elseif bi==199 then bl(function()ao=aI()end)elseif bi==207 then bl(function()
for bk=1,#e do ao=aJ(ao,1)end end)elseif bh==32 then
local bn,bm=aB()
if bn and bm and not g(bn.name)then c[bm]=not c[bm]or nil;s()
ax()local bo=c[bm]and aW(bn,bm)if bo then aK(bo)end else ax()end elseif bh==103 or bh==71 then local bm=bf()if bm then local bn,bo=be(bm)ax()
aK(string.format("%s %d in %s",
bn and"Selected"or"Cleared",bo,z(bm)))end elseif bh==47 or bh==63 then
bg()elseif bh==97 or bh==65 then for bk,bm in ipairs(aS())do
if not g(d[bm].name)then c[bm]=true end end;s()ax()elseif bh==110 or bh==78 then if h==""then c={}else for bk,bm in
ipairs(aS())do c[bm]=nil end end;s()ax()elseif
bh==114 or bh==82 then local bn={}for bo in pairs(c)do
for bk,bp in ipairs(d[bo].recommends or{})do
local bq=A[bp]if bq and not g(d[bq].name)then bn[bq]=true end end end;local bm=0;for bo in
pairs(bn)do if not c[bo]then bm=bm+1 end;c[bo]=true end
s()ax()
aK(bm>0 and string.format("Added %d suggested",bm)or
"Your selection suggests nothing more")elseif i(bh,bi)and h~=""then h=""F()ao=aI()at=0;ax()elseif
bh==113 or bh==81 or i(bh,bi)then aq(1,1,al,ap," ",ak.fg,ak.bg)return j elseif bi==28 and aR()then local bm,bn=aB()
c[bn]=true;s()ax()
aK(aW(bm,bn)or(bm.name.." selected · Enter installs"))elseif bi==28 and next(c)==nil then
aK("Nothing selected. Space or Enter adds a package")elseif bi==28 then local bn=0;local bm,bo={},0
return k,
function(bq,br,bp)
local function bs(bu)bo=bu;local bv=ap-1;local bw=math.max(10,al-18)local by=
(bn>0)and math.min(1,bu/bn)or 0;local bx=math.floor(
bw*by+0.5)
aq(1,bv,al,1," ",ak.fg,ak.bg)
am(2,bv,"["..string.rep(ar and"#"or"█",bx)..
string.rep(" ",bw-bx).."]",ak.title,ak.bg)
am(bw+5,bv,string.format("%d/%d",bu,bn),ak.dim,ak.bg)end
local function bt()aq(1,1,al,ap," ",ak.fg,ak.bg)
am(2,1,"Installing…",ak.title,ak.bg)
for bv,bu in pairs(bm)do if bu.name then
am(2,bv,an(bu.name,al-20),ak.fg,ak.bg)end;if bu.mark then
am(al-16,bv,bu.mark,bu.color,ak.bg)end end;bs(bo)end
if br=="swap"then local bw,bu=pcall(require,"shell.panels.dialogs")
if
bw and bu and bu.dialog then local by={W=al,H=ap,T=ak,D={set=am,fill=aq}}
local bx=bu.dialog(by,{style=k,title="Next disk",message=
tostring(bq)..
"\n\nSwap the floppy, then choose Continue.".."\nStopping here keeps everything already installed.",buttons={"Continue","Stop (keep)","Undo all"},default=1,escIndex=2})bt()return
(bx==3 and"undo")or(bx==2 and"abort")or"retry"end;local bv=math.max(2,ap-6)aq(1,bv,al,4," ",ak.fg,ak.bg)am(2,bv,an(tostring(bq),
al-4),ak.warn,ak.bg)
am(2,bv+1,an("Enter = continue   A = stop, keep what's installed   U = undo all",
al-4),ak.fg,ak.bg)
while true do local bz,bk,bx,by=aC.pullSignal()
if bz==l then
local bA=

(by==28 and"retry")or((
bx==97 or bx==65 or by==1)and"abort")or((bx==117 or bx==85)and"undo")or nil;if bA then bt()return bA end end end elseif br=="begin"then bn=bp or 0;bm,bo={},0;aq(1,1,al,ap," ",ak.fg,ak.bg)
am(2,1,"Installing…",ak.title,ak.bg)bs(0)elseif br=="row"then local bu=2+ (bp or 0)if bu<ap-2 then
am(2,bu,an(bq,al-20),ak.fg,ak.bg)bm[bu]={name=bq}end
bs((bp or 1)-1)elseif br=="ok"then local bu=2+ (bp or 0)
if bu<ap-2 then
am(al-16,bu,o,ak.ok,ak.bg)if bm[bu]then bm[bu].mark,bm[bu].color=o,ak.ok end end;bs(bp or 0)elseif br=="fail"then local bu=2+ (bp or 0)
if bu<ap-2 then
local bv=an(tostring(bq),15)am(al-16,bu,bv,ak.err,ak.bg)if bm[bu]then
bm[bu].mark,bm[bu].color=bv,ak.err end end;bs(bp or 0)elseif br=="done"then bs(bn)
am(2,ap,an(tostring(bq).."   Press any key…",
al-4),ak.fg,ak.bg)
while true do local bu=aC.pullSignal()if bu==l then break end end;aq(1,1,al,ap," ",ak.fg,ak.bg)end end end end end end
local function ag()
if not J then
b("No GPU for the menu and no interactive input here.")b("Install from the disk with:")
b("  pkg from-floppy        installs the whole disk, with prompts")
b("  pkg install <name>     one package, e.g.  pkg install tetris")return j end
local function ak()b("")b("=== TOS Optional Utilities ===")
b("  [*] already installed   [x] selected   [ ] available")local al=nil
for an,am in ipairs(d)do
if am.category~=al then al=am.category;b("  -- "..
z(am.category).." --")end;local ao
if g(am.name)then ao="[*]"elseif c[an]then ao="[x]"elseif r[an]then ao="[+]"else ao="[ ]"end
b(string.format("   %2d %s %-16s %s",an,ao,am.name or"?",(am.description or""):sub(1,42)))end;b("")
b("  <number> toggle  ·  a all  ·  n none  ·  i install  ·  q quit")end
while true do ak()x("> ")local al=io.read()
if not al then b("")
b("No interactive input here (panels shell). Install from the disk with:")
b("  pkg from-floppy        installs the whole disk, with prompts")
b("  pkg install <name>     one package, e.g.  pkg install tetris")return j end;al=al:gsub("%s+","")
if al=="q"then
b("Cancelled — nothing installed.")return j elseif al=="i"and next(c)==nil then
b("  Nothing selected: enter a package's number first.")elseif al=="i"then return k elseif al=="a"then
for am,an in ipairs(d)do if not g(an.name)then c[am]=true end end;s()elseif al=="n"then c={}s()else local am=tonumber(al)
if am and d[am]then
if g(d[am].name)then
b("  ("..
d[am].name.." is already installed)")else c[am]=not c[am]or nil;s()end else
b("  ? unrecognised — enter a number, or a/n/i/q")end end end end
local function U()local am,ak=pcall(require,"kernel.display")if
am and ak and ak.invalidateColors then pcall(ak.invalidateColors)end
local an,al=pcall(require,"kernel.screen")
if an and al and al.invalidateAll then pcall(al.invalidateAll)end end;local N,q=af()U()if N==nil then N=ag()end;if N~=k then return end;local B={}for ak,al in ipairs(d)do if c[ak]or
r[ak]then B[#B+1]=al end end;if q then q(nil,"begin",
#B)else b("")
b("Installing "..#B.." package(s)...")end;local G,O,w=0,0,{}local H={}local C=0
local function ah(ak)
for am,al in
ipairs((f.listAllAvailable and
f.listAllAvailable({includeRemote=true}))or{})do if al.name==ak then return true end end;return false end
local function ai(ak)C=C+1;if q then q(ak.name,"row",C)else
x(string.format("  %-16s ",ak.name))end
local an={session=E,allowUnverified=a.allowUnverified==true,allowUnsigned=a.allowUnsigned==true,force=
a.force==true}local am,al;if ak.remote then am,al=f.installRemote(ak.name,an)else
am,al=f.installByName(ak.name,an)end
if am then G=G+1;H[#H+1]=ak.name;if q then
q(ak.name,"ok",C)else b(o)end
for ap,ao in ipairs(ae(ak.name))do w[#w+1]=ao end else O=O+1;if q then q(tostring(al),"fail",C)else
b("FAILED: "..tostring(al))end end end
local function aj()local ak,al=0,{}
for am=#H,1,-1 do local an=H[am]
local ao=f.uninstall and f.uninstall(an,{session=E})if ao then ak=ak+1 else al[#al+1]=an end end;return ak,al end;local t={}for al,ak in ipairs(B)do t[#t+1]=ak end;local P,I=false,nil
while#t>0 do local al={}
for aq,ap in
ipairs(t)do if ah(ap.name)then ai(ap)else al[#al+1]=ap end end;t=al;if#t==0 then break end;local am,an=nil,{}for aq,ap in ipairs(t)do am=am or ap.disk
an[#an+1]=ap.name end
local ao=string.format("Insert disk %s for: %s",tostring(am or"?"),table.concat(an,", "))local ak
if q then ak=q(ao,"swap")else b("")b(ao)
b("  [Enter] continue   [a] stop, keep what's installed   [u] undo everything")x("> ")local ap=io.read()
if ap==nil then ak="abort"else
ap=ap:gsub("%s+",""):lower()ak=(ap=="u"and"undo")or(ap=="a"and"abort")or
"retry"end end
if ak=="undo"then local aq,ap=aj()I=aq;if#ap>0 then
b("Could NOT remove: "..table.concat(ap,", "))end;P=true;break elseif ak=="abort"then P=true;break end end;local u
if I then
u=string.format("Undone: %d package(s) removed, nothing kept.",I)elseif P then
u=string.format("Stopped: %d installed and kept, %d not installed.",G,#t)else
u=string.format("Done: %d installed, %d failed.",G,O)end;if not I and#w>0 then
u=u.."  Start service(s): "..table.concat(w,", ")end
if q then q(u,"done")U()else b("")b(u)
if#w>0 then
b("Service packages installed DISABLED. They register on the next reboot;")b("then enable (and persist) one with:")for al,ak in ipairs(w)do b(
"  service start "..ak)end end end end;return m