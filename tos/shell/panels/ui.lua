local ui = {}

local _ustr = nil
local function ustrLib()
  if _ustr == nil then
    local ok, m = pcall(require, "kernel.ustr")
    _ustr = (ok and m) or false
  end
  return _ustr or nil
end
local function ufit(s, cols)
  local u = ustrLib()
  if u then return u.fit(s, cols) end
  return tostring(s or ""):sub(1, cols)
end
local function uwidth(s)
  local u = ustrLib()
  if u then return u.width(s) end
  return #tostring(s or "")
end

function ui.tileGrid(region, opts)
  opts = opts or {}
  local tw = math.max(6, opts.tileW or 14)
  local th = math.max(3, opts.tileH or 4)
  local gx = opts.gapX or 2
  local gy = opts.gapY or 1
  local cols = math.max(1, math.floor((region.w + gx) / (tw + gx)))
  local rows = math.max(1, math.floor((region.h + gy) / (th + gy)))
  local usedW = cols * tw + (cols - 1) * gx
  local ox = region.x + math.max(0, math.floor((region.w - usedW) / 2))
  return { cols = cols, rows = rows, perPage = cols * rows,
           tileW = tw, tileH = th, gapX = gx, gapY = gy,
           ox = ox, oy = region.y }
end

function ui.tileRect(g, slot)
  if type(slot) ~= "number" or slot < 1 or slot > g.perPage then return nil end
  local i = slot - 1
  local c = i % g.cols
  local r = math.floor(i / g.cols)
  return { x = g.ox + c * (g.tileW + g.gapX),
           y = g.oy + r * (g.tileH + g.gapY),
           w = g.tileW, h = g.tileH }
end

function ui.tileHit(g, x, y)
  for slot = 1, g.perPage do
    local r = ui.tileRect(g, slot)
    if r and x >= r.x and x < r.x + r.w
         and y >= r.y and y < r.y + r.h then
      return slot
    end
  end
  return nil
end

function ui.cycle(values, current, dir)
  if type(values) ~= "table" or #values == 0 then return current end
  local idx = 0
  for i, v in ipairs(values) do
    if v == current then idx = i; break end
  end
  if idx == 0 then return values[1] end
  idx = idx + (dir or 1)
  if idx > #values then idx = 1 elseif idx < 1 then idx = #values end
  return values[idx]
end

local EXT_GLYPHS = {
  lua = "♦",
  txt = "≡", md = "≡", log = "≡",
  man = "¶",
  cfg = "§", conf = "§", json = "§",
  dat = "▓", tcz = "▓", bak = "▓", bin = "▓",
}

function ui.fileGlyph(name, isDir)
  if isDir then
    return (name == "..") and "«" or "■"
  end
  local ext = type(name) == "string" and name:match("%.(%w+)$") or nil
  return (ext and EXT_GLYPHS[ext:lower()]) or "·"
end

function ui.drawTile(D, th, r, opts)
  opts = opts or {}
  local bg    = opts.selected and (th.sel_bg or th.highlight) or (th.panel_bg or th.bg)
  local fg    = opts.selected and (th.sel_fg or th.bg) or (opts.dim and (th.dim or th.fg) or th.fg)
  local frame = opts.selected and (th.highlight or th.title) or (th.border or th.dim or th.fg)
  local interior = r.w - 2
  D.set(r.x, r.y, "┌" .. string.rep("─", interior) .. "┐", frame, bg)
  for row = 1, r.h - 2 do
    D.set(r.x, r.y + row, "│" .. string.rep(" ", interior) .. "│", frame, bg)
  end
  D.set(r.x, r.y + r.h - 1, "└" .. string.rep("─", interior) .. "┘", frame, bg)

  local gy = r.y + r.h - 3
  local ly = r.y + r.h - 2
  if gy > r.y then
    D.set(r.x + math.floor(r.w / 2), gy, opts.glyph or "•",
      opts.selected and fg or (th.title or th.fg), bg)
  end
  local label = ufit(tostring(opts.label or ""), interior)
  local off = math.max(0, math.floor((interior - uwidth(label)) / 2))
  D.set(r.x + 1 + off, ly, label, fg, bg)
