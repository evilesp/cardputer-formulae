#!lua
-- pyrt: the run-time of the Python programs that pylang translates: operators, str/list/dict/set, classes, exceptions, modules.
local R = {}
local mtype, floor, unpack, concat, sfmt = math.type, math.floor, table.unpack, table.concat, string.format
local getmt, setmt, rawget_, type_ = getmetatable, setmetatable, rawget, type

local None = setmt({}, { __tostring = function() return "None" end, __name = "NoneType" })
R.None = None

local function write(s)
  if term and term.write then term.write(s) else io.write(s) end
end

-- ---------------------------------------------------------------- classes
local List, Tuple, Dict, Set = {}, {}, {}, {}
local object = {}
local TypeMT = {}
local function newBuiltinType(name, base, tbl)
  tbl = tbl or {}
  tbl.__name__ = name
  tbl.__index = tbl
  tbl.__bases = base and { base } or {}
  tbl.__builtin = true
  return tbl
end
local function classLookup(cls, k)
  local v = rawget_(cls, k)
  if v ~= nil then return v end
  local bases = rawget_(cls, "__bases")
  if bases then
    for i = 1, #bases do
      v = classLookup(bases[i], k)
      if v ~= nil then return v end
    end
  end
  return nil
end
R.classLookup = classLookup

local builtins = {}
R.builtins = builtins

local function isSub(c, base)
  if c == base then return true end
  local bases = rawget_(c, "__bases")
  if bases then
    for i = 1, #bases do if isSub(bases[i], base) then return true end end
  end
  return false
end

function TypeMT.__call(cls, ...)
  local ctor = rawget_(cls, "__ctor")
  if ctor then return ctor(cls, ...) end
  ctor = classLookup(cls, "__ctor")
  if ctor then return ctor(cls, ...) end
  local new = classLookup(cls, "__new__")
  local o
  if new then o = new(cls, ...) else o = setmt({}, cls) end
  if getmt(o) == cls or (type_(o) == "table" and getmt(o) and rawget_(getmt(o), "__index") and isSub(getmt(o), cls)) then
    local init = classLookup(cls, "__init__")
    if init then init(o, ...) elseif select("#", ...) > 0 and not new then R.raise(builtins.TypeError(cls.__name__ .. "() takes no arguments")) end
  end
  return o
end
TypeMT.__index = function(cls, k)
  local bases = rawget_(cls, "__bases")
  if bases then
    for i = 1, #bases do
      local v = bases[i][k]
      if v ~= nil then return v end
    end
  end
  return nil
end
TypeMT.__tostring = function(c) return "<class '" .. tostring(rawget_(c, "__name__")) .. "'>" end

object.__name__ = "object"
object.__index = object
object.__bases = {}
setmt(object, TypeMT)
builtins.object = object
object.__ctor = nil

function R.class(name, bases, body)
  local cls = { __name__ = name, __qualname__ = name, __module__ = "__main__" }
  cls.__index = function(o, k)
    local v = classLookup(cls, k)
    return v
  end
  if #bases == 0 then bases = { object } end
  cls.__bases = bases
  setmt(cls, TypeMT)
  cls.__class_mt = true
  -- instances are called through __call__, and hash/equal are done by the helpers below
  cls.__call = function(o, ...)
    local f = classLookup(cls, "__call__")
    if not f then R.raise(builtins.TypeError("'" .. name .. "' object is not callable")) end
    return f(o, ...)
  end
  cls.__tostring = function(o) return R.str(o) end
  body(cls)
  return cls
end

-- the wrappers of @property, @staticmethod, @classmethod
local Property, Static, ClassM = {}, {}, {}
Property.__index = Property
function builtins.property(fget, fset)
  local p = setmt({ get = fget, set = fset ~= None and fset or nil }, Property)
  return p
end
function Property.setter(p, f) p.set = f; return p end
function Property.getter(p, f) p.get = f; return p end
function builtins.staticmethod(f) return setmt({ f = f }, Static) end
function builtins.classmethod(f) return setmt({ f = f }, ClassM) end

-- ---------------------------------------------------------------- functions
local FN = setmt({}, { __mode = "k" })
local NAMES = setmt({}, { __mode = "k" })
local pendingKw
function R.def(f, info) FN[f] = info; return f end
function R.named(f, n) if type_(f) == "function" then NAMES[f] = n end return f end
function R.takekw() local k = pendingKw; pendingKw = nil; return k end
function R.kwget(kw, n, d)
  if kw and kw[n] ~= nil then local v = kw[n]; kw[n] = nil; return v end
  if d == nil then R.raise(builtins.TypeError("missing required keyword argument: '" .. n .. "'")) end
  return d
