-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: web's browser screen, driven like an operator would   ║
-- ║                                                              ║
-- ║  Loads the REAL init.lua inside a fake of the package        ║
-- ║  sandbox (a GPU that keeps a screen buffer, a keyboard fed    ║
-- ║  from a script, a fake `internet` capability) and types at    ║
-- ║  it: opening a url, following a numbered link, going back,    ║
-- ║  scrolling, and the no-capability / no-card / fetch-failure    ║
-- ║  paths. render.lua has its own tests; this is the seam between ║
-- ║  keys, the fetch, and the screen.                                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua web/browser/test_web_ui.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local ROOT = "web/browser/"

local function key(code, ch) return { "key_down", "kbd", ch or 0, code } end
local function char(c) return key(0, c:byte()) end
local function typed(s) local t = {} for c in s:gmatch(".") do t[#t + 1] = char(c) end return t end
local ENTER, UP, DOWN, LEFT, RIGHT = key(28, 13), key(200), key(208), key(203), key(205)
local BKSP, F10 = key(14, 8), key(68)
local function script(...)
  local out = {}
  for _, part in ipairs({ ... }) do
    if part[1] == "key_down" then out[#out + 1] = part
    else for _, k in ipairs(part) do out[#out + 1] = k end end
  end
  return out
end

-- `pages`: url -> html (or a function returning nil, err for a failure
-- case). `opts.noInternet` skips injecting the capability at all, the
-- way the sandbox behaves when the manifest grant was refused.
local function run(opts)
  opts = opts or {}
  local W, H = opts.W or 80, opts.H or 25
  local fx = { screens = {}, pages = opts.pages or {} }
  local rows = {}
  for y = 1, H do rows[y] = {} for x = 1, W do rows[y][x] = " " end end
  local function text() local t = {} for y = 1, H do t[y] = table.concat(rows[y]) end return table.concat(t, "\n") end
  local gpu = {
    getResolution = function() return W, H end,
    getDepth = function() return 8 end,
    setForeground = function() end, setBackground = function() end,
    set = function(x, y, s)
      if y < 1 or y > H then return end
      for i = 1, #s do local xx = x + i - 1; if xx >= 1 and xx <= W then rows[y][xx] = s:sub(i, i) end end
    end,
    fill = function(x, y, w, h, ch)
      for yy = y, y + h - 1 do for xx = x, x + w - 1 do
        if yy >= 1 and yy <= H and xx >= 1 and xx <= W then rows[yy][xx] = ch end
      end end
    end,
  }
  local component = {
    list = function(t) local done = false
      return function() if done or t ~= "gpu" then return nil end done = true return "gpu", "gpu" end end,
    proxy = function() return gpu end,
  }
  local queue = {}
  for _, k in ipairs(opts.keys or {}) do queue[#queue + 1] = k end
  local spare = 0
  local computer = {
    pullSignal = function()
      fx.screens[#fx.screens + 1] = text()
      local s = table.remove(queue, 1)
      if s then return table.unpack(s) end
      spare = spare + 1
      if spare > 8 then error("the key script ran out", 0) end
      return "interrupted"
    end,
  }
  -- NOT "opts.noInternet and nil or {...}" -- that classic and/or
  -- ternary breaks exactly when the "true" branch is nil, which it is
  -- here on purpose (opts.noInternet means absent, not an empty table).
  local internet = nil
  if not opts.noInternet then
    internet = {
      status = function() return opts.cardStatus or { present = true, http = true, enabled = true } end,
      available = function() return not opts.noCard end,
      get = function(url, o)
        local page = fx.pages[url]
        if page == nil then return nil, "404 not found" end
        if type(page) == "function" then return page() end
        return page
      end,
    }
  end
  local env
  local loaded = {}
  local function req(name)
    if name == "component" then return component end
    if name == "computer" then return computer end
    -- The real sandbox's shape (tos/kernel/sandbox.lua): the kernel wrapper
    -- with get() is the `internet` GLOBAL; require("internet") is OpenOS's
    -- library, request/socket/open and no get. This used to hand back the
    -- wrapper here, which is how 1.0.0 shipped calling a nil get.
    if name == "internet" then
      if not internet then error("sandbox: 'compat.internet' needs the internet capability", 2) end
      return { request = function() error("not used") end, socket = function() end, open = function() end }
    end
    if name == "shell.keys" then error("sandbox: module 'shell.keys' is not on the allowed list", 2) end
    if name == "web.render" then
      loaded[name] = loaded[name] or assert(loadfile(ROOT .. "render.lua", "t", env))()
      return loaded[name]
    end
    error("sandbox: module '" .. name .. "' is not on the allowed list", 2)
  end
  env = setmetatable({ require = req, internet = internet }, { __index = _G })
  local main = assert(loadfile(ROOT .. "init.lua", "t", env))()
  fx.ok, fx.err = pcall(main.commands.web, opts.args or {}, function(t) fx.said = (fx.said or "") .. t .. "\n" end)
  function fx.any(pat)
    for _, s in ipairs(fx.screens) do if s:find(pat, 1, true) then return true end end
    return false
  end
  function fx.last() return fx.screens[#fx.screens] end
  return fx
end

print("=== web browser screen Tests ===")
print()

-- ── Help text when no URL is given ──────────────────────────────────
do
  local fx = run({ args = {} })
  test("help text explains usage", fx.said and fx.said:find("web <url>", 1, true) ~= nil)
  test("no screen was ever touched for bare help", #fx.screens == 0)
end

-- ── A page loads and renders ─────────────────────────────────────────
do
  local fx = run({
    pages = { ["http://example.com/"] = "<h1>Hello</h1><p>World.</p>" },
    args = { "http://example.com/" },
    keys = script(F10),
  })
  test("ran without error", fx.ok)
  test("the title bar shows the url", fx.any("example.com"))
  test("the page content reached the screen", fx.any("Hello") and fx.any("World."))
end

-- ── A bare host gets http:// prepended ───────────────────────────────
do
  local fx = run({
    pages = { ["http://example.com/"] = "<p>ok</p>" },
    args = { "example.com/" },
    keys = script(F10),
  })
  test("a scheme-less url still resolves (http:// assumed)", fx.any("ok"))
end

-- ── Following a numbered link ────────────────────────────────────────
do
  local fx = run({
    pages = {
      ["http://a.test/"] = '<p>Go to <a href="http://b.test/">page b</a>.</p>',
      ["http://b.test/"] = "<h1>Page B</h1>",
    },
    args = { "http://a.test/" },
    keys = script(typed("1"), ENTER, F10),
  })
  test("following link 1 loads the linked page", fx.any("Page B"))
end

-- ── Back returns to the previous page ────────────────────────────────
do
  local fx = run({
    pages = {
      ["http://a.test/"] = '<p>Go to <a href="http://b.test/">page b</a>.</p>',
      ["http://b.test/"] = "<h1>Page B</h1>",
    },
    args = { "http://a.test/" },
    keys = script(typed("1"), ENTER, char("b"), F10),
  })
  test("back returns to the page that had the link", fx.any("Go to"))
end

-- ── Opening a new URL from inside the browser (o) ───────────────────
do
  local fx = run({
    pages = {
      ["http://a.test/"] = "<p>start</p>",
      ["http://c.test/"] = "<h1>Page C</h1>",
    },
    args = { "http://a.test/" },
    keys = script(char("o"), typed("http://c.test/"), ENTER, F10),
  })
  test("opening a new url navigates there", fx.any("Page C"))
end

-- ── Scrolling: a long page's later lines reach the screen ──────────
do
  local lots = {}
  for i = 1, 60 do lots[#lots + 1] = "<p>Line " .. i .. " of the document.</p>" end
  local fx = run({
    pages = { ["http://a.test/"] = table.concat(lots) },
    args = { "http://a.test/" },
    keys = script(DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN,
      DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, DOWN, F10),
  })
  test("scrolling down reaches lines past the first screenful", fx.any("Line 20"))
end

-- ── Failure semantics (adapted §7 for no-proxy local browsing) ──────
do
  local fx = run({ args = { "http://a.test/" }, noInternet = true, keys = script(F10) })
  test("no capability grant -> a status message, not a crash", fx.ok)
  test("...naming the real cause", fx.any("not granted"))
end
do
  local fx = run({ args = { "http://a.test/" }, noCard = true,
    cardStatus = { present = false, reason = "no internet card installed" },
    keys = script(F10) })
  test("no internet card -> the kernel's own reason surfaces", fx.any("no internet card installed"))
end
do
  local fx = run({ args = { "http://a.test/" }, pages = {}, keys = script(F10) })
  test("a fetch failure (404 here) shows 'Failed:' with the reason, not a blank page",
    fx.any("Failed:") and fx.any("404"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
