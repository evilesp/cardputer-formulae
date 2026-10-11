#!lua
-- scope: an oscilloscope for a pin. It reads an analogue pin (GPIO 1 to 10) and draws the voltage over time: the top of the
-- screen is 3.3 V. p chooses the pin, + and - change the time between the readings (a faster sweep shows less), r holds
-- the picture, ctrl-q quits. Needs the graphics, the ui package and firmware v0.1.0.18(beta) (gpio.scope).
-- Run it with --selftest to check the scaling and the measurements.

local W, H = 240, 135
local SAMPLES = 200
local TOP, BOTTOM = 22, 110
local MAX_MV = 3300

-- the screen row of a voltage in millivolts (0 at the bottom, MAX_MV at the top)
local function rowOf(mv)
  mv = math.max(0, math.min(MAX_MV, mv))
  return BOTTOM - math.floor((BOTTOM - TOP) * mv / MAX_MV + 0.5)
end

-- the lowest, the highest and the peak-to-peak voltage of a list of readings
local function measure(values)
  local lo, hi = math.huge, -math.huge
  for _, v in ipairs(values) do
    if v < lo then lo = v end
    if v > hi then hi = v end
  end
  if #values == 0 then return 0, 0, 0 end
  return lo, hi, hi - lo
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(rowOf(0) == BOTTOM and rowOf(MAX_MV) == TOP, "0 V is at the bottom, 3.3 V at the top")
  check(rowOf(-500) == BOTTOM and rowOf(9999) == TOP, "a reading outside the range is held at the edge")
  local mid = rowOf(MAX_MV / 2)
  check(mid > TOP and mid < BOTTOM, "half the voltage is in the middle")
  local lo, hi, pp = measure({ 100, 1200, 3000, 400 })
  check(lo == 100 and hi == 3000 and pp == 2900, "the lowest, highest and peak to peak")
  check(select(3, measure({})) == 0, "no readings, no measurements")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("scope needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gpio or not gpio.scope then
  print("scope needs firmware v0.1.0.18(beta) or newer: SystemBackUpdate")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("scope: " .. tostring(uiErr))
  return
end

local pin = 1
local spacing = 40   -- microseconds between readings
local frozen = false
local picture = nil

local function draw(values)
  gfx.clear(0x0a0c14)
  gfx.hline(0, W - 1, rowOf(0), 0x3a4260)
  gfx.hline(0, W - 1, rowOf(MAX_MV), 0x3a4260)
  local prevX, prevY
  for i, mv in ipairs(values) do
    local x = math.floor((i - 1) * (W - 1) / (#values - 1))
    local y = rowOf(mv)
    if prevX then gfx.line(prevX, prevY, x, y, 0x60ff90) end
    prevX, prevY = x, y
  end
  local lo, hi, pp = measure(values)
  ui.label(8, 4, "GPIO" .. pin .. "  p pin  + - sweep  r hold", 0xe8ecf4)
  ui.label(8, 118, string.format("low %.2f V   high %.2f V   peak %.2f V   %d us a sample", lo / 1000, hi / 1000, pp / 1000, spacing), 0x8a94aa)
  if frozen then ui.label(190, 4, "HOLD", 0xffe060) end
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("scope: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "p" then
        local answer = tonumber(ui.prompt("pin (1 to 10)", tostring(pin), 2) or "")
        if answer and answer >= 1 and answer <= 10 then pin = answer end
      elseif k == "+" or k == "=" then spacing = math.min(2000, spacing + 20)
      elseif k == "-" then spacing = math.max(0, spacing - 20)
      elseif k == "r" then frozen = not frozen
      end
      k = key.poll()
    end
    if not frozen then
      local ok2, values = pcall(gpio.scope, pin, SAMPLES, spacing)
      if ok2 then picture = values else picture = nil end
    end
    if picture then draw(picture) else
      gfx.clear(0x0a0c14)
      ui.label(8, 60, "cannot read GPIO" .. pin .. " (use 1 to 10)", 0xff6060)
      gfx.flush()
    end
    sys.sleep(50)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("scope: " .. tostring(problem)) end
