-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Colophon — a note from the author                       ║
-- ║                                                              ║
-- ║  The SECOND easter egg, and unlike the takeover cinematic it ║
-- ║  is not a reference to anything. It is just a note, left     ║
-- ║  where somebody would only find it by wondering whether      ║
-- ║  something was there.                                        ║
-- ║                                                              ║
-- ║  It is deliberately undiscoverable from inside the OS: no    ║
-- ║  command lists it, no help mentions it, nothing hints at it  ║
-- ║  on the login screen, and it is absent from every shipped    ║
-- ║  document (MANUAL/README/CHANGELOG are all Release-excluded  ║
-- ║  or silent on it). If nobody ever types it, that is fine —   ║
-- ║  it is here because it should be, not because it should be   ║
-- ║  found.                                                      ║
-- ║                                                              ║
-- ║  It grants NOTHING. No session, no token, no tier: it draws  ║
-- ║  text and returns to the login screen. See colophon.run.     ║
-- ║                                                              ║
-- ║  PHOTOSENSITIVITY RULE (inherited from panels/takeover.lua): ║
-- ║  no strobing, no full-field colour flips. This screen is     ║
-- ║  static text revealed a line at a time; every hold is well   ║
-- ║  over 0.1s and any key skips straight to the end.            ║
-- ╚══════════════════════════════════════════════════════════════╝

local colophon = {}

-- ── The note ──────────────────────────────────────────────────────
-- AUTHOR'S TEXT. This is the one place in TOS where the prose belongs
-- to the author rather than to the system — edit freely; nothing below
-- depends on the wording, only on the line count fitting a screen.
colophon.AUTHOR = "Evan"

-- { text, role }  — role picks the colour (see ROLE_COLORS).
-- Keep lines <= 58 columns so the note composes on an 80x25 screen and
-- degrades onto a T1 50x16 without wrapping mid-word.
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

-- ── Mechanism ─────────────────────────────────────────────────────

-- The trigger: an EMPTY username and this exact password. 65536 is the
-- number the takeover cinematic lands on twice ("65,536 games. 65,536
-- draws."), which is the only place it is written down.
colophon.PASSPHRASE = "65536"

--- Does this (username, password) pair open the note?
--- PURE — the whole trigger decision lives here so it can be tested
--- without a screen, and so it is obvious that it can never authorise
--- anything: it returns a boolean, not a session.
function colophon.isTrigger(username, password)
  if type(password) ~= "string" then return false end
  -- Only a genuinely EMPTY name. A name of spaces is a typo, not this.
  if username ~= nil and username ~= "" then return false end
  return password == colophon.PASSPHRASE
end

local ROLE_COLORS = {
  title  = "highlight",
  accent = "highlight",
  dim    = "dim",
  fg     = "fg",
}

--- Lay the note out for a screen of W x H. PURE.
--- Returns { {x, y, text, role}, ... } plus the row the footer goes on,
--- or nil when the screen is too small to hold the note at all.
function colophon.layout(W, H, note, width)
  note = note or colophon.NOTE
  local widest = 0
  for _, ln in ipairs(note) do
    local n = #ln[1]
    if width then n = width(ln[1]) end
    if n > widest then widest = n end
  end
  -- One blank row above and below, plus a footer row and its gap.
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

--- Draw the note, then wait for the operator, then return.
--- ctx = {
---   W, H,                       screen size
---   clear(bg),                  full clear
---   set(x, y, text, fg, bg),    draw
---   theme,                      { fg, dim, highlight, bg }
---   pull(timeout),              seat-safe signal read
---   sleep(sec),                 cooperative sleep
---   width(s),                   optional column width fn
--- }
--- ALWAYS returns nil: there is no success path, because there is
--- nothing to succeed at. The caller redraws the login screen.
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
    -- Too small to compose: say the one line that matters and leave.
    ctx.set(1, 1, "Thanks for looking.  - " .. colophon.AUTHOR,
      th.highlight or th.fg or 0xFFFFFF, bg)
    ctx.sleep(3)
    return nil
  end

  -- Reveal a line at a time. This is the ONLY animation, it is additive
  -- (nothing already drawn changes), and each step is 0.12s — far above
  -- the photosensitivity floor and nowhere near a flash.
  local skipped = false
  for _, r in ipairs(rows) do
    ctx.set(r.x, r.y, r.text, colour(r.role), bg)
    if not skipped then
      local sig = ctx.pull(0.12)
      if sig == "key_down" then skipped = true end   -- draw the rest at once
    end
  end
  ctx.set(rows[1].x, footerY - 1, "- " .. colophon.AUTHOR,
    th.dim or th.fg or 0xFFFFFF, bg)

  -- Hold, then wait for a key. The hold means a fast skipper still sees
  -- the whole note; the wait means nobody is rushed off it.
  ctx.sleep(0.8)
  ctx.set(rows[1].x, footerY + 1, "(any key)", th.dim or 0xAAAAAA, bg)
  local deadline = (ctx.uptime and ctx.uptime() or 0) + 120
  while true do
    local sig = ctx.pull(0.5)
    if sig == "key_down" then break end
    -- Never strand a seat on this screen if the machine is left alone.
    if ctx.uptime and ctx.uptime() >= deadline then break end
  end
  return nil
end

return colophon
