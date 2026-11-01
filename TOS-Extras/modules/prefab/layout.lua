-- ╔══════════════════════════════════════════════════════════════╗
-- ║  prefab: laying out a base                                   ║
-- ║                                                              ║
-- ║  The base as a map of tiles, each drawn with its doors, so   ║
-- ║  you can see what joins what. Pick a part, turn it, drop it. ║
-- ║  The rules live in base.lua and parts.lua; this file is the  ║
-- ║  screen and the keys.                                        ║
-- ╚══════════════════════════════════════════════════════════════╝

local Base = require("prefab.base")
local Parts = require("prefab.parts")
local B = require("prefab.blueprint")

local L = {}

local CW, CH = 6, 3                    -- screen cells a tile takes

--- `env` is what the caller owns: U from tui, read(path), write(path, text),
--- and reportLines(bp) for the materials.
function L.run(o, env, base, path)
  local U = env.U
  local S, why = U.screen()
  if not S then o("prefab: " .. why .. ". The commands still work: prefab help", 0xFF6600); return end
  local T, Wd, Ht = S.T, S.W, S.H
  local K, pad = U.K, U.pad
  local PANEL = math.min(24, math.floor(Wd * 0.34))
  local PX = Wd - PANEL + 1
  local GX, GY = 1, 3
  local GW = math.floor((Wd - PANEL - 1) / CW)   -- tiles across
  local GH = math.floor((Ht - 4) / CH)           -- tiles down

  local choices = {}                     -- what can be placed: names
  for _, p in ipairs(Parts.LIBRARY) do choices[#choices + 1] = p.name end
  for _, e in ipairs(base.parts) do
    if e.name:sub(1, 1) == "/" then
      local known = false
      for _, c in ipairs(choices) do known = known or c == e.name end
      if not known then choices[#choices + 1] = e.name end
    end
  end

  local cx, cz, sx, sz = 1, 1, 0, 0      -- cursor and scroll, in tiles
  local current, turns = 1, 0            -- the part in hand, and how turned
  local dirty = false
  local status, statusTone = nil, "hi"
  local tiles = {}

  local function say(m, t) status, statusTone = m, t or "hi" end
  local function tone(t) return T[t] or T.fg end
  local function refresh() tiles = Base.tiles(base, env.read) or {} end
  local function at(x, z) return tiles[x .. "," .. z] end
  local function shortName(name) return (name:match("([^/]+)%.%w+$") or name) end

  --- One tile: a room's outline with gaps at its doors, and its name.
  local function drawTile(x, z)
    local px = GX + (x - sx - 1) * CW
    local py = GY + (z - sz - 1) * CH
    if px < GX or py < GY or x - sx > GW or z - sz > GH then return end
    local t = at(x, z)
    local isCur = x == cx and z == cz
    local fg = isCur and T.selfg or T.fg
    local bg = isCur and T.selbg or T.bg
    if not t then
      S.set(px, py, "      ", T.dim, bg)
      S.set(px, py + 1, isCur and "  ++  " or "  ..  ", isCur and T.selfg or T.dim, bg)
      S.set(px, py + 2, "      ", T.dim, bg)
      return
    end
    local mono = S.mono
    local tl, tr, bl, br = "┌", "┐", "└", "┘"
    local hz, vt = "─", "│"
    if mono then tl, tr, bl, br, hz, vt = "+", "+", "+", "+", "-", "|" end
    local e = base.parts[t.index]
    --- The same part on the next tile means no wall between them.
    local function open(dx, dz)
      local n = at(x + dx, z + dz)
      return n ~= nil and n.index == t.index
    end
    local function across(door, same, left, right)
      local mid = same and "    " or (door and (hz .. "  " .. hz) or string.rep(hz, 4))
      return left .. mid .. right
    end
    S.set(px, py, across(t.doors.n, open(0, -1), tl, tr), fg, bg)
    S.set(px, py + 2, across(t.doors.s, open(0, 1), bl, br), fg, bg)
    local label = (e.x == x and e.z == z) and shortName(e.name) or ""
    S.set(px, py + 1, ((t.doors.w or open(-1, 0)) and " " or vt) .. pad(label, 4)
      .. ((t.doors.e or open(1, 0)) and " " or vt), fg, bg)
  end

  local function drawGrid()
    S.fill(GX, GY, PX - 2, Ht - 4, " ", T.fg, T.bg)
    for z = sz + 1, math.min(base.d, sz + GH) do
      for x = sx + 1, math.min(base.w, sx + GW) do drawTile(x, z) end
    end
  end

  local function header()
    S.fill(1, 1, Wd, 1, " ", T.bg, T.border)
    S.set(2, 1, pad("PREFAB BASE  " .. base.name .. (dirty and " *" or ""), Wd - 22), T.bg, T.border)
    local right = string.format("%d by %d tiles", base.w, base.d)
    S.set(Wd - U.ulen(right), 1, right, T.bg, T.border)
    S.fill(1, 2, Wd, 1, S.mono and "-" or "─", T.dim, T.bg)
  end

  local function handEntry() return { name = choices[current], x = cx, z = cz, turns = turns } end

  local HELP = { "R Turn  C Check", "B Blocks M Report", "S Save  O Open", "X Blueprint", "A Add a part" }

  local function drawPanel()
    local top, bottom = GY, Ht - 3
    S.fill(PX - 1, top, PANEL + 1, bottom - top + 1, " ", T.fg, T.bg)
    for y = top, bottom do S.set(PX - 1, y, S.mono and "|" or "│", T.dim, T.bg) end
    local y = top
    local room = (bottom - top + 1) - #HELP - 2
    local first = math.max(1, math.min(current - math.floor(room / 2), #choices - room + 1))
    for i = first, math.min(#choices, first + room - 1) do
      local isSel = i == current
      S.set(PX, y, pad(" " .. shortName(choices[i]), PANEL - 1), isSel and T.selfg or T.fg, isSel and T.selbg or T.bg)
      y = y + 1
    end
    local bp = Base.resolve(handEntry(), env.read)
    local doors = bp and Parts.doorText((Parts.doors(bp))) or "?"
    S.set(PX + 1, bottom - #HELP - 1, pad("Doors: " .. doors, PANEL - 2), T.title, T.bg)
    for i, l in ipairs(HELP) do S.set(PX + 1, bottom - #HELP + i, pad(l, PANEL - 2), T.dim, T.bg) end
  end

  local function footer()
    S.fill(1, Ht - 1, Wd, 1, " ", T.fg, T.bg)
    if status then S.set(2, Ht - 1, pad(status, Wd - 2), tone(statusTone), T.bg) end
    S.fill(1, Ht, Wd, 1, " ", T.bg, T.border)
    S.set(2, Ht, pad(U.fitKeys({ "Space Place", "Del Remove", "Tab Part" },
      U.quitLabel() .. " Quit", Wd - 2), Wd - 2), T.bg, T.border)
  end

  local function draw() refresh(); header(); drawGrid(); drawPanel(); footer() end
  local kit = U.kit(S, draw)

  local function follow()
    if cx <= sx then sx = cx - 1 elseif cx > sx + GW then sx = cx - GW end
    if cz <= sz then sz = cz - 1 elseif cz > sz + GH then sz = cz - GH end
  end

  local function moveTo(x, z)
    cx, cz = math.max(1, math.min(base.w, x)), math.max(1, math.min(base.d, z))
    follow()
    drawGrid()
  end

  --- Try a change: put it back and say why if the layout will not have it.
  local function attempt(change, undo)
    change()
    local ok, err = Base.check(base, env.read)
    if not ok then undo(); say(tostring(err), "warn"); return false end
    dirty = true
    return true
  end

  local function place()
    local entry = handEntry()
    if at(cx, cz) then say("This tile is taken: Del clears it.", "warn"); return end
    attempt(function() base.parts[#base.parts + 1] = entry end,
      function() table.remove(base.parts) end)
  end

  local function remove()
    local t = at(cx, cz)
    if not t then return end
    table.remove(base.parts, t.index)
    dirty = true
  end

  --- R turns what is under the cursor, or else what is in hand.
  local function turn()
    local t = at(cx, cz)
    if t then
      local e = base.parts[t.index]
      local was = e.turns or 0
      attempt(function() e.turns = (was + 1) % 4 end, function() e.turns = was end)
    else
      turns = (turns + 1) % 4
    end
  end

  local function checkReport()
    local r, err = Base.check(base, env.read)
    local lines = {}
    if not r then lines[1] = { tostring(err), "warn" }
    else
      for _, p in ipairs(r.problems) do lines[#lines + 1] = { p, "warn" } end
      if #lines == 0 then
        lines[1] = { Base.summary(r), "hi" }
      end
    end
    kit.popup("Check", lines, "Any key to go back", 0)
    kit.nextKey()
  end

  local function report()
    local bp, err = Base.compile(base, env.read)
    if not bp then say(tostring(err), "warn"); return end
    kit.popup("What this takes", env.reportLines(bp), "Any key to go back", 0)
    kit.nextKey()
  end

  local function blocks()
    for _, r in ipairs(Parts.ROLES) do
      local have = base.blocks[r.key] or r
      local id = kit.prompt("Blocks", r.role .. ", by registry name:", have.id)
      if not id then return end
      if id ~= have.id then
        local scratch = B.new(1, 1, 1)
        local ok, err = B.addBlock(scratch, r.key, id, 0, B.cleanName(id:match(":(.+)$") or id))
        if not ok then say(err, "warn"); return end
        base.blocks[r.key] = scratch.palette[r.key]
        dirty = true
      end
    end
  end

  local function save()
    local name = kit.prompt("Save base", "File:", path or (base.name:gsub("%W+", "-"):lower() .. ".base"))
    if not name or name == "" then return end
    local ok, err = env.write(name, Base.serialize(base))
    if ok then path, dirty = name, false; say("Saved " .. name .. ".")
    else say("NOT saved: " .. tostring(err), "warn") end
  end

  local function exportBp()
    local bp, err = Base.compile(base, env.read)
    if not bp then say(tostring(err), "warn"); return end
    local name = kit.prompt("Blueprint", "File:", (base.name:gsub("%W+", "-"):lower() .. ".bp"))
    if not name or name == "" then return end
    local ok, wErr = env.write(name, B.serialize(bp))
    if ok then say("Wrote " .. name .. ".") else say("NOT saved: " .. tostring(wErr), "warn") end
  end

  local function open()
    if dirty and not kit.yesNo("Open another without saving this one?") then return end
    local name = kit.prompt("Open base", "File:", path or "")
    if not name or name == "" then return end
    local text = env.read(name)
    if not text then say("no such file: " .. name, "warn"); return end
    local loaded, err = Base.parse(text)
    if not loaded then say("Cannot open: " .. tostring(err), "warn"); return end
    base, path, dirty = loaded, name, false
    cx, cz, sx, sz = 1, 1, 0, 0
    say("Opened " .. name .. ".")
  end

  local function addPart()
    local name = kit.prompt("Add a part", "A blueprint of whole tiles, by full path:", "")
    if not name or name == "" then return end
    local bp, err = Base.resolve({ name = name, turns = 0 }, env.read)
    if not bp then say(tostring(err), "warn"); return end
    choices[#choices + 1] = name
    current, turns = #choices, 0
    say("Added " .. shortName(name) .. ": doors " .. Parts.doorText((Parts.doors(bp))))
  end

  draw()
  while true do
    local kind, ch, code, button, how = U.pullEvent()
    local redraw = true
    if kind == "tos_focus" then draw(); redraw = false
    elseif kind == "mouse" then
      local mx, my = ch, code
      if mx < PX - 1 and my >= GY and my < Ht - 1 then
        local x = math.floor((mx - GX) / CW) + 1 + sx
        local z = math.floor((my - GY) / CH) + 1 + sz
        if x <= base.w and z <= base.d then
          cx, cz = x, z
          if how == "touch" then
            refresh()
            if button == 1 then remove() elseif not at(x, z) then place() end
          end
        end
      elseif how == "touch" and mx >= PX and my >= GY then
        local room = (Ht - 3 - GY + 1) - #HELP - 2
        local first = math.max(1, math.min(current - math.floor(room / 2), #choices - room + 1))
        local i = first + (my - GY)
        if i <= #choices and my - GY < room then current, turns = i, 0 end
      end
    elseif kind == "key" then
      status = nil
      local c = ch and ch > 0 and string.char(ch):lower() or ""
      if U.isQuit(ch, code) then
        if not dirty or kit.yesNo("Leave without saving?") then break end
      elseif code == K.LEFT then moveTo(cx - 1, cz)
      elseif code == K.RIGHT then moveTo(cx + 1, cz)
      elseif code == K.UP then moveTo(cx, cz - 1)
      elseif code == K.DOWN then moveTo(cx, cz + 1)
      elseif code == K.TAB then current, turns = current % #choices + 1, 0
      elseif c == " " or code == K.ENTER then place()
      elseif code == K.DEL or code == K.BACK then remove()
      elseif c == "r" then turn()
      elseif c == "c" then checkReport()
      elseif c == "m" then report()
      elseif c == "b" then blocks()
      elseif c == "s" then save()
      elseif c == "o" then open()
      elseif c == "x" then exportBp()
      elseif c == "a" then addPart()
      end
    else
      redraw = false
    end
    if redraw then draw() end
  end
  S.fill(1, 1, Wd, Ht, " ", T.fg, T.bg)
end

return L
