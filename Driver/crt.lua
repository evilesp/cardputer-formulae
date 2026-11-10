#!lua
-- crt: the run-time of the C and C++ programs that clang translates: pointers, strings, stdio, string.h, stdlib.h, math.h, containers, streams.
local R = {}
local mtype, floor, concat, sfmt, char, byte = math.type, math.floor, table.concat, string.format, string.char, string.byte
local setmt, getmt, type_ = setmetatable, getmetatable, type
local function write(s) term.write(s) end

-- ---- pointers: {a = a table, i = a key} ----
function R.ptr(a, i) return { a = a, i = i } end
-- a row of a 2-D array knows its length (__rn), its number (__ri) and the array (__pr): a pointer that leaves the row goes on
-- in the next one. One past the end stays in its row (the end of a loop); reading or writing it reaches the next row.
local function rowFix(a, i)
  local rn = a.__rn
  if rn and rn > 0 and (i >= rn or i < 0) then
    local flat = a.__ri * rn + i
    local row = a.__pr[flat // rn]
    if row then return row, flat % rn end
  end
  return a, i
end
function R.padd(p, n)
  local a, i = p.a, p.i + n
  local rn = a.__rn
  if rn and (i > rn or i < 0) then a, i = rowFix(a, i) end
  return { a = a, i = i }
end
function R.pdiff(p, q)
  if p == nil or q == nil then return (p == nil and 0 or 1) - (q == nil and 0 or 1) end
  local pa, qa = p.a, q.a
  if pa ~= qa and pa.__rn and qa.__rn and pa.__pr == qa.__pr then return (pa.__ri * pa.__rn + p.i) - (qa.__ri * qa.__rn + q.i) end
  return p.i - q.i
end
function R.load(p)
  if p == nil then error("Segmentation fault (a null pointer was read)", 0) end
  local a, i = p.a, p.i
  local v = a[i]
  if v == nil and a.__rn then a, i = rowFix(a, i); return a[i] end
  return v
end
function R.store(p, v)
  if p == nil then error("Segmentation fault (a null pointer was written)", 0) end
  local a, i = p.a, p.i
  if a.__rn and i >= a.__rn then a, i = rowFix(a, i) end
  a[i] = v
end
local rptrMt
local mergeSort  -- (below, with the containers; qsort uses it too)
function R.box(v) return { a = { [0] = v }, i = 0 } end
function R.addr(get, set)
  return { a = setmt({}, { __index = function() return get() end, __newindex = function(_, _, v) set(v) end }), i = 0 }
end
function R.peq(x, y)
  if x == 0 then x = nil end
  if y == 0 then y = nil end
  if x == y then return true end
  if x == nil or y == nil then return false end
  if x.a == y.a and x.i == y.i then return true end
  if x.mapEnd and y.mapEnd then return true end
  local vx = rawget(x.a, x.i)
  if type_(vx) == "table" and vx == rawget(y.a, y.i) then return true end
  return false
end
function R.typed(p, zero)
  if p == nil or p == 0 then return nil end
  local mt = getmt(p.a)
  if zero then
    setmt(p.a, { typedStruct = true, __index = function(t, k)
      local v = zero()
      rawset(t, k, v)
      return v
    end })
  else setmt(p.a, nil) end
  return p
end
function R.retype(p, zero)
  if p == nil or p == 0 then return nil end
  if next(p.a) == nil then
    setmt(p.a, { typedStruct = true, __index = function(t, k)
      local v = zero()
      rawset(t, k, v)
      return v
    end })
  end
  return p
end
function R.void() end
function R.iff(c, a, b) if c then return a() end return b() end
function R.truth(v) return v ~= nil and v ~= 0 and v ~= false end
function R.d2i(x)
  if x ~= x then return math.mininteger end
  local r = x >= 0 and floor(x) or -floor(-x)
  return math.tointeger(r) or math.mininteger
end
function R.idiv(a, b)
  if b == 0 then error("Floating point exception (division by zero)", 0) end
  local q = a // b
  if q < 0 and q * b ~= a then q = q + 1 end
  return q
end
function R.imod(a, b)
  if b == 0 then error("Floating point exception (division by zero)", 0) end
  return math.fmod(a, b)
end
function R.sar(a, b)
  if a >= 0 then return a >> b end
  return ~((~a) >> b)
end
function R.dadd(a, b) if type_(a) == "string" or type_(b) == "string" then return a .. b end return a + b end
function R.dsub(a, b) return a - b end
function R.dmul(a, b) return a * b end
function R.ddiv(a, b) if mtype(a) == "integer" and mtype(b) == "integer" then return R.idiv(a, b) end return a / b end
function R.dmod(a, b) return math.fmod(a, b) end
function R.min(a, b, f) if f then return f(b, a) and b or a end if b < a then return b end return a end
function R.max(a, b, f) if f then return f(a, b) and b or a end if a < b then return b end return a end
function R.abs(x) return x < 0 and -x or x end
function R.delete(p)
  if p == nil then return end
  local o = p.a[p.i]
  if type_(o) == "table" and o.dtor_0 then o:dtor_0() end
end
function R.dyncast(p, cls)
  if p == nil then return nil end
  local o = p.a[p.i]
  local m = getmt(o)
  while m do
    if m == cls then return p end
    m = m.__base
  end
  return nil
end
function R.instof(o, cls)
  if type_(o) ~= "table" then return false end
  local m = getmt(o)
  while m do
    if m == cls then return true end
    m = m.__base
  end
  return false
end

-- ---- arrays and strings ----
function R.arr(n, z)
  local t = {}
  for i = 0, n - 1 do t[i] = z end
  return t
end
-- the rows of a two-dimensional array know their place, so that a pointer to the first element can run over the whole array (int *p = &a[0][0]; p[k])
-- p.a[p.i + k] past the end of a row (the translator writes that for p[k]) reaches the next rows through these
local RowMt = {
  __index = function(a, i)
    if mtype(i) ~= "integer" then return nil end
    local b, j = rowFix(a, i)
    if b ~= a then return b[j] end
  end,
  __newindex = function(a, i, v)
    if mtype(i) == "integer" then
      local b, j = rowFix(a, i)
      if b ~= a then b[j] = v; return end
    end
    rawset(a, i, v)
  end,
}
local function linkRows(t, n)
  for k = 0, n - 1 do
    local row = t[k]
    if type_(row) == "table" and getmt(row) == nil and row[0] ~= nil and type_(row[0]) ~= "table" then
      local rn = 0
      while row[rn] ~= nil do rn = rn + 1 end
      row.__pr, row.__ri, row.__rn = t, k, rn
      setmt(row, RowMt)
    end
  end
  return t
end
function R.arrf(n, f)
  local t = {}
  for i = 0, n - 1 do t[i] = f() end
  return linkRows(t, n)
end
function R.arrinit(n, z, vals)
  for i = 0, n - 1 do if vals[i] == nil then vals[i] = z end end
  return vals
end
function R.arrinitf(n, f, vals)
  for i = 0, n - 1 do if vals[i] == nil then vals[i] = f() end end
  return linkRows(vals, n)
end
function R.chararr(s, n)
  local t = {}
  n = n or (#s + 1)
  for i = 0, n - 1 do t[i] = byte(s, i + 1) or 0 end
  return t
end
local cstrCache = {}
function R.cstr(s)
  local p = cstrCache[s]
  if not p then
    p = { a = R.chararr(s), i = 0 }
    cstrCache[s] = p
  end
  return p
end
local charBuf = {}
local function tolua(p)
  if p == nil then return "(null)" end
  if type_(p) == "string" then return p end
  local a, i = p.a, p.i
  local j = i
  while true do
    local c = a[j]
    if c == 0 or c == nil then break end
    j = j + 1
  end
  if j == i then return "" end
  -- string.char of up to 200 bytes at a time (one string per piece, not one per byte)
  local parts, n, buf = nil, 0, charBuf
  for s = i, j - 1, 200 do
    local e = s + 199
    if e > j - 1 then e = j - 1 end
    for k = s, e do buf[k - s + 1] = a[k] & 255 end
    local piece = char(table.unpack(buf, 1, e - s + 1))
    if s == i and e == j - 1 then return piece end
    parts = parts or {}
    n = n + 1
    parts[n] = piece
  end
  return concat(parts)
end
R.tolua = tolua
function R.tolua_num(x) return tostring(x) end
function R.ptrtext(p) if p == nil then return "0" end return sfmt("0x%x", tonumber(tostring(p.a):match("0x(%x+)") or "1000", 16) + (mtype(p.i) == "integer" and p.i * 4 or 0)) end
local function fromLua(s, p)
  local a, i = p.a, p.i
  for k = 1, #s do a[i + k - 1] = byte(s, k) end
  a[i + #s] = 0
end

-- std::string
function R.strget(s, i) return byte(s, i + 1) or 0 end
function R.strat(s, i)
  if i < 0 or i >= #s then R.throw(R.newExc("out_of_range", "basic_string::at: __n (which is " .. i .. ") >= this->size() (which is " .. #s .. ")")) end
  return byte(s, i + 1)
end
function R.strset(s, i, c) return s:sub(1, i) .. char(c & 255) .. s:sub(i + 2) end
function R.substr(s, a, n)
  if a > #s then R.throw(R.newExc("out_of_range", "basic_string::substr")) end
  if n == nil or n < 0 then return s:sub(a + 1) end
  return s:sub(a + 1, a + n)
end
function R.strfind(s, t, from)
  local i = s:find(t, (from or 0) + 1, true)
  return i and i - 1 or -1
end
function R.strrfind(s, t)
  local last, i = -1, 1
  while true do
    local a = s:find(t, i, true)
    if not a then return last end
    last = a - 1
    i = a + 1
  end
end
function R.strcmp(a, b) return a < b and -1 or (a > b and 1 or 0) end
function R.strerase(s, a, n)
  if type_(a) == "table" then return s:sub(1, a.i) .. s:sub(a.i + 2) end
  if n == nil or n < 0 then return s:sub(1, a) end
  return s:sub(1, a) .. s:sub(a + n + 1)
end
function R.strinsert(s, a, t) return s:sub(1, a) .. t .. s:sub(a + 1) end
function R.strreplace(s, a, n, t) return s:sub(1, a) .. t .. s:sub(a + n + 1) end
function R.striter(s, i)
  local a = {}
  for k = 1, #s do a[k - 1] = byte(s, k) end
  a.str = s
  return { a = a, i = i }
end
function R.stoi(s)
  local v = tonumber(tostring(s):match("^%s*([+-]?%d+)"))
  if not v then R.throw(R.newExc("invalid_argument", "stoi")) end
  return math.tointeger(v)
end
R.stol, R.stoll = R.stoi, R.stoi
function R.stod(s)
  local v = tonumber(tostring(s):match("^%s*([+-]?%d*%.?%d*[eE]?[+-]?%d*)"))
  if not v then R.throw(R.newExc("invalid_argument", "stod")) end
  return v + 0.0
end
R.stof = R.stod

-- ---- containers ----
local Vec = { __name = "vector" }
Vec.__index = Vec
function R.vec() return setmt({ n = 0 }, Vec) end
function R.vecof(n, ...)
  local v = setmt({ n = n }, Vec)
  local a = { ... }
  for i = 1, n do v[i - 1] = a[i] end
  return v
end
function R.vecn(n, f)
  local v = setmt({ n = n }, Vec)
  for i = 0, n - 1 do v[i] = f() end
  return v
end
function R.vecrange(p, q)
  local v = setmt({ n = 0 }, Vec)
  for i = p.i, q.i - 1 do v[v.n] = p.a[i]; v.n = v.n + 1 end
  return v
end
function R.vpush(v, x) v[v.n] = x; v.n = v.n + 1 end
function R.vpop(v)
  if v.n > 0 then v.n = v.n - 1; v[v.n] = nil end
end
function R.vshift(v)
  if v.n == 0 then return end
  table.move(v, 1, v.n - 1, 0)
  v.n = v.n - 1
  v[v.n] = nil
end
function R.vat(v, i)
  if i < 0 or i >= v.n then R.throw(R.newExc("out_of_range", "vector::_M_range_check: __n (which is " .. i .. ") >= this->size() (which is " .. v.n .. ")")) end
  return v[i]
end
function R.vclear(v) for i = 0, v.n - 1 do v[i] = nil end v.n = 0 end
function R.verase(v, p, q)
  local a, b = p.i, q and q.i or p.i + 1
  local c = b - a
  table.move(v, b, v.n - 1, a)
  for i = v.n - c, v.n - 1 do v[i] = nil end
  v.n = v.n - c
  return { a = v, i = a }
end
function R.vinsert(v, p, x)
  table.move(v, p.i, v.n - 1, p.i + 1)
  v[p.i] = x
  v.n = v.n + 1
  return { a = v, i = p.i }
end
function R.vresize(v, n, f)
  for i = v.n, n - 1 do v[i] = f() end
  for i = n, v.n - 1 do v[i] = nil end
  v.n = n
end
function R.vassign(v, n, x)
  R.vclear(v)
  for i = 0, n - 1 do v[i] = x end
  v.n = n
end
function R.vswap(a, b)
  local keys = {}
  for k, x in pairs(a) do keys[k] = x end
  for k in pairs(a) do a[k] = nil end
  for k, x in pairs(b) do a[k] = x end
  for k in pairs(b) do b[k] = nil end
  for k, x in pairs(keys) do b[k] = x end
end
function R.rptr(v, i) return setmt({ a = v, i = i }, { __index = nil }) end

local function less(a, b)
  if type_(a) == "table" then
    if a.first ~= nil then
      if a.first ~= b.first then return less(a.first, b.first) end
      return less(a.second, b.second)
    end
    if getmt(a) == Vec then
      for i = 0, math.min(a.n, b.n) - 1 do
        if less(a[i], b[i]) then return true end
        if less(b[i], a[i]) then return false end
      end
      return a.n < b.n
    end
    if a.op_lt_1 then return a:op_lt_1(b) end
  end
  if a == true then a = 1 elseif a == false then a = 0 end
  if b == true then b = 1 elseif b == false then b = 0 end
  return a < b
end
R.less = less
local function veq(a, b)
  if type_(a) == "table" and type_(b) == "table" then
    if a.op_eq_1 then return a:op_eq_1(b) end
    if a.first ~= nil and b.first ~= nil then return veq(a.first, b.first) and veq(a.second, b.second) end
    if getmt(a) == Vec and getmt(b) == Vec then
      if a.n ~= b.n then return false end
      for i = 0, a.n - 1 do if not veq(a[i], b[i]) then return false end end
      return true
    end
  end
  return a == b
end
Vec.__eq = function(a, b) return veq(a, b) end
Vec.__lt = function(a, b) return less(a, b) end
Vec.__le = function(a, b) return not less(b, a) end

local Pair = { __name = "pair" }
Pair.__index = Pair
Pair.__eq = function(a, b) return veq(a.first, b.first) and veq(a.second, b.second) end
Pair.__lt = function(a, b) return less(a, b) end
Pair.__le = function(a, b) return not less(b, a) end
function R.pair(a, b) return setmt({ first = a, second = b }, Pair) end

-- a map: a hash on the key (its text for tables), an ordered list made when it is walked
local Map = { __name = "map" }
Map.__index = Map
local function hashKey(k)
  if type_(k) == "table" then
    if k.first ~= nil then return "\0P" .. tostring(hashKey(k.first)) .. "\1" .. tostring(hashKey(k.second)) end
    if getmt(k) == Vec then
      local p = {}
      for i = 0, k.n - 1 do p[i + 1] = tostring(hashKey(k[i])) end
      return "\0V" .. concat(p, "\1")
    end
  end
  return k
end
function R.map(sorted, zero)
  return setmt({ n = 0, h = {}, sorted = sorted, zero = zero, zeroT = type_(zero) == "table" and zero or nil, isSet = false }, Map)
end
function R.set(sorted) return setmt({ n = 0, h = {}, sorted = sorted, isSet = true }, Map) end
local function slot(m, k)
  local hk = hashKey(k)
  local s = m.h[hk]
  if not s then
    local z = m.zero
    if m.zeroT then z = R.copy(m.zeroT) end
    s = { k = k, v = z, seq = (m.seq or 0) + 1 }
    m.seq = s.seq
    m.h[hk] = s
    m.n = m.n + 1
    m.cache = nil
  end
  return s
end
R.mslot = slot
function R.mput(m, k, v)
  slot(m, k).v = v
end
function R.mputnew(m, k, v)
  if not m.h[hashKey(k)] then slot(m, k).v = v end
end
function R.mputpair(m, p)
  if p.first == nil then R.mputnew(m, p[0], p[1]) else R.mputnew(m, p.first, p.second) end
end
function R.mcount(m, k) return m.h[hashKey(k)] and 1 or 0 end
function R.mat(m, k)
  local s = m.h[hashKey(k)]
  if not s then R.throw(R.newExc("out_of_range", "map::at")) end
  return s.v
end
local function walk(m)
  if m.cache then return m.cache end
  local items, n = {}, 0
  for _, s in pairs(m.h) do n = n + 1; items[n] = s end
  if m.sorted then table.sort(items, function(a, b) return less(a.k, b.k) end)
  else table.sort(items, function(a, b) return a.seq > b.seq end) end
  local arr = { n = n }
  for i = 1, n do
    local s = items[i]
    if m.isSet then arr[i - 1] = s.k
    else
      arr[i - 1] = setmt({ first = s.k }, { __index = function(t, f) if f == "second" then return s.v end return Pair[f] end, __newindex = function(t, f, v) if f == "second" then s.v = v else rawset(t, f, v) end end })
    end
  end
  m.cache = arr
  return arr
end
function R.rangeOf(c)
  if type_(c) == "string" then
    local a = { n = #c }
    for i = 1, #c do a[i - 1] = byte(c, i) end
    return a
  end
  if getmt(c) == Map then return walk(c) end
  return c
end
function R.mbegin(m) local w = walk(m); return { a = w, i = 0, mapEnd = w.n == 0 } end
function R.mend(m) local w = walk(m); return { a = w, i = w.n, mapEnd = true } end
function R.mfind(m, k)
  local s = m.h[hashKey(k)]
  local w = walk(m)
  if not s then return { a = w, i = w.n, mapEnd = true } end
  for i = 0, w.n - 1 do
    local x = w[i]
    if m.isSet then if veq(x, k) then return { a = w, i = i } end
    elseif veq(x.first, k) then return { a = w, i = i } end
  end
end
function R.merase(m, k)
  if type_(k) == "table" and k.a ~= nil and k.i ~= nil then
    local x = k.a[k.i]
    k = m.isSet and x or x.first
  end
  local hk = hashKey(k)
  if m.h[hk] then
    m.h[hk] = nil
    m.n = m.n - 1
    m.cache = nil
    return 1
  end
  return 0
end
function R.mclear(m) m.h = {}; m.n = 0; m.cache = nil end
function R.setof(sorted, ...)
  local s = R.set(sorted)
  for _, v in ipairs{ ... } do slot(s, v) end
  return s
end
function R.mapof(sorted, zero, ...)
  local m = R.map(sorted, zero)
  for _, p in ipairs{ ... } do
    if p.first ~= nil then slot(m, p.first).v = p.second
    else slot(m, p[0]).v = p[1] end
  end
  return m
end
-- a priority queue: a binary heap, the largest on top
local PQ = { __name = "priority_queue" }
PQ.__index = PQ
function R.pq() return setmt({ n = 0, h = {} }, PQ) end
function R.pqpush(q, x)
  local h = q.h
  q.n = q.n + 1
  local i = q.n
  h[i] = x
  while i > 1 do
    local p = i // 2
    if not less(h[p], h[i]) then break end
    h[p], h[i] = h[i], h[p]
    i = p
  end
end
function R.pqtop(q) return q.h[1] end
function R.pqpop(q)
  local h, n = q.h, q.n
  if n == 0 then return end
  h[1] = h[n]
  h[n] = nil
  n = n - 1
  q.n = n
  local i = 1
  while true do
    local l, r, m = i * 2, i * 2 + 1, i
    if l <= n and less(h[m], h[l]) then m = l end
    if r <= n and less(h[m], h[r]) then m = r end
    if m == i then break end
    h[m], h[i] = h[i], h[m]
    i = m
  end
end
-- a deep copy of a value: structs, vectors, arrays
local function copy(v)
  if type_(v) ~= "table" then return v end
  local m = getmt(v)
  if m and m.op_copy then return v:op_copy() end
  local o = {}
  for k, x in pairs(v) do
    if type_(x) == "table" and k ~= "h" and k ~= "cache" and not (x.a and x.i ~= nil) then o[k] = copy(x) else o[k] = x end
  end
  if m == Map then
    o.h = {}
    for k, s in pairs(v.h) do o.h[k] = { k = s.k, v = copy(s.v), seq = s.seq } end
    o.cache = nil
  end
  return setmt(o, m)
end
R.copy = copy

-- ---- streams ----
local cout = { prec = 6 }
R.cout = cout
R.cin = {}
R.manip = { fixed = "fixed", scientific = "sci", defaultfloat = "defaultfloat", boolalpha = "boolalpha", noboolalpha = "noboolalpha", left = "left", right = "right", hex = "hex", dec = "dec", oct = "oct", showpoint = "showpoint", flush = "flush", ws = "ws" }
local function dbl(x)
  if x ~= x then return "nan" end
  if x == math.huge then return "inf" elseif x == -math.huge then return "-inf" end
  if cout.mode == "fixed" then return sfmt("%." .. cout.prec .. "f", x) end
  if cout.mode == "sci" then return sfmt("%." .. cout.prec .. "e", x) end
  return sfmt("%." .. cout.prec .. "g", x)
end
R.dbl = function(x) return { dbl = x } end
function R.boolout(b)
  if cout.boolalpha then return b and "true" or "false" end
  return b and "1" or "0"
end
function R.anyout(v)
  local t = type_(v)
  if t == "number" then if mtype(v) == "float" then return { dbl = v } end return tostring(v) end
  if t == "boolean" then return R.boolout(v) end
  if t == "table" and v.a then return tolua(v) end
  return tostring(v)
end
function R.coutput(s, x)
  local text = x
  if type_(x) == "table" and x.dbl then text = dbl(x.dbl) end
  if cout.base == "hex" and type_(x) == "string" and x:find("^%-?%d+$") then text = sfmt("%x", tonumber(x)) end
  if cout.base == "oct" and type_(x) == "string" and x:find("^%-?%d+$") then text = sfmt("%o", tonumber(x)) end
  if type_(text) ~= "string" then text = tostring(text) end
  local w = cout.width
  if w then
    cout.width = nil
    local pad = w - #text
    if pad > 0 then
      local f = cout.fill or " "
      if cout.left then text = text .. f:rep(pad) else text = f:rep(pad) .. text end
    end
  end
  if s and s.isStream then
    if s.h then s.h:write(text) else s.text = s.text .. text end
    return s
  end
  write(text)
  return s
end
function R.sfill(n, c) return string.rep(char(c & 255), n) end
-- files and strings as streams
local StreamMt = {}
function R.stream(kind, path, mode)
  local s = setmt({ isStream = true, kind = kind, text = "", pos = 1, ok = true }, StreamMt)
  if kind == "stringstream" or kind == "istringstream" or kind == "ostringstream" then
    if path then s.text = tolua(path) end
    return s
  end
  if path then
    R.sopen(s, path, mode)
  end
  return s
end
-- a stream of C++ closes itself when its block ends; here the files that are written are flushed before another file is opened, and at the end
local openOut = setmt({}, { __mode = "k" })
local function flushStreams() for st in pairs(openOut) do if st.h then st.h:flush() end end end
R.flushStreams = flushStreams
function R.sopen(s, path, mode)
  flushStreams()
  path = tolua(path)
  mode = mode or 0
  local writes = s.kind == "ofstream" or (s.kind == "fstream" and mode & 16 ~= 0)
  if writes then
    local h = io.open(path, mode & 1 ~= 0 and "a" or "w")
    if h then s.h = h; s.open = true; openOut[s] = true else s.ok = false end
  else
    local h = io.open(path, "r")
    if h then
      s.text = h:read("a") or ""
      h:close()
      s.open = true
    else s.ok = false end
  end
end
function R.sgood(s) return s.ok and not s.failed end
function R.smethod(s, n, a, b)
  if n == "is_open" then return s.open == true
  elseif n == "open" then return R.sopen(s, a, b)
  elseif n == "close" then if s.h then s.h:close(); s.h = nil end s.open = false; return
  elseif n == "good" then return s.ok and not s.failed and s.pos <= #s.text
  elseif n == "eof" then return s.pos > #s.text
  elseif n == "fail" or n == "bad" then return not s.ok or s.failed == true
  elseif n == "str" then
    if a ~= nil then s.text = tolua(a); s.pos = 1; return end
    return s.text
  elseif n == "clear" then s.failed = false; return
  elseif n == "flush" then if s.h then s.h:flush() end return
  elseif n == "seekg" then s.pos = (a or 0) + 1; s.failed = false; return
  elseif n == "tellg" then return s.pos - 1
  elseif n == "peek" then return s.text:byte(s.pos) or -1
  elseif n == "get" then local c = s.text:byte(s.pos); if c then s.pos = s.pos + 1 return c end s.failed = true return -1
  end
  return nil
end
function R.getlinefrom(s, set, d)
  if s.pos > #s.text then s.failed = true; return false end
  local sep = d and char(d) or "\n"
  local e = s.text:find(sep, s.pos, true)
  if e then
    set(s.text:sub(s.pos, e - 1))
    s.pos = e + 1
  else
    set(s.text:sub(s.pos))
    s.pos = #s.text + 1
  end
  return true
end
function R.streamtoken(s)
  local a, b = s.text:find("%S+", s.pos)
  if not a then s.failed = true; return nil end
  s.pos = b + 1
  return s.text:sub(a, b)
end
function R.coutmanip(s, m)
  if m == "fixed" or m == "sci" then cout.mode = m
  elseif m == "defaultfloat" then cout.mode = nil
  elseif m == "boolalpha" then cout.boolalpha = true
  elseif m == "noboolalpha" then cout.boolalpha = false
  elseif m == "left" then cout.left = true
  elseif m == "right" then cout.left = false
  elseif m == "hex" or m == "oct" then cout.base = m
  elseif m == "dec" then cout.base = nil
  elseif type_(m) == "table" then
    if m.setw then cout.width = m.setw
    elseif m.setprecision then cout.prec = m.setprecision
    elseif m.setfill then cout.fill = char(m.setfill) end
  end
  return s
end
function R.streammethod(n, a)
  if n == "precision" then cout.prec = a elseif n == "width" then cout.width = a elseif n == "fill" then cout.fill = char(a) end
end
local inputBuf, inputPos = "", 1
R.stdinText = nil
local function readKeyLine()
  if R.stdinText then
    local t = R.stdinText
    if t == "" then return nil end
    local e = t:find("\n", 1, true)
    local l = e and t:sub(1, e - 1) or t
    R.stdinText = e and t:sub(e + 1) or ""
    return l
  end
  if io and io.read then return io.read("l") end
  if not key or not key.poll then return nil end
  local buf = {}
  while true do
    local k = key.poll()
    if k == "enter" then write("\n"); return concat(buf) end
    if k == "backspace" then
      if #buf > 0 then buf[#buf] = nil; write("\b \b") end
    elseif k == "ctrl-d" then if #buf == 0 then return nil end
    elseif k == "space" then buf[#buf + 1] = " "; write(" ")
    elseif k and #k == 1 then buf[#buf + 1] = k; write(k)
    elseif not k and sys and sys.sleep then sys.sleep(10) end
  end
end
local function fill()
  local l = readKeyLine()
  if l == nil then return false end
  inputBuf = l .. "\n"
  inputPos = 1
  return true
end
-- signals and timers: a handler of SIGALRM runs while the program waits (getch, sleep, select), as it would run on Linux
local handlers, timer = {}, nil
local function timerTick()
  if timer and sys.millis() >= timer.next then
    local h = handlers[14]
    if timer.interval > 0 then timer.next = timer.next + timer.interval else timer = nil end
    if h and h ~= 0 and h ~= 1 and type_(h) == "function" then h(14) end
  end
end
R.timerTick = timerTick
local function sleepMs(ms)
  local t0 = sys.millis()
  repeat
    timerTick()
    local left = ms - (sys.millis() - t0)
    if left > 0 then sys.sleep(left > 8 and 8 or left) end
  until sys.millis() - t0 >= ms
end
-- the keys as bytes, for the programs that put the terminal in raw mode (tcsetattr without ICANON): arrows come as ESC [ A ...
local rawKeys, rawMin, rawTime = false, 1, 0
local rawQueue = {}
local KEYSEQ = { up = "\27[A", down = "\27[B", right = "\27[C", left = "\27[D", enter = "\r", backspace = "\127", tab = "\t", space = " ", pgup = "\27[5~", pgdn = "\27[6~", home = "\27[H", ["end"] = "\27[F", delete = "\27[3~" }
local function pollRaw(wait)
  if #rawQueue > 0 then return table.remove(rawQueue, 1) end
  local start = sys.millis()
  while true do
    local k = key and key.poll and key.poll()
    if k then
      local seq = KEYSEQ[k]
      if not seq then
        local c = k:match("^ctrl%-(%a)$")
        if c then seq = string.char(byte(c) & 31) elseif #k == 1 then seq = k else seq = "" end
      end
      for j = 1, #seq do rawQueue[#rawQueue + 1] = byte(seq, j) end
      if #rawQueue > 0 then return table.remove(rawQueue, 1) end
    end
    timerTick()
    if wait >= 0 and sys.millis() - start >= wait then return nil end
    sys.sleep(4)
  end
end
R.pollRaw = pollRaw
local function getc()
  if rawKeys and not R.stdinText then
    local c = pollRaw(rawMin == 0 and rawTime * 100 or -1)
    return c
  end
  if inputPos > #inputBuf then if not fill() then return nil end end
  local c = byte(inputBuf, inputPos)
  inputPos = inputPos + 1
  return c
end
local function token()
  while true do
    local a, b = inputBuf:find("%S+", inputPos)
    if a then
      inputPos = b + 1
      return inputBuf:sub(a, b)
    end
    if not fill() then return nil end
  end
end
R.failed = false
function R.cinread(s, kind, set)
  if s and s.isStream then
    if kind == "c" then
      local a = s.text:find("%S", s.pos)
      if not a then s.failed = true; return s end
      set(s.text:byte(a))
      s.pos = a + 1
      return s
    end
    local t = R.streamtoken(s)
    if t == nil then return s end
    if kind == "s" then set(t)
    elseif kind == "f" then local v = tonumber(t); if v then set(v + 0.0) else s.failed = true end
    else local v = tonumber(t); if v then set(math.tointeger(v) or 0) else s.failed = true end end
    return s
  end
  if kind == "c" then
    local t
    while true do
      t = getc()
      if t == nil or t > 32 then break end
    end
    if t == nil then R.failed = true else set(t) end
    return s
  end
  local t = token()
  if t == nil then R.failed = true; return s end
  if kind == "s" then set(t)
  elseif kind == "f" then local v = tonumber(t); if v then set(v + 0.0) else R.failed = true end
  else local v = tonumber(t); if v then set(math.tointeger(v) or 0) else R.failed = true end end
  return s
end
R.cin = setmt({}, { __name = "cin" })
function R.getlineinto(set)
  if inputPos <= #inputBuf then
    local rest = inputBuf:sub(inputPos)
    inputPos = #inputBuf + 1
    rest = rest:gsub("\n$", "")
    set(rest)
    return true
  end
  local l = readKeyLine()
  if l == nil then return false end
  set(l)
  return true
end

-- ---- printf ----
local function format(fmt, args, start)
  fmt = tolua(fmt)
  local i = start or 1
  local function nextArg() local v = args[i]; i = i + 1; return v end
  local out = fmt:gsub("%%([%-+ #0]*)([%d%*]*)%.?([%d%*]*)([hlLzjt]*)([%a%%])", function(flags, w, p, _, c)
    if c == "%" then return "%" end
    if w == "*" then w = tostring(nextArg()) end
    if p == "*" then p = tostring(nextArg()) end
    local hasPrec = fmt:find("%%[%-+ #0]*[%d%*]*%.", 1) ~= nil and p ~= ""
    local spec = "%" .. flags .. w .. (p ~= "" and ("." .. p) or "")
    if c == "d" or c == "i" then
      local v = nextArg()
      if v == true then v = 1 elseif v == false or v == nil then v = 0 end
      if mtype(v) == "float" then v = R.d2i(v) end
      return sfmt(spec .. "d", v)
    elseif c == "u" then
      local v = nextArg() or 0
      if v == true then v = 1 elseif v == false then v = 0 end
      if v < 0 then v = v & 0xFFFFFFFF end
      return sfmt(spec .. "d", v)
    elseif c == "x" or c == "X" or c == "o" then
      local v = nextArg() or 0
      if v < 0 then v = v & 0xFFFFFFFF end
      return sfmt(spec .. c, v)
    elseif c == "c" then return sfmt(spec .. "s", char((nextArg() or 0) & 255))
    elseif c == "s" then
      local s = tolua(nextArg())
      local fl, wd, pr = spec:match("^%%([%-+ #0]*)(%d*)%.?(%d*)$")
      if not fl then return sfmt(spec .. "s", s) end
      if pr ~= "" then s = s:sub(1, tonumber(pr)) end
      if wd ~= "" and #s < tonumber(wd) then
        local pad = (" "):rep(tonumber(wd) - #s)
        s = fl:find("-", 1, true) and (s .. pad) or (pad .. s)
      end
      return s
    elseif c == "f" or c == "F" or c == "e" or c == "E" or c == "g" or c == "G" or c == "a" then
      local v = nextArg() or 0
      if v == math.huge then return sfmt("%" .. flags .. w .. "s", "inf") elseif v == -math.huge then return sfmt("%" .. flags .. w .. "s", "-inf") elseif v ~= v then return sfmt("%" .. flags .. w .. "s", "nan") end
      return sfmt(spec .. c, v + 0.0)
    elseif c == "p" then return R.ptrtext(nextArg())
    end
    return ""
  end)
  return out
end

-- ---- the C library, found by name ----
local L = {}
function L.printf(f, ...) local s = format(f, { ... }); write(s); return #s end
function L.puts(s) s = tolua(s); write(s .. "\n"); return #s + 1 end
function L.putchar(c) write(char(c & 255)); return c end
function L.sprintf(b, f, ...) local s = format(f, { ... }); fromLua(s, b); return #s end
function L.snprintf(b, n, f, ...)
  local s = format(f, { ... })
  if b and n > 0 then fromLua(s:sub(1, n - 1), b) end
  return #s
end
function L.getchar() return getc() or -1 end
-- scanf: a reader of bytes with one byte of look-back, and the format as in C
local function scanFormat(peek, nextc, fmt, args)
  fmt = tolua(fmt)
  local n, ai, consumed = 0, 1, 0
  local i = 1
  local function take() local c = nextc(); if c then consumed = consumed + 1 end return c end
  local function skipSpace()
    while true do
      local c = peek()
      if c and (c == 32 or (c >= 9 and c <= 13)) then take() else break end
    end
  end
  while i <= #fmt do
    local f = fmt:sub(i, i)
    if f:find("%s") then
      skipSpace()
      i = i + 1
    elseif f ~= "%" then
      local c = peek()
      if c == nil then return n > 0 and n or -1 end
      if c ~= byte(f) then return n end
      take()
      i = i + 1
    elseif fmt:sub(i + 1, i + 1) == "%" then
      skipSpace()
      if peek() ~= 37 then return n end
      take()
      i = i + 2
    else
      i = i + 1
      local suppress = false
      if fmt:sub(i, i) == "*" then suppress = true; i = i + 1 end
      local w = fmt:match("^%d+", i)
      if w then i = i + #w end
      local width = w and tonumber(w) or math.huge
      local m = fmt:match("^[hlLqjzt]+", i)
      if m then i = i + #m end
      local conv = fmt:sub(i, i)
      i = i + 1
      local value
      if conv == "n" then
        if not suppress then local p = args[ai]; ai = ai + 1; p.a[p.i] = consumed end
        goto continue
      elseif conv == "c" then
        if peek() == nil then return n > 0 and n or -1 end
        local count = w and width or 1
        local p = not suppress and args[ai] or nil
        for k = 0, count - 1 do
          local c = take()
          if c == nil then break end
          if p then p.a[p.i + k] = c end
        end
        if not suppress then ai = ai + 1; n = n + 1 end
        goto continue
      elseif conv == "[" then
        local neg = fmt:sub(i, i) == "^"
        if neg then i = i + 1 end
        local close = fmt:find("]", i + 1, true) or #fmt
        local set = fmt:sub(i, close - 1)
        i = close + 1
        local members = {}
        local k = 1
        while k <= #set do
          if set:sub(k + 1, k + 1) == "-" and k + 2 <= #set then
            for b = byte(set, k), byte(set, k + 2) do members[b] = true end
            k = k + 3
          else
            members[byte(set, k)] = true
            k = k + 1
          end
        end
        local t = {}
        while #t < width do
          local c = peek()
          if c == nil or (members[c] or false) == neg then break end
          t[#t + 1] = char(take())
        end
        if #t == 0 then return peek() == nil and n == 0 and -1 or n end
        if not suppress then fromLua(concat(t), args[ai]); ai = ai + 1; n = n + 1 end
        goto continue
      end
      skipSpace()
      if peek() == nil then return n > 0 and n or -1 end
      if conv == "s" then
        local t = {}
        while #t < width do
          local c = peek()
          if c == nil or c == 32 or (c >= 9 and c <= 13) then break end
          t[#t + 1] = char(take())
        end
        if not suppress then fromLua(concat(t), args[ai]); ai = ai + 1; n = n + 1 end
      elseif conv == "f" or conv == "e" or conv == "g" or conv == "a" or conv == "E" or conv == "G" then
        local t = {}
        while #t < width do
          local c = peek()
          if c == nil or not char(c):find("[%d%.eE+%-]") then break end
          if (c == 43 or c == 45) and #t > 0 and not t[#t]:find("[eE]") then break end
          t[#t + 1] = char(take())
        end
        value = tonumber(concat(t))
        if not value then return n end
        if not suppress then local p = args[ai]; ai = ai + 1; p.a[p.i] = value + 0.0; n = n + 1 end
      else  -- d i u x X o p
        local base = (conv == "x" or conv == "X" or conv == "p") and 16 or conv == "o" and 8 or conv == "i" and 0 or 10
        local t = {}
        local c = peek()
        if (c == 45 or c == 43) and #t < width then t[1] = char(take()) end
        local digits = {}
        while #t + #digits < width do
          c = peek()
          if c == nil then break end
          local ch = char(c)
          if base == 0 then
            if #digits == 0 and ch == "0" then
              take()
              digits[1] = "0"
              local x = peek()
              if x == 120 or x == 88 then take(); base = 16; digits = {} else base = 8 end
              goto nextDigit
            end
            base = 10
          end
          if (base == 16 or base == 0) and #digits == 0 and ch == "0" then
            take()
            digits[1] = "0"
            local x = peek()
            if x == 120 or x == 88 then take(); digits = {} end
            goto nextDigit
          end
          do
            local d = tonumber(ch, 36)
            if not d or d >= base then break end
            digits[#digits + 1] = char(take())
          end
          ::nextDigit::
        end
        if #digits == 0 then return n end
        value = tonumber(concat(digits), base) or 0
        if t[1] == "-" then value = -value end
        if not suppress then local p = args[ai]; ai = ai + 1; p.a[p.i] = value; n = n + 1 end
      end
      ::continue::
    end
  end
  return n
end
function L.scanf(f, ...)
  return scanFormat(function()
    if inputPos > #inputBuf and not fill() then return nil end
    return byte(inputBuf, inputPos)
  end, function()
    if inputPos > #inputBuf and not fill() then return nil end
    local c = byte(inputBuf, inputPos)
    inputPos = inputPos + 1
    return c
  end, f, { ... })
end
function L.sscanf(s, f, ...)
  local text = tolua(s)
  local i = 1
  return scanFormat(function() return byte(text, i) end, function() local c = byte(text, i); if c then i = i + 1 end return c end, f, { ... })
end
function L.fgets(b, n, f)
  local l
  if f and f ~= R.stdin then
    if f.pos > #f.data then return nil end
    local e = f.data:find("\n", f.pos, true) or #f.data
    l = f.data:sub(f.pos, e)
    f.pos = e + 1
  else
    if inputPos <= #inputBuf then
      l = inputBuf:sub(inputPos)
      inputPos = #inputBuf + 1
    else
      local x = readKeyLine()
      if x == nil then return nil end
      l = x .. "\n"
    end
  end
  fromLua(l:sub(1, n - 1), b)
  return b
end
function L.gets(b) local x = readKeyLine(); if x == nil then return nil end fromLua(x, b); return b end
function L.strlen(s)
  if type_(s) == "string" then return #s end
  local a, i, n = s.a, s.i, 0
  while a[i + n] ~= 0 and a[i + n] ~= nil do n = n + 1 end
  return n
end
function L.strcpy(d, s) fromLua(tolua(s), d); return d end
function L.strncpy(d, s, n)
  local t = tolua(s):sub(1, n)
  for k = 1, n do d.a[d.i + k - 1] = byte(t, k) or 0 end
  return d
end
function L.strcat(d, s) local n = L.strlen(d); fromLua(tolua(s), { a = d.a, i = d.i + n }); return d end
function L.strncat(d, s, c) local n = L.strlen(d); fromLua(tolua(s):sub(1, c), { a = d.a, i = d.i + n }); return d end
function L.strcmp(a, b)
  if a == nil or b == nil or type_(a) == "string" or type_(b) == "string" then
    a, b = tolua(a), tolua(b)
    return a < b and -1 or (a > b and 1 or 0)
  end
  -- byte by byte, as unsigned chars
  local aa, ai, ba, bi = a.a, a.i, b.a, b.i
  local k = 0
  while true do
    local x, y = (aa[ai + k] or 0) & 255, (ba[bi + k] or 0) & 255
    if x ~= y then return x < y and -1 or 1 end
    if x == 0 then return 0 end
    k = k + 1
  end
end
function L.strncmp(a, b, n) a, b = tolua(a):sub(1, n), tolua(b):sub(1, n); return a < b and -1 or (a > b and 1 or 0) end
function L.strcasecmp(a, b) a, b = tolua(a):lower(), tolua(b):lower(); return a < b and -1 or (a > b and 1 or 0) end
function L.strchr(s, c)
  if type_(s) == "string" then s = R.cstr(s) end
  local i = s.i
  while true do
    local x = s.a[i]
    if x == c then return { a = s.a, i = i } end
    if x == 0 or x == nil then return nil end
    i = i + 1
  end
end
function L.strrchr(s, c)
  if type_(s) == "string" then s = R.cstr(s) end
  local i, found = s.i, nil
  while true do
    local x = s.a[i]
    if x == c then found = { a = s.a, i = i } end
    if x == 0 or x == nil then return found end
    i = i + 1
  end
end
function L.strstr(s, t)
  if type_(s) == "string" then s = R.cstr(s) end
  local a = tolua(s):find(tolua(t), 1, true)
  if not a then return nil end
  return { a = s.a, i = s.i + a - 1 }
end
function L.strdup(s) return { a = R.chararr(tolua(s)), i = 0 } end
local tokState
function L.strtok(s, delims)
  delims = tolua(delims)
  if s then tokState = s end
  if not tokState then return nil end
  local a, i = tokState.a, tokState.i
  while a[i] ~= 0 and a[i] ~= nil and delims:find(char(a[i]), 1, true) do i = i + 1 end
  if a[i] == 0 or a[i] == nil then tokState = nil; return nil end
  local start = i
  while a[i] ~= 0 and a[i] ~= nil and not delims:find(char(a[i]), 1, true) do i = i + 1 end
  if a[i] == 0 or a[i] == nil then tokState = nil
  else
    a[i] = 0
    tokState = { a = a, i = i + 1 }
  end
  return { a = a, i = start }
end
function L.memset(p, v, n)
  local mt_ = p and getmt(p.a)
  if mt_ and mt_.typedStruct then  -- structs in memory: they start again from zero
    for k in pairs(p.a) do if k >= p.i then p.a[k] = nil end end
    return p
  end
  if p and type_(rawget(p.a, p.i)) == "table" then
    local v = p.a[p.i]
    for k in pairs(v) do v[k] = nil end
    return p
  end
  local cnt = n
  -- the unit of a pointer is an element, not a byte: an array of ints has a fourth of the bytes
  if rawget(p.a, p.i) ~= nil and p.elemSize then cnt = n // p.elemSize end
  local a = p.a
  local i = p.i
  for k = 0, cnt - 1 do
    if rawget(a, i + k) == nil and k >= 1 and rawget(a, i + k - 1) ~= nil and not getmt(a) and k > 0 then break end
    a[i + k] = v
  end
  return p
end
function L.memcpy(d, s, n)
  local i = 0
  while i < n do
    local v = s.a[s.i + i]
    if v == nil then break end
    d.a[d.i + i] = v
    i = i + 1
  end
  return d
end
L.memmove = function(d, s, n)
  local t = {}
  local c = 0
  for i = 0, n - 1 do
    local v = s.a[s.i + i]
    if v == nil then break end
    t[i] = v
    c = i + 1
  end
  for i = 0, c - 1 do d.a[d.i + i] = t[i] end
  return d
end
function L.memcmp(a, b, n)
  for i = 0, n - 1 do
    local x, y = a.a[a.i + i], b.a[b.i + i]
    if x ~= y then return (x or 0) - (y or 0) end
  end
  return 0
end
local zeroMt = { __index = function() return 0 end }
function L.malloc() return { a = setmt({}, zeroMt), i = 0 } end
L.calloc = L.malloc
function L.realloc(p) if p then return p end return L.malloc() end
function L.free() end
function L.atoi(s) local v = tonumber(tolua(s):match("^%s*([+-]?%d+)")); return math.tointeger(v) or 0 end
L.atol = L.atoi
function L.atof(s) local v = tonumber(tolua(s):match("^%s*([+-]?%d*%.?%d*[eE]?[+-]?%d*)")); return (v or 0) + 0.0 end
function L.strtol(s, e, base)
  local t = tolua(s)
  local sp, sign = t:match("^(%s*)([+-]?)")
  local at = #sp + #sign + 1
  if base == 0 or base == nil then
    if t:sub(at, at + 1):lower() == "0x" then base = 16; at = at + 2
    elseif t:sub(at, at) == "0" then base = 8
    else base = 10 end
  elseif base == 16 and t:sub(at, at + 1):lower() == "0x" then at = at + 2 end
  local v, i = 0, at
  while i <= #t do
    local d = tonumber(t:sub(i, i), 36)
    if not d or d >= base then break end
    v = v * base + d
    i = i + 1
  end
  if type_(e) == "table" then
    if type_(s) == "string" then s = R.cstr(s) end
    e.a[e.i] = { a = s.a, i = s.i + (i > at and i - 1 or 0) }
  end
  return sign == "-" and -v or v
end
L.strtoul = L.strtol
L.labs = function(x) return x < 0 and -x or x end
function L.rand() return math.random(0, 2147483647) end
function L.srand(s) math.randomseed(s) end
L.random = L.rand
L.srandom = L.srand
function L.lrand48() return math.random(0, 2147483647) end
L.mrand48 = L.lrand48
function L.drand48() return math.random() end
function L.srand48(s) math.randomseed(s) end
function L.rand_r() return math.random(0, 2147483647) end
function L.arc4random() return math.random(0, 4294967295) end
function L.arc4random_uniform(n) return math.random(0, n - 1) end
function L.exit(c) error({ exit = c or 0 }, 0) end
function L.abort() error("Aborted", 0) end
function L.assert(c)
  if c == 0 or c == false or c == nil then error("Assertion failed", 0) end
end
function L.system(c) c = tolua(c); if sys and sys.shell then return sys.shell(c, true) or 0 end return 1 end
function L.clock() return sys and sys.millis and sys.millis() or 0 end
function L.sleep(s) if sys and sys.sleep then sys.sleep(s * 1000) end return 0 end
function L.usleep(s) if sys and sys.sleep then sys.sleep(s // 1000) end return 0 end
function L.delay(ms) if sys and sys.sleep then sys.sleep(ms) end end
for _, n in ipairs{ "sqrt", "sin", "cos", "tan", "asin", "acos", "exp", "fmod" } do local f = math[n]; L[n] = function(a, b) return f(a + 0.0, b) end end
function L.atan(x) return math.atan(x) end
function L.atan2(y, x) return math.atan(y, x) end
function L.log(x) if x == 0 then return -math.huge end return math.log(x) end
function L.log2(x) return math.log(x, 2) end
function L.log10(x) return math.log(x, 10) end
function L.pow(a, b) return (a + 0.0) ^ b end
function L.floor(x) return floor(x) + 0.0 end
function L.ceil(x) return math.ceil(x) + 0.0 end
function L.fabs(x) return math.abs(x) + 0.0 end
function L.round(x) return (x >= 0 and floor(x + 0.5) or -floor(-x + 0.5)) + 0.0 end
function L.trunc(x) return (x >= 0 and floor(x) or -floor(-x)) + 0.0 end
function L.hypot(a, b) return math.sqrt(a * a + b * b) end
function L.cbrt(x) return x < 0 and -((-x) ^ (1 / 3)) or x ^ (1 / 3) end
local function ct(p) return function(c) return (c >= 0 and c < 256 and char(c):find(p)) and 1 or 0 end end
L.isdigit, L.isalpha, L.isalnum, L.isspace, L.isupper, L.islower, L.ispunct, L.isxdigit, L.iscntrl = ct("%d"), ct("%a"), ct("%w"), ct("%s"), ct("%u"), ct("%l"), ct("%p"), ct("%x"), ct("%c")
function L.isprint(c) return (c >= 32 and c < 127) and 1 or 0 end
function L.isgraph(c) return (c > 32 and c < 127) and 1 or 0 end
function L.isblank(c) return (c == 32 or c == 9) and 1 or 0 end
function L.isascii(c) return (c >= 0 and c < 128) and 1 or 0 end
function L.toascii(c) return c & 127 end
function L.toupper(c) if c >= 97 and c <= 122 then return c - 32 end return c end
function L.tolower(c) if c >= 65 and c <= 90 then return c + 32 end return c end
-- files
R.stdin, R.stdout, R.stderr = { std = true, h = io.stdin }, { std = true, h = io.stdout }, { std = true, h = io.stderr }
local errnoBox = { a = { [0] = 0 }, i = 0 }
function L.__errno_location() return errnoBox end
local ERRNO = { [1] = "Operation not permitted", [2] = "No such file or directory", [5] = "Input/output error", [9] = "Bad file descriptor", [12] = "Cannot allocate memory", [13] = "Permission denied", [17] = "File exists", [20] = "Not a directory", [21] = "Is a directory", [22] = "Invalid argument", [28] = "No space left on device" }
local function failed(code, msg)
  errnoBox.a[0] = code or 5
  if msg and not code then
    for k, v in pairs(ERRNO) do if msg:find(v, 1, true) then errnoBox.a[0] = k end end
  end
end
function L.strerror(n)
  return R.cstr(ERRNO[n] or (n == 0 and "Success") or ("Unknown error " .. tostring(n)))
end
function L.perror(s)
  local p = s and tolua(s)
  local t = ERRNO[errnoBox.a[0]] or "Unknown error"
  io.stderr:write((p and p ~= "" and (p .. ": ") or "") .. t .. "\n")
end
function L.fopen(p, m)
  p = tolua(p); m = tolua(m)
  local h, e, code = io.open(p, m)
  if not h then failed(code or 2, e); return nil end
  return { h = h }
end
function L.freopen(p, m, f)
  if tolua(p) == "/dev/tty" or tolua(p) == "/dev/stdin" then return R.stdin end
  if f and f.h and not f.std then f.h:close() end
  return L.fopen(p, m)
end
function L.tmpfile() local h = io.tmpfile(); return h and { h = h } end
function L.popen(c, m) local h = io.popen(tolua(c), tolua(m)); return h and { h = h, pipe = true } end
function L.pclose(f) local a, b, c = f.h:close(); return c or (a and 0 or 1) end
function L.fclose(f)
  if f and f.h and not f.std then f.h:close() end
  return 0
end
function L.fprintf(f, fmt, ...)
  local s = format(fmt, { ... })
  if f == R.stdout then write(s) else f.h:write(s) end
  return #s
end
function L.fputs(s, f) s = tolua(s); if f == R.stdout then write(s) else f.h:write(s) end return 0 end
function L.fputc(c, f) local s = char(c & 255); if f == R.stdout then write(s) else f.h:write(s) end return c end
L.putc = L.fputc
function L.fwrite(p, size, n, f)
  local t = {}
  if type_(p) == "string" then t[1] = p:sub(1, size * n)
  else
    for k = 0, size * n - 1 do
      local v = p.a[p.i + k]
      t[k + 1] = char(mtype(v) == "integer" and v & 255 or 0)
    end
  end
  local s = concat(t)
  if f == R.stdout then write(s) else f.h:write(s) end
  return n
end
function L.fread(p, size, n, f)
  local s = (f == R.stdin and io.stdin or f.h):read(size * n)
  if not s then return 0 end
  for k = 1, #s do p.a[p.i + k - 1] = byte(s, k) end
  return #s // (size > 0 and size or 1)
end
local ungot = setmt({}, { __mode = "k" })
function L.fgetc(f)
  local u = ungot[f]
  if u then ungot[f] = nil; return u end
  if f == R.stdin then return getc() or -1 end
  local s = f.h:read(1)
  if not s then return -1 end
  return byte(s)
end
L.getc = L.fgetc
function L.ungetc(c, f) ungot[f] = c; return c end
function L.feof(f)
  if ungot[f] then return 0 end
  if f == R.stdin then
    if inputPos <= #inputBuf then return 0 end
    return fill() and 0 or 1
  end
  local at = f.h:seek("cur")
  local s = f.h:read(0)
  return s == nil and 1 or 0
end
function L.ferror() return 0 end
function L.clearerr() end
function L.fflush(f) if f and f.h then f.h:flush() end return 0 end
function L.setvbuf() return 0 end
function L.setbuf() end
function L.setlinebuf() end
function L.fseek(f, off, w)
  local r = f.h:seek(w == 1 and "cur" or w == 2 and "end" or "set", off)
  ungot[f] = nil
  return r and 0 or -1
end
L.fseeko = L.fseek
function L.ftell(f) return f.h:seek("cur") or -1 end
L.ftello = L.ftell
function L.rewind(f) f.h:seek("set", 0); ungot[f] = nil end
local function fgetsRaw(n, f)
  if f == R.stdin then
    if inputPos > #inputBuf and not fill() then return nil end
    local e = inputBuf:find("\n", inputPos, true) or #inputBuf
    local l = inputBuf:sub(inputPos, e)
    inputPos = e + 1
    return l
  end
  local u = ungot[f]
  local l = f.h:read("L")
  if u then ungot[f] = nil; l = char(u) .. (l or "") end
  return l
end
function L.fgets(b, n, f)
  local l = fgetsRaw(n, f or R.stdin)
  if not l then return nil end
  if #l > n - 1 then
    if f and f ~= R.stdin then f.h:seek("cur", n - 1 - #l) end
    l = l:sub(1, n - 1)
  end
  fromLua(l, b)
  return b
end
-- getline(&line, &n, f)
function L.getline(lp, np, f)
  local l = fgetsRaw(0, f or R.stdin)
  if not l then return -1 end
  lp.a[lp.i] = { a = R.chararr(l), i = 0 }
  if np then np.a[np.i] = #l + 1 end
  return #l
end
function L.getdelim(lp, np, d, f) return L.getline(lp, np, f) end
function L.fscanf(f, fmt, ...)
  if f == R.stdin then return L.scanf(fmt, ...) end
  local h = f.h
  local look
  return scanFormat(function()
    if look == nil then
      local x = h:read(1)
      look = x and byte(x) or false
    end
    return look or nil
  end, function()
    if look == nil then local x = h:read(1); look = x and byte(x) or false end
    local c = look
    look = nil
    return c or nil
  end, fmt, { ... })
end
function L.remove(p) local ok, e, c = os.remove(tolua(p)); if ok then return 0 end failed(c, e); return -1 end
function L.rename(a, b) local ok, e, c = os.rename(tolua(a), tolua(b)); if ok then return 0 end failed(c, e); return -1 end
L.unlink = L.remove
-- what programs ask of the system
function L.getenv(n)
  local v = os.getenv(tolua(n))
  return v and R.cstr(v) or nil
end
function L.setenv(n, v) if os.setenv then os.setenv(tolua(n), tolua(v)) end return 0 end
function L.isatty(fd) return 1 end
function L.getuid() return 1000 end
L.geteuid, L.getgid, L.getegid = L.getuid, L.getuid, L.getuid
function L.getpid() return 1 end
L.getppid = L.getpid
function L.gethostname(b, n) fromLua((sys and sys.hostname and sys.hostname() or "esp"):sub(1, n - 1), b); return 0 end
function L.getlogin() return R.cstr(sys and sys.user and sys.user() or "user") end
function L.getpwuid()
  local u = sys and sys.user and sys.user() or "user"
  return { a = { [0] = { pw_name = R.cstr(u), pw_dir = R.cstr(os.getenv("HOME") or "/home/user"), pw_shell = R.cstr("/bin/sh"), pw_uid = 1000, pw_gid = 1000, pw_gecos = R.cstr(u) } }, i = 0 }
end
L.getpwnam = L.getpwuid
function L.getgrgid() return { a = { [0] = { gr_name = R.cstr("user"), gr_gid = 1000 } }, i = 0 } end
function L.setlocale() return R.cstr("C") end
function L.bindtextdomain() return nil end
function L.textdomain() return nil end
function L.gettext(s) return s end
function L.nl_langinfo() return R.cstr("UTF-8") end
function L.signal(sig, h) handlers[sig] = h; return nil end
function L.sigaction(sig, act)
  if act then handlers[sig] = act.a[act.i].sa_handler end
  return 0
end
function L.sigemptyset() return 0 end
L.sigfillset, L.sigaddset, L.sigdelset, L.sigprocmask, L.pthread_sigmask = L.sigemptyset, L.sigemptyset, L.sigemptyset, L.sigemptyset, L.sigemptyset
function L.setitimer(which, new)
  local v = new and new.a[new.i]
  if type_(v) ~= "table" then return 0 end
  local function ms(t) return t and ((t.tv_sec or 0) * 1000 + (t.tv_usec or 0) // 1000) or 0 end
  local value, interval = ms(v.it_value), ms(v.it_interval)
  if value == 0 and interval == 0 then timer = nil else timer = { next = sys.millis() + (value > 0 and value or interval), interval = interval } end
  return 0
end
function L.getitimer() return 0 end
function L.pause() sys.sleep(50) return -1 end
function L.raise() return 0 end
function L.alarm(n) if n > 0 then timer = { next = sys.millis() + n * 1000, interval = 0 } else timer = nil end return 0 end
function L.atexit(f) R.atExit = R.atExit or {}; table.insert(R.atExit, f); return 0 end
function L.getcwd(b, n)
  local d = (lfs and lfs.currentdir and lfs.currentdir()) or os.getenv("PWD") or "/"
  if not b then return R.cstr(d) end
  fromLua(d, b)
  return b
end
function L.chdir(p) local ok, e = lfs.chdir(tolua(p)); if ok then return 0 end failed(2, e); return -1 end
function L.mkdir(p) local ok, e = lfs.mkdir(tolua(p)); if ok then return 0 end failed(nil, e); return -1 end
function L.rmdir(p) local ok, e = lfs.rmdir(tolua(p)); if ok then return 0 end failed(nil, e); return -1 end
function L.access(p) local h = io.open(tolua(p), "r"); if h then h:close(); return 0 end failed(2); return -1 end
local function fillStat(p, st)
  local a = lfs.attributes(p)
  if not a then failed(2); return -1 end
  local v = st.a[st.i]
  v.st_size = a.size or 0
  v.st_mode = a.mode == "directory" and 16877 or 33188
  v.st_mtime = a.modification or 0
  v.st_atime, v.st_ctime = v.st_mtime, v.st_mtime
  v.st_uid, v.st_gid, v.st_nlink, v.st_ino, v.st_dev = 1000, 1000, 1, 0, 0
  v.st_blocks, v.st_blksize = (v.st_size + 511) // 512, 512
  return 0
end
function L.stat(p, st) return fillStat(tolua(p), st) end
L.lstat = L.stat
function L.fstat() return -1 end
function L.chmod() return 0 end
function L.chown() return 0 end
function L.umask() return 18 end
function L.utime() return 0 end
function L.sync() end
-- folders
function L.opendir(p)
  p = tolua(p)
  if not lfs.attributes(p) then failed(2); return nil end
  local names = {}
  for n in lfs.dir(p) do names[#names + 1] = n end
  table.sort(names)
  return { names = names, at = 0, path = p }
end
function L.readdir(d)
  d.at = d.at + 1
  local n = d.names[d.at]
  if not n then return nil end
  local a = lfs.attributes(d.path .. "/" .. n)
  return { a = { [0] = { d_name = { a = R.chararr(n), i = 0 }, d_type = a and a.mode == "directory" and 4 or 8, d_ino = d.at } }, i = 0 }
end
function L.closedir() return 0 end
function L.rewinddir(d) d.at = 0 end
-- time
local function tmOf(t, utc)
  local d = os.date(utc and "!*t" or "*t", t)
  return { tm_sec = d.sec, tm_min = d.min, tm_hour = d.hour, tm_mday = d.day, tm_mon = d.month - 1, tm_year = d.year - 1900, tm_wday = d.wday - 1, tm_yday = d.yday - 1, tm_isdst = d.isdst and 1 or 0 }
end
function L.time(p) local t = os.time(); if p then p.a[p.i] = t end return t end
function L.localtime(p) return { a = { [0] = tmOf(p.a[p.i], false) }, i = 0 } end
function L.gmtime(p) return { a = { [0] = tmOf(p.a[p.i], true) }, i = 0 } end
L.localtime_r = function(p, r) local v = tmOf(p.a[p.i], false); for k, x in pairs(v) do r.a[r.i][k] = x end return r end
L.gmtime_r = function(p, r) local v = tmOf(p.a[p.i], true); for k, x in pairs(v) do r.a[r.i][k] = x end return r end
function L.mktime(p)
  local v = p.a[p.i]
  return os.time{ year = v.tm_year + 1900, month = v.tm_mon + 1, day = v.tm_mday, hour = v.tm_hour, min = v.tm_min, sec = v.tm_sec }
end
L.timegm = L.mktime
function L.difftime(a, b) return (a - b) + 0.0 end
function L.strftime(b, n, f, p)
  local v = p.a[p.i]
  local t = os.time{ year = v.tm_year + 1900, month = v.tm_mon + 1, day = v.tm_mday, hour = v.tm_hour, min = v.tm_min, sec = v.tm_sec }
  local s = os.date(tolua(f), t):sub(1, n - 1)
  fromLua(s, b)
  return #s
end
function L.ctime(p) return R.cstr(os.date("%a %b %e %H:%M:%S %Y\n", p.a[p.i])) end
function L.asctime(p) return R.cstr(os.date("%a %b %e %H:%M:%S %Y\n", L.mktime(p))) end
function L.clock() return floor(os.clock() * 1000000) end
function L.gettimeofday(p)
  if p then local v = p.a[p.i]; v.tv_sec = os.time(); v.tv_usec = 0 end
  return 0
end
function L.clock_gettime(_, p)
  local v = p.a[p.i]; local c = os.clock()
  v.tv_sec = floor(c); v.tv_nsec = floor((c - floor(c)) * 1e9)
  return 0
end
function L.sleep(n) sleepMs(n * 1000); return 0 end
function L.usleep(n) sleepMs(n // 1000); return 0 end
function L.nanosleep(p) local v = p.a[p.i]; if sys and sys.sleep then sys.sleep(v.tv_sec * 1000 + (v.tv_nsec or 0) // 1000000) end return 0 end
function L.ioctl(_, req, p)
  if req == 21531 then  -- FIONREAD: how many bytes wait on stdin
    if not R.stdinText then
      if rawKeys then
        if p then p.a[p.i] = (#rawQueue > 0) and #rawQueue or 0 end
        return 0
      end
      local all = io and io.stdin and io.stdin:read("a")
      if all then R.stdinText = all end
    end
    if p then p.a[p.i] = #(R.stdinText or "") end
    return 0
  end
  if p then
    local v = p.a[p.i]
    if type_(v) == "table" then
      local w, h = 80, 24
      if term and term.size then w, h = term.size() end
      v.ws_row, v.ws_col = h, w
    end
  end
  return 0
end
function L.tcgetattr(fd, p)
  if p then
    local v = p.a[p.i]
    if type_(v) == "table" then
      v.c_iflag, v.c_oflag, v.c_cflag, v.c_lflag = 0, 0, 0, rawKeys and 0 or 10
      v.c_cc = R.arr and R.arr(32, 0) or {}
      v.c_cc[6], v.c_cc[5] = rawMin, rawTime
    end
  end
  return 0
end
function L.tcsetattr(fd, when, p)
  local v = p and p.a[p.i]
  if type_(v) == "table" then
    rawKeys = ((v.c_lflag or 10) & 2) == 0
    local cc = v.c_cc
    if type_(cc) == "table" then rawMin, rawTime = cc[6] or 1, cc[5] or 0 end
  end
  return 0
end
function L.cfmakeraw(p)
  local v = p and p.a[p.i]
  if type_(v) == "table" then v.c_lflag = 0 end
end
function L.tcflush() return 0 end
function L.tcdrain() return 0 end
-- select on the keyboard: ready when a key waits
local selReady = false
function L.select(n, r, w, e, tv)
  local wait = -1
  if type_(tv) == "table" then
    local t = tv.a[tv.i]
    wait = ((t.tv_sec or 0) * 1000) + ((t.tv_usec or 0) // 1000)
  end
  selReady = false
  if #rawQueue > 0 or (rawKeys and key and key.poll) then
    local c = pollRaw(wait)
    if c then table.insert(rawQueue, 1, c); selReady = true; return 1 end
    return 0
  end
  if inputPos <= #inputBuf or (sys.piped and sys.piped()) then selReady = true; return 1 end
  if wait > 0 and sys and sys.sleep then sys.sleep(wait) end
  return 0
end
function L.__fd_isset() return selReady and 1 or 0 end
-- the network interfaces of the device: the radio as wlan0 and the loopback, with the data of the wifi module
local function ipInt(ip)
  local a, b, c, d = tostring(ip or "0.0.0.0"):match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
  return (tonumber(a) or 0) | ((tonumber(b) or 0) << 8) | ((tonumber(c) or 0) << 16) | ((tonumber(d) or 0) << 24)
end
local function ifaces()
  local st = wifi and wifi.status and wifi.status() or {}
  local list = { { name = "lo", ip = "127.0.0.1", mask = "255.0.0.0", flags = 0x49, index = 1, mac = "00:00:00:00:00:00" } }
  list[2] = { name = "wlan0", ip = st.ip or "0.0.0.0", mask = st.netmask or "255.255.255.0", flags = st.connected and 0x1043 or 0x1002, index = 2, mac = st.mac or "00:00:00:00:00:00" }
  return list
end
local function sockaddrIn(ip) return { a = { [0] = { sa_family = 2, sin_family = 2, sin_port = 0, sin_addr = { s_addr = ipInt(ip) } } }, i = 0 } end
function L.getifaddrs(pp)
  local first, prev
  for _, f in ipairs(ifaces()) do
    local node = { ifa_name = R.cstr(f.name), ifa_flags = f.flags, ifa_addr = sockaddrIn(f.ip), ifa_netmask = sockaddrIn(f.mask), ifa_broadaddr = nil, ifa_next = nil }
    local p = { a = { [0] = node }, i = 0 }
    if prev then prev.a[0].ifa_next = p else first = p end
    prev = p
  end
  pp.a[pp.i] = first
  return 0
end
function L.freeifaddrs() end
function L.if_nametoindex(n) n = tolua(n); for _, f in ipairs(ifaces()) do if f.name == n then return f.index end end failed(19) return 0 end
function L.if_indextoname(i, b) for _, f in ipairs(ifaces()) do if f.index == i then fromLua(f.name, b) return b end end return nil end
local IFREQ = { [35093] = "ip", [35099] = "mask", [35091] = "flags", [35123] = "index", [35111] = "mac" }
local ioctlOld = L.ioctl
function L.ioctl(fd, req, p)
  local what = IFREQ[req]
  if what and p then
    local v = p.a[p.i]
    local name = v and v.ifr_name and tolua(v.ifr_name)
    for _, f in ipairs(ifaces()) do
      if f.name == name then
        if what == "ip" or what == "mask" then v.ifr_addr = sockaddrIn(what == "ip" and f.ip or f.mask).a[0]
        elseif what == "flags" then v.ifr_flags = f.flags
        elseif what == "index" then v.ifr_ifindex = f.index
        else local h = { sa_family = 1 }; local k = 0; for hx in f.mac:gmatch("%x%x") do h[k] = tonumber(hx, 16); k = k + 1 end v.ifr_hwaddr = h end
        return 0
      end
    end
    failed(19)
    return -1
  end
  return ioctlOld(fd, req, p)
end
-- the loader of libraries: there is none, so a program that wants a plugin hears that it is not there
function L.dlopen() return nil end
function L.dlsym() return nil end
function L.dlclose() return 0 end
function L.dlerror() return R.cstr("dynamic libraries are not supported on this device") end
function L.setjmp() return 0 end
function L.longjmp() error("longjmp is not supported", 0) end
L.sigsetjmp, L.siglongjmp, L._setjmp = L.setjmp, L.longjmp, L.setjmp
-- file descriptors: a number for a handle of io
local fds = { [0] = R.stdin, [1] = R.stdout, [2] = R.stderr }
local nextFd = 3
local function newFd(f)
  local n = nextFd
  nextFd = n + 1
  fds[n] = f
  f.fd = n
  return n
end
function L.open(p, flags)
  p = tolua(p)
  flags = flags or 0
  if p == "/dev/urandom" or p == "/dev/random" then return newFd({ random = true }) end
  local mode = "rb"
  if flags & 3 ~= 0 then
    if flags & 1024 ~= 0 then mode = "ab"
    elseif flags & 512 ~= 0 then mode = "wb"
    elseif flags & 64 ~= 0 then
      local h = io.open(p, "rb")
      if h then h:close(); mode = "r+b" else mode = "wb" end
    else mode = "r+b" end
  end
  local h, e, c = io.open(p, mode)
  if not h then failed(c or 2, e); return -1 end
  return newFd({ h = h })
end
function L.close(fd)
  local f = fds[fd]
  if f and f.h and not f.std then f.h:close() end
  fds[fd] = nil
  return f and 0 or -1
end
function L.write(fd, p, n)
  local s
  if type_(p) == "string" then s = p:sub(1, n)
  else
    local t = {}
    for k = 0, n - 1 do t[k + 1] = char((p.a[p.i + k] or 0) & 255) end
    s = concat(t)
  end
  if fd == 1 then write(s)
  elseif fd == 2 then io.stderr:write(s)
  elseif fds[fd] and fds[fd].h then fds[fd].h:write(s)
  else failed(9); return -1 end
  return n
end
function L.read(fd, p, n)
  if fd == 0 and R.stdinText then
    local t = R.stdinText
    if t == "" then return 0 end
    local chunk = t:sub(1, n)
    R.stdinText = t:sub(#chunk + 1)
    for k = 1, #chunk do p.a[p.i + k - 1] = byte(chunk, k) end
    return #chunk
  end
  if fd == 0 and rawKeys and not R.stdinText then
    local c = pollRaw(rawMin == 0 and rawTime * 100 or -1)
    if not c then return 0 end
    p.a[p.i] = c
    return 1
  end
  local f = fds[fd]
  if not f then failed(9); return -1 end
  if f.random then
    for k = 0, n - 1 do p.a[p.i + k] = math.random(0, 255) end
    return n
  end
  local s = (f.h or io.stdin):read(n)
  if not s then return 0 end
  for k = 1, #s do p.a[p.i + k - 1] = byte(s, k) end
  return #s
end
function L.lseek(fd, off, w)
  local f = fds[fd]
  if not (f and f.h) then return -1 end
  return f.h:seek(w == 1 and "cur" or w == 2 and "end" or "set", off) or -1
end
function L.mkstemp(t)
  local s = tolua(t)
  for _ = 1, 50 do
    local name = s:gsub("XXXXXX$", function()
      local o = {}
      for k = 1, 6 do o[k] = char(math.random(97, 122)) end
      return concat(o)
    end)
    local h0 = io.open(name, "rb")
    if h0 then h0:close()
    else
      local h, e, c = io.open(name, "w+b")
      if not h then failed(c or 13, e); return -1 end
      fromLua(name, t)
      return newFd({ h = h, path = name })
    end
  end
  return -1
end
function L.mkdtemp(t)
  local name = tolua(t):gsub("XXXXXX$", tostring(math.random(100000, 999999)))
  if not lfs.mkdir(name) then return nil end
  fromLua(name, t)
  return t
end
function L.fdopen(fd) return fds[fd] end
function L.fileno(f)
  if f == R.stdin then return 0 elseif f == R.stdout then return 1 elseif f == R.stderr then return 2 end
  if not f.fd then newFd(f) end
  return f.fd
end
-- more of string.h and stdlib.h
L.strcmpi, L.stricmp = L.strcasecmp, L.strcasecmp
function L.S_ISDIR(m) return (m & 61440) == 16384 and 1 or 0 end
function L.S_ISREG(m) return (m & 61440) == 32768 and 1 or 0 end
function L.S_ISLNK(m) return 0 end
function L.strncasecmp(a, b, n) a, b = tolua(a):sub(1, n):lower(), tolua(b):sub(1, n):lower(); return a < b and -1 or (a > b and 1 or 0) end
function L.strcasestr(s, t)
  if type_(s) == "string" then s = R.cstr(s) end
  local a = tolua(s):lower():find(tolua(t):lower(), 1, true)
  return a and { a = s.a, i = s.i + a - 1 } or nil
end
function L.strndup(s, n) return { a = R.chararr(tolua(s):sub(1, n)), i = 0 } end
function L.strnlen(s, n) return math.min(L.strlen(s), n) end
function L.strspn(s, set)
  s, set = tolua(s), tolua(set)
  local n = 0
  while n < #s and set:find(s:sub(n + 1, n + 1), 1, true) do n = n + 1 end
  return n
end
function L.strcspn(s, set)
  s, set = tolua(s), tolua(set)
  local n = 0
  while n < #s and not set:find(s:sub(n + 1, n + 1), 1, true) do n = n + 1 end
  return n
end
function L.strpbrk(s, set)
  if type_(s) == "string" then s = R.cstr(s) end
  local n = L.strcspn(s, set)
  if s.a[s.i + n] == 0 or s.a[s.i + n] == nil then return nil end
  return { a = s.a, i = s.i + n }
end
function L.strsep(sp, d)
  local s = sp.a[sp.i]
  if s == nil then return nil end
  local n = L.strcspn(s, d)
  if s.a[s.i + n] == 0 or s.a[s.i + n] == nil then sp.a[sp.i] = nil
  else s.a[s.i + n] = 0; sp.a[sp.i] = { a = s.a, i = s.i + n + 1 } end
  return s
end
function L.stpcpy(d, s) local t = tolua(s); fromLua(t, d); return { a = d.a, i = d.i + #t } end
function L.memchr(s, c, n)
  if type_(s) == "string" then s = R.cstr(s) end
  for k = 0, n - 1 do if s.a[s.i + k] == c then return { a = s.a, i = s.i + k } end end
  return nil
end
function L.strtod(s, e)
  local t = tolua(s)
  local m = t:match("^%s*[-+]?%d*%.?%d*[eE]?[-+]?%d*") or ""
  local v = tonumber(m)
  while not v and #m > 0 do m = m:sub(1, -2); v = tonumber(m) end
  if e then e.a[e.i] = { a = s.a, i = s.i + #m } end
  return (v or 0) + 0.0
end
L.strtof, L.strtold = L.strtod, L.strtod
L.strtoll, L.strtoull = L.strtol, L.strtoul
L.atoll = L.atol
function L.abs(x) return x < 0 and -x or x end
L.llabs = L.abs
function L.basename(p) local s = tolua(p):gsub("/+$", ""); return R.cstr(s:match("([^/]*)$")) end
function L.dirname(p) local s = tolua(p):gsub("/+$", ""); local d = s:match("^(.*)/[^/]*$"); return R.cstr(d == "" and "/" or d or ".") end
function L.qsort(p, n, size, cmp)
  local items = {}
  for k = 1, n do items[k] = p.a[p.i + (k - 1) * (size_units and 1 or 1)] end
  -- two pointers made once and filled for each comparison (not two new ones every time)
  local ba, bb = { a = {}, i = 0 }, { a = {}, i = 0 }
  local aa, ab = ba.a, bb.a
  local function lt(x, y) aa[0] = x; ab[0] = y; return cmp(ba, bb) < 0 end
  local s = mergeSort(items, n, lt)
  for k = 1, n do p.a[p.i + k - 1] = s[k] end
end
function L.bsearch(key, p, n, size, cmp)
  local lo, hi = 0, n - 1
  while lo <= hi do
    local mid = (lo + hi) // 2
    local c = cmp(key, { a = p.a, i = p.i + mid })
    if c == 0 then return { a = p.a, i = p.i + mid } end
    if c < 0 then hi = mid - 1 else lo = mid + 1 end
  end
  return nil
end
-- variable arguments
function R.vaStart(set, ...) set({ n = select("#", ...), at = 0, ... }) end
function R.vaArg(ap) ap.at = ap.at + 1; return ap[ap.at] end
function R.vaCopy(set, ap)
  local c = {}
  for k, v in pairs(ap) do c[k] = v end
  set(c)
end
local function vaRest(ap)
  local t = {}
  for k = ap.at + 1, ap.n do t[k - ap.at] = ap[k] end
  return t
end
function L.vprintf(f, ap) local s = format(f, vaRest(ap)); write(s); return #s end
function L.vfprintf(o, f, ap) local s = format(f, vaRest(ap)); if o == R.stdout then write(s) else o.h:write(s) end return #s end
function L.vsprintf(b, f, ap) local s = format(f, vaRest(ap)); fromLua(s, b); return #s end
function L.vsnprintf(b, n, f, ap)
  local s = format(f, vaRest(ap))
  if b and n > 0 then fromLua(s:sub(1, n - 1), b) end
  return #s
end
function L.fcntl() return 0 end
L.alloca = L.malloc
function L.mvcur() return 0 end
L.savetty, L.resetty, L.def_prog_mode, L.reset_prog_mode, L.def_shell_mode, L.reset_shell_mode, L.set_escdelay = L.mvcur, L.mvcur, L.mvcur, L.mvcur, L.mvcur, L.mvcur, L.mvcur
function L.getbegyx() return 0 end
function L.dup() return 3 end
function L.dup2() return 0 end
function L.pipe() return -1 end
function L.fork() return -1 end
function L.getpagesize() return 4096 end
function L.sysconf() return 4096 end
function L.wcwidth() return 1 end
function L.mbrtowc(pwc, s, n, ps)
  local c = s and s.a[s.i]
  if c == nil or c == 0 then if pwc then pwc.a[pwc.i] = 0 end return 0 end
  if pwc then pwc.a[pwc.i] = c end
  return 1
end
function L.mbstowcs(d, s, n) local t = tolua(s); if d then for k = 1, math.min(#t, n) do d.a[d.i + k - 1] = byte(t, k) end d.a[d.i + #t] = 0 end return #t end
function L.wcstombs(d, s, n) local o = {}; local k = 0; while s.a[s.i + k] ~= 0 and s.a[s.i + k] ~= nil do o[#o + 1] = char(s.a[s.i + k] & 255); k = k + 1 end if d then fromLua(concat(o), d) end return k end
function L.wcslen(s) local k = 0; while s.a[s.i + k] ~= 0 and s.a[s.i + k] ~= nil do k = k + 1 end return k end
function L.towupper(c) return L.toupper(c) end
function L.towlower(c) return L.tolower(c) end
L.iswalpha, L.iswdigit, L.iswspace, L.iswprint = L.isalpha, L.isdigit, L.isspace, L.isprint
function L.mbsinit() return 1 end
function L.mblen() return 1 end
-- getopt and getopt_long
local optargBox, optindBox, opterrBox, optoptBox = { a = { [0] = false }, i = 0 }, { a = { [0] = 1 }, i = 0 }, { a = { [0] = 1 }, i = 0 }, { a = { [0] = 0 }, i = 0 }
optargBox.a[0] = nil
function L.__optarg() return optargBox end
function L.__optind() return optindBox end
function L.__opterr() return opterrBox end
function L.__optopt() return optoptBox end
local optSub = 1
local function getoptBase(argc, argv, spec, long, idx)
  spec = tolua(spec)
  local colon = spec:sub(1, 1) == ":"
  optargBox.a[0] = nil
  while true do
    local ind = optindBox.a[0]
    if ind >= argc then return -1 end
    local a = tolua(argv.a[argv.i + ind])
    if optSub == 1 then
      if a == "--" then optindBox.a[0] = ind + 1; return -1 end
      if a:sub(1, 1) ~= "-" or a == "-" then
        -- GNU moves the other words to the end: the options after them are found too
        local moved = false
        for j = ind + 1, argc - 1 do
          local w = tolua(argv.a[argv.i + j])
          if w:sub(1, 1) == "-" and w ~= "-" then
            local item = argv.a[argv.i + j]
            for k = j, ind + 1, -1 do argv.a[argv.i + k] = argv.a[argv.i + k - 1] end
            argv.a[argv.i + ind] = item
            R.__gnuMoved = (R.__gnuMoved or 0) + 1
            moved = true
            break
          end
        end
        if not moved then return -1 end
        a = tolua(argv.a[argv.i + ind])
        if a == "--" then optindBox.a[0] = ind + 1; return -1 end
      end
      if long and a:sub(1, 2) == "--" then
        local name, val = a:sub(3):match("^([^=]*)=?(.*)$")
        local hasEq = a:find("=", 1, true) ~= nil
        local k = 0
        while true do
          local o = long.a[long.i + k]
          if not o or o.name == nil or o.name == 0 then break end
          if tolua(o.name) == name or tolua(o.name):sub(1, #name) == name then
            optindBox.a[0] = ind + 1
            if type_(idx) == "table" then idx.a[idx.i] = k end
            if o.has_arg == 1 or o.has_arg == 2 then
              if hasEq then optargBox.a[0] = { a = R.chararr(val), i = 0 }
              elseif o.has_arg == 1 then
                if optindBox.a[0] < argc then optargBox.a[0] = argv.a[argv.i + optindBox.a[0]]; optindBox.a[0] = optindBox.a[0] + 1
                else
                  if opterrBox.a[0] ~= 0 then io.stderr:write(tolua(argv.a[argv.i]) .. ": option '--" .. name .. "' requires an argument\n") end
                  return colon and 58 or 63
                end
              end
            end
            if type_(o.flag) == "table" then o.flag.a[o.flag.i] = o.val; return 0 end
            return o.val
          end
          k = k + 1
        end
        optindBox.a[0] = ind + 1
        if opterrBox.a[0] ~= 0 then io.stderr:write(tolua(argv.a[argv.i]) .. ": unrecognized option '" .. a .. "'\n") end
        return 63
      end
    end
    local c = a:sub(optSub + 1, optSub + 1)
    local at = c ~= ":" and spec:find(c, 1, true)
    optSub = optSub + 1
    local done = optSub >= #a
    if not at then
      if done then optindBox.a[0] = ind + 1; optSub = 1 end
      optoptBox.a[0] = byte(c)
      if opterrBox.a[0] ~= 0 and not colon then io.stderr:write(tolua(argv.a[argv.i]) .. ": invalid option -- '" .. c .. "'\n") end
      return 63
    end
    if spec:sub(at + 1, at + 1) == ":" then
      local optional = spec:sub(at + 2, at + 2) == ":"
      if not done then optargBox.a[0] = { a = R.chararr(a:sub(optSub + 1)), i = 0 }; optindBox.a[0] = ind + 1
      elseif optional then optindBox.a[0] = ind + 1
      elseif ind + 1 < argc then optargBox.a[0] = argv.a[argv.i + ind + 1]; optindBox.a[0] = ind + 2
      else
        optindBox.a[0] = ind + 1
        optSub = 1
        optoptBox.a[0] = byte(c)
        if colon then return 58 end
        if opterrBox.a[0] ~= 0 then io.stderr:write(tolua(argv.a[argv.i]) .. ": option requires an argument -- '" .. c .. "'\n") end
        return 63
      end
      optSub = 1
    elseif done then
      optindBox.a[0] = ind + 1
      optSub = 1
    end
    return byte(c)
  end
end
function L.getopt(argc, argv, spec) return getoptBase(argc, argv, spec) end
function L.getopt_long(argc, argv, spec, long, idx) return getoptBase(argc, argv, spec, long, idx) end
L.getopt_long_only = L.getopt_long
-- ncurses on the text grid of the device: windows, panels, colours, keys (the picture is made with term.*)
local pairsT = {}
local CNAME = { [0] = "dim", "red", "green", "yellow", "blue", "magenta", "cyan", "white" }
local function gridSize() local w, h = term.size(); return w, h end
local stdscr
local function newWindow(h, w, y, x)
  return { win = true, h = h, w = w, oy = y, ox = x, y = 0, x = 0, attr = 0, delay = -1, bkgd = 32 }
end
local function std()
  if not stdscr then local w, h = gridSize(); stdscr = newWindow(h, w, 0, 0) end
  return stdscr
end
local linesBox, colsBox = { a = {}, i = 0 }, { a = {}, i = 0 }
function L.__LINESP() local s = std(); linesBox.a[0], colsBox.a[0] = s.h, s.w; return linesBox end
function L.__COLSP() L.__LINESP(); return colsBox end
function L.initscr() term.fullscreen(true); term.clear(); stdscr = nil; return std() end
function L.newterm() return L.initscr() end
function L.set_term(s) return s end
function L.delscreen() return nil end
function L.endwin() term.fullscreen(false); return 0 end
function L.isendwin() return 0 end
local function ok() return 0 end
for _, n in ipairs{ "cbreak", "nocbreak", "raw", "noraw", "echo", "noecho", "nonl", "nl", "intrflush", "leaveok", "scrollok", "idlok", "clearok", "meta", "start_color", "use_default_colors", "typeahead", "flushinp", "beep", "flash", "notimeout", "immedok", "resizeterm", "doupdate", "keypad", "wnoutrefresh", "touchwin", "redrawwin", "wtouchln", "wsetscrreg", "setscrreg", "def_prog_mode", "reset_prog_mode", "def_shell_mode", "reset_shell_mode", "savetty", "resetty", "set_escdelay", "mvcur", "assume_default_colors", "cbreak", "slk_init", "wredrawln", "idcok", "syncok", "is_term_resized", "update_panels", "top_panel", "bottom_panel", "show_panel", "hide_panel", "ungetch", "move_panel_noop" } do L[n] = ok end
function L.doupdate() term.flush(); return 0 end
function L.has_colors() return 1 end
function L.can_change_color() return 0 end
function L.init_pair(n, f, b) pairsT[n] = { fg = CNAME[f] or "text", bg = (b and b ~= 0 and b ~= -1) and CNAME[b] or nil }; return 0 end
function L.init_color() return 0 end
function L.curs_set() return 1 end
function L.napms(n) sleepMs(n); return 0 end
function L.halfdelay(t) std().delay = t * 100; return 0 end
function L.COLOR_PAIR(n) return n << 8 end
function L.PAIR_NUMBER(a) return (a >> 8) & 255 end
local function wrapWin(f) return function(win, ...) return f(win or std(), ...) end end
local function attrColor(win, extra)
  local a = win.attr | (extra or 0)
  if (a & 0xFF00) == 0 then a = a | (win.bkgdAttr or 0) end
  local pr = pairsT[(a >> 8) & 255]
  local c = pr and pr.fg or "text"
  if pr and pr.bg then
    if a & 2097152 ~= 0 then c = "white" end
    return "inverse-" .. pr.bg  -- the block of the background colour; the letter on it is dark
  end
  if a & 65536 ~= 0 then return c == "text" and "inverse" or ("inverse-" .. c) end
  if a & 2097152 ~= 0 and c == "text" then return "white" end
  return c
end
local function cell(win, y, x, ch, color)
  if y < 0 or x < 0 or y >= win.h or x >= win.w then return end
  local bc = win.bc
  if not bc then bc = {}; win.bc = bc; win.bk = {} end
  bc[y * win.w + x] = ch
  win.bk[y * win.w + x] = color
  if not win.pad then term.put(win.ox + x, win.oy + y, ch, color) end
end
local function putText(win, s, extra)
  local color = attrColor(win, extra)
  for k = 1, #s do
    local c = s:sub(k, k)
    if c == "\n" then
      for x = win.x, win.w - 1 do cell(win, win.y, x, " ", color) end
      win.y = win.y + 1; win.x = 0
    elseif c == "\t" then
      local n = 8 - win.x % 8
      for _ = 1, n do cell(win, win.y, win.x, " ", color); win.x = win.x + 1 end
    else
      if win.x >= win.w then win.x = 0; win.y = win.y + 1 end
      cell(win, win.y, win.x, c, color)
      win.x = win.x + 1
    end
  end
  return 0
end
function L.newwin(h, w, y, x)
  local s = std()
  if h == 0 then h = s.h - y end
  if w == 0 then w = s.w - x end
  return newWindow(h, w, y, x)
end
function L.newpad(h, w) local p = newWindow(h, w, 0, 0); p.pad = true; return p end
function L.subpad(parent, h, w, y, x) local p = newWindow(h, w, 0, 0); p.pad = true; return p end
function L.prefresh(pad, pr, pc, sr, sc, er, ec)
  for r = sr, er do
    for c = sc, ec do
      local i = (pr + r - sr) * pad.w + (pc + c - sc)
      if pad.bc and pr + r - sr < pad.h and pc + c - sc < pad.w then term.put(c, r, pad.bc[i] or " ", pad.bk[i] or "text") end
    end
  end
  term.flush()
  return 0
end
L.pnoutrefresh = L.prefresh
function L.copywin(src, dst, sr, sc, dr, dc, er, ec, overlay)
  for r = dr, er do
    for c = dc, ec do
      local sy, sx = sr + (r - dr), sc + (c - dc)
      local i = sy * src.w + sx
      local ch = src.bc and src.bc[i] or " "
      if sy < src.h and sx < src.w and not (overlay ~= 0 and ch == " ") then cell(dst, r, c, ch, src.bk and src.bk[i] or "text") end
    end
  end
  return 0
end
function L.overwrite(src, dst) return L.copywin(src, dst, 0, 0, 0, 0, math.min(src.h, dst.h) - 1, math.min(src.w, dst.w) - 1, 0) end
function L.overlay(src, dst) return L.copywin(src, dst, 0, 0, 0, 0, math.min(src.h, dst.h) - 1, math.min(src.w, dst.w) - 1, 1) end
function L.subwin(parent, h, w, y, x) return newWindow(h, w, y, x) end
function L.derwin(parent, h, w, y, x) return newWindow(h, w, parent.oy + y, parent.ox + x) end
function L.delwin() return 0 end
function L.mvwin(win, y, x) win.oy, win.ox = y, x; return 0 end
function L.wresize(win, h, w) win.h, win.w = h, w; return 0 end
L.resize = L.wresize
function L.getmaxy(win) return (win or std()).h end
function L.getmaxx(win) return (win or std()).w end
function L.getcury(win) return (win or std()).y end
function L.getcurx(win) return (win or std()).x end
function L.getbegy(win) return (win or std()).oy end
function L.getbegx(win) return (win or std()).ox end
L.getbegyx = ok
function L.wmove(win, y, x) win = win or std(); win.y, win.x = y, x; return 0 end
function L.move(y, x) return L.wmove(nil, y, x) end
function L.mvwmove(win, y, x) return L.wmove(win, y, x) end
function L.wattron(win, a) win = win or std(); win.attr = win.attr | a; return 0 end
function L.wattroff(win, a) win = win or std(); win.attr = win.attr & ~a; return 0 end
function L.wattrset(win, a) win = win or std(); win.attr = a; return 0 end
function L.wcolor_set(win, n) win = win or std(); win.attr = (win.attr & ~0xFF00) | (n << 8); return 0 end
function L.attron(a) return L.wattron(nil, a) end
function L.attroff(a) return L.wattroff(nil, a) end
function L.attrset(a) return L.wattrset(nil, a) end
function L.color_set(n) return L.wcolor_set(nil, n) end
function L.standout() return L.wattron(nil, 65536) end
function L.standend() return L.wattrset(nil, 0) end
L.wstandout, L.wstandend = L.standout, L.standend
function L.wbkgd(win, c) win = win or std(); win.bkgd = (c & 255) == 0 and 32 or (c & 255); win.bkgdAttr = c & ~255; return 0 end
L.bkgd, L.bkgdset, L.wbkgdset = function(c) return L.wbkgd(nil, c) end, function(c) return L.wbkgd(nil, c) end, L.wbkgd
function L.wclear(win)
  win = win or std()
  local color = "text"
  for y = 0, win.h - 1 do for x = 0, win.w - 1 do cell(win, y, x, string.char(win.bkgd), color) end end
  win.y, win.x = 0, 0
  return 0
end
L.werase = L.wclear
function L.clear() return L.wclear(nil) end
L.erase = L.clear
function L.wclrtoeol(win) win = win or std(); for x = win.x, win.w - 1 do cell(win, win.y, x, " ", "text") end return 0 end
function L.clrtoeol() return L.wclrtoeol(nil) end
function L.wclrtobot(win)
  win = win or std()
  L.wclrtoeol(win)
  for y = win.y + 1, win.h - 1 do for x = 0, win.w - 1 do cell(win, y, x, " ", "text") end end
  return 0
end
function L.clrtobot() return L.wclrtobot(nil) end
function L.wrefresh() term.flush(); if sys and sys.yield then sys.yield() end return 0 end
function L.refresh() return L.wrefresh() end
function L.waddch(win, c) win = win or std(); return putText(win, string.char(c & 255), c & ~255) end
function L.addch(c) return L.waddch(nil, c) end
function L.mvaddch(y, x, c) L.wmove(nil, y, x); return L.waddch(nil, c) end
function L.mvwaddch(win, y, x, c) L.wmove(win, y, x); return L.waddch(win, c) end
function L.echochar(c) return L.waddch(nil, c) end
function L.waddstr(win, s) return putText(win or std(), tolua(s)) end
function L.addstr(s) return L.waddstr(nil, s) end
function L.waddnstr(win, s, n) return putText(win or std(), tolua(s):sub(1, n < 0 and #tolua(s) or n)) end
function L.addnstr(s, n) return L.waddnstr(nil, s, n) end
function L.mvaddstr(y, x, s) L.wmove(nil, y, x); return L.waddstr(nil, s) end
function L.mvwaddstr(win, y, x, s) L.wmove(win, y, x); return L.waddstr(win, s) end
function L.mvaddnstr(y, x, s, n) L.wmove(nil, y, x); return L.waddnstr(nil, s, n) end
function L.wprintw(win, f, ...) return putText(win or std(), format(f, { ... })) end
function L.printw(f, ...) return L.wprintw(nil, f, ...) end
function L.mvprintw(y, x, f, ...) L.wmove(nil, y, x); return L.wprintw(nil, f, ...) end
function L.mvwprintw(win, y, x, f, ...) L.wmove(win, y, x); return L.wprintw(win, f, ...) end
function L.whline(win, c, n) win = win or std(); for k = 0, n - 1 do cell(win, win.y, win.x + k, string.char((c == 0 and 45 or c) & 255), attrColor(win)) end return 0 end
function L.wvline(win, c, n) win = win or std(); for k = 0, n - 1 do cell(win, win.y + k, win.x, string.char((c == 0 and 124 or c) & 255), attrColor(win)) end return 0 end
function L.hline(c, n) return L.whline(nil, c, n) end
function L.vline(c, n) return L.wvline(nil, c, n) end
function L.mvhline(y, x, c, n) L.wmove(nil, y, x); return L.whline(nil, c, n) end
function L.mvvline(y, x, c, n) L.wmove(nil, y, x); return L.wvline(nil, c, n) end
function L.mvwhline(win, y, x, c, n) L.wmove(win, y, x); return L.whline(win, c, n) end
function L.mvwvline(win, y, x, c, n) L.wmove(win, y, x); return L.wvline(win, c, n) end
function L.wborder(win, ls, rs, ts, bs, tl, tr, bl, br)
  win = win or std()
  local function ch(c, d) return string.char((c and c ~= 0 and c or d) & 255) end
  local col = attrColor(win)
  for x = 1, win.w - 2 do cell(win, 0, x, ch(ts, 45), col); cell(win, win.h - 1, x, ch(bs, 45), col) end
  for y = 1, win.h - 2 do cell(win, y, 0, ch(ls, 124), col); cell(win, y, win.w - 1, ch(rs, 124), col) end
  cell(win, 0, 0, ch(tl, 43), col); cell(win, 0, win.w - 1, ch(tr, 43), col)
  cell(win, win.h - 1, 0, ch(bl, 43), col); cell(win, win.h - 1, win.w - 1, ch(br, 43), col)
  return 0
end
function L.box(win, v, h) return L.wborder(win, v, v, h, h) end
function L.border(...) return L.wborder(nil, ...) end
function L.nodelay(win, b) (win or std()).delay = (b ~= 0 and b ~= false) and 0 or -1; return 0 end
function L.timeout(t) std().delay = t; return 0 end
function L.wtimeout(win, t) (win or std()).delay = t; return 0 end
local KEYS = { up = 259, down = 258, left = 260, right = 261, backspace = 263, enter = 10, tab = 9, space = 32, pgup = 339, pgdn = 338 }
function L.wgetch(win)
  win = win or std()
  term.flush()
  local limit = win.delay
  local start = sys.millis()
  while true do
    local k = key.poll()
    if k then
      if KEYS[k] then return KEYS[k] end
      if #k == 1 then return byte(k) end
      local c = k:match("^ctrl%-(%a)$")
      if c then return byte(c) & 31 end
    end
    timerTick()
    if limit >= 0 and sys.millis() - start >= limit then return -1 end
    sys.sleep(5)
  end
end
function L.getch() return L.wgetch(nil) end
function L.mvgetch(y, x) L.wmove(nil, y, x); return L.wgetch(nil) end
function L.mvwgetch(win, y, x) L.wmove(win, y, x); return L.wgetch(win) end
function L.wgetnstr(win, b, n) local l = io.read("l") or ""; fromLua(l:sub(1, n), b); return 0 end
function L.getnstr(b, n) return L.wgetnstr(nil, b, n) end
function L.getstr(b) return L.wgetnstr(nil, b, 1000) end
L.wgetstr = function(win, b) return L.wgetnstr(win, b, 1000) end
function L.winch(win) return 32 end
function L.mvwin_wch(win, y, x, p) if p then local v = p.a[p.i]; v.attr = 0; v.chars = { [0] = 32 } end return 0 end
L.win_wch = function(win, p) return L.mvwin_wch(win, 0, 0, p) end
function L.mvin_wch(y, x, p) return L.mvwin_wch(nil, y, x, p) end
function L.wadd_wch(win, p) local v = p.a[p.i]; return L.waddch(win, (v.chars and v.chars[0] or 32) & 255) end
function L.add_wch(p) return L.wadd_wch(nil, p) end
function L.mvwadd_wch(win, y, x, p) L.wmove(win, y, x); return L.wadd_wch(win, p) end
function L.mvadd_wch(y, x, p) return L.mvwadd_wch(nil, y, x, p) end
L.inch = function() return 32 end
L.mvinch = function() return 32 end
-- panels
function L.new_panel(win) return { panel = true, win = win } end
function L.panel_window(p) return p.win end
function L.del_panel() return 0 end
function L.move_panel(p, y, x) p.win.oy, p.win.ox = y, x; return 0 end
function L.panel_hidden() return 0 end
function L.set_panel_userptr(p, u) p.user = u; return 0 end
function L.panel_userptr(p) return p.user end
function L.panel_above() return nil end
function L.panel_below() return nil end
function L.replace_panel(p, w) p.win = w; return 0 end
function L.hide_panel(p) if p and p.win then L.wclear(p.win) end return 0 end
-- the algorithms of C++: they work on iterators
mergeSort = function(a, n, lt)
  if n < 2 then return a end
  local b = {}
  local w = 1
  while w < n do
    local i = 1
    while i <= n do
      local mid, hi = math.min(i + w, n + 1), math.min(i + 2 * w, n + 1)
      local l, r, k = i, mid, i
      while l < mid and r < hi do
        if lt(a[r], a[l]) then b[k] = a[r]; r = r + 1 else b[k] = a[l]; l = l + 1 end
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
function L.sort(p, q, f)
  local items, n = {}, 0
  for i = p.i, q.i - 1 do n = n + 1; items[n] = p.a[i] end
  local s = mergeSort(items, n, f or less)
  for k = 1, n do p.a[p.i + k - 1] = s[k] end
end
L.stable_sort = L.sort
function L.reverse(p, q)
  local i, j = p.i, q.i - 1
  local a = p.a
  while i < j do a[i], a[j] = a[j], a[i]; i = i + 1; j = j - 1 end
end
function L.find(p, q, x)
  for i = p.i, q.i - 1 do if veq(p.a[i], x) then return { a = p.a, i = i } end end
  return { a = p.a, i = q.i }
end
function L.find_if(p, q, f)
  for i = p.i, q.i - 1 do if f(p.a[i]) then return { a = p.a, i = i } end end
  return { a = p.a, i = q.i }
end
function L.count(p, q, x) local c = 0; for i = p.i, q.i - 1 do if veq(p.a[i], x) then c = c + 1 end end return c end
function L.count_if(p, q, f) local c = 0; for i = p.i, q.i - 1 do if f(p.a[i]) then c = c + 1 end end return c end
function L.accumulate(p, q, init, f)
  local r = init
  for i = p.i, q.i - 1 do
    if f then r = f(r, p.a[i]) elseif type_(r) == "string" then r = r .. p.a[i] else r = r + p.a[i] end
  end
  return r
end
function L.max_element(p, q, f)
  local b = p.i
  for i = p.i + 1, q.i - 1 do if (f or less)(p.a[b], p.a[i]) then b = i end end
  return { a = p.a, i = b }
end
function L.min_element(p, q, f)
  local b = p.i
  for i = p.i + 1, q.i - 1 do if (f or less)(p.a[i], p.a[b]) then b = i end end
  return { a = p.a, i = b }
end
function L.fill(p, q, v) for i = p.i, q.i - 1 do p.a[i] = v end end
function L.iota(p, q, v) for i = p.i, q.i - 1 do p.a[i] = v; v = v + 1 end end
function L.for_each(p, q, f) for i = p.i, q.i - 1 do f(p.a[i]) end return f end
function L.any_of(p, q, f) for i = p.i, q.i - 1 do if f(p.a[i]) then return true end end return false end
function L.all_of(p, q, f) for i = p.i, q.i - 1 do if not f(p.a[i]) then return false end end return true end
function L.none_of(p, q, f) for i = p.i, q.i - 1 do if f(p.a[i]) then return false end end return true end
function L.binary_search(p, q, x)
  local a, b = p.i, q.i
  while a < b do
    local m = (a + b) // 2
    if less(p.a[m], x) then a = m + 1 elseif less(x, p.a[m]) then b = m else return true end
  end
  return false
end
function L.lower_bound(p, q, x)
  local a, b = p.i, q.i
  while a < b do
    local m = (a + b) // 2
    if less(p.a[m], x) then a = m + 1 else b = m end
  end
  return { a = p.a, i = a }
end
function L.upper_bound(p, q, x)
  local a, b = p.i, q.i
  while a < b do
    local m = (a + b) // 2
    if less(x, p.a[m]) then b = m else a = m + 1 end
  end
  return { a = p.a, i = a }
end
function L.unique(p, q)
  local w = p.i
  for i = p.i, q.i - 1 do
    if i == p.i or not veq(p.a[i], p.a[w - 1]) then p.a[w] = p.a[i]; w = w + 1 end
  end
  return { a = p.a, i = w }
end
function L.distance(p, q) return q.i - p.i end
function L.next(p, n) return { a = p.a, i = p.i + (n or 1) } end
function L.prev(p, n) return { a = p.a, i = p.i - (n or 1) } end
function L.advance(p, n) p.i = p.i + n end
function L.greater() return function(a, b) return less(b, a) end end
function L.less() return less end
function L.setw(n) return { setw = n } end
function L.setprecision(n) return { setprecision = n } end
function L.setfill(c) return { setfill = c } end
function L.pow10(x) return 10.0 ^ x end
function R.libOpt(n) return L[n] or function() error("undefined reference to `" .. n .. "'", 0) end end
function R.lib(n)
  local f = L[n]
  if not f then error("undefined reference to `" .. n .. "'", 0) end
  return f
end
function R.anyindex(c, i)
  if type_(c) == "table" and c.a and c.i ~= nil then return c.a[c.i + i] end
  return c[i]
end
function R.anycall(o, n, ...)
  if type_(o) == "string" then
    if n == "size" or n == "length" then return #o end
    if n == "c_str" then return R.cstr(o) end
    if n == "substr" then return R.substr(o, ...) end
    if n == "empty" then return o == "" end
  elseif type_(o) == "table" then
    local m = getmt(o)
    if m == Vec then
      if n == "size" then return o.n end
      if n == "push_back" then return R.vpush(o, (...)) end
      if n == "pop_back" then return R.vpop(o) end
      if n == "back" then return o[o.n - 1] end
      if n == "front" then return o[0] end
      if n == "empty" then return o.n == 0 end
      if n == "begin" then return { a = o, i = 0 } end
      if n == "end" then return { a = o, i = o.n } end
      if n == "clear" then return R.vclear(o) end
    end
    local c = select("#", ...)
    local f = o[n .. "_" .. c]
    if f then return f(o, ...) end
    f = o[n]
    if f then return f(...) end
  end
  error("no member named '" .. n .. "'", 0)
end

-- exceptions
local Thrown = {}
function R.throw(v) error(setmt({ v = v }, Thrown), 0) end
function R.caught(e)
  if getmt(e) == Thrown then return e.v end
  error(e, 0)
end
local function excClass(name, base)
  local c = { __name = name }
  c.__index = c
  c.__base = base
  if base then setmt(c, { __index = base }) end
  c.what_0 = function(self) return R.cstr(self.__what or name) end
  return c
end
local classes = {}
for _, p in ipairs{ { "exception" }, { "runtime_error", "exception" }, { "logic_error", "exception" }, { "out_of_range", "logic_error" }, { "invalid_argument", "logic_error" }, { "overflow_error", "runtime_error" }, { "range_error", "runtime_error" }, { "length_error", "logic_error" }, { "domain_error", "logic_error" }, { "bad_alloc", "exception" } } do
  classes[p[1]] = excClass(p[1], p[2] and classes[p[2]])
end
function R.baseClass(n) return classes[n] or classes.exception end
function R.newExc(name, msg) return setmt({ __what = msg }, classes[name]) end
R.classes = classes

function R.run(text, args)
  local G = {}
  -- the library's exception classes as C++ types
  for name, c in pairs(classes) do
    G[name] = c
    local nameC = name
    G[name .. "_zero"] = function() return setmt({}, c) end
    G[name .. "_fill"] = function() end
    G[name .. "_new_1"] = function(m) return setmt({ __what = m }, c) end
    G[name .. "_new_0"] = function() return setmt({}, c) end
    G[name .. "_init_1"] = function(o, m) o.__what = m end
    G[name .. "_init_0"] = function() end
  end
  local env = setmt({ R = R, G = G }, { __index = _G })
  local f, e = load(text, "=program", "t", env)
  if not f then
    write("internal error: " .. tostring(e) .. "\n")
    return 1
  end
  local ok, mainF = pcall(f)
  if not ok then
    write("error: " .. tostring(mainF) .. "\n")
    return 1
  end
  local argv = { n = #args }
  for i = 1, #args do argv[i - 1] = { a = R.chararr(args[i]), i = 0 } end
  local ok2, code = xpcall(function()
    return mainF(#args, { a = argv, i = 0 })
  end, function(e)
    if type_(e) == "string" and os.getenv("C_TRACE") then return e .. "\n" .. debug.traceback() end
    return e
  end)
  if not ok2 then
    if type_(code) == "table" and code.exit then return code.exit end
    if getmt(code) == Thrown then
      local v = code.v
      if type_(v) == "table" and v.what_0 then write("terminate called after throwing an instance of '" .. tostring(getmt(v).__name) .. "'\n  what():  " .. tolua(v:what_0()) .. "\nAborted\n")
      else write("terminate called after throwing an exception\nAborted\n") end
      return 134
    end
    if type_(code) == "string" and code:find("interrupted", 1, true) then error(code, 0) end
    write(tostring(code):gsub("^program:%d+: ", "") .. "\n")
    return 139
  end
  if R.atExit then for k = #R.atExit, 1, -1 do pcall(R.atExit[k]) end end
  pcall(flushStreams)
  return code or 0
end
return R
