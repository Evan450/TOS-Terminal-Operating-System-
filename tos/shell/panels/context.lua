local e=require("shell.panels.helpers")
local h=require("shell.panels.filebrowser")local g=require("shell.panels.editor")local f={}
function f.openChoices(a,b)if not
e.mayHavePackages()then return{}end
local j,c=pcall(require,"shell.open")if not j then return{}end;local i=e.sessionOf(a)
local k,l=pcall(c.rank,b,c.gather(a.F,i and i.home,b))if not k then return{}end;local d={}for n,m in ipairs(l)do
if m.cmd~=c.EDITOR then d[#d+1]=m end end;return d end
function f.buildItems(c,a,b)local d={}for j,i in ipairs(b or{})do
d[#d+1]={label="Open in "..i.cmd,action="ctx_open:"..i.cmd}end
d[#d+1]={label="View",action="ctx_view",key="F3"}d[#d+1]={label="Edit",action="ctx_edit"}if a:match("%.lua$")then
d[#d+1]={label="Run",action="ctx_run"}end;d[#d+1]={sep=true}
d[#d+1]={label="Copy",action="ctx_copy",key="F5"}d[#d+1]={label="Move",action="ctx_move",key="F6"}
d[#d+1]={label="Delete",action="ctx_delete",key="F8"}d[#d+1]={label="Rename",action="ctx_rename"}
d[#d+1]={sep=true}d[#d+1]={label="Properties",action="ctx_props"}return d end
function f.open(a)local b,c=e.selPath(a)if not b or not c then return end
a.ctxItems=f.buildItems(c,b,
(not c.dir)and f.openChoices(a,b)or nil)a.ctxPath=b;a.ctxFile=c;a.ctxSel=1;local d=a.LIST_TOP+
(a.browser.sel-a.browser.scroll)-1;a.ctxX=math.max(1,math.floor(
a.W/2)-10)a.ctxY=math.min(d,a.H-#
a.ctxItems-3)
if a.ctxY<2 then a.ctxY=2 end;a.ctxOpen=true end;function f.nextItem(a,b)local c=a.ctxSel+b
while c>=1 and c<=#a.ctxItems do if not
a.ctxItems[c].sep then a.ctxSel=c;return end;c=c+b end end
function f.execute(a,b,d,c)
local i=a.T;local j=a.F;a.ctxOpen=false;local k=b:match("^ctx_open:(.+)$")
if k then
local l,m=pcall(require,"shell.open")if c and l then
c(k.." "..m.quote(a.ctxPath))end;return end
if b=="ctx_view"then if not e.canRead(a,a.ctxPath)then return end
local l={{
" Viewing: "..a.ctxFile.name,i.title}}
local m,n,o=e.readLinesCapped(j,a.ctxPath,function(p)l[#l+1]={p,i.fg}end)if not m then
a.lastOut={"Cannot read: "..a.ctxFile.name,i.error}return end;if o then
l[#l+1]={string.format(e.VIEW_STOPPED,n),i.warning}end
g.openViewTab(a,l,a.ctxFile.name)elseif b=="ctx_edit"then g.openEditTab(a,a.ctxPath)elseif b=="ctx_run"then local m={}local function l(p,q)m[#m+1]={tostring(p),
q or i.fg}end
local n=e.safeModeRefusal(a.ctxPath)local o=not n and j.readFile(a.ctxPath)
if n then
l(n,i.error)elseif not o then
l("Cannot read: "..a.ctxFile.name,i.error)else
local p=d{name=a.ctxFile.name,stdout=function(s)l(s,i.fg)end}local q,r=load(o,"="..a.ctxFile.name,"t",p)
if not q then l(
"Compile error: "..tostring(r),i.error)else
local s,t=pcall(q)e.reportProgramEnd(a,l,s,t,"Runtime error: ",p)end end
if#m>0 then local p=e.expandBuf(a,m)if#p==1 then a.lastOut=p[1]else
g.openViewTab(a,p,a.ctxFile.name,true)end end elseif b=="ctx_copy"then if not e.canRead(a,a.ctxPath)then return end
a.clipboard={path=a.ctxPath,name=a.ctxFile.name}
a.lastOut={"Marked: "..a.ctxFile.name.."  -- navigate & F5 to paste",i.highlight}elseif b=="ctx_move"then h.doMove(a,a.ctxPath,a.ctxFile)elseif b=="ctx_delete"then
h.doDelete(a,a.ctxPath,a.ctxFile)elseif b=="ctx_rename"then h.doRename(a,a.ctxPath,a.ctxFile)elseif
b=="ctx_props"then local l
if a.ctxFile.dir then local j=a.F;local function q(s,t)return
s:sub(-1)=="/"and(s..t)or(s.."/"..t)end;local function r(s)
if not j.size then return 0 end;local t,u=pcall(j.size,s)
return(t and tonumber(u))or 0 end;local o,n=0,0
local function p(s)
local u,t=pcall(j.list,s)if not u or type(t)~="table"then return end;for w,v in ipairs(t)do
local x=q(s,(v:gsub("/$","")))local y,z=pcall(j.isDirectory,x)
if y and z then p(x)else n=n+1;o=o+r(x)end end end;p(a.ctxPath)
l=e.fmtSz(o).."  ("..n..
" file".. (n==1 and""or"s")..")"else l=e.fmtSz(a.ctxFile.sz)end
local m={{" Properties: "..a.ctxFile.name,i.title},{"",i.fg},{" Name:  "..
a.ctxFile.name,i.fg},{" Path:  "..a.ctxPath,i.fg},{" Size:  "..
l,i.fg},{" Type:  "..
(a.ctxFile.dir and"Directory"or(
a.ctxFile.name:match("%.(%w+)$")or"File")),i.fg}}
g.openViewTab(a,m,"Props:"..a.ctxFile.name:sub(1,8))end end;return f