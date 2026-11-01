-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: pic, from the bytes of a file to the cells on a GPU   ║
-- ║                                                              ║
-- ║  The PNG fixtures were written by Pillow, so the decoder is  ║
-- ║  read against a real encoder's dynamic Huffman and filter    ║
-- ║  choices, and each picture's pixels follow the formula beside ║
-- ║  its check here.                                             ║
-- ║  The OCIF fixtures are laid out by hand from MineOS's        ║
-- ║  Image.lua. The last section runs the real init.lua inside a ║
-- ║  fake sandbox with a GPU that remembers every cell.          ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/pic/test_pic.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "modules/?.lua;" .. package.path
local O = require("pic.ocif")
local P = require("pic.png")
local C = require("pic.convert")
-- Written by Pillow; each one's pixels are the formula beside its check.
local FIX = {
  rgb8 = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\016\000\000\000\016\008\002\000\000\000\144\145\104\054\000\000\000\113\073\068\065\084\120\156\149\208\125\007\128\048\016\128\241\075\039\034\082\068\068\028\049\198\125\255\175\151\045\203\094\218\237\226\049\247\199\126\142\235\000\096\249\019\186\007\122\125\024\192\160\012\035\048\106\194\020\076\205\176\000\179\028\126\129\085\008\043\096\171\196\002\216\211\204\051\200\224\240\081\024\092\077\112\102\201\128\252\039\138\211\108\032\128\235\077\000\038\005\198\215\184\082\006\044\128\173\001\046\000\123\192\055\229\089\017\042\162\011\241\111\000\000\000\000\073\069\078\068\174\066\096\130",
  rgba8 = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\016\000\000\000\016\008\006\000\000\000\031\243\255\097\000\000\000\127\073\068\065\084\120\156\157\209\109\007\128\048\020\134\225\103\122\068\068\047\068\068\140\136\216\255\255\123\057\149\094\087\157\237\195\197\049\206\109\054\003\000\021\080\198\034\042\024\032\137\198\035\144\070\225\053\144\005\227\051\144\007\161\063\080\168\241\061\080\171\240\059\208\252\112\154\064\235\049\238\051\117\129\110\099\079\243\138\250\064\239\069\093\192\110\011\246\129\097\055\144\165\225\066\017\144\007\187\007\228\076\168\127\193\023\152\022\063\001\247\018\144\115\009\056\051\003\057\205\019\010\163\022\207\132\000\000\000\000\073\069\078\068\174\066\096\130",
  grey8 = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\016\000\000\000\016\008\000\000\000\000\058\152\160\189\000\000\000\019\073\068\065\084\120\156\099\100\016\064\005\076\140\104\096\100\009\000\000\128\055\002\000\091\177\055\116\000\000\000\000\073\069\078\068\174\066\096\130",
  la8 = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\016\000\000\000\016\008\004\000\000\000\181\250\055\234\000\000\000\027\073\068\065\084\120\156\099\100\096\016\096\196\007\089\024\005\024\241\130\081\005\016\048\060\194\001\000\245\132\003\254\109\104\091\060\000\000\000\000\073\069\078\068\174\066\096\130",
  grey16 = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\016\000\000\000\016\016\000\000\000\000\106\008\124\254\000\000\000\025\073\068\065\084\120\156\099\100\096\023\096\192\007\153\024\025\240\195\081\005\140\195\040\028\000\249\032\002\007\034\230\037\187\000\000\000\000\073\069\078\068\174\066\096\130",
  pal1 = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\016\000\000\000\016\001\003\000\000\000\037\061\109\034\000\000\000\006\080\076\084\069\000\000\000\037\091\151\172\197\191\188\000\000\000\017\073\068\065\084\120\156\099\012\101\096\009\101\096\036\154\004\000\134\048\005\121\169\210\162\025\000\000\000\000\073\069\078\068\174\066\096\130",
  pal2 = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\016\000\000\000\016\002\003\000\000\000\098\157\023\242\000\000\000\012\080\076\084\069\000\000\000\037\091\151\074\182\046\111\017\197\085\089\194\217\000\000\000\027\073\068\065\084\120\156\099\148\102\096\096\096\060\198\192\192\192\242\026\068\236\006\113\041\016\003\000\149\227\010\069\225\105\234\082\000\000\000\000\073\069\078\068\174\066\096\130",
  pal4 = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\016\000\000\000\016\004\003\000\000\000\237\221\226\082\000\000\000\048\080\076\084\069\000\000\000\037\091\151\074\182\046\111\017\197\148\108\092\185\199\243\222\034\138\003\125\033\040\216\184\077\051\079\114\142\230\151\233\125\188\068\020\225\159\171\006\250\066\043\085\217\129\247\186\217\000\000\000\069\073\068\065\084\120\156\099\100\084\130\000\022\099\048\037\004\101\008\041\025\131\024\066\074\198\074\074\140\103\149\132\192\146\140\031\160\138\025\149\033\180\016\138\098\176\106\198\061\048\197\239\033\180\018\035\148\134\042\134\089\001\082\140\176\226\030\084\017\000\181\150\020\163\136\056\038\081\000\000\000\000\073\069\078\068\174\066\096\130",
  pal8 = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\016\000\000\000\016\008\003\000\000\000\040\045\015\083\000\000\003\000\080\076\084\069\000\000\000\037\091\151\074\182\046\111\017\197\148\108\092\185\199\243\222\034\138\003\125\033\040\216\184\077\051\079\114\142\230\151\233\125\188\068\020\225\159\171\006\250\066\043\085\217\080\176\112\117\011\007\154\102\158\191\193\053\228\028\204\009\119\099\046\210\250\083\045\145\120\136\040\157\227\191\194\062\086\231\153\237\012\244\132\049\079\027\086\170\178\123\005\073\160\096\224\197\187\119\234\022\014\015\113\165\052\204\060\089\039\211\126\130\106\163\221\001\200\056\152\237\147\047\018\238\198\055\073\093\092\164\244\129\255\139\166\090\034\203\181\185\240\016\080\021\107\231\058\198\126\095\033\021\132\124\172\169\215\067\206\050\218\243\141\113\024\232\008\061\067\159\098\158\054\135\249\205\172\084\100\209\175\251\246\010\146\027\101\041\064\192\192\101\027\087\138\118\238\175\209\133\212\044\028\249\135\179\030\226\074\067\061\225\104\152\120\141\243\015\178\078\166\215\169\061\252\004\212\033\095\107\070\186\002\107\021\153\144\112\048\181\203\199\218\038\094\255\129\245\036\220\140\073\055\035\110\146\186\147\237\081\184\072\232\221\163\127\002\254\022\039\089\173\076\180\068\113\015\219\150\106\114\187\197\009\224\032\160\005\123\055\042\214\206\079\049\101\116\140\252\153\231\147\190\066\042\227\157\193\008\248\088\045\083\239\082\174\134\119\009\029\156\100\180\193\191\075\230\026\226\011\117\121\048\208\016\085\043\167\122\134\062\159\225\213\196\060\108\233\151\003\014\242\154\051\077\049\088\168\200\125\003\095\162\094\246\199\185\141\236\020\036\017\111\187\054\202\082\091\037\233\128\128\128\165\219\023\202\054\174\239\145\069\020\236\220\057\071\115\094\162\010\131\253\161\168\088\056\205\179\207\242\014\102\023\105\253\060\196\148\097\031\043\134\122\194\171\213\089\208\048\240\245\139\135\026\230\030\063\065\181\100\156\076\137\247\227\174\082\122\211\173\017\248\008\168\029\099\063\066\190\214\103\025\109\140\116\004\177\207\155\214\042\050\251\133\201\032\224\096\069\059\247\106\150\142\143\241\037\180\076\188\217\167\083\254\002\234\035\093\129\072\184\024\109\019\175\146\110\070\183\201\221\220\036\116\001\127\011\038\218\162\075\053\057\112\144\208\149\235\103\186\070\254\223\161\149\004\252\044\041\087\195\078\178\090\115\013\241\152\104\136\189\195\031\226\030\182\007\121\077\044\212\228\081\047\123\118\138\018\155\229\169\192\064\064\229\155\215\010\246\110\047\081\005\084\172\156\121\007\051\158\098\202\195\189\097\232\024\248\013\115\143\050\206\038\087\041\189\124\132\084\161\223\235\198\058\130\235\149\025\016\240\176\053\075\071\090\166\222\127\001\117\164\092\012\201\183\163\238\018\058\019\109\209\056\200\104\093\035\255\130\126\150\167\217\045\204\052\196\241\143\091\022\234\242\059\069\137\096\160\032\133\251\183\170\086\078\207\177\229\244\012\124\025\103\019\062\194\170\099\029\065\136\120\216\173\211\111\210\046\006\247\137\157\028\228\052\065\063\203\102\154\098\139\245\249\176\080\144\213\171\039\250\006\190\031\097\085\068\188\236\105\023\131\142\114\026\179\205\177\216\040\072\253\131\223\034\222\118\071\057\013\108\148\164\145\239\059\182\074\210\219\165\105\233\023\028\028\000\000\000\102\073\068\065\084\120\156\085\199\215\002\066\000\000\134\209\207\008\165\068\123\210\018\013\026\218\245\254\207\213\245\127\238\014\024\166\101\215\028\215\171\055\252\102\043\104\035\011\163\014\178\110\175\143\108\048\028\033\027\079\166\200\102\243\024\089\178\088\034\091\173\055\200\210\109\134\044\223\237\145\029\142\005\178\242\116\070\118\185\086\200\110\247\007\178\231\235\141\236\243\253\253\001\160\181\030\001\200\092\156\107\000\000\000\000\073\069\078\068\174\066\096\130",
  tRNS = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\016\000\000\000\016\001\003\000\000\000\037\061\109\034\000\000\000\006\080\076\084\069\010\020\030\040\050\060\213\027\180\233\000\000\000\002\116\082\078\083\255\000\229\183\048\074\000\000\000\017\073\068\065\084\120\156\099\012\101\096\009\101\096\036\154\004\000\134\048\005\121\169\210\162\025\000\000\000\000\073\069\078\068\174\066\096\130",
  bit1 = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\016\000\000\000\016\001\000\000\000\000\055\136\194\204\000\000\000\017\073\068\065\084\120\156\099\012\101\096\009\101\096\036\154\004\000\134\048\005\121\169\210\162\025\000\000\000\000\073\069\078\068\174\066\096\130",
  big = "\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\064\008\002\000\000\000\106\086\229\089\000\000\001\021\073\068\065\084\120\218\237\216\193\013\130\048\024\134\225\015\131\067\120\233\036\029\193\009\024\161\019\116\004\038\096\132\078\224\008\078\224\008\076\226\001\218\148\032\122\032\136\216\151\244\064\222\244\244\095\158\182\149\022\190\075\097\253\188\208\107\073\146\153\173\043\113\088\167\056\032\043\053\082\144\238\082\079\076\049\031\080\043\249\217\166\210\099\026\144\139\083\236\178\077\196\080\079\007\214\189\154\098\209\049\031\144\145\130\212\079\055\149\030\043\152\255\196\188\129\121\152\135\121\152\135\121\152\063\044\243\006\230\185\205\175\136\233\028\100\037\043\185\248\067\028\035\204\195\060\204\195\252\190\204\091\152\135\121\110\243\219\197\252\028\052\080\215\106\060\092\019\097\030\230\097\254\011\204\055\048\015\243\048\207\163\253\110\049\157\131\156\228\035\117\033\163\174\244\008\243\048\191\150\121\015\243\048\015\243\048\207\163\253\239\222\230\013\162\195\252\042\230\059\152\135\121\152\135\121\152\231\209\254\176\204\027\068\127\207\252\013\230\097\030\230\097\030\230\097\158\219\252\191\050\255\128\121\152\135\121\152\135\121\152\135\121\152\047\146\249\039\232\118\126\208\181\057\132\055\000\000\000\000\073\069\078\068\174\066\096\130",
}

