#!lua
-- tiltracer: a road racer in pseudo 3D. Tilt the Cardputer left and right to steer (the motion sensor). w speeds up and s
-- brakes (a and d steer too, for the Cardputer without a sensor). Keep to the road and dodge the cones; the road bends more
-- and more. r starts again, ctrl-q quits. Needs the graphics, the ui package and a motion sensor (the ADV board); the
-- sound of a crash needs firmware v0.1.0.18(beta). Run it with --selftest to check the road, the steering and the cones.

local W, H = 240, 135
local HORIZON = 40
local FOCAL = 94      -- the road is 94 pixels from the horizon to the bottom, at distance 1
local ROAD_HALF = 90  -- half the road width in pixels at distance 1
local SEG = 40        -- the bend of the road changes every 40 units

-- a pseudo random value in -1 .. 1 for a number n
local function noise(n)
  local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
  return (x - math.floor(x)) * 2 - 1
end

-- the bend of the road at distance s: smooth between the segments, -0.7 .. 0.7
local function bendAt(s)
  local i = math.floor(s / SEG)
  local f = s / SEG - i
  local a, b = noise(i) * 0.7, noise(i + 1) * 0.7
  return a + (b - a) * (f * f * (3 - 2 * f))
end

-- how far the middle of the road is pushed sideways at distance z ahead of the car at position s
local function centreOffset(s, z)
  return bendAt(s + z) * z * z * 0.5
end

-- cone n: where it is along the road (its distance) and its sideways position, -0.8 .. 0.8
local function coneAt(n)
  return n * 22 + 14, noise(n * 7.31 + 1.7) * 0.8
end

-- the steering from the sensor's sideways reading (g): a small tilt is no steering, the rest is scaled to -1 .. 1
local function steerOf(ax)
  if not ax or math.abs(ax) < 0.06 then return 0 end
  local sign = ax < 0 and -1 or 1
  local v = (ax - 0.06 * sign) / 0.44
  if v > 1 then return 1 end
  if v < -1 then return -1 end
  return v
end

