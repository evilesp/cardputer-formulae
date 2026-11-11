#!lua
-- htmljs: the page engine of the html player. It loads a page (a file of the card or a web address), its style sheets and scripts, and runs
-- the JavaScript (translated by jslang, run by jsrt) in a sandbox with a DOM: document, elements, events, timers, requestAnimationFrame,
-- fetch, localStorage, location, history, alert, console and the 2D context of <canvas>. The screen and the keys are the program's (html.lua);
-- this file only knows the page.
--   local H = driver.load("htmljs")
--   local page = H.new(host)      host = { vw, vh, read(url) -> text | nil, err, log(line), alert(kind, text, value) -> answer, fontOf, measure,
--                                          fontHeight, intrinsic(node, url), storage(origin) -> path, now() -> ms }
--   page:load(url) ; page:tick(now) ; page:key(name) ; page:down(x, y) ; page:move(x, y) ; page:up(x, y) ; page:layout() ; page:paint(api, rect)
local H = {}
-- the drivers of the player are loaded once and shared (driver.load makes a new copy each time)
local function need(name)
  local reg = rawget(_G, "HTML_DRIVERS") or {}
  rawset(_G, "HTML_DRIVERS", reg)
  if not reg[name] then reg[name] = assert(driver.load(name)) end
  return reg[name]
end
local D = need("htmldom")
local C = need("htmlcss")
local L = need("htmllayout")
local P = need("htmlpaint")
local J = need("jslang")
local R = need("jsrt")
local G = R.globals
local null = R.null
local floor, max, min = math.floor, math.max, math.min

R.compiler = J.compile
R.reEngine = R.reEngine or need("relang")

-- the metatable jsrt uses for getters and setters (taken from an object made with one)
local AccMt = getmetatable(rawget(R.obj({ { k = "x", get = function() end } }), "x"))
local function accessor(get, set) return setmetatable({ get = get, set = set }, AccMt) end
local function native(name, f) return R.fn(f, name) end
local function obj(fields)
  local o = R.obj({})
  if fields then for _, kv in ipairs(fields) do R.set(o, kv[1], kv[2]) end end
  return o
end
local function str(v)
  if v == nil then return "undefined" end
  if type(v) == "string" then return v end
  return R.tostr(v)
end
local function num(v) return R.num(v) end
local function arr(t) return R.array(t) end

