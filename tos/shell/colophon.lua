local c={}c.AUTHOR="Evan"
c.NOTE={{"TOS","title"},{"Terminal Operating System","dim"},{"","dim"},{"There was no reason to build this.","fg"},{"","dim"},{"OpenComputers hands you a machine with a couple of","fg"},{"megabytes of memory, a screen eighty characters wide,","fg"},{"and a language with nothing underneath it. You were","fg"},{"meant to write a script. I wrote accounts and","fg"},{"permissions instead, then a shell to reach them,","fg"},{"and then a filesystem that did not need to exist.","fg"},{"","dim"},{"Somewhere in there it stopped being a hobby.","fg"},{"","dim"},{"If you're reading this, you gave it no name and a","fg"},{"number for a password, on the chance that something","fg"},{"was hidden here. I'll be the first to admit that there was.","fg"},{"","dim"},{"Thanks for looking.","accent"}}c.PASSPHRASE="65536"
function c.isTrigger(a,b)if type(b)~="string"then return false end;if a~=
nil and a~=""then return false end;return b==c.PASSPHRASE end
local d={title="highlight",accent="highlight",dim="dim",fg="fg"}
function c.layout(e,b,a,f)a=a or c.NOTE;local g=0;for l,k in ipairs(a)do local m=#k[1]if f then m=f(k[1])end
if m>g then g=m end end
if b<#a+4 or e<g+2 then return nil end
local i=math.max(2,math.floor((b-#a-2)/2))
local j=math.max(1,math.floor((e-g)/2)+1)local h={}for l,k in ipairs(a)do if k[1]~=""then
h[#h+1]={x=j,y=i+l-1,text=k[1],role=k[2]}end end;return h,math.min(
b-1,i+#a+1)end
function c.run(a)local b=a.theme or{}local e=b.bg or 0x000000;local function i(k)local l=d[k]or"fg"return
b[l]or b.fg or 0xFFFFFF end
local f,g=c.layout(a.W,a.H,c.NOTE,a.width)a.clear(e)
if not f then
a.set(1,1,"Thanks for looking.  - "..c.AUTHOR,b.highlight or b.fg or
0xFFFFFF,e)a.sleep(3)return nil end;local h=false
for l,k in ipairs(f)do a.set(k.x,k.y,k.text,i(k.role),e)if not h then
local m=a.pull(0.12)if m=="key_down"then h=true end end end
a.set(f[1].x,g-1,"- "..c.AUTHOR,b.dim or b.fg or 0xFFFFFF,e)a.sleep(0.8)
a.set(f[1].x,g+1,"(any key)",b.dim or 0xAAAAAA,e)
local j=(a.uptime and a.uptime()or 0)+120
while true do local k=a.pull(0.5)if k=="key_down"then break end;if
a.uptime and a.uptime()>=j then break end end;return nil end;return c