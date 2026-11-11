#!lua
-- htmllayout: the layout engine of the html player (pure Lua). From a styled tree (htmlcss gave each element node.cs) it makes boxes with
-- page coordinates: block and inline flow with text wrapping, inline-block, lists, flexbox, a simple grid, simple tables, replaced elements
-- (img, input, canvas, ...), position relative/absolute/fixed, overflow clipping and scrolling.
--   local L = driver.load("htmllayout")
--   local root = L.layout(doc, env)   env = { vw, vh, measure(text, font) -> w, fontOf(cs) -> font, fontHeight(font) -> h, intrinsic(node) -> w, h }
-- A box: { n = node, cs = style, x, y, w, h (border box), cx, cy, cw, ch (content box), m, bd, pd (edges {t,r,b,l}), kids = {boxes},
--          texts = { {x, y, w, h, s, cs, font, n} }, decos = { {x, y, w, h, cs} }, clip = true when overflow is not visible, sy = scroll }
local L = {}
-- the drivers of the player are loaded once and shared (driver.load makes a new copy each time)
local function need(name)
  local reg = rawget(_G, "HTML_DRIVERS") or {}
  rawset(_G, "HTML_DRIVERS", reg)
  if not reg[name] then reg[name] = assert(driver.load(name)) end
  return reg[name]
end
local C = need("htmlcss")
local floor, max, min = math.floor, math.max, math.min
local INF = 1e9

local function setC(c) C = c end
L.setC = setC

local env = { vw = 800, vh = 480, rem = 16 } -- the environment of the running layout
local function lenOf(v, cs, ref)
  if v == nil or v == "auto" or v == "none" or v == "" or v == "normal" then return nil end
  return C.len(v, { fs = cs.fs, ref = ref, rem = env.rem, vw = env.vw, vh = env.vh })
end
L.lenOf = function(v, cs, ref, e) env = e or env; return lenOf(v, cs, ref) end
local BW = { thin = 1, medium = 3, thick = 5 }
local function bwidth(cs, side)
  local st = cs["border-" .. side .. "-style"]
  if not st or st == "none" or st == "hidden" then return 0 end
  local w = cs["border-" .. side .. "-width"] or "medium"
  return BW[w] or lenOf(w, cs, 0) or 0
end
-- margins (nil = auto), borders, paddings
local function edges(cs, cbw)
  local m = { t = lenOf(cs["margin-top"], cs, cbw), r = lenOf(cs["margin-right"], cs, cbw), b = lenOf(cs["margin-bottom"], cs, cbw), l = lenOf(cs["margin-left"], cs, cbw) }
  m.autoL, m.autoR = cs["margin-left"] == "auto", cs["margin-right"] == "auto"
  m.autoT, m.autoB = cs["margin-top"] == "auto", cs["margin-bottom"] == "auto"
  for _, k in ipairs({ "t", "r", "b", "l" }) do m[k] = m[k] or 0 end
  local bd = { t = bwidth(cs, "top"), r = bwidth(cs, "right"), b = bwidth(cs, "bottom"), l = bwidth(cs, "left") }
  local pd = { t = lenOf(cs["padding-top"], cs, cbw) or 0, r = lenOf(cs["padding-right"], cs, cbw) or 0,
               b = lenOf(cs["padding-bottom"], cs, cbw) or 0, l = lenOf(cs["padding-left"], cs, cbw) or 0 }
  return m, bd, pd
end
L.edges = edges

local REPLACED = { img = true, input = true, select = true, textarea = true, canvas = true, video = true, audio = true, iframe = true, svg = true,
  progress = true, meter = true, object = true, embed = true }
local function isReplaced(n) return n.type == "el" and REPLACED[n.tag] and not (n.tag == "input" and n.attrs.type == "hidden") end
L.isReplaced = isReplaced
local BLOCKLEVEL = { block = true, ["list-item"] = true, flex = true, grid = true, table = true, ["flow-root"] = true, ["table-caption"] = true,
  ["table-row-group"] = true, ["table-header-group"] = true, ["table-footer-group"] = true, ["table-row"] = true, ["table-cell"] = true }
local function display(n)
  if n.type ~= "el" then return "inline" end
  return n.cs and n.cs.display or "inline"
end
local function outOfFlow(n)
  local p = n.cs and n.cs.position
  return p == "absolute" or p == "fixed"
end
local function isBlockLevel(n)
  if n.type ~= "el" then return false end
  local d = display(n)
  return BLOCKLEVEL[d] == true
