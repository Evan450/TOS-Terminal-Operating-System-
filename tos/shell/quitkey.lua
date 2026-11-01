-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Shell - The quit key, without the key table           ║
-- ║                                                            ║
-- ║  shell.keys is the one answer to "is this quit?", but the  ║
-- ║  surfaces that run without the panels (the CLI prompt, CLI ║
-- ║  chat, login, the tutorial) are the ones on the 1 MB floor,║
-- ║  and until someone binds quit its answer is always ^Q. So  ║
-- ║  it is loaded the moment a keys file exists, or when       ║
-- ║  something else has loaded it, and not before.             ║
-- ╚══════════════════════════════════════════════════════════╝

local M = {}

local bound = {}   -- user or "" -> does a keys file apply to them?

local function currentUser()
  local users = package.loaded["kernel.users"]
  local s = users and users.currentSession and users.currentSession()
  return s and s.user or ""
end

local function hasKeysFile(who)
  local okF, fs = pcall(require, "kernel.fs")
  if not okF or type(fs) ~= "table" or not fs.exists then return false end
  if fs.exists("/etc/keys.cfg") then return true end
  if who == "" then return false end
  local home = who == "root" and "/root" or ("/home/" .. who)
  return fs.exists(home .. "/.keys.cfg") == true
end

local function table_()
  local keys = package.loaded["shell.keys"]
  if keys then return keys end
  local who = currentUser()
  if bound[who] == nil then bound[who] = hasKeysFile(who) end
  if bound[who] then
    local ok, mod = pcall(require, "shell.keys")
    if ok then return mod end
  end
end

--- Is this keypress the quit key? `typing`: see keys.isQuit.
function M.is(ch, code, typing)
  local keys = table_()
  if keys then return keys.isQuit(ch, code, typing) end
  return ch == 17
end

--- The quit key's short name for a one-line hint.
function M.hint()
  local keys = table_()
  return keys and keys.quitHint() or "^Q"
end

return M
