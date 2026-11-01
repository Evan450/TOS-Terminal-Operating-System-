
local ae,N,af,V,W,ag,O,ah,ai,X,aj,ak,al,Y,am,an,M,ao,Z,_,ap,aq,ar,as,aa,P,ab="  Examples:","  Subcommands:"," %-24s %8s"," (needs admin for /etc).","--system","Cancelled.","Cannot read: ","Keychain is locked.","Language: ","No such file: ","Save failed","Save failed.","Write failed: ","[^/]+$","^(.*)/[^/]+/?$","decrypt","encrypt","function","kernel.pkg","kernel.process","profile module unavailable","recursive","rename","save failed","shell.keys","shell.panels.commands","timezone"local Q=require("computer")local R=require("component")
local L=require("shell.panels.helpers")local S=function()end
do local b,a=pcall(require,_)if b and a and a.yieldCooperative then
S=a.yieldCooperative end end;local function T()local a,b=pcall(require,"shell.panels.home")
return(a and b)or nil end;local function ac(a)local b=T()return
b and b.cycleKeyLabel(a)or"F2"end
local function at(a)
local b=T()if b and b.enabled(a)then
return b.viewKeyLabel(a).."  Tiles / files "end;return"F2  Next tab      "end
local function ad(a)local e=T()local d,b=pcall(require,aa)if not(d and b)then
return"Copy Ctrl+Insert  Cut ^X  Paste ^V"end;local c=a and a.who or nil;return
"Copy "..
b.label("copy",c).."  Cut "..
b.label("cut",c).."  Paste "..b.label("paste",c)end
local function U(a)local c,b=pcall(require,aa)return
(c and b and b.quitHint)and b.quitHint(
a and a.who or nil)or"^Q"end
local function au(a)local b=ac(a)return b..
string.rep(" ",math.max(1,12-#b)).."Next tab   "end
return
function(b,a,c)local h,J,u,e,n,g=a.K,a.E,a.P,a.F,a.D,a.U;local p,A,i=a.SC,a.NM,a.st;local d=a.T;local B=a.tier
local q,v=a.W,a.H;local f=c.rp;local s=c.openViewTab;local K=c.openEditTab;local k=c.refreshBrowser
local l=c.canRead;local o=c.canWrite;local av=c.canAccess;local w=c.rootOnly;local r=c.adminOnly
local aw=c.makeProgramEnv;local m=L.fmtSz
local ax=function(E)return L.expandBuf(a,E)end;local j=c.promptInput
b.help=function(ay,E)
local az=ay and ay[1]and ay[1]:lower()
if az=="cp"or az=="copy"then E("cp <source> <dest>",d.title)
E("  Copy a file. Both paths are required.",d.fg)
E("  Paths starting with / are absolute; others are relative to cwd.",d.fg)E(ae,d.dim)
E("    cp notes.txt /home/root/notes_bak.txt",d.dim)E("    cp /etc/cfg.conf /tmp/cfg.conf",d.dim)
E("  Tip: Use F5 in the browser for clipboard-style copy.",d.highlight)elseif az=="mv"then E("mv <source> <dest>",d.title)
E("  Move or rename a file.",d.fg)E(ae,d.dim)
E("    mv old.txt new.txt           (rename in cwd)",d.dim)
E("    mv /tmp/work.lua /home/root/ (move to dir)",d.dim)elseif az=="cd"then E("cd [dir]",d.title)
E("  Change directory. With no argument, prints current directory.",d.fg)
E("  Special paths:  ..  (parent)   ~  (home dir)",d.fg)elseif az=="find"then E("find [path] [-name pattern]",d.title)
E("  Recursively search for files. Pattern uses Lua patterns.",d.fg)E(ae,d.dim)E("    find /tos -name *.lua",d.dim)
E("    find /home",d.dim)elseif az=="grep"then E("grep <pattern> <file>",d.title)
E("  Search file lines for pattern (plain text, not regex).",d.fg)
E("  Example:  grep function /tos/shell/init.lua",d.dim)elseif az=="flash"then E("flash <file>",d.title)
E("  Write a Lua file to the EEPROM (overwrites BIOS!).",d.fg)
E("  Prompts for confirmation. Use to install a new BIOS.",d.fg)E("  Example:  flash /tos/bios.lua",d.dim)elseif az=="edit"then
E("edit <file>",d.title)
E("  Open file in editor tab. Creates the file if it doesn't exist.",d.fg)
E("  Keys:  Ctrl+S = save   Ctrl+Q = close tab   Ctrl+F = find",d.dim)E("  Ctrl+H = find/replace  Ctrl+Z = undo",d.dim)E(
"  Select: Shift+arrows.  "..ad(a),d.dim)
E("  With nothing selected, copy/cut take the whole line.",d.dim)
E("  Use "..ac(a).." to switch tabs, F4 to close.",d.dim)elseif az=="run"then E("run <file> [args...]",d.title)
E("  Execute a Lua file in the current environment.",d.fg)
E("  Args are passed as a table in the second argument.",d.fg)elseif az=="tape"then E("tape [subcommand]",d.title)
E("  Data storage on Computronics tapes (requires module).",d.fg)
E("  If the tape package is not installed, shows",d.fg)
E("  instructions for installing it or building your own.",d.fg)E("",d.fg)
E("  Subcommands (when module is active):",d.dim)E("    detect           List tape drives",d.dim)
E("    info             Tape size, label, format",d.dim)E("    label [name]     Get/set tape label",d.dim)
E("    store <path>     Archive file/dir to tape",d.dim)
E("    restore [path]   Restore archive from tape",d.dim)
E("    list             List archived entries",d.dim)
E("    dump [off] [len] Hex dump of tape bytes",d.dim)E("    erase [full]     Quick or full wipe",d.dim)
E("    raw read/write   Low-level byte I/O",d.dim)elseif az=="net"then E("net [subcommand]",d.title)
E("  Network management (requires modem or linked card).",d.fg)E("",d.fg)E(N,d.dim)
E("    status              Show network status",d.dim)
E("    discover / scan     Broadcast ping to find peers",d.dim)
E("    peers / list        List known peers and trust levels",d.dim)
E("    trust <addr> [full] Elevate peer to KNOWN or TRUSTED",d.dim)E("    block <addr>        Block a peer",d.dim)
E("    send <addr> <msg>   Send message to trusted peer",d.dim)E("",d.fg)
E("  Related: ping <addr>, hostname [name], chat",d.dim)elseif

az=="pkg"or az=="mod"or az=="module"or az=="modules"or az=="package"or az=="packages"then E("pkg [subcommand]",d.title)
E("  Package manager — install and manage add-ons. (Replaces the old",d.fg)
E("  'mod'/module manager, retired in v1.3.1.)",d.fg)E("",d.fg)E(N,d.dim)
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
E("  Shortcuts: 'install <name>' and 'uninstall <name>' work too.",d.dim)elseif az=="monitor"or az=="top"then
E("monitor   (alias: top; also opened with Ctrl+T)",d.title)
E("  The live System Monitor — one screen showing what TOS is doing.",d.fg)E("",d.fg)E("  Shows:",d.dim)
E("    · Every process (kernel AND user), each explained, with owner,",d.dim)
E("      state, CPU and seat — auto-refreshing.",d.dim)
E("    · rc.d services and their status (admin).",d.dim)E("    · Memory and uptime vitals.",d.dim)
E("",d.fg)
E("  Runs as a full-screen tab: scrolls, never truncates, per-seat.",d.dim)E("",d.fg)E("  Keys:",d.dim)
E("    up/down move   Enter switch-to   K kill   T suspend/resume (TSR)",d.dim)
E("    Enter start-stop a service (admin)   R refresh   "..U(a).." close",d.dim)elseif az=="cron"then E("cron [subcommand]",d.title)
E("  Manage scheduled tasks.  (admin+)",d.fg)E("",d.fg)E(N,d.dim)
E("    list                Show all cron jobs",d.dim)
E("    add <interval> <cmd> Schedule a command",d.dim)
E("    rm <id>             Remove a cron job",d.dim)elseif az=="service"then E("service [subcommand]",d.title)
E("  Manage startup services.  (admin+)",d.fg)E("",d.fg)E(N,d.dim)
E("    (none)              List all services and status",d.dim)E("    start <name>        Start a service",d.dim)
E("    stop <name>         Stop a service",d.dim)elseif az=="users"or az=="useradd"or az=="userdel"or
az=="usermod"then
E("User Management  (admin/root)",d.title)
E("  users                   List all user accounts",d.fg)
E("  useradd <name>          Create a new user",d.fg)E("  userdel <name>          Delete a user",d.fg)
E("  usermod <user> <action> Modify a user:",d.fg)
E("    lock / unlock         Lock or unlock an account",d.dim)
E("    admin / user          Set role to admin or user",d.dim)
E("  whoami                  Show current user",d.fg)
E("  passwd                  Change your password",d.fg)elseif az=="disk"then E("disk [subcommand]",d.title)
E("  Manage removable disks (floppies, HDDs).",d.fg)E("",d.fg)E(N,d.dim)
E("    list                List removable disks",d.dim)
E("    info <mount>        Show disk contents",d.dim)
E("    install <mount>     Install module from disk (admin)",d.dim)
E("    export <name> <mnt> Write module to disk    (admin)",d.dim)E("    eject <mount>       Unmount a disk",d.dim)elseif az==
"redstone"or az=="rs"then
E("redstone [subcommand]  (alias: rs)",d.title)E("  Control redstone I/O on all sides.",d.fg)
E("",d.fg)E(N,d.dim)
E("    (none)              Show redstone levels",d.dim)
E("    set <side> <level>  Set output (0-15)",d.dim)
E("    pulse <side> [dur]  Pulse output (default 0.5s)",d.dim)elseif az=="robot"then E("robot <command>",d.title)
E("  Control robot/drone movement and interaction.",d.fg)E("",d.fg)
E("  Movement: forward, back, up, down, left, right",d.dim)
E("  Actions:  swing, use, place, suck, drop, detect",d.dim)E("  Info:     name, energy, slot <n>",d.dim)elseif
az=="audio"or az=="sound"or az=="beep"then
E("audio [subcommand]",d.title)
E("  Control audio feedback (beeps and notifications).",d.fg)E("",d.fg)E(N,d.dim)
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
E("    2 descending        Shutdown / logout",d.dim)E("    3 ascending         Boot complete",d.dim)elseif az and
az~=""then local aB=require(P)local aA=aB.entry and aB.entry(az)
if aA then
local aD={[0]="guest",[1]="user",[2]="admin",[3]="root"}E(az,d.title)
E("  ".. (aA.help or"(no description)"),d.fg)E("",d.fg)
E(string.format("  Minimum tier: %s    Group: %s",aD[aA.tier or 0]or
tostring(aA.tier),aA.category or"?"),d.dim)
local aC="  Tip: run '"..az.."' with no args for usage"
if e.exists("/usr/man/"..az..".man")then aC=aC.."; 'man "..
az.."' for the manual."else aC=aC.."."end;E(aC,d.dim)else
E("No such command: '"..az.."'.  Type 'help' for the full list.",d.warning)end else local aB=require(P)
local function aA(aG)return aB.needMet and aB.needMet(aG)end
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
E("  F1  Help      "..at(a)..
"  F3  View file",d.fg)
E("  F4  Close tab F5  Copy file      F6  Move file",d.fg)
E("  "..au(a).." F9  Menu bar",d.fg)E("  F7  Mkdir     F8  Delete",d.fg)
E("  Text: Shift+arrows select.  "..ad(a),d.fg)
E("  F10 Quit      "..U(a).."  Cancel/Close   ^F  Find",d.fg)
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
E("  edit <file>   Open in editor tab  (^S save, "..U(a).." close)",d.fg)end
if a.userTier>=3 then
E("  lua           Interactive Lua REPL  (exit to quit)",d.fg)
E("  flash <file>  Flash EEPROM with Lua file  (!CAUTION)",d.fg)end
E("  programs      List executables in /bin and /usr/bin",d.fg)E("  history       Show command history",d.fg)
E("  date [fmt]    Show wall clock  (time = alias)",d.fg)
E("  tree [path] [depth]  Visual recursive directory listing",d.fg)
E("  theme [list|set|color|...]  Customize colors  (colors = alias)",d.fg)
E("  tutorial      Replay the welcome walkthrough",d.fg)if a.userTier>=1 and aA("swap")then
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
E("  cron [list|add|rm]        Scheduled tasks",d.fg)end;local aC,aD=aA("component:redstone"),aA("component:robot")
local aE,aF=aA("inventory"),aA("module:tape")
if aC or aD or aE or aF or a.userTier>=2 then E("",d.fg)
E(" Peripherals",d.highlight)if aC then
E("  redstone [set|pulse] Control redstone I/O  (rs = alias)",d.fg)end;if aD then
E("  robot <cmd>          Robot/drone movement & interaction",d.fg)end;if aE then
E("  inventory [side]     Inspect inventories  (inv = alias)",d.fg)end;if aF then
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
b.man=function(ay,E)local aA="/usr/man"local az=ay and ay[1]
if not az then
E("Manual pages — usage: man <topic>",d.title)local aD=
(e.isDirectory and e.isDirectory(aA)and e.list(aA))or{}
if
type(aD)=="table"and#aD>0 then table.sort(aD)
for aF,aE in ipairs(aD)do
local aG=(aE:gsub("/$","")):gsub("%.man$","")if aG~=""then E("  "..aG,d.fg)end end else
E("  (no manual pages installed under "..aA..")",d.dim)end
E("Depth: help (quick) < man (detailed) < MANUAL.md (the full book)",d.dim)return end;az=tostring(az):gsub("[^%w_%-]","")if az==""then
E("man: invalid topic",d.error)return end;local aB=e.join(aA,az..".man")if not
e.exists(aB)then aB=e.join(aA,az)end
if not e.exists(aB)then E(
"No manual page for '"..az.."'.",d.error)
E(
"Try 'help "..az.."', or open MANUAL.md for the full book.",d.dim)return end;local aC=e.readFile(aB)if not aC then
E("man: cannot read page",d.error)return end
if s then local aD={}
for aE in
(aC.."\n"):gmatch("([^\n]*)\n")do local aF=d.fg
if aE:match("^[A-Z][A-Z0-9 /%-]+$")then aF=d.title elseif aE:match("^%s")then aF=d.dim end;aD[#aD+1]={aE,aF}end;s(aD,"man "..az)else for aD in(aC.."\n"):gmatch("([^\n]*)\n")do
E(aD,d.fg)end end end
b.about=function(ay,E)local az=_G._TOS or{}
local aC,aA,aD="Strata Systems LLC",nil,"Terminal Operating System"local aE,aB=pcall(require,"kernel.logo")if aE and aB then
aC=aB.VENDOR or aC;aA=aB.MOTTO;aD=aB.TAGLINE or aD end;E(
"TOS - "..aD,d.title)
E("Version "..
(az.version or"?").."  [".. (az.codename or
"?").."]",d.highlight)
E("Build "..tostring(az.build or"?").." ("..
tostring(az.variant or"?")..")",d.dim)
E("GPU T"..B.." | "..
math.floor(Q.totalMemory()/1024).."K RAM",d.dim)E(aC.."   -   GNU GPL v3.0",d.dim)if aA and aA~=""then E(
'"'..aA..'"',d.dim)end;E("",d.fg)
E("A secure, multi-seat terminal OS for OpenComputers:",d.fg)
E("  - Sandboxed processes, role-based users, encrypted homes",d.fg)
E("  - Tabbed file browser + editor, themeable panels UI",d.fg)
E("  - Zero-trust networking: chat, mesh mail, clustering",d.fg)
E("  - Package manager + Optional Utilities add-on disk",d.fg)
E("  - Boot Settings (DEL at POST), swap, backups, OpenOS compat",d.fg)E("",d.fg)
E("'help' lists commands · 'tutorial' walks you through it.",d.dim)end;b.ver=b.about
b.echo=function(E,ay)ay(table.concat(E," "),d.fg)end
b.notify=function(ay,E)local aG,az=pcall(require,"kernel.notify")if not aG or not az then
E("notify unavailable",d.error)return end;local aB,aC,aA="info",nil,{}local aD
for aI=1,# (ay or{})
do local aJ=tostring(ay[aI])
if aI==aD then elseif aJ:sub(1,2)=="--"then
local aL,aK=aJ:match("^%-%-([%w%-]+)=?(.*)$")
if aL=="style"or aL=="title"then if aK==""and ay[aI+1]and
tostring(ay[aI+1]):sub(1,2)~="--"then
aK=tostring(ay[aI+1])aD=aI+1 end
if aL=="style"then aB=aK else aC=aK end end else aA[#aA+1]=aJ end end;local aE=table.concat(aA," ")
if aE==""then
E("Usage: notify <message> [--style info|warn|danger|error] [--title T]",d.title)
E("Puts a modal dialog box in front of every seat — the intrusive",d.dim)
E("counterpart to 'echo', which only writes above the command line.",d.dim)E("",d.dim)
E(string.format("Pending now: %d   (limits: %ds between boxes, %ds per source)",az.depth(),az.MIN_GAP,az.MIN_SOURCE_GAP),d.dim)return end
local aF,aH=az.post({message=aE,style=aB,title=aC,from="notify/"..tostring(a.who or"?")})
if aF then
E("Raised on every seat (dialog #"..aF..").",d.highlight)else
E("Not raised: "..tostring(aH),d.warning)
E("The message is in the log either way ('log' to see it).",d.dim)end end
b.tutorial=function(ay,E)local aA,az=L.requireRoomy(a,"shell.tutorial","core")
if
not aA then E(L.loadFailure("tutorial",az),d.error)return end
if ay[1]=="--reset"then local aC=
(g and i and g.getSession)and g.getSession(i)or nil;local aB=az.markerFor and
az.markerFor(aC)
if aB and e.exists(aB)then
e.remove(aB)
E("Tutorial reset — it will run again at your next login.",d.success or d.fg)elseif aB then
E("Tutorial was not marked done for this account.",d.dim)else
E("This account has no home to remember the tutorial in.",d.dim)end end;az.run({D=n,F=e,U=g,st=i,W=q,H=v})c.drawAll()end
b.cls=function(E,ay)n.fill(1,1,q,v," ",d.fg,d.bg)c.drawAll()end;b.clear=b.cls
b.cd=function(E,ay)if not E[1]then ay(a.cwd,d.fg)return end
local az=E[1]
if az==".."then a.cwd=a.cwd:match(am)or"/"
if a.cwd==""then a.cwd="/"end else local aA=f(az):gsub("//+","/")if
aA~="/"and aA:sub(-1)=="/"then aA=aA:sub(1,-2)end
if e.isDirectory(aA)then a.cwd=aA else ay(
"Not a directory: "..az,d.error)return end end;a.browser.path=a.cwd;a.browser.sel=1;a.browser.scroll=0
c.loadFiles(a.browser)end
b.ls=function(ay,E)local aE,aF,aB=false,false,nil
for aK,aJ in ipairs(ay)do
if not aB and aJ:sub(1,1)=="-"and
#aJ>1 then
for aL in aJ:sub(2):gmatch(".")do if aL=="l"then aE=true elseif aL=="a"then aF=true else
E("Usage: ls [-l|-a] [dir]",d.dim)return end end elseif not aB then aB=aJ end end;local az=f(aB or a.cwd)if not l(az,E)then return end;if e.exists and
not e.exists(az)then
E("no such file: ".. (aB or az),d.error)return end
local aH,aC=pcall(e.list,az)
if not aH or not aC then E("Cannot list: "..az,d.error)return end;local aA,aD={},0;local function aG(aJ)
if aF or aJ:sub(1,1)~="."then aA[#aA+1]=aJ else aD=aD+1 end end
if type(aC)=="table"then for aK,aJ in ipairs(aC)do
aG(aJ)end elseif type(aC)==ao then for aJ in aC do aG(aJ)end end
table.sort(aA,function(aJ,aK)local aL,aM=aJ:sub(-1)=="/",aK:sub(-1)=="/"if aL~=aM then
return aL end;return aJ<aK end)
local function aI(aJ)if not e.lastModified then return"-"end
local aL,aK=pcall(e.lastModified,e.join(az,aJ))
if not aL or type(aK)~="number"or aK<=0 then return"-"end
local aM,aN=pcall(os.date,"%Y-%m-%d %H:%M",math.floor(aK/1000))return aM and aN or"-"end
if aE then
E(string.format(" %-24s %8s  %s","Name","Size","Modified"),d.title)E(string.rep("-",52),d.border)else
E(string.format(af,"Name","Size"),d.title)E(string.rep("-",34),d.border)end
for aK,aJ in ipairs(aA)do local aM,aL
if aJ:sub(-1)=="/"then
aM=string.format(af,"["..aJ:sub(1,-2).."]","<DIR>")aL=d.dir or d.highlight else local aN=e.size(e.join(az,aJ))
aL=d.fg
if aJ:match("%.lua$")then
aL=d.file_lua or d.file_exec or d.highlight elseif aJ:match("%.cfg$")or aJ:match("%.conf$")then
aL=d.file_cfg or d.warning elseif aJ:match("%.log$")then aL=d.file_log or d.dim end;aM=string.format(af,aJ:sub(1,24),m(aN))end;if aE then aM=aM.."  "..aI(aJ)end;E(aM,aL)end
if aD>0 then
E(#aA.." items ("..aD.." hidden: ls -a shows them)",d.dim)else E(#aA.." items",d.dim)end end;b.dir=b.ls
local function C(ay,E)local az=f(ay)if not l(az,E)then return true end;local aA,aB,aC=L.readLinesCapped(e,az,function(aD)
E(aD,d.fg)end)if not aA then E(
O..ay,d.error)elseif aC then
E(string.format(L.VIEW_STOPPED,aB),d.warning)return false end;return true end
b.cat=function(E,ay)
if not E[1]then ay("Usage: cat <file...>",d.dim)return end;for aA,az in ipairs(E)do if not C(az,ay)then break end end end;b.type=b.cat
b.more=function(E,ay)
if not E[1]then ay("Usage: more <file>",d.dim)return end;local aA=f(E[1])if not l(aA,ay)then return end
local az={{" "..aA,d.title}}
local aB,aC,aD=L.readLinesCapped(e,aA,function(aE)az[#az+1]={aE,d.fg}end)if not aB then ay(O..E[1],d.error)return end;if aD then
az[#az+1]={string.format(L.VIEW_STOPPED,aC),d.warning}end
s(az,E[1]:match(Y)or E[1])end
local function D(E,az,ay)local aA=f(E)local aB=aA:match(am)or"/"
if not o(aB,ay)then return false end
if e.isDirectory and e.isDirectory(aA)then if not az then
ay("Already exists: "..E,d.warning)end;return false end;local aC,aD=e.makeDirectory(aA)if aC then
ay("Created: "..E,d.highlight)return true end
ay(tostring(aD or"Could not create "..E),d.error)return false end
b.mkdir=function(ay,E)local aA="Usage: mkdir [-p] <dir...>"
local aB,aC=L.getopt(ay,{["-p"]="parents",["--parents"]="parents"},E,d,aA)if not aB then return end;if not aC[1]then E(aA,d.dim)return end;local az=false;for aE,aD in
ipairs(aC)do az=D(aD,aB.parents,E)or az end;if az then
k()end end
local function F(E,ay)local az=f(E)if e.isDirectory(az)then
ay("Is a directory: "..E,d.dim)return false end
if not o(az,ay)then return false end
if not e.exists(az)then local aA,aB=e.writeFile(az,"")if not aA then
ay(tostring(aB or
"Could not create "..E),d.error)return false end end;ay("Touched: "..E,d.highlight)return true end
b.touch=function(E,ay)
if not E[1]then ay("Usage: touch <file...>",d.dim)return end;local az=false;for aB,aA in ipairs(E)do az=F(aA,ay)or az end
if az then k()end end
local function x(E,ay)
local az,aA=L.getopt(E,{["-k"]="keep",["--keep"]="keep"},ay,d)if not az then return nil end;return az.keep,aA end
b.compress=function(ay,E)local aI,az=x(ay,E)if not az then return end;if not az[1]then
E("Usage: compress <file> [out]   (-k keeps original)",d.dim)return end
local aD=h.getCompress and h.getCompress()if not aD or not aD.available()then
E("Compression needs a data card (none detected).",d.error)return end;local aA=f(az[1])if not
l(aA,E)then return end;if not e.exists(aA)or
(e.isDirectory and e.isDirectory(aA))then
E("Not a file: "..az[1],d.error)return end
local aF=e.readFile(aA)if not aF then E("Read failed",d.error)return end;local aC=az[2]and
f(az[2])or(aA..".tcz")
if not o(aC,E)then return end;local aG,aH,aB,aE=aD.pack(aF)
if not aG then E("Compress failed",d.error)return end
if not e.writeFile(aC,aG)then E("Write failed",d.error)return end;if not aI and aC~=aA then pcall(e.remove,aA)end;k()
local aJ=
(aB>0)and math.floor((aB-aE)*100/aB)or 0
local aK=aE<aB and(aJ.."% smaller")or"no smaller"
E(string.format("%s -> %s  (%s: %s -> %s)",az[1],(aC:gsub("^.*/","")),aK,m(aB),m(aE)),
aH=="deflate"and d.highlight or d.warning)if aH=="stored"then
E("(stored uncompressed — data didn't shrink)",d.dim)end end
b.decompress=function(ay,E)local aF,az=x(ay,E)if not az then return end;if not az[1]then
E("Usage: decompress <file.tcz> [out]   (-k keeps original)",d.dim)return end;local aA=f(az[1])if
not l(aA,E)then return end
if not e.exists(aA)then E(X..az[1],d.error)return end;local aC=e.readFile(aA)
if not aC then E("Read failed",d.error)return end;local aD=h.getCompress and h.getCompress()if not aD then
E("Compression module unavailable",d.error)return end
if not aD.isPacked(aC)then E("Not a .tcz container: "..
az[1],d.error)return end;local aE,aG=aD.unpack(aC)if not aE then
E("Decompress failed: "..tostring(aG),d.error)return end;local aB
if az[2]then aB=f(az[2])elseif
aA:sub(-4)==".tcz"then aB=aA:sub(1,-5)else aB=aA..".out"end;if not o(aB,E)then return end;if not e.writeFile(aB,aE)then
E("Write failed",d.error)return end;if not aF and aB~=aA then
pcall(e.remove,aA)end;k()
E(string.format("%s -> %s  (%s restored)",az[1],(aB:gsub("^.*/","")),m(
#aE)),d.highlight)end
local function G(ay,az,aA,E)local aB=f(ay)
if aB=="/"then E("Cannot remove root",d.error)return end;local aC=_G._TOS and _G._TOS.securefs
if aC and
type(aC.removeRefusal)==ao then
local aG=aC.removeRefusal(aB,L.sessionOf(a))if aG then E(tostring(aG),d.error)return end end
local aE={"^/$","^/init%.lua$","^/bios%.lua$","^/tos$","^/tos/","^/etc$","^/etc/","^/boot$","^/boot/"}
for aH,aG in ipairs(aE)do
if aB:match(aG)and not az then
E("Refusing to remove a system path without -r: "..aB..
"  [E-303 ERR_RM_SYSTEM_PATH]",d.error)
E("Protection is off, so this would really delete it. Add -r to confirm.",d.dim)return end end;if not o(aB,E)then return end;if e.exists and not e.exists(aB)then
E(X..ay,d.error)return end
if
e.isDirectory and e.isDirectory(aB)then if not az then
E("Cannot remove directory without -r: "..aB.."  [E-302 ERR_NEEDS_RECURSIVE]",d.error)return end
local aG=e.list and e.list(aB)if aG and#aG>0 then
E("Removing "..#aG.." item(s) under "..aB.."...",d.dim)end end;local aD=false
local aF=aB:match("^/tos")or aB:match("^/etc")or
aB:match("^/var")or aB:match("^/usr")
if not aA and not aF then local aH,aG=pcall(require,"kernel.trash")
if
aH and aG and aG.put then local aI=L.sessionOf(a)local aJ,aK=aG.put(aB,aI)
if aJ then aD=true
E("Trashed: "..ay..

" (use 'trash restore ".. (ay:match(Y)or ay).."' to undo)",d.highlight)else local aL=tostring(aK or"unknown reason")
if
aL:find("no trash",1,true)then
E("No trash for this session — deleting "..ay.." outright.",d.warning)else
E("Not trashed: "..aL.."  [E-304 ERR_TRASH_REFUSED]",d.error)
E("It is still there. Delete it for good with:  rm "..
(az and"-r "or"").."--hard "..ay,d.dim)return end end end end
if not aD then local aG,aH=e.remove(aB)if aG then k()
E("Removed: "..ay,d.highlight)else
E(tostring(aH or"Could not remove "..ay),d.error)end else k()end end
b.rm=function(ay,E)local aA="Usage: rm [-r] [--hard] <path...>"
local az,aB=L.getopt(ay,{["-r"]=aq,["-rf"]=aq,["-R"]=aq,["--hard"]="hard",["-H"]="hard"},E,d,aA)if not az then return end
local aC,aD=az.recursive or false,az.hard or false;if#aB==0 then E(aA,d.dim)return end
for aF,aE in ipairs(aB)do G(aE,aC,aD,E)end end
b.trash=function(ay,E)local aC,az=pcall(require,"kernel.trash")if not aC or not az then
E("Trash unavailable",d.error)return end;local aA=ay[1]or"list"
local aB=L.sessionOf(a)
if aA=="list"or aA=="ls"then local aE=az.list(aB)if#aE==0 then
E("Trash is empty.",d.dim)return end
E(string.format(" %-20s %-8s %s","name","size","origin"),d.title)for aG,aF in ipairs(aE)do
E(string.format(" %-20s %-8d %s",aF.name:sub(1,20),aF.size,aF.origin),d.fg)end;local aD=az.usage(aB)if
aD then
E(string.format(" %d/%d items, %d/%d bytes used",aD.count,aD.max_count,aD.bytes,aD.max_bytes),d.dim)end elseif aA=="empty"then
local aE,aD=az.empty(aB)if aE then
E("Emptied "..tostring(aD).." items.",d.highlight)else
E(tostring(aD or"empty failed"),d.error)end elseif aA=="restore"then if not ay[2]then
E("Usage: trash restore <name> [dest] [--force]",d.dim)return end;local aD,aE=false,nil;for aH=3,#ay do
if
ay[aH]=="--force"or ay[aH]=="-f"then aD=true else aE=ay[aH]end end
local aG,aF=az.restore(ay[2],{session=aB,dest=aE,force=aD})if aG then k()
E("Restored to "..tostring(aF),d.highlight)else
E(tostring(aF or"restore failed"),d.error)end else
E("Usage: trash [list|empty|restore <name> [dest] [--force]]",d.dim)end end
b.vault=function(ay,E)local aG,aA=L.requireRoomy(a,"kernel.vault","core")
if
not aG or not aA then E(L.loadFailure("vault",aA),d.error)return end;local az=ay[1]local aE=L.sessionOf(a)
local aB=_G._TOS and _G._TOS.securefs
local function aC(aH)if aB and aB.readFile then return aB.readFile(aH,aE)end;return
nil,"securefs unavailable (refusing unchecked read)"end
local function aF(aH,aI)
if aB and aB.writeFile then return aB.writeFile(aH,aI,aE)end;return false,"securefs unavailable (refusing unchecked write)"end
local function aD(aH,aI)
if aH~=nil and aH~="-"then
E("Note: a typed passphrase stays in this seat's command history;",d.dim)
E("leave it off, or use -, to be asked for it instead.",d.dim)return aH end;if not j then
E("Cannot ask for a passphrase here: give it as the last argument.",d.error)return nil end
local aJ=j("Passphrase: ",256,true)if not aJ or aJ==""then E(ag,d.dim)return nil end
if aI then
local aK=j("Again, to confirm: ",256,true)if aK~=aJ then
E(aK and"The two did not match; nothing was changed."or ag,d.error)return nil end end;return aJ end
if az==M or az==an then local aK,aM=ay[2],ay[3]if not aK or not aM then
E("Usage: vault "..az..
" <src> <dst> [passphrase | -]",d.dim)return end;local aH=aC(f(aK))if not aH then E(O..
aK,d.error)return end;if az==an and
not aA.isEncrypted(aH)then
E("Source is not a TOS vault blob.",d.warning)return end
local aL=aD(ay[4],az==M)if not aL then return end;local aI,aJ;if az==M then aI,aJ=aA.encrypt(aH,aL)else
aI,aJ=aA.decrypt(aH,aL)end;if not aI then
E("Failed: "..tostring(aJ),d.error)return end;local aN,aO=aF(f(aM),aI)if not aN then
E(al..tostring(aO),d.error)return end
E(string.format("%s %d -> %d bytes (algo=%s)",az==M and"Encrypted"or
"Decrypted",#aH,#aI,tostring(aJ.algo)),d.highlight)elseif az=="encrypt-in-place"or az=="decrypt-in-place"then
local aK=ay[2]if not aK then
E("Usage: vault "..az.." <file> [passphrase | -]",d.dim)return end;local aN=f(aK)local aH=aC(aN)if not aH then
E(O..aK,d.error)return end;local aJ=az:sub(1,7)==M
if
aJ and aA.isEncrypted(aH)then
E("Already encrypted — refusing to double-encrypt.",d.warning)return elseif not aJ and not aA.isEncrypted(aH)then
E("Not a vault blob — nothing to decrypt.",d.warning)return end;local aL=aD(ay[3],aJ)if not aL then return end;local aI,aM;if aJ then
aI,aM=aA.encrypt(aH,aL)else aI,aM=aA.decrypt(aH,aL)end
if not aI then E("Failed: "..
tostring(aM),d.error)return end;local aO,aP=aF(aN,aI)if not aO then E(al..tostring(aP),d.error)
return end
E(string.format("%s in place: %d -> %d bytes",
az:sub(1,7)==M and"Encrypted"or"Decrypted",#aH,#aI),d.highlight)elseif az=="info"then local aH=ay[2]if not aH then
E("Usage: vault info <file>",d.dim)return end;local aI=aC(f(aH))if not aI then
E(O..aH,d.error)return end;if not aA.isEncrypted(aI)then
E("Not a vault blob (no TVAULT1 magic).",d.warning)return end
E(string.format(" file:     %s",aH),d.title)
E(string.format(" size:     %d bytes",#aI),d.fg)local aJ=#aA.MAGIC+1
local aK=aI:sub(aJ,aJ+3):gsub("\0+$","")
E(string.format(" algo:     %s",aK),d.fg)
E(string.format(" ctLen:    encrypted body inside this blob"),d.dim)
E(" (decrypt with the right passphrase to access contents)",d.dim)elseif az=="tape"then local aH=ay[2]if aH~=M and aH~=an then
E("Usage: vault tape encrypt|decrypt [passphrase | -]",d.dim)return end;local aI=b.tape;if not aI then
E("Tape module not installed (run `pkg install tape`).",d.warning)return end
local aJ=aD(ay[3],aH==M)if not aJ then return end;aI({aH,aJ},E)else
E("Usage: vault [encrypt|decrypt|encrypt-in-place|decrypt-in-place|info|tape] ...",d.dim)
E("  vault encrypt <src> <dst> [passphrase]",d.dim)
E("  vault decrypt <src> <dst> [passphrase]",d.dim)
E("  vault encrypt-in-place <file> [passphrase]",d.dim)
E("  vault decrypt-in-place <file> [passphrase]",d.dim)E("  vault info <file>",d.dim)
E("  vault tape encrypt|decrypt [passphrase]",d.dim)
E("  Leave the passphrase off (or use -) to be asked for it, unechoed:",d.dim)
E("  a typed one stays in this seat's command history.",d.dim)end end
b.keychain=function(ay,E)local az=_G._TOS and _G._TOS.keychain;if not az then
E("keychain module unavailable",d.error)return end;local aA=L.sessionOf(a)
local aB=ay[1]or"status"
if aB=="status"then
E(az.isUnlocked(aA)and"unlocked"or"locked",d.fg)elseif aB=="unlock"then if not j then
E("interactive prompt unavailable",d.error)return end
local aC=j("Master password: ",64,"*")or""
if#aC==0 then E("(empty — cancelled)",d.dim)return end;local aD,aE=az.unlock(aC,aA)if aD then
E("Keychain unlocked.",d.highlight)else
E("Unlock failed: "..tostring(aE),d.error)end elseif aB=="lock"then az.lock(aA)
E("Keychain locked.",d.highlight)elseif aB=="list"then
if not az.isUnlocked(aA)then E(ah,d.warning)return end;local aC=az.list(aA)
if#aC==0 then E("(empty)",d.dim)return end;for aE,aD in ipairs(aC)do E("  "..aD,d.fg)end elseif aB=="set"then if not ay[2]then
E("Usage: keychain set <name>",d.dim)return end;if not az.isUnlocked(aA)then
E("Keychain is locked. Run 'keychain unlock' first.",d.warning)return end;if not j then
E("interactive prompt unavailable",d.error)return end;local aC=
j("Passphrase for '"..ay[2].."': ",256,"*")or""if#aC==0 then
E("(empty — cancelled)",d.dim)return end;local aD,aE=az.set(ay[2],aC,aA)if aD then
E("Slot '"..
ay[2].."' saved.",d.highlight)else
E("Save failed: "..tostring(aE),d.error)end elseif aB=="get"then if not ay[2]then
E("Usage: keychain get <name>",d.dim)return end;if not az.isUnlocked(aA)then
E(ah,d.warning)return end;local aC,aD=az.get(ay[2],aA)if aC then
E(aC,d.fg)else
E(tostring(aD or"no such slot"),d.error)end elseif aB=="remove"or aB=="rm"then if not ay[2]then
E("Usage: keychain remove <name>",d.dim)return end;if not az.isUnlocked(aA)then
E(ah,d.warning)return end;local aC,aD=az.remove(ay[2],aA)
if aC then E("Removed '"..
ay[2].."'.",d.highlight)else E(
"Remove failed: "..tostring(aD),d.error)end else
E("Usage: keychain [status|unlock|lock|list|set|get|remove] ...",d.dim)end end
b.profile=function(ay,E)local aA=_G._TOS and _G._TOS.profile;if not aA then
E(ap,d.error)return end;local az=L.sessionOf(a)local aB=ay[1]or"show"
if aB==
"show"then local aC,aE=aA.load(az)
E(string.format(" name:    %s",aC.name),d.title)
E(string.format(" theme:   %s",aC.theme or"(unset — uses `theme set` choice or default)"),d.fg)
E(string.format(" cwd:     %s",aC.cwd or"(unset)"),d.fg)
E(string.format(" prompt:  %s",aC.prompt or"(default)"),d.fg)local aD=0;for aF in pairs(aC.env)do aD=aD+1 end
E(string.format(" env:     %d entries",aD),d.fg)
E(string.format(" startup: %d commands",#aC.startup),d.fg)if not aE then
E(" (no profile file — showing defaults)",d.dim)end elseif aB=="set"then
if not ay[2]or not ay[3]then
E("Usage: profile set <field> <value>",d.dim)E("  fields: name, theme, cwd, prompt",d.dim)return end;local aC,aD=ay[2],ay[3]local aE=aA.load(az)
if aC=="name"or aC=="theme"or
aC=="cwd"or aC=="prompt"then
if aC=="theme"then local aH=_G._TOS and
_G._TOS.theme
if
aH and aH.preset and not aH.preset(aD)then E("Unknown theme preset: "..aD,d.error)if aH.list then
E(
"Available: "..table.concat(aH.list(),", "),d.dim)end;return end end;aE[aC]=aD;local aF,aG=aA.save(aE,az)
if aF then
E("Profile updated. Re-login to apply.",d.highlight)else E(tostring(aG or as),d.error)end else E("Unknown field: "..aC,d.error)end elseif aB=="env"then if not ay[2]then
E("Usage: profile env <KEY> [VALUE]",d.dim)return end;local aC=aA.load(az)if ay[3]then
aC.env[ay[2]]=ay[3]E("env["..ay[2].."] set",d.highlight)else aC.env[ay[2]]=
nil
E("env["..ay[2].."] cleared",d.highlight)end
aA.save(aC,az)elseif aB=="startup"then local aD=ay[2]or"list"local aC=aA.load(az)
if aD=="add"then
local aE=table.concat(ay," ",3)
if#aE==0 then E("Usage: profile startup add <cmd>",d.dim)return end;aC.startup[#aC.startup+1]=aE;aA.save(aC,az)
E("Added.",d.highlight)elseif aD=="clear"then aC.startup={}aA.save(aC,az)
E("Startup commands cleared.",d.highlight)else for aE,aF in ipairs(aC.startup)do
E(string.format(" %d. %s",aE,aF),d.fg)end;if#aC.startup==0 then
E("(no startup commands)",d.dim)end end elseif aB=="reset"then local aC=_G._TOS and _G._TOS.securefs;if
aC and az and az.home and az.home~="/"then
aC.remove(az.home.."/.profile.cfg",az)end
E("Profile reset to defaults.",d.highlight)else
E("Usage: profile [show|set|env|startup|reset]",d.dim)end end
b.cp=function(E,ay)
local aB,aC=L.getopt(E,{["-r"]="r",["-R"]="r"},ay,d,"Usage: cp <src> <dst>")if not aB then return end;E=aC;if not E[2]then
ay("Usage: cp <src> <dst>",d.dim)return end;local aA,az=f(E[1]),f(E[2])
if
e.isDirectory(az)then az=e.join(az,aA:match(Y)or aA)end;local aD,aE=e.copy(aA,az)
if aD then k()
ay("Copied: "..E[2],d.highlight)else ay(aE or"Failed",d.error)end end
b.mv=function(ay,E)
if not ay[2]then E("Usage: mv <src> <dst>",d.dim)return end;local az,aA=f(ay[1]),f(ay[2])if not e.exists(az)then
E(X..ay[1],d.error)return end;if e.isDirectory(aA)then
aA=e.join(aA,az:match(Y)or az)end;local aB=aA:match(am)if aB and aB~=""and not
e.isDirectory(aB)then
E("No such directory: "..aB,d.error)return end
if not o(az,E)then return end;if not o(aA,E)then return end
if e.rename(az,aA)then k()
E("Moved: "..ay[2],d.highlight)else local aC,aD=e.copy(az,aA)if aC and e.remove(az)then k()
E("Moved: "..ay[2],d.highlight)else
E("Move failed: "..tostring(aD or"cross-fs copy failed"),d.error)end end end
b.find=function(E,ay)local aD="/"local az=nil;local aA={}local aB=1;while aB<=#E do
if E[aB]=="-name"and E[aB+1]then
az=E[aB+1]aB=aB+2 else aA[#aA+1]=E[aB]aB=aB+1 end end
if aA[2]then aD=f(aA[1])az=az or
aA[2]elseif aA[1]then if az or e.isDirectory(f(aA[1]))then aD=f(aA[1])else
az=aA[1]end end
if az then local aJ,aK=pcall(string.match,"",az)if not aJ then
ay("Invalid pattern: "..tostring(aK),d.error)return end end;ay("Searching "..aD.." ...",d.dim)local aH=16
local aE=1000;local aC={}
local function aI(aJ)if not g or not g.canAccessAs then return false end
local aK=L.sessionOf(a)local aL=g.canAccessAs(aK,aJ,"r")return aL end
local function aG(aJ,aK)if aK>aH then return end;if#aC>=aE then return end;if not aI(aJ)then return end
local aN,aL=pcall(e.list,aJ)if not aN or not aL then return end;local aM={}
if type(aL)=="table"then aM=aL elseif
type(aL)==ao then for aO in aL do aM[#aM+1]=aO end end
for aP,aO in ipairs(aM)do if#aC>=aE then break end;S()
local aQ=e.join(aJ,(aO:gsub("/$","")))local aR=aO:sub(-1)=="/"local aS=false;if az then
local aT,aU=pcall(string.match,aQ,az)local aV,aW=pcall(string.match,aO,az)
aS=(aT and aU)or(aV and aW)else aS=true end;if aS then
aC[
#aC+1]={aQ.. (aR and"/"or""),
aR and(d.dir or d.highlight)or d.fg}end;if
aR and not aQ:match("^/tos")then aG(aQ,aK+1)end end end;aG(aD,0)if#aC==0 then ay("No matches found",d.dim)else for aK,aJ in ipairs(aC)do
ay(aJ[1],aJ[2])end end;local aF=#aC..
" result(s)"if#aC>=aE then
aF=aF.." (truncated at "..aE..")"end;ay(aF,d.dim)end
b.grep=function(E,ay)
local aA,aC=L.getopt(E,{["-i"]="fold"},ay,d,"Usage: grep [-i] <pattern> <file...>   (-- before a pattern that starts with -)")if not aA then return end;local aB=aA.fold;E=aC;if not E[2]then
ay("Usage: grep [-i] <pattern> <file...>",d.dim)return end
local aD=aB and E[1]:lower()or E[1]local aE=E[3]~=nil;local az=0
for aF=2,#E do local aG=f(E[aF])
if l(aG,ay)then local aH=0
local aI=L.eachLine(e,aG,function(aJ)aH=aH+1
if(aB and
aJ:lower()or aJ):find(aD,1,true)then if aE then ay(
E[aF]..":"..aH..": "..aJ,d.fg)else
ay(string.format("%4d: %s",aH,aJ),d.fg)end;az=az+1 end end)if not aI then ay(O..E[aF],d.error)end end end
ay(az>0 and(az.." match(es)")or"No matches",d.dim)end
b.wc=function(E,ay)
if not E[1]then ay("Usage: wc <file>",d.dim)return end;local aB=f(E[1])if not l(aB,ay)then return end;local az,aA=0,0
local aC,aD=L.eachLine(e,aB,function(aE)az=az+1;for aF in
aE:gmatch("%S+")do aA=aA+1 end end)if not aC then ay(O..E[1],d.error)return end
ay(string.format(" Lines: %d  Words: %d  Bytes: %d  -- %s",az,aA,aD,E[1]),d.fg)end;b.pwd=function(ay,E)E(a.cwd or"/",d.fg)end
local function y(E,ay)
local aA,az=L.getopt(E,{["-n"]={"n"},number="n"},ay,d)if not aA then return false end;local aC,aB=az[1],tonumber(aA.n)or 10
if
az[2]and tonumber(az[2])then aB=tonumber(az[2])end;return aC,aB end
local function z(E,aA,ay,az)if e.exists and not e.exists(aA)then az(X..E,d.error)else
az("Cannot read "..
E.. (ay and(": "..
tostring(ay))or""),d.error)end end
b.head=function(ay,E)local az,aA=y(ay,E)if az==false then return end;if not az then
E("Usage: head [-n N] <file>",d.dim)return end;local aB=f(az)if not l(aB,E)then return end
local aC=0;if not aA or aA<1 then return end
local aD,aE=L.eachLine(e,aB,function(aF)E(aF,d.fg)aC=aC+1;if aC>=aA then
return false end end)if not aD then z(az,aB,aE,E)end end
b.tail=function(ay,E)local aB,az=y(ay,E)if aB==false then return end;if not aB then
E("Usage: tail [-n N] <file>",d.dim)return end;local aC=f(aB)if not l(aC,E)then return end;if
not az or az<1 then return end;if az>1000 then az=1000 end;local aD,aA={},0
local aE,aF=L.eachLine(e,aC,function(aG)aA=
aA+1;aD[(aA-1)%az+1]=aG end)if not aE then z(aB,aC,aF,E)return end
for aG=math.max(1,aA-az+1),aA do E(aD[
(aG-1)%az+1],d.fg)end end
b.which=function(ay,E)
if not ay[1]then E("Usage: which <name>",d.dim)return end;local az=ay[1]:lower()local aA=false;local aC=L.aliases(a)
if aC[az]then
E(az..": alias for '"..
aC[az].."'",d.highlight)
E("  (expanded before dispatch; the expansion is resolved below)",d.dim)
az=tostring(L.tokenizeSimple(aC[az])[1]or az):lower()aA=true end;local aE=require(P)
local aB=aE.entry and aE.entry(az)or nil
if aB then local aJ=aB.tier or 0
E(az..
": built-in (".. (aB.category or"?")..", needs "..
L.tierName(aJ)..")",d.title)if aB.help then E("  "..aB.help,d.fg)end;if
aJ>L.liveTier(a)then
E("  You do not have the tier to run it — 'why "..az.."'.",d.warning)end;aA=true end;local aH,aD=pcall(require,Z)
local aF=aH and aD and aD.ownerOfCommand and
aD.ownerOfCommand(az)or nil
if aF then
E(az..": package command from '"..aF.."'",aB and d.dim or d.title)
if aB then E("  (shadowed by the built-in above)",d.dim)end;aA=true end;local aG,aI=L.resolveProgram(e,az)
if aG then
E(az..": "..aG..
(aI=="path"and"  (via PATH)"or""),aA and d.dim or
d.title)
if aA then E("  (shadowed by the entry above)",d.dim)end;aA=true end
if not aA then E(az..": not found",d.error)
E("  Not a built-in, an installed package's command, or a program on",d.dim)
E("  /bin, /usr/bin or /tos/shell. 'help' lists what this box has.",d.dim)end end
local function H(E)local ay=require(P)
if ay.entry and ay.entry(E)then return true end;if L.mayHavePackages()then local aA,az=pcall(require,Z)
if
aA and az and az.ownerOfCommand and az.ownerOfCommand(E)then return true end end;return
L.resolveProgram(e,E)~=nil end
b.open=function(ay,E)local az=require("shell.open")local aE=L.sessionOf(a)
local aC=aE and aE.home;local aA=ay[1]
local function aB()
E("Usage: open <file>                    in the program that suits it",d.dim)
E("       open with <file> [program]     every program that could, and why",d.dim)
E("       open set .<ext> <program> [--system]   choose (--system: every user)",d.dim)
E("       open unset .<ext> [--system]   forget the choice",d.dim)
E("       open list                      the choices and what packages declare",d.dim)
E("       open hints on|off              edit's suggestions",d.dim)end;if not aA then aB()return end;local function aF(aI)if aI then return az.SYSTEM_FILE end
return aC and(aC..
"/"..az.USER_FILE)or nil end
local function aG(aI)
local aJ,aK=pcall(e.exists,aI)return
az.parseDefaults(aJ and aK and e.readFile(aI)or nil)end
local function aD(aI,aJ)
local aK,aL=e.writeFile(aI,az.serializeDefaults(aJ))if not aK then
E("Not saved: "..tostring(aL or aI),d.error)end;return aK end
local function aH(aI,aJ)if not a.execOne then
E("open: the executor is unavailable",d.error)return end;local aK=a.execOne(aI.." "..az.quote(aJ),
nil,true)for aM,aL in ipairs(aK or{})do
E(aL[1],aL[2])end end
if aA=="set"or aA=="unset"then local aL=ay[#ay]==W
local aI=(ay[2]or""):gsub("^%.",""):lower()if
aI==""or not aI:match("^[%w]+$")or#aI>8 then aB()return end;if aL and not r(E)then return end
local aJ=aF(aL)if not aJ then
E("There is no home directory to keep your choice in.",d.error)return end;local aK=aG(aJ)
if aA=="set"then local aM=ay[3]and
ay[3]:lower()if not aM or aM==W then aB()return end;if
not H(aM)then
E("'"..
aM.."' is not a command this machine has ('which "..aM.."').",d.error)return end;aK.ext[aI]=aM;if
aD(aJ,aK)then
E("."..
aI.." files now open in "..aM..
(aL and" for every user."or" for you."),d.highlight)end else aK.ext[aI]=nil;if
aD(aJ,aK)then
E("."..aI..": back to the ranking.",d.highlight)end end elseif aA=="hints"then local aI=aF(false)if not aI or
(ay[2]~="on"and ay[2]~="off")then aB()return end;local aJ=aG(aI)aJ.hints=(
ay[2]=="on")if aD(aI,aJ)then
E("edit's suggestions are "..ay[2]..".",d.highlight)end elseif aA=="list"then
local aI=az.gather(e,aC,nil,"")
local function aJ(aL,aK)local aM={}for aN in pairs(aK.ext)do aM[#aM+1]=aN end
table.sort(aM)
E(aL.. (#aM==0 and"  (none)"or""),d.title)for aO,aN in ipairs(aM)do
E(string.format("  .%-8s %s",aN,aK.ext[aN]),d.fg)end end
aJ("Your choices (~/"..az.USER_FILE.."):",aI.user)
aJ("This machine's ("..az.SYSTEM_FILE.."):",aI.system)
E("What installed packages open:"..
(#aI.decls==0 and"  (none)"or""),d.title)
for aL,aK in ipairs(aI.decls)do local aM={}
for aO in pairs(aK.exts)do aM[#aM+1]="."..aO end;table.sort(aM)
local aN=aK.markers and
("when a line starts "..table.concat(aK.markers," "))or(aK.as=="native"and"its own format"or
"can open")
E(string.format("  %-8s %s  %s",aK.cmd,table.concat(aM," "),aN),d.fg)end;if aI.user.hints==false then
E("edit's suggestions are off ('open hints on').",d.dim)end else local aK=aA=="with"
local aL=aK and ay[2]or aA;if not aL then aB()return end;local aI=f(aL)local aN,aO=pcall(e.exists,aI)if not aN or
not aO then E("open: no such file: "..aI,d.error)
return end;if
e.isDirectory and e.isDirectory(aI)then
E("open: "..aI.." is a directory ('cd' into it).",d.error)return end
local aJ=az.rank(aI,az.gather(e,aC,aI))
if aK and not ay[3]then if#aJ==0 then
E("Nothing here opens "..aI..".",d.warning)return end
E("Programs that could open "..aI..", best first:",d.title)for aQ,aP in ipairs(aJ)do
E(string.format("  %-8s %3d  %s",aP.cmd,aP.score,aP.why),aQ==1 and
d.highlight or d.fg)end
E("'open with "..aL..

" <program>' uses another; 'open set .".. (az.ext(aI)or"ext").." <program>' makes it yours.",d.dim)return end
local aM=aK and ay[3]:lower()or(aJ[1]and aJ[1].cmd)if not aM then
E("Nothing here opens "..aI.." ('open with' lists what could).",d.warning)return end;if not aK then
E("Opening in "..aM..": "..aJ[1].why..
".",d.dim)end;aH(aM,aI)end end
b.alias=function(ay,E)local aB=_G._TOS and _G._TOS.profile;if not aB then E(ap,d.error)
return end;local aC=L.sessionOf(a)
if not ay[1]then local aI=aB.load(aC)
local aH={}for aJ in pairs(aI.aliases or{})do aH[#aH+1]=aJ end
table.sort(aH)if#aH==0 then E("(no aliases)",d.dim)
E("Define one:  alias ll ls -l",d.dim)return end;for aK,aJ in ipairs(aH)do
E(string.format(" %-12s %s",aJ,aI.aliases[aJ]),d.fg)end;return end;local az=ay[1]:lower()if not az:match("^[%w_%-]+$")then E("Bad alias name: "..
ay[1],d.error)
E("Letters, digits, underscore and hyphen only.",d.dim)return end
local aA=aB.load(aC)
if not ay[2]then
if aA.aliases and aA.aliases[az]then
E(string.format(" %-12s %s",az,aA.aliases[az]),d.fg)else E(az..": not aliased",d.dim)end;return end;local aD=table.concat(ay," ",2)
local aE=tostring(L.tokenizeSimple(aD)[1]or""):lower()if aE==az then E("An alias cannot expand to itself.",d.error)
E("To add default flags, alias to a different name.",d.dim)return end;aA.aliases=
aA.aliases or{}aA.aliases[az]=aD;local aF,aG=aB.save(aA,aC)
if
not aF then E(tostring(aG or as),d.error)return end;L.invalidateAliases(a)
E("alias "..az.." -> "..aD,d.highlight)end
b.unalias=function(ay,E)local aB=_G._TOS and _G._TOS.profile;if not aB then
E(ap,d.error)return end;if not ay[1]then
E("Usage: unalias <name>",d.dim)return end;local aC=L.sessionOf(a)
local az=ay[1]:lower()local aA=aB.load(aC)
if not aA.aliases or not aA.aliases[az]then E(
az..": not aliased",d.dim)return end;aA.aliases[az]=nil;local aD,aE=aB.save(aA,aC)if not aD then
E(tostring(aE or as),d.error)return end;L.invalidateAliases(a)E("Removed alias '"..
az.."'.",d.highlight)end
b.du=function(ay,E)local az=f(ay[1]or(a.cwd or"/"))
if not l(az,E)then return end;if not e.exists(az)then
E("No such file or directory: "..tostring(ay[1]),d.error)return end;local function aB(aC,aD)
return aC:sub(-1)=="/"and
(aC..aD)or(aC.."/"..aD)end
local function aA(aC)
if e.isDirectory(aC)then
local aD,aE=0,e.list(aC)
if type(aE)=="table"then for aG,aF in ipairs(aE)do S()aD=aD+
aA(aB(aC,(aF:gsub("/$",""))))end end;return aD end;return(e.size and e.size(aC))or 0 end
if e.isDirectory(az)then local aC=e.list(az)
if type(aC)=="table"then for aE,aD in ipairs(aC)do
local aF=aD:gsub("/$","")
E(string.format(" %8s  %s",m(aA(aB(az,aF))),aF),d.fg)end end end
E(string.format(" %8s  %s (total)",m(aA(az)),az),d.title)end
b.df=function(ay,E)local aB,az=pcall(require,"kernel.monitor")
E(string.format(" %-16s %8s %8s %8s  %s","Mount","Total","Used","Free","Use%"),d.title)
E(string.rep("-",math.min(q,56)),d.dim)local aA=e.mounts and e.mounts()or{}
if#aA==0 then
E("(mount info unavailable)",d.dim)else
for aD,aC in ipairs(aA)do local aE=aC.total or 0;local aF=aC.used or 0;local aH=aE-aF
local aG=aE>0 and math.floor(
aF*100/aE)or 0
local aI=(aB and az.memBar)and az.memBar(aF,aE,8)or""
local aJ=aG<80 and d.fg or(aG<95 and d.warning or d.error)
E(string.format(" %-16s %8s %8s %8s  [%s] %3d%%",(aC.mountPoint or"?"):sub(1,16),m(aE),m(aF),m(aH),aI,aG),aJ)end end
if _G._TOS_ROOT_READONLY then E("",d.dim)
E("WARNING: the root filesystem is READ-ONLY.",d.error)
E("Nothing TOS writes will survive a reboot — users, logs, packages,",d.dim)
E("settings. Install to a writable drive, or unprotect this one.",d.dim)end
E("A path's own size: 'du <path>'.  Removable media + pools: 'disk'.",d.dim)end
b.mem=function(ay,E)
if ay and ay[1]=="--boot"then
local aL=_G._TOS and _G._TOS.bootMem
if type(aL)~="table"or#aL==0 then
E("This boot was not profiled.",d.warning)
E("Add  memprofile = true  to /etc/boot.cfg and reboot.",d.dim)return end;E("=== Memory each boot stage used ===",d.title)
for aN,aM in
ipairs(aL)do local aO=aL[aN+1]
if aO then
E(string.format(" %-30s %4dK  (%dK free after)",tostring(aM.stage),math.floor((
(aM.free or 0)- (aO.free or 0))/1024),math.floor((
aO.free or 0)/1024)),d.fg)else
E(string.format(" %-30s %5dK free",tostring(aM.stage),math.floor((aM.free or 0)/1024)),d.dim)end end;return end;local aD,az=Q.freeMemory(),Q.totalMemory()local aE=az-aD;local aA=az>0 and math.floor(
aE*100/az)or 0
local aH,aG=pcall(require,"kernel.monitor")local aC=math.min(24,math.max(8,q-36))
local aI=
(aH and aG.memBar)and aG.memBar(aE,az,aC)or
(
string.rep("#",math.floor(aA/100*aC))..string.rep("-",aC-math.floor(aA/100*aC)))E("=== Memory ===",d.title)
E(string.format(" RAM:  %dK used / %dK total   (%d%% used, %dK free)",math.floor(
aE/1024),math.floor(az/1024),aA,math.floor(aD/1024)),d.fg)
local aJ=aA<75 and d.highlight or(aA<90 and d.warning or d.error)E(" ["..aI.."]",aJ)
local aK,aB=pcall(function()
return h.getHAL().systemInfo()end)if aK and aB and(aB.memTierName or aB.memTier)then
E(
" Tier: ".. (aB.memTierName or("T"..aB.memTier)),d.dim)end
local aF=h.getSwap and h.getSwap()
if aF and aF.usage then local aM,aL=pcall(aF.usage)
if aM and type(aL)=="table"then
E(string.format(" Swap: %dK / %dK on /var/swap   ('slow RAM' overflow)",math.floor((
aL.bytes or 0)/1024),math.floor((aL.max or 0)/1024)),d.dim)end else
E(" Swap: off   (enable in Boot Settings for low-RAM overflow)",d.dim)end;if aD<16*1024 then
E(" ! Low memory — near the ~16K danger zone.",d.warning)end
E("Live usage: 'monitor'.  Hardware tiers: 'hw'.",d.dim)end
b.hw=function(ay,E)local az=h.getHAL().systemInfo()
E("=== Hardware ===",d.title)
E(string.format(" CPU T%d    GPU T%d    RAM %s",az.cpuTier or 0,az.gpuTier or 0,az.memTierName or("T"..
(az.memTier or 0))),d.fg)local aB,aA=pcall(require,"kernel.datacard")if
aB and aA and aA.detect then local aC=aA.detect()
E(" Data card: "..
(aC.present and aC.name or"none"),aC.present and d.fg or d.dim)end
E(string.format(" Components: %d    Network: %s    Tunnel: %s",
az.components or 0,az.canNetwork and"yes"or"no",az.hasTunnel and"yes"or"no"),d.dim)
E("Full component list: 'devices'.  Memory detail: 'mem'.  Live: 'monitor'.",d.dim)end;b.hardware=b.hw
b.ps=function(ay,E)local aC=u.getForeground(a.displayIdx)
local az=L.sessionOf(a)local aA=(az and az.tier)or 0
local aD=az and az.user or"?"
local aB=(ay[1]=="-v"or ay[1]=="--verbose")and aA>=2
if aB then
E(string.format(" %-4s %-14s %-8s %-3s %-10s %-6s %s","PID","Name","State","DSP","Owner","CPU","Caps"),d.title)else
E(string.format(" %-4s %-16s %-8s %-3s %-10s %s","PID","Name","State","DSP","Owner","CPU"),d.title)end
E(string.rep("-",aB and 70 or 50),d.border)
for aF,aE in ipairs(u.list())do local aG=aE.user or"?"
if aG=="_kernel_"then aG="kernel"end;local aH=false
if aA>=2 then aH=true elseif aA>=1 and aG==aD then aH=true elseif aA>=1 then aH="redacted"end
if aH==true then local aJ=d.fg;local aI=aE.state;if aE.tsr then aI="TSR"end;if aE.pid==aC then
aJ=d.highlight;aI=aI.." *"elseif aE.tsr then aJ=d.dim end
if aB then local aK={}if
aE.caps then for aL in pairs(aE.caps)do aK[#aK+1]=aL end
table.sort(aK)end
E(string.format(" %-4d %-14s %-8s %-3s %-10s %-6.1f %s",aE.pid,aE.name:sub(1,14),aI,tostring(
aE.display or"-"),(aG):sub(1,10),aE.cpuTime or 0,#aK>0 and
table.concat(aK,",")or"-"),aJ)else
E(string.format(" %-4d %-16s %-8s %-3s %-10s %.1fs",aE.pid,aE.name:sub(1,16),aI,tostring(aE.display or"-"),(aG):sub(1,10),
aE.cpuTime or 0),aJ)end elseif aH=="redacted"then
E(string.format(" %-4d %-16s %-8s %-3s %-10s   ",aE.pid,"(other user)","?","?","?"),d.dim)end end;E("",d.dim)
E(" * = foreground  |  -v for caps (admin+)  |  'monitor' for the live view",d.dim)end
b.monitor=function(ay,E)local aA,az=pcall(require,"shell.panels.monitorapp")if not aA then
E(
"Monitor unavailable: "..tostring(az),d.error)return end;az.open(a)end;b.top=b.monitor
b.watch=function(ay,E)
if not ay[1]then
E("Usage: watch [seconds] <command ...>",d.dim)
E("  Opens a self-updating tab. e.g.  watch ps  ·  watch 2 df  ·  watch mem",d.dim)return end;local aB,az=1,tonumber(ay[1])if az then aB=2 else az=1 end;if az<1 then az=1 end;if not
ay[aB]then E("Usage: watch [seconds] <command ...>",d.dim)
return end
local aC=table.concat(ay," ",aB)
local aA=(aC:match("^(%S+)")or""):lower()
local aD={edit=true,lua=true,monitor=true,top=true,watch=true,launcher=true,launch=true,apps=true,kiosk=true,chat=true,more=true,man=true,vault=true,keychain=true,passwd=true,tutorial=true,bootsettings=true,useradd=true,["tape-auth"]=true}if aD[aA]then
E("Can't watch '"..aA.."' — it's interactive/screen-driven.",d.error)return end;do
local aF,aG,aH=L.tierRefusal(a,aA)
if aF then E(aF,d.error)a.lastDenial={cmd=aA,need=aG,have=aH}return end end;if not c.openLiveTab then
E("Live tabs aren't available in this shell.",d.error)return end
local function aE()local aF={}local aG={}for aO in
aC:gmatch("%S+")do aG[#aG+1]=aO end;if#aG==0 then return aF end
local aH=aG[1]:lower()local aJ={}for aO=2,#aG do aJ[#aJ+1]=aG[aO]end
local aK=L.tierRefusal(a,aH)if aK then aF[#aF+1]={aK,d.error}return aF end;local aI=b[aH]
if
not aI then local aP,aO=pcall(require,Z)if aP and aO and aO.getCommand then
aI=aO.getCommand(aH)end end;if not aI then
aF[#aF+1]={"Unknown command: "..aH.."  [E-801 ERR_UNKNOWN_CMD]",d.error}return aF end
local aL=function(aO,aP)aF[#aF+1]={tostring(aO),
aP or d.fg}end;local aM,aN=pcall(aI,aJ,aL)if not aM then
aF[#aF+1]={"Error: "..tostring(aN),d.error}end;return aF end;c.openLiveTab("watch: "..aC,aE,az)end
b.why=function(ay,E)local aF=require(P)local aB=L.liveTier(a)
local az={title=d.title or d.highlight or d.fg,ok=
d.success or d.highlight or d.fg,err=d.error,fix=d.highlight or d.fg,dim=d.dim}local function aA(aG)
for aI,aH in ipairs(aG)do E(aH.text,az[aH.tone]or d.fg)end end
local aC=ay and ay[1]and ay[1]:lower()
if not aC then local aG=a.lastDenial
if aG and aG.cmd then
aA(L.whyExplain(aG.cmd,aG.need,aG.have or aB,true))return elseif aG then
E("Your last blocked action needed "..L.tierName(aG.need).."; you are "..
L.tierName(aG.have or aB)..".",d.error)
E("Fix: run it on an admin/root account, or have an admin grant access.",az.fix)return end;local aH=a.lastFailure
if aH then
E((aH.cmd and(aH.cmd.." failed:")or
"The last action failed:"),az.title)E("  "..aH.text,d.error)
local aI,aK,aJ=L.explainFailure(aH.text)if aJ then E("  "..aJ,az.dim)end
if aI then aA(aI)else
E("No canned explanation for that one.",d.dim)
E("`log` has the kernel's own record of it, and `doctor` checks",d.dim)
E("memory, disks, services and security for a cause.",d.dim)end;return end
E("Nothing has failed since the last command ran.",d.dim)
E("why            — explain the last refusal or error.",d.dim)
E("why <code>     — explain an error code: E-402, ERR_PATH_PROTECTED, K4.",d.dim)
E("why <command>  — explain what a command needs and whether you can run it.",d.dim)return end;local aE=L.explainCode(ay[1])if aE then aA(aE)return end
local aD=aF.entry(aC)
aA(L.whyExplain(aC,aD and aD.tier or 0,aB,aD~=nil))end
b.screendump=function(ay,E)if not n or not n.dump then
E("Screen capture isn't available on this seat.",d.error)return end
local aG,aB=pcall(n.dump)if not aG or type(aB)~="table"or not aB.lines then
E("Screen capture failed.",d.error)return end
local aD=(ay and ay[1])and
f(ay[1])or
f("screen-"..math.floor(h.uptime())..".txt")
local aH=(L.sessionOf(a)or{}).user or"?"
local aF=string.format("TOS screendump — seat %s · user %s · %dx%d · uptime %ds · read from the %s",tostring(a.displayIdx or"?"),aH,
aB.w or 0,aB.h or 0,math.floor(h.uptime()),tostring(aB.source or"?"))local az=string.char(10)local aA=aF..
az..string.rep("-",#aF)..az..
table.concat(aB.lines,az)..az
if aB.bg then
aA=aA..az..
"--- background colour runs, per row ---"..az
for aL=1,(aB.h or 0)do local aM=aB.bg[aL]
if aM then local aN={}for aP,aO in ipairs(aM)do
aN[#aN+1]=string.format("%d-%d:%s",aO.from,aO.to,
aO.c and string.format("%06X",aO.c)or"nil")end
aA=aA..
string.format("row %2d  %s",aL,table.concat(aN,"  "))..az end end;local aK=a.T or{}
aA=aA..
az..
"theme: bg="..
string.format("%06X",aK.bg or 0)..
"  statusbar_bg="..string.format("%06X",
aK.statusbar_bg or 0)..
"  menubar_bg="..string.format("%06X",
aK.menubar_bg or aK.bar_bg or 0)..az end;local aC=function(aK)
return aK and string.format("%06X",aK)or"nil"end;aA=aA..az..
"--- cache vs glass ---"..az
if
aB.disagree and#aB.disagree>0 then
aA=aA.."THE SHADOW DISAGREES WITH THE SCREEN on "..#aB.disagree..
" row(s)."..az
for aL,aK in ipairs(aB.disagree)do
aA=aA..
string.format("  row %2d col %2d  glass=%s  shadow believes=%s",aK.row,aK.col,aC(aK.glass),aC(aK.shadow))..az;local aM=aB.pageBg and aB.pageBg[aK.row]
if aM then local aN={}for aL,aO in
ipairs(aM)do
aN[#aN+1]=string.format("%d-%d:%s",aO.from,aO.to,aC(aO.c))end
aA=aA.."    off-screen page holds: "..
table.concat(aN,"  ")..az end end elseif aB.shadowBg then
aA=aA.."none — the shadow matches the glass everywhere."..az else
aA=aA.."(no shadow active on this seat)"..az end;local i=aB.state
if i then
aA=aA..
az..
"--- display machinery ---"..
az..
"  shadow="..
tostring(i.shadow)..
"  colour cache: fg="..

aC(i.lastFg)..
" bg="..
aC(i.lastBg)..
az..
"  backbuffer="..
tostring(i.backbuffer)..
"  broken="..
tostring(i.backBroken)..

"  frameDepth="..
tostring(i.frameDepth)..
"  pageStale="..
tostring(i.pageStale)..az..
"  writerGen="..
tostring(i.writerGen)..
"  mine="..tostring(i.myWriterGen).."  lastWriterIsMe="..
tostring(i.lastWriterIsMe)..az end;local aE=_G._TOS and _G._TOS.fs;if
not(aE and aE.writeFile)then
E("No filesystem available to write the dump.",d.error)return end
local aI,aJ=aE.writeFile(aD,aA)
if aI then
E("Screen captured -> "..aD.."  (".. (aB.h or 0).." rows)",
d.success or d.fg)
E("Attach it to a bug report, or 'cat' it to read it back.",d.dim)else
E("Could not write "..aD..": "..tostring(aJ),d.error)end end
b.crash=function(ay,E)if not r(E)then return end;local az=_G._TOS and _G._TOS.fs
if not
(az and az.list)then E("No filesystem.",d.error)return end
if ay and ay[1]then local aD=ay[1]:find("/")and f(ay[1])or
("/var/crash/"..ay[1])
local aF,aE=pcall(az.readFile,aD)if not aF or not aE then
E("No such crash report: "..aD,d.error)return end;for aG in
(tostring(aE).."\n"):gmatch("(.-)\n")do E(aG,d.fg)end;return end;local aC,aB=pcall(az.list,"/var/crash")local aA={}if
aC and type(aB)=="table"then
for aE,aD in ipairs(aB)do aD=tostring(aD):gsub("/$","")if
aD~=""and aD~="NEW"then aA[#aA+1]=aD end end end
if#aA==0 then
E("No crash reports — clean so far.",d.dim)
E("(TOS saves one here on a panic or an unrecoverable shell, so you",d.dim)E(" can read it after rebooting.)",d.dim)return end
E("Crash reports in /var/crash:",d.title or d.highlight or d.fg)for aE,aD in ipairs(aA)do E("  "..aD,d.fg)end
E("Read one with:  crash <name>",d.dim)end
b.history=function(ay,E)for az,aA in ipairs(a.cmdHistory)do
E(string.format(" %3d  %s",az,aA),d.dim)end;if#a.cmdHistory==0 then
E("(no history)",d.dim)end end
b.uptime=function(ay,E)local az=h.uptime()local aA=math.floor(az/3600)local aB=math.floor(
(az%3600)/60)local aC=math.floor(az%60)
E(string.format("Uptime: %dh %dm %ds (%.1fs total)",aA,aB,aC,az),d.fg)end
b.date=function(ay,E)
local az=h.getConfig and h.getConfig()or nil
if ay[1]=="tz"or ay[1]==ab or ay[1]=="set"then
local aI=(
az and az.get and az.get(ab))or 0;local aH=tonumber(ay[2])
if not aH then
E("Timezone offset: "..aI.."h",d.fg)
E("Usage: date tz <hours>   e.g. 'date tz -5'",d.dim)
E("OpenComputers has no settable clock; this only shifts the",d.dim)
E("DISPLAYED time relative to the world/host clock.",d.dim)return end;if aH<-23 or aH>23 then
E("Offset must be between -23 and 23.",d.error)return end;if not r(E)then return end
if not
(az and az.set)then E("No writable config available.",d.error)return end;az.set(ab,aH)if az.save then az.save()end
E("Timezone offset set to "..aH.."h. (was "..
aI.."h)",d.highlight)return end;local aC=ay[1]or"%Y-%m-%d %H:%M:%S"local aD=
(az and az.get and az.get(ab))or 0
local aA=_G._TOS and _G._TOS.fs;local aE=aA and aA.hostTime and aA.hostTime()local aF=(aE or
os.time())+ (aD*3600)
local aG,aB=pcall(os.date,aC,aF)if aG and aB then E(tostring(aB),d.fg)else
E(tostring(aB or"date error"),d.error)end end;b.time=b.date
b.keys=function(ay,E)local aH,az=pcall(require,aa)if not aH or not az then
E("Keybind module unavailable.",d.error)return end
local aA=(ay[1]or"list"):lower()local aB=false;for aJ=2,#ay do
if ay[aJ]==W then aB=true;table.remove(ay,aJ)break end end
local aI=(a.who=="root")and"/root"or(
"/home/".. (a.who or""))
local aD=aB and"/etc/keys.cfg"or(aI.."/.keys.cfg")local aF,aC=pcall(require,"kernel.serialize")
local function aG()
if not(aF and aC and
a.F.exists(aD))then return{}end;local aJ=a.F.readFile(aD)if not aJ then return{}end
local aL,aK=pcall(aC.decode,aJ,{maxBytes=8192})return
(aL and type(aK)=="table")and aK or{}end
local function aE(aJ)if not(aF and aC)then return false end
local aK=a.F.writeFile(aD,aC.encode(aJ))if aK then az.reload()end;return aK end
if aA=="list"or aA=="ls"then
E("TOS standard shortcuts:",d.title)for aK,aJ in ipairs(az.actions(a.who))do
E(string.format("  %-9s %-14s %s",aJ.action,aJ.keys,aJ.help),
aJ.isDefault and d.fg or d.highlight)end
E("",d.dim)
E("Reserved by the kernel — these cannot be rebound:",d.dim)for aK,aJ in ipairs(az.reserved())do
E(string.format("  %-9s %s",aJ.key,aJ.help),d.dim)end;E("",d.dim)
E("Change one:  keys set quit F4       (add --system for everyone)",d.dim)E("Undo:        keys reset [action]",d.dim)
E("Every first-party TOS program follows this table.",d.dim)elseif aA=="set"then local aJ,aM=ay[2],ay[3]
if not(aJ and aM)then
E("Usage: keys set <action> <key> [<key>...]",d.dim)
E("  e.g. keys set quit F4      keys set find ^F",d.dim)
E("Key names are written the way you say them: ^Q, F10, Ctrl+S, /",d.dim)return end;if not az.DEFAULTS[aJ]then
E("No such action: "..aJ.."  (see 'keys list')",d.error)return end;local aK={}
for aN=3,#ay do local aO=ay[aN]if not
az.parse(aO)then
E("Not a key name: '"..aO.."'  (try ^Q, F10, Ctrl+S, /)",d.error)return end
if az.isReserved(aO)then
E(aO..
" is reserved by the kernel and never reaches a program.",d.error)E("See 'keys list' for the reserved set.",d.dim)return end;aK[#aK+1]=aO end;local aL=aG()aL[aJ]=aK
if aE(aL)then
E(aJ..
" is now "..table.concat(aK," ").. (aB and"  (machine-wide)"or
""),d.highlight)else E(aj.. (aB and V or"."),d.error)end elseif aA=="reset"then local aJ=ay[2]local aK=aG()
if aJ then if not az.DEFAULTS[aJ]then
E("No such action: "..aJ,d.error)return end;aK[aJ]=nil;if aE(aK)then
E(aJ.." is back to the default.",d.highlight)else E(ak,d.error)end else if aE({})then
E("All shortcuts back to the defaults.",d.highlight)else E(ak,d.error)end end else
E("keys — TOS's standard keyboard shortcuts",d.title)
E("  keys list                     Show them",d.fg)
E("  keys set <action> <key>...    Rebind one",d.fg)
E("  keys reset [action]           Back to the default",d.fg)
E("Add --system to change them for every user (/etc/keys.cfg, admin).",d.dim)end end
b.menu=function(ay,E)local az=(ay[1]or"list"):lower()local aB=false
for aJ=2,#ay do if
ay[aJ]==W then aB=true;table.remove(ay,aJ)break end end;local aH=(a.who=="root")and"/root"or
("/home/".. (a.who or""))local aA=
aB and"/etc/menu.cfg"or(aH.."/.menu.cfg")
local aI,aF=pcall(require,"kernel.serialize")
if not aI or not aF then E("serialize unavailable",d.error)return end
local function aC()if not a.F.exists(aA)then return{}end
local aJ=a.F.readFile(aA)if not aJ then return{}end
local aL,aK=pcall(aF.decode,aJ,{maxBytes=8192})return
(aL and type(aK)=="table")and aK or{}end
local function aD(aJ)return a.F.writeFile(aA,aF.encode(aJ))end;local function aE()local aK,aJ=pcall(require,"shell.panels.draw")
if
aK and aJ and aJ.buildMenuDefs then a.menuDefs=aJ.buildMenuDefs(a)end end
local function aG(aJ)if
aJ.remove then
return"remove "..tostring(aJ.remove)..
(aJ.menu==true and" (whole menu)"or"")end;if aJ.rename then return
"rename "..
tostring(aJ.rename).." -> "..tostring(aJ.to)end;if
aJ.move then return
"move "..tostring(aJ.move).." -> "..tostring(aJ.menu)end
if aJ.menu and not
aJ.cmd then return"new menu "..tostring(aJ.menu)end;return
string.format("[%s] %s -> %s",aJ.menu or"Tools",aJ.add or aJ.label or"?",aJ.cmd or"?")end
if az=="list"or az=="ls"then local aJ=aC()
if#aJ==0 then
E("No menu edits in "..aA..".",d.dim)
E("Add one:  menu add <label> <command...> [in <Menu>]",d.dim)
E("Machine-wide instead of just you:  menu add ... --system",d.dim)return end;E("Menu edits ("..aA.."):",d.title)for aK,aL in ipairs(aJ)do
E(string.format("  %d. %s",aK,aG(aL)),d.fg)end elseif az=="show"then
local aK,aJ=pcall(require,"shell.panels.draw")if not aK or not aJ or not aJ.buildMenuDefs then
E("Menu system unavailable.",d.error)return end
for aM,aL in
ipairs(aJ.buildMenuDefs(a))do E(aL.label,d.title)
for aM,aN in ipairs(aL.items)do if aN.sep then E("    ---",d.dim)else
E(string.format("    %-20s %s",aN.label,(
aN.action or""):match("^run:(.+)$")or(aN.action or"")),d.fg)end end end
E("Change it with: menu add|remove|rename|move  (add --system for everyone)",d.dim)elseif az==ar or az=="move"then local aK,aL=ay[2],ay[3]if not(aK and aL)then
E("Usage: menu "..az..

" <name> <".. (az==ar and"new name"or"Menu")..">",d.dim)return end;local aJ=aC()
aJ[#aJ+1]=(
az==ar)and{rename=aK,to=aL}or{move=aK,menu=aL}
if aD(aJ)then aE()
E("Saved. "..aG(aJ[#aJ]),d.highlight)else E(aj.. (aB and V or"."),d.error)end elseif az=="hide"then local aJ=ay[2]if not aJ then
E("Usage: menu hide <item or Menu name>",d.dim)
E("Hides a built-in entry. 'menu reset' brings everything back.",d.dim)return end
local aK=aC()
aK[#aK+1]={remove=aJ,menu=(ay[3]=="menu")or nil}
if aD(aK)then aE()E("Hidden: "..aJ,d.highlight)else E(aj..
(aB and V or"."),d.error)end elseif az=="reset"then if aD({})then aE()
E("Menu reset to the built-in bar ("..aA.." cleared).",d.highlight)else
E("Reset failed".. (aB and V or"."),d.error)end elseif
az=="add"then local aK=ay[2]
if not aK or not ay[3]then
E("Usage: menu add <label> <command...> [in <Menu>]",d.dim)
E("  e.g. menu add Tetris tetris   |   menu add Disk df in System",d.dim)return end;local aJ=table.concat(ay," ",3)
local aL=aJ:match("%s+in%s+(%S+)%s*$")if aL then aJ=aJ:gsub("%s+in%s+%S+%s*$","")end
if
#aK>24 then E("Label too long (max 24).",d.error)return end;if#aJ==0 or#aJ>200 then
E("Command empty or too long.",d.error)return end;local aM=aC()
aM[#aM+1]={label=aK,cmd=aJ,menu=aL or"Tools"}
if aD(aM)then aE()
E(string.format("Added '%s' -> %s  (menu: %s)",aK,aJ,aL or"Tools"),d.highlight)else E("Save failed (is your home writable?).",d.error)end elseif az=="remove"or az=="rm"or az=="del"then
local aJ=tonumber(ay[2])local aK=aC()if not aJ or not aK[aJ]then
E("Usage: menu remove <#>   (see 'menu list')",d.error)return end
local aL=table.remove(aK,aJ)if aD(aK)then aE()
E("Removed '".. (aL.label or"?").."'.",d.highlight)else E(ak,d.error)end else
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
b.tree=function(ay,E)local aB=f(ay[1]or a.cwd)
local aE=tonumber(ay[2])or 3;local aC=400;local az,aA=0,false
local function aD(aF,aG,aH)if aA then return end;if aH>aE then return end
local aI=e.list(aF)or{}
table.sort(aI,function(aJ,aK)
local aL=e.isDirectory(aF.."/".. (aJ:gsub("/$","")))
local aM=e.isDirectory(aF.."/".. (aK:gsub("/$","")))if aL~=aM then return aL end;return aJ<aK end)
for aJ,aK in ipairs(aI)do if az>=aC then aA=true;return end;local aL=aK:gsub("/$","")
local aN=aF=="/"and(
"/"..aL)or(aF.."/"..aL)local aM=e.isDirectory(aN)local aO=(aJ==#aI)
local aP=aO and"`-- "or"|-- "local aQ=aM and d.dir or d.fg;E(aG..
aP..aL.. (aM and"/"or""),aQ)az=az+1;if aM then
aD(aN,aG.. (aO and"    "or
"|   "),aH+1)end end end;E(aB,d.title)aD(aB,"",1)if aA then
E(string.format("(truncated at %d entries; raise the limit or narrow the path)",aC),d.dim)end end
b.whoami=function(ay,E)if g then local az=g.getSession(i)
E(az and az.user or"root",d.fg)else E(a.who,d.fg)end end
b.passwd=function(ay,E)
if not g then E("No user system",d.error)return end;local aB=j("Current password: ",64,true)if not aB then return end
local az=j("New password: ",64,true)if not az then return end;local aF=j("Confirm new password: ",64,true)if
aF~=az then
a.lastOut={"Passwords do not match — unchanged.",d.error}return end;if az==""then
a.lastOut={"Password cannot be empty.",d.error}return end;local aC=g.getSession(i)local aD=
aC and aC.user or"root"
local aE,aA=g.changePassword(aD,aD,aB,az)
if aE and aA then
a.lastOut={"Password changed. "..tostring(aA),d.warning}elseif aE then a.lastOut={"Password changed.",d.highlight}else
a.lastOut={tostring(aA),d.error}end end
local function I(E,ay,az)local aD=a.st
local aB=g.registerSession and g.registerSession(E)or nil;local aE,aC=pcall(require,_)
local aA=aE and aC.current and aC.current()local aF=aA and aA.principal;if aB then a.st=aB end
if aA then aA.principal=E end;local aG,aH=pcall(ay)a.st=aD;if aA then aA.principal=aF end;if aB and g.logout then
pcall(g.logout,aB)end;if not aG then
az("sudo: "..tostring(aH),d.error)end end
local function t()if not a._sudo then return false end;a.st=a._sudo.origSt
local az,E=pcall(require,_)local ay=az and E.current and E.current()if ay then
ay.principal=a._sudo.origPrincipal end;if a._sudo.token and g.logout then
pcall(g.logout,a._sudo.token)end;a._sudo=nil;return true end;a.sudoDrop=t
b.sudo=function(ay,E)
if not g then E("No user system",d.error)return end;local aB=L.sessionOf(a)local az=ay[1]
if az=="setup"then if not w(E)then return end;local aH=2;if
ay[2]=="root"then aH=3 elseif ay[2]and ay[2]~="admin"then
E("Usage: sudo setup [admin|root]",d.dim)return end
local aG=j("New elevation password: ",64,true)if not aG or aG==""then E("Aborted.",d.dim)return end
if
j("Confirm: ",64,true)~=aG then E("Passwords do not match.",d.error)return end;local aI,aJ=g.setElevation(aB,aG,aH)
if aI then
E("Elevation configured (cap: "..
L.tierName(aH)..").",d.highlight)else E(tostring(aJ),d.error)end;return elseif az=="off"then if not w(E)then return end
local aG,aH=g.clearElevation and g.clearElevation(aB)if aG then E("Elevation disabled.",d.highlight)else
E(tostring(aH or"unavailable"),d.error)end;return elseif az=="-k"then
E(
t()and"Elevated session dropped."or"No active elevation.",d.dim)return end;if not az then
E("Usage: sudo <command> | sudo -s | sudo -k | sudo setup [admin|root] | sudo off",d.dim)return end
if
L.liveTier(a)<1 then E("sudo: guests cannot elevate.",d.error)return end
local aD=g.elevationInfo and g.elevationInfo()or{configured=false}if not aD.configured then
E("sudo: elevation is not configured. Root: sudo setup [admin|root]",d.warning)return end
local aC=j("[sudo] elevation password: ",64,true)if aC==nil then E("Aborted.",d.dim)return end
local aA,aE=g.elevate(aB,aC)if not aA then
E("sudo: "..tostring(aE or"elevation failed"),d.error)return end
if az=="-s"then t()
local aH=g.registerSession and
g.registerSession(aA)or nil;local aJ,aI=pcall(require,_)
local aG=aJ and aI.current and aI.current()
a._sudo={origSt=a.st,origPrincipal=aG and aG.principal,token=aH}if aH then a.st=aH end;if aG then aG.principal=aA end
E("Elevated to "..
L.tierName(aA.tier)..". 'sudo -k' or 'logout' drops it.",d.highlight)return end;local aF=table.concat(ay," ")
I(aA,function()if not a.execOne then
E("sudo: executor unavailable",d.error)return end;local aG=a.execOne(aF)if
type(aG)=="table"then
for aI,aH in ipairs(aG)do if type(aH)=="table"then E(aH[1],aH[2]or d.fg)else
E(tostring(aH),d.fg)end end end end,E)end;b.logout=function(E,ay)L.logout(a)end
b.cli=function(ay,E)if a.isCLI then
E("You are already at the command line. Type 'tui' for the full interface.",d.dim)return end;a._exitTo="cli"end
b.tui=function(ay,E)if a.isCLI then E("Returning to the full interface…",d.dim)
a._exitTo="tui"return end
E("You are already in the full interface. Type 'cli' for the command line.",d.dim)end
b.reboot=function(ay,E)local az,aA=L.canPowerOff(a)
if not az then E(aA,d.error)return end;h.reboot()end
b.shutdown=function(ay,E)local az,aA=L.canPowerOff(a)
if not az then E(aA,d.error)return end;h.shutdown()end
b.env=function(E,ay)local aC,az=pcall(require,"kernel.env")if not aC then
ay("Env module unavailable",d.error)return end;local aB=h.getProc()local aA=
aB and aB.current()or nil
if E[1]then
local aD,aE=E[1]:match("^([%w_]+)=(.*)$")if not aD and E[2]and E[1]:match("^[%w_]+$")then
aD,aE=E[1],table.concat(E," ",2)end;if aD then az.write(aA,aD,aE)ay(aD..
"="..aE,d.highlight)else local aF=az.read(aA,E[1])
ay(E[1].."="..tostring(
aF or""),d.fg)end else
local aE,aD=az.list(aA),{}for aF in pairs(aE)do aD[#aD+1]=aF end;table.sort(aD)for aG,aF in
ipairs(aD)do
ay("  "..aF.."="..tostring(aE[aF]),d.fg)end end end;b.export=b.env;b.set=b.env
b["tape-menu"]=function(ay,E)
local aG,aA=pcall(require,"shell.launcher")if not aG or not aA then
E("Menu engine unavailable (low RAM?)",d.error)return end;if not n or not n.getSize then
E("tape-menu needs a screen.",d.error)return end;local aB=nil
local function aH(aN)local aO={}local aP={}for aX in
aN:gmatch("%S+")do aP[#aP+1]=aX end;if#aP==0 then return aO end
local aQ=aP[1]local aS={}for aX=2,#aP do aS[#aS+1]=aP[aX]end
local aT=L.tierRefusal(a,aQ:lower())if aT then aO[#aO+1]={aT,d.error}return aO end;if not aB then
aB=require(P).build(a,c)end;local aR=aB[aQ]
if not aR then local aY,aX=pcall(require,Z)if aY and aX and
aX.getCommand then aR=aX.getCommand(aQ)end end;if not aR then
aO[#aO+1]={"Unknown command: "..aQ,d.error}return aO end;local aU=function(aX,aY)
aO[#aO+1]={tostring(aX),aY or d.fg}end
local aV,aW=pcall(aR,aS,aU)if not aV then
aO[#aO+1]={"Error: "..tostring(aW),d.error}end;return aO end;local aD=R.list and R.list("tape_drive")()
if
not aD then E("No tape drive found.",d.error)return end;local az=R.proxy(aD)
local aI,aJ=pcall(function()return az.isReady()end)
if not aI or not aJ then E("No tape inserted.",d.warning)return end
local aK=(az.getSize and az.getSize())or 0
if aK<=0 then E("Tape is empty.",d.warning)return end
local aC=j and j("Tape menu passphrase: ",64,true)or nil;if not aC or aC==""then E(ag,d.dim)return end
local aL,aE=pcall(require,"kernel.vault")
if not aL or not aE then E("vault unavailable",d.error)return end;local aF,aM=aA.readTapeMenuFromDrive(az,aC,aE)if not aF then
E(tostring(aM),d.error)return end
aA.run({display=n,profile=aF,runLine=aH,title="Tape toolbox"})if c.drawAll then pcall(c.drawAll)end end
b.clip=function(ay,E)local aC,az=pcall(require,"kernel.clipboard")if not aC or not az then
E(
"Clipboard unavailable: "..tostring(az),d.error)return end;local aA=a.displayIdx;local aB=ay[1]
if
not aB then
E("Clipboard: "..az.describe(aA),d.title)local aD=az.get(aA)
if aD and not az.isEmpty(aA)then
local aE=math.min(#aD,10)for aF=1,aE do E("  "..aD[aF],d.fg)end;if#aD>aE then
E("  ... "..
(#aD-aE).." more line(s)",d.dim)end end
E("Usage: clip [set <text> | clear]   Copy: "..
(function()local aF,aE=pcall(require,aa)
return(aF and aE)and
aE.label("copy",a.who)or"Ctrl+Insert"end)(),d.dim)return end;if aB=="clear"then az.clear(aA)
E("Clipboard cleared.",d.highlight)return end
if aB=="set"then
local aD=table.concat(ay," ",2)
if aD==""then E("Usage: clip set <text>",d.warning)return end;local aF,aE=az.set(aD,aA)if not aF then
E("Could not set clipboard: "..tostring(aE),d.error)return end;if aE then
E("Clipboard set, TRUNCATED at the cap: "..
az.describe(aA),d.warning)else
E("Clipboard: "..az.describe(aA),d.highlight)end;return end;E("Usage: clip [set <text> | clear]",d.warning)end
b.desktop=function(ay,E)local aA,az=pcall(require,"shell.panels.desktop")if not aA then
E(
"Desktop unavailable: "..tostring(az),d.error)return end;az.open(a)end
b.settings=function(ay,E)local aA,az=pcall(require,"shell.panels.settingsapp")if
not aA then
E("Settings unavailable: "..tostring(az),d.error)return end;az.open(a)end
b.lang=function(ay,E)local aD,az=pcall(require,"kernel.i18n")if not aD or not az then
E(
"i18n unavailable: "..tostring(az),d.error)return end;local aA=ay[1]
if not aA then
E(ai..az.language()..
"  ("..az.languageName()..")",d.title)E("Installed catalogs:",d.fg)for aI,aH in ipairs(az.available())do
local aJ=(aH.code==
az.language())and" * "or"   "
E(aJ..string.format("%-8s %s",aH.code,aH.name),d.fg)end
E("Usage: lang <code> | lang system <code> | lang dump [path]",d.dim)
E("Catalogs are DATA files at /usr/lang/<code>.lang — see 'man lang'.",d.dim)return end
if aA=="system"then if not r(E)then return end;local aH=ay[2]if not aH then
E("Usage: lang system <code|en>",d.dim)return end;local aI,aJ=az.setLanguage(aH)
if not aI then E(
"Cannot set: "..tostring(aJ),d.error)return end
if p and p.set then p.set("language",aH)if p.save then p.save()end end
E("System language: "..az.language(),d.highlight)return end
if aA=="dump"then
local aI=f(ay[2]or"/tmp/lang-template.lang")local aJ=az.keysSeen()if#aJ==0 then
E("No keys seen yet — visit a few screens first (log out/in, open the Desktop).",d.warning)return end
local aH={"-- TOS language catalog template (every t() key seen this session).","-- Translate the values, set meta.code/name, save as /usr/lang/<code>.lang,","-- then run `lang <code>`. Untranslated keys keep their English default.","-- An admin can write there directly, or ship the catalog as a package.","return {",'  meta = { code = "xx", name = "Language name" },',"  strings = {"}for aN,aM in ipairs(aJ)do
aH[#aH+1]=string.format("    [%q] = %q,",aM.key,aM.default)end;aH[#aH+1]="  },"
aH[#aH+1]="}"
if not o(aI)then E("Cannot write: "..aI,d.error)return end
local aL,aK=e.writeFile(aI,table.concat(aH,"\n").."\n")if aL then
E("Template with "..#aJ.." key(s) -> "..aI,d.highlight)k()else E(al..aI,d.error)
if aK then E(tostring(aK),d.dim)end end;return end;local aE,aF=az.setLanguage(aA)if not aE then
E("Cannot set '"..tostring(aA)..
"': "..tostring(aF),d.error)E("Run 'lang' to list installed catalogs.",d.dim)
return end
local aC=L.sessionOf(a)local aG,aB=pcall(require,"kernel.profile")
if aG and aB and aB.load and
aB.save then local aH=aB.load(aC)
aH.lang=
(az.language()~="en")and az.language()or nil;local aI,aJ=aB.save(aH,aC)
if aI then
E(ai..
az.language().."  (saved to your profile)",d.highlight)else
E("Language set for this session (profile save failed: "..tostring(aJ)..")",d.warning)end else
E(ai..az.language().."  (this session)",d.highlight)end end end