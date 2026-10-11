#!lua
-- rss: the headlines of your feeds. The feed addresses are in /home/user/rss.txt, one per line (RSS or Atom, https or http).
-- The list shows the newest headlines first; w and s move, r downloads again, ctrl-q quits. Only the first 24 KB of a feed
-- are read, which is enough for the latest headlines. Needs the graphics, the ui package and a network connection.
-- Run it with --selftest to check the reading of headlines.

local FILE = "/home/user/rss.txt"
local LIMIT = 24576

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", ["#39"] = "'", nbsp = " " }

-- the text of one headline without its markup: CDATA, tags and the usual entities are taken away
local function plain(text)
  text = text:gsub("<!%[CDATA%[(.-)%]%]>", "%1")
  text = text:gsub("<[^>]*>", "")
  text = text:gsub("&(#?%w+);", function(name)
    if ENTITIES[name] then return ENTITIES[name] end
    local code = name:match("^#(%d+)$")
    if code and tonumber(code) < 128 then return string.char(tonumber(code)) end
    return "?"
  end)
  return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- the headlines in the order they come in the feed: each <item> (RSS) or <entry> (Atom) has a <title>
local function titlesOf(xml)
  local titles = {}
  for block in xml:gmatch("<item[ >].-</item>") do
    local t = block:match("<title[^>]*>(.-)</title>")
    if t then titles[#titles + 1] = plain(t) end
  end
  if #titles == 0 then
    for block in xml:gmatch("<entry[ >].-</entry>") do
      local t = block:match("<title[^>]*>(.-)</title>")
      if t then titles[#titles + 1] = plain(t) end
    end
  end
  return titles
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local rss = '<?xml version="1.0"?><rss><channel><title>News</title>' ..
    '<item><title><![CDATA[Rain &amp; wind]]></title><link>x</link></item>' ..
    '<item><title>Tom &lt;3 cats</title></item></channel></rss>'
  local t = titlesOf(rss)
  check(#t == 2, "two headlines")
  check(t[1] == "Rain & wind" and t[2] == "Tom <3 cats", "CDATA and entities are read")
  local atom = '<feed><entry><title type="text">First  post</title></entry><entry><title>Second</title></entry></feed>'
  local a = titlesOf(atom)
  check(#a == 2 and a[1] == "First post", "Atom entries are read, spaces are made single")
  check(#titlesOf("<html>nothing</html>") == 0, "a page without headlines has none")
  check(plain("&#65;&#x42;") == "A?", "a number entity below 128 is a character")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("rss needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not net.connected() then
  print("rss: no WiFi connection (wifi connect SSID PASS)")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("rss: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local feeds = {}
local headlines = {}
local top = 1
local message = nil

local function loadFeeds()
  feeds = {}
  local text = fs.read(FILE)
  if not text then return end
  for line in text:gmatch("[^\n]+") do
    local url = line:gsub("%s", "")
    if url:match("^https?://") then feeds[#feeds + 1] = url end
  end
end

local function download()
  headlines = {}
  loadFeeds()
  if #feeds == 0 then
    message = "add feed addresses to " .. FILE .. ", one per line"
    return
  end
  message = "downloading..."
  for _, url in ipairs(feeds) do
    local code, body = net.fetch(url, LIMIT)
    if code == 200 and body then
      for _, t in ipairs(titlesOf(body)) do headlines[#headlines + 1] = t end
    else
      headlines[#headlines + 1] = "cannot read " .. url:sub(1, 30) .. " (" .. tostring(code or body) .. ")"
    end
    body = nil
    collectgarbage()
  end
  message = nil
  top = 1
end

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "HEADLINES", 0xe8ecf4)
  ui.label(150, 4, #headlines .. " items", 0x8a94aa)
  for i = 0, 6 do
    local idx = top + i
    local text = headlines[idx]
    if not text then break end
    ui.label(8, 20 + i * 14, idx .. ". " .. text:sub(1, 36), idx == top and 0xffe060 or 0xe8ecf4)
  end
  ui.label(8, H - 10, message or "w s move   r download   ctrl-q quit", message and 0xffe060 or 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("rss: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  download()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "w" then top = math.max(1, top - 1)
      elseif k == "s" then top = math.min(math.max(1, #headlines), top + 1)
      elseif k == "r" then download()
      end
      k = key.poll()
    end
    sys.sleep(80)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("rss: " .. tostring(problem)) end
