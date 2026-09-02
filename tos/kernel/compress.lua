local component = require("component")

local compress = {}

local MAGIC        = "TCZ1"
local F_COMPRESSED = 1
local CHUNK        = 4096
local MIN_COMPRESS = 256

local dataCard = nil
local avail    = false
local log      = nil

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

function compress.init(modules)
  modules = modules or {}
  log = modules.log or log
  dataCard, avail = nil, false

  local info
  do
    local okD, dc = pcall(require, "kernel.datacard")
    if okD and dc and dc.detect then info = dc.detect() end
  end

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

      log.info("compress", "Data card present (" .. (info.name or "?")
        .. ") but no deflate/inflate — compression store-only")
    else
      log.info("compress", "No data card — compression disabled (store-only)")
    end
  end
  return avail
end

function compress.available() return avail end

function compress.isPacked(blob)
  return type(blob) == "string" and #blob >= 9 and blob:sub(1, 4) == MAGIC
end

local function packStored(data)
  return MAGIC .. string.char(0) .. u32(#data) .. data
end

local coopProc = nil
local function coopYield()
  if coopProc == nil then
    local okP, m = pcall(require, "kernel.process")
    coopProc = (okP and m and m.yieldCooperative) and m or false
  end
  if coopProc then coopProc.yieldCooperative() end
end

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

compress.MAGIC = MAGIC

return compress
