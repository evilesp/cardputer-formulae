#!lua
-- divider: voltage divider calculator. Vout = Vin x R2 / (R1 + R2). Three jobs:
--   * Vout from Vin, R1 and R2
--   * R2 for a wanted Vout, with the nearest standard value (E12, E24 or E96) and the Vout you really get
--   * the best pair of standard resistors for a wanted Vout (searched in the series you choose)
-- Values are typed like 4k7, 100k, 3.3. ctrl-q goes back. Needs the graphics, the ui package and the eng driver.
-- Run it with --selftest to check the formulas and the search.

local function vout(vin, r1, r2) return vin * r2 / (r1 + r2) end

-- R2 for a wanted Vout with a given R1, or nil when it is not possible
local function r2For(vin, want, r1)
  if want <= 0 or want >= vin then return nil end
  return r1 * want / (vin - want)
end

-- the pairs of standard values (r1, r2) that give the wanted output, best first: { r1, r2, vout, errorPercent }.
-- Both resistors are from 1k to 1M (the divider should not load the source, nor be too weak against a load).
local function bestPairs(eng, vin, want, series, count)
  local list = eng.series(series)
  local values = {}
  for decade = 3, 5 do
    for _, x in ipairs(list) do values[#values + 1] = x * 10 ^ decade end
  end
  values[#values + 1] = 1e6
  local found = {}
  for _, a in ipairs(values) do
    local target = a * want / (vin - want)
    if target >= 1e3 / 1.2 and target <= 1e6 * 1.2 then
      for _, b in ipairs(values) do
        local ratio = b / target
        if ratio > 0.97 and ratio < 1.03 then
          local v = vout(vin, a, b)
          found[#found + 1] = { a, b, v, (v / want - 1) * 100 }
        end
      end
    end
  end
  table.sort(found, function(x, y)
    local ex, ey = math.abs(x[4]), math.abs(y[4])
    if math.abs(ex - ey) > 1e-9 then return ex < ey end
    return x[1] + x[2] > y[1] + y[2]  -- the same error: the larger resistors waste less current
  end)
  local out = {}
  for i = 1, math.min(count, #found) do out[i] = found[i] end
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
  local eng = driver.load("eng")
  check(eng ~= nil, "the eng driver is installed for the test")
  if not eng then return end
  local function near(a, b, e) return a and math.abs(a - b) <= (e or 1e-9) * math.max(1, math.abs(b)) end
  check(near(vout(5, 10e3, 10e3), 2.5) and near(vout(12, 20e3, 10e3), 4), "Vout")
  check(near(r2For(5, 2.5, 10e3), 10e3) and near(r2For(12, 4, 20e3), 10e3), "R2 for a wanted Vout")
  check(r2For(5, 5, 1e3) == nil and r2For(5, 0, 1e3) == nil and r2For(5, 6, 1e3) == nil, "impossible outputs")
  local pairs3 = bestPairs(eng, 5, 3.3, "E24", 3)
  check(#pairs3 == 3 and math.abs(pairs3[1][4]) < 1, "pairs for 3.3 V from 5 V in E24 (error " .. (pairs3[1] and pairs3[1][4] or "?") .. "%)")
  check(math.abs(pairs3[1][4]) <= math.abs(pairs3[2][4]) and math.abs(pairs3[2][4]) <= math.abs(pairs3[3][4]), "best first")
  local e96 = bestPairs(eng, 5, 3.3, "E96", 1)
  check(#e96 == 1 and math.abs(e96[1][4]) < 0.2, "E96 gets closer than 0.2% (" .. (e96[1] and e96[1][4] or "?") .. ")")
  check(#bestPairs(eng, 5, 4.99, "E24", 3) >= 0, "no crash for a wanted Vout close to Vin")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("divider needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("divider: " .. tostring(uiErr))
  return
end
local eng, engErr = driver.load("eng")
if not eng then
  print("divider: " .. tostring(engErr))
  return
end

local W, H = 240, 135

-- asks for a number; nil when the user backs out
local function ask(title, default, unit)
  while true do
    local text = ui.prompt(title, default or "", 14)
    if text == nil then return nil end
    local v = eng.parse(text)
    if v then return v end
    ui.message("Not a number", { "try 4k7, 3.3, 100k" })
  end
end

-- a screen with lines of result; any key goes back
local function result(title, lines)
  while true do
    gfx.clear(0x0a0e18)
    ui.label(4, 3, title, 0xe8ecf4)
    for i, l in ipairs(lines) do ui.label(4, 16 + (i - 1) * 11, l, i == 1 and 0x60e090 or 0xe8ecf4) end
    ui.label(4, H - 10, "any key: back", 0x8a94aa)
    gfx.flush()
    if key.poll() then return end
    sys.sleep(40)
  end
end

local function modeVout()
  local vin = ask("Vin in volt", "5")
  if not vin then return end
  local r1 = ask("R1 in ohm", "10k")
  if not r1 then return end
  local r2 = ask("R2 in ohm", "10k")
  if not r2 then return end
  if r1 + r2 <= 0 then return ui.message("Error", { "R1 + R2 must be above 0" }) end
  local vo = vout(vin, r1, r2)
  local i = vin / (r1 + r2)
  result("VOUT", {
    "Vout = " .. eng.format(vo) .. "V",
    "Vin " .. eng.format(vin) .. "V  R1 " .. eng.format(r1) .. "  R2 " .. eng.format(r2),
    "current " .. eng.format(i) .. "A  power " .. eng.format(vin * i) .. "W",
    "source resistance " .. eng.format(eng.parallel(r1, r2)) .. " ohm",
    "(a load on Vout lowers it)",
  })
end

local function modeR2()
  local vin = ask("Vin in volt", "5")
  if not vin then return end
  local want = ask("wanted Vout in volt", "3.3")
  if not want then return end
  local r1 = ask("R1 in ohm", "10k")
  if not r1 then return end
  local r2 = r2For(vin, want, r1)
  if not r2 then return ui.message("Error", { "Vout must be between 0 and Vin" }) end
  local lines = { "R2 = " .. eng.format(r2) .. " ohm", "R1 " .. eng.format(r1) .. " ohm, Vin " .. eng.format(vin) .. "V" }
  for _, name in ipairs({ "E12", "E24", "E96" }) do
    local best, err = eng.nearest(r2, name)
    local v = vout(vin, r1, best)
    lines[#lines + 1] = string.format("%s: %s -> %sV (%+.2f%%)", name, eng.format(best), eng.format(v, 4), (v / want - 1) * 100)
  end
  result("R2 FOR A VOUT", lines)
end

local function modeBest()
  local vin = ask("Vin in volt", "5")
  if not vin then return end
  local want = ask("wanted Vout in volt", "3.3")
  if not want then return end
  if want <= 0 or want >= vin then return ui.message("Error", { "Vout must be between 0 and Vin" }) end
  local pick = ui.choose("Series", { "E12 (10%)", "E24 (5%)", "E96 (1%)" }, { selected = 2 })
  if not pick then return end
  local series = ({ "E12", "E24", "E96" })[pick]
  gfx.clear(0x0a0e18)
  ui.label(4, 60, "searching...", 0xe8ecf4)
  gfx.flush()
  local list = bestPairs(eng, vin, want, series, 4)
  local lines = { "best pairs in " .. series .. ", " .. eng.format(vin) .. "V -> " .. eng.format(want) .. "V" }
  for i, p in ipairs(list) do
    lines[#lines + 1] = string.format("R1 %s  R2 %s  %sV %+.2f%%", eng.format(p[1]), eng.format(p[2]), eng.format(p[3], 4), p[4])
  end
  if #list == 0 then lines[#lines + 1] = "no pair of 1k to 1M found" end
  result("BEST PAIR", lines)
end

local w, h = ui.open()
if not w then
  print("divider: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local last = 1
  while true do
    local pick = ui.choose("Voltage divider", { "Vout from R1 and R2", "R2 for a wanted Vout", "Best pair of standard values" }, { selected = last })
    if not pick then return end
    last = pick
    if pick == 1 then modeVout() elseif pick == 2 then modeR2() else modeBest() end
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("divider: " .. tostring(problem)) end
