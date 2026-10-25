local K,L="No printer available: ","center"local A=require("printer")
local G=require("printerfmt")local y=0xFF5555;local E=0xFF9900;local C=0x55FF55;local z=0xAAAAAA;local D=0xFFFF55;local B=0xFFFFFF
local function M(a)
local b,c={},{}
for d=1,#a do local e=tostring(a[d])
local f,g=e:match("^%-%-([%w%-]+)=(.*)$")
if f then c[f]=g elseif e:match("^%-%-[%w%-]+$")then c[e:sub(3)]=true else b[#b+1]=e end end;return b,c end
local function N()return fs and fs.readFile and fs.exists end
local function O(a)local b,e=A.status()
if not b then a(K..tostring(e),y)
if
tostring(e):find("cap")then
a("This program was not granted the peripheral.printer capability.",z)else
a("Place an OpenPrinter next to (or on the network with) this computer.",z)end;return end
a("Printer "..tostring(b.address):sub(1,8).."...",D)
local function d(g,f,h)if f==nil then
a(string.format("  %-12s %s",g,"(not reported by this printer)"),z)else
a(string.format("  %-12s %d",g,f),f<=h and E or B)end end;d("paper",b.paper,4)d("black ink",b.black,10)
d("colour ink",b.color,10)
a(string.format("  %-12s %d px x %d lines","page",b.maxWidth,b.maxLines),B)local c={}
for g,f in
ipairs({"width","maxWidth","scan","scanBook","printTag"})do if not b.features[f]then c[#c+1]=f end end;if#c>0 then
a("  older build: no "..table.concat(c,", "),z)end end;local H=64*1024
local function I(a,b)
if not N()then b("No filesystem access.",y)return nil end
if not fs.exists(a)then b("No such file: "..a,y)return nil end;local d,c=pcall(fs.readFile,a)if not d or not c then
b("Cannot read "..a.. (d and""or
(": "..tostring(c))),y)return nil end
if#c>H then
b(string.format("%s is %d bytes; the limit is %d.",a,
#c,H),y)
b("Split it, or print the part you want with `head`/`tail` into a file.",z)return nil end;return c end
local function J(a)
local b={title=a.title~=true and a.title or nil,align=a.center and L or"left",wrap=not
a["no-wrap"],force=a.force==true}
if a.copies then b.copies=tonumber(a.copies)if not b.copies then
return nil,"--copies needs a number"end end;if a.color then
b.color=tonumber(a.color)or tonumber(a.color,16)
if not b.color then return nil,"--color needs a number like 0xFF0000"end end;return b end;local function F(a,b)
b(string.format("  %d sheet(s), %d black, %d colour",a.paper,a.black,a.color),z)end
local function P(c,b,a)local e=c[2]if not e then
a("Usage: printer file <path> [--title=T] [--copies=N] [--center]",z)return end;local g=I(e,a)
if not g then return end;local d,k=J(b)if not d then a(tostring(k),y)return end;d.title=d.title or
e:match("[^/]+$")if not A.available()then a(K..
tostring(A.unavailableReason()),y)
a("`printer preview "..e..
"` still works without one.",z)return end
local f=A.job(d.title)local l,m=f:text(g,d)if not l then a(tostring(m),y)return end;if
d.copies then local q,r=f:copies(d.copies)
if not q then a(tostring(r),y)return end end;local h=f:cost()if b["dry-run"]then
a("Would print:",D)F(h,a)return end;local n,o=f:check()if
not n and not d.force then a("Refused: "..tostring(o),y)F(h,a)
a("Load more, or pass --force to try anyway.",z)return end
local i,p,j=f:commit(d)
if not i then a("Print failed: "..tostring(p),y)if
(j or 0)>0 then
a(string.format("%d page(s) DID print — check the output slots before reprinting.",j),E)end;return end
a(string.format("Printed %d page(s) of %s.",i,e),C)end
local function Q(b,c,a)local f=b[2]if not f then
a("Usage: printer preview <path> [--center] [--no-wrap]",z)return end;local g=I(f,a)if not g then return end
local d,j=J(c)if not d then a(tostring(j),y)return end
local h,i=G.width,"estimated widths"
if A.available()then local n,m=A.width("M")h=A.measurer()if m=="component"then
i="the attached printer's own metrics"end;d.maxWidth=A.maxWidth()end;d.measure=h;local e,k=G.layout(g,d)
if not e then a(tostring(k),y)return end
for m,n in ipairs(e)do
a(string.format("── page %d/%d ─────────────────",m,#e),D)for p,o in ipairs(n)do
a("  ".. (o.text~=""and o.text or"~"),
o.text~=""and B or z)end end;local l=G.cost(e,d.copies or 1)
a(string.format("%d page(s), laid out using %s.",#e,i),z)F(l,a)end
local function R(b,a)if not A.available()then
a(K..tostring(A.unavailableReason()),y)return end
local c=A.job("TOS test page")c:line("TOS PRINTER TEST",nil,L)c:blank()
c:line("If you are reading this off a printed page, the")
c:line("driver, the capability and the printer all work.")c:blank()c:line("Left aligned.")
c:line("Centred.",nil,L)c:blank()c:line("Widest line the page will hold:")
local e,d=A.maxWidth(),""
for j=1,e do local k=(A.width(d.."#"))if k>e then break end;d=d.."#"end;c:line(d)local f=c:cost()if b["dry-run"]then
a("Would print the test page:",D)F(f,a)return end;local g,h,i=c:commit(b)if not g then a(
"Test print failed: "..tostring(h),y)
if
(i or 0)>0 then a("(some pages did come out)",E)end;return end
a("Test page printed. Check the output slots.",C)end
local function S(b,a)local c,e=A.scan()if not c then
a("Scan failed: "..tostring(e),y)return end;if type(c)~="table"then
a("Nothing in the input slot.",E)return end;local d=b[2]
if d then
if
not(fs and fs.writeFile)then a("No filesystem access.",y)return end;local f=table.concat(c,"\n")local g,h=pcall(fs.writeFile,d,f)if
not g then
a("Cannot write "..d..": "..tostring(h),y)return end
a(string.format("Scanned %d line(s) into %s.",#c,d),C)return end;for f,g in ipairs(c)do
a(string.format("%3d  %s",f,tostring(g)),B)end;if#c==0 then
a("(the page is blank)",z)end end
local function T(b,a)
local c=table.concat({table.unpack(b,2)}," ")
if c==""then a("Usage: printer tag <text>",z)return end;local d,e=A.tag(c)if not d then
a("Tag failed: "..tostring(e),y)return end;a("Name tag printed.",C)end
local function U(a)a("printer — OpenPrinter driver",D)
a("  printer                    Attached printer and its levels",B)
a("  printer test               Print one test page",B)
a("  printer file <path>        Print a text file",B)
a("  printer preview <path>     Paginate it without printing",B)
a("  printer scan [<path>]      Read the page in the input slot",B)
a("  printer tag <text>         Print a name tag",B)
a("  printer clear              Empty the printer's buffer",B)a("Flags for file/preview:",z)
a("  --title=T  --copies=N  --center  --color=0xRRGGBB",z)a("  --no-wrap  --dry-run   --force",z)
a("Colour costs one unit of colour ink PER LINE; leave it off for black.",z)end
local function V(b,a)b=b or{}local d,e=M(b)local c=d[1]
if c==nil or c=="status"then O(a)elseif c=="help"then U(a)elseif
c=="test"then R(e,a)elseif c=="file"or c=="print"then P(d,e,a)elseif c=="preview"then Q(d,e,a)elseif c=="scan"then
S(d,a)elseif c=="tag"then T(d,a)elseif c=="clear"then local g,f=A.clear()
if g==nil and f then
a("Clear failed: "..tostring(f),y)else a("Printer buffer cleared.",C)end else
a("Unknown subcommand: "..tostring(c),y)a("Try 'printer help'.",z)end end;return{commands={printer=V}}