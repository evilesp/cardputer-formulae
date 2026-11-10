#!lua
-- jslang: JavaScript (Node.js style) for this device, translated to Lua and run by the Lua of the firmware. There: let/const/var, closures, classes (extends, super,
-- getters, static, private #x), destructuring, spread, arrow functions, template strings, generators, async/await with promises and timers, exceptions, regular
-- expressions, Map, Set, JSON, Math, require('fs'|'os'|'path'|'readline'). Not there: npm packages with native parts, Proxy, Reflect, typed arrays, eval.
local J = {}
local KW = {}
for w in ("break case catch class const continue default delete do else extends finally for function if in instanceof let new of return static super switch this throw try typeof var void while yield async await null true false undefined get set"):gmatch("%S+") do KW[w] = true end
local RESERVED = {}
for w in ("break case catch class const continue default delete do else extends finally for function if in instanceof let new return super switch this throw try typeof var void while null true false"):gmatch("%S+") do RESERVED[w] = true end
local LUAKW = {}
for w in ("and elseif end goto local nil not or repeat then until self"):gmatch("%S+") do LUAKW[w] = true end
local function mangle(n)
  if LUAKW[n] then return n .. "_" end
  if n:find("[$\128-\255]") then return (n:gsub("[$\128-\255]", function(c) return string.format("_x%02x", c:byte()) end)) end
  return n
end
local function syntaxError(msg, line) error({ syntax = msg, line = line }, 0) end
local ESC = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", v = "\v", ["0"] = "\0", ["\n"] = "" }
local OPS = { ">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=", "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "?.", "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "**", "<<", ">>" }
local OPSET = {}
for _, o in ipairs(OPS) do OPSET[o] = true end

local function lex(src)
  local toks, i, n, line = {}, 1, #src, 1
  local nlBefore = false
  local function push(t, v, extra)
    local tk = { t = t, v = v, line = line, nl = nlBefore }
    if extra then for k, x in pairs(extra) do tk[k] = x end end
    toks[#toks + 1] = tk
    nlBefore = false
  end
  local function regexAllowed()
    local p = toks[#toks]
    if not p then return true end
    if p.t == "num" or p.t == "str" or p.t == "tpl" or p.t == "name" or p.t == "regex" then return false end
    if p.t == "kw" then return not (p.v == "this" or p.v == "null" or p.v == "true" or p.v == "false" or p.v == "undefined" or p.v == "super") end
    return not (p.v == ")" or p.v == "]" or p.v == "}")
  end
  local function readEsc(j)
    local d = src:sub(j + 1, j + 1)
    if d == "x" then return utf8.char(tonumber(src:sub(j + 2, j + 3), 16) or 63), j + 4 end
    if d == "u" then
      if src:sub(j + 2, j + 2) == "{" then
        local e = src:find("}", j, true)
        return utf8.char(tonumber(src:sub(j + 3, e - 1), 16) or 63), e + 1
      end
      return utf8.char(tonumber(src:sub(j + 2, j + 5), 16) or 63), j + 6
    end
    if d == "\n" then line = line + 1 end
    return ESC[d] or d, j + 2
  end
  if src:sub(1, 2) == "#!" then i = src:find("\n", 1, true) or n + 1 end
  while i <= n do
    local c = src:sub(i, i)
    if c == "\n" then line = line + 1; nlBefore = true; i = i + 1
    elseif c == " " or c == "\t" or c == "\r" then i = i + 1
    elseif src:sub(i, i + 1) == "//" then i = src:find("\n", i, true) or n + 1
    elseif src:sub(i, i + 1) == "/*" then
      local e = src:find("*/", i + 2, true) or n
      for _ in src:sub(i, e):gmatch("\n") do line = line + 1; nlBefore = true end
      i = e + 2
    elseif c:find("[%a_$\128-\255#]") then
      local j = i + 1
      while j <= n and src:sub(j, j):find("[%w_$\128-\255]") do j = j + 1 end
      local w = src:sub(i, j - 1)
      push(KW[w] and "kw" or "name", w)
      i = j
    elseif c:find("%d") or (c == "." and src:sub(i + 1, i + 1):find("%d")) then
      local s = src:match("^0[xX][%x_]+", i) or src:match("^0[bB][01_]+", i) or src:match("^0[oO][0-7_]+", i)
      local v
      if s then
        local clean = s:gsub("_", "")
        local k = clean:sub(2, 2):lower()
        v = k == "x" and tonumber(clean) or tonumber(clean:sub(3), k == "b" and 2 or 8)
      else
        s = src:match("^[%d_]*%.?[%d_]*[eE][+-]?%d+", i) or src:match("^[%d_]*%.?[%d_]*", i)
        v = tonumber((s:gsub("_", "")))
      end
      i = i + #s
      if src:sub(i, i) == "n" then i = i + 1 end
      push("num", v)
    elseif c == '"' or c == "'" then
      local b, j = {}, i + 1
      while true do
        local d = src:sub(j, j)
        if d == "" or d == "\n" then syntaxError("Invalid or unexpected token", line) end
        if d == c then break end
        if d == "\\" then
          local x
          x, j = readEsc(j)
          b[#b + 1] = x
        else
          local e = src:find('[\\\n"\']', j) or n + 1
          if e == j then e = j + 1 end
          b[#b + 1] = src:sub(j, e - 1)
          j = e
        end
      end
      push("str", table.concat(b))
      i = j + 1
    elseif c == "`" then
      local parts, b, j = {}, {}, i + 1
      while true do
        local d = src:sub(j, j)
        if d == "" then syntaxError("Unterminated template literal", line) end
        if d == "`" then break end
        if d == "\\" then
          local x
          x, j = readEsc(j)
          b[#b + 1] = x
        elseif d == "$" and src:sub(j + 1, j + 1) == "{" then
          parts[#parts + 1] = table.concat(b); b = {}
          local depth, k = 1, j + 2
          while depth > 0 do
            local e = src:sub(k, k)
            if e == "" then syntaxError("Unterminated template literal", line) end
            if e == "{" then depth = depth + 1 elseif e == "}" then depth = depth - 1
            elseif e == "`" then
              -- a template inside: skip it whole
              local d2, m = 0, k + 1
              while true do
                local f = src:sub(m, m)
                if f == "" then break end
                if f == "\\" then m = m + 1
                elseif f == "`" and d2 == 0 then break
                elseif f == "$" and src:sub(m + 1, m + 1) == "{" then d2 = d2 + 1; m = m + 1
                elseif f == "}" and d2 > 0 then d2 = d2 - 1 end
                m = m + 1
              end
              k = m
            elseif e == "'" or e == '"' then
              local m = k + 1
              while src:sub(m, m) ~= e and m <= n do if src:sub(m, m) == "\\" then m = m + 1 end m = m + 1 end
              k = m
            end
            k = k + 1
          end
          parts[#parts + 1] = { code = src:sub(j + 2, k - 2) }
          j = k
        else
          if d == "\n" then line = line + 1 end
          b[#b + 1] = d
          j = j + 1
        end
      end
      parts[#parts + 1] = table.concat(b)
      push("tpl", parts)
      i = j + 1
    elseif c == "/" and regexAllowed() then
      local j, inClass = i + 1, false
      while true do
        local d = src:sub(j, j)
        if d == "" or d == "\n" then syntaxError("Invalid regular expression", line) end
        if d == "\\" then j = j + 1
        elseif d == "[" then inClass = true
        elseif d == "]" then inClass = false
        elseif d == "/" and not inClass then break end
        j = j + 1
      end
      local body = src:sub(i + 1, j - 1)
      local flags = src:match("^[a-z]*", j + 1)
      push("regex", body, { flags = flags })
      i = j + 1 + #flags
    else
      -- the longest operator that starts here: a lookup by length, not a scan of the list
      local op
      for len = 4, 2, -1 do
        local s = src:sub(i, i + len - 1)
        if OPSET[s] then op = s; break end
      end
      op = op or c
      if op == "?." and src:sub(i + 2, i + 2):find("%d") then op = "?" end
      push("op", op)
      i = i + #op
    end
  end
  push("eof")
  return toks
end

-- ---------------------------------------------------------------- names that always hold numbers
-- A variable (by its name, in the whole file, so closures are counted) is a number when it is declared with a value and every
-- assignment to it gives a number: number literals, such names, + - * / % ** and the bit operators of them, Math.x, x.length,
-- parseInt/parseFloat/Number(...). It is never a parameter, a for-of/in variable, a destructuring target or a function. The
-- translator writes plain Lua arithmetic and comparisons for them (all numbers of JavaScript are floats, so nothing overflows).
local JOPEN, JCLOSE = { ["("] = 1, ["["] = 1, ["{"] = 1 }, { [")"] = 1, ["]"] = 1, ["}"] = 1 }
local JNUMOP = { ["+"] = 1, ["-"] = 1, ["*"] = 1, ["/"] = 1, ["%"] = 1, ["**"] = 1, ["("] = 1, [")"] = 1, ["~"] = 1, ["&"] = 1, ["|"] = 1, ["^"] = 1, ["<<"] = 1, [">>"] = 1, [">>>"] = 1 }
local JAUG = { ["+="] = 1, ["-="] = 1, ["*="] = 1, ["/="] = 1, ["%="] = 1, ["**="] = 1, ["&="] = 1, ["|="] = 1, ["^="] = 1, ["<<="] = 1, [">>="] = 1, [">>>="] = 1 }
local JNUMFN = { parseInt = 1, parseFloat = 1, Number = 1 }
local function jsMatch(toks, p)  -- the index of the bracket that closes the one at p
  local d = 0
  for q = p, #toks do
    local x = toks[q]
    if x.t == "op" then
      if JOPEN[x.v] then d = d + 1 elseif JCLOSE[x.v] then d = d - 1; if d == 0 then return q end end
    elseif x.t == "eof" then return q end
  end
  return #toks
end
local function jsNumericSpan(toks, p1, p2, N)
  if p1 >= p2 then return false end
  local p = p1
  while p < p2 do
    local x, nx = toks[p], toks[p + 1]
    if x.t == "num" then
    elseif x.t == "name" and (x.v == "Math" or JNUMFN[x.v]) and not N.__shadow[x.v] then
      if x.v == "Math" then
        if not (nx.t == "op" and nx.v == "." and toks[p + 2].t == "name") then return false end
        p = p + 2
        nx = toks[p + 1]
      end
      if nx.t == "op" and nx.v == "(" then p = jsMatch(toks, p + 1); if p >= p2 then return false end
      elseif x.v ~= "Math" then return false end
    elseif x.t == "name" and nx.t == "op" and nx.v == "." and toks[p + 2].v == "length" and p + 2 < p2 then
      p = p + 2
      local after = toks[p + 1]
      if after.t == "op" and (after.v == "(" or after.v == "[" or after.v == ".") then return false end
    elseif x.t == "name" then
      if not N[x.v] then return false end
      if nx.t == "op" and (nx.v == "(" or nx.v == "[" or nx.v == "." or nx.v == "?.") and p + 1 < p2 then return false end
    elseif x.t == "op" and JNUMOP[x.v] then
      if x.v == "(" and nx.t == "op" and nx.v == ")" then return false end
    else return false end
    p = p + 1
  end
  return true
end
local function jsNumericNames(toks)
  local assigns, bad, N = {}, {}, { __shadow = {}, __params = {} }
  local function badRange(a, b) for q = a, b do if toks[q].t == "name" then bad[toks[q].v] = true; N.__params[toks[q].v] = true end end end
  -- the end of an expression that starts at p: a depth-0 , ; or a closing bracket, or a new line that does not go on with an operator
  local function exprEnd(p)
    local d = 0
    for q = p, #toks do
      local x = toks[q]
      if x.t == "eof" then return q end
      if q > p and x.nl and x.t ~= "op" and d == 0 then return q end
      if x.t == "op" then
        if JOPEN[x.v] then d = d + 1
        elseif JCLOSE[x.v] then d = d - 1; if d < 0 then return q end
        elseif d == 0 and (x.v == "," or x.v == ";") then return q end
      end
    end
    return #toks
  end
  for i, x in ipairs(toks) do
    local prev, nx = toks[i - 1], toks[i + 1]
    if x.t == "name" then
      if (x.v == "Math" or JNUMFN[x.v]) and prev and ((prev.t == "kw" and (prev.v == "let" or prev.v == "const" or prev.v == "var" or prev.v == "function" or prev.v == "class")) or (prev.t == "op" and prev.v == ",")) then N.__shadow[x.v] = true end
      if prev and prev.t == "kw" and (prev.v == "let" or prev.v == "const" or prev.v == "var") then
        if nx.t == "op" and nx.v == "=" then
          assigns[#assigns + 1] = { n = x.v, p1 = i + 2, p2 = exprEnd(i + 2) }
        else bad[x.v] = true end
      elseif prev and prev.t == "op" and prev.v == "," and nx.t == "op" and nx.v == "=" then
        -- let a = 1, b = 2 (or an assignment in a list): counted like the first
        assigns[#assigns + 1] = { n = x.v, p1 = i + 2, p2 = exprEnd(i + 2) }
      elseif nx.t == "op" and nx.v == "=" and not (prev and prev.t == "op" and (prev.v == "." or prev.v == "?.")) then
        assigns[#assigns + 1] = { n = x.v, p1 = i + 2, p2 = exprEnd(i + 2) }
      elseif nx.t == "op" and JAUG[nx.v] and not (prev and prev.t == "op" and (prev.v == "." or prev.v == "?.")) then
        assigns[#assigns + 1] = { n = x.v, p1 = i + 2, p2 = exprEnd(i + 2), aug = nx.v }
      elseif nx.t == "op" and nx.v == "=>" then bad[x.v] = true
      elseif nx.t == "kw" and (nx.v == "of" or nx.v == "in") and prev and (prev.t == "kw" or (prev.t == "op" and prev.v == "(")) then bad[x.v] = true
      elseif prev and prev.t == "kw" and (prev.v == "function" or prev.v == "class" or prev.v == "import" or prev.v == "catch") then bad[x.v] = true
      end
    elseif x.t == "kw" and (x.v == "let" or x.v == "const" or x.v == "var") and nx.t == "op" and (nx.v == "{" or nx.v == "[") then
      badRange(i + 1, jsMatch(toks, i + 1))
    elseif x.t == "op" and x.v == "(" then
      -- the parameters of a function or an arrow
      local c = jsMatch(toks, i)
      local after = toks[c + 1]
      local before = prev
      if after and after.t == "op" and (after.v == "=>" or (after.v == "{" and not (before and before.t == "kw" and (before.v == "if" or before.v == "while" or before.v == "for" or before.v == "switch" or before.v == "with")))) then
        badRange(i + 1, c - 1)
      end
    elseif x.t == "op" and (x.v == "]" or x.v == "}") and nx and nx.t == "op" and nx.v == "=" then
      -- [a, b] = ... : a destructuring assignment
      local d = 0
      for q = i, 1, -1 do
        local y = toks[q]
        if y.t == "op" then
          if JCLOSE[y.v] then d = d + 1
          elseif JOPEN[y.v] then
            d = d - 1
            if d == 0 then
              -- a[i] = ... is a store, not a pattern
              local b = toks[q - 1]
              if not (x.v == "]" and b and (b.t == "name" or (b.t == "kw" and b.v == "this") or (b.t == "op" and (b.v == ")" or b.v == "]")))) then badRange(q, i) end
              break
            end
          end
        end
      end
    end
  end
  for _, a in ipairs(assigns) do if not bad[a.n] then N[a.n] = true end end
  -- functions declared once by "function NAME" and bound nowhere else: called straight (no check that it is a function)
  local decl, other = {}, {}
  for i, x in ipairs(toks) do
    if x.t == "name" then
      local prev, nx = toks[i - 1], toks[i + 1]
      if prev and prev.t == "kw" and prev.v == "function" and nx.t == "op" and nx.v == "(" then decl[x.v] = (decl[x.v] or 0) + 1
      elseif not (prev and prev.t == "op" and (prev.v == "." or prev.v == "?.")) and ((nx.t == "op" and (nx.v == "=" or JAUG[nx.v] or nx.v == "++" or nx.v == "--" or nx.v == "=>")) or (prev and prev.t == "op" and (prev.v == "++" or prev.v == "--"))) then other[x.v] = true end
    end
  end
  for _, a in ipairs(assigns) do other[a.n] = true end
  N.__funcs = {}
  for n, c in pairs(decl) do if c == 1 and not other[n] and not N.__params[n] then N.__funcs[n] = true end end
  repeat
    local changed = false
    for _, a in ipairs(assigns) do
      if N[a.n] and not (jsNumericSpan(toks, a.p1, a.p2, N) and (not a.aug or JAUG[a.aug])) then N[a.n] = nil; changed = true end
    end
  until not changed
  return N
end

local function compile(src)
  local toks, pos = lex(src), 1
  local tok = toks[1]
  local out = {}
  local NUMS = jsNumericNames(toks)
  -- texts known to be numbers, texts known to be Lua booleans, and the parts of && and ||
  local NUM, BOOL, ANDOR = {}, {}, {}
  local function condOf(c)
    if BOOL[c] or c == "true" or c == "false" then return c end
    local ao = ANDOR[c]
    if ao then return "(" .. condOf(ao[2]) .. " " .. ao[1] .. " " .. condOf(ao[3]) .. ")" end
    if NUM[c] then
      if c:match("^[%w_]+$") then return "(" .. c .. "~=0 and " .. c .. "==" .. c .. ")" end
      return "R_T(" .. c .. ")"
    end
    if c:match("^R_[lg][te]%(") or c:match("^R_eq%(") or c:match("^R_ne%(") or c:match("^R_instanceof%(") or c:match("^R_in%(") or c:sub(1, 5) == "(not " then return c end
    return "R_T(" .. c .. ")"
  end
  -- a statement made of an expression: i++ and friends without the closure that gives their value
  local function exprStmt(e)
    local a, b, d = e:match("^%(function%(%) local _o=R_num%(([%w_]+)%) ([%w_]+)=_o([%+%-])1%.0 return _o end%)%(%)$")
    if a and a == b then return a .. "=" .. (NUM[a] and a or ("R_num(" .. a .. ")")) .. d .. "1.0" end
    a, d, b = e:match("^%(function%(%) ([%w_]+)=R_num%(([%w_]+)%)([%+%-])1%.0 return [%w_]+ end%)%(%)$")
    if a then return a .. "=" .. (NUM[a] and a or ("R_num(" .. a .. ")")) .. b .. "1.0" end
    if e:match("^R_[%w_]*%(") and e:sub(-1) == ")" then return e end
    return "local _ = " .. e
  end
  local labelN, tmpN = 0, 0
  local fn = { closure = 0, breakables = {} }
  local block = { decl = {}, list = {} }
  local hoisted = {}
  local function adv() pos = pos + 1; tok = toks[pos] end
  local function isOp(v) return tok.t == "op" and tok.v == v end
  local function isKw(v) return tok.t == "kw" and tok.v == v end
  local function err(m) syntaxError(m or ("Unexpected token '" .. tostring(tok.v or "end of input") .. "'"), tok.line) end
  local function acceptOp(v) if isOp(v) then adv(); return true end end
  local function acceptKw(v) if isKw(v) then adv(); return true end end
  local function expectOp(v) if not acceptOp(v) then err() end end
  local function expectKw(v) if not acceptKw(v) then err() end end
  local function emit(s) out[#out + 1] = s end
  local function tmp() tmpN = tmpN + 1; return "_t" .. tmpN end
  local function capture(f) local s = out; out = {}; f(); local r = table.concat(out, "\n"); out = s; return r end
  local function str(s) return (string.format("%q", s):gsub("\\\n", "\\n"):gsub("\r", "\\r")) end
  local function num(v)
    if v ~= v then return "(0/0)" end
    if v == math.huge then return "(1/0)" end
    local s = string.format("%.17g", v)
    if not s:find("[%.e]") then s = s .. ".0" end
    return s
  end
  local function identName()  -- a property name: any word
    if tok.t == "name" or tok.t == "kw" then local v = tok.v; adv(); return v end
    err()
  end
  local function declare(n)
    n = mangle(n)
    if not block.decl[n] then block.decl[n] = true; block.list[#block.list + 1] = n end
    return n
  end
  local function declareVar(n)
    n = mangle(n)
    local b = fn.varBlock or block
    if not b.decl[n] then b.decl[n] = true; b.list[#b.list + 1] = n end
    return n
  end
  local function asiEnd()
    if acceptOp(";") then return end
    if isOp("}") or tok.t == "eof" or tok.nl then return end
    err()
  end
  local assignExpr, expression, statement, functionRest, classExpr, parseBlockBody, unaryExpr

  -- ---- binding patterns: {a, b: c, ...r}, [x, , y=1] ----
  local function parsePattern()
    if acceptOp("[") then
      local items = {}
      while not isOp("]") do
        if isOp(",") then items[#items + 1] = false
        elseif acceptOp("...") then items[#items + 1] = { rest = parsePattern() }
        else
          local p = parsePattern()
          if acceptOp("=") then p.def = assignExpr() end
          items[#items + 1] = p
        end
        if not acceptOp(",") then break end
      end
      expectOp("]")
      return { k = "arr", items = items }
    elseif acceptOp("{") then
      local items = {}
      while not isOp("}") do
        if acceptOp("...") then items[#items + 1] = { rest = parsePattern() }
        else
          local key
          if tok.t == "str" then key = str(tok.v); adv()
          elseif tok.t == "num" then key = str(tostring(tok.v)); adv()
          elseif acceptOp("[") then key = assignExpr(); expectOp("]")
          else
            local nm = tok.v
            key = str(identName())
            if not isOp(":") then
              local p = { k = "name", n = nm, key = key }
              if acceptOp("=") then p.def = assignExpr() end
              items[#items + 1] = p
              goto next
            end
          end
          expectOp(":")
          do
            local p = parsePattern()
            p.key = key
            if acceptOp("=") then p.def = assignExpr() end
            items[#items + 1] = p
          end
        end
        ::next::
        if not acceptOp(",") then break end
      end
      expectOp("}")
      return { k = "obj", items = items }
    end
    if tok.t ~= "name" and not (tok.t == "kw" and not RESERVED[tok.v]) then err() end
    local n = tok.v
    adv()
    return { k = "name", n = n }
  end
  local function patternNames(p, f)
    if p.k == "name" then f(p.n)
    elseif p.rest then patternNames(p.rest, f)
    else
      for _, it in ipairs(p.items) do if it then patternNames(it, f) end end
    end
  end
  -- assigns value code to the pattern; lvFn makes the left side of a name
  local function bindPattern(p, v)
    if p.k == "name" then
      emit(mangle(p.n) .. " = " .. v)
    elseif p.k == "lv" then
      emit(p.set(v))
    elseif p.k == "arr" then
      local t = tmp()
      emit("do local " .. t .. " = R_toarr(" .. v .. ")")
      for i, it in ipairs(p.items) do
        if it then
          if it.rest then bindPattern(it.rest, "R_arrfrom(" .. t .. "," .. i .. ")")
          else
            local val = t .. "[" .. i .. "]"
            if it.def then val = "R_def(" .. val .. ",function() return " .. it.def .. " end)" end
            bindPattern(it, val)
          end
        end
      end
      emit("end")
    else
      local t = tmp()
      emit("do local " .. t .. " = " .. v)
      local used = {}
      for _, it in ipairs(p.items) do
        if it.rest then bindPattern(it.rest, "R_objrest(" .. t .. ",{" .. table.concat(used, ",") .. "})")
        else
          used[#used + 1] = it.key
          local val = "R_get(" .. t .. "," .. it.key .. ")"
          if it.def then val = "R_def(" .. val .. ",function() return " .. it.def .. " end)" end
          bindPattern(it, val)
        end
      end
      emit("end")
    end
  end

  -- ---- functions ----
  local function withBlockText(parse)
    -- a block: its let, const and functions are declared at its top, so anything inside can see anything else
    local savedBlock, savedHoist = block, hoisted
    block = { decl = {}, list = {} }
    hoisted = {}
    local body = capture(parse)
    local head = ""
    if #block.list > 0 then
      local n = math.min(#block.list, 150)
      head = "local " .. table.concat(block.list, ",", 1, n) .. "\n"
    end
    local text = head .. table.concat(hoisted, "\n") .. "\n" .. body
    block, hoisted = savedBlock, savedHoist
    return text
  end

  -- params were parsed already: {items of patterns}
  local function functionText(params, parseBody, opts)
    opts = opts or {}
    local savedFn = fn
    local outerFn = fn
    fn = { closure = 0, breakables = {}, arrow = opts.arrow, isGen = opts.gen, isAsync = opts.async, derived = opts.derived, parent = outerFn }
    local plist = {}
    local pro = {}
    local rest
    local text = withBlockText(function()
      fn.varBlock = block
      for i, p in ipairs(params) do
        if p.rest then
          rest = p.rest
        elseif p.k == "name" and not p.def then
          plist[#plist + 1] = mangle(p.n)
        else
          local a = "_p" .. i
          plist[#plist + 1] = a
          local v = a
          if p.def then v = "R_def(" .. a .. ",function() return " .. p.def .. " end)" end
          patternNames(p, declare)
          bindPattern(p, v)
        end
      end
      if rest then
        patternNames(rest, declare)
        bindPattern(rest, "R_array{...}")
      end
      parseBody()
    end)
    local usesArgs = fn.usesArgs
    fn = savedFn
    local head
    if opts.arrow then
      head = "function(_this_unused" .. (#plist > 0 and "," or "") .. table.concat(plist, ",") .. ((rest or usesArgs) and ((#plist > 0 or true) and ",..." or "...") or "") .. ")\n"
    else
      head = "function(this" .. (#plist > 0 and "," or "") .. table.concat(plist, ",") .. ((rest or usesArgs) and ",..." or "") .. ")\n"
    end
    if usesArgs and not opts.arrow then
      local names = table.concat(plist, ",")
      text = "local arguments=R_array{" .. names .. (#plist > 0 and "," or "") .. "...}\n" .. text
    end
    if opts.gen then
      text = "return R_gen(function()\n" .. text .. "\nend)"
    elseif opts.async then
      text = "return R_async(function()\n" .. text .. "\nend)"
    end
    return head .. text .. "\nend"
  end

  local function parseParams()
    expectOp("(")
    local params = {}
    while not isOp(")") do
      if acceptOp("...") then params[#params + 1] = { rest = parsePattern() }
      else
        local p = parsePattern()
        if acceptOp("=") then p.def = assignExpr() end
        params[#params + 1] = p
      end
      if not acceptOp(",") then break end
    end
    expectOp(")")
    return params
  end

  local function functionBodyBraces()
    expectOp("{")
    while not isOp("}") do
      if tok.t == "eof" then err("Unexpected end of input") end
      statement()
    end
    adv()
  end

  local function nameFn(code, n)
    return "R_fn(" .. code .. "," .. str(n or "") .. ")"
  end

  local function functionExpr(isAsync)
    expectKw("function")
    local gen = acceptOp("*")
    local n
    if tok.t == "name" or (tok.t == "kw" and not RESERVED[tok.v]) then n = tok.v; adv() end
    local params = parseParams()
    local t = functionText(params, functionBodyBraces, { gen = gen, async = isAsync })
    if n then
      -- the name of a function expression is visible inside it
      return "(function() local " .. mangle(n) .. "; " .. mangle(n) .. " = " .. nameFn(t, n) .. " return " .. mangle(n) .. " end)()"
    end
    return nameFn(t, "")
  end

  local function arrowBody(params, isAsync)
    local t
    if isOp("{") then
      t = functionText(params, functionBodyBraces, { arrow = true, async = isAsync })
    else
      t = functionText(params, function()
        local e = assignExpr()
        emit("do return " .. e .. " end")
      end, { arrow = true, async = isAsync })
    end
    return nameFn(t, "")
  end

  -- is the ( at the cursor the start of arrow function parameters?
  local function looksLikeArrow()
    local d, p = 0, pos
    while true do
      local t = toks[p]
      if t.t == "eof" then return false end
      if t.t == "op" then
        if t.v == "(" or t.v == "[" or t.v == "{" then d = d + 1
        elseif t.v == ")" or t.v == "]" or t.v == "}" then
          d = d - 1
          if d == 0 then
            local nx = toks[p + 1]
            return nx.t == "op" and nx.v == "=>"
          end
        end
      end
      p = p + 1
    end
  end

  local function objectLiteral()
    expectOp("{")
    local parts = {}
    while not isOp("}") do
      if acceptOp("...") then
        parts[#parts + 1] = "{spread=" .. assignExpr() .. "}"
      else
        local isAsync, isGen, accessor = false, false, nil
        local function nextIsKey() local x = toks[pos + 1]; return not (x.t == "op" and (x.v == "," or x.v == ":" or x.v == "(" or x.v == "}" or x.v == "=")) end
        if isKw("async") and nextIsKey() then adv(); isAsync = true end
        if acceptOp("*") then isGen = true end
        if (isKw("get") or isKw("set")) and nextIsKey() then accessor = tok.v; adv() end
        local key, shorthand
        if tok.t == "str" then key = str(tok.v); adv()
        elseif tok.t == "num" then key = "R_tostr(" .. num(tok.v) .. ")"; adv()
        elseif acceptOp("[") then key = "R_key(" .. assignExpr() .. ")"; expectOp("]")
        else shorthand = tok.v; key = str(identName()) end
        if isOp("(") then
          local params = parseParams()
          local f = nameFn(functionText(params, functionBodyBraces, { gen = isGen, async = isAsync }), shorthand or "")
          if accessor then parts[#parts + 1] = "{" .. accessor .. "=" .. f .. ",k=" .. key .. "}"
          else parts[#parts + 1] = "{k=" .. key .. ",v=" .. f .. "}" end
        elseif acceptOp(":") then
          local before = tok
          local v = assignExpr()
          if before.t == "kw" and before.v == "function" or isOp("") then end
          parts[#parts + 1] = "{k=" .. key .. ",v=" .. v .. "}"
        else
          if not shorthand then err() end
          parts[#parts + 1] = "{k=" .. key .. ",v=" .. mangle(shorthand) .. "}"
        end
      end
      if not acceptOp(",") then break end
    end
    expectOp("}")
    return "R_obj{" .. table.concat(parts, ",") .. "}"
  end

  local function arrayLiteral()
    expectOp("[")
    local parts, hasSpread, holes = {}, false, 0
    local n = 0
    while not isOp("]") do
      n = n + 1
      if isOp(",") then parts[n] = "nil"
      elseif acceptOp("...") then parts[n] = "{spread=" .. assignExpr() .. "}"; hasSpread = true
      else parts[n] = assignExpr() end
      if not acceptOp(",") then break end
    end
    expectOp("]")
    if hasSpread then
      for i = 1, n do if parts[i]:sub(1, 8) ~= "{spread=" then parts[i] = "{v=" .. parts[i] .. "}" end end
      return "R_arrspread{" .. table.concat(parts, ",") .. "}"
    end
    return "R_arrn(" .. n .. (n > 0 and "," or "") .. table.concat(parts, ",") .. ")"
  end

  local function templateCode(parts)
    local p = {}
    for _, x in ipairs(parts) do
      if type(x) == "string" then
        if x ~= "" then p[#p + 1] = str(x) end
      else
        local savedT, savedP, savedTok = toks, pos, tok
        toks = lex(x.code); pos = 1; tok = toks[1]
        local c = expression()
        toks, pos, tok = savedT, savedP, savedTok
        p[#p + 1] = "R_tostr(" .. c .. ")"
      end
    end
    if #p == 0 then return '""' end
    return "(" .. table.concat(p, "..") .. ")"
  end

  local lastLv
  local function argsList()
    -- after "(": returns a list of argument texts, with spread handled by the caller through hasSpread
    local parts, hasSpread = {}, false
    while not isOp(")") do
      if acceptOp("...") then parts[#parts + 1] = { spread = assignExpr() }; hasSpread = true
      else parts[#parts + 1] = assignExpr() end
      if not acceptOp(",") then break end
    end
    expectOp(")")
    if hasSpread then
      local p = {}
      for i, a in ipairs(parts) do p[i] = type(a) == "table" and ("{spread=" .. a.spread .. "}") or ("{v=" .. a .. "}") end
      return nil, "R_spreadargs{" .. table.concat(p, ",") .. "}"
    end
    return parts
  end

  local function primary()
    local t = tok
    lastLv = nil
    if t.t == "num" then adv(); local s = num(t.v); NUM[s] = true; return s
    elseif t.t == "str" then adv(); return str(t.v)
    elseif t.t == "tpl" then adv(); return templateCode(t.v)
    elseif t.t == "regex" then adv(); return "R_regex(" .. str(t.v) .. "," .. str(t.flags) .. ")"
    elseif t.t == "name" then
      adv()
      if isOp("=>") then
        adv()
        return arrowBody({ { k = "name", n = t.v } })
      end
      if t.v == "arguments" then fn.usesArgs = true; local f = fn; while f.arrow and f.parent do f = f.parent; f.usesArgs = true end end
      lastLv = { k = "name", n = t.v }
      local r = mangle(t.v)
      if NUMS[t.v] then NUM[r] = true end
      return r
    elseif t.t == "kw" then
      local v = t.v
      if v == "this" then adv(); return "this"
      elseif v == "null" then adv(); return "null"
      elseif v == "undefined" then adv(); return "nil"
      elseif v == "true" or v == "false" then adv(); return v
      elseif v == "function" then return functionExpr(false)
      elseif v == "class" then return classExpr()
      elseif v == "async" then
        local nx = toks[pos + 1]
        if nx.t == "kw" and nx.v == "function" then adv(); return functionExpr(true) end
        if nx.t == "op" and nx.v == "(" then
          adv()
          if looksLikeArrow() then
            local params = parseParams()
            expectOp("=>")
            return arrowBody(params, true)
          end
          pos = pos - 1; tok = toks[pos]
        elseif nx.t == "name" and toks[pos + 2].v == "=>" then
          adv()
          local n = tok.v
          adv(); adv()
          return arrowBody({ { k = "name", n = n } }, true)
        end
        adv()
        lastLv = { k = "name", n = "async" }
        return "async"
      elseif v == "new" then
        adv()
        if isOp(".") then adv(); identName(); return "nil" end
        -- the callee: member accesses without calls
        local c = primary()
        while true do
          if acceptOp(".") then c = "R_get(" .. c .. "," .. str(identName()) .. ")"
          elseif acceptOp("[") then c = "R_get(" .. c .. "," .. expression() .. ")"; expectOp("]")
          else break end
        end
        lastLv = nil
        if acceptOp("(") then
          local a, sp = argsList()
          if sp then return "R_new(" .. c .. ",table.unpack(" .. sp .. "))" end
          return "R_new(" .. c .. (#a > 0 and "," or "") .. table.concat(a, ",") .. ")"
        end
        return "R_new(" .. c .. ")"
      elseif v == "super" then
        adv()
        if acceptOp("(") then
          local a, sp = argsList()
          lastLv = nil
          return "R_superctor(_class,this" .. (sp and (",table.unpack(" .. sp .. ")") or ((#a > 0 and "," or "") .. table.concat(a, ","))) .. ")"
        end
        expectOp(".")
        local n = identName()
        if acceptOp("(") then
          local a, sp = argsList()
          lastLv = nil
          return "R_supercall(_class,this," .. str(n) .. (sp and (",table.unpack(" .. sp .. ")") or ((#a > 0 and "," or "") .. table.concat(a, ","))) .. ")"
        end
        return "R_superget(_class,this," .. str(n) .. ")"
      elseif v == "get" or v == "set" or v == "of" or v == "static" or v == "let" or v == "await" or v == "yield" then
        adv()
        lastLv = { k = "name", n = v }
        if isOp("=>") then adv(); return arrowBody({ { k = "name", n = v } }) end
        return mangle(v)
      end
      err()
    elseif t.t == "op" then
      if t.v == "(" then
        if looksLikeArrow() then
          local params = parseParams()
          expectOp("=>")
          return arrowBody(params)
        end
        adv()
        local e = expression()
        expectOp(")")
        local lv = lastLv
        lastLv = lv
        return "(" .. e .. ")"
      elseif t.v == "[" then return arrayLiteral()
      elseif t.v == "{" then return objectLiteral()
      end
    end
    err()
  end

  local function member()
    local e = primary()
    local chain = false
    while true do
      if isOp(".") then
        adv()
        local n = identName()
        if isOp("(") then
          adv()
          local a, sp = argsList()
          lastLv = nil
          if sp then e = "R_M(" .. e .. "," .. str(n) .. ",table.unpack(" .. sp .. "))"
          else e = "R_M(" .. e .. "," .. str(n) .. (#a > 0 and "," or "") .. table.concat(a, ",") .. ")" end
        else
          lastLv = { k = "get", o = e, i = str(n) }
          e = n == "length" and ("R_len(" .. e .. ")") or ("R_get(" .. e .. "," .. str(n) .. ")")
        end
      elseif isOp("?.") then
        adv()
        local o = tmp()
        local rest
        if isOp("(") then
          adv()
          local a = argsList()
          rest = o .. "(nil" .. (#a > 0 and "," or "") .. table.concat(a, ",") .. ")"
        elseif acceptOp("[") then
          local i = expression(); expectOp("]")
          rest = "R_get(" .. o .. "," .. i .. ")"
        else
          local n = identName()
          if isOp("(") then
            adv()
            local a = argsList()
            rest = "R_M(" .. o .. "," .. str(n) .. (#a > 0 and "," or "") .. table.concat(a, ",") .. ")"
          else rest = "R_get(" .. o .. "," .. str(n) .. ")" end
        end
        e = "(function() local " .. o .. "=" .. e .. " if " .. o .. "==nil or " .. o .. "==null then return nil end return " .. rest .. " end)()"
        lastLv = nil
      elseif isOp("[") then
        adv()
        local i = expression()
        expectOp("]")
        if isOp("(") then
          adv()
          local a, sp = argsList()
          lastLv = nil
          if sp then e = "R_M(" .. e .. "," .. i .. ",table.unpack(" .. sp .. "))"
          else e = "R_M(" .. e .. "," .. i .. (#a > 0 and "," or "") .. table.concat(a, ",") .. ")" end
        else
          lastLv = { k = "get", o = e, i = i }
          e = "R_get(" .. e .. "," .. i .. ")"
        end
      elseif isOp("(") then
        adv()
        local a, sp = argsList()
        lastLv = nil
        if e:sub(1, 8) == "function" or e:sub(1, 4) == "R_fn" then e = "(" .. e .. ")" end
        if sp then e = "R_call(" .. e .. ",nil,table.unpack(" .. sp .. "))"
        elseif NUMS.__funcs[e] then e = e .. "(nil" .. (#a > 0 and "," or "") .. table.concat(a, ",") .. ")"
        else e = "R_call(" .. e .. ",nil" .. (#a > 0 and "," or "") .. table.concat(a, ",") .. ")" end
      elseif tok.t == "tpl" then
        adv()
        lastLv = nil
      else break end
    end
    return e
  end

  -- makes a left side: read text and an assignment
  local function lvSet(lv, v)
    if lv.k == "name" then return mangle(lv.n) .. " = " .. v end
    return "R_set(" .. lv.o .. "," .. lv.i .. "," .. v .. ")"
  end
  local function lvGet(lv)
    if lv.k == "name" then return mangle(lv.n) end
    return "R_get(" .. lv.o .. "," .. lv.i .. ")"
  end

  local function postfix()
    local e = member()
    if (isOp("++") or isOp("--")) and not tok.nl then
      local lv = lastLv
      if not lv then err("Invalid left-hand side expression in postfix operation") end
      local d = tok.v == "++" and "+" or "-"
      adv()
      lastLv = nil
      if lv.k == "name" then
        return "(function() local _o=R_num(" .. mangle(lv.n) .. ") " .. mangle(lv.n) .. "=_o" .. d .. "1.0 return _o end)()", { stmt = mangle(lv.n) .. "=R_num(" .. mangle(lv.n) .. ")" .. d .. "1.0" }
      end
      return "(function() local _b,_i=" .. lv.o .. "," .. lv.i .. " local _o=R_num(R_get(_b,_i)) R_set(_b,_i,_o" .. d .. "1.0) return _o end)()"
    end
    return e
  end
  unaryExpr = function()
    local t = tok
    if t.t == "op" then
      if t.v == "!" then adv(); local c = unaryExpr(); lastLv = nil; return "(not " .. condOf(c) .. ")" end
      if t.v == "-" then
        adv()
        local c = unaryExpr()
        lastLv = nil
        if NUM[c] then local r = "(-" .. c .. ")"; NUM[r] = true; return r end
        return "R_neg(" .. c .. ")"
      end
      if t.v == "+" then adv(); local c = unaryExpr(); lastLv = nil; return "R_num(" .. c .. ")" end
      if t.v == "~" then adv(); local c = unaryExpr(); lastLv = nil; return "R_bnot(" .. c .. ")" end
      if t.v == "++" or t.v == "--" then
        local d = t.v == "++" and "+" or "-"
        adv()
        unaryExpr()
        local lv = lastLv
        if not lv then err() end
        lastLv = nil
        if lv.k == "name" then
          return "(function() " .. mangle(lv.n) .. "=R_num(" .. mangle(lv.n) .. ")" .. d .. "1.0 return " .. mangle(lv.n) .. " end)()"
        end
        return "(function() local _b,_i=" .. lv.o .. "," .. lv.i .. " local _n=R_num(R_get(_b,_i))" .. d .. "1.0 R_set(_b,_i,_n) return _n end)()"
      end
    elseif t.t == "kw" then
      if t.v == "typeof" then
        adv()
        local isName = tok.t == "name"
        local n = tok.v
        local c = unaryExpr()
        lastLv = nil
        if isName and c == mangle(n) then return "R_typeof(rawget_env(_ENV," .. str(mangle(n)) .. ",function() return " .. c .. " end))" end
        return "R_typeof(" .. c .. ")"
      end
      if t.v == "void" then adv(); local c = unaryExpr(); lastLv = nil; return "R_void(" .. c .. ")" end
      if t.v == "delete" then
        adv()
        unaryExpr()
        local lv = lastLv
        lastLv = nil
        if lv and lv.k == "get" then return "R_delete(" .. lv.o .. "," .. lv.i .. ")" end
        return "true"
      end
      if t.v == "await" then
        local nx = toks[pos + 1]
        if not (nx.t == "op" and (nx.v == ")" or nx.v == "=" or nx.v == ";" or nx.v == "," or nx.v == "=>")) then
          adv()
          local c = unaryExpr()
          lastLv = nil
          return "R_await(" .. c .. ")"
        end
      end
      if t.v == "yield" then
        adv()
        lastLv = nil
        if acceptOp("*") then return "R_yieldstar(" .. assignExpr() .. ")" end
        if isOp(")") or isOp(";") or isOp("]") or isOp(",") or tok.nl or isOp("}") then return "R_yield(nil)" end
        return "R_yield(" .. assignExpr() .. ")"
      end
    end
    return postfix()
  end
  local function powExpr()
    local a = unaryExpr()
    if isOp("**") then
      adv()
      local b = powExpr()
      lastLv = nil
      return "R_pow(" .. a .. "," .. b .. ")"
    end
    return a
  end
  local LEVELS = {
    { ["*"] = "R_mul", ["/"] = "R_div", ["%"] = "R_mod" },
    { ["+"] = "R_add", ["-"] = "R_sub" },
    { ["<<"] = "R_shl", [">>"] = "R_shr", [">>>"] = "R_ushr" },
    { ["<"] = "R_lt", [">"] = "R_gt", ["<="] = "R_le", [">="] = "R_ge", ["instanceof"] = "R_instanceof", ["in"] = "R_in" },
    { ["=="] = "R_eq", ["!="] = "R_ne", ["==="] = "R_seq", ["!=="] = "R_sne" },
    { ["&"] = "R_band" }, { ["^"] = "R_bxor" }, { ["|"] = "R_bor" },
  }
  local noIn = false
  local function binLevel(l)
    if l == 0 then return powExpr() end
    local ops = LEVELS[l]
    local a = binLevel(l - 1)
    while true do
      local f
      if tok.t == "op" and ops[tok.v] then f = ops[tok.v]
      elseif tok.t == "kw" and (tok.v == "instanceof" or (tok.v == "in" and not noIn)) and ops[tok.v] then f = ops[tok.v] end
      if not f then return a end
      adv()
      local b = binLevel(l - 1)
      lastLv = nil
      local LUAOP = { R_add = "+", R_sub = "-", R_mul = "*", R_div = "/", R_lt = "<", R_gt = ">", R_le = "<=", R_ge = ">=", R_eq = "==", R_ne = "~=" }
      local both = NUM[a] and NUM[b]
      if f == "R_seq" then a = "(" .. a .. "==" .. b .. ")"; BOOL[a] = true
      elseif f == "R_sne" then a = "(" .. a .. "~=" .. b .. ")"; BOOL[a] = true
      elseif both and LUAOP[f] then
        a = "(" .. a .. LUAOP[f] .. b .. ")"
        if l <= 2 then NUM[a] = true else BOOL[a] = true end
      elseif both and f == "R_mod" and tonumber(b) and tonumber(b) ~= 0 then
        a = "R_fmod(" .. a .. "," .. b .. ")"; NUM[a] = true
      else
        a = f .. "(" .. a .. "," .. b .. ")"
        if (both and l <= 2) or l == 3 or l >= 6 then NUM[a] = true end
      end
    end
  end
  local function isBoolCode(c)
    return c:sub(1, 5) == "(not " or c:match("^R_lt%(") or c:match("^R_gt%(") or c:match("^R_le%(") or c:match("^R_ge%(")
  end
  local function andExpr()
    local a = binLevel(#LEVELS)
    while isOp("&&") do
      adv()
      local b = binLevel(#LEVELS)
      lastLv = nil
      local simple = b:match("^[%a_][%w_]*$") or tonumber(b) or b:match('^"[^"]*"$')
      local whole = simple and ("R_andv(" .. a .. "," .. b .. ")") or ("R_and(" .. a .. ",function() return " .. b .. " end)")
      ANDOR[whole] = { "and", a, b }
      a = whole
    end
    return a
  end
  local function orExpr()
    local a = andExpr()
    while isOp("||") or isOp("??") do
      local f = tok.v == "||" and "R_or" or "R_nullish"
      adv()
      local b = andExpr()
      lastLv = nil
      local whole
      if f == "R_or" then
        local simple = b:match("^[%a_][%w_]*$") or tonumber(b) or b:match('^"[^"]*"$')
        whole = simple and ("R_orv(" .. a .. "," .. b .. ")") or ("R_or(" .. a .. ",function() return " .. b .. " end)")
        ANDOR[whole] = { "or", a, b }
      else whole = f .. "(" .. a .. ",function() return " .. b .. " end)" end
      a = whole
    end
    return a
  end
  local function condExpr()
    local c = orExpr()
    if isOp("?") then
      adv()
      local saved = noIn
      noIn = false
      local a = assignExpr()
      noIn = saved
      expectOp(":")
      local b = assignExpr()
      lastLv = nil
      -- a value that is never false or nil in Lua can stand in "c and a or b"
      if NUM[a] or tonumber(a) or a:match('^"[^"]*"$') then
        local r = "(" .. condOf(c) .. " and " .. a .. " or " .. b .. ")"
        if NUM[a] and NUM[b] then NUM[r] = true end
        return r
      end
      return "R_if(" .. c .. ",function() return " .. a .. " end,function() return " .. b .. " end)"
    end
    return c
  end
  -- a destructuring assignment: [a, b] = ... or ({a} = ...)
  local function isPatternAssign()
    if not (isOp("[") or isOp("{")) then return false end
    local d, p = 0, pos
    while true do
      local t = toks[p]
      if t.t == "eof" then return false end
      if t.t == "op" then
        if t.v == "(" or t.v == "[" or t.v == "{" then d = d + 1
        elseif t.v == ")" or t.v == "]" or t.v == "}" then
          d = d - 1
          if d == 0 then return toks[p + 1].t == "op" and toks[p + 1].v == "=" end
        end
      end
      p = p + 1
    end
  end
  local ASSIGN = { ["+="] = "R_add", ["-="] = "R_sub", ["*="] = "R_mul", ["/="] = "R_div", ["%="] = "R_mod", ["**="] = "R_pow", ["<<="] = "R_shl", [">>="] = "R_shr", [">>>="] = "R_ushr", ["&="] = "R_band", ["|="] = "R_bor", ["^="] = "R_bxor" }
  assignExpr = function()
    if isPatternAssign() then
      local p = parsePattern()
      expectOp("=")
      local v = assignExpr()
      local t = tmp()
      local body = capture(function() bindPattern(p, t) end)
      lastLv = nil
      return "(function() local " .. t .. "=" .. v .. "\n" .. body .. "\nreturn " .. t .. " end)()"
    end
    local a, extra = condExpr()
    if tok.t == "op" then
      local lv = lastLv
      local op = tok.v
      if op == "=" then
        if not lv then err("Invalid left-hand side in assignment") end
        adv()
        local fnName = lv.k == "name" and lv.n
        local v = assignExpr()
        lastLv = nil
        if lv.k == "name" then
          return "(function() " .. mangle(lv.n) .. "=" .. v .. " return " .. mangle(lv.n) .. " end)()", { stmt = mangle(lv.n) .. " = " .. v }
        end
        return "R_set(" .. lv.o .. "," .. lv.i .. "," .. v .. ")", { stmt = "R_set(" .. lv.o .. "," .. lv.i .. "," .. v .. ")" }
      elseif ASSIGN[op] then
        if not lv then err() end
        adv()
        local v = assignExpr()
        lastLv = nil
        if lv.k == "name" then
          local n = mangle(lv.n)
          local LUAOP = { ["+="] = "+", ["-="] = "-", ["*="] = "*", ["/="] = "/" }
          local s = n .. " = " .. ASSIGN[op] .. "(" .. n .. "," .. v .. ")"
          if NUM[n] and NUM[v] and LUAOP[op] then s = n .. " = " .. n .. LUAOP[op] .. "(" .. v .. ")"
          elseif NUM[n] and NUM[v] and op == "%=" and tonumber(v) and tonumber(v) ~= 0 then s = n .. " = R_fmod(" .. n .. "," .. v .. ")" end
          return "(function() " .. s .. " return " .. n .. " end)()", { stmt = s }
        end
        local stmt
        if (lv.o == "this" or lv.o:match("^[%a_][%w_]*$")) and (lv.i:match('^"[%w_]*"$') or lv.i:match("^[%a_][%w_]*$")) then
          stmt = "R_set(" .. lv.o .. "," .. lv.i .. "," .. ASSIGN[op] .. "(R_get(" .. lv.o .. "," .. lv.i .. ")," .. v .. "))"
        else
          stmt = "do local _b,_i=" .. lv.o .. "," .. lv.i .. " R_set(_b,_i," .. ASSIGN[op] .. "(R_get(_b,_i)," .. v .. ")) end"
        end
        return "(function() local _b,_i=" .. lv.o .. "," .. lv.i .. " return R_set(_b,_i," .. ASSIGN[op] .. "(R_get(_b,_i)," .. v .. ")) end)()", { stmt = stmt }
      elseif op == "&&=" or op == "||=" or op == "??=" then
        if not lv then err() end
        adv()
        local v = assignExpr()
        lastLv = nil
        local f = op == "&&=" and "R_and" or (op == "||=" and "R_or" or "R_nullish")
        local s = lvSet(lv, f .. "(" .. lvGet(lv) .. ",function() return " .. v .. " end)")
        return "(function() " .. s .. " return " .. lvGet(lv) .. " end)()"
      end
    end
    return a, extra
  end
  expression = function()
    local a, extra = assignExpr()
    if isOp(",") then
      local parts = { a }
      while acceptOp(",") do parts[#parts + 1] = (assignExpr()) end
      lastLv = nil
      return "R_last(" .. table.concat(parts, ",") .. ")"
    end
    return a, extra
  end

  classExpr = function()
    expectKw("class")
    local n
    if tok.t == "name" then n = tok.v; adv() end
    local base = "nil"
    if acceptKw("extends") then base = (function() local c = member(); return c end)() end
    expectOp("{")
    local members = {}
    local fields = {}
    local ctor
    while not isOp("}") do
      if not acceptOp(";") then
        local static, isAsync, isGen, accessor = false, false, false, nil
        local function nextIsKey() local x = toks[pos + 1]; return not (x.t == "op" and (x.v == "(" or x.v == "=" or x.v == ";" or x.v == "}")) end
        if isKw("static") and nextIsKey() then adv(); static = true end
        if isKw("async") and nextIsKey() then adv(); isAsync = true end
        if acceptOp("*") then isGen = true end
        if (isKw("get") or isKw("set")) and nextIsKey() then accessor = tok.v; adv() end
        local key, plain
        if tok.t == "str" then key = str(tok.v); adv()
        elseif acceptOp("[") then key = "R_key(" .. assignExpr() .. ")"; expectOp("]")
        else plain = tok.v; key = str(identName()) end
        if isOp("(") then
          local params = parseParams()
          local f = functionText(params, functionBodyBraces, { gen = isGen, async = isAsync })
          if plain == "constructor" and not static then ctor = f
          else
            members[#members + 1] = "{k=" .. key .. ",f=R_fn(" .. f .. "," .. str(plain or "") .. "),static=" .. tostring(static) .. (accessor and (",acc=" .. str(accessor)) or "") .. "}"
          end
        else
          local v = "nil"
          local saved = fn
          if acceptOp("=") then v = assignExpr() end
          asiEnd()
          if static then members[#members + 1] = "{k=" .. key .. ",v=" .. "function(this) return " .. v .. " end,static=true,field=true}"
          else fields[#fields + 1] = "{k=" .. key .. ",v=function(this) return " .. v .. " end}" end
        end
      end
    end
    adv()
    lastLv = nil
    return "(function() local _class; _class = R_class(" .. str(n or "") .. "," .. base .. "," .. (ctor or "nil") .. ",{" .. table.concat(members, ",") .. "},{" .. table.concat(fields, ",") .. "})" ..
      (n and (" local " .. mangle(n) .. " = _class") or "") .. " return _class end)()"
  end

  -- ---- statements ----
  local function flowReturn(v)
    if fn.closure > 0 then emit('do return "r",' .. v .. " end") else emit("do return " .. v .. " end") end
  end
  local function exprStatement()
    local e, extra = expression()
    if extra and extra.stmt then emit(extra.stmt)
    elseif e:match("^R_[%w_]*%(") and e:sub(-1) == ")" then emit(e)
    else emit("local _ = " .. e) end
  end
  local function blockStatement()
    expectOp("{")
    local t = withBlockText(function()
      while not isOp("}") do
        if tok.t == "eof" then err("Unexpected end of input") end
        statement()
      end
    end)
    adv()
    emit("do\n" .. t .. "\nend")
  end
  local function subStatement()
    if isOp("{") then blockStatement()
    else
      local t = withBlockText(function() statement() end)
      emit("do\n" .. t .. "\nend")
    end
  end
  local function afterFlows(f, v)
    emit("if " .. f .. '=="r" then')
    flowReturn(v)
    emit("end")
    local br = fn.breakables[#fn.breakables]
    if br then
      local cb = br
      if fn.closure > cb.closure then
        emit("if " .. f .. '=="b" then return "b" end')
      elseif cb.kind == "switch" then emit("if " .. f .. '=="b" then goto ' .. cb.endLabel .. " end")
      else emit("if " .. f .. '=="b" then goto ' .. cb.endLabel .. " end") end
      -- continue goes to the innermost loop
      local lp
      for i = #fn.breakables, 1, -1 do if fn.breakables[i].kind == "loop" then lp = fn.breakables[i]; break end end
      if lp then
        if fn.closure > lp.closure then emit("if " .. f .. '=="c" then return "c" end')
        else emit("if " .. f .. '=="c" then goto ' .. lp.contLabel .. " end") end
      end
    end
  end
  local function loopBody(rec, parse)
    fn.breakables[#fn.breakables + 1] = rec
    parse()
    fn.breakables[#fn.breakables] = nil
  end
  local function newLoop(name)
    labelN = labelN + 1
    return { kind = "loop", closure = fn.closure, contLabel = "cont_" .. labelN, endLabel = "brk_" .. labelN, name = name }
  end
  local function hasClosure(fromPos, toPos)
    for p = fromPos, toPos do
      local t = toks[p]
      if (t.t == "kw" and t.v == "function") or (t.t == "op" and t.v == "=>") then return true end
    end
    return false
  end
  local function tokensToBodyEnd()
    -- the position of the end of the statement that starts at the cursor, roughly: a whole {} or up to ;
    local d, p = 0, pos
    while true do
      local t = toks[p]
      if t.t == "eof" then return p end
      if t.t == "op" then
        if t.v == "(" or t.v == "[" or t.v == "{" then d = d + 1
        elseif t.v == ")" or t.v == "]" or t.v == "}" then
          d = d - 1
          if d == 0 and t.v == "}" then return p end
        elseif t.v == ";" and d == 0 then return p end
      end
      p = p + 1
    end
  end

  local function forStatement(labelName)
    expectKw("for")
    local isAwait = acceptKw("await")
    expectOp("(")
    local rec = newLoop(labelName)
    local declKind
    if isKw("let") or isKw("const") or isKw("var") then declKind = tok.v end
    -- for ( ... of / in ... )
    local startPos = pos
    if declKind then
      adv()
      local p = parsePattern()
      if isKw("of") or isKw("in") then
        local kind = tok.v
        adv()
        local src = kind == "of" and assignExpr() or expression()
        expectOp(")")
        local v_ = tmp()
        local names = {}
        patternNames(p, function(n) names[#names + 1] = mangle(n) end)
        local iterFn = kind == "of" and "R_forof" or "R_forin"
        if declKind == "var" then patternNames(p, declareVar) end
        emit("for " .. v_ .. " in " .. iterFn .. "(" .. src .. ") do")
        if declKind ~= "var" and #names > 0 then emit("local " .. table.concat(names, ",")) end
        bindPattern(p, v_)
        loopBody(rec, subStatement)
        emit("::" .. rec.contLabel .. "::")
        emit("end")
        emit("::" .. rec.endLabel .. "::")
        return
      end
      pos = startPos; tok = toks[pos]
    elseif tok.t == "name" and toks[pos + 1].t == "kw" and (toks[pos + 1].v == "of" or toks[pos + 1].v == "in") then
      local n = tok.v
      adv()
      local kind = tok.v
      adv()
      local src = kind == "of" and assignExpr() or expression()
      expectOp(")")
      local v_ = tmp()
      emit("for " .. v_ .. " in " .. (kind == "of" and "R_forof" or "R_forin") .. "(" .. src .. ") do")
      emit(mangle(n) .. " = " .. v_)
      loopBody(rec, subStatement)
      emit("::" .. rec.contLabel .. "::")
      emit("end")
      emit("::" .. rec.endLabel .. "::")
      return
    end
    -- the classic form: init; cond; update
    emit("do")
    local names = {}
    if declKind then
      adv()
      repeat
        local p = parsePattern()
        local v = "nil"
        noIn = true
        if acceptOp("=") then v = assignExpr() end
        noIn = false
        patternNames(p, function(n)
          if declKind == "var" then declareVar(n) else names[#names + 1] = mangle(n); emit("local " .. mangle(n)) end
        end)
        bindPattern(p, v)
      until not acceptOp(",")
    elseif not isOp(";") then
      noIn = true
      local e, extra = expression()
      noIn = false
      if extra and extra.stmt then emit(extra.stmt) else emit(exprStmt(e)) end
    end
    expectOp(";")
    local cond = "true"
    if not isOp(";") then cond = condOf((expression())) end
    expectOp(";")
    local updateText = ""
    if not isOp(")") then
      updateText = capture(function()
        local e, extra = expression()
        if extra and extra.stmt then emit(extra.stmt)
        else emit(exprStmt(e)) end
      end)
    end
    expectOp(")")
    local closures = #names > 0 and hasClosure(pos, tokensToBodyEnd())
    emit("while " .. cond .. " do")
    if closures then
      -- each round has its own copy of the variables, for the functions made inside
      local copies = {}
      for i, n in ipairs(names) do copies[i] = "_c_" .. n end
      emit("local " .. table.concat(copies, ",") .. " = " .. table.concat(names, ","))
      emit("do local " .. table.concat(names, ",") .. " = " .. table.concat(copies, ","))
      loopBody(rec, subStatement)
      emit("::" .. rec.contLabel .. "::")
      emit(table.concat(copies, ",") .. " = " .. table.concat(names, ","))
      emit("end")
      emit(table.concat(names, ",") .. " = " .. table.concat(copies, ","))
    else
      loopBody(rec, subStatement)
      emit("::" .. rec.contLabel .. "::")
    end
    emit(updateText)
    emit("end")
    emit("end")
    emit("::" .. rec.endLabel .. "::")
  end

  local function tryStatement()
    expectKw("try")
    fn.closure = fn.closure + 1
    local bodyText = capture(blockStatement)
    fn.closure = fn.closure - 1
    local catchPattern, catchPos
    if acceptKw("catch") then
      if acceptOp("(") then catchPattern = parsePattern(); expectOp(")") end
      catchPos = pos
      -- skip the block; it is compiled in its place below
      local d = 0
      while true do
        local t = toks[pos]
        if t.t == "op" then
          if t.v == "{" then d = d + 1 elseif t.v == "}" then d = d - 1; if d == 0 then pos = pos + 1; break end end
        end
        if t.t == "eof" then err() end
        pos = pos + 1
      end
      tok = toks[pos]
    end
    local finallyPos
    if isKw("finally") then
      adv()
      finallyPos = pos
      local d = 0
      while true do
        local t = toks[pos]
        if t.t == "op" then
          if t.v == "{" then d = d + 1 elseif t.v == "}" then d = d - 1; if d == 0 then pos = pos + 1; break end end
        end
        if t.t == "eof" then err() end
        pos = pos + 1
      end
      tok = toks[pos]
    end
    local after = pos
    local function runAt(p) pos = p; tok = toks[pos]; blockStatement() end
    local function core()
      local ok, f, v = tmp(), tmp(), tmp()
      emit("do local " .. ok .. "," .. f .. "," .. v .. " = R_pcall(function()\n" .. bodyText .. "\nend)")
      if catchPos then
        emit("if not " .. ok .. " then")
        emit("local _e = R_catch(" .. f .. ")")
        if catchPattern then
          local names = {}
          patternNames(catchPattern, function(n) names[#names + 1] = mangle(n) end)
          emit("local " .. table.concat(names, ","))
          bindPattern(catchPattern, "_e")
        end
        runAt(catchPos)
        emit("else")
        afterFlows(f, v)
        emit("end")
      else
        emit("if not " .. ok .. " then R_error(" .. f .. ",0) end")
        afterFlows(f, v)
      end
      emit("end")
    end
    if finallyPos then
      local ok, f, v = tmp(), tmp(), tmp()
      fn.closure = fn.closure + 1
      local text = capture(core)
      fn.closure = fn.closure - 1
      emit("do local " .. ok .. "," .. f .. "," .. v .. " = R_pcall(function()\n" .. text .. "\nend)")
      runAt(finallyPos)
      emit("if not " .. ok .. " then R_error(" .. f .. ",0) end")
      afterFlows(f, v)
      emit("end")
    else
      core()
    end
    pos = after; tok = toks[pos]
  end

  local function switchStatement()
    expectKw("switch")
    expectOp("(")
    local v = expression()
    expectOp(")")
    expectOp("{")
    labelN = labelN + 1
    local rec = { kind = "switch", closure = fn.closure, endLabel = "brk_" .. labelN }
    local cases = {}
    local base = labelN
    local bodyText = withBlockText(function()
      fn.breakables[#fn.breakables + 1] = rec
      local i = 0
      while not isOp("}") do
        i = i + 1
        local label = "case_" .. base .. "_" .. i
        if acceptKw("case") then
          cases[#cases + 1] = { test = expression(), label = label }
        else
          expectKw("default")
          cases[#cases + 1] = { default = true, label = label }
        end
        expectOp(":")
        emit("::" .. label .. "::")
        emit("do")
        while not (isKw("case") or isKw("default") or isOp("}")) do statement() end
        emit("end")
      end
      fn.breakables[#fn.breakables] = nil
    end)
    adv()
    local s = tmp()
    emit("do local " .. s .. " = " .. v)
    local def
    -- the jumps come first; declarations of the block go before them
    local head, rest = bodyText:match("^(local [^\n]*\n)(.*)$")
    if head then emit(head) else rest = bodyText end
    for _, c in ipairs(cases) do
      if c.default then def = c.label
      else emit("if " .. s .. "==" .. c.test .. " then goto " .. c.label .. " end") end
    end
    emit("goto " .. (def or rec.endLabel))
    emit(rest)
    emit("end")
    emit("::" .. rec.endLabel .. "::")
  end

  statement = function()
    local t = tok
    if t.t == "op" then
      if t.v == "{" then return blockStatement() end
      if t.v == ";" then adv(); return end
    elseif t.t == "name" and toks[pos + 1].t == "op" and toks[pos + 1].v == ":" then
      -- a label
      local n = t.v
      adv(); adv()
      fn.nextLabel = n
      return statement()
    elseif t.t == "kw" then
      local v = t.v
      if v == "var" or v == "let" or v == "const" then
        local nx = toks[pos + 1]
        if not (v == "let" and nx.t == "op" and nx.v == "=") then
          adv()
          repeat
            local p = parsePattern()
            local value
            if acceptOp("=") then value = assignExpr() end
            if p.k == "name" and value and (value:sub(1, 6) == 'R_fn(f' or value:sub(1, 6) == "R_fn(f") then
              value = value:gsub(',""%)$', "," .. str(p.n) .. ")")
            end
            patternNames(p, v == "var" and declareVar or declare)
            if value then bindPattern(p, value)
            elseif v ~= "var" and p.k == "name" then emit(mangle(p.n) .. " = nil") end
          until not acceptOp(",")
          asiEnd()
          return
        end
      elseif v == "function" or (v == "async" and toks[pos + 1].t == "kw" and toks[pos + 1].v == "function" and not toks[pos + 1].nl) then
        local isAsync = acceptKw("async")
        adv()
        local gen = acceptOp("*")
        local n = tok.v
        adv()
        local params = parseParams()
        local m = declare(n)
        local text = nameFn(functionText(params, functionBodyBraces, { gen = gen, async = isAsync }), n)
        hoisted[#hoisted + 1] = m .. " = " .. text
        return
      elseif v == "class" then
        local n = toks[pos + 1].v
        local m = declare(n)
        local c = classExpr()
        emit(m .. " = " .. c)
        return
      elseif v == "if" then
        adv(); expectOp("(")
        local c = expression()
        expectOp(")")
        emit("if " .. condOf(c) .. " then")
        subStatement()
        if acceptKw("else") then emit("else"); subStatement() end
        emit("end")
        return
      elseif v == "while" then
        adv(); expectOp("(")
        local c = expression()
        expectOp(")")
        local rec = newLoop(fn.nextLabel)
        fn.nextLabel = nil
        emit("while " .. condOf(c) .. " do")
        loopBody(rec, subStatement)
        emit("::" .. rec.contLabel .. "::")
        emit("end")
        emit("::" .. rec.endLabel .. "::")
        return
      elseif v == "do" then
        adv()
        local rec = newLoop(fn.nextLabel)
        fn.nextLabel = nil
        emit("while true do")
        loopBody(rec, subStatement)
        emit("::" .. rec.contLabel .. "::")
        expectKw("while"); expectOp("(")
        local c = expression()
        expectOp(")")
        acceptOp(";")
        emit("if not " .. condOf(c) .. " then break end")
        emit("end")
        emit("::" .. rec.endLabel .. "::")
        return
      elseif v == "for" then
        local l = fn.nextLabel
        fn.nextLabel = nil
        return forStatement(l)
      elseif v == "try" then return tryStatement()
      elseif v == "switch" then return switchStatement()
      elseif v == "return" then
        adv()
        if isOp(";") or isOp("}") or tok.nl or tok.t == "eof" then flowReturn("nil")
        else flowReturn((expression())) end
        asiEnd()
        return
      elseif v == "throw" then
        adv()
        emit("R_throw(" .. expression() .. ")")
        asiEnd()
        return
      elseif v == "break" or v == "continue" then
        adv()
        local target
        if tok.t == "name" and not tok.nl then
          local n = tok.v
          adv()
          for i = #fn.breakables, 1, -1 do if fn.breakables[i].name == n then target = fn.breakables[i]; break end end
          if not target then err("Undefined label '" .. n .. "'") end
        elseif v == "break" then target = fn.breakables[#fn.breakables]
        else
          for i = #fn.breakables, 1, -1 do if fn.breakables[i].kind == "loop" then target = fn.breakables[i]; break end end
        end
        if not target then err("Illegal " .. v .. " statement") end
        if fn.closure > target.closure then emit('do return "' .. v:sub(1, 1) .. '" end')
        elseif v == "break" then emit("goto " .. target.endLabel)
        else emit("goto " .. target.contLabel) end
        asiEnd()
        return
      end
    end
    exprStatement()
    asiEnd()
  end

  local text = withBlockText(function()
    fn.varBlock = block
    while tok.t ~= "eof" do statement() end
  end)
  return text
end

-- ---------------------------------------------------------------- translation cache, LANG_DUMP and LANG_TIME
-- The Lua text of a program is kept in /var/cache/lang (LANG_CACHE=DIR elsewhere, LANG_CACHE=off not at all): one file per source path,
-- used while the source text and this translator (its version, the size and date of its file) stay the same. LANG_DUMP=FILE writes
-- the Lua text to FILE; LANG_TIME=1 prints how long the translation and the run took (to stderr).
local LC = { clock = os.clock or function() return 0 end, translate = 0 }
local function lcEnv(k) return os.getenv and os.getenv(k) end
local function lcHash(s)
  local h1, h2, byte, n, i = 0x811c9dc5, #s, string.byte, #s, 1
  while i + 7 <= n do
    local a, b, c, d, e, f, g, k = byte(s, i, i + 7)
    h1 = ((h1 ~ (a | b << 8 | c << 16 | d << 24)) * 16777619) & 0xffffffff
    h2 = ((h2 ~ (e | f << 8 | g << 16 | k << 24) ~ (h1 >> 7)) * 2246822519) & 0xffffffff
    i = i + 8
  end
  for j = i, n do h1 = ((h1 ~ byte(s, j)) * 16777619) & 0xffffffff end
  return string.format("%08x%08x", h1, h2)
end
-- the text of SRC (a file NAME) translated by TRANSLATE(), from the cache when it can be
function LC.get(tag, version, name, src, translate)
  local t0 = LC.clock()
  local dir = lcEnv("LANG_CACHE") or "/var/cache/lang"
  local file, stamp, text
  if dir ~= "off" and #src >= 200 and fs and fs.read and fs.write then
    local st = fs.stat and fs.stat((lcEnv("DRIVER_DIR") or "/usr/local/lib/drivers") .. "/" .. tag .. ".lua")
    stamp = "-- " .. version .. " " .. (type(st) == "table" and (tostring(st.size) .. "." .. tostring(st.mtime)) or "-") .. " " .. #src .. " " .. lcHash(src) .. "\n"
    file = dir .. "/" .. tag .. "-" .. lcHash(name) .. ".lua"
    local old = fs.read(file)
    if old and old:sub(1, #stamp) == stamp then text = old:sub(#stamp + 1) end
  end
  if not text then
    text = translate()
    if file and not fs.write(file, stamp .. text) and fs.mkdir then
      pcall(fs.mkdir, dir, true)
      fs.write(file, stamp .. text)
    end
  end
  local dump = lcEnv("LANG_DUMP")
  if dump and fs and fs.write then fs.write(dump, text) end
  LC.translate = LC.translate + (LC.clock() - t0)
  return text
end
function LC.report(t0)
  if lcEnv("LANG_TIME") then
    local line = string.format("lang-time translate %.4f run %.4f\n", LC.translate, LC.clock() - t0 - LC.translate)
    if io and io.stderr then io.stderr:write(line) else print(line) end
  end
end

J.compile = compile
J.VERSION = "1.0.0.2"
function J.main(args)
  local rt = driver.load("jsrt")
  -- the file is the first argument that is not an option (as jsrt reads them)
  local path
  for _, a in ipairs(args) do
    if a == "-e" or a == "--eval" or a == "-p" or a == "--print" then break end
    if a:sub(1, 1) ~= "-" then path = a; break end
  end
  local t0 = LC.clock()
  local first = true
  local code = rt.main(args, function(src)
    -- the program itself is cached; the lines of the prompt and the modules it requires are translated each time
    if not (first and path) then return compile(src) end
    first = false
    return LC.get("jslang", J.VERSION, path, src, function() return compile(src) end)
  end)
  LC.report(t0)
  return code
end
return J
