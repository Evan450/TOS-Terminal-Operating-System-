local ser = require("kernel.serialize")
local serialization = {}

function serialization.serialize(value, pretty)
  if pretty then
    local s = ser.encode(value)

    if s:sub(1, 7) == "return " then
      s = s:sub(8)
    end
    return s
  else
    return ser.compact(value)
  end
end

function serialization.unserialize(str)

  if type(str) ~= "string" then return nil, "unserialize: expected string" end
  local ok, v, err = pcall(ser.decode, str)
  if not ok then return nil, tostring(v) end
  return v, err
end

return serialization
