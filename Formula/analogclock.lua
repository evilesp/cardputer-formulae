#!lua
-- analogclock: an analogue clock face with hour, minute and second hands, and the date and the time in digits. The time
-- comes from the network clock, so connect to WiFi first (wifi connect SSID PASS); without it the clock says so.
-- ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the hands.

local CX, CY, R = 120, 66, 58

-- the end of a hand of the given length at a fraction of a full turn (0 is straight up, 0.25 is to the right)
local function handEnd(fraction, length)
  local a = fraction * 2 * math.pi
  return CX + math.floor(math.sin(a) * length + 0.5), CY - math.floor(math.cos(a) * length + 0.5)
end

-- the positions of the three hands, as fractions of a turn, from hours, minutes and seconds
local function handFractions(h, m, s)
  return ((h % 12) + m / 60) / 12, (m + s / 60) / 60, s / 60
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local x, y = handEnd(0, 50)
  check(x == CX and y == CY - 50, "a hand at zero points straight up")
  x, y = handEnd(0.25, 50)
  check(x == CX + 50 and y == CY, "a quarter turn points right")
  x, y = handEnd(0.5, 50)
  check(x == CX and y == CY + 50, "half a turn points down")
  local hf, mf, sf = handFractions(3, 0, 0)
  check(hf == 0.25 and mf == 0 and sf == 0, "three o'clock puts the hour hand a quarter round")
  hf, mf, sf = handFractions(12, 30, 30)
  check(math.abs(hf - 0.5 / 12) < 1e-9, "at half past twelve the hour hand has crept half an hour")
  hf, mf, sf = handFractions(6, 30, 0)
  check(math.abs(hf - 0.5416666) < 0.001 and mf == 0.5, "half past six")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("analogclock needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("analogclock: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("analogclock: " .. tostring(uiErr))
  return
end

local function draw()
  gfx.clear(0x0a0c14)
  gfx.circle(CX, CY, R, 0x6a7ab0, false)
  gfx.circle(CX, CY, R - 1, 0x2a3350, false)
  for i = 0, 11 do
    local x0, y0 = handEnd(i / 12, R - 6)
    local x1, y1 = handEnd(i / 12, R - 1)
    gfx.line(x0, y0, x1, y1, i % 3 == 0 and 0xffffff or 0x8a94aa)
  end
  local stamp = sys.date("%H %M %S")
  if stamp then
    local h, m, s = stamp:match("(%d+) (%d+) (%d+)")
    h, m, s = tonumber(h), tonumber(m), tonumber(s)
    local hf, mf, sf = handFractions(h, m, s)
    local hx, hy = handEnd(hf, 28)
    local mx, my = handEnd(mf, 42)
    local sx, sy = handEnd(sf, 48)
    gfx.line(CX, CY, hx, hy, 0xe8ecf4)
    gfx.line(CX + 1, CY, hx + 1, hy, 0xe8ecf4)
    gfx.line(CX, CY, mx, my, 0x60c8ff)
    gfx.line(CX, CY, sx, sy, 0xff5050)
    gfx.disc(CX, CY, 3, 0xffe060)
    ui.center(124, sys.date("%a %d %b  %H:%M:%S"), 0x8a94aa, 1)
  else
    ui.center(60, "no time yet", 0xe8ecf4, 1)
    ui.center(72, "connect to WiFi", 0x8a94aa, 1)
  end
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("analogclock: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      k = key.poll()
    end
    draw()
    sys.sleep(200)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("analogclock: " .. tostring(problem)) end
