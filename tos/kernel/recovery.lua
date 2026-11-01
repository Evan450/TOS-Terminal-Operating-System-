-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Recovery menu                               ║
-- ║                                                           ║
-- ║  One screen for a machine that is in trouble, reached     ║
-- ║  from /init.lua BEFORE the kernel exists: R at the POST   ║
-- ║  screen, or by itself when a system file is missing.      ║
-- ║                                                           ║
-- ║  This is stage 2 of the split BIOS. The EEPROM has no     ║
-- ║  room for a menu and keeps only what must survive a dead  ║
-- ║  disk ("d: other disk"). Everything here needs this disk, ║
-- ║  so everything here may fail, and none of it may stop a   ║
-- ║  boot: /init.lua pcalls the lot and falls back to the     ║
-- ║  screens it had before this file existed.                 ║
-- ║                                                           ║
-- ║  The menu is driven through ctx, the shape Boot Settings  ║
-- ║  uses: { W, H, set, clear, color, readKey, px, tick,      ║
-- ║  component, failed, why, otherDisk }.                     ║
-- ╚══════════════════════════════════════════════════════════╝

local recovery = {}

--- The filesystem srm wants, over a raw filesystem proxy: there is no
--- kernel.fs yet. Same remove-then-rename as fs.writeFileAtomic, and the
--- same suffix, so a restore cut off halfway is finished by the next boot's
--- recoverAtomic instead of leaving a file at zero bytes.
function recovery.fsOver(px)
  local fs = {}
  function fs.exists(path)
    local ok, there = pcall(px.exists, path)
    return ok and there == true
  end
  function fs.size(path) return px.size(path) end
  function fs.remove(path) return px.remove(path) end
  function fs.makeDirectory(path) return px.makeDirectory(path) end
  function fs.readFile(path)
    local h, err = px.open(path, "r")
    if not h then return nil, err end
    local parts = {}
    while true do
      local chunk = px.read(h, 4096)
      if not chunk then break end
      parts[#parts + 1] = chunk
    end
    px.close(h)
    return table.concat(parts)
  end
  function fs.writeFile(path, content)
    local parent = path:match("^(.*)/[^/]*$")
    if parent and parent ~= "" and not fs.exists(parent) then
      pcall(px.makeDirectory, parent)
    end
    local h, err = px.open(path, "w")
    if not h then return false, err end
    local ok, werr = px.write(h, content)
    px.close(h)
    if not ok then return false, werr end
    return true
  end
  function fs.writeFileAtomic(path, content)
    local tmp = path .. ".tos-tmp"
    local ok, err = fs.writeFile(tmp, content)
    if ok and px.size(tmp) ~= #content then ok, err = false, "short write" end
    if not ok then
      pcall(px.remove, tmp)
      return false, err or "temp write failed"
    end
    if fs.exists(path) then
      pcall(px.remove, path)
      if fs.exists(path) then
        pcall(px.remove, tmp)
        return false, "cannot replace target"
      end
    end
    if not px.rename(tmp, path) then return false, "rename failed" end
    return true
  end
  return fs
end

--- What the menu offers. A machine that failed its file check cannot carry
--- on or reach Boot Settings' reboot-to-apply usefully, so it is not offered
--- those: everything on the list has to be able to work from where it is.
function recovery.items(failed, canSwitchDisk)
  local items = {}
  local function add(label, action) items[#items + 1] = { label = label, action = action } end
  if not failed then
    add("Carry on booting", "continue")
    add("Safe Mode, this boot only", "safe")
    add("Boot Settings", "settings")
  end
  add("Check system files", "check")
  add("Restore changed files from the baseline", "restore")
  if canSwitchDisk then add("Boot another disk", "disk") end
  add("Reboot", "reboot")
  add("Power off", "off")
  return items
end

--- Show a report a screen at a time, then wait for a key.
local function showLines(ctx, title, lines)
  local col = ctx.color
  local rows = math.max(1, (ctx.H or 16) - 4)
  local i = 1
  repeat
    ctx.clear()
    ctx.set(2, 1, title, col("title"))
    for y = 1, rows do
      local l = lines[i]
      if not l then break end
      ctx.set(2, y + 2, tostring(l.text):sub(1, (ctx.W or 50) - 2), col(l.role or "value"))
      i = i + 1
    end
    ctx.set(2, ctx.H or 16, lines[i] and "Any key: more" or "Any key: back", col("dim"))
    ctx.readKey()
  until not lines[i]
end

local ROLE = { ok = "ok", info = "dim", warn = "warn", err = "warn" }

--- Run the check or the restore through srm, and show what it said.
--- `tick` is what keeps the machine alive: OC stops a computer that goes too
--- long without yielding, and here there is no scheduler for srm to yield to.
local function runSrm(ctx, restore)
  local function failed(why)
    showLines(ctx, "Recovery", { { text = "The repair tools did not load:", role = "warn" },
      { text = tostring(why), role = "dim" } })
  end
  local okS, srm = pcall(require, "kernel.srm")
  if not okS or type(srm) ~= "table" then return failed(srm) end
  local okC, crypto = pcall(require, "kernel.crypto")
  if not okC or type(crypto) ~= "table" then return failed(crypto) end
  -- A data card if there is one: the software hash is much slower.
  if crypto.init then pcall(crypto.init) end

  ctx.clear()
  ctx.set(2, 1, restore and "Restoring..." or "Checking...", ctx.color("title"))
  ctx.set(2, 3, "Hashing every file in the baseline. This takes a while.", ctx.color("dim"))
  local done = 0
  srm.beat = function()
    done = done + 1
    ctx.set(2, 4, tostring(done) .. " files", ctx.color("value"))
    if ctx.tick then ctx.tick() end
  end
  local deps = { fs = recovery.fsOver(ctx.px), crypto = crypto, component = ctx.component }
  local okR, rep = pcall(restore and srm.restore or srm.scan, deps, { checkStore = false })
  srm.beat = nil
  if not okR then return failed(rep) end

  local lines = {}
  for _, f in ipairs(rep.findings or {}) do
    lines[#lines + 1] = { text = f.text, role = ROLE[f.sev] or "value" }
  end
  if #lines == 0 then lines[1] = { text = "Nothing to report.", role = "ok" } end
  showLines(ctx, restore and "Restore" or "System files", lines)
  return rep
end

local function confirmRestore(ctx)
  local col = ctx.color
  ctx.clear()
  ctx.set(2, 1, "Restore changed files", col("title"))
  ctx.set(2, 3, "Files that differ from the baseline go back to the copies", col("value"))
  ctx.set(2, 4, "it verified. Anything you changed on purpose is lost.", col("value"))
  ctx.set(2, 6, "Y goes ahead. Any other key goes back.", col("warn"))
  local _, ch = ctx.readKey()
  return ch == 89 or ch == 121
end

--- The menu. Returns the action /init.lua has to carry out: "continue",
--- "safe", "settings", "reboot" or "off". Check and restore are done here,
--- and the disk switch never comes back: it ends in a reboot either way.
function recovery.run(ctx)
  local col = ctx.color
  local items = recovery.items(ctx.failed, ctx.otherDisk ~= nil)
  while true do
    ctx.clear()
    ctx.set(2, 1, "TOS Recovery", col("title"))
    local y = 2
    if ctx.why then
      ctx.set(2, y, tostring(ctx.why):sub(1, (ctx.W or 50) - 2), col("warn"))
      y = y + 1
    end
    y = y + 1
    for i, item in ipairs(items) do
      ctx.set(3, y, i .. "  " .. item.label, col("value"))
      y = y + 1
    end
    ctx.set(2, y + 1, "Press a number.", col("dim"))

    local _, ch = ctx.readKey()
    local item = items[(tonumber(ch) or 0) - 48]
    if item then
      if item.action == "check" then
        runSrm(ctx, false)
      elseif item.action == "restore" then
        if confirmRestore(ctx) then runSrm(ctx, true) end
      elseif item.action == "disk" then
        ctx.clear()
        ctx.otherDisk()
      else
        return item.action
      end
    end
  end
end

return recovery
