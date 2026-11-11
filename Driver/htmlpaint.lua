#!lua
-- htmlpaint: draws the boxes of htmllayout and the pictures of <canvas> through a small drawing API (pure Lua, the device is behind API):
--   api.fill(x, y, w, h, c)  api.alpha(x, y, w, h, c, a255)  api.round(x, y, w, h, r, c)  api.line(x1, y1, x2, y2, c)  api.triangle(...)
--   api.disc(x, y, r, c)  api.circle(x, y, r, c)  api.text(x, y, s, c, font)  api.fh(font)  api.tw(s, font)  api.image(src, x, y, w, h, cover)
--   api.gradient(x, y, w, h, c1, c2, horizontal)  api.clip(x, y, w, h) / api.clip()
--   P.paint(root, view)   view = { api, sy (page scroll), vw, vh, rect (only this part), focus (node), caret (bool), fontOf, url(src) }
local P = {}
-- the drivers of the player are loaded once and shared (driver.load makes a new copy each time)
local function need(name)
  local reg = rawget(_G, "HTML_DRIVERS") or {}
  rawset(_G, "HTML_DRIVERS", reg)
  if not reg[name] then reg[name] = assert(driver.load(name)) end
  return reg[name]
end
local C = need("htmlcss")
local L = need("htmllayout")
local floor, max, min = math.floor, math.max, math.min

local function isect(a, b)
  if not a then return b end
  if not b then return a end
  local x0, y0 = max(a[1], b[1]), max(a[2], b[2])
  local x1, y1 = min(a[1] + a[3], b[1] + b[3]), min(a[2] + a[4], b[2] + b[4])
  if x1 <= x0 or y1 <= y0 then return { x0, y0, 0, 0 } end
  return { x0, y0, x1 - x0, y1 - y0 }
end
P.isect = isect

local api, view
local function restoreClip()
  local c = view.cr
  if c then api.clip(c[1], c[2], c[3], c[4]) else api.clip() end
end
local function visible(x, y, w, h, clip)
  if w <= 0 or h <= 0 then return false end
  if clip and (x >= clip[1] + clip[3] or y >= clip[2] + clip[4] or x + w <= clip[1] or y + h <= clip[2]) then return false end
  return true
end
local function colorOf(v, cur)
  if not v then return nil end
  if v == "currentcolor" or v == "currentColor" then return cur, 1 end
  local c, a = C.color(v)
  if not c then return nil end
  return c, a
end
local function box4(x, y, w, h, c, a, r)
  x, y, w, h = floor(x + 0.5), floor(y + 0.5), floor(w + 0.5), floor(h + 0.5)
  if w <= 0 or h <= 0 then return end
  if a and a < 0.99 then api.alpha(x, y, w, h, c, floor(a * 255 + 0.5))
  elseif r and r > 0.5 then api.round(x, y, w, h, min(r, w / 2, h / 2), c)
  else api.fill(x, y, w, h, c) end
end

-- the colour of a page point's background (for text faded by opacity and canvas clearing)
local function bgOf(b)
  while b do
    local c, a = colorOf(b.cs and b.cs["background-color"], 0)
    if c and a > 0.5 then return c end
    b = b.parent
  end
  return view.pageBg or 0xffffff
end

