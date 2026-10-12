#!lua
-- ohm: Ohm's law and power. Set any two of voltage (V), current (I), resistance (R) and power (P); the other two are worked
-- out at once. w and s choose a row, enter types a value (4k7, 100m, 2u2; an empty answer clears the row), c clears all,
-- ctrl-q quits. A third value replaces the oldest of the two you set. Needs the graphics, the ui package and the eng driver.
-- Run it with --selftest to check the formulas.

local NAMES = { "V", "I", "R", "P" }
local UNITS = { V = "V", I = "A", R = "ohm", P = "W" }
local LABEL = { V = "voltage", I = "current", R = "resistance", P = "power" }

-- the other two values from two known ones (a table with the names V, I, R, P), or nil when two are not known or the sum is
-- impossible (zero or negative where it must not be)
local function solve(known)
  local V, I, R, P = known.V, known.I, known.R, known.P
  local n = 0
  for _, k in ipairs(NAMES) do if known[k] then n = n + 1 end end
  if n ~= 2 then return nil end
  local out = { V = V, I = I, R = R, P = P }
  if V and I then
    if I == 0 then return nil end
    out.R, out.P = V / I, V * I
  elseif V and R then
    if R == 0 then return nil end
    out.I, out.P = V / R, V * V / R
  elseif V and P then
    if V == 0 then return nil end
    out.I, out.R = P / V, V * V / P
  elseif I and R then
    out.V, out.P = I * R, I * I * R
  elseif I and P then
    if I == 0 then return nil end
    out.V, out.R = P / I, P / (I * I)
  elseif R and P then
    if R < 0 or P < 0 or R == 0 then return nil end
    out.V, out.I = math.sqrt(P * R), math.sqrt(P / R)
  end
  return out
end

-- the standard power ratings of resistors in watt: the smallest that has twice the power as room
local RATINGS = { { 0.125, "1/8 W" }, { 0.25, "1/4 W" }, { 0.5, "1/2 W" }, { 1, "1 W" }, { 2, "2 W" }, { 5, "5 W" }, { 10, "10 W" } }
local function rating(p)
  for _, r in ipairs(RATINGS) do
    if r[1] >= 2 * math.abs(p) then return r[2] end
  end
  return "over 10 W"
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local function near(a, b) return a and math.abs(a - b) < 1e-9 * math.max(1, math.abs(b)) end
  local function same(r) return near(r.V, 12) and near(r.I, 0.5) and near(r.R, 24) and near(r.P, 6) end
  check(same(solve({ V = 12, I = 0.5 })), "V and I")
  check(same(solve({ V = 12, R = 24 })), "V and R")
  check(same(solve({ V = 12, P = 6 })), "V and P")
  check(same(solve({ I = 0.5, R = 24 })), "I and R")
  check(same(solve({ I = 0.5, P = 6 })), "I and P")
  check(same(solve({ R = 24, P = 6 })), "R and P")
  check(solve({ V = 1 }) == nil and solve({ V = 1, I = 2, R = 3 }) == nil, "exactly two values are needed")
  check(solve({ V = 5, I = 0 }) == nil and solve({ V = 0, P = 1 }) == nil, "no division by zero")
  check(rating(0.1) == "1/4 W" and rating(0.2) == "1/2 W" and rating(0.5) == "1 W" and rating(6) == "over 10 W", "power ratings")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("ohm needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("ohm: " .. tostring(uiErr))
  return
end
local eng, engErr = driver.load("eng")
if not eng then
  print("ohm: " .. tostring(engErr))
  return
end

local W, H = 240, 135
local known, order = {}, {}  -- the values typed, and which two are the newest
local sel = 1

local function setValue(name, v)
  for i, n in ipairs(order) do
    if n == name then table.remove(order, i) break end
  end
  known[name] = nil
  if v ~= nil then
    table.insert(order, name)
    known[name] = v
    while #order > 2 do
      known[table.remove(order, 1)] = nil
    end
  end
end

local function draw()
  gfx.clear(0x0a0e18)
  ui.label(4, 3, "OHM'S LAW", 0xe8ecf4)
  local result = solve(known)
  for i, name in ipairs(NAMES) do
    local y = 20 + (i - 1) * 20
    local typed = known[name] ~= nil
    if i == sel then gfx.fill(2, y - 3, W - 4, 17, 0x2a3350) end
    ui.label(8, y, name, 0xf0c840, 2)
    ui.label(34, y + 3, LABEL[name], 0x8a94aa)
    local v = typed and known[name] or (result and result[name])
    if v ~= nil then
      ui.label(120, y, eng.format(v) .. UNITS[name], typed and 0xe8ecf4 or 0x60e090, 2)
    else
      ui.label(120, y + 3, "-", 0x5a6478)
    end
  end
  if result and result.P then
    ui.label(4, 104, "a resistor for this: " .. rating(result.P), 0x8a94aa)
  else
    ui.label(4, 104, "set two values, the others follow", 0x8a94aa)
  end
  ui.label(4, H - 10, "w s row  enter value  c clear  ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("ohm: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      if k == "w" or k == "up" then sel = sel > 1 and sel - 1 or #NAMES
      elseif k == "s" or k == "down" then sel = sel < #NAMES and sel + 1 or 1
      elseif k == "c" then known, order = {}, {}
      elseif k == "enter" or k == " " then
        local text = ui.prompt(LABEL[NAMES[sel]] .. " in " .. UNITS[NAMES[sel]], "", 12)
        if text ~= nil then
          if text == "" then
            setValue(NAMES[sel], nil)
          else
            local v = eng.parse(text)
            if v and v >= 0 then setValue(NAMES[sel], v) else ui.message("Not a value", { "try 4k7, 100m, 12" }) end
          end
        end
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("ohm: " .. tostring(problem)) end
