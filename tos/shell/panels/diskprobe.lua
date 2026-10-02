-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Shell — what is on a raw drive, read without writing       ║
-- ║                                                                ║
-- ║  `drive format` and `deploy` erase a drive behind a danger      ║
-- ║  confirmation, and the only thing TBFS could say about a        ║
-- ║  foreign volume was "not a TBFS volume". "This drive holds an   ║
-- ║  OSDI partition table" is a different decision from "this       ║
-- ║  drive looks blank", so the confirmations (and `drive info`)    ║
-- ║  name what is there first. RECOGNISING other formats only:      ║
-- ║  TOS reads none of them, and nothing here writes a byte.        ║
-- ║                                                                ║
-- ║  Signatures, from each format's own spec:                       ║
-- ║    TBFS     sector 1 starts "TBFS" (TOS's blockfs)              ║
-- ║    OSDI 1.1 sector 1, first 32-byte entry: start = version,     ║
-- ║             size 0, type "OSDI\xAA\xAA\x55\x55"; little-endian  ║
-- ║    SimpleFS sector 1 starts "\x1bSFS"                           ║
-- ║    OCGPT    sector 2 starts "\x1b[OCGPTm" (table: sectors 2-9)  ║
-- ║    MTPT     LAST sector, 32-byte big-endian entries, the first  ║
-- ║             one typed "mtpt" (Minitel/PsychOS)                  ║
-- ║    MBR/FAT  sector 1 ends 0x55 0xAA                             ║
-- ║  Sectors are 1-based, as the OC drive API numbers them.         ║
-- ╚══════════════════════════════════════════════════════════════╝

local M = {}

local function sector(px, n)
  local ok, s = pcall(px.readSector, n)
  if ok and type(s) == "string" then return s end
end

--! Names below come off the disk, so they are the disk's words: control
--! bytes become "?" and each is capped, so a crafted label cannot draw on
--! the confirmation that is about to ask the operator to erase it.
local function clean(s, max)
  s = tostring(s or ""):gsub("\0.*$", ""):gsub("%c", "?"):gsub("%s+$", "")
  if #s > max then s = s:sub(1, max) end
  return s
end

-- Entries after the header in a table of fixed-size rows; `name` picks a
-- row's display name and returns nil for an unused row.
local function partitions(sec, fmt, name)
  local size, out = string.packsize(fmt), {}
  for pos = size + 1, #sec - size + 1, size do
    local okU, a, b, c, d, e = pcall(string.unpack, fmt, sec, pos)
    local n = okU and name(a, b, c, d, e)
    if n then out[#out + 1] = n end
  end
  return out
end

local function listed(kind, parts)
  if #parts == 0 then return kind .. ", with no partitions" end
  local shown = {}
  for i = 1, math.min(#parts, 3) do shown[i] = parts[i] end
  return ("%s: %d partition%s (%s%s)"):format(kind, #parts, #parts == 1 and "" or "s",
    table.concat(shown, ", "), #parts > 3 and (", +" .. (#parts - 3)) or "")
end

--- Probe the drive proxy `px`. Read-only. Returns { kind=, text= } where
--- kind is tbfs | osdi | simplefs | ocgpt | mtpt | mbr | blank | unknown |
--- unreadable, and text completes "It holds ...".
function M.probe(px)
  if type(px) ~= "table" or type(px.readSector) ~= "function" then
    return { kind = "unreadable", text = "nothing TOS can read as a raw drive" }
  end
  local s1 = sector(px, 1)
  if not s1 then
    return { kind = "unreadable", text = "a first sector that cannot be read" }
  end

  if s1:sub(1, 4) == "TBFS" then
    return { kind = "tbfs", text = "a TBFS volume (TOS's own filesystem)" }
  end
  if #s1 >= 32 and s1:sub(9, 16) == "OSDI\170\170\85\85" then
    local parts = partitions(s1, "<I4I4c8I3c13", function(_, _, ptype, _, name)
      if not ptype:find("[^\0]") then return nil end          -- unallocated
      local n = clean(name, 12)
      return n ~= "" and n or clean(ptype, 8)
    end)
    return { kind = "osdi", text = listed("an OSDI partition table", parts), count = #parts }
  end
  if s1:sub(1, 4) == "\27SFS" then
    local label = #s1 >= 35 and clean(s1:sub(17, 35), 19) or ""   -- after 12 bytes of counts
    return { kind = "simplefs", text = "a SimpleFS filesystem"
      .. (label ~= "" and (' labelled "' .. label .. '"') or "") }
  end
  local s2 = sector(px, 2)
  if s2 and s2:sub(1, 8) == "\27[OCGPTm" then
    return { kind = "ocgpt", text = "an OCGPT partition table" }
  end
  local last
  do
    local okC, cap = pcall(px.getCapacity)
    local okS, ss = pcall(px.getSectorSize)
    if okC and okS and type(cap) == "number" and type(ss) == "number" and ss > 0 then
      local n = math.floor(cap / ss)
      if n > 2 then last = sector(px, n) end
    end
  end
  if last and #last >= 32 and last:sub(21, 24) == "mtpt" then
    local parts = partitions(last, ">c20c4I4I4", function(name)
      local n = clean(name, 12)
      return n ~= "" and n or nil
    end)
    return { kind = "mtpt", text = listed("an MTPT partition table", parts), count = #parts }
  end
  if #s1 >= 512 and s1:sub(511, 512) == "\85\170" then
    return { kind = "mbr", text = "an MS-DOS boot record (MBR or FAT)" }
  end
  if not s1:find("[^\0]") and (not last or not last:find("[^\0]")) then
    return { kind = "blank", text = "nothing in its first and last sectors (it looks blank)" }
  end
  return { kind = "unknown", text = "data in a format TOS does not recognise" }
end

return M
