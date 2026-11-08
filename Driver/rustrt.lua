#!lua
-- rustrt: the run-time of the Rust programs that rustlang translates: Vec, String, Option, Result, iterators, maps, formatting.
local R = {}
local mtype, floor, concat, sfmt, unpack = math.type, math.floor, table.concat, string.format, table.unpack
local setmt, getmt, type_ = setmetatable, getmetatable, type
function R.write(s) term.write(s) end
local PanicMt = {}
function R.panic(msg) error(setmt({ msg = msg }, PanicMt), 0) end
local panic = R.panic
R.unit = setmt({}, { __name = "unit" })
local unit = R.unit

-- ---- generic classes ----
local Vec = { __name = "Vec" }
Vec.__index = Vec
local Tuple = { __name = "tuple" }
Tuple.__index = Tuple
local Map = { __name = "Map" }
Map.__index = Map
local Set = { __name = "Set" }
Set.__index = Set
local Range = { __name = "Range" }
Range.__index = Range
local Iter = { __name = "Iter" }
Iter.__index = Iter
local Option = { __name = "Option", __enum = true }
Option.__index = Option
local Result = { __name = "Result", __enum = true }
Result.__index = Result
local Ref = { __name = "Ref" }       -- a &mut to a place that holds a scalar
Ref.__index = function(t, k)
  if k == "v" then return t.get() end
  return nil
end
local Ordering = { __name = "Ordering", __enum = true }
Ordering.__index = Ordering
local Cell = { __name = "RefCell" }
Cell.__index = Cell

function R.vec(t)
  t.n = #t
  return setmt(t, Vec)
end
local function vecn(t, n) t.n = n; return setmt(t, Vec) end
function R.vecRepeat(v, n)
  local t = {}
  local isT = type_(v) == "table"
  for i = 1, n do t[i] = isT and R.clone(v) or v end
  return vecn(t, n)
end
function R.tuple(t) return setmt(t, Tuple) end
function R.range(a, b, incl)
  return setmt({ a = a, b = b, incl = incl or false }, Range)
