-- TOS ADDITION (not an upstream LuaMinify file): hoist a string literal
-- that is repeated often enough in one file into a single module-level
-- local, so N occurrences of "a long error message" cost one copy of the
-- text plus N short variable references instead of N copies of the text.
--
-- SAFETY. A Lua string literal and a local variable holding that same
-- string are interchangeable in EVERY expression position -- the
-- language does not distinguish "this came from source text" from "this
-- came from a variable" at runtime, so replacing one with the other can
-- never change behaviour, independent of where in the grammar it sits:
-- an argument, a table value, a condition, an index, a require() call, a
-- load() chunk name. What is NOT safe to touch, and this never touches,
-- are the two places a string-shaped thing appears in the AST without
-- being a full expression node at all:
--   - `{foo = 1}` (ConstructorExpr "KeyString") stores the key as a bare
--     Lua string in `entry.Key`, not an AST node -- there is nothing
--     there with an .AstType for the walker below to find.
--   - `f"str"` (StringCallExpr sugar) stores its argument as a raw
--     token in `Arguments[1]`, again with no .AstType.
-- The walker below only ever treats a table carrying `.AstType` as a
-- node eligible for recursion or replacement, so both cases are skipped
-- by construction, with no special-casing needed to get that right.
--
-- Runs between parsing and formatting: build/minify_vars.lua calls
-- dedupStrings(ast) on the freshly-parsed AST, then hands the (possibly
-- mutated) AST to FormatMini as usual. The new local is created via the
-- top scope's own CreateLocal, with its .References set to the real
-- occurrence count, so MinifyLocals' descending-frequency allocator (see
-- Scope.lua) gives it a short name on the same footing as everything
-- else in the file -- this file adds no naming logic of its own.

local MIN_LEN = 8    -- quoted length (i.e. content length >= 6)
local MIN_COUNT = 3  -- not worth a local for one or two uses

--- Generic AST walk. `visit(node)` is called for every node this walker
--- finds (depth-first, parent before children); if it returns a
--- non-nil replacement, that replacement takes the node's place in its
--- parent and is NOT itself recursed into (it is assumed already-final,
--- which is true for the VarExpr this module ever substitutes).
local function walk(root, visit)
  -- Guard against reference cycles: every AST node that names a
  -- variable (VarExpr, a LocalStatement's LocalList entries, ...) holds
  -- a `Variable` object, and that object's own `.Scope` field points
  -- BACK to the Scope that owns it -- which holds that same Variable in
  -- its `.Locals` list. Scope.Parent/Children link scopes to each other
  -- the same way. None of that is "child syntax" to walk into, and
  -- without a seen-set this walker recurses through the cycle forever
  -- (hit immediately on anything with a single VarExpr in it).
  local seen = {}
  local function walkTable(t)
    if seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
      if type(v) == "table" then
        if v.AstType then
          local replacement = visit(v)
          if replacement then
            t[k] = replacement
          else
            walkTable(v)
          end
        else
          walkTable(v)
        end
      end
    end
  end
  walkTable(root)
end

--- Mutates `ast` in place. Returns the number of distinct strings hoisted
--- and the number of occurrences replaced, for the caller to log.
local function dedupStrings(ast)
  -- Pass 1: count. Keyed by the literal's exact source text (quotes and
  -- all), so two spellings of the same value (e.g. different quote
  -- characters) are never conflated -- a smaller dedup, never a wrong one.
  local counts = {}
  walk(ast, function(node)
    if node.AstType == "StringExpr" then
      local text = node.Value.Data
      counts[text] = (counts[text] or 0) + 1
    end
    return nil -- never replace during the counting pass
  end)

  local qualifies = {}
  for text, n in pairs(counts) do
    if n >= MIN_COUNT and #text >= MIN_LEN then
      qualifies[text] = true
    end
  end
  if not next(qualifies) then return 0, 0 end

  -- Pass 2: replace. One shared Variable per qualifying string, all of
  -- them created up front in SORTED order, and only looked up during the
  -- walk. They used to be created on first sight, which sounds ordered
  -- and is not: walk() recurses with pairs(), and Lua 5.4 seeds its
  -- string hash per process, so first sight changed from run to run.
  -- Creation order is declaration order, and Scope.lua's MinifyLocals
  -- breaks a tie in use count by declaration order, so two strings used
  -- equally often swapped names between builds: the release came out
  -- different on two runs over the same source (6 of 144 files), and no
  -- built file could be compared against an earlier one byte for byte.
  local vars = {}        -- text -> Variable
  local declOrder = {}   -- text, sorted
  for text in pairs(qualifies) do declOrder[#declOrder + 1] = text end
  table.sort(declOrder)
  for i, text in ipairs(declOrder) do
    local var = ast.Scope:CreateLocal("_tos_dedup_" .. tostring(i))
    var.References = counts[text]
    vars[text] = var
  end
  local replaced = 0
  walk(ast, function(node)
    if node.AstType ~= "StringExpr" then return nil end
    local var = vars[node.Value.Data]
    if not var then return nil end
    replaced = replaced + 1
    return { AstType = "VarExpr", Name = var.Name, Variable = var }
  end)

  -- Splice `local a,b,c = "x","y","z"` as the FIRST statement(s) of the
  -- top-level body -- lexically before every use, including inside
  -- nested functions (an upvalue, exactly like any other module-level
  -- local declared at the top of a file in this codebase already).
  if #declOrder > 0 then
    local localList, initList = {}, {}
    for i, text in ipairs(declOrder) do
      localList[i] = vars[text]
      initList[i] = { AstType = "StringExpr", Value = { Data = text } }
    end
    local declStatement = {
      AstType = "LocalStatement",
      LocalList = localList,
      InitList = initList,
      Tokens = {},
    }
    table.insert(ast.Body, 1, declStatement)
  end

  return #declOrder, replaced
end

return dedupStrings
