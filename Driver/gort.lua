#!lua
-- gort: the run-time of the Go programs that golang translates: slices, maps, goroutines, channels, fmt and the other packages.
local R = {}
local mtype, floor, concat, sfmt, unpack = math.type, math.floor, table.concat, string.format, table.unpack
local setmt, getmt, type_ = setmetatable, getmetatable, type
local function write(s) term.write(s) end
local PanicMt = {}
local function panicText(v)
  if type_(v) == "table" and v.Error then return v:Error() end
  return R.sprint(v)
end
function R.panic(v) error(setmt({ v = v }, PanicMt), 0) end
local function rtPanic(msg)
  error(setmt({ v = setmt({ msg = "runtime error: " .. msg }, R.RuntimeErr), rt = true }, PanicMt), 0)
end
R.RuntimeErr = { __name = "runtime.Error" }
R.RuntimeErr.__index = R.RuntimeErr
function R.RuntimeErr.Error(e) return e.msg end

function R.newType(n)
  local t = { __name = n }
  t.__index = t
  return t
end
function R.struct(t) return t end

-- ---- slices: {a = the array, o = offset, n = length, c = capacity} ----
local Slice = { __name = "slice" }
Slice.__index = Slice
local function mk(a, o, n, c) return setmt({ a = a, o = o, n = n, c = c }, Slice) end
function R.make(n, c, zero)
  if n < 0 then rtPanic("makeslice: len out of range") end
  local a = {}
  c = c or n
  for i = 0, c - 1 do a[i] = zero() end
  local s = mk(a, 0, n, c)
  s.zero = zero
  return s
end
function R.arrayOf(n, zero)
  local a = {}
  for i = 0, n - 1 do a[i] = zero() end
  local s = mk(a, 0, n, n)
  s.isArray = true
  return s
end
function R.sliceLit(n, items, zero, isArray)
  for i = 0, n - 1 do if items[i] == nil then items[i] = zero() end end
  local s = mk(items, 0, n, n)
  s.zero = zero
  s.isArray = isArray or nil
  return s
end
function R.sliceFrom(...)
  local n = select("#", ...)
  local a = {}
  for i = 1, n do a[i - 1] = (select(i, ...)) end
  return mk(a, 0, n, n)
end
function R.unpackSlice(s)
  if s == nil then return end
  local t = {}
  for i = 1, s.n do t[i] = s.a[s.o + i - 1] end
  return unpack(t, 1, s.n)
end
function R.idx(s, i)
  if s == nil or i < 0 or i >= s.n then
    rtPanic("index out of range [" .. tostring(i) .. "] with length " .. tostring(s and s.n or 0))
  end
  return s.a[s.o + i]
end
function R.setIdx(s, i, v)
  if s == nil or i < 0 or i >= s.n then
    rtPanic("index out of range [" .. tostring(i) .. "] with length " .. tostring(s and s.n or 0))
  end
  s.a[s.o + i] = v
end
function R.addrIdx(s, i)
  return setmt({}, { __index = function(_, k) if k == "v" then return s.a[s.o + i] end end, __newindex = function(_, k, v) if k == "v" then s.a[s.o + i] = v end end })
end
function R.idxAny(c, i)
  if type_(c) == "table" and getmt(c) == Slice then return R.idx(c, i) end
  if type_(c) == "table" and getmt(c) == R.Map then return R.mapGet(c, i) end
  if type_(c) == "string" then return R.strIdx(c, i) end
  return c
end
function R.setAny(c, i, v)
  if getmt(c) == Slice then return R.setIdx(c, i, v) end
  return R.mapSet(c, i, v)
end
function R.slice(s, a, b, c)
  if type_(s) == "string" then  -- the type of the value was not known to the translator
    b = b or #s
    if a < 0 or b < a or b > #s then rtPanic("slice bounds out of range [" .. a .. ":" .. b .. "]") end
    return s:sub(a + 1, b)
  end
  if s == nil then
    if a == 0 and (b == nil or b == 0) then return nil end
    rtPanic("slice bounds out of range")
  end
  b = b or s.n
  if a < 0 or b < a or b > s.c then rtPanic("slice bounds out of range [" .. a .. ":" .. b .. "]") end
  local r = mk(s.a, s.o + a, b - a, (c or s.c) - a)
  r.zero = s.zero
  return r
end
function R.append(s, ...)
  local k = select("#", ...)
  if k == 0 then return s end
  local n = s and s.n or 0
  local cap = s and s.c or 0
  local r
  if n + k <= cap then
    r = mk(s.a, s.o, n + k, cap)
  else
    local c2 = math.max(cap * 2, n + k, 4)
    local a = {}
    if s then for i = 0, n - 1 do a[i] = s.a[s.o + i] end end
    r = mk(a, 0, n + k, c2)
  end
  r.zero = s and s.zero
  for i = 1, k do r.a[r.o + n + i - 1] = (select(i, ...)) end
  return r
end
function R.appendSlice(s, t)
  if t == nil then return s end
  if type_(t) == "string" then t = R.bytes(t) end
  return R.append(s, R.unpackSlice(t))
end
function R.len(x)
  if x == nil then return 0 end
  if type_(x) == "string" then return #x end
  return x.n or 0
end
function R.cap(x) if x == nil then return 0 end return x.c or x.cap or 0 end
function R.copyInto(d, s)
  if type_(s) == "string" then s = R.bytes(s) end
  if d == nil or s == nil then return 0 end
  local n = math.min(d.n, s.n)
  local t = {}
  for i = 0, n - 1 do t[i] = s.a[s.o + i] end
  for i = 0, n - 1 do d.a[d.o + i] = t[i] end
  return n
end
function R.clear(x)
  if getmt(x) == R.Map then x.h = {}; x.n = 0; return end
  for i = 0, x.n - 1 do x.a[x.o + i] = x.zero and x.zero() or 0 end
end
function R.min(a, ...) for _, v in ipairs{ ... } do if v < a then a = v end end return a end
function R.max(a, ...) for _, v in ipairs{ ... } do if v > a then a = v end end return a end

-- a copy of a struct or an array value
local function copy(v)
  if type_(v) ~= "table" then return v end
  local m = getmt(v)
  if m == Slice then
    if not v.isArray then return v end
    local a = {}
    for i = 0, v.n - 1 do a[i] = copy(v.a[v.o + i]) end
    local s = mk(a, 0, v.n, v.n)
    s.isArray = true
    s.zero = v.zero
    return s
  end
  if m and m.__struct then
    local o = {}
    for _, f in ipairs(m.__fields) do
      local x = v[f]
      if type_(x) == "table" and (getmt(x) == Slice and x.isArray or (getmt(x) and getmt(x).__struct)) and not R.isPointerField then o[f] = copy(x) else o[f] = x end
    end
    return setmt(o, m)
  end
  if m == nil then
    local o = {}
    for k, x in pairs(v) do o[k] = x end
    return o
  end
  return v
end
R.copy = copy
local function deepEq(a, b)
  if a == b then return true end
  if type_(a) ~= "table" or type_(b) ~= "table" then return false end
  local m = getmt(a)
  if m ~= getmt(b) then return false end
  if m == Slice then
    if a.n ~= b.n then return false end
    for i = 0, a.n - 1 do if not deepEq(a.a[a.o + i], b.a[b.o + i]) then return false end end
    return true
  end
  if m and m.__struct then
    for _, f in ipairs(m.__fields) do if not deepEq(a[f], b[f]) then return false end end
    return true
  end
  return false
end
R.deepEq = deepEq
function R.eq(a, b) if type_(a) == "table" then return deepEq(a, b) end return a == b end

-- ---- numbers ----
function R.idiv(a, b)
  if b == 0 then rtPanic("integer divide by zero") end
  local q = a // b
  if q < 0 and q * b ~= a then q = q + 1 end
  return q
end
function R.imod(a, b)
  if b == 0 then rtPanic("integer divide by zero") end
  return math.fmod(a, b)
