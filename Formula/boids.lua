#!lua
-- boids: a flock of birds that gather, keep a little space from each other and turn towards the way their
-- neighbours fly, like Craig Reynolds' boids; the birds bounce off the edges of the sky. w and s change the top
-- speed, space scatters the flock, p pauses, q quits. Needs the graphics (firmware v0.1.0.13).
-- Run it with --selftest to check the maths.

local W, H = 240, 135
local SKY = 120 -- the bar at the bottom is not part of the sky
local N = 28
local RANGE2 = 40 * 40 -- birds closer than 40 px are neighbours
local SPACE2 = 9 * 9 -- birds closer than 9 px push each other apart
local SPEEDS = { 0.5, 0.8, 1.1, 1.5, 2.0 }
local DEFAULT_SPEED = 3

-- flat arrays, allocated once: no tables are made inside the frame loop
local X, Y, VX, VY, NVX, NVY = {}, {}, {}, {}, {}, {}

-- the same colour wheel as kaleidoscope: hue h in turns, v the brightness
local function hue(h, v)
  h = (h % 1) * 6
  local i, f = math.floor(h), h - math.floor(h)
  local rr, g, b
  if i == 0 then rr, g, b = 1, f, 0 elseif i == 1 then rr, g, b = 1 - f, 1, 0 elseif i == 2 then rr, g, b = 0, 1, f
  elseif i == 3 then rr, g, b = 0, 1 - f, 1 elseif i == 4 then rr, g, b = f, 0, 1 else rr, g, b = 1, 0, 1 - f end
  return (math.floor(rr * v * 255) << 16) | (math.floor(g * v * 255) << 8) | math.floor(b * v * 255)
end

-- a velocity kept between half and all of the top speed: a bird never stops and never gets faster
local function limit(vx, vy, maxv)
  local s = math.sqrt(vx * vx + vy * vy)
  local minv = maxv * 0.5
  if s < 1e-9 then return minv, 0 end
  local f
  if s > maxv then f = maxv / s elseif s < minv then f = minv / s else return vx, vy end
  return vx * f, vy * f
end

-- the steering of bird i from its neighbours: cohesion (towards their middle), alignment (their speed)
-- and separation (away from birds that are too close), plus a little wander so the flock never freezes
local function steer(i)
  local cx, cy, ax, ay, sx, sy, n = 0, 0, 0, 0, 0, 0, 0
  for j = 1, N do
    if j ~= i then
      local dx, dy = X[j] - X[i], Y[j] - Y[i]
      local d2 = dx * dx + dy * dy
      if d2 < RANGE2 then
        n = n + 1
        cx, cy = cx + dx, cy + dy
        ax, ay = ax + VX[j], ay + VY[j]
        if d2 < SPACE2 then
          local safe = d2 < 0.01 and 0.01 or d2
          sx, sy = sx - dx / safe, sy - dy / safe
        end
      end
    end
  end
  local fx, fy = (math.random() - 0.5) * 0.05, (math.random() - 0.5) * 0.05
  if n > 0 then
    fx = fx + cx / n * 0.004 + (ax / n - VX[i]) * 0.05
    fy = fy + cy / n * 0.004 + (ay / n - VY[i]) * 0.05
  end
  return fx + sx * 0.6, fy + sy * 0.6
end

-- one frame of the flock: every bird steers from the old positions, then all birds move and bounce
local function step(maxv)
  for i = 1, N do
    local fx, fy = steer(i)
    NVX[i], NVY[i] = limit(VX[i] + fx, VY[i] + fy, maxv)
  end
  for i = 1, N do
    VX[i], VY[i] = NVX[i], NVY[i]
    local x, y = X[i] + VX[i], Y[i] + VY[i]
    if x < 0 then x = -x; VX[i] = -VX[i] elseif x > W - 1 then x = 2 * (W - 1) - x; VX[i] = -VX[i] end
    if y < 0 then y = -y; VY[i] = -VY[i] elseif y > SKY - 1 then y = 2 * (SKY - 1) - y; VY[i] = -VY[i] end
    X[i], Y[i] = x, y
  end
end

-- every bird at a random place, flying in a random direction at 80 percent of the top speed
local function scatter(maxv)
  for i = 1, N do
    local a = math.random() * 2 * math.pi
    X[i], Y[i] = math.random() * (W - 1), math.random() * (SKY - 1)
    VX[i], VY[i] = math.cos(a) * maxv * 0.8, math.sin(a) * maxv * 0.8
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
  local x, y = limit(3, 4, 2.5)
  check(math.abs(math.sqrt(x * x + y * y) - 2.5) < 1e-9, "a fast bird is slowed to the top speed")
  x, y = limit(0.1, 0, 1)
  check(math.abs(math.sqrt(x * x + y * y) - 0.5) < 1e-9, "a slow bird is sped up to half the top speed")
  x, y = limit(0.6, 0.8, 1)
  check(math.abs(x - 0.6) < 1e-9 and math.abs(y - 0.8) < 1e-9, "a bird in range keeps its speed")
  check(hue(0, 1) == 0xff0000 and hue(1 / 3, 1) == 0x00ff00, "hue")
  -- a run of the flock: no bird leaves the sky and no speed goes out of range
  math.randomseed(7)
  local maxv = SPEEDS[DEFAULT_SPEED]
  scatter(maxv)
  local inside, speeds, finite = true, true, true
  for _ = 1, 400 do
    step(maxv)
    for i = 1, N do
      if not (X[i] == X[i] and Y[i] == Y[i]) then finite = false end
      if X[i] < 0 or X[i] > W - 1 or Y[i] < 0 or Y[i] > SKY - 1 then inside = false end
      local s = math.sqrt(VX[i] * VX[i] + VY[i] * VY[i])
      if s > maxv + 1e-6 or s < maxv * 0.5 - 1e-6 then speeds = false end
    end
  end
  check(finite, "positions stay numbers")
  check(inside, "every bird stays in the sky")
  check(speeds, "every speed stays between half and all of the top speed")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("boids needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("boids: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local speedIndex = DEFAULT_SPEED
  local paused = false
  scatter(SPEEDS[speedIndex])

  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then scatter(SPEEDS[speedIndex])
      elseif k == "p" then paused = not paused
      elseif k == "w" or k == "up" then speedIndex = math.min(#SPEEDS, speedIndex + 1)
      elseif k == "s" or k == "down" then speedIndex = math.max(1, speedIndex - 1) end
      k = key.poll()
    end
    if not paused then step(SPEEDS[speedIndex]) end

    gfx.clear(0x000000)
    for i = 1, N do
      local a = math.atan(VY[i], VX[i]) / (2 * math.pi)
      local x, y = math.floor(X[i] + 0.5), math.floor(Y[i] + 0.5)
      -- a dim tail behind the bird, then the bird itself in its heading colour
      gfx.disc(math.floor(X[i] - VX[i] * 2 + 0.5), math.floor(Y[i] - VY[i] * 2 + 0.5), 1, hue(a, 0.4))
      gfx.disc(x, y, 2, hue(a, 1))
    end
    gfx.fill(0, 122, W, 13, 0x000000)
    local status = paused and "paused" or ("speed " .. speedIndex .. " of " .. #SPEEDS)
    gfx.text(2, 124, "w s " .. status .. "  space scatter  q", 0x9aa8c0, 1)
    gfx.flush()
    sys.sleep(30)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("boids: " .. tostring(problem)) end
