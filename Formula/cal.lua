#!lua
-- cal: a calendar month. usage: cal [MONTH YEAR]   (default: the current month, once the clock is set)

local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
                 "August", "September", "October", "November", "December" }
local DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function leap(y)
  return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
end

local function daysIn(y, m)
  if m == 2 and leap(y) then return 29 end
  return DAYS[m]
end

-- weekday of a date, 0 = Sunday (Sakamoto's method)
local function weekday(y, m, d)
  local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
  if m < 3 then y = y - 1 end
  return (y + y // 4 - y // 100 + y // 400 + t[m] + d) % 7
end

local month, year, today
if #arg >= 2 then
  month, year = tonumber(arg[1]), tonumber(arg[2])
elseif sys.date("%Y") then
  year = tonumber(sys.date("%Y"))
  month = tonumber(sys.date("%m"))
  today = tonumber(sys.date("%d"))
else
  print("cal: the clock is not set yet, use: cal MONTH YEAR")
  return
end
if not month or not year or month < 1 or month > 12 then
  print("cal: usage: cal [MONTH YEAR]")
  return
end

local title = MONTHS[month] .. " " .. year
print(string.rep(" ", (21 - #title) // 2) .. title)
term.print("Su Mo Tu We Th Fr Sa", "cyan")

-- one row per week, every day cell is 3 characters wide
local col = weekday(year, month, 1)
term.write(string.rep("   ", col), "text")
for d = 1, daysIn(year, month) do
  local color = (d == today) and "yellow" or "text"
  term.write(string.format("%2d ", d), color)
  col = col + 1
  if col == 7 then
    term.print("", "text")
    col = 0
  end
end
if col ~= 0 then term.print("", "text") end
