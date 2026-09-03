#!/usr/bin/env lua
-- ╔═════════════════════════════════════════════════╗
-- ║  TOS Build Tool — Comment Stripper                                 ║
-- ║                                                                    ║
-- ║  Takes the heavily-commented source tree (the "dev" copy) and      ║
-- ║  emits a parallel tree with comments stripped (the "dist" copy).   ║
-- ║                                                                    ║
-- ║  Why two copies:                                                   ║
-- ║    • The source tree's comments are doing real work — #SEC blocks  ║
-- ║      explain attack mitigations, design decisions, etc. They       ║
-- ║      should never be lost.                                         ║
-- ║    • The deployed tree pays for those comments in RAM and disk     ║
-- ║      pressure on tight machines, and the BIOS specifically is      ║
-- ║      already over the 4 KiB EEPROM limit (5046 bytes; ~1700 of     ║
-- ║      that is comments).                                            ║
-- ║                                                                    ║
-- ║  Marker convention:                                                ║
-- ║    --!  Preserve this comment in dist. Use it for:                 ║
-- ║          • #SEC notes that document an active mitigation           ║
-- ║          • Cross-file invariants future-you will need              ║
-- ║          • License / attribution headers                           ║
-- ║    --   Strip in dist. Use this for ordinary explanation,          ║
-- ║          rationale, dev notes, TODOs.                              ║
-- ║                                                                    ║
-- ║  Block comments work the same way — `--[[!` keeps, `--[[` strips.  ║
-- ║                                                                    ║
-- ║  Usage:                                                            ║
-- ║    lua build/strip.lua <src-dir> <dist-dir>                        ║
-- ║                              [--minify]                            ║
-- ║                              [--exclude PAT]...                    ║
-- ║                                                                    ║
-- ║    --minify    Additionally collapses runs of blank lines, useful  ║
-- ║                for the BIOS where every byte counts. Off by        ║
-- ║                default because it shifts line numbers in stack     ║
-- ║                traces.                                             ║
-- ║                                                                    ║
-- ║    --exclude   Skip any source path whose relative-to-src form     ║
-- ║                contains this substring. Repeatable. Use to drop    ║
-- ║                dev-only trees (build/, tests, .claude, etc.)       ║
-- ║                from a Release build.                               ║
-- ║                                                                    ║
-- ║  After walking, if `<dst>/tos/system_manifest.lua` exists, the     ║
-- ║  driver re-reads it and rewrites it with any entries dropped       ║
-- ║  whose target path no longer exists in the dist tree. That keeps   ║
-- ║  the Release manifest in sync with what was actually emitted —     ║
-- ║  e.g. excluding /usr/modules/foo from the build automatically      ║
-- ║  drops the foo entry from the manifest too. The Dev tree's         ║
-- ║  manifest is never touched.                                        ║
-- ║                                                                    ║
-- ║  Strings are preserved verbatim, including their content. A `--`   ║
-- ║  inside a string literal is NOT a comment and is left alone.       ║
-- ╚═════════════════════════════════════════════════╝

local M = {}

-- ============================================================
-- Tokenizer
-- ============================================================
-- Walks a source string, emitting token records:
--   { type = "code"|"line_comment"|"block_comment"|"string"|"long_string",
--     text = <verbatim source>, marked = bool (comments only) }
--
-- The tokenizer is byte-oriented and handles:
--   • Single- and double-quoted strings with backslash escapes
--   • Long strings/comments with any number of `=` signs
--   • Line comments (-- to end-of-line)
--   • Block comments (--[[ ... ]])
--   • The `--!` and `--[[!` marker variants
--
-- It is NOT a Lua parser — it doesn't care about syntactic validity,
-- only about partitioning bytes into "this is a comment" vs "this
-- isn't". That's enough for what we need.

