

















return function(t)
  local okH, sha256 = pcall(require, "kernel.sha256")
  if not okH or type(sha256) ~= "table" then
    return t.skip("sha256", "kernel.sha256 unavailable")
  end

  
  
  t.eq("FIPS vector still correct on this machine",
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    sha256.hex("abc"))

  local sizes = { 1024, 16384, 65536, 131072, 262144 }
  local largest = 0
  for _, n in ipairs(sizes) do
    
    
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
    
    
    
    
    if type(collectgarbage) == "function" then pcall(collectgarbage) end
  end

  
  
  t.ok("can hash at least 64K (backup.lua hashes file bodies) -- got "
    .. largest, largest >= 65536)
end
