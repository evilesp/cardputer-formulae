#!lua
-- weatherForecast: the weather now and for the next days, from Open-Meteo.com. No API key, no sign-up.
--   weatherForecast                         the saved location (set with saveMyLocation)
--   weatherForecast CITY                    e.g. weatherForecast Krakow   or   weatherForecast Paris, France
--   weatherForecast LAT LON                 e.g. weatherForecast 52.23 21.01
--   weatherForecast saveMyLocation CITY     saves the place for the next runs (also: saveMyLocation LAT LON)
--   weatherForecast saveMyLocation          shows the saved place
-- Weather data: Open-Meteo.com, CC BY 4.0. The free API is meant for non-commercial use.

local API_FORECAST = "https://api.open-meteo.com/v1/forecast"
local API_GEOCODE = "https://geocoding-api.open-meteo.com/v1/search"
local SAVED = "/home/user/.weather"
local USAGE = "usage: weatherForecast [CITY | LAT LON | saveMyLocation CITY | saveMyLocation LAT LON]"
local DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

local function fail(msg)
  print("weatherForecast: " .. msg)
end

-- A small JSON reader for the Open-Meteo answers. It returns nil when the text is not JSON.
local function decode(text)
  local pos = 1
  local value

  local function skip()
    pos = text:find("[^ \t\r\n]", pos) or (#text + 1)
  end

  local function readString()  -- pos is at the opening quote
    local out, i = {}, pos + 1
    while true do
      local j = text:find('["\\]', i)
      if not j then return nil end
      out[#out + 1] = text:sub(i, j - 1)
      if text:sub(j, j) == '"' then
        pos = j + 1
        return table.concat(out)
      end
      local e = text:sub(j + 1, j + 1)
      if e == "u" then
        out[#out + 1] = "?"
        i = j + 6
      else
        out[#out + 1] = (e == "n" and "\n") or (e == "t" and "\t") or e
        i = j + 2
      end
    end
  end

  -- returns ok, value; a null is ok with no value
  value = function()
    skip()
    local c = text:sub(pos, pos)
    if c == "{" then
      local obj = {}
      pos = pos + 1
      skip()
      if text:sub(pos, pos) == "}" then
        pos = pos + 1
        return true, obj
      end
      while true do
        skip()
        if text:sub(pos, pos) ~= '"' then return false end
        local key = readString()
        if not key then return false end
        skip()
        if text:sub(pos, pos) ~= ":" then return false end
        pos = pos + 1
        local ok, v = value()
        if not ok then return false end
        obj[key] = v
        skip()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return true, obj end
        if d ~= "," then return false end
      end
    elseif c == "[" then
      local arr, n = {}, 0
      pos = pos + 1
      skip()
      if text:sub(pos, pos) == "]" then
        pos = pos + 1
        return true, arr
      end
      while true do
        local ok, v = value()
        if not ok then return false end
        n = n + 1
        arr[n] = v
        skip()
        local d = text:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return true, arr end
        if d ~= "," then return false end
      end
    elseif c == '"' then
      local s = readString()
      if s == nil then return false end
      return true, s
    elseif text:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true, true
    elseif text:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return true, false
    elseif text:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return true, nil
    end
    local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if not num then return false end
    pos = pos + #num
    return true, tonumber(num)
  end

  local ok, v = value()
  if ok then return v end
  return nil
end

-- The text of a WMO weather code, as Open-Meteo gives it
local function describe(code)
  if code == 0 then return "Clear" end
  if code == 1 then return "Mostly clear" end
  if code == 2 then return "Partly cloudy" end
  if code == 3 then return "Overcast" end
  if code == 45 or code == 48 then return "Fog" end
  if code >= 51 and code <= 55 then return "Drizzle" end
  if code == 56 or code == 57 then return "Freezing drizzle" end
  if code >= 61 and code <= 65 then return "Rain" end
  if code == 66 or code == 67 then return "Freezing rain" end
  if code >= 71 and code <= 75 then return "Snow" end
  if code == 77 then return "Snow grains" end
  if code >= 80 and code <= 82 then return "Rain showers" end
  if code == 85 or code == 86 then return "Snow showers" end
  if code == 95 then return "Thunderstorm" end
  if code == 96 or code == 99 then return "Thunderstorm, hail" end
  return "Code " .. tostring(code)
end

-- 0 = Sunday (Sakamoto's method)
local function weekday(y, m, d)
  local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
  if m < 3 then y = y - 1 end
  return (y + y // 4 - y // 100 + y // 400 + t[m] + d) % 7
end

-- Characters other than letters, digits and - . _ ~ become %XX (the city name can hold accents)
local function encodeQuery(s)
  return (s:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function fetchJson(url)
  local status, body = net.fetch(url, 16384)
  if not status then return nil, "no answer from Open-Meteo: " .. tostring(body) end
  if status ~= 200 then return nil, "Open-Meteo answered with HTTP " .. status end
  local data = decode(body)
  if type(data) ~= "table" then return nil, "the answer is not readable" end
  return data
end

-- Among the matches the first populated place wins (PPL, PPLC, PPLA...); a park or an airport only if nothing else
local function pickPlace(results)
  local first = nil
  for _, r in ipairs(results) do
    first = first or r
    if type(r.feature_code) == "string" and r.feature_code:sub(1, 3) == "PPL" then return r end
  end
  return first
end

local function findPlace(query)
  local url = API_GEOCODE .. "?name=" .. encodeQuery(query) .. "&count=10&language=pl&format=json"
  local data, err = fetchJson(url)
  if not data then return nil, err end
  local r = type(data.results) == "table" and pickPlace(data.results) or nil
  if not r or type(r.latitude) ~= "number" or type(r.longitude) ~= "number" then
    return nil, "no place called '" .. query .. "' (try with a country: Paris, France, or use LAT LON)"
  end
  local name = r.name or query
  if r.country then name = name .. ", " .. r.country end
  return { name = name, lat = r.latitude, lon = r.longitude }
end

-- The place from the arguments starting at `from`: LAT LON, or the words of a city name
local function placeFromArgs(from)
  local count = #arg - from + 1
  if count < 1 then return nil, "give a city or LAT LON" end
  if count == 2 then
    local lat, lon = tonumber(arg[from]), tonumber(arg[from + 1])
    if lat and lon then
      if lat < -90 or lat > 90 or lon < -180 or lon > 180 then
        return nil, "the coordinates are out of range (latitude -90..90, longitude -180..180)"
      end
      return { name = string.format("%.2f, %.2f", lat, lon), lat = lat, lon = lon }
    end
  end
  local words = {}
  for i = from, #arg do words[#words + 1] = arg[i] end
  return findPlace(table.concat(words, " "))
end

local function loadSaved()
  local text = fs.read(SAVED)
  if not text then return nil end
  local place = {}
  for line in text:gmatch("[^\n]+") do
    local k, v = line:match("^(%a+)=(.*)$")
    if k then place[k] = v end
  end
  place.lat, place.lon = tonumber(place.lat or ""), tonumber(place.lon or "")
  if not place.name or not place.lat or not place.lon then return nil end
  return place
end

local function saveLocation(place)
  local text = string.format("name=%s\nlat=%.5f\nlon=%.5f\n", place.name, place.lat, place.lon)
  local ok, err = fs.write(SAVED, text)
  if not ok then return nil, tostring(err) end
  return true
end

-- Formats a number of a daily or current value, or "-" when the answer has none
local function num(v, fmt)
  if type(v) ~= "number" then return "-" end
  return string.format(fmt, v)
end

local function show(place, data)
  local cur = data.current
  if type(cur) ~= "table" then
    fail("the answer has no current weather")
    return
  end
  print(place.name)
  print(string.format("%.2f, %.2f", place.lat, place.lon))
  print("")
  local night = cur.is_day == 0 and " (night)" or ""
  print(string.format("Now: %s C (feels %s C), %s%s", num(cur.temperature_2m, "%.1f"),
    num(cur.apparent_temperature, "%.1f"), describe(cur.weather_code or -1), night))
  print(string.format("Wind %s km/h, humidity %s%%", num(cur.wind_speed_10m, "%.0f"),
    num(cur.relative_humidity_2m, "%.0f")))
  print("")

  local d = data.daily
  if type(d) == "table" and type(d.time) == "table" then
    for i, date in ipairs(d.time) do
      local y, m, day = nil, nil, nil
      if type(date) == "string" then y, m, day = date:match("^(%d+)-(%d+)-(%d+)$") end
      local label = "Today"
      if i == 2 then label = "Tomorrow"
      elseif i > 2 and y then label = DAYS[weekday(tonumber(y), tonumber(m), tonumber(day)) + 1] end
      local code = type(d.weather_code) == "table" and d.weather_code[i] or -1
      print(string.format("%-9s%-15s%s/%s C %s mm", label, describe(code):sub(1, 15),
        num(type(d.temperature_2m_min) == "table" and d.temperature_2m_min[i] or nil, "%2.0f"),
        num(type(d.temperature_2m_max) == "table" and d.temperature_2m_max[i] or nil, "%2.0f"),
        num(type(d.precipitation_sum) == "table" and d.precipitation_sum[i] or nil, "%4.1f")))
    end
    local rise = type(d.sunrise) == "table" and type(d.sunrise[1]) == "string" and d.sunrise[1]:sub(12, 16) or "-"
    local set = type(d.sunset) == "table" and type(d.sunset[1]) == "string" and d.sunset[1]:sub(12, 16) or "-"
    print("Sunrise " .. rise .. ", sunset " .. set)
  end
  print("Weather data: Open-Meteo.com (CC BY 4.0)")
end

local function forecast(place)
  local url = API_FORECAST .. "?latitude=" .. string.format("%.4f", place.lat) .. "&longitude=" ..
    string.format("%.4f", place.lon) ..
    "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m" ..
    "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_sum" ..
    "&timezone=auto&forecast_days=3"
  local data, err = fetchJson(url)
  if not data then return fail(err) end
  show(place, data)
end

if arg[1] == "help" or arg[1] == "-h" or arg[1] == "--help" then
  print(USAGE)
  return
end

if arg[1] == "saveMyLocation" then
  if #arg == 1 then
    local saved = loadSaved()
    if saved then print("saved: " .. saved.name .. " (" .. string.format("%.2f, %.2f", saved.lat, saved.lon) .. ")")
    else print("no saved location yet") end
    return
  end
  local place, err = placeFromArgs(2)
  if not place then return fail(err) end
  local ok, serr = saveLocation(place)
  if not ok then return fail("cannot save the location: " .. serr) end
  print("saved: " .. place.name)
  return
end

if not net.connected() then
  fail("no WiFi connection (wifi connect SSID PASS)")
  return
end

if #arg == 0 then
  local place = loadSaved()
  if not place then
    print(USAGE)
    print("no saved location yet: weatherForecast saveMyLocation CITY")
    return
  end
  return forecast(place)
end

local place, err = placeFromArgs(1)
if not place then return fail(err) end
forecast(place)
