












local mail = require("mail")

return {
  start = mail.start,
  stop  = mail.stop,
  
  check = mail.running,
}
