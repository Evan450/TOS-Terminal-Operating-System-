-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Internet card transport                     ║
-- ║                                                            ║
-- ║  ONE place that answers "can this machine reach outside    ║
-- ║  the world, and how much of it may it pull in?" — so pkg,  ║
-- ║  the compat shim, sysinfo and the `internet` command all   ║
-- ║  agree, and so every size/timeout bound lives together     ║
-- ║  instead of once per caller.                               ║
-- ║                                                            ║
-- ║  An OpenComputers internet card offers two things, each    ║
-- ║  separately switchable in the mod's own config:            ║
-- ║    HTTP  — request(url, [postData], [headers], [method])   ║
-- ║    TCP   — connect(host:port)  (raw sockets)               ║
-- ║  A card with HTTP disabled server-side is present and      ║
-- ║  useless; status() reports the difference so an operator    ║
-- ║  is told "your server has HTTP off" rather than "failed".  ║
-- ╚══════════════════════════════════════════════════════════╝
--
--! THREAT MODEL — read before widening anything here.
--!
--! This module is the first way code on a TOS machine can reach a system
--! outside the Minecraft world. Two consequences follow, and they pull in
--! opposite directions:
--!
--!   1. OUTBOUND is an exfiltration channel. Anything a program can read,
--!      it can now post somewhere. That is why reaching this module at all
--!      requires the `internet` capability, which a package manifest must
--!      declare and an operator must accept — the same shape as
--!      peripheral.modem. The bounds below are NOT a containment boundary
--!      against code that holds the cap; the capability grant is.
--!   2. INBOUND is untrusted bytes. Everything this returns was written by
--!      a stranger. It is never executed here, never deserialized here, and
--!      the byte caps exist so a hostile (or merely large) response cannot
--!      exhaust a machine whose entire RAM is measured in kilobytes.
--!
--! What this module deliberately does NOT do:
--!   * It does not maintain a host allowlist. Policy belongs to the caller
--!     that knows what the fetch is FOR — pkg allowlists repository hosts
--!     because it is about to install executable code; a browser or a
--!     status poller has no business being confined to pkg's list. A
--!     transport that hardcoded one policy would either break the honest
--!     callers or lie to the dangerous one.
--!   * It does not follow redirects blindly (see MAX_REDIRECTS).
--!   * It does not touch the filesystem except through the caller's own
--!     `download` destination path, which the caller must have vetted.

local component = require("component")
local computer  = require("computer")

local internet = {}

local log    = nil
local config = nil

-- ============================================================
-- Bounds
-- ============================================================
-- These are sized for OpenComputers, not for a desktop. A Tier 1 machine
-- has 192 KB of RAM in TOTAL; a response held as a Lua string is real RAM,
-- so "just read it all" is how you OOM a machine from a web page.
local DEFAULT_MAX_BYTES   = 64 * 1024   -- string reads (internet.get)
local HARD_MAX_BYTES      = 512 * 1024  -- ceiling on any configured value
local DEFAULT_TIMEOUT     = 15          -- seconds of no progress
local MAX_REDIRECTS       = 3
local READ_CHUNK_YIELD    = 8           -- yield to other seats every N chunks

internet.DEFAULT_MAX_BYTES = DEFAULT_MAX_BYTES
internet.DEFAULT_TIMEOUT   = DEFAULT_TIMEOUT

function internet.init(modules)
  modules = modules or {}
  log    = modules.log
  config = modules.config
end

-- ============================================================
-- URL vetting
-- ============================================================
--! Only http/https. An OC internet card's request() will happily be handed
--! whatever string you give it, and a scheme we have not thought about is a
--! surface we have not thought about. Control characters are refused
--! outright: a newline in a URL is how header injection starts.
local ALLOWED_SCHEMES = { http = true, https = true }

--- Validate a URL for use with request(). Returns ok, scheme|err, host.
function internet.parseUrl(url)
  if type(url) ~= "string" or url == "" then return false, "empty URL" end
  if #url > 2048 then return false, "URL too long" end
  if url:find("[%c]") then return false, "URL contains control characters" end
  local scheme, rest = url:match("^(%a[%w+.-]*)://(.+)$")
  if not scheme then return false, "URL must start with http:// or https://" end
  scheme = scheme:lower()
  if not ALLOWED_SCHEMES[scheme] then
    return false, "unsupported scheme '" .. scheme .. "' (http and https only)"
  end
  local hostport = rest:match("^([^/?#]+)") or ""
  if hostport == "" then return false, "URL has no host" end
  -- Strip any userinfo; a "user:pass@host" URL is a phishing shape and the
  -- credentials would be logged by anything that echoes the URL back.
  if hostport:find("@", 1, true) then
    return false, "URL must not contain credentials"
  end
  local host = hostport:match("^([^:]+)") or hostport
  return true, scheme, host:lower()
