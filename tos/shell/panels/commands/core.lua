
local P,U,V,I,K,W,X,J,Y,Z,_,H,aa,ab,ac,ad,ae,Q,af,R,ag,ah,ai="kernel.process","shell.keys","  Examples:","  Subcommands:","shell.panels.commands","function"," %-24s %8s","Cannot read: ","[^/]+$","Cancelled.","decrypt","encrypt","Write failed: ","Keychain is locked.","profile module unavailable","save failed","kernel.pkg","timezone","Save failed"," (needs admin for /etc).","Save failed.","rename","Language: "local L=require("computer")local M=require("component")
local G=require("shell.panels.helpers")local N=function()end
do local b,a=pcall(require,P)if b and a and a.yieldCooperative then
N=a.yieldCooperative end end;local function O()local a,b=pcall(require,"shell.panels.home")
return(a and b)or nil end;local function S(a)local b=O()return
b and b.cycleKeyLabel(a)or"F2"end
local function aj(a)
local b=O()if b and b.enabled(a)then
return b.viewKeyLabel(a).."  Tiles / files "end;return"F2  Next tab      "end
local function T(a)local e=O()local d,b=pcall(require,U)if not(d and b)then
return"Copy Ctrl+Insert  Cut ^X  Paste ^V"end;local c=a and a.who or nil;return
"Copy "..
b.label("copy",c).."  Cut "..
b.label("cut",c).."  Paste "..b.label("paste",c)end
local function ak(a)local b=S(a)return b..
string.rep(" ",math.max(1,12-#b)).."Next tab   "end
return
function(b,a,c)local h,an,u,e,n,g=a.K,a.E,a.P,a.F,a.D,a.U;local p,A,i=a.SC,a.NM,a.st;local d=a.T;local B=a.tier
local q,v=a.W,a.H;local f=c.rp;local r=c.openViewTab;local ao=c.openEditTab;local k=c.refreshBrowser
local l=c.canRead;local o=c.canWrite;local ap=c.canAccess;local w=c.rootOnly;local s=c.adminOnly
local aq=c.makeProgramEnv;local m=G.fmtSz
local ar=function(E)return G.expandBuf(a,E)end;local j=c.promptInput
b.help=function(as,E)
local at=as and as[1]and as[1]:lower()
if at=="cp"or at=="copy"then E("cp <source> <dest>",d.title)
E("  Copy a file. Both paths are required.",d.fg)
E("  Paths starting with / are absolute; others are relative to cwd.",d.fg)E(V,d.dim)
E("    cp notes.txt /home/root/notes_bak.txt",d.dim)E("    cp /etc/cfg.conf /tmp/cfg.conf",d.dim)
E("  Tip: Use F5 in the browser for clipboard-style copy.",d.highlight)elseif at=="mv"then E("mv <source> <dest>",d.title)
E("  Move or rename a file.",d.fg)E(V,d.dim)
E("    mv old.txt new.txt           (rename in cwd)",d.dim)
E("    mv /tmp/work.lua /home/root/ (move to dir)",d.dim)elseif at=="cd"then E("cd [dir]",d.title)
E("  Change directory. With no argument, prints current directory.",d.fg)
E("  Special paths:  ..  (parent)   ~  (home dir)",d.fg)elseif at=="find"then E("find [path] [-name pattern]",d.title)
E("  Recursively search for files. Pattern uses Lua patterns.",d.fg)E(V,d.dim)E("    find /tos -name *.lua",d.dim)
E("    find /home",d.dim)elseif at=="grep"then E("grep <pattern> <file>",d.title)
E("  Search file lines for pattern (plain text, not regex).",d.fg)
E("  Example:  grep function /tos/shell/init.lua",d.dim)elseif at=="flash"then E("flash <file>",d.title)
E("  Write a Lua file to the EEPROM (overwrites BIOS!).",d.fg)
E("  Prompts for confirmation. Use to install a new BIOS.",d.fg)E("  Example:  flash /tos/bios.lua",d.dim)elseif at=="edit"then
E("edit <file>",d.title)
E("  Open file in editor tab. Creates the file if it doesn't exist.",d.fg)
E("  Keys:  Ctrl+S = save   Ctrl+Q = close tab   Ctrl+F = find",d.dim)E("  Ctrl+H = find/replace  Ctrl+Z = undo",d.dim)E(
"  Select: Shift+arrows.  "..T(a),d.dim)
E("  With nothing selected, copy/cut take the whole line.",d.dim)
E("  Use "..S(a).." to switch tabs, F4 to close.",d.dim)elseif at=="run"then E("run <file> [args...]",d.title)
E("  Execute a Lua file in the current environment.",d.fg)
E("  Args are passed as a table in the second argument.",d.fg)elseif at=="tape"then E("tape [subcommand]",d.title)
E("  Data storage on Computronics tapes (requires module).",d.fg)
E("  If the tape package is not installed, shows",d.fg)
E("  instructions for installing it or building your own.",d.fg)E("",d.fg)
E("  Subcommands (when module is active):",d.dim)E("    detect           List tape drives",d.dim)
E("    info             Tape size, label, format",d.dim)E("    label [name]     Get/set tape label",d.dim)
E("    store <path>     Archive file/dir to tape",d.dim)
E("    restore [path]   Restore archive from tape",d.dim)
E("    list             List archived entries",d.dim)
E("    dump [off] [len] Hex dump of tape bytes",d.dim)E("    erase [full]     Quick or full wipe",d.dim)
E("    raw read/write   Low-level byte I/O",d.dim)elseif at=="net"then E("net [subcommand]",d.title)
E("  Network management (requires modem or linked card).",d.fg)E("",d.fg)E(I,d.dim)
E("    status              Show network status",d.dim)
E("    discover / scan     Broadcast ping to find peers",d.dim)
E("    peers / list        List known peers and trust levels",d.dim)
E("    trust <addr> [full] Elevate peer to KNOWN or TRUSTED",d.dim)E("    block <addr>        Block a peer",d.dim)
E("    send <addr> <msg>   Send message to trusted peer",d.dim)E("",d.fg)
E("  Related: ping <addr>, hostname [name], chat",d.dim)elseif

at=="pkg"or at=="mod"or at=="module"or at=="modules"or at=="package"or at=="packages"then E("pkg [subcommand]",d.title)
E("  Package manager — install and manage add-ons. (Replaces the old",d.fg)
E("  'mod'/module manager, retired in v1.3.1.)",d.fg)E("",d.fg)E(I,d.dim)
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
E("  Shortcuts: 'install <name>' and 'uninstall <name>' work too.",d.dim)elseif at=="monitor"or at=="top"then
E("monitor   (alias: top; also opened with Ctrl+T)",d.title)
E("  The live System Monitor — one screen showing what TOS is doing.",d.fg)E("",d.fg)E("  Shows:",d.dim)
E("    · Every process (kernel AND user), each explained, with owner,",d.dim)
E("      state, CPU and seat — auto-refreshing.",d.dim)
E("    · rc.d services and their status (admin).",d.dim)E("    · Memory and uptime vitals.",d.dim)
E("",d.fg)
E("  Runs as a full-screen tab: scrolls, never truncates, per-seat.",d.dim)E("",d.fg)E("  Keys:",d.dim)
E("    up/down move   Enter switch-to   K kill   T suspend/resume (TSR)",d.dim)
E("    Enter start-stop a service (admin)   R refresh   ^Q close",d.dim)elseif at=="cron"then E("cron [subcommand]",d.title)
E("  Manage scheduled tasks.  (admin+)",d.fg)E("",d.fg)E(I,d.dim)
E("    list                Show all cron jobs",d.dim)
E("    add <interval> <cmd> Schedule a command",d.dim)
E("    rm <id>             Remove a cron job",d.dim)elseif at=="service"then E("service [subcommand]",d.title)
E("  Manage startup services.  (admin+)",d.fg)E("",d.fg)E(I,d.dim)
E("    (none)              List all services and status",d.dim)E("    start <name>        Start a service",d.dim)
E("    stop <name>         Stop a service",d.dim)elseif at=="users"or at=="useradd"or at=="userdel"or
at=="usermod"then
E("User Management  (admin/root)",d.title)
E("  users                   List all user accounts",d.fg)
E("  useradd <name>          Create a new user",d.fg)E("  userdel <name>          Delete a user",d.fg)
E("  usermod <user> <action> Modify a user:",d.fg)
E("    lock / unlock         Lock or unlock an account",d.dim)
E("    admin / user          Set role to admin or user",d.dim)
E("  whoami                  Show current user",d.fg)
E("  passwd                  Change your password",d.fg)elseif at=="disk"then E("disk [subcommand]",d.title)
E("  Manage removable disks (floppies, HDDs).",d.fg)E("",d.fg)E(I,d.dim)
E("    list                List removable disks",d.dim)
E("    info <mount>        Show disk contents",d.dim)
E("    install <mount>     Install module from disk (admin)",d.dim)
E("    export <name> <mnt> Write module to disk    (admin)",d.dim)E("    eject <mount>       Unmount a disk",d.dim)elseif at==
"redstone"or at=="rs"then
E("redstone [subcommand]  (alias: rs)",d.title)E("  Control redstone I/O on all sides.",d.fg)
E("",d.fg)E(I,d.dim)
E("    (none)              Show redstone levels",d.dim)
E("    set <side> <level>  Set output (0-15)",d.dim)
E("    pulse <side> [dur]  Pulse output (default 0.5s)",d.dim)elseif at=="robot"then E("robot <command>",d.title)
E("  Control robot/drone movement and interaction.",d.fg)E("",d.fg)
E("  Movement: forward, back, up, down, left, right",d.dim)
E("  Actions:  swing, use, place, suck, drop, detect",d.dim)E("  Info:     name, energy, slot <n>",d.dim)elseif
at=="audio"or at=="sound"or at=="beep"then
E("audio [subcommand]",d.title)
E("  Control audio feedback (beeps and notifications).",d.fg)E("",d.fg)E(I,d.dim)
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
E("    2 descending        Shutdown / logout",d.dim)E("    3 ascending         Boot complete",d.dim)elseif at and
at~=""then local av=require(K)local au=av.entry and av.entry(at)
if au then
local ax={[0]="guest",[1]="user",[2]="admin",[3]="root"}E(at,d.title)
E("  ".. (au.help or"(no description)"),d.fg)E("",d.fg)
E(string.format("  Minimum tier: %s    Group: %s",ax[au.tier or 0]or
tostring(au.tier),au.category or"?"),d.dim)
local aw="  Tip: run '"..at.."' with no args for usage"
if e.exists("/usr/man/"..at..".man")then aw=aw.."; 'man "..
at.."' for the manual."else aw=aw.."."end;E(aw,d.dim)else
E("No such command: '"..at.."'.  Type 'help' for the full list.",d.warning)end else local av=require(K)
local function au(aA)return av.needMet and av.needMet(aA)end
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
E("  F1  Help      "..aj(a)..
"  F3  View file",d.fg)
E("  F4  Close tab F5  Copy file      F6  Move file",d.fg)
E("  "..ak(a).." F9  Menu bar",d.fg)E("  F7  Mkdir     F8  Delete",d.fg)
E("  Text: Shift+arrows select.  "..T(a),d.fg)
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
E("  tutorial      Replay the welcome walkthrough",d.fg)if a.userTier>=1 and au("swap")then
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
E("  cron [list|add|rm]        Scheduled tasks",d.fg)end;local aw,ax=au("component:redstone"),au("component:robot")
local ay,az=au("inventory"),au("module:tape")
if aw or ax or ay or az or a.userTier>=2 then E("",d.fg)
E(" Peripherals",d.highlight)if aw then
E("  redstone [set|pulse] Control redstone I/O  (rs = alias)",d.fg)end;if ax then
E("  robot <cmd>          Robot/drone movement & interaction",d.fg)end;if ay then
E("  inventory [side]     Inspect inventories  (inv = alias)",d.fg)end;if az then
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
b.man=function(as,E)local au="/usr/man"local at=as and as[1]
if not at then
E("Manual pages — usage: man <topic>",d.title)local ax=
(e.isDirectory and e.isDirectory(au)and e.list(au))or{}
if
type(ax)=="table"and#ax>0 then table.sort(ax)
for az,ay in ipairs(ax)do
local aA=(ay:gsub("/$","")):gsub("%.man$","")if aA~=""then E("  "..aA,d.fg)end end else
E("  (no manual pages installed under "..au..")",d.dim)end
E("Depth: help (quick) < man (detailed) < MANUAL.md (the full book)",d.dim)return end;at=tostring(at):gsub("[^%w_%-]","")if at==""then
E("man: invalid topic",d.error)return end;local av=e.join(au,at..".man")if not
e.exists(av)then av=e.join(au,at)end
if not e.exists(av)then E(
"No manual page for '"..at.."'.",d.error)
E(
"Try 'help "..at.."', or open MANUAL.md for the full book.",d.dim)return end;local aw=e.readFile(av)if not aw then
E("man: cannot read page",d.error)return end
if r then local ax={}
for ay in
(aw.."\n"):gmatch("([^\n]*)\n")do local az=d.fg
if ay:match("^[A-Z][A-Z0-9 /%-]+$")then az=d.title elseif ay:match("^%s")then az=d.dim end;ax[#ax+1]={ay,az}end;r(ax,"man "..at)else for ax in(aw.."\n"):gmatch("([^\n]*)\n")do
E(ax,d.fg)end end end
b.about=function(as,E)local at=_G._TOS or{}
local aw,au,ax="Strata Systems LLC",nil,"Terminal Operating System"local ay,av=pcall(require,"kernel.logo")if ay and av then
aw=av.VENDOR or aw;au=av.MOTTO;ax=av.TAGLINE or ax end;E(
"TOS - "..ax,d.title)
E("Version "..
(at.version or"?").."  [".. (at.codename or
"?").."]",d.highlight)
E("Build "..tostring(at.build or"?").." ("..
tostring(at.variant or"?")..")",d.dim)
E("GPU T"..B.." | "..
math.floor(L.totalMemory()/1024).."K RAM",d.dim)E(aw.."   -   GNU GPL v3.0",d.dim)if au and au~=""then E(
'"'..au..'"',d.dim)end;E("",d.fg)
E("A secure, multi-seat terminal OS for OpenComputers:",d.fg)
E("  - Sandboxed processes, role-based users, encrypted homes",d.fg)
E("  - Tabbed file browser + editor, themeable panels UI",d.fg)
E("  - Zero-trust networking: chat, mesh mail, clustering",d.fg)
E("  - Package manager + Optional Utilities add-on disk",d.fg)
E("  - Boot Settings (DEL at POST), swap, backups, OpenOS compat",d.fg)E("",d.fg)
E("'help' lists commands · 'tutorial' walks you through it.",d.dim)end;b.ver=b.about
b.echo=function(E,as)as(table.concat(E," "),d.fg)end
b.notify=function(as,E)local aA,at=pcall(require,"kernel.notify")if not aA or not at then
E("notify unavailable",d.error)return end;local av,aw,au="info",nil,{}local ax
for aC=1,# (as or{})
do local aD=tostring(as[aC])
if aC==ax then elseif aD:sub(1,2)=="--"then
local aF,aE=aD:match("^%-%-([%w%-]+)=?(.*)$")
if aF=="style"or aF=="title"then if aE==""and as[aC+1]and
tostring(as[aC+1]):sub(1,2)~="--"then
aE=tostring(as[aC+1])ax=aC+1 end
if aF=="style"then av=aE else aw=aE end end else au[#au+1]=aD end end;local ay=table.concat(au," ")
if ay==""then
E("Usage: notify <message> [--style info|warn|danger|error] [--title T]",d.title)
E("Puts a modal dialog box in front of every seat — the intrusive",d.dim)
E("counterpart to 'echo', which only writes above the command line.",d.dim)E("",d.dim)
E(string.format("Pending now: %d   (limits: %ds between boxes, %ds per source)",at.depth(),at.MIN_GAP,at.MIN_SOURCE_GAP),d.dim)return end
local az,aB=at.post({message=ay,style=av,title=aw,from="notify/"..tostring(a.who or"?")})
if az then
E("Raised on every seat (dialog #"..az..").",d.highlight)else
E("Not raised: "..tostring(aB),d.warning)
E("The message is in the log either way ('log' to see it).",d.dim)end end
b.tutorial=function(as,E)local au,at=G.requireRoomy(a,"shell.tutorial","core")
if
not au then E(G.loadFailure("tutorial",at),d.error)return end
if as[1]=="--reset"then local aw=
(g and i and g.getSession)and g.getSession(i)or nil;local av=at.markerFor and
at.markerFor(aw)
if av and e.exists(av)then
e.remove(av)
E("Tutorial reset — it will run again at your next login.",d.success or d.fg)elseif av then
E("Tutorial was not marked done for this account.",d.dim)else
E("This account has no home to remember the tutorial in.",d.dim)end end;at.run({D=n,F=e,U=g,st=i,W=q,H=v})c.drawAll()end
b.cls=function(E,as)n.fill(1,1,q,v," ",d.fg,d.bg)c.drawAll()end;b.clear=b.cls
b.cd=function(E,as)if not E[1]then as(a.cwd,d.fg)return end
local at=E[1]
if at==".."then
a.cwd=a.cwd:match("^(.*)/[^/]+/?$")or"/"if a.cwd==""then a.cwd="/"end else local au=f(at):gsub("//+","/")
if
au~="/"and au:sub(-1)=="/"then au=au:sub(1,-2)end;if e.isDirectory(au)then a.cwd=au else
as("Not a directory: "..at,d.error)return end end;a.browser.path=a.cwd;a.browser.sel=1;a.browser.scroll=0
c.loadFiles(a.browser)end
b.ls=function(as,E)local ay,az,av=false,false,nil
for aE,aD in ipairs(as)do
if not av and aD:sub(1,1)=="-"and
#aD>1 then
for aF in aD:sub(2):gmatch(".")do if aF=="l"then ay=true elseif aF=="a"then az=true else
E("Usage: ls [-l|-a] [dir]",d.dim)return end end elseif not av then av=aD end end;local at=f(av or a.cwd)if not l(at,E)then return end;if e.exists and
not e.exists(at)then
E("no such file: ".. (av or at),d.error)return end
local aB,aw=pcall(e.list,at)
if not aB or not aw then E("Cannot list: "..at,d.error)return end;local au,ax={},0;local function aA(aD)
if az or aD:sub(1,1)~="."then au[#au+1]=aD else ax=ax+1 end end
if type(aw)=="table"then for aE,aD in ipairs(aw)do
aA(aD)end elseif type(aw)==W then for aD in aw do aA(aD)end end
table.sort(au,function(aD,aE)local aF,aG=aD:sub(-1)=="/",aE:sub(-1)=="/"if aF~=aG then
return aF end;return aD<aE end)
local function aC(aD)if not e.lastModified then return"-"end
local aF,aE=pcall(e.lastModified,e.join(at,aD))
if not aF or type(aE)~="number"or aE<=0 then return"-"end
local aG,aH=pcall(os.date,"%Y-%m-%d %H:%M",math.floor(aE/1000))return aG and aH or"-"end
if ay then
E(string.format(" %-24s %8s  %s","Name","Size","Modified"),d.title)E(string.rep("-",52),d.border)else
E(string.format(X,"Name","Size"),d.title)E(string.rep("-",34),d.border)end
for aE,aD in ipairs(au)do local aG,aF
if aD:sub(-1)=="/"then
aG=string.format(X,"["..aD:sub(1,-2).."]","<DIR>")aF=d.dir or d.highlight else local aH=e.size(e.join(at,aD))
aF=d.fg
if aD:match("%.lua$")then
aF=d.file_lua or d.file_exec or d.highlight elseif aD:match("%.cfg$")or aD:match("%.conf$")then
aF=d.file_cfg or d.warning elseif aD:match("%.log$")then aF=d.file_log or d.dim end;aG=string.format(X,aD:sub(1,24),m(aH))end;if ay then aG=aG.."  "..aC(aD)end;E(aG,aF)end
if ax>0 then
E(#au.." items ("..ax.." hidden: ls -a shows them)",d.dim)else E(#au.." items",d.dim)end end;b.dir=b.ls
local function C(as,E)local at=f(as)if not l(at,E)then return true end;local au,av,aw=G.readLinesCapped(e,at,function(ax)
E(ax,d.fg)end)if not au then E(
J..as,d.error)elseif aw then
E(string.format(G.VIEW_STOPPED,av),d.warning)return false end;return true end
b.cat=function(E,as)
if not E[1]then as("Usage: cat <file...>",d.dim)return end;for au,at in ipairs(E)do if not C(at,as)then break end end end;b.type=b.cat
b.more=function(E,as)
if not E[1]then as("Usage: more <file>",d.dim)return end;local au=f(E[1])if not l(au,as)then return end
local at={{" "..au,d.title}}
local av,aw,ax=G.readLinesCapped(e,au,function(ay)at[#at+1]={ay,d.fg}end)if not av then as(J..E[1],d.error)return end;if ax then
at[#at+1]={string.format(G.VIEW_STOPPED,aw),d.warning}end
r(at,E[1]:match(Y)or E[1])end
local function D(E,at,as)local au=f(E)local av=au:match("^(.*)/[^/]+/?$")or"/"if not
o(av,as)then return false end;if e.isDirectory and e.isDirectory(au)then
if
not at then as("Already exists: "..E,d.warning)end;return false end
local aw,ax=e.makeDirectory(au)
if aw then as("Created: "..E,d.highlight)return true end
as(tostring(ax or"Could not create "..E),d.error)return false end
b.mkdir=function(as,E)local av,at=false,{}
for ax,aw in ipairs(as)do if aw=="-p"or aw=="--parents"then av=true else
at[#at+1]=aw end end
if not at[1]then E("Usage: mkdir [-p] <dir...>",d.dim)return end;local au=false;for ax,aw in ipairs(at)do au=D(aw,av,E)or au end
if au then k()end end
local function F(E,as)local at=f(E)if not o(at,as)then return false end
if not e.exists(at)then
local au,av=e.writeFile(at,"")if not au then
as(tostring(av or"Could not create "..E),d.error)return false end end;as("Touched: "..E,d.highlight)return true end
b.touch=function(E,as)
if not E[1]then as("Usage: touch <file...>",d.dim)return end;local at=false;for av,au in ipairs(E)do at=F(au,as)or at end
if at then k()end end
local function x(E)local at,as=false,{}for av,au in ipairs(E)do if au=="-k"or au=="--keep"then at=true else
as[#as+1]=au end end;return
at,as end
b.compress=function(as,E)local aC,au=x(as)if not au[1]then
E("Usage: compress <file> [out]   (-k keeps original)",d.dim)return end
local ax=h.getCompress and h.getCompress()if not ax or not ax.available()then
E("Compression needs a data card (none detected).",d.error)return end;local at=f(au[1])if not
l(at,E)then return end;if not e.exists(at)or
(e.isDirectory and e.isDirectory(at))then
E("Not a file: "..au[1],d.error)return end
local ay=e.readFile(at)if not ay then E("Read failed",d.error)return end;local av=au[2]and
f(au[2])or(at..".tcz")
if not o(av,E)then return end;local az,aA,aw,aB=ax.pack(ay)
if not az then E("Compress failed",d.error)return end
if not e.writeFile(av,az)then E("Write failed",d.error)return end;if not aC and av~=at then pcall(e.remove,at)end;k()
local aD=
(aw>0)and math.floor((aw-aB)*100/aw)or 0
E(string.format("%s -> %s  (%d%% smaller: %s -> %s)",au[1],(av:gsub("^.*/","")),aD,m(aw),m(aB)),
aA=="deflate"and d.highlight or d.warning)if aA=="stored"then
E("(stored uncompressed — data didn't shrink)",d.dim)end end
b.decompress=function(as,E)local az,au=x(as)if not au[1]then
E("Usage: decompress <file.tcz> [out]   (-k keeps original)",d.dim)return end;local at=f(au[1])if
not l(at,E)then return end;if not e.exists(at)then
E("No such file: "..au[1],d.error)return end;local aw=e.readFile(at)if not aw then
E("Read failed",d.error)return end
local ax=h.getCompress and h.getCompress()
if not ax then E("Compression module unavailable",d.error)return end;if not ax.isPacked(aw)then
E("Not a .tcz container: "..au[1],d.error)return end;local ay,aA=ax.unpack(aw)if not ay then
E(
"Decompress failed: "..tostring(aA),d.error)return end;local av
if au[2]then av=f(au[2])elseif at:sub(-4)==
".tcz"then av=at:sub(1,-5)else av=at..".out"end;if not o(av,E)then return end;if not e.writeFile(av,ay)then
E("Write failed",d.error)return end;if not az and av~=at then
pcall(e.remove,at)end;k()
E(string.format("%s -> %s  (%s restored)",au[1],(av:gsub("^.*/","")),m(
#ay)),d.highlight)end
local function al(as,at,au,E)local av=f(as)
if av=="/"then E("Cannot remove root",d.error)return end;local aw=_G._TOS and _G._TOS.securefs
if aw and
type(aw.removeRefusal)==W then
local aA=aw.removeRefusal(av,G.sessionOf(a))if aA then E(tostring(aA),d.error)return end end
local ay={"^/$","^/init%.lua$","^/bios%.lua$","^/tos$","^/tos/","^/etc$","^/etc/","^/boot$","^/boot/"}
for aB,aA in ipairs(ay)do
if av:match(aA)and not at then
E("Refusing to remove a system path without -r: "..av..
"  [E-303 ERR_RM_SYSTEM_PATH]",d.error)
E("Protection is off, so this would really delete it. Add -r to confirm.",d.dim)return end end;if not o(av,E)then return end
if e.isDirectory and e.isDirectory(av)then if not at then
E(
"Cannot remove directory without -r: "..av.."  [E-302 ERR_NEEDS_RECURSIVE]",d.error)return end
local aA=e.list and e.list(av)if aA and#aA>0 then
E("Removing "..#aA.." item(s) under "..av.."...",d.dim)end end;local ax=false
local az=av:match("^/tos")or av:match("^/etc")or
av:match("^/var")or av:match("^/usr")
if not au and not az then local aB,aA=pcall(require,"kernel.trash")
if
aB and aA and aA.put then local aC=G.sessionOf(a)local aD,aE=aA.put(av,aC)
if aD then ax=true
E("Trashed: "..as..
" (use 'restore' to undo)",d.highlight)else local aF=tostring(aE or"unknown reason")
if
aF:find("no trash",1,true)then
E("No trash for this session — deleting "..as.." outright.",d.warning)else
E("Not trashed: "..aF.."  [E-304 ERR_TRASH_REFUSED]",d.error)
E("It is still there. Delete it for good with:  rm "..
(at and"-r "or"").."--hard "..as,d.dim)return end end end end
if not ax then local aA,aB=e.remove(av)if aA then k()
E("Removed: "..as,d.highlight)else
E(tostring(aB or"Could not remove "..as),d.error)end else k()end end
b.rm=function(as,E)local au,av=false,false;local at={}for ax,aw in ipairs(as)do
if
aw=="-r"or aw=="-rf"or aw=="-R"then au=true elseif aw=="--hard"or aw=="-H"then av=true else at[#at+1]=aw end end
if
#at==0 then E("Usage: rm [-r] [--hard] <path...>",d.dim)return end;for ax,aw in ipairs(at)do al(aw,au,av,E)end end
b.trash=function(as,E)local aw,at=pcall(require,"kernel.trash")if not aw or not at then
E("Trash unavailable",d.error)return end;local au=as[1]or"list"
local av=G.sessionOf(a)
if au=="list"or au=="ls"then local ay=at.list(av)if#ay==0 then
E("Trash is empty.",d.dim)return end
E(string.format(" %-20s %-8s %s","name","size","origin"),d.title)for aA,az in ipairs(ay)do
E(string.format(" %-20s %-8d %s",az.name:sub(1,20),az.size,az.origin),d.fg)end;local ax=at.usage(av)if
ax then
E(string.format(" %d/%d items, %d/%d bytes used",ax.count,ax.max_count,ax.bytes,ax.max_bytes),d.dim)end elseif au=="empty"then
local ay,ax=at.empty(av)if ay then
E("Emptied "..tostring(ax).." items.",d.highlight)else
E(tostring(ax or"empty failed"),d.error)end elseif au=="restore"then if not as[2]then
E("Usage: trash restore <name> [dest] [--force]",d.dim)return end;local ax,ay=false,nil;for aB=3,#as do
if
as[aB]=="--force"or as[aB]=="-f"then ax=true else ay=as[aB]end end
local aA,az=at.restore(as[2],{session=av,dest=ay,force=ax})if aA then k()
E("Restored to "..tostring(az),d.highlight)else
E(tostring(az or"restore failed"),d.error)end else
E("Usage: trash [list|empty|restore <name> [dest] [--force]]",d.dim)end end
b.vault=function(as,E)local aA,au=G.requireRoomy(a,"kernel.vault","core")
if
not aA or not au then E(G.loadFailure("vault",au),d.error)return end;local at=as[1]local ay=G.sessionOf(a)
local av=_G._TOS and _G._TOS.securefs
local function aw(aB)if av and av.readFile then return av.readFile(aB,ay)end;return
nil,"securefs unavailable (refusing unchecked read)"end
local function az(aB,aC)
if av and av.writeFile then return av.writeFile(aB,aC,ay)end;return false,"securefs unavailable (refusing unchecked write)"end
local function ax(aB,aC)
if aB~=nil and aB~="-"then
E("Note: a typed passphrase stays in this seat's command history;",d.dim)
E("leave it off, or use -, to be asked for it instead.",d.dim)return aB end;if not j then
E("Cannot ask for a passphrase here: give it as the last argument.",d.error)return nil end
local aD=j("Passphrase: ",256,true)if not aD or aD==""then E(Z,d.dim)return nil end
if aC then
local aE=j("Again, to confirm: ",256,true)if aE~=aD then
E(aE and"The two did not match; nothing was changed."or Z,d.error)return nil end end;return aD end
if at==H or at==_ then local aE,aG=as[2],as[3]if not aE or not aG then
E("Usage: vault "..
at.." <src> <dst> [passphrase | -]",d.dim)return end;local aB=aw(f(aE))if not aB then E(J..
aE,d.error)return end;if at==_ and
not au.isEncrypted(aB)then
E("Source is not a TOS vault blob.",d.warning)return end
local aF=ax(as[4],at==H)if not aF then return end;local aC,aD;if at==H then aC,aD=au.encrypt(aB,aF)else
aC,aD=au.decrypt(aB,aF)end;if not aC then
E("Failed: "..tostring(aD),d.error)return end;local aH,aI=az(f(aG),aC)if not aH then
E(aa..tostring(aI),d.error)return end
E(string.format("%s %d -> %d bytes (algo=%s)",at==H and"Encrypted"or
"Decrypted",#aB,#aC,tostring(aD.algo)),d.highlight)elseif at=="encrypt-in-place"or at=="decrypt-in-place"then
local aE=as[2]if not aE then
E("Usage: vault "..at.." <file> [passphrase | -]",d.dim)return end;local aH=f(aE)local aB=aw(aH)if not aB then
E(J..aE,d.error)return end;local aD=at:sub(1,7)==H
if
aD and au.isEncrypted(aB)then
E("Already encrypted — refusing to double-encrypt.",d.warning)return elseif not aD and not au.isEncrypted(aB)then
E("Not a vault blob — nothing to decrypt.",d.warning)return end;local aF=ax(as[3],aD)if not aF then return end;local aC,aG;if aD then
aC,aG=au.encrypt(aB,aF)else aC,aG=au.decrypt(aB,aF)end
if not aC then E("Failed: "..
tostring(aG),d.error)return end;local aI,aJ=az(aH,aC)if not aI then E(aa..tostring(aJ),d.error)
return end
E(string.format("%s in place: %d -> %d bytes",
at:sub(1,7)==H and"Encrypted"or"Decrypted",#aB,#aC),d.highlight)elseif at=="info"then local aB=as[2]if not aB then
E("Usage: vault info <file>",d.dim)return end;local aC=aw(f(aB))if not aC then
E(J..aB,d.error)return end;if not au.isEncrypted(aC)then
E("Not a vault blob (no TVAULT1 magic).",d.warning)return end
E(string.format(" file:     %s",aB),d.title)
E(string.format(" size:     %d bytes",#aC),d.fg)local aD=#au.MAGIC+1
local aE=aC:sub(aD,aD+3):gsub("\0+$","")
E(string.format(" algo:     %s",aE),d.fg)
E(string.format(" ctLen:    encrypted body inside this blob"),d.dim)
E(" (decrypt with the right passphrase to access contents)",d.dim)elseif at=="tape"then local aB=as[2]if aB~=H and aB~=_ then
E("Usage: vault tape encrypt|decrypt [passphrase | -]",d.dim)return end;local aC=b.tape;if not aC then
E("Tape module not installed (run `pkg install tape`).",d.warning)return end
local aD=ax(as[3],aB==H)if not aD then return end;aC({aB,aD},E)else
E("Usage: vault [encrypt|decrypt|encrypt-in-place|decrypt-in-place|info|tape] ...",d.dim)
E("  vault encrypt <src> <dst> [passphrase]",d.dim)
E("  vault decrypt <src> <dst> [passphrase]",d.dim)
E("  vault encrypt-in-place <file> [passphrase]",d.dim)
E("  vault decrypt-in-place <file> [passphrase]",d.dim)E("  vault info <file>",d.dim)
E("  vault tape encrypt|decrypt [passphrase]",d.dim)
E("  Leave the passphrase off (or use -) to be asked for it, unechoed:",d.dim)
E("  a typed one stays in this seat's command history.",d.dim)end end
b.keychain=function(as,E)local at=_G._TOS and _G._TOS.keychain;if not at then
E("keychain module unavailable",d.error)return end;local au=G.sessionOf(a)
local av=as[1]or"status"
if av=="status"then
E(at.isUnlocked(au)and"unlocked"or"locked",d.fg)elseif av=="unlock"then if not j then
E("interactive prompt unavailable",d.error)return end
local aw=j("Master password: ",64,"*")or""
if#aw==0 then E("(empty — cancelled)",d.dim)return end;local ax,ay=at.unlock(aw,au)if ax then
E("Keychain unlocked.",d.highlight)else
E("Unlock failed: "..tostring(ay),d.error)end elseif av=="lock"then at.lock(au)
E("Keychain locked.",d.highlight)elseif av=="list"then
if not at.isUnlocked(au)then E(ab,d.warning)return end;local aw=at.list(au)
if#aw==0 then E("(empty)",d.dim)return end;for ay,ax in ipairs(aw)do E("  "..ax,d.fg)end elseif av=="set"then if not as[2]then
E("Usage: keychain set <name>",d.dim)return end;if not at.isUnlocked(au)then
E("Keychain is locked. Run 'keychain unlock' first.",d.warning)return end;if not j then
E("interactive prompt unavailable",d.error)return end;local aw=
j("Passphrase for '"..as[2].."': ",256,"*")or""if#aw==0 then
E("(empty — cancelled)",d.dim)return end;local ax,ay=at.set(as[2],aw,au)if ax then
E("Slot '"..
as[2].."' saved.",d.highlight)else
E("Save failed: "..tostring(ay),d.error)end elseif av=="get"then if not as[2]then
E("Usage: keychain get <name>",d.dim)return end;if not at.isUnlocked(au)then
E(ab,d.warning)return end;local aw,ax=at.get(as[2],au)if aw then
E(aw,d.fg)else
E(tostring(ax or"no such slot"),d.error)end elseif av=="remove"or av=="rm"then if not as[2]then
E("Usage: keychain remove <name>",d.dim)return end;if not at.isUnlocked(au)then
E(ab,d.warning)return end;local aw,ax=at.remove(as[2],au)
if aw then E("Removed '"..
as[2].."'.",d.highlight)else E(
"Remove failed: "..tostring(ax),d.error)end else
E("Usage: keychain [status|unlock|lock|list|set|get|remove] ...",d.dim)end end
b.profile=function(as,E)local au=_G._TOS and _G._TOS.profile;if not au then
E(ac,d.error)return end;local at=G.sessionOf(a)local av=as[1]or"show"
if av==
"show"then local aw,ay=au.load(at)
E(string.format(" name:    %s",aw.name),d.title)
E(string.format(" theme:   %s",aw.theme or"(unset — uses `theme set` choice or default)"),d.fg)
E(string.format(" cwd:     %s",aw.cwd or"(unset)"),d.fg)
E(string.format(" prompt:  %s",aw.prompt or"(default)"),d.fg)local ax=0;for az in pairs(aw.env)do ax=ax+1 end
E(string.format(" env:     %d entries",ax),d.fg)
E(string.format(" startup: %d commands",#aw.startup),d.fg)if not ay then
E(" (no profile file — showing defaults)",d.dim)end elseif av=="set"then
if not as[2]or not as[3]then
E("Usage: profile set <field> <value>",d.dim)E("  fields: name, theme, cwd, prompt",d.dim)return end;local aw,ax=as[2],as[3]local ay=au.load(at)
if aw=="name"or aw=="theme"or
aw=="cwd"or aw=="prompt"then
if aw=="theme"then local aB=_G._TOS and
_G._TOS.theme
if
aB and aB.preset and not aB.preset(ax)then E("Unknown theme preset: "..ax,d.error)if aB.list then
E(
"Available: "..table.concat(aB.list(),", "),d.dim)end;return end end;ay[aw]=ax;local az,aA=au.save(ay,at)
if az then
E("Profile updated. Re-login to apply.",d.highlight)else E(tostring(aA or ad),d.error)end else E("Unknown field: "..aw,d.error)end elseif av=="env"then if not as[2]then
E("Usage: profile env <KEY> [VALUE]",d.dim)return end;local aw=au.load(at)if as[3]then
aw.env[as[2]]=as[3]E("env["..as[2].."] set",d.highlight)else aw.env[as[2]]=
nil
E("env["..as[2].."] cleared",d.highlight)end
au.save(aw,at)elseif av=="startup"then local ax=as[2]or"list"local aw=au.load(at)
if ax=="add"then
local ay=table.concat(as," ",3)
if#ay==0 then E("Usage: profile startup add <cmd>",d.dim)return end;aw.startup[#aw.startup+1]=ay;au.save(aw,at)
E("Added.",d.highlight)elseif ax=="clear"then aw.startup={}au.save(aw,at)
E("Startup commands cleared.",d.highlight)else for ay,az in ipairs(aw.startup)do
E(string.format(" %d. %s",ay,az),d.fg)end;if#aw.startup==0 then
E("(no startup commands)",d.dim)end end elseif av=="reset"then local aw=_G._TOS and _G._TOS.securefs;if
aw and at and at.home and at.home~="/"then
aw.remove(at.home.."/.profile.cfg",at)end
E("Profile reset to defaults.",d.highlight)else
E("Usage: profile [show|set|env|startup|reset]",d.dim)end end
b.cp=function(E,as)
if not E[2]then as("Usage: cp <src> <dst>",d.dim)return end;local au,at=f(E[1]),f(E[2])if e.isDirectory(at)then
at=e.join(at,au:match(Y)or au)end;local av,aw=e.copy(au,at)
if av then k()
as("Copied: "..E[2],d.highlight)else as(aw or"Failed",d.error)end end
b.mv=function(as,E)
if not as[2]then E("Usage: mv <src> <dst>",d.dim)return end;local at,au=f(as[1]),f(as[2])if e.isDirectory(au)then
au=e.join(au,at:match(Y)or at)end;if not o(at,E)then return end
if not o(au,E)then return end
if e.rename(at,au)then k()E("Moved: "..as[2],d.highlight)else
local av,aw=e.copy(at,au)if av and e.remove(at)then k()
E("Moved: "..as[2],d.highlight)else
E("Move failed: "..tostring(aw or"cross-fs copy failed"),d.error)end end end
b.find=function(E,as)local ax="/"local av=nil;local at=1
while at<=#E do if E[at]=="-name"and E[at+1]then
av=E[at+1]at=at+2 else ax=f(E[at])at=at+1 end end
if av then local aC,aD=pcall(string.match,"",av)if not aC then
as("Invalid pattern: "..tostring(aD),d.error)return end end;as("Searching "..ax.." ...",d.dim)local aA=16
local aw=1000;local au={}
local function aB(aC)if not g or not g.canAccessAs then return false end
local aD=G.sessionOf(a)local aE=g.canAccessAs(aD,aC,"r")return aE end
local function az(aC,aD)if aD>aA then return end;if#au>=aw then return end;if not aB(aC)then return end
local aG,aE=pcall(e.list,aC)if not aG or not aE then return end;local aF={}
if type(aE)=="table"then aF=aE elseif
type(aE)==W then for aH in aE do aF[#aF+1]=aH end end
for aI,aH in ipairs(aF)do if#au>=aw then break end;N()
local aJ=e.join(aC,aH:gsub("/$",""))local aK=aH:sub(-1)=="/"local aL=false;if av then
local aM,aN=pcall(string.match,aJ,av)local aO,aP=pcall(string.match,aH,av)
aL=(aM and aN)or(aO and aP)else aL=true end;if aL then
au[
#au+1]={aJ.. (aK and"/"or""),
aK and(d.dir or d.highlight)or d.fg}end;if
aK and not aJ:match("^/tos")then az(aJ,aD+1)end end end;az(ax,0)if#au==0 then as("No matches found",d.dim)else for aD,aC in ipairs(au)do
as(aC[1],aC[2])end end;local ay=#au..
" result(s)"if#au>=aw then
ay=ay.." (truncated at "..aw..")"end;as(ay,d.dim)end
b.grep=function(as,E)
if not as[2]then E("Usage: grep <pattern> <file>",d.dim)return end;local aw=as[1]local av=f(as[2])if not l(av,E)then return end;local at=0;local au=0
local ax=G.eachLine(e,av,function(ay)au=
au+1;if ay:find(aw,1,true)then
E(string.format("%4d: %s",au,ay),d.fg)at=at+1 end end)if not ax then E(J..as[2],d.error)return end
E(at>0 and
(at.." match(es)")or"No matches",d.dim)end
b.wc=function(E,as)
if not E[1]then as("Usage: wc <file>",d.dim)return end;local av=f(E[1])if not l(av,as)then return end;local at,au=0,0
local aw,ax=G.eachLine(e,av,function(ay)at=at+1;for az in
ay:gmatch("%S+")do au=au+1 end end)if not aw then as(J..E[1],d.error)return end
as(string.format(" Lines: %d  Words: %d  Bytes: %d  -- %s",at,au,ax,E[1]),d.fg)end;b.pwd=function(as,E)E(a.cwd or"/",d.fg)end
local function y(E)
local au,at=nil,10;local as=1
while as<=#E do local av=E[as]
if av=="-n"and E[as+1]then
at=tonumber(E[as+1])or at;as=as+1 elseif av:match("^%-%d+$")then at=tonumber(av:sub(2))elseif not au then au=av elseif
tonumber(av)then at=tonumber(av)end;as=as+1 end;return au,at end
local function z(E,au,as,at)if e.exists and not e.exists(au)then
at("No such file: "..E,d.error)else
at("Cannot read "..E..
(as and(": "..tostring(as))or""),d.error)end end
b.head=function(as,E)local at,au=y(as)if not at then E("Usage: head [-n N] <file>",d.dim)
return end;local av=f(at)if not l(av,E)then return end
local aw=0;if not au or au<1 then return end
local ax,ay=G.eachLine(e,av,function(az)E(az,d.fg)aw=aw+1;if aw>=au then
return false end end)if not ax then z(at,av,ay,E)end end
b.tail=function(as,E)local av,at=y(as)if not av then E("Usage: tail [-n N] <file>",d.dim)
return end;local aw=f(av)if not l(aw,E)then return end;if not at or
at<1 then return end;if at>1000 then at=1000 end;local ax,au={},0
local ay,az=G.eachLine(e,aw,function(aA)
au=au+1;ax[(au-1)%at+1]=aA end)if not ay then z(av,aw,az,E)return end
for aA=math.max(1,au-at+1),au do E(ax[
(aA-1)%at+1],d.fg)end end
b.which=function(as,E)
if not as[1]then E("Usage: which <name>",d.dim)return end;local at=as[1]:lower()local au=false;local aw=G.aliases(a)
if aw[at]then
E(at..": alias for '"..
aw[at].."'",d.highlight)
E("  (expanded before dispatch; the expansion is resolved below)",d.dim)
at=tostring(G.tokenizeSimple(aw[at])[1]or at):lower()au=true end;local ay=require(K)
local av=ay.entry and ay.entry(at)or nil
if av then local aD=av.tier or 0
E(at..
": built-in (".. (av.category or"?")..", needs "..
G.tierName(aD)..")",d.title)if av.help then E("  "..av.help,d.fg)end;if
aD>G.liveTier(a)then
E("  You do not have the tier to run it — 'why "..at.."'.",d.warning)end;au=true end;local aB,ax=pcall(require,ae)
local az=aB and ax and ax.ownerOfCommand and
ax.ownerOfCommand(at)or nil
if az then
E(at..": package command from '"..az.."'",av and d.dim or d.title)
if av then E("  (shadowed by the built-in above)",d.dim)end;au=true end;local aA,aC=G.resolveProgram(e,at)
if aA then
E(at..": "..aA..
(aC=="path"and"  (via PATH)"or""),au and d.dim or
d.title)
if au then E("  (shadowed by the entry above)",d.dim)end;au=true end
if not au then E(at..": not found",d.error)
E("  Not a built-in, an installed package's command, or a program on",d.dim)
E("  /bin, /usr/bin or /tos/shell. 'help' lists what this box has.",d.dim)end end
b.alias=function(as,E)local av=_G._TOS and _G._TOS.profile;if not av then E(ac,d.error)
return end;local aw=G.sessionOf(a)
if not as[1]then local aC=av.load(aw)
local aB={}for aD in pairs(aC.aliases or{})do aB[#aB+1]=aD end
table.sort(aB)if#aB==0 then E("(no aliases)",d.dim)
E("Define one:  alias ll ls -l",d.dim)return end;for aE,aD in ipairs(aB)do
E(string.format(" %-12s %s",aD,aC.aliases[aD]),d.fg)end;return end;local at=as[1]:lower()if not at:match("^[%w_%-]+$")then E("Bad alias name: "..
as[1],d.error)
E("Letters, digits, underscore and hyphen only.",d.dim)return end
local au=av.load(aw)
if not as[2]then
if au.aliases and au.aliases[at]then
E(string.format(" %-12s %s",at,au.aliases[at]),d.fg)else E(at..": not aliased",d.dim)end;return end;local ax=table.concat(as," ",2)
local ay=tostring(G.tokenizeSimple(ax)[1]or""):lower()if ay==at then E("An alias cannot expand to itself.",d.error)
E("To add default flags, alias to a different name.",d.dim)return end;au.aliases=
au.aliases or{}au.aliases[at]=ax;local az,aA=av.save(au,aw)
if
not az then E(tostring(aA or ad),d.error)return end;G.invalidateAliases(a)
E("alias "..at.." -> "..ax,d.highlight)end
b.unalias=function(as,E)local av=_G._TOS and _G._TOS.profile;if not av then
E(ac,d.error)return end;if not as[1]then
E("Usage: unalias <name>",d.dim)return end;local aw=G.sessionOf(a)
local at=as[1]:lower()local au=av.load(aw)
if not au.aliases or not au.aliases[at]then E(
at..": not aliased",d.dim)return end;au.aliases[at]=nil;local ax,ay=av.save(au,aw)if not ax then
E(tostring(ay or ad),d.error)return end;G.invalidateAliases(a)E("Removed alias '"..
at.."'.",d.highlight)end
b.du=function(as,E)local at=f(as[1]or(a.cwd or"/"))
if not l(at,E)then return end;local function av(aw,ax)return
aw:sub(-1)=="/"and(aw..ax)or(aw.."/"..ax)end
local function au(aw)
if
e.isDirectory(aw)then local ax,ay=0,e.list(aw)
if type(ay)=="table"then for aA,az in ipairs(ay)do N()ax=ax+
au(av(aw,az:gsub("/$","")))end end;return ax end;return(e.size and e.size(aw))or 0 end
if e.isDirectory(at)then local aw=e.list(at)
if type(aw)=="table"then for ay,ax in ipairs(aw)do
local az=ax:gsub("/$","")
E(string.format(" %8s  %s",m(au(av(at,az))),az),d.fg)end end end
E(string.format(" %8s  %s (total)",m(au(at)),at),d.title)end
b.df=function(as,E)local av,at=pcall(require,"kernel.monitor")
E(string.format(" %-16s %8s %8s %8s  %s","Mount","Total","Used","Free","Use%"),d.title)
E(string.rep("-",math.min(q,56)),d.dim)local au=e.mounts and e.mounts()or{}
if#au==0 then
E("(mount info unavailable)",d.dim)else
for ax,aw in ipairs(au)do local ay=aw.total or 0;local az=aw.used or 0;local aB=ay-az
local aA=ay>0 and math.floor(
az*100/ay)or 0
local aC=(av and at.memBar)and at.memBar(az,ay,8)or""
local aD=aA<80 and d.fg or(aA<95 and d.warning or d.error)
E(string.format(" %-16s %8s %8s %8s  [%s] %3d%%",(aw.mountPoint or"?"):sub(1,16),m(ay),m(az),m(aB),aC,aA),aD)end end
if _G._TOS_ROOT_READONLY then E("",d.dim)
E("WARNING: the root filesystem is READ-ONLY.",d.error)
E("Nothing TOS writes will survive a reboot — users, logs, packages,",d.dim)
E("settings. Install to a writable drive, or unprotect this one.",d.dim)end
E("A path's own size: 'du <path>'.  Removable media + pools: 'disk'.",d.dim)end
b.mem=function(as,E)
if as and as[1]=="--boot"then
local aF=_G._TOS and _G._TOS.bootMem
if type(aF)~="table"or#aF==0 then
E("This boot was not profiled.",d.warning)
E("Add  memprofile = true  to /etc/boot.cfg and reboot.",d.dim)return end;E("=== Memory each boot stage used ===",d.title)
for aH,aG in
ipairs(aF)do local aI=aF[aH+1]
if aI then
E(string.format(" %-30s %4dK  (%dK free after)",tostring(aG.stage),math.floor((
(aG.free or 0)- (aI.free or 0))/1024),math.floor((
aI.free or 0)/1024)),d.fg)else
E(string.format(" %-30s %5dK free",tostring(aG.stage),math.floor((aG.free or 0)/1024)),d.dim)end end;return end;local ax,at=L.freeMemory(),L.totalMemory()local ay=at-ax;local au=at>0 and math.floor(
ay*100/at)or 0
local aB,aA=pcall(require,"kernel.monitor")local aw=math.min(24,math.max(8,q-36))
local aC=
(aB and aA.memBar)and aA.memBar(ay,at,aw)or
(
string.rep("#",math.floor(au/100*aw))..string.rep("-",aw-math.floor(au/100*aw)))E("=== Memory ===",d.title)
E(string.format(" RAM:  %dK used / %dK total   (%d%% used, %dK free)",math.floor(
ay/1024),math.floor(at/1024),au,math.floor(ax/1024)),d.fg)
local aD=au<75 and d.highlight or(au<90 and d.warning or d.error)E(" ["..aC.."]",aD)
local aE,av=pcall(function()
return h.getHAL().systemInfo()end)if aE and av and(av.memTierName or av.memTier)then
E(
" Tier: ".. (av.memTierName or("T"..av.memTier)),d.dim)end
local az=h.getSwap and h.getSwap()
if az and az.usage then local aG,aF=pcall(az.usage)
if aG and type(aF)=="table"then
E(string.format(" Swap: %dK / %dK on /var/swap   ('slow RAM' overflow)",math.floor((
aF.bytes or 0)/1024),math.floor((aF.max or 0)/1024)),d.dim)end else
E(" Swap: off   (enable in Boot Settings for low-RAM overflow)",d.dim)end;if ax<16*1024 then
E(" ! Low memory — near the ~16K danger zone.",d.warning)end
E("Live usage: 'monitor'.  Hardware tiers: 'hw'.",d.dim)end
b.hw=function(as,E)local at=h.getHAL().systemInfo()
E("=== Hardware ===",d.title)
E(string.format(" CPU T%d    GPU T%d    RAM %s",at.cpuTier or 0,at.gpuTier or 0,at.memTierName or("T"..
(at.memTier or 0))),d.fg)local av,au=pcall(require,"kernel.datacard")if
av and au and au.detect then local aw=au.detect()
E(" Data card: "..
(aw.present and aw.name or"none"),aw.present and d.fg or d.dim)end
E(string.format(" Components: %d    Network: %s    Tunnel: %s",
at.components or 0,at.canNetwork and"yes"or"no",at.hasTunnel and"yes"or"no"),d.dim)
E("Full component list: 'devices'.  Memory detail: 'mem'.  Live: 'monitor'.",d.dim)end;b.hardware=b.hw
b.ps=function(as,E)local aw=u.getForeground(a.displayIdx)
local at=G.sessionOf(a)local au=(at and at.tier)or 0
local ax=at and at.user or"?"
local av=(as[1]=="-v"or as[1]=="--verbose")and au>=2
if av then
E(string.format(" %-4s %-14s %-8s %-3s %-10s %-6s %s","PID","Name","State","DSP","Owner","CPU","Caps"),d.title)else
E(string.format(" %-4s %-16s %-8s %-3s %-10s %s","PID","Name","State","DSP","Owner","CPU"),d.title)end
E(string.rep("-",av and 70 or 50),d.border)
for az,ay in ipairs(u.list())do local aA=ay.user or"?"
if aA=="_kernel_"then aA="kernel"end;local aB=false
if au>=2 then aB=true elseif au>=1 and aA==ax then aB=true elseif au>=1 then aB="redacted"end
if aB==true then local aD=d.fg;local aC=ay.state;if ay.tsr then aC="TSR"end;if ay.pid==aw then
aD=d.highlight;aC=aC.." *"elseif ay.tsr then aD=d.dim end
if av then local aE={}if
ay.caps then for aF in pairs(ay.caps)do aE[#aE+1]=aF end
table.sort(aE)end
E(string.format(" %-4d %-14s %-8s %-3s %-10s %-6.1f %s",ay.pid,ay.name:sub(1,14),aC,tostring(
ay.display or"-"),(aA):sub(1,10),ay.cpuTime or 0,#aE>0 and
table.concat(aE,",")or"-"),aD)else
E(string.format(" %-4d %-16s %-8s %-3s %-10s %.1fs",ay.pid,ay.name:sub(1,16),aC,tostring(ay.display or"-"),(aA):sub(1,10),
ay.cpuTime or 0),aD)end elseif aB=="redacted"then
E(string.format(" %-4d %-16s %-8s %-3s %-10s   ",ay.pid,"(other user)","?","?","?"),d.dim)end end;E("",d.dim)
E(" * = foreground  |  -v for caps (admin+)  |  'monitor' for the live view",d.dim)end
b.monitor=function(as,E)local au,at=pcall(require,"shell.panels.monitorapp")if not au then
E(
"Monitor unavailable: "..tostring(at),d.error)return end;at.open(a)end;b.top=b.monitor
b.watch=function(as,E)
if not as[1]then
E("Usage: watch [seconds] <command ...>",d.dim)
E("  Opens a self-updating tab. e.g.  watch ps  ·  watch 2 df  ·  watch mem",d.dim)return end;local av,at=1,tonumber(as[1])if at then av=2 else at=1 end;if at<1 then at=1 end;if not
as[av]then E("Usage: watch [seconds] <command ...>",d.dim)
return end
local aw=table.concat(as," ",av)
local au=(aw:match("^(%S+)")or""):lower()
local ax={edit=true,lua=true,monitor=true,top=true,watch=true,launcher=true,launch=true,apps=true,kiosk=true,chat=true,more=true,man=true,vault=true,keychain=true,passwd=true,tutorial=true,bootsettings=true,useradd=true,["tape-auth"]=true}if ax[au]then
E("Can't watch '"..au.."' — it's interactive/screen-driven.",d.error)return end;do
local az,aA,aB=G.tierRefusal(a,au)
if az then E(az,d.error)a.lastDenial={cmd=au,need=aA,have=aB}return end end;if not c.openLiveTab then
E("Live tabs aren't available in this shell.",d.error)return end
local function ay()local az={}local aA={}for aI in
aw:gmatch("%S+")do aA[#aA+1]=aI end;if#aA==0 then return az end
local aB=aA[1]:lower()local aD={}for aI=2,#aA do aD[#aD+1]=aA[aI]end
local aE=G.tierRefusal(a,aB)if aE then az[#az+1]={aE,d.error}return az end;local aC=b[aB]
if
not aC then local aJ,aI=pcall(require,ae)if aJ and aI and aI.getCommand then
aC=aI.getCommand(aB)end end;if not aC then
az[#az+1]={"Unknown command: "..aB.."  [E-801 ERR_UNKNOWN_CMD]",d.error}return az end
local aF=function(aI,aJ)az[#az+1]={tostring(aI),
aJ or d.fg}end;local aG,aH=pcall(aC,aD,aF)if not aG then
az[#az+1]={"Error: "..tostring(aH),d.error}end;return az end;c.openLiveTab("watch: "..aw,ay,at)end
b.why=function(as,E)local az=require(K)local av=G.liveTier(a)
local at={title=d.title or d.highlight or d.fg,ok=
d.success or d.highlight or d.fg,err=d.error,fix=d.highlight or d.fg,dim=d.dim}local function au(aA)
for aC,aB in ipairs(aA)do E(aB.text,at[aB.tone]or d.fg)end end
local aw=as and as[1]and as[1]:lower()
if not aw then local aA=a.lastDenial
if aA and aA.cmd then
au(G.whyExplain(aA.cmd,aA.need,aA.have or av,true))return elseif aA then
E("Your last blocked action needed "..G.tierName(aA.need).."; you are "..
G.tierName(aA.have or av)..".",d.error)
E("Fix: run it on an admin/root account, or have an admin grant access.",at.fix)return end;local aB=a.lastFailure
if aB then
E((aB.cmd and(aB.cmd.." failed:")or
"The last action failed:"),at.title)E("  "..aB.text,d.error)
local aC,aE,aD=G.explainFailure(aB.text)if aD then E("  "..aD,at.dim)end
if aC then au(aC)else
E("No canned explanation for that one.",d.dim)
E("`log` has the kernel's own record of it, and `doctor` checks",d.dim)
E("memory, disks, services and security for a cause.",d.dim)end;return end
E("Nothing has failed since the last command ran.",d.dim)
E("why            — explain the last refusal or error.",d.dim)
E("why <code>     — explain an error code: E-402, ERR_PATH_PROTECTED, K4.",d.dim)
E("why <command>  — explain what a command needs and whether you can run it.",d.dim)return end;local ay=G.explainCode(as[1])if ay then au(ay)return end
local ax=az.entry(aw)
au(G.whyExplain(aw,ax and ax.tier or 0,av,ax~=nil))end
b.screendump=function(as,E)if not n or not n.dump then
E("Screen capture isn't available on this seat.",d.error)return end
local aA,av=pcall(n.dump)if not aA or type(av)~="table"or not av.lines then
E("Screen capture failed.",d.error)return end
local ax=(as and as[1])and
f(as[1])or
f("screen-"..math.floor(h.uptime())..".txt")
local aB=(G.sessionOf(a)or{}).user or"?"
local az=string.format("TOS screendump — seat %s · user %s · %dx%d · uptime %ds · read from the %s",tostring(a.displayIdx or"?"),aB,
av.w or 0,av.h or 0,math.floor(h.uptime()),tostring(av.source or"?"))local at=string.char(10)local au=az..
at..string.rep("-",#az)..at..
table.concat(av.lines,at)..at
if av.bg then
au=au..at..
"--- background colour runs, per row ---"..at
for aF=1,(av.h or 0)do local aG=av.bg[aF]
if aG then local aH={}for aJ,aI in ipairs(aG)do
aH[#aH+1]=string.format("%d-%d:%s",aI.from,aI.to,
aI.c and string.format("%06X",aI.c)or"nil")end
au=au..
string.format("row %2d  %s",aF,table.concat(aH,"  "))..at end end;local aE=a.T or{}
au=au..
at..
"theme: bg="..
string.format("%06X",aE.bg or 0)..
"  statusbar_bg="..string.format("%06X",
aE.statusbar_bg or 0)..
"  menubar_bg="..string.format("%06X",
aE.menubar_bg or aE.bar_bg or 0)..at end;local aw=function(aE)
return aE and string.format("%06X",aE)or"nil"end;au=au..at..
"--- cache vs glass ---"..at
if
av.disagree and#av.disagree>0 then
au=au.."THE SHADOW DISAGREES WITH THE SCREEN on "..#av.disagree..
" row(s)."..at
for aF,aE in ipairs(av.disagree)do
au=au..
string.format("  row %2d col %2d  glass=%s  shadow believes=%s",aE.row,aE.col,aw(aE.glass),aw(aE.shadow))..at;local aG=av.pageBg and av.pageBg[aE.row]
if aG then local aH={}for aF,aI in
ipairs(aG)do
aH[#aH+1]=string.format("%d-%d:%s",aI.from,aI.to,aw(aI.c))end
au=au.."    off-screen page holds: "..
table.concat(aH,"  ")..at end end elseif av.shadowBg then
au=au.."none — the shadow matches the glass everywhere."..at else
au=au.."(no shadow active on this seat)"..at end;local i=av.state
if i then
au=au..
at..
"--- display machinery ---"..
at..
"  shadow="..
tostring(i.shadow)..
"  colour cache: fg="..

aw(i.lastFg)..
" bg="..
aw(i.lastBg)..
at..
"  backbuffer="..
tostring(i.backbuffer)..
"  broken="..
tostring(i.backBroken)..

"  frameDepth="..
tostring(i.frameDepth)..
"  pageStale="..
tostring(i.pageStale)..at..
"  writerGen="..
tostring(i.writerGen)..
"  mine="..tostring(i.myWriterGen).."  lastWriterIsMe="..
tostring(i.lastWriterIsMe)..at end;local ay=_G._TOS and _G._TOS.fs;if
not(ay and ay.writeFile)then
E("No filesystem available to write the dump.",d.error)return end
local aC,aD=ay.writeFile(ax,au)
if aC then
E("Screen captured -> "..ax.."  (".. (av.h or 0).." rows)",
d.success or d.fg)
E("Attach it to a bug report, or 'cat' it to read it back.",d.dim)else
E("Could not write "..ax..": "..tostring(aD),d.error)end end
b.crash=function(as,E)if not s(E)then return end;local at=_G._TOS and _G._TOS.fs
if not
(at and at.list)then E("No filesystem.",d.error)return end
if as and as[1]then local ax=as[1]:find("/")and f(as[1])or
("/var/crash/"..as[1])
local az,ay=pcall(at.readFile,ax)if not az or not ay then
E("No such crash report: "..ax,d.error)return end;for aA in
(tostring(ay).."\n"):gmatch("(.-)\n")do E(aA,d.fg)end;return end;local aw,av=pcall(at.list,"/var/crash")local au={}if
aw and type(av)=="table"then
for ay,ax in ipairs(av)do ax=tostring(ax):gsub("/$","")if
ax~=""and ax~="NEW"then au[#au+1]=ax end end end
if#au==0 then
E("No crash reports — clean so far.",d.dim)
E("(TOS saves one here on a panic or an unrecoverable shell, so you",d.dim)E(" can read it after rebooting.)",d.dim)return end
E("Crash reports in /var/crash:",d.title or d.highlight or d.fg)for ay,ax in ipairs(au)do E("  "..ax,d.fg)end
E("Read one with:  crash <name>",d.dim)end
b.history=function(as,E)for at,au in ipairs(a.cmdHistory)do
E(string.format(" %3d  %s",at,au),d.dim)end;if#a.cmdHistory==0 then
E("(no history)",d.dim)end end
b.uptime=function(as,E)local at=h.uptime()local au=math.floor(at/3600)local av=math.floor(
(at%3600)/60)local aw=math.floor(at%60)
E(string.format("Uptime: %dh %dm %ds (%.1fs total)",au,av,aw,at),d.fg)end
b.date=function(as,E)
local at=h.getConfig and h.getConfig()or nil
if as[1]=="tz"or as[1]==Q or as[1]=="set"then local aA=(at and at.get and
at.get(Q))or 0
local az=tonumber(as[2])
if not az then E("Timezone offset: "..aA.."h",d.fg)
E("Usage: date tz <hours>   e.g. 'date tz -5'",d.dim)
E("OpenComputers has no settable clock; this only shifts the",d.dim)
E("DISPLAYED time relative to the world/host clock.",d.dim)return end;if az<-23 or az>23 then
E("Offset must be between -23 and 23.",d.error)return end;if not s(E)then return end
if not
(at and at.set)then E("No writable config available.",d.error)return end;at.set(Q,az)if at.save then at.save()end
E("Timezone offset set to "..az.."h. (was "..
aA.."h)",d.highlight)return end;local av=as[1]or"%Y-%m-%d %H:%M:%S"local aw=
(at and at.get and at.get(Q))or 0
local ax=os.time()+ (aw*3600)local ay,au=pcall(os.date,av,ax)if ay and au then
E(tostring(au),d.fg)else
E(tostring(au or"date error"),d.error)end end;b.time=b.date
b.keys=function(as,E)local aB,at=pcall(require,U)if not aB or not at then
E("Keybind module unavailable.",d.error)return end
local au=(as[1]or"list"):lower()local av=false;for aD=2,#as do
if as[aD]=="--system"then av=true;table.remove(as,aD)break end end
local aC=
(a.who=="root")and"/root"or("/home/".. (a.who or""))
local ax=av and"/etc/keys.cfg"or(aC.."/.keys.cfg")local az,aw=pcall(require,"kernel.serialize")
local function aA()
if not(az and aw and
a.F.exists(ax))then return{}end;local aD=a.F.readFile(ax)if not aD then return{}end
local aF,aE=pcall(aw.decode,aD,{maxBytes=8192})return
(aF and type(aE)=="table")and aE or{}end
local function ay(aD)if not(az and aw)then return false end
local aE=a.F.writeFile(ax,aw.encode(aD))if aE then at.reload()end;return aE end
if au=="list"or au=="ls"then
E("TOS standard shortcuts:",d.title)for aE,aD in ipairs(at.actions(a.who))do
E(string.format("  %-9s %-14s %s",aD.action,aD.keys,aD.help),
aD.isDefault and d.fg or d.highlight)end
E("",d.dim)
E("Reserved by the kernel — these cannot be rebound:",d.dim)for aE,aD in ipairs(at.reserved())do
E(string.format("  %-9s %s",aD.key,aD.help),d.dim)end;E("",d.dim)
E("Change one:  keys set quit F4       (add --system for everyone)",d.dim)E("Undo:        keys reset [action]",d.dim)
E("Every first-party TOS program follows this table.",d.dim)elseif au=="set"then local aD,aG=as[2],as[3]
if not(aD and aG)then
E("Usage: keys set <action> <key> [<key>...]",d.dim)
E("  e.g. keys set quit F4      keys set find ^F",d.dim)
E("Key names are written the way you say them: ^Q, F10, Ctrl+S, /",d.dim)return end;if not at.DEFAULTS[aD]then
E("No such action: "..aD.."  (see 'keys list')",d.error)return end;local aE={}
for aH=3,#as do local aI=as[aH]if not
at.parse(aI)then
E("Not a key name: '"..aI.."'  (try ^Q, F10, Ctrl+S, /)",d.error)return end
if at.isReserved(aI)then
E(aI..
" is reserved by the kernel and never reaches a program.",d.error)E("See 'keys list' for the reserved set.",d.dim)return end;aE[#aE+1]=aI end;local aF=aA()aF[aD]=aE
if ay(aF)then
E(aD..
" is now "..table.concat(aE," ").. (av and"  (machine-wide)"or
""),d.highlight)else E(af.. (av and R or"."),d.error)end elseif au=="reset"then local aD=as[2]local aE=aA()
if aD then if not at.DEFAULTS[aD]then
E("No such action: "..aD,d.error)return end;aE[aD]=nil;if ay(aE)then
E(aD.." is back to the default.",d.highlight)else E(ag,d.error)end else if ay({})then
E("All shortcuts back to the defaults.",d.highlight)else E(ag,d.error)end end else
E("keys — TOS's standard keyboard shortcuts",d.title)
E("  keys list                     Show them",d.fg)
E("  keys set <action> <key>...    Rebind one",d.fg)
E("  keys reset [action]           Back to the default",d.fg)
E("Add --system to change them for every user (/etc/keys.cfg, admin).",d.dim)end end
b.menu=function(as,E)local at=(as[1]or"list"):lower()local av=false;for aD=2,#as do
if
as[aD]=="--system"then av=true;table.remove(as,aD)break end end
local aB=
(a.who=="root")and"/root"or("/home/".. (a.who or""))
local au=av and"/etc/menu.cfg"or(aB.."/.menu.cfg")local aC,az=pcall(require,"kernel.serialize")if not aC or not az then
E("serialize unavailable",d.error)return end
local function aw()
if not a.F.exists(au)then return{}end;local aD=a.F.readFile(au)if not aD then return{}end
local aF,aE=pcall(az.decode,aD,{maxBytes=8192})return
(aF and type(aE)=="table")and aE or{}end
local function ax(aD)return a.F.writeFile(au,az.encode(aD))end;local function ay()local aE,aD=pcall(require,"shell.panels.draw")
if
aE and aD and aD.buildMenuDefs then a.menuDefs=aD.buildMenuDefs(a)end end
local function aA(aD)if
aD.remove then
return"remove "..tostring(aD.remove)..
(aD.menu==true and" (whole menu)"or"")end;if aD.rename then return
"rename "..
tostring(aD.rename).." -> "..tostring(aD.to)end;if
aD.move then return
"move "..tostring(aD.move).." -> "..tostring(aD.menu)end
if aD.menu and not
aD.cmd then return"new menu "..tostring(aD.menu)end;return
string.format("[%s] %s -> %s",aD.menu or"Tools",aD.add or aD.label or"?",aD.cmd or"?")end
if at=="list"or at=="ls"then local aD=aw()
if#aD==0 then
E("No menu edits in "..au..".",d.dim)
E("Add one:  menu add <label> <command...> [in <Menu>]",d.dim)
E("Machine-wide instead of just you:  menu add ... --system",d.dim)return end;E("Menu edits ("..au.."):",d.title)for aE,aF in ipairs(aD)do
E(string.format("  %d. %s",aE,aA(aF)),d.fg)end elseif at=="show"then
local aE,aD=pcall(require,"shell.panels.draw")if not aE or not aD or not aD.buildMenuDefs then
E("Menu system unavailable.",d.error)return end
for aG,aF in
ipairs(aD.buildMenuDefs(a))do E(aF.label,d.title)
for aG,aH in ipairs(aF.items)do if aH.sep then E("    ---",d.dim)else
E(string.format("    %-20s %s",aH.label,(
aH.action or""):match("^run:(.+)$")or(aH.action or"")),d.fg)end end end
E("Change it with: menu add|remove|rename|move  (add --system for everyone)",d.dim)elseif at==ah or at=="move"then local aE,aF=as[2],as[3]if not(aE and aF)then
E("Usage: menu "..at..

" <name> <".. (at==ah and"new name"or"Menu")..">",d.dim)return end;local aD=aw()
aD[#aD+1]=(
at==ah)and{rename=aE,to=aF}or{move=aE,menu=aF}
if ax(aD)then ay()
E("Saved. "..aA(aD[#aD]),d.highlight)else E(af.. (av and R or"."),d.error)end elseif at=="hide"then local aD=as[2]if not aD then
E("Usage: menu hide <item or Menu name>",d.dim)
E("Hides a built-in entry. 'menu reset' brings everything back.",d.dim)return end
local aE=aw()
aE[#aE+1]={remove=aD,menu=(as[3]=="menu")or nil}
if ax(aE)then ay()E("Hidden: "..aD,d.highlight)else E(af..
(av and R or"."),d.error)end elseif at=="reset"then if ax({})then ay()
E("Menu reset to the built-in bar ("..au.." cleared).",d.highlight)else
E("Reset failed".. (av and R or"."),d.error)end elseif
at=="add"then local aE=as[2]
if not aE or not as[3]then
E("Usage: menu add <label> <command...> [in <Menu>]",d.dim)
E("  e.g. menu add Tetris tetris   |   menu add Disk df in System",d.dim)return end;local aD=table.concat(as," ",3)
local aF=aD:match("%s+in%s+(%S+)%s*$")if aF then aD=aD:gsub("%s+in%s+%S+%s*$","")end
if
#aE>24 then E("Label too long (max 24).",d.error)return end;if#aD==0 or#aD>200 then
E("Command empty or too long.",d.error)return end;local aG=aw()
aG[#aG+1]={label=aE,cmd=aD,menu=aF or"Tools"}
if ax(aG)then ay()
E(string.format("Added '%s' -> %s  (menu: %s)",aE,aD,aF or"Tools"),d.highlight)else E("Save failed (is your home writable?).",d.error)end elseif at=="remove"or at=="rm"or at=="del"then
local aD=tonumber(as[2])local aE=aw()if not aD or not aE[aD]then
E("Usage: menu remove <#>   (see 'menu list')",d.error)return end
local aF=table.remove(aE,aD)if ax(aE)then ay()
E("Removed '".. (aF.label or"?").."'.",d.highlight)else E(ag,d.error)end else
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
b.tree=function(as,E)local av=f(as[1]or a.cwd)
local ay=tonumber(as[2])or 3;local aw=400;local at,au=0,false
local function ax(az,aA,aB)if au then return end;if aB>ay then return end
local aC=e.list(az)or{}
table.sort(aC,function(aD,aE)
local aF=e.isDirectory(az.."/".. (aD:gsub("/$","")))
local aG=e.isDirectory(az.."/".. (aE:gsub("/$","")))if aF~=aG then return aF end;return aD<aE end)
for aD,aE in ipairs(aC)do if at>=aw then au=true;return end;local aF=aE:gsub("/$","")
local aH=az=="/"and(
"/"..aF)or(az.."/"..aF)local aG=e.isDirectory(aH)local aI=(aD==#aC)
local aJ=aI and"`-- "or"|-- "local aK=aG and d.dir or d.fg;E(aA..
aJ..aF.. (aG and"/"or""),aK)at=at+1;if aG then
ax(aH,aA.. (aI and"    "or
"|   "),aB+1)end end end;E(av,d.title)ax(av,"",1)if au then
E(string.format("(truncated at %d entries; raise the limit or narrow the path)",aw),d.dim)end end
b.whoami=function(as,E)if g then local at=g.getSession(i)
E(at and at.user or"root",d.fg)else E(a.who,d.fg)end end
b.passwd=function(as,E)
if not g then E("No user system",d.error)return end;local av=j("Current password: ",64,true)if not av then return end
local at=j("New password: ",64,true)if not at then return end;local az=j("Confirm new password: ",64,true)if
az~=at then
a.lastOut={"Passwords do not match — unchanged.",d.error}return end;if at==""then
a.lastOut={"Password cannot be empty.",d.error}return end;local aw=g.getSession(i)local ax=
aw and aw.user or"root"
local ay,au=g.changePassword(ax,ax,av,at)
if ay and au then
a.lastOut={"Password changed. "..tostring(au),d.warning}elseif ay then a.lastOut={"Password changed.",d.highlight}else
a.lastOut={tostring(au),d.error}end end
local function am(E,as,at)local ax=a.st
local av=g.registerSession and g.registerSession(E)or nil;local ay,aw=pcall(require,P)
local au=ay and aw.current and aw.current()local az=au and au.principal;if av then a.st=av end
if au then au.principal=E end;local aA,aB=pcall(as)a.st=ax;if au then au.principal=az end;if av and g.logout then
pcall(g.logout,av)end;if not aA then
at("sudo: "..tostring(aB),d.error)end end
local function t()if not a._sudo then return false end;a.st=a._sudo.origSt
local at,E=pcall(require,P)local as=at and E.current and E.current()if as then
as.principal=a._sudo.origPrincipal end;if a._sudo.token and g.logout then
pcall(g.logout,a._sudo.token)end;a._sudo=nil;return true end;a.sudoDrop=t
b.sudo=function(as,E)
if not g then E("No user system",d.error)return end;local av=G.sessionOf(a)local at=as[1]
if at=="setup"then if not w(E)then return end;local aB=2;if
as[2]=="root"then aB=3 elseif as[2]and as[2]~="admin"then
E("Usage: sudo setup [admin|root]",d.dim)return end
local aA=j("New elevation password: ",64,true)if not aA or aA==""then E("Aborted.",d.dim)return end
if
j("Confirm: ",64,true)~=aA then E("Passwords do not match.",d.error)return end;local aC,aD=g.setElevation(av,aA,aB)
if aC then
E("Elevation configured (cap: "..
G.tierName(aB)..").",d.highlight)else E(tostring(aD),d.error)end;return elseif at=="off"then if not w(E)then return end
local aA,aB=g.clearElevation and g.clearElevation(av)if aA then E("Elevation disabled.",d.highlight)else
E(tostring(aB or"unavailable"),d.error)end;return elseif at=="-k"then
E(
t()and"Elevated session dropped."or"No active elevation.",d.dim)return end;if not at then
E("Usage: sudo <command> | sudo -s | sudo -k | sudo setup [admin|root] | sudo off",d.dim)return end
if
G.liveTier(a)<1 then E("sudo: guests cannot elevate.",d.error)return end
local ax=g.elevationInfo and g.elevationInfo()or{configured=false}if not ax.configured then
E("sudo: elevation is not configured. Root: sudo setup [admin|root]",d.warning)return end
local aw=j("[sudo] elevation password: ",64,true)if aw==nil then E("Aborted.",d.dim)return end
local au,ay=g.elevate(av,aw)if not au then
E("sudo: "..tostring(ay or"elevation failed"),d.error)return end
if at=="-s"then t()
local aB=g.registerSession and
g.registerSession(au)or nil;local aD,aC=pcall(require,P)
local aA=aD and aC.current and aC.current()
a._sudo={origSt=a.st,origPrincipal=aA and aA.principal,token=aB}if aB then a.st=aB end;if aA then aA.principal=au end
E("Elevated to "..
G.tierName(au.tier)..". 'sudo -k' or 'logout' drops it.",d.highlight)return end;local az=table.concat(as," ")
am(au,function()if not a.execOne then
E("sudo: executor unavailable",d.error)return end;local aA=a.execOne(az)if
type(aA)=="table"then
for aC,aB in ipairs(aA)do if type(aB)=="table"then E(aB[1],aB[2]or d.fg)else
E(tostring(aB),d.fg)end end end end,E)end;b.logout=function(E,as)G.logout(a)end
b.cli=function(as,E)if a.isCLI then
E("You are already at the command line. Type 'tui' for the full interface.",d.dim)return end;a._exitTo="cli"end
b.tui=function(as,E)if a.isCLI then E("Returning to the full interface…",d.dim)
a._exitTo="tui"return end
E("You are already in the full interface. Type 'cli' for the command line.",d.dim)end
b.reboot=function(as,E)local at,au=G.canPowerOff(a)
if not at then E(au,d.error)return end;h.reboot()end
b.shutdown=function(as,E)local at,au=G.canPowerOff(a)
if not at then E(au,d.error)return end;h.shutdown()end
b.env=function(E,as)local aw,at=pcall(require,"kernel.env")if not aw then
as("Env module unavailable",d.error)return end;local av=h.getProc()local au=
av and av.current()or nil
if E[1]then
local ax,ay=E[1]:match("^([%w_]+)=(.*)$")if ax then at.write(au,ax,ay)as(ax.."="..ay,d.highlight)else
local az=at.read(au,E[1])
as(E[1].."="..tostring(az or""),d.fg)end else
local ax=at.list(au)for ay,az in pairs(ax)do
as("  "..ay.."="..tostring(az),d.fg)end end end;b.export=b.env;b.set=b.env
b["tape-menu"]=function(as,E)
local aA,au=pcall(require,"shell.launcher")if not aA or not au then
E("Menu engine unavailable (low RAM?)",d.error)return end;if not n or not n.getSize then
E("tape-menu needs a screen.",d.error)return end;local av=nil
local function aB(aH)local aI={}local aJ={}for aR in
aH:gmatch("%S+")do aJ[#aJ+1]=aR end;if#aJ==0 then return aI end
local aK=aJ[1]local aM={}for aR=2,#aJ do aM[#aM+1]=aJ[aR]end
local aN=G.tierRefusal(a,aK:lower())if aN then aI[#aI+1]={aN,d.error}return aI end;if not av then
av=require(K).build(a,c)end;local aL=av[aK]
if not aL then local aS,aR=pcall(require,ae)if aS and aR and
aR.getCommand then aL=aR.getCommand(aK)end end;if not aL then
aI[#aI+1]={"Unknown command: "..aK,d.error}return aI end;local aO=function(aR,aS)
aI[#aI+1]={tostring(aR),aS or d.fg}end
local aP,aQ=pcall(aL,aM,aO)if not aP then
aI[#aI+1]={"Error: "..tostring(aQ),d.error}end;return aI end;local ax=M.list and M.list("tape_drive")()
if
not ax then E("No tape drive found.",d.error)return end;local at=M.proxy(ax)
local aC,aD=pcall(function()return at.isReady()end)
if not aC or not aD then E("No tape inserted.",d.warning)return end
local aE=(at.getSize and at.getSize())or 0
if aE<=0 then E("Tape is empty.",d.warning)return end
local aw=j and j("Tape menu passphrase: ",64,true)or nil;if not aw or aw==""then E(Z,d.dim)return end
local aF,ay=pcall(require,"kernel.vault")
if not aF or not ay then E("vault unavailable",d.error)return end;local az,aG=au.readTapeMenuFromDrive(at,aw,ay)if not az then
E(tostring(aG),d.error)return end
au.run({display=n,profile=az,runLine=aB,title="Tape toolbox"})if c.drawAll then pcall(c.drawAll)end end
b.clip=function(as,E)local aw,at=pcall(require,"kernel.clipboard")if not aw or not at then
E(
"Clipboard unavailable: "..tostring(at),d.error)return end;local au=a.displayIdx;local av=as[1]
if
not av then
E("Clipboard: "..at.describe(au),d.title)local ax=at.get(au)
if ax and not at.isEmpty(au)then
local ay=math.min(#ax,10)for az=1,ay do E("  "..ax[az],d.fg)end;if#ax>ay then
E("  ... "..
(#ax-ay).." more line(s)",d.dim)end end
E("Usage: clip [set <text> | clear]   Copy: "..
(function()local az,ay=pcall(require,U)
return(az and ay)and
ay.label("copy",a.who)or"Ctrl+Insert"end)(),d.dim)return end;if av=="clear"then at.clear(au)
E("Clipboard cleared.",d.highlight)return end
if av=="set"then
local ax=table.concat(as," ",2)
if ax==""then E("Usage: clip set <text>",d.warning)return end;local az,ay=at.set(ax,au)if not az then
E("Could not set clipboard: "..tostring(ay),d.error)return end;if ay then
E("Clipboard set, TRUNCATED at the cap: "..
at.describe(au),d.warning)else
E("Clipboard: "..at.describe(au),d.highlight)end;return end;E("Usage: clip [set <text> | clear]",d.warning)end
b.desktop=function(as,E)local au,at=pcall(require,"shell.panels.desktop")if not au then
E(
"Desktop unavailable: "..tostring(at),d.error)return end;at.open(a)end
b.settings=function(as,E)local au,at=pcall(require,"shell.panels.settingsapp")if
not au then
E("Settings unavailable: "..tostring(at),d.error)return end;at.open(a)end
b.lang=function(as,E)local ax,at=pcall(require,"kernel.i18n")if not ax or not at then
E(
"i18n unavailable: "..tostring(at),d.error)return end;local au=as[1]
if not au then
E(ai..at.language()..
"  ("..at.languageName()..")",d.title)E("Installed catalogs:",d.fg)for aC,aB in ipairs(at.available())do
local aD=(aB.code==
at.language())and" * "or"   "
E(aD..string.format("%-8s %s",aB.code,aB.name),d.fg)end
E("Usage: lang <code> | lang system <code> | lang dump [path]",d.dim)
E("Catalogs are DATA files at /usr/lang/<code>.lang — see 'man lang'.",d.dim)return end
if au=="system"then if not s(E)then return end;local aB=as[2]if not aB then
E("Usage: lang system <code|en>",d.dim)return end;local aC,aD=at.setLanguage(aB)
if not aC then E(
"Cannot set: "..tostring(aD),d.error)return end
if p and p.set then p.set("language",aB)if p.save then p.save()end end
E("System language: "..at.language(),d.highlight)return end
if au=="dump"then
local aC=f(as[2]or"/tmp/lang-template.lang")local aD=at.keysSeen()if#aD==0 then
E("No keys seen yet — visit a few screens first (log out/in, open the Desktop).",d.warning)return end
local aB={"-- TOS language catalog template (every t() key seen this session).","-- Translate the values, set meta.code/name, save as /usr/lang/<code>.lang,","-- then run `lang <code>`. Untranslated keys keep their English default.","-- /usr is a protected system path: as root, `protect off` to copy this","-- in and `protect on` after -- or ship the catalog as a package.","return {",'  meta = { code = "xx", name = "Language name" },',"  strings = {"}for aH,aG in ipairs(aD)do
aB[#aB+1]=string.format("    [%q] = %q,",aG.key,aG.default)end;aB[#aB+1]="  },"
aB[#aB+1]="}"
if not o(aC)then E("Cannot write: "..aC,d.error)return end
local aF,aE=e.writeFile(aC,table.concat(aB,"\n").."\n")
if aF then
E("Template with "..#aD.." key(s) -> "..aC,d.highlight)k()else E(aa..aC,d.error)
if aE then E(tostring(aE),d.dim)end
if aC:sub(1,10)=="/usr/lang/"then
E("Dump to /tmp (the default), then copy it in under `protect off`,",d.dim)E("or ship the catalog as a package.",d.dim)end end;return end;local ay,az=at.setLanguage(au)if not ay then
E("Cannot set '"..tostring(au)..
"': "..tostring(az),d.error)E("Run 'lang' to list installed catalogs.",d.dim)
return end
local aw=G.sessionOf(a)local aA,av=pcall(require,"kernel.profile")
if aA and av and av.load and
av.save then local aB=av.load(aw)
aB.lang=
(at.language()~="en")and at.language()or nil;local aC,aD=av.save(aB,aw)
if aC then
E(ai..
at.language().."  (saved to your profile)",d.highlight)else
E("Language set for this session (profile save failed: "..tostring(aD)..")",d.warning)end else
E(ai..at.language().."  (this session)",d.highlight)end end end