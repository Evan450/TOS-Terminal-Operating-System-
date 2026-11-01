-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  prefab: what both designers draw with                       ║
-- ║                                                              ║
-- ║  The screen, the keys, and pop-ups in the shell's dialog     ║
-- ║  style, shared by the blueprint designer and the base        ║
-- ║  layout. new() takes component, computer and shell.keys      ║
-- ║  because this file is loaded once and they belong to the     ║
-- ║  sandbox that called it.                                     ║
-- ╚══════════════════════════════════════════════════════════════╝

local M = {}

--- Eight colours a block can be told apart by. Tier 1 has none, so there
--- a block is its letter, reversed.
local T3_BLOCKS = { 0xB0B0B0, 0xC08040, 0x60C0FF, 0x60C060, 0xE06060, 0xE0C040, 0xC060E0, 0x40C0B0 }
local T2_BLOCKS = { 0xCCCCCC, 0xFFCC33, 0x6699FF, 0x33CC33, 0xFF3333, 0xFFFF33, 0xCC66CC, 0x336699 }

function M.new(component, computer, KEYS)
  local U = {}

  U.K = { ENTER = 28, BACK = 14, DEL = 211, TAB = 15, UP = 200, DOWN = 208,
          LEFT = 203, RIGHT = 205, PGUP = 201, PGDN = 209 }

  function U.isQuit(ch, code)
    if KEYS and KEYS.is then return KEYS.is("quit", ch, code) end
    return ch == 17 or code == 68 or code == 1
  end
  function U.quitLabel()
    if KEYS and KEYS.label then
      local l = KEYS.label("quit")
      if l ~= "" then return l end
    end
    return "^Q"
  end

  -- ── Text that measures in screen columns ─────────────────────────
  local function ulen(s)
    local n = 0
    for i = 1, #s do
      local b = s:byte(i)
      if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
  end
  local function usub(s, a, b)
    local starts, n = {}, 0
    for i = 1, #s do
      local by = s:byte(i)
      if by < 0x80 or by >= 0xC0 then n = n + 1; starts[n] = i end
    end
    starts[n + 1] = #s + 1
    a, b = math.max(1, a), math.min(n, b)
    if a > b then return "" end
    return s:sub(starts[a], starts[b + 1] - 1)
  end
  local function pad(s, n)
    s = tostring(s or "")
    local w = ulen(s)
    if w > n then return usub(s, 1, n) end
    return s .. string.rep(" ", n - w)
  end
  U.ulen, U.usub, U.pad = ulen, usub, pad

  --- The key bar: hints that fit whole, and the way out always last.
  function U.fitKeys(hints, out, width)
    local sep = " \194\183 "
    local kept = {}
    for _, h in ipairs(hints) do
      kept[#kept + 1] = h
      if ulen(table.concat(kept, sep) .. sep .. out) > width then kept[#kept] = nil; break end
    end
    if #kept == 0 then return out end
    return table.concat(kept, sep) .. sep .. out
  end

  --- Plain word wrap.
  function U.wrap(text, width)
    local out, line = {}, ""
    for word in tostring(text):gmatch("%S+") do
      if line == "" then line = word
      elseif ulen(line) + 1 + ulen(word) <= width then line = line .. " " .. word
      else out[#out + 1] = line; line = word end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
  end

  -- ── The screen ───────────────────────────────────────────────────
  function U.screen()
    local addr = component.list and component.list("gpu")()
    if not addr then return nil, "no GPU" end
    local okG, gpu = pcall(component.proxy, addr)
    if not okG or not gpu then return nil, "cannot open the GPU" end
    local Wd, Ht = gpu.getResolution()
    if not Wd or Wd < 50 or Ht < 16 then
      return nil, string.format("the designer needs 50x16 (this one is %sx%s)", tostring(Wd), tostring(Ht))
    end
    local okD, depth = pcall(gpu.getDepth)
    local tier = (okD and type(depth) == "number") and (depth <= 1 and 1 or (depth <= 4 and 2 or 3)) or 1
    local T = (tier == 1) and {
      fg = 0xFFFFFF, dim = 0xFFFFFF, bg = 0x000000, border = 0xFFFFFF, title = 0xFFFFFF,
      hi = 0xFFFFFF, warn = 0xFFFFFF, selfg = 0x000000, selbg = 0xFFFFFF,
    } or {
      fg = 0xFFFFFF, dim = tier == 2 and 0x333333 or 0x666666, bg = 0x000000,
      border = tier == 2 and 0x6699FF or 0x00C0FF, title = tier == 2 and 0xFFFF33 or 0xFFFF00,
      hi = tier == 2 and 0x33CC33 or 0x00FF00, warn = tier == 2 and 0xFF3333 or 0xFF4040,
      selfg = 0x000000, selbg = 0xFFFFFF,
    }
    local S = { W = Wd, H = Ht, tier = tier, T = T, gpu = gpu, mono = tier == 1,
                blocks = tier == 2 and T2_BLOCKS or T3_BLOCKS }
    function S.set(x, y, s, fg, bg)
      if fg then pcall(gpu.setForeground, fg) end
      if bg then pcall(gpu.setBackground, bg) end
      pcall(gpu.set, x, y, s)
    end
    function S.fill(x, y, w, h, ch, fg, bg)
      if fg then pcall(gpu.setForeground, fg) end
      if bg then pcall(gpu.setBackground, bg) end
      pcall(gpu.fill, x, y, w, h, ch or " ")
    end
    return S
  end

  function U.pullEvent()
    local e = { computer.pullSignal() }
    if e[1] == "key_down" then return "key", e[3], e[4] end
    if e[1] == "interrupted" then return "key", 17, nil end
    if e[1] == "touch" or e[1] == "drag" then return "mouse", e[3], e[4], e[5], e[1] end
    return e[1]
  end

  -- ── Pop-ups, in the shell's dialog style ─────────────────────────
  --- draw() repaints what is behind a pop-up.
  function U.kit(S, draw)
    local T, Wd, Ht = S.T, S.W, S.H
    local kit = {}
    local function tone(t) return T[t] or T.fg end

    local function box(title, x, y, w, h)
      local mono = S.mono
      local hz, vt = mono and "=" or "═", mono and "|" or "║"
      if not mono then
        S.set(x + 1, y + h, string.rep(" ", w), T.bg, 0x1A1A1A)
        S.fill(x + w, y + 1, 1, h, " ", T.bg, 0x1A1A1A)
      end
      local inner = string.rep(hz, w - 2)
      S.set(x, y, (mono and "+" or "╔") .. inner .. (mono and "+" or "╗"), T.border, T.bg)
      S.set(x, y + h - 1, (mono and "+" or "╚") .. inner .. (mono and "+" or "╝"), T.border, T.bg)
      S.fill(x, y + 1, 1, h - 2, vt, T.border, T.bg)
      S.fill(x + w - 1, y + 1, 1, h - 2, vt, T.border, T.bg)
      S.fill(x + 1, y + 1, w - 2, h - 2, " ", T.fg, T.bg)
      local label = pad(title, math.min(ulen(title), w - 6))
      S.set(x + math.floor((w - ulen(label) - 4) / 2), y,
        (mono and "[ " or "╡ ") .. label .. (mono and " ]" or " ╞"), T.title, T.bg)
    end

    function kit.popup(title, lines, hint, rows)
      draw()
      local w = math.min(Wd - 6, 64)
      local n = math.min(#lines, Ht - 6 - rows)
      local h = n + rows + 4
      local x, y = math.floor((Wd - w) / 2) + 1, math.floor((Ht - h) / 2) + 1
      box(title, x, y, w, h)
      for i = 1, n do S.set(x + 2, y + i, pad(lines[i][1], w - 4), tone(lines[i][2]), T.bg) end
      S.set(x + 2, y + h - 2, pad(hint, w - 4), T.dim, T.bg)
      return x, y + n + 1, w
    end

    function kit.nextKey()
      while true do
        local kind, a, b = U.pullEvent()
        if kind == "key" then return a, b end
      end
    end

    function kit.prompt(title, label, initial)
      local buf = tostring(initial or "")
      local fresh = buf ~= ""              -- the first letter typed replaces it
      local x, y, w = kit.popup(title, { { label, "fg" } }, "Enter OK · " .. U.quitLabel() .. " cancel", 1)
      while true do
        local line = buf .. "_"
        local over = ulen(line) - (w - 4)
        if over > 0 then line = usub(line, over + 1, ulen(line)) end
        S.set(x + 2, y, pad(line, w - 4), T.title, T.bg)
        local ch, code = kit.nextKey()
        if code == U.K.ENTER then return buf end
        if U.isQuit(ch, code) then return nil end
        if code == U.K.BACK then buf = buf:sub(1, -2)
        elseif ch and ch >= 32 and ch < 127 then
          if fresh then buf = "" end
          buf = buf .. string.char(ch)
        end
        fresh = false
      end
    end

    function kit.yesNo(question)
      local lines = {}
      for _, l in ipairs(U.wrap(question, 56)) do lines[#lines + 1] = { l, "warn" } end
      kit.popup("Confirm", lines, "Y Yes · N No", 0)
      while true do
        local ch, code = kit.nextKey()
        if U.isQuit(ch, code) then return false end
        if ch and ch > 0 then
          local c = string.char(ch):lower()
          if c == "y" then return true end
          if c == "n" then return false end
        end
      end
    end

    return kit
  end

  return U
end

return M
