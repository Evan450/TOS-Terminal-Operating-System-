local V,K,W,X="Copied","key_down","scroll","clipboard"
local C=require("computer")local D=require("shell.panels.helpers")
local P=require("shell.panels.tabs")local Q=require("shell.panels.dialogs")
local B=require("shell.panels.draw")local I=require("shell.panels.filebrowser")
local R=require("shell.panels.editor")local L=require("shell.panels.context")
local M=require("shell.panels.menus")local Y=require("shell.panels.mouse")
local H=require("shell.panels.apps")local E=require("shell.panels.home")
local S=require("shell.keys")local F=require("shell.panels.selection")
local J=require("shell.panels.textcol")local G=require("kernel.clipboard")local T=nil;local function Z()if T==nil then
local a,b=pcall(require,"shell.panels.desktop")T=a and b or false end
return T or nil end;local U={}local N
local function _()if
N~=nil then return N or nil end;local a=_G._TOS
if not(a and
(a.powerIdleSec or a.screenBlankSec))then return nil end;local c,b=pcall(require,"kernel.power")N=
(c and type(b)=="table")and b or false;return N or nil end
local aa={[200]=true,[208]=true,[203]=true,[205]=true,[199]=true,[207]=true,[201]=true,[209]=true}local function O()if coroutine.isyieldable and coroutine.isyieldable()then return
coroutine.yield()end
return C.pullSignal(0.1)end
function U.run(a,b)
local f,c,d=a.D,a.T,a.F;local y,aC=a.K,a.E;local l,n=a.W,a.H;local g=a.KEYS;local aD=a.tier;local u=b.C;local h=b.exec
local z=b.makeProgramEnv;local s=b.widgetDefs;a._lastInputAt=C.uptime()a._blanked=nil
local function i()B.all(a,s)end;local function o()B.topBar(a)end;local function am()B.rail(a)end;local function an()
B.sumRail(a)end;local function ao()B.fileList(a)end;local function v(aE,aF)
B.outRow(a,aE,aF)end;local function ap()B.outLines(a)end
local function A()
if a.outLines and#a.outLines>
0 then ap()elseif a.lastOut then
B.outMessage(a,a.lastOut[1],a.lastOut[2])elseif E.isTiles(a)then local aE=a.tabs[a.activeTab]local aF,aG,aH=E.hintText(a,aE)
v(aF,a.T.dim)E.markToggle(a,a.OUT_ROW,aG,aH)else v(nil)end end;local function ab()B.cmdRow(a)end;local function w()B.statusBar(a,s)end;local function aq(aE)
B.viewTab(a,aE)end;local function ar(aE)B.editTab(a,aE)end;local function as()
B.menuDropdown(a)end;local function at()B.contextMenu(a)end;local function j(aE)
return P.close(a,aE)end;local function ac(aE)return P.cycle(a,aE)end;local function ad()return
D.selPath(a)end
local function au(aE,aF)return D.canRead(a,aE,aF)end;local function ae(aE,aF)return D.canWrite(a,aE,aF)end;local function t()return
D.refreshBrowser(a)end
local function af(aE,aF)return R.openViewTab(a,aE,aF)end;local function ag()return L.open(a)end
local function ah()local aG,aE=ad()if
not(aG and aE)or aE.dir then return end;if not au(aG)then return end
local aF={{" Viewing: "..aE.name,c.title}}
local aH,aI,aJ=D.readLinesCapped(d,aG,function(aK)aF[#aF+1]={aK,c.fg}end)if not aH then
a.lastOut={"Cannot read: "..aE.name,c.error}return end;if aJ then
aF[#aF+1]={string.format(D.VIEW_STOPPED,aI),c.warning}end;af(aF,aE.name)end;local function x()return I.navigateUp(a)end;local function ai(aE)
return I.navigateInto(a,aE)end;local function av()return I.doCopy(a)end;local function aw()return
I.doMove(a)end;local function ax()return I.doMkdir(a)end;local function ay()return
I.doDelete(a)end
local function aj(aE,aF,aG)return Q.promptInput(a,aE,aF,aG)end;local function ak(aE)return Q.promptSearch(a,aE)end;local function az(aE)
return D.expandBuf(a,aE)end;local function q()
return S.modDown(a.mods,"shift",C.uptime())end
local function m(aE,aF,aG)return S.is(aE,aF,aG,a.who,a.mods)end;local function e()return a.displayIdx end;local function r(aE)
a.lastOut={aE..": "..G.describe(e()),c.dim}end
local function k(aE)
local aF=a.cmdCursor or(#a.cmdline+1)
aE=math.max(1,math.min(#a.cmdline+1,aE))if q()then if not a.cmdSel then a.cmdSel=aF end
if a.cmdSel==aE then a.cmdSel=nil end else a.cmdSel=nil end
a.cmdCursor=aE end
local function p()local aE,aG,aF=F.remove(a.cmdline,a.cmdSel,a.cmdCursor)
a.cmdline=aE;a.cmdCursor=aF or a.cmdCursor;a.cmdSel=nil;return a.cmdCursor end
local function aA(aE,aF)
if m("copy",aE,aF)then local aG=F.text(a.cmdline,a.cmdSel,a.cmdCursor)if not
aG and a.cmdline~=""then aG=a.cmdline end
if not aG then local aH=(not
E.isTiles(a))and ad()or nil
if aH then
G.set(aH,e())a.lastOut={"Copied path: "..aH,c.dim}return 1 end;a.lastOut={"Nothing to copy",c.dim}return 1 end;G.set(aG,e())r(V)return 1 elseif m("cut",aE,aF)then
local aG=F.text(a.cmdline,a.cmdSel,a.cmdCursor)
if aG then p()elseif a.cmdline~=""then aG=a.cmdline;a.cmdline,a.cmdCursor,a.cmdSel="",1,nil else
a.lastOut={"Nothing to cut",c.dim}return 1 end;G.set(aG,e())r("Cut")return 1 elseif m("paste",aE,aF)then local aG=G.line(e())
if not aG or aG==
""then a.lastOut={"Clipboard empty",c.dim}return 1 end;local aH=p()a.cmdline,a.cmdCursor=F.insert(a.cmdline,aH,aG)if
G.count(e())>1 then
a.lastOut={"Pasted "..G.count(e()).." lines joined with spaces",c.warning}end;return 1 end;return nil end
local aB={menuDefs=a.menuDefs or B.menuDefs,menuExecute=function(aE)return
M.execute(a,aE.action,{exec=h,drawAll=i,widgetDefs=s})end,ctxExecute=function(aE)return
L.execute(a,aE,z,h)end,openContextMenu=ag,viewFile=ah,navigateUp=x,navigateInto=ai,closeTab=j,drawFileListRow=function(aE)B.fileListRow(a,aE)end,cmdColAt=function(aE)return
B.cmdIndexAt(a,aE)end,exec=h}D.loadFiles(a,a.browser)
pcall(function()local aE=D.scanMountedMedia(d)
if aE then
local aF=string.format('%s: "%s" -> %s',aE.desc,
aE.label or"disk",aE.mountPoint)if aE.hint then aF=aF.."   "..aE.hint end
a.lastOut={aF,c.highlight}end end)i()
local function al(aE)if aE<=0 then return end;if a.suspendIdleDraw then return end
local aF=a.tabs[a.activeTab]
if not aF or aF.type=="shell"then
if aE==1 then o()A()ab()w()elseif aE==2 then if E.isTiles(a,aF)then i()else
o()am()ao()an()A()ab()w()end elseif aE>=3 then i()end;if a.menuOpen then as()end;if a.ctxOpen then at()end elseif aF.type=="view"or
aF.type=="output"then o()aq(aF)elseif aF.type=="edit"then o()ar(aF)else
H.ensureBuiltins()local aG=H.get(aF.type)
if aG and aG.draw then o()aG.draw(a,aF)end end end
while true do if a._exitTo then local aR=a._exitTo;a._exitTo=nil;return aR end
local aI,aN,aH,aG,aO=O()local aF=0
do
local aR=

aI==K or aI=="key_up"or aI=="touch"or aI=="drag"or aI=="drop"or aI==W or aI==X
if aR then a._lastInputAt=C.uptime()if a._blanked then a._blanked=nil;i()
aI,aN,aH,aG,aO=nil,nil,nil,nil,nil end end end;local aP=false;if aI==K or aI=="key_up"then
aP=S.trackMods(a.mods,aI,aH,aG,C.uptime())end;local aQ=a.outLines~=nil;local aL=a.browser and
a.browser.sel
local aM=a.browser and a.browser.scroll;local aE=a.tabs[a.activeTab]
if a.suspendIdleDraw and
(

aI==K or aI=="touch"or aI=="drag"or aI=="drop"or aI==W or aI==X or aI=="tos_focus"or aI=="tos_monitor")then
a.suspendIdleDraw=nil end
if aI==K and not aP then
if a.ctxOpen then
if aG==200 then L.nextItem(a,-1)elseif aG==208 then
L.nextItem(a,1)elseif aG==28 then local aR=a.ctxItems[a.ctxSel]if aR and not aR.sep then
L.execute(a,aR.action,z,h)end elseif aH==17 then a.ctxOpen=false end;aF=3 elseif a.menuOpen then local aR=a.menuDefs or B.menuDefs
if aG==200 then
M.menuNextItem(a,-1)elseif aG==208 then M.menuNextItem(a,1)elseif aG==28 then
local aS=aR[a.menuOpen].items[a.menuSel]
if aS and not aS.sep then
local aT=M.execute(a,aS.action,{exec=h,drawAll=i,widgetDefs=s})if aT then return aT end end elseif aH==17 then a.menuOpen=nil;a.menuFocused=false elseif aG==203 then a.menuOpen=
a.menuOpen>1 and a.menuOpen-1 or#aR;a.menuSel=1 elseif aG==205 then a.menuOpen=
a.menuOpen<#aR and a.menuOpen+1 or 1
a.menuSel=1 end;aF=3 elseif a.menuFocused then local aR=a.menuDefs or B.menuDefs
if aG==203 then a.menuIdx=a.menuIdx>1 and
a.menuIdx-1 or#aR elseif aG==205 then
a.menuIdx=
a.menuIdx<#aR and a.menuIdx+1 or 1 elseif aG==28 then a.menuOpen=a.menuIdx;a.menuSel=1 elseif aH==17 then a.menuFocused=false end;aF=3 else local aR=false
if E.isViewKey(a,aH,aG)then
if E.enabled(a)then
if aE and
(aE.type==nil or aE.type=="shell")then E.toggle(a,aE)else for aS,aT in ipairs(a.tabs)do if aT.type=="shell"then
a.activeTab=aS;break end end end else ac(1)end;aF=3;aR=true elseif aG==g.tabClose then
if aE and aE.type~="shell"then
if
aE.type=="edit"and aE.modified then f.fill(1,n,l,1," ",c.fg,c.bg)
f.set(1,n," Unsaved! [y]Close [n]Cancel",c.warning,c.bg)while true do local aT,aU,aS=O()
if aT==K then if aS==121 or aS==89 then j()break else break end end end else j()end;aF=3 end;aR=true elseif aG==g.menu then
if aE and aE.type~="shell"then a.activeTab=1 end;a.menuFocused=not a.menuFocused
if not a.menuFocused then a.menuOpen=nil end;aF=3;aR=true elseif aG==g.quit then a.activeTab=1;i()
f.fill(1,a.OUT_ROW,l,1," ",c.fg,c.bg)
f.set(1,a.OUT_ROW,(" [1]Reboot [2]Shut down [3]Log out [4]CLI Mode [^Q]Cancel"):sub(1,l),c.title,c.bg)
while true do local aT,aU,aS=O()
if aT==K then
if aS==49 or aS==50 then local aV,aW=D.canPowerOff(a)
if not aV then
f.fill(1,a.OUT_ROW,l,1," ",c.fg,c.bg)f.set(1,a.OUT_ROW,aW:sub(1,l),c.error,c.bg)else if
_G._TOS.audio then _G._TOS.audio.shutdown()end;if
aS==49 then y.reboot()else y.shutdown()end;return"exit"end elseif aS==51 then
if _G._TOS.audio then _G._TOS.audio.shutdown()end;D.logout(a)return"exit"elseif aS==52 then return"cli"elseif aS==17 then a.lastOut=nil;break end end end;aF=3;aR=true end
if not aR and aE then
if aE.type=="shell"then local aS=E.isTiles(a,aE)local aU=aA(aH,aG)
local aT=nil
if not aU and q()and a.cmdline~=""then
local aX=a.cmdCursor or(#a.cmdline+1)if aG==203 then k(aX-1)aT=1 elseif aG==205 then k(aX+1)aT=1 elseif aG==199 then k(1)aT=1 elseif aG==207 then
k(#a.cmdline+1)aT=1 end end;local aV,aW;if not aU and not aT and aS then
aV,aW=E.handleKey(a,aE,aH,aG,{exec=h})end
if aU then aF=aU elseif aT then aF=aT elseif aV~=nil then
if aW=="exit"then return aW end;aF=aV elseif aG==g.help then local aY={}local function aZ(a_,ba)aY[#aY+1]={a_,ba}end
u.help({},aZ)local aX=nil;for ba,a_ in ipairs(a.tabs)do if a_.label=="Help"and a_.type=="view"then aX=ba
break end end;if
aX then a.tabs[aX].content=az(aY)a.tabs[aX].offset=0
a.activeTab=aX else af(aY,"Help")end;aF=3 elseif not aS and aG==
g.viewFile then ah()aF=3 elseif not aS and aG==g.copy then av()aF=3 elseif
not aS and aG==g.move then aw()aF=3 elseif not aS and aG==g.mkdir then ax()aF=3 elseif not aS and aG==g.delete then ay()
aF=3 elseif aG==200 and not aS then
if a.browser.sel>1 then local aL=a.browser.sel
local aM=a.browser.scroll;a.browser.sel=aL-1;if a.browser.sel<=a.browser.scroll then a.browser.scroll=
a.browser.sel-1 end;if
a.browser.scroll==aM then B.fileListRow(a,aL)
B.fileListRow(a,a.browser.sel)aF=0 else aF=2 end else aF=0 end elseif aG==208 and not aS then
if a.browser.sel<#a.browser.files then
local aL=a.browser.sel;local aM=a.browser.scroll;a.browser.sel=aL+1;if a.browser.sel>a.browser.scroll+
a.LIST_H then
a.browser.scroll=a.browser.sel-a.LIST_H end
if a.browser.scroll==aM then
B.fileListRow(a,aL)B.fileListRow(a,a.browser.sel)aF=0 else aF=2 end else aF=0 end elseif aG==201 then
a.browser.sel=math.max(1,a.browser.sel-a.LIST_H)
a.browser.scroll=math.max(0,a.browser.scroll-a.LIST_H)aF=2 elseif aG==209 then
a.browser.sel=math.min(#a.browser.files,a.browser.sel+a.LIST_H)
a.browser.scroll=math.min(math.max(0,#a.browser.files-a.LIST_H),
a.browser.scroll+a.LIST_H)aF=2 elseif aG==203 then
if a.cmdline~=""then k(
(a.cmdCursor or(#a.cmdline+1))-1)aF=1 end elseif aG==205 then
if a.cmdline~=""then k(
(a.cmdCursor or(#a.cmdline+1))+1)aF=1 end elseif aG==199 then
if a.cmdline~=""then k(1)aF=1 else a.browser.sel=1;a.browser.scroll=0;aF=2 end elseif aG==207 then if a.cmdline~=""then k(#a.cmdline+1)aF=1 else a.browser.sel=#
a.browser.files
a.browser.scroll=math.max(0,#a.browser.files-a.LIST_H)aF=2 end elseif aG==
14 then local aX=a.cmdCursor or(#a.cmdline+1)
if a.cmdSel then p()
aF=1 elseif aX>1 then
a.cmdline=a.cmdline:sub(1,aX-2)..a.cmdline:sub(aX)a.cmdCursor=aX-1;aF=1 elseif a.cmdline==""and not aS then x()aF=3 end elseif aG==211 and a.cmdSel then p()aF=1 elseif aG==211 then
local aX=a.cmdCursor or(#a.cmdline+1)if aX<=#a.cmdline then
a.cmdline=a.cmdline:sub(1,aX-1)..a.cmdline:sub(aX+1)aF=1 end elseif aG==28 then
if a.cmdline~=""then
local aY=a.cmdline;a.cmdline=""a.cmdCursor=1;a.cmdHistIdx=0;a.cmdSel=nil;local aX=aY:lower()
local a_=
aX:find("trust setsecret",1,true)or aX:find("trust generatesecret",1,true)or
aX:find("trust key ",1,true)or
aX:find("changepass ",1,true)or
aX:find("usermod ",1,true)and aX:find(" pass",1,true)
if not a_ then local bc=200
if#a.cmdHistory==0 or
a.cmdHistory[#a.cmdHistory]~=aY then
a.cmdHistory[#a.cmdHistory+1]=aY
if#a.cmdHistory>bc then table.remove(a.cmdHistory,1)end end end;a.outLines=nil
local aZ=(aY:match("^(%S+)")or""):lower()local d=a.F
local function ba(bc)if bc==""or(u and u[bc])then return false end
if
D.mayHavePackages()then local be,bd=pcall(require,"kernel.pkg")if be and bd and bd.getCommand and
bd.getCommand(bc)then return true end end
if d and d.exists and d.join then
for be,bd in
ipairs({"/bin","/usr/bin","/tos/shell"})do if
d.exists(d.join(bd,bc..".lua"))or d.exists(d.join(bd,bc))then return true end end end;return false end
local function bb(bc)local bf,bd=pcall(require,"shell.panels.commands")local be=
bf and bd and bd.entry and bd.entry(bc)return
type(be)=="table"and be.slow==true end;if ba(aZ)or bb(aZ)then
v("Running "..aZ.."\226\128\166",c.dim)end;h(aY)else
local aX=a.browser.files[a.browser.sel]if aX then
if aX.name==".."then x()elseif aX.dir then ai(aX.name)else ag()end end end;aF=3 elseif aH==17 then a.cmdline=""a.cmdCursor=1;a.cmdSel=nil;if a.clipboard then a.clipboard=nil
a.lastOut={"Copy cancelled",c.dim}aF=3 else a.lastOut=nil;aF=1 end elseif
aH==16 and aG~=200 then
if a.cmdHistIdx==0 then a.cmdHistIdx=#a.cmdHistory elseif
a.cmdHistIdx>1 then a.cmdHistIdx=a.cmdHistIdx-1 end
if a.cmdHistIdx>0 then a.cmdline=a.cmdHistory[a.cmdHistIdx]end;a.cmdCursor=#a.cmdline+1;a.cmdSel=nil;aF=1 elseif aH==14 and aG~=14 then
if a.cmdHistIdx<#
a.cmdHistory then a.cmdHistIdx=a.cmdHistIdx+1
a.cmdline=a.cmdHistory[a.cmdHistIdx]else a.cmdHistIdx=0;a.cmdline=""end;a.cmdCursor=#a.cmdline+1;a.cmdSel=nil;aF=1 elseif
aG==15 and a.cmdline==""and E.enabled(a)then ac(1)aF=3 elseif aG==15 then
local bc,a_=pcall(require,"shell.panels.commands")
local aX=(bc and a_.commandNames)and a_.commandNames()or{}local bd,aY=pcall(require,"kernel.pkg")
if bd and aY and aY.commands then
local bg,bf=pcall(aY.commands)if bg and type(bf)=="table"then
for bh in pairs(bf)do aX[#aX+1]=bh end end end
local ba=a.cwd or(a.browser and a.browser.path)or"/"
local function be(bf)local bi=(bf:sub(1,1)=="/")and bf or
(bf==""and ba or d.join(ba,bf))local bh={}
local bj,bg=pcall(d.list,bi)
if bj and bg then local bk={}if type(bg)=="table"then bk=bg elseif type(bg)=="function"then for bl in bg do
bk[#bk+1]=bl end end
for bm,bl in ipairs(bk)do
local bo=bl:gsub("/$","")local bn=bl:sub(-1)=="/"if not bn then
local bp,bq=pcall(d.isDirectory,d.join(bi,bo))bn=bp and bq end
bh[#bh+1]={name=bo,dir=bn}end end;return bh end;local bb,aZ=D.completeCmdline(a.cmdline,aX,be)if bb~=a.cmdline then
a.cmdline=bb;a.cmdHistIdx=0 end;a.cmdCursor=#a.cmdline+1;if#
aZ>1 then a.outLines=nil
a.lastOut={(#aZ.." matches: "..table.concat(aZ,"  ")):sub(1,l),c.dim}end;aF=1 elseif
aH and aH>=32 and aH<127 then
local aX=a.cmdSel and p()or(a.cmdCursor or(#a.cmdline+1))a.cmdline=a.cmdline:sub(1,aX-1)..
string.char(aH)..a.cmdline:sub(aX)
a.cmdCursor=aX+1;a.cmdHistIdx=0;aF=1 end elseif aE.type=="view"or aE.type=="output"then
local aS=aE.content or{}local aT=n-2
local function aU(aV)local aX=aE.selCur or(aE.offset+1)local aW=math.max(1,math.min(#aS,
aX+aV))if not aE.selAnchor then
aE.selAnchor=aX end;aE.selCur=aW
if aW<=aE.offset then
aE.offset=math.max(0,aW-1)elseif aW>aE.offset+aT then aE.offset=aW-aT end end
if aH==17 or aH==113 then j()aF=3 elseif m("copy",aH,aG)then
local aV=F.lines(aS,aE.selAnchor,aE.selCur)
if not aV then aV=F.lines(aS,aE.offset+1,aE.offset+1)end
if aV then G.set(aV,e())r(V)else a.lastOut={"Nothing to copy",c.dim}end;aF=3 elseif q()and aG==200 then aU(-1)aF=3 elseif q()and aG==208 then aU(1)aF=3 elseif

aG==200 or aG==208 or aG==201 or aG==209 or aG==199 or aG==207 then aE.selAnchor,aE.selCur=nil,nil
if aG==200 and
aE.offset>0 then aE.offset=aE.offset-1;aF=1 elseif aG==208 and
aE.offset+aT<#aS then aE.offset=aE.offset+1;aF=1 elseif aG==201 then
aE.offset=math.max(0,aE.offset-aT)aF=1 elseif aG==209 then
aE.offset=math.min(math.max(0,#aS-aT),aE.offset+aT)aF=1 elseif aG==199 then aE.offset=0;aF=1 elseif aG==207 then aE.offset=math.max(0,#aS-aT)
aF=1 else aF=1 end elseif aE.live and(aH==114 or aH==82)then
R.refreshLiveTab(a,aE)aE.lastRefresh=C.uptime()aF=3 elseif aH==6 then local aV=ak(aE.searchTerm)
aE.searchTerm=aV
if aV then
for aW=aE.offset+1,#aS do local aX=aS[aW]
local aY=type(aX)=="table"and aX[1]or tostring(aX)
if aY:find(aV,1,true)then aE.offset=math.max(0,aW-1)break end end end;aF=3 end elseif aE.type=="edit"then local aS=aE.lines;local aW=n-2
local function aT()
aE.curRow=math.max(1,math.min(#aS,aE.curRow))
aE.curCol=math.max(1,math.min(# (aS[aE.curRow]or"")+1,aE.curCol))if aE.curRow<aE.viewTop then aE.viewTop=aE.curRow end
if aE.curRow>
aE.viewTop+aW-1 then aE.viewTop=aE.curRow-aW+1 end end
local function aU()if not aE.undoStack then aE.undoStack={}end;local aZ={}for a_,ba in ipairs(aS)do
aZ[a_]=ba end
aE.undoStack[#aE.undoStack+1]={lines=aZ,row=aE.curRow,col=aE.curCol}if#aE.undoStack> (aE.undoMax or 32)then
table.remove(aE.undoStack,1)end end;if aE.suggest and aH~=15 then aE.hintSeen=true end
aE.flash=nil;local aV=nil;local aX={row=aE.curRow,col=aE.curCol}
if m("copy",aH,aG)then local aZ=
F.extract(aS,aE.selAnchor,aX)or{aS[aE.curRow]}
G.set(aZ,e())r(V)aV=1 elseif m("cut",aH,aG)then aU()local aZ=F.extract(aS,aE.selAnchor,aX)
if aZ then
local bb,a_,ba=F.removeBlock(aS,aE.selAnchor,aX)aE.curRow,aE.curCol=a_,ba;aE.selAnchor=nil else aZ={aS[aE.curRow]}
if#aS>
1 then table.remove(aS,aE.curRow)else aS[1]=""end end;G.set(aZ,e())aE.modified=true;aT()r("Cut")aV=1 elseif m("paste",aH,aG)then
local aZ=G.get(e())
if aZ and#aZ>0 then aU()
if aE.selAnchor then
local bb,a_,ba=F.removeBlock(aS,aE.selAnchor,aX)aE.curRow,aE.curCol=a_,ba;aE.selAnchor=nil end
aE.curRow,aE.curCol=F.insertBlock(aS,aE.curRow,aE.curCol,aZ)aE.modified=true;aT()
a.lastOut={"Pasted "..#aZ.." line(s)",c.dim}else a.lastOut={"Clipboard empty",c.dim}end;aV=1 end;if aa[aG]then
if q()then if not aE.selAnchor then
aE.selAnchor={row=aE.curRow,col=aE.curCol}end else aE.selAnchor=nil end end
local function aY(aZ)local a_=J.cellOf(
aS[aE.curRow]or"",aE.curCol)aE.curRow=math.max(1,math.min(
#aS,aZ))
aE.curCol=J.colOf(aS[aE.curRow]or"",a_)aT()end
if aV then aF=aV elseif aG==200 then aY(aE.curRow-1)aF=1 elseif aG==208 then
aY(aE.curRow+1)aF=1 elseif aG==203 then if aE.curCol>1 then
aE.curCol=J.prevCol(aS[aE.curRow],aE.curCol)elseif aE.curRow>1 then aE.curRow=aE.curRow-1
aE.curCol=#aS[aE.curRow]+1 end;aT()
aF=1 elseif aG==205 then
if aE.curCol<=#aS[aE.curRow]then
aE.curCol=J.nextCol(aS[aE.curRow],aE.curCol)elseif aE.curRow<#aS then aE.curRow=aE.curRow+1;aE.curCol=1 end;aT()aF=1 elseif aG==199 then aE.curCol=1;aF=1 elseif aG==207 then
aE.curCol=#aS[aE.curRow]+1;aF=1 elseif aG==201 then aY(aE.curRow-aW)aF=1 elseif aG==209 then
aY(aE.curRow+aW)aF=1 elseif(aG==14 or aG==211)and aE.selAnchor then aU()
local ba,aZ,a_=F.removeBlock(aS,aE.selAnchor,{row=aE.curRow,col=aE.curCol})aE.curRow,aE.curCol=aZ,a_;aE.selAnchor=nil;aE.modified=true;aT()aF=1 elseif aG==14 then
if
aE.curCol>1 then local aZ=aS[aE.curRow]local a_=J.prevCol(aZ,aE.curCol)aS[aE.curRow]=aZ:sub(1,
a_-1)..aZ:sub(aE.curCol)
aE.curCol=a_;aE.modified=true;aF=1 elseif aE.curRow>1 then aU()
aE.curCol=#aS[aE.curRow-1]+1
aS[aE.curRow-1]=aS[aE.curRow-1]..aS[aE.curRow]table.remove(aS,aE.curRow)aE.curRow=aE.curRow-1
aE.modified=true;aT()aF=1 end elseif aG==211 then local aZ=aS[aE.curRow]
if aE.curCol<=#aZ then
aS[aE.curRow]=
aZ:sub(1,aE.curCol-1)..aZ:sub(J.nextCol(aZ,aE.curCol))aE.modified=true;aF=1 elseif aE.curRow<#aS then aU()
aS[aE.curRow]=aZ..aS[aE.curRow+1]table.remove(aS,aE.curRow+1)aE.modified=true;aF=1 end elseif aG==28 then aU()local bb=aS[aE.curRow]
local ba=bb:sub(1,aE.curCol-1)local bc=bb:sub(aE.curCol)aS[aE.curRow]=ba
local a_=ba:match("^(%s*)")or""local aZ=ba:match("^%s*(.-)%s*$")or""
if

aZ:match("then$")or
aZ:match("do$")or aZ:match("repeat$")or
aZ:match("else$")or aZ:match("function%s*%(.*%)%s*$")or aZ:match("{%s*$")then a_=a_.."  "end;table.insert(aS,aE.curRow+1,a_..bc)
aE.curRow=aE.curRow+1;aE.curCol=#a_+1;aE.modified=true;aT()aF=1 elseif aG==15 then local aZ=aS[aE.curRow]
aS[aE.curRow]=aZ:sub(1,
aE.curCol-1).."  "..aZ:sub(aE.curCol)aE.curCol=aE.curCol+2;aE.modified=true;aF=1 elseif aH==17 then
if aE.modified then
f.fill(1,n,l,1," ",c.fg,c.bg)
f.set(1,n," Save? [y]es [n]o [c]ancel",c.warning,c.bg)local a_,ba,aZ=O()
if a_==K then
if aZ==121 or aZ==89 then
if aE.path then local bb=
(d.normalize and d.normalize(aE.path))or aE.path;if ae(bb)then
d.writeFile(bb,table.concat(aS,"\n"))t()end end;j()aF=3 elseif aZ==110 or aZ==78 then j()aF=3 else aF=1 end end else j()aF=3 end elseif aH==15 and aE.suggest then
if aE.modified then aE.flash="Save first (^S): "..
aE.suggest.cmd.." reads the file from disk."aF=1 elseif
aE.path then local aZ,a_=aE.path,aE.suggest.cmd;j()
local ba,bb=pcall(require,"shell.open")
if ba then h(a_.." "..bb.quote(aZ))end;aF=3 end elseif aH==19 then
if aE.path then local aZ=(d.normalize and d.normalize(aE.path))or
aE.path
if ae(aZ)then
if
d.writeFile(aZ,table.concat(aS,"\n"))then aE.path=aZ;aE.modified=false
a.lastOut={"Saved: "..aE.label,c.highlight}t()else a.lastOut={"Save failed!",c.error}end end elseif not aE.path then a.lastOut={"No path set",c.error}end;aF=1 elseif aH==6 then local aZ=ak(aE.searchTerm)
if aZ and#aZ>0 then aE.searchTerm=aZ
local a_=false
for ba=aE.curRow,#aS do
local bc=ba==aE.curRow and aE.curCol+1 or 1;local bb=aS[ba]:find(aZ,bc,true)if bb then aE.curRow=ba;aE.curCol=bb;a_=true
break end end;if not a_ then
for ba=1,aE.curRow-1 do local bb=aS[ba]:find(aZ,1,true)if bb then aE.curRow=ba
aE.curCol=bb;a_=true;break end end end
if not a_ then a.lastOut={
"Not found: "..aZ,c.warning}end;aT()elseif aZ==nil then aE.searchTerm=nil end;aF=1 elseif aH==8 then local aZ=aj("Find: ",40)
if aZ and#aZ>0 then
local a_=aj("Replace with: ",40)
if a_ then local function bc(bg)
return(bg:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])","%%%1"))end;local function bd(bg)
return(bg:gsub("%%","%%%%"))end;local be=bc(aZ)local bf=bd(a_)local ba=0
if aE.undoStack then local bg={}for bh,bi in
ipairs(aS)do bg[bh]=bi end
aE.undoStack[#aE.undoStack+1]={lines=bg,row=aE.curRow,col=aE.curCol}if#aE.undoStack> (aE.undoMax or 32)then
table.remove(aE.undoStack,1)end end;local bb=true
for bg=1,#aS do local bi,bj,bh=pcall(string.gsub,aS[bg],be,bf,nil)if
not bi then bb=false;break end;if bh>0 then aS[bg]=bj;ba=ba+bh end end
if not bb then
a.lastOut={"Replace failed (pattern error)",c.error}if aE.undoStack and#aE.undoStack>0 then aE.undoStack[#aE.undoStack]=
nil end elseif ba>0 then
aE.modified=true
a.lastOut={"Replaced "..ba.." occurrence(s)",c.highlight}else a.lastOut={"Not found: "..aZ,c.warning}if aE.undoStack and
#aE.undoStack>0 then
aE.undoStack[#aE.undoStack]=nil end end end end;aF=1 elseif aH==26 then
if aE.undoStack and#aE.undoStack>0 then
local aZ=table.remove(aE.undoStack)aE.lines=aZ.lines;aS=aE.lines;aE.curRow=aZ.row;aE.curCol=aZ.col
aE.modified=true;aT()a.lastOut={"Undo",c.dim}else
a.lastOut={"Nothing to undo",c.dim}end;aF=1 elseif aH and aH>=32 and aH<127 then
if aE.selAnchor then aU()
local bb,a_,ba=F.removeBlock(aS,aE.selAnchor,{row=aE.curRow,col=aE.curCol})aE.curRow,aE.curCol=a_,ba;aE.selAnchor=nil end;local aZ=aS[aE.curRow]
aS[aE.curRow]=aZ:sub(1,aE.curCol-1)..
string.char(aH)..aZ:sub(aE.curCol)aE.curCol=aE.curCol+1;aE.modified=true;aF=1 end else H.ensureBuiltins()local aS=H.get(aE.type)
if aS and aS.onKey then
local aU,aT=aS.onKey(a,aE,{ch=aH,co=aG,exec=h})if aT then return aT end;aF=aU or 0 end end end end elseif
aI=="touch"or aI=="drag"or aI=="drop"or aI==W then local aS,aR=Y.handle(a,aB,aI,aN,aH,aG,aO)if aR then return aR end
aF=aS or 0 elseif aI==X and type(aH)=="string"then
if aE and aE.type=="shell"then
local aS=aH:gsub("[\r\n]+"," ")
local aR=a.cmdSel and p()or(a.cmdCursor or(#a.cmdline+1))
a.cmdline=a.cmdline:sub(1,aR-1)..aS..a.cmdline:sub(aR)a.cmdCursor=aR+#aS;aF=1 elseif aE and aE.type=="edit"then
local aR=aH:gsub("\n"," "):gsub("\r","")local aS=aE.lines[aE.curRow]
aE.lines[aE.curRow]=
aS:sub(1,aE.curCol-1)..aR..aS:sub(aE.curCol)aE.curCol=aE.curCol+#aR;aE.modified=true;aF=1 end elseif aI=="tos_focus"then c=f.getTheme()a.T=c;aF=3
local aR=a.tabs and a.tabs[a.activeTab]
if aR and aR.type=="program"then local aS=1
for aU,aT in ipairs(a.tabs)do if aT.type=="shell"or
aT.type==nil then aS=aU;break end end;a.activeTab=aS end elseif aI=="tos_monitor"then
local aS,aR=pcall(require,"shell.panels.monitorapp")
if aS and aR then a.menuOpen=nil;a.menuFocused=false;a.ctxOpen=false;aR.open(a)aF=3 end elseif aI=="tos_interrupt"then if aE and aE.type=="shell"then
if a.cmdline~=""then a.cmdline=""
a.cmdCursor=1;a.cmdSel=nil;a.lastOut={"^C",c.dim}end;aF=1 end elseif aI==
"tos_disk_added"or aI=="tos_disk_removed"then if
D.announceDisk(a,d,
aI=="tos_disk_added"and"added"or"removed",aH,aG)then pcall(t)end;aF=3 elseif
aI=="component_added"or aI=="component_removed"then aF=3 elseif aI=="screen_resized"then
local aS,aR=pcall(require,"shell.panels.state")
if aS and aR and aR.recomputeLayout then pcall(aR.recomputeLayout,a)end;pcall(t)aF=3 end
if
aQ and a.outLines and a.browser and(a.browser.sel~=aL or
a.browser.scroll~=aM)then a.outLines=nil;if aF<2 then aF=2 end end;if aQ and not a.outLines and aF<2 then aF=2 end
al(aF)do local aR=C.uptime()
if
aR- (a._lastSwapSweep or 0)>=1 then a._lastSwapSweep=aR;pcall(P.sweepCold,a)end end
do local aR=C.uptime()
if

aR- (
a._lastNotice or 0)>=1 and not a.suspendIdleDraw and not a.menuOpen and not a.ctxOpen then a._lastNotice=aR;local aT,aS=pcall(require,"kernel.notify")
if aT and type(aS)==
"table"then
if a._noticeSeen==nil then a._noticeSeen=aS.highWater()end;aS.sweep()local aV=aS.pending(a._noticeSeen)
local aU=aS.nextToShow(aV,a._noticeShownAt)
if aU then a._noticeSeen=aU.seq
local aW,aX=pcall(Q.dialog,a,{style=aU.style,title=aU.title,message=aU.message.."\n\nFrom: "..aU.from,buttons=aU.buttons,closeIf=function()return
aS.result(aU.id)~=nil end})if not(aW and aX==nil)then
aS.settle(aU.id,aW and aX or 1)end;a._noticeShownAt=C.uptime()
a._lastInputAt=a._noticeShownAt;a._blanked=nil;i()end end end end;local aK=_()
if
aK and not a.suspendIdleDraw and not a.menuOpen and not a.ctxOpen and
aK.shouldBlank(C.uptime(),a._lastInputAt,a._blanked)then
a._blanked=true;pcall(f.fill,1,1,a.W,a.H," ",c.fg,0x000000)end;local aJ=a.tabs[a.activeTab]
if a._blanked then elseif a.suspendIdleDraw then
local aR=_G._TOS and _G._TOS.kernel
if aR and aR.isForeground then local aS,aT=pcall(aR.isForeground)if aS and aT then
a.suspendIdleDraw=nil;i()end end elseif

aJ and(aJ.type==nil or aJ.type=="shell")and not a.menuOpen and not a.ctxOpen then local aR=C.uptime()
if
aR- (a._lastStatusT or 0)>= ((aK and
aK.idleSeconds())or 1)then a._lastStatusT=aR;w()
if H.chipsChanged and H.chipsChanged(a)then o()end;if E.isTiles(a,aJ)then E.drawHeader(a,aJ)end end elseif aJ and aJ.type=="desktop"and not a.menuOpen and
not a.ctxOpen then local aR=C.uptime()
if aR-
(a._lastStatusT or 0)>=
((aK and aK.idleSeconds())or 1)then a._lastStatusT=aR;local aS=Z()if aS then
aS.drawHeader(a,aJ)end end elseif
aJ and aJ.type=="view"and aJ.live and not a.menuOpen and not a.ctxOpen then local aR=C.uptime()
if
aR- (aJ.lastRefresh or
0)>= (aJ.interval or 1)then aJ.lastRefresh=aR;R.refreshLiveTab(a,aJ)B.viewTab(a,aJ)end elseif aJ and not a.menuOpen and not a.ctxOpen then
local aR=H.get(aJ.type)
if aR and aR.tick then local aS=C.uptime()
if aS- (aJ.lastRefresh or 0)>= (
aJ.interval or 2)then aJ.lastRefresh=aS
local aT=aR.tick(a,aJ)if aT and aT>0 then al(aT)end end end end end end;return U