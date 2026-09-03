-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS kernel.sandbox                                      ║
-- ║  Capability-checked environments for user programs.      ║
-- ║                                                          ║
-- ║  Replaces ad-hoc __index=_G environments and the legacy  ║
-- ║  panels.makeProgramEnv. User programs see ONLY what the  ║
-- ║  caller explicitly granted via the `caps` table. No      ║
-- ║  ambient authority, no raw computer/component/io, no     ║
-- ║  back-door require into kernel.* modules.                ║
-- ╚══════════════════════════════════════════════════════════╝

local sandbox = {}

-- ============================================================
-- Capability set — what a sandboxed program may touch.
-- ============================================================
-- "fs.read"     — read via securefs bound to opts.session
-- "fs.write"    — write via securefs bound to opts.session
-- "compat.io"   — Lua io/os/filesystem/shell compat API
-- "component"   — component proxy (filtered: no computer.shutdown)
-- "load"        — load/loadstring (for REPL/debug tools)
-- "net"         — network module (in-world, modem-based)
-- "internet"    — internet card: outbound HTTP/TCP to the real world,
--                 plus raw `component.internet` for OpenOS compat
-- "swap"        — disk-backed table API (self-namespacing only)
-- "vault"       — passphrase blob encrypt/decrypt/isEncrypted (pure
--                 data-in/data-out; no keychain or fs access)
-- "crypto"      — hash/hmac/ctEquals/random primitives, plus a
--                 per-PACKAGE machine secret (admin-gated; see below)
-- "legacy"      — unlocks full os.* and io.* (opt-in compat for
--                 ported OpenOS programs; default OFF)
-- ============================================================

local KERNEL_MODULE_PREFIX = "kernel."

-- Modules whose names have any of these prefixes are allowed through
-- makeSafeRequire without per-name vetting. Everything else must match
-- one of the exact names in ALLOWED_MODULE_NAMES, or be installed under
-- /usr/lib or /usr/modules (user-installed libraries, already gated by
-- securefs when the install happens).
local ALLOWED_MODULE_PREFIXES = {
  "compat.",
  "shell.ext",  -- only the user extension API, not internal shell modules
  "peripheral.",
}

-- Narrow whitelist of bare module names sandboxed programs may require.
-- Extend with care — anything added here runs OUTSIDE the sandbox with
-- full unsandboxed require, so it must be safe to expose unconditionally.
local ALLOWED_MODULE_NAMES = {
  compat        = true,
  ["shell.ext"] = true,
  -- The shared keybind table. Exposed to package code deliberately: a
  -- standard that only the base image can read standardises nothing, and
  -- the whole point is that a bundled package and the shell agree on
  -- what ^Q means and follow the operator when they change it.
  -- Safe to hand out — it reads two keybind config files and returns key
  -- MATCHERS. No filesystem handle, no component, no authority of any
  -- kind passes through it.
  ["shell.keys"] = true,
}

-- require names that must be rejected outright even if they'd otherwise
-- fall under a user-lib path. Loading any of these gives the caller the
-- real kernel.* surface via their own require.
local BLOCKED_MODULE_NAMES = {
  -- #SEC H5 — `debug` exposes sethook, getlocal, getupvalue, and the
  -- whole introspection surface. A sandboxed program with require()
  -- access to it can rip out any upvalue in the calling closure
  -- (including the secret-bound `fs` proxy or the `caps` table),
  -- bypassing every other guard. The OC Lua stdlib ships `debug`
  -- so it's reachable via the host's package.loaded["debug"]; block
  -- it explicitly here so the user-lib resolver also refuses.
  ["debug"]                   = true,
  ["package"]                 = true,  -- and the package resolver itself
  ["os"]                      = true,  -- raw os.execute/remove/exit
  ["io"]                      = true,  -- raw io.popen/io.open
  ["component"]               = true,  -- raw component (sandbox shadows it)
  ["computer"]                = true,  -- raw computer.shutdown/eeprom
  ["filesystem"]              = true,  -- raw FS bypasses securefs
  ["shell.init"]              = true,
  ["shell.panels.init"]       = true,
  ["shell.panels.commands"]   = true,
  ["shell.panels.events"]     = true,
  ["shell.panels.executor"]   = true,
  ["shell.panels.state"]      = true,
  ["shell.panels.draw"]       = true,
  ["shell.panels.helpers"]    = true,
  ["shell.panels.filebrowser"] = true,
  ["shell.panels.editor"]     = true,
  ["shell.panels.menus"]      = true,
  ["shell.panels.dialogs"]    = true,
  ["shell.panels.context"]    = true,
  ["shell.panels.keymap"]     = true,
  ["shell.panels.tabs"]       = true,
  ["shell.panels.widgets"]    = true,
  ["shell.panels.mouse"]      = true,
  ["shell.panels.ui"]         = true,
  ["shell.panels.desktop"]    = true,
  ["shell.panels.settingsapp"] = true,
  ["shell.panels.apps"]       = true,
  ["shell.panels.monitorapp"] = true,
  ["shell.panels.chatapp"]    = true,
  -- Stage 5 — the mail ADD-ON's libraries live in /usr/lib, which the
  -- user-lib resolver below would otherwise load through the REAL
  -- require (that's how a full-priv add-on works). Blocking them by name
  -- preserves the exact posture mail had as a kernel module: sandboxed
  -- package code can't reach the mesh transport (bypassing its `net`
  -- capability) or another user's mailbox through it.
  ["mail"]                    = true,
  ["mailui"]                  = true,
  ["mailapp"]                 = true,
  -- The RBMK controller's libraries, for the same reason and then some:
  -- they hold raw console access and the SCRAM path. A sandboxed package
  -- must not be able to require its way to a reactor.
  ["rbmk-cmd"]                = true,
  ["rbmk-controld"]           = true,
  ["rbmk.core"]               = true,
  ["shell.panels.takeover"]   = true,
  ["shell.login"]             = true,
  ["shell.chat"]              = true,
  ["shell.tutorial"]          = true,
  ["shell.syntax"]            = true,
  ["shell.panels"]            = true,
  ["shell"]                   = true,
  ["bios"]                    = true,
  ["init"]                    = true,
  ["install"]                 = true,
  ["system_manifest"]         = true,
}