end
function R.bytes(s) local t = {}; for i = 1, #s do t[i] = s:byte(i) end return vecn(t, #s) end
function R.vslice(v, a, b)
  local t = {}
  for i = a + 1, b do t[#t + 1] = v[i] end
  return vecn(t, #t)
end
function R.if_(c, a, b) if c then return a end return b end

-- Option and Result
local None = setmt({ tag = "None" }, Option)
R.None = None
function R.Some(v) return setmt({ tag = "Some", v }, Option) end
function R.Ok(v) return setmt({ tag = "Ok", v }, Result) end
function R.Err(v) return setmt({ tag = "Err", v }, Result) end
local Some, Ok, Err = R.Some, R.Ok, R.Err
function R.tagOf(v) if type_(v) == "table" then return v.tag end return nil end
function R.isFail(v) return v == None or (type_(v) == "table" and v.tag == "Err") end
R.Ordering = {}
for i, n in ipairs{ "Less", "Equal", "Greater" } do
  R.Ordering[n] = setmt({ tag = n, ord = i - 2 }, Ordering)
end
local function ordOf(c) if c < 0 then return R.Ordering.Less elseif c > 0 then return R.Ordering.Greater end return R.Ordering.Equal end

-- ---- references ----
function R.mutref(get, set)
  local v = get()
  if type_(v) == "table" and v ~= unit and getmt(v) ~= Option and getmt(v) ~= Result then return v end
  return setmt({ get = get, set = set }, Ref)
end
function R.d(p)
  if type_(p) == "table" then
    local m = getmt(p)
    if m == Ref then return p.get() end
    if m == Cell then return p.v end
  end
  return p
end
local d = R.d
function R.setd(p, v)
  local m = getmt(p)
  if m == Ref then p.set(v)
  elseif m == Cell then p.v = v
  elseif type_(p) == "table" and type_(v) == "table" then
    if p == v then return end
    for k in pairs(p) do p[k] = nil end
    for k, x in pairs(v) do p[k] = x end
    setmt(p, getmt(v))
  else panic("cannot assign through this reference") end
end
-- plain values (a number in a place) that have been passed as references
local function arith(v) if type_(v) == "table" then local m = getmt(v); if m == Ref then return v.get() end if m == Cell then return v.v end end return v end
Ref.__add = function(a, b) return arith(a) + arith(b) end
Ref.__sub = function(a, b) return arith(a) - arith(b) end
Ref.__mul = function(a, b) return arith(a) * arith(b) end
Ref.__eq = function(a, b) return arith(a) == arith(b) end
Ref.__lt = function(a, b) return arith(a) < arith(b) end
Ref.__le = function(a, b) return arith(a) <= arith(b) end
Ref.__unm = function(a) return -arith(a) end
Ref.__concat = function(a, b) return tostring(arith(a)) .. tostring(arith(b)) end
function R.cp(v)
  if type_(v) == "table" then
    local m = getmt(v)
    if m and m.__copy then return R.clone(v) end
    if m == Tuple then
      local allPlain = true
      for i = 1, #v do if type_(v[i]) == "table" then allPlain = false end end
      if allPlain then return R.clone(v) end
    end
  end
  return v
end
function R.clone(v)
  if type_(v) ~= "table" or v == unit or v == None then return v end
  local m = getmt(v)
  if m == Ref then return v.get() end
  if m == Cell and v.shared then return v end
  if m and m.__user_clone then return m.__user_clone(v) end
  if m and rawget(m, "clone") then return m.clone(v) end
  if m == Iter then return v end
  if m == Ordering then return v end
  local o = {}
  for k, x in pairs(v) do
    if type_(x) == "table" then o[k] = R.clone(x) else o[k] = x end
  end
  return setmt(o, m)
end

-- ---- numbers ----
function R.div(a, b)
  a, b = arith(a), arith(b)
  if mtype(a) == "integer" and mtype(b) == "integer" then
    if b == 0 then panic("attempt to divide by zero") end
    local q = a // b
    if q < 0 and q * b ~= a then q = q + 1 end
    return q
  end
  if type_(a) == "table" then
    local m = getmt(a)
    if m and m.__rdiv then return m.__rdiv(a, b) end
  end
  return a / b
end
function R.rem(a, b)
  a, b = arith(a), arith(b)
  if mtype(a) == "integer" and mtype(b) == "integer" then
    if b == 0 then panic("attempt to calculate the remainder with a divisor of zero") end
    return math.fmod(a, b)
  end
  if type_(a) == "table" then
    local m = getmt(a)
    if m and m.__rrem then return m.__rrem(a, b) end
  end
  return math.fmod(a, b)
end
function R.sar(a, b) if a >= 0 then return a >> b end return ~((~a) >> b) end
function R.band(a, b)
  if type_(a) == "boolean" then return a and b end
  if getmt(a) == Set then return Set.intersection(a, b) end
  return a & b
end
function R.bor(a, b)
  if type_(a) == "boolean" then return a or b end
  if getmt(a) == Set then return Set.union(a, b) end
  return a | b
end
function R.bxor(a, b) if type_(a) == "boolean" then return a ~= b end return a ~ b end
function R.not_(a)
  if type_(a) == "boolean" then return not a end
  if mtype(a) then return ~a end
  local m = getmt(a)
  if m and m.__not then return m.__not(a) end
  return not a
end
function R.toInt(v, bits, signed)
  v = arith(v)
  local t = type_(v)
  if t == "string" then v = utf8.codepoint(v)
  elseif t == "boolean" then v = v and 1 or 0
  elseif t == "table" then v = v.disc or 0 end
  if mtype(v) == "float" then
    if v ~= v then return 0 end
    v = v >= 0 and floor(v) or -floor(-v)
    -- a cast saturates
    if bits < 64 then
      local hi = signed and (1 << (bits - 1)) - 1 or (1 << bits) - 1
      local lo = signed and -(1 << (bits - 1)) or 0
      if v > hi then return hi end
      if v < lo then return lo end
    end
    v = math.tointeger(v) or (v > 0 and math.maxinteger or math.mininteger)
    return v
  end
  if bits >= 64 then return v end
  v = v & ((1 << bits) - 1)
  if signed and v >= (1 << (bits - 1)) then v = v - (1 << bits) end
  return v
end
function R.toFloat(v) v = arith(v); return v + 0.0 end
function R.toChar(v) if type_(v) == "string" then return v end return utf8.char(v) end
local LIMITS = { i8 = { -128, 127 }, i16 = { -32768, 32767 }, i32 = { -2147483648, 2147483647 }, i64 = { math.mininteger, math.maxinteger }, isize = { math.mininteger, math.maxinteger }, u8 = { 0, 255 }, u16 = { 0, 65535 }, u32 = { 0, 4294967295 }, u64 = { 0, math.maxinteger }, usize = { 0, math.maxinteger } }
function R.intConst(t, n)
  local l = LIMITS[t]
  if l then
    if n == "MAX" then return l[2] elseif n == "MIN" then return l[1] elseif n == "BITS" then return tonumber(t:match("%d+")) or 64 end
  end
  if n == "MAX" then return 1.7976931348623157e308 elseif n == "MIN" then return -1.7976931348623157e308 elseif n == "INFINITY" then return math.huge elseif n == "NEG_INFINITY" then return -math.huge elseif n == "NAN" then return 0 / 0 elseif n == "EPSILON" then return 2.220446049250313e-16 end
  panic("unknown constant " .. t .. "::" .. n)
end
R.consts = { PI = math.pi, E = math.exp(1), TAU = 2 * math.pi, SQRT_2 = math.sqrt(2), LN_2 = math.log(2), LN_10 = math.log(10), FRAC_PI_2 = math.pi / 2 }

-- strings: + is concatenation
local smt = getmt("")
smt.__add = function(a, b) return tostring(a) .. d(b) end
function R.addAssign(a, b)
  if type_(a) == "table" then
    local m = getmt(a)
    if m == Ref then return a.get() + arith(b) end
    if m and m.__add_assign then m.__add_assign(a, b); return a end
  end
  return a + b
end

-- ---- comparing ----
local function deepEq(a, b)
  if rawequal(a, b) then return true end
  if type_(a) ~= "table" or type_(b) ~= "table" then return a == b end
  local ma, mb = getmt(a), getmt(b)
  if ma == Ref or ma == Cell then return deepEq(d(a), d(b)) end
  if mb == Ref or mb == Cell then return deepEq(a, d(b)) end
  if ma ~= mb then return false end
  if ma == Map or ma == Set then
    if ma == Map or ma == Set then
      if a.n ~= b.n then return false end
      for k, s in pairs(a.h) do
        local o = b.h[k]
        if not o or not deepEq(s.v, o.v) then return false end
      end
      return true
    end
  end
  if ma == Vec and a.n ~= b.n then return false end
  for k, x in pairs(a) do if not deepEq(x, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
R.deepEq = deepEq
local cmp
cmp = function(a, b)
  a, b = d(a), d(b)
  local t = type_(a)
  if t == "number" or t == "string" then
    if a < b then return -1 elseif a > b then return 1 end
    return 0
  end
  if t == "boolean" then
    local x, y = a and 1 or 0, b and 1 or 0
    return x - y
  end
  if t == "table" then
    local m = getmt(a)
    if m and m.__cmp then return m.__cmp(a, b).ord end
    if m and m.__pcmp then
      local o = m.__pcmp(a, b)
      return o[1] and o[1].ord or 0
    end
    if m == Vec then
      for i = 1, math.min(a.n, b.n) do
        local c = cmp(a[i], b[i])
        if c ~= 0 then return c end
      end
      return a.n - b.n
    end
    if m == Tuple then
      for i = 1, #a do
        local c = cmp(a[i], b[i])
        if c ~= 0 then return c end
      end
      return 0
    end
    if m == Option or m == Result then
      if a == None then return b == None and 0 or -1 end
      if b == None then return 1 end
      return cmp(a[1], b[1])
    end
    if m and m.__enum and a.disc and b.disc then return a.disc - b.disc end
    if m and m.__fields then
      for _, f in ipairs(m.__fields) do
        local c = cmp(a[f], b[f])
        if c ~= 0 then return c end
      end
      return 0
    end
  end
  panic("these values cannot be compared")
end
R.cmp = cmp
for _, c in ipairs{ Vec, Tuple, Option, Result, Map, Set } do
  c.__eq = deepEq
  c.__lt = function(a, b) return cmp(a, b) < 0 end
  c.__le = function(a, b) return cmp(a, b) <= 0 end
end

-- ---- user types ----
function R.newStruct(name, fields, copy, tuple)
  local t = { __name = name, __fields = fields, __copy = copy or nil, __tuple = tuple or nil }
  t.__index = t
  t.__eq = function(a, b) if t.__ueq then return t.__ueq(a, b) end return deepEq(a, b) end
  t.__lt = function(a, b)
    if t.__ult then return t.__ult(a, b) end
    return cmp(a, b) < 0
  end
  t.__le = function(a, b) return cmp(a, b) <= 0 end
  if tuple then
    return setmt(t, { __call = function(_, ...) return setmt({ ... }, t) end })
  end
  if #fields == 0 then
    -- a unit struct: the type is its only value
    setmt(t, setmt({}, { __index = function(_, k) return rawget(t, k) end }))
  end
  return t
end
function R.structUpdate(t, fields, base)
  local o = {}
  for k, v in pairs(base) do o[k] = v end
  for k, v in pairs(fields) do o[k] = v end
  return setmt(o, t)
end
function R.newEnum(name, copy)
  local t = { __name = name, __enum = true, __copy = copy or nil }
  t.__index = t
  t.__eq = function(a, b) if t.__ueq then return t.__ueq(a, b) end return deepEq(a, b) end
  t.__lt = function(a, b) return cmp(a, b) < 0 end
  t.__le = function(a, b) return cmp(a, b) <= 0 end
  return t
end
function R.variantUnit(t, n, disc) t[n] = setmt({ tag = n, disc = disc }, t) end
function R.variantTuple(t, n) t[n] = function(...) return setmt({ tag = n, ... }, t) end end
function R.variantFields(t, n, fields)
  t.__vfields = t.__vfields or {}
  t.__vfields[n] = fields
end
function R.variantStruct(t, n, fields)
  fields.tag = n
  return setmt(fields, t)
end
function R.importAll(G, t)
  for k, v in pairs(t) do
    if type_(k) == "string" and k:sub(1, 2) ~= "__" and (type_(v) == "function" or (type_(v) == "table" and v.tag)) then rawset(G, k, v) end
  end
end
function R.newTrait(n) return { __name = n, __trait = true } end
local extTypes = {}
function R.extType(n)
  local t = extTypes[n]
  if not t then
    t = { __name = n, __ext = true }
    t.__index = t
    extTypes[n] = t
  end
  return t
end
function R.implTrait(t, trait, name)
  if type_(trait) == "table" then
    for k, v in pairs(trait) do
      if type_(v) == "function" and t[k] == nil then t[k] = v end
    end
  end
end
local stdlib = {}
function R.genericCall(n)
  panic("calling " .. n .. " through a type parameter is not supported here")
end

-- ---- the built-in maps ----
local function mapKey(k)
  k = d(k)
  if type_(k) == "table" then
    local m = getmt(k)
    if m == Tuple or m == Vec then
      local p = {}
      for i = 1, #k do p[i] = tostring(mapKey(k[i])) end
      return "\0T" .. concat(p, "\1")
    end
    if m and (m.__fields or m.__enum) then
      local p = { tostring(k.tag) }
      if m.__fields then for _, f in ipairs(m.__fields) do p[#p + 1] = tostring(mapKey(k[f])) end end
      for i = 1, #k do p[#p + 1] = tostring(mapKey(k[i])) end
      return "\0S" .. concat(p, "\1")
    end
  end
  return k
end
local function newMap(cls, sorted) return setmt({ h = {}, n = 0, sorted = sorted, seq = 0 }, cls) end
local function mapPut(m, k, v)
  local key = mapKey(k)
  local s = m.h[key]
  if s then
    local old = s.v
    s.v = v
    return old, true
  end
  m.seq = m.seq + 1
  m.h[key] = { k = k, v = v, seq = m.seq }
  m.n = m.n + 1
  return nil, false
end
local function entries(m)
  local items, n = {}, 0
  for _, s in pairs(m.h) do n = n + 1; items[n] = s end
  table.sort(items, function(a, b) return cmp(a.k, b.k) < 0 end)
  return items
end
-- ---- iterators: an object with a next function (nil at the end) ----
local function iterOf(f) return setmt({ f = f }, Iter) end
local Nil = {}  -- stands for the unit in a stream, never nil
function R.iter(x)
  x = d(x)
  local t = type_(x)
  if t == "table" then
    local m = getmt(x)
    if m == Vec then
      local i, n = 0, x.n
      return function()
        i = i + 1
        if i <= n then return x[i] end
      end
    elseif m == Range then
      local i, stop = x.a, x.b
      if type_(i) == "string" then
        local c, e = utf8.codepoint(i), utf8.codepoint(stop)
        if not x.incl then e = e - 1 end
        c = c - 1
        return function()
          c = c + 1
          if c <= e then return utf8.char(c) end
        end
      end
      if stop == nil then
        i = i - 1
        return function() i = i + 1; return i end
      end
      if x.incl then stop = stop + 1 end
      i = i - 1
      return function()
        i = i + 1
        if i < stop then return i end
      end
    elseif m == Iter then return x.f
    elseif m == Map then
      local items, i = entries(x), 0
      return function()
        i = i + 1
        local s = items[i]
        if s then return setmt({ s.k, s.v }, Tuple) end
      end
    elseif m == Set then
      local items, i = entries(x), 0
      return function()
        i = i + 1
        local s = items[i]
        if s then return s.k end
      end
    elseif m == Option then
      local done = x == None
      return function()
        if not done then done = true; return x[1] end
      end
    elseif m and m.__next then
      return function()
        local o = m.__next(x)
        if o ~= None then return o[1] end
      end
    elseif m and rawget(m, "into_iter") then
      return R.iter(m.into_iter(x))
    end
  end
  panic("this value cannot be iterated")
end
local iter = R.iter
local function listOf(it)
  local t, n = {}, 0
  for v in iter(it) do n = n + 1; t[n] = v end
  return t, n
end
local I = {}  -- the methods of iterators (a Vec or a Range takes them too)
function I.iter(x) return iterOf(iter(x)) end
I.iter_mut, I.into_iter, I.by_ref, I.cloned, I.copied = I.iter, I.iter, function(x) return x end, I.iter, I.iter
function I.map(x, f)
  local nx = iter(x)
  return iterOf(function()
    local v = nx()
    if v ~= nil then return f(v) end
  end)
end
function I.filter(x, f)
  local nx = iter(x)
  return iterOf(function()
    while true do
      local v = nx()
      if v == nil then return nil end
      if f(v) then return v end
    end
  end)
end
function I.filter_map(x, f)
  local nx = iter(x)
  return iterOf(function()
    while true do
      local v = nx()
      if v == nil then return nil end
      local r = f(v)
      if r ~= None then return r[1] end
    end
  end)
end
function I.enumerate(x)
  local nx, i = iter(x), -1
  return iterOf(function()
    local v = nx()
    if v == nil then return nil end
    i = i + 1
    return setmt({ i, v }, Tuple)
  end)
end
function I.zip(x, y)
  local a, b = iter(x), iter(y)
  return iterOf(function()
    local p = a()
    if p == nil then return nil end
    local q = b()
    if q == nil then return nil end
    return setmt({ p, q }, Tuple)
  end)
end
function I.chain(x, y)
  local a, b = iter(x), iter(y)
  local first = true
  return iterOf(function()
    if first then
      local v = a()
      if v ~= nil then return v end
      first = false
    end
    return b()
  end)
end
function I.rev(x)
  if getmt(x) == Range then
    local a, b = x.a, x.b
    if type_(a) == "number" then
      if x.incl then b = b + 1 end
      local i = b
      return iterOf(function()
        i = i - 1
        if i >= a then return i end
      end)
    end
  end
  local t, n = listOf(x)
  local i = n + 1
  return iterOf(function()
    i = i - 1
    if i >= 1 then return t[i] end
  end)
end
function I.take(x, c)
  local nx, i = iter(x), 0
  return iterOf(function()
    if i >= c then return nil end
    i = i + 1
    return nx()
  end)
end
function I.skip(x, c)
  local nx, done = iter(x), false
  return iterOf(function()
    if not done then
      done = true
      for _ = 1, c do if nx() == nil then return nil end end
    end
    return nx()
  end)
end
function I.step_by(x, s)
  local nx, first = iter(x), true
  return iterOf(function()
    if first then first = false; return nx() end
    for _ = 1, s - 1 do if nx() == nil then return nil end end
    return nx()
  end)
end
function I.take_while(x, f)
  local nx, done = iter(x), false
  return iterOf(function()
    if done then return nil end
    local v = nx()
    if v == nil or not f(v) then done = true; return nil end
    return v
  end)
end
function I.skip_while(x, f)
  local nx, go = iter(x), false
  return iterOf(function()
    while true do
      local v = nx()
      if v == nil then return nil end
      if go or not f(v) then go = true; return v end
    end
  end)
end
function I.flat_map(x, f)
  local nx, cur = iter(x), nil
  return iterOf(function()
    while true do
      if cur then
        local v = cur()
        if v ~= nil then return v end
      end
      local o = nx()
      if o == nil then return nil end
      cur = iter(f(o))
    end
  end)
end
function I.flatten(x) return I.flat_map(x, function(v) return v end) end
function I.inspect(x, f)
  local nx = iter(x)
  return iterOf(function()
    local v = nx()
    if v ~= nil then f(v) end
    return v
  end)
end
function I.peekable(x)
  local nx = iter(x)
  local it
  local buffered, has = nil, false
  it = iterOf(function()
    if has then
      has = false
      return buffered
    end
    return nx()
  end)
  it.peekFn = function()
    if not has then buffered = nx(); has = true end
    if buffered == nil then return None end
    return Some(buffered)
  end
  return it
end
function Iter.peek(it) return it.peekFn() end
function I.next(x)
  local v = x.f and x.f() or iter(x)()
  if v == nil then return None end
  return Some(v)
end
function I.nth(x, n)
  local nx = iter(x)
  for _ = 1, n do if nx() == nil then return None end end
  local v = nx()
  if v == nil then return None end
  return Some(v)
end
function I.last(x)
  local l
  for v in iter(x) do l = v end
  if l == nil then return None end
  return Some(l)
end
function I.count(x) local c = 0; for _ in iter(x) do c = c + 1 end return c end
function I.sum(x, target)
  local s = (target == "f64" or target == "f32") and 0.0 or 0
  for v in iter(x) do s = s + d(v) end
  return s
end
function I.product(x, target)
  local s = (target == "f64" or target == "f32") and 1.0 or 1
  for v in iter(x) do s = s * d(v) end
  return s
end
function I.fold(x, init, f)
  local a = init
  for v in iter(x) do a = f(a, v) end
  return a
end
function I.reduce(x, f)
  local a
  for v in iter(x) do if a == nil then a = v else a = f(a, v) end end
  if a == nil then return None end
  return Some(a)
end
function I.for_each(x, f) for v in iter(x) do f(v) end return unit end
function I.any(x, f) for v in iter(x) do if f(v) then return true end end return false end
function I.all(x, f) for v in iter(x) do if not f(v) then return false end end return true end
function I.find(x, f) for v in iter(x) do if f(v) then return Some(v) end end return None end
function I.find_map(x, f) for v in iter(x) do local r = f(v); if r ~= None then return r end end return None end
function I.position(x, f)
  local i = 0
  for v in iter(x) do
    if f(v) then return Some(i) end
    i = i + 1
  end
  return None
end
function I.max(x)
  local b
  for v in iter(x) do if b == nil or cmp(v, b) >= 0 then b = v end end
  if b == nil then return None end
  return Some(b)
end
function I.min(x)
  local b
  for v in iter(x) do if b == nil or cmp(v, b) < 0 then b = v end end
  if b == nil then return None end
  return Some(b)
end
function I.max_by_key(x, f)
  local b, bk
  for v in iter(x) do
    local k = f(v)
    if b == nil or cmp(k, bk) >= 0 then b, bk = v, k end
  end
  if b == nil then return None end
  return Some(b)
end
function I.min_by_key(x, f)
  local b, bk
  for v in iter(x) do
    local k = f(v)
    if b == nil or cmp(k, bk) < 0 then b, bk = v, k end
  end
  if b == nil then return None end
  return Some(b)
end
function I.max_by(x, f)
  local b
  for v in iter(x) do if b == nil or f(v, b).ord >= 0 then b = v end end
  if b == nil then return None end
  return Some(b)
end
function I.min_by(x, f)
  local b
  for v in iter(x) do if b == nil or f(v, b).ord < 0 then b = v end end
  if b == nil then return None end
  return Some(b)
end
function I.partition(x, f)
  local a, b = {}, {}
  for v in iter(x) do if f(v) then a[#a + 1] = v else b[#b + 1] = v end end
  return setmt({ vecn(a, #a), vecn(b, #b) }, Tuple)
end
function I.unzip(x)
  local a, b = {}, {}
  for v in iter(x) do a[#a + 1] = v[1]; b[#b + 1] = v[2] end
  return setmt({ vecn(a, #a), vecn(b, #b) }, Tuple)
end
function I.collect(x, target)
  if target == "String" then
    local p = {}
    for v in iter(x) do p[#p + 1] = d(v) end
    return concat(p)
  end
  if target == "HashMap" or target == "BTreeMap" then
    local m = newMap(Map, target == "BTreeMap")
    for v in iter(x) do mapPut(m, v[1], v[2]) end
    return m
  end
  if target == "HashSet" or target == "BTreeSet" then
    local m = newMap(Set, target == "BTreeSet")
    for v in iter(x) do mapPut(m, v, true) end
    return m
  end
  if target == "Result" or target == "Option" then
    local t, n = {}, 0
    for v in iter(x) do
      if R.isFail(v) then return v end
      n = n + 1
      t[n] = v[1]
    end
    return target == "Result" and Ok(vecn(t, n)) or Some(vecn(t, n))
  end
  local t, n = listOf(x)
  return vecn(t, n)
end
function I.sorted(x) local t, n = listOf(x); local v = vecn(t, n); Vec.sort(v); return v end
for _, c in ipairs{ Iter, Range } do
  for k, f in pairs(I) do c[k] = f end
end
function Range.contains(r, x)
  x = d(x)
  if r.a ~= nil and x < r.a then return false end
  if r.b == nil then return true end
  if r.incl then return x <= r.b end
  return x < r.b
end
function Range.len(r) return math.max(0, r.b - r.a + (r.incl and 1 or 0)) end
function Range.is_empty(r) return Range.len(r) == 0 end

-- ---- Vec ----
for _, n in ipairs{ "iter", "iter_mut", "into_iter", "map", "filter", "fold", "sum" } do Vec[n] = I[n] end
Vec.into_iter, Vec.iter = I.iter, I.iter
function Vec.iter_mut(v)
  local i = 0
  return iterOf(function()
    i = i + 1
    if i > v.n then return nil end
    local x = v[i]
    if type_(x) == "table" and getmt(x) ~= Option and getmt(x) ~= Result then return x end
    local at = i
    return setmt({ get = function() return v[at] end, set = function(y) v[at] = y end }, Ref)
  end)
end
function R.idx(v, i)
  v = d(v)
  local t = type_(v)
  if t == "table" then
    local m = getmt(v)
    if m == Vec then
      if mtype(i) == "integer" then
        local x = v[i + 1]
        if x == nil or i < 0 then panic("index out of bounds: the len is " .. v.n .. " but the index is " .. i) end
        return x
      end
      i = d(i)
      if getmt(i) == Range then
        local a, b = i.a or 0, i.b or v.n
        if i.incl then b = b + 1 end
        if a > b then panic("slice index starts at " .. a .. " but ends at " .. b) end
        if b > v.n then panic("range end index " .. b .. " out of range for slice of length " .. v.n) end
        local o = {}
        for k = a + 1, b do o[k - a] = v[k] end
        return vecn(o, b - a)
      end
      return R.idx(v, i)
    elseif m == Map then
      local s = v.h[mapKey(i)]
      if not s then panic("key not found in map") end
      return s.v
    elseif m and m.__uindex then return m.__uindex(v, i)
    end
  elseif t == "string" then
    i = d(i)
    if getmt(i) == Range then
      local a, b = i.a or 0, i.b or #v
      if i.incl then b = b + 1 end
      if b > #v then panic("byte index " .. b .. " is out of bounds of `" .. v .. "`") end
      return v:sub(a + 1, b)
    end
  end
  panic("cannot index this value")
end
function R.setidx(v, i, x)
  v = d(v)
  if getmt(v) == Vec then
    if i < 0 or i >= v.n then panic("index out of bounds: the len is " .. v.n .. " but the index is " .. i) end
    v[i + 1] = x
    return
  end
  if getmt(v) == Map then mapPut(v, i, x); return end
  local m = getmt(v)
  if m and m.index_mut then R.setd(m.index_mut(v, i), x); return end
  panic("cannot assign to this index")
end
function Vec.len(v) return v.n end
function Vec.is_empty(v) return v.n == 0 end
function Vec.push(v, x) v.n = v.n + 1; v[v.n] = x; return unit end
function Vec.pop(v)
  if v.n == 0 then return None end
  local x = v[v.n]
  v[v.n] = nil
  v.n = v.n - 1
  return Some(x)
end
function Vec.clear(v) for i = v.n, 1, -1 do v[i] = nil end v.n = 0; return unit end
function Vec.insert(v, i, x)
  if i > v.n then panic("insertion index (is " .. i .. ") should be <= len (is " .. v.n .. ")") end
  table.insert(v, i + 1, x)
  v.n = v.n + 1
  return unit
end
function Vec.remove(v, i)
  if i >= v.n then panic("removal index (is " .. i .. ") should be < len (is " .. v.n .. ")") end
  v.n = v.n - 1
  return table.remove(v, i + 1)
end
function Vec.swap_remove(v, i)
  local x = v[i + 1]
  v[i + 1] = v[v.n]
  v[v.n] = nil
  v.n = v.n - 1
  return x
end
function Vec.get(v, i)
  if getmt(i) == Range then
    if (i.b or v.n) > v.n then return None end
    return Some(R.idx(v, i))
  end
  local x = v[i + 1]
  if x == nil or i < 0 then return None end
  return Some(x)
end
Vec.get_mut = Vec.get
function Vec.first(v) if v.n == 0 then return None end return Some(v[1]) end
function Vec.last(v) if v.n == 0 then return None end return Some(v[v.n]) end
Vec.last_mut, Vec.first_mut = Vec.last, Vec.first
function Vec.contains(v, x)
  x = d(x)
  for i = 1, v.n do if deepEq(v[i], x) then return true end end
  return false
end
function Vec.extend(v, o) for x in iter(o) do Vec.push(v, x) end return unit end
Vec.extend_from_slice = Vec.extend
function Vec.append(v, o) Vec.extend(v, o); Vec.clear(o); return unit end
function Vec.reverse(v)
  local i, j = 1, v.n
  while i < j do v[i], v[j] = v[j], v[i]; i = i + 1; j = j - 1 end
  return unit
end
function Vec.swap(v, a, b) v[a + 1], v[b + 1] = v[b + 1], v[a + 1]; return unit end
local function sortWith(v, less)
  local a, b, n, w = {}, {}, v.n, 1
  for i = 1, n do a[i] = v[i] end
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
  for i = 1, n do v[i] = a[i] end
  return unit
end
function Vec.sort(v) return sortWith(v, function(x, y) return cmp(x, y) < 0 end) end
Vec.sort_unstable = Vec.sort
function Vec.sort_by(v, f) return sortWith(v, function(x, y) return f(x, y).ord < 0 end) end
Vec.sort_unstable_by = Vec.sort_by
function Vec.sort_by_key(v, f) return sortWith(v, function(x, y) return cmp(f(x), f(y)) < 0 end) end
Vec.sort_unstable_by_key = Vec.sort_by_key
function Vec.dedup(v)
  local o, n = {}, 0
  for i = 1, v.n do
    if n == 0 or not deepEq(o[n], v[i]) then n = n + 1; o[n] = v[i] end
  end
  for i = 1, v.n do v[i] = o[i] end
  v.n = n
  return unit
end
function Vec.retain(v, f)
  local n = 0
  local total = v.n
  for i = 1, total do
    local x = v[i]
    if f(x) then n = n + 1; v[n] = x end
  end
  for i = n + 1, total do v[i] = nil end
  v.n = n
  return unit
end
function Vec.truncate(v, n)
  for i = n + 1, v.n do v[i] = nil end
  if n < v.n then v.n = n end
  return unit
end
function Vec.join(v, sep)
  local p = {}
  for i = 1, v.n do p[i] = R.disp(v[i]) end
  return concat(p, sep or "")
end
function Vec.concat(v)
  if type_(v[1]) == "table" then
    local o, n = {}, 0
    for i = 1, v.n do for j = 1, v[i].n do n = n + 1; o[n] = v[i][j] end end
    return vecn(o, n)
  end
  local p = {}
  for i = 1, v.n do p[i] = R.disp(v[i]) end
  return concat(p)
end
function Vec.to_vec(v) return R.clone(v) end
Vec.to_owned, Vec.as_slice, Vec.as_mut_slice = Vec.to_vec, function(v) return v end, function(v) return v end
function Vec.windows(v, k)
  local i = 0
  return iterOf(function()
    i = i + 1
    if i + k - 1 > v.n then return nil end
    local o = {}
    for j = 0, k - 1 do o[j + 1] = v[i + j] end
    return vecn(o, k)
  end)
end
function Vec.chunks(v, k)
  local i = 1
  return iterOf(function()
    if i > v.n then return nil end
    local o, c = {}, 0
    for j = i, math.min(i + k - 1, v.n) do c = c + 1; o[c] = v[j] end
    i = i + k
    return vecn(o, c)
  end)
end
function Vec.binary_search(v, x)
  local a, b = 0, v.n
  while a < b do
    local m = (a + b) // 2
    local c = cmp(v[m + 1], x)
    if c == 0 then return Ok(m) end
    if c < 0 then a = m + 1 else b = m end
  end
  return Err(a)
end
function Vec.split_at(v, i) return setmt({ R.idx(v, R.range(0, i)), R.idx(v, R.range(i, v.n)) }, Tuple) end
function Vec.capacity(v) return v.n end
function Vec.reserve() return unit end
function Vec.push_back(v, x) return Vec.push(v, x) end
function Vec.pop_back(v) return Vec.pop(v) end
function Vec.push_front(v, x) return Vec.insert(v, 0, x) end
function Vec.pop_front(v) if v.n == 0 then return None end return Some(Vec.remove(v, 0)) end
function Vec.front(v) return Vec.first(v) end
function Vec.back(v) return Vec.last(v) end
function Vec.peek(v)
  -- a BinaryHeap keeps its items sorted
  return Vec.last(v)
end
function Vec.fill(v, x) for i = 1, v.n do v[i] = x end return unit end
function Vec.iter_rev(v) return I.rev(v) end
for k, f in pairs(I) do if Vec[k] == nil then Vec[k] = f end end
Vec.into_iter = I.iter
Vec.last, Vec.count = Vec.last, function(v) return v.n end
-- a heap: pop gives the largest
local Heap = setmt({ __name = "BinaryHeap" }, { __index = Vec })
Heap.__index = Heap
function Heap.push(v, x)
  Vec.push(v, x)
  Vec.sort(v)
  return unit
end
function Heap.into_sorted_vec(v) return setmt(v, Vec) end

-- ---- Map, Set ----
function Map.insert(m, k, v)
  local old, had = mapPut(m, k, v)
  if had then return Some(old) end
  return None
end
function Map.get(m, k)
  local s = m.h[mapKey(k)]
  if s then return Some(s.v) end
  return None
end
Map.get_mut = function(m, k)
  local s = m.h[mapKey(k)]
  if not s then return None end
  if type_(s.v) == "table" then return Some(s.v) end
  return Some(setmt({ get = function() return s.v end, set = function(v) s.v = v end }, Ref))
end
function Map.contains_key(m, k) return m.h[mapKey(k)] ~= nil end
function Map.remove(m, k)
  local key = mapKey(k)
  local s = m.h[key]
  if not s then return None end
  m.h[key] = nil
  m.n = m.n - 1
  return Some(s.v)
end
function Map.len(m) return m.n end
function Map.is_empty(m) return m.n == 0 end
function Map.clear(m) m.h = {}; m.n = 0; return unit end
function Map.keys(m)
  local items, i = entries(m), 0
  return iterOf(function()
    i = i + 1
    return items[i] and items[i].k
  end)
end
function Map.values(m)
  local items, i = entries(m), 0
  return iterOf(function()
    i = i + 1
    return items[i] and items[i].v
  end)
end
function Map.values_mut(m)
  local items, i = entries(m), 0
  return iterOf(function()
    i = i + 1
    local s = items[i]
    if not s then return nil end
    if type_(s.v) == "table" then return s.v end
    return setmt({ get = function() return s.v end, set = function(v) s.v = v end }, Ref)
  end)
end
function Map.iter(m)
  local items, i = entries(m), 0
  return iterOf(function()
    i = i + 1
    local s = items[i]
    if s then return setmt({ s.k, s.v }, Tuple) end
  end)
end
Map.into_iter = Map.iter
function Map.iter_mut(m)
  local items, i = entries(m), 0
  return iterOf(function()
    i = i + 1
    local s = items[i]
    if not s then return nil end
    local v = s.v
    if type_(v) ~= "table" then v = setmt({ get = function() return s.v end, set = function(x) s.v = x end }, Ref) end
    return setmt({ s.k, v }, Tuple)
  end)
end
local Entry = { __name = "Entry" }
Entry.__index = Entry
function Map.entry(m, k) return setmt({ m = m, k = k }, Entry) end
local function entrySlot(e, makeV)
  local key = mapKey(e.k)
  local s = e.m.h[key]
  if not s then
    mapPut(e.m, e.k, makeV())
    s = e.m.h[key]
  end
  if type_(s.v) == "table" then return s.v end
  return setmt({ get = function() return s.v end, set = function(v) s.v = v end }, Ref)
end
function Entry.or_insert(e, v) return entrySlot(e, function() return v end) end
function Entry.or_insert_with(e, f) return entrySlot(e, f) end
function Entry.or_default(e) return entrySlot(e, function() return 0 end) end
function Entry.and_modify(e, f)
  local s = e.m.h[mapKey(e.k)]
  if s then
    if type_(s.v) == "table" then f(s.v)
    else f(setmt({ get = function() return s.v end, set = function(v) s.v = v end }, Ref)) end
  end
  return e
end
for k, f in pairs(I) do if Map[k] == nil and k ~= "iter" and k ~= "into_iter" then Map[k] = f end end
function Set.insert(s, x)
  local _, had = mapPut(s, x, true)
  return not had
end
function Set.contains(s, x) return s.h[mapKey(x)] ~= nil end
function Set.remove(s, x)
  local key = mapKey(x)
  if not s.h[key] then return false end
  s.h[key] = nil
  s.n = s.n - 1
  return true
end
function Set.len(s) return s.n end
function Set.is_empty(s) return s.n == 0 end
function Set.clear(s) s.h = {}; s.n = 0; return unit end
function Set.iter(s) return iterOf(iter(s)) end
Set.into_iter = Set.iter
function Set.union(a, b)
  local r = newMap(Set, a.sorted)
  for x in iter(a) do mapPut(r, x, true) end
  for x in iter(b) do mapPut(r, x, true) end
  return r
end
function Set.intersection(a, b)
  local r = newMap(Set, a.sorted)
  for x in iter(a) do if b.h[mapKey(x)] then mapPut(r, x, true) end end
  return r
end
function Set.difference(a, b)
  local r = newMap(Set, a.sorted)
  for x in iter(a) do if not b.h[mapKey(x)] then mapPut(r, x, true) end end
  return r
end
function Set.is_subset(a, b) for x in iter(a) do if not b.h[mapKey(x)] then return false end end return true end
for k, f in pairs(I) do if Set[k] == nil then Set[k] = f end end

-- ---- Option, Result ----
local function unwrapFail(o, msg)
  if o == None then panic(msg or "called `Option::unwrap()` on a `None` value") end
  panic((msg or "called `Result::unwrap()` on an `Err` value") .. ": " .. R.dbg(o[1]))
end
function Option.unwrap(o) if o == None then unwrapFail(o) end return o[1] end
function Result.unwrap(o) if o.tag == "Err" then unwrapFail(o) end return o[1] end
function Option.expect(o, m) if o == None then panic(m) end return o[1] end
function Result.expect(o, m) if o.tag == "Err" then unwrapFail(o, m) end return o[1] end
function Result.unwrap_err(o) if o.tag ~= "Err" then panic("called `Result::unwrap_err()` on an `Ok` value: " .. R.dbg(o[1])) end return o[1] end
function Option.unwrap_or(o, v) if o == None then return v end return o[1] end
function Result.unwrap_or(o, v) if o.tag == "Err" then return v end return o[1] end
function Option.unwrap_or_else(o, f) if o == None then return f() end return o[1] end
function Result.unwrap_or_else(o, f) if o.tag == "Err" then return f(o[1]) end return o[1] end
function Option.unwrap_or_default(o) if o == None then return 0 end return o[1] end
Result.unwrap_or_default = function(o) if o.tag == "Err" then return 0 end return o[1] end
function Option.is_some(o) return o ~= None end
function Option.is_none(o) return o == None end
function Result.is_ok(o) return o.tag == "Ok" end
function Result.is_err(o) return o.tag == "Err" end
function Option.map(o, f) if o == None then return None end return Some(f(o[1])) end
function Result.map(o, f) if o.tag == "Err" then return o end return Ok(f(o[1])) end
function Result.map_err(o, f) if o.tag == "Err" then return Err(f(o[1])) end return o end
function Option.map_or(o, v, f) if o == None then return v end return f(o[1]) end
Result.map_or = function(o, v, f) if o.tag == "Err" then return v end return f(o[1]) end
function Option.map_or_else(o, g, f) if o == None then return g() end return f(o[1]) end
function Option.and_then(o, f) if o == None then return None end return f(o[1]) end
function Result.and_then(o, f) if o.tag == "Err" then return o end return f(o[1]) end
function Option.or_(o, x) if o == None then return x end return o end
Option["or"] = Option.or_
function Option.or_else(o, f) if o == None then return f() end return o end
Result.or_else = function(o, f) if o.tag == "Err" then return f(o[1]) end return o end
function Option.ok_or(o, e) if o == None then return Err(e) end return Ok(o[1]) end
function Option.ok_or_else(o, f) if o == None then return Err(f()) end return Ok(o[1]) end
function Result.ok(o) if o.tag == "Err" then return None end return Some(o[1]) end
function Result.err(o) if o.tag == "Err" then return Some(o[1]) end return None end
function Option.filter(o, f) if o ~= None and f(o[1]) then return o end return None end
function Option.cloned(o) return R.clone(o) end
Option.copied = Option.cloned
local same = function(o) return o end
Option.as_ref, Option.as_mut, Option.as_deref, Option.as_deref_mut = same, same, same, same
Result.as_ref, Result.as_mut, Result.cloned = same, same, same
function Option.iter(o) return iterOf(iter(o)) end
function Option.unzip(o) if o == None then return setmt({ None, None }, Tuple) end return setmt({ Some(o[1][1]), Some(o[1][2]) }, Tuple) end
function Ordering.reverse(o) return ordOf(-o.ord) end
function Ordering.then_with(o, f) if o.ord ~= 0 then return o end return f() end
Ordering["then"] = function(o, x) if o.ord ~= 0 then return o end return x end
function Ordering.is_lt(o) return o.ord < 0 end
function Ordering.is_gt(o) return o.ord > 0 end
function Ordering.is_eq(o) return o.ord == 0 end

-- ---- String, char ----
local S = {}
function S.len(s) return #s end
function S.is_empty(s) return s == "" end
S.to_string, S.to_owned, S.as_str, S.as_ref, S.clone, S.into, S.borrow, S.as_bytes_ = same, same, same, same, same, same, same, same
function S.as_bytes(s) return R.bytes(s) end
S.bytes = function(s) return iterOf(iter(R.bytes(s))) end
S.into_bytes = S.as_bytes
function S.chars(s)
  local i, n = 1, #s
  return iterOf(function()
    if i > n then return nil end
    local e = utf8.offset(s, 2, i) or n + 1
    local c = s:sub(i, e - 1)
    i = e
    return c
  end)
end
function S.char_indices(s)
  local i, n = 1, #s
  return iterOf(function()
    if i > n then return nil end
    local e = utf8.offset(s, 2, i) or n + 1
    local c = s:sub(i, e - 1)
    local at = i - 1
    i = e
    return setmt({ at, c }, Tuple)
  end)
end
function S.to_uppercase(s) return s:upper() end
function S.to_lowercase(s) return s:lower() end
S.to_ascii_uppercase, S.to_ascii_lowercase = S.to_uppercase, S.to_lowercase
function S.trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function S.trim_start(s) return (s:gsub("^%s+", "")) end
function S.trim_end(s) return (s:gsub("%s+$", "")) end
local function matcher(p)
  p = d(p)
  if type_(p) == "function" then return function(c) return p(c) end end
  if getmt(p) == Vec then return function(c) return Vec.contains(p, c) end end
  return nil
end
function S.contains(s, p)
  local m = matcher(p)
  if m then for c in iter(S.chars(s)) do if m(c) then return true end end return false end
  return s:find(d(p), 1, true) ~= nil
end
function S.starts_with(s, p)
  local m = matcher(p)
  if m then return s ~= "" and m(s:sub(1, (utf8.offset(s, 2) or 2) - 1)) end
  p = d(p)
  return s:sub(1, #p) == p
end
function S.ends_with(s, p) p = d(p); return p == "" or s:sub(-#p) == p end
function S.find(s, p)
  local m = matcher(p)
  if m then
    for pr in iter(S.char_indices(s)) do if m(pr[2]) then return Some(pr[1]) end end
    return None
  end
  local a = s:find(d(p), 1, true)
  if a then return Some(a - 1) end
  return None
end
function S.rfind(s, p)
  p = d(p)
  local last, i = nil, 1
  while true do
    local a = s:find(p, i, true)
    if not a then break end
    last = a - 1
    i = a + 1
  end
  if last then return Some(last) end
  return None
end
function S.replace(s, a, b)
  a = d(a)
  if a == "" then return s end
  local o, i = {}, 1
  while true do
    local x, y = s:find(a, i, true)
    if not x then break end
    o[#o + 1] = s:sub(i, x - 1)
    o[#o + 1] = b
    i = y + 1
  end
  o[#o + 1] = s:sub(i)
  return concat(o)
end
S.replacen = function(s, a, b, n)
  local o, i, c = {}, 1, 0
  while c < n do
    local x, y = s:find(a, i, true)
    if not x then break end
    o[#o + 1] = s:sub(i, x - 1)
    o[#o + 1] = b
    i = y + 1
    c = c + 1
  end
  o[#o + 1] = s:sub(i)
  return concat(o)
end
local function splitList(s, p)
  p = d(p)
  local o = {}
  local m = matcher(p)
  if m then
    local cur = {}
    for c in iter(S.chars(s)) do
      if m(c) then o[#o + 1] = concat(cur); cur = {}
      else cur[#cur + 1] = c end
    end
    o[#o + 1] = concat(cur)
    return o
  end
  if p == "" then
    o[1] = ""
    for c in iter(S.chars(s)) do o[#o + 1] = c end
    o[#o + 1] = ""
    return o
  end
  local i = 1
  while true do
    local a, b = s:find(p, i, true)
    if not a then break end
    o[#o + 1] = s:sub(i, a - 1)
    i = b + 1
  end
  o[#o + 1] = s:sub(i)
  return o
end
function S.split(s, p) local o = splitList(s, p); return iterOf(iter(vecn(o, #o))) end
function S.split_whitespace(s)
  local nx = s:gmatch("%S+")
  return iterOf(function() return nx() end)
end
S.split_ascii_whitespace = S.split_whitespace
function S.splitn(s, n, p)
  p = d(p)
  local o, i = {}, 1
  while #o < n - 1 do
    local a, b = s:find(p, i, true)
    if not a then break end
    o[#o + 1] = s:sub(i, a - 1)
    i = b + 1
  end
  o[#o + 1] = s:sub(i)
  return iterOf(iter(vecn(o, #o)))
end
function S.split_once(s, p)
  p = d(p)
  local a, b = s:find(p, 1, true)
  if not a then return None end
  return Some(setmt({ s:sub(1, a - 1), s:sub(b + 1) }, Tuple))
end
function S.lines(s)
  local o = {}
  for line in (s:sub(-1) == "\n" and s or (s == "" and s or s .. "\n")):gmatch("(.-)\r?\n") do o[#o + 1] = line end
  return iterOf(iter(vecn(o, #o)))
end
function S.strip_prefix(s, p) p = d(p); if s:sub(1, #p) == p then return Some(s:sub(#p + 1)) end return None end
function S.strip_suffix(s, p) p = d(p); if p == "" or s:sub(-#p) == p then return Some(s:sub(1, -#p - 1)) end return None end
function S.trim_matches(s, c) c = d(c):gsub("[%^%]%-%%]", "%%%0"); return (s:gsub("^[" .. c .. "]+", ""):gsub("[" .. c .. "]+$", "")) end
S.trim_start_matches = function(s, c) c = d(c); while c ~= "" and s:sub(1, #c) == c do s = s:sub(#c + 1) end return s end
S.trim_end_matches = function(s, c) c = d(c); while c ~= "" and s:sub(-#c) == c do s = s:sub(1, -#c - 1) end return s end
S.repeat_ = function(s, n) return s:rep(n) end
S["repeat"] = S.repeat_
function S.eq_ignore_ascii_case(a, b) return a:lower() == d(b):lower() end
function S.get(s, r)
  local a, b = r.a or 0, r.b or #s
  if r.incl then b = b + 1 end
  if b > #s then return None end
  return Some(s:sub(a + 1, b))
end
function S.parse(s, target)
  if target == "f64" or target == "f32" then
    local v = s:find("^[+-]?%d*%.?%d*[eE]?[+-]?%d*$") and s ~= "" and tonumber(s)
    if not v then return Err(R.simpleErr("invalid float literal")) end
    return Ok(v + 0.0)
  end
  if target == "bool" then
    if s == "true" then return Ok(true) elseif s == "false" then return Ok(false) end
    return Err(R.simpleErr("provided string was not `true` or `false`"))
  end
  if target == "char" then
    if utf8.len(s) == 1 then return Ok(s) end
    return Err(R.simpleErr("too many characters in string"))
  end
  if target == "String" then return Ok(s) end
  if s == "" then return Err(R.simpleErr("cannot parse integer from empty string")) end
  if not s:find("^[+-]?%d+$") then return Err(R.simpleErr("invalid digit found in string")) end
  local v = math.tointeger(tonumber((s:gsub("^%+", ""))))
  local l = LIMITS[target or "i32"]
  if not v or (l and (v > l[2] or v < l[1])) then return Err(R.simpleErr("number too large to fit in target type")) end
  return Ok(v)
end
-- what a char can do; a char is a string of one letter
function S.is_alphabetic(c) return c:find("^[%a\128-\255]") ~= nil end
function S.is_numeric(c) return c:find("^%d") ~= nil end
S.is_ascii_digit = S.is_numeric
function S.is_digit(c, base)
  local v = tonumber(c, base)
  return v ~= nil
end
function S.to_digit(c, base)
  local v = tonumber(c, base)
  if v then return Some(v) end
  return None
end
function S.is_alphanumeric(c) return c:find("^[%w\128-\255]") ~= nil end
function S.is_ascii_alphabetic(c) return c:find("^%a") ~= nil end
function S.is_ascii_alphanumeric(c) return c:find("^%w") ~= nil end
function S.is_whitespace(c) return c:find("^%s") ~= nil end
S.is_ascii_whitespace = S.is_whitespace
function S.is_uppercase(c) return c:find("^%u") ~= nil end
function S.is_lowercase(c) return c:find("^%l") ~= nil end
S.is_ascii_uppercase, S.is_ascii_lowercase = S.is_uppercase, S.is_lowercase
function S.is_ascii_punctuation(c) return c:find("^%p") ~= nil end
function S.is_ascii(c) return not c:find("[\128-\255]") end
function S.len_utf8(c) return #c end
function S.cmp(a, b) return ordOf(cmp(a, b)) end
S.partial_cmp = function(a, b) return Some(ordOf(cmp(a, b))) end
local SimpleErr = { __name = "Error" }
SimpleErr.__index = SimpleErr
function SimpleErr.to_string(e) return e.msg end
function R.simpleErr(m) return setmt({ msg = m }, SimpleErr) end
-- what changes a string, on the place that holds it: returns the new value and the result
local STRM = {
  push = function(s, c) return s .. d(c), unit end,
  push_str = function(s, t) return s .. d(t), unit end,
  pop = function(s)
    if s == "" then return s, None end
    local o = utf8.offset(s, -1) or #s
    return s:sub(1, o - 1), Some(s:sub(o))
  end,
  clear = function() return "", unit end,
  insert = function(s, i, c) return s:sub(1, i) .. d(c) .. s:sub(i + 1), unit end,
  insert_str = function(s, i, c) return s:sub(1, i) .. d(c) .. s:sub(i + 1), unit end,
  truncate = function(s, n) return s:sub(1, n), unit end,
  remove = function(s, i) local e = utf8.offset(s, 2, i + 1) or #s + 1; return s:sub(1, i) .. s:sub(e), s:sub(i + 1, e - 1) end,
  retain = function(s, f)
    local o = {}
    for c in iter(S.chars(s)) do if f(c) then o[#o + 1] = c end end
    return concat(o), unit
  end,
}
local OPTM = {
  take = function(o) return None, o end,
  replace = function(o, v) return Some(v), o end,
  insert = function(_, v) return Some(v), v end,
  get_or_insert_with = function(o, f)
    if o == None then local v = f(); return Some(v), v end
    return o, o[1]
  end,
}

-- numbers
local N = {}
function N.abs(x) return x < 0 and -x or x end
function N.pow(x, e)
  local r = 1
  for _ = 1, e do r = r * x end
  return r
end
function N.powi(x, e) return x ^ e end
function N.powf(x, e) return x ^ e end
function N.sqrt(x) if x < 0 then return 0 / 0 end return math.sqrt(x) end
function N.cbrt(x) return x < 0 and -((-x) ^ (1 / 3)) or x ^ (1 / 3) end
function N.floor(x) return floor(x) + 0.0 end
function N.ceil(x) return math.ceil(x) + 0.0 end
function N.round(x) return (x >= 0 and floor(x + 0.5) or -floor(-x + 0.5)) + 0.0 end
function N.trunc(x) return (x >= 0 and floor(x) or -floor(-x)) + 0.0 end
function N.fract(x) return x - (x >= 0 and floor(x) or -floor(-x)) end
function N.sin(x) return math.sin(x) end
function N.cos(x) return math.cos(x) end
function N.tan(x) return math.tan(x) end
function N.asin(x) return math.asin(x) end
function N.acos(x) return math.acos(x) end
function N.atan(x) return math.atan(x) end
function N.atan2(y, x) return math.atan(y, x) end
function N.exp(x) return math.exp(x) end
function N.ln(x) return math.log(x) end
function N.log10(x) return math.log(x, 10) end
function N.log2(x) return math.log(x, 2) end
function N.log(x, b) return math.log(x, b) end
function N.hypot(x, y) return math.sqrt(x * x + y * y) end
function N.to_radians(x) return x * math.pi / 180 end
function N.to_degrees(x) return x * 180 / math.pi end
function N.is_nan(x) return x ~= x end
function N.is_finite(x) return x == x and x ~= math.huge and x ~= -math.huge end
function N.is_infinite(x) return x == math.huge or x == -math.huge end
function N.max(a, b) b = d(b); if b > a then return b end return a end
function N.min(a, b) b = d(b); if b < a then return b end return a end
function N.clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
function N.signum(x) if x > 0 then return mtype(x) == "float" and 1.0 or 1 elseif x < 0 then return mtype(x) == "float" and -1.0 or -1 end return x end
function N.is_positive(x) return x > 0 end
function N.is_negative(x) return x < 0 end
function N.rem_euclid(a, b) local r = math.fmod(a, b); if r < 0 then r = r + math.abs(b) end return r end
function N.div_euclid(a, b) return (a - N.rem_euclid(a, b)) // b end
function N.abs_diff(a, b) return a > b and a - b or b - a end
function N.count_ones(x) local c = 0; while x ~= 0 do c = c + (x & 1); x = x >> 1 end return c end
function N.leading_zeros(x) local c = 0; for i = 31, 0, -1 do if x & (1 << i) ~= 0 then break end c = c + 1 end return c end
function N.trailing_zeros(x) if x == 0 then return 32 end local c = 0; while x & 1 == 0 do c = c + 1; x = x >> 1 end return c end
function N.is_power_of_two(x) return x > 0 and x & (x - 1) == 0 end
function N.wrapping_add(a, b) return a + b end
function N.wrapping_sub(a, b) return a - b end
function N.wrapping_mul(a, b) return a * b end
function N.checked_add(a, b) local r = a + b; if (a ~ r) & (b ~ r) < 0 or r > 2147483647 and false then return None end return Some(r) end
function N.checked_sub(a, b) return Some(a - b) end
function N.checked_mul(a, b) local r = a * b; if a ~= 0 and r // a ~= b then return None end return Some(r) end
function N.checked_div(a, b) if b == 0 then return None end return Some(R.div(a, b)) end
function N.saturating_sub(a, b) local r = a - b; return r < 0 and 0 or r end
function N.saturating_add(a, b) return a + b end
function N.cmp(a, b) return ordOf(cmp(a, b)) end
function N.partial_cmp(a, b) return Some(ordOf(cmp(a, b))) end
function N.total_cmp(a, b) return ordOf(cmp(a, b)) end
function N.to_string(x) return R.disp(x) end
function N.clone(x) return x end
N.into, N.as_ref, N.to_owned = N.clone, N.clone, N.clone
function N.is_ascii_digit(b) return b >= 48 and b <= 57 end
function N.is_ascii_alphabetic(b) return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) end
function N.then_some(b, v) if b then return Some(v) end return None end
N["then"] = function(b, f) if b then return Some(f()) end return None end
function R.typeFn(t, n)
  local f = (t == "str" or t == "char") and S[n] or N[n]
  if t == "char" and n == "from" then return function(x) return R.toChar(x) end end
  if t == "char" and n == "from_u32" then return function(x) return Some(utf8.char(x)) end end
  if t == "char" and n == "from_digit" then return function(x, base) return Some(("0123456789abcdefghijklmnopqrstuvwxyz"):sub(x + 1, x + 1)) end end
  if n == "from" then return function(x) if t == "f64" or t == "f32" then return x + 0.0 end return R.toInt(x, 64, true) end end
  if n == "from_str_radix" then
    return function(s, base)
      local v = tonumber(s, base)
      if v then return Ok(v) end
      return Err(R.simpleErr("invalid digit found in string"))
    end
  end
  if not f then panic("unknown function " .. t .. "::" .. n) end
  return f
end

-- ---- calling a method by its name ----
local function userMethod(x, n)
  local t = type_(x)
  local ext
  if t == "number" then ext = extTypes[mtype(x) == "integer" and "i32" or "f64"] or extTypes.i64 or extTypes.u32 or extTypes.f32
  elseif t == "string" then ext = extTypes.String or extTypes.str
  elseif t == "boolean" then ext = extTypes.bool
  elseif getmt(x) == Vec then ext = extTypes.Vec end
  return ext and ext[n]
end
function R.m(o, n, ...)
  local t = type_(o)
  if t == "table" then
    local m = getmt(o)
    if m == Ref then
      return R.m(o.get(), n, ...)
    end
    if m == Cell then
      if n == "borrow" or n == "get" then
        local v = o.v
        return v
      end
      if n == "borrow_mut" or n == "lock" or n == "write" or n == "read" then
        local self = o
        if type_(self.v) == "table" then
          if n == "lock" or n == "write" or n == "read" then return Ok(self.v) end
          return self.v
        end
        if n == "lock" or n == "write" or n == "read" then return Ok(self) end
        return self
      end
      if n == "set" then o.v = (...); return unit end
      if n == "replace" then local old = o.v; o.v = (...); return old end
      if n == "take" then local old = o.v; o.v = 0; return old end
      if n == "into_inner" then return o.v end
      return R.m(o.v, n, ...)
    end
    local f = m and m[n]
    if f then return f(o, ...) end
    if m and m.__tuple and o[1] ~= nil then
      local g = rawget(m, n)
      if g then return g(o, ...) end
    end
    if n == "to_string" then return R.disp(o) end
    if n == "cmp" then return ordOf(cmp(o, (...))) end
    if n == "partial_cmp" then return Some(ordOf(cmp(o, (...)))) end
    if n == "eq" then return deepEq(o, (...)) end
    if n == "ne" then return not deepEq(o, (...)) end
    if n == "clone" then return R.clone(o) end
    if n == "into" or n == "borrow" or n == "as_ref" or n == "as_mut" or n == "unwrap_or_clone" or n == "deref" or n == "to_owned" then return o end
    if n == "max" then local b = ...; if cmp(b, o) > 0 then return b end return o end
    if n == "min" then local b = ...; if cmp(b, o) < 0 then return b end return o end
    if m and m.__next then
      local g = I[n]
      if g then return g(iterOf(iter(o)), ...) end
    end
    if o == unit and n == "is_ok" then return true end
    panic("no method named `" .. n .. "` found for " .. tostring(m and m.__name or "this value"))
  elseif t == "string" then
    local u = userMethod(o, n)
    if u then return u(o, ...) end
    local f = S[n]
    if f then return f(o, ...) end
    if n == "max" or n == "min" then return N[n](o, ...) end
    panic("no method named `" .. n .. "` found for String")
  elseif t == "number" or t == "boolean" then
    local u = userMethod(o, n)
    if u then return u(o, ...) end
    local f = N[n]
    if f then return f(o, ...) end
    panic("no method named `" .. n .. "` found for this number")
  elseif t == "function" then
    if n == "call" then return o(...) end
    panic("no method named `" .. n .. "` on a function")
  end
  panic("no method named `" .. n .. "`")
end
function R.mutcall(o, n, ...)
  local t = type_(o)
  if t == "string" then
    local f = STRM[n]
    if f then
      local nv, r = f(o, ...)
      return nv, r
    end
    return nil, R.m(o, n, ...)
  end
  if t == "table" then
    local m = getmt(o)
    if m == Ref then
      local nv, r = R.mutcall(o.get(), n, ...)
      if nv ~= nil then o.set(nv) end
      return nil, r
    end
    if m == Option and OPTM[n] then return OPTM[n](o, ...) end
  end
  return nil, R.m(o, n, ...)
end

-- ---- formatting ----
local function floatDisp(x, dbg)
  if x ~= x then return "NaN" end
  if x == math.huge then return "inf" elseif x == -math.huge then return "-inf" end
  if x == floor(x) and math.abs(x) < 1e16 then
    local s = sfmt("%.0f", x)
    if x == 0 and 1 / x < 0 then s = "-0" end
    return dbg and (s .. ".0") or s
  end
  for p = 1, 17 do
    local s = sfmt("%." .. p .. "g", x)
    if tonumber(s) == x then
      if s:find("e", 1, true) then
        if dbg then
          local m, e = s:match("^(.-)e([+-]%d+)$")
          return m .. "e" .. tonumber(e)
        end
        return (sfmt("%.0f", x))
      end
      return s
    end
  end
  return sfmt("%.17g", x)
end
local Formatter = { __name = "Formatter" }
Formatter.__index = Formatter
local function withFormatter(fn, o, spec)
  local f = setmt({ buf = {}, spec = spec }, Formatter)
  local r = fn(o, f)
  return concat(f.buf)
end
function Formatter.write_str(f, s) f.buf[#f.buf + 1] = d(s); return Ok(unit) end
function Formatter.pad(f, s) f.buf[#f.buf + 1] = d(s); return Ok(unit) end
function Formatter.alternate() return false end
function Formatter.debug_struct(f, n)
  local b = { f = f, name = n, parts = {} }
  return setmt(b, { __index = {
    field = function(self, k, v) self.parts[#self.parts + 1] = k .. ": " .. R.dbg(v); return self end,
    finish = function(self)
      f.buf[#f.buf + 1] = self.name .. " { " .. concat(self.parts, ", ") .. " }"
      return Ok(unit)
    end,
  } })
end
function R.fwrite(f, s)
  if type_(f) == "table" and getmt(f) == Formatter then f.buf[#f.buf + 1] = s; return Ok(unit) end
  if type_(f) == "string" then return Ok(unit) end
  if getmt(f) == Ref then f.set(f.get() .. s); return Ok(unit) end
  if f == R.lib.io.stdoutHandle or (type_(f) == "table" and f.isStdout) then R.write(s); return Ok(unit) end
  if getmt(f) == Vec then for i = 1, #s do Vec.push(f, s:byte(i)) end return Ok(unit) end
  R.write(s)
  return Ok(unit)
end
function R.disp(v)
  local t = type_(v)
  if t == "string" then return v end
  if t == "number" then
    if mtype(v) == "integer" then return tostring(v) end
    return floatDisp(v)
  end
  if t == "boolean" then return v and "true" or "false" end
  if t == "nil" then return "()" end
  if t == "table" then
    local m = getmt(v)
    if m == Ref then return R.disp(v.get()) end
    if m == Cell then return R.disp(v.v) end
    if m == SimpleErr then return v.msg end
    if m and m.__fmt_Display then return withFormatter(m.__fmt_Display, v) end
    return R.dbg(v)
  end
  return tostring(v)
end
local function dbgStr(s)
  return '"' .. s:gsub('[\\"\n\t\r]', function(c)
    if c == "\\" then return "\\\\" elseif c == '"' then return '\\"' elseif c == "\n" then return "\\n" elseif c == "\t" then return "\\t" else return "\\r" end
  end) .. '"'
end
local function dbgList(open, close, items, pretty, level)
  if #items == 0 then return open .. close end
  if pretty then
    local pad = ("    "):rep(level + 1)
    return open .. "\n" .. pad .. concat(items, ",\n" .. pad) .. ",\n" .. ("    "):rep(level) .. close
  end
  return open .. concat(items, ", ") .. close
end
local function dbg(v, pretty, level)
  level = level or 0
  local t = type_(v)
  if t == "string" then return dbgStr(v) end
  if t == "number" then
    if mtype(v) == "integer" then return tostring(v) end
    return floatDisp(v, true)
  end
  if t == "boolean" then return v and "true" or "false" end
  if t == "nil" or v == unit then return "()" end
  if t == "function" then return "<fn>" end
  local m = getmt(v)
  local function sub(x) return dbg(x, pretty, level + 1) end
  if m == Ref then return dbg(v.get(), pretty, level) end
  if m == Cell then return "RefCell { value: " .. dbg(v.v, pretty, level) .. " }" end
  if m == SimpleErr then
    local kind = v.msg:find("invalid digit") and "InvalidDigit" or (v.msg:find("empty") and "Empty" or (v.msg:find("too large") and "PosOverflow" or nil))
    if kind then return "ParseIntError { kind: " .. kind .. " }" end
    return "ParseError(" .. dbgStr(v.msg) .. ")"
  end
  if m == Vec or m == Heap then
    local p = {}
    for i = 1, v.n do p[i] = sub(v[i]) end
    return dbgList("[", "]", p, pretty, level)
  end
  if m == Tuple then
    local p = {}
    for i = 1, #v do p[i] = sub(v[i]) end
    if #p == 1 then return "(" .. p[1] .. ",)" end
    return dbgList("(", ")", p, pretty, level)
  end
  if m == Map then
    local p = {}
    for i, s in ipairs(entries(v)) do p[i] = sub(s.k) .. ": " .. sub(s.v) end
    return dbgList("{", "}", p, pretty, level)
  end
  if m == Set then
    local p = {}
    for i, s in ipairs(entries(v)) do p[i] = sub(s.k) end
    return dbgList("{", "}", p, pretty, level)
  end
  if m == Range then return R.disp(v.a) .. (v.incl and "..=" or "..") .. R.disp(v.b) end
  if m == Option or m == Result then
    if v == None then return "None" end
    return dbgList(v.tag .. "(", ")", { sub(v[1]) }, pretty, level)
  end
  if m == Ordering then return v.tag end
  if m and m.__fmt_Debug then return withFormatter(m.__fmt_Debug, v) end
  if m and m.__enum then
    if v[1] ~= nil then
      local p = {}
      for i = 1, #v do p[i] = sub(v[i]) end
      return dbgList(v.tag .. "(", ")", p, pretty, level)
    end
    local fields = m.__vfields and m.__vfields[v.tag]
    if fields then
      local p = {}
      for i, f in ipairs(fields) do p[i] = f .. ": " .. sub(v[f]) end
      if pretty then return dbgList(v.tag .. " {", "}", p, pretty, level) end
      return v.tag .. " { " .. concat(p, ", ") .. " }"
    end
    return v.tag
  end
  if m and m.__tuple then
    local p = {}
    for i = 1, #v do p[i] = sub(v[i]) end
    return dbgList(m.__name .. "(", ")", p, pretty, level)
  end
  if m and m.__fields then
    if #m.__fields == 0 then return m.__name end
    local p = {}
    for i, f in ipairs(m.__fields) do p[i] = f .. ": " .. sub(v[f]) end
    if pretty then return dbgList(m.__name .. " {", "}", p, pretty, level) end
    return m.__name .. " { " .. concat(p, ", ") .. " }"
  end
  return tostring(m and m.__name or "?")
end
R.dbg = dbg
function R.fmtv(v, spec, wArg, pArg)
  -- [[fill]align][sign][#][0][width][.prec][type]
  local s = spec
  local fill, align = s:match("^(.[\128-\191]*)([<>^])")
  if fill then s = s:sub(#fill + 2)
  else
    align = s:match("^([<>^])")
    if align then s = s:sub(2) end
    fill = " "
  end
  local sign = s:match("^%+")
  if sign then s = s:sub(2) end
  local alt = s:match("^#")
  if alt then s = s:sub(2) end
  local zero = s:match("^0")
  if zero then s = s:sub(2) end
  local width = s:match("^%d+")
  if width then s = s:sub(#width + 1) elseif s:sub(1, 1) == "*" then s = s:sub(2); width = wArg end
  width = tonumber(width)
  local prec
  if s:sub(1, 1) == "." then
    s = s:sub(2)
    prec = s:match("^%d+")
    if prec then s = s:sub(#prec + 1) elseif s:sub(1, 1) == "*" then s = s:sub(2); prec = pArg end
    prec = tonumber(prec)
  end
  local ty = s
  v = d(v)
  local text
  if ty == "?" or ty == "#?" then
    if alt or ty == "#?" then text = dbg(v, true, 0)
    elseif prec and mtype(v) then text = sfmt("%." .. prec .. "f", v)
    else text = dbg(v) end
  elseif ty == "x" or ty == "X" or ty == "o" then
    text = sfmt("%" .. ty, v)
    if alt then text = "0" .. ty .. text end
  elseif ty == "b" then
    local bits = {}
    local x = v
    if x == 0 then bits[1] = "0" end
    while x > 0 do table.insert(bits, 1, tostring(x & 1)); x = x >> 1 end
    text = concat(bits)
    if alt then text = "0b" .. text end
  elseif ty == "e" then
    text = sfmt("%e", v):gsub("0+e", "e"):gsub("%.e", "e"):gsub("e%+?(-?)0*(%d)", "e%1%2")
  elseif mtype(v) == "float" and prec then
    text = sfmt("%." .. prec .. "f", v)
  elseif type_(v) == "string" and prec then
    text = v:sub(1, (utf8.offset(v, prec + 1) or #v + 1) - 1)
  else
    text = R.disp(v)
    if mtype(v) == "integer" and prec then end
  end
  if sign and mtype(v) and v >= 0 then text = "+" .. text end
  if width then
    local len = utf8.len(text) or #text
    if len < width then
      local pad = width - len
      if zero then
        local sg = text:match("^[+-]") or ""
        return sg .. ("0"):rep(pad) .. text:sub(#sg + 1)
      end
      local al = align or ((mtype(v)) and ">" or "<")
      if al == "<" then return text .. fill:rep(pad)
      elseif al == ">" then return fill:rep(pad) .. text end
      local l = pad // 2
      return fill:rep(l) .. text .. fill:rep(pad - l)
    end
  end
  return text
end
function R.assertEq(a, b, ne)
  local same_ = deepEq(d(a), d(b))
  if same_ == ne then
    panic("assertion `left " .. (ne and "!=" or "==") .. " right` failed\n  left: " .. dbg(a) .. "\n right: " .. dbg(b))
  end
end

-- ---- the library by path ----
local lib = {}
R.lib = lib
local function wrapCell(v) return setmt({ v = v, shared = true }, Cell) end
lib.String = { new = function() return "" end, from = function(x) return R.disp(x) end, with_capacity = function() return "" end, from_utf8 = function(v) local p = {}; for i = 1, v.n do p[i] = string.char(v[i]) end return Ok(concat(p)) end, from_utf8_lossy = function(v) local p = {}; for i = 1, v.n do p[i] = string.char(v[i]) end return concat(p) end }
lib.Vec = { new = function() return vecn({}, 0) end, with_capacity = function() return vecn({}, 0) end, from = function(x) if type_(x) == "string" then return R.bytes(x) end return x end }
lib.VecDeque = { new = lib.Vec.new, with_capacity = lib.Vec.new, from = lib.Vec.from }
lib.BinaryHeap = { new = function() return setmt({ n = 0 }, Heap) end, from = function(x) Vec.sort(x); return setmt(x, Heap) end }
lib.HashMap = { new = function() return newMap(Map) end, with_capacity = function() return newMap(Map) end, from = function(a) return I.collect(a, "HashMap") end }
lib.BTreeMap = { new = function() return newMap(Map, true) end, from = lib.HashMap.from }
lib.HashSet = { new = function() return newMap(Set) end, with_capacity = function() return newMap(Set) end, from = function(a) return I.collect(a, "HashSet") end }
lib.BTreeSet = { new = function() return newMap(Set, true) end, from = lib.HashSet.from }
local same1 = function(x) return x end
lib.Box = { new = same1, from = same1 }
lib.Rc = { new = function(x) if type_(x) == "table" then return x end return wrapCell(x) end, clone = same1, strong_count = function() return 1 end, ptr_eq = function(a, b) return a == b end, downgrade = same1 }
lib.Arc = lib.Rc
lib.Weak = { new = function() return None end }
lib.RefCell = { new = wrapCell }
lib.Cell, lib.Mutex, lib.RwLock = lib.RefCell, lib.RefCell, lib.RefCell
lib.Default = { default = function() return 0 end }
lib.mem = {
  swap = function(a, b)
    local x, y = d(a), d(b)
    if type_(x) == "table" and getmt(a) ~= Ref then
      local cx = {}
      for k, v in pairs(x) do cx[k] = v end
      local mx = getmt(x)
      R.setd(a, y)
      for k in pairs(b) do b[k] = nil end
      for k, v in pairs(cx) do b[k] = v end
      setmt(b, mx)
      return unit
    end
    R.setd(a, y)
    R.setd(b, x)
    return unit
  end,
  replace = function(a, v)
    local old = d(a)
    if type_(old) == "table" and getmt(a) ~= Ref then old = R.clone(old) end
    R.setd(a, v)
    return old
  end,
  take = function(a)
    local old = d(a)
    if type_(old) == "string" then R.setd(a, ""); return old end
    if mtype(old) then R.setd(a, 0); return old end
    if old == None or getmt(old) == Option then
      local c = old
      R.setd(a, None)
      return c
    end
    local cp = R.clone(old)
    if getmt(old) == Vec then Vec.clear(old) end
    return cp
  end,
  drop = function() return unit end,
  size_of = function() return 8 end,
}
lib.cmp = { max = function(a, b) if cmp(b, a) >= 0 then return b end return a end, min = function(a, b) if cmp(b, a) < 0 then return b end return a end, Reverse = same1 }
lib.iter = {
  ["repeat"] = function(v) return iterOf(function() return v end) end,
  repeat_ = function(v) return iterOf(function() return v end) end,
  once = function(v)
    local done = false
    return iterOf(function()
      if not done then done = true; return v end
    end)
  end,
  empty = function() return iterOf(function() end) end,
  from_fn = function(f)
    return iterOf(function()
      local o = f()
      if o ~= None then return o[1] end
    end)
  end,
  successors = function(first, f)
    local cur = first
    return iterOf(function()
      if cur == None then return nil end
      local v = cur[1]
      cur = f(v)
      return v
    end)
  end,
}
lib.process = { exit = function(c) error({ exit = c }, 0) end, id = function() return 1 end }
lib.env = {
  args = function()
    local t = {}
    for i, a in ipairs(R.progArgs or {}) do t[i] = a end
    return iterOf(iter(vecn(t, #t)))
  end,
  var = function() return Err(R.simpleErr("environment variable not found")) end,
}
local ioError = function(m) return R.simpleErr(m) end
lib.fs = {
  read_to_string = function(p)
    local s = fs.read(p)
    if not s then return Err(ioError("No such file or directory (os error 2)")) end
    return Ok(s)
  end,
  write = function(p, s) fs.write(p, R.disp(s)); return Ok(unit) end,
  remove_file = function(p) fs.remove(p); return Ok(unit) end,
  create_dir_all = function(p) if sys and sys.shell then sys.shell("mkdir -p " .. p) end return Ok(unit) end,
}
local function readLine()
  if not key or not key.poll then return nil end
  local buf = {}
  while true do
    local k = key.poll()
    if k == "enter" then R.write("\n"); return concat(buf) end
    if k == "backspace" then
      if #buf > 0 then buf[#buf] = nil; R.write("\b \b") end
    elseif k == "ctrl-d" then if #buf == 0 then return nil end
    elseif k == "space" then buf[#buf + 1] = " "; R.write(" ")
    elseif k and #k == 1 then buf[#buf + 1] = k; R.write(k)
    elseif not k and sys and sys.sleep then sys.sleep(10) end
  end
end
local Stdin = { __name = "Stdin" }
Stdin.__index = Stdin
function Stdin.read_line(_, s)
  local l = readLine()
  if not l then return Ok(0) end
  R.setd(s, d(s) .. l .. "\n")
  return Ok(#l + 1)
end
function Stdin.lock(x) return x end
function Stdin.lines()
  return iterOf(function()
    local l = readLine()
    if l then return Ok(l) end
  end)
end
local Stdout = { __name = "Stdout", isStdout = true }
Stdout.__index = Stdout
function Stdout.flush() return Ok(unit) end
function Stdout.lock(x) return x end
function Stdout.write_all(_, b) R.write(R.disp(b)); return Ok(unit) end
lib.io = {
  stdin = function() return setmt({}, Stdin) end,
  stdout = function() return setmt({ isStdout = true }, Stdout) end,
  stderr = function() return setmt({ isStdout = true }, Stdout) end,
  Error = R.simpleErr,
}
local Thread = { __name = "JoinHandle" }
Thread.__index = Thread
function Thread.join(t) return t.res end
lib.thread = {
  spawn = function(f)
    local ok, v = pcall(f)
    if not ok then
      if getmt(v) == PanicMt then return setmt({ res = Err(v.msg) }, Thread) end
      error(v, 0)
    end
    return setmt({ res = Ok(v) }, Thread)
  end,
  sleep = function(ms) if sys and sys.sleep then sys.sleep(math.floor(ms)) end return unit end,
}
lib.Duration = { from_millis = same1, from_secs = function(s) return s * 1000 end, from_micros = function(x) return x // 1000 end, from_secs_f64 = function(s) return s * 1000 end }
local Instant = { __name = "Instant" }
Instant.__index = Instant
function Instant.elapsed(i) return setmt({ ms = (sys and sys.millis and sys.millis() or 0) - i.t }, { __index = {
  as_millis = function(x) return x.ms end, as_secs = function(x) return x.ms // 1000 end, as_secs_f64 = function(x) return x.ms / 1000 end, as_micros = function(x) return x.ms * 1000 end } }) end
lib.Instant = { now = function() return setmt({ t = sys and sys.millis and sys.millis() or 0 }, Instant) end }
lib.time = {}
lib.fmt = { Error = R.simpleErr("formatter error") }
lib.mpsc = {
  channel = function()
    local q = {}
    local sender = setmt({}, { __index = { send = function(_, v) q[#q + 1] = v; return Ok(unit) end, clone = function(s) return s end } })
    local receiver = setmt({}, { __index = {
      recv = function()
        if #q == 0 then return Err(R.simpleErr("receiving on a closed channel")) end
        return Ok(table.remove(q, 1))
      end,
      try_recv = function()
        if #q == 0 then return Err(R.simpleErr("receiving on an empty channel")) end
        return Ok(table.remove(q, 1))
      end,
      iter = function() return iterOf(function() return table.remove(q, 1) end) end,
      into_iter = function() return iterOf(function() return table.remove(q, 1) end) end,
      __next = nil,
    } })
    return setmt({ sender, receiver }, Tuple)
  end,
}
R.type_String, R.type_Vec, R.type_Box = lib.String, lib.Vec, lib.Box

function R.run(text, args)
  local G = {}
  R.progArgs = args
  G.Display, G.Debug, G.Clone, G.Copy, G.PartialEq, G.Eq, G.PartialOrd, G.Ord, G.Hash, G.Default = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
  local env = setmt({ R = R, G = setmt(G, { __index = function(_, k) return R.traitBase and nil end }) }, { __index = _G })
  local f, e = load(text, "=program", "t", env)
  if not f then
    R.write("internal error: " .. tostring(e) .. "\n")
    return 1
  end
  local ok, res = pcall(function()
    local mainF = f()
    if not mainF then error({ msg2 = "`main` function not found in crate" }, 0) end
    return mainF()
  end)
  if ok then
    if type_(res) == "table" and res.tag == "Err" then
      R.write("Error: " .. dbg(res[1]) .. "\n")
      return 1
    end
    return 0
  end
  if type_(res) == "table" and res.exit then return res.exit end
  if getmt(res) == PanicMt then
    R.write("thread 'main' panicked at main.rs:\n" .. tostring(res.msg) .. "\nnote: run with `RUST_BACKTRACE=1` environment variable to display a backtrace\n")
    return 101
  end
  if type_(res) == "table" and res.msg2 then R.write("error: " .. res.msg2 .. "\n"); return 1 end
  if type_(res) == "string" and res:find("interrupted", 1, true) then error(res, 0) end
  if type_(res) == "string" and res:find("stack overflow", 1, true) then
    R.write("thread 'main' has overflowed its stack\nfatal runtime error: stack overflow\n")
    return 134
  end
  R.write("thread 'main' panicked: " .. tostring(res):gsub("^program:%d+: ", "") .. "\n")
  return 101
end
return R
