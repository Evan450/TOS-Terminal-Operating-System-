-- ╔══════════════════════════════════════╗
-- ║  TOS Kernel - Disk Compression       ║
-- ║  Data-card deflate/inflate framing   ║
-- ╚══════════════════════════════════════╝
-- A thin, detection-gated wrapper around the OpenComputers data card's
-- deflate/inflate (available on EVERY data-card tier). It frames compressed
-- data with a small self-describing header so it can be reversed later, and
-- it degrades safely:
--
--   * No data card  -> compression is unavailable; pack() returns a "stored"
--     (uncompressed) blob, so callers still get a valid blob and nothing is
--     "compressed that isn't there". A stored blob needs NO data card to read.
--   * Data card      -> data is deflated in bounded chunks (the card caps the
--     bytes per call) and only kept if it actually shrinks past the header
--     overhead; otherwise we fall back to "stored" for that payload.
--
-- Blob layout (big-endian):
--   stored:      MAGIC(4) flags(1=0)            origLen(u32)  rawbytes...
--   compressed:  MAGIC(4) flags(1=F_COMPRESSED) origLen(u32)  nChunks(u16)
--                then nChunks × ( cLen(u32) cData[cLen] )
-- Each chunk is inflated independently and concatenated; origLen is the
-- integrity check on the reconstructed total.
--
-- NOTE on cost: a data-card call draws from a per-tick budget and can sleep
-- the computer a game-tick when spent (the same trap that bit the password
-- KDF). So compression is for COLD, one-shot data (files, spilled swap), not
-- hot loops. We skip tiny payloads entirely to avoid pointless calls.

local component = require("component")

local compress = {}

local MAGIC        = "TCZ1"          -- TOS Compressed, v1
local F_COMPRESSED = 1
local CHUNK        = 4096            -- conservative: within every tier's call cap
local MIN_COMPRESS = 256            -- below this, deflate can't beat the header

local dataCard = nil
local avail    = false
local log      = nil

-- ── byte helpers (big-endian) ───────────────────────────────
local function u32(n)
  return string.char((n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF)
end
local function u16(n) return string.char((n >> 8) & 0xFF, n & 0xFF) end
local function ru32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return ((a << 24) | (b << 16) | (c << 8) | d) & 0xFFFFFFFF
end
local function ru16(s, i)
  local a, b = s:byte(i, i + 1)
  return (a << 8) | b
end

-- ============================================================
-- Init / detection
-- ============================================================

--- Detect a data card exposing deflate/inflate. Safe to call repeatedly.
--- Uses the shared kernel.datacard detector so it agrees with crypto and
--- the POST screen about what's installed — and, crucially, reports a
--- card that IS present but lacks deflate/inflate honestly (instead of
--- the old "No data card", which read as a detection failure even when
--- crypto saw the same card as Hardware).
function compress.init(modules)
  modules = modules or {}
  log = modules.log or log
  dataCard, avail = nil, false

  local info
  do
    local okD, dc = pcall(require, "kernel.datacard")
    if okD and dc and dc.detect then info = dc.detect() end
  end

  -- Fallback when the shared detector isn't reachable (very early boot, or
  -- a standalone test harness): probe the component directly. compress must
  -- never go dead just because kernel.datacard couldn't load.
  if not info then
    info = { present = false, caps = {}, name = nil }
    pcall(function()
      for addr in component.list("data") do
        local p = component.proxy(addr)
        if p then
          info.present = true
          info.caps = { deflate = type(p.deflate) == "function"
            and type(p.inflate) == "function" }
          info.proxy = p
          info.name = info.caps.deflate and "data card" or "data card (no deflate)"
          return
        end
      end
    end)
  end

  if info and info.present and info.caps.deflate then
    dataCard, avail = info.proxy, true
  end

  if log and log.info then
    if avail then
      log.info("compress", "Data card present (" .. (info.name or "?")
        .. ") — deflate/inflate available")
    elseif info and info.present then
      -- The card exists (crypto may use it for hashing/AES) but this tier
      -- or emulator build doesn't expose deflate/inflate.
      log.info("compress", "Data card present (" .. (info.name or "?")
        .. ") but no deflate/inflate — compression store-only")
    else
      log.info("compress", "No data card — compression disabled (store-only)")
    end
  end
  return avail
end

--- True when a data card can actually deflate/inflate on this machine.
function compress.available() return avail end

