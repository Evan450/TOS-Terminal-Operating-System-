
local Q,X,Y,J,L,Z,_,K,aa,ab,ac,I,ad,ae,af,ag,R,S,T,ah,U,ai,aj,ak="kernel.process","shell.keys","  Examples:","  Subcommands:","shell.panels.commands","function"," %-24s %8s","Cannot read: ","[^/]+$","Cancelled.","decrypt","encrypt","Write failed: ","Keychain is locked.","profile module unavailable","save failed","kernel.pkg","--system","timezone","Save failed"," (needs admin for /etc).","Save failed.","rename","Language: "local M=require("computer")local N=require("component")
local H=require("shell.panels.helpers")local O=function()end
do local b,a=pcall(require,Q)if b and a and a.yieldCooperative then
O=a.yieldCooperative end end;local function P()local a,b=pcall(require,"shell.panels.home")
return(a and b)or nil end;local function V(a)local b=P()return
b and b.cycleKeyLabel(a)or"F2"end
local function al(a)
local b=P()if b and b.enabled(a)then
return b.viewKeyLabel(a).."  Tiles / files "end;return"F2  Next tab      "end
local function W(a)local e=P()local d,b=pcall(require,X)if not(d and b)then
return"Copy Ctrl+Insert  Cut ^X  Paste ^V"end;local c=a and a.who or nil;return
"Copy "..
b.label("copy",c).."  Cut "..
b.label("cut",c).."  Paste "..b.label("paste",c)end
local function am(a)local b=V(a)return b..
string.rep(" ",math.max(1,12-#b)).."Next tab   "end
return
function(b,a,c)local h,ap,u,e,n,g=a.K,a.E,a.P,a.F,a.D,a.U;local p,A,i=a.SC,a.NM,a.st;local d=a.T;local B=a.tier
local q,v=a.W,a.H;local f=c.rp;local s=c.openViewTab;local aq=c.openEditTab;local k=c.refreshBrowser
local l=c.canRead;local o=c.canWrite;local ar=c.canAccess;local w=c.rootOnly;local r=c.adminOnly
local as=c.makeProgramEnv;local m=H.fmtSz
local at=function(E)return H.expandBuf(a,E)end;local j=c.promptInput
b.help=function(au,E)
local av=au and au[1]and au[1]:lower()
if av=="cp"or av=="copy"then E("cp <source> <dest>",d.title)
E("  Copy a file. Both paths are required.",d.fg)
E("  Paths starting with / are absolute; others are relative to cwd.",d.fg)E(Y,d.dim)
E("    cp notes.txt /home/root/notes_bak.txt",d.dim)E("    cp /etc/cfg.conf /tmp/cfg.conf",d.dim)
E("  Tip: Use F5 in the browser for clipboard-style copy.",d.highlight)elseif av=="mv"then E("mv <source> <dest>",d.title)
E("  Move or rename a file.",d.fg)E(Y,d.dim)
E("    mv old.txt new.txt           (rename in cwd)",d.dim)
E("    mv /tmp/work.lua /home/root/ (move to dir)",d.dim)elseif av=="cd"then E("cd [dir]",d.title)
E("  Change directory. With no argument, prints current directory.",d.fg)
E("  Special paths:  ..  (parent)   ~  (home dir)",d.fg)elseif av=="find"then E("find [path] [-name pattern]",d.title)
E("  Recursively search for files. Pattern uses Lua patterns.",d.fg)E(Y,d.dim)E("    find /tos -name *.lua",d.dim)
E("    find /home",d.dim)elseif av=="grep"then E("grep <pattern> <file>",d.title)
E("  Search file lines for pattern (plain text, not regex).",d.fg)
E("  Example:  grep function /tos/shell/init.lua",d.dim)elseif av=="flash"then E("flash <file>",d.title)
E("  Write a Lua file to the EEPROM (overwrites BIOS!).",d.fg)
E("  Prompts for confirmation. Use to install a new BIOS.",d.fg)E("  Example:  flash /tos/bios.lua",d.dim)elseif av=="edit"then
E("edit <file>",d.title)
E("  Open file in editor tab. Creates the file if it doesn't exist.",d.fg)
E("  Keys:  Ctrl+S = save   Ctrl+Q = close tab   Ctrl+F = find",d.dim)E("  Ctrl+H = find/replace  Ctrl+Z = undo",d.dim)E(
"  Select: Shift+arrows.  "..W(a),d.dim)
E("  With nothing selected, copy/cut take the whole line.",d.dim)
E("  Use "..V(a).." to switch tabs, F4 to close.",d.dim)elseif av=="run"then E("run <file> [args...]",d.title)
E("  Execute a Lua file in the current environment.",d.fg)
E("  Args are passed as a table in the second argument.",d.fg)elseif av=="tape"then E("tape [subcommand]",d.title)
E("  Data storage on Computronics tapes (requires module).",d.fg)
E("  If the tape package is not installed, shows",d.fg)
E("  instructions for installing it or building your own.",d.fg)E("",d.fg)
E("  Subcommands (when module is active):",d.dim)E("    detect           List tape drives",d.dim)
E("    info             Tape size, label, format",d.dim)E("    label [name]     Get/set tape label",d.dim)
E("    store <path>     Archive file/dir to tape",d.dim)
E("    restore [path]   Restore archive from tape",d.dim)
E("    list             List archived entries",d.dim)
E("    dump [off] [len] Hex dump of tape bytes",d.dim)E("    erase [full]     Quick or full wipe",d.dim)
E("    raw read/write   Low-level byte I/O",d.dim)elseif av=="net"then E("net [subcommand]",d.title)
E("  Network management (requires modem or linked card).",d.fg)E("",d.fg)E(J,d.dim)
E("    status              Show network status",d.dim)
E("    discover / scan     Broadcast ping to find peers",d.dim)
E("    peers / list        List known peers and trust levels",d.dim)
E("    trust <addr> [full] Elevate peer to KNOWN or TRUSTED",d.dim)E("    block <addr>        Block a peer",d.dim)
E("    send <addr> <msg>   Send message to trusted peer",d.dim)E("",d.fg)
E("  Related: ping <addr>, hostname [name], chat",d.dim)elseif

av=="pkg"or av=="mod"or av=="module"or av=="modules"or av=="package"or av=="packages"then E("pkg [subcommand]",d.title)
E("  Package manager — install and manage add-ons. (Replaces the old",d.fg)
E("  'mod'/module manager, retired in v1.3.1.)",d.fg)E("",d.fg)E(J,d.dim)
E("    list                List installed packages",d.dim)
E("    search              List packages on repos + mounted disks",d.dim)
E("    info <name>         Show a package's details + status",d.dim)
E("    install [name|dir]  By name (deps+hashes); a path installs a dir;",d.dim)
E("                        no arg scans mounted disks and prompts",d.dim)
E("    enable|disable <n>  Toggle an installed package (admin)",d.dim)
E("    uninstall <name>    Remove a package (admin)",d.dim)
E("    commands            List commands provided by packages",d.dim)
E("    make-disk <mount>   Build an add-on disk from installed packages",d.dim)E("",d.fg)
E("  Insert the Optional Utilities disk, then: pkg install",d.dim)
E("  Shortcuts: 'install <name>' and 'uninstall <name>' work too.",d.dim)elseif av=="monitor"or av=="top"then
E("monitor   (alias: top; also opened with Ctrl+T)",d.title)
E("  The live System Monitor — one screen showing what TOS is doing.",d.fg)E("",d.fg)E("  Shows:",d.dim)
E("    · Every process (kernel AND user), each explained, with owner,",d.dim)
E("      state, CPU and seat — auto-refreshing.",d.dim)
E("    · rc.d services and their status (admin).",d.dim)E("    · Memory and uptime vitals.",d.dim)
E("",d.fg)
E("  Runs as a full-screen tab: scrolls, never truncates, per-seat.",d.dim)E("",d.fg)E("  Keys:",d.dim)
E("    up/down move   Enter switch-to   K kill   T suspend/resume (TSR)",d.dim)
E("    Enter start-stop a service (admin)   R refresh   ^Q close",d.dim)elseif av=="cron"then E("cron [subcommand]",d.title)
E("  Manage scheduled tasks.  (admin+)",d.fg)E("",d.fg)E(J,d.dim)
E("    list                Show all cron jobs",d.dim)
E("    add <interval> <cmd> Schedule a command",d.dim)
E("    rm <id>             Remove a cron job",d.dim)elseif av=="service"then E("service [subcommand]",d.title)
E("  Manage startup services.  (admin+)",d.fg)E("",d.fg)E(J,d.dim)
E("    (none)              List all services and status",d.dim)E("    start <name>        Start a service",d.dim)
E("    stop <name>         Stop a service",d.dim)elseif av=="users"or av=="useradd"or av=="userdel"or
av=="usermod"then
E("User Management  (admin/root)",d.title)
E("  users                   List all user accounts",d.fg)
E("  useradd <name>          Create a new user",d.fg)E("  userdel <name>          Delete a user",d.fg)
E("  usermod <user> <action> Modify a user:",d.fg)
E("    lock / unlock         Lock or unlock an account",d.dim)
E("    admin / user          Set role to admin or user",d.dim)
E("  whoami                  Show current user",d.fg)
E("  passwd                  Change your password",d.fg)elseif av=="disk"then E("disk [subcommand]",d.title)
E("  Manage removable disks (floppies, HDDs).",d.fg)E("",d.fg)E(J,d.dim)
E("    list                List removable disks",d.dim)
E("    info <mount>        Show disk contents",d.dim)
E("    install <mount>     Install module from disk (admin)",d.dim)
E("    export <name> <mnt> Write module to disk    (admin)",d.dim)E("    eject <mount>       Unmount a disk",d.dim)elseif av==
"redstone"or av=="rs"then
E("redstone [subcommand]  (alias: rs)",d.title)E("  Control redstone I/O on all sides.",d.fg)
E("",d.fg)E(J,d.dim)
E("    (none)              Show redstone levels",d.dim)
E("    set <side> <level>  Set output (0-15)",d.dim)
E("    pulse <side> [dur]  Pulse output (default 0.5s)",d.dim)elseif av=="robot"then E("robot <command>",d.title)
E("  Control robot/drone movement and interaction.",d.fg)E("",d.fg)
E("  Movement: forward, back, up, down, left, right",d.dim)
E("  Actions:  swing, use, place, suck, drop, detect",d.dim)E("  Info:     name, energy, slot <n>",d.dim)elseif
av=="audio"or av=="sound"or av=="beep"then
E("audio [subcommand]",d.title)
E("  Control audio feedback (beeps and notifications).",d.fg)E("",d.fg)E(J,d.dim)
E("    (none)              Show audio status",d.dim)
E("    on                  Enable audio feedback",d.dim)
E("    off                 Disable audio feedback",d.dim)
E("    volume <0-100>      Set volume level (shorter/longer beeps)",d.dim)
E("    test                Play all beep codes",d.dim)E("",d.fg)E("  Beep codes:",d.dim)
E("    1 short high        Success / positive action",d.dim)
E("    2 ascending         Login success / confirm",d.dim)
E("    1 long low          Error / login failure",d.dim)
E("    3 short low         Critical error / kernel panic",d.dim)
E("    2 short             Warning / command not found",d.dim)
E("    2-tone chime        Chat message received",d.dim)
E("    2 descending        Shutdown / logout",d.dim)E("    3 ascending         Boot complete",d.dim)elseif av and
av~=""then local ax=require(L)local aw=ax.entry and ax.entry(av)
if aw then
local az={[0]="guest",[1]="user",[2]="admin",[3]="root"}E(av,d.title)
E("  ".. (aw.help or"(no description)"),d.fg)E("",d.fg)
E(string.format("  Minimum tier: %s    Group: %s",az[aw.tier or 0]or
tostring(aw.tier),aw.category or"?"),d.dim)
local ay="  Tip: run '"..av.."' with no args for usage"
if e.exists("/usr/man/"..av..".man")then ay=ay.."; 'man "..
av.."' for the manual."else ay=ay.."."end;E(ay,d.dim)else
E("No such command: '"..av.."'.  Type 'help' for the full list.",d.warning)end else local ax=require(L)
local function aw(aC)return ax.needMet and ax.needMet(aC)end
E("=== TOS Command Reference ===  (help <cmd> for detail)",d.title)E("",d.fg)E(" Navigation & Files",d.highlight)
E("  cd [dir]              Change directory  (~ = home, .. = parent)",d.fg)
E("  ls [path]             List directory  (dir = alias)",d.fg)
E("  cat <file...>         View file contents  (type = alias)",d.fg)
E("  more <file>           Open file in view tab",d.fg)
if a.userTier>=1 then
E("  mkdir [-p] <dir...>   Create directories",d.fg)
E("  touch <file...>       Create empty files",d.fg)
E("  cp <src> <dst>        Copy file (both paths required)",d.fg)
E("  mv <src> <dst>        Move or rename file",d.fg)
E("  rm <path>             Delete file or directory",d.fg)end
E("  find [path] [-name p] Recursive file search",d.fg)
E("  grep <pat> <file>     Search file for text pattern",d.fg)
E("  wc <file>             Show line / word / byte counts",d.fg)
E("  df                    Show disk usage for all mounts",d.fg)
E("  echo [text]           Print text to output",d.fg)E("",d.fg)E(" UI & Shortcuts",d.highlight)
E("  F1  Help      "..al(a)..
"  F3  View file",d.fg)
E("  F4  Close tab F5  Copy file      F6  Move file",d.fg)
E("  "..am(a).." F9  Menu bar",d.fg)E("  F7  Mkdir     F8  Delete",d.fg)
E("  Text: Shift+arrows select.  "..W(a),d.fg)
E("  F10 Quit      ^Q  Cancel/Close   ^F  Find",d.fg)
E("  Enter on file = context menu  |  ^T  System Monitor",d.dim)
if a.userTier>=1 then E("",d.fg)E(" Devices",d.highlight)
E("  lsdev                 List all connected peripherals",d.fg)
E("  mount                 List mounted filesystems",d.fg)
if a.userTier>=2 then
E("  mount <dev> <path>    Mount a device at path",d.fg)E("  umount <path>         Unmount a device",d.fg)end end;E("",d.fg)E(" System",d.highlight)
E("  mem    Show memory usage",d.fg)E("  hw     List hardware components",d.fg)
E("  ps     Show running processes  (snapshot)",d.fg)
E("  monitor  Live System Monitor: processes/services/memory  (also ^T)",d.fg)E("  ver    TOS version info",d.fg)
E("  about  Changelog and credits",d.fg)E("  uptime Show system uptime",d.fg)
if a.userTier>=1 then
E("  srm    System Repair & Maintenance  (status/scan/repair/baseline)",d.fg)
E("  doctor Runtime health: memory, disk, services, power, security",d.fg)end;if a.userTier>=2 then
E("  log [N]       Show last N system log entries",d.fg)
E("  verify Check all system files for integrity",d.fg)end
if
a.userTier>=1 then E("  run <file>    Execute a Lua file",d.fg)
E("  bg <file>     Run a Lua file in a background tab",d.fg)
E("  edit <file>   Open in editor tab  (^S save, ^Q close)",d.fg)end
if a.userTier>=3 then
E("  lua           Interactive Lua REPL  (exit to quit)",d.fg)
E("  flash <file>  Flash EEPROM with Lua file  (!CAUTION)",d.fg)end
E("  programs      List executables in /bin and /usr/bin",d.fg)E("  history       Show command history",d.fg)
E("  date [fmt]    Show wall clock  (time = alias)",d.fg)
E("  tree [path] [depth]  Visual recursive directory listing",d.fg)
E("  theme [list|set|color|...]  Customize colors  (colors = alias)",d.fg)
E("  tutorial      Replay the welcome walkthrough",d.fg)if a.userTier>=1 and aw("swap")then
E("  swap                Disk-swap status ('slow RAM' on /var/swap)",d.fg)end;if a.userTier>=1 then
E("  optimize [power|buffer|swap]  Performance & power conservation",d.fg)end;if a.userTier>=2 then
E("  bootsettings [..]   Edit boot profile/verbosity  (or DEL at boot)",d.fg)end;E("",d.fg)
E(" Session & Power",d.highlight)E("  whoami  passwd  logout",d.fg)
if a.userTier>=2 then
E("  users                            List user accounts",d.fg)E("  reboot  shutdown",d.fg)end
if a.userTier>=3 then E("",d.fg)
E(" Administration (root)",d.highlight)
E("  useradd <user>                   Create a new user",d.fg)
E("  userdel <user>                   Delete a user",d.fg)
E("  usermod <user> lock|unlock|admin|user  Modify user",d.fg)
E("  deploy <mount>                   Copy TOS to another disk",d.fg)end
if a.userTier>=2 then E("",d.fg)
E(" Environment & Services",d.highlight)
E("  env [KEY=VAL]   Show/set environment variables",d.fg)
E("  service [start|stop <n>]  Manage startup services",d.fg)
E("  cron [list|add|rm]        Scheduled tasks",d.fg)end;local ay,az=aw("component:redstone"),aw("component:robot")
local aA,aB=aw("inventory"),aw("module:tape")
if ay or az or aA or aB or a.userTier>=2 then E("",d.fg)
E(" Peripherals",d.highlight)if ay then
E("  redstone [set|pulse] Control redstone I/O  (rs = alias)",d.fg)end;if az then
E("  robot <cmd>          Robot/drone movement & interaction",d.fg)end;if aA then
E("  inventory [side]     Inspect inventories  (inv = alias)",d.fg)end;if aB then
E("  tape [subcmd]        Tape drive data storage (module)",d.fg)end;if a.userTier>=2 then
E("  component <type> [method] [args]  Call any component",d.fg)end end
if A then E("",d.fg)E(" Network",d.highlight)
E("  net  ping  hostname",d.fg)if a.userTier>=1 then
E("  chat               Open chat with trusted peers",d.fg)end
if a.userTier>=2 then
E("  hostname  config  battery  audio",d.fg)
E("  rsh <addr> <cmd>   Run command on remote peer",d.fg)
E("  scp <addr>:<path> <local>  Transfer file from peer",d.fg)
E("  screen [list|next|N]  Manage multiple displays",d.fg)end end;E("",d.fg)E(" Packages & Disks",d.highlight)
E("  pkg list           List installed packages",d.fg)
E("  pkg search         Show packages on repos + mounted disks",d.fg)
if a.userTier>=2 then
E("  pkg install <name>         Install an add-on (deps + verify)",d.fg)
E("  pkg enable|disable <name>  Toggle an installed package",d.fg)
E("  pkg uninstall <name>       Remove a package",d.fg)
E("  pkg install                Install from an inserted disk (no arg)",d.fg)end
E("  disk [list]        List removable disks",d.fg)E("  disk info <mount>  Show disk contents",d.fg)
if
a.userTier>=2 then
E("  disk install <mount>          Install module from disk",d.fg)
E("  disk export <name> <mount>    Write module to disk",d.fg)end;E("  disk eject <mount> Unmount a disk",d.fg)if
a.userTier>=2 then E("",d.fg)E(" Compatibility",d.highlight)
E("  compat             Show OpenOS compatibility status",d.fg)end
E("",d.fg)E(" Pipes & Redirects",d.highlight)
E("  cmd1 | cmd2        Pipe output of cmd1 into cmd2",d.fg)
E("  cmd > file         Redirect output to file",d.fg)
E("  cmd >> file        Append output to file",d.fg)E("",d.fg)
E("Showing only what's installed here. 'man <topic>' for detail; MANUAL.md for the book.",d.dim)end end
b.man=function(au,E)local aw="/usr/man"local av=au and au[1]
if not av then
E("Manual pages — usage: man <topic>",d.title)local az=
(e.isDirectory and e.isDirectory(aw)and e.list(aw))or{}
if
type(az)=="table"and#az>0 then table.sort(az)
for aB,aA in ipairs(az)do
local aC=(aA:gsub("/$","")):gsub("%.man$","")if aC~=""then E("  "..aC,d.fg)end end else
E("  (no manual pages installed under "..aw..")",d.dim)end
E("Depth: help (quick) < man (detailed) < MANUAL.md (the full book)",d.dim)return end;av=tostring(av):gsub("[^%w_%-]","")if av==""then
E("man: invalid topic",d.error)return end;local ax=e.join(aw,av..".man")if not
e.exists(ax)then ax=e.join(aw,av)end
if not e.exists(ax)then E(
"No manual page for '"..av.."'.",d.error)
E(
"Try 'help "..av.."', or open MANUAL.md for the full book.",d.dim)return end;local ay=e.readFile(ax)if not ay then
E("man: cannot read page",d.error)return end
if s then local az={}
for aA in
(ay.."\n"):gmatch("([^\n]*)\n")do local aB=d.fg
if aA:match("^[A-Z][A-Z0-9 /%-]+$")then aB=d.title elseif aA:match("^%s")then aB=d.dim end;az[#az+1]={aA,aB}end;s(az,"man "..av)else for az in(ay.."\n"):gmatch("([^\n]*)\n")do
E(az,d.fg)end end end
b.about=function(au,E)local av=_G._TOS or{}
local ay,aw,az="Strata Systems LLC",nil,"Terminal Operating System"local aA,ax=pcall(require,"kernel.logo")if aA and ax then
ay=ax.VENDOR or ay;aw=ax.MOTTO;az=ax.TAGLINE or az end;E(
"TOS - "..az,d.title)
E("Version "..
(av.version or"?").."  [".. (av.codename or
"?").."]",d.highlight)
E("Build "..tostring(av.build or"?").." ("..
tostring(av.variant or"?")..")",d.dim)
E("GPU T"..B.." | "..
math.floor(M.totalMemory()/1024).."K RAM",d.dim)E(ay.."   -   GNU GPL v3.0",d.dim)if aw and aw~=""then E(
'"'..aw..'"',d.dim)end;E("",d.fg)
E("A secure, multi-seat terminal OS for OpenComputers:",d.fg)
E("  - Sandboxed processes, role-based users, encrypted homes",d.fg)
E("  - Tabbed file browser + editor, themeable panels UI",d.fg)
E("  - Zero-trust networking: chat, mesh mail, clustering",d.fg)
E("  - Package manager + Optional Utilities add-on disk",d.fg)
E("  - Boot Settings (DEL at POST), swap, backups, OpenOS compat",d.fg)E("",d.fg)
E("'help' lists commands · 'tutorial' walks you through it.",d.dim)end;b.ver=b.about
b.echo=function(E,au)au(table.concat(E," "),d.fg)end
b.notify=function(au,E)local aC,av=pcall(require,"kernel.notify")if not aC or not av then
E("notify unavailable",d.error)return end;local ax,ay,aw="info",nil,{}local az
for aE=1,# (au or{})
do local aF=tostring(au[aE])
if aE==az then elseif aF:sub(1,2)=="--"then
local aH,aG=aF:match("^%-%-([%w%-]+)=?(.*)$")
if aH=="style"or aH=="title"then if aG==""and au[aE+1]and
tostring(au[aE+1]):sub(1,2)~="--"then
aG=tostring(au[aE+1])az=aE+1 end
if aH=="style"then ax=aG else ay=aG end end else aw[#aw+1]=aF end end;local aA=table.concat(aw," ")
if aA==""then
E("Usage: notify <message> [--style info|warn|danger|error] [--title T]",d.title)
E("Puts a modal dialog box in front of every seat — the intrusive",d.dim)
E("counterpart to 'echo', which only writes above the command line.",d.dim)E("",d.dim)
E(string.format("Pending now: %d   (limits: %ds between boxes, %ds per source)",av.depth(),av.MIN_GAP,av.MIN_SOURCE_GAP),d.dim)return end
local aB,aD=av.post({message=aA,style=ax,title=ay,from="notify/"..tostring(a.who or"?")})
if aB then
E("Raised on every seat (dialog #"..aB..").",d.highlight)else
E("Not raised: "..tostring(aD),d.warning)
E("The message is in the log either way ('log' to see it).",d.dim)end end
b.tutorial=function(au,E)local aw,av=H.requireRoomy(a,"shell.tutorial","core")
if
not aw then E(H.loadFailure("tutorial",av),d.error)return end
if au[1]=="--reset"then local ay=
(g and i and g.getSession)and g.getSession(i)or nil;local ax=av.markerFor and
av.markerFor(ay)
if ax and e.exists(ax)then
e.remove(ax)
E("Tutorial reset — it will run again at your next login.",d.success or d.fg)elseif ax then
E("Tutorial was not marked done for this account.",d.dim)else
E("This account has no home to remember the tutorial in.",d.dim)end end;av.run({D=n,F=e,U=g,st=i,W=q,H=v})c.drawAll()end
b.cls=function(E,au)n.fill(1,1,q,v," ",d.fg,d.bg)c.drawAll()end;b.clear=b.cls
b.cd=function(E,au)if not E[1]then au(a.cwd,d.fg)return end
local av=E[1]
if av==".."then
a.cwd=a.cwd:match("^(.*)/[^/]+/?$")or"/"if a.cwd==""then a.cwd="/"end else local aw=f(av):gsub("//+","/")
if
aw~="/"and aw:sub(-1)=="/"then aw=aw:sub(1,-2)end;if e.isDirectory(aw)then a.cwd=aw else
au("Not a directory: "..av,d.error)return end end;a.browser.path=a.cwd;a.browser.sel=1;a.browser.scroll=0
c.loadFiles(a.browser)end
b.ls=function(au,E)local aA,aB,ax=false,false,nil
for aG,aF in ipairs(au)do
if not ax and aF:sub(1,1)=="-"and
#aF>1 then
for aH in aF:sub(2):gmatch(".")do if aH=="l"then aA=true elseif aH=="a"then aB=true else
E("Usage: ls [-l|-a] [dir]",d.dim)return end end elseif not ax then ax=aF end end;local av=f(ax or a.cwd)if not l(av,E)then return end;if e.exists and
not e.exists(av)then
E("no such file: ".. (ax or av),d.error)return end
local aD,ay=pcall(e.list,av)
if not aD or not ay then E("Cannot list: "..av,d.error)return end;local aw,az={},0;local function aC(aF)
if aB or aF:sub(1,1)~="."then aw[#aw+1]=aF else az=az+1 end end
if type(ay)=="table"then for aG,aF in ipairs(ay)do
aC(aF)end elseif type(ay)==Z then for aF in ay do aC(aF)end end
table.sort(aw,function(aF,aG)local aH,aI=aF:sub(-1)=="/",aG:sub(-1)=="/"if aH~=aI then
return aH end;return aF<aG end)
local function aE(aF)if not e.lastModified then return"-"end
local aH,aG=pcall(e.lastModified,e.join(av,aF))
if not aH or type(aG)~="number"or aG<=0 then return"-"end
local aI,aJ=pcall(os.date,"%Y-%m-%d %H:%M",math.floor(aG/1000))return aI and aJ or"-"end
if aA then
E(string.format(" %-24s %8s  %s","Name","Size","Modified"),d.title)E(string.rep("-",52),d.border)else
E(string.format(_,"Name","Size"),d.title)E(string.rep("-",34),d.border)end
for aG,aF in ipairs(aw)do local aI,aH
if aF:sub(-1)=="/"then
aI=string.format(_,"["..aF:sub(1,-2).."]","<DIR>")aH=d.dir or d.highlight else local aJ=e.size(e.join(av,aF))
aH=d.fg
if aF:match("%.lua$")then
aH=d.file_lua or d.file_exec or d.highlight elseif aF:match("%.cfg$")or aF:match("%.conf$")then
aH=d.file_cfg or d.warning elseif aF:match("%.log$")then aH=d.file_log or d.dim end;aI=string.format(_,aF:sub(1,24),m(aJ))end;if aA then aI=aI.."  "..aE(aF)end;E(aI,aH)end
if az>0 then
E(#aw.." items ("..az.." hidden: ls -a shows them)",d.dim)else E(#aw.." items",d.dim)end end;b.dir=b.ls
local function C(au,E)local av=f(au)if not l(av,E)then return true end;local aw,ax,ay=H.readLinesCapped(e,av,function(az)
E(az,d.fg)end)if not aw then E(
K..au,d.error)elseif ay then
E(string.format(H.VIEW_STOPPED,ax),d.warning)return false end;return true end
b.cat=function(E,au)
if not E[1]then au("Usage: cat <file...>",d.dim)return end;for aw,av in ipairs(E)do if not C(av,au)then break end end end;b.type=b.cat
b.more=function(E,au)
if not E[1]then au("Usage: more <file>",d.dim)return end;local aw=f(E[1])if not l(aw,au)then return end
local av={{" "..aw,d.title}}
local ax,ay,az=H.readLinesCapped(e,aw,function(aA)av[#av+1]={aA,d.fg}end)if not ax then au(K..E[1],d.error)return end;if az then
av[#av+1]={string.format(H.VIEW_STOPPED,ay),d.warning}end
s(av,E[1]:match(aa)or E[1])end
local function D(E,av,au)local aw=f(E)local ax=aw:match("^(.*)/[^/]+/?$")or"/"if not
o(ax,au)then return false end;if e.isDirectory and e.isDirectory(aw)then
if
not av then au("Already exists: "..E,d.warning)end;return false end
local ay,az=e.makeDirectory(aw)
if ay then au("Created: "..E,d.highlight)return true end
au(tostring(az or"Could not create "..E),d.error)return false end
b.mkdir=function(au,E)local ax,av=false,{}
for az,ay in ipairs(au)do if ay=="-p"or ay=="--parents"then ax=true else
av[#av+1]=ay end end
if not av[1]then E("Usage: mkdir [-p] <dir...>",d.dim)return end;local aw=false;for az,ay in ipairs(av)do aw=D(ay,ax,E)or aw end
if aw then k()end end
local function F(E,au)local av=f(E)if not o(av,au)then return false end
if not e.exists(av)then
local aw,ax=e.writeFile(av,"")if not aw then
au(tostring(ax or"Could not create "..E),d.error)return false end end;au("Touched: "..E,d.highlight)return true end
b.touch=function(E,au)
if not E[1]then au("Usage: touch <file...>",d.dim)return end;local av=false;for ax,aw in ipairs(E)do av=F(aw,au)or av end
if av then k()end end
local function x(E)local av,au=false,{}for ax,aw in ipairs(E)do if aw=="-k"or aw=="--keep"then av=true else
au[#au+1]=aw end end;return
av,au end
b.compress=function(au,E)local aE,aw=x(au)if not aw[1]then
E("Usage: compress <file> [out]   (-k keeps original)",d.dim)return end
local az=h.getCompress and h.getCompress()if not az or not az.available()then
E("Compression needs a data card (none detected).",d.error)return end;local av=f(aw[1])if not
l(av,E)then return end;if not e.exists(av)or
(e.isDirectory and e.isDirectory(av))then
E("Not a file: "..aw[1],d.error)return end
local aA=e.readFile(av)if not aA then E("Read failed",d.error)return end;local ax=aw[2]and
f(aw[2])or(av..".tcz")
if not o(ax,E)then return end;local aB,aC,ay,aD=az.pack(aA)
if not aB then E("Compress failed",d.error)return end
if not e.writeFile(ax,aB)then E("Write failed",d.error)return end;if not aE and ax~=av then pcall(e.remove,av)end;k()
local aF=
(ay>0)and math.floor((ay-aD)*100/ay)or 0
E(string.format("%s -> %s  (%d%% smaller: %s -> %s)",aw[1],(ax:gsub("^.*/","")),aF,m(ay),m(aD)),
aC=="deflate"and d.highlight or d.warning)if aC=="stored"then
E("(stored uncompressed — data didn't shrink)",d.dim)end end
b.decompress=function(au,E)local aB,aw=x(au)if not aw[1]then
E("Usage: decompress <file.tcz> [out]   (-k keeps original)",d.dim)return end;local av=f(aw[1])if
not l(av,E)then return end;if not e.exists(av)then
E("No such file: "..aw[1],d.error)return end;local ay=e.readFile(av)if not ay then
E("Read failed",d.error)return end
local az=h.getCompress and h.getCompress()
if not az then E("Compression module unavailable",d.error)return end;if not az.isPacked(ay)then
E("Not a .tcz container: "..aw[1],d.error)return end;local aA,aC=az.unpack(ay)if not aA then
E(
"Decompress failed: "..tostring(aC),d.error)return end;local ax
if aw[2]then ax=f(aw[2])elseif av:sub(-4)==
".tcz"then ax=av:sub(1,-5)else ax=av..".out"end;if not o(ax,E)then return end;if not e.writeFile(ax,aA)then
E("Write failed",d.error)return end;if not aB and ax~=av then
pcall(e.remove,av)end;k()
E(string.format("%s -> %s  (%s restored)",aw[1],(ax:gsub("^.*/","")),m(
#aA)),d.highlight)end
local function G(au,av,aw,E)local ax=f(au)
if ax=="/"then E("Cannot remove root",d.error)return end;local ay=_G._TOS and _G._TOS.securefs
if ay and
type(ay.removeRefusal)==Z then
local aC=ay.removeRefusal(ax,H.sessionOf(a))if aC then E(tostring(aC),d.error)return end end
local aA={"^/$","^/init%.lua$","^/bios%.lua$","^/tos$","^/tos/","^/etc$","^/etc/","^/boot$","^/boot/"}
for aD,aC in ipairs(aA)do
if ax:match(aC)and not av then
E("Refusing to remove a system path without -r: "..ax..
"  [E-303 ERR_RM_SYSTEM_PATH]",d.error)
E("Protection is off, so this would really delete it. Add -r to confirm.",d.dim)return end end;if not o(ax,E)then return end
if e.isDirectory and e.isDirectory(ax)then if not av then
E(
"Cannot remove directory without -r: "..ax.."  [E-302 ERR_NEEDS_RECURSIVE]",d.error)return end
local aC=e.list and e.list(ax)if aC and#aC>0 then
E("Removing "..#aC.." item(s) under "..ax.."...",d.dim)end end;local az=false
local aB=ax:match("^/tos")or ax:match("^/etc")or
ax:match("^/var")or ax:match("^/usr")
if not aw and not aB then local aD,aC=pcall(require,"kernel.trash")
if
aD and aC and aC.put then local aE=H.sessionOf(a)local aF,aG=aC.put(ax,aE)
if aF then az=true
E("Trashed: "..au..
" (use 'restore' to undo)",d.highlight)else local aH=tostring(aG or"unknown reason")
if
aH:find("no trash",1,true)then
E("No trash for this session — deleting "..au.." outright.",d.warning)else
E("Not trashed: "..aH.."  [E-304 ERR_TRASH_REFUSED]",d.error)
E("It is still there. Delete it for good with:  rm "..
(av and"-r "or"").."--hard "..au,d.dim)return end end end end
if not az then local aC,aD=e.remove(ax)if aC then k()
E("Removed: "..au,d.highlight)else
E(tostring(aD or"Could not remove "..au),d.error)end else k()end end
b.rm=function(au,E)local aw,ax=false,false;local av={}for az,ay in ipairs(au)do
if
ay=="-r"or ay=="-rf"or ay=="-R"then aw=true elseif ay=="--hard"or ay=="-H"then ax=true else av[#av+1]=ay end end
if
#av==0 then E("Usage: rm [-r] [--hard] <path...>",d.dim)return end;for az,ay in ipairs(av)do G(ay,aw,ax,E)end end
b.trash=function(au,E)local ay,av=pcall(require,"kernel.trash")if not ay or not av then
E("Trash unavailable",d.error)return end;local aw=au[1]or"list"
local ax=H.sessionOf(a)
if aw=="list"or aw=="ls"then local aA=av.list(ax)if#aA==0 then
E("Trash is empty.",d.dim)return end
E(string.format(" %-20s %-8s %s","name","size","origin"),d.title)for aC,aB in ipairs(aA)do
E(string.format(" %-20s %-8d %s",aB.name:sub(1,20),aB.size,aB.origin),d.fg)end;local az=av.usage(ax)if
az then
E(string.format(" %d/%d items, %d/%d bytes used",az.count,az.max_count,az.bytes,az.max_bytes),d.dim)end elseif aw=="empty"then
local aA,az=av.empty(ax)if aA then
E("Emptied "..tostring(az).." items.",d.highlight)else
E(tostring(az or"empty failed"),d.error)end elseif aw=="restore"then if not au[2]then
E("Usage: trash restore <name> [dest] [--force]",d.dim)return end;local az,aA=false,nil;for aD=3,#au do
if
au[aD]=="--force"or au[aD]=="-f"then az=true else aA=au[aD]end end
local aC,aB=av.restore(au[2],{session=ax,dest=aA,force=az})if aC then k()
E("Restored to "..tostring(aB),d.highlight)else
E(tostring(aB or"restore failed"),d.error)end else
E("Usage: trash [list|empty|restore <name> [dest] [--force]]",d.dim)end end
b.vault=function(au,E)local aC,aw=H.requireRoomy(a,"kernel.vault","core")
if
not aC or not aw then E(H.loadFailure("vault",aw),d.error)return end;local av=au[1]local aA=H.sessionOf(a)
local ax=_G._TOS and _G._TOS.securefs
local function ay(aD)if ax and ax.readFile then return ax.readFile(aD,aA)end;return
nil,"securefs unavailable (refusing unchecked read)"end
local function aB(aD,aE)
if ax and ax.writeFile then return ax.writeFile(aD,aE,aA)end;return false,"securefs unavailable (refusing unchecked write)"end
local function az(aD,aE)
if aD~=nil and aD~="-"then
E("Note: a typed passphrase stays in this seat's command history;",d.dim)
E("leave it off, or use -, to be asked for it instead.",d.dim)return aD end;if not j then
E("Cannot ask for a passphrase here: give it as the last argument.",d.error)return nil end
local aF=j("Passphrase: ",256,true)if not aF or aF==""then E(ab,d.dim)return nil end
if aE then
local aG=j("Again, to confirm: ",256,true)if aG~=aF then
E(aG and"The two did not match; nothing was changed."or ab,d.error)return nil end end;return aF end
if av==I or av==ac then local aG,aI=au[2],au[3]if not aG or not aI then
E("Usage: vault "..av..
" <src> <dst> [passphrase | -]",d.dim)return end;local aD=ay(f(aG))if not aD then E(K..
aG,d.error)return end;if av==ac and
not aw.isEncrypted(aD)then
E("Source is not a TOS vault blob.",d.warning)return end
local aH=az(au[4],av==I)if not aH then return end;local aE,aF;if av==I then aE,aF=aw.encrypt(aD,aH)else
aE,aF=aw.decrypt(aD,aH)end;if not aE then
E("Failed: "..tostring(aF),d.error)return end;local aJ,aK=aB(f(aI),aE)if not aJ then
E(ad..tostring(aK),d.error)return end
E(string.format("%s %d -> %d bytes (algo=%s)",av==I and"Encrypted"or
"Decrypted",#aD,#aE,tostring(aF.algo)),d.highlight)elseif av=="encrypt-in-place"or av=="decrypt-in-place"then
local aG=au[2]if not aG then
E("Usage: vault "..av.." <file> [passphrase | -]",d.dim)return end;local aJ=f(aG)local aD=ay(aJ)if not aD then
E(K..aG,d.error)return end;local aF=av:sub(1,7)==I
if
aF and aw.isEncrypted(aD)then
E("Already encrypted — refusing to double-encrypt.",d.warning)return elseif not aF and not aw.isEncrypted(aD)then
E("Not a vault blob — nothing to decrypt.",d.warning)return end;local aH=az(au[3],aF)if not aH then return end;local aE,aI;if aF then
aE,aI=aw.encrypt(aD,aH)else aE,aI=aw.decrypt(aD,aH)end
if not aE then E("Failed: "..
tostring(aI),d.error)return end;local aK,aL=aB(aJ,aE)if not aK then E(ad..tostring(aL),d.error)
return end
E(string.format("%s in place: %d -> %d bytes",
av:sub(1,7)==I and"Encrypted"or"Decrypted",#aD,#aE),d.highlight)elseif av=="info"then local aD=au[2]if not aD then
E("Usage: vault info <file>",d.dim)return end;local aE=ay(f(aD))if not aE then
E(K..aD,d.error)return end;if not aw.isEncrypted(aE)then
E("Not a vault blob (no TVAULT1 magic).",d.warning)return end
E(string.format(" file:     %s",aD),d.title)
E(string.format(" size:     %d bytes",#aE),d.fg)local aF=#aw.MAGIC+1
local aG=aE:sub(aF,aF+3):gsub("\0+$","")
E(string.format(" algo:     %s",aG),d.fg)
E(string.format(" ctLen:    encrypted body inside this blob"),d.dim)
E(" (decrypt with the right passphrase to access contents)",d.dim)elseif av=="tape"then local aD=au[2]if aD~=I and aD~=ac then
E("Usage: vault tape encrypt|decrypt [passphrase | -]",d.dim)return end;local aE=b.tape;if not aE then
E("Tape module not installed (run `pkg install tape`).",d.warning)return end
local aF=az(au[3],aD==I)if not aF then return end;aE({aD,aF},E)else
E("Usage: vault [encrypt|decrypt|encrypt-in-place|decrypt-in-place|info|tape] ...",d.dim)
E("  vault encrypt <src> <dst> [passphrase]",d.dim)
E("  vault decrypt <src> <dst> [passphrase]",d.dim)
E("  vault encrypt-in-place <file> [passphrase]",d.dim)
E("  vault decrypt-in-place <file> [passphrase]",d.dim)E("  vault info <file>",d.dim)
E("  vault tape encrypt|decrypt [passphrase]",d.dim)
E("  Leave the passphrase off (or use -) to be asked for it, unechoed:",d.dim)
E("  a typed one stays in this seat's command history.",d.dim)end end
b.keychain=function(au,E)local av=_G._TOS and _G._TOS.keychain;if not av then
E("keychain module unavailable",d.error)return end;local aw=H.sessionOf(a)
local ax=au[1]or"status"
if ax=="status"then
E(av.isUnlocked(aw)and"unlocked"or"locked",d.fg)elseif ax=="unlock"then if not j then
E("interactive prompt unavailable",d.error)return end
local ay=j("Master password: ",64,"*")or""
if#ay==0 then E("(empty — cancelled)",d.dim)return end;local az,aA=av.unlock(ay,aw)if az then
E("Keychain unlocked.",d.highlight)else
E("Unlock failed: "..tostring(aA),d.error)end elseif ax=="lock"then av.lock(aw)
E("Keychain locked.",d.highlight)elseif ax=="list"then
if not av.isUnlocked(aw)then E(ae,d.warning)return end;local ay=av.list(aw)
if#ay==0 then E("(empty)",d.dim)return end;for aA,az in ipairs(ay)do E("  "..az,d.fg)end elseif ax=="set"then if not au[2]then
E("Usage: keychain set <name>",d.dim)return end;if not av.isUnlocked(aw)then
E("Keychain is locked. Run 'keychain unlock' first.",d.warning)return end;if not j then
E("interactive prompt unavailable",d.error)return end;local ay=
j("Passphrase for '"..au[2].."': ",256,"*")or""if#ay==0 then
E("(empty — cancelled)",d.dim)return end;local az,aA=av.set(au[2],ay,aw)if az then
E("Slot '"..
au[2].."' saved.",d.highlight)else
E("Save failed: "..tostring(aA),d.error)end elseif ax=="get"then if not au[2]then
E("Usage: keychain get <name>",d.dim)return end;if not av.isUnlocked(aw)then
E(ae,d.warning)return end;local ay,az=av.get(au[2],aw)if ay then
E(ay,d.fg)else
E(tostring(az or"no such slot"),d.error)end elseif ax=="remove"or ax=="rm"then if not au[2]then
E("Usage: keychain remove <name>",d.dim)return end;if not av.isUnlocked(aw)then
E(ae,d.warning)return end;local ay,az=av.remove(au[2],aw)
if ay then E("Removed '"..
au[2].."'.",d.highlight)else E(
"Remove failed: "..tostring(az),d.error)end else
E("Usage: keychain [status|unlock|lock|list|set|get|remove] ...",d.dim)end end
b.profile=function(au,E)local aw=_G._TOS and _G._TOS.profile;if not aw then
E(af,d.error)return end;local av=H.sessionOf(a)local ax=au[1]or"show"
if ax==
"show"then local ay,aA=aw.load(av)
E(string.format(" name:    %s",ay.name),d.title)
E(string.format(" theme:   %s",ay.theme or"(unset — uses `theme set` choice or default)"),d.fg)
E(string.format(" cwd:     %s",ay.cwd or"(unset)"),d.fg)
E(string.format(" prompt:  %s",ay.prompt or"(default)"),d.fg)local az=0;for aB in pairs(ay.env)do az=az+1 end
E(string.format(" env:     %d entries",az),d.fg)
E(string.format(" startup: %d commands",#ay.startup),d.fg)if not aA then
E(" (no profile file — showing defaults)",d.dim)end elseif ax=="set"then
if not au[2]or not au[3]then
E("Usage: profile set <field> <value>",d.dim)E("  fields: name, theme, cwd, prompt",d.dim)return end;local ay,az=au[2],au[3]local aA=aw.load(av)
if ay=="name"or ay=="theme"or
ay=="cwd"or ay=="prompt"then
if ay=="theme"then local aD=_G._TOS and
_G._TOS.theme
if
aD and aD.preset and not aD.preset(az)then E("Unknown theme preset: "..az,d.error)if aD.list then
E(
"Available: "..table.concat(aD.list(),", "),d.dim)end;return end end;aA[ay]=az;local aB,aC=aw.save(aA,av)
if aB then
E("Profile updated. Re-login to apply.",d.highlight)else E(tostring(aC or ag),d.error)end else E("Unknown field: "..ay,d.error)end elseif ax=="env"then if not au[2]then
E("Usage: profile env <KEY> [VALUE]",d.dim)return end;local ay=aw.load(av)if au[3]then
ay.env[au[2]]=au[3]E("env["..au[2].."] set",d.highlight)else ay.env[au[2]]=
nil
E("env["..au[2].."] cleared",d.highlight)end
aw.save(ay,av)elseif ax=="startup"then local az=au[2]or"list"local ay=aw.load(av)
if az=="add"then
local aA=table.concat(au," ",3)
if#aA==0 then E("Usage: profile startup add <cmd>",d.dim)return end;ay.startup[#ay.startup+1]=aA;aw.save(ay,av)
E("Added.",d.highlight)elseif az=="clear"then ay.startup={}aw.save(ay,av)
E("Startup commands cleared.",d.highlight)else for aA,aB in ipairs(ay.startup)do
E(string.format(" %d. %s",aA,aB),d.fg)end;if#ay.startup==0 then
E("(no startup commands)",d.dim)end end elseif ax=="reset"then local ay=_G._TOS and _G._TOS.securefs;if
ay and av and av.home and av.home~="/"then
ay.remove(av.home.."/.profile.cfg",av)end
E("Profile reset to defaults.",d.highlight)else
E("Usage: profile [show|set|env|startup|reset]",d.dim)end end
b.cp=function(E,au)
if not E[2]then au("Usage: cp <src> <dst>",d.dim)return end;local aw,av=f(E[1]),f(E[2])if e.isDirectory(av)then
av=e.join(av,aw:match(aa)or aw)end;local ax,ay=e.copy(aw,av)
if ax then k()
au("Copied: "..E[2],d.highlight)else au(ay or"Failed",d.error)end end
b.mv=function(au,E)
if not au[2]then E("Usage: mv <src> <dst>",d.dim)return end;local av,aw=f(au[1]),f(au[2])if e.isDirectory(aw)then
aw=e.join(aw,av:match(aa)or av)end;if not o(av,E)then return end
if not o(aw,E)then return end
if e.rename(av,aw)then k()E("Moved: "..au[2],d.highlight)else
local ax,ay=e.copy(av,aw)if ax and e.remove(av)then k()
E("Moved: "..au[2],d.highlight)else
E("Move failed: "..tostring(ay or"cross-fs copy failed"),d.error)end end end
b.find=function(E,au)local az="/"local ax=nil;local av=1
while av<=#E do if E[av]=="-name"and E[av+1]then
ax=E[av+1]av=av+2 else az=f(E[av])av=av+1 end end
if ax then local aE,aF=pcall(string.match,"",ax)if not aE then
au("Invalid pattern: "..tostring(aF),d.error)return end end;au("Searching "..az.." ...",d.dim)local aC=16
local ay=1000;local aw={}
local function aD(aE)if not g or not g.canAccessAs then return false end
local aF=H.sessionOf(a)local aG=g.canAccessAs(aF,aE,"r")return aG end
local function aB(aE,aF)if aF>aC then return end;if#aw>=ay then return end;if not aD(aE)then return end
local aI,aG=pcall(e.list,aE)if not aI or not aG then return end;local aH={}
if type(aG)=="table"then aH=aG elseif
type(aG)==Z then for aJ in aG do aH[#aH+1]=aJ end end
for aK,aJ in ipairs(aH)do if#aw>=ay then break end;O()
local aL=e.join(aE,aJ:gsub("/$",""))local aM=aJ:sub(-1)=="/"local aN=false;if ax then
local aO,aP=pcall(string.match,aL,ax)local aQ,aR=pcall(string.match,aJ,ax)
aN=(aO and aP)or(aQ and aR)else aN=true end;if aN then
aw[
#aw+1]={aL.. (aM and"/"or""),
aM and(d.dir or d.highlight)or d.fg}end;if
aM and not aL:match("^/tos")then aB(aL,aF+1)end end end;aB(az,0)if#aw==0 then au("No matches found",d.dim)else for aF,aE in ipairs(aw)do
au(aE[1],aE[2])end end;local aA=#aw..
" result(s)"if#aw>=ay then
aA=aA.." (truncated at "..ay..")"end;au(aA,d.dim)end
b.grep=function(au,E)
if not au[2]then E("Usage: grep <pattern> <file>",d.dim)return end;local ay=au[1]local ax=f(au[2])if not l(ax,E)then return end;local av=0;local aw=0
local az=H.eachLine(e,ax,function(aA)aw=
aw+1;if aA:find(ay,1,true)then
E(string.format("%4d: %s",aw,aA),d.fg)av=av+1 end end)if not az then E(K..au[2],d.error)return end
E(av>0 and
(av.." match(es)")or"No matches",d.dim)end
b.wc=function(E,au)
if not E[1]then au("Usage: wc <file>",d.dim)return end;local ax=f(E[1])if not l(ax,au)then return end;local av,aw=0,0
local ay,az=H.eachLine(e,ax,function(aA)av=av+1;for aB in
aA:gmatch("%S+")do aw=aw+1 end end)if not ay then au(K..E[1],d.error)return end
au(string.format(" Lines: %d  Words: %d  Bytes: %d  -- %s",av,aw,az,E[1]),d.fg)end;b.pwd=function(au,E)E(a.cwd or"/",d.fg)end
local function y(E)
local aw,av=nil,10;local au=1
while au<=#E do local ax=E[au]
if ax=="-n"and E[au+1]then
av=tonumber(E[au+1])or av;au=au+1 elseif ax:match("^%-%d+$")then av=tonumber(ax:sub(2))elseif not aw then aw=ax elseif
tonumber(ax)then av=tonumber(ax)end;au=au+1 end;return aw,av end
local function z(E,aw,au,av)if e.exists and not e.exists(aw)then
av("No such file: "..E,d.error)else
av("Cannot read "..E..
(au and(": "..tostring(au))or""),d.error)end end
b.head=function(au,E)local av,aw=y(au)if not av then E("Usage: head [-n N] <file>",d.dim)
return end;local ax=f(av)if not l(ax,E)then return end
local ay=0;if not aw or aw<1 then return end
local az,aA=H.eachLine(e,ax,function(aB)E(aB,d.fg)ay=ay+1;if ay>=aw then
return false end end)if not az then z(av,ax,aA,E)end end
b.tail=function(au,E)local ax,av=y(au)if not ax then E("Usage: tail [-n N] <file>",d.dim)
return end;local ay=f(ax)if not l(ay,E)then return end;if not av or
av<1 then return end;if av>1000 then av=1000 end;local az,aw={},0
local aA,aB=H.eachLine(e,ay,function(aC)
aw=aw+1;az[(aw-1)%av+1]=aC end)if not aA then z(ax,ay,aB,E)return end
for aC=math.max(1,aw-av+1),aw do E(az[
(aC-1)%av+1],d.fg)end end
b.which=function(au,E)
if not au[1]then E("Usage: which <name>",d.dim)return end;local av=au[1]:lower()local aw=false;local ay=H.aliases(a)
if ay[av]then
E(av..": alias for '"..
ay[av].."'",d.highlight)
E("  (expanded before dispatch; the expansion is resolved below)",d.dim)
av=tostring(H.tokenizeSimple(ay[av])[1]or av):lower()aw=true end;local aA=require(L)
local ax=aA.entry and aA.entry(av)or nil
if ax then local aF=ax.tier or 0
E(av..
": built-in (".. (ax.category or"?")..", needs "..
H.tierName(aF)..")",d.title)if ax.help then E("  "..ax.help,d.fg)end;if
aF>H.liveTier(a)then
E("  You do not have the tier to run it — 'why "..av.."'.",d.warning)end;aw=true end;local aD,az=pcall(require,R)
local aB=aD and az and az.ownerOfCommand and
az.ownerOfCommand(av)or nil
if aB then
E(av..": package command from '"..aB.."'",ax and d.dim or d.title)
if ax then E("  (shadowed by the built-in above)",d.dim)end;aw=true end;local aC,aE=H.resolveProgram(e,av)
if aC then
E(av..": "..aC..
(aE=="path"and"  (via PATH)"or""),aw and d.dim or
d.title)
if aw then E("  (shadowed by the entry above)",d.dim)end;aw=true end
if not aw then E(av..": not found",d.error)
E("  Not a built-in, an installed package's command, or a program on",d.dim)
E("  /bin, /usr/bin or /tos/shell. 'help' lists what this box has.",d.dim)end end
local function an(E)local au=require(L)
if au.entry and au.entry(E)then return true end;if H.mayHavePackages()then local aw,av=pcall(require,R)
if
aw and av and av.ownerOfCommand and av.ownerOfCommand(E)then return true end end;return
H.resolveProgram(e,E)~=nil end
b.open=function(au,E)local av=require("shell.open")local aA=H.sessionOf(a)
local ay=aA and aA.home;local aw=au[1]
local function ax()
E("Usage: open <file>                    in the program that suits it",d.dim)
E("       open with <file> [program]     every program that could, and why",d.dim)
E("       open set .<ext> <program> [--system]   choose (--system: every user)",d.dim)
E("       open unset .<ext> [--system]   forget the choice",d.dim)
E("       open list                      the choices and what packages declare",d.dim)
E("       open hints on|off              edit's suggestions",d.dim)end;if not aw then ax()return end;local function aB(aE)if aE then return av.SYSTEM_FILE end
return ay and(ay..
"/"..av.USER_FILE)or nil end
local function aC(aE)
local aF,aG=pcall(e.exists,aE)return
av.parseDefaults(aF and aG and e.readFile(aE)or nil)end
local function az(aE,aF)
local aG,aH=e.writeFile(aE,av.serializeDefaults(aF))if not aG then
E("Not saved: "..tostring(aH or aE),d.error)end;return aG end
local function aD(aE,aF)if not a.execOne then
E("open: the executor is unavailable",d.error)return end;local aG=a.execOne(aE.." "..av.quote(aF),
nil,true)for aI,aH in ipairs(aG or{})do
E(aH[1],aH[2])end end
if aw=="set"or aw=="unset"then local aH=au[#au]==S
local aE=(au[2]or""):gsub("^%.",""):lower()if
aE==""or not aE:match("^[%w]+$")or#aE>8 then ax()return end;if aH and not r(E)then return end
local aF=aB(aH)if not aF then
E("There is no home directory to keep your choice in.",d.error)return end;local aG=aC(aF)
if aw=="set"then local aI=au[3]and
au[3]:lower()if not aI or aI==S then ax()return end;if
not an(aI)then
E("'"..
aI.."' is not a command this machine has ('which "..aI.."').",d.error)return end;aG.ext[aE]=aI;if
az(aF,aG)then
E("."..
aE.." files now open in "..aI..
(aH and" for every user."or" for you."),d.highlight)end else aG.ext[aE]=nil;if
az(aF,aG)then
E("."..aE..": back to the ranking.",d.highlight)end end elseif aw=="hints"then local aE=aB(false)if not aE or
(au[2]~="on"and au[2]~="off")then ax()return end;local aF=aC(aE)aF.hints=(
au[2]=="on")if az(aE,aF)then
E("edit's suggestions are "..au[2]..".",d.highlight)end elseif aw=="list"then
local aE=av.gather(e,ay,nil,"")
local function aF(aH,aG)local aI={}for aJ in pairs(aG.ext)do aI[#aI+1]=aJ end
table.sort(aI)
E(aH.. (#aI==0 and"  (none)"or""),d.title)for aK,aJ in ipairs(aI)do
E(string.format("  .%-8s %s",aJ,aG.ext[aJ]),d.fg)end end
aF("Your choices (~/"..av.USER_FILE.."):",aE.user)
aF("This machine's ("..av.SYSTEM_FILE.."):",aE.system)
E("What installed packages open:"..
(#aE.decls==0 and"  (none)"or""),d.title)
for aH,aG in ipairs(aE.decls)do local aI={}
for aK in pairs(aG.exts)do aI[#aI+1]="."..aK end;table.sort(aI)
local aJ=aG.markers and
("when a line starts "..table.concat(aG.markers," "))or(aG.as=="native"and"its own format"or
"can open")
E(string.format("  %-8s %s  %s",aG.cmd,table.concat(aI," "),aJ),d.fg)end;if aE.user.hints==false then
E("edit's suggestions are off ('open hints on').",d.dim)end else local aG=aw=="with"
local aH=aG and au[2]or aw;if not aH then ax()return end;local aE=f(aH)local aJ,aK=pcall(e.exists,aE)if not aJ or
not aK then E("open: no such file: "..aE,d.error)
return end;if
e.isDirectory and e.isDirectory(aE)then
E("open: "..aE.." is a directory ('cd' into it).",d.error)return end
local aF=av.rank(aE,av.gather(e,ay,aE))
if aG and not au[3]then if#aF==0 then
E("Nothing here opens "..aE..".",d.warning)return end
E("Programs that could open "..aE..", best first:",d.title)for aM,aL in ipairs(aF)do
E(string.format("  %-8s %3d  %s",aL.cmd,aL.score,aL.why),aM==1 and
d.highlight or d.fg)end
E("'open with "..aH..

" <program>' uses another; 'open set .".. (av.ext(aE)or"ext").." <program>' makes it yours.",d.dim)return end
local aI=aG and au[3]:lower()or(aF[1]and aF[1].cmd)if not aI then
E("Nothing here opens "..aE.." ('open with' lists what could).",d.warning)return end;if not aG then
E("Opening in "..aI..": "..aF[1].why..
".",d.dim)end;aD(aI,aE)end end
b.alias=function(au,E)local ax=_G._TOS and _G._TOS.profile;if not ax then E(af,d.error)
return end;local ay=H.sessionOf(a)
if not au[1]then local aE=ax.load(ay)
local aD={}for aF in pairs(aE.aliases or{})do aD[#aD+1]=aF end
table.sort(aD)if#aD==0 then E("(no aliases)",d.dim)
E("Define one:  alias ll ls -l",d.dim)return end;for aG,aF in ipairs(aD)do
E(string.format(" %-12s %s",aF,aE.aliases[aF]),d.fg)end;return end;local av=au[1]:lower()if not av:match("^[%w_%-]+$")then E("Bad alias name: "..
au[1],d.error)
E("Letters, digits, underscore and hyphen only.",d.dim)return end
local aw=ax.load(ay)
if not au[2]then
if aw.aliases and aw.aliases[av]then
E(string.format(" %-12s %s",av,aw.aliases[av]),d.fg)else E(av..": not aliased",d.dim)end;return end;local az=table.concat(au," ",2)
local aA=tostring(H.tokenizeSimple(az)[1]or""):lower()if aA==av then E("An alias cannot expand to itself.",d.error)
E("To add default flags, alias to a different name.",d.dim)return end;aw.aliases=
aw.aliases or{}aw.aliases[av]=az;local aB,aC=ax.save(aw,ay)
if
not aB then E(tostring(aC or ag),d.error)return end;H.invalidateAliases(a)
E("alias "..av.." -> "..az,d.highlight)end
b.unalias=function(au,E)local ax=_G._TOS and _G._TOS.profile;if not ax then
E(af,d.error)return end;if not au[1]then
E("Usage: unalias <name>",d.dim)return end;local ay=H.sessionOf(a)
local av=au[1]:lower()local aw=ax.load(ay)
if not aw.aliases or not aw.aliases[av]then E(
av..": not aliased",d.dim)return end;aw.aliases[av]=nil;local az,aA=ax.save(aw,ay)if not az then
E(tostring(aA or ag),d.error)return end;H.invalidateAliases(a)E("Removed alias '"..
av.."'.",d.highlight)end
b.du=function(au,E)local av=f(au[1]or(a.cwd or"/"))
if not l(av,E)then return end;local function ax(ay,az)return
ay:sub(-1)=="/"and(ay..az)or(ay.."/"..az)end
local function aw(ay)
if
e.isDirectory(ay)then local az,aA=0,e.list(ay)
if type(aA)=="table"then for aC,aB in ipairs(aA)do O()az=az+
aw(ax(ay,aB:gsub("/$","")))end end;return az end;return(e.size and e.size(ay))or 0 end
if e.isDirectory(av)then local ay=e.list(av)
if type(ay)=="table"then for aA,az in ipairs(ay)do
local aB=az:gsub("/$","")
E(string.format(" %8s  %s",m(aw(ax(av,aB))),aB),d.fg)end end end
E(string.format(" %8s  %s (total)",m(aw(av)),av),d.title)end
b.df=function(au,E)local ax,av=pcall(require,"kernel.monitor")
E(string.format(" %-16s %8s %8s %8s  %s","Mount","Total","Used","Free","Use%"),d.title)
E(string.rep("-",math.min(q,56)),d.dim)local aw=e.mounts and e.mounts()or{}
if#aw==0 then
E("(mount info unavailable)",d.dim)else
for az,ay in ipairs(aw)do local aA=ay.total or 0;local aB=ay.used or 0;local aD=aA-aB
local aC=aA>0 and math.floor(
aB*100/aA)or 0
local aE=(ax and av.memBar)and av.memBar(aB,aA,8)or""
local aF=aC<80 and d.fg or(aC<95 and d.warning or d.error)
E(string.format(" %-16s %8s %8s %8s  [%s] %3d%%",(ay.mountPoint or"?"):sub(1,16),m(aA),m(aB),m(aD),aE,aC),aF)end end
if _G._TOS_ROOT_READONLY then E("",d.dim)
E("WARNING: the root filesystem is READ-ONLY.",d.error)
E("Nothing TOS writes will survive a reboot — users, logs, packages,",d.dim)
E("settings. Install to a writable drive, or unprotect this one.",d.dim)end
E("A path's own size: 'du <path>'.  Removable media + pools: 'disk'.",d.dim)end
b.mem=function(au,E)
if au and au[1]=="--boot"then
local aH=_G._TOS and _G._TOS.bootMem
if type(aH)~="table"or#aH==0 then
E("This boot was not profiled.",d.warning)
E("Add  memprofile = true  to /etc/boot.cfg and reboot.",d.dim)return end;E("=== Memory each boot stage used ===",d.title)
for aJ,aI in
ipairs(aH)do local aK=aH[aJ+1]
if aK then
E(string.format(" %-30s %4dK  (%dK free after)",tostring(aI.stage),math.floor((
(aI.free or 0)- (aK.free or 0))/1024),math.floor((
aK.free or 0)/1024)),d.fg)else
E(string.format(" %-30s %5dK free",tostring(aI.stage),math.floor((aI.free or 0)/1024)),d.dim)end end;return end;local az,av=M.freeMemory(),M.totalMemory()local aA=av-az;local aw=av>0 and math.floor(
aA*100/av)or 0
local aD,aC=pcall(require,"kernel.monitor")local ay=math.min(24,math.max(8,q-36))
local aE=
(aD and aC.memBar)and aC.memBar(aA,av,ay)or
(
string.rep("#",math.floor(aw/100*ay))..string.rep("-",ay-math.floor(aw/100*ay)))E("=== Memory ===",d.title)
E(string.format(" RAM:  %dK used / %dK total   (%d%% used, %dK free)",math.floor(
aA/1024),math.floor(av/1024),aw,math.floor(az/1024)),d.fg)
local aF=aw<75 and d.highlight or(aw<90 and d.warning or d.error)E(" ["..aE.."]",aF)
local aG,ax=pcall(function()
return h.getHAL().systemInfo()end)if aG and ax and(ax.memTierName or ax.memTier)then
E(
" Tier: ".. (ax.memTierName or("T"..ax.memTier)),d.dim)end
local aB=h.getSwap and h.getSwap()
if aB and aB.usage then local aI,aH=pcall(aB.usage)
if aI and type(aH)=="table"then
E(string.format(" Swap: %dK / %dK on /var/swap   ('slow RAM' overflow)",math.floor((
aH.bytes or 0)/1024),math.floor((aH.max or 0)/1024)),d.dim)end else
E(" Swap: off   (enable in Boot Settings for low-RAM overflow)",d.dim)end;if az<16*1024 then
E(" ! Low memory — near the ~16K danger zone.",d.warning)end
E("Live usage: 'monitor'.  Hardware tiers: 'hw'.",d.dim)end
b.hw=function(au,E)local av=h.getHAL().systemInfo()
E("=== Hardware ===",d.title)
E(string.format(" CPU T%d    GPU T%d    RAM %s",av.cpuTier or 0,av.gpuTier or 0,av.memTierName or("T"..
(av.memTier or 0))),d.fg)local ax,aw=pcall(require,"kernel.datacard")if
ax and aw and aw.detect then local ay=aw.detect()
E(" Data card: "..
(ay.present and ay.name or"none"),ay.present and d.fg or d.dim)end
E(string.format(" Components: %d    Network: %s    Tunnel: %s",
av.components or 0,av.canNetwork and"yes"or"no",av.hasTunnel and"yes"or"no"),d.dim)
E("Full component list: 'devices'.  Memory detail: 'mem'.  Live: 'monitor'.",d.dim)end;b.hardware=b.hw
b.ps=function(au,E)local ay=u.getForeground(a.displayIdx)
local av=H.sessionOf(a)local aw=(av and av.tier)or 0
local az=av and av.user or"?"
local ax=(au[1]=="-v"or au[1]=="--verbose")and aw>=2
if ax then
E(string.format(" %-4s %-14s %-8s %-3s %-10s %-6s %s","PID","Name","State","DSP","Owner","CPU","Caps"),d.title)else
E(string.format(" %-4s %-16s %-8s %-3s %-10s %s","PID","Name","State","DSP","Owner","CPU"),d.title)end
E(string.rep("-",ax and 70 or 50),d.border)
for aB,aA in ipairs(u.list())do local aC=aA.user or"?"
if aC=="_kernel_"then aC="kernel"end;local aD=false
if aw>=2 then aD=true elseif aw>=1 and aC==az then aD=true elseif aw>=1 then aD="redacted"end
if aD==true then local aF=d.fg;local aE=aA.state;if aA.tsr then aE="TSR"end;if aA.pid==ay then
aF=d.highlight;aE=aE.." *"elseif aA.tsr then aF=d.dim end
if ax then local aG={}if
aA.caps then for aH in pairs(aA.caps)do aG[#aG+1]=aH end
table.sort(aG)end
E(string.format(" %-4d %-14s %-8s %-3s %-10s %-6.1f %s",aA.pid,aA.name:sub(1,14),aE,tostring(
aA.display or"-"),(aC):sub(1,10),aA.cpuTime or 0,#aG>0 and
table.concat(aG,",")or"-"),aF)else
E(string.format(" %-4d %-16s %-8s %-3s %-10s %.1fs",aA.pid,aA.name:sub(1,16),aE,tostring(aA.display or"-"),(aC):sub(1,10),
aA.cpuTime or 0),aF)end elseif aD=="redacted"then
E(string.format(" %-4d %-16s %-8s %-3s %-10s   ",aA.pid,"(other user)","?","?","?"),d.dim)end end;E("",d.dim)
E(" * = foreground  |  -v for caps (admin+)  |  'monitor' for the live view",d.dim)end
b.monitor=function(au,E)local aw,av=pcall(require,"shell.panels.monitorapp")if not aw then
E(
"Monitor unavailable: "..tostring(av),d.error)return end;av.open(a)end;b.top=b.monitor
b.watch=function(au,E)
if not au[1]then
E("Usage: watch [seconds] <command ...>",d.dim)
E("  Opens a self-updating tab. e.g.  watch ps  ·  watch 2 df  ·  watch mem",d.dim)return end;local ax,av=1,tonumber(au[1])if av then ax=2 else av=1 end;if av<1 then av=1 end;if not
au[ax]then E("Usage: watch [seconds] <command ...>",d.dim)
return end
local ay=table.concat(au," ",ax)
local aw=(ay:match("^(%S+)")or""):lower()
local az={edit=true,lua=true,monitor=true,top=true,watch=true,launcher=true,launch=true,apps=true,kiosk=true,chat=true,more=true,man=true,vault=true,keychain=true,passwd=true,tutorial=true,bootsettings=true,useradd=true,["tape-auth"]=true}if az[aw]then
E("Can't watch '"..aw.."' — it's interactive/screen-driven.",d.error)return end;do
local aB,aC,aD=H.tierRefusal(a,aw)
if aB then E(aB,d.error)a.lastDenial={cmd=aw,need=aC,have=aD}return end end;if not c.openLiveTab then
E("Live tabs aren't available in this shell.",d.error)return end
local function aA()local aB={}local aC={}for aK in
ay:gmatch("%S+")do aC[#aC+1]=aK end;if#aC==0 then return aB end
local aD=aC[1]:lower()local aF={}for aK=2,#aC do aF[#aF+1]=aC[aK]end
local aG=H.tierRefusal(a,aD)if aG then aB[#aB+1]={aG,d.error}return aB end;local aE=b[aD]
if
not aE then local aL,aK=pcall(require,R)if aL and aK and aK.getCommand then
aE=aK.getCommand(aD)end end;if not aE then
aB[#aB+1]={"Unknown command: "..aD.."  [E-801 ERR_UNKNOWN_CMD]",d.error}return aB end
local aH=function(aK,aL)aB[#aB+1]={tostring(aK),
aL or d.fg}end;local aI,aJ=pcall(aE,aF,aH)if not aI then
aB[#aB+1]={"Error: "..tostring(aJ),d.error}end;return aB end;c.openLiveTab("watch: "..ay,aA,av)end
b.why=function(au,E)local aB=require(L)local ax=H.liveTier(a)
local av={title=d.title or d.highlight or d.fg,ok=
d.success or d.highlight or d.fg,err=d.error,fix=d.highlight or d.fg,dim=d.dim}local function aw(aC)
for aE,aD in ipairs(aC)do E(aD.text,av[aD.tone]or d.fg)end end
local ay=au and au[1]and au[1]:lower()
if not ay then local aC=a.lastDenial
if aC and aC.cmd then
aw(H.whyExplain(aC.cmd,aC.need,aC.have or ax,true))return elseif aC then
E("Your last blocked action needed "..H.tierName(aC.need).."; you are "..
H.tierName(aC.have or ax)..".",d.error)
E("Fix: run it on an admin/root account, or have an admin grant access.",av.fix)return end;local aD=a.lastFailure
if aD then
E((aD.cmd and(aD.cmd.." failed:")or
"The last action failed:"),av.title)E("  "..aD.text,d.error)
local aE,aG,aF=H.explainFailure(aD.text)if aF then E("  "..aF,av.dim)end
if aE then aw(aE)else
E("No canned explanation for that one.",d.dim)
E("`log` has the kernel's own record of it, and `doctor` checks",d.dim)
E("memory, disks, services and security for a cause.",d.dim)end;return end
E("Nothing has failed since the last command ran.",d.dim)
E("why            — explain the last refusal or error.",d.dim)
E("why <code>     — explain an error code: E-402, ERR_PATH_PROTECTED, K4.",d.dim)
E("why <command>  — explain what a command needs and whether you can run it.",d.dim)return end;local aA=H.explainCode(au[1])if aA then aw(aA)return end
local az=aB.entry(ay)
aw(H.whyExplain(ay,az and az.tier or 0,ax,az~=nil))end
b.screendump=function(au,E)if not n or not n.dump then
E("Screen capture isn't available on this seat.",d.error)return end
local aC,ax=pcall(n.dump)if not aC or type(ax)~="table"or not ax.lines then
E("Screen capture failed.",d.error)return end
local az=(au and au[1])and
f(au[1])or
f("screen-"..math.floor(h.uptime())..".txt")
local aD=(H.sessionOf(a)or{}).user or"?"
local aB=string.format("TOS screendump — seat %s · user %s · %dx%d · uptime %ds · read from the %s",tostring(a.displayIdx or"?"),aD,
ax.w or 0,ax.h or 0,math.floor(h.uptime()),tostring(ax.source or"?"))local av=string.char(10)local aw=aB..
av..string.rep("-",#aB)..av..
table.concat(ax.lines,av)..av
if ax.bg then
aw=aw..av..
"--- background colour runs, per row ---"..av
for aH=1,(ax.h or 0)do local aI=ax.bg[aH]
if aI then local aJ={}for aL,aK in ipairs(aI)do
aJ[#aJ+1]=string.format("%d-%d:%s",aK.from,aK.to,
aK.c and string.format("%06X",aK.c)or"nil")end
aw=aw..
string.format("row %2d  %s",aH,table.concat(aJ,"  "))..av end end;local aG=a.T or{}
aw=aw..
av..
"theme: bg="..
string.format("%06X",aG.bg or 0)..
"  statusbar_bg="..string.format("%06X",
aG.statusbar_bg or 0)..
"  menubar_bg="..string.format("%06X",
aG.menubar_bg or aG.bar_bg or 0)..av end;local ay=function(aG)
return aG and string.format("%06X",aG)or"nil"end;aw=aw..av..
"--- cache vs glass ---"..av
if
ax.disagree and#ax.disagree>0 then
aw=aw.."THE SHADOW DISAGREES WITH THE SCREEN on "..#ax.disagree..
" row(s)."..av
for aH,aG in ipairs(ax.disagree)do
aw=aw..
string.format("  row %2d col %2d  glass=%s  shadow believes=%s",aG.row,aG.col,ay(aG.glass),ay(aG.shadow))..av;local aI=ax.pageBg and ax.pageBg[aG.row]
if aI then local aJ={}for aH,aK in
ipairs(aI)do
aJ[#aJ+1]=string.format("%d-%d:%s",aK.from,aK.to,ay(aK.c))end
aw=aw.."    off-screen page holds: "..
table.concat(aJ,"  ")..av end end elseif ax.shadowBg then
aw=aw.."none — the shadow matches the glass everywhere."..av else
aw=aw.."(no shadow active on this seat)"..av end;local i=ax.state
if i then
aw=aw..
av..
"--- display machinery ---"..
av..
"  shadow="..
tostring(i.shadow)..
"  colour cache: fg="..

ay(i.lastFg)..
" bg="..
ay(i.lastBg)..
av..
"  backbuffer="..
tostring(i.backbuffer)..
"  broken="..
tostring(i.backBroken)..

"  frameDepth="..
tostring(i.frameDepth)..
"  pageStale="..
tostring(i.pageStale)..av..
"  writerGen="..
tostring(i.writerGen)..
"  mine="..tostring(i.myWriterGen).."  lastWriterIsMe="..
tostring(i.lastWriterIsMe)..av end;local aA=_G._TOS and _G._TOS.fs;if
not(aA and aA.writeFile)then
E("No filesystem available to write the dump.",d.error)return end
local aE,aF=aA.writeFile(az,aw)
if aE then
E("Screen captured -> "..az.."  (".. (ax.h or 0).." rows)",
d.success or d.fg)
E("Attach it to a bug report, or 'cat' it to read it back.",d.dim)else
E("Could not write "..az..": "..tostring(aF),d.error)end end
b.crash=function(au,E)if not r(E)then return end;local av=_G._TOS and _G._TOS.fs
if not
(av and av.list)then E("No filesystem.",d.error)return end
if au and au[1]then local az=au[1]:find("/")and f(au[1])or
("/var/crash/"..au[1])
local aB,aA=pcall(av.readFile,az)if not aB or not aA then
E("No such crash report: "..az,d.error)return end;for aC in
(tostring(aA).."\n"):gmatch("(.-)\n")do E(aC,d.fg)end;return end;local ay,ax=pcall(av.list,"/var/crash")local aw={}if
ay and type(ax)=="table"then
for aA,az in ipairs(ax)do az=tostring(az):gsub("/$","")if
az~=""and az~="NEW"then aw[#aw+1]=az end end end
if#aw==0 then
E("No crash reports — clean so far.",d.dim)
E("(TOS saves one here on a panic or an unrecoverable shell, so you",d.dim)E(" can read it after rebooting.)",d.dim)return end
E("Crash reports in /var/crash:",d.title or d.highlight or d.fg)for aA,az in ipairs(aw)do E("  "..az,d.fg)end
E("Read one with:  crash <name>",d.dim)end
b.history=function(au,E)for av,aw in ipairs(a.cmdHistory)do
E(string.format(" %3d  %s",av,aw),d.dim)end;if#a.cmdHistory==0 then
E("(no history)",d.dim)end end
b.uptime=function(au,E)local av=h.uptime()local aw=math.floor(av/3600)local ax=math.floor(
(av%3600)/60)local ay=math.floor(av%60)
E(string.format("Uptime: %dh %dm %ds (%.1fs total)",aw,ax,ay,av),d.fg)end
b.date=function(au,E)
local av=h.getConfig and h.getConfig()or nil
if au[1]=="tz"or au[1]==T or au[1]=="set"then local aC=(av and av.get and
av.get(T))or 0
local aB=tonumber(au[2])
if not aB then E("Timezone offset: "..aC.."h",d.fg)
E("Usage: date tz <hours>   e.g. 'date tz -5'",d.dim)
E("OpenComputers has no settable clock; this only shifts the",d.dim)
E("DISPLAYED time relative to the world/host clock.",d.dim)return end;if aB<-23 or aB>23 then
E("Offset must be between -23 and 23.",d.error)return end;if not r(E)then return end
if not
(av and av.set)then E("No writable config available.",d.error)return end;av.set(T,aB)if av.save then av.save()end
E("Timezone offset set to "..aB.."h. (was "..
aC.."h)",d.highlight)return end;local ax=au[1]or"%Y-%m-%d %H:%M:%S"local ay=
(av and av.get and av.get(T))or 0
local az=os.time()+ (ay*3600)local aA,aw=pcall(os.date,ax,az)if aA and aw then
E(tostring(aw),d.fg)else
E(tostring(aw or"date error"),d.error)end end;b.time=b.date
b.keys=function(au,E)local aD,av=pcall(require,X)if not aD or not av then
E("Keybind module unavailable.",d.error)return end
local aw=(au[1]or"list"):lower()local ax=false;for aF=2,#au do
if au[aF]==S then ax=true;table.remove(au,aF)break end end
local aE=(a.who=="root")and"/root"or(
"/home/".. (a.who or""))
local az=ax and"/etc/keys.cfg"or(aE.."/.keys.cfg")local aB,ay=pcall(require,"kernel.serialize")
local function aC()
if not(aB and ay and
a.F.exists(az))then return{}end;local aF=a.F.readFile(az)if not aF then return{}end
local aH,aG=pcall(ay.decode,aF,{maxBytes=8192})return
(aH and type(aG)=="table")and aG or{}end
local function aA(aF)if not(aB and ay)then return false end
local aG=a.F.writeFile(az,ay.encode(aF))if aG then av.reload()end;return aG end
if aw=="list"or aw=="ls"then
E("TOS standard shortcuts:",d.title)for aG,aF in ipairs(av.actions(a.who))do
E(string.format("  %-9s %-14s %s",aF.action,aF.keys,aF.help),
aF.isDefault and d.fg or d.highlight)end
E("",d.dim)
E("Reserved by the kernel — these cannot be rebound:",d.dim)for aG,aF in ipairs(av.reserved())do
E(string.format("  %-9s %s",aF.key,aF.help),d.dim)end;E("",d.dim)
E("Change one:  keys set quit F4       (add --system for everyone)",d.dim)E("Undo:        keys reset [action]",d.dim)
E("Every first-party TOS program follows this table.",d.dim)elseif aw=="set"then local aF,aI=au[2],au[3]
if not(aF and aI)then
E("Usage: keys set <action> <key> [<key>...]",d.dim)
E("  e.g. keys set quit F4      keys set find ^F",d.dim)
E("Key names are written the way you say them: ^Q, F10, Ctrl+S, /",d.dim)return end;if not av.DEFAULTS[aF]then
E("No such action: "..aF.."  (see 'keys list')",d.error)return end;local aG={}
for aJ=3,#au do local aK=au[aJ]if not
av.parse(aK)then
E("Not a key name: '"..aK.."'  (try ^Q, F10, Ctrl+S, /)",d.error)return end
if av.isReserved(aK)then
E(aK..
" is reserved by the kernel and never reaches a program.",d.error)E("See 'keys list' for the reserved set.",d.dim)return end;aG[#aG+1]=aK end;local aH=aC()aH[aF]=aG
if aA(aH)then
E(aF..
" is now "..table.concat(aG," ").. (ax and"  (machine-wide)"or
""),d.highlight)else E(ah.. (ax and U or"."),d.error)end elseif aw=="reset"then local aF=au[2]local aG=aC()
if aF then if not av.DEFAULTS[aF]then
E("No such action: "..aF,d.error)return end;aG[aF]=nil;if aA(aG)then
E(aF.." is back to the default.",d.highlight)else E(ai,d.error)end else if aA({})then
E("All shortcuts back to the defaults.",d.highlight)else E(ai,d.error)end end else
E("keys — TOS's standard keyboard shortcuts",d.title)
E("  keys list                     Show them",d.fg)
E("  keys set <action> <key>...    Rebind one",d.fg)
E("  keys reset [action]           Back to the default",d.fg)
E("Add --system to change them for every user (/etc/keys.cfg, admin).",d.dim)end end
b.menu=function(au,E)local av=(au[1]or"list"):lower()local ax=false
for aF=2,#au do if
au[aF]==S then ax=true;table.remove(au,aF)break end end;local aD=(a.who=="root")and"/root"or
("/home/".. (a.who or""))local aw=
ax and"/etc/menu.cfg"or(aD.."/.menu.cfg")
local aE,aB=pcall(require,"kernel.serialize")
if not aE or not aB then E("serialize unavailable",d.error)return end
local function ay()if not a.F.exists(aw)then return{}end
local aF=a.F.readFile(aw)if not aF then return{}end
local aH,aG=pcall(aB.decode,aF,{maxBytes=8192})return
(aH and type(aG)=="table")and aG or{}end
local function az(aF)return a.F.writeFile(aw,aB.encode(aF))end;local function aA()local aG,aF=pcall(require,"shell.panels.draw")
if
aG and aF and aF.buildMenuDefs then a.menuDefs=aF.buildMenuDefs(a)end end
local function aC(aF)if
aF.remove then
return"remove "..tostring(aF.remove)..
(aF.menu==true and" (whole menu)"or"")end;if aF.rename then return
"rename "..
tostring(aF.rename).." -> "..tostring(aF.to)end;if
aF.move then return
"move "..tostring(aF.move).." -> "..tostring(aF.menu)end
if aF.menu and not
aF.cmd then return"new menu "..tostring(aF.menu)end;return
string.format("[%s] %s -> %s",aF.menu or"Tools",aF.add or aF.label or"?",aF.cmd or"?")end
if av=="list"or av=="ls"then local aF=ay()
if#aF==0 then
E("No menu edits in "..aw..".",d.dim)
E("Add one:  menu add <label> <command...> [in <Menu>]",d.dim)
E("Machine-wide instead of just you:  menu add ... --system",d.dim)return end;E("Menu edits ("..aw.."):",d.title)for aG,aH in ipairs(aF)do
E(string.format("  %d. %s",aG,aC(aH)),d.fg)end elseif av=="show"then
local aG,aF=pcall(require,"shell.panels.draw")if not aG or not aF or not aF.buildMenuDefs then
E("Menu system unavailable.",d.error)return end
for aI,aH in
ipairs(aF.buildMenuDefs(a))do E(aH.label,d.title)
for aI,aJ in ipairs(aH.items)do if aJ.sep then E("    ---",d.dim)else
E(string.format("    %-20s %s",aJ.label,(
aJ.action or""):match("^run:(.+)$")or(aJ.action or"")),d.fg)end end end
E("Change it with: menu add|remove|rename|move  (add --system for everyone)",d.dim)elseif av==aj or av=="move"then local aG,aH=au[2],au[3]if not(aG and aH)then
E("Usage: menu "..av..

" <name> <".. (av==aj and"new name"or"Menu")..">",d.dim)return end;local aF=ay()
aF[#aF+1]=(
av==aj)and{rename=aG,to=aH}or{move=aG,menu=aH}
if az(aF)then aA()
E("Saved. "..aC(aF[#aF]),d.highlight)else E(ah.. (ax and U or"."),d.error)end elseif av=="hide"then local aF=au[2]if not aF then
E("Usage: menu hide <item or Menu name>",d.dim)
E("Hides a built-in entry. 'menu reset' brings everything back.",d.dim)return end
local aG=ay()
aG[#aG+1]={remove=aF,menu=(au[3]=="menu")or nil}
if az(aG)then aA()E("Hidden: "..aF,d.highlight)else E(ah..
(ax and U or"."),d.error)end elseif av=="reset"then if az({})then aA()
E("Menu reset to the built-in bar ("..aw.." cleared).",d.highlight)else
E("Reset failed".. (ax and U or"."),d.error)end elseif
av=="add"then local aG=au[2]
if not aG or not au[3]then
E("Usage: menu add <label> <command...> [in <Menu>]",d.dim)
E("  e.g. menu add Tetris tetris   |   menu add Disk df in System",d.dim)return end;local aF=table.concat(au," ",3)
local aH=aF:match("%s+in%s+(%S+)%s*$")if aH then aF=aF:gsub("%s+in%s+%S+%s*$","")end
if
#aG>24 then E("Label too long (max 24).",d.error)return end;if#aF==0 or#aF>200 then
E("Command empty or too long.",d.error)return end;local aI=ay()
aI[#aI+1]={label=aG,cmd=aF,menu=aH or"Tools"}
if az(aI)then aA()
E(string.format("Added '%s' -> %s  (menu: %s)",aG,aF,aH or"Tools"),d.highlight)else E("Save failed (is your home writable?).",d.error)end elseif av=="remove"or av=="rm"or av=="del"then
local aF=tonumber(au[2])local aG=ay()if not aF or not aG[aF]then
E("Usage: menu remove <#>   (see 'menu list')",d.error)return end
local aH=table.remove(aG,aF)if az(aG)then aA()
E("Removed '".. (aH.label or"?").."'.",d.highlight)else E(ai,d.error)end else
E("menu — adjust the menu bar",d.title)
E("  menu show                     The bar as it is right now",d.fg)
E("  menu list                     Your edits to it",d.fg)E("  menu add <label> <cmd...> [in <Menu>]",d.fg)
E("  menu hide <item|Menu> [menu]  Hide a built-in entry",d.fg)
E("  menu rename <name> <new>      Rename a menu or an item",d.fg)
E("  menu move <item> <Menu>       Move an item to another menu",d.fg)
E("  menu remove <#>               Undo one of your edits",d.fg)
E("  menu reset                    Back to the built-in bar",d.fg)
E("Add --system to any of these to change the bar for EVERY user",d.dim)
E("(/etc/menu.cfg, admin-only) instead of just yourself.",d.dim)end end
b.tree=function(au,E)local ax=f(au[1]or a.cwd)
local aA=tonumber(au[2])or 3;local ay=400;local av,aw=0,false
local function az(aB,aC,aD)if aw then return end;if aD>aA then return end
local aE=e.list(aB)or{}
table.sort(aE,function(aF,aG)
local aH=e.isDirectory(aB.."/".. (aF:gsub("/$","")))
local aI=e.isDirectory(aB.."/".. (aG:gsub("/$","")))if aH~=aI then return aH end;return aF<aG end)
for aF,aG in ipairs(aE)do if av>=ay then aw=true;return end;local aH=aG:gsub("/$","")
local aJ=aB=="/"and(
"/"..aH)or(aB.."/"..aH)local aI=e.isDirectory(aJ)local aK=(aF==#aE)
local aL=aK and"`-- "or"|-- "local aM=aI and d.dir or d.fg;E(aC..
aL..aH.. (aI and"/"or""),aM)av=av+1;if aI then
az(aJ,aC.. (aK and"    "or
"|   "),aD+1)end end end;E(ax,d.title)az(ax,"",1)if aw then
E(string.format("(truncated at %d entries; raise the limit or narrow the path)",ay),d.dim)end end
b.whoami=function(au,E)if g then local av=g.getSession(i)
E(av and av.user or"root",d.fg)else E(a.who,d.fg)end end
b.passwd=function(au,E)
if not g then E("No user system",d.error)return end;local ax=j("Current password: ",64,true)if not ax then return end
local av=j("New password: ",64,true)if not av then return end;local aB=j("Confirm new password: ",64,true)if
aB~=av then
a.lastOut={"Passwords do not match — unchanged.",d.error}return end;if av==""then
a.lastOut={"Password cannot be empty.",d.error}return end;local ay=g.getSession(i)local az=
ay and ay.user or"root"
local aA,aw=g.changePassword(az,az,ax,av)
if aA and aw then
a.lastOut={"Password changed. "..tostring(aw),d.warning}elseif aA then a.lastOut={"Password changed.",d.highlight}else
a.lastOut={tostring(aw),d.error}end end
local function ao(E,au,av)local az=a.st
local ax=g.registerSession and g.registerSession(E)or nil;local aA,ay=pcall(require,Q)
local aw=aA and ay.current and ay.current()local aB=aw and aw.principal;if ax then a.st=ax end
if aw then aw.principal=E end;local aC,aD=pcall(au)a.st=az;if aw then aw.principal=aB end;if ax and g.logout then
pcall(g.logout,ax)end;if not aC then
av("sudo: "..tostring(aD),d.error)end end
local function t()if not a._sudo then return false end;a.st=a._sudo.origSt
local av,E=pcall(require,Q)local au=av and E.current and E.current()if au then
au.principal=a._sudo.origPrincipal end;if a._sudo.token and g.logout then
pcall(g.logout,a._sudo.token)end;a._sudo=nil;return true end;a.sudoDrop=t
b.sudo=function(au,E)
if not g then E("No user system",d.error)return end;local ax=H.sessionOf(a)local av=au[1]
if av=="setup"then if not w(E)then return end;local aD=2;if
au[2]=="root"then aD=3 elseif au[2]and au[2]~="admin"then
E("Usage: sudo setup [admin|root]",d.dim)return end
local aC=j("New elevation password: ",64,true)if not aC or aC==""then E("Aborted.",d.dim)return end
if
j("Confirm: ",64,true)~=aC then E("Passwords do not match.",d.error)return end;local aE,aF=g.setElevation(ax,aC,aD)
if aE then
E("Elevation configured (cap: "..
H.tierName(aD)..").",d.highlight)else E(tostring(aF),d.error)end;return elseif av=="off"then if not w(E)then return end
local aC,aD=g.clearElevation and g.clearElevation(ax)if aC then E("Elevation disabled.",d.highlight)else
E(tostring(aD or"unavailable"),d.error)end;return elseif av=="-k"then
E(
t()and"Elevated session dropped."or"No active elevation.",d.dim)return end;if not av then
E("Usage: sudo <command> | sudo -s | sudo -k | sudo setup [admin|root] | sudo off",d.dim)return end
if
H.liveTier(a)<1 then E("sudo: guests cannot elevate.",d.error)return end
local az=g.elevationInfo and g.elevationInfo()or{configured=false}if not az.configured then
E("sudo: elevation is not configured. Root: sudo setup [admin|root]",d.warning)return end
local ay=j("[sudo] elevation password: ",64,true)if ay==nil then E("Aborted.",d.dim)return end
local aw,aA=g.elevate(ax,ay)if not aw then
E("sudo: "..tostring(aA or"elevation failed"),d.error)return end
if av=="-s"then t()
local aD=g.registerSession and
g.registerSession(aw)or nil;local aF,aE=pcall(require,Q)
local aC=aF and aE.current and aE.current()
a._sudo={origSt=a.st,origPrincipal=aC and aC.principal,token=aD}if aD then a.st=aD end;if aC then aC.principal=aw end
E("Elevated to "..
H.tierName(aw.tier)..". 'sudo -k' or 'logout' drops it.",d.highlight)return end;local aB=table.concat(au," ")
ao(aw,function()if not a.execOne then
E("sudo: executor unavailable",d.error)return end;local aC=a.execOne(aB)if
type(aC)=="table"then
for aE,aD in ipairs(aC)do if type(aD)=="table"then E(aD[1],aD[2]or d.fg)else
E(tostring(aD),d.fg)end end end end,E)end;b.logout=function(E,au)H.logout(a)end
b.cli=function(au,E)if a.isCLI then
E("You are already at the command line. Type 'tui' for the full interface.",d.dim)return end;a._exitTo="cli"end
b.tui=function(au,E)if a.isCLI then E("Returning to the full interface…",d.dim)
a._exitTo="tui"return end
E("You are already in the full interface. Type 'cli' for the command line.",d.dim)end
b.reboot=function(au,E)local av,aw=H.canPowerOff(a)
if not av then E(aw,d.error)return end;h.reboot()end
b.shutdown=function(au,E)local av,aw=H.canPowerOff(a)
if not av then E(aw,d.error)return end;h.shutdown()end
b.env=function(E,au)local ay,av=pcall(require,"kernel.env")if not ay then
au("Env module unavailable",d.error)return end;local ax=h.getProc()local aw=
ax and ax.current()or nil
if E[1]then
local az,aA=E[1]:match("^([%w_]+)=(.*)$")if az then av.write(aw,az,aA)au(az.."="..aA,d.highlight)else
local aB=av.read(aw,E[1])
au(E[1].."="..tostring(aB or""),d.fg)end else
local az=av.list(aw)for aA,aB in pairs(az)do
au("  "..aA.."="..tostring(aB),d.fg)end end end;b.export=b.env;b.set=b.env
b["tape-menu"]=function(au,E)
local aC,aw=pcall(require,"shell.launcher")if not aC or not aw then
E("Menu engine unavailable (low RAM?)",d.error)return end;if not n or not n.getSize then
E("tape-menu needs a screen.",d.error)return end;local ax=nil
local function aD(aJ)local aK={}local aL={}for aT in
aJ:gmatch("%S+")do aL[#aL+1]=aT end;if#aL==0 then return aK end
local aM=aL[1]local aO={}for aT=2,#aL do aO[#aO+1]=aL[aT]end
local aP=H.tierRefusal(a,aM:lower())if aP then aK[#aK+1]={aP,d.error}return aK end;if not ax then
ax=require(L).build(a,c)end;local aN=ax[aM]
if not aN then local aU,aT=pcall(require,R)if aU and aT and
aT.getCommand then aN=aT.getCommand(aM)end end;if not aN then
aK[#aK+1]={"Unknown command: "..aM,d.error}return aK end;local aQ=function(aT,aU)
aK[#aK+1]={tostring(aT),aU or d.fg}end
local aR,aS=pcall(aN,aO,aQ)if not aR then
aK[#aK+1]={"Error: "..tostring(aS),d.error}end;return aK end;local az=N.list and N.list("tape_drive")()
if
not az then E("No tape drive found.",d.error)return end;local av=N.proxy(az)
local aE,aF=pcall(function()return av.isReady()end)
if not aE or not aF then E("No tape inserted.",d.warning)return end
local aG=(av.getSize and av.getSize())or 0
if aG<=0 then E("Tape is empty.",d.warning)return end
local ay=j and j("Tape menu passphrase: ",64,true)or nil;if not ay or ay==""then E(ab,d.dim)return end
local aH,aA=pcall(require,"kernel.vault")
if not aH or not aA then E("vault unavailable",d.error)return end;local aB,aI=aw.readTapeMenuFromDrive(av,ay,aA)if not aB then
E(tostring(aI),d.error)return end
aw.run({display=n,profile=aB,runLine=aD,title="Tape toolbox"})if c.drawAll then pcall(c.drawAll)end end
b.clip=function(au,E)local ay,av=pcall(require,"kernel.clipboard")if not ay or not av then
E(
"Clipboard unavailable: "..tostring(av),d.error)return end;local aw=a.displayIdx;local ax=au[1]
if
not ax then
E("Clipboard: "..av.describe(aw),d.title)local az=av.get(aw)
if az and not av.isEmpty(aw)then
local aA=math.min(#az,10)for aB=1,aA do E("  "..az[aB],d.fg)end;if#az>aA then
E("  ... "..
(#az-aA).." more line(s)",d.dim)end end
E("Usage: clip [set <text> | clear]   Copy: "..
(function()local aB,aA=pcall(require,X)
return(aB and aA)and
aA.label("copy",a.who)or"Ctrl+Insert"end)(),d.dim)return end;if ax=="clear"then av.clear(aw)
E("Clipboard cleared.",d.highlight)return end
if ax=="set"then
local az=table.concat(au," ",2)
if az==""then E("Usage: clip set <text>",d.warning)return end;local aB,aA=av.set(az,aw)if not aB then
E("Could not set clipboard: "..tostring(aA),d.error)return end;if aA then
E("Clipboard set, TRUNCATED at the cap: "..
av.describe(aw),d.warning)else
E("Clipboard: "..av.describe(aw),d.highlight)end;return end;E("Usage: clip [set <text> | clear]",d.warning)end
b.desktop=function(au,E)local aw,av=pcall(require,"shell.panels.desktop")if not aw then
E(
"Desktop unavailable: "..tostring(av),d.error)return end;av.open(a)end
b.settings=function(au,E)local aw,av=pcall(require,"shell.panels.settingsapp")if
not aw then
E("Settings unavailable: "..tostring(av),d.error)return end;av.open(a)end
b.lang=function(au,E)local az,av=pcall(require,"kernel.i18n")if not az or not av then
E(
"i18n unavailable: "..tostring(av),d.error)return end;local aw=au[1]
if not aw then
E(ak..av.language()..
"  ("..av.languageName()..")",d.title)E("Installed catalogs:",d.fg)for aE,aD in ipairs(av.available())do
local aF=(aD.code==
av.language())and" * "or"   "
E(aF..string.format("%-8s %s",aD.code,aD.name),d.fg)end
E("Usage: lang <code> | lang system <code> | lang dump [path]",d.dim)
E("Catalogs are DATA files at /usr/lang/<code>.lang — see 'man lang'.",d.dim)return end
if aw=="system"then if not r(E)then return end;local aD=au[2]if not aD then
E("Usage: lang system <code|en>",d.dim)return end;local aE,aF=av.setLanguage(aD)
if not aE then E(
"Cannot set: "..tostring(aF),d.error)return end
if p and p.set then p.set("language",aD)if p.save then p.save()end end
E("System language: "..av.language(),d.highlight)return end
if aw=="dump"then
local aE=f(au[2]or"/tmp/lang-template.lang")local aF=av.keysSeen()if#aF==0 then
E("No keys seen yet — visit a few screens first (log out/in, open the Desktop).",d.warning)return end
local aD={"-- TOS language catalog template (every t() key seen this session).","-- Translate the values, set meta.code/name, save as /usr/lang/<code>.lang,","-- then run `lang <code>`. Untranslated keys keep their English default.","-- /usr is a protected system path: as root, `protect off` to copy this","-- in and `protect on` after -- or ship the catalog as a package.","return {",'  meta = { code = "xx", name = "Language name" },',"  strings = {"}for aJ,aI in ipairs(aF)do
aD[#aD+1]=string.format("    [%q] = %q,",aI.key,aI.default)end;aD[#aD+1]="  },"
aD[#aD+1]="}"
if not o(aE)then E("Cannot write: "..aE,d.error)return end
local aH,aG=e.writeFile(aE,table.concat(aD,"\n").."\n")
if aH then
E("Template with "..#aF.." key(s) -> "..aE,d.highlight)k()else E(ad..aE,d.error)
if aG then E(tostring(aG),d.dim)end
if aE:sub(1,10)=="/usr/lang/"then
E("Dump to /tmp (the default), then copy it in under `protect off`,",d.dim)E("or ship the catalog as a package.",d.dim)end end;return end;local aA,aB=av.setLanguage(aw)if not aA then
E("Cannot set '"..tostring(aw)..
"': "..tostring(aB),d.error)E("Run 'lang' to list installed catalogs.",d.dim)
return end
local ay=H.sessionOf(a)local aC,ax=pcall(require,"kernel.profile")
if aC and ax and ax.load and
ax.save then local aD=ax.load(ay)
aD.lang=
(av.language()~="en")and av.language()or nil;local aE,aF=ax.save(aD,ay)
if aE then
E(ak..
av.language().."  (saved to your profile)",d.highlight)else
E("Language set for this session (profile save failed: "..tostring(aF)..")",d.warning)end else
E(ak..av.language().."  (this session)",d.highlight)end end end