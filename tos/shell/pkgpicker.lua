local g,h,k,i,l="cancel","install","installed","key_down","string"local j={}
function j.run(a)a=a or{}local H=io and
io.read and io.write
local function b(ai)if H then
io.write((ai or"").."\n")else print(ai or"")end end;local function w(ai)if H then io.write(ai or"")end end;local function A(ai)b("ERROR: "..
ai)return end
local T,f=pcall(require,"kernel.pkg")
if not T or not f or not f.installByName then return
A("kernel.pkg unavailable — run this on a TOS machine.")end;local U,x=pcall(require,"kernel.users")
if not U or not x then return
A("kernel.users unavailable — run this on a TOS machine.")end
local B=select(1,x.currentSession and x.currentSession()or nil)local V=(x.TIER and x.TIER.ADMIN)or 2
if not B then return
A("no logged-in session. Log in (admin/root), then re-run.")end;if(B.tier or 0)<V then
return A("installing packages requires admin/root.")end
local W,I=pcall(require,"kernel.fs")local X,N=pcall(require,"kernel.serialize")
local function Y()if not
(W and X and I and N)then return nil end
local ai=
(f.repoRoots and f.repoRoots())or{"/usr/repo","/var/repo"}
for ak,aj in ipairs(ai)do local al=aj.."/optutil-set.lua"
if I.exists(al)then
local w=I.readFile(al)
if type(w)==l then
local an,am=pcall(N.decode,w:gsub("^%s*%-%-[^\n]*\n",""),{maxBytes=64*1024})if
an and type(am)=="table"and type(am.packages)=="table"then return am end end end end end;local O=Y()local c=
(f.listAllAvailable and f.listAllAvailable({includeRemote=true}))or{}
local P={}
for aj,ai in ipairs(c)do ai.reachable=true;P[ai.name]=true end
if O then
for aj,ai in pairs(O.packages)do
if not P[aj]then
c[#c+1]={name=aj,version=ai.version,description=ai.description,category=
(
type(ai.category)==l and ai.category~="")and ai.category or"misc",kind=ai.kind,requires=ai.requires,recommends=ai.recommends,disk=ai.disk,reachable=false}else
for al,ak in ipairs(c)do if ak.name==aj then ak.disk=ai.disk end end end end end
if#c==0 then b("No installable packages found.")
b("Insert the Optional Utilities disk (it auto-mounts under /mnt) and re-run.")return false,"no installable packages found"end
local Z={games=1,productivity=2,network=3,storage=4,security=5,drivers=6,control=7,misc=99}local function Q(ai)return Z[ai or"misc"]or 50 end
table.sort(c,function(ai,aj)
local ak,al=Q(ai.category),Q(aj.category)if ak~=al then return ak<al end;if(ai.category or"")~=
(aj.category or"")then return
(ai.category or"")< (aj.category or"")end;return
(ai.name or"")< (aj.name or"")end)
local _={games="Games",productivity="Productivity",network="Network",storage="Storage",security="Security",drivers="Drivers",control="Control",hbm="HBM Nuclear Tech",misc="Other"}
local function y(ai)return _[ai or"misc"]or
((ai or"misc"):gsub("^%l",string.upper))end;local e={}local n=""
local function aa(aj,ai)if ai==""then return true end;ai=ai:lower()
local function ak(al)return al and
tostring(al):lower():find(ai,1,true)~=nil end;return
ak(aj.name)or ak(aj.description)or ak(aj.category)end
local function C()e={}local ai=nil
for ak,aj in ipairs(c)do if aa(aj,n)then if aj.category~=ai then ai=aj.category
e[#e+1]={header=y(aj.category),cat=aj.category}end
e[#e+1]={ai=ak,cat=aj.category}end end end;C()local d={}local p={}
local function o(ai)return f.info and f.info(ai)~=nil end
local function J(ai)if type(ai)=="table"then return ai.name end;if type(ai)==l then return
(ai:match("^(%S+)"))end end;local D={}for ai,aj in ipairs(c)do D[aj.name]=ai end;local t={}
for aj,ai in ipairs(c)do for aj,ak in ipairs(
ai.recommends or{})do t[ak]=t[ak]or{}
t[ak][#t[ak]+1]=ai.name end end;for aj,ai in pairs(t)do table.sort(ai)end
local function R(al,aj,ak)aj,ak=aj or{},ak or{}
local ai=c[al]if not ai or ak[al]then return aj end;ak[al]=true
for an,am in
ipairs(ai.requires or{})do local ap=J(am)local ao=ap and D[ap]if ao and not o(c[ao].name)then
aj[ao]=true;R(ao,aj,ak)end end;return aj end
local function q()p={}for aj in pairs(d)do
for ai in pairs(R(aj))do if not d[ai]then p[ai]=true end end end end
local function ab(ai)local b={}
for ak,aj in ipairs(ai.requires or{})do local al=J(aj)if
al and not D[al]and not o(al)then b[#b+1]=al end end;return b end
local function ac(ai)local aj={}local ak=f.info and f.info(ai)
if
ak and ak.kind=="service"then
for am,al in ipairs(ak.files or{})do
local an=tostring(al):match("^/etc/rc%.d/(.+)%.lua$")if an then aj[#aj+1]=an end end;if#aj==0 then aj[1]=ai end end;return aj end
local function ad()local aS,aH=pcall(require,"component")
local aT,az=pcall(require,"computer")
if not(aS and aT and aH and az)then return nil end;local aA
do local bd,bc=pcall(require,"kernel.screen")
if
bd and type(bc)=="table"and bc.callerDevices then local bf,be=pcall(bc.callerDevices)if bf and
type(be)=="table"then aA=be.gpu end end end
aA=aA or(aH.list and aH.list("gpu")())if not aA then return nil end;local aU,as=pcall(aH.proxy,aA)if not aU or not as or not
as.getResolution then return nil end
local aj,an=as.getResolution()
if not aj or not an or aj<40 or an<12 then return nil end;local aM=8
pcall(function()aM=as.getDepth()end)local ap=(aM or 8)<=1
local ai={bg=0x000000,fg=0xC0C0C0,dim=0x555555,title=0x00AAFF,sel_fg=0x000000,sel_bg=0x00AAFF,ok=0x00FF00,warn=0xFFAA00,err=0xFF0000,panel=0x1A1A1A}local aV,aJ=pcall(require,"kernel.display")
if
aV and aJ and aJ.getTheme then local bc=aJ.getTheme()
if type(bc)=="table"then ai.bg=bc.bg or ai.bg;ai.fg=
bc.fg or ai.fg;ai.dim=bc.dim or ai.dim
ai.title=bc.title or ai.title;ai.sel_fg=bc.sel_fg or ai.sel_fg
ai.sel_bg=bc.sel_bg or ai.sel_bg;ai.ok=bc.highlight or ai.ok
ai.warn=bc.warning or ai.warn;ai.err=bc.error or ai.err
ai.panel=bc.panel_bg or ai.panel end end
if ap then
ai={bg=0x000000,fg=0xFFFFFF,dim=0xFFFFFF,title=0xFFFFFF,sel_fg=0x000000,sel_bg=0xFFFFFF,ok=0xFFFFFF,warn=0xFFFFFF,err=0xFFFFFF,panel=0x000000}end
local function ak(be,bf,bg,bc,bd)if bc then pcall(as.setForeground,bc)end;if bd then
pcall(as.setBackground,bd)end;pcall(as.set,be,bf,bg)end
local function ao(be,bf,bg,bh,bi,bc,bd)if bc then pcall(as.setForeground,bc)end;if bd then
pcall(as.setBackground,bd)end;pcall(as.fill,be,bf,bg,bh,bi or" ")end;local aB=nil
do local bc,bd=pcall(require,"unicode")if bc then aB=bd end end
local function aW(bc)local bd=0;for be=1,#bc do local bf=bc:byte(be)
if bf<0x80 or bf>=0xC0 then bd=bd+1 end end;return bd end
local function aX(bc,bd,be)local bg,bf={},0;for bh=1,#bc do local bi=bc:byte(bh)
if bi<0x80 or bi>=0xC0 then bf=bf+1;bg[bf]=bh end end;bg[bf+1]=#bc+1
bd=math.max(1,bd or 1)be=math.min(bf,be or bf)if bd>be then return""end;return bc:sub(bg[bd],
bg[be+1]-1)end
local function ax(bc)return aB and aB.len(bc)or aW(bc)end;local function aN(bc,bd,be)
return aB and aB.sub(bc,bd,be)or aX(bc,bd,be)end
local function al(bc,bd)bc=tostring(bc or"")if
ax(bc)<=bd then return bc end;if bd<=1 then return aN(bc,1,bd)end;return aN(bc,1,bd-1).. (ap and
">"or"…")end;local at=4;local av=an;local ay=aj>=60;local au=
ay and math.max(26,math.floor(aj*0.42))or aj;local aC=au+2;local aD=aj-aC;local aE=ay and
(an-1)or(an-2)local aq=math.max(1,aE-at)
local ar=0
local function aF()for bc,bd in ipairs(e)do if bd.ai then return bc end end;return 1 end
local function aG(bc,bd)local be=bc
while true do local bf=be+bd;if bf<1 or bf>#e then return be end;be=bf;if
e[be]and e[be].ai then return be end end end;local am=aF()
local function aI()local bc=e[am]return bc and bc.ai and c[bc.ai]or nil,
bc and bc.ai or nil end
local function aY()local bc=0;for bd in pairs(d)do bc=bc+1 end;for bd in pairs(p)do bc=bc+1 end;return bc end;local function aO()local b={}
for bd,bc in ipairs(e)do if bc.ai then b[#b+1]=bc.ai end end;return b end;local function aZ(bc)local b={}
for be,bd in ipairs(e)do if bd.ai and
bd.cat==bc then b[#b+1]=bd.ai end end;return b end
local function a_(bc)
local bd=aZ(bc)local be=false;for bg,bf in ipairs(bd)do
if not o(c[bf].name)and not d[bf]then be=true end end
for bg,bf in ipairs(bd)do if not o(c[bf].name)then d[bf]=
be and true or nil end end;q()return be,#bd end;local function ba()local bc=e[am]return bc and bc.cat end
local function aP()
ao(1,1,aj,an," ",ai.fg,ai.bg)local bg=" TOS Optional Utilities "local bl=(ap and"="or"═")
ak(1,1,string.rep(bl,aj),ai.title,ai.bg)
ak(math.max(1,math.floor((aj-#bg)/2)),1,bg,ai.title,ai.bg)local bd=0;for bo,bn in ipairs(e)do if bn.ai then bd=bd+1 end end;local bc;if n~=""then bc=string.format("%d of %d match '%s'",bd,
#c,n)else
bc=string.format("%d add-ons",#c)end
local bh=string.format("%d selected",aY())local be=(ap and"-"or"─")local bi,bj=(ap and"|"or"┤"),(ap and"|"or
"├")local bk=be..
bi.." "..bc.." "..bj
local bf=bi.." "..bh.." "..bj..be;local bm=aj-ax(bk)-ax(bf)
ak(1,2,bk..
string.rep(be,math.max(0,bm))..bf,ai.dim,ai.bg)ak(4,2,bc,ai.fg,ai.bg)
ak(aj-ax(bf)+3,2,bh,ai.fg,ai.bg)
ak(2,3,al("[*] installed  [x] selected  [+] needed by one  [ ] available",aj-3),ai.dim,ai.bg)end
local function aK()if am<ar+1 then ar=am-1 end;if am>ar+aq then ar=am-aq end
if ar<0 then ar=0 end
for bc=0,aq-1 do local bf=ar+bc+1;local bd=at+bc;local be=e[bf]
ao(1,bd,au,1," ",ai.fg,ai.bg)
if be and be.header then local bg=(ap and"-"or"─")
local bh=" "..be.header.." "
ak(1,bd,bg..bg..
bh..string.rep(bg,math.max(0,au-3-ax(bh))),ai.dim,ai.bg)ak(4,bd,be.header,ai.title,ai.bg)elseif be and be.ai then local bl=be.ai
local bi=c[bl]local bm=o(bi.name)
local bo=bm and"[*]"or(d[bl]and"[x]"or
(p[bl]and"[+]"or"[ ]"))local bh=(bf==am)
local bj=bh and ai.sel_fg or(
(bm or bi.reachable==false)and ai.dim or ai.fg)local bk=bh and ai.sel_bg or ai.bg;if bh then
ao(1,bd,au,1," ",bj,bk)end
local bp=bh and bj or
(bm and ai.ok or(d[bl]and ai.warn or
(p[bl]and ai.title or ai.dim)))ak(3,bd,bo,bp,bk)local bq=ay and(au-16)or 17
ak(7,bd,al(bi.name or"?",math.max(4,bq)),bj,bk)
local bn=bi.version and("v"..tostring(bi.version))or""
if ay then
ak(au-8,bd,al(bn,8),bh and bj or ai.dim,bk)else ak(25,bd,al(bn,8),bh and bj or ai.dim,bk)
ak(34,bd,al(
bi.description or"",math.max(0,aj-35)),bh and bj or ai.dim,bk)end end end
if#e>aq then local bc=math.floor(
(ar/math.max(1,#e-aq))* (aq-1)+0.5)for bd=0,aq-1 do
ak(au,
at+bd,(bd==bc)and(ap and"#"or"█")or
(ap and"|"or"│"),ai.dim,ai.bg)end end;if#e==0 then
ak(2,at,al("Nothing matches '"..n.."'.",au-3),ai.warn,ai.bg)
ak(2,at+1,al("Esc clears the filter, / edits it.",au-3),ai.dim,ai.bg)end;if ay then for bc=0,
aq-1 do
ak(au+1,at+bc,ap and"|"or"│",ai.dim,ai.bg)end end end
local function aL()if not ay then return end;local bc=aI()for bm=0,aq-1 do
ao(aC,at+bm,aD,1," ",ai.fg,ai.bg)end;if not bc then return end;local be=at;local function bf(bn,bo,bm)
if be>=at+aq then return end
ak(aC+ (bm or 0),be,al(bn or"",aD- (bm or 0)),bo or ai.fg,ai.bg)be=be+1 end
local function bd(bn,bm,bo)if bm==
nil or bm==""then return end;if be>=at+aq then return end
ak(aC,be,al(bn,10),ai.dim,ai.bg)
ak(aC+10,be,al(tostring(bm),aD-10),bo or ai.fg,ai.bg)be=be+1 end
local function bi(bo,bn,bm)local bq=aD- (bm or 0)local bp=""
for br in
tostring(bo or""):gmatch("%S+")do if bp==""then bp=br elseif ax(bp)+1+ax(br)<=bq then bp=bp.." "..br else
bf(bp,bn,bm)bp=br end end;if bp~=""then bf(bp,bn,bm)end end;bf(bc.name or"?",ai.title)
bf(string.rep(ap and"-"or"─",math.min(aD,40)),ai.dim)
bi(bc.description or"(no description)",ai.fg)bf("",nil)local bk=o(bc.name)local bg=select(2,aI())
local bl=
bk and"already installed"or
(d[bg]and"selected to install"or
(p[bg]and"needed by another choice"or"available"))
bd("Status",bl,bk and ai.ok or
((d[bg]or p[bg])and ai.warn or ai.dim))bd("Version",bc.version)
bd("Category",y(bc.category))bd("Kind",bc.kind)bd("Author",bc.author)
if bc.remote then
bd("From","repo "..tostring(
bc.repo or"?").."  (downloads on install)")elseif bc.reachable then
bd("From",bc.root or(bc.disk and("disk "..bc.disk)))else
bd("On disk",tostring(bc.disk or"?").."  (not inserted)",ai.warn)
bi("selectable — the installer will ask for it",ai.dim,10)end;local bh={}for bn,bm in ipairs(bc.requires or{})do local bo=J(bm)
if bo then bh[#bh+1]=bo end end
if#bh>0 then
bd("Needs",table.concat(bh,", "))local bm=ab(bc)if#bm>0 then
bi("not on any inserted disk: "..table.concat(bm,", "),ai.err,10)end end;if bc.recommends and#bc.recommends>0 then
bd("Suggests",table.concat(bc.recommends,", "),ai.dim)end;local bj=t[bc.name]if bj and
#bj>0 then
bd("Wanted by",table.concat(bj,", "),ai.dim)end end
local function aQ()ao(1,av,aj,1,ap and" "or"░",ai.dim,ai.bg)
if
not ap then ak(1,av,"▓▒░",ai.dim,ai.bg)if aj>6 then
ak(aj-2,av,"░▒▓",ai.dim,ai.bg)end end end
local function aR()
if not ay then local bd=aI()ao(1,aE,aj,1," ",ai.fg,ai.bg)
ao(1,aE+1,aj,1," ",ai.fg,ai.bg)
if bd then local bf=bd.description or"(no description)"
ak(2,aE,al(bf,aj-3),ai.fg,ai.bg)local be={}if bd.category then be[#be+1]=y(bd.category)end;if
o(bd.name)then be[#be+1]="already installed"end;if bd.root then
be[#be+1]=tostring(bd.root)end
if bd.kind then be[#be+1]=tostring(bd.kind)end;if#be>0 then
ak(2,aE+1,al(table.concat(be,"  ·  "),aj-3),ai.dim,ai.bg)end end end;aQ()
local bc=" Space · G Group · / Filter · A All · N None · R +Suggested · Enter Install · Q Quit "ak(5,av,al(bc,aj-9),ai.fg,ai.bg)end;local function aw()aP()aK()aL()aR()end
local function bb()local bd=n;local bc=n
while true do C()am=aF()ar=0;aP()
aK()aL()ao(1,av,aj,1," ",ai.fg,ai.bg)
ak(2,av,al("Filter: "..bc.."_",aj-22),ai.title,ai.bg)
ak(math.max(2,aj-19),av,"Enter=keep Esc=undo",ai.dim,ai.bg)local bg,bh,be,bf=az.pullSignal()
if bg==i then
if bf==28 then n=bc;break elseif bf==1 then n=bd;break elseif bf==14 then
bc=bc:sub(1,-2)n=bc elseif be and be>=32 and be<127 then bc=bc..string.char(be)
n=bc end end end;C()am=aF()ar=0;aw()end;aw()
while true do local be,bf,bc,bd=az.pullSignal()
if be==i then
local function bg(bh)bh()aK()aL()aR()end
if bd==200 then bg(function()am=aG(am,-1)end)elseif bd==208 then bg(function()
am=aG(am,1)end)elseif bd==201 then bg(function()
for bf=1,aq do am=aG(am,-1)end end)elseif
bd==209 then
bg(function()for bf=1,aq do am=aG(am,1)end end)elseif bd==199 then bg(function()am=aF()end)elseif bd==207 then bg(function()
for bf=1,#e do am=aG(am,1)end end)elseif bc==32 then
local bi,bh=aI()
if bi and bh and not o(bi.name)then d[bh]=not d[bh]or nil;q()end;aw()elseif bc==103 or bc==71 then local bh=ba()if bh then local bi,bj=a_(bh)aw()aQ()
ak(5,av,al(string.format(" %s %d in %s ",
bi and"Selected"or"Cleared",bj,y(bh)),aj-9),ai.title,ai.bg)end elseif
bc==47 or bc==63 then bb()elseif bc==97 or bc==65 then for bf,bh in ipairs(aO())do if not o(c[bh].name)then
d[bh]=true end end;q()aw()elseif
bc==110 or bc==78 then
if n==""then d={}else for bf,bh in ipairs(aO())do d[bh]=nil end end;q()aw()elseif bc==114 or bc==82 then local bh={}
for bi in pairs(d)do for bf,bj in
ipairs(c[bi].recommends or{})do local bk=D[bj]
if bk and not o(c[bk].name)then bh[bk]=true end end end;for bi in pairs(bh)do d[bi]=true end;q()aw()elseif
(bd==1 or bc==17)and n~=""then n=""C()am=aF()ar=0;aw()elseif
bc==113 or bc==81 or bc==17 or bd==1 then ao(1,1,aj,an," ",ai.fg,ai.bg)return g elseif bd==28 then local bi=0;local bh,bj={},0
return h,
function(bl,bm,bk)
local function bn(bp)bj=bp
local bq=an-1;local br=math.max(10,aj-18)
local bt=(bi>0)and math.min(1,bp/bi)or 0;local bs=math.floor(br*bt+0.5)
ao(1,bq,aj,1," ",ai.fg,ai.bg)
ak(2,bq,"["..string.rep(ap and"#"or"█",bs)..
string.rep(" ",br-bs).."]",ai.title,ai.bg)
ak(br+5,bq,string.format("%d/%d",bp,bi),ai.dim,ai.bg)end
local function bo()ao(1,1,aj,an," ",ai.fg,ai.bg)
ak(2,1,"Installing…",ai.title,ai.bg)
for bq,bp in pairs(bh)do if bp.name then
ak(2,bq,al(bp.name,aj-20),ai.fg,ai.bg)end;if bp.mark then
ak(aj-16,bq,bp.mark,bp.color,ai.bg)end end;bn(bj)end
if bm=="swap"then local br,bp=pcall(require,"shell.panels.dialogs")
if
br and bp and bp.dialog then local bt={W=aj,H=an,T=ai,D={set=ak,fill=ao}}
local bs=bp.dialog(bt,{style=h,title="Next disk",message=
tostring(bl)..
"\n\nSwap the floppy, then choose Continue.".."\nStopping here keeps everything already installed.",buttons={"Continue","Stop (keep)","Undo all"},default=1,escIndex=2})bo()return
(bs==3 and"undo")or(bs==2 and"abort")or"retry"end;local bq=math.max(2,an-6)ao(1,bq,aj,4," ",ai.fg,ai.bg)ak(2,bq,al(tostring(bl),
aj-4),ai.warn,ai.bg)
ak(2,bq+1,al("Enter = continue   A = stop, keep what's installed   U = undo all",
aj-4),ai.fg,ai.bg)
while true do local bu,bf,bs,bt=az.pullSignal()
if bu==i then
local bv=

(bt==28 and"retry")or((
bs==97 or bs==65 or bt==1)and"abort")or((bs==117 or bs==85)and"undo")or nil;if bv then bo()return bv end end end elseif bm=="begin"then bi=bk or 0;bh,bj={},0;ao(1,1,aj,an," ",ai.fg,ai.bg)
ak(2,1,"Installing…",ai.title,ai.bg)bn(0)elseif bm=="row"then local bp=2+ (bk or 0)if bp<an-2 then
ak(2,bp,al(bl,aj-20),ai.fg,ai.bg)bh[bp]={name=bl}end
bn((bk or 1)-1)elseif bm=="ok"then local bp=2+ (bk or 0)
if bp<an-2 then
ak(aj-16,bp,k,ai.ok,ai.bg)if bh[bp]then bh[bp].mark,bh[bp].color=k,ai.ok end end;bn(bk or 0)elseif bm=="fail"then local bp=2+ (bk or 0)
if bp<an-2 then
local bq=al(tostring(bl),15)ak(aj-16,bp,bq,ai.err,ai.bg)if bh[bp]then
bh[bp].mark,bh[bp].color=bq,ai.err end end;bn(bk or 0)elseif bm=="done"then bn(bi)
ak(2,an,al(tostring(bl).."   Press any key…",
aj-4),ai.fg,ai.bg)
while true do local bp=az.pullSignal()if bp==i then break end end;ao(1,1,aj,an," ",ai.fg,ai.bg)end end end end end end
local function ae()
if not H then
b("No GPU for the menu and no interactive input here.")b("Install from the disk with:")
b("  pkg from-floppy        installs the whole disk, with prompts")
b("  pkg install <name>     one package, e.g.  pkg install tetris")return g end
local function ai()b("")b("=== TOS Optional Utilities ===")
b("  [*] already installed   [x] selected   [ ] available")local aj=nil
for al,ak in ipairs(c)do
if ak.category~=aj then aj=ak.category;b("  -- "..
y(ak.category).." --")end;local am
if o(ak.name)then am="[*]"elseif d[al]then am="[x]"elseif p[al]then am="[+]"else am="[ ]"end
b(string.format("   %2d %s %-16s %s",al,am,ak.name or"?",(ak.description or""):sub(1,42)))end;b("")
b("  <number> toggle  ·  a all  ·  n none  ·  i install  ·  q quit")end
while true do ai()w("> ")local aj=io.read()
if not aj then b("")
b("No interactive input here (panels shell). Install from the disk with:")
b("  pkg from-floppy        installs the whole disk, with prompts")
b("  pkg install <name>     one package, e.g.  pkg install tetris")return g end;aj=aj:gsub("%s+","")
if aj=="q"then
b("Cancelled — nothing installed.")return g elseif aj=="i"then return h elseif aj=="a"then
for ak,al in ipairs(c)do if not o(al.name)then d[ak]=true end end;q()elseif aj=="n"then d={}q()else local ak=tonumber(aj)
if ak and c[ak]then
if o(c[ak].name)then
b("  ("..
c[ak].name.." is already installed)")else d[ak]=not d[ak]or nil;q()end else
b("  ? unrecognised — enter a number, or a/n/i/q")end end end end
local function S()local ak,ai=pcall(require,"kernel.display")if
ak and ai and ai.invalidateColors then pcall(ai.invalidateColors)end
local al,aj=pcall(require,"kernel.screen")
if al and aj and aj.invalidateAll then pcall(aj.invalidateAll)end end;local K,m=ad()S()if K==nil then K=ae()end;if K~=h then return end;local u={}for ai,aj in ipairs(c)do if d[ai]or
p[ai]then u[#u+1]=aj end end
if#u==0 then if m then
m("Nothing selected.","done")else b("Nothing selected.")end;return end;if m then m(nil,"begin",#u)else b("")
b("Installing "..#u.." package(s)...")end;local E,L,v=0,0,{}local F={}local z=0
local function af(ai)
for ak,aj in
ipairs((f.listAllAvailable and
f.listAllAvailable({includeRemote=true}))or{})do if aj.name==ai then return true end end;return false end
local function ag(ai)z=z+1;if m then m(ai.name,"row",z)else
w(string.format("  %-16s ",ai.name))end
local al={session=B,allowUnverified=a.allowUnverified==true,allowUnsigned=a.allowUnsigned==true,force=
a.force==true}local ak,aj;if ai.remote then ak,aj=f.installRemote(ai.name,al)else
ak,aj=f.installByName(ai.name,al)end
if ak then E=E+1;F[#F+1]=ai.name;if m then
m(ai.name,"ok",z)else b(k)end
for an,am in ipairs(ac(ai.name))do v[#v+1]=am end else L=L+1;if m then m(tostring(aj),"fail",z)else
b("FAILED: "..tostring(aj))end end end
local function ah()local ai,aj=0,{}
for ak=#F,1,-1 do local al=F[ak]
local am=f.uninstall and f.uninstall(al,{session=B})if am then ai=ai+1 else aj[#aj+1]=al end end;return ai,aj end;local r={}for aj,ai in ipairs(u)do r[#r+1]=ai end;local M,G=false,nil
while#r>0 do local aj={}
for ao,an in
ipairs(r)do if af(an.name)then ag(an)else aj[#aj+1]=an end end;r=aj;if#r==0 then break end;local ak,al=nil,{}for ao,an in ipairs(r)do ak=ak or an.disk
al[#al+1]=an.name end
local am=string.format("Insert disk %s for: %s",tostring(ak or"?"),table.concat(al,", "))local ai
if m then ai=m(am,"swap")else b("")b(am)
b("  [Enter] continue   [a] stop, keep what's installed   [u] undo everything")w("> ")local an=io.read()
if an==nil then ai="abort"else
an=an:gsub("%s+",""):lower()ai=(an=="u"and"undo")or(an=="a"and"abort")or
"retry"end end
if ai=="undo"then local ao,an=ah()G=ao;if#an>0 then
b("Could NOT remove: "..table.concat(an,", "))end;M=true;break elseif ai=="abort"then M=true;break end end;local s
if G then
s=string.format("Undone: %d package(s) removed, nothing kept.",G)elseif M then
s=string.format("Stopped: %d installed and kept, %d not installed.",E,#r)else
s=string.format("Done: %d installed, %d failed.",E,L)end;if not G and#v>0 then
s=s.."  Start service(s): "..table.concat(v,", ")end
if m then m(s,"done")S()else b("")b(s)
if#v>0 then
b("Service packages installed DISABLED. They register on the next reboot;")b("then enable (and persist) one with:")for aj,ai in ipairs(v)do b(
"  service start "..ai)end end end end;return j