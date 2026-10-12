#!lua
-- roman: converts a number to a Roman numeral and a Roman numeral back to a number.
-- usage: roman NUMBER|ROMAN     for example: roman 1994   roman MMXXVI   roman mcmxciv
-- The numbers run from 1 to 3999. Only the usual spelling counts: IIII and VX are refused.
-- Run it with --selftest to check the rules.

-- the symbols from the largest value down, with the subtractive pairs (CM, XC, IV...)
local SYMBOLS = {
  { 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" },
  { 100, "C" }, { 90, "XC" }, { 50, "L" }, { 40, "XL" },
  { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" },
}

local VALUES = { I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000 }

-- the Roman numeral for a whole number from 1 to 3999, or nil when it is out of range
local function toRoman(n)
  if math.type(n) ~= "integer" or n < 1 or n > 3999 then return nil end
  local out = {}
  for _, pair in ipairs(SYMBOLS) do
    while n >= pair[1] do
      out[#out + 1] = pair[2]
      n = n - pair[1]
    end
  end
  return table.concat(out)
end

-- the number for a Roman numeral (upper or lower case), or nil when the text is not a valid numeral
local function fromRoman(text)
  local s = text:upper()
  if s == "" or s:find("[^IVXLCDM]") then return nil end
  -- read from the right: a smaller symbol before a larger one is subtracted
  local total, previous = 0, 0
  for i = #s, 1, -1 do
    local value = VALUES[s:sub(i, i)]
    if value < previous then
      total = total - value
    else
      total = total + value
      previous = value
    end
  end
  -- the number must give back the same spelling, so IIII and VX are refused
  if total < 1 or total > 3999 or toRoman(total) ~= s then return nil end
  return total
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(toRoman(1994) == "MCMXCIV", "1994 is MCMXCIV")
  check(toRoman(2026) == "MMXXVI", "2026 is MMXXVI")
  check(toRoman(3999) == "MMMCMXCIX", "3999 is MMMCMXCIX")
  check(toRoman(4) == "IV", "4 is IV")
  check(toRoman(0) == nil, "0 has no Roman numeral")
  check(toRoman(4000) == nil, "4000 is out of range")
  check(toRoman(1.5) == nil, "a fraction has no Roman numeral")
  check(fromRoman("mcmxciv") == 1994, "mcmxciv is 1994 (lower case works)")
  check(fromRoman("MMXXVI") == 2026, "MMXXVI is 2026")
  check(fromRoman("IIII") == nil, "IIII is refused, the usual spelling is IV")
  check(fromRoman("VX") == nil, "VX is refused")
  check(fromRoman("ABC") == nil, "ABC is not a numeral")
  check(fromRoman("") == nil, "an empty text is not a numeral")
  for n = 1, 3999 do
    if fromRoman(toRoman(n)) ~= n then
      check(false, "round trip of " .. n)
      break
    end
  end
  if failed == 0 then print("selftest ok") end
  return
end

local input = arg[1]
if not input then
  print("usage: roman NUMBER|ROMAN   (roman 1994 or roman MMXXVI, 1 to 3999)")
  return
end

local number = tonumber(input)
if number then
  local numeral = toRoman(number)
  if numeral then
    print(input .. " = " .. numeral)
  else
    print("out of range: use whole numbers from 1 to 3999")
  end
  return
end

local value = fromRoman(input)
if value then
  print(input:upper() .. " = " .. value)
else
  print("not a Roman numeral: " .. input)
end
