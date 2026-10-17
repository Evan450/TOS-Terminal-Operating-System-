local m,s="Wrong input ","number"local t=require("computer")local l={}
local u={c=0,d=2,e=4,f=5,g=7,a=9,b=11}
local v={[0]="C",[1]="C#",[2]="D",[3]="D#",[4]="E",[5]="F",[6]="F#",[7]="G",[8]="G#",[9]="A",[10]="A#",[11]="B"}local n,o=21,95;local p=5
local function q(a)
local c,d,e=a:lower():match("^([a-g])([#b]?)(%d+)$")if not c then return nil end
local b=12* (tonumber(e)+1)+u[c]if d=="#"then b=b+1 elseif d=="b"then b=b-1 end
if b<n or b>o then return nil end;return b end
local r=" given to note.%s, needs to be <note>[semitone sign]".."<octave>, e.g. A#0 or Gb4"
function l.midi(a)
if type(a)=="string"then local b=q(a)
if not b then error(m..
tostring(a)..r:format("midi"),2)end;return b elseif type(a)==s then return
math.floor((12*math.log(a/440,2))+69)end
error(m..tostring(a).." given to note.midi, needs to be a number or a string",2)end
function l.freq(a)
if type(a)=="string"then local b=q(a)
if not b then error(m..
tostring(a)..r:format("freq"),2)end;return 2^ ((b-69)/12)*440 elseif type(a)==s then return 2^
((a-69)/12)*440 end
error(m..tostring(a).." given to note.freq, needs to be a number or a string",2)end
function l.name(a)a=tonumber(a)if
not a or a<n or a>o or a~=math.floor(a)then
error("Attempt to get a note for a non-exsisting MIDI code",2)end
return v[a%12]..tostring(math.floor(a/
12)-1)end
function l.ticks(a)if type(a)~=s then
error(m..
tostring(a).." given to note.ticks, needs to be a number",2)end
if a>=0 and a<=24 then return a+34 end;if a>=34 and a<=58 then return a-34 end
error(m..tostring(a)..
" given to note.ticks, needs to be a number [0-24 or 34-58]",2)end
function l.play(b,a)local d=l.freq(b)a=tonumber(a)or 0.1
if a~=a or a<=0 then return end;if a>p then a=p end;local e,c=pcall(require,"kernel.audio")
if
e and c and c.isEnabled and not c.isEnabled()then return end;pcall(t.beep,d,a)end;return l