end
function R.div(a, b)
  if mtype(a) == "integer" and mtype(b) == "integer" then return R.idiv(a, b) end
  return a / b
end
function R.tofloat(x) if mtype(x) then return x + 0.0 end return x end
function R.f2i(x)
  if x ~= x then return math.mininteger end
  local r = x >= 0 and floor(x) or -floor(-x)
  return math.tointeger(r) or math.mininteger
end
function R.toint(x) if mtype(x) == "float" then return R.f2i(x) end return x end

-- ---- strings ----
function R.strIdx(s, i)
  if i < 0 or i >= #s then rtPanic("index out of range [" .. i .. "] with length " .. #s) end
  return s:byte(i + 1)
end
function R.strSlice(s, a, b)
  b = b or #s
  if a < 0 or b < a or b > #s then rtPanic("slice bounds out of range [" .. a .. ":" .. b .. "]") end
  return s:sub(a + 1, b)
end
function R.runeStr(r) return utf8.char(r) end
function R.bytes(s)
  local a = {}
  for i = 1, #s do a[i - 1] = s:byte(i) end
  return mk(a, 0, #s, #s)
end
function R.runes(s)
  local a, n = {}, 0
  for _, c in utf8.codes(s, true) do a[n] = c; n = n + 1 end
  return mk(a, 0, n, n)
end
function R.toString(x)
  if type_(x) == "string" then return x end
  if type_(x) == "number" then return utf8.char(x) end
  if x == nil then return "" end
  if getmt(x) == Slice then
    local p = {}
    local isBytes = true
    for i = 0, x.n - 1 do
      local c = x.a[x.o + i]
      if c > 255 then isBytes = false end
    end
    for i = 0, x.n - 1 do p[i + 1] = utf8.char(x.a[x.o + i]) end
    if isBytes then
      local q = {}
      for i = 0, x.n - 1 do q[i + 1] = string.char(x.a[x.o + i]) end
      local raw = concat(q)
      if utf8.len(raw) then return raw end
    end
    return concat(p)
  end
  return tostring(x)
end

-- ---- maps ----
local Map = { __name = "map" }
Map.__index = Map
R.Map = Map
local function mapKey(k)
  if type_(k) == "table" then
    local m = getmt(k)
    if m and m.__struct then
      local p = {}
      for i, f in ipairs(m.__fields) do p[i] = tostring(mapKey(k[f])) end
      return "\0S" .. tostring(m.__name) .. concat(p, "\1")
    end
    if m == Slice and k.isArray then
      local p = {}
      for i = 0, k.n - 1 do p[i + 1] = tostring(mapKey(k.a[k.o + i])) end
      return "\0A" .. concat(p, "\1")
    end
  end
  return k
end
function R.mapLit(zero, tn, ...)
  local m = setmt({ h = {}, n = 0, zero = zero, tn = tn }, Map)
  local a = { ... }
  for i = 1, select("#", ...), 2 do R.mapSet(m, a[i], a[i + 1]) end
  return m
end
function R.mapGet(m, k)
  if m == nil then return nil end
  local s = m.h[mapKey(k)]
  if s then return s.v end
  return m.zero()
end
function R.mapGet2(m, k)
  if m == nil then return nil, false end
  local s = m.h[mapKey(k)]
  if s then return s.v, true end
  return m.zero(), false
end
function R.mapSet(m, k, v)
  if m == nil then error(setmt({ v = setmt({ msg = "assignment to entry in nil map" }, R.RuntimeErr) }, PanicMt), 0) end
  local hk = mapKey(k)
  local s = m.h[hk]
  if s then s.v = v
  else
    m.seq = (m.seq or 0) + 1
    m.h[hk] = { k = k, v = v, seq = m.seq }
    m.n = m.n + 1
  end
end
function R.delete(m, k)
  if m == nil then return end
  local hk = mapKey(k)
  if m.h[hk] then m.h[hk] = nil; m.n = m.n - 1 end
end
local function sortedEntries(m)
  local items = {}
  for _, s in pairs(m.h) do items[#items + 1] = s end
  table.sort(items, function(a, b)
    if type_(a.k) == type_(b.k) and (type_(a.k) == "number" or type_(a.k) == "string") then return a.k < b.k end
    return a.seq < b.seq
  end)
  return items
end
-- ---- range ----
function R.range(x)
  if x == nil then return function() end end
  local t = type_(x)
  if t == "number" then
    local i = -1
    return function()
      i = i + 1
      if i < x then return i end
    end
  end
  if t == "string" then
    local i, n = 1, #x
    return function()
      if i > n then return nil end
      local at = i
      local c = x:byte(i)
      local len = c < 0x80 and 1 or (c < 0xE0 and 2 or (c < 0xF0 and 3 or 4))
      local ok, r = pcall(utf8.codepoint, x, i)
      if not ok then r = 0xFFFD; len = 1 end
      i = i + len
      return at - 1, r
    end
  end
  local m = getmt(x)
  if m == Slice then
    local i, n = -1, x.n
    return function()
      i = i + 1
      if i < n then return i, x.a[x.o + i] end
    end
  end
  if m == Map then
    local items = sortedEntries(x)
    local i = 0
    return function()
      while true do
        i = i + 1
        local s = items[i]
        if not s then return nil end
        if x.h[mapKey(s.k)] then return s.k, s.v end
      end
    end
  end
  if m == R.Chan then
    return function()
      local v, ok = R.recv2(x)
      if ok then return v end
    end
  end
  if t == "function" then
    -- a range-over-func iterator: not a coroutine in the host, values are collected
    local vals = {}
    x(function(a, b) vals[#vals + 1] = { a, b }; return true end)
    local i = 0
    return function()
      i = i + 1
      if vals[i] then return vals[i][1], vals[i][2] end
    end
  end
  error("cannot range over this value", 0)
end
-- ---- pointers ----
function R.newBox(v) return { v = v } end
function R.addr(get, set)
  return setmt({}, { __index = function(_, k) if k == "v" then return get() end end, __newindex = function(_, k, v) if k == "v" then set(v) end end })
end
function R.deref(p)
  if p == nil then rtPanic("invalid memory address or nil pointer dereference") end
  if type_(p) == "table" and getmt(p) and getmt(p).__struct then return p end
  return p.v
end
function R.bindMethod(f, self) return function(...) return f(self, ...) end end
function R.callMethod(o, n, ...)
  if o == nil then rtPanic("invalid memory address or nil pointer dereference") end
  if type_(o) == "table" then
    local f = o[n]
    if f then
      if rawget(o, n) ~= nil and getmt(o) == nil then return f(...) end
      if rawget(o, n) ~= nil then return f(...) end
      return f(o, ...)
    end
  end
  error("the value has no method " .. n, 0)
end
-- ---- types at run time ----
local function typeName(v)
  local t = type_(v)
  if t == "number" then return mtype(v) == "integer" and "int" or "float64" end
  if t == "string" then return "string" end
  if t == "boolean" then return "bool" end
  if t == "function" then return "func" end
  if t == "table" then
    local m = getmt(v)
    if m == Slice then return "[]" end
    if m == Map then return v.tn or "map" end
    if m and m.__name then return m.__name end
    return "struct"
  end
  return "nil"
end
function R.isType(v, n, G)
  if v == nil then return false end
  if n == "interface" or n == "any" then return true end
  if n == "error" then return type_(v) == "table" and v.Error ~= nil end
  local base = n:gsub("^%*", "")
  local gt = G[base]
  if gt and gt.__iface then
    if type_(v) ~= "table" then return false end
    for _, m in ipairs(gt.__iface) do if v[m] == nil then return false end end
    return true
  end
  local tn = typeName(v)
  if tn == base then return true end
  if base:sub(1, 2) == "[]" then return tn == "[]" end
  if base == "int32" or base == "int64" or base == "uint8" or base == "byte" or base == "uint" then return tn == "int" end
  if base == "float32" then return tn == "float64" end
  return false
end
function R.assert(v, n, G)
  if R.isType(v, n, G) then return v end
  error(setmt({ v = setmt({ msg = "interface conversion: interface {} is " .. typeName(v) .. ", not " .. n }, R.RuntimeErr), rt = false }, PanicMt), 0)
end
local ZEROS = { int = 0, float64 = 0.0, string = "", bool = false }
function R.assert2(v, n, G)
  if R.isType(v, n, G) then return v, true end
  return ZEROS[n], false
end
-- ---- defer, recover ----
local panicking = {}
function R.runDefers(defers, res)
  local state = { active = not res[1], err = res[2] }
  if state.active and getmt(state.err) ~= PanicMt then
    if type_(state.err) == "string" and state.err:find("interrupted", 1, true) then error(state.err, 0) end
    if os.getenv("GO_TRACE") then io.stderr:write(tostring(state.err), "\n") end
    state.err = setmt({ v = setmt({ msg = "runtime error: " .. tostring(state.err):gsub("^.-:%d+: ", "") }, R.RuntimeErr) }, PanicMt)
  end
  panicking[#panicking + 1] = state
  for i = #defers, 1, -1 do
    local ok, e = pcall(defers[i])
    if not ok then state.active = true; state.err = e end
  end
  panicking[#panicking] = nil
  if state.active then error(state.err, 0) end
  if not res[1] then
    res[1] = true
    res.n = 1
  end
end
function R.recover()
  local s = panicking[#panicking]
  if s and s.active then
    s.active = false
    local e = s.err
    if getmt(e) == PanicMt then return e.v end
    return e
  end
  return nil
end
-- ---- goroutines ----
local ready, sleeping = {}, {}
local current
local clock = 0
function R.go(f)
  ready[#ready + 1] = { co = coroutine.create(f) }
end
local function park() return coroutine.yield("park") end
local function wake(g) ready[#ready + 1] = g end
local function yieldNow()
  ready[#ready + 1] = current
  coroutine.yield("yield")
end
function R.sleepNs(ns)
  local g = current
  g.at = clock + ns / 1000000
  sleeping[#sleeping + 1] = g
  park()
end
R.Chan = { __name = "chan" }
R.Chan.__index = R.Chan
function R.chan(cap, zero)
  return setmt({ cap = cap, buf = {}, n = 0, recvq = {}, sendq = {}, closed = false, zero = zero }, R.Chan)
end
local function nilWait()
  while true do park() end
end
function R.send(c, v)
  if c == nil then nilWait() end
  if c.closed then R.panic(setmt({ msg = "send on closed channel" }, R.RuntimeErr)) end
  local w = table.remove(c.recvq, 1)
  if w then
    if w.sel then w.sel.done = true; w.sel.idx = w.idx end
    w.g.val, w.g.ok = v, true
    if w.sel then w.g.selIdx = w.idx end
    wake(w.g)
    return
  end
  if c.n < c.cap then
    c.buf[#c.buf + 1] = v
    c.n = c.n + 1
    return
  end
  local me = { g = current, v = v }
  c.sendq[#c.sendq + 1] = me
  park()
  if me.closedPanic then R.panic(setmt({ msg = "send on closed channel" }, R.RuntimeErr)) end
end
local function dropDone(q)
  while q[1] and q[1].sel and q[1].sel.done do table.remove(q, 1) end
end
function R.recv2(c)
  if c == nil then nilWait() end
  if c.n > 0 then
    local v = table.remove(c.buf, 1)
    c.n = c.n - 1
    dropDone(c.sendq)
    local s = table.remove(c.sendq, 1)
    if s then
      c.buf[#c.buf + 1] = s.v
      c.n = c.n + 1
      if s.sel then s.sel.done = true; s.g.selIdx = s.idx end
      wake(s.g)
    end
    return v, true
  end
  dropDone(c.sendq)
  local s = table.remove(c.sendq, 1)
  if s then
    if s.sel then s.sel.done = true; s.g.selIdx = s.idx end
    wake(s.g)
    return s.v, true
  end
  if c.closed then return c.zero(), false end
  local g = current
  c.recvq[#c.recvq + 1] = { g = g }
  park()
  return g.val, g.ok
end
function R.recv(c) local v = R.recv2(c); return v end
function R.closeChan(c)
  if c == nil then R.panic(setmt({ msg = "close of nil channel" }, R.RuntimeErr)) end
  if c.closed then R.panic(setmt({ msg = "close of closed channel" }, R.RuntimeErr)) end
  c.closed = true
  for _, w in ipairs(c.recvq) do
    if not (w.sel and w.sel.done) then
      if w.sel then w.sel.done = true; w.g.selIdx = w.idx end
      w.g.val, w.g.ok = c.zero(), false
      wake(w.g)
    end
  end
  c.recvq = {}
end
function R.select(cases)
  -- a case that can go now
  local order = {}
  local default
  for i, x in ipairs(cases) do
    if x.default then default = i else order[#order + 1] = i end
  end
  for k = #order, 2, -1 do
    local j = math.random(k)
    order[k], order[j] = order[j], order[k]
  end
  for _, i in ipairs(order) do
    local x = cases[i]
    if x.recv ~= nil then
      local c = x.recv
      dropDone(c.sendq)
      if c.n > 0 or c.sendq[1] or c.closed then
        local v, ok = R.recv2(c)
        return i, v, ok
      end
    elseif x.send ~= nil then
      local c = x.send
      if c.closed then R.panic(setmt({ msg = "send on closed channel" }, R.RuntimeErr)) end
      dropDone(c.recvq)
      if c.recvq[1] or c.n < c.cap then
        R.send(c, x.v)
        return i
      end
    end
  end
  if default then return default end
  if #order == 0 then nilWait() end
  local sel = { done = false }
  local g = current
  for _, i in ipairs(order) do
    local x = cases[i]
    if x.recv ~= nil then
      table.insert(x.recv.recvq, { g = g, sel = sel, idx = i })
    elseif x.send ~= nil then
      table.insert(x.send.sendq, { g = g, sel = sel, idx = i, v = x.v })
    end
  end
  park()
  return g.selIdx, g.val, g.ok
end
local function runAll(mainF)
  local mainG = { co = coroutine.create(mainF) }
  ready[#ready + 1] = mainG
  while true do
    local g = table.remove(ready, 1)
    if not g then
      if #sleeping == 0 then
        error(setmt({ fatal = "fatal error: all goroutines are asleep - deadlock!" }, PanicMt), 0)
      end
      table.sort(sleeping, function(a, b) return a.at < b.at end)
      g = table.remove(sleeping, 1)
      if g.at > clock then
        if sys and sys.sleep then sys.sleep(floor(g.at - clock)) end
        clock = g.at
      end
    end
    current = g
    local ok, e = coroutine.resume(g.co)
    if not ok then error(e, 0) end
    if g == mainG and coroutine.status(g.co) == "dead" then return end
  end
end
-- ---- fmt ----
local function floatG(x)
  if x ~= x then return "NaN" end
  if x == math.huge then return "+Inf" elseif x == -math.huge then return "-Inf" end
  if x == 0 then return (1 / x < 0) and "-0" or "0" end
  local a = math.abs(x)
  for p = 1, 17 do
    local s = sfmt("%." .. p .. "g", x)
    if tonumber(s) == x then
      local m, e = s:match("^(.-)e([+-]%d+)$")
      if a >= 1e21 or a < 1e-4 then
        if not m then
          -- %g did not use an exponent: make it
          s = sfmt("%." .. (p - 1) .. "e", x)
          m, e = s:match("^(.-)e([+-]%d+)$")
        end
        return m .. "e" .. e:sub(1, 1) .. sfmt("%02d", math.abs(tonumber(e)))
      end
      if m then return (sfmt("%.0f", x)) end
      return s
    end
  end
  return sfmt("%.17g", x)
end
local function vText(v, plus, sharp, top)
  local t = type_(v)
  if t == "nil" then return "<nil>" end
  if t == "number" then if mtype(v) == "integer" then return tostring(v) end return floatG(v) end
  if t == "boolean" then return v and "true" or "false" end
  if t == "string" then if sharp or top == "q" then return sfmt("%q", v):gsub("\\\n", "\\n") end return v end
  if t == "function" then return "0xc000010000" end
  local m = getmt(v)
  if not sharp then
    if v.Error and type_(v.Error) == "function" then return v:Error() end
    if v.String and type_(v.String) == "function" then return v:String() end
  end
  if m == Slice then
    local p = {}
    for i = 0, v.n - 1 do p[i + 1] = vText(v.a[v.o + i], plus, sharp) end
    return "[" .. concat(p, " ") .. "]"
  end
  if m == Map then
    local p = {}
    for i, s in ipairs(sortedEntries(v)) do p[i] = vText(s.k, plus, sharp) .. ":" .. vText(s.v, plus, sharp) end
    return "map[" .. concat(p, " ") .. "]"
  end
  if m and m.__struct then
    local p = {}
    for i, f in ipairs(m.__fields) do
      local fv = vText(v[f], plus, sharp)
      p[i] = (plus or sharp) and (f .. ":" .. fv) or fv
    end
    if sharp then return "main." .. m.__name .. "{" .. concat(p, ", ") .. "}" end
    return "{" .. concat(p, " ") .. "}"
  end
  if m == R.Chan then return "0xc000020000" end
  if rawget(v, "v") ~= nil then return "0xc000012345" end
  local p = {}
  for k, x in pairs(v) do p[#p + 1] = vText(x, plus, sharp) end
  return "{" .. concat(p, " ") .. "}"
end
function R.sprint(v) return vText(v) end
local function sprintf(f, ...)
  local args = { ... }
  local n = select("#", ...)
  local ai = 1
  local out, i, len = {}, 1, #f
  while i <= len do
    local a = f:find("%", i, true)
    if not a then out[#out + 1] = f:sub(i); break end
    out[#out + 1] = f:sub(i, a - 1)
    local flags, w, dot, p, c, e = f:match("^%%([%-+# 0]*)([%d%*]*)(%.?)([%d%*]*)(.)()", a)
    if not c then out[#out + 1] = "%!(NOVERB)"; break end
    i = e
    if c == "%" then out[#out + 1] = "%"
    else
      if w == "*" then w = tostring(args[ai]); ai = ai + 1 end
      if p == "*" then p = tostring(args[ai]); ai = ai + 1 end
      if ai > n then out[#out + 1] = "%!" .. c .. "(MISSING)"
      else
        local v = args[ai]
        ai = ai + 1
        local spec = "%" .. flags:gsub("#", "") .. w .. (dot ~= "" and ("." .. p) or "")
        local text
        if c == "v" then
          text = vText(v, flags:find("+", 1, true) ~= nil, flags:find("#", 1, true) ~= nil)
          text = sfmt("%" .. flags:gsub("[#+0]", "") .. w .. "s", text)
        elseif c == "d" then
          if mtype(v) == "integer" then text = sfmt(spec .. "d", v)
          elseif getmt(v) == Slice then text = vText(v)
          else text = "%!d(" .. typeName(v) .. "=" .. vText(v) .. ")" end
        elseif c == "s" then
          local s = (type_(v) == "table" and getmt(v) == Slice) and R.toString(v) or vText(v)
          if type_(v) == "number" then s = "%!s(" .. typeName(v) .. "=" .. vText(v) .. ")" end
          text = sfmt("%" .. flags:gsub("[#+0]", "") .. w .. (dot ~= "" and ("." .. p) or "") .. "s", s)
        elseif c == "q" then
          if type_(v) == "number" then text = "'" .. utf8.char(v) .. "'" else text = sfmt("%q", vText(v)):gsub("\\\n", "\\n") end
        elseif c == "f" or c == "F" then
          if mtype(v) then text = sfmt(spec .. "f", v) else text = "%!f(" .. typeName(v) .. "=" .. vText(v) .. ")" end
          if mtype(v) == "integer" then text = "%!f(int=" .. v .. ")" end
        elseif c == "e" or c == "E" or c == "g" or c == "G" then
          if c == "g" and dot == "" then text = sfmt("%" .. flags:gsub("[#+0]", "") .. w .. "s", floatG(v))
          else text = sfmt(spec .. c, v) end
        elseif c == "t" then text = sfmt("%" .. flags:gsub("[#+0]", "") .. w .. "s", tostring(v))
        elseif c == "x" or c == "X" or c == "o" then
          if type_(v) == "string" then
            text = v:gsub(".", function(ch) return sfmt(c == "x" and "%02x" or "%02X", ch:byte()) end)
          else text = sfmt(spec .. c, v) end
          if flags:find("#", 1, true) and c ~= "o" then text = "0" .. c .. text end
        elseif c == "b" then
          local bits = {}
          local x = v
          if x == 0 then bits[1] = "0" end
          while x > 0 do table.insert(bits, 1, tostring(x & 1)); x = x >> 1 end
          text = concat(bits)
          local wn = tonumber(w) or 0
          if #text < wn then text = (flags:find("0", 1, true) and "0" or " "):rep(wn - #text) .. text end
        elseif c == "c" then text = utf8.char(v)
        elseif c == "U" then text = sfmt("U+%04X", v)
        elseif c == "T" then
          local tn = typeName(v)
          if type_(v) == "table" and getmt(v) and getmt(v).__struct then tn = "main." .. tn end
          text = tn
        elseif c == "p" then text = "0xc000012345"
        else text = "%!" .. c .. "(" .. vText(v) .. ")" end
        out[#out + 1] = text
      end
    end
  end
  if ai <= n then
    local extra = {}
    for k = ai, n do extra[#extra + 1] = typeName(args[k]) .. "=" .. vText(args[k]) end
    out[#out + 1] = "%!(EXTRA " .. concat(extra, ", ") .. ")"
  end
  return concat(out)
end
local function sprintln(...)
  local p = {}
  for i = 1, select("#", ...) do p[i] = vText((select(i, ...))) end
  return concat(p, " ") .. "\n"
end
local function sprint(...)
  local p = {}
  local n = select("#", ...)
  local prevStr = true
  for i = 1, n do
    local v = select(i, ...)
    if i > 1 and type_(v) ~= "string" and not prevStr then p[#p + 1] = " " end
    p[#p + 1] = vText(v)
    prevStr = type_(v) == "string"
  end
  return concat(p)
end
function R.builtinPrint(k, ...) write(k == "println" and sprintln(...) or sprint(...)) end
local ErrT = R.newType("errorString")
function ErrT.Error(e) return e.s end
local function newError(s, wrapped) return setmt({ s = s, wrapped = wrapped }, ErrT) end
function ErrT.Unwrap(e) return e.wrapped end
local pkg = {}
R.pkg = pkg
R.stdout, R.stdin = { std = true }, { std = true, h = io and io.stdin }
R.stderr = { err = true, h = io and io.stderr }
local fileWriter = function(w, s)
  if w == nil or w.std then write(s)
  elseif w.err then w.h:write(s)
  elseif w.h then w.h:write(s)
  elseif w.WriteString then w:WriteString(s)
  else w:Write(R.bytes(s)) end
end
-- input from the keyboard
R.FileInfo = R.newType("FileInfo")
function R.FileInfo.Name(f) return f.name:match("([^/]*)$") end
function R.FileInfo.Size(f) return f.a.size or 0 end
function R.FileInfo.IsDir(f) return f.a.mode == "directory" end
function R.FileInfo.Mode(f) return f.a.mode == "directory" and 2147484141 or 420 end
function R.FileInfo.ModTime(f) return f.a.modification or 0 end
local function readLine()
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
local words = {}
local function scanInto(p, w)
  local cur = p.v
  if type_(cur) == "number" and mtype(cur) == "float" then p.v = (tonumber(w) or 0) + 0.0
  elseif type_(cur) == "number" then p.v = math.tointeger(tonumber(w) or 0) or 0
  else p.v = w end
end
pkg.fmt = {
  Println = function(...) local s = sprintln(...); write(s); return #s, nil end,
  Print = function(...) local s = sprint(...); write(s); return #s, nil end,
  Printf = function(f, ...) local s = sprintf(f, ...); write(s); return #s, nil end,
  Sprintf = sprintf, Sprint = sprint, Sprintln = sprintln,
  Errorf = function(f, ...)
    local wrapped
    for i = 1, select("#", ...) do
      local v = select(i, ...)
      if type_(v) == "table" and v.Error then wrapped = v end
    end
    local g = f:gsub("%%w", "%%v")
    return newError(sprintf(g, ...), f:find("%%w") and wrapped or nil)
  end,
  Fprintf = function(w, f, ...) fileWriter(w, sprintf(f, ...)) end,
  Fprintln = function(w, ...) fileWriter(w, sprintln(...)) end,
  Fprint = function(w, ...) fileWriter(w, sprint(...)) end,
  Scanln = function(...)
    local l = readLine()
    if not l then return 0, newError("EOF") end
    local c = 0
    local it = l:gmatch("%S+")
    for i = 1, select("#", ...) do
      local w = it()
      if not w then break end
      scanInto((select(i, ...)), w)
      c = c + 1
    end
    return c, nil
  end,
  Scan = function(...)
    local c = 0
    for i = 1, select("#", ...) do
      while #words == 0 do
        local l = readLine()
        if not l then return c, newError("EOF") end
        for w in l:gmatch("%S+") do words[#words + 1] = w end
      end
      scanInto((select(i, ...)), table.remove(words, 1))
      c = c + 1
    end
    return c, nil
  end,
  Sscanf = function() return 0, newError("Sscanf is not available") end,
  Sscan = function(s, ...)
    local it = s:gmatch("%S+")
    local c = 0
    for i = 1, select("#", ...) do
      local w = it()
      if not w then break end
      scanInto((select(i, ...)), w)
      c = c + 1
    end
    return c, nil
  end,
}
local function strSlice(t) local a = {}; for i, v in ipairs(t) do a[i - 1] = v end return mk(a, 0, #t, #t) end
local strings = {}
pkg.strings = strings
function strings.Contains(s, t) return s:find(t, 1, true) ~= nil end
function strings.ContainsRune(s, r) return s:find(utf8.char(r), 1, true) ~= nil end
function strings.ContainsAny(s, cs) for c in cs:gmatch(".") do if s:find(c, 1, true) then return true end end return false end
function strings.HasPrefix(s, t) return s:sub(1, #t) == t end
function strings.HasSuffix(s, t) return t == "" or s:sub(-#t) == t end
function strings.Index(s, t) local i = s:find(t, 1, true); return i and i - 1 or -1 end
function strings.IndexByte(s, c) local i = s:find(string.char(c), 1, true); return i and i - 1 or -1 end
function strings.IndexRune(s, c) local i = s:find(utf8.char(c), 1, true); return i and i - 1 or -1 end
function strings.LastIndex(s, t)
  local last, i = -1, 1
  while true do
    local a = s:find(t, i, true)
    if not a then return last end
    last = a - 1
    i = a + 1
  end
end
function strings.Count(s, t)
  if t == "" then return (utf8.len(s) or #s) + 1 end
  local c, i = 0, 1
  while true do
    local a, b = s:find(t, i, true)
    if not a then return c end
    c = c + 1
    i = b + 1
  end
end
function strings.Repeat(s, n) if n < 0 then R.panic("strings: negative Repeat count") end return s:rep(n) end
function strings.ToUpper(s) return s:upper() end
function strings.ToLower(s) return s:lower() end
function strings.Title(s) return (s:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)) end
function strings.TrimSpace(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function cset(c) return "[" .. c:gsub("[%^%]%-%%]", "%%%0") .. "]" end
function strings.Trim(s, c) local p = cset(c); return (s:gsub("^" .. p .. "+", ""):gsub(p .. "+$", "")) end
function strings.TrimLeft(s, c) return (s:gsub("^" .. cset(c) .. "+", "")) end
function strings.TrimRight(s, c) return (s:gsub(cset(c) .. "+$", "")) end
function strings.TrimPrefix(s, t) if s:sub(1, #t) == t then return s:sub(#t + 1) end return s end
function strings.TrimSuffix(s, t) if t ~= "" and s:sub(-#t) == t then return s:sub(1, -#t - 1) end return s end
function strings.Split(s, sep)
  local o = {}
  if sep == "" then for _, c in utf8.codes(s) do o[#o + 1] = utf8.char(c) end return strSlice(o) end
  local i = 1
  while true do
    local a, b = s:find(sep, i, true)
    if not a then break end
    o[#o + 1] = s:sub(i, a - 1)
    i = b + 1
  end
  o[#o + 1] = s:sub(i)
  return strSlice(o)
end
function strings.SplitN(s, sep, n)
  local o = {}
  local i = 1
  while n < 0 or #o < n - 1 do
    local a, b = s:find(sep, i, true)
    if not a then break end
    o[#o + 1] = s:sub(i, a - 1)
    i = b + 1
  end
  o[#o + 1] = s:sub(i)
  return strSlice(o)
end
function strings.Fields(s) local o = {}; for w in s:gmatch("%S+") do o[#o + 1] = w end return strSlice(o) end
function strings.Join(l, sep)
  if l == nil then return "" end
  local o = {}
  for i = 0, l.n - 1 do o[i + 1] = l.a[l.o + i] end
  return concat(o, sep)
end
function strings.Replace(s, a, b, n)
  if a == "" then return s end
  local o, i, c = {}, 1, 0
  while n < 0 or c < n do
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
function strings.ReplaceAll(s, a, b) return strings.Replace(s, a, b, -1) end
function strings.EqualFold(a, b) return a:lower() == b:lower() end
function strings.Compare(a, b) return a < b and -1 or (a > b and 1 or 0) end
function strings.Map(f, s)
  local o = {}
  for _, c in utf8.codes(s) do
    local r = f(c)
    if r >= 0 then o[#o + 1] = utf8.char(r) end
  end
  return concat(o)
end
local Builder = R.newType("Builder")
function R.newBuilder() return setmt({ parts = {} }, Builder) end
function Builder.WriteString(b, s) b.parts[#b.parts + 1] = s; return #s, nil end
function Builder.WriteByte(b, c) b.parts[#b.parts + 1] = string.char(c); return nil end
function Builder.WriteRune(b, c) b.parts[#b.parts + 1] = utf8.char(c); return 1, nil end
function Builder.Write(b, s) b.parts[#b.parts + 1] = R.toString(s); return s.n, nil end
function Builder.String(b) local s = concat(b.parts); b.parts = { s }; return s end
function Builder.Len(b) return #concat(b.parts) end
function Builder.Reset(b) b.parts = {} end
function Builder.Grow() end
local NumError = function(fn, s, why) return newError("strconv." .. fn .. ': parsing "' .. s .. '": ' .. why) end
pkg.strconv = {
  Itoa = function(i) return tostring(i) end,
  Atoi = function(s)
    local v = s:match("^[+-]?%d+$") and math.tointeger(tonumber((s:gsub("^%+", ""))))
    if not v then return 0, NumError("Atoi", s, "invalid syntax") end
    return v, nil
  end,
  ParseFloat = function(s)
    local v = s:find("^[+-]?%d*%.?%d*[eE]?[+-]?%d*$") and tonumber(s)
    if not v then return 0.0, NumError("ParseFloat", s, "invalid syntax") end
    return v + 0.0, nil
  end,
  ParseInt = function(s, base)
    local v = tonumber(s, base ~= 0 and base or 10)
    if not v then return 0, NumError("ParseInt", s, "invalid syntax") end
    return v, nil
  end,
  ParseBool = function(s)
    if s == "true" or s == "1" or s == "t" or s == "T" or s == "TRUE" or s == "True" then return true, nil end
    if s == "false" or s == "0" or s == "f" or s == "F" or s == "FALSE" or s == "False" then return false, nil end
    return false, NumError("ParseBool", s, "invalid syntax")
  end,
  Quote = function(s) return (sfmt("%q", s):gsub("\\\n", "\\n")) end,
  FormatBool = function(b) return tostring(b) end,
  FormatInt = function(v, base)
    if base == 10 then return tostring(v) end
    local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    local neg = v < 0
    if neg then v = -v end
    local o = {}
    if v == 0 then o[1] = "0" end
    while v > 0 do
      local d = v % base
      table.insert(o, 1, digits:sub(d + 1, d + 1))
      v = v // base
    end
    return (neg and "-" or "") .. concat(o)
  end,
  FormatFloat = function(f, fmtc, prec)
    local c = string.char(fmtc)
    if prec < 0 then return floatG(f) end
    return sfmt("%." .. prec .. c, f)
  end,
}
pkg.math = {
  Sqrt = function(x) if x < 0 then return 0 / 0 end return math.sqrt(x) end,
  Pow = function(a, b) return (a + 0.0) ^ b end, Abs = function(x) return math.abs(x + 0.0) end,
  Floor = function(x) if x ~= x or x == math.huge or x == -math.huge then return x end return floor(x) + 0.0 end,
  Ceil = function(x) if x ~= x or x == math.huge or x == -math.huge then return x end return math.ceil(x) + 0.0 end,
  Round = function(x) if x ~= x or x == math.huge or x == -math.huge then return x end return (x >= 0 and floor(x + 0.5) or -floor(-x + 0.5)) + 0.0 end,
  Trunc = function(x) if x ~= x or x == math.huge or x == -math.huge then return x end return (x >= 0 and floor(x) or -floor(-x)) + 0.0 end,
  Sin = math.sin, Cos = math.cos, Tan = math.tan, Asin = math.asin, Acos = math.acos, Atan = function(x) return math.atan(x) end, Atan2 = function(y, x) return math.atan(y, x) end, Exp = math.exp,
  Log = function(x) return math.log(x) end, Log2 = function(x) return math.log(x, 2) end, Log10 = function(x) return math.log(x, 10) end,
  Max = function(a, b) return math.max(a + 0.0, b) end, Min = function(a, b) return math.min(a + 0.0, b) end, Mod = function(a, b) return math.fmod(a + 0.0, b) end,
  Hypot = function(a, b) return math.sqrt(a * a + b * b) end, Cbrt = function(x) return x < 0 and -((-x) ^ (1 / 3)) or x ^ (1 / 3) end,
  Inf = function(s) return s >= 0 and math.huge or -math.huge end, NaN = function() return 0 / 0 end, IsNaN = function(x) return x ~= x end,
  IsInf = function(x, s) if s > 0 then return x == math.huge elseif s < 0 then return x == -math.huge end return x == math.huge or x == -math.huge end,
}
local function sortSlice(s, less)
  local items = {}
  for i = 1, s.n do items[i] = s.a[s.o + i - 1] end
  local b = {}
  local n, w = s.n, 1
  local a = items
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
  for i = 1, n do s.a[s.o + i - 1] = a[i] end
end
local natural = function(x, y) return x < y end
pkg.sort = {
  Ints = function(s) if s then sortSlice(s, natural) end end,
  Strings = function(s) if s then sortSlice(s, natural) end end,
  Float64s = function(s) if s then sortSlice(s, natural) end end,
  Slice = function(s, f)
    if not s then return end
    -- less takes indexes: the values to compare are put into two scratch places at the end of the array
    local a, o, n = s.a, s.o, s.n
    local i1, i2 = n, n + 1
    sortSlice(s, function(x, y)
      local sx, sy = a[o + i1], a[o + i2]
      a[o + i1], a[o + i2] = x, y
      local sn = s.n
      s.n = n + 2
      local r = f(i1, i2)
      s.n = sn
      a[o + i1], a[o + i2] = sx, sy
      return r
    end)
  end,
  SearchInts = function(s, x)
    local a, b = 0, s.n
    while a < b do
      local m = (a + b) // 2
      if s.a[s.o + m] < x then a = m + 1 else b = m end
    end
    return a
  end,
  Search = function(n, f)
    local a, b = 0, n
    while a < b do
      local m = (a + b) // 2
      if not f(m) then a = m + 1 else b = m end
    end
    return a
  end,
  Sort = function(x)
    local n = x:Len()
    for i = 1, n - 1 do
      local j = i
      while j > 0 and x:Less(j, j - 1) do x:Swap(j, j - 1); j = j - 1 end
    end
  end,
}
pkg.sort.SliceStable = pkg.sort.Slice
pkg.sort.Stable = pkg.sort.Sort
pkg.slices = {
  Sort = function(s) if s then sortSlice(s, natural) end end,
  Contains = function(s, x) if s then for i = 0, s.n - 1 do if s.a[s.o + i] == x then return true end end end return false end,
  Index = function(s, x) if s then for i = 0, s.n - 1 do if s.a[s.o + i] == x then return i end end end return -1 end,
  Reverse = function(s) local i, j = 0, s.n - 1; while i < j do s.a[s.o + i], s.a[s.o + j] = s.a[s.o + j], s.a[s.o + i]; i = i + 1; j = j - 1 end end,
  Max = function(s) local m = s.a[s.o]; for i = 1, s.n - 1 do if s.a[s.o + i] > m then m = s.a[s.o + i] end end return m end,
  Min = function(s) local m = s.a[s.o]; for i = 1, s.n - 1 do if s.a[s.o + i] < m then m = s.a[s.o + i] end end return m end,
}
pkg.errors = {
  New = function(s) return newError(s) end,
  Is = function(e, t)
    while e ~= nil do
      if e == t then return true end
      if type_(e) == "table" and e.Unwrap then e = e:Unwrap() else return false end
    end
    return t == nil
  end,
  Unwrap = function(e) if type_(e) == "table" and e.Unwrap then return e:Unwrap() end return nil end,
  As = function(e, target)
    while e ~= nil do
      if getmt(e) == getmt(target.v) or target.v == nil then target.v = e; return true end
      if type_(e) == "table" and e.Unwrap then e = e:Unwrap() else return false end
    end
    return false
  end,
}
-- files: a handle of the io library
local File = R.newType("File")
function File.Close(f) if f.h then f.h:close() end return nil end
function File.WriteString(f, t) f.h:write(t); return #t, nil end
function File.Write(f, b) local t = type_(b) == "string" and b or R.toString(b); f.h:write(t); return #t, nil end
function File.Name(f) return f.name end
function File.Sync() return nil end
function File.Stat(f) return pkg.os.Stat(f.name) end
function File.ReadString(f, d) local l = f.h:read("L"); if not l then return "", pkg.io.EOF end return l, nil end
local function wrapFile(h, name) return setmt({ h = h, name = name }, File) end
pkg.io = { EOF = newError("EOF"), ErrUnexpectedEOF = newError("unexpected EOF") }
pkg.io.ReadAll = function(r)
  if r.h then return R.bytes(r.h:read("a") or ""), nil end
  return R.bytes(""), nil
end
pkg.io.WriteString = function(w, t) fileWriter(w, t); return #t, nil end
pkg.ioutil = { ReadAll = pkg.io.ReadAll }
-- bufio
local Scanner = R.newType("Scanner")
function Scanner.Scan(c)
  local l
  if c.words then
    while not (c.buf and c.buf[c.at]) do
      local line = c.h:read("l")
      if not line then return false end
      c.buf, c.at = {}, 1
      for w in line:gmatch("%S+") do c.buf[#c.buf + 1] = w end
    end
    c.text = c.buf[c.at]
    c.at = c.at + 1
    return true
  end
  l = c.h:read("l")
  if not l then return false end
  c.text = l:gsub("\r$", "")
  return true
end
function Scanner.Text(c) return c.text end
function Scanner.Bytes(c) return R.bytes(c.text) end
function Scanner.Err() return nil end
function Scanner.Buffer() end
function Scanner.Split(c, f) if f == pkg.bufio.ScanWords then c.words = true end end
local Reader = R.newType("Reader")
function Reader.ReadString(r)
  local l = r.h:read("L")
  if not l then return "", pkg.io.EOF end
  return l, nil
end
function Reader.ReadLine(r) local l = r.h:read("l"); if not l then return nil, false, pkg.io.EOF end return R.bytes(l), false, nil end
function Reader.ReadByte(r) local c = r.h:read(1); if not c then return 0, pkg.io.EOF end return c:byte(), nil end
local Writer = R.newType("Writer")
function Writer.WriteString(w, t) w.buf[#w.buf + 1] = t; return #t, nil end
function Writer.Write(w, b) local t = type_(b) == "string" and b or R.toString(b); w.buf[#w.buf + 1] = t; return #t, nil end
function Writer.WriteByte(w, c) w.buf[#w.buf + 1] = string.char(c); return nil end
function Writer.WriteRune(w, c) w.buf[#w.buf + 1] = utf8.char(c); return 1, nil end
function Writer.Flush(w) fileWriter(w.to, table.concat(w.buf)); w.buf = {}; return nil end
pkg.bufio = {
  ScanLines = "lines", ScanWords = "words",
  NewScanner = function(r) return setmt({ h = r.h or io.stdin }, Scanner) end,
  NewReader = function(r) return setmt({ h = r.h or io.stdin }, Reader) end,
  NewWriter = function(w) return setmt({ to = w, buf = {} }, Writer) end,
}
-- flag
local flags = {}
local flagRest = {}
local function addFlag(name, value, usage, kind)
  local p = { v = value }
  flags[name] = { p = p, kind = kind, usage = usage, def = value }
  return p
end
pkg.flag = {
  Int = function(n, d, u) return addFlag(n, d, u, "int") end,
  Int64 = function(n, d, u) return addFlag(n, d, u, "int") end,
  Uint = function(n, d, u) return addFlag(n, d, u, "int") end,
  Float64 = function(n, d, u) return addFlag(n, d, u, "float") end,
  String = function(n, d, u) return addFlag(n, d, u, "string") end,
  Bool = function(n, d, u) return addFlag(n, d, u, "bool") end,
  Duration = function(n, d, u) return addFlag(n, d, u, "int") end,
  IntVar = function(p, n, d, u) p.v = d; flags[n] = { p = p, kind = "int", usage = u, def = d } end,
  StringVar = function(p, n, d, u) p.v = d; flags[n] = { p = p, kind = "string", usage = u, def = d } end,
  BoolVar = function(p, n, d, u) p.v = d; flags[n] = { p = p, kind = "bool", usage = u, def = d } end,
  Float64Var = function(p, n, d, u) p.v = d; flags[n] = { p = p, kind = "float", usage = u, def = d } end,
  PrintDefaults = function()
    local names = {}
    for k in pairs(flags) do names[#names + 1] = k end
    table.sort(names)
    for _, k in ipairs(names) do
      local f = flags[k]
      io.stderr:write("  -" .. k .. (f.kind ~= "bool" and (" " .. f.kind) or "") .. "\n    \t" .. tostring(f.usage) .. "\n")
    end
  end,
  Parse = function()
    local a = R.rawArgs or {}
    flagRest = {}
    local i = 2
    while i <= #a do
      local w = a[i]
      if w == "--" then
        for k = i + 1, #a do flagRest[#flagRest + 1] = a[k] end
        break
      end
      local name, val = w:match("^%-%-?([%w_.-]+)=(.*)$")
      if not name then name = w:match("^%-%-?([%w_.-]+)$") end
      if not name or w == "-" then
        for k = i, #a do flagRest[#flagRest + 1] = a[k] end
        break
      end
      if name == "h" or name == "help" then
        if pkg.flag.Usage then pkg.flag.Usage() else io.stderr:write("Usage of " .. tostring(a[1]) .. ":\n"); pkg.flag.PrintDefaults() end
        error({ exit = 0 }, 0)
      end
      local f = flags[name]
      if not f then
        io.stderr:write("flag provided but not defined: -" .. name .. "\nUsage of " .. tostring(a[1]) .. ":\n")
        pkg.flag.PrintDefaults()
        error({ exit = 2 }, 0)
      end
      if f.kind == "bool" then
        f.p.v = val == nil or val == "true" or val == "1"
      else
        if val == nil then
          i = i + 1
          val = a[i]
          if val == nil then
            io.stderr:write("flag needs an argument: -" .. name .. "\n")
            error({ exit = 2 }, 0)
          end
        end
        if f.kind == "int" then
          local v = math.tointeger(tonumber(val))
          if not v then
            io.stderr:write("invalid value \"" .. val .. "\" for flag -" .. name .. "\n")
            error({ exit = 2 }, 0)
          end
          f.p.v = v
        elseif f.kind == "float" then f.p.v = (tonumber(val) or 0) + 0.0
        else f.p.v = val end
      end
      i = i + 1
    end
  end,
  NArg = function() return #flagRest end,
  Arg = function(i) return flagRest[i + 1] or "" end,
  Args = function() return R.sliceFrom(table.unpack(flagRest)) end,
  NFlag = function() return 0 end,
}
-- regexp, with the engine of the other languages
local Regexp = R.newType("Regexp")
local reEngine
local function reCompile(p)
  reEngine = reEngine or driver.load("relang")
  local tree, groups = reEngine.parse(p)
  return setmt({ tree = tree, src = p, groups = groups or 0 }, Regexp)
end
local function reFind(r, t, from)
  from = from or 1
  for at = from, #t + 1 do
    local e, caps = reEngine.exec(r.tree, t, at, 0)
    if e then return at, e, caps end
  end
end
function Regexp.MatchString(r, t) return reFind(r, t) ~= nil end
function Regexp.String(r) return r.src end
function Regexp.FindString(r, t) local a, e = reFind(r, t); if a then return t:sub(a, e - 1) end return "" end
function Regexp.FindStringIndex(r, t) local a, e = reFind(r, t); if a then return R.sliceFrom(a - 1, e - 1) end return nil end
function Regexp.FindStringSubmatch(r, t)
  local a, e, caps = reFind(r, t)
  if not a then return nil end
  local o = { t:sub(a, e - 1) }
  for k = 1, r.groups do
    local c = caps and caps[k]
    o[#o + 1] = c and t:sub(c[1], c[2]) or ""
  end
  return R.sliceFrom(table.unpack(o))
end
function Regexp.FindAllString(r, t, lim)
  local o, at = {}, 1
  while at <= #t + 1 and (not lim or lim < 0 or #o < lim) do
    local a, e = reFind(r, t, at)
    if not a then break end
    o[#o + 1] = t:sub(a, e - 1)
    at = e > a and e or e + 1
  end
  return R.sliceFrom(table.unpack(o))
end
function Regexp.ReplaceAllString(r, t, rep)
  local o, at = {}, 1
  while at <= #t + 1 do
    local a, e = reFind(r, t, at)
    if not a then break end
    o[#o + 1] = t:sub(at, a - 1) .. rep
    if e == a then o[#o + 1] = t:sub(a, a); at = a + 1 else at = e end
  end
  o[#o + 1] = t:sub(at)
  return table.concat(o)
end
pkg.regexp = {
  MustCompile = reCompile,
  Compile = function(p) local ok, r = pcall(reCompile, p); if ok then return r, nil end return nil, newError("error parsing regexp: " .. tostring(r)) end,
  MatchString = function(p, t) return Regexp.MatchString(reCompile(p), t), nil end,
  QuoteMeta = function(t) return (t:gsub("[%^%$%(%)%.%[%]%*%+%-%?{}|\\]", "\\%0")) end,
}
-- paths
pkg.filepath = {
  Join = function(...)
    local o = {}
    for _, p in ipairs{ ... } do if p ~= "" then o[#o + 1] = p end end
    return ((table.concat(o, "/"):gsub("/+", "/")))
  end,
  Base = function(p) p = p:gsub("/+$", ""); return p:match("([^/]*)$") end,
  Dir = function(p) local d = p:match("^(.*)/[^/]*$"); if d == "" then return "/" end return d or "." end,
  Ext = function(p) return p:match("(%.[^./]*)$") or "" end,
  IsAbs = function(p) return p:sub(1, 1) == "/" end,
  Abs = function(p) if p:sub(1, 1) == "/" then return p, nil end return lfs.currentdir() .. "/" .. p, nil end,
  Clean = function(p) return p end,
}
pkg.path = pkg.filepath
pkg.os = {
  Stdin = R.stdin, Stdout = R.stdout, Stderr = R.stderr,
  Exit = function(c) error({ exit = c }, 0) end,
  Getenv = function(k) return os.getenv(k) or "" end,
  Setenv = function(k, v) if os.setenv then os.setenv(k, v) end return nil end,
  Open = function(p)
    local h, e = io.open(p, "r")
    if not h then return nil, newError("open " .. p .. ": no such file or directory") end
    return wrapFile(h, p), nil
  end,
  Create = function(p)
    local h, e = io.open(p, "w")
    if not h then return nil, newError("open " .. p .. ": " .. tostring(e):gsub("^.*: ", "")) end
    return wrapFile(h, p), nil
  end,
  Remove = function(p) local ok, e = os.remove(p); if ok then return nil end return newError("remove " .. p .. ": no such file or directory") end,
  Rename = function(a, b) local ok = os.rename(a, b); if ok then return nil end return newError("rename " .. a .. ": no such file or directory") end,
  Mkdir = function(p) local ok, e = lfs.mkdir(p); if ok then return nil end return newError("mkdir " .. p .. ": " .. tostring(e)) end,
  MkdirAll = function(p)
    local at = p:sub(1, 1) == "/" and "" or nil
    for part in p:gmatch("[^/]+") do
      at = at and (at .. "/" .. part) or part
      if not lfs.attributes(at) then lfs.mkdir(at) end
    end
    return nil
  end,
  Getwd = function() return lfs.currentdir(), nil end,
  Chdir = function(p) local ok = lfs.chdir(p); if ok then return nil end return newError("chdir " .. p .. ": no such file or directory") end,
  Hostname = function() return sys and sys.hostname and sys.hostname() or "esp", nil end,
  Getpid = function() return 1 end,
  IsNotExist = function(e) return e ~= nil and tostring(R.callMethod(e, "Error")):find("no such", 1, true) ~= nil end,
  Stat = function(p)
    local a = lfs.attributes(p)
    if not a then return nil, newError("stat " .. p .. ": no such file or directory") end
    return setmt({ a = a, name = p }, R.FileInfo), nil
  end,
  ReadDir = function(p)
    if not lfs.attributes(p) then return nil, newError("open " .. p .. ": no such file or directory") end
    local names = {}
    for n in lfs.dir(p) do if n ~= "." and n ~= ".." then names[#names + 1] = n end end
    table.sort(names)
    local o = {}
    for i, n in ipairs(names) do o[i] = setmt({ a = lfs.attributes(p .. "/" .. n) or {}, name = n }, R.FileInfo) end
    return R.sliceFrom(table.unpack(o)), nil
  end,
  ReadFile = function(p)
    local s = fs.read(p)
    if not s then return nil, newError("open " .. p .. ": no such file or directory") end
    return R.bytes(s), nil
  end,
  WriteFile = function(p, d)
    fs.write(p, type_(d) == "string" and d or R.toString(d))
    return nil
  end,
  Remove = function(p) fs.remove(p); return nil end,
}
local TimeT = {}
function R.timeMethod(t, n)
  if n == "Unix" then return floor(t.ms / 1000) end
  if n == "UnixMilli" then return floor(t.ms) end
  if n == "UnixNano" then return floor(t.ms * 1e6) end
  return 0
end
local function nowMs() return (sys and sys.millis and sys.millis() or 0) + clock end
pkg.time = {
  Sleep = function(ns) R.sleepNs(ns) end,
  Now = function() return { ms = nowMs() } end,
  Since = function(t) return (nowMs() - t.ms) * 1000000 // 1 end,
  After = function(ns)
    local c = R.chan(1, function() return nil end)
    R.go(function() R.sleepNs(ns); R.send(c, { ms = nowMs() }) end)
    return c
  end,
  Tick = function(ns)
    local c = R.chan(1, function() return nil end)
    R.go(function() while true do R.sleepNs(ns); R.send(c, { ms = nowMs() }) end end)
    return c
  end,
}
pkg.rand = {
  Intn = function(n) return math.random(0, n - 1) end, Int = function() return math.random(0, math.maxinteger) end, Float64 = function() return math.random() end,
  Seed = function(s) math.randomseed(s) end, Perm = function(n)
    local a = {}
    for i = 0, n - 1 do a[i] = i end
    for i = n - 1, 1, -1 do local j = math.random(0, i); a[i], a[j] = a[j], a[i] end
    return mk(a, 0, n, n)
  end,
  Shuffle = function(n, f) for i = n - 1, 1, -1 do f(i, math.random(0, i)) end end,
}
local function runeTest(p) return function(r) return r < 128 and string.char(r):find(p) ~= nil end end
pkg.unicode = { IsDigit = runeTest("%d"), IsLetter = function(r) return r >= 128 or string.char(r):find("%a") ~= nil end, IsSpace = runeTest("%s"), IsUpper = runeTest("%u"), IsLower = runeTest("%l"), IsPunct = runeTest("%p"),
  ToUpper = function(r) if r >= 97 and r <= 122 then return r - 32 end return r end, ToLower = function(r) if r >= 65 and r <= 90 then return r + 32 end return r end }
pkg.utf8 = { RuneCountInString = function(s) return utf8.len(s) or #s end, RuneLen = function(r) return #utf8.char(r) end }
local WG = R.newType("WaitGroup")
function R.newWaitGroup() return setmt({ n = 0, q = {} }, WG) end
function WG.Add(w, d) w.n = w.n + d end
function WG.Done(w)
  w.n = w.n - 1
  if w.n <= 0 then for _, g in ipairs(w.q) do wake(g) end w.q = {} end
end
function WG.Wait(w) if w.n > 0 then w.q[#w.q + 1] = current; park() end end
local Mu = R.newType("Mutex")
function R.newMutex() return setmt({ locked = false, q = {} }, Mu) end
function Mu.Lock(m)
  if m.locked then m.q[#m.q + 1] = current; park() else m.locked = true end
end
function Mu.Unlock(m)
  local g = table.remove(m.q, 1)
  if g then wake(g) else m.locked = false end
end
Mu.RLock, Mu.RUnlock = Mu.Lock, Mu.Unlock
pkg.sync = {}

function R.run(text, args)
  local G = {}
  R.args = strSlice(args)
  R.rawArgs = args
  local env = setmt({ R = R, G = G }, { __index = _G })
  local f, e = load(text, "=program", "t", env)
  if not f then
    write("internal error: " .. tostring(e) .. "\n")
    return 1
  end
  local ok, res = pcall(function()
    local mainF = f()
    runAll(mainF)
  end)
  if ok then return 0 end
  if type_(res) == "table" and res.exit then return res.exit end
  if getmt(res) == PanicMt then
    if res.fatal then write(res.fatal .. "\n"); return 2 end
    local v = res.v
    local text2
    if type_(v) == "table" and getmt(v) == R.RuntimeErr then text2 = v.msg
    elseif type_(v) == "table" and v.Error then text2 = v:Error()
    elseif type_(v) == "string" then text2 = v
    else text2 = typeName(v) .. "(" .. vText(v) .. ")" end
    write("panic: " .. text2 .. "\n\ngoroutine 1 [running]:\nexit status 2\n")
    return 2
  end
  if type_(res) == "string" and res:find("interrupted", 1, true) then error(res, 0) end
  write("panic: " .. tostring(res):gsub("^program:%d+: ", "") .. "\n")
  return 2
end
return R
