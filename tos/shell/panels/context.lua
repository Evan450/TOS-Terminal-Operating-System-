local e=require("shell.panels.helpers")
local h=require("shell.panels.filebrowser")local g=require("shell.panels.editor")local f={}
function f.buildItems(b,a)
local c={{label="View",action="ctx_view",key="F3"},{label="Edit",action="ctx_edit"}}
if a:match("%.lua$")then c[#c+1]={label="Run",action="ctx_run"}end;c[#c+1]={sep=true}
c[#c+1]={label="Copy",action="ctx_copy",key="F5"}c[#c+1]={label="Move",action="ctx_move",key="F6"}
c[#c+1]={label="Delete",action="ctx_delete",key="F8"}c[#c+1]={label="Rename",action="ctx_rename"}
c[#c+1]={sep=true}c[#c+1]={label="Properties",action="ctx_props"}return c end
function f.open(a)local b,c=e.selPath(a)if not b or not c then return end
a.ctxItems=f.buildItems(c,b)a.ctxPath=b;a.ctxFile=c;a.ctxSel=1;local d=a.LIST_TOP+
(a.browser.sel-a.browser.scroll)-1;a.ctxX=math.max(1,math.floor(
a.W/2)-10)a.ctxY=math.min(d,a.H-#
a.ctxItems-3)
if a.ctxY<2 then a.ctxY=2 end;a.ctxOpen=true end;function f.nextItem(a,b)local c=a.ctxSel+b
while c>=1 and c<=#a.ctxItems do if not
a.ctxItems[c].sep then a.ctxSel=c;return end;c=c+b end end
function f.execute(a,b,c)
local d=a.T;local i=a.F;a.ctxOpen=false
if b=="ctx_view"then
if not e.canRead(a,a.ctxPath)then return end
local j={{" Viewing: "..a.ctxFile.name,d.title}}
local k,l,m=e.readLinesCapped(i,a.ctxPath,function(n)j[#j+1]={n,d.fg}end)if not k then
a.lastOut={"Cannot read: "..a.ctxFile.name,d.error}return end;if m then
j[#j+1]={string.format(e.VIEW_STOPPED,l),d.warning}end
g.openViewTab(a,j,a.ctxFile.name)elseif b=="ctx_edit"then g.openEditTab(a,a.ctxPath)elseif b=="ctx_run"then local k={}local function j(n,o)k[#k+1]={tostring(n),
o or d.fg}end
local l=e.safeModeRefusal(a.ctxPath)local m=not l and i.readFile(a.ctxPath)
if l then
j(l,d.error)elseif not m then
j("Cannot read: "..a.ctxFile.name,d.error)else
local n=c{name=a.ctxFile.name,stdout=function(q)j(q,d.fg)end}local o,p=load(m,"="..a.ctxFile.name,"t",n)
if not o then j(
"Compile error: "..tostring(p),d.error)else
local q,r=pcall(o)e.reportProgramEnd(a,j,q,r,"Runtime error: ",n)end end
if#k>0 then local n=e.expandBuf(a,k)if#n==1 then a.lastOut=n[1]else
g.openViewTab(a,n,a.ctxFile.name,true)end end elseif b=="ctx_copy"then if not e.canRead(a,a.ctxPath)then return end
a.clipboard={path=a.ctxPath,name=a.ctxFile.name}
a.lastOut={"Marked: "..a.ctxFile.name.."  -- navigate & F5 to paste",d.highlight}elseif b=="ctx_move"then h.doMove(a,a.ctxPath,a.ctxFile)elseif b=="ctx_delete"then
h.doDelete(a,a.ctxPath,a.ctxFile)elseif b=="ctx_rename"then h.doRename(a,a.ctxPath,a.ctxFile)elseif
b=="ctx_props"then local j
if a.ctxFile.dir then local i=a.F;local function o(q,r)return
q:sub(-1)=="/"and(q..r)or(q.."/"..r)end;local function p(q)
if not i.size then return 0 end;local r,t=pcall(i.size,q)
return(r and tonumber(t))or 0 end;local m,l=0,0
local function n(q)
local s,r=pcall(i.list,q)if not s or type(r)~="table"then return end;for u,t in ipairs(r)do
local v=o(q,(t:gsub("/$","")))local w,x=pcall(i.isDirectory,v)
if w and x then n(v)else l=l+1;m=m+p(v)end end end;n(a.ctxPath)
j=e.fmtSz(m).."  ("..l..
" file".. (l==1 and""or"s")..")"else j=e.fmtSz(a.ctxFile.sz)end
local k={{" Properties: "..a.ctxFile.name,d.title},{"",d.fg},{" Name:  "..
a.ctxFile.name,d.fg},{" Path:  "..a.ctxPath,d.fg},{" Size:  "..
j,d.fg},{" Type:  "..
(a.ctxFile.dir and"Directory"or(
a.ctxFile.name:match("%.(%w+)$")or"File")),d.fg}}
g.openViewTab(a,k,"Props:"..a.ctxFile.name:sub(1,8))end end;return f