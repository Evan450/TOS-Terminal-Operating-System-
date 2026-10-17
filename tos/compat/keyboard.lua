local c={}
c.keys={a=30,b=48,c=46,d=32,e=18,f=33,g=34,h=35,i=23,j=36,k=37,l=38,m=50,n=49,o=24,p=25,q=16,r=19,s=31,t=20,u=22,v=47,w=17,x=45,y=21,z=44,["1"]=2,["2"]=3,["3"]=4,["4"]=5,["5"]=6,["6"]=7,["7"]=8,["8"]=9,["9"]=10,["0"]=11,f1=59,f2=60,f3=61,f4=62,f5=63,f6=64,f7=65,f8=66,f9=67,f10=68,f11=87,f12=88,back=14,tab=15,enter=28,lshift=42,rshift=54,lcontrol=29,rcontrol=157,lmenu=56,rmenu=184,space=57,capital=58,numlock=69,scroll=70,up=200,down=208,left=203,right=205,home=199,["end"]=207,pageUp=201,pageDown=209,insert=210,delete=211,numpad0=82,numpad1=79,numpad2=80,numpad3=81,numpad4=75,numpad5=76,numpad6=77,numpad7=71,numpad8=72,numpad9=73,numpadmul=55,numpadsub=74,numpadadd=78,numpaddecimal=83,numpadenter=156,minus=12,equals=13,lbracket=26,rbracket=27,semicolon=39,apostrophe=40,grave=41,backslash=43,comma=51,period=52,slash=53}do local a={}for b in pairs(c.keys)do a[#a+1]=b end
for e,b in ipairs(a)do
local f=c.keys[b]if c.keys[f]==nil then c.keys[f]=b end end end
local function d()
local f,a=pcall(require,"kernel.screen")
if not f or type(a)~="table"or not a.callerSeat or not
a.seatDevices then return nil end;local g,b=pcall(a.callerSeat)if not g or b==nil then return nil end
local h,e=pcall(a.seatDevices,b)if not h or type(e)~="table"then return{}end
return e.keyboards or{}end
function c.isKeyDown(a)local e,b=pcall(require,"kernel.process")if not e or
type(b)~="table"or type(b.keyDown)~="function"then return
false end
return b.keyDown(a,d())==true end;function c.isAltDown()return
c.isKeyDown(c.keys.lmenu)or c.isKeyDown(c.keys.rmenu)end;function c.isControlDown()
return
c.isKeyDown(c.keys.lcontrol)or c.isKeyDown(c.keys.rcontrol)end;function c.isShiftDown()
return
c.isKeyDown(c.keys.lshift)or c.isKeyDown(c.keys.rshift)end;return c