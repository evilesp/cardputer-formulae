#!lua
-- pylang: Python 3 for this device. The source is translated to Lua, then run by the Lua of the firmware. A large part of the language is
-- here (classes, exceptions, generators, comprehensions, f-strings, decorators, keyword arguments) with the usual builtins and the modules
-- math, random, time, os, sys, json, string, collections, itertools, functools, re. Not here: async, metaclasses, big integers beyond 64 bits
-- (they become floats), C extensions and pip packages. import gfx, term, key, touch, net, fs, sys_ give the device modules.
-- Loaded by the programs python3 and python: driver.load("pylang").main(arg)

local P = {}
local KW = {}
for w in ("False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield"):gmatch("%S+") do KW[w] = true end
local LUAKW = {}
for w in ("end nil then repeat until function local goto do and or not true false"):gmatch("%S+") do LUAKW[w] = true end
local function mangle(n) if LUAKW[n] then return n .. "_" end return n end

-- ---------------------------------------------------------------- lexer
local OPS3 = { ["**="]=1, ["//="]=1, [">>="]=1, ["<<="]=1, ["..."]=1 }
local OPS2 = { ["**"]=1, ["//"]=1, [">>"]=1, ["<<"]=1, ["<="]=1, [">="]=1, ["=="]=1, ["!="]=1, ["->"]=1, ["+="]=1, ["-="]=1, ["*="]=1, ["/="]=1, ["%="]=1, ["&="]=1, ["|="]=1, ["^="]=1, [":="]=1 }
local ESC = { n="\n", t="\t", r="\r", ["\\"]="\\", ["'"]="'", ['"']='"', a="\a", b="\b", f="\f", v="\v", ["0"]="\0", ["\n"]="" }

