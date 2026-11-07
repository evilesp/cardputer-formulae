#!lua
-- duckduckgo: a browser for DuckDuckGo with a clean interface (light, or dark with the key t).
--   duckduckgo WORDS                search the web
--   duckduckgo img [COUNT] WORDS    pictures; COUNT is how many (img 23 cats). Without it the pictures come 24 at a time, more as you reach the end
-- In the search box, "img 23 cats" does the same. Keys:
--   search box: type, Enter searches, up/down older searches, Ctrl+T theme, Ctrl+Q quits
--   results:    up/down choose, Enter opens the page, i pictures of the same words, / new search, b back, q quit
--   page:       up/down and PageUp/PageDown scroll, space page down, g/G top and end, l then a number and Enter follows a link, b back
--   pictures:   arrows choose, Enter shows one on the whole screen, / new search, b back
--   a picture:  left/right turn them, b back; the title shows for a moment
-- Pages and pictures are kept on the SD card. Pictures are fetched in the background on the other processor core, so the keys and the
-- screen go on while they arrive. Needs the smooth fonts (the fonts driver fetches them once) and firmware v0.1 or newer.

---------------------------------------------------------------- pure helpers (checked by --selftest)

local function domainOf(url)
  return url:match("^https?://([^/]+)") or url
end

local function pathOf(url)
  return url:match("^https?://[^/]+(.*)$") or ""
end

-- Bing makes the picture of the size asked for on its side, and crops it (c=7: the middle) when the shape differs. It never makes a
-- picture bigger than the one it has: a larger size only adds white edges, so the whole-screen view asks for no size (native).
local function stripSize(url)
  local base = url:gsub("&[whc]=[^&]*", "")
  return base
end

local function sized(url, w, h)
  local base = stripSize(url)
  return base .. (base:find("%?") and "&" or "?") .. string.format("w=%d&h=%d&c=7", w, h)
end

-- "img 23 cats" -> 23, "cats";  "img cats" -> nil, "cats";  "img<23> cats" (the older form) -> 23, "cats";  not a picture search -> nil, nil
local function parseImages(text)
  local n, words = text:match("^img<(%d+)>%s*(.*)$")
  if n then return tonumber(n), words end
  local rest = text:match("^img%s+(.+)$")
  if not rest then return nil, nil end
  local num, tail = rest:match("^(%d+)%s+(.+)$")
  if num then return tonumber(num), tail end
  return nil, rest
end

local function mix(a, b, t)
  local function ch(s)
    local x, y = (a >> s) & 255, (b >> s) & 255
    return math.floor(x + (y - x) * t + 0.5)
  end
  return (ch(16) << 16) | (ch(8) << 8) | ch(0)
end

