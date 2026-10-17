local j=require("shell.panels.filebrowser")
local n=require("shell.panels.dialogs")local o=require("shell.panels.draw")
local p=require("shell.panels.widgets")local k=require("shell.panels.editor")
local i=require("shell.panels.helpers")local l={}
local function m()if coroutine.isyieldable and coroutine.isyieldable()then return
coroutine.yield()end;return
require("computer").pullSignal(0.05)end
function l.execute(a,b,c)local d=a.T;local f=a.D;local q=a.K;local t=a.E;local g=a.W;local h=a.SC;local e=c.exec;local r=c.drawAll
local s=c.widgetDefs;a.menuOpen=nil;a.menuFocused=false;if type(b)=="string"then
local u=b:match("^run:(.+)$")if u then e(u)return nil end end
if
b=="newfile"then j.doNewFile(a)elseif b=="mkdir"then j.doMkdir(a)elseif b=="rename"then
j.doRename(a)elseif b=="delete"then j.doDelete(a)elseif b=="refresh"then i.refreshBrowser(a)elseif
b=="viewfile"then local v,u=i.selPath(a)
if
v and u and not u.dir and i.canRead(a,v)then local w=a.F.readFile(v)
if w then
local x={{" Viewing: "..u.name,d.title}}for y in w:gmatch("([^\n]*)\n?")do x[#x+1]={y,d.fg}end
k.openViewTab(a,x,u.name)else a.lastOut={"Cannot read: "..u.name,d.error}end end elseif b=="editfile"then local u,v=i.selPath(a)if u and v and not v.dir then
k.openEditTab(a,u)end elseif b=="logout"then i.logout(a)return"exit"elseif b=="quit"then r()
f.fill(1,a.OUT_ROW,g,1," ",d.fg,d.bg)
f.set(1,a.OUT_ROW,(" [1]Reboot [2]Shut down [3]Log out [4]CLI Mode [^Q]Cancel"):sub(1,g),d.title,d.bg)
while true do local v,w,u=m()
if v=="key_down"then
if u==49 or u==50 then local x,y=i.canPowerOff(a)
if not x then
f.fill(1,a.OUT_ROW,g,1," ",d.fg,d.bg)f.set(1,a.OUT_ROW,y:sub(1,g),d.error,d.bg)elseif u==49 then
q.reboot()return"exit"else q.shutdown()return"exit"end elseif u==51 then i.logout(a)return"exit"elseif u==52 then return"cli"elseif u==17 then a.lastOut=nil;return nil end end end elseif b=="lua"then e("lua")elseif b=="verify"then e("verify")elseif b=="flash"then
local u=n.promptInput(a,"Flash file: ",60)if u and#u>0 then e("flash "..u)end elseif b=="ps"then e("ps")elseif b=="mem"then
e("mem")elseif b=="hw"then e("hw")elseif b=="df"then e("df")elseif b=="log"then e("log")elseif b=="reboot"then
local u,v=i.canPowerOff(a)if u then q.reboot()else a.lastOut={v,d.error}end elseif
b=="shutdown"then local u,v=i.canPowerOff(a)
if u then q.shutdown()else a.lastOut={v,d.error}end elseif b=="help"then e("help")elseif b=="man"then e("man")elseif b=="tutorial"then e("tutorial")elseif
b=="about"then e("about")elseif b=="keyhelp"then local w=d.title or d.highlight
local v=d.highlight or d.title;local x=d.fg;local D,z=pcall(require,"shell.panels.home")local A=D and z and
z.enabled(a)
local B=A and z.viewKeyLabel(a)or"F2"
local E=(D and z)and z.cycleKeyLabel(a)or"F2"
local function y(b)local H,F=pcall(require,"shell.keys")
if not(H and F)then return"?"end;local G=F.label(b,a.who)return(G~="")and G or"?"end;local C={{" TOS Keyboard Shortcuts",w},{"",x}}local function u(F,G)C[
#C+1]={F,G or x}end
if A then u(" Home",w)
u("   "..B..
string.rep(" ",math.max(1,
17-#B)).."Flip the view: tiles / files",v)
u("   Up/Down/Left/Rt  Move the selection in whichever view is up")
u("   Enter            Open the selection, or run the typed command")
u("   Alt+1-9          Quick-launch a tile on this page")
u("   PgUp / PgDn      Page the tiles / the file list")
u("   "..E..
string.rep(" ",math.max(1,17-#E)).."Next tab (on an empty command line)",v)u("")
u(" The prompt is always there, in both views. Anything you type")
u(" goes to it — which is why quick-launch is Alt+1-9 and history")
u(" is ^P / ^N rather than the arrows.",d.dim or x)else u(" File browser",w)
u("   Up / Down        Move selection")u("   PgUp / PgDn      Page up / down")
u("   Home / End       Jump to first / last")
u("   Enter            Open folder / run typed command")
u("   Backspace        Go up a directory (empty command line)")end;u("")u(" Function keys",w)
u("   F1   Help            "..B..
"   ".. (
A and"Flip view (tiles/files)"or"Next pane / tab"),v)u("   F3   View file       F4   Close tab",v)
u("   F5   Copy a FILE      F6   Move a FILE",v)u("   F7   New directory   F8   Delete",v)
u("   F9   Menu bar        F10  Power menu (reboot/off/logout)",v)u("")u(" Command line",w)
u("   Type a command, then Enter to run it.")if A then u("   Ctrl+P / Ctrl+N   Recall command history")else
u("   Up / Down         Recall command history")end
u("   Tab               Auto-complete")
u("   Ctrl+Q            Close menu / cancel prompt")u("")u(" Selecting and the clipboard",w)
u("   Shift + arrows   Select text (prompt, editor)")
u("   Shift + Up/Down  Select lines in a view buffer")
u("   "..
y("copy")..
string.rep(" ",math.max(1,17-#y("copy"))).."Copy the selection",v)
u("   "..
y("cut")..
string.rep(" ",math.max(1,17-#y("cut"))).."Cut the selection",v)
u("   "..y("paste")..
string.rep(" ",math.max(1,17-#y("paste"))).."Paste",v)
u("   With nothing selected, copy and cut take the whole line.")
u("   With the mouse driver, click and drag selects.")u("")
u("   Copy is Ctrl+Insert, not Ctrl+C: the kernel takes Ctrl+C to")
u("   interrupt the running program, so it never reaches a program")
u("   at all. DOS moved copy to Ctrl+Insert for the same reason.",d.dim or x)
u("   F5 and F6 in the file list are a separate FILE clipboard:")
u("   they mark and copy files, not text.",d.dim or x)u("")u(" Editor / viewer",w)
u("   Ctrl+S  Save     Ctrl+F  Find     Ctrl+Q  Close",v)u("")
u(" Tip: type 'help' for commands, or 'man <topic>' for detail.",d.dim or x)k.openViewTab(a,C,"Keyboard")elseif b=="statusbar_cfg"then
local u={"memory","disk","clock","user","uptime"}
for y,z in pairs(s)do local A=false
for z,B in ipairs(u)do if B==y then A=true;break end end;if not A then u[#u+1]=y end end;local x=p.getWidgetList(a)local v={}for z,y in ipairs(x)do v[y]=true end
local w=1
while true do f.fill(1,a.OUT_ROW,g,1," ",d.fg,d.bg)local y={}
for E,D in ipairs(u)do local F=
v[D]and"[x]"or"[ ]"if E==w then y[#y+1]=">"..F..D else
y[#y+1]=" "..F..D end end
f.set(1,a.OUT_ROW,table.concat(y," "):sub(1,g),d.title,d.bg)local B,C,A,z=m()
if B=="touch"and type(a._mouseLib)=="table"and z==
a.OUT_ROW then local D=1
for F,E in ipairs(u)do local G=4+#E;if A>=D and A<D+G then
w=F;v[E]=not v[E]break end;D=D+G+1 end elseif B=="key_down"then
if z==203 then w=math.max(1,w-1)elseif z==205 then w=math.min(#u,w+1)elseif
z==28 then local D=u[w]v[D]=not v[D]elseif A==17 then local D={}for C,E in ipairs(u)do
if v[E]then D[#D+1]=E end end;if h and h.set then
h.set("statusbar_widgets",D)if h.save then h.save()end end
a.lastOut={"Status bar updated",d.highlight}break end end end end;return nil end
function l.menuNextItem(a,b)if not a.menuOpen then return end
local d=(a.menuDefs or o.menuDefs)[a.menuOpen].items;local c=a.menuSel+b;while c>=1 and c<=#d do
if not d[c].sep then a.menuSel=c;return end;c=c+b end end;return l