#!lua
-- spirograph: curves drawn by a pen on a wheel that rolls inside a ring, one coloured line at a time, until the pattern
-- is finished. space starts a new pattern, a and d change the colours, w and s change the drawing speed, p pauses, q quits.
-- Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the curve.

local W, H = 240, 135
local CX, CY = W / 2, H / 2

-- a point of the hypotrochoid: a ring of radius R, a wheel of radius r rolling inside it, the pen d from the wheel's middle
local function point(R, r, d, t)
  local k = (R - r) / r
  return (R - r) * math.cos(t) + d * math.cos(k * t), (R - r) * math.sin(t) - d * math.sin(k * t)
end

local function gcd(a, b)
  while b ~= 0 do a, b = b, a % b end
  return a
end

-- the angle after which the curve closes: the wheel must turn a whole number of times
local function period(R, r)
  return 2 * math.pi * (r / gcd(R, r))
end

local function hue(h, v)
  h = (h % 1) * 6
  local i, f = math.floor(h), h - math.floor(h)
  local rr, g, b
  if i == 0 then rr, g, b = 1, f, 0 elseif i == 1 then rr, g, b = 1 - f, 1, 0 elseif i == 2 then rr, g, b = 0, 1, f
  elseif i == 3 then rr, g, b = 0, 1 - f, 1 elseif i == 4 then rr, g, b = f, 0, 1 else rr, g, b = 1, 0, 1 - f end
  return (math.floor(rr * v * 255) << 16) | (math.floor(g * v * 255) << 8) | math.floor(b * v * 255)
end

-- a random pattern that closes after a moderate number of turns
local function randomPattern()
  while true do
    local R = math.random(40, 68)
    local r = math.random(7, R - 6)
    if r ~= R and gcd(R, r) < r and r // gcd(R, r) <= 14 then
      return { R = R, r = r, d = math.random(5, r + 14), hue = math.random() }
    end
  end
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local x, y = point(10, 5, 5, 0)
  check(math.abs(x - 10) < 1e-9 and math.abs(y) < 1e-9, "the pen starts on the ring's side")
  local T = period(10, 4)
  local x0, y0 = point(10, 4, 3, 0)
  local x1, y1 = point(10, 4, 3, T)
  check(math.abs(x0 - x1) < 1e-6 and math.abs(y0 - y1) < 1e-6, "the curve closes after one period")
  check(gcd(12, 8) == 4 and gcd(7, 3) == 1, "gcd")
  local good = true
  for _ = 1, 30 do
    local p = randomPattern()
    if p.r >= p.R or p.R > 68 then good = false end
  end
  check(good, "random patterns have a smaller wheel than the ring")
  check(hue(0, 1) == 0xff0000, "hue")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("spirograph needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("spirograph: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local pat = randomPattern()
  local T = period(pat.R, pat.r)
  local t, step, paused, shown = 0, 0.045, false, sys.millis()
  local perFrame, hueSpeed = 6, 0.0006
  local px, py
  gfx.clear(0x04060c)
  local function fresh()
    pat = randomPattern()
    T = period(pat.R, pat.r)
    t, px, py = 0, nil, nil
    gfx.clear(0x04060c)
    shown = sys.millis()
  end
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " or k == "n" then fresh()
      elseif k == "p" then paused = not paused
      elseif k == "a" or k == "left" then hueSpeed = hueSpeed - 0.0003
      elseif k == "d" or k == "right" then hueSpeed = hueSpeed + 0.0003
      elseif k == "w" or k == "up" then perFrame = math.min(30, perFrame + 3)
      elseif k == "s" or k == "down" then perFrame = math.max(1, perFrame - 3) end
      k = key.poll()
    end
    if not paused and t < T then
      for _ = 1, perFrame do
        t = math.min(T, t + step)
        local x, y = point(pat.R, pat.r, pat.d, t)
        x, y = math.floor(CX + x + 0.5), math.floor(CY + y + 0.5)
        pat.hue = pat.hue + hueSpeed
        if px then gfx.line(px, py, x, y, hue(pat.hue + t / T * 0.5, 1)) end
        px, py = x, y
        if t >= T then break end
      end
    elseif not paused and t >= T and sys.millis() - shown > 4000 then
      fresh()  -- a finished pattern stays for a while, then the next one starts
    end
    if t >= T and shown then shown = math.max(shown, sys.millis() - 3999) end
    if sys.millis() - shown < 1800 then
      gfx.fill(0, 0, W, 10, 0x04060c)
      gfx.text(4, 1, "space p a d w s q", 0xffffff, 1)
    end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("spirograph: " .. tostring(problem)) end
