#!lua
-- bmi: body mass index with the WHO categories and the healthy weight range for a height.
-- usage: bmi WEIGHT_KG HEIGHT_CM     for example: bmi 70 175   bmi 70 1.75   bmi 82,5 180
--        the height can be given in centimetres (over 3) or in metres.
-- Run it with --selftest to check the numbers.

-- the height in metres, from centimetres (175) or metres (1.75)
local function toMetres(height)
  if height > 3 then return height / 100 end
  return height
end

-- the body mass index: kilograms divided by the square of the height in metres
local function bmiOf(kg, height)
  local m = toMetres(height)
  return kg / (m * m)
end

-- the WHO category for a body mass index
local function categoryOf(value)
  if value < 18.5 then return "underweight" end
  if value < 25 then return "normal weight" end
  if value < 30 then return "overweight" end
  return "obese"
end

-- the weight range with a BMI from 18.5 to 24.9 for this height, in kilograms
local function healthyRange(height)
  local m = toMetres(height)
  return 18.5 * m * m, 24.9 * m * m
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
  check(math.abs(bmiOf(70, 1.75) - 22.857) < 0.01, "70 kg at 1.75 m is about 22.9")
  check(math.abs(bmiOf(70, 175) - 22.857) < 0.01, "175 cm is the same as 1.75 m")
  check(categoryOf(bmiOf(50, 1.80)) == "underweight", "50 kg at 1.80 m is underweight")
  check(categoryOf(bmiOf(70, 1.75)) == "normal weight", "70 kg at 1.75 m is normal")
  check(categoryOf(bmiOf(100, 1.75)) == "obese", "100 kg at 1.75 m is obese")
  check(categoryOf(25) == "overweight", "a BMI of exactly 25 is overweight")
  check(categoryOf(18.5) == "normal weight", "a BMI of exactly 18.5 is normal")
  check(categoryOf(30) == "obese", "a BMI of exactly 30 is obese")
  local low, high = healthyRange(1.80)
  check(math.abs(low - 59.94) < 0.01 and math.abs(high - 80.68) < 0.01, "1.80 m range is 59.9 to 80.7 kg")
  check(parseNumber("82,5") == 82.5, "a comma works as the decimal point")
  if failed == 0 then print("selftest ok") end
  return
end

local kg = parseNumber(arg[1])
local height = parseNumber(arg[2])

if not kg or not height or kg <= 0 or height <= 0 then
  print("usage: bmi WEIGHT_KG HEIGHT_CM   (bmi 70 175)")
  return
end

local value = bmiOf(kg, height)
local low, high = healthyRange(height)
print(string.format("BMI: %.1f", value))
print("category: " .. categoryOf(value))
print(string.format("healthy weight for this height: %.1f to %.1f kg", low, high))
