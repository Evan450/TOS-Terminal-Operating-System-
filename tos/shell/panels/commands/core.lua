
local _,K,aa,S,T,ab,L,ac,ad,ae,af,ag,ah,ai,J,aj,U,V,ak,al,am,W,M,X="  Examples:","  Subcommands:"," %-24s %8s"," (needs admin for /etc).","--system","Cancelled.","Cannot read: ","Keychain is locked.","Language: ","Save failed","Save failed.","Write failed: ","[^/]+$","decrypt","encrypt","function","kernel.pkg","kernel.process","profile module unavailable","rename","save failed","shell.keys","shell.panels.commands","timezone"local N=require("computer")local O=require("component")
local I=require("shell.panels.helpers")local P=function()end
do local b,a=pcall(require,V)if b and a and a.yieldCooperative then
P=a.yieldCooperative end end;local function Q()local a,b=pcall(require,"shell.panels.home")
return(a and b)or nil end;local function Y(a)local b=Q()return
b and b.cycleKeyLabel(a)or"F2"end
local function an(a)
local b=Q()if b and b.enabled(a)then
return b.viewKeyLabel(a).."  Tiles / files "end;return"F2  Next tab      "end
local function Z(a)local e=Q()local d,b=pcall(require,W)if not(d and b)then
return"Copy Ctrl+Insert  Cut ^X  Paste ^V"end;local c=a and a.who or nil;return
"Copy "..
b.label("copy",c).."  Cut "..
b.label("cut",c).."  Paste "..b.label("paste",c)end
local function R(a)local c,b=pcall(require,W)return
(c and b and b.quitHint)and b.quitHint(a and a.who or
nil)or"^Q"end
local function ao(a)local b=Y(a)return b..
string.rep(" ",math.max(1,12-#b)).."Next tab   "end
return
function(b,a,c)local h,aq,u,e,n,g=a.K,a.E,a.P,a.F,a.D,a.U;local p,A,i=a.SC,a.NM,a.st;local d=a.T;local B=a.tier
local q,v=a.W,a.H;local f=c.rp;local s=c.openViewTab;local ar=c.openEditTab;local k=c.refreshBrowser
local l=c.canRead;local o=c.canWrite;local as=c.canAccess;local w=c.rootOnly;local r=c.adminOnly
local at=c.makeProgramEnv;local m=I.fmtSz
local au=function(E)return I.expandBuf(a,E)end;local j=c.promptInput
b.help=function(av,E)
local aw=av and av[1]and av[1]:lower()
if aw=="cp"or aw=="copy"then E("cp <source> <dest>",d.title)
E("  Copy a file. Both paths are required.",d.fg)
E("  Paths starting with / are absolute; others are relative to cwd.",d.fg)E(_,d.dim)
E("    cp notes.txt /home/root/notes_bak.txt",d.dim)E("    cp /etc/cfg.conf /tmp/cfg.conf",d.dim)
E("  Tip: Use F5 in the browser for clipboard-style copy.",d.highlight)elseif aw=="mv"then E("mv <source> <dest>",d.title)
E("  Move or rename a file.",d.fg)E(_,d.dim)
E("    mv old.txt new.txt           (rename in cwd)",d.dim)
E("    mv /tmp/work.lua /home/root/ (move to dir)",d.dim)elseif aw=="cd"then E("cd [dir]",d.title)
E("  Change directory. With no argument, prints current directory.",d.fg)
E("  Special paths:  ..  (parent)   ~  (home dir)",d.fg)elseif aw=="find"then E("find [path] [-name pattern]",d.title)
E("  Recursively search for files. Pattern uses Lua patterns.",d.fg)E(_,d.dim)E("    find /tos -name *.lua",d.dim)
E("    find /home",d.dim)elseif aw=="grep"then E("grep <pattern> <file>",d.title)
E("  Search file lines for pattern (plain text, not regex).",d.fg)
E("  Example:  grep function /tos/shell/init.lua",d.dim)elseif aw=="flash"then E("flash <file>",d.title)
E("  Write a Lua file to the EEPROM (overwrites BIOS!).",d.fg)
E("  Prompts for confirmation. Use to install a new BIOS.",d.fg)E("  Example:  flash /tos/bios.lua",d.dim)elseif aw=="edit"then
E("edit <file>",d.title)
E("  Open file in editor tab. Creates the file if it doesn't exist.",d.fg)
E("  Keys:  Ctrl+S = save   Ctrl+Q = close tab   Ctrl+F = find",d.dim)E("  Ctrl+H = find/replace  Ctrl+Z = undo",d.dim)E(
"  Select: Shift+arrows.  "..Z(a),d.dim)
E("  With nothing selected, copy/cut take the whole line.",d.dim)
E("  Use "..Y(a).." to switch tabs, F4 to close.",d.dim)elseif aw=="run"then E("run <file> [args...]",d.title)
E("  Execute a Lua file in the current environment.",d.fg)
E("  Args are passed as a table in the second argument.",d.fg)elseif aw=="tape"then E("tape [subcommand]",d.title)
E("  Data storage on Computronics tapes (requires module).",d.fg)
E("  If the tape package is not installed, shows",d.fg)
E("  instructions for installing it or building your own.",d.fg)E("",d.fg)
E("  Subcommands (when module is active):",d.dim)E("    detect           List tape drives",d.dim)
E("    info             Tape size, label, format",d.dim)E("    label [name]     Get/set tape label",d.dim)
E("    store <path>     Archive file/dir to tape",d.dim)
E("    restore [path]   Restore archive from tape",d.dim)
E("    list             List archived entries",d.dim)
E("    dump [off] [len] Hex dump of tape bytes",d.dim)E("    erase [full]     Quick or full wipe",d.dim)
E("    raw read/write   Low-level byte I/O",d.dim)elseif aw=="net"then E("net [subcommand]",d.title)
E("  Network management (requires modem or linked card).",d.fg)E("",d.fg)E(K,d.dim)
E("    status              Show network status",d.dim)
E("    discover / scan     Broadcast ping to find peers",d.dim)
E("    peers / list        List known peers and trust levels",d.dim)
E("    trust <addr> [full] Elevate peer to KNOWN or TRUSTED",d.dim)E("    block <addr>        Block a peer",d.dim)
E("    send <addr> <msg>   Send message to trusted peer",d.dim)E("",d.fg)
E("  Related: ping <addr>, hostname [name], chat",d.dim)elseif

aw=="pkg"or aw=="mod"or aw=="module"or aw=="modules"or aw=="package"or aw=="packages"then E("pkg [subcommand]",d.title)
E("  Package manager — install and manage add-ons. (Replaces the old",d.fg)
E("  'mod'/module manager, retired in v1.3.1.)",d.fg)E("",d.fg)E(K,d.dim)
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
E("  Shortcuts: 'install <name>' and 'uninstall <name>' work too.",d.dim)elseif aw=="monitor"or aw=="top"then
E("monitor   (alias: top; also opened with Ctrl+T)",d.title)
E("  The live System Monitor — one screen showing what TOS is doing.",d.fg)E("",d.fg)E("  Shows:",d.dim)
E("    · Every process (kernel AND user), each explained, with owner,",d.dim)
E("      state, CPU and seat — auto-refreshing.",d.dim)
E("    · rc.d services and their status (admin).",d.dim)E("    · Memory and uptime vitals.",d.dim)
E("",d.fg)
E("  Runs as a full-screen tab: scrolls, never truncates, per-seat.",d.dim)E("",d.fg)E("  Keys:",d.dim)
E("    up/down move   Enter switch-to   K kill   T suspend/resume (TSR)",d.dim)
E("    Enter start-stop a service (admin)   R refresh   "..R(a).." close",d.dim)elseif aw=="cron"then E("cron [subcommand]",d.title)
E("  Manage scheduled tasks.  (admin+)",d.fg)E("",d.fg)E(K,d.dim)
E("    list                Show all cron jobs",d.dim)
E("    add <interval> <cmd> Schedule a command",d.dim)
E("    rm <id>             Remove a cron job",d.dim)elseif aw=="service"then E("service [subcommand]",d.title)
E("  Manage startup services.  (admin+)",d.fg)E("",d.fg)E(K,d.dim)
E("    (none)              List all services and status",d.dim)E("    start <name>        Start a service",d.dim)
E("    stop <name>         Stop a service",d.dim)elseif aw=="users"or aw=="useradd"or aw=="userdel"or
aw=="usermod"then
E("User Management  (admin/root)",d.title)
E("  users                   List all user accounts",d.fg)
E("  useradd <name>          Create a new user",d.fg)E("  userdel <name>          Delete a user",d.fg)
E("  usermod <user> <action> Modify a user:",d.fg)
E("    lock / unlock         Lock or unlock an account",d.dim)
E("    admin / user          Set role to admin or user",d.dim)
E("  whoami                  Show current user",d.fg)
E("  passwd                  Change your password",d.fg)elseif aw=="disk"then E("disk [subcommand]",d.title)
E("  Manage removable disks (floppies, HDDs).",d.fg)E("",d.fg)E(K,d.dim)
E("    list                List removable disks",d.dim)
E("    info <mount>        Show disk contents",d.dim)
E("    install <mount>     Install module from disk (admin)",d.dim)
E("    export <name> <mnt> Write module to disk    (admin)",d.dim)E("    eject <mount>       Unmount a disk",d.dim)elseif aw==
"redstone"or aw=="rs"then
E("redstone [subcommand]  (alias: rs)",d.title)E("  Control redstone I/O on all sides.",d.fg)
E("",d.fg)E(K,d.dim)
E("    (none)              Show redstone levels",d.dim)
E("    set <side> <level>  Set output (0-15)",d.dim)
E("    pulse <side> [dur]  Pulse output (default 0.5s)",d.dim)elseif aw=="robot"then E("robot <command>",d.title)
E("  Control robot/drone movement and interaction.",d.fg)E("",d.fg)
E("  Movement: forward, back, up, down, left, right",d.dim)
E("  Actions:  swing, use, place, suck, drop, detect",d.dim)E("  Info:     name, energy, slot <n>",d.dim)elseif
aw=="audio"or aw=="sound"or aw=="beep"then
E("audio [subcommand]",d.title)
E("  Control audio feedback (beeps and notifications).",d.fg)E("",d.fg)E(K,d.dim)
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
E("    2 descending        Shutdown / logout",d.dim)E("    3 ascending         Boot complete",d.dim)elseif aw and
aw~=""then local ay=require(M)local ax=ay.entry and ay.entry(aw)
if ax then
local aA={[0]="guest",[1]="user",[2]="admin",[3]="root"}E(aw,d.title)
E("  ".. (ax.help or"(no description)"),d.fg)E("",d.fg)
E(string.format("  Minimum tier: %s    Group: %s",aA[ax.tier or 0]or
tostring(ax.tier),ax.category or"?"),d.dim)
local az="  Tip: run '"..aw.."' with no args for usage"
if e.exists("/usr/man/"..aw..".man")then az=az.."; 'man "..
aw.."' for the manual."else az=az.."."end;E(az,d.dim)else
E("No such command: '"..aw.."'.  Type 'help' for the full list.",d.warning)end else local ay=require(M)
local function ax(aD)return ay.needMet and ay.needMet(aD)end
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
E("  F1  Help      "..an(a)..
"  F3  View file",d.fg)
E("  F4  Close tab F5  Copy file      F6  Move file",d.fg)
E("  "..ao(a).." F9  Menu bar",d.fg)E("  F7  Mkdir     F8  Delete",d.fg)
E("  Text: Shift+arrows select.  "..Z(a),d.fg)
E("  F10 Quit      "..R(a).."  Cancel/Close   ^F  Find",d.fg)
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
E("  edit <file>   Open in editor tab  (^S save, "..R(a).." close)",d.fg)end
if a.userTier>=3 then
E("  lua           Interactive Lua REPL  (exit to quit)",d.fg)
E("  flash <file>  Flash EEPROM with Lua file  (!CAUTION)",d.fg)end
E("  programs      List executables in /bin and /usr/bin",d.fg)E("  history       Show command history",d.fg)
E("  date [fmt]    Show wall clock  (time = alias)",d.fg)
E("  tree [path] [depth]  Visual recursive directory listing",d.fg)
E("  theme [list|set|color|...]  Customize colors  (colors = alias)",d.fg)
E("  tutorial      Replay the welcome walkthrough",d.fg)if a.userTier>=1 and ax("swap")then
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
E("  cron [list|add|rm]        Scheduled tasks",d.fg)end;local az,aA=ax("component:redstone"),ax("component:robot")
local aB,aC=ax("inventory"),ax("module:tape")
if az or aA or aB or aC or a.userTier>=2 then E("",d.fg)
E(" Peripherals",d.highlight)if az then
E("  redstone [set|pulse] Control redstone I/O  (rs = alias)",d.fg)end;if aA then
E("  robot <cmd>          Robot/drone movement & interaction",d.fg)end;if aB then
E("  inventory [side]     Inspect inventories  (inv = alias)",d.fg)end;if aC then
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
b.man=function(av,E)local ax="/usr/man"local aw=av and av[1]
if not aw then
E("Manual pages — usage: man <topic>",d.title)local aA=
(e.isDirectory and e.isDirectory(ax)and e.list(ax))or{}
if
type(aA)=="table"and#aA>0 then table.sort(aA)
for aC,aB in ipairs(aA)do
local aD=(aB:gsub("/$","")):gsub("%.man$","")if aD~=""then E("  "..aD,d.fg)end end else
E("  (no manual pages installed under "..ax..")",d.dim)end
E("Depth: help (quick) < man (detailed) < MANUAL.md (the full book)",d.dim)return end;aw=tostring(aw):gsub("[^%w_%-]","")if aw==""then
E("man: invalid topic",d.error)return end;local ay=e.join(ax,aw..".man")if not
e.exists(ay)then ay=e.join(ax,aw)end
if not e.exists(ay)then E(
"No manual page for '"..aw.."'.",d.error)
E(
"Try 'help "..aw.."', or open MANUAL.md for the full book.",d.dim)return end;local az=e.readFile(ay)if not az then
E("man: cannot read page",d.error)return end
if s then local aA={}
for aB in
(az.."\n"):gmatch("([^\n]*)\n")do local aC=d.fg
if aB:match("^[A-Z][A-Z0-9 /%-]+$")then aC=d.title elseif aB:match("^%s")then aC=d.dim end;aA[#aA+1]={aB,aC}end;s(aA,"man "..aw)else for aA in(az.."\n"):gmatch("([^\n]*)\n")do
E(aA,d.fg)end end end
b.about=function(av,E)local aw=_G._TOS or{}
local az,ax,aA="Strata Systems LLC",nil,"Terminal Operating System"local aB,ay=pcall(require,"kernel.logo")if aB and ay then
az=ay.VENDOR or az;ax=ay.MOTTO;aA=ay.TAGLINE or aA end;E(
"TOS - "..aA,d.title)
E("Version "..
(aw.version or"?").."  [".. (aw.codename or
"?").."]",d.highlight)
E("Build "..tostring(aw.build or"?").." ("..
tostring(aw.variant or"?")..")",d.dim)
E("GPU T"..B.." | "..
math.floor(N.totalMemory()/1024).."K RAM",d.dim)E(az.."   -   GNU GPL v3.0",d.dim)if ax and ax~=""then E(
'"'..ax..'"',d.dim)end;E("",d.fg)
E("A secure, multi-seat terminal OS for OpenComputers:",d.fg)
E("  - Sandboxed processes, role-based users, encrypted homes",d.fg)
E("  - Tabbed file browser + editor, themeable panels UI",d.fg)
E("  - Zero-trust networking: chat, mesh mail, clustering",d.fg)
E("  - Package manager + Optional Utilities add-on disk",d.fg)
E("  - Boot Settings (DEL at POST), swap, backups, OpenOS compat",d.fg)E("",d.fg)
E("'help' lists commands · 'tutorial' walks you through it.",d.dim)end;b.ver=b.about
b.echo=function(E,av)av(table.concat(E," "),d.fg)end
b.notify=function(av,E)local aD,aw=pcall(require,"kernel.notify")if not aD or not aw then
E("notify unavailable",d.error)return end;local ay,az,ax="info",nil,{}local aA
for aF=1,# (av or{})
do local aG=tostring(av[aF])
if aF==aA then elseif aG:sub(1,2)=="--"then
local aI,aH=aG:match("^%-%-([%w%-]+)=?(.*)$")
if aI=="style"or aI=="title"then if aH==""and av[aF+1]and
tostring(av[aF+1]):sub(1,2)~="--"then
aH=tostring(av[aF+1])aA=aF+1 end
if aI=="style"then ay=aH else az=aH end end else ax[#ax+1]=aG end end;local aB=table.concat(ax," ")
if aB==""then
E("Usage: notify <message> [--style info|warn|danger|error] [--title T]",d.title)
E("Puts a modal dialog box in front of every seat — the intrusive",d.dim)
E("counterpart to 'echo', which only writes above the command line.",d.dim)E("",d.dim)
E(string.format("Pending now: %d   (limits: %ds between boxes, %ds per source)",aw.depth(),aw.MIN_GAP,aw.MIN_SOURCE_GAP),d.dim)return end
local aC,aE=aw.post({message=aB,style=ay,title=az,from="notify/"..tostring(a.who or"?")})
if aC then
E("Raised on every seat (dialog #"..aC..").",d.highlight)else
E("Not raised: "..tostring(aE),d.warning)
E("The message is in the log either way ('log' to see it).",d.dim)end end
b.tutorial=function(av,E)local ax,aw=I.requireRoomy(a,"shell.tutorial","core")
if
not ax then E(I.loadFailure("tutorial",aw),d.error)return end
if av[1]=="--reset"then local az=
(g and i and g.getSession)and g.getSession(i)or nil;local ay=aw.markerFor and
aw.markerFor(az)
if ay and e.exists(ay)then
e.remove(ay)
E("Tutorial reset — it will run again at your next login.",d.success or d.fg)elseif ay then
E("Tutorial was not marked done for this account.",d.dim)else
E("This account has no home to remember the tutorial in.",d.dim)end end;aw.run({D=n,F=e,U=g,st=i,W=q,H=v})c.drawAll()end
b.cls=function(E,av)n.fill(1,1,q,v," ",d.fg,d.bg)c.drawAll()end;b.clear=b.cls
b.cd=function(E,av)if not E[1]then av(a.cwd,d.fg)return end
local aw=E[1]
if aw==".."then
a.cwd=a.cwd:match("^(.*)/[^/]+/?$")or"/"if a.cwd==""then a.cwd="/"end else local ax=f(aw):gsub("//+","/")
if
ax~="/"and ax:sub(-1)=="/"then ax=ax:sub(1,-2)end;if e.isDirectory(ax)then a.cwd=ax else
av("Not a directory: "..aw,d.error)return end end;a.browser.path=a.cwd;a.browser.sel=1;a.browser.scroll=0
c.loadFiles(a.browser)end
b.ls=function(av,E)local aB,aC,ay=false,false,nil
for aH,aG in ipairs(av)do
if not ay and aG:sub(1,1)=="-"and
#aG>1 then
for aI in aG:sub(2):gmatch(".")do if aI=="l"then aB=true elseif aI=="a"then aC=true else
E("Usage: ls [-l|-a] [dir]",d.dim)return end end elseif not ay then ay=aG end end;local aw=f(ay or a.cwd)if not l(aw,E)then return end;if e.exists and
not e.exists(aw)then
E("no such file: ".. (ay or aw),d.error)return end
local aE,az=pcall(e.list,aw)
if not aE or not az then E("Cannot list: "..aw,d.error)return end;local ax,aA={},0;local function aD(aG)
if aC or aG:sub(1,1)~="."then ax[#ax+1]=aG else aA=aA+1 end end
if type(az)=="table"then for aH,aG in ipairs(az)do
aD(aG)end elseif type(az)==aj then for aG in az do aD(aG)end end
table.sort(ax,function(aG,aH)local aI,aJ=aG:sub(-1)=="/",aH:sub(-1)=="/"if aI~=aJ then
return aI end;return aG<aH end)
local function aF(aG)if not e.lastModified then return"-"end
local aI,aH=pcall(e.lastModified,e.join(aw,aG))
if not aI or type(aH)~="number"or aH<=0 then return"-"end
local aJ,aK=pcall(os.date,"%Y-%m-%d %H:%M",math.floor(aH/1000))return aJ and aK or"-"end
if aB then
E(string.format(" %-24s %8s  %s","Name","Size","Modified"),d.title)E(string.rep("-",52),d.border)else
E(string.format(aa,"Name","Size"),d.title)E(string.rep("-",34),d.border)end
for aH,aG in ipairs(ax)do local aJ,aI
if aG:sub(-1)=="/"then
aJ=string.format(aa,"["..aG:sub(1,-2).."]","<DIR>")aI=d.dir or d.highlight else local aK=e.size(e.join(aw,aG))
aI=d.fg
if aG:match("%.lua$")then
aI=d.file_lua or d.file_exec or d.highlight elseif aG:match("%.cfg$")or aG:match("%.conf$")then
aI=d.file_cfg or d.warning elseif aG:match("%.log$")then aI=d.file_log or d.dim end;aJ=string.format(aa,aG:sub(1,24),m(aK))end;if aB then aJ=aJ.."  "..aF(aG)end;E(aJ,aI)end
if aA>0 then
E(#ax.." items ("..aA.." hidden: ls -a shows them)",d.dim)else E(#ax.." items",d.dim)end end;b.dir=b.ls
local function C(av,E)local aw=f(av)if not l(aw,E)then return true end;local ax,ay,az=I.readLinesCapped(e,aw,function(aA)
E(aA,d.fg)end)if not ax then E(
L..av,d.error)elseif az then
E(string.format(I.VIEW_STOPPED,ay),d.warning)return false end;return true end
b.cat=function(E,av)
if not E[1]then av("Usage: cat <file...>",d.dim)return end;for ax,aw in ipairs(E)do if not C(aw,av)then break end end end;b.type=b.cat
b.more=function(E,av)
if not E[1]then av("Usage: more <file>",d.dim)return end;local ax=f(E[1])if not l(ax,av)then return end
local aw={{" "..ax,d.title}}
local ay,az,aA=I.readLinesCapped(e,ax,function(aB)aw[#aw+1]={aB,d.fg}end)if not ay then av(L..E[1],d.error)return end;if aA then
aw[#aw+1]={string.format(I.VIEW_STOPPED,az),d.warning}end
s(aw,E[1]:match(ah)or E[1])end
local function D(E,aw,av)local ax=f(E)local ay=ax:match("^(.*)/[^/]+/?$")or"/"if not
o(ay,av)then return false end;if e.isDirectory and e.isDirectory(ax)then
if
not aw then av("Already exists: "..E,d.warning)end;return false end
local az,aA=e.makeDirectory(ax)
if az then av("Created: "..E,d.highlight)return true end
av(tostring(aA or"Could not create "..E),d.error)return false end
b.mkdir=function(av,E)local ay,aw=false,{}
for aA,az in ipairs(av)do if az=="-p"or az=="--parents"then ay=true else
aw[#aw+1]=az end end
if not aw[1]then E("Usage: mkdir [-p] <dir...>",d.dim)return end;local ax=false;for aA,az in ipairs(aw)do ax=D(az,ay,E)or ax end
if ax then k()end end
local function F(E,av)local aw=f(E)if not o(aw,av)then return false end
if not e.exists(aw)then
local ax,ay=e.writeFile(aw,"")if not ax then
av(tostring(ay or"Could not create "..E),d.error)return false end end;av("Touched: "..E,d.highlight)return true end
b.touch=function(E,av)
if not E[1]then av("Usage: touch <file...>",d.dim)return end;local aw=false;for ay,ax in ipairs(E)do aw=F(ax,av)or aw end
if aw then k()end end
local function x(E)local aw,av=false,{}for ay,ax in ipairs(E)do if ax=="-k"or ax=="--keep"then aw=true else
av[#av+1]=ax end end;return
aw,av end
b.compress=function(av,E)local aF,ax=x(av)if not ax[1]then
E("Usage: compress <file> [out]   (-k keeps original)",d.dim)return end
local aA=h.getCompress and h.getCompress()if not aA or not aA.available()then
E("Compression needs a data card (none detected).",d.error)return end;local aw=f(ax[1])if not
l(aw,E)then return end;if not e.exists(aw)or
(e.isDirectory and e.isDirectory(aw))then
E("Not a file: "..ax[1],d.error)return end
local aB=e.readFile(aw)if not aB then E("Read failed",d.error)return end;local ay=ax[2]and
f(ax[2])or(aw..".tcz")
if not o(ay,E)then return end;local aC,aD,az,aE=aA.pack(aB)
if not aC then E("Compress failed",d.error)return end
if not e.writeFile(ay,aC)then E("Write failed",d.error)return end;if not aF and ay~=aw then pcall(e.remove,aw)end;k()
local aG=
(az>0)and math.floor((az-aE)*100/az)or 0
E(string.format("%s -> %s  (%d%% smaller: %s -> %s)",ax[1],(ay:gsub("^.*/","")),aG,m(az),m(aE)),
aD=="deflate"and d.highlight or d.warning)if aD=="stored"then
E("(stored uncompressed — data didn't shrink)",d.dim)end end
b.decompress=function(av,E)local aC,ax=x(av)if not ax[1]then
E("Usage: decompress <file.tcz> [out]   (-k keeps original)",d.dim)return end;local aw=f(ax[1])if
not l(aw,E)then return end;if not e.exists(aw)then
E("No such file: "..ax[1],d.error)return end;local az=e.readFile(aw)if not az then
E("Read failed",d.error)return end
local aA=h.getCompress and h.getCompress()
if not aA then E("Compression module unavailable",d.error)return end;if not aA.isPacked(az)then
E("Not a .tcz container: "..ax[1],d.error)return end;local aB,aD=aA.unpack(az)if not aB then
E(
"Decompress failed: "..tostring(aD),d.error)return end;local ay
if ax[2]then ay=f(ax[2])elseif aw:sub(-4)==
".tcz"then ay=aw:sub(1,-5)else ay=aw..".out"end;if not o(ay,E)then return end;if not e.writeFile(ay,aB)then
E("Write failed",d.error)return end;if not aC and ay~=aw then
pcall(e.remove,aw)end;k()
E(string.format("%s -> %s  (%s restored)",ax[1],(ay:gsub("^.*/","")),m(
#aB)),d.highlight)end
local function G(av,aw,ax,E)local ay=f(av)
if ay=="/"then E("Cannot remove root",d.error)return end;local az=_G._TOS and _G._TOS.securefs
if az and
type(az.removeRefusal)==aj then
local aD=az.removeRefusal(ay,I.sessionOf(a))if aD then E(tostring(aD),d.error)return end end
local aB={"^/$","^/init%.lua$","^/bios%.lua$","^/tos$","^/tos/","^/etc$","^/etc/","^/boot$","^/boot/"}
for aE,aD in ipairs(aB)do
if ay:match(aD)and not aw then
E("Refusing to remove a system path without -r: "..ay..
"  [E-303 ERR_RM_SYSTEM_PATH]",d.error)
E("Protection is off, so this would really delete it. Add -r to confirm.",d.dim)return end end;if not o(ay,E)then return end
if e.isDirectory and e.isDirectory(ay)then if not aw then
E(
"Cannot remove directory without -r: "..ay.."  [E-302 ERR_NEEDS_RECURSIVE]",d.error)return end
local aD=e.list and e.list(ay)if aD and#aD>0 then
E("Removing "..#aD.." item(s) under "..ay.."...",d.dim)end end;local aA=false
local aC=ay:match("^/tos")or ay:match("^/etc")or
ay:match("^/var")or ay:match("^/usr")
if not ax and not aC then local aE,aD=pcall(require,"kernel.trash")
if
aE and aD and aD.put then local aF=I.sessionOf(a)local aG,aH=aD.put(ay,aF)
if aG then aA=true
E("Trashed: "..av..
" (use 'restore' to undo)",d.highlight)else local aI=tostring(aH or"unknown reason")
if
aI:find("no trash",1,true)then
E("No trash for this session — deleting "..av.." outright.",d.warning)else
E("Not trashed: "..aI.."  [E-304 ERR_TRASH_REFUSED]",d.error)
E("It is still there. Delete it for good with:  rm "..
(aw and"-r "or"").."--hard "..av,d.dim)return end end end end
if not aA then local aD,aE=e.remove(ay)if aD then k()
E("Removed: "..av,d.highlight)else
E(tostring(aE or"Could not remove "..av),d.error)end else k()end end
b.rm=function(av,E)local ax,ay=false,false;local aw={}for aA,az in ipairs(av)do
if
az=="-r"or az=="-rf"or az=="-R"then ax=true elseif az=="--hard"or az=="-H"then ay=true else aw[#aw+1]=az end end
if
#aw==0 then E("Usage: rm [-r] [--hard] <path...>",d.dim)return end;for aA,az in ipairs(aw)do G(az,ax,ay,E)end end
b.trash=function(av,E)local az,aw=pcall(require,"kernel.trash")if not az or not aw then
E("Trash unavailable",d.error)return end;local ax=av[1]or"list"
local ay=I.sessionOf(a)
if ax=="list"or ax=="ls"then local aB=aw.list(ay)if#aB==0 then
E("Trash is empty.",d.dim)return end
E(string.format(" %-20s %-8s %s","name","size","origin"),d.title)for aD,aC in ipairs(aB)do
E(string.format(" %-20s %-8d %s",aC.name:sub(1,20),aC.size,aC.origin),d.fg)end;local aA=aw.usage(ay)if
aA then
E(string.format(" %d/%d items, %d/%d bytes used",aA.count,aA.max_count,aA.bytes,aA.max_bytes),d.dim)end elseif ax=="empty"then
local aB,aA=aw.empty(ay)if aB then
E("Emptied "..tostring(aA).." items.",d.highlight)else
E(tostring(aA or"empty failed"),d.error)end elseif ax=="restore"then if not av[2]then
E("Usage: trash restore <name> [dest] [--force]",d.dim)return end;local aA,aB=false,nil;for aE=3,#av do
if
av[aE]=="--force"or av[aE]=="-f"then aA=true else aB=av[aE]end end
local aD,aC=aw.restore(av[2],{session=ay,dest=aB,force=aA})if aD then k()
E("Restored to "..tostring(aC),d.highlight)else
E(tostring(aC or"restore failed"),d.error)end else
E("Usage: trash [list|empty|restore <name> [dest] [--force]]",d.dim)end end
b.vault=function(av,E)local aD,ax=I.requireRoomy(a,"kernel.vault","core")
if
not aD or not ax then E(I.loadFailure("vault",ax),d.error)return end;local aw=av[1]local aB=I.sessionOf(a)
local ay=_G._TOS and _G._TOS.securefs
local function az(aE)if ay and ay.readFile then return ay.readFile(aE,aB)end;return
nil,"securefs unavailable (refusing unchecked read)"end
local function aC(aE,aF)
if ay and ay.writeFile then return ay.writeFile(aE,aF,aB)end;return false,"securefs unavailable (refusing unchecked write)"end
local function aA(aE,aF)
if aE~=nil and aE~="-"then
E("Note: a typed passphrase stays in this seat's command history;",d.dim)
E("leave it off, or use -, to be asked for it instead.",d.dim)return aE end;if not j then
E("Cannot ask for a passphrase here: give it as the last argument.",d.error)return nil end
local aG=j("Passphrase: ",256,true)if not aG or aG==""then E(ab,d.dim)return nil end
if aF then
local aH=j("Again, to confirm: ",256,true)if aH~=aG then
E(aH and"The two did not match; nothing was changed."or ab,d.error)return nil end end;return aG end
if aw==J or aw==ai then local aH,aJ=av[2],av[3]if not aH or not aJ then
E("Usage: vault "..aw..
" <src> <dst> [passphrase | -]",d.dim)return end;local aE=az(f(aH))if not aE then E(L..
aH,d.error)return end;if aw==ai and
not ax.isEncrypted(aE)then
E("Source is not a TOS vault blob.",d.warning)return end
local aI=aA(av[4],aw==J)if not aI then return end;local aF,aG;if aw==J then aF,aG=ax.encrypt(aE,aI)else
aF,aG=ax.decrypt(aE,aI)end;if not aF then
E("Failed: "..tostring(aG),d.error)return end;local aK,aL=aC(f(aJ),aF)if not aK then
E(ag..tostring(aL),d.error)return end
E(string.format("%s %d -> %d bytes (algo=%s)",aw==J and"Encrypted"or
"Decrypted",#aE,#aF,tostring(aG.algo)),d.highlight)elseif aw=="encrypt-in-place"or aw=="decrypt-in-place"then
local aH=av[2]if not aH then
E("Usage: vault "..aw.." <file> [passphrase | -]",d.dim)return end;local aK=f(aH)local aE=az(aK)if not aE then
E(L..aH,d.error)return end;local aG=aw:sub(1,7)==J
if
aG and ax.isEncrypted(aE)then
E("Already encrypted — refusing to double-encrypt.",d.warning)return elseif not aG and not ax.isEncrypted(aE)then
E("Not a vault blob — nothing to decrypt.",d.warning)return end;local aI=aA(av[3],aG)if not aI then return end;local aF,aJ;if aG then
aF,aJ=ax.encrypt(aE,aI)else aF,aJ=ax.decrypt(aE,aI)end
if not aF then E("Failed: "..
tostring(aJ),d.error)return end;local aL,aM=aC(aK,aF)if not aL then E(ag..tostring(aM),d.error)
return end
E(string.format("%s in place: %d -> %d bytes",
aw:sub(1,7)==J and"Encrypted"or"Decrypted",#aE,#aF),d.highlight)elseif aw=="info"then local aE=av[2]if not aE then
E("Usage: vault info <file>",d.dim)return end;local aF=az(f(aE))if not aF then
E(L..aE,d.error)return end;if not ax.isEncrypted(aF)then
E("Not a vault blob (no TVAULT1 magic).",d.warning)return end
E(string.format(" file:     %s",aE),d.title)
E(string.format(" size:     %d bytes",#aF),d.fg)local aG=#ax.MAGIC+1
local aH=aF:sub(aG,aG+3):gsub("\0+$","")
E(string.format(" algo:     %s",aH),d.fg)
E(string.format(" ctLen:    encrypted body inside this blob"),d.dim)
E(" (decrypt with the right passphrase to access contents)",d.dim)elseif aw=="tape"then local aE=av[2]if aE~=J and aE~=ai then
E("Usage: vault tape encrypt|decrypt [passphrase | -]",d.dim)return end;local aF=b.tape;if not aF then
E("Tape module not installed (run `pkg install tape`).",d.warning)return end
local aG=aA(av[3],aE==J)if not aG then return end;aF({aE,aG},E)else
E("Usage: vault [encrypt|decrypt|encrypt-in-place|decrypt-in-place|info|tape] ...",d.dim)
E("  vault encrypt <src> <dst> [passphrase]",d.dim)
E("  vault decrypt <src> <dst> [passphrase]",d.dim)
E("  vault encrypt-in-place <file> [passphrase]",d.dim)
E("  vault decrypt-in-place <file> [passphrase]",d.dim)E("  vault info <file>",d.dim)
E("  vault tape encrypt|decrypt [passphrase]",d.dim)
E("  Leave the passphrase off (or use -) to be asked for it, unechoed:",d.dim)
E("  a typed one stays in this seat's command history.",d.dim)end end
b.keychain=function(av,E)local aw=_G._TOS and _G._TOS.keychain;if not aw then
E("keychain module unavailable",d.error)return end;local ax=I.sessionOf(a)
local ay=av[1]or"status"
if ay=="status"then
E(aw.isUnlocked(ax)and"unlocked"or"locked",d.fg)elseif ay=="unlock"then if not j then
E("interactive prompt unavailable",d.error)return end
local az=j("Master password: ",64,"*")or""
if#az==0 then E("(empty — cancelled)",d.dim)return end;local aA,aB=aw.unlock(az,ax)if aA then
E("Keychain unlocked.",d.highlight)else
E("Unlock failed: "..tostring(aB),d.error)end elseif ay=="lock"then aw.lock(ax)
E("Keychain locked.",d.highlight)elseif ay=="list"then
if not aw.isUnlocked(ax)then E(ac,d.warning)return end;local az=aw.list(ax)
if#az==0 then E("(empty)",d.dim)return end;for aB,aA in ipairs(az)do E("  "..aA,d.fg)end elseif ay=="set"then if not av[2]then
E("Usage: keychain set <name>",d.dim)return end;if not aw.isUnlocked(ax)then
E("Keychain is locked. Run 'keychain unlock' first.",d.warning)return end;if not j then
E("interactive prompt unavailable",d.error)return end;local az=
j("Passphrase for '"..av[2].."': ",256,"*")or""if#az==0 then
E("(empty — cancelled)",d.dim)return end;local aA,aB=aw.set(av[2],az,ax)if aA then
E("Slot '"..
av[2].."' saved.",d.highlight)else
E("Save failed: "..tostring(aB),d.error)end elseif ay=="get"then if not av[2]then
E("Usage: keychain get <name>",d.dim)return end;if not aw.isUnlocked(ax)then
E(ac,d.warning)return end;local az,aA=aw.get(av[2],ax)if az then
E(az,d.fg)else
E(tostring(aA or"no such slot"),d.error)end elseif ay=="remove"or ay=="rm"then if not av[2]then
E("Usage: keychain remove <name>",d.dim)return end;if not aw.isUnlocked(ax)then
E(ac,d.warning)return end;local az,aA=aw.remove(av[2],ax)
if az then E("Removed '"..
av[2].."'.",d.highlight)else E(
"Remove failed: "..tostring(aA),d.error)end else
E("Usage: keychain [status|unlock|lock|list|set|get|remove] ...",d.dim)end end
b.profile=function(av,E)local ax=_G._TOS and _G._TOS.profile;if not ax then
E(ak,d.error)return end;local aw=I.sessionOf(a)local ay=av[1]or"show"
if ay==
"show"then local az,aB=ax.load(aw)
E(string.format(" name:    %s",az.name),d.title)
E(string.format(" theme:   %s",az.theme or"(unset — uses `theme set` choice or default)"),d.fg)
E(string.format(" cwd:     %s",az.cwd or"(unset)"),d.fg)
E(string.format(" prompt:  %s",az.prompt or"(default)"),d.fg)local aA=0;for aC in pairs(az.env)do aA=aA+1 end
E(string.format(" env:     %d entries",aA),d.fg)
E(string.format(" startup: %d commands",#az.startup),d.fg)if not aB then
E(" (no profile file — showing defaults)",d.dim)end elseif ay=="set"then
if not av[2]or not av[3]then
E("Usage: profile set <field> <value>",d.dim)E("  fields: name, theme, cwd, prompt",d.dim)return end;local az,aA=av[2],av[3]local aB=ax.load(aw)
if az=="name"or az=="theme"or
az=="cwd"or az=="prompt"then
if az=="theme"then local aE=_G._TOS and
_G._TOS.theme
if
aE and aE.preset and not aE.preset(aA)then E("Unknown theme preset: "..aA,d.error)if aE.list then
E(
"Available: "..table.concat(aE.list(),", "),d.dim)end;return end end;aB[az]=aA;local aC,aD=ax.save(aB,aw)
if aC then
E("Profile updated. Re-login to apply.",d.highlight)else E(tostring(aD or am),d.error)end else E("Unknown field: "..az,d.error)end elseif ay=="env"then if not av[2]then
E("Usage: profile env <KEY> [VALUE]",d.dim)return end;local az=ax.load(aw)if av[3]then
az.env[av[2]]=av[3]E("env["..av[2].."] set",d.highlight)else az.env[av[2]]=
nil
E("env["..av[2].."] cleared",d.highlight)end
ax.save(az,aw)elseif ay=="startup"then local aA=av[2]or"list"local az=ax.load(aw)
if aA=="add"then
local aB=table.concat(av," ",3)
if#aB==0 then E("Usage: profile startup add <cmd>",d.dim)return end;az.startup[#az.startup+1]=aB;ax.save(az,aw)
E("Added.",d.highlight)elseif aA=="clear"then az.startup={}ax.save(az,aw)
E("Startup commands cleared.",d.highlight)else for aB,aC in ipairs(az.startup)do
E(string.format(" %d. %s",aB,aC),d.fg)end;if#az.startup==0 then
E("(no startup commands)",d.dim)end end elseif ay=="reset"then local az=_G._TOS and _G._TOS.securefs;if
az and aw and aw.home and aw.home~="/"then
az.remove(aw.home.."/.profile.cfg",aw)end
E("Profile reset to defaults.",d.highlight)else
E("Usage: profile [show|set|env|startup|reset]",d.dim)end end
b.cp=function(E,av)
if not E[2]then av("Usage: cp <src> <dst>",d.dim)return end;local ax,aw=f(E[1]),f(E[2])if e.isDirectory(aw)then
aw=e.join(aw,ax:match(ah)or ax)end;local ay,az=e.copy(ax,aw)
if ay then k()
av("Copied: "..E[2],d.highlight)else av(az or"Failed",d.error)end end
b.mv=function(av,E)
if not av[2]then E("Usage: mv <src> <dst>",d.dim)return end;local aw,ax=f(av[1]),f(av[2])if e.isDirectory(ax)then
ax=e.join(ax,aw:match(ah)or aw)end;if not o(aw,E)then return end
if not o(ax,E)then return end
if e.rename(aw,ax)then k()E("Moved: "..av[2],d.highlight)else
local ay,az=e.copy(aw,ax)if ay and e.remove(aw)then k()
E("Moved: "..av[2],d.highlight)else
E("Move failed: "..tostring(az or"cross-fs copy failed"),d.error)end end end
b.find=function(E,av)local aA="/"local ay=nil;local aw=1
while aw<=#E do if E[aw]=="-name"and E[aw+1]then
ay=E[aw+1]aw=aw+2 else aA=f(E[aw])aw=aw+1 end end
if ay then local aF,aG=pcall(string.match,"",ay)if not aF then
av("Invalid pattern: "..tostring(aG),d.error)return end end;av("Searching "..aA.." ...",d.dim)local aD=16
local az=1000;local ax={}
local function aE(aF)if not g or not g.canAccessAs then return false end
local aG=I.sessionOf(a)local aH=g.canAccessAs(aG,aF,"r")return aH end
local function aC(aF,aG)if aG>aD then return end;if#ax>=az then return end;if not aE(aF)then return end
local aJ,aH=pcall(e.list,aF)if not aJ or not aH then return end;local aI={}
if type(aH)=="table"then aI=aH elseif
type(aH)==aj then for aK in aH do aI[#aI+1]=aK end end
for aL,aK in ipairs(aI)do if#ax>=az then break end;P()
local aM=e.join(aF,aK:gsub("/$",""))local aN=aK:sub(-1)=="/"local aO=false;if ay then
local aP,aQ=pcall(string.match,aM,ay)local aR,aS=pcall(string.match,aK,ay)
aO=(aP and aQ)or(aR and aS)else aO=true end;if aO then
ax[
#ax+1]={aM.. (aN and"/"or""),
aN and(d.dir or d.highlight)or d.fg}end;if
aN and not aM:match("^/tos")then aC(aM,aG+1)end end end;aC(aA,0)if#ax==0 then av("No matches found",d.dim)else for aG,aF in ipairs(ax)do
av(aF[1],aF[2])end end;local aB=#ax..
" result(s)"if#ax>=az then
aB=aB.." (truncated at "..az..")"end;av(aB,d.dim)end
b.grep=function(av,E)
if not av[2]then E("Usage: grep <pattern> <file>",d.dim)return end;local az=av[1]local ay=f(av[2])if not l(ay,E)then return end;local aw=0;local ax=0
local aA=I.eachLine(e,ay,function(aB)ax=
ax+1;if aB:find(az,1,true)then
E(string.format("%4d: %s",ax,aB),d.fg)aw=aw+1 end end)if not aA then E(L..av[2],d.error)return end
E(aw>0 and
(aw.." match(es)")or"No matches",d.dim)end
b.wc=function(E,av)
if not E[1]then av("Usage: wc <file>",d.dim)return end;local ay=f(E[1])if not l(ay,av)then return end;local aw,ax=0,0
local az,aA=I.eachLine(e,ay,function(aB)aw=aw+1;for aC in
aB:gmatch("%S+")do ax=ax+1 end end)if not az then av(L..E[1],d.error)return end
av(string.format(" Lines: %d  Words: %d  Bytes: %d  -- %s",aw,ax,aA,E[1]),d.fg)end;b.pwd=function(av,E)E(a.cwd or"/",d.fg)end
local function y(E)
local ax,aw=nil,10;local av=1
while av<=#E do local ay=E[av]
if ay=="-n"and E[av+1]then
aw=tonumber(E[av+1])or aw;av=av+1 elseif ay:match("^%-%d+$")then aw=tonumber(ay:sub(2))elseif not ax then ax=ay elseif
tonumber(ay)then aw=tonumber(ay)end;av=av+1 end;return ax,aw end
local function z(E,ax,av,aw)if e.exists and not e.exists(ax)then
aw("No such file: "..E,d.error)else
aw("Cannot read "..E..
(av and(": "..tostring(av))or""),d.error)end end
b.head=function(av,E)local aw,ax=y(av)if not aw then E("Usage: head [-n N] <file>",d.dim)
return end;local ay=f(aw)if not l(ay,E)then return end
local az=0;if not ax or ax<1 then return end
local aA,aB=I.eachLine(e,ay,function(aC)E(aC,d.fg)az=az+1;if az>=ax then
return false end end)if not aA then z(aw,ay,aB,E)end end
b.tail=function(av,E)local ay,aw=y(av)if not ay then E("Usage: tail [-n N] <file>",d.dim)
return end;local az=f(ay)if not l(az,E)then return end;if not aw or
aw<1 then return end;if aw>1000 then aw=1000 end;local aA,ax={},0
local aB,aC=I.eachLine(e,az,function(aD)
ax=ax+1;aA[(ax-1)%aw+1]=aD end)if not aB then z(ay,az,aC,E)return end
for aD=math.max(1,ax-aw+1),ax do E(aA[
(aD-1)%aw+1],d.fg)end end
b.which=function(av,E)
if not av[1]then E("Usage: which <name>",d.dim)return end;local aw=av[1]:lower()local ax=false;local az=I.aliases(a)
if az[aw]then
E(aw..": alias for '"..
az[aw].."'",d.highlight)
E("  (expanded before dispatch; the expansion is resolved below)",d.dim)
aw=tostring(I.tokenizeSimple(az[aw])[1]or aw):lower()ax=true end;local aB=require(M)
local ay=aB.entry and aB.entry(aw)or nil
if ay then local aG=ay.tier or 0
E(aw..
": built-in (".. (ay.category or"?")..", needs "..
I.tierName(aG)..")",d.title)if ay.help then E("  "..ay.help,d.fg)end;if
aG>I.liveTier(a)then
E("  You do not have the tier to run it — 'why "..aw.."'.",d.warning)end;ax=true end;local aE,aA=pcall(require,U)
local aC=aE and aA and aA.ownerOfCommand and
aA.ownerOfCommand(aw)or nil
if aC then
E(aw..": package command from '"..aC.."'",ay and d.dim or d.title)
if ay then E("  (shadowed by the built-in above)",d.dim)end;ax=true end;local aD,aF=I.resolveProgram(e,aw)
if aD then
E(aw..": "..aD..
(aF=="path"and"  (via PATH)"or""),ax and d.dim or
d.title)
if ax then E("  (shadowed by the entry above)",d.dim)end;ax=true end
if not ax then E(aw..": not found",d.error)
E("  Not a built-in, an installed package's command, or a program on",d.dim)
E("  /bin, /usr/bin or /tos/shell. 'help' lists what this box has.",d.dim)end end
local function H(E)local av=require(M)
if av.entry and av.entry(E)then return true end;if I.mayHavePackages()then local ax,aw=pcall(require,U)
if
ax and aw and aw.ownerOfCommand and aw.ownerOfCommand(E)then return true end end;return
I.resolveProgram(e,E)~=nil end
b.open=function(av,E)local aw=require("shell.open")local aB=I.sessionOf(a)
local az=aB and aB.home;local ax=av[1]
local function ay()
E("Usage: open <file>                    in the program that suits it",d.dim)
E("       open with <file> [program]     every program that could, and why",d.dim)
E("       open set .<ext> <program> [--system]   choose (--system: every user)",d.dim)
E("       open unset .<ext> [--system]   forget the choice",d.dim)
E("       open list                      the choices and what packages declare",d.dim)
E("       open hints on|off              edit's suggestions",d.dim)end;if not ax then ay()return end;local function aC(aF)if aF then return aw.SYSTEM_FILE end
return az and(az..
"/"..aw.USER_FILE)or nil end
local function aD(aF)
local aG,aH=pcall(e.exists,aF)return
aw.parseDefaults(aG and aH and e.readFile(aF)or nil)end
local function aA(aF,aG)
local aH,aI=e.writeFile(aF,aw.serializeDefaults(aG))if not aH then
E("Not saved: "..tostring(aI or aF),d.error)end;return aH end
local function aE(aF,aG)if not a.execOne then
E("open: the executor is unavailable",d.error)return end;local aH=a.execOne(aF.." "..aw.quote(aG),
nil,true)for aJ,aI in ipairs(aH or{})do
E(aI[1],aI[2])end end
if ax=="set"or ax=="unset"then local aI=av[#av]==T
local aF=(av[2]or""):gsub("^%.",""):lower()if
aF==""or not aF:match("^[%w]+$")or#aF>8 then ay()return end;if aI and not r(E)then return end
local aG=aC(aI)if not aG then
E("There is no home directory to keep your choice in.",d.error)return end;local aH=aD(aG)
if ax=="set"then local aJ=av[3]and
av[3]:lower()if not aJ or aJ==T then ay()return end;if
not H(aJ)then
E("'"..
aJ.."' is not a command this machine has ('which "..aJ.."').",d.error)return end;aH.ext[aF]=aJ;if
aA(aG,aH)then
E("."..
aF.." files now open in "..aJ..
(aI and" for every user."or" for you."),d.highlight)end else aH.ext[aF]=nil;if
aA(aG,aH)then
E("."..aF..": back to the ranking.",d.highlight)end end elseif ax=="hints"then local aF=aC(false)if not aF or
(av[2]~="on"and av[2]~="off")then ay()return end;local aG=aD(aF)aG.hints=(
av[2]=="on")if aA(aF,aG)then
E("edit's suggestions are "..av[2]..".",d.highlight)end elseif ax=="list"then
local aF=aw.gather(e,az,nil,"")
local function aG(aI,aH)local aJ={}for aK in pairs(aH.ext)do aJ[#aJ+1]=aK end
table.sort(aJ)
E(aI.. (#aJ==0 and"  (none)"or""),d.title)for aL,aK in ipairs(aJ)do
E(string.format("  .%-8s %s",aK,aH.ext[aK]),d.fg)end end
aG("Your choices (~/"..aw.USER_FILE.."):",aF.user)
aG("This machine's ("..aw.SYSTEM_FILE.."):",aF.system)
E("What installed packages open:"..
(#aF.decls==0 and"  (none)"or""),d.title)
for aI,aH in ipairs(aF.decls)do local aJ={}
for aL in pairs(aH.exts)do aJ[#aJ+1]="."..aL end;table.sort(aJ)
local aK=aH.markers and
("when a line starts "..table.concat(aH.markers," "))or(aH.as=="native"and"its own format"or
"can open")
E(string.format("  %-8s %s  %s",aH.cmd,table.concat(aJ," "),aK),d.fg)end;if aF.user.hints==false then
E("edit's suggestions are off ('open hints on').",d.dim)end else local aH=ax=="with"
local aI=aH and av[2]or ax;if not aI then ay()return end;local aF=f(aI)local aK,aL=pcall(e.exists,aF)if not aK or
not aL then E("open: no such file: "..aF,d.error)
return end;if
e.isDirectory and e.isDirectory(aF)then
E("open: "..aF.." is a directory ('cd' into it).",d.error)return end
local aG=aw.rank(aF,aw.gather(e,az,aF))
if aH and not av[3]then if#aG==0 then
E("Nothing here opens "..aF..".",d.warning)return end
E("Programs that could open "..aF..", best first:",d.title)for aN,aM in ipairs(aG)do
E(string.format("  %-8s %3d  %s",aM.cmd,aM.score,aM.why),aN==1 and
d.highlight or d.fg)end
E("'open with "..aI..

" <program>' uses another; 'open set .".. (aw.ext(aF)or"ext").." <program>' makes it yours.",d.dim)return end
local aJ=aH and av[3]:lower()or(aG[1]and aG[1].cmd)if not aJ then
E("Nothing here opens "..aF.." ('open with' lists what could).",d.warning)return end;if not aH then
E("Opening in "..aJ..": "..aG[1].why..
".",d.dim)end;aE(aJ,aF)end end
b.alias=function(av,E)local ay=_G._TOS and _G._TOS.profile;if not ay then E(ak,d.error)
return end;local az=I.sessionOf(a)
if not av[1]then local aF=ay.load(az)
local aE={}for aG in pairs(aF.aliases or{})do aE[#aE+1]=aG end
table.sort(aE)if#aE==0 then E("(no aliases)",d.dim)
E("Define one:  alias ll ls -l",d.dim)return end;for aH,aG in ipairs(aE)do
E(string.format(" %-12s %s",aG,aF.aliases[aG]),d.fg)end;return end;local aw=av[1]:lower()if not aw:match("^[%w_%-]+$")then E("Bad alias name: "..
av[1],d.error)
E("Letters, digits, underscore and hyphen only.",d.dim)return end
local ax=ay.load(az)
if not av[2]then
if ax.aliases and ax.aliases[aw]then
E(string.format(" %-12s %s",aw,ax.aliases[aw]),d.fg)else E(aw..": not aliased",d.dim)end;return end;local aA=table.concat(av," ",2)
local aB=tostring(I.tokenizeSimple(aA)[1]or""):lower()if aB==aw then E("An alias cannot expand to itself.",d.error)
E("To add default flags, alias to a different name.",d.dim)return end;ax.aliases=
ax.aliases or{}ax.aliases[aw]=aA;local aC,aD=ay.save(ax,az)
if
not aC then E(tostring(aD or am),d.error)return end;I.invalidateAliases(a)
E("alias "..aw.." -> "..aA,d.highlight)end
b.unalias=function(av,E)local ay=_G._TOS and _G._TOS.profile;if not ay then
E(ak,d.error)return end;if not av[1]then
E("Usage: unalias <name>",d.dim)return end;local az=I.sessionOf(a)
local aw=av[1]:lower()local ax=ay.load(az)
if not ax.aliases or not ax.aliases[aw]then E(
aw..": not aliased",d.dim)return end;ax.aliases[aw]=nil;local aA,aB=ay.save(ax,az)if not aA then
E(tostring(aB or am),d.error)return end;I.invalidateAliases(a)E("Removed alias '"..
aw.."'.",d.highlight)end
b.du=function(av,E)local aw=f(av[1]or(a.cwd or"/"))
if not l(aw,E)then return end;local function ay(az,aA)return
az:sub(-1)=="/"and(az..aA)or(az.."/"..aA)end
local function ax(az)
if
e.isDirectory(az)then local aA,aB=0,e.list(az)
if type(aB)=="table"then for aD,aC in ipairs(aB)do P()aA=aA+
ax(ay(az,aC:gsub("/$","")))end end;return aA end;return(e.size and e.size(az))or 0 end
if e.isDirectory(aw)then local az=e.list(aw)
if type(az)=="table"then for aB,aA in ipairs(az)do
local aC=aA:gsub("/$","")
E(string.format(" %8s  %s",m(ax(ay(aw,aC))),aC),d.fg)end end end
E(string.format(" %8s  %s (total)",m(ax(aw)),aw),d.title)end
b.df=function(av,E)local ay,aw=pcall(require,"kernel.monitor")
E(string.format(" %-16s %8s %8s %8s  %s","Mount","Total","Used","Free","Use%"),d.title)
E(string.rep("-",math.min(q,56)),d.dim)local ax=e.mounts and e.mounts()or{}
if#ax==0 then
E("(mount info unavailable)",d.dim)else
for aA,az in ipairs(ax)do local aB=az.total or 0;local aC=az.used or 0;local aE=aB-aC
local aD=aB>0 and math.floor(
aC*100/aB)or 0
local aF=(ay and aw.memBar)and aw.memBar(aC,aB,8)or""
local aG=aD<80 and d.fg or(aD<95 and d.warning or d.error)
E(string.format(" %-16s %8s %8s %8s  [%s] %3d%%",(az.mountPoint or"?"):sub(1,16),m(aB),m(aC),m(aE),aF,aD),aG)end end
if _G._TOS_ROOT_READONLY then E("",d.dim)
E("WARNING: the root filesystem is READ-ONLY.",d.error)
E("Nothing TOS writes will survive a reboot — users, logs, packages,",d.dim)
E("settings. Install to a writable drive, or unprotect this one.",d.dim)end
E("A path's own size: 'du <path>'.  Removable media + pools: 'disk'.",d.dim)end
b.mem=function(av,E)
if av and av[1]=="--boot"then
local aI=_G._TOS and _G._TOS.bootMem
if type(aI)~="table"or#aI==0 then
E("This boot was not profiled.",d.warning)
E("Add  memprofile = true  to /etc/boot.cfg and reboot.",d.dim)return end;E("=== Memory each boot stage used ===",d.title)
for aK,aJ in
ipairs(aI)do local aL=aI[aK+1]
if aL then
E(string.format(" %-30s %4dK  (%dK free after)",tostring(aJ.stage),math.floor((
(aJ.free or 0)- (aL.free or 0))/1024),math.floor((
aL.free or 0)/1024)),d.fg)else
E(string.format(" %-30s %5dK free",tostring(aJ.stage),math.floor((aJ.free or 0)/1024)),d.dim)end end;return end;local aA,aw=N.freeMemory(),N.totalMemory()local aB=aw-aA;local ax=aw>0 and math.floor(
aB*100/aw)or 0
local aE,aD=pcall(require,"kernel.monitor")local az=math.min(24,math.max(8,q-36))
local aF=
(aE and aD.memBar)and aD.memBar(aB,aw,az)or
(
string.rep("#",math.floor(ax/100*az))..string.rep("-",az-math.floor(ax/100*az)))E("=== Memory ===",d.title)
E(string.format(" RAM:  %dK used / %dK total   (%d%% used, %dK free)",math.floor(
aB/1024),math.floor(aw/1024),ax,math.floor(aA/1024)),d.fg)
local aG=ax<75 and d.highlight or(ax<90 and d.warning or d.error)E(" ["..aF.."]",aG)
local aH,ay=pcall(function()
return h.getHAL().systemInfo()end)if aH and ay and(ay.memTierName or ay.memTier)then
E(
" Tier: ".. (ay.memTierName or("T"..ay.memTier)),d.dim)end
local aC=h.getSwap and h.getSwap()
if aC and aC.usage then local aJ,aI=pcall(aC.usage)
if aJ and type(aI)=="table"then
E(string.format(" Swap: %dK / %dK on /var/swap   ('slow RAM' overflow)",math.floor((
aI.bytes or 0)/1024),math.floor((aI.max or 0)/1024)),d.dim)end else
E(" Swap: off   (enable in Boot Settings for low-RAM overflow)",d.dim)end;if aA<16*1024 then
E(" ! Low memory — near the ~16K danger zone.",d.warning)end
E("Live usage: 'monitor'.  Hardware tiers: 'hw'.",d.dim)end
b.hw=function(av,E)local aw=h.getHAL().systemInfo()
E("=== Hardware ===",d.title)
E(string.format(" CPU T%d    GPU T%d    RAM %s",aw.cpuTier or 0,aw.gpuTier or 0,aw.memTierName or("T"..
(aw.memTier or 0))),d.fg)local ay,ax=pcall(require,"kernel.datacard")if
ay and ax and ax.detect then local az=ax.detect()
E(" Data card: "..
(az.present and az.name or"none"),az.present and d.fg or d.dim)end
E(string.format(" Components: %d    Network: %s    Tunnel: %s",
aw.components or 0,aw.canNetwork and"yes"or"no",aw.hasTunnel and"yes"or"no"),d.dim)
E("Full component list: 'devices'.  Memory detail: 'mem'.  Live: 'monitor'.",d.dim)end;b.hardware=b.hw
b.ps=function(av,E)local az=u.getForeground(a.displayIdx)
local aw=I.sessionOf(a)local ax=(aw and aw.tier)or 0
local aA=aw and aw.user or"?"
local ay=(av[1]=="-v"or av[1]=="--verbose")and ax>=2
if ay then
E(string.format(" %-4s %-14s %-8s %-3s %-10s %-6s %s","PID","Name","State","DSP","Owner","CPU","Caps"),d.title)else
E(string.format(" %-4s %-16s %-8s %-3s %-10s %s","PID","Name","State","DSP","Owner","CPU"),d.title)end
E(string.rep("-",ay and 70 or 50),d.border)
for aC,aB in ipairs(u.list())do local aD=aB.user or"?"
if aD=="_kernel_"then aD="kernel"end;local aE=false
if ax>=2 then aE=true elseif ax>=1 and aD==aA then aE=true elseif ax>=1 then aE="redacted"end
if aE==true then local aG=d.fg;local aF=aB.state;if aB.tsr then aF="TSR"end;if aB.pid==az then
aG=d.highlight;aF=aF.." *"elseif aB.tsr then aG=d.dim end
if ay then local aH={}if
aB.caps then for aI in pairs(aB.caps)do aH[#aH+1]=aI end
table.sort(aH)end
E(string.format(" %-4d %-14s %-8s %-3s %-10s %-6.1f %s",aB.pid,aB.name:sub(1,14),aF,tostring(
aB.display or"-"),(aD):sub(1,10),aB.cpuTime or 0,#aH>0 and
table.concat(aH,",")or"-"),aG)else
E(string.format(" %-4d %-16s %-8s %-3s %-10s %.1fs",aB.pid,aB.name:sub(1,16),aF,tostring(aB.display or"-"),(aD):sub(1,10),
aB.cpuTime or 0),aG)end elseif aE=="redacted"then
E(string.format(" %-4d %-16s %-8s %-3s %-10s   ",aB.pid,"(other user)","?","?","?"),d.dim)end end;E("",d.dim)
E(" * = foreground  |  -v for caps (admin+)  |  'monitor' for the live view",d.dim)end
b.monitor=function(av,E)local ax,aw=pcall(require,"shell.panels.monitorapp")if not ax then
E(
"Monitor unavailable: "..tostring(aw),d.error)return end;aw.open(a)end;b.top=b.monitor
b.watch=function(av,E)
if not av[1]then
E("Usage: watch [seconds] <command ...>",d.dim)
E("  Opens a self-updating tab. e.g.  watch ps  ·  watch 2 df  ·  watch mem",d.dim)return end;local ay,aw=1,tonumber(av[1])if aw then ay=2 else aw=1 end;if aw<1 then aw=1 end;if not
av[ay]then E("Usage: watch [seconds] <command ...>",d.dim)
return end
local az=table.concat(av," ",ay)
local ax=(az:match("^(%S+)")or""):lower()
local aA={edit=true,lua=true,monitor=true,top=true,watch=true,launcher=true,launch=true,apps=true,kiosk=true,chat=true,more=true,man=true,vault=true,keychain=true,passwd=true,tutorial=true,bootsettings=true,useradd=true,["tape-auth"]=true}if aA[ax]then
E("Can't watch '"..ax.."' — it's interactive/screen-driven.",d.error)return end;do
local aC,aD,aE=I.tierRefusal(a,ax)
if aC then E(aC,d.error)a.lastDenial={cmd=ax,need=aD,have=aE}return end end;if not c.openLiveTab then
E("Live tabs aren't available in this shell.",d.error)return end
local function aB()local aC={}local aD={}for aL in
az:gmatch("%S+")do aD[#aD+1]=aL end;if#aD==0 then return aC end
local aE=aD[1]:lower()local aG={}for aL=2,#aD do aG[#aG+1]=aD[aL]end
local aH=I.tierRefusal(a,aE)if aH then aC[#aC+1]={aH,d.error}return aC end;local aF=b[aE]
if
not aF then local aM,aL=pcall(require,U)if aM and aL and aL.getCommand then
aF=aL.getCommand(aE)end end;if not aF then
aC[#aC+1]={"Unknown command: "..aE.."  [E-801 ERR_UNKNOWN_CMD]",d.error}return aC end
local aI=function(aL,aM)aC[#aC+1]={tostring(aL),
aM or d.fg}end;local aJ,aK=pcall(aF,aG,aI)if not aJ then
aC[#aC+1]={"Error: "..tostring(aK),d.error}end;return aC end;c.openLiveTab("watch: "..az,aB,aw)end
b.why=function(av,E)local aC=require(M)local ay=I.liveTier(a)
local aw={title=d.title or d.highlight or d.fg,ok=
d.success or d.highlight or d.fg,err=d.error,fix=d.highlight or d.fg,dim=d.dim}local function ax(aD)
for aF,aE in ipairs(aD)do E(aE.text,aw[aE.tone]or d.fg)end end
local az=av and av[1]and av[1]:lower()
if not az then local aD=a.lastDenial
if aD and aD.cmd then
ax(I.whyExplain(aD.cmd,aD.need,aD.have or ay,true))return elseif aD then
E("Your last blocked action needed "..I.tierName(aD.need).."; you are "..
I.tierName(aD.have or ay)..".",d.error)
E("Fix: run it on an admin/root account, or have an admin grant access.",aw.fix)return end;local aE=a.lastFailure
if aE then
E((aE.cmd and(aE.cmd.." failed:")or
"The last action failed:"),aw.title)E("  "..aE.text,d.error)
local aF,aH,aG=I.explainFailure(aE.text)if aG then E("  "..aG,aw.dim)end
if aF then ax(aF)else
E("No canned explanation for that one.",d.dim)
E("`log` has the kernel's own record of it, and `doctor` checks",d.dim)
E("memory, disks, services and security for a cause.",d.dim)end;return end
E("Nothing has failed since the last command ran.",d.dim)
E("why            — explain the last refusal or error.",d.dim)
E("why <code>     — explain an error code: E-402, ERR_PATH_PROTECTED, K4.",d.dim)
E("why <command>  — explain what a command needs and whether you can run it.",d.dim)return end;local aB=I.explainCode(av[1])if aB then ax(aB)return end
local aA=aC.entry(az)
ax(I.whyExplain(az,aA and aA.tier or 0,ay,aA~=nil))end
b.screendump=function(av,E)if not n or not n.dump then
E("Screen capture isn't available on this seat.",d.error)return end
local aD,ay=pcall(n.dump)if not aD or type(ay)~="table"or not ay.lines then
E("Screen capture failed.",d.error)return end
local aA=(av and av[1])and
f(av[1])or
f("screen-"..math.floor(h.uptime())..".txt")
local aE=(I.sessionOf(a)or{}).user or"?"
local aC=string.format("TOS screendump — seat %s · user %s · %dx%d · uptime %ds · read from the %s",tostring(a.displayIdx or"?"),aE,
ay.w or 0,ay.h or 0,math.floor(h.uptime()),tostring(ay.source or"?"))local aw=string.char(10)local ax=aC..
aw..string.rep("-",#aC)..aw..
table.concat(ay.lines,aw)..aw
if ay.bg then
ax=ax..aw..
"--- background colour runs, per row ---"..aw
for aI=1,(ay.h or 0)do local aJ=ay.bg[aI]
if aJ then local aK={}for aM,aL in ipairs(aJ)do
aK[#aK+1]=string.format("%d-%d:%s",aL.from,aL.to,
aL.c and string.format("%06X",aL.c)or"nil")end
ax=ax..
string.format("row %2d  %s",aI,table.concat(aK,"  "))..aw end end;local aH=a.T or{}
ax=ax..
aw..
"theme: bg="..
string.format("%06X",aH.bg or 0)..
"  statusbar_bg="..string.format("%06X",
aH.statusbar_bg or 0)..
"  menubar_bg="..string.format("%06X",
aH.menubar_bg or aH.bar_bg or 0)..aw end;local az=function(aH)
return aH and string.format("%06X",aH)or"nil"end;ax=ax..aw..
"--- cache vs glass ---"..aw
if
ay.disagree and#ay.disagree>0 then
ax=ax.."THE SHADOW DISAGREES WITH THE SCREEN on "..#ay.disagree..
" row(s)."..aw
for aI,aH in ipairs(ay.disagree)do
ax=ax..
string.format("  row %2d col %2d  glass=%s  shadow believes=%s",aH.row,aH.col,az(aH.glass),az(aH.shadow))..aw;local aJ=ay.pageBg and ay.pageBg[aH.row]
if aJ then local aK={}for aI,aL in
ipairs(aJ)do
aK[#aK+1]=string.format("%d-%d:%s",aL.from,aL.to,az(aL.c))end
ax=ax.."    off-screen page holds: "..
table.concat(aK,"  ")..aw end end elseif ay.shadowBg then
ax=ax.."none — the shadow matches the glass everywhere."..aw else
ax=ax.."(no shadow active on this seat)"..aw end;local i=ay.state
if i then
ax=ax..
aw..
"--- display machinery ---"..
aw..
"  shadow="..
tostring(i.shadow)..
"  colour cache: fg="..

az(i.lastFg)..
" bg="..
az(i.lastBg)..
aw..
"  backbuffer="..
tostring(i.backbuffer)..
"  broken="..
tostring(i.backBroken)..

"  frameDepth="..
tostring(i.frameDepth)..
"  pageStale="..
tostring(i.pageStale)..aw..
"  writerGen="..
tostring(i.writerGen)..
"  mine="..tostring(i.myWriterGen).."  lastWriterIsMe="..
tostring(i.lastWriterIsMe)..aw end;local aB=_G._TOS and _G._TOS.fs;if
not(aB and aB.writeFile)then
E("No filesystem available to write the dump.",d.error)return end
local aF,aG=aB.writeFile(aA,ax)
if aF then
E("Screen captured -> "..aA.."  (".. (ay.h or 0).." rows)",
d.success or d.fg)
E("Attach it to a bug report, or 'cat' it to read it back.",d.dim)else
E("Could not write "..aA..": "..tostring(aG),d.error)end end
b.crash=function(av,E)if not r(E)then return end;local aw=_G._TOS and _G._TOS.fs
if not
(aw and aw.list)then E("No filesystem.",d.error)return end
if av and av[1]then local aA=av[1]:find("/")and f(av[1])or
("/var/crash/"..av[1])
local aC,aB=pcall(aw.readFile,aA)if not aC or not aB then
E("No such crash report: "..aA,d.error)return end;for aD in
(tostring(aB).."\n"):gmatch("(.-)\n")do E(aD,d.fg)end;return end;local az,ay=pcall(aw.list,"/var/crash")local ax={}if
az and type(ay)=="table"then
for aB,aA in ipairs(ay)do aA=tostring(aA):gsub("/$","")if
aA~=""and aA~="NEW"then ax[#ax+1]=aA end end end
if#ax==0 then
E("No crash reports — clean so far.",d.dim)
E("(TOS saves one here on a panic or an unrecoverable shell, so you",d.dim)E(" can read it after rebooting.)",d.dim)return end
E("Crash reports in /var/crash:",d.title or d.highlight or d.fg)for aB,aA in ipairs(ax)do E("  "..aA,d.fg)end
E("Read one with:  crash <name>",d.dim)end
b.history=function(av,E)for aw,ax in ipairs(a.cmdHistory)do
E(string.format(" %3d  %s",aw,ax),d.dim)end;if#a.cmdHistory==0 then
E("(no history)",d.dim)end end
b.uptime=function(av,E)local aw=h.uptime()local ax=math.floor(aw/3600)local ay=math.floor(
(aw%3600)/60)local az=math.floor(aw%60)
E(string.format("Uptime: %dh %dm %ds (%.1fs total)",ax,ay,az,aw),d.fg)end
b.date=function(av,E)
local aw=h.getConfig and h.getConfig()or nil
if av[1]=="tz"or av[1]==X or av[1]=="set"then local aD=(aw and aw.get and
aw.get(X))or 0
local aC=tonumber(av[2])
if not aC then E("Timezone offset: "..aD.."h",d.fg)
E("Usage: date tz <hours>   e.g. 'date tz -5'",d.dim)
E("OpenComputers has no settable clock; this only shifts the",d.dim)
E("DISPLAYED time relative to the world/host clock.",d.dim)return end;if aC<-23 or aC>23 then
E("Offset must be between -23 and 23.",d.error)return end;if not r(E)then return end
if not
(aw and aw.set)then E("No writable config available.",d.error)return end;aw.set(X,aC)if aw.save then aw.save()end
E("Timezone offset set to "..aC.."h. (was "..
aD.."h)",d.highlight)return end;local ay=av[1]or"%Y-%m-%d %H:%M:%S"local az=
(aw and aw.get and aw.get(X))or 0
local aA=os.time()+ (az*3600)local aB,ax=pcall(os.date,ay,aA)if aB and ax then
E(tostring(ax),d.fg)else
E(tostring(ax or"date error"),d.error)end end;b.time=b.date
b.keys=function(av,E)local aE,aw=pcall(require,W)if not aE or not aw then
E("Keybind module unavailable.",d.error)return end
local ax=(av[1]or"list"):lower()local ay=false;for aG=2,#av do
if av[aG]==T then ay=true;table.remove(av,aG)break end end
local aF=(a.who=="root")and"/root"or(
"/home/".. (a.who or""))
local aA=ay and"/etc/keys.cfg"or(aF.."/.keys.cfg")local aC,az=pcall(require,"kernel.serialize")
local function aD()
if not(aC and az and
a.F.exists(aA))then return{}end;local aG=a.F.readFile(aA)if not aG then return{}end
local aI,aH=pcall(az.decode,aG,{maxBytes=8192})return
(aI and type(aH)=="table")and aH or{}end
local function aB(aG)if not(aC and az)then return false end
local aH=a.F.writeFile(aA,az.encode(aG))if aH then aw.reload()end;return aH end
if ax=="list"or ax=="ls"then
E("TOS standard shortcuts:",d.title)for aH,aG in ipairs(aw.actions(a.who))do
E(string.format("  %-9s %-14s %s",aG.action,aG.keys,aG.help),
aG.isDefault and d.fg or d.highlight)end
E("",d.dim)
E("Reserved by the kernel — these cannot be rebound:",d.dim)for aH,aG in ipairs(aw.reserved())do
E(string.format("  %-9s %s",aG.key,aG.help),d.dim)end;E("",d.dim)
E("Change one:  keys set quit F4       (add --system for everyone)",d.dim)E("Undo:        keys reset [action]",d.dim)
E("Every first-party TOS program follows this table.",d.dim)elseif ax=="set"then local aG,aJ=av[2],av[3]
if not(aG and aJ)then
E("Usage: keys set <action> <key> [<key>...]",d.dim)
E("  e.g. keys set quit F4      keys set find ^F",d.dim)
E("Key names are written the way you say them: ^Q, F10, Ctrl+S, /",d.dim)return end;if not aw.DEFAULTS[aG]then
E("No such action: "..aG.."  (see 'keys list')",d.error)return end;local aH={}
for aK=3,#av do local aL=av[aK]if not
aw.parse(aL)then
E("Not a key name: '"..aL.."'  (try ^Q, F10, Ctrl+S, /)",d.error)return end
if aw.isReserved(aL)then
E(aL..
" is reserved by the kernel and never reaches a program.",d.error)E("See 'keys list' for the reserved set.",d.dim)return end;aH[#aH+1]=aL end;local aI=aD()aI[aG]=aH
if aB(aI)then
E(aG..
" is now "..table.concat(aH," ").. (ay and"  (machine-wide)"or
""),d.highlight)else E(ae.. (ay and S or"."),d.error)end elseif ax=="reset"then local aG=av[2]local aH=aD()
if aG then if not aw.DEFAULTS[aG]then
E("No such action: "..aG,d.error)return end;aH[aG]=nil;if aB(aH)then
E(aG.." is back to the default.",d.highlight)else E(af,d.error)end else if aB({})then
E("All shortcuts back to the defaults.",d.highlight)else E(af,d.error)end end else
E("keys — TOS's standard keyboard shortcuts",d.title)
E("  keys list                     Show them",d.fg)
E("  keys set <action> <key>...    Rebind one",d.fg)
E("  keys reset [action]           Back to the default",d.fg)
E("Add --system to change them for every user (/etc/keys.cfg, admin).",d.dim)end end
b.menu=function(av,E)local aw=(av[1]or"list"):lower()local ay=false
for aG=2,#av do if
av[aG]==T then ay=true;table.remove(av,aG)break end end;local aE=(a.who=="root")and"/root"or
("/home/".. (a.who or""))local ax=
ay and"/etc/menu.cfg"or(aE.."/.menu.cfg")
local aF,aC=pcall(require,"kernel.serialize")
if not aF or not aC then E("serialize unavailable",d.error)return end
local function az()if not a.F.exists(ax)then return{}end
local aG=a.F.readFile(ax)if not aG then return{}end
local aI,aH=pcall(aC.decode,aG,{maxBytes=8192})return
(aI and type(aH)=="table")and aH or{}end
local function aA(aG)return a.F.writeFile(ax,aC.encode(aG))end;local function aB()local aH,aG=pcall(require,"shell.panels.draw")
if
aH and aG and aG.buildMenuDefs then a.menuDefs=aG.buildMenuDefs(a)end end
local function aD(aG)if
aG.remove then
return"remove "..tostring(aG.remove)..
(aG.menu==true and" (whole menu)"or"")end;if aG.rename then return
"rename "..
tostring(aG.rename).." -> "..tostring(aG.to)end;if
aG.move then return
"move "..tostring(aG.move).." -> "..tostring(aG.menu)end
if aG.menu and not
aG.cmd then return"new menu "..tostring(aG.menu)end;return
string.format("[%s] %s -> %s",aG.menu or"Tools",aG.add or aG.label or"?",aG.cmd or"?")end
if aw=="list"or aw=="ls"then local aG=az()
if#aG==0 then
E("No menu edits in "..ax..".",d.dim)
E("Add one:  menu add <label> <command...> [in <Menu>]",d.dim)
E("Machine-wide instead of just you:  menu add ... --system",d.dim)return end;E("Menu edits ("..ax.."):",d.title)for aH,aI in ipairs(aG)do
E(string.format("  %d. %s",aH,aD(aI)),d.fg)end elseif aw=="show"then
local aH,aG=pcall(require,"shell.panels.draw")if not aH or not aG or not aG.buildMenuDefs then
E("Menu system unavailable.",d.error)return end
for aJ,aI in
ipairs(aG.buildMenuDefs(a))do E(aI.label,d.title)
for aJ,aK in ipairs(aI.items)do if aK.sep then E("    ---",d.dim)else
E(string.format("    %-20s %s",aK.label,(
aK.action or""):match("^run:(.+)$")or(aK.action or"")),d.fg)end end end
E("Change it with: menu add|remove|rename|move  (add --system for everyone)",d.dim)elseif aw==al or aw=="move"then local aH,aI=av[2],av[3]if not(aH and aI)then
E("Usage: menu "..aw..

" <name> <".. (aw==al and"new name"or"Menu")..">",d.dim)return end;local aG=az()
aG[#aG+1]=(
aw==al)and{rename=aH,to=aI}or{move=aH,menu=aI}
if aA(aG)then aB()
E("Saved. "..aD(aG[#aG]),d.highlight)else E(ae.. (ay and S or"."),d.error)end elseif aw=="hide"then local aG=av[2]if not aG then
E("Usage: menu hide <item or Menu name>",d.dim)
E("Hides a built-in entry. 'menu reset' brings everything back.",d.dim)return end
local aH=az()
aH[#aH+1]={remove=aG,menu=(av[3]=="menu")or nil}
if aA(aH)then aB()E("Hidden: "..aG,d.highlight)else E(ae..
(ay and S or"."),d.error)end elseif aw=="reset"then if aA({})then aB()
E("Menu reset to the built-in bar ("..ax.." cleared).",d.highlight)else
E("Reset failed".. (ay and S or"."),d.error)end elseif
aw=="add"then local aH=av[2]
if not aH or not av[3]then
E("Usage: menu add <label> <command...> [in <Menu>]",d.dim)
E("  e.g. menu add Tetris tetris   |   menu add Disk df in System",d.dim)return end;local aG=table.concat(av," ",3)
local aI=aG:match("%s+in%s+(%S+)%s*$")if aI then aG=aG:gsub("%s+in%s+%S+%s*$","")end
if
#aH>24 then E("Label too long (max 24).",d.error)return end;if#aG==0 or#aG>200 then
E("Command empty or too long.",d.error)return end;local aJ=az()
aJ[#aJ+1]={label=aH,cmd=aG,menu=aI or"Tools"}
if aA(aJ)then aB()
E(string.format("Added '%s' -> %s  (menu: %s)",aH,aG,aI or"Tools"),d.highlight)else E("Save failed (is your home writable?).",d.error)end elseif aw=="remove"or aw=="rm"or aw=="del"then
local aG=tonumber(av[2])local aH=az()if not aG or not aH[aG]then
E("Usage: menu remove <#>   (see 'menu list')",d.error)return end
local aI=table.remove(aH,aG)if aA(aH)then aB()
E("Removed '".. (aI.label or"?").."'.",d.highlight)else E(af,d.error)end else
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
b.tree=function(av,E)local ay=f(av[1]or a.cwd)
local aB=tonumber(av[2])or 3;local az=400;local aw,ax=0,false
local function aA(aC,aD,aE)if ax then return end;if aE>aB then return end
local aF=e.list(aC)or{}
table.sort(aF,function(aG,aH)
local aI=e.isDirectory(aC.."/".. (aG:gsub("/$","")))
local aJ=e.isDirectory(aC.."/".. (aH:gsub("/$","")))if aI~=aJ then return aI end;return aG<aH end)
for aG,aH in ipairs(aF)do if aw>=az then ax=true;return end;local aI=aH:gsub("/$","")
local aK=aC=="/"and(
"/"..aI)or(aC.."/"..aI)local aJ=e.isDirectory(aK)local aL=(aG==#aF)
local aM=aL and"`-- "or"|-- "local aN=aJ and d.dir or d.fg;E(aD..
aM..aI.. (aJ and"/"or""),aN)aw=aw+1;if aJ then
aA(aK,aD.. (aL and"    "or
"|   "),aE+1)end end end;E(ay,d.title)aA(ay,"",1)if ax then
E(string.format("(truncated at %d entries; raise the limit or narrow the path)",az),d.dim)end end
b.whoami=function(av,E)if g then local aw=g.getSession(i)
E(aw and aw.user or"root",d.fg)else E(a.who,d.fg)end end
b.passwd=function(av,E)
if not g then E("No user system",d.error)return end;local ay=j("Current password: ",64,true)if not ay then return end
local aw=j("New password: ",64,true)if not aw then return end;local aC=j("Confirm new password: ",64,true)if
aC~=aw then
a.lastOut={"Passwords do not match — unchanged.",d.error}return end;if aw==""then
a.lastOut={"Password cannot be empty.",d.error}return end;local az=g.getSession(i)local aA=
az and az.user or"root"
local aB,ax=g.changePassword(aA,aA,ay,aw)
if aB and ax then
a.lastOut={"Password changed. "..tostring(ax),d.warning}elseif aB then a.lastOut={"Password changed.",d.highlight}else
a.lastOut={tostring(ax),d.error}end end
local function ap(E,av,aw)local aA=a.st
local ay=g.registerSession and g.registerSession(E)or nil;local aB,az=pcall(require,V)
local ax=aB and az.current and az.current()local aC=ax and ax.principal;if ay then a.st=ay end
if ax then ax.principal=E end;local aD,aE=pcall(av)a.st=aA;if ax then ax.principal=aC end;if ay and g.logout then
pcall(g.logout,ay)end;if not aD then
aw("sudo: "..tostring(aE),d.error)end end
local function t()if not a._sudo then return false end;a.st=a._sudo.origSt
local aw,E=pcall(require,V)local av=aw and E.current and E.current()if av then
av.principal=a._sudo.origPrincipal end;if a._sudo.token and g.logout then
pcall(g.logout,a._sudo.token)end;a._sudo=nil;return true end;a.sudoDrop=t
b.sudo=function(av,E)
if not g then E("No user system",d.error)return end;local ay=I.sessionOf(a)local aw=av[1]
if aw=="setup"then if not w(E)then return end;local aE=2;if
av[2]=="root"then aE=3 elseif av[2]and av[2]~="admin"then
E("Usage: sudo setup [admin|root]",d.dim)return end
local aD=j("New elevation password: ",64,true)if not aD or aD==""then E("Aborted.",d.dim)return end
if
j("Confirm: ",64,true)~=aD then E("Passwords do not match.",d.error)return end;local aF,aG=g.setElevation(ay,aD,aE)
if aF then
E("Elevation configured (cap: "..
I.tierName(aE)..").",d.highlight)else E(tostring(aG),d.error)end;return elseif aw=="off"then if not w(E)then return end
local aD,aE=g.clearElevation and g.clearElevation(ay)if aD then E("Elevation disabled.",d.highlight)else
E(tostring(aE or"unavailable"),d.error)end;return elseif aw=="-k"then
E(
t()and"Elevated session dropped."or"No active elevation.",d.dim)return end;if not aw then
E("Usage: sudo <command> | sudo -s | sudo -k | sudo setup [admin|root] | sudo off",d.dim)return end
if
I.liveTier(a)<1 then E("sudo: guests cannot elevate.",d.error)return end
local aA=g.elevationInfo and g.elevationInfo()or{configured=false}if not aA.configured then
E("sudo: elevation is not configured. Root: sudo setup [admin|root]",d.warning)return end
local az=j("[sudo] elevation password: ",64,true)if az==nil then E("Aborted.",d.dim)return end
local ax,aB=g.elevate(ay,az)if not ax then
E("sudo: "..tostring(aB or"elevation failed"),d.error)return end
if aw=="-s"then t()
local aE=g.registerSession and
g.registerSession(ax)or nil;local aG,aF=pcall(require,V)
local aD=aG and aF.current and aF.current()
a._sudo={origSt=a.st,origPrincipal=aD and aD.principal,token=aE}if aE then a.st=aE end;if aD then aD.principal=ax end
E("Elevated to "..
I.tierName(ax.tier)..". 'sudo -k' or 'logout' drops it.",d.highlight)return end;local aC=table.concat(av," ")
ap(ax,function()if not a.execOne then
E("sudo: executor unavailable",d.error)return end;local aD=a.execOne(aC)if
type(aD)=="table"then
for aF,aE in ipairs(aD)do if type(aE)=="table"then E(aE[1],aE[2]or d.fg)else
E(tostring(aE),d.fg)end end end end,E)end;b.logout=function(E,av)I.logout(a)end
b.cli=function(av,E)if a.isCLI then
E("You are already at the command line. Type 'tui' for the full interface.",d.dim)return end;a._exitTo="cli"end
b.tui=function(av,E)if a.isCLI then E("Returning to the full interface…",d.dim)
a._exitTo="tui"return end
E("You are already in the full interface. Type 'cli' for the command line.",d.dim)end
b.reboot=function(av,E)local aw,ax=I.canPowerOff(a)
if not aw then E(ax,d.error)return end;h.reboot()end
b.shutdown=function(av,E)local aw,ax=I.canPowerOff(a)
if not aw then E(ax,d.error)return end;h.shutdown()end
b.env=function(E,av)local az,aw=pcall(require,"kernel.env")if not az then
av("Env module unavailable",d.error)return end;local ay=h.getProc()local ax=
ay and ay.current()or nil
if E[1]then
local aA,aB=E[1]:match("^([%w_]+)=(.*)$")if aA then aw.write(ax,aA,aB)av(aA.."="..aB,d.highlight)else
local aC=aw.read(ax,E[1])
av(E[1].."="..tostring(aC or""),d.fg)end else
local aA=aw.list(ax)for aB,aC in pairs(aA)do
av("  "..aB.."="..tostring(aC),d.fg)end end end;b.export=b.env;b.set=b.env
b["tape-menu"]=function(av,E)
local aD,ax=pcall(require,"shell.launcher")if not aD or not ax then
E("Menu engine unavailable (low RAM?)",d.error)return end;if not n or not n.getSize then
E("tape-menu needs a screen.",d.error)return end;local ay=nil
local function aE(aK)local aL={}local aM={}for aU in
aK:gmatch("%S+")do aM[#aM+1]=aU end;if#aM==0 then return aL end
local aN=aM[1]local aP={}for aU=2,#aM do aP[#aP+1]=aM[aU]end
local aQ=I.tierRefusal(a,aN:lower())if aQ then aL[#aL+1]={aQ,d.error}return aL end;if not ay then
ay=require(M).build(a,c)end;local aO=ay[aN]
if not aO then local aV,aU=pcall(require,U)if aV and aU and
aU.getCommand then aO=aU.getCommand(aN)end end;if not aO then
aL[#aL+1]={"Unknown command: "..aN,d.error}return aL end;local aR=function(aU,aV)
aL[#aL+1]={tostring(aU),aV or d.fg}end
local aS,aT=pcall(aO,aP,aR)if not aS then
aL[#aL+1]={"Error: "..tostring(aT),d.error}end;return aL end;local aA=O.list and O.list("tape_drive")()
if
not aA then E("No tape drive found.",d.error)return end;local aw=O.proxy(aA)
local aF,aG=pcall(function()return aw.isReady()end)
if not aF or not aG then E("No tape inserted.",d.warning)return end
local aH=(aw.getSize and aw.getSize())or 0
if aH<=0 then E("Tape is empty.",d.warning)return end
local az=j and j("Tape menu passphrase: ",64,true)or nil;if not az or az==""then E(ab,d.dim)return end
local aI,aB=pcall(require,"kernel.vault")
if not aI or not aB then E("vault unavailable",d.error)return end;local aC,aJ=ax.readTapeMenuFromDrive(aw,az,aB)if not aC then
E(tostring(aJ),d.error)return end
ax.run({display=n,profile=aC,runLine=aE,title="Tape toolbox"})if c.drawAll then pcall(c.drawAll)end end
b.clip=function(av,E)local az,aw=pcall(require,"kernel.clipboard")if not az or not aw then
E(
"Clipboard unavailable: "..tostring(aw),d.error)return end;local ax=a.displayIdx;local ay=av[1]
if
not ay then
E("Clipboard: "..aw.describe(ax),d.title)local aA=aw.get(ax)
if aA and not aw.isEmpty(ax)then
local aB=math.min(#aA,10)for aC=1,aB do E("  "..aA[aC],d.fg)end;if#aA>aB then
E("  ... "..
(#aA-aB).." more line(s)",d.dim)end end
E("Usage: clip [set <text> | clear]   Copy: "..
(function()local aC,aB=pcall(require,W)
return(aC and aB)and
aB.label("copy",a.who)or"Ctrl+Insert"end)(),d.dim)return end;if ay=="clear"then aw.clear(ax)
E("Clipboard cleared.",d.highlight)return end
if ay=="set"then
local aA=table.concat(av," ",2)
if aA==""then E("Usage: clip set <text>",d.warning)return end;local aC,aB=aw.set(aA,ax)if not aC then
E("Could not set clipboard: "..tostring(aB),d.error)return end;if aB then
E("Clipboard set, TRUNCATED at the cap: "..
aw.describe(ax),d.warning)else
E("Clipboard: "..aw.describe(ax),d.highlight)end;return end;E("Usage: clip [set <text> | clear]",d.warning)end
b.desktop=function(av,E)local ax,aw=pcall(require,"shell.panels.desktop")if not ax then
E(
"Desktop unavailable: "..tostring(aw),d.error)return end;aw.open(a)end
b.settings=function(av,E)local ax,aw=pcall(require,"shell.panels.settingsapp")if
not ax then
E("Settings unavailable: "..tostring(aw),d.error)return end;aw.open(a)end
b.lang=function(av,E)local aA,aw=pcall(require,"kernel.i18n")if not aA or not aw then
E(
"i18n unavailable: "..tostring(aw),d.error)return end;local ax=av[1]
if not ax then
E(ad..aw.language()..
"  ("..aw.languageName()..")",d.title)E("Installed catalogs:",d.fg)for aF,aE in ipairs(aw.available())do
local aG=(aE.code==
aw.language())and" * "or"   "
E(aG..string.format("%-8s %s",aE.code,aE.name),d.fg)end
E("Usage: lang <code> | lang system <code> | lang dump [path]",d.dim)
E("Catalogs are DATA files at /usr/lang/<code>.lang — see 'man lang'.",d.dim)return end
if ax=="system"then if not r(E)then return end;local aE=av[2]if not aE then
E("Usage: lang system <code|en>",d.dim)return end;local aF,aG=aw.setLanguage(aE)
if not aF then E(
"Cannot set: "..tostring(aG),d.error)return end
if p and p.set then p.set("language",aE)if p.save then p.save()end end
E("System language: "..aw.language(),d.highlight)return end
if ax=="dump"then
local aF=f(av[2]or"/tmp/lang-template.lang")local aG=aw.keysSeen()if#aG==0 then
E("No keys seen yet — visit a few screens first (log out/in, open the Desktop).",d.warning)return end
local aE={"-- TOS language catalog template (every t() key seen this session).","-- Translate the values, set meta.code/name, save as /usr/lang/<code>.lang,","-- then run `lang <code>`. Untranslated keys keep their English default.","-- /usr is a protected system path: as root, `protect off` to copy this","-- in and `protect on` after -- or ship the catalog as a package.","return {",'  meta = { code = "xx", name = "Language name" },',"  strings = {"}for aK,aJ in ipairs(aG)do
aE[#aE+1]=string.format("    [%q] = %q,",aJ.key,aJ.default)end;aE[#aE+1]="  },"
aE[#aE+1]="}"
if not o(aF)then E("Cannot write: "..aF,d.error)return end
local aI,aH=e.writeFile(aF,table.concat(aE,"\n").."\n")
if aI then
E("Template with "..#aG.." key(s) -> "..aF,d.highlight)k()else E(ag..aF,d.error)
if aH then E(tostring(aH),d.dim)end
if aF:sub(1,10)=="/usr/lang/"then
E("Dump to /tmp (the default), then copy it in under `protect off`,",d.dim)E("or ship the catalog as a package.",d.dim)end end;return end;local aB,aC=aw.setLanguage(ax)if not aB then
E("Cannot set '"..tostring(ax)..
"': "..tostring(aC),d.error)E("Run 'lang' to list installed catalogs.",d.dim)
return end
local az=I.sessionOf(a)local aD,ay=pcall(require,"kernel.profile")
if aD and ay and ay.load and
ay.save then local aE=ay.load(az)
aE.lang=
(aw.language()~="en")and aw.language()or nil;local aF,aG=ay.save(aE,az)
if aF then
E(ad..
aw.language().."  (saved to your profile)",d.highlight)else
E("Language set for this session (profile save failed: "..tostring(aG)..")",d.warning)end else
E(ad..aw.language().."  (this session)",d.highlight)end end end