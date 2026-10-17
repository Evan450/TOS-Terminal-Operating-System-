local i=require("computer")local f={}local g="/etc/.tutorial_done"
local j=".tutorial_done"
function f.markerFor(a)if type(a)~="table"then return nil end;if
a.isGuest or a.user=="guest"then return nil end;local b=a.home;if
type(b)~="string"or b==""or b=="/"then return nil end;return
(b:gsub("/+$","")).."/"..j end
local h={{title="Welcome to TOS",minTier=0,lines={"","Welcome to TOS v"..
tostring(_G._TOS and _G._TOS.version or"?").."!","","TOS is a Terminal Operating System for OpenComputers.","It features a tabbed file browser, built-in editor,","networking, and more.","","This tutorial will walk you through the basics.","Let's get started!"}},{title="Navigation Basics",minTier=0,lines={"","The screen layout (top to bottom):","","  Tab bar       - open tabs across the top","  Menu bar      - actions and menus","  Path bar      - current directory","  File list     - files and folders","  Output line   - command results","  Command prompt - type commands here","  Status bar    - system info at the bottom","","Use arrow keys to browse files.","Press Enter for a context menu.","Type commands at the prompt like a terminal.","Press F1 anytime for command help."}},{title="Essential Commands",minTier=0,lines={"","File operations:","  ls  cd  cat  mkdir  cp  mv  rm","","Open the built-in editor:","  edit <file>","","Get help:","  help   or press F1","","These work just like a standard terminal."}},{title="Home: two views, one prompt",minTier=0,lines={"","  F2       - Flip the view: tiles / files","","Home is ONE tab. The tile grid and the file","list are two ways of looking at it, and the","prompt sits on the same row in both -- so it","is never somewhere else, and what you run","prints where the last thing printed.","","  Arrows   - Move the selection, either view","  Enter    - Open it (or run what you typed)","  Alt+1-9  - Launch a tile by its number","","Anything you type goes to the prompt, which","is why quick-launch is Alt+1-9 and history","is Ctrl+P / Ctrl+N."}},{title="Tabs & Multitasking",minTier=0,lines={"","  Tab      - Next tab (on an empty prompt)","  F4       - Close the current tab","  Ctrl+T   - Switch between shell and panels","","The editor opens in its own tab so you can","switch back and forth between files and code.","","  ps       - Show running processes"}},{title="Editor",minTier=0,lines={"","The built-in editor supports:","","  Ctrl+S           Save","  Ctrl+Q           Close","  Ctrl+F           Find","  Ctrl+H           Find & replace","  Ctrl+Z           Undo","  Ctrl+C / X / V   Copy / Cut / Paste lines"}},{title="Your Account",minTier=1,lines={"","  whoami   - Shows your username","  passwd   - Changes your password","","Your home directory is /home/<username>","","Permissions:","  Read:   /public","  Write:  /home/<you>, /tmp"}},{title="Administration",minTier=2,lines={"","User management:","  useradd  userdel  usermod","","Services & scheduling:","  service  - Manage startup services in /etc/rc.d/","  cron     - Manage scheduled tasks","","System control:","  shutdown   reboot   flash (write BIOS to EEPROM)"}},{title="Networking & Security",minTier=2,lines={"","Zero-trust model: peers start UNKNOWN and","must be elevated to TRUSTED before data flows.","","  net    - Show network status","  ping   - Discover peers","  chat   - Messaging","  rsh    - Remote shell commands","  scp    - Secure file transfer","","All comms are encrypted between TRUSTED peers."}},{title="System Internals",minTier=3,lines={"","  verify     - Check system file integrity","  log        - Show kernel log","  component <type> [method]","             - Call any OC component directly","  compat     - Show OpenOS compatibility status","","Startup scripts:  /etc/rc.d/","Scheduled tasks:  /etc/cron.dat","","  deploy     - Copy TOS to another disk"}},{title="Pipes & Extras",minTier=0,lines={"","Piping and redirection:","  cmd1 | cmd2    - Pipe output between commands","  cmd > file     - Redirect output to file","  cmd >> file    - Append output to file","","Peripherals:","  redstone   robot   inventory   tape","","  env        - View environment variables"}},{title="Ready!",minTier=0,lines={"","You're ready to use TOS!","","Remember:","  Press F1 anytime for command help.","","  Run 'tutorial' to see this again -- it won't","  interrupt you a second time on its own.","","Press Enter to begin."}}}
function f.shouldShow(a,b)if not(a and a.exists)then return false end
local c=f.markerFor(b)if not c then return not a.exists(g,b)end;if a.exists(c,b)then
return false end
if b.user=="root"and a.exists(g,b)then return false end;return true end
function f.run(a)local c=a.D;local o=a.F;local p=a.U;local q=a.st;local l=a.W or 80;local m=a.H or 25;local r=0
local n=nil;local s=nil;if p and q then local x=p.getSession(q)
if x then r=x.tier or 0;n=x;s=x end end
local t=f.markerFor(s)or g
local function u()local x,y
if n then x,y=o.writeFile(t,"1",n)else x,y=o.writeFile(t,"1")end;if not x then
pcall(function()local z=require("kernel.log")
if z and z.warn then z.warn("tutorial","markDone failed: "..
tostring(y))end end)end
return x,y end;local d={}
for x=1,#h do if r>=h[x].minTier then d[#d+1]=h[x]end end;if#d==0 then pcall(u)return end;local e=#d;local b=1;local function v()pcall(u)end
local function w(x,y)if
#x<=y then return{x}end;local z={}
while#x>y do local A=y;local B=false
for C=y,math.max(1,y-20),-1 do if
x:sub(C,C)==" "then A=C-1;B=true;break end end;z[#z+1]=x:sub(1,A)
x=x:sub(A+ (B and 2 or 1))end;if#x>0 then z[#z+1]=x end;return z end
local function k()local x=c.getTheme()local F=d[b]local A=math.min(l-2,60)
local B=math.min(m-2,20)local C=math.floor((l-A)/2)+1;local E=
math.floor((m-B)/2)+1;c.clear(x.bg)
c.dbox(C,E,A,B,F.title,{bg=x.panel_bg,border=x.border,title=x.title})local G=C+2;local H=E+2;local I=A-4;local J=B-4;local z={}
for M,L in ipairs(F.lines)do if#L==0 then z[#z+1]=""else for M,N in
ipairs(w(L,I))do z[#z+1]=N end end end;for L=1,math.min(#z,J)do
c.set(G,H+ (L-1),z[L],x.fg,x.panel_bg)end;local D=A-4;local y
if D>=44 then y=b.."/"..
e.." Enter:next Bksp:prev ^Q:skip"elseif D>=28 then y=b.."/"..e..
" Ent/Bksp:nav ^Q:skip"else y=b.."/"..
e.." Ent/Bk/^Q"end;if#y>D then y=y:sub(1,D)end
local K=C+math.floor((A-#y)/2)
c.set(math.max(C+1,K),E+B-1,y,x.dim,x.panel_bg)end;k()
while true do local y,A,z,x=i.pullSignal(0.5)
if y=="key_down"then
if z==17 then local B=c.getTheme()
local C="Skip tutorial? [y/N]"local E=math.max(1,math.floor((l-#C)/2))c.set(E,m,C,
B.warning or B.fg,B.bg)local D=false
repeat
local G,A,F=i.pullSignal(10)if G=="key_down"then if F==121 or F==89 then D=true;break elseif F~=0 then break end elseif G==
nil then break end until false;if D then v()return else k()end end;if x==28 or x==208 then if b>=e then v()return end;b=b+1;k()elseif x==14 or x==200 then if b>1 then b=b-1
k()end end end end end;return f