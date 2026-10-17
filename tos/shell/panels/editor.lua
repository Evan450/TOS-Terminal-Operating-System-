local f=require("shell.panels.helpers")
local e=require("shell.panels.tabs")local d={}
function d.openViewTab(b,c,a,g)local h=g and c or f.expandBuf(b,c)
if#h==0 then return end;a=a or"Output"if#a>16 then a=a:sub(1,15).."~"end
e.create(b,"view",a,{content=h,offset=0,searchTerm=
nil})end
function d.refreshLiveTab(b,a)
if not a or type(a.refresh)~="function"then return end;local g=b.T or{}local j,c=pcall(a.refresh)if
not j or type(c)~="table"then
c={{"(refresh error: "..tostring(c)..")",g.error}}end;a.refreshCount=
(a.refreshCount or 0)+1
local h={{"\226\151\143 LIVE  "..

(a.liveLabel or a.label or"").."   ~"..
(a.interval or 1).."s  \194\183  \226\159\179 "..
a.refreshCount.."  \194\183  r refresh  \194\183  q/F4 close",g.dim},{"",g.fg}}for n,m in ipairs(c)do h[#h+1]=m end;a.content=f.expandBuf(b,h)local k=
(b.H or 25)-2;local i=math.max(0,#a.content-k)if
(a.offset or 0)>i then a.offset=i end end
function d.openLiveTab(c,a,g,b)if type(g)~="function"then return end;a=a or"Live"
b=tonumber(b)or 1;if b<1 then b=1 end
local i=(#a>13)and(a:sub(1,12).."~")or a
local h=e.create(c,"view","\226\151\143"..i,{content={},offset=0,searchTerm=nil,live=true,refresh=g,interval=b,liveLabel=a,lastRefresh=0})d.refreshLiveTab(c,h)return h end
function d.openEditTab(b,a)local g=e.find(b,"edit",a)if g then b.activeTab=g;return end
if a and
b.F.exists(a)and not f.canRead(b,a)then return end;local c={""}
if a and b.F.exists(a)then local i=b.F.readFile(a)or""
c={}for j in i:gmatch("([^\n]*)\n?")do c[#c+1]=j end
if#c==0 then c[1]=""end;if c[#c]==""and#c>1 then c[#c]=nil end end
local h=(a and a:match("[^/]+$"))or"new file"
e.create(b,"edit",h,{path=a,lines=c,curRow=1,curCol=1,viewTop=1,viewLeft=1,modified=false,searchTerm=nil,undoStack={},undoMax=32})end;return d