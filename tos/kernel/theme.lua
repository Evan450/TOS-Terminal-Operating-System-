local v="default"local m={}local w=".theme.cfg"local q,o,p,u
local r={default={description="TOS classic — teal frames, gold titles on black",bg=0x000000,fg=0xE6E6E6,border=0x2FB8C6,title=0xFFD75A,highlight=0x42D77D,dim=0x909090,selected_bg=0x0E5E70,selected_fg=0xFFFFFF,menubar_bg=0x262B33,menubar_fg=0xE6E6E6,menubar_hot=0xFFD75A,statusbar_bg=0x103C4E,statusbar_fg=0xBFE3EE,error=0xFF5C57,warning=0xFFA042,panel_bg=0x000000,input_bg=0x14181E,input_fg=0xFFFFFF,syn_keyword=0x61AFEF,syn_string=0x98C379,syn_comment=0x7A828E,syn_number=0xD19A66,syn_func=0xE5C07B,file_lua=0x56B6C2,dir_color=0x42D77D},midnight={description="Tokyo night — indigo panels, neon accents",bg=0x0D1420,fg=0xD6E2F0,border=0x3E7CB8,title=0x9CC4F0,highlight=0x59C2A0,dim=0x7388A6,selected_bg=0x24466B,selected_fg=0xFFFFFF,menubar_bg=0x16243A,menubar_fg=0xC4D6EC,menubar_hot=0xF0B35E,statusbar_bg=0x16243A,statusbar_fg=0x8FB2D9,error=0xE8606B,warning=0xE8B44C,panel_bg=0x0D1420,input_bg=0x1A2C46,input_fg=0xF0F6FF,syn_keyword=0x7AA2F7,syn_string=0x9ECE6A,syn_comment=0x565F89,syn_number=0xFF9E64,syn_func=0xE0AF68,file_lua=0x7DCFFF,dir_color=0x73DACA},amber={description="Retro CRT — warm amber phosphor",bg=0x0A0500,fg=0xFFB000,border=0xCC8400,title=0xFFD75A,highlight=0xFFE599,dim=0x8F5E00,selected_bg=0xFFB000,selected_fg=0x1A0D00,menubar_bg=0x241200,menubar_fg=0xFFB000,menubar_hot=0xFFE599,statusbar_bg=0x241200,statusbar_fg=0xCC8400,error=0xFF5C57,warning=0xFFE599,panel_bg=0x0A0500,input_bg=0x1A0D00,input_fg=0xFFC840,syn_keyword=0xFFD75A,syn_string=0xE59E00,syn_comment=0x8F5E00,syn_number=0xFFE599,syn_func=0xFFC840,file_lua=0xFFC840,dir_color=0xFFD75A},green={description="Matrix — green phosphor on black",bg=0x020A02,fg=0x3FD23F,border=0x2AA62A,title=0xA8F0A8,highlight=0x88E888,dim=0x1E7A1E,selected_bg=0x3FD23F,selected_fg=0x031003,menubar_bg=0x0A2410,menubar_fg=0x66E866,menubar_hot=0xCCFFCC,statusbar_bg=0x0A2410,statusbar_fg=0x2AA62A,error=0xFF5C57,warning=0xE8E84C,panel_bg=0x020A02,input_bg=0x07180A,input_fg=0x88E888,syn_keyword=0x88E888,syn_string=0x2AA62A,syn_comment=0x1E7A1E,syn_number=0xCCFFCC,syn_func=0xA8F0A8,file_lua=0x66E866,dir_color=0x88E888},plasma={description="Plasma display — neon red-orange on black (night-vision friendly)",bg=0x000000,fg=0xFF6A33,border=0xCC4A1F,title=0xFFA64D,highlight=0xFFC78F,dim=0x8F2E14,selected_bg=0xFF6A33,selected_fg=0x1F0900,menubar_bg=0x260C00,menubar_fg=0xFF6A33,menubar_hot=0xFFC78F,statusbar_bg=0x260C00,statusbar_fg=0xCC4A1F,error=0xFF2424,warning=0xFF8A1F,panel_bg=0x000000,input_bg=0x1F0900,input_fg=0xFFA64D,syn_keyword=0xFFA64D,syn_string=0xCC4A1F,syn_comment=0x8F2E14,syn_number=0xFFC78F,syn_func=0xFF8A1F,file_lua=0xFF8A1F,dir_color=0xFFC78F},classic={description="Norton-style — white on blue, cyan bars",bg=0x0000A8,fg=0xFFFFFF,border=0x55FFFF,title=0xFFFF55,highlight=0x55FF55,dim=0xA8B8D8,selected_bg=0x00A8A8,selected_fg=0x000000,menubar_bg=0x00A8A8,menubar_fg=0x000000,menubar_hot=0xFFFF55,statusbar_bg=0x00A8A8,statusbar_fg=0x000000,error=0xFF5555,warning=0xFFAA55,panel_bg=0x0000A8,input_bg=0x000054,input_fg=0xFFFF55,syn_keyword=0x55FFFF,syn_string=0x55FF55,syn_comment=0xA8B8D8,syn_number=0xFFAA55,syn_func=0xFFFF55,file_lua=0x55FFFF,dir_color=0x55FF55},contrast={description="High contrast — readability first",bg=0x000000,fg=0xFFFFFF,border=0xFFFFFF,title=0xFFFF00,highlight=0xFFFFFF,dim=0xD0D0D0,selected_bg=0xFFFF00,selected_fg=0x000000,menubar_bg=0xFFFFFF,menubar_fg=0x000000,menubar_hot=0xAA0000,statusbar_bg=0xFFFFFF,statusbar_fg=0x000000,error=0xFF4040,warning=0xFF9900,panel_bg=0x000000,input_bg=0x000000,input_fg=0xFFFFFF,syn_keyword=0xFFFFFF,syn_string=0xFFFF00,syn_comment=0xD0D0D0,syn_number=0xFFFF00,syn_func=0xFFFFFF,file_lua=0xFFFFFF,dir_color=0xFFFF00},nord={description="Nord — arctic blues and frost",bg=0x2E3440,fg=0xD8DEE9,border=0x81A1C1,title=0x88C0D0,highlight=0xA3BE8C,dim=0x616E88,selected_bg=0x434C5E,selected_fg=0xECEFF4,menubar_bg=0x3B4252,menubar_fg=0xD8DEE9,menubar_hot=0xEBCB8B,statusbar_bg=0x3B4252,statusbar_fg=0x88C0D0,error=0xBF616A,warning=0xEBCB8B,panel_bg=0x2E3440,input_bg=0x434C5E,input_fg=0xECEFF4,syn_keyword=0x81A1C1,syn_string=0xA3BE8C,syn_comment=0x616E88,syn_number=0xB48EAD,syn_func=0x88C0D0,file_lua=0x88C0D0,dir_color=0xA3BE8C},solarized={description="Solarized dark — muted teal + earth accents",bg=0x002B36,fg=0x93A1A1,border=0x268BD2,title=0xB58900,highlight=0x859900,dim=0x586E75,selected_bg=0x586E75,selected_fg=0xFDF6E3,menubar_bg=0x073642,menubar_fg=0x93A1A1,menubar_hot=0xCB4B16,statusbar_bg=0x073642,statusbar_fg=0x2AA198,error=0xDC322F,warning=0xCB4B16,panel_bg=0x002B36,input_bg=0x073642,input_fg=0xFDF6E3,syn_keyword=0x268BD2,syn_string=0x2AA198,syn_comment=0x586E75,syn_number=0xD33682,syn_func=0xB58900,file_lua=0x2AA198,dir_color=0x859900}}
local s={bg=true,fg=true,border=true,title=true,highlight=true,dim=true,selected_bg=true,selected_fg=true,menubar_bg=true,menubar_fg=true,menubar_hot=true,statusbar_bg=true,statusbar_fg=true,error=true,warning=true,panel_bg=true,input_bg=true,input_fg=true,syn_keyword=true,syn_string=true,syn_comment=true,syn_number=true,syn_func=true,file_lua=true,dir_color=true}local n={preset=v,overrides={}}
function m.init(a)q=a.display;o=a.securefs;p=a.log;u=a.serialize or
require("kernel.serialize")end
function m.list()local a={}for b in pairs(r)do a[#a+1]=b end;table.sort(a)return a end;function m.preset(a)return r[a]end;function m.describe(a)local b=r[a]return
b and b.description or nil end;function m.current()return
{preset=n.preset,overrides=n.overrides}end;function m.isOverridable(a)return
s[a]==true end;function m.overridableKeys()local a={}
for b in pairs(s)do a[#a+1]=b end;table.sort(a)return a end
local function x(b,a)if
not q then return false,"display module not available"end;if
q.isMonochrome and q.isMonochrome()then
return false,"Color themes require a Tier 2+ GPU (display is monochrome)"end;local c={}for d,e in pairs(b)do if d~=
"description"then c[d]=e end end;if a then for d,e in pairs(a)do if s[d]then
c[d]=e end end end
q.setTheme(c)return true end
function m.apply(a,b)local c=r[a]
if not c then return false,"Unknown theme: "..tostring(a)end;local d,e=x(c,b)if not d then return false,e end;n.preset=a;n.overrides=b or{}
if p then p.info("theme",
"Applied preset '"..a.."'")end;return true end
function m.setColor(b,a)if not s[b]then
return false,"Not an overridable color: "..tostring(b)end;if type(a)~="number"then return false,
"Color must be a number (e.g. 0xFF8800)"end
if a<0 or
a>0xFFFFFF then return false,"Color out of range (0x000000 - 0xFFFFFF)"end;n.overrides[b]=a;return m.apply(n.preset,n.overrides)end
function m.resetOverrides()n.overrides={}return m.apply(n.preset,n.overrides)end
local function t(a)if not a or not a.home then return nil end;return a.home:gsub("/$","")..
"/"..w end
function m.hasSavedTheme(a)local b=t(a)if not b or not o then return false end
local c,d=pcall(o.exists,b,a)return c and d==true end
function m.saveForUser(a)local b=t(a)
if not b then return false,"no session / no home"end;if not o then return false,"securefs not available"end
local d={preset=n.preset,overrides=n.overrides}local e,c=pcall(u.encode,d)if not e then
return false,"serialize failed: "..tostring(c)end;local f,g=o.writeFile(b,c,a)
if not f then return false,g end;if p then
p.info("theme","Saved theme for "..a.user.." -> "..b)end;return true end
function m.applyForUser(a)local b=t(a)
if not b or not o then return false,"no session"end;if not o.exists(b,a)then return false,"no saved theme"end
local d,g=o.readFile(b,a)if not d then return false,g or"read failed"end
if#d>8192 then if p then
p.warn("theme",
"Theme file too large at "..b.." ("..#d.." bytes)")end;return false,"theme file too large"end;local h,e=pcall(u.decode,d,{maxBytes=8192})
if not h or
type(e)~="table"then if p then
p.warn("theme","Corrupt theme file at "..b)end;return false,"corrupt theme file"end;local c=e.preset or v
if not r[c]then if p then
p.warn("theme","Unknown preset '"..
tostring(c).."', falling back to default")end;c=v end;local f={}
if type(e.overrides)=="table"then for y,l in pairs(e.overrides)do
if s[y]and
type(l)=="number"and l>=0 and l<=0xFFFFFF then f[y]=l end end end;local i,j=m.apply(c,f)if not i then return false,j end;return true,c end
function m.clearForUser(a)local b=t(a)
if not b or not o then return false,"no session"end
if o.exists(b,a)then local c,d=o.remove(b,a)if not c then return false,d end end;n.overrides={}return m.apply(v)end;return m