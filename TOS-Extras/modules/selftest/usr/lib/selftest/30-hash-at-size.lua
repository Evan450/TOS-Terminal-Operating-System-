-- How big an input can this machine actually hash?
--
-- The bug that motivated this check: sha256.lua built its padded message
-- with `{ msg:byte(1, #msg) }`, which returns one Lua value per byte and
-- raises "stack overflow (string slice too long)" past a few hundred
-- thousand of them. Nobody types a million characters to find that. A
-- script does, and so does anyone probing for a way in -- a hash that
-- throws on attacker-chosen length is a denial of service against
-- anything that hashes untrusted input.
--
-- Off-box that limit is Lua 5.4's on a desktop. HERE it is the real one:
-- OC's Lua, OC's memory ceiling, this machine's RAM. Those are different
-- numbers and only one of them matters in play.
--
-- This does not assert a fixed size. It walks up until something gives,
-- reports the largest that worked, and only FAILS if the machine cannot
-- manage a size TOS genuinely needs -- backup.lua hashes file bodies, so
-- "one disk file" is the real requirement.
return function(t)
  local okH, sha256 = pcall(require, "kernel.sha256")
  if not okH or type(sha256) ~= "table" then
    return t.skip("sha256", "kernel.sha256 unavailable")
  end

  -- Known-good anchor first. A ceiling measured with a broken hash is
  -- worth nothing.
  t.eq("FIPS vector still correct on this machine",
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    sha256.hex("abc"))

  local sizes = { 1024, 16384, 65536, 131072, 262144 }
  local largest = 0
  for _, n in ipairs(sizes) do
    -- Memory, not just the stack, is the limit on a 2 MB box: bail out
    -- before allocating something that would OOM the machine mid-boot.
    if computer.freeMemory() < (n * 3) then
      t.skip("hash " .. n .. " bytes", "not enough free memory to try safely")
      break
    end
    local ok = pcall(function()
      local s = string.rep("a", n)
      local d = sha256.hex(s)
      if #d ~= 64 then error("digest was not 64 hex chars", 0) end
    end)
    if ok then largest = n
    else
      t.ok("hashing " .. n .. " bytes raised (largest ok: " .. largest .. ")", false)
      break
    end
    -- collectgarbage is NOT a global here. The kernel environment does
    -- not carry it (kernel/init.lua type-checks before using it, for
    -- the same reason), and calling it blind killed this check at the
    -- 16 KB step on the first successful round.
    if type(collectgarbage) == "function" then pcall(collectgarbage) end
  end

  -- The requirement, stated as a requirement: crypto.hash is fed file
  -- bodies by kernel/backup.lua, so 64 KB is not an aspiration.
  t.ok("can hash at least 64K (backup.lua hashes file bodies) -- got "
    .. largest, largest >= 65536)
end