-- the end of a text without a half character (UTF-8) left over
local function cleanCut(s)
  while #s > 0 do
    local b = s:byte(#s)
    if b >= 0xC0 then return s:sub(1, #s - 1) end            -- a lead byte whose continuation is missing
    if b >= 0x80 then
      local i = #s
      while i > 1 and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do i = i - 1 end
      local lead = s:byte(i)
      local need = lead >= 0xF0 and 4 or lead >= 0xE0 and 3 or lead >= 0xC0 and 2 or 1
      if #s - i + 1 < need then return s:sub(1, i - 1) end
    end
    return s
  end
  return s
end

-- the words of a text in lines no wider than maxw (measure gives the width of a text); maxLines cuts it with "..."
local function wrapText(text, measure, maxw, maxLines)
  local lines, line = {}, ""
  local cut = false
  for word in text:gmatch("%S+") do
    local try = line == "" and word or (line .. " " .. word)
    if measure(try) <= maxw or line == "" then
      line = try
    else
      lines[#lines + 1] = line
      line = word
      if #lines == maxLines then cut = true; break end
    end
  end
  if not cut and line ~= "" then lines[#lines + 1] = line end
  if cut and #lines > 0 then
    local last = lines[#lines]
    while #last > 1 and measure(last .. "...") > maxw do last = cleanCut(last:sub(1, #last - 1)) end
    lines[#lines] = last .. "..."
  end
  return lines
end

local function selftest()
  local checks = 0
  local function expect(got, want)
    checks = checks + 1
    if got ~= want then error(string.format("check %d: got %q, want %q", checks, tostring(got), tostring(want))) end
  end
  expect(domainOf("https://a.org/x/y.html"), "a.org")
  expect(domainOf("a.org"), "a.org")
  expect(pathOf("https://a.org/x/y.html"), "/x/y.html")
  expect(pathOf("https://a.org"), "")
  expect(sized("https://th.bing.com/th?id=1&w=217&h=180&c=7", 112, 84), "https://th.bing.com/th?id=1&w=112&h=84&c=7")
  expect(sized("https://th.bing.com/th?id=1", 140, 105), "https://th.bing.com/th?id=1&w=140&h=105&c=7")
  expect(stripSize("https://th.bing.com/th?id=1&w=140&h=105&c=7"), "https://th.bing.com/th?id=1")
  local n, w = parseImages("img 23 cats")
  expect(n, 23); expect(w, "cats")
  n, w = parseImages("img cats and dogs")
  expect(n, nil); expect(w, "cats and dogs")
  n, w = parseImages("img<2> cute cats")
  expect(n, 2); expect(w, "cute cats")
  n, w = parseImages("img 2024")
  expect(n, nil); expect(w, "2024")
  n, w = parseImages("cats img")
  expect(n, nil); expect(w, nil)
  expect(mix(0x000000, 0xFFFFFF, 0.5), 0x808080)
  expect(mix(0x102030, 0x102030, 0.7), 0x102030)
  expect(cleanCut("ab\xC4"), "ab")
  expect(cleanCut("ab\xC4\x85"), "ab\xC4\x85")
  expect(cleanCut("abc"), "abc")
  local measure = function(s) return #s * 10 end
  local lines = wrapText("one two three four five six", measure, 100, 5)
  expect(#lines, 3); expect(lines[1], "one two"); expect(lines[3], "five six")
  lines = wrapText("one two three four five six seven eight", measure, 100, 2)
  expect(#lines, 2); expect(lines[2], "three f...")
  print(string.format("selftest ok (%d checks)", checks))
end

if arg[1] == "--selftest" then
  selftest()
  return
end

---------------------------------------------------------------- the screen, the fonts, the colors

local W, H = gfx.open("native")
if not W then
  print("duckduckgo needs the graphics screen: " .. tostring(H))
  return
end

local fonts = driver.load("fonts")
local FONTDIR = "/usr/share/fonts/vlw/"
local fontOk = true
local currentFont = nil

local themes = {
  light = { name = "light", bg = 0xF5F5F7, card = 0xFFFFFF, pill = 0xE6E6EB, text = 0x1D1D1F, dim = 0x6E6E73, faint = 0x9A9AA1,
            link = 0x0A5FD0, url = 0x2E7D32, accent = 0xDE5833, line = 0xDADADF, ring = 0x0A84FF, spin = 0x9A9AA1 },
  dark = { name = "dark", bg = 0x121214, card = 0x1F1F23, pill = 0x2B2B30, text = 0xF2F2F4, dim = 0x9C9CA3, faint = 0x6D6D74,
           link = 0x73B4FF, url = 0x71D08C, accent = 0xFF7A4D, line = 0x2F2F35, ring = 0x73B4FF, spin = 0x6D6D74 },
}
local theme = themes.light

-- a font is named by style and size: "r18" regular, "b18" bold, "l44" light. Without the font files the bitmap font is used.
local function fallbackSize(spec)
  if fontOk then return 1 end
  local px = tonumber(spec:match("%d+")) or 16
  return math.max(1, math.min(6, math.floor(px / 9 + 0.5)))
end

local function setFont(spec)
  if spec == currentFont then return end
  currentFont = spec
  if not fontOk then gfx.font(""); return end
  local style, size = spec:match("^(%a)(%d+)$")
  local name = (style == "b" and "lato-bold-" or style == "l" and "lato-light-" or "lato-") .. size
  if not gfx.font(FONTDIR .. name .. ".vlw") then
    fontOk = false
    gfx.font("")
  end
end

local function T(x, y, str, color, spec)
  setFont(spec)
  gfx.text(x, y, str, color, fallbackSize(spec))
end

local function TW(str, spec)
  setFont(spec)
  return gfx.textWidth(str, fallbackSize(spec))
end

local function TC(cx, y, str, color, spec)
  T(cx - TW(str, spec) // 2, y, str, color, spec)
end

local function TR(rx, y, str, color, spec)
  T(rx - TW(str, spec), y, str, color, spec)
end

local function fit(str, spec, maxw)
  if TW(str, spec) <= maxw then return str end
  local lo, hi = 1, #str
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if TW(str:sub(1, mid) .. "...", spec) <= maxw then lo = mid else hi = mid - 1 end
  end
  return cleanCut(str:sub(1, lo)) .. "..."
end

local function wrap(text, spec, maxw, maxLines)
  return wrapText(text, function(s) return TW(s, spec) end, maxw, maxLines)
end

---------------------------------------------------------------- small drawings

local function shadow(x, y, w, h, r, bg, strength)
  for i = 7, 1, -1 do
    local a = (8 - i) * 0.010 * (strength or 1)
    gfx.round(x - i, y - i + 3, w + 2 * i, h + 2 * i, r + i, mix(bg, 0x000000, a))
  end
end

local function ring(cx, cy, r, th, color, bg)
  gfx.round(cx - r, cy - r, 2 * r, 2 * r, r, color)
  gfx.round(cx - r + th, cy - r + th, 2 * (r - th), 2 * (r - th), r - th, bg)
end

local function stroke(x1, y1, x2, y2, th, color)
  local n = math.max(math.abs(x2 - x1), math.abs(y2 - y1), 1)
  for i = 0, n do
    local x, y = x1 + (x2 - x1) * i / n, y1 + (y2 - y1) * i / n
    gfx.round(x - th / 2, y - th / 2, th, th, th / 2, color)
  end
end

local function magnifier(x, y, s, color, bg)
  ring(x + s * 0.42, y + s * 0.42, s * 0.42, math.max(2, s * 0.11), color, bg)
  stroke(x + s * 0.72, y + s * 0.72, x + s * 0.98, y + s * 0.98, math.max(2, s * 0.12), color)
end

local function chevron(x, y, s, color)
  stroke(x + s * 0.65, y, x, y + s * 0.5, 3, color)
  stroke(x, y + s * 0.5, x + s * 0.65, y + s, 3, color)
end

local function spinner(cx, cy, r, color, bg)
  local step = (sys.millis() // 70) % 12
  for i = 0, 11 do
    local a = i / 12 * 2 * math.pi
    local age = (step - i) % 12
    gfx.round(cx + math.cos(a) * r - 3, cy + math.sin(a) * r - 3, 6, 6, 3, mix(bg, color, 1 - age / 12))
  end
end

---------------------------------------------------------------- state

local HISTORY_FILE = "/home/user/.duckduckgo"
local history = {}
local view = { kind = "home", input = "" }
local stack = {}
local toastText, toastUntil = nil, 0
local lastKeyAt = 0
local TEXT_COLS = 70      -- the width pages are wrapped to (about 600 pixels in the reading font)
local READ_TOP, READ_ROWS, READ_LINE = 70, 14, 26

local function loadSettings()
  local data = fs.read(HISTORY_FILE)
  if not data then return end
  for line in data:gmatch("[^\n]+") do
    local th = line:match("^theme=(%a+)$")
    if th and themes[th] then theme = themes[th]
    elseif #history < 14 then history[#history + 1] = line end
  end
end

local function saveSettings()
  fs.write(HISTORY_FILE, "theme=" .. theme.name .. "\n" .. table.concat(history, "\n") .. "\n")
end

local function remember(q)
  for i = #history, 1, -1 do
    if history[i] == q then table.remove(history, i) end
  end
  table.insert(history, 1, q)
  while #history > 14 do table.remove(history) end
  saveSettings()
end

local function push(v) stack[#stack + 1] = v end
local function pop()
  local v = stack[#stack]
  stack[#stack] = nil
  return v
end

local redrawRequest = false   -- something outside the keys wants the screen drawn again (a message)

local function toast(text, seconds)
  toastText = text
  toastUntil = sys.millis() + (seconds or 3) * 1000
  redrawRequest = true
end

---------------------------------------------------------------- pieces shared by the screens

-- the bar at the top: back arrow, a pill with a title, a note at the right
local function header(title, note)
  gfx.round(0, 0, W, 64, 0, theme.bg)
  if #stack > 0 then chevron(26, 22, 20, theme.dim) end
  local x, w = 64, W - 64 - 40
  gfx.round(x, 12, w, 40, 20, theme.pill)
  magnifier(x + 16, 22, 18, theme.dim, theme.pill)
  T(x + 46, 20, fit(title, "r18", w - 46 - (note and (TW(note, "r14") + 36) or 24)), theme.text, "r18")
  if note then TR(x + w - 18, 24, note, theme.dim, "r14") end
end

local function footer(text)
  gfx.round(0, H - 30, W, 30, 0, theme.bg)
  TC(W // 2, H - 24, text, theme.faint, "r12")
end

local function drawToast()
  if not toastText or sys.millis() > toastUntil then toastText = nil; return end
  local w = TW(toastText, "r16") + 40
  local x, y = (W - w) // 2, H - 76
  shadow(x, y, w, 36, 18, theme.bg, 1.5)
  gfx.round(x, y, w, 36, 18, mix(theme.text, theme.bg, 0.12))
  TC(W // 2, y + 8, toastText, theme.bg, "r16")
end

-- a whole-screen message with a spinner, shown before a slow download (the keys wait while it runs)
local function busy(text, sub)
  gfx.clear(theme.bg)
  spinner(W // 2, H // 2 - 30, 22, theme.accent, theme.bg)
  TC(W // 2, H // 2 + 14, text, theme.text, "r20")
  if sub then TC(W // 2, H // 2 + 46, sub, theme.dim, "r14") end
  gfx.flush()
end

-- the font files are fetched once, the first time
if fonts then
  local missing = false
  for _, name in ipairs(fonts.all) do
    if not fonts.have(name) then missing = true end
  end
  if missing then
    busy("Fetching the fonts", "once, about 1 MB")
    local ok, err = fonts.ensure(nil, function(i, n, name) busy("Fetching the fonts", string.format("%d of %d: %s", i, n, name)) end)
    if not ok then print("fonts: " .. tostring(err)) end
  end
end

---------------------------------------------------------------- pages

local function fetchPage(url)
  if not browser then return nil, "needs firmware v0.1 or newer" end
  return browser.open(url, TEXT_COLS)
end

local function linkTarget(v, n)
  local target, err = browser.link(v.page, n)
  if target then return target end
  if tostring(err):find("no longer", 1, true) then
    local page = fetchPage(v.url)
    if page then
      v.page = page
      target = browser.link(page, n)
      if target then return target end
    end
  end
  return nil, err
end

local function pageLines(v)
  local lines = browser.lines(v.page, v.top, READ_ROWS)
  if lines then return lines end
  local page, err = fetchPage(v.url)
  if not page then
    toast("cannot reopen the page: " .. tostring(err))
    return {}
  end
  v.page = page
  return browser.lines(page, v.top, READ_ROWS) or {}
end

local function clampPage(v)
  local maxTop = math.max(1, v.page.lines - READ_ROWS + 1)
  if v.top > maxTop then v.top = maxTop end
  if v.top < 1 then v.top = 1 end
end

local function openPage(url)
  busy("Loading " .. domainOf(url), fit(pathOf(url), "r14", 560))
  local page, err = fetchPage(url)
  if not page then
    toast("cannot open: " .. tostring(err), 4)
    return
  end
  push(view)
  view = { kind = "page", url = url, page = page, top = 1 }
  if page.truncated then toast("the page is cut at 128 KB") end
  if page.lines == 0 then toast("this page has no text") end
end

---------------------------------------------------------------- search

local function doSearch(query)
  busy("Searching", fit(query, "r14", 560))
  local items, err = search.web(query)
  if not items then
    toast("search failed: " .. tostring(err), 4)
    return
  end
  remember(query)
  if view.kind == "home" or view.kind == "results" then push(view) end
  view = { kind = "results", query = query, items = items, sel = 1, scroll = 0, scrollNow = 0 }
  if #items == 0 then toast("no results for this search") end
end

-- the grid of pictures: 5 columns of 4:3 tiles. A tile asks for a picture of its own size (never bigger than Bing has).
local GRID_COLS, GRID_ROWS = 5, 3
local TILE_W, TILE_H, GAP = 128, 96, 14
local GRID_X = (W - (GRID_COLS * TILE_W + (GRID_COLS - 1) * GAP)) // 2
local GRID_Y = 82
local PER_PAGE = GRID_COLS * GRID_ROWS

local function addPictures(v, found)
  for _, p in ipairs(found) do
    if not v.seen[p.thumb] and (not v.count or #v.items < v.count) then
      v.seen[p.thumb] = true
      v.items[#v.items + 1] = {
        title = p.title,
        small = sized(p.thumb, 256, 192),   -- sizes that divide by 16: the JPEG engine of the chip takes them
        native = stripSize(p.thumb),
        full = p.full ~= "" and p.full or nil,
        source = p.source,
      }
    end
  end
end

-- gets the pictures of the next 24 results; false when there are no more
local function morePictures(v)
  local found, err = search.pictures(v.query, v.offset)
  if not found then
    toast("picture search failed: " .. tostring(err), 4)
    return false
  end
  v.offset = v.offset + 24
  local before = #v.items
  addPictures(v, found)
  return #v.items > before
end

local function openImages(query, count)
  busy("Searching pictures", fit(query, "r14", 560))
  local v = { kind = "images", query = query, items = {}, seen = {}, offset = 0, count = count, sel = 1, requested = {}, drawn = {} }
  if not morePictures(v) then return end
  -- a count that is bigger than one page of results takes the next pages at once
  while v.count and #v.items < v.count do
    busy("Searching pictures", string.format("%d of %d", #v.items, v.count))
    if not morePictures(v) then break end
  end
  remember("img " .. query)
  if view.kind == "home" or view.kind == "results" or view.kind == "images" then push(view) end
  view = v
  if #v.items == 0 then toast("no pictures found") end
end

local function startSearch(text)
  local count, words = parseImages(text)
  if words and words ~= "" then
    openImages(words, count)
  elseif text:match("^img%s*$") then
    view = { kind = "home", input = "img ", images = true }
  else
    doSearch(text)
  end
end

---------------------------------------------------------------- drawing: home

local function fieldRect()
  return (W - 600) // 2, 214, 600, 56
end

local function drawField(v)
  local x, y, w, h = fieldRect()
  shadow(x, y, w, h, 28, theme.bg, 1.2)
  gfx.round(x, y, w, h, 28, theme.card)
  magnifier(x + 24, y + 17, 22, theme.faint, theme.card)
  local caret = (sys.millis() // 530) % 2 == 0
  if v.input == "" then
    T(x + 64, y + 14, "Search the web", theme.faint, "r20")
    if caret then gfx.round(x + 62, y + 14, 2, 26, 1, theme.accent) end
  else
    local shown = v.input
    while TW(shown, "r20") > w - 100 do shown = cleanCut(shown:sub(2)) end
    T(x + 64, y + 14, shown, theme.text, "r20")
    if caret then gfx.round(x + 66 + TW(shown, "r20"), y + 14, 2, 26, 1, theme.accent) end
  end
end

local function drawHome()
  local v = view
  gfx.clear(theme.bg)
  TC(W // 2, 70, v.images and "Pictures" or "DuckDuckGo", theme.accent, "l64")
  drawField(v)
  -- the earlier searches as chips
  local x, y = 100, 304
  for i, q in ipairs(history) do
    local label = fit(q, "r16", 300)
    local w = TW(label, "r16") + 32
    if x + w > W - 100 then x = 100; y = y + 44 end
    if y > 380 then break end
    local on = v.hist == i
    gfx.round(x, y, w, 34, 17, on and theme.accent or theme.pill)
    T(x + 16, y + 7, label, on and 0xFFFFFF or theme.dim, "r16")
    x = x + w + 10
  end
  footer("Enter search      up/down earlier searches      img 12 cats : pictures      Ctrl+T theme      Ctrl+Q quit")
  drawToast()
  gfx.flush()
end

---------------------------------------------------------------- drawing: results

local CARD_H, CARD_GAP, LIST_TOP, LIST_BOTTOM = 100, 8, 70, H - 32

local function resultY(i)
  return LIST_TOP + (i - 1) * (CARD_H + CARD_GAP) - view.scrollNow
end

local function drawResults()
  local v = view
  gfx.clear(theme.bg)
  gfx.clip(0, LIST_TOP - 4, W, LIST_BOTTOM - LIST_TOP + 4)
  for i, item in ipairs(v.items) do
    local y = resultY(i)
    if y > LIST_TOP - CARD_H and y < LIST_BOTTOM then
      local x, w = 56, W - 112
      local on = i == v.sel
      if on then
        shadow(x, y, w, CARD_H, 14, theme.bg, 1)
        gfx.round(x, y, w, CARD_H, 14, theme.card)
        gfx.round(x, y + 14, 4, CARD_H - 28, 2, theme.accent)
      end
      if not item.fitTitle then   -- the texts are fitted to the card once
        item.fitTitle = fit(item.title, "b18", w - 44)
        item.fitUrl = fit(domainOf(item.url) .. pathOf(item.url), "r14", w - 44)
        item.fitSnippet = wrap(item.snippet or "", "r14", w - 44, 2)
      end
      T(x + 22, y + 10, item.fitTitle, theme.link, "b18")
      T(x + 22, y + 36, item.fitUrl, theme.url, "r14")
      for j, line in ipairs(item.fitSnippet) do T(x + 22, y + 58 + (j - 1) * 20, line, theme.dim, "r14") end
    end
  end
  gfx.clip()
  header(v.query, #v.items .. " results")
  footer("up/down choose      Enter open      i pictures      / new search      b back      q quit")
  -- a thin scroll bar
  if #v.items > 3 then
    local total = #v.items * (CARD_H + CARD_GAP)
    local viewH = LIST_BOTTOM - LIST_TOP
    local bh = math.max(24, viewH * viewH // total)
    local by = LIST_TOP + (viewH - bh) * v.scrollNow // math.max(1, total - viewH)
    gfx.round(W - 12, by, 4, bh, 2, theme.line)
  end
  drawToast()
  gfx.flush()
end

local function clampResults(v)
  if v.sel < 1 then v.sel = 1 end
  if v.sel > #v.items then v.sel = #v.items end
  local top = (v.sel - 1) * (CARD_H + CARD_GAP)
  local viewH = LIST_BOTTOM - LIST_TOP
  if top < v.scroll then v.scroll = top end
  if top + CARD_H > v.scroll + viewH then v.scroll = top + CARD_H - viewH end
  local maxScroll = math.max(0, #v.items * (CARD_H + CARD_GAP) - viewH)
  if v.scroll > maxScroll then v.scroll = maxScroll end
  if v.scroll < 0 then v.scroll = 0 end
end

---------------------------------------------------------------- drawing: a page

local function drawPage()
  local v = view
  gfx.clear(theme.bg)
  local x = (W - 640) // 2
  local lines = pageLines(v)
  for row, line in ipairs(lines) do
    local y = READ_TOP + (row - 1) * READ_LINE
    local cx = x
    -- the link marks [n] get the color of links
    local pos = 1
    while pos <= #line do
      local s, e = line:find("%[%d+%]", pos)
      local plain = line:sub(pos, (s or #line + 1) - 1)
      if plain ~= "" then
        T(cx, y, plain, theme.text, "r18")
        cx = cx + TW(plain, "r18")
      end
      if not s then break end
      local mark = line:sub(s, e)
      T(cx, y, mark, theme.link, "b16")
      cx = cx + TW(mark, "b16")
      pos = e + 1
    end
  end
  local last = math.min(v.top + READ_ROWS - 1, v.page.lines)
  header(domainOf(v.url) .. pathOf(v.url), v.page.lines > 0 and string.format("%d%%", math.floor(last * 100 / v.page.lines)) or nil)
  if v.linkInput then
    local label = "Link number: " .. v.linkInput .. "_   (Enter opens it)"
    local w = TW(label, "r16") + 40
    shadow((W - w) // 2, H - 74, w, 38, 19, theme.bg, 1.5)
    gfx.round((W - w) // 2, H - 74, w, 38, 19, theme.card)
    TC(W // 2, H - 65, label, theme.text, "r16")
    footer("")
  else
    footer(string.format("lines %d-%d of %d      links %d      l link      b back      / search      q quit", v.top, last, v.page.lines, v.page.links))
  end
  -- a thin scroll bar
  if v.page.lines > READ_ROWS then
    local viewH = H - 70 - 34
    local bh = math.max(24, viewH * READ_ROWS // v.page.lines)
    local by = 70 + (viewH - bh) * (v.top - 1) // math.max(1, v.page.lines - READ_ROWS)
    gfx.round(W - 12, by, 4, bh, 2, theme.line)
  end
  drawToast()
  gfx.flush()
end

---------------------------------------------------------------- drawing: the grid of pictures

local function tileRect(i)
  local slot = (i - 1) % PER_PAGE
  local col, row = slot % GRID_COLS, slot // GRID_COLS
  return GRID_X + col * (TILE_W + GAP), GRID_Y + row * (TILE_H + GAP)
end

local function pageOf(v)
  return (v.sel - 1) // PER_PAGE
end

local function drawTile(v, i, selected)
  local item = v.items[i]
  if not item then return end
  local x, y = tileRect(i)
  gfx.round(x - 8, y - 8, TILE_W + 16, TILE_H + 16, 12, theme.bg)
  if selected then gfx.round(x - 4, y - 4, TILE_W + 8, TILE_H + 8, 10, theme.ring) end
  local state = term.imageStatus(item.small)
  if state == "ready" then
    local ok = gfx.image(item.small, x, y, TILE_W, TILE_H, "cover")
    if ok then
      v.drawn[i] = true
      return
    end
  end
  v.drawn[i] = false
  gfx.round(x, y, TILE_W, TILE_H, 6, mix(theme.bg, theme.text, 0.07))
  if state == "failed" then
    TC(x + TILE_W // 2, y + TILE_H // 2 - 8, "no picture", theme.faint, "r12")
  else
    spinner(x + TILE_W // 2, y + TILE_H // 2, 9, theme.spin, mix(theme.bg, theme.text, 0.07))
  end
end

local function drawGridChrome(v)
  local pages = math.max(1, (#v.items + PER_PAGE - 1) // PER_PAGE)
  header("Pictures: " .. v.query, string.format("%d / %d", pageOf(v) + 1, pages))
  -- the title of the chosen picture under the grid
  gfx.round(0, H - 76, W, 76, 0, theme.bg)
  local it = v.items[v.sel]
  if it then
    TC(W // 2, H - 74, fit(it.title, "r16", W - 120), theme.text, "r16")
    TC(W // 2, H - 50, domainOf(it.source) .. "   " .. v.sel .. " of " .. #v.items, theme.faint, "r12")
  end
end

local function queueThumbs(v)
  term.imageDrop()
  local page = pageOf(v)
  for p = page, page + 1 do
    for i = p * PER_PAGE + 1, math.min(#v.items, (p + 1) * PER_PAGE) do
      term.imageFetch(v.items[i].small, p == page)
    end
  end
end

local function drawImages(full)
  local v = view
  if full then
    gfx.clear(theme.bg)
    local first = pageOf(v) * PER_PAGE + 1
    for i = first, math.min(#v.items, first + PER_PAGE - 1) do drawTile(v, i, i == v.sel) end
    drawGridChrome(v)
    if #v.items == 0 then TC(W // 2, 220, "No pictures", theme.dim, "r24") end
    footer("arrows choose      Enter open      / new search      b back      q quit")
    drawToast()
    gfx.flush()
  end
end

---------------------------------------------------------------- drawing: one picture on the whole screen

local OVERLAY_MS = 3200

local function bestPicture(item)
  if item.full and not item.fullBad and term.imageStatus(item.full) == "ready" then return item.full, "full" end
  if term.imageStatus(item.native) == "ready" then return item.native, "native" end
  if term.imageStatus(item.small) == "ready" then return item.small, "small" end
  return nil
end

local function drawPicture()
  local v = view
  local item = v.items[v.index]
  gfx.clear(0x000000)
  local src, quality = bestPicture(item)
  local ok, err = false, nil
  if src then
    ok, err = gfx.image(src, 0, 0, W, H)
    if not ok and quality == "full" then
      item.fullBad = true   -- too big, or not a picture at all (the site refused it): the thumbnail stays
      src, quality = bestPicture(item)
      if src then ok, err = gfx.image(src, 0, 0, W, H) end
    end
  end
  v.quality = ok and quality or nil
  if not ok then
    local st = term.imageStatus(item.native)
    if st == "failed" and term.imageStatus(item.small) == "failed" then
      TC(W // 2, H // 2 - 14, "This picture is not available", 0xC8C8CC, "r20")
    else
      spinner(W // 2, H // 2, 22, 0x8E8E93, 0x000000)
    end
  elseif quality ~= "full" and item.full and not item.fullBad and term.imageStatus(item.full) ~= "failed" then
    spinner(W - 34, 34, 11, 0xDDDDDD, 0x000000)   -- the sharper picture is on its way
  end
  if sys.millis() < (v.overlayUntil or 0) then
    gfx.alpha(0, H - 92, W, 92, 0x000000, 150)
    T(34, H - 82, fit(item.title, "b20", W - 68), 0xFFFFFF, "b20")
    T(34, H - 48, domainOf(item.source) .. "     " .. v.index .. " / " .. #v.items, 0xC8C8CC, "r14")
    if v.index > 1 then chevron(10, H // 2 - 12, 24, 0xEEEEEE) end
  end
  drawToast()
  gfx.flush()
end

local function wantPictures(v)
  -- the picture on the screen first, then the ones next to it
  local order = { v.index, v.index + 1, v.index - 1 }
  term.imageDrop()
  for _, i in ipairs(order) do
    local it = v.items[i]
    if it then
      term.imageFetch(it.native, i == v.index)
      if i == v.index and it.full and it.full:lower():find("%.jpe?g") then term.imageFetch(it.full) end
    end
  end
end

---------------------------------------------------------------- keys

local function openPictureView(v)
  push(view)
  view = { kind = "picture", items = v.items, index = v.sel, query = v.query, source = v, overlayUntil = sys.millis() + OVERLAY_MS }
  wantPictures(view)
end

local function moveInGrid(v, to)
  local old = v.sel
  v.sel = math.max(1, math.min(#v.items, to))
  if v.sel == old then return false end
  -- the end of the pictures: the next 24 results come when the last page is reached
  if not v.count and v.sel > #v.items - PER_PAGE and not v.exhausted then
    busy("More pictures", fit(v.query, "r14", 560))
    if not morePictures(v) then v.exhausted = true end
    return true, true
  end
  return true, pageOf(v) ~= (old - 1) // PER_PAGE
end

local function handleKey(k)
  if k == "ctrl-q" then return "quit" end
  local v = view
  if v.kind == "home" then
    if k == "enter" then
      local text = v.input
      if text == "" and v.hist and v.hist > 0 then text = history[v.hist] end
      if text and text ~= "" then
        if v.images and not text:match("^img") then text = "img " .. text end
        startSearch(text)
      end
    elseif k == "backspace" then
      v.input = cleanCut(v.input:sub(1, -2))
      v.hist = 0
    elseif k == "up" then
      v.hist = math.min(#history, (v.hist or 0) + 1)
      if v.hist > 0 then v.input = history[v.hist] end
    elseif k == "down" then
      v.hist = math.max(0, (v.hist or 0) - 1)
      v.input = v.hist > 0 and history[v.hist] or ""
    elseif k == "ctrl-t" then
      theme = theme == themes.light and themes.dark or themes.light
      saveSettings()
    elseif #k == 1 and k:byte() >= 32 then
      v.input = v.input .. k
      v.hist = 0
    end
    return
  end

  if v.kind == "results" then
    if k == "q" then return "quit"
    elseif k == "up" then v.sel = v.sel - 1; clampResults(v)
    elseif k == "down" then v.sel = v.sel + 1; clampResults(v)
    elseif k == "pageup" then v.sel = v.sel - 3; clampResults(v)
    elseif k == "pagedown" then v.sel = v.sel + 3; clampResults(v)
    elseif k == "enter" and #v.items > 0 then openPage(v.items[v.sel].url)
    elseif k == "i" then openImages(v.query, nil)
    elseif k == "/" then push(v); view = { kind = "home", input = "" }
    elseif (k == "b" or k == "backspace") and #stack > 0 then view = pop()
    elseif k == "t" then theme = theme == themes.light and themes.dark or themes.light; saveSettings()
    end
    return
  end

  if v.kind == "page" then
    if v.linkInput then
      if k:match("^%d$") then v.linkInput = v.linkInput .. k
      elseif k == "backspace" then v.linkInput = v.linkInput:sub(1, -2)
      elseif k == "enter" then
        local n = tonumber(v.linkInput)
        v.linkInput = nil
        if n then
          local target, err = linkTarget(v, n)
          if target then openPage(target) else toast(tostring(err)) end
        else
          toast("no link")
        end
      else
        v.linkInput = nil
      end
      return
    end
    if k == "q" then return "quit"
    elseif k == "up" then v.top = v.top - 1; clampPage(v)
    elseif k == "down" then v.top = v.top + 1; clampPage(v)
    elseif k == "pageup" then v.top = v.top - (READ_ROWS - 1); clampPage(v)
    elseif k == "pagedown" or k == " " then v.top = v.top + (READ_ROWS - 1); clampPage(v)
    elseif k == "g" then v.top = 1
    elseif k == "G" then v.top = v.page.lines; clampPage(v)
    elseif k == "l" then v.linkInput = ""
    elseif k == "/" then push(v); view = { kind = "home", input = "" }
    elseif (k == "b" or k == "backspace") and #stack > 0 then view = pop()
    elseif k == "t" then theme = theme == themes.light and themes.dark or themes.light; saveSettings()
    end
    return
  end

  if v.kind == "images" then
    local n = #v.items
    local changed, page = false, false
    if k == "q" then return "quit"
    elseif k == "left" then changed, page = moveInGrid(v, v.sel - 1)
    elseif k == "right" then changed, page = moveInGrid(v, v.sel + 1)
    elseif k == "up" then changed, page = moveInGrid(v, v.sel - GRID_COLS)
    elseif k == "down" then changed, page = moveInGrid(v, v.sel + GRID_COLS)
    elseif k == "pageup" then changed, page = moveInGrid(v, v.sel - PER_PAGE)
    elseif k == "pagedown" then changed, page = moveInGrid(v, v.sel + PER_PAGE)
    elseif k == "enter" and n > 0 then openPictureView(v)
    elseif k == "/" then push(v); view = { kind = "home", input = "", images = true }
    elseif (k == "b" or k == "backspace") and #stack > 0 then view = pop()
    elseif k == "t" then theme = theme == themes.light and themes.dark or themes.light; saveSettings(); v.redraw = true
    end
    if changed then
      if page then
        v.redraw = true
        queueThumbs(v)
      else
        v.moved = true
      end
    end
    return
  end

  if v.kind == "picture" then
    local i = v.index
    if k == "q" then return "quit"
    elseif k == "left" then i = math.max(1, i - 1)
    elseif k == "right" then i = math.min(#v.items, i + 1)
    elseif (k == "b" or k == "backspace") and #stack > 0 then
      local back = pop()
      back.sel = v.index
      view = back
      back.redraw = true
      queueThumbs(back)
      return
    end
    v.overlayUntil = sys.millis() + OVERLAY_MS
    if i ~= v.index then
      v.index = i
      wantPictures(v)
    end
    v.redraw = true
    return
  end
end

---------------------------------------------------------------- the main loop

loadSettings()

local initial = table.concat(arg, " ")
local firstCount, firstWords = parseImages(initial)
if firstWords and firstWords ~= "" then
  openImages(firstWords, firstCount)
elseif initial == "img" then
  view = { kind = "home", input = "", images = true }
elseif initial ~= "" then
  doSearch(initial)
end
if view.kind == "images" then queueThumbs(view) end

local lastDraw, lastTick, lastFlush = 0, 0, 0
local redraw = true
local quit = false

while not quit do
  local k = key.poll()
  while k do
    lastKeyAt = sys.millis()
    local v0 = view
    local action = handleKey(k)
    if action == "quit" then quit = true; break end
    if view.kind ~= "images" then redraw = true end   -- (the grid redraws only what changed)
    if view ~= v0 then
      redraw = true
      if view.kind == "images" then view.redraw = true; queueThumbs(view) end
    end
    k = key.poll()
  end
  if quit then break end

  local v = view
  local now = sys.millis()
  if redrawRequest then redrawRequest = false; redraw = true; v.redraw = true end
  if v.kind == "home" then
    -- the box redraws itself for the caret; the rest only when something changed
    if redraw or now - lastTick > 530 then drawHome(); lastTick = now; redraw = false end
  elseif v.kind == "results" then
    local d = v.scroll - v.scrollNow
    if math.abs(d) > 0.5 then v.scrollNow = v.scrollNow + d * 0.4; redraw = true else v.scrollNow = v.scroll end
    if redraw then drawResults(); redraw = false end
    if toastText and now > toastUntil then toastText = nil; drawResults() end
  elseif v.kind == "page" then
    if redraw or (v.moved) then drawPage(); redraw = false; v.moved = nil end
    if toastText and now > toastUntil then toastText = nil; drawPage() end
  elseif v.kind == "images" then
    if redraw or v.redraw then
      drawImages(true)
      redraw = false
      v.redraw = false
      v.moved = false
    elseif v.moved then
      -- only the two tiles and the title change
      local old = v.prevSel
      v.moved = false
      local first = pageOf(v) * PER_PAGE + 1
      for i = first, math.min(#v.items, first + PER_PAGE - 1) do
        if v.drawn[i] ~= nil and (i == v.sel or i == v.prevSel) then drawTile(v, i, i == v.sel) end
      end
      drawGridChrome(v)
      gfx.flush()
    else
      -- a picture that has arrived is drawn in its tile; the spinners turn
      local first = pageOf(v) * PER_PAGE + 1
      local any, pending = false, false
      for i = first, math.min(#v.items, first + PER_PAGE - 1) do
        local it = v.items[i]
        if not v.drawn[i] then
          local st = term.imageStatus(it.small)
          if st == "ready" or st == "failed" then drawTile(v, i, i == v.sel); any = true
          elseif now - lastTick > 90 then drawTile(v, i, i == v.sel); any = true; pending = true
          else pending = true end
        end
      end
      if any then
        if now - lastTick > 90 then lastTick = now end
        gfx.flush()
      end
      v.prevSel = v.sel
    end
    v.prevSel = v.sel
    if toastText and now > toastUntil then toastText = nil; v.redraw = true end
  elseif v.kind == "picture" then
    local item = v.items[v.index]
    local src, quality = bestPicture(item)
    local overlay = now < (v.overlayUntil or 0)
    if redraw or v.redraw or (quality ~= v.quality) or (v.overlayShown ~= overlay) or (not src and now - lastTick > 90) then
      drawPicture()
      v.redraw = false
      v.overlayShown = overlay
      redraw = false
      lastTick = now
    end
    if toastText and now > toastUntil then toastText = nil; v.redraw = true end
  end
  if now - lastFlush > 250 then gfx.flush(); lastFlush = now end   -- the screen is kept alive
  sys.sleep(12)
end

gfx.close()
