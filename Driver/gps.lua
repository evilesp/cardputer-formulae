#!lua
-- gps: a driver for GPS modules that send NMEA sentences on a UART (NEO-6M, NEO-7M, NEO-8M, GT-U7 and similar).
-- A driver is not a program: brew installs it into /usr/local/lib/drivers, and an app loads it with driver.load("gps").
--   local gps = driver.load("gps")
--   local port = uart.open{ rx = 1, tx = 2, baud = 9600 }   -- rx: the pin the module's TX is wired to
--   local reader = gps.new(port)
--   local fix = reader:poll()      -- call it often; it reads what came in and returns the newest fix
-- A fix has: valid (true with a position), lat and lon (degrees, minus for S and W), alt (metres), sats, quality
-- (0 no fix, 1 GPS, 2 DGPS), time ("hh:mm:ss" UTC), speed (km/h) and course (degrees). Fields are nil until known.
-- The app closes the port when it ends; the driver keeps nothing outside the app.
-- Run it as a script with --selftest to check the parser on the sentences of real modules.

local M = {}

-- An NMEA sentence is $TALKER,field,...*hh, where hh is the XOR of the characters between $ and *
function M.checksumOk(sentence)
  local body, hex = sentence:match("^%$([^*]*)%*(%x%x)")
  if not body then return false end
  local x = 0
  for i = 1, #body do x = x ~ body:byte(i) end
  return x == tonumber(hex, 16)
end

-- ddmm.mmmm (latitude) or dddmm.mmmm (longitude) with N, S, E or W, as decimal degrees
local function degrees(value, hemisphere)
  local v = tonumber(value)
  if not v then return nil end
  local whole = math.floor(v / 100)
  local deg = whole + (v - whole * 100) / 60
  if hemisphere == "S" or hemisphere == "W" then deg = -deg end
  return deg
end

-- hhmmss.sss (UTC) as hh:mm:ss
local function clock(text)
  if not text or #text < 6 then return nil end
  return text:sub(1, 2) .. ":" .. text:sub(3, 4) .. ":" .. text:sub(5, 6)
end

-- One sentence as a table: GGA (position, altitude, quality) or RMC (time, speed, course). Nil for anything else, and
-- for a sentence whose checksum is wrong.
function M.parse(sentence)
  if not M.checksumOk(sentence) then return nil end
  local body = sentence:match("^%$([^*]*)")
  local f = {}
  for field in (body .. ","):gmatch("([^,]*),") do f[#f + 1] = field end
  local kind = f[1]:sub(3)  -- GPGGA -> GGA, GNRMC -> RMC
  if kind == "GGA" then
    return {
      kind = "GGA", time = clock(f[2]), lat = degrees(f[3], f[4]), lon = degrees(f[5], f[6]),
      quality = tonumber(f[7]) or 0, sats = tonumber(f[8]), alt = tonumber(f[10]),
    }
  elseif kind == "RMC" then
    local knots = tonumber(f[8])
    return {
      kind = "RMC", time = clock(f[2]), valid = f[3] == "A",
      speed = knots and knots * 1.852 or nil, course = tonumber(f[9]),
    }
  end
  return nil
end

-- The reader keeps the newest values: GGA gives the position, altitude and quality, RMC the time, speed and course.
function M.new(port)
  local reader = { port = port, buffer = "", fix = { valid = false } }

  function reader:apply(s)
    local fix = self.fix
    if s.kind == "GGA" then
      fix.lat, fix.lon = s.lat, s.lon
      fix.quality, fix.sats, fix.alt = s.quality, s.sats, s.alt
      fix.valid = s.quality > 0 and s.lat ~= nil
      fix.time = s.time or fix.time
    else
      fix.time = s.time or fix.time
      fix.speed, fix.course = s.speed, s.course
    end
  end

  -- reads what the module sent since the last call and returns the fix
  function reader:poll()
    local chunk = self.port:read(256)
    if chunk ~= "" then self.buffer = self.buffer .. chunk end
    while true do
      local nl = self.buffer:find("\n", 1, true)
      if not nl then break end
      local line = self.buffer:sub(1, nl - 1):gsub("\r$", "")
      self.buffer = self.buffer:sub(nl + 1)
      local s = M.parse(line)
      if s then self:apply(s) end
    end
    if #self.buffer > 512 then self.buffer = "" end  -- no line end for a long time: noise, not a sentence
    return self.fix
  end

  return reader
end

if arg and arg[1] == "--selftest" then
  local checks = 0
  local function expect(got, want)
    checks = checks + 1
    if got ~= want then error(string.format("check %d: got %s, want %s", checks, tostring(got), tostring(want))) end
  end
  local function near(got, want, tolerance)
    checks = checks + 1
    if not got or math.abs(got - want) > tolerance then
      error(string.format("check %d: got %s, want %s", checks, tostring(got), tostring(want)))
    end
  end

  expect(M.checksumOk("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47"), true)
  expect(M.checksumOk("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*48"), false)
  expect(M.checksumOk("no sentence"), false)

  local gga = M.parse("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47")
  expect(gga.kind, "GGA")
  expect(gga.time, "12:35:19")
  near(gga.lat, 48.1173, 0.0001)
  near(gga.lon, 11.5166667, 0.0001)
  expect(gga.quality, 1)
  expect(gga.sats, 8)
  expect(gga.alt, 545.4)

  local south = M.parse("$GPGGA,123519,3352.000,S,15112.000,W,1,08,0.9,10.0,M,46.9,M,,*7A")
  near(south.lat, -33.8666667, 0.0001)
  near(south.lon, -151.2, 0.0001)

  local rmc = M.parse("$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A")
  expect(rmc.kind, "RMC")
  expect(rmc.valid, true)
  near(rmc.speed, 41.4848, 0.001)
  expect(rmc.course, 84.4)

  expect(M.parse("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*48"), nil)  -- bad checksum
  expect(M.parse("$GPGSV,1,1,00*79"), nil)  -- a sentence the driver does not use

  -- a reader gets the same fix from a port that delivers the sentences in pieces
  local pieces = {
    "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47\r\n$GPRMC,1235",
    "19,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A\r\n",
  }
  local n = 0
  local port = { read = function(self, max) n = n + 1; return pieces[n] or "" end }
  local reader = M.new(port)
  reader:poll()
  local fix = reader:poll()
  expect(fix.valid, true)
  near(fix.lat, 48.1173, 0.0001)
  near(fix.speed, 41.4848, 0.001)
  expect(fix.time, "12:35:19")

  print(string.format("selftest ok (%d checks)", checks))
  return
end

return M