end

--- The host part of a URL, lower-cased, or nil.
function internet.hostOf(url)
  local ok, _, host = internet.parseUrl(url)
  if not ok then return nil end
  return host
end

-- ============================================================
-- Card detection
-- ============================================================
local function card()
  local addr = component.list("internet")()
  if not addr then return nil end
  local ok, p = pcall(component.proxy, addr)
  if not ok then return nil end
  return p, addr
end

--- Is internet access usable right now? Reports WHY not, because the three
--- reasons an operator hits are genuinely different problems: no card
--- installed, the mod's server config has HTTP off, or an admin here has
--- switched it off in /etc/tos.cfg.
function internet.status()
  local st = {
    present = false, http = false, tcp = false,
    enabled = internet.isEnabled(), addr = nil, reason = nil,
  }
  local p, addr = card()
  if not p then
    st.reason = "no internet card installed"
    return st
  end
  st.present = true
  st.addr = addr and addr:sub(1, 8) or nil
  st.http = (p.isHttpEnabled and select(2, pcall(p.isHttpEnabled))) == true
  st.tcp  = (p.isTcpEnabled  and select(2, pcall(p.isTcpEnabled)))  == true
  if not st.enabled then
    st.reason = "disabled on this machine (config: internet = false)"
  elseif not st.http then
    st.reason = "the server has HTTP disabled for internet cards"
  end
  return st
end

function internet.available()
  local st = internet.status()
  return st.present and st.http and st.enabled
end

--- Machine-wide kill switch. A card is installed by a deliberate physical
--- act, so the default when one is present is ON — requiring both a card
--- and a config toggle is friction without a matching gain. The switch
--- exists for the shared box where the card is wanted for one service and
--- not for everybody.
function internet.isEnabled()
  if not config or not config.get then return true end
  local v = config.get("internet")
  if v == nil then return true end
  return v ~= false and v ~= "false" and v ~= "off" and v ~= 0
end

-- ============================================================
-- Limits
-- ============================================================
local function maxBytesLimit(opts)
  local want = (opts and tonumber(opts.maxBytes))
    or (config and config.get and tonumber(config.get("internetMaxKB") or 0) * 1024)
    or nil
  if not want or want <= 0 then want = DEFAULT_MAX_BYTES end
  if want > HARD_MAX_BYTES then want = HARD_MAX_BYTES end
  return math.floor(want)
end

local function timeoutOf(opts)
  local t = (opts and tonumber(opts.timeout))
    or (config and config.get and tonumber(config.get("internetTimeout") or 0))
  if not t or t <= 0 then t = DEFAULT_TIMEOUT end
  return t
end

local function coopYield()
  local okP, proc = pcall(require, "kernel.process")
  if okP and proc and proc.yieldCooperative then proc.yieldCooperative() end
end

-- ============================================================
-- The request core
-- ============================================================
-- `sink(chunk)` is called with each body chunk and returns true to keep
-- going. Both get() and download() are thin wrappers over this, so the
-- timeout / byte-cap / yield behaviour cannot drift between them.
--
-- Returns ok, err, meta   where meta = { status=, headers=, bytes= }.
local function requestInto(url, sink, opts)
  opts = opts or {}
  local okUrl, schemeOrErr = internet.parseUrl(url)
  if not okUrl then return false, schemeOrErr end

  local st = internet.status()
  if not st.present then return false, "no internet card installed" end
  if not st.enabled then return false, st.reason end
  if not st.http   then return false, st.reason or "HTTP is not available" end

  local p = card()
  if not p or not p.request then return false, "internet card has no HTTP support" end

  local limit   = maxBytesLimit(opts)
  local timeout = timeoutOf(opts)

  local okReq, handle, reason = pcall(p.request, url, opts.body, opts.headers, opts.method)
  if not okReq then return false, "request failed: " .. tostring(handle) end
  if not handle then return false, tostring(reason or "request refused") end

  local meta = { bytes = 0 }
  local closed = false
  local function shut()
    if not closed then closed = true; pcall(function() handle.close() end) end
  end

  -- Response metadata is available only once the card has a reply; OC's
  -- handle exposes response() on newer versions. Absent = not fatal.
  local function grabMeta()
    if meta.status or not handle.response then return end
    local okR, code, msg, headers = pcall(handle.response)
    if okR and code then
      meta.status  = tonumber(code) or code
      meta.message = msg
      meta.headers = headers
    end
  end

  local deadline = computer.uptime() + timeout
  local chunks = 0
  while true do
    local okRead, chunk, readErr = pcall(handle.read)
    if not okRead then
      shut(); return false, "read failed: " .. tostring(chunk)
    end
    grabMeta()
    if chunk == nil then
      -- nil = end of stream, or an error carried in the second return.
      shut()
      if readErr then return false, tostring(readErr), meta end
      return true, nil, meta
    end
    if #chunk > 0 then
      meta.bytes = meta.bytes + #chunk
      if meta.bytes > limit then
        shut()
        return false, string.format(
          "response exceeds the %d KB limit (raise it with the maxBytes option " ..
          "or the internetMaxKB config key)", math.floor(limit / 1024)), meta
      end
      if not sink(chunk) then
        shut(); return false, "write failed while saving the response", meta
      end
      deadline = computer.uptime() + timeout   -- progress resets the clock
    else
      -- Empty chunk = "nothing yet"; yield rather than spin. This is the
      -- loop that would otherwise hold the CPU for every seat on the box.
      coopYield()
    end
    chunks = chunks + 1
    if chunks % READ_CHUNK_YIELD == 0 then coopYield() end
    if computer.uptime() > deadline then
      shut()
      return false, "timed out after " .. timeout .. "s with no data", meta
    end
  end
