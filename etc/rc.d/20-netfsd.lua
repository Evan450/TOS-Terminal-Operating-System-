-- ╔══════════════════════════════════════╗
-- ║  TOS netfs Service                   ║
-- ║  Serve exported directories to peers ║
-- ╚══════════════════════════════════════╝
-- Answers NETFS_REQ from TRUSTED, challenge-verified peers using the
-- export table in /etc/netfs-exports.cfg. A machine with no exports
-- file serves nothing, and a machine without this service serves
-- nothing even if the file exists.
--
-- The arm/disarm dance is deliberate and copied from 20-fileshare.lua:
-- kernel.netfs registers its NETFS_REQ listener once at init and never
-- removes it, so `service stop netfsd` has to actually disarm the
-- backend. A stop() that only dropped a log listener would leave the
-- machine serving files while reporting the service as stopped.

local running = false
local listenerID = nil

local function backend()
  local ok, mod = pcall(require, "kernel.netfs")
  if ok then return mod end
  return nil
end

local function start()
  local net = _G._TOS and _G._TOS.net
  if not net then return end

  local netfs = backend()
  if not netfs then return end

  -- Re-read exports on every start, so editing the file and restarting
  -- the service is the whole update procedure.
  local F = _G._TOS and _G._TOS.fs
  local ok, err = netfs.loadExports(F)
  if not ok then
    if _G._TOS and _G._TOS.log then
      _G._TOS.log("netfsd", "refusing to start: " .. tostring(err))
    end
    -- Fail closed: a malformed export table must not fall back to some
    -- earlier, wider set that happens to still be in memory.
    netfs.setExports({})
    netfs.setEnabled(false)
    return
  end

  netfs.setEnabled(true)
  running = true

  local protocol = net.getProtocol()
  listenerID = net.on(protocol.TYPE.NETFS_REQ, function(packet, remoteAddr)
    if _G._TOS and _G._TOS.log then
      local p = packet.payload or {}
      _G._TOS.log("netfsd", "request from " .. tostring(remoteAddr):sub(1, 8) ..
        ": " .. tostring(p.op) .. " " .. tostring(p.share))
    end
  end)
end

local function stop()
  running = false
  local netfs = backend()
  if netfs then
    netfs.setEnabled(false)
    netfs.setExports({})
  end
  if listenerID then
    local net = _G._TOS and _G._TOS.net
    if net then
      local protocol = net.getProtocol()
      net.off(protocol.TYPE.NETFS_REQ, listenerID)
    end
    listenerID = nil
  end
end

return {
  start   = start,
  stop    = stop,
  deps    = {},
  restart = true,
  caps    = { ["fs.read"] = true, ["fs.write"] = true, net = true },
  -- root, NOT _kernel_. This shipped claiming kernel tier -- copied from
  -- 20-fileshare.lua, which is on rc.lua's #SEC C2 allowlist -- so every
  -- boot logged "Refusing kernel-tier service '20-netfsd.lua': not in C2
  -- allowlist; demoting to user-tier". The honest fix is to stop claiming
  -- it rather than to widen the allowlist: netfsd reads one config file
  -- and flips the backend's arm flag, both of which root does. Nothing in
  -- kernel/netfs.lua takes a session, so the tier bought nothing.
  user    = "root",
}
