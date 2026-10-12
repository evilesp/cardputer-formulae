#!lua
-- eseries: standard values of resistors and capacitors (the E series: E3, E6, E12, E24, E48, E96, E192).
--   * the nearest standard value to what you need, and the one below and above it, with the error in percent
--   * two parts that make a value: in series (A + B) or in parallel (A || B), found among the E12 values
--   * a list of the values of a series
-- Values are typed like 4k7, 100n, 2.2u. ctrl-q goes back. Needs the graphics, the ui package and the eng driver.
-- Run it with --selftest to check the search.

-- the best ways to make `target` from two values of a list (spread over the decades) joined in series or in parallel:
-- { a, b, how ("+" or "||"), result, errorPercent }, best first
local function twoParts(eng, target, name, count)
  local list = eng.series(name)
  local decade = math.floor(math.log(target, 10) + 1e-9)
  local values = {}
  for d = decade - 3, decade + 2 do
    for _, x in ipairs(list) do values[#values + 1] = x * 10 ^ d end
  end
  local found = {}
  for i = 1, #values do
    local a = values[i]
    for j = i, #values do
      local b = values[j]
      local s = a + b
      if math.abs(s / target - 1) < 0.05 then found[#found + 1] = { a, b, "+", s, (s / target - 1) * 100 } end
      local p = a * b / (a + b)
      if math.abs(p / target - 1) < 0.05 then found[#found + 1] = { a, b, "||", p, (p / target - 1) * 100 } end
    end
  end
  table.sort(found, function(x, y)
    local ex, ey = math.abs(x[5]), math.abs(y[5])
    if math.abs(ex - ey) > 1e-9 then return ex < ey end
    if x[3] ~= y[3] then return x[3] == "+" end
    return x[1] < y[1]
  end)
  local out, seen = {}, {}
  for _, f in ipairs(found) do
    local key = f[1] .. f[3] .. f[2]
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = f
      if #out >= count then break end
    end
  end
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
  local list = twoParts(eng, 3000, "E12", 5)
  check(#list == 5, "five ways for 3k")
  check(math.abs(list[1][5]) < 1e-6, "the best way is exact (" .. list[1][1] .. list[1][3] .. list[1][2] .. ")")
  local exact = false
  for _, f in ipairs(list) do
    if f[3] == "+" and ((f[1] == 1000 and f[2] == 2000) or (f[1] == 1800 and f[2] == 1200)) then exact = true end
  end
  check(exact or math.abs(list[1][4] - 3000) < 1e-6, "series sums are right")
  local p = twoParts(eng, 500, "E12", 20)
  local par = false
  for _, f in ipairs(p) do
    if f[3] == "||" and math.abs(f[4] - f[1] * f[2] / (f[1] + f[2])) < 1e-9 then par = true end
  end
  check(par, "parallel results are right")
  local wide = twoParts(eng, 123456, "E24", 3)
  check(#wide == 3 and math.abs(wide[1][5]) < 1, "a big odd value in E24 (" .. string.format("%.3f%%", wide[1][5]) .. ")")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("eseries needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("eseries: " .. tostring(uiErr))
  return
end
local eng, engErr = driver.load("eng", true)
if not eng then
  print("eseries: " .. tostring(engErr))
  return
end

local W, H = 240, 135
local SERIES = { "E3", "E6", "E12", "E24", "E48", "E96", "E192" }
local TOLERANCE = { E3 = "40%", E6 = "20%", E12 = "10%", E24 = "5%", E48 = "2%", E96 = "1%", E192 = "0.5%" }

local function ask(title, default)
  while true do
    local text = ui.prompt(title, default or "", 14)
    if text == nil then return nil end
    local v = eng.parse(text)
    if v and v > 0 then return v end
    ui.message("Not a number", { "try 4.6k, 100n, 12" })
  end
end

local function result(title, lines)
  while true do
    gfx.clear(0x0a0e18)
    ui.label(4, 3, title, 0xe8ecf4)
    for i, l in ipairs(lines) do ui.label(4, 18 + (i - 1) * 12, l, i == 1 and 0x60e090 or 0xe8ecf4) end
    ui.label(4, H - 10, "any key: back", 0x8a94aa)
    gfx.flush()
    if key.poll() then return end
    sys.sleep(40)
  end
end

local function nearestJob()
  local v = ask("the value you need", "4.6k")
  if not v then return end
  local pick = ui.choose("Series", { "E6 (20%)", "E12 (10%)", "E24 (5%)", "E48 (2%)", "E96 (1%)", "E192 (0.5%)" }, { selected = 3 })
  if not pick then return end
  local name = ({ "E6", "E12", "E24", "E48", "E96", "E192" })[pick]
  local best, err, below, above = eng.nearest(v, name)
  result("NEAREST IN " .. name, {
    "nearest " .. eng.format(best, 4) .. string.format("  (%+.2f%%)", err),
    "below   " .. eng.format(below, 4) .. string.format("  (%+.2f%%)", (below / v - 1) * 100),
    "above   " .. eng.format(above, 4) .. string.format("  (%+.2f%%)", (above / v - 1) * 100),
    "wanted  " .. eng.format(v, 4),
    name .. " parts have " .. TOLERANCE[name] .. " tolerance",
  })
end

local function pairJob()
  local v = ask("the value you need", "3k")
  if not v then return end
  local list = twoParts(eng, v, "E12", 5)
  local lines = { "two E12 parts for " .. eng.format(v, 4) }
  for _, f in ipairs(list) do
    lines[#lines + 1] = string.format("%s %s %s = %s  (%+.2f%%)", eng.format(f[1]), f[3], eng.format(f[2]), eng.format(f[4], 4), f[5])
  end
  if #list == 0 then lines[#lines + 1] = "nothing within 5%" end
  lines[#lines + 1] = "+ is in series, || is in parallel"
  result("TWO PARTS", lines)
end

local function listJob()
  local pick = ui.choose("List a series", { "E3", "E6", "E12", "E24", "E48", "E96", "E192" }, { selected = 4 })
  if not pick then return end
  local name = SERIES[pick]
  local values = eng.series(name)
  local top = 1
  local perRow, rows = 6, 8
  while true do
    gfx.clear(0x0a0e18)
    ui.label(4, 3, name .. " (" .. #values .. " values, " .. TOLERANCE[name] .. ")", 0xe8ecf4)
    for r = 0, rows - 1 do
      for c = 0, perRow - 1 do
        local v = values[top + r * perRow + c]
        if v then ui.label(6 + c * 38, 18 + r * 12, string.format("%.2f", v), 0xe8ecf4) end
      end
    end
    ui.label(4, H - 10, "w s scroll   ctrl-q back", 0x8a94aa)
    gfx.flush()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "s" or k == "down" then top = math.min(math.max(1, #values - perRow * rows + 1), top + perRow)
      elseif k == "w" or k == "up" then top = math.max(1, top - perRow) end
      k = key.poll()
    end
    sys.sleep(40)
  end
end

local w, h = ui.open()
if not w then
  print("eseries: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local last = 1
  while true do
    local pick = ui.choose("E series", { "Nearest standard value", "Two parts for a value", "List a series" }, { selected = last })
    if not pick then return end
    last = pick
    if pick == 1 then nearestJob() elseif pick == 2 then pairJob() else listJob() end
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("eseries: " .. tostring(problem)) end
