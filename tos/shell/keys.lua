-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Shell — keybinds                                        ║
-- ║                                                              ║
-- ║  ONE TABLE, and everything first-party reads it: the shell,   ║
-- ║  its dialogs, the picker, and every bundled package.          ║
-- ║                                                              ║
-- ║  WHY THIS EXISTS. Operator, 2026-08-11: "^Q is the close      ║
-- ║  combination, the ttt game just uses Q to exit, which can be  ║
-- ║  confusing for Operators who prefer one standard." Correct    ║
-- ║  and worth more than it sounds — a shortcut you have to       ║
-- ║  remember PER PROGRAM is not a shortcut, it is trivia. So     ║
-- ║  the bindings live here rather than being re-decided in       ║
-- ║  every init.lua, and an operator can change them once and     ║
-- ║  have every TOS program follow.                                ║
-- ║                                                              ║
-- ║  THIS IS A CONVENTION, NOT A CAGE. A third-party package can  ║
-- ║  bind whatever it likes and nothing here stops it. What we    ║
-- ║  get by being consistent is that OUR packages feel like one   ║
-- ║  system — which is the difference the operator was after.     ║
-- ║                                                              ║
-- ║  Operator configuration, layered:                              ║
-- ║    /etc/keys.cfg    the machine's binds (admin)               ║
-- ║    ~/.keys.cfg      this user's, applied on top               ║
-- ║  Keys are written the way a person says them — "^Q", "F10",   ║
-- ║  "Ctrl+S", "/" — never scancodes. A config nobody can read    ║
-- ║  back is a config nobody will edit.                           ║
-- ║                                                              ║
-- ║  Reachable from sandboxed package code (kernel.sandbox's      ║
-- ║  ALLOWED_MODULE_NAMES), because a keybind table that only     ║
-- ║  the base image could see would standardise nothing. It is    ║
-- ║  safe to expose: it reads two config files and returns key    ║
-- ║  matchers. No authority passes through it.                     ║
-- ╚══════════════════════════════════════════════════════════════╝

local keys = {}

-- ============================================================
-- The standard actions
-- ============================================================
--! Deliberately SMALL. These are the bindings that mean the same thing
--! in every program; anything a single program invented stays in that
--! program. A "standard" that tries to cover every key ends up
--! describing none of them.
--!
--! ESC IS LISTED ON `quit` AND IS NOT THE POINT. It never arrives in
--! real Minecraft — it closes the screen GUI — so it is here only so
--! that an emulator, or some future OC build that does deliver it,
--! behaves the same. See the convention block in panels/keymap.lua.
local DEFAULTS = {
  quit    = { "^Q", "F10", "Esc" },
  help    = { "F1" },
  save    = { "^S" },
  find    = { "/" },
  refresh = { "^R" },
  view    = { "F2" },
  --! COPY IS Ctrl+Insert, NOT ^C, AND THAT IS NOT A STYLE CHOICE.
  --! kernel/init.lua consumes char 3 to interrupt the foreground process
  --! and then blanks the signal, so ^C never reaches a program at all —
  --! see RESERVED below. DOS and Norton Commander landed on
  --! Ctrl+Insert / Shift+Insert / Shift+Delete for exactly the same
  --! reason a decade before ^C/^X/^V existed, and TOS looks like Norton
  --! Commander on purpose. ^X and ^V are free, so they are kept as the
  --! second binding for the two that can have one.
  copy    = { "Ctrl+Insert" },
  cut     = { "Shift+Delete", "^X" },
  paste   = { "Shift+Insert", "^V" },
}

local DESCRIPTIONS = {
  quit    = "Close the current program, prompt or dialog",
  help    = "Show the program's help",
  save    = "Save",
  find    = "Filter / search within a list",
  refresh = "Re-read and redraw",
  --! THE SIXTH ACTION, added with the merged Home surface. It is here
  --! rather than as a bespoke panels scancode for the reason the whole
  --! file exists: "flip to the other view" is a thing an operator will
  --! want to rebind, and every surface that draws an F2 legend reads
  --! keys.label("view") so the label can never disagree with the bind.
  view    = "Switch the view (Home: tiles or files)",
  copy    = "Copy the selection (^C is the kernel's interrupt)",
  cut     = "Cut the selection",
  paste   = "Paste the clipboard",
}

