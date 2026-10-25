local j="number"local f={}
local i={{1,2,3},{4,5,6},{7,8,9},{1,4,7},{2,5,8},{3,6,9},{1,5,9},{3,5,7}}f.LINES=i;function f.newBoard()return{}end
function f.winner(a)
for c,b in ipairs(i)do local d=a[b[1]]if d and
a[b[2]]==d and a[b[3]]==d then return d,b end end;for b=1,9 do if not a[b]then return nil end end;return"draw"end;local function g(a)return(a=="X")and"O"or"X"end;f.other=g
local function h(a,d,e,k,b,c)
local l=f.winner(a)if l==e then return 10-k end;if l==g(e)then return k-10 end
if l=="draw"then return 0 end
if d==e then local m=-math.huge;for n=1,9 do
if not a[n]then a[n]=d;local o=h(a,g(d),e,k+1,b,c)
a[n]=nil;if o>m then m=o end;if m>b then b=m end;if b>=c then break end end end
return m else local m=math.huge;for n=1,9 do
if not a[n]then a[n]=d;local o=h(a,g(d),e,k+1,b,c)a[n]=nil
if o<m then m=o end;if m<c then c=m end;if b>=c then break end end end
return m end end
function f.bestMove(a,b,c)if f.winner(a)then return nil end;local e,d=nil,{}
for k=1,9 do
if not a[k]then a[k]=b;local l=h(a,g(b),b,1,-
math.huge,math.huge)a[k]=nil;if not e or l>e then
e,d=l,{k}elseif l==e then d[#d+1]=k end end end;if#d==0 then return nil end;if c then return d[c(#d)]end;return d[1]end
function f.selfPlay(a)a=tonumber(a)or 1;local c=f.newBoard()local k,d,e={},"X",0
while not
f.winner(c)do e=e+1
local b=f.bestMove(c,d,function(m)
return((a*7+e*13+a*e)%m)+1 end)if not b then break end;f.play(c,b,d)local l={}for m=1,9 do l[m]=c[m]end
k[#k+1]=l;d=g(d)end;return{boards=k,result=f.winner(c)or"draw"}end
function f.play(c,a,d)if type(a)~=j or a<1 or a>9 then return false end;if
c[a]or f.winner(c)then return false end;c[a]=d;return true end
function f.step(a,b)
if b=="up"then return((a-3-1)%9)+1 elseif b=="down"then return
((a+3-1)%9)+1 elseif b=="left"then return((a-2)%9)+1 elseif b=="right"then return(a%9)+1 end;return a end
function f.cellAt(a,b,e,k,c,d)if type(a)~=j or type(b)~=j then return nil end;local l,m
for n=0,2 do local o=
e+n* (c+1)if a>=o and a<o+c then l=n;break end end
for n=0,2 do local o=k+n* (d+1)if b>=o and b<o+d then m=n;break end end;if not l or not m then return nil end;return m*3+l+1 end;return f