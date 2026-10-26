local l=require("shell.panels.filebrowser")
local p=require("shell.panels.dialogs")local q=require("shell.panels.draw")
local r=require("shell.panels.widgets")local m=require("shell.panels.editor")
local j=require("shell.panels.helpers")local k=require("shell.keys")local n={}
local function o()
if coroutine.isyieldable and
coroutine.isyieldable()then return coroutine.yield()end;return require("computer").pullSignal(0.05)end
function n.execute(a,b,c)local d=a.T;local f=a.D;local i=a.K;local u=a.E;local g=a.W;local h=a.SC;local e=c.exec;local s=c.drawAll
local t=c.widgetDefs;a.menuOpen=nil;a.menuFocused=false;if type(b)=="string"then
local v=b:match("^run:(.+)$")if v then e(v)return nil end end
if
b=="newfile"then l.doNewFile(a)elseif b=="mkdir"then l.doMkdir(a)elseif b=="rename"then
l.doRename(a)elseif b=="delete"then l.doDelete(a)elseif b=="refresh"then j.refreshBrowser(a)elseif
b=="viewfile"then local w,v=j.selPath(a)
if
w and v and not v.dir and j.canRead(a,w)then local x=a.F.readFile(w)
if x then
local y={{" Viewing: "..v.name,d.title}}for z in x:gmatch("([^\n]*)\n?")do y[#y+1]={z,d.fg}end
m.openViewTab(a,y,v.name)else a.lastOut={"Cannot read: "..v.name,d.error}end end elseif b=="editfile"then local v,w=j.selPath(a)if v and w and not w.dir then
m.openEditTab(a,v)end elseif b=="logout"then j.logout(a)return"exit"elseif b=="quit"then s()
f.fill(1,a.OUT_ROW,g,1," ",d.fg,d.bg)
f.set(1,a.OUT_ROW,(" [1]Reboot [2]Shut down [3]Log out [4]CLI Mode ["..k.quitHint(a.who).."]Cancel"):sub(1,g),d.title,d.bg)
while true do local w,y,v,x=o()
if w=="key_down"then
if v==49 or v==50 then local z,A=j.canPowerOff(a)
if not z then
f.fill(1,a.OUT_ROW,g,1," ",d.fg,d.bg)f.set(1,a.OUT_ROW,A:sub(1,g),d.error,d.bg)elseif v==49 then
i.reboot()return"exit"else i.shutdown()return"exit"end elseif v==51 then j.logout(a)return"exit"elseif v==52 then return"cli"elseif k.isQuit(v,x,true,a.who)then
a.lastOut=nil;return nil end end end elseif b=="lua"then e("lua")elseif b=="verify"then e("verify")elseif b=="flash"then
local v=p.promptInput(a,"Flash file: ",60)if v and#v>0 then e("flash "..v)end elseif b=="ps"then e("ps")elseif b=="mem"then
e("mem")elseif b=="hw"then e("hw")elseif b=="df"then e("df")elseif b=="log"then e("log")elseif b=="reboot"then
local v,w=j.canPowerOff(a)if v then i.reboot()else a.lastOut={w,d.error}end elseif
b=="shutdown"then local v,w=j.canPowerOff(a)
if v then i.shutdown()else a.lastOut={w,d.error}end elseif b=="help"then e("help")elseif b=="man"then e("man")elseif b=="tutorial"then e("tutorial")elseif
b=="about"then e("about")elseif b=="keyhelp"then local x=d.title or d.highlight
local w=d.highlight or d.title;local y=d.fg;local E,A=pcall(require,"shell.panels.home")local B=E and A and
A.enabled(a)
local C=B and A.viewKeyLabel(a)or"F2"
local F=(E and A)and A.cycleKeyLabel(a)or"F2"
local function z(b)local H,k=pcall(require,"shell.keys")
if not(H and k)then return"?"end;local G=k.label(b,a.who)return(G~="")and G or"?"end;local D={{" TOS Keyboard Shortcuts",x},{"",y}}local function v(G,H)D[
#D+1]={G,H or y}end
if B then v(" Home",x)
v("   "..C..
string.rep(" ",math.max(1,
17-#C)).."Flip the view: tiles / files",w)
v("   Up/Down/Left/Rt  Move the selection in whichever view is up")
v("   Enter            Open the selection, or run the typed command")
v("   Alt+1-9          Quick-launch a tile on this page")
v("   PgUp / PgDn      Page the tiles / the file list")
v("   "..F..
string.rep(" ",math.max(1,17-#F)).."Next tab (on an empty command line)",w)v("")
v(" The prompt is always there, in both views. Anything you type")
v(" goes to it — which is why quick-launch is Alt+1-9 and history")
v(" is ^P / ^N rather than the arrows.",d.dim or y)else v(" File browser",x)
v("   Up / Down        Move selection")v("   PgUp / PgDn      Page up / down")
v("   Home / End       Jump to first / last")
v("   Enter            Open folder / run typed command")
v("   Backspace        Go up a directory (empty command line)")end;v("")v(" Function keys",x)
v("   F1   Help            "..C..
"   ".. (
B and"Flip view (tiles/files)"or"Next pane / tab"),w)v("   F3   View file       F4   Close tab",w)
v("   F5   Copy a FILE      F6   Move a FILE",w)v("   F7   New directory   F8   Delete",w)
v("   F9   Menu bar        F10  Power menu (reboot/off/logout)",w)v("")v(" Command line",x)
v("   Type a command, then Enter to run it.")if B then v("   Ctrl+P / Ctrl+N   Recall command history")else
v("   Up / Down         Recall command history")end
v("   Tab               Auto-complete")
v("   Ctrl+Q            Close menu / cancel prompt")v("")v(" Selecting and the clipboard",x)
v("   Shift + arrows   Select text (prompt, editor)")
v("   Shift + Up/Down  Select lines in a view buffer")
v("   "..
z("copy")..
string.rep(" ",math.max(1,17-#z("copy"))).."Copy the selection",w)
v("   "..
z("cut")..
string.rep(" ",math.max(1,17-#z("cut"))).."Cut the selection",w)
v("   "..z("paste")..
string.rep(" ",math.max(1,17-#z("paste"))).."Paste",w)
v("   With nothing selected, copy and cut take the whole line.")
v("   With the mouse driver, click and drag selects.")v("")
v("   Copy is Ctrl+Insert, not Ctrl+C: the kernel takes Ctrl+C to")
v("   interrupt the running program, so it never reaches a program")
v("   at all. DOS moved copy to Ctrl+Insert for the same reason.",d.dim or y)
v("   F5 and F6 in the file list are a separate FILE clipboard:")
v("   they mark and copy files, not text.",d.dim or y)v("")v(" Editor / viewer",x)
v("   Ctrl+S  Save     Ctrl+F  Find     Ctrl+Q  Close",w)v("")
v(" Tip: type 'help' for commands, or 'man <topic>' for detail.",d.dim or y)m.openViewTab(a,D,"Keyboard")elseif b=="statusbar_cfg"then
local v={"memory","disk","clock","user","uptime"}
for z,A in pairs(t)do local B=false
for A,C in ipairs(v)do if C==z then B=true;break end end;if not B then v[#v+1]=z end end;local y=r.getWidgetList(a)local w={}for A,z in ipairs(y)do w[z]=true end
local x=1
while true do f.fill(1,a.OUT_ROW,g,1," ",d.fg,d.bg)local z={}
for F,E in ipairs(v)do local G=
w[E]and"[x]"or"[ ]"if F==x then z[#z+1]=">"..G..E else
z[#z+1]=" "..G..E end end
f.set(1,a.OUT_ROW,table.concat(z," "):sub(1,g),d.title,d.bg)local C,D,B,A=o()
if C=="touch"and type(a._mouseLib)=="table"and A==
a.OUT_ROW then local E=1
for G,F in ipairs(v)do local H=4+#F;if B>=E and B<E+H then
x=G;w[F]=not w[F]break end;E=E+H+1 end elseif C=="key_down"then
if A==203 then x=math.max(1,x-1)elseif A==205 then x=math.min(#v,x+1)elseif
A==28 then local E=v[x]w[E]=not w[E]elseif k.isQuit(B,A,true,a.who)then local E={}for D,F in ipairs(v)do if w[F]then
E[#E+1]=F end end;if h and h.set then
h.set("statusbar_widgets",E)if h.save then h.save()end end
a.lastOut={"Status bar updated",d.highlight}break end end end end;return nil end
function n.menuNextItem(a,b)if not a.menuOpen then return end
local d=(a.menuDefs or q.menuDefs)[a.menuOpen].items;local c=a.menuSel+b;while c>=1 and c<=#d do
if not d[c].sep then a.menuSel=c;return end;c=c+b end end;return n