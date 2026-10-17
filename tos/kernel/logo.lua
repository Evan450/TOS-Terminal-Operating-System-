local c={}
c.MARK={"████████  ████████  ████████","   ██     ██    ██  ██      ","   ██     ██    ██  ████████","   ██     ██    ██        ██","   ██     ████████  ████████"}c.MARK_W=28
c.MARK_ASCII={"TTTTTTT  OOOOOO  SSSSSS","   T     O    O  S     ","   T     O    O  SSSSSS","   T     O    O       S","   T     OOOOOO  SSSSSS"}c.MARK_ASCII_W=23;c.TAGLINE="Terminal Operating System"
c.VENDOR="Strata Systems LLC"c.MOTTO="Firmware with a will of its own."
c.COLORS={mark=0x00AAFF,tagline=0xFFFFFF,vendor=0x00FF66,motto=0x888888,blank=0xFFFFFF}
local function d(b,a,e)if e~=nil then return string.rep(" ",e)end
if not a or a<=b then return""end;return string.rep(" ",math.floor((a-b)/2))end
function c.banner(a)a=a or{}local e=a.width or 50
local f=a.ascii and c.MARK_ASCII or c.MARK;local g=a.ascii and c.MARK_ASCII_W or c.MARK_W
local b={}
for i,h in ipairs(f)do b[#b+1]={d(g,e,a.indent)..h,"mark"}end;b[#b+1]={"","blank"}
b[#b+1]={d(#c.TAGLINE,e,a.indent)..c.TAGLINE,"tagline"}if not a.compact then
b[#b+1]={d(#c.VENDOR,e,a.indent)..c.VENDOR,"vendor"}
b[#b+1]={d(#c.MOTTO,e,a.indent)..c.MOTTO,"motto"}end;return b end;return c