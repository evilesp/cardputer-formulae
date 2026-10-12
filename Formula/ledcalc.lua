#!lua
-- ledcalc: the series resistor for an LED (or several LEDs in series). Type the supply voltage, choose the colour of the LED
-- (or type its forward voltage), the current and the number of LEDs in a row; it shows the exact resistor, the next standard
-- values (E12 and E24) with the current and the heat you really get, and which resistor power rating to use. ctrl-q quits.
-- Needs the graphics, the ui package and the eng driver. Run it with --selftest to check the formulas.

local COLOURS = {
  { "red", 1.9 }, { "orange", 2.0 }, { "yellow", 2.1 }, { "green", 2.2 }, { "blue", 3.1 }, { "white", 3.2 }, { "infrared", 1.3 },
  { "your own value", nil },
}

-- the resistor in ohm for a supply, a forward voltage per LED, the number of LEDs and the current in ampere; nil when the supply
-- is too low
local function resistorFor(supply, vf, count, current)
  local drop = supply - count * vf
  if drop <= 0 or current <= 0 then return nil end
  return drop / current
end

-- what a real resistor gives: the current in ampere and the power in watt
local function actual(supply, vf, count, r)
  local i = (supply - count * vf) / r
  return i, i * i * r
end

-- the smallest resistor power rating (watt, with its name) that has twice the power as room
local RATINGS = { { 0.125, "1/8 W" }, { 0.25, "1/4 W" }, { 0.5, "1/2 W" }, { 1, "1 W" }, { 2, "2 W" } }
local function rating(p)
  for _, r in ipairs(RATINGS) do
    if r[1] >= 2 * p then return r[2] end
  end
  return "over 2 W"
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local eng = driver.load("eng")
  check(eng ~= nil, "the eng driver is installed for the test")
  if not eng then return end
  local function near(a, b) return a and math.abs(a - b) <= 1e-9 * math.max(1, math.abs(b)) end
  check(near(resistorFor(5, 2, 1, 0.01), 300), "5 V, a 2 V LED, 10 mA is 300 ohm")
  check(near(resistorFor(12, 2, 3, 0.02), 300), "three LEDs in series")
  check(resistorFor(3, 3.2, 1, 0.01) == nil and resistorFor(5, 2, 1, 0) == nil, "a supply that is too low")
  local i, p = actual(5, 2, 1, 330)
  check(near(i, 3 / 330) and near(p, 9 / 330), "current and power of a real resistor")
  local best, _, below, above = eng.nearest(300, "E24")
  check(best == 300 and above == 300, "300 ohm is in E24")
  local _, _, b12, a12 = eng.nearest(300, "E12")
  check(a12 == 330 and b12 == 270, "E12 around 300 ohm: 270 and 330")
  check(rating(0.03) == "1/8 W" and rating(0.2) == "1/2 W" and rating(5) == "over 2 W", "ratings")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("ledcalc needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("ledcalc: " .. tostring(uiErr))
  return
end
local eng, engErr = driver.load("eng")
if not eng then
  print("ledcalc: " .. tostring(engErr))
  return
end

local W, H = 240, 135

local function ask(title, default)
  while true do
    local text = ui.prompt(title, default or "", 12)
    if text == nil then return nil end
    local v = eng.parse(text)
    if v and v > 0 then return v end
    ui.message("Not a number", { "try 5, 12, 3.3, 20m" })
  end
end

local function show(supply, vf, count, current, colour)
  local exact = resistorFor(supply, vf, count, current)
  while true do
    gfx.clear(0x0a0e18)
    ui.label(4, 3, "LED RESISTOR", 0xe8ecf4)
    ui.label(120, 3, string.format("%gV, %s %gV x%d", supply, colour, vf, count), 0x8a94aa)
    if not exact then
      ui.label(4, 30, "the supply is too low for", 0xff6060)
      ui.label(4, 42, count .. " LED" .. (count > 1 and "s" or "") .. " of " .. vf .. " V each", 0xff6060)
    else
      ui.label(4, 16, "exact: " .. eng.format(exact, 4) .. " ohm at " .. eng.format(current) .. "A", 0x60e090, 1)
      local row = 32
      for _, name in ipairs({ "E24", "E12" }) do
        local _, _, below, above = eng.nearest(exact, name)
        for _, r in ipairs({ above, below }) do
          if r and r > 0 then
            local i, p = actual(supply, vf, count, r)
            local text = string.format("%s %s%s: %smA  %smW", name, eng.format(r), r == above and "+" or "-", eng.format(i * 1000, 3), eng.format(p * 1000, 2))
            ui.label(4, row, text, r == above and 0xf0d060 or 0xe8ecf4)
            row = row + 11
          end
        end
      end
      local _, pe = actual(supply, vf, count, eng.nearest(exact, "E24"))
      ui.label(4, row + 4, "use a " .. rating(pe) .. " resistor", 0xe8ecf4)
      ui.label(4, row + 15, "+ is safer (a little less current)", 0x8a94aa)
      ui.label(4, row + 26, "- is brighter, a little more current", 0x8a94aa)
    end
    ui.label(4, H - 10, "any key: back", 0x8a94aa)
    gfx.flush()
    if key.poll() then return end
    sys.sleep(40)
  end
end

local w, h = ui.open()
if not w then
  print("ledcalc: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local supply, last, count, current = 5, 1, 1, 0.010
  while true do
    local items = {}
    for i, c in ipairs(COLOURS) do items[i] = c[2] and string.format("%s (%.1f V)", c[1], c[2]) or c[1] end
    local pick = ui.choose("LED colour", items, { selected = last })
    if not pick then return end
    last = pick
    local vf = COLOURS[pick][2]
    if not vf then
      vf = ask("forward voltage in volt", "2.0")
      if not vf then goto continue end
    end
    do
      local s = ask("supply voltage in volt", tostring(supply))
      if not s then goto continue end
      supply = s
      local c = ask("current in ampere (10m)", eng.format(current))
      if not c then goto continue end
      current = c
      local n = ask("LEDs in series", tostring(count))
      if not n then goto continue end
      count = math.max(1, math.floor(n))
      show(supply, vf, count, current, COLOURS[pick][1])
    end
    ::continue::
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("ledcalc: " .. tostring(problem)) end
