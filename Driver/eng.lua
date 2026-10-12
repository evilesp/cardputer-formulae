#!lua
-- eng: engineering numbers for the electronics apps (brew installs it as a driver: driver.load("eng")).
--   eng.parse("4.7k") -> 4700      eng.parse("4k7"), "4R7", "100n", "2u2", "10Meg", "1e3", "100nF", "4.7kohm" all work
--   eng.format(4700) -> "4.7k"     eng.format(0.0000001) -> "100n"   (letters p n u m k M G; 3 significant digits by default)
--   eng.series("E24") -> the values 1.0 .. 9.1 of a decade     eng.nearest(4.6e3, "E24") -> 4700, error in percent
-- Letters are ASCII (u is micro). Run it as a script with --selftest.

local eng = {}

local PREFIX = { p = 1e-12, n = 1e-9, u = 1e-6, m = 1e-3, k = 1e3, M = 1e6, G = 1e9 }
local ORDER = { { 1e9, "G" }, { 1e6, "M" }, { 1e3, "k" }, { 1, "" }, { 1e-3, "m" }, { 1e-6, "u" }, { 1e-9, "n" }, { 1e-12, "p" } }

-- the text as a number, or nil. A prefix letter in the middle of the digits is the decimal point: "4k7" is 4.7k
function eng.parse(text)
  if type(text) ~= "string" then return nil end
  local s = text:gsub("%s+", ""):gsub("[\xCE\xBC\xC2\xB5]", "u")  -- spaces go; the Greek mu and the micro sign become u
  -- units after the number are ignored: ohm, F, H, V, A, W, Hz (but not a prefix letter)
  s = s:gsub("[Oo][Hh][Mm][Ss]?$", ""):gsub("Hz$", ""):gsub("[FHVAW]$", "")
  s = s:gsub("[Mm][Ee][Gg]$", "M")
  if s == "" then return nil end
  local plain = tonumber(s)
  if plain then return plain end
  local int, p, frac = s:match("^(%d*)([pnumkMGRr])(%d*)$")
  if p and (int ~= "" or frac ~= "") then
    local v = tonumber((int ~= "" and int or "0") .. "." .. (frac ~= "" and frac or "0"))
    if not v then return nil end
    return v * (PREFIX[p] or 1)
  end
  local num, suffix = s:match("^([%d%.]+)([pnumkMG])$")
  if num and tonumber(num) then return tonumber(num) * PREFIX[suffix] end
  local num2, suffix2 = s:match("^([%d%.]+[eE][%+%-]?%d+)([pnumkMG])$")
  if num2 and tonumber(num2) then return tonumber(num2) * PREFIX[suffix2] end
  return nil
end

