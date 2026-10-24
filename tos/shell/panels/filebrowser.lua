local k,n,o="Cancelled","Overwrite '","delete"
local i=require("shell.panels.helpers")local l=require("shell.panels.dialogs")local j={}
local function p()
if coroutine.isyieldable and
coroutine.isyieldable()then return coroutine.yield()end;return require("computer").pullSignal(0.05)end
function j.navigateUp(a)
local b=a.browser.path:match("^(.*)/[^/]+/?$")or"/"if b==""then b="/"end
a.browser.path=a.F.normalize and a.F.normalize(b)or b;a.browser.sel=1;a.browser.scroll=0
i.loadFiles(a,a.browser)a.cwd=a.browser.path end
function j.navigateInto(a,b)local c=a.F.join(a.browser.path,b)if
not i.canRead(a,c)then return end;a.browser.path=c;a.browser.sel=1
a.browser.scroll=0;i.loadFiles(a,a.browser)a.cwd=a.browser.path end
local function m(a,b)local d,c,e=a.D,a.T,a.W;d.fill(1,a.OUT_ROW,e,1," ",c.fg,c.bg)
d.set(1,a.OUT_ROW,(
b.." (y/n)"):sub(1,e),c.warning,c.bg)
while true do local g,h,f=p()if g=="key_down"then if f==121 or f==89 then return true end
return false end end end
function j.doCopy(a)local b=a.T
if a.clipboard then
local c=a.F.join(a.browser.path,a.clipboard.name)
if a.F.exists(c)and
not m(a,n..a.clipboard.name.."'?")then a.lastOut={k,b.dim}a.clipboard=nil;return end;local d,e=a.F.copy(a.clipboard.path,c)
if d then
i.refreshBrowser(a)
a.lastOut={"Pasted: "..a.clipboard.name.." -> "..a.browser.path,b.highlight}else
a.lastOut={"Paste failed: "..tostring(e or"unknown"),b.error}end;a.clipboard=nil else local c,d=i.selPath(a)if not c then
a.lastOut={"Select a file or folder to copy",b.warning}return end
if not i.canRead(a,c)then return end;a.clipboard={path=c,name=d.name}
a.lastOut={"Marked: "..
d.name.."  -- navigate & F5 to paste",b.highlight}end end
function j.doMove(a,b,c)local e=a.T
if not b then b,c=i.selPath(a)if not b or c.dir then
a.lastOut={"Select a file to move",e.warning}return end end;if not i.canWrite(a,b)then return end
local f=l.promptInput(a,"Move to: ",60)if not f or#f==0 then a.lastOut={k,e.dim}return end
local d=i.resolvePath(a,f)if a.F.isDirectory(d)then d=a.F.join(d,c.name)end;if not
i.canWrite(a,d)then return end
if a.F.exists(d)and d~=b then if not
m(a,n..d.."'?")then a.lastOut={k,e.dim}return end end;local g=a.F.rename(b,d)
if not g then local h,q=a.F.copy(b,d)if not h then
a.lastOut={"Move failed: "..tostring(q or
"copy failed"),e.error}return end;local r,s=a.F.remove(b)
if
not r then
a.lastOut={"Copied to "..
d.." but could not remove source: "..tostring(s or"?"),e.warning}i.refreshBrowser(a)return end end;i.refreshBrowser(a)
a.lastOut={"Moved: "..c.name.." -> "..d,e.highlight}end
function j.doDelete(a,b,c)local d=a.T;i.clearFailure(a)
if not b then b,c=i.selPath(a)if not b then
a.lastOut={"Nothing selected",d.warning}return end end
if b=="/"then return i.fail(a,"Cannot delete root",nil,o)end;if not i.canWrite(a,b)then return end
local f=b:match("^/tos")or
b:match("^/etc")or b:match("^/var")or
b:match("^/usr")local e;if not f then local s,r=pcall(require,"kernel.trash")
if s and r and r.put then e=r end end
local g=l.confirm(a,"Delete '"..
c.name.."'?\n"..
(e and
"It goes to the trash; 'trash restore' brings it back."or"This cannot be undone."),{title="Delete File",severity="danger",yes="Delete",no="Cancel",default="no"})if not g then a.lastOut={k,d.dim}return end
if e then
local s,t=e.put(b,i.sessionOf(a))if s then i.refreshBrowser(a)
a.lastOut={"Trashed: "..
c.name.." (use 'trash restore' to undo)",d.highlight}return end
local r=tostring(t or"unknown reason")
if not r:find("no trash",1,true)then
i.fail(a,"Not trashed: "..r..
" — still there; use  rm --hard  to force  [E-304 ERR_TRASH_REFUSED]",
nil,o)return end end;local h,q=a.F.remove(b)i.refreshBrowser(a)if h then
a.lastOut={"Deleted: "..c.name,d.highlight}else
i.fail(a,"Delete failed: "..tostring(q or"is the directory non-empty?"),
nil,o)end end
function j.doMkdir(a)local c=a.T
if not i.canWrite(a,a.browser.path)then return end;local b=l.promptInput(a,"New directory name: ",40)if
not b or#b==0 then a.lastOut={k,c.dim}return end
if
a.F.makeDirectory(a.F.join(a.browser.path,b))then i.refreshBrowser(a)
a.lastOut={"Created: "..b,c.highlight}else a.lastOut={"Failed",c.error}end end
function j.doRename(a,b,c)local d=a.T
if not b then b,c=i.selPath(a)if not b then
a.lastOut={"Nothing selected",d.warning}return end end;if not i.canWrite(a,b)then return end
local e=l.promptInput(a,"Rename to: ",60)if not e or#e==0 then a.lastOut={k,d.dim}return end
local f=a.F.join(a.browser.path,e)if f==b then a.lastOut={k,d.dim}return end;if a.F.exists(f)then if not
m(a,n..e.."'?")then a.lastOut={k,d.dim}return end
pcall(a.F.remove,f)end
if a.F.rename(b,f)then
i.refreshBrowser(a)
a.lastOut={"Renamed: "..c.name.." -> "..e,d.highlight}else
a.lastOut={"Rename failed (cross-fs? use F6 Move instead)",d.error}end end
function j.doNewFile(a)local c=a.T
if not i.canWrite(a,a.browser.path)then return end;local b=l.promptInput(a,"New file name: ",40)if not b or#b==0 then
a.lastOut={k,c.dim}return end
local d=a.F.join(a.browser.path,b)
if a.F.writeFile(d,"")then i.refreshBrowser(a)
a.lastOut={"Created: "..b,c.highlight}else a.lastOut={"Failed",c.error}end end;return j