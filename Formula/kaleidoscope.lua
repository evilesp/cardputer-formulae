#!lua
-- kaleidoscope: a bright point wanders on a looping path, and every copy of it is mirrored around the centre, so
-- the trail turns into a symmetric flower of coloured dots. space starts a new pattern, a and d change the number of
-- mirror sides (4 to 12), w and s change the speed, c clears the trail, p pauses, q quits.
-- Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the maths.

local W, H = 240, 135
local CX, CY = W / 2, H / 2
local TRAIL = 24
local SIDES = { 4, 6, 8, 10, 12 }
local SPEEDS = { 0.01, 0.02, 0.03, 0.045, 0.065, 0.09, 0.12 }

-- the same colour wheel as spirograph: hue h in turns, v the brightness
local function hue(h, v)
  h = (h % 1) * 6
  local i, f = math.floor(h), h - math.floor(h)
  local rr, g, b
  if i == 0 then rr, g, b = 1, f, 0 elseif i == 1 then rr, g, b = 1 - f, 1, 0 elseif i == 2 then rr, g, b = 0, 1, f
  elseif i == 3 then rr, g, b = 0, 1 - f, 1 elseif i == 4 then rr, g, b = f, 0, 1 else rr, g, b = 1, 0, 1 - f end
  return (math.floor(rr * v * 255) << 16) | (math.floor(g * v * 255) << 8) | math.floor(b * v * 255)
end

-- the point at time t: its distance and its angle around the centre both swing, so the path loops
local function pointAt(p, t)
  local r = p.r0 * (0.55 + 0.45 * math.sin(p.fr * t + p.pr))
  local a = p.fa * t + p.pa
  return r * math.cos(a), r * math.sin(a)
end

-- copy j of a point: every second copy is flipped across the horizontal line, then all copies turn by 1/sides
local function mirror(x, y, j, sides)
  if j % 2 == 1 then y = -y end
  local a = 2 * math.pi * j / sides
  local c, s = math.cos(a), math.sin(a)
  return x * c - y * s, x * s + y * c
end

-- the ring buffer slot of the point that is `age` steps old (age 0 is the newest, the head is the next write)
local function slot(head, age)
  return (head - 1 - age) % TRAIL
end

local function randomPattern()
  return {
    r0 = math.random(26, 58),
    fr = math.random(2, 7) * 0.05,
    pr = math.random() * 2 * math.pi,
    fa = (math.random(2, 9) * 0.5) * (math.random(0, 1) == 0 and 1 or -1),
    pa = math.random() * 2 * math.pi,
    hue = math.random(),
  }
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local x, y = mirror(10, 0, 0, 6)
  check(math.abs(x - 10) < 1e-9 and math.abs(y) < 1e-9, "copy 0 stays where it is")
  x, y = mirror(10, 0, 1, 4)
  check(math.abs(x) < 1e-9 and math.abs(y - 10) < 1e-9, "a quarter turn of the mirrored copy")
  x, y = mirror(3, 4, 1, 8)
  local dist = math.sqrt(x * x + y * y)
  check(dist > 4.99 and dist < 5.01, "mirroring keeps the distance")
  local good = true
  for _ = 1, 40 do
    local p = randomPattern()
    for k = 0, 50 do
      local px, py = pointAt(p, k * 0.37)
      local d = math.sqrt(px * px + py * py)
      if d > p.r0 + 1e-9 or d < 0.1 * p.r0 - 1e-9 then good = false end
    end
  end
  check(good, "the point stays between 10 and 100 percent of its radius")
  local slots, seen = true, {}
  for age = 0, TRAIL - 1 do
    local s = slot(5, age)
    if s < 0 or s >= TRAIL or seen[s] then slots = false end
    seen[s] = true
  end
  check(slots and slot(0, 0) == TRAIL - 1, "the trail buffer holds every point once")
  local even = true
  for _, n in ipairs(SIDES) do if n % 2 ~= 0 or n < 4 then even = false end end
  check(even, "mirror sides are even and at least 4")
  check(hue(0, 1) == 0xff0000 and hue(1 / 3, 1) == 0x00ff00, "hue")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("kaleidoscope needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("kaleidoscope: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local p = randomPattern()
  local sideIndex, speedIndex = 2, 3
  local t, paused = 0, false
  local tx, ty = {}, {}
  local head, count = 0, 0
  for i = 1, TRAIL do tx[i], ty[i] = 0, 0 end

  local function fresh()
    p = randomPattern()
    count = 0
  end

  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " or k == "n" then fresh()
      elseif k == "p" then paused = not paused
      elseif k == "c" then count = 0
      elseif k == "a" or k == "left" then sideIndex = math.max(1, sideIndex - 1)
      elseif k == "d" or k == "right" then sideIndex = math.min(#SIDES, sideIndex + 1)
      elseif k == "w" or k == "up" then speedIndex = math.min(#SPEEDS, speedIndex + 1)
      elseif k == "s" or k == "down" then speedIndex = math.max(1, speedIndex - 1) end
      k = key.poll()
    end
    if not paused then
      t = t + SPEEDS[speedIndex]
      local x, y = pointAt(p, t)
      head = (head + 1) % TRAIL
      tx[head + 1], ty[head + 1] = x, y
      if count < TRAIL then count = count + 1 end
      p.hue = p.hue + 0.002
    end
    gfx.clear(0x000000)
    local sides = SIDES[sideIndex]
    for age = 0, count - 1 do
      local s = slot(head, age) + 1
      local v = 1 - age / TRAIL * 0.8
      local c = hue(p.hue + age * 0.012, v)
      local r = age < 6 and 2 or 1
      for j = 0, sides - 1 do
        local mx, my = mirror(tx[s], ty[s], j, sides)
        gfx.disc(math.floor(CX + mx + 0.5), math.floor(CY + my + 0.5), r, c)
      end
    end
    gfx.fill(0, 122, W, 13, 0x000000)
    gfx.text(2, 124, "a d sides " .. sides .. "  w s speed  space new  q", 0x9aa8c0, 1)
    gfx.flush()
    sys.sleep(20)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("kaleidoscope: " .. tostring(problem)) end
