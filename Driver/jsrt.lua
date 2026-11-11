#!lua
-- jsrt: the run-time of the JavaScript programs that jslang translates.
local R = {}
local mtype, floor, unpack, concat, sfmt = math.type, math.floor, table.unpack, table.concat, string.format
local getmt, setmt, rawget_, rawset_, type_ = getmetatable, setmetatable, rawget, rawset, type
local null = setmt({}, { __tostring = function() return "null" end })
R.null = null
local function write(s) term.write(s) end

-- objects: the fields are in the table, the order of the keys beside it; the prototype is the __index of the metatable
local ORDER = setmt({}, { __mode = "k" })
local FP = setmt({}, { __mode = "k" })  -- the properties of functions
local Accessor = {}
local function protoMt(proto)
  local m = rawget_(proto, "__imt")
  if not m then
    m = { __index = proto, proto = proto }
    rawset_(proto, "__imt", m)
  end
  return m
end
local function hiddenKey(k) return k == "__imt" end
local ObjectProto, ArrayProto, FunctionProto, StringProto, NumberProto, BooleanProto, ErrorProto = {}, {}, {}, {}, {}, {}, {}
local ObjectMt = { __index = ObjectProto, proto = ObjectProto }
rawset_(ObjectProto, "__imt", ObjectMt)
local ArrayMt = { __index = ArrayProto, proto = ArrayProto, isArray = true }
rawset_(ArrayProto, "__imt", ArrayMt)

local function newObject() return setmt({}, ObjectMt) end
local function array(t, n)
  t.n = n or #t
  return setmt(t, ArrayMt)
end
R.array = function(t) return array(t) end
function R.arrn(n, ...)
  return setmt({ n = n, ... }, ArrayMt)
end
local function isArray(v) return type_(v) == "table" and getmt(v) == ArrayMt end

local tostr, inspect
local Thrown = {}
local function throwErr(ctorName, msg)
  local e = R.new(R.globals[ctorName], msg)
  error(setmt({ v = e }, Thrown), 0)
end
function R.throw(v) error(setmt({ v = v }, Thrown), 0) end
function R.catch(e)
  if getmt(e) == Thrown then return e.v end
  local s = tostring(e)
  if s:find("interrupted", 1, true) then error(e, 0) end
  if s:find("stack overflow", 1, true) then return R.new(R.globals.RangeError, "Maximum call stack size exceeded") end
  if s:find("not enough memory", 1, true) then return R.new(R.globals.RangeError, "Out of memory") end
  if s:find("is not defined", 1, true) then return R.new(R.globals.ReferenceError, (s:gsub("^.-:%d+: ", ""))) end
  return R.new(R.globals.TypeError, (s:gsub("^.-:%d+: ", "")))
end

local function protoOfValue(v)
  local t = type_(v)
  if t == "string" then return StringProto end
  if t == "number" then return NumberProto end
  if t == "boolean" then return BooleanProto end
  if t == "function" then return FunctionProto end
end
local function keyToNum(k)
  if mtype(k) then
    return k
  end
  if type_(k) == "string" and k:find("^%d+$") then return tonumber(k) end
end
local function isAscii(s) return not s:find("[\128-\255]") end
local function chars(s)
  local o, n = {}, 0
  for _, c in utf8.codes(s, true) do n = n + 1; o[n] = utf8.char(c) end
  return o
end
local function strLen(s) if isAscii(s) then return #s + 0.0 end return (utf8.len(s) or #s) + 0.0 end
local protoOf_
local function fnProp(f, k)
  local p = FP[f]
  if p then
    local v = p[k]
    if v ~= nil then return v end
    if p.__base then return fnProp(p.__base, k) end
  end
  return FunctionProto[k]
end
local function get(o, k)
  local t = type_(o)
  if t == "table" then
    if o == null then throwErr("TypeError", "Cannot read properties of null (reading '" .. tostr(k) .. "')") end
    local m = getmt(o)
    if m == ArrayMt then
      if mtype(k) then return o[k + 1] end
      if k == "length" then return o.n + 0.0 end
      local nk = keyToNum(k)
      if nk then return o[nk + 1] end
      return ArrayProto[k]
    end
    if mtype(k) then k = tostr(k) end
    local v = o[k]
    if type_(v) == "table" and getmt(v) == Accessor then
      if v.get then return v.get(o) end
      return nil
    end
    return v
  end
  if t == "string" then
    if k == "length" then return strLen(o) end
    local nk = keyToNum(k)
    if nk then
      if isAscii(o) then
        local c = o:sub(nk + 1, nk + 1)
        return c ~= "" and c or nil
      end
      return chars(o)[nk + 1]
    end
    return StringProto[k]
  end
  if t == "function" then
    if k == "name" then local p = FP[o]; return p and p.name or "" end
    if k == "length" then return 0.0 end
    if k == "prototype" then return protoOf_(o) end
    return fnProp(o, k)
  end
  if t == "nil" then throwErr("TypeError", "Cannot read properties of undefined (reading '" .. tostr(k) .. "')") end
  local p = protoOfValue(o)
  return p and p[k]
end
R.get = get
function R.len(o)
  if type_(o) == "table" and getmt(o) == ArrayMt then return o.n + 0.0 end
  return get(o, "length")
