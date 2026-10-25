local p,i,m,n="computer","extras","inventory","shell.panels.commands."local j={}
local k={help={category="core",tier=0,help="Quick help (install-aware); 'man' for detail"},man={category="core",tier=0,help="Detailed manual page for a command/topic"},why={category="core",tier=0,help="Explain the last error, an error code (E-402, K4), or what a command needs"},screendump={category="core",tier=1,help="Capture this screen to a text file (for bug reports)"},crash={category="core",tier=2,help="List/read crash post-mortems saved in /var/crash"},about={category="core",tier=0,help="OS info: version, codename, hardware summary"},ver={category="core",tier=0,help="TOS version info",alias="about"},echo={category="core",tier=0,help="Print arguments"},notify={category="core",tier=1,help="Raise a dialog box on every seat (the intrusive 'echo')"},tutorial={category="core",tier=0,help="Replay the welcome walkthrough (--reset to see it again at login)"},cls={category="core",tier=0,help="Clear the screen"},clear={category="core",tier=0,help="Clear the screen",alias="cls"},cd={category="core",tier=0,help="Change directory"},ls={category="core",tier=0,help="List directory entries"},dir={category="core",tier=0,help="List directory entries",alias="ls"},pwd={category="core",tier=0,help="Print working directory"},cat={category="core",tier=0,help="Print file contents"},type={category="core",tier=0,help="Print file contents",alias="cat"},more={category="core",tier=0,help="Page through a file"},head={category="core",tier=0,help="Print the first lines of a file"},tail={category="core",tier=0,help="Print the last lines of a file: tail [-n N] <file> (watch tail to follow it)"},mkdir={category="core",tier=1,help="Make a directory"},touch={category="core",tier=1,help="Create an empty file"},compress={category="core",tier=1,help="Compress a file with the data card (-> .tcz)"},decompress={category="core",tier=1,help="Restore a .tcz file compressed by 'compress'"},rm={category="core",tier=1,help="Remove a file (--hard skips trash)"},trash={category="core",tier=1,help="Per-user trash: list/empty/restore"},vault={category="core",tier=1,help="Encrypt/decrypt files, tapes, or in-place (passphrase-based)"},keychain={category="core",tier=1,help="Per-user passphrase stash (unlocked with login password)"},cp={category="core",tier=1,help="Copy a file"},mv={category="core",tier=1,help="Move/rename a file"},find={category="core",tier=0,slow=true,help="Find files by name"},grep={category="core",tier=0,help="Search a file for a pattern"},wc={category="core",tier=0,help="Count lines/words/bytes"},df={category="core",tier=0,help="Disk space per mount (with usage bars)"},du={category="core",tier=0,slow=true,help="Size of a path on disk (recursive)"},mem={category="core",tier=0,help="Memory report: RAM + swap usage, tier, danger zone"},hw={category="core",tier=0,help="Hardware inventory: tiers, data card, components"},hardware={category="core",tier=0,help="Hardware inventory",alias="hw"},ps={category="core",tier=0,help="List processes (-v for caps)"},monitor={category="core",tier=0,help="Live System Monitor: processes, services, memory (also Ctrl+T)"},top={category="core",tier=0,help="Live System Monitor",alias="monitor"},watch={category="core",tier=0,help="Open a live, self-updating tab for a command (e.g. watch ps)"},history={category="core",tier=0,help="Show command history"},uptime={category="core",tier=0,help="Show kernel uptime"},date={category="core",tier=0,help="Show date/time (date tz <h> to set offset)"},time={category="core",tier=0,help="Show date/time",alias="date"},menu={category="core",tier=1,help="Adjust the menu bar (show/add/hide/rename/move/reset)"},keys={category="core",tier=0,help="Show or change TOS's standard keyboard shortcuts"},["tape-menu"]={category="core",tier=1,help="Personal command menu from your identity tape (keycard)"},desktop={category="core",tier=0,help="Open the Desktop: app tiles for built-ins + installed packages"},clip={category="core",tier=0,help="Show, set or clear the text clipboard"},settings={category="core",tier=0,help="Open the Settings app (theme, status bar, desktop, system)"},lang={category="core",tier=0,help="Show or set the UI language (data catalogs in /usr/lang)"},tree={category="core",tier=0,help="Show directory tree"},whoami={category="core",tier=0,help="Show current user"},passwd={category="core",tier=0,help="Change own password"},sudo={category="core",tier=1,help="Run a command with elevated privileges (sudo <cmd> | -s | -k | setup)"},logout={category="core",tier=0,help="Log out of this session"},cli={category="core",tier=0,help="Drop to the command-line shell (same commands, no panels)"},tui={category="core",tier=0,help="Return to the full panels interface"},reboot={category="core",tier=2,help="Reboot the system"},shutdown={category="core",tier=2,help="Shut the system down"},which={category="core",tier=0,help="Show what a command name resolves to (built-in, package, or program)"},open={category="core",tier=0,help="Open a file in the program that suits it ('open with' says why)"},alias={category="core",tier=0,help="Per-user command aliases: 'alias' lists, 'alias ll ls -l' defines"},unalias={category="core",tier=0,help="Remove a command alias"},env={category="core",tier=0,help="Show environment variables"},export={category="core",tier=0,help="Set an environment variable"},set={category="core",tier=0,help="Set an environment variable",alias="export"},kill={category="admin",tier=2,help="Kill a process by PID"},fg={category="admin",tier=2,help="Bring a process to foreground"},srm={category="admin",tier=1,slow=true,help="System Repair & Maintenance: status/scan/repair/baseline (front door for doctor+verify)"},verify={category="admin",tier=2,slow=true,help="File integrity vs the manifest (vs 'doctor' = runtime health)"},doctor={category="admin",tier=1,slow=true,help="Runtime health: memory/disk/services/power/security ('verify' = files)"},backup={category="admin",tier=2,slow=true,help="Snapshot/inspect/restore a directory tree"},pkg={category="admin",tier=2,slow=true,help="Package manager: list/search/install/upgrade/outdated/uninstall/enable/disable/make-disk"},install={category="admin",tier=2,help="Install a package (shortcut for 'pkg install')",alias="pkg"},uninstall={category="admin",tier=2,help="Remove a package (shortcut for 'pkg uninstall')",alias="pkg"},diag={category="admin",tier=1,help="Runtime health",alias="doctor"},optimize={category="admin",tier=1,help="Optimizations: power profile, display buffer, disk swap"},swap={category="admin",tier=1,help="Disk swap ('slow RAM' on /var/swap): status/keys/now/clear/on/off/auto"},bootsettings={category="admin",tier=2,help="Edit boot profile/verbosity/toggles (DEL during boot = visual editor)"},kiosk={category="admin",tier=2,help="Kiosk-mode info (log in as 'kiosk' to activate)"},profile={category="core",tier=0,help="Per-user profile (theme, env, startup, prompt)"},programs={category="admin",tier=2,help="List installed executables"},log={category="admin",tier=2,help="Show recent kernel log"},bg={category="admin",tier=2,help="Run a script in the background"},run={category="admin",tier=2,help="Run a Lua file directly"},lua={category="admin",tier=3,help="Open the Lua REPL (root only)"},edit={category="admin",tier=2,help="Open a file in the editor"},flash={category="admin",tier=3,help="Flash a BIOS to EEPROM (root only)"},protect={category="admin",tier=3,help="Stand down protected-path guards for this session (root only)"},reclaim={category="admin",tier=3,help="Remove leftover OpenOS files after installing over it (root only)"},users={category="admin",tier=2,help="List users (tier-filtered)"},useradd={category="admin",tier=3,help="Create a new user (root only)"},userdel={category="admin",tier=3,help="Delete a user (root only)"},usermod={category="admin",tier=3,help="Modify a user (root only)"},lsdev={category="admin",tier=1,help="List connected components (devices)"},devices={category="admin",tier=1,help="List connected components",alias="lsdev"},mount={category="admin",tier=2,help="Mount a disk"},umount={category="admin",tier=2,help="Unmount a path"},jbod={category="admin",tier=2,help="Disk pooling: combine several disks into one mount (opt-in)"},netfs={category="admin",tier=2,help="Remote shares: mount a directory exported by another TOS machine"},theme={category="admin",tier=1,help="Pick a preset theme for yourself (custom colours admin-only)"},colors={category="admin",tier=1,help="Pick a theme",alias="theme"},service={category="admin",tier=2,help="Start/stop/list rc.d services"},cron={category="admin",tier=2,help="Manage cron jobs"},redstone={category=i,tier=1,help="Redstone I/O (requires peripheral.redstone cap)"},rs={category=i,tier=1,help="Redstone I/O",alias="redstone"},robot={category=i,tier=1,help="Robot control (requires peripheral.robot cap)"},inventory={category=i,tier=1,help="Inventory control (requires peripheral.inventory cap)"},inv={category=i,tier=1,help="Inventory control",alias=m},component={category=i,tier=2,help="Generic component invocation"},compat={category=i,tier=0,help="OpenOS compat layer status"},disk={category=i,tier=2,help="Removable disks: list/info/eject (install from one = 'pkg install', pooling = 'jbod', space = 'df')"},drive={category=i,tier=1,slow=true,help="Unmanaged (raw) drives: list/info/format/mount/check/defrag (needs 'blockfs')"},tape={category=i,tier=1,help="Tape archive (via the tape package)"},deploy={category=i,tier=3,slow=true,help="Create install disk from running system"},chat={category=i,tier=1,help="Network chat"},mail={category=i,tier=1,help="Mesh email (needs the 'mail' add-on): 'mail' opens the inbox; mail send/read/delete"},intercom={category=i,tier=1,help="Announcement system (needs the 'intercom' add-on): say/play a tape cue + broadcast it"},["cluster-setup"]={category=i,tier=3,help="Set this machine up as a cluster Master or Manager (guided; works before anything is installed)"},rbmk={category=i,tier=1,help="RBMK reactor supervisor (needs the 'rbmk-control' add-on): survey/status/limits/scram/skala/wall"},rsh={category=i,tier=2,help="Remote shell client"},scp={category=i,tier=2,help="Network file copy"},screen={category=i,tier=1,help="Seat/screen info; 'screen res <auto|max|WxH>' sets resolution"},net={category=i,tier=1,help="Network admin (trust, peers, servers, ports)"},ping={category=i,tier=1,help="Network ping"},hostname={category=i,tier=0,help="Show device type + hostname; 'hostname <name>' sets it (admin)"},config={category=i,tier=2,help="Show /etc/tos.cfg, the machine's settings (read-only)"},battery={category=i,tier=0,help="Power management info"},internet={category=i,tier=1,help="Internet card: status, a test fetch, and the machine-wide on/off"},audio={category=i,tier=1,help="Audio feedback controls"}}
local o={net="net",ping="net",chat="net",rsh="net",scp="net",mail={"module:mail","net"},intercom="net",swap="swap",audio="audio",compat="compat",jbod="jbod",netfs="net",compress="component:data",decompress="component:data",redstone="component:redstone",rs="component:redstone",robot="component:robot",inventory=m,inv=m,tape="module:tape",["tape-menu"]="component:tape_drive",internet="component:internet"}j.NEEDS=o
function j.needMet(a)if not a then return true end;if type(a)=="table"then for f,e in ipairs(a)do if not
j.needMet(e)then return false end end
return true end;local b=_G._TOS or{}if
a=="net"then return b.net~=nil end
if a=="swap"then return b.swap~=nil end;if a=="jbod"then return b.jbod~=nil end;if a=="audio"then
return b.audio~=nil end;if a=="compat"then return b.compat~=nil end;if a==
"cluster"then return b.cluster_worker~=nil end
local c=a:match("^component:(.+)$")
if c then local e,f=pcall(require,"component")if not e then return false end;for g in
f.list(c)do return true end;return false end
if a==m then local e,f=pcall(require,"component")if not e then return false end
for h,g in
ipairs({"inventory_controller","transposer","tank_controller"})do for h in f.list(g)do return true end end;return false end;local d=a:match("^module:(.+)$")if d then
return(b.pkg and b.pkg.info and
b.pkg.info(d))~=nil end;return true end
function j.helpList(a)a=a or 0;local b={}
for e,d in pairs(k)do if d.alias then b[d.alias]=b[d.alias]or{}
table.insert(b[d.alias],e)end end;local c={core={},admin={},extras={}}
for d,e in pairs(k)do
if not e.alias and
(e.tier or 0)<=a and j.needMet(o[d])then local f=d;if b[d]then
table.sort(b[d])
f=d.." ("..table.concat(b[d],", ")..")"end
local h=c[e.category]or c.extras;h[#h+1]={name=f,help=e.help,manual=e.manual}end end;for e,d in pairs(c)do
table.sort(d,function(f,g)return f.name<g.name end)end;return c end;function j.entry(a)return a and k[a]or nil end
local l=setmetatable({},{__index=function(b,a)local c=k[a]return c and
c.category or nil end,__pairs=function()
return function(b,a)
local c,d=next(k,a)while c and not d.category do c,d=next(k,c)end;if c then
return c,d.category end end end})
function j.build(a,b)local d={}local c={}
local function f(r)r=tostring(r or""):lower()return

r:find("memory",1,true)~=nil or r:find("buffer alloc",1,true)~=nil end
local function h()local r=_G._TOS and _G._TOS.kernel
if r and r.gc then pcall(r.gc)return end;if type(collectgarbage)=="function"then
pcall(collectgarbage,"collect")end end
local function g(r)local s=0;for t in pairs(c)do
if t~=r then c[t]=nil;package.loaded[n..t]=nil;s=s+1 end end
if s>0 then for u,t in pairs(l)do if t~=r and not c[t]then
d[u]=nil end end;h()end;return s end;j._releaseCategories=g;a.releaseCommands=g
local function q(r)if c[r]then return end
local t,s=pcall(require,n..r)if not t and f(s)then g(r)t,s=pcall(require,n..r)end;if not
t and f(s)then h()t,s=pcall(require,n..r)end
if
not t then local x=f(s)local w=
(a.K and a.K.getLog and a.K.getLog())or nil;if w and w.warn then
w.warn("commands",
"Failed to load category '"..r.."': "..tostring(s))end
if x then local z=""
local A,y=pcall(require,p)if A and y and y.freeMemory then
z=string.format(" (%dKB free)",math.floor(y.freeMemory()/1024))end
a.lastOut={"'"..r..

"' commands need more memory than is free"..z.." — free RAM (close tabs / reboot) and they'll load on next use.",(
a.T and a.T.error)or nil}else c[r]=true end;return end;local u,v=pcall(s,d,a,b)
if not u then local w=
(a.K and a.K.getLog and a.K.getLog())or nil;if w and w.warn then
w.warn("commands","Category '"..r..
"' register error: "..tostring(v))end end;c[r]=true end;local e={}
do local function r(w,x)
w(x,(a.T and a.T.error)or nil)end;local function s(w,x)
w(x,(a.T and a.T.dim)or nil)end
local function t()
if a and a.U and a.st and a.U.getSession then
local x,w=pcall(a.U.getSession,a.st)if
x and type(w)=="table"and type(w.tier)=="number"then return w.tier end end;return 0 end
local function v(w)local y,x=pcall(require,"shell.panels.helpers")if
y and x and x.canPowerOff then local z,A=x.canPowerOff(a)
if not z then r(w,tostring(A))return false end;return true end;if t()<2 then
r(w,"Admin tier required to power off.")return false end;return true end
local function u(w,x)if not v(w)then return end
s(w,"(rescue: the core commands could not load, using the built-in)")local y=a.K;if y then local B=x and y.reboot or y.shutdown
if B then pcall(B)return end end;local A,z=pcall(require,p)
if A and z and
z.shutdown then
s(w,"(kernel handle missing -- restarting without a clean flush)")pcall(z.shutdown,x and true or false)else
r(w,"Cannot reach the power controls at all.")end end;e.reboot=function(x,w)u(w,true)end
e.shutdown=function(x,w)u(w,false)end
e.help=function(x,w)
r(w,"Command help is running in rescue mode: the full listing needs")
r(w,"memory that is not free. Names only, from the registry.")local y=j.helpList(t())
for x,z in ipairs({"core","admin",i})do local A=y[z]
if
A and#A>0 then local C={}for x,E in ipairs(A)do
C[#C+1]=(E.name:match("^%S+")or E.name)end
local B,D="",(a and a.W or 80)-2
for x,E in ipairs(C)do if#B+#E+2 >D then s(w,B)B=""end;B=
(B=="")and("  "..E)or(B.."  "..E)end;if B~=""then s(w,B)end end end;s(w,"'reboot' and 'shutdown' work from here too.")end
e.mem=function(x,w)local z,y=pcall(require,p)
if
not(z and y and y.freeMemory)then r(w,"Memory figures unavailable.")return end;local A=y.freeMemory()
local B=y.totalMemory and y.totalMemory()or 0
w(string.format("Free: %dK of %dK  (rescue reading)",math.floor(A/1024),math.floor(B/1024)),(
a.T and a.T.warning)or nil)end end
return
setmetatable({},{__index=function(s,r)local t=l[r]if not t then return nil end;q(t)local u=d[r]if u then return u end
return e[r]end,__newindex=function(t,r,s)d[r]=s end,__pairs=function()
local r={}for t,s in pairs(l)do if not r[s]then r[s]=true;q(s)end end;return
pairs(d)end})end;function j.commandNames()local a={}for b in pairs(l)do a[#a+1]=b end;table.sort(a)
return a end;function j.preloadAll(a,b)local c=j.build(a,b)
local d=c.help;d=c.flash;d=c.deploy;return c end
return j