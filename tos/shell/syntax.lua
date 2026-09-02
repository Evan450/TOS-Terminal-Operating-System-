local syntax = {}

local KEYWORDS = {
  ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
  ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
  ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
  ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
  ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
  ["until"] = true, ["while"] = true,
}

function syntax.tokenize(line)
  local tokens = {}

  local MAX_TOKENIZE = 2048
  local tail = nil
  if #line > MAX_TOKENIZE then
    tail = line:sub(MAX_TOKENIZE + 1)
    line = line:sub(1, MAX_TOKENIZE)
  end
  local i = 1
  local len = #line

  while i <= len do
    local ch = line:sub(i, i)

    if ch == "-" and line:sub(i + 1, i + 1) == "-" then
      tokens[#tokens + 1] = { type = "comment", text = line:sub(i) }
      break

    elseif ch == '"' then
      local j = i + 1
      while j <= len do
        local c = line:sub(j, j)
        if c == "\\" then j = j + 2
        elseif c == '"' then j = j + 1; break
        else j = j + 1 end
      end
      tokens[#tokens + 1] = { type = "string", text = line:sub(i, j - 1) }
      i = j
      goto next

    elseif ch == "'" then
      local j = i + 1
      while j <= len do
        local c = line:sub(j, j)
        if c == "\\" then j = j + 2
        elseif c == "'" then j = j + 1; break
        else j = j + 1 end
      end
      tokens[#tokens + 1] = { type = "string", text = line:sub(i, j - 1) }
      i = j
      goto next

    elseif ch == "[" and (line:sub(i + 1, i + 1) == "[" or line:sub(i + 1, i + 1) == "=") then
      local eqs = line:match("^%[(=*)%[", i)
      if eqs then
        local close = "]" .. eqs .. "]"
        local j = line:find(close, i + 2 + #eqs, true)
        if j then
          j = j + #close
        else
          j = len + 1
        end
        tokens[#tokens + 1] = { type = "string", text = line:sub(i, j - 1) }
        i = j
        goto next
      end

      tokens[#tokens + 1] = { type = "op", text = ch }
      i = i + 1
      goto next

    elseif ch:match("%d") or (ch == "." and i + 1 <= len and line:sub(i + 1, i + 1):match("%d")) then
      local j = i
      if line:sub(j, j + 1):lower() == "0x" then
        j = j + 2
        while j <= len and line:sub(j, j):match("[%da-fA-F]") do j = j + 1 end
      else
        while j <= len and line:sub(j, j):match("[%d.]") do j = j + 1 end
        if j <= len and line:sub(j, j):match("[eE]") then
          j = j + 1
          if j <= len and line:sub(j, j):match("[%+%-]") then j = j + 1 end
          while j <= len and line:sub(j, j):match("%d") do j = j + 1 end
        end
      end
      tokens[#tokens + 1] = { type = "number", text = line:sub(i, j - 1) }
      i = j
      goto next

    elseif ch:match("[%a_]") then
      local j = i + 1
      while j <= len and line:sub(j, j):match("[%w_]") do j = j + 1 end
      local word = line:sub(i, j - 1)
      local tokType = KEYWORDS[word] and "keyword" or "ident"
      tokens[#tokens + 1] = { type = tokType, text = word }
      i = j
      goto next

    elseif ch:match("%s") then
      local j = i + 1
      while j <= len and line:sub(j, j):match("%s") do j = j + 1 end
      tokens[#tokens + 1] = { type = "space", text = line:sub(i, j - 1) }
      i = j
      goto next

    else
      tokens[#tokens + 1] = { type = "op", text = ch }
      i = i + 1
      goto next
    end

    i = i + 1
    ::next::
  end

  if tail then tokens[#tokens + 1] = { type = "ident", text = tail } end
  return tokens
end

function syntax.tokenColor(tokType, theme)
  if tokType == "keyword" then return theme.syn_keyword or theme.title end
  if tokType == "string"  then return theme.syn_string  or theme.highlight end
  if tokType == "comment" then return theme.syn_comment  or theme.dim end
  if tokType == "number"  then return theme.syn_number   or theme.warning end
  if tokType == "ident"   then return theme.fg end
  if tokType == "op"      then return theme.dim or theme.fg end
  return theme.fg
end

return syntax
