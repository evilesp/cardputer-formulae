#!lua
-- moon: the phase of the Moon on a date, worked out on the Cardputer (no network): the name, the age in days, how much
-- of the disc is lit, the next new and full moons, and a drawing of the disc. Today comes from the clock (WiFi). The
-- phase is for noon UTC of the day and the dates of the next moons are in UTC.
-- usage: moon [YYYY-MM-DD]     (today when left out)
--   moon 2024-01-25     a full moon
-- Run it with --selftest to check the sums.

local SYNODIC = 29.530588861                  -- days from one new moon to the next
local EPOCH_NEW = 2451550.09766               -- the new moon of 2000-01-06 as a Julian day (the first of the count)
local NAMES = { "new moon", "waxing crescent", "first quarter", "waxing gibbous",
                "full moon", "waning gibbous", "last quarter", "waning crescent" }
local rad = math.pi / 180

-- days since 1970-01-01 of a date (the civil calendar, no table of months)
local function daysOf(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = y // 400
  local yoe = y - era * 400
  local doy = (153 * ((m + 9) % 12) + 2) // 5 + d - 1
  return era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy - 719468
end

-- the date (year, month, day) of a day number since 1970 (the inverse of daysOf)
local function dateOf(z)
  z = z + 719468
  local era = z // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400
  if m <= 2 then y = y + 1 end
  return y, m, d
end

-- the moment of new moon (half = 0) or full moon (half = 0.5) number k, as a Julian day: the mean moon with the main
-- corrections of Meeus, "Astronomical Algorithms" chapter 49, so the day is right to a few minutes
local function phaseJD(k, half)
  local kk = k + half
  local T = kk / 1236.85
  local E = 1 - 0.002516 * T
  local M = (2.5534 + 29.10535670 * kk) * rad        -- the sun's mean anomaly
  local Mp = (201.5643 + 385.81693528 * kk) * rad    -- the moon's mean anomaly
  local F = (160.7108 + 390.67050284 * kk) * rad     -- the moon's argument of latitude
  local Om = (124.7746 - 1.56375588 * kk) * rad      -- the longitude of the moon's node
  local s = math.sin
  return EPOCH_NEW + SYNODIC * kk + 0.00015437 * T * T
    - 0.40720 * s(Mp) + 0.17241 * E * s(M) + 0.01608 * s(2 * Mp) + 0.01039 * s(2 * F)
    + 0.00739 * E * s(Mp - M) - 0.00514 * E * s(Mp + M) + 0.00208 * E * E * s(2 * M)
    - 0.00111 * s(Mp - 2 * F) - 0.00057 * s(Mp + 2 * F) + 0.00056 * E * s(2 * Mp + M)
    - 0.00042 * s(3 * Mp) + 0.00042 * E * s(M + 2 * F) + 0.00038 * E * s(M - 2 * F)
    - 0.00024 * E * s(2 * Mp - M) - 0.00017 * s(Om)
end

-- the number of the last new moon at or before the Julian day jd
local function lastNew(jd)
  local k = math.floor((jd - EPOCH_NEW) / SYNODIC)
  if phaseJD(k, 0) > jd then
    k = k - 1
  elseif phaseJD(k + 1, 0) <= jd then
    k = k + 1
  end
  return k
end

-- the age of the moon in days at the Julian day jd, and the Julian days of the next new and full moons
local function moonAt(jd)
  local k = lastNew(jd)
  local age = jd - phaseJD(k, 0)
  local full = phaseJD(k, 0.5)
  if full <= jd then full = phaseJD(k + 1, 0.5) end
  return age, phaseJD(k + 1, 0), full
end

-- the fraction of the disc that is lit, 0 to 1 (from the age, with the mean moon)
local function litAt(age)
  return (1 - math.cos(2 * math.pi * age / SYNODIC)) / 2
end

-- the disc as 11 rows of 21 characters: # is lit, . is dark, the terminator is a half ellipse moving across
local function disc(age)
  local c = math.cos(2 * math.pi * age / SYNODIC)
  local waxing = age < SYNODIC / 2
  local rows = {}
  for row = -5, 5 do
    local line = {}
    for col = -10, 10 do
      local nx, ny = col / 10, row / 5
      local ch = " "
      if nx * nx + ny * ny <= 1 then
        local inside = (waxing and nx > c) or (not waxing and nx < -c)
        ch = inside and "#" or "."
      end
      line[#line + 1] = ch
    end
    rows[#rows + 1] = table.concat(line)
  end
  return rows
end

local function fmt(y, m, d)
  return string.format("%04d-%02d-%02d", y, m, d)
end

-- the phase name for an age: eight parts of the month, each centred on its principal phase
local function nameOf(age)
  return NAMES[math.floor(age / SYNODIC * 8 + 0.5) % 8 + 1]
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local y, m, d = dateOf(daysOf(2024, 2, 29))
  check(y == 2024 and m == 2 and d == 29, "dates round trip")
  y, m, d = dateOf(daysOf(1970, 1, 1))
  check(y == 1970 and m == 1 and d == 1, "the epoch")
  -- the new moon of 2000-01-06 (14:20 UTC) and of 2024-01-11 (11:57 UTC), the full moon of 2024-01-25 (17:54 UTC)
  local function jdNoon(yy, mm, dd) return daysOf(yy, mm, dd) + 2440588.0 end
  local age, nextNew, nextFull = moonAt(jdNoon(2000, 1, 6))
  check(nameOf(age) == "new moon", "new moon in 2000")
  check(nameOf(moonAt(jdNoon(2024, 1, 11))) == "new moon", "new moon in January 2024")
  check(nameOf(moonAt(jdNoon(2024, 1, 25))) == "full moon", "full moon in January 2024")
  check(litAt(SYNODIC / 2) > 0.999 and litAt(0) < 0.001, "lit at full and at new")
  check(math.abs(litAt(SYNODIC / 4) - 0.5) < 0.001, "half lit at the quarter")
  age, nextNew, nextFull = moonAt(jdNoon(2024, 1, 11))
  y, m, d = dateOf(math.floor(nextFull - 2440587.5))
  check(fmt(y, m, d) == "2024-01-25", "next full moon after the new moon of 2024-01-11")
  y, m, d = dateOf(math.floor(nextNew - 2440587.5))
  check(fmt(y, m, d) == "2024-02-09", "next new moon after the new moon of 2024-01-11")
  if failed == 0 then print("selftest ok") end
  return
end

local dateArg = arg[1]
if not dateArg then
  dateArg = sys.date("%Y-%m-%d")
  if not dateArg then
    print("moon: the clock is not set yet (connect WiFi), give the date: moon 2024-01-25")
    return
  end
end
local y, m, d = dateArg:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
y, m, d = tonumber(y), tonumber(m), tonumber(d)
if not y or m < 1 or m > 12 or d < 1 or d > 31 then
  print("usage: moon [YYYY-MM-DD]   (moon 2024-01-25)")
  return
end

local age, nextNew, nextFull = moonAt(daysOf(y, m, d) + 2440588.0)   -- noon UTC of the day
local lit = math.floor(litAt(age) * 100 + 0.5)
local ny, nm, nd = dateOf(math.floor(nextNew - 2440587.5))
local fy, fm, fd = dateOf(math.floor(nextFull - 2440587.5))

local text = {
  fmt(y, m, d),
  nameOf(age),
  "",
  string.format("age %.1f days", age),
  string.format("%d%% lit", lit),
  "",
  "new  " .. fmt(ny, nm, nd),
  "full " .. fmt(fy, fm, fd),
}
local drawing = disc(age)
for i = 1, #drawing do
  print(drawing[i] .. "  " .. (text[i] or ""))
end
