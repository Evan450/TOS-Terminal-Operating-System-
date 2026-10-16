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
--
-- This runs as root, so its env is a kernel.sandbox: no _TOS, and a
-- require that refuses every "kernel." name. It used to reach for both
-- -- `_G._TOS.net`, then `pcall(require, "kernel.netfs")` -- so start()
-- returned on its first line and rc listed it running while nothing was
-- ever armed. `net` here is the sandbox's handle on kernel.net (rc.d
-- services get the whole module, setServiceArm included), and arming
-- through it is the whole job: net records the arm, applies it to
-- kernel.netfs if that is loaded, and kernel.netfs applies it itself
-- when the first NETFS_REQ loads it. Arming re-reads the export file,
-- so editing it and restarting this service is the update procedure; a
-- file that does not load serves nothing and says why in the log.
--
-- No request-logging listener, unlike fileshare: the sandbox has no log
-- to write to, and any NETFS_REQ listener registered here would stop
-- net's dispatch from lazy-loading kernel.netfs for the first request.

local function start()
  -- Fail out loud: a quiet return here is how rc came to report a
  -- service running that had armed nothing.
  if not (net and net.setServiceArm) then
    error("netfsd: no kernel.net arm API in this environment", 0)
  end
  net.setServiceArm("netfsd", true)
end

local function stop()
  if net and net.setServiceArm then net.setServiceArm("netfsd", false) end
end

return {
  start   = start,
  stop    = stop,
  deps    = {},
  restart = true,
  caps    = { net = true },
  needs   = "net",  -- not loaded at all without a network (rc.lua NEEDS)
  -- root, NOT _kernel_. This shipped claiming kernel tier -- copied from
  -- 20-fileshare.lua, which is on rc.lua's #SEC C2 allowlist -- so every
  -- boot logged "Refusing kernel-tier service '20-netfsd.lua': not in C2
  -- allowlist; demoting to user-tier". The honest fix is to stop claiming
  -- it rather than to widen the allowlist: netfsd only flips the backend's
  -- arm flag, which root does, and the export file it governs is root's to
  -- write. Nothing in kernel/netfs.lua takes a session, so the tier bought
  -- nothing -- and the kernel tier's gated require refuses kernel.netfs too.
  user    = "root",
}
