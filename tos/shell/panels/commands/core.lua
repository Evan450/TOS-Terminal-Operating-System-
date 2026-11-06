
local ad,M,U,V,ae,N,af,ag,W,ah,ai,aj,X,ak,al,L,am,Y,Z,an,ao,ap,aq,_,O,aa="  Examples:","  Subcommands:"," (needs admin for /etc).","--system","Cancelled.","Cannot read: ","Keychain is locked.","Language: ","No such file: ","Save failed","Save failed.","Write failed: ","[^/]+$","^(.*)/[^/]+/?$","decrypt","encrypt","function","kernel.pkg","kernel.process","profile module unavailable","recursive","rename","save failed","shell.keys","shell.panels.commands","timezone"local P=require("computer")local Q=require("component")
local K=require("shell.panels.helpers")local R=function()end
do local b,a=pcall(require,Z)if b and a and a.yieldCooperative then
R=a.yieldCooperative end end;local function S()local a,b=pcall(require,"shell.panels.home")
return(a and b)or nil end;local function ab(a)local b=S()return
b and b.cycleKeyLabel(a)or"F2"end
local function ar(a)
local b=S()if b and b.enabled(a)then
return b.viewKeyLabel(a).."  Tiles / files "end;return"F2  Next tab      "end
local function ac(a)local e=S()local d,b=pcall(require,_)if not(d and b)then
return"Copy Ctrl+Insert  Cut ^X  Paste ^V"end;local c=a and a.who or nil;return
"Copy "..
b.label("copy",c).."  Cut "..
b.label("cut",c).."  Paste "..b.label("paste",c)end
local function T(a)local c,b=pcall(require,_)return
(c and b and b.quitHint)and b.quitHint(a and a.who or
nil)or"^Q"end
local function as(a)local b=ab(a)return b..
string.rep(" ",math.max(1,12-#b)).."Next tab   "end
return
function(b,a,c)local h,J,u,e,n,g=a.K,a.E,a.P,a.F,a.D,a.U;local p,A,i=a.SC,a.NM,a.st;local d=a.T;local B=a.tier
local q,v=a.W,a.H;local f=c.rp;local s=c.openViewTab;local at=c.openEditTab;local k=c.refreshBrowser
local l=c.canRead;local o=c.canWrite;local au=c.canAccess;local w=c.rootOnly;local r=c.adminOnly
local av=c.makeProgramEnv;local m=K.fmtSz
local aw=function(E)return K.expandBuf(a,E)end;local j=c.promptInput
b.help=function(ax,E)
local ay=ax and ax[1]and ax[1]:lower()
if ay=="cp"or ay=="copy"then E("cp <source> <dest>",d.title)
E("  Copy a file. Both paths are required.",d.fg)
E("  Paths starting with / are absolute; others are relative to cwd.",d.fg)E(ad,d.dim)
E("    cp notes.txt /home/root/notes_bak.txt",d.dim)E("    cp /etc/cfg.conf /tmp/cfg.conf",d.dim)
E("  Tip: Use F5 in the browser for clipboard-style copy.",d.highlight)elseif ay=="mv"then E("mv <source> <dest>",d.title)
E("  Move or rename a file.",d.fg)E(ad,d.dim)
E("    mv old.txt new.txt           (rename in cwd)",d.dim)
E("    mv /tmp/work.lua /home/root/ (move to dir)",d.dim)elseif ay=="cd"then E("cd [dir]",d.title)
E("  Change directory. With no argument, prints current directory.",d.fg)
E("  Special paths:  ..  (parent)   ~  (home dir)",d.fg)elseif ay=="find"then E("find [path] [-name pattern]",d.title)
E("  Recursively search for files. Pattern uses Lua patterns.",d.fg)E(ad,d.dim)E("    find /tos -name *.lua",d.dim)
E("    find /home",d.dim)elseif ay=="grep"then E("grep <pattern> <file>",d.title)
E("  Search file lines for pattern (plain text, not regex).",d.fg)
E("  Example:  grep function /tos/shell/init.lua",d.dim)elseif ay=="flash"then E("flash <file>",d.title)
E("  Write a Lua file to the EEPROM (overwrites BIOS!).",d.fg)
E("  Prompts for confirmation. Use to install a new BIOS.",d.fg)E("  Example:  flash /tos/bios.lua",d.dim)elseif ay=="edit"then
E("edit <file>",d.title)
E("  Open file in editor tab. Creates the file if it doesn't exist.",d.fg)
E("  Keys:  Ctrl+S = save   Ctrl+Q = close tab   Ctrl+F = find",d.dim)E("  Ctrl+H = find/replace  Ctrl+Z = undo",d.dim)E(
"  Select: Shift+arrows.  "..ac(a),d.dim)
E("  With nothing selected, copy/cut take the whole line.",d.dim)
E("  Use "..ab(a).." to switch tabs, F4 to close.",d.dim)elseif ay=="run"then E("run <file> [args...]",d.title)
E("  Execute a Lua file in the current environment.",d.fg)
E("  Args are passed as a table in the second argument.",d.fg)elseif ay=="tape"then E("tape [subcommand]",d.title)
E("  Data storage on Computronics tapes (requires module).",d.fg)
E("  If the tape package is not installed, shows",d.fg)
E("  instructions for installing it or building your own.",d.fg)E("",d.fg)
E("  Subcommands (when module is active):",d.dim)E("    detect           List tape drives",d.dim)
E("    info             Tape size, label, format",d.dim)E("    label [name]     Get/set tape label",d.dim)
E("    store <path>     Archive file/dir to tape",d.dim)
E("    restore [path]   Restore archive from tape",d.dim)
E("    list             List archived entries",d.dim)
E("    dump [off] [len] Hex dump of tape bytes",d.dim)E("    erase [full]     Quick or full wipe",d.dim)
E("    raw read/write   Low-level byte I/O",d.dim)elseif ay=="net"then E("net [subcommand]",d.title)
E("  Network management (requires modem or linked card).",d.fg)E("",d.fg)E(M,d.dim)
E("    status              Show network status",d.dim)
E("    discover / scan     Broadcast ping to find peers",d.dim)
E("    peers / list        List known peers and trust levels",d.dim)
E("    trust <addr> [full] Elevate peer to KNOWN or TRUSTED",d.dim)E("    block <addr>        Block a peer",d.dim)
E("    send <addr> <msg>   Send message to trusted peer",d.dim)E("",d.fg)
E("  Related: ping <addr>, hostname [name], chat",d.dim)elseif

ay=="pkg"or ay=="mod"or ay=="module"or ay=="modules"or ay=="package"or ay=="packages"then E("pkg [subcommand]",d.title)
E("  Package manager — install and manage add-ons. (Replaces the old",d.fg)
E("  'mod'/module manager, retired in v1.3.1.)",d.fg)E("",d.fg)E(M,d.dim)
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
E("  Shortcuts: 'install <name>' and 'uninstall <name>' work too.",d.dim)elseif ay=="monitor"or ay=="top"then
E("monitor   (alias: top; also opened with Ctrl+T)",d.title)
E("  The live System Monitor — one screen showing what TOS is doing.",d.fg)E("",d.fg)E("  Shows:",d.dim)
E("    · Every process (kernel AND user), each explained, with owner,",d.dim)
E("      state, CPU and seat — auto-refreshing.",d.dim)
E("    · rc.d services and their status (admin).",d.dim)E("    · Memory and uptime vitals.",d.dim)
E("",d.fg)
E("  Runs as a full-screen tab: scrolls, never truncates, per-seat.",d.dim)E("",d.fg)E("  Keys:",d.dim)
E("    up/down move   Enter switch-to   K kill   T suspend/resume (TSR)",d.dim)
E("    Enter start-stop a service (admin)   R refresh   "..T(a).." close",d.dim)elseif ay=="cron"then E("cron [subcommand]",d.title)
E("  Manage scheduled tasks.  (admin+)",d.fg)E("",d.fg)E(M,d.dim)
E("    list                Show all cron jobs",d.dim)
E("    add <interval> <cmd> Schedule a command",d.dim)
E("    rm <id>             Remove a cron job",d.dim)elseif ay=="service"then E("service [subcommand]",d.title)
E("  Manage startup services.  (admin+)",d.fg)E("",d.fg)E(M,d.dim)
E("    (none)              List all services and status",d.dim)E("    start <name>        Start a service",d.dim)
E("    stop <name>         Stop a service",d.dim)elseif ay=="users"or ay=="useradd"or ay=="userdel"or
ay=="usermod"then
E("User Management  (admin/root)",d.title)
E("  users                   List all user accounts",d.fg)
E("  useradd <name>          Create a new user",d.fg)E("  userdel <name>          Delete a user",d.fg)
E("  usermod <user> <action> Modify a user:",d.fg)
E("    lock / unlock         Lock or unlock an account",d.dim)
E("    admin / user          Set role to admin or user",d.dim)
E("  whoami                  Show current user",d.fg)
E("  passwd                  Change your password",d.fg)elseif ay=="disk"then E("disk [subcommand]",d.title)
E("  Manage removable disks (floppies, HDDs).",d.fg)E("",d.fg)E(M,d.dim)
E("    list                List removable disks",d.dim)
E("    info <mount>        Show disk contents",d.dim)
E("    install <mount>     Install module from disk (admin)",d.dim)
E("    export <name> <mnt> Write module to disk    (admin)",d.dim)E("    eject <mount>       Unmount a disk",d.dim)elseif ay==
"redstone"or ay=="rs"then
E("redstone [subcommand]  (alias: rs)",d.title)E("  Control redstone I/O on all sides.",d.fg)
E("",d.fg)E(M,d.dim)
E("    (none)              Show redstone levels",d.dim)
E("    set <side> <level>  Set output (0-15)",d.dim)
E("    pulse <side> [dur]  Pulse output (default 0.5s)",d.dim)elseif ay=="robot"then E("robot <command>",d.title)
E("  Control robot/drone movement and interaction.",d.fg)E("",d.fg)
E("  Movement: forward, back, up, down, left, right",d.dim)
E("  Actions:  swing, use, place, suck, drop, detect",d.dim)E("  Info:     name, energy, slot <n>",d.dim)elseif
ay=="audio"or ay=="sound"or ay=="beep"then
E("audio [subcommand]",d.title)
E("  Control audio feedback (beeps and notifications).",d.fg)E("",d.fg)E(M,d.dim)
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
E("    2 descending        Shutdown / logout",d.dim)E("    3 ascending         Boot complete",d.dim)elseif ay and
ay~=""then local aA=require(O)local az=aA.entry and aA.entry(ay)
if az then
local aC={[0]="guest",[1]="user",[2]="admin",[3]="root"}E(ay,d.title)
E("  ".. (az.help or"(no description)"),d.fg)E("",d.fg)
E(string.format("  Minimum tier: %s    Group: %s",aC[az.tier or 0]or
tostring(az.tier),az.category or"?"),d.dim)
local aB="  Tip: run '"..ay.."' with no args for usage"
if e.exists("/usr/man/"..ay..".man")then aB=aB.."; 'man "..
ay.."' for the manual."else aB=aB.."."end;E(aB,d.dim)else
E("No such command: '"..ay.."'.  Type 'help' for the full list.",d.warning)end else local aA=require(O)
local function az(aF)return aA.needMet and aA.needMet(aF)end
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
E("  F1  Help      "..ar(a)..
"  F3  View file",d.fg)
E("  F4  Close tab F5  Copy file      F6  Move file",d.fg)
E("  "..as(a).." F9  Menu bar",d.fg)E("  F7  Mkdir     F8  Delete",d.fg)
E("  Text: Shift+arrows select.  "..ac(a),d.fg)
E("  F10 Quit      "..T(a).."  Cancel/Close   ^F  Find",d.fg)
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
E("  edit <file>   Open in editor tab  (^S save, "..T(a).." close)",d.fg)end
if a.userTier>=3 then
E("  lua           Interactive Lua REPL  (exit to quit)",d.fg)
E("  flash <file>  Flash EEPROM with Lua file  (!CAUTION)",d.fg)end
E("  programs      List executables in /bin and /usr/bin",d.fg)E("  history       Show command history",d.fg)
E("  date [fmt]    Show wall clock  (time = alias)",d.fg)
E("  tree [path] [depth]  Visual recursive directory listing",d.fg)
E("  theme [list|set|color|...]  Customize colors  (colors = alias)",d.fg)
E("  tutorial      Replay the welcome walkthrough",d.fg)if a.userTier>=1 and az("swap")then
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
E("  cron [list|add|rm]        Scheduled tasks",d.fg)end;local aB,aC=az("component:redstone"),az("component:robot")
local aD,aE=az("inventory"),az("module:tape")
if aB or aC or aD or aE or a.userTier>=2 then E("",d.fg)
E(" Peripherals",d.highlight)if aB then
E("  redstone [set|pulse] Control redstone I/O  (rs = alias)",d.fg)end;if aC then
E("  robot <cmd>          Robot/drone movement & interaction",d.fg)end;if aD then
E("  inventory [side]     Inspect inventories  (inv = alias)",d.fg)end;if aE then
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
E("  cmd >> file        Append output to file",d.fg)
E("  One command per line: there is no && or ||.",d.dim)E("",d.fg)
E("Showing only what's installed here. 'man <topic>' for detail; MANUAL.md for the book.",d.dim)end end
b.man=function(ax,E)local az="/usr/man"local ay=ax and ax[1]
if not ay then
E("Manual pages — usage: man <topic>",d.title)local aC=
(e.isDirectory and e.isDirectory(az)and e.list(az))or{}
if
type(aC)=="table"and#aC>0 then table.sort(aC)
for aE,aD in ipairs(aC)do
local aF=(aD:gsub("/$","")):gsub("%.man$","")if aF~=""then E("  "..aF,d.fg)end end else
E("  (no manual pages installed under "..az..")",d.dim)end
E("Depth: help (quick) < man (detailed) < MANUAL.md (the full book)",d.dim)return end;ay=tostring(ay):gsub("[^%w_%-]","")if ay==""then
E("man: invalid topic",d.error)return end;local aA=e.join(az,ay..".man")if not
e.exists(aA)then aA=e.join(az,ay)end
if not e.exists(aA)then E(
"No manual page for '"..ay.."'.",d.error)
E(
"Try 'help "..ay.."', or open MANUAL.md for the full book.",d.dim)return end;local aB=e.readFile(aA)if not aB then
E("man: cannot read page",d.error)return end
if s then local aC={}
for aD in
(aB.."\n"):gmatch("([^\n]*)\n")do local aE=d.fg
if aD:match("^[A-Z][A-Z0-9 /%-]+$")then aE=d.title elseif aD:match("^%s")then aE=d.dim end;aC[#aC+1]={aD,aE}end;s(aC,"man "..ay)else for aC in(aB.."\n"):gmatch("([^\n]*)\n")do
E(aC,d.fg)end end end
b.about=function(ax,E)local ay=_G._TOS or{}
local aB,az,aC="Strata Systems LLC",nil,"Terminal Operating System"local aD,aA=pcall(require,"kernel.logo")if aD and aA then
aB=aA.VENDOR or aB;az=aA.MOTTO;aC=aA.TAGLINE or aC end;E(
"TOS - "..aC,d.title)
E("Version "..
(ay.version or"?").."  [".. (ay.codename or
"?").."]",d.highlight)
E("Build "..tostring(ay.build or"?").." ("..
tostring(ay.variant or"?")..")",d.dim)
E("GPU T"..B.." | "..
math.floor(P.totalMemory()/1024).."K RAM",d.dim)E(aB.."   -   GNU GPL v3.0",d.dim)if az and az~=""then E(
'"'..az..'"',d.dim)end;E("",d.fg)
E("A secure, multi-seat terminal OS for OpenComputers:",d.fg)
E("  - Sandboxed processes, role-based users, encrypted homes",d.fg)
E("  - Tabbed file browser + editor, themeable panels UI",d.fg)
E("  - Zero-trust networking: chat, mesh mail, clustering",d.fg)
E("  - Package manager + Optional Utilities add-on disk",d.fg)
E("  - Boot Settings (DEL at POST), swap, backups, OpenOS compat",d.fg)E("",d.fg)
E("'help' lists commands · 'tutorial' walks you through it.",d.dim)end;b.ver=b.about
b.echo=function(E,ax)ax(table.concat(E," "),d.fg)end
b.notify=function(ax,E)local aF,ay=pcall(require,"kernel.notify")if not aF or not ay then
E("notify unavailable",d.error)return end;local aA,aB,az="info",nil,{}local aC
for aH=1,# (ax or{})
do local aI=tostring(ax[aH])
if aH==aC then elseif aI:sub(1,2)=="--"then
local aK,aJ=aI:match("^%-%-([%w%-]+)=?(.*)$")
if aK=="style"or aK=="title"then if aJ==""and ax[aH+1]and
tostring(ax[aH+1]):sub(1,2)~="--"then
aJ=tostring(ax[aH+1])aC=aH+1 end
if aK=="style"then aA=aJ else aB=aJ end end else az[#az+1]=aI end end;local aD=table.concat(az," ")
if aD==""then
E("Usage: notify <message> [--style info|warn|danger|error] [--title T]",d.title)
E("Puts a modal dialog box in front of every seat — the intrusive",d.dim)
E("counterpart to 'echo', which only writes above the command line.",d.dim)E("",d.dim)
E(string.format("Pending now: %d   (limits: %ds between boxes, %ds per source)",ay.depth(),ay.MIN_GAP,ay.MIN_SOURCE_GAP),d.dim)return end
local aE,aG=ay.post({message=aD,style=aA,title=aB,from="notify/"..tostring(a.who or"?")})
if aE then
E("Raised on every seat (dialog #"..aE..").",d.highlight)else
E("Not raised: "..tostring(aG),d.warning)
E("The message is in the log either way ('log' to see it).",d.dim)end end
b.tutorial=function(ax,E)local az,ay=K.requireRoomy(a,"shell.tutorial","core")
if
not az then E(K.loadFailure("tutorial",ay),d.error)return end
if ax[1]=="--reset"then local aB=
(g and i and g.getSession)and g.getSession(i)or nil;local aA=ay.markerFor and
ay.markerFor(aB)
if aA and e.exists(aA)then
e.remove(aA)
E("Tutorial reset — it will run again at your next login.",d.success or d.fg)elseif aA then
E("Tutorial was not marked done for this account.",d.dim)else
E("This account has no home to remember the tutorial in.",d.dim)end end;ay.run({D=n,F=e,U=g,st=i,W=q,H=v})c.drawAll()end
b.cls=function(E,ax)n.fill(1,1,q,v," ",d.fg,d.bg)c.drawAll()end;b.clear=b.cls
b.cd=function(E,ax)if not E[1]then ax(a.cwd,d.fg)return end
local ay=E[1]
if ay==".."then a.cwd=a.cwd:match(ak)or"/"
if a.cwd==""then a.cwd="/"end else local az=f(ay):gsub("//+","/")if
az~="/"and az:sub(-1)=="/"then az=az:sub(1,-2)end
if e.isDirectory(az)then a.cwd=az else ax(
"Not a directory: "..ay,d.error)return end end;a.browser.path=a.cwd;a.browser.sel=1;a.browser.scroll=0
c.loadFiles(a.browser)end
b.ls=function(ax,E)local aD,aH,aA=false,false,nil
for aQ,aP in ipairs(ax)do
if not aA and aP:sub(1,1)=="-"and
#aP>1 then
for aR in aP:sub(2):gmatch(".")do if aR=="l"then aD=true elseif aR=="a"then aH=true else
E("Usage: ls [-l|-a] [dir]",d.dim)return end end elseif not aA then aA=aP end end;local ay=f(aA or a.cwd)if not l(ay,E)then return end;if e.exists and
not e.exists(ay)then
E("no such file: ".. (aA or ay),d.error)return end
local aM,aB=pcall(e.list,ay)
if not aM or not aB then E("Cannot list: "..ay,d.error)return end;local az,aE={},0;local function aI(aP)
if aH or aP:sub(1,1)~="."then az[#az+1]=aP else aE=aE+1 end end
if type(aB)=="table"then for aQ,aP in ipairs(aB)do
aI(aP)end elseif type(aB)==am then for aP in aB do aI(aP)end end
table.sort(az,function(aP,aQ)local aR,aS=aP:sub(-1)=="/",aQ:sub(-1)=="/"if aR~=aS then
return aR end;return aP<aQ end)
local function aN(aP)if not e.lastModified then return"-"end
local aR,aQ=pcall(e.lastModified,e.join(ay,aP))
if not aR or type(aQ)~="number"or aQ<=0 then return"-"end
local aS,aT=pcall(os.date,"%Y-%m-%d %H:%M",math.floor(aQ/1000))return aS and aT or"-"end;local function aJ(aP)
if aP:sub(-1)=="/"then return"["..aP:sub(1,-2).."]"end;return aP end;local aG=24;for aQ,aP in ipairs(az)do aG=math.max(aG,#
aJ(aP))end
local aO=
(tonumber(a.W)or 80)-11- (aD and 18 or 0)local aC=math.max(24,math.min(aG,aO))
local function aK(aP)
if#aP<=aC then return aP end;local aQ=aC-1;while

aQ>0 and(aP:byte(aQ+1)or 0)>=0x80 and(aP:byte(aQ+1)or 0)<0xC0 do aQ=aQ-1 end
return aP:sub(1,aQ).."~"end;local aF=" %-"..aC.."s %8s"
if aD then
E(string.format(aF.."  %s","Name","Size","Modified"),d.title)E(string.rep("-",aC+28),d.border)else
E(string.format(aF,"Name","Size"),d.title)E(string.rep("-",aC+10),d.border)end
for aQ,aP in ipairs(az)do local aS,aR
if aP:sub(-1)=="/"then
aS=string.format(aF,aK(aJ(aP)),"<DIR>")aR=d.dir or d.highlight else local aT=e.size(e.join(ay,aP))
aR=d.fg
if aP:match("%.lua$")then
aR=d.file_lua or d.file_exec or d.highlight elseif aP:match("%.cfg$")or aP:match("%.conf$")then
aR=d.file_cfg or d.warning elseif aP:match("%.log$")then aR=d.file_log or d.dim end;aS=string.format(aF,aK(aP),m(aT))end;if aD then aS=aS.."  "..aN(aP)end;E(aS,aR)end
local aL=#az.. (#az==1 and" item"or" items")if aE>0 then
E(aL.." ("..aE.." hidden: ls -a shows them)",d.dim)else E(aL,d.dim)end end;b.dir=b.ls
local function C(ax,E)local ay=f(ax)if not l(ay,E)then return true end;local az,aA,aB=K.readLinesCapped(e,ay,function(aC)
E(aC,d.fg)end)if not az then E(
N..ax,d.error)elseif aB then
E(string.format(K.VIEW_STOPPED,aA),d.warning)return false end;return true end
b.cat=function(E,ax)
if not E[1]then ax("Usage: cat <file...>",d.dim)return end;for az,ay in ipairs(E)do if not C(ay,ax)then break end end end;b.type=b.cat
b.more=function(E,ax)
if not E[1]then ax("Usage: more <file>",d.dim)return end;local az=f(E[1])if not l(az,ax)then return end
local ay={{" "..az,d.title}}
local aA,aB,aC=K.readLinesCapped(e,az,function(aD)ay[#ay+1]={aD,d.fg}end)if not aA then ax(N..E[1],d.error)return end;if aC then
ay[#ay+1]={string.format(K.VIEW_STOPPED,aB),d.warning}end
s(ay,E[1]:match(X)or E[1])end
local function D(E,ay,ax)local az=f(E)local aA=az:match(ak)or"/"
if not o(aA,ax)then return false end
if e.isDirectory and e.isDirectory(az)then if not ay then
ax("Already exists: "..E,d.warning)end;return false end;local aB,aC=e.makeDirectory(az)if aB then
ax("Created: "..E,d.highlight)return true end
ax(tostring(aC or"Could not create "..E),d.error)return false end
b.mkdir=function(ax,E)local az="Usage: mkdir [-p] <dir...>"
local aA,aB=K.getopt(ax,{["-p"]="parents",["--parents"]="parents"},E,d,az)if not aA then return end;if not aB[1]then E(az,d.dim)return end;local ay=false;for aD,aC in
ipairs(aB)do ay=D(aC,aA.parents,E)or ay end;if ay then
k()end end
local function F(E,ax)local ay=f(E)if e.isDirectory(ay)then
ax("Is a directory: "..E,d.dim)return false end
if not o(ay,ax)then return false end
if not e.exists(ay)then local az,aA=e.writeFile(ay,"")if not az then
ax(tostring(aA or
"Could not create "..E),d.error)return false end end;ax("Touched: "..E,d.highlight)return true end
b.touch=function(E,ax)
if not E[1]then ax("Usage: touch <file...>",d.dim)return end;local ay=false;for aA,az in ipairs(E)do ay=F(az,ax)or ay end
if ay then k()end end
local function x(E,ax)
local ay,az=K.getopt(E,{["-k"]="keep",["--keep"]="keep"},ax,d)if not ay then return nil end;return ay.keep,az end
b.compress=function(ax,E)local aH,ay=x(ax,E)if not ay then return end;if not ay[1]then
E("Usage: compress <file> [out]   (-k keeps original)",d.dim)return end
local aC=h.getCompress and h.getCompress()if not aC or not aC.available()then
E("Compression needs a data card (none detected).",d.error)return end;local az=f(ay[1])if not
l(az,E)then return end;if not e.exists(az)or
(e.isDirectory and e.isDirectory(az))then
E("Not a file: "..ay[1],d.error)return end
local aE=e.readFile(az)if not aE then E("Read failed",d.error)return end;local aB=ay[2]and
f(ay[2])or(az..".tcz")
if not o(aB,E)then return end;local aF,aG,aA,aD=aC.pack(aE)
if not aF then E("Compress failed",d.error)return end
if not e.writeFile(aB,aF)then E("Write failed",d.error)return end;if not aH and aB~=az then pcall(e.remove,az)end;k()
local aI=
(aA>0)and math.floor((aA-aD)*100/aA)or 0
local aJ=aD<aA and(aI.."% smaller")or"no smaller"
E(string.format("%s -> %s  (%s: %s -> %s)",ay[1],(aB:gsub("^.*/","")),aJ,m(aA),m(aD)),
aG=="deflate"and d.highlight or d.warning)if aG=="stored"then
E("(stored uncompressed — data didn't shrink)",d.dim)end end
b.decompress=function(ax,E)local aE,ay=x(ax,E)if not ay then return end;if not ay[1]then
E("Usage: decompress <file.tcz> [out]   (-k keeps original)",d.dim)return end;local az=f(ay[1])if
not l(az,E)then return end
if not e.exists(az)then E(W..ay[1],d.error)return end;local aB=e.readFile(az)
if not aB then E("Read failed",d.error)return end;local aC=h.getCompress and h.getCompress()if not aC then
E("Compression module unavailable",d.error)return end
if not aC.isPacked(aB)then E("Not a .tcz container: "..
ay[1],d.error)return end;local aD,aF=aC.unpack(aB)if not aD then
E("Decompress failed: "..tostring(aF),d.error)return end;local aA
if ay[2]then aA=f(ay[2])elseif
az:sub(-4)==".tcz"then aA=az:sub(1,-5)else aA=az..".out"end;if not o(aA,E)then return end;if not e.writeFile(aA,aD)then
E("Write failed",d.error)return end;if not aE and aA~=az then
pcall(e.remove,az)end;k()
E(string.format("%s -> %s  (%s restored)",ay[1],(aA:gsub("^.*/","")),m(
#aD)),d.highlight)end
local function G(ax,ay,az,E)local aA=f(ax)
if aA=="/"then E("Cannot remove root",d.error)return end;local aB=_G._TOS and _G._TOS.securefs
if aB and
type(aB.removeRefusal)==am then
local aF=aB.removeRefusal(aA,K.sessionOf(a))if aF then E(tostring(aF),d.error)return end end
local aD={"^/$","^/init%.lua$","^/bios%.lua$","^/tos$","^/tos/","^/etc$","^/etc/","^/boot$","^/boot/"}
for aG,aF in ipairs(aD)do
if aA:match(aF)and not ay then
E("Refusing to remove a system path without -r: "..aA..
"  [E-303 ERR_RM_SYSTEM_PATH]",d.error)
E("Protection is off, so this would really delete it. Add -r to confirm.",d.dim)return end end;if not o(aA,E)then return end;if e.exists and not e.exists(aA)then
E(W..ax,d.error)return end
if
e.isDirectory and e.isDirectory(aA)then if not ay then
E("Cannot remove directory without -r: "..aA.."  [E-302 ERR_NEEDS_RECURSIVE]",d.error)return end
local aF=e.list and e.list(aA)if aF and#aF>0 then
E("Removing "..#aF.." item(s) under "..aA.."...",d.dim)end end;local aC=false
local aE=aA:match("^/tos")or aA:match("^/etc")or
aA:match("^/var")or aA:match("^/usr")
if not az and not aE then local aG,aF=pcall(require,"kernel.trash")
if
aG and aF and aF.put then local aH=K.sessionOf(a)local aI,aJ=aF.put(aA,aH)
if aI then aC=true
E("Trashed: "..ax..

" (use 'trash restore ".. (ax:match(X)or ax).."' to undo)",d.highlight)else local aK=tostring(aJ or"unknown reason")
if
aK:find("no trash",1,true)then
E("No trash for this session — deleting "..ax.." outright.",d.warning)else
E("Not trashed: "..aK.."  [E-304 ERR_TRASH_REFUSED]",d.error)
E("It is still there. Delete it for good with:  rm "..
(ay and"-r "or"").."--hard "..ax,d.dim)return end end end end
if not aC then local aF,aG=e.remove(aA)if aF then k()
E("Removed: "..ax,d.highlight)else
E(tostring(aG or"Could not remove "..ax),d.error)end else k()end end
b.rm=function(ax,E)local az="Usage: rm [-r] [--hard] <path...>"
local ay,aA=K.getopt(ax,{["-r"]=ao,["-rf"]=ao,["-R"]=ao,["--hard"]="hard",["-H"]="hard"},E,d,az)if not ay then return end
local aB,aC=ay.recursive or false,ay.hard or false;if#aA==0 then E(az,d.dim)return end
for aE,aD in ipairs(aA)do G(aD,aB,aC,E)end end
b.trash=function(ax,E)local aB,ay=pcall(require,"kernel.trash")if not aB or not ay then
E("Trash unavailable",d.error)return end;local az=ax[1]or"list"
local aA=K.sessionOf(a)
if az=="list"or az=="ls"then local aD=ay.list(aA)if#aD==0 then
E("Trash is empty.",d.dim)return end
E(string.format(" %-20s %-8s %s","name","size","origin"),d.title)for aF,aE in ipairs(aD)do
E(string.format(" %-20s %-8d %s",aE.name:sub(1,20),aE.size,aE.origin),d.fg)end;local aC=ay.usage(aA)if
aC then
E(string.format(" %d/%d items, %d/%d bytes used",aC.count,aC.max_count,aC.bytes,aC.max_bytes),d.dim)end elseif az=="empty"then
local aD,aC=ay.empty(aA)if aD then
E("Emptied "..
tostring(aC).. (aC==1 and" item."or" items."),d.highlight)else
E(tostring(aC or"empty failed"),d.error)end elseif
az=="restore"then if not ax[2]then
E("Usage: trash restore <name> [dest] [--force]",d.dim)return end;local aC,aD=false,nil;for aG=3,#ax do
if
ax[aG]=="--force"or ax[aG]=="-f"then aC=true else aD=ax[aG]end end
local aF,aE=ay.restore(ax[2],{session=aA,dest=aD,force=aC})if aF then k()
E("Restored to "..tostring(aE),d.highlight)else
E(tostring(aE or"restore failed"),d.error)end else
E("Usage: trash [list|empty|restore <name> [dest] [--force]]",d.dim)end end
b.vault=function(ax,E)local aF,az=K.requireRoomy(a,"kernel.vault","core")
if
not aF or not az then E(K.loadFailure("vault",az),d.error)return end;local ay=ax[1]local aD=K.sessionOf(a)
local aA=_G._TOS and _G._TOS.securefs
local function aB(aG)if aA and aA.readFile then return aA.readFile(aG,aD)end;return
nil,"securefs unavailable (refusing unchecked read)"end
local function aE(aG,aH)
if aA and aA.writeFile then return aA.writeFile(aG,aH,aD)end;return false,"securefs unavailable (refusing unchecked write)"end
local function aC(aG,aH)
if aG~=nil and aG~="-"then
E("Note: a typed passphrase stays in this seat's command history;",d.dim)
E("leave it off, or use -, to be asked for it instead.",d.dim)return aG end;if not j then
E("Cannot ask for a passphrase here: give it as the last argument.",d.error)return nil end
local aI=j("Passphrase: ",256,true)if not aI or aI==""then E(ae,d.dim)return nil end
if aH then
local aJ=j("Again, to confirm: ",256,true)if aJ~=aI then
E(aJ and"The two did not match; nothing was changed."or ae,d.error)return nil end end;return aI end
if ay==L or ay==al then local aJ,aL=ax[2],ax[3]if not aJ or not aL then
E("Usage: vault "..ay..
" <src> <dst> [passphrase | -]",d.dim)return end;local aG=aB(f(aJ))if not aG then E(N..
aJ,d.error)return end;if ay==al and
not az.isEncrypted(aG)then
E("Source is not a TOS vault blob.",d.warning)return end
local aK=aC(ax[4],ay==L)if not aK then return end;local aH,aI;if ay==L then aH,aI=az.encrypt(aG,aK)else
aH,aI=az.decrypt(aG,aK)end;if not aH then
E("Failed: "..tostring(aI),d.error)return end;local aM,aN=aE(f(aL),aH)if not aM then
E(aj..tostring(aN),d.error)return end
E(string.format("%s %d -> %d bytes (algo=%s)",ay==L and"Encrypted"or
"Decrypted",#aG,#aH,tostring(aI.algo)),d.highlight)elseif ay=="encrypt-in-place"or ay=="decrypt-in-place"then
local aJ=ax[2]if not aJ then
E("Usage: vault "..ay.." <file> [passphrase | -]",d.dim)return end;local aM=f(aJ)local aG=aB(aM)if not aG then
E(N..aJ,d.error)return end;local aI=ay:sub(1,7)==L
if
aI and az.isEncrypted(aG)then
E("Already encrypted — refusing to double-encrypt.",d.warning)return elseif not aI and not az.isEncrypted(aG)then
E("Not a vault blob — nothing to decrypt.",d.warning)return end;local aK=aC(ax[3],aI)if not aK then return end;local aH,aL;if aI then
aH,aL=az.encrypt(aG,aK)else aH,aL=az.decrypt(aG,aK)end
if not aH then E("Failed: "..
tostring(aL),d.error)return end;local aN,aO=aE(aM,aH)if not aN then E(aj..tostring(aO),d.error)
return end
E(string.format("%s in place: %d -> %d bytes",
ay:sub(1,7)==L and"Encrypted"or"Decrypted",#aG,#aH),d.highlight)elseif ay=="info"then local aG=ax[2]if not aG then
E("Usage: vault info <file>",d.dim)return end;local aH=aB(f(aG))if not aH then
E(N..aG,d.error)return end;if not az.isEncrypted(aH)then
E("Not a vault blob (no TVAULT1 magic).",d.warning)return end
E(string.format(" file:     %s",aG),d.title)
E(string.format(" size:     %d bytes",#aH),d.fg)local aI=#az.MAGIC+1
local aJ=aH:sub(aI,aI+3):gsub("\0+$","")
E(string.format(" algo:     %s",aJ),d.fg)
E(string.format(" ctLen:    encrypted body inside this blob"),d.dim)
E(" (decrypt with the right passphrase to access contents)",d.dim)elseif ay=="tape"then local aG=ax[2]if aG~=L and aG~=al then
E("Usage: vault tape encrypt|decrypt [passphrase | -]",d.dim)return end;local aH=b.tape;if not aH then
E("Tape module not installed (run `pkg install tape`).",d.warning)return end
local aI=aC(ax[3],aG==L)if not aI then return end;aH({aG,aI},E)else
E("Usage: vault [encrypt|decrypt|encrypt-in-place|decrypt-in-place|info|tape] ...",d.dim)
E("  vault encrypt <src> <dst> [passphrase]",d.dim)
E("  vault decrypt <src> <dst> [passphrase]",d.dim)
E("  vault encrypt-in-place <file> [passphrase]",d.dim)
E("  vault decrypt-in-place <file> [passphrase]",d.dim)E("  vault info <file>",d.dim)
E("  vault tape encrypt|decrypt [passphrase]",d.dim)
E("  Leave the passphrase off (or use -) to be asked for it, unechoed:",d.dim)
E("  a typed one stays in this seat's command history.",d.dim)end end
b.keychain=function(ax,E)local ay=_G._TOS and _G._TOS.keychain;if not ay then
E("keychain module unavailable",d.error)return end;local az=K.sessionOf(a)
local aA=ax[1]or"status"
if aA=="status"then
E(ay.isUnlocked(az)and"unlocked"or"locked",d.fg)elseif aA=="unlock"then if not j then
E("interactive prompt unavailable",d.error)return end
local aB=j("Master password: ",64,"*")or""
if#aB==0 then E("(empty — cancelled)",d.dim)return end;local aC,aD=ay.unlock(aB,az)if aC then
E("Keychain unlocked.",d.highlight)else
E("Unlock failed: "..tostring(aD),d.error)end elseif aA=="lock"then ay.lock(az)
E("Keychain locked.",d.highlight)elseif aA=="list"then
if not ay.isUnlocked(az)then E(af,d.warning)return end;local aB=ay.list(az)
if#aB==0 then E("(empty)",d.dim)return end;for aD,aC in ipairs(aB)do E("  "..aC,d.fg)end elseif aA=="set"then if not ax[2]then
E("Usage: keychain set <name>",d.dim)return end;if not ay.isUnlocked(az)then
E("Keychain is locked. Run 'keychain unlock' first.",d.warning)return end;if not j then
E("interactive prompt unavailable",d.error)return end;local aB=
j("Passphrase for '"..ax[2].."': ",256,"*")or""if#aB==0 then
E("(empty — cancelled)",d.dim)return end;local aC,aD=ay.set(ax[2],aB,az)if aC then
E("Slot '"..
ax[2].."' saved.",d.highlight)else
E("Save failed: "..tostring(aD),d.error)end elseif aA=="get"then if not ax[2]then
E("Usage: keychain get <name>",d.dim)return end;if not ay.isUnlocked(az)then
E(af,d.warning)return end;local aB,aC=ay.get(ax[2],az)if aB then
E(aB,d.fg)else
E(tostring(aC or"no such slot"),d.error)end elseif aA=="remove"or aA=="rm"then if not ax[2]then
E("Usage: keychain remove <name>",d.dim)return end;if not ay.isUnlocked(az)then
E(af,d.warning)return end;local aB,aC=ay.remove(ax[2],az)
if aB then E("Removed '"..
ax[2].."'.",d.highlight)else E(
"Remove failed: "..tostring(aC),d.error)end else
E("Usage: keychain [status|unlock|lock|list|set|get|remove] ...",d.dim)end end
b.profile=function(ax,E)local az=_G._TOS and _G._TOS.profile;if not az then
E(an,d.error)return end;local ay=K.sessionOf(a)local aA=ax[1]or"show"
if aA==
"show"then local aB,aD=az.load(ay)
E(string.format(" name:    %s",aB.name),d.title)
E(string.format(" theme:   %s",aB.theme or"(unset — uses `theme set` choice or default)"),d.fg)
E(string.format(" cwd:     %s",aB.cwd or"(unset)"),d.fg)
E(string.format(" prompt:  %s",aB.prompt or"(default)"),d.fg)local aC=0;for aE in pairs(aB.env)do aC=aC+1 end
E(string.format(" env:     %d entries",aC),d.fg)
E(string.format(" startup: %d commands",#aB.startup),d.fg)if not aD then
E(" (no profile file — showing defaults)",d.dim)end elseif aA=="set"then
if not ax[2]or not ax[3]then
E("Usage: profile set <field> <value>",d.dim)E("  fields: name, theme, cwd, prompt",d.dim)return end;local aB,aC=ax[2],ax[3]local aD=az.load(ay)
if aB=="name"or aB=="theme"or
aB=="cwd"or aB=="prompt"then
if aB=="theme"then local aG=_G._TOS and
_G._TOS.theme
if
aG and aG.preset and not aG.preset(aC)then E("Unknown theme preset: "..aC,d.error)if aG.list then
E(
"Available: "..table.concat(aG.list(),", "),d.dim)end;return end end;aD[aB]=aC;local aE,aF=az.save(aD,ay)
if aE then
E("Profile updated. Re-login to apply.",d.highlight)else E(tostring(aF or aq),d.error)end else E("Unknown field: "..aB,d.error)end elseif aA=="env"then if not ax[2]then
E("Usage: profile env <KEY> [VALUE]",d.dim)return end;local aB=az.load(ay)if ax[3]then
aB.env[ax[2]]=ax[3]E("env["..ax[2].."] set",d.highlight)else aB.env[ax[2]]=
nil
E("env["..ax[2].."] cleared",d.highlight)end
az.save(aB,ay)elseif aA=="startup"then local aC=ax[2]or"list"local aB=az.load(ay)
if aC=="add"then
local aD=table.concat(ax," ",3)
if#aD==0 then E("Usage: profile startup add <cmd>",d.dim)return end;aB.startup[#aB.startup+1]=aD;az.save(aB,ay)
E("Added.",d.highlight)elseif aC=="clear"then aB.startup={}az.save(aB,ay)
E("Startup commands cleared.",d.highlight)else for aD,aE in ipairs(aB.startup)do
E(string.format(" %d. %s",aD,aE),d.fg)end;if#aB.startup==0 then
E("(no startup commands)",d.dim)end end elseif aA=="reset"then local aB=_G._TOS and _G._TOS.securefs;if
aB and ay and ay.home and ay.home~="/"then
aB.remove(ay.home.."/.profile.cfg",ay)end
E("Profile reset to defaults.",d.highlight)else
E("Usage: profile [show|set|env|startup|reset]",d.dim)end end
b.cp=function(E,ax)
local aA,aB=K.getopt(E,{["-r"]="r",["-R"]="r"},ax,d,"Usage: cp <src> <dst>")if not aA then return end;E=aB;if not E[2]then
ax("Usage: cp <src> <dst>",d.dim)return end;local az,ay=f(E[1]),f(E[2])
if
e.isDirectory(ay)then ay=e.join(ay,az:match(X)or az)end;local aC,aD=e.copy(az,ay)
if aC then k()
ax("Copied: "..E[2],d.highlight)else ax(aD or"Failed",d.error)end end
b.mv=function(ax,E)
if not ax[2]then E("Usage: mv <src> <dst>",d.dim)return end;local ay,az=f(ax[1]),f(ax[2])if not e.exists(ay)then
E(W..ax[1],d.error)return end;if e.isDirectory(az)then
az=e.join(az,ay:match(X)or ay)end;local aA=az:match(ak)if aA and aA~=""and not
e.isDirectory(aA)then
E("No such directory: "..aA,d.error)return end
if not o(ay,E)then return end;if not o(az,E)then return end
if e.rename(ay,az)then k()
E("Moved: "..ax[2],d.highlight)else local aB,aC=e.copy(ay,az)if aB and e.remove(ay)then k()
E("Moved: "..ax[2],d.highlight)else
E("Move failed: "..tostring(aC or"cross-fs copy failed"),d.error)end end end
b.find=function(E,ax)local aC="/"local ay=nil;local az={}local aA=1;while aA<=#E do
if E[aA]=="-name"and E[aA+1]then
ay=E[aA+1]aA=aA+2 else az[#az+1]=E[aA]aA=aA+1 end end
if az[2]then aC=f(az[1])ay=ay or
az[2]elseif az[1]then if ay or e.isDirectory(f(az[1]))then aC=f(az[1])else
ay=az[1]end end
local aF=ay and ay:find("[%*%?]")and not ay:find("%",1,true)
if aF then local aJ=ay:gsub("[%^%$%(%)%.%[%]%+%-]","%%%0")ay="^"..
(aJ:gsub("%*",".*"):gsub("%?",".")).."$"end
if ay then local aJ,aK=pcall(string.match,"",ay)if not aJ then
ax("Invalid pattern: "..tostring(aK),d.error)return end end;ax("Searching "..aC.." ...",d.dim)local aH=16
local aD=1000;local aB={}
local function aI(aJ)if not g or not g.canAccessAs then return false end
local aK=K.sessionOf(a)local aL=g.canAccessAs(aK,aJ,"r")return aL end
local function aG(aJ,aK)if aK>aH then return end;if#aB>=aD then return end;if not aI(aJ)then return end
local aN,aL=pcall(e.list,aJ)if not aN or not aL then return end;local aM={}
if type(aL)=="table"then aM=aL elseif
type(aL)==am then for aO in aL do aM[#aM+1]=aO end end
for aP,aO in ipairs(aM)do if#aB>=aD then break end;R()
local aQ=e.join(aJ,(aO:gsub("/$","")))local aS=aO:sub(-1)=="/"local aR=false
if aF then aR=
(aO:gsub("/$","")):match(ay)~=nil elseif ay then
local aT,aU=pcall(string.match,aQ,ay)local aV,aW=pcall(string.match,aO,ay)
aR=(aT and aU)or(aV and aW)else aR=true end;if aR then
aB[#aB+1]={aQ.. (aS and"/"or""),aS and
(d.dir or d.highlight)or d.fg}end;if
aS and not aQ:match("^/tos")then aG(aQ,aK+1)end end end;aG(aC,0)if#aB==0 then ax("No matches found",d.dim)else for aK,aJ in ipairs(aB)do
ax(aJ[1],aJ[2])end end;local aE=#aB..
" result(s)"if#aB>=aD then
aE=aE.." (truncated at "..aD..")"end;ax(aE,d.dim)end
b.grep=function(E,ax)
local az,aB=K.getopt(E,{["-i"]="fold"},ax,d,"Usage: grep [-i] <pattern> <file...>   (-- before a pattern that starts with -)")if not az then return end;local aA=az.fold;E=aB;if not E[2]then
ax("Usage: grep [-i] <pattern> <file...>",d.dim)return end
local aC=aA and E[1]:lower()or E[1]local aD=E[3]~=nil;local ay=0
for aE=2,#E do local aF=f(E[aE])
if l(aF,ax)then local aG=0
local aH=K.eachLine(e,aF,function(aI)aG=aG+1
if(aA and
aI:lower()or aI):find(aC,1,true)then if aD then ax(
E[aE]..":"..aG..": "..aI,d.fg)else
ax(string.format("%4d: %s",aG,aI),d.fg)end;ay=ay+1 end end)if not aH then ax(N..E[aE],d.error)end end end
ax(ay>0 and(ay.." match(es)")or"No matches",d.dim)end
b.wc=function(E,ax)
if not E[1]then ax("Usage: wc <file>",d.dim)return end;local aA=f(E[1])if not l(aA,ax)then return end;local ay,az=0,0
local aB,aC=K.eachLine(e,aA,function(aD)ay=ay+1;for aE in
aD:gmatch("%S+")do az=az+1 end end)if not aB then ax(N..E[1],d.error)return end
ax(string.format(" Lines: %d  Words: %d  Bytes: %d  -- %s",ay,az,aC,E[1]),d.fg)end;b.pwd=function(ax,E)E(a.cwd or"/",d.fg)end
local function y(E,ax)
local az,ay=K.getopt(E,{["-n"]={"n"},number="n"},ax,d)if not az then return false end;local aB,aA=ay[1],tonumber(az.n)or 10
if
ay[2]and tonumber(ay[2])then aA=tonumber(ay[2])end;return aB,aA end
local function z(E,az,ax,ay)if e.exists and not e.exists(az)then ay(W..E,d.error)else
ay("Cannot read "..
E.. (ax and(": "..
tostring(ax))or""),d.error)end end
b.head=function(ax,E)local ay,az=y(ax,E)if ay==false then return end;if not ay then
E("Usage: head [-n N] <file>",d.dim)return end;local aA=f(ay)if not l(aA,E)then return end
local aB=0;if not az or az<1 then return end
local aC,aD=K.eachLine(e,aA,function(aE)E(aE,d.fg)aB=aB+1;if aB>=az then
return false end end)if not aC then z(ay,aA,aD,E)end end
b.tail=function(ax,E)local aA,ay=y(ax,E)if aA==false then return end;if not aA then
E("Usage: tail [-n N] <file>",d.dim)return end;local aB=f(aA)if not l(aB,E)then return end;if
not ay or ay<1 then return end;if ay>1000 then ay=1000 end;local aC,az={},0
local aD,aE=K.eachLine(e,aB,function(aF)az=
az+1;aC[(az-1)%ay+1]=aF end)if not aD then z(aA,aB,aE,E)return end
for aF=math.max(1,az-ay+1),az do E(aC[
(aF-1)%ay+1],d.fg)end end
b.which=function(ax,E)
if not ax[1]then E("Usage: which <name>",d.dim)return end;local ay=ax[1]:lower()local az=false;local aB=K.aliases(a)
if aB[ay]then
E(ay..": alias for '"..
aB[ay].."'",d.highlight)
E("  (expanded before dispatch; the expansion is resolved below)",d.dim)
ay=tostring(K.tokenizeSimple(aB[ay])[1]or ay):lower()az=true end;local aD=require(O)
local aA=aD.entry and aD.entry(ay)or nil
if aA then local aI=aA.tier or 0
E(ay..
": built-in (".. (aA.category or"?")..", needs "..
K.tierName(aI)..")",d.title)if aA.help then E("  "..aA.help,d.fg)end;if
aI>K.liveTier(a)then
E("  You do not have the tier to run it — 'why "..ay.."'.",d.warning)end;az=true end;local aG,aC=pcall(require,Y)
local aE=aG and aC and aC.ownerOfCommand and
aC.ownerOfCommand(ay)or nil
if aE then
E(ay..": package command from '"..aE.."'",aA and d.dim or d.title)
if aA then E("  (shadowed by the built-in above)",d.dim)end;az=true end;local aF,aH=K.resolveProgram(e,ay)
if aF then
E(ay..": "..aF..
(aH=="path"and"  (via PATH)"or""),az and d.dim or
d.title)
if az then E("  (shadowed by the entry above)",d.dim)end;az=true end
if not az then E(ay..": not found",d.error)
E("  Not a built-in, an installed package's command, or a program on",d.dim)
E("  /bin, /usr/bin or /tos/shell. 'help' lists what this box has.",d.dim)end end
local function H(E)local ax=require(O)
if ax.entry and ax.entry(E)then return true end;if K.mayHavePackages()then local az,ay=pcall(require,Y)
if
az and ay and ay.ownerOfCommand and ay.ownerOfCommand(E)then return true end end;return
K.resolveProgram(e,E)~=nil end
b.open=function(ax,E)local ay=require("shell.open")local aD=K.sessionOf(a)
local aB=aD and aD.home;local az=ax[1]
local function aA()
E("Usage: open <file>                    in the program that suits it",d.dim)
E("       open with <file> [program]     every program that could, and why",d.dim)
E("       open set .<ext> <program> [--system]   choose (--system: every user)",d.dim)
E("       open unset .<ext> [--system]   forget the choice",d.dim)
E("       open list                      the choices and what packages declare",d.dim)
E("       open hints on|off              edit's suggestions",d.dim)end;if not az then aA()return end;local function aE(aH)if aH then return ay.SYSTEM_FILE end
return aB and(aB..
"/"..ay.USER_FILE)or nil end
local function aF(aH)
local aI,aJ=pcall(e.exists,aH)return
ay.parseDefaults(aI and aJ and e.readFile(aH)or nil)end
local function aC(aH,aI)
local aJ,aK=e.writeFile(aH,ay.serializeDefaults(aI))if not aJ then
E("Not saved: "..tostring(aK or aH),d.error)end;return aJ end
local function aG(aH,aI)if not a.execOne then
E("open: the executor is unavailable",d.error)return end;local aJ=a.execOne(aH.." "..ay.quote(aI),
nil,true)for aL,aK in ipairs(aJ or{})do
E(aK[1],aK[2])end end
if az=="set"or az=="unset"then local aK=ax[#ax]==V
local aH=(ax[2]or""):gsub("^%.",""):lower()if
aH==""or not aH:match("^[%w]+$")or#aH>8 then aA()return end;if aK and not r(E)then return end
local aI=aE(aK)if not aI then
E("There is no home directory to keep your choice in.",d.error)return end;local aJ=aF(aI)
if az=="set"then local aL=ax[3]and
ax[3]:lower()if not aL or aL==V then aA()return end;if
not H(aL)then
E("'"..
aL.."' is not a command this machine has ('which "..aL.."').",d.error)return end;aJ.ext[aH]=aL;if
aC(aI,aJ)then
E("."..
aH.." files now open in "..aL..
(aK and" for every user."or" for you."),d.highlight)end else aJ.ext[aH]=nil;if
aC(aI,aJ)then
E("."..aH..": back to the ranking.",d.highlight)end end elseif az=="hints"then local aH=aE(false)if not aH or
(ax[2]~="on"and ax[2]~="off")then aA()return end;local aI=aF(aH)aI.hints=(
ax[2]=="on")if aC(aH,aI)then
E("edit's suggestions are "..ax[2]..".",d.highlight)end elseif az=="list"then
local aH=ay.gather(e,aB,nil,"")
local function aI(aK,aJ)local aL={}for aM in pairs(aJ.ext)do aL[#aL+1]=aM end
table.sort(aL)
E(aK.. (#aL==0 and"  (none)"or""),d.title)for aN,aM in ipairs(aL)do
E(string.format("  .%-8s %s",aM,aJ.ext[aM]),d.fg)end end
aI("Your choices (~/"..ay.USER_FILE.."):",aH.user)
aI("This machine's ("..ay.SYSTEM_FILE.."):",aH.system)
E("What installed packages open:"..
(#aH.decls==0 and"  (none)"or""),d.title)
for aK,aJ in ipairs(aH.decls)do local aL={}
for aN in pairs(aJ.exts)do aL[#aL+1]="."..aN end;table.sort(aL)
local aM=aJ.markers and
("when a line starts "..table.concat(aJ.markers," "))or(aJ.as=="native"and"its own format"or
"can open")
E(string.format("  %-8s %s  %s",aJ.cmd,table.concat(aL," "),aM),d.fg)end;if aH.user.hints==false then
E("edit's suggestions are off ('open hints on').",d.dim)end else local aJ=az=="with"
local aK=aJ and ax[2]or az;if not aK then aA()return end;local aH=f(aK)local aM,aN=pcall(e.exists,aH)if not aM or
not aN then E("open: no such file: "..aH,d.error)
return end;if
e.isDirectory and e.isDirectory(aH)then
E("open: "..aH.." is a directory ('cd' into it).",d.error)return end
local aI=ay.rank(aH,ay.gather(e,aB,aH))
if aJ and not ax[3]then if#aI==0 then
E("Nothing here opens "..aH..".",d.warning)return end
E("Programs that could open "..aH..", best first:",d.title)for aP,aO in ipairs(aI)do
E(string.format("  %-8s %3d  %s",aO.cmd,aO.score,aO.why),aP==1 and
d.highlight or d.fg)end
E("'open with "..aK..

" <program>' uses another; 'open set .".. (ay.ext(aH)or"ext").." <program>' makes it yours.",d.dim)return end
local aL=aJ and ax[3]:lower()or(aI[1]and aI[1].cmd)if not aL then
E("Nothing here opens "..aH.." ('open with' lists what could).",d.warning)return end;if not aJ then
E("Opening in "..aL..": "..aI[1].why..
".",d.dim)end;aG(aL,aH)end end
b.alias=function(ax,E)local aA=_G._TOS and _G._TOS.profile;if not aA then E(an,d.error)
return end;local aB=K.sessionOf(a)
if not ax[1]then local aH=aA.load(aB)
local aG={}for aI in pairs(aH.aliases or{})do aG[#aG+1]=aI end
table.sort(aG)if#aG==0 then E("(no aliases)",d.dim)
E("Define one:  alias ll ls -l",d.dim)return end;for aJ,aI in ipairs(aG)do
E(string.format(" %-12s %s",aI,aH.aliases[aI]),d.fg)end;return end;local ay=ax[1]:lower()if not ay:match("^[%w_%-]+$")then E("Bad alias name: "..
ax[1],d.error)
E("Letters, digits, underscore and hyphen only.",d.dim)return end
local az=aA.load(aB)
if not ax[2]then
if az.aliases and az.aliases[ay]then
E(string.format(" %-12s %s",ay,az.aliases[ay]),d.fg)else E(ay..": not aliased",d.dim)end;return end;local aC=table.concat(ax," ",2)
local aD=tostring(K.tokenizeSimple(aC)[1]or""):lower()if aD==ay then E("An alias cannot expand to itself.",d.error)
E("To add default flags, alias to a different name.",d.dim)return end;az.aliases=
az.aliases or{}az.aliases[ay]=aC;local aE,aF=aA.save(az,aB)
if
not aE then E(tostring(aF or aq),d.error)return end;K.invalidateAliases(a)
E("alias "..ay.." -> "..aC,d.highlight)end
b.unalias=function(ax,E)local aA=_G._TOS and _G._TOS.profile;if not aA then
E(an,d.error)return end;if not ax[1]then
E("Usage: unalias <name>",d.dim)return end;local aB=K.sessionOf(a)
local ay=ax[1]:lower()local az=aA.load(aB)
if not az.aliases or not az.aliases[ay]then E(
ay..": not aliased",d.dim)return end;az.aliases[ay]=nil;local aC,aD=aA.save(az,aB)if not aC then
E(tostring(aD or aq),d.error)return end;K.invalidateAliases(a)E("Removed alias '"..
ay.."'.",d.highlight)end
b.du=function(ax,E)local ay=f(ax[1]or(a.cwd or"/"))
if not l(ay,E)then return end;if not e.exists(ay)then
E("No such file or directory: "..tostring(ax[1]),d.error)return end;local function aA(aB,aC)
return aB:sub(-1)=="/"and
(aB..aC)or(aB.."/"..aC)end
local function az(aB)
if e.isDirectory(aB)then
local aC,aD=0,e.list(aB)
if type(aD)=="table"then for aF,aE in ipairs(aD)do R()aC=aC+
az(aA(aB,(aE:gsub("/$",""))))end end;return aC end;return(e.size and e.size(aB))or 0 end
if e.isDirectory(ay)then local aB=e.list(ay)
if type(aB)=="table"then for aD,aC in ipairs(aB)do
local aE=aC:gsub("/$","")
E(string.format(" %8s  %s",m(az(aA(ay,aE))),aE),d.fg)end end end
E(string.format(" %8s  %s (total)",m(az(ay)),ay),d.title)end
b.df=function(ax,E)local aA,ay=pcall(require,"kernel.monitor")
E(string.format(" %-16s %8s %8s %8s  %s","Mount","Total","Used","Free","Use%"),d.title)
E(string.rep("-",math.min(q,56)),d.dim)local az=e.mounts and e.mounts()or{}
if#az==0 then
E("(mount info unavailable)",d.dim)else
for aC,aB in ipairs(az)do local aD=aB.total or 0;local aE=aB.used or 0;local aG=aD-aE
local aF=aD>0 and math.floor(
aE*100/aD)or 0
local aH=(aA and ay.memBar)and ay.memBar(aE,aD,8)or""
local aI=aF<80 and d.fg or(aF<95 and d.warning or d.error)
E(string.format(" %-16s %8s %8s %8s  [%s] %3d%%",(aB.mountPoint or"?"):sub(1,16),m(aD),m(aE),m(aG),aH,aF),aI)end end
if _G._TOS_ROOT_READONLY then E("",d.dim)
E("WARNING: the root filesystem is READ-ONLY.",d.error)
E("Nothing TOS writes will survive a reboot — users, logs, packages,",d.dim)
E("settings. Install to a writable drive, or unprotect this one.",d.dim)end
E("A path's own size: 'du <path>'.  Removable media + pools: 'disk'.",d.dim)end
b.mem=function(ax,E)
if ax and ax[1]=="--boot"then
local aK=_G._TOS and _G._TOS.bootMem
if type(aK)~="table"or#aK==0 then
E("This boot was not profiled.",d.warning)
E("Add  memprofile = true  to /etc/boot.cfg and reboot.",d.dim)return end;E("=== Memory each boot stage used ===",d.title)
for aM,aL in
ipairs(aK)do local aN=aK[aM+1]
if aN then
E(string.format(" %-30s %4dK  (%dK free after)",tostring(aL.stage),math.floor((
(aL.free or 0)- (aN.free or 0))/1024),math.floor((
aN.free or 0)/1024)),d.fg)else
E(string.format(" %-30s %5dK free",tostring(aL.stage),math.floor((aL.free or 0)/1024)),d.dim)end end;return end;local aC,ay=P.freeMemory(),P.totalMemory()local aD=ay-aC;local az=ay>0 and math.floor(
aD*100/ay)or 0
local aG,aF=pcall(require,"kernel.monitor")local aB=math.min(24,math.max(8,q-36))
local aH=
(aG and aF.memBar)and aF.memBar(aD,ay,aB)or
(
string.rep("#",math.floor(az/100*aB))..string.rep("-",aB-math.floor(az/100*aB)))E("=== Memory ===",d.title)
E(string.format(" RAM:  %dK used / %dK total   (%d%% used, %dK free)",math.floor(
aD/1024),math.floor(ay/1024),az,math.floor(aC/1024)),d.fg)
local aI=az<75 and d.highlight or(az<90 and d.warning or d.error)E(" ["..aH.."]",aI)
local aJ,aA=pcall(function()
return h.getHAL().systemInfo()end)if aJ and aA and(aA.memTierName or aA.memTier)then
E(
" Tier: ".. (aA.memTierName or("T"..aA.memTier)),d.dim)end
local aE=h.getSwap and h.getSwap()
if aE and aE.usage then local aL,aK=pcall(aE.usage)
if aL and type(aK)=="table"then
E(string.format(" Swap: %dK / %dK on /var/swap   ('slow RAM' overflow)",math.floor((
aK.bytes or 0)/1024),math.floor((aK.max or 0)/1024)),d.dim)end else
E(" Swap: off   (enable in Boot Settings for low-RAM overflow)",d.dim)end;if aC<16*1024 then
E(" ! Low memory — near the ~16K danger zone.",d.warning)end
E("Live usage: 'monitor'.  Hardware tiers: 'hw'.",d.dim)end
b.hw=function(ax,E)local ay=h.getHAL().systemInfo()
E("=== Hardware ===",d.title)
E(string.format(" CPU T%d    GPU T%d    RAM %s",ay.cpuTier or 0,ay.gpuTier or 0,ay.memTierName or("T"..
(ay.memTier or 0))),d.fg)local aA,az=pcall(require,"kernel.datacard")if
aA and az and az.detect then local aB=az.detect()
E(" Data card: "..
(aB.present and aB.name or"none"),aB.present and d.fg or d.dim)end
E(string.format(" Components: %d    Network: %s    Tunnel: %s",
ay.components or 0,ay.canNetwork and"yes"or"no",ay.hasTunnel and"yes"or"no"),d.dim)
E("Full component list: 'devices'.  Memory detail: 'mem'.  Live: 'monitor'.",d.dim)end;b.hardware=b.hw
b.ps=function(ax,E)local aB=u.getForeground(a.displayIdx)
local ay=K.sessionOf(a)local az=(ay and ay.tier)or 0
local aC=ay and ay.user or"?"
local aA=(ax[1]=="-v"or ax[1]=="--verbose")and az>=2
if aA then
E(string.format(" %-4s %-14s %-8s %-3s %-10s %-6s %s","PID","Name","State","DSP","Owner","CPU","Caps"),d.title)else
E(string.format(" %-4s %-16s %-8s %-3s %-10s %s","PID","Name","State","DSP","Owner","CPU"),d.title)end
E(string.rep("-",aA and 70 or 50),d.border)
for aE,aD in ipairs(u.list())do local aF=aD.user or"?"
if aF=="_kernel_"then aF="kernel"end;local aG=false
if az>=2 then aG=true elseif az>=1 and aF==aC then aG=true elseif az>=1 then aG="redacted"end
if aG==true then local aI=d.fg;local aH=aD.state;if aD.tsr then aH="TSR"end;if aD.pid==aB then
aI=d.highlight;aH=aH.." *"elseif aD.tsr then aI=d.dim end
if aA then local aJ={}if
aD.caps then for aK in pairs(aD.caps)do aJ[#aJ+1]=aK end
table.sort(aJ)end
E(string.format(" %-4d %-14s %-8s %-3s %-10s %-6.1f %s",aD.pid,aD.name:sub(1,14),aH,tostring(
aD.display or"-"),(aF):sub(1,10),aD.cpuTime or 0,#aJ>0 and
table.concat(aJ,",")or"-"),aI)else
E(string.format(" %-4d %-16s %-8s %-3s %-10s %.1fs",aD.pid,aD.name:sub(1,16),aH,tostring(aD.display or"-"),(aF):sub(1,10),
aD.cpuTime or 0),aI)end elseif aG=="redacted"then
E(string.format(" %-4d %-16s %-8s %-3s %-10s   ",aD.pid,"(other user)","?","?","?"),d.dim)end end;E("",d.dim)
E(" * = foreground  |  -v for caps (admin+)  |  'monitor' for the live view",d.dim)end
b.monitor=function(ax,E)if K.needsTabs(a,E,"monitor")then E("The processes now:",d.dim)
b.ps({},E)return end
local az,ay=pcall(require,"shell.panels.monitorapp")if not az then
E("Monitor unavailable: "..tostring(ay),d.error)return end;ay.open(a)end;b.top=b.monitor
b.watch=function(ax,E)
if not ax[1]then
E("Usage: watch [seconds] <command ...>",d.dim)
E("  Opens a self-updating tab. e.g.  watch ps  ·  watch 2 df  ·  watch mem",d.dim)return end;local aA,ay=1,tonumber(ax[1])if ay then aA=2 else ay=1 end;if ay<1 then ay=1 end;if not
ax[aA]then E("Usage: watch [seconds] <command ...>",d.dim)
return end
local aB=table.concat(ax," ",aA)
local az=(aB:match("^(%S+)")or""):lower()
local aC={edit=true,lua=true,monitor=true,top=true,watch=true,launcher=true,launch=true,apps=true,kiosk=true,chat=true,more=true,man=true,vault=true,keychain=true,passwd=true,tutorial=true,bootsettings=true,useradd=true,["tape-auth"]=true}if aC[az]then
E("Can't watch '"..az.."' — it's interactive/screen-driven.",d.error)return end;do
local aE,aF,aG=K.tierRefusal(a,az)
if aE then E(aE,d.error)a.lastDenial={cmd=az,need=aF,have=aG}return end end;if not c.openLiveTab then
E("Live tabs aren't available in this shell.",d.error)return end
local function aD()local aE={}local aF={}for aN in
aB:gmatch("%S+")do aF[#aF+1]=aN end;if#aF==0 then return aE end
local aG=aF[1]:lower()local aI={}for aN=2,#aF do aI[#aI+1]=aF[aN]end
local aJ=K.tierRefusal(a,aG)if aJ then aE[#aE+1]={aJ,d.error}return aE end;local aH=b[aG]
if
not aH then local aO,aN=pcall(require,Y)if aO and aN and aN.getCommand then
aH=aN.getCommand(aG)end end;if not aH then
aE[#aE+1]={"Unknown command: "..aG.."  [E-801 ERR_UNKNOWN_CMD]",d.error}return aE end
local aK=function(aN,aO)aE[#aE+1]={tostring(aN),
aO or d.fg}end;local aL,aM=pcall(aH,aI,aK)if not aL then
aE[#aE+1]={"Error: "..tostring(aM),d.error}end;return aE end;c.openLiveTab("watch: "..aB,aD,ay)end
b.why=function(ax,E)local aE=require(O)local aA=K.liveTier(a)
local ay={title=d.title or d.highlight or d.fg,ok=
d.success or d.highlight or d.fg,err=d.error,fix=d.highlight or d.fg,dim=d.dim}local function az(aF)
for aH,aG in ipairs(aF)do E(aG.text,ay[aG.tone]or d.fg)end end
local aB=ax and ax[1]and ax[1]:lower()
if not aB then local aF=a.lastDenial
if aF and aF.cmd then
az(K.whyExplain(aF.cmd,aF.need,aF.have or aA,true))return elseif aF then
E("Your last blocked action needed "..K.tierName(aF.need).."; you are "..
K.tierName(aF.have or aA)..".",d.error)
E("Fix: run it on an admin/root account, or have an admin grant access.",ay.fix)return end;local aG=a.lastFailure
if aG then
E((aG.cmd and(aG.cmd.." failed:")or
"The last action failed:"),ay.title)E("  "..aG.text,d.error)
local aH,aJ,aI=K.explainFailure(aG.text)if aI then E("  "..aI,ay.dim)end
if aH then az(aH)else
E("No canned explanation for that one.",d.dim)
E("`log` has the kernel's own record of it, and `doctor` checks",d.dim)
E("memory, disks, services and security for a cause.",d.dim)end;return end
E("Nothing has failed since the last command ran.",d.dim)
E("why            — explain the last refusal or error.",d.dim)
E("why <code>     — explain an error code: E-402, ERR_PATH_PROTECTED, K4.",d.dim)
E("why <command>  — explain what a command needs and whether you can run it.",d.dim)return end;local aD=K.explainCode(ax[1])if aD then az(aD)return end
local aC=aE.entry(aB)
az(K.whyExplain(aB,aC and aC.tier or 0,aA,aC~=nil))end
b.screendump=function(ax,E)if not n or not n.dump then
E("Screen capture isn't available on this seat.",d.error)return end
local aF,aA=pcall(n.dump)if not aF or type(aA)~="table"or not aA.lines then
E("Screen capture failed.",d.error)return end
local aC=(ax and ax[1])and
f(ax[1])or
f("screen-"..math.floor(h.uptime())..".txt")
local aG=(K.sessionOf(a)or{}).user or"?"
local aE=string.format("TOS screendump — seat %s · user %s · %dx%d · uptime %ds · read from the %s",tostring(a.displayIdx or"?"),aG,
aA.w or 0,aA.h or 0,math.floor(h.uptime()),tostring(aA.source or"?"))local ay=string.char(10)local az=aE..
ay..string.rep("-",#aE)..ay..
table.concat(aA.lines,ay)..ay
if aA.bg then
az=az..ay..
"--- background colour runs, per row ---"..ay
for aK=1,(aA.h or 0)do local aL=aA.bg[aK]
if aL then local aM={}for aO,aN in ipairs(aL)do
aM[#aM+1]=string.format("%d-%d:%s",aN.from,aN.to,
aN.c and string.format("%06X",aN.c)or"nil")end
az=az..
string.format("row %2d  %s",aK,table.concat(aM,"  "))..ay end end;local aJ=a.T or{}
az=az..
ay..
"theme: bg="..
string.format("%06X",aJ.bg or 0)..
"  statusbar_bg="..string.format("%06X",
aJ.statusbar_bg or 0)..
"  menubar_bg="..string.format("%06X",
aJ.menubar_bg or aJ.bar_bg or 0)..ay end;local aB=function(aJ)
return aJ and string.format("%06X",aJ)or"nil"end;az=az..ay..
"--- cache vs glass ---"..ay
if
aA.disagree and#aA.disagree>0 then
az=az.."THE SHADOW DISAGREES WITH THE SCREEN on "..#aA.disagree..
" row(s)."..ay
for aK,aJ in ipairs(aA.disagree)do
az=az..
string.format("  row %2d col %2d  glass=%s  shadow believes=%s",aJ.row,aJ.col,aB(aJ.glass),aB(aJ.shadow))..ay;local aL=aA.pageBg and aA.pageBg[aJ.row]
if aL then local aM={}for aK,aN in
ipairs(aL)do
aM[#aM+1]=string.format("%d-%d:%s",aN.from,aN.to,aB(aN.c))end
az=az.."    off-screen page holds: "..
table.concat(aM,"  ")..ay end end elseif aA.shadowBg then
az=az.."none — the shadow matches the glass everywhere."..ay else
az=az.."(no shadow active on this seat)"..ay end;local i=aA.state
if i then
az=az..
ay..
"--- display machinery ---"..
ay..
"  shadow="..
tostring(i.shadow)..
"  colour cache: fg="..

aB(i.lastFg)..
" bg="..
aB(i.lastBg)..
ay..
"  backbuffer="..
tostring(i.backbuffer)..
"  broken="..
tostring(i.backBroken)..

"  frameDepth="..
tostring(i.frameDepth)..
"  pageStale="..
tostring(i.pageStale)..ay..
"  writerGen="..
tostring(i.writerGen)..
"  mine="..tostring(i.myWriterGen).."  lastWriterIsMe="..
tostring(i.lastWriterIsMe)..ay end;local aD=_G._TOS and _G._TOS.fs;if
not(aD and aD.writeFile)then
E("No filesystem available to write the dump.",d.error)return end
local aH,aI=aD.writeFile(aC,az)
if aH then
E("Screen captured -> "..aC.."  (".. (aA.h or 0).." rows)",
d.success or d.fg)
E("Attach it to a bug report, or 'cat' it to read it back.",d.dim)else
E("Could not write "..aC..": "..tostring(aI),d.error)end end
b.crash=function(ax,E)if not r(E)then return end;local ay=_G._TOS and _G._TOS.fs
if not
(ay and ay.list)then E("No filesystem.",d.error)return end
if ax and ax[1]then local aC=ax[1]:find("/")and f(ax[1])or
("/var/crash/"..ax[1])
local aE,aD=pcall(ay.readFile,aC)if not aE or not aD then
E("No such crash report: "..aC,d.error)return end;for aF in
(tostring(aD).."\n"):gmatch("(.-)\n")do E(aF,d.fg)end;return end;local aB,aA=pcall(ay.list,"/var/crash")local az={}if
aB and type(aA)=="table"then
for aD,aC in ipairs(aA)do aC=tostring(aC):gsub("/$","")if
aC~=""and aC~="NEW"then az[#az+1]=aC end end end
if#az==0 then
E("No crash reports — clean so far.",d.dim)
E("(TOS saves one here on a panic or an unrecoverable shell, so you",d.dim)E(" can read it after rebooting.)",d.dim)return end
E("Crash reports in /var/crash:",d.title or d.highlight or d.fg)for aD,aC in ipairs(az)do E("  "..aC,d.fg)end
E("Read one with:  crash <name>",d.dim)end
b.history=function(ax,E)for ay,az in ipairs(a.cmdHistory)do
E(string.format(" %3d  %s",ay,az),d.dim)end;if#a.cmdHistory==0 then
E("(no history)",d.dim)end end
b.uptime=function(ax,E)local ay=h.uptime()local az=math.floor(ay/3600)local aA=math.floor(
(ay%3600)/60)local aB=math.floor(ay%60)
E(string.format("Uptime: %dh %dm %ds (%.1fs total)",az,aA,aB,ay),d.fg)end
b.date=function(ax,E)
local ay=h.getConfig and h.getConfig()or nil
if ax[1]=="tz"or ax[1]==aa or ax[1]=="set"then
local aH=(
ay and ay.get and ay.get(aa))or 0;local aG=tonumber(ax[2])
if not aG then
E("Timezone offset: "..aH.."h",d.fg)
E("Usage: date tz <hours>   e.g. 'date tz -5'",d.dim)
E("OpenComputers has no settable clock; this only shifts the",d.dim)
E("DISPLAYED time relative to the world/host clock.",d.dim)return end;if aG<-23 or aG>23 then
E("Offset must be between -23 and 23.",d.error)return end;if not r(E)then return end
if not
(ay and ay.set)then E("No writable config available.",d.error)return end;ay.set(aa,aG)if ay.save then ay.save()end
E("Timezone offset set to "..aG.."h. (was "..
aH.."h)",d.highlight)return end;local aB=ax[1]or"%Y-%m-%d %H:%M:%S"local aC=
(ay and ay.get and ay.get(aa))or 0
local az=_G._TOS and _G._TOS.fs;local aD=az and az.hostTime and az.hostTime()local aE=(aD or
os.time())+ (aC*3600)
local aF,aA=pcall(os.date,aB,aE)if aF and aA then E(tostring(aA),d.fg)else
E(tostring(aA or"date error"),d.error)end end;b.time=b.date
b.keys=function(ax,E)local aG,ay=pcall(require,_)if not aG or not ay then
E("Keybind module unavailable.",d.error)return end
local az=(ax[1]or"list"):lower()local aA=false;for aI=2,#ax do
if ax[aI]==V then aA=true;table.remove(ax,aI)break end end
local aH=(a.who=="root")and"/root"or(
"/home/".. (a.who or""))
local aC=aA and"/etc/keys.cfg"or(aH.."/.keys.cfg")local aE,aB=pcall(require,"kernel.serialize")
local function aF()
if not(aE and aB and
a.F.exists(aC))then return{}end;local aI=a.F.readFile(aC)if not aI then return{}end
local aK,aJ=pcall(aB.decode,aI,{maxBytes=8192})return
(aK and type(aJ)=="table")and aJ or{}end
local function aD(aI)if not(aE and aB)then return false end
local aJ=a.F.writeFile(aC,aB.encode(aI))if aJ then ay.reload()end;return aJ end
if az=="list"or az=="ls"then
E("TOS standard shortcuts:",d.title)local aJ,aI=ay.actions(a.who),14;for aL,aK in ipairs(aJ)do
aI=math.max(aI,#aK.keys)end;for aL,aK in ipairs(aJ)do
E(string.format("  %-9s %-"..aI.."s  %s",aK.action,aK.keys,aK.help),
aK.isDefault and d.fg or d.highlight)end
E("",d.dim)
E("Reserved by the kernel — these cannot be rebound:",d.dim)for aL,aK in ipairs(ay.reserved())do
E(string.format("  %-9s %s",aK.key,aK.help),d.dim)end;E("",d.dim)
E("Change one:  keys set quit F4       (add --system for everyone)",d.dim)E("Undo:        keys reset [action]",d.dim)
E("Every first-party TOS program follows this table.",d.dim)elseif az=="set"then local aI,aL=ax[2],ax[3]
if not(aI and aL)then
E("Usage: keys set <action> <key> [<key>...]",d.dim)
E("  e.g. keys set quit F4      keys set find ^F",d.dim)
E("Key names are written the way you say them: ^Q, F10, Ctrl+S, /",d.dim)return end;if not ay.DEFAULTS[aI]then
E("No such action: "..aI.."  (see 'keys list')",d.error)return end;local aJ={}
for aM=3,#ax do local aN=ax[aM]if not
ay.parse(aN)then
E("Not a key name: '"..aN.."'  (try ^Q, F10, Ctrl+S, /)",d.error)return end
if ay.isReserved(aN)then
E(aN..
" is reserved by the kernel and never reaches a program.",d.error)E("See 'keys list' for the reserved set.",d.dim)return end;aJ[#aJ+1]=aN end;local aK=aF()aK[aI]=aJ
if aD(aK)then
E(aI..
" is now "..table.concat(aJ," ").. (aA and"  (machine-wide)"or
""),d.highlight)else E(ah.. (aA and U or"."),d.error)end elseif az=="reset"then local aI=ax[2]local aJ=aF()
if aI then if not ay.DEFAULTS[aI]then
E("No such action: "..aI,d.error)return end;aJ[aI]=nil;if aD(aJ)then
E(aI.." is back to the default.",d.highlight)else E(ai,d.error)end else if aD({})then
E("All shortcuts back to the defaults.",d.highlight)else E(ai,d.error)end end else
E("keys — TOS's standard keyboard shortcuts",d.title)
E("  keys list                     Show them",d.fg)
E("  keys set <action> <key>...    Rebind one",d.fg)
E("  keys reset [action]           Back to the default",d.fg)
E("Add --system to change them for every user (/etc/keys.cfg, admin).",d.dim)end end
b.menu=function(ax,E)local ay=(ax[1]or"list"):lower()local aA=false
for aI=2,#ax do if
ax[aI]==V then aA=true;table.remove(ax,aI)break end end;local aG=(a.who=="root")and"/root"or
("/home/".. (a.who or""))local az=
aA and"/etc/menu.cfg"or(aG.."/.menu.cfg")
local aH,aE=pcall(require,"kernel.serialize")
if not aH or not aE then E("serialize unavailable",d.error)return end
local function aB()if not a.F.exists(az)then return{}end
local aI=a.F.readFile(az)if not aI then return{}end
local aK,aJ=pcall(aE.decode,aI,{maxBytes=8192})return
(aK and type(aJ)=="table")and aJ or{}end
local function aC(aI)return a.F.writeFile(az,aE.encode(aI))end;local function aD()local aJ,aI=pcall(require,"shell.panels.draw")
if
aJ and aI and aI.buildMenuDefs then a.menuDefs=aI.buildMenuDefs(a)end end
local function aF(aI)if
aI.remove then
return"remove "..tostring(aI.remove)..
(aI.menu==true and" (whole menu)"or"")end;if aI.rename then return
"rename "..
tostring(aI.rename).." -> "..tostring(aI.to)end;if
aI.move then return
"move "..tostring(aI.move).." -> "..tostring(aI.menu)end
if aI.menu and not
aI.cmd then return"new menu "..tostring(aI.menu)end;return
string.format("[%s] %s -> %s",aI.menu or"Tools",aI.add or aI.label or"?",aI.cmd or"?")end
if ay=="list"or ay=="ls"then local aI=aB()
if#aI==0 then
E("No menu edits in "..az..".",d.dim)
E("Add one:  menu add <label> <command...> [in <Menu>]",d.dim)
E("Machine-wide instead of just you:  menu add ... --system",d.dim)return end;E("Menu edits ("..az.."):",d.title)for aJ,aK in ipairs(aI)do
E(string.format("  %d. %s",aJ,aF(aK)),d.fg)end elseif ay=="show"then
local aJ,aI=pcall(require,"shell.panels.draw")if not aJ or not aI or not aI.buildMenuDefs then
E("Menu system unavailable.",d.error)return end
for aL,aK in
ipairs(aI.buildMenuDefs(a))do E(aK.label,d.title)
for aL,aM in ipairs(aK.items)do if aM.sep then E("    ---",d.dim)else
E(string.format("    %-20s %s",aM.label,(
aM.action or""):match("^run:(.+)$")or(aM.action or"")),d.fg)end end end
E("Change it with: menu add|remove|rename|move  (add --system for everyone)",d.dim)elseif ay==ap or ay=="move"then local aJ,aK=ax[2],ax[3]if not(aJ and aK)then
E("Usage: menu "..ay..

" <name> <".. (ay==ap and"new name"or"Menu")..">",d.dim)return end;local aI=aB()
aI[#aI+1]=(
ay==ap)and{rename=aJ,to=aK}or{move=aJ,menu=aK}
if aC(aI)then aD()
E("Saved. "..aF(aI[#aI]),d.highlight)else E(ah.. (aA and U or"."),d.error)end elseif ay=="hide"then local aI=ax[2]if not aI then
E("Usage: menu hide <item or Menu name>",d.dim)
E("Hides a built-in entry. 'menu reset' brings everything back.",d.dim)return end
local aJ=aB()
aJ[#aJ+1]={remove=aI,menu=(ax[3]=="menu")or nil}
if aC(aJ)then aD()E("Hidden: "..aI,d.highlight)else E(ah..
(aA and U or"."),d.error)end elseif ay=="reset"then if aC({})then aD()
E("Menu reset to the built-in bar ("..az.." cleared).",d.highlight)else
E("Reset failed".. (aA and U or"."),d.error)end elseif
ay=="add"then local aJ=ax[2]
if not aJ or not ax[3]then
E("Usage: menu add <label> <command...> [in <Menu>]",d.dim)
E("  e.g. menu add Tetris tetris   |   menu add Disk df in System",d.dim)return end;local aI=table.concat(ax," ",3)
local aK=aI:match("%s+in%s+(%S+)%s*$")if aK then aI=aI:gsub("%s+in%s+%S+%s*$","")end
if
#aJ>24 then E("Label too long (max 24).",d.error)return end;if#aI==0 or#aI>200 then
E("Command empty or too long.",d.error)return end;local aL=aB()
aL[#aL+1]={label=aJ,cmd=aI,menu=aK or"Tools"}
if aC(aL)then aD()
E(string.format("Added '%s' -> %s  (menu: %s)",aJ,aI,aK or"Tools"),d.highlight)else E("Save failed (is your home writable?).",d.error)end elseif ay=="remove"or ay=="rm"or ay=="del"then
local aI=tonumber(ax[2])local aJ=aB()if not aI or not aJ[aI]then
E("Usage: menu remove <#>   (see 'menu list')",d.error)return end
local aK=table.remove(aJ,aI)if aC(aJ)then aD()
E("Removed '".. (aK.label or"?").."'.",d.highlight)else E(ai,d.error)end else
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
b.tree=function(ax,E)local aA=f(ax[1]or a.cwd)
local aD=tonumber(ax[2])or 3;local aB=400;local ay,az=0,false
local function aC(aE,aF,aG)if az then return end;if aG>aD then return end
local aH=e.list(aE)or{}
table.sort(aH,function(aI,aJ)
local aK=e.isDirectory(aE.."/".. (aI:gsub("/$","")))
local aL=e.isDirectory(aE.."/".. (aJ:gsub("/$","")))if aK~=aL then return aK end;return aI<aJ end)
for aI,aJ in ipairs(aH)do if ay>=aB then az=true;return end;local aK=aJ:gsub("/$","")
local aM=aE=="/"and(
"/"..aK)or(aE.."/"..aK)local aL=e.isDirectory(aM)local aN=(aI==#aH)
local aO=aN and"`-- "or"|-- "local aP=aL and d.dir or d.fg;E(aF..
aO..aK.. (aL and"/"or""),aP)ay=ay+1;if aL then
aC(aM,aF.. (aN and"    "or
"|   "),aG+1)end end end;E(aA,d.title)aC(aA,"",1)if az then
E(string.format("(truncated at %d entries; raise the limit or narrow the path)",aB),d.dim)end end
b.whoami=function(ax,E)if g then local ay=g.getSession(i)
E(ay and ay.user or"root",d.fg)else E(a.who,d.fg)end end
b.passwd=function(ax,E)
if not g then E("No user system",d.error)return end;local aA=j("Current password: ",64,true)if not aA then return end
local ay=j("New password: ",64,true)if not ay then return end;local aE=j("Confirm new password: ",64,true)if
aE~=ay then
a.lastOut={"Passwords do not match — unchanged.",d.error}return end;if ay==""then
a.lastOut={"Password cannot be empty.",d.error}return end;local aB=g.getSession(i)local aC=
aB and aB.user or"root"
local aD,az=g.changePassword(aC,aC,aA,ay)
if aD and az then
a.lastOut={"Password changed. "..tostring(az),d.warning}elseif aD then a.lastOut={"Password changed.",d.highlight}else
a.lastOut={tostring(az),d.error}end end
local function I(E,ax,ay)local aC=a.st
local aA=g.registerSession and g.registerSession(E)or nil;local aD,aB=pcall(require,Z)
local az=aD and aB.current and aB.current()local aE=az and az.principal;if aA then a.st=aA end
if az then az.principal=E end;local aF,aG=pcall(ax)a.st=aC;if az then az.principal=aE end;if aA and g.logout then
pcall(g.logout,aA)end;if not aF then
ay("sudo: "..tostring(aG),d.error)end end
local function t()if not a._sudo then return false end;a.st=a._sudo.origSt
local ay,E=pcall(require,Z)local ax=ay and E.current and E.current()if ax then
ax.principal=a._sudo.origPrincipal end;if a._sudo.token and g.logout then
pcall(g.logout,a._sudo.token)end;a._sudo=nil;return true end;a.sudoDrop=t
b.sudo=function(ax,E)
if not g then E("No user system",d.error)return end;local aA=K.sessionOf(a)local ay=ax[1]
if ay=="setup"then if not w(E)then return end;local aG=2;if
ax[2]=="root"then aG=3 elseif ax[2]and ax[2]~="admin"then
E("Usage: sudo setup [admin|root]",d.dim)return end
local aF=j("New elevation password: ",64,true)if not aF or aF==""then E("Aborted.",d.dim)return end
if
j("Confirm: ",64,true)~=aF then E("Passwords do not match.",d.error)return end;local aH,aI=g.setElevation(aA,aF,aG)
if aH then
E("Elevation configured (cap: "..
K.tierName(aG)..").",d.highlight)else E(tostring(aI),d.error)end;return elseif ay=="off"then if not w(E)then return end
local aF,aG=g.clearElevation and g.clearElevation(aA)if aF then E("Elevation disabled.",d.highlight)else
E(tostring(aG or"unavailable"),d.error)end;return elseif ay=="-k"then
E(
t()and"Elevated session dropped."or"No active elevation.",d.dim)return end;if not ay then
E("Usage: sudo <command> | sudo -s | sudo -k | sudo setup [admin|root] | sudo off",d.dim)return end
if
K.liveTier(a)<1 then E("sudo: guests cannot elevate.",d.error)return end
local aC=g.elevationInfo and g.elevationInfo()or{configured=false}if not aC.configured then
E("sudo: elevation is not configured. Root: sudo setup [admin|root]",d.warning)return end
local aB=j("[sudo] elevation password: ",64,true)if aB==nil then E("Aborted.",d.dim)return end
local az,aD=g.elevate(aA,aB)if not az then
E("sudo: "..tostring(aD or"elevation failed"),d.error)return end
if ay=="-s"then t()
local aG=g.registerSession and
g.registerSession(az)or nil;local aI,aH=pcall(require,Z)
local aF=aI and aH.current and aH.current()
a._sudo={origSt=a.st,origPrincipal=aF and aF.principal,token=aG}if aG then a.st=aG end;if aF then aF.principal=az end
E("Elevated to "..
K.tierName(az.tier)..". 'sudo -k' or 'logout' drops it.",d.highlight)return end;local aE=table.concat(ax," ")
I(az,function()if not a.execOne then
E("sudo: executor unavailable",d.error)return end;local aF=a.execOne(aE)if
type(aF)=="table"then
for aH,aG in ipairs(aF)do if type(aG)=="table"then E(aG[1],aG[2]or d.fg)else
E(tostring(aG),d.fg)end end end end,E)end;b.logout=function(E,ax)K.logout(a)end
b.cli=function(ax,E)if a.isCLI then
E("You are already at the command line. Type 'tui' for the full interface.",d.dim)return end;a._exitTo="cli"end
b.tui=function(ax,E)if a.isCLI then E("Returning to the full interface…",d.dim)
a._exitTo="tui"return end
E("You are already in the full interface. Type 'cli' for the command line.",d.dim)end
b.reboot=function(ax,E)local ay,az=K.canPowerOff(a)
if not ay then E(az,d.error)return end;h.reboot()end
b.shutdown=function(ax,E)local ay,az=K.canPowerOff(a)
if not ay then E(az,d.error)return end;h.shutdown()end
b.env=function(E,ax)local aB,ay=pcall(require,"kernel.env")if not aB then
ax("Env module unavailable",d.error)return end;local aA=h.getProc()local az=
aA and aA.current()or nil
if E[1]then
local aC,aD=E[1]:match("^([%w_]+)=(.*)$")if not aC and E[2]and E[1]:match("^[%w_]+$")then
aC,aD=E[1],table.concat(E," ",2)end;if aC then ay.write(az,aC,aD)ax(aC..
"="..aD,d.highlight)else local aE=ay.read(az,E[1])
ax(E[1].."="..tostring(
aE or""),d.fg)end else
local aD,aC=ay.list(az),{}for aE in pairs(aD)do aC[#aC+1]=aE end;table.sort(aC)for aF,aE in
ipairs(aC)do
ax("  "..aE.."="..tostring(aD[aE]),d.fg)end end end;b.export=b.env;b.set=b.env
b["tape-menu"]=function(ax,E)
local aF,az=pcall(require,"shell.launcher")if not aF or not az then
E("Menu engine unavailable (low RAM?)",d.error)return end;if not n or not n.getSize then
E("tape-menu needs a screen.",d.error)return end;local aA=nil
local function aG(aM)local aN={}local aO={}for aW in
aM:gmatch("%S+")do aO[#aO+1]=aW end;if#aO==0 then return aN end
local aP=aO[1]local aR={}for aW=2,#aO do aR[#aR+1]=aO[aW]end
local aS=K.tierRefusal(a,aP:lower())if aS then aN[#aN+1]={aS,d.error}return aN end;if not aA then
aA=require(O).build(a,c)end;local aQ=aA[aP]
if not aQ then local aX,aW=pcall(require,Y)if aX and aW and
aW.getCommand then aQ=aW.getCommand(aP)end end;if not aQ then
aN[#aN+1]={"Unknown command: "..aP,d.error}return aN end;local aT=function(aW,aX)
aN[#aN+1]={tostring(aW),aX or d.fg}end
local aU,aV=pcall(aQ,aR,aT)if not aU then
aN[#aN+1]={"Error: "..tostring(aV),d.error}end;return aN end;local aC=Q.list and Q.list("tape_drive")()
if
not aC then E("No tape drive found.",d.error)return end;local ay=Q.proxy(aC)
local aH,aI=pcall(function()return ay.isReady()end)
if not aH or not aI then E("No tape inserted.",d.warning)return end
local aJ=(ay.getSize and ay.getSize())or 0
if aJ<=0 then E("Tape is empty.",d.warning)return end
local aB=j and j("Tape menu passphrase: ",64,true)or nil;if not aB or aB==""then E(ae,d.dim)return end
local aK,aD=pcall(require,"kernel.vault")
if not aK or not aD then E("vault unavailable",d.error)return end;local aE,aL=az.readTapeMenuFromDrive(ay,aB,aD)if not aE then
E(tostring(aL),d.error)return end
az.run({display=n,profile=aE,runLine=aG,title="Tape toolbox"})if c.drawAll then pcall(c.drawAll)end end
b.clip=function(ax,E)local aB,ay=pcall(require,"kernel.clipboard")if not aB or not ay then
E(
"Clipboard unavailable: "..tostring(ay),d.error)return end;local az=a.displayIdx;local aA=ax[1]
if
not aA then
E("Clipboard: "..ay.describe(az),d.title)local aC=ay.get(az)
if aC and not ay.isEmpty(az)then
local aD=math.min(#aC,10)for aE=1,aD do E("  "..aC[aE],d.fg)end;if#aC>aD then
E("  ... "..
(#aC-aD).." more line(s)",d.dim)end end
E("Usage: clip [set <text> | clear]   Copy: "..
(function()local aE,aD=pcall(require,_)
return(aE and aD)and
aD.label("copy",a.who)or"Ctrl+Insert"end)(),d.dim)return end;if aA=="clear"then ay.clear(az)
E("Clipboard cleared.",d.highlight)return end
if aA=="set"then
local aC=table.concat(ax," ",2)
if aC==""then E("Usage: clip set <text>",d.warning)return end;local aE,aD=ay.set(aC,az)if not aE then
E("Could not set clipboard: "..tostring(aD),d.error)return end;if aD then
E("Clipboard set, TRUNCATED at the cap: "..
ay.describe(az),d.warning)else
E("Clipboard: "..ay.describe(az),d.highlight)end;return end;E("Usage: clip [set <text> | clear]",d.warning)end
b.desktop=function(ax,E)if K.needsTabs(a,E,"desktop")then return end
local az,ay=pcall(require,"shell.panels.desktop")if not az then
E("Desktop unavailable: "..tostring(ay),d.error)return end;ay.open(a)end
b.settings=function(ax,E)if K.needsTabs(a,E,"settings")then return end
local az,ay=pcall(require,"shell.panels.settingsapp")if not az then
E("Settings unavailable: "..tostring(ay),d.error)return end;ay.open(a)end
b.lang=function(ax,E)local aC,ay=pcall(require,"kernel.i18n")if not aC or not ay then
E(
"i18n unavailable: "..tostring(ay),d.error)return end;local az=ax[1]
if not az then
E(ag..ay.language()..
"  ("..ay.languageName()..")",d.title)E("Installed catalogs:",d.fg)for aH,aG in ipairs(ay.available())do
local aI=(aG.code==
ay.language())and" * "or"   "
E(aI..string.format("%-8s %s",aG.code,aG.name),d.fg)end
E("Usage: lang <code> | lang system <code> | lang dump [path]",d.dim)
E("Catalogs are DATA files at /usr/lang/<code>.lang — see 'man lang'.",d.dim)return end
if az=="system"then if not r(E)then return end;local aG=ax[2]if not aG then
E("Usage: lang system <code|en>",d.dim)return end;local aH,aI=ay.setLanguage(aG)
if not aH then E(
"Cannot set: "..tostring(aI),d.error)return end
if p and p.set then p.set("language",aG)if p.save then p.save()end end
E("System language: "..ay.language(),d.highlight)return end
if az=="dump"then
local aH=f(ax[2]or"/tmp/lang-template.lang")local aI=ay.keysSeen()if#aI==0 then
E("No keys seen yet — visit a few screens first (log out/in, open the Desktop).",d.warning)return end
local aG={"-- TOS language catalog template (every t() key seen this session).","-- Translate the values, set meta.code/name, save as /usr/lang/<code>.lang,","-- then run `lang <code>`. Untranslated keys keep their English default.","-- An admin can write there directly, or ship the catalog as a package.","return {",'  meta = { code = "xx", name = "Language name" },',"  strings = {"}for aM,aL in ipairs(aI)do
aG[#aG+1]=string.format("    [%q] = %q,",aL.key,aL.default)end;aG[#aG+1]="  },"
aG[#aG+1]="}"
if not o(aH)then E("Cannot write: "..aH,d.error)return end
local aK,aJ=e.writeFile(aH,table.concat(aG,"\n").."\n")if aK then
E("Template with "..#aI.." key(s) -> "..aH,d.highlight)k()else E(aj..aH,d.error)
if aJ then E(tostring(aJ),d.dim)end end;return end;local aD,aE=ay.setLanguage(az)if not aD then
E("Cannot set '"..tostring(az)..
"': "..tostring(aE),d.error)E("Run 'lang' to list installed catalogs.",d.dim)
return end
local aB=K.sessionOf(a)local aF,aA=pcall(require,"kernel.profile")
if aF and aA and aA.load and
aA.save then local aG=aA.load(aB)
aG.lang=
(ay.language()~="en")and ay.language()or nil;local aH,aI=aA.save(aG,aB)
if aH then
E(ag..
ay.language().."  (saved to your profile)",d.highlight)else
E("Language set for this session (profile save failed: "..tostring(aI)..")",d.warning)end else
E(ag..ay.language().."  (this session)",d.highlight)end end end