-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Error registry                              ║
-- ║  One table; three spellings of every error                ║
-- ╚══════════════════════════════════════════════════════════╝
--! Every error TOS names has three spellings, all from one entry here:
--!
--!   E-401            what an operator reads, says aloud and searches for
--!   ERR_PERM_DENIED  what a program keys on, and what `why` looks up
--!   0x00040001       the stop screen's reference line -- machine-only
--!
--! The hex is COMPUTED from the E-number and never stored, so the two
--! cannot disagree: (subsystem << 16) | index, E-401 being subsystem 4,
--! index 1.
--!
--! Numbers group by subsystem, the hundreds digit:
--!   1xx boot / POST   2xx kernel     3xx files     4xx access
--!   5xx network       6xx packages   7xx hardware  8xx shell
--!
--! Boot faults keep the EEPROM's two-character codes (C1, K4, ...). The
--! digit is the BEEP COUNT, so a machine with no screen still says which
--! fault it hit, and the BIOS has ~150 bytes free -- no room for names. Each
--! maps to an entry here, and E-10N's index is that same beep count.
--!
--! A code is never renumbered or reused once shipped: a log line or a forum
--! post written against E-304 has to mean the same thing forever. Retire an
--! entry by leaving it in place.
--!
--! Refusals carry their code in the message itself, as a trailing tag --
--! "... [E-402 ERR_PATH_PROTECTED]". That survives every path a message
--! travels (securefs -> fs wrapper -> command -> output sink) without
--! threading a second value through all of them, and test_error_registry
--! scans every shipped file so a tag cannot name a code this table lacks.

local errors = {}

errors.SUBSYSTEMS = { "boot", "kernel", "files", "access", "network",
                      "packages", "hardware", "shell" }

-- number, symbol, one-line title, EEPROM code (boot faults only)
local LIST = {
  { 101, "ERR_CPU_ARCH",        "CPU architecture is too old — TOS needs a Lua 5.3+ CPU", "C1" },
  { 102, "ERR_NO_BOOT_DEVICE",  "no boot device — no /init.lua disk and no TBFS drive was found", "D2" },
  { 103, "ERR_TBFS_BOOT",       "the TBFS boot blob would not compile (raw-drive boot region damaged)", "B3" },
  { 104, "ERR_KERNEL_MISSING",  "the kernel was missing — /tos/kernel/init.lua was not on the disk", "K4" },
  { 105, "ERR_INIT_UNREADABLE", "/init.lua could not be opened (unreadable or the disk went away)", "I5" },
  { 106, "ERR_INIT_SYNTAX",     "/init.lua would not compile (truncated or corrupted write)", "I6" },

  { 201, "ERR_KERNEL_PANIC",    "the kernel hit an error it could not recover from" },
  { 202, "ERR_OUT_OF_MEMORY",   "the machine ran out of RAM" },

  { 301, "ERR_NO_SPACE",        "the disk is full" },
  { 302, "ERR_NEEDS_RECURSIVE", "that is a directory; removing it needs -r" },
  { 303, "ERR_RM_SYSTEM_PATH",  "rm will not remove a system path without -r" },
  { 304, "ERR_TRASH_REFUSED",   "the trash would not take it, so nothing was deleted" },

  { 401, "ERR_PERM_DENIED",     "your account is not allowed to do that" },
  { 402, "ERR_PATH_PROTECTED",  "that path is guarded against changes, even by an admin" },
  { 403, "ERR_TIER_REQUIRED",   "that needs a higher account tier" },

  { 801, "ERR_UNKNOWN_CMD",     "no command by that name" },
  { 802, "ERR_CMD_UNLOADABLE",  "the command exists but would not fit in memory" },
}

local BY_NUM, BY_SYM, BY_BIOS, ALL = {}, {}, {}, {}
for _, r in ipairs(LIST) do
  local e = { num = r[1], sym = r[2], title = r[3], bios = r[4] }
  BY_NUM[e.num] = e; BY_SYM[e.sym] = e; ALL[#ALL + 1] = e
  if e.bios then BY_BIOS[e.bios] = e end
end

--- "E-401": what an operator reads.
function errors.code(e)  return string.format("E-%03d", e.num) end
--- "0x00040001": derived, never stored.
function errors.hex(e)   return string.format("0x%08X", ((e.num // 100) << 16) | (e.num % 100)) end
--- "E-401 ERR_PERM_DENIED"
function errors.label(e) return errors.code(e) .. " " .. e.sym end
--- "  [E-401 ERR_PERM_DENIED]", for appending to a message.
function errors.tag(sym)
  local e = BY_SYM[sym]
  return e and ("  [" .. errors.label(e) .. "]") or ""
end
--- "access"
function errors.subsystem(e) return errors.SUBSYSTEMS[e.num // 100] end

--- Look an error up by anything an operator might type: E-401, e401, 401,
--- ERR_PERM_DENIED, perm_denied, 0x00040001, or an EEPROM code like C1.
--- nil when it is none of those -- so `why ls` still means the command.
function errors.find(q)
  if type(q) == "number" then return BY_NUM[math.tointeger(q) or -1] end
  if type(q) ~= "string" then return nil end
  local u = q:match("^%s*(.-)%s*$"):upper()
  if u == "" then return nil end
  local n = u:match("^E%-?(%d+)$") or u:match("^(%d+)$")
  if n then return BY_NUM[tonumber(n)] end
  local h = u:match("^0X(%x+)$")
  if h then
    local v = tonumber(h, 16)
    return v and BY_NUM[(v >> 16) * 100 + (v & 0xFFFF)] or nil
  end
  return BY_BIOS[u] or BY_SYM[u] or BY_SYM["ERR_" .. u]
end

--- The entry a message is tagged with, or nil for an untagged message.
function errors.parse(text)
  if type(text) ~= "string" then return nil end
  local n = text:match("%[E%-(%d%d%d) ERR_")
  return n and BY_NUM[tonumber(n)] or nil
end

--- EEPROM code -> title: the shape srm.BASIC_CODES has always had.
function errors.biosTable()
  local t = {}
  for code, e in pairs(BY_BIOS) do t[code] = e.title end
  return t
end

--- Every entry, in number order.
function errors.all()
  local t = {}
  for i, e in ipairs(ALL) do t[i] = e end
  table.sort(t, function(a, b) return a.num < b.num end)
  return t
end

return errors
