local f=require("computer")
local e=require("shell.panels.keymap")local d={}
function d.recomputeLayout(a)local b,c;local g=a.D.getGpu and a.D.getGpu()if g then
local k,i,j=pcall(g.getResolution)if k and i and j then b,c=i,j end end;if
not b then b,c=a.D.getSize()end;if b and c and b>0 and c>0 then
a.W,a.H=b,c end;a.padW=string.rep(" ",a.W)a.MENU_ROW=1
a.RAIL_ROW=2;a.LIST_TOP=3;a.SUM_ROW=a.H-3;a.OUT_ROW=a.H-2;a.CMD_ROW=a.H-1
a.STAT_ROW=a.H;a.LIST_H=a.SUM_ROW-a.LIST_TOP;a.BAND_ROW=a.RAIL_ROW+1;a.TILE_TOP=
a.BAND_ROW+1;a.TILE_H=a.SUM_ROW-a.TILE_TOP end
function d.new(a)local b={}b.K=a.K;b.E=a.E;b.P=a.P;b.F=a.F;b.D=a.D;b.U=a.U;b.SC=a.SC;b.NM=a.NM
b.st=a.st
b.displayIdx=a.displayIdx or
(a.K and a.K.getDisplayIdx and a.K.getDisplayIdx())or nil;b.W=a.W;b.H=a.H;b.T=b.D.getTheme()b.tier=b.D.getGpuTier()
d.recomputeLayout(b)b.cwd=a.cwd or"/"b.who=a.who or"root"b.userTier=3
if b.U and b.st then
local h=b.U.getSession(b.st)if h then b.userTier=h.tier or 3 end end;b.cmdline=""b.cmdCursor=1;b.cmdSel=nil;b.cmdHistory={}b.cmdHistIdx=0
b.lastOut=nil;local g,c=pcall(require,"shell.keys")
b.mods=
(g and c and c.newMods)and c.newMods()or{shift=false,ctrl=false,alt=false,at=0}b.clipboard=nil;b.browser={path=b.cwd,sel=1,scroll=0,files={}}b.uiSplit=
a.uiSplit or false
b.tabs={{type="shell",label=b.uiSplit and"Shell"or"Home",view=b.uiSplit and
"files"or(a.homeView or"files")}}b.activeTab=1;b.menuFocused=false;b.menuIdx=1;b.menuOpen=nil;b.menuSel=1
b.ctxOpen=false;b.ctxItems={}b.ctxSel=1;b.ctxPath=nil;b.ctxFile=nil;b.ctxX=1;b.ctxY=1;b.KEYS=e;b.sandboxMod=
nil;return b end;return d