-- ---------------------------------------------------------------- URLs
function H.resolve(base, rel)
  rel = rel or ""
  rel = rel:gsub("^%s+", ""):gsub("%s+$", "")
  if rel:find("^%a[%w+.-]*:") then
    if rel:find("^file://") then return (rel:gsub("^file://", "")) end
    return rel
  end
  base = base or ""
  local scheme, host = base:match("^(%a[%w+.-]*://)([^/]*)")
  if rel:sub(1, 2) == "//" then return (scheme and scheme:match("^(%a+:)") or "https:") .. rel end
  if rel == "" then return base end
  if rel:sub(1, 1) == "#" then return (base:gsub("#.*$", "")) .. rel end
  local path, prefix
  if scheme then
    prefix = scheme .. host
    path = base:sub(#prefix + 1):gsub("[?#].*$", "")
    if path == "" then path = "/" end
  else
    prefix = ""
    path = base:gsub("[?#].*$", "")
  end
  local dir
  if rel:sub(1, 1) == "/" then dir, rel = "", rel:sub(2)
  elseif rel:sub(1, 1) == "?" then return prefix .. path .. rel
  else dir = path:match("^(.*)/[^/]*$") or (scheme and "" or ".") end
  local parts = {}
  for p in (dir .. "/" .. rel):gmatch("[^/]+") do
    if p == ".." then if #parts > 0 and parts[#parts] ~= ".." then parts[#parts] = nil elseif not scheme and dir:sub(1, 1) ~= "/" then parts[#parts + 1] = ".." end
    elseif p ~= "." then parts[#parts + 1] = p end
  end
  local joined = table.concat(parts, "/")
  if rel:sub(-1) == "/" and joined ~= "" then joined = joined .. "/" end
  if scheme then return prefix .. "/" .. joined end
  if (dir:sub(1, 1) == "/" or dir == "") then return "/" .. joined end
  return joined
end

-- ---------------------------------------------------------------- the page object
local Page = {}
Page.__index = Page
local current -- the page whose scripts run now (one at a time)

local W2N = setmetatable({}, { __mode = "k" })  -- wrapper -> node
local wrap
local ElemMt, DocMt

-- names of JS properties <-> CSS
local function kebab(k)
  if k:sub(1, 2) == "--" then return k end
  local s = k:gsub("(%u)", function(c) return "-" .. c:lower() end)
  if s:sub(1, 7) == "webkit-" then s = "-" .. s end
  if k == "cssFloat" then return "float" end
  return s
end
local function camel(k) return (k:gsub("%-(%l)", function(c) return c:upper() end)) end

-- ---------------------------------------------------------------- changes of the tree
local function changed(match)
  local p = current
  if not p then return end
  if match then p.needMatch = true end
  p.needStyle = true
end
local function runScriptNode(p, n) end -- set below

local function connected(n)
  while n do
    if n.type == "doc" then return true end
    n = n.parent
  end
  return false
end
local function insertNode(parent, child, ref)
  if child.type == "doc" then R.throw(R.new(G.Error, "HierarchyRequestError")) end
  if D.contains(child, parent) then R.throw(R.new(G.Error, "HierarchyRequestError: The new child element contains the parent.")) end
  local list = child.type == "frag" and { table.unpack(child.kids) } or { child }
  D.insert(parent, child, ref)
  changed(true)
  -- a <script> put into the document runs (once)
  if current and connected(parent) then
    for _, k in ipairs(list) do
      if k.type == "el" then
        local scripts = k.tag == "script" and { k } or D.byTag(k, "script")
        for _, s in ipairs(scripts) do runScriptNode(current, s) end
        if k.tag == "canvas" or #D.byTag(k, "img") > 0 then current.needImages = true end
      end
    end
  end
end

-- ---------------------------------------------------------------- inline style objects
local function inlineMap(n)
  local src = n.attrs.style or ""
  if n._inl and n._inl.src == src then return n._inl end
  local m = { src = src, order = {}, map = {} }
  for _, d in ipairs(C.splitTop(src, ";")) do
    local k, v = d:match("^%s*([%-%w]+)%s*:%s*(.-)%s*$")
    if k then
      if k:sub(1, 2) ~= "--" then k = k:lower() end
      if m.map[k] == nil then m.order[#m.order + 1] = k end
      m.map[k] = v
    end
  end
  n._inl = m
  return m
end
local function writeInline(n, m)
  local parts = {}
  for _, k in ipairs(m.order) do if m.map[k] then parts[#parts + 1] = k .. ": " .. m.map[k] end end
  local s = table.concat(parts, "; ")
  if s == "" then D.removeAttr(n, "style") else D.setAttr(n, "style", s) end
  m.src = n.attrs.style or ""
  changed(false)
end
local function setStyleProp(n, k, v)
  local m = inlineMap(n)
  k = kebab(k)
  if v == nil or v == null or v == "" then
    m.map[k] = nil
    for i, x in ipairs(m.order) do if x == k then table.remove(m.order, i); break end end
  else
    if m.map[k] == nil then m.order[#m.order + 1] = k end
    v = str(v)
    -- a number for a length means px only for 0 (as browsers ignore the rest); a few properties take plain numbers
    m.map[k] = v
  end
  writeInline(n, m)
end
local StyleMt = {}
local styleAcc = {}
local STYLE_METHODS = {
  setProperty = native("setProperty", function(this, k, v) setStyleProp(W2N[this], str(k), v) end),
  getPropertyValue = native("getPropertyValue", function(this, k) return inlineMap(W2N[this]).map[kebab(str(k))] or "" end),
  removeProperty = native("removeProperty", function(this, k) local n = W2N[this]; local old = inlineMap(n).map[kebab(str(k))]; setStyleProp(n, str(k), nil); return old or "" end),
}
StyleMt.__index = function(w, k)
  if type(k) ~= "string" then return nil end
  local m = STYLE_METHODS[k]
  if m then return m end
  if k == "cssText" then
    return styleAcc.cssText or accessor(function(o) return W2N[o].attrs.style or "" end,
      function(o, v) local n = W2N[o]; D.setAttr(n, "style", str(v)); n._inl = nil; changed(false) end)
  end
  local a = styleAcc[k]
  if not a then
    a = accessor(function(o) return inlineMap(W2N[o]).map[kebab(k)] or "" end, function(o, v) setStyleProp(W2N[o], k, v) end)
    styleAcc[k] = a
  end
  return a
end
local function styleOf(n)
  if not n._style then
    local s = setmetatable({}, StyleMt)
    W2N[s] = n
    n._style = s
  end
  return n._style
end

-- classList and dataset
local ClassMt = {}
local function classes(n)
  local t = {}
  for w in (n.attrs.class or ""):gmatch("%S+") do t[#t + 1] = w end
  return t
end
local function setClasses(n, t)
  D.setAttr(n, "class", table.concat(t, " "))
  changed(true)
end
local CLASS_METHODS = {
  add = native("add", function(this, ...)
    local n = W2N[this]; local t = classes(n)
    for _, c in ipairs({ ... }) do c = str(c); local has = false; for _, x in ipairs(t) do if x == c then has = true end end if not has then t[#t + 1] = c end end
    setClasses(n, t)
  end),
  remove = native("remove", function(this, ...)
    local n = W2N[this]; local t = classes(n)
    for _, c in ipairs({ ... }) do c = str(c); for i = #t, 1, -1 do if t[i] == c then table.remove(t, i) end end end
    setClasses(n, t)
  end),
  toggle = native("toggle", function(this, c, force)
    local n = W2N[this]; local t = classes(n); c = str(c)
    local at
    for i, x in ipairs(t) do if x == c then at = i end end
    local want = not at
    if force ~= nil then want = R.T(force) end
    if want and not at then t[#t + 1] = c elseif not want and at then table.remove(t, at) end
    setClasses(n, t)
    return want
  end),
  contains = native("contains", function(this, c) c = str(c); for _, x in ipairs(classes(W2N[this])) do if x == c then return true end end return false end),
  replace = native("replace", function(this, a, b)
    local n = W2N[this]; local t = classes(n)
    for i, x in ipairs(t) do if x == str(a) then t[i] = str(b); setClasses(n, t); return true end end
    return false
  end),
  item = native("item", function(this, i) return classes(W2N[this])[floor(num(i)) + 1] or null end),
  forEach = native("forEach", function(this, f) for i, c in ipairs(classes(W2N[this])) do f(nil, c, i - 1.0) end end),
}
local classLen = accessor(function(o) return #classes(W2N[o]) + 0.0 end)
local classValue = accessor(function(o) return W2N[o].attrs.class or "" end, function(o, v) D.setAttr(W2N[o], "class", str(v)); changed(true) end)
ClassMt.__index = function(_, k)
  if k == "length" then return classLen end
  if k == "value" then return classValue end
  return CLASS_METHODS[k]
end
local function classListOf(n)
  if not n._cl then local c = setmetatable({}, ClassMt); W2N[c] = n; n._cl = c end
  return n._cl
end
local DataMt = {}
local dataAcc = {}
DataMt.__index = function(_, k)
  if type(k) ~= "string" then return nil end
  local a = dataAcc[k]
  if not a then
    local attr = "data-" .. kebab(k)
    a = accessor(function(o) return W2N[o].attrs[attr] end, function(o, v) D.setAttr(W2N[o], attr, str(v)); changed(true) end)
    dataAcc[k] = a
  end
  return a
end
local function datasetOf(n)
  if not n._ds then local d = setmetatable({}, DataMt); W2N[d] = n; n._ds = d end
  return n._ds
end

-- ---------------------------------------------------------------- events
local NOBUBBLE = { focus = true, blur = true, load = true, mouseenter = true, mouseleave = true, scroll = false, DOMContentLoaded = false }
local EVENT_METHODS = {
  preventDefault = native("preventDefault", function(this) if R.get(this, "cancelable") ~= false then R.set(this, "defaultPrevented", true) end end),
  stopPropagation = native("stopPropagation", function(this) rawset(this, "\0stop", true) end),
  stopImmediatePropagation = native("stopImmediatePropagation", function(this) rawset(this, "\0stop", true); rawset(this, "\0stopNow", true) end),
  composedPath = native("composedPath", function(this) return arr({}) end),
}
local function newEvent(kind, init)
  local e = obj()
  R.set(e, "type", kind)
  R.set(e, "bubbles", not NOBUBBLE[kind])
  R.set(e, "cancelable", true)
  R.set(e, "defaultPrevented", false)
  R.set(e, "timeStamp", (current and current:now() or 0) + 0.0)
  R.set(e, "isTrusted", true)
  for k, f in pairs(EVENT_METHODS) do rawset(e, k, f) end
  if init then for k, v in pairs(init) do R.set(e, k, v) end end
  return e
end
H.newEvent = newEvent

local function report(p, prefix, e)
  local msg
  if type(e) == "table" and e.syntax then msg = "SyntaxError: " .. tostring(e.syntax) .. " (line " .. tostring(e.line) .. ")"
  else
    local ok, v = pcall(R.catch, e)
    if ok then
      local ok2, s = pcall(function()
        if type(v) == "table" and v ~= null then
          local m = R.get(v, "message")
          local nm = R.get(v, "name")
          if m ~= nil then return str(nm or "Error") .. ": " .. str(m) end
        end
        return R.inspect(v)
      end)
      msg = ok2 and s or tostring(e)
    else msg = tostring(e) end
  end
  p:log("[script error: " .. (prefix and (prefix .. ": ") or "") .. msg .. "]", true)
end
-- calls a JS function F with THIS and the arguments, catching what it throws
local function callJS(p, f, this, ...)
  local ok, r = pcall(f, this, ...)
  if not ok then
    if type(r) == "string" and r:find("interrupted", 1, true) then error(r, 0) end
    report(p, nil, r)
    return nil
  end
  return r
end
H.callJS = callJS
local function drain(p)
  local ok, e = pcall(R.runOne)
  if not ok then report(p, "promise", e) end
end

-- an inline handler (onclick="...") made into a function, kept while the attribute text stays the same
local function attrHandler(p, n, name)
  local code = n.attrs and n.attrs[name]
  if not code or code == "" then return nil end
  n._h = n._h or {}
  local h = n._h[name]
  if h and h.src == code then return h.f end
  local f = p:compileHandler(code, name)
  n._h[name] = { src = code, f = f }
  return f
end

-- sends the event E to the node N and its parents (and the document and the window); returns false when the default was prevented
local function fire(p, n, e)
  local path = {}
  local x = n
  while x do path[#path + 1] = x; x = x.parent end
  if n ~= p.win then path[#path + 1] = p.win end
  R.set(e, "target", wrap(n))
  R.set(e, "srcElement", wrap(n))
  local kind = R.get(e, "type")
  local bubbles = R.get(e, "bubbles")
  for i, t in ipairs(path) do
    if i > 1 and not bubbles then break end
    local w = wrap(t)
    R.set(e, "currentTarget", w)
    R.set(e, "eventPhase", i == 1 and 2.0 or 3.0)
    local ls = t.listeners and t.listeners[kind]
    if ls then
      local copy = { table.unpack(ls) }
      for _, l in ipairs(copy) do
        if not l.removed then
          local f = l.f
          if type(f) == "table" and f ~= null then
            local he = R.get(f, "handleEvent")
            if type(he) == "function" then callJS(p, he, f, e) end
          elseif type(f) == "function" then callJS(p, f, w, e) end
          if l.once then l.removed = true; for j, m in ipairs(ls) do if m == l then table.remove(ls, j); break end end end
          if rawget(e, "\0stopNow") then break end
        end
      end
    end
    -- the property handler (el.onclick = ...) and the attribute one (onclick="...")
    local ph
    if t == p.win then ph = rawget(p.env, "on" .. kind) elseif type(w) == "table" then ph = rawget(w, "on" .. kind) end
    if type(ph) == "function" then
      local r = callJS(p, ph, w, e)
      if r == false then R.set(e, "defaultPrevented", true) end
    elseif t.attrs and t.type == "el" then
      local ah = attrHandler(p, t, "on" .. kind)
      if t.tag == "body" and (kind == "load" or kind == "resize") then ah = nil end
      if t == p.win and (kind == "load") then ah = p.doc.body and attrHandler(p, p.doc.body, "onload") end
      if ah then
        local r = callJS(p, ah, w, e)
        if r == false then R.set(e, "defaultPrevented", true) end
      end
    elseif t == p.win and kind == "load" and p.doc.body then
      local ah = attrHandler(p, p.doc.body, "onload")
      if ah then callJS(p, ah, w, e) end
    end
    if rawget(e, "\0stop") then break end
  end
  drain(p)
  return R.get(e, "defaultPrevented") ~= true
end
H.fire = fire
local function hasListeners(p, kinds)
  local found = false
  local function check(n)
    if n.listeners then for _, k in ipairs(kinds) do if n.listeners[k] and #n.listeners[k] > 0 then found = true end end end
    if n.attrs then for _, k in ipairs(kinds) do if n.attrs["on" .. k] then found = true end end end
    if n.js then for _, k in ipairs(kinds) do if type(rawget(n.js, "on" .. k)) == "function" then found = true end end end
    if n == p.win then for _, k in ipairs(kinds) do if type(rawget(p.env, "on" .. k)) == "function" then found = true end end end
  end
  check(p.win)
  check(p.doc)
  D.walk(p.doc, function(e) check(e); return found end)
  return found
end

-- ---------------------------------------------------------------- the 2D context of <canvas>
local CtxProto = {}
local CtxMt = { __index = CtxProto }
local colorCache = {}
local function paintColor(v)
  if type(v) == "table" and v ~= null then
    local stops = rawget(v, "\0stops")
    if stops and stops[1] then v = stops[1][2] else return 0, 1 end
  end
  v = str(v)
  local c = colorCache[v]
  if not c then
    local col, a = C.color(v)
    c = { col or 0, a or 1 }
    colorCache[v] = c
  end
  return c[1], c[2]
end
local function cstate(ctx) return rawget(ctx, "\0st") end
local function tx(st, x, y)
  local m = st.m
  return m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
end
local function pushOp(ctx, op)
  local n = W2N[ctx]
  local ops = n.canvasOps
  ops[#ops + 1] = op
  if #ops > 6000 then table.move(ops, 2001, #ops, 1); for i = #ops - 1999, #ops do ops[i] = nil end end
  if current then current.canvasDirty[n] = true end
end
local function fontOfCanvas(ctx)
  local f = str(R.get(ctx, "font") or "10px sans-serif")
  local px = tonumber(f:match("([%d%.]+)px")) or (tonumber(f:match("([%d%.]+)pt")) and tonumber(f:match("([%d%.]+)pt")) * 4 / 3) or 10
  local bold = f:find("bold") ~= nil or (tonumber(f:match("^%s*(%d00)%s")) or 400) >= 600
  return px, bold, f:find("mono") ~= nil
end
local function ctxMethod(name, f) CtxProto[name] = native(name, f) end
local function alphaOf(ctx, a) return (a or 1) * num(R.get(ctx, "globalAlpha") or 1) end
ctxMethod("save", function(this)
  local st = cstate(this)
  local copy = { m = { table.unpack(st.m) } }
  for _, k in ipairs({ "fillStyle", "strokeStyle", "lineWidth", "font", "textAlign", "textBaseline", "globalAlpha", "lineCap", "lineJoin" }) do copy[k] = R.get(this, k) end
  st.stack[#st.stack + 1] = copy
end)
ctxMethod("restore", function(this)
  local st = cstate(this)
  local s = table.remove(st.stack)
  if not s then return end
  st.m = s.m
  for k, v in pairs(s) do if k ~= "m" then R.set(this, k, v) end end
end)
local function mul(st, a, b, c, d, e, f)
  local m = st.m
  st.m = { m[1] * a + m[3] * b, m[2] * a + m[4] * b, m[1] * c + m[3] * d, m[2] * c + m[4] * d, m[1] * e + m[3] * f + m[5], m[2] * e + m[4] * f + m[6] }
end
ctxMethod("translate", function(this, x, y) mul(cstate(this), 1, 0, 0, 1, num(x), num(y)) end)
ctxMethod("scale", function(this, x, y) mul(cstate(this), num(x), 0, 0, num(y or x), 0, 0) end)
ctxMethod("rotate", function(this, a) a = num(a); local c, s = math.cos(a), math.sin(a); mul(cstate(this), c, s, -s, c, 0, 0) end)
ctxMethod("transform", function(this, a, b, c, d, e, f) mul(cstate(this), num(a), num(b), num(c), num(d), num(e), num(f)) end)
ctxMethod("setTransform", function(this, a, b, c, d, e, f)
  if type(a) == "table" then cstate(this).m = { 1, 0, 0, 1, 0, 0 } return end
  cstate(this).m = { num(a or 1), num(b or 0), num(c or 0), num(d or 1), num(e or 0), num(f or 0) }
end)
ctxMethod("resetTransform", function(this) cstate(this).m = { 1, 0, 0, 1, 0, 0 } end)
local function rectOp(this, x, y, w, h, kind)
  local st = cstate(this)
  x, y, w, h = num(x), num(y), num(w), num(h)
  local m = st.m
  if kind == "clear" then
    local n = W2N[this]
    local cw, ch = tonumber(n.attrs.width) or 300, tonumber(n.attrs.height) or 150
    local x0, y0 = tx(st, x, y)
    local x1, y1 = tx(st, x + w, y + h)
    if m[2] == 0 and m[3] == 0 and min(x0, x1) <= 0 and min(y0, y1) <= 0 and max(x0, x1) >= cw and max(y0, y1) >= ch then
      n.canvasOps = {}
      if current then current.canvasDirty[n] = true end
      return
    end
    pushOp(this, { op = "clear", x = min(x0, x1), y = min(y0, y1), w = math.abs(x1 - x0), h = math.abs(y1 - y0) })
    return
  end
  local c, a = paintColor(R.get(this, kind == "fill" and "fillStyle" or "strokeStyle"))
  a = alphaOf(this, a)
  if kind == "fill" then
    if m[2] == 0 and m[3] == 0 then
      local x0, y0 = tx(st, x, y)
      local x1, y1 = tx(st, x + w, y + h)
      -- an opaque fill of the whole canvas hides all before it: the list starts again
      local n = W2N[this]
      if a >= 0.99 and min(x0, x1) <= 0 and min(y0, y1) <= 0 and max(x0, x1) >= (tonumber(n.attrs.width) or 300) and max(y0, y1) >= (tonumber(n.attrs.height) or 150) then
        n.canvasOps = {}
      end
      pushOp(this, { op = "rect", x = min(x0, x1), y = min(y0, y1), w = math.abs(x1 - x0), h = math.abs(y1 - y0), c = c, a = a })
    else
      local p = {}
      for _, q in ipairs({ { x, y }, { x + w, y }, { x + w, y + h }, { x, y + h } }) do local px, py = tx(st, q[1], q[2]); p[#p + 1] = px; p[#p + 1] = py end
      pushOp(this, { op = "poly", pts = p, c = c, a = a })
    end
  else
    local p = {}
    for _, q in ipairs({ { x, y }, { x + w, y }, { x + w, y + h }, { x, y + h } }) do local px, py = tx(st, q[1], q[2]); p[#p + 1] = px; p[#p + 1] = py end
    pushOp(this, { op = "lines", pts = p, closed = true, c = c, a = a, lw = num(R.get(this, "lineWidth") or 1) * math.sqrt(math.abs(m[1] * m[4] - m[2] * m[3])) })
  end
end
ctxMethod("fillRect", function(this, x, y, w, h) rectOp(this, x, y, w, h, "fill") end)
ctxMethod("strokeRect", function(this, x, y, w, h) rectOp(this, x, y, w, h, "stroke") end)
ctxMethod("clearRect", function(this, x, y, w, h) rectOp(this, x, y, w, h, "clear") end)
ctxMethod("beginPath", function(this) cstate(this).path = {} end)
local function sub(st)
  local p = st.path
  local s = p[#p]
  if not s then s = { pts = {} }; p[1] = s end
  return s
end
ctxMethod("moveTo", function(this, x, y)
  local st = cstate(this)
  local px, py = tx(st, num(x), num(y))
  st.path[#st.path + 1] = { pts = { px, py } }
end)
ctxMethod("lineTo", function(this, x, y)
  local st = cstate(this)
  local s = sub(st)
  local px, py = tx(st, num(x), num(y))
  s.pts[#s.pts + 1] = px; s.pts[#s.pts + 1] = py
  s.circle = nil
end)
ctxMethod("closePath", function(this) local s = cstate(this).path; s = s[#s]; if s then s.closed = true end end)
ctxMethod("rect", function(this, x, y, w, h)
  local st = cstate(this)
  x, y, w, h = num(x), num(y), num(w), num(h)
  local s = { pts = {}, closed = true }
  for _, q in ipairs({ { x, y }, { x + w, y }, { x + w, y + h }, { x, y + h } }) do local px, py = tx(st, q[1], q[2]); s.pts[#s.pts + 1] = px; s.pts[#s.pts + 1] = py end
  st.path[#st.path + 1] = s
end)
local function arcPoints(this, cx, cy, rx, ry, a0, a1, ccw, rot)
  local st = cstate(this)
  local s = sub(st)
  local fresh = #s.pts == 0
  local sweep = a1 - a0
  if ccw then if sweep > 0 then sweep = sweep - 2 * math.pi * math.ceil(sweep / (2 * math.pi)) end
  else if sweep < 0 then sweep = sweep + 2 * math.pi * math.ceil(-sweep / (2 * math.pi)) end end
  if math.abs(sweep) > 2 * math.pi then sweep = sweep > 0 and 2 * math.pi or -2 * math.pi end
  local steps = max(6, floor(math.abs(sweep) / (2 * math.pi) * 32 + 0.5))
  for i = 0, steps do
    local a = a0 + sweep * i / steps
    local ux, uy = math.cos(a) * rx, math.sin(a) * ry
    if rot then ux, uy = ux * math.cos(rot) - uy * math.sin(rot), ux * math.sin(rot) + uy * math.cos(rot) end
    local px, py = tx(st, cx + ux, cy + uy)
    s.pts[#s.pts + 1] = px; s.pts[#s.pts + 1] = py
  end
  -- a whole circle alone in its sub-path is drawn as a disc or a ring
  if fresh and math.abs(math.abs(sweep) - 2 * math.pi) < 1e-6 and rx == ry then
    local m = st.m
    if m[2] == 0 and m[3] == 0 and math.abs(m[1] - m[4]) < 1e-9 then
      local px, py = tx(st, cx, cy)
      s.circle = { x = px, y = py, r = rx * math.abs(m[1]) }
    end
  else s.circle = nil end
end
ctxMethod("arc", function(this, x, y, r, a0, a1, ccw) arcPoints(this, num(x), num(y), num(r), num(r), num(a0), num(a1), R.T(ccw)) end)
ctxMethod("ellipse", function(this, x, y, rx, ry, rot, a0, a1, ccw) arcPoints(this, num(x), num(y), num(rx), num(ry), num(a0), num(a1), R.T(ccw), num(rot)) end)
ctxMethod("arcTo", function(this, x1, y1, x2, y2) CtxProto.lineTo(this, x1, y1); CtxProto.lineTo(this, x2, y2) end)
local function curve(this, pts)
  local st = cstate(this)
  local s = sub(st)
  -- the last point, back in canvas units, is the start of the curve
  local m = st.m
  local det = m[1] * m[4] - m[2] * m[3]
  local lx, ly = s.pts[#s.pts - 1] or 0, s.pts[#s.pts] or 0
  local ix = det ~= 0 and ((lx - m[5]) * m[4] - (ly - m[6]) * m[3]) / det or lx
  local iy = det ~= 0 and ((ly - m[6]) * m[1] - (lx - m[5]) * m[2]) / det or ly
  local P0 = { ix, iy }
  for i = 1, 12 do
    local t = i / 12
    local x, y
    if #pts == 2 then
      local u = 1 - t
      x = u * u * P0[1] + 2 * u * t * pts[1][1] + t * t * pts[2][1]
      y = u * u * P0[2] + 2 * u * t * pts[1][2] + t * t * pts[2][2]
    else
      local u = 1 - t
      x = u ^ 3 * P0[1] + 3 * u * u * t * pts[1][1] + 3 * u * t * t * pts[2][1] + t ^ 3 * pts[3][1]
      y = u ^ 3 * P0[2] + 3 * u * u * t * pts[1][2] + 3 * u * t * t * pts[2][2] + t ^ 3 * pts[3][2]
    end
    local px, py = tx(st, x, y)
    s.pts[#s.pts + 1] = px; s.pts[#s.pts + 1] = py
  end
  s.circle = nil
end
ctxMethod("quadraticCurveTo", function(this, a, b, c, d) curve(this, { { num(a), num(b) }, { num(c), num(d) } }) end)
ctxMethod("bezierCurveTo", function(this, a, b, c, d, e, f) curve(this, { { num(a), num(b) }, { num(c), num(d) }, { num(e), num(f) } }) end)
ctxMethod("fill", function(this)
  local c, a = paintColor(R.get(this, "fillStyle"))
  a = alphaOf(this, a)
  for _, s in ipairs(cstate(this).path) do
    if s.circle then pushOp(this, { op = "disc", x = s.circle.x, y = s.circle.y, r = s.circle.r, c = c, a = a })
    elseif #s.pts >= 6 then pushOp(this, { op = "poly", pts = { table.unpack(s.pts) }, c = c, a = a }) end
  end
end)
ctxMethod("stroke", function(this)
  local c, a = paintColor(R.get(this, "strokeStyle"))
  a = alphaOf(this, a)
  local st = cstate(this)
  local scale = math.sqrt(math.abs(st.m[1] * st.m[4] - st.m[2] * st.m[3]))
  local lw = num(R.get(this, "lineWidth") or 1) * scale
  for _, s in ipairs(st.path) do
    if s.circle then pushOp(this, { op = "ring", x = s.circle.x, y = s.circle.y, r = s.circle.r, lw = lw, c = c, a = a })
    elseif #s.pts >= 4 then pushOp(this, { op = "lines", pts = { table.unpack(s.pts) }, closed = s.closed, lw = lw, c = c, a = a }) end
  end
end)
local function textOp(this, s, x, y, style)
  local st = cstate(this)
  local px, bold, mono = fontOfCanvas(this)
  local c, a = paintColor(R.get(this, style))
  local X, Y = tx(st, num(x), num(y))
  local scale = math.sqrt(math.abs(st.m[1] * st.m[4] - st.m[2] * st.m[3]))
  pushOp(this, { op = "text", s = str(s), x = X, y = Y, px = px * scale, bold = bold, mono = mono, c = c, a = alphaOf(this, a),
    align = str(R.get(this, "textAlign") or "start"), base = str(R.get(this, "textBaseline") or "alphabetic") })
end
ctxMethod("fillText", function(this, s, x, y) textOp(this, s, x, y, "fillStyle") end)
ctxMethod("strokeText", function(this, s, x, y) textOp(this, s, x, y, "strokeStyle") end)
ctxMethod("measureText", function(this, s)
  local px, bold, mono = fontOfCanvas(this)
  local p = current
  local w = 0
  if p then w = p.host.measure(str(s), p.host.fontOf({ fs = px, bold = bold, mono = mono })) end
  return obj({ { "width", w + 0.0 }, { "actualBoundingBoxAscent", px * 0.8 }, { "actualBoundingBoxDescent", px * 0.2 } })
end)
ctxMethod("drawImage", function(this, img, a, b, c, d, e, f, g, h)
  local n = W2N[img] or (type(img) == "table" and rawget(img, "\0node"))
  if not n then return end
  local src = n.attrs and n.attrs.src
  if n.tag == "canvas" then return end
  if not src or not current then return end
  local url = current:abs(src)
  local st = cstate(this)
  local x, y, w, hh
  if e ~= nil then x, y, w, hh = num(e), num(f), num(g), num(h)
  else x, y, w, hh = num(a), num(b), c and num(c), d and num(d) end
  if not w then
    local iw, ih = current.host.intrinsic and current.host.intrinsic(n, url)
    w, hh = iw or tonumber(n.attrs.width) or 32, ih or tonumber(n.attrs.height) or 32
  end
  local x0, y0 = tx(st, x, y)
  local x1, y1 = tx(st, x + w, y + hh)
  pushOp(this, { op = "image", src = url, x = min(x0, x1), y = min(y0, y1), w = math.abs(x1 - x0), h = math.abs(y1 - y0) })
end)
local function gradient()
  local g = obj()
  rawset(g, "\0stops", {})
  R.set(g, "addColorStop", native("addColorStop", function(this, o, c) local s = rawget(this, "\0stops"); s[#s + 1] = { num(o), str(c) } end))
  return g
end
ctxMethod("createLinearGradient", function() return gradient() end)
ctxMethod("createRadialGradient", function() return gradient() end)
ctxMethod("createPattern", function() return "#808080" end)
ctxMethod("setLineDash", function() end)
ctxMethod("getLineDash", function() return arr({}) end)
ctxMethod("clip", function() end)
ctxMethod("isPointInPath", function() return false end)
ctxMethod("getImageData", function(this, x, y, w, h)
  local d = { n = 0 }
  return obj({ { "width", num(w) }, { "height", num(h) }, { "data", R.array({}) } })
end)
ctxMethod("putImageData", function() end)
ctxMethod("createImageData", function(this, w, h) return obj({ { "width", num(w) }, { "height", num(h) }, { "data", R.array({}) } }) end)
local function contextOf(n)
  if n._ctx then return n._ctx end
  local ctx = setmetatable({}, CtxMt)
  W2N[ctx] = n
  rawset(ctx, "\0st", { m = { 1, 0, 0, 1, 0, 0 }, stack = {}, path = {} })
  for _, kv in ipairs({ { "fillStyle", "#000000" }, { "strokeStyle", "#000000" }, { "lineWidth", 1.0 }, { "font", "10px sans-serif" },
    { "textAlign", "start" }, { "textBaseline", "alphabetic" }, { "globalAlpha", 1.0 }, { "lineCap", "butt" }, { "lineJoin", "miter" },
    { "globalCompositeOperation", "source-over" }, { "imageSmoothingEnabled", true } }) do R.set(ctx, kv[1], kv[2]) end
  R.set(ctx, "canvas", wrap(n))
  n.canvasOps = n.canvasOps or {}
  n._ctx = ctx
  return ctx
end

-- ---------------------------------------------------------------- element properties
local PROPS = {}   -- name -> { get = function(node, wrapper), set = function(node, value) }
local METHODS = {}
local function prop(name, get, set) PROPS[name] = { get = get, set = set } end
local function method(name, f) METHODS[name] = native(name, f) end
local function nodeOf(w)
  if w == nil or w == null then return nil end
  local n = W2N[w]
  if not n then R.throw(R.new(G.TypeError, "parameter is not of type 'Node'")) end
  return n
end
local function asNode(v)
  if type(v) == "string" or type(v) == "number" then return D.txt(str(v)) end
  return nodeOf(v)
end
local function elemKids(n)
  local out = {}
  for _, k in ipairs(n.kids or {}) do if k.type == "el" then out[#out + 1] = k end end
  return out
end
local function sibling(n, dir, elemOnly)
  local p = n.parent
  if not p then return nil end
  local i = D.indexIn(p, n)
  i = i + dir
  while p.kids[i] do
    local k = p.kids[i]
    if not elemOnly or k.type == "el" then return k end
    i = i + dir
  end
  return nil
end
local function wraps(list) local t = {}; for i, n in ipairs(list) do t[i] = wrap(n) end return arr(t) end
local function ensure(p) if p then p:layout() end end
local function boxOf(n)
  local p = current
  if not p then return nil end
  p:layout()
  return p.root and L.boxOf(p.root, n)
end
local function fieldValue(n)
  if n.tag == "select" then
    local i, sel = 0, n.selectedIndex or 0
    for _, o in ipairs(D.byTag(n, "option")) do
      if i == sel then return o.attrs.value or L.optionText(o) end
      i = i + 1
    end
    return ""
  end
  if n.tag == "textarea" then return n.value or D.textOf(n) end
  if n.tag == "option" then return n.attrs.value or L.optionText(n) end
  local t = (n.attrs.type or ""):lower()
  if n.value == nil and (t == "checkbox" or t == "radio") then return n.attrs.value or "on" end
  if n.value == nil and t == "range" then
    local lo, hi = tonumber(n.attrs.min) or 0, tonumber(n.attrs.max) or 100
    return n.attrs.value or tostring(floor((lo + hi) / 2))
  end
  return n.value or n.attrs.value or ""
end
H.fieldValue = fieldValue

prop("nodeType", function(n) return n.type == "el" and 1.0 or n.type == "text" and 3.0 or n.type == "comment" and 8.0 or n.type == "doc" and 9.0 or 11.0 end)
prop("nodeName", function(n) return n.type == "el" and n.tag:upper() or n.type == "text" and "#text" or n.type == "doc" and "#document" or "#document-fragment" end)
prop("tagName", function(n) return n.tag and n.tag:upper() end)
prop("localName", function(n) return n.tag end)
prop("id", function(n) return n.attrs and n.attrs.id or "" end, function(n, v) D.setAttr(n, "id", str(v)); changed(true) end)
prop("className", function(n) return n.attrs and n.attrs.class or "" end, function(n, v) D.setAttr(n, "class", str(v)); changed(true) end)
prop("classList", function(n) return classListOf(n) end)
prop("dataset", function(n) return datasetOf(n) end)
prop("style", function(n) return styleOf(n) end, function(n, v) D.setAttr(n, "style", str(v)); n._inl = nil; changed(false) end)
prop("textContent", function(n) if n.type == "text" or n.type == "comment" then return n.text end return D.textOf(n) end,
  function(n, v) v = (v == nil or v == null) and "" or str(v); if n.type == "text" then n.text = v else D.setText(n, v) end changed(true) end)
prop("innerText", PROPS.textContent.get, PROPS.textContent.set)
prop("nodeValue", function(n) return n.type == "el" and null or n.text end, function(n, v) if n.type ~= "el" then n.text = str(v); changed(false) end end)
prop("data", function(n) return n.text end, function(n, v) n.text = str(v); changed(false) end)
prop("innerHTML", function(n) return D.serialize(n, true) end, function(n, v)
  local f = D.fragment(str(v))
  for _, k in ipairs(n.kids) do k.parent = nil end
  n.kids = {}
  for _, k in ipairs({ table.unpack(f.kids) }) do D.insert(n, k) end
  if current then current:prepareForms(n) end
  changed(true)
  if current then current.needImages = true end
end)
prop("outerHTML", function(n) return D.serialize(n, false) end, function(n, v)
  local p = n.parent
  if not p then return end
  local f = D.fragment(str(v))
  D.insert(p, f, n)
  D.remove(n)
  changed(true)
end)
prop("parentNode", function(n) return n.parent and wrap(n.parent) or null end)
prop("parentElement", function(n) return (n.parent and n.parent.type == "el") and wrap(n.parent) or null end)
prop("children", function(n) return wraps(elemKids(n)) end)
prop("childNodes", function(n) return wraps(n.kids or {}) end)
prop("childElementCount", function(n) return #elemKids(n) + 0.0 end)
prop("firstChild", function(n) return n.kids and n.kids[1] and wrap(n.kids[1]) or null end)
prop("lastChild", function(n) return n.kids and n.kids[#n.kids] and wrap(n.kids[#n.kids]) or null end)
prop("firstElementChild", function(n) local e = elemKids(n); return e[1] and wrap(e[1]) or null end)
prop("lastElementChild", function(n) local e = elemKids(n); return e[#e] and wrap(e[#e]) or null end)
prop("nextSibling", function(n) local s = sibling(n, 1); return s and wrap(s) or null end)
prop("previousSibling", function(n) local s = sibling(n, -1); return s and wrap(s) or null end)
prop("nextElementSibling", function(n) local s = sibling(n, 1, true); return s and wrap(s) or null end)
prop("previousElementSibling", function(n) local s = sibling(n, -1, true); return s and wrap(s) or null end)
prop("isConnected", function(n) return connected(n) end)
prop("ownerDocument", function(n) return current and wrap(current.doc) or null end)
prop("value", function(n) return fieldValue(n) end, function(n, v)
  v = (v == nil or v == null) and "" or str(v)
  if n.tag == "select" then
    local i = 0
    for _, o in ipairs(D.byTag(n, "option")) do
      if (o.attrs.value or L.optionText(o)) == v then n.selectedIndex = i end
      i = i + 1
    end
  else
    n.value = v
    n.caret = nil
  end
  changed(false)
end)
prop("defaultValue", function(n) return n.attrs.value or "" end, function(n, v) D.setAttr(n, "value", str(v)); changed(false) end)
prop("valueAsNumber", function(n) return tonumber(fieldValue(n)) or (0 / 0) end, function(n, v) n.value = R.tostr(v); changed(false) end)
prop("checked", function(n) return n.checked == true end, function(n, v)
  n.checked = R.T(v)
  if n.checked and (n.attrs.type or ""):lower() == "radio" and current then current:uncheckGroup(n) end
  changed(true)
end)
prop("selectedIndex", function(n) return (n.selectedIndex or 0) + 0.0 end, function(n, v) n.selectedIndex = floor(num(v)); changed(false) end)
prop("options", function(n) return wraps(D.byTag(n, "option")) end)
prop("selected", function(n)
  local s = n.parent
  while s and s.tag ~= "select" do s = s.parent end
  if not s then return n.attrs.selected ~= nil end
  local i = 0
  for _, o in ipairs(D.byTag(s, "option")) do if o == n then return i == (s.selectedIndex or 0) end i = i + 1 end
  return false
end)
for _, a in ipairs({ "href", "src", "type", "name", "alt", "title", "placeholder", "rel", "target", "action", "method", "htmlFor", "lang", "min", "max", "step", "pattern", "accept", "download", "role" }) do
  local attr = a == "htmlFor" and "for" or a
  prop(a, function(n)
    local v = n.attrs and n.attrs[attr]
    if (a == "href" or a == "src") and v and current then return current:abs(v) end
    if a == "type" and n.tag == "input" then return (v or "text"):lower() end
    if a == "type" and n.tag == "button" then return (v or "submit"):lower() end
    return v or ""
  end, function(n, v)
    D.setAttr(n, attr, str(v)); changed(true)
    if a == "src" and current then
      current.needImages = true
      -- a picture (also one made with new Image()) says it has loaded on the next turn of the loop
      if n.tag == "img" then current.pendingLoads[#current.pendingLoads + 1] = n end
    end
  end)
end
for _, a in ipairs({ "disabled", "hidden", "required", "readOnly", "multiple", "autofocus", "open" }) do
  local attr = a:lower()
  prop(a, function(n) return n.attrs and n.attrs[attr] ~= nil end, function(n, v)
    if R.T(v) then D.setAttr(n, attr, "") else D.removeAttr(n, attr) end
    changed(true)
  end)
end
prop("tabIndex", function(n) return tonumber(n.attrs.tabindex) or (H.focusable(n) and 0.0 or -1.0) end, function(n, v) D.setAttr(n, "tabindex", R.tostr(v)) end)
prop("width", function(n)
  if n.tag == "canvas" then return (tonumber(n.attrs.width) or 300) + 0.0 end
  if n.tag == "img" then local b = boxOf(n); return b and floor(b.cw) + 0.0 or (tonumber(n.attrs.width) or 0) + 0.0 end
  return (tonumber(n.attrs.width) or 0) + 0.0
end, function(n, v)
  D.setAttr(n, "width", R.tostr(floor(num(v))))
  if n.tag == "canvas" then n.canvasOps = {}; if n._ctx then rawget(n._ctx, "\0st").m = { 1, 0, 0, 1, 0, 0 } end end
  changed(false)
end)
prop("height", function(n)
  if n.tag == "canvas" then return (tonumber(n.attrs.height) or 150) + 0.0 end
  if n.tag == "img" then local b = boxOf(n); return b and floor(b.ch) + 0.0 or (tonumber(n.attrs.height) or 0) + 0.0 end
  return (tonumber(n.attrs.height) or 0) + 0.0
end, function(n, v)
  D.setAttr(n, "height", R.tostr(floor(num(v))))
  if n.tag == "canvas" then n.canvasOps = {}; if n._ctx then rawget(n._ctx, "\0st").m = { 1, 0, 0, 1, 0, 0 } end end
  changed(false)
end)
prop("naturalWidth", function(n) local w = current and current.host.intrinsic and current.host.intrinsic(n, current:abs(n.attrs.src or "")); return (w or 0) + 0.0 end)
prop("naturalHeight", function(n) local _, h = current and current.host.intrinsic and current.host.intrinsic(n, current:abs(n.attrs.src or "")); return (h or 0) + 0.0 end)
prop("complete", function() return true end)
local function geo(f) return function(n) local b = boxOf(n); if not b then return 0.0 end return floor(f(b) + 0.5) + 0.0 end end
prop("offsetWidth", geo(function(b) return b.w end))
prop("offsetHeight", geo(function(b) return b.h end))
prop("offsetLeft", geo(function(b) return b.x end))
prop("offsetTop", geo(function(b) return b.y end))
prop("clientWidth", geo(function(b) return b.w - (b.bd and (b.bd.l + b.bd.r) or 0) end))
prop("clientHeight", geo(function(b) return b.h - (b.bd and (b.bd.t + b.bd.b) or 0) end))
prop("scrollWidth", geo(function(b) return b.w end))
prop("scrollHeight", geo(function(b) return max(b.h, (b.scrollH or 0) + (b.pd and b.pd.t + b.pd.b or 0)) end))
prop("scrollTop", function(n)
  if n.tag == "html" or n.tag == "body" then return (current and current.sy or 0) + 0.0 end
  return (n.scrollTop or 0) + 0.0
end, function(n, v)
  if (n.tag == "html" or n.tag == "body") and current then current:scrollTo(num(v)) return end
  n.scrollTop = max(0, num(v)); if current then current.needLayout = true end
end)
prop("scrollLeft", function() return 0.0 end, function() end)
prop("offsetParent", function(n) return n.parent and wrap(n.parent) or null end)
prop("form", function(n) local f = n.parent; while f and f.tag ~= "form" do f = f.parent end return f and wrap(f) or null end)
prop("elements", function(n) local out = {}; D.walk(n, function(e) if e.tag == "input" or e.tag == "select" or e.tag == "textarea" or e.tag == "button" then out[#out + 1] = e end end); return wraps(out) end)
prop("labels", function() return arr({}) end)
prop("validity", function(n) local ok = not (n.attrs.required and fieldValue(n) == ""); return obj({ { "valid", ok }, { "valueMissing", not ok } }) end)
prop("validationMessage", function(n) return (n.attrs.required and fieldValue(n) == "") and "Please fill out this field." or "" end)
prop("attributes", function(n)
  local list = {}
  for _, k in ipairs(n.order or {}) do list[#list + 1] = obj({ { "name", k }, { "value", n.attrs[k] } }) end
  return arr(list)
end)
prop("selectionStart", function(n) return (n.caret or #(fieldValue(n))) + 0.0 end, function(n, v) n.caret = floor(num(v)) end)
prop("selectionEnd", function(n) return (n.caret or #(fieldValue(n))) + 0.0 end, function() end)

method("getAttribute", function(this, k) local v = nodeOf(this).attrs[str(k):lower()]; if v == nil then return null end return v end)
method("setAttribute", function(this, k, v)
  local n = nodeOf(this)
  k = str(k):lower()
  D.setAttr(n, k, str(v))
  if k == "checked" then n.checked = true end
  if k == "value" and n.tag ~= "input" then n.value = nil end
  if k == "src" and current then current.needImages = true end
  changed(true)
end)
method("removeAttribute", function(this, k) local n = nodeOf(this); D.removeAttr(n, str(k):lower()); changed(true) end)
method("hasAttribute", function(this, k) return nodeOf(this).attrs[str(k):lower()] ~= nil end)
method("toggleAttribute", function(this, k, force)
  local n = nodeOf(this); k = str(k):lower()
  local want = n.attrs[k] == nil
  if force ~= nil then want = R.T(force) end
  if want then D.setAttr(n, k, "") else D.removeAttr(n, k) end
  changed(true)
  return want
end)
method("getAttributeNames", function(this) local n = nodeOf(this); local t = {}; for i, k in ipairs(n.order) do t[i] = k end return arr(t) end)
method("appendChild", function(this, c) insertNode(nodeOf(this), nodeOf(c)); return c end)
method("insertBefore", function(this, c, ref) insertNode(nodeOf(this), nodeOf(c), ref ~= nil and ref ~= null and nodeOf(ref) or nil); return c end)
method("removeChild", function(this, c)
  local n = nodeOf(c)
  if n.parent ~= nodeOf(this) then R.throw(R.new(G.Error, "NotFoundError: The node to be removed is not a child of this node.")) end
  D.remove(n); changed(true); return c
end)
method("replaceChild", function(this, new, old) local o = nodeOf(old); insertNode(nodeOf(this), nodeOf(new), o); D.remove(o); return old end)
method("remove", function(this) D.remove(nodeOf(this)); changed(true) end)
method("append", function(this, ...) local n = nodeOf(this); for _, c in ipairs({ ... }) do insertNode(n, asNode(c)) end end)
method("prepend", function(this, ...) local n = nodeOf(this); local first = n.kids[1]; for _, c in ipairs({ ... }) do insertNode(n, asNode(c), first) end end)
method("before", function(this, ...) local n = nodeOf(this); for _, c in ipairs({ ... }) do insertNode(n.parent, asNode(c), n) end end)
method("after", function(this, ...)
  local n = nodeOf(this)
  local nx = sibling(n, 1)
  for _, c in ipairs({ ... }) do insertNode(n.parent, asNode(c), nx) end
end)
method("replaceWith", function(this, ...) local n = nodeOf(this); for _, c in ipairs({ ... }) do insertNode(n.parent, asNode(c), n) end D.remove(n); changed(true) end)
method("replaceChildren", function(this, ...)
  local n = nodeOf(this)
  for _, k in ipairs(n.kids) do k.parent = nil end
  n.kids = {}
  for _, c in ipairs({ ... }) do insertNode(n, asNode(c)) end
  changed(true)
end)
method("cloneNode", function(this, deep) return wrap(D.clone(nodeOf(this), R.T(deep))) end)
method("contains", function(this, o) if o == nil or o == null then return false end return D.contains(nodeOf(this), nodeOf(o)) end)
method("hasChildNodes", function(this) return #(nodeOf(this).kids or {}) > 0 end)
method("matches", function(this, sel) return C.matches(nodeOf(this), str(sel)) end)
method("closest", function(this, sel)
  local list = C.selector(str(sel))
  local n = nodeOf(this)
  while n and n.type == "el" do
    if C.matches(n, list) then return wrap(n) end
    n = n.parent
  end
  return null
end)
method("querySelector", function(this, sel) local r = C.query(nodeOf(this), str(sel), true)[1]; return r and wrap(r) or null end)
method("querySelectorAll", function(this, sel) return wraps(C.query(nodeOf(this), str(sel))) end)
method("getElementsByTagName", function(this, t) return wraps(D.byTag(nodeOf(this), str(t))) end)
method("getElementsByClassName", function(this, c)
  local want = {}
  for w in str(c):gmatch("%S+") do want[#want + 1] = w end
  local out = {}
  D.walk(nodeOf(this), function(e)
    local set = C.classSet(e)
    for _, w in ipairs(want) do if not set[w] then return end end
    out[#out + 1] = e
  end)
  return wraps(out)
end)
method("getElementsByName", function(this, nm) local out = {}; D.walk(nodeOf(this), function(e) if e.attrs.name == str(nm) then out[#out + 1] = e end end); return wraps(out) end)
method("insertAdjacentHTML", function(this, where, html)
  local n = nodeOf(this)
  local f = D.fragment(str(html))
  where = str(where):lower()
  if where == "beforebegin" then D.insert(n.parent, f, n)
  elseif where == "afterbegin" then D.insert(n, f, n.kids[1])
  elseif where == "beforeend" then D.insert(n, f)
  else D.insert(n.parent, f, sibling(n, 1)) end
  if current then current:prepareForms(n.parent or n) end
  changed(true)
end)
method("insertAdjacentElement", function(this, where, el)
  local n, e = nodeOf(this), nodeOf(el)
  where = str(where):lower()
  if where == "beforebegin" then insertNode(n.parent, e, n)
  elseif where == "afterbegin" then insertNode(n, e, n.kids[1])
  elseif where == "beforeend" then insertNode(n, e)
  else insertNode(n.parent, e, sibling(n, 1)) end
  return el
end)
method("insertAdjacentText", function(this, where, s) METHODS.insertAdjacentElement(this, where, wrap(D.txt(str(s)))) end)
method("addEventListener", function(this, kind, f, opts)
  local n = nodeOf(this)
  if f == nil or f == null then return end
  n.listeners = n.listeners or {}
  kind = str(kind)
  local list = n.listeners[kind] or {}
  n.listeners[kind] = list
  for _, l in ipairs(list) do if l.f == f then return end end
  local once = type(opts) == "table" and opts ~= null and R.T(R.get(opts, "once"))
  list[#list + 1] = { f = f, once = once }
end)
method("removeEventListener", function(this, kind, f)
  local n = nodeOf(this)
  local list = n.listeners and n.listeners[str(kind)]
  if not list then return end
  for i, l in ipairs(list) do if l.f == f then l.removed = true; table.remove(list, i); return end end
end)
method("dispatchEvent", function(this, e)
  if not current then return true end
  return fire(current, nodeOf(this), e)
end)
method("click", function(this) if current then current:activate(nodeOf(this)) end end)
method("focus", function(this) if current then current:setFocus(nodeOf(this)) end end)
method("blur", function(this) if current and current.focus == nodeOf(this) then current:setFocus(nil) end end)
method("select", function(this) end)
method("setSelectionRange", function(this, a) nodeOf(this).caret = floor(num(a)) end)
method("checkValidity", function(this) local n = nodeOf(this); return not (n.attrs.required and fieldValue(n) == "") end)
method("reportValidity", function(this) local n = nodeOf(this); return not (n.attrs.required and fieldValue(n) == "") end)
method("setCustomValidity", function() end)
method("submit", function(this) if current then current:submitForm(nodeOf(this), true) end end)
method("reset", function(this)
  D.walk(nodeOf(this), function(e) e.value = nil; e.checked = e.attrs.checked ~= nil; e.selectedIndex = nil end)
  if current then current:prepareForms(nodeOf(this)) end
  changed(true)
end)
method("getBoundingClientRect", function(this)
  local b = boxOf(nodeOf(this))
  local sy = current and current.sy or 0
  if b and b.fixed then sy = 0 end
  local x, y, w, h = b and b.x or 0, (b and b.y or 0) - sy, b and b.w or 0, b and b.h or 0
  return obj({ { "x", x + 0.0 }, { "y", y + 0.0 }, { "left", x + 0.0 }, { "top", y + 0.0 }, { "width", w + 0.0 }, { "height", h + 0.0 },
    { "right", x + w + 0.0 }, { "bottom", y + h + 0.0 } })
end)
method("getClientRects", function(this) return arr({ METHODS.getBoundingClientRect(this) }) end)
method("scrollIntoView", function(this)
  local b = boxOf(nodeOf(this))
  if b and current then current:scrollTo(b.y - 8) end
end)
method("scrollTo", function(this, x, y)
  local n = nodeOf(this)
  if type(x) == "table" and x ~= null then y = R.get(x, "top") end
  n.scrollTop = max(0, num(y or 0)); if current then current.needLayout = true end
end)
method("scrollBy", function(this, x, y)
  local n = nodeOf(this)
  if type(x) == "table" and x ~= null then y = R.get(x, "top") end
  n.scrollTop = max(0, (n.scrollTop or 0) + num(y or 0)); if current then current.needLayout = true end
end)
method("getContext", function(this, kind)
  local n = nodeOf(this)
  if n.tag ~= "canvas" or str(kind) ~= "2d" then return null end
  return contextOf(n)
end)
method("toDataURL", function() return "data:," end)
method("animate", function() return obj({ { "cancel", native("cancel", function() end) }, { "finished", R.M(G.Promise, "resolve") } }) end)
method("attachShadow", function(this) return this end)
method("isEqualNode", function(this, o) return o ~= nil and o ~= null and D.serialize(nodeOf(this)) == D.serialize(nodeOf(o)) end)
method("isSameNode", function(this, o) return this == o end)
method("normalize", function() end)
method("play", function() return R.M(G.Promise, "resolve") end)
method("pause", function() end)
method("load", function() end)
method("showModal", function(this) local n = nodeOf(this); D.setAttr(n, "open", ""); changed(true) end)
method("show", function(this) local n = nodeOf(this); D.setAttr(n, "open", ""); changed(true) end)
method("close", function(this) local n = nodeOf(this); D.removeAttr(n, "open"); changed(true) end)
-- text nodes
method("splitText", function(this, off) local n = nodeOf(this); off = floor(num(off)); local rest = D.txt(n.text:sub(off + 1)); n.text = n.text:sub(1, off); insertNode(n.parent, rest, sibling(n, 1)); return wrap(rest) end)
method("appendData", function(this, s) local n = nodeOf(this); n.text = n.text .. str(s); changed(false) end)

-- the prototypes for instanceof
local ProtoNode = R.protoOf(native("Node", function() end))
local CTORS = {}
local function ctor(name, parentProto)
  local f = native(name, function() R.throw(R.new(G.TypeError, "Illegal constructor")) end)
  local p = R.protoOf(f)
  if parentProto then setmetatable(p, { __index = parentProto, proto = parentProto }) end
  CTORS[name] = f
  return p
end
local NodeP = ctor("Node")
local ElementP = ctor("Element", NodeP)
local HTMLElementP = ctor("HTMLElement", ElementP)
ctor("Text", NodeP)
ctor("Document", NodeP)
ctor("HTMLCanvasElement", HTMLElementP)
ctor("HTMLInputElement", HTMLElementP)
ctor("HTMLImageElement", HTMLElementP)
ctor("HTMLFormElement", HTMLElementP)
ctor("HTMLButtonElement", HTMLElementP)
ctor("HTMLDivElement", HTMLElementP)
ctor("HTMLAnchorElement", HTMLElementP)
ctor("HTMLSelectElement", HTMLElementP)
ctor("HTMLTextAreaElement", HTMLElementP)
ctor("CanvasRenderingContext2D")
CtxMt.proto = R.protoOf(CTORS.CanvasRenderingContext2D)
local TAGCTOR = { canvas = "HTMLCanvasElement", input = "HTMLInputElement", img = "HTMLImageElement", form = "HTMLFormElement", button = "HTMLButtonElement",
  div = "HTMLDivElement", a = "HTMLAnchorElement", select = "HTMLSelectElement", textarea = "HTMLTextAreaElement" }
local mtByProto = {}
local accCache = {}
local function elemIndex(w, k)
  if type(k) ~= "string" then return nil end
  local p = PROPS[k]
  if p then
    local a = accCache[k]
    if not a then
      a = accessor(function(o) return p.get(W2N[o], o) end, p.set and function(o, v) p.set(W2N[o], v) end or function() end)
      accCache[k] = a
    end
    return a
  end
  local m = METHODS[k]
  if m then return m end
  return nil
end
local function mtFor(n)
  local name = n.type == "text" and "Text" or n.type == "doc" and "Document" or (n.tag and TAGCTOR[n.tag]) or "HTMLElement"
  local mt = mtByProto[name]
  if not mt then
    mt = { __index = elemIndex, proto = R.protoOf(CTORS[name]) }
    mtByProto[name] = mt
  end
  return mt
end
wrap = function(n)
  if n == nil then return null end
  local w = n.js
  if w then return w end
  if n.isWindow then return current and current.window or null end
  if n.type == "doc" then
    w = setmetatable({}, DocMt)
  else
    w = setmetatable({}, mtFor(n))
  end
  W2N[w] = n
  n.js = w
  return w
end
H.wrap = function(n) return wrap(n) end
H.nodeOf = function(w) return W2N[w] end

-- ---------------------------------------------------------------- document
local DOCPROPS, DOCMETHODS = {}, {}
local function dprop(name, get, set) DOCPROPS[name] = { get = get, set = set } end
local function dmethod(name, f) DOCMETHODS[name] = native(name, f) end
dprop("body", function(d) return wrap(d.body) end)
dprop("head", function(d) return wrap(d.head) end)
dprop("documentElement", function(d) return wrap(d.html) end)
dprop("title", function(d) local t = D.byTag(d, "title")[1]; return t and D.textOf(t):gsub("^%s+", ""):gsub("%s+$", "") or "" end, function(d, v)
  local t = D.byTag(d, "title")[1]
  if not t then t = D.el("title"); D.insert(d.head, t) end
  D.setText(t, str(v))
end)
dprop("readyState", function() return current and current.readyState or "complete" end)
dprop("activeElement", function(d) return wrap((current and current.focus) or d.body) end)
dprop("cookie", function() return current and current.cookie or "" end, function(_, v)
  if not current then return end
  local kv = str(v):match("^([^;]*)")
  local k = kv:match("^%s*([^=]+)=")
  local jar = {}
  for part in (current.cookie or ""):gmatch("[^;]+") do
    local pk = part:match("^%s*([^=]+)=")
    if pk ~= k then jar[#jar + 1] = part:gsub("^%s+", "") end
  end
  jar[#jar + 1] = kv
  current.cookie = table.concat(jar, "; ")
end)
dprop("location", function() return current and current.locationObj or null end, function(_, v) if current then current:navigate(str(v)) end end)
dprop("URL", function() return current and current.url or "" end)
dprop("defaultView", function() return current and current.window or null end)
dprop("currentScript", function() return current and current.curScript and wrap(current.curScript) or null end)
dprop("forms", function(d) return wraps(D.byTag(d, "form")) end)
dprop("images", function(d) return wraps(D.byTag(d, "img")) end)
dprop("links", function(d) local out = {}; D.walk(d, function(e) if e.tag == "a" and e.attrs.href then out[#out + 1] = e end end); return wraps(out) end)
dprop("scripts", function(d) return wraps(D.byTag(d, "script")) end)
dprop("visibilityState", function() return "visible" end)
dprop("hidden", function() return false end)
dprop("nodeType", function() return 9.0 end)
dprop("children", function(d) return wraps({ d.html }) end)
dprop("scrollingElement", function(d) return wrap(d.html) end)
dmethod("getElementById", function(this, id) local n = D.byId(W2N[this], str(id)); return n and wrap(n) or null end)
dmethod("createElement", function(_, tag)
  local n = D.el(str(tag):lower())
  return wrap(n)
end)
dmethod("createElementNS", function(_, ns, tag) return wrap(D.el(str(tag):lower())) end)
dmethod("createTextNode", function(_, s) return wrap(D.txt(str(s))) end)
dmethod("createComment", function(_, s) return wrap({ type = "comment", text = str(s) }) end)
dmethod("createDocumentFragment", function() return wrap({ type = "frag", kids = {}, attrs = {}, order = {} }) end)
dmethod("createEvent", function(_, kind) return newEvent("") end)
dmethod("write", function(this, ...)
  if not current then return end
  local parts = {}
  for i, v in ipairs({ ... }) do parts[i] = str(v) end
  current:docWrite(table.concat(parts))
end)
dmethod("writeln", function(this, ...)
  local parts = {}
  for i, v in ipairs({ ... }) do parts[i] = str(v) end
  if current then current:docWrite(table.concat(parts) .. "\n") end
end)
dmethod("open", function() end)
dmethod("close", function() end)
dmethod("hasFocus", function() return true end)
dmethod("elementFromPoint", function(_, x, y)
  if not current then return null end
  current:layout()
  local n = L.hit(current.root, num(x), num(y), current.sy)
  while n and n.type ~= "el" do n = n.parent end
  return n and wrap(n) or null
end)
dmethod("execCommand", function() return false end)
DocMt = { __index = function(w, k)
  if type(k) ~= "string" then return nil end
  local p = DOCPROPS[k]
  if p then
    local a = accCache["doc:" .. k]
    if not a then
      a = accessor(function(o) return p.get(W2N[o], o) end, p.set and function(o, v) p.set(W2N[o], v) end or function() end)
      accCache["doc:" .. k] = a
    end
    return a
  end
  return DOCMETHODS[k] or METHODS[k]
end }

-- ---------------------------------------------------------------- the page
function H.new(host)
  local p = setmetatable({}, Page)
  p.host = host
  p.vw, p.vh = host.vw or 800, host.vh or 480
  p.sy = 0
  p.timers, p.timerSeq = {}, 0
  p.rafs, p.rafSeq = {}, 0
  p.canvasDirty = {}
  p.logLines = {}
  p.fetches = {}
  p.pendingLoads = {}
  p.cssCache = {}
  p.declared = {}
  p.readyState = "loading"
  return p
end
function Page:now() return self.host.now and self.host.now() or 0 end
function Page:log(line, isError)
  local l = self.logLines
  for s in (line .. "\n"):gmatch("([^\n]*)\n") do l[#l + 1] = s end
  while #l > 300 do table.remove(l, 1) end
  if isError then self.lastError = line; self.lastErrorAt = self:now() end
  if self.host.log then self.host.log(line, isError) end
end
function Page:abs(rel) return H.resolve(self.base or self.url or "", rel) end

-- the text of a file or a web address
function Page:read(url)
  return self.host.read(url)
end

-- translated JS: the names declared at the top become globals of the page (shared by its scripts and handlers, like in a browser)
function Page:translate(src, name)
  local ok, text = pcall(J.compile, src)
  if not ok then return nil, text end
  local first, rest = text:match("^(local [%w_,]+)\n(.*)$")
  if first and not first:find("=", 1, true) then
    for nm in first:sub(7):gmatch("[%w_]+") do self.declared[nm] = true end
    text = "\n" .. rest
  end
  return text
end
function Page:runJS(src, name)
  current = self
  local text, err = self:translate(src, name)
  if not text then report(self, name, err); return end
  local f, e = load(R.header() .. text, "=" .. name, "t")
  if not f then self:log("[script error: " .. name .. ": " .. tostring(e) .. "]", true); return end
  local ok, e2 = pcall(f, R, self.env)
  if not ok then
    if type(e2) == "string" and e2:find("interrupted", 1, true) then error(e2, 0) end
    report(self, name, e2)
  end
  drain(self)
end
function Page:compileHandler(code, name)
  local text, err = self:translate("__h = function (event) {\n" .. code .. "\n};", name)
  if not text then report(self, name, err); return nil end
  local f, e = load(R.header() .. text, "=" .. name, "t")
  if not f then return nil end
  local env = self.env
  local ok, e2 = pcall(f, R, env)
  if not ok then report(self, name, e2); return nil end
  local h = rawget(env, "__h")
  rawset(env, "__h", nil)
  return h
end
runScriptNode = function(p, n)
  if n._ran then return end
  local ty = (n.attrs.type or ""):lower()
  if ty ~= "" and ty ~= "text/javascript" and ty ~= "application/javascript" and ty ~= "module" and ty ~= "text/babel" then n._ran = true; return end
  n._ran = true
  local src = n.attrs.src
  local code, name
  if src then
    local url = p:abs(src)
    local body, err = p:read(url)
    if not body then p:log("[script error: cannot load " .. url .. ": " .. tostring(err) .. "]", true); return end
    code, name = body, url:match("[^/]*$")
  else
    code, name = D.textOf(n), "inline script"
  end
  if ty == "module" then code = code:gsub("\n%s*import%s[^\n]*", "\n"):gsub("^%s*import%s[^\n]*", ""):gsub("\n%s*export%s+default%s", "\n"):gsub("\n%s*export%s+", "\n") end
  local saved = p.curScript
  p.curScript = n
  p:runJS(code, name)
  p.curScript = saved
end

-- form fields get their state from their attributes
function Page:prepareForms(root)
  local function prep(e)
    if e.tag == "input" then
      local t = (e.attrs.type or ""):lower()
      if (t == "checkbox" or t == "radio") and e.checked == nil then e.checked = e.attrs.checked ~= nil end
    elseif e.tag == "select" and e.selectedIndex == nil then
      local i = 0
      e.selectedIndex = 0
      for _, o in ipairs(D.byTag(e, "option")) do
        if o.attrs.selected ~= nil then e.selectedIndex = i end
        i = i + 1
      end
    end
  end
  if root.type == "el" then prep(root) end
  D.walk(root, function(e) prep(e) end)
end

function Page:docWrite(html)
  local f = D.fragment(html)
  local s = self.curScript
  if s and s.parent and self.readyState == "loading" then
    local nx
    local list = { table.unpack(f.kids) }
    local i = D.indexIn(s.parent, s)
    nx = s.parent.kids[i + 1]
    D.insert(s.parent, f, nx)
    self:prepareForms(s.parent)
    for _, k in ipairs(list) do
      if k.type == "el" then for _, sc in ipairs(k.tag == "script" and { k } or D.byTag(k, "script")) do runScriptNode(self, sc) end end
    end
  else
    -- after the load, document.write starts a new page in the same window
    local body = self.doc.body
    for _, k in ipairs(body.kids) do k.parent = nil end
    body.kids = {}
    D.insert(body, f)
    self:prepareForms(body)
  end
  changed(true)
  self.needImages = true
end

-- ---------------------------------------------------------------- the global objects of the page
local function storageObject(p)
  local data, order = {}, {}
  local path = p.host.storage and p.host.storage(p.origin)
  if path and p.host.readFile then
    local text = p.host.readFile(path)
    if text then
      for line in text:gmatch("[^\n]+") do
        local k, v = line:match("^(.-)\t(.*)$")
        if k then
          local function un(s) return (s:gsub("\\(.)", { n = "\n", t = "\t", ["\\"] = "\\" })) end
          k, v = un(k), un(v)
          if data[k] == nil then order[#order + 1] = k end
          data[k] = v
        end
      end
    end
  end
  local function save()
    if not (path and p.host.writeFile) then return end
    local out = {}
    for _, k in ipairs(order) do
      local function esc(s) return (s:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t")) end
      if data[k] ~= nil then out[#out + 1] = esc(k) .. "\t" .. esc(data[k]) end
    end
    p.host.writeFile(path, table.concat(out, "\n") .. "\n")
  end
  local s = obj()
  R.set(s, "getItem", native("getItem", function(_, k) local v = data[str(k)]; if v == nil then return null end return v end))
  R.set(s, "setItem", native("setItem", function(_, k, v)
    k = str(k)
    if data[k] == nil then order[#order + 1] = k end
    data[k] = str(v)
    save()
  end))
  R.set(s, "removeItem", native("removeItem", function(_, k)
    k = str(k)
    if data[k] == nil then return end
    data[k] = nil
    for i, x in ipairs(order) do if x == k then table.remove(order, i); break end end
    save()
  end))
  R.set(s, "clear", native("clear", function() data, order = {}, {}; save() end))
  R.set(s, "key", native("key", function(_, i) return order[floor(num(i)) + 1] or null end))
  rawset(s, "length", accessor(function() return #order + 0.0 end))
  return s
end

local function locationObject(p)
  local loc = obj()
  local function part(f) return accessor(function() return f(p.url or "") end, function(_, v) p:navigate(str(v)) end) end
  rawset(loc, "href", part(function(u) return u:find("://") and u or ("file://" .. u) end))
  rawset(loc, "protocol", accessor(function() local s = (p.url or ""):match("^(%a+:)//"); return s or "file:" end))
  rawset(loc, "host", accessor(function() return (p.url or ""):match("^%a+://([^/]*)") or "" end))
  rawset(loc, "hostname", accessor(function() return ((p.url or ""):match("^%a+://([^/:]*)") or "") end))
  rawset(loc, "origin", accessor(function() return p.origin or "null" end))
  rawset(loc, "pathname", accessor(function() local u = (p.url or ""):gsub("[?#].*$", ""); return u:match("^%a+://[^/]*(/.*)$") or (u:find("://") and "/" or u) end))
  rawset(loc, "search", accessor(function() return (p.url or ""):match("(%?[^#]*)") or "" end))
  rawset(loc, "hash", accessor(function() return (p.url or ""):match("(#.*)$") or "" end, function(_, v)
    p.url = (p.url or ""):gsub("#.*$", "") .. "#" .. str(v):gsub("^#", "")
    fire(p, p.win, newEvent("hashchange"))
  end))
  R.set(loc, "assign", native("assign", function(_, u) p:navigate(str(u)) end))
  R.set(loc, "replace", native("replace", function(_, u) p:navigate(str(u)) end))
  R.set(loc, "reload", native("reload", function() p.navTo = { url = p.url, reload = true } end))
  R.set(loc, "toString", native("toString", function() return p.url or "" end))
  return loc
end

function Page:makeEnv()
  local p = self
  local env = {}
  self.env = env
  local win = { isWindow = true, listeners = {}, type = "window" }
  self.win = win
  -- window: its properties are the globals of the page
  local winAcc = {}
  local window = setmetatable({}, { __index = function(_, k)
    if type(k) ~= "string" then return nil end
    local a = winAcc[k]
    if not a then
      a = accessor(function() local v = rawget(env, k); if v == nil then v = G[k] end return v end, function(_, v) rawset(env, k, v) end)
      winAcc[k] = a
    end
    return a
  end, proto = R.protoOf(CTORS.Node) })
  W2N[window] = win
  win.js = window
  self.window = window
  local function fn(name, f) env[name] = native(name, f) end
  env.window, env.self, env.globalThis, env.top, env.parent, env.frames = window, window, window, window, window, window
  env.document = wrap(self.doc)
  env.innerWidth, env.innerHeight = self.vw + 0.0, self.vh + 0.0
  env.outerWidth, env.outerHeight = self.vw + 0.0, self.vh + 0.0
  env.devicePixelRatio = 1.0
  env.screen = obj({ { "width", self.vw + 0.0 }, { "height", self.vh + 0.0 }, { "availWidth", self.vw + 0.0 }, { "availHeight", self.vh + 0.0 } })
  env.navigator = obj({ { "userAgent", "Mozilla/5.0 (arch-esp; ESP32-P4) html-player/1.0" }, { "language", "en-US" }, { "languages", arr({ "en-US" }) },
    { "platform", "ESP32-P4" }, { "onLine", true }, { "maxTouchPoints", 5.0 }, { "cookieEnabled", true } })
  rawset(env, "scrollX", nil)
  -- console
  local console = obj()
  local function logFn(prefix, isErr)
    return native("log", function(_, ...)
      local parts = {}
      local n = select("#", ...)
      for i = 1, n do
        local v = select(i, ...)
        if type(v) == "string" then parts[#parts + 1] = v else
          local ok, s = pcall(R.inspect, v)
          parts[#parts + 1] = ok and s or tostring(v)
        end
      end
      local first = parts[1]
      -- %s and %d in the first argument
      if type(first) == "string" and first:find("%%[sdifo]") and n > 1 then
        local i = 1
        first = first:gsub("%%[sdifoO]", function() i = i + 1; local x = parts[i]; parts[i] = false; return x or "" end)
        local rest = { first }
        for j = 2, #parts do if parts[j] then rest[#rest + 1] = parts[j] end end
        parts = rest
      end
      p:log(prefix .. table.concat(parts, " "), isErr)
    end)
  end
  R.set(console, "log", logFn("", false))
  R.set(console, "info", logFn("", false))
  R.set(console, "debug", logFn("", false))
  R.set(console, "warn", logFn("warning: ", false))
  R.set(console, "error", logFn("error: ", true))
  R.set(console, "table", logFn("", false))
  R.set(console, "dir", logFn("", false))
  R.set(console, "trace", logFn("trace: ", false))
  R.set(console, "assert", native("assert", function(_, c, ...) if not R.T(c) then console.error(nil, "Assertion failed:", ...) end end))
  R.set(console, "clear", native("clear", function() p.logLines = {} end))
  R.set(console, "time", native("time", function() end))
  R.set(console, "timeEnd", native("timeEnd", function() end))
  R.set(console, "group", native("group", function() end))
  R.set(console, "groupEnd", native("groupEnd", function() end))
  env.console = console
  -- timers from the loop of the program
  local function addTimer(f, ms, every, args)
    if type(f) == "string" then local code = f; f = function() p:runJS(code, "timer") end end
    if type(f) ~= "function" then return 0.0 end
    p.timerSeq = p.timerSeq + 1
    ms = tonumber(ms) or R.num(ms or 0)
    if ms ~= ms or ms < 0 then ms = 0 end
    local t = { id = p.timerSeq + 0.0, at = p:now() + ms, f = f, every = every and max(ms, 4) or nil, args = args }
    p.timers[#p.timers + 1] = t
    return t.id
  end
  local function clear(_, id)
    for i, t in ipairs(p.timers) do if t.id == id then table.remove(p.timers, i); return end end
  end
  fn("setTimeout", function(_, f, ms, ...) return addTimer(f, ms, false, { ... }) end)
  fn("setInterval", function(_, f, ms, ...) return addTimer(f, ms, true, { ... }) end)
  fn("clearTimeout", clear)
  fn("clearInterval", clear)
  fn("requestAnimationFrame", function(_, f)
    p.rafSeq = p.rafSeq + 1
    p.rafs[#p.rafs + 1] = { id = p.rafSeq + 0.0, f = f }
    return p.rafSeq + 0.0
  end)
  fn("cancelAnimationFrame", function(_, id) for i, r in ipairs(p.rafs) do if r.id == id then table.remove(p.rafs, i); return end end end)
  fn("queueMicrotask", function(_, f) R.M(R.M(G.Promise, "resolve"), "then", f) end)
  env.performance = obj({ { "now", native("now", function() return (p:now() - (p.t0 or 0)) + 0.0 end) }, { "timeOrigin", 0.0 } })
  -- dialogs
  fn("alert", function(_, msg) if p.host.alert then p.host.alert("alert", msg == nil and "" or str(msg)) end end)
  fn("confirm", function(_, msg) if p.host.alert then return p.host.alert("confirm", str(msg or "")) == true end return false end)
  fn("prompt", function(_, msg, def)
    if not p.host.alert then return null end
    local r = p.host.alert("prompt", str(msg or ""), def ~= nil and def ~= null and str(def) or "")
    if r == nil then return null end
    return r
  end)
  -- events on the window
  fn("addEventListener", function(_, kind, f, opts) METHODS.addEventListener(window, kind, f, opts) end)
  fn("removeEventListener", function(_, kind, f) METHODS.removeEventListener(window, kind, f) end)
  fn("dispatchEvent", function(_, e) return fire(p, win, e) end)
  fn("getComputedStyle", function(_, el)
    local n = nodeOf(el)
    p:layout()
    local cs = n.cs or {}
    local o = obj()
    local b = L.boxOf(p.root, n)
    for k, v in pairs(cs) do
      if type(k) == "string" and type(v) == "string" then R.set(o, k, v); R.set(o, camel(k), v) end
    end
    R.set(o, "fontSize", floor(cs.fs or 16) .. "px"); R.set(o, "font-size", floor(cs.fs or 16) .. "px")
    R.set(o, "display", cs.display or "inline")
    local c = cs.fg or 0
    R.set(o, "color", string.format("rgb(%d, %d, %d)", (c >> 16) & 255, (c >> 8) & 255, c & 255))
    if b then R.set(o, "width", floor(b.cw or 0) .. "px"); R.set(o, "height", floor(b.ch or 0) .. "px") end
    R.set(o, "getPropertyValue", native("getPropertyValue", function(this, k) local v = R.get(this, str(k)); if v == nil then return "" end return v end))
    return o
  end)
  fn("matchMedia", function(_, q)
    local m = C.media(str(q), { vw = p.vw, vh = p.vh })
    return obj({ { "matches", m }, { "media", str(q) }, { "addListener", native("addListener", function() end) },
      { "addEventListener", native("addEventListener", function() end) }, { "removeEventListener", native("removeEventListener", function() end) } })
  end)
  fn("scrollTo", function(_, x, y) if type(x) == "table" and x ~= null then y = R.get(x, "top") end p:scrollTo(num(y or 0)) end)
  fn("scroll", function(_, x, y) if type(x) == "table" and x ~= null then y = R.get(x, "top") end p:scrollTo(num(y or 0)) end)
  fn("scrollBy", function(_, x, y) if type(x) == "table" and x ~= null then y = R.get(x, "top") end p:scrollTo(p.sy + num(y or 0)) end)
  rawset(env, "scrollY", nil)
  fn("focus", function() end)
  fn("blur", function() end)
  fn("print", function() end)
  fn("open", function(_, u) if u then p:navigate(str(u)) end return null end)
  fn("close", function() p.navTo = { quit = true } end)
  fn("atob", function(_, s)
    s = str(s):gsub("[^%w%+/=]", "")
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    return (s:gsub(".", function(x) if x == "=" then return "" end local r, f = "", (b:find(x, 1, true) - 1) for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0") end return r end)
      :gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x) if #x ~= 8 then return "" end local c = 0 for i = 1, 8 do c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0) end return string.char(c) end))
  end)
  fn("btoa", function(_, s)
    s = str(s)
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    return ((s:gsub(".", function(x) local r, bb = "", x:byte() for i = 8, 1, -1 do r = r .. (bb % 2 ^ i - bb % 2 ^ (i - 1) > 0 and "1" or "0") end return r end) .. "0000")
      :gsub("%d%d%d?%d?%d?%d?", function(x) if #x < 6 then return "" end local c = 0 for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end return b:sub(c + 1, c + 1) end)
      .. ({ "", "==", "=" })[#s % 3 + 1])
  end)
  -- storage, location, history
  env.localStorage = storageObject(p)
  local sess = obj()
  do
    local d = {}
    R.set(sess, "getItem", native("getItem", function(_, k) local v = d[str(k)]; if v == nil then return null end return v end))
    R.set(sess, "setItem", native("setItem", function(_, k, v) d[str(k)] = str(v) end))
    R.set(sess, "removeItem", native("removeItem", function(_, k) d[str(k)] = nil end))
    R.set(sess, "clear", native("clear", function() d = {} end))
  end
  env.sessionStorage = sess
  self.locationObj = locationObject(p)
  env.location = self.locationObj
  env.history = obj({ { "length", 1.0 }, { "state", null },
    { "back", native("back", function() p.navTo = { back = true } end) },
    { "forward", native("forward", function() end) },
    { "go", native("go", function(_, n) if num(n or 0) < 0 then p.navTo = { back = true } end end) },
    { "pushState", native("pushState", function(_, st, t, u) if u ~= nil and u ~= null then p.url = p:abs(str(u)) end end) },
    { "replaceState", native("replaceState", function(_, st, t, u) if u ~= nil and u ~= null then p.url = p:abs(str(u)) end end) } })
  -- fetch: the request is made from the loop (so the page is drawn first); text() and json() give promises
  fn("fetch", function(_, input, init)
    local url = type(input) == "table" and input ~= null and str(R.get(input, "url")) or str(input)
    url = p:abs(url)
    local method, body, headers = "GET", nil, nil
    if type(init) == "table" and init ~= null then
      method = str(R.get(init, "method") or "GET"):upper()
      local b = R.get(init, "body")
      if b ~= nil and b ~= null then body = str(b) end
      local h = R.get(init, "headers")
      if type(h) == "table" and h ~= null then
        headers = {}
        local ok, keys = pcall(R.M, G.Object, "keys", h)
        if ok then for i = 1, R.len(keys) do local k = R.get(keys, i - 1.0); headers[k] = str(R.get(h, k)) end end
      end
    end
    local resolveF, rejectF
    local promise = R.new(G.Promise, function(_, res, rej) resolveF, rejectF = res, rej end)
    p.fetches[#p.fetches + 1] = { url = url, method = method, body = body, headers = headers, res = resolveF, rej = rejectF }
    return promise
  end)
  env.XMLHttpRequest = nil
  -- constructors
  local function evCtor(name)
    local f = native(name, function(this, kind, init)
      local e = newEvent(str(kind))
      if type(init) == "table" and init ~= null then
        local ok, keys = pcall(R.M, G.Object, "keys", init)
        if ok then for i = 1, R.len(keys) do local k = R.get(keys, i - 1.0); R.set(e, k, R.get(init, k)) end end
      end
      R.set(e, "isTrusted", false)
      if R.get(e, "bubbles") == nil then R.set(e, "bubbles", false) end
      return e
    end)
    R.protoOf(f)
    return f
  end
  local Event = evCtor("Event")
  -- `new Event(...)` calls the native constructor and returns the object it makes
  for _, name in ipairs({ "Event", "CustomEvent", "KeyboardEvent", "MouseEvent", "TouchEvent", "InputEvent", "FocusEvent", "PointerEvent", "UIEvent" }) do
    local f = name == "Event" and Event or evCtor(name)
    local info = { native = function(kind, init)
      local e = newEvent(str(kind))
      R.set(e, "bubbles", false)
      R.set(e, "isTrusted", false)
      if type(init) == "table" and init ~= null then
        local ok, keys = pcall(R.M, G.Object, "keys", init)
        if ok then for i = 1, R.len(keys) do local k = R.get(keys, i - 1.0); R.set(e, k, R.get(init, k)) end end
      end
      return e
    end }
    R.set(f, "native", nil)
    env[name] = f
    H.setNative(f, info.native)
  end
  env.Image = native("Image", function() end)
  H.setNative(env.Image, function(w, h)
    local n = D.el("img")
    if w then D.setAttr(n, "width", R.tostr(w)) end
    if h then D.setAttr(n, "height", R.tostr(h)) end
    return wrap(n)
  end)
  env.Audio = native("Audio", function() end)
  H.setNative(env.Audio, function() return wrap(D.el("audio")) end)
  for name, f in pairs(CTORS) do env[name] = f end
  env.HTMLElement = CTORS.HTMLElement
  -- what a page may not reach: the modules of node and the device API
  local hidden = { require = true, process = true, module = true, exports = true, __filename = true, __dirname = true, Buffer = true }
  setmetatable(env, { __index = function(_, k)
    if hidden[k] then return nil end
    local v = G[k]
    if v ~= nil then return v end
    if p.declared[k] or k == "_ENV" then return nil end
    if k == "scrollY" or k == "pageYOffset" then return p.sy + 0.0 end
    if k == "scrollX" or k == "pageXOffset" then return 0.0 end
    if k:sub(1, 2) == "on" then return nil end
    -- an element with an id is a global too (like in browsers)
    local n = p.doc and D.byId(p.doc, k)
    if n then return wrap(n) end
    R.throw(R.new(G.ReferenceError, tostring(k) .. " is not defined"))
  end })
end
-- `new X()` of a native constructor runs F instead (jsrt keeps this in the function's properties)
function H.setNative(f, impl)
  -- jsrt.new looks at FP[c].native; FP is reached through R.set on the function (it keeps function properties there)
  R.set(f, "native", impl)
end

-- ---------------------------------------------------------------- loading
function Page:load(url)
  current = self
  self.url = url
  self.t0 = self:now()
  local scheme, host = url:match("^(%a+)://([^/]+)")
  self.origin = scheme and (scheme .. "://" .. host) or ("file://" .. (url:match("^(.*)/[^/]*$") or "."))
  local src, err = self:read(url)
  if not src then
    src = "<html><head><title>Error</title></head><body style='font-family:sans-serif;padding:20px'><h2>This page cannot be shown</h2><p>"
      .. D.serialize(D.txt(url)) .. "</p><p style='color:#a00'>" .. D.serialize(D.txt(tostring(err))) .. "</p><p>Backspace goes back, Ctrl+Q quits.</p></body></html>"
    self.failed = true
  end
  if #src > 2 * 1024 * 1024 then src = src:sub(1, 2 * 1024 * 1024) end
  self.doc = D.parse(src)
  local base = D.byTag(self.doc.head, "base")[1]
  if base and base.attrs.href then self.base = H.resolve(url, base.attrs.href) end
  self:prepareForms(self.doc)
  self:makeEnv()
  self.readyState = "loading"
  -- the scripts in the order of the page
  local scripts = D.byTag(self.doc, "script")
  local deferred = {}
  for _, s in ipairs(scripts) do
    if s.attrs.defer ~= nil and s.attrs.src then deferred[#deferred + 1] = s else runScriptNode(self, s) end
  end
  for _, s in ipairs(deferred) do runScriptNode(self, s) end
  self.readyState = "interactive"
  fire(self, self.doc, newEvent("DOMContentLoaded"))
  self.readyState = "complete"
  local e = newEvent("load")
  R.set(e, "bubbles", false)
  fire(self, self.win, e)
  self.needMatch, self.needStyle = true, true
  self.needImages = true
  -- an anchor in the address
  local hash = url:match("#(.+)$")
  if hash then self.scrollToId = hash end
  self:layout()
  if self.scrollToId then
    local n = D.byId(self.doc, self.scrollToId)
    local b = n and L.boxOf(self.root, n)
    if b then self:scrollTo(b.y) end
    self.scrollToId = nil
  end
end

-- the style sheets of the page in their order: the browser's, then <style> and <link rel=stylesheet>
function Page:sheets()
  local list = { C.ua() }
  local p = self
  local function addCss(text, base, media)
    local key = (base or "") .. "\0" .. text
    local sh = p.cssCache[key]
    if not sh then
      sh = C.parse(text, media)
      for _, imp in ipairs(sh.imports) do
        local u = H.resolve(base or p.url, imp)
        local body = p:read(u)
        if body then
          local sub = C.parse(body)
          for _, r in ipairs(sh.rules) do sub.rules[#sub.rules + 1] = r end
          sh = sub
        end
      end
      p.cssCache[key] = sh
    end
    list[#list + 1] = sh
  end
  D.walk(self.doc, function(e)
    if e.tag == "style" then
      local m = e.attrs.media
      if not m or C.media(m, { vw = p.vw, vh = p.vh }) then addCss(D.textOf(e), nil) end
    elseif e.tag == "link" and (e.attrs.rel or ""):lower():find("stylesheet") and e.attrs.href then
      local u = p:abs(e.attrs.href)
      local m = e.attrs.media
      if not m or C.media(m, { vw = p.vw, vh = p.vh }) then
        local text = p.cssCache["link:" .. u]
        if text == nil then text = p:read(u) or false; p.cssCache["link:" .. u] = text end
        if text then addCss(text, u) end
      end
    end
  end)
  return list
end

-- the style and the boxes, when something changed
function Page:layout()
  if not self.doc then return end
  if not (self.needMatch or self.needStyle or self.needLayout or not self.root) then return end
  local saved = current
  current = self
  local sheets = self:sheets()
  local same = self.lastSheets and #self.lastSheets == #sheets
  if same then for i, s in ipairs(sheets) do if self.lastSheets[i] ~= s then same = false end end end
  if not same then self.idx = nil; self.needMatch = true end
  self.lastSheets = sheets
  local env = { vw = self.vw, vh = self.vh }
  if self.needMatch or not self.idx then
    C.gen = C.gen + 1
    self.idx = C.index(sheets, env)
  end
  if self.needMatch or self.needStyle or not self.root then
    C.focused = self.focus
    C.compute(self.doc, sheets, env, self.idx)
  end
  local h = self.host
  self.root = L.layout(self.doc, { vw = self.vw, vh = self.vh, measure = h.measure, fontOf = h.fontOf, fontHeight = h.fontHeight,
    intrinsic = function(n) if n.tag == "img" and n.attrs.src and h.intrinsic then return h.intrinsic(n, self:abs(n.attrs.src)) end end })
  self.needMatch, self.needStyle, self.needLayout = false, false, false
  self.needPaint = true
  self.docH = self.root.docH or self.vh
  self:scrollTo(self.sy)
  current = saved
end

function Page:scrollTo(y)
  local maxY = max(0, (self.docH or 0) - self.vh)
  y = max(0, min(maxY, y or 0))
  if y ~= self.sy then
    self.sy = y
    self.needPaint = true
    if self.win then fire(self, self.win, newEvent("scroll")) end
  end
end

-- draws the page with the drawing API (see htmlpaint); RECT limits it to a part of the screen
function Page:paint(api, rect, caret)
  self:layout()
  P.paint(self.root, { api = api, sy = self.sy, vw = self.vw, vh = self.vh, rect = rect, focus = self.focus, caret = caret,
    fontOf = self.host.fontOf, url = function(u) return self:abs(u) end })
  self.needPaint = false
  self.canvasDirty = {}
end
-- the screen rectangle of the canvases that changed (nil when the page needs a full drawing)
function Page:dirtyRect()
  if self.needPaint or self.needMatch or self.needStyle or self.needLayout then return nil, true end
  local x0, y0, x1, y1
  for n in pairs(self.canvasDirty) do
    local b = self.root and L.boxOf(self.root, n)
    if b then
      local y = b.y - (b.fixed and 0 or self.sy)
      x0, y0 = min(x0 or b.x, b.x), min(y0 or y, y)
      x1, y1 = max(x1 or 0, b.x + b.w), max(y1 or 0, y + b.h)
    end
  end
  if not x0 then return nil, false end
  x0, y0 = max(0, floor(x0)), max(0, floor(y0))
  x1, y1 = min(self.vw, math.ceil(x1)), min(self.vh, math.ceil(y1))
  if x1 <= x0 or y1 <= y0 then self.canvasDirty = {}; return nil, false end
  return { x0, y0, x1 - x0, y1 - y0 }, true
end

-- ---------------------------------------------------------------- the event loop (called by the program about 30 times a second)
function Page:tick(now)
  current = self
  now = now or self:now()
  -- network requests of fetch()
  local fetches = self.fetches
  self.fetches = {}
  for _, f in ipairs(fetches) do
    local body, status, err
    if self.host.request then body, status, err = self.host.request(f.url, f.method, f.body, f.headers)
    else body, err = self:read(f.url); status = body and 200 or nil end
    if not body and not status then
      callJS(self, f.rej, nil, R.new(G.TypeError, "Failed to fetch" .. (err and (": " .. tostring(err)) or "")))
    else
      body = body or ""
      local resp = obj()
      R.set(resp, "ok", status >= 200 and status < 300)
      R.set(resp, "status", status + 0.0)
      R.set(resp, "statusText", status == 200 and "OK" or "")
      R.set(resp, "url", f.url)
      R.set(resp, "headers", obj({ { "get", native("get", function() return null end) } }))
      R.set(resp, "text", native("text", function() return R.M(G.Promise, "resolve", body) end))
      R.set(resp, "json", native("json", function()
        return R.new(G.Promise, function(_, res, rej)
          local ok, v = pcall(R.M, G.JSON, "parse", body)
          if ok then res(nil, v) else rej(nil, R.catch(v)) end
        end)
      end))
      callJS(self, f.res, nil, resp)
    end
  end
  local loads = self.pendingLoads
  self.pendingLoads = {}
  for _, n in ipairs(loads) do
    local e = newEvent("load"); R.set(e, "bubbles", false)
    fire(self, n, e)
  end
  -- timers that are due (a few at a time, so a page cannot stop the loop)
  local ran = 0
  while ran < 64 do
    local best
    for i, t in ipairs(self.timers) do
      if t.at <= now and (not best or t.at < self.timers[best].at or (t.at == self.timers[best].at and t.id < self.timers[best].id)) then best = i end
    end
    if not best then break end
    local t = self.timers[best]
    if t.every then t.at = max(t.at + t.every, now - t.every) else table.remove(self.timers, best) end
    callJS(self, t.f, nil, table.unpack(t.args or {}))
    drain(self)
    ran = ran + 1
  end
  -- animation frames: the callbacks asked for before this frame
  if #self.rafs > 0 then
    local list = self.rafs
    self.rafs = {}
    local ts = (now - (self.t0 or 0)) + 0.0
    for _, r in ipairs(list) do callJS(self, r.f, nil, ts) end
    drain(self)
  end
  drain(self)
end
function Page:busy()
  return #self.timers > 0 or #self.rafs > 0 or #self.fetches > 0 or #self.pendingLoads > 0
end
-- when the next timer wants to run (ms from now), for the sleep of the loop
function Page:nextDue(now)
  if #self.rafs > 0 or #self.fetches > 0 or #self.pendingLoads > 0 then return 0 end
  local best
  for _, t in ipairs(self.timers) do best = min(best or 1e9, t.at - now) end
  return best
end

-- ---------------------------------------------------------------- focus, clicks, forms
function H.focusable(n)
  if not n or n.type ~= "el" then return false end
  if n.attrs.disabled ~= nil then return false end
  local t = n.tag
  if t == "a" and n.attrs.href then return true end
  if t == "button" or t == "select" or t == "textarea" or t == "summary" then return true end
  if t == "input" and (n.attrs.type or ""):lower() ~= "hidden" then return true end
  if n.attrs.tabindex and tonumber(n.attrs.tabindex) and tonumber(n.attrs.tabindex) >= 0 then return true end
  if n.attrs.contenteditable then return true end
  return false
end
local function isTextField(n)
  if not n or n.type ~= "el" then return false end
  if n.tag == "textarea" then return true end
  if n.tag ~= "input" then return n.attrs.contenteditable ~= nil end
  local t = (n.attrs.type or "text"):lower()
  return t == "text" or t == "password" or t == "email" or t == "number" or t == "search" or t == "tel" or t == "url" or t == "date" or t == "time"
end
H.isTextField = isTextField
function Page:setFocus(n)
  if n == self.focus then return end
  local old = self.focus
  if old then old.focus = nil end
  self.focus = n
  if n then n.focus = true end
  if self.idx and self.idx.focus then self.needMatch = true end
  self.needPaint = true
  if old then
    fire(self, old, newEvent("blur"))
    local e = newEvent("focusout"); fire(self, old, e)
    -- a changed text field sends change when it loses the focus
    if old._changed then old._changed = nil; fire(self, old, newEvent("change")) end
  end
  if n then
    fire(self, n, newEvent("focus"))
    fire(self, n, newEvent("focusin"))
  end
end
function Page:uncheckGroup(n)
  local name = n.attrs.name
  if not name then return end
  local root = n.parent
  while root and root.tag ~= "form" and root.type ~= "doc" do root = root.parent end
  D.walk(root or self.doc, function(e)
    if e ~= n and e.tag == "input" and (e.attrs.type or ""):lower() == "radio" and e.attrs.name == name then e.checked = false end
  end)
end
function Page:navigate(url)
  if url:find("^javascript:") then self:runJS(url:sub(12), "javascript: link"); return end
  local abs = self:abs(url)
  if abs:sub(1, 1) == "#" or (abs:gsub("#.*$", "") == (self.url or ""):gsub("#.*$", "") and abs:find("#")) then
    local id = abs:match("#(.*)$")
    local n = id and id ~= "" and D.byId(self.doc, id)
    self:layout()
    local b = n and L.boxOf(self.root, n)
    self:scrollTo(b and b.y or 0)
    self.url = (self.url or ""):gsub("#.*$", "") .. "#" .. (id or "")
    fire(self, self.win, newEvent("hashchange"))
    return
  end
  self.navTo = { url = abs }
end
-- the values of a form as name=value&... (for GET)
function Page:formQuery(form)
  local parts = {}
  local function enc(s) return (s:gsub("[^%w%-_%.~]", function(c) if c == " " then return "+" end return string.format("%%%02X", c:byte()) end)) end
  D.walk(form, function(e)
    local nm = e.attrs.name
    if not nm or e.attrs.disabled ~= nil then return end
    if e.tag == "input" then
      local t = (e.attrs.type or "text"):lower()
      if (t == "checkbox" or t == "radio") and not e.checked then return end
      if t == "submit" or t == "button" or t == "reset" or t == "file" then return end
    elseif e.tag ~= "select" and e.tag ~= "textarea" then return end
    parts[#parts + 1] = enc(nm) .. "=" .. enc(fieldValue(e))
  end)
  return table.concat(parts, "&")
end
function Page:submitForm(form, noEvent)
  if not noEvent then
    -- fields marked required stop the sending (as in browsers, with a note)
    local missing
    D.walk(form, function(e)
      if not missing and e.attrs.required ~= nil and (e.tag == "input" or e.tag == "textarea" or e.tag == "select") then
        local t = (e.attrs.type or ""):lower()
        if (t == "checkbox" and not e.checked) or (t ~= "checkbox" and fieldValue(e) == "") then missing = e end
      end
    end)
    if missing and form.attrs.novalidate == nil then
      self:setFocus(missing)
      self:log("Please fill out this field: " .. (missing.attrs.name or missing.attrs.id or missing.tag))
      self.toast = "Please fill out this field."
      return
    end
    local e = newEvent("submit")
    if not fire(self, form, e) then return end
  end
  local action = form.attrs.action
  local q = self:formQuery(form)
  local target = self:abs(action or (self.url or ""):gsub("[?#].*$", ""))
  if target:find("^https?://") then
    if (form.attrs.method or "get"):lower() == "get" then target = target:gsub("[?#].*$", "") .. "?" .. q end
    self.navTo = { url = target }
  else
    self.navTo = { url = target:gsub("[?#].*$", ""), reload = true }
  end
end

-- the default action of a click on N (after the click event was not cancelled)
function Page:defaultClick(n, x)
  local e = n
  while e and e.type == "el" do
    local t = e.tag
    if t == "a" and e.attrs.href then
      if e.attrs.download then self:log("download is not supported: " .. e.attrs.href) return end
      self:navigate(e.attrs.href)
      return
    elseif t == "label" then
      local target = e.attrs["for"] and D.byId(self.doc, e.attrs["for"])
      if not target then
        D.walk(e, function(k) if k.tag == "input" or k.tag == "select" or k.tag == "textarea" then target = k; return true end end)
      end
      if target and target ~= n then self:activate(target) end
      return
    elseif t == "summary" then
      local det = e.parent
      if det and det.tag == "details" then
        if det.attrs.open then D.removeAttr(det, "open") else D.setAttr(det, "open", "") end
        changed(true)
        fire(self, det, newEvent("toggle"))
      end
      return
    elseif (t == "button" and (e.attrs.type or "submit"):lower() == "submit") or (t == "input" and (e.attrs.type or ""):lower() == "submit") then
      local f = e.parent
      while f and f.tag ~= "form" do f = f.parent end
      if e.attrs.form then f = D.byId(self.doc, e.attrs.form) end
      if f then self:submitForm(f) end
      return
    elseif t == "button" and (e.attrs.type or ""):lower() == "reset" then
      local f = e.parent
      while f and f.tag ~= "form" do f = f.parent end
      if f then METHODS.reset(wrap(f)) end
      return
    end
    e = e.parent
  end
end
-- a click (or tap, or Enter) on the element N: the state of fields changes first, then the events go out
function Page:activate(n, x, y, noFocus)
  current = self
  if not n or n.type ~= "el" then return end
  if n.attrs.disabled ~= nil then return end
  local t = (n.attrs.type or ""):lower()
  local toggled
  if n.tag == "input" and t == "checkbox" then n.checked = not n.checked; toggled = true
  elseif n.tag == "input" and t == "radio" and not n.checked then n.checked = true; self:uncheckGroup(n); toggled = true
  elseif n.tag == "input" and t == "range" and x then
    local b = self.root and L.boxOf(self.root, n)
    if b then
      local lo, hi = tonumber(n.attrs.min) or 0, tonumber(n.attrs.max) or 100
      local step = tonumber(n.attrs.step) or 1
      local f = max(0, min(1, (x - b.cx) / max(1, b.cw)))
      local v = lo + (hi - lo) * f
      v = lo + floor((v - lo) / step + 0.5) * step
      n.value = R.tostr(v + 0.0)
      fire(self, n, newEvent("input"))
      fire(self, n, newEvent("change"))
    end
  elseif n.tag == "select" then
    local count = #D.byTag(n, "option")
    if count > 0 then
      n.selectedIndex = ((n.selectedIndex or 0) + 1) % count
      fire(self, n, newEvent("input"))
      fire(self, n, newEvent("change"))
    end
  end
  if toggled then changed(true) end
  if noFocus then
  elseif H.focusable(n) or isTextField(n) then self:setFocus(n)
  else
    -- a click on a part of a focusable element (a span in a button) focuses the element
    local f = n.parent
    while f and f.type == "el" and not H.focusable(f) do f = f.parent end
    self:setFocus(f and f.type == "el" and f or nil)
  end
  local b = self.root and L.boxOf(self.root, n)
  local cx, cy = x or (b and b.x + b.w / 2) or 0, y or (b and b.y - self.sy + b.h / 2) or 0
  local e = newEvent("click", { clientX = cx + 0.0, clientY = cy + 0.0, pageX = cx + 0.0, pageY = cy + self.sy + 0.0, button = 0.0, buttons = 0.0,
    offsetX = cx - (b and b.x or 0) + 0.0, offsetY = cy + self.sy - (b and b.y or 0) + 0.0, detail = 1.0 })
  local ok = fire(self, n, e)
  if toggled then
    if not ok then
      -- a cancelled click puts a box back
      if t == "checkbox" then n.checked = not n.checked end
    else
      fire(self, n, newEvent("input"))
      fire(self, n, newEvent("change"))
    end
  end
  if ok then self:defaultClick(n, x) end
  self.needPaint = true
end

local function pointerInit(p, x, y, n, kind)
  local b = p.root and n and L.boxOf(p.root, n)
  local touch = obj({ { "clientX", x + 0.0 }, { "clientY", y + 0.0 }, { "pageX", x + 0.0 }, { "pageY", y + p.sy + 0.0 }, { "identifier", 0.0 },
    { "target", wrap(n) } })
  local list = kind == "touchend" and arr({}) or arr({ touch })
  return { clientX = x + 0.0, clientY = y + 0.0, pageX = x + 0.0, pageY = y + p.sy + 0.0, screenX = x + 0.0, screenY = y + 0.0, button = 0.0,
    buttons = kind:find("up") and 0.0 or 1.0, offsetX = x - (b and b.x or 0) + 0.0, offsetY = y + p.sy - (b and b.y or 0) + 0.0,
    touches = list, targetTouches = list, changedTouches = arr({ touch }), pointerType = "touch", pointerId = 1.0, isPrimary = true }
end
local function hitAt(p, x, y)
  p:layout()
  local n = L.hit(p.root, x, y, p.sy)
  if n and n.type ~= "el" and n.parent then n = n.parent end
  if n and n.pseudo then n = n.parent end
  return n or p.doc.body
end
local function setHover(p, n, on)
  if not (p.idx and p.idx.hover) then return end
  local e = n
  while e and e.type == "el" do e.hover, e.active = on or nil, on or nil; e = e.parent end
  p.needMatch = true
end
-- the finger (or the pointer) goes down, moves and is lifted, in screen pixels
function Page:down(x, y)
  current = self
  local n = hitAt(self, x, y)
  self.press = { x = x, y = y, n = n, sy = self.sy, moved = false }
  -- what scrolls when the finger drags: the nearest box that can scroll, or the page
  local b
  local function find(box, oy)
    if box.fixed then oy = 0 end
    if x >= box.x and x < box.x + box.w and y + oy >= box.y and y + oy < box.y + box.h then
      if box.scrollable then b = box end
    elseif box.clip then return end
    local ky = oy + (box.clip and (box.sy or 0) or 0)
    for _, k in ipairs(box.kids) do find(k, ky) end
  end
  if self.root then find(self.root, self.sy) end
  self.press.scroller = b
  self.press.st0 = b and (b.n.scrollTop or 0)
  setHover(self, n, true)
  fire(self, n, newEvent("pointerdown", pointerInit(self, x, y, n, "pointerdown")))
  local ok = fire(self, n, newEvent("touchstart", pointerInit(self, x, y, n, "touchstart")))
  if ok then fire(self, n, newEvent("mousedown", pointerInit(self, x, y, n, "mousedown"))) else self.press.noMouse = true end
  self.needPaint = true
end
function Page:move(x, y)
  current = self
  local pr = self.press
  if not pr then return end
  local dy = y - pr.y
  if not pr.moved and (math.abs(dy) > 10 or math.abs(x - pr.x) > 10) then pr.moved = true end
  local n = pr.n
  local okT = fire(self, n, newEvent("touchmove", pointerInit(self, x, y, n, "touchmove")))
  fire(self, n, newEvent("pointermove", pointerInit(self, x, y, n, "pointermove")))
  if not pr.noMouse then fire(self, n, newEvent("mousemove", pointerInit(self, x, y, n, "mousemove"))) end
  -- a drag scrolls, unless the page took the move (a game on a canvas)
  if pr.moved and okT and not (n and (n.tag == "canvas" or (n.tag == "input" and (n.attrs.type or "") == "range"))) then
    if pr.scroller then
      local sb = pr.scroller
      local maxS = max(0, (sb.scrollH or 0) - (sb.ch or 0))
      sb.n.scrollTop = max(0, min(maxS, pr.st0 - dy))
      self.needLayout = true
    else
      self:scrollTo(pr.sy - dy)
    end
  end
end
function Page:up(x, y)
  current = self
  local pr = self.press
  self.press = nil
  if not pr then return end
  local n = pr.n
  setHover(self, n, false)
  fire(self, n, newEvent("pointerup", pointerInit(self, x, y, n, "pointerup")))
  local ok = fire(self, n, newEvent("touchend", pointerInit(self, x, y, n, "touchend")))
  if not pr.noMouse and ok then fire(self, n, newEvent("mouseup", pointerInit(self, x, y, n, "mouseup"))) end
  if not pr.moved then self:activate(n, x, y) end
  self.needPaint = true
end
-- a tap at once (down and up at the same point)
function Page:tap(x, y)
  self:down(x, y)
  self:up(x, y)
end

-- ---------------------------------------------------------------- keys
local KEYS = { enter = { "Enter", "Enter", 13 }, backspace = { "Backspace", "Backspace", 8 }, tab = { "Tab", "Tab", 9 }, esc = { "Escape", "Escape", 27 },
  escape = { "Escape", "Escape", 27 }, up = { "ArrowUp", "ArrowUp", 38 }, down = { "ArrowDown", "ArrowDown", 40 }, left = { "ArrowLeft", "ArrowLeft", 37 },
  right = { "ArrowRight", "ArrowRight", 39 }, [" "] = { " ", "Space", 32 }, space = { " ", "Space", 32 }, del = { "Delete", "Delete", 46 },
  delete = { "Delete", "Delete", 46 }, pageup = { "PageUp", "PageUp", 33 }, pagedown = { "PageDown", "PageDown", 34 }, home = { "Home", "Home", 36 },
  ["end"] = { "End", "End", 35 } }
function H.keyInfo(k)
  local ctrl = false
  if k:sub(1, 5) == "ctrl-" and #k > 5 then ctrl = true; k = k:sub(6) end
  local info = KEYS[k]
  if info then return info[1], info[2], info[3], ctrl, false end
  if #k == 1 or (utf8.len(k) == 1) then
    local code
    if k:match("^%a$") then code = "Key" .. k:upper()
    elseif k:match("^%d$") then code = "Digit" .. k
    else code = k end
    local kc = k:match("^%a$") and k:upper():byte() or k:byte()
    return k, code, kc, ctrl, k:match("^%u$") ~= nil
  end
  return k, k, 0, ctrl, false
end
local function utf8sub(s, i, j)
  local a = utf8.offset(s, i) or (#s + 1)
  local b = j and ((utf8.offset(s, j + 1) or (#s + 1)) - 1) or #s
  return s:sub(a, b)
end
-- a key from the keyboard; returns "back" when the page asks to go back (Backspace or b outside a field), "scroll" when it scrolled
function Page:key(k)
  current = self
  local key, code, kc, ctrl, shift = H.keyInfo(k)
  local target = self.focus or self.doc.body
  local init = { key = key, code = code, keyCode = kc + 0.0, which = kc + 0.0, charCode = (#key == 1 and key:byte() or 0) + 0.0, ctrlKey = ctrl,
    shiftKey = shift, altKey = false, metaKey = false, ["repeat"] = false }
  local ok = fire(self, target, newEvent("keydown", init))
  if ok and (#key == 1 or key == "Enter") and not ctrl then ok = fire(self, target, newEvent("keypress", init)) end
  -- no release comes from the keyboard: keyup goes right after
  fire(self, target, newEvent("keyup", init))
  self.needPaint = true
  if not ok then return "handled" end
  local f = self.focus
  if isTextField(f) then
    local v = fieldValue(f)
    local len = utf8.len(v) or #v
    local caret = f.caret or len
    if key == "Backspace" then
      if caret > 0 then f.value = utf8sub(v, 1, caret - 1) .. utf8sub(v, caret + 1); f.caret = caret - 1; f._changed = true; fire(self, f, newEvent("input", { inputType = "deleteContentBackward" })) end
      changed(false)
      return "handled"
    elseif key == "Delete" then
      if caret < len then f.value = utf8sub(v, 1, caret) .. utf8sub(v, caret + 2); f._changed = true; fire(self, f, newEvent("input")) end
      changed(false)
      return "handled"
    elseif key == "ArrowLeft" then f.caret = max(0, caret - 1); return "handled"
    elseif key == "ArrowRight" then f.caret = min(len, caret + 1); return "handled"
    elseif key == "Home" then f.caret = 0; return "handled"
    elseif key == "End" then f.caret = len; return "handled"
    elseif key == "Enter" then
      if f.tag == "textarea" then
        f.value = utf8sub(v, 1, caret) .. "\n" .. utf8sub(v, caret + 1); f.caret = caret + 1; f._changed = true
        fire(self, f, newEvent("input")); changed(false)
      else
        if f._changed then f._changed = nil; fire(self, f, newEvent("change")) end
        local form = f.parent
        while form and form.tag ~= "form" do form = form.parent end
        if form then
          -- Enter in a field sends the form (through its submit button when there is one)
          local btn
          D.walk(form, function(e)
            if (e.tag == "button" and (e.attrs.type or "submit"):lower() == "submit") or (e.tag == "input" and (e.attrs.type or ""):lower() == "submit") then btn = e; return true end
          end)
          if btn then self:activate(btn, nil, nil, true) else self:submitForm(form) end
        end
      end
      return "handled"
    elseif key == "Tab" or key == "Escape" or key == "ArrowUp" or key == "ArrowDown" then
      -- these leave the text to the rules below
    elseif not ctrl and (#key == 1 or utf8.len(key) == 1) then
      f.value = utf8sub(v, 1, caret) .. key .. utf8sub(v, caret + 1)
      f.caret = caret + 1
      f._changed = true
      fire(self, f, newEvent("input", { data = key, inputType = "insertText" }))
      changed(false)
      return "handled"
    end
  end
  if key == "Tab" then
    local list = {}
    D.walk(self.doc, function(e)
      if H.focusable(e) then
        local hidden = false
        local x = e
        while x and x.type == "el" do if x.cs and x.cs.display == "none" then hidden = true end x = x.parent end
        if not hidden then list[#list + 1] = e end
      end
    end)
    if #list > 0 then
      local i = 0
      for j, e in ipairs(list) do if e == self.focus then i = j end end
      i = shift and i - 1 or i + 1
      if i < 1 then i = #list elseif i > #list then i = 1 end
      self:setFocus(list[i])
      self:layout()
      local b = L.boxOf(self.root, list[i])
      if b and (b.y < self.sy or b.y + b.h > self.sy + self.vh) then self:scrollTo(b.y - self.vh / 3) end
    end
    return "handled"
  end
  if f and (key == "Enter" or key == " ") and not isTextField(f) then
    if f.tag == "select" and key == " " then return "handled" end
    self:activate(f)
    return "handled"
  end
  if f and f.tag == "select" and (key == "ArrowUp" or key == "ArrowDown") then
    local count = #D.byTag(f, "option")
    f.selectedIndex = max(0, min(count - 1, (f.selectedIndex or 0) + (key == "ArrowUp" and -1 or 1)))
    fire(self, f, newEvent("input")); fire(self, f, newEvent("change"))
    changed(false)
    return "handled"
  end
  if f and f.tag == "input" and (f.attrs.type or ""):lower() == "range" and (key == "ArrowLeft" or key == "ArrowRight" or key == "ArrowUp" or key == "ArrowDown") then
    local lo, hi = tonumber(f.attrs.min) or 0, tonumber(f.attrs.max) or 100
    local step = tonumber(f.attrs.step) or 1
    local v = tonumber(fieldValue(f)) or lo
    v = (key == "ArrowLeft" or key == "ArrowDown") and v - step or v + step
    f.value = R.tostr(max(lo, min(hi, v)) + 0.0)
    fire(self, f, newEvent("input")); fire(self, f, newEvent("change"))
    changed(false)
    return "handled"
  end
  if key == "ArrowDown" then self:scrollTo(self.sy + 40); return "scroll" end
  if key == "ArrowUp" then self:scrollTo(self.sy - 40); return "scroll" end
  if key == "PageDown" or (key == " " and not f) then self:scrollTo(self.sy + self.vh - 40); return "scroll" end
  if key == "PageUp" then self:scrollTo(self.sy - self.vh + 40); return "scroll" end
  if key == "Home" then self:scrollTo(0); return "scroll" end
  if key == "End" then self:scrollTo(1e9); return "scroll" end
  if key == "Escape" and f then self:setFocus(nil); return "handled" end
  if key == "Backspace" then return "back" end
  if key == "b" and not hasListeners(self, { "keydown", "keypress", "keyup" }) then return "back" end
  if key == "q" and not hasListeners(self, { "keydown", "keypress", "keyup" }) then return "quit" end
  return nil
end
function Page:hasKeyListeners() return hasListeners(self, { "keydown", "keypress", "keyup" }) end
function Page:isEditing() return isTextField(self.focus) end
return H
