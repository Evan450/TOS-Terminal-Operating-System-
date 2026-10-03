















local intercom = require("intercom")

return {
  start = intercom.start,
  stop  = intercom.stop,
  
  check = intercom.running,
}
