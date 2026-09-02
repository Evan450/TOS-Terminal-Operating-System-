local keyboard = {}
keyboard.keys = {

  a=30,b=48,c=46,d=32,e=18,f=33,g=34,h=35,i=23,j=36,k=37,l=38,
  m=50,n=49,o=24,p=25,q=16,r=19,s=31,t=20,u=22,v=47,w=17,x=45,y=21,z=44,

  ["1"]=2,["2"]=3,["3"]=4,["4"]=5,["5"]=6,["6"]=7,["7"]=8,["8"]=9,["9"]=10,["0"]=11,

  f1=59,f2=60,f3=61,f4=62,f5=63,f6=64,f7=65,f8=66,f9=67,f10=68,f11=87,f12=88,

  back=14,tab=15,enter=28,lshift=42,rshift=54,lcontrol=29,rcontrol=157,
  lmenu=56,rmenu=184,space=57,capital=58,numlock=69,scroll=70,

  up=200,down=208,left=203,right=205,home=199,["end"]=207,
  pageUp=201,pageDown=209,insert=210,delete=211,

  numpad0=82,numpad1=79,numpad2=80,numpad3=81,numpad4=75,
  numpad5=76,numpad6=77,numpad7=71,numpad8=72,numpad9=73,
  numpadmul=55,numpadsub=74,numpadadd=78,numpaddecimal=83,numpadenter=156,

  minus=12,equals=13,lbracket=26,rbracket=27,semicolon=39,
  apostrophe=40,grave=41,backslash=43,comma=51,period=52,slash=53,
}

--! Snapshot the names FIRST — adding keys to a table mid-pairs() is
--! undefined behaviour and dropped a third to two thirds of the reverse
--! entries here, a different set each boot. See colors.lua for the full
--! note. (test_compat_tables.lua)
do
  local names = {}
  for name in pairs(keyboard.keys) do names[#names + 1] = name end
  for _, name in ipairs(names) do
    local code = keyboard.keys[name]
    if keyboard.keys[code] == nil then keyboard.keys[code] = name end
  end
end

function keyboard.isKeyDown(code)
  local component = require("component")
  if component.isAvailable("keyboard") then
    return component.keyboard.isKeyDown(code)
  end
  return false
end

function keyboard.isAltDown() return keyboard.isKeyDown(keyboard.keys.lmenu) or keyboard.isKeyDown(keyboard.keys.rmenu) end

function keyboard.isControlDown() return keyboard.isKeyDown(keyboard.keys.lcontrol) or keyboard.isKeyDown(keyboard.keys.rcontrol) end

function keyboard.isShiftDown() return keyboard.isKeyDown(keyboard.keys.lshift) or keyboard.isKeyDown(keyboard.keys.rshift) end
return keyboard