end
local function addOrder(o, k)
  local l = ORDER[o]
  if not l then l = {}; ORDER[o] = l end
  l[#l + 1] = k
end
local function set(o, k, v)
  local t = type_(o)
  if t == "table" then
    if o == null then throwErr("TypeError", "Cannot set properties of null (setting '" .. tostr(k) .. "')") end
    local m = getmt(o)
    if m == ArrayMt then
      local nk = keyToNum(k)
      if nk then
        local i = math.tointeger(nk) + 1
        o[i] = v
        if i > o.n then o.n = i end
        return v
      end
      if k == "length" then
        local n = math.tointeger(v)
        for i = n + 1, o.n do o[i] = nil end
        o.n = n
        return v
      end
      rawset_(o, k, v)
      return v
    end
    if mtype(k) then k = tostr(k) end
    local cur = rawget_(o, k)
    if cur == nil then
      local inherited = o[k]
      if type_(inherited) == "table" and getmt(inherited) == Accessor then
        if inherited.set then inherited.set(o, v) end
        return v
      end
      if not hiddenKey(k) then addOrder(o, k) end
    elseif type_(cur) == "table" and getmt(cur) == Accessor then
      if cur.set then cur.set(o, v) end
      return v
    end
    rawset_(o, k, v == nil and R.undefinedField or v)
    return v
  end
  if t == "function" then
    local p = FP[o]
    if not p then p = {}; FP[o] = p end
    p[k] = v
    return v
  end
  if t == "nil" then throwErr("TypeError", "Cannot set properties of undefined (setting '" .. tostr(k) .. "')") end
  return v
end
R.set = set
function R.delete(o, k)
  if isArray(o) then
    local nk = keyToNum(k)
    if nk then o[nk + 1] = nil end
    return true
  end
  if mtype(k) then k = tostr(k) end
  if rawget_(o, k) ~= nil then
    rawset_(o, k, nil)
    local l = ORDER[o]
    if l then for i = 1, #l do if l[i] == k then table.remove(l, i); break end end end
  end
  return true
end
function R.key(k) if type_(k) == "number" then return tostr(k) end return k end
function R.obj(parts)
  local o = newObject()
  for i = 1, #parts do
    local p = parts[i]
    if p.spread ~= nil then
      local s = p.spread
      if isArray(s) then for j = 1, s.n do set(o, tostr(j - 1), s[j]) end
      elseif type_(s) == "table" and s ~= null then
        local l = ORDER[s]
        if l then for j = 1, #l do set(o, l[j], get(s, l[j])) end end
      end
    elseif p.get or p.set then
      local a = rawget_(o, p.k)
      if not a then
        a = setmt({}, Accessor)
        addOrder(o, p.k)
        rawset_(o, p.k, a)
      end
      a.get = p.get or a.get
      a.set = p.set or a.set
    else
      if p.v ~= nil and type_(p.v) == "function" and FP[p.v] and FP[p.v].name == "" then FP[p.v].name = p.k end
      if rawget_(o, p.k) == nil then addOrder(o, p.k) end
      rawset_(o, p.k, p.v == nil and R.undefinedField or p.v)
    end
  end
  return o
end
-- a field whose value is undefined still has its key: this stands for it where it is kept
R.undefinedField = nil
function R.arrspread(parts)
  local o, n = {}, 0
  for i = 1, #parts do
    local p = parts[i]
    if p.spread ~= nil then
      for v in R.forof(p.spread) do n = n + 1; o[n] = v == R.UNDEF and nil or v end
    else n = n + 1; o[n] = p.v end
  end
  return array(o, n)
end
function R.spreadargs(parts)
  local o, n = {}, 0
  for i = 1, #parts do
    local p = parts[i]
    if p.spread ~= nil then
      for v in R.forof(p.spread) do n = n + 1; o[n] = v end
    else n = n + 1; o[n] = p.v end
  end
  return o
end
function R.toarr(v)
  if isArray(v) then return v end
  local o, n = {}, 0
  for x in R.forof(v) do n = n + 1; o[n] = x end
  return array(o, n)
end
function R.arrfrom(a, i)
  local o, n = {}, 0
  for j = i, a.n do n = n + 1; o[n] = a[j] end
  return array(o, n)
end
function R.objrest(s, used)
  local o = newObject()
  local skip = {}
  for _, k in ipairs(used) do skip[k] = true end
  local l = ORDER[s]
  if l then for _, k in ipairs(l) do if not skip[k] then set(o, k, get(s, k)) end end end
  return o
end
function R.def(v, f) if v == nil then return f() end return v end
function R.last(...) local n = select("#", ...); return (select(n, ...)) end
function R.void() return nil end

-- ---- functions and classes ----
function R.fn(f, name)
  FP[f] = FP[f] or {}
  FP[f].name = name
  return f
end
local function protoOf(f)
  local p = FP[f]
  if not p then p = {}; FP[f] = p end
  if not p.prototype then
    local pr = setmt({}, ObjectMt)
    rawset_(pr, "constructor", f)
    p.prototype = pr
  end
  return p.prototype
end
R.protoOf = protoOf
protoOf_ = protoOf
function R.call(f, this, ...)
  if type_(f) ~= "function" then
    throwErr("TypeError", tostr(f == nil and "undefined" or inspect(f)) .. " is not a function")
  end
  return f(this, ...)
end
function R.M(o, k, ...)
  local f = get(o, k)
  if type_(f) ~= "function" then
    throwErr("TypeError", "o." .. tostr(k) .. " is not a function")
  end
  return f(o, ...)
end
function R.new(c, ...)
  if type_(c) ~= "function" then throwErr("TypeError", tostr(c == nil and "undefined" or "value") .. " is not a constructor") end
  local info = FP[c]
  local o
  local native = info and info.native
  if native then return native(...) end
  local proto = protoOf(c)
  o = setmt({}, protoMt(proto))
  local r = c(o, ...)
  if type_(r) == "table" and r ~= null then return r end
  return o
end
local function initFields(cls, this)
  local p = FP[cls]
  if p and p.__fields then
    for _, f in ipairs(p.__fields) do set(this, f.k, f.v(this)) end
  end
end
function R.class(name, base, ctor, members, fields)
  local cls
  if base == null then base = nil end
  local hasBase = base ~= nil
  local userCtor = ctor
  cls = function(this, ...)
    if this == nil then throwErr("TypeError", "Class constructor " .. name .. " cannot be invoked without 'new'") end
    if not hasBase then initFields(cls, this) end
    if userCtor then
      local r = userCtor(this, ...)
      if type_(r) == "table" and r ~= null then return r end
    elseif hasBase then
      local r = base(this, ...)
      if type_(r) == "table" and r ~= null and r ~= this then this = r end
      initFields(cls, this)
      return this
    end
    return this
  end
  local p = { name = name, isClass = true, __base = base, __fields = fields }
  FP[cls] = p
  local proto
  if hasBase then
    proto = setmt({}, protoMt(protoOf(base)))
  else
    proto = setmt({}, ObjectMt)
  end
  rawset_(proto, "constructor", cls)
  p.prototype = proto
  for _, m in ipairs(members) do
    local target = m.static and p or proto
    if m.acc then
      local a = rawget_(target, m.k)
      if not a then
        a = setmt({}, Accessor)
        rawset_(target, m.k, a)
      end
      a[m.acc] = m.f
    elseif m.field then
      p[m.k] = m.v(cls)
    else
      rawset_(target, m.k, m.f)
    end
  end
  return cls
end
function R.superctor(cls, this, ...)
  local base = FP[cls].__base
  local r = base(this, ...)
  initFields(cls, this)
  return r
end
local function superProto(cls) return protoOf(FP[cls].__base) end
function R.supercall(cls, this, k, ...)
  local f
  if type_(this) == "function" then f = fnProp(FP[cls].__base, k)
  else f = superProto(cls)[k] end
  if type_(f) ~= "function" then throwErr("TypeError", "(intermediate value)." .. k .. " is not a function") end
  return f(this, ...)
end
function R.superget(cls, this, k)
  local v = superProto(cls)[k]
  if type_(v) == "table" and getmt(v) == Accessor then return v.get and v.get(this) end
  return v
end
function R.instanceof(v, c)
  if type_(c) ~= "function" then throwErr("TypeError", "Right-hand side of 'instanceof' is not callable") end
  local p = FP[c] and FP[c].prototype
  if type_(v) ~= "table" or v == null or not p then return false end
  local m = getmt(v)
  while m do
    if m.proto == p then return true end
    local up = m.proto and getmt(m.proto)
    m = up
  end
  return false
end
function R.in_(k, o)
  if isArray(o) then local n = keyToNum(k); return n ~= nil and o[n + 1] ~= nil end
  if mtype(k) then k = tostr(k) end
  return o[k] ~= nil
end

-- ---- values ----
local function T(v)
  if v == nil or v == false or v == null or v == "" or v == 0 or v ~= v then return false end
  return true
end
R.T = T
function R.and_(a, f) if T(a) then return f() end return a end
function R.or_(a, f) if T(a) then return a end return f() end
function R.nullish(a, f) if a == nil or a == null then return f() end return a end
function R.if_(c, a, b) if T(c) then return a() end return b() end
-- && and || whose right side is a plain name or a constant: no closure
R.fmod = math.fmod
function R.andv(a, b) if T(a) then return b end return a end
function R.orv(a, b) if T(a) then return a end return b end
local function numText(x)
  if x ~= x then return "NaN" end
  if x == math.huge then return "Infinity" elseif x == -math.huge then return "-Infinity" end
  if x == 0 then return "0" end
  if x == floor(x) and math.abs(x) < 1e21 then return sfmt("%.0f", x) end
  for p = 1, 17 do
    local s = sfmt("%." .. p .. "g", x)
    if tonumber(s) == x then
      local m, e = s:match("^(.-)e([+-]%d+)$")
      if m then
        local en = tonumber(e)
        if en >= 21 or en < -6 then return m .. "e" .. (en < 0 and "-" or "+") .. math.abs(en) end
        return (sfmt("%." .. math.max(0, p - 1 - en) .. "f", x))
      end
      return s
    end
  end
  return sfmt("%.17g", x)
end
tostr = function(v)
  local t = type_(v)
  if t == "string" then return v end
  if t == "number" then return numText(v) end
  if t == "boolean" then return v and "true" or "false" end
  if t == "nil" then return "undefined" end
  if v == null then return "null" end
  if t == "function" then
    local p = FP[v]
    if p and p.isClass then return "class " .. p.name .. " { }" end
    return "function " .. (p and p.name or "") .. "() { [native code] }"
  end
  if isArray(v) then
    local o = {}
    for i = 1, v.n do
      local x = v[i]
      o[i] = (x == nil or x == null) and "" or tostr(x)
    end
    return concat(o, ",")
  end
  local f = v.toString
  if type_(f) == "function" then return f(v) end
  return "[object Object]"
end
R.tostr = tostr
local function toNum(v)
  local t = type_(v)
  if t == "number" then return v + 0.0 end
  if t == "boolean" then return v and 1.0 or 0.0 end
  if t == "nil" then return 0 / 0 end
  if v == null then return 0.0 end
  if t == "string" then
    local s = v:match("^%s*(.-)%s*$")
    if s == "" then return 0.0 end
    if s == "Infinity" or s == "+Infinity" then return math.huge end
    if s == "-Infinity" then return -math.huge end
    if s:find("^[+-]?%d*%.?%d*[eE]?[+-]?%d*$") or s:find("^0[xX]%x+$") then
      local n = tonumber(s)
      if n then return n + 0.0 end
    end
    if s:find("^0[bB][01]+$") then return tonumber(s:sub(3), 2) + 0.0 end
    return 0 / 0
  end
  if t == "table" then
    if isArray(v) then return toNum(tostr(v)) end
    local f = v.valueOf
    if type_(f) == "function" then
      local x = f(v)
      if type_(x) ~= "table" then return toNum(x) end
    end
    return toNum(tostr(v))
  end
  return 0 / 0
end
R.num = toNum
local function prim(v)
  if type_(v) == "table" and v ~= null then
    if isArray(v) then return tostr(v) end
    local f = v.valueOf
    if type_(f) == "function" then
      local x = f(v)
      if type_(x) ~= "table" then return x end
    end
    return tostr(v)
  end
  return v
end
function R.add(a, b)
  if mtype(a) and mtype(b) then return a + b end
  local ta, tb = type_(a), type_(b)
  if ta == "string" and tb == "string" then return a .. b end
  a, b = prim(a), prim(b)
  if type_(a) == "string" or type_(b) == "string" then return tostr(a) .. tostr(b) end
  return toNum(a) + toNum(b)
end
function R.sub(a, b) if mtype(a) and mtype(b) then return a - b end return toNum(a) - toNum(b) end
function R.mul(a, b) if mtype(a) and mtype(b) then return a * b end return toNum(a) * toNum(b) end
function R.div(a, b) if mtype(a) and mtype(b) then return a / b end return toNum(a) / toNum(b) end
function R.mod(a, b)
  a, b = toNum(a), toNum(b)
  if b == 0 or a ~= a or b ~= b or a == math.huge or a == -math.huge then return 0 / 0 end
  if b == math.huge or b == -math.huge then return a end
  return math.fmod(a, b)
end
function R.pow(a, b) return toNum(a) ^ toNum(b) end
function R.neg(a) return -toNum(a) end
local function int32(v)
  v = toNum(v)
  if v ~= v or v == math.huge or v == -math.huge then return 0 end
  local i = math.tointeger(v >= 0 and floor(v) or -floor(-v)) or 0
  i = i & 0xffffffff
  if i >= 0x80000000 then i = i - 0x100000000 end
  return i
end
local function back(i)
  i = i & 0xffffffff
  if i >= 0x80000000 then i = i - 0x100000000 end
  return i + 0.0
end
function R.band(a, b) return back(int32(a) & int32(b)) end
function R.bor(a, b) return back(int32(a) | int32(b)) end
function R.bxor(a, b) return back(int32(a) ~ int32(b)) end
function R.bnot(a) return back(~int32(a)) end
function R.shl(a, b) return back(int32(a) << (int32(b) & 31)) end
function R.shr(a, b) return (int32(a) >> 0 >= 0 and (int32(a) >> (int32(b) & 31)) or ~((~int32(a)) >> (int32(b) & 31))) + 0.0 end
function R.ushr(a, b) return ((int32(a) & 0xffffffff) >> (int32(b) & 31)) + 0.0 end
function R.lt(a, b)
  if mtype(a) and mtype(b) then return a < b end
  a, b = prim(a), prim(b)
  if type_(a) == "string" and type_(b) == "string" then return a < b end
  return toNum(a) < toNum(b)
end
function R.gt(a, b) return R.lt(b, a) end
function R.le(a, b)
  if mtype(a) and mtype(b) then return a <= b end
  a, b = prim(a), prim(b)
  if type_(a) == "string" and type_(b) == "string" then return a <= b end
  return toNum(a) <= toNum(b)
end
function R.ge(a, b) return R.le(b, a) end
function R.eq(a, b)
  if a == b then return true end
  if (a == nil or a == null) and (b == nil or b == null) then return true end
  if a == nil or b == nil or a == null or b == null then return false end
  local ta, tb = type_(a), type_(b)
  if ta == tb and ta ~= "table" then return false end
  if ta == "table" and tb == "table" then return false end
  return toNum(prim(a)) == toNum(prim(b)) or (type_(prim(a)) == "string" and prim(a) == prim(b))
end
function R.ne(a, b) return not R.eq(a, b) end
function R.typeof(v)
  local t = type_(v)
  if t == "nil" then return "undefined" end
  if t == "table" then return "object" end
  return t
end
function rawget_env(env, n, f)
  if rawget_(env, n) ~= nil or R.globals[n] ~= nil then return f() end
  local ok, v = pcall(f)
  if ok then return v end
  return nil
end

-- ---- iteration ----
local GenProto = {}
local GenMt = { __index = GenProto, proto = GenProto }
function R.forof(x)
  local t = type_(x)
  if isArray(x) then
    local i, a = 0, x
    return function()
      i = i + 1
      if i > a.n then return nil end
      local v = a[i]
      if v == nil then return R.UNDEF end
      return v
    end
  elseif t == "string" then
    local c = isAscii(x) and nil or chars(x)
    local i = 0
    if c then return function() i = i + 1; return c[i] end end
    return function()
      i = i + 1
      if i <= #x then return x:sub(i, i) end
    end
  elseif t == "table" and x ~= null then
    if getmt(x) == GenMt then
      return function()
        local r = GenProto.next(x)
        if r.done then return nil end
        local v = r.value
        if v == nil then return R.UNDEF end
        return v
      end
    end
    local f = x[R.iteratorKey]
    if type_(f) == "function" then
      local it = f(x)
      if isArray(it) or getmt(it) == GenMt then return R.forof(it) end
      local nx = get(it, "next")
      return function()
        local r = nx(it)
        if T(get(r, "done")) then return nil end
        local v = get(r, "value")
        if v == nil then return R.UNDEF end
        return v
      end
    end
  end
  throwErr("TypeError", (x == nil and "undefined" or inspect(x)) .. " is not iterable")
end
R.iteratorKey = "@@iterator"
function R.forin(x)
  local keys = {}
  if isArray(x) then for i = 1, x.n do keys[i] = tostr(i - 1) end
  elseif type_(x) == "string" then for i = 1, #x do keys[i] = tostr(i - 1) end
  elseif type_(x) == "table" and x ~= null then
    local l = ORDER[x]
    if l then for i, k in ipairs(l) do keys[i] = k end end
  end
  local i = 0
  return function()
    i = i + 1
    return keys[i]
  end
end
function R.gen(body)
  return setmt({ co = coroutine.create(body), done = false }, GenMt)
end
function GenProto.next(g, v)
  local r = newObject()
  if not g.co or coroutine.status(g.co) == "dead" then
    set(r, "value", nil); set(r, "done", true)
    return r
  end
  local ok, x = coroutine.resume(g.co, v)
  if not ok then g.co = nil; error(x, 0) end
  local d = coroutine.status(g.co) == "dead"
  set(r, "value", x)
  set(r, "done", d)
  return r
end
GenProto[R.iteratorKey] = function(g) return g end
GenProto["return"] = function(g, v) g.co = nil; local r = newObject(); set(r, "value", v); set(r, "done", true); return r end
function R.yield(v) return coroutine.yield(v) end
function R.yieldstar(it) for v in R.forof(it) do if v == R.UNDEF then v = nil end coroutine.yield(v) end end

-- ---- inspect: what console.log prints ----
local function keyText(k)
  if k:find("^[%a_$][%w_$]*$") then return k end
  return "'" .. k .. "'"
end
local function strQuote(s)
  local q = "'"
  if s:find("'", 1, true) then
    if not s:find('"', 1, true) then q = '"' elseif not s:find("`", 1, true) then q = "`" end
  end
  s = s:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t")
  if q == "'" then s = s:gsub("'", "\\'") end
  return q .. s .. q
end
local MapMt, SetMt = {}, {}
local function isError(v)
  return type_(v) == "table" and v ~= null and R.instanceof(v, R.globals.Error)
end
inspect = function(v, depth, seen)
  depth = depth or 0
  local t = type_(v)
  if t == "string" then return depth == 0 and v or strQuote(v) end
  if t == "number" then
    if v == 0 and 1 / v < 0 then return "-0" end
    return numText(v)
  end
  if t == "boolean" then return v and "true" or "false" end
  if t == "nil" then return "undefined" end
  if v == null then return "null" end
  if t == "function" then
    local p = FP[v]
    if p and p.isClass then
      local b = p.__base and FP[p.__base]
      return "[class " .. (p.name ~= "" and p.name or "(anonymous)") .. (b and (" extends " .. b.name) or "") .. "]"
    end
    local n = p and p.name or ""
    return n ~= "" and ("[Function: " .. n .. "]") or "[Function (anonymous)]"
  end
  seen = seen or {}
  if seen[v] then return "[Circular *1]" end
  if isError(v) then
    local s = tostr(get(v, "stack") or tostr(v))
    return depth == 0 and s or ("[" .. s .. "]")
  end
  local m = getmt(v)
  if m == R.RegExpMt then return "/" .. v.source .. "/" .. v.flags end
  if m == R.DateMt then return v.toISOString(v) end
  seen[v] = true
  local parts = {}
  local open, close, prefix = "{", "}", ""
  if m == ArrayMt then
    open, close = "[", "]"
    if depth > 2 then seen[v] = nil; return "[Array]" end
    local i = 1
    while i <= v.n and i <= 100 do
      if v[i] == nil then
        local j = i
        while j < v.n and v[j + 1] == nil do j = j + 1 end
        parts[#parts + 1] = "<" .. (j - i + 1) .. " empty item" .. (j > i and "s" or "") .. ">"
        i = j + 1
      else
        parts[#parts + 1] = inspect(v[i], depth + 1, seen)
        i = i + 1
      end
    end
    if v.n > 100 then parts[#parts + 1] = "... " .. (v.n - 100) .. " more items" end
    if rawget_(v, "index") ~= nil then
      parts[#parts + 1] = "index: " .. inspect(rawget_(v, "index"), depth + 1, seen)
      parts[#parts + 1] = "input: " .. inspect(rawget_(v, "input"), depth + 1, seen)
      parts[#parts + 1] = "groups: " .. inspect(rawget_(v, "groups"), depth + 1, seen)
    end
  elseif m == MapMt then
    prefix = "Map(" .. v.size_ .. ") "
    if depth > 2 then seen[v] = nil; return "[Map]" end
    for i = 1, v.top do
      local k = v.ks[i]
      if k ~= nil then parts[#parts + 1] = inspect(k == R.UNDEF and nil or k, depth + 1, seen) .. " => " .. inspect(v.vs[i], depth + 1, seen) end
    end
  elseif m == SetMt then
    prefix = "Set(" .. v.size_ .. ") "
    if depth > 2 then seen[v] = nil; return "[Set]" end
    for i = 1, v.top do
      local k = v.ks[i]
      if k ~= nil then parts[#parts + 1] = inspect(k == R.UNDEF and nil or k, depth + 1, seen) end
    end
  else
    local ctor = v.constructor
    local cname = type_(ctor) == "function" and FP[ctor] and FP[ctor].name
    if cname and cname ~= "Object" and cname ~= "" then prefix = cname .. " " end
    if depth > 2 then seen[v] = nil; return "[" .. (cname or "Object") .. "]" end
    local l = ORDER[v]
    if l then
      for _, k in ipairs(l) do
        if k:sub(1, 1) ~= "#" then
          local x = rawget_(v, k)
          if type_(x) == "table" and getmt(x) == Accessor then
            parts[#parts + 1] = keyText(k) .. ": " .. ((x.get and x.set) and "[Getter/Setter]" or (x.get and "[Getter]" or "[Setter]"))
          else
            parts[#parts + 1] = keyText(k) .. ": " .. inspect(x, depth + 1, seen)
          end
        end
      end
    end
  end
  seen[v] = nil
  if #parts == 0 then return prefix .. open .. close end
  local total = #prefix + #parts
  local multi = false
  for _, p in ipairs(parts) do
    total = total + #p
    if p:find("\n", 1, true) then multi = true end
  end
  if multi or total + depth * 2 > 72 then
    local pad = ("  "):rep(depth + 1)
    return prefix .. open .. "\n" .. pad .. concat(parts, ",\n" .. pad) .. "\n" .. ("  "):rep(depth) .. close
  end
  return prefix .. open .. " " .. concat(parts, ", ") .. " " .. close
end
R.inspect = inspect
local function formatArgs(...)
  local n = select("#", ...)
  local a = { ... }
  local start = 1
  local out = {}
  if type_(a[1]) == "string" and a[1]:find("%", 1, true) and n > 1 then
    local i = 2
    out[1] = a[1]:gsub("%%([sdifoOj%%])", function(c)
      if c == "%" then return "%" end
      if i > n then return "%" .. c end
      local v = a[i]
      i = i + 1
      if c == "s" then return type_(v) == "string" and v or inspect(v, 1) end
      if c == "d" or c == "i" then
        local x = toNum(v)
        if c == "i" then x = x >= 0 and floor(x) or -floor(-x) end
        return numText(x)
      end
      if c == "f" then return numText(toNum(v)) end
      return inspect(v, 1)
    end)
    start = i
  elseif n >= 1 then
    out[1] = inspect(a[1])
    start = 2
  end
  for i = start, n do out[#out + 1] = inspect(a[i]) end
  return concat(out, " ")
end

-- ---- globals ----
local G = {}
R.globals = G
local function native(name, f) FP[f] = FP[f] or {}; FP[f].name = name; return f end
local function method(tbl, name, f) rawset_(tbl, name, native(name, f)) end
local function toIndex(v, default)
  if v == nil then return default end
  v = toNum(v)
  if v ~= v then return 0 end
  return v >= 0 and floor(v) or -floor(-v)
end

-- Error family
local function errorClass(name, baseCtor)
  local c
  c = function(this, msg, opts)
    if this == nil or type_(this) ~= "table" or this == G.Math then return R.new(c, msg) end
    if msg ~= nil then
      rawset_(this, "message", tostr(msg))
    else rawset_(this, "message", "") end
    local ctor = this.constructor
    rawset_(this, "stack", (FP[ctor] and FP[ctor].name or name) .. (msg ~= nil and (": " .. tostr(msg)) or "") .. "\n    at <anonymous>")
    return this
  end
  FP[c] = { name = name, __base = baseCtor }
  local proto
  if baseCtor then proto = setmt({}, protoMt(protoOf(baseCtor))) else proto = setmt({}, ObjectMt) end
  rawset_(proto, "constructor", c)
  rawset_(proto, "name", name)
  FP[c].prototype = proto
  G[name] = c
  return c
end
local Err = errorClass("Error")
rawset_(protoOf(Err), "toString", native("toString", function(this)
  local n, m = get(this, "name"), get(this, "message")
  if m == nil or m == "" then return tostr(n) end
  return tostr(n) .. ": " .. tostr(m)
end))
for _, n in ipairs{ "TypeError", "RangeError", "ReferenceError", "SyntaxError", "EvalError", "URIError" } do errorClass(n, Err) end

-- Object
method(ObjectProto, "hasOwnProperty", function(o, k)
  if isArray(o) then local n = keyToNum(k); if n then return o[n + 1] ~= nil end return k == "length" end
  return rawget_(o, tostr(k)) ~= nil
end)
method(ObjectProto, "toString", function() return "[object Object]" end)
method(ObjectProto, "valueOf", function(o) return o end)
method(ObjectProto, "toLocaleString", function(o) return tostr(o) end)
local function ownKeys(o)
  local keys = {}
  if isArray(o) then for i = 1, o.n do if o[i] ~= nil then keys[#keys + 1] = tostr(i - 1) end end
  elseif type_(o) == "string" then for i = 1, #o do keys[i] = tostr(i - 1) end
  elseif type_(o) == "table" and o ~= null then
    local l = ORDER[o]
    if l then
      local nums, strs = {}, {}
      for _, k in ipairs(l) do if k:find("^%d+$") then nums[#nums + 1] = k elseif k:sub(1, 1) ~= "#" then strs[#strs + 1] = k end end
      table.sort(nums, function(a, b) return tonumber(a) < tonumber(b) end)
      for _, k in ipairs(nums) do keys[#keys + 1] = k end
      for _, k in ipairs(strs) do keys[#keys + 1] = k end
    end
  end
  return keys
end
local ObjectCtor = native("Object", function(_, v)
  if v == nil or v == null then return newObject() end
  return v
end)
G.Object = ObjectCtor
FP[ObjectCtor].prototype = ObjectProto
rawset_(ObjectProto, "constructor", ObjectCtor)
local function st(c, name, f) FP[c] = FP[c] or {}; FP[c][name] = native(name, f) end
st(ObjectCtor, "keys", function(_, o) local k = ownKeys(o); return array(k, #k) end)
st(ObjectCtor, "values", function(_, o) local r = {}; local k = ownKeys(o); for i, x in ipairs(k) do r[i] = get(o, x) end return array(r, #k) end)
st(ObjectCtor, "entries", function(_, o) local r = {}; local k = ownKeys(o); for i, x in ipairs(k) do r[i] = R.arrn(2, x, get(o, x)) end return array(r, #k) end)
st(ObjectCtor, "assign", function(_, t, ...)
  for _, s in ipairs{ ... } do
    for _, k in ipairs(ownKeys(s)) do set(t, k, get(s, k)) end
  end
  return t
end)
st(ObjectCtor, "freeze", function(_, o) return o end)
st(ObjectCtor, "isFrozen", function() return false end)
st(ObjectCtor, "seal", function(_, o) return o end)
st(ObjectCtor, "create", function(_, p)
  if p == null then return setmt({}, { proto = false }) end
  return setmt({}, protoMt(p))
end)
st(ObjectCtor, "getPrototypeOf", function(_, o)
  if type_(o) == "function" then return FunctionProto end
  local m = getmt(o)
  return m and m.proto or null
end)
st(ObjectCtor, "setPrototypeOf", function(_, o, p) setmt(o, protoMt(p)); return o end)
st(ObjectCtor, "fromEntries", function(_, it)
  local o = newObject()
  for e in R.forof(it) do set(o, tostr(get(e, 0.0)), get(e, 1.0)) end
  return o
end)
st(ObjectCtor, "getOwnPropertyNames", function(_, o) local k = ownKeys(o); return array(k, #k) end)
st(ObjectCtor, "defineProperty", function(_, o, k, d)
  local v = get(d, "value")
  local g, s = get(d, "get"), get(d, "set")
  if g or s then
    local a = setmt({ get = g, set = s }, Accessor)
    rawset_(o, k, a)
  else set(o, k, v) end
  return o
end)

-- Function
method(FunctionProto, "call", function(f, this, ...) return f(this, ...) end)
method(FunctionProto, "apply", function(f, this, a)
  if a == nil or a == null then return f(this) end
  return f(this, unpack(a, 1, a.n))
end)
method(FunctionProto, "bind", function(f, this, ...)
  local b = { ... }
  local nb = select("#", ...)
  return R.fn(function(_, ...)
    local args = { unpack(b, 1, nb) }
    local n = select("#", ...)
    for i = 1, n do args[nb + i] = (select(i, ...)) end
    return f(this, unpack(args, 1, nb + n))
  end, "bound " .. (FP[f] and FP[f].name or ""))
end)
method(FunctionProto, "toString", function(f) return tostr(f) end)
G.Function = native("Function", function() throwErr("TypeError", "Function constructor is not supported") end)
FP[G.Function].prototype = FunctionProto

-- Array
local function toArrIdx(a, v, default)
  local i = toIndex(v, default)
  if i < 0 then i = math.max(a.n + i, 0) end
  if i > a.n then i = a.n end
  return math.tointeger(i)
end
local A = ArrayProto
method(A, "push", function(a, ...)
  local c = select("#", ...)
  for i = 1, c do a[a.n + i] = (select(i, ...)) end
  a.n = a.n + c
  return a.n + 0.0
end)
method(A, "pop", function(a)
  if a.n == 0 then return nil end
  local v = a[a.n]
  a[a.n] = nil
  a.n = a.n - 1
  return v
end)
method(A, "shift", function(a)
  if a.n == 0 then return nil end
  local v = a[1]
  table.move(a, 2, a.n, 1)
  a[a.n] = nil
  a.n = a.n - 1
  return v
end)
method(A, "unshift", function(a, ...)
  local c = select("#", ...)
  table.move(a, 1, a.n, c + 1)
  for i = 1, c do a[i] = (select(i, ...)) end
  a.n = a.n + c
  return a.n + 0.0
end)
method(A, "slice", function(a, s, e)
  local i, j = toArrIdx(a, s, 0), toArrIdx(a, e, a.n)
  local o, n = {}, 0
  for k = i + 1, j do n = n + 1; o[n] = a[k] end
  return array(o, n)
end)
method(A, "splice", function(a, s, c, ...)
  local i = toArrIdx(a, s, 0)
  local cnt = c == nil and a.n - i or math.max(0, math.min(math.tointeger(toIndex(c, 0)), a.n - i))
  local removed = {}
  for k = 1, cnt do removed[k] = a[i + k] end
  local add = select("#", ...)
  local tail = a.n - i - cnt
  table.move(a, i + cnt + 1, a.n, i + add + 1)
  for k = 1, add do a[i + k] = (select(k, ...)) end
  local newN = i + add + tail
  for k = newN + 1, a.n do a[k] = nil end
  a.n = newN
  return array(removed, cnt)
end)
method(A, "concat", function(a, ...)
  local o, n = {}, a.n
  for i = 1, n do o[i] = a[i] end
  for i = 1, select("#", ...) do
    local x = select(i, ...)
    if isArray(x) then for j = 1, x.n do o[n + j] = x[j] end n = n + x.n
    else n = n + 1; o[n] = x end
  end
  return array(o, n)
end)
method(A, "join", function(a, sep)
  sep = sep == nil and "," or tostr(sep)
  local o = {}
  for i = 1, a.n do
    local x = a[i]
    o[i] = (x == nil or x == null) and "" or tostr(x)
  end
  return concat(o, sep)
end)
method(A, "reverse", function(a)
  local i, j = 1, a.n
  while i < j do a[i], a[j] = a[j], a[i]; i = i + 1; j = j - 1 end
  return a
end)
method(A, "indexOf", function(a, x, s)
  for i = toArrIdx(a, s, 0) + 1, a.n do if a[i] == x then return i - 1.0 end end
  return -1.0
end)
method(A, "lastIndexOf", function(a, x)
  for i = a.n, 1, -1 do if a[i] == x then return i - 1.0 end end
  return -1.0
end)
method(A, "includes", function(a, x)
  for i = 1, a.n do if a[i] == x or (x ~= x and a[i] ~= a[i]) then return true end end
  return false
end)
method(A, "forEach", function(a, f, this) for i = 1, a.n do if a[i] ~= nil then f(this, a[i], i - 1.0, a) end end end)
method(A, "map", function(a, f, this)
  local o = {}
  for i = 1, a.n do if a[i] ~= nil then o[i] = f(this, a[i], i - 1.0, a) end end
  return array(o, a.n)
end)
method(A, "filter", function(a, f, this)
  local o, n = {}, 0
  for i = 1, a.n do if a[i] ~= nil and T(f(this, a[i], i - 1.0, a)) then n = n + 1; o[n] = a[i] end end
  return array(o, n)
end)
method(A, "find", function(a, f) for i = 1, a.n do if T(f(nil, a[i], i - 1.0, a)) then return a[i] end end end)
method(A, "findIndex", function(a, f) for i = 1, a.n do if T(f(nil, a[i], i - 1.0, a)) then return i - 1.0 end end return -1.0 end)
method(A, "findLast", function(a, f) for i = a.n, 1, -1 do if T(f(nil, a[i], i - 1.0, a)) then return a[i] end end end)
method(A, "some", function(a, f) for i = 1, a.n do if a[i] ~= nil and T(f(nil, a[i], i - 1.0, a)) then return true end end return false end)
method(A, "every", function(a, f) for i = 1, a.n do if a[i] ~= nil and not T(f(nil, a[i], i - 1.0, a)) then return false end end return true end)
method(A, "reduce", function(a, f, ...)
  local acc, i = nil, 1
  if select("#", ...) > 0 then acc = (...)
  else
    if a.n == 0 then throwErr("TypeError", "Reduce of empty array with no initial value") end
    acc = a[1]; i = 2
  end
  for k = i, a.n do acc = f(nil, acc, a[k], k - 1.0, a) end
  return acc
end)
method(A, "reduceRight", function(a, f, ...)
  local acc, i = nil, a.n
  if select("#", ...) > 0 then acc = (...)
  else acc = a[a.n]; i = a.n - 1 end
  for k = i, 1, -1 do acc = f(nil, acc, a[k], k - 1.0, a) end
  return acc
end)
local function mergeSort(a, n, less)
  if n < 2 then return a end
  local b = {}
  local w = 1
  while w < n do
    local i = 1
    while i <= n do
      local mid, hi = math.min(i + w, n + 1), math.min(i + 2 * w, n + 1)
      local l, r, k = i, mid, i
      while l < mid and r < hi do
        if less(a[r], a[l]) then b[k] = a[r]; r = r + 1 else b[k] = a[l]; l = l + 1 end
        k = k + 1
      end
      while l < mid do b[k] = a[l]; l = l + 1; k = k + 1 end
      while r < hi do b[k] = a[r]; r = r + 1; k = k + 1 end
      i = i + 2 * w
    end
    a, b = b, a
    w = w * 2
  end
  return a
end
method(A, "sort", function(a, f)
  local less
  if f then less = function(x, y) return toNum(f(nil, x, y)) < 0 end
  else less = function(x, y) return tostr(x) < tostr(y) end end
  local items = {}
  for i = 1, a.n do items[i] = a[i] end
  local s = mergeSort(items, a.n, less)
  for i = 1, a.n do a[i] = s[i] end
  return a
end)
method(A, "flat", function(a, d)
  d = d == nil and 1 or d
  local o, n = {}, 0
  local function go(x, depth)
    for i = 1, x.n do
      if isArray(x[i]) and depth > 0 then go(x[i], depth - 1)
      else n = n + 1; o[n] = x[i] end
    end
  end
  go(a, d)
  return array(o, n)
end)
method(A, "flatMap", function(a, f)
  local o, n = {}, 0
  for i = 1, a.n do
    local r = f(nil, a[i], i - 1.0, a)
    if isArray(r) then for j = 1, r.n do n = n + 1; o[n] = r[j] end
    else n = n + 1; o[n] = r end
  end
  return array(o, n)
end)
method(A, "fill", function(a, v, s, e)
  for i = toArrIdx(a, s, 0) + 1, toArrIdx(a, e, a.n) do a[i] = v end
  return a
end)
method(A, "at", function(a, i) i = toIndex(i, 0); if i < 0 then i = a.n + i end return a[math.tointeger(i) + 1] end)
method(A, "toString", function(a) return tostr(a) end)
method(A, "keys", function(a) local o = {}; for i = 1, a.n do o[i] = i - 1.0 end return array(o, a.n) end)
method(A, "values", function(a) return a end)
method(A, "entries", function(a) local o = {}; for i = 1, a.n do o[i] = R.arrn(2, i - 1.0, a[i]) end return array(o, a.n) end)
local ArrayCtor = native("Array", function(_, ...)
  local n = select("#", ...)
  if n == 1 and mtype((...)) then
    local c = (...)
    if c < 0 or c ~= floor(c) then throwErr("RangeError", "Invalid array length") end
    return array({}, math.tointeger(c))
  end
  return array({ ... }, n)
end)
G.Array = ArrayCtor
FP[ArrayCtor].prototype = ArrayProto
FP[ArrayCtor].native = function(...) return ArrayCtor(nil, ...) end
rawset_(ArrayProto, "constructor", ArrayCtor)
st(ArrayCtor, "isArray", function(_, v) return isArray(v) end)
st(ArrayCtor, "of", function(_, ...) return array({ ... }, select("#", ...)) end)
st(ArrayCtor, "from", function(_, src, f)
  local o, n = {}, 0
  if type_(src) == "table" and src ~= null and not isArray(src) and getmt(src) ~= GenMt and getmt(src) ~= MapMt and getmt(src) ~= SetMt and src[R.iteratorKey] == nil then
    local c = math.tointeger(toIndex(get(src, "length"), 0))
    for i = 1, c do o[i] = get(src, i - 1.0) end
    n = c
  else
    for v in R.forof(src) do
      n = n + 1
      if v ~= R.UNDEF then o[n] = v end
    end
  end
  if f then for i = 1, n do o[i] = f(nil, o[i], i - 1.0) end end
  return array(o, n)
end)

-- String
local S = StringProto
local function sv(s) return s end
local function rangeAscii(s, a, b)
  if isAscii(s) then return s:sub(a + 1, b) end
  local c = chars(s)
  return concat(c, "", a + 1, math.min(b, #c))
end
method(S, "charAt", function(s, i) return get(s, toIndex(i, 0)) or "" end)
method(S, "charCodeAt", function(s, i)
  local c = get(s, toIndex(i, 0))
  if not c then return 0 / 0 end
  return utf8.codepoint(c) + 0.0
end)
S.codePointAt = S.charCodeAt
method(S, "at", function(s, i) i = toIndex(i, 0); if i < 0 then i = strLen(s) + i end return get(s, i) end)
method(S, "toUpperCase", function(s) return s:upper() end)
method(S, "toLowerCase", function(s) return s:lower() end)
S.toLocaleUpperCase, S.toLocaleLowerCase = S.toUpperCase, S.toLowerCase
method(S, "trim", function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end)
method(S, "trimStart", function(s) return (s:gsub("^%s+", "")) end)
method(S, "trimEnd", function(s) return (s:gsub("%s+$", "")) end)
method(S, "toString", function(s) return s end)
method(S, "valueOf", function(s) return s end)
method(S, "concat", function(s, ...) local o = { s }; for _, x in ipairs{ ... } do o[#o + 1] = tostr(x) end return concat(o) end)
method(S, "includes", function(s, p) return s:find(tostr(p), 1, true) ~= nil end)
method(S, "startsWith", function(s, p, a) a = toIndex(a, 0); p = tostr(p); return s:sub(a + 1, a + #p) == p end)
method(S, "endsWith", function(s, p) p = tostr(p); return p == "" or s:sub(-#p) == p end)
method(S, "indexOf", function(s, p, a)
  local i = s:find(tostr(p), math.tointeger(toIndex(a, 0)) + 1, true)
  return i and i - 1.0 or -1.0
end)
method(S, "lastIndexOf", function(s, p)
  local last, i = -1.0, 1
  p = tostr(p)
  while true do
    local a = s:find(p, i, true)
    if not a then return last end
    last = a - 1.0
    i = a + 1
  end
end)
local function clampIdx(s, v, default)
  local n = strLen(s)
  local i = toIndex(v, default)
  if i < 0 then i = 0 end
  if i > n then i = n end
  return math.tointeger(i)
end
method(S, "substring", function(s, a, b)
  a, b = clampIdx(s, a, 0), clampIdx(s, b, strLen(s))
  if a > b then a, b = b, a end
  return rangeAscii(s, a, b)
end)
method(S, "slice", function(s, a, b)
  local n = strLen(s)
  a, b = toIndex(a, 0), toIndex(b, n)
  if a < 0 then a = math.max(n + a, 0) end
  if b < 0 then b = math.max(n + b, 0) end
  if a > n then a = n end
  if b > n then b = n end
  if a >= b then return "" end
  return rangeAscii(s, math.tointeger(a), math.tointeger(b))
end)
method(S, "substr", function(s, a, c)
  local n = strLen(s)
  a = toIndex(a, 0)
  if a < 0 then a = math.max(n + a, 0) end
  local e = c == nil and n or math.min(n, a + toIndex(c, 0))
  return rangeAscii(s, math.tointeger(a), math.tointeger(e))
end)
method(S, "repeat", function(s, c)
  c = toIndex(c, 0)
  if c < 0 then throwErr("RangeError", "Invalid count value: " .. numText(c)) end
  return s:rep(math.tointeger(c))
end)
local function pad(s, w, f)
  f = f == nil and " " or tostr(f)
  local need = math.tointeger(toIndex(w, 0)) - math.tointeger(strLen(s))
  if need <= 0 or f == "" then return "" end
  return f:rep(need // #f + 1):sub(1, need)
end
method(S, "padStart", function(s, w, f) return pad(s, w, f) .. s end)
method(S, "padEnd", function(s, w, f) return s .. pad(s, w, f) end)
method(S, "normalize", function(s) return s end)
method(S, "localeCompare", function(s, o) o = tostr(o); return s < o and -1.0 or (s > o and 1.0 or 0.0) end)
G.String = native("String", function(_, ...)
  if select("#", ...) == 0 then return "" end
  return tostr((...))
end)
FP[G.String].prototype = StringProto
rawset_(StringProto, "constructor", G.String)
st(G.String, "fromCharCode", function(_, ...)
  local o = {}
  for i, c in ipairs{ ... } do o[i] = utf8.char(math.tointeger(toNum(c))) end
  return concat(o)
end)
FP[G.String].fromCodePoint = FP[G.String].fromCharCode

-- Number, Boolean
method(NumberProto, "toFixed", function(x, d) return sfmt("%." .. math.tointeger(toIndex(d, 0)) .. "f", x) end)
method(NumberProto, "toString", function(x, base)
  if base == nil or base == 10 then return numText(x) end
  base = math.tointeger(base)
  local neg = x < 0
  local i = math.tointeger(floor(math.abs(x)))
  local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  local o = {}
  if i == 0 then o[1] = "0" end
  while i > 0 do
    local d = i % base
    table.insert(o, 1, digits:sub(d + 1, d + 1))
    i = i // base
  end
  return (neg and "-" or "") .. concat(o)
end)
method(NumberProto, "toPrecision", function(x, p) return (sfmt("%." .. math.tointeger(p) .. "g", x)) end)
method(NumberProto, "valueOf", function(x) return x end)
method(NumberProto, "toLocaleString", function(x)
  local ip, fp = numText(x):match("^(-?%d+)(.*)$")
  if not ip then return numText(x) end
  return ip:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""):gsub("^%-,", "-") .. fp
end)
method(BooleanProto, "toString", function(b) return b and "true" or "false" end)
method(BooleanProto, "valueOf", function(b) return b end)
G.Number = native("Number", function(_, ...)
  if select("#", ...) == 0 then return 0.0 end
  return toNum((...))
end)
FP[G.Number].prototype = NumberProto
rawset_(NumberProto, "constructor", G.Number)
G.Boolean = native("Boolean", function(_, v) return T(v) end)
FP[G.Boolean].prototype = BooleanProto
rawset_(BooleanProto, "constructor", G.Boolean)
local NP = FP[G.Number]
NP.MAX_SAFE_INTEGER, NP.MIN_SAFE_INTEGER, NP.EPSILON, NP.MAX_VALUE, NP.MIN_VALUE, NP.POSITIVE_INFINITY, NP.NEGATIVE_INFINITY, NP.NaN = 9007199254740991.0, -9007199254740991.0, 2.220446049250313e-16, 1.7976931348623157e308, 5e-324, math.huge, -math.huge, 0 / 0
st(G.Number, "isInteger", function(_, v) return mtype(v) ~= nil and v == floor(v) and v ~= math.huge and v ~= -math.huge end)
st(G.Number, "isSafeInteger", function(_, v) return mtype(v) ~= nil and v == floor(v) and math.abs(v) <= 9007199254740991.0 end)
st(G.Number, "isFinite", function(_, v) return mtype(v) ~= nil and v == v and v ~= math.huge and v ~= -math.huge end)
st(G.Number, "isNaN", function(_, v) return mtype(v) ~= nil and v ~= v end)
G.parseInt = native("parseInt", function(_, s, base)
  s = tostr(s):match("^%s*(.*)$")
  local neg = s:sub(1, 1) == "-"
  if neg or s:sub(1, 1) == "+" then s = s:sub(2) end
  base = base and math.tointeger(toNum(base)) or 0
  if base == 0 then base = 10; if s:find("^0[xX]") then base = 16 end end
  if base == 16 then s = s:gsub("^0[xX]", "") end
  local v, any = 0.0, false
  for i = 1, #s do
    local d = tonumber(s:sub(i, i), 36)
    if not d or d >= base then break end
    v = v * base + d
    any = true
  end
  if not any then return 0 / 0 end
  return neg and -v or v
end)
G.parseFloat = native("parseFloat", function(_, s)
  s = tostr(s):match("^%s*(.*)$")
  if s:find("^[+-]?Infinity") then return s:sub(1, 1) == "-" and -math.huge or math.huge end
  local m = s:match("^[+-]?%d+%.?%d*[eE][+-]?%d+") or s:match("^[+-]?%.%d+[eE][+-]?%d+") or s:match("^[+-]?%d+%.?%d*") or s:match("^[+-]?%.%d+")
  return m and tonumber(m) + 0.0 or 0 / 0
end)
FP[G.Number].parseInt, FP[G.Number].parseFloat = G.parseInt, G.parseFloat
G.isNaN = native("isNaN", function(_, v) v = toNum(v); return v ~= v end)
G.isFinite = native("isFinite", function(_, v) v = toNum(v); return v == v and v ~= math.huge and v ~= -math.huge end)
G.NaN, G.Infinity = 0 / 0, math.huge
G.encodeURIComponent = native("encodeURIComponent", function(_, s) return (tostr(s):gsub("[^%w%-_%.!~%*'%(%)]", function(c) return sfmt("%%%02X", c:byte()) end)) end)
G.decodeURIComponent = native("decodeURIComponent", function(_, s) return (tostr(s):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end)
G.encodeURI = native("encodeURI", function(_, s) return (tostr(s):gsub("[^%w%-_%.!~%*'%(%);/%?:@&=%+%$,#]", function(c) return sfmt("%%%02X", c:byte()) end)) end)

-- Math
local M = newObject()
G.Math = M
local function mathf(name, f) rawset_(M, name, native(name, function(_, ...) return f(...) end)) end
rawset_(M, "PI", math.pi); rawset_(M, "E", math.exp(1)); rawset_(M, "SQRT2", math.sqrt(2)); rawset_(M, "LN2", math.log(2)); rawset_(M, "LN10", math.log(10))
for _, n in ipairs{ "sin", "cos", "tan", "asin", "acos", "exp", "sqrt" } do
  local f = math[n]
  mathf(n, function(x)
    x = toNum(x)
    if n == "sqrt" and x < 0 then return 0 / 0 end
    return f(x)
  end)
end
mathf("floor", function(x) x = toNum(x); if x ~= x or x == math.huge or x == -math.huge then return x end return floor(x) + 0.0 end)
mathf("ceil", function(x) x = toNum(x); if x ~= x or x == math.huge or x == -math.huge then return x end return math.ceil(x) + 0.0 end)
mathf("round", function(x) x = toNum(x); if x ~= x or x == math.huge or x == -math.huge then return x end return floor(x + 0.5) + 0.0 end)
mathf("trunc", function(x) x = toNum(x); if x ~= x or x == math.huge or x == -math.huge then return x end return (x >= 0 and floor(x) or -floor(-x)) + 0.0 end)
mathf("abs", function(x) return math.abs(toNum(x)) end)
mathf("sign", function(x) x = toNum(x); if x > 0 then return 1.0 elseif x < 0 then return -1.0 end return x end)
mathf("atan", function(x) return math.atan(toNum(x)) end)
mathf("atan2", function(y, x) return math.atan(toNum(y), toNum(x)) end)
mathf("log", function(x) x = toNum(x); if x < 0 then return 0 / 0 end return math.log(x) end)
mathf("log2", function(x) return math.log(toNum(x), 2) end)
mathf("log10", function(x) return math.log(toNum(x), 10) end)
mathf("pow", function(a, b) return toNum(a) ^ toNum(b) end)
mathf("cbrt", function(x) x = toNum(x); return x < 0 and -((-x) ^ (1 / 3)) or x ^ (1 / 3) end)
mathf("hypot", function(...) local s = 0.0; for _, v in ipairs{ ... } do v = toNum(v); s = s + v * v end return math.sqrt(s) end)
mathf("random", function() return math.random() end)
mathf("max", function(...)
  local r = -math.huge
  for i = 1, select("#", ...) do local v = toNum((select(i, ...))); if v ~= v then return v end if v > r then r = v end end
  return r
end)
mathf("min", function(...)
  local r = math.huge
  for i = 1, select("#", ...) do local v = toNum((select(i, ...))); if v ~= v then return v end if v < r then r = v end end
  return r
end)

-- JSON
local JSON = newObject()
G.JSON = JSON
local function jsonStr(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" elseif c == "\t" then return "\\t" elseif c == "\r" then return "\\r" end
    return sfmt("\\u%04x", c:byte())
  end) .. '"'
end
local function jsonEnc(v, ind, cur, replacer, key)
  if type_(v) == "table" and v ~= null then
    local tj = v.toJSON
    if type_(tj) == "function" then v = tj(v) end
  end
  if type_(replacer) == "function" then v = replacer(nil, key, v) end
  local t = type_(v)
  if v == null then return "null" end
  if t == "nil" or t == "function" then return nil end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then if v ~= v or v == math.huge or v == -math.huge then return "null" end return numText(v) end
  if t == "string" then return jsonStr(v) end
  local nl, inner = "", ""
  if ind ~= "" then nl = "\n" .. cur; inner = "\n" .. cur .. ind end
  if isArray(v) then
    if v.n == 0 then return "[]" end
    local p = {}
    for i = 1, v.n do p[i] = jsonEnc(v[i], ind, cur .. ind, replacer, tostr(i - 1)) or "null" end
    return "[" .. inner .. concat(p, "," .. inner) .. nl .. "]"
  end
  local p = {}
  local allow = isArray(replacer) and {} or nil
  if allow then for i = 1, replacer.n do allow[replacer[i]] = true end end
  for _, k in ipairs(ownKeys(v)) do
    if not allow or allow[k] then
      local e = jsonEnc(get(v, k), ind, cur .. ind, replacer, k)
      if e then p[#p + 1] = jsonStr(k) .. (ind ~= "" and ": " or ":") .. e end
    end
  end
  if #p == 0 then return "{}" end
  return "{" .. inner .. concat(p, "," .. inner) .. nl .. "}"
end
method(JSON, "stringify", function(_, v, rep, sp)
  local ind = ""
  if mtype(sp) then ind = (" "):rep(math.tointeger(math.min(sp, 10))) elseif type_(sp) == "string" then ind = sp end
  return jsonEnc(v, ind, "", rep, "")
end)
method(JSON, "parse", function(_, s)
  s = tostr(s)
  local i = 1
  local function bad()
    local c = s:sub(i, i)
    throwErr("SyntaxError", c == "" and "Unexpected end of JSON input" or ("Unexpected token " .. c .. " in JSON at position " .. (i - 1)))
  end
  local function ws() i = s:find("%S", i) or #s + 1 end
  local val
  val = function()
    ws()
    local c = s:sub(i, i)
    if c == "{" then
      i = i + 1
      local o = newObject()
      ws()
      if s:sub(i, i) == "}" then i = i + 1; return o end
      while true do
        ws()
        if s:sub(i, i) ~= '"' then bad() end
        local k = val()
        ws()
        if s:sub(i, i) ~= ":" then bad() end
        i = i + 1
        set(o, k, val())
        ws()
        local e = s:sub(i, i)
        if e == "}" then i = i + 1; return o end
        if e ~= "," then bad() end
        i = i + 1
      end
    elseif c == "[" then
      i = i + 1
      local a, n = {}, 0
      ws()
      if s:sub(i, i) == "]" then i = i + 1; return array(a, 0) end
      while true do
        n = n + 1
        a[n] = val()
        ws()
        local e = s:sub(i, i)
        if e == "]" then i = i + 1; return array(a, n) end
        if e ~= "," then bad() end
        i = i + 1
      end
    elseif c == '"' then
      local b, j = {}, i + 1
      while true do
        local x = s:sub(j, j)
        if x == "" then i = j; bad() end
        if x == '"' then break end
        if x == "\\" then
          local y = s:sub(j + 1, j + 1)
          if y == "u" then b[#b + 1] = utf8.char(tonumber(s:sub(j + 2, j + 5), 16)); j = j + 6
          else
            local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" }
            b[#b + 1] = map[y] or y
            j = j + 2
          end
        else b[#b + 1] = x; j = j + 1 end
      end
      i = j + 1
      return concat(b)
    elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4; return null
    end
    local n = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
    if not n then bad() end
    i = i + #n
    return tonumber(n) + 0.0
  end
  local r = val()
  ws()
  if i <= #s then bad() end
  return r
end)

-- Map and Set: the keys keep their order
R.UNDEF = setmt({}, { __tostring = function() return "undefined" end })
local function mkKey(k) if k == nil then return R.UNDEF end if k ~= k then return "\0NaN" end return k end
local function mapLike(name, mt, isMap)
  mt.__index = mt
  mt.proto = mt
  local ctor
  ctor = native(name, function(this) throwErr("TypeError", "Constructor " .. name .. " requires 'new'") end)
  FP[ctor].native = function(src)
    local o = setmt({ idx = {}, ks = {}, vs = {}, top = 0, size_ = 0 }, mt)
    if src ~= nil and src ~= null then
      for e in R.forof(src) do
        if isMap then mt.set(o, get(e, 0.0), get(e, 1.0))
        else mt.add(o, e == R.UNDEF and nil or e) end
      end
    end
    return o
  end
  FP[ctor].prototype = mt
  rawset_(mt, "constructor", ctor)
  G[name] = ctor
  local function put(o, k, v)
    local key = mkKey(k)
    local i = o.idx[key]
    if i then o.vs[i] = v
    else
      i = o.top + 1
      o.top = i
      o.idx[key] = i
      o.ks[i] = key
      o.vs[i] = v
      o.size_ = o.size_ + 1
    end
    return o
  end
  if isMap then mt.set = put; mt.get = function(o, k) local i = o.idx[mkKey(k)]; if i then return o.vs[i] end end
  else mt.add = function(o, k) return put(o, k, true) end end
  mt.has = function(o, k) return o.idx[mkKey(k)] ~= nil end
  mt.delete = function(o, k)
    local key = mkKey(k)
    local i = o.idx[key]
    if not i then return false end
    o.idx[key], o.ks[i], o.vs[i] = nil, nil, nil
    o.size_ = o.size_ - 1
    return true
  end
  mt.clear = function(o) o.idx, o.ks, o.vs, o.top, o.size_ = {}, {}, {}, 0, 0 end
  mt.forEach = function(o, f)
    for i = 1, o.top do
      local k = o.ks[i]
      if k ~= nil then
        local kk = k ~= R.UNDEF and k or nil
        if isMap then f(nil, o.vs[i], kk, o) else f(nil, kk, kk, o) end
      end
    end
  end
  local function list(o, pick)
    local r, n = {}, 0
    for i = 1, o.top do
      local k = o.ks[i]
      if k ~= nil then n = n + 1; r[n] = pick(k ~= R.UNDEF and k or nil, o.vs[i]) end
    end
    return array(r, n)
  end
  mt.keys = function(o) return list(o, function(k) return k end) end
  mt.values = function(o) return list(o, function(k, v) if isMap then return v end return k end) end
  mt.entries = function(o) return list(o, function(k, v) return R.arrn(2, k, isMap and v or k) end) end
  mt[R.iteratorKey] = isMap and mt.entries or mt.values
  mt.size = setmt({ get = function(o) return o.size_ + 0.0 end }, Accessor)
end
mapLike("Map", MapMt, true)
mapLike("Set", SetMt, false)
G.WeakMap, G.WeakSet = G.Map, G.Set
local SymbolCtor = native("Symbol", function(_, d) return "@@sym:" .. tostr(d) .. ":" .. tostring({}) end)
G.Symbol = SymbolCtor
FP[SymbolCtor].iterator = R.iteratorKey
FP[SymbolCtor].asyncIterator = "@@asyncIterator"

-- RegExp, using the matcher of relang
local RegExpMt = {}
R.RegExpMt = RegExpMt
RegExpMt.__index = RegExpMt
RegExpMt.proto = RegExpMt
local function flagBits(f)
  local b = 0
  if f:find("i", 1, true) then b = b | 2 end
  if f:find("m", 1, true) then b = b | 8 end
  if f:find("s", 1, true) then b = b | 16 end
  return b
end
function R.regex(src, flags)
  local engine = driver.load("relang")
  R.reEngine = R.reEngine or engine
  local tree, ng, names = R.reEngine.parse(src)
  local o = setmt({ source = src, flags = flags, tree = tree, ng = ng, names = names, bits = flagBits(flags), global = flags:find("g", 1, true) ~= nil, ignoreCase = flags:find("i", 1, true) ~= nil, lastIndex = 0.0 }, RegExpMt)
  return o
end
G.RegExp = native("RegExp", function(_, s, f) return R.regex(tostr(s), f or "") end)
FP[G.RegExp].native = function(s, f)
  if getmt(s) == RegExpMt then s = s.source end
  return R.regex(tostr(s), f or "")
end
FP[G.RegExp].prototype = RegExpMt
local function reSearch(r, s, from)
  for j = from, #s + 1 do
    local e, caps = R.reEngine.exec(r.tree, s, j, r.bits)
    if e then return j, e, caps end
  end
end
local function matchArray(r, s, a, e, caps)
  local o = { s:sub(a, e - 1) }
  for g = 1, r.ng do local c = caps[g]; o[g + 1] = c and s:sub(c[1], c[2]) or nil end
  local m = array(o, r.ng + 1)
  rawset_(m, "index", a - 1.0)
  rawset_(m, "input", s)
  if next(r.names) then
    local g = newObject()
    for n, i in pairs(r.names) do set(g, n, o[i + 1]) end
    rawset_(m, "groups", g)
  end
  return m
end
function RegExpMt.exec(r, s)
  s = tostr(s)
  local from = (r.global or r.flags:find("y", 1, true)) and math.tointeger(r.lastIndex) + 1 or 1
  local a, e, caps = reSearch(r, s, from)
  if not a then r.lastIndex = 0.0; return null end
  if r.global then r.lastIndex = (e > a and e or e + 1) - 1.0 end
  return matchArray(r, s, a, e, caps)
end
function RegExpMt.test(r, s) return RegExpMt.exec(r, s) ~= null end
function RegExpMt.toString(r) return "/" .. r.source .. "/" .. r.flags end
local function allMatches(r, s)
  local out, i = {}, 1
  while i <= #s + 1 do
    local a, e, caps = reSearch(r, s, i)
    if not a then break end
    out[#out + 1] = { a = a, e = e, caps = caps }
    i = e > a and e or e + 1
    if not r.global then break end
  end
  return out
end
method(S, "match", function(s, r)
  if getmt(r) ~= RegExpMt then r = R.regex(tostr(r), "") end
  if not r.global then
    local a, e, caps = reSearch(r, s, 1)
    if not a then return null end
    return matchArray(r, s, a, e, caps)
  end
  local ms = allMatches(r, s)
  if #ms == 0 then return null end
  local o = {}
  for i, m in ipairs(ms) do o[i] = s:sub(m.a, m.e - 1) end
  return array(o, #o)
end)
method(S, "matchAll", function(s, r)
  local o = {}
  for i, m in ipairs(allMatches(r, s)) do o[i] = matchArray(r, s, m.a, m.e, m.caps) end
  return array(o, #o)
end)
method(S, "search", function(s, r)
  local a = reSearch(r, s, 1)
  return a and a - 1.0 or -1.0
end)
local function replacement(rep, r, s, m)
  if type_(rep) == "function" then
    local args = { s:sub(m.a, m.e - 1) }
    local ng = r and r.ng or 0
    for g = 1, ng do local c = m.caps[g]; args[g + 1] = c and s:sub(c[1], c[2]) or nil end
    args[ng + 2] = m.a - 1.0
    args[ng + 3] = s
    return tostr(rep(nil, unpack(args, 1, ng + 3)))
  end
  rep = tostr(rep)
  return (rep:gsub("%$([%d&$])", function(d)
    if d == "$" then return "$" end
    if d == "&" then return s:sub(m.a, m.e - 1) end
    local c = m.caps and m.caps[tonumber(d)]
    return c and s:sub(c[1], c[2]) or ""
  end))
end
local function replaceAny(s, p, rep, all)
  if getmt(p) == RegExpMt then
    local out, i = {}, 1
    for _, m in ipairs(allMatches(p, s)) do
      out[#out + 1] = s:sub(i, m.a - 1)
      out[#out + 1] = replacement(rep, p, s, m)
      i = m.e
    end
    out[#out + 1] = s:sub(i)
    return concat(out)
  end
  p = tostr(p)
  local out, i = {}, 1
  while true do
    local a, b = s:find(p, i, true)
    if not a then break end
    out[#out + 1] = s:sub(i, a - 1)
    out[#out + 1] = replacement(rep, nil, s, { a = a, e = b + 1 })
    i = b + 1
    if not all or p == "" then break end
  end
  out[#out + 1] = s:sub(i)
  return concat(out)
end
method(S, "replace", function(s, p, rep) return replaceAny(s, p, rep, false) end)
method(S, "replaceAll", function(s, p, rep) return replaceAny(s, p, rep, true) end)
method(S, "split", function(s, sep, lim)
  local o, n = {}, 0
  if sep == nil then return array({ s }, 1) end
  if getmt(sep) == RegExpMt then
    local i = 1
    local copy = setmt({ tree = sep.tree, ng = sep.ng, bits = sep.bits, global = true }, RegExpMt)
    for _, m in ipairs(allMatches(copy, s)) do
      if m.e > m.a then
        n = n + 1; o[n] = s:sub(i, m.a - 1)
        for g = 1, sep.ng do local c = m.caps[g]; n = n + 1; o[n] = c and s:sub(c[1], c[2]) or nil end
        i = m.e
      end
    end
    n = n + 1; o[n] = s:sub(i)
  elseif sep == "" then
    for c in R.forof(s) do n = n + 1; o[n] = c end
  else
    sep = tostr(sep)
    local i = 1
    while true do
      local a, b = s:find(sep, i, true)
      if not a then break end
      n = n + 1; o[n] = s:sub(i, a - 1)
      i = b + 1
    end
    n = n + 1; o[n] = s:sub(i)
  end
  if lim ~= nil and n > lim then n = math.tointeger(lim); for k = n + 1, #o do o[k] = nil end end
  return array(o, n)
end)

-- Date (the clock of the device)
local DateMt = {}
R.DateMt = DateMt
DateMt.__index = DateMt
DateMt.proto = DateMt
local function nowMs()
  if sys and sys.time then local t = sys.time(); if t then return floor(t) * 1000.0 end end
  return (sys and sys.millis and sys.millis() or 0) + 0.0
end
local function civil(ms)
  local days = floor(ms / 86400000)
  local z = days + 719468
  local era = floor(z / 146097)
  local doe = z - era * 146097
  local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  local mp = floor((5 * doy + 2) / 153)
  local d = doy - floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400 + (m <= 2 and 1 or 0)
  local rest = ms - days * 86400000
  return y, m, d, floor(rest / 3600000), floor(rest / 60000) % 60, floor(rest / 1000) % 60, rest % 1000, (days + 4) % 7
end
local function dayNum(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = floor(y / 400)
  local yoe = y - era * 400
  local doy = floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
  local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end
G.Date = native("Date", function() return "now" end)
FP[G.Date].native = function(a, mo, d, h, mi, s, ms)
  local t
  if a == nil then t = nowMs()
  elseif mo ~= nil then t = dayNum(toNum(a), toNum(mo) + 1, d and toNum(d) or 1) * 86400000 + (h or 0) * 3600000 + (mi or 0) * 60000 + (s or 0) * 1000 + (ms or 0)
  elseif mtype(a) then t = a
  elseif getmt(a) == DateMt then t = a.t
  else
    local y, m2, d2, H, M2, S2 = tostr(a):match("^(%d+)-(%d+)-(%d+)[T ]?(%d*):?(%d*):?(%d*)")
    if y then t = dayNum(tonumber(y), tonumber(m2), tonumber(d2)) * 86400000 + (tonumber(H) or 0) * 3600000 + (tonumber(M2) or 0) * 60000 + (tonumber(S2) or 0) * 1000
    else t = 0 / 0 end
  end
  return setmt({ t = t + 0.0 }, DateMt)
end
FP[G.Date].prototype = DateMt
st(G.Date, "now", function() return nowMs() end)
function DateMt.getTime(d) return d.t end
DateMt.valueOf = DateMt.getTime
for i, n in ipairs{ "FullYear", "Month", "Date", "Hours", "Minutes", "Seconds", "Milliseconds", "Day" } do
  local f = function(d)
    local v = select(i, civil(d.t))
    if n == "Month" then v = v - 1 end
    return v + 0.0
  end
  DateMt["get" .. n], DateMt["getUTC" .. n] = f, f
end
function DateMt.toISOString(d)
  local y, m, dd, h, mi, s, ms = civil(d.t)
  return sfmt("%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", y, m, dd, h, mi, s, ms)
end
DateMt.toJSON, DateMt.toString = DateMt.toISOString, DateMt.toISOString
function DateMt.toLocaleDateString(d) local y, m, dd = civil(d.t); return sfmt("%d/%d/%d", m, dd, y) end
function DateMt.toLocaleTimeString(d) local _, _, _, h, mi, s = civil(d.t); return sfmt("%02d:%02d:%02d", h, mi, s) end
function DateMt.getTimezoneOffset() return 0.0 end

-- Promise, timers: the event loop runs when the program ends
local micro, timers, timerId, clockNow = {}, {}, 0, 0
local PromiseMt = {}
PromiseMt.__index = PromiseMt
PromiseMt.proto = PromiseMt
local function queueMicro(f) micro[#micro + 1] = f end
local function settle(p, state, v)
  if p.state ~= "pending" then return end
  p.state, p.value = state, v
  for _, cb in ipairs(p.cbs) do queueMicro(function() cb(state, v) end) end
  p.cbs = {}
end
local resolvePromise
resolvePromise = function(p, v)
  if p.state ~= "pending" then return end
  if type_(v) == "table" and v ~= null then
    if getmt(v) == PromiseMt then
      local cbs = v.cbs
      if v.state == "pending" then cbs[#cbs + 1] = function(s, x) settle(p, s, x) end
      else queueMicro(function() settle(p, v.state, v.value) end) end
      return
    end
    local th = v["then"]
    if type_(th) == "function" then
      queueMicro(function()
        th(v, function(_, x) resolvePromise(p, x) end, function(_, x) settle(p, "rejected", x) end)
      end)
      return
    end
  end
  settle(p, "fulfilled", v)
end
local function newPromise() return setmt({ state = "pending", cbs = {} }, PromiseMt) end
PromiseMt["then"] = function(p, onOk, onErr)
  local q = newPromise()
  local function handle(state, v)
    local f = state == "fulfilled" and onOk or onErr
    if state == "rejected" then p.handled = true end
    if type_(f) ~= "function" then
      if state == "fulfilled" then resolvePromise(q, v) else settle(q, "rejected", v) end
      return
    end
    local ok, r = pcall(f, nil, v)
    if ok then resolvePromise(q, r) else settle(q, "rejected", R.catch(r)) end
  end
  if p.state == "pending" then p.cbs[#p.cbs + 1] = handle
  else queueMicro(function() handle(p.state, p.value) end) end
  if onErr then p.handled = true end
  return q
end
PromiseMt["catch"] = function(p, f) return PromiseMt["then"](p, nil, f) end
PromiseMt["finally"] = function(p, f)
  return PromiseMt["then"](p, function(_, v) f(nil); return v end, function(_, e) f(nil); R.throw(e) end)
end
G.Promise = native("Promise", function() throwErr("TypeError", "Promise constructor cannot be invoked without 'new'") end)
FP[G.Promise].native = function(ex)
  local p = newPromise()
  local ok, e = pcall(ex, nil, function(_, v) resolvePromise(p, v) end, function(_, v) settle(p, "rejected", v) end)
  if not ok then settle(p, "rejected", R.catch(e)) end
  return p
end
FP[G.Promise].prototype = PromiseMt
st(G.Promise, "resolve", function(_, v)
  if getmt(v) == PromiseMt then return v end
  local p = newPromise()
  resolvePromise(p, v)
  return p
end)
st(G.Promise, "reject", function(_, v) local p = newPromise(); settle(p, "rejected", v); return p end)
local function combine(mode)
  return function(_, it)
    local q = newPromise()
    local items = R.toarr(it)
    local res = {}
    local left = items.n
    if left == 0 and mode ~= "race" then resolvePromise(q, array({}, 0)) end
    for i = 1, items.n do
      local p = FP[G.Promise].resolve(nil, items[i])
      PromiseMt["then"](p, function(_, v)
        if mode == "race" or mode == "any" then resolvePromise(q, v); return end
        if mode == "allSettled" then
          local o = newObject(); set(o, "status", "fulfilled"); set(o, "value", v); v = o
        end
        res[i] = v
        left = left - 1
        if left == 0 then resolvePromise(q, array(res, items.n)) end
      end, function(_, e)
        if mode == "allSettled" then
          local o = newObject(); set(o, "status", "rejected"); set(o, "reason", e)
          res[i] = o
          left = left - 1
          if left == 0 then resolvePromise(q, array(res, items.n)) end
        elseif mode == "any" then
          left = left - 1
          if left == 0 then settle(q, "rejected", R.new(G.Error, "All promises were rejected")) end
        else settle(q, "rejected", e) end
      end)
    end
    return q
  end
end
for _, m in ipairs{ "all", "race", "any", "allSettled" } do st(G.Promise, m, combine(m)) end
function R.async(body)
  local p = newPromise()
  local co = coroutine.create(body)
  local step
  step = function(...)
    local ok, r = coroutine.resume(co, ...)
    if not ok then settle(p, "rejected", R.catch(r)); return end
    if coroutine.status(co) == "dead" then resolvePromise(p, r); return end
    -- it waits for a promise: r is {await=promise}
    local aw = FP[G.Promise].resolve(nil, r.await)
    aw.handled = true
    PromiseMt["then"](aw, function(_, v) step(true, v) end, function(_, e) step(false, e) end)
  end
  step()
  return p
end
function R.await(v)
  if not coroutine.isyieldable() then
    -- a top-level await: the loop runs until the promise is settled
    local p = FP[G.Promise].resolve(nil, v)
    p.handled = true
    while p.state == "pending" do
      if not R.runOne() then break end
    end
    if p.state == "rejected" then R.throw(p.value) end
    return p.value
  end
  local ok, x = coroutine.yield({ await = v })
  if not ok then R.throw(x) end
  return x
end
local function addTimer(f, ms, again, args)
  timerId = timerId + 1
  ms = toNum(ms or 0)
  if ms ~= ms or ms < 1 then ms = 1 end
  timers[#timers + 1] = { id = timerId + 0.0, at = clockNow + ms, f = f, every = again and ms, args = args, seq = timerId }
  return timerId + 0.0
end
G.setTimeout = native("setTimeout", function(_, f, ms, ...) return addTimer(f, ms, false, { ... }) end)
G.setInterval = native("setInterval", function(_, f, ms, ...) return addTimer(f, ms, true, { ... }) end)
G.setImmediate = native("setImmediate", function(_, f, ...) return addTimer(f, 0, false, { ... }) end)
local function clearT(_, id) for i, t in ipairs(timers) do if t.id == id then table.remove(timers, i); return end end end
G.clearTimeout, G.clearInterval, G.clearImmediate = native("clearTimeout", clearT), native("clearInterval", clearT), native("clearImmediate", clearT)
G.queueMicrotask = native("queueMicrotask", function(_, f) queueMicro(function() f(nil) end) end)
local function drainMicro()
  local i = 1
  while i <= #micro do
    local f = micro[i]
    i = i + 1
    f()
    if i > 2000 then
      table.move(micro, i, #micro + i, 1)
      i = 1
    end
  end
  micro = {}
end
function R.runOne()
  drainMicro()
  if #timers == 0 then return false end
  local best = 1
  for i, t in ipairs(timers) do
    if t.at < timers[best].at or (t.at == timers[best].at and t.seq < timers[best].seq) then best = i end
  end
  local t = timers[best]
  local wait = t.at - clockNow
  if wait > 0 then
    if sys and sys.sleep then sys.sleep(math.floor(wait)) end
    clockNow = t.at
  end
  if t.every then t.at = clockNow + t.every else table.remove(timers, best) end
  t.f(nil, unpack(t.args))
  drainMicro()
  return true
end

-- console, process, modules
local console = newObject()
G.console = console
local indent = ""
local function logger(...)
  local s = formatArgs(...)
  if indent ~= "" then s = indent .. s:gsub("\n", "\n" .. indent) end
  write(s .. "\n")
end
for _, n in ipairs{ "log", "info", "debug", "error", "warn", "trace" } do method(console, n, function(_, ...) logger(...) end) end
method(console, "group", function(_, ...) if select("#", ...) > 0 then logger(...) end indent = indent .. "  " end)
method(console, "groupEnd", function() indent = indent:sub(3) end)
method(console, "table", function(_, v) logger(v) end)
method(console, "dir", function(_, v) logger(v) end)
method(console, "assert", function(_, c, ...) if not T(c) then logger("Assertion failed", ...) end end)
method(console, "time", function() end)
method(console, "timeEnd", function() end)
local process = newObject()
G.process = process
local stdout = newObject()
method(stdout, "write", function(_, s) write(tostr(s)); return true end)
set(process, "stdout", stdout)
set(process, "stderr", stdout)
set(process, "platform", "esp32p4")
set(process, "version", "v20.0.0")
set(process, "pid", 1.0)
local envO = newObject()
set(envO, "HOME", "/home/user")
set(envO, "USER", "user")
set(process, "env", envO)
method(process, "exit", function(_, c) error({ exit = c and math.tointeger(toNum(c)) or 0 }, 0) end)
method(process, "cwd", function() return "/home/user" end)
method(process, "uptime", function() return (sys and sys.millis and sys.millis() or 0) / 1000 end)
method(process, "on", function() end)
method(process, "nextTick", function(_, f, ...) local a = { ... }; queueMicro(function() f(nil, unpack(a)) end) end)
local hr = native("hrtime", function() local m = sys and sys.millis and sys.millis() or 0; return R.arrn(2, floor(m / 1000) + 0.0, (m % 1000) * 1e6) end)
set(process, "hrtime", hr)
method(process, "memoryUsage", function() local o = newObject(); set(o, "heapUsed", collectgarbage("count") * 1024); return o end)
G.globalThis = newObject()
G.global = G.globalThis
G.performance = newObject()
method(G.performance, "now", function() return (sys and sys.millis and sys.millis() or 0) + 0.0 end)

local function readLineKeys(prompt)
  if prompt then write(prompt) end
  if io and io.read then return io.read("l") end
  if not key or not key.poll then return nil end
  local buf = {}
  while true do
    local k = key.poll()
    if k == "enter" then write("\n"); return concat(buf) end
    if k == "backspace" then if #buf > 0 then buf[#buf] = nil; write("\b \b") end
    elseif k == "ctrl-d" then if #buf == 0 then return nil end
    elseif k == "space" then buf[#buf + 1] = " "; write(" ")
    elseif k and #k == 1 then buf[#buf + 1] = k; write(k)
    elseif not k and sys and sys.sleep then sys.sleep(10) end
  end
end
local modules = {}
local function nodeError(code, msg) local e = R.new(G.Error, msg); set(e, "code", code); R.throw(e) end
function modules.fs()
  local m = newObject()
  method(m, "readFileSync", function(_, p)
    local s = fs.read(p)
    if not s then nodeError("ENOENT", "ENOENT: no such file or directory, open '" .. tostr(p) .. "'") end
    return s
  end)
  method(m, "writeFileSync", function(_, p, s) fs.write(p, tostr(s)) end)
  method(m, "appendFileSync", function(_, p, s) fs.append(p, tostr(s)) end)
  method(m, "existsSync", function(_, p) return fs.exists(p) and true or false end)
  method(m, "unlinkSync", function(_, p) fs.remove(p) end)
  method(m, "mkdirSync", function(_, p) if sys and sys.shell then sys.shell("mkdir -p " .. p) end end)
  method(m, "readdirSync", function(_, p)
    local items = fs.list(p) or {}
    local o = {}
    for i, it in ipairs(items) do o[i] = type_(it) == "table" and it.name or it end
    return array(o, #o)
  end)
  method(m, "statSync", function(_, p)
    local s = fs.stat(p)
    if not s then nodeError("ENOENT", "ENOENT: no such file or directory, stat '" .. tostr(p) .. "'") end
    local o = newObject()
    set(o, "size", (type_(s) == "table" and s.size or 0) + 0.0)
    local isDir = type_(s) == "table" and s.isDir
    method(o, "isDirectory", function() return isDir == true end)
    method(o, "isFile", function() return not isDir end)
    return o
  end)
  return m
end
function modules.os()
  local m = newObject()
  method(m, "platform", function() return "linux" end)
  method(m, "hostname", function() return sys and sys.hostname and sys.hostname() or "esp" end)
  method(m, "arch", function() return "riscv32" end)
  method(m, "homedir", function() return "/home/user" end)
  method(m, "uptime", function() return (sys and sys.millis and sys.millis() or 0) / 1000 end)
  set(m, "EOL", "\n")
  return m
end
function modules.path()
  local m = newObject()
  method(m, "join", function(_, ...)
    local o = {}
    for _, p in ipairs{ ... } do if p ~= "" then o[#o + 1] = p end end
    local s = concat(o, "/"):gsub("/+", "/")
    return s
  end)
  method(m, "basename", function(_, p, ext)
    local b = p:match("([^/]*)$")
    if ext and b:sub(-#ext) == ext then b = b:sub(1, -#ext - 1) end
    return b
  end)
  method(m, "dirname", function(_, p) return p:match("^(.*)/[^/]*$") or "." end)
  method(m, "extname", function(_, p) return p:match("[^/.](%.[^./]*)$") or "" end)
  method(m, "resolve", function(_, ...) return concat({ ... }, "/") end)
  set(m, "sep", "/")
  return m
end
function modules.readline()
  local m = newObject()
  method(m, "createInterface", function()
    local i = newObject()
    method(i, "question", function(_, q, cb) local l = readLineKeys(tostr(q)); cb(nil, l or "") end)
    method(i, "close", function() end)
    method(i, "on", function(self, ev, cb)
      if ev == "line" then
        addTimer(function()
          while true do
            local l = readLineKeys()
            if not l then break end
            cb(nil, l)
          end
        end, 0, false, {})
      end
      return self
    end)
    return i
  end)
  return m
end
function modules.util()
  local m = newObject()
  method(m, "inspect", function(_, v) return inspect(v, 1) end)
  method(m, "format", function(_, ...) return formatArgs(...) end)
  return m
end
function modules.assert()
  local f = native("assert", function(_, c, msg) if not T(c) then R.throw(R.new(G.Error, msg or "Assertion failed")) end end)
  FP[f].strictEqual = native("strictEqual", function(_, a, b, msg) if a ~= b then R.throw(R.new(G.Error, msg or "Expected values to be strictly equal")) end end)
  FP[f].equal = FP[f].strictEqual
  return f
end
function modules.events()
  local src = driver and nil
  local cls = R.class("EventEmitter", nil, function(this) rawset_(this, "_l", {}) end, {
    { k = "on", f = R.fn(function(this, ev, f) local l = rawget_(this, "_l"); l[ev] = l[ev] or {}; table.insert(l[ev], f); return this end, "on"), static = false },
    { k = "emit", f = R.fn(function(this, ev, ...) local l = rawget_(this, "_l")[ev]; if not l then return false end for _, f in ipairs(l) do f(this, ...) end return true end, "emit"), static = false },
    { k = "off", f = R.fn(function(this, ev, f) local l = rawget_(this, "_l")[ev]; if l then for i, x in ipairs(l) do if x == f then table.remove(l, i); break end end end return this end, "off"), static = false },
    { k = "once", f = R.fn(function(this, ev, f) local w; w = function(t, ...) local l = rawget_(t, "_l")[ev]; for i, x in ipairs(l) do if x == w then table.remove(l, i); break end end return f(t, ...) end; local l = rawget_(this, "_l"); l[ev] = l[ev] or {}; table.insert(l[ev], w); return this end, "once"), static = false },
  }, {})
  FP[cls].EventEmitter = cls
  return cls
end
local loaded = {}
G.require = native("require", function(_, name)
  name = tostr(name):gsub("^node:", "")
  if loaded[name] ~= nil then return loaded[name] end
  if modules[name] then
    loaded[name] = modules[name]()
    return loaded[name]
  end
  -- a file next to the program
  local base = R.scriptDir or "."
  local paths = name:sub(1, 1) == "/" and { name, name .. ".js" } or { base .. "/" .. name, base .. "/" .. name .. ".js", "/usr/local/lib/node_modules/" .. name .. ".js", "/usr/local/lib/node_modules/" .. name .. "/index.js" }
  for _, p in ipairs(paths) do
    local src = fs.read(p)
    if src then
      local exports = newObject()
      local mod = newObject()
      set(mod, "exports", exports)
      loaded[name] = exports
      R.runSource(src, p, { module = mod, exports = exports })
      loaded[name] = get(mod, "exports")
      return loaded[name]
    end
  end
  local e = R.new(G.Error, "Cannot find module '" .. name .. "'")
  set(e, "code", "MODULE_NOT_FOUND")
  R.throw(e)
end)

-- ---- running ----
local HELP = { "T", "get", "set", "len", "M", "call", "new", "obj", "array", "arrn", "arrspread", "spreadargs", "toarr", "arrfrom", "objrest", "def", "fn", "gen", "async", "await", "yield", "yieldstar", "class", "superctor", "supercall", "superget",
  "instanceof", "tostr", "key", "num", "neg", "add", "sub", "mul", "div", "mod", "pow", "band", "bor", "bxor", "bnot", "shl", "shr", "ushr", "lt", "gt", "le", "ge", "eq", "ne", "typeof", "void", "delete", "last", "nullish", "forof", "forin", "regex", "throw", "catch" }
local function header()
  local names, values = {}, {}
  for _, k in ipairs(HELP) do names[#names + 1] = "R_" .. k; values[#values + 1] = "RT." .. k end
  names[#names + 1] = "R_and"; values[#values + 1] = "RT.and_"
  names[#names + 1] = "R_or"; values[#values + 1] = "RT.or_"
  names[#names + 1] = "R_if"; values[#values + 1] = "RT.if_"
  names[#names + 1] = "R_in"; values[#values + 1] = "RT.in_"
  names[#names + 1] = "R_andv"; values[#values + 1] = "RT.andv"
  names[#names + 1] = "R_orv"; values[#values + 1] = "RT.orv"
  names[#names + 1] = "R_fmod"; values[#values + 1] = "RT.fmod"
  return "local R_pcall,R_error,table,rawget_env=pcall,error,table,rawget_env\nlocal RT, _ENV = ...\nlocal null=RT.null\nlocal this\nlocal " .. concat(names, ",") .. "=" .. concat(values, ",") .. "\n"
end
R.header = header  -- for hosts that load translated text in their own environment (the html player)
function R.runSource(src, name, extra)
  local text = R.compiler(src)
  local env = setmt(extra or {}, { __index = function(_, k)
    local v = G[k]
    if v ~= nil then return v end
    if k == "_ENV" then return nil end
    if _G[k] ~= nil and (k == "gfx" or k == "term" or k == "key" or k == "touch" or k == "net" or k == "fs" or k == "gpio" or k == "audio") then return _G[k] end
    error(setmt({ v = R.new(G.ReferenceError, tostr(k) .. " is not defined") }, Thrown), 0)
  end })
  local f, e = load(header() .. text, "=" .. name, "t")
  if not f then error({ syntax = "internal: " .. tostring(e), line = 0 }, 0) end
  return f(R, env)
end
function R.protect(f, name)
  local ok, e = pcall(f)
  if ok then return 0 end
  if type_(e) == "table" and e.exit then return e.exit end
  if type_(e) == "table" and e.syntax then
    write(name .. ":" .. tostring(e.line) .. "\nSyntaxError: " .. e.syntax .. "\n")
    return 1
  end
  if type_(e) == "string" and e:find("interrupted", 1, true) then error(e, 0) end
  local v = R.catch(e)
  write("Uncaught " .. inspect(v, 1) .. "\n")
  return 1
end
-- A program translated on the computer (tools/linux2esp.py)
function R.run(text, argv)
  R.reEngine = driver.load("relang")
  local av = { "node", argv[1] }
  for i = 2, #argv do av[#av + 1] = argv[i] end
  set(process, "argv", array(av, #av))
  R.scriptDir = "."
  local mod = newObject()
  local exports = newObject()
  set(mod, "exports", exports)
  local name = tostring(argv[1])
  return R.protect(function()
    local env = setmt({ module = mod, exports = exports, __filename = name, __dirname = "." }, { __index = function(_, k)
      local v = G[k]
      if v ~= nil then return v end
      if k == "_ENV" then return nil end
      if _G[k] ~= nil and (k == "gfx" or k == "term" or k == "key" or k == "touch" or k == "net" or k == "fs" or k == "gpio" or k == "audio") then return _G[k] end
      error(setmt({ v = R.new(G.ReferenceError, tostr(k) .. " is not defined") }, Thrown), 0)
    end })
    local f, e = load(header() .. text, "=" .. name, "t")
    if not f then error({ syntax = "internal: " .. tostring(e), line = 0 }, 0) end
    f(R, env)
    while R.runOne() do end
  end, name)
end

function R.main(args, compiler)
  R.compiler = compiler
  R.reEngine = driver.load("relang")
  local path, code
  local i = 1
  while args[i] do
    local a = args[i]
    if a == "-e" or a == "--eval" then code = args[i + 1]; i = i + 2; break
    elseif a == "-p" or a == "--print" then code = "console.log(" .. args[i + 1] .. ")"; i = i + 2; break
    elseif a == "--version" or a == "-v" then write("v20.0.0 (ESP Linux)\n"); return 0
    elseif a == "--selftest" then code = "console.log('node ok', [1,2,3].map(x => x * 2))"; i = i + 1; break
    else path = a; i = i + 1; break end
  end
  local argv = { "node", path or "-" }
  while args[i] do argv[#argv + 1] = args[i]; i = i + 1 end
  set(process, "argv", array(argv, #argv))
  if not path and not code then return R.repl() end
  local src = code
  if path then
    src = fs.read(path)
    if not src then
      write("Error: Cannot find module '" .. path .. "'\n")
      return 1
    end
    R.scriptDir = path:match("^(.*)/[^/]*$") or "."
  end
  local mod = newObject()
  local exports = newObject()
  set(mod, "exports", exports)
  local status = R.protect(function()
    R.runSource(src, path or "[eval]", { module = mod, exports = exports, __filename = path or "[eval]", __dirname = R.scriptDir or "." })
    while R.runOne() do end
  end, path or "[eval]")
  return status
end
function R.repl()
  write("Welcome to Node.js for ESP Linux (translated to Lua). Ctrl+D to leave.\n")
  local env = {}
  while true do
    local line = readLineKeys("> ")
    if not line then write("\n"); return 0 end
    if line:find("%S") then
      R.protect(function()
        -- the value of an expression is shown
        local ok = pcall(R.compiler, "(" .. line .. ")")
        if ok then
          local holder = setmt({}, { __index = env, __newindex = env })
          R.runSource("console.log((" .. line .. "))", "repl", env)
        else
          R.runSource((line:gsub("^%s*let%s", "var "):gsub("^%s*const%s", "var ")), "repl", env)
        end
        while R.runOne() do end
      end, "repl")
    end
  end
end
return R
