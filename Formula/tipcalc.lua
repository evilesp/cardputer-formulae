#!lua
-- tipcalc: the tip and the split of a bill between people.
-- usage: tipcalc BILL [PERCENT] [PEOPLE]     for example: tipcalc 85.50   tipcalc 85,50 15 3
--        the tip is 10 percent and one person when not given; a comma works as the decimal point.
-- Run it with --selftest to check the sums.

-- the numbers in cents, so the sums never show more than two decimals
local function toCents(v)
  return math.floor(v * 100 + 0.5)
end

-- the money in the form 12.34 (cents are rounded half up)
local function money(cents)
  local sign = ""
  if cents < 0 then sign = "-"; cents = -cents end
  return string.format("%s%d.%02d", sign, cents // 100, cents % 100)
end

-- the bill with its tip and the total, in cents; the tip is rounded to the cent
local function tipOf(billCents, percent)
  local tipCents = math.floor(billCents * percent / 100 + 0.5)
  return tipCents, billCents + tipCents
end

-- each person's share of the total, rounded up to the cent so the group never pays too little
local function share(totalCents, people)
  return (totalCents + people - 1) // people
end

local function parseNumber(text)
  if not text then return nil end
  return tonumber((text:gsub(",", ".")))
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local tip, total = tipOf(8550, 10)
  check(tip == 855 and total == 9405, "85.50 with 10 percent is 8.55 and 94.05")
  tip, total = tipOf(10000, 15)
  check(tip == 1500 and total == 11500, "100.00 with 15 percent is 15.00 and 115.00")
  check(share(9405, 3) == 3135, "94.05 split three ways is 31.35 each")
  check(share(10000, 3) == 3334, "100.00 split three ways rounds up to 33.34")
  check(share(9405, 1) == 9405, "one person pays the whole total")
  check(money(3135) == "31.35", "31.35 is printed with two decimals")
  check(money(5) == "0.05", "5 cents is printed as 0.05")
  check(money(-250) == "-2.50", "a negative amount keeps its sign")
  check(toCents(85.5) == 8550, "85.50 is 8550 cents")
  check(parseNumber("85,50") == 85.5, "a comma works as the decimal point")
  if failed == 0 then print("selftest ok") end
  return
end

local bill = parseNumber(arg[1])
local percent = parseNumber(arg[2]) or 10
local people = math.floor(parseNumber(arg[3]) or 1)

if not bill or bill < 0 or percent < 0 or people < 1 then
  print("usage: tipcalc BILL [PERCENT] [PEOPLE]   (tipcalc 85.50 15 3)")
  return
end

local billCents = toCents(bill)
local tipCents, totalCents = tipOf(billCents, percent)
print("bill:  " .. money(billCents))
print("tip " .. string.format("%g", percent) .. "%: " .. money(tipCents))
print("total: " .. money(totalCents))
if people > 1 then
  print("each of " .. people .. ": " .. money(share(totalCents, people)))
end
