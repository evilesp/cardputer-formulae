#!lua
-- sensors: live charts of the motion sensor and the battery. 1 shows the accelerometer (x, y, z in g), 2 the gyroscope
-- (x, y, z in degrees per second), 3 the battery (percent, with the voltage and whether it charges). The charts show
-- the last 200 readings, ten a second. ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the history and the scale.

local KEEP = 200

-- a history that keeps the last `limit` values of each of its series
local function newHistory(limit)
  return { limit = limit, series = {} }
end

local function push(history, name, value)
  local s = history.series[name]
  if not s then
    s = {}
    history.series[name] = s
  end
  s[#s + 1] = value
  if #s > history.limit then table.remove(s, 1) end
end

-- the pixel row of a value in a chart `height` pixels tall that shows lo to hi (row 0 is the top)
local function rowOf(value, lo, hi, height)
  if value < lo then value = lo elseif value > hi then value = hi end
  return height - 1 - math.floor((value - lo) / (hi - lo) * (height - 1) + 0.5)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local h = newHistory(3)
  for i = 1, 5 do push(h, "x", i) end
  check(#h.series.x == 3 and h.series.x[1] == 3 and h.series.x[3] == 5, "the history keeps the last values")
  push(h, "y", 7)
  check(#h.series.y == 1, "every series has its own history")
  check(rowOf(0, -2, 2, 101) == 50, "the middle value is the middle row")
  check(rowOf(2, -2, 2, 101) == 0 and rowOf(-2, -2, 2, 101) == 100, "the largest value is on top, the smallest at the bottom")
  check(rowOf(99, -2, 2, 101) == 0 and rowOf(-99, -2, 2, 101) == 100, "values outside the range are held at the edge")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("sensors needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("sensors: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui")
if not ui then
  print("sensors: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local PLOT_X, PLOT_Y, PLOT_W, PLOT_H = 34, 22, 200, 90
local COLORS = { 0xff6060, 0x60e060, 0x60a0ff }
local history = newHistory(KEEP)
local mode = 1
local charging, millivolts = false, 0

local function sample()
  local ax, ay, az, gx, gy, gz = sys.imu()
  if ax then
    push(history, "ax", ax); push(history, "ay", ay); push(history, "az", az)
    push(history, "gx", gx); push(history, "gy", gy); push(history, "gz", gz)
  end
  local pct, mv, chg = sys.battery()
  push(history, "bat", pct or 0)
  charging, millivolts = chg, mv or 0
end

local function chart(names, lo, hi, title, unit)
  gfx.rect(PLOT_X - 1, PLOT_Y - 1, PLOT_W + 2, PLOT_H + 2, 0x4a5470)
  ui.label(2, PLOT_Y - 2, string.format("%g", hi), 0x8a94aa)
  ui.label(2, PLOT_Y + PLOT_H - 8, string.format("%g", lo), 0x8a94aa)
  local zero = rowOf(0, lo, hi, PLOT_H)
  if lo < 0 and hi > 0 then gfx.hline(PLOT_X, PLOT_X + PLOT_W - 1, PLOT_Y + zero, 0x2a3040) end
  for ci, name in ipairs(names) do
    local s = history.series[name] or {}
    local prevX, prevY
    for i, v in ipairs(s) do
      local x = PLOT_X + (PLOT_W - #s) + i - 1
      local y = PLOT_Y + rowOf(v, lo, hi, PLOT_H)
      if prevX then gfx.line(prevX, prevY, x, y, COLORS[ci]) end
      prevX, prevY = x, y
    end
    local last = s[#s]
    if last then ui.label(PLOT_X + (ci - 1) * 66, PLOT_Y + PLOT_H + 4, string.format("%s %.2f", name:sub(-1), last), COLORS[ci]) end
  end
  ui.label(4, 4, title .. " (" .. unit .. ")", 0xe8ecf4)
end

local function draw()
  gfx.clear(0x0a0c14)
  if mode == 1 then
    chart({ "ax", "ay", "az" }, -2, 2, "accelerometer", "g")
  elseif mode == 2 then
    chart({ "gx", "gy", "gz" }, -250, 250, "gyroscope", "deg/s")
  else
    chart({ "bat" }, 0, 100, "battery", "%")
    ui.label(PLOT_X + 70, PLOT_Y + PLOT_H + 4, string.format("%d mV%s", millivolts, charging and "  charging" or ""), 0xe8ecf4)
  end
  ui.label(4, H - 10, "1 accel   2 gyro   3 battery   ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if k == "1" or k == "2" or k == "3" then mode = tonumber(k) end
  return true
end

local w, h = ui.open()
if not w then
  print("sensors: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local nextSample = 0
  while true do
    local now = sys.millis()
    if now >= nextSample then
      sample()
      nextSample = now + 100
    end
    local k = key.poll()
    while k do
      if not handle(k) then return end
      k = key.poll()
    end
    draw()
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("sensors: " .. tostring(problem)) end
