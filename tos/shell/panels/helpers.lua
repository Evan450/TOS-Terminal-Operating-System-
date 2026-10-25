local s,t,p="function","pkg install","string"local u=require("computer")
local o={}
function o.resolvePath(b,a)if not a or a==""then return b.cwd end
if a:sub(1,1)=="/"then return a end;if a=="~"or a:sub(1,2)=="~/"then local c="/home/"..b.who;return
c..a:sub(2)end
return b.F.join(b.cwd,a)end
function o.loadFiles(b,a)a.files={}
if a.path~="/"then a.files[1]={name="..",dir=true,sz=0}end;local e,d=pcall(b.F.list,a.path)if not e or not d then return end
local c={}if type(d)=="table"then for g,f in ipairs(d)do c[#c+1]=f end elseif type(d)==s then for f in d do
c[#c+1]=f end end
table.sort(c,function(f,g)local h,i=f:sub(
-1)=="/",g:sub(-1)=="/"if h~=i then return h end;return
f<g end)
for g,f in ipairs(c)do local h=f:sub(-1)=="/"
local i=h and f:sub(1,-2)or f;local j=0;if not h then
pcall(function()j=b.F.size(b.F.join(a.path,i))end)end
a.files[#a.files+1]={name=i,dir=h,sz=j}end
if a.sel>#a.files then a.sel=math.max(1,#a.files)end;a.freeStr=nil
pcall(function()local f,g=nil,-1
for i,h in ipairs(b.F.mounts()or{})do
local j=h.mountPoint or""if j~=""and a.path:sub(1,#j)==j and#j>g then
f,g=h,#j end end;if f and f.total then
a.freeStr=o.fmtSz(math.max(0,(f.total or 0)- (f.used or 0)))end end)end;function o.refreshBrowser(a)o.loadFiles(a,a.browser)end
function o.fileColor(b,a)
local c=b.T
if a.dir then return c.dir or c.dir_color or c.highlight end;if a.name:match("%.lua$")then
return c.file_lua or c.file_exec or c.highlight end
if a.name:match("%.cfg$")or
a.name:match("%.conf$")then return c.file_cfg or c.warning end
if a.name:match("%.log$")then return c.file_log or c.dim end;return c.fg end
function o.safeModeRefusal(a)local c=_G._TOS;if
not(c and c.pkgDispatchDisabled)then return nil end
local e,b=pcall(require,"kernel.pkg")local d=
e and type(b)=="table"and b.ownerOfFile and b.ownerOfFile(a)or nil;if
not d then return nil end
return
"Safe Mode: "..
tostring(a).." belongs to the package '"..
tostring(d)..
"', and package code does not run in this boot. Reboot normally to use it.".."  [E-404 ERR_SAFE_MODE]"end
function o.mayHavePackages()
if package.loaded["kernel.pkg"]~=nil then return true end;local a=_G._TOS and _G._TOS.fs;if
type(a)~="table"or not a.exists or not a.list then return true end
local c,d=pcall(a.exists,"/var/pkg/installed")if not c then return true end;if not d then return false end
local e,b=pcall(a.list,"/var/pkg/installed")if not e then return true end;if type(b)==s then for f in b do if
tostring(f):gsub("/$","")~=""then return true end end
return false end;if type(b)~="table"then
return true end;for g,f in ipairs(b)do if
tostring(f):gsub("/$","")~=""then return true end end;return
false end
function o.loadFailure(a,b)local c=tostring(b or"unknown error")
if
c:find("Out of memory",1,true)or c:find("not enough memory",1,true)then return a..
" cannot load: not enough free memory on this machine."end;return a.." module unavailable: "..c end
function o.requireRoomy(a,b,c)local d,e=pcall(require,b)
if not d and a and
type(a.releaseCommands)==s then local f=tostring(e)if f:find("memory",1,true)or
f:find("buffer alloc",1,true)then a.releaseCommands(c)
d,e=pcall(require,b)end end;return d,e end
function o.reportProgramEnd(e,b,c,a,f,d)local i=e.T;local g,j;local k,h=pcall(require,"kernel.sandbox")if k and
type(h)=="table"and d and h.finish then
h.finish(d)end
if
k and type(h)=="table"and h.describeEnd then g,j=h.describeEnd(c,a)elseif c then
g=a~=nil and tostring(a)or nil else g,j=tostring(a),true end;if not g then return end;if j then
b((f or"Error: ")..g,i.error)elseif c then b(g,i.fg)else b(g,i.dim)end end
function o.diskName(a)
local b=type(a)=="table"and a.label or nil
if type(b)==p and b~=""and b~="Unnamed"then return b end
local c=type(a)=="table"and a.mountPoint or nil
local d=type(c)==p and c:match("([^/]+)/*$")or nil;return d or"disk"end
function o.announceDisk(a,d,e,b,c)if type(b)~=p then return false end;local f=a.T;a.outLines=nil
if
e=="added"then local g=o.classifyDisk(d,b)
local h=string.format('%s: "%s" -> %s',g.desc,c or"disk",b)if g.hint then h=h.."   "..g.hint end
a.lastOut={h,f.highlight}else
a.lastOut={'Disk removed: "'..o.diskName({label=c,mountPoint=b})..'"',f.dim}end;return true end
function o.fmtSz(a)
if a>=1048576 then return string.format("%.1fM",a/1048576)end;if a>=1024 then
return string.format("%dK",math.floor(a/1024))end;return a.."B"end
function o.selPath(a)if
a.browser.sel<1 or a.browser.sel>#a.browser.files then return nil,nil end
local b=a.browser.files[a.browser.sel]if b.name==".."then return nil,nil end;return
a.F.join(a.browser.path,b.name),b end
function o.classifyDisk(a,b)
if not a or not b or b==""then return{kind="data",desc="disk"}end
local function d(g)local h,i=pcall(a.exists,g)return h and i or false end;local function c(g)return d(a.join(b,g))end
local function e(g)local h={}
local j,i=pcall(a.list,g)if j and i then
if type(i)=="table"then for l,k in ipairs(i)do h[#h+1]=k end elseif type(i)==s then for k in i do h[#h+
1]=k end end end;return h end
local function f(g)
for i,h in ipairs(e(g))do local j=h:gsub("/$","")
if j~=""and j~="."and j~=".."and not
j:find("[/\\]")and
d(a.join(a.join(g,j),"package.lua"))then return true end end;return false end
if c("tos/kernel/init.lua")then return
{kind="tos-install",desc="TOS install disk",hint="(install image — run its install.lua on the target machine)"}end
if f(b)then
if c("optutil-set.lua")then return
{kind="optional-utilities",desc="Optional Utilities disk",hint=t}end;return{kind="package-repo",desc="package repo disk",hint=t}end
for h,g in ipairs(e(b))do local i=g:gsub("/$","")
if i~=""and i~="."and i~=".."and not
i:find("[/\\]")then local j=a.join(b,i)
if f(j)then if
d(a.join(j,"optutil-set.lua"))then
return{kind="optional-utilities",desc="Optional Utilities disk",hint=t}end;return
{kind="package-repo",desc="package repo disk",hint=t}end end end
if c("package.lua")then return
{kind="package",desc="single-package disk",hint="disk install "..b}end
if c("module.cfg")then return
{kind="module",desc="module disk (legacy)",hint="disk install "..b}end;return{kind="data",desc="data / blank disk"}end
function o.scanMountedMedia(a)if not a or not a.mounts then return nil end
local c,b=pcall(a.mounts)if not c or type(b)~="table"then return nil end
for e,d in ipairs(b)do
if
d.mountPoint and d.mountPoint~="/"then
local f=o.classifyDisk(a,d.mountPoint)
if f and f.kind~="data"then f.mountPoint=d.mountPoint;f.label=d.label;return f end end end;return nil end
function o.routeOutput(a,b)a=tonumber(a)or 0;if a<=0 then return"none"end
if a==1 then return"status"end;if a<= (b or 8)then return"inline"end;return"tab"end
function o.completeToken(a,b)a=a or""local c={}for f,e in ipairs(b or{})do
if e:sub(1,#a)==a then c[#c+1]=e end end;if#c==0 then return a,c end
if#c==1 then return c[1],c end;local d=c[1]for e=2,#c do local g,f=c[e],0;while f<#d and f<#g and
d:sub(f+1,f+1)==g:sub(f+1,f+1)do f=f+1 end
d=d:sub(1,f)end;return d,c end
function o.completeCmdline(b,c,a)local f,g=(b or""):match("^(.-)(%S*)$")if not
f:find("%S")then local l,m=o.completeToken(g,c or{})
if#m==1 then l=l.." "end;return f..l,m end
local d,h=g:match("^(.*/)([^/]*)$")d,h=d or"",h or g;local j=(a and a(d))or{}local i={}for m,l in ipairs(j)do
i[#i+1]=(
type(l)=="table"and l.name or l)end;local e,k=o.completeToken(h,i)
if#k==1 then for m,l in
ipairs(j)do local n=type(l)=="table"and l.name or l
if n==e then e=e..
((
type(l)=="table"and l.dir)and"/"or" ")break end end end;return f..d..e,k end
function o.cmdScroll(b,c,a)if a<1 then a=1 end;local d=(c or(b+1))-1
if d<0 then d=0 elseif d>b then d=b end;local e=0;if d>a-1 then e=d- (a-1)end;if e<0 then e=0 end;return e end
function o.wrapLine(a,b)if#a<=b then return{a}end;local c={}
while#a>b do local d=b;local e=false
for f=b,math.max(1,b-20),-1 do if
a:sub(f,f)==" "then d=f-1;e=true;break end end;c[#c+1]=a:sub(1,d)
a=a:sub(d+ (e and 2 or 1))end;if#a>0 then c[#c+1]=a end;return c end
function o.expandBuf(a,b)local c={}
local e=(a.tier and a.tier>=2)and 6 or 0;local d=math.max(8,a.W-e)
for g,f in ipairs(b)do local i=type(f)=="table"local h=
i and f[1]or f;if type(h)~=p then h=tostring(h)end;local j=i and f[2]or
a.T.fg
if#h<=d then if i and f[1]==h and f[2]~=nil then
c[#c+1]=f else c[#c+1]={h,j}end else for g,k in
ipairs(o.wrapLine(h,d))do c[#c+1]={k,j}end end end;return c end;local y=32*1024
o.VIEW_STOPPED="-- stopped after %d lines: memory is low. Read the rest with head, tail or grep."
function o.readLinesCapped(a,b,c)local d,e=0,false
local f,g=o.eachLine(a,b,function(h)if d%64 ==0 then local i=u.freeMemory and u.freeMemory()or
math.huge
if i<y+d*16 then e=true;return false end end;c(h)d=d+1 end)if not f then return false,g end;return true,d,e end;local v={}
function o.formatLineNum(b,a)local c=v[a]
if not c then c="%".. (a-1).."d "v[a]=c end;return string.format(c,b)end
function o.padR(a,b)a=tostring(a)if#a>=b then return a:sub(1,b)end;return a..
string.rep(" ",b-#a)end
function o.padL(a,b)a=tostring(a)if#a>=b then return a:sub(1,b)end;return
string.rep(" ",b-#a)..a end
function o.liveTier(a)
if a and a.U and a.st then
if a.U.getSession then local b=a.U.getSession(a.st)if b and
type(b.tier)=="number"then return b.tier end end;return 0 end;return(a and a.userTier)or 0 end;local q
local function z()if q==nil then local b,a=pcall(require,"shell.panels.commands")
q=(b and
type(a)=="table")and a or false end;return q or nil end
function o.tierRefusal(b,a)local d=z()
local e=d and d.entry and d.entry(a)or nil;local c=e and tonumber(e.tier)or 0
if c<=0 then return nil end;local f=o.liveTier(b)if f>=c then return nil end;return
"Permission denied: '"..tostring(a)..
"' needs "..
(
o.tierName and o.tierName(c)or("tier "..c)).."  [E-403 ERR_TIER_REQUIRED]",c,f end
function o.rootOnly(a,b)
if o.liveTier(a)<3 then
local c=o.fail(a,"Permission denied: root only  [E-403 ERR_TIER_REQUIRED]",b)a.lastDenial={cmd=a.curCmd,need=3,have=o.liveTier(a)}return c end;return true end
function o.adminOnly(a,b)
if o.liveTier(a)<2 then
local c=o.fail(a,"Permission denied: admin access required  [E-403 ERR_TIER_REQUIRED]",b)a.lastDenial={cmd=a.curCmd,need=2,have=o.liveTier(a)}return c end;return true end;function o.tierName(a)a=tonumber(a)or 0
return
({[0]="GUEST",[1]="USER",[2]="ADMIN",[3]="ROOT"})[a]or("tier "..a)end
function o.whyExplain(b,a,c,d)local f={}local function e(g,h)
f[#f+1]={text=g,tone=h}end;b=b or"?"
if not d then
e("Unknown command: "..b,"err")
e("It isn't a built-in. If it came from a package, check `pkg list`;","dim")
e("otherwise check the spelling — Tab completes command names.","dim")return f end;a=tonumber(a)or 0;c=tonumber(c)or 0
e(b..
" — needs "..o.tierName(a)..
"; you are "..o.tierName(c)..".","title")
if c>=a then e("You have the access to run this.","ok")
e("If it still failed, the cause is something else (a missing","dim")
e("resource, file, or capability) — check `doctor` and `log`.","dim")elseif a>=3 then e("This is ROOT-only.","err")
e("Fix: log in on the root account to run it (`logout`, then","fix")e("sign in as root).","fix")else
e("This needs administrator access.","err")
e("Fix: have an admin run it, or sign in on an admin account","fix")
e("(`logout`, then log in as an admin). An admin can also grant","fix")e("your account admin rights.","fix")end;return f end
function o.noteFailure(b,c,a)if not b or b.lastFailure then return end
a=tostring(a or"")if a==""then return end;b.lastFailure={cmd=c,text=a}end
function o.clearFailure(a)if not a then return end;a.lastFailure=nil;a.lastDenial=nil end
function o.fail(a,b,c,d)b=tostring(b or"failed")if a then a.lastFailure=nil end;o.noteFailure(a,
d or(a and a.curCmd),b)if c then
c(b,a.T.error)elseif a then a.lastOut={b,a.T.error}end;return false end
local w={{key="is a protected system path",sym="ERR_PATH_PROTECTED",lines={{"That is a guard, not a permission problem.","err"},{"TOS keeps its own files (/tos, /etc, /init.lua, /usr) behind a","dim"},{"check that sits ABOVE the user model, so a mistake — or a","dim"},{"tampered admin account — cannot overwrite the kernel and leave","dim"},{"the machine unbootable.","dim"},{"Fix: root can stand it down for one session with  protect off","fix"},{"(it lifts at logout, and every path it allows is logged). To","fix"},{"REMOVE TOS, boot another disk and delete it from there.","fix"}}},{key="Refusing to remove a system path without -r",sym="ERR_RM_SYSTEM_PATH",lines={{"You named a system path, and rm will not touch one by accident.","err"},{"The protected-path guard has already been asked and allows it:","dim"},{"root has lifted protection, so the delete would really happen.","dim"},{"Fix: add -r to confirm, if you really mean it.","fix"}}},{key="Cannot remove directory without -r",sym="ERR_NEEDS_RECURSIVE",lines={{"rm removes files; a directory needs the recursive flag.","err"},{"Fix:  rm -r <path>","fix"}}},{key="Not trashed:",sym="ERR_TRASH_REFUSED",lines={{"The delete was REFUSED, not performed — the file is still there.","err"},{"TOS routes rm through the trash so a delete is undoable. When","dim"},{"the trash will not take a file (too large for its cap, or the","dim"},{"cap is full) the delete stops rather than quietly becoming","dim"},{"permanent.","dim"},{"Fix: empty it (`trash empty`), raise the cap, or delete for good","fix"},{"with  rm --hard <path>","fix"}}},{key="not enough memory",sym="ERR_OUT_OF_MEMORY",lines={{"The machine ran out of RAM part-way through.","err"},{"Fix: close view tabs, `trash empty`, or reboot. `free` shows","fix"},{"what is left; more RAM sticks raise the ceiling.","fix"}}},{key="could not be loaded",sym="ERR_CMD_UNLOADABLE",lines={{"The command exists — its command group would not fit in memory.","err"},{"Fix: free RAM (close tabs, reboot) and run it again.","fix"}}},{key="Unknown command:",sym="ERR_UNKNOWN_CMD",lines={{"No command by that name is registered on this machine.","err"},{"Fix: `help` lists what there is, Tab completes names, and","fix"},{"`pkg list` shows what an add-on would provide.","fix"}}},{key="out of space",sym="ERR_NO_SPACE",lines={{"The disk is full.","err"},{"Fix: `df` shows which disk; `trash empty` and removing files free","fix"},{"it. The write that failed changed nothing, so retry after.","fix"}}},{sym="ERR_TIER_REQUIRED",lines={{"Your account's tier is too low for that command.","err"},{"Fix: `why <command>` shows the tier it needs; an admin can run it,","fix"},{"or sign in on an account that has that tier.","fix"}}},{sym="ERR_VAULT_UNLOCK",lines={{"It did not decrypt: the passphrase is wrong, or the encrypted","err"},{"data was changed after it was written.","err"},{"A vault checks its own integrity, so a wrong passphrase is","dim"},{"refused instead of producing garbage. Nothing was changed.","dim"},{"Fix: try the passphrase again (`keychain list` may have it).","fix"},{"If it is right, this copy is damaged; restore it from a backup.","fix"}}},{sym="ERR_DRIVE_TOO_SMALL",lines={{"The install would not fit on that drive, so nothing was erased.","err"},{"Fix: use a larger drive, or install onto a managed disk:","fix"},{"  deploy <mount-point>","fix"}}},{sym="ERR_NET_NO_ANSWER",lines={{"A remote host did not answer: it timed out, refused the","err"},{"connection, or the transfer broke off part-way.","err"},{"Nothing was changed, and the next attempt asks again.","dim"},{"Fix: `internet` shows whether the card can reach the network;","fix"},{"then try again.","fix"}}},{sym="ERR_PKG_NOT_FOUND",lines={{"No configured repo lists a package by that name.","err"},{"Fix: `pkg search <word>` lists what the repos offer, and","fix"},{"`pkg repo list` shows which repos this machine uses (an admin","fix"},{"adds one with  pkg repo add <name> <url>).","fix"}}},{sym="ERR_PKG_BAD_NAME",lines={{"A package name is letters, digits and inner dashes, 64 at most.","err"},{"A name that is not one is refused before it is used for","dim"},{"anything -- including one a repo's requirements asked for,","dim"},{"which means that repo is broken or hostile.","dim"},{"Fix: check the spelling; nothing was written.","fix"}}},{sym="ERR_PKG_DEPENDENCY",lines={{"Something the package requires could not be satisfied, so","err"},{"nothing was installed. The message says which requirement,","err"},{"and why: in no configured repo, installed but too old, or the","dim"},{"repo's copy does not meet the version asked for.","dim"},{"Fix: install or upgrade that one first (`pkg install` from a","fix"},{"disk, `pkg upgrade <name>`), or add a repo that has it.","fix"}}},{sym="ERR_PKG_FILE_MISSING",lines={{"A file the package lists is not on the source, so nothing was","err"},{"installed: the copy is incomplete.","err"},{"Fix: copy the package again, or install it from another source.","fix"}}},{sym="ERR_PKG_FILE_UNREADABLE",lines={{"A file the package lists is there but would not read, so nothing","err"},{"was installed. Usually memory: installing needs 1280 KB of RAM.","err"},{"Fix: on \"not enough memory\", close tabs, reboot or add a stick.","fix"}}},{sym="ERR_PKG_UNTRUSTED_SOURCE",lines={{"The package is only in a repo nobody configured, and from there","err"},{"TOS takes only what a trusted key signed, never an unsigned one.","err"},{"Fix: check the fingerprint with the publisher elsewhere, then","fix"},{"pkg trust add <name> <key> -- or pkg repo add <name> <url>.","fix"}}},{sym="ERR_PKG_UNVERIFIED",lines={{"The manifest gives no hashes for its files, so TOS cannot check","err"},{"them. Nothing was installed.","err"},{"Fix: if you trust the source, install again with --allow-unverified.","fix"}}},{sym="ERR_PKG_HASH_MISMATCH",lines={{"A file does not match its hash in the manifest: the copy is","err"},{"damaged or was changed. Nothing was installed.","err"},{"Fix: copy it again; if it happens again, do not install it.","fix"}}},{sym="ERR_PKG_SIGNATURE_INVALID",lines={{"The package's signature does not verify: it was changed after","err"},{"signing. That is tampering or corruption, with no override.","err"},{"Fix: get the package again from its publisher.","fix"}}},{sym="ERR_PKG_SIGNATURE_REQUIRED",lines={{"pkg trust require is on, and this package is unsigned or signed","err"},{"by a key this machine does not trust.","err"},{"Fix: check the fingerprint, then pkg trust add <name> <key>,","fix"},{"or --allow-unsigned for this one install.","fix"}}},{sym="ERR_PKG_WRONG_PUBLISHER",lines={{"Not signed by the publisher it must be: the one its requirer pins,","err"},{"or the one that signed the installed version.","err"},{"Fix: if they really changed keys, confirm it with them, then","fix"},{"pkg upgrade <name> --force.","fix"}}},{sym="ERR_PKG_PROTECTED_TARGET",lines={{"The package would write a path no package may own (the message","err"},{"names it). Nothing was installed; there is no override.","err"},{"Fix: do not install it, and tell its author.","fix"}}},{sym="ERR_PKG_CONFLICT",lines={{"The package conflicts with one already installed (the message","err"},{"names it). Nothing was installed.","err"},{"Fix: uninstall the other one first:  pkg uninstall <name>","fix"}}},{sym="ERR_SAFE_MODE",lines={{"The boot profile has this turned off. Safe Mode runs nothing","err"},{"third-party: no services, cron jobs, package commands or programs.","err"},{"The pkg admin verbs still work, to remove what broke.","dim"},{"Fix: bootsettings profile normal, then reboot.","fix"}}},{sym="ERR_KERNEL_PANIC",lines={{"The kernel hit an error it could not recover from, and stopped.","err"},{"The crash report is in /var/crash — `crash` reads it.","dim"},{"Fix: reboot. If it happens again, run  srm scan  (from another","fix"},{"disk, if this one will not boot).","fix"}}},{key="Permission denied",sym="ERR_PERM_DENIED",lines={{"Your account is not allowed to touch that path.","err"},{"This one IS the permission model: the file's owner and mode","dim"},{"decide, so it depends on who you are as much as what you ran.","dim"},{"Fix: `whoami` shows your account and tier; an admin can grant","fix"},{"access, or run it for you.","fix"}}}}
local function x()local b,a=pcall(require,"kernel.errors")return
(b and type(a)=="table")and a or nil end
local function r(a)
for c,b in ipairs(w)do if b.sym==a then local d={}
for c,e in ipairs(b.lines)do d[#d+1]={text=e[1],tone=e[2]}end;return d end end end
function o.explainFailure(a)if type(a)~=p then return nil end;local c=x()
local b=c and c.parse(a)local d
if b then
d=r(b.sym)or
{{text=b.title:sub(1,1):upper()..
b.title:sub(2)..".",tone="err"}}else
for f,e in ipairs(w)do if e.key and a:find(e.key,1,true)then d=r(e.sym)
b=c and c.find(e.sym)break end end end;if not d then return nil end;return d,b,b and c.label(b)or nil end
function o.explainCode(a)local d=x()local b=d and d.find(a)if not b then return nil end
local c={{text=
d.label(b).." — "..b.title,tone="title"}}for f,e in ipairs(r(b.sym)or{})do c[#c+1]=e end
if b.bios then
c[#c+1]={text=string.format(
"The EEPROM reports this one as %s: a long beep, then %d ".."short. `srm status` shows the last one.",b.bios,
b.num%100),tone="dim"}end;return c,b end
function o.logout(a)
if a and a._sudo and a.sudoDrop then pcall(a.sudoDrop)end;if a and a.E and a.E.push then
a.E.push("tos_logout",a.displayIdx)end end
function o.canPowerOff(a)if o.liveTier(a)>=2 then return true end;local b=0;local c=_G._TOS and
_G._TOS.shellPIDs;if type(c)=="table"then
for e,d in pairs(c)do if d then b=b+1 end end end;if b<=1 then return true end;return false,
b..
" operators are logged in. Ask an admin to power off, ".."or wait for the others to log out."end;local A=64*1024
function o.eachLine(b,c,a)local e,g=b.open(c,"r")if not e then return false,g end
local f,d=0,""
local h,i=pcall(function()
while true do local j=e:read(4096)if not j then break end;f=f+#j
local l=(d~="")and(d..j)or j;local k=1
while true do local m=l:find("\n",k,true)if not m then break end;if a(l:sub(k,m-1))==
false then d=""return end;k=m+1 end;d=l:sub(k)
if#d>A then if a(d)==false then d=""return end;d=""end end;if d~=""then a(d)end end)pcall(e.close,e)if not h then return false,tostring(i)end
return true,f end
function o.sessionOf(a)
if a and a.U then if a.st and a.U.getSession then local b=a.U.getSession(a.st)if b then
return b end end;if a.U.currentSession then
local b=a.U.currentSession()if b then return b end end end;return nil end
function o.canAccess(a,b,c,d)
if a.U then local g=o.sessionOf(a)local e,f
if g and a.U.canAccessAs then
e,f=a.U.canAccessAs(g,b,c)elseif a.U.canAccess then e,f=a.U.canAccess(b,c)else e,f=false,"access check unavailable"end
if not e then return
o.fail(a,"Permission denied: ".. (f or b).."  [E-401 ERR_PERM_DENIED]",d)end;return true end
if c=="w"then
for f,e in ipairs({"/tos","/etc","/var"})do if b==e or
b:sub(1,#e+1)==e.."/"then
if a.who~="root"then return
o.fail(a,"Permission denied: system path  [E-401 ERR_PERM_DENIED]",d)end end end end;return true end;function o.canWrite(a,b,c)return o.canAccess(a,b,"w",c)end;function o.canRead(a,b,c)return
o.canAccess(a,b,"r",c)end
o.SYSTEM_BIN_DIRS={"/bin","/usr/bin","/tos/shell"}
o.UNSAFE_PREFIXES={"/mnt/","/tmp/","/public/","/home/","/root/"}
function o.dirIsSafe(a)local b=tostring(a or"")if b==""then return false end;local c={}
for d in
b:gsub("\\","/"):gmatch("[^/]+")do
if d==".."then c[#c]=nil elseif d~="."then
d=d:gsub("\226\132\170","k"):gsub("\196\176","i"):lower():gsub("[%. ]+$","")if d~=""then c[#c+1]=d end end end;b="/"..table.concat(c,"/")
if b:sub(-1)~="/"then b=b.."/"end
for e,d in ipairs(o.UNSAFE_PREFIXES)do if b:sub(1,#d)==d then return false end end;return true end
function o.aliases(a)if a._aliases then return a._aliases end;local b={}
local c=_G._TOS and _G._TOS.profile
if c and c.load then local e,d=pcall(c.load,o.sessionOf(a))
if e and
type(d)=="table"and type(d.aliases)=="table"then for f,g in
pairs(d.aliases)do
if type(f)==p and type(g)==p then b[f:lower()]=g end end end end;a._aliases=b;return b end;function o.invalidateAliases(a)a._aliases=nil end;local B=8
function o.expandAlias(b,a)if
type(a)~="table"or#a==0 then return a end;local c=o.aliases(b)if
next(c)==nil then return a end;local d={}
for e=1,B do
local g=tostring(a[1]or""):lower()local i=c[g]if not i or d[g]then break end;d[g]=true
local f=o.tokenizeSimple(i)if#f==0 then break end;local h={}for j=2,#a do h[#h+1]=a[j]end;for e,j in ipairs(h)do
f[#f+1]=j end;a=f end;return a end;function o.tokenizeSimple(a)local b={}
for c in tostring(a):gmatch("%S+")do b[#b+1]=c end;return b end
function o.safeMountName(a,b)
local f,d=pcall(require,"kernel.diskmount")if f and type(d)=="table"and d.sanitizeLabel then return
d.sanitizeLabel(a,b)end;local e="disk_"..
tostring(b or"????"):sub(1,4)if type(a)~=p then return e end
local c=a:gsub("[^%w_%- ]","_")
c=c:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")if c==""or c=="."or c==".."then return e end;if#c>32 then
c=c:sub(1,32)end;return c end
function o.resolveProgram(a,b)if type(b)~=p or b==""then return nil end
local function c(f)
local g=a.join(f,b..".lua")if a.exists(g)then return g end;g=a.join(f,b)
if a.exists(g)then return g end;return nil end
for g,f in ipairs(o.SYSTEM_BIN_DIRS)do local h=c(f)if h then return h,"system"end end;local d,e=pcall(require,"kernel.env")
if d then
local f=e.read(nil,"PATH")or"/usr/bin:/bin"for g in f:gmatch("[^:]+")do
if o.dirIsSafe(g)then local h=c(g)if h then return h,"path"end end end end;return nil end;return o