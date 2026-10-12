#!lua
-- earthquakes: the latest earthquakes in the world from the USGS feed (no key). Each line has the magnitude, how long ago
-- it was and where. w and s move, enter shows the details of one, r downloads the list again, q quits.
-- usage: earthquakes [MIN_MAGNITUDE]   (4.5 when left out; 2.5 shows many more)
-- Needs WiFi (wifi connect SSID PASS). Run it with --selftest to check the reading of the list.

local COLS, ROWS = term.size()
local LIMIT = 20
local minMag = 4.5

-- splits one CSV line; a field in quotes may hold commas ("12 km E of Town, Country")
local function csvFields(line)
  local out, i, n = {}, 1, #line
  while i <= n + 1 do
    if line:sub(i, i) == '"' then
      local j, parts = i + 1, {}
      while j <= n do
        local ch = line:sub(j, j)
        if ch == '"' then
          if line:sub(j + 1, j + 1) == '"' then
            parts[#parts + 1] = '"'
            j = j + 2
          else
            break
          end
        else
          parts[#parts + 1] = ch
          j = j + 1
        end
      end
      out[#out + 1] = table.concat(parts)
      i = j + 2  -- past the closing quote and the comma
    else
      local comma = line:find(",", i, true) or (n + 1)
      out[#out + 1] = line:sub(i, comma - 1)
      i = comma + 1
    end
  end
  return out
end

-- seconds since 1970 of a UTC date (the days from the civil calendar, no table of months needed)
local function epochOf(y, mo, d, h, mi, s)
  if mo <= 2 then y = y - 1 end
  local era = y // 400
  local yoe = y - era * 400
  local mp = (mo + 9) % 12
  local doy = (153 * mp + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  local days = era * 146097 + doe - 719468
  return days * 86400 + h * 3600 + mi * 60 + s
end

-- the quakes of the USGS CSV answer: { mag, place, depth, lat, lon, time, when } newest first
local function parseQuakes(text)
  local list = {}
  local header = true
  for line in text:gmatch("[^\r\n]+") do
    if header then
      header = false
    else
      local f = csvFields(line)
      local y, mo, d, h, mi, s = (f[1] or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
      local mag = tonumber(f[5])
      if y and mag then
        list[#list + 1] = {
          mag = mag, place = f[14] ~= "" and f[14] or "unknown place", depth = tonumber(f[4]) or 0,
          lat = tonumber(f[2]) or 0, lon = tonumber(f[3]) or 0, time = f[1]:sub(1, 16):gsub("T", " "),
          when = epochOf(tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)),
        }
      end
    end
  end
  return list
end

-- "5 min", "3 h", "2 d"
local function ago(seconds)
  if seconds < 0 then seconds = 0 end
  if seconds < 3600 then return string.format("%d min", seconds // 60) end
  if seconds < 86400 then return string.format("%d h", seconds // 3600) end
  return string.format("%d d", seconds // 86400)
end

-- the plain ASCII of a place name (the screen font has no accents)
local function ascii(s)
  return (s:gsub("[\xC2-\xF4][\x80-\xBF]*", "?"))
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local f = csvFields('a,"b, c",,"say ""hi""",5')
  check(#f == 5 and f[2] == "b, c" and f[3] == "" and f[4] == 'say "hi"' and f[5] == "5", "CSV fields with quotes and commas")
  check(epochOf(1970, 1, 1, 0, 0, 0) == 0 and epochOf(2000, 3, 1, 0, 0, 0) == 951868800, "dates to seconds")
  check(epochOf(2026, 10, 12, 11, 28, 43) == 1791804523, "a date of 2026")
  local sample = "time,latitude,longitude,depth,mag,magType,nst,gap,dmin,rms,net,id,updated,place,type\n" ..
    '2026-10-12T11:28:43.067Z,-9.007,67.5641,10,5.7,mww,95,40,5.091,1.51,us,x,2026,"Mid-Indian Ridge",earthquake\n' ..
    '2026-10-12T08:30:08.695Z,-8.237,128.9661,22.4,4.7,mb,33,123,5.0,0.71,us,y,2026,"219 km E of Lospalos, Timor Leste",earthquake\n'
  local q = parseQuakes(sample)
  check(#q == 2 and q[1].mag == 5.7 and q[2].place == "219 km E of Lospalos, Timor Leste", "the quakes are read")
  check(q[1].time == "2026-10-12 11:28", "the time of a quake")
  check(ago(90) == "1 min" and ago(7200) == "2 h" and ago(200000) == "2 d", "how long ago")
  check(ascii("Ca\xC3\xB1ada") == "Ca?ada", "accents become ?")
  if failed == 0 then print("selftest ok") end
  return
end

if arg[1] then
  minMag = tonumber(arg[1])
  if not minMag or minMag < 0 or minMag > 9 then
    print("usage: earthquakes [MIN_MAGNITUDE]   (0 to 9, 4.5 when left out)")
    return
  end
end
if not net.connected() then
  print("earthquakes: no WiFi connection (wifi connect SSID PASS)")
  return
end

local URL = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=csv&orderby=time&limit=" .. LIMIT ..
  "&minmagnitude=" .. minMag

local function download()
  local code, body = net.fetch(URL, 12288)
  if not code then return nil, tostring(body) end
  if code ~= 200 then return nil, "the server answered " .. code end
  local list = parseQuakes(body)
  if #list == 0 then return nil, "no earthquakes in the answer" end
  return list
end

local function magColor(m)
  if m >= 6 then return "red" elseif m >= 5 then return "yellow" else return "green" end
end

local quakes, message, selected, top, details = {}, "downloading...", 1, 1, false
local LIST_ROWS = ROWS - 3

local function draw()
  term.clear()
  term.text(0, 0, string.format("EARTHQUAKES  M%.1f+  (USGS)", minMag), "cyan")
  local now = sys.time()
  if details and quakes[selected] then
    local q = quakes[selected]
    term.text(0, 2, string.format("magnitude %.1f", q.mag), magColor(q.mag))
    local place = ascii(q.place)
    term.text(0, 4, place:sub(1, COLS), "text")
    if #place > COLS then term.text(0, 5, place:sub(COLS + 1, 2 * COLS), "text") end
    term.text(0, 7, "time  " .. q.time .. " UTC", "text")
    if now > 0 then term.text(0, 8, "      " .. ago(now - q.when) .. " ago", "dim") end
    term.text(0, 9, string.format("depth %.0f km", q.depth), "text")
    term.text(0, 10, string.format("lat %.2f  lon %.2f", q.lat, q.lon), "text")
    term.text(0, ROWS - 1, "enter back   q quit", "dim")
  else
    if selected < top then top = selected end
    if selected > top + LIST_ROWS - 1 then top = selected - LIST_ROWS + 1 end
    for row = 0, LIST_ROWS - 1 do
      local i = top + row
      local q = quakes[i]
      if q then
        local when = now > 0 and ago(now - q.when) or q.time:sub(12, 16)
        local line = string.format("%4.1f %6s %s", q.mag, when, ascii(q.place))
        line = line:sub(1, COLS)
        if i == selected then line = line .. string.rep(" ", COLS - #line) end
        term.text(0, row + 1, line, i == selected and "white" or magColor(q.mag))
        if i == selected then term.text(0, row + 1, ">", "cyan") end
      end
    end
    if message then term.text(0, ROWS - 2, message:sub(1, COLS), "warn") end
    term.text(0, ROWS - 1, "w s move  enter more  r reload  q quit", "dim")
  end
  term.flush()
end

term.fullscreen(true)
draw()
local function reload()
  message = "downloading..."
  draw()
  local list, err = download()
  if list then
    quakes, message = list, nil
    selected, top = math.min(selected, #list), 1
  else
    message = "cannot download: " .. err
  end
end
reload()

local quit = false
while not quit do
  draw()
  local k = key.poll()
  while k do
    if k == "q" or k == "ctrl-q" then quit = true
    elseif k == "w" or k == "up" then selected = math.max(1, selected - 1)
    elseif k == "s" or k == "down" then selected = math.min(math.max(1, #quakes), selected + 1)
    elseif k == "enter" or k == " " then details = not details
    elseif k == "r" then reload()
    end
    k = key.poll()
  end
  sys.sleep(100)
end
term.fullscreen(false)
