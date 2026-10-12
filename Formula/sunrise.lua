#!lua
-- sunrise: when the sun rises and sets, the solar noon and the length of the day, worked out on the Cardputer (no
-- network). The times are in the clock's time zone once the clock is set (WiFi), else in UTC.
-- usage: sunrise [LATITUDE LONGITUDE] [YYYY-MM-DD]     (Warsaw and today when left out; south and west are negative)
--   sunrise 50.06 19.94          Krakow today
--   sunrise 52.23 21.01 2026-12-21
-- Run it with --selftest to check the sums.

local DEFAULT_LAT, DEFAULT_LON = 52.23, 21.01
local rad, deg = math.pi / 180, 180 / math.pi

-- days since 1970-01-01 of a date (the civil calendar, no table of months)
local function daysOf(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = y // 400
  local yoe = y - era * 400
  local doy = (153 * ((m + 9) % 12) + 2) // 5 + d - 1
  return era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy - 719468
end

-- sunrise, sunset and noon as seconds since 1970 (UTC). rise and set are nil with "day" (the sun never sets) or "night"
-- (it never rises). The sunrise equation: the sun's mean anomaly, its ecliptic longitude, the declination, then the
-- hour angle where the top of the sun touches the horizon (-0.833 degrees: the refraction and the sun's radius).
local function sunTimes(y, m, d, lat, lon)
  local jdNoon = daysOf(y, m, d) + 2440588.0  -- the Julian day at 12:00 UTC
  local n = math.floor(jdNoon - 2451545.0 + 0.0008 + 0.5)
  local jStar = n - lon / 360
  local M = (357.5291 + 0.98560028 * jStar) % 360
  local C = 1.9148 * math.sin(M * rad) + 0.02 * math.sin(2 * M * rad) + 0.0003 * math.sin(3 * M * rad)
  local lambda = (M + C + 180 + 102.9372) % 360
  local transit = 2451545.0 + jStar + 0.0053 * math.sin(M * rad) - 0.0069 * math.sin(2 * lambda * rad)
  local sinDec = math.sin(lambda * rad) * math.sin(23.4397 * rad)
  local cosDec = math.cos(math.asin(sinDec))
  local cosH = (math.sin(-0.833 * rad) - math.sin(lat * rad) * sinDec) / (math.cos(lat * rad) * cosDec)
  local function unix(jd) return math.floor((jd - 2440587.5) * 86400 + 0.5) end
  if cosH > 1 then return nil, nil, unix(transit), "night" end
  if cosH < -1 then return nil, nil, unix(transit), "day" end
  local h = math.acos(cosH) * deg
  return unix(transit - h / 360), unix(transit + h / 360), unix(transit)
end

-- "+0200" -> 7200 seconds
local function offsetOf(z)
  local sign, hh, mm = (z or ""):match("^([%+%-])(%d%d)(%d%d)$")
  if not sign then return nil end
  local s = tonumber(hh) * 3600 + tonumber(mm) * 60
  return sign == "-" and -s or s
end

local function hhmm(t, offset)
  local s = (t + offset) % 86400
  return string.format("%02d:%02d", s // 3600, (s % 3600) // 60)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(daysOf(1970, 1, 1) == 0 and daysOf(2000, 3, 1) == 11017, "dates to days")
  -- Warsaw on 2026-10-12: 04:56 and 15:48 UTC by the NOAA calculator (06:56 and 17:48 summer time)
  local rise, set, noon = sunTimes(2026, 10, 12, 52.23, 21.01)
  local function near(t, h, m) return t and math.abs((t % 86400) - (h * 3600 + m * 60)) <= 180 end
  check(near(rise, 4, 56), "Warsaw sunrise in October (" .. (rise and hhmm(rise, 0) or "none") .. ")")
  check(near(set, 15, 48), "Warsaw sunset in October (" .. (set and hhmm(set, 0) or "none") .. ")")
  check(near(noon, 10, 22), "Warsaw solar noon")
  local _, _, _, polar = sunTimes(2026, 12, 21, 78.22, 15.65)
  check(polar == "night", "Svalbard has polar night at Christmas")
  _, _, _, polar = sunTimes(2026, 6, 21, 78.22, 15.65)
  check(polar == "day", "and the midnight sun in June")
  check(offsetOf("+0200") == 7200 and offsetOf("-0330") == -12600 and offsetOf("x") == nil, "time zone offsets")
  if failed == 0 then print("selftest ok") end
  return
end

local lat, lon, dateArg = DEFAULT_LAT, DEFAULT_LON, nil
local a = { table.unpack(arg) }
if a[1] and a[1]:match("^%d%d%d%d%-%d%d%-%d%d$") then dateArg = table.remove(a, 1) end
if #a >= 2 then
  lat, lon = tonumber(a[1]), tonumber(a[2])
  dateArg = dateArg or a[3]
elseif #a == 1 then
  lat = nil
end
if not lat or not lon or lat < -90 or lat > 90 or lon < -180 or lon > 180 then
  print("usage: sunrise [LATITUDE LONGITUDE] [YYYY-MM-DD]   (sunrise 50.06 19.94)")
  return
end

local y, m, d
if dateArg then
  y, m, d = dateArg:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not y or m < 1 or m > 12 or d < 1 or d > 31 then
    print("sunrise: the date is YYYY-MM-DD")
    return
  end
else
  local today = sys.date("%Y-%m-%d")
  if not today then
    print("sunrise: the clock is not set yet (connect WiFi), give the date: sunrise 52.23 21.01 2026-10-12")
    return
  end
  y, m, d = today:match("^(%d+)%-(%d+)%-(%d+)$")
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
end

local offset = offsetOf(sys.date("%z"))
local zone = offset and (sys.date("%Z") or "local") or "UTC"
offset = offset or 0

local rise, set, noon, polar = sunTimes(y, m, d, lat, lon)
print(string.format("%04d-%02d-%02d at %.2f, %.2f (%s)", y, m, d, lat, lon, zone))
if polar == "day" then
  print("the sun does not set (midnight sun)")
elseif polar == "night" then
  print("the sun does not rise (polar night)")
else
  local length = set - rise
  print("sunrise     " .. hhmm(rise, offset))
  print("solar noon  " .. hhmm(noon, offset))
  print("sunset      " .. hhmm(set, offset))
  print(string.format("day length  %d h %02d min", length // 3600, (length % 3600) // 60))
end
