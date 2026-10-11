#!lua
-- gpsmap: draws the track of a GPS module on the screen: the places you have been as a line, the present position as a
-- dot, and the distance walked. The map fits the track and keeps north up. c clears the track, ctrl-q quits. The module's TX
-- goes to the pin RX (given first), its RX to the pin TX (-1 when it is not wired back).
--   gpsmap RX TX [BAUD]        e.g. gpsmap 1 2      (BAUD 9600 by default)
-- A first fix can take a few minutes outdoors. Needs the packages gps and ui (brew install gps ui) and firmware v0.1.0.13.
-- Run it with --selftest to check the distance and the map scale.

-- the distance in metres between two points on the Earth (the haversine formula)
local function distance(lat1, lon1, lat2, lon2)
  local r = 6371000
  local p1, p2 = math.rad(lat1), math.rad(lat2)
  local dp, dl = math.rad(lat2 - lat1), math.rad(lon2 - lon1)
  local a = math.sin(dp / 2) ^ 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ^ 2
  return 2 * r * math.asin(math.min(1, math.sqrt(a)))
end

-- the pixel position of every point of the track in a box of w x h pixels (with a margin); north is up, and one metre is
-- the same on both axes. Returns the list of { x, y }.
local function project(points, w, h, margin)
  if #points == 0 then return {} end
  local minLat, maxLat, minLon, maxLon = points[1].lat, points[1].lat, points[1].lon, points[1].lon
  for _, p in ipairs(points) do
    minLat, maxLat = math.min(minLat, p.lat), math.max(maxLat, p.lat)
    minLon, maxLon = math.min(minLon, p.lon), math.max(maxLon, p.lon)
  end
  local midLat = (minLat + maxLat) / 2
  local kx = math.cos(math.rad(midLat))  -- a degree of longitude is shorter away from the equator
  local spanX, spanY = math.max((maxLon - minLon) * kx, 1e-6), math.max(maxLat - minLat, 1e-6)
  local scale = math.min((w - 2 * margin) / spanX, (h - 2 * margin) / spanY)
  local out = {}
  for i, p in ipairs(points) do
    out[i] = {
      x = math.floor(w / 2 + ((p.lon - (minLon + maxLon) / 2) * kx) * scale + 0.5),
      y = math.floor(h / 2 - (p.lat - midLat) * scale + 0.5),
    }
  end
  return out
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(math.abs(distance(0, 0, 0, 1) - 111195) < 100, "a degree of longitude on the equator is about 111 km")
  check(math.abs(distance(0, 0, 1, 0) - 111195) < 100, "a degree of latitude is about 111 km")
  check(distance(48.1, 11.5, 48.1, 11.5) == 0, "no distance from a point to itself")
  check(math.abs(distance(52.2297, 21.0122, 50.0647, 19.9450) - 252000) < 3000, "Warsaw to Krakow is about 252 km")
  local pts = project({ { lat = 10, lon = 20 }, { lat = 10.001, lon = 20 } }, 200, 100, 10)
  check(pts[1].x == 100 and pts[2].x == 100 and pts[2].y < pts[1].y, "a track going north goes up the screen")
  pts = project({ { lat = 0, lon = 0 }, { lat = 0, lon = 0.001 } }, 200, 100, 10)
  check(pts[2].x > pts[1].x and pts[1].y == pts[2].y, "a track going east goes right")
  check(pts[1].x >= 10 and pts[2].x <= 190, "the track stays inside the margin")
  check(#project({}, 200, 100, 10) == 0, "no points, no map")
  pts = project({ { lat = 5, lon = 5 } }, 200, 100, 10)
  check(pts[1].x == 100 and pts[1].y == 50, "one point is in the middle")
  if failed == 0 then print("selftest ok") end
  return
end

local USAGE = "usage: gpsmap RX TX [BAUD]   e.g. gpsmap 1 2   (TX -1 if the module is not wired back)"
if not gfx then
  print("gpsmap needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not uart or not driver then
  print("gpsmap: this firmware cannot open a UART, update to v0.1.0.10(beta) or newer")
  return
end
local rx, tx = tonumber(arg[1] or ""), tonumber(arg[2] or "")
local baud = tonumber(arg[3] or "") or 9600
if not rx or not tx or rx ~= math.floor(rx) or tx ~= math.floor(tx) then
  print(USAGE)
  return
end
local gps, gerr = driver.load("gps")
if not gps then
  print("gpsmap: " .. tostring(gerr))
  return
end
local ui, uerr = driver.load("ui", true)
if not ui then
  print("gpsmap: " .. tostring(uerr))
  return
end
local port, perr = uart.open{ rx = rx, tx = tx, baud = math.floor(baud) }
if not port then
  print("gpsmap: " .. tostring(perr))
  return
end
local reader = gps.new(port)

local W, H = 240, 135
local track, walked, fix = {}, 0, {}

local function draw()
  gfx.clear(0x0a0c14)
  local mapH = H - 24
  local pts = project(track, W, mapH, 14)
  for i = 2, #pts do gfx.line(pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y, 0x60c8ff) end
  if #pts > 0 then
    local last = pts[#pts]
    gfx.disc(last.x, last.y, 3, 0xff5050)
    gfx.disc(pts[1].x, pts[1].y, 2, 0x60e060)
  else
    ui.center(50, "waiting for a position...", 0xffe060, 1)
  end
  gfx.hline(0, W - 1, mapH, 0x3a4260)
  if fix.lat then
    ui.label(4, mapH + 4, string.format("lat %.5f  lon %.5f", fix.lat, fix.lon), 0xe8ecf4)
  else
    ui.label(4, mapH + 4, "no fix yet", 0x8a94aa)
  end
  ui.label(4, mapH + 14, string.format("sats %s   %.0f m walked   c clear", tostring(fix.sats or "-"), walked), 0x8a94aa)
  gfx.flush()
end

local function addPoint()
  if not fix.lat then return end
  local last = track[#track]
  if not last then
    track[1] = { lat = fix.lat, lon = fix.lon }
    return
  end
  local d = distance(last.lat, last.lon, fix.lat, fix.lon)
  if d >= 2 then
    track[#track + 1] = { lat = fix.lat, lon = fix.lon }
    walked = walked + d
    if #track > 300 then table.remove(track, 1) end
  end
end

local w, h = ui.open()
if not w then
  port:close()
  print("gpsmap: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    local f = reader:poll()
    if f then fix = f end
    addPoint()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "c" then track, walked = {}, 0 end
      k = key.poll()
    end
    draw()
    sys.sleep(200)
  end
end)
port:close()
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("gpsmap: " .. tostring(problem)) end
