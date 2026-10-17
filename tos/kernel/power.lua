local u=require("computer")local p={}local r=false;local v=100;local A=0;local C=5
local s={low=false,critical=false}local w=15;local x=5;local y=nil;local z=nil;local q=nil;local t=nil
function p.init(a)q=a.log;t=a.config;r=
t and t.isTablet()or false
if t then
w=t.get("lowBatWarn")or 15;x=t.get("critBatWarn")or 5 end
if r then if q then
q.info("power","Tablet mode: battery monitoring active")end else if q then
q.debug("power","Computer mode: power monitor idle")end end;return true end
function p.level()if not r then return 100 end;local a=u.uptime()
if a-A>=C then local c=u.energy()
local b=u.maxEnergy()if b>0 then v=math.floor((c/b)*100)else v=100 end;A=a end;return v end;function p.energy()return u.energy(),u.maxEnergy()end;function p.isActive()
return r end
function p.check()if not r then return end;local a=p.level()
if
a<=x and not s.critical then s.critical=true;if q then
q.error("power","CRITICAL: Battery at "..a.."%!")end;if z then z(a)end elseif a<=w and not s.low then s.low=true
if q then q.warn("power",
"Low battery: "..a.."%")end;if y then y(a)end end;if a>x+5 then s.critical=false end;if a>w+5 then s.low=false end end;function p.onLow(a)y=a end;function p.onCritical(a)z=a end
function p.statusString()if not r then return nil end
local b=p.level()local a
if b>75 then a="█"elseif b>50 then a="▓"elseif b>25 then a="▒"else a="░"end;return string.format("%s%d%%",a,b)end
p.PROFILES={off={idleSec=1,blankSec=0,buffer="auto"},balanced={idleSec=1,blankSec=600,buffer="auto"},save={idleSec=5,blankSec=120,buffer="on"}}local D={"off","balanced","save"}p.PROFILE_ORDER=D
function p.normalizeProfile(a)
a=tostring(a or""):lower()
if a=="none"or a=="performance"or a=="full"then a="off"end;if a=="default"or a=="normal"then a="balanced"end
if
a=="saver"or a=="low"or a=="conserve"then a="save"end;return p.PROFILES[a]and a or nil end;local B=nil
function p.applyProfile(a)local b=p.normalizeProfile(a)
if not b then return nil,"unknown power profile: "..
tostring(a)end;local c=p.PROFILES[b]B=b;local d=_G._TOS;if d then d.powerIdleSec=c.idleSec
d.screenBlankSec=c.blankSec end;if q then
q.info("power","Profile '"..b..
"': idle "..c.idleSec.."s, blank "..
(c.blankSec>0 and(
c.blankSec.."s")or"never"))end;return b end;function p.profile()return B or"off"end
function p.idleSeconds()
local a=tonumber(_G._TOS and _G._TOS.powerIdleSec)return(a and a>0)and a or 1 end
function p.blankSeconds()
local a=tonumber(_G._TOS and _G._TOS.screenBlankSec)return(a and a>0)and a or 0 end
function p.shouldBlank(b,c,d,a)if d then return false end;a=a or p.blankSeconds()if a<=0 then
return false end;b=tonumber(b)or 0;return
(b- (tonumber(c)or 0))>=a end
function p.setKnob(b,a)a=tonumber(a)
if not a or a<0 then return nil,"expected a number of seconds"end;local c=_G._TOS
if b=="idle"then
if a<1 then return nil,"idle cadence must be at least 1 second"end;if c then c.powerIdleSec=a end;return a elseif b=="blank"then
if a>0 and a<10 then return nil,
"blank timeout must be 0 (off) or at least 10 seconds"end;if c then c.screenBlankSec=a end;return a end;return nil,"unknown knob: "..tostring(b)end;return p