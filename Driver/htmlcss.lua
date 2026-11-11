#!lua
-- htmlcss: style sheets of the html player (pure Lua): parsing CSS, selectors and their specificity, @media, the cascade with !important and
-- inheritance, var(--x), calc(), lengths and colours. The computed style of an element is node.cs (property -> text) with a few numbers
-- worked out: cs.fs (font size, px), cs.lh (line height, px), cs.bold, cs.italic, cs.mono, cs.fg (colour 0xRRGGBB).
--   local C = driver.load("htmlcss")
--   local sheet = C.parse(cssText)        ; C.compute(doc, { sheet1, sheet2 }, { vw = 800, vh = 480 })
local C = {}

-- ---------------------------------------------------------------- colours
local NAMES = { black = 0x000000, white = 0xffffff, red = 0xff0000, green = 0x008000, blue = 0x0000ff, yellow = 0xffff00, cyan = 0x00ffff, aqua = 0x00ffff,
  magenta = 0xff00ff, fuchsia = 0xff00ff, gray = 0x808080, grey = 0x808080, silver = 0xc0c0c0, maroon = 0x800000, olive = 0x808000, lime = 0x00ff00,
  navy = 0x000080, purple = 0x800080, teal = 0x008080, orange = 0xffa500, pink = 0xffc0cb, brown = 0xa52a2a, gold = 0xffd700, coral = 0xff7f50,
  tomato = 0xff6347, salmon = 0xfa8072, crimson = 0xdc143c, indigo = 0x4b0082, violet = 0xee82ee, orchid = 0xda70d6, plum = 0xdda0dd, khaki = 0xf0e68c,
  beige = 0xf5f5dc, ivory = 0xfffff0, linen = 0xfaf0e6, lavender = 0xe6e6fa, turquoise = 0x40e0d0, tan = 0xd2b48c, chocolate = 0xd2691e,
  darkred = 0x8b0000, darkgreen = 0x006400, darkblue = 0x00008b, darkgray = 0xa9a9a9, darkgrey = 0xa9a9a9, darkorange = 0xff8c00, darkviolet = 0x9400d3,
  lightgray = 0xd3d3d3, lightgrey = 0xd3d3d3, lightblue = 0xadd8e6, lightgreen = 0x90ee90, lightyellow = 0xffffe0, lightpink = 0xffb6c1,
  dimgray = 0x696969, dimgrey = 0x696969, gainsboro = 0xdcdcdc, whitesmoke = 0xf5f5f5, slategray = 0x708090, steelblue = 0x4682b4,
  royalblue = 0x4169e1, dodgerblue = 0x1e90ff, deepskyblue = 0x00bfff, skyblue = 0x87ceeb, cornflowerblue = 0x6495ed, midnightblue = 0x191970,
  seagreen = 0x2e8b57, forestgreen = 0x228b22, limegreen = 0x32cd32, olivedrab = 0x6b8e23, firebrick = 0xb22222, indianred = 0xcd5c5c,
  hotpink = 0xff69b4, deeppink = 0xff1493, mediumpurple = 0x9370db, rebeccapurple = 0x663399, slateblue = 0x6a5acd, darkslategray = 0x2f4f4f,
  aliceblue = 0xf0f8ff, ghostwhite = 0xf8f8ff, honeydew = 0xf0fff0, mintcream = 0xf5fffa, azure = 0xf0ffff, snow = 0xfffafa, seashell = 0xfff5ee,
  wheat = 0xf5deb3, peru = 0xcd853f, sienna = 0xa0522d, goldenrod = 0xdaa520, orangered = 0xff4500, springgreen = 0x00ff7f, aquamarine = 0x7fffd4,
  cadetblue = 0x5f9ea0, darkcyan = 0x008b8b, lightcyan = 0xe0ffff, mistyrose = 0xffe4e1, lemonchiffon = 0xfffacd, papayawhip = 0xffefd5 }
local function clamp(v, a, b) if v < a then return a end if v > b then return b end return v end
local function hsl(h, s, l)
  h = (h % 360) / 360
  local function f(n)
    local k = (n + h * 12) % 12
    return l - s * math.min(l, 1 - l) * math.max(-1, math.min(k - 3, 9 - k, 1))
  end
  return math.floor(f(0) * 255 + 0.5), math.floor(f(8) * 255 + 0.5), math.floor(f(4) * 255 + 0.5)
