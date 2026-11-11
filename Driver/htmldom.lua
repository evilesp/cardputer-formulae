#!lua
-- htmldom: the HTML parser and the document tree of the html player (pure Lua, no device API).
-- A node is a table: { type = "el"|"text"|"comment"|"doc", tag = "div", attrs = { id = "x" }, kids = { ... }, parent = node, text = "..." }.
--   local D = driver.load("htmldom")
--   local doc = D.parse(src)              -- a document with <html>, <head> and <body> always there
--   D.serialize(node, true)               -- innerHTML ; D.textOf(node) -- textContent
local D = {}

local VOID = {}
for w in ("area base br col embed hr img input link meta param source track wbr"):gmatch("%S+") do VOID[w] = true end
D.VOID = VOID
local RAW = { script = true, style = true, textarea = true, title = true, xmp = true }
local HEADTAG = { meta = true, link = true, style = true, title = true, base = true, script = true }
-- a start tag of one of these closes an open <p>
local CLOSEP = {}
for w in ("address article aside blockquote details div dl fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hr main menu nav ol p pre section table ul"):gmatch("%S+") do CLOSEP[w] = true end
-- the tags that close themselves when a sibling of the listed kind starts
local AUTOCLOSE = {
  li = { li = true }, dt = { dt = true, dd = true }, dd = { dt = true, dd = true },
  tr = { tr = true, tbody = true, thead = true, tfoot = true }, td = { td = true, th = true, tr = true, tbody = true, tfoot = true },
  th = { td = true, th = true, tr = true, tbody = true, tfoot = true }, option = { option = true, optgroup = true }, optgroup = { optgroup = true },
  thead = { tbody = true, tfoot = true }, tbody = { tbody = true, tfoot = true, thead = true }, tfoot = { tbody = true },
  p = {},
}
local SCOPE = { table = true, ul = true, ol = true, dl = true, select = true, body = true, html = true }

local ENT = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = "\194\160", copy = "©", reg = "®", trade = "™", hellip = "…", mdash = "—",
  ndash = "–", laquo = "«", raquo = "»", times = "×", divide = "÷", deg = "°", middot = "·", bull = "•", euro = "€", pound = "£", yen = "¥", cent = "¢",
  larr = "←", rarr = "→", uarr = "↑", darr = "↓", harr = "↔", hearts = "♥", check = "✓", lsquo = "‘", rsquo = "’", ldquo = "“", rdquo = "”",
  sect = "§", para = "¶", plusmn = "±", frac12 = "½", micro = "µ", infin = "∞", ne = "≠", le = "≤", ge = "≥", ensp = " ", emsp = " ", thinsp = " ",
  shy = "", zwj = "", zwnj = "", star = "☆", starf = "★" }
local function utf8c(n)
  if n < 0 or n > 0x10FFFF then return "\239\191\189" end
  return utf8.char(n)
end
function D.decode(s)
  if not s:find("&", 1, true) then return s end
  return (s:gsub("&(#?[%w]+);?", function(e)
    if e:sub(1, 1) == "#" then
      local n = e:sub(2, 2):lower() == "x" and tonumber(e:sub(3), 16) or tonumber(e:sub(2))
      if n then return utf8c(n) end
      return nil
    end
    return ENT[e]
  end))
end
local function esc(s, attr)
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\194\160", "&nbsp;")
  if attr then s = s:gsub('"', "&quot;") end
  return s
end

-- ---------------------------------------------------------------- nodes
function D.el(tag, attrs)
  return { type = "el", tag = tag, attrs = attrs or {}, order = {}, kids = {} }
