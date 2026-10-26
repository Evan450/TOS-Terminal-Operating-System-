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
(ak or"").."\n")else print(ak or"")end end;local function y(ak)
if J then io.write(ak or"")end end
local function C(ak)b("ERROR: "..ak)return end;local V,f=pcall(require,"kernel.pkg")if
not V or not f or not f.installByName then
return C("kernel.pkg unavailable — run this on a TOS machine.")end
local W,z=pcall(require,"kernel.users")if not W or not z then
return C("kernel.users unavailable — run this on a TOS machine.")end
local D=select(1,z.currentSession and
z.currentSession()or nil)local X=(z.TIER and z.TIER.ADMIN)or 2
if not D then return
C("no logged-in session. Log in (admin/root), then re-run.")end;if(D.tier or 0)<X then
return C("installing packages requires admin/root.")end
local Y,K=pcall(require,"kernel.fs")local Z,P=pcall(require,"kernel.serialize")
local function _()if not
(Y and Z and K and P)then return nil end
local ak=
(f.repoRoots and f.repoRoots())or{"/usr/repo","/var/repo"}
for am,al in ipairs(ak)do local an=al.."/optutil-set.lua"
if K.exists(an)then
local y=K.readFile(an)
if type(y)==p then
local ap,ao=pcall(P.decode,y:gsub("^%s*%-%-[^\n]*\n",""),{maxBytes=64*1024})if
ap and type(ao)=="table"and type(ao.packages)=="table"then return ao end end end end end;local Q=_()local c=
(f.listAllAvailable and f.listAllAvailable({includeRemote=true}))or{}
local R={}
for al,ak in ipairs(c)do ak.reachable=true;R[ak.name]=true end
if Q then
for al,ak in pairs(Q.packages)do
if not R[al]then
c[#c+1]={name=al,version=ak.version,description=ak.description,category=
(
type(ak.category)==p and ak.category~="")and ak.category or"misc",kind=ak.kind,requires=ak.requires,recommends=ak.recommends,disk=ak.disk,reachable=false}else
for an,am in ipairs(c)do if am.name==al then am.disk=ak.disk end end end end end
if#c==0 then b("No installable packages found.")
b("Insert the Optional Utilities disk (it auto-mounts under /mnt) and re-run.")return false,"no installable packages found"end
local aa={games=1,productivity=2,network=3,storage=4,security=5,drivers=6,control=7,misc=99}local function S(ak)return aa[ak or"misc"]or 50 end
table.sort(c,function(ak,al)
local am,an=S(ak.category),S(al.category)if am~=an then return am<an end;if(ak.category or"")~=
(al.category or"")then return
(ak.category or"")< (al.category or"")end;return
(ak.name or"")< (al.name or"")end)
local ab={games="Games",productivity="Productivity",network="Network",storage="Storage",security="Security",drivers="Drivers",control="Control",hbm="HBM Nuclear Tech",misc="Other"}
local function A(ak)return ab[ak or"misc"]or
((ak or"misc"):gsub("^%l",string.upper))end;local e={}local h=""
local function ac(al,ak)if ak==""then return true end;ak=ak:lower()
local function am(an)return an and
tostring(an):lower():find(ak,1,true)~=nil end;return
am(al.name)or am(al.description)or am(al.category)end
local function E()e={}local ak=nil
for am,al in ipairs(c)do if ac(al,h)then if al.category~=ak then ak=al.category
e[#e+1]={header=A(al.category),cat=al.category}end
e[#e+1]={ai=am,cat=al.category}end end end;E()local d={}local r={}
local function q(ak)return f.info and f.info(ak)~=nil end
local function L(ak)if type(ak)=="table"then return ak.name end;if type(ak)==p then return
(ak:match("^(%S+)"))end end;local F={}for ak,al in ipairs(c)do F[al.name]=ak end;local v={}
for al,ak in ipairs(c)do for al,am in ipairs(
ak.recommends or{})do v[am]=v[am]or{}
v[am][#v[am]+1]=ak.name end end;for al,ak in pairs(v)do table.sort(ak)end
local function T(am,ak,al)ak,al=ak or{},al or{}
local an=c[am]if not an or al[am]then return ak end;al[am]=true
for ap,ao in
ipairs(an.requires or{})do local ar=L(ao)local aq=ar and F[ar]if aq and not q(c[aq].name)then
ak[aq]=true;T(aq,ak,al)end end;return ak end
local function s()r={}for ak in pairs(d)do
for al in pairs(T(ak))do if not d[al]then r[al]=true end end end end
local function ad(ak)local b={}
for am,al in ipairs(ak.requires or{})do local an=L(al)if
an and not F[an]and not q(an)then b[#b+1]=an end end;return b end
local function ae(ak)local al={}local am=f.info and f.info(ak)
if
am and am.kind=="service"then
for ao,an in ipairs(am.files or{})do
local ap=tostring(an):match("^/etc/rc%.d/(.+)%.lua$")if ap then al[#al+1]=ap end end;if#al==0 then al[1]=ak end end;return al end
local function af()local aU,aJ=pcall(require,"component")
local aV,aB=pcall(require,"computer")
if not(aU and aV and aJ and aB)then return nil end;local aC
do local bf,be=pcall(require,"kernel.screen")
if
bf and type(be)=="table"and be.callerDevices then local bh,bg=pcall(be.callerDevices)if bh and
type(bg)=="table"then aC=bg.gpu end end end
aC=aC or(aJ.list and aJ.list("gpu")())if not aC then return nil end;local aW,au=pcall(aJ.proxy,aC)if not aW or not au or not
au.getResolution then return nil end
local al,ap=au.getResolution()
if not al or not ap or al<40 or ap<12 then return nil end;local aO=8
pcall(function()aO=au.getDepth()end)local ar=(aO or 8)<=1
local ak={bg=0x000000,fg=0xC0C0C0,dim=0x555555,title=0x00AAFF,sel_fg=0x000000,sel_bg=0x00AAFF,ok=0x00FF00,warn=0xFFAA00,err=0xFF0000,panel=0x1A1A1A}local aX,aL=pcall(require,"kernel.display")
if
aX and aL and aL.getTheme then local be=aL.getTheme()
if type(be)=="table"then ak.bg=be.bg or ak.bg;ak.fg=
be.fg or ak.fg;ak.dim=be.dim or ak.dim
ak.title=be.title or ak.title;ak.sel_fg=be.sel_fg or ak.sel_fg
ak.sel_bg=be.sel_bg or ak.sel_bg;ak.ok=be.highlight or ak.ok
ak.warn=be.warning or ak.warn;ak.err=be.error or ak.err
ak.panel=be.panel_bg or ak.panel end end
if ar then
ak={bg=0x000000,fg=0xFFFFFF,dim=0xFFFFFF,title=0xFFFFFF,sel_fg=0x000000,sel_bg=0xFFFFFF,ok=0xFFFFFF,warn=0xFFFFFF,err=0xFFFFFF,panel=0x000000}end
local function am(bg,bh,bi,be,bf)if be then pcall(au.setForeground,be)end;if bf then
pcall(au.setBackground,bf)end;pcall(au.set,bg,bh,bi)end
local function aq(bg,bh,bi,bj,bk,be,bf)if be then pcall(au.setForeground,be)end;if bf then
pcall(au.setBackground,bf)end;pcall(au.fill,bg,bh,bi,bj,bk or" ")end;local aD=nil
do local be,bf=pcall(require,"unicode")if be then aD=bf end end
local function aY(be)local bf=0;for bg=1,#be do local bh=be:byte(bg)
if bh<0x80 or bh>=0xC0 then bf=bf+1 end end;return bf end
local function aZ(be,bf,bg)local bi,bh={},0;for bj=1,#be do local bk=be:byte(bj)
if bk<0x80 or bk>=0xC0 then bh=bh+1;bi[bh]=bj end end;bi[bh+1]=#be+1
bf=math.max(1,bf or 1)bg=math.min(bh,bg or bh)if bf>bg then return""end;return be:sub(bi[bf],
bi[bg+1]-1)end
local function ax(be)return aD and aD.len(be)or aY(be)end;local function aP(be,bf,bg)
return aD and aD.sub(be,bf,bg)or aZ(be,bf,bg)end
local function an(be,bf)be=tostring(be or"")if
ax(be)<=bf then return be end;if bf<=1 then return aP(be,1,bf)end;return aP(be,1,bf-1).. (ar and
">"or"…")end;local av=4;local ay=ap;local aA=al>=60;local aw=
aA and math.max(26,math.floor(al*0.42))or al;local aE=aw+2;local aF=al-aE;local aG=aA and
(ap-1)or(ap-2)local as=math.max(1,aG-av)
local at=0
local function aH()for be,bf in ipairs(e)do if bf.ai then return be end end;return 1 end
local function aI(be,bf)local bg=be
while true do local bh=bg+bf;if bh<1 or bh>#e then return bg end;bg=bh;if
e[bg]and e[bg].ai then return bg end end end;local ao=aH()
local function aK()local be=e[ao]return be and be.ai and c[be.ai]or nil,
be and be.ai or nil end
local function a_()local be=0;for bf in pairs(d)do be=be+1 end;for bf in pairs(r)do be=be+1 end;return be end;local function aQ()local b={}
for bf,be in ipairs(e)do if be.ai then b[#b+1]=be.ai end end;return b end;local function ba(be)local b={}
for bg,bf in ipairs(e)do if bf.ai and
bf.cat==be then b[#b+1]=bf.ai end end;return b end
local function bb(be)
local bf=ba(be)local bg=false;for bi,bh in ipairs(bf)do
if not q(c[bh].name)and not d[bh]then bg=true end end
for bi,bh in ipairs(bf)do if not q(c[bh].name)then d[bh]=
bg and true or nil end end;s()return bg,#bf end;local function bc()local be=e[ao]return be and be.cat end
local function aR()
aq(1,1,al,ap," ",ak.fg,ak.bg)local bi=" TOS Optional Utilities "local bn=(ar and"="or"═")
am(1,1,string.rep(bn,al),ak.title,ak.bg)
am(math.max(1,math.floor((al-#bi)/2)),1,bi,ak.title,ak.bg)local bf=0;for bq,bp in ipairs(e)do if bp.ai then bf=bf+1 end end;local be;if h~=""then be=string.format("%d of %d match '%s'",bf,
#c,h)else
be=string.format("%d add-ons",#c)end
local bj=string.format("%d selected",a_())local bg=(ar and"-"or"─")local bk,bl=(ar and"|"or"┤"),(ar and"|"or
"├")local bm=bg..
bk.." "..be.." "..bl
local bh=bk.." "..bj.." "..bl..bg;local bo=al-ax(bm)-ax(bh)
am(1,2,bm..
string.rep(bg,math.max(0,bo))..bh,ak.dim,ak.bg)am(4,2,be,ak.fg,ak.bg)
am(al-ax(bh)+3,2,bj,ak.fg,ak.bg)
am(2,3,an("[*] installed  [x] selected  [+] needed by one  [ ] available",al-3),ak.dim,ak.bg)end
local function aM()if ao<at+1 then at=ao-1 end;if ao>at+as then at=ao-as end
if at<0 then at=0 end
for be=0,as-1 do local bh=at+be+1;local bf=av+be;local bg=e[bh]
aq(1,bf,aw,1," ",ak.fg,ak.bg)
if bg and bg.header then local bi=(ar and"-"or"─")
local bj=" "..bg.header.." "
am(1,bf,bi..bi..
bj..string.rep(bi,math.max(0,aw-3-ax(bj))),ak.dim,ak.bg)am(4,bf,bg.header,ak.title,ak.bg)elseif bg and bg.ai then local bm=bg.ai
local bj=c[bm]local bn=q(bj.name)
local bp=bn and"[*]"or(d[bm]and"[x]"or
(r[bm]and"[+]"or"[ ]"))local bi=(bh==ao)
local bk=bi and ak.sel_fg or(
(bn or bj.reachable==false)and ak.dim or ak.fg)local bl=bi and ak.sel_bg or ak.bg;if bi then
aq(1,bf,aw,1," ",bk,bl)end
local bq=bi and bk or
(bn and ak.ok or(d[bm]and ak.warn or
(r[bm]and ak.title or ak.dim)))am(3,bf,bp,bq,bl)local br=aA and(aw-16)or 17
am(7,bf,an(bj.name or"?",math.max(4,br)),bk,bl)
local bo=bj.version and("v"..tostring(bj.version))or""
if aA then
am(aw-8,bf,an(bo,8),bi and bk or ak.dim,bl)else am(25,bf,an(bo,8),bi and bk or ak.dim,bl)
am(34,bf,an(
bj.description or"",math.max(0,al-35)),bi and bk or ak.dim,bl)end end end
if#e>as then local be=math.floor(
(at/math.max(1,#e-as))* (as-1)+0.5)for bf=0,as-1 do
am(aw,
av+bf,(bf==be)and(ar and"#"or"█")or
(ar and"|"or"│"),ak.dim,ak.bg)end end;if#e==0 then
am(2,av,an("Nothing matches '"..h.."'.",aw-3),ak.warn,ak.bg)
am(2,av+1,an("Esc clears the filter, / edits it.",aw-3),ak.dim,ak.bg)end;if aA then for be=0,
as-1 do
am(aw+1,av+be,ar and"|"or"│",ak.dim,ak.bg)end end end
local function aN()if not aA then return end;local be=aK()for bo=0,as-1 do
aq(aE,av+bo,aF,1," ",ak.fg,ak.bg)end;if not be then return end;local bg=av;local function bh(bp,bq,bo)
if bg>=av+as then return end
am(aE+ (bo or 0),bg,an(bp or"",aF- (bo or 0)),bq or ak.fg,ak.bg)bg=bg+1 end
local function bf(bp,bo,bq)if bo==
nil or bo==""then return end;if bg>=av+as then return end
am(aE,bg,an(bp,10),ak.dim,ak.bg)
am(aE+10,bg,an(tostring(bo),aF-10),bq or ak.fg,ak.bg)bg=bg+1 end
local function bk(bq,bp,bo)local bs=aF- (bo or 0)local br=""
for bt in
tostring(bq or""):gmatch("%S+")do if br==""then br=bt elseif ax(br)+1+ax(bt)<=bs then br=br.." "..bt else
bh(br,bp,bo)br=bt end end;if br~=""then bh(br,bp,bo)end end;bh(be.name or"?",ak.title)
bh(string.rep(ar and"-"or"─",math.min(aF,40)),ak.dim)
bk(be.description or"(no description)",ak.fg)bh("",nil)local bm=q(be.name)local bi=select(2,aK())
local bn=
bm and"already installed"or
(d[bi]and"selected to install"or
(r[bi]and"needed by another choice"or"available"))
bf("Status",bn,bm and ak.ok or
((d[bi]or r[bi])and ak.warn or ak.dim))bf("Version",be.version)
bf("Category",A(be.category))bf("Kind",be.kind)bf("Author",be.author)
if be.remote then
bf("From","repo "..tostring(
be.repo or"?").."  (downloads on install)")elseif be.reachable then
bf("From",be.root or(be.disk and("disk "..be.disk)))else
bf("On disk",tostring(be.disk or"?").."  (not inserted)",ak.warn)
bk("selectable — the installer will ask for it",ak.dim,10)end;local bj={}for bp,bo in ipairs(be.requires or{})do local bq=L(bo)
if bq then bj[#bj+1]=bq end end
if#bj>0 then
bf("Needs",table.concat(bj,", "))local bo=ad(be)if#bo>0 then
bk("not on any inserted disk: "..table.concat(bo,", "),ak.err,10)end end;if be.recommends and#be.recommends>0 then
bf("Suggests",table.concat(be.recommends,", "),ak.dim)end;local bl=v[be.name]if bl and
#bl>0 then
bf("Wanted by",table.concat(bl,", "),ak.dim)end end
local function aS()aq(1,ay,al,1,ar and" "or"░",ak.dim,ak.bg)
if
not ar then am(1,ay,"▓▒░",ak.dim,ak.bg)if al>6 then
am(al-2,ay,"░▒▓",ak.dim,ak.bg)end end end
local function aT()
if not aA then local bg=aK()aq(1,aG,al,1," ",ak.fg,ak.bg)
aq(1,aG+1,al,1," ",ak.fg,ak.bg)
if bg then local bi=bg.description or"(no description)"
am(2,aG,an(bi,al-3),ak.fg,ak.bg)local bh={}if bg.category then bh[#bh+1]=A(bg.category)end;if
q(bg.name)then bh[#bh+1]="already installed"end;if bg.root then
bh[#bh+1]=tostring(bg.root)end
if bg.kind then bh[#bh+1]=tostring(bg.kind)end;if#bh>0 then
am(2,aG+1,an(table.concat(bh,"  ·  "),al-3),ak.dim,ak.bg)end end end;aS()
local bf={"Space","Enter Install",n():gsub(" / .*","").." Quit","/ Filter","G Group","A All","N None","R +Suggested"}
local be=" "..table.concat(bf," · ").." "if ax(be)>al-9 then be=table.concat(bf,"·")end;am(5,ay,an(be,
al-9),ak.fg,ak.bg)end;local function az()aR()aM()aN()aT()end
local function bd()local bf=h;local be=h
while true do E()ao=aH()at=0;aR()
aM()aN()aq(1,ay,al,1," ",ak.fg,ak.bg)
am(2,ay,an("Filter: "..be.."_",al-22),ak.title,ak.bg)
local bi="Enter=keep "..n():gsub(" / .*","").."=undo"am(math.max(2,al-#bi),ay,bi,ak.dim,ak.bg)
local bj,bk,bg,bh=aB.pullSignal()
if bj==l then
if bh==28 then h=be;break elseif i(bg,bh,true)then h=bf;break elseif bh==14 then be=be:sub(1,-2)h=be elseif bg and bg>=32 and bg<
127 then be=be..string.char(bg)h=be end end end;E()ao=aH()at=0;az()end;az()
while true do local bg,bh,be,bf=aB.pullSignal()
if bg==l then
local function bi(bj)bj()aM()aN()aT()end
if bf==200 then bi(function()ao=aI(ao,-1)end)elseif bf==208 then bi(function()
ao=aI(ao,1)end)elseif bf==201 then bi(function()
for bh=1,as do ao=aI(ao,-1)end end)elseif
bf==209 then
bi(function()for bh=1,as do ao=aI(ao,1)end end)elseif bf==199 then bi(function()ao=aH()end)elseif bf==207 then bi(function()
for bh=1,#e do ao=aI(ao,1)end end)elseif be==32 then
local bk,bj=aK()
if bk and bj and not q(bk.name)then d[bj]=not d[bj]or nil;s()end;az()elseif be==103 or be==71 then local bj=bc()if bj then local bk,bl=bb(bj)az()aS()
am(5,ay,an(string.format(" %s %d in %s ",
bk and"Selected"or"Cleared",bl,A(bj)),al-9),ak.title,ak.bg)end elseif
be==47 or be==63 then bd()elseif be==97 or be==65 then for bh,bj in ipairs(aQ())do if not q(c[bj].name)then
d[bj]=true end end;s()az()elseif
be==110 or be==78 then
if h==""then d={}else for bh,bj in ipairs(aQ())do d[bj]=nil end end;s()az()elseif be==114 or be==82 then local bj={}
for bk in pairs(d)do for bh,bl in
ipairs(c[bk].recommends or{})do local bm=F[bl]
if bm and not q(c[bm].name)then bj[bm]=true end end end;for bk in pairs(bj)do d[bk]=true end;s()az()elseif i(be,bf)and h~=""then h=""E()
ao=aH()at=0;az()elseif be==113 or be==81 or i(be,bf)then
aq(1,1,al,ap," ",ak.fg,ak.bg)return j elseif bf==28 then local bk=0;local bj,bl={},0
return k,
function(bn,bo,bm)
local function bp(br)bl=br;local bs=ap-1;local bt=math.max(10,al-18)local bv=
(bk>0)and math.min(1,br/bk)or 0;local bu=math.floor(
bt*bv+0.5)
aq(1,bs,al,1," ",ak.fg,ak.bg)
am(2,bs,"["..string.rep(ar and"#"or"█",bu)..
string.rep(" ",bt-bu).."]",ak.title,ak.bg)
am(bt+5,bs,string.format("%d/%d",br,bk),ak.dim,ak.bg)end
local function bq()aq(1,1,al,ap," ",ak.fg,ak.bg)
am(2,1,"Installing…",ak.title,ak.bg)
for bs,br in pairs(bj)do if br.name then
am(2,bs,an(br.name,al-20),ak.fg,ak.bg)end;if br.mark then
am(al-16,bs,br.mark,br.color,ak.bg)end end;bp(bl)end
if bo=="swap"then local bt,br=pcall(require,"shell.panels.dialogs")
if
bt and br and br.dialog then local bv={W=al,H=ap,T=ak,D={set=am,fill=aq}}
local bu=br.dialog(bv,{style=k,title="Next disk",message=
tostring(bn)..
"\n\nSwap the floppy, then choose Continue.".."\nStopping here keeps everything already installed.",buttons={"Continue","Stop (keep)","Undo all"},default=1,escIndex=2})bq()return
(bu==3 and"undo")or(bu==2 and"abort")or"retry"end;local bs=math.max(2,ap-6)aq(1,bs,al,4," ",ak.fg,ak.bg)am(2,bs,an(tostring(bn),
al-4),ak.warn,ak.bg)
am(2,bs+1,an("Enter = continue   A = stop, keep what's installed   U = undo all",
al-4),ak.fg,ak.bg)
while true do local bw,bh,bu,bv=aB.pullSignal()
if bw==l then
local bx=

(bv==28 and"retry")or((
bu==97 or bu==65 or bv==1)and"abort")or((bu==117 or bu==85)and"undo")or nil;if bx then bq()return bx end end end elseif bo=="begin"then bk=bm or 0;bj,bl={},0;aq(1,1,al,ap," ",ak.fg,ak.bg)
am(2,1,"Installing…",ak.title,ak.bg)bp(0)elseif bo=="row"then local br=2+ (bm or 0)if br<ap-2 then
am(2,br,an(bn,al-20),ak.fg,ak.bg)bj[br]={name=bn}end
bp((bm or 1)-1)elseif bo=="ok"then local br=2+ (bm or 0)
if br<ap-2 then
am(al-16,br,o,ak.ok,ak.bg)if bj[br]then bj[br].mark,bj[br].color=o,ak.ok end end;bp(bm or 0)elseif bo=="fail"then local br=2+ (bm or 0)
if br<ap-2 then
local bs=an(tostring(bn),15)am(al-16,br,bs,ak.err,ak.bg)if bj[br]then
bj[br].mark,bj[br].color=bs,ak.err end end;bp(bm or 0)elseif bo=="done"then bp(bk)
am(2,ap,an(tostring(bn).."   Press any key…",
al-4),ak.fg,ak.bg)
while true do local br=aB.pullSignal()if br==l then break end end;aq(1,1,al,ap," ",ak.fg,ak.bg)end end end end end end
local function ag()
if not J then
b("No GPU for the menu and no interactive input here.")b("Install from the disk with:")
b("  pkg from-floppy        installs the whole disk, with prompts")
b("  pkg install <name>     one package, e.g.  pkg install tetris")return j end
local function ak()b("")b("=== TOS Optional Utilities ===")
b("  [*] already installed   [x] selected   [ ] available")local al=nil
for an,am in ipairs(c)do
if am.category~=al then al=am.category;b("  -- "..
A(am.category).." --")end;local ao
if q(am.name)then ao="[*]"elseif d[an]then ao="[x]"elseif r[an]then ao="[+]"else ao="[ ]"end
b(string.format("   %2d %s %-16s %s",an,ao,am.name or"?",(am.description or""):sub(1,42)))end;b("")
b("  <number> toggle  ·  a all  ·  n none  ·  i install  ·  q quit")end
while true do ak()y("> ")local al=io.read()
if not al then b("")
b("No interactive input here (panels shell). Install from the disk with:")
b("  pkg from-floppy        installs the whole disk, with prompts")
b("  pkg install <name>     one package, e.g.  pkg install tetris")return j end;al=al:gsub("%s+","")
if al=="q"then
b("Cancelled — nothing installed.")return j elseif al=="i"then return k elseif al=="a"then
for am,an in ipairs(c)do if not q(an.name)then d[am]=true end end;s()elseif al=="n"then d={}s()else local am=tonumber(al)
if am and c[am]then
if q(c[am].name)then
b("  ("..
c[am].name.." is already installed)")else d[am]=not d[am]or nil;s()end else
b("  ? unrecognised — enter a number, or a/n/i/q")end end end end
local function U()local am,ak=pcall(require,"kernel.display")if
am and ak and ak.invalidateColors then pcall(ak.invalidateColors)end
local an,al=pcall(require,"kernel.screen")
if an and al and al.invalidateAll then pcall(al.invalidateAll)end end;local M,g=af()U()if M==nil then M=ag()end;if M~=k then return end;local w={}for ak,al in ipairs(c)do if d[ak]or
r[ak]then w[#w+1]=al end end
if#w==0 then if g then
g("Nothing selected.","done")else b("Nothing selected.")end;return end;if g then g(nil,"begin",#w)else b("")
b("Installing "..#w.." package(s)...")end;local G,N,x=0,0,{}local H={}local B=0
local function ah(ak)
for am,al in
ipairs((f.listAllAvailable and
f.listAllAvailable({includeRemote=true}))or{})do if al.name==ak then return true end end;return false end
local function ai(ak)B=B+1;if g then g(ak.name,"row",B)else
y(string.format("  %-16s ",ak.name))end
local an={session=D,allowUnverified=a.allowUnverified==true,allowUnsigned=a.allowUnsigned==true,force=
a.force==true}local am,al;if ak.remote then am,al=f.installRemote(ak.name,an)else
am,al=f.installByName(ak.name,an)end
if am then G=G+1;H[#H+1]=ak.name;if g then
g(ak.name,"ok",B)else b(o)end
for ap,ao in ipairs(ae(ak.name))do x[#x+1]=ao end else N=N+1;if g then g(tostring(al),"fail",B)else
b("FAILED: "..tostring(al))end end end
local function aj()local ak,al=0,{}
for am=#H,1,-1 do local an=H[am]
local ao=f.uninstall and f.uninstall(an,{session=D})if ao then ak=ak+1 else al[#al+1]=an end end;return ak,al end;local t={}for al,ak in ipairs(w)do t[#t+1]=ak end;local O,I=false,nil
while#t>0 do local al={}
for aq,ap in
ipairs(t)do if ah(ap.name)then ai(ap)else al[#al+1]=ap end end;t=al;if#t==0 then break end;local am,an=nil,{}for aq,ap in ipairs(t)do am=am or ap.disk
an[#an+1]=ap.name end
local ao=string.format("Insert disk %s for: %s",tostring(am or"?"),table.concat(an,", "))local ak
if g then ak=g(ao,"swap")else b("")b(ao)
b("  [Enter] continue   [a] stop, keep what's installed   [u] undo everything")y("> ")local ap=io.read()
if ap==nil then ak="abort"else
ap=ap:gsub("%s+",""):lower()ak=(ap=="u"and"undo")or(ap=="a"and"abort")or
"retry"end end
if ak=="undo"then local aq,ap=aj()I=aq;if#ap>0 then
b("Could NOT remove: "..table.concat(ap,", "))end;O=true;break elseif ak=="abort"then O=true;break end end;local u
if I then
u=string.format("Undone: %d package(s) removed, nothing kept.",I)elseif O then
u=string.format("Stopped: %d installed and kept, %d not installed.",G,#t)else
u=string.format("Done: %d installed, %d failed.",G,N)end;if not I and#x>0 then
u=u.."  Start service(s): "..table.concat(x,", ")end
if g then g(u,"done")U()else b("")b(u)
if#x>0 then
b("Service packages installed DISABLED. They register on the next reboot;")b("then enable (and persist) one with:")for al,ak in ipairs(x)do b(
"  service start "..ak)end end end end;return m