#!lua
-- golang: Go for this device, translated to Lua. There: packages fmt, strings, strconv, math, sort, os, time, errors, sync, unicode, math/rand; structs, methods, interfaces, embedding, closures,
-- slices, maps, multiple results, defer/panic/recover, goroutines with channels and select (cooperative, on one core), generics (without checks), iota, type switches. Not there: cgo, reflect,
-- unsafe, packages from the network, a real compile-time type check (a wrong program may fail only when it runs).
local M = {}
local KW = {}
for w in ("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"):gmatch("%S+") do KW[w] = true end
local LUAKW = {}
for w in ("and do elseif end function in local nil not or repeat then until self true false while R G"):gmatch("%S+") do LUAKW[w] = true end
local function mangle(n) if LUAKW[n] then return n .. "_" end if n:find("[\128-\255]") then return (n:gsub("[\128-\255]", function(c) return string.format("_x%02x", c:byte()) end)) end return n end
local function syntaxError(m, l) error({ syntax = m, line = l }, 0) end
local OPS = { "<<=", ">>=", "&^=", "...", "&&", "||", "<-", "++", "--", "==", "!=", "<=", ">=", ":=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<", ">>", "&^" }
local ESC = { n = 10, t = 9, r = 13, a = 7, b = 8, f = 12, v = 11, ["\\"] = 92, ["'"] = 39, ['"'] = 34 }

