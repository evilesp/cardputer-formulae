#!lua
-- sensors: live charts of the motion sensor and the battery. 1 shows the accelerometer (x, y, z in g), 2 the gyroscope
-- (x, y, z in degrees per second), 3 the battery (percent, with the voltage and whether it charges). The charts show
-- the last 200 readings, ten a second. Every reading is also written to /home/user/sensors.csv on the SD card, a new file
-- for each run (it starts again after 3000 lines), so the memory of the Cardputer is not used for the log. ctrl-q quits.
-- Needs the graphics, the ui package and firmware v0.1.0.15(beta) (fs.append). Run it with --selftest to check the history.

local KEEP = 200
local LOG = "/home/user/sensors.csv"
local LOG_LINES = 3000
local HEADER = "ms,ax,ay,az,gx,gy,gz,bat,mv\n"

-- the range of each series: a reading is kept as one byte, scaled across this range
local RANGE = {
  ax = { -2, 2 }, ay = { -2, 2 }, az = { -2, 2 },
  gx = { -250, 250 }, gy = { -250, 250 }, gz = { -250, 250 },
  bat = { 0, 100 },
}

-- a history that keeps the last `limit` readings of each of its series, as text: one byte a reading, so 200 readings take
-- 200 bytes instead of 200 numbers in a table
local function newHistory(limit)
  return { limit = limit, series = {} }
end

local function rangeOf(name)
  return RANGE[name] or { -1, 1 }
end

local function quantize(value, lo, hi)
  if value < lo then value = lo elseif value > hi then value = hi end
  return math.floor((value - lo) / (hi - lo) * 255 + 0.5)
end

local function push(history, name, value)
  local r = rangeOf(name)
  local s = (history.series[name] or "") .. string.char(quantize(value, r[1], r[2]))
  if #s > history.limit then s = s:sub(#s - history.limit + 1) end
  history.series[name] = s
end

-- the value of reading i of a series (1 is the oldest)
local function valueAt(history, name, i)
  local r = rangeOf(name)
  return r[1] + history.series[name]:byte(i) / 255 * (r[2] - r[1])
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
  for _, v in ipairs({ -1, 0, 1, 2 }) do push(h, "ax", v) end
  check(#h.series.ax == 3, "the history keeps the last 3 readings")
  check(math.abs(valueAt(h, "ax", 1)) < 0.02 and math.abs(valueAt(h, "ax", 3) - 2) < 0.02, "the readings come back in order")
  push(h, "bat", 50)
  check(#h.series.bat == 1 and math.abs(valueAt(h, "bat", 1) - 50) < 0.5, "every series has its own history, scaled to its range")
  check(rowOf(0, -2, 2, 101) == 50, "the middle value is the middle row")
  check(rowOf(2, -2, 2, 101) == 0 and rowOf(-2, -2, 2, 101) == 100, "the largest value is on top, the smallest at the bottom")
  check(rowOf(99, -2, 2, 101) == 0 and rowOf(-99, -2, 2, 101) == 100, "values outside the range are held at the edge")
  check(#(newHistory(KEEP).series.ax or "") == 0, "a new history is empty")
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
if not fs.append then
  print("sensors needs firmware v0.1.0.15(beta) or newer: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
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
local logLines, logState = 0, "log: sd"

-- writes one line to the log on the SD card; the file starts again after LOG_LINES lines
local function logLine(text)
  if logState ~= "log: sd" then return end
  if logLines >= LOG_LINES then
    logLines = 0
    fs.write(LOG, HEADER)
  end
  local ok, err = fs.append(LOG, text .. "\n")
  if ok then
    logLines = logLines + 1
  else
    logState = "log: off"  -- no card, or a full one: the charts go on
  end
end

local function sample()
  local ax, ay, az, gx, gy, gz = sys.imu()
  local pct, mv, chg = sys.battery()
  charging, millivolts = chg, mv or 0
  local t = sys.millis()
  if ax then
    push(history, "ax", ax); push(history, "ay", ay); push(history, "az", az)
    push(history, "gx", gx); push(history, "gy", gy); push(history, "gz", gz)
    logLine(string.format("%d,%.3f,%.3f,%.3f,%.1f,%.1f,%.1f,%d,%d", t, ax, ay, az, gx, gy, gz, pct or 0, millivolts))
  else
    logLine(string.format("%d,,,,,,,%d,%d", t, pct or 0, millivolts))
  end
  push(history, "bat", pct or 0)
end

local function chart(names, lo, hi, title, unit)
  gfx.rect(PLOT_X - 1, PLOT_Y - 1, PLOT_W + 2, PLOT_H + 2, 0x4a5470)
  ui.label(2, PLOT_Y - 2, string.format("%g", hi), 0x8a94aa)
  ui.label(2, PLOT_Y + PLOT_H - 8, string.format("%g", lo), 0x8a94aa)
  local zero = rowOf(0, lo, hi, PLOT_H)
  if lo < 0 and hi > 0 then gfx.hline(PLOT_X, PLOT_X + PLOT_W - 1, PLOT_Y + zero, 0x2a3040) end
  for ci, name in ipairs(names) do
    local s = history.series[name] or ""
    local prevX, prevY
    for i = 1, #s do
      local x = PLOT_X + (PLOT_W - #s) + i - 1
      local y = PLOT_Y + rowOf(valueAt(history, name, i), lo, hi, PLOT_H)
      if prevX then gfx.line(prevX, prevY, x, y, COLORS[ci]) end
      prevX, prevY = x, y
    end
    if #s > 0 then
      ui.label(PLOT_X + (ci - 1) * 66, PLOT_Y + PLOT_H + 4, string.format("%s %.2f", name:sub(-1), valueAt(history, name, #s)), COLORS[ci])
    end
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
  ui.label(W - 50, 4, logState, 0x8a94aa)
  ui.label(4, H - 10, "1 accel   2 gyro   3 battery   ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if k == "1" or k == "2" or k == "3" then mode = tonumber(k) end
  return true
end

-- a new log for this run
logState = fs.write(LOG, HEADER) and "log: sd" or "log: off"
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