end
local function callKw(f, pos, kw)
  if not kw or next(kw) == nil then return f(unpack(pos, 1, pos.n or #pos)) end
  local info = type_(f) == "function" and FN[f]
  if type_(f) == "table" and getmt(f) == TypeMT then
    local init = classLookup(f, "__init__")
    if init and FN[init] then
      -- the constructor: self comes first
      local o = setmt({}, f)
      local a = { o, unpack(pos, 1, pos.n or #pos) }
      callKw(init, a, kw)
      return o
    end
    pendingKw = kw
    return f(unpack(pos, 1, pos.n or #pos))
  end
  if not info then
    pendingKw = kw
    return f(unpack(pos, 1, pos.n or #pos))
  end
  local names = info.names
  local args = { unpack(pos, 1, pos.n or #pos) }
  local top = pos.n or #pos
  local rest = {}
  local anyRest = false
  for k, v in pairs(kw) do
    local placed = false
    for i = 1, #names do
      if names[i] == k then
        args[i] = v
        if i > top then top = i end
        placed = true
        break
      end
    end
    if not placed then
      rest[k] = v
      anyRest = true
    end
  end
  if anyRest and not info.kw then
    local k = next(rest)
    R.raise(builtins.TypeError((NAMES[f] or "function") .. "() got an unexpected keyword argument '" .. k .. "'"))
  end
  if info.kw then pendingKw = rest end
  return f(unpack(args, 1, top))
end
R.CK = callKw
function R.kwdict(kw)
  local d = R.dict()
  if kw then for k, v in pairs(kw) do R.dset(d, k, v) end end
  return d
end
function R.kwmerge(a, m)
  for _, k in R.dkeys(m) do a[k] = R.dget(m, k) end
  return a
end

-- ---------------------------------------------------------------- errors
local function excClass(name, base)
  local c = R.class(name, { base }, function() end)
  builtins[name] = c
  return c
end
local BaseException = R.class("BaseException", {}, function(c)
  c.__init__ = function(self, ...)
    self.args = R.tuple{ ... }
  end
  c.__str__ = function(self)
    local a = rawget_(self, "args")
    if not a or #a == 0 then return "" end
    if #a == 1 then return R.str(a[1]) end
    return R.repr(a)
  end
  c.__repr__ = function(self)
    local a = rawget_(self, "args")
    local cn = getmt(self).__name__
    if not a or #a == 0 then return cn .. "()" end
    if #a == 1 then return cn .. "(" .. R.repr(a[1]) .. ")" end
    return cn .. R.repr(a)
  end
end)
builtins.BaseException = BaseException
local Exception = excClass("Exception", BaseException)
excClass("SystemExit", BaseException)
excClass("KeyboardInterrupt", BaseException)
excClass("GeneratorExit", BaseException)
local Arith = excClass("ArithmeticError", Exception)
excClass("ZeroDivisionError", Arith)
excClass("OverflowError", Arith)
excClass("AssertionError", Exception)
excClass("AttributeError", Exception)
excClass("EOFError", Exception)
excClass("ImportError", Exception)
excClass("ModuleNotFoundError", builtins.ImportError)
local Lookup = excClass("LookupError", Exception)
excClass("IndexError", Lookup)
excClass("KeyError", Lookup)
excClass("MemoryError", Exception)
excClass("NameError", Exception)
local OSE = excClass("OSError", Exception)
builtins.IOError = OSE
excClass("FileNotFoundError", OSE)
excClass("FileExistsError", OSE)
excClass("PermissionError", OSE)
excClass("IsADirectoryError", OSE)
excClass("NotADirectoryError", OSE)
excClass("InterruptedError", OSE)
excClass("BlockingIOError", OSE)
excClass("BrokenPipeError", OSE)
excClass("ConnectionError", OSE)
excClass("ConnectionRefusedError", OSE)
excClass("ConnectionResetError", OSE)
excClass("TimeoutError", OSE)
excClass("TimeoutError", OSE)
local RT = excClass("RuntimeError", Exception)
excClass("NotImplementedError", RT)
excClass("RecursionError", RT)
excClass("StopIteration", Exception)
excClass("SyntaxError", Exception)
excClass("TypeError", Exception)
local VE = excClass("ValueError", Exception)
excClass("UnicodeError", VE)
excClass("Warning", Exception)
builtins.KeyError.__str__ = function(self)
  local a = rawget_(self, "args")
  if a and #a == 1 then return R.repr(a[1]) end
  return ""
end

function R.raise(e)
  if type_(e) == "table" and getmt(e) == TypeMT then e = e() end
  error(e, 0)
end
local raise = R.raise

local function isExc(e)
  if type_(e) ~= "table" then return false end
  local m = getmt(e)
  return m and rawget_(m, "__class_mt") and isSub(m, BaseException)
end

function R.exc(e)
  if isExc(e) then return e end
  local s = tostring(e)
  if s:find("attempt to perform 'n//0'", 1, true) or s:find("attempt to perform 'n%%0'", 1, true) or s:find("attempt to divide", 1, true) then
    return builtins.ZeroDivisionError("integer division or modulo by zero")
  end
  if s:find("stack overflow", 1, true) then return builtins.RecursionError("maximum recursion depth exceeded") end
  if s:find("interrupted", 1, true) then error(e, 0) end
  if s:find("attempt to call", 1, true) then return builtins.TypeError("object is not callable") end
  if s:find("attempt to", 1, true) then return builtins.TypeError(s:gsub("^.-:%d+: ", "")) end
  if s:find("not enough memory", 1, true) then return builtins.MemoryError("out of memory") end
  return builtins.RuntimeError(s)
end
function R.excmatch(e, cls)
  if getmt(cls) == nil and type_(cls) == "table" then
    for i = 1, #cls do if isSub(getmt(e), cls[i]) then return true end end
    return false
  end
  if getmt(cls) == Tuple then
    for i = 1, #cls do if isSub(getmt(e), cls[i]) then return true end end
    return false
  end
  return isSub(getmt(e), cls)
end
function R.classof(x) return builtins.type(x) end

-- ---------------------------------------------------------------- containers
local function tuple(t) return setmt(t, Tuple) end
local function list(t) return setmt(t, List) end
R.tuple, R.list = tuple, list

local tupleKey
local function keyOf(k)
  if type_(k) == "table" then
    local m = getmt(k)
    if m == Tuple then return tupleKey(k) end
    if m and rawget_(m, "__class_mt") then
      local h = classLookup(m, "__hash__")
      if h then return "\0H" .. tostring(h(k)) end
    end
    if m == List or m == Dict or m == Set then raise(builtins.TypeError("unhashable type: '" .. m.__name__ .. "'")) end
  elseif k == true then return 1
  elseif k == false then return 0
  end
  return k
end
tupleKey = function(t)
  local p = {}
  for i = 1, #t do
    local k = keyOf(t[i])
    p[i] = type_(k) .. ":" .. tostring(k)
  end
  return "\0T" .. concat(p, "\1")
end

function R.dict()
  return setmt({ idx = {}, ks = {}, vs = {}, top = 0, n = 0 }, Dict)
end
local dict = R.dict
local function dset(d, k, v)
  local key = keyOf(k)
  local i = d.idx[key]
  if i then d.vs[i] = v
  else
    i = d.top + 1
    d.top = i
    d.idx[key] = i
    d.ks[i] = k
    d.vs[i] = v
    d.n = d.n + 1
  end
end
R.dset = dset
local function dget(d, k)
  local i = d.idx[keyOf(k)]
  if i then return d.vs[i] end
  return nil
end
R.dget = dget
local function ddel(d, k)
  local key = keyOf(k)
  local i = d.idx[key]
  if not i then return false end
  d.idx[key] = nil
  d.ks[i] = nil
  d.vs[i] = nil
  d.n = d.n - 1
  return true
end
-- the keys in the order they were put in (iterator of index, key)
local function dnext(d, i)
  local top, ks = d.top, d.ks
  i = i + 1
  while i <= top do
    local k = ks[i]
    if k ~= nil then return i, k end
    i = i + 1
  end
end
function R.dkeys(d) return dnext, d, 0 end
local dkeys = R.dkeys

function R.dictlit(...)
  local d = dict()
  local a = { ... }
  for i = 1, select("#", ...), 2 do dset(d, a[i], a[i + 1]) end
  return d
end
function R.dictmerge(...)
  local d = dict()
  for _, p in ipairs{ ... } do
    if p.m then for _, k in dkeys(p.m) do dset(d, k, dget(p.m, k)) end
    else dset(d, p.k, p.v) end
  end
  return d
end
local function newSet()
  return setmt({ idx = {}, ks = {}, vs = {}, top = 0, n = 0 }, Set)
end
function R.sadd(s, k) dset(s, k, true) end
function R.set(t) return newSet() end
function R.setlit(t)
  local s = newSet()
  for i = 1, #t do dset(s, t[i], true) end
  return s
end

-- ---------------------------------------------------------------- iteration
local Gen = newBuiltinType("generator")
local function toList(x)
  local out = {}
  local n = 0
  for v in R.iter(x) do
    n = n + 1
    out[n] = v
  end
  return out
end
R.toList = toList

local function utf8chars(s)
  local out, n = {}, 0
  for _, c in utf8.codes(s, true) do
    n = n + 1
    out[n] = utf8.char(c)
  end
  return out
end
local function isAscii(s) return not s:find("[\128-\255]") end

function R.iter(x)
  local t = type_(x)
  if t == "table" then
    local m = getmt(x)
    if m == List or m == Tuple then
      local i = 0
      return function()
        i = i + 1
        return x[i]
      end
    elseif m == Dict or m == Set then
      local i = 0
      return function()
        local k
        i, k = dnext(x, i)
        return k
      end
    elseif m == Gen then
      return function()
        local v = Gen.resume(x)
        return v
      end
    elseif m and rawget_(m, "__class_mt") then
      local f = classLookup(m, "__iter__")
      if f then
        local it = f(x)
        if getmt(it) == Gen or type_(it) ~= "table" or not rawget_(getmt(it) or {}, "__class_mt") then return R.iter(it) end
        local nx = classLookup(getmt(it), "__next__")
        return function()
          local ok, v = pcall(nx, it)
          if ok then return v == nil and None or v end
          if isExc(v) and isSub(getmt(v), builtins.StopIteration) then return nil end
          error(v, 0)
        end
      end
      local gi = classLookup(m, "__getitem__")
      if gi then
        local i = -1
        return function()
          i = i + 1
          local ok, v = pcall(gi, x, i)
          if ok then return v end
          if isExc(v) and isSub(getmt(v), builtins.IndexError) then return nil end
          error(v, 0)
        end
      end
    elseif m and m.__iterfn then return m.__iterfn(x)
    end
  elseif t == "string" then
    if isAscii(x) then
      local i, n = 0, #x
      return function()
        i = i + 1
        if i <= n then return x:sub(i, i) end
      end
    end
    local c = utf8chars(x)
    local i = 0
    return function()
      i = i + 1
      return c[i]
    end
  elseif t == "function" then return x
  end
  raise(builtins.TypeError("'" .. builtins.type(x).__name__ .. "' object is not iterable"))
end
local iter = R.iter

function R.gen(body)
  return setmt({ co = coroutine.create(body), started = false }, Gen)
end
Gen.__iterfn = nil
function Gen.resume(g, v)
  if not g.co or coroutine.status(g.co) == "dead" then return nil end
  local ok, r = coroutine.resume(g.co, v)
  if not ok then g.co = nil; error(r, 0) end
  if coroutine.status(g.co) == "dead" then g.ret = r; g.co = nil; return nil end
  return r == nil and None or r
end
function R.yield(v) local r = coroutine.yield(v == nil and None or v); return r == nil and None or r end
function R.yieldfrom(it)
  for v in iter(it) do R.yield(v) end
  return None
end
Gen.__next__ = function(g)
  local v = Gen.resume(g)
  if v == nil then raise(builtins.StopIteration()) end
  return v
end
Gen.__iter__ = function(g) return g end
Gen.send = function(g, v)
  local r = Gen.resume(g, v)
  if r == nil then raise(builtins.StopIteration()) end
  return r
end
Gen.close = function(g) g.co = nil; return None end

function R.UNP(v, n, star)
  local items = (type_(v) == "table" and (getmt(v) == List or getmt(v) == Tuple)) and v or toList(v)
  local c = #items
  if star then
    if c < n - 1 then raise(builtins.ValueError("not enough values to unpack (expected at least " .. (n - 1) .. ", got " .. c .. ")")) end
    local out = {}
    for i = 1, star - 1 do out[i] = items[i] end
    local mid = {}
    local after = n - star
    for i = star, c - after do mid[#mid + 1] = items[i] end
    out[star] = list(mid)
    for i = 1, after do out[star + i] = items[c - after + i] end
    return out
  end
  if c < n then raise(builtins.ValueError("not enough values to unpack (expected " .. n .. ", got " .. c .. ")")) end
  if c > n then raise(builtins.ValueError("too many values to unpack (expected " .. n .. ", got " .. c .. ")")) end
  return items
end
function R.stararg(x) return toList(x) end
function R.concat(...)
  local out, n = {}, 0
  for _, p in ipairs{ ... } do
    for i = 1, #p do n = n + 1; out[n] = p[i] end
  end
  out.n = n
  return out
end

-- ---------------------------------------------------------------- truth, compare
local function classOf(x) local m = getmt(x); if m and rawget_(m, "__class_mt") then return m end end
local function T(v)
  if v == true then return true end
  if v == false or v == nil or v == None or v == 0 or v == "" then return false end
  if type_(v) == "table" then
    local m = getmt(v)
    if m == List or m == Tuple then return v[1] ~= nil end
    if m == Dict or m == Set then return v.n > 0 end
    if classOf(v) then
      local f = classLookup(m, "__bool__")
      if f then return T(f(v)) end
      f = classLookup(m, "__len__")
      if f then return f(v) ~= 0 end
    end
  end
  return true
end
R.T = T
function R.and_(a, f) if T(a) then return f() end return a end
function R.or_(a, f) if T(a) then return a end return f() end
function R.if_(c, a, b) if c then return a() end return b() end
-- the same without closures, when the second part is a plain name or a constant
function R.andv(a, b) if T(a) then return b end return a end
function R.orv(a, b) if T(a) then return a end return b end
function R.ifv(c, a, b) if c then return a end return b end

local eq
eq = function(a, b)
  if a == b then return true end
  local ta, tb = type_(a), type_(b)
  if ta == "boolean" then a = a and 1 or 0; ta = "number" end
  if tb == "boolean" then b = b and 1 or 0; tb = "number" end
  if ta == "number" and tb == "number" then return a == b end
  if ta ~= "table" and tb ~= "table" then return false end
  if ta == "table" then
    local m = getmt(a)
    if m == List or m == Tuple then
      if getmt(b) ~= m or #a ~= #b then return false end
      for i = 1, #a do if not eq(a[i], b[i]) then return false end end
      return true
    elseif m == Dict then
      if getmt(b) ~= Dict or a.n ~= b.n then return false end
      for _, k in dkeys(a) do
        local v = dget(b, k)
        if v == nil or not eq(dget(a, k), v) then return false end
      end
      return true
    elseif m == Set then
      if getmt(b) ~= Set or a.n ~= b.n then return false end
      for _, k in dkeys(a) do if dget(b, k) == nil then return false end end
      return true
    elseif classOf(a) then
      local f = classLookup(m, "__eq__")
      if f then return T(f(a, b)) end
    end
  end
  if tb == "table" and classOf(b) then
    local f = classLookup(getmt(b), "__eq__")
    if f then return T(f(b, a)) end
  end
  return false
end
R.eq = eq
function R.ne(a, b)
  if type_(a) == "table" and classOf(a) then
    local f = classLookup(getmt(a), "__ne__")
    if f then return T(f(a, b)) end
  end
  return not eq(a, b)
end
local function typeName(x) return builtins.type(x).__name__ end
local function cmpErr(op, a, b) raise(builtins.TypeError("'" .. op .. "' not supported between instances of '" .. typeName(a) .. "' and '" .. typeName(b) .. "'")) end
local lt
local function cmp3(a, b)  -- -1, 0, 1 for sequences
  for i = 1, math.min(#a, #b) do
    if not eq(a[i], b[i]) then return lt(a[i], b[i]) and -1 or 1 end
  end
  return #a < #b and -1 or (#a > #b and 1 or 0)
end
local function numv(x) if x == true then return 1 elseif x == false then return 0 end return x end
lt = function(a, b)
  if mtype(a) and mtype(b) then return a < b end
  a, b = numv(a), numv(b)
  local ta, tb = type_(a), type_(b)
  if (ta == "number" and tb == "number") or (ta == "string" and tb == "string") then return a < b end
  if ta == "table" then
    local m = getmt(a)
    if (m == List or m == Tuple) and getmt(b) == m then return cmp3(a, b) < 0 end
    if m == Set and getmt(b) == Set then return a.n < b.n and R.issub(a, b) end
    if classOf(a) then
      local f = classLookup(m, "__lt__")
      if f then return T(f(a, b)) end
      if classLookup(m, "__gt__") and classOf(b) then return T(classLookup(getmt(b), "__gt__")(b, a)) end
    end
  end
  if tb == "table" and classOf(b) then
    local f = classLookup(getmt(b), "__gt__")
    if f then return T(f(b, a)) end
  end
  cmpErr("<", a, b)
end
R.lt = lt
function R.gt(a, b)
  if mtype(a) and mtype(b) then return a > b end
  if type_(a) == "table" and classOf(a) then
    local f = classLookup(getmt(a), "__gt__")
    if f then return T(f(a, b)) end
  end
  return lt(b, a)
end
function R.le(a, b)
  if mtype(a) and mtype(b) then return a <= b end
  a, b = numv(a), numv(b)
  local ta, tb = type_(a), type_(b)
  if (ta == "number" and tb == "number") or (ta == "string" and tb == "string") then return a <= b end
  if ta == "table" and classOf(a) then
    local f = classLookup(getmt(a), "__le__")
    if f then return T(f(a, b)) end
  end
  if ta == "table" and (getmt(a) == List or getmt(a) == Tuple) and getmt(b) == getmt(a) then return cmp3(a, b) <= 0 end
  if ta == "table" and getmt(a) == Set then return R.issub(a, b) end
  return not lt(b, a)
end
function R.ge(a, b)
  if mtype(a) and mtype(b) then return a >= b end
  if type_(a) == "table" and classOf(a) then
    local f = classLookup(getmt(a), "__ge__")
    if f then return T(f(a, b)) end
  end
  return R.le(b, a)
end
function R.is(a, b) return a == b or (a == nil and b == None) or (a == None and b == nil) end
function R.isnot(a, b) return not R.is(a, b) end
function R.in_(x, c)
  local t = type_(c)
  if t == "string" then
    if type_(x) ~= "string" then raise(builtins.TypeError("'in <string>' requires string as left operand")) end
    return c:find(x, 1, true) ~= nil
  end
  if t == "table" then
    local m = getmt(c)
    if m == Dict or m == Set then return c.idx[keyOf(x)] ~= nil end
    if m == List or m == Tuple then
      for i = 1, #c do if eq(c[i], x) then return true end end
      return false
    end
    if classOf(c) then
      local f = classLookup(m, "__contains__")
      if f then return T(f(c, x)) end
    end
  end
  for v in iter(c) do if eq(v, x) then return true end end
  return false
end
function R.notin(x, c) return not R.in_(x, c) end

-- ---------------------------------------------------------------- arithmetic
local function dunder(a, b, name, rname)
  if type_(a) == "table" and classOf(a) then
    local f = classLookup(getmt(a), name)
    if f then
      local r = f(a, b)
      if r ~= builtins.NotImplemented then return true, r end
    end
  end
  if type_(b) == "table" and classOf(b) then
    local f = classLookup(getmt(b), rname)
    if f then
      local r = f(b, a)
      if r ~= builtins.NotImplemented then return true, r end
    end
  end
  return false
end
local function opErr(op, a, b)
  raise(builtins.TypeError("unsupported operand type(s) for " .. op .. ": '" .. typeName(a) .. "' and '" .. typeName(b) .. "'"))
end
local function toNum(x)
  if x == true then return 1 elseif x == false then return 0 end
  return x
end
-- 64-bit integers overflow into floats (there are no big integers)
local function addInt(a, b)
  local r = a + b
  if (a ~ r) & (b ~ r) < 0 then return (a + 0.0) + b end
  return r
end
function R.add(a, b)
  local ma, mb = mtype(a), mtype(b)
  if ma == "integer" and mb == "integer" then
    local r = a + b
    if (a ~ r) & (b ~ r) >= 0 then return r end
    return (a + 0.0) + b
  end
  if ma and mb then return a + b end
  local ta, tb = type_(a), type_(b)
  if ta == "string" and tb == "string" then return a .. b end
  if ta == "table" and getmt(a) == getmt(b) and (getmt(a) == List or getmt(a) == Tuple) then
    local out, n = {}, #a
    for i = 1, n do out[i] = a[i] end
    for i = 1, #b do out[n + i] = b[i] end
    return setmt(out, getmt(a))
  end
  local ok, r = dunder(a, b, "__add__", "__radd__")
  if ok then return r end
  if ta == "boolean" or tb == "boolean" then
    local x, y = toNum(a), toNum(b)
    if mtype(x) and mtype(y) then return x + y end
  end
  if ta == "string" then raise(builtins.TypeError('can only concatenate str (not "' .. typeName(b) .. '") to str')) end
  opErr("+", a, b)
end
function R.sub(a, b)
  local ma, mb = mtype(a), mtype(b)
  if ma and mb then
    if ma == "integer" and mb == "integer" then
      local r = a - b
      if (a ~ b) & (a ~ r) < 0 then return (a + 0.0) - b end
      return r
    end
    return a - b
  end
  if type_(a) == "table" and getmt(a) == Set and getmt(b) == Set then
    local s = newSet()
    for _, k in dkeys(a) do if dget(b, k) == nil then dset(s, k, true) end end
    return s
  end
  local ok, r = dunder(a, b, "__sub__", "__rsub__")
  if ok then return r end
  local x, y = toNum(a), toNum(b)
  if mtype(x) and mtype(y) then return x - y end
  opErr("-", a, b)
end
local function repeatSeq(seq, n)
  if type_(seq) == "string" then return n > 0 and seq:rep(n) or "" end
  local out, c, top = {}, #seq, 0
  for _ = 1, n do
    for i = 1, c do top = top + 1; out[top] = seq[i] end
  end
  return setmt(out, getmt(seq))
end
function R.mul(a, b)
  local ma, mb = mtype(a), mtype(b)
  if ma == "integer" and mb == "integer" then
    if a < 2147483648 and a > -2147483648 and b < 2147483648 and b > -2147483648 then return a * b end
    local r = a * b
    if a ~= 0 and (r // a ~= b or (a == -1 and b == math.mininteger)) then return (a + 0.0) * b end
    return r
  end
  if ma and mb then return a * b end
  if mb == "integer" and (type_(a) == "string" or getmt(a) == List or getmt(a) == Tuple) then return repeatSeq(a, b) end
  if ma == "integer" and (type_(b) == "string" or getmt(b) == List or getmt(b) == Tuple) then return repeatSeq(b, a) end
  local ok, r = dunder(a, b, "__mul__", "__rmul__")
  if ok then return r end
  local x, y = toNum(a), toNum(b)
  if mtype(x) and mtype(y) then return x * y end
  opErr("*", a, b)
end
function R.div(a, b)
  if mtype(a) and mtype(b) then
    if b == 0 then raise(builtins.ZeroDivisionError("division by zero")) end
    return a / b
  end
  local ok, r = dunder(a, b, "__truediv__", "__rtruediv__")
  if ok then return r end
  local x, y = toNum(a), toNum(b)
  if mtype(x) and mtype(y) then return R.div(x, y) end
  opErr("/", a, b)
end
function R.idiv(a, b)
  if mtype(a) and mtype(b) then
    if b == 0 then raise(builtins.ZeroDivisionError("integer division or modulo by zero")) end
    return a // b
  end
  local ok, r = dunder(a, b, "__floordiv__", "__rfloordiv__")
  if ok then return r end
  local x, y = toNum(a), toNum(b)
  if mtype(x) and mtype(y) then return R.idiv(x, y) end
  opErr("//", a, b)
end
function R.mod(a, b)
  if mtype(a) and mtype(b) then
    if b == 0 then raise(builtins.ZeroDivisionError("integer division or modulo by zero")) end
    return a % b
  end
  if type_(a) == "string" then return R.percent(a, b) end
  local ok, r = dunder(a, b, "__mod__", "__rmod__")
  if ok then return r end
  local x, y = toNum(a), toNum(b)
  if mtype(x) and mtype(y) then return R.mod(x, y) end
  opErr("%", a, b)
end
function R.pow(a, b)
  if mtype(a) == "integer" and mtype(b) == "integer" and b >= 0 then
    local r = 1
    for _ = 1, b do
      r = R.mul(r, a)
      if mtype(r) == "float" then return (a + 0.0) ^ b end
    end
    return r
  end
  if mtype(a) and mtype(b) then
    if a == 0 and b < 0 then raise(builtins.ZeroDivisionError("0.0 cannot be raised to a negative power")) end
    return a ^ b
  end
  local ok, r = dunder(a, b, "__pow__", "__rpow__")
  if ok then return r end
  opErr("**", a, b)
end
function R.neg(a)
  if mtype(a) then return -a end
  if a == true then return -1 elseif a == false then return 0 end
  if classOf(a) then
    local f = classLookup(getmt(a), "__neg__")
    if f then return f(a) end
  end
  raise(builtins.TypeError("bad operand type for unary -: '" .. typeName(a) .. "'"))
end
function R.matmul(a, b)
  local ok, r = dunder(a, b, "__matmul__", "__rmatmul__")
  if ok then return r end
  opErr("@", a, b)
end
function R.shl(a, b) local ok, r = dunder(a, b, "__lshift__", "__rlshift__"); if ok then return r end return toNum(a) << toNum(b) end
function R.shr(a, b) local ok, r = dunder(a, b, "__rshift__", "__rrshift__"); if ok then return r end
  a, b = toNum(a), toNum(b)
  if a >= 0 then return a >> b end
  return a // (1 << b)
end
function R.band(a, b)
  if type_(a) == "table" and getmt(a) == Set then
    local s = newSet()
    for _, k in dkeys(a) do if dget(b, k) ~= nil then dset(s, k, true) end end
    return s
  end
  local ok, r = dunder(a, b, "__and__", "__rand__")
  if ok then return r end
  if type_(a) == "boolean" and type_(b) == "boolean" then return a and b end
  return toNum(a) & toNum(b)
end
function R.bor(a, b)
  if type_(a) == "table" and getmt(a) == Set then
    local s = newSet()
    for _, k in dkeys(a) do dset(s, k, true) end
    for _, k in dkeys(b) do dset(s, k, true) end
    return s
  end
  if type_(a) == "table" and getmt(a) == Dict then
    local d = dict()
    for _, k in dkeys(a) do dset(d, k, dget(a, k)) end
    for _, k in dkeys(b) do dset(d, k, dget(b, k)) end
    return d
  end
  local ok, r = dunder(a, b, "__or__", "__ror__")
  if ok then return r end
  if type_(a) == "boolean" and type_(b) == "boolean" then return a or b end
  return toNum(a) | toNum(b)
end
function R.bxor(a, b)
  if type_(a) == "table" and getmt(a) == Set then
    local s = newSet()
    for _, k in dkeys(a) do if dget(b, k) == nil then dset(s, k, true) end end
    for _, k in dkeys(b) do if dget(a, k) == nil then dset(s, k, true) end end
    return s
  end
  local ok, r = dunder(a, b, "__xor__", "__rxor__")
  if ok then return r end
  if type_(a) == "boolean" and type_(b) == "boolean" then return a ~= b end
  return toNum(a) ~ toNum(b)
end
function R.iadd(a, b)
  local ma = mtype(a)
  if ma == "integer" and mtype(b) == "integer" then
    local r = a + b
    if (a ~ r) & (b ~ r) >= 0 then return r end
    return (a + 0.0) + b
  elseif ma == "float" and mtype(b) then return a + b end
  if type_(a) == "table" then
    local m = getmt(a)
    if m == List then
      local n = #a
      local items = (getmt(b) == List or getmt(b) == Tuple) and b or toList(b)
      local c = #items
      for i = 1, c do a[n + i] = items[i] end
      return a
    end
    if classOf(a) then
      local f = classLookup(m, "__iadd__")
      if f then return f(a, b) end
    end
  end
  return R.add(a, b)
end
function R.imul(a, b) return R.mul(a, b) end

-- ---------------------------------------------------------------- text of values
local function floatRepr(x)
  if x ~= x then return "nan" end
  if x == math.huge then return "inf" elseif x == -math.huge then return "-inf" end
  if x == floor(x) and x > -1e16 and x < 1e16 then return sfmt("%.1f", x) end
  for p = 1, 17 do
    local s = sfmt("%." .. p .. "g", x)
    if tonumber(s) == x then
      if s:find("e", 1, true) then
        local m, e = s:match("^(.-)e([+-]%d+)$")
        local en = tonumber(e)
        if en < 0 and en >= -4 then return sfmt("%." .. (p - 1 - en) .. "f", x) end
        if en >= 0 and en < 16 then return sfmt("%.1f", x) end
        return m .. "e" .. (en < 0 and "-" or "+") .. sfmt("%02d", math.abs(en))
      end
      return s
    end
  end
  return sfmt("%.17g", x)
end
local function strRepr(s)
  local q = "'"
  if s:find("'", 1, true) and not s:find('"', 1, true) then q = '"' end
  local r = s:gsub("[\\\n\t\r%c" .. q .. "]", function(c)
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    if c == "\t" then return "\\t" end
    if c == "\r" then return "\\r" end
    if c == q then return "\\" .. q end
    return sfmt("\\x%02x", c:byte())
  end)
  return q .. r .. q
end
local repr
local function seqRepr(t, a, b, seen)
  local p = {}
  for i = 1, #t do p[i] = repr(t[i], seen) end
  return a .. concat(p, ", ") .. b
end
repr = function(v, seen)
  local t = type_(v)
  if t == "string" then return strRepr(v)
  elseif t == "number" then
    if mtype(v) == "integer" then return tostring(v) end
    return floatRepr(v)
  elseif t == "boolean" then return v and "True" or "False"
  elseif t == "nil" or v == None then return "None"
  elseif t == "function" then
    return "<function " .. (NAMES[v] or "<lambda>") .. ">"
  elseif t == "table" then
    local m = getmt(v)
    seen = seen or {}
    if seen[v] then return m == List and "[...]" or "{...}" end
    seen[v] = true
    local r
    if m == List then r = seqRepr(v, "[", "]", seen)
    elseif m == Tuple then r = #v == 1 and ("(" .. repr(v[1], seen) .. ",)") or seqRepr(v, "(", ")", seen)
    elseif m == Dict then
      local p = {}
      for _, k in dkeys(v) do p[#p + 1] = repr(k, seen) .. ": " .. repr(dget(v, k), seen) end
      r = "{" .. concat(p, ", ") .. "}"
    elseif m == Set then
      if v.n == 0 then r = "set()"
      else
        local p = {}
        for _, k in dkeys(v) do p[#p + 1] = repr(k, seen) end
        r = "{" .. concat(p, ", ") .. "}"
      end
    elseif m == TypeMT then r = "<class '" .. tostring(rawget_(v, "__name__")) .. "'>"
    elseif m and rawget_(m, "__class_mt") then
      local f = classLookup(m, "__repr__")
      if f then r = f(v)
      else r = "<" .. m.__name__ .. " object>" end
    elseif m and m.__repr then r = m.__repr(v)
    elseif m and m.__name__ then r = "<" .. m.__name__ .. " object>"
    else r = "<module>" end
    seen[v] = nil
    return r
  end
  return tostring(v)
end
R.repr = repr
local function str(v)
  local t = type_(v)
  if t == "string" then return v end
  if t == "table" then
    local m = getmt(v)
    if m and rawget_(m, "__class_mt") then
      local f = classLookup(m, "__str__")
      if f then return f(v) end
    end
  end
  return repr(v)
end
R.str = str

-- the mini language of format(): [[fill]align][sign][#][0][width][,][.prec][type]
local function fmtSpec(v, spec)
  if spec == "" then return str(v) end
  if type_(v) == "table" and classOf(v) then
    local f = classLookup(getmt(v), "__format__")
    if f then return f(v, spec) end
  end
  local fill, align, rest = spec:match("^(.[\128-\191]*)([<>^=])(.*)$")
  if not fill then
    align, rest = spec:match("^([<>^=])(.*)$")
    fill = " "
    if not align then rest = spec end
  end
  local sign, alt, zero, width, comma, prec, ty = rest:match("^([+%- ]?)(#?)(0?)(%d*)([,_]?)%.?(%d*)([%a%%]?)$")
  if not sign then raise(builtins.ValueError("Invalid format specifier '" .. spec .. "'")) end
  local hasDot = rest:find(".", 1, true) ~= nil
  local s
  if v == true then v = 1 elseif v == false then v = 0 end
  if mtype(v) then
    local neg = v < 0 or (v == 0 and 1 / v < 0)
    local a = neg and -v or v
    if ty == "" and mtype(v) == "integer" then s = tostring(a)
    elseif ty == "d" then
      if mtype(v) == "float" then raise(builtins.ValueError("Unknown format code 'd' for object of type 'float'")) end
      s = tostring(a)
    elseif ty == "x" or ty == "X" or ty == "o" then
      s = sfmt("%" .. ty, a)
      if alt ~= "" then s = "0" .. ty .. s end
    elseif ty == "b" then
      local bits = {}
      local x = a
      if x == 0 then bits[1] = "0" end
      while x > 0 do table.insert(bits, 1, tostring(x & 1)); x = x >> 1 end
      s = concat(bits)
      if alt ~= "" then s = "0b" .. s end
    elseif ty == "c" then s = utf8.char(a)
    elseif ty == "f" or ty == "F" then s = sfmt("%." .. (prec ~= "" and prec or "6") .. "f", a)
    elseif ty == "e" or ty == "E" then s = sfmt("%." .. (prec ~= "" and prec or "6") .. ty, a)
    elseif ty == "g" or ty == "G" then s = sfmt("%." .. (prec ~= "" and prec or "6") .. ty, a)
    elseif ty == "%" then s = sfmt("%." .. (prec ~= "" and prec or "6") .. "f", a * 100) .. "%"
    elseif ty == "n" then s = tostring(a)
    elseif ty == "" then
      if hasDot then s = sfmt("%." .. prec .. "g", a) else s = floatRepr(a) end
    else raise(builtins.ValueError("Unknown format code '" .. ty .. "'")) end
    if comma ~= "" then
      local ip, fp = s:match("^(%d+)(.*)$")
      if ip then
        ip = ip:reverse():gsub("(%d%d%d)", "%1" .. comma):reverse():gsub("^" .. (comma == "," and "," or "_"), "")
        s = ip .. fp
      end
    end
    local sg = neg and "-" or (sign == "+" and "+" or (sign == " " and " " or ""))
    local w = tonumber(width) or 0
    if zero ~= "" and not fill:find("^ ") == false and not align then fill = "0"; align = "=" end
    if zero ~= "" and not align then fill = "0"; align = "=" end
    if align == "=" then
      local padN = w - #sg - #s
      return sg .. (padN > 0 and fill:rep(padN) or "") .. s
    end
    s = sg .. s
    align = align or ">"
  else
    s = str(v)
    if hasDot and prec ~= "" then s = R.sliceText(s, 0, tonumber(prec)) end
    align = align or "<"
  end
  local w = tonumber(width) or 0
  local n = utf8.len(s) or #s
  if n >= w then return s end
  local pad = w - n
  if align == "<" then return s .. fill:rep(pad)
  elseif align == ">" then return fill:rep(pad) .. s end
  local l = pad // 2
  return fill:rep(l) .. s .. fill:rep(pad - l)
end
R.fmt = function(v, spec) return fmtSpec(v, spec) end

function R.percent(fmt, args)
  local i = 0
  local items = getmt(args) == Tuple and args or { args }
  local function piece(key, flags, width, prec, conv)
    if conv == "%" then return "%" end
    local v
    if key ~= "" and key:sub(1, 1) == "(" then v = dget(args, key:sub(2, -2))
    else
      i = i + 1
      v = items[i]
      if v == nil then raise(builtins.TypeError("not enough arguments for format string")) end
    end
    local spec = "%" .. flags .. width .. (prec ~= "" and ("." .. prec) or "")
    if conv == "s" then return sfmt(spec .. "s", str(v))
    elseif conv == "r" then return sfmt(spec .. "s", repr(v))
    elseif conv == "d" or conv == "i" or conv == "u" then
      if not mtype(v) and type_(v) ~= "boolean" then raise(builtins.TypeError("%d format: a real number is required, not " .. typeName(v))) end
      return sfmt(spec .. "d", math.tointeger(floor(toNum(v))) or 0)
    elseif conv == "c" then return type_(v) == "number" and utf8.char(v) or v
    elseif conv == "x" or conv == "X" or conv == "o" then return sfmt(spec .. conv, v)
    else return sfmt(spec .. conv, toNum(v)) end
  end
  local out
  if fmt:find("%(") then out = fmt:gsub("%%(%([%w_]+%))([#0%- +]*)(%d*)%.?(%d*)([%a%%])", piece) end
  out = (out or fmt):gsub("%%([#0%- +]*)(%d*)%.?(%d*)([%a%%])", function(f, w, p_, c) return piece("", f, w, p_, c) end)
  return out
end

-- ---------------------------------------------------------------- slices and indexing
local Slice = newBuiltinType("slice")
function R.slice(a, b, c) return setmt({ a = a, b = b, c = c }, Slice) end
local function sliceRange(s, n)
  local step = s.c == None and 1 or s.c
  if step == 0 then raise(builtins.ValueError("slice step cannot be zero")) end
  local a, b = s.a, s.b
  if step > 0 then
    a = a == None and 0 or a
    b = b == None and n or b
    if a < 0 then a = math.max(a + n, 0) end
    if b < 0 then b = math.max(b + n, 0) end
    if a > n then a = n end
    if b > n then b = n end
  else
    a = a == None and n - 1 or a
    b = b == None and -1 or (b < 0 and b + n or b)
    if b < -1 then b = -1 end
    if a < 0 then a = a + n end
    if a < 0 then a = -1 end
    if a >= n then a = n - 1 end
    if s.b ~= None and s.b < 0 and s.b + n < 0 then b = -1 end
  end
  return a, b, step
end
function R.sliceText(s, a, b)
  if isAscii(s) then return s:sub(a + 1, b) end
  local c = utf8chars(s)
  return concat(c, "", a + 1, math.min(b, #c))
end
local function strIndex(s, i)
  if isAscii(s) then
    local n = #s
    if i < 0 then i = i + n end
    if i < 0 or i >= n then raise(builtins.IndexError("string index out of range")) end
    return s:sub(i + 1, i + 1)
  end
  local c = utf8chars(s)
  local n = #c
  if i < 0 then i = i + n end
  if i < 0 or i >= n then raise(builtins.IndexError("string index out of range")) end
  return c[i + 1]
end
function R.GI(o, i)
  local t = type_(o)
  if t == "table" then
    local m = getmt(o)
    if m == List or m == Tuple then
      if mtype(i) == "integer" then
        if i < 0 then i = i + #o end
        local v = o[i + 1]
        if v == nil or i < 0 then raise(builtins.IndexError((m == List and "list" or "tuple") .. " index out of range")) end
        return v
      end
      if getmt(i) == Slice then
        local a, b, step = sliceRange(i, #o)
        local out, n = {}, 0
        local j = a
        while (step > 0 and j < b) or (step < 0 and j > b) do
          n = n + 1
          out[n] = o[j + 1]
          j = j + step
        end
        return setmt(out, m)
      end
      if i == true then return o[2] elseif i == false then return o[1] end
      raise(builtins.TypeError("list indices must be integers or slices, not " .. typeName(i)))
    end
    if m == Dict then
      local v = dget(o, i)
      if v == nil then
        local missing = rawget_(o, "__missing")
        if missing then
          v = missing()
          dset(o, i, v)
          return v
        end
        raise(builtins.KeyError(i))
      end
      return v
    end
    if classOf(o) then
      local f = classLookup(m, "__getitem__")
      if f then return f(o, i) end
    end
    if m == R.Range then return R.rangeGI(o, i) end
  elseif t == "string" then
    if mtype(i) == "integer" then return strIndex(o, i) end
    if getmt(i) == Slice then
      local c = isAscii(o) and nil or utf8chars(o)
      local n = c and #c or #o
      local a, b, step = sliceRange(i, n)
      if step == 1 and not c then return o:sub(a + 1, b) end
      local out, top = {}, 0
      local j = a
      while (step > 0 and j < b) or (step < 0 and j > b) do
        top = top + 1
        out[top] = c and c[j + 1] or o:sub(j + 1, j + 1)
        j = j + step
      end
      return concat(out)
    end
    raise(builtins.TypeError("string indices must be integers"))
  end
  raise(builtins.TypeError("'" .. typeName(o) .. "' object is not subscriptable"))
end
function R.SI(o, i, v)
  local m = getmt(o)
  if m == List then
    if mtype(i) == "integer" then
      local n = #o
      if i < 0 then i = i + n end
      if i < 0 or i >= n then raise(builtins.IndexError("list assignment index out of range")) end
      o[i + 1] = v
      return
    end
    if getmt(i) == Slice then
      local a, b, step = sliceRange(i, #o)
      local items = toList(v)
      if step == 1 then
        if b < a then b = a end
        local tail = {}
        for j = b + 1, #o do tail[#tail + 1] = o[j] end
        for j = #o, a + 1, -1 do o[j] = nil end
        for _, x in ipairs(items) do o[#o + 1] = x end
        for _, x in ipairs(tail) do o[#o + 1] = x end
        return
      end
      local j, k = a, 1
      while (step > 0 and j < b) or (step < 0 and j > b) do
        o[j + 1] = items[k]
        k = k + 1
        j = j + step
      end
      return
    end
  elseif m == Dict then dset(o, i, v); return
  elseif classOf(o) then
    local f = classLookup(m, "__setitem__")
    if f then f(o, i, v); return end
  end
  raise(builtins.TypeError("'" .. typeName(o) .. "' object does not support item assignment"))
end
function R.DI(o, i)
  local m = getmt(o)
  if m == List then
    if getmt(i) == Slice then
      local a, b, step = sliceRange(i, #o)
      local keep = {}
      local gone = {}
      local j = a
      while (step > 0 and j < b) or (step < 0 and j > b) do gone[j + 1] = true; j = j + step end
      for k = 1, #o do if not gone[k] then keep[#keep + 1] = o[k] end end
      for k = #o, 1, -1 do o[k] = nil end
      for k, x in ipairs(keep) do o[k] = x end
      return
    end
    if i < 0 then i = i + #o end
    if i < 0 or i >= #o then raise(builtins.IndexError("list assignment index out of range")) end
    table.remove(o, i + 1)
  elseif m == Dict then
    if not ddel(o, i) then raise(builtins.KeyError(i)) end
  elseif classOf(o) then
    local f = classLookup(m, "__delitem__")
    if f then f(o, i) end
  else raise(builtins.TypeError("object doesn't support item deletion")) end
end

-- ---------------------------------------------------------------- attributes
local strM, listM, dictM, setM, tupleM, numM = {}, {}, {}, {}, {}, {}
local function typeMethods(o)
  local t = type_(o)
  if t == "string" then return strM end
  if t == "number" or t == "boolean" then return numM end
  if t == "table" then
    local m = getmt(o)
    if m == List then return listM elseif m == Dict then return dictM elseif m == Set then return setM elseif m == Tuple then return tupleM end
  end
end
local function attrErr(o, n)
  local c = type_(o) == "table" and getmt(o) == TypeMT and ("type object '" .. tostring(rawget_(o, "__name__")) .. "'") or ("'" .. typeName(o) .. "' object")
  raise(builtins.AttributeError(c .. " has no attribute '" .. n .. "'"))
end
local Super = {}
Super.__index = function(t, k)
  local c = rawget_(t, "__c")
  local bases = rawget_(c, "__bases")
  for i = 1, #bases do
    local v = classLookup(bases[i], k)
    if v ~= nil then return v end
  end
  return nil
end
function R.super(c, self) return setmt({ __c = c, __self = self }, Super) end
local function bind(f, o) return function(...) return f(o, ...) end end
local plainSA

function R.GA(o, n)
  local t = type_(o)
  if t == "table" then
    local m = getmt(o)
    if m == TypeMT then
      local v = o[n]
      if n == "__name__" or n == "__qualname__" then return rawget_(o, n) end
      if v == nil then attrErr(o, n) end
      local vm = getmt(v)
      if vm == Static then return v.f end
      if vm == ClassM then return bind(v.f, o) end
      return v
    end
    if m == Super then
      local v = o[n]
      if v == nil then attrErr(rawget_(o, "__self"), n) end
      if type_(v) == "function" then return bind(v, rawget_(o, "__self")) end
      return v
    end
    if m and rawget_(m, "__class_mt") then
      local v = rawget_(o, n)
      if v ~= nil then return v end
      if n == "__class__" then return m end
      if n == "__dict__" then
        local d = dict()
        for k, x in pairs(o) do dset(d, k, x) end
        return d
      end
      v = classLookup(m, n)
      if v == nil then
        local ga = classLookup(m, "__getattr__")
        if ga then return ga(o, n) end
        attrErr(o, n)
      end
      local tv = type_(v)
      if tv == "function" then return bind(v, o) end
      if tv == "table" then
        local vm = getmt(v)
        if vm == Property then return v.get(o) end
        if vm == Static then return v.f end
        if vm == ClassM then return bind(v.f, m) end
      end
      return v
    end
    if m == nil or m.__module then
      local v = o[n]
      if v == nil then attrErr(o, n) end
      return v
    end
    local tm = typeMethods(o)
    if tm and tm[n] then return bind(tm[n], o) end
    if m and m[n] ~= nil then
      local v = m[n]
      if type_(v) == "function" then return bind(v, o) end
      return v
    end
    if n == "__class__" then return builtins.type(o) end
    local fieldv = rawget_(o, n)
    if fieldv ~= nil then return fieldv end
    attrErr(o, n)
  end
  if t == "function" then
    if n == "__name__" then return NAMES[o] or "<lambda>" end
    if n == "__doc__" then return None end
    local fa = FN[o] and FN[o].attrs
    if fa and fa[n] ~= nil then return fa[n] end
    attrErr(o, n)
  end
  local tm = typeMethods(o)
  if tm and tm[n] then return bind(tm[n], o) end
  if n == "__class__" then return builtins.type(o) end
  attrErr(o, n)
end
-- the classes whose attributes NAME are stored plainly (no property, no __setattr__), forgotten when a class changes
plainSA = setmt({}, { __mode = "k" })
function R.SA(o, n, v)
  if type_(o) ~= "table" then
    if type_(o) == "function" then
      FN[o] = FN[o] or { names = {} }
      FN[o].attrs = FN[o].attrs or {}
      FN[o].attrs[n] = v
      return
    end
    raise(builtins.AttributeError("'" .. typeName(o) .. "' object has no attribute '" .. n .. "'"))
  end
  local m = getmt(o)
  if m and rawget_(m, "__class_mt") then
    local pc = plainSA[m]
    if pc and pc[n] then rawset(o, n, v); return end
    local cv = classLookup(m, n)
    if type_(cv) == "table" and getmt(cv) == Property then
      if not cv.set then raise(builtins.AttributeError("can't set attribute '" .. n .. "'")) end
      cv.set(o, v)
      return
    end
    local sa = classLookup(m, "__setattr__")
    if sa then sa(o, n, v); return end
    -- neither a property nor __setattr__: the next time it is a plain store
    if not pc then pc = {}; plainSA[m] = pc end
    pc[n] = true
    rawset(o, n, v)
    return
  end
  if m == TypeMT then plainSA = setmt({}, { __mode = "k" }) end
  o[n] = v
end
function R.DA(o, n) if getmt(o) == TypeMT then plainSA = setmt({}, { __mode = "k" }) end rawset(o, n, nil) end
function R.CM(o, n, ...)
  local t = type_(o)
  if t == "table" then
    local m = getmt(o)
    if m == List then local f = listM[n]; if f then return f(o, ...) end
    elseif m == Dict then local f = dictM[n]; if f then return f(o, ...) end
    elseif m and rawget_(m, "__class_mt") then
      local v = rawget_(o, n)
      if v ~= nil then return v(...) end
      v = classLookup(m, n)
      if type_(v) == "function" then return v(o, ...) end
    elseif m == Super then
      local v = o[n]
      if type_(v) == "function" then return v(rawget_(o, "__self"), ...) end
    end
  elseif t == "string" then
    local f = strM[n]
    if f then return f(o, ...) end
  end
  return R.GA(o, n)(...)
end
function R.CMK(o, n, pos, kw)
  local t = type_(o)
  if t == "table" and getmt(o) and rawget_(getmt(o), "__class_mt") then
    local v = classLookup(getmt(o), n)
    if type_(v) == "function" and rawget_(o, n) == nil then
      local a = { o }
      for i = 1, pos.n or #pos do a[i + 1] = pos[i] end
      a.n = (pos.n or #pos) + 1
      return callKw(v, a, kw)
    end
  elseif t == "table" and getmt(o) == Super then
    local v = o[n]
    if type_(v) == "function" then
      local a = { rawget_(o, "__self") }
      for i = 1, pos.n or #pos do a[i + 1] = pos[i] end
      a.n = (pos.n or #pos) + 1
      return callKw(v, a, kw)
    end
  end
  return callKw(R.GA(o, n), pos, kw)
end

-- ---------------------------------------------------------------- str methods
local function plainSplit(s, sep, maxn)
  local out, i = {}, 1
  while true do
    local a, b = s:find(sep, i, true)
    if not a or (maxn and #out >= maxn) then break end
    out[#out + 1] = s:sub(i, a - 1)
    i = b + 1
  end
  out[#out + 1] = s:sub(i)
  return list(out)
end
local function opt(v) if v == None then return nil end return v end
function strM.split(s, sep, maxn)
  local kw = R.takekw()
  if kw then sep = kw.sep or sep; maxn = kw.maxsplit or maxn end
  sep, maxn = opt(sep), opt(maxn)
  if maxn == -1 then maxn = nil end
  if sep then return plainSplit(s, sep, maxn) end
  local out = {}
  local i = 1
  while true do
    local a, b = s:find("%S+", i)
    if not a then break end
    if maxn and #out >= maxn then
      out[#out + 1] = s:sub(a):gsub("%s+$", "")
      break
    end
    out[#out + 1] = s:sub(a, b)
    i = b + 1
  end
  return list(out)
end
function strM.rsplit(s, sep, maxn)
  sep, maxn = opt(sep), opt(maxn)
  if not maxn or maxn == -1 then return strM.split(s, sep) end
  local all = strM.split(s, sep)
  local n = #all
  if n <= maxn + 1 then return all end
  local head = {}
  for i = 1, n - maxn do head[i] = all[i] end
  local out = { concat(head, sep or " ") }
  for i = n - maxn + 1, n do out[#out + 1] = all[i] end
  return list(out)
end
function strM.splitlines(s, keep)
  local out = {}
  if keep and keep ~= None then
    for line in s:gmatch("[^\n]*\n?") do if line ~= "" then out[#out + 1] = line end end
    return list(out)
  end
  for line in (s:sub(-1) == "\n" and s or s .. "\n"):gmatch("(.-)\r?\n") do out[#out + 1] = line end
  if s == "" then out = {} end
  return list(out)
end
function strM.join(s, it)
  local items = (getmt(it) == List or getmt(it) == Tuple) and it or toList(it)
  for i = 1, #items do
    if type_(items[i]) ~= "string" then raise(builtins.TypeError("sequence item " .. (i - 1) .. ": expected str instance, " .. typeName(items[i]) .. " found")) end
  end
  return concat(items, s)
end
local function stripSet(c) return "[" .. c:gsub("[%^%]%-%%]", "%%%0") .. "]" end
function strM.strip(s, c)
  c = opt(c)
  if c then local p = stripSet(c); return (s:gsub("^" .. p .. "+", ""):gsub(p .. "+$", "")) end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
function strM.lstrip(s, c) c = opt(c); return (s:gsub("^" .. (c and stripSet(c) or "%s") .. "+", "")) end
function strM.rstrip(s, c) c = opt(c); return (s:gsub((c and stripSet(c) or "%s") .. "+$", "")) end
function strM.upper(s) return s:upper() end
function strM.lower(s) return s:lower() end
strM.casefold = strM.lower
function strM.title(s) return (s:lower():gsub("(%a)(%a*)", function(a, b) return a:upper() .. b end)) end
function strM.capitalize(s) return s:sub(1, 1):upper() .. s:sub(2):lower() end
function strM.swapcase(s) return (s:gsub("%a", function(c) return c:lower() == c and c:upper() or c:lower() end)) end
function strM.startswith(s, p, a)
  if getmt(p) == Tuple then
    for i = 1, #p do if strM.startswith(s, p[i], a) then return true end end
    return false
  end
  a = a or 0
  return s:sub(a + 1, a + #p) == p
end
function strM.endswith(s, p)
  if getmt(p) == Tuple then
    for i = 1, #p do if strM.endswith(s, p[i]) then return true end end
    return false
  end
  return p == "" or s:sub(-#p) == p
end
function strM.find(s, p, a, b)
  local start = a and (a < 0 and #s + a or a) or 0
  local text = b and s:sub(1, b) or s
  local i = text:find(p, start + 1, true)
  return i and i - 1 or -1
end
function strM.rfind(s, p)
  local last, i = -1, 1
  while true do
    local a = s:find(p, i, true)
    if not a then return last end
    last = a - 1
    i = a + 1
  end
end
function strM.index(s, p, a)
  local i = strM.find(s, p, a)
  if i < 0 then raise(builtins.ValueError("substring not found")) end
  return i
end
function strM.rindex(s, p)
  local i = strM.rfind(s, p)
  if i < 0 then raise(builtins.ValueError("substring not found")) end
  return i
end
function strM.count(s, p)
  if p == "" then return (utf8.len(s) or #s) + 1 end
  local n, i = 0, 1
  while true do
    local a, b = s:find(p, i, true)
    if not a then return n end
    n = n + 1
    i = b + 1
  end
end
function strM.replace(s, a, b, n)
  if a == "" then return s end
  local out, i, c = {}, 1, 0
  while true do
    local x, y = s:find(a, i, true)
    if not x or (n and n >= 0 and c >= n) then break end
    out[#out + 1] = s:sub(i, x - 1)
    out[#out + 1] = b
    i = y + 1
    c = c + 1
  end
  out[#out + 1] = s:sub(i)
  return concat(out)
end
function strM.isdigit(s) return s ~= "" and not s:find("%D") end
strM.isnumeric, strM.isdecimal = strM.isdigit, strM.isdigit
function strM.isalpha(s) return s ~= "" and not s:find("[^%a\128-\255]") end
function strM.isalnum(s) return s ~= "" and not s:find("[^%w\128-\255]") end
function strM.isspace(s) return s ~= "" and not s:find("%S") end
function strM.isupper(s) return s:find("%u") ~= nil and not s:find("%l") end
function strM.islower(s) return s:find("%l") ~= nil and not s:find("%u") end
function strM.isidentifier(s) return s:find("^[%a_][%w_]*$") ~= nil end
function strM.istitle(s) return s == strM.title(s) and s:find("%a") ~= nil end
local function padLen(s) return utf8.len(s) or #s end
function strM.center(s, w, f) f = f or " "; local p = w - padLen(s); if p <= 0 then return s end local l = p // 2 + (p & w & 1); return f:rep(l) .. s .. f:rep(p - l) end
function strM.ljust(s, w, f) f = f or " "; local p = w - padLen(s); return p > 0 and s .. f:rep(p) or s end
function strM.rjust(s, w, f) f = f or " "; local p = w - padLen(s); return p > 0 and f:rep(p) .. s or s end
function strM.zfill(s, w)
  local p = w - #s
  if p <= 0 then return s end
  if s:sub(1, 1) == "-" or s:sub(1, 1) == "+" then return s:sub(1, 1) .. ("0"):rep(p) .. s:sub(2) end
  return ("0"):rep(p) .. s
end
function strM.partition(s, p)
  local a, b = s:find(p, 1, true)
  if not a then return tuple{ s, "", "" } end
  return tuple{ s:sub(1, a - 1), p, s:sub(b + 1) }
end
function strM.rpartition(s, p)
  local i = strM.rfind(s, p)
  if i < 0 then return tuple{ "", "", s } end
  return tuple{ s:sub(1, i), p, s:sub(i + #p + 1) }
end
function strM.removeprefix(s, p) if strM.startswith(s, p) then return s:sub(#p + 1) end return s end
function strM.removesuffix(s, p) if p ~= "" and strM.endswith(s, p) then return s:sub(1, -#p - 1) end return s end
function strM.encode(s) return s end
function strM.decode(s) return s end
function strM.expandtabs(s, n) return (s:gsub("\t", (" "):rep(n or 8))) end
function strM.format(s, ...)
  local args = { ... }
  local kw = R.takekw() or {}
  local auto = 0
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == "{" then
      if s:sub(i + 1, i + 1) == "{" then out[#out + 1] = "{"; i = i + 2
      else
        local j = s:find("}", i, true)
        if not j then raise(builtins.ValueError("expected '}' before end of string")) end
        local field = s:sub(i + 1, j - 1)
        local name_, spec = field:match("^([^:]*):?(.*)$")
        local conv
        local nm, cv = name_:match("^(.-)!(%a)$")
        if nm then name_ = nm; conv = cv end
        local base, rest = name_:match("^([%w_]*)(.*)$")
        local v
        if base == "" then v = args[auto + 1]; auto = auto + 1
        elseif tonumber(base) then v = args[tonumber(base) + 1]
        else v = kw[base] end
        if v == nil then raise(builtins.IndexError("Replacement index " .. auto - 1 .. " out of range for positional args tuple")) end
        for kind, key in rest:gmatch("([%.%[])([^%.%[%]]+)%]?") do
          if kind == "." then v = R.GA(v, key)
          else v = R.GI(v, tonumber(key) or key) end
        end
        if conv == "r" then v = repr(v) elseif conv == "s" then v = str(v) end
        out[#out + 1] = fmtSpec(v, spec)
        i = j + 1
      end
    elseif c == "}" then out[#out + 1] = "}"; i = i + (s:sub(i + 1, i + 1) == "}" and 2 or 1)
    else
      local j = s:find("[{}]", i) or n + 1
      out[#out + 1] = s:sub(i, j - 1)
      i = j
    end
  end
  return concat(out)
end

-- ---------------------------------------------------------------- list, tuple, dict, set methods
function listM.append(l, x) l[#l + 1] = x; return None end
function listM.extend(l, x) R.iadd(l, x); return None end
function listM.insert(l, i, x)
  local n = #l
  if i < 0 then i = math.max(i + n, 0) end
  if i > n then i = n end
  table.insert(l, i + 1, x)
  return None
end
function listM.pop(l, i)
  local n = #l
  if n == 0 then raise(builtins.IndexError("pop from empty list")) end
  if i == nil then local v = l[n]; l[n] = nil; return v end
  if i < 0 then i = i + n end
  if i < 0 or i >= n then raise(builtins.IndexError("pop index out of range")) end
  return table.remove(l, i + 1)
end
function listM.remove(l, x)
  for i = 1, #l do if eq(l[i], x) then table.remove(l, i); return None end end
  raise(builtins.ValueError("list.remove(x): x not in list"))
end
function listM.clear(l) for i = #l, 1, -1 do l[i] = nil end return None end
function listM.index(l, x, a)
  for i = (a or 0) + 1, #l do if eq(l[i], x) then return i - 1 end end
  raise(builtins.ValueError(repr(x) .. " is not in list"))
end
function listM.count(l, x) local c = 0; for i = 1, #l do if eq(l[i], x) then c = c + 1 end end return c end
function listM.reverse(l)
  local i, j = 1, #l
  while i < j do l[i], l[j] = l[j], l[i]; i = i + 1; j = j - 1 end
  return None
end
function listM.copy(l) local o = {}; for i = 1, #l do o[i] = l[i] end return list(o) end
-- a stable merge sort, as Python's is
local function stableSort(a, less)
  local n = #a
  if n < 2 then return end
  local b = {}
  local w = 1
  while w < n do
    local i = 1
    while i <= n do
      local mid, hi = math.min(i + w, n + 1), math.min(i + 2 * w, n + 1)
      local l, r, k = i, mid, i
      while l < mid and r < hi do
        if less(a[r], a[l]) then b[k] = a[r]; r = r + 1
        else b[k] = a[l]; l = l + 1 end
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
local function sortInto(l, keyf, rev)
  local items = {}
  for i = 1, #l do items[i] = { keyf and keyf(l[i]) or l[i], l[i] } end
  local less = rev and function(x, y) return lt(y[1], x[1]) end or function(x, y) return lt(x[1], y[1]) end
  local sorted = stableSort(items, less) or items
  for i = 1, #sorted do l[i] = sorted[i][2] end
end
function listM.sort(l)
  local kw = R.takekw() or {}
  sortInto(l, opt(kw.key), T(kw.reverse))
  return None
end
tupleM.index, tupleM.count = listM.index, listM.count
function dictM.get(d, k, def)
  local v = dget(d, k)
  if v == nil then return def == nil and None or def end
  return v
end
local function viewList(t) return list(t) end
function dictM.keys(d) local o = {}; for _, k in dkeys(d) do o[#o + 1] = k end return viewList(o) end
function dictM.values(d) local o = {}; for _, k in dkeys(d) do o[#o + 1] = dget(d, k) end return viewList(o) end
function dictM.items(d) local o = {}; for _, k in dkeys(d) do o[#o + 1] = tuple{ k, dget(d, k) } end return viewList(o) end
function dictM.pop(d, k, def)
  local v = dget(d, k)
  if v == nil then
    if def ~= nil then return def end
    raise(builtins.KeyError(k))
  end
  ddel(d, k)
  return v
end
function dictM.popitem(d)
  for i = d.top, 1, -1 do
    local k = d.ks[i]
    if k ~= nil then
      local v = d.vs[i]
      ddel(d, k)
      return tuple{ k, v }
    end
  end
  raise(builtins.KeyError("popitem(): dictionary is empty"))
end
function dictM.setdefault(d, k, def)
  local v = dget(d, k)
  if v ~= nil then return v end
  def = def == nil and None or def
  dset(d, k, def)
  return def
end
function dictM.update(d, o)
  local kw = R.takekw()
  if o ~= nil then
    if getmt(o) == Dict then for _, k in dkeys(o) do dset(d, k, dget(o, k)) end
    else for p in iter(o) do local x = toList(p); dset(d, x[1], x[2]) end end
  end
  if kw then for k, v in pairs(kw) do dset(d, k, v) end end
  return None
end
function dictM.clear(d) d.idx, d.ks, d.vs, d.top, d.n = {}, {}, {}, 0, 0; return None end
function dictM.copy(d) local c = dict(); for _, k in dkeys(d) do dset(c, k, dget(d, k)) end
  c.__missing = rawget_(d, "__missing")
  return c
end
function setM.add(s, x) dset(s, x, true); return None end
function setM.remove(s, x) if not ddel(s, x) then raise(builtins.KeyError(x)) end return None end
function setM.discard(s, x) ddel(s, x); return None end
function setM.pop(s)
  for i = 1, s.top do
    local k = s.ks[i]
    if k ~= nil then ddel(s, k); return k end
  end
  raise(builtins.KeyError("pop from an empty set"))
end
function setM.clear(s) return dictM.clear(s) end
function setM.copy(s) local c = newSet(); for _, k in dkeys(s) do dset(c, k, true) end return c end
local function asSet(x) if getmt(x) == Set then return x end return builtins.set(x) end
function setM.union(s, o) return R.bor(s, asSet(o)) end
function setM.intersection(s, o) return R.band(s, asSet(o)) end
function setM.difference(s, o) return R.sub(s, asSet(o)) end
function setM.symmetric_difference(s, o) return R.bxor(s, asSet(o)) end
function setM.update(s, o) for v in iter(o) do dset(s, v, true) end return None end
function R.issub(a, b) for _, k in dkeys(a) do if dget(b, k) == nil then return false end end return true end
function setM.issubset(a, b) return R.issub(a, asSet(b)) end
function setM.issuperset(a, b) return R.issub(asSet(b), a) end
function setM.isdisjoint(a, b) b = asSet(b); for _, k in dkeys(a) do if dget(b, k) ~= nil then return false end end return true end
function numM.is_integer(x) return x == floor(x) end
function numM.real(x) return x end
function numM.conjugate(x) return x end
function numM.bit_length(x) local n = 0; x = math.abs(x); while x > 0 do n = n + 1; x = x >> 1 end return n end

-- ---------------------------------------------------------------- builtins
local B = builtins
builtins.NotImplemented = setmt({}, { __name = "NotImplementedType" })
builtins.Ellipsis = None
List.__name__, Tuple.__name__, Dict.__name__, Set.__name__ = "list", "tuple", "dict", "set"

local function valueType(name, ctor, check, base)
  local t = { __name__ = name, __bases = base and { base } or { object }, __ctor = ctor, __check = check, __class_builtin = true }
  t.__index = t
  B[name] = setmt(t, TypeMT)
  return t
end
valueType("int", function(_, x, base)
  if x == nil then return 0 end
  if base and base ~= None then
    local s = strM.strip(x):lower()
    local neg = s:sub(1, 1) == "-"
    if neg or s:sub(1, 1) == "+" then s = s:sub(2) end
    if base == 16 then s = s:gsub("^0x", "") elseif base == 2 then s = s:gsub("^0b", "") elseif base == 8 then s = s:gsub("^0o", "") end
    local v = tonumber(s, base)
    if not v then raise(B.ValueError("invalid literal for int() with base " .. base .. ": " .. repr(x))) end
    return neg and -v or v
  end
  local t = type_(x)
  if t == "number" then
    if mtype(x) == "integer" then return x end
    if x ~= x or x == math.huge or x == -math.huge then raise(B.OverflowError("cannot convert float to integer")) end
    local r = x >= 0 and floor(x) or -floor(-x)
    return math.tointeger(r) or r
  end
  if t == "boolean" then return x and 1 or 0 end
  if t == "string" then
    local s = x:gsub("_", ""):match("^%s*([+-]?%d+)%s*$")
    local v = s and math.tointeger(tonumber((s:gsub("^%+", ""))))
    if not v then raise(B.ValueError("invalid literal for int() with base 10: " .. repr(x))) end
    return v
  end
  if classOf(x) then
    local f = classLookup(getmt(x), "__int__")
    if f then return f(x) end
  end
  raise(B.TypeError("int() argument must be a string or a number, not '" .. typeName(x) .. "'"))
end, function(x) return mtype(x) == "integer" or type_(x) == "boolean" end)
valueType("float", function(_, x)
  if x == nil then return 0.0 end
  local t = type_(x)
  if t == "number" then return x + 0.0 end
  if t == "boolean" then return x and 1.0 or 0.0 end
  if t == "string" then
    local s = strM.strip(x):lower()
    if s == "inf" or s == "+inf" or s == "infinity" then return math.huge end
    if s == "-inf" or s == "-infinity" then return -math.huge end
    if s == "nan" then return 0 / 0 end
    local v = tonumber(s)
    if not v or s:find("^0x") then raise(B.ValueError("could not convert string to float: " .. repr(x))) end
    return v + 0.0
  end
  if classOf(x) then
    local f = classLookup(getmt(x), "__float__")
    if f then return f(x) end
  end
  raise(B.TypeError("float() argument must be a string or a real number, not '" .. typeName(x) .. "'"))
end, function(x) return mtype(x) == "float" end)
valueType("str", function(_, x) if x == nil then return "" end return str(x) end, function(x) return type_(x) == "string" end)
valueType("bool", function(_, x) return T(x) end, function(x) return type_(x) == "boolean" end, B.int)
valueType("NoneType", function() return None end, function(x) return x == None or x == nil end)
valueType("function", function() raise(B.TypeError("cannot create 'function' instances")) end, function(x) return type_(x) == "function" end)
local function bcopy(name, mt, ctor, methods)
  mt.__name__ = name
  mt.__bases = { object }
  mt.__ctor = ctor
  mt.__index = mt
  for k, v in pairs(methods) do mt[k] = v end
  B[name] = setmt(mt, TypeMT)
end
bcopy("list", List, function(_, x) if x == nil then return list{} end return list(toList(x)) end, listM)
bcopy("tuple", Tuple, function(_, x) if x == nil then return tuple{} end return tuple(toList(x)) end, tupleM)
bcopy("dict", Dict, function(_, x)
  local kw = R.takekw()
  local d = dict()
  if x ~= nil then
    if getmt(x) == Dict then for _, k in dkeys(x) do dset(d, k, dget(x, k)) end
    else for p in iter(x) do local kv = toList(p); dset(d, kv[1], kv[2]) end end
  end
  if kw then for k, v in pairs(kw) do dset(d, k, v) end end
  return d
end, dictM)
bcopy("set", Set, function(_, x)
  local s = newSet()
  if x ~= nil then for v in iter(x) do dset(s, v, true) end end
  return s
end, setM)
B.frozenset = B.set
B.bytes = B.str
B.bytearray = B.list
function B.type(x, ...)
  local t = type_(x)
  if t == "number" then return mtype(x) == "integer" and B.int or B.float end
  if t == "string" then return B.str end
  if t == "boolean" then return B.bool end
  if t == "nil" or x == None then return B.NoneType end
  if t == "function" then return B["function"] end
  local m = getmt(x)
  if m == TypeMT then return setmt({ __name__ = "type", __bases = {} }, TypeMT) end
  if m and rawget_(m, "__name__") then return m end
  return setmt({ __name__ = m and m.__name__ or "module", __bases = {} }, TypeMT)
end
function B.isinstance(x, c)
  if getmt(c) == Tuple then
    for i = 1, #c do if B.isinstance(x, c[i]) then return true end end
    return false
  end
  local chk = rawget_(c, "__check")
  if chk then return chk(x) end
  if c == object then return true end
  if type_(x) ~= "table" then return false end
  local m = getmt(x)
  if not m or m == TypeMT then return false end
  return isSub(m, c)
end
function B.issubclass(a, b)
  if getmt(b) == Tuple then
    for i = 1, #b do if isSub(a, b[i]) then return true end end
    return false
  end
  return isSub(a, b)
end
function B.callable(x) return type_(x) == "function" or (type_(x) == "table" and (getmt(x) == TypeMT or (classOf(x) and classLookup(getmt(x), "__call__") ~= nil))) end
local function flushLine() end
function B.print(...)
  local kw = R.takekw() or {}
  local p, n = {}, select("#", ...)
  for i = 1, n do p[i] = str((select(i, ...))) end
  local sep = opt(kw.sep) or " "
  local e = opt(kw["end"]) or "\n"
  local text = concat(p, sep) .. e
  local f = opt(kw.file)
  if f and f ~= R.stderr and f ~= R.stdout then R.CM(f, "write", text)
  else write(text) end
  return None
end
FN[B.print] = nil
function B.len(x)
  local t = type_(x)
  if t == "string" then return isAscii(x) and #x or (utf8.len(x) or #x) end
  if t == "table" then
    local m = getmt(x)
    if m == List or m == Tuple then return #x end
    if m == Dict or m == Set then return x.n end
    if classOf(x) then
      local f = classLookup(m, "__len__")
      if f then return f(x) end
    end
    if m and m.__len_ then return m.__len_(x) end
  end
  raise(B.TypeError("object of type '" .. typeName(x) .. "' has no len()"))
end
local Range = { __name__ = "range" }
Range.__index = Range
Range.__iterfn = function(r)
  local i, stop, step = r.a - r.c, r.b, r.c
  if step > 0 then
    return function()
      i = i + step
      if i < stop then return i end
    end
  end
  return function()
    i = i + step
    if i > stop then return i end
  end
end
Range.__len_ = function(r)
  local n
  if r.c > 0 then n = (r.b - r.a + r.c - 1) // r.c else n = (r.a - r.b - r.c - 1) // -r.c end
  return n > 0 and n or 0
end
Range.__repr = function(r)
  if r.c == 1 then return "range(" .. r.a .. ", " .. r.b .. ")" end
  return "range(" .. r.a .. ", " .. r.b .. ", " .. r.c .. ")"
end
-- for x in range(a, b, c): the first value, the last one and the step of a numeric for of Lua
function R.rng(a, b, c)
  if a == true or a == false then a = a and 1 or 0 end
  if b == true or b == false then b = b and 1 or 0 end
  if mtype(a) ~= "integer" or mtype(b) ~= "integer" or mtype(c) ~= "integer" then
    local bad = mtype(a) ~= "integer" and a or (mtype(b) ~= "integer" and b or c)
    raise(B.TypeError("'" .. builtins.type(bad).__name__ .. "' object cannot be interpreted as an integer"))
  end
  if c == 0 then raise(B.ValueError("range() arg 3 must not be zero")) end
  if c > 0 then return a, b - 1, c end
  return a, b + 1, c
end
function B.range(a, b, c)
  if b == nil then a, b = 0, a end
  c = c or 1
  if c == 0 then raise(B.ValueError("range() arg 3 must not be zero")) end
  if mtype(a) ~= "integer" or mtype(b) ~= "integer" or mtype(c) ~= "integer" then raise(B.TypeError("'float' object cannot be interpreted as an integer")) end
  return setmt({ a = a, b = b, c = c }, Range)
end
R.rangeGI = function(o, i)
  local n = Range.__len_(o)
  if i < 0 then i = i + n end
  if i < 0 or i >= n then raise(B.IndexError("range object index out of range")) end
  return o.a + i * o.c
end
R.Range = Range
local oldIn = R.in_
function R.in_(x, c)
  if type_(c) == "table" and getmt(c) == Range then
    if mtype(x) ~= "integer" then return false end
    if c.c > 0 then return x >= c.a and x < c.b and (x - c.a) % c.c == 0 end
    return x <= c.a and x > c.b and (c.a - x) % -c.c == 0
  end
  return oldIn(x, c)
end
function R.notin(x, c) return not R.in_(x, c) end
function B.abs(x)
  if mtype(x) then return x < 0 and -x or x end
  if x == true then return 1 elseif x == false then return 0 end
  if classOf(x) then
    local f = classLookup(getmt(x), "__abs__")
    if f then return f(x) end
  end
  raise(B.TypeError("bad operand type for abs(): '" .. typeName(x) .. "'"))
end
local function minmax(name, better)
  return function(...)
    local kw = R.takekw() or {}
    local keyf = opt(kw.key)
    local n = select("#", ...)
    local items = n == 1 and toList((...)) or { ... }
    if #items == 0 then
      if kw.default ~= nil then return kw.default end
      raise(B.ValueError(name .. "() iterable argument is empty"))
    end
    local best, bk = items[1], keyf and keyf(items[1]) or items[1]
    for i = 2, #items do
      local k = keyf and keyf(items[i]) or items[i]
      if better(k, bk) then best, bk = items[i], k end
    end
    return best
  end
end
B.max = minmax("max", function(a, b) return lt(b, a) end)
B.min = minmax("min", lt)
function B.sum(it, start)
  local kw = R.takekw()
  local s = start or (kw and kw.start) or 0
  for v in iter(it) do s = R.add(s, v) end
  return s
end
function B.sorted(it)
  local kw = R.takekw() or {}
  local l = list(toList(it))
  sortInto(l, opt(kw.key), T(kw.reverse))
  return l
end
function B.reversed(it)
  local items
  if type_(it) == "table" and classOf(it) and classLookup(getmt(it), "__reversed__") then return classLookup(getmt(it), "__reversed__")(it) end
  items = (getmt(it) == List or getmt(it) == Tuple) and it or toList(it)
  local i = #items + 1
  return function()
    i = i - 1
    return items[i]
  end
end
function B.enumerate(it, start)
  local kw = R.takekw()
  local i = (start or (kw and kw.start) or 0) - 1
  local nx = iter(it)
  return function()
    local v = nx()
    if v == nil then return nil end
    i = i + 1
    return tuple{ i, v }
  end
end
function B.zip(...)
  local its = { ... }
  local n = select("#", ...)
  for i = 1, n do its[i] = iter(its[i]) end
  return function()
    if n == 0 then return nil end
    local t = {}
    for i = 1, n do
      local v = its[i]()
      if v == nil then return nil end
      t[i] = v
    end
    return tuple(t)
  end
end
function B.map(f, ...)
  local n = select("#", ...)
  if n == 1 then
    local nx = iter((...))
    return function()
      local v = nx()
      if v == nil then return nil end
      local r = f(v)
      return r == nil and None or r
    end
  end
  local z = B.zip(...)
  return function()
    local t = z()
    if t == nil then return nil end
    local r = f(unpack(t))
    return r == nil and None or r
  end
end
function B.filter(f, it)
  local nx = iter(it)
  return function()
    while true do
      local v = nx()
      if v == nil then return nil end
      if f == None and T(v) or (f ~= None and T(f(v))) then return v end
    end
  end
end
function B.any(it) for v in iter(it) do if T(v) then return true end end return false end
function B.all(it) for v in iter(it) do if not T(v) then return false end end return true end
function B.repr(x) return repr(x) end
function B.ascii(x) return repr(x) end
function B.chr(n) return utf8.char(n) end
function B.ord(c)
  if #c == 1 then return c:byte() end
  if (utf8.len(c) or 0) ~= 1 then raise(B.TypeError("ord() expected a character, but string of length " .. B.len(c) .. " found")) end
  return utf8.codepoint(c)
end
local function based(prefix, spec)
  return function(n)
    local neg = n < 0
    return (neg and "-" or "") .. prefix .. fmtSpec(neg and -n or n, spec)
  end
end
B.hex, B.oct, B.bin = based("0x", "x"), based("0o", "o"), based("0b", "b")
function B.round(x, n)
  if n == None then n = nil end
  if mtype(x) == "integer" and (not n or n >= 0) then return x end
  if x == true then return 1 elseif x == false then return 0 end
  if classOf(x) then
    local f = classLookup(getmt(x), "__round__")
    if f then return f(x, n) end
  end
  if not n then
    local r = floor(x + 0.5)
    if r - x == 0.5 and r % 2 ~= 0 then r = r - 1 end
    return math.tointeger(r) or r
  end
  return tonumber(sfmt("%." .. math.max(n, 0) .. "f", x)) + 0.0
end
B.pow = function(a, b, m)
  if m then
    local r = 1
    a = a % m
    while b > 0 do
      if b & 1 == 1 then r = r * a % m end
      a = a * a % m
      b = b >> 1
    end
    return r
  end
  return R.pow(a, b)
end
function B.divmod(a, b) return tuple{ R.idiv(a, b), R.mod(a, b) } end
function B.id(x) return tonumber(tostring(x):match("0x(%x+)") or "0", 16) or 0 end
function B.hash(x)
  local k = keyOf(x)
  if mtype(k) == "integer" then return k end
  local s = tostring(k)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) & 0xffffffffffff end
  return h
end
function B.format(v, s) return fmtSpec(v, s or "") end
function B.getattr(o, n, d)
  if d == nil then return R.GA(o, n) end
  local ok, v = pcall(R.GA, o, n)
  if ok then return v end
  if isExc(v) and isSub(getmt(v), B.AttributeError) then return d end
  error(v, 0)
end
function B.hasattr(o, n)
  local ok, v = pcall(R.GA, o, n)
  if ok then return true end
  if isExc(v) and isSub(getmt(v), B.AttributeError) then return false end
  error(v, 0)
end
function B.setattr(o, n, v) R.SA(o, n, v); return None end
function B.delattr(o, n) R.DA(o, n); return None end
function B.iter(x)
  if type_(x) == "table" and getmt(x) == Gen then return x end
  local nx = iter(x)
  return R.gen(function() while true do local v = nx(); if v == nil then return end coroutine.yield(v) end end)
end
function B.next(it, d)
  if type_(it) == "function" then
    local v = it()
    if v == nil then
      if d ~= nil then return d end
      raise(B.StopIteration())
    end
    return v
  end
  if getmt(it) == Gen then
    local v = Gen.resume(it)
    if v == nil then
      if d ~= nil then return d end
      raise(B.StopIteration())
    end
    return v
  end
  local m = classOf(it) and classLookup(getmt(it), "__next__")
  if m then
    if d == nil then return m(it) end
    local ok, v = pcall(m, it)
    if ok then return v end
    if isExc(v) and isSub(getmt(v), B.StopIteration) then return d end
    error(v, 0)
  end
  raise(B.TypeError("'" .. typeName(it) .. "' object is not an iterator"))
end
function B.vars(o) return R.GA(o, "__dict__") end
function B.dir(o)
  local names = {}
  if type_(o) == "table" then for k in pairs(o) do if type_(k) == "string" then names[#names + 1] = k end end end
  local tm = typeMethods(o)
  if tm then for k in pairs(tm) do names[#names + 1] = k end end
  table.sort(names)
  return list(names)
end
function B.exit(c) local e = B.SystemExit(c == nil and 0 or c); error(e, 0) end
B.quit = B.exit

-- reading a line from the keyboard, with echo
local function readLine(prompt)
  if prompt and prompt ~= "" then write(prompt) end
  if R.stdinLines then
    local l = table.remove(R.stdinLines, 1)
    if l then write(l .. "\n") end
    return l
  end
  if io and io.read then return io.read("l") end
  if not key or not key.poll then return nil end
  local buf = {}
  while true do
    local k = key.poll()
    if k == "enter" or k == "\n" or k == "\r" then write("\n"); return concat(buf) end
    if k == "backspace" or k == "bs" then
      if #buf > 0 then buf[#buf] = nil; write("\b \b") end
    elseif k == "ctrl-d" then
      if #buf == 0 then return nil end
    elseif k == "ctrl-c" then raise(B.KeyboardInterrupt())
    elseif k and #k == 1 then buf[#buf + 1] = k; write(k)
    elseif k and k == "space" then buf[#buf + 1] = " "; write(" ")
    elseif k == nil then
      if sys and sys.sleep then sys.sleep(10) end
    end
  end
end
R.readLine = readLine
function B.input(p)
  local l = readLine(p and str(p) or "")
  if l == nil then raise(B.EOFError("EOF when reading a line")) end
  return l
end

-- files: the whole text is held in memory and written when the file closes
local File = newBuiltinType("TextIOWrapper")
setmt(File, TypeMT)
File.__class_mt = true
local function osErr(cls, code, msg, path)
  local e = (cls or B.OSError)("[Errno " .. tostring(code or 5) .. "] " .. tostring(msg or "error") .. (path and (": " .. repr(path)) or ""))
  rawset(e, "errno", code or 5)
  rawset(e, "strerror", msg)
  rawset(e, "filename", path)
  return e
end
R.osErr = osErr
local function checkOpen(f) if f.closed then raise(B.ValueError("I/O operation on closed file.")) end end
function File.read(f, n)
  checkOpen(f)
  if not n or n == None or n < 0 then return f.h:read("a") or "" end
  return f.h:read(n) or ""
end
function File.readline(f)
  checkOpen(f)
  return f.h:read("L") or ""
end
function File.readlines(f)
  local o = {}
  while true do
    local l = File.readline(f)
    if l == "" then return list(o) end
    o[#o + 1] = l
  end
end
function File.write(f, s)
  checkOpen(f)
  local ok, e, c = f.h:write(s)
  if not ok then raise(osErr(B.OSError, c or 9, e or "not writable")) end
  return #s
end
function File.writelines(f, it) for s in iter(it) do File.write(f, s) end return None end
function File.flush(f) if not f.closed then f.h:flush() end return None end
function File.close(f)
  if not f.closed then f.h:close(); f.closed = true end
  return None
end
function File.__enter__(f) return f end
function File.__exit__(f) File.close(f); return false end
function File.__iter__(f)
  return function()
    local l = File.readline(f)
    if l ~= "" then return l end
  end
end
File.__iterfn = File.__iter__
function File.seek(f, p, w)
  checkOpen(f)
  return f.h:seek(w == 1 and "cur" or w == 2 and "end" or "set", p)
end
function File.tell(f) checkOpen(f); return f.h:seek("cur") end
function File.fileno(f) return 3 end
function File.isatty(f) return false end
function File.readable(f) return f.mode:find("r", 1, true) ~= nil or f.mode:find("+", 1, true) ~= nil end
function File.writable(f) return not f.mode:find("^r") or f.mode:find("+", 1, true) ~= nil end
function File.truncate(f) return 0 end
function B.open(path, mode)
  local kw = R.takekw()
  mode = mode or (kw and kw.mode) or "r"
  if type_(path) == "table" and path.__fspath__ then path = path:__fspath__() end
  if type_(path) ~= "string" then path = B.str(path) end
  local m = mode:gsub("[tbU]", "")
  if m:find("x", 1, true) then
    local x = io.open(path, "r")
    if x then x:close(); raise(osErr(B.FileExistsError, 17, "File exists", path)) end
    m = m:gsub("x", "w")
  end
  local h, e, c = io.open(path, m)
  if not h then
    local cls = c == 2 and B.FileNotFoundError or c == 13 and B.PermissionError or c == 21 and B.IsADirectoryError or B.OSError
    local text = tostring(e):gsub("^.*: ", "")
    raise(osErr(cls, c or 5, text, path))
  end
  return setmt({ h = h, name = path, mode = mode, closed = false }, File)
end
R.File = File

-- ---------------------------------------------------------------- modules
local modules = {}
local function module(name, t) t.__name__ = name; modules[name] = t; return t end
local function lazy(name, f) modules[name] = f end

lazy("math", function()
  local m = module("math", { pi = math.pi, e = math.exp(1), tau = 2 * math.pi, inf = math.huge, nan = 0 / 0 })
  local function nums(f) return function(...) return f(...) end end
  m.sqrt = function(x)
    if x < 0 then raise(B.ValueError("math domain error")) end
    return math.sqrt(x)
  end
  m.sin, m.cos, m.tan, m.asin, m.acos, m.exp = math.sin, math.cos, math.tan, math.asin, math.acos, math.exp
  m.atan = function(y) return math.atan(y) end
  m.atan2 = function(y, x) return math.atan(y, x) end
  m.floor = function(x) if mtype(x) == "integer" then return x end return math.tointeger(floor(x)) or floor(x) end
  m.ceil = function(x) if mtype(x) == "integer" then return x end return math.tointeger(math.ceil(x)) or math.ceil(x) end
  m.trunc = function(x) if mtype(x) == "integer" then return x end local r = x >= 0 and floor(x) or -floor(-x); return math.tointeger(r) or r end
  m.fabs = function(x) return math.abs(x) + 0.0 end
  m.pow = function(a, b) return (a + 0.0) ^ b end
  m.log = function(x, b)
    if x <= 0 then raise(B.ValueError("math domain error")) end
    if b then return math.log(x, b) end
    return math.log(x)
  end
  m.log2 = function(x) return math.log(x, 2) end
  m.log10 = function(x) return math.log(x, 10) end
  m.degrees = function(x) return x * 180 / math.pi end
  m.radians = function(x) return x * math.pi / 180 end
  m.hypot = function(a, b) return math.sqrt(a * a + b * b) end
  m.fmod = function(a, b) return math.fmod(a + 0.0, b) end
  m.isnan = function(x) return x ~= x end
  m.isinf = function(x) return x == math.huge or x == -math.huge end
  m.isfinite = function(x) return x == x and x ~= math.huge and x ~= -math.huge end
  m.factorial = function(n)
    if n < 0 then raise(B.ValueError("factorial() not defined for negative values")) end
    local r = 1
    for i = 2, n do r = R.mul(r, i) end
    return r
  end
  m.gcd = function(a, b) a, b = math.abs(a), math.abs(b); while b ~= 0 do a, b = b, a % b end return a end
  m.lcm = function(a, b) if a == 0 or b == 0 then return 0 end return math.abs(a * b) // m.gcd(a, b) end
  m.isqrt = function(n) local r = floor(math.sqrt(n)); r = math.tointeger(r); while r * r > n do r = r - 1 end while (r + 1) * (r + 1) <= n do r = r + 1 end return r end
  m.comb = function(n, k) if k > n then return 0 end local r = 1; for i = 1, math.min(k, n - k) do r = r * (n - i + 1) // i end return r end
  m.perm = function(n, k) local r = 1; for i = 0, (k or n) - 1 do r = r * (n - i) end return r end
  m.copysign = function(a, b) a = math.abs(a) + 0.0; if b < 0 or (b == 0 and 1 / b < 0) then return -a end return a end
  m.sinh = function(x) return (math.exp(x) - math.exp(-x)) / 2 end
  m.cosh = function(x) return (math.exp(x) + math.exp(-x)) / 2 end
  m.tanh = function(x) return m.sinh(x) / m.cosh(x) end
  m.prod = function(it) local r = 1; for v in iter(it) do r = R.mul(r, v) end return r end
  m.fsum = function(it) local r = 0.0; for v in iter(it) do r = r + v end return r end
  return m
end)
lazy("random", function()
  local m = module("random", {})
  m.seed = function(s) math.randomseed(s == nil and os_time and os_time() or (mtype(s) == "integer" and s or B.hash(s))); return None end
  m.random = function() return math.random() end
  m.randint = function(a, b) return math.random(a, b) end
  m.randrange = function(a, b, c)
    if not b then return math.random(0, a - 1) end
    c = c or 1
    return a + c * math.random(0, (b - a - 1) // c)
  end
  m.uniform = function(a, b) return a + (b - a) * math.random() end
  m.choice = function(s)
    local items = type_(s) == "string" and toList(s) or s
    if #items == 0 then raise(B.IndexError("Cannot choose from an empty sequence")) end
    return items[math.random(#items)]
  end
  m.shuffle = function(l)
    for i = #l, 2, -1 do
      local j = math.random(i)
      l[i], l[j] = l[j], l[i]
    end
    return None
  end
  m.sample = function(s, k)
    local c = toList(s)
    local out = {}
    for i = 1, k do
      local j = math.random(i, #c)
      c[i], c[j] = c[j], c[i]
      out[i] = c[i]
    end
    return list(out)
  end
  m.choices = function(s, _, k)
    local kw = R.takekw()
    k = (kw and kw.k) or k or 1
    local out = {}
    for i = 1, k do out[i] = s[math.random(#s)] end
    return list(out)
  end
  m.gauss = function(mu, sigma)
    return mu + sigma * math.sqrt(-2 * math.log(1 - math.random())) * math.cos(2 * math.pi * math.random())
  end
  return m
end)
lazy("time", function()
  local m = module("time", {})
  local function now() if sys and sys.time then local t = sys.time(); if t then return t end end return (sys and sys.millis and sys.millis() or 0) / 1000 end
  m.time = function() return now() + 0.0 end
  m.monotonic_ns = function() return (sys and sys.millis and sys.millis() or 0) * 1000000 end
  m.sleep = function(s) if sys and sys.sleep then sys.sleep(math.floor(s * 1000)) end return None end
  m.monotonic = function() return (sys and sys.millis and sys.millis() or 0) / 1000 end
  m.perf_counter = m.monotonic
  m.time_ns = function() return math.floor(now() * 1000000000) end
  local function tmToTime(t) return os.time{ year = t[1], month = t[2], day = t[3], hour = t[4], min = t[5], sec = t[6] } end
  local function structTime(secs, utc)
    local d = os.date(utc and "!*t" or "*t", math.floor(secs))
    local v = tuple{ d.year, d.month, d.day, d.hour, d.min, d.sec, (d.wday + 5) % 7, d.yday, d.isdst and 1 or 0 }
    return v
  end
  m.localtime = function(s) return structTime(s == nil and now() or s, false) end
  m.gmtime = function(s) return structTime(s == nil and now() or s, true) end
  m.mktime = function(t) return tmToTime(t) + 0.0 end
  m.strftime = function(f, t) return os.date(f, t and t ~= None and tmToTime(t) or nil) end
  m.ctime = function(s) return os.date("%a %b %e %H:%M:%S %Y", math.floor(s == nil and now() or s)) end
  m.asctime = function(t) return os.date("%a %b %e %H:%M:%S %Y", t and tmToTime(t) or nil) end
  m.process_time = function() return os.clock() end
  m.timezone, m.altzone, m.daylight, m.tzname = 0, 0, 0, tuple{ "UTC", "UTC" }
  return m
end)
lazy("sys", function()
  local m = module("sys", { argv = list{}, maxsize = math.maxinteger, platform = "linux", byteorder = "little", executable = "/usr/local/bin/python3", prefix = "/usr/local", version = "3.12.0 (ESP Linux, translated to Lua)", path = list{ "." }, modules = dict() })
  m.exit = B.exit
  m.stdout = setmt({ write = function(s) write(s); return #s end, flush = function() return None end, isatty = function() return true end, fileno = function() return 1 end, encoding = "utf-8" }, { __module = true })
  m.stderr = setmt({ write = function(s) if io and io.stderr then io.stderr:write(s) else write(s) end return #s end, flush = function() return None end, isatty = function() return true end, fileno = function() return 2 end, encoding = "utf-8" }, { __module = true })
  m.stdin = setmt({ readline = function() local l = readLine(""); return l and (l .. "\n") or "" end, read = function() local o = {}; while true do local l = readLine(""); if not l then break end o[#o + 1] = l .. "\n" end return concat(o) end }, { __module = true })
  R.stdout, R.stderr = m.stdout, m.stderr
  m.getrecursionlimit = function() return 200 end
  m.setrecursionlimit = function() return None end
  m.version_info = tuple{ 3, 12, 0 }
  m.argv = R.argv or list{}
  return m
end)
lazy("os", function()
  local m = module("os", { sep = "/", linesep = "\n", name = "posix", curdir = ".", pardir = ".." })
  m.environ = dict()
  m.devnull = "/dev/null"
  m.extsep, m.pathsep = ".", ":"
  m.O_RDONLY, m.O_WRONLY, m.O_RDWR, m.O_CREAT, m.R_OK, m.W_OK, m.X_OK, m.F_OK = 0, 1, 2, 64, 4, 2, 1, 0
  do
    local env = sys and sys.env and sys.env()
    if env then for k, v in pairs(env) do if not k:find("[", 1, true) then dset(m.environ, k, v) end end
    else
      dset(m.environ, "HOME", os.getenv("HOME") or "/home/user")
      dset(m.environ, "USER", os.getenv("USER") or "user")
      dset(m.environ, "PATH", os.getenv("PATH") or "/usr/bin")
    end
  end
  m.getenv = function(k, d) local v = dget(m.environ, k); if v ~= nil then return v end return d == nil and None or d end
  m.putenv = function(k, v) if os.setenv then os.setenv(k, v) end dset(m.environ, k, v); return None end
  local function fsPath(p)
    if type_(p) == "table" and p.__fspath__ then return p:__fspath__() end
    return p
  end
  m.fspath = fsPath
  local function fail(e, p, c)
    local t = tostring(e):gsub("^.*: ", "")
    c = c or (t:find("No such") and 2) or (t:find("exists") and 17) or (t:find("denied") and 13) or (t:find("Not a dir") and 20) or (t:find("Is a dir") and 21) or (t:find("not empty") and 39) or 5
    local cls = c == 2 and B.FileNotFoundError or c == 13 and B.PermissionError or c == 17 and B.FileExistsError or c == 20 and B.NotADirectoryError or c == 21 and B.IsADirectoryError or B.OSError
    raise(R.osErr(cls, c, t, p))
  end
  m.listdir = function(p)
    p = fsPath(p == nil and "." or p)
    if not lfs.attributes(p) then fail("No such file or directory", p, 2) end
    local o = {}
    for n in lfs.dir(p) do if n ~= "." and n ~= ".." then o[#o + 1] = n end end
    return list(o)
  end
  m.remove = function(p) p = fsPath(p); local ok, e, c = os.remove(p); if not ok then fail(e, p, c) end return None end
  m.unlink = m.remove
  m.system = function(c) local ok, _, code = os.execute(c); if ok == true and code == nil then return 0 end return code or 0 end
  m.getcwd = function() return lfs.currentdir() end
  m.chdir = function(p) p = fsPath(p); local ok, e = lfs.chdir(p); if not ok then fail(e, p) end return None end
  m.mkdir = function(p) p = fsPath(p); if lfs.attributes(p) then fail("File exists", p, 17) end local ok, e = lfs.mkdir(p); if not ok then fail(e, p) end return None end
  m.makedirs = function(p, _, exist)
    local kw = R.takekw()
    local okExist = exist or (kw and kw.exist_ok)
    p = fsPath(p)
    if lfs.attributes(p) then
      if okExist then return None end
      fail("File exists", p, 17)
    end
    local at = p:sub(1, 1) == "/" and "" or nil
    for part in p:gmatch("[^/]+") do
      at = at and (at .. "/" .. part) or part
      if not lfs.attributes(at) then
        local ok, e = lfs.mkdir(at)
        if not ok then fail(e, at) end
      end
    end
    return None
  end
  m.rmdir = function(p) p = fsPath(p); local ok, e = lfs.rmdir(p); if not ok then fail(e, p) end return None end
  m.rename = function(a, b) a, b = fsPath(a), fsPath(b); local ok, e, c = os.rename(a, b); if not ok then fail(e, a, c) end return None end
  m.replace = m.rename
  m.getpid = function() return 1 end
  m.getppid = m.getpid
  m.getuid = function() return 1000 end
  m.geteuid, m.getgid, m.getegid = m.getuid, m.getuid, m.getuid
  m.getlogin = function() return sys and sys.user and sys.user() or "user" end
  m.urandom = function(n) local o = {}; for k = 1, n do o[k] = string.char(math.random(0, 255)) end return table.concat(o) end
  m.isatty = function() return true end
  m.chmod = function() return None end
  m.chown = function() return None end
  m.utime = function() return None end
  m.umask = function() return 18 end
  m.kill = function() return None end
  m.nice = function() return 0 end
  m.sync = function() return None end
  m.cpu_count = function() return 2 end
  m.access = function(p) return lfs.attributes(fsPath(p)) ~= nil end
  m.popen = function(c) local h = io.popen(c, "r"); return setmt({ h = h, name = c, mode = "r", closed = false }, R.File) end
  m.uname = function()
    return setmt({ sysname = "Linux", nodename = sys and sys.hostname and sys.hostname() or "esp", release = "6.8.0-esp", version = "#1 SMP", machine = "riscv32" }, { __module = true })
  end
  m.get_terminal_size = function()
    local w, h = 80, 24
    if term and term.size then w, h = term.size() end
    return setmt({ columns = w, lines = h, [0] = w, [1] = h }, { __module = true })
  end
  m.terminal_size = m.get_terminal_size
  local StatResult = {}
  local function statOf(p)
    p = fsPath(p)
    local a = lfs.attributes(p)
    if not a then fail("No such file or directory", p, 2) end
    return setmt({ st_size = a.size or 0, st_mode = a.mode == "directory" and 16877 or 33188, st_mtime = (a.modification or 0) + 0.0, st_atime = (a.modification or 0) + 0.0, st_ctime = (a.modification or 0) + 0.0, st_uid = 1000, st_gid = 1000, st_nlink = 1, st_ino = 0, st_dev = 0 }, { __module = true })
  end
  m.stat = statOf
  m.lstat = statOf
  m.walk = function(top)
    top = fsPath(top)
    local out = {}
    local function visit(d)
      local dirs, files = {}, {}
      local names = {}
      for n in lfs.dir(d) do if n ~= "." and n ~= ".." then names[#names + 1] = n end end
      table.sort(names)
      for _, n in ipairs(names) do
        local a = lfs.attributes(d .. "/" .. n)
        if a and a.mode == "directory" then dirs[#dirs + 1] = n else files[#files + 1] = n end
      end
      out[#out + 1] = tuple{ d, list(dirs), list(files) }
      for _, n in ipairs(dirs) do visit(d .. "/" .. n) end
    end
    if lfs.attributes(top) then visit(top) end
    return list(out)
  end
  m.scandir = function(p)
    p = fsPath(p == nil and "." or p)
    local o = {}
    for n in lfs.dir(p) do
      if n ~= "." and n ~= ".." then
        local full = p .. "/" .. n
        o[#o + 1] = setmt({ name = n, path = full, is_dir = function() return (lfs.attributes(full) or {}).mode == "directory" end, is_file = function() return (lfs.attributes(full) or {}).mode == "file" end, is_symlink = function() return false end, stat = function() return statOf(full) end }, { __module = true })
      end
    end
    return setmt({ __iterfn = nil }, { __index = function(_, k) if k == "__enter__" then return function(x) return x end end if k == "__exit__" then return function() return false end end end, __call = nil }) and list(o)
  end
  m.path = setmt({
    exists = function(p) return lfs.attributes(fsPath(p)) ~= nil end,
    lexists = function(p) return lfs.attributes(fsPath(p)) ~= nil end,
    join = function(...)
      local out = ""
      for _, p in ipairs{ ... } do
        p = fsPath(p)
        if p:sub(1, 1) == "/" or out == "" then out = p
        elseif out:sub(-1) == "/" then out = out .. p
        else out = out .. "/" .. p end
      end
      return out
    end,
    basename = function(p) p = fsPath(p); return p:match("([^/]*)$") end,
    dirname = function(p) p = fsPath(p); local d = p:match("^(.*)/[^/]*$"); if d == "" then return "/" end return d or "" end,
    splitext = function(p)
      p = fsPath(p)
      local a, b = p:match("^(.*[^/])(%.[^./]*)$")
      if a then return tuple{ a, b } end
      return tuple{ p, "" }
    end,
    split = function(p) p = fsPath(p); local d = p:match("^(.*)/[^/]*$"); if d == "" then d = "/" end return tuple{ d or "", p:match("([^/]*)$") } end,
    isfile = function(p) local a = lfs.attributes(fsPath(p)); return a ~= nil and a.mode == "file" end,
    isdir = function(p) local a = lfs.attributes(fsPath(p)); return a ~= nil and a.mode == "directory" end,
    islink = function() return false end,
    ismount = function(p) return fsPath(p) == "/" end,
    isabs = function(p) return fsPath(p):sub(1, 1) == "/" end,
    getsize = function(p) p = fsPath(p); local a = lfs.attributes(p); if not a then fail("No such file or directory", p, 2) end return a.size or 0 end,
    getmtime = function(p) p = fsPath(p); local a = lfs.attributes(p); if not a then fail("No such file or directory", p, 2) end return (a.modification or 0) + 0.0 end,
    normpath = function(p)
      p = fsPath(p)
      local abs = p:sub(1, 1) == "/"
      local o = {}
      for part in p:gmatch("[^/]+") do
        if part == ".." and #o > 0 and o[#o] ~= ".." then o[#o] = nil
        elseif part == ".." and abs then
        elseif part ~= "." then o[#o + 1] = part end
      end
      local t = table.concat(o, "/")
      if abs then return "/" .. t end
      return t == "" and "." or t
    end,
    expanduser = function(p)
      p = fsPath(p)
      if p:sub(1, 1) == "~" then return (dget(m.environ, "HOME") or "/home/user") .. p:sub(2) end
      return p
    end,
    expandvars = function(p)
      return (fsPath(p):gsub("%${?([%w_]+)}?", function(k) return dget(m.environ, k) or nil end))
    end,
    commonprefix = function(l)
      local items = {}
      for x in iter(l) do items[#items + 1] = x end
      if #items == 0 then return "" end
      local s0 = items[1]
      local n = #s0
      for _, x in ipairs(items) do
        local k = 0
        while k < n and k < #x and x:byte(k + 1) == s0:byte(k + 1) do k = k + 1 end
        n = k
      end
      return s0:sub(1, n)
    end,
    sep = "/",
    curdir = ".",
    pardir = "..",
  }, { __module = true })
  m.path.abspath = function(p)
    p = fsPath(p)
    if p:sub(1, 1) ~= "/" then p = lfs.currentdir() .. "/" .. p end
    return m.path.normpath(p)
  end
  m.path.realpath = m.path.abspath
  m.path.relpath = function(p, start)
    p, start = m.path.abspath(p), m.path.abspath(start == nil and "." or start)
    if p == start then return "." end
    if p:sub(1, #start + 1) == start .. "/" then return p:sub(#start + 2) end
    return p
  end
  modules["os.path"] = m.path
  return m
end)
lazy("string", function()
  return module("string", {
    ascii_lowercase = "abcdefghijklmnopqrstuvwxyz", ascii_uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    ascii_letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", digits = "0123456789", hexdigits = "0123456789abcdefABCDEF",
    punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~", whitespace = " \t\n\r\v\f",
  })
end)
lazy("json", function()
  local m = module("json", {})
  local function enc(v, ind, cur)
    local t = type_(v)
    if v == None or v == nil then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then return repr(v) end
    if t == "string" then
      return '"' .. v:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" elseif c == "\t" then return "\\t" elseif c == "\r" then return "\\r" end
        return sfmt("\\u%04x", c:byte())
      end) .. '"'
    end
    local mt_ = getmt(v)
    local nl, inner = "", ""
    if ind then nl = "\n" .. (" "):rep(cur); inner = "\n" .. (" "):rep(cur + ind) end
    if mt_ == List or mt_ == Tuple then
      if #v == 0 then return "[]" end
      local p = {}
      for i = 1, #v do p[i] = enc(v[i], ind, cur + (ind or 0)) end
      return "[" .. inner .. concat(p, ind and ("," .. inner) or (R.jsonItem or ", ")) .. nl .. "]"
    end
    if mt_ == Dict then
      if v.n == 0 then return "{}" end
      local p = {}
      for _, k in dkeys(v) do p[#p + 1] = enc(str(k), nil, 0) .. (R.jsonKey or ": ") .. enc(dget(v, k), ind, cur + (ind or 0)) end
      return "{" .. inner .. concat(p, ind and ("," .. inner) or (R.jsonItem or ", ")) .. nl .. "}"
    end
    raise(B.TypeError("Object of type " .. typeName(v) .. " is not JSON serializable"))
  end
  m.dumps = function(v)
    local kw = R.takekw() or {}
    R.jsonItem, R.jsonKey = nil, nil
    if kw.separators and kw.separators ~= None then R.jsonItem, R.jsonKey = kw.separators[1], kw.separators[2] end
    return enc(v, opt(kw.indent), 0)
  end
  local function dec(s)
    local i = 1
    local function ws() i = s:find("%S", i) or #s + 1 end
    local val
    local function fail() raise(B.ValueError("Expecting value: char " .. (i - 1))) end
    val = function()
      ws()
      local c = s:sub(i, i)
      if c == "{" then
        i = i + 1
        local d = dict()
        ws()
        if s:sub(i, i) == "}" then i = i + 1; return d end
        while true do
          local k = val()
          ws()
          if s:sub(i, i) ~= ":" then fail() end
          i = i + 1
          dset(d, k, val())
          ws()
          local e = s:sub(i, i)
          i = i + 1
          if e == "}" then return d end
          if e ~= "," then fail() end
        end
      elseif c == "[" then
        i = i + 1
        local l = {}
        ws()
        if s:sub(i, i) == "]" then i = i + 1; return list(l) end
        while true do
          l[#l + 1] = val()
          ws()
          local e = s:sub(i, i)
          i = i + 1
          if e == "]" then return list(l) end
          if e ~= "," then fail() end
        end
      elseif c == '"' then
        local j = i + 1
        local b = {}
        while true do
          local x = s:sub(j, j)
          if x == "" then fail() end
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
      elseif s:sub(i, i + 3) == "null" then i = i + 4; return None
      end
      local n = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
      if not n then fail() end
      i = i + #n
      return tonumber(n)
    end
    return val()
  end
  m.loads = dec
  m.JSONDecodeError = B.ValueError
  m.dump = function(v, f)
    local kw = R.takekw() or {}
    R.CM(f, "write", enc(v, opt(kw.indent), 0))
    return None
  end
  m.load = function(f) return dec(R.CM(f, "read")) end
  return m
end)
lazy("collections", function()
  local m = module("collections", {})
  m.OrderedDict = B.dict
  m.defaultdict = function(f, x)
    local d = dict()
    d.__missing = f
    if x then dictM.update(d, x) end
    return d
  end
  m.Counter = function(it)
    local d = dict()
    if it ~= nil then for v in iter(it) do dset(d, v, (dget(d, v) or 0) + 1) end end
    d.__missing = function() return 0 end
    return d
  end
  dictM.most_common = function(d, n)
    local l = dictM.items(d)
    sortInto(l, function(p) return p[2] end, true)
    if n and n ~= None then for i = #l, n + 1, -1 do l[i] = nil end end
    return l
  end
  dictM.elements = function(d)
    local o = {}
    for _, k in dkeys(d) do for _ = 1, dget(d, k) do o[#o + 1] = k end end
    return list(o)
  end
  m.deque = function(it, n)
    local kw = R.takekw()
    local l = list(it and toList(it) or {})
    local maxlen = n or (kw and opt(kw.maxlen))
    if maxlen then l.__maxlen = nil end
    return l
  end
  listM.appendleft = function(l, x) table.insert(l, 1, x); return None end
  listM.popleft = function(l)
    if #l == 0 then raise(B.IndexError("pop from an empty deque")) end
    return table.remove(l, 1)
  end
  listM.extendleft = function(l, it) for v in iter(it) do table.insert(l, 1, v) end return None end
  listM.rotate = function(l, n)
    n = n or 1
    for _ = 1, math.abs(n) do
      if n > 0 then table.insert(l, 1, table.remove(l)) else l[#l + 1] = table.remove(l, 1) end
    end
    return None
  end
  m.namedtuple = function(name, fields)
    local names = type_(fields) == "string" and toList(strM.split((fields:gsub(",", " ")))) or toList(fields)
    return R.class(name, {}, function(c)
      c.__init__ = function(self, ...)
        local kw = R.takekw()
        local a = { ... }
        for i, f in ipairs(names) do
          local v = a[i]
          if v == nil and kw then v = kw[f] end
          rawset(self, f, v)
        end
      end
      c.__repr__ = function(self)
        local p = {}
        for i, f in ipairs(names) do p[i] = f .. "=" .. repr(rawget_(self, f)) end
        return name .. "(" .. concat(p, ", ") .. ")"
      end
      c.__iter__ = function(self)
        local o = {}
        for i, f in ipairs(names) do o[i] = rawget_(self, f) end
        return list(o)
      end
      c.__getitem__ = function(self, i) return rawget_(self, names[i + 1]) end
      c.__eq__ = function(self, o)
        for _, f in ipairs(names) do if not eq(rawget_(self, f), R.GA(o, f)) then return false end end
        return true
      end
      c.__len__ = function() return #names end
      c._fields = tuple(names)
    end)
  end
  return m
end)
lazy("itertools", function()
  local m = module("itertools", {})
  m.count = function(a, s)
    a = (a or 0)
    s = s or 1
    local i = a - s
    return function()
      i = i + s
      return i
    end
  end
  m.chain = function(...)
    local its = { ... }
    local k, cur = 0, nil
    return function()
      while true do
        if cur then
          local v = cur()
          if v ~= nil then return v end
        end
        k = k + 1
        if not its[k] then return nil end
        cur = iter(its[k])
      end
    end
  end
  m.repeat_ = function(x, n)
    local i = 0
    return function()
      i = i + 1
      if not n or i <= n then return x end
    end
  end
  m["repeat"] = m.repeat_
  m.cycle = function(it)
    local items, i = toList(it), 0
    return function()
      if #items == 0 then return nil end
      i = i % #items + 1
      return items[i]
    end
  end
  m.islice = function(it, a, b, c)
    if b == nil then a, b = 0, a end
    if b == None then b = nil end
    local nx, i = iter(it), -1
    c = c or 1
    local want = a
    return function()
      while true do
        if b and want >= b then return nil end
        local v = nx()
        if v == nil then return nil end
        i = i + 1
        if i == want then
          want = want + c
          return v
        end
      end
    end
  end
  m.takewhile = function(f, it)
    local nx, done = iter(it), false
    return function()
      if done then return nil end
      local v = nx()
      if v == nil or not T(f(v)) then done = true; return nil end
      return v
    end
  end
  m.dropwhile = function(f, it)
    local nx, go = iter(it), false
    return function()
      while true do
        local v = nx()
        if v == nil then return nil end
        if go or not T(f(v)) then go = true; return v end
      end
    end
  end
  m.accumulate = function(it, f)
    local nx, acc = iter(it), nil
    return function()
      local v = nx()
      if v == nil then return nil end
      if acc == nil then acc = v elseif f then acc = f(acc, v) else acc = R.add(acc, v) end
      return acc
    end
  end
  m.product = function(...)
    local kw = R.takekw()
    local pools = {}
    for i, it in ipairs{ ... } do pools[i] = toList(it) end
    local rep = kw and kw["repeat"] or 1
    local all = {}
    for _ = 1, rep do for _, p in ipairs(pools) do all[#all + 1] = p end end
    local out = { {} }
    for _, p in ipairs(all) do
      local nextOut = {}
      for _, pre in ipairs(out) do
        for _, v in ipairs(p) do
          local c = { unpack(pre) }
          c[#c + 1] = v
          nextOut[#nextOut + 1] = c
        end
      end
      out = nextOut
    end
    for i = 1, #out do out[i] = tuple(out[i]) end
    return list(out)
  end
  m.permutations = function(it, r)
    local items = toList(it)
    r = r or #items
    local out, used, cur = {}, {}, {}
    local function go(d)
      if d > r then out[#out + 1] = tuple{ unpack(cur) }; return end
      for i = 1, #items do
        if not used[i] then
          used[i] = true
          cur[d] = items[i]
          go(d + 1)
          used[i] = false
        end
      end
    end
    go(1)
    return list(out)
  end
  m.combinations = function(it, r)
    local items = toList(it)
    local out, cur = {}, {}
    local function go(start, d)
      if d > r then out[#out + 1] = tuple{ unpack(cur) }; return end
      for i = start, #items do
        cur[d] = items[i]
        go(i + 1, d + 1)
      end
    end
    go(1, 1)
    return list(out)
  end
  m.groupby = function(it, f)
    local items = toList(it)
    local out = {}
    local i = 1
    while i <= #items do
      local k = f and f(items[i]) or items[i]
      local g = {}
      while i <= #items and eq(f and f(items[i]) or items[i], k) do g[#g + 1] = items[i]; i = i + 1 end
      out[#out + 1] = tuple{ k, list(g) }
    end
    return list(out)
  end
  return m
end)
lazy("functools", function()
  local m = module("functools", {})
  m.reduce = function(f, it, init)
    local acc = init
    for v in iter(it) do
      if acc == nil then acc = v else acc = f(acc, v) end
    end
    if acc == nil then raise(B.TypeError("reduce() of empty iterable with no initial value")) end
    return acc
  end
  m.partial = function(f, ...)
    local a = { ... }
    local na = select("#", ...)
    local kw0 = R.takekw()
    return function(...)
      local args = { unpack(a, 1, na) }
      local n = select("#", ...)
      for i = 1, n do args[na + i] = (select(i, ...)) end
      args.n = na + n
      return callKw(f, args, kw0)
    end
  end
  m.wraps = function() return function(f) return f end end
  local function memo(f)
    local cache = {}
    return function(...)
      local k = tupleKey({ ... })
      local v = cache[k]
      if v == nil then v = f(...); cache[k] = v end
      return v
    end
  end
  m.lru_cache = function(a)
    if type_(a) == "function" then return memo(a) end
    R.takekw()
    return memo
  end
  m.cache = memo
  m.cmp_to_key = function(f)
    local K = R.class("K", {}, function(c)
      c.__init__ = function(self, x) rawset(self, "x", x) end
      c.__lt__ = function(self, o) return f(rawget_(self, "x"), rawget_(o, "x")) < 0 end
    end)
    return K
  end
  return m
end)
lazy("re", function() return R.makeRe(module, modules) end)
lazy("copy", function()
  local m = module("copy", {})
  local function deep(v)
    if type_(v) ~= "table" then return v end
    local mt_ = getmt(v)
    if mt_ == List or mt_ == Tuple then local o = {}; for i = 1, #v do o[i] = deep(v[i]) end return setmt(o, mt_) end
    if mt_ == Dict or mt_ == Set then
      local d = setmt({ idx = {}, ks = {}, vs = {}, top = 0, n = 0 }, mt_)
      for _, k in dkeys(v) do dset(d, deep(k), deep(dget(v, k))) end
      return d
    end
    if mt_ and rawget_(mt_, "__class_mt") then
      local o = setmt({}, mt_)
      for k, x in pairs(v) do rawset(o, k, deep(x)) end
      return o
    end
    return v
  end
  m.deepcopy = deep
  m.copy = function(v)
    if type_(v) ~= "table" then return v end
    local mt_ = getmt(v)
    if mt_ == List then return listM.copy(v) end
    if mt_ == Dict then return dictM.copy(v) end
    if mt_ == Set then return setM.copy(v) end
    if mt_ and rawget_(mt_, "__class_mt") then
      local o = setmt({}, mt_)
      for k, x in pairs(v) do rawset(o, k, x) end
      return o
    end
    return v
  end
  return m
end)
lazy("typing", function()
  return module("typing", setmt({}, { __index = function() return object end }))
end)
lazy("abc", function()
  return module("abc", { ABC = object, ABCMeta = B.type, abstractmethod = function(f) return f end, abstractproperty = B.property, abstractclassmethod = B.classmethod, abstractstaticmethod = B.staticmethod })
end)
lazy("enum", function()
  local m = module("enum", {})
  m.Enum = R.class("Enum", {}, function() end)
  m.auto = function() return 0 end
  return m
end)
lazy("dataclasses", function()
  local m = module("dataclasses", {})
  m.dataclass = function(c)
    return c
  end
  m.field = function() return None end
  return m
end)
-- the modules of the device itself are given as they are
for _, n in ipairs{ "gfx", "term", "key", "touch", "net", "fs", "gpio", "audio", "uart", "spi", "i2c", "search", "video", "llm" } do
  lazy(n, function() return _G[n] end)
end
lazy("esp", function() return _G.sys end)
lazy("_lua", function()
  -- from Python, to the libraries of Lua: several results come back as a tuple
  local function ok(v, ...) if v == nil or v == false then return tuple{ false, ... } end return tuple{ true, v, ... } end
  rawset(_G, "__pysock", function(what, a, b, c, d)
    if what == "new" then return b == nil and (a == "udp" and socket.udp() or socket.tcp()) end
    if what == "toip" then return ok(socket.dns.toip(a)) end
    if what == "timeout" then if b == None then b = nil end a:settimeout(b); return None end
    if what == "option" then a:setoption(b, c); return None end
    if what == "connect" then return ok(a:connect(b, c)) end
    if what == "bind" then return ok(a:bind(b, c)) end
    if what == "listen" then a:listen(b); return None end
    if what == "accept" then return ok(a:accept()) end
    if what == "send" then return ok(a:send(b)) end
    if what == "sendto" then return ok(a:sendto(b, c, d)) end
    if what == "recv" then
      local got, e, part = a:receive(1)
      if not got then return ok(nil, e) end
      a:settimeout(0)
      local more, _, p2 = a:receive(math.max(b - 1, 0))
      local rest = more or p2 or ""
      return ok(got .. rest)
    end
    if what == "recvfrom" then return ok(a:receivefrom()) end
    if what == "name" then return ok(a:getsockname()) end
    if what == "peer" then return ok(a:getpeername()) end
    if what == "shutdown" then a:shutdown(); return None end
    if what == "close" then a:close(); return None end
  end)
  rawset(_G, "__pyhttp", function(url, method, headers, body)
    local h = {}
    if headers and headers ~= None then
      for k in R.iter(headers) do h[#h + 1] = tostring(k) .. ": " .. tostring(dget(headers, k)) end
    end
    if body == None then body = nil end
    if method == None then method = nil end
    local st, data = net.request{ url = url, method = method, headers = h, body = body, maxBytes = 1048576 }
    if st == nil then return tuple{ None, data } end
    return tuple{ st, data }
  end)
  return setmt({}, { __module = true, __index = function(_, k)
    local v = _G[k]
    if v == nil then return None end
    return v
  end })
end)
lazy("wifi", function() return _G.wifi end)
lazy("ble", function() return _G.ble end)

local importOne
function R.import(name)
  local m = importOne(name)
  -- import a.b: b is also a name in a
  local parent, last = name:match("^(.*)%.([^.]+)$")
  if parent then
    local pm = R.import(parent)
    if type_(pm) == "table" and rawget(pm, last) == nil then rawset(pm, last, m) end
  end
  return m
end
importOne = function(name)
  local m = modules[name]
  if type_(m) == "function" then
    m = m()
    if name ~= "os.path" then modules[name] = m end
  end
  if m then return m end
  -- a module of a converted program
  local packed = R.bundled and R.bundled[name]
  if packed then
    local env = R.newEnv(name)
    modules[name] = env
    local f, e = load(R.header() .. packed, "=" .. name, "t")
    if not f then error({ syntax = "internal: " .. tostring(e), line = 0 }, 0) end
    f(R, env)
    return env
  end
  -- the library of Python written in Python (the driver pylib)
  if driver and not R.pylib then
    local ok, lib = pcall(driver.load, "pylib")
    R.pylib = ok and lib or {}
  end
  if R.pylib and R.pylib[name] and R.compileText then
    local env = R.newEnv(name)
    modules[name] = env
    if not R.compiler then R.compiler = driver.load("pylang").compile end
    R.runSource(R.pylib[name], name, env)
    return env
  end
  -- a .py file next to the program
  for _, dir in ipairs{ R.scriptDir or ".", "/usr/local/lib/python" } do
    local path = dir .. "/" .. name:gsub("%.", "/") .. ".py"
    local src = fs and fs.read and fs.read(path)
    if src then
      local env = R.newEnv(name)
      modules[name] = env
      R.runSource(src, path, env)
      return env
    end
  end
  raise(B.ModuleNotFoundError("No module named '" .. name .. "'"))
end
function R.importall(m, env)
  for k, v in pairs(m) do
    if type_(k) == "string" and k:sub(1, 1) ~= "_" then env[k] = v end
  end
end

-- ---------------------------------------------------------------- running
function R.newEnv(name)
  return setmt({ __name__ = name }, {
    __module = true,
    __index = function(_, k)
      local v = B[k]
      if v ~= nil then return v end
      if k == "None" then return None end
      if k == "__file__" then return R.scriptPath end
      if k:match("^_t%d+$") then return nil end
      raise(B.NameError("name '" .. k .. "' is not defined"))
    end,
  })
end

local HELPERS = {}
for _, k in ipairs{ "T", "repr", "str", "fmt", "UNP", "SA", "SI", "DI", "DA", "GA", "GI", "CM", "CMK", "CK", "tuple", "list", "dict", "setlit", "set", "dictlit", "dictmerge",
  "dset", "sadd", "stararg", "concat", "takekw", "kwget", "kwdict", "kwmerge", "def", "named", "gen", "yield", "yieldfrom", "iter", "super", "slice", "pow", "neg", "mul", "div", "idiv",
  "mod", "matmul", "add", "sub", "shl", "shr", "band", "bxor", "bor", "lt", "gt", "le", "ge", "eq", "ne", "notin", "is", "isnot", "iadd", "imul", "exc", "excmatch", "raise",
  "import", "importall", "class", "classof", "rng", "andv", "orv", "ifv" } do
  HELPERS[#HELPERS + 1] = k
end
local aliases = { and_ = "R_and", or_ = "R_or", if_ = "R_if", in_ = "R_in" }

local function header()
  local names, values = {}, {}
  for _, k in ipairs(HELPERS) do names[#names + 1] = "R_" .. k; values[#values + 1] = "RT." .. k end
  for k, v in pairs(aliases) do names[#names + 1] = v; values[#values + 1] = "RT." .. k end
  return "local pcall,error,R_rawget=pcall,error,rawget\nlocal RT, _ENV = ...\nlocal None=RT.None\nlocal _L=0\nlocal R_curexc\nlocal R_pcall,R_error=pcall,error\nlocal " .. concat(names, ",") .. "=" .. concat(values, ",") .. "\nRT.lineFn=function() return _L end\n"
end
R.header = header

R.header = function() return header() end
function R.compileText(src, name)
  local ok, text = pcall(R.compiler, src, name)
  if not ok then
    if type_(text) == "table" and text.syntax then
      error(setmt({ syntax = text.syntax, line = text.line }, { __tostring = function() return text.syntax end }), 0)
    end
    error(text, 0)
  end
  return header() .. text
end
function R.runSource(src, name, env)
  local code = R.compileText(src, name)
  local f, e = load(code, "=" .. name, "t")
  if not f then error({ syntax = "internal: " .. tostring(e), line = 0 }, 0) end
  return f(R, env)
end

-- A program translated on the computer (tools/linux2esp.py): the Lua text of __main__, argv, and R.bundled: the modules of the program, also translated
function R.run(text, argv)
  R.argv = list(argv)
  R.scriptDir = "."
  local env = R.newEnv("__main__")
  return R.protect(function()
    local f, e = load(header() .. text, "=" .. tostring(argv[1]), "t")
    if not f then error({ syntax = "internal: " .. tostring(e), line = 0 }, 0) end
    return f(R, env)
  end, tostring(argv[1]))
end

function R.main(args, compiler)
  R.compiler = compiler
  local path
  local list_ = {}
  local i = 1
  local code
  while args[i] do
    local a = args[i]
    if a == "-c" then code = args[i + 1]; i = i + 2; list_[1] = "-c"; break
    elseif a == "--version" or a == "-V" then write("Python 3.12.0 (ESP Linux)\n"); return 0
    elseif a == "--selftest" then code = "print('python ok', sum(i*i for i in range(4)))"; i = i + 1; list_[1] = "-c"; break
    elseif a == "-u" or a == "-B" then i = i + 1
    else path = a; list_[1] = a; i = i + 1; break end
  end
  while args[i] do list_[#list_ + 1] = args[i]; i = i + 1 end
  R.argv = list(list_)
  if not path and not code then return R.repl() end
  local src = code
  if path then
    src = fs.read(path)
    if not src then
      write("python3: can't open file '" .. path .. "': [Errno 2] No such file or directory\n")
      return 2
    end
    R.scriptDir = path:match("^(.*)/[^/]*$") or "."
    R.scriptPath = path
  end
  local env = R.newEnv("__main__")
  return R.protect(function() R.runSource(src, path or "<string>", env) end, path or "<string>")
end

function R.protect(f, name)
  local ok, e = pcall(f)
  if ok then return 0 end
  if type_(e) == "table" and e.syntax then
    write('  File "' .. name .. '", line ' .. tostring(e.line) .. "\nSyntaxError: " .. e.syntax .. "\n")
    return 1
  end
  if type_(e) == "string" and e:find("interrupted", 1, true) then error(e, 0) end
  local x = R.exc(e)
  local cn = getmt(x).__name__
  if cn == "SystemExit" then
    local a = rawget_(x, "args")
    local c = a and a[1]
    if c == nil or c == None then return 0 end
    if mtype(c) then return c end
    write(str(c) .. "\n")
    return 1
  end
  local line = R.lineFn and R.lineFn() or 0
  local msg = str(x)
  write("Traceback (most recent call last):\n  File \"" .. name .. "\", line " .. line .. ", in <module>\n" .. cn .. (msg ~= "" and (": " .. msg) or "") .. "\n")
  return 1
end

function R.repl()
  write("Python 3.12.0 (ESP Linux, translated to Lua)\nType exit() to leave.\n")
  local env = R.newEnv("__main__")
  while true do
    local line = readLine(">>> ")
    if not line then write("\n"); return 0 end
    local text = line
    if line:match(":%s*$") then
      while true do
        local more = readLine("... ")
        if not more or more == "" then break end
        text = text .. "\n" .. more
      end
    end
    if text:match("%S") then
      -- an expression prints its value
      local shown = false
      local okC = pcall(R.compiler, "_ = (" .. text .. ")\n", "<stdin>")
      if okC and not text:find("^%s*print%s*%(") then
        local code = R.protect(function()
          R.runSource("_ = (" .. text .. ")\nif _ is not None: print(repr(_))\n", "<stdin>", env)
        end, "<stdin>")
        shown = true
        if env.__exit then return code end
      end
      if not shown then
        R.protect(function() R.runSource(text .. "\n", "<stdin>", env) end, "<stdin>")
      end
    end
  end
end

-- ---------------------------------------------------------------- re: a backtracking matcher
function R.makeRe(moduleFn)
  local m = moduleFn("re", {})
  m.IGNORECASE, m.I, m.MULTILINE, m.M, m.DOTALL, m.S = 2, 2, 8, 8, 16, 16
  local engine = driver.load("relang")
  local parse, exec = engine.parse, engine.exec
  local Match = newBuiltinType("Match")
  function Match.group(mm, ...)
    local n = select("#", ...)
    local function one(g)
      if g == nil or g == 0 then return mm.s:sub(mm.a, mm.b - 1) end
      if type_(g) == "string" then g = mm.names[g] end
      local c = mm.caps[g]
      if not c then return None end
      return mm.s:sub(c[1], c[2])
    end
    if n <= 1 then return one((...)) end
    local o = {}
    for i = 1, n do o[i] = one((select(i, ...))) end
    return tuple(o)
  end
  function Match.groups(mm)
    local o = {}
    for i = 1, mm.ng do local c = mm.caps[i]; o[i] = c and mm.s:sub(c[1], c[2]) or None end
    return tuple(o)
  end
  function Match.groupdict(mm)
    local d = dict()
    for n, i in pairs(mm.names) do local c = mm.caps[i]; dset(d, n, c and mm.s:sub(c[1], c[2]) or None) end
    return d
  end
  function Match.start(mm) return mm.a - 1 end
  Match["end_"] = function(mm) return mm.b - 1 end
  Match["end"] = Match["end_"]
  function Match.span(mm) return tuple{ mm.a - 1, mm.b - 1 } end
  Match.__repr = function(mm) return "<re.Match object; span=(" .. (mm.a - 1) .. ", " .. (mm.b - 1) .. "), match=" .. repr(mm.s:sub(mm.a, mm.b - 1)) .. ">" end
  local Pattern = newBuiltinType("Pattern")
  local function compileRe(p, flags)
    if getmt(p) == Pattern then return p end
    local tree, ng, names = parse(p)
    return setmt({ tree = tree, ng = ng, names = names, flags = flags or 0, pattern = p }, Pattern)
  end
  local function matchAt(pt, s, i)
    local e, caps = exec(pt.tree, s, i, pt.flags)
    if e then return setmt({ s = s, a = i, b = e, caps = caps, names = pt.names, ng = pt.ng }, Match) end
  end
  local function searchFrom(pt, s, i)
    for j = i, #s + 1 do
      local mm = matchAt(pt, s, j)
      if mm then return mm end
    end
  end
  function Pattern.match(pt, s) return matchAt(pt, s, 1) or None end
  function Pattern.fullmatch(pt, s)
    local mm = matchAt(pt, s, 1)
    if mm and mm.b == #s + 1 then return mm end
    return None
  end
  function Pattern.search(pt, s) return searchFrom(pt, s, 1) or None end
  local function allMatches(pt, s)
    local out, i = {}, 1
    while i <= #s + 1 do
      local mm = searchFrom(pt, s, i)
      if not mm then break end
      out[#out + 1] = mm
      i = mm.b > mm.a and mm.b or mm.b + 1
    end
    return out
  end
  function Pattern.findall(pt, s)
    local o = {}
    for i, mm in ipairs(allMatches(pt, s)) do
      if pt.ng == 0 then o[i] = Match.group(mm)
      elseif pt.ng == 1 then o[i] = Match.group(mm, 1)
      else o[i] = Match.groups(mm) end
    end
    return list(o)
  end
  function Pattern.finditer(pt, s) return list(allMatches(pt, s)) end
  function Pattern.sub(pt, rep, s, count)
    local kw = R.takekw()
    count = count or (kw and kw.count) or 0
    local out, i, n = {}, 1, 0
    for _, mm in ipairs(allMatches(pt, s)) do
      if count > 0 and n >= count then break end
      out[#out + 1] = s:sub(i, mm.a - 1)
      if type_(rep) == "function" then out[#out + 1] = rep(mm)
      else
        out[#out + 1] = rep:gsub("\\(%d)", function(d) local g = Match.group(mm, tonumber(d)); return g == None and "" or g end):gsub("\\g<([%w_]+)>", function(g) return Match.group(mm, tonumber(g) or g) end)
      end
      i = mm.b
      n = n + 1
    end
    out[#out + 1] = s:sub(i)
    return concat(out)
  end
  function Pattern.split(pt, s)
    local out, i = {}, 1
    for _, mm in ipairs(allMatches(pt, s)) do
      if mm.b > mm.a then
        out[#out + 1] = s:sub(i, mm.a - 1)
        for g = 1, pt.ng do local c = mm.caps[g]; out[#out + 1] = c and s:sub(c[1], c[2]) or None end
        i = mm.b
      end
    end
    out[#out + 1] = s:sub(i)
    return list(out)
  end
  m.compile = function(p, f) return compileRe(p, f) end
  for _, n in ipairs{ "match", "fullmatch", "search", "findall", "finditer", "split" } do
    m[n] = function(p, s, f) return Pattern[n](compileRe(p, f), s) end
  end
  m.sub = function(p, r, s, c) return Pattern.sub(compileRe(p), r, s, c) end
  m.escape = function(s) return (s:gsub("[^%w_]", "\\%0")) end
  m.error = B.ValueError
  return m
end

return R