end
-- "#abc", "rgb(1 2 3 / 50%)", "hsl(...)", a name -> 0xRRGGBB, alpha (0..1); nil when it is not a colour
function C.color(s)
  if not s then return nil end
  s = s:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if s == "transparent" then return 0, 0 end
  local nm = NAMES[s]
  if nm then return nm, 1 end
  local hex = s:match("^#(%x+)$")
  if hex then
    if #hex == 3 or #hex == 4 then
      local r, g, b, a = hex:sub(1, 1), hex:sub(2, 2), hex:sub(3, 3), hex:sub(4, 4)
      return tonumber(r .. r .. g .. g .. b .. b, 16), a ~= "" and tonumber(a .. a, 16) / 255 or 1
    elseif #hex == 6 or #hex == 8 then
      return tonumber(hex:sub(1, 6), 16), #hex == 8 and tonumber(hex:sub(7, 8), 16) / 255 or 1
    end
    return nil
  end
  local fn, args = s:match("^(%a+)%((.*)%)$")
  if not fn then return nil end
  local v = {}
  for p in args:gmatch("[^,%s/]+") do v[#v + 1] = p end
  if #v < 3 then return nil end
  local function num(p, scale)
    local n = tonumber((p:gsub("%%$", "")))
    if not n then n = tonumber((p:gsub("deg$", ""))) or 0 end
    if p:find("%%$") then return n / 100 * scale end
    return n
  end
  local a = v[4] and clamp(num(v[4], 1), 0, 1) or 1
  if fn == "rgb" or fn == "rgba" then
    local r, g, b = clamp(num(v[1], 255), 0, 255), clamp(num(v[2], 255), 0, 255), clamp(num(v[3], 255), 0, 255)
    return (math.floor(r + 0.5) << 16) | (math.floor(g + 0.5) << 8) | math.floor(b + 0.5), a
  elseif fn == "hsl" or fn == "hsla" then
    local r, g, b = hsl(num(v[1], 360), clamp(num(v[2], 1), 0, 1), clamp(num(v[3], 1), 0, 1))
    return (r << 16) | (g << 8) | b, a
  end
  return nil
end
-- mixes colour A over B with the alpha AL (0..1)
function C.mix(a, b, al)
  if al >= 1 then return a end
  if al <= 0 then return b end
  local function ch(sh) return math.floor(((a >> sh) & 255) * al + ((b >> sh) & 255) * (1 - al) + 0.5) end
  return (ch(16) << 16) | (ch(8) << 8) | ch(0)
end

-- ---------------------------------------------------------------- lengths, calc()
local ABS = { px = 1, pt = 4 / 3, pc = 16, ["in"] = 96, cm = 96 / 2.54, mm = 96 / 25.4, q = 96 / 101.6 }
-- one value with its unit in px; ctx = { fs, ref (what % is of), rem, vw, vh }
local function unitPx(n, u, ctx)
  if u == "" or ABS[u] then return n * (ABS[u] or 1) end
  if u == "em" then return n * (ctx.fs or 16) end
  if u == "rem" then return n * (ctx.rem or 16) end
  if u == "%" then if not ctx.ref then return nil end return n * ctx.ref / 100 end
  if u == "vw" then return n * (ctx.vw or 800) / 100 end
  if u == "vh" then return n * (ctx.vh or 480) / 100 end
  if u == "vmin" then return n * math.min(ctx.vw or 800, ctx.vh or 480) / 100 end
  if u == "vmax" then return n * math.max(ctx.vw or 800, ctx.vh or 480) / 100 end
  if u == "ch" or u == "ex" then return n * (ctx.fs or 16) * 0.5 end
  if u == "fr" then return nil end
  return nil
end
-- calc(), min(), max(), clamp(): a small expression reader
local function calcExpr(s, ctx)
  local pos = 1
  local function ws() pos = s:find("[^%s]", pos) or (#s + 1) end
  local expr
  local function atom()
    ws()
    local c = s:sub(pos, pos)
    if c == "(" then
      pos = pos + 1
      local v = expr()
      ws(); if s:sub(pos, pos) == ")" then pos = pos + 1 end
      return v
    end
    local fn = s:match("^(%a+)%(", pos)
    if fn then
      pos = pos + #fn + 1
      local vals = {}
      repeat
        vals[#vals + 1] = expr()
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
      until d ~= ","
      if fn == "calc" then return vals[1] end
      for _, v in ipairs(vals) do if not v then return nil end end
      if fn == "min" then return math.min(table.unpack(vals)) end
      if fn == "max" then return math.max(table.unpack(vals)) end
      if fn == "clamp" and #vals == 3 then return math.max(vals[1], math.min(vals[2], vals[3])) end
      return nil
    end
    local num, unit = s:match("^([%+%-]?%d*%.?%d+[eE]?[%+%-]?%d*)(%a*%%?)", pos)
    if not num then num, unit = s:match("^([%+%-]?%d*%.?%d+)(%a*%%?)", pos) end
    if not num then pos = #s + 1; return nil end
    pos = pos + #num + #unit
    if unit == "" then return tonumber(num), true end
    return unitPx(tonumber(num), unit:lower(), ctx)
  end
  local function term()
    local v, plain = atom()
    while true do
      ws()
      local op = s:sub(pos, pos)
      if op ~= "*" and op ~= "/" then break end
      pos = pos + 1
      local w = atom()
      if not v or not w then return nil end
      if op == "*" then v = v * w else if w == 0 then return nil end v = v / w end
    end
    return v, plain
  end
  expr = function()
    local v = term()
    while true do
      ws()
      local op = s:sub(pos, pos)
      if op ~= "+" and op ~= "-" then break end
      pos = pos + 1
      local w = term()
      if not v or not w then return nil end
      v = op == "+" and v + w or v - w
    end
    return v
  end
  return expr()
end
-- a length in px, or nil for auto/none/what cannot be worked out
function C.len(v, ctx)
  if v == nil then return nil end
  if type(v) == "number" then return v end
  local n, u = v:match("^%s*([%+%-]?%d*%.?%d+)([%a%%]*)%s*$")
  if n then return unitPx(tonumber(n), u:lower(), ctx) end
  if v:find("^%s*%a+%(") then
    local f = v:match("^%s*(%a+)%(")
    if f == "calc" or f == "min" or f == "max" or f == "clamp" then return calcExpr(v, ctx) end
  end
  return nil
end

-- ---------------------------------------------------------------- declarations and shorthands
local function splitTop(s, sepPat)
  -- splits at SEP outside brackets and quotes
  local out, depth, q, start = {}, 0, nil, 1
  for i = 1, #s do
    local c = s:sub(i, i)
    if q then if c == q then q = nil end
    elseif c == '"' or c == "'" then q = c
    elseif c == "(" then depth = depth + 1
    elseif c == ")" then depth = depth - 1
    elseif depth == 0 and c:find(sepPat) then
      out[#out + 1] = s:sub(start, i - 1); start = i + 1
    end
  end
  out[#out + 1] = s:sub(start)
  return out
end
C.splitTop = splitTop
local function words(v)
  local t = {}
  for _, w in ipairs(splitTop(v, "%s")) do if w ~= "" then t[#t + 1] = w end end
  return t
end
C.words = words
local SIDES = { "top", "right", "bottom", "left" }
local function four(v)
  local w = words(v)
  local a, b, c, d = w[1], w[2] or w[1], w[3] or w[1], w[4] or w[2] or w[1]
  return { a, b, c, d }
end
local BSTYLE = { none = true, hidden = true, solid = true, dashed = true, dotted = true, double = true, groove = true, ridge = true, inset = true, outset = true }
local function isLen(w) return w:find("^[%+%-]?%d*%.?%d") or w:find("^calc%(") or w == "thin" or w == "medium" or w == "thick" end
local function borderParts(v)
  local wd, st, co = nil, nil, nil
  for _, w in ipairs(words(v)) do
    local lw = w:lower()
    if BSTYLE[lw] then st = lw elseif isLen(lw) then wd = lw else co = w end
  end
  return wd or "medium", st or "none", co or "currentcolor"
end
-- a property and its value -> the longhands (list of {prop, value})
function C.expand(p, v)
  local out = {}
  local function put(k, x) out[#out + 1] = { k, x } end
  if p == "margin" or p == "padding" then
    local f = four(v)
    for i, s in ipairs(SIDES) do put(p .. "-" .. s, f[i]) end
  elseif p == "inset" then
    local f = four(v)
    for i, s in ipairs(SIDES) do put(s, f[i]) end
  elseif p == "border" or p == "border-top" or p == "border-right" or p == "border-bottom" or p == "border-left" then
    local wd, st, co = borderParts(v)
    local sides = p == "border" and SIDES or { p:sub(8) }
    for _, s in ipairs(sides) do put("border-" .. s .. "-width", wd); put("border-" .. s .. "-style", st); put("border-" .. s .. "-color", co) end
  elseif p == "border-width" or p == "border-style" or p == "border-color" then
    local f = four(v)
    local what = p:sub(8)
    for i, s in ipairs(SIDES) do put("border-" .. s .. "-" .. what, f[i]) end
  elseif p == "border-radius" then
    put("border-radius", (splitTop(v, "/")[1]:match("^%s*(%S+)")) or "0")
  elseif p == "background" then
    local img, col = "none", "transparent"
    for _, w in ipairs(words(v)) do
      local lw = w:lower()
      if lw:find("^url%(") or lw:find("gradient%(") then img = w
      elseif C.color(lw) then col = w
      elseif lw == "cover" or lw == "contain" then put("background-size", lw) end
    end
    put("background-color", col); put("background-image", img)
  elseif p == "font" then
    local w = words(v)
    for i, x in ipairs(w) do
      local lx = x:lower()
      if lx == "italic" or lx == "oblique" then put("font-style", "italic")
      elseif lx == "bold" or lx == "bolder" or lx:match("^%d00$") then put("font-weight", lx)
      elseif isLen(lx) or lx:find("^%a+%-?%a*$") and (lx == "small" or lx == "medium" or lx == "large" or lx:find("x%-")) then
        local size, lh = x:match("^([^/]+)/(.+)$")
        put("font-size", size or x)
        if lh then put("line-height", lh) end
        local fam = table.concat(w, " ", i + 1)
        if fam ~= "" then put("font-family", fam) end
        break
      end
    end
  elseif p == "flex" then
    local w = words(v)
    if v == "none" then put("flex-grow", "0"); put("flex-shrink", "0"); put("flex-basis", "auto")
    elseif v == "auto" then put("flex-grow", "1"); put("flex-shrink", "1"); put("flex-basis", "auto")
    elseif #w == 1 and tonumber(w[1]) then put("flex-grow", w[1]); put("flex-shrink", "1"); put("flex-basis", "0%")
    elseif #w == 1 then put("flex-grow", "1"); put("flex-shrink", "1"); put("flex-basis", w[1])
    else
      put("flex-grow", w[1])
      if tonumber(w[2]) then put("flex-shrink", w[2]); put("flex-basis", w[3] or "0%") else put("flex-shrink", "1"); put("flex-basis", w[2]) end
    end
  elseif p == "flex-flow" then
    for _, x in ipairs(words(v)) do
      if x:find("wrap") then put("flex-wrap", x) else put("flex-direction", x) end
    end
  elseif p == "gap" or p == "grid-gap" then
    local w = words(v)
    put("row-gap", w[1]); put("column-gap", w[2] or w[1])
  elseif p == "grid-row-gap" then put("row-gap", v)
  elseif p == "grid-column-gap" then put("column-gap", v)
  elseif p == "list-style" then
    for _, x in ipairs(words(v)) do
      if x ~= "inside" and x ~= "outside" and not x:find("^url") then put("list-style-type", x) end
      if x == "inside" or x == "outside" then put("list-style-position", x) end
    end
  elseif p == "text-decoration" or p == "text-decoration-line" then
    local line = "none"
    for _, x in ipairs(words(v)) do if x == "underline" or x == "line-through" or x == "overline" then line = x end end
    put("text-decoration", line)
  elseif p == "overflow" then
    local w = words(v)
    put("overflow-x", w[1]); put("overflow-y", w[2] or w[1])
  elseif p == "place-items" then
    local w = words(v); put("align-items", w[1]); put("justify-items", w[2] or w[1])
  elseif p == "place-content" then
    local w = words(v); put("align-content", w[1]); put("justify-content", w[2] or w[1])
  elseif p == "place-self" then
    local w = words(v); put("align-self", w[1]); put("justify-self", w[2] or w[1])
  elseif p == "grid-area" then
    local w = splitTop(v, "/")
    put("grid-row", w[1]); if w[2] then put("grid-column", w[2]) end
  else
    put(p, v)
  end
  return out
end

-- "a: b; c: d !important" -> list of { prop, value, important }
function C.decls(text)
  local out = {}
  for _, d in ipairs(splitTop(text, ";")) do
    local p, v = d:match("^%s*([%-%w]+)%s*:%s*(.-)%s*$")
    if p and v ~= "" then
      local imp = false
      local v2 = v:match("^(.-)%s*!%s*[Ii][Mm][Pp][Oo][Rr][Tt][Aa][Nn][Tt]$")
      if v2 then v = v2; imp = true end
      if p:sub(1, 2) == "--" then out[#out + 1] = { p, v, imp }
      else
        p = p:lower()
        local ex = C.expand(p, v)
        -- a shorthand with var() is expanded when the variables are known (in the cascade)
        if v:find("var(", 1, true) and (#ex ~= 1 or ex[1][1] ~= p) then out[#out + 1] = { p, v, imp, true }
        else for _, e in ipairs(ex) do out[#out + 1] = { e[1], e[2], imp } end end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- selectors
-- a complex selector is a list: compound, combinator, compound, ... (the subject is the last one)
local parseList
-- a name in a selector; a backslash keeps the next character (".sm\:flex")
local function ident(s, i)
  local out = {}
  while i <= #s do
    local t = s:match("^[%w_%-\128-\255]+", i)
    if t then out[#out + 1] = t; i = i + #t
    elseif s:sub(i, i) == "\\" and i < #s then out[#out + 1] = s:sub(i + 1, i + 1); i = i + 2
    else break end
  end
  return table.concat(out), i
end
local function parseCompound(s, i)
  local c = { classes = {}, attrs = {}, pseudos = {} }
  local n = #s
  local any = false
  while i <= n do
    local ch = s:sub(i, i)
    if ch == "*" then c.tag = nil; i = i + 1; any = true
    elseif ch:find("[%w_%-]") and not any and not c.tag and #c.classes == 0 and not c.id and #c.attrs == 0 and #c.pseudos == 0 then
      local t = s:match("^[%w_%-]+", i); c.tag = t:lower(); i = i + #t; any = true
    elseif ch == "#" then local t, j = ident(s, i + 1); c.id = t; i = j; any = true
    elseif ch == "." then local t, j = ident(s, i + 1); c.classes[#c.classes + 1] = t; i = j; any = true
    elseif ch == "[" then
      local close = s:find("]", i, true) or n
      local body = s:sub(i + 1, close - 1)
      local name, op, val = body:match("^%s*([%w_%-:]+)%s*([~|%^%$%*]?=)%s*(.-)%s*$")
      if not name then name = body:match("^%s*([%w_%-:]+)") end
      if val then
        local fl = val:match("%s+([iIsS])$")
        val = val:gsub("%s+[iIsS]$", ""):gsub("^[\"'](.*)[\"']$", "%1")
        c.attrs[#c.attrs + 1] = { name = name:lower(), op = op, val = val, ci = fl == "i" or fl == "I" }
      else c.attrs[#c.attrs + 1] = { name = (name or ""):lower() } end
      i = close + 1; any = true
    elseif ch == ":" then
      local el = s:sub(i + 1, i + 1) == ":"
      local j = el and i + 2 or i + 1
      local name = (s:match("^[%w%-]+", j) or ""):lower()
      j = j + #name
      local arg
      if s:sub(j, j) == "(" then
        local depth, k = 1, j + 1
        while k <= n and depth > 0 do
          local x = s:sub(k, k)
          if x == "(" then depth = depth + 1 elseif x == ")" then depth = depth - 1 end
          k = k + 1
        end
        arg = s:sub(j + 1, k - 2)
        j = k
      end
      if el or name == "before" or name == "after" or name == "first-line" or name == "first-letter" or name == "placeholder" or name == "marker" or name == "selection" then
        c.pseudoEl = name
      else
        local p = { name = name, arg = arg }
        if (name == "not" or name == "is" or name == "where" or name == "matches") and arg then p.list = parseList(arg) end
        if (name == "nth-child" or name == "nth-last-child" or name == "nth-of-type" or name == "nth-last-of-type") and arg then
          local a = arg:gsub("%s", ""):lower()
          if a == "odd" then p.a, p.b = 2, 1 elseif a == "even" then p.a, p.b = 2, 0
          else
            local an, bn = a:match("^([%+%-]?%d*)n([%+%-]?%d*)$")
            if an then
              p.a = (an == "" or an == "+") and 1 or an == "-" and -1 or tonumber(an)
              p.b = tonumber(bn) or 0
            else p.a, p.b = 0, tonumber(a) or 0 end
          end
        end
        c.pseudos[#c.pseudos + 1] = p
      end
      i = j; any = true
    else break end
  end
  return c, i
end
local function parseComplex(s)
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil end
  local out = {}
  local i, n = 1, #s
  while i <= n do
    local c, j = parseCompound(s, i)
    if j == i then return nil end -- something it cannot read
    out[#out + 1] = c
    i = j
    local a, b = s:find("^%s*([>+~])%s*", i)
    if a then
      out[#out + 1] = s:match("^%s*([>+~])", i)
      i = b + 1
    else
      local w1, w2 = s:find("^%s+", i)
      if w1 and w2 < n then out[#out + 1] = " "; i = w2 + 1 elseif w1 then i = w2 + 1 end
    end
  end
  return out
end
parseList = function(s)
  local list = {}
  for _, part in ipairs(splitTop(s, ",")) do
    local c = parseComplex(part)
    if c then list[#list + 1] = c end
  end
  return list
end
C.selector = parseList

local specOf
local function specCompound(c)
  local a, b, d = c.id and 1 or 0, #c.classes + #c.attrs, (c.tag and 1 or 0) + (c.pseudoEl and 1 or 0)
  for _, p in ipairs(c.pseudos) do
    if p.list then
      if p.name ~= "where" then
        local best = 0
        for _, s in ipairs(p.list) do best = math.max(best, specOf(s)) end
        a = a + best // 10000; b = b + (best // 100) % 100; d = d + best % 100
      end
    else b = b + 1 end
  end
  return a * 10000 + b * 100 + d
end
specOf = function(sel)
  local s = 0
  for i = 1, #sel, 2 do s = s + specCompound(sel[i]) end
  return s
end
C.spec = specOf

local function classSet(n)
  local cls = n.attrs.class
  if n._clsSrc ~= cls or not n._cls then
    local set = {}
    if cls then for w in cls:gmatch("%S+") do set[w] = true end end
    n._cls, n._clsSrc = set, cls
  end
  return n._cls
end
C.classSet = classSet
local function elemKids(p)
  local out = {}
  if p then for _, k in ipairs(p.kids) do if k.type == "el" then out[#out + 1] = k end end end
  return out
end
local function position(n, ofType, fromEnd)
  local sib = elemKids(n.parent)
  local count, idx = 0, 0
  local a, b, step = 1, #sib, 1
  if fromEnd then a, b, step = #sib, 1, -1 end
  for i = a, b, step do
    local k = sib[i]
    if not ofType or k.tag == n.tag then
      count = count + 1
      if k == n then idx = count end
    end
  end
  return idx, count
end
local matchComplex
local function matchList(n, list)
  for _, s in ipairs(list) do if matchComplex(n, s, #s) then return true end end
  return false
end
local function matchCompound(n, c)
  if n.type ~= "el" then return false end
  if c.tag and c.tag ~= n.tag then return false end
  if c.id and n.attrs.id ~= c.id then return false end
  if #c.classes > 0 then
    local set = classSet(n)
    for _, k in ipairs(c.classes) do if not set[k] then return false end end
  end
  for _, a in ipairs(c.attrs) do
    local v = n.attrs[a.name]
    if v == nil then return false end
    if a.op then
      local want = a.val
      if a.ci then v = v:lower(); want = want:lower() end
      local op = a.op
      if op == "=" and v ~= want then return false end
      if op == "~=" then local ok = false; for w in v:gmatch("%S+") do if w == want then ok = true end end if not ok then return false end end
      if op == "^=" and (want == "" or v:sub(1, #want) ~= want) then return false end
      if op == "$=" and (want == "" or v:sub(-#want) ~= want) then return false end
      if op == "*=" and (want == "" or not v:find(want, 1, true)) then return false end
      if op == "|=" and v ~= want and v:sub(1, #want + 1) ~= want .. "-" then return false end
    end
  end
  for _, p in ipairs(c.pseudos) do
    local nm = p.name
    if nm == "hover" then if not n.hover then return false end
    elseif nm == "focus" or nm == "focus-visible" then if not n.focus then return false end
    elseif nm == "focus-within" then
      local ok = false
      local d = C.focused
      while d do if d == n then ok = true; break end d = d.parent end
      if not ok then return false end
    elseif nm == "active" then if not n.active then return false end
    elseif nm == "checked" then if not n.checked and not (n.tag == "option" and n.selected) then return false end
    elseif nm == "disabled" then if n.attrs.disabled == nil then return false end
    elseif nm == "enabled" then if n.attrs.disabled ~= nil then return false end
    elseif nm == "root" then if n.tag ~= "html" then return false end
    elseif nm == "empty" then if #n.kids > 0 then return false end
    elseif nm == "link" or nm == "any-link" then if n.tag ~= "a" or not n.attrs.href then return false end
    elseif nm == "visited" or nm == "target" or nm == "has" then return false
    elseif nm == "first-child" then if position(n) ~= 1 then return false end
    elseif nm == "last-child" then if position(n, false, true) ~= 1 then return false end
    elseif nm == "only-child" then local _, c2 = position(n); if c2 ~= 1 then return false end
    elseif nm == "first-of-type" then if position(n, true) ~= 1 then return false end
    elseif nm == "last-of-type" then if position(n, true, true) ~= 1 then return false end
    elseif nm == "only-of-type" then local _, c2 = position(n, true); if c2 ~= 1 then return false end
    elseif p.a then
      local idx = position(n, nm:find("of%-type") ~= nil, nm:find("last") ~= nil)
      local a, b = p.a, p.b
      if a == 0 then if idx ~= b then return false end
      else
        local k = (idx - b) / a
        if k < 0 or k ~= math.floor(k) then return false end
      end
    elseif nm == "not" then if p.list and matchList(n, p.list) then return false end
    elseif nm == "is" or nm == "where" or nm == "matches" then if not p.list or not matchList(n, p.list) then return false end
    elseif nm == "placeholder-shown" then if (n.value or n.attrs.value or "") ~= "" then return false end
    else return false end
  end
  return true
end
local function prevElem(n)
  local p = n.parent
  if not p then return nil end
  local prev
  for _, k in ipairs(p.kids) do
    if k == n then return prev end
    if k.type == "el" then prev = k end
  end
end
matchComplex = function(n, sel, i)
  if not matchCompound(n, sel[i]) then return false end
  if i == 1 then return true end
  local comb = sel[i - 1]
  if comb == ">" then
    local p = n.parent
    return p ~= nil and p.type == "el" and matchComplex(p, sel, i - 2)
  elseif comb == " " then
    local p = n.parent
    while p and p.type == "el" do
      if matchComplex(p, sel, i - 2) then return true end
      p = p.parent
    end
    return false
  elseif comb == "+" then
    local p = prevElem(n)
    return p ~= nil and matchComplex(p, sel, i - 2)
  elseif comb == "~" then
    local p = prevElem(n)
    while p do
      if matchComplex(p, sel, i - 2) then return true end
      p = prevElem(p)
    end
    return false
  end
  return false
end
-- true when the element N matches the selector text (or a parsed list)
function C.matches(n, sel)
  if type(sel) == "string" then sel = parseList(sel) end
  for _, s in ipairs(sel) do
    if not s[#s].pseudoEl and matchComplex(n, s, #s) then return true end
  end
  return false
end
-- the elements under ROOT that match SEL (all of them, or the first one)
function C.query(root, sel, first)
  local list = type(sel) == "string" and parseList(sel) or sel
  local out = {}
  local function walk(x)
    for _, k in ipairs(x.kids or {}) do
      if k.type == "el" then
        if C.matches(k, list) then
          out[#out + 1] = k
          if first then return true end
        end
        if walk(k) then return true end
      end
    end
  end
  walk(root)
  return out
end

-- ---------------------------------------------------------------- media queries
function C.media(q, env)
  q = q:lower()
  for _, part in ipairs(splitTop(q, ",")) do
    local ok = true
    local p = part:gsub("^%s+", "")
    local neg = false
    if p:find("^not%s") then neg = true; p = p:gsub("^not%s+", "") end
    p = p:gsub("^only%s+", "")
    local mtype = p:match("^(%a+)")
    if mtype and mtype ~= "and" then
      if mtype == "print" or mtype == "speech" then ok = false end
    end
    for feat, val in p:gmatch("%(%s*([%w%-]+)%s*:?%s*([^%)]*)%)") do
      local ctx = { fs = 16, rem = 16, vw = env.vw, vh = env.vh }
      local px = C.len(val, ctx)
      if feat == "max-width" then ok = ok and px ~= nil and env.vw <= px
      elseif feat == "min-width" then ok = ok and px ~= nil and env.vw >= px
      elseif feat == "max-height" then ok = ok and px ~= nil and env.vh <= px
      elseif feat == "min-height" then ok = ok and px ~= nil and env.vh >= px
      elseif feat == "orientation" then ok = ok and ((val == "landscape") == (env.vw >= env.vh))
      elseif feat == "prefers-color-scheme" then ok = ok and val == (env.scheme or "light")
      elseif feat == "prefers-reduced-motion" then ok = ok and val == "no-preference"
      elseif feat == "hover" then ok = ok and val == "none"
      elseif feat == "pointer" then ok = ok and val == "coarse"
      elseif feat == "width" then ok = ok and px ~= nil and math.abs(env.vw - px) < 1
      else ok = false end
    end
    if neg then ok = not ok end
    if ok then return true end
  end
  return false
end

-- ---------------------------------------------------------------- style sheets
local function stripComments(s) return (s:gsub("/%*.-%*/", "")) end
local function matchBrace(s, i)
  local depth, q = 0, nil
  for k = i, #s do
    local c = s:sub(k, k)
    if q then if c == q and s:sub(k - 1, k - 1) ~= "\\" then q = nil end
    elseif c == '"' or c == "'" then q = c
    elseif c == "{" then depth = depth + 1
    elseif c == "}" then depth = depth - 1; if depth == 0 then return k end end
  end
  return #s
end
local orderSeq = 0
-- a style sheet: { rules = { { sel, spec, order, decls, pseudo, media } }, imports = { url } }
function C.parse(text, media)
  local sheet = { rules = {}, imports = {} }
  local function block(s, mq)
    local i, n = 1, #s
    while i <= n do
      local a = s:find("[^%s]", i)
      if not a then break end
      if s:sub(a, a) == "@" then
        local name = s:match("^@([%w%-]+)", a) or ""
        local brace = s:find("[{;]", a)
        if not brace then break end
        if s:sub(brace, brace) == ";" then
          if name == "import" then
            local u = s:sub(a, brace):match("url%(%s*[\"']?([^\"')]+)") or s:sub(a, brace):match("[\"']([^\"']+)[\"']")
            if u then sheet.imports[#sheet.imports + 1] = u end
          end
          i = brace + 1
        else
          local close = matchBrace(s, brace)
          if name == "media" then
            local q = s:sub(a + 6, brace - 1)
            block(s:sub(brace + 1, close - 1), mq and { mq, q } or q)
          elseif name == "supports" or name == "layer" or name == "container" then
            block(s:sub(brace + 1, close - 1), mq)
          end
          i = close + 1
        end
      else
        local brace = s:find("{", a, true)
        if not brace then break end
        local close = matchBrace(s, brace)
        local selText = s:sub(a, brace - 1)
        local decls = C.decls(s:sub(brace + 1, close - 1))
        if #decls > 0 then
          for _, sel in ipairs(parseList(selText)) do
            orderSeq = orderSeq + 1
            sheet.rules[#sheet.rules + 1] = { sel = sel, spec = specOf(sel), order = orderSeq, decls = decls, pseudo = sel[#sel].pseudoEl, media = mq }
          end
        end
        i = close + 1
      end
    end
  end
  block(stripComments(text or ""), media)
  return sheet
end
local function mediaOk(mq, env)
  if not mq then return true end
  if type(mq) == "table" then for _, q in ipairs(mq) do if not mediaOk(q, env) then return false end end return true end
  return C.media(mq, env)
end

-- the browser's own style
C.UA = [[
html,body,div,p,h1,h2,h3,h4,h5,h6,ul,ol,dl,dt,dd,form,header,footer,section,article,nav,main,aside,figure,figcaption,blockquote,pre,hr,address,fieldset,details,summary,center,legend,dialog,menu,hgroup,search{display:block}
head,script,style,title,meta,link,template,noscript,base,datalist,param,source,track{display:none}
[hidden]{display:none}
body{margin:8px}
h1{font-size:2em;margin:.67em 0;font-weight:bold}
h2{font-size:1.5em;margin:.83em 0;font-weight:bold}
h3{font-size:1.17em;margin:1em 0;font-weight:bold}
h4{margin:1.33em 0;font-weight:bold}
h5{font-size:.83em;margin:1.67em 0;font-weight:bold}
h6{font-size:.67em;margin:2.33em 0;font-weight:bold}
p,dl,figure{margin:1em 0}
figure{margin:1em 40px}
dd{margin-left:40px}
ul,ol,menu{margin:1em 0;padding-left:40px}
ul{list-style-type:disc}
ol{list-style-type:decimal}
ul ul,ol ul{list-style-type:circle;margin:0}
ol ol,ul ol{margin:0}
li{display:list-item}
b,strong,th,dt{font-weight:bold}
i,em,cite,var,dfn,address{font-style:italic}
u,ins{text-decoration:underline}
s,del,strike{text-decoration:line-through}
a{color:#0000ee;text-decoration:underline}
code,kbd,samp,pre,tt{font-family:monospace}
pre{white-space:pre;margin:1em 0}
small,sub,sup{font-size:smaller}
big{font-size:larger}
mark{background-color:yellow;color:black}
blockquote{margin:1em 40px}
center{text-align:center}
hr{border:1px solid #9a9a9a;margin:.5em 0;height:0}
table{display:table;border-spacing:2px;border-collapse:separate}
caption{display:table-caption;text-align:center}
thead,tbody,tfoot{display:table-row-group}
tr{display:table-row}
td,th{display:table-cell;padding:1px}
th{text-align:center}
img,canvas,video,audio,iframe,svg,object,embed,progress,meter{display:inline-block}
input,button,select,textarea{display:inline-block;font-size:13px}
button{padding:2px 8px;border:1px solid #767676;background-color:#efefef;border-radius:3px;text-align:center}
input,textarea,select{border:1px solid #767676;background-color:white;padding:2px 3px}
input[type=checkbox],input[type=radio]{border:0;padding:0;margin:3px 4px}
input[type=submit],input[type=button],input[type=reset]{background-color:#efefef;border-radius:3px;padding:2px 8px}
input[type=hidden]{display:none}
fieldset{border:2px solid #c0c0c0;padding:.35em .75em .6em;margin:0 2px}
summary{display:block;font-weight:bold}
details:not([open])>:not(summary){display:none}
dialog:not([open]){display:none}
dialog{position:absolute;left:0;right:0;margin:auto;border:2px solid #333;padding:1em;background-color:white;width:fit-content}
label{cursor:pointer}
]]

local INHERITED = {}
for w in ("color font-size font-weight font-style font-family text-align line-height text-decoration white-space visibility list-style-type list-style-position cursor letter-spacing text-transform word-break overflow-wrap word-wrap border-collapse border-spacing text-indent direction"):gmatch("%S+") do INHERITED[w] = true end
C.INHERITED = INHERITED
local SIZES = { ["xx-small"] = 9, ["x-small"] = 10, small = 13, medium = 16, large = 18, ["x-large"] = 24, ["xx-large"] = 32, ["xxx-large"] = 48 }

-- the rules indexed by the key of their subject (id, class, tag), for a set of sheets and a viewport
function C.index(sheets, env)
  local idx = { id = {}, class = {}, tag = {}, any = {}, hover = false }
  for _, sh in ipairs(sheets) do
    for _, r in ipairs(sh.rules) do
      if mediaOk(r.media, env) then
        local subj = r.sel[#r.sel]
        local bucket
        if subj.id then bucket = idx.id; r.key = subj.id
        elseif subj.classes[1] then bucket = idx.class; r.key = subj.classes[1]
        elseif subj.tag then bucket = idx.tag; r.key = subj.tag end
        if bucket then
          bucket[r.key] = bucket[r.key] or {}
          table.insert(bucket[r.key], r)
        else idx.any[#idx.any + 1] = r end
        for i = 1, #r.sel, 2 do
          for _, p in ipairs(r.sel[i].pseudos) do
            if p.name == "hover" or p.name == "active" then idx.hover = true end
            if p.name == "focus" or p.name == "focus-within" or p.name == "focus-visible" then idx.focus = true end
          end
        end
      end
    end
  end
  return idx
end

local function matched(n, idx)
  local list = {}
  local function try(rules)
    if not rules then return end
    for _, r in ipairs(rules) do if matchComplex(n, r.sel, #r.sel) then list[#list + 1] = r end end
  end
  if n.attrs.id then try(idx.id[n.attrs.id]) end
  for c in pairs(classSet(n)) do try(idx.class[c]) end
  try(idx.tag[n.tag])
  try(idx.any)
  table.sort(list, function(a, b)
    if a.ua ~= b.ua then return a.ua == true end
    if a.spec ~= b.spec then return a.spec < b.spec end
    return a.order < b.order
  end)
  return list
end

-- var(--x, fallback) in V, with the custom properties of CS
local function subVars(v, cs, depth)
  depth = depth or 0
  if depth > 8 or not v:find("var(", 1, true) then return v end
  local out = v:gsub("var%(%s*(%-%-[%w%-_]+)%s*,?%s*(.-)%)", function(name, fb)
    local x = cs[name]
    if x == nil then x = fb ~= "" and fb or nil end
    if x == nil then return "" end
    return x
  end)
  -- a fallback may hold another var() with its own brackets: run again
  if out:find("var(", 1, true) then out = subVars(out, cs, depth + 1) end
  return out
end
local inlineCache = setmetatable({}, { __mode = "k" })
local function inlineDecls(n)
  local s = n.attrs.style
  if not s then return nil end
  local c = inlineCache[n]
  if c and c.src == s then return c.d end
  local d = C.decls(s)
  inlineCache[n] = { src = s, d = d }
  return d
end

local function fontSize(v, pfs, rem, env)
  if not v then return pfs end
  if SIZES[v] then return SIZES[v] end
  if v == "smaller" then return pfs / 1.2 end
  if v == "larger" then return pfs * 1.2 end
  return C.len(v, { fs = pfs, ref = pfs, rem = rem, vw = env.vw, vh = env.vh }) or pfs
end

-- works out the style of one element (or of a ::before/::after when PSEUDO is given) from its rules and its parent
local function cascade(n, rules, pcs, env, pseudo)
  local spec, imp, seq, iseq, pend = {}, {}, {}, {}, nil
  local k = 0
  local function apply(d)
    k = k + 1
    if d[4] then
      pend = pend or {}
      pend[#pend + 1] = { d[1], d[2], d[3], k }
    elseif d[3] then imp[d[1]] = d[2]; iseq[d[1]] = k
    else spec[d[1]] = d[2]; seq[d[1]] = k end
  end
  for _, r in ipairs(rules) do
    if r.pseudo == pseudo then
      for _, d in ipairs(r.decls) do apply(d) end
    end
  end
  if not pseudo then
    local inl = inlineDecls(n)
    if inl then for _, d in ipairs(inl) do apply(d) end end
    -- presentational attributes (lowest priority: only when no rule set them)
    local a = n.attrs
    if a.bgcolor and not spec["background-color"] then spec["background-color"] = a.bgcolor end
    if n.tag == "font" and a.color and not spec.color then spec.color = a.color end
    if a.align and not spec["text-align"] and n.tag ~= "img" then spec["text-align"] = a.align end
    if (n.tag == "td" or n.tag == "th" or n.tag == "table" or n.tag == "col") and a.width and not spec.width then spec.width = a.width:find("%%") and a.width or (a.width .. "px") end
  end
  for k, v in pairs(imp) do spec[k] = v end
  local cs = {}
  -- inherited properties and custom properties come from the parent
  if pcs then
    for k, v in pairs(pcs) do
      if type(k) == "string" and (INHERITED[k] or k:sub(1, 2) == "--") then cs[k] = v end
    end
  end
  -- custom properties first: other values may use them
  for k, v in pairs(spec) do if k:sub(1, 2) == "--" then cs[k] = v end end
  for k, v in pairs(spec) do if k:sub(1, 2) == "--" and v:find("var(", 1, true) then cs[k] = subVars(v, cs) end end
  -- the shorthands that used var(): expanded now, where no later longhand set the same property
  if pend then
    for _, d in ipairs(pend) do
      for _, e in ipairs(C.expand(d[1], subVars(d[2], cs))) do
        if d[3] then if (iseq[e[1]] or -1) < d[4] then imp[e[1]] = e[2]; iseq[e[1]] = d[4] end
        elseif (seq[e[1]] or -1) < d[4] then spec[e[1]] = e[2]; seq[e[1]] = d[4] end
      end
    end
    for k2, v in pairs(imp) do spec[k2] = v end
  end
  for k, v in pairs(spec) do
    if k:sub(1, 2) ~= "--" then
      v = subVars(v, cs)
      if v == "inherit" then cs[k] = pcs and pcs[k] or nil
      elseif v == "initial" or v == "unset" or v == "revert" then cs[k] = (v == "unset" and INHERITED[k] and pcs) and pcs[k] or nil
      else cs[k] = v end
    end
  end
  -- numbers
  local rem = env.rem or 16
  local pfs = pcs and pcs.fs or 16
  cs.fs = fontSize(spec["font-size"] and cs["font-size"], pfs, rem, env)
  if n.tag == "html" and not pseudo then env.rem = cs.fs end
  local w = cs["font-weight"] or "normal"
  cs.bold = w == "bold" or w == "bolder" or (tonumber(w) or 400) >= 600
  cs.italic = (cs["font-style"] or "normal") ~= "normal"
  local fam = (cs["font-family"] or ""):lower()
  cs.mono = fam:find("mono") ~= nil or fam:find("courier") ~= nil or fam:find("consolas") ~= nil
  local lh = cs["line-height"]
  local lhn = lh and tonumber(lh)
  if not lh or lh == "normal" then cs.lh = math.floor(cs.fs * 1.2 + 0.5)
  elseif lhn then cs.lh = math.floor(cs.fs * lhn + 0.5)
  else cs.lh = math.floor((C.len(lh, { fs = cs.fs, ref = cs.fs, rem = rem, vw = env.vw, vh = env.vh }) or cs.fs * 1.2) + 0.5) end
  local col = cs.color
  local fg, fa = C.color(col or "")
  if not fg then fg, fa = pcs and pcs.fg or 0, pcs and pcs.fa or 1 end
  cs.fg, cs.fa = fg, fa
  return cs
end

-- the text of `content` (strings, attr(), \hex escapes)
local function contentText(v, n)
  if not v or v == "none" or v == "normal" then return nil end
  local out = {}
  for _, w in ipairs(words(v)) do
    local q = w:match('^"(.*)"$') or w:match("^'(.*)'$")
    if q then
      q = q:gsub("\\(%x%x?%x?%x?%x?%x?)%s?", function(h) return utf8.char(tonumber(h, 16)) end)
      out[#out + 1] = q
    else
      local a = w:match("^attr%(%s*([%w%-]+)%s*%)$")
      if a then out[#out + 1] = n.attrs[a] or "" end
    end
  end
  return table.concat(out)
end

-- computes node.cs for every element of DOC; nodes whose rules did not change keep their matched list (gen is bumped on changes)
C.gen = 0
function C.compute(doc, sheets, env, idx)
  idx = idx or C.index(sheets, env)
  env.rem = 16
  local gen = C.gen
  local function visit(n, pcs)
    if n._mgen ~= gen or not n._rules then n._rules = matched(n, idx); n._mgen = gen end
    local cs = cascade(n, n._rules, pcs, env)
    n.cs = cs
    n.before, n.after = nil, nil
    if cs.display ~= "none" then
      for _, which in ipairs({ "before", "after" }) do
        local has = false
        for _, r in ipairs(n._rules) do if r.pseudo == which then has = true; break end end
        if has then
          local pc = cascade(n, n._rules, cs, env, which)
          local text = contentText(pc.content, n)
          if text then
            local p = { type = "el", tag = "::" .. which, attrs = {}, order = {}, kids = {}, parent = n, pseudo = true, cs = pc }
            if text ~= "" then p.kids[1] = { type = "text", text = text, parent = p } end
            n[which] = p
          end
        end
      end
      for _, k in ipairs(n.kids) do
        if k.type == "el" then visit(k, cs) end
      end
    end
  end
  local root = doc.html or doc
  local base = { fs = 16, fg = 0, fa = 1 }
  if root.type == "el" then visit(root, base) end
  return idx
end
-- the UA sheet is parsed once
local uaSheet
function C.ua()
  if not uaSheet then
    uaSheet = C.parse(C.UA)
    for _, r in ipairs(uaSheet.rules) do r.ua = true end
  end
  return uaSheet
end
return C