function M.tokenize(src)
  local tokens = {}
  local i, n = 1, #src

  -- Helper: append a token. Coalesces consecutive code tokens so the
  -- emitter doesn't have to.
  local function emit(kind, text, marked)
    if kind == "code" and tokens[#tokens] and tokens[#tokens].type == "code" then
      tokens[#tokens].text = tokens[#tokens].text .. text
    else
      tokens[#tokens + 1] = { type = kind, text = text, marked = marked }
    end
  end

  while i <= n do
    local c  = src:sub(i, i)
    local c2 = src:sub(i, i + 1)

    -- ── Line comment / block comment ───────────────────────
    if c2 == "--" then
      -- Distinguish block from line. `--[==[` opens a long comment.
      local afterDash = i + 2
      if src:sub(afterDash, afterDash) == "[" then
        local eqs = src:match("^=*", afterDash + 1) or ""
        if src:sub(afterDash + 1 + #eqs, afterDash + 1 + #eqs) == "[" then
          -- Block comment. Marker is `--[[!` (the `!` directly after the
          -- second `[`, before any text).
          local close = "]" .. eqs .. "]"
          local startContent = afterDash + 2 + #eqs
          local marked = src:sub(startContent, startContent) == "!"
          local closeAt = src:find(close, startContent, true)
          -- #SEC M-13 — an unterminated block comment must HARD ERROR, not
          -- silently consume to EOF. Producing a truncated release is
          -- especially dangerous here: this tool guards the `--!`/`#SEC`
          -- security invariants, and a swallowed tail could drop a guard.
          if not closeAt then
            local lineNo = select(2, src:sub(1, i):gsub("\n", "")) + 1
            error(string.format(
              "strip: unterminated block comment (opened at line %d)", lineNo), 0)
          end
          local endIdx = closeAt + #close - 1
          emit("block_comment", src:sub(i, endIdx), marked)
          i = endIdx + 1
          goto cont
        end
      end
      -- Line comment.
      local marked = src:sub(afterDash, afterDash) == "!"
      local nl = src:find("\n", afterDash, true)
      local endIdx = nl and (nl - 1) or n
      emit("line_comment", src:sub(i, endIdx), marked)
      i = endIdx + 1
      goto cont
    end

    -- ── Long string ────────────────────────────────────────
    -- `[[...]]` or `[=[...]=]` etc. We deliberately accept this
    -- everywhere even though Lua only allows it as an expression —
    -- it's simpler than tracking grammatical context, and the worst
    -- case is we keep a non-string verbatim, which is harmless.
    if c == "[" then
      local eqs = src:match("^=*", i + 1) or ""
      if src:sub(i + 1 + #eqs, i + 1 + #eqs) == "[" then
        local close = "]" .. eqs .. "]"
        local startContent = i + 2 + #eqs
        local closeAt = src:find(close, startContent, true)
        -- #SEC M-13 — unterminated long string: hard error rather than
        -- swallow to EOF and emit a truncated release.
        if not closeAt then
          local lineNo = select(2, src:sub(1, i):gsub("\n", "")) + 1
          error(string.format(
            "strip: unterminated long string (opened at line %d)", lineNo), 0)
        end
        local endIdx = closeAt + #close - 1
        emit("long_string", src:sub(i, endIdx))
        i = endIdx + 1
        goto cont
      end
    end

    -- ── Quoted string ──────────────────────────────────────
    if c == '"' or c == "'" then
      local quote = c
      local j = i + 1
      while j <= n do
        local cc = src:sub(j, j)
        if cc == "\\" then
          j = j + 2  -- skip the escape and the next byte
        elseif cc == quote then
          j = j + 1; break
        elseif cc == "\n" then
          -- Unterminated single-line string. Lua would error; we just
          -- bail out of the string and let the next pass treat the rest
          -- as code. Keeps the stripper from consuming the rest of the
          -- file on a malformed source.
          break
        else
          j = j + 1
        end
      end
      emit("string", src:sub(i, j - 1))
      i = j
      goto cont
    end

    -- ── Plain code byte ────────────────────────────────────
    emit("code", c)
    i = i + 1

    ::cont::
  end

  return tokens
end

-- ============================================================
-- Emit
-- ============================================================
-- Walks the token list and produces the stripped output. Preserves
-- newlines from inside stripped comments so line numbers shift as
-- little as possible (a stripped `-- ordinary` becomes empty but the
-- following newline is still there).

function M.emit(tokens, opts)
  opts = opts or {}
  local out = {}
  for _, tok in ipairs(tokens) do
    if tok.type == "line_comment" and not tok.marked then
      -- Drop the comment text; the trailing newline (if any) is in
      -- the next token (a "code" token starting with `\n`) so we
      -- naturally preserve line count.
    elseif tok.type == "block_comment" and not tok.marked then
      -- Replace with whatever newlines the comment spanned, so
      -- multi-line block comments don't collapse the file.
      local nlCount = select(2, tok.text:gsub("\n", ""))
      out[#out + 1] = string.rep("\n", nlCount)
    else
      out[#out + 1] = tok.text
    end
  end

  local result = table.concat(out)

  -- Optional minify: collapse runs of 2+ blank lines into one. Off by
  -- default because it shifts line numbers in stack traces; the BIOS
  -- (where every byte matters) explicitly opts in.
  if opts.minify then
    -- Normalise line endings FIRST. This repo is developed on Windows and
    -- checks out CRLF, which broke minify silently in two ways: every
    -- collapse pattern below is written against "\n", so on CRLF input
    -- NONE of them matched (blank lines were never collapsed), and every
    -- surviving line carried a "\r" that was then burned onto the EEPROM.
    -- The BIOS image was shipping ~150 bytes of pure carriage returns
    -- against a hard 4 KiB budget. Lua accepts \n, \r\n and \r equally,
    -- so emitting LF-only is purely a saving.
    result = result:gsub("\r\n", "\n"):gsub("\r", "\n")
    -- Strip trailing whitespace on each line (post-comment lines are
    -- often just "      " left over from the indented code that had
    -- a trailing comment).
    result = result:gsub("[ \t]+\n", "\n")
    -- Collapse runs of blank lines.
    result = result:gsub("\n\n\n+", "\n\n")
    -- Strip leading newlines from the file.
    result = result:gsub("^\n+", "")
  end

  return result
end

-- ============================================================
-- Convenience: strip a single source string
-- ============================================================

function M.strip(src, opts)
  return M.emit(M.tokenize(src), opts)
end

-- ============================================================
-- File-tree driver (only runs when invoked as a script, not when
-- required as a library)
-- ============================================================

if arg and arg[0] and arg[0]:match("strip%.lua$") then
  local lfs_ok, lfs = pcall(require, "lfs")  -- LuaFileSystem if available

  -- OpenOS path: use the `filesystem` module. Standalone path: use lfs.
  -- Detect which one we're in by attempting to require both.
  local fs_ok, fs = pcall(require, "filesystem")

  local function isDir(path)
    if fs_ok then return fs.isDirectory(path) end
    if lfs_ok then return lfs.attributes(path, "mode") == "directory" end
    error("need either openos filesystem or lfs to traverse directories")
  end

  local function listDir(path)
    if fs_ok then
      local out = {}
      for name in fs.list(path) do out[#out + 1] = name:gsub("/$", "") end
      return out
    end
    if lfs_ok then
      local out = {}
      for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then out[#out + 1] = name end
      end
      return out
    end
    error("need either openos filesystem or lfs to traverse directories")
  end

  local function makeDir(path)
    if fs_ok then return fs.makeDirectory(path) end
    if lfs_ok then return lfs.mkdir(path) end
    os.execute("mkdir -p " .. path)
  end

  local function readAll(path)
    local h = io.open(path, "rb")
    if not h then return nil end
    local s = h:read("*a")
    h:close()
    return s
  end

  local function writeAll(path, content)
    local h = io.open(path, "wb")
    if not h then return false end
    h:write(content)
    h:close()
    return true
  end

  local function joinPath(a, b)
    if a:sub(-1) == "/" then return a .. b end
    return a .. "/" .. b
  end

  -- Parse args. Positional: src, dst. Optional: --minify, --exclude PAT.
  local src, dst
  local minify = false
  local excludes = {}
  local i_arg = 1
  while i_arg <= #arg do
    local v = arg[i_arg]
    if v == "--minify" then
      minify = true
    elseif v == "--exclude" then
      i_arg = i_arg + 1
      local pat = arg[i_arg]
      if not pat then
        io.stderr:write("--exclude requires a pattern argument\n"); os.exit(1)
      end
      excludes[#excludes + 1] = pat
    elseif not src then src = v
    elseif not dst then dst = v
    else
      io.stderr:write("Unexpected argument: " .. tostring(v) .. "\n"); os.exit(1)
    end
    i_arg = i_arg + 1
  end

  if not src or not dst then
    io.stderr:write("Usage: lua strip.lua <src-dir> <dist-dir> [--minify] [--exclude PAT]...\n")
    os.exit(1)
  end

  -- Normalize: strip a single trailing slash so excludes match cleanly.
  local function noTrailSlash(p) return (p:gsub("/+$", "")) end
  src = noTrailSlash(src)
  dst = noTrailSlash(dst)

  local function isExcluded(srcPath)
    --! Exclusion is substring-matched against the path *relative to src*,
    --! prefixed with `/` so patterns like "/build/" match a directory boundary
    --! without hitting "rebuild" or similar substrings elsewhere. We also
    --! match against rel with a trailing slash appended so a pattern like
    --! "/build/" matches the directory `/build` itself (otherwise we'd
    --! create an empty dir in dst before excluding its children).
    local rel = srcPath:sub(#src + 1)
    if rel == "" then rel = "/" end
    local relSlash = rel .. "/"
    for _, pat in ipairs(excludes) do
      if rel:find(pat, 1, true) or relSlash:find(pat, 1, true) then
        return true
      end
    end
    return false
  end

  local processed, total, skipped = 0, 0, 0

  local function walk(srcPath, dstPath)
    if isExcluded(srcPath) then
      skipped = skipped + 1
      io.write(string.format("  SKIP  %s\n", srcPath))
      return
    end
    if isDir(srcPath) then
      makeDir(dstPath)
      for _, name in ipairs(listDir(srcPath)) do
        walk(joinPath(srcPath, name), joinPath(dstPath, name))
      end
    elseif srcPath:sub(-4) == ".lua" then
      total = total + 1
      local content = readAll(srcPath)
      if content then
        local stripped = M.strip(content, { minify = minify })
        if writeAll(dstPath, stripped) then
          processed = processed + 1
          local saved = #content - #stripped
          io.write(string.format("  %s  -%dB\n", dstPath, saved))
        end
      end
    else
      -- Non-Lua file: copy as-is. The deploy chain still needs the
      -- non-Lua bits (manifests, configs, themes) intact.
      local content = readAll(srcPath)
      if content then writeAll(dstPath, content) end
    end
  end

  walk(src, dst)
  io.write(string.format("\nStripped %d/%d Lua files (skipped %d entries)\n", processed, total, skipped))

  -- ── Manifest auto-prune ──────────────────────────────────
  --! After the walk, if a system_manifest.lua landed in the dist tree, drop
  --! any entries whose target path doesn't exist on disk in the dist. This
  --! keeps the Release manifest honest: excluding /usr/modules/foo from the
  --! build (via --exclude) automatically prunes its manifest entry, so the
  --! manifest-completeness test won't fail in the deployed image.
  local manifestPath = dst .. "/tos/system_manifest.lua"
  local manifestSrc = readAll(manifestPath)
  if manifestSrc then
    local function distHas(ocPath)
      --! ocPath is the absolute path on the OC filesystem (e.g. /tos/foo.lua).
      --! Source/dist trees mirror that layout, so the dist file lives at dst..ocPath.
      local h = io.open(dst .. ocPath, "rb")
      if h then h:close(); return true end
      return false
    end
    local kept, dropped = {}, {}
    --! Match `{ path = "/...", critical = ... }` entries line-by-line. The
    --! manifest is a flat return-table of these; this is intentionally a
    --! line-level filter rather than a Lua parser to keep the build tool
    --! standalone (no dependency on a Lua interpreter for parsing).
    for line in manifestSrc:gmatch("([^\n]*)\n?") do
      local p = line:match('path%s*=%s*"([^"]+)"')
      if p and not distHas(p) then
        dropped[#dropped + 1] = p
      else
        kept[#kept + 1] = line
      end
    end
    if #dropped > 0 then
      writeAll(manifestPath, table.concat(kept, "\n"))
      io.write(string.format("\nPruned %d manifest entr%s with no file in dist:\n",
        #dropped, #dropped == 1 and "y" or "ies"))
      for _, p in ipairs(dropped) do io.write("  - " .. p .. "\n") end
    end
  end
end

return M