--- True if `blob` is a TCZ container produced by pack().
function compress.isPacked(blob)
  return type(blob) == "string" and #blob >= 9 and blob:sub(1, 4) == MAGIC
end

-- ============================================================
-- Pack / unpack
-- ============================================================

-- Build a "stored" (uncompressed) container — always readable, no card needed.
local function packStored(data)
  return MAGIC .. string.char(0) .. u32(#data) .. data
end

-- Cooperative slice between deflate/inflate chunks (#REV multi-seat
-- freeze) — pure in-RAM work, safe to interleave. Lazy + guarded so
-- off-box tests and non-process contexts are no-ops.
local coopProc = nil
local function coopYield()
  if coopProc == nil then
    local okP, m = pcall(require, "kernel.process")
    coopProc = (okP and m and m.yieldCooperative) and m or false
  end
  if coopProc then coopProc.yieldCooperative() end
end

--- Compress `data` into a TCZ blob. Always returns a valid blob (never nil for
--- a string): falls back to "stored" when there's no card, the payload is
--- tiny, deflate fails, or the result wouldn't be smaller.
--- @return blob string, method ("deflate"|"stored"), origBytes, packedBytes
function compress.pack(data)
  if type(data) ~= "string" then return nil, "data must be a string" end
  local orig = #data

  if avail and orig >= MIN_COMPRESS then
    local chunks, total, ok = {}, 0, true
    for i = 1, orig, CHUNK do
      coopYield()
      local piece = data:sub(i, i + CHUNK - 1)
      local dok, def = pcall(dataCard.deflate, piece)
      if not dok or type(def) ~= "string" then ok = false; break end
      chunks[#chunks + 1] = def
      total = total + #def
    end
    -- header overhead: MAGIC(4)+flags(1)+origLen(4)+nChunks(2)+ 4 per chunk len
    local overhead = 11 + 4 * #chunks
    if ok and (total + overhead) < orig then
      local out = { MAGIC, string.char(F_COMPRESSED), u32(orig), u16(#chunks) }
      for _, c in ipairs(chunks) do
        out[#out + 1] = u32(#c)
        out[#out + 1] = c
      end
      local blob = table.concat(out)
      return blob, "deflate", orig, #blob
    end
  end

  local blob = packStored(data)
  return blob, "stored", orig, #blob
end

--- Reverse pack(). Returns the original data, or (nil, err). A "stored" blob
--- decodes without a data card; a "compressed" blob needs one.
function compress.unpack(blob)
  if not compress.isPacked(blob) then return nil, "not a TCZ blob" end
  local flags   = blob:byte(5)
  local origLen = ru32(blob, 6)

  if (flags & F_COMPRESSED) == 0 then
    local data = blob:sub(10)
    if #data ~= origLen then return nil, "stored length mismatch" end
    return data
  end

  if not avail then return nil, "data card required to decompress" end
  -- A compressed container's header is 11 bytes: MAGIC(4) flags(1)
  -- origLen(4) nChunks(2). isPacked only demands 9 — enough for a STORED
  -- blob — so a container truncated to 9 or 10 bytes reached the ru16
  -- below with nothing to read and raised "bitwise operation on a nil
  -- value" out of a function whose whole contract is (nil, err). The
  -- `decompress` command calls this unprotected and prints err; it got a
  -- Lua traceback instead. Every OTHER truncation was already caught
  -- inside the chunk loop; only the header itself was unchecked.
  -- (test_compress.lua)
  if #blob < 11 then return nil, "truncated blob" end
  local off = 10
  local nChunks = ru16(blob, off); off = off + 2
  local out = {}
  for _ = 1, nChunks do
    coopYield()
    if off + 3 > #blob then return nil, "truncated blob" end
    local cLen = ru32(blob, off); off = off + 4
    local cData = blob:sub(off, off + cLen - 1); off = off + cLen
    if #cData ~= cLen then return nil, "truncated chunk" end
    local iok, inf = pcall(dataCard.inflate, cData)
    if not iok or type(inf) ~= "string" then return nil, "inflate failed" end
    out[#out + 1] = inf
  end
  local data = table.concat(out)
  if #data ~= origLen then return nil, "length mismatch after inflate" end
  return data
end

-- Introspection for callers/tests.
compress.MAGIC = MAGIC

return compress
