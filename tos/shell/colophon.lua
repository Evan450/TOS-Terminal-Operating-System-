local colophon = {}

colophon.AUTHOR = "Evan"

colophon.NOTE = {
  { "TOS", "title" },
  { "Terminal Operating System", "dim" },
  { "", "dim" },
  { "There was no reason to build this.", "fg" },
  { "", "dim" },
  { "OpenComputers hands you a machine with a couple of", "fg" },
  { "megabytes of memory, a screen eighty characters wide,", "fg" },
  { "and a language with nothing underneath it. You were", "fg" },
  { "meant to write a script. I wrote accounts and", "fg" },
  { "permissions instead, then a shell to reach them,", "fg" },
  { "and then a filesystem that did not need to exist.", "fg" },
  { "", "dim" },
  { "Somewhere in there it stopped being a hobby.", "fg" },
  { "", "dim" },
  { "If you're reading this, you gave it no name and a", "fg" },
  { "number for a password, on the chance that something", "fg" },
  { "was hidden here. I'll be the first to admit that there was.", "fg" },
  { "", "dim" },
  { "Thanks for looking.", "accent" },
}

colophon.PASSPHRASE = "65536"

function colophon.isTrigger(username, password)
  if type(password) ~= "string" then return false end

  if username ~= nil and username ~= "" then return false end
  return password == colophon.PASSPHRASE
end

local ROLE_COLORS = {
  title  = "highlight",
  accent = "highlight",
  dim    = "dim",
  fg     = "fg",
}

function colophon.layout(W, H, note, width)
  note = note or colophon.NOTE
  local widest = 0
  for _, ln in ipairs(note) do
    local n = #ln[1]
    if width then n = width(ln[1]) end
    if n > widest then widest = n end
  end

  if H < #note + 4 or W < widest + 2 then return nil end
  local top  = math.max(2, math.floor((H - #note - 2) / 2))
  local left = math.max(1, math.floor((W - widest) / 2) + 1)
  local out = {}
  for i, ln in ipairs(note) do
    if ln[1] ~= "" then
      out[#out + 1] = { x = left, y = top + i - 1, text = ln[1], role = ln[2] }
    end
  end
  return out, math.min(H - 1, top + #note + 1)
end

function colophon.run(ctx)
  local th = ctx.theme or {}
  local bg = th.bg or 0x000000
  local function colour(role)
    local key = ROLE_COLORS[role] or "fg"
    return th[key] or th.fg or 0xFFFFFF
  end

  local rows, footerY = colophon.layout(ctx.W, ctx.H, colophon.NOTE, ctx.width)
  ctx.clear(bg)
  if not rows then

    ctx.set(1, 1, "Thanks for looking.  - " .. colophon.AUTHOR,
      th.highlight or th.fg or 0xFFFFFF, bg)
    ctx.sleep(3)
    return nil
  end

  local skipped = false
  for _, r in ipairs(rows) do
    ctx.set(r.x, r.y, r.text, colour(r.role), bg)
    if not skipped then
      local sig = ctx.pull(0.12)
      if sig == "key_down" then skipped = true end
    end
  end
  ctx.set(rows[1].x, footerY - 1, "- " .. colophon.AUTHOR,
    th.dim or th.fg or 0xFFFFFF, bg)

  ctx.sleep(0.8)
  ctx.set(rows[1].x, footerY + 1, "(any key)", th.dim or 0xAAAAAA, bg)
  local deadline = (ctx.uptime and ctx.uptime() or 0) + 120
  while true do
    local sig = ctx.pull(0.5)
    if sig == "key_down" then break end

    if ctx.uptime and ctx.uptime() >= deadline then break end
  end
  return nil
end

return colophon
