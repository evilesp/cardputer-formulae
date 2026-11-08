#!lua
-- crt: the run-time of the C and C++ programs that clang translates: pointers, strings, stdio, string.h, stdlib.h, math.h, containers, streams.
local R = {}
local mtype, floor, concat, sfmt, char, byte = math.type, math.floor, table.concat, string.format, string.char, string.byte
local setmt, getmt, type_ = setmetatable, getmetatable, type
local function write(s) term.write(s) end

-- ---- pointers: {a = a table, i = a key} ----
function R.ptr(a, i) return { a = a, i = i } end
function R.padd(p, n) return { a = p.a, i = p.i + n } end
function R.pdiff(p, q)
  if p == nil or q == nil then return (p == nil and 0 or 1) - (q == nil and 0 or 1) end
  return p.i - q.i
end
function R.load(p)
  if p == nil then error("Segmentation fault (a null pointer was read)", 0) end
  return p.a[p.i]
end
function R.store(p, v)
  if p == nil then error("Segmentation fault (a null pointer was written)", 0) end
  p.a[p.i] = v
end
local rptrMt
function R.box(v) return { a = { [0] = v }, i = 0 } end
function R.addr(get, set)
  return { a = setmt({}, { __index = function() return get() end, __newindex = function(_, _, v) set(v) end }), i = 0 }
end
function R.peq(x, y)
  if x == y then return true end
  if x == nil or y == nil then return false end
  if x.a == y.a and x.i == y.i then return true end
  if x.mapEnd and y.mapEnd then return true end
  local vx = rawget(x.a, x.i)
  if type_(vx) == "table" and vx == rawget(y.a, y.i) then return true end
  return false
end
function R.typed(p, zero)
  if p == nil then return nil end
  local mt = getmt(p.a)
  if zero then
    setmt(p.a, { __index = function(t, k)
      local v = zero()
      rawset(t, k, v)
      return v
    end })
  else setmt(p.a, nil) end
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
function R.arrf(n, f)
  local t = {}
  for i = 0, n - 1 do t[i] = f() end
  return t
end
function R.arrinit(n, z, vals)
  for i = 0, n - 1 do if vals[i] == nil then vals[i] = z end end
  return vals
end
function R.arrinitf(n, f, vals)
  for i = 0, n - 1 do if vals[i] == nil then vals[i] = f() end end
  return vals
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
local function tolua(p)
  if p == nil then return "(null)" end
  if type_(p) == "string" then return p end
  local o, n, a, i = {}, 0, p.a, p.i
  while true do
    local c = a[i]
    if c == 0 or c == nil then break end
    n = n + 1
    o[n] = char(c & 255)
    i = i + 1
  end
  return concat(o)
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
  write(text)
  return s
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
local function getc()
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
      return sfmt(spec .. "s", s)
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
local function scanInto(tokenFn, fmt, args)
  fmt = tolua(fmt)
  local n, ai = 0, 1
  for conv in fmt:gmatch("%%[%d]*[hlL]*([%a%[])") do
    local p = args[ai]
    ai = ai + 1
    if conv == "c" then
      local c = tokenFn(true)
      if c == nil then return n > 0 and n or -1 end
      p.a[p.i] = c
    else
      local t = tokenFn(false)
      if t == nil then return n > 0 and n or -1 end
      if conv == "s" then fromLua(t, p)
      elseif conv == "d" or conv == "i" or conv == "u" or conv == "x" then
        local v = tonumber(t, conv == "x" and 16 or nil)
        if not v then return n end
        p.a[p.i] = math.tointeger(v) or floor(v)
      else
        local v = tonumber(t)
        if not v then return n end
        p.a[p.i] = v + 0.0
      end
    end
    n = n + 1
  end
  return n
end
function L.scanf(f, ...)
  return scanInto(function(raw) if raw then return getc() end return token() end, f, { ... })
end
function L.sscanf(s, f, ...)
  local text = tolua(s)
  local i = 1
  return scanInto(function(raw)
    if raw then local c = byte(text, i); i = i + 1; return c end
    local a, b = text:find("%S+", i)
    if not a then return nil end
    i = b + 1
    return text:sub(a, b)
  end, f, { ... })
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
function L.strcmp(a, b) a, b = tolua(a), tolua(b); return a < b and -1 or (a > b and 1 or 0) end
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
  local m = t:match("^%s*[+-]?%w+") or ""
  return tonumber(m, base and base ~= 0 and base or 10) or 0
end
L.strtoul = L.strtol
L.labs = function(x) return x < 0 and -x or x end
function L.rand() return math.random(0, 2147483647) end
function L.srand(s) math.randomseed(s) end
function L.exit(c) error({ exit = c or 0 }, 0) end
function L.abort() error("Aborted", 0) end
function L.assert(c)
  if c == 0 or c == false or c == nil then error("Assertion failed", 0) end
end
function L.system(c) c = tolua(c); if sys and sys.shell then return sys.shell(c, true) or 0 end return 1 end
function L.getenv() return nil end
function L.time() local t = sys and sys.time and sys.time(); return math.tointeger(floor(t or 0)) end
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
function L.toupper(c) if c >= 97 and c <= 122 then return c - 32 end return c end
function L.tolower(c) if c >= 65 and c <= 90 then return c + 32 end return c end
-- files
R.stdin, R.stdout, R.stderr = { std = true }, { std = true }, { std = true }
function L.fopen(p, m)
  p = tolua(p); m = tolua(m)
  local f = { path = p, mode = m, pos = 1, data = "", buf = {} }
  if m:find("r", 1, true) then
    local d = fs.read(p)
    if not d then return nil end
    f.data = d
  elseif m:find("w", 1, true) then fs.write(p, "") end
  return f
end
function L.fclose(f)
  if f and #f.buf > 0 then fs.append(f.path, concat(f.buf)); f.buf = {} end
  return 0
end
function L.fprintf(f, fmt, ...)
  local s = format(fmt, { ... })
  if f.std then write(s) else f.buf[#f.buf + 1] = s end
  return #s
end
function L.fputs(s, f) s = tolua(s); if f.std then write(s) else f.buf[#f.buf + 1] = s end return 0 end
function L.fputc(c, f) local s = char(c); if f.std then write(s) else f.buf[#f.buf + 1] = s end return c end
L.putc = L.fputc
function L.fgetc(f)
  if f.std then return getc() or -1 end
  if f.pos > #f.data then return -1 end
  local c = byte(f.data, f.pos)
  f.pos = f.pos + 1
  return c
end
L.getc = L.fgetc
function L.feof(f) return f.pos > #f.data and 1 or 0 end
function L.fflush() return 0 end
function L.perror(s) write(tolua(s) .. ": error\n") end
-- the algorithms of C++: they work on iterators
local function mergeSort(a, n, lt)
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
  local ok2, code = pcall(function()
    local arity = debug and nil
    return mainF(#args, { a = argv, i = 0 })
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
  return code or 0
end
return R