end

function ui.railText(W, parts)
  local segs, spans = {}, {}
  local col = 1
  local function fill(n)
    if n > 0 then segs[#segs + 1] = string.rep("─", n); col = col + n end
  end
  for _, p in ipairs(parts or {}) do
    local tabbed = p.label ~= nil
    local label = tostring(p.label or p.text or "")
    local lw = uwidth(label)
    if p.at and p.at > col then fill(p.at - col) end
    if col == 1 then fill(1) end
    local cellW = lw + (tabbed and 4 or 2)
    if col + cellW - 1 > W then
      local avail = W - col - (tabbed and 4 or 2)
      if avail < 1 then break end
      label = ufit(label, avail)
      lw = uwidth(label)
      cellW = lw + (tabbed and 4 or 2)
    end
    if tabbed then
      segs[#segs + 1] = "┤ " .. label .. " ├"
      spans[#spans + 1] = { s = col + 2, e = col + 1 + lw, label = label }
    else
      segs[#segs + 1] = " " .. label .. " "
      spans[#spans + 1] = { s = col + 1, e = col + lw, label = label }
    end
    col = col + cellW
  end
  fill(W - col + 1)
  return table.concat(segs), spans
end

function ui.drawRail(D, th, y, W, parts, opts)
  opts = opts or {}
  local line, spans = ui.railText(W, parts)
  local bg = opts.bg or th.bg
  D.set(1, y, line, opts.fg or th.dim or th.fg, bg)
  local lfg = opts.labelFg or th.fg
  for _, sp in ipairs(spans) do
    D.set(sp.s, y, sp.label, lfg, bg)
  end
  return spans
end

function ui.drawRampBar(D, th, y, W, left, right, fg, bg)
  fg = fg or th.statusbar_fg or th.bar_fg or th.fg
  bg = bg or th.statusbar_bg or th.bar_bg or th.bg
  local cap = th.dim or fg
  D.fill(1, y, W, 1, "░", cap, bg)
  D.set(1, y, "▓▒░", cap, bg)
  if W > 6 then D.set(W - 2, y, "░▒▓", cap, bg) end

  local lt = ufit(tostring(left or ""), math.max(0, W - 9))
  if uwidth(lt) > 0 then D.set(5, y, " " .. lt .. " ", fg, bg) end
  if right and #right > 0 then
    local rt = " " .. right .. " "
    local rx = W - 3 - #rt
    if rx > 5 + uwidth(lt) + 2 then D.set(rx, y, rt, fg, bg) end
  end
end

function ui.tabChips(tabs, activeIdx, labelW)
  labelW = labelW or 10
  local chips = {}
  for i, tab in ipairs(tabs or {}) do
    local label = tostring(tab.label or "?")
    label = ufit(label, labelW)
    local state = "idle"
    if i == activeIdx then state = "active"
    elseif tab.live or (tab.type == "edit" and tab.modified) then state = "busy" end
    local text = (state == "busy") and ("[" .. label .. "]") or (" " .. label .. " ")
    chips[#chips + 1] = { text = text, state = state, idx = i }
  end
  return chips
end

function ui.chipSpans(chips, rightEnd, leftMin)
  leftMin = leftMin or 1
  local keep = {}
  for i, c in ipairs(chips or {}) do keep[i] = c end
  local total = #keep
  local function totalW(list)
    local w = 0
    for i, c in ipairs(list) do w = w + uwidth(c.text) + (i > 1 and 1 or 0) end
    return w
  end
  while #keep > 1 and totalW(keep) > (rightEnd - leftMin + 1) do
    if keep[1].state == "active" then table.remove(keep, 2)
    else table.remove(keep, 1) end
  end
  if #keep == 1 and totalW(keep) > (rightEnd - leftMin + 1) then
    return {}, total
  end
  local spans = {}
  local x = rightEnd - totalW(keep) + 1
  for i, c in ipairs(keep) do
    if i > 1 then x = x + 1 end
    local w = uwidth(c.text)
    spans[#spans + 1] = { s = x, e = x + w - 1, idx = c.idx, text = c.text, state = c.state }
    x = x + w
  end
  return spans, total - #keep
end

function ui.fitChips(tabs, activeIdx, rightEnd, leftMin)
  local spans, hidden
  for _, lw in ipairs({ 10, 8, 6, 5 }) do
    local chips = ui.tabChips(tabs, activeIdx, lw)
    spans, hidden = ui.chipSpans(chips, rightEnd, leftMin)
    if hidden == 0 then return spans end
    if lw == 5 then

      local moreText = "«" .. hidden
      spans, hidden = ui.chipSpans(chips, rightEnd, leftMin + #moreText + 3)
      moreText = "«" .. hidden
      local s = ((spans[1] and spans[1].s) or (rightEnd - #moreText + 1)) - #moreText - 1
      if s >= leftMin then
        table.insert(spans, 1,
          { s = s, e = s + #moreText - 1, idx = 0, text = moreText, state = "more" })
      end
      return spans
    end
  end
  return spans or {}
end

function ui.menuSpans(menuDefs)
  local spans, x = {}, 2
  for i, m in ipairs(menuDefs or {}) do
    local cell = " " .. tostring(m.label or "") .. " "
    spans[#spans + 1] = { s = x, e = x + #cell - 1, idx = i, text = cell }
    x = x + #cell + 1
  end
  return spans
end

function ui.drawBar(D, th, y, W, left, right, fg, bg)
  fg = fg or th.bar_fg or th.fg
  bg = bg or th.bar_bg or th.bg
  D.fill(1, y, W, 1, " ", fg, bg)

  if left and #left > 0 then D.set(1, y, ufit(left, W), fg, bg) end
  if right and #right > 0 and #right < W then
    D.set(W - #right, y, right, fg, bg)
  end
end

function ui.drawSettingRow(D, th, y, x, w, row, selected)
  local bg = selected and (th.sel_bg or th.highlight) or th.bg
  local fg = selected and (th.sel_fg or th.bg) or th.fg
  D.fill(x, y, w, 1, " ", fg, bg)
  if row.kind == "header" then
    D.set(x, y, tostring(row.label or ""):sub(1, w), th.title or th.fg, th.bg)
  elseif row.kind == "info" then
    D.set(x + 1, y, tostring(row.text or ""):sub(1, w - 1), th.dim or th.fg, th.bg)
  elseif row.kind == "toggle" then
    local mark = row.value and "[x] " or "[ ] "
    D.set(x + 1, y, (mark .. tostring(row.label or "")):sub(1, w - 1), fg, bg)
  elseif row.kind == "choice" then
    D.set(x + 1, y, tostring(row.label or ""):sub(1, w - 1), fg, bg)

    local val = "« " .. tostring(row.value or "") .. " »"
    local vx = x + w - #val - 1
    if vx > x + 1 then
      D.set(vx, y, val, selected and fg or (th.highlight or th.fg), bg)
    end
  elseif row.kind == "button" then
    D.set(x + 1, y, ("[ " .. tostring(row.label or "") .. " ]"):sub(1, w - 1), fg, bg)
  end
end

function ui.rowSelectable(row)
  return row and (row.kind == "toggle" or row.kind == "choice"
    or row.kind == "button")
end

function ui.nextSelectable(rows, sel, dir)
  local n = sel
  repeat
    n = n + dir
    if n < 1 or n > #rows then return sel end
  until ui.rowSelectable(rows[n])
  return n
end

function ui.firstSelectable(rows)
  for i, r in ipairs(rows) do
    if ui.rowSelectable(r) then return i end
  end
  return nil
end

return ui