print("=== the palette ===")
print()

test("256 colours, ascending", (function()
  for i = 1, 255 do if O.PALETTE[i] <= O.PALETTE[i - 1] then return false end end
  return O.PALETTE[255] == 0xFFFFFF and O.PALETTE[0] == 0
end)())
test("the entries MineOS's table opens with",
  O.PALETTE[1] == 0x000040 and O.PALETTE[2] == 0x000080 and O.PALETTE[5] == 0x002400)
test("and closes with", O.PALETTE[254] == 0xFFFFBF and O.PALETTE[250] == 0xFFDBFF)
test("every palette colour maps to itself", (function()
  for i = 0, 255 do
    local r, g, b = O.rgb(O.PALETTE[i])
    if O.to8(r, g, b) ~= i then return false end
  end
  return true
end)())
test("a mid grey lands on a grey", O.to8(120, 120, 120) == (function()
  for i = 0, 255 do if O.PALETTE[i] == 0x787878 then return i end end
end)())

print()
print("=== reading OCIF ===")
print()

local function chr(...) return string.char(...) end
local UP = O.UPPER                     -- E2 96 80

local function cellAt(img, x, y)
  local row = img.rows[y]
  return row.bg:byte(x), row.fg:byte(x), img.syms[row.sym:byte(x)]