local function unescape(s)
  if not s:find("\\", 1, true) then return s end
  local out, i = {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    if c ~= "\\" then out[#out + 1] = c; i = i + 1
    else
      local d = s:sub(i + 1, i + 1)
      if d == "x" then out[#out + 1] = utf8.char(tonumber(s:sub(i + 2, i + 3), 16) or 63); i = i + 4
      elseif d == "u" then out[#out + 1] = utf8.char(tonumber(s:sub(i + 2, i + 5), 16) or 63); i = i + 6
      elseif d == "U" then out[#out + 1] = utf8.char(tonumber(s:sub(i + 2, i + 9), 16) or 63); i = i + 10
      elseif ESC[d] then out[#out + 1] = ESC[d]; i = i + 2
      else out[#out + 1] = c .. d; i = i + 2 end
    end
  end
  return table.concat(out)
end

-- col, len: where the error is in the line (1-based) and how long the token is
local function syntaxError(msg, line, col, len) error({ syntax = msg, line = line, col = col, len = len }, 0) end

-- where a token stands: the line starts of a source, and the column (1 = first character of the line) of an index; used by the
-- error messages of the translator
local function lineStartsOf(src)
  local ls, p = { 1 }, 1
  while true do
    p = src:find("\n", p, true)
    if not p then break end
    p = p + 1
    ls[#ls + 1] = p
  end
  return ls
end
local function colAt(ls, p)
  local lo, hi = 1, #ls
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if ls[mid] <= p then lo = mid else hi = mid - 1 end
  end
  return p - ls[lo] + 1
end

local function lex(src)
  local toks, i, n, line, depth, indents = {}, 1, #src, 1, 0, { 0 }
  local ls, tokStart = lineStartsOf(src), 1
  local function push(t, v) toks[#toks + 1] = { t = t, v = v, line = line, col = colAt(ls, tokStart) } end
  local bol = true
  if src:sub(1, 2) == "#!" then i = (src:find("\n", 1, true) or n) end
  while i <= n do
    local lt = toks[#toks]
    if lt and not lt.ecol then lt.ecol = colAt(ls, i - 1) end
    tokStart = i
    if bol and depth == 0 then
      local j, col = i, 0
      while true do
        local c = src:sub(j, j)
        if c == " " then col = col + 1; j = j + 1
        elseif c == "\t" then col = col + 8 - col % 8; j = j + 1
        else break end
      end
      local c = src:sub(j, j)
      if c == "\n" then i = j + 1; line = line + 1
      elseif c == "\r" then i = j + 1
      elseif c == "#" then i = src:find("\n", j, true) or n + 1
      elseif j > n then i = j
      else
        i = j; bol = false
        if col > indents[#indents] then indents[#indents + 1] = col; push("indent")
        else
          while col < indents[#indents] do indents[#indents] = nil; push("dedent") end
          if col ~= indents[#indents] then syntaxError("unindent does not match any outer indentation level", line, j - i + 1, 1) end
        end
      end
    else
      local c = src:sub(i, i)
      if c == " " or c == "\t" or c == "\r" then i = (src:find("[^ \t\r]", i + 1) or n + 1)
      elseif c == "\n" then
        if depth == 0 then push("nl"); bol = true end
        line = line + 1; i = i + 1
      elseif c == "\\" and src:sub(i + 1, i + 1):find("[\r\n]") then
        i = src:find("\n", i, true) + 1; line = line + 1
      elseif c == "#" then i = src:find("\n", i, true) or n + 1
      elseif c:find("[%a_\128-\255]") or c:find("%d") == nil and false then
        -- a word in one find (not a find per character)
        local j = select(2, src:find("^[%w_\128-\255]*", i)) + 1
        local w = src:sub(i, j - 1)
        local q = src:sub(j, j)
        if (q == '"' or q == "'") and #w <= 2 and w:lower():find("^[rbfu]+$") then
          i = j
          local prefix = w:lower()
          local qs = src:sub(i, i + 2)
          local triple = qs == q .. q .. q
          local close = triple and qs or q
          local from = i + #close
          local k = from
          while true do
            k = src:find(q == '"' and '[\\"]' or "[\\']", k) or n + 1
            local d = src:sub(k, k)
            if k > n then syntaxError("unterminated string literal (detected at line " .. line .. ")", line, colAt(ls, tokStart), 1) end
            if d == "\\" then k = k + 2
            elseif src:sub(k, k + #close - 1) == close then break
            else k = k + 1 end
          end
          local body = src:sub(from, k - 1)
          i = k + #close
          local start = line
          for _ in body:gmatch("\n") do line = line + 1 end
          if prefix:find("f") then toks[#toks + 1] = { t = "fstr", v = body, raw = prefix:find("r") ~= nil, line = start, col = colAt(ls, tokStart) }
          else toks[#toks + 1] = { t = "str", v = prefix:find("r") and body or unescape(body), line = start, col = colAt(ls, tokStart) } end
        else
          push(KW[w] and "kw" or "name", w); i = j
        end
      elseif c:find("%d") or (c == "." and src:sub(i + 1, i + 1):find("%d")) then
        local hex = src:match("^0[xX][%x_]+", i) or src:match("^0[oO][0-7_]+", i) or src:match("^0[bB][01_]+", i)
        if hex then
          local clean = hex:gsub("_", "")
          local v = clean:sub(2, 2):lower() == "x" and math.tointeger(tonumber(clean)) or tonumber(clean:sub(3), clean:sub(2, 2):lower() == "o" and 8 or 2)
          push("num", tostring(v)); i = i + #hex
        else
          local s = src:match("^[%d_]*%.?[%d_]*[eE][+-]?%d+", i) or src:match("^[%d_]*%.?[%d_]*", i)
          local clean = s:gsub("_", "")
          i = i + #s
          if clean:find("[%.eE]") then
            if not clean:find("%.") then clean = clean:gsub("[eE]", ".0e") end
            if clean:sub(-1) == "." then clean = clean .. "0" end
            if clean:sub(1, 1) == "." then clean = "0" .. clean end
          elseif not math.tointeger(tonumber(clean)) then
            clean = string.format("%.17g", tonumber(clean))
          end
          push("num", clean)
        end
      elseif c == '"' or c == "'" then
        local triple = src:sub(i, i + 2) == c .. c .. c
        local close = triple and (c .. c .. c) or c
        local from = i + #close
        local k = from
        while true do
          k = src:find(c == '"' and '[\\"\n]' or "[\\'\n]", k) or n + 1
          local d = src:sub(k, k)
          if k > n or (d == "\n" and not triple) then syntaxError("unterminated string literal (detected at line " .. line .. ")", line, colAt(ls, tokStart), 1) end
          if d == "\\" then k = k + 2
          elseif src:sub(k, k + #close - 1) == close then break
          else k = k + 1 end
        end
        local body = src:sub(from, k - 1)
        toks[#toks + 1] = { t = "str", v = unescape(body), line = line, col = colAt(ls, tokStart) }
        for _ in body:gmatch("\n") do line = line + 1 end
        i = k + #close
      else
        local s3, s2 = src:sub(i, i + 2), src:sub(i, i + 1)
        local op = OPS3[s3] and s3 or (OPS2[s2] and s2 or c)
        if op == "(" or op == "[" or op == "{" then depth = depth + 1
        elseif op == ")" or op == "]" or op == "}" then depth = math.max(0, depth - 1) end
        push("op", op); i = i + #op
      end
    end
  end
  do
    local lt = toks[#toks]
    if lt and not lt.ecol then lt.ecol = colAt(ls, i - 1) end
  end
  tokStart = i
  if toks[#toks] and toks[#toks].t ~= "nl" then push("nl") end
  for k = #indents, 2, -1 do push("dedent") end
  push("eof")
  return toks
end

-- ---------------------------------------------------------------- names that always hold numbers
-- A name of a function (or of the module) is a number when every assignment to it gives one: number literals, such names, + - * / // %
-- ** of them, len() int() float() ord() of anything, abs() round() min() max() of numbers, the variable of a for over range(). The
-- translator then writes plain Lua arithmetic for it, with a range check that keeps Python's results (big integers become floats).
local NUMFN = { len = "any", int = "any", float = "any", ord = "any", abs = "num", round = "num", min = "num", max = "num" }
local NUMOP = { ["+"] = 1, ["-"] = 1, ["*"] = 1, ["/"] = 1, ["//"] = 1, ["%"] = 1, ["**"] = 1, ["("] = 1, [")"] = 1, ["~"] = 1, ["<<"] = 1, [">>"] = 1, ["&"] = 1, ["|"] = 1, ["^"] = 1 }
local AUGNUM = { ["+="] = 1, ["-="] = 1, ["*="] = 1, ["/="] = 1, ["//="] = 1, ["%="] = 1, ["**="] = 1 }
local OPEN, CLOSE = { ["("] = 1, ["["] = 1, ["{"] = 1 }, { [")"] = 1, ["]"] = 1, ["}"] = 1 }

-- the builtins that the program gives another meaning (then their results are not known), and the names of global/nonlocal statements
local function programFacts(toks)
  local shadow, outer = {}, {}
  local SAFE = { math = 1, random = 1, time = 1, string = 1, os = 1, sys = 1 }
  for i, t in ipairs(toks) do
    local prev, nx = toks[i - 1], toks[i + 1]
    if t.t == "name" and (NUMFN[t.v] or t.v == "range") then
      if (nx and nx.t == "op" and (nx.v == "=" or nx.v == ",")) or (prev and (prev.t == "kw" and (prev.v == "def" or prev.v == "class" or prev.v == "as" or prev.v == "import" or prev.v == "for" or prev.v == "global" or prev.v == "nonlocal"))) then shadow[t.v] = true end
    elseif t.t == "kw" and (t.v == "global" or t.v == "nonlocal") then
      local j = i + 1
      while toks[j] and toks[j].t == "name" do outer[toks[j].v] = true; j = j + (toks[j + 1] and toks[j + 1].v == "," and 2 or 1) end
    elseif t.t == "op" and t.v == "*" and prev and prev.t == "kw" and prev.v == "import" then
      local m = toks[i - 2]
      if not (m and m.t == "name" and SAFE[m.v]) then for k in pairs(NUMFN) do shadow[k] = true end shadow.range = true end
    end
  end
  return shadow, outer
end

-- the tokens P1..P2-1 always give a number when the names in N are numbers
local function numericSpan(toks, p1, p2, N, shadow)
  if p1 >= p2 then return false end
  local p = p1
  while p < p2 do
    local t = toks[p]
    local nx = toks[p + 1]
    if t.t == "num" then
      if nx and nx.t == "op" and nx.v == "." then return false end
    elseif t.t == "name" then
      local kind = NUMFN[t.v]
      local call = nx and nx.t == "op" and p + 1 < p2 and (nx.v == "(" or nx.v == "[" or nx.v == ".")
      if call then
        if not (kind and not shadow[t.v] and nx.v == "(") then return false end
        local d, q = 0, p + 1
        repeat
          local x = toks[q]
          if x.t == "op" then if OPEN[x.v] then d = d + 1 elseif CLOSE[x.v] then d = d - 1 end end
          q = q + 1
        until d == 0 or q >= p2
        if d ~= 0 then return false end
        if kind == "num" then
          local s, d2 = p + 2, 0
          for r = p + 2, q - 2 do
            local x = toks[r]
            if x.t == "op" then
              if OPEN[x.v] then d2 = d2 + 1 elseif CLOSE[x.v] then d2 = d2 - 1
              elseif d2 == 0 and x.v == "," then
                if not numericSpan(toks, s, r, N, shadow) then return false end
                s = r + 1
              elseif x.v == "=" then return false end
            end
          end
          if not numericSpan(toks, s, q - 1, N, shadow) then return false end
        end
        p = q - 1
      elseif not N[t.v] then return false end
    elseif t.t == "op" and NUMOP[t.v] then
      if t.v == "(" and nx and nx.t == "op" and nx.v == ")" then return false end
    else return false end
    p = p + 1
  end
  return true
end

-- the number names of one scope: its statements from token A to B-1 (the bodies of def and class inside are other scopes)
local function numericScan(toks, a, b, shadow, outer, params)
  local assigns, bad, assigned = {}, {}, {}
  local function add(n, p1, p2, kind) assigns[#assigns + 1] = { n = n, p1 = p1, p2 = p2, kind = kind }; assigned[n] = true end
  local function badNames(p1, p2) for q = p1, p2 - 1 do if toks[q].t == "name" then bad[toks[q].v] = true; assigned[toks[q].v] = true end end end
  for q = a, b - 1 do
    local t = toks[q]
    if t.t == "op" and t.v == ":=" and toks[q - 1].t == "name" then bad[toks[q - 1].v] = true end
  end
  -- the end of the simple statement at Q (the token nl or ;), and the colon that ends the header of a compound statement
  local function stmtEnd(q)
    local d = 0
    while q < b do
      local t = toks[q]
      if t.t == "nl" or t.t == "eof" then return q end
      if t.t == "op" then
        if OPEN[t.v] then d = d + 1 elseif CLOSE[t.v] then d = d - 1 elseif t.v == ";" and d == 0 then return q end
      end
      q = q + 1
    end
    return b
  end
  local function headerColon(q)
    local d, lambdas = 0, 0
    while q < b do
      local t = toks[q]
      if t.t == "nl" then return nil end
      if t.t == "kw" and t.v == "lambda" then lambdas = lambdas + 1 end
      if t.t == "op" then
        if OPEN[t.v] then d = d + 1 elseif CLOSE[t.v] then d = d - 1
        elseif t.v == ":" and d == 0 then
          if lambdas == 0 then return q end
          lambdas = lambdas - 1
        end
      end
      q = q + 1
    end
  end
  local function blockAfter(colon)  -- the token after the body that follows a header colon
    if toks[colon + 1] and toks[colon + 1].t == "nl" then
      local q, depth = colon + 3, 1
      while q < b and depth > 0 do
        local t = toks[q]
        if t.t == "indent" then depth = depth + 1 elseif t.t == "dedent" then depth = depth - 1 end
        q = q + 1
      end
      return q
    end
    return stmtEnd(colon + 1) + 1
  end
  local p = a
  while p < b do
    local t = toks[p]
    if t.t == "nl" or t.t == "indent" or t.t == "dedent" or (t.t == "op" and t.v == ";") then p = p + 1
    elseif t.t == "op" and t.v == "@" then p = stmtEnd(p) + 1
    elseif t.t == "kw" and (t.v == "def" or t.v == "class") then
      if toks[p + 1].t == "name" then bad[toks[p + 1].v] = true; assigned[toks[p + 1].v] = true end
      local c = headerColon(p)
      p = c and blockAfter(c) or stmtEnd(p) + 1
    elseif t.t == "kw" and (t.v == "if" or t.v == "elif" or t.v == "else" or t.v == "while" or t.v == "for" or t.v == "with" or t.v == "try"
        or t.v == "except" or t.v == "finally" or t.v == "async") then
      local c = headerColon(p)
      if not c then p = stmtEnd(p) + 1
      else
        if t.v == "for" or (t.v == "async" and toks[p + 1].v == "for") then
          local f = t.v == "for" and p or p + 1
          local q, d = f + 1, 0
          while q < c and not (d == 0 and toks[q].t == "kw" and toks[q].v == "in") do
            local x = toks[q]
            if x.t == "op" then if OPEN[x.v] then d = d + 1 elseif CLOSE[x.v] then d = d - 1 end end
            q = q + 1
          end
          local r = toks[q + 1]
          if q == f + 2 and toks[f + 1].t == "name" and r and r.t == "name" and r.v == "range" and not shadow.range and toks[q + 2].v == "(" and toks[c - 1].v == ")" then
            -- the parenthesis that opens at q+2 closes just before the colon
            local d2, z = 0, q + 2
            repeat
              local x = toks[z]
              if x.t == "op" then if OPEN[x.v] then d2 = d2 + 1 elseif CLOSE[x.v] then d2 = d2 - 1 end end
              z = z + 1
            until d2 == 0 or z >= c
            if z == c then add(toks[f + 1].v, nil, nil, "range") else bad[toks[f + 1].v] = true; assigned[toks[f + 1].v] = true end
          else badNames(f + 1, q) end
        elseif t.v == "with" or t.v == "except" then
          for q = p, c do if toks[q].t == "kw" and toks[q].v == "as" then badNames(q + 1, q + 2) end end
        end
        p = c + 1
      end
    elseif t.t == "kw" and (t.v == "import" or t.v == "from" or t.v == "global" or t.v == "nonlocal" or t.v == "del") then
      local e = stmtEnd(p)
      badNames(p, e)
      p = e + 1
    else
      local e = stmtEnd(p)
      local eqs, aug, d = {}, nil, 0
      for q = p, e - 1 do
        local x = toks[q]
        if x.t == "op" then
          if OPEN[x.v] then d = d + 1 elseif CLOSE[x.v] then d = d - 1
          elseif d == 0 and x.v == "=" then eqs[#eqs + 1] = q
          elseif d == 0 and not aug and #eqs == 0 and x.v:sub(-1) == "=" and #x.v >= 2 and x.v ~= "==" and x.v ~= "<=" and x.v ~= ">=" and x.v ~= "!=" then aug = q end
        elseif x.t == "kw" and x.v == "lambda" then break end
      end
      if #eqs > 0 then
        local s = p
        for _, q in ipairs(eqs) do
          local first, second = toks[s], toks[s + 1]
          if first.t == "name" and (s + 1 == q or (second.t == "op" and second.v == ":")) then add(first.v, eqs[#eqs] + 1, e)
          elseif first.t == "name" and second.t == "op" and (second.v == "." or second.v == "[") then
            local tuple = false
            local d3 = 0
            for z = s, q - 1 do
              local x = toks[z]
              if x.t == "op" then if OPEN[x.v] then d3 = d3 + 1 elseif CLOSE[x.v] then d3 = d3 - 1 elseif x.v == "," and d3 == 0 then tuple = true end end
            end
            if tuple then badNames(s, q) end
          else badNames(s, q) end
          s = q + 1
        end
      elseif aug then
        if aug == p + 1 and toks[p].t == "name" then add(toks[p].v, aug + 1, e, toks[aug].v) end
      end
      p = e + 1
    end
  end
  local N = {}
  for _, as in ipairs(assigns) do N[as.n] = true end
  for n in pairs(N) do if bad[n] or outer[n] or (params and params[n]) then N[n] = nil end end
  repeat
    local changed = false
    for _, as in ipairs(assigns) do
      if N[as.n] then
        local ok
        if as.kind == "range" then ok = true
        elseif as.kind then ok = AUGNUM[as.kind] and numericSpan(toks, as.p1, as.p2, N, shadow)
        else ok = numericSpan(toks, as.p1, as.p2, N, shadow) end
        if not ok then N[as.n] = nil; changed = true end
      end
    end
  until not changed
  return N, assigned
end

-- ---------------------------------------------------------------- compiler
local function compileText(src, chunkName)
  local toks, pos = lex(src), 1
  local tok = toks[1]
  local out = {}
  local scope = { kind = "module", locals = {}, globals = {}, closure = 0 }
  local shadow, outerNames = programFacts(toks)
  scope.nums, scope.assigned = numericScan(toks, 1, #toks, shadow, outerNames)
  -- texts of expressions known to be numbers (the value is the scope they belong to, or true for a literal), their bound, and/or parts
  local NUM, BND, ANDOR = {}, {}, {}
  local loops = {}
  local labelN, tmpN = 0, 0
  local lastLv
  local function adv() pos = pos + 1; tok = toks[pos] end
  local function isOp(v) return tok.t == "op" and tok.v == v end
  local function isKw(v) return tok.t == "kw" and tok.v == v end
  local function err(msg) syntaxError(msg or "invalid syntax", tok.line, tok.col, tok.col and tok.ecol and math.max(1, tok.ecol - tok.col + 1) or 1) end
  local function acceptOp(v) if isOp(v) then adv(); return true end end
  local function acceptKw(v) if isKw(v) then adv(); return true end end
  local function expectOp(v) if not acceptOp(v) then err("expected '" .. v .. "'") end end
  local function expectKw(v) if not acceptKw(v) then err("expected '" .. v .. "'") end end
  local function name() if tok.t ~= "name" then err() end local v = tok.v; adv(); return v end
  local function tmp() tmpN = tmpN + 1; return "_t" .. tmpN end
  local function emit(s) out[#out + 1] = s end
  local function capture(fn)
    local saved = out
    out = {}
    fn()
    local r = table.concat(out, "\n")
    out = saved
    return r
  end
  local function str(s) return string.format("%q", s):gsub("\\\n", "\\n"):gsub("\r", "\\r") .. "" end

  local function declare(n)
    if scope.kind == "module" or scope.globals[n] then return end
    scope.locals[n] = true
  end
  local function nameRef(n)
    if scope.kind == "class" and scope.locals[n] then return "c_" .. n end
    return mangle(n)
  end
  -- is the name N (as read here) one of the number names of the scope it belongs to
  local function numName(n)
    if scope.kind == "class" then return false end
    local s = scope
    while s do
      if s.kind ~= "class" then
        if s.globals[n] then return false end
        if (s.params and s.params[n]) or s.locals[n] or (s.assigned and s.assigned[n]) then return s.nums and s.nums[n] or false end
      end
      s = s.parent
    end
    return false
  end
  local function isNum(c) local v = NUM[c]; return v == true or (v ~= nil and v == scope) end
  local function markNum(c, bound) NUM[c] = scope; BND[c] = bound; return c end
  local function intLit(c) return c:match("^%d+$") and math.tointeger(tonumber(c)) end
  local function floatLit(c) return c:match("^[%d%.]+[eE]?[%-+]?%d*$") and c:find("[%.eE]") and tonumber(c) end
  local function simpleT(c) return c:match("^[%a_][%w_]*$") or intLit(c) end
  local B62, B61 = 4611686018427387904, 2305843009213693952
  -- Lua for "a OP b" when both are numbers: plain arithmetic, with a range check where an integer could overflow (then the helper
  -- makes a float of it as before). Nil when one of them is not known to be a number.
  local HELPER = { ["+"] = "R_add", ["-"] = "R_sub", ["*"] = "R_mul", ["/"] = "R_div", ["//"] = "R_idiv", ["%"] = "R_mod", ["**"] = "R_pow" }
  local function numBin(op, a, b)
    if not (isNum(a) and isNum(b)) then return nil end
    local ba, bb = BND[a], BND[b]
    local fa, fb = floatLit(a), floatLit(b)
    local helper = HELPER[op] and (HELPER[op] .. "(" .. a .. "," .. b .. ")")
    local exact = "(" .. a .. op .. b .. ")"
    if op == "+" or op == "-" or op == "*" then
      if fa or fb then return markNum(exact) end
      local conds = {}
      local function need(x, L)
        if not simpleT(x) then return false end
        local c = x .. "<" .. L .. " and " .. x .. ">-" .. L
        if conds[1] ~= c then conds[#conds + 1] = c end
        return true
      end
      if op == "*" then
        if ba and bb and (ba == 0 or bb <= math.maxinteger // ba) then return markNum(exact, ba * bb) end
        local ok
        if ba and ba < B62 then ok = need(b, B62 // math.max(ba, 1))
        elseif bb and bb < B62 then ok = need(a, B62 // math.max(bb, 1))
        else ok = need(a, 2147483648) and need(b, 2147483648) end
        if not ok then return markNum(helper) end
      else
        -- an integer result stays below 2^63 when the bounds add up to less
        if ba and bb and ba <= math.maxinteger - bb then return markNum(exact, ba + bb) end
        if not ((ba and ba < B61) or need(a, B61)) or not ((bb and bb < B61) or need(b, B61)) then return markNum(helper) end
      end
      -- the checked form: an integer result is below 2^62 (a float needs no bound)
      return markNum("((" .. table.concat(conds, " and ") .. ") and " .. exact .. " or " .. helper .. ")", B62)
    end
    local kb = intLit(b) or fb
    if (op == "%" or op == "//" or op == "/") and kb and kb ~= 0 then
      local bound
      if op == "%" and intLit(b) then bound = kb elseif op == "//" and ba and intLit(b) then bound = ba // kb + 1 end
      return markNum(exact, bound)
    end
    return helper and markNum(helper) or nil
  end

  local testExpr, testList, parseLambda, suite, statement, comprehension, parseArgsCall

  local function assign(lv, v)
    if not lv then err("cannot assign to expression") end
    if lv.k == "name" then
      declare(lv.n)
      emit(nameRef(lv.n) .. " = " .. v)
    elseif lv.k == "attr" then emit("R_SA(" .. lv.o .. "," .. str(lv.n) .. "," .. v .. ")")
    elseif lv.k == "idx" then emit("R_SI(" .. lv.o .. "," .. lv.i .. "," .. v .. ")")
    elseif lv.k == "tuple" then
      local t = tmp()
      local star
      for i, it in ipairs(lv.items) do if it.star then star = i end end
      emit("do local " .. t .. " = R_UNP(" .. v .. "," .. #lv.items .. "," .. tostring(star or "nil") .. ")")
      for i, it in ipairs(lv.items) do assign(it.star and it.lv or it, t .. "[" .. i .. "]") end
      emit("end")
    else err("cannot assign") end
  end

  -- f-string: pieces of text and expressions, compiled by a parser of their own text
  local function fstring(t)
    local s, parts, buf, i = t.v, {}, {}, 1
    local function flush()
      if #buf > 0 then
        local text = table.concat(buf)
        parts[#parts + 1] = str(t.raw and text or unescape(text))
        buf = {}
      end
    end
    while i <= #s do
      local c = s:sub(i, i)
      if c == "{" and s:sub(i + 1, i + 1) == "{" then buf[#buf + 1] = "{"; i = i + 2
      elseif c == "}" and s:sub(i + 1, i + 1) == "}" then buf[#buf + 1] = "}"; i = i + 2
      elseif c == "{" then
        flush()
        local depth, j, q = 0, i + 1, nil
        local exprEnd, specStart, conv
        while j <= #s do
          local d = s:sub(j, j)
          if q then if d == q then q = nil end
          elseif d == "'" or d == '"' then q = d
          elseif d == "(" or d == "[" or d == "{" then depth = depth + 1
          elseif d == ")" or d == "]" then depth = depth - 1
          elseif d == "}" then
            if depth == 0 then break end
            depth = depth - 1
          elseif d == ":" and depth == 0 then specStart = j; break
          elseif d == "!" and depth == 0 and s:sub(j + 1, j + 1) ~= "=" then exprEnd = j; conv = s:sub(j + 1, j + 1); j = j + 1 end
          j = j + 1
        end
        local exprText = s:sub(i + 1, (exprEnd or j) - 1)
        local spec = ""
        local specExpr
        if specStart then
          local k, d2 = specStart + 1, 0
          while k <= #s do
            local d = s:sub(k, k)
            if d == "{" then d2 = d2 + 1 elseif d == "}" then if d2 == 0 then break end d2 = d2 - 1 end
            k = k + 1
          end
          spec = s:sub(specStart + 1, k - 1)
          j = k
          if spec:find("{", 1, true) then specExpr = fstring({ v = spec }) end
        end
        local selfDoc = exprText:match("^(.-)=%s*$")
        if selfDoc then parts[#parts + 1] = str(exprText); exprText = selfDoc end
        local savedT, savedP, savedTok = toks, pos, tok
        toks = lex(exprText .. "\n"); pos = 1; tok = toks[1]
        local code = testList()
        toks, pos, tok = savedT, savedP, savedTok
        if conv == "r" or (selfDoc and not specStart and not conv) then code = "R_repr(" .. code .. ")" elseif conv == "s" then code = "R_str(" .. code .. ")" end
        parts[#parts + 1] = "R_fmt(" .. code .. "," .. (specExpr or str(spec)) .. ")"
        i = j + 1
      else buf[#buf + 1] = c; i = i + 1 end
    end
    flush()
    if #parts == 0 then return '""' end
    return "(" .. table.concat(parts, "..") .. ")"
  end

  -- a function: parameters, body; returns the Lua text of a function value
  local function functionBody(params, parseBody, isMethodClass, bodyFrom, bodyTo)
    local saved, savedLoops = scope, loops
    scope = { kind = "function", locals = {}, globals = {}, closure = 0, parent = saved, first = params.names[1], cls = isMethodClass }
    loops = {}
    for _, p in ipairs(params.names) do scope.locals[p] = nil end
    local paramSet = {}
    for _, p in ipairs(params.names) do paramSet[p] = true end
    if params.star then paramSet[params.star] = true end
    if params.kwstar then paramSet[params.kwstar] = true end
    for _, p in ipairs(params.kwonly) do paramSet[p] = true end
    scope.params = paramSet
    if bodyFrom then scope.nums, scope.assigned = numericScan(toks, bodyFrom, bodyTo, shadow, outerNames, paramSet) end
    local body = capture(parseBody)
    local locals = {}
    for n in pairs(scope.locals) do if not paramSet[n] then locals[#locals + 1] = mangle(n) end end
    table.sort(locals)
    local isGen = scope.isGen
    scope, loops = saved, savedLoops
    local plist = {}
    for _, p in ipairs(params.names) do plist[#plist + 1] = mangle(p) end
    if params.star then plist[#plist + 1] = "..." end
    local pro = {}
    for i, p in ipairs(params.names) do
      local d = params.defaults[p]
      if d then pro[#pro + 1] = "if " .. mangle(p) .. "==nil then " .. mangle(p) .. "=" .. d .. " end" end
    end
    if params.star then pro[#pro + 1] = "local " .. mangle(params.star) .. "=R_tuple{...}" end
    if params.kwstar or #params.kwonly > 0 then
      pro[#pro + 1] = "local _kw=R_takekw()"
      for _, p in ipairs(params.kwonly) do
        local d = params.defaults[p]
        pro[#pro + 1] = "local " .. mangle(p) .. "=R_kwget(_kw," .. str(p) .. "," .. (d or "nil") .. ")"
      end
      if params.kwstar then pro[#pro + 1] = "local " .. mangle(params.kwstar) .. "=R_kwdict(_kw)" end
    end
    if #locals > 0 then
      -- more than 180 locals do not fit a Lua function: the rest live in a table (rare; a huge function)
      pro[#pro + 1] = "local " .. table.concat(locals, ",", 1, math.min(#locals, 180))
    end
    local text
    if isGen then
      text = "function(" .. table.concat(plist, ",") .. ")\n" .. table.concat(pro, "\n") .. "\nreturn R_gen(function()\n" .. body .. "\nend)\nend"
    else
      text = "function(" .. table.concat(plist, ",") .. ")\n" .. table.concat(pro, "\n") .. "\n" .. body .. "\nreturn None\nend"
    end
    local names = {}
    for _, p in ipairs(params.names) do names[#names + 1] = str(p) end
    local info = "{names={" .. table.concat(names, ",") .. "},kw=" .. tostring((params.kwstar or #params.kwonly > 0) and true or false) .. "}"
    return "R_def(" .. text .. "," .. info .. ")"
  end

  local function parseParams(closer)
    local p = { names = {}, defaults = {}, kwonly = {} }
    local afterStar = false
    while not (tok.t == "op" and tok.v == closer) do
      if acceptOp("*") then
        if tok.t == "name" then p.star = name() end
        afterStar = true
        if acceptOp(":") then testExpr() end
      elseif acceptOp("**") then
        p.kwstar = name()
        if acceptOp(":") then testExpr() end
      elseif acceptOp("/") then
      else
        local n = name()
        if closer == ")" and acceptOp(":") then testExpr() end
        if acceptOp("=") then p.defaults[n] = testExpr() end
        if afterStar then p.kwonly[#p.kwonly + 1] = n else p.names[#p.names + 1] = n end
      end
      if not acceptOp(",") then break end
    end
    return p
  end

  parseLambda = function()
    adv()
    local params = parseParams(":")
    expectOp(":")
    local f = functionBody(params, function() emit("do return " .. testExpr() .. " end") end)
    return f
  end

  -- what follows the first element of [x for ...]: returns the code that fills the result, wrapped in a function
  comprehension = function(startPos, kind)
    -- the element expression was parsed once to find the "for": it is parsed again inside the new scope
    local saved, savedLoops = scope, loops
    scope = { kind = "function", locals = {}, globals = {}, closure = 0, parent = saved, first = saved.first, cls = saved.cls }
    loops = {}
    local endElem = pos
    local body = capture(function()
      local opens = 0
      local function clause()
        if acceptKw("async") then end
        expectKw("for")
        local targets = {}
        repeat
          local star = false
          local code = (function()
            local c = nil
            -- target list: names, attributes, tuples
            local function target()
              if acceptOp("(") then
                local items = {}
                repeat items[#items + 1] = target() until not acceptOp(",") or isOp(")")
                expectOp(")")
                return { k = "tuple", items = items }
              end
              local n = name()
              return { k = "name", n = n }
            end
            return target()
          end)()
          targets[#targets + 1] = code
        until not acceptOp(",") or isKw("in")
        expectKw("in")
        local it
        -- the source: an expression without a conditional
        local src = (function()
          local a = P._orTest()
          return a
        end)()
        local t = tmp()
        emit("for " .. t .. " in R_iter(" .. src .. ") do")
        opens = opens + 1
        if #targets == 1 then
          assign(targets[1], t)
        else
          assign({ k = "tuple", items = targets }, t)
        end
        while isKw("if") do
          adv()
          local c = P._orTestCond()
          emit("if " .. c .. " then")
          opens = opens + 1
        end
        if isKw("for") or isKw("async") then return clause() end
      end
      clause()
      local afterClauses = pos
      local afterTok = tok
      -- back to the element
      pos = startPos; tok = toks[pos]
      local a, b = testExpr()
      if kind == "dict" then
        expectOp(":")
        b = testExpr()
        emit("R_dset(_r," .. a .. "," .. b .. ")")
      elseif kind == "set" then emit("R_sadd(_r," .. a .. ")")
      elseif kind == "gen" then scope.isGen = true; emit("R_yield(" .. a .. ")")
      else emit("_r[#_r+1]=" .. a) end
      pos = afterClauses; tok = afterTok
      for _ = 1, opens do emit("end") end
    end)
    local locals = {}
    for n in pairs(scope.locals) do locals[#locals + 1] = mangle(n) end
    local decl = #locals > 0 and ("local " .. table.concat(locals, ",") .. "\n") or ""
    scope, loops = saved, savedLoops
    if kind == "gen" then return "R_gen(function()\n" .. decl .. body .. "\nend)" end
    local init = kind == "dict" and "R_dict()" or (kind == "set" and "R_set{}" or "R_list{}")
    return "(function()\n" .. decl .. "local _r=" .. init .. "\n" .. body .. "\nreturn _r\nend)()"
  end

  -- skips an expression at token level, to see what comes after it (a comprehension's "for")
  local function skipToFor(closeBracket)
    local depth, p = 0, pos
    while true do
      local t = toks[p]
      if t.t == "eof" then return false end
      if t.t == "op" then
        if t.v == "(" or t.v == "[" or t.v == "{" then depth = depth + 1
        elseif t.v == ")" or t.v == "]" or t.v == "}" then
          if depth == 0 then return false end
          depth = depth - 1
        elseif depth == 0 and t.v == "," then return false end
      elseif depth == 0 and t.t == "kw" and t.v == "for" then return p
      elseif depth == 0 and t.t == "kw" and t.v == "lambda" then
        -- the colon of a lambda does not matter here
      end
      p = p + 1
    end
  end

  local function atom()
    local t = tok
    lastLv = nil
    if t.t == "name" then
      adv()
      lastLv = { k = "name", n = t.v }
      local r = nameRef(t.v)
      if numName(t.v) then markNum(r) end
      return r
    elseif t.t == "num" then
      adv()
      local v = math.tointeger(tonumber(t.v))
      NUM[t.v] = true
      BND[t.v] = v and math.abs(v) or nil
      return t.v
    elseif t.t == "str" then
      adv()
      local s = t.v
      local parts = nil
      while tok.t == "str" or tok.t == "fstr" do
        parts = parts or { str(s) }
        parts[#parts + 1] = tok.t == "str" and str(tok.v) or fstring(tok)
        adv()
      end
      lastLv = nil
      if parts then return "(" .. table.concat(parts, "..") .. ")" end
      return str(s)
    elseif t.t == "fstr" then
      local parts = {}
      while tok.t == "str" or tok.t == "fstr" do
        parts[#parts + 1] = tok.t == "str" and str(tok.v) or fstring(tok)
        adv()
      end
      lastLv = nil
      return "(" .. table.concat(parts, "..") .. ")"
    elseif t.t == "kw" then
      if t.v == "True" then adv(); return "true"
      elseif t.v == "False" then adv(); return "false"
      elseif t.v == "None" then adv(); return "None"
      elseif t.v == "lambda" then return parseLambda()
      elseif t.v == "yield" then
        adv()
        local fn = scope
        fn.isGen = true
        if acceptKw("from") then return "R_yieldfrom(" .. testExpr() .. ")" end
        if tok.t == "nl" or isOp(")") or isOp("=") then return "R_yield(None)" end
        return "R_yield(" .. testList() .. ")"
      elseif t.v == "await" then adv(); return testExpr()
      elseif t.v == "not" then adv(); return "(not " .. P._cond(P._notTest()) .. ")"
      end
      err()
    elseif t.t == "op" then
      if t.v == "(" then
        adv()
        if acceptOp(")") then lastLv = nil; return "R_tuple{}" end
        local start = pos
        if skipToFor() then
          local p = skipToFor()
          pos = p; tok = toks[pos]
          local c = comprehension(start, "gen")
          expectOp(")")
          lastLv = nil
          return c
        end
        local first = testList(true)
        local lv = lastLv
        expectOp(")")
        lastLv = lv
        if isNum(first) then return markNum("(" .. first .. ")", BND[first]) end
        if ANDOR[first] then ANDOR["(" .. first .. ")"] = ANDOR[first] end
        return "(" .. first .. ")"
      elseif t.v == "[" then
        adv()
        if acceptOp("]") then lastLv = nil; return "R_list{}" end
        local start = pos
        local p = skipToFor()
        if p then
          pos = p; tok = toks[pos]
          local c = comprehension(start, "list")
          expectOp("]")
          lastLv = nil
          return c
        end
        local items, lvs, hasStar = {}, {}, false
        repeat
          if isOp("]") then break end
          if acceptOp("*") then
            items[#items + 1] = { star = P._orTest() }; hasStar = true
          else
            items[#items + 1] = testExpr(); lvs[#lvs + 1] = lastLv
          end
        until not acceptOp(",")
        expectOp("]")
        local listLv = { k = "tuple", items = lvs }
        if hasStar then
          local parts = {}
          for i, it in ipairs(items) do parts[i] = type(it) == "table" and ("R_stararg(" .. it.star .. ")") or ("{" .. it .. "}") end
          lastLv = nil
          return "R_list(R_concat(" .. table.concat(parts, ",") .. "))"
        end
        lastLv = #lvs == #items and listLv or nil
        return "R_list{" .. table.concat(items, ",") .. "}"
      elseif t.v == "{" then
        adv()
        if acceptOp("}") then lastLv = nil; return "R_dict()" end
        if isOp("**") then
          local parts = {}
          repeat
            if isOp("}") then break end
            if acceptOp("**") then parts[#parts + 1] = "{m=" .. P._orTest() .. "}"
            else
              local k = testExpr(); expectOp(":"); local v = testExpr()
              parts[#parts + 1] = "{k=" .. k .. ",v=" .. v .. "}"
            end
          until not acceptOp(",")
          expectOp("}")
          lastLv = nil
          return "R_dictmerge(" .. table.concat(parts, ",") .. ")"
        end
        local start = pos
        local p = skipToFor()
        -- a dict comprehension has ':' before the for
        if p then
          local isDict = false
          local d = 0
          for q = pos, p do
            local x = toks[q]
            if x.t == "op" then
              if x.v == "(" or x.v == "[" or x.v == "{" then d = d + 1
              elseif x.v == ")" or x.v == "]" or x.v == "}" then d = d - 1
              elseif x.v == ":" and d == 0 then isDict = true end
            end
          end
          pos = p; tok = toks[pos]
          local c = comprehension(start, isDict and "dict" or "set")
          expectOp("}")
          lastLv = nil
          return c
        end
        local first = testExpr()
        if acceptOp(":") then
          local parts = { first, testExpr() }
          while acceptOp(",") do
            if isOp("}") then break end
            local k = testExpr(); expectOp(":")
            parts[#parts + 1] = k; parts[#parts + 1] = testExpr()
          end
          expectOp("}")
          lastLv = nil
          return "R_dictlit(" .. table.concat(parts, ",") .. ")"
        end
        local items = { first }
        while acceptOp(",") do
          if isOp("}") then break end
          items[#items + 1] = testExpr()
        end
        expectOp("}")
        lastLv = nil
        return "R_setlit{" .. table.concat(items, ",") .. "}"
      elseif t.v == "..." then adv(); return "None"
      end
    end
    err()
  end

  -- arguments of a call. Returns the positional text (possibly with a star) and the keyword text
  parseArgsCall = function()
    local pos_, kw, stars, kwstars = {}, {}, false, {}
    local single
    while not isOp(")") do
      if acceptOp("*") then pos_[#pos_ + 1] = { star = P._orTest() }; stars = true
      elseif acceptOp("**") then kwstars[#kwstars + 1] = P._orTest()
      elseif tok.t == "name" and toks[pos + 1].t == "op" and toks[pos + 1].v == "=" then
        local n = name(); adv()
        kw[#kw + 1] = "[" .. str(n) .. "]=" .. testExpr()
      else
        local startP = pos
        local p = skipToFor()
        if p and #pos_ == 0 then
          pos = p; tok = toks[pos]
          pos_[1] = comprehension(startP, "gen")
        else
          pos_[#pos_ + 1] = testExpr()
        end
      end
      if not acceptOp(",") then break end
    end
    expectOp(")")
    local posText
    if stars then
      local parts = {}
      for i, it in ipairs(pos_) do parts[i] = type(it) == "table" and ("R_stararg(" .. it.star .. ")") or ("{" .. it .. "}") end
      posText = "R_concat(" .. table.concat(parts, ",") .. ")"
    else
      posText = nil
    end
    local plain = {}
    if not stars then for i, it in ipairs(pos_) do plain[i] = it end end
    local kwText
    if #kw > 0 or #kwstars > 0 then
      kwText = "{" .. table.concat(kw, ",") .. "}"
      for _, s in ipairs(kwstars) do kwText = "R_kwmerge(" .. kwText .. "," .. s .. ")" end
    end
    return plain, posText, kwText
  end

  local function primary()
    local isCallName = tok.t == "name" and tok.v
    local code = atom()
    while true do
      if isOp(".") then
        adv()
        local n = tok.v
        if tok.t ~= "name" and tok.t ~= "kw" then err() end
        adv()
        if isOp("(") then
          adv()
          local plain, posText, kwText = parseArgsCall()
          if kwText or posText then
            code = "R_CMK(" .. code .. "," .. str(n) .. "," .. (posText or ("{" .. table.concat(plain, ",") .. "}")) .. "," .. (kwText or "nil") .. ")"
          else
            local a = #plain > 0 and ("," .. table.concat(plain, ",")) or ""
            code = "R_CM(" .. code .. "," .. str(n) .. a .. ")"
          end
          lastLv = nil
        else
          lastLv = { k = "attr", o = code, n = n }
          if code == "self" and scope.cls and scope.first == "self" then
            -- self of a method is an instance: its own attributes are read straight (false and missing go to the helper)
            code = "(R_rawget(self," .. str(n) .. ") or R_GA(self," .. str(n) .. "))"
          else
            code = "R_GA(" .. code .. "," .. str(n) .. ")"
          end
        end
        isCallName = nil
      elseif isOp("(") then
        adv()
        if isCallName == "super" and isOp(")") and scope.kind == "function" then
          adv()
          code = "R_super(c_," .. mangle(scope.first or "self") .. ")"
        else
          local plain, posText, kwText = parseArgsCall()
          if kwText or posText then
            code = "R_CK(" .. code .. "," .. (posText or ("{" .. table.concat(plain, ",") .. "}")) .. "," .. (kwText or "nil") .. ")"
          else
            code = code .. "(" .. table.concat(plain, ",") .. ")"
            if code:sub(1, 8) == "function" or code:sub(1, 5) == "R_def" then code = "(" .. code .. ")" end
          end
        end
        lastLv = nil
        isCallName = nil
      elseif isOp("[") then
        adv()
        local function sliceOrIndex()
          local a, b, c = "None", "None", "None"
          local isSlice = false
          if not isOp(":") then a = testExpr() end
          if acceptOp(":") then
            isSlice = true
            if not (isOp(":") or isOp("]") or isOp(",")) then b = testExpr() end
            if acceptOp(":") then
              if not (isOp("]") or isOp(",")) then c = testExpr() end
            end
          end
          if isSlice then return "R_slice(" .. a .. "," .. b .. "," .. c .. ")" end
          return a
        end
        local i = sliceOrIndex()
        if isOp(",") then
          local items = { i }
          while acceptOp(",") do
            if isOp("]") then break end
            items[#items + 1] = sliceOrIndex()
          end
          i = "R_tuple{" .. table.concat(items, ",") .. "}"
        end
        expectOp("]")
        lastLv = { k = "idx", o = code, i = i }
        code = "R_GI(" .. code .. "," .. i .. ")"
        isCallName = nil
      else
        break
      end
    end
    return code
  end

  local function power()
    local a = primary()
    if isOp("**") then
      adv()
      local b = P._unary()
      lastLv = nil
      return "R_pow(" .. a .. "," .. b .. ")"
    end
    return a
  end
  local function unary()
    if isOp("-") then
      adv()
      local c = unary()
      lastLv = nil
      if isNum(c) then return markNum("(-" .. c .. ")", BND[c]) end
      return "R_neg(" .. c .. ")"
    end
    if isOp("+") then adv(); local c = unary(); lastLv = nil; return c end
    if isOp("~") then adv(); local c = unary(); lastLv = nil; return "(~" .. c .. ")" end
    return power()
  end
  P._unary = unary
  local function binary(next_, ops)
    return function()
      local a = next_()
      while tok.t == "op" and ops[tok.v] do
        local f, op = ops[tok.v], tok.v
        adv()
        local b = next_()
        local fast = numBin(op, a, b)
        if fast then a = fast
        else
          local both = isNum(a) and isNum(b)
          a = f .. "(" .. a .. "," .. b .. ")"
          if both and op ~= "@" then markNum(a) end
        end
        lastLv = nil
      end
      return a
    end
  end
  local term = binary(unary, { ["*"] = "R_mul", ["/"] = "R_div", ["//"] = "R_idiv", ["%"] = "R_mod", ["@"] = "R_matmul" })
  local arith = binary(term, { ["+"] = "R_add", ["-"] = "R_sub" })
  local shift = binary(arith, { ["<<"] = "R_shl", [">>"] = "R_shr" })
  local bitand = binary(shift, { ["&"] = "R_band" })
  local bitxor = binary(bitand, { ["^"] = "R_bxor" })
  local bitor = binary(bitxor, { ["|"] = "R_bor" })
  local CMP = { ["<"] = "R_lt", [">"] = "R_gt", ["<="] = "R_le", [">="] = "R_ge", ["=="] = "R_eq", ["!="] = "R_ne" }
  local BOOLS = {}  -- texts known to be Lua booleans
  local function isBool(c) return BOOLS[c] or c == "true" or c == "false" end
  local function mkBool(c) BOOLS[c] = true; return c end
  local function cmpOp()
    if tok.t == "op" and CMP[tok.v] then local f = CMP[tok.v]; adv(); return f end
    if isKw("in") then adv(); return "R_in" end
    if isKw("is") then
      adv()
      if acceptKw("not") then return "R_isnot" end
      return "R_is"
    end
    if isKw("not") and toks[pos + 1].t == "kw" and toks[pos + 1].v == "in" then adv(); adv(); return "R_notin" end
  end
  local function comparison()
    local a = bitor()
    local f = cmpOp()
    if not f then return a end
    lastLv = nil
    local b = bitor()
    local g = cmpOp()
    local LUACMP = { R_lt = "<", R_gt = ">", R_le = "<=", R_ge = ">=", R_eq = "==", R_ne = "~=" }
    if not g and LUACMP[f] and isNum(a) and isNum(b) then lastLv = nil; return mkBool("(" .. a .. LUACMP[f] .. b .. ")") end
    if not g then lastLv = nil; return mkBool(f .. "(" .. a .. "," .. b .. ")") end
    -- a chain: a < b < c, each middle once
    local parts = { "local _a=" .. a, "local _b=" .. b, "if not " .. f .. "(_a,_b) then return false end" }
    while g do
      local c = bitor()
      parts[#parts + 1] = "local _c=" .. c
      parts[#parts + 1] = "if not " .. g .. "(_b,_c) then return false end"
      parts[#parts + 1] = "_b=_c"
      g = cmpOp()
    end
    lastLv = nil
    return mkBool("(function() " .. table.concat(parts, " ") .. " return true end)()")
  end
  local function cond(c)
    if isBool(c) then return c end
    local ao = ANDOR[c]
    if ao then return "(" .. cond(ao[2]) .. " " .. ao[1] .. " " .. cond(ao[3]) .. ")" end
    if isNum(c) then return "(" .. c .. "~=0)" end
    return "R_T(" .. c .. ")"
  end
  P._cond = cond
  local function notTest()
    if isKw("not") then
      adv()
      local c = notTest()
      lastLv = nil
      return mkBool("(not " .. cond(c) .. ")")
    end
    return comparison()
  end
  P._notTest = notTest
  local function isSimple(c) return c:match("^[%a_][%w_]*$") or tonumber(c) or c == "None" or c:match('^"[^"]*"$') end
  local function andTest()
    local a = notTest()
    while isKw("and") do
      adv()
      local b = notTest()
      lastLv = nil
      if isBool(a) and isBool(b) then a = mkBool("(" .. a .. " and " .. b .. ")")
      else
        local whole = isSimple(b) and ("R_andv(" .. a .. "," .. b .. ")") or ("R_and(" .. a .. ",function() return " .. b .. " end)")
        ANDOR[whole] = { "and", a, b }
        a = whole
      end
    end
    return a
  end
  local function orTest()
    local a = andTest()
    while isKw("or") do
      adv()
      local b = andTest()
      lastLv = nil
      if isBool(a) and isBool(b) then a = mkBool("(" .. a .. " or " .. b .. ")")
      else
        local whole = isSimple(b) and ("R_orv(" .. a .. "," .. b .. ")") or ("R_or(" .. a .. ",function() return " .. b .. " end)")
        ANDOR[whole] = { "or", a, b }
        a = whole
      end
    end
    return a
  end
  P._orTest = orTest
  P._orTestCond = function() return cond(orTest()) end
  testExpr = function()
    if isKw("lambda") then lastLv = nil; return parseLambda() end
    local a = orTest()
    if isOp(":=") then
      adv()
      local lv = lastLv
      local v = testExpr()
      if lv and lv.k == "name" then
        declare(lv.n)
        lastLv = nil
        return "(function() " .. nameRef(lv.n) .. "=" .. v .. " return " .. nameRef(lv.n) .. " end)()"
      end
      err()
    end
    if isKw("if") then
      adv()
      local c = cond(orTest())
      expectKw("else")
      local b = testExpr()
      lastLv = nil
      -- a value that is never false in Lua can stand in "c and a or b"
      if isNum(a) or a:sub(1, 1) == '"' or a == "None" or a == "true" then
        local r = "(" .. c .. " and " .. a .. " or " .. b .. ")"
        if isNum(a) and isNum(b) then markNum(r) end
        return r
      end
      if isSimple(a) and isSimple(b) then return "R_ifv(" .. c .. "," .. a .. "," .. b .. ")" end
      return "R_if(" .. c .. ",function() return " .. a .. " end,function() return " .. b .. " end)"
    end
    return a
  end
  testList = function(inParen)
    if isOp("*") then
      -- a starred target or a starred value in a tuple
      local items, lvs = {}, {}
      repeat
        if tok.t == "nl" or isOp(")") or isOp("=") then break end
        if acceptOp("*") then local c = orTest(); items[#items + 1] = { star = c }; lvs[#lvs + 1] = { star = true, lv = lastLv }
        else items[#items + 1] = testExpr(); lvs[#lvs + 1] = lastLv end
      until not acceptOp(",")
      lastLv = { k = "tuple", items = lvs }
      local parts = {}
      for i, it in ipairs(items) do parts[i] = type(it) == "table" and ("R_stararg(" .. it.star .. ")") or ("{" .. it .. "}") end
      return "R_tuple(R_concat(" .. table.concat(parts, ",") .. "))"
    end
    local first = testExpr()
    local lv = lastLv
    if not isOp(",") then lastLv = lv; return first end
    local items, lvs = { first }, { lv }
    local allLv = lv ~= nil
    local hasStar = false
    while acceptOp(",") do
      if tok.t == "nl" or isOp(")") or isOp("=") or isOp("]") or isOp(":") or tok.t == "eof" then break end
      if acceptOp("*") then
        local c = orTest()
        items[#items + 1] = { star = c }; lvs[#lvs + 1] = { star = true, lv = lastLv }; hasStar = true
      else
        items[#items + 1] = testExpr()
        if lastLv then lvs[#lvs + 1] = lastLv else allLv = false end
      end
    end
    lastLv = allLv and { k = "tuple", items = lvs } or nil
    if hasStar then
      local parts = {}
      for i, it in ipairs(items) do parts[i] = type(it) == "table" and ("R_stararg(" .. it.star .. ")") or ("{" .. it .. "}") end
      return "R_tuple(R_concat(" .. table.concat(parts, ",") .. "))"
    end
    return "R_tuple{" .. table.concat(items, ",") .. "}"
  end

  -- ---- statements ----
  local function flowReturn(v)
    if scope.closure > 0 then emit('do return "r",' .. v .. " end") else emit("do return " .. v .. " end") end
  end

  local function endStmt()
    if tok.t == "nl" then adv()
    elseif tok.t == "eof" or isOp(";") then
    else err() end
  end

  suite = function()
    expectOp(":")
    if tok.t == "nl" then
      adv()
      if tok.t ~= "indent" then err("expected an indented block") end
      adv()
      while tok.t ~= "dedent" and tok.t ~= "eof" do statement() end
      if tok.t == "dedent" then adv() end
    else
      statement(true)
    end
  end

  local function loopBody(parseBody, label)
    local record = { label = label, closure = scope.closure, usedCont = false }
    loops[#loops + 1] = record
    parseBody()
    loops[#loops] = nil
    return record
  end

  -- after a try closure: the flows it returned
  local function afterFlows(f, v)
    emit("if " .. f .. '=="r" then')
    flowReturn(v)
    emit("end")
    local l = loops[#loops]
    if l and l.closure < scope.closure + 1 then
      if scope.closure > l.closure then
        emit("if " .. f .. '=="b" then return "b" end')
        emit("if " .. f .. '=="c" then return "c" end')
      else
        emit("if " .. f .. '=="b" then BF_' .. l.label .. '=false break end')
        l.usedCont = true
        emit("if " .. f .. '=="c" then goto ' .. l.label .. " end")
      end
    end
  end

  local function tryStatement()
    adv()
    local line = tok.line
    -- body
    local function inClosure(fn)
      scope.closure = scope.closure + 1
      local text = capture(fn)
      scope.closure = scope.closure - 1
      return text
    end
    local bodyText = inClosure(function() suite() end)
    local handlers = {}
    while isKw("except") do
      adv()
      local cls, asName
      if not isOp(":") then
        cls = testExpr()
        if acceptKw("as") then asName = name() end
      end
      handlers[#handlers + 1] = { cls = cls, as = asName }
      local h = handlers[#handlers]
      if asName then declare(asName) end
      h.startPos = pos
      -- the handler is compiled twice at most, so its text is made when the frame around it is known: once with a finally, in a closure
      h.text = nil
      h.tokPos = pos
      -- skip it for now
      local depth = 0
      if toks[pos].v == ":" then
        pos = pos + 1
        if toks[pos].t == "nl" then
          pos = pos + 2  -- nl, indent
          depth = 1
          while depth > 0 do
            local t = toks[pos]
            if t.t == "indent" then depth = depth + 1 elseif t.t == "dedent" then depth = depth - 1 end
            if t.t == "eof" then break end
            pos = pos + 1
          end
        else
          while toks[pos].t ~= "nl" and toks[pos].t ~= "eof" do pos = pos + 1 end
          pos = pos + 1
        end
      end
      tok = toks[pos]
    end
    local elsePos
    if isKw("else") then
      adv()
      elsePos = pos
      if toks[pos].v == ":" then
        pos = pos + 1
        if toks[pos].t == "nl" then
          pos = pos + 2
          local depth = 1
          while depth > 0 do
            local t = toks[pos]
            if t.t == "indent" then depth = depth + 1 elseif t.t == "dedent" then depth = depth - 1 end
            if t.t == "eof" then break end
            pos = pos + 1
          end
        else
          while toks[pos].t ~= "nl" and toks[pos].t ~= "eof" do pos = pos + 1 end
          pos = pos + 1
        end
      end
      tok = toks[pos]
    end
    local finallyPos
    if isKw("finally") then
      adv()
      finallyPos = pos
      if toks[pos].v == ":" then
        pos = pos + 1
        if toks[pos].t == "nl" then
          pos = pos + 2
          local depth = 1
          while depth > 0 do
            local t = toks[pos]
            if t.t == "indent" then depth = depth + 1 elseif t.t == "dedent" then depth = depth - 1 end
            if t.t == "eof" then break end
            pos = pos + 1
          end
        else
          while toks[pos].t ~= "nl" and toks[pos].t ~= "eof" do pos = pos + 1 end
          pos = pos + 1
        end
      end
      tok = toks[pos]
    end
    local afterPos = pos
    local function runAt(p)
      pos = p; tok = toks[pos]
      suite()
    end
    local function genCore()
      local ok, f, v = tmp(), tmp(), tmp()
      emit("do local " .. ok .. "," .. f .. "," .. v .. " = R_pcall(function()\n" .. bodyText .. "\nend)")
      if #handlers > 0 then
        emit("if not " .. ok .. " then")
        emit("local _e = R_exc(" .. f .. ")")
        emit(f .. "=nil")
        local firstH = true
        for _, h in ipairs(handlers) do
          local test = h.cls and ("R_excmatch(_e," .. h.cls .. ")") or "true"
          emit((firstH and "if " or "elseif ") .. test .. " then")
          firstH = false
          if h.as then emit(nameRef(h.as) .. " = _e") end
          emit("R_curexc=_e")
          runAt(h.tokPos)
        end
        emit("else R_error(_e,0) end")
        if elsePos then
          emit("else")
          emit("if " .. f .. "==nil then")
          runAt(elsePos)
          emit("end")
          afterFlows(f, v)
          emit("end")
        else
          emit("else")
          afterFlows(f, v)
          emit("end")
        end
      else
        emit("if not " .. ok .. " then R_error(" .. f .. ",0) end")
        afterFlows(f, v)
      end
      emit("end")
    end
    if finallyPos then
      local ok, f, v = tmp(), tmp(), tmp()
      local text = inClosure(genCore)
      emit("do local " .. ok .. "," .. f .. "," .. v .. " = R_pcall(function()\n" .. text .. "\nend)")
      runAt(finallyPos)
      emit("if not " .. ok .. " then R_error(" .. f .. ",0) end")
      afterFlows(f, v)
      emit("end")
    else
      genCore()
    end
    pos = afterPos; tok = toks[pos]
  end

  local function importModule(dotted)
    return "R_import(" .. str(dotted) .. ")"
  end

  local function classStatement(decorators)
    adv()
    local n = name()
    local bases = {}
    if acceptOp("(") then
      while not isOp(")") do
        if tok.t == "name" and toks[pos + 1].v == "=" then adv(); adv(); testExpr()
        else bases[#bases + 1] = testExpr() end
        if not acceptOp(",") then break end
      end
      expectOp(")")
    end
    declare(n)
    local outerClass = scope.kind == "class"
    local saved, savedLoops = scope, loops
    scope = { kind = "class", locals = {}, globals = {}, closure = 0, parent = saved }
    loops = {}
    local body = capture(function() suite() end)
    local names = {}
    for k in pairs(scope.locals) do names[#names + 1] = k end
    table.sort(names)
    scope, loops = saved, savedLoops
    local decl = {}
    local store = {}
    for _, k in ipairs(names) do
      decl[#decl + 1] = "c_" .. k
      store[#store + 1] = "c_." .. mangle(k) .. "=c_" .. k
      if k ~= mangle(k) then store[#store] = "c_[" .. str(k) .. "]=c_" .. k end
    end
    local text = "R_class(" .. str(n) .. ",{" .. table.concat(bases, ",") .. "},function(c_)\n" ..
      (#decl > 0 and ("local " .. table.concat(decl, ",") .. "\n") or "") .. body .. "\n" .. table.concat(store, "\n") .. "\nend)"
    for i = #decorators, 1, -1 do text = decorators[i] .. "(" .. text .. ")" end
    emit(nameRef(n) .. " = " .. text)
  end

  local function defStatement(decorators)
    adv()
    local n = name()
    declare(n)
    expectOp("(")
    local params = parseParams(")")
    expectOp(")")
    if acceptOp("->") then testExpr() end
    local isMethod = scope.kind == "class"
    -- the body: from the colon to the end of its block
    local bodyTo = pos + 1
    if toks[pos + 1] and toks[pos + 1].t == "nl" then
      local depth = 0
      bodyTo = pos + 2
      repeat
        local x = toks[bodyTo]
        if x.t == "indent" then depth = depth + 1 elseif x.t == "dedent" then depth = depth - 1 end
        bodyTo = bodyTo + 1
      until depth == 0 or x.t == "eof"
    else
      while toks[bodyTo].t ~= "nl" and toks[bodyTo].t ~= "eof" do bodyTo = bodyTo + 1 end
    end
    local f = functionBody(params, function() suite() end, isMethod, pos + 1, bodyTo)
    -- the name of the function, for repr and __name__
    local text = "R_named(" .. f .. "," .. str(n) .. ")"
    for i = #decorators, 1, -1 do text = decorators[i] .. "(" .. text .. ")" end
    emit(nameRef(n) .. " = " .. text)
  end

  statement = function(simpleOnly)
    local t = tok
    if t.t == "nl" then adv(); return end
    emit("_L=" .. t.line)
    if t.t == "kw" then
      local v = t.v
      if v == "if" then
        adv()
        emit("if " .. cond(testExpr()) .. " then")
        suite()
        while isKw("elif") do
          adv()
          emit("elseif " .. cond(testExpr()) .. " then")
          suite()
        end
        if acceptKw("else") then emit("else"); suite() end
        emit("end")
        return
      elseif v == "while" then
        adv()
        labelN = labelN + 1
        local label = "cont_" .. labelN
        local c = cond(testExpr())
        local elseFlag
        local rec
        local text = capture(function() rec = loopBody(function() suite() end, label) end)
        if isKw("else") then
          adv()
          elseFlag = tmp()
          emit("do local " .. elseFlag .. "=true")
          emit("while " .. c .. " do")
          emit((text:gsub("BF_" .. label .. "=", elseFlag .. "=")))
          emit("::" .. label .. "::")
          emit("end")
          emit("if " .. elseFlag .. " then")
          suite()
          emit("end end")
          return
        end
        emit("while " .. c .. " do")
        emit(text)
        emit("::" .. label .. "::")
        emit("end")
        return
      elseif v == "for" then
        adv()
        labelN = labelN + 1
        local label = "cont_" .. labelN
        local lv = (function()
          local items = {}
          local function target()
            if acceptOp("(") or acceptOp("[") then
              local inner = {}
              repeat inner[#inner + 1] = target() until not acceptOp(",") or isOp(")") or isOp("]")
              adv()
              return { k = "tuple", items = inner }
            end
            if acceptOp("*") then return { star = true, lv = target() } end
            local save = primary()
            return lastLv
          end
          repeat items[#items + 1] = target() until not acceptOp(",") or isKw("in")
          if #items == 1 then return items[1] end
          return { k = "tuple", items = items }
        end)()
        expectKw("in")
        -- for x in range(...): a numeric for of Lua (range() is not made)
        local rangeArgs
        if tok.t == "name" and tok.v == "range" and not shadow.range and toks[pos + 1].v == "(" then
          local save = pos
          adv(); adv()
          local args = {}
          while not isOp(")") do
            if isOp("*") then break end
            args[#args + 1] = testExpr()
            if not acceptOp(",") then break end
          end
          if acceptOp(")") and isOp(":") and #args >= 1 and #args <= 3 then rangeArgs = args
          else pos = save; tok = toks[pos] end
        end
        local src = not rangeArgs and testList()
        local v_ = tmp()
        local rec
        local text = capture(function()
          assign(lv, v_)
          rec = loopBody(function() suite() end, label)
        end)
        local flag
        if isKw("else") then
          adv()
          flag = tmp()
          emit("do local " .. flag .. "=true")
        end
        local closeExtra = false
        if rangeArgs then
          local a, b, c = rangeArgs[1], rangeArgs[2], rangeArgs[3]
          if not b then a, b = "0", a end
          local ia, ib, ic = intLit(a), intLit(b), c and intLit(c) or (not c and 1)
          local na, nb, nc = a:match("^%(%-(%d+)%)$"), b:match("^%(%-(%d+)%)$"), c and c:match("^%(%-(%d+)%)$")
          ia = ia or (na and -math.tointeger(tonumber(na))); ib = ib or (nb and -math.tointeger(tonumber(nb))); ic = ic or (nc and -math.tointeger(tonumber(nc)))
          if ia and ib and ic and ic ~= 0 then
            emit("for " .. v_ .. " = " .. ia .. "," .. (ic > 0 and ib - 1 or ib + 1) .. (ic ~= 1 and ("," .. ic) or "") .. " do")
          else
            local r1, r2, r3 = tmp(), tmp(), tmp()
            emit("do local " .. r1 .. "," .. r2 .. "," .. r3 .. " = R_rng(" .. a .. "," .. b .. "," .. (c or "1") .. ")")
            emit("for " .. v_ .. " = " .. r1 .. "," .. r2 .. "," .. r3 .. " do")
            closeExtra = true
          end
        else
          emit("for " .. v_ .. " in R_iter(" .. src .. ") do")
        end
        emit(flag and (text:gsub("BF_" .. label .. "=", flag .. "=")) or text)
        emit("::" .. label .. "::")
        emit("end")
        if closeExtra then emit("end") end
        if flag then
          emit("if " .. flag .. " then")
          suite()
          emit("end end")
        end
        return
      elseif v == "try" then tryStatement(); return
      elseif v == "def" then defStatement({}); return
      elseif v == "class" then classStatement({}); return
      elseif v == "async" then adv(); return statement()
      elseif v == "with" then
        adv()
        local items = {}
        repeat
          local c = testExpr()
          local lv
          if acceptKw("as") then primary(); lv = lastLv end
          items[#items + 1] = { c = c, lv = lv }
        until not acceptOp(",")
        -- with a as b: body  ==  try / finally with __exit__
        local function nest(i)
          if i > #items then suite(); return end
          local it = items[i]
          local m, ok, f, v2 = tmp(), tmp(), tmp(), tmp()
          emit("do local " .. m .. " = " .. it.c)
          emit("local _ev = R_CM(" .. m .. ',"__enter__")')
          if it.lv then assign(it.lv, "_ev") end
          scope.closure = scope.closure + 1
          local text = capture(function() nest(i + 1) end)
          scope.closure = scope.closure - 1
          emit("local " .. ok .. "," .. f .. "," .. v2 .. " = R_pcall(function()\n" .. text .. "\nend)")
          emit("if not " .. ok .. " then")
          emit("local _x=R_exc(" .. f .. ") if not R_T(R_CM(" .. m .. ',"__exit__",R_classof(_x),_x,None)) then R_error(_x,0) end')
          emit("else R_CM(" .. m .. ',"__exit__",None,None,None)')
          afterFlows(f, v2)
          emit("end end")
        end
        nest(1)
        return
      end
      if v == "return" then
        adv()
        if tok.t == "nl" or isOp(";") or tok.t == "eof" then flowReturn("None") else flowReturn(testList()) end
      elseif v == "pass" then adv()
      elseif v == "break" then
        adv()
        local l = loops[#loops]
        if not l then err("'break' outside loop") end
        if scope.closure > l.closure then emit('do return "b" end')
        else emit("do BF_" .. l.label .. "=false break end") end
      elseif v == "continue" then
        adv()
        local l = loops[#loops]
        if not l then err("'continue' not properly in loop") end
        if scope.closure > l.closure then emit('do return "c" end')
        else emit("goto " .. l.label) end
      elseif v == "raise" then
        adv()
        if tok.t == "nl" or tok.t == "eof" then emit("R_error(R_curexc,0)")
        else
          local c = testExpr()
          if acceptKw("from") then testExpr() end
          emit("R_raise(" .. c .. ")")
        end
      elseif v == "import" then
        adv()
        repeat
          local dotted = name()
          while acceptOp(".") do dotted = dotted .. "." .. name() end
          local as = acceptKw("as") and name()
          local local_ = as or dotted:match("^[^.]+")
          declare(local_)
          if not as and dotted:find(".", 1, true) then emit("local _ = " .. importModule(dotted)) end
          emit(nameRef(local_) .. " = " .. importModule(as and dotted or dotted:match("^[^.]+")))
        until not acceptOp(",")
      elseif v == "from" then
        adv()
        local dots = ""
        while acceptOp(".") or acceptOp("...") do dots = "." end
        local dotted = tok.t == "name" and name() or ""
        while acceptOp(".") do dotted = dotted .. "." .. name() end
        expectKw("import")
        if acceptOp("*") then
          emit("R_importall(" .. importModule(dotted) .. ",_ENV)")
        else
          local paren = acceptOp("(")
          local m = tmp()
          emit("do local " .. m .. " = " .. importModule(dotted))
          repeat
            if paren and isOp(")") then break end
            local n = name()
            local as = acceptKw("as") and name() or n
            declare(as)
            emit(nameRef(as) .. " = R_GA(" .. m .. "," .. str(n) .. ")")
          until not acceptOp(",")
          if paren then expectOp(")") end
          emit("end")
        end
      elseif v == "global" then
        adv()
        repeat local n = name(); scope.globals[n] = true; scope.locals[n] = nil until not acceptOp(",")
      elseif v == "nonlocal" then
        adv()
        repeat local n = name(); scope.globals[n] = true; scope.locals[n] = nil until not acceptOp(",")
      elseif v == "del" then
        adv()
        repeat
          primary()
          local lv = lastLv
          if lv.k == "name" then emit(nameRef(lv.n) .. " = nil")
          elseif lv.k == "idx" then emit("R_DI(" .. lv.o .. "," .. lv.i .. ")")
          elseif lv.k == "attr" then emit("R_DA(" .. lv.o .. "," .. str(lv.n) .. ")") end
        until not acceptOp(",")
      elseif v == "assert" then
        adv()
        local c = cond(testExpr())
        local m = acceptOp(",") and testExpr() or "None"
        emit("if not " .. c .. " then R_raise(AssertionError(" .. m .. ")) end")
      else
        -- an expression that starts with a keyword (not x, lambda, None, yield ...)
        goto expression
      end
      if acceptOp(";") then if tok.t ~= "nl" then return statement(true) end end
      endStmt()
      return
    elseif t.t == "op" and t.v == "@" then
      local decorators = {}
      while acceptOp("@") do
        decorators[#decorators + 1] = testExpr()
        if tok.t == "nl" then adv() end
      end
      if isKw("async") then adv() end
      if isKw("def") then defStatement(decorators) else classStatement(decorators) end
      return
    end
    ::expression::
    do
      local code = testList()
      local lv = lastLv
      if isOp("=") then
        local targets = { lv }
        local value
        while acceptOp("=") do
          value = testList()
          if isOp("=") then targets[#targets + 1] = lastLv end
        end
        if #targets == 1 then assign(targets[1], value)
        else
          local v_ = tmp()
          emit("do local " .. v_ .. " = " .. value)
          for _, tg in ipairs(targets) do assign(tg, v_) end
          emit("end")
        end
      elseif isOp(":") and lv then
        -- an annotation: x: int = 3
        adv()
        testExpr()
        if acceptOp("=") then assign(lv, testList()) elseif lv.k == "name" then declare(lv.n) end
      elseif tok.t == "op" and tok.v:match("^[%+%-%*/%%&|%^<>]+=$") and tok.v ~= "==" and tok.v ~= "<=" and tok.v ~= ">=" then
        local op = tok.v:sub(1, -2)
        adv()
        local value = testList()
        local F = { ["+"] = "R_iadd", ["-"] = "R_sub", ["*"] = "R_imul", ["/"] = "R_div", ["//"] = "R_idiv", ["%"] = "R_mod", ["**"] = "R_pow", ["&"] = "R_band", ["|"] = "R_bor", ["^"] = "R_bxor", ["<<"] = "R_shl", [">>"] = "R_shr" }
        if lv.k == "name" then
          if scope.kind ~= "module" and not scope.globals[lv.n] and not scope.locals[lv.n] then declare(lv.n) end
          local fast = numBin(op, code, value)
          emit(nameRef(lv.n) .. " = " .. (fast or (F[op] .. "(" .. nameRef(lv.n) .. "," .. value .. ")")))
        elseif lv.k == "attr" then
          local o = tmp()
          emit("do local " .. o .. "=" .. lv.o)
          local get = "R_GA(" .. o .. "," .. str(lv.n) .. ")"
          if lv.o == "self" and scope.cls and scope.first == "self" then get = "(R_rawget(" .. o .. "," .. str(lv.n) .. ") or " .. get .. ")" end
          emit("R_SA(" .. o .. "," .. str(lv.n) .. "," .. F[op] .. "(" .. get .. "," .. value .. "))")
          emit("end")
        else
          local o, i = tmp(), tmp()
          emit("do local " .. o .. "," .. i .. "=" .. lv.o .. "," .. lv.i)
          emit("R_SI(" .. o .. "," .. i .. "," .. F[op] .. "(R_GI(" .. o .. "," .. i .. ")," .. value .. "))")
          emit("end")
        end
      else
        if code:sub(1, 1) == '"' or tonumber(code) or code == "None" or code == "true" or code == "false" then
          -- a docstring or a constant: nothing to do
        elseif code:match("^[%a_][%w_]*$") then emit("local _ = " .. code)
        elseif code:sub(1, 1) == "(" and not code:match("^%(function") then emit("local _ = " .. code)
        elseif code:match("%)$") and not code:match("^%(") then emit(code)
        else emit("local _ = " .. code) end
      end
    end
    if acceptOp(";") then if tok.t ~= "nl" and tok.t ~= "eof" then return statement(true) end end
    endStmt()
  end

  local function program()
    while tok.t ~= "eof" do
      if tok.t == "nl" then adv()
      elseif tok.t == "indent" then err("unexpected indent")
      else statement() end
    end
  end
  program()
  local text = table.concat(out, "\n")
  -- a `break` that stands outside a loop-with-else has nothing to clear
  text = text:gsub("BF_cont_%d+=false break", "break")
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

-- an error of the translator gets the text of its line, for the message (File "x.py", line 3 / the caret under the token)
local function compile(src, chunkName)
  local ok, r = pcall(compileText, src, chunkName)
  if ok then return r end
  if type(r) == "table" and r.syntax and not r.text then
    local k = 0
    for l in (src .. "\n"):gmatch("([^\n]*)\n") do
      k = k + 1
      if k == tonumber(r.line) then r.text = l; break end
    end
  end
  error(r, 0)
end
P.compile = compile
P.VERSION = "1.0.0.3"

function P.main(args)
  local rt = driver.load("pyrt")
  local t0 = LC.clock()
  local code = rt.main(args, function(src, name)
    if name == "<stdin>" then return compile(src, name) end
    return LC.get("pylang", P.VERSION, name or "?", src, function() return compile(src, name) end)
  end)
  LC.report(t0)
  return code
end

return P