end
-- the children that take part in layout: ::before, the element and text children, ::after (display: contents is flattened)
local function kidsOf(n)
  local out = {}
  if n.before then out[#out + 1] = n.before end
  for _, k in ipairs(n.kids or {}) do
    if k.type == "text" then out[#out + 1] = k
    elseif k.type == "el" and k.cs and k.cs.display ~= "none" then
      if k.cs.display == "contents" then for _, x in ipairs(kidsOf(k)) do out[#out + 1] = x end
      else out[#out + 1] = k end
    end
  end
  if n.after then out[#out + 1] = n.after end
  return out
end
L.kidsOf = kidsOf

local function newBox(n, cs)
  return { n = n, cs = cs, kids = {}, texts = {}, decos = {}, x = 0, y = 0, w = 0, h = 0 }
end
local function shift(b, dx, dy)
  if dx == 0 and dy == 0 then return end
  b.x, b.y = b.x + dx, b.y + dy
  if b.cx then b.cx, b.cy = b.cx + dx, b.cy + dy end
  if b.baseline then b.baseline = b.baseline + dy end
  if b.markerY then b.markerY = b.markerY + dy end
  for _, t in ipairs(b.texts) do t.x, t.y = t.x + dx, t.y + dy end
  for _, t in ipairs(b.decos) do t.x, t.y = t.x + dx, t.y + dy end
  for _, k in ipairs(b.kids) do shift(k, dx, dy) end
  if b.staticX then b.staticX, b.staticY = b.staticX + dx, b.staticY + dy end
end
L.shift = shift

-- ---------------------------------------------------------------- text
local function transform(s, cs)
  local tt = cs["text-transform"]
  if tt == "uppercase" then return s:upper() elseif tt == "lowercase" then return s:lower()
  elseif tt == "capitalize" then return (s:gsub("(%w)(%w*)", function(a, b) return a:upper() .. b end)) end
  return s
end
local wcache = {}
local function measure(s, font)
  local key = font .. "\0" .. s
  local w = wcache[key]
  if not w then
    w = env.measure(s, font)
    if #s < 40 then wcache[key] = w end
  end
  return w
end
L.measure = function(s, font) return measure(s, font) end
function L.resetCache() wcache = {} end

-- ---------------------------------------------------------------- intrinsic sizes
local pass = 0
local function edgeSum(cs, horizontal)
  local _, bd, pd = edges(cs, 0)
  local m = { l = lenOf(cs["margin-left"], cs, 0) or 0, r = lenOf(cs["margin-right"], cs, 0) or 0 }
  if horizontal then return bd.l + bd.r + pd.l + pd.r + m.l + m.r end
  return bd.t + bd.b + pd.t + pd.b
end
local replacedSize
local function optionText(o)
  local s = o.kids and o.kids[1] and o.kids[1].text or ""
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
L.optionText = optionText
-- the max-content and min-content width of the content of N (not with its own edges)
local function contentWidths(n)
  if n._ipass == pass then return n._imax, n._imin end
  local cs = n.cs
  local mx, mn = 0, 0
  if isReplaced(n) then
    local w = replacedSize(n, nil)
    mx, mn = w, w
  else
    local d = cs.display
    local line, lineMin = 0, 0
    local ws = cs["white-space"] or "normal"
    local flexRow = d == "table-row" or ((d == "flex" or d == "inline-flex") and not (cs["flex-direction"] or "row"):find("column"))
    local font = env.fontOf(cs)
    local sp = measure(" ", font)
    local function flush() mx = max(mx, line); line = 0 end
    for _, k in ipairs(kidsOf(n)) do
      if k.type == "text" then
        local kcs = n.cs
        local f = env.fontOf(kcs)
        local s = transform(k.text, kcs)
        if ws == "pre" or ws == "pre-wrap" or ws == "pre-line" then
          local first = true
          for ln in (s .. "\n"):gmatch("([^\n]*)\n") do
            if not first then flush() end
            first = false
            local w = measure((ln:gsub("\t", "    ")), f)
            line = line + w
            if ws == "pre" then mn = max(mn, w) else for wd in ln:gmatch("%S+") do mn = max(mn, measure(wd, f)) end end
          end
        else
          s = s:gsub("[ \t\r\n\f]+", " ")
          if s ~= " " and s ~= "" then
            local w = measure(s, f)
            line = line + w
            if ws == "nowrap" then mn = max(mn, w) else
              for wd in s:gmatch("[^ ]+") do mn = max(mn, measure(wd, f)) end
            end
          elseif s == " " and line > 0 then line = line + sp end
        end
      elseif k.type == "el" and not outOfFlow(k) then
        local kmx, kmn = contentWidths(k)
        local kcs = k.cs
        local e = edgeSum(kcs, true)
        local fixed = lenOf(kcs.width, kcs, nil)
        if fixed then
          if kcs["box-sizing"] == "border-box" then fixed = fixed - edgeSum(kcs, true) + (lenOf(kcs["margin-left"], kcs, 0) or 0) + (lenOf(kcs["margin-right"], kcs, 0) or 0) end
          kmx, kmn = fixed, fixed
        end
        local mw = lenOf(kcs["min-width"], kcs, nil)
        if mw then kmx, kmn = max(kmx, mw), max(kmn, mw) end
        local xw = lenOf(kcs["max-width"], kcs, nil)
        if xw then kmx = min(kmx, xw); kmn = min(kmn, xw) end
        if k.tag == "br" then flush()
        elseif isBlockLevel(k) and not flexRow then
          flush()
          mx = max(mx, kmx + e)
        else
          line = line + kmx + e
          if flexRow then mn = mn + kmn + e else mn = max(mn, kmn + e) end
        end
        mn = max(mn, kmn + e)
      end
    end
    flush()
    if flexRow then
      local gap = lenOf(cs["column-gap"], cs, 0) or 0
      local cnt = 0
      for _, k in ipairs(kidsOf(n)) do if k.type == "el" then cnt = cnt + 1 end end
      mx = mx + gap * max(0, cnt - 1)
    end
    if d == "grid" or d == "inline-grid" then
      -- the columns of the grid side by side
      local tracks = cs["grid-template-columns"]
      local count = 0
      if tracks then for _ in tracks:gmatch("%S+") do count = count + 1 end end
      local rep = tracks and tonumber(tracks:match("repeat%(%s*(%d+)"))
      if rep then count = rep end
      if count > 1 then mx = mx * count end
    end
  end
  n._ipass, n._imax, n._imin = pass, mx, mn
  return mx, mn
end
L.contentWidths = function(n) return contentWidths(n) end

-- the content size of a replaced element: width (and height when W is given)
replacedSize = function(n, w, cs)
  cs = cs or n.cs
  local t, a = n.tag, n.attrs
  local fs = cs.fs
  local iw, ih = env.intrinsic and env.intrinsic(n)
  if t == "img" then
    local aw, ah = tonumber(a.width), tonumber(a.height)
    if not iw then iw, ih = aw or (ah and ah * 4 / 3) or 0, ah or (aw and aw * 3 / 4) or 0 end
    if aw and ah then iw, ih = aw, ah elseif aw and iw > 0 then ih = ih * aw / iw; iw = aw elseif ah and ih > 0 then iw = iw * ah / ih; ih = ah end
  elseif t == "canvas" then iw, ih = tonumber(a.width) or 300, tonumber(a.height) or 150
  elseif t == "video" or t == "iframe" or t == "object" or t == "embed" then iw, ih = tonumber(a.width) or 300, tonumber(a.height) or 150
  elseif t == "svg" then iw, ih = tonumber(a.width) or 150, tonumber(a.height) or 150
  elseif t == "audio" then iw, ih = 300, 32
  elseif t == "progress" or t == "meter" then iw, ih = t == "meter" and 80 or 160, 16
  elseif t == "textarea" then iw, ih = (tonumber(a.cols) or 20) * fs * 0.55, (tonumber(a.rows) or 2) * cs.lh
  elseif t == "select" then
    local best = 0
    for _, o in ipairs(n.kids) do
      if o.type == "el" and o.tag == "option" then
        local f = env.fontOf(cs)
        best = max(best, measure(optionText(o), f))
      end
    end
    iw, ih = best + fs * 1.4, cs.lh
  else -- input
    local ty = (a.type or "text"):lower()
    if ty == "checkbox" or ty == "radio" then iw, ih = 13, 13
    elseif ty == "range" then iw, ih = 130, 16
    elseif ty == "color" then iw, ih = 44, 22
    elseif ty == "submit" or ty == "button" or ty == "reset" then
      local label = n.value or a.value or (ty == "submit" and "Submit" or ty == "reset" and "Reset" or "")
      iw, ih = measure(label, env.fontOf(cs)), cs.lh
    else iw, ih = (tonumber(a.size) or 20) * fs * 0.55, cs.lh end
  end
  if w then
    if (t == "img" or t == "canvas" or t == "video" or t == "svg") and iw > 0 then return w, ih * w / iw end
    return w, ih
  end
  return iw, ih
end

-- ---------------------------------------------------------------- block layout
local layoutBox, layoutInline, absQueue
local function queueAbs(k, x, y, parentBox)
  local ab = newBox(k, k.cs)
  ab.staticX, ab.staticY = x, y
  ab.parentBox = parentBox
  k._absBox = ab
  absQueue[#absQueue + 1] = ab
end

-- the used width of a box in a containing block of width CBW: sets b.m, b.bd, b.pd, b.cw
local function resolveWidth(b, cbw, shrink)
  local cs = b.cs
  local m, bd, pd = edges(cs, cbw)
  b.m, b.bd, b.pd = m, bd, pd
  local eh = bd.l + bd.r + pd.l + pd.r
  local w = lenOf(cs.width, cs, cbw)
  if w and cs["box-sizing"] == "border-box" then w = max(0, w - eh) end
  local n = b.n
  if not w and isReplaced(n) then
    local iw = replacedSize(n, nil)
    local h = lenOf(cs.height, cs, nil)
    if h and cs["box-sizing"] == "border-box" then h = h - bd.t - bd.b - pd.t - pd.b end
    local _, ih = replacedSize(n, nil)
    if h and ih and ih > 0 and (n.tag == "img" or n.tag == "canvas" or n.tag == "video") then w = iw * h / ih else w = iw end
  end
  if not w then
    if shrink then
      local mx, mn = contentWidths(n)
      local avail = cbw - m.l - m.r - eh
      w = max(mn, min(mx, avail))
    else
      w = max(0, cbw - m.l - m.r - eh)
    end
  end
  local mxw = lenOf(cs["max-width"], cs, cbw)
  if mxw then if cs["box-sizing"] == "border-box" then mxw = mxw - eh end w = min(w, mxw) end
  local mnw = lenOf(cs["min-width"], cs, cbw)
  if mnw then if cs["box-sizing"] == "border-box" then mnw = mnw - eh end w = max(w, mnw) end
  if w < 0 then w = 0 end
  -- auto margins share what is left (centring)
  if not shrink then
    local rest = cbw - w - eh - (m.autoL and 0 or m.l) - (m.autoR and 0 or m.r)
    if m.autoL and m.autoR then m.l, m.r = max(0, rest / 2), max(0, rest / 2)
    elseif m.autoL then m.l = max(0, rest)
    elseif m.autoR then m.r = max(0, rest) end
  end
  b.cw = w
  return w
end
local function resolveHeight(b, cbh, contentH)
  local cs = b.cs
  local h = lenOf(cs.height, cs, cbh)
  local ev = b.bd.t + b.bd.b + b.pd.t + b.pd.b
  if h and cs["box-sizing"] == "border-box" then h = max(0, h - ev) end
  if not h and isReplaced(b.n) then
    local _, rh = replacedSize(b.n, b.cw)
    h = rh
  end
  h = h or contentH
  local mxh = lenOf(cs["max-height"], cs, cbh)
  if mxh then if cs["box-sizing"] == "border-box" then mxh = mxh - ev end h = min(h, mxh) end
  local mnh = lenOf(cs["min-height"], cs, cbh)
  if mnh then if cs["box-sizing"] == "border-box" then mnh = mnh - ev end h = max(h, mnh) end
  b.ch = max(0, h)
  b.h = b.ch + ev
  b.contentH = contentH
end
-- places the content box once the margins are known: X, Y is the margin edge
local function place(b, x, y)
  b.x, b.y = x + b.m.l, y + b.m.t
  b.cx, b.cy = b.x + b.bd.l + b.pd.l, b.y + b.bd.t + b.pd.t
  b.w = b.cw + b.bd.l + b.bd.r + b.pd.l + b.pd.r
end

local layoutFlex, layoutGrid, layoutTable
-- lays out the children of B (a block container) in normal flow; returns the height of the content
local function layoutFlow(b, kids)
  kids = kids or kidsOf(b.n)
  local anyBlock = false
  for _, k in ipairs(kids) do
    if (isBlockLevel(k) or (k.type == "el" and k.cs.float and k.cs.float ~= "none" and not isReplaced(k))) and not outOfFlow(k) then anyBlock = true; break end
  end
  if not anyBlock then return layoutInline(b, kids, b.cx, b.cy, b.cw) end
  local y = b.cy
  local prevMB = 0
  -- floats: side by side in a row from the left (or the right); the next box in the flow starts under them
  local fl = { x = 0, rx = 0, top = nil, bottom = 0 }
  local function clearFloats()
    if fl.top then y = max(y + prevMB, fl.bottom); prevMB = 0; fl.top = nil end
  end
  local run = {}
  local function flushRun()
    if #run == 0 then return end
    local has = false
    for _, k in ipairs(run) do
      if k.type ~= "text" or k.text:find("%S") or (k.parent and k.parent.cs and (k.parent.cs["white-space"] or ""):find("pre")) then has = true; break end
    end
    if has then
      clearFloats()
      local a = newBox(b.n, b.cs)
      a.anon = true
      a.m, a.bd, a.pd = { t = 0, r = 0, b = 0, l = 0 }, { t = 0, r = 0, b = 0, l = 0 }, { t = 0, r = 0, b = 0, l = 0 }
      a.cw = b.cw
      y = y + prevMB
      prevMB = 0
      place(a, b.cx, y)
      local h = layoutInline(a, run, a.cx, a.cy, a.cw)
      a.ch, a.h = h, h
      b.kids[#b.kids + 1] = a
      if a.baseline then b.baseline = a.baseline end
      y = y + h
    else
      for _, k in ipairs(run) do
        if k.type == "el" and outOfFlow(k) then queueAbs(k, b.cx, y + prevMB, b) end
      end
    end
    run = {}
  end
  for _, k in ipairs(kids) do
    local float = k.type == "el" and k.cs.float
    if float == "none" then float = nil end
    if float and not outOfFlow(k) then
      flushRun()
      local kb = newBox(k, k.cs)
      resolveWidth(kb, b.cw, true)
      local ow = kb.cw + kb.bd.l + kb.bd.r + kb.pd.l + kb.pd.r + kb.m.l + kb.m.r
      if not fl.top or fl.x + fl.rx + ow > b.cw + 0.5 then
        if fl.top then y = max(y, fl.bottom) else y = y + prevMB; prevMB = 0 end
        fl.top, fl.x, fl.rx = y, 0, 0
      end
      if float == "right" then place(kb, b.cx + b.cw - fl.rx - ow, fl.top); fl.rx = fl.rx + ow
      else place(kb, b.cx + fl.x, fl.top); fl.x = fl.x + ow end
      layoutBox(kb, b)
      b.kids[#b.kids + 1] = kb
      fl.bottom = max(fl.bottom, kb.y + kb.h + kb.m.b)
    elseif k.type == "el" and isBlockLevel(k) and not outOfFlow(k) then
      flushRun()
      clearFloats()
      local kb = newBox(k, k.cs)
      resolveWidth(kb, b.cw, false)
      local mt = kb.m.t
      local gap = (prevMB >= 0 and mt >= 0) and max(prevMB, mt) or prevMB + mt
      place(kb, b.cx, y + gap - mt)
      layoutBox(kb, b)
      b.kids[#b.kids + 1] = kb
      y = kb.y + kb.h
      prevMB = kb.m.b
    elseif k.type == "el" and outOfFlow(k) then
      queueAbs(k, b.cx, y + prevMB, b)
    else
      run[#run + 1] = k
    end
  end
  flushRun()
  clearFloats()
  return y + prevMB - b.cy
end

-- the content of a box by its display; B is placed (cx, cy, cw known); sets b.h
layoutBox = function(b, parent)
  local n, cs = b.n, b.cs
  b.parent = parent
  local d = cs.display
  local cbh = parent and parent.definiteH
  local hasH = lenOf(cs.height, cs, cbh)
  if hasH then
    if cs["box-sizing"] == "border-box" then hasH = hasH - b.bd.t - b.bd.b - b.pd.t - b.pd.b end
    b.definiteH = hasH
  end
  local contentH
  if isReplaced(n) then contentH = 0
  elseif d == "flex" or d == "inline-flex" then contentH = layoutFlex(b)
  elseif d == "grid" or d == "inline-grid" then contentH = layoutGrid(b)
  elseif d == "table" or d == "inline-table" then contentH = layoutTable(b)
  else contentH = layoutFlow(b) end
  resolveHeight(b, cbh, contentH)
  local ox, oy = cs["overflow-x"] or "visible", cs["overflow-y"] or "visible"
  if ox ~= "visible" or oy ~= "visible" then
    b.clip = true
    b.scrollH = contentH
    b.scrollable = (oy == "auto" or oy == "scroll") and contentH > b.ch
    b.sy = n.scrollTop or 0
    local maxSy = max(0, contentH - b.ch)
    if b.sy > maxSy then b.sy = maxSy; n.scrollTop = maxSy end
  end
  if d == "list-item" then
    local lt = cs["list-style-type"] or "disc"
    if lt ~= "none" then
      local mark
      if lt == "decimal" or lt == "decimal-leading-zero" or lt == "lower-alpha" or lt == "upper-alpha" or lt == "lower-roman" or lt == "upper-roman" or lt == "lower-latin" or lt == "upper-latin" then
        local idx, start = 0, tonumber(n.parent and n.parent.attrs and n.parent.attrs.start) or 1
        for _, s in ipairs(n.parent and n.parent.kids or {}) do
          if s.type == "el" and s.cs and s.cs.display == "list-item" then idx = idx + 1 end
          if s == n then break end
        end
        local v = tonumber(n.attrs.value) or (start + idx - 1)
        if lt:find("alpha") or lt:find("latin") then mark = string.char(96 + ((v - 1) % 26) + 1) .. "."
          if lt:find("upper") then mark = mark:upper() end
        elseif lt:find("roman") then
          local r, vals, syms = "", { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 }, { "m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i" }
          local x = v
          for i2, vv in ipairs(vals) do while x >= vv do r = r .. syms[i2]; x = x - vv end end
          mark = (lt:find("upper") and r:upper() or r) .. "."
        else mark = tostring(v) .. "." end
      else mark = lt == "circle" and "◦" or lt == "square" and "▪" or "•" end
      b.marker = mark
      b.markerY = b.markerY or b.cy
    end
  end
  -- position: relative moves the box after the layout
  if cs.position == "relative" or cs.position == "sticky" then
    local l, t = lenOf(cs.left, cs, parent and parent.cw), lenOf(cs.top, cs, cbh)
    local r, bt = lenOf(cs.right, cs, parent and parent.cw), lenOf(cs.bottom, cs, cbh)
    local dx = l or (r and -r) or 0
    local dy = t or (bt and -bt) or 0
    if cs.position == "relative" then shift(b, dx, dy) end
  end
  return b
end

-- ---------------------------------------------------------------- inline formatting
local function strut(cs)
  local fs, lh = cs.fs, cs.lh
  local a = (lh - fs) / 2 + fs * 0.8
  return a, lh - a
end
local VA_MIDDLE = { middle = true }
-- collects the items of the inline content KIDS of the element P (style PCS)
local function inlineItems(kids, pcs, items, avail, owner, stack)
  for _, k in ipairs(kids) do
    if k.type == "text" then
      local cs = pcs
      local font = env.fontOf(cs)
      local ws = cs["white-space"] or "normal"
      local s = transform(k.text, cs)
      local node = k.parent
      if ws == "pre" or ws == "pre-wrap" or ws == "pre-line" or ws == "break-spaces" then
        local first = true
        for ln in (s .. "\n"):gmatch("([^\n]*)\n") do
          if not first then items[#items + 1] = { kind = "br", cs = cs } end
          first = false
          ln = ln:gsub("\r", "")
          if ws == "pre" then
            ln = ln:gsub("\t", "    ")
            if ln ~= "" then items[#items + 1] = { kind = "text", s = ln, w = measure(ln, font), cs = cs, font = font, n = node, stack = stack } end
          else
            if ws == "pre-line" then ln = ln:gsub("[ \t]+", " ") end
            local sp = measure(" ", font)
            for wd, spc in ln:gmatch("([^ \t]+)([ \t]*)") do
              items[#items + 1] = { kind = "text", s = wd, w = measure(wd, font), sp = spc ~= "" and sp * #spc or 0, cs = cs, font = font, n = node, stack = stack }
            end
          end
        end
        -- a pre text ending in a newline leaves no empty line after it
        if s:sub(-1) == "\n" and items[#items] and items[#items].kind == "br" then items[#items] = nil end
      else
        s = s:gsub("[ \t\r\n\f]+", " ")
        local sp = measure(" ", font)
        if s:sub(1, 1) == " " then
          local prev = items[#items]
          if prev and prev.kind ~= "br" and (prev.sp or 0) == 0 then prev.sp = sp end
        end
        if ws == "nowrap" then
          local t = s:gsub("^ ", ""):gsub(" $", "")
          if t ~= "" then
            t = t:gsub("\194\160", " ")
            items[#items + 1] = { kind = "text", s = t, w = measure(t, font), sp = s:sub(-1) == " " and sp or 0, cs = cs, font = font, n = node, stack = stack }
          end
        else
          local words = {}
          for wd in s:gmatch("[^ ]+") do words[#words + 1] = wd end
          for i, wd in ipairs(words) do
            local last = i == #words
            wd = wd:gsub("\194\160", " ")
            items[#items + 1] = { kind = "text", s = wd, w = measure(wd, font), sp = (not last or s:sub(-1) == " ") and sp or 0, cs = cs, font = font, n = node, stack = stack }
          end
        end
      end
    elseif k.type == "el" then
      local cs = k.cs
      local d = cs.display or "inline"
      if outOfFlow(k) then
        items[#items + 1] = { kind = "abs", n = k, w = 0 }
      elseif k.tag == "br" then
        items[#items + 1] = { kind = "br", cs = pcs }
      elseif d == "inline" and not isReplaced(k) then
        local m, bd, pd = edges(cs, avail)
        local deco = (cs["background-color"] and cs["background-color"] ~= "transparent") or bd.l + bd.r + bd.t + bd.b > 0
        local ns = stack
        if deco then
          ns = { n = k, cs = cs, up = stack, m = m, bd = bd, pd = pd }
        end
        local lw = m.l + bd.l + pd.l
        items[#items + 1] = { kind = "open", w = lw, n = k, stack = ns }
        inlineItems(kidsOf(k), cs, items, avail, owner, ns)
        items[#items + 1] = { kind = "close", w = m.r + bd.r + pd.r, n = k, stack = ns, sp = 0 }
      elseif isBlockLevel(k) and d ~= "table-cell" and d ~= "table-row" and not (cs.float and cs.float ~= "none") then
        items[#items + 1] = { kind = "block", n = k }
      else
        -- an atomic inline box: inline-block, inline-flex, a replaced element, a float
        local kb = newBox(k, cs)
        resolveWidth(kb, avail, true)
        place(kb, 0, 0)
        layoutBox(kb, owner)
        local w = kb.w + kb.m.l + kb.m.r
        items[#items + 1] = { kind = "box", box = kb, w = w, h = kb.h + kb.m.t + kb.m.b, n = k, stack = stack, sp = 0, float = cs.float }
      end
    end
  end
  return items
end

-- lays out inline content KIDS in the box B at X, Y with width W; returns the height
layoutInline = function(b, kids, x, y, w)
  local items = inlineItems(kids, b.cs, {}, w, b, nil)
  if #items == 0 then return 0 end
  local align = b.cs["text-align"] or "left"
  local indent = lenOf(b.cs["text-indent"], b.cs, w) or 0
  local sa, sd = strut(b.cs)
  local lines, cur = {}, { items = {}, w = indent }
  local function finish(force)
    if #cur.items == 0 and not force then return end
    lines[#lines + 1] = cur
    cur = { items = {}, w = 0 }
  end
  local function content(line)
    for _, it in ipairs(line.items) do if it.kind == "text" or it.kind == "box" then return true end end
    return false
  end
  for _, it in ipairs(items) do
    if it.kind == "br" then
      cur.br = true
      finish(true)
    elseif it.kind == "block" then
      finish(false)
      lines[#lines + 1] = { block = it.n, items = {} }
    elseif it.kind == "abs" then
      it.x = cur.w
      cur.items[#cur.items + 1] = it
    else
      local nowrapHere = it.cs and it.cs["white-space"] == "nowrap"
      if cur.w + it.w > w + 0.5 and content(cur) and it.kind ~= "close" and not nowrapHere then
        -- the opening items at the end go with the word to the next line
        local carry = {}
        while #cur.items > 0 and cur.items[#cur.items].kind == "open" do table.insert(carry, 1, table.remove(cur.items)) end
        finish(false)
        for _, c in ipairs(carry) do c.x = cur.w; cur.items[#cur.items + 1] = c; cur.w = cur.w + c.w end
      end
      it.x = cur.w
      cur.items[#cur.items + 1] = it
      cur.w = cur.w + it.w + (it.sp or 0)
    end
  end
  finish(false)
  -- vertical placement
  local yy = y
  local fh = {}
  for li, line in ipairs(lines) do
    if line.block then
      local kb = newBox(line.block, line.block.cs)
      resolveWidth(kb, w, false)
      place(kb, x, yy)
      layoutBox(kb, b)
      b.kids[#b.kids + 1] = kb
      yy = kb.y + kb.h + kb.m.b
    else
      local A, Dd = sa, sd
      local hasText = false
      for _, it in ipairs(line.items) do
        if it.kind == "text" then
          local a, d = strut(it.cs)
          it.a = a
          if a > A then A = a end
          if d > Dd then Dd = d end
          hasText = true
        elseif it.kind == "box" then
          local kb = it.box
          local va = kb.cs["vertical-align"] or "baseline"
          local a
          if VA_MIDDLE[va] then a = it.h / 2 + b.cs.fs * 0.3
          elseif va == "top" or va == "text-top" then a = sa
          elseif va == "bottom" or va == "text-bottom" then a = it.h - sd
          elseif kb.baseline then a = kb.baseline - kb.y + kb.m.t
          else a = it.h end
          it.a = a
          if a > A then A = a end
          if it.h - a > Dd then Dd = it.h - a end
        end
      end
      -- width without the last space, for the alignment
      local lw = 0
      for _, it in ipairs(line.items) do lw = max(lw, it.x + it.w) end
      local dx = 0
      if align == "center" or align == "-webkit-center" then dx = (w - lw) / 2
      elseif align == "right" or align == "end" or align == "-webkit-right" then dx = w - lw end
      if dx < 0 then dx = 0 end
      local base = yy + A
      local decoSpans = {}
      for _, it in ipairs(line.items) do
        local ix = x + dx + it.x
        if it.kind == "text" then
          b.texts[#b.texts + 1] = { x = ix, y = base - it.a, w = it.w, h = it.cs.lh, s = it.s, cs = it.cs, font = it.font, n = it.n }
        elseif it.kind == "box" then
          local kb = it.box
          shift(kb, ix + kb.m.l - kb.x, base - it.a + kb.m.t - kb.y)
          b.kids[#b.kids + 1] = kb
        elseif it.kind == "abs" then
          queueAbs(it.n, ix, yy, b)
        end
        -- the inline elements with a background or a border on this line
        local s = it.stack
        while s do
          local sp = decoSpans[s]
          if not sp then sp = { x0 = ix, x1 = ix + it.w, st = s }; decoSpans[s] = sp; decoSpans[#decoSpans + 1] = sp
          else sp.x0 = min(sp.x0, ix); sp.x1 = max(sp.x1, ix + it.w) end
          s = s.up
        end
      end
      for i = #decoSpans, 1, -1 do
        local sp = decoSpans[i]
        local st = sp.st
        local fs = st.cs.fs
        local x0 = sp.x0 + (st.m.l or 0)
        local x1 = sp.x1 - (st.m.r or 0)
        table.insert(b.decos, 1, { x = x0, y = base - fs * 0.85 - st.pd.t - st.bd.t, w = x1 - x0, h = fs * 1.1 + st.pd.t + st.pd.b + st.bd.t + st.bd.b, cs = st.cs, n = st.n, bd = st.bd })
      end
      if li == 1 and b.markerY == nil then b.markerY = yy; b.markerH = A + Dd; b.markerBase = base end
      b.baseline = base
      yy = yy + A + Dd
    end
  end
  return yy - y
end

-- ---------------------------------------------------------------- flexbox
local function num(v, d) return tonumber(v) or d end
layoutFlex = function(b)
  local cs = b.cs
  local dir = cs["flex-direction"] or "row"
  local row = not dir:find("column")
  local rev = dir:find("reverse") ~= nil
  local wrap = (cs["flex-wrap"] or "nowrap") ~= "nowrap"
  local jc = cs["justify-content"] or "flex-start"
  local ai = cs["align-items"] or "stretch"
  local cgap = lenOf(cs["column-gap"], cs, b.cw) or 0
  local rgap = lenOf(cs["row-gap"], cs, b.definiteH) or 0
  local mainGap = row and cgap or rgap
  local crossGap = row and rgap or cgap
  local items = {}
  local order = 0
  for _, k in ipairs(kidsOf(b.n)) do
    if k.type == "text" then
      if k.text:find("%S") then
        -- text straight in a flex container is an anonymous item
        local acs = { display = "block" }
        for p, v in pairs(b.cs) do
          if type(p) ~= "string" or C.INHERITED[p] or p:sub(1, 2) == "--" or #p <= 6 and not p:find("-", 1, true) and p ~= "width" and p ~= "height" and p ~= "top" and p ~= "left" and p ~= "right" and p ~= "bottom" and p ~= "order" and p ~= "float" and p ~= "content" and p ~= "display" then acs[p] = v end
        end
        local a = { type = "el", tag = "#anon", attrs = {}, order = {}, kids = { k }, cs = acs, parent = b.n }
        order = order + 1
        items[#items + 1] = { n = a, ord = 0, seq = order, anonText = k }
      end
    elseif outOfFlow(k) then
      queueAbs(k, b.cx, b.cy, b)
    else
      order = order + 1
      items[#items + 1] = { n = k, ord = num(k.cs.order, 0), seq = order }
    end
  end
  table.sort(items, function(p, q) if p.ord ~= q.ord then return p.ord < q.ord end return p.seq < q.seq end)
  if rev then
    local r = {}
    for i = #items, 1, -1 do r[#r + 1] = items[i] end
    items = r
  end
  local mainSize = row and b.cw or b.definiteH
  -- the base size of each item
  for _, it in ipairs(items) do
    local k = it.n
    local kcs = k.cs
    local kb = newBox(k, kcs)
    it.box = kb
    local m, bd, pd = edges(kcs, b.cw)
    kb.m, kb.bd, kb.pd = m, bd, pd
    local eMain = row and (bd.l + bd.r + pd.l + pd.r) or (bd.t + bd.b + pd.t + pd.b)
    local mMain = row and (m.l + m.r) or (m.t + m.b)
    it.eMain, it.mMain = eMain, mMain
    it.grow = num(kcs["flex-grow"], 0)
    it.shrink = num(kcs["flex-shrink"], 1)
    local basis = kcs["flex-basis"]
    local bsz = (basis and basis ~= "auto" and basis ~= "content") and lenOf(basis, kcs, mainSize) or nil
    local bb = kcs["box-sizing"] == "border-box"
    if bsz and bb then bsz = bsz - eMain end
    if not bsz then
      local sz = lenOf(row and kcs.width or kcs.height, kcs, row and b.cw or b.definiteH)
      if sz and bb then sz = sz - eMain end
      bsz = sz
    end
    local mx, mn = 0, 0
    if row then
      mx, mn = contentWidths(k)
      if isReplaced(k) then mx = select(1, replacedSize(k, nil)); mn = mx end
    end
    if not bsz then
      if row then bsz = mx
      else
        -- a column item: its height at the width it gets
        resolveWidth(kb, b.cw, not (ai == "stretch" and not (kcs["align-self"] and kcs["align-self"] ~= "stretch" and kcs["align-self"] ~= "auto")))
        place(kb, 0, 0)
        layoutBox(kb, b)
        bsz = kb.contentH or kb.ch
        if lenOf(kcs.height, kcs, nil) then bsz = kb.ch end
        it.pre = true
      end
    end
    local minMain = row and lenOf(kcs["min-width"], kcs, b.cw) or (not row and lenOf(kcs["min-height"], kcs, b.definiteH))
    local maxMain = row and lenOf(kcs["max-width"], kcs, b.cw) or (not row and lenOf(kcs["max-height"], kcs, b.definiteH))
    if not minMain then
      local ov = kcs["overflow-x"]
      minMain = (row and (not ov or ov == "visible")) and min(mn, bsz) or 0
    elseif bb then minMain = minMain - eMain end
    if maxMain and bb then maxMain = maxMain - eMain end
    it.minM, it.maxM = minMain, maxMain
    if maxMain then bsz = min(bsz, maxMain) end
    bsz = max(bsz, minMain or 0)
    it.base = bsz
    it.size = bsz
  end
  -- lines
  local lines = {}
  local avail = mainSize or INF
  local cur = { items = {}, used = 0 }
  for _, it in ipairs(items) do
    local outer = it.base + it.eMain + it.mMain
    if wrap and #cur.items > 0 and cur.used + mainGap + outer > avail + 0.5 then
      lines[#lines + 1] = cur
      cur = { items = {}, used = 0 }
    end
    cur.used = cur.used + (#cur.items > 0 and mainGap or 0) + outer
    cur.items[#cur.items + 1] = it
  end
  if #cur.items > 0 then lines[#lines + 1] = cur end
  -- flexible lengths, then the cross size of each item
  for _, line in ipairs(lines) do
    local free = (mainSize or line.used) - line.used
    if mainSize then
      for _ = 1, 3 do
        if math.abs(free) < 0.5 then break end
        local total = 0
        for _, it in ipairs(line.items) do
          if not it.frozen then total = total + (free > 0 and it.grow or it.shrink * it.base) end
        end
        if total <= 0 then break end
        local spent = 0
        for _, it in ipairs(line.items) do
          if not it.frozen then
            local share = free > 0 and it.grow / total or (it.shrink * it.base) / total
            if free > 0 and it.grow > 0 and total < 1 then share = it.grow end
            local ns = it.size + free * share
            if it.maxM and ns > it.maxM then ns = it.maxM; it.frozen = true end
            if ns < (it.minM or 0) then ns = it.minM or 0; it.frozen = true end
            spent = spent + ns - it.size
            it.size = ns
          end
        end
        free = free - spent
      end
    end
    line.free = free
    line.cross = 0
    for _, it in ipairs(line.items) do
      local kb = it.box
      local kcs = kb.cs
      if row then
        kb.cw = it.size
        if rawget(kb.cs, "width") == nil or true then
          -- the width is the flexed one; margins auto are worked out below
          local am = kb.m
          kb.m = { t = am.t, r = am.autoR and 0 or am.r, b = am.b, l = am.autoL and 0 or am.l, autoL = am.autoL, autoR = am.autoR, autoT = am.autoT, autoB = am.autoB }
        end
        place(kb, 0, 0)
        kb.w = kb.cw + kb.bd.l + kb.bd.r + kb.pd.l + kb.pd.r
        layoutBox(kb, b)
        it.cross = kb.h + kb.m.t + kb.m.b
      else
        if not it.pre then
          resolveWidth(kb, b.cw, not (ai == "stretch"))
          place(kb, 0, 0)
          layoutBox(kb, b)
        end
        -- the main size is the flexed height
        if math.abs(kb.ch - it.size) > 0.5 then
          kb.definiteH = it.size
          kb.ch = it.size
          kb.h = it.size + kb.bd.t + kb.bd.b + kb.pd.t + kb.pd.b
          if kb.cs.display == "flex" or kb.cs.display == "grid" then
            local m = kb.m
            kb.kids, kb.texts, kb.decos = {}, {}, {}
            place(kb, 0, 0)
            kb.m = m
            local fh = kb.ch
            layoutBox(kb, b)
            kb.ch, kb.h = fh, fh + kb.bd.t + kb.bd.b + kb.pd.t + kb.pd.b
          end
        end
        it.cross = kb.w + kb.m.l + kb.m.r
      end
      if it.cross > line.cross then line.cross = it.cross end
    end
  end
  -- a single line fills a definite cross size
  local crossSize = b.cw
  if row then crossSize = b.definiteH end
  if #lines == 1 and crossSize and not wrap then lines[1].cross = crossSize end
  if #lines == 1 and crossSize and wrap and (cs["align-content"] == "stretch" or cs["align-content"] == nil) then lines[1].cross = max(lines[1].cross, crossSize) end
  -- placing
  local crossPos = 0
  for li, line in ipairs(lines) do
    local n = #line.items
    local free = line.free
    local start, between = 0, mainGap
    -- auto margins take the free space first
    local autos = 0
    for _, it in ipairs(line.items) do
      local m = it.box.m
      if row then autos = autos + (m.autoL and 1 or 0) + (m.autoR and 1 or 0) else autos = autos + (m.autoT and 1 or 0) + (m.autoB and 1 or 0) end
    end
    local autoShare = 0
    if autos > 0 and free > 0 then autoShare = free / autos; free = 0 end
    if free > 0 then
      if jc == "flex-end" or jc == "end" or jc == "right" then start = free
      elseif jc == "center" then start = free / 2
      elseif jc == "space-between" and n > 1 then between = mainGap + free / (n - 1)
      elseif jc == "space-around" then between = mainGap + free / n; start = free / n / 2
      elseif jc == "space-evenly" then between = mainGap + free / (n + 1); start = free / (n + 1) end
    end
    local pos = start
    for _, it in ipairs(line.items) do
      local kb = it.box
      local m = kb.m
      local a1 = row and (m.autoL and autoShare or 0) or (m.autoT and autoShare or 0)
      local a2 = row and (m.autoR and autoShare or 0) or (m.autoB and autoShare or 0)
      pos = pos + a1
      local self = kb.cs["align-self"]
      if not self or self == "auto" then self = ai end
      local cross = row and (kb.h + m.t + m.b) or (kb.w + m.l + m.r)
      local coff = 0
      if self == "center" then coff = (line.cross - cross) / 2
      elseif self == "flex-end" or self == "end" then coff = line.cross - cross
      elseif self == "stretch" or self == "normal" then
        if row and not lenOf(kb.cs.height, kb.cs, nil) and line.cross > cross then
          local extra = line.cross - cross
          kb.ch = kb.ch + extra
          kb.h = kb.h + extra
          if kb.cs.display == "flex" or kb.cs.display == "grid" then
            -- the inside is laid out again for the taller box (a column that pushes its last child down)
            local keepM = kb.m
            kb.kids, kb.texts, kb.decos = {}, {}, {}
            kb.definiteH = kb.ch
            local hh = kb.ch
            place(kb, 0, 0)
            kb.m = keepM
            kb.cs = setmetatable({ height = hh .. "px", ["box-sizing"] = "content-box" }, { __index = kb.cs })
            layoutBox(kb, b)
          end
        end
      end
      local mx, my
      if row then mx, my = b.cx + pos + m.l, b.cy + crossPos + coff + m.t
      else mx, my = b.cx + crossPos + coff + m.l, b.cy + pos + m.t end
      shift(kb, mx - kb.x, my - kb.y)
      b.kids[#b.kids + 1] = kb
      local mainOuter = row and (kb.w + m.l + m.r) or (kb.h + m.t + m.b)
      pos = pos + mainOuter + a2 + between
    end
    crossPos = crossPos + line.cross + (li < #lines and crossGap or 0)
    line.mainEnd = pos - between
  end
  if row then return crossPos end
  local used = 0
  for _, line in ipairs(lines) do used = max(used, line.mainEnd or 0) end
  -- a column: the content height; wrapped columns are not handled (one line)
  return used
end

-- ---------------------------------------------------------------- grid (simple)
local function tracksOf(spec, cs, width, gap, itemCount)
  local out = {}
  if not spec or spec == "none" then return out end
  spec = spec:gsub("%[[^%]]*%]", " ")
  -- repeat(auto-fill, minmax(200px, 1fr)) and repeat(N, X)
  spec = spec:gsub("repeat%(%s*([%w%-]+)%s*,%s*(.-)%)%s*$", function(cnt, what) return "repeat(" .. cnt .. "," .. what .. ")" end)
  local toks = {}
  for _, w in ipairs(C.words(spec)) do toks[#toks + 1] = w end
  for _, t in ipairs(toks) do
    local cnt, what = t:match("^repeat%(([%w%-]+),(.+)%)$")
    if cnt then
      local inner = C.words(what)
      local n = tonumber(cnt)
      if not n then
        local mn = what:match("minmax%(%s*([^,]+),") or inner[1]
        local px = lenOf(mn, cs, width) or 100
        n = max(1, floor((width + gap) / (px + gap)))
        if cnt == "auto-fit" and itemCount and itemCount < n then n = max(1, itemCount) end
      end
      for _ = 1, n do for _, x in ipairs(inner) do out[#out + 1] = x end end
    else out[#out + 1] = t end
  end
  return out
end
layoutGrid = function(b)
  local cs = b.cs
  local cgap = lenOf(cs["column-gap"], cs, b.cw) or 0
  local rgap = lenOf(cs["row-gap"], cs, b.definiteH) or 0
  local kids = {}
  for _, k in ipairs(kidsOf(b.n)) do
    if k.type == "el" then
      if outOfFlow(k) then queueAbs(k, b.cx, b.cy, b)
      else kids[#kids + 1] = k end
    end
  end
  local tracks = tracksOf(cs["grid-template-columns"], cs, b.cw, cgap, #kids)
  if #tracks == 0 then tracks = { "1fr" } end
  local ncol = #tracks
  -- column widths
  local widths, fr, fixed = {}, 0, 0
  for i, t in ipairs(tracks) do
    local f = t:match("^([%d%.]+)fr$")
    local mm1, mm2 = t:match("^minmax%(%s*([^,]+)%s*,%s*([^%)]+)%)$")
    if mm2 and mm2:match("fr$") then f = mm2:match("^([%d%.]+)fr$"); widths[i] = { fr = tonumber(f), min = lenOf(mm1, cs, b.cw) or 0 }
    elseif f then widths[i] = { fr = tonumber(f), min = 0 }
    elseif t == "auto" or t == "min-content" or t == "max-content" then widths[i] = { fr = 1, min = 0, auto = true }
    else
      local px = lenOf(mm1 or t, cs, b.cw) or 0
      widths[i] = { px = px }
      fixed = fixed + px
    end
    if widths[i].fr then fr = fr + widths[i].fr end
  end
  local free = b.cw - fixed - cgap * (ncol - 1)
  local colW = {}
  for i, w in ipairs(widths) do
    if w.px then colW[i] = w.px else colW[i] = max(w.min, fr > 0 and free * w.fr / fr or 0) end
  end
  local colX = {}
  local xx = 0
  for i = 1, ncol do colX[i] = xx; xx = xx + colW[i] + cgap end
  -- placing the items row by row
  local rowsTpl = tracksOf(cs["grid-template-rows"], cs, b.definiteH or 0, rgap)
  local autoRow = lenOf(cs["grid-auto-rows"], cs, nil)
  local occupied = {}
  local placed = {}
  local r, c = 1, 1
  for _, k in ipairs(kids) do
    local gc = k.cs["grid-column"]
    local span, start = 1, nil
    if gc then
      local a, bb = gc:match("^%s*(.-)%s*/%s*(.-)%s*$")
      a = a or gc
      local sp = a:match("span%s+(%d+)")
      if sp then span = tonumber(sp) else start = tonumber(a) end
      if bb then
        local sp2 = bb:match("span%s+(%d+)")
        local e = tonumber(bb)
        if sp2 then span = tonumber(sp2)
        elseif e and start then
          if e < 0 then e = ncol + 2 + e end
          span = max(1, e - start)
        end
      end
    end
    span = min(span, ncol)
    if start then
      if start < 0 then start = ncol + 1 + start end
      start = max(1, min(start, ncol))
      if start < c then r = r + 1 end
      c = start
    end
    while true do
      if c + span - 1 > ncol then r = r + 1; c = 1 end
      local free_ = true
      for j = c, c + span - 1 do if occupied[r .. ":" .. j] then free_ = false end end
      if free_ then break end
      c = c + 1
    end
    for j = c, c + span - 1 do occupied[r .. ":" .. j] = true end
    placed[#placed + 1] = { n = k, r = r, c = c, span = span }
    c = c + span
  end
  -- the boxes, then the height of each row
  local rowH = {}
  for _, p in ipairs(placed) do
    local kb = newBox(p.n, p.n.cs)
    local w = colW[p.c]
    for j = p.c + 1, p.c + p.span - 1 do w = w + cgap + colW[j] end
    p.cellW = w
    local ji = p.n.cs["justify-self"] or cs["justify-items"]
    resolveWidth(kb, w, ji == "center" or ji == "start" or ji == "end")
    place(kb, 0, 0)
    layoutBox(kb, b)
    p.box = kb
    local h = kb.h + kb.m.t + kb.m.b
    local tpl = rowsTpl[p.r] and lenOf(rowsTpl[p.r], cs, b.definiteH)
    rowH[p.r] = max(rowH[p.r] or (tpl or autoRow or 0), h)
  end
  local rowY = {}
  local yy = 0
  local nrows = 0
  for rr in pairs(rowH) do nrows = max(nrows, rr) end
  for rr = 1, nrows do rowY[rr] = yy; yy = yy + (rowH[rr] or 0) + (rr < nrows and rgap or 0) end
  for _, p in ipairs(placed) do
    local kb = p.box
    local ai = p.n.cs["align-self"] or cs["align-items"] or "stretch"
    local ji = p.n.cs["justify-self"] or cs["justify-items"] or "stretch"
    local h = kb.h + kb.m.t + kb.m.b
    local dy = 0
    if ai == "center" then dy = (rowH[p.r] - h) / 2 elseif ai == "end" or ai == "flex-end" then dy = rowH[p.r] - h
    elseif (ai == "stretch" or ai == "normal") and not lenOf(kb.cs.height, kb.cs, nil) then
      local extra = rowH[p.r] - h
      kb.ch, kb.h = kb.ch + extra, kb.h + extra
    end
    local dx = 0
    local ow = kb.w + kb.m.l + kb.m.r
    if ji == "center" then dx = (p.cellW - ow) / 2 elseif ji == "end" then dx = p.cellW - ow end
    shift(kb, b.cx + colX[p.c] + dx + kb.m.l - kb.x, b.cy + rowY[p.r] + dy + kb.m.t - kb.y)
    b.kids[#b.kids + 1] = kb
  end
  return yy
end

-- ---------------------------------------------------------------- tables (simple)
layoutTable = function(b)
  local cs = b.cs
  local collapse = cs["border-collapse"] == "collapse"
  local spacing = collapse and 0 or (lenOf(C.words(cs["border-spacing"] or "2px")[1], cs, 0) or 2)
  local rows, caption = {}, nil
  local function addRow(tr)
    local cells = {}
    for _, c in ipairs(kidsOf(tr)) do if c.type == "el" then cells[#cells + 1] = c end end
    rows[#rows + 1] = { n = tr, cells = cells }
  end
  for _, k in ipairs(kidsOf(b.n)) do
    if k.type == "el" then
      local d = k.cs.display
      if d == "table-caption" or k.tag == "caption" then caption = k
      elseif d == "table-row" then addRow(k)
      elseif d:find("group") then for _, tr in ipairs(kidsOf(k)) do if tr.type == "el" then addRow(tr) end end end
    end
  end
  -- columns: the widths each column wants
  local ncol = 0
  local mins, maxs, fixedW = {}, {}, {}
  for _, r in ipairs(rows) do
    local col = 1
    r.at = {}
    for _, c in ipairs(r.cells) do
      local span = tonumber(c.attrs.colspan) or 1
      r.at[#r.at + 1] = { n = c, col = col, span = span }
      if span == 1 then
        local mx, mn = contentWidths(c)
        local e = edgeSum(c.cs, true)
        maxs[col] = max(maxs[col] or 0, mx + e)
        mins[col] = max(mins[col] or 0, mn + e)
        local fw = lenOf(c.cs.width, c.cs, nil)
        if fw then fixedW[col] = max(fixedW[col] or 0, fw + e) end
      end
      col = col + span
    end
    ncol = max(ncol, col - 1)
  end
  for i = 1, ncol do
    mins[i] = mins[i] or 0
    maxs[i] = max(maxs[i] or 0, mins[i])
    if fixedW[i] then maxs[i] = max(fixedW[i], mins[i]); mins[i] = maxs[i] end
  end
  local avail = b.cw - spacing * (ncol + 1)
  local tableW = lenOf(cs.width, cs, b.parent and b.parent.cw)
  local sumMax, sumMin = 0, 0
  for i = 1, ncol do sumMax, sumMin = sumMax + maxs[i], sumMin + mins[i] end
  local widths = {}
  if sumMax <= avail then
    for i = 1, ncol do widths[i] = maxs[i] end
    if tableW and sumMax < avail and sumMax > 0 then
      local extra = avail - sumMax
      for i = 1, ncol do widths[i] = widths[i] + extra * maxs[i] / sumMax end
    end
  else
    local extra = max(0, avail - sumMin)
    local spread = sumMax - sumMin
    for i = 1, ncol do widths[i] = mins[i] + (spread > 0 and extra * (maxs[i] - mins[i]) / spread or 0) end
  end
  local total = spacing
  for i = 1, ncol do total = total + widths[i] + spacing end
  if not tableW then
    b.cw = total
    b.w = total + b.bd.l + b.bd.r + b.pd.l + b.pd.r
    if b.m.autoL and b.m.autoR and b.parent then
      local rest = b.parent.cw - b.w
      local nx = b.parent.cx + max(0, rest / 2)
      shift(b, nx - b.x, 0)
      b.m.l, b.m.r = max(0, rest / 2), max(0, rest / 2)
    end
  end
  local colX = {}
  local xx = spacing
  for i = 1, ncol do colX[i] = xx; xx = xx + widths[i] + spacing end
  local y = 0
  if caption then
    local kb = newBox(caption, caption.cs)
    resolveWidth(kb, b.cw, false)
    place(kb, b.cx, b.cy)
    layoutBox(kb, b)
    b.kids[#b.kids + 1] = kb
    y = kb.h + kb.m.t + kb.m.b
  end
  y = y + spacing
  for _, r in ipairs(rows) do
    local rowH = 0
    local boxes = {}
    for _, at in ipairs(r.at) do
      if at.col <= ncol then
        local c = at.n
        local w = widths[at.col]
        for j = at.col + 1, min(ncol, at.col + at.span - 1) do w = w + spacing + widths[j] end
        local kb = newBox(c, c.cs)
        local m, bd, pd = edges(c.cs, w)
        kb.m, kb.bd, kb.pd = { t = 0, r = 0, b = 0, l = 0 }, bd, pd
        kb.cw = max(0, w - bd.l - bd.r - pd.l - pd.r)
        place(kb, b.cx + colX[at.col], b.cy + y)
        layoutBox(kb, b)
        boxes[#boxes + 1] = kb
        rowH = max(rowH, kb.h)
      end
    end
    local rh = lenOf(r.n.cs and r.n.cs.height, r.n.cs or cs, nil)
    if rh then rowH = max(rowH, rh) end
    -- a row with its own background
    if r.n.cs and r.n.cs["background-color"] and r.n.cs["background-color"] ~= "transparent" then
      local rb = newBox(r.n, r.n.cs)
      rb.m, rb.bd, rb.pd = { t = 0, r = 0, b = 0, l = 0 }, { t = 0, r = 0, b = 0, l = 0 }, { t = 0, r = 0, b = 0, l = 0 }
      rb.x, rb.y, rb.w, rb.h = b.cx, b.cy + y, b.cw, rowH
      rb.cx, rb.cy, rb.cw, rb.ch = rb.x, rb.y, rb.w, rb.h
      b.kids[#b.kids + 1] = rb
    end
    for _, kb in ipairs(boxes) do
      local va = kb.cs["vertical-align"] or "middle"
      local extra = rowH - kb.h
      if va == "middle" then
        for _, t in ipairs(kb.texts) do t.y = t.y + extra / 2 end
        for _, k in ipairs(kb.kids) do shift(k, 0, extra / 2) end
        for _, t in ipairs(kb.decos) do t.y = t.y + extra / 2 end
      elseif va == "bottom" then
        for _, t in ipairs(kb.texts) do t.y = t.y + extra end
        for _, k in ipairs(kb.kids) do shift(k, 0, extra) end
      end
      kb.ch, kb.h = kb.ch + extra, rowH
      b.kids[#b.kids + 1] = kb
    end
    y = y + rowH + spacing
  end
  return y
end

-- ---------------------------------------------------------------- absolute and fixed boxes
local function containingBlock(ab)
  if ab.cs.position == "fixed" then return { x = 0, y = 0, w = env.vw, h = env.vh, fixed = true } end
  local p = ab.parentBox
  while p do
    local pos = p.cs and p.cs.position
    if p.n and not p.anon and pos and pos ~= "static" then
      return { x = p.x + p.bd.l, y = p.y + p.bd.t, w = p.w - p.bd.l - p.bd.r, h = p.h - p.bd.t - p.bd.b, box = p }
    end
    p = p.parent
  end
  return { x = 0, y = 0, w = env.vw, h = max(env.vh, env.docH or 0) }
end
local function layoutAbs(ab)
  local cs = ab.cs
  local cb = containingBlock(ab)
  local l, r = lenOf(cs.left, cs, cb.w), lenOf(cs.right, cs, cb.w)
  local t, bt = lenOf(cs.top, cs, cb.h), lenOf(cs.bottom, cs, cb.h)
  local m, bd, pd = edges(cs, cb.w)
  ab.m, ab.bd, ab.pd = m, bd, pd
  local eh = bd.l + bd.r + pd.l + pd.r
  local w = lenOf(cs.width, cs, cb.w)
  if w and cs["box-sizing"] == "border-box" then w = w - eh end
  if not w then
    if l and r then w = cb.w - l - r - m.l - m.r - eh
    else resolveWidth(ab, cb.w, true); w = ab.cw end
  end
  local mxw = lenOf(cs["max-width"], cs, cb.w)
  if mxw then w = min(w, mxw - (cs["box-sizing"] == "border-box" and eh or 0)) end
  local mnw = lenOf(cs["min-width"], cs, cb.w)
  if mnw then w = max(w, mnw - (cs["box-sizing"] == "border-box" and eh or 0)) end
  ab.m, ab.bd, ab.pd = m, bd, pd
  ab.cw = max(0, w)
  local x
  if l then x = cb.x + l
  elseif r then x = cb.x + cb.w - r - ab.cw - eh - m.l - m.r
  else x = ab.staticX or cb.x end
  if not l and not r and (m.autoL and m.autoR) then x = cb.x end
  local h = lenOf(cs.height, cs, cb.h)
  local hasTB = t and bt
  if hasTB and not h then
    ab.definiteH = cb.h - t - bt - m.t - m.b - bd.t - bd.b - pd.t - pd.b
  end
  place(ab, x, 0)
  layoutBox(ab, ab.parentBox)
  if hasTB and not h then
    local hh = max(0, cb.h - t - bt - m.t - m.b)
    ab.ch = hh - bd.t - bd.b - pd.t - pd.b
    ab.h = hh
  end
  local y
  if t then y = cb.y + t
  elseif bt then y = cb.y + cb.h - bt - ab.h - m.t - m.b
  else y = ab.staticY or cb.y end
  -- margin auto with left and right (or top and bottom) both set centres the box
  if l and r and m.autoL and m.autoR then x = cb.x + l + (cb.w - l - r - ab.w) / 2 - m.l end
  if t and bt and m.autoT and m.autoB then y = cb.y + t + (cb.h - t - bt - ab.h) / 2 - m.t end
  shift(ab, x + m.l - ab.x, y + m.t - ab.y)
  ab.fixed = cb.fixed or (cb.box and cb.box.fixed)
  ab.positioned = true
  -- the box is drawn with its containing block (or the root)
  local holder = cb.box or env.root
  holder.kids[#holder.kids + 1] = ab
end

-- ---------------------------------------------------------------- the page
function L.layout(doc, e)
  env = e
  env.rem = env.rem or 16
  pass = pass + 1
  absQueue = {}
  local html = doc.html or doc
  local root = newBox(html, html.cs)
  env.root = root
  resolveWidth(root, env.vw, false)
  place(root, 0, 0)
  layoutBox(root, nil)
  env.docH = root.y + root.h + root.m.b
  local i = 1
  while i <= #absQueue do
    local ab = absQueue[i]
    if ab.n._absBox == ab then layoutAbs(ab) end
    i = i + 1
    if i > 2000 then break end
  end
  -- the page is as tall as the lowest box (absolute ones too)
  local bottom = env.docH
  local function low(b)
    if b.fixed then return end
    bottom = max(bottom, b.y + b.h)
    if b.clip then return end
    for _, k in ipairs(b.kids) do low(k) end
  end
  low(root)
  root.docH = bottom
  return root
end

-- ---------------------------------------------------------------- hit testing
-- the boxes in the order they are drawn: normal ones in tree order, positioned ones after their siblings by z-index
function L.paintOrder(b, out)
  local normal, pos = {}, {}
  for _, k in ipairs(b.kids) do
    local p = k.cs and k.cs.position
    if p and p ~= "static" then pos[#pos + 1] = k else normal[#normal + 1] = k end
  end
  if #pos > 1 then
    for i, k in ipairs(pos) do k._seq = i end
    table.sort(pos, function(a, c)
      local za, zc = tonumber(a.cs["z-index"]) or 0, tonumber(c.cs["z-index"]) or 0
      if za ~= zc then return za < zc end
      return a._seq < c._seq
    end)
  end
  out = out or {}
  local neg = {}
  for _, k in ipairs(pos) do if (tonumber(k.cs["z-index"]) or 0) < 0 then neg[#neg + 1] = k end end
  for _, k in ipairs(neg) do out[#out + 1] = k end
  for _, k in ipairs(normal) do out[#out + 1] = k end
  for _, k in ipairs(pos) do if (tonumber(k.cs["z-index"]) or 0) >= 0 then out[#out + 1] = k end end
  return out
end
-- the element under the page point X, Y (with the scroll of the page SY applied to boxes that are not fixed)
function L.hit(root, x, y, sy)
  local best
  local function visit(b, oy)
    if b.fixed then oy = 0 end
    local px, py = x, y + oy
    local inside = px >= b.x and px < b.x + b.w and py >= b.y and py < b.y + b.h
    if b.clip and not inside then return end
    if b.cs and b.cs.visibility ~= "hidden" and b.cs["pointer-events"] ~= "none" then
      if inside and not b.anon then best = b.n end
      for _, t in ipairs(b.decos) do
        if px >= t.x and px < t.x + t.w and py >= t.y and py < t.y + t.h then best = t.n end
      end
      for _, t in ipairs(b.texts) do
        if px >= t.x and px < t.x + t.w and py >= t.y and py < t.y + t.h then best = t.n end
      end
    end
    local ky = oy + (b.clip and (b.sy or 0) or 0)
    for _, k in ipairs(L.paintOrder(b)) do visit(k, ky) end
  end
  visit(root, sy or 0)
  return best
end
-- the box of node N (the first one), for getBoundingClientRect and scrolling to it
function L.boxOf(root, n)
  local found
  local function visit(b)
    if found then return end
    if b.n == n and not b.anon then found = b; return end
    for _, k in ipairs(b.kids) do visit(k) end
  end
  visit(root)
  if found then return found end
  -- an inline element: the rectangle around its text
  local x0, y0, x1, y1
  local function walk(b)
    for _, t in ipairs(b.texts) do
      local m = t.n
      while m and m ~= n do m = m.parent end
      if m then
        x0 = min(x0 or t.x, t.x); y0 = min(y0 or t.y, t.y); x1 = max(x1 or 0, t.x + t.w); y1 = max(y1 or 0, t.y + t.h)
      end
    end
    for _, k in ipairs(b.kids) do walk(k) end
  end
  walk(root)
  if x0 then return { x = x0, y = y0, w = x1 - x0, h = y1 - y0, inline = true } end
  return nil
end
return L