end

-- Method 5: 2-byte sizes, then bg, fg, alpha, character, by position.
do
  local data = "OCIF" .. chr(5, 0, 2, 0, 1) .. chr(10, 20, 0) .. "A" .. chr(30, 40, 0) .. UP
  local img, err = O.decode(data)
  test("method 5 decodes", img ~= nil, err)
  local bg, fg, s = cellAt(img, 1, 1)
  test("...the first cell", bg == 10 and fg == 20 and s == "A")
  bg, fg, s = cellAt(img, 2, 1)
  test("...a three-byte character", bg == 30 and fg == 40 and s == UP)
  test("...and its size", img.w == 2 and img.h == 1)
  test("the header is enough for the size", select(1, O.size(data)) == 2 and select(3, O.size(data)) == 5)
end

-- Method 6: one alpha, one character, one background, one foreground, one
-- row, two columns. Every count stored as itself.
local function grouped(method, n, p)
  return "OCIF" .. chr(method, 3 - p, 2 - p)
    .. chr(1 - n, 0, 0, 1 - n) .. "x" .. chr(1 - n, 7, 1 - n, 9, 1 - n, 2 - p, 2 - n, 1 - p, 3 - p)
end
for _, m in ipairs({ { 6, 0, 0 }, { 7, 1, 0 }, { 8, 1, 1 } }) do
  local img, err = O.decode(grouped(m[1], m[2], m[3]))
  test("method " .. m[1] .. " decodes", img ~= nil, err)
  if img then
    test("...3x2", img.w == 3 and img.h == 2, img.w .. "x" .. img.h)
    local bg, fg, s = cellAt(img, 1, 2)
    test("...its cells land where they say", bg == 7 and fg == 9 and s == "x")
    bg, fg, s = cellAt(img, 3, 2)
    test("...both of them", bg == 7 and fg == 9 and s == "x")
    bg, fg, s = cellAt(img, 2, 2)
    test("...and the rest are blank", bg == 0 and s == " ")
  end
