#!lua
-- units: converts between units of length, mass, temperature, speed, area, volume, time, data and energy.
-- usage: units VALUE FROM TO      for example: units 10 km mi   units 98.6 F C   units 1.5 GB MB
--        units list               shows every unit it knows
-- Run it with --selftest to check the conversions.

-- each unit is a factor to its group's base unit (metre, kilogram, m/s, m2, litre, second, byte, joule); temperature is
-- not a factor and has its own rule
local GROUPS = {
  length = { m = 1, km = 1000, cm = 0.01, mm = 0.001, um = 1e-6, mi = 1609.344, yd = 0.9144, ft = 0.3048, ["in"] = 0.0254,
             nmi = 1852, au = 1.495978707e11, ly = 9.4607304725808e15 },
  mass = { kg = 1, g = 0.001, mg = 1e-6, t = 1000, lb = 0.45359237, oz = 0.028349523125, st = 6.35029318 },
  speed = { ["m/s"] = 1, ["km/h"] = 1 / 3.6, mph = 0.44704, kn = 1852 / 3600, ["ft/s"] = 0.3048 },
  area = { m2 = 1, km2 = 1e6, cm2 = 1e-4, ha = 1e4, a = 100, acre = 4046.8564224, ft2 = 0.09290304, mi2 = 2589988.110336 },
  volume = { l = 1, ml = 0.001, m3 = 1000, cl = 0.01, gal = 3.785411784, qt = 0.946352946, pt = 0.473176473,
             cup = 0.2365882365, floz = 0.0295735295625 },
  time = { s = 1, ms = 0.001, min = 60, h = 3600, d = 86400, wk = 604800, yr = 31557600 },
  data = { B = 1, KB = 1000, MB = 1e6, GB = 1e9, TB = 1e12, KiB = 1024, MiB = 1048576, GiB = 1073741824, bit = 0.125 },
  energy = { J = 1, kJ = 1000, cal = 4.184, kcal = 4184, Wh = 3600, kWh = 3.6e6 },
}
local TEMPS = { C = true, F = true, K = true }

-- the group of a unit and its factor; the exact spelling first, then without regard to case (km, KM and Km are one)
local function findUnit(name)
  for g, units in pairs(GROUPS) do
    if units[name] then return g, units[name] end
  end
  local lower = name:lower()
  for g, units in pairs(GROUPS) do
    for u, f in pairs(units) do
      if u:lower() == lower then return g, f end
    end
  end
  return nil
end

local function toKelvin(v, u)
  if u == "C" then return v + 273.15 elseif u == "F" then return (v - 32) * 5 / 9 + 273.15 end
  return v
end

local function fromKelvin(k, u)
  if u == "C" then return k - 273.15 elseif u == "F" then return (k - 273.15) * 9 / 5 + 32 end
  return k
end

-- the value in unit `to`, or nil and why
local function convert(value, from, to)
  local tf, tt = from:upper(), to:upper()
  if TEMPS[tf] or TEMPS[tt] then
    if not (TEMPS[tf] and TEMPS[tt]) then return nil, "a temperature converts only to C, F or K" end
    return fromKelvin(toKelvin(value, tf), tt)
  end
  local g1, f1 = findUnit(from)
  local g2, f2 = findUnit(to)
  if not g1 then return nil, "unknown unit: " .. from end
  if not g2 then return nil, "unknown unit: " .. to end
  if g1 ~= g2 then return nil, from .. " is " .. g1 .. " and " .. to .. " is " .. g2 end
  return value * f1 / f2
end

-- 12 significant digits at most, without trailing zeros
local function fmt(v)
  if v ~= v then return "nan" end
  local s = string.format("%.10g", v)
  return s
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local function near(a, b) return a and math.abs(a - b) < 1e-6 * math.max(1, math.abs(b)) end
  check(near(convert(10, "km", "mi"), 6.213711922), "10 km is 6.21 miles")
  check(near(convert(98.6, "F", "C"), 37), "98.6 F is 37 C")
  check(near(convert(0, "C", "K"), 273.15), "0 C is 273.15 K")
  check(near(convert(1.5, "GB", "MB"), 1500), "1.5 GB is 1500 MB")
  check(near(convert(1, "GiB", "MiB"), 1024), "1 GiB is 1024 MiB")
  check(near(convert(100, "km/h", "m/s"), 27.7777778), "100 km/h in m/s")
  check(near(convert(1, "KM", "m"), 1000), "the case of a unit does not matter")
  check(convert(1, "kg", "m") == nil, "kilograms are not metres")
  check(convert(1, "C", "kg") == nil, "a temperature is not a mass")
  check(convert(1, "parsec", "m") == nil, "an unknown unit is refused")
  check(fmt(6.2137119223733) == "6.213711922", "ten significant digits")
  if failed == 0 then print("selftest ok") end
  return
end

if arg[1] == "list" then
  local names = {}
  for g in pairs(GROUPS) do names[#names + 1] = g end
  table.sort(names)
  print("temperature: C F K")
  for _, g in ipairs(names) do
    local units = {}
    for u in pairs(GROUPS[g]) do units[#units + 1] = u end
    table.sort(units)
    print(g .. ": " .. table.concat(units, " "))
  end
  return
end

local value = tonumber(arg[1] or "")
if not value or not arg[2] or not arg[3] then
  print("usage: units VALUE FROM TO   (units 10 km mi)")
  print("       units list")
  return
end
local result, why = convert(value, arg[2], arg[3])
if not result then
  print("units: " .. why)
  return
end
print(fmt(value) .. " " .. arg[2] .. " = " .. fmt(result) .. " " .. arg[3])
