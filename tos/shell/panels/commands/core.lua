
local ab,L,ac,T,U,ad,M,ae,af,ag,ah,ai,aj,V,ak,K,al,W,X,am,an,ao,Y,N,Z="  Examples:","  Subcommands:"," %-24s %8s"," (needs admin for /etc).","--system","Cancelled.","Cannot read: ","Keychain is locked.","Language: ","No such file: ","Save failed","Save failed.","Write failed: ","[^/]+$","decrypt","encrypt","function","kernel.pkg","kernel.process","profile module unavailable","rename","save failed","shell.keys","shell.panels.commands","timezone"local O=require("computer")local P=require("component")
local J=require("shell.panels.helpers")local Q=function()end
do local b,a=pcall(require,X)if b and a and a.yieldCooperative then
Q=a.yieldCooperative end end;local function R()local a,b=pcall(require,"shell.panels.home")
return(a and b)or nil end;local function _(a)local b=R()return
b and b.cycleKeyLabel(a)or"F2"end
local function ap(a)
local b=R()if b and b.enabled(a)then
return b.viewKeyLabel(a).."  Tiles / files "end;return"F2  Next tab      "end
local function aa(a)local e=R()local d,b=pcall(require,Y)if not(d and b)then
return"Copy Ctrl+Insert  Cut ^X  Paste ^V"end;local c=a and a.who or nil;return
"Copy "..
b.label("copy",c).."  Cut "..
b.label("cut",c).."  Paste "..b.label("paste",c)end
local function S(a)local c,b=pcall(require,Y)return
(c and b and b.quitHint)and b.quitHint(a and a.who or
nil)or"^Q"end
local function aq(a)local b=_(a)return b..
string.rep(" ",math.max(1,12-#b)).."Next tab   "end
return
function(b,a,c)local h,ar,u,e,n,g=a.K,a.E,a.P,a.F,a.D,a.U;local p,A,i=a.SC,a.NM,a.st;local d=a.T;local B=a.tier
local q,v=a.W,a.H;local f=c.rp;local s=c.openViewTab;local as=c.openEditTab;local k=c.refreshBrowser
local l=c.canRead;local o=c.canWrite;local at=c.canAccess;local w=c.rootOnly;local r=c.adminOnly
local au=c.makeProgramEnv;local m=J.fmtSz
local av=function(E)return J.expandBuf(a,E)end;local j=c.promptInput
b.help=function(aw,E)
local ax=aw and aw[1]and aw[1]:lower()
if ax=="cp"or ax=="copy"then E("cp <source> <dest>",d.title)
E("  Copy a file. Both paths are required.",d.fg)
E("  Paths starting with / are absolute; others are relative to cwd.",d.fg)E(ab,d.dim)
E("    cp notes.txt /home/root/notes_bak.txt",d.dim)E("    cp /etc/cfg.conf /tmp/cfg.conf",d.dim)
E("  Tip: Use F5 in the browser for clipboard-style copy.",d.highlight)elseif ax=="mv"then E("mv <source> <dest>",d.title)
E("  Move or rename a file.",d.fg)E(ab,d.dim)
E("    mv old.txt new.txt           (rename in cwd)",d.dim)
E("    mv /tmp/work.lua /home/root/ (move to dir)",d.dim)elseif ax=="cd"then E("cd [dir]",d.title)
E("  Change directory. With no argument, prints current directory.",d.fg)
E("  Special paths:  ..  (parent)   ~  (home dir)",d.fg)elseif ax=="find"then E("find [path] [-name pattern]",d.title)
E("  Recursively search for files. Pattern uses Lua patterns.",d.fg)E(ab,d.dim)E("    find /tos -name *.lua",d.dim)
E("    find /home",d.dim)elseif ax=="grep"then E("grep <pattern> <file>",d.title)
E("  Search file lines for pattern (plain text, not regex).",d.fg)
E("  Example:  grep function /tos/shell/init.lua",d.dim)elseif ax=="flash"then E("flash <file>",d.title)
E("  Write a Lua file to the EEPROM (overwrites BIOS!).",d.fg)
E("  Prompts for confirmation. Use to install a new BIOS.",d.fg)E("  Example:  flash /tos/bios.lua",d.dim)elseif ax=="edit"then
E("edit <file>",d.title)
E("  Open file in editor tab. Creates the file if it doesn't exist.",d.fg)
E("  Keys:  Ctrl+S = save   Ctrl+Q = close tab   Ctrl+F = find",d.dim)E("  Ctrl+H = find/replace  Ctrl+Z = undo",d.dim)E(
"  Select: Shift+arrows.  "..aa(a),d.dim)
E("  With nothing selected, copy/cut take the whole line.",d.dim)
E("  Use ".._(a).." to switch tabs, F4 to close.",d.dim)elseif ax=="run"then E("run <file> [args...]",d.title)
E("  Execute a Lua file in the current environment.",d.fg)
E("  Args are passed as a table in the second argument.",d.fg)elseif ax=="tape"then E("tape [subcommand]",d.title)
E("  Data storage on Computronics tapes (requires module).",d.fg)
E("  If the tape package is not installed, shows",d.fg)
E("  instructions for installing it or building your own.",d.fg)E("",d.fg)
E("  Subcommands (when module is active):",d.dim)E("    detect           List tape drives",d.dim)
E("    info             Tape size, label, format",d.dim)E("    label [name]     Get/set tape label",d.dim)
E("    store <path>     Archive file/dir to tape",d.dim)
E("    restore [path]   Restore archive from tape",d.dim)
E("    list             List archived entries",d.dim)
E("    dump [off] [len] Hex dump of tape bytes",d.dim)E("    erase [full]     Quick or full wipe",d.dim)
E("    raw read/write   Low-level byte I/O",d.dim)elseif ax=="net"then E("net [subcommand]",d.title)
E("  Network management (requires modem or linked card).",d.fg)E("",d.fg)E(L,d.dim)
E("    status              Show network status",d.dim)
E("    discover / scan     Broadcast ping to find peers",d.dim)
E("    peers / list        List known peers and trust levels",d.dim)
E("    trust <addr> [full] Elevate peer to KNOWN or TRUSTED",d.dim)E("    block <addr>        Block a peer",d.dim)
E("    send <addr> <msg>   Send message to trusted peer",d.dim)E("",d.fg)
E("  Related: ping <addr>, hostname [name], chat",d.dim)elseif

ax=="pkg"or ax=="mod"or ax=="module"or ax=="modules"or ax=="package"or ax=="packages"then E("pkg [subcommand]",d.title)
E("  Package manager — install and manage add-ons. (Replaces the old",d.fg)
E("  'mod'/module manager, retired in v1.3.1.)",d.fg)E("",d.fg)E(L,d.dim)
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
E("  Shortcuts: 'install <name>' and 'uninstall <name>' work too.",d.dim)elseif ax=="monitor"or ax=="top"then
E("monitor   (alias: top; also opened with Ctrl+T)",d.title)
E("  The live System Monitor — one screen showing what TOS is doing.",d.fg)E("",d.fg)E("  Shows:",d.dim)
E("    · Every process (kernel AND user), each explained, with owner,",d.dim)
E("      state, CPU and seat — auto-refreshing.",d.dim)
E("    · rc.d services and their status (admin).",d.dim)E("    · Memory and uptime vitals.",d.dim)
E("",d.fg)
E("  Runs as a full-screen tab: scrolls, never truncates, per-seat.",d.dim)E("",d.fg)E("  Keys:",d.dim)
E("    up/down move   Enter switch-to   K kill   T suspend/resume (TSR)",d.dim)
E("    Enter start-stop a service (admin)   R refresh   "..S(a).." close",d.dim)elseif ax=="cron"then E("cron [subcommand]",d.title)
E("  Manage scheduled tasks.  (admin+)",d.fg)E("",d.fg)E(L,d.dim)
E("    list                Show all cron jobs",d.dim)
E("    add <interval> <cmd> Schedule a command",d.dim)
E("    rm <id>             Remove a cron job",d.dim)elseif ax=="service"then E("service [subcommand]",d.title)
E("  Manage startup services.  (admin+)",d.fg)E("",d.fg)E(L,d.dim)
E("    (none)              List all services and status",d.dim)E("    start <name>        Start a service",d.dim)
E("    stop <name>         Stop a service",d.dim)elseif ax=="users"or ax=="useradd"or ax=="userdel"or
ax=="usermod"then
E("User Management  (admin/root)",d.title)
E("  users                   List all user accounts",d.fg)
E("  useradd <name>          Create a new user",d.fg)E("  userdel <name>          Delete a user",d.fg)
E("  usermod <user> <action> Modify a user:",d.fg)
E("    lock / unlock         Lock or unlock an account",d.dim)
E("    admin / user          Set role to admin or user",d.dim)
E("  whoami                  Show current user",d.fg)
E("  passwd                  Change your password",d.fg)elseif ax=="disk"then E("disk [subcommand]",d.title)
E("  Manage removable disks (floppies, HDDs).",d.fg)E("",d.fg)E(L,d.dim)
E("    list                List removable disks",d.dim)
E("    info <mount>        Show disk contents",d.dim)
E("    install <mount>     Install module from disk (admin)",d.dim)
E("    export <name> <mnt> Write module to disk    (admin)",d.dim)E("    eject <mount>       Unmount a disk",d.dim)elseif ax==
"redstone"or ax=="rs"then
E("redstone [subcommand]  (alias: rs)",d.title)E("  Control redstone I/O on all sides.",d.fg)
E("",d.fg)E(L,d.dim)
E("    (none)              Show redstone levels",d.dim)
E("    set <side> <level>  Set output (0-15)",d.dim)
E("    pulse <side> [dur]  Pulse output (default 0.5s)",d.dim)elseif ax=="robot"then E("robot <command>",d.title)
E("  Control robot/drone movement and interaction.",d.fg)E("",d.fg)
E("  Movement: forward, back, up, down, left, right",d.dim)
E("  Actions:  swing, use, place, suck, drop, detect",d.dim)E("  Info:     name, energy, slot <n>",d.dim)elseif
ax=="audio"or ax=="sound"or ax=="beep"then
E("audio [subcommand]",d.title)
E("  Control audio feedback (beeps and notifications).",d.fg)E("",d.fg)E(L,d.dim)
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
E("    2 descending        Shutdown / logout",d.dim)E("    3 ascending         Boot complete",d.dim)elseif ax and
ax~=""then local az=require(N)local ay=az.entry and az.entry(ax)
if ay then
local aB={[0]="guest",[1]="user",[2]="admin",[3]="root"}E(ax,d.title)
E("  ".. (ay.help or"(no description)"),d.fg)E("",d.fg)
E(string.format("  Minimum tier: %s    Group: %s",aB[ay.tier or 0]or
tostring(ay.tier),ay.category or"?"),d.dim)
local aA="  Tip: run '"..ax.."' with no args for usage"
if e.exists("/usr/man/"..ax..".man")then aA=aA.."; 'man "..
ax.."' for the manual."else aA=aA.."."end;E(aA,d.dim)else
E("No such command: '"..ax.."'.  Type 'help' for the full list.",d.warning)end else local az=require(N)
local function ay(aE)return az.needMet and az.needMet(aE)end
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
E("  F1  Help      "..ap(a)..
"  F3  View file",d.fg)
E("  F4  Close tab F5  Copy file      F6  Move file",d.fg)
E("  "..aq(a).." F9  Menu bar",d.fg)E("  F7  Mkdir     F8  Delete",d.fg)
E("  Text: Shift+arrows select.  "..aa(a),d.fg)
E("  F10 Quit      "..S(a).."  Cancel/Close   ^F  Find",d.fg)
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
E("  edit <file>   Open in editor tab  (^S save, "..S(a).." close)",d.fg)end
if a.userTier>=3 then
E("  lua           Interactive Lua REPL  (exit to quit)",d.fg)
E("  flash <file>  Flash EEPROM with Lua file  (!CAUTION)",d.fg)end
E("  programs      List executables in /bin and /usr/bin",d.fg)E("  history       Show command history",d.fg)
E("  date [fmt]    Show wall clock  (time = alias)",d.fg)
E("  tree [path] [depth]  Visual recursive directory listing",d.fg)
E("  theme [list|set|color|...]  Customize colors  (colors = alias)",d.fg)
E("  tutorial      Replay the welcome walkthrough",d.fg)if a.userTier>=1 and ay("swap")then
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
E("  cron [list|add|rm]        Scheduled tasks",d.fg)end;local aA,aB=ay("component:redstone"),ay("component:robot")
local aC,aD=ay("inventory"),ay("module:tape")
if aA or aB or aC or aD or a.userTier>=2 then E("",d.fg)
E(" Peripherals",d.highlight)if aA then
E("  redstone [set|pulse] Control redstone I/O  (rs = alias)",d.fg)end;if aB then
E("  robot <cmd>          Robot/drone movement & interaction",d.fg)end;if aC then
E("  inventory [side]     Inspect inventories  (inv = alias)",d.fg)end;if aD then
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
b.man=function(aw,E)local ay="/usr/man"local ax=aw and aw[1]
if not ax then
E("Manual pages — usage: man <topic>",d.title)local aB=
(e.isDirectory and e.isDirectory(ay)and e.list(ay))or{}
if
type(aB)=="table"and#aB>0 then table.sort(aB)
for aD,aC in ipairs(aB)do
local aE=(aC:gsub("/$","")):gsub("%.man$","")if aE~=""then E("  "..aE,d.fg)end end else
E("  (no manual pages installed under "..ay..")",d.dim)end
E("Depth: help (quick) < man (detailed) < MANUAL.md (the full book)",d.dim)return end;ax=tostring(ax):gsub("[^%w_%-]","")if ax==""then
E("man: invalid topic",d.error)return end;local az=e.join(ay,ax..".man")if not
e.exists(az)then az=e.join(ay,ax)end
if not e.exists(az)then E(
"No manual page for '"..ax.."'.",d.error)
E(
"Try 'help "..ax.."', or open MANUAL.md for the full book.",d.dim)return end;local aA=e.readFile(az)if not aA then
E("man: cannot read page",d.error)return end
if s then local aB={}
for aC in
(aA.."\n"):gmatch("([^\n]*)\n")do local aD=d.fg
if aC:match("^[A-Z][A-Z0-9 /%-]+$")then aD=d.title elseif aC:match("^%s")then aD=d.dim end;aB[#aB+1]={aC,aD}end;s(aB,"man "..ax)else for aB in(aA.."\n"):gmatch("([^\n]*)\n")do
E(aB,d.fg)end end end
b.about=function(aw,E)local ax=_G._TOS or{}
local aA,ay,aB="Strata Systems LLC",nil,"Terminal Operating System"local aC,az=pcall(require,"kernel.logo")if aC and az then
aA=az.VENDOR or aA;ay=az.MOTTO;aB=az.TAGLINE or aB end;E(
"TOS - "..aB,d.title)
E("Version "..
(ax.version or"?").."  [".. (ax.codename or
"?").."]",d.highlight)
E("Build "..tostring(ax.build or"?").." ("..
tostring(ax.variant or"?")..")",d.dim)
E("GPU T"..B.." | "..
math.floor(O.totalMemory()/1024).."K RAM",d.dim)E(aA.."   -   GNU GPL v3.0",d.dim)if ay and ay~=""then E(
'"'..ay..'"',d.dim)end;E("",d.fg)
E("A secure, multi-seat terminal OS for OpenComputers:",d.fg)
E("  - Sandboxed processes, role-based users, encrypted homes",d.fg)
E("  - Tabbed file browser + editor, themeable panels UI",d.fg)
E("  - Zero-trust networking: chat, mesh mail, clustering",d.fg)
E("  - Package manager + Optional Utilities add-on disk",d.fg)
E("  - Boot Settings (DEL at POST), swap, backups, OpenOS compat",d.fg)E("",d.fg)
E("'help' lists commands · 'tutorial' walks you through it.",d.dim)end;b.ver=b.about
b.echo=function(E,aw)aw(table.concat(E," "),d.fg)end
b.notify=function(aw,E)local aE,ax=pcall(require,"kernel.notify")if not aE or not ax then
E("notify unavailable",d.error)return end;local az,aA,ay="info",nil,{}local aB
for aG=1,# (aw or{})
do local aH=tostring(aw[aG])
if aG==aB then elseif aH:sub(1,2)=="--"then
local aJ,aI=aH:match("^%-%-([%w%-]+)=?(.*)$")
if aJ=="style"or aJ=="title"then if aI==""and aw[aG+1]and
tostring(aw[aG+1]):sub(1,2)~="--"then
aI=tostring(aw[aG+1])aB=aG+1 end
if aJ=="style"then az=aI else aA=aI end end else ay[#ay+1]=aH end end;local aC=table.concat(ay," ")
if aC==""then
E("Usage: notify <message> [--style info|warn|danger|error] [--title T]",d.title)
E("Puts a modal dialog box in front of every seat — the intrusive",d.dim)
E("counterpart to 'echo', which only writes above the command line.",d.dim)E("",d.dim)
E(string.format("Pending now: %d   (limits: %ds between boxes, %ds per source)",ax.depth(),ax.MIN_GAP,ax.MIN_SOURCE_GAP),d.dim)return end
local aD,aF=ax.post({message=aC,style=az,title=aA,from="notify/"..tostring(a.who or"?")})
if aD then
E("Raised on every seat (dialog #"..aD..").",d.highlight)else
E("Not raised: "..tostring(aF),d.warning)
E("The message is in the log either way ('log' to see it).",d.dim)end end
b.tutorial=function(aw,E)local ay,ax=J.requireRoomy(a,"shell.tutorial","core")
if
not ay then E(J.loadFailure("tutorial",ax),d.error)return end
if aw[1]=="--reset"then local aA=
(g and i and g.getSession)and g.getSession(i)or nil;local az=ax.markerFor and
ax.markerFor(aA)
if az and e.exists(az)then
e.remove(az)
E("Tutorial reset — it will run again at your next login.",d.success or d.fg)elseif az then
E("Tutorial was not marked done for this account.",d.dim)else
E("This account has no home to remember the tutorial in.",d.dim)end end;ax.run({D=n,F=e,U=g,st=i,W=q,H=v})c.drawAll()end
b.cls=function(E,aw)n.fill(1,1,q,v," ",d.fg,d.bg)c.drawAll()end;b.clear=b.cls
b.cd=function(E,aw)if not E[1]then aw(a.cwd,d.fg)return end
local ax=E[1]
if ax==".."then
a.cwd=a.cwd:match("^(.*)/[^/]+/?$")or"/"if a.cwd==""then a.cwd="/"end else local ay=f(ax):gsub("//+","/")
if
ay~="/"and ay:sub(-1)=="/"then ay=ay:sub(1,-2)end;if e.isDirectory(ay)then a.cwd=ay else
aw("Not a directory: "..ax,d.error)return end end;a.browser.path=a.cwd;a.browser.sel=1;a.browser.scroll=0
c.loadFiles(a.browser)end
b.ls=function(aw,E)local aC,aD,az=false,false,nil
for aI,aH in ipairs(aw)do
if not az and aH:sub(1,1)=="-"and
#aH>1 then
for aJ in aH:sub(2):gmatch(".")do if aJ=="l"then aC=true elseif aJ=="a"then aD=true else
E("Usage: ls [-l|-a] [dir]",d.dim)return end end elseif not az then az=aH end end;local ax=f(az or a.cwd)if not l(ax,E)then return end;if e.exists and
not e.exists(ax)then
E("no such file: ".. (az or ax),d.error)return end
local aF,aA=pcall(e.list,ax)
if not aF or not aA then E("Cannot list: "..ax,d.error)return end;local ay,aB={},0;local function aE(aH)
if aD or aH:sub(1,1)~="."then ay[#ay+1]=aH else aB=aB+1 end end
if type(aA)=="table"then for aI,aH in ipairs(aA)do
aE(aH)end elseif type(aA)==al then for aH in aA do aE(aH)end end
table.sort(ay,function(aH,aI)local aJ,aK=aH:sub(-1)=="/",aI:sub(-1)=="/"if aJ~=aK then
return aJ end;return aH<aI end)
local function aG(aH)if not e.lastModified then return"-"end
local aJ,aI=pcall(e.lastModified,e.join(ax,aH))
if not aJ or type(aI)~="number"or aI<=0 then return"-"end
local aK,aL=pcall(os.date,"%Y-%m-%d %H:%M",math.floor(aI/1000))return aK and aL or"-"end
if aC then
E(string.format(" %-24s %8s  %s","Name","Size","Modified"),d.title)E(string.rep("-",52),d.border)else
E(string.format(ac,"Name","Size"),d.title)E(string.rep("-",34),d.border)end
for aI,aH in ipairs(ay)do local aK,aJ
if aH:sub(-1)=="/"then
aK=string.format(ac,"["..aH:sub(1,-2).."]","<DIR>")aJ=d.dir or d.highlight else local aL=e.size(e.join(ax,aH))
aJ=d.fg
if aH:match("%.lua$")then
aJ=d.file_lua or d.file_exec or d.highlight elseif aH:match("%.cfg$")or aH:match("%.conf$")then
aJ=d.file_cfg or d.warning elseif aH:match("%.log$")then aJ=d.file_log or d.dim end;aK=string.format(ac,aH:sub(1,24),m(aL))end;if aC then aK=aK.."  "..aG(aH)end;E(aK,aJ)end
if aB>0 then
E(#ay.." items ("..aB.." hidden: ls -a shows them)",d.dim)else E(#ay.." items",d.dim)end end;b.dir=b.ls
local function C(aw,E)local ax=f(aw)if not l(ax,E)then return true end;local ay,az,aA=J.readLinesCapped(e,ax,function(aB)
E(aB,d.fg)end)if not ay then E(
M..aw,d.error)elseif aA then
E(string.format(J.VIEW_STOPPED,az),d.warning)return false end;return true end
b.cat=function(E,aw)
if not E[1]then aw("Usage: cat <file...>",d.dim)return end;for ay,ax in ipairs(E)do if not C(ax,aw)then break end end end;b.type=b.cat
b.more=function(E,aw)
if not E[1]then aw("Usage: more <file>",d.dim)return end;local ay=f(E[1])if not l(ay,aw)then return end
local ax={{" "..ay,d.title}}
local az,aA,aB=J.readLinesCapped(e,ay,function(aC)ax[#ax+1]={aC,d.fg}end)if not az then aw(M..E[1],d.error)return end;if aB then
ax[#ax+1]={string.format(J.VIEW_STOPPED,aA),d.warning}end
s(ax,E[1]:match(V)or E[1])end
local function D(E,ax,aw)local ay=f(E)local az=ay:match("^(.*)/[^/]+/?$")or"/"if not
o(az,aw)then return false end;if e.isDirectory and e.isDirectory(ay)then
if
not ax then aw("Already exists: "..E,d.warning)end;return false end
local aA,aB=e.makeDirectory(ay)
if aA then aw("Created: "..E,d.highlight)return true end
aw(tostring(aB or"Could not create "..E),d.error)return false end
b.mkdir=function(aw,E)local az,ax=false,{}
for aB,aA in ipairs(aw)do if aA=="-p"or aA=="--parents"then az=true else
ax[#ax+1]=aA end end
if not ax[1]then E("Usage: mkdir [-p] <dir...>",d.dim)return end;local ay=false;for aB,aA in ipairs(ax)do ay=D(aA,az,E)or ay end
if ay then k()end end
local function F(E,aw)local ax=f(E)if not o(ax,aw)then return false end
if not e.exists(ax)then
local ay,az=e.writeFile(ax,"")if not ay then
aw(tostring(az or"Could not create "..E),d.error)return false end end;aw("Touched: "..E,d.highlight)return true end
b.touch=function(E,aw)
if not E[1]then aw("Usage: touch <file...>",d.dim)return end;local ax=false;for az,ay in ipairs(E)do ax=F(ay,aw)or ax end
if ax then k()end end
local function x(E)local ax,aw=false,{}for az,ay in ipairs(E)do if ay=="-k"or ay=="--keep"then ax=true else
aw[#aw+1]=ay end end;return
ax,aw end
b.compress=function(aw,E)local aG,ay=x(aw)if not ay[1]then
E("Usage: compress <file> [out]   (-k keeps original)",d.dim)return end
local aB=h.getCompress and h.getCompress()if not aB or not aB.available()then
E("Compression needs a data card (none detected).",d.error)return end;local ax=f(ay[1])if not
l(ax,E)then return end;if not e.exists(ax)or
(e.isDirectory and e.isDirectory(ax))then
E("Not a file: "..ay[1],d.error)return end
local aC=e.readFile(ax)if not aC then E("Read failed",d.error)return end;local az=ay[2]and
f(ay[2])or(ax..".tcz")
if not o(az,E)then return end;local aD,aE,aA,aF=aB.pack(aC)
if not aD then E("Compress failed",d.error)return end
if not e.writeFile(az,aD)then E("Write failed",d.error)return end;if not aG and az~=ax then pcall(e.remove,ax)end;k()
local aH=
(aA>0)and math.floor((aA-aF)*100/aA)or 0
E(string.format("%s -> %s  (%d%% smaller: %s -> %s)",ay[1],(az:gsub("^.*/","")),aH,m(aA),m(aF)),
aE=="deflate"and d.highlight or d.warning)if aE=="stored"then
E("(stored uncompressed — data didn't shrink)",d.dim)end end
b.decompress=function(aw,E)local aD,ay=x(aw)if not ay[1]then
E("Usage: decompress <file.tcz> [out]   (-k keeps original)",d.dim)return end;local ax=f(ay[1])if
not l(ax,E)then return end
if not e.exists(ax)then E(ag..ay[1],d.error)return end;local aA=e.readFile(ax)
if not aA then E("Read failed",d.error)return end;local aB=h.getCompress and h.getCompress()if not aB then
E("Compression module unavailable",d.error)return end
if not aB.isPacked(aA)then E("Not a .tcz container: "..
ay[1],d.error)return end;local aC,aE=aB.unpack(aA)if not aC then
E("Decompress failed: "..tostring(aE),d.error)return end;local az
if ay[2]then az=f(ay[2])elseif
ax:sub(-4)==".tcz"then az=ax:sub(1,-5)else az=ax..".out"end;if not o(az,E)then return end;if not e.writeFile(az,aC)then
E("Write failed",d.error)return end;if not aD and az~=ax then
pcall(e.remove,ax)end;k()
E(string.format("%s -> %s  (%s restored)",ay[1],(az:gsub("^.*/","")),m(
#aC)),d.highlight)end
local function G(aw,ax,ay,E)local az=f(aw)
if az=="/"then E("Cannot remove root",d.error)return end;local aA=_G._TOS and _G._TOS.securefs
if aA and
type(aA.removeRefusal)==al then
local aE=aA.removeRefusal(az,J.sessionOf(a))if aE then E(tostring(aE),d.error)return end end
local aC={"^/$","^/init%.lua$","^/bios%.lua$","^/tos$","^/tos/","^/etc$","^/etc/","^/boot$","^/boot/"}
for aF,aE in ipairs(aC)do
if az:match(aE)and not ax then
E("Refusing to remove a system path without -r: "..az..
"  [E-303 ERR_RM_SYSTEM_PATH]",d.error)
E("Protection is off, so this would really delete it. Add -r to confirm.",d.dim)return end end;if not o(az,E)then return end;if e.exists and not e.exists(az)then
E(ag..aw,d.error)return end
if
e.isDirectory and e.isDirectory(az)then if not ax then
E("Cannot remove directory without -r: "..az.."  [E-302 ERR_NEEDS_RECURSIVE]",d.error)return end
local aE=e.list and e.list(az)if aE and#aE>0 then
E("Removing "..#aE.." item(s) under "..az.."...",d.dim)end end;local aB=false
local aD=az:match("^/tos")or az:match("^/etc")or
az:match("^/var")or az:match("^/usr")
if not ay and not aD then local aF,aE=pcall(require,"kernel.trash")
if
aF and aE and aE.put then local aG=J.sessionOf(a)local aH,aI=aE.put(az,aG)
if aH then aB=true
E("Trashed: "..aw..

" (use 'trash restore ".. (aw:match(V)or aw).."' to undo)",d.highlight)else local aJ=tostring(aI or"unknown reason")
if
aJ:find("no trash",1,true)then
E("No trash for this session — deleting "..aw.." outright.",d.warning)else
E("Not trashed: "..aJ.."  [E-304 ERR_TRASH_REFUSED]",d.error)
E("It is still there. Delete it for good with:  rm "..
(ax and"-r "or"").."--hard "..aw,d.dim)return end end end end
if not aB then local aE,aF=e.remove(az)if aE then k()
E("Removed: "..aw,d.highlight)else
E(tostring(aF or"Could not remove "..aw),d.error)end else k()end end
b.rm=function(aw,E)local ay,az=false,false;local ax={}for aB,aA in ipairs(aw)do
if
aA=="-r"or aA=="-rf"or aA=="-R"then ay=true elseif aA=="--hard"or aA=="-H"then az=true else ax[#ax+1]=aA end end
if
#ax==0 then E("Usage: rm [-r] [--hard] <path...>",d.dim)return end;for aB,aA in ipairs(ax)do G(aA,ay,az,E)end end
b.trash=function(aw,E)local aA,ax=pcall(require,"kernel.trash")if not aA or not ax then
E("Trash unavailable",d.error)return end;local ay=aw[1]or"list"
local az=J.sessionOf(a)
if ay=="list"or ay=="ls"then local aC=ax.list(az)if#aC==0 then
E("Trash is empty.",d.dim)return end
E(string.format(" %-20s %-8s %s","name","size","origin"),d.title)for aE,aD in ipairs(aC)do
E(string.format(" %-20s %-8d %s",aD.name:sub(1,20),aD.size,aD.origin),d.fg)end;local aB=ax.usage(az)if
aB then
E(string.format(" %d/%d items, %d/%d bytes used",aB.count,aB.max_count,aB.bytes,aB.max_bytes),d.dim)end elseif ay=="empty"then
local aC,aB=ax.empty(az)if aC then
E("Emptied "..tostring(aB).." items.",d.highlight)else
E(tostring(aB or"empty failed"),d.error)end elseif ay=="restore"then if not aw[2]then
E("Usage: trash restore <name> [dest] [--force]",d.dim)return end;local aB,aC=false,nil;for aF=3,#aw do
if
aw[aF]=="--force"or aw[aF]=="-f"then aB=true else aC=aw[aF]end end
local aE,aD=ax.restore(aw[2],{session=az,dest=aC,force=aB})if aE then k()
E("Restored to "..tostring(aD),d.highlight)else
E(tostring(aD or"restore failed"),d.error)end else
E("Usage: trash [list|empty|restore <name> [dest] [--force]]",d.dim)end end
b.vault=function(aw,E)local aE,ay=J.requireRoomy(a,"kernel.vault","core")
if
not aE or not ay then E(J.loadFailure("vault",ay),d.error)return end;local ax=aw[1]local aC=J.sessionOf(a)
local az=_G._TOS and _G._TOS.securefs
local function aA(aF)if az and az.readFile then return az.readFile(aF,aC)end;return
nil,"securefs unavailable (refusing unchecked read)"end
local function aD(aF,aG)
if az and az.writeFile then return az.writeFile(aF,aG,aC)end;return false,"securefs unavailable (refusing unchecked write)"end
local function aB(aF,aG)
if aF~=nil and aF~="-"then
E("Note: a typed passphrase stays in this seat's command history;",d.dim)
E("leave it off, or use -, to be asked for it instead.",d.dim)return aF end;if not j then
E("Cannot ask for a passphrase here: give it as the last argument.",d.error)return nil end
local aH=j("Passphrase: ",256,true)if not aH or aH==""then E(ad,d.dim)return nil end
if aG then
local aI=j("Again, to confirm: ",256,true)if aI~=aH then
E(aI and"The two did not match; nothing was changed."or ad,d.error)return nil end end;return aH end
if ax==K or ax==ak then local aI,aK=aw[2],aw[3]if not aI or not aK then
E("Usage: vault "..ax..
" <src> <dst> [passphrase | -]",d.dim)return end;local aF=aA(f(aI))if not aF then E(M..
aI,d.error)return end;if ax==ak and
not ay.isEncrypted(aF)then
E("Source is not a TOS vault blob.",d.warning)return end
local aJ=aB(aw[4],ax==K)if not aJ then return end;local aG,aH;if ax==K then aG,aH=ay.encrypt(aF,aJ)else
aG,aH=ay.decrypt(aF,aJ)end;if not aG then
E("Failed: "..tostring(aH),d.error)return end;local aL,aM=aD(f(aK),aG)if not aL then
E(aj..tostring(aM),d.error)return end
E(string.format("%s %d -> %d bytes (algo=%s)",ax==K and"Encrypted"or
"Decrypted",#aF,#aG,tostring(aH.algo)),d.highlight)elseif ax=="encrypt-in-place"or ax=="decrypt-in-place"then
local aI=aw[2]if not aI then
E("Usage: vault "..ax.." <file> [passphrase | -]",d.dim)return end;local aL=f(aI)local aF=aA(aL)if not aF then
E(M..aI,d.error)return end;local aH=ax:sub(1,7)==K
if
aH and ay.isEncrypted(aF)then
E("Already encrypted — refusing to double-encrypt.",d.warning)return elseif not aH and not ay.isEncrypted(aF)then
E("Not a vault blob — nothing to decrypt.",d.warning)return end;local aJ=aB(aw[3],aH)if not aJ then return end;local aG,aK;if aH then
aG,aK=ay.encrypt(aF,aJ)else aG,aK=ay.decrypt(aF,aJ)end
if not aG then E("Failed: "..
tostring(aK),d.error)return end;local aM,aN=aD(aL,aG)if not aM then E(aj..tostring(aN),d.error)
return end
E(string.format("%s in place: %d -> %d bytes",
ax:sub(1,7)==K and"Encrypted"or"Decrypted",#aF,#aG),d.highlight)elseif ax=="info"then local aF=aw[2]if not aF then
E("Usage: vault info <file>",d.dim)return end;local aG=aA(f(aF))if not aG then
E(M..aF,d.error)return end;if not ay.isEncrypted(aG)then
E("Not a vault blob (no TVAULT1 magic).",d.warning)return end
E(string.format(" file:     %s",aF),d.title)
E(string.format(" size:     %d bytes",#aG),d.fg)local aH=#ay.MAGIC+1
local aI=aG:sub(aH,aH+3):gsub("\0+$","")
E(string.format(" algo:     %s",aI),d.fg)
E(string.format(" ctLen:    encrypted body inside this blob"),d.dim)
E(" (decrypt with the right passphrase to access contents)",d.dim)elseif ax=="tape"then local aF=aw[2]if aF~=K and aF~=ak then
E("Usage: vault tape encrypt|decrypt [passphrase | -]",d.dim)return end;local aG=b.tape;if not aG then
E("Tape module not installed (run `pkg install tape`).",d.warning)return end
local aH=aB(aw[3],aF==K)if not aH then return end;aG({aF,aH},E)else
E("Usage: vault [encrypt|decrypt|encrypt-in-place|decrypt-in-place|info|tape] ...",d.dim)
E("  vault encrypt <src> <dst> [passphrase]",d.dim)
E("  vault decrypt <src> <dst> [passphrase]",d.dim)
E("  vault encrypt-in-place <file> [passphrase]",d.dim)
E("  vault decrypt-in-place <file> [passphrase]",d.dim)E("  vault info <file>",d.dim)
E("  vault tape encrypt|decrypt [passphrase]",d.dim)
E("  Leave the passphrase off (or use -) to be asked for it, unechoed:",d.dim)
E("  a typed one stays in this seat's command history.",d.dim)end end
b.keychain=function(aw,E)local ax=_G._TOS and _G._TOS.keychain;if not ax then
E("keychain module unavailable",d.error)return end;local ay=J.sessionOf(a)
local az=aw[1]or"status"
if az=="status"then
E(ax.isUnlocked(ay)and"unlocked"or"locked",d.fg)elseif az=="unlock"then if not j then
E("interactive prompt unavailable",d.error)return end
local aA=j("Master password: ",64,"*")or""
if#aA==0 then E("(empty — cancelled)",d.dim)return end;local aB,aC=ax.unlock(aA,ay)if aB then
E("Keychain unlocked.",d.highlight)else
E("Unlock failed: "..tostring(aC),d.error)end elseif az=="lock"then ax.lock(ay)
E("Keychain locked.",d.highlight)elseif az=="list"then
if not ax.isUnlocked(ay)then E(ae,d.warning)return end;local aA=ax.list(ay)
if#aA==0 then E("(empty)",d.dim)return end;for aC,aB in ipairs(aA)do E("  "..aB,d.fg)end elseif az=="set"then if not aw[2]then
E("Usage: keychain set <name>",d.dim)return end;if not ax.isUnlocked(ay)then
E("Keychain is locked. Run 'keychain unlock' first.",d.warning)return end;if not j then
E("interactive prompt unavailable",d.error)return end;local aA=
j("Passphrase for '"..aw[2].."': ",256,"*")or""if#aA==0 then
E("(empty — cancelled)",d.dim)return end;local aB,aC=ax.set(aw[2],aA,ay)if aB then
E("Slot '"..
aw[2].."' saved.",d.highlight)else
E("Save failed: "..tostring(aC),d.error)end elseif az=="get"then if not aw[2]then
E("Usage: keychain get <name>",d.dim)return end;if not ax.isUnlocked(ay)then
E(ae,d.warning)return end;local aA,aB=ax.get(aw[2],ay)if aA then
E(aA,d.fg)else
E(tostring(aB or"no such slot"),d.error)end elseif az=="remove"or az=="rm"then if not aw[2]then
E("Usage: keychain remove <name>",d.dim)return end;if not ax.isUnlocked(ay)then
E(ae,d.warning)return end;local aA,aB=ax.remove(aw[2],ay)
if aA then E("Removed '"..
aw[2].."'.",d.highlight)else E(
"Remove failed: "..tostring(aB),d.error)end else
E("Usage: keychain [status|unlock|lock|list|set|get|remove] ...",d.dim)end end
b.profile=function(aw,E)local ay=_G._TOS and _G._TOS.profile;if not ay then
E(am,d.error)return end;local ax=J.sessionOf(a)local az=aw[1]or"show"
if az==
"show"then local aA,aC=ay.load(ax)
E(string.format(" name:    %s",aA.name),d.title)
E(string.format(" theme:   %s",aA.theme or"(unset — uses `theme set` choice or default)"),d.fg)
E(string.format(" cwd:     %s",aA.cwd or"(unset)"),d.fg)
E(string.format(" prompt:  %s",aA.prompt or"(default)"),d.fg)local aB=0;for aD in pairs(aA.env)do aB=aB+1 end
E(string.format(" env:     %d entries",aB),d.fg)
E(string.format(" startup: %d commands",#aA.startup),d.fg)if not aC then
E(" (no profile file — showing defaults)",d.dim)end elseif az=="set"then
if not aw[2]or not aw[3]then
E("Usage: profile set <field> <value>",d.dim)E("  fields: name, theme, cwd, prompt",d.dim)return end;local aA,aB=aw[2],aw[3]local aC=ay.load(ax)
if aA=="name"or aA=="theme"or
aA=="cwd"or aA=="prompt"then
if aA=="theme"then local aF=_G._TOS and
_G._TOS.theme
if
aF and aF.preset and not aF.preset(aB)then E("Unknown theme preset: "..aB,d.error)if aF.list then
E(
"Available: "..table.concat(aF.list(),", "),d.dim)end;return end end;aC[aA]=aB;local aD,aE=ay.save(aC,ax)
if aD then
E("Profile updated. Re-login to apply.",d.highlight)else E(tostring(aE or ao),d.error)end else E("Unknown field: "..aA,d.error)end elseif az=="env"then if not aw[2]then
E("Usage: profile env <KEY> [VALUE]",d.dim)return end;local aA=ay.load(ax)if aw[3]then
aA.env[aw[2]]=aw[3]E("env["..aw[2].."] set",d.highlight)else aA.env[aw[2]]=
nil
E("env["..aw[2].."] cleared",d.highlight)end
ay.save(aA,ax)elseif az=="startup"then local aB=aw[2]or"list"local aA=ay.load(ax)
if aB=="add"then
local aC=table.concat(aw," ",3)
if#aC==0 then E("Usage: profile startup add <cmd>",d.dim)return end;aA.startup[#aA.startup+1]=aC;ay.save(aA,ax)
E("Added.",d.highlight)elseif aB=="clear"then aA.startup={}ay.save(aA,ax)
E("Startup commands cleared.",d.highlight)else for aC,aD in ipairs(aA.startup)do
E(string.format(" %d. %s",aC,aD),d.fg)end;if#aA.startup==0 then
E("(no startup commands)",d.dim)end end elseif az=="reset"then local aA=_G._TOS and _G._TOS.securefs;if
aA and ax and ax.home and ax.home~="/"then
aA.remove(ax.home.."/.profile.cfg",ax)end
E("Profile reset to defaults.",d.highlight)else
E("Usage: profile [show|set|env|startup|reset]",d.dim)end end
b.cp=function(E,aw)
if not E[2]then aw("Usage: cp <src> <dst>",d.dim)return end;local ay,ax=f(E[1]),f(E[2])if e.isDirectory(ax)then
ax=e.join(ax,ay:match(V)or ay)end;local az,aA=e.copy(ay,ax)
if az then k()
aw("Copied: "..E[2],d.highlight)else aw(aA or"Failed",d.error)end end
b.mv=function(aw,E)
if not aw[2]then E("Usage: mv <src> <dst>",d.dim)return end;local ax,ay=f(aw[1]),f(aw[2])if e.isDirectory(ay)then
ay=e.join(ay,ax:match(V)or ax)end;if not o(ax,E)then return end
if not o(ay,E)then return end
if e.rename(ax,ay)then k()E("Moved: "..aw[2],d.highlight)else
local az,aA=e.copy(ax,ay)if az and e.remove(ax)then k()
E("Moved: "..aw[2],d.highlight)else
E("Move failed: "..tostring(aA or"cross-fs copy failed"),d.error)end end end
b.find=function(E,aw)local aB="/"local az=nil;local ax=1
while ax<=#E do if E[ax]=="-name"and E[ax+1]then
az=E[ax+1]ax=ax+2 else aB=f(E[ax])ax=ax+1 end end
if az then local aG,aH=pcall(string.match,"",az)if not aG then
aw("Invalid pattern: "..tostring(aH),d.error)return end end;aw("Searching "..aB.." ...",d.dim)local aE=16
local aA=1000;local ay={}
local function aF(aG)if not g or not g.canAccessAs then return false end
local aH=J.sessionOf(a)local aI=g.canAccessAs(aH,aG,"r")return aI end
local function aD(aG,aH)if aH>aE then return end;if#ay>=aA then return end;if not aF(aG)then return end
local aK,aI=pcall(e.list,aG)if not aK or not aI then return end;local aJ={}
if type(aI)=="table"then aJ=aI elseif
type(aI)==al then for aL in aI do aJ[#aJ+1]=aL end end
for aM,aL in ipairs(aJ)do if#ay>=aA then break end;Q()
local aN=e.join(aG,aL:gsub("/$",""))local aO=aL:sub(-1)=="/"local aP=false;if az then
local aQ,aR=pcall(string.match,aN,az)local aS,aT=pcall(string.match,aL,az)
aP=(aQ and aR)or(aS and aT)else aP=true end;if aP then
ay[
#ay+1]={aN.. (aO and"/"or""),
aO and(d.dir or d.highlight)or d.fg}end;if
aO and not aN:match("^/tos")then aD(aN,aH+1)end end end;aD(aB,0)if#ay==0 then aw("No matches found",d.dim)else for aH,aG in ipairs(ay)do
aw(aG[1],aG[2])end end;local aC=#ay..
" result(s)"if#ay>=aA then
aC=aC.." (truncated at "..aA..")"end;aw(aC,d.dim)end
b.grep=function(aw,E)
if not aw[2]then E("Usage: grep <pattern> <file>",d.dim)return end;local aA=aw[1]local az=f(aw[2])if not l(az,E)then return end;local ax=0;local ay=0
local aB=J.eachLine(e,az,function(aC)ay=
ay+1;if aC:find(aA,1,true)then
E(string.format("%4d: %s",ay,aC),d.fg)ax=ax+1 end end)if not aB then E(M..aw[2],d.error)return end
E(ax>0 and
(ax.." match(es)")or"No matches",d.dim)end
b.wc=function(E,aw)
if not E[1]then aw("Usage: wc <file>",d.dim)return end;local az=f(E[1])if not l(az,aw)then return end;local ax,ay=0,0
local aA,aB=J.eachLine(e,az,function(aC)ax=ax+1;for aD in
aC:gmatch("%S+")do ay=ay+1 end end)if not aA then aw(M..E[1],d.error)return end
aw(string.format(" Lines: %d  Words: %d  Bytes: %d  -- %s",ax,ay,aB,E[1]),d.fg)end;b.pwd=function(aw,E)E(a.cwd or"/",d.fg)end
local function y(E)
local ay,ax=nil,10;local aw=1
while aw<=#E do local az=E[aw]
if az=="-n"and E[aw+1]then
ax=tonumber(E[aw+1])or ax;aw=aw+1 elseif az:match("^%-%d+$")then ax=tonumber(az:sub(2))elseif not ay then ay=az elseif
tonumber(az)then ax=tonumber(az)end;aw=aw+1 end;return ay,ax end
local function z(E,ay,aw,ax)if e.exists and not e.exists(ay)then ax(ag..E,d.error)else
ax("Cannot read "..E..
(aw and(
": "..tostring(aw))or""),d.error)end end
b.head=function(aw,E)local ax,ay=y(aw)if not ax then E("Usage: head [-n N] <file>",d.dim)
return end;local az=f(ax)if not l(az,E)then return end
local aA=0;if not ay or ay<1 then return end
local aB,aC=J.eachLine(e,az,function(aD)E(aD,d.fg)aA=aA+1;if aA>=ay then
return false end end)if not aB then z(ax,az,aC,E)end end
b.tail=function(aw,E)local az,ax=y(aw)if not az then E("Usage: tail [-n N] <file>",d.dim)
return end;local aA=f(az)if not l(aA,E)then return end;if not ax or
ax<1 then return end;if ax>1000 then ax=1000 end;local aB,ay={},0
local aC,aD=J.eachLine(e,aA,function(aE)
ay=ay+1;aB[(ay-1)%ax+1]=aE end)if not aC then z(az,aA,aD,E)return end
for aE=math.max(1,ay-ax+1),ay do E(aB[
(aE-1)%ax+1],d.fg)end end
b.which=function(aw,E)
if not aw[1]then E("Usage: which <name>",d.dim)return end;local ax=aw[1]:lower()local ay=false;local aA=J.aliases(a)
if aA[ax]then
E(ax..": alias for '"..
aA[ax].."'",d.highlight)
E("  (expanded before dispatch; the expansion is resolved below)",d.dim)
ax=tostring(J.tokenizeSimple(aA[ax])[1]or ax):lower()ay=true end;local aC=require(N)
local az=aC.entry and aC.entry(ax)or nil
if az then local aH=az.tier or 0
E(ax..
": built-in (".. (az.category or"?")..", needs "..
J.tierName(aH)..")",d.title)if az.help then E("  "..az.help,d.fg)end;if
aH>J.liveTier(a)then
E("  You do not have the tier to run it — 'why "..ax.."'.",d.warning)end;ay=true end;local aF,aB=pcall(require,W)
local aD=aF and aB and aB.ownerOfCommand and
aB.ownerOfCommand(ax)or nil
if aD then
E(ax..": package command from '"..aD.."'",az and d.dim or d.title)
if az then E("  (shadowed by the built-in above)",d.dim)end;ay=true end;local aE,aG=J.resolveProgram(e,ax)
if aE then
E(ax..": "..aE..
(aG=="path"and"  (via PATH)"or""),ay and d.dim or
d.title)
if ay then E("  (shadowed by the entry above)",d.dim)end;ay=true end
if not ay then E(ax..": not found",d.error)
E("  Not a built-in, an installed package's command, or a program on",d.dim)
E("  /bin, /usr/bin or /tos/shell. 'help' lists what this box has.",d.dim)end end
local function H(E)local aw=require(N)
if aw.entry and aw.entry(E)then return true end;if J.mayHavePackages()then local ay,ax=pcall(require,W)
if
ay and ax and ax.ownerOfCommand and ax.ownerOfCommand(E)then return true end end;return
J.resolveProgram(e,E)~=nil end
b.open=function(aw,E)local ax=require("shell.open")local aC=J.sessionOf(a)
local aA=aC and aC.home;local ay=aw[1]
local function az()
E("Usage: open <file>                    in the program that suits it",d.dim)
E("       open with <file> [program]     every program that could, and why",d.dim)
E("       open set .<ext> <program> [--system]   choose (--system: every user)",d.dim)
E("       open unset .<ext> [--system]   forget the choice",d.dim)
E("       open list                      the choices and what packages declare",d.dim)
E("       open hints on|off              edit's suggestions",d.dim)end;if not ay then az()return end;local function aD(aG)if aG then return ax.SYSTEM_FILE end
return aA and(aA..
"/"..ax.USER_FILE)or nil end
local function aE(aG)
local aH,aI=pcall(e.exists,aG)return
ax.parseDefaults(aH and aI and e.readFile(aG)or nil)end
local function aB(aG,aH)
local aI,aJ=e.writeFile(aG,ax.serializeDefaults(aH))if not aI then
E("Not saved: "..tostring(aJ or aG),d.error)end;return aI end
local function aF(aG,aH)if not a.execOne then
E("open: the executor is unavailable",d.error)return end;local aI=a.execOne(aG.." "..ax.quote(aH),
nil,true)for aK,aJ in ipairs(aI or{})do
E(aJ[1],aJ[2])end end
if ay=="set"or ay=="unset"then local aJ=aw[#aw]==U
local aG=(aw[2]or""):gsub("^%.",""):lower()if
aG==""or not aG:match("^[%w]+$")or#aG>8 then az()return end;if aJ and not r(E)then return end
local aH=aD(aJ)if not aH then
E("There is no home directory to keep your choice in.",d.error)return end;local aI=aE(aH)
if ay=="set"then local aK=aw[3]and
aw[3]:lower()if not aK or aK==U then az()return end;if
not H(aK)then
E("'"..
aK.."' is not a command this machine has ('which "..aK.."').",d.error)return end;aI.ext[aG]=aK;if
aB(aH,aI)then
E("."..
aG.." files now open in "..aK..
(aJ and" for every user."or" for you."),d.highlight)end else aI.ext[aG]=nil;if
aB(aH,aI)then
E("."..aG..": back to the ranking.",d.highlight)end end elseif ay=="hints"then local aG=aD(false)if not aG or
(aw[2]~="on"and aw[2]~="off")then az()return end;local aH=aE(aG)aH.hints=(
aw[2]=="on")if aB(aG,aH)then
E("edit's suggestions are "..aw[2]..".",d.highlight)end elseif ay=="list"then
local aG=ax.gather(e,aA,nil,"")
local function aH(aJ,aI)local aK={}for aL in pairs(aI.ext)do aK[#aK+1]=aL end
table.sort(aK)
E(aJ.. (#aK==0 and"  (none)"or""),d.title)for aM,aL in ipairs(aK)do
E(string.format("  .%-8s %s",aL,aI.ext[aL]),d.fg)end end
aH("Your choices (~/"..ax.USER_FILE.."):",aG.user)
aH("This machine's ("..ax.SYSTEM_FILE.."):",aG.system)
E("What installed packages open:"..
(#aG.decls==0 and"  (none)"or""),d.title)
for aJ,aI in ipairs(aG.decls)do local aK={}
for aM in pairs(aI.exts)do aK[#aK+1]="."..aM end;table.sort(aK)
local aL=aI.markers and
("when a line starts "..table.concat(aI.markers," "))or(aI.as=="native"and"its own format"or
"can open")
E(string.format("  %-8s %s  %s",aI.cmd,table.concat(aK," "),aL),d.fg)end;if aG.user.hints==false then
E("edit's suggestions are off ('open hints on').",d.dim)end else local aI=ay=="with"
local aJ=aI and aw[2]or ay;if not aJ then az()return end;local aG=f(aJ)local aL,aM=pcall(e.exists,aG)if not aL or
not aM then E("open: no such file: "..aG,d.error)
return end;if
e.isDirectory and e.isDirectory(aG)then
E("open: "..aG.." is a directory ('cd' into it).",d.error)return end
local aH=ax.rank(aG,ax.gather(e,aA,aG))
if aI and not aw[3]then if#aH==0 then
E("Nothing here opens "..aG..".",d.warning)return end
E("Programs that could open "..aG..", best first:",d.title)for aO,aN in ipairs(aH)do
E(string.format("  %-8s %3d  %s",aN.cmd,aN.score,aN.why),aO==1 and
d.highlight or d.fg)end
E("'open with "..aJ..

" <program>' uses another; 'open set .".. (ax.ext(aG)or"ext").." <program>' makes it yours.",d.dim)return end
local aK=aI and aw[3]:lower()or(aH[1]and aH[1].cmd)if not aK then
E("Nothing here opens "..aG.." ('open with' lists what could).",d.warning)return end;if not aI then
E("Opening in "..aK..": "..aH[1].why..
".",d.dim)end;aF(aK,aG)end end
b.alias=function(aw,E)local az=_G._TOS and _G._TOS.profile;if not az then E(am,d.error)
return end;local aA=J.sessionOf(a)
if not aw[1]then local aG=az.load(aA)
local aF={}for aH in pairs(aG.aliases or{})do aF[#aF+1]=aH end
table.sort(aF)if#aF==0 then E("(no aliases)",d.dim)
E("Define one:  alias ll ls -l",d.dim)return end;for aI,aH in ipairs(aF)do
E(string.format(" %-12s %s",aH,aG.aliases[aH]),d.fg)end;return end;local ax=aw[1]:lower()if not ax:match("^[%w_%-]+$")then E("Bad alias name: "..
aw[1],d.error)
E("Letters, digits, underscore and hyphen only.",d.dim)return end
local ay=az.load(aA)
if not aw[2]then
if ay.aliases and ay.aliases[ax]then
E(string.format(" %-12s %s",ax,ay.aliases[ax]),d.fg)else E(ax..": not aliased",d.dim)end;return end;local aB=table.concat(aw," ",2)
local aC=tostring(J.tokenizeSimple(aB)[1]or""):lower()if aC==ax then E("An alias cannot expand to itself.",d.error)
E("To add default flags, alias to a different name.",d.dim)return end;ay.aliases=
ay.aliases or{}ay.aliases[ax]=aB;local aD,aE=az.save(ay,aA)
if
not aD then E(tostring(aE or ao),d.error)return end;J.invalidateAliases(a)
E("alias "..ax.." -> "..aB,d.highlight)end
b.unalias=function(aw,E)local az=_G._TOS and _G._TOS.profile;if not az then
E(am,d.error)return end;if not aw[1]then
E("Usage: unalias <name>",d.dim)return end;local aA=J.sessionOf(a)
local ax=aw[1]:lower()local ay=az.load(aA)
if not ay.aliases or not ay.aliases[ax]then E(
ax..": not aliased",d.dim)return end;ay.aliases[ax]=nil;local aB,aC=az.save(ay,aA)if not aB then
E(tostring(aC or ao),d.error)return end;J.invalidateAliases(a)E("Removed alias '"..
ax.."'.",d.highlight)end
b.du=function(aw,E)local ax=f(aw[1]or(a.cwd or"/"))
if not l(ax,E)then return end;local function az(aA,aB)return
aA:sub(-1)=="/"and(aA..aB)or(aA.."/"..aB)end
local function ay(aA)
if
e.isDirectory(aA)then local aB,aC=0,e.list(aA)
if type(aC)=="table"then for aE,aD in ipairs(aC)do Q()aB=aB+
ay(az(aA,aD:gsub("/$","")))end end;return aB end;return(e.size and e.size(aA))or 0 end
if e.isDirectory(ax)then local aA=e.list(ax)
if type(aA)=="table"then for aC,aB in ipairs(aA)do
local aD=aB:gsub("/$","")
E(string.format(" %8s  %s",m(ay(az(ax,aD))),aD),d.fg)end end end
E(string.format(" %8s  %s (total)",m(ay(ax)),ax),d.title)end
b.df=function(aw,E)local az,ax=pcall(require,"kernel.monitor")
E(string.format(" %-16s %8s %8s %8s  %s","Mount","Total","Used","Free","Use%"),d.title)
E(string.rep("-",math.min(q,56)),d.dim)local ay=e.mounts and e.mounts()or{}
if#ay==0 then
E("(mount info unavailable)",d.dim)else
for aB,aA in ipairs(ay)do local aC=aA.total or 0;local aD=aA.used or 0;local aF=aC-aD
local aE=aC>0 and math.floor(
aD*100/aC)or 0
local aG=(az and ax.memBar)and ax.memBar(aD,aC,8)or""
local aH=aE<80 and d.fg or(aE<95 and d.warning or d.error)
E(string.format(" %-16s %8s %8s %8s  [%s] %3d%%",(aA.mountPoint or"?"):sub(1,16),m(aC),m(aD),m(aF),aG,aE),aH)end end
if _G._TOS_ROOT_READONLY then E("",d.dim)
E("WARNING: the root filesystem is READ-ONLY.",d.error)
E("Nothing TOS writes will survive a reboot — users, logs, packages,",d.dim)
E("settings. Install to a writable drive, or unprotect this one.",d.dim)end
E("A path's own size: 'du <path>'.  Removable media + pools: 'disk'.",d.dim)end
b.mem=function(aw,E)
if aw and aw[1]=="--boot"then
local aJ=_G._TOS and _G._TOS.bootMem
if type(aJ)~="table"or#aJ==0 then
E("This boot was not profiled.",d.warning)
E("Add  memprofile = true  to /etc/boot.cfg and reboot.",d.dim)return end;E("=== Memory each boot stage used ===",d.title)
for aL,aK in
ipairs(aJ)do local aM=aJ[aL+1]
if aM then
E(string.format(" %-30s %4dK  (%dK free after)",tostring(aK.stage),math.floor((
(aK.free or 0)- (aM.free or 0))/1024),math.floor((
aM.free or 0)/1024)),d.fg)else
E(string.format(" %-30s %5dK free",tostring(aK.stage),math.floor((aK.free or 0)/1024)),d.dim)end end;return end;local aB,ax=O.freeMemory(),O.totalMemory()local aC=ax-aB;local ay=ax>0 and math.floor(
aC*100/ax)or 0
local aF,aE=pcall(require,"kernel.monitor")local aA=math.min(24,math.max(8,q-36))
local aG=
(aF and aE.memBar)and aE.memBar(aC,ax,aA)or
(
string.rep("#",math.floor(ay/100*aA))..string.rep("-",aA-math.floor(ay/100*aA)))E("=== Memory ===",d.title)
E(string.format(" RAM:  %dK used / %dK total   (%d%% used, %dK free)",math.floor(
aC/1024),math.floor(ax/1024),ay,math.floor(aB/1024)),d.fg)
local aH=ay<75 and d.highlight or(ay<90 and d.warning or d.error)E(" ["..aG.."]",aH)
local aI,az=pcall(function()
return h.getHAL().systemInfo()end)if aI and az and(az.memTierName or az.memTier)then
E(
" Tier: ".. (az.memTierName or("T"..az.memTier)),d.dim)end
local aD=h.getSwap and h.getSwap()
if aD and aD.usage then local aK,aJ=pcall(aD.usage)
if aK and type(aJ)=="table"then
E(string.format(" Swap: %dK / %dK on /var/swap   ('slow RAM' overflow)",math.floor((
aJ.bytes or 0)/1024),math.floor((aJ.max or 0)/1024)),d.dim)end else
E(" Swap: off   (enable in Boot Settings for low-RAM overflow)",d.dim)end;if aB<16*1024 then
E(" ! Low memory — near the ~16K danger zone.",d.warning)end
E("Live usage: 'monitor'.  Hardware tiers: 'hw'.",d.dim)end
b.hw=function(aw,E)local ax=h.getHAL().systemInfo()
E("=== Hardware ===",d.title)
E(string.format(" CPU T%d    GPU T%d    RAM %s",ax.cpuTier or 0,ax.gpuTier or 0,ax.memTierName or("T"..
(ax.memTier or 0))),d.fg)local az,ay=pcall(require,"kernel.datacard")if
az and ay and ay.detect then local aA=ay.detect()
E(" Data card: "..
(aA.present and aA.name or"none"),aA.present and d.fg or d.dim)end
E(string.format(" Components: %d    Network: %s    Tunnel: %s",
ax.components or 0,ax.canNetwork and"yes"or"no",ax.hasTunnel and"yes"or"no"),d.dim)
E("Full component list: 'devices'.  Memory detail: 'mem'.  Live: 'monitor'.",d.dim)end;b.hardware=b.hw
b.ps=function(aw,E)local aA=u.getForeground(a.displayIdx)
local ax=J.sessionOf(a)local ay=(ax and ax.tier)or 0
local aB=ax and ax.user or"?"
local az=(aw[1]=="-v"or aw[1]=="--verbose")and ay>=2
if az then
E(string.format(" %-4s %-14s %-8s %-3s %-10s %-6s %s","PID","Name","State","DSP","Owner","CPU","Caps"),d.title)else
E(string.format(" %-4s %-16s %-8s %-3s %-10s %s","PID","Name","State","DSP","Owner","CPU"),d.title)end
E(string.rep("-",az and 70 or 50),d.border)
for aD,aC in ipairs(u.list())do local aE=aC.user or"?"
if aE=="_kernel_"then aE="kernel"end;local aF=false
if ay>=2 then aF=true elseif ay>=1 and aE==aB then aF=true elseif ay>=1 then aF="redacted"end
if aF==true then local aH=d.fg;local aG=aC.state;if aC.tsr then aG="TSR"end;if aC.pid==aA then
aH=d.highlight;aG=aG.." *"elseif aC.tsr then aH=d.dim end
if az then local aI={}if
aC.caps then for aJ in pairs(aC.caps)do aI[#aI+1]=aJ end
table.sort(aI)end
E(string.format(" %-4d %-14s %-8s %-3s %-10s %-6.1f %s",aC.pid,aC.name:sub(1,14),aG,tostring(
aC.display or"-"),(aE):sub(1,10),aC.cpuTime or 0,#aI>0 and
table.concat(aI,",")or"-"),aH)else
E(string.format(" %-4d %-16s %-8s %-3s %-10s %.1fs",aC.pid,aC.name:sub(1,16),aG,tostring(aC.display or"-"),(aE):sub(1,10),
aC.cpuTime or 0),aH)end elseif aF=="redacted"then
E(string.format(" %-4d %-16s %-8s %-3s %-10s   ",aC.pid,"(other user)","?","?","?"),d.dim)end end;E("",d.dim)
E(" * = foreground  |  -v for caps (admin+)  |  'monitor' for the live view",d.dim)end
b.monitor=function(aw,E)local ay,ax=pcall(require,"shell.panels.monitorapp")if not ay then
E(
"Monitor unavailable: "..tostring(ax),d.error)return end;ax.open(a)end;b.top=b.monitor
b.watch=function(aw,E)
if not aw[1]then
E("Usage: watch [seconds] <command ...>",d.dim)
E("  Opens a self-updating tab. e.g.  watch ps  ·  watch 2 df  ·  watch mem",d.dim)return end;local az,ax=1,tonumber(aw[1])if ax then az=2 else ax=1 end;if ax<1 then ax=1 end;if not
aw[az]then E("Usage: watch [seconds] <command ...>",d.dim)
return end
local aA=table.concat(aw," ",az)
local ay=(aA:match("^(%S+)")or""):lower()
local aB={edit=true,lua=true,monitor=true,top=true,watch=true,launcher=true,launch=true,apps=true,kiosk=true,chat=true,more=true,man=true,vault=true,keychain=true,passwd=true,tutorial=true,bootsettings=true,useradd=true,["tape-auth"]=true}if aB[ay]then
E("Can't watch '"..ay.."' — it's interactive/screen-driven.",d.error)return end;do
local aD,aE,aF=J.tierRefusal(a,ay)
if aD then E(aD,d.error)a.lastDenial={cmd=ay,need=aE,have=aF}return end end;if not c.openLiveTab then
E("Live tabs aren't available in this shell.",d.error)return end
local function aC()local aD={}local aE={}for aM in
aA:gmatch("%S+")do aE[#aE+1]=aM end;if#aE==0 then return aD end
local aF=aE[1]:lower()local aH={}for aM=2,#aE do aH[#aH+1]=aE[aM]end
local aI=J.tierRefusal(a,aF)if aI then aD[#aD+1]={aI,d.error}return aD end;local aG=b[aF]
if
not aG then local aN,aM=pcall(require,W)if aN and aM and aM.getCommand then
aG=aM.getCommand(aF)end end;if not aG then
aD[#aD+1]={"Unknown command: "..aF.."  [E-801 ERR_UNKNOWN_CMD]",d.error}return aD end
local aJ=function(aM,aN)aD[#aD+1]={tostring(aM),
aN or d.fg}end;local aK,aL=pcall(aG,aH,aJ)if not aK then
aD[#aD+1]={"Error: "..tostring(aL),d.error}end;return aD end;c.openLiveTab("watch: "..aA,aC,ax)end
b.why=function(aw,E)local aD=require(N)local az=J.liveTier(a)
local ax={title=d.title or d.highlight or d.fg,ok=
d.success or d.highlight or d.fg,err=d.error,fix=d.highlight or d.fg,dim=d.dim}local function ay(aE)
for aG,aF in ipairs(aE)do E(aF.text,ax[aF.tone]or d.fg)end end
local aA=aw and aw[1]and aw[1]:lower()
if not aA then local aE=a.lastDenial
if aE and aE.cmd then
ay(J.whyExplain(aE.cmd,aE.need,aE.have or az,true))return elseif aE then
E("Your last blocked action needed "..J.tierName(aE.need).."; you are "..
J.tierName(aE.have or az)..".",d.error)
E("Fix: run it on an admin/root account, or have an admin grant access.",ax.fix)return end;local aF=a.lastFailure
if aF then
E((aF.cmd and(aF.cmd.." failed:")or
"The last action failed:"),ax.title)E("  "..aF.text,d.error)
local aG,aI,aH=J.explainFailure(aF.text)if aH then E("  "..aH,ax.dim)end
if aG then ay(aG)else
E("No canned explanation for that one.",d.dim)
E("`log` has the kernel's own record of it, and `doctor` checks",d.dim)
E("memory, disks, services and security for a cause.",d.dim)end;return end
E("Nothing has failed since the last command ran.",d.dim)
E("why            — explain the last refusal or error.",d.dim)
E("why <code>     — explain an error code: E-402, ERR_PATH_PROTECTED, K4.",d.dim)
E("why <command>  — explain what a command needs and whether you can run it.",d.dim)return end;local aC=J.explainCode(aw[1])if aC then ay(aC)return end
local aB=aD.entry(aA)
ay(J.whyExplain(aA,aB and aB.tier or 0,az,aB~=nil))end
b.screendump=function(aw,E)if not n or not n.dump then
E("Screen capture isn't available on this seat.",d.error)return end
local aE,az=pcall(n.dump)if not aE or type(az)~="table"or not az.lines then
E("Screen capture failed.",d.error)return end
local aB=(aw and aw[1])and
f(aw[1])or
f("screen-"..math.floor(h.uptime())..".txt")
local aF=(J.sessionOf(a)or{}).user or"?"
local aD=string.format("TOS screendump — seat %s · user %s · %dx%d · uptime %ds · read from the %s",tostring(a.displayIdx or"?"),aF,
az.w or 0,az.h or 0,math.floor(h.uptime()),tostring(az.source or"?"))local ax=string.char(10)local ay=aD..
ax..string.rep("-",#aD)..ax..
table.concat(az.lines,ax)..ax
if az.bg then
ay=ay..ax..
"--- background colour runs, per row ---"..ax
for aJ=1,(az.h or 0)do local aK=az.bg[aJ]
if aK then local aL={}for aN,aM in ipairs(aK)do
aL[#aL+1]=string.format("%d-%d:%s",aM.from,aM.to,
aM.c and string.format("%06X",aM.c)or"nil")end
ay=ay..
string.format("row %2d  %s",aJ,table.concat(aL,"  "))..ax end end;local aI=a.T or{}
ay=ay..
ax..
"theme: bg="..
string.format("%06X",aI.bg or 0)..
"  statusbar_bg="..string.format("%06X",
aI.statusbar_bg or 0)..
"  menubar_bg="..string.format("%06X",
aI.menubar_bg or aI.bar_bg or 0)..ax end;local aA=function(aI)
return aI and string.format("%06X",aI)or"nil"end;ay=ay..ax..
"--- cache vs glass ---"..ax
if
az.disagree and#az.disagree>0 then
ay=ay.."THE SHADOW DISAGREES WITH THE SCREEN on "..#az.disagree..
" row(s)."..ax
for aJ,aI in ipairs(az.disagree)do
ay=ay..
string.format("  row %2d col %2d  glass=%s  shadow believes=%s",aI.row,aI.col,aA(aI.glass),aA(aI.shadow))..ax;local aK=az.pageBg and az.pageBg[aI.row]
if aK then local aL={}for aJ,aM in
ipairs(aK)do
aL[#aL+1]=string.format("%d-%d:%s",aM.from,aM.to,aA(aM.c))end
ay=ay.."    off-screen page holds: "..
table.concat(aL,"  ")..ax end end elseif az.shadowBg then
ay=ay.."none — the shadow matches the glass everywhere."..ax else
ay=ay.."(no shadow active on this seat)"..ax end;local i=az.state
if i then
ay=ay..
ax..
"--- display machinery ---"..
ax..
"  shadow="..
tostring(i.shadow)..
"  colour cache: fg="..

aA(i.lastFg)..
" bg="..
aA(i.lastBg)..
ax..
"  backbuffer="..
tostring(i.backbuffer)..
"  broken="..
tostring(i.backBroken)..

"  frameDepth="..
tostring(i.frameDepth)..
"  pageStale="..
tostring(i.pageStale)..ax..
"  writerGen="..
tostring(i.writerGen)..
"  mine="..tostring(i.myWriterGen).."  lastWriterIsMe="..
tostring(i.lastWriterIsMe)..ax end;local aC=_G._TOS and _G._TOS.fs;if
not(aC and aC.writeFile)then
E("No filesystem available to write the dump.",d.error)return end
local aG,aH=aC.writeFile(aB,ay)
if aG then
E("Screen captured -> "..aB.."  (".. (az.h or 0).." rows)",
d.success or d.fg)
E("Attach it to a bug report, or 'cat' it to read it back.",d.dim)else
E("Could not write "..aB..": "..tostring(aH),d.error)end end
b.crash=function(aw,E)if not r(E)then return end;local ax=_G._TOS and _G._TOS.fs
if not
(ax and ax.list)then E("No filesystem.",d.error)return end
if aw and aw[1]then local aB=aw[1]:find("/")and f(aw[1])or
("/var/crash/"..aw[1])
local aD,aC=pcall(ax.readFile,aB)if not aD or not aC then
E("No such crash report: "..aB,d.error)return end;for aE in
(tostring(aC).."\n"):gmatch("(.-)\n")do E(aE,d.fg)end;return end;local aA,az=pcall(ax.list,"/var/crash")local ay={}if
aA and type(az)=="table"then
for aC,aB in ipairs(az)do aB=tostring(aB):gsub("/$","")if
aB~=""and aB~="NEW"then ay[#ay+1]=aB end end end
if#ay==0 then
E("No crash reports — clean so far.",d.dim)
E("(TOS saves one here on a panic or an unrecoverable shell, so you",d.dim)E(" can read it after rebooting.)",d.dim)return end
E("Crash reports in /var/crash:",d.title or d.highlight or d.fg)for aC,aB in ipairs(ay)do E("  "..aB,d.fg)end
E("Read one with:  crash <name>",d.dim)end
b.history=function(aw,E)for ax,ay in ipairs(a.cmdHistory)do
E(string.format(" %3d  %s",ax,ay),d.dim)end;if#a.cmdHistory==0 then
E("(no history)",d.dim)end end
b.uptime=function(aw,E)local ax=h.uptime()local ay=math.floor(ax/3600)local az=math.floor(
(ax%3600)/60)local aA=math.floor(ax%60)
E(string.format("Uptime: %dh %dm %ds (%.1fs total)",ay,az,aA,ax),d.fg)end
b.date=function(aw,E)
local ax=h.getConfig and h.getConfig()or nil
if aw[1]=="tz"or aw[1]==Z or aw[1]=="set"then local aE=(ax and ax.get and
ax.get(Z))or 0
local aD=tonumber(aw[2])
if not aD then E("Timezone offset: "..aE.."h",d.fg)
E("Usage: date tz <hours>   e.g. 'date tz -5'",d.dim)
E("OpenComputers has no settable clock; this only shifts the",d.dim)
E("DISPLAYED time relative to the world/host clock.",d.dim)return end;if aD<-23 or aD>23 then
E("Offset must be between -23 and 23.",d.error)return end;if not r(E)then return end
if not
(ax and ax.set)then E("No writable config available.",d.error)return end;ax.set(Z,aD)if ax.save then ax.save()end
E("Timezone offset set to "..aD.."h. (was "..
aE.."h)",d.highlight)return end;local az=aw[1]or"%Y-%m-%d %H:%M:%S"local aA=
(ax and ax.get and ax.get(Z))or 0
local aB=os.time()+ (aA*3600)local aC,ay=pcall(os.date,az,aB)if aC and ay then
E(tostring(ay),d.fg)else
E(tostring(ay or"date error"),d.error)end end;b.time=b.date
b.keys=function(aw,E)local aF,ax=pcall(require,Y)if not aF or not ax then
E("Keybind module unavailable.",d.error)return end
local ay=(aw[1]or"list"):lower()local az=false;for aH=2,#aw do
if aw[aH]==U then az=true;table.remove(aw,aH)break end end
local aG=(a.who=="root")and"/root"or(
"/home/".. (a.who or""))
local aB=az and"/etc/keys.cfg"or(aG.."/.keys.cfg")local aD,aA=pcall(require,"kernel.serialize")
local function aE()
if not(aD and aA and
a.F.exists(aB))then return{}end;local aH=a.F.readFile(aB)if not aH then return{}end
local aJ,aI=pcall(aA.decode,aH,{maxBytes=8192})return
(aJ and type(aI)=="table")and aI or{}end
local function aC(aH)if not(aD and aA)then return false end
local aI=a.F.writeFile(aB,aA.encode(aH))if aI then ax.reload()end;return aI end
if ay=="list"or ay=="ls"then
E("TOS standard shortcuts:",d.title)for aI,aH in ipairs(ax.actions(a.who))do
E(string.format("  %-9s %-14s %s",aH.action,aH.keys,aH.help),
aH.isDefault and d.fg or d.highlight)end
E("",d.dim)
E("Reserved by the kernel — these cannot be rebound:",d.dim)for aI,aH in ipairs(ax.reserved())do
E(string.format("  %-9s %s",aH.key,aH.help),d.dim)end;E("",d.dim)
E("Change one:  keys set quit F4       (add --system for everyone)",d.dim)E("Undo:        keys reset [action]",d.dim)
E("Every first-party TOS program follows this table.",d.dim)elseif ay=="set"then local aH,aK=aw[2],aw[3]
if not(aH and aK)then
E("Usage: keys set <action> <key> [<key>...]",d.dim)
E("  e.g. keys set quit F4      keys set find ^F",d.dim)
E("Key names are written the way you say them: ^Q, F10, Ctrl+S, /",d.dim)return end;if not ax.DEFAULTS[aH]then
E("No such action: "..aH.."  (see 'keys list')",d.error)return end;local aI={}
for aL=3,#aw do local aM=aw[aL]if not
ax.parse(aM)then
E("Not a key name: '"..aM.."'  (try ^Q, F10, Ctrl+S, /)",d.error)return end
if ax.isReserved(aM)then
E(aM..
" is reserved by the kernel and never reaches a program.",d.error)E("See 'keys list' for the reserved set.",d.dim)return end;aI[#aI+1]=aM end;local aJ=aE()aJ[aH]=aI
if aC(aJ)then
E(aH..
" is now "..table.concat(aI," ").. (az and"  (machine-wide)"or
""),d.highlight)else E(ah.. (az and T or"."),d.error)end elseif ay=="reset"then local aH=aw[2]local aI=aE()
if aH then if not ax.DEFAULTS[aH]then
E("No such action: "..aH,d.error)return end;aI[aH]=nil;if aC(aI)then
E(aH.." is back to the default.",d.highlight)else E(ai,d.error)end else if aC({})then
E("All shortcuts back to the defaults.",d.highlight)else E(ai,d.error)end end else
E("keys — TOS's standard keyboard shortcuts",d.title)
E("  keys list                     Show them",d.fg)
E("  keys set <action> <key>...    Rebind one",d.fg)
E("  keys reset [action]           Back to the default",d.fg)
E("Add --system to change them for every user (/etc/keys.cfg, admin).",d.dim)end end
b.menu=function(aw,E)local ax=(aw[1]or"list"):lower()local az=false
for aH=2,#aw do if
aw[aH]==U then az=true;table.remove(aw,aH)break end end;local aF=(a.who=="root")and"/root"or
("/home/".. (a.who or""))local ay=
az and"/etc/menu.cfg"or(aF.."/.menu.cfg")
local aG,aD=pcall(require,"kernel.serialize")
if not aG or not aD then E("serialize unavailable",d.error)return end
local function aA()if not a.F.exists(ay)then return{}end
local aH=a.F.readFile(ay)if not aH then return{}end
local aJ,aI=pcall(aD.decode,aH,{maxBytes=8192})return
(aJ and type(aI)=="table")and aI or{}end
local function aB(aH)return a.F.writeFile(ay,aD.encode(aH))end;local function aC()local aI,aH=pcall(require,"shell.panels.draw")
if
aI and aH and aH.buildMenuDefs then a.menuDefs=aH.buildMenuDefs(a)end end
local function aE(aH)if
aH.remove then
return"remove "..tostring(aH.remove)..
(aH.menu==true and" (whole menu)"or"")end;if aH.rename then return
"rename "..
tostring(aH.rename).." -> "..tostring(aH.to)end;if
aH.move then return
"move "..tostring(aH.move).." -> "..tostring(aH.menu)end
if aH.menu and not
aH.cmd then return"new menu "..tostring(aH.menu)end;return
string.format("[%s] %s -> %s",aH.menu or"Tools",aH.add or aH.label or"?",aH.cmd or"?")end
if ax=="list"or ax=="ls"then local aH=aA()
if#aH==0 then
E("No menu edits in "..ay..".",d.dim)
E("Add one:  menu add <label> <command...> [in <Menu>]",d.dim)
E("Machine-wide instead of just you:  menu add ... --system",d.dim)return end;E("Menu edits ("..ay.."):",d.title)for aI,aJ in ipairs(aH)do
E(string.format("  %d. %s",aI,aE(aJ)),d.fg)end elseif ax=="show"then
local aI,aH=pcall(require,"shell.panels.draw")if not aI or not aH or not aH.buildMenuDefs then
E("Menu system unavailable.",d.error)return end
for aK,aJ in
ipairs(aH.buildMenuDefs(a))do E(aJ.label,d.title)
for aK,aL in ipairs(aJ.items)do if aL.sep then E("    ---",d.dim)else
E(string.format("    %-20s %s",aL.label,(
aL.action or""):match("^run:(.+)$")or(aL.action or"")),d.fg)end end end
E("Change it with: menu add|remove|rename|move  (add --system for everyone)",d.dim)elseif ax==an or ax=="move"then local aI,aJ=aw[2],aw[3]if not(aI and aJ)then
E("Usage: menu "..ax..

" <name> <".. (ax==an and"new name"or"Menu")..">",d.dim)return end;local aH=aA()
aH[#aH+1]=(
ax==an)and{rename=aI,to=aJ}or{move=aI,menu=aJ}
if aB(aH)then aC()
E("Saved. "..aE(aH[#aH]),d.highlight)else E(ah.. (az and T or"."),d.error)end elseif ax=="hide"then local aH=aw[2]if not aH then
E("Usage: menu hide <item or Menu name>",d.dim)
E("Hides a built-in entry. 'menu reset' brings everything back.",d.dim)return end
local aI=aA()
aI[#aI+1]={remove=aH,menu=(aw[3]=="menu")or nil}
if aB(aI)then aC()E("Hidden: "..aH,d.highlight)else E(ah..
(az and T or"."),d.error)end elseif ax=="reset"then if aB({})then aC()
E("Menu reset to the built-in bar ("..ay.." cleared).",d.highlight)else
E("Reset failed".. (az and T or"."),d.error)end elseif
ax=="add"then local aI=aw[2]
if not aI or not aw[3]then
E("Usage: menu add <label> <command...> [in <Menu>]",d.dim)
E("  e.g. menu add Tetris tetris   |   menu add Disk df in System",d.dim)return end;local aH=table.concat(aw," ",3)
local aJ=aH:match("%s+in%s+(%S+)%s*$")if aJ then aH=aH:gsub("%s+in%s+%S+%s*$","")end
if
#aI>24 then E("Label too long (max 24).",d.error)return end;if#aH==0 or#aH>200 then
E("Command empty or too long.",d.error)return end;local aK=aA()
aK[#aK+1]={label=aI,cmd=aH,menu=aJ or"Tools"}
if aB(aK)then aC()
E(string.format("Added '%s' -> %s  (menu: %s)",aI,aH,aJ or"Tools"),d.highlight)else E("Save failed (is your home writable?).",d.error)end elseif ax=="remove"or ax=="rm"or ax=="del"then
local aH=tonumber(aw[2])local aI=aA()if not aH or not aI[aH]then
E("Usage: menu remove <#>   (see 'menu list')",d.error)return end
local aJ=table.remove(aI,aH)if aB(aI)then aC()
E("Removed '".. (aJ.label or"?").."'.",d.highlight)else E(ai,d.error)end else
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
b.tree=function(aw,E)local az=f(aw[1]or a.cwd)
local aC=tonumber(aw[2])or 3;local aA=400;local ax,ay=0,false
local function aB(aD,aE,aF)if ay then return end;if aF>aC then return end
local aG=e.list(aD)or{}
table.sort(aG,function(aH,aI)
local aJ=e.isDirectory(aD.."/".. (aH:gsub("/$","")))
local aK=e.isDirectory(aD.."/".. (aI:gsub("/$","")))if aJ~=aK then return aJ end;return aH<aI end)
for aH,aI in ipairs(aG)do if ax>=aA then ay=true;return end;local aJ=aI:gsub("/$","")
local aL=aD=="/"and(
"/"..aJ)or(aD.."/"..aJ)local aK=e.isDirectory(aL)local aM=(aH==#aG)
local aN=aM and"`-- "or"|-- "local aO=aK and d.dir or d.fg;E(aE..
aN..aJ.. (aK and"/"or""),aO)ax=ax+1;if aK then
aB(aL,aE.. (aM and"    "or
"|   "),aF+1)end end end;E(az,d.title)aB(az,"",1)if ay then
E(string.format("(truncated at %d entries; raise the limit or narrow the path)",aA),d.dim)end end
b.whoami=function(aw,E)if g then local ax=g.getSession(i)
E(ax and ax.user or"root",d.fg)else E(a.who,d.fg)end end
b.passwd=function(aw,E)
if not g then E("No user system",d.error)return end;local az=j("Current password: ",64,true)if not az then return end
local ax=j("New password: ",64,true)if not ax then return end;local aD=j("Confirm new password: ",64,true)if
aD~=ax then
a.lastOut={"Passwords do not match — unchanged.",d.error}return end;if ax==""then
a.lastOut={"Password cannot be empty.",d.error}return end;local aA=g.getSession(i)local aB=
aA and aA.user or"root"
local aC,ay=g.changePassword(aB,aB,az,ax)
if aC and ay then
a.lastOut={"Password changed. "..tostring(ay),d.warning}elseif aC then a.lastOut={"Password changed.",d.highlight}else
a.lastOut={tostring(ay),d.error}end end
local function I(E,aw,ax)local aB=a.st
local az=g.registerSession and g.registerSession(E)or nil;local aC,aA=pcall(require,X)
local ay=aC and aA.current and aA.current()local aD=ay and ay.principal;if az then a.st=az end
if ay then ay.principal=E end;local aE,aF=pcall(aw)a.st=aB;if ay then ay.principal=aD end;if az and g.logout then
pcall(g.logout,az)end;if not aE then
ax("sudo: "..tostring(aF),d.error)end end
local function t()if not a._sudo then return false end;a.st=a._sudo.origSt
local ax,E=pcall(require,X)local aw=ax and E.current and E.current()if aw then
aw.principal=a._sudo.origPrincipal end;if a._sudo.token and g.logout then
pcall(g.logout,a._sudo.token)end;a._sudo=nil;return true end;a.sudoDrop=t
b.sudo=function(aw,E)
if not g then E("No user system",d.error)return end;local az=J.sessionOf(a)local ax=aw[1]
if ax=="setup"then if not w(E)then return end;local aF=2;if
aw[2]=="root"then aF=3 elseif aw[2]and aw[2]~="admin"then
E("Usage: sudo setup [admin|root]",d.dim)return end
local aE=j("New elevation password: ",64,true)if not aE or aE==""then E("Aborted.",d.dim)return end
if
j("Confirm: ",64,true)~=aE then E("Passwords do not match.",d.error)return end;local aG,aH=g.setElevation(az,aE,aF)
if aG then
E("Elevation configured (cap: "..
J.tierName(aF)..").",d.highlight)else E(tostring(aH),d.error)end;return elseif ax=="off"then if not w(E)then return end
local aE,aF=g.clearElevation and g.clearElevation(az)if aE then E("Elevation disabled.",d.highlight)else
E(tostring(aF or"unavailable"),d.error)end;return elseif ax=="-k"then
E(
t()and"Elevated session dropped."or"No active elevation.",d.dim)return end;if not ax then
E("Usage: sudo <command> | sudo -s | sudo -k | sudo setup [admin|root] | sudo off",d.dim)return end
if
J.liveTier(a)<1 then E("sudo: guests cannot elevate.",d.error)return end
local aB=g.elevationInfo and g.elevationInfo()or{configured=false}if not aB.configured then
E("sudo: elevation is not configured. Root: sudo setup [admin|root]",d.warning)return end
local aA=j("[sudo] elevation password: ",64,true)if aA==nil then E("Aborted.",d.dim)return end
local ay,aC=g.elevate(az,aA)if not ay then
E("sudo: "..tostring(aC or"elevation failed"),d.error)return end
if ax=="-s"then t()
local aF=g.registerSession and
g.registerSession(ay)or nil;local aH,aG=pcall(require,X)
local aE=aH and aG.current and aG.current()
a._sudo={origSt=a.st,origPrincipal=aE and aE.principal,token=aF}if aF then a.st=aF end;if aE then aE.principal=ay end
E("Elevated to "..
J.tierName(ay.tier)..". 'sudo -k' or 'logout' drops it.",d.highlight)return end;local aD=table.concat(aw," ")
I(ay,function()if not a.execOne then
E("sudo: executor unavailable",d.error)return end;local aE=a.execOne(aD)if
type(aE)=="table"then
for aG,aF in ipairs(aE)do if type(aF)=="table"then E(aF[1],aF[2]or d.fg)else
E(tostring(aF),d.fg)end end end end,E)end;b.logout=function(E,aw)J.logout(a)end
b.cli=function(aw,E)if a.isCLI then
E("You are already at the command line. Type 'tui' for the full interface.",d.dim)return end;a._exitTo="cli"end
b.tui=function(aw,E)if a.isCLI then E("Returning to the full interface…",d.dim)
a._exitTo="tui"return end
E("You are already in the full interface. Type 'cli' for the command line.",d.dim)end
b.reboot=function(aw,E)local ax,ay=J.canPowerOff(a)
if not ax then E(ay,d.error)return end;h.reboot()end
b.shutdown=function(aw,E)local ax,ay=J.canPowerOff(a)
if not ax then E(ay,d.error)return end;h.shutdown()end
b.env=function(E,aw)local aA,ax=pcall(require,"kernel.env")if not aA then
aw("Env module unavailable",d.error)return end;local az=h.getProc()local ay=
az and az.current()or nil
if E[1]then
local aB,aC=E[1]:match("^([%w_]+)=(.*)$")if aB then ax.write(ay,aB,aC)aw(aB.."="..aC,d.highlight)else
local aD=ax.read(ay,E[1])
aw(E[1].."="..tostring(aD or""),d.fg)end else
local aB=ax.list(ay)for aC,aD in pairs(aB)do
aw("  "..aC.."="..tostring(aD),d.fg)end end end;b.export=b.env;b.set=b.env
b["tape-menu"]=function(aw,E)
local aE,ay=pcall(require,"shell.launcher")if not aE or not ay then
E("Menu engine unavailable (low RAM?)",d.error)return end;if not n or not n.getSize then
E("tape-menu needs a screen.",d.error)return end;local az=nil
local function aF(aL)local aM={}local aN={}for aV in
aL:gmatch("%S+")do aN[#aN+1]=aV end;if#aN==0 then return aM end
local aO=aN[1]local aQ={}for aV=2,#aN do aQ[#aQ+1]=aN[aV]end
local aR=J.tierRefusal(a,aO:lower())if aR then aM[#aM+1]={aR,d.error}return aM end;if not az then
az=require(N).build(a,c)end;local aP=az[aO]
if not aP then local aW,aV=pcall(require,W)if aW and aV and
aV.getCommand then aP=aV.getCommand(aO)end end;if not aP then
aM[#aM+1]={"Unknown command: "..aO,d.error}return aM end;local aS=function(aV,aW)
aM[#aM+1]={tostring(aV),aW or d.fg}end
local aT,aU=pcall(aP,aQ,aS)if not aT then
aM[#aM+1]={"Error: "..tostring(aU),d.error}end;return aM end;local aB=P.list and P.list("tape_drive")()
if
not aB then E("No tape drive found.",d.error)return end;local ax=P.proxy(aB)
local aG,aH=pcall(function()return ax.isReady()end)
if not aG or not aH then E("No tape inserted.",d.warning)return end
local aI=(ax.getSize and ax.getSize())or 0
if aI<=0 then E("Tape is empty.",d.warning)return end
local aA=j and j("Tape menu passphrase: ",64,true)or nil;if not aA or aA==""then E(ad,d.dim)return end
local aJ,aC=pcall(require,"kernel.vault")
if not aJ or not aC then E("vault unavailable",d.error)return end;local aD,aK=ay.readTapeMenuFromDrive(ax,aA,aC)if not aD then
E(tostring(aK),d.error)return end
ay.run({display=n,profile=aD,runLine=aF,title="Tape toolbox"})if c.drawAll then pcall(c.drawAll)end end
b.clip=function(aw,E)local aA,ax=pcall(require,"kernel.clipboard")if not aA or not ax then
E(
"Clipboard unavailable: "..tostring(ax),d.error)return end;local ay=a.displayIdx;local az=aw[1]
if
not az then
E("Clipboard: "..ax.describe(ay),d.title)local aB=ax.get(ay)
if aB and not ax.isEmpty(ay)then
local aC=math.min(#aB,10)for aD=1,aC do E("  "..aB[aD],d.fg)end;if#aB>aC then
E("  ... "..
(#aB-aC).." more line(s)",d.dim)end end
E("Usage: clip [set <text> | clear]   Copy: "..
(function()local aD,aC=pcall(require,Y)
return(aD and aC)and
aC.label("copy",a.who)or"Ctrl+Insert"end)(),d.dim)return end;if az=="clear"then ax.clear(ay)
E("Clipboard cleared.",d.highlight)return end
if az=="set"then
local aB=table.concat(aw," ",2)
if aB==""then E("Usage: clip set <text>",d.warning)return end;local aD,aC=ax.set(aB,ay)if not aD then
E("Could not set clipboard: "..tostring(aC),d.error)return end;if aC then
E("Clipboard set, TRUNCATED at the cap: "..
ax.describe(ay),d.warning)else
E("Clipboard: "..ax.describe(ay),d.highlight)end;return end;E("Usage: clip [set <text> | clear]",d.warning)end
b.desktop=function(aw,E)local ay,ax=pcall(require,"shell.panels.desktop")if not ay then
E(
"Desktop unavailable: "..tostring(ax),d.error)return end;ax.open(a)end
b.settings=function(aw,E)local ay,ax=pcall(require,"shell.panels.settingsapp")if
not ay then
E("Settings unavailable: "..tostring(ax),d.error)return end;ax.open(a)end
b.lang=function(aw,E)local aB,ax=pcall(require,"kernel.i18n")if not aB or not ax then
E(
"i18n unavailable: "..tostring(ax),d.error)return end;local ay=aw[1]
if not ay then
E(af..ax.language()..
"  ("..ax.languageName()..")",d.title)E("Installed catalogs:",d.fg)for aG,aF in ipairs(ax.available())do
local aH=(aF.code==
ax.language())and" * "or"   "
E(aH..string.format("%-8s %s",aF.code,aF.name),d.fg)end
E("Usage: lang <code> | lang system <code> | lang dump [path]",d.dim)
E("Catalogs are DATA files at /usr/lang/<code>.lang — see 'man lang'.",d.dim)return end
if ay=="system"then if not r(E)then return end;local aF=aw[2]if not aF then
E("Usage: lang system <code|en>",d.dim)return end;local aG,aH=ax.setLanguage(aF)
if not aG then E(
"Cannot set: "..tostring(aH),d.error)return end
if p and p.set then p.set("language",aF)if p.save then p.save()end end
E("System language: "..ax.language(),d.highlight)return end
if ay=="dump"then
local aG=f(aw[2]or"/tmp/lang-template.lang")local aH=ax.keysSeen()if#aH==0 then
E("No keys seen yet — visit a few screens first (log out/in, open the Desktop).",d.warning)return end
local aF={"-- TOS language catalog template (every t() key seen this session).","-- Translate the values, set meta.code/name, save as /usr/lang/<code>.lang,","-- then run `lang <code>`. Untranslated keys keep their English default.","-- /usr is a protected system path: as root, `protect off` to copy this","-- in and `protect on` after -- or ship the catalog as a package.","return {",'  meta = { code = "xx", name = "Language name" },',"  strings = {"}for aL,aK in ipairs(aH)do
aF[#aF+1]=string.format("    [%q] = %q,",aK.key,aK.default)end;aF[#aF+1]="  },"
aF[#aF+1]="}"
if not o(aG)then E("Cannot write: "..aG,d.error)return end
local aJ,aI=e.writeFile(aG,table.concat(aF,"\n").."\n")
if aJ then
E("Template with "..#aH.." key(s) -> "..aG,d.highlight)k()else E(aj..aG,d.error)
if aI then E(tostring(aI),d.dim)end
if aG:sub(1,10)=="/usr/lang/"then
E("Dump to /tmp (the default), then copy it in under `protect off`,",d.dim)E("or ship the catalog as a package.",d.dim)end end;return end;local aC,aD=ax.setLanguage(ay)if not aC then
E("Cannot set '"..tostring(ay)..
"': "..tostring(aD),d.error)E("Run 'lang' to list installed catalogs.",d.dim)
return end
local aA=J.sessionOf(a)local aE,az=pcall(require,"kernel.profile")
if aE and az and az.load and
az.save then local aF=az.load(aA)
aF.lang=
(ax.language()~="en")and ax.language()or nil;local aG,aH=az.save(aF,aA)
if aG then
E(af..
ax.language().."  (saved to your profile)",d.highlight)else
E("Language set for this session (profile save failed: "..tostring(aH)..")",d.warning)end else
E(af..ax.language().."  (this session)",d.highlight)end end end