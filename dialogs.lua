-- ╔═════════════════════════════════════���════════════════╗
-- ║  TOS Shell - Panels Dialogs                         ║
-- ║  Inline input prompts and search dialogs            ║
-- ╚═══════���═══════════════════════════════���══════════════��

local M = {}

local function pullSignal()
  if coroutine.isyieldable and coroutine.isyieldable() then
    return coroutine.yield()
  end
  return require("computer").pullSignal(0.05)
end

function M.promptInput(S, msg, maxLen, isPassword)
  local D, T, W = S.D, S.T, S.W
  local OUT_ROW = S.OUT_ROW
  local buf = ""
  while true do
    D.fill(1, OUT_ROW, W, 1, " ", T.fg, T.bg)
    local disp = isPassword and string.rep("*", #buf) or buf
    D.set(1, OUT_ROW, (msg .. disp .. "_"):sub(1, W), T.title, T.bg)
    local sig, _, ch2, co2 = pullSignal()
    if sig == "key_down" then
      if co2 == 28 then return buf
      elseif ch2 == 17 then return nil
      elseif co2 == 14 then if #buf > 0 then buf = buf:sub(1, -2) end
      elseif ch2 and ch2 >= 32 and ch2 < 127 and #buf < (maxLen or 64) then
        buf = buf .. string.char(ch2)
      end
    elseif sig == "clipboard" and type(ch2) == "string" and not isPassword then
      buf = (buf .. ch2:gsub("\n", "")):sub(1, maxLen or 64)
    end
  end
end

function M.promptSearch(S, currentTerm)
  local D, T, W, H = S.D, S.T, S.W, S.H
  local buf = currentTerm or ""
  while true do
    D.fill(1, H, W, 1, " ", T.fg, T.bg)
    D.set(1, H, ("Find: " .. buf .. "_"):sub(1, W), T.title, T.bg)
    local sig, _, ch2, co2 = pullSignal()
    if sig == "key_down" then
      if co2 == 28 then return #buf > 0 and buf or nil
      elseif ch2 == 17 then return currentTerm
      elseif co2 == 14 then if #buf > 0 then buf = buf:sub(1, -2) end
      elseif ch2 and ch2 >= 32 and ch2 < 127 then buf = buf .. string.char(ch2)
      end
    end
  end
end

return M