end
function D.txt(s) return { type = "text", text = s } end
function D.setAttr(n, k, v)
  if n.attrs[k] == nil then n.order[#n.order + 1] = k end
  n.attrs[k] = v
end
function D.removeAttr(n, k)
  if n.attrs[k] == nil then return end
  n.attrs[k] = nil
  for i, x in ipairs(n.order) do if x == k then table.remove(n.order, i); break end end
end
local function indexIn(p, n)
  for i, k in ipairs(p.kids) do if k == n then return i end end
end
D.indexIn = indexIn
function D.remove(n)
  local p = n.parent
  if not p then return n end
  local i = indexIn(p, n)
  if i then table.remove(p.kids, i) end
  n.parent = nil
  return n
end
-- puts N into P before REF (at the end without REF); a fragment brings its children
function D.insert(p, n, ref)
  if n.type == "frag" then
    local list = {}
    for _, k in ipairs(n.kids) do list[#list + 1] = k end
    for _, k in ipairs(list) do D.insert(p, k, ref) end
    return n
  end
  D.remove(n)
  local i = ref and indexIn(p, ref) or (#p.kids + 1)
  table.insert(p.kids, i, n)
  n.parent = p
  return n
end
function D.clone(n, deep)
  local c = { type = n.type, tag = n.tag, text = n.text }
  if n.attrs then
    c.attrs, c.order, c.kids = {}, {}, {}
    for _, k in ipairs(n.order) do D.setAttr(c, k, n.attrs[k]) end
    if deep then for _, k in ipairs(n.kids) do D.insert(c, D.clone(k, true)) end end
  end
  if n.kids and not c.kids then c.kids = {} end
  return c
end
function D.textOf(n)
  if n.type == "text" then return n.text end
  if n.type == "comment" then return "" end
  local out = {}
  local function walk(x)
    for _, k in ipairs(x.kids) do
      if k.type == "text" then out[#out + 1] = k.text elseif k.kids then walk(k) end
    end
  end
  walk(n)
  return table.concat(out)
end
function D.setText(n, s)
  for _, k in ipairs(n.kids) do k.parent = nil end
  n.kids = {}
  if s ~= "" then D.insert(n, D.txt(s)) end
end
-- each element under N (N itself not), in document order; F returns true to stop
function D.walk(n, f)
  local kids = n.kids
  if not kids then return end
  for i = 1, #kids do
    local k = kids[i]
    if k and k.type == "el" then
      if f(k) then return true end
      if D.walk(k, f) then return true end
    end
  end
end
function D.byId(root, id)
  local found
  D.walk(root, function(e) if e.attrs.id == id then found = e; return true end end)
  return found
end
function D.byTag(root, tag)
  local out = {}
  tag = tag:lower()
  D.walk(root, function(e) if tag == "*" or e.tag == tag then out[#out + 1] = e end end)
  return out
end
function D.contains(a, b)
  while b do if a == b then return true end b = b.parent end
  return false
end

-- ---------------------------------------------------------------- serializing (innerHTML, outerHTML)
function D.serialize(n, inner, out)
  local top = not out
  out = out or {}
  local function one(k)
    if k.type == "text" then
      local p = k.parent
      out[#out + 1] = (p and RAW[p.tag] and p.tag ~= "textarea" and p.tag ~= "title") and k.text or esc(k.text)
    elseif k.type == "comment" then out[#out + 1] = "<!--" .. k.text .. "-->"
    elseif k.type == "el" then
      out[#out + 1] = "<" .. k.tag
      for _, a in ipairs(k.order) do out[#out + 1] = " " .. a .. '="' .. esc(k.attrs[a], true) .. '"' end
      out[#out + 1] = ">"
      if not VOID[k.tag] then
        D.serialize(k, true, out)
        out[#out + 1] = "</" .. k.tag .. ">"
      end
    elseif k.kids then D.serialize(k, true, out) end
  end
  if inner then for _, k in ipairs(n.kids or {}) do one(k) end else one(n) end
  if top then return table.concat(out) end
end

-- ---------------------------------------------------------------- the parser
local function parseAttrs(s)
  local attrs, order = {}, {}
  local i, n = 1, #s
  while i <= n do
    local a, b = s:find("^[%s/]+", i)
    if a then i = b + 1 end
    if i > n then break end
    local name = s:match("^[^%s=/>]+", i)
    if not name then i = i + 1 else
      i = i + #name
      name = name:lower()
      local val = ""
      local eq = s:find("^%s*=%s*", i)
      if eq then
        local _, e2 = s:find("^%s*=%s*", i)
        i = e2 + 1
        local q = s:sub(i, i)
        if q == '"' or q == "'" then
          local close = s:find(q, i + 1, true) or (n + 1)
          val = s:sub(i + 1, close - 1)
          i = close + 1
        else
          val = s:match("^[^%s>]*", i)
          i = i + #val
        end
        val = D.decode(val)
      end
      if attrs[name] == nil then order[#order + 1] = name; attrs[name] = val end
    end
  end
  return attrs, order
end

-- parses SRC into the children of ROOT (a document when FRAGMENT is not set: html, head and body are made as needed)
local function build(src, root, fragment)
  local html, head, body
  local stack = { root }
  local function cur() return stack[#stack] end
  if not fragment then
    html = D.el("html"); D.insert(root, html)
    head = D.el("head"); D.insert(html, head)
    body = D.el("body")
    stack = { root, html, head }
  end
  local inBody = fragment
  local function toBody()
    if inBody then return end
    inBody = true
    if not body.parent then D.insert(html, body) end
    stack = { root, html, body }
  end
  local function addText(s)
    if s == "" then return end
    local c = cur()
    if not inBody and not fragment then
      if not s:find("%S") then return end
      toBody()
      c = cur()
    end
    if c.tag == "table" or c.tag == "tbody" or c.tag == "tr" or c.tag == "thead" then
      if not s:find("%S") then return end
    end
    local last = c.kids[#c.kids]
    if last and last.type == "text" then last.text = last.text .. s
    else D.insert(c, D.txt(s)) end
  end
  local function popTo(tag)
    for i = #stack, 2, -1 do
      if stack[i].tag == tag then
        for j = #stack, i, -1 do stack[j] = nil end
        return true
      end
      if SCOPE[stack[i].tag] and stack[i].tag ~= tag then return false end
    end
    return false
  end
  local i, n = 1, #src
  while i <= n do
    local lt = src:find("<", i, true)
    if not lt then addText(D.decode(src:sub(i))); break end
    if lt > i then addText(D.decode(src:sub(i, lt - 1))) end
    i = lt
    if src:sub(i, i + 3) == "<!--" then
      local e = src:find("-->", i + 4, true)
      local text = src:sub(i + 4, (e or n + 1) - 1)
      local c = { type = "comment", text = text }
      D.insert(cur(), c)
      i = e and e + 3 or n + 1
    elseif src:sub(i, i + 1) == "<!" or src:sub(i, i + 1) == "<?" then
      local e = src:find(">", i, true)
      i = e and e + 1 or n + 1
    elseif src:sub(i, i + 1) == "</" then
      local tag, e = src:match("^</%s*([%w%-:]+)[^>]*>()", i)
      if not tag then
        addText("<"); i = i + 1
      else
        i = e
        tag = tag:lower()
        if tag == "body" or tag == "html" then -- the end of the body: later content still goes into it
        elseif tag == "head" then if not fragment then toBody() end
        elseif tag == "p" and not popTo("p") then
          D.insert(cur(), D.el("p"))  -- </p> without <p> makes an empty paragraph
        elseif tag == "br" then D.insert(cur(), D.el("br"))
        else popTo(tag) end
      end
    else
      local tag, rest, e = src:match("^<([%a][%w%-:]*)(.-)>()", i)
      if not tag then
        addText("<"); i = i + 1
      else
        -- a > inside a quoted attribute value: read up to the real end of the tag
        if rest:find('["\']') then
          local j, q = i + 1 + #tag, nil
          while j <= n do
            local c = src:sub(j, j)
            if q then if c == q then q = nil end
            elseif c == '"' or c == "'" then q = c
            elseif c == ">" then break end
            j = j + 1
          end
          rest = src:sub(i + 1 + #tag, j - 1)
          e = j + 1
        end
        i = e
        tag = tag:lower()
        local attrs, order = parseAttrs(rest)
        if not fragment and (tag == "html" or tag == "body" or tag == "head") then
          local target = tag == "html" and html or tag == "head" and head or body
          for _, k in ipairs(order) do if target.attrs[k] == nil then D.setAttr(target, k, attrs[k]) end end
          if tag == "body" then toBody() end
        else
          if not inBody and not fragment and not HEADTAG[tag] then toBody() end
          -- implied end tags
          local c = cur()
          if CLOSEP[tag] or tag == "li" or tag == "dt" or tag == "dd" then
            for k = #stack, 2, -1 do
              local t = stack[k].tag
              if t == "p" then popTo("p"); break end
              if SCOPE[t] or not (t == "span" or t == "b" or t == "i" or t == "a" or t == "em" or t == "strong") then break end
            end
            c = cur()
          end
          while c and AUTOCLOSE[c.tag] and AUTOCLOSE[c.tag][tag] do
            stack[#stack] = nil
            c = cur()
          end
          if (tag == "tr") and (c.tag == "table") then
            local tb = D.el("tbody"); D.insert(c, tb); stack[#stack + 1] = tb; c = tb
          end
          local el = { type = "el", tag = tag, attrs = attrs, order = order, kids = {} }
          D.insert(c, el)
          local selfClose = rest:find("/%s*$") ~= nil
          if RAW[tag] and not selfClose then
            local a2, b2 = src:find("</%s*" .. tag .. "%s*>", i)
            if not a2 then a2 = src:lower():find("</" .. tag, i, true) ; b2 = a2 and (src:find(">", a2, true) or n) end
            local body_ = src:sub(i, (a2 or n + 1) - 1)
            if tag == "textarea" or tag == "title" then body_ = D.decode(body_:gsub("^\r?\n", "")) end
            if body_ ~= "" then D.insert(el, D.txt(body_)) end
            i = b2 and b2 + 1 or n + 1
          elseif not VOID[tag] and not selfClose then
            stack[#stack + 1] = el
          end
        end
      end
    end
  end
  if not fragment and not body.parent then D.insert(html, body) end
  return html, head, body
end

function D.parse(src)
  local doc = { type = "doc", kids = {} }
  local html, head, body = build(src or "", doc, false)
  doc.html, doc.head, doc.body = html, head, body
  return doc
end
-- parses SRC as the children of a new fragment (for innerHTML, insertAdjacentHTML, document.write)
function D.fragment(src)
  local f = { type = "frag", kids = {} }
  build(src or "", f, true)
  return f
end
return D
