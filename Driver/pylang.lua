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

local function syntaxError(msg, line) error({ syntax = msg, line = line }, 0) end

local function lex(src)
  local toks, i, n, line, depth, indents = {}, 1, #src, 1, 0, { 0 }
  local function push(t, v) toks[#toks + 1] = { t = t, v = v, line = line } end
  local bol = true
  if src:sub(1, 2) == "#!" then i = (src:find("\n", 1, true) or n) end
  while i <= n do
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
          if col ~= indents[#indents] then syntaxError("unindent does not match any outer indentation level", line) end
        end
      end
    else
      local c = src:sub(i, i)
      if c == " " or c == "\t" or c == "\r" then i = i + 1
      elseif c == "\n" then
        if depth == 0 then push("nl"); bol = true end
        line = line + 1; i = i + 1
      elseif c == "\\" and src:sub(i + 1, i + 1):find("[\r\n]") then
        i = src:find("\n", i, true) + 1; line = line + 1
      elseif c == "#" then i = src:find("\n", i, true) or n + 1
      elseif c:find("[%a_\128-\255]") or c:find("%d") == nil and false then
        local j = i
        while src:sub(j, j):find("[%w_\128-\255]") and j <= n do j = j + 1 end
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
            local d = src:sub(k, k)
            if k > n then syntaxError("unterminated string literal", line) end
            if d == "\\" then k = k + 2
            elseif src:sub(k, k + #close - 1) == close then break
            else k = k + 1 end
          end
          local body = src:sub(from, k - 1)
          i = k + #close
          local start = line
          for _ in body:gmatch("\n") do line = line + 1 end
          if prefix:find("f") then toks[#toks + 1] = { t = "fstr", v = body, raw = prefix:find("r") ~= nil, line = start }
          else toks[#toks + 1] = { t = "str", v = prefix:find("r") and body or unescape(body), line = start } end
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
          local d = src:sub(k, k)
          if k > n or (d == "\n" and not triple) then syntaxError("unterminated string literal", line) end
          if d == "\\" then k = k + 2
          elseif src:sub(k, k + #close - 1) == close then break
          else k = k + 1 end
        end
        local body = src:sub(from, k - 1)
        toks[#toks + 1] = { t = "str", v = unescape(body), line = line }
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
  if toks[#toks] and toks[#toks].t ~= "nl" then push("nl") end
  for k = #indents, 2, -1 do push("dedent") end
  push("eof")
  return toks
end

-- ---------------------------------------------------------------- compiler
local function compile(src, chunkName)
  local toks, pos = lex(src), 1
  local tok = toks[1]
  local out = {}
  local scope = { kind = "module", locals = {}, globals = {}, closure = 0 }
  local loops = {}
  local labelN, tmpN = 0, 0
  local lastLv
  local function adv() pos = pos + 1; tok = toks[pos] end
  local function isOp(v) return tok.t == "op" and tok.v == v end
  local function isKw(v) return tok.t == "kw" and tok.v == v end
  local function err(msg) syntaxError(msg or "invalid syntax", tok.line) end
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
  local function functionBody(params, parseBody, isMethodClass)
    local saved, savedLoops = scope, loops
    scope = { kind = "function", locals = {}, globals = {}, closure = 0, parent = saved, first = params.names[1], cls = isMethodClass }
    loops = {}
    for _, p in ipairs(params.names) do scope.locals[p] = nil end
    local paramSet = {}
    for _, p in ipairs(params.names) do paramSet[p] = true end
    if params.star then paramSet[params.star] = true end
    if params.kwstar then paramSet[params.kwstar] = true end
    for _, p in ipairs(params.kwonly) do paramSet[p] = true end
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
      return nameRef(t.v)
    elseif t.t == "num" then adv(); return t.v
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
          code = "R_GA(" .. code .. "," .. str(n) .. ")"
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
    if isOp("-") then adv(); local c = unary(); lastLv = nil; return "R_neg(" .. c .. ")" end
    if isOp("+") then adv(); local c = unary(); lastLv = nil; return c end
    if isOp("~") then adv(); local c = unary(); lastLv = nil; return "(~" .. c .. ")" end
    return power()
  end
  P._unary = unary
  local function binary(next_, ops)
    return function()
      local a = next_()
      while tok.t == "op" and ops[tok.v] do
        local f = ops[tok.v]
        adv()
        local b = next_()
        a = f .. "(" .. a .. "," .. b .. ")"
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
  local function isSimple(c) return c:match("^[%a_][%w_]*$") or tonumber(c) or c == "None" end
  local function andTest()
    local a = notTest()
    while isKw("and") do
      adv()
      local b = notTest()
      lastLv = nil
      if isBool(a) and isBool(b) then a = mkBool("(" .. a .. " and " .. b .. ")")
      else a = "R_and(" .. a .. ",function() return " .. b .. " end)" end
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
      else a = "R_or(" .. a .. ",function() return " .. b .. " end)" end
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
    local f = functionBody(params, function() suite() end, isMethod)
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
        local src = testList()
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
        emit("for " .. v_ .. " in R_iter(" .. src .. ") do")
        emit(flag and (text:gsub("BF_" .. label .. "=", flag .. "=")) or text)
        emit("::" .. label .. "::")
        emit("end")
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
          emit(nameRef(lv.n) .. " = " .. F[op] .. "(" .. nameRef(lv.n) .. "," .. value .. ")")
        elseif lv.k == "attr" then
          local o = tmp()
          emit("do local " .. o .. "=" .. lv.o)
          emit("R_SA(" .. o .. "," .. str(lv.n) .. "," .. F[op] .. "(R_GA(" .. o .. "," .. str(lv.n) .. ")," .. value .. "))")
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

P.compile = compile

function P.main(args)
  local rt = driver.load("pyrt")
  return rt.main(args, compile)
end

return P