-- ---------------------------------------------------------------- canvas pictures
-- OPS were recorded by the 2D context (htmljs) in canvas pixels; drawn into the content box of B
function P.canvas(ops, b, oy, clip, bg)
  local kx = b.cw / (tonumber(b.n.attrs.width) or 300)
  local ky = b.ch / (tonumber(b.n.attrs.height) or 150)
  local ox, oyy = b.cx, b.cy - oy
  local function X(v) return floor(ox + v * kx + 0.5) end
  local function Y(v) return floor(oyy + v * ky + 0.5) end
  local cr = isect(clip, { b.cx, b.cy - oy, b.cw, b.ch })
  if cr[3] <= 0 then return end
  api.clip(cr[1], cr[2], cr[3], cr[4])
  for _, o in ipairs(ops) do
    local k = o.op
    local c = o.c
    if o.a and o.a < 0.99 and k ~= "rect" and k ~= "clear" then c = C.mix(c, bg, o.a) end
    if k == "rect" then
      local x0, y0 = X(o.x), Y(o.y)
      box4(x0, y0, X(o.x + o.w) - x0, Y(o.y + o.h) - y0, o.c, o.a)
    elseif k == "clear" then
      local x0, y0 = X(o.x), Y(o.y)
      box4(x0, y0, X(o.x + o.w) - x0, Y(o.y + o.h) - y0, bg)
    elseif k == "poly" then
      local p = o.pts
      if #p >= 6 then
        local x1, y1 = X(p[1]), Y(p[2])
        for i = 3, #p - 3, 2 do api.triangle(x1, y1, X(p[i]), Y(p[i + 1]), X(p[i + 2]), Y(p[i + 3]), c) end
      end
    elseif k == "lines" then
      local p = o.pts
      local lw = (o.lw or 1) * kx
      local n = #p
      local last = o.closed and n + 2 or n
      for i = 1, last - 3, 2 do
        local a1, b1 = p[(i - 1) % n + 1], p[i % n + 1]
        local a2, b2 = p[(i + 1) % n + 1], p[(i + 2) % n + 1]
        local x1, y1, x2, y2 = X(a1), Y(b1), X(a2), Y(b2)
        if lw <= 1.5 then api.line(x1, y1, x2, y2, c)
        else
          local dx, dy = x2 - x1, y2 - y1
          local len = math.sqrt(dx * dx + dy * dy)
          if len > 0 then
            local nx, ny = -dy / len * lw / 2, dx / len * lw / 2
            api.triangle(floor(x1 + nx), floor(y1 + ny), floor(x2 + nx), floor(y2 + ny), floor(x2 - nx), floor(y2 - ny), c)
            api.triangle(floor(x1 + nx), floor(y1 + ny), floor(x2 - nx), floor(y2 - ny), floor(x1 - nx), floor(y1 - ny), c)
            if lw > 3 then api.disc(x2, y2, floor(lw / 2), c) end
          end
        end
      end
    elseif k == "disc" then api.disc(X(o.x), Y(o.y), max(1, floor(o.r * kx + 0.5)), c)
    elseif k == "ring" then
      local r = max(1, floor(o.r * kx + 0.5))
      local lw = max(1, floor((o.lw or 1) * kx + 0.5))
      for d = 0, lw - 1 do api.circle(X(o.x), Y(o.y), max(1, r - floor(lw / 2) + d), c) end
    elseif k == "text" then
      local font = view.fontOf({ fs = o.px * ky, bold = o.bold, mono = o.mono, italic = false })
      local w = api.tw(o.s, font)
      local fh = api.fh(font)
      local x = X(o.x)
      if o.align == "center" then x = x - w / 2 elseif o.align == "right" or o.align == "end" then x = x - w end
      local y = Y(o.y)
      local bl = o.base or "alphabetic"
      if bl == "middle" then y = y - fh / 2 elseif bl == "alphabetic" or bl == "bottom" or bl == "ideographic" then y = y - fh * 0.8 end
      api.text(floor(x), floor(y), o.s, c, font)
    elseif k == "image" then
      api.image(o.src, X(o.x), Y(o.y), X(o.x + o.w) - X(o.x), Y(o.y + o.h) - Y(o.y), false)
    end
  end
  api.clip(clip and clip[1], clip and clip[2], clip and clip[3], clip and clip[4])
end

-- ---------------------------------------------------------------- the parts of a box
local function radiusOf(b)
  local r = b.cs["border-radius"]
  if not r or r == "0" then return 0 end
  if r:find("%%$") then return (tonumber(r:sub(1, -2)) or 0) / 100 * min(b.w, b.h) end
  return L.lenOf(r, b.cs, b.w) or 0
