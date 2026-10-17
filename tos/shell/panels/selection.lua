local d="number"local c={}
function c.range(a,b)
if type(a)~=d or type(b)~=d then return nil end;local e,f=a,b;if e>f then e,f=f,e end;if e==f then return nil end;return e,f end
function c.text(a,b,e)local f,g=c.range(b,e)if not f then return nil end;return tostring(a or""):sub(f,
g-1)end
function c.remove(a,e,b)a=tostring(a or"")local f,g=c.range(e,b)
if not f then return a,nil,b end;return a:sub(1,f-1)..a:sub(g),a:sub(f,g-1),f end
function c.insert(a,b,e)a=tostring(a or"")e=tostring(e or"")b=math.max(1,math.min(#a+1,b or(
#a+1)))return
a:sub(1,b-1)..e..a:sub(b),b+#e end
function c.replace(b,e,a,f)local g,i,h=c.remove(b,e,a)return c.insert(g,h or a,f)end
function c.orderPos(e,f)
if type(e)~="table"or type(f)~="table"then return nil end;local a,g=e.row or 1,e.col or 1;local b,h=f.row or 1,f.col or 1;if
a==b and g==h then return nil end
if a>b or(a==b and g>h)then a,g,b,h=b,h,a,g end;return{row=a,col=g},{row=b,col=h}end
function c.extract(e,f,g)local a,b=c.orderPos(f,g)if not a then return nil end;e=e or{}
if
a.row==b.row then local i=e[a.row]or""return{i:sub(a.col,b.col-1)}end
local h={(e[a.row]or""):sub(a.col)}for i=a.row+1,b.row-1 do h[#h+1]=e[i]or""end;h[#h+1]=(
e[b.row]or""):sub(1,b.col-1)return h end
function c.removeBlock(e,f,g)local a,b=c.orderPos(f,g)if not a then return nil end
local h=c.extract(e,a,b)local i=(e[a.row]or""):sub(1,a.col-1)local j=(
e[b.row]or""):sub(b.col)for k=a.row+1,b.row do table.remove(e,
a.row+1)end;e[a.row]=i..j;if#e==0 then
e[1]=""end;return h,a.row,a.col end
function c.insertBlock(b,e,f,a)b=b or{}a=a or{}if#a==0 then return e,f end;if#b==0 then b[1]=""end;e=math.max(1,math.min(
#b,e or 1))local g=b[e]or""f=math.max(1,math.min(
#g+1,f or 1))
local h,i=g:sub(1,f-1),g:sub(f)if#a==1 then b[e]=h..a[1]..i;return e,f+#a[1]end;b[e]=h..
a[1]
for l=2,#a do table.insert(b,e+l-1,a[l])end;local j=e+#a-1;local k=#a[#a]+1;b[j]=a[#a]..i;return j,k end
function c.contains(g,h,e,f)local a,b=c.orderPos(g,h)if not a then return false end;if
e<a.row or e>b.row then return false end
if e==a.row and f<a.col then return false end;if e==b.row and f>=b.col then return false end;return true end
function c.lineRange(a,b)if type(a)~=d or type(b)~=d then return nil end;if a>b then
return b,a end;return a,b end
function c.lines(a,b,e)local g,h=c.lineRange(b,e)if not g then return nil end;a=a or{}local f={}for j=math.max(1,g),math.min(
#a,h)do local i=a[j]
if type(i)=="table"then
f[#f+1]=tostring(i[1]or"")else f[#f+1]=tostring(i or"")end end;if#f==0 then
return nil end;return f end;return c