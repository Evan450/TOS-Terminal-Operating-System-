#!/usr/bin/env lua
-- ╔═════════════════════════════════════════════════╗
-- ║  TOS Build Tool — Local-variable minifier         ║
-- ║                                                    ║
-- ║  A thin driver over a vendored, patched copy of    ║
-- ║  stravant/LuaMinify (build/vendor/luaminify/) that  ║
-- ║  shortens LOCAL variable and function-parameter     ║
-- ║  names to the minimum that is still unambiguous.    ║
-- ║  Never touches globals, table fields, or string      ║
-- ║  literals — those are never safe to rename and the   ║
-- ║  vendored Scope.lua only ever renames `self.Locals`. ║
-- ║                                                      ║
-- ║  WHY VENDORED AND PATCHED, NOT USED AS-IS:          ║
-- ║  Upstream's parser has no support for Lua 5.3's      ║
-- ║  bitwise/shift operators (& | ~ << >>) or floor      ║
-- ║  division (//) — it hard-errors on them — and        ║
-- ║  kernel/sha256.lua alone uses all five. TOS requires  ║
-- ║  Lua 5.3+ (5.2 is rejected at boot), so this is not   ║
-- ║  an edge case. See build/vendor/luaminify/README.md   ║
-- ║  for the exact patch and why each piece is safe.      ║
-- ║                                                      ║
-- ║  Usage (as a library):                               ║
-- ║    local mv = require("minify_vars")                 ║
-- ║    local out, err = mv.minify(src, chunkname)        ║
-- ║                                                      ║
-- ║  Usage (CLI, for ad-hoc checks):                     ║
-- ║    lua build/minify_vars.lua <file.lua>              ║
-- ╚═════════════════════════════════════════════════╝

local M = {}

local HERE = (...) or arg and arg[0]
local VENDOR_DIR
do
  -- Resolve the vendor directory relative to THIS file, not the caller's
  -- cwd, so strip.lua can require() this from anywhere.
  local src = debug.getinfo(1, "S").source
  local path = src:match("^@(.*)$") or src
  local dir = path:gsub("[^/\\]*$", "")
  if dir == "" then dir = "." end
  VENDOR_DIR = dir .. "vendor/luaminify"
end

local function loadVendored(name)
  local path = VENDOR_DIR .. "/" .. name .. ".lua"
  local chunk, err = loadfile(path)
  if not chunk then return nil, "cannot load " .. path .. ": " .. tostring(err) end
  -- The vendored files require() each other by bare name ('Util',
  -- 'Scope', ...) with no package prefix, so they must be reachable on
  -- package.path while they load. Scoped to just this call rather than
  -- mutated globally for longer than necessary.
  local savedPath = package.path
  package.path = VENDOR_DIR .. "/?.lua;" .. package.path
  local ok, mod = pcall(chunk)
  package.path = savedPath
  if not ok then return nil, "error loading " .. name .. ": " .. tostring(mod) end
  return mod
end

local parserMod, parserErr
local formatMod, formatErr
local dedupMod, dedupErr

local function ensureLoaded()
  if not parserMod then parserMod, parserErr = loadVendored("ParseLua") end
  if not formatMod then formatMod, formatErr = loadVendored("FormatMini") end
  if not dedupMod then dedupMod, dedupErr = loadVendored("DedupStrings") end
  return parserMod and formatMod and dedupMod, parserErr or formatErr or dedupErr
end

--- How many of each kind of node a parsed program has: `BinopExpr:-`,
--- `CallStatement`, `MemberExpr::` and so on, as one sorted string. Two
--- programs with the same shape give the same string whatever their
--- local names are. Scope and Variable links are not syntax and are not
--- followed; a seen-set keeps any other back-reference from looping.
local function shapeOf(ast)
  local counts, seen = {}, {}
  local SKIP = { Scope = true, Variable = true, Tokens = true, Parent = true }
  local function visit(t)
    if seen[t] then return end
    seen[t] = true
    if t.AstType then
      local key = t.AstType .. (t.Op and (":" .. t.Op) or "")
        .. (t.Indexer and (":" .. t.Indexer) or "")
      counts[key] = (counts[key] or 0) + 1
    end
    for k, v in pairs(t) do
      if type(v) == "table" and not SKIP[k] then visit(v) end
    end
  end
  visit(ast)
  local keys = {}
  for k, n in pairs(counts) do keys[#keys + 1] = k .. "=" .. n end
  table.sort(keys)
  return table.concat(keys, " "), counts
end

--- Minify the local-variable names in `src`, and hoist any string literal
--- repeated often enough in this one file into a shared local (see
--- DedupStrings.lua for exactly why that's always safe). Returns the
--- minified source on success, or nil + an error message on failure —
--- NEVER a partial or best-effort result. `chunkname` is used only for
--- parser error messages (it is not written into the output).
function M.minify(src, chunkname)
  local ok, err = ensureLoaded()
  if not ok then return nil, err end

  local pOk, ast = parserMod.ParseLua(src)
  if not pOk then
    return nil, "parse error in " .. tostring(chunkname) .. ": " .. tostring(ast)
  end

  -- Mutates ast in place; a failure here is a bug in the dedup pass
  -- itself (it never touches syntax, only which Variable a VarExpr
  -- points at), so it is not allowed to fail silently into a skip.
  local dOk, dErr = pcall(dedupMod, ast)
  if not dOk then
    return nil, "string-dedup error in " .. tostring(chunkname) .. ": " .. tostring(dErr)
  end

  local before, beforeCounts = shapeOf(ast)
  local fOk, out = pcall(formatMod, ast)
  if not fOk then
    return nil, "format error in " .. tostring(chunkname) .. ": " .. tostring(out)
  end
  if type(out) ~= "string" or out == "" then
    return nil, "formatter produced no output for " .. tostring(chunkname)
  end

  --! ROUND TRIP: the output must parse back to a program of the same
  --! shape. load() cannot be the only gate, because the formatter's
  --! mistakes compile: it joined `f()` and `;(g)()` into `f()(g)()`, a
  --! call on f's result, and every release from 2026-10-17 shipped six of
  --! those in the kernel's and the shell's focus switching ("attempt to
  --! call a boolean value"); it made `a - -b` into `a--b`, a comment; it
  --! made `t[ [=[k]=] ]` into a call. Each of those changes how many of
  --! some kind of node the program has -- a statement fewer, a call more
  --! -- so counting them on both sides catches the whole class, including
  --! the joins nobody has found yet. One more parse per file.
  local rOk, ast2 = parserMod.ParseLua(out)
  if not rOk then
    return nil, "minified output of " .. tostring(chunkname) .. " does not parse: " .. tostring(ast2)
  end
  local after, afterCounts = shapeOf(ast2)
  if after ~= before then
    local diffs = {}
    for k, n in pairs(beforeCounts) do
      if (afterCounts[k] or 0) ~= n then diffs[#diffs + 1] = k .. " " .. n .. "->" .. (afterCounts[k] or 0) end
    end
    for k, n in pairs(afterCounts) do
      if beforeCounts[k] == nil then diffs[#diffs + 1] = k .. " 0->" .. n end
    end
    table.sort(diffs)
    return nil, "minified output of " .. tostring(chunkname) .. " is a different program ("
      .. table.concat(diffs, ", ") .. ")"
  end
  return out
end

-- ============================================================
-- CLI: ad-hoc single-file check, not used by the release build
-- ============================================================
-- Exact basename match, not a suffix pattern: arg[0] is whatever script
-- actually started this Lua process, and test_minify_vars.lua (which
-- requires this module as a library) ends in "minify_vars.lua" too --
-- a suffix match like strip.lua's own arg[0]:match("strip%.lua$") would
-- have made loading this from that test run the CLI path instead.
if arg and arg[0] and arg[0]:match("([^/\\]+)$") == "minify_vars.lua" then
  local path = arg[1]
  if not path then
    io.stderr:write("Usage: lua build/minify_vars.lua <file.lua>\n")
    os.exit(1)
  end
  local h = io.open(path, "rb")
  if not h then
    io.stderr:write("cannot open " .. path .. "\n")
    os.exit(1)
  end
  local src = h:read("*a"); h:close()
  local out, err = M.minify(src, path)
  if not out then
    io.stderr:write(tostring(err) .. "\n")
    os.exit(1)
  end
  io.write(out)
end

return M
