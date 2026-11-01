-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: PaneUI actually running, keys in, screen out ║
-- ║                                                                ║
-- ║  Every other PaneUI test reads the source. The first time the  ║
-- ║  program ran on OpenOS 1.8.9 (the headless machine, 2026-10-31)║
-- ║  it showed what that cannot: ^Q on help quit the program,      ║
-- ║  because Ctrl raises a key_down of its own and "any key" took  ║
-- ║  it; ^Q at a save prompt threw the work away; F10 anywhere     ║
-- ║  but the editor quit past unsaved tabs; and a full disk, which ║
-- ║  ANSWERS nil rather than raising, read "Saved".                ║
-- ║                                                                ║
-- ║  So this loads the real file on a fake OpenOS: a keyboard      ║
-- ║  queue, a screen grid and an in-memory disk.                   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua pane-ui/test_paneui_session.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local src
for _, p in ipairs({ "pane-ui/PaneUI.lua", "PaneUI.lua", "../pane-ui/PaneUI.lua" }) do
  local h = io.open(p, "rb")
  if h then src = h:read("*a"); h:close(); break end
end
if not src then
  print("FAIL: could not find PaneUI.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); os.exit(1)
end
src = src:gsub("\r\n", "\n")

local F = { f1 = 59, f2 = 60, f3 = 61, f4 = 62, f5 = 63, f8 = 66, f10 = 68 }
local CTRL, Q = 29, 16

-- A session's input. A plain string is typed; a table is { ch, code }.
local function keys(...)
  local out = {}
  for _, k in ipairs({ ... }) do
    if type(k) == "string" then
      for i = 1, #k do
        local b = k:byte(i)
        out[#out + 1] = b == 10 and { 13, 28 } or { b, 0 }
      end
    else
      out[#out + 1] = k
    end
  end
  return out
end
local CTRL_Q = { { 0, CTRL }, { 17, Q } }
local function ctrlQ() return { 0, CTRL }, { 17, Q } end

local function run(input, opts)
  opts = opts or {}
  local W, H = 80, 25
  local grid = {}
  for y = 1, H do grid[y] = {} end
  local function put(x, y, s)
    if not grid[y] then return end
    local i = 0
    for _, cp in utf8.codes(s, true) do
      if x + i >= 1 and x + i <= W then grid[y][x + i] = utf8.char(cp) end
      i = i + 1
    end
  end
  local gpu = setmetatable({
    getDepth = function() return 4 end,
    getResolution = function() return W, H end,
    set = function(x, y, s) put(x, y, s); return true end,
    fill = function(x, y, w, h, ch)
      for r = y, y + h - 1 do put(x, r, ch:rep(w)) end
      return true
    end,
    getForeground = function() return 0xFFFFFF end,
    getBackground = function() return 0 end,
  }, { __index = function() return function() return true end end })

  local function screen()
    local rows = {}
    for y = 1, H do
      local cells = {}
      for x = 1, W do cells[x] = grid[y][x] or " " end
      rows[y] = table.concat(cells)
    end
    return table.concat(rows, "\n")
  end

  local disk = opts.disk or {}
  local dirs = { ["/"] = true, ["/home"] = true }
  local queue = {}
  for _, k in ipairs(input) do queue[#queue + 1] = k end
  local shots = {}

  local fs = {}
  function fs.exists(p) return dirs[p] ~= nil or disk[p] ~= nil end
  function fs.isDirectory(p) return dirs[p] == true end
  function fs.size(p) return disk[p] and #disk[p] or 0 end
  function fs.concat(a, b) return (a:gsub("/$", "")) .. "/" .. b end
  function fs.path(p) return p:match("^(.*/)") or "" end
  function fs.remove(p) disk[p] = nil; return true end
  function fs.list(p)
    local names = {}
    local prefix = (p:gsub("/$", "")) .. "/"
    for k in pairs(disk) do
      local rest = k:sub(1, #prefix) == prefix and k:sub(#prefix + 1)
      if rest and not rest:find("/", 1, true) then names[#names + 1] = rest end
    end
    table.sort(names)
    local i = 0
    return function() i = i + 1; return names[i] end
  end
  function fs.open(p, mode)
    if mode:sub(1, 1) == "r" then
      if not disk[p] then return nil, "no such file" end
      local at = 1
      return {
        read = function(_, n)
          if at > #disk[p] then return nil end
          local s = disk[p]:sub(at, at + n - 1); at = at + n; return s
        end,
        close = function() end,
      }
    end
    if p:find(opts.refuseOpen or "\0", 1, true) then return nil, "read only" end
    disk[p] = ""
    return {
      write = function(_, s)
        if opts.fullDisk then return nil, "not enough space" end
        disk[p] = disk[p] .. s
        return true
      end,
      close = function() end,
    }
  end

  local event = {}
  function event.pull(a)
    if type(a) == "string" then
      local k = table.remove(queue, 1)
      if not k then error("a prompt was left waiting for a key", 0) end
      return "key_down", "kb", k[1], k[2]
    end
    local k = table.remove(queue, 1)
    if k then return "key_down", "kb", k[1], k[2] end
    shots[#shots + 1] = screen()
    return "interrupted"
  end

  local env = setmetatable({
    require = function(name)
      if name == "component" then return { gpu = gpu } end
      if name == "computer" then
        return {
          uptime = function() return 10 end,
          freeMemory = function() return 512 * 1024 end,
          totalMemory = function() return 2048 * 1024 end,
        }
      end
      if name == "event" then return event end
      if name == "filesystem" then return fs end
      if name == "term" then
        return { getCursor = function() return 1, 1 end, setCursor = function() end,
                 setCursorBlink = function() end, getCursorBlink = function() return true end }
      end
      if name == "unicode" then
        return { len = utf8.len, sub = function(s, i, j)
          local n = utf8.len(s)
          j = j or n
          if j > n then j = n end
          if i > j then return "" end
          return s:sub(utf8.offset(s, i), utf8.offset(s, j + 1) - 1)
        end, wlen = utf8.len, charWidth = function() return 1 end }
      end
      if name == "shell" then
        return { resolve = function(p) return p end, execute = function() return true end,
                 getWorkingDirectory = function() return "/home" end, setWorkingDirectory = function() end }
      end
      error("the fake OpenOS has no " .. name)
    end,
  }, { __index = _G })

  local chunk = assert(load(src, "=PaneUI", "t", env))
  local rc = chunk()
  return {
    rc = rc,
    left = #queue,
    screen = shots[1] or screen(),
    disk = disk,
  }
end

print("=== it runs ===")
do
  local r = run(keys(), { disk = { ["/home/a.txt"] = "line one" } })
  test("a session with no keys ends cleanly", r.rc == 0, r.rc)
  test("the browser lists the disk", r.screen:find("a.txt", 1, true) ~= nil)
end

print("=== help is closed by ^Q, not the program ===")
do
  local r = run(keys({ 0, F.f1 }, { 0, CTRL }, { 17, Q }, "x"))
  -- help is open after F1; Ctrl must not close it, Q must, and the x then
  -- lands on the browser's command line, which only a live PaneUI can do.
  test("the program was still running for the key after ^Q", r.left == 0, r.left)
  test("the key after ^Q reached the browser", r.screen:find("$ x", 1, true) ~= nil)
  test("help is closed", r.screen:find("HELP", 1, true) == nil)
end
do
  local r = run(keys({ 0, F.f1 }, { 0, CTRL }, "x"))
  test("a bare Ctrl leaves help open until a real key", r.screen:find("HELP", 1, true) == nil
    and r.screen:find("$ ", 1, true) ~= nil)
end

print("=== a save prompt can be backed out of ===")
do
  local a, b = ctrlQ()
  local c, d = ctrlQ()
  local r = run(keys({ 0, F.f4 }, "n.txt\n", "hi", a, b, c, d, "!"))
  test("^Q at the prompt stays in the editor", r.screen:find("EDIT: ", 1, true) ~= nil)
  test("nothing was written", r.disk["/home/n.txt"] == nil)
  test("the prompt says it is there to take",
    src:find("^Q Cancel", 1, true) ~= nil)
end
do
  local a, b = ctrlQ()
  local r = run(keys({ 0, F.f4 }, "n.txt\n", "hi", a, b, "n"))
  test("No still closes without saving", r.disk["/home/n.txt"] == nil
    and r.screen:find("EDIT: ", 1, true) == nil)
end
do
  local a, b = ctrlQ()
  local r = run(keys({ 0, F.f4 }, "n.txt\n", "hi", a, b, "y"))
  test("Yes saves and closes", r.disk["/home/n.txt"] == "hi", r.disk["/home/n.txt"])
  test("the tab is gone", r.screen:find("EDIT: ", 1, true) == nil)
end

print("=== no way out skips an unsaved tab ===")
do
  local r = run(keys({ 0, F.f4 }, "n.txt\n", "hi", { 0, F.f2 }, { 0, F.f10 }, "y"))
  test("F10 from the browser asks, and Yes saves", r.disk["/home/n.txt"] == "hi", r.disk["/home/n.txt"])
  test("then it quits (nothing left unread)", r.left == 0 and r.rc == 0)
end
do
  local a, b = ctrlQ()
  local r = run(keys({ 0, F.f4 }, "n.txt\n", "hi", { 0, F.f2 }, { 0, F.f10 }, a, b, "!"))
  test("Cancel keeps PaneUI open on the unsaved tab", r.screen:find("EDIT: ", 1, true) ~= nil
    and r.screen:find("hi!", 1, true) ~= nil)
end
do
  local a, b = ctrlQ()
  local r = run(keys({ 0, F.f4 }, "n.txt\n", "hi", { 0, F.f2 }, a, b, "n"))
  test("^Q from the browser takes the same path", r.left == 0 and r.disk["/home/n.txt"] == nil)
end
do
  local r = run(keys({ 0, F.f4 }, "n.txt\n", "hi", { 0, F.f2 }, "exit\n", "y"))
  test("so does typing exit", r.disk["/home/n.txt"] == "hi", r.disk["/home/n.txt"])
end
do
  local r = run(keys({ 0, F.f4 }, "n.txt\n", "hi", { 0, F.f1 }, { 0, F.f10 }, "n"))
  test("and F10 from help", r.left == 0 and r.rc == 0)
end

print("=== a refused write is not called done ===")
do
  local r = run(keys({ 0, F.f4 }, "n.txt\n", "hi", { 19, 31 }), { fullDisk = true })
  test("a full disk reads as a failed save", r.screen:find("Save failed", 1, true) ~= nil)
  test("and says why", r.screen:find("not enough space", 1, true) ~= nil)
  test("the tab still says unsaved", r.screen:find("[+]", 1, true) ~= nil)
end
do
  local r = run(keys({ 0, F.f5 }, "\n"), { disk = { ["/home/a.txt"] = "line one" }, fullDisk = true })
  test("a copy onto a full disk reports it", r.screen:find("Copy failed", 1, true) ~= nil)
  test("and leaves no empty copy behind", r.disk["/home/a.txt.bak"] == nil)
  test("the original is untouched", r.disk["/home/a.txt"] == "line one")
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***"); os.exit(1)
end
print("All tests passed.")