local function lex(src)
  local toks, i, n, line = {}, 1, #src, 1
  local function push(t, v) toks[#toks + 1] = { t = t, v = v, line = line } end
  local function needsSemi()
    local p = toks[#toks]
    if not p then return false end
    if p.t == "name" or p.t == "int" or p.t == "float" or p.t == "str" or p.t == "char" then return true end
    if p.t == "kw" then return p.v == "break" or p.v == "continue" or p.v == "fallthrough" or p.v == "return" end
    return p.v == "++" or p.v == "--" or p.v == ")" or p.v == "]" or p.v == "}"
  end
  local function esc(j)
    local d = src:sub(j + 1, j + 1)
    if d == "x" then return tonumber(src:sub(j + 2, j + 3), 16), j + 4, true end
    if d == "u" then return tonumber(src:sub(j + 2, j + 5), 16), j + 6 end
    if d == "U" then return tonumber(src:sub(j + 2, j + 9), 16), j + 10 end
    if d:find("[0-7]") then return tonumber(src:sub(j + 1, j + 3), 8), j + 4, true end
    return ESC[d] or d:byte(), j + 2
  end
  if src:sub(1, 2) == "#!" then i = src:find("\n", 1, true) or n + 1 end
  while i <= n do
    local c = src:sub(i, i)
    if c == "\n" then
      if needsSemi() then push("op", ";") end
      line = line + 1; i = i + 1
    elseif c == " " or c == "\t" or c == "\r" then i = i + 1
    elseif src:sub(i, i + 1) == "//" then i = src:find("\n", i, true) or n + 1
    elseif src:sub(i, i + 1) == "/*" then
      local e = src:find("*/", i + 2, true) or n
      for _ in src:sub(i, e):gmatch("\n") do line = line + 1 end
      i = e + 2
    elseif c:find("[%a_\128-\255]") then
      local j = src:match("^[%w_\128-\255]*()", i)
      local w = src:sub(i, j - 1)
      push(KW[w] and "kw" or "name", w)
      i = j
    elseif c:find("%d") or (c == "." and src:sub(i + 1, i + 1):find("%d")) then
      local s = src:match("^0[xX][%x_]+", i) or src:match("^0[bB][01_]+", i) or src:match("^0[oO][0-7_]+", i)
      if s then
        local clean = s:gsub("_", "")
        local k = clean:sub(2, 2):lower()
        push("int", k == "x" and math.tointeger(tonumber(clean)) or tonumber(clean:sub(3), k == "b" and 2 or 8))
      else
        s = src:match("^[%d_]*%.?[%d_]*[eE][+-]?%d+", i) or src:match("^[%d_]*%.?[%d_]*", i)
        local clean = s:gsub("_", "")
        if clean:find("[%.eE]") then push("float", tonumber(clean) + 0.0)
        elseif #clean > 1 and clean:sub(1, 1) == "0" then push("int", tonumber(clean, 8))
        else push("int", math.tointeger(tonumber(clean)) or tonumber(clean)) end
      end
      i = i + #s
    elseif c == '"' then
      local b, j = {}, i + 1
      while true do
        local d = src:sub(j, j)
        if d == "" or d == "\n" then syntaxError("string literal not terminated", line) end
        if d == '"' then break end
        if d == "\\" then
          local v, nx, raw = esc(j)
          b[#b + 1] = raw and string.char(v) or utf8.char(v)
          j = nx
        else b[#b + 1] = d; j = j + 1 end
      end
      push("str", table.concat(b))
      i = j + 1
    elseif c == "`" then
      local e = src:find("`", i + 1, true)
      local body = src:sub(i + 1, e - 1)
      push("str", body)
      for _ in body:gmatch("\n") do line = line + 1 end
      i = e + 1
    elseif c == "'" then
      local v, j
      if src:sub(i + 1, i + 1) == "\\" then v, j = esc(i + 1)
      else
        local e = src:find("'", i + 1, true)
        v = utf8.codepoint(src:sub(i + 1, e - 1))
        j = e
      end
      push("char", v)
      i = j + 1
    else
      local op
      for _, o in ipairs(OPS) do if src:sub(i, i + #o - 1) == o then op = o; break end end
      op = op or c
      push("op", op)
      i = i + #op
    end
  end
  if needsSemi() then push("op", ";") end
  push("eof")
  return toks
end

local INT, FLOAT, STRING, BOOL, RUNE = { k = "int" }, { k = "float" }, { k = "string" }, { k = "bool" }, { k = "int", rune = true }
local ANY = { k = "iface" }
local BYTE, WRAPS = { k = "int", name = "byte" }, { uint8 = "0xFF", byte = "0xFF", uint16 = "0xFFFF", uint32 = "0xFFFFFFFF" }
local BASIC = { int = INT, int8 = INT, int16 = INT, int32 = INT, int64 = INT, uint = INT, uint64 = INT, uintptr = INT, rune = RUNE, byte = BYTE, uint8 = { k = "int", name = "uint8" }, uint16 = { k = "int", name = "uint16" }, uint32 = { k = "int", name = "uint32" }, float32 = FLOAT, float64 = FLOAT, string = STRING, bool = BOOL, error = { k = "iface", name = "error" }, any = ANY, comparable = ANY }
local ERR = BASIC.error

-- what the packages give back, for the conversions that depend on it
local PKG_RET = {
  ["math.Sqrt"] = FLOAT, ["math.Pow"] = FLOAT, ["math.Abs"] = FLOAT, ["math.Floor"] = FLOAT, ["math.Ceil"] = FLOAT, ["math.Sin"] = FLOAT, ["math.Cos"] = FLOAT, ["math.Tan"] = FLOAT, ["math.Log"] = FLOAT, ["math.Log2"] = FLOAT, ["math.Log10"] = FLOAT, ["math.Exp"] = FLOAT, ["math.Max"] = FLOAT, ["math.Min"] = FLOAT, ["math.Mod"] = FLOAT, ["math.Round"] = FLOAT, ["math.Trunc"] = FLOAT, ["math.Hypot"] = FLOAT, ["math.Atan"] = FLOAT, ["math.Atan2"] = FLOAT, ["math.Inf"] = FLOAT, ["math.NaN"] = FLOAT, ["math.Cbrt"] = FLOAT,
  ["strings.Repeat"] = STRING, ["strings.ToUpper"] = STRING, ["strings.ToLower"] = STRING, ["strings.TrimSpace"] = STRING, ["strings.Trim"] = STRING, ["strings.TrimLeft"] = STRING, ["strings.TrimRight"] = STRING, ["strings.TrimPrefix"] = STRING, ["strings.TrimSuffix"] = STRING, ["strings.Replace"] = STRING, ["strings.ReplaceAll"] = STRING, ["strings.Join"] = STRING, ["strings.Title"] = STRING,
  ["strings.Split"] = { k = "slice", el = STRING }, ["strings.Fields"] = { k = "slice", el = STRING }, ["strings.SplitN"] = { k = "slice", el = STRING },
  ["strings.Contains"] = BOOL, ["strings.HasPrefix"] = BOOL, ["strings.HasSuffix"] = BOOL, ["strings.ContainsRune"] = BOOL, ["strings.ContainsAny"] = BOOL, ["strings.EqualFold"] = BOOL,
  ["strings.Index"] = INT, ["strings.LastIndex"] = INT, ["strings.Count"] = INT, ["strings.IndexByte"] = INT, ["strings.Compare"] = INT,
  ["fmt.Sprintf"] = STRING, ["fmt.Sprint"] = STRING, ["fmt.Sprintln"] = STRING, ["fmt.Errorf"] = ERR, ["errors.New"] = ERR, ["strconv.Itoa"] = STRING, ["strconv.Quote"] = STRING, ["strconv.FormatInt"] = STRING, ["strconv.FormatBool"] = STRING, ["strconv.FormatFloat"] = STRING,
  ["strconv.Atoi"] = { k = "tuple", items = { INT, ERR } }, ["strconv.ParseFloat"] = { k = "tuple", items = { FLOAT, ERR } }, ["strconv.ParseInt"] = { k = "tuple", items = { INT, ERR } }, ["strconv.ParseBool"] = { k = "tuple", items = { BOOL, ERR } },
  ["unicode.IsDigit"] = BOOL, ["unicode.IsLetter"] = BOOL, ["unicode.IsSpace"] = BOOL, ["unicode.IsUpper"] = BOOL, ["unicode.IsLower"] = BOOL, ["unicode.IsPunct"] = BOOL, ["unicode.ToUpper"] = RUNE, ["unicode.ToLower"] = RUNE,
  ["rand.Intn"] = INT, ["rand.Int"] = INT, ["rand.Float64"] = FLOAT, ["time.Now"] = { k = "pkgtime" }, ["utf8.RuneCountInString"] = INT,
}
local PKG_CONST = { ["math.Pi"] = { "math.pi", FLOAT }, ["math.E"] = { "2.718281828459045", FLOAT }, ["math.MaxInt"] = { "math.maxinteger", INT }, ["math.MinInt"] = { "math.mininteger", INT }, ["math.MaxInt64"] = { "math.maxinteger", INT }, ["math.MinInt64"] = { "math.mininteger", INT }, ["math.MaxInt32"] = { "2147483647", INT }, ["math.MinInt32"] = { "(-2147483648)", INT }, ["math.MaxFloat64"] = { "1.7976931348623157e308", FLOAT }, ["math.SmallestNonzeroFloat64"] = { "5e-324", FLOAT }, ["math.MaxUint32"] = { "4294967295", INT }, ["math.Sqrt2"] = { "1.4142135623730951", FLOAT }, ["time.Millisecond"] = { "1000000", INT }, ["time.Second"] = { "1000000000", INT }, ["time.Microsecond"] = { "1000", INT }, ["time.Nanosecond"] = { "1", INT }, ["time.Minute"] = { "60000000000", INT }, ["time.Hour"] = { "3600000000000", INT } }

-- "f(a, g(b))" -> "f", "a, g(b)": the last call of a text of Lua
local function splitCall(c)
  local stack, i, n, last = {}, 1, #c, nil
  while i <= n do
    local ch = c:sub(i, i)
    if ch == '"' then
      i = i + 1
      while c:sub(i, i) ~= '"' and i <= n do
        if c:sub(i, i) == "\\" then i = i + 1 end
        i = i + 1
      end
    elseif ch == "(" then stack[#stack + 1] = i
    elseif ch == ")" then last = table.remove(stack) end
    i = i + 1
  end
  if not last or c:sub(-1) ~= ")" then return nil end
  return c:sub(1, last - 1), c:sub(last + 1, -2)
end

local function compile(src)
  local toks, pos = lex(src), 1
  local tok = toks[1]
  local out = {}
  local tmpN, labelN = 0, 0
  local scopes = { {} }
  local types, funcs, methods, interfaces = {}, {}, {}, {}
  local imports = {}
  local curFn
  local loops = {}
  local pendingLabel
  local iotaVal

  local function adv() pos = pos + 1; tok = toks[pos] end
  local function peek(k) return toks[pos + (k or 1)] end
  local function isOp(v) return tok.t == "op" and tok.v == v end
  local function isKw(v) return tok.t == "kw" and tok.v == v end
  local function err(m) syntaxError(m or ("syntax error: unexpected " .. tostring(tok.v or "EOF")), tok.line) end
  local function acceptOp(v) if isOp(v) then adv(); return true end end
  local function acceptKw(v) if isKw(v) then adv(); return true end end
  local function expectOp(v) if not acceptOp(v) then err("syntax error: unexpected " .. tostring(tok.v or "EOF") .. ", expected " .. v) end end
  local function expectKw(v) if not acceptKw(v) then err("syntax error: expected " .. v) end end
  local function name() if tok.t ~= "name" then err("syntax error: unexpected " .. tostring(tok.v) .. ", expected name") end local v = tok.v; adv(); return v end
  local function emit(s) out[#out + 1] = s end
  local function tmp() tmpN = tmpN + 1; return "_t" .. tmpN end
  local function capture(f) local s = out; out = {}; f(); local r = table.concat(out, "\n"); out = s; return r end
  local function str(s) return (string.format("%q", s):gsub("\\\n", "\\n"):gsub("\r", "\\r")) end
  local function pushScope() scopes[#scopes + 1] = {} end
  local function popScope() scopes[#scopes] = nil end
  local function bind(n, t, code)
    if n == "_" then return end
    scopes[#scopes][n] = { t = t, code = code or mangle(n) }
  end
  local function lookup(n)
    for i = #scopes, 1, -1 do
      local v = scopes[i][n]
      if v then return v end
    end
  end
  local function under(t)
    while t and t.k == "named" do
      local d = types[t.name]
      if not d then return t end
      t = d
    end
    return t
  end
  local function isFloat(t) local u = under(t); return u and u.k == "float" end
  local function isInt(t) local u = under(t); return u and u.k == "int" end
  local function isString(t) local u = under(t); return u and u.k == "string" end
  local function isValue(t)   -- a value that is copied when it is assigned: a struct or an array
    local u = under(t)
    return u and (u.k == "struct" or u.k == "array")
  end

  local parseType, expr, unary, block, simpleStmt, statement, funcLit, compositeBody

  parseType = function()
    if acceptOp("*") then return { k = "ptr", to = parseType() } end
    if acceptOp("[") then
      if acceptOp("]") then return { k = "slice", el = parseType() } end
      if acceptOp("...") then expectOp("]"); return { k = "array", el = parseType(), len = false } end
      local c = expr()
      expectOp("]")
      return { k = "array", el = parseType(), len = c }
    end
    if acceptKw("map") then
      expectOp("[")
      local k = parseType()
      expectOp("]")
      return { k = "map", key = k, val = parseType() }
    end
    if acceptKw("chan") then acceptOp("<-"); return { k = "chan", el = parseType() } end
    if isOp("<-") then adv(); expectKw("chan"); return { k = "chan", el = parseType() } end
    if acceptKw("func") then
      expectOp("(")
      while not isOp(")") do
        if tok.t == "name" and (peek().t == "name" or peek().v == "*" or peek().v == "[" or peek().v == "...") and not BASIC[tok.v] then adv() end
        acceptOp("...")
        parseType()
        if not acceptOp(",") then break end
      end
      expectOp(")")
      local ret = {}
      if acceptOp("(") then
        while not isOp(")") do
          if tok.t == "name" and (peek().t == "name" or peek().v == "*" or peek().v == "[") then adv() end
          ret[#ret + 1] = parseType()
          if not acceptOp(",") then break end
        end
        expectOp(")")
      elseif not (isOp(")") or isOp(",") or isOp("{") or isOp(";") or isOp("]") or isOp("=") or tok.t == "str") then ret[1] = parseType() end
      return { k = "func", ret = ret }
    end
    if acceptKw("struct") then
      expectOp("{")
      local fields, order = {}, {}
      while not isOp("}") do
        local names = {}
        if isOp("*") or (tok.t == "name" and (peek().v == ";" or peek().v == "}" or peek().t == "str" or peek().v == ".")) then
          -- an embedded type
          acceptOp("*")
          local nm = tok.v
          local save = pos
          local ty = parseType()
          local short = nm
          if toks[save + 1].v == "." then short = toks[save + 2].v end
          local f = { name = short, t = ty, embedded = true }
          fields[short] = f
          order[#order + 1] = f
        else
          repeat names[#names + 1] = name() until not acceptOp(",")
          local ty = parseType()
          for _, nm in ipairs(names) do
            local f = { name = nm, t = ty }
            fields[nm] = f
            order[#order + 1] = f
          end
        end
        if tok.t == "str" then adv() end
        if not acceptOp(";") then break end
      end
      expectOp("}")
      return { k = "struct", fields = fields, order = order }
    end
    if acceptKw("interface") then
      expectOp("{")
      local list = {}
      while not isOp("}") do
        if tok.t == "name" and peek().v == "(" then
          list[#list + 1] = tok.v
          adv()
          local d = 0
          repeat
            if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
            adv()
          until d == 0
          while not (isOp(";") or isOp("}")) do adv() end
        else
          while not (isOp(";") or isOp("}")) do adv() end
        end
        if not acceptOp(";") then break end
      end
      expectOp("}")
      return { k = "iface", methods = list }
    end
    if acceptOp("(") then local t = parseType(); expectOp(")"); return t end
    if tok.t == "name" then
      local n = name()
      if BASIC[n] and not types[n] then return BASIC[n] end
      if isOp(".") then
        adv()
        local m = name()
        if n == "sync" and m == "WaitGroup" then return { k = "pkg", name = "WaitGroup" } end
        if n == "sync" and (m == "Mutex" or m == "RWMutex") then return { k = "pkg", name = "Mutex" } end
        if n == "strings" and m == "Builder" then return { k = "pkg", name = "Builder" } end
        if n == "time" and m == "Duration" then return INT end
        if n == "time" and m == "Time" then return { k = "pkgtime" } end
        return { k = "pkg", name = m }
      end
      if isOp("[") and peek().v ~= "]" and (types[n] or funcs[n]) then
        -- generic arguments
        adv()
        while not isOp("]") do parseType(); if not acceptOp(",") then break end end
        expectOp("]")
      end
      return { k = "named", name = n }
    end
    err("syntax error: expected a type")
  end

  local function zero(t)
    if not t then return "nil" end
    local u = under(t)
    if not u then return "nil" end
    local k = u.k
    if k == "int" then return "0" end
    if k == "float" then return "0.0" end
    if k == "string" then return '""' end
    if k == "bool" then return "false" end
    if k == "struct" then
      if t.k == "named" then return "G." .. t.name .. "_zero()" end
      local parts = {}
      for i, f in ipairs(u.order) do parts[i] = mangle(f.name) .. "=" .. zero(f.t) end
      return "R.struct({" .. table.concat(parts, ",") .. "})"
    end
    if k == "array" then return "R.arrayOf(" .. (u.len or "0") .. ",function() return " .. zero(u.el) .. " end)" end
    if k == "pkg" then
      if u.name == "WaitGroup" then return "R.newWaitGroup()" end
      if u.name == "Mutex" then return "R.newMutex()" end
      if u.name == "Builder" then return "R.newBuilder()" end
    end
    return "nil"
  end
  local function typeName(t)
    if t.k == "named" then return t.name end
    if t.k == "ptr" then return "*" .. typeName(t.to) end
    local u = under(t)
    if u.k == "int" then return u.name or (u.rune and "int32") or "int" end
    if u.k == "float" then return "float64" end
    if u.k == "string" then return "string" end
    if u.k == "bool" then return "bool" end
    if u.k == "slice" then return "[]" .. typeName(u.el) end
    if u.k == "map" then return "map[" .. typeName(u.key) .. "]" .. typeName(u.val) end
    if u.k == "iface" then return u.name or "interface" end
    if u.k == "func" then return "func" end
    return u.k
  end
  -- value c of type from, for a place of type to
  local function conv(c, from, to)
    if to and isFloat(to) and not isFloat(from) then
      if tonumber(c) and math.type(tonumber(c)) == "integer" then return c .. ".0" end
      if from and isInt(from) then return "(" .. c .. "+0.0)" end
      if not from or under(from).k == "iface" then return "R.tofloat(" .. c .. ")" end
    end
    return c
  end
  local function copied(c, t, isLv)
    if isLv and isValue(t) then return "R.copy(" .. c .. ")" end
    return c
  end

  local function fieldPath(t, n)
    -- looks for the field in the struct and its embedded structs: returns the path and the type
    local u = under(t)
    if u and u.k == "ptr" then u = under(u.to) end
    if not u or u.k ~= "struct" then return nil end
    local f = u.fields[n]
    if f then return mangle(n), f.t end
    for _, e in ipairs(u.order) do
      if e.embedded then
        local p, ft = fieldPath(e.t, n)
        if p then return mangle(e.name) .. "." .. p, ft end
      end
    end
  end
  local function methodType(t, n)
    -- the type that has the method (possibly an embedded one): returns the owner name and the path to it
    local x = t
    if x and x.k == "ptr" then x = x.to end
    if not x then return nil end
    if x.k == "named" and methods[x.name] and methods[x.name][n] then return x.name, "", methods[x.name][n] end
    local u = under(x)
    if u and u.k == "struct" then
      for _, e in ipairs(u.order) do
        if e.embedded then
          local owner, path, m = methodType(e.t, n)
          if owner then return owner, "." .. mangle(e.name) .. path, m end
        end
      end
    end
  end

  -- a literal of a composite type, after its "{"
  compositeBody = function(t)
    local u = under(t)
    expectOp("{")
    local k = u.k
    if k == "struct" then
      local parts, seen = {}, {}
      local i = 0
      while not isOp("}") do
        i = i + 1
        local fname, ft
        if tok.t == "name" and peek().v == ":" then
          fname = name()
          adv()
          ft = u.fields[fname] and u.fields[fname].t
          if not u.fields[fname] then err("unknown field " .. fname .. " in struct literal") end
        else
          local f = u.order[i]
          if not f then err("too many values in struct literal") end
          fname, ft = f.name, f.t
        end
        local c, vt, lv
        if isOp("{") then c, vt = compositeBody(ft), ft
        else c, vt, lv = expr() end
        parts[#parts + 1] = mangle(fname) .. "=" .. conv(copied(c, vt, lv), vt, ft)
        seen[fname] = true
        acceptOp(";")
        if not acceptOp(",") then break end
      end
      acceptOp(";")
      expectOp("}")
      for _, f in ipairs(u.order) do
        if not seen[f.name] then
          local z = zero(f.t)
          if z ~= "nil" then parts[#parts + 1] = mangle(f.name) .. "=" .. z end
        end
      end
      if t.k == "named" then return "setmetatable({" .. table.concat(parts, ",") .. "},G." .. t.name .. ")" end
      return "R.struct({" .. table.concat(parts, ",") .. "})"
    elseif k == "slice" or k == "array" then
      local items, maxI, idx, keyed = {}, 0, 0, false
      while not isOp("}") do
        local c, vt, lv
        if isOp("{") then c, vt = compositeBody(u.el), u.el
        elseif isOp("&") and peek().v == "{" then adv(); c = compositeBody(u.el.to or u.el); vt = u.el
        else c, vt, lv = expr() end
        if acceptOp(":") then
          keyed = true
          idx = math.tointeger(tonumber(c)) or 0
          if isOp("{") then c, vt = compositeBody(u.el), u.el else c, vt, lv = expr() end
        end
        items[#items + 1] = "[" .. idx .. "]=" .. conv(copied(c, vt, lv), vt, u.el)
        idx = idx + 1
        if idx > maxI then maxI = idx end
        acceptOp(";")
        if not acceptOp(",") then break end
      end
      acceptOp(";")
      expectOp("}")
      local n = tostring(maxI)
      if k == "array" then
        if u.len then n = u.len else u.len = n end
      end
      return "R.sliceLit(" .. n .. ",{" .. table.concat(items, ",") .. "},function() return " .. zero(u.el) .. " end," .. tostring(k == "array") .. ")"
    elseif k == "map" then
      local parts = {}
      while not isOp("}") do
        local kc, kt
        if isOp("{") then kc = compositeBody(u.key) else kc, kt = expr() end
        expectOp(":")
        local vc, vt, lv
        if isOp("{") then vc = compositeBody(u.val); vt = u.val
        elseif isOp("&") and peek().v == "{" then adv(); vc = compositeBody(u.val.to or u.val); vt = u.val
        else vc, vt, lv = expr() end
        parts[#parts + 1] = kc
        parts[#parts + 1] = conv(copied(vc, vt, lv), vt, u.val)
        acceptOp(";")
        if not acceptOp(",") then break end
      end
      acceptOp(";")
      expectOp("}")
      return "R.mapLit(function() return " .. zero(u.val) .. " end," .. str(typeName(t)) .. (#parts > 0 and "," or "") .. table.concat(parts, ",") .. ")"
    end
    err("invalid composite literal type")
  end

  local function functionBody(params, results, recvName)
    -- params: { {name, t, variadic} }, results: { {name, t} }
    local savedFn, savedLoops = curFn, loops
    local hasDefer = false
    do
      local d, p = 0, pos
      while true do
        local x = toks[p]
        if x.t == "eof" then break end
        if x.t == "op" and x.v == "{" then d = d + 1
        elseif x.t == "op" and x.v == "}" then d = d - 1; if d == 0 then break end
        elseif x.t == "kw" and x.v == "defer" then hasDefer = true end
        p = p + 1
      end
    end
    local named = results[1] and results[1].name
    curFn = { results = results, named = named, hasDefer = hasDefer }
    loops = {}
    pushScope()
    local list, pro = {}, {}
    for i, p in ipairs(params) do
      local m = p.name and p.name ~= "_" and mangle(p.name) or ("_p" .. i)
      if p.variadic then
        list[#list + 1] = "..."
        pro[#pro + 1] = "local " .. m .. "=R.sliceFrom(...)"
        bind(p.name, { k = "slice", el = p.t })
      else
        list[#list + 1] = m
        if p.name then bind(p.name, p.t) end
        if isFloat(p.t) then pro[#pro + 1] = "if math.type(" .. m .. ")=='integer' then " .. m .. "=" .. m .. "+0.0 end" end
        if isValue(p.t) then pro[#pro + 1] = m .. "=R.copy(" .. m .. ")" end
      end
    end
    if named then
      for _, r in ipairs(results) do
        if r.name ~= "_" then
          pro[#pro + 1] = "local " .. mangle(r.name) .. "=" .. zero(r.t)
          bind(r.name, r.t)
        end
      end
    end
    local body = capture(function() block(true) end)
    popScope()
    curFn, loops = savedFn, savedLoops
    local retNames = {}
    if named then for i, r in ipairs(results) do retNames[i] = r.name == "_" and "nil" or mangle(r.name) end end
    if hasDefer then
      local rv = named and ("return " .. table.concat(retNames, ",")) or ""
      -- the body runs in a protected call; the deferred calls run after it, and recover() ends a panic
      body = "local _defers={}\nlocal _res=table.pack(pcall(function()\n" .. body .. "\nend))\n" ..
        "local _panic=R.runDefers(_defers,_res)\n" ..
        (named and "if _res[1] and _res.n>1 then local _r=_res; " .. (function()
          local parts = {}
          for i, n in ipairs(retNames) do parts[i] = n .. "=" .. "(_res[" .. (i + 1) .. "]) " end
          return ""
        end)() .. " end\n" or "") ..
        (named and (rv) or "if _res[1] then return table.unpack(_res,2,_res.n) end")
    elseif named then
      body = body .. "\ndo return " .. table.concat(retNames, ",") .. " end"
    end
    return "function(" .. table.concat(list, ",") .. ")\n" .. table.concat(pro, "\n") .. "\n" .. body .. "\nend"
  end

  local function parseSignature()
    expectOp("(")
    -- parameter names are optional: decide by looking at the first group
    local groups = {}
    while not isOp(")") do
      local g = {}
      if tok.t == "name" and (peek().v == "," or peek().v == ")") then
        g.single = tok.v
        adv()
      elseif tok.t == "name" and not (peek().v == ".") and not (peek().v == "[" and toks[pos + 2].v ~= "]" and peek().t == "op" and types[tok.v]) then
        g.name = name()
        if acceptOp("...") then g.variadic = true end
        g.t = parseType()
      else
        if acceptOp("...") then g.variadic = true end
        g.t = parseType()
      end
      groups[#groups + 1] = g
      if not acceptOp(",") then break end
    end
    expectOp(")")
    local params = {}
    local anyNamed = false
    for _, g in ipairs(groups) do if g.name then anyNamed = true end end
    if anyNamed then
      local pendingNames = {}
      for _, g in ipairs(groups) do
        if g.single then pendingNames[#pendingNames + 1] = g.single
        else
          for _, n in ipairs(pendingNames) do params[#params + 1] = { name = n, t = g.t } end
          pendingNames = {}
          params[#params + 1] = { name = g.name, t = g.t, variadic = g.variadic }
        end
      end
    else
      for _, g in ipairs(groups) do
        if g.single then params[#params + 1] = { t = BASIC[g.single] or { k = "named", name = g.single } }
        else params[#params + 1] = { t = g.t, variadic = g.variadic } end
      end
    end
    return params
  end
  local function parseResults()
    local results = {}
    if isOp("(") then
      local ps = parseSignature()
      for i, p in ipairs(ps) do results[i] = { name = p.name, t = p.t } end
    elseif not (isOp("{") or isOp(";") or isOp(")") or isOp(",") or isOp("]") or isOp("=") or isOp("}") or isOp(":=") or tok.t == "str") then
      results[1] = { t = parseType() }
    end
    return results
  end
  local function retTypeOf(results)
    if #results == 0 then return nil end
    if #results == 1 then return results[1].t end
    local items = {}
    for i, r in ipairs(results) do items[i] = r.t end
    return { k = "tuple", items = items }
  end

  funcLit = function()
    local params = parseSignature()
    local results = parseResults()
    local rt = {}
    for i, r in ipairs(results) do rt[i] = r.t end
    return functionBody(params, results), { k = "func", ret = rt }
  end

  local function callArgs(sig)
    -- after "(": the argument texts, converted when the types are known
    local parts = {}
    local i = 0
    while not isOp(")") do
      i = i + 1
      local c, t, lv = expr()
      local spread = acceptOp("...")
      if spread then c = "R.unpackSlice(" .. c .. ")"
      else
        local p = sig and (sig[i] or (sig[#sig] and sig[#sig].variadic and sig[#sig]))
        if p then c = conv(c, t, p.t) end
        c = copied(c, t, lv)
        if not p and t and t.k == "tuple" then end
      end
      parts[#parts + 1] = c
      acceptOp(";")
      if not acceptOp(",") then break end
    end
    expectOp(")")
    return parts
  end

  local function isTypeExpr()
    -- does an expression at the cursor name a type, for conversions and composite literals?
    if isOp("[") then return true end
    if isKw("map") or isKw("struct") or isKw("chan") or isKw("interface") then return true end
    if isKw("func") then return false end
    if tok.t == "name" and not lookup(tok.v) then
      if BASIC[tok.v] or types[tok.v] then return true end
    end
    return false
  end

  local function primary()
    local t = tok
    if t.t == "int" then adv(); return tostring(t.v), INT, false, true end
    if t.t == "float" then
      adv()
      local s = string.format("%.17g", t.v)
      if not s:find("[%.en]") then s = s .. ".0" end
      return s, FLOAT
    end
    if t.t == "char" then adv(); return tostring(t.v), RUNE end
    if t.t == "str" then adv(); return str(t.v), STRING end
    if isOp("(") then
      adv()
      if isOp("*") and peek().t == "name" and types[peek().v] and toks[pos + 2].v == ")" then
        -- (*T)(x)
        local ty = parseType()
        expectOp(")")
        if isOp("(") then adv(); local c = expr(); expectOp(")"); return c, ty end
        return "nil", ty
      end
      local c, ty, lv = expr()
      expectOp(")")
      return "(" .. c .. ")", ty, lv
    end
    if isKw("func") then adv(); return funcLit() end
    if isTypeExpr() then
      local ty = parseType()
      if isOp("{") then return compositeBody(ty), ty end
      expectOp("(")
      local c, from = expr()
      acceptOp(",")
      expectOp(")")
      local u = under(ty)
      if u.k == "float" then
        if isInt(from) then return "(" .. c .. "+0.0)", ty end
        return "R.tofloat(" .. c .. ")", ty
      end
      if u.k == "int" then
        local r = isFloat(from) and ("R.f2i(" .. c .. ")") or ((from and isInt(from)) and c or ("R.toint(" .. c .. ")"))
        local mask = WRAPS[u.name or ""]
        if mask then r = "((" .. r .. ")&" .. mask .. ")" end
        return r, ty
      end
      if u.k == "string" then
        if from and isString(from) then return c, ty end
        if from and isInt(from) then return "R.runeStr(" .. c .. ")", ty end
        return "R.toString(" .. c .. ")", ty
      end
      if u.k == "slice" and isString(from) then
        local el = under(u.el)
        if el.rune then return "R.runes(" .. c .. ")", ty end
        return "R.bytes(" .. c .. ")", ty
      end
      return c, ty
    end
    if t.t == "name" then
      adv()
      local n = t.v
      if n == "_" then return "_", nil, true end
      local b = lookup(n)
      if b then
        if b.const then return b.code, b.t end
        return b.code, b.t, true
      end
      if n == "nil" then return "nil", nil end
      if n == "true" or n == "false" then return n, BOOL end
      if n == "iota" then return tostring(iotaVal or 0), INT end
      if imports[n] and isOp(".") then
        adv()
        local m = name()
        local key = n .. "." .. m
        local cst = PKG_CONST[key]
        if cst then return cst[1], cst[2] end
        if key == "os.Args" then return "R.args", { k = "slice", el = STRING } end
        if key == "os.Stdout" then return "R.stdout", ANY end
        if key == "os.Stderr" then return "R.stderr", ANY end
        if key == "os.Stdin" then return "R.stdin", ANY end
        return "R.pkg." .. n .. "." .. m, { k = "func", pkgRet = PKG_RET[key] }
      end
      if funcs[n] then
        if isOp("[") then
          -- generic arguments
          local save = pos
          adv()
          local ok = pcall(function()
            while not isOp("]") do parseType(); if not acceptOp(",") then break end end
            expectOp("]")
          end)
          if not ok or not isOp("(") then pos = save; tok = toks[pos] end
        end
        return "G." .. mangle(n), { k = "func", sig = funcs[n].params, results = funcs[n].results, ret = {} }
      end
      local B = { len = 1, cap = 1, append = 1, make = 1, new = 1, panic = 1, recover = 1, print = 1, println = 1, delete = 1, copy = 1, close = 1, min = 1, max = 1, clear = 1 }
      if B[n] and isOp("(") then
        adv()
        if n == "make" then
          local ty = parseType()
          local args = {}
          while acceptOp(",") do
            if isOp(")") then break end
            args[#args + 1] = (expr())
          end
          expectOp(")")
          local u = under(ty)
          if u.k == "slice" then return "R.make(" .. (args[1] or "0") .. "," .. (args[2] or "nil") .. ",function() return " .. zero(u.el) .. " end)", ty end
          if u.k == "map" then return "R.mapLit(function() return " .. zero(u.val) .. " end," .. str(typeName(ty)) .. ")", ty end
          return "R.chan(" .. (args[1] or "0") .. ",function() return " .. zero(u.el) .. " end)", ty
        elseif n == "new" then
          local ty = parseType()
          expectOp(")")
          if isValue(ty) then return zero(ty), { k = "ptr", to = ty } end
          return "R.newBox(" .. zero(ty) .. ")", { k = "ptr", to = ty }
        elseif n == "append" then
          local c, ty = expr()
          local u = ty and under(ty)
          local el = u and u.el
          local parts = {}
          local spread = false
          while acceptOp(",") do
            if isOp(")") then break end
            local a, at, lv
            if isOp("{") and el then a, at = compositeBody(el), el else a, at, lv = expr() end
            if acceptOp("...") then spread = true; parts[#parts + 1] = a
            else parts[#parts + 1] = conv(copied(a, at, lv), at, el) end
          end
          expectOp(")")
          if spread then return "R.appendSlice(" .. c .. "," .. parts[1] .. ")", ty end
          return "R.append(" .. c .. (#parts > 0 and "," or "") .. table.concat(parts, ",") .. ")", ty
        end
        local args = callArgs()
        local a = table.concat(args, ",")
        if n == "len" then return "R.len(" .. a .. ")", INT end
        if n == "cap" then return "R.cap(" .. a .. ")", INT end
        if n == "panic" then return "R.panic(" .. a .. ")", nil end
        if n == "recover" then return "R.recover()", ANY end
        if n == "delete" then return "R.delete(" .. a .. ")", nil end
        if n == "copy" then return "R.copyInto(" .. a .. ")", INT end
        if n == "close" then return "R.closeChan(" .. a .. ")", nil end
        if n == "print" or n == "println" then return "R.builtinPrint(" .. str(n) .. (#args > 0 and "," or "") .. a .. ")", nil end
        if n == "clear" then return "R.clear(" .. a .. ")", nil end
        return "R." .. n .. "(" .. a .. ")", INT
      end
      syntaxError("undefined: " .. n, t.line)
    end
    err()
  end

  local function postfix()
    local c, t, lv = primary()
    while true do
      if isOp(".") then
        adv()
        if acceptOp("(") then
          -- a type assertion
          if acceptKw("type") then
            expectOp(")")
            return c, { k = "typeswitch" }
          end
          local ty = parseType()
          expectOp(")")
          c = "R.assert(" .. c .. "," .. str(typeName(ty)) .. ",G)"
          t = { k = "assert", to = ty }
          lv = false
        else
          local n = name()
          local b = t and (t.k == "ptr" and under(t.to) or under(t))
          if isOp("(") then
            adv()
            local owner, path, m = methodType(t, n)
            if owner then
              local args = callArgs(m.params)
              local self = c .. path
              if m.ptr and t.k ~= "ptr" and not isValue({ k = "named", name = owner }) then
                self = "R.addr(function() return " .. self .. " end,function(_v) " .. self .. "=_v end)"
              end
              c = "G." .. owner .. "." .. mangle(n) .. "(" .. self .. (#args > 0 and "," or "") .. table.concat(args, ",") .. ")"
              t = retTypeOf(m.results)
            elseif b and b.k == "struct" and fieldPath(t, n) then
              local p, ft = fieldPath(t, n)
              local fr = under(ft)
              local args = callArgs(fr and fr.sig)
              c = c .. "." .. p .. "(" .. table.concat(args, ",") .. ")"
              t = fr and fr.ret and (#fr.ret == 1 and fr.ret[1] or (#fr.ret > 1 and { k = "tuple", items = fr.ret })) or nil
            else
              local args = callArgs()
              if t and t.k == "pkgtime" then c = "R.timeMethod(" .. c .. "," .. str(n) .. ")"; t = (n == "Sub" or n == "UnixNano" or n == "Unix" or n == "UnixMilli") and INT or FLOAT
              else
                c = "R.callMethod(" .. c .. "," .. str(n) .. (#args > 0 and "," or "") .. table.concat(args, ",") .. ")"
                local iface = b and b.k == "pkg" and b.name
                if iface == "Builder" and n == "String" then t = STRING elseif iface == "Builder" then t = INT else t = (n == "Error" or n == "String") and STRING or nil end
              end
            end
            lv = false
          else
            local p, ft = fieldPath(t, n)
            if p then
              c = c .. "." .. p
              t = ft
              lv = true
            else
              local owner, path = methodType(t, n)
              if owner then
                c = "R.bindMethod(G." .. owner .. "." .. mangle(n) .. "," .. c .. path .. ")"
                t = { k = "func", ret = {} }
                lv = false
              else
                c = c .. "." .. mangle(n)
                t = nil
                lv = true
              end
            end
          end
        end
      elseif isOp("(") then
        adv()
        local args
        local sig = t and t.sig
        args = callArgs(sig)
        if c:sub(1, 8) == "function" then c = "(" .. c .. ")" end
        c = c .. "(" .. table.concat(args, ",") .. ")"
        if t and t.pkgRet then t = t.pkgRet
        elseif t and t.results then t = retTypeOf(t.results)
        elseif t and t.ret then t = #t.ret == 1 and t.ret[1] or (#t.ret > 1 and { k = "tuple", items = t.ret } or nil)
        else t = under(t) and under(t).ret and (#under(t).ret == 1 and under(t).ret[1] or nil) or nil end
        lv = false
      elseif isOp("[") then
        adv()
        local a, b, third
        local isSlice = false
        if not isOp(":") then a = expr() end
        if acceptOp(":") then
          isSlice = true
          if not (isOp("]") or isOp(":")) then b = expr() end
          if acceptOp(":") then third = expr() end
        end
        expectOp("]")
        local u = t and under(t)
        if u and u.k == "ptr" then u = under(u.to) end
        if isSlice then
          if u and u.k == "string" then
            c = "R.strSlice(" .. c .. "," .. (a or "0") .. "," .. (b or "nil") .. ")"
          else
            c = "R.slice(" .. c .. "," .. (a or "0") .. "," .. (b or "nil") .. "," .. (third or "nil") .. ")"
            if u and u.k == "array" then t = { k = "slice", el = u.el } end
          end
          lv = false
        elseif u and u.k == "map" then
          c, t, lv = "R.mapGet(" .. c .. "," .. a .. ")", u.val, { map = c, key = a }
        elseif u and u.k == "string" then
          c, t, lv = "R.strIdx(" .. c .. "," .. a .. ")", BYTE, false
        elseif u and (u.k == "slice" or u.k == "array") then
          c, t, lv = "R.idx(" .. c .. "," .. a .. ")", u.el, { slice = c, idx = a }
        else
          -- generic instantiation or unknown container
          c, t, lv = "R.idxAny(" .. c .. "," .. a .. ")", nil, { any = c, idx = a }
        end
      elseif isOp("{") and t and t.k == "named" and not lookup(t.name) and types[t.name] and false then
        break
      else break end
    end
    return c, t, lv
  end

  unary = function()
    if isOp("-") then
      adv()
      local c, t = unary()
      return "(-" .. c .. ")", t
    end
    if isOp("+") then adv(); return unary() end
    if isOp("!") then adv(); local c = unary(); return "(not " .. c .. ")", BOOL end
    if isOp("^") then adv(); local c, t = unary(); return "(~" .. c .. ")", t end
    if isOp("<-") then
      adv()
      local c, t = unary()
      local u = t and under(t)
      return "R.recv(" .. c .. ")", { k = "recv", el = u and u.el }
    end
    if isOp("*") then
      adv()
      local c, t = unary()
      local u = t and under(t)
      if u and u.k == "ptr" then
        if isValue(u.to) then return c, u.to, true end
        return c .. ".v", u.to, true
      end
      return "R.deref(" .. c .. ")", nil, false
    end
    if isOp("&") then
      adv()
      if isOp("[") or (tok.t == "name" and types[tok.v] and not lookup(tok.v) and peek().v == "{") then
        local ty = parseType()
        return compositeBody(ty), { k = "ptr", to = ty }
      end
      local c, t, lv = unary()
      if isValue(t) then return c, { k = "ptr", to = t } end
      if type(lv) == "table" and lv.slice then return "R.addrIdx(" .. lv.slice .. "," .. lv.idx .. ")", { k = "ptr", to = t } end
      return "R.addr(function() return " .. c .. " end,function(_v) " .. c .. "=_v end)", { k = "ptr", to = t }
    end
    return postfix()
  end
  local function arith(op, a, ta, b, tb)
    if ta and ta.k == "tuple" then ta = ta.items[1] end
    if isString(ta) or isString(tb) then
      if op == "+" then return "(" .. a .. ".." .. b .. ")", ta or tb end
    end
    local isF = isFloat(ta) or isFloat(tb)
    local rt = isF and (isFloat(ta) and ta or tb) or (ta or tb)
    if ta and ta.k == "assert" then rt = ta.to end
    if op == "/" then
      if isF then return "(" .. a .. "/" .. b .. ")", rt end
      if ta and tb and isInt(ta) and isInt(tb) then return "R.idiv(" .. a .. "," .. b .. ")", rt end
      return "R.div(" .. a .. "," .. b .. ")", rt
    end
    if op == "%" then return "R.imod(" .. a .. "," .. b .. ")", rt end
    if op == "&^" then return "(" .. a .. "&~" .. b .. ")", rt end
    if op == "^" then return "(" .. a .. "~" .. b .. ")", rt end
    local e = "(" .. a .. op .. b .. ")"
    local mask = rt and under(rt) and WRAPS[under(rt).name or ""]
    if mask and (op == "+" or op == "-" or op == "*" or op == "<<") then e = "(" .. e .. "&" .. mask .. ")" end
    return e, rt
  end
  local LV = { { "*", "/", "%", "<<", ">>", "&", "&^" }, { "+", "-", "|", "^" }, { "==", "!=", "<", "<=", ">", ">=" }, { "&&" }, { "||" } }
  local LEVELS = {}
  for i, l in ipairs(LV) do LEVELS[i] = {}; for _, o in ipairs(l) do LEVELS[i][o] = true end end
  local noComposite = false
  local function bin(l)
    if l == 0 then return unary() end
    local a, ta, lv = bin(l - 1)
    while tok.t == "op" and LEVELS[l][tok.v] do
      local op = tok.v
      adv()
      local b, tb = bin(l - 1)
      lv = false
      if l == 5 then a = "(" .. a .. " or " .. b .. ")"; ta = BOOL
      elseif l == 4 then a = "(" .. a .. " and " .. b .. ")"; ta = BOOL
      elseif l == 3 then
        local map = { ["=="] = "==", ["!="] = "~=", ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=" }
        if (op == "==" or op == "!=") and (isValue(ta) or isValue(tb)) then
          a = (op == "!=" and "(not " or "(") .. "R.deepEq(" .. a .. "," .. b .. "))"
        else
          a = "(" .. a .. map[op] .. b .. ")"
        end
        ta = BOOL
      else a, ta = arith(op, a, ta, b, tb) end
    end
    return a, ta, lv
  end
  expr = function() return bin(5) end

  -- ---- statements ----
  local function storeTo(c, lv, v)
    if type(lv) == "table" then
      if lv.map then return "R.mapSet(" .. lv.map .. "," .. lv.key .. "," .. v .. ")" end
      if lv.slice then return "R.setIdx(" .. lv.slice .. "," .. lv.idx .. "," .. v .. ")" end
      if lv.any then return "R.setAny(" .. lv.any .. "," .. lv.idx .. "," .. v .. ")" end
    end
    return c .. "=" .. v
  end
  -- the value of a call with several results, or a value with "ok": a, ok := m[k]; v, ok := x.(T); v, ok := <-ch
  local function commaOk(c, t, lv)
    if type(lv) == "table" and lv.map then return "R.mapGet2(" .. lv.map .. "," .. lv.key .. ")", { k = "tuple", items = { t, BOOL } } end
    if t and t.k == "assert" then return (c:gsub("^R%.assert%(", "R.assert2(")), { k = "tuple", items = { t.to, BOOL } } end
    if t and t.k == "recv" then return (c:gsub("^R%.recv%(", "R.recv2(")), { k = "tuple", items = { t.el, BOOL } } end
    return c, t
  end
  local function fixType(t)
    if t and t.k == "assert" then return t.to end
    if t and t.k == "recv" then return t.el end
    return t
  end

  local function exprList()
    local list = {}
    repeat
      local c, t, lv = expr()
      list[#list + 1] = { c = c, t = t, lv = lv }
    until not acceptOp(",")
    return list
  end

  simpleStmt = function()
    -- returns nothing; emits the statement. A statement that declares names leaves them in the current scope.
    local lhs = exprListSafe and nil
    if isKw("func") and false then end
    local startPos = pos
    -- a := b needs names, which may be new: look ahead
    do
      local p = pos
      local names = {}
      while toks[p].t == "name" do
        names[#names + 1] = toks[p].v
        p = p + 1
        if toks[p].t == "op" and toks[p].v == "," then p = p + 1 else break end
      end
      if toks[p].t == "op" and toks[p].v == ":=" and #names > 0 then
        pos = p + 1; tok = toks[pos]
        if isKw("range") then
          return { range = true, names = names, define = true }
        end
        local vals = exprList()
        if #vals == 1 and #names > 1 then
          local c, t = commaOk(vals[1].c, vals[1].t, vals[1].lv)
          local ts = t and t.k == "tuple" and t.items or {}
          local locals, assign = {}, {}
          for i, n in ipairs(names) do
            local isNew = n == "_" or not scopes[#scopes][n]
            locals[i] = n == "_" and ("_u" .. i) or (scopes[#scopes][n] and mangle(n) or mangle(n))
          end
          local anyOld = false
          for _, n in ipairs(names) do if n ~= "_" and scopes[#scopes][n] then anyOld = true end end
          if anyOld then
            local fresh = {}
            for i, n in ipairs(names) do
              if n ~= "_" and not scopes[#scopes][n] then fresh[#fresh + 1] = mangle(n) end
            end
            if #fresh > 0 then emit("local " .. table.concat(fresh, ",")) end
            emit(table.concat(locals, ",") .. "=" .. c)
          else
            emit("local " .. table.concat(locals, ",") .. "=" .. c)
          end
          for i, n in ipairs(names) do
            if not scopes[#scopes][n] or ts[i] then bind(n, fixType(ts[i])) end
          end
        else
          if #vals ~= #names then err("assignment mismatch: " .. #names .. " variables but " .. #vals .. " values") end
          local anyOld = false
          for _, n in ipairs(names) do if n ~= "_" and scopes[#scopes][n] then anyOld = true end end
          local codes = {}
          for i, v in ipairs(vals) do
            local vt = fixType(v.t)
            codes[i] = copied(v.c, vt, v.lv)
          end
          if anyOld then
            local fresh, locals = {}, {}
            for i, n in ipairs(names) do
              locals[i] = n == "_" and "_u" or mangle(n)
              if n == "_" or not scopes[#scopes][n] then fresh[#fresh + 1] = locals[i] end
            end
            if #fresh > 0 then emit("local " .. table.concat(fresh, ",")) end
            emit(table.concat(locals, ",") .. "=" .. table.concat(codes, ","))
          else
            local locals = {}
            for i, n in ipairs(names) do locals[i] = n == "_" and ("_u" .. i) or mangle(n) end
            emit("local " .. table.concat(locals, ",") .. "=" .. table.concat(codes, ","))
          end
          for i, n in ipairs(names) do bind(n, fixType(vals[i].t)) end
        end
        return
      end
    end
    if isKw("range") then return { range = true, names = {} } end
    local lvals = exprList()
    if isOp(":=") then err() end
    if isOp("=") then
      adv()
      if isKw("range") then
        return { range = true, lvals = lvals }
      end
      local vals = exprList()
      if #vals == 1 and #lvals > 1 then
        local c = commaOk(vals[1].c, vals[1].t, vals[1].lv)
        local tmps = {}
        for i = 1, #lvals do tmps[i] = tmp() end
        emit("do local " .. table.concat(tmps, ",") .. "=" .. c)
        for i, l in ipairs(lvals) do
          if l.c ~= "_" then emit(storeTo(l.c, l.lv, tmps[i])) end
        end
        emit("end")
      elseif #lvals == 1 then
        local l, v = lvals[1], vals[1]
        local value = conv(copied(v.c, fixType(v.t), v.lv), fixType(v.t), fixType(l.t))
        if l.c == "_" then emit("local _=" .. value)
        else emit(storeTo(l.c, l.lv, value)) end
      else
        local tmps, codes = {}, {}
        for i, v in ipairs(vals) do tmps[i] = tmp(); codes[i] = conv(copied(v.c, fixType(v.t), v.lv), fixType(v.t), fixType(lvals[i].t)) end
        emit("do local " .. table.concat(tmps, ",") .. "=" .. table.concat(codes, ","))
        for i, l in ipairs(lvals) do
          if l.c ~= "_" then emit(storeTo(l.c, l.lv, tmps[i])) end
        end
        emit("end")
      end
      return
    end
    local l = lvals[1]
    if isOp("++") or isOp("--") then
      local op = tok.v == "++" and "+" or "-"
      adv()
      local ex, et = arith(op, l.c, l.t, "1", INT)
      emit(storeTo(l.c, l.lv, ex))
      return
    end
    if tok.t == "op" and tok.v:sub(-1) == "=" and #tok.v >= 2 and tok.v ~= "==" and tok.v ~= "!=" and tok.v ~= "<=" and tok.v ~= ">=" then
      local op = tok.v:sub(1, -2)
      adv()
      local c, t = expr()
      local value = conv(c, t, isFloat(l.t) and l.t or nil)
      local ex = arith(op, l.c, l.t, value, t)
      emit(storeTo(l.c, l.lv, ex))
      return
    end
    if isOp("<-") then
      adv()
      local c = expr()
      emit("R.send(" .. l.c .. "," .. c .. ")")
      return
    end
    -- an expression statement
    local c = l.c
    if c:sub(-1) == ")" and not c:find("^%(") then emit(c)
    else emit("local _=" .. c) end
  end

  local function varDecl(isGlobal)
    local function one()
      local names = {}
      repeat names[#names + 1] = name() until not acceptOp(",")
      local t
      if not isOp("=") then t = parseType() end
      local prefix = isGlobal and "G." or ""
      local function target(n)
        if n == "_" then return isGlobal and "G._" or "_u" end
        return isGlobal and ("G." .. mangle(n)) or mangle(n)
      end
      if acceptOp("=") then
        local vals = exprList()
        if #vals == 1 and #names > 1 then
          local c, ct = commaOk(vals[1].c, vals[1].t, vals[1].lv)
          local tg = {}
          for i, n in ipairs(names) do tg[i] = target(n) end
          emit((isGlobal and "" or "local ") .. table.concat(tg, ",") .. "=" .. c)
          for i, n in ipairs(names) do bind(n, t or (ct and ct.items and ct.items[i]), isGlobal and target(n) or nil) end
        else
          for i, n in ipairs(names) do
            local v = vals[i]
            if not v then err("missing value in declaration") end
            local vt = fixType(v.t)
            emit((isGlobal and "" or "local ") .. target(n) .. "=" .. conv(copied(v.c, vt, v.lv), vt, t))
            bind(n, t or vt, isGlobal and target(n) or nil)
          end
        end
      else
        for _, n in ipairs(names) do
          emit((isGlobal and "" or "local ") .. target(n) .. "=" .. zero(t))
          bind(n, t, isGlobal and target(n) or nil)
        end
      end
    end
    if acceptOp("(") then
      while not isOp(")") do
        one()
        if not acceptOp(";") then break end
      end
      expectOp(")")
    else one() end
  end
  local function constDecl(isGlobal)
    local function group()
      local lastT, lastTokens
      iotaVal = 0
      local function one()
        local names = {}
        repeat names[#names + 1] = name() until not acceptOp(",")
        local t
        if not (isOp("=") or isOp(";") or isOp(")")) then t = parseType() end
        local startTok
        if isOp("=") then
          adv()
          startTok = pos
          lastTokens = pos
          lastT = t
        else
          -- repeats the expression before it, with the next iota
          startTok = nil
        end
        local here = pos
        if not startTok then pos = lastTokens; tok = toks[pos] end
        for i, n in ipairs(names) do
          local c, ct = expr()
          if i < #names then acceptOp(",") end
          local useT = t or lastT or ct
          if useT and isFloat(useT) then c = conv(c, ct, useT) end
          scopes[#scopes][n] = { code = c, t = useT, const = true }
        end
        if not startTok then pos = here; tok = toks[pos] end
        iotaVal = iotaVal + 1
      end
      if acceptOp("(") then
        while not isOp(")") do
          one()
          if not acceptOp(";") then break end
        end
        expectOp(")")
      else one() end
      iotaVal = nil
    end
    group()
  end

  block = function(noScope)
    expectOp("{")
    if not noScope then pushScope() end
    while not isOp("}") do
      if tok.t == "eof" then err("syntax error: unexpected EOF, expected }") end
      statement()
      if not isOp("}") then
        if not acceptOp(";") then err("syntax error: unexpected " .. tostring(tok.v) .. " at end of statement") end
      end
    end
    adv()
    if not noScope then popScope() end
  end

  local function retValue(list)
    -- converts by the declared results
    local res = curFn and curFn.results or {}
    local codes = {}
    for i, v in ipairs(list) do
      local want = res[i] and res[i].t
      local vt = fixType(v.t)
      codes[i] = conv(copied(v.c, vt, v.lv), vt, want)
    end
    return table.concat(codes, ",")
  end

  statement = function()
    local t = tok
    if t.t == "kw" then
      local v = t.v
      if v == "var" then adv(); varDecl(false); return
      elseif v == "const" then adv(); constDecl(false); return
      elseif v == "type" then
        adv()
        local function one()
          local n = name()
          acceptOp("=")
          types[n] = parseType()
          emit("G." .. n .. "=G." .. n .. " or R.newType(" .. str(n) .. ")")
          if under({ k = "named", name = n }).k == "struct" then
            emit("G." .. n .. "_zero=function() return setmetatable({},G." .. n .. ") end")
          end
        end
        if acceptOp("(") then
          while not isOp(")") do one(); if not acceptOp(";") then break end end
          expectOp(")")
        else one() end
        return
      elseif v == "return" then
        adv()
        if isOp(";") or isOp("}") then
          if curFn.named then
            local names = {}
            for i, r in ipairs(curFn.results) do names[i] = r.name == "_" and "nil" or mangle(r.name) end
            if curFn.hasDefer then
              for i = 1, #names do end
              emit("do return " .. table.concat(names, ",") .. " end")
            else
              emit("do return " .. table.concat(names, ",") .. " end")
            end
          else emit("do return end") end
          return
        end
        local list = exprList()
        if curFn.named and curFn.hasDefer then
          local names = {}
          for i, r in ipairs(curFn.results) do names[i] = r.name == "_" and "_u" or mangle(r.name) end
          emit(table.concat(names, ",") .. "=" .. retValue(list))
          emit("do return end")
          return
        end
        emit("do return " .. retValue(list) .. " end")
        return
      elseif v == "if" then
        adv()
        pushScope()
        emit("do")
        local function ifRest()
          local saveComposite = noComposite
          -- if init; cond {
          local c, ct
          local p, d = pos, 0
          local hasInit = false
          while true do
            local x = toks[p]
            if x.t == "eof" then break end
            if x.t == "op" then
              if x.v == "(" or x.v == "[" then d = d + 1
              elseif x.v == ")" or x.v == "]" then d = d - 1
              elseif x.v == "{" and d == 0 then
                -- a composite literal needs parentheses here in Go, or a func body
                if not (toks[p - 1].t == "kw" and toks[p - 1].v == "func") and not (toks[p - 1].v == ")" and false) then break end
                local dd = 0
                repeat
                  if toks[p].v == "{" then dd = dd + 1 elseif toks[p].v == "}" then dd = dd - 1 end
                  p = p + 1
                until dd == 0
                p = p - 1
              elseif x.v == ";" and d == 0 then hasInit = true; break end
            end
            p = p + 1
          end
          if hasInit then
            simpleStmt()
            expectOp(";")
          end
          c = expr()
          emit("if " .. c .. " then")
          block()
          if acceptKw("else") then
            if isKw("if") then
              adv()
              emit("else")
              pushScope()
              emit("do")
              ifRest()
              emit("end")
              popScope()
            else
              emit("else")
              block()
            end
          end
          emit("end")
        end
        ifRest()
        emit("end")
        popScope()
        return
      elseif v == "for" then
        adv()
        labelN = labelN + 1
        local rec = { cont = "cont_" .. labelN, brk = "brk_" .. labelN, isLoop = true, label = pendingLabel }
        pendingLabel = nil
        pushScope()
        emit("do")
        loops[#loops + 1] = rec
        if isOp("{") then
          emit("while true do")
          block()
          emit("::" .. rec.cont .. "::")
          emit("end")
        else
          -- for cond {, for init; cond; post {, for x := range y {
          local p, d, semis = pos, 0, 0
          local hasRange = false
          while true do
            local x = toks[p]
            if x.t == "eof" then break end
            if x.t == "kw" and x.v == "range" and d == 0 then hasRange = true end
            if x.t == "op" then
              if x.v == "(" or x.v == "[" then d = d + 1
              elseif x.v == ")" or x.v == "]" then d = d - 1
              elseif x.v == ";" and d == 0 then semis = semis + 1
              elseif x.v == "{" and d == 0 then
                if not (toks[p - 1].t == "kw" and toks[p - 1].v == "func") then break end
                local dd = 0
                repeat
                  if toks[p].v == "{" then dd = dd + 1 elseif toks[p].v == "}" then dd = dd - 1 end
                  p = p + 1
                until dd == 0
                p = p - 1
              end
            end
            p = p + 1
          end
          if hasRange then
            local r = simpleStmt()
            expectKw("range")
            local c, ct = expr()
            local u = ct and under(ct)
            if u and u.k == "ptr" then u = under(u.to) end
            local a, b = tmp(), tmp()
            local keyT, valT = INT, nil
            local kind = u and u.k
            if kind == "slice" or kind == "array" then valT = u.el
            elseif kind == "string" then valT = RUNE
            elseif kind == "map" then keyT, valT = u.key, u.val
            elseif kind == "chan" then keyT = u.el
            elseif kind == "int" then keyT = INT end
            emit("for " .. a .. "," .. b .. " in R.range(" .. c .. ") do")
            pushScope()
            if r.names and r.names[1] then
              if r.define then
                local n1, n2 = r.names[1], r.names[2]
                if n1 ~= "_" then emit("local " .. mangle(n1) .. "=" .. a); bind(n1, keyT) end
                if n2 and n2 ~= "_" then
                  emit("local " .. mangle(n2) .. "=" .. copied(b, valT, true))
                  bind(n2, valT)
                end
              end
            elseif r.lvals then
              if r.lvals[1] and r.lvals[1].c ~= "_" then emit(storeTo(r.lvals[1].c, r.lvals[1].lv, a)) end
              if r.lvals[2] and r.lvals[2].c ~= "_" then emit(storeTo(r.lvals[2].c, r.lvals[2].lv, b)) end
            end
            block()
            popScope()
            emit("::" .. rec.cont .. "::")
            emit("end")
          elseif semis == 0 then
            local c = expr()
            emit("while " .. c .. " do")
            block()
            emit("::" .. rec.cont .. "::")
            emit("end")
          else
            if not isOp(";") then simpleStmt() end
            expectOp(";")
            local c = "true"
            if not isOp(";") then c = expr() end
            expectOp(";")
            local post = ""
            if not isOp("{") then post = capture(function() simpleStmt() end) end
            -- each round has its own copy of the loop variables (Go 1.22), for the functions made inside
            local names = {}
            for n, b in pairs(scopes[#scopes]) do if not b.const then names[#names + 1] = mangle(n) end end
            table.sort(names)
            local closures = false
            do
              local dd, q = 0, pos
              while true do
                local x = toks[q]
                if x.t == "eof" then break end
                if x.t == "kw" and x.v == "func" then closures = true end
                if x.t == "op" and x.v == "{" then dd = dd + 1
                elseif x.t == "op" and x.v == "}" then dd = dd - 1; if dd == 0 then break end end
                q = q + 1
              end
            end
            emit("while " .. c .. " do")
            if closures and #names > 0 then
              local copies = {}
              for i, n in ipairs(names) do copies[i] = "_c_" .. n end
              emit("local " .. table.concat(copies, ",") .. "=" .. table.concat(names, ","))
              emit("do local " .. table.concat(names, ",") .. "=" .. table.concat(copies, ","))
              block()
              emit("::" .. rec.cont .. "::")
              emit(table.concat(copies, ",") .. "=" .. table.concat(names, ","))
              emit("end")
              emit(table.concat(names, ",") .. "=" .. table.concat(copies, ","))
            else
              block()
              emit("::" .. rec.cont .. "::")
            end
            emit(post)
            emit("end")
          end
        end
        loops[#loops] = nil
        emit("end")
        emit("::" .. rec.brk .. "::")
        popScope()
        return
      elseif v == "switch" then
        adv()
        pushScope()
        emit("do")
        labelN = labelN + 1
        local rec = { brk = "brk_" .. labelN, label = pendingLabel }
        pendingLabel = nil
        -- init; tag
        local subject, subjT, typeSwitch, tsName
        if not isOp("{") then
          local p, d, isInit = pos, 0, false
          while true do
            local x = toks[p]
            if x.t == "eof" then break end
            if x.t == "op" then
              if x.v == "(" or x.v == "[" then d = d + 1
              elseif x.v == ")" or x.v == "]" then d = d - 1
              elseif x.v == "{" and d == 0 then break
              elseif x.v == ";" and d == 0 then isInit = true; break end
            end
            p = p + 1
          end
          if isInit then
            simpleStmt()
            expectOp(";")
          end
        end
        if not isOp("{") then
          if tok.t == "name" and peek().v == ":=" then
            tsName = tok.v
            adv(); adv()
          end
          local c, ct = expr()
          if ct and ct.k == "typeswitch" then
            typeSwitch = true
            subject = tmp()
            emit("local " .. subject .. "=" .. c)
          else
            subject = tmp()
            emit("local " .. subject .. "=" .. c)
            subjT = ct
          end
        end
        expectOp("{")
        loops[#loops + 1] = rec
        local clauses = {}
        local base_ = labelN
        local i = 0
        local bodies = capture(function()
          while not isOp("}") do
            i = i + 1
            local label = "case_" .. base_ .. "_" .. i
            local cl = { label = label }
            local singleT
            if acceptKw("default") then cl.default = true
            else
              expectKw("case")
              cl.tests = {}
              repeat
                if typeSwitch then
                  if tok.t == "name" and tok.v == "nil" then adv(); cl.tests[#cl.tests + 1] = subject .. "==nil"
                  else
                    local ty = parseType()
                    singleT = ty
                    cl.tests[#cl.tests + 1] = "R.isType(" .. subject .. "," .. str(typeName(ty)) .. ",G)"
                  end
                elseif subject then
                  local c = expr()
                  cl.tests[#cl.tests + 1] = "R.eq(" .. subject .. "," .. c .. ")"
                else cl.tests[#cl.tests + 1] = (expr()) end
              until not acceptOp(",")
              if #cl.tests > 1 then singleT = nil end
            end
            expectOp(":")
            clauses[#clauses + 1] = cl
            emit("::" .. label .. "::")
            emit("do")
            pushScope()
            if tsName and tsName ~= "_" then
              emit("local " .. mangle(tsName) .. "=" .. subject)
              bind(tsName, singleT)
            end
            local fell = false
            while not (isKw("case") or isKw("default") or isOp("}")) do
              if isKw("fallthrough") then
                adv()
                fell = true
                acceptOp(";")
              else
                statement()
                if not isOp("}") then acceptOp(";") end
              end
            end
            popScope()
            emit("end")
            if not fell then emit("goto " .. rec.brk) end
          end
        end)
        adv()
        loops[#loops] = nil
        local def
        for _, cl in ipairs(clauses) do
          if cl.default then def = cl.label
          else emit("if " .. table.concat(cl.tests, " or ") .. " then goto " .. cl.label .. " end") end
        end
        emit("goto " .. (def or rec.brk))
        emit(bodies)
        emit("::" .. rec.brk .. "::")
        emit("end")
        popScope()
        return
      elseif v == "select" then
        adv()
        expectOp("{")
        labelN = labelN + 1
        local rec = { brk = "brk_" .. labelN, label = pendingLabel }
        pendingLabel = nil
        loops[#loops + 1] = rec
        local cases = {}
        local hasDefault = false
        local base_ = labelN
        local chosen = tmp()
        local val, ok = tmp(), tmp()
        local i = 0
        local bodies = capture(function()
          while not isOp("}") do
            i = i + 1
            pushScope()
            emit((i == 1 and "if " or "elseif ") .. chosen .. "==" .. i .. " then")
            if acceptKw("default") then
              hasDefault = true
              cases[i] = "{default=true}"
            else
              expectKw("case")
              -- case v := <-c:  case v, ok := <-c:  case <-c:  case c <- x:
              local names = {}
              local q = pos
              while toks[q].t == "name" and (toks[q + 1].v == "," or toks[q + 1].v == ":=") do
                names[#names + 1] = toks[q].v
                q = q + (toks[q + 1].v == "," and 2 or 1)
                if toks[q].v == ":=" then break end
              end
              if toks[q].v == ":=" and #names > 0 then
                pos = q + 1; tok = toks[pos]
                local c, ct = expr()
                local chanCode = c:match("^R%.recv%((.*)%)$")
                cases[i] = "{recv=" .. chanCode .. "}"
                if names[1] ~= "_" then emit("local " .. mangle(names[1]) .. "=" .. val); bind(names[1], ct and ct.el) end
                if names[2] and names[2] ~= "_" then emit("local " .. mangle(names[2]) .. "=" .. ok); bind(names[2], BOOL) end
              else
                local c, ct = expr()
                if isOp("<-") then
                  adv()
                  local x = expr()
                  cases[i] = "{send=" .. c .. ",v=" .. x .. "}"
                else
                  local chanCode = c:match("^R%.recv%((.*)%)$")
                  cases[i] = "{recv=" .. chanCode .. "}"
                end
              end
            end
            expectOp(":")
            while not (isKw("case") or isKw("default") or isOp("}")) do
              statement()
              if not isOp("}") then acceptOp(";") end
            end
            popScope()
          end
          if i > 0 then emit("end") end
        end)
        adv()
        loops[#loops] = nil
        emit("do local " .. chosen .. "," .. val .. "," .. ok .. "=R.select({" .. table.concat(cases, ",") .. "})")
        emit(bodies)
        emit("end")
        emit("::" .. rec.brk .. "::")
        return
      elseif v == "break" or v == "continue" then
        adv()
        local target
        if tok.t == "name" then
          local l = tok.v
          adv()
          for i = #loops, 1, -1 do if loops[i].label == l then target = loops[i]; break end end
        elseif v == "break" then target = loops[#loops]
        else for i = #loops, 1, -1 do if loops[i].isLoop then target = loops[i]; break end end end
        if not target then err(v .. " is not in a loop") end
        emit("goto " .. (v == "break" and target.brk or target.cont))
        return
      elseif v == "goto" then
        adv()
        emit("goto u_" .. name())
        return
      elseif v == "defer" then
        adv()
        local c, ct = expr()
        -- the arguments are evaluated now
        local fnc, args = splitCall(c)
        if not fnc then err("expression in defer must be function call") end
        emit("do local _a=table.pack(" .. args .. ") local _f=" .. fnc .. " _defers[#_defers+1]=function() return _f(table.unpack(_a,1,_a.n)) end end")
        return
      elseif v == "go" then
        adv()
        local c = expr()
        local fnc, args = splitCall(c)
        if not fnc then err("expression in go must be function call") end
        emit("do local _a=table.pack(" .. args .. ") local _f=" .. fnc .. " R.go(function() _f(table.unpack(_a,1,_a.n)) end) end")
        return
      elseif v == "func" then
        simpleStmt()
        return
      end
    end
    if isOp("{") then
      emit("do")
      block()
      emit("end")
      return
    end
    if isOp(";") then return end
    if t.t == "name" and peek().v == ":" and peek().t == "op" then
      local l = t.v
      adv(); adv()
      pendingLabel = l
      acceptOp(";")
      emit("::u_" .. l .. "::")
      if isOp("}") then return end
      return statement()
    end
    simpleStmt()
  end

  -- ---- the file ----
  -- first pass: types and signatures of everything at the top, so that order does not matter
  local function skipBraces()
    local d = 0
    repeat
      if isOp("{") then d = d + 1 elseif isOp("}") then d = d - 1 end
      if tok.t == "eof" then err("syntax error: unexpected EOF") end
      adv()
    until d == 0
  end
  local function skipTypeParams()
    if isOp("[") then
      local d = 0
      repeat
        if isOp("[") then d = d + 1
        elseif isOp("]") then d = d - 1
        elseif tok.t == "name" and d == 1 and (peek().t == "name" or peek().v == "," or peek().v == "interface" or peek().v == "~") then BASIC[tok.v] = BASIC[tok.v] or ANY end
        adv()
      until d == 0
    end
  end
  local startPos = pos
  -- package and imports
  if acceptKw("package") then name(); acceptOp(";") end
  while isKw("import") do
    adv()
    local function one()
      local alias
      if tok.t == "name" then alias = tok.v; adv() elseif isOp("_") or isOp(".") then adv() end
      local path = tok.v
      adv()
      local short = alias or path:match("([^/]+)$")
      imports[short] = path
    end
    if acceptOp("(") then
      while not isOp(")") do
        one()
        acceptOp(";")
      end
      adv()
    else one() end
    acceptOp(";")
  end
  local bodyStart = pos
  for pass = 1, 2 do
    pos = bodyStart; tok = toks[pos]
    while tok.t ~= "eof" do
      if isKw("type") then
        adv()
        local function one()
          local n = name()
          if isOp("[") and peek().t == "name" and toks[pos + 2].v ~= "]" then skipTypeParams() end
          acceptOp("=")
          local ok, t = pcall(parseType)
          if not ok then
            if pass == 2 then error(t, 0) end
            -- it refers to something later: the second pass gets it
            while not (isOp(";") or tok.t == "eof") do
              if isOp("{") then skipBraces() else adv() end
            end
          else types[n] = t end
        end
        if acceptOp("(") then
          while not isOp(")") do one(); acceptOp(";") end
          adv()
        else one() end
      elseif isKw("func") then
        adv()
        local recv, recvPtr
        if isOp("(") then
          adv()
          if tok.t == "name" and (peek().t == "name" or peek().v == "*") then adv() end
          recvPtr = acceptOp("*")
          recv = name()
          if isOp("[") then skipTypeParams() end
          expectOp(")")
        end
        local n = name()
        skipTypeParams()
        local ok, params = pcall(parseSignature)
        if not ok then
          if pass == 2 then error(params, 0) end
        else
          local results = parseResults()
          if recv then
            methods[recv] = methods[recv] or {}
            methods[recv][n] = { params = params, results = results, ptr = recvPtr }
          elseif n ~= "init" then funcs[n] = { params = params, results = results } end
        end
        while not (isOp("{") or isOp(";") or tok.t == "eof") do adv() end
        if isOp("{") then skipBraces() end
      elseif isKw("var") or isKw("const") then
        adv()
        if isOp("(") then
          local d = 0
          repeat
            if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
            adv()
          until d == 0
        else
          while not (isOp(";") or tok.t == "eof") do
            if isOp("{") then skipBraces() elseif isOp("(") then
              local d = 0
              repeat
                if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
                adv()
              until d == 0
            else adv() end
          end
        end
      else adv() end
    end
  end
  -- second pass: code. Types, then constants and variables, then functions
  for n, t in pairs(types) do
    emit("G." .. n .. "=R.newType(" .. str(n) .. ")")
  end
  for n, t in pairs(types) do
    local u = under(t)
    if u and u.k == "struct" then
      local parts = {}
      local names = {}
      for i, f in ipairs(u.order) do
        parts[i] = mangle(f.name) .. "=" .. zero(f.t)
        names[i] = str(mangle(f.name))
      end
      emit("G." .. n .. "_zero=function() return setmetatable({" .. table.concat(parts, ",") .. "},G." .. n .. ") end")
      emit("G." .. n .. ".__fields={" .. table.concat(names, ",") .. "}")
      emit("G." .. n .. ".__struct=true")
    end
  end
  -- embedded methods come through the parent
  for n, t in pairs(types) do
    local u = under(t)
    if u and u.k == "struct" then
      for _, e in ipairs(u.order) do
        if e.embedded then
          local en = e.t.k == "ptr" and e.t.to or e.t
          if en.k == "named" and methods[en.name] then
            for m in pairs(methods[en.name]) do
              if not (methods[n] and methods[n][m]) then
                emit("G." .. n .. "." .. mangle(m) .. "=function(s,...) return G." .. en.name .. "." .. mangle(m) .. "(s." .. mangle(e.name) .. ",...) end")
              end
            end
          end
        end
      end
    end
    if u and u.k == "iface" and u.methods then interfaces[n] = u.methods end
  end
  for n, list in pairs(interfaces) do
    local q = {}
    for i, m in ipairs(list) do q[i] = str(m) end
    emit("G." .. n .. ".__iface={" .. table.concat(q, ",") .. "}")
  end
  -- constants first, they may be used by anything
  pos = bodyStart; tok = toks[pos]
  while tok.t ~= "eof" do
    if isKw("const") then
      adv()
      constDecl(true)
    elseif isKw("type") then
      adv()
      if isOp("(") then
        local d = 0
        repeat
          if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
          adv()
        until d == 0
      else
        while not (isOp(";") or tok.t == "eof") do if isOp("{") then skipBraces() else adv() end end
      end
    elseif isKw("func") or isKw("var") then
      adv()
      while not (isOp(";") or tok.t == "eof") do
        if isOp("{") then skipBraces() elseif isOp("(") then
          local d = 0
          repeat
            if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
            adv()
          until d == 0
        else adv() end
      end
    else adv() end
  end
  -- the names of the variables, so that functions can use them
  pos = bodyStart; tok = toks[pos]
  local varPositions = {}
  while tok.t ~= "eof" do
    if isKw("var") then
      adv()
      varPositions[#varPositions + 1] = pos
      local function names_()
        local ns = {}
        repeat ns[#ns + 1] = name() until not acceptOp(",")
        local t
        if not isOp("=") then t = parseType() end
        for _, n in ipairs(ns) do scopes[1][n] = { t = t, code = "G." .. mangle(n) } end
        while not (isOp(";") or isOp(")") or tok.t == "eof") do
          if isOp("{") then skipBraces() elseif isOp("(") then
            local d = 0
            repeat
              if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
              adv()
            until d == 0
          else adv() end
        end
      end
      if acceptOp("(") then
        while not isOp(")") do names_(); acceptOp(";") end
        adv()
      else names_() end
    elseif isKw("func") or isKw("type") or isKw("const") then
      adv()
      if isOp("(") and not toks[pos - 1].v == "func" then end
      while not (isOp(";") or tok.t == "eof") do
        if isOp("{") then skipBraces() elseif isOp("(") then
          local d = 0
          repeat
            if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
            adv()
          until d == 0
        else adv() end
      end
    else adv() end
  end
  local inits = {}
  pos = bodyStart; tok = toks[pos]
  while tok.t ~= "eof" do
    if isKw("func") then
      adv()
      local recvName, recvType
      local params0 = nil
      if isOp("(") then
        adv()
        local rn
        if tok.t == "name" and (peek().t == "name" or peek().v == "*") then rn = tok.v; adv() end
        local isPtr = acceptOp("*")
        local tn = name()
        if isOp("[") then skipTypeParams() end
        expectOp(")")
        recvName = rn or "_recv"
        recvType = isPtr and { k = "ptr", to = { k = "named", name = tn } } or { k = "named", name = tn }
        params0 = tn
      end
      local n = name()
      skipTypeParams()
      local params = parseSignature()
      local results = parseResults()
      if recvName then table.insert(params, 1, { name = recvName, t = recvType }) end
      if isOp("{") then
        local text = functionBody(params, results)
        if params0 then emit("G." .. params0 .. "." .. mangle(n) .. "=" .. text)
        elseif n == "init" then inits[#inits + 1] = text
        else emit("G." .. mangle(n) .. "=" .. text) end
      end
    elseif isKw("var") then
      adv()
      local text = capture(function() varDecl(true) end)
      inits[#inits + 1] = { var = text }
    elseif isKw("const") or isKw("type") then
      adv()
      while not (isOp(";") or tok.t == "eof") do
        if isOp("{") then skipBraces() elseif isOp("(") then
          local d = 0
          repeat
            if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
            adv()
          until d == 0
        else adv() end
      end
    else adv() end
  end
  for _, x in ipairs(inits) do if type(x) == "table" then emit(x.var) end end
  for _, x in ipairs(inits) do if type(x) == "string" then emit("(" .. x .. ")()") end end
  if not funcs.main then syntaxError("function main is undeclared in the main package", 0) end
  emit("return G.main")
  return table.concat(out, "\n")
end
M.compile = compile

function M.main(args)
  local rt = driver.load("gort")
  local cmd = args[1]
  local function usage() term.write("usage: go run FILE.go [ARGS] | go build [-o PROGRAM] FILE.go | go version\n"); return 2 end
  if not cmd then return usage() end
  if cmd == "version" or cmd == "--version" then term.write("go version go1.22 esp/riscv32 (translated to Lua)\n"); return 0 end
  if cmd == "--selftest" then return rt.run(compile('package main\nimport "fmt"\nfunc main() { fmt.Println("go ok", 6*7) }\n'), {}) end
  local function report(path, e)
    if type(e) == "table" and e.syntax then term.write("# command-line-arguments\n" .. path .. ":" .. tostring(e.line) .. ": " .. e.syntax .. "\n")
    else term.write(tostring(e) .. "\n") end
    return 1
  end
  if cmd == "run" or cmd == "-run" then
    local path = args[2]
    if not path then return usage() end
    local src = fs.read(path)
    if not src then term.write("go: cannot find " .. path .. "\n"); return 1 end
    local ok, text = pcall(compile, src)
    if not ok then return report(path, text) end
    local a = { path }
    for i = 3, #args do a[#a + 1] = args[i] end
    return rt.run(text, a)
  elseif cmd == "build" then
    local outPath, path
    local i = 2
    while args[i] do
      if args[i] == "-o" then outPath = args[i + 1]; i = i + 1 else path = args[i] end
      i = i + 1
    end
    if not path then return usage() end
    local src = fs.read(path)
    if not src then term.write("go: cannot find " .. path .. "\n"); return 1 end
    local ok, text = pcall(compile, src)
    if not ok then return report(path, text) end
    outPath = outPath or path:gsub("%.go$", ""):match("([^/]+)$")
    fs.write(outPath, '#!lua\nlocal rt = driver.load("gort")\nlocal text = ' .. string.format("%q", text):gsub("\\\n", "\\n") .. "\nlocal a = {" .. string.format("%q", outPath) .. "}\nfor i, v in ipairs(arg) do a[i + 1] = v end\nrt.run(text, a)\n")
    if sys and sys.shell then pcall(sys.shell, "chmod +x " .. outPath) end
    return 0
  end
  return usage()
end
return M
