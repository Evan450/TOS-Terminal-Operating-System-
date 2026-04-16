-- TOS BIOS
local c,p=component,computer
local e=c.list("eeprom")()
p.getBootAddress=function() return c.invoke(e,"getData") end
p.setBootAddress=function(a) return c.invoke(e,"setData",a) end

-- GPU
local g,s
for a in c.list("gpu") do g=c.proxy(a) break end
for a in c.list("screen") do s=a break end
local W,H=50,16
local depth=1
if g and s then
  g.bind(s)
  local mw,mh=g.maxResolution()
  W,H=math.min(80,mw),mh
  g.setResolution(W,H)
  -- Detect color depth (T1=1-bit, T2=4-bit, T3=8-bit)
  local ok,d=pcall(g.getDepth)
  if ok and d then depth=d end
  g.setBackground(0x000000)
  g.setForeground(depth<=1 and 0xFFFFFF or 0x00FF00)
  g.fill(1,1,W,H," ")
end
-- Tier-safe colors: T1 only has black/white
local function tc(color) return depth<=1 and 0xFFFFFF or color end
local cy=1
local function pr(t,fg)
  if not g then return end
  if fg then g.setForeground(tc(fg)) end
  if cy>H then g.copy(1,2,W,H-1,0,-1) cy=H end
  g.fill(1,cy,W,1," ") g.set(1,cy,tostring(t):sub(1,W)) cy=cy+1
end

pr("TOS BIOS",tc(0x00FF00))

-- Find boot FS
local addr=p.getBootAddress()
local fs
if addr and addr~="" then
  local ok,px=pcall(c.proxy,addr)
  if ok and px then fs=px end
end
if not fs or not fs.exists("/init.lua") then
  fs=nil
  for a in c.list("filesystem") do
    local ok,px=pcall(c.proxy,a)
    if ok and px and px.exists("/init.lua") then fs=px p.setBootAddress(a) break end
  end
end
if not fs then
  pr("NO BOOT DEVICE!",0xFF0000)
  pr("Need drive with /init.lua",0xAAAAAA)
  p.beep(1000,0.5)
  while true do p.pullSignal(1e9) end
end

-- ── POST (Power-On Self-Test) ──────────────────────────
-- Tier 1: BIOS-level quick checks before loading anything.
-- Ensures the system can actually boot rather than erroring out.
pr("POST...",0xAAAAAA)

-- POST check 1: /init.lua exists
if not fs.exists("/init.lua") then
  pr("POST FAIL: /init.lua missing!",0xFF0000)
  p.beep(800,0.3) p.beep(400,0.3)
  while true do p.pullSignal(1e9) end
end

-- POST check 2: /tos/kernel/init.lua exists (kernel is present)
if not fs.exists("/tos/kernel/init.lua") then
  pr("POST FAIL: kernel missing!",0xFF0000)
  pr("  /tos/kernel/init.lua not found",0xFF6600)
  p.beep(800,0.3) p.beep(400,0.3)
  while true do p.pullSignal(1e9) end
end

-- POST check 3: /init.lua compiles
local h=fs.open("/init.lua","r")
if not h then
  pr("POST FAIL: Cannot open /init.lua!",0xFF0000)
  while true do p.pullSignal(1e9) end
end
local parts={}
repeat local ch=fs.read(h,4096) if ch then parts[#parts+1]=ch end until not ch
fs.close(h)
local fn,er=load(table.concat(parts),"=init.lua")
if not fn then
  pr("POST FAIL: /init.lua syntax error",0xFF0000)
  pr("  "..tostring(er),0xFF6600)
  pr("Press any key to reboot...",0xAAAAAA)
  p.pullSignal(1e9)
  p.shutdown(true)
end

pr("POST OK",tc(0x00FF00))
pr("Booting from "..(fs.getLabel() or "disk").."...",0xAAAAAA)

-- Pass cursor position and GPU depth to init.lua
_G._BIOS_CY=cy
_G._BIOS_DEPTH=depth
fn(fs)
