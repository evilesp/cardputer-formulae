#!lua
-- rustlang: Rust for this device, translated to Lua. There: structs, enums with data, match with all the usual patterns, traits (default methods, trait objects, operators), generics (without
-- checks), closures, iterators, Vec, String, HashMap, HashSet, BTreeMap, Option, Result, the ? operator, Box, Rc, RefCell, formatting with {} {:?} {:#?} and width and precision, modules, std::env, std::fs, std::io.
-- It does not check: no borrow checker and no type checker, so a program rustc would refuse may run here. Integers do not panic on overflow, a char is a one-letter string (so {:?} of a
-- char shows double quotes), threads run one after the other, crates from crates.io are not there.
local M = {}
local KW = {}
for w in ("as break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while async await"):gmatch("%S+") do KW[w] = true end
local LUAKW = {}
for w in ("and do elseif end function local nil not or repeat then until goto R G"):gmatch("%S+") do LUAKW[w] = true end
local function mangle(n) if LUAKW[n] then return n .. "_" end return n end
local function syntaxError(m, l) error({ syntax = m, line = l }, 0) end
local OPS = { "<<=", ">>=", "..=", "...", "::", "->", "=>", "==", "!=", "<=", ">=", "&&", "||", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<", ">>", ".." }
local OPSET, OPMAX = {}, 2
for _, o in ipairs(OPS) do OPSET[o] = true; if #o > OPMAX then OPMAX = #o end end
local ESC = { n = "\n", t = "\t", r = "\r", ["0"] = "\0", ["\\"] = "\\", ["'"] = "'", ['"'] = '"' }

local function lex(src)
  local toks, i, n, line = {}, 1, #src, 1
  local function push(t, v, x) toks[#toks + 1] = { t = t, v = v, line = line, x = x } end
  local function esc(j)
    local d = src:sub(j + 1, j + 1)
    if d == "x" then return string.char(tonumber(src:sub(j + 2, j + 3), 16)), j + 4 end
    if d == "u" then
      local e = src:find("}", j, true)
      return utf8.char(tonumber(src:sub(j + 3, e - 1), 16)), e + 1
    end
    if d == "\n" then
      line = line + 1
      local k = j + 2
      while src:sub(k, k):find("^%s") do if src:sub(k, k) == "\n" then line = line + 1 end k = k + 1 end
      return "", k
    end
    return ESC[d] or d, j + 2
  end
  local function str(j)
    local b = {}
    while true do
      local d = src:sub(j, j)
      if d == "" then syntaxError("unterminated double quote string", line) end
      if d == '"' then break end
      if d == "\\" then
        local v
        v, j = esc(j)
        b[#b + 1] = v
      else
        if d == "\n" then line = line + 1 end
        b[#b + 1] = d
        j = j + 1
      end
    end
    return table.concat(b), j + 1
  end
  if src:sub(1, 2) == "#!" and src:sub(3, 3) ~= "[" then i = src:find("\n", 1, true) or n + 1 end
  while i <= n do
    local c = src:sub(i, i)
    if c == "\n" then line = line + 1; i = i + 1
    elseif c == " " or c == "\t" or c == "\r" then i = i + 1
    elseif src:sub(i, i + 1) == "//" then i = src:find("\n", i, true) or n + 1
    elseif src:sub(i, i + 1) == "/*" then
      local d, j = 1, i + 2
      while d > 0 and j <= n do
        if src:sub(j, j + 1) == "/*" then d = d + 1; j = j + 2
        elseif src:sub(j, j + 1) == "*/" then d = d - 1; j = j + 2
        else
          if src:sub(j, j) == "\n" then line = line + 1 end
          j = j + 1
        end
      end
      i = j
    elseif src:match('^r#*"', i) then
      local hashes = src:match('^r(#*)"', i)
      local e = src:find('"' .. hashes, i + 2 + #hashes, true)
      local body = src:sub(i + 2 + #hashes, e - 1)
      push("str", body)
      for _ in body:gmatch("\n") do line = line + 1 end
      i = e + 1 + #hashes
    elseif src:sub(i, i + 1) == 'b"' then
      local s, j = str(i + 2)
      push("bstr", s)
      i = j
    elseif src:sub(i, i + 1) == "b'" then
      local v, j
      if src:sub(i + 2, i + 2) == "\\" then v, j = esc(i + 2) else v, j = src:sub(i + 2, i + 2), i + 3 end
      push("int", v:byte())
      i = j + 1
    elseif c:find("[%a_\128-\255]") then
      local j = src:match("^[%w_\128-\255]*()", i)
      local w = src:sub(i, j - 1)
      push(KW[w] and "kw" or "name", w)
      i = j
    elseif c:find("%d") then
      local s = src:match("^0[xX][%x_]+", i) or src:match("^0[bB][01_]+", i) or src:match("^0[oO][0-7_]+", i)
      if s then
        local clean = s:gsub("_", "")
        local k = clean:sub(2, 2):lower()
        push("int", k == "x" and math.tointeger(tonumber(clean)) or tonumber(clean:sub(3), k == "b" and 2 or 8))
        i = i + #s
      else
        s = src:match("^[%d_]+", i)
        local j = i + #s
        local isF = false
        if src:sub(j, j) == "." and src:sub(j + 1, j + 1):find("%d") then
          local fr = src:match("^%.[%d_]+", j)
          s = s .. fr
          j = j + #fr
          isF = true
        elseif src:sub(j, j) == "." and not src:sub(j + 1, j + 1):find("[%.%a_]") then
          j = j + 1
          isF = true
        end
        local ex = src:match("^[eE][+-]?%d+", j)
        if ex then s = s .. ex; j = j + #ex; isF = true end
        local clean = s:gsub("_", "")
        i = j
        local suf = src:match("^_?[iuf]%d+", i) or src:match("^_?[iu]size", i)
        if suf then
          i = i + #suf
          if suf:find("f") then isF = true end
        end
        if isF then push("float", tonumber(clean) + 0.0) else push("int", math.tointeger(tonumber(clean)) or tonumber(clean)) end
      end
      local suf2 = src:match("^_?[iuf]%d+", i) or src:match("^_?[iu]size", i)
      if suf2 then
        i = i + #suf2
        if suf2:find("f") and toks[#toks].t == "int" then toks[#toks] = { t = "float", v = toks[#toks].v + 0.0, line = line } end
      end
    elseif c == '"' then
      local s, j = str(i + 1)
      push("str", s)
      i = j
    elseif c == "'" then
      -- a char or a lifetime
      if src:sub(i + 1, i + 1) == "\\" then
        local v, j = esc(i + 1)
        push("char", v)
        i = j + 1
      else
        local e = src:find("'", i + 1, true)
        local body = e and src:sub(i + 1, e - 1)
        if body and (utf8.len(body) == 1) then
          push("char", body)
          i = e + 1
        else
          local j = src:match("^[%w_]*()", i + 1)
          push("life", src:sub(i, j - 1))
          i = j
        end
      end
    else
      local op
      -- the longest operator that starts here: a lookup by length, not a scan of the list
      for len = OPMAX, 2, -1 do
        local s = src:sub(i, i + len - 1)
        if OPSET[s] then op = s; break end
      end
      op = op or c
      push("op", op)
      i = i + #op
    end
  end
  push("eof")
  return toks
end

local INT_TYPES = { i8 = { 8, true }, i16 = { 16, true }, i32 = { 32, true }, i64 = { 64, true }, isize = { 64, true }, i128 = { 64, true }, u8 = { 8 }, u16 = { 16 }, u32 = { 32 }, u64 = { 64 }, usize = { 64 }, u128 = { 64 } }
local MUTATORS = { push = 1, push_str = 1, pop = 1, clear = 1, insert = 1, insert_str = 1, truncate = 1, remove = 1, retain = 1, take = 1, replace = 1, get_or_insert_with = 1, sort = 1 }

local item_derive
local useAliases
local function compile(src)
  useAliases = {}
  local toks, pos = lex(src), 1
  local tok = toks[1]
  local out = {}
  local tmpN, labelN = 0, 0
  local noStruct = false
  -- integer variables declared with a type narrower than 64 bits (for wrapping_* and friends), and the parts of a..b texts
  local NARROW, RANGES = {}, {}
  local loops = {}
  local selfType
  local curRetHint, hint
  local structs, enums, traits, fnNames, impls = {}, {}, {}, {}, {}
  local locals = { {} }

  local function adv() pos = pos + 1; tok = toks[pos] end
  local function peek(k) return toks[pos + (k or 1)] end
  local function isOp(v) return tok.t == "op" and tok.v == v end
  local function isKw(v) return tok.t == "kw" and tok.v == v end
  local function err(m) syntaxError(m or ("expected something else, found `" .. tostring(tok.v or "<eof>") .. "`"), tok.line) end
  local function acceptOp(v) if isOp(v) then adv(); return true end end
  local function acceptKw(v) if isKw(v) then adv(); return true end end
  local function splitOp(first)
    -- ">>" where ">" is wanted, "&&" where "&" is wanted, "||" where "|" is wanted
    if tok.t == "op" and #tok.v > 1 and tok.v:sub(1, #first) == first and (first == ">" or first == "&" or first == "|") and (tok.v == ">>" or tok.v == "&&" or tok.v == "||" or tok.v == ">=" or tok.v == ">>=") then
      local rest = tok.v:sub(#first + 1)
      toks[pos] = { t = "op", v = rest, line = tok.line }
      tok = toks[pos]
      return true
    end
  end
  local function expectOp(v)
    if acceptOp(v) then return end
    if splitOp(v) then return end
    err("expected `" .. v .. "`, found `" .. tostring(tok.v or "<eof>") .. "`")
  end
  local function expectKw(v) if not acceptKw(v) then err("expected `" .. v .. "`") end end
  local function name() if tok.t ~= "name" then err("expected identifier, found `" .. tostring(tok.v) .. "`") end local v = tok.v; adv(); return v end
  local function emit(s) out[#out + 1] = s end
  local function tmp() tmpN = tmpN + 1; return "_t" .. tmpN end
  local function capture(f) local s = out; out = {}; local a, b = f(); local r = table.concat(out, "\n"); out = s; return r, a, b end
  local function str(s) return (string.format("%q", s):gsub("\\\n", "\\n"):gsub("\r", "\\r")) end
  local function pushLocals() locals[#locals + 1] = {} end
  local function popLocals() locals[#locals] = nil end
  local function declare(n) locals[#locals][n] = true end
  local function isLocal(n)
    for i = #locals, 1, -1 do if locals[i][n] then return true end end
    return false
  end

  local expr, blockInto, block, statement, parseType, pattern, item, closure, parseMacro, assignTo

  -- ---- types: read and thrown away, the name is kept for collect() and casts ----
  local function skipGenerics()
    if isOp("<") then
      local d = 0
      repeat
        if isOp("<") then d = d + 1
        elseif isOp(">") then d = d - 1
        elseif isOp(">>") then d = d - 2
        elseif isOp("->") then
        end
        if d <= 0 then adv(); break end
        adv()
      until tok.t == "eof"
    end
  end
  parseType = function()
    if acceptOp("&") or splitOp("&") then
      if tok.t == "life" then adv() end
      local isMut = acceptKw("mut")
      local t = parseType()
      return (isMut and "&mut " or "&") .. t
    end
    if acceptOp("*") then acceptKw("const"); acceptKw("mut"); return "*" .. parseType() end
    if acceptOp("(") then
      local parts = {}
      while not isOp(")") do parts[#parts + 1] = parseType(); if not acceptOp(",") then break end end
      expectOp(")")
      return "(" .. table.concat(parts, ",") .. ")"
    end
    if acceptOp("[") then
      local t = parseType()
      if acceptOp(";") then local save = hint; expr(); hint = save end
      expectOp("]")
      return "[" .. t .. "]"
    end
    if acceptOp("!") then return "!" end
    if isKw("dyn") or isKw("impl") then
      adv()
      local t = parseType()
      while acceptOp("+") do if tok.t == "life" then adv() else parseType() end end
      return t
    end
    if isKw("fn") then
      adv()
      expectOp("(")
      while not isOp(")") do parseType(); if not acceptOp(",") then break end end
      expectOp(")")
      if acceptOp("->") then parseType() end
      return "fn"
    end
    if tok.t == "life" then adv(); return "'" end
    local last = "?"
    if isOp("<") then skipGenerics() end
    while true do
      if tok.t == "name" or isKw("Self") or isKw("self") or isKw("crate") or isKw("super") then
        last = tok.v
        adv()
      else err("expected a type, found `" .. tostring(tok.v) .. "`") end
      local args
      if isOp("<") then
        -- keep the first argument: Vec<char> and the like matter for collect
        skipGenerics()
      elseif isOp("(") and (last == "Fn" or last == "FnMut" or last == "FnOnce") then
        adv()
        while not isOp(")") do parseType(); if not acceptOp(",") then break end end
        expectOp(")")
        if acceptOp("->") then parseType() end
      end
      if not acceptOp("::") then break end
      if isOp("<") then skipGenerics(); if not acceptOp("::") then break end end
    end
    return last
  end
  local function skipWhere()
    if tok.t == "name" and tok.v == "where" or isKw("where") then
      while not (isOp("{") or isOp(";") or tok.t == "eof") do adv() end
    end
  end

  -- ---- format strings: "{} {x:>5}" and arguments -> a Lua expression ----
  local function formatCall()
    -- the cursor is at the format string; reads to the closing bracket (not eaten)
    if tok.t ~= "str" then
      if isOp(")") or isOp("]") or isOp("}") then return '""' end
      err("format argument must be a string literal")
    end
    local f = tok.v
    adv()
    local args, named = {}, {}
    while acceptOp(",") do
      if isOp(")") or isOp("]") or isOp("}") then break end
      if (tok.t == "name") and peek().v == "=" and peek().t == "op" then
        local n = name()
        adv()
        named[n] = expr()
      else args[#args + 1] = expr() end
    end
    local parts, i, auto = {}, 1, 0
    local buf = {}
    local function flush() if #buf > 0 then parts[#parts + 1] = str(table.concat(buf)); buf = {} end end
    while i <= #f do
      local c = f:sub(i, i)
      if c == "{" then
        if f:sub(i + 1, i + 1) == "{" then buf[#buf + 1] = "{"; i = i + 2
        else
          local e = f:find("}", i, true)
          if not e then syntaxError("invalid format string: expected `}`", tok.line) end
          flush()
          local inner = f:sub(i + 1, e - 1)
          local arg, spec = inner:match("^([^:]*):?(.*)$")
          arg = arg:gsub("%s+", "")
          local code
          if arg == "" then auto = auto + 1; code = args[auto]
          elseif tonumber(arg) then code = args[tonumber(arg) + 1]
          elseif named[arg] then code = named[arg]
          else code = arg == "self" and "self" or mangle(arg) end
          if not code then syntaxError("the format string needs more arguments", tok.line) end
          -- width and precision may be arguments too: {:>width$} {:.*} {:.prec$}
          local w = spec:match("([%a_][%w_]*)%$")
          local wcode = "nil"
          local prec = spec:match("%.([%a_][%w_]*)%$")
          local pcode = "nil"
          if prec then pcode = named[prec] or mangle(prec); spec = spec:gsub("%.[%a_][%w_]*%$", ".*") end
          if spec:find("%.%*") and not prec then
            pcode = code
            auto = auto + 1
            code = args[auto]
          end
          local w2 = spec:match("([%a_][%w_]*)%$")
          if w2 then wcode = named[w2] or mangle(w2); spec = spec:gsub("[%a_][%w_]*%$", "*") end
          local n1 = spec:match("(%d+)%$")
          if n1 then wcode = args[tonumber(n1) + 1]; spec = spec:gsub("%d+%$", "*") end
          if spec == "" then parts[#parts + 1] = "R.disp(" .. code .. ")"
          else parts[#parts + 1] = "R.fmtv(" .. code .. "," .. str(spec) .. "," .. wcode .. "," .. pcode .. ")" end
          i = e + 1
        end
      elseif c == "}" then buf[#buf + 1] = "}"; i = i + (f:sub(i + 1, i + 1) == "}" and 2 or 1)
      else
        local e = f:find("[{}]", i) or #f + 1
        buf[#buf + 1] = f:sub(i, e - 1)
        i = e
      end
    end
    flush()
    if #parts == 0 then return '""' end
    return table.concat(parts, "..")
  end

  parseMacro = function(n)
    -- after "name!"
    local close = isOp("(") and ")" or (isOp("[") and "]" or "}")
    adv()
    local r
    if n == "println" or n == "print" or n == "eprintln" or n == "eprint" then
      local text = formatCall()
      if n == "println" or n == "eprintln" then text = text .. '.."\\n"' end
      emit("R.write(" .. text .. ")")
      r = "R.unit"
    elseif n == "format" then r = "(" .. formatCall() .. ")"
    elseif n == "panic" or n == "unreachable" or n == "todo" or n == "unimplemented" then
      local text = formatCall()
      if n == "unreachable" then text = '"internal error: entered unreachable code"' .. (text ~= '""' and ('..": "..' .. text) or "")
      elseif n == "todo" then text = '"not yet implemented"'
      elseif n == "unimplemented" then text = '"not implemented"'
      elseif text == '""' then text = '"explicit panic"' end
      emit("R.panic(" .. text .. ")")
      r = "nil"
    elseif n == "vec" then
      if isOp(close) then r = "R.vec{}"
      else
        local first = expr()
        if acceptOp(";") then
          local cnt = expr()
          r = "R.vecRepeat(" .. first .. "," .. cnt .. ")"
        else
          local items = { first }
          while acceptOp(",") do
            if isOp(close) then break end
            items[#items + 1] = expr()
          end
          r = "R.vec{" .. table.concat(items, ",") .. "}"
        end
      end
    elseif n == "assert" then
      local c = expr()
      local msg = '"assertion failed"'
      if acceptOp(",") then msg = formatCall() end
      emit("if not (" .. c .. ") then R.panic(" .. msg .. ") end")
      r = "R.unit"
    elseif n == "assert_eq" or n == "assert_ne" or n == "debug_assert_eq" or n == "debug_assert_ne" then
      local a = expr()
      expectOp(",")
      local b = expr()
      if acceptOp(",") then formatCall() end
      local ne = n:find("_ne") ~= nil
      emit("R.assertEq(" .. a .. "," .. b .. "," .. tostring(ne) .. ")")
      r = "R.unit"
    elseif n == "debug_assert" then
      local c = expr()
      if acceptOp(",") then formatCall() end
      emit("if not (" .. c .. ") then R.panic('assertion failed') end")
      r = "R.unit"
    elseif n == "write" or n == "writeln" then
      local f = expr()
      local text = '""'
      if acceptOp(",") then text = formatCall() end
      if n == "writeln" then text = text .. '.."\\n"' end
      r = "R.fwrite(" .. f .. "," .. text .. ")"
    elseif n == "matches" then
      local v = expr()
      expectOp(",")
      local t = tmp()
      emit("local " .. t .. "=" .. v)
      local cond, binds = pattern(t)
      local guard
      if isKw("if") then
        adv()
        pushLocals()
        local bindText = {}
        for _, b in ipairs(binds) do bindText[#bindText + 1] = "local " .. mangle(b[1]) .. "=" .. b[2]; declare(b[1]) end
        local g = expr()
        popLocals()
        guard = "(function() " .. table.concat(bindText, " ") .. " return " .. g .. " end)()"
      end
      acceptOp(",")
      r = "(" .. cond .. (guard and (" and " .. guard) or "") .. ")"
    elseif n == "dbg" then r = expr()
    elseif n == "concat" then
      local parts = {}
      while not isOp(close) do parts[#parts + 1] = "R.disp(" .. expr() .. ")"; if not acceptOp(",") then break end end
      r = table.concat(parts, "..")
    elseif n == "stringify" then
      local p = {}
      while not isOp(close) do p[#p + 1] = tostring(tok.v); adv() end
      r = str(table.concat(p, " "))
    elseif n == "line" then r = tostring(tok.line)
    elseif n == "file" then r = '"main.rs"'
    else syntaxError("cannot find macro `" .. n .. "` in this scope", tok.line) end
    if not isOp(close) then err() end
    adv()
    return r
  end

  -- ---- patterns: returns the test (a Lua expression over v) and the names to bind ----
  local patternAtom
  patternAtom = function(v)
    local t = tok
    -- literals
    if t.t == "int" or t.t == "float" or t.t == "char" or t.t == "str" or isOp("-") then
      local neg = acceptOp("-")
      local lit = tok
      adv()
      local function litText(x, sign)
        if x.t == "int" then return (sign and "-" or "") .. tostring(x.v) end
        if x.t == "float" then return (sign and "-" or "") .. string.format("%.17g", x.v) end
        return str(x.v)
      end
      local a = litText(lit, neg)
      if isOp("..=") or isOp("..") or isOp("...") then
        local incl = tok.v ~= ".."
        adv()
        if tok.t == "int" or tok.t == "char" or tok.t == "float" or isOp("-") then
          local ng = acceptOp("-")
          local hi = tok
          adv()
          return "(" .. v .. ">=" .. a .. " and " .. v .. (incl and "<=" or "<") .. litText(hi, ng) .. ")", {}
        end
        return "(" .. v .. ">=" .. a .. ")", {}
      end
      return "(" .. v .. "==" .. a .. ")", {}
    end
    if isOp("_") or (t.t == "name" and t.v == "_") then adv(); return "true", {} end
    if isKw("true") or isKw("false") then adv(); return "(" .. v .. "==" .. t.v .. ")", {} end
    if isOp("&") or isOp("&&") then
      if not acceptOp("&") then adv() end
      acceptKw("mut")
      local c, b = patternAtom("R.d(" .. v .. ")")
      return c, b
    end
    if isOp("(") then
      adv()
      local conds, binds = {}, {}
      local i = 0
      local single = true
      local firstCond, firstBinds
      while not isOp(")") do
        if isOp("..") then adv()
        else
          i = i + 1
          local c, b = pattern(v .. "[" .. i .. "]")
          conds[#conds + 1] = c
          for _, x in ipairs(b) do binds[#binds + 1] = x end
        end
        if not acceptOp(",") then break end
        single = false
      end
      expectOp(")")
      if i == 1 and single then
        -- only parentheses: the pattern again, on the value itself
        local save = pos
        return (conds[1]:gsub(v:gsub("%p", "%%%0") .. "%[1%]", v)), (function()
          for _, x in ipairs(binds) do x[2] = x[2]:gsub(v:gsub("%p", "%%%0") .. "%[1%]", v) end
          return binds
        end)()
      end
      return "(" .. (#conds > 0 and table.concat(conds, " and ") or "true") .. ")", binds
    end
    if isOp("[") then
      adv()
      local conds, binds, i = {}, {}, 0
      local rest
      local items = {}
      while not isOp("]") do
        if isOp("..") then adv(); items[#items + 1] = { rest = true }
        elseif tok.t == "name" and peek().v == "@" and toks[pos + 2].v == ".." then
          local n = name()
          adv(); adv()
          items[#items + 1] = { rest = true, name = n }
        else items[#items + 1] = { pos = pos } ; do local d = 0; local c, b = pattern("_PLACE"); items[#items].c, items[#items].b = c, b end end
        if not acceptOp(",") then break end
      end
      expectOp("]")
      local hasRest = false
      local restIdx
      for k, it in ipairs(items) do if it.rest then hasRest = true; restIdx = k end end
      local count = #items - (hasRest and 1 or 0)
      conds[1] = hasRest and ("(" .. v .. ".n>=" .. count .. ")") or ("(" .. v .. ".n==" .. count .. ")")
      for k, it in ipairs(items) do
        if it.rest then
          if it.name then binds[#binds + 1] = { it.name, "R.vslice(" .. v .. "," .. (k - 1) .. "," .. v .. ".n-" .. (#items - k) .. ")" } end
        else
          local acc
          if restIdx and k > restIdx then acc = v .. "[" .. v .. ".n-" .. (#items - k) .. "]"
          else acc = v .. "[" .. k .. "]" end
          conds[#conds + 1] = (it.c:gsub("_PLACE", (acc:gsub("%%", "%%%%"))))
          for _, x in ipairs(it.b) do binds[#binds + 1] = { x[1], (x[2]:gsub("_PLACE", (acc:gsub("%%", "%%%%")))) } end
        end
      end
      return "(" .. table.concat(conds, " and ") .. ")", binds
    end
    if isKw("ref") or isKw("mut") then
      acceptKw("ref")
      acceptKw("mut")
      local n = name()
      return "true", { { n, v } }
    end
    -- a path: Enum::Variant(..), Struct { .. }, Some(x), None, a constant, or a new name
    if t.t == "name" or isKw("Self") or isKw("self") or isKw("crate") or isKw("super") then
      local path = { tok.v }
      adv()
      if isOp("<") and false then skipGenerics() end
      while acceptOp("::") do
        if isOp("<") then skipGenerics() else path[#path + 1] = tok.v; adv() end
      end
      local last = path[#path]
      if isOp("@") then
        adv()
        local c, b = pattern(v)
        b[#b + 1] = { path[1], v }
        return c, b
      end
      if isOp("(") then
        adv()
        local conds = { "(R.tagOf(" .. v .. ")==" .. str(last) .. ")" }
        local binds = {}
        local i = 0
        while not isOp(")") do
          if isOp("..") then adv()
          else
            i = i + 1
            local c, b = pattern(v .. "[" .. i .. "]")
            if c ~= "true" then conds[#conds + 1] = c end
            for _, x in ipairs(b) do binds[#binds + 1] = x end
          end
          if not acceptOp(",") then break end
        end
        expectOp(")")
        return "(" .. table.concat(conds, " and ") .. ")", binds
      end
      if isOp("{") then
        adv()
        local isStruct = structs[last] or (last == "Self" and selfType and structs[selfType])
        local conds = isStruct and {} or { "(R.tagOf(" .. v .. ")==" .. str(last) .. ")" }
        local binds = {}
        while not isOp("}") do
          if isOp("..") then adv()
          else
            acceptKw("ref")
            acceptKw("mut")
            local f = tok.v
            adv()
            if acceptOp(":") then
              local c, b = pattern(v .. "." .. mangle(f))
              if c ~= "true" then conds[#conds + 1] = c end
              for _, x in ipairs(b) do binds[#binds + 1] = x end
            else binds[#binds + 1] = { f, v .. "." .. mangle(f) } end
          end
          if not acceptOp(",") then break end
        end
        expectOp("}")
        return "(" .. (#conds > 0 and table.concat(conds, " and ") or "true") .. ")", binds
      end
      if #path > 1 then
        local head = path[#path - 1]
        if enums[head] or head == "Self" or head == "Option" or head == "Ordering" then return "(R.tagOf(" .. v .. ")==" .. str(last) .. ")", {} end
        -- a constant: i32::MAX, module::CONST
        return "(" .. v .. "==" .. (INT_TYPES[head] and ("R.intConst(" .. str(head) .. "," .. str(last) .. ")") or ("G." .. mangle(last))) .. ")", {}
      end
      if last == "None" then return "(R.tagOf(" .. v .. ')=="None")', {} end
      -- an upper-case single name is a constant or a unit variant brought in by use
      if last:match("^%u") then
        if last:match("^%u[%u%d_]*$") then return "(" .. v .. "==G." .. mangle(last) .. ")", {} end
        return "(R.tagOf(" .. v .. ")==" .. str(last) .. ")", {}
      end
      return "true", { { last, v } }
    end
    err("expected a pattern, found `" .. tostring(tok.v) .. "`")
  end
  pattern = function(v)
    if acceptOp("|") then end
    local c, b = patternAtom(v)
    if isOp("|") then
      local conds = { c }
      local allB = b
      while acceptOp("|") do
        local c2, b2 = patternAtom(v)
        conds[#conds + 1] = c2
        -- names bound in each alternative are the same; with data the first that matches gives them
        if #b2 > 0 then
          for k, x in ipairs(allB) do
            local other
            for _, y in ipairs(b2) do if y[1] == x[1] then other = y[2] end end
            if other and other ~= x[2] then
              x[2] = "R.if_(" .. c .. "," .. x[2] .. "," .. other .. ")"
            end
          end
        end
      end
      return "(" .. table.concat(conds, " or ") .. ")", allB
    end
    return c, b
  end
  local function emitBinds(binds)
    if #binds == 0 then return end
    local names, vals = {}, {}
    for i, b in ipairs(binds) do
      names[i] = mangle(b[1])
      vals[i] = b[2]
      declare(b[1])
    end
    emit("local " .. table.concat(names, ",") .. "=" .. table.concat(vals, ","))
  end

  -- ---- expressions: what cannot be an expression in Lua goes out as statements before it ----
  local function isSimple(c) return c:match("^[%a_][%w_%.]*$") or tonumber(c) or c:match('^"[^"]*"$') end
  local function holdValue(c)
    if isSimple(c) then return c end
    local t = tmp()
    emit("local " .. t .. "=" .. c)
    return t
  end

  closure = function()
    acceptKw("move")
    local params = {}
    if isOp("||") then adv()
    else
      expectOp("|")
      while not isOp("|") do
        acceptKw("mut")
        local start = pos
        params[#params + 1] = { pos = pos }
        local i = #params
        local arg = "_a" .. i
        local c, b = patternAtom(arg)
        params[i].arg = arg
        params[i].binds = b
        if acceptOp(":") then parseType() end
        if not acceptOp(",") then break end
      end
      expectOp("|")
    end
    local isBlock = false
    if acceptOp("->") then parseType() end
    local list = {}
    pushLocals()
    local savedLoops, savedHint = loops, hint
    loops = {}
    hint = nil
    local text = capture(function()
      for i, p in ipairs(params) do
        list[i] = p.arg
        emitBinds(p.binds)
      end
      local savedNS = noStruct
      noStruct = false
      if isOp("{") then blockInto("return")
      else
        local e = expr()
        emit("do return " .. e .. " end")
      end
      noStruct = savedNS
    end)
    loops, hint = savedLoops, savedHint
    popLocals()
    return "function(" .. table.concat(list, ",") .. ")\n" .. text .. "\nend"
  end

  -- into: "return", a variable name, or nil for nothing
  local function deliver(into, c)
    if into == "return" then emit("do return " .. (c or "R.unit") .. " end")
    elseif into then emit(into .. "=" .. (c or "R.unit"))
    elseif c and c ~= "R.unit" and c ~= "nil" and not isSimple(c) then
      if c:sub(-1) == ")" and not c:find("^%(") then emit(c) else emit("local _=" .. c) end
    end
  end

  local function ifInto(into)
    expectKw("if")
    local function condPart()
      -- if let PATTERN = v { }  or an expression. Emits what is needed; returns the test and the binds
      local saved = noStruct
      noStruct = true
      local c, binds
      if acceptKw("let") then
        local patStart = pos
        -- the value comes after the pattern: find it, then read the pattern with the name of the value
        local d, p = 0, pos
        while true do
          local x = toks[p]
          if x.t == "eof" then err() end
          if x.t == "op" then
            if x.v == "(" or x.v == "[" or x.v == "{" then d = d + 1
            elseif x.v == ")" or x.v == "]" or x.v == "}" then d = d - 1
            elseif x.v == "=" and d == 0 then break end
          end
          p = p + 1
        end
        pos = p + 1; tok = toks[pos]
        local v = expr()
        local afterVal = pos
        local t = tmp()
        emit("local " .. t .. "=" .. v)
        pos = patStart; tok = toks[pos]
        c, binds = pattern(t)
        pos = afterVal; tok = toks[pos]
      else
        c = expr()
        binds = {}
      end
      noStruct = saved
      return c, binds
    end
    emit("do")
    local c, binds = condPart()
    emit("if " .. c .. " then")
    pushLocals()
    emitBinds(binds)
    blockInto(into)
    popLocals()
    if acceptKw("else") then
      emit("else")
      if isKw("if") then ifInto(into)
      else blockInto(into) end
    else
      if into and into ~= "return" then emit("else " .. into .. "=R.unit") end
    end
    emit("end")
    emit("end")
  end

  local function matchInto(into)
    expectKw("match")
    local saved = noStruct
    noStruct = true
    local v = expr()
    noStruct = saved
    expectOp("{")
    labelN = labelN + 1
    local done = "match_end_" .. labelN
    local t = tmp()
    emit("do local " .. t .. "=" .. v)
    while not isOp("}") do
      local c, binds = pattern(t)
      pushLocals()
      emit("if " .. c .. " then")
      emitBinds(binds)
      local guard
      if acceptKw("if") then
        guard = expr()
        emit("if " .. guard .. " then")
      end
      expectOp("=>")
      if isOp("{") then blockInto(into); acceptOp(",")
      else
        local savedN = noStruct
        noStruct = false
        local start = tok
        if isKw("if") then ifInto(into)
        elseif isKw("match") then matchInto(into)
        else
          local e = expr()
          deliver(into, e)
        end
        noStruct = savedN
        acceptOp(",")
      end
      emit("goto " .. done)
      if guard then emit("end") end
      emit("end")
      popLocals()
    end
    adv()
    emit("R.panic('no match arm fits')")
    emit("::" .. done .. "::")
    emit("end")
  end
  -- a label in Lua needs its goto not to jump into a local: both are inside "do ... end" blocks, and the label comes last there

  local function loopInto(into, label)
    labelN = labelN + 1
    local rec = { cont = "cont_" .. labelN, brk = "brk_" .. labelN, label = label, into = into }
    loops[#loops + 1] = rec
    if acceptKw("loop") then
      emit("while true do")
      blockInto(nil)
      emit("::" .. rec.cont .. "::")
      emit("end")
    elseif acceptKw("while") then
      local saved = noStruct
      noStruct = true
      emit("while true do")
      if acceptKw("let") then
        local patStart = pos
        local d, p = 0, pos
        while true do
          local x = toks[p]
          if x.t == "eof" then err() end
          if x.t == "op" then
            if x.v == "(" or x.v == "[" or x.v == "{" then d = d + 1
            elseif x.v == ")" or x.v == "]" or x.v == "}" then d = d - 1
            elseif x.v == "=" and d == 0 then break end
          end
          p = p + 1
        end
        pos = p + 1; tok = toks[pos]
        local v = expr()
        local after = pos
        local t = tmp()
        emit("local " .. t .. "=" .. v)
        pos = patStart; tok = toks[pos]
        local c, binds = pattern(t)
        pos = after; tok = toks[pos]
        noStruct = saved
        emit("if not " .. c .. " then break end")
        pushLocals()
        emit("do")
        emitBinds(binds)
        blockInto(nil)
        emit("end")
        popLocals()
      else
        local c = expr()
        noStruct = saved
        emit("if not (" .. c .. ") then break end")
        emit("do")
        blockInto(nil)
        emit("end")
      end
      emit("::" .. rec.cont .. "::")
      emit("end")
    else
      expectKw("for")
      local patStart = pos
      local d, p = 0, pos
      while true do
        local x = toks[p]
        if x.t == "eof" then err() end
        if x.t == "op" and (x.v == "(" or x.v == "[" or x.v == "{") then d = d + 1
        elseif x.t == "op" and (x.v == ")" or x.v == "]" or x.v == "}") then d = d - 1
        elseif x.t == "kw" and x.v == "in" and d == 0 then break end
        p = p + 1
      end
      pos = p + 1; tok = toks[pos]
      local saved = noStruct
      noStruct = true
      local isMutIter = isOp("&") and peek().t == "kw" and peek().v == "mut"
      if isMutIter then adv(); adv() end
      local iterC = expr()
      if isMutIter then iterC = 'R.m(' .. iterC .. ',"iter_mut")' end
      noStruct = saved
      local after = pos
      local v_ = tmp()
      pos = patStart; tok = toks[pos]
      local c, binds = pattern(v_)
      pos = after; tok = toks[pos]
      local rg = RANGES[iterC]
      if rg and (rg[1]:match("^%-?%d+$") or rg[2]:match("^%-?%d+$")) then
        -- a range of integers: a numeric for of Lua
        emit("for " .. v_ .. " = " .. rg[1] .. "," .. (rg[3] and rg[2] or ("(" .. rg[2] .. ")-1")) .. " do")
      else
        emit("for " .. v_ .. " in R.iter(" .. iterC .. ") do")
      end
      pushLocals()
      emit("do")
      emitBinds(binds)
      blockInto(nil)
      emit("end")
      popLocals()
      emit("::" .. rec.cont .. "::")
      emit("end")
    end
    loops[#loops] = nil
    emit("::" .. rec.brk .. "::")
    if into and into ~= "return" and rec.noValue then emit(into .. "=R.unit") end
    if into == "return" then emit("do return " .. (rec.valueVar or "R.unit") .. " end") end
  end

  local function pathExpr()
    local path = { tok.v }
    adv()
    local turbofish
    while isOp("::") do
      adv()
      if isOp("<") then
        local save = pos
        adv()
        if tok.t ~= "op" then turbofish = tok.v end
        pos = save; tok = toks[pos]
        skipGenerics()
      else
        path[#path + 1] = tok.v
        adv()
      end
    end
    return path, turbofish
  end

  local function structLiteral(tname, path)
    expectOp("{")
    local parts = {}
    local base
    while not isOp("}") do
      if acceptOp("..") then base = expr(); break end
      local f = tok.v
      adv()
      local v
      if acceptOp(":") then v = expr()
      else v = mangle(f) end
      parts[#parts + 1] = mangle(f) .. "=" .. v
      if not acceptOp(",") then break end
    end
    expectOp("}")
    local body = "{" .. table.concat(parts, ",") .. "}"
    if #path >= 2 and (enums[path[#path - 1]] or path[#path - 1] == "Self") then
      local e = path[#path - 1] == "Self" and selfType or path[#path - 1]
      return "R.variantStruct(G." .. e .. "," .. str(path[#path]) .. "," .. body .. ")"
    end
    if base then return "R.structUpdate(G." .. tname .. "," .. body .. "," .. base .. ")" end
    return "setmetatable(" .. body .. ",G." .. tname .. ")"
  end

  local function args()
    -- after "("
    local a = {}
    local saved, savedHint = noStruct, hint
    noStruct = false
    hint = nil
    while not isOp(")") do
      local c = expr()
      a[#a + 1] = c
      if not acceptOp(",") then break end
    end
    expectOp(")")
    noStruct, hint = saved, savedHint
    return a
  end

  local function primary()
    local t = tok
    if t.t == "int" then adv(); return tostring(t.v) end
    if t.t == "float" then
      adv()
      local s = string.format("%.17g", t.v)
      if not s:find("[%.en]") then s = s .. ".0" end
      return s
    end
    if t.t == "str" or t.t == "char" then adv(); return str(t.v) end
    if t.t == "bstr" then
      adv()
      return "R.bytes(" .. str(t.v) .. ")"
    end
    if t.t == "life" then
      -- a label: 'a: loop
      local l = t.v
      adv()
      expectOp(":")
      if isOp("{") then
        local r = tmp()
        emit("local " .. r)
        labelN = labelN + 1
        local rec = { brk = "brk_" .. labelN, cont = "brk_" .. labelN, label = l, into = r }
        loops[#loops + 1] = rec
        emit("do")
        blockInto(r)
        emit("end")
        loops[#loops] = nil
        emit("::" .. rec.brk .. "::")
        return r
      end
      local r = tmp()
      emit("local " .. r)
      loopInto(r, l)
      return r
    end
    if t.t == "op" then
      if t.v == "(" then
        adv()
        local saved = noStruct
        noStruct = false
        if acceptOp(")") then noStruct = saved; return "R.unit" end
        local c, lv = expr()
        if isOp(",") then
          local items = { c }
          while acceptOp(",") do
            if isOp(")") then break end
            items[#items + 1] = expr()
          end
          expectOp(")")
          noStruct = saved
          return "R.tuple{" .. table.concat(items, ",") .. "}"
        end
        expectOp(")")
        noStruct = saved
        return "(" .. c .. ")", lv
      elseif t.v == "[" then
        adv()
        local saved = noStruct
        noStruct = false
        if acceptOp("]") then noStruct = saved; return "R.vec{}" end
        local first = expr()
        local r
        if acceptOp(";") then
          local n = expr()
          r = "R.vecRepeat(" .. first .. "," .. n .. ")"
        else
          local items = { first }
          while acceptOp(",") do
            if isOp("]") then break end
            items[#items + 1] = expr()
          end
          r = "R.vec{" .. table.concat(items, ",") .. "}"
        end
        expectOp("]")
        noStruct = saved
        return r
      elseif t.v == "|" or t.v == "||" then return closure()
      elseif t.v == "{" then
        local r = tmp()
        emit("local " .. r)
        emit("do")
        blockInto(r)
        emit("end")
        return r
      end
      err()
    end
    if t.t == "kw" then
      local v = t.v
      if v == "true" or v == "false" then adv(); return v end
      if v == "if" then
        local r = tmp()
        emit("local " .. r)
        ifInto(r)
        return r
      elseif v == "match" then
        local r = tmp()
        emit("local " .. r)
        matchInto(r)
        return r
      elseif v == "loop" or v == "while" or v == "for" then
        local r = tmp()
        emit("local " .. r)
        loopInto(r)
        return r
      elseif v == "move" then return closure()
      elseif v == "return" then
        adv()
        if isOp(";") or isOp("}") or isOp(",") or isOp(")") then emit("do return R.unit end")
        else
          local c = expr()
          emit("do return " .. c .. " end")
        end
        return "nil"
      elseif v == "break" then
        adv()
        local rec = loops[#loops]
        if tok.t == "life" then
          local l = tok.v
          adv()
          for i = #loops, 1, -1 do if loops[i].label == l then rec = loops[i]; break end end
        end
        if not rec then err("`break` outside of a loop") end
        if not (isOp(";") or isOp("}") or isOp(",") or isOp(")")) then
          local c = expr()
          if rec.into and rec.into ~= "return" then emit(rec.into .. "=" .. c) end
          if rec.into == "return" then
            emit("do return " .. c .. " end")
            return "nil"
          end
        end
        emit("goto " .. rec.brk)
        return "nil"
      elseif v == "continue" then
        adv()
        local rec = loops[#loops]
        if tok.t == "life" then
          local l = tok.v
          adv()
          for i = #loops, 1, -1 do if loops[i].label == l then rec = loops[i]; break end end
        end
        if not rec then err("`continue` outside of a loop") end
        emit("goto " .. rec.cont)
        return "nil"
      elseif v == "unsafe" then
        adv()
        local r = tmp()
        emit("local " .. r)
        emit("do")
        blockInto(r)
        emit("end")
        return r
      elseif v == "self" and peek().v ~= "::" then adv(); return "self", { set = function(x) return "R.setd(self," .. x .. ")" end, code = "self" }
      end
      if v ~= "Self" and v ~= "crate" and v ~= "super" and v ~= "self" then err() end
    end
    -- a path or a name
    if t.t == "name" and peek().t == "op" and peek().v == "!" and toks[pos + 2].t == "op" and (toks[pos + 2].v == "(" or toks[pos + 2].v == "[" or toks[pos + 2].v == "{") then
      local n = t.v
      adv(); adv()
      return parseMacro(n)
    end
    local path, fish = pathExpr()
    local last = path[#path]
    if #path == 1 then
      local n = last
      if n ~= "Self" then
        if isLocal(n) then
          local m = mangle(n)
          return m, { set = function(x) return m .. "=" .. x end, code = m, name = n }
        end
        if isOp("{") and not noStruct and (structs[n] or n:match("^%u")) then return structLiteral(n, path) end
        if n == "Some" or n == "Ok" or n == "Err" then return "R." .. n end
        if n == "None" then return "R.None" end
        if n == "String" or n == "Vec" or n == "Box" then return "R.type_" .. n end
        return "G." .. mangle(n), { set = function(x) return "G." .. mangle(n) .. "=" .. x end, code = "G." .. mangle(n) }
      end
      -- Self { ... } or Self(...)
      if isOp("{") then return structLiteral(selfType, { selfType }) end
      return "G." .. selfType
    end
    local head = path[#path - 1]
    if head == "Self" then head = selfType end
    -- the types of the language
    if INT_TYPES[head] or head == "f64" or head == "f32" or head == "char" or head == "str" or head == "bool" then
      if last:match("^%u") then
        return "R.intConst(" .. str(head) .. "," .. str(last) .. ")"
      end
      return "R.typeFn(" .. str(head) .. "," .. str(last) .. ")"
    end
    if head == "consts" then return "R.consts." .. last end
    if head == "Ordering" then return "R.Ordering." .. last end
    if head == "Option" then return "R." .. last end
    if head == "Result" then return "R." .. last end
    local BUILTIN = { Path = 1, PathBuf = 1, File = 1, String = 1, Vec = 1, HashMap = 1, BTreeMap = 1, HashSet = 1, BTreeSet = 1, VecDeque = 1, Box = 1, Rc = 1, Arc = 1, RefCell = 1, Cell = 1, Mutex = 1, RwLock = 1, env = 1, fs = 1, io = 1, process = 1, thread = 1, mem = 1, cmp = 1, Instant = 1, Duration = 1, iter = 1, Default = 1, fmt = 1, mpsc = 1, time = 1, BinaryHeap = 1, Weak = 1 }
    if BUILTIN[head] and not structs[head] and not enums[head] then
      if isOp("{") then err() end
      return "R.lib." .. head .. "." .. mangle(last)
    end
    if enums[head] then
      if isOp("{") and not noStruct then return structLiteral(head, path) end
      return "G." .. head .. "." .. mangle(last)
    end
    if isOp("{") and not noStruct and (structs[last]) then return structLiteral(last, path) end
    if structs[head] or traits[head] or impls[head] then
      return "G." .. head .. "." .. mangle(last)
    end
    -- a function of a module, or a generic parameter's function
    if last:match("^%u") and isOp("{") and not noStruct then return structLiteral(last, path) end
    if #head == 1 then return "R.genericCall(" .. str(last) .. ")" end
    return "G." .. mangle(last)
  end

  local function postfix()
    local c, lv = primary()
    while true do
      if isOp(".") then
        adv()
        if tok.t == "int" then
          local i = tok.v
          adv()
          local code = c .. "[" .. (i + 1) .. "]"
          c, lv = code, { set = function(x) return code .. "=" .. x end, code = code }
        elseif tok.t == "float" then
          -- t.0.1
          local a, b = tostring(tok.v):match("(%d+)%.(%d+)")
          adv()
          local code = c .. "[" .. (tonumber(a) + 1) .. "][" .. (tonumber(b) + 1) .. "]"
          c, lv = code, { set = function(x) return code .. "=" .. x end, code = code }
        elseif isKw("await") then adv()
        else
          local n = tok.v
          adv()
          local fish
          if isOp("::") then
            adv()
            if isOp("<") then
              adv()
              fish = tok.v
              pos = pos - 1; tok = toks[pos]
              skipGenerics()
            end
          end
          if isOp("(") then
            local savedHint = hint
            adv()
            local a = args()
            hint = savedHint
            local recv = c
            if n == "collect" or n == "parse" or n == "into" or n == "sum" or n == "product" then
              local target = fish or hint
              a[#a + 1] = target and str(target) or "nil"
            end
            if n == "or_default" and #a == 0 then
              -- the type of the value is not known here: what the next step does with it says what it is
              local zero = "nil"
              if isOp(".") then
                local nx = peek().v
                if nx == "push" or nx == "extend" or nx == "push_back" or nx == "len" or nx == "iter" then zero = "function() return R.vec({}) end"
                elseif nx == "push_str" then zero = 'function() return "" end'
                elseif nx == "insert" or nx == "entry" or nx == "contains_key" then zero = "function() return R.lib.HashMap.new() end"
                elseif peek(2).v ~= "(" then zero = "function() return R.lazyStruct() end" end
              elseif isOp(";") then zero = "function() return R.lazyStruct() end" end
              a[1] = zero
            end
            local argText = #a > 0 and ("," .. table.concat(a, ",")) or ""
            if MUTATORS[n] and lv then
              local nv, res = tmp(), tmp()
              emit("local " .. nv .. "," .. res .. "=R.mutcall(" .. recv .. "," .. str(n) .. argText .. ")")
              emit("if " .. nv .. "~=nil then " .. lv.set(nv) .. " end")
              c, lv = res, nil
            elseif n == "clone" then c, lv = "R.clone(" .. recv .. ")", nil
            else
              c, lv = "R.m(" .. recv .. "," .. str(n) .. argText .. ")", nil
              -- a.wrapping_mul(b) on a u32 (or another narrow type) wraps at its width
              local nw = NARROW[recv]
              if nw and (n:match("^wrapping_") or n == "pow") then c = "R.toInt(" .. c .. "," .. nw[1] .. "," .. tostring(nw[2] or false) .. ")" end
            end
          else
            local m = mangle(n)
            local code = c .. "." .. m
            c, lv = code, { set = function(x) return code .. "=" .. x end, code = code }
          end
        end
      elseif isOp("(") then
        adv()
        local a = args()
        if c:sub(1, 8) == "function" then c = "(" .. c .. ")" end
        c, lv = c .. "(" .. table.concat(a, ",") .. ")", nil
      elseif isOp("[") then
        adv()
        local saved = noStruct
        noStruct = false
        local i = expr()
        noStruct = saved
        expectOp("]")
        local base_, idx = c, i
        local code = "R.idx(" .. base_ .. "," .. idx .. ")"
        c, lv = code, { set = function(x) return "R.setidx(" .. base_ .. "," .. idx .. "," .. x .. ")" end, code = code }
      elseif isOp("?") then
        adv()
        local t = holdValue(c)
        local r = tmp()
        emit("if R.isFail(" .. t .. ") then return " .. t .. " end")
        c, lv = t .. "[1]", nil
      else break end
    end
    return c, lv
  end

  local function castType(c, ty)
    if INT_TYPES[ty] then
      local info = INT_TYPES[ty]
      return "R.toInt(" .. c .. "," .. info[1] .. "," .. tostring(info[2] or false) .. ")"
    end
    if ty == "f64" or ty == "f32" then return "R.toFloat(" .. c .. ")" end
    if ty == "char" then return "R.toChar(" .. c .. ")" end
    return c
  end
  local function unary()
    if isOp("-") then
      adv()
      local c = unary()
      return "(-" .. c .. ")"
    end
    if isOp("!") then
      adv()
      local c = unary()
      return "R.not_(" .. c .. ")"
    end
    if isOp("*") then
      adv()
      local c, lv = unary()
      local code = "R.d(" .. c .. ")"
      return code, { set = function(x) return "R.setd(" .. c .. "," .. x .. ")" end, code = code, deref = true }
    end
    if isOp("&") or isOp("&&") then
      local isDouble = tok.v == "&&"
      adv()
      local isMut = acceptKw("mut")
      local c, lv = unary()
      if isMut and lv then
        return "R.mutref(function() return " .. c .. " end,function(_v) " .. lv.set("_v") .. " end)"
      end
      return c
    end
    return postfix()
  end
  local function castExpr()
    local c, lv = unary()
    while isKw("as") do
      adv()
      local ty = parseType()
      c, lv = castType(c, ty), nil
    end
    return c, lv
  end
  local function binary(nextF, ops)
    return function()
      local a, lv = nextF()
      while tok.t == "op" and ops[tok.v] do
        local f = ops[tok.v]
        adv()
        local b = nextF()
        lv = nil
        if type(f) == "function" then a = f(a, b)
        else a = "(" .. a .. f .. b .. ")" end
      end
      return a, lv
    end
  end
  local mulE = binary(castExpr, { ["*"] = "*", ["/"] = function(a, b) return "R.div(" .. a .. "," .. b .. ")" end, ["%"] = function(a, b)
    -- a constant divisor that is not 0: math.fmod is Rust's % for integers and floats
    if tonumber(b) and tonumber(b) ~= 0 then return "R_fmod(" .. a .. "," .. b .. ")" end
    return "R.rem(" .. a .. "," .. b .. ")"
  end })
  local addE = binary(mulE, { ["+"] = "+", ["-"] = "-" })
  local shiftE = binary(addE, { ["<<"] = "<<", [">>"] = function(a, b) return "R.sar(" .. a .. "," .. b .. ")" end })
  local andE = binary(shiftE, { ["&"] = function(a, b) return "R.band(" .. a .. "," .. b .. ")" end })
  local xorE = binary(andE, { ["^"] = function(a, b) return "R.bxor(" .. a .. "," .. b .. ")" end })
  local orE = binary(xorE, { ["|"] = function(a, b) return "R.bor(" .. a .. "," .. b .. ")" end })
  local cmpE = binary(orE, { ["=="] = "==", ["!="] = "~=", ["<"] = "<", [">"] = ">", ["<="] = "<=", [">="] = ">=" })
  local function shortCircuit(nextF, op)
    return function()
      local a, lv = nextF()
      while (op == "and" and isOp("&&")) or (op == "or" and isOp("||")) do
        adv()
        lv = nil
        local text, b = capture(nextF)
        if text == "" then a = "(" .. a .. " " .. op .. " " .. b .. ")"
        else
          local r = tmp()
          emit("local " .. r .. "=" .. a)
          emit("if " .. (op == "and" and "" or "not ") .. r .. " then")
          emit(text)
          emit(r .. "=" .. b)
          emit("end")
          a = r
        end
      end
      return a, lv
    end
  end
  local logAnd = shortCircuit(cmpE, "and")
  local logOr = shortCircuit(logAnd, "or")
  local function rangeE()
    if isOp("..") or isOp("..=") then
      local incl = tok.v == "..="
      adv()
      if isOp("]") or isOp(")") or isOp(";") or isOp(",") then return "R.range(nil,nil)" end
      local b = logOr()
      return "R.range(nil," .. b .. "," .. tostring(incl) .. ")"
    end
    local a, lv = logOr()
    if isOp("..") or isOp("..=") then
      local incl = tok.v == "..="
      adv()
      if isOp("]") or isOp(")") or isOp(";") or isOp(",") or isOp("{") or isOp("}") then return "R.range(" .. a .. ",nil)" end
      local b = logOr()
      local r = "R.range(" .. a .. "," .. b .. "," .. tostring(incl) .. ")"
      RANGES[r] = { a, b, incl }
      return r
    end
    return a, lv
  end
  local COMPOUND = { ["+="] = "+", ["-="] = "-", ["*="] = "*", ["/="] = "/", ["%="] = "%", ["&="] = "&", ["|="] = "|", ["^="] = "^", ["<<="] = "<<", [">>="] = ">>" }
  expr = function()
    local a, lv = rangeE()
    if isOp("=") then
      if not lv then err("invalid left-hand side of assignment") end
      adv()
      local saved = noStruct
      local v = expr()
      emit(lv.set(v))
      return "R.unit"
    end
    if tok.t == "op" and COMPOUND[tok.v] then
      if not lv then err("invalid left-hand side of assignment") end
      local op = COMPOUND[tok.v]
      adv()
      local v = expr()
      local nv
      if op == "/" then nv = "R.div(" .. a .. "," .. v .. ")"
      elseif op == "%" then nv = "R.rem(" .. a .. "," .. v .. ")"
      elseif op == "^" then nv = "R.bxor(" .. a .. "," .. v .. ")"
      elseif op == "&" then nv = "R.band(" .. a .. "," .. v .. ")"
      elseif op == "|" then nv = "R.bor(" .. a .. "," .. v .. ")"
      elseif op == ">>" then nv = "R.sar(" .. a .. "," .. v .. ")"
      elseif op == "+" and (tonumber(v) or v:match("^R_fmod%(") or v:match("^R%.rem%(") or v:match("^R%.toInt%(")) then nv = "(" .. a .. "+" .. v .. ")"
      elseif op == "+" then nv = "R.addAssign(" .. a .. "," .. v .. ")"
      else nv = "(" .. a .. op .. v .. ")" end
      emit(lv.set(nv))
      return "R.unit"
    end
    return a, lv
  end

  -- ---- statements and blocks ----
  local function letStatement()
    expectKw("let")
    -- a simple name is the common case; otherwise a pattern over a temporary
    local patStart = pos
    local simpleName
    acceptKw("mut")
    if tok.t == "name" and (peek().v == "=" or peek().v == ":" or peek().v == ";") and tok.v ~= "_" then
      simpleName = tok.v
      adv()
    else
      pos = patStart; tok = toks[pos]
      -- skip the pattern to find the type and the value
      local d = 0
      while true do
        local x = tok
        if x.t == "eof" then err() end
        if x.t == "op" then
          if x.v == "(" or x.v == "[" or x.v == "{" then d = d + 1
          elseif x.v == ")" or x.v == "]" or x.v == "}" then d = d - 1
          elseif d == 0 and (x.v == "=" or x.v == ":" or x.v == ";") then break end
        end
        adv()
      end
    end
    local ty
    if acceptOp(":") then ty = parseType() end
    if simpleName then NARROW[simpleName] = ty and INT_TYPES[ty] and INT_TYPES[ty][1] < 64 and INT_TYPES[ty] or nil end
    local savedHint = hint
    hint = ty
    local value
    local m = simpleName and mangle(simpleName)
    local elseBranch
    if acceptOp("=") then
      if simpleName then
        -- the value is computed in a block of its own, so that its temporaries do not use up the locals of the function
        local tname = "_v" .. tmp()
        emit("local " .. tname)
        emit("do")
        if isKw("if") then ifInto(tname)
        elseif isKw("match") then matchInto(tname)
        elseif isOp("{") then blockInto(tname)
        else
          local v, lv = expr()
          if lv and lv.name then v = "R.cp(" .. v .. ")" end
          emit(tname .. "=" .. v)
        end
        emit("end")
        hint = savedHint
        if ty == "f64" or ty == "f32" then end
        declare(simpleName)
        emit("local " .. m .. "=" .. tname)
        expectOp(";")
        return
      end
      value = expr()
    end
    hint = savedHint
    if not simpleName then
      if value then
        local after = pos
        local t = tmp()
        emit("local " .. t .. "=" .. value)
        pos = patStart; tok = toks[pos]
        local c, binds = pattern(t)
        pos = after; tok = toks[pos]
        if acceptKw("else") then
          emit("if not " .. c .. " then")
          blockInto(nil)
          emit("end")
        end
        emitBinds(binds)
      end
    else
      declare(simpleName)
      emit("local " .. m)
    end
    expectOp(";")
  end

  blockInto = function(into)
    expectOp("{")
    pushLocals()
    local saved = noStruct
    noStruct = false
    while not isOp("}") do
      if tok.t == "eof" then err("this file contains an unclosed delimiter") end
      -- attributes
      while isOp("#") do
        adv()
        acceptOp("!")
        local d = 0
        repeat
          if isOp("[") then d = d + 1 elseif isOp("]") then d = d - 1 end
          adv()
        until d == 0
      end
      if isOp("}") then break end
      if acceptOp(";") then
      elseif isKw("let") then letStatement()
      elseif isKw("fn") or isKw("struct") or isKw("enum") or isKw("impl") or isKw("trait") or isKw("use") or isKw("const") or isKw("static") or isKw("mod") or isKw("type") or isKw("pub") then
        item()
      elseif isKw("if") or isKw("match") or isKw("loop") or isKw("while") or isKw("for") or isOp("{") or isKw("unsafe") or (tok.t == "life") then
        -- a statement form; its value goes out when it is the last thing in the block
        local start = pos
        local kind = tok.v
        local afterText
        -- is it the last in the block (the value of the block), or does a method follow?
        local text = capture(function()
          if kind == "if" then ifInto(into and "_BLOCKV" or nil)
          elseif kind == "match" then matchInto(into and "_BLOCKV" or nil)
          elseif kind == "loop" or kind == "while" or kind == "for" then loopInto(into and "_BLOCKV" or nil)
          elseif tok.t == "life" then
            local l = tok.v
            adv()
            expectOp(":")
            loopInto(into and "_BLOCKV" or nil, l)
          else
            if kind == "unsafe" then adv() end
            emit("do")
            blockInto(into and "_BLOCKV" or nil)
            emit("end")
          end
        end)
        if isOp("}") and into then
          if into == "return" then
            emit("do local _BLOCKV\n" .. text .. "\ndo return _BLOCKV end end")
          else
            emit((text:gsub("_BLOCKV", into)))
          end
        elseif isOp(".") or isOp("?") then
          -- the value is used: parse again as an expression
          pos = start; tok = toks[pos]
          local c = expr()
          if isOp("}") and into then deliver(into, c)
          else
            deliver(nil, c)
            acceptOp(";")
          end
        else
          if into then emit("do local _BLOCKV\n" .. text .. "\nend") else emit(text) end
          acceptOp(";")
        end
      else
        emit("do")
        local c = expr()
        if isOp("}") and into then
          deliver(into, c)
          emit("end")
          break
        end
        deliver(nil, c)
        emit("end")
        if not isOp("}") then
          if not acceptOp(";") then err("expected `;`, found `" .. tostring(tok.v) .. "`") end
          -- nothing after the last `;`: the value of the block is ()
        end
      end
    end
    expectOp("}")
    popLocals()
    noStruct = saved
  end
  block = blockInto

  -- ---- items ----
  local function parseFnSignature()
    if isOp("<") then skipGenerics() end
    expectOp("(")
    local params = {}
    local hasSelf = false
    while not isOp(")") do
      while isOp("#") do
        adv()
        local d = 0
        repeat
          if isOp("[") then d = d + 1 elseif isOp("]") then d = d - 1 end
          adv()
        until d == 0
      end
      -- self in its forms
      local p = pos
      local q = p
      if toks[q].t == "op" and toks[q].v == "&" then q = q + 1 end
      if toks[q].t == "life" then q = q + 1 end
      if toks[q].t == "kw" and toks[q].v == "mut" then q = q + 1 end
      if toks[q].t == "kw" and toks[q].v == "self" then
        pos = q + 1; tok = toks[pos]
        hasSelf = true
        if acceptOp(":") then parseType() end
      else
        local arg = "_a" .. #params + 1
        local c, b = pattern(arg)
        expectOp(":")
        local ty = parseType()
        params[#params + 1] = { arg = arg, binds = b, ty = ty }
      end
      if not acceptOp(",") then break end
    end
    expectOp(")")
    local ret
    if acceptOp("->") then ret = parseType() end
    skipWhere()
    return params, hasSelf, ret
  end
  local function functionText(params, hasSelf, ret)
    local list = {}
    if hasSelf then list[1] = "self" end
    for _, p in ipairs(params) do
      list[#list + 1] = (#p.binds == 1 and p.binds[1][2] == p.arg) and mangle(p.binds[1][1]) or p.arg
    end
    pushLocals()
    if hasSelf then declare("self") end
    local savedLoops, savedHint = loops, hint
    loops = {}
    hint = ret
    local text = capture(function()
      for _, p in ipairs(params) do
        if #p.binds == 1 and p.binds[1][2] == p.arg then declare(p.binds[1][1])
        else emitBinds(p.binds) end
      end
      blockInto("return")
    end)
    loops, hint = savedLoops, savedHint
    popLocals()
    return "function(" .. table.concat(list, ",") .. ")\n" .. text .. "\nend"
  end

  -- a first look at the file: names of types, so that paths resolve whatever the order
  do
    local p = 1
    local depth = 0
    while toks[p].t ~= "eof" do
      local x = toks[p]
      if x.t == "kw" and (x.v == "struct" or x.v == "enum" or x.v == "trait") and toks[p + 1].t == "name" then
        local n = toks[p + 1].v
        if x.v == "struct" then structs[n] = true elseif x.v == "enum" then enums[n] = true else traits[n] = true end
      elseif x.t == "kw" and x.v == "impl" then
        local q = p + 1
        if toks[q].v == "<" then
          local d = 0
          repeat
            if toks[q].v == "<" then d = d + 1 elseif toks[q].v == ">" then d = d - 1 elseif toks[q].v == ">>" then d = d - 2 end
            q = q + 1
          until d <= 0 or toks[q].t == "eof"
        end
        if toks[q].t == "name" then impls[toks[q].v] = true end
      end
      p = p + 1
    end
  end

  item = function()
    while isOp("#") do
      adv()
      acceptOp("!")
      local d = 0
      local derive = {}
      repeat
        if isOp("[") then d = d + 1 elseif isOp("]") then d = d - 1
        elseif tok.t == "name" then derive[tok.v] = true end
        adv()
      until d == 0
      item_derive = derive
    end
    if acceptKw("pub") then
      if isOp("(") then
        repeat adv() until isOp(")")
        adv()
      end
    end
    acceptKw("unsafe")
    acceptKw("async")
    if isKw("const") and peek().v == "fn" then adv() end
    if isKw("extern") then adv(); if tok.t == "str" then adv() end end
    if isKw("use") or (isKw("extern")) then
      adv()
      local d = 0
      local en
      while not (isOp(";") and d == 0) do
        if isOp("{") then d = d + 1 elseif isOp("}") then d = d - 1 end
        if tok.t == "eof" then err() end
        if tok.t == "name" and enums[tok.v] and peek().v == "::" then
          en = tok.v
        elseif en and tok.t == "name" then useAliases[#useAliases + 1] = "G." .. mangle(tok.v) .. "=G." .. en .. "." .. mangle(tok.v)
        elseif en and isOp("*") then useAliases[#useAliases + 1] = "R.importAll(G,G." .. en .. ")" end
        adv()
      end
      adv()
      return
    end
    if isKw("type") then
      adv()
      while not isOp(";") do adv() end
      adv()
      return
    end
    if isKw("mod") then
      adv()
      name()
      if acceptOp(";") then return end
      expectOp("{")
      while not isOp("}") do item() end
      adv()
      return
    end
    if isKw("const") or isKw("static") then
      adv()
      acceptKw("mut")
      local n = name()
      expectOp(":")
      local ty = parseType()
      expectOp("=")
      local savedHint = hint
      hint = ty
      local v = expr()
      hint = savedHint
      expectOp(";")
      emit("G." .. mangle(n) .. "=" .. v)
      return
    end
    if isKw("fn") then
      adv()
      local n = name()
      local params, hasSelf, ret = parseFnSignature()
      if acceptOp(";") then return end
      -- a function inside a block is global too: the name is unique enough for a small program
      local text = functionText(params, hasSelf, ret)
      emit("G." .. mangle(n) .. "=" .. text)
      fnNames[n] = true
      return
    end
    if isKw("struct") then
      adv()
      local n = name()
      local d = item_derive or {}
      item_derive = nil
      if isOp("<") then skipGenerics() end
      skipWhere()
      local fields = {}
      local zeros = {}
      if acceptOp("{") then
        while not isOp("}") do
          while isOp("#") do
            adv()
            local dd = 0
            repeat
              if isOp("[") then dd = dd + 1 elseif isOp("]") then dd = dd - 1 end
              adv()
            until dd == 0
          end
          acceptKw("pub")
          if isOp("(") then repeat adv() until isOp(")"); adv() end
          local f = name()
          fields[#fields + 1] = str(mangle(f))
          expectOp(":")
          local ft = parseType()
          do
            local z = ({ String = '""', str = '""', bool = "false", f64 = "0.0", f32 = "0.0", Vec = "R.vec({})", HashMap = "R.lib.HashMap.new()", BTreeMap = "R.lib.BTreeMap.new()", Option = "R.None", char = '"\\0"' })[ft]
            if not z then
              if ft:match("^[iu]%d+$") or ft == "usize" or ft == "isize" then z = "0"
              elseif ft:match("^%u") then z = "G." .. ft .. ".default()"
              else z = "0" end
            end
            zeros[#zeros + 1] = "[" .. str(mangle(f)) .. "]=" .. z
          end
          if not acceptOp(",") then break end
        end
        expectOp("}")
      elseif acceptOp("(") then
        local i = 0
        while not isOp(")") do
          acceptKw("pub")
          parseType()
          i = i + 1
          if not acceptOp(",") then break end
        end
        expectOp(")")
        expectOp(";")
        emit("G." .. n .. "=R.newStruct(" .. str(n) .. ",{}," .. tostring(d.Copy or false) .. ",true)")
        return
      else expectOp(";") end
      emit("G." .. n .. "=R.newStruct(" .. str(n) .. ",{" .. table.concat(fields, ",") .. "}," .. tostring(d.Copy or false) .. ")")
      if d.Default then emit("G." .. n .. ".default=function() return setmetatable({" .. table.concat(zeros, ",") .. "},G." .. n .. ") end") end
      return
    end
    if isKw("enum") then
      adv()
      local n = name()
      local d = item_derive or {}
      item_derive = nil
      if isOp("<") then skipGenerics() end
      skipWhere()
      expectOp("{")
      emit("G." .. n .. "=R.newEnum(" .. str(n) .. "," .. tostring(d.Copy or false) .. ")")
      local nextD = 0
      while not isOp("}") do
        while isOp("#") do
          adv()
          local dd = 0
          repeat
            if isOp("[") then dd = dd + 1 elseif isOp("]") then dd = dd - 1 end
            adv()
          until dd == 0
        end
        local v = name()
        if acceptOp("(") then
          local c = 0
          while not isOp(")") do parseType(); c = c + 1; if not acceptOp(",") then break end end
          expectOp(")")
          emit("R.variantTuple(G." .. n .. "," .. str(v) .. ")")
        elseif acceptOp("{") then
          local fields = {}
          while not isOp("}") do
            local f = name()
            fields[#fields + 1] = str(mangle(f))
            expectOp(":")
            parseType()
            if not acceptOp(",") then break end
          end
          expectOp("}")
          emit("R.variantFields(G." .. n .. "," .. str(v) .. ",{" .. table.concat(fields, ",") .. "})")
        else
          local disc = nextD
          if acceptOp("=") then
            local neg = acceptOp("-")
            disc = (neg and -1 or 1) * tok.v
            adv()
          end
          nextD = disc + 1
          emit("R.variantUnit(G." .. n .. "," .. str(v) .. "," .. disc .. ")")
        end
        if not acceptOp(",") then break end
      end
      expectOp("}")
      return
    end
    if isKw("trait") then
      adv()
      local n = name()
      if isOp("<") then skipGenerics() end
      if acceptOp(":") then
        while not (isOp("{") or tok.t == "eof") do adv() end
      end
      skipWhere()
      expectOp("{")
      emit("G." .. n .. "=R.newTrait(" .. str(n) .. ")")
      local savedSelf = selfType
      selfType = n
      while not isOp("}") do
        acceptKw("unsafe")
        if isKw("fn") then
          adv()
          local mn = name()
          local params, hasSelf, ret = parseFnSignature()
          if acceptOp(";") then
          else
            emit("G." .. n .. "." .. mangle(mn) .. "=" .. functionText(params, hasSelf, ret))
          end
        else
          while not isOp(";") do adv() end
          adv()
        end
      end
      adv()
      selfType = savedSelf
      return
    end
    if isKw("impl") then
      adv()
      if isOp("<") then skipGenerics() end
      -- impl T, impl Trait for T
      local first = parseType()
      local traitName
      local target = first
      if acceptKw("for") then
        traitName = first
        target = parseType()
      end
      skipWhere()
      expectOp("{")
      local isBuiltin = not (structs[target] or enums[target])
      if isBuiltin then emit("G." .. target .. "=G." .. target .. " or R.extType(" .. str(target) .. ")") end
      local savedSelf = selfType
      selfType = target
      local isFmt = traitName == "Display" or traitName == "Debug" or traitName == "LowerHex" or traitName == "UpperHex" or traitName == "Binary"
      while not isOp("}") do
        while isOp("#") do
          adv()
          local dd = 0
          repeat
            if isOp("[") then dd = dd + 1 elseif isOp("]") then dd = dd - 1 end
            adv()
          until dd == 0
        end
        if acceptKw("pub") then
          if isOp("(") then repeat adv() until isOp(")"); adv() end
        end
        acceptKw("unsafe")
        acceptKw("async")
        if isKw("const") and peek().v == "fn" then adv() end
        if isKw("fn") then
          adv()
          local mn = name()
          local params, hasSelf, ret = parseFnSignature()
          local text = functionText(params, hasSelf, ret)
          local key = mangle(mn)
          if isFmt and mn == "fmt" then key = "__fmt_" .. traitName end
          emit("G." .. target .. "." .. key .. "=" .. text)
          if traitName then
            local ops = { add = "__add", sub = "__sub", mul = "__mul", div = "__rdiv", rem = "__rrem", neg = "__unm", eq = "__ueq", lt = "__ult", partial_cmp = "__pcmp", cmp = "__cmp", index = "__uindex", add_assign = "__add_assign", sub_assign = "__sub_assign", mul_assign = "__mul_assign", next = "__next", from = "__from", drop = "__drop", not_ = "__not" }
            if ops[mn] then emit("G." .. target .. "." .. ops[mn] .. "=G." .. target .. "." .. key) end
          end
        elseif isKw("const") then
          adv()
          local cn = name()
          expectOp(":")
          parseType()
          expectOp("=")
          local v = expr()
          expectOp(";")
          emit("G." .. target .. "." .. mangle(cn) .. "=" .. v)
        elseif isKw("type") then
          while not isOp(";") do adv() end
          adv()
        else err() end
      end
      adv()
      selfType = savedSelf
      if traitName and (traits[traitName] or true) then
        emit("R.implTrait(G." .. target .. ",G." .. mangle(traitName) .. "," .. str(traitName) .. ")")
      end
      return
    end
    err("expected item, found `" .. tostring(tok.v) .. "`")
  end

  -- items may refer to each other: types first
  while tok.t ~= "eof" do item() end
  for _, a in ipairs(useAliases) do emit(a) end
  emit("return G.main")
  local all = "local R_fmod=math.fmod\n" .. table.concat(out, "\n")
  return all
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

M.compile = compile
M.VERSION = "1.0.0.2"

function M.main(args)
  local rt = driver.load("rustrt")
  local t0 = LC.clock()
  local path, outPath, run
  local i = 1
  while args[i] do
    local a = args[i]
    if a == "-run" then run = true
    elseif a == "--version" or a == "-V" then term.write("rustc 1.80.0 (ESP Linux, translates to Lua)\n"); return 0
    elseif a == "--selftest" then return rt.run(compile('fn main() { let v: Vec<i32> = (1..4).map(|x| x * 2).collect(); println!("rust ok {:?}", v); }'), {})
    elseif a == "-o" then outPath = args[i + 1]; i = i + 1
    elseif a:sub(1, 1) == "-" and not path then
      if a == "-O" or a == "-g" then elseif a:sub(1, 2) == "-C" or a:sub(1, 2) == "-A" or a:sub(1, 2) == "-W" or a == "--edition" or a:sub(1, 9) == "--edition" then if a == "-C" or a == "-A" or a == "-W" or a == "--edition" then i = i + 1 end end
    else
      path = a
      if run then break end
    end
    i = i + 1
  end
  if not path then term.write("usage: rustc FILE.rs [-o PROGRAM], then ./PROGRAM; or rustc -run FILE.rs [ARGS]\n"); return 2 end
  local src = fs.read(path)
  if not src then term.write("error: couldn't read " .. path .. ": No such file or directory\n"); return 1 end
  local ok, text = pcall(LC.get, "rustlang", M.VERSION, path, src, function() return compile(src) end)
  if not ok then
    if type(text) == "table" and text.syntax then term.write("error: " .. text.syntax .. "\n --> " .. path .. ":" .. tostring(text.line) .. "\n")
    else term.write(tostring(text) .. "\n") end
    return 1
  end
  if run then
    local a = { path }
    for k = i + 1, #args do a[#a + 1] = args[k] end
    local code = rt.run(text, a)
    LC.report(t0)
    return code
  end
  outPath = outPath or path:gsub("%.rs$", ""):match("([^/]+)$")
  fs.write(outPath, '#!lua\nlocal rt = driver.load("rustrt")\nlocal text = ' .. string.format("%q", text):gsub("\\\n", "\\n") .. "\nlocal a = {" .. string.format("%q", outPath) .. "}\nfor i, v in ipairs(arg) do a[i + 1] = v end\nrt.run(text, a)\n")
  if sys and sys.shell then pcall(sys.shell, "chmod +x " .. outPath) end
  return 0
end
return M
