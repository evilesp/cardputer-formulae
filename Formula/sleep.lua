#!lua
-- sleep: the low power screen. The processor runs at 80 MHz, the WiFi saves power (it stays connected), the screen is at its
-- lowest brightness and shows the time, the date, today's steps and the battery. The step counter keeps counting. Any key
-- wakes it up (ctrl-q quits). Needs the graphics, the ui package and firmware v0.1.0.18(beta). "sleep" alone runs this
-- program when it is installed; "sleep 30" still waits 30 seconds.
-- Run it with --selftest to check the helpers.

-- the battery as text: 0 to 100 percent, or "--"
local function batteryText(percent)
  if not percent then return "--" end
  return tostring(percent) .. "%"
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(batteryText(87) == "87%" and batteryText(nil) == "--", "the battery text")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("sleep needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not sys.lowPower then
  print("sleep needs firmware v0.1.0.18(beta) or newer: SystemBackUpdate")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("sleep: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local DIM = 0x3a4050  -- dim on purpose: the screen is at its lowest brightness

local function draw()
  gfx.clear(0x000000)
  ui.center(18, sys.date("%H:%M"), DIM, 5)
  ui.center(70, sys.date("%A %d %B %Y"), DIM, 1)
  local line = "steps " .. tostring(steps and steps.today and steps.today() or "--")
  ui.center(88, line, DIM, 1)
  ui.center(108, "battery " .. batteryText(sys.battery and sys.battery() or nil) .. "    any key wakes up", DIM, 1)
  gfx.flush()
end

sys.lowPower(true)
local w, h = ui.open()
if not w then
  sys.lowPower(false)
  print("sleep: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    draw()
    local k = key.poll()
    if k then return end
    sys.sleep(1000)
  end
end)
ui.close()
sys.lowPower(false)
if not ok and not tostring(problem):find("interrupted", 1, true) then print("sleep: " .. tostring(problem)) end
