#!lua
-- rcfilter: calculators for timing and filtering parts. Pick one:
--   * RC filter: the cutoff frequency from R and C, and the time constant
--   * RC filter: the R you need for a cutoff, with the nearest standard values
--   * LC circuit: the resonance frequency and the characteristic impedance
--   * 555 timer, astable: the frequency, the period and the duty cycle from R1, R2 and C
--   * 555 timer, monostable: the length of the pulse from R and C
--   * charging time of a capacitor through a resistor
-- Values are typed like 4k7, 100n, 2u2. ctrl-q goes back. Needs the graphics, the ui package and the eng driver.
-- Run it with --selftest to check the formulas.

local TWO_PI = 2 * math.pi

local function cutoff(r, c) return 1 / (TWO_PI * r * c) end
local function resistorForCutoff(f, c) return 1 / (TWO_PI * f * c) end
local function resonance(l, c) return 1 / (TWO_PI * math.sqrt(l * c)) end
local function impedance(l, c) return math.sqrt(l / c) end
-- the 555 as an astable: the frequency, the high time, the low time and the duty cycle (percent)
local function astable(r1, r2, c)
  local high, low = 0.693 * (r1 + r2) * c, 0.693 * r2 * c
  return 1 / (high + low), high, low, high / (high + low) * 100
end
local function monostable(r, c) return 1.1 * r * c end
-- the time for a capacitor to reach a part of the supply through a resistor: t = -RC ln(1 - part)
local function chargeTime(r, c, part) return -r * c * math.log(1 - part) end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local function near(a, b, e) return a and math.abs(a - b) <= (e or 1e-6) * math.max(1e-30, math.abs(b)) end
  check(near(cutoff(1e3, 1e-7), 1591.549, 1e-5), "1k and 100n cut off at 1.59 kHz")
  check(near(resistorForCutoff(1591.549431, 1e-7), 1000, 1e-6), "the R for a cutoff")
  check(near(resonance(1e-3, 1e-6), 5032.921, 1e-5), "1 mH and 1 uF resonate at 5.03 kHz")
  check(near(impedance(1e-3, 1e-6), 31.6228, 1e-5), "characteristic impedance")
  local f, high, low, duty = astable(1e3, 10e3, 1e-7)
  check(near(f, 1 / (0.693 * (11e3 + 10e3) * 1e-7), 1e-9) and near(duty, 11 / 21 * 100, 1e-9), "555 astable")
  check(near(high, 0.693 * 11e3 * 1e-7) and near(low, 0.693 * 10e3 * 1e-7), "555 high and low times")
  check(near(monostable(100e3, 1e-5), 1.1), "555 monostable: 100k and 10u is 1.1 s")
  check(near(chargeTime(1e3, 1e-6, 0.632121), 1e-3, 1e-4) and near(chargeTime(1e3, 1e-6, 0.99), 4.60517e-3, 1e-5), "charging time")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("rcfilter needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("rcfilter: " .. tostring(uiErr))
  return
end
local eng, engErr = driver.load("eng")
if not eng then
  print("rcfilter: " .. tostring(engErr))
  return
end

local W, H = 240, 135

local function ask(title, default)
  while true do
    local text = ui.prompt(title, default or "", 14)
    if text == nil then return nil end
    local v = eng.parse(text)
    if v and v > 0 then return v end
    ui.message("Not a number", { "try 4k7, 100n, 2u2" })
  end
end

local function result(title, lines)
  while true do
    gfx.clear(0x0a0e18)
    ui.label(4, 3, title, 0xe8ecf4)
    for i, l in ipairs(lines) do ui.label(4, 18 + (i - 1) * 12, l, i == 1 and 0x60e090 or 0xe8ecf4, 1) end
    ui.label(4, H - 10, "any key: back", 0x8a94aa)
    gfx.flush()
    if key.poll() then return end
    sys.sleep(40)
  end
end

local function hz(f) return eng.format(f, 4) .. "Hz" end
local function sec(t) return eng.format(t, 4) .. "s" end

local JOBS = {
  { "RC filter: cutoff", function()
      local r = ask("R in ohm", "10k") if not r then return end
      local c = ask("C in farad", "100n") if not c then return end
      result("RC FILTER", { "cutoff " .. hz(cutoff(r, c)), "R " .. eng.format(r) .. " ohm   C " .. eng.format(c) .. "F",
        "time constant " .. sec(r * c), "the output is 3 dB down at the cutoff,", "low-pass or high-pass: the same frequency" })
    end },
  { "RC filter: R for a cutoff", function()
      local f = ask("cutoff in hertz", "1k") if not f then return end
      local c = ask("C in farad", "100n") if not c then return end
      local r = resistorForCutoff(f, c)
      local lines = { "R = " .. eng.format(r, 4) .. " ohm", "for " .. hz(f) .. " with " .. eng.format(c) .. "F" }
      for _, name in ipairs({ "E12", "E24", "E96" }) do
        local best = eng.nearest(r, name)
        lines[#lines + 1] = name .. ": " .. eng.format(best) .. " ohm gives " .. hz(cutoff(best, c))
      end
      result("R FOR A CUTOFF", lines)
    end },
  { "LC resonance", function()
      local l = ask("L in henry", "1m") if not l then return end
      local c = ask("C in farad", "1u") if not c then return end
      result("LC CIRCUIT", { "resonance " .. hz(resonance(l, c)), "L " .. eng.format(l) .. "H   C " .. eng.format(c) .. "F",
        "impedance " .. eng.format(impedance(l, c), 4) .. " ohm", "period " .. sec(1 / resonance(l, c)) })
    end },
  { "555 astable", function()
      local r1 = ask("R1 in ohm", "1k") if not r1 then return end
      local r2 = ask("R2 in ohm", "10k") if not r2 then return end
      local c = ask("C in farad", "100n") if not c then return end
      local f, high, low, duty = astable(r1, r2, c)
      result("555 ASTABLE", { hz(f), "high " .. sec(high) .. "  low " .. sec(low), string.format("duty cycle %.1f%%", duty),
        "period " .. sec(1 / f), "the duty cycle is always above 50%", "(R2 much bigger than R1 is near 50%)" })
    end },
  { "555 monostable", function()
      local r = ask("R in ohm", "100k") if not r then return end
      local c = ask("C in farad", "10u") if not c then return end
      result("555 MONOSTABLE", { "pulse " .. sec(monostable(r, c)), "T = 1.1 x R x C", "R " .. eng.format(r) .. " ohm   C " .. eng.format(c) .. "F" })
    end },
  { "Charging time", function()
      local r = ask("R in ohm", "10k") if not r then return end
      local c = ask("C in farad", "100u") if not c then return end
      result("CHARGING", { "RC = " .. sec(r * c), "63% after " .. sec(chargeTime(r, c, 0.632121)), "90% after " .. sec(chargeTime(r, c, 0.9)),
        "99% after " .. sec(chargeTime(r, c, 0.99)), "full in about 5 RC = " .. sec(5 * r * c) })
    end },
}

local w, h = ui.open()
if not w then
  print("rcfilter: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local items = {}
  for i, j in ipairs(JOBS) do items[i] = j[1] end
  local last = 1
  while true do
    local pick = ui.choose("Timing and filters", items, { selected = last })
    if not pick then return end
    last = pick
    JOBS[pick][2]()
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("rcfilter: " .. tostring(problem)) end
