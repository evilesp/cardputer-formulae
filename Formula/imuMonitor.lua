#!lua
-- imuMonitor: a live view of the accelerometer (g) and the gyroscope (degrees per second). q quits.
-- Each bar grows from the centre: 1 g is half of the accelerometer bar, 250 deg/s is half of the gyroscope bar.

local COLS, ROWS = term.size()
local HALF = 10  -- characters from the centre to the end of a bar

local function bar(value, full)
  local n = math.floor(math.abs(value) / full * HALF + 0.5)
  if n > HALF then n = HALF end
  if value < 0 then
    return string.rep(" ", HALF - n) .. string.rep("#", n) .. "|" .. string.rep(" ", HALF)
  end
  return string.rep(" ", HALF) .. "|" .. string.rep("#", n) .. string.rep(" ", HALF - n)
end

local function line(row, label, value, full)
  term.text(0, row, string.format("%s %s %6.2f", label, bar(value, full), value):sub(1, COLS), "text")
end

local ax, ay, az, gx, gy, gz = sys.imu()
if not ax then
  print("imuMonitor: this board has no motion sensor")
  return
end

term.fullscreen(true)
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true end
    k = key.poll()
  end
  if quit then break end

  ax, ay, az, gx, gy, gz = sys.imu()
  term.clear()
  term.text(0, 0, "imuMonitor   q = quit", "white")
  term.text(0, 2, "accelerometer (g)", "cyan")
  line(3, "x", ax, 2)
  line(4, "y", ay, 2)
  line(5, "z", az, 2)
  term.text(0, 7, "gyroscope (deg/s)", "cyan")
  line(8, "x", gx, 250)
  line(9, "y", gy, 250)
  line(10, "z", gz, 250)
  term.text(0, 12, "lying flat on a table: z is about 1 g", "dim")
  term.flush()
  sys.sleep(80)
end
term.fullscreen(false)