-- the sensor reads a tilt to the right as a negative value, so the car steers the way the Cardputer is tilted
local function steerFromSensor(ax)
  return -steerOf(ax)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(math.abs(bendAt(0.0)) <= 0.7 and math.abs(bendAt(123.4)) <= 0.71, "the bend stays within its range")
  check(bendAt(40) == bendAt(40) and bendAt(10) ~= bendAt(50), "the bend is the same every time and changes along the road")
  check(centreOffset(0, 0) == 0, "at the car the road is in the middle")
  check(steerOf(nil) == 0 and steerOf(0.03) == 0 and steerOf(-0.04) == 0, "a small tilt is no steering")
  check(steerOf(0.3) > 0.4 and steerOf(0.3) < 0.6 and steerOf(-0.3) < -0.4, "a tilt steers in its direction")
  check(steerOf(5) == 1 and steerOf(-5) == -1, "steering is limited")
  check(steerFromSensor(-0.3) > 0.4 and steerFromSensor(0.3) < -0.4, "tilting right (negative reading) steers right")
  check(steerFromSensor(nil) == 0, "no sensor, no steering from the sensor")
  local d, q = coneAt(3)
  check(d > 0 and q >= -0.8 and q <= 0.8, "the cones are on the road")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("tiltracer needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("tiltracer: " .. tostring(uiErr))
  return
end

local pos, speed, lateral, score, crashes = 0.0, 0.0, 0.0, 0, 0
local flashT = 0

local function reset()
  pos, speed, lateral, score, crashes = 0.0, 0.0, 0.0, 0, 0
end

-- the road: each screen row is a distance, and nearer rows are wider; stripes move with the speed
local function drawRoad()
  gfx.fill(0, 0, W, HORIZON, 0x1d3a5c)
  for y = HORIZON + 1, H - 1 do
    local z = FOCAL / (y - HORIZON)
    local cx = W / 2 + ROAD_HALF * centreOffset(pos, z) / z
    local half = ROAD_HALF / z
    local stripe = math.floor(pos / 4 + z) % 2 == 0
    gfx.fill(0, y, W, 1, stripe and 0x2e6b2e or 0x2a5f2a)
    local left = math.floor(cx - half)
    gfx.fill(left, y, math.floor(2 * half) + 1, 1, stripe and 0x555555 or 0x5f5f5f)
    gfx.fill(left - 2, y, 2, 1, 0xf0f0f0)
    gfx.fill(left + math.floor(2 * half) + 1, y, 2, 1, 0xf0f0f0)
  end
  for n = math.floor(pos / 22), math.floor(pos / 22) + 10 do
    local d, q = coneAt(n)
    local dist = d - pos
    if dist > 0.5 and dist < 40 then
      local y = HORIZON + math.floor(FOCAL / dist)
      local cx = W / 2 + ROAD_HALF * (centreOffset(pos, dist) + q) / dist
      if y < H then gfx.fill(math.floor(cx) - 2, y - 4, 4, 4, 0xff7020) end
    end
  end
end

local function drawCar()
  local x = math.floor(W / 2 + ROAD_HALF * lateral * 0.7)
  gfx.fill(x - 10, H - 18, 20, 10, 0xd02020)
  gfx.fill(x - 8, H - 24, 16, 7, 0xa01818)
  gfx.fill(x - 9, H - 9, 4, 4, 0x101010)
  gfx.fill(x + 5, H - 9, 4, 4, 0x101010)
end

-- one step of the game: steer is -1 .. 1, accel and brake are booleans
local function update(dt, steer, accel, brake)
  lateral = lateral + steer * dt * 1.6 - bendAt(pos) * dt * speed * 0.25  -- the bends push the car out
  if accel then speed = math.min(6.0, speed + 2.0 * dt) else speed = math.max(0.0, speed - 0.8 * dt) end
  if brake then speed = math.max(0.0, speed - 3.0 * dt) end
  if math.abs(lateral) > 1.0 then speed = math.max(0.0, speed - 2.0 * dt) end  -- off the road is slow
  pos = pos + speed * dt
  score = math.floor(pos)
  for n = math.floor(pos / 22), math.floor(pos / 22) + 2 do
    local d, q = coneAt(n)
    if math.abs(d - pos) < 0.6 and math.abs(lateral - q) < 0.35 then
      speed = speed * 0.4
      crashes = crashes + 1
      flashT = 0.4
      if audio and audio.beep then pcall(audio.beep, 180, 90) end
    end
  end
  flashT = math.max(0, flashT - dt)
end

local w, h = ui.open()
if not w then
  print("tiltracer: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local last = sys.millis()
  while true do
    local now = sys.millis()
    local dt = math.min((now - last) / 1000, 0.1)
    last = now
    local held = key.down and key.down() or {}
    local accel, brake, keySteer = false, false, 0
    for _, k in ipairs(held) do
      if k == "w" then accel = true end
      if k == "s" then brake = true end
      if k == "a" then keySteer = keySteer - 1 end
      if k == "d" then keySteer = keySteer + 1 end
    end
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "r" then reset() end
      k = key.poll()
    end
    local ax = nil
    if sys.imu then ax = sys.imu() end
    local steer = steerFromSensor(ax)
    if steer == 0 then steer = keySteer end
    update(dt, steer, accel, brake)
    gfx.clear(0x000000)
    drawRoad()
    drawCar()
    if flashT > 0 then gfx.fill(0, 0, W, H, 0x602020) end
    ui.label(4, 2, "score " .. score .. "   crashes " .. crashes, 0xe8ecf4)
    ui.label(150, H - 9, string.format("%d km/h", math.floor(speed * 30)), 0xe8ecf4)
    gfx.flush()
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("tiltracer: " .. tostring(problem)) end