--! NOT REBINDABLE, and listed so `keys` can say so rather than leaving
--! an operator to discover it by trying. These are consumed by the
--! KERNEL before a program ever sees them — rebinding them here would
--! produce a setting that silently does nothing.
local RESERVED = {
  ["^B"] = "background the current program (kernel)",
  ["^T"] = "switch tasks / open the Monitor (kernel)",
  ["^C"] = "interrupt the foreground program (kernel)",
}

-- ============================================================
-- Key names ↔ matchers
-- ============================================================
-- A matcher is { ch = <char code> } or { code = <scancode> }. OC hands
-- key_down both; letters arrive as chars and function/arrow keys as
-- scancodes, which is why one form cannot cover both.

local NAMED = {
  esc = { code = 1 },      enter = { code = 28 },  tab = { code = 15 },
  space = { code = 57 },   backspace = { code = 14 },
  delete = { code = 211 }, insert = { code = 210 },
  home = { code = 199 },   ["end"] = { code = 207 },
  pageup = { code = 201 }, pagedown = { code = 209 },
  up = { code = 200 },     down = { code = 208 },
  left = { code = 203 },   right = { code = 205 },
}
for i = 1, 10 do NAMED["f" .. i] = { code = 58 + i } end   -- F1=59 … F10=68
NAMED.f11, NAMED.f12 = { code = 87 }, { code = 88 }

--- Parse a human key name into a matcher, or nil.
-- Accepts "F10", "Esc", "^Q", "Ctrl+Q", "ctrl-q", "/", "a", and
-- modifier+named forms like "Ctrl+Insert", "Shift+Delete", "Alt+Enter".
function keys.parse(name)
  if type(name) ~= "string" then return nil end
  local s = name:match("^%s*(.-)%s*$")
  if s == "" then return nil end

  -- Ctrl forms. In OC a control chord arrives as the character with the
  -- top bits cleared: ^A is 1, ^Q is 17. Not a scancode.
  local c = s:match("^%^(.)$") or s:match("^[Cc][Tt][Rr][Ll][%+%-](.)$")
  if c then
    local b = c:upper():byte()
    if b and b >= 64 and b <= 95 then return { ch = b - 64, ctrl = c:upper() } end
    return nil
  end

  --! Modifier + NAMED key. A letter chord encodes its modifier in the
  --! character OC delivers (^Q arrives as 17), but a named key does not:
  --! Shift+Delete and Delete are the same scancode with no character at
  --! all, so the only way to tell them apart is to know what was held.
  --! Matchers therefore carry the requirement and `keys.is` is handed
  --! the live modifier state. Order is free — "Ctrl+Shift+Home" parses.
  local mods, rest = {}, s
  while true do
    local mod, tail = rest:match("^([%a]+)[%+%-](.+)$")
    if not mod then break end
    local low = mod:lower()
    if low == "ctrl" or low == "control" then mods.ctrl = true
    elseif low == "shift" then mods.shift = true
    elseif low == "alt" then mods.alt = true
    else break end
    rest = tail
  end

  local named = NAMED[rest:lower()]
  if named then
    local m = { code = named.code }
    m.needCtrl, m.needShift, m.needAlt = mods.ctrl, mods.shift, mods.alt
    return m
  end

  -- A single printable character binds to itself (no modifier prefixes:
  -- a modified letter is the ^X form above).
  if rest == s and #s == 1 then
    local b = s:byte()
    if b >= 32 and b < 127 then return { ch = b } end
  end
  return nil
end

--- Render a matcher back as the name a person would write.
function keys.name(m)
  if type(m) ~= "table" then return "?" end
  if m.ctrl then return "^" .. m.ctrl end
  if m.ch then
    if m.ch < 32 then return "^" .. string.char(m.ch + 64) end
    return string.char(m.ch)
  end
  local prefix = ""
  if m.needCtrl  then prefix = prefix .. "Ctrl+" end
  if m.needShift then prefix = prefix .. "Shift+" end
  if m.needAlt   then prefix = prefix .. "Alt+" end
  for n, v in pairs(NAMED) do
    if v.code == m.code then return prefix .. (n:gsub("^%l", string.upper)) end
  end
  return prefix .. "code " .. tostring(m.code)