end

do
  -- Alpha 255 is fully see-through, MineOS's "nothing here".
  local img = O.decode("OCIF" .. chr(5, 0, 2, 0, 1) .. chr(255, 255, 255) .. "A" .. chr(255, 255, 128) .. "B")
  local bg, _, s = cellAt(img, 1, 1)
  test("a fully transparent cell is the dark behind it", bg == 0 and s == " ")
  bg, _, s = cellAt(img, 2, 1)
  local r = O.rgb(O.PALETTE[bg])
  test("half transparent fades toward black, and keeps its character", s == "B" and r > 90 and r < 160, r)
end

test("a file that is not a .pic says so", select(2, O.decode("hello")) == "not a .pic file")
test("an unknown method says which", select(2, O.decode("OCIF" .. chr(9, 1, 1, 1, 1, 1))):find("method 9", 1, true) ~= nil)
test("a file cut short says so", select(2, O.decode("OCIF" .. chr(5, 0, 2, 0, 2) .. chr(1, 2, 0))) ~= nil)
test("a huge header is refused before anything is allocated",
  select(2, O.decode("OCIF" .. chr(5, 255, 255, 255, 255) .. "xx")):find("65535", 1, true) ~= nil)
do
  local cut = O.decode(grouped(6, 0, 0):sub(1, 14))
  test("grouped data cut short is refused", cut == nil)
  -- Positions outside the picture are dropped, not written past it.
  local img = O.decode("OCIF" .. chr(6, 1, 1) .. chr(1, 0, 0, 1) .. "x" .. chr(1, 7, 1, 9, 1, 200, 1, 200))
  test("a position outside the picture is dropped", img ~= nil and img.h == 1 and #img.rows == 1)
end

print()
print("=== writing OCIF ===")
print()

do
  local b = O.builder(4, 3)
  local a, up = b:symbol("A"), b:symbol(UP)
  b:set(1, 1, 10, 20, a)
  b:set(4, 3, 200, 100, up)
  b:set(2, 2, 10, 20, a)
  local img = b:finish()
  local bytes = O.encode(img)
  test("it writes method 8", O.method(bytes) == 8)
  local back, err = O.decode(bytes)
  test("what it writes reads back", back ~= nil, err)
  local same = back ~= nil
  for y = 1, 3 do
    for x = 1, 4 do
      local b1, f1, s1 = cellAt(img, x, y)
      local b2, f2, s2 = cellAt(back, x, y)
      if b1 ~= b2 or s1 ~= s2 or (s1 ~= " " and f1 ~= f2) then same = false end
    end
  end
  test("cell for cell", same)
  test("one picture always writes the same bytes", O.encode(img) == bytes)
end

do
  -- Wider than method 8 can say.
  local b = O.builder(300, 1)
  b:set(300, 1, 5, 6, b:symbol("z"))
  local bytes = O.encode(b:finish())
  test("past 256 wide it falls back to method 5", O.method(bytes) == 5)
  local back = O.decode(bytes)
  test("...and still reads back", back and back.w == 300 and select(3, cellAt(back, 300, 1)) == "z")
end

do
  local b = O.builder(300, 1)
  for i = 1, 300 do b:set(i, 1, 0, 0, b:symbol(utf8 and utf8.char(0x4E00 + i) or tostring(i))) end
  local img = b:finish()
  test("past 255 different characters the rest are counted as lost", img.lost > 0 and #img.syms <= 255, img.lost)
end

print()
print("=== reading PNG ===")
print()

local function pixels(data)
  local out, w, h = {}, nil, nil
  local ok, err = P.read(data, function(a, b) w, h = a, b end, function(y, pixel)
    local row = {}
    for x = 1, w do row[x] = { pixel(x) } end
    out[y] = row
  end)
  return ok and out or nil, err, w, h
end

--- Every pixel against want(x, y), 0-based, as {r, g, b, a}.
local function check(name, want)
  local out, err, w, h = pixels(FIX[name])
  if not out then test(name .. " decodes", false, err); return end
  local bad
  for y = 1, h do
    for x = 1, w do
      local w4, got = want(x - 1, y - 1), out[y][x]
      for i = 1, 4 do
        if w4[i] ~= got[i] and not bad then
          bad = string.format("(%d,%d)[%d] want %s got %s", x - 1, y - 1, i, tostring(w4[i]), tostring(got[i]))
        end
      end
    end
  end
  test(name .. ": every pixel", bad == nil, bad)
end

local function rgbAt(x, y) return (x * 17) % 256, (y * 17) % 256, (x * y * 3) % 256 end
local function greyAt(x, y) return (x * 16 + y) % 256 end
check("rgb8", function(x, y) local r, g, b = rgbAt(x, y); return { r, g, b, 255 } end)
check("rgba8", function(x, y) local r, g, b = rgbAt(x, y); return { r, g, b, greyAt(x, y) } end)
check("grey8", function(x, y) local v = greyAt(x, y); return { v, v, v, 255 } end)
check("la8", function(x, y) local v = greyAt(x, y); return { v, v, v, (y * 16 + x) % 256 } end)
check("grey16", function(x, y) local v = greyAt(x, y); return { v, v, v, 255 } end)
for _, c in ipairs({ { "pal1", 2 }, { "pal2", 4 }, { "pal4", 16 }, { "pal8", 256 } }) do
  check(c[1], function(x, y)
    local i = (x + y * 3) % c[2]
    return { (i * 37) % 256, (i * 91) % 256, (i * 151) % 256, 255 }
  end)
end
check("tRNS", function(x, y)
  if (x + y) % 2 == 0 then return { 10, 20, 30, 255 } end
  return { 40, 50, 60, 0 }
end)
check("bit1", function(x, y)
  local v = ((x + y) % 2 == 1) and 255 or 0
  return { v, v, v, 255 }
end)
check("big", function(x, y)
  return { math.min(255, (x - x % 8) / 8 * 25), (y - y % 8) / 8 * 30, (x * y) % 7 * 30, 255 }
end)

do
  local w, h = P.size(FIX.big)
  test("the header is enough for the size", w == 96 and h == 64)
  test("a file that is not a PNG says so", select(2, P.read("nope", nil, nil)) == "not a PNG file")
  local cut = FIX.big:sub(1, math.floor(#FIX.big * 0.6))
  test("a PNG cut short is refused", P.read(cut, nil, function() end) == nil)
  -- Stored deflate blocks, which Pillow never writes.
  local got = {}
  P.inflate("\1\3\0\252\255abc", 1, function(b) got[#got + 1] = string.char(b); return false end)
  test("inflate reads a stored block", table.concat(got) == "abc", table.concat(got))
  -- A decompression bomb: the row budget ends it, not the stream.
  local rows = 0
  test("rows stop at the header's height", P.read(FIX.big, nil, function() rows = rows + 1 end) and rows == 64)
  local seen = 0
  P.read(FIX.big, function() return { [3] = true } end, function() seen = seen + 1 end)
  test("onHeader's set picks the rows delivered", seen == 1)
  local ticks = 0
  P.read(FIX.big, function() return {} end, function() end, function() ticks = ticks + 1 end)
  test("progress runs on rows nobody wanted, so a long unpack can yield", ticks == 64, ticks)
  local fake = FIX.rgb8:sub(1, 16) .. string.char(0, 0, 0, 13) .. "IHDR"
    .. string.char(0, 4, 0, 0, 0, 4, 0, 0, 8, 2, 0, 0, 0) .. string.rep("\0", 4)
  test("an absurd size is refused", P.read(fake, nil, nil) == nil)
end

print()
print("=== pixels to cells ===")
print()

do
  test("a picture shrinks to fit, keeping its shape", (function()
    local w, h = C.targetSize(512, 384, 160, 50)
    return w == 133 and h == 100
  end)())
  test("a small one is left alone", (function()
    local w, h = C.targetSize(16, 16, 160, 50)
    return w == 16 and h == 16
  end)())
  local img, err = C.fromPNG(FIX.big, { maxW = 48, maxH = 16, depth = 8, dither = false })
  test("a PNG converts", img ~= nil, err)
  test("...to the size asked", img and img.w == 48 and img.h == 16, img and (img.w .. "x" .. img.h))
  test("...in half blocks and spaces", img and #img.syms == 2)
  local odd = C.fromPNG(FIX.rgb8, { maxW = 16, maxH = 7 })
  test("an odd pixel height keeps every row", odd and odd.h == 7, odd and odd.h)
end

do
  --- Average brightness of an image's half-cells, in 0..255.
  local function mean(img)
    local sum, n = 0, 0
    for y = 1, img.h do
      local row = img.rows[y]
      for x = 1, img.w do
        local s = img.syms[row.sym:byte(x)]
        sum = sum + O.LUMA[row.bg:byte(x)] + O.LUMA[(s == " " and row.bg or row.fg):byte(x)]
        n = n + 2
      end
    end
    return sum / n
  end
  local grey = C.fromPNG(FIX.grey8, { maxW = 16, maxH = 8, depth = 1 })
  local flat = C.fromPNG(FIX.grey8, { maxW = 16, maxH = 8, depth = 1, dither = false })
  local colours = {}
  for y = 1, grey.h do
    for x = 1, grey.w do
      colours[grey.rows[y].bg:byte(x)] = true
      colours[grey.rows[y].fg:byte(x)] = true
    end
  end
  local n = 0
  for _ in pairs(colours) do n = n + 1 end
  test("tier 1 is black and white only", n == 2 and colours[0] and colours[255], n)
  local m = mean(grey)
  test("dithering keeps the brightness of the picture", m > 95 and m < 160, m)
  test("...which a plain threshold need not", flat ~= nil)
end

do
  local q = C.quantizer(4, C.T2_PALETTE)
  local _, r, g, b = q(250, 205, 50)
  test("tier 2 picks from the 16 it has", r == 0xFF and g == 0xCC and b == 0x33)
end

do
  -- Scaling by pixel keeps both halves of a cell.
  local top = { 10, 20, 30, 40 }
  local bot = { 50, 60, 70, 80 }
  local img = { w = 4, h = 1, syms = { O.UPPER, " " }, lost = 0,
    rows = { O.pixelRow(top, bot, 4, "\1", "\2") } }
  local s = O.scale(img, 2, 1)
  local bg, fg = cellAt(s, 1, 1)
  test("scaling a half-block picture keeps its two halves",
    s.w == 2 and bg == 60 and fg == 20, tostring(bg) .. "," .. tostring(fg))
  local text = { w = 4, h = 2, syms = { "a", "b" }, lost = 0,
    rows = { { bg = "\1\2\3\4", fg = "\5\6\7\8", sym = "\1\2\1\2" },
             { bg = "\9\10\11\12", fg = "\13\14\15\16", sym = "\2\1\2\1" } } }
  local st = O.scale(text, 2, 1)
  test("a text picture scales by whole cells", st.w == 2 and st.h == 1 and #st.rows == 1)
  test("a fit never grows a picture", select(1, O.fit(10, 5, 160, 50)) == 10)
  local fw, fh = O.fit(160, 100, 80, 25)
  test("a fit keeps the shape", fw == 40 and fh == 25, fw .. "x" .. fh)
end

-- ── The real init.lua, on a GPU that remembers ─────────────────────────
print()
print("=== the viewer ===")
print()

local function utf8chars(s)
  local out = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end

local function machine(opts)
  opts = opts or {}
  local W, H = opts.W or 80, opts.H or 25
  local fx = { files = opts.files or {}, out = {}, screens = {}, sets = 0, colours = 0 }
  local fg, bg = 0xFFFFFF, 0
  local grid = {}
  for y = 1, H do grid[y] = {}; for x = 1, W do grid[y][x] = { " ", fg, bg } end end
  fx.grid = grid
  function fx.text()
    local t = {}
    for y = 1, H do
      local l = {}
      for x = 1, W do l[x] = grid[y][x][1] end
      t[y] = table.concat(l)
    end
    return table.concat(t, "\n")
  end
  local gpu = {
    getResolution = function() return W, H end,
    getDepth = function() return opts.depth or 8 end,
    setForeground = function(c) fg = c; fx.colours = fx.colours + 1 end,
    setBackground = function(c) bg = c; fx.colours = fx.colours + 1 end,
    set = function(x, y, s)
      fx.sets = fx.sets + 1
      for i, ch in ipairs(utf8chars(s)) do
        if grid[y] and grid[y][x + i - 1] then grid[y][x + i - 1] = { ch, fg, bg } end
      end
    end,
    fill = function(x, y, w, h, ch)
      for yy = y, y + h - 1 do
        for xx = x, x + w - 1 do
          if grid[yy] and grid[yy][xx] then grid[yy][xx] = { ch, fg, bg } end
        end
      end
    end,
  }
  if opts.depth == 4 then
    gpu.getPaletteColor = function(i) return C.T2_PALETTE[i + 1] end
  end
  fx.gpu = gpu
  local component = {
    list = function(kind)
      local done = false
      return function()
        if done or kind ~= "gpu" then return nil end
        done = true
        return "gpu-1", "gpu"
      end
    end,
    proxy = function() return gpu end,
  }
  local queue = {}
  for _, k in ipairs(opts.keys or {}) do queue[#queue + 1] = k end
  local computer = {
    uptime = function() fx.clock = (fx.clock or 0) + 0.3; return fx.clock end,
    pullSignal = function(t)
      if t == 0 then fx.yields = (fx.yields or 0) + 1; return nil end
      fx.screens[#fx.screens + 1] = fx.text()
      local k = table.remove(queue, 1)
      if k then return "key_down", "kbd", k[1], k[2] end
      return "interrupted"
    end,
  }
  local fs = {
    exists = function(p)
      if fx.files[p] ~= nil then return true end
      for k in pairs(fx.files) do if k:sub(1, #p + 1) == p .. "/" then return true end end
      return false
    end,
    isDirectory = function(p)
      if fx.files[p] ~= nil then return false end
      for k in pairs(fx.files) do if k:sub(1, #p + 1) == p .. "/" then return true end end
      return false
    end,
    list = function(p)
      local out = {}
      for k in pairs(fx.files) do
        local name = k:sub(1, #p + 1) == p .. "/" and k:sub(#p + 2)
        if name then out[#out + 1] = name end
      end
      return out
    end,
    readFile = function(p) return fx.files[p] end,
    writeFile = function(p, d) fx.files[p] = d; return true end,
  }
  local function req(name)
    if name == "component" then return component end
    if name == "computer" then return computer end
    if name == "shell.keys" and opts.quitLabel then
      return { is = function(_, ch) return ch == 17 end,
               label = function() return opts.quitLabel end }
    end
    if name:sub(1, 4) == "pic." then return require(name) end
    error("sandbox: module '" .. name .. "' is not on the allowed list", 2)
  end
  local env = setmetatable({ require = req, fs = fs, internet = opts.internet }, { __index = _G })
  local main = assert(loadfile("modules/pic/init.lua", "t", env))()
  fx.V = main.text
  fx.run = function(args)
    fx.out = {}
    main.commands.pic(args, function(t) fx.out[#fx.out + 1] = tostring(t) end)
    return table.concat(fx.out, "\n")
  end
  return fx
end

local function has(s, n) return s ~= nil and s:find(n, 1, true) ~= nil end
local key = { F = { 102, 33 }, B = { 98, 48 }, N = { 110, 49 }, P = { 112, 25 },
              RIGHT = { 0, 205 }, DOWN = { 0, 208 }, QUIT = { 17, 16 } }

do
  -- A checker of half blocks: what the GPU ends up holding is the picture.
  local b = O.builder(4, 2)
  local up = b:symbol(O.UPPER)
  for y = 1, 2 do for x = 1, 4 do b:set(x, y, x * 10, y * 40, up) end end
  local img = b:finish()
  local fx = machine()
  fx.V.paint(fx.gpu, img, 1, 1, 3, 5, 4, 2, false)
  local good = true
  for y = 1, 2 do
    for x = 1, 4 do
      local c = fx.grid[4 + y][2 + x]
      if c[1] ~= O.UPPER or c[2] ~= O.PALETTE[y * 40] or c[3] ~= O.PALETTE[x * 10] then good = false end
    end
  end
  test("paint: every cell lands with its colours", good)
  test("paint: nothing outside it is touched", fx.grid[5][2][1] == " " and fx.grid[5][7][1] == " ")

  local flat = O.builder(40, 3)
  local up2 = flat:symbol(O.UPPER)
  for y = 1, 3 do for x = 1, 40 do flat:set(x, y, 7, 9, up2) end end
  local fx2 = machine()
  fx2.V.paint(fx2.gpu, flat:finish(), 1, 1, 1, 1, 40, 3, false)
  test("one colour pair is one set a row, and two colour changes in all",
    fx2.sets == 3 and fx2.colours == 2, fx2.sets .. " sets, " .. fx2.colours .. " colours")

  -- Spaces of one background, with foregrounds that never show.
  local sp = O.builder(6, 1)
  local s = sp:symbol(" ")
  for x = 1, 6 do sp:set(x, 1, 7, x, s) end
  local fx3 = machine()
  fx3.V.paint(fx3.gpu, sp:finish(), 1, 1, 1, 1, 6, 1, false)
  test("a run of spaces is one set, whatever foregrounds they carry", fx3.sets == 1, fx3.sets)
end

do
  local V = machine().V
  local white = 255
  local bg, fg, text = V.monoCell(0, 255, O.UPPER, 1, 1)
  test("mono: a white top half on black", bg == 0 and fg == white and text == O.UPPER)
  bg, _, text = V.monoCell(255, 255, " ", 1, 1)
  test("mono: all white is a white space", bg == white and text == " ")
  bg, fg, text = V.monoCell(0, 0, "A", 1, 1)
  test("mono: text keeps its two colours opposite, so it stays readable",
    bg == 0 and fg == white and text == "A")
  local on = 0
  local mid = O.to8(128, 128, 128)
  for x = 0, 3 do for y = 0, 3 do
    local _, _, t = V.monoCell(mid, mid, O.FULL, x, y)
    if t ~= " " or select(1, V.monoCell(mid, mid, O.FULL, x, y)) == white then on = on + 1 end
  end end
  test("mono: a mid grey comes out as a pattern, not a flat colour", on > 4 and on <= 16, on)
end

do
  local pic = O.encode(C.fromPNG(FIX.big, { maxW = 48, maxH = 16 }))
  local fx = machine({ files = { ["/p/a.pic"] = pic }, keys = { key.B, key.QUIT }, quitLabel = "^Q / F10" })
  local ok, err = pcall(fx.run, { "/p/a.pic" })
  test("a .pic opens", ok, err)
  local s = fx.screens[1]
  test("the bar names it, with its size", has(s, "a.pic  48x16"))
  test("...and the way out, in the machine's own key", has(s, "^Q / F10 Quit"))
  test("the picture is on the screen", has(s, O.UPPER))
  test("B hides the bar", not has(fx.screens[2], "a.pic"))
  test("the screen is left clear", has(fx.text(), O.UPPER) == false and not has(fx.text(), "a.pic"))
end

do
  -- Bigger than the screen: fitted first, panned at full size.
  local b = O.builder(100, 40)
  local a = b:symbol("A")
  for y = 1, 40 do for x = 1, 100 do b:set(x, y, 0, 255, a) end end
  b:set(100, 40, 0, 255, b:symbol("Z"))
  local bytes = O.encode(b:finish())
  local fx = machine({ files = { ["/big.pic"] = bytes },
    keys = { key.F, key.RIGHT, key.RIGHT, key.RIGHT, key.RIGHT, key.RIGHT,
             key.DOWN, key.DOWN, key.DOWN, key.DOWN, key.QUIT } })
  local ok, err = pcall(fx.run, { "/big.pic" })
  test("a big picture opens", ok, err)
  test("...fitted to the screen", has(fx.screens[1], "big.pic  60x24"), (fx.screens[1] or ""):sub(-80))
  test("F shows it full size", has(fx.screens[2], "big.pic  100x40"))
  test("the arrows reach its far corner", has(fx.screens[#fx.screens], "Z"))
end

do
  -- A directory, a PNG in it, and something that is not a picture.
  local fx = machine({ files = { ["/d/a.png"] = FIX.big, ["/d/b.pic"] = "not really", ["/d/c.txt"] = "x" },
    keys = { key.N, key.N, key.P, key.QUIT } })
  local ok, err = pcall(fx.run, { "/d" })
  test("a directory opens", ok, err)
  test("...on its first picture, counted", has(fx.screens[1], "a.png") and has(fx.screens[1], "1/2"))
  test("N moves on, and a bad file says why", has(fx.screens[2], "Cannot show b.pic")
    and has(fx.screens[2], "not a picture this can read"))
  test("...and wraps round", has(fx.screens[3], "a.png"))
  test("P goes back", has(fx.screens[4], "b.pic"))
end

do
  -- A tier 1 screen: a real picture in black and white only.
  local fx = machine({ W = 50, H = 16, depth = 1, files = { ["/a.png"] = FIX.big }, keys = { key.QUIT } })
  local ok, err = pcall(fx.run, { "/a.png" })
  test("tier 1 shows a PNG", ok, err)
  test("...in half blocks", has(fx.screens[1], O.UPPER) or has(fx.screens[1], O.LOWER))
end

do
  local fx = machine({ files = { ["/a.png"] = FIX.big }, keys = {} })
  local out = fx.run({ "convert", "/a.png", "/a.pic", "--width", "24", "--height", "8", "--tier", "2" })
  test("convert writes a .pic", has(out, "Wrote /a.pic: 24x8") or has(out, "Wrote /a.pic: 24x"), out)
  test("...that reads back", O.decode(fx.files["/a.pic"]) ~= nil)
  test("convert says what it needs", has(fx.run({ "convert", "/a.png" }), "pic convert"))
  test("an unknown option is named", has(fx.run({ "convert", "/a.png", "/b.pic", "--zoom" }), "--zoom"))
  test("--width needs a number", has(fx.run({ "convert", "/a.png", "/b.pic", "--width" }), "needs a number"))
  test("convert refuses what is not a PNG", has(fx.run({ "convert", "/a.pic", "/b.pic" }), "not a PNG"))
  test("info reads a PNG's size", has(fx.run({ "info", "/a.png" }), "PNG, 96x64 pixels"))
  test("info reads a .pic's", has(fx.run({ "info", "/a.pic" }), "MineOS .pic (OCIF 8)"))
  test("no such file says so", has(fx.run({ "/nope.png" }), "No such file"))
  test("no argument is the help", has(fx.run({}), "pic convert"))
end

do
  -- A URL, through the sandbox's internet global.
  local asked
  local fx = machine({ keys = { key.QUIT }, internet = { get = function(url, o)
    asked = o.maxBytes
    if url:find("gone", 1, true) then return nil, "HTTP 404" end
    return FIX.big
  end } })
  local ok, err = pcall(fx.run, { "http://x.example/a.png" })
  test("a URL opens", ok, err)
  test("...with room for a picture past the default 64 KB", asked and asked > 64 * 1024)
  test("...and the bar names the file", has(fx.screens[1], "a.png"))
  local fx2 = machine({ keys = { key.QUIT }, internet = { get = function() return nil, "HTTP 404" end } })
  pcall(fx2.run, { "http://x.example/gone.png" })
  test("a failed fetch says why on the screen", has(fx2.screens[1], "HTTP 404"))
  local fx3 = machine({ keys = { key.QUIT } })
  pcall(fx3.run, { "http://x.example/a.png" })
  test("no internet card says so", has(fx3.screens[1], "no internet"))
end

do
  -- A long unpack gives the machine a chance to breathe.
  local fx = machine({ files = { ["/a.png"] = FIX.big }, keys = { key.QUIT } })
  pcall(fx.run, { "/a.png" })
  test("decoding stops to yield", (fx.yields or 0) > 0, fx.yields)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
