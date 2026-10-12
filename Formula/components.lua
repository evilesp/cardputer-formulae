#!lua
-- components: reads the values of electronic parts. Pick the kind of part:
--   * resistor with colour bands (through hole): 3, 4, 5 or 6 bands; w and s change the colour of the chosen band, a and d choose
--     the band, v types a value (4k7) and puts the bands for it, b changes the number of bands
--   * resistor SMD code: 3 digits (472), 4 digits (1002), with R (4R7, 0R22), EIA-96 (01C), and the reverse: value to code
--   * capacitor code: 104K, 4n7, 22, and the tantalum 3-digit code with its voltage (A106), and the reverse
--   * inductor SMD code: 101, 4R7, 47N, and the reverse
--   * inductor with colour bands (like a resistor, the value is in microhenry)
-- c types a code, v types a value, ctrl-q goes back. Needs the graphics, the ui package and the eng driver.
-- Run it with --selftest to check the codes.

local COLORS = {
  black = 0x181818, brown = 0x7a4a20, red = 0xd02020, orange = 0xf07820, yellow = 0xf0d820, green = 0x30a040,
  blue = 0x2050d0, violet = 0x8030c0, grey = 0x909090, white = 0xf0f0f0, gold = 0xd0a830, silver = 0xc0c8d0,
}
local DIGIT = { "black", "brown", "red", "orange", "yellow", "green", "blue", "violet", "grey", "white" }
-- the multiplier of each colour (as a power of ten)
local MULT = { black = 0, brown = 1, red = 2, orange = 3, yellow = 4, green = 5, blue = 6, violet = 7, grey = 8, white = 9, gold = -1, silver = -2 }
local MULT_ORDER = { "black", "brown", "red", "orange", "yellow", "green", "blue", "violet", "grey", "white", "gold", "silver" }
-- the tolerance in percent; "none" has no band (20 percent)
local TOL = { brown = 1, red = 2, green = 0.5, blue = 0.25, violet = 0.1, grey = 0.05, gold = 5, silver = 10, none = 20 }
local TOL_ORDER = { "gold", "silver", "brown", "red", "green", "blue", "violet", "grey", "none" }
-- the temperature coefficient in ppm per kelvin
local TEMPCO = { black = 250, brown = 100, red = 50, orange = 15, yellow = 25, green = 20, blue = 10, violet = 5, grey = 1 }
local TEMPCO_ORDER = { "brown", "red", "orange", "yellow", "green", "blue", "violet", "grey", "black" }

-- the roles of the bands for a number of bands
local ROLES = {
  [3] = { "digit", "digit", "mult" },
  [4] = { "digit", "digit", "mult", "tol" },
  [5] = { "digit", "digit", "digit", "mult", "tol" },
  [6] = { "digit", "digit", "digit", "mult", "tol", "tempco" },
}
local CHOICES = { digit = DIGIT, mult = MULT_ORDER, tol = TOL_ORDER, tempco = TEMPCO_ORDER }
local ROLE_NAME = { digit = "digit", mult = "multiplier", tol = "tolerance", tempco = "temp. coefficient" }

local DIGIT_VALUE = {}
for i, name in ipairs(DIGIT) do DIGIT_VALUE[name] = i - 1 end