end
local function shadow(b, x, y, w, h, op)
  local s = b.cs["box-shadow"]
  if not s or s == "none" then return end
  local parts = C.splitTop(s, ",")[1]
  local nums, col = {}, nil
  for _, wd in ipairs(C.words(parts)) do
    if wd ~= "inset" then
      local px = L.lenOf(wd, b.cs, 0)
      if px and not C.color(wd) then nums[#nums + 1] = px else col = wd end
    end
  end
  local c, a = C.color(col or "rgba(0,0,0,.3)")
  if not c then return end
  local ox, oy2, blur, spread = nums[1] or 0, nums[2] or 0, nums[3] or 0, nums[4] or 0
  local grow = spread + blur / 2
  api.alpha(floor(x + ox - grow), floor(y + oy2 - grow), floor(w + 2 * grow), floor(h + 2 * grow), c, floor(min(1, a) * 255 * 0.6 * op))
end
local function urlOf(v)
  return v and v:match("url%(%s*[\"']?([^\"')]+)[\"']?%s*%)")
end
local function background(b, x, y, w, h, op)
  local cs = b.cs
  local r = radiusOf(b)
  local c, a = colorOf(cs["background-color"], cs.fg)
  if c and a > 0 then box4(x, y, w, h, c, a * op < 0.99 and a * op or nil, r) end
  local img = cs["background-image"]
  if img and img ~= "none" then
    local g = img:match("linear%-gradient%((.*)%)")
    if g then
      local parts = C.splitTop(g, ",")
      local horiz = parts[1]:find("right") or parts[1]:find("left") or parts[1]:find("90deg") or parts[1]:find("270deg")
      local cols = {}
      for _, p in ipairs(parts) do
        local cc = C.color((p:gsub("%s+[%d%.]+%%?%s*$", "")))
        if cc then cols[#cols + 1] = cc end
      end
      if #cols >= 2 then
        local c1, c2 = cols[1], cols[#cols]
        if parts[1]:find("left") and not parts[1]:find("right") then c1, c2 = c2, c1 end
        api.gradient(floor(x), floor(y), floor(w), floor(h), c1, c2, horiz and true or false)
      end
    else
      local u = urlOf(img)
      if u then api.image(view.url(u), floor(x), floor(y), floor(w), floor(h), cs["background-size"] == "cover") end
    end
  end
end
-- the radius when the four borders are the same (drawn as two round shapes), else nil
local function roundCase(b)
  local bd, cs = b.bd, b.cs
  if not bd or bd.t <= 0 or bd.t ~= bd.r or bd.t ~= bd.b or bd.t ~= bd.l then return nil end
  local r = radiusOf(b)
  if r <= 0.5 then return nil end
  local c = cs["border-top-color"]
  if c ~= cs["border-right-color"] or c ~= cs["border-bottom-color"] or c ~= cs["border-left-color"] then return nil end
  return r
end
local function borders(b, x, y, w, h, op)
  local bd = b.bd
  if not bd or bd.t + bd.r + bd.b + bd.l == 0 then return end
  local cs = b.cs
  local ct = colorOf(cs["border-top-color"], cs.fg) or cs.fg
  local cr = colorOf(cs["border-right-color"], cs.fg) or cs.fg
  local cb = colorOf(cs["border-bottom-color"], cs.fg) or cs.fg
  local cl = colorOf(cs["border-left-color"], cs.fg) or cs.fg
  local r = roundCase(b)
  if r then
    -- a round border: the outer shape, then the inside in the background colour
    local inner = colorOf(cs["background-color"], cs.fg)
    local _, ia = colorOf(cs["background-color"], cs.fg)
    if not inner or ia < 0.5 then inner = bgOf(b.parent) end
    local t = bd.t
    api.round(floor(x), floor(y), floor(w), floor(h), min(r, w / 2, h / 2), ct)
    api.round(floor(x + t), floor(y + t), floor(w - 2 * t), floor(h - 2 * t), max(0, min(r - t, (w - 2 * t) / 2, (h - 2 * t) / 2)), inner)
    return true
  end
  if bd.t > 0 then box4(x, y, w, bd.t, ct) end
  if bd.b > 0 then box4(x, y + h - bd.b, w, bd.b, cb) end
  if bd.l > 0 then box4(x, y, bd.l, h, cl) end
  if bd.r > 0 then box4(x + w - bd.r, y, bd.r, h, cr) end
end

-- the inside of form fields and other replaced elements
local function replaced(b, oy, op)
  local n, cs = b.n, b.cs
  local x, y, w, h = b.cx, b.cy - oy, b.cw, b.ch
  local t = n.tag
  local font = view.fontOf(cs)
  local fh = api.fh(font)
  local fg = cs.fg
  local ty = (n.attrs.type or "text"):lower()
  if t == "img" then
    local src = n.attrs.src
    local ok = src and src ~= "" and api.image(view.url(src), floor(x), floor(y), floor(w), floor(h), cs["object-fit"] == "cover")
    if not ok and w > 4 and h > 4 then
      api.rect(floor(x), floor(y), floor(w), floor(h), 0xc0c0c0)
      local alt = n.attrs.alt
      if alt and alt ~= "" then api.clip(floor(x), floor(y), floor(w), floor(h)); api.text(floor(x + 3), floor(y + 2), alt, 0x707070, font); restoreClip() end
    end
  elseif t == "input" and (ty == "checkbox" or ty == "radio") then
    local s = floor(min(w, h))
    local cx, cy = floor(x + w / 2), floor(y + h / 2)
    local on = n.checked
    local accent = colorOf(cs["accent-color"], 0x1a73e8) or 0x1a73e8
    if ty == "radio" then
      api.disc(cx, cy, floor(s / 2), on and accent or 0xffffff)
      api.circle(cx, cy, floor(s / 2), on and accent or 0x767676)
      if on then api.disc(cx, cy, max(1, floor(s / 5)), 0xffffff) end
    else
      api.round(floor(x), floor(y), s, s, 2, on and accent or 0x767676)
      if not on then api.fill(floor(x) + 1, floor(y) + 1, s - 2, s - 2, 0xffffff)
      else
        api.line(floor(x + s * 0.2), floor(y + s * 0.5), floor(x + s * 0.42), floor(y + s * 0.75), 0xffffff)
        api.line(floor(x + s * 0.42), floor(y + s * 0.75), floor(x + s * 0.8), floor(y + s * 0.25), 0xffffff)
        api.line(floor(x + s * 0.2), floor(y + s * 0.5) + 1, floor(x + s * 0.42), floor(y + s * 0.75) + 1, 0xffffff)
        api.line(floor(x + s * 0.42), floor(y + s * 0.75) + 1, floor(x + s * 0.8), floor(y + s * 0.25) + 1, 0xffffff)
      end
    end
  elseif t == "input" and ty == "range" then
    local lo, hi = tonumber(n.attrs.min) or 0, tonumber(n.attrs.max) or 100
    local v = tonumber(n.value or n.attrs.value) or (lo + hi) / 2
    local f = hi > lo and (v - lo) / (hi - lo) or 0
    local accent = colorOf(cs["accent-color"], 0x1a73e8) or 0x1a73e8
    local my = floor(y + h / 2)
    api.round(floor(x), my - 2, floor(w), 4, 2, 0xc8c8c8)
    api.round(floor(x), my - 2, max(4, floor(w * f)), 4, 2, accent)
    api.disc(floor(x + 7 + (w - 14) * f), my, 7, accent)
  elseif t == "progress" or t == "meter" then
    local hi = tonumber(n.attrs.max) or 1
    local v = tonumber(n.attrs.value) or 0
    api.round(floor(x), floor(y), floor(w), floor(h), 4, 0xe0e0e0)
    if hi > 0 then api.round(floor(x), floor(y), max(2, floor(w * min(1, v / hi))), floor(h), 4, t == "meter" and 0x3cb043 or 0x1a73e8) end
  elseif t == "canvas" then
    if n.canvasOps then P.canvas(n.canvasOps, b, oy, view.cr, bgOf(b)) end
  elseif t == "video" or t == "audio" or t == "iframe" or t == "object" or t == "embed" or t == "svg" then
    api.fill(floor(x), floor(y), floor(w), floor(h), t == "svg" and 0xf0f0f0 or 0x202020)
    local label = t == "video" and "▶ video (not played here)" or t == "audio" and "♪ audio (not played here)" or t == "iframe" and ("iframe: " .. (n.attrs.src or "")) or t
    api.clip(floor(x), floor(y), floor(w), floor(h))
    api.text(floor(x + 6), floor(y + h / 2 - fh / 2), label, t == "svg" and 0x808080 or 0xdddddd, font)
    restoreClip()
  else
    -- text fields, buttons made of input, select, textarea
    local text, color = "", fg
    if t == "select" then
      local sel = n.selectedIndex or 0
      local i = 0
      for _, o in ipairs(n.kids) do
        if o.type == "el" and o.tag == "option" then
          if i == sel then text = L.optionText(o) end
          i = i + 1
        end
      end
    elseif ty == "submit" or ty == "button" or ty == "reset" then
      text = n.value or n.attrs.value or (ty == "submit" and "Submit" or ty == "reset" and "Reset" or "")
    else
      text = n.value or n.attrs.value or ""
      if t == "textarea" and n.value == nil then text = n.kids[1] and n.kids[1].text or "" end
      if ty == "password" then text = string.rep("•", utf8.len(text) or #text) end
      if text == "" and n.attrs.placeholder then text = n.attrs.placeholder; color = 0x8a8a8a end
    end
    api.clip(floor(x), floor(y), max(1, floor(w)), max(1, floor(h)))
    local caretX
    if t == "textarea" then
      local yy = y
      local lines = {}
      for ln in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = ln end
      for _, ln in ipairs(lines) do
        api.text(floor(x), floor(yy), ln, color, font)
        yy = yy + cs.lh
      end
      caretX = x + api.tw(lines[#lines] or "", font)
      if view.caret and view.focus == n then api.fill(floor(caretX), floor(yy - cs.lh), 1, floor(fh), fg) end
    else
      local tw = api.tw(text, font)
      local tx = x
      if ty == "submit" or ty == "button" or ty == "reset" then tx = x + (w - tw) / 2 end
      -- a long value shows its end (where the caret is)
      if tw > w and color == fg and t ~= "select" then tx = x + w - tw - 2 end
      api.text(floor(tx), floor(y + (h - fh) / 2), text, color, font)
      if view.caret and view.focus == n and t == "input" then
        local cx = (color == fg) and (tx + tw) or x
        api.fill(floor(cx) + 1, floor(y + (h - fh) / 2), 1, floor(fh), fg)
      end
    end
    if t == "select" then
      local ax, ay = floor(x + w - fh * 0.6), floor(y + h / 2)
      api.triangle(ax - 4, ay - 2, ax + 4, ay - 2, ax, ay + 3, fg)
    end
    restoreClip()
  end
end

-- ---------------------------------------------------------------- boxes
local paintBox
local function texts(b, oy, op, clip)
  local bgc
  for _, d in ipairs(b.decos) do
    local y = d.y - oy
    if visible(d.x, y, d.w, d.h, clip) then
      local c, a = colorOf(d.cs["background-color"], d.cs.fg)
      local r = L.lenOf(d.cs["border-radius"], d.cs, d.h) or 0
      if d.bd and d.bd.t > 0 then
        local bc = colorOf(d.cs["border-top-color"], d.cs.fg) or d.cs.fg
        box4(d.x, y, d.w, d.h, bc, nil, r)
        if c and a > 0 then box4(d.x + d.bd.l, y + d.bd.t, d.w - d.bd.l - d.bd.r, d.h - d.bd.t - d.bd.b, c, a < 0.99 and a or nil, r) end
      elseif c and a > 0 then box4(d.x, y, d.w, d.h, c, (a * op) < 0.99 and a * op or nil, r) end
    end
  end
  for _, t in ipairs(b.texts) do
    local y = t.y - oy
    if visible(t.x, y, t.w + 2, t.h, clip) and t.cs.visibility ~= "hidden" then
      local fh = api.fh(t.font)
      local c = t.cs.fg
      local a = (t.cs.fa or 1) * op
      if a < 0.99 then bgc = bgc or bgOf(b); c = C.mix(c, bgc, a) end
      local ty = floor(y + (t.h - fh) / 2 + 0.5)
      api.text(floor(t.x + 0.5), ty, t.s, c, t.font)
      local dec = t.cs["text-decoration"]
      if dec == "underline" then api.fill(floor(t.x), ty + floor(fh * 0.9), floor(t.w + 0.5), 1, c)
      elseif dec == "line-through" then api.fill(floor(t.x), ty + floor(fh * 0.55), floor(t.w + 0.5), 1, c)
      elseif dec == "overline" then api.fill(floor(t.x), ty, floor(t.w + 0.5), 1, c) end
    end
  end
end
paintBox = function(b, oy, op, clip)
  if b.fixed then oy = 0 end
  local cs = b.cs
  local opacity = tonumber(cs.opacity or "") or 1
  op = op * opacity
  if op <= 0.01 then return end
  local x, y, w, h = b.x, b.y - oy, b.w, b.h
  local shown = cs.visibility ~= "hidden" and not b.anon
  if shown and visible(x - 20, y - 20, w + 40, h + 40, clip) then
    shadow(b, x, y, w, h, op)
    local bd = b.bd
    local uniformRound = roundCase(b)
    if not uniformRound then background(b, x, y, w, h, op) end
    borders(b, x, y, w, h, op)
    if uniformRound then
      -- the background is inside the round border already; a picture still goes on top
      local img = cs["background-image"]
      if img and img ~= "none" then
        background({ cs = setmetatable({ ["background-color"] = "transparent" }, { __index = cs }), w = w, h = h, bd = bd }, x + bd.l, y + bd.t, w - bd.l - bd.r, h - bd.t - bd.b, op)
      end
    end
    if b.n and L.isReplaced(b.n) then replaced(b, oy, op) end
    if b.marker then
      local font = view.fontOf(cs)
      local mw = api.tw(b.marker, font)
      local fh = api.fh(font)
      local my = (b.markerBase and (b.markerBase - cs.fs * 0.8 - (fh - cs.fs) / 2) or b.markerY or b.cy) - oy
      api.text(floor(b.cx - mw - 6), floor(my), b.marker, cs.fg, font)
    end
    if view.focus and b.n == view.focus and b.n.tag ~= "body" then
      api.rect(floor(x) - 2, floor(y) - 2, floor(w) + 4, floor(h) + 4, 0x1a73e8)
    end
  end
  local inner = clip
  if b.clip then
    inner = isect(clip, { x + b.bd.l, y + b.bd.t, w - b.bd.l - b.bd.r, h - b.bd.t - b.bd.b })
    if inner[3] <= 0 or inner[4] <= 0 then return end
    api.clip(inner[1], inner[2], inner[3], inner[4])
  end
  local saved = view.cr
  view.cr = inner
  local koy = oy + (b.clip and (b.sy or 0) or 0)
  texts(b, koy, op, inner)
  for _, k in ipairs(L.paintOrder(b)) do paintBox(k, koy, op, inner) end
  -- a scroll bar for a box that scrolls
  if b.scrollable then
    local track = b.h - b.bd.t - b.bd.b
    local bar = max(12, track * b.ch / b.scrollH)
    local pos = (track - bar) * (b.sy or 0) / max(1, b.scrollH - b.ch)
    api.alpha(floor(x + w - b.bd.r - 4), floor(y + b.bd.t + pos), 3, floor(bar), 0x000000, 90)
  end
  view.cr = saved
  if b.clip then
    if clip then api.clip(clip[1], clip[2], clip[3], clip[4]) else api.clip() end
  end
end

-- draws the page; VIEW.rect limits the work to a part of the screen (a canvas that changed)
function P.paint(root, v)
  view = v
  api = v.api
  local clip = v.rect and { v.rect[1], v.rect[2], v.rect[3], v.rect[4] } or { 0, 0, v.vw, v.vh }
  -- the page background: the root, or the body when the root has none
  local body
  for _, k in ipairs(root.kids) do if k.n and k.n.tag == "body" then body = k end end
  local bg, a = colorOf(root.cs["background-color"], 0)
  if not bg or a < 0.5 then
    local bb = body and body.cs["background-color"]
    bg, a = colorOf(bb, 0)
    if not bg or a < 0.5 then bg = 0xffffff end
  end
  v.pageBg = bg
  api.clip(clip[1], clip[2], clip[3], clip[4])
  api.fill(clip[1], clip[2], clip[3], clip[4], bg)
  -- a background image of the body covers the whole screen
  local bimg = body and body.cs["background-image"]
  if bimg and bimg ~= "none" then
    background({ cs = setmetatable({ ["background-color"] = "transparent" }, { __index = body.cs }), w = v.vw, h = v.vh }, 0, 0, v.vw, v.vh, 1)
  end
  v.cr = clip
  paintBox(root, v.sy or 0, 1, clip)
  api.clip()
end
return P
