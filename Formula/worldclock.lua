#!lua
-- worldclock: the time in several cities, with the date and the difference to your clock. Summer time (DST) is taken from
-- the dates: Europe from the last Sunday of March to the last Sunday of October, the US and Canada from the second Sunday
-- of March to the first Sunday of November (about one hour is wrong on the switching days). Sydney and Tokyo are shown
-- without summer time. w and s choose a city, a adds a city in the list, ctrl-q quits. Needs the graphics, the ui package
-- and a clock (the network sets it). Run it with --selftest to check the dates.

-- the date (year, month, day) of a number of days since 1 January 1970
local function civilFromDays(z)
  z = z + 719468
  local era = z // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  if m <= 2 then y = y + 1 end
  return y, m, d
end

-- the days since 1 January 1970 of a date (proleptic Gregorian)
local function daysFrom(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = y // 400
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = (153 * mp + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

-- the day of the week of a day number: 0 is Sunday ... 6 is Saturday (1 January 1970 was a Thursday)
local function weekdayOf(days)
  return (days + 4) % 7
end

-- the day of the month of the n-th Sunday of a month (n = -1 is the last one)
local function sundayOf(y, m, n)
  if n > 0 then
    local first = daysFrom(y, m, 1)
    local offset = (7 - weekdayOf(first)) % 7
    return 1 + offset + (n - 1) * 7
  end
  local lastDay = daysFrom(y, m + 1 > 12 and 1 or m + 1, 1) - daysFrom(y, m, 1)
  local lastDays = daysFrom(y, m, 1) + lastDay - 1
  return lastDay - (weekdayOf(lastDays) + 0) % 7
end

-- true when summer time is on for a date (y, m, d) in the given rule ("eu" or "us")
local function summerTime(rule, y, m, d)
  local day = daysFrom(y, m, d)
  if rule == "eu" then
    local start = daysFrom(y, 3, sundayOf(y, 3, -1))
    local stop = daysFrom(y, 10, sundayOf(y, 10, -1))
    return day >= start and day < stop
  end
  if rule == "us" then
    local start = daysFrom(y, 3, sundayOf(y, 3, 2))
    local stop = daysFrom(y, 11, sundayOf(y, 11, 1))
    return day >= start and day < stop
  end
  return false
end

local CITIES = {
  { name = "Warsaw", zone = 1, rule = "eu" },
  { name = "London", zone = 0, rule = "eu" },
  { name = "New York", zone = -5, rule = "us" },
  { name = "Los Angeles", zone = -8, rule = "us" },
  { name = "Tokyo", zone = 9, rule = nil },
  { name = "Sydney", zone = 10, rule = nil },
}

-- the offset of a city from UTC in hours at the time utc (seconds since 1970)
local function offsetOf(city, utc)
  local y, m, d = civilFromDays(utc // 86400)
  return city.zone + ((city.rule and summerTime(city.rule, y, m, d)) and 1 or 0)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local y, m, d = civilFromDays(0)
  check(y == 1970 and m == 1 and d == 1, "day 0 is 1 January 1970")
  y, m, d = civilFromDays(daysFrom(2026, 10, 12))
  check(y == 2026 and m == 10 and d == 12, "the date of a day round trips")
  check(weekdayOf(daysFrom(2000, 1, 1)) == 6, "1 January 2000 was a Saturday")
  check(weekdayOf(daysFrom(2026, 10, 12)) == 1, "12 October 2026 is a Monday")
  check(sundayOf(2026, 3, -1) == 29, "the last Sunday of March 2026 is the 29th")
  check(sundayOf(2026, 3, 2) == 8, "the second Sunday of March 2026 is the 8th")
  check(summerTime("eu", 2026, 7, 1) and not summerTime("eu", 2026, 1, 15), "Europe: summer in July, not in January")
  check(not summerTime("eu", 2026, 3, 28) and summerTime("eu", 2026, 3, 30), "Europe starts on the last Sunday of March")
  check(summerTime("us", 2026, 7, 1) and not summerTime("us", 2026, 12, 1), "the US: summer in July, not in December")
  local warsaw = CITIES[1]
  check(offsetOf(warsaw, daysFrom(2026, 1, 15) * 86400) == 1 and offsetOf(warsaw, daysFrom(2026, 7, 15) * 86400) == 2, "Warsaw is UTC+1, in summer UTC+2")
  check(offsetOf(CITIES[5], daysFrom(2026, 7, 15) * 86400) == 9, "Tokyo has no summer time")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("worldclock needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("worldclock: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local selected = 1

local function two(n)
  return string.format("%02d", n)
end

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "WORLD CLOCK", 0xe8ecf4)
  local utc = sys.time()
  local homeOffset = 1
  for i, city in ipairs(CITIES) do
    local y = 20 + (i - 1) * 17
    local off = offsetOf(city, utc)
    local local_ = utc + off * 3600
    local days = local_ // 86400
    local secs = local_ % 86400
    local yy, mm, dd = civilFromDays(days)
    if i == selected then gfx.fill(4, y - 2, W - 8, 15, 0x2a3350) end
    ui.label(8, y, city.name, 0xe8ecf4)
    ui.label(104, y, two(secs // 3600) .. ":" .. two(secs // 60 % 60) .. ":" .. two(secs % 60), 0xf0d040)
    ui.label(170, y, string.format("%02d.%02d", dd, mm), 0x8a94aa)
    ui.label(200, y, string.format("UTC%+d", off), 0x8a94aa)
  end
  ui.label(8, H - 10, "w s choose   ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("worldclock: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "w" then selected = math.max(1, selected - 1)
      elseif k == "s" then selected = math.min(#CITIES, selected + 1)
      end
      k = key.poll()
    end
    sys.sleep(200)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("worldclock: " .. tostring(problem)) end
