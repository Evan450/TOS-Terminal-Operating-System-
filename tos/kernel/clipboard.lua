-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Kernel — the text clipboard                             ║
-- ║                                                              ║
-- ║  ONE clipboard, so text copied in the editor pastes at the   ║
-- ║  prompt and text copied from a command's output pastes into  ║
-- ║  the editor. Before this there were two half-clipboards and  ║
-- ║  neither could see the other: `S.editClipboard` held whole   ║
-- ║  LINES for the editor and nothing else could reach it, and   ║
-- ║  the command line had no clipboard at all.                   ║
-- ║                                                              ║
-- ║  NOT THE FILE CLIPBOARD. `S.clipboard` in the panels shell   ║
-- ║  holds a file the operator marked with F5, and pasting THAT  ║
-- ║  copies a file. Two different verbs that happen to share an  ║
-- ║  English word; keeping them separate is deliberate, because  ║
-- ║  merging them would make "paste" mean two things depending   ║
-- ║  on invisible state.                                         ║
-- ║                                                              ║
-- ║  PER SEAT. A multi-seat rig is several people at several     ║
-- ║  screens; one global clipboard would let them read each      ║
-- ║  other's copies by accident, which is both a privacy leak    ║
-- ║  and merely confusing. Seat is the display index, resolved   ║
-- ║  from the kernel when the caller doesn't name one.           ║
-- ║                                                              ║
-- ║  NOT SANDBOX-REACHABLE, and this is the one thing to think   ║
-- ║  twice about before changing. `shell.keys` is allowlisted    ║
-- ║  for package code because a keybind table carries no         ║
-- ║  authority. A clipboard carries whatever the operator last   ║
-- ║  copied — which is sometimes a password on its way to a      ║
-- ║  prompt. A background package that could poll this would be  ║
-- ║  a keylogger with extra steps, so it stays out of            ║
-- ║  kernel.sandbox's ALLOWED_MODULE_NAMES.                      ║
-- ╚══════════════════════════════════════════════════════════════╝

local clipboard = {}

--! BOUNDED, because this is heap on a machine that considers 192 KB of
--! free RAM a comfortable day. A runaway `clip set` or a select-all over
--! a 4 MB log must cost a truncation notice, not the session. The caps
--! are stated out loud by `describe()` whenever they bite — a clipboard
--! that silently holds less than you copied is worse than one that
--! refuses, because you find out at paste time.
local MAX_BYTES = 16 * 1024
local MAX_LINES = 512

-- seat -> { lines = { "..." }, bytes = n, truncated = bool }
local store = {}

local function seatOf(seat)
  if seat ~= nil then return seat end
  local K = _G._TOS and _G._TOS.kernel
  if K and K.getDisplayIdx then
    local ok, idx = pcall(K.getDisplayIdx)
    if ok and idx then return idx end
  end
  return 0   -- single-display / off-box: one shared slot, still not global
end

--- Normalize a value into an array of lines, bounded.
--- Accepts a string (split on newlines) or an array of strings.
--- Returns (lines, truncated).
local function normalize(value)
  local lines, truncated = {}, false
  local bytes = 0

  local function push(s)
    if #lines >= MAX_LINES then truncated = true; return false end
    s = tostring(s or ""):gsub("[\r\n]", "")
    if bytes + #s > MAX_BYTES then
      local room = MAX_BYTES - bytes
      if room > 0 then lines[#lines + 1] = s:sub(1, room) end
      truncated = true
      return false
    end
    lines[#lines + 1] = s
    bytes = bytes + #s + 1
    return true
  end

  if type(value) == "string" then
    -- Split on \n and keep empty lines: a blank line in the middle of a
    -- copied block is content, not noise.
    local from = 1
    while true do
      local at = value:find("\n", from, true)
      if not at then push(value:sub(from)); break end
      if not push(value:sub(from, at - 1)) then break end
      from = at + 1
    end
  elseif type(value) == "table" then
    for _, l in ipairs(value) do
      if not push(l) then break end
    end
  else
    return nil, false
  end

  return lines, truncated
end

--- Put text on the seat's clipboard. `value` is a string or an array of
--- lines. Returns (true, truncated) or (false, reason).
function clipboard.set(value, seat)
  local lines, truncated = normalize(value)
  if not lines then return false, "clipboard takes a string or a list of lines" end
  if #lines == 0 then lines = { "" } end
  local bytes = 0
  for _, l in ipairs(lines) do bytes = bytes + #l + 1 end
  store[seatOf(seat)] = { lines = lines, bytes = bytes, truncated = truncated }
  return true, truncated
end

--- The seat's clipboard as an array of lines, or nil when empty.
--- Returns a COPY: a caller that mutates what it pasted must not mutate
--- what is still on the clipboard.
function clipboard.get(seat)
  local e = store[seatOf(seat)]
  if not e then return nil end
  local out = {}
  for i, l in ipairs(e.lines) do out[i] = l end
  return out
end

--- The seat's clipboard as one string, newline-joined, or nil.
function clipboard.text(seat)
  local e = store[seatOf(seat)]
  if not e then return nil end
  return table.concat(e.lines, "\n")
end

--- The seat's clipboard as ONE line, for a single-line target like the
--- command prompt. Multi-line content is joined with spaces rather than
--- concatenated: gluing "ls" and "cd" into "lscd" would produce a
--- command the operator never typed and might well run.
function clipboard.line(seat)
  local e = store[seatOf(seat)]
  if not e then return nil end
  if #e.lines == 1 then return e.lines[1] end
  return table.concat(e.lines, " ")
end

function clipboard.isEmpty(seat)
  local e = store[seatOf(seat)]
  return e == nil or (#e.lines == 1 and e.lines[1] == "")
end

--- How many lines are held (0 when empty).
function clipboard.count(seat)
  local e = store[seatOf(seat)]
  if not e or clipboard.isEmpty(seat) then return 0 end
  return #e.lines
end

--- A short human summary for a status row: "3 lines · 214 bytes".
function clipboard.describe(seat)
  local e = store[seatOf(seat)]
  if not e or clipboard.isEmpty(seat) then return "empty" end
  local n = #e.lines
  local s = (n == 1) and (#e.lines[1] .. " chars")
                     or (n .. " lines \194\183 " .. e.bytes .. " bytes")
  if e.truncated then s = s .. " (truncated at the clipboard cap)" end
  return s
end

--! Clear the seat's clipboard. Called on LOGOUT, not only on request:
--! a seat is a physical screen someone else walks up to, and the last
--! thing the previous operator copied should not be one keystroke away
--! from appearing at their prompt.
function clipboard.clear(seat)
  store[seatOf(seat)] = nil
  return true
end

--- Wipe every seat (reboot / test reset).
function clipboard.clearAll()
  store = {}
  return true
end

clipboard.MAX_BYTES = MAX_BYTES
clipboard.MAX_LINES = MAX_LINES

return clipboard
