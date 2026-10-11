#!lua
-- iss: where the International Space Station is now, on a map of the world. The position comes from open-notify.org
-- (no key). It is refreshed every 15 seconds; r refreshes now, q quits. It needs WiFi (wifi connect SSID PASS).
-- The map is a plain grid: left is 180 degrees west, right is 180 degrees east, the top is the North Pole.

local COLS, ROWS = term.size()
local URL = "http://api.open-notify.org/iss-now.json"
local REFRESH_MS = 15000
local MAP_TOP = 2                 -- the map's top border row
local MAP_IN = ROWS - 8           -- the rows inside the map border

-- the answer holds "latitude": "35.7239" and "longitude": "-14.2040"
local function parse(body)
  local lat = body:match('"latitude": "([%-%d%.]+)"')
  local lon = body:match('"longitude": "([%-%d%.]+)"')
  if not lat or not lon then return nil end
  return tonumber(lat), tonumber(lon)
end

local function fetch()
  if not net.connected() then return nil, "no WiFi connection (wifi connect SSID PASS)" end
  local status, body = net.fetch(URL, 4096)
  if not status then return nil, tostring(body) end
  if status ~= 200 then return nil, "the server answered " .. status end
  local lat, lon = parse(body)
  if not lat then return nil, "the answer has no position" end
  return { lat = lat, lon = lon, at = sys.date("%H:%M:%S") }
end

local function draw(pos, message)
  term.clear()
  term.text(0, 0, "ISS now", "green")
  local top = string.rep("-", COLS - 2)
  term.text(0, MAP_TOP, "+" .. top .. "+", "dim")
  for row = 1, MAP_IN do
    term.text(0, MAP_TOP + row, "|" .. string.rep(" ", COLS - 2) .. "|", "dim")
  end
  term.text(0, MAP_TOP + MAP_IN + 1, "+" .. top .. "+", "dim")
  if pos then
    local col = math.floor((pos.lon + 180) / 360 * (COLS - 3) + 0.5) + 1
    local row = math.floor((90 - pos.lat) / 180 * (MAP_IN - 1) + 0.5) + 1
    term.text(col, MAP_TOP + row, "O", "green")
    term.text(0, MAP_IN + 4, string.format("lat %.2f   lon %.2f", pos.lat, pos.lon), "text")
    term.text(0, MAP_IN + 5, "updated " .. (pos.at or "(clock not set)"), "dim")
  end
  if message then term.text(0, MAP_IN + 6, message, "warn") end
  term.text(0, ROWS - 1, "r refresh   q quit", "dim")
  term.flush()
end

local pos, message = nil, "fetching the position..."
draw(nil, message)
pos, message = fetch()
if not pos then
  print("iss: " .. tostring(message))
  return
end
local nextAt = sys.millis() + REFRESH_MS

term.fullscreen(true)
local quit = false
while not quit do
  draw(pos, message)
  local k = key.poll()
  while k do
    if k == "q" then quit = true end
    if k == "r" then nextAt = 0 end
    k = key.poll()
  end
  if not quit and sys.millis() >= nextAt then
    -- a failed refresh keeps the last position and says why
    local newPos, err = fetch()
    if newPos then
      pos, message = newPos, nil
    else
      message = err
    end
    nextAt = sys.millis() + REFRESH_MS
  end
  sys.sleep(200)
end
term.fullscreen(false)