-- the value, the tolerance (percent) and the temperature coefficient of a list of colours (names)
local function bandsValue(colours)
  local roles = ROLES[#colours]
  local mantissa, exp, tol, tempco = 0, 0, 20, nil
  for i, role in ipairs(roles) do
    local c = colours[i]
    if role == "digit" then mantissa = mantissa * 10 + (DIGIT_VALUE[c] or 0)
    elseif role == "mult" then exp = MULT[c]
    elseif role == "tol" then tol = TOL[c]
    elseif role == "tempco" then tempco = TEMPCO[c] end
  end
  return mantissa * 10 ^ exp, tol, tempco
end

-- the bands (colour names) of a value with n bands and a tolerance in percent; nil and the reason when it cannot be shown
local function valueBands(value, n, tol)
  local roles = ROLES[n]
  local digits = 0
  for _, r in ipairs(roles) do if r == "digit" then digits = digits + 1 end end
  if not value or value <= 0 then
    if value == 0 then
      local c = {}
      for i = 1, digits do c[i] = "black" end
      c[#c + 1] = "black"
      for i = digits + 2, n do c[i] = roles[i] == "tol" and "gold" or "brown" end
      return c, 0
    end
    return nil, "the value must be bigger than zero"
  end
  local e = math.floor(math.log(value, 10) + 1e-9) - (digits - 1)
  local mant = math.floor(value / 10 ^ e + 0.5)
  if mant >= 10 ^ digits then mant, e = mant // 10, e + 1 end
  if e < -2 then return nil, "too small for " .. n .. " bands" end
  if e > 9 then return nil, "too big for " .. n .. " bands" end
  local text = string.format("%0" .. digits .. "d", mant)
  local colours = {}
  for i = 1, digits do colours[i] = DIGIT[tonumber(text:sub(i, i)) + 1] end
  for name, p in pairs(MULT) do if p == e then colours[digits + 1] = name end end
  if #colours < n then
    -- the tolerance band: the colour of the nearest tolerance
    local pick, bestErr = "gold", math.huge
    for name, t in pairs(TOL) do
      if name ~= "none" and math.abs(t - (tol or 5)) < bestErr then pick, bestErr = name, math.abs(t - (tol or 5)) end
    end
    colours[digits + 2] = pick
    if n == 6 then colours[6] = "brown" end
  end
  if n == 3 then colours[4] = nil end
  local approx = mant * 10 ^ e
  return colours, approx
end

-- ---- SMD codes ----

-- the 96 values of the EIA-96 code (01 to 96) and the multiplier letters
local EIA96 = { 100, 102, 105, 107, 110, 113, 115, 118, 121, 124, 127, 130, 133, 137, 140, 143, 147, 150, 154, 158, 162, 165, 169, 174,
  178, 182, 187, 191, 196, 200, 205, 210, 215, 221, 226, 232, 237, 243, 249, 255, 261, 267, 274, 280, 287, 294, 301, 309, 316, 324,
  332, 340, 348, 357, 365, 374, 383, 392, 402, 412, 422, 432, 442, 453, 464, 475, 487, 499, 511, 523, 536, 549, 562, 576, 590, 604,
  619, 634, 649, 665, 681, 698, 715, 732, 750, 768, 787, 806, 825, 845, 866, 887, 909, 931, 953, 976 }
local EIA_MULT = { Z = 0.001, Y = 0.01, R = 0.01, X = 0.1, S = 0.1, A = 1, B = 10, H = 10, C = 100, D = 1000, E = 10000, F = 100000 }
local EIA_LETTER = { [0.001] = "Z", [0.01] = "Y", [0.1] = "X", [1] = "A", [10] = "B", [100] = "C", [1000] = "D", [10000] = "E", [100000] = "F" }

local function clean(code) return (code or ""):gsub("%s+", "") end

-- decodes the marking of an SMD resistor: value in ohm and the lines that explain it, or nil and a reason
local function decodeResistor(code)
  local s = clean(code):upper()
  if s == "" then return nil, "type the code printed on the part" end
  local int, mark, frac = s:match("^(%d*)([RKM])(%d*)$")
  if mark and (int ~= "" or frac ~= "") then
    local v = tonumber((int ~= "" and int or "0") .. "." .. (frac ~= "" and frac or "0"))
    local m = mark == "R" and 1 or (mark == "K" and 1e3 or 1e6)
    return v * m, { mark .. " is the decimal point", (mark == "R" and "ohm" or (mark == "K" and "kilo-ohm" or "mega-ohm")) .. " range" }
  end
  local d2, letter = s:match("^(%d%d)([ZYXSABHCDEF])$")
  if d2 then
    local idx = tonumber(d2)
    if idx >= 1 and idx <= 96 then
      return EIA96[idx] * EIA_MULT[letter], { "EIA-96: " .. d2 .. " is " .. EIA96[idx], letter .. " multiplies by " .. EIA_MULT[letter], "a 1% resistor" }
    end
    return nil, "EIA-96 numbers are 01 to 96"
  end
  local a, c = s:match("^(%d%d)(%d)$")
  if a then
    local e = tonumber(c)
    if e == 8 then e = -2 elseif e == 9 then e = -1 end
    local v = tonumber(a) * 10 ^ e
    local lines = { "3 digits: " .. a .. " x 10^" .. e }
    if s == "000" then lines = { "000 is a jumper of zero ohm" } end
    return v, lines
  end
  local abc, d = s:match("^(%d%d%d)(%d)$")
  if abc then
    local e = tonumber(d)
    if e == 8 then e = -2 elseif e == 9 then e = -1 end
    return tonumber(abc) * 10 ^ e, { "4 digits: " .. abc .. " x 10^" .. e, "a 1% resistor" }
  end
  return nil, "not a resistor code: try 472, 1002, 4R7 or 01C"
end

-- the ways to write a value in ohm as a code
local function resistorCodes(value)
  local out = {}
  if value <= 0 then return { "000 (jumper)" } end
  local e = math.floor(math.log(value, 10) + 1e-9)
  local function exact(mantDigits)
    local ee = e - (mantDigits - 1)
    local mant = math.floor(value / 10 ^ ee + 0.5)
    if mant >= 10 ^ mantDigits then mant, ee = mant // 10, ee + 1 end
    return mant, ee, math.abs(mant * 10 ^ ee - value) < value * 1e-6
  end
  if value < 10 then
    local text = string.format("%g", value):gsub("%.", "R")
    if not text:find("R") then text = text .. "R" end
    out[#out + 1] = text .. "  (R = decimal point)"
  end
  local m2, e2, ok2 = exact(2)
  if ok2 and e2 >= 0 and e2 <= 7 then out[#out + 1] = string.format("%02d%d  (3 digits)", m2, e2) end
  local m3, e3, ok3 = exact(3)
  if ok3 and e3 >= 0 and e3 <= 7 then out[#out + 1] = string.format("%03d%d  (4 digits)", m3, e3) end
  for i, v in ipairs(EIA96) do
    local k = math.floor(math.log(value / v, 10) + 0.5)
    local mult = 10 ^ k
    if EIA_LETTER[mult] and math.abs(v * mult - value) < value * 1e-4 then
      out[#out + 1] = string.format("%02d%s  (EIA-96, 1%%)", i, EIA_LETTER[mult])
      break
    end
  end
  if #out == 0 then out[1] = "no exact code: use " .. string.format("%03d%d", m3, e3) end
  return out
end

local CAP_TOL = { B = "+-0.1 pF", C = "+-0.25 pF", D = "+-0.5 pF", F = "+-1%", G = "+-2%", J = "+-5%", K = "+-10%", M = "+-20%", Z = "+80/-20%" }
local TANTALUM_V = { e = 2.5, G = 4, J = 6.3, A = 10, C = 16, D = 20, E = 25, V = 35, H = 50 }

-- decodes the marking of a capacitor: value in farad and lines of explanation
local function decodeCapacitor(code, eng)
  local s = clean(code)
  if s == "" then return nil, "type the code printed on the part" end
  local volt, mant, ex = s:match("^([eGJACDEVH])(%d%d)(%d)$")
  if volt then
    local v = tonumber(mant) * 10 ^ tonumber(ex) * 1e-12
    return v, { "tantalum: " .. volt .. " is " .. TANTALUM_V[volt] .. " V", mant .. " x 10^" .. ex .. " pF" }, TANTALUM_V[volt]
  end
  local u = s:upper()
  local a, e, letter = u:match("^(%d%d)(%d)([BCDFGJKMZ]?)$")
  if a then
    local v = tonumber(a) * 10 ^ tonumber(e) * 1e-12
    local lines = { "3 digits: " .. a .. " x 10^" .. e .. " pF" }
    if letter ~= "" then lines[#lines + 1] = "letter " .. letter .. ": tolerance " .. CAP_TOL[letter] end
    return v, lines
  end
  local lower = s:lower()
  local int, p, frac = lower:match("^(%d*)([pnu])(%d*)$")
  if p and (int ~= "" or frac ~= "") then
    local unit = p == "p" and 1e-12 or (p == "n" and 1e-9 or 1e-6)
    return tonumber((int ~= "" and int or "0") .. "." .. (frac ~= "" and frac or "0")) * unit, { p .. " is the decimal point: " .. p .. "F range" }
  end
  if u:match("^%d%d?$") then return tonumber(u) * 1e-12, { "1 or 2 digits are picofarad" } end
  local plain = eng.parse(s)
  if plain then return plain, { "read as a plain value" } end
  return nil, "not a capacitor code: try 104K, 4n7 or A106"
end

local function capacitorCodes(value)
  local pf = value * 1e12
  if pf < 1 then return { "below 1 pF" } end
  if pf < 10 then
    local text = string.format("%g", pf):gsub("%.", "p")
    if not text:find("p") then text = text .. "p" end
    return { text .. "  (p = decimal point)" }
  end
  local e = math.floor(math.log(pf, 10) + 1e-9) - 1
  local mant = math.floor(pf / 10 ^ e + 0.5)
  if mant >= 100 then mant, e = mant // 10, e + 1 end
  local out = { string.format("%02d%d  (3 digits, pF)", mant, e) }
  if math.abs(mant * 10 ^ e - pf) > pf * 1e-6 then out[#out + 1] = "(rounded to 2 digits)" end
  local n = value * 1e9
  if n >= 1 and n < 1000 then
    local t = string.format("%g", n):gsub("%.", "n")
    if not t:find("n") then t = t .. "n" end
    out[#out + 1] = t .. "  (n = decimal point)"
  end
  return out
end

local IND_TOL = { J = "+-5%", K = "+-10%", M = "+-20%" }

-- decodes the marking of an SMD inductor: value in henry and lines of explanation
local function decodeInductor(code)
  local s = clean(code):upper()
  if s == "" then return nil, "type the code printed on the part" end
  local int, frac = s:match("^(%d*)R(%d*)$")
  if int and (int ~= "" or frac ~= "") then
    return tonumber((int ~= "" and int or "0") .. "." .. (frac ~= "" and frac or "0")) * 1e-6, { "R is the decimal point, microhenry" }
  end
  int, frac = s:match("^(%d*)N(%d*)$")
  if int and (int ~= "" or frac ~= "") then
    return tonumber((int ~= "" and int or "0") .. "." .. (frac ~= "" and frac or "0")) * 1e-9, { "N is the decimal point, nanohenry" }
  end
  local a, e, letter = s:match("^(%d%d)(%d)([JKM]?)$")
  if a then
    local lines = { "3 digits: " .. a .. " x 10^" .. e .. " uH" }
    if letter ~= "" then lines[#lines + 1] = "letter " .. letter .. ": tolerance " .. IND_TOL[letter] end
    return tonumber(a) * 10 ^ tonumber(e) * 1e-6, lines
  end
  return nil, "not an inductor code: try 101, 4R7 or 47N"
end

local function inductorCodes(value)
  local uh = value * 1e6
  if uh < 0.1 then
    local nh = value * 1e9
    local t = string.format("%g", nh):gsub("%.", "N")
    if not t:find("N") then t = t .. "N" end
    return { t .. "  (N = decimal point, nH)" }
  end
  if uh < 10 then
    local t = string.format("%g", uh):gsub("%.", "R")
    if not t:find("R") then t = t .. "R" end
    return { t .. "  (R = decimal point, uH)" }
  end
  local e = math.floor(math.log(uh, 10) + 1e-9) - 1
  local mant = math.floor(uh / 10 ^ e + 0.5)
  if mant >= 100 then mant, e = mant // 10, e + 1 end
  local out = { string.format("%02d%d  (3 digits, uH)", mant, e) }
  if math.abs(mant * 10 ^ e - uh) > uh * 1e-6 then out[#out + 1] = "(rounded to 2 digits)" end
  return out
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local function near(a, b) return a and b and math.abs(a - b) <= 1e-9 * math.max(1, math.abs(b)) end
  local eng = driver.load("eng")
  check(eng ~= nil, "the eng driver is installed for the test")
  if not eng then return end
  -- colour bands
  local v, t = bandsValue({ "brown", "black", "red", "gold" })
  check(near(v, 1000) and t == 5, "brown black red gold is 1k 5%")
  v, t = bandsValue({ "yellow", "violet", "orange", "silver" })
  check(near(v, 47000) and t == 10, "yellow violet orange silver is 47k 10%")
  v, t = bandsValue({ "brown", "black", "black", "red", "brown" })
  check(near(v, 10000) and t == 1, "five bands: brown black black red brown is 10k 1%")
  local tc
  v, t, tc = bandsValue({ "green", "blue", "black", "brown", "violet", "red" })
  check(near(v, 5600) and t == 0.1 and tc == 50, "six bands: 560 x 10 = 5.6k 0.1% 50 ppm")
  v, t = bandsValue({ "red", "red", "gold" })
  check(near(v, 2.2) and t == 20, "three bands: red red gold is 2.2 ohm 20%")
  v = bandsValue({ "orange", "orange", "silver", "gold" })
  check(near(v, 0.33), "silver is x0.01: 0.33 ohm")
  -- value to bands and back
  for _, case in ipairs({ { 4700, 4 }, { 1e6, 4 }, { 0.47, 4 }, { 33, 3 }, { 100000, 5 }, { 4990, 5 }, { 12, 6 }, { 2.2e9, 4 } }) do
    local bands, approx = valueBands(case[1], case[2], 5)
    local back
    if bands then back = bandsValue(bands) end
    check(bands ~= nil and math.abs(back - case[1]) < case[1] * 1e-6, "value " .. case[1] .. " with " .. case[2] .. " bands comes back")
  end
  check(valueBands(0.001, 4) == nil and valueBands(1e11, 4) == nil, "values the bands cannot show are refused")
  local zero = valueBands(0, 4)
  check(zero and zero[1] == "black" and zero[3] == "black", "a zero-ohm link is black bands")
  check(#valueBands(4700, 3) == 3 and #valueBands(4700, 6) == 6, "the bands have the length asked")
  -- SMD resistors
  check(near(decodeResistor("472"), 4700) and near(decodeResistor("1002"), 10000) and near(decodeResistor("000"), 0), "3 and 4 digits")
  check(near(decodeResistor("4R7"), 4.7) and near(decodeResistor("R47"), 0.47) and near(decodeResistor("0R22"), 0.22) and near(decodeResistor("47R"), 47), "R notation")
  check(near(decodeResistor("4K7"), 4700) and near(decodeResistor("1M0"), 1e6), "K and M notation")
  check(#EIA96 == 96 and EIA96[1] == 100 and EIA96[96] == 976, "the EIA-96 table has 96 values")
  check(near(decodeResistor("01A"), 100) and near(decodeResistor("01C"), 10000) and near(decodeResistor("68X"), 49.9), "EIA-96 codes")
  check(near(decodeResistor("96F"), 97600000), "EIA-96: the last value")
  check(near(decodeResistor("101"), 100) and near(decodeResistor("222"), 2200) and near(decodeResistor("510"), 51), "common 3-digit codes")
  check(decodeResistor("97A") == nil and decodeResistor("hello") == nil and decodeResistor("") == nil, "bad resistor codes")
  local codes = resistorCodes(4700)
  check(codes[1]:find("^472") and codes[2]:find("^4701"), "4.7k is 472 and 4701")
  check(resistorCodes(4.7)[1]:find("^4R7"), "4.7 ohm is 4R7")
  local eiaFound = false
  for _, c in ipairs(resistorCodes(10000)) do if c:find("^01C") then eiaFound = true end end
  check(eiaFound, "10k is also 01C in EIA-96")
  check(resistorCodes(0)[1]:find("jumper"), "zero is a jumper")
  -- capacitors
  check(near(decodeCapacitor("104", eng), 1e-7) and near(decodeCapacitor("104K", eng), 1e-7), "104 is 100 nF")
  check(near(decodeCapacitor("473", eng), 4.7e-8) and near(decodeCapacitor("102", eng), 1e-9) and near(decodeCapacitor("225", eng), 2.2e-6), "other 3-digit codes")
  check(near(decodeCapacitor("4n7", eng), 4.7e-9) and near(decodeCapacitor("p47", eng), 4.7e-13) and near(decodeCapacitor("1u5", eng), 1.5e-6), "notation with n p u")
  check(near(decodeCapacitor("22", eng), 2.2e-11), "two digits are picofarad")
  local cv, clines, volts = decodeCapacitor("A106", eng)
  check(near(cv, 1e-5) and volts == 10, "tantalum A106 is 10 uF 10 V")
  cv, clines, volts = decodeCapacitor("e476", eng)
  check(near(cv, 4.7e-5) and volts == 2.5, "tantalum e476 is 47 uF 2.5 V")
  local _, lines = decodeCapacitor("104K", eng)
  check(lines[2] and lines[2]:find("10%%"), "the tolerance letter K is 10%")
  check(decodeCapacitor("hello", eng) == nil, "a bad capacitor code")
  check(capacitorCodes(1e-7)[1]:find("^104") and capacitorCodes(4.7e-9)[1]:find("^472"), "values to capacitor codes")
  check(capacitorCodes(4.7e-12)[1]:find("^4p7"), "4.7 pF is 4p7")
  -- inductors
  check(near(decodeInductor("101"), 1e-4) and near(decodeInductor("100"), 1e-5) and near(decodeInductor("4R7"), 4.7e-6), "inductor codes")
  check(near(decodeInductor("47N"), 4.7e-8) and near(decodeInductor("R47"), 4.7e-7) and near(decodeInductor("2N2"), 2.2e-9), "N and R notation")
  check(near(decodeInductor("220K"), 2.2e-5), "inductor with a tolerance letter")
  check(decodeInductor("xyz") == nil, "a bad inductor code")
  check(inductorCodes(1e-4)[1]:find("^101") and inductorCodes(4.7e-6)[1]:find("^4R7") and inductorCodes(4.7e-8)[1]:find("^47N"), "values to inductor codes")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("components needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("components: " .. tostring(uiErr))
  return
end
local eng, engErr = driver.load("eng")
if not eng then
  print("components: " .. tostring(engErr))
  return
end

local W, H = 240, 135

-- the text with which a number is shown: "4.7k ohm"
local function show(value, unit)
  return eng.format(value) .. unit
end

-- ---- the colour band screen (a resistor, or an inductor with colour bands in microhenry) ----

local function bandsScreen(n, inductor)
  local roles = ROLES[n]
  local colours = {}
  if n == 3 then colours = { "brown", "black", "red" }
  elseif n == 4 then colours = { "brown", "black", "red", "gold" }
  elseif n == 5 then colours = { "brown", "black", "black", "red", "brown" }
  else colours = { "brown", "black", "black", "red", "brown", "red" } end
  local sel = 1
  local function indexIn(list, name)
    for i, v in ipairs(list) do if v == name then return i end end
    return 1
  end
  local function draw()
    gfx.clear(0x0a0e18)
    ui.label(4, 3, (inductor and "INDUCTOR " or "RESISTOR ") .. n .. " bands", 0xe8ecf4)
    -- the part: wires, the body and the bands
    gfx.fill(6, 33, 228, 3, 0x9098a8)
    local bodyX, bodyW = 54, 132
    gfx.fill(bodyX, 22, bodyW, 24, inductor and 0x3a6a8a or 0xd8c08a)
    gfx.disc(bodyX, 34, 12, inductor and 0x3a6a8a or 0xd8c08a)
    gfx.disc(bodyX + bodyW, 34, 12, inductor and 0x3a6a8a or 0xd8c08a)
    local groupEnd = n <= 4 and n - (n >= 4 and 1 or 0) or n - 2
    local xs = {}
    local step = (bodyW - 26 - 8 - 14) / (n - 1)  -- the bands are spread over the body, the tolerance a little apart
    local x = bodyX + 13
    for i = 1, n do
      xs[i] = math.floor(x)
      x = x + step + ((i == groupEnd) and 14 or 0)
    end
    for i = 1, n do
      local name = colours[i]
      if name == "none" then
        gfx.rect(xs[i], 22, 8, 24, 0x7a6a40)
      else
        gfx.fill(xs[i], 22, 8, 24, COLORS[name] or 0xff00ff)
      end
      if i == sel then
        gfx.triangle(xs[i] + 4, 50, xs[i] - 1, 57, xs[i] + 9, 57, 0xffe060)
      end
    end
    -- the result
    local value, tol, tempco = bandsValue(colours)
    if inductor then
      ui.label(4, 66, eng.format(value * 1e-6) .. "H", 0x60e090, 2)
    else
      ui.label(4, 66, eng.format(value) .. " ohm", 0x60e090, 2)
    end
    local info = "tolerance +-" .. tol .. "%"
    if tempco then info = info .. "  " .. tempco .. " ppm/K" end
    ui.label(4, 86, info, 0xe8ecf4)
    local lo, hi = value * (1 - tol / 100), value * (1 + tol / 100)
    if inductor then
      ui.label(4, 97, "from " .. eng.format(lo * 1e-6) .. "H to " .. eng.format(hi * 1e-6) .. "H", 0x8a94aa)
    else
      ui.label(4, 97, "from " .. eng.format(lo) .. " to " .. eng.format(hi) .. " ohm", 0x8a94aa)
      local series = eng.inSeries(value, "E24") and (eng.inSeries(value, "E12") and "E12 / E24" or "E24")
      series = series or (eng.inSeries(value, "E96") and "E96") or "no standard series"
      ui.label(4, 108, "series: " .. series, 0x8a94aa)
    end
    ui.label(120, 108, roles[sel] and (ROLE_NAME[roles[sel]] .. ": " .. colours[sel]) or "", 0xffe060)
    ui.label(4, H - 10, "a d band  w s colour  v value  b bands  q back", 0x8a94aa)
    gfx.flush()
  end
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" or k == "q" then return true end
      if #k == 1 then k = k:lower() end
      if k == "a" or k == "left" then sel = math.max(1, sel - 1)
      elseif k == "d" or k == "right" then sel = math.min(n, sel + 1)
      elseif k == "w" or k == "up" or k == "s" or k == "down" then
        local list = CHOICES[roles[sel]]
        local i = indexIn(list, colours[sel])
        i = (k == "w" or k == "up") and (i - 2) % #list + 1 or i % #list + 1
        colours[sel] = list[i]
      elseif k == "b" then
        return false
      elseif k == "v" then
        local text = ui.prompt(inductor and "value in henry (4.7u, 100u)" or "value in ohm (4k7)", "", 12)
        local val = text and eng.parse(text)
        if val and inductor then val = val * 1e6 end  -- the bands of an inductor give microhenry
        if val then
          local tolNow = select(2, bandsValue(colours)) or 5
          local bands, approx = valueBands(val, n, tolNow == 20 and 5 or tolNow)
          if bands then
            for i = 1, n do colours[i] = bands[i] or colours[i] end
            if n == 4 and not bands[4] then colours[4] = "gold" end
          else
            ui.message("Cannot show", { approx })
          end
        elseif text then
          ui.message("Not a value", { inductor and "try 4.7u, 100u, 1m" or "try 4k7, 100, 2.2M" })
        end
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end

-- ---- the code screen (SMD resistor, capacitor, SMD inductor) ----

local KINDS = {
  resistor = { title = "SMD RESISTOR", unit = "ohm", body = 0x101010, text = 0xe0e0e0, example = "472", help = "472  1002  4R7  01C",
    decode = function(code) return decodeResistor(code) end, codes = resistorCodes, parse = function(t) return eng.parse(t) end,
    format = function(v) return eng.format(v) .. " ohm" end },
  capacitor = { title = "CAPACITOR", unit = "F", body = 0xb89860, text = 0x302010, example = "104K", help = "104K  4n7  22  A106",
    decode = function(code) return decodeCapacitor(code, eng) end, codes = capacitorCodes, parse = function(t) return eng.parse(t) end,
    format = function(v) return eng.format(v) .. "F" end },
  inductor = { title = "SMD INDUCTOR", unit = "H", body = 0x484c58, text = 0xe8e8e8, example = "101", help = "101  4R7  47N  220K",
    decode = function(code) return decodeInductor(code) end, codes = inductorCodes, parse = function(t) return eng.parse(t) end,
    format = function(v) return eng.format(v) .. "H" end },
}

local function codeScreen(kind)
  local K = KINDS[kind]
  local code, value, lines, problem, volts = K.example, nil, nil, nil, nil
  local codes
  local function decode()
    value, lines, volts = K.decode(code)
    if not value then
      problem, lines = lines, nil
    else
      problem = nil
      codes = K.codes(value)
    end
  end
  decode()
  local function draw()
    gfx.clear(0x0a0e18)
    ui.label(4, 3, K.title, 0xe8ecf4)
    -- the part with its marking
    local x, y, w, h = 8, 20, 64, 30
    if kind == "capacitor" then gfx.fill(x, y, w, h, K.body) else gfx.fill(x, y, w, h, K.body) end
    gfx.fill(x - 4, y, 4, h, 0xc0c8d0)
    gfx.fill(x + w, y, 4, h, 0xc0c8d0)
    local shown = #code <= 5 and code or code:sub(1, 5)
    ui.center(y + 8, shown, K.text, 2, x, x + w)
    if value then
      ui.label(84, 22, K.format(value), 0x60e090, 2)
      if volts then ui.label(84, 40, volts .. " V (tantalum)", 0xe8ecf4) end
      local row = 60
      for _, l in ipairs(lines or {}) do
        ui.label(4, row, l, 0xe8ecf4)
        row = row + 10
      end
      ui.label(4, row + 4, "also written as:", 0x8a94aa)
      row = row + 14
      for i, c in ipairs(codes) do
        if i <= 3 then ui.label(4, row, c, 0xf0d060) row = row + 10 end
      end
    else
      ui.label(84, 24, problem or "", 0xff6060)
      ui.label(4, 62, "examples: " .. K.help, 0x8a94aa)
    end
    ui.label(4, H - 10, "c type code  v type value  q back", 0x8a94aa)
    gfx.flush()
  end
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" or k == "q" then return end
      if k == "c" then
        local text = ui.prompt("code on the part", code, 8)
        if text then code = clean(text) decode() end
      elseif k == "v" then
        local text = ui.prompt("value (" .. K.unit .. ")", "", 12)
        local v = text and K.parse(text)
        if v and v >= 0 then
          local list = K.codes(v)
          code = list[1]:match("^(%S+)") or code
          decode()
        elseif text then
          ui.message("Not a value", { "try 4k7, 100n, 4.7u" })
        end
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end

local w, h = ui.open()
if not w then
  print("components: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local last = 1
  while true do
    local pick = ui.choose("Components", { "Resistor, colour bands", "Resistor, SMD code", "Capacitor, code", "Inductor, SMD code",
      "Inductor, colour bands" }, { selected = last })
    if not pick then return end
    last = pick
    if pick == 1 or pick == 5 then
      local nb = pick == 5 and 4 or nil
      while true do
        if not nb then
          local c = ui.choose("Number of bands", { "3 bands", "4 bands (common)", "5 bands (precision)", "6 bands (with ppm)" }, { selected = 2 })
          if not c then break end
          nb = c + 2
        end
        local back = bandsScreen(nb, pick == 5)
        nb = nil
        if back or pick == 5 then break end
      end
    elseif pick == 2 then codeScreen("resistor")
    elseif pick == 3 then codeScreen("capacitor")
    elseif pick == 4 then codeScreen("inductor") end
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("components: " .. tostring(problem)) end
