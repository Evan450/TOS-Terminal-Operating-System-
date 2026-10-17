local g={}
g.SUBSYSTEMS={"boot","kernel","files","access","network","packages","hardware","shell"}
local l={{101,"ERR_CPU_ARCH","CPU architecture is too old — TOS needs a Lua 5.3+ CPU","C1"},{102,"ERR_NO_BOOT_DEVICE","no boot device — no /init.lua disk and no TBFS drive was found","D2"},{103,"ERR_TBFS_BOOT","the TBFS boot blob would not compile (raw-drive boot region damaged)","B3"},{104,"ERR_KERNEL_MISSING","the kernel was missing — /tos/kernel/init.lua was not on the disk","K4"},{105,"ERR_INIT_UNREADABLE","/init.lua could not be opened (unreadable or the disk went away)","I5"},{106,"ERR_INIT_SYNTAX","/init.lua would not compile (truncated or corrupted write)","I6"},{201,"ERR_KERNEL_PANIC","the kernel hit an error it could not recover from"},{202,"ERR_OUT_OF_MEMORY","the machine ran out of RAM"},{301,"ERR_NO_SPACE","the disk is full"},{302,"ERR_NEEDS_RECURSIVE","that is a directory; removing it needs -r"},{303,"ERR_RM_SYSTEM_PATH","rm will not remove a system path without -r"},{304,"ERR_TRASH_REFUSED","the trash would not take it, so nothing was deleted"},{305,"ERR_VAULT_UNLOCK","the passphrase is wrong, or the encrypted data was changed"},{306,"ERR_DRIVE_TOO_SMALL","TOS will not fit on that drive, so nothing was erased"},{401,"ERR_PERM_DENIED","your account is not allowed to do that"},{402,"ERR_PATH_PROTECTED","that path is guarded against changes, even by an admin"},{403,"ERR_TIER_REQUIRED","that needs a higher account tier"},{404,"ERR_SAFE_MODE","Safe Mode, or another boot profile, has that turned off"},{501,"ERR_NET_NO_ANSWER","a remote host did not answer (timed out, refused, or broke off)"},{601,"ERR_PKG_NOT_FOUND","no configured repo has a package by that name"},{602,"ERR_PKG_BAD_NAME","that is not a valid package name"},{603,"ERR_PKG_DEPENDENCY","something the package requires could not be satisfied"},{604,"ERR_PKG_FILE_MISSING","a file the package lists is not where it says"},{605,"ERR_PKG_FILE_UNREADABLE","a file the package lists is there but could not be read"},{606,"ERR_PKG_UNTRUSTED_SOURCE","a package only in a repo nobody configured, not signed by a key trusted here"},{607,"ERR_PKG_UNVERIFIED","the package lists no file hashes, so its files cannot be checked"},{608,"ERR_PKG_HASH_MISMATCH","a file is not the one the package's manifest describes"},{609,"ERR_PKG_SIGNATURE_INVALID","the package's signature does not verify: it changed after signing"},{610,"ERR_PKG_SIGNATURE_REQUIRED","this machine installs only packages signed by a key it trusts"},{611,"ERR_PKG_WRONG_PUBLISHER","the package is not signed by the publisher it has to be"},{612,"ERR_PKG_PROTECTED_TARGET","the package would write a path no package may own"},{613,"ERR_PKG_CONFLICT","the package conflicts with something already installed"},{801,"ERR_UNKNOWN_CMD","no command by that name"},{802,"ERR_CMD_UNLOADABLE","the command exists but would not fit in memory"}}local h,i,j,k={},{},{},{}
for b,a in ipairs(l)do
local c={num=a[1],sym=a[2],title=a[3],bios=a[4]}h[c.num]=c;i[c.sym]=c;k[#k+1]=c;if c.bios then j[c.bios]=c end end
function g.code(a)return string.format("E-%03d",a.num)end;function g.hex(a)return
string.format("0x%08X",((a.num//100)<<16)| (a.num%100))end;function g.label(a)return
g.code(a).." "..a.sym end;function g.tag(a)local b=i[a]
return b and("  ["..
g.label(b).."]")or""end;function g.subsystem(a)
return g.SUBSYSTEMS[a.num//100]end
function g.find(a)if type(a)=="number"then return
h[math.tointeger(a)or-1]end
if type(a)~="string"then return nil end;local b=a:match("^%s*(.-)%s*$"):upper()if
b==""then return nil end
local c=b:match("^E%-?(%d+)$")or b:match("^(%d+)$")if c then return h[tonumber(c)]end
local d=b:match("^0X(%x+)$")
if d then local e=tonumber(d,16)return e and
h[(e>>16)*100+ (e&0xFFFF)]or nil end;return j[b]or i[b]or i["ERR_"..b]end
function g.parse(a)if type(a)~="string"then return nil end
local b=a:match("%[E%-(%d%d%d) ERR_")return b and h[tonumber(b)]or nil end
function g.biosTable()local a={}for b,c in pairs(j)do a[b]=c.title end;return a end;function g.all()local a={}for b,c in ipairs(k)do a[b]=c end
table.sort(a,function(c,d)return c.num<d.num end)return a end;return g