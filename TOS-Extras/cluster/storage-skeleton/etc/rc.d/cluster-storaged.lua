-- ╔══════════════════════════════════════╗
-- ║  Cluster Storage Node service        ║
-- ╚══════════════════════════════════════╝
-- Serves the Public storage tier: writes on 2101 (TRUSTED, namespace
-- checked) and reads on 2100 (open, per §2.2). Stopping the service
-- stops both and flushes the index, so the node comes back knowing
-- what it holds.

local running = false

local function start()
  local ok, d = pcall(require, "cluster-storaged")
  if not ok or not d then return end
  local sok, serr = d.start()
  if not sok then
    if _G._TOS and _G._TOS.log then
      _G._TOS.log("cluster-storaged", "failed to start: " .. tostring(serr))
    end
    return
  end
  running = true
end

local function stop()
  local ok, d = pcall(require, "cluster-storaged")
  if ok and d and d.stop then d.stop() end
  running = false
end

return {
  start   = start,
  stop    = stop,
  deps    = {},
  restart = true,
  caps    = { ["fs.read"] = true, ["fs.write"] = true, net = true },
  user    = "_kernel_",
}
