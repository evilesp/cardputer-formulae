#!lua
-- duckduckgo: a text browser that searches with DuckDuckGo.
-- Type a search (or run: duckduckgo WORDS...), pick a result with up/down and Enter, read the page.
-- l then a number and Enter follows a link. b goes back, / starts a new search, q quits.
-- Pictures: duckduckgo img WORDS (or type "img WORDS" in the search box) shows a grid of pictures.

local COLS, ROWS = term.size()
local TEXT_ROWS = ROWS - 2
local WIDTH = COLS - 1
-- Sites answer 202 (a bot check) to clients that do not look like a browser
local BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
-- The ADV has no PSRAM: pages are read in 40 KB, so the browser stays inside the internal RAM
local PAGE_BYTES = 40 * 1024
local PER_PAGE = 8  -- pictures on one screen: 4 columns, 2 rows

---------------------------------------------------------------- text helpers

local function urlDecode(s)
  s = s:gsub("%+", " ")
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local CODE_MAP = {
  [160] = " ", [169] = "(c)", [174] = "(R)", [8211] = "-", [8212] = "-", [8216] = "'", [8217] = "'",
  [8220] = '"', [8221] = '"', [8230] = "...",
}
local NAMED = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ", mdash = "-", ndash = "-",
  hellip = "...", copy = "(c)", reg = "(R)", trade = "TM", lsquo = "'", rsquo = "'", ldquo = '"',
  rdquo = '"', bull = "*", middot = "*", laquo = '"', raquo = '"',
}

local function codepoint(n)
  if CODE_MAP[n] then return CODE_MAP[n] end
  if n >= 32 and n < 127 then return string.char(n) end
  return "?"
end

local function decodeEntities(s)
  s = s:gsub("&#[xX](%x+);", function(h) return codepoint(tonumber(h, 16)) end)
  s = s:gsub("&#(%d+);", function(d) return codepoint(tonumber(d)) end)
  s = s:gsub("&(%a+);", function(n) return NAMED[n:lower()] or ("&" .. n .. ";") end)
  return s
end

-- common UTF-8 punctuation becomes ASCII, other characters become ?
local UTF8_MAP = {
  ["\226\128\156"] = '"', ["\226\128\157"] = '"', ["\226\128\152"] = "'", ["\226\128\153"] = "'",
  ["\226\128\147"] = "-", ["\226\128\148"] = "-", ["\226\128\166"] = "...", ["\194\160"] = " ",
}
local function fixUtf8(s)
  return (s:gsub("[\192-\255][\128-\191]*", function(seq) return UTF8_MAP[seq] or "?" end))
end

local function stripTags(s)
  return (s:gsub("<[^>]*>", ""))
end

local function squash(s)
  local t = s:gsub("%s+", " ")
  return (t:match("^%s*(.-)%s*$"))
end

local function clean(s)
  return squash(fixUtf8(decodeEntities(stripTags(s))))
end

local function domainOf(url)
  return url:match("^https?://([^/]+)") or url
end

---------------------------------------------------------------- URLs

-- absolute URL for a link found on the page at base
local function resolveUrl(base, href)
  href = decodeEntities(href)
  if href == "" or href:sub(1, 1) == "#" then return nil end
  local lower = href:lower()
  if lower:find("^javascript:") or lower:find("^mailto:") or lower:find("^tel:") or lower:find("^data:") then
    return nil
  end
  -- DuckDuckGo wraps result links: //duckduckgo.com/l/?uddg=ENCODED_URL&...
  if href:find("duckduckgo%.com/l/") or href:find("^/l/") then
    local target = href:match("[?&]uddg=([^&]*)")
    if target then return urlDecode(target) end
  end
  if href:find("^https?://") then return href end
  if href:sub(1, 2) == "//" then return "https:" .. href end
  local scheme, host, path = base:match("^(https?://)([^/]+)(.*)$")
  if not scheme then return nil end
  if href:sub(1, 1) == "/" then return scheme .. host .. href end
  local dir = path:match("^(.*/)") or "/"
  return scheme .. host .. dir .. href
end

