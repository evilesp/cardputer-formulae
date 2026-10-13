#!lua
-- loan: the monthly payment of a loan and what it costs in total.
-- usage: loan AMOUNT RATE YEARS     for example: loan 20000 7.5 5   loan 5000 0 2
--        RATE is the yearly interest in percent (0 for an interest-free loan); YEARS may be 2.5.
--        The payments are equal (annuity): the interest falls as the debt is paid down.
--        A comma works as the decimal point. Run it with --selftest to check the sums.

-- the numbers in cents, so the sums never show more than two decimals
local function toCents(v)
  return math.floor(v * 100 + 0.5)
end

-- the money in the form 12.34 (cents are rounded half up)
local function money(cents)
  return string.format("%d.%02d", cents // 100, cents % 100)
end

-- the equal monthly payment for an amount, a monthly rate (0.01 = 1 percent) and a number of months
local function payment(amount, monthlyRate, months)
  if monthlyRate == 0 then return amount / months end
  local growth = (1 + monthlyRate) ^ months
  return amount * monthlyRate * growth / (growth - 1)
end

-- the monthly payment in cents, rounded up as banks do, so the total is never less than the loan
local function paymentCents(amount, monthlyRate, months)
  return math.ceil(payment(amount, monthlyRate, months) * 100 - 1e-6)
end

-- the number of monthly payments for a number of years, rounded to the nearest month
local function monthsOf(years)
  return math.floor(years * 12 + 0.5)
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
  local p = payment(10000, 0.01, 12)
  check(math.abs(p - 888.49) < 0.01, "10000 at 12 percent for a year is about 888.49 a month")
  check(math.abs(payment(12000, 0, 12) - 1000) < 1e-9, "12000 without interest for a year is 1000 a month")
  check(monthsOf(2.5) == 30, "2.5 years is 30 months")
  check(monthsOf(1) == 12, "1 year is 12 months")
  check(paymentCents(10000, 0.01, 12) == 88849, "10000 at 12 percent for a year is 888.49 a month, rounded up")
  check(paymentCents(5000, 0, 24) == 20834, "5000 without interest over 24 months is 208.34 a month, rounded up")
  check(money(toCents(888.487)) == "888.49", "888.487 is printed as 888.49")
  check(money(toCents(1000)) == "1000.00", "1000 is printed with two decimals")
  check(money(5) == "0.05", "5 cents is printed as 0.05")
  check(parseNumber("7,5") == 7.5, "a comma works as the decimal point")
  if failed == 0 then print("selftest ok") end
  return
end

local amount = parseNumber(arg[1])
local rate = parseNumber(arg[2])
local years = parseNumber(arg[3])

if not amount or not rate or not years or amount <= 0 or rate < 0 or years <= 0 or years > 100 then
  print("usage: loan AMOUNT RATE YEARS   (loan 20000 7.5 5)")
  return
end

local months = monthsOf(years)
if months < 1 then
  print("usage: loan AMOUNT RATE YEARS   (the loan must run at least a month)")
  return
end

local monthlyPayment = paymentCents(amount, rate / 1200, months)
local totalCents = monthlyPayment * months
local amountCents = toCents(amount)

print("loan:     " .. money(amountCents))
print("rate:     " .. string.format("%g", rate) .. "% a year for " .. months .. " months")
print("monthly:  " .. money(monthlyPayment))
print("total:    " .. money(totalCents))
print("interest: " .. money(totalCents - amountCents))
