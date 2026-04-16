-- TOS OpenOS Compatibility - text
-- Lightweight text manipulation utilities matching the OpenOS text API.
local text = {}

--- Strip leading and trailing whitespace from a string.
-- @param s string
-- @return string
function text.trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

--- Word-wrap a string to the given width. Returns a table of lines.
-- @param str string
-- @param width number
-- @return table
function text.wrap(str, width)
  width = width or 80
  local lines = {}
  for paragraph in str:gmatch("[^\n]*") do
    if paragraph == "" then
      lines[#lines + 1] = ""
    else
      local line = ""
      for word in paragraph:gmatch("%S+") do
        if line == "" then
          line = word
        elseif #line + 1 + #word <= width then
          line = line .. " " .. word
        else
          lines[#lines + 1] = line
          line = word
        end
      end
      lines[#lines + 1] = line
    end
  end
  return lines
end

--- Pad a string on the right with spaces to reach length n.
-- @param s string
-- @param n number
-- @return string
function text.padRight(s, n)
  local len = #s
  if len >= n then return s end
  return s .. string.rep(" ", n - len)
end

--- Pad a string on the left with spaces to reach length n.
-- @param s string
-- @param n number
-- @return string
function text.padLeft(s, n)
  local len = #s
  if len >= n then return s end
  return string.rep(" ", n - len) .. s
end

--- Replace tab characters with spaces.
-- @param s string
-- @param tabWidth number  (default 8)
-- @return string
function text.detab(s, tabWidth)
  tabWidth = tabWidth or 8
  local col = 0
  local out = {}
  for i = 1, #s do
    local ch = s:sub(i, i)
    if ch == "\t" then
      local spaces = tabWidth - (col % tabWidth)
      out[#out + 1] = string.rep(" ", spaces)
      col = col + spaces
    elseif ch == "\n" then
      out[#out + 1] = ch
      col = 0
    else
      out[#out + 1] = ch
      col = col + 1
    end
  end
  return table.concat(out)
end

--- Tokenize a string into an array of tokens, respecting quoted strings.
-- Both single and double quotes are recognized. A backslash inside a
-- quoted region escapes the next character (including the quote itself).
-- @param s string
-- @return table
function text.tokenize(s)
  local tokens = {}
  local i = 1
  local len = #s
  while i <= len do
    -- skip whitespace
    local ws = s:match("^%s+", i)
    if ws then i = i + #ws end
    if i > len then break end
    local ch = s:sub(i, i)
    if ch == '"' or ch == "'" then
      -- quoted token
      local quote = ch
      i = i + 1
      local buf = {}
      while i <= len do
        local c = s:sub(i, i)
        if c == "\\" and i < len then
          -- escaped character
          i = i + 1
          buf[#buf + 1] = s:sub(i, i)
        elseif c == quote then
          break
        else
          buf[#buf + 1] = c
        end
        i = i + 1
      end
      tokens[#tokens + 1] = table.concat(buf)
      i = i + 1 -- skip closing quote
    else
      -- unquoted token: run until whitespace or quote
      local tok = s:match("^[^%s'\"]+", i)
      if tok then
        tokens[#tokens + 1] = tok
        i = i + #tok
      else
        i = i + 1
      end
    end
  end
  return tokens
end

return text
