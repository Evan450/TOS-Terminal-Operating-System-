-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Shell - Panels Command Executor                ║
-- ║  Parse and run commands, handle pipes and redirects ║
-- ╚══════════════════════════════════════════════════════╝

local helpers = require("shell.panels.helpers")
local editorMod = require("shell.panels.editor")

local M = {}

function M.build(S, deps)
  local F = S.F
  local T = S.T
  local rp = deps.rp
  local makeProgramEnv = deps.makeProgramEnv
  local C = deps.C  -- command table from commands.lua

  local function execSingle(cmdStr, inputData)
    local parts = {}
    for w in cmdStr:gmatch("%S+") do parts[#parts + 1] = w end
    if #parts == 0 then return "" end
    local name = parts[1]:lower()
    local args = {}
    for i = 2, #parts do args[#args + 1] = parts[i] end

    local buf = {}
    local function o(text, color)
      buf[#buf + 1] = { tostring(text), color or T.fg }
    end

    -- If there's piped input, make it available for stdin-consuming commands
    if inputData and #inputData > 0 then
      if name == "grep" and #args >= 1 and not args[2] then
        local pat = args[1]
        for line in inputData:gmatch("([^\n]*)\n?") do
          if line:find(pat, 1, true) then o(line, T.fg) end
        end
        return buf
      elseif name == "wc" and #args == 0 then
        local lc, wc2, bc = 0, 0, #inputData
        for _ in inputData:gmatch("\n") do lc = lc + 1 end
        for _ in inputData:gmatch("%S+") do wc2 = wc2 + 1 end
        o(string.format(" %d lines  %d words  %d bytes", lc, wc2, bc), T.fg)
        return buf
      end
    end

    local fn = C[name]
    if not fn then
      local ok3, modMgr = pcall(require, "kernel.modules")
      if ok3 then fn = modMgr.getCommand(name) end
    end
    if fn then
      local ok2, err2 = pcall(fn, args, o)
      if not ok2 then o("Error: " .. tostring(err2), T.error) end
    else
      local ok3, envMod = pcall(require, "kernel.env")
      local resolved = nil
      if ok3 then
        local pathStr = envMod.read(nil, "PATH") or "/usr/bin:/bin"
        for dir in pathStr:gmatch("[^:]+") do
          local full = F.join(dir, name .. ".lua")
          if F.exists(full) then resolved = full; break end
          full = F.join(dir, name)
          if F.exists(full) then resolved = full; break end
        end
      end
      if resolved then
        local data = F.readFile(resolved)
        if data then
          local fn2, err2 = load(data, "=" .. resolved, "t", makeProgramEnv{ name = resolved, stdout = function(line) o(line, T.fg) end })
          if fn2 then
            local ok2, result = pcall(fn2, table.unpack(args))
            if not ok2 then o("Error: " .. tostring(result), T.error)
            elseif result ~= nil then o(tostring(result), T.fg) end
          else
            o("Compile error: " .. tostring(err2), T.error)
          end
        end
      else
        o("Unknown command: " .. name, T.error)
        o("Type 'help' for available commands.", T.dim)
        if _G._TOS.audio then _G._TOS.audio.warning() end
      end
    end
    return buf
  end

  local function exec(input)
    local hasPipe = input:find("|", 1, true)
    local hasRedirect = input:find("[>]") or input:find("<")

    if hasPipe or hasRedirect then
      local ok2, pipeMod = pcall(require, "kernel.pipe")
      if ok2 then
        local segments = pipeMod.parse(input)
        local prevOutput = nil
        local finalBuf = {}
        for i, seg in ipairs(segments) do
          local buf = execSingle(seg.cmd, prevOutput)
          local textParts = {}
          for _, e in ipairs(buf) do
            textParts[#textParts + 1] = type(e) == "table" and e[1] or tostring(e)
          end
          prevOutput = table.concat(textParts, "\n")

          if seg.stdout and seg.stdout.type == "file" then
            local outPath = rp(seg.stdout.path)
            if helpers.canWrite(S, outPath) then
              if seg.stdout.append then
                F.appendFile(outPath, prevOutput .. "\n")
              else
                F.writeFile(outPath, prevOutput .. "\n")
              end
              helpers.refreshBrowser(S)
              S.lastOut = { "Output written to " .. seg.stdout.path, T.highlight }
            end
            return
          end

          if i == #segments then finalBuf = buf end
        end
        local wrapped = helpers.expandBuf(S, finalBuf)
        if #wrapped == 0 then
        elseif #wrapped == 1 then S.lastOut = wrapped[1]
        else editorMod.openViewTab(S, wrapped, "output") end
        return
      end
    end

    local buf = execSingle(input)
    local wrapped = helpers.expandBuf(S, buf)
    if #wrapped == 0 then
    elseif #wrapped == 1 then S.lastOut = wrapped[1]
    else editorMod.openViewTab(S, wrapped, input:match("^(%S+)") or "output") end
  end

  return exec
end

return M