end

-- ============================================================
-- Modifier state
-- ============================================================
--! OC delivers key_down/key_up for the modifier keys themselves, and
--! that is the ONLY way to know whether Shift is held: Shift+Left and
--! Left are byte-identical in a key_down signal (no character, same
--! scancode). Selection therefore needs a tiny state machine, and it
--! lives here rather than in the shell so both shells and any package
--! can share one answer.
--!
--! THE STUCK-MODIFIER PROBLEM IS REAL, and it is the Esc problem
--! wearing a different hat: hold Shift, press Esc to close the screen
--! GUI, release Shift somewhere else — the key_up never arrives and TOS
--! believes Shift is still down. So the state also EXPIRES. A modifier
--! nobody has touched for STALE_AFTER seconds is treated as released,
--! which costs a held-Shift-and-thinking operator nothing (the next
--! keypress re-asserts it) and un-wedges the case that would otherwise
--! need a re-login to clear.
local MOD_CODES = {
  [42] = "shift", [54] = "shift",     -- lshift / rshift
  [29] = "ctrl",  [157] = "ctrl",     -- lcontrol / rcontrol
  [56] = "alt",   [184] = "alt",      -- lmenu / rmenu
}
local STALE_AFTER = 15

--- A fresh modifier-state table.
function keys.newMods()
  return { shift = false, ctrl = false, alt = false, at = 0 }
end

--- Fold one signal into `mods`. Pure apart from mutating `mods`, so a
--- test can drive a whole keyboard sequence through it.
--- Returns true when the signal WAS a modifier key (caller may ignore it).
function keys.trackMods(mods, sig, ch, co, now)
  if type(mods) ~= "table" then return false end
  now = now or 0
  -- Expire first: a stale reading must not survive into this decision.
  if mods.at > 0 and (now - mods.at) > STALE_AFTER then
    mods.shift, mods.ctrl, mods.alt = false, false, false
  end
  local which = MOD_CODES[co]
  if sig == "key_down" then
    if which then mods[which] = true; mods.at = now; return true end
    -- A printable character proves Ctrl and Alt are NOT held: both
    -- suppress the character. Cheap self-correction for a lost key_up.
    if ch and ch >= 32 then mods.ctrl, mods.alt = false, false end
    mods.at = now
  elseif sig == "key_up" then
    if which then mods[which] = false; mods.at = now; return true end
    mods.at = now
  end
  return false
end

--- Is a modifier held, honouring the staleness rule?
function keys.modDown(mods, which, now)
  if type(mods) ~= "table" then return false end
  if mods.at > 0 and ((now or 0) - mods.at) > STALE_AFTER then return false end
  return mods[which] == true
end

keys.MOD_CODES = MOD_CODES
keys.STALE_AFTER = STALE_AFTER

-- ============================================================
-- Loading
-- ============================================================
local _cache = {}   -- who -> resolved binding table

local function decodeFile(path)
  local okF, fs = pcall(require, "kernel.fs")
  local okS, ser = pcall(require, "kernel.serialize")
  if not (okF and okS and fs and ser and fs.exists and fs.exists(path)) then return nil end
  local raw = fs.readFile(path)
  if type(raw) ~= "string" or #raw == 0 or #raw > 8192 then return nil end
  local ok, t = pcall(ser.decode, raw, { maxBytes = 8192 })
  if ok and type(t) == "table" then return t end
  return nil
end

