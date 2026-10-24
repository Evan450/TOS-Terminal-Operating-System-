-- ╔══════════════════════════════════════════════════════════╗
-- ║  Test: web — the HTML renderer (browser-spec-draft.md §6)  ║
-- ║                                                            ║
-- ║  render.lua is pure (§6.3: "touches no network, no screen, ║
-- ║  no filesystem"), so all of it tests off-box against       ║
-- ║  fixture HTML, exactly as the spec asks for.                ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua web/browser/test_web.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local here = (arg and arg[0]) or "web/browser/test_web.lua"
local base = here:gsub("[^/\\]*$", "")
local function findChunk(rel, roots)
  for _, root in ipairs(roots) do
    local chunk = loadfile(root .. rel)
    if chunk then return chunk end
  end
  error("cannot find " .. rel)
end

local render = findChunk("render.lua", { base, "web/browser/", "TOS-Extras/web/browser/" })()

-- Joins rendered lines with "\n" so a test can grep across wraps without
-- caring exactly where a line broke.
local function text(html, width)
  return table.concat(render.render(html, width or 80).lines, "\n")
end

print("=== web (HTML renderer) Tests ===")
print()

-- ── Entities (§6.2: "decode to the closest thing the T1/T2 font has") ─
eq("amp", "a & b", render.decodeEntities("a &amp; b"))
eq("lt/gt", "<x>", render.decodeEntities("&lt;x&gt;"))
eq("mdash becomes a plain hyphen, not a glyph the font may lack",
  "a - b", render.decodeEntities("a &mdash; b"))
eq("nbsp becomes a plain space", "a b", render.decodeEntities("a&nbsp;b"))
eq("decimal numeric reference", "A", render.decodeEntities("&#65;"))
eq("hex numeric reference", "A", render.decodeEntities("&#x41;"))
eq("an unknown entity is an honest ? , never a dropped/blank glyph",
  "a ? b", render.decodeEntities("a &zzznosuch; b"))
eq("a numeric reference outside printable ASCII is also ?",
  "?", render.decodeEntities("&#8364;"))   -- Euro sign

-- ── Paragraphs + wrapping ────────────────────────────────────────────
do
  local out = render.render("<p>" .. string.rep("word ", 20):gsub("%s+$", "") .. "</p>", 20)
  test("every wrapped line fits the width", (function()
    for _, l in ipairs(out.lines) do if #l > 19 then return false end end
    return true
  end)())
  test("no word was split across the wrap (none contain a broken 'word')",
    not table.concat(out.lines, " "):find("wor d", 1, true))
end

eq("whitespace inside a paragraph collapses, same as a real browser",
  "a b", text("<p>a   \n  b</p>"))

-- ── Headings ─────────────────────────────────────────────────────────
do
  local out = render.render("<h1>Title</h1><p>Body text.</p>", 80)
  eq("heading text present", "Title", out.lines[1])
  eq("a blank line separates the heading from what follows", "", out.lines[2])
  eq("body follows", "Body text.", out.lines[3])
end

-- ── Lists ────────────────────────────────────────────────────────────
eq("unordered list uses a dash bullet", "- one\n- two",
  text("<ul><li>one</li><li>two</li></ul>"))
eq("ordered list auto-numbers from 1", "1. one\n2. two",
  text("<ol><li>one</li><li>two</li></ol>"))
eq("a fresh list restarts its own counter from 1",
  "1. a\n1. b", text("<ol><li>a</li></ol><ol><li>b</li></ol>"))
test("a nested list indents under its parent item",
  text("<ul><li>A<ul><li>A1</li></ul></li></ul>"):find("  %- A1") ~= nil)

-- ── Links (§6.2: bracketed ordinal + numbered footer) ───────────────
do
  local out = render.render('<p>See <a href="http://example.com/x">the docs</a> here.</p>', 80)
  eq("exactly one link collected", 1, #out.links)
  eq("link url", "http://example.com/x", out.links[1].url)
  eq("link text is ONLY the anchor's own words, not the whole paragraph",
    "the docs", out.links[1].text)
  test("the inline marker [1] appears in the body text",
    table.concat(out.lines, " "):find("%[1%]") ~= nil)
  test("the footer references the same url",
    table.concat(out.lines, " "):find("http://example.com/x", 1, true) ~= nil)
end
eq("a link with no text falls back to its own url as the label",
  "http://x.test", render.render('<a href="http://x.test"></a>', 80).links[1].text)
eq("an in-page anchor (#fragment) is not collected as a link",
  0, #render.render('<a href="#top">top</a>', 80).links)
eq("a javascript: href is not collected as a link",
  0, #render.render('<a href="javascript:alert(1)">x</a>', 80).links)
do
  -- The bug this guards against: the link-text capture used to concat
  -- the WHOLE accumulated paragraph buffer, not just what was typed
  -- between <a> and </a> -- so a link near the end of a long sentence
  -- came out holding the entire sentence as its "text".
  local out = render.render(
    '<p>A long sentence leads up to <a href="http://x.test">a short link</a>.</p>', 80)
  eq("link text does not include the text BEFORE the anchor opened",
    "a short link", out.links[1].text)
end

-- ── <pre> (§6.2: never wraps, scrolls sideways instead) ──────────────
do
  local out = render.render("<pre>line one\n   two  spaced   out</pre>", 10)
  eq("pre keeps its own line breaks", "line one", out.lines[1])
  test("pre is not word-wrapped even past the width",
    out.lines[2]:find("two  spaced   out", 1, true) ~= nil)
  eq("internal whitespace in <pre> is preserved exactly, unlike prose",
    "   two  spaced   out", out.lines[2])
end

-- ── <br> forces a line break without starting a new block ───────────
eq("br breaks the line", "one\ntwo", text("<p>one<br>two</p>"))

-- ── Skipped elements never reach the output ──────────────────────────
do
  local out = text("<head><title>T</title><style>.c{color:red}</style></head>"
    .. "<body><script>alert(1)</script><p>visible</p></body>")
  test("title is not rendered", not out:find("T", 1, true))
  test("style rules are not rendered", not out:find("color", 1, true))
  test("script contents are not rendered", not out:find("alert", 1, true))
  test("the real body text still comes through", out:find("visible", 1, true) ~= nil)
end

-- ── Inline/transparent tags pass their text through unchanged ───────
eq("b/i/em/strong/span are transparent to their surrounding block",
  "bold italic span", text("<p><b>bold</b> <i>italic</i> <span>span</span></p>"))

-- ── Tolerance: real pages are not well-formed ────────────────────────
test("an unterminated tag at EOF degrades to plain text, not a crash",
  pcall(render.render, "<p>hello <b>world", 40))
test("a tag with no closing '>' at EOF does not crash",
  pcall(render.render, "<p>hello <b", 40))
eq("a comment is removed entirely", "before after",
  text("<p>before <!-- a comment --> after</p>"))
eq("a DOCTYPE declaration is removed", "text",
  text("<!DOCTYPE html><p>text</p>"))

-- ── Safety on degenerate input ───────────────────────────────────────
do
  local ok1, out1 = pcall(render.render, "", 80)
  test("empty input does not raise", ok1)
  eq("...and produces no lines", 0, ok1 and #out1.lines)
  local ok2 = pcall(render.render, nil, 80)
  test("nil html does not raise", ok2)
  local ok3 = pcall(render.render, "<p>x</p>", 0)
  test("a width of 0 does not raise (clamped to a sane minimum)", ok3)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
