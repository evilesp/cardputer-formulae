#!lua
-- lissajous: two waves swing at once, one across the screen and one up and down, and a dot draws the curve they make
-- with a comet trail behind it. a d change the frequency across (1 to 9), w s change the frequency up and down (1 to 9),
-- space changes the phase between the waves, p pauses, q quits.
-- Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the maths.

local W, H = 240, 135
local CX, CY = W / 2, 58
local RX, RY = 110, 52
local STEPS = 360
local TAIL = 60
local PHASES = 16
local MIN_FREQ, MAX_FREQ = 1, 9

-- the same colour wheel as spirograph: hue h in turns, v the brightness
local function hue(h, v)
  h = (h % 1) * 6
  local i, f = math.floor(h), h - math.floor(h)
  local rr, g, b
  if i == 0 then rr, g, b = 1, f, 0 elseif i == 1 then rr, g, b = 1 - f, 1, 0 elseif i == 2 then rr, g, b = 0, 1, f
  elseif i == 3 then rr, g, b = 0, 1 - f, 1 elseif i == 4 then rr, g, b = f, 0, 1 else rr, g, b = 1, 0, 1 - f end
  return (math.floor(rr * v * 255) << 16) | (math.floor(g * v * 255) << 8) | math.floor(b * v * 255)
end

-- the point of step i (0 to STEPS, the curve closes at STEPS); ph is the phase index (0 to PHASES - 1)
local function pointAt(i, fx, fy, ph)
  local t = 2 * math.pi * i / STEPS
  local p = ph * math.pi / PHASES
  return CX + RX * math.sin(fx * t + p), CY + RY * math.sin(fy * t)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local x, y = pointAt(0, 1, 1, 0)
  check(math.abs(x - CX) < 1e-9 and math.abs(y - CY) < 1e-9, "the curve starts at the centre with no phase")
  x, y = pointAt(90, 1, 1, 0)
  check(math.abs(x - (CX + RX)) < 1e-9 and math.abs(y - (CY + RY)) < 1e-9, "a quarter turn reaches the far corner")
  local closed, inside = true, true
  for fx = MIN_FREQ, MAX_FREQ do
    for fy = MIN_FREQ, MAX_FREQ do
      for ph = 0, PHASES - 1 do
        local x0, y0 = pointAt(0, fx, fy, ph)
        local x1, y1 = pointAt(STEPS, fx, fy, ph)
        if math.abs(x0 - x1) > 1e-6 or math.abs(y0 - y1) > 1e-6 then closed = false end
        for i = 0, STEPS do
          local px, py = pointAt(i, fx, fy, ph)
          if math.abs(px - CX) > RX + 1e-9 or math.abs(py - CY) > RY + 1e-9 then inside = false end
        end
      end
    end
  end
  check(closed, "every curve closes after one full turn")
  check(inside, "every curve stays inside the box")
  check(hue(0, 1) == 0xff0000 and hue(1 / 3, 1) == 0x00ff00, "hue")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("lissajous needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("lissajous: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local fx, fy, ph = 3, 2, 0
  local head, paused = 0, false
  local hueShift = 0

  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == "a" or k == "left" then fx = math.max(MIN_FREQ, fx - 1)
      elseif k == "d" or k == "right" then fx = math.min(MAX_FREQ, fx + 1)
      elseif k == "w" or k == "up" then fy = math.min(MAX_FREQ, fy + 1)
      elseif k == "s" or k == "down" then fy = math.max(MIN_FREQ, fy - 1)
      elseif k == " " then ph = (ph + 1) % PHASES
      elseif k == "p" then paused = not paused end
      k = key.poll()
    end
    if not paused then
      head = (head + 2) % STEPS
      hueShift = hueShift + 0.003
    end

    gfx.clear(0x000000)
    -- the whole figure, dim, so its shape stays on the screen
    for i = 0, STEPS - 1 do
      local x, y = pointAt(i, fx, fy, ph)
      gfx.pixel(math.floor(x + 0.5), math.floor(y + 0.5), 0x203040)
    end
    -- the comet: the newest point is bright, the older ones fade, the oldest are drawn first
    for age = TAIL - 1, 0, -1 do
      local i = (head - age) % STEPS
      local x, y = pointAt(i, fx, fy, ph)
      local v = 1 - age / TAIL
      local c = hue(hueShift + i / STEPS, v)
      local r = age < 3 and 2 or 1
      gfx.disc(math.floor(x + 0.5), math.floor(y + 0.5), r, c)
    end

    gfx.fill(0, 122, W, 13, 0x000000)
    gfx.text(2, 124, "x " .. fx .. " y " .. fy .. "  a d w s  space phase  q", 0x9aa8c0, 1)
    gfx.flush()
    sys.sleep(30)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("lissajous: " .. tostring(problem)) end