end

--- Fetch a URL into a STRING. For small things — an index, a status page.
--- Bounded by maxBytes (default 64 KB) because the result is RAM.
--- Returns body, err, meta.
function internet.get(url, opts)
  local parts = {}
  local ok, err, meta = requestInto(url, function(chunk)
    parts[#parts + 1] = chunk
    return true
  end, opts)
  if not ok then return nil, err, meta end
  return table.concat(parts), nil, meta
end

--- Fetch a URL straight to a FILE, a chunk at a time.
--
-- This is the one to use for anything that might be big: the body is never
-- held in RAM as a whole, which on a 192 KB machine is the difference
-- between a download and a crash. Writes to `destPath .. ".part"` and
-- renames on success, so a failed or truncated transfer never leaves a
-- half-file that looks complete to the next reader.
--
-- The CALLER is responsible for vetting destPath — this module does not
-- know which paths the caller is allowed to write.
-- Returns ok, err, meta.
function internet.download(url, destPath, opts)
  local fs = (_G._TOS and _G._TOS.fs) or require("kernel.fs")
  if type(destPath) ~= "string" or destPath == "" then
    return false, "no destination path"
  end
  local tmp = destPath .. ".part"
  pcall(fs.remove, tmp)

  -- Buffered append: one fs write per chunk would be brutal on a managed
  -- filesystem, and holding everything is what we are avoiding.
  local buf, bufLen = {}, 0
  local FLUSH_AT = 8 * 1024
  local writeFailed = false
  local function flush()
    if bufLen == 0 then return true end
    local data = table.concat(buf)
    buf, bufLen = {}, 0
    local okW = fs.appendFile and fs.appendFile(tmp, data)
      or fs.writeFile(tmp, data)
    if not okW then writeFailed = true end
    return okW and true or false
  end

  local ok, err, meta = requestInto(url, function(chunk)
    buf[#buf + 1] = chunk
    bufLen = bufLen + #chunk
    if bufLen >= FLUSH_AT then return flush() end
    return true
  end, opts)

  if ok then
    if not flush() then ok, err = false, "write failed" end
  end
  if not ok or writeFailed then
    pcall(fs.remove, tmp)
    return false, err or "write failed", meta
  end
  -- Atomic-ish finish: remove any previous file, then rename the part in.
  pcall(fs.remove, destPath)
  local okMv = fs.rename and fs.rename(tmp, destPath)
  if not okMv then
    -- No rename in this fs layer: fall back to copy-then-drop, still only
    -- after the whole body arrived.
    local data = fs.readFile(tmp)
    if not data or not fs.writeFile(destPath, data) then
      pcall(fs.remove, tmp)
      return false, "could not finalize " .. destPath, meta
    end
    pcall(fs.remove, tmp)
  end
  if log then
    log.info("internet", string.format("Downloaded %d bytes to %s",
      (meta and meta.bytes) or 0, destPath))
  end
  return true, nil, meta
end

--- Raw TCP socket, for the few things that are not HTTP. Returns the OC
--- socket handle untouched — there is no useful bounding to apply to a
--- stream whose protocol we do not know, so this is deliberately thin and
--- the `internet` capability is the whole of the gate.
function internet.socket(address, port)
  local st = internet.status()
  if not st.present then return nil, "no internet card installed" end
  if not st.enabled then return nil, st.reason end
  if not st.tcp then
    return nil, "the server has TCP sockets disabled for internet cards"
  end
  local p = card()
  if not p or not p.connect then return nil, "internet card has no TCP support" end
  local target = tostring(address) .. (port and (":" .. tostring(port)) or "")
  local ok, sock, reason = pcall(p.connect, target)
  if not ok then return nil, tostring(sock) end
  if not sock then return nil, tostring(reason or "connection refused") end
  return sock
end

return internet