--! Apply one config over `out`. An action names a LIST of keys, and a
--! config REPLACES that action's list rather than adding to it — "quit
--! is F4" has to be able to mean only F4, or an operator can never take
--! a binding away. Unknown actions and unparseable names are skipped
--! individually: a typo in a keybind file must not cost the operator the
--! key they would use to get out of the program that reads it.
local function applyConfig(out, cfg)
  if type(cfg) ~= "table" then return end
  for action, spec in pairs(cfg) do
    if DEFAULTS[action] ~= nil and (type(spec) == "string" or type(spec) == "table") then
      local list = (type(spec) == "string") and { spec } or spec
      local parsed = {}
      for _, name in ipairs(list) do
        local m = keys.parse(name)
        if m then parsed[#parsed + 1] = m end
      end
      if #parsed > 0 then out[action] = parsed end
    end
  end
end

local function homeOf(who)
  if not who or who == "" then return nil end
  return (who == "root") and "/root" or ("/home/" .. who)
end

--- Resolved bindings for `who` (defaults to the live session's user).
function keys.load(who)
  if not who then
    local okU, users = pcall(require, "kernel.users")
    if okU and users and users.currentSession then
      local s = users.currentSession()
      who = s and s.user or nil
    end
  end
  local ck = who or "*"
  if _cache[ck] then return _cache[ck] end

  local out = {}
  for action, names in pairs(DEFAULTS) do
    local list = {}
    for _, n in ipairs(names) do
      local m = keys.parse(n)
      if m then list[#list + 1] = m end
    end
    out[action] = list
  end
  applyConfig(out, decodeFile("/etc/keys.cfg"))
  local home = homeOf(who)
  if home then applyConfig(out, decodeFile(home .. "/.keys.cfg")) end

  _cache[ck] = out
  return out
end

function keys.reload()
  _cache = {}
  return true
end

-- ============================================================
-- The API programs use
-- ============================================================

--- Does this keypress mean `action`?
-- @param action  "quit" | "help" | "save" | "find" | "refresh" | "view"
--                | "copy" | "cut" | "paste"
-- @param ch      character code from key_down (may be nil)
-- @param code    scancode from key_down (may be nil)
-- @param who     user whose bindings to read (defaults to the session's)
-- @param mods    live modifier state from keys.trackMods (optional)
--
--! `mods` IS OPTIONAL AND THAT IS LOAD-BEARING. Every call site that
--! predates modifier-aware bindings passes four arguments and must keep
--! behaving identically, so a matcher's modifier requirements are only
--! enforced when the caller actually knows the modifier state. A caller
--! that does pass it gets the strict reading: Shift+Delete matches only
--! with Shift held, and plain Delete matches only WITHOUT it — which is
--! the whole point, since they are the same scancode.
function keys.is(action, ch, code, who, mods)
  local bind = keys.load(who)[action]
  if not bind then return false end
  for _, m in ipairs(bind) do
    if m.ch and ch and m.ch == ch then return true end
    if m.code and code and m.code == code then
      if not mods then return true end
      local wantCtrl  = m.needCtrl  == true
      local wantShift = m.needShift == true
      local wantAlt   = m.needAlt   == true
      if (mods.ctrl == true) == wantCtrl
         and (mods.shift == true) == wantShift
         and (mods.alt == true) == wantAlt then
        return true
      end
    end
  end
  return false
end

--- The keys bound to `action`, as the names a person would write:
--- "^Q / F10". For help text, so a footer can never disagree with what
--- the program actually listens for.
function keys.label(action, who)
  local bind = keys.load(who)[action]
  if not bind or #bind == 0 then return "" end
  local parts = {}
  for _, m in ipairs(bind) do
    -- Esc is honoured but never ADVERTISED: telling an operator to press
    -- it is exactly the bug this whole convention came from.
    if m.code ~= 1 then parts[#parts + 1] = keys.name(m) end
  end
  return table.concat(parts, " / ")
end

--- Every action, for `keys list` and for the settings UI.
function keys.actions(who)
  local bound = keys.load(who)
  local out = {}
  for action in pairs(DEFAULTS) do out[#out + 1] = action end
  table.sort(out)
  local rows = {}
  for _, action in ipairs(out) do
    local names = {}
    for _, m in ipairs(bound[action] or {}) do names[#names + 1] = keys.name(m) end
    rows[#rows + 1] = {
      action = action,
      keys   = table.concat(names, " "),
      help   = DESCRIPTIONS[action] or "",
      isDefault = table.concat(names, " ") == table.concat(DEFAULTS[action], " "),
    }
  end
  return rows
end

--- Kernel-owned chords, so `keys` can say why rebinding them is refused.
function keys.reserved()
  local out = {}
  for k, v in pairs(RESERVED) do out[#out + 1] = { key = k, help = v } end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

--- Is this key name reserved by the kernel?
function keys.isReserved(name)
  local m = keys.parse(name)
  if not m or not m.ctrl then return false end
  return RESERVED["^" .. m.ctrl] ~= nil
end

keys.DEFAULTS = DEFAULTS

return keys
