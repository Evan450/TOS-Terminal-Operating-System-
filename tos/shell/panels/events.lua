local V,W,K,X="Copied","clipboard","key_down","scroll"
local C=require("computer")local D=require("shell.panels.helpers")
local Q=require("shell.panels.tabs")local R=require("shell.panels.dialogs")
local B=require("shell.panels.draw")local I=require("shell.panels.filebrowser")
local S=require("shell.panels.editor")local L=require("shell.panels.context")
local N=require("shell.panels.menus")local Y=require("shell.panels.mouse")
local H=require("shell.panels.apps")local E=require("shell.panels.home")
local M=require("shell.keys")local F=require("shell.panels.selection")
local J=require("shell.panels.textcol")local G=require("kernel.clipboard")local T=nil;local function Z()if T==nil then
local a,b=pcall(require,"shell.panels.desktop")T=a and b or false end
return T or nil end;local U={}local O
local function _()if
O~=nil then return O or nil end;local a=_G._TOS
if not(a and
(a.powerIdleSec or a.screenBlankSec))then return nil end;local c,b=pcall(require,"kernel.power")O=
(c and type(b)=="table")and b or false;return O or nil end
local aa={[200]=true,[208]=true,[203]=true,[205]=true,[199]=true,[207]=true,[201]=true,[209]=true}local function P()if coroutine.isyieldable and coroutine.isyieldable()then return
coroutine.yield()end
return C.pullSignal(0.1)end
function U.run(a,b)
local f,c,d=a.D,a.T,a.F;local z,aD=a.K,a.E;local l,o=a.W,a.H;local g=a.KEYS;local aE=a.tier;local v=b.C;local h=b.exec
local A=b.makeProgramEnv;local t=b.widgetDefs;a._lastInputAt=C.uptime()a._blanked=nil
local function i()B.all(a,t)end;local function p()B.topBar(a)end;local function an()B.rail(a)end;local function ao()
B.sumRail(a)end;local function ap()B.fileList(a)end;local function w(aF,aG)
B.outRow(a,aF,aG)end;local function aq()B.outLines(a)end
local function ab()
if a.outLines and#a.outLines>
0 then aq()elseif a.lastOut then
B.outMessage(a,a.lastOut[1],a.lastOut[2])elseif E.isTiles(a)then local aF=a.tabs[a.activeTab]local aG,aH,aI=E.hintText(a,aF)
w(aG,a.T.dim)E.markToggle(a,a.OUT_ROW,aH,aI)else w(nil)end end;local function ac()B.cmdRow(a)end;local function x()B.statusBar(a,t)end;local function ar(aF)
B.viewTab(a,aF)end;local function as(aF)B.editTab(a,aF)end;local function at()
B.menuDropdown(a)end;local function au()B.contextMenu(a)end;local function j(aF)
return Q.close(a,aF)end;local function ad(aF)return Q.cycle(a,aF)end;local function ae()return
D.selPath(a)end
local function av(aF,aG)return D.canRead(a,aF,aG)end;local function af(aF,aG)return D.canWrite(a,aF,aG)end;local function u()return
D.refreshBrowser(a)end
local function ag(aF,aG)return S.openViewTab(a,aF,aG)end;local function ah()return L.open(a)end
local function ai()local aH,aF=ae()if
not(aH and aF)or aF.dir then return end;if not av(aH)then return end
local aG={{" Viewing: "..aF.name,c.title}}
local aI,aJ,aK=D.readLinesCapped(d,aH,function(aL)aG[#aG+1]={aL,c.fg}end)if not aI then
a.lastOut={"Cannot read: "..aF.name,c.error}return end;if aK then
aG[#aG+1]={string.format(D.VIEW_STOPPED,aJ),c.warning}end;ag(aG,aF.name)end;local function y()return I.navigateUp(a)end;local function aj(aF)
return I.navigateInto(a,aF)end;local function aw()return I.doCopy(a)end;local function ax()return
I.doMove(a)end;local function ay()return I.doMkdir(a)end;local function az()return
I.doDelete(a)end
local function ak(aF,aG,aH)return R.promptInput(a,aF,aG,aH)end;local function al(aF)return R.promptSearch(a,aF)end;local function aA(aF)
return D.expandBuf(a,aF)end;local function r()
return M.modDown(a.mods,"shift",C.uptime())end
local function m(aF,aG,aH)return M.is(aF,aG,aH,a.who,a.mods)end
local function n(aF,aG,aH)return M.isQuit(aF,aG,aH,a.who,a.mods)end;local function e()return a.displayIdx end;local function s(aF)
a.lastOut={aF..": "..G.describe(e()),c.dim}end
local function k(aF)
local aG=a.cmdCursor or(#a.cmdline+1)
aF=math.max(1,math.min(#a.cmdline+1,aF))if r()then if not a.cmdSel then a.cmdSel=aG end
if a.cmdSel==aF then a.cmdSel=nil end else a.cmdSel=nil end
a.cmdCursor=aF end
local function q()local aF,aH,aG=F.remove(a.cmdline,a.cmdSel,a.cmdCursor)
a.cmdline=aF;a.cmdCursor=aG or a.cmdCursor;a.cmdSel=nil;return a.cmdCursor end
local function aB(aF,aG)
if m("copy",aF,aG)then local aH=F.text(a.cmdline,a.cmdSel,a.cmdCursor)if not
aH and a.cmdline~=""then aH=a.cmdline end
if not aH then local aI=(not
E.isTiles(a))and ae()or nil
if aI then
G.set(aI,e())a.lastOut={"Copied path: "..aI,c.dim}return 1 end;a.lastOut={"Nothing to copy",c.dim}return 1 end;G.set(aH,e())s(V)return 1 elseif m("cut",aF,aG)then
local aH=F.text(a.cmdline,a.cmdSel,a.cmdCursor)
if aH then q()elseif a.cmdline~=""then aH=a.cmdline;a.cmdline,a.cmdCursor,a.cmdSel="",1,nil else
a.lastOut={"Nothing to cut",c.dim}return 1 end;G.set(aH,e())s("Cut")return 1 elseif m("paste",aF,aG)then local aH=G.line(e())
if not aH or aH==
""then a.lastOut={"Clipboard empty",c.dim}return 1 end;local aI=q()a.cmdline,a.cmdCursor=F.insert(a.cmdline,aI,aH)if
G.count(e())>1 then
a.lastOut={"Pasted "..G.count(e()).." lines joined with spaces",c.warning}end;return 1 end;return nil end
local aC={menuDefs=a.menuDefs or B.menuDefs,menuExecute=function(aF)return
N.execute(a,aF.action,{exec=h,drawAll=i,widgetDefs=t})end,ctxExecute=function(aF)return
L.execute(a,aF,A,h)end,openContextMenu=ah,viewFile=ai,navigateUp=y,navigateInto=aj,closeTab=j,drawFileListRow=function(aF)B.fileListRow(a,aF)end,cmdColAt=function(aF)return
B.cmdIndexAt(a,aF)end,exec=h}D.loadFiles(a,a.browser)
pcall(function()local aF=D.scanMountedMedia(d)
if aF then
local aG=string.format('%s: "%s" -> %s',aF.desc,
aF.label or"disk",aF.mountPoint)if aF.hint then aG=aG.."   "..aF.hint end
a.lastOut={aG,c.highlight}end end)i()
local function am(aF)if aF<=0 then return end;if a.suspendIdleDraw then return end
local aG=a.tabs[a.activeTab]
if not aG or aG.type=="shell"then
if aF==1 then p()ab()ac()x()elseif aF==2 then if E.isTiles(a,aG)then
i()else p()an()ap()ao()ab()ac()x()end elseif aF>=3 then i()end;if a.menuOpen then at()end;if a.ctxOpen then au()end elseif aG.type=="view"or
aG.type=="output"then p()ar(aG)elseif aG.type=="edit"then p()as(aG)else
H.ensureBuiltins()local aH=H.get(aG.type)
if aH and aH.draw then p()aH.draw(a,aG)end end end
while true do if a._exitTo then local aS=a._exitTo;a._exitTo=nil;return aS end
local aJ,aO,aI,aH,aP=P()local aG=0
do
local aS=

aJ==K or aJ=="key_up"or aJ=="touch"or aJ=="drag"or aJ=="drop"or aJ==X or aJ==W
if aS then a._lastInputAt=C.uptime()if a._blanked then a._blanked=nil;i()
aJ,aO,aI,aH,aP=nil,nil,nil,nil,nil end end end;local aQ=false;if aJ==K or aJ=="key_up"then
aQ=M.trackMods(a.mods,aJ,aI,aH,C.uptime())end;local aR=a.outLines~=nil;local aM=a.browser and
a.browser.sel
local aN=a.browser and a.browser.scroll;local aF=a.tabs[a.activeTab]
if a.suspendIdleDraw and
(

aJ==K or aJ=="touch"or aJ=="drag"or aJ=="drop"or aJ==X or aJ==W or aJ=="tos_focus"or aJ=="tos_monitor")then
a.suspendIdleDraw=nil end
if aJ==K and not aQ then
if a.ctxOpen then
if aH==200 then L.nextItem(a,-1)elseif aH==208 then
L.nextItem(a,1)elseif aH==28 then local aS=a.ctxItems[a.ctxSel]if aS and not aS.sep then
L.execute(a,aS.action,A,h)end elseif n(aI,aH,true)then a.ctxOpen=false end;aG=3 elseif a.menuOpen then local aS=a.menuDefs or B.menuDefs
if aH==200 then
N.menuNextItem(a,-1)elseif aH==208 then N.menuNextItem(a,1)elseif aH==28 then
local aT=aS[a.menuOpen].items[a.menuSel]
if aT and not aT.sep then
local aU=N.execute(a,aT.action,{exec=h,drawAll=i,widgetDefs=t})if aU then return aU end end elseif n(aI,aH,true)then a.menuOpen=nil;a.menuFocused=false elseif aH==203 then a.menuOpen=a.menuOpen>1 and
a.menuOpen-1 or#aS;a.menuSel=1 elseif aH==205 then
a.menuOpen=
a.menuOpen<#aS and a.menuOpen+1 or 1;a.menuSel=1 end;aG=3 elseif a.menuFocused then local aS=a.menuDefs or B.menuDefs
if aH==203 then a.menuIdx=a.menuIdx>1 and
a.menuIdx-1 or#aS elseif aH==205 then
a.menuIdx=
a.menuIdx<#aS and a.menuIdx+1 or 1 elseif aH==28 then a.menuOpen=a.menuIdx;a.menuSel=1 elseif n(aI,aH,true)then a.menuFocused=false end;aG=3 else local aS=false
if E.isViewKey(a,aI,aH)then
if E.enabled(a)then
if aF and
(aF.type==nil or aF.type=="shell")then E.toggle(a,aF)else for aT,aU in ipairs(a.tabs)do if aU.type=="shell"then
a.activeTab=aT;break end end end else ad(1)end;aG=3;aS=true elseif aH==g.tabClose and
not(aF and aF.type=="shell")then
if aF and aF.type~="shell"then
if
aF.type=="edit"and aF.modified then f.fill(1,o,l,1," ",c.fg,c.bg)
f.set(1,o," Unsaved! [y]Close [n]Cancel",c.warning,c.bg)while true do local aU,aV,aT=P()
if aU==K then if aT==121 or aT==89 then j()break else break end end end else j()end;aG=3 end;aS=true elseif aH==g.menu then
if aF and aF.type~="shell"then a.activeTab=1 end;a.menuFocused=not a.menuFocused
if not a.menuFocused then a.menuOpen=nil end;aG=3;aS=true elseif aH==g.quit then a.activeTab=1;i()
f.fill(1,a.OUT_ROW,l,1," ",c.fg,c.bg)
f.set(1,a.OUT_ROW,(" [1]Reboot [2]Shut down [3]Log out [4]CLI Mode ["..M.quitHint(a.who).."]Cancel"):sub(1,l),c.title,c.bg)
while true do local aU,aW,aT,aV=P()
if aU==K then
if aT==49 or aT==50 then local aX,aY=D.canPowerOff(a)
if not aX then
f.fill(1,a.OUT_ROW,l,1," ",c.fg,c.bg)f.set(1,a.OUT_ROW,aY:sub(1,l),c.error,c.bg)else if
_G._TOS.audio then _G._TOS.audio.shutdown()end;if
aT==49 then z.reboot()else z.shutdown()end;return"exit"end elseif aT==51 then
if _G._TOS.audio then _G._TOS.audio.shutdown()end;D.logout(a)return"exit"elseif aT==52 then return"cli"elseif n(aT,aV,true)then a.lastOut=nil;break end end end;aG=3;aS=true end
if not aS and aF then
if aF.type=="shell"then local aT=E.isTiles(a,aF)local aV=aB(aI,aH)
local aU=nil
if not aV and r()and a.cmdline~=""then
local aY=a.cmdCursor or(#a.cmdline+1)if aH==203 then k(aY-1)aU=1 elseif aH==205 then k(aY+1)aU=1 elseif aH==199 then k(1)aU=1 elseif aH==207 then
k(#a.cmdline+1)aU=1 end end;local aW,aX;if not aV and not aU and aT then
aW,aX=E.handleKey(a,aF,aI,aH,{exec=h})end
if aV then aG=aV elseif aU then aG=aU elseif aW~=nil then
if aX=="exit"then return aX end;aG=aW elseif aH==g.help then local aZ={}local function a_(ba,bb)aZ[#aZ+1]={ba,bb}end
v.help({},a_)local aY=nil;for bb,ba in ipairs(a.tabs)do if ba.label=="Help"and ba.type=="view"then aY=bb
break end end;if
aY then a.tabs[aY].content=aA(aZ)a.tabs[aY].offset=0
a.activeTab=aY else ag(aZ,"Help")end;aG=3 elseif not aT and aH==
g.viewFile then ai()aG=3 elseif not aT and aH==g.copy then aw()aG=3 elseif
not aT and aH==g.move then ax()aG=3 elseif not aT and aH==g.mkdir then ay()aG=3 elseif not aT and aH==g.delete then az()
aG=3 elseif aH==200 and not aT then
if a.browser.sel>1 then local aM=a.browser.sel
local aN=a.browser.scroll;a.browser.sel=aM-1;if a.browser.sel<=a.browser.scroll then a.browser.scroll=
a.browser.sel-1 end;if
a.browser.scroll==aN then B.fileListRow(a,aM)
B.fileListRow(a,a.browser.sel)aG=0 else aG=2 end else aG=0 end elseif aH==208 and not aT then
if a.browser.sel<#a.browser.files then
local aM=a.browser.sel;local aN=a.browser.scroll;a.browser.sel=aM+1;if a.browser.sel>a.browser.scroll+
a.LIST_H then
a.browser.scroll=a.browser.sel-a.LIST_H end
if a.browser.scroll==aN then
B.fileListRow(a,aM)B.fileListRow(a,a.browser.sel)aG=0 else aG=2 end else aG=0 end elseif aH==201 then
a.browser.sel=math.max(1,a.browser.sel-a.LIST_H)
a.browser.scroll=math.max(0,a.browser.scroll-a.LIST_H)aG=2 elseif aH==209 then
a.browser.sel=math.min(#a.browser.files,a.browser.sel+a.LIST_H)
a.browser.scroll=math.min(math.max(0,#a.browser.files-a.LIST_H),
a.browser.scroll+a.LIST_H)aG=2 elseif aH==203 then
if a.cmdline~=""then k(
(a.cmdCursor or(#a.cmdline+1))-1)aG=1 end elseif aH==205 then
if a.cmdline~=""then k(
(a.cmdCursor or(#a.cmdline+1))+1)aG=1 end elseif aH==199 then
if a.cmdline~=""then k(1)aG=1 else a.browser.sel=1;a.browser.scroll=0;aG=2 end elseif aH==207 then if a.cmdline~=""then k(#a.cmdline+1)aG=1 else a.browser.sel=#
a.browser.files
a.browser.scroll=math.max(0,#a.browser.files-a.LIST_H)aG=2 end elseif aH==
14 then local aY=a.cmdCursor or(#a.cmdline+1)
if a.cmdSel then q()
aG=1 elseif aY>1 then
a.cmdline=a.cmdline:sub(1,aY-2)..a.cmdline:sub(aY)a.cmdCursor=aY-1;aG=1 elseif a.cmdline==""and not aT then y()aG=3 end elseif aH==211 and a.cmdSel then q()aG=1 elseif aH==211 then
local aY=a.cmdCursor or(#a.cmdline+1)if aY<=#a.cmdline then
a.cmdline=a.cmdline:sub(1,aY-1)..a.cmdline:sub(aY+1)aG=1 end elseif aH==28 then
if a.cmdline~=""then
local aZ=a.cmdline;a.cmdline=""a.cmdCursor=1;a.cmdHistIdx=0;a.cmdSel=nil;local aY=aZ:lower()
local ba=
aY:find("trust setsecret",1,true)or aY:find("trust generatesecret",1,true)or
aY:find("trust key ",1,true)or
aY:find("changepass ",1,true)or
aY:find("usermod ",1,true)and aY:find(" pass",1,true)
if not ba then local bd=200
if#a.cmdHistory==0 or
a.cmdHistory[#a.cmdHistory]~=aZ then
a.cmdHistory[#a.cmdHistory+1]=aZ
if#a.cmdHistory>bd then table.remove(a.cmdHistory,1)end end end;a.outLines=nil
local a_=(aZ:match("^(%S+)")or""):lower()local d=a.F
local function bb(bd)if bd==""or(v and v[bd])then return false end
if
D.mayHavePackages()then local bf,be=pcall(require,"kernel.pkg")if bf and be and be.getCommand and
be.getCommand(bd)then return true end end
if d and d.exists and d.join then
for bf,be in
ipairs({"/bin","/usr/bin","/tos/shell"})do if
d.exists(d.join(be,bd..".lua"))or d.exists(d.join(be,bd))then return true end end end;return false end
local function bc(bd)local bg,be=pcall(require,"shell.panels.commands")local bf=
bg and be and be.entry and be.entry(bd)return
type(bf)=="table"and bf.slow==true end;if bb(a_)or bc(a_)then
w("Running "..a_.."\226\128\166",c.dim)end;h(aZ)else
local aY=a.browser.files[a.browser.sel]if aY then
if aY.name==".."then y()elseif aY.dir then aj(aY.name)else ah()end end end;aG=3 elseif n(aI,aH,true)then a.cmdline=""a.cmdCursor=1;a.cmdSel=nil;if a.clipboard then a.clipboard=nil
a.lastOut={"Copy cancelled",c.dim}aG=3 else a.lastOut=nil;aG=1 end elseif
aI==16 and aH~=200 then
if a.cmdHistIdx==0 then a.cmdHistIdx=#a.cmdHistory elseif
a.cmdHistIdx>1 then a.cmdHistIdx=a.cmdHistIdx-1 end
if a.cmdHistIdx>0 then a.cmdline=a.cmdHistory[a.cmdHistIdx]end;a.cmdCursor=#a.cmdline+1;a.cmdSel=nil;aG=1 elseif aI==14 and aH~=14 then
if a.cmdHistIdx<#
a.cmdHistory then a.cmdHistIdx=a.cmdHistIdx+1
a.cmdline=a.cmdHistory[a.cmdHistIdx]else a.cmdHistIdx=0;a.cmdline=""end;a.cmdCursor=#a.cmdline+1;a.cmdSel=nil;aG=1 elseif
aH==15 and a.cmdline==""and E.enabled(a)then ad(1)aG=3 elseif aH==15 then
local bd,ba=pcall(require,"shell.panels.commands")
local aY=(bd and ba.commandNames)and ba.commandNames()or{}local be,aZ=pcall(require,"kernel.pkg")
if be and aZ and aZ.commands then
local bh,bg=pcall(aZ.commands)if bh and type(bg)=="table"then
for bi in pairs(bg)do aY[#aY+1]=bi end end end
local bb=a.cwd or(a.browser and a.browser.path)or"/"
local function bf(bg)local bj=(bg:sub(1,1)=="/")and bg or
(bg==""and bb or d.join(bb,bg))local bi={}
local bk,bh=pcall(d.list,bj)
if bk and bh then local bl={}if type(bh)=="table"then bl=bh elseif type(bh)=="function"then for bm in bh do
bl[#bl+1]=bm end end
for bn,bm in ipairs(bl)do
local bp=bm:gsub("/$","")local bo=bm:sub(-1)=="/"if not bo then
local bq,br=pcall(d.isDirectory,d.join(bj,bp))bo=bq and br end
bi[#bi+1]={name=bp,dir=bo}end end;return bi end;local bc,a_=D.completeCmdline(a.cmdline,aY,bf)if bc~=a.cmdline then
a.cmdline=bc;a.cmdHistIdx=0 end;a.cmdCursor=#a.cmdline+1;if#
a_>1 then a.outLines=nil
a.lastOut={(#a_.." matches: "..table.concat(a_,"  ")):sub(1,l),c.dim}end;aG=1 elseif
aI and aI>=32 and aI<127 then
local aY=a.cmdSel and q()or(a.cmdCursor or(#a.cmdline+1))a.cmdline=a.cmdline:sub(1,aY-1)..
string.char(aI)..a.cmdline:sub(aY)
a.cmdCursor=aY+1;a.cmdHistIdx=0;aG=1 end elseif aF.type=="view"or aF.type=="output"then
local aT=aF.content or{}local aU=o-2
local function aV(aW)local aY=aF.selCur or(aF.offset+1)local aX=math.max(1,math.min(#aT,
aY+aW))if not aF.selAnchor then
aF.selAnchor=aY end;aF.selCur=aX
if aX<=aF.offset then
aF.offset=math.max(0,aX-1)elseif aX>aF.offset+aU then aF.offset=aX-aU end end
if n(aI,aH)or aI==113 then j()aG=3 elseif m("copy",aI,aH)then
local aW=F.lines(aT,aF.selAnchor,aF.selCur)
if not aW then aW=F.lines(aT,aF.offset+1,aF.offset+1)end
if aW then G.set(aW,e())s(V)else a.lastOut={"Nothing to copy",c.dim}end;aG=3 elseif r()and aH==200 then aV(-1)aG=3 elseif r()and aH==208 then aV(1)aG=3 elseif

aH==200 or aH==208 or aH==201 or aH==209 or aH==199 or aH==207 then aF.selAnchor,aF.selCur=nil,nil
if aH==200 and
aF.offset>0 then aF.offset=aF.offset-1;aG=1 elseif aH==208 and
aF.offset+aU<#aT then aF.offset=aF.offset+1;aG=1 elseif aH==201 then
aF.offset=math.max(0,aF.offset-aU)aG=1 elseif aH==209 then
aF.offset=math.min(math.max(0,#aT-aU),aF.offset+aU)aG=1 elseif aH==199 then aF.offset=0;aG=1 elseif aH==207 then aF.offset=math.max(0,#aT-aU)
aG=1 else aG=1 end elseif aF.live and(aI==114 or aI==82)then
S.refreshLiveTab(a,aF)aF.lastRefresh=C.uptime()aG=3 elseif aI==6 then local aW=al(aF.searchTerm)
aF.searchTerm=aW
if aW then
for aX=aF.offset+1,#aT do local aY=aT[aX]
local aZ=type(aY)=="table"and aY[1]or tostring(aY)
if aZ:find(aW,1,true)then aF.offset=math.max(0,aX-1)break end end end;aG=3 end elseif aF.type=="edit"then local aT=aF.lines;local aX=o-2
local function aU()
aF.curRow=math.max(1,math.min(#aT,aF.curRow))
aF.curCol=math.max(1,math.min(# (aT[aF.curRow]or"")+1,aF.curCol))if aF.curRow<aF.viewTop then aF.viewTop=aF.curRow end
if aF.curRow>
aF.viewTop+aX-1 then aF.viewTop=aF.curRow-aX+1 end end
local function aV()if not aF.undoStack then aF.undoStack={}end;local a_={}for ba,bb in ipairs(aT)do
a_[ba]=bb end
aF.undoStack[#aF.undoStack+1]={lines=a_,row=aF.curRow,col=aF.curCol}if#aF.undoStack> (aF.undoMax or 32)then
table.remove(aF.undoStack,1)end end;if aF.suggest and aI~=15 then aF.hintSeen=true end
aF.flash=nil;local aW=nil;local aY={row=aF.curRow,col=aF.curCol}
if m("copy",aI,aH)then local a_=
F.extract(aT,aF.selAnchor,aY)or{aT[aF.curRow]}
G.set(a_,e())s(V)aW=1 elseif m("cut",aI,aH)then aV()local a_=F.extract(aT,aF.selAnchor,aY)
if a_ then
local bc,ba,bb=F.removeBlock(aT,aF.selAnchor,aY)aF.curRow,aF.curCol=ba,bb;aF.selAnchor=nil else a_={aT[aF.curRow]}
if#aT>
1 then table.remove(aT,aF.curRow)else aT[1]=""end end;G.set(a_,e())aF.modified=true;aU()s("Cut")aW=1 elseif m("paste",aI,aH)then
local a_=G.get(e())
if a_ and#a_>0 then aV()
if aF.selAnchor then
local bc,ba,bb=F.removeBlock(aT,aF.selAnchor,aY)aF.curRow,aF.curCol=ba,bb;aF.selAnchor=nil end
aF.curRow,aF.curCol=F.insertBlock(aT,aF.curRow,aF.curCol,a_)aF.modified=true;aU()
a.lastOut={"Pasted "..#a_.." line(s)",c.dim}else a.lastOut={"Clipboard empty",c.dim}end;aW=1 end;if aa[aH]then
if r()then if not aF.selAnchor then
aF.selAnchor={row=aF.curRow,col=aF.curCol}end else aF.selAnchor=nil end end
local function aZ(a_)local ba=J.cellOf(
aT[aF.curRow]or"",aF.curCol)aF.curRow=math.max(1,math.min(
#aT,a_))
aF.curCol=J.colOf(aT[aF.curRow]or"",ba)aU()end
if aW then aG=aW elseif aH==200 then aZ(aF.curRow-1)aG=1 elseif aH==208 then
aZ(aF.curRow+1)aG=1 elseif aH==203 then if aF.curCol>1 then
aF.curCol=J.prevCol(aT[aF.curRow],aF.curCol)elseif aF.curRow>1 then aF.curRow=aF.curRow-1
aF.curCol=#aT[aF.curRow]+1 end;aU()
aG=1 elseif aH==205 then
if aF.curCol<=#aT[aF.curRow]then
aF.curCol=J.nextCol(aT[aF.curRow],aF.curCol)elseif aF.curRow<#aT then aF.curRow=aF.curRow+1;aF.curCol=1 end;aU()aG=1 elseif aH==199 then aF.curCol=1;aG=1 elseif aH==207 then
aF.curCol=#aT[aF.curRow]+1;aG=1 elseif aH==201 then aZ(aF.curRow-aX)aG=1 elseif aH==209 then
aZ(aF.curRow+aX)aG=1 elseif(aH==14 or aH==211)and aF.selAnchor then aV()
local bb,a_,ba=F.removeBlock(aT,aF.selAnchor,{row=aF.curRow,col=aF.curCol})aF.curRow,aF.curCol=a_,ba;aF.selAnchor=nil;aF.modified=true;aU()aG=1 elseif aH==14 then
if
aF.curCol>1 then local a_=aT[aF.curRow]local ba=J.prevCol(a_,aF.curCol)aT[aF.curRow]=a_:sub(1,
ba-1)..a_:sub(aF.curCol)
aF.curCol=ba;aF.modified=true;aG=1 elseif aF.curRow>1 then aV()
aF.curCol=#aT[aF.curRow-1]+1
aT[aF.curRow-1]=aT[aF.curRow-1]..aT[aF.curRow]table.remove(aT,aF.curRow)aF.curRow=aF.curRow-1
aF.modified=true;aU()aG=1 end elseif aH==211 then local a_=aT[aF.curRow]
if aF.curCol<=#a_ then
aT[aF.curRow]=
a_:sub(1,aF.curCol-1)..a_:sub(J.nextCol(a_,aF.curCol))aF.modified=true;aG=1 elseif aF.curRow<#aT then aV()
aT[aF.curRow]=a_..aT[aF.curRow+1]table.remove(aT,aF.curRow+1)aF.modified=true;aG=1 end elseif aH==28 then aV()local bc=aT[aF.curRow]
local bb=bc:sub(1,aF.curCol-1)local bd=bc:sub(aF.curCol)aT[aF.curRow]=bb
local ba=bb:match("^(%s*)")or""local a_=bb:match("^%s*(.-)%s*$")or""
if

a_:match("then$")or
a_:match("do$")or a_:match("repeat$")or
a_:match("else$")or a_:match("function%s*%(.*%)%s*$")or a_:match("{%s*$")then ba=ba.."  "end;table.insert(aT,aF.curRow+1,ba..bd)
aF.curRow=aF.curRow+1;aF.curCol=#ba+1;aF.modified=true;aU()aG=1 elseif aH==15 then local a_=aT[aF.curRow]
aT[aF.curRow]=a_:sub(1,
aF.curCol-1).."  "..a_:sub(aF.curCol)aF.curCol=aF.curCol+2;aF.modified=true;aG=1 elseif n(aI,aH,true)then
if aF.modified then
f.fill(1,o,l,1," ",c.fg,c.bg)
f.set(1,o," Save? [y]es [n]o [c]ancel",c.warning,c.bg)local ba,bb,a_=P()
if ba==K then
if a_==121 or a_==89 then
if aF.path then local bc=
(d.normalize and d.normalize(aF.path))or aF.path;if af(bc)then
d.writeFile(bc,table.concat(aT,"\n"))u()end end;j()aG=3 elseif a_==110 or a_==78 then j()aG=3 else aG=1 end end else j()aG=3 end elseif aI==15 and aF.suggest then
if aF.modified then aF.flash="Save first (^S): "..
aF.suggest.cmd.." reads the file from disk."aG=1 elseif
aF.path then local a_,ba=aF.path,aF.suggest.cmd;j()
local bb,bc=pcall(require,"shell.open")
if bb then h(ba.." "..bc.quote(a_))end;aG=3 end elseif aI==19 then
if aF.path then local a_=(d.normalize and d.normalize(aF.path))or
aF.path
if af(a_)then
if
d.writeFile(a_,table.concat(aT,"\n"))then aF.path=a_;aF.modified=false
a.lastOut={"Saved: "..aF.label,c.highlight}u()else a.lastOut={"Save failed!",c.error}end end elseif not aF.path then a.lastOut={"No path set",c.error}end;aG=1 elseif aI==6 then local a_=al(aF.searchTerm)
if a_ and#a_>0 then aF.searchTerm=a_
local ba=false
for bb=aF.curRow,#aT do
local bd=bb==aF.curRow and aF.curCol+1 or 1;local bc=aT[bb]:find(a_,bd,true)if bc then aF.curRow=bb;aF.curCol=bc;ba=true
break end end;if not ba then
for bb=1,aF.curRow-1 do local bc=aT[bb]:find(a_,1,true)if bc then aF.curRow=bb
aF.curCol=bc;ba=true;break end end end
if not ba then a.lastOut={
"Not found: "..a_,c.warning}end;aU()elseif a_==nil then aF.searchTerm=nil end;aG=1 elseif aI==8 then local a_=ak("Find: ",40)
if a_ and#a_>0 then
local ba=ak("Replace with: ",40)
if ba then local function bd(bh)
return(bh:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])","%%%1"))end;local function be(bh)
return(bh:gsub("%%","%%%%"))end;local bf=bd(a_)local bg=be(ba)local bb=0
if aF.undoStack then local bh={}for bi,bj in
ipairs(aT)do bh[bi]=bj end
aF.undoStack[#aF.undoStack+1]={lines=bh,row=aF.curRow,col=aF.curCol}if#aF.undoStack> (aF.undoMax or 32)then
table.remove(aF.undoStack,1)end end;local bc=true
for bh=1,#aT do local bj,bk,bi=pcall(string.gsub,aT[bh],bf,bg,nil)if
not bj then bc=false;break end;if bi>0 then aT[bh]=bk;bb=bb+bi end end
if not bc then
a.lastOut={"Replace failed (pattern error)",c.error}if aF.undoStack and#aF.undoStack>0 then aF.undoStack[#aF.undoStack]=
nil end elseif bb>0 then
aF.modified=true
a.lastOut={"Replaced "..bb.." occurrence(s)",c.highlight}else a.lastOut={"Not found: "..a_,c.warning}if aF.undoStack and
#aF.undoStack>0 then
aF.undoStack[#aF.undoStack]=nil end end end end;aG=1 elseif aI==26 then
if aF.undoStack and#aF.undoStack>0 then
local a_=table.remove(aF.undoStack)aF.lines=a_.lines;aT=aF.lines;aF.curRow=a_.row;aF.curCol=a_.col
aF.modified=true;aU()a.lastOut={"Undo",c.dim}else
a.lastOut={"Nothing to undo",c.dim}end;aG=1 elseif aI and aI>=32 and aI<127 then
if aF.selAnchor then aV()
local bc,ba,bb=F.removeBlock(aT,aF.selAnchor,{row=aF.curRow,col=aF.curCol})aF.curRow,aF.curCol=ba,bb;aF.selAnchor=nil end;local a_=aT[aF.curRow]
aT[aF.curRow]=a_:sub(1,aF.curCol-1)..
string.char(aI)..a_:sub(aF.curCol)aF.curCol=aF.curCol+1;aF.modified=true;aG=1 end else H.ensureBuiltins()local aT=H.get(aF.type)
if aT and aT.onKey then
local aV,aU=aT.onKey(a,aF,{ch=aI,co=aH,exec=h})if aU then return aU end;aG=aV or 0 end end end end elseif
aJ=="touch"or aJ=="drag"or aJ=="drop"or aJ==X then local aT,aS=Y.handle(a,aC,aJ,aO,aI,aH,aP)if aS then return aS end
aG=aT or 0 elseif aJ==W and type(aI)=="string"then
if aF and aF.type=="shell"then
local aT=aI:gsub("[\r\n]+"," ")
local aS=a.cmdSel and q()or(a.cmdCursor or(#a.cmdline+1))
a.cmdline=a.cmdline:sub(1,aS-1)..aT..a.cmdline:sub(aS)a.cmdCursor=aS+#aT;aG=1 elseif aF and aF.type=="edit"then
local aS=aI:gsub("\n"," "):gsub("\r","")local aT=aF.lines[aF.curRow]
aF.lines[aF.curRow]=
aT:sub(1,aF.curCol-1)..aS..aT:sub(aF.curCol)aF.curCol=aF.curCol+#aS;aF.modified=true;aG=1 end elseif aJ=="tos_focus"then c=f.getTheme()a.T=c;aG=3
local aS=a.tabs and a.tabs[a.activeTab]
if aS and aS.type=="program"then local aT=1
for aV,aU in ipairs(a.tabs)do if aU.type=="shell"or
aU.type==nil then aT=aV;break end end;a.activeTab=aT end elseif aJ=="tos_monitor"then
local aT,aS=pcall(require,"shell.panels.monitorapp")
if aT and aS then a.menuOpen=nil;a.menuFocused=false;a.ctxOpen=false;aS.open(a)aG=3 end elseif aJ=="tos_interrupt"then if aF and aF.type=="shell"then
if a.cmdline~=""then a.cmdline=""
a.cmdCursor=1;a.cmdSel=nil;a.lastOut={"^C",c.dim}end;aG=1 end elseif aJ==
"tos_disk_added"or aJ=="tos_disk_removed"then if
D.announceDisk(a,d,
aJ=="tos_disk_added"and"added"or"removed",aI,aH)then pcall(u)end;aG=3 elseif
aJ=="component_added"or aJ=="component_removed"then aG=3 elseif aJ=="screen_resized"then
local aT,aS=pcall(require,"shell.panels.state")
if aT and aS and aS.recomputeLayout then pcall(aS.recomputeLayout,a)end;pcall(u)aG=3 end
if
aR and a.outLines and a.browser and(a.browser.sel~=aM or
a.browser.scroll~=aN)then a.outLines=nil;if aG<2 then aG=2 end end;if aR and not a.outLines and aG<2 then aG=2 end
am(aG)do local aS=C.uptime()
if
aS- (a._lastSwapSweep or 0)>=1 then a._lastSwapSweep=aS;pcall(Q.sweepCold,a)end end
do local aS=C.uptime()
if

aS- (
a._lastNotice or 0)>=1 and not a.suspendIdleDraw and not a.menuOpen and not a.ctxOpen then a._lastNotice=aS;local aU,aT=pcall(require,"kernel.notify")
if aU and type(aT)==
"table"then
if a._noticeSeen==nil then a._noticeSeen=aT.highWater()end;aT.sweep()local aW=aT.pending(a._noticeSeen)
local aV=aT.nextToShow(aW,a._noticeShownAt)
if aV then a._noticeSeen=aV.seq
local aX,aY=pcall(R.dialog,a,{style=aV.style,title=aV.title,message=aV.message.."\n\nFrom: "..aV.from,buttons=aV.buttons,closeIf=function()return
aT.result(aV.id)~=nil end})if not(aX and aY==nil)then
aT.settle(aV.id,aX and aY or 1)end;a._noticeShownAt=C.uptime()
a._lastInputAt=a._noticeShownAt;a._blanked=nil;i()end end end end;local aL=_()
if
aL and not a.suspendIdleDraw and not a.menuOpen and not a.ctxOpen and
aL.shouldBlank(C.uptime(),a._lastInputAt,a._blanked)then
a._blanked=true;pcall(f.fill,1,1,a.W,a.H," ",c.fg,0x000000)end;local aK=a.tabs[a.activeTab]
if a._blanked then elseif a.suspendIdleDraw then
local aS=_G._TOS and _G._TOS.kernel
if aS and aS.isForeground then local aT,aU=pcall(aS.isForeground)if aT and aU then
a.suspendIdleDraw=nil;i()end end elseif

aK and(aK.type==nil or aK.type=="shell")and not a.menuOpen and not a.ctxOpen then local aS=C.uptime()
if
aS- (a._lastStatusT or 0)>= ((aL and
aL.idleSeconds())or 1)then a._lastStatusT=aS;x()
if H.chipsChanged and H.chipsChanged(a)then p()end;if E.isTiles(a,aK)then E.drawHeader(a,aK)end end elseif aK and aK.type=="desktop"and not a.menuOpen and
not a.ctxOpen then local aS=C.uptime()
if aS-
(a._lastStatusT or 0)>=
((aL and aL.idleSeconds())or 1)then a._lastStatusT=aS;local aT=Z()if aT then
aT.drawHeader(a,aK)end end elseif
aK and aK.type=="view"and aK.live and not a.menuOpen and not a.ctxOpen then local aS=C.uptime()
if
aS- (aK.lastRefresh or
0)>= (aK.interval or 1)then aK.lastRefresh=aS;S.refreshLiveTab(a,aK)B.viewTab(a,aK)end elseif aK and not a.menuOpen and not a.ctxOpen then
local aS=H.get(aK.type)
if aS and aS.tick then local aT=C.uptime()
if aT- (aK.lastRefresh or 0)>= (
aK.interval or 2)then aK.lastRefresh=aT
local aU=aS.tick(a,aK)if aU and aU>0 then am(aU)end end end end end end;return U