#!lua
-- wikipedia: the start (lead) of a Wikipedia article on the screen, as plain text. No key is needed.
--   wikipedia WORDS           searches the Polish Wikipedia (pl)
--   wikipedia -l en WORDS     searches another language: en, de, fr...
-- Type a search (or give it on the command line) and pick an article with up/down and Enter. Read it with up/down,
-- space, pageup/pagedown, g and G. b goes back, / starts a new search, ctrl-q quits.
-- Only the lead of an article is shown: the whole article is too big for the ADV's RAM. Polish letters are written
-- without their accents, because the screen has no Polish font.

local COLS, ROWS = term.size()
local TEXT_ROWS = ROWS - 3  -- rows 2 to ROWS-2 hold the text; row 0 and 1 are the title, the last row the keys
local LANG = "pl"

-- letters with accents and typographic marks, as the screen shows them (keys are the UTF-8 bytes)
local ASCII = {
  ["\xC4\x85"] = "a", ["\xC4\x87"] = "c", ["\xC4\x99"] = "e", ["\xC5\x82"] = "l",
  ["\xC5\x84"] = "n", ["\xC3\xB3"] = "o", ["\xC5\x9B"] = "s", ["\xC5\xBA"] = "z",
  ["\xC5\xBC"] = "z", ["\xC4\x84"] = "A", ["\xC4\x86"] = "C", ["\xC4\x98"] = "E",
  ["\xC5\x81"] = "L", ["\xC5\x83"] = "N", ["\xC3\x93"] = "O", ["\xC5\x9A"] = "S",
  ["\xC5\xB9"] = "Z", ["\xC5\xBB"] = "Z", ["\xC3\xA9"] = "e", ["\xC3\xA8"] = "e",
  ["\xC3\xAA"] = "e", ["\xC3\xAB"] = "e", ["\xC3\xA1"] = "a", ["\xC3\xA0"] = "a",
  ["\xC3\xA2"] = "a", ["\xC3\xA4"] = "a", ["\xC3\xA5"] = "a", ["\xC3\xAD"] = "i",
  ["\xC3\xBA"] = "u", ["\xC3\xB6"] = "o", ["\xC3\xB4"] = "o", ["\xC3\xBC"] = "u",
  ["\xC3\xBB"] = "u", ["\xC3\x9F"] = "ss", ["\xC3\xA7"] = "c", ["\xC3\xB1"] = "n",
  ["\xC3\x89"] = "E", ["\xC3\x9C"] = "U", ["\xC3\x96"] = "O", ["\xC3\x84"] = "A",
  ["\xE2\x80\x93"] = "-", ["\xE2\x80\x94"] = "-", ["\xE2\x80\x9E"] = '"', ["\xE2\x80\x9D"] = '"',
  ["\xE2\x80\x9C"] = '"', ["\xE2\x80\x99"] = "'", ["\xE2\x80\x98"] = "'", ["\xE2\x80\xA6"] = "...",
  ["\xC2\xA0"] = " ",
}

---------------------------------------------------------------- text

-- percent-escapes a value of a web address
local function urlEncode(s)
  return (s:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- the UTF-8 bytes of a code point
local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)) end
  if cp < 0x10000 then return string.char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F)) end
  return string.char(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
end

local ESCAPES = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }

