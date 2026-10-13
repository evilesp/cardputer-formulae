#!lua
-- epoch: converts Unix time (seconds since 1970-01-01 00:00:00 UTC) to a date and back, all in UTC, no network.
-- usage: epoch SECONDS               a number of seconds (or milliseconds, when it is very large) to a date
--        epoch YYYY-MM-DD [HH:MM[:SS]]   a UTC date and time to the number of seconds
--        epoch now                   the current time, from the clock (needs the time set)
--   epoch 1700000000        2023-11-14 22:13:20 UTC
--   epoch 2026-10-13 12:00  the Unix time of that moment
-- Run it with --selftest to check the sums.

local DAY = 86400
local DAY_NAMES = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
-- above this many seconds the number is taken as milliseconds (year 5138 in seconds)
local MILLI_LIMIT = 100000000000

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

-- true when y-m-d is a real date (no 2026-02-30, and leap years count)
local function isDate(y, m, d)
  if m < 1 or m > 12 or d < 1 then return false end
  local ny, nm, nd = dateOf(daysOf(y, m, d))
  return ny == y and nm == m and nd == d
end

-- the Unix time of a UTC date and time, or nil when the date or the time is not valid
local function unixOf(y, m, d, hh, mm, ss)
  if not isDate(y, m, d) then return nil end
  if hh < 0 or hh > 23 or mm < 0 or mm > 59 or ss < 0 or ss > 59 then return nil end
  return daysOf(y, m, d) * DAY + hh * 3600 + mm * 60 + ss
end

-- the UTC fields of a Unix time: year, month, day, hour, minute, second and the weekday name
local function fieldsOf(t)
  local days = t // DAY
  local secs = t - days * DAY
  local y, m, d = dateOf(days)
  local weekday = DAY_NAMES[(days + 4) % 7 + 1]   -- 1970-01-01 was a Thursday
  return y, m, d, secs // 3600, secs % 3600 // 60, secs % 60, weekday
end

-- the text of a Unix time, for example "2023-11-14 22:13:20 UTC (Tuesday)"
local function describe(t)
  local y, m, d, hh, mm, ss, weekday = fieldsOf(t)
  return string.format("%04d-%02d-%02d %02d:%02d:%02d UTC (%s)", y, m, d, hh, mm, ss, weekday)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(daysOf(1970, 1, 1) == 0, "1970-01-01 is day 0")
  check(unixOf(2023, 11, 14, 22, 13, 20) == 1700000000, "2023-11-14 22:13:20 is 1700000000")
  check(unixOf(2000, 3, 1, 0, 0, 0) == 951868800, "2000-03-01 is 951868800")
  check(unixOf(1969, 12, 31, 23, 59, 59) == -1, "1969-12-31 23:59:59 is -1")
  check(unixOf(2024, 2, 29, 0, 0, 0) ~= nil, "2024-02-29 exists (leap year)")
  check(unixOf(2026, 2, 29, 0, 0, 0) == nil, "2026-02-29 does not exist")
  check(unixOf(2026, 4, 31, 0, 0, 0) == nil, "April has 30 days")
  check(unixOf(2026, 13, 1, 0, 0, 0) == nil, "month 13 does not exist")
  check(unixOf(2026, 1, 1, 24, 0, 0) == nil, "hour 24 does not exist")
  check(describe(0) == "1970-01-01 00:00:00 UTC (Thursday)", "0 is 1970-01-01 Thursday")
  check(describe(1700000000) == "2023-11-14 22:13:20 UTC (Tuesday)", "1700000000 is 2023-11-14 Tuesday")
  check(describe(-1) == "1969-12-31 23:59:59 UTC (Wednesday)", "-1 is 1969-12-31 Wednesday")
  check(describe(951782400) == "2000-02-29 00:00:00 UTC (Tuesday)", "leap day 2000 is a Tuesday")
  for t = -100000000, 100000000, 997 do
    local y, m, d, hh, mm, ss = fieldsOf(t)
    if unixOf(y, m, d, hh, mm, ss) ~= t then
      check(false, "round trip of " .. t)
      break
    end
  end
  if failed == 0 then print("selftest ok") end
  return
end

local USAGE = "usage: epoch SECONDS | epoch YYYY-MM-DD [HH:MM[:SS]] | epoch now"
local first = arg[1]
if not first then
  print(USAGE)
  return
end

if first == "now" then
  local t
  local ok = pcall(function() t = os.time() end)
  if not ok or not t then
    t = tonumber(sys.date("%s"))
  end
  if not t then
    print("the clock is not set: connect to WiFi first")
    return
  end
  print(string.format("now: %d = %s", t, describe(t)))
  return
end

-- a number of seconds (or milliseconds) to a date
if first:match("^%-?%d+$") then
  local t = math.tointeger(tonumber(first))
  if not t then
    print("too large: " .. first)
    return
  end
  if math.abs(t) > MILLI_LIMIT then
    t = t // 1000
  end
  print(first .. " = " .. describe(t))
  return
end

-- a date, with an optional time in the next argument
local y, m, d = first:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
if y then
  local hh, mm, ss = 0, 0, 0
  if arg[2] then
    local h1, m1, s1 = arg[2]:match("^(%d%d?):(%d%d)(:?%d*)$")
    -- the seconds part is ":SS" or empty; a bare colon like "12:30:" is refused
    if not h1 or (s1 ~= "" and #s1 ~= 3) then
      print("the time must be HH:MM or HH:MM:SS: " .. arg[2])
      return
    end
    hh, mm = tonumber(h1), tonumber(m1)
    ss = s1 == "" and 0 or tonumber(s1:sub(2))
  end
  local t = unixOf(tonumber(y), tonumber(m), tonumber(d), hh, mm, ss)
  if not t then
    print("not a real UTC date and time: " .. first .. (arg[2] and (" " .. arg[2]) or ""))
  else
    print(string.format("%04d-%02d-%02d %02d:%02d:%02d UTC = %d", tonumber(y), tonumber(m), tonumber(d), hh, mm, ss, t))
  end
  return
end

print(USAGE)
