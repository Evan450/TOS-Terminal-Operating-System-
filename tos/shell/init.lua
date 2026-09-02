local computer = require("computer")
local S, K, E, P, F, D, U, SC, NM = {}, nil, nil, nil, nil, nil, nil, nil, nil
local W, H, cwd, who, st = 80, 25, "/", "root", nil

local myDisplayIdx = nil

local function uiShape()
  local okB, bcM = pcall(require, "kernel.bootcfg")
  local cfg = _G._TOS and _G._TOS.bootcfg
  if okB and bcM and bcM.ui then return bcM.ui(cfg) end
  return "home"
end

local function ctx()
  return { K = K, E = E, P = P, F = F, D = D, U = U, SC = SC, NM = NM,
           cwd = cwd, who = who, W = W, H = H, st = st,
           uiSplit = uiShape() == "split",

           displayIdx = myDisplayIdx }
end

local function runCLI()
  local okC, cliMod = pcall(require, "shell.cli")
  if not okC then

    D.clear(D.c("bg"))
    D.set(1, 2, "CLI unavailable: " .. tostring(cliMod), D.c("error"), D.c("bg"))
    D.set(1, 3, "Reboot and hold S at POST for Safe Mode.", D.c("warning"), D.c("bg"))
    computer.pullSignal(5)
    return "logout"
  end
  return cliMod.run(ctx())
end

local function runTUI()
  local ok, pm = pcall(require, "shell.panels")
  if not ok then
    D.clear(D.c("bg"))
    D.set(1, 2, "WARNING: TUI unavailable (" .. tostring(pm) .. ")", D.c("error"), D.c("bg"))
    D.set(1, 3, "Falling back to the command line.", D.c("warning"), D.c("bg"))
    computer.pullSignal(2)
    return nil
  end
  return pm.run(ctx())
end

function S.run(k, token)
  K = k;  st = token
  E = k.getEvent();  P = k.getProc()

  F = k.getSecureFS() or k.getFS();     D = k.getDisplay()
  U = k.getUsers();  SC = k.getConfig();  NM = k.getNet()

  myDisplayIdx = k.getDisplayIdx and k.getDisplayIdx() or nil
  W, H = D.getSize()
  who = "root"
  if U and st then local s = U.getSession(st); if s then who = s.user end end
  cwd = "/home/" .. who
  if not F.exists(cwd) then cwd = "/" end

  local mode = (uiShape() == "cli") and "cli" or "tui"

  for _ = 1, 64 do
    local code
    if mode == "cli" then
      code = runCLI()
      if code == "tui" then mode = "tui" else return end
    else
      code = runTUI()
      if code == "cli" or code == nil then mode = "cli" else return end
    end
  end

end

return S
