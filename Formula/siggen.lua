#!lua
-- siggen: a square wave generator on a pin, for testing a buzzer, an LED or a circuit. w and s choose the pin from the pins
-- of the Cardputer that may be used, a and d change the frequency (by 1 Hz below 100 Hz, 10 Hz below 1000 Hz, 100 Hz above),
-- enter starts and stops it, ctrl-q quits (and stops the wave). Needs the graphics, the ui package and firmware v0.1.0.18(beta)
-- (gpio.tone). Run it with --selftest to check the frequency steps.

-- the step of the frequency at f: 1 Hz below 100, 10 Hz below 1000, 100 Hz above
local function stepOf(f)
  if f < 100 then return 1 end
  if f < 1000 then return 10 end
  return 100
end

-- the frequency after one step up (dir 1) or down (dir -1), kept between 20 and 10000 Hz
local function stepFreq(f, dir)
  local s = stepOf(dir > 0 and f or f - 1)
  local nf = f + dir * s
  if nf < 20 then return 20 end
  if nf > 10000 then return 10000 end
  return nf
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(stepOf(50) == 1 and stepOf(500) == 10 and stepOf(5000) == 100, "the steps")
  check(stepFreq(440, 1) == 450 and stepFreq(440, -1) == 430, "440 Hz up and down by 10")
  check(stepFreq(50, 1) == 51 and stepFreq(20, -1) == 20, "below 100 Hz the step is 1, not below 20")
  check(stepFreq(9950, 1) == 10000 and stepFreq(10000, 1) == 10000, "the top is 10000 Hz")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("siggen needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gpio or not gpio.tone then
  print("siggen needs firmware v0.1.0.18(beta) or newer: SystemBackUpdate")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("siggen: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local pins = gpio.pins and gpio.pins() or {}
local choice = 1
local freq = 440
local running = false

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "SIGGEN  square wave", 0xe8ecf4)
  ui.center(30, string.format("%d Hz", freq), running and 0x60ff90 or 0xe8ecf4, 3)
  local pin = pins[choice]
  ui.label(8, 70, "pin GPIO" .. tostring(pin or "-"), 0xffe060)
  ui.label(8, 84, running and "playing   enter stops" or "stopped   enter starts", running and 0x60ff90 or 0x8a94aa)
  ui.label(8, 100, "w s pin   a d frequency", 0x8a94aa)
  ui.label(8, H - 10, "ctrl-q quit (stops the wave)", 0x8a94aa)
  gfx.flush()
end

local function stop()
  if running and pins[choice] then pcall(gpio.noTone, pins[choice]) end
  running = false
end

local w, h = ui.open()
if not w then
  print("siggen: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then
        stop()
        return
      end
      if k == "w" then
        stop()
        choice = math.max(1, choice - 1)
      elseif k == "s" then
        stop()
        choice = math.min(#pins, choice + 1)
      elseif k == "a" then
        freq = stepFreq(freq, -1)
        if running then gpio.tone(pins[choice], freq) end
      elseif k == "d" then
        freq = stepFreq(freq, 1)
        if running then gpio.tone(pins[choice], freq) end
      elseif k == "enter" and pins[choice] then
        if running then stop() else
          gpio.tone(pins[choice], freq)
          running = true
        end
      end
      k = key.poll()
    end
    sys.sleep(60)
  end
end)
stop()
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("siggen: " .. tostring(problem)) end
