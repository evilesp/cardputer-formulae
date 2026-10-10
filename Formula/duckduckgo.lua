#!lua
-- duckduckgo: a text browser that searches with DuckDuckGo.
-- Type a search (or run: duckduckgo WORDS...), pick a result with up/down and Enter, read the page.
-- l then a number and Enter follows a link. b goes back, / starts a new search, q quits.
-- Pictures: duckduckgo img WORDS (or type "img WORDS" in the search box) shows a grid of pictures.
-- Pages and pictures are kept on the SD card, because the ADV's RAM is small: only the lines and the pictures that
-- are on the screen are read back. Pages need firmware v0.1.0.8(beta) or newer.

local COLS, ROWS = term.size()
local TEXT_ROWS = ROWS - 2
local PER_PAGE = 8  -- pictures on one screen: 4 columns, 2 rows

---------------------------------------------------------------- helpers

local function domainOf(url)
  return url:match("^https?://([^/]+)") or url
end

-- thumbnail address with a size: Bing scales the picture on its side, so the device downloads little
local function withSize(url, w, h)
  local base = url:gsub("&[whc]=[^&]*", "")
  return base .. (base:find("%?") and "&" or "?") .. string.format("w=%d&h=%d&c=7", w, h)
end

-- a message on an otherwise empty screen, shown before a slow download starts
local function showMessage(text, color)
  term.clear()
  term.text(0, 7, text, color or "cyan")
  term.flush()
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

---------------------------------------------------------------- pages

-- opens a page on the SD card: the handle and the size of the page come back, the text stays on the card
local function fetchPage(url)
  if not browser then return nil, "needs firmware v0.1.0.8" end  -- short: the status line is 40 columns
  return browser.open(url)
end

-- the address of link n of a page. When the page was replaced on the card, it is opened again first.
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

local function openPage(url)
  status = "loading " .. domainOf(url) .. "..."
  showMessage(status)
  local page, err = fetchPage(url)
  if not page then
    status = "cannot open: " .. tostring(err)
    return
  end
  status = page.truncated and "page cut at 128 KB" or nil
  push(view)
  view = { kind = "page", url = url, page = page, top = 1 }
  if page.lines == 0 then status = "this page has no text" end
end

-- the lines on the screen, read from the card; a page that was replaced there is opened again
local function pageLines(v)
  local lines = browser.lines(v.page, v.top, TEXT_ROWS)
  if lines then return lines end
  local page, err = fetchPage(v.url)
  if not page then
    status = "cannot reopen: " .. tostring(err)
    return {}
  end
  v.page = page
  return browser.lines(page, v.top, TEXT_ROWS) or {}
end

local function clampPage()
  local maxTop = math.max(1, view.page.lines - TEXT_ROWS + 1)
  if view.top > maxTop then view.top = maxTop end
  if view.top < 1 then view.top = 1 end
end

---------------------------------------------------------------- search

local function doSearch(query)
  showMessage("searching DuckDuckGo...")
  local items, err = search.web(query)
  if not items then
    status = "search failed: " .. tostring(err)
    return
  end
  status = #items == 0 and "no results for this search" or nil
  push(view)
  view = { kind = "results", query = query, items = items, sel = 1, top = 1 }
end

local function clampResults()
  local v = view
  if v.sel < 1 then v.sel = 1 end
  if v.sel > #v.items then v.sel = #v.items end
  if v.sel < v.top then v.top = v.sel end
  if v.sel >= v.top + 4 then v.top = v.sel - 3 end
  if v.top < 1 then v.top = 1 end
end

---------------------------------------------------------------- pictures

local function openImages(query)
  showMessage("searching pictures...")
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
  -- pictures go on top of the text, cell by cell. Each one comes from the card (downloaded the first time).
  -- A picture that failed is not tried again on every screen.
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
  term.text(0, 0, (domainOf(v.url) .. "  " .. (v.url:match("^https?://[^/]+(.*)$") or "")):sub(1, COLS), "white")
  for row, line in ipairs(pageLines(v)) do
    term.text(0, row, line, "text")
  end
  local last = math.min(v.top + TEXT_ROWS - 1, v.page.lines)
  local bottom
  if linkInput then
    bottom = "link number: " .. linkInput .. "_  (enter opens)"
  elseif status then
    bottom = status
  else
    bottom = string.format("%d-%d/%d  links %d  l b / q", v.top, last, v.page.lines, v.page.links)
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
      if n then
        local target, err = linkTarget(view, n)
        if target then openPage(target) else status = tostring(err) end
      else
        status = "no link"
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
  elseif k == "G" then view.top = view.page.lines; clampPage()
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
  expect(domainOf("https://a.org/x/y.html"), "a.org")
  expect(domainOf("a.org"), "a.org")
  expect(withSize("https://th.bing.com/th?id=1&w=217&h=180&c=7", 112, 84),
    "https://th.bing.com/th?id=1&w=112&h=84&c=7")
  expect(withSize("https://th.bing.com/th?id=1", 140, 105), "https://th.bing.com/th?id=1&w=140&h=105&c=7")
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

-- the screen is drawn when something changed (a key, a result), not on every loop: drawing reads the pictures
local dirty = true
local quit = false
while not quit do
  local k = key.poll()
  while k do
    dirty = true
    local action = handleKey(k)
    if action == "quit" then quit = true break end
    k = key.poll()
  end
  if quit then break end
  if dirty then
    draw()
    dirty = false
  else
    term.flush()  -- nothing changed: the flush only keeps the input and the screen alive
  end
  sys.sleep(50)
end
term.fullscreen(false)
