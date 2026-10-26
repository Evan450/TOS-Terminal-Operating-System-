-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the installer stops at the first failed write║
-- ║                                                                ║
-- ║  install.lua's copyFileChunked was                             ║
-- ║    pcall(function() oh:write(chunk) end)                       ║
-- ║  OpenOS answers a full disk with nil, "not enough space"; it   ║
-- ║  does not raise. So the loop wrote on, chunk after chunk, and  ║
-- ║  only verifyCopy's size check noticed afterwards (AUDIT 1;     ║
-- ║  fs.writeAll's twin in AUDIT 5). The last buffered block is    ║
-- ║  written by the flush, and OpenOS's buffer:close() drops what   ║
-- ║  that flush answers, so the copy flushes itself and checks it. ║
-- ║                                                                ║
-- ║  The function is LIFTED from install.lua and run against        ║
-- ║  handles shaped like OpenOS's buffer (Reference/OpenOS          ║
-- ║  lib/buffer.lua): write -> self or nil, reason; flush -> self   ║
-- ║  or nil, reason; close -> whatever the stream says, nil here.   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_install_copy_write.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local h = assert(io.open("install.lua", "rb"))
local src = h:read("a"):gsub("\r\n", "\n"); h:close()
local from = src:find("local function copyFileChunked", 1, true)
local to = from and src:find("\nend\n", from, true)
test("found copyFileChunked in install.lua", from ~= nil and to ~= nil)
if not (from and to) then
  print(string.format("Results: %d passed, %d failed", passed, failed))
  print("*** TESTS FAILED ***"); os.exit(1)
end

-- A source file of `n` 4 KB chunks, and an OpenOS-shaped output handle.
-- `failAt` = the write call that answers nil, "not enough space";
-- `raiseAt` = the write call that raises; `flushFails` = flush answers nil.
local function run(n, opts)
  opts = opts or {}
  local writes, flushed, closed = 0, false, false
  local written = {}
  local out = {}
  function out.write(self, s)
    writes = writes + 1
    if opts.raiseAt == writes then error("disk on fire") end
    if opts.failAt and writes >= opts.failAt then return nil, "not enough space" end
    written[#written + 1] = s
    return self
  end
  if not opts.noFlush then
    function out.flush(self)
      flushed = true
      if opts.flushFails then return nil, "not enough space" end
      return self
    end
  end
  function out.close() closed = true; return nil end   -- a stream close returns nothing
  local reads = 0
  local inp = {
    read = function() reads = reads + 1; if reads <= n then return string.rep("x", 4096) end end,
    close = function() end,
  }
  local env = {
    io = { open = function(_, mode) if mode == "r" then return inp end; return out end },
    pcall = pcall, tostring = tostring,
  }
  local chunk = assert(load(src:sub(from, to + 4) .. "\nreturn copyFileChunked", "=install.lua", "t", env))()
  local ok, err = chunk("/src", "/dst")
  return { ok = ok, err = err, writes = writes, flushed = flushed, closed = closed, n = #written }
end

print("=== copyFileChunked: a failed write is a failure ===")
print()

local r = run(3)
test("a good copy succeeds", r.ok == true, r.err)
test("...writes every chunk", r.n == 3, r.n)
test("...flushes before it closes", r.flushed and r.closed)
test("...and does not read close()'s nil as a failure", r.ok == true)

r = run(5, { failAt = 2 })
test("a write that answers nil, 'not enough space' fails the copy", r.ok == false)
test("...saying why", tostring(r.err):find("not enough space", 1, true) ~= nil, r.err)
test("...and stops writing there", r.writes == 2, r.writes)
test("...and still closes the file", r.closed)

r = run(3, { raiseAt = 1 })
test("a write that raises fails the copy", r.ok == false and tostring(r.err):find("disk on fire", 1, true) ~= nil, r.err)

r = run(2, { flushFails = true })
test("a flush that answers nil fails the copy", r.ok == false, r.err)
test("...saying why", tostring(r.err):find("not enough space", 1, true) ~= nil, r.err)

r = run(2, { noFlush = true })
test("a handle with no flush still copies", r.ok == true and r.n == 2, r.err)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