local function isKernelModule(name)
  return type(name) == "string" and name:sub(1, #KERNEL_MODULE_PREFIX) == KERNEL_MODULE_PREFIX
end

local function isAllowedPrefix(name)
  for _, p in ipairs(ALLOWED_MODULE_PREFIXES) do
    if name:sub(1, #p) == p then return true end
  end
  return false
end

-- True for names that look like user-installed libraries (installed into
-- /usr/lib or /usr/modules). Conservative: only accepts plain identifiers
-- and dotted identifiers so "../foo" or "/abs/path" style names are denied.
local function isUserLibName(name)
  if name:find("[^%w_.-]") then return false end
  if name:sub(1, 1) == "." then return false end
  return true
end

-- Shallow copy helper — we want a fresh table for string/math/table so
-- a malicious program can't monkey-patch the base libraries for everyone.
local function shallowCopy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- ============================================================
-- Trimmed os table — drops functions that would bypass securefs
-- or leak machine info a user program has no business touching.
-- ============================================================
local function makeSafeOs()
  return {
    time     = os.time,
    date     = os.date,
    clock    = os.clock,
    difftime = os.difftime,
    -- #SEC M-18 — os.getenv dropped: it leaks the host process environment
    -- (PATH, HOME, and anything the OC launcher set) into every sandbox
    -- holding only `compat.io`. Programs that genuinely need the full os
    -- (including getenv) must request the `legacy` cap, which exposes the
    -- real os table below.
    -- os.remove / os.rename intentionally omitted — use fs/filesystem.
    -- os.execute / os.exit intentionally omitted.
  }
end

-- ============================================================
-- Trimmed computer table — no shutdown/beep/eeprom mutation.
-- pushSignal is wrapped to filter dangerous internal signals.
-- ============================================================
local DANGEROUS_SIGNALS = {
  tos_shutdown = true, tos_logout = true,
  tos_login_complete = true, tos_seat_changed = true,
  tos_shell_exited = true,
}

-- #SEC (review, Jul 2026) — signals a sandboxed program must NEVER receive
-- from pullSignal: broadcast network traffic (packet sniffing) and kernel
-- control signals (login/shutdown spoofing + surveillance). Seat-ROUTED
-- input (key/touch/clipboard/...) is NOT here: the scheduler already
-- delivers it only to THIS seat's foreground, so a routed key event is the
-- program's own input and is safe to hand back.
local PULL_DROP = {
  modem_message      = true,
  tos_shutdown       = true, tos_logout        = true,
  tos_login_complete = true, tos_seat_changed  = true,
  tos_shell_exited   = true,
}

-- #SEC — the old sandbox handed out `computer.pullSignal` raw. That drains
-- the GLOBAL hardware queue: a sandboxed program could steal another seat's
-- keystrokes, sniff every modem packet, block the whole machine inside one
-- pull, and bypass the scheduler's per-seat input routing entirely.
--
-- The fix mirrors how the real shell reads input: when we're inside a
-- scheduler coroutine (always, for a running command), YIELD instead of
-- pulling raw. proc.tick then resumes us with THIS seat's routed signal —
-- and yielding, unlike a raw pull, cannot consume another process's copy of
-- a broadcast (each process is resumed with its own). We just loop past the
-- broadcast/control signals in PULL_DROP; whatever's left is this seat's own
-- input. A rare non-scheduler caller (pre-init / off-box test) falls back to
-- a raw pull with a hard timeout ceiling, still dropping the sensitive set.
local function safePullSignal(timeout)
  local computer = require("computer")
  local deadline
  if type(timeout) == "number" and timeout >= 0 and timeout ~= math.huge then
    deadline = computer.uptime() + timeout
  end
  if coroutine.isyieldable and coroutine.isyieldable() then
    while true do
      local sig = table.pack(coroutine.yield())
      local name = sig[1]
      if name ~= nil and not PULL_DROP[name] then
        return table.unpack(sig, 1, sig.n)
      end
      -- Dropped signal or idle (nil) resume: honour the deadline, else keep
      -- waiting. We already yielded, so other seats/processes ran — no spin.
      if deadline and computer.uptime() >= deadline then return nil end
    end
  end
  -- No scheduler (pre-init / test): raw pull, ceilinged so a program can't
  -- wedge the machine, still filtering the sensitive set.
  local CEIL = 3
  local stop = computer.uptime()
    + ((type(timeout) == "number" and timeout >= 0 and timeout < CEIL) and timeout or CEIL)
  while true do
    local remaining = stop - computer.uptime()
    if remaining < 0 then return nil end
    local sig = table.pack(computer.pullSignal(remaining))
    local name = sig[1]
    if name == nil then return nil end
    if not PULL_DROP[name] then return table.unpack(sig, 1, sig.n) end
  end
end

local function makeSafeComputer()
  local computer = require("computer")
  return {
    uptime      = computer.uptime,
    freeMemory  = computer.freeMemory,
    totalMemory = computer.totalMemory,
    address     = computer.address,
    pullSignal  = safePullSignal,
    pushSignal  = function(name, ...)
      if type(name) == "string" and DANGEROUS_SIGNALS[name] then
        return  -- silently drop synthesized control signals
      end
      return computer.pushSignal(name, ...)
    end,
    energy      = computer.energy,
    maxEnergy   = computer.maxEnergy,
  }
end

-- Exposed for the regression test (drives the yield path in a coroutine).
sandbox._safePullSignal = safePullSignal

-- ============================================================
-- Filtered component API — hides dangerous component types
-- (eeprom, computer) and only exposes user-safe peripherals.
-- ============================================================
-- #SEC — `filesystem` is intentionally NOT on this list. A raw
-- filesystem proxy bypasses securefs/ACL entirely (proxy.open,
-- proxy.list, proxy.remove all hit the disk directly). Sandboxed
-- code wanting filesystem access must use require("filesystem")
-- (the compat shim) or the bound `fs` global, both of which route
-- through securefs. Granting raw disk access via component.proxy
-- would silently restore the very bypass that securefs exists to
-- prevent.
-- #SEC C4 — component types split into two categories:
--   BASE  — granted by the `component` cap. Read-only-ish surfaces
--           (gpu/screen for drawing, keyboard for input, crafting/
--           navigation/geolyzer/sign for benign sensors and a few
--           low-impact actuators).
--   GATED — require an additional per-type cap (peripheral.<type>).
--           These have network reach (modem), persistent state
--           (tape_drive, hologram), real-world actuation (redstone,
--           piston), or inventory mutation (robot, inventory_*).
-- The audit's worst case (a module with the default `component` cap
-- proxying a modem and sniffing all network traffic) is closed: every
-- module needs an explicit `peripheral.modem` grant to even open a
-- proxy on the modem type.
local BASE_COMPONENT_TYPES = {
  gpu = true, screen = true, keyboard = true,
  crafting = true, navigation = true, geolyzer = true,
  note_block = true, sign = true,
}

local GATED_COMPONENT_TYPES = {
  modem                = "peripheral.modem",
  tunnel               = "peripheral.modem",
  redstone             = "peripheral.redstone",
  robot                = "peripheral.robot",
  inventory_controller = "peripheral.inventory",
  transposer           = "peripheral.inventory",
  tank_controller      = "peripheral.inventory",
  tape_drive           = "peripheral.tape",
  --! An internet card reaches OUTSIDE the Minecraft world: it is both an
  --! exfiltration channel for anything the program can read and an inbound
  --! channel of bytes a stranger wrote. Gated behind its own cap rather
  --! than folded into the generic `component` grant, so a package that
  --! wants a screen and a keyboard does not silently get the network.
  internet             = "internet",
  tractor_beam         = "peripheral.tractor",
  piston               = "peripheral.piston",
  hologram             = "peripheral.hologram",
  --! OpenPrinter (PC-Logix) — the ONLY non-vanilla component type named in
  --! this file, and it is here on purpose rather than left to
  --! /etc/component_caps.cfg below. FEAT-5's config exists so an operator
  --! can add types WE do not ship code for; TOS ships a first-party
  --! `printer` driver package, and a package capability has to clear
  --! pkg.lua's PKG_RUN_CAPS allowlist as well as this table. A cap an
  --! operator can add to one side but not the other is a cap that silently
  --! does nothing (see the package-cap overrides in pkg.lua, which close
  --! that asymmetry for every OTHER mod). Costs nothing on a world without
  --! the mod: the type simply never appears in component.list.
  --! GATED, not base: a printer WRITES to the world — it consumes the
  --! player's paper and ink and drops physical pages into a chest. That is
  --! real-world actuation with a consumable cost, which is the same reason
  --! piston and robot are gated.
  openprinter          = "peripheral.printer",
}

-- FEAT-5 — operator-extensible component allowlist.
-- /etc/component_caps.cfg lets an admin add component types (HBM
-- Nuclear Tech, OpenSecurity, Computronics, AE2, etc.) WITHOUT touching
-- this file. Schema:
--   {
--     base = { "reactor_logic_adapter", "geiger_counter" },   -- granted by `component`
--     gated = {
--       reactor_control = "peripheral.reactor",
--       rfid_writer     = "peripheral.security",
--       ...
--     },
--   }
-- Loaded lazily on first sandbox build and cached. Reload via
-- sandbox.reloadComponentConfig() after editing the file.
local _extraBase  = {}
local _extraGated = {}
local _extraLoaded = false

local function loadComponentConfig()
  if _extraLoaded then return end
  _extraLoaded = true  -- mark before we try, so failures don't loop
  local okF, fsMod = pcall(require, "kernel.fs")
  local okS, serMod = pcall(require, "kernel.serialize")
  if not (okF and okS) then return end
  local path = "/etc/component_caps.cfg"
  if not fsMod.exists(path) then return end
  local raw = fsMod.readFile(path)
  if not raw or #raw == 0 or #raw > 8192 then return end
  local ok, cfg = pcall(serMod.decode, raw, { maxBytes = 8192 })
  if not ok or type(cfg) ~= "table" then return end
  -- Validate + accept. Same shape constraints as the kiosk config
  -- loader: alphanumeric / underscore / dash, bounded length.
  if type(cfg.base) == "table" then
    for _, t in ipairs(cfg.base) do
      if type(t) == "string" and #t <= 64 and t:match("^[%w_]+$") then
        _extraBase[t] = true
      end
    end
  end
  if type(cfg.gated) == "table" then
    for ctype, cap in pairs(cfg.gated) do
      if type(ctype) == "string" and #ctype <= 64 and ctype:match("^[%w_]+$")
         and type(cap) == "string" and #cap <= 64 and cap:match("^[%w_%.]+$") then
        _extraGated[ctype] = cap
      end
    end
  end
end

--- Reload /etc/component_caps.cfg from disk. Admin command for the
--- "I just edited the file, refresh sandbox" workflow. Existing
--- sandboxes keep their captured cap lists; new sandbox.build()s
--- pick up the new config.
function sandbox.reloadComponentConfig()
  _extraBase  = {}
  _extraGated = {}
  _extraLoaded = false
  loadComponentConfig()
  return _extraBase, _extraGated
end

local function isAllowedComponentType(ctype, caps)
  if not ctype then return false end
  loadComponentConfig()
  if BASE_COMPONENT_TYPES[ctype] or _extraBase[ctype] then return true end
  local gated = GATED_COMPONENT_TYPES[ctype] or _extraGated[ctype]
  if gated and caps and caps[gated] then return true end
  return false
end

-- Back-compat: exported list used by older callers that just want to
-- check "is this type whitelisted at all." Returns the BASE set only —
-- a caller relying on this view will be slightly more restrictive than
-- before, which is the right direction.
local ALLOWED_COMPONENT_TYPES = BASE_COMPONENT_TYPES

-- #FIX/#SEC (emulator round 7) — SEAT-SCOPED display hardware.
--
-- Every sandboxed TUI program opens its screen the obvious way:
--   local gpuAddr = component.list("gpu")()
-- which is the FIRST GPU on the bus — seat 1's. On a two-seat machine a
-- game launched from seat 2 therefore drew onto seat 1's SCREEN, over the
-- other operator's work (observed: `ttt 2p` typed on one seat, the board
-- painted on the other). It is also a spoofing surface: a package could
-- paint a convincing login prompt on somebody else's screen.
--
-- The sandbox already routes INPUT per seat (safePullSignal yields for the
-- scheduler's seat-routed delivery). This is the output half: a program's
-- view of gpu/screen/keyboard is narrowed to the seat it was launched from,
-- so the obvious code is automatically the correct code. When the seat
-- can't be resolved (kernel context, boot, off-box tests) nothing is
-- filtered — a single-seat machine behaves exactly as it always did.
local SEAT_SCOPED_TYPES = { gpu = true, screen = true, keyboard = true }

local function seatDeviceFilter()
  local okS, scr = pcall(require, "kernel.screen")
  if not okS or type(scr) ~= "table" or not scr.callerDevices then return nil end
  local okD, dev = pcall(scr.callerDevices)
  if not okD or type(dev) ~= "table" then return nil end
  -- A seat with no resolvable GPU address tells us nothing useful; don't
  -- filter on it or the program would see no display at all.
  if not dev.gpu then return nil end
  local allow = { [dev.gpu] = true }
  if dev.screen then allow[dev.screen] = true end
  for _, kb in ipairs(dev.keyboards or {}) do allow[kb] = true end
  return allow, dev
end

--- This seat's own address for a seat-scoped component type (nil if the
--- seat is unresolvable, i.e. don't narrow anything).
local function seatOwnAddress(ctype)
  local allow, dev = seatDeviceFilter()
  if not allow then return nil end
  if ctype == "gpu"      then return dev.gpu end
  if ctype == "screen"   then return dev.screen end
  if ctype == "keyboard" then return (dev.keyboards or {})[1] end
  return nil
end

local function makeSafeComponent(caps)
  caps = caps or {}
  local comp = require("component")
  local safe = {}

  -- Resolved per call, not once at build time: seats come and go with
  -- hot-plug, and a sandbox env outlives any single screen.
  local function seatDenies(addr, ctype)
    if not SEAT_SCOPED_TYPES[ctype] then return false end
    local allow = seatDeviceFilter()
    if not allow then return false end
    return not allow[addr]
  end

  function safe.list(filter, exact)
    local raw = comp.list(filter, exact)
    -- Resolve the seat ONCE per enumeration rather than per component:
    -- the answer can't change mid-walk, and this is called on a machine
    -- that already runs at a few ticks per second.
    local allow = seatDeviceFilter()
    return function()
      while true do
        local addr, ctype = raw()
        if addr == nil then return nil end
        local denied = allow and SEAT_SCOPED_TYPES[ctype] and not allow[addr]
        if isAllowedComponentType(ctype, caps) and not denied then
          return addr, ctype
        end
      end
    end
  end

  function safe.proxy(addr)
    local ctype = comp.type(addr)
    if not isAllowedComponentType(ctype, caps) then
      return nil, "access denied"
    end
    if seatDenies(addr, ctype) then return nil, "not your seat" end
    return comp.proxy(addr)
  end

  function safe.type(addr) return comp.type(addr) end
  function safe.slot(addr) return comp.slot(addr) end

  function safe.get(addr, ctype)
    local result = comp.get(addr, ctype)
    if result then
      local t = comp.type(result)
      if isAllowedComponentType(t, caps) then return result end
    end
    return nil, "access denied"
  end

  function safe.invoke(addr, method, ...)
    local ctype = comp.type(addr)
    if not isAllowedComponentType(ctype, caps) then
      error("sandbox: access denied to " .. tostring(ctype))
    end
    if seatDenies(addr, ctype) then
      error("sandbox: " .. tostring(ctype) .. " belongs to another seat")
    end
    return comp.invoke(addr, method, ...)
  end

  function safe.isAvailable(ctype)
    if not isAllowedComponentType(ctype, caps) then return false end
    return comp.isAvailable(ctype)
  end

  function safe.getPrimary(ctype)
    if not isAllowedComponentType(ctype, caps) then
      return nil, "access denied"
    end
    -- "Primary" for a sandboxed program means primary FOR ITS SEAT, not
    -- the machine's first device — same reasoning as safe.list.
    if SEAT_SCOPED_TYPES[ctype] then
      local mine = seatOwnAddress(ctype)
      if mine then return comp.proxy(mine) end
    end
    return comp.getPrimary(ctype)
  end

  return safe
end

-- ============================================================
-- Capability-checked require. Never returns a kernel.* module;
-- only modules that live under /usr/lib, /usr/modules, or the
-- compat/shell namespaces. Everything goes through the caller's
-- session so securefs can enforce ACLs on the source file.
-- ============================================================
-- TOS's user-library search roots. A name is allowed if (a) it's on the
-- explicit prefix/name whitelist above, or (b) the require resolves to a
-- file inside one of these roots (i.e. it was installed there, not
-- shipped as part of the kernel/shell).
local USER_LIB_ROOTS = { "/usr/lib", "/usr/modules" }

local function nameToCandidatePaths(name)
  local rel = name:gsub("%.", "/")
  return {
    rel .. ".lua",
    rel .. "/init.lua",
  }
end

-- Return the absolute path that `name` would resolve to under a user-lib
-- root, if any. Used as the final gate: if we can't locate the source
-- file inside /usr/lib or /usr/modules, we refuse to require it.
local function resolveUserLibPath(name)
  local fs = nil
  local ok, mod = pcall(require, "kernel.fs")
  if ok then fs = mod end
  if not fs then return nil end
  for _, root in ipairs(USER_LIB_ROOTS) do
    for _, rel in ipairs(nameToCandidatePaths(name)) do
      local path = root .. "/" .. rel
      if fs.exists(path) then return path end
    end
  end
  return nil
end

-- #SEC H4 — shallow-copy compat.* modules per sandbox so one sandbox
-- can't monkey-patch event.listen / filesystem.list / shell.execute for
-- everyone else (including the kernel). Names listed here get a fresh
-- shallow copy on every require; all other allowed modules pass through
-- unchanged (their behaviour is already kernel-managed and per-sandbox
-- isolation would break call dispatch).
local COMPAT_COPY_NAMES = {
  ["compat"]               = true,
  ["compat.event"]         = true,
  ["compat.filesystem"]    = true,
  ["compat.io"]            = true,
  ["compat.term"]          = true,
  ["compat.keyboard"]      = true,
  ["compat.serialization"] = true,
  ["compat.sides"]         = true,
  ["compat.colors"]        = true,
  ["compat.text"]          = true,
  ["compat.buffer"]        = true,
  ["shell.ext"]            = true,
}

local function shallowCopyModule(mod)
  if type(mod) ~= "table" then return mod end
  local copy = {}
  for k, v in pairs(mod) do copy[k] = v end
  return copy
end

local function makeSafeRequire(opts, prebound)
  local cache = {}
  if prebound then
    for k, v in pairs(prebound) do cache[k] = v end
  end
  return function(name)
    if type(name) ~= "string" then
      error("bad argument #1 to 'require' (string expected)", 2)
    end
    if cache[name] ~= nil then return cache[name] end

    if isKernelModule(name) then
      error("sandbox: cannot require kernel module '" .. name .. "'", 2)
    end

    if BLOCKED_MODULE_NAMES[name] then
      -- #FIX (emulator round 6) — an rc.d SERVICE shim is allowed past the
      -- block for names that genuinely resolve to an installed user
      -- library. The blocklist exists to stop ordinary sandboxed COMMAND
      -- code (a game, a user program) from pulling in a full-priv add-on
      -- lib like `mail`. But a service package's own shim legitimately
      -- does `local mail = require("mail")` — that's how cluster-manager
      -- and clusterd have always started — and blocking it stopped the
      -- mail service from ever registering its delivery handler.
      --
      -- Safe, because: (a) rc.d services already hold `net` in their
      -- DEFAULT caps, so this grants no reach they lacked; (b) rc.d
      -- scripts are admin-installed system glue, gated by pkg's narrow
      -- /etc/rc.d write exception; and (c) the bypass only applies to
      -- names that RESOLVE under a user-lib root, so `debug`, `os`, `io`,
      -- `component`, `computer` and every `shell.*` internal stay blocked
      -- for services too (none of them live in /usr/lib or /usr/modules).
      if not (opts and opts.allowUserLibs and resolveUserLibPath(name)) then
        error("sandbox: module '" .. name .. "' is not available to sandboxed code", 2)
      end
    end

    -- Explicit whitelist (prefix or exact name).
    if ALLOWED_MODULE_NAMES[name] or isAllowedPrefix(name) then
      local mod = require(name)
      -- #SEC H4 — return a per-sandbox shallow copy for compat.* so a
      -- mutation in this sandbox doesn't leak to others or the kernel.
      if COMPAT_COPY_NAMES[name] then
        mod = shallowCopyModule(mod)
        -- #SEC CR-8 — bind term.gpu() to THIS sandbox's capabilities so a
        -- mutation-capable GPU proxy is only handed to processes that hold
        -- a display cap. Without it, term.gpu() stays read-only.
        if name == "compat.term" and type(mod._gpuForCaps) == "function" then
          local sbCaps = opts and opts.caps
          mod.gpu = function() return mod._gpuForCaps(sbCaps) end
        end
      end
      cache[name] = mod
      return mod
    end

    -- User-installed library: must resolve to a file under /usr/lib or
    -- /usr/modules. This prevents requiring shell.init or similar by
    -- name: they live under /tos and will not resolve under user roots.
    if isUserLibName(name) then
      local resolved = resolveUserLibPath(name)
      if resolved then
        -- #SEC M-19 — resolveUserLibPath() checks existence via the RAW
        -- kernel fs, but the load must respect the caller's session ACL.
        -- Re-verify the seat principal may actually read the resolved path
        -- before loading; fail closed so a user lib can't be pulled in
        -- past securefs (and so a name that resolves to a file the caller
        -- can't read isn't silently loaded). The check is skipped only for
        -- sessionless/kernel contexts where ACLs don't apply.
        local usersMod = _G._TOS and _G._TOS.users
        if opts.session and usersMod and usersMod.canAccessAs then
          local okR = usersMod.canAccessAs(opts.session, resolved, "r")
          if not okR then
            error("sandbox: access denied loading user lib '" .. name .. "'", 2)
          end
        end
        local mod = require(name)
        cache[name] = mod
        return mod
      end
    end

    error("sandbox: module '" .. name .. "' is not on the allowed list", 2)
  end
end

-- ============================================================
-- sandbox.build(opts) -> env
-- ============================================================
function sandbox.build(opts)
  opts = opts or {}
  local caps = opts.caps or {}
  local session = opts.session

  -- Resolve securefs with the caller's session pre-bound. If the
  -- caller lacks fs caps we still expose it as nil so attempts to
  -- touch it produce a clear error rather than working by accident.
  local secfs = _G._TOS and _G._TOS.securefs
  if not secfs then
    local ok, mod = pcall(require, "kernel.securefs")
    if ok then secfs = mod end
  end
  local boundFs = nil
  if secfs and (caps["fs.read"] or caps["fs.write"]) then
    boundFs = secfs.forSession(session)
  end

  -- A read-only projection of securefs. Named readers are forwarded;
  -- everything else is simply absent, so a program probing for a writer
  -- finds nil rather than a function that refuses -- there is no
  -- ambiguity for it to mistake for "try harder".
  --
  -- `open` is forwarded but MODE-GATED: it is the one reader that is
  -- also a writer, and a view that forwarded it unfiltered would hand
  -- back everything it just withheld.
  local function readOnlyFsView(fsImpl)
    local READERS = {
      "exists", "isDirectory", "list", "readFile", "size", "lastModified",
      "normalize", "split", "join", "spaceTotal", "spaceUsed", "spaceFree",
      "mounts", "home", "resolve",
    }
    local view = {}
    for _, name in ipairs(READERS) do
      local fn = fsImpl[name]
      if type(fn) == "function" then
        view[name] = function(...) return fn(...) end
      end
    end
    if type(fsImpl.open) == "function" then
      view.open = function(path, mode, ...)
        mode = mode or "r"
        if type(mode) ~= "string" or mode:find("[wa+]") then
          return nil, "fs.write capability required"
        end
        return fsImpl.open(path, mode, ...)
      end
    end
    return view
  end

  -- Output stream: opts.stdout is a function(text) — if absent, fall
  -- through to the global print so CLI scripts still produce output.
  local function sandboxPrint(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring(select(i, ...))
    end
    local line = table.concat(parts, "\t")
    if opts.stdout then
      opts.stdout(line)
    else
      print(line)
    end
  end

  -- Safe-only meta helpers. The real getmetatable/setmetatable leak the
  -- string metatable (via getmetatable("")) which points at the REAL
  -- string library, letting a sandbox monkey-patch string functions for
  -- everyone. We deny access to any protected metatable (__metatable set)
  -- and we refuse to hand back metatables for raw strings. setmetatable
  -- is still useful on tables the sandbox itself owns, so we leave that
  -- intact but block the string-library attack by forbidding attempts to
  -- reach the string metatable.
  local stringMT = getmetatable("")
  local realStringLib = string
  local function refersToString(v)
    return v == stringMT or v == realStringLib
  end
  local function safeGetMetatable(v)
    if type(v) == "string" then
      return nil  -- hide the shared string metatable entirely
    end
    local mt = getmetatable(v)
    if mt == stringMT then return nil end
    return mt
  end
  local function safeSetMetatable(t, mt)
    if type(t) ~= "table" then
      error("bad argument #1 to 'setmetatable' (table expected)", 2)
    end
    if mt ~= nil then
      if type(mt) ~= "table" then
        error("bad argument #2 to 'setmetatable' (nil or table expected)", 2)
      end
      -- Guard against a metatable that aliases the real string library or
      -- its metatable: such a metatable would let sandboxed code reach or
      -- monkey-patch string.* for the whole VM through the metatable chain.
      -- rawget so a hostile metatable on `mt` itself can't hide the field.
      if refersToString(mt)
         or refersToString(rawget(mt, "__index"))
         or refersToString(rawget(mt, "__newindex"))
         or refersToString(rawget(mt, "__metatable")) then
        error("setmetatable: metatable referencing protected library denied", 2)
      end
    end
    return setmetatable(t, mt)
  end

  local sandboxedStringCopy = shallowCopy(string)

  -- Prebuild the safe component/computer tables once so they can be
  -- returned both as globals and via require("component") / require("computer").
  local safeComp, safeCompr
  if caps["component"] then
    safeComp  = makeSafeComponent(caps)
    safeCompr = makeSafeComputer()
  end
  local prebound = {}
  if safeComp  then prebound.component = safeComp  end
  if safeCompr then prebound.computer  = safeCompr end

  local env = {
    -- Base Lua — safe pure functions.
    assert      = assert,
    error       = error,
    pcall       = pcall,
    xpcall      = xpcall,
    type        = type,
    tostring    = tostring,
    tonumber    = tonumber,
    pairs       = pairs,
    ipairs      = ipairs,
    next        = next,
    select      = select,
    unpack      = table.unpack,  -- some programs still expect the 5.1 name
    rawequal    = rawequal,
    rawlen      = rawlen,
    -- rawget/rawset intentionally omitted — a sandbox doesn't need them,
    -- and they can be used to poke at fields that metatables would guard.
    setmetatable = safeSetMetatable,
    getmetatable = safeGetMetatable,

    -- Fresh shallow copies so sandboxes can't mutate each other's libs.
    math        = shallowCopy(math),
    string      = sandboxedStringCopy,
    table       = shallowCopy(table),
    utf8        = utf8 and shallowCopy(utf8) or nil,
    coroutine   = shallowCopy(coroutine),

    -- Bound I/O
    print       = sandboxPrint,
    require     = makeSafeRequire(opts, prebound),
  }

  env._G = env
  env._ENV = env
  env._VERSION = _VERSION

  -- Session-bound filesystem. Programs that want raw path operations
  -- use this; compat.io/compat.filesystem provide the OpenOS flavor.
  --
  -- fs.read WITHOUT fs.write gets a READER-ONLY view. This used to hand
  -- over the whole securefs surface whenever EITHER cap was present, so
  -- a manifest declaring `capabilities = { "fs.read" }` -- which is what
  -- `pkg info` shows the operator -- could writeFile, remove and rename
  -- anything the invoking user could. securefs still applied the user's
  -- ACLs, so it was not privilege escalation; it was the DECLARATION
  -- being false, which is worse in its own way. The capability list is
  -- the thing an operator reads before installing, and the header of
  -- this very file lists fs.read and fs.write as separate powers.
  --
  -- Found by the in-emulator battery (60-sandbox), which asks the live
  -- sandbox what a cap set actually yields. Every off-box sandbox test
  -- builds an environment by hand and then asserts about the thing it
  -- just built, so none of them could see this.
  if boundFs then
    if caps["fs.write"] then
      env.fs = boundFs
    else
      env.fs = readOnlyFsView(boundFs)
    end
  end

  -- compat.io cap: expose io + trimmed os + filesystem compat module.
  if caps["compat.io"] then
    local ok, compatIo = pcall(require, "compat.io")
    if ok then env.io = compatIo end
    env.os = makeSafeOs()
    local okFs, compatFs = pcall(require, "compat.filesystem")
    if okFs then env.filesystem = compatFs end
  end

  -- Legacy cap: unlock the full os/io libraries for ported OpenOS
  -- programs that need os.remove etc. Should only be granted when the
  -- user explicitly opts in via a "legacy" flag.
  --
  -- #SEC — DANGER: granting `legacy` is granting "do anything".
  --
  -- The unfiltered `os` table includes os.execute (shells out to the
  -- host) and os.remove (raw filesystem.remove, bypassing securefs and
  -- every ACL we maintain). The unfiltered `io` table includes
  -- io.popen (process spawn with attacker-controlled command) and
  -- io.open with no path validation. Any one of these is sufficient
  -- to fully compromise the kernel sandbox.
  --
  -- This cap exists for porting third-party OpenOS programs whose
  -- author expected the standard library and would otherwise need
  -- per-call rewrites. It is NOT intended for kernel-managed services,
  -- rc.d entries, cron jobs, or modules — any of those should declare
  -- the narrower caps (fs.read, fs.write, component, etc.) they
  -- actually need. There is no granular form of `legacy`; the only
  -- way to grant less than "do anything" is to not grant it at all.
  --
  -- The manifest validator in /tos/kernel/modules.lua deliberately
  -- excludes "legacy" from ALLOWED_MANIFEST_CAPS so a module's
  -- manifest can't request it; granting `legacy` requires hand-built
  -- caller code that explicitly passes it.
  if caps["legacy"] then
    env.os = os
    env.io = io
    -- Audit-trail: every legacy build leaves a log entry so an operator
    -- can cross-check what was granted that. pcall-require so a tight
    -- low-memory boot that skipped the log module doesn't crash here.
    local okLog, logMod = pcall(require, "kernel.log")
    if okLog and logMod and logMod.warn then
      logMod.warn("sandbox", "Built env with legacy cap — full os/io exposed")
    end
  end

  -- component cap: filtered component + trimmed computer API.
  if caps["component"] then
    env.component = safeComp
    env.computer  = safeCompr
  end

  -- load cap: dynamic code evaluation, for REPLs and debuggers.
  -- #SEC — The previous implementation honored an arbitrary env passed
  -- by the sandboxed caller (`e or env`), which let a program with the
  -- load cap pass in the real `_G` (or any other table) and escape the
  -- sandbox entirely. We now always force the sandbox env: a sandboxed
  -- REPL evaluates its input in the SAME environment as the REPL
  -- itself, never a richer one. mode is also pinned to "t" (text only)
  -- so bytecode attacks aren't reintroduced via a creative mode flag.
  if caps["load"] then
    env.load = function(chunk, name, _mode, _e)
      return load(chunk, name, "t", env)
    end
    env.loadstring = env.load
  end

  -- notify cap: let a sandboxed program put a DOS-style dialog box in the
  -- operator's face, instead of only writing to the output area above the
  -- command line. Gated because interrupting someone is a privilege — but
  -- a SAFE one to grant, because kernel.notify's rate limits are enforced
  -- inside post() and there is no way to opt out of them from here.
  --
  -- Deliberately a NARROWED surface, not the module: post/result only. A
  -- sandboxed program may raise its own notices and read its own answers;
  -- it may not read the queue (other programs' notices are none of its
  -- business), settle someone else's dialog, or _reset the facility.
  -- Follows the crypto/vault precedent — inject a global, don't unlock
  -- require().
  if caps["notify"] then
    local okN, nf = pcall(require, "kernel.notify")
    if okN and nf and nf.post then
      env.notify = {
        post = function(spec)
          if type(spec) ~= "table" then return nil, "spec must be a table" end
          -- Stamp the source from the PACKAGE NAME, ignoring any `from` the
          -- program supplied: the operator must be able to trust that the
          -- name on an interrupting dialog is really who raised it. It is
          -- also the per-source rate-limit key, so letting a program choose
          -- it would let one program evade its own gap by rotating names.
          local copy = {}
          for k, v in pairs(spec) do copy[k] = v end
          local pkgName = opts.pkgName
          copy.from = (type(pkgName) == "string"
            and pkgName:match("^[%w][%w%-]*$")) and pkgName or "package"
          return nf.post(copy)
        end,
        result = function(id) return nf.result(id) end,
      }
    end
  end

  -- net cap: expose the net module. The net module itself may
  -- check per-call permissions in a later phase.
  if caps["net"] then
    local ok, net = pcall(require, "kernel.net")
    if ok then env.net = net end
  end

  -- internet cap: outbound access to the real world.
  --
  --! Exposes the KERNEL WRAPPER (bounded reads, timeouts, http/https only),
  --! which is what well-behaved code and TOS's own callers should use. It
  --! does NOT make those bounds a containment boundary: this same cap is
  --! what unlocks the raw `internet` component type above, because an
  --! OpenOS program doing require("internet") reaches for the card
  --! directly and compat would be a fiction without it. The capability
  --! grant is the boundary; the bounds are there so honest code cannot
  --! accidentally OOM a 192 KB machine on somebody's web page.
  if caps["internet"] then
    local ok, inet = pcall(require, "kernel.internet")
    if ok and inet then
      env.internet = {
        get      = function(url, o) return inet.get(url, o) end,
        download = function(url, dest, o) return inet.download(url, dest, o) end,
        socket   = function(addr, port) return inet.socket(addr, port) end,
        status   = function() return inet.status() end,
        available = function() return inet.available() end,
      }
    end
  end

  -- swap cap: disk-backed "slow RAM" tables. We expose ONLY the
  -- self-namespacing table API — each swap.table() gets a private key
  -- namespace, so one sandboxed program can't read or clobber another's
  -- (or the kernel's) swap keys. The raw global key/value store is
  -- deliberately NOT exposed for that reason. Total disk use stays bounded
  -- by the kernel's swap cap; an over-budget write surfaces as a normal
  -- "swap full" error rather than corrupting anything.
  if caps["swap"] then
    local ok, sw = pcall(require, "kernel.swap")
    if ok and sw and sw.table then
      env.swap = {
        table     = function(o) return sw.table(o) end,
        freeTable = function(p) return sw.freeTable(p) end,
        usage     = sw.usage,
      }
    end
  end

  -- vault cap: passphrase-encrypted blobs (used by the tape package's
  -- encrypt/decrypt commands). We expose ONLY the pure data-in/data-out
  -- trio — encrypt(plaintext, passphrase[, opts]), decrypt(blob,
  -- passphrase), isEncrypted(s). All three operate exclusively on
  -- caller-supplied strings with a caller-supplied passphrase: no
  -- filesystem access, no keychain, no ambient key material — so the
  -- grant adds crypto capability without widening any other surface.
  if caps["vault"] then
    local ok, v = pcall(require, "kernel.vault")
    if ok and v and v.encrypt and v.decrypt then
      env.vault = {
        encrypt     = function(plaintext, passphrase, o) return v.encrypt(plaintext, passphrase, o) end,
        decrypt     = function(blob, passphrase) return v.decrypt(blob, passphrase) end,
        isEncrypted = function(s) return v.isEncrypted(s) end,
      }
    end
  end

  -- crypto cap: keyed-integrity primitives (used by tape-authenticator's
  -- HMAC keycards). Like vault, the exposed functions are pure
  -- data-in/data-out: hash(s), hmac(key, msg), ctEquals(a, b), and
  -- random(n) (CSPRNG bytes via crypto.salt). Password hashing, the
  -- cipher surface, and entropy export stay kernel-only.
  --
  -- crypto.secret() — the one stateful member — returns a 32-byte
  -- machine secret OWNED BY THIS PACKAGE, minted on first use and kept
  -- at /var/pkg/secrets/<pkgName> via the RAW kernel fs (the store is
  -- kernel-owned; user ACLs don't apply, the gate below does):
  --   * isolation — the scope is opts.pkgName, threaded in by
  --     kernel.pkg's loader, NOT caller-supplied; package A can never
  --     name (and thus never read) package B's secret, and a sandbox
  --     built without a pkgName has no secret() at all.
  --   * privilege — resolved against the LIVE session per call (same
  --     pattern as securefs): ADMIN+ tier or a kernel/login
  --     pseudo-session is required, failing closed with no session.
  --     A guest at the same seat can therefore verify nothing and
  --     mint nothing; key minting/verification is an operator action.
  if caps["crypto"] then
    local okC, kcrypto = pcall(require, "kernel.crypto")
    if okC and kcrypto and kcrypto.hmac then
      env.crypto = {
        hash     = function(s) return kcrypto.hash(s) end,
        hmac     = function(key, msg) return kcrypto.hmac(key, msg) end,
        ctEquals = function(a, b) return kcrypto.ctEquals(a, b) end,
        random   = function(n) return kcrypto.salt(n) end,
      }
      local pkgName = opts.pkgName
      if type(pkgName) == "string" and pkgName:match("^[%w][%w%-]*$") then
        env.crypto.secret = function()
          -- Live principal, fail closed (mirrors securefs.sessionOf).
          local sess = nil
          local okP, procMod = pcall(require, "kernel.process")
          if okP and procMod and procMod.currentSession then
            sess = procMod.currentSession()
          end
          if not sess then
            local usersMod = _G._TOS and _G._TOS.users
            if not usersMod then
              local okU, u = pcall(require, "kernel.users")
              if okU then usersMod = u end
            end
            if usersMod and usersMod.currentSession then
              sess = usersMod.currentSession()
            end
          end
          local allowed = sess and (sess.isKernel or sess.isLogin
            or (type(sess.tier) == "number" and sess.tier >= 2))
          if not allowed then
            return nil, "crypto.secret requires an admin session"
          end
          local okF, kfs = pcall(require, "kernel.fs")
          if not okF or not kfs then return nil, "fs unavailable" end
          local dir  = "/var/pkg/secrets"
          local path = dir .. "/" .. pkgName
          if kfs.exists(path) then
            local data = kfs.readFile(path)
            if data and #data >= 16 then return data end
            return nil, "secret unreadable"
          end
          if not kfs.exists(dir) then kfs.makeDirectory(dir) end
          local secret = kcrypto.salt(32)
          local wOk, wErr = kfs.writeFile(path, secret)
          if not wOk then return nil, "cannot store secret: " .. tostring(wErr) end
          return secret
        end
      end
    end
  end

  return env
end

-- ============================================================
-- sandbox.run(src, chunkname, opts, ...) -> ok, result
-- Convenience wrapper: build env, load source, pcall.
-- ============================================================
function sandbox.run(src, chunkname, opts, ...)
  local env = sandbox.build(opts)
  local fn, err = load(src, chunkname, "t", env)
  if not fn then
    return false, "compile error: " .. tostring(err)
  end
  return pcall(fn, ...)
end

return sandbox
