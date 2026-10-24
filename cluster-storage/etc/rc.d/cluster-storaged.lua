


















local storaged = require("cluster-storaged")

return {
  start   = storaged.start,
  stop    = storaged.stop,
  restart = true,
  needs   = "net",
}