-- a number as short text with a prefix letter: 4700 -> "4.7k", 0.00047 -> "470u"; digits = significant digits (3)
function eng.format(v, digits)
  digits = digits or 3
  if v == 0 then return "0" end
  local sign = v < 0 and "-" or ""
  v = math.abs(v)
  local chosen = ORDER[#ORDER]
  for _, o in ipairs(ORDER) do
    if v >= o[1] * 0.9995 then chosen = o break end
  end
  local scaled = v / chosen[1]
  local text = string.format("%." .. digits .. "g", scaled)
  if text:find("e", 1, true) then text = string.format("%.0f", scaled) end
  if text:find("%.") then text = text:gsub("0+$", ""):gsub("%.$", "") end
  return sign .. text .. chosen[2]
end

-- the values of one decade of a standard series (E3, E6, E12, E24, E48, E96, E192) as numbers from 1.00 to 9.99
local E24 = { 1.0, 1.1, 1.2, 1.3, 1.5, 1.6, 1.8, 2.0, 2.2, 2.4, 2.7, 3.0, 3.3, 3.6, 3.9, 4.3, 4.7, 5.1, 5.6, 6.2, 6.8, 7.5, 8.2, 9.1 }
local E12 = { 1.0, 1.2, 1.5, 1.8, 2.2, 2.7, 3.3, 3.9, 4.7, 5.6, 6.8, 8.2 }
local E6 = { 1.0, 1.5, 2.2, 3.3, 4.7, 6.8 }
local E3 = { 1.0, 2.2, 4.7 }
local cache = {}
function eng.series(name)
  if cache[name] then return cache[name] end
  local list
  if name == "E3" then list = E3 elseif name == "E6" then list = E6 elseif name == "E12" then list = E12
  elseif name == "E24" then list = E24
  else
    local n = tonumber(name:match("^E(%d+)$") or "")
    if n ~= 48 and n ~= 96 and n ~= 192 then return nil end
    list = {}
    for i = 0, n - 1 do list[i + 1] = math.floor(10 ^ (i / n) * 100 + 0.5) / 100 end  -- three digits: 1.00, 1.02, 1.05, ...
  end
  cache[name] = list
  return list
end

-- the nearest standard value to v (by ratio) and how far it is in percent (positive: the standard value is bigger).
-- Also the nearest below and above.
function eng.nearest(v, name)
  local list = eng.series(name)
  if not list or not v or v <= 0 then return nil end
  local decade = math.floor(math.log(v, 10) + 1e-9)
  local best, bestErr, below, above = nil, math.huge, nil, nil
  for d = decade - 1, decade + 1 do
    for _, x in ipairs(list) do
      local value = x * 10 ^ d
      local err = math.abs(math.log(value / v))
      if err < bestErr then best, bestErr = value, err end
      if value <= v * 1.000001 and (not below or value > below) then below = value end
      if value >= v * 0.999999 and (not above or value < above) then above = value end
    end
  end
  return best, (best / v - 1) * 100, below, above
end

-- true when v is a value of the series (within 0.2 percent)
function eng.inSeries(v, name)
  local best, err = eng.nearest(v, name)
  return best ~= nil and math.abs(err) < 0.2
end

function eng.parallel(a, b) return a * b / (a + b) end

if arg and arg[1] == "--selftest" and select("#", ...) > 0 then  -- only when run as a script: a driver is loaded with no arguments
  local checks = 0
  local function expect(cond, what)
    checks = checks + 1
    if not cond then error("check " .. checks .. ": " .. what) end
  end
  local function near(a, b) return a and b and math.abs(a - b) <= 1e-9 * math.max(1, math.abs(b)) end
  expect(near(eng.parse("4.7k"), 4700) and near(eng.parse("4k7"), 4700) and near(eng.parse("4R7"), 4.7), "decimal prefixes")
  expect(near(eng.parse("100n"), 1e-7) and near(eng.parse("2u2"), 2.2e-6) and near(eng.parse("100nF"), 1e-7), "small values and units")
  expect(near(eng.parse("10Meg"), 1e7) and near(eng.parse("1e3"), 1000) and near(eng.parse("4.7kohm"), 4700), "words and exponents")
  expect(near(eng.parse(" 22 pF"), 2.2e-11) and near(eng.parse("0.5"), 0.5) and near(eng.parse("1.5e-3"), 0.0015), "spaces and plain numbers")
  expect(eng.parse("abc") == nil and eng.parse("") == nil and eng.parse("k") == nil and eng.parse(nil) == nil, "bad text")
  expect(eng.format(4700) == "4.7k" and eng.format(1e-7) == "100n" and eng.format(2.2e-6) == "2.2u", "format")
  expect(eng.format(0) == "0" and eng.format(1) == "1" and eng.format(1500000) == "1.5M" and eng.format(0.47) == "470m", "format: edges")
  expect(eng.format(999.9) == "1k" and eng.format(-4700) == "-4.7k" and eng.format(33) == "33", "format: rounding up and sign")
  expect(#eng.series("E24") == 24 and #eng.series("E12") == 12 and #eng.series("E96") == 96 and #eng.series("E192") == 192, "series sizes")
  expect(#eng.series("E48") == 48 and eng.series("E7") == nil, "E48, and an unknown series")
  local e96 = eng.series("E96")
  expect(e96[1] == 1 and e96[2] == 1.02 and e96[3] == 1.05 and e96[96] == 9.76 and e96[49] == 3.16, "E96 values")
  local best, err, below, above = eng.nearest(4600, "E24")
  expect(best == 4700 and below == 4300 and above == 4700 and math.abs(err - 2.17) < 0.01, "nearest in E24")
  expect(near(eng.nearest(1, "E12"), 1) and near(eng.nearest(9.6, "E12"), 10), "the next decade")
  expect(eng.inSeries(4700, "E24") and not eng.inSeries(4600, "E24") and eng.inSeries(4640, "E96"), "membership")
  expect(near(eng.parallel(100, 100), 50), "parallel")
  print("selftest ok")
end

return eng