-- Reads JSON: objects become tables with string keys, arrays become lists. Returns nil when the text is not JSON.
local function jsonDecode(text)
  local pos = 1
  local readValue

  local function skip()
    pos = text:find("[^ \t\r\n]", pos) or (#text + 1)
  end

  local function readString()
    local parts = {}
    pos = pos + 1  -- the opening quote
    while true do
      local stop = text:find('["\\]', pos)
      if not stop then error("unfinished text") end
      parts[#parts + 1] = text:sub(pos, stop - 1)
      if text:sub(stop, stop) == '"' then
        pos = stop + 1
        break
      end
      local e = text:sub(stop + 1, stop + 1)
      if e == "u" then
        local cp = tonumber(text:sub(stop + 2, stop + 5), 16) or 0x3F
        pos = stop + 6
        if cp >= 0xD800 and cp <= 0xDBFF and text:sub(pos, pos + 1) == "\\u" then  -- a pair makes one character
          local low = tonumber(text:sub(pos + 2, pos + 5), 16) or 0
          if low >= 0xDC00 and low <= 0xDFFF then
            cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00)
            pos = pos + 6
          end
        end
        parts[#parts + 1] = utf8char(cp)
      else
        parts[#parts + 1] = ESCAPES[e] or e
        pos = stop + 2
      end
    end
    return table.concat(parts)
  end

  readValue = function()
    skip()
    local c = text:sub(pos, pos)
    if c == "{" then
      local obj = {}
      pos = pos + 1
      skip()
      if text:sub(pos, pos) == "}" then
        pos = pos + 1
        return obj
      end
      while true do
        skip()
        local key = readString()
        skip()
        pos = pos + 1  -- the colon
        obj[key] = readValue()
        skip()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return obj end
        if d ~= "," then error("bad object") end
      end
    elseif c == "[" then
      local list = {}
      pos = pos + 1
      skip()
      if text:sub(pos, pos) == "]" then
        pos = pos + 1
        return list
      end
      while true do
        list[#list + 1] = readValue()
        skip()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return list end
        if d ~= "," then error("bad list") end
      end
    elseif c == '"' then
      return readString()
    end
    local word = text:match("^[%w%.%+%-]+", pos)
    if not word then error("bad value") end
    pos = pos + #word
    if word == "true" then return true end
    if word == "false" then return false end
    if word == "null" then return nil end
    return tonumber(word)
  end

  local ok, result = pcall(readValue)
  if not ok then return nil end
  return result
end

-- the text as the screen shows it: no carriage returns or tabs, accents written as plain letters
local function toScreen(s)
  s = s:gsub("\r", ""):gsub("\t", " ")
  return (s:gsub("[\192-\255][\128-\191]*", function(ch) return ASCII[ch] or "?" end))
end

-- the text as lines of at most width characters, with an empty line between paragraphs
local function wrap(text, width)
  local lines = {}
  for para in (text .. "\n"):gmatch("(.-)\n") do
    para = para:gsub("^%s+", ""):gsub("%s+$", "")
    if para == "" then
      if #lines > 0 and lines[#lines] ~= "" then lines[#lines + 1] = "" end
    else
      local line = ""
      for word in para:gmatch("%S+") do
        while #word > width do  -- a word longer than a line is cut
          if line ~= "" then
            lines[#lines + 1] = line
            line = ""
          end
          lines[#lines + 1] = word:sub(1, width)
          word = word:sub(width + 1)
        end
        if line == "" then
          line = word
        elseif #line + 1 + #word <= width then
          line = line .. " " .. word
        else
          lines[#lines + 1] = line
          line = word
        end
      end
      if line ~= "" then lines[#lines + 1] = line end
    end
  end
  while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
  return lines
end

---------------------------------------------------------------- the Wikipedia API

-- one request to the API of the language; the body of the answer, or nil and the reason
local function apiGet(query)
  local code, body = net.fetch("https://" .. LANG .. ".wikipedia.org/w/api.php?format=json&formatversion=2&" .. query,
    65536)
  if not code then return nil, tostring(body) end
  if code ~= 200 then return nil, "HTTP " .. tostring(code) end
  return body
end

-- the titles of the articles that match the search
local function search(query)
  local body, err = apiGet("action=opensearch&limit=20&namespace=0&search=" .. urlEncode(query))
  if not body then return nil, err end
  local data = jsonDecode(body)
  if type(data) ~= "table" or type(data[2]) ~= "table" then return nil, "the answer was not understood" end
  return data[2]
end

-- the lead (first part) of an article as plain text
local function lead(title)
  local body, err = apiGet("action=query&prop=extracts&explaintext=1&exintro=1&redirects=1&titles=" .. urlEncode(title))
  if not body then return nil, err end
  local data = jsonDecode(body)
  local page = type(data) == "table" and data.query and data.query.pages and data.query.pages[1]
  if type(page) ~= "table" or page.missing then return nil, "no article with this title" end
  return page.extract or ""
end

---------------------------------------------------------------- navigation

local stack = {}
local view = { kind = "search", input = "" }
local status = nil  -- message shown on the bottom row

local function push(v) stack[#stack + 1] = v end
local function pop()
  local v = stack[#stack]
  stack[#stack] = nil
  return v
end

local function showMessage(text, color)
  term.clear()
  term.text(0, 7, text:sub(1, COLS), color or "cyan")
  term.flush()
end

local function doSearch(query)
  showMessage("searching " .. LANG .. ".wikipedia...")
  local titles, err = search(query)
  if not titles then
    status = "search failed: " .. tostring(err)
    return
  end
  status = #titles == 0 and "no articles for this search" or nil
  push(view)
  view = { kind = "results", query = query, items = titles, sel = 1, top = 1 }
end

local function clampResults()
  local v = view
  if v.sel < 1 then v.sel = 1 end
  if v.sel > #v.items then v.sel = #v.items end
  if v.sel < v.top then v.top = v.sel end
  if v.sel >= v.top + TEXT_ROWS then v.top = v.sel - TEXT_ROWS + 1 end
  if v.top < 1 then v.top = 1 end
end

local function openArticle(title)
  showMessage("loading...")
  local text, err = lead(title)
  if not text then
    status = "cannot open: " .. tostring(err)
    return
  end
  local lines = wrap(toScreen(text), COLS)
  if #lines == 0 then lines[1] = "(this article has no lead text)" end
  status = nil
  push(view)
  view = { kind = "article", title = toScreen(title), lines = lines, top = 1 }
end

local function clampArticle()
  local v = view
  local maxTop = math.max(1, #v.lines - TEXT_ROWS + 1)
  if v.top > maxTop then v.top = maxTop end
  if v.top < 1 then v.top = 1 end
end

---------------------------------------------------------------- drawing

local function drawSearch()
  term.text(0, 0, ("Wikipedia (" .. LANG .. ")"):sub(1, COLS), "white")
  term.text(0, 2, ("search: " .. view.input .. "_"):sub(1, COLS), "green")
  term.text(0, 4, "type a search, then Enter", "dim")
  if status then term.text(0, 6, status:sub(1, COLS), "warn") end
  term.text(0, ROWS - 1, "enter search  ctrl-q quit", "dim")
end

local function drawResults()
  local v = view
  term.text(0, 0, ("results for: " .. toScreen(v.query)):sub(1, COLS), "white")
  if #v.items == 0 then term.text(0, 2, (status or "no results"):sub(1, COLS), "warn") end
  for r = 0, TEXT_ROWS - 1 do
    local i = v.top + r
    if v.items[i] then
      local selected = i == v.sel
      term.text(0, 2 + r, ((selected and "> " or "  ") .. toScreen(v.items[i])):sub(1, COLS),
        selected and "white" or "text")
    end
  end
  if status and #v.items > 0 then
    term.text(0, ROWS - 1, status:sub(1, COLS), "warn")
  else
    term.text(0, ROWS - 1, "up/dn pick  enter read  / search  q quit", "dim")
  end
end

local function drawArticle()
  local v = view
  term.text(0, 0, v.title:sub(1, COLS), "white")
  term.text(0, 1, (LANG .. ".wikipedia.org"):sub(1, COLS), "cyan")
  for r = 0, TEXT_ROWS - 1 do
    local line = v.lines[v.top + r]
    if line then term.text(0, 2 + r, line, "text") end
  end
  local last = math.min(v.top + TEXT_ROWS - 1, #v.lines)
  if status then
    term.text(0, ROWS - 1, status:sub(1, COLS), "warn")
  else
    term.text(0, ROWS - 1, string.format("%d-%d/%d  b back  / search  q quit", v.top, last, #v.lines), "dim")
  end
end

local function draw()
  term.clear()
  if view.kind == "search" then drawSearch()
  elseif view.kind == "results" then drawResults()
  else drawArticle() end
  term.flush()
end

---------------------------------------------------------------- keys

local function handleKey(k)
  if k == "ctrl-q" then return "quit" end
  if view.kind == "search" then
    if k == "enter" then
      if view.input ~= "" then
        doSearch(view.input)
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

  if view.kind == "results" then
    local v = view
    if k == "q" then return "quit"
    elseif k == "up" then v.sel = v.sel - 1; clampResults()
    elseif k == "down" then v.sel = v.sel + 1; clampResults()
    elseif k == "pageup" then v.sel = v.sel - TEXT_ROWS; clampResults()
    elseif k == "pagedown" then v.sel = v.sel + TEXT_ROWS; clampResults()
    elseif k == "enter" and #v.items > 0 then openArticle(v.items[v.sel])
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

  -- article
  local v = view
  if k == "q" then return "quit"
  elseif k == "up" then v.top = v.top - 1; clampArticle()
  elseif k == "down" then v.top = v.top + 1; clampArticle()
  elseif k == "pageup" then v.top = v.top - (TEXT_ROWS - 1); clampArticle()
  elseif k == "pagedown" or k == " " then v.top = v.top + (TEXT_ROWS - 1); clampArticle()
  elseif k == "g" then v.top = 1
  elseif k == "G" then v.top = #v.lines; clampArticle()
  elseif k == "/" then
    push(view)
    view = { kind = "search", input = "" }
    status = nil
  elseif k == "b" and #stack > 0 then
    view = pop()
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
  expect(urlEncode("Warszawa x/y"), "Warszawa%20x%2Fy")
  expect(toScreen("Warszawa, miasto sto\xC5\x82\xC4\x85czne"), "Warszawa, miasto stolaczne")
  expect(toScreen("a\xE2\x80\x93b \xE2\x80\x9Eq\xE2\x80\x9D"), 'a-b "q"')
  expect(toScreen("\xE6\xBC\xA2"), "?")
  local data = jsonDecode('{"a":["x\\u0105y","q\\"z"],"b":{"c":null,"d":true,"e":-12.5}}')
  expect(data.a[1], "x\xC4\x85y")
  expect(data.a[2], 'q"z')
  expect(data.b.d, true)
  expect(data.b.e, -12.5)
  expect(jsonDecode("<html>"), nil)
  expect(table.concat(wrap("one two three", 7), "|"), "one two|three")
  expect(table.concat(wrap("a\n\nb", 40), "|"), "a||b")
  expect(table.concat(wrap("abcdefghijk", 4), "|"), "abcd|efgh|ijk")
  print(string.format("selftest ok (%d checks)", checks))
end

if arg[1] == "--selftest" then
  selftest()
  return
end

---------------------------------------------------------------- main

local words = {}
local i = 1
while i <= #arg do
  if arg[i] == "-l" then
    LANG = arg[i + 1] or ""
    if not LANG:match("^%a%a%a?$") then
      print("usage: wikipedia [-l LANG] WORDS   (LANG is a code like pl, en or de)")
      return
    end
    i = i + 2
  else
    words[#words + 1] = arg[i]
    i = i + 1
  end
end

term.fullscreen(true)
if #words > 0 then doSearch(table.concat(words, " ")) end

-- the screen is drawn when something changed (a key, a result), not on every loop
local dirty = true
local quit = false
while not quit do
  local k = key.poll()
  while k do
    dirty = true
    if handleKey(k) == "quit" then
      quit = true
      break
    end
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
