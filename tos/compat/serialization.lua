-- TOS OpenOS Compatibility - serialization
-- Wraps kernel.serialize to provide the OpenOS serialization API.
local ser = require("kernel.serialize")
local serialization = {}

--- Serialize a value to a string (OpenOS-compatible).
-- Unlike kernel.serialize.encode, the result has no "return " prefix.
-- @param value any   value to serialize (typically a table)
-- @param pretty boolean  if true, produce indented output
-- @return string
function serialization.serialize(value, pretty)
  if pretty then
    local s = ser.encode(value)
    -- strip the "return " prefix produced by encode
    if s:sub(1, 7) == "return " then
      s = s:sub(8)
    end
    return s
  else
    return ser.compact(value)
  end
end

--- Deserialize a string back to a Lua value (OpenOS-compatible).
-- @param str string
-- @return any
function serialization.unserialize(str)
  -- #SEC L — return (value) or (nil, error) cleanly, never a raw crash.
  -- A non-string input or an unexpected internal decode error must not
  -- propagate to the OpenOS caller as an uncaught error.
  if type(str) ~= "string" then return nil, "unserialize: expected string" end
  local ok, v, err = pcall(ser.decode, str)
  if not ok then return nil, tostring(v) end
  return v, err
end

return serialization
