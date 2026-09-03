-- TOS BIOS
-- Byte budget: the flashable copy is TOS-Release/bios.lua (this file run
-- through build/strip.lua --minify, which removes ALL comments) and must
-- fit a 4 KiB EEPROM. Comments here are free; CODE bytes are not — keep
-- names short and constructs lean (test_bios.lua enforces the budget).
local c,p=component,computer
-- Status colours, named once. These literals appeared 21 times between
-- them; at 7 bytes saved per use that is ~110 bytes of EEPROM budget
-- recovered, which is what paid for the POST-OK beep below. Short names
-- are the house style here (see the byte-budget note above).
--   G = ok/green   D = dim/grey   R = fail/red
local G,D,R=0x00ff00,0xaaaaaa,0xff0000
local l=c.list
local e=l("eeprom")()
-- EEPROM invokes can fail (removed mid-boot, hardware glitch). Guard both
-- accessors so the BIOS doesn't crash before we've drawn anything.
local function E(m,...)local o,v=pcall(c.invoke,e,m,...)if o then return v end end
-- The 256-byte EEPROM data field holds the boot address on the FIRST
-- LINE. Anything after a newline belongs to someone else — the kernel
-- anchors its manifest hash there (#SEC C1) — so read only line one, or
-- that anchor would be swallowed into the address and the BIOS would
-- lose its saved boot device on every boot. Old EEPROMs hold a bare
-- address with no newline, which this still reads unchanged.
p.getBootAddress=function()return(E("getData")or""):match("^[^\n]*")end
-- Writing a NEW boot device intentionally drops any trailing anchor: the
-- system it described is no longer the one booting. `doctor` then reports
-- the manifest as un-anchored and the operator re-anchors.
p.setBootAddress=function(a)return E("setData",a)end

-- Safe component proxy: nil-ish on any failure (bad/missing address).
local function X(a)local o,x=pcall(c.proxy,a)return o and x end

-- GPU init. A GPU with NO screen must leave g nil: P() below calls
-- g.fill/g.set/g.copy unguarded and an unbound GPU raises "no screen".
local g,s=X(l("gpu")()),l("screen")()
if not s then g=nil end
local w,h,d,y=50,16,1,1
if g then
 pcall(g.bind,s)
 -- Clamp BOTH axes (init.lua uses the same clamp); some T3 multi-seat
 -- screens report oversize maxResolution.
 local o,a,b=pcall(g.maxResolution)
 if o and a and b then w,h=math.min(80,a),math.min(25,b)end
 pcall(g.setResolution,w,h)
 o,a=pcall(g.getDepth)if o and a then d=a end
 pcall(g.setBackground,0)
 pcall(g.setForeground,d<2 and 0xffffff or G)
 pcall(g.fill,1,1,w,h," ")
end
-- Print one status line. T1 (1-bit) gets white; scroll at the bottom.
-- The body is pcall'd: a screen/GPU pulled MID-BOOT otherwise raises
-- "no screen" out of the BIOS as a raw machine error. On failure the
-- BIOS goes silent (g=nil) but keeps booting.
local function P(t,f)
 if not g then return end
 if not pcall(function()
  g.setForeground(d<2 and 0xffffff or f)
  if y>h then g.copy(1,2,w,h-1,0,-1)y=h end
  g.fill(1,y,w,1," ")g.set(1,y,tostring(t):sub(1,w))y=y+1
 end)then g=nil end
end
-- Wait for an actual KEY (ignore stray touch/component/network signals —
-- #118/#99/#101), then reboot.
local function K()while p.pullSignal(1e9)~="key_down"do end p.shutdown(true)end

-- SRM Basic — the EEPROM half of System Repair & Maintenance. (Plain `--`,
-- not `--!`: this explanation is worth 62 EEPROM bytes to nobody, and the
-- dev copy you are reading is where it belongs. See the byte-budget note at
-- the top of the file.)
--
-- SRM Basic's remit is exactly the faults SRM Advanced can NEVER observe,
-- because the machine never got far enough to run it — a dead CPU arch, no
-- boot device, an unloadable kernel or init. Everything else (memory
-- headroom, disk usage, services, drifted files) is left to the on-disk half,
-- which has the storage to do it properly. That division is why this stays
-- small enough to fit beside a boot loader.
--
-- Every POST failure below is a NAMED fault with a single exit, F(), which
-- (1) parks the code where the on-disk SRM will find it, (2) names it on
-- screen, (3) beeps it for a box with no working display, and (4) halts.
--
-- Parking is the whole point of the split: the faults SRM Basic catches are
-- exactly the ones SRM Advanced can never observe, because the machine never
-- got far enough to run it. The EEPROM data field is the only storage that
-- survives a box whose disk is the problem, so the code goes on its OWN LINE
-- there — line 1 is the boot address (getBootAddress reads only line 1) and
-- line 2 is the kernel's TOS1 manifest anchor, so appending is safe and
-- neither is disturbed. Any previous SRM line is stripped first so codes
-- replace rather than accumulate. `srm status` reports the parked code on the
-- next successful boot and clears it.
--
-- Code = subsystem letter + beep count. The digit IS the number of short
-- beeps after the long one, so a screenless box still tells you which fault
-- it hit (this is why they aren't all "1"):
--   C1 CPU architecture   D2 no boot device   B3 TBFS boot blob
--   K4 kernel missing     I5 init unreadable  I6 init syntax
local function F(n,t)
 -- gsub returns (string,count); the concat below forces the string alone.
 local x=(E("getData")or""):gsub("\nSRM:%S*","")
 E("setData",x.."\nSRM:"..n)
 P("SRM "..n.." - POST FAILED",R)
 if t then P(t,0xff6600)end
 P("Any key reboots. Then run 'srm'",D)
 p.beep(400,.4)
 for _=1,n:byte(2)-48 do p.beep(900,.1)end
 K()
end

-- Try to read a TBFS boot blob from a raw `drive` at address x; returns
-- the blob string or nil. The superblock is sector 1: "TBFS", ver(1),
-- then fixed little-endian fields — bootStart at byte offset 32,
-- bootBlocks at 36 (blockfs packSuper; block == sector, 0-indexed, so
-- block b = sector b+1). The boot region is a CONTIGUOUS sector run
-- holding a 4-byte-LE-length-prefixed Lua chunk (blockfs.writeBoot), so
-- no TBFS parser is needed here — that's the whole point of the design.
local function T(x)
 local v=X(x)
 if not v or not v.readSector then return end
 local o,sc=pcall(v.readSector,1)
 if not o or type(sc)~="string"or #sc<40 or sc:sub(1,4)~="TBFS"or sc:byte(5)~=1 then return end
 local bs,bb=("<I4"):unpack(sc,32),("<I4"):unpack(sc,36)
 if bb<1 then return end
 local r={}
 for i=bs+1,bs+bb do
  local k,dd=pcall(v.readSector,i)
  r[#r+1]=k and type(dd)=="string"and dd or""
 end
 r=table.concat(r)
 if #r<5 then return end
 local n=("<I4"):unpack(r)
 if n>0 and n<=#r-4 then return r:sub(5,4+n)end
end

P("TOS BIOS",G)

-- Lua architecture probe: the kernel needs Lua 5.3 FEATURES (bitwise
-- syntax in kernel modules; string.pack in this BIOS's TBFS reader).
-- This is deliberately a PARSER-FEATURE probe, not a version compare:
-- the 5.4 architecture parses 5.3 syntax and carries every library TOS
-- uses, so it passes and boots (supported). Only a 5.2 CPU fails —
-- stop HERE with the fix instead of booting into a raw syntax-error
-- panic from a healthy disk.
if not load("return 1<<1")then F("C1","Lua 5.3+ CPU: sneak-click it to switch")end

-- Find the boot device. Stored address first (managed FS or TBFS raw
-- drive — an EEPROM-committed target boots without prompting), then scan
-- managed filesystems, then raw drives. `b` non-nil marks a FALLBACK
-- pick that still needs operator approval (#SEC H1 below).
-- exists() is pcall'd everywhere below: a floppy yanked mid-scan makes
-- the component call RAISE, which otherwise kills the whole scan (and
-- the BIOS) instead of skipping that device.
local function ex(z)
 local k,r=pcall(z.exists,"/init.lua")
 return k and r
end
local a=p.getBootAddress()
local f,b,blob
if a and a~=""then
 local px=X(a)
 if px then
  if px.readSector then blob=T(a)
  elseif px.exists and ex(px)then f=px end
 end
end
if not f and not blob then
 for x in l("filesystem")do
  local z=X(x)
  if z and ex(z)then f,b,a=z,x,x break end
 end
end
if not f and not blob then
 -- EXACT match: OC's component.list filters by SUBSTRING, so a bare
 -- "drive" also returns tape_drive / disk_drive. T() would reject them
 -- (no readSector), but scanning them at all is wrong.
 for x in l("drive",true)do
  local z=T(x)
  if z then blob,b,a=z,x,x break end
 end
end
if not f and not blob then F("D2","Need an /init.lua disk or a TBFS drive")end

-- #SEC H1 — fallback boot needs explicit approval: auto-booting (or
-- worse, auto-flashing setBootAddress for) the first bootable media let
-- anyone with a floppy — or now a raw drive — own the box on the next
-- power cycle. Y commits the EEPROM; Shift+Enter boots once (init.lua
-- refuses to parlay a one-time boot into a persistent rebind); any other
-- key or the 30s timeout halts. Shift is tracked as HELD state because
-- OC delivers key_down(shift) BEFORE key_down(enter) — probing after the
-- fact can never see it. Codes: 42=LShift, 54=RShift, 28=Enter.
local one=false
if b then
 P("Boot drive changed: "..b:sub(1,8),0xffaa00)
 P("Save it? Y=yes Shift+Enter=once other=halt",D)
 local t=p.uptime()+30
 local sh
 repeat
  local ev,_,ch,k=p.pullSignal(t-p.uptime())
  if ev=="key_down"then
   if k==42 or k==54 then sh=true
   elseif ch==89 or ch==121 then
    p.setBootAddress(b)P("Boot drive saved",G)b=nil
   elseif k==28 and sh then
    one=true P("One-time boot",G)b=nil
   else break end
  elseif ev=="key_up"and(k==42 or k==54)then sh=false end
 until not b or p.uptime()>=t
 if b then P("Boot cancelled",R)K()end
end

-- Depth + boot mode are final now; only _BIOS_CY still moves (set at
-- each handoff below).
_G._BIOS_DEPTH=d
_G._BIOS_ONETIME=one

P("POST...",D)

-- ── TBFS raw-drive boot ─────────────────────────────────────
-- The blob embeds the blockfs driver + stage-2 bootstrap: it mounts the
-- drive as root, sets _G._TOS_UNMANAGED_ROOT, and runs /init.lua itself.
if blob then
 -- Text mode only — no bytecode may enter the boot path (see below).
 local fn,er=load(blob,"=tbfs-boot","t")
 if not fn then F("B3",er)end
 -- One short beep = POST passed, the way a PC BIOS signals it. Failure
 -- paths above have their own distinct beeps, so the tones tell the
 -- operator what happened without reading the screen.
 P("POST OK",G)p.beep()
 P("Booting: raw drive "..a:sub(1,8),D)
 _G._BIOS_CY=y
 -- Hand the CHOSEN drive to the bootstrap. getBootAddress may still
 -- point at a managed FS (fresh deploy, EEPROM never committed) and a
 -- blind first-drive scan could mount the wrong volume on a multi-drive
 -- box.
 _G._TBFS_BOOT_DRIVE=a
 local o2,e2=pcall(fn)
 if not o2 then P("TBFS boot failed: "..tostring(e2),R)end
 K()
end

-- ── Managed-FS POST + boot ──────────────────────────────────
-- (/init.lua presence was already the selection criterion; open+load
-- below still catch removal/unreadability/corruption.)
if not f.exists("/tos/kernel/init.lua")then F("K4","/tos/kernel/init.lua is missing")end
local q=f.open("/init.lua","r")
if not q then F("I5","cannot open /init.lua")end
-- Chunk list + table.concat, NOT z=z..chunk: repeated concat churns
-- O(n^2) garbage and can OOM a low-RAM box before any of TOS's
-- resilience layers exist.
local z={}
repeat local x=f.read(q,4096)if x then z[#z+1]=x end until not x
f.close(q)
-- Text mode only: reject bytecode so a tampered /init.lua can't smuggle
-- in pre-compiled chunks (bytecode skips Lua's validity checks).
local fn,er=load(table.concat(z),"=init.lua","t")
if not fn then F("I6",er)end
-- The POST-OK beep, the way a 5150 told you the board came up. This is
-- the branch almost every machine takes; the beep was originally added
-- only to the TBFS branch above, so in practice nothing ever beeped.
-- pcall'd because this is the LAST thing before handing off to the
-- kernel: a box whose beep() is missing must still boot.
P("POST OK",G)pcall(p.beep)
P("Booting: "..(f.getLabel()or a:sub(1,8)),D)
_G._BIOS_CY=y
fn(f)