---------------------------------------------------------------- HTML

local BLOCK = {
  p = true, div = true, li = true, h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
  tr = true, table = true, ul = true, ol = true, section = true, article = true, header = true,
  footer = true, nav = true, blockquote = true, pre = true, hr = true, dt = true, dd = true, form = true,
}
local DROP = { "script", "style", "noscript", "svg", "template", "select", "button", "iframe" }

-- page text, wrapped to the screen, with links numbered [1], [2]...
local function htmlToText(html, base)
  local links = {}
  html = html:gsub("<!%-%-.-%-%->", "")
  html = html:gsub("<![^>]*>", "")
  html = html:gsub("<head[^>]*>.-</head>", "")
  for _, tag in ipairs(DROP) do
    html = html:gsub("<" .. tag .. "[^>]*>.-</" .. tag .. ">", "")
  end
  html = html:gsub("<a(%s[^>]*)>(.-)</a>", function(attrs, inner)
    local href = attrs:match('href="([^"]*)"') or attrs:match("href='([^']*)'")
    local text = clean(inner)
    local target = href and resolveUrl(base, href)
    if target and text ~= "" then
      links[#links + 1] = target
      return " " .. text .. "[" .. #links .. "] "
    end
    return " " .. text .. " "
  end)
  html = html:gsub("<br[^>]*>", "\n")
  html = html:gsub("<li[^>]*>", "\n* ")
  html = html:gsub("<(/?)(%w+)[^>]*>", function(_, name)
    if BLOCK[name:lower()] then return "\n" end
    return ""
  end)
  html = fixUtf8(decodeEntities(html))

  local lines = {}
  for raw in (html .. "\n"):gmatch("([^\n]*)\n") do
    local line = squash(raw)
    if line ~= "" or (#lines > 0 and lines[#lines] ~= "") then lines[#lines + 1] = line end
  end

  local wrapped = {}
  for _, line in ipairs(lines) do
    if line == "" then
      wrapped[#wrapped + 1] = ""
    else
      local cur = ""
      for word in line:gmatch("%S+") do
        local w = word
        while #w > WIDTH do
          if cur ~= "" then wrapped[#wrapped + 1] = cur; cur = "" end
          wrapped[#wrapped + 1] = w:sub(1, WIDTH)
          w = w:sub(WIDTH + 1)
        end
        if cur == "" then
          cur = w
        elseif #cur + 1 + #w <= WIDTH then
          cur = cur .. " " .. w
        else
          wrapped[#wrapped + 1] = cur
          cur = w
        end
      end
      if cur ~= "" then wrapped[#wrapped + 1] = cur end
    end
  end
  return wrapped, links
end

---------------------------------------------------------------- navigation

local stack = {}
local view = { kind = "search", input = "" }
local status = nil     -- message shown on the bottom row
local linkInput = nil  -- digits typed after "l", or nil

local function push(v) stack[#stack + 1] = v end
local function pop()
  local v = stack[#stack]
  stack[#stack] = nil
  return v
end

local function fetchPage(url, maxBytes)
  local code, body, truncated = net.fetch(url, maxBytes, BROWSER_UA)
  if not code then return nil, body end
  if code ~= 200 then return nil, "HTTP " .. code end
  return body, truncated
end

-- The device reads the results page itself (search.web), so no page text is built here
local function doSearch(query)
  status = "searching DuckDuckGo..."
  term.clear()
  term.text(0, 7, status, "cyan")
  term.flush()
  local items, err = search.web(query)
  if not items then
    status = "search failed: " .. tostring(err)
    return
  end
  status = #items == 0 and "no results for this search" or nil
  push(view)
  view = { kind = "results", query = query, items = items, sel = 1, top = 1 }
end

local function openPage(url)
  status = "loading " .. domainOf(url) .. "..."
  term.clear()
  term.text(0, 7, status, "cyan")
  term.flush()
  local body, info = fetchPage(url, PAGE_BYTES)
  if not body then
    status = "cannot open: " .. tostring(info)
    return
  end
  local lines, links = htmlToText(body, url)
  status = info and "page cut at 40 KB" or nil
  push(view)
  view = { kind = "page", url = url, lines = lines, links = links, top = 1 }
  if #lines == 0 then status = "this page has no text" end
end

local function clampResults()
  local v = view
  if v.sel < 1 then v.sel = 1 end
  if v.sel > #v.items then v.sel = #v.items end
  if v.sel < v.top then v.top = v.sel end
  if v.sel >= v.top + 4 then v.top = v.sel - 3 end
  if v.top < 1 then v.top = 1 end
end

local function clampPage()
  local maxTop = math.max(1, #view.lines - TEXT_ROWS + 1)
  if view.top > maxTop then view.top = maxTop end
  if view.top < 1 then view.top = 1 end
end

---------------------------------------------------------------- pictures

-- thumbnail address with a size: Bing scales the picture on its side, so the device downloads little
local function withSize(url, w, h)
  local base = url:gsub("&[whc]=[^&]*", "")
  return base .. (base:find("%?") and "&" or "?") .. string.format("w=%d&h=%d&c=7", w, h)
end

local function openImages(query)
  status = "searching pictures..."
  term.clear()
  term.text(0, 7, status, "cyan")
  term.flush()
  local found, err = search.pictures(query)
  if not found then
    status = "picture search failed: " .. tostring(err)
    return
  end
  local items = {}
  for _, p in ipairs(found) do
    items[#items + 1] = {
      title = p.title,
      thumb = withSize(p.thumb, 112, 84),
      big = withSize(p.thumb, 140, 105),
      source = p.source,
    }
  end
  push(view)
  view = { kind = "images", query = query, items = items, sel = 1 }
  status = #items == 0 and "no pictures found" or nil
end

local function drawImages()
  local v = view
  local n = #v.items
  local pages = math.max(1, (n + PER_PAGE - 1) // PER_PAGE)
  local page = (v.sel - 1) // PER_PAGE
  local first = page * PER_PAGE + 1
  local last = math.min(n, first + PER_PAGE - 1)
  term.text(0, 0, ("pictures: " .. v.query):sub(1, COLS - 6), "white")
  term.text(COLS - 5, 0, string.format("%d/%d", page + 1, pages), "dim")
  if n == 0 then term.text(0, 3, status or "no pictures", "warn") end
  for i = first, last do
    local slot = i - first
    local col, row = slot % 4, slot // 4
    local caption = (i == v.sel and ">" or " ") .. v.items[i].title:sub(1, 8)
    term.text(col * 10, row == 0 and 7 or 14, caption, i == v.sel and "white" or "dim")
  end
  if status then
    term.text(0, ROWS - 1, status:sub(1, COLS), "warn")
  else
    term.text(0, ROWS - 1, "arrows move  enter open  / new  b back", "dim")
  end
  term.flush()
  -- pictures go on top of the text, cell by cell (a download meter may show on the last row meanwhile).
  -- This runs on every screen update, so a picture that failed is not fetched again.
  for i = first, last do
    local item = v.items[i]
    if not item.failed then
      local slot = i - first
      local col, row = slot % 4, slot // 4
      if not term.image(item.thumb, col * 60 + 2, row == 0 and 8 or 64, 0.5) then
        item.failed = true
      end
    end
  end
end

local function drawPicture()
  local v = view
  local item = v.items[v.index]
  term.clear()
  term.text(0, 0, item.title:sub(1, COLS), "white")
  term.text(0, ROWS - 1, (domainOf(item.source) .. "  left/right  b back  q quit"):sub(1, COLS), "dim")
  term.flush()
  local ok, err = term.image(item.big, 50, 8, 1.0)
  if not ok then
    term.text(0, 6, "picture not available:", "warn")
    term.text(0, 7, tostring(err):sub(1, COLS), "dim")
    term.flush()
  end
end

---------------------------------------------------------------- drawing

local function drawSearch()
  term.text(0, 0, view.images and "DuckDuckGo image search" or "DuckDuckGo search", "white")
  term.text(0, 2, "search: " .. view.input .. "_", "green")
  term.text(0, 4, "type a query, then Enter", "dim")
  if status then term.text(0, 6, status, "warn") end
  term.text(0, ROWS - 1, "enter search  ctrl-q quit", "dim")
end

local function drawResults()
  local q = view.query
  term.text(0, 0, ("results: " .. q):sub(1, COLS), "white")
  if #view.items == 0 then
    term.text(0, 2, status or "no results", "warn")
  end
  local y = 1
  for i = view.top, math.min(#view.items, view.top + 3) do
    local item = view.items[i]
    local selected = i == view.sel
    term.text(0, y, (selected and "> " or "  ") .. item.title:sub(1, COLS - 2), selected and "white" or "text")
    term.text(0, y + 1, "  " .. domainOf(item.url):sub(1, COLS - 2), "cyan")
    y = y + 3
  end
  if status and #view.items > 0 then term.text(0, ROWS - 2, status, "warn") end
  if linkInput then
    term.text(0, ROWS - 1, "", "dim")
  else
    term.text(0, ROWS - 1, "up/dn select enter open / new q quit", "dim")
  end
end

local function drawPage()
  local v = view
  term.text(0, 0, (domainOf(v.url) .. "  " .. v.url:match("^https?://[^/]+(.*)$")):sub(1, COLS), "white")
  for row = 0, TEXT_ROWS - 1 do
    local line = v.lines[v.top + row]
    if line then term.text(0, row + 1, line, "text") end
  end
  local last = math.min(v.top + TEXT_ROWS - 1, #v.lines)
  local bottom
  if linkInput then
    bottom = "link number: " .. linkInput .. "_  (enter opens)"
  elseif status then
    bottom = status
  else
    bottom = string.format("%d-%d/%d  links %d  l b / q", v.top, last, #v.lines, #v.links)
  end
  term.text(0, ROWS - 1, bottom:sub(1, COLS), status and "warn" or "dim")
end

local function draw()
  term.clear()
  if view.kind == "search" then drawSearch()
  elseif view.kind == "results" then drawResults()
  elseif view.kind == "images" then drawImages()
  elseif view.kind == "picture" then drawPicture()
  else drawPage() end
  term.flush()
end

---------------------------------------------------------------- keys

local function handleKey(k)
  if k == "ctrl-q" then return "quit" end
  if view.kind == "search" then
    if k == "enter" then
      if view.input ~= "" then
        local q = view.input
        local picQuery = q:match("^img%s+(.+)$") or (view.images and q)
        if picQuery then openImages(picQuery) else doSearch(q) end
      elseif #stack > 0 then
        view = pop()
      end
    elseif k == "backspace" then
      view.input = view.input:sub(1, -2)
    elseif #k == 1 and k:match("[%g ]") then
      view.input = view.input .. k
    end
    return
  end

  if view.kind == "images" then
    local v = view
    local n = #v.items
    if k == "q" then return "quit"
    elseif k == "left" then v.sel = math.max(1, v.sel - 1)
    elseif k == "right" then v.sel = math.min(n, v.sel + 1)
    elseif k == "up" then v.sel = math.max(1, v.sel - 4)
    elseif k == "down" then v.sel = math.min(n, v.sel + 4)
    elseif k == "pageup" then v.sel = math.max(1, v.sel - PER_PAGE)
    elseif k == "pagedown" then v.sel = math.min(n, v.sel + PER_PAGE)
    elseif k == "enter" and n > 0 then
      push(view)
      view = { kind = "picture", items = v.items, index = v.sel, query = v.query }
      status = nil
    elseif k == "/" then
      push(view)
      view = { kind = "search", input = "", images = true }
      status = nil
    elseif k == "b" and #stack > 0 then
      view = pop()
      status = nil
    end
    return
  end

  if view.kind == "picture" then
    local v = view
    if k == "q" then return "quit"
    elseif k == "left" and v.index > 1 then v.index = v.index - 1
    elseif k == "right" and v.index < #v.items then v.index = v.index + 1
    elseif k == "b" and #stack > 0 then view = pop()
    end
    return
  end

  if view.kind == "results" then
    if k == "q" then return "quit"
    elseif k == "up" then view.sel = view.sel - 1; clampResults()
    elseif k == "down" then view.sel = view.sel + 1; clampResults()
    elseif k == "pageup" then view.sel = view.sel - 4; clampResults()
    elseif k == "pagedown" then view.sel = view.sel + 4; clampResults()
    elseif k == "enter" and #view.items > 0 then
      local item = view.items[view.sel]
      openPage(item.url)
    elseif k == "/" then
      push(view)
      view = { kind = "search", input = "" }
      status = nil
    elseif k == "b" and #stack > 0 then
      view = pop()
      status = nil
    end
    return
  end

  -- page
  if linkInput then
    if k:match("^%d$") then
      linkInput = linkInput .. k
    elseif k == "backspace" then
      linkInput = linkInput:sub(1, -2)
    elseif k == "enter" then
      local n = tonumber(linkInput)
      linkInput = nil
      if n and view.links[n] then
        openPage(view.links[n])
      else
        status = "no link " .. tostring(n)
      end
    else
      linkInput = nil
    end
    return
  end
  if k == "q" then return "quit"
  elseif k == "up" then view.top = view.top - 1; clampPage()
  elseif k == "down" then view.top = view.top + 1; clampPage()
  elseif k == "pageup" then view.top = view.top - (TEXT_ROWS - 1); clampPage()
  elseif k == "pagedown" or k == " " then view.top = view.top + (TEXT_ROWS - 1); clampPage()
  elseif k == "g" then view.top = 1
  elseif k == "G" then view.top = #view.lines; clampPage()
  elseif k == "l" then linkInput = ""; status = nil
  elseif k == "b" and #stack > 0 then view = pop(); status = nil
  elseif k == "/" then
    push(view)
    view = { kind = "search", input = "" }
    status = nil
  end
end

---------------------------------------------------------------- self test

local function selftest()
  local checks = 0
  local function expect(got, want)
    checks = checks + 1
    if got ~= want then error(string.format("check %d: got %q, want %q", checks, tostring(got), tostring(want))) end
  end
  expect(urlDecode("a+b%26c"), "a b&c")
  expect(decodeEntities("&amp;&lt;&#65;&#x42;&nbsp;x&hellip;"), "&<AB x...")
  expect(clean("<b>Hi</b>&nbsp;<i>there</i>"), "Hi there")
  expect(resolveUrl("https://a.org/x/y.html", "z.html"), "https://a.org/x/z.html")
  expect(resolveUrl("https://a.org/x/y.html", "/top"), "https://a.org/top")
  expect(resolveUrl("https://a.org/", "//b.org/p"), "https://b.org/p")
  expect(resolveUrl("https://a.org/", "mailto:x@y"), nil)
  expect(resolveUrl("https://a.org/", "//duckduckgo.com/l/?uddg=https%3A%2F%2Fe.org%2Fp&rut=1"), "https://e.org/p")
  local lines, links = htmlToText('<head><title>t</title></head><p>Hello <a href="/next">more</a> world</p><script>x()</script>', "https://a.org/")
  expect(lines[1], "Hello more[1] world")
  expect(links[1], "https://a.org/next")
  local page = htmlToText('<!doctype html><div><h1>Example Domain</h1><p>Some text here.</p></div>', "https://a.org/")
  expect(page[1], "Example Domain")
  expect(page[3], "Some text here.")  -- headings and paragraphs are separated by a blank line
  print(string.format("selftest ok (%d checks)", checks))
end

if arg[1] == "--selftest" then
  selftest()
  return
end

---------------------------------------------------------------- main

term.fullscreen(true)
local initial = table.concat(arg, " ")
if arg[1] == "img" then
  local words = table.concat(arg, " ", 2)
  if words ~= "" then openImages(words) else view = { kind = "search", input = "", images = true } end
elseif initial ~= "" then
  doSearch(initial)
end

local quit = false
while not quit do
  local k = key.poll()
  while k do
    local action = handleKey(k)
    if action == "quit" then quit = true break end
    k = key.poll()
  end
  if quit then break end
  draw()
  sys.sleep(50)
end
term.fullscreen(false)
