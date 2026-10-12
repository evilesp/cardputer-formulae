#!lua
-- tiltracer: a race against five bots on a track with bends and hills, in pseudo 3D. The car speeds up by itself; s brakes,
-- a and d steer (or tilt the Cardputer to steer, t switches the tilt on and off). Bump into a car and you lose speed; off the
-- road you are slow. Three laps (or five); you start last and must get to the front. Choose easy, normal or hard bots.
-- r starts the race again, ctrl-q quits. Needs the graphics and the ui package; the motion sensor is used when it is there.
-- Run it with --selftest to check the track, the steering and the race order.

local W, H = 240, 135
local SEG = 200            -- the length of a segment of road
local ROAD = 2000          -- half the width of the road
local CAM_H = 1000         -- the height of the camera
local DEPTH = 0.84         -- 1 / tan(fov / 2) for a field of view of 100 degrees
local DRAW = 34            -- the segments drawn ahead (more is slower on the Cardputer)
local MAX_SPEED = SEG * 60 -- per second
local PLAYER_Z = CAM_H * DEPTH
local CENTRIFUGAL = 0.3

-- the track: sections of { segments, bend, rise } (rise in segment lengths). The bend is 0 at both ends of a section and
-- strongest in its middle; the hills are smooth too. The last section brings the road back to its starting height.
local SECTIONS = {
  { 120, 0, 0 }, { 160, 3, 0 }, { 120, 0, 20 }, { 200, -4, -10 }, { 140, 0, 30 }, { 180, 5, -30 },
  { 120, -2, 10 }, { 220, -5, 0 }, { 160, 0, -20 }, { 200, 4, 15 }, { 160, -3, -15 }, { 140, 0, 0 },
}
local starts, heights, COUNT = {}, {}, 0
do
  local y = 0
  for i, s in ipairs(SECTIONS) do
    starts[i] = COUNT
    heights[i] = y
    COUNT = COUNT + s[1]
    y = y + s[3] * SEG
  end
  SECTIONS[#SECTIONS][3] = SECTIONS[#SECTIONS][3] - y / SEG  -- the loop closes at height 0
end
local TRACK = COUNT * SEG

local function sectionOf(i)
  i = i % COUNT
  for k = #SECTIONS, 1, -1 do
    if i >= starts[k] then return k, i - starts[k] end
  end
  return 1, i
end

-- the bend of segment i
local function curveAt(i)
  local k, t = sectionOf(i)
  local s = SECTIONS[k]
  return s[2] * math.sin(math.pi * t / s[1])
end

-- the height of the road at the start of segment i
local function heightAt(i)
  local k, t = sectionOf(i)
  local s = SECTIONS[k]
  return heights[k] + s[3] * SEG * (1 - math.cos(math.pi * t / s[1])) / 2
end

-- a pseudo random value 0 .. 1 for a number
local function noise(n)
  local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
  return x - math.floor(x)
end

-- the steering from the motion sensor's sideways reading: a small tilt is nothing, tilting right steers right
local function steerFromSensor(ax)
  if not ax or math.abs(ax) < 0.06 then return 0 end
  local sign = ax < 0 and -1 or 1
  local v = (ax - 0.06 * sign) / 0.44
  return -math.max(-1, math.min(1, v))
end

-- the order of the race: everyone by laps done and then by distance, the leader first
local function standings(cars)
  local order = {}
  for i, c in ipairs(cars) do order[i] = c end
  table.sort(order, function(a, b) return a.lap * TRACK + a.z > b.lap * TRACK + b.z end)
  return order
end

local function lapTime(ms)
  return string.format("%d:%04.1f", ms // 60000, (ms % 60000) / 1000)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(COUNT > 1500, "a lap is long enough (" .. COUNT .. " segments)")
  check(math.abs(heightAt(0)) < 1e-6 and math.abs(heightAt(COUNT)) < 1e-6, "the track starts and ends at the same height")
  local jump = 0
  for i = 0, COUNT - 1 do jump = math.max(jump, math.abs(heightAt(i + 1) - heightAt(i)), math.abs(curveAt(i + 1) - curveAt(i)) * SEG) end
  check(jump < SEG * 0.8, "no steps in the hills and the bends (" .. jump .. ")")
  check(curveAt(0) == 0 and math.abs(curveAt(starts[2] + 80) - 3) < 0.01, "a bend is strongest in the middle of its section")
  check(steerFromSensor(nil) == 0 and steerFromSensor(0.03) == 0, "a small tilt is no steering")
  check(steerFromSensor(-0.3) > 0.4 and steerFromSensor(0.3) < -0.4 and steerFromSensor(5) == -1, "tilting steers, limited")
  local order = standings({ { name = "a", lap = 0, z = 500 }, { name = "b", lap = 1, z = 100 }, { name = "c", lap = 0, z = 900 } })
  check(order[1].name == "b" and order[2].name == "c" and order[3].name == "a", "laps count before distance")
  check(lapTime(83400) == "1:23.4" and lapTime(5000) == "0:05.0", "lap times")
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

local function mix(a, b, t)
  if t <= 0 then return a elseif t >= 1 then return b end
  local function ch(sh) return math.floor(((a >> sh) & 255) + (((b >> sh) & 255) - ((a >> sh) & 255)) * t + 0.5) end
  return (ch(16) << 16) | (ch(8) << 8) | ch(0)
end

local SKY_TOP, SKY_LOW, FOG = 0x2a6ab8, 0x9ccaf0, 0xa8d0f0
local COLORS = {
  light = { road = 0x6a6a6e, grass = 0x3c9a3a, rumble = 0xe8e8e8, lane = 0xe8e8e8 },
  dark = { road = 0x646468, grass = 0x358a34, rumble = 0xc83030 },
}
local BOT_COLORS = { 0x2a70e0, 0xf0c020, 0x30b050, 0xe060c0, 0xf08020 }
local BOT_NAMES = { "Blue", "Yellow", "Green", "Pink", "Orange" }
local LEVELS = { { name = "easy", lo = 0.70, hi = 0.80 }, { name = "normal", lo = 0.80, hi = 0.90 }, { name = "hard", lo = 0.88, hi = 0.97 } }

-- the projected corners of the segments in view, kept in flat lists (no new tables every frame)
local sx1, sy1, sw1, sx2, sy2, sw2, sclip, sscale = {}, {}, {}, {}, {}, {}, {}, {}
local sidx = {}

-- the far mountains: two rows of peaks, made once
local peaks = {}
for i = 1, 24 do peaks[i] = { h = 10 + noise(i) * 22, far = i % 2 == 0 } end

local player, bots, laps, level, state, raceStart, countStart, finishPos, lapStart, bestLap, lastLap, skyOffset, useTilt
local bumpT = 0

local function newRace()
  player = { z = 0, x = 0, speed = 0, lap = 0, name = "YOU", player = true }
  bots = {}
  for i = 1, 5 do
    local lv = LEVELS[level]
    bots[i] = { z = (i * 3 + (i % 2) * 2) * SEG, x = (i % 2 == 0) and -0.45 or 0.45, speed = 0, lap = 0, name = BOT_NAMES[i],
                color = BOT_COLORS[i], top = MAX_SPEED * (lv.lo + (lv.hi - lv.lo) * (i - 1) / 4), aim = 0, aimT = 0 }
  end
  state, countStart, finishPos, bestLap, lastLap, skyOffset = "count", sys.millis(), nil, nil, nil, 0
end

local function quad(x1, y1, w1, x2, y2, w2, colour)
  gfx.triangle(math.floor(x1 - w1), y1, math.floor(x1 + w1), y1, math.floor(x2 + w2), y2, colour)
  gfx.triangle(math.floor(x1 - w1), y1, math.floor(x2 + w2), y2, math.floor(x2 - w2), y2, colour)
end

-- a car seen from behind: w is its width in pixels, (x, y) the middle of its bottom
local function drawCar(x, y, w, colour, steer)
  x, y, w = math.floor(x), math.floor(y), math.max(4, math.floor(w))
  local h = math.max(3, w * 45 // 100)
  local dark = mix(colour, 0x000000, 0.45)
  if w >= 10 then
    gfx.fill(x - w // 2, y - h // 3, w // 5, h // 3, 0x101010)            -- the wheels
    gfx.fill(x + w // 2 - w // 5, y - h // 3, w // 5, h // 3, 0x101010)
  end
  gfx.fill(x - w // 2 + 1, y - h + h // 4, w - 2, h - h // 3, colour)       -- the body
  gfx.fill(x - w // 3 + (steer or 0), y - h, w * 2 // 3, h // 3 + 1, dark)  -- the roof and the rear window
  if w >= 14 then
    gfx.fill(x - w // 4 + (steer or 0), y - h + 1, w // 2, math.max(1, h // 5), 0x9cc0e0)
    gfx.fill(x - w // 2 + 2, y - h // 3 - 2, w // 6, 2, 0xff3020)              -- the tail lights
    gfx.fill(x + w // 2 - 2 - w // 6, y - h // 3 - 2, w // 6, 2, 0xff3020)
    gfx.fill(x - w // 2 - 1, y - h + h // 4 - 2, w + 2, 2, dark)               -- the spoiler
  end
end

local function drawTree(x, y, size, kind)
  x, y, size = math.floor(x), math.floor(y), math.max(2, math.floor(size))
  if kind == 1 then  -- a pine
    gfx.fill(x - size // 12, y - size // 4, math.max(1, size // 6), size // 4, 0x4a2c14)
    gfx.triangle(x, y - size, x - size // 3, y - size // 4, x + size // 3, y - size // 4, 0x1c5a2a)
    gfx.triangle(x, y - size, x - size // 5, y - size // 2, x + size // 5, y - size // 2, 0x2a7a38)
  else  -- a round tree
    gfx.fill(x - size // 14, y - size // 3, math.max(1, size // 7), size // 3, 0x5a3418)
    gfx.disc(x, y - size * 2 // 3, size // 3, 0x2c8a30)
    gfx.disc(x - size // 10, y - size * 3 // 4, size // 6, 0x48a840)
  end
end

local function project(worldY, camX, camY, camZ, worldZ)
  local z = worldZ - camZ
  if z < 1 then z = 1 end
  local scale = DEPTH / z
  return W / 2 + scale * (-camX) * W / 2, H / 2 - scale * (worldY - camY) * H / 2, scale * ROAD * W / 2, scale
end

local function drawBackground()
  for y = 0, H // 2 + 6, 6 do gfx.fill(0, y, W, 6, mix(SKY_TOP, SKY_LOW, y / (H / 2))) end
  gfx.disc(196, 18, 9, 0xfff4c8)
  gfx.disc(196, 18, 12, mix(SKY_LOW, 0xfff4c8, 0.25))
  gfx.disc(196, 18, 9, 0xfff4c8)
  -- the mountains move sideways as the road bends
  for pass = 1, 2 do
    local colour = pass == 1 and 0x7a92b8 or 0x5a7a68
    local span = pass == 1 and 40 or 30
    local base = H // 2 + 4
    local shift = (skyOffset * (pass == 1 and 0.3 or 0.6)) % span
    for i = -1, W // span + 1 do
      local p = peaks[((i + math.floor(skyOffset * (pass == 1 and 0.3 or 0.6) / span)) % #peaks) + 1]
      local h = math.floor(p.h * (pass == 1 and 1 or 0.6))
      local x = math.floor(i * span - shift)
      gfx.triangle(x, base, x + span // 2, base - h, x + span + span // 2, base, colour)
    end
  end
end

local function render()
  drawBackground()
  local base = math.floor(player.z / SEG)
  local basePercent = (player.z % SEG) / SEG
  local playerSeg = math.floor((player.z + PLAYER_Z) / SEG)
  local pPercent = ((player.z + PLAYER_Z) % SEG) / SEG
  local playerY = heightAt(playerSeg) + (heightAt(playerSeg + 1) - heightAt(playerSeg)) * pPercent
  local camY = playerY + CAM_H
  local maxy = H
  local x, dx = 0, -(curveAt(base) * basePercent)
  local count = 0
  for n = 0, DRAW - 1 do
    local i = base + n
    local camX = player.x * ROAD
    local z1, z2 = i * SEG, (i + 1) * SEG
    local ax, ay, aw, ascale = project(heightAt(i), camX - x, camY, player.z, z1)
    local bx, by, bw = project(heightAt(i + 1), camX - x - dx, camY, player.z, z2)
    x = x + dx
    dx = dx + curveAt(i)
    count = count + 1
    sx1[count], sy1[count], sw1[count], sx2[count], sy2[count], sw2[count], sscale[count], sidx[count] = ax, ay, aw, bx, by, bw, ascale, i
    sclip[count] = maxy
    if z1 - player.z > DEPTH and by < ay and by < maxy then
      local y1, y2 = math.floor(ay), math.floor(by)
      local fog = n / DRAW
      local c = (i // 3) % 2 == 0 and COLORS.light or COLORS.dark
      local bottom = math.min(y1, maxy)
      gfx.fill(0, y2, W, bottom - y2 + 1, mix(c.grass, FOG, fog * 0.8))
      quad(ax, y1, aw * 1.15, bx, y2, bw * 1.15, mix(c.rumble, FOG, fog * 0.8))
      quad(ax, y1, aw, bx, y2, bw, mix(c.road, FOG, fog * 0.7))
      if c.lane and y1 - y2 >= 1 then
        quad(ax, y1, aw * 0.03, bx, y2, bw * 0.03, mix(c.lane, FOG, fog))
      end
      if i % COUNT < 3 then  -- the start and finish line, black and white
        quad(ax, y1, aw, bx, y2, bw, (i % 2 == 0) and 0xf0f0f0 or 0x202020)
      end
      maxy = y2
    end
  end
  -- the trees, the start gate and the cars, far ones first
  local all = { player }
  for _, b in ipairs(bots) do all[#all + 1] = b end
  for k = count, 1, -1 do
    local i, scale = sidx[k], sscale[k]
    local clip = sclip[k]
    local y = sy1[k]
    if y < clip + 2 and scale > 0 then
      local roadPx = sw1[k]
      local r = noise(i)
      if i % 6 == 0 then drawTree(sx1[k] - roadPx * (1.35 + r * 0.6), y, roadPx * 0.9, i % 12 == 0 and 1 or 2) end
      if i % 7 == 3 then drawTree(sx1[k] + roadPx * (1.4 + r * 0.5), y, roadPx * 0.8, i % 14 == 3 and 2 or 1) end
      if i % COUNT == 2 then  -- the gate over the start line
        local l, rr = math.floor(sx1[k] - roadPx * 1.1), math.floor(sx1[k] + roadPx * 1.1)
        local top = math.floor(y - roadPx * 0.9)
        gfx.fill(l, top, math.max(1, roadPx // 20), y - top, 0xd0d0d0)
        gfx.fill(rr, top, math.max(1, roadPx // 20), y - top, 0xd0d0d0)
        gfx.fill(l, top, rr - l, math.max(2, roadPx // 8), 0xd02020)
      end
      for _, b in ipairs(bots) do
        local bseg = math.floor(b.z / SEG)
        if bseg % COUNT == i % COUNT and not b.drawn then
          b.drawn = true
          drawCar(sx1[k] + b.x * roadPx, y, roadPx * 0.27, b.color)
        end
      end
    end
  end
  for _, b in ipairs(bots) do b.drawn = nil end
  -- your car, tilting into the bends
  local steer = player.steer or 0
  drawCar(W / 2, H - 3, 58, 0xd82020, math.floor(steer * 3))
end

-- the bots: they speed up to their own top speed, keep a little behind or ahead of you (so the race stays close), change
-- lanes now and then, and go round a slower car in front of them
local function updateBots(dt)
  for _, b in ipairs(bots) do
    local gap = (b.lap * TRACK + b.z) - (player.lap * TRACK + player.z)
    local band = gap > 6 * SEG and 0.94 or (gap < -10 * SEG and 1.06 or 1)
    local target = b.top * band
    if b.speed < target then b.speed = math.min(target, b.speed + MAX_SPEED / 6 * dt) else b.speed = b.speed - MAX_SPEED / 8 * dt end
    b.aimT = b.aimT - dt
    if b.aimT <= 0 then
      b.aim = (noise(b.z + b.top) * 2 - 1) * 0.6
      b.aimT = 2 + noise(b.z) * 3
    end
    for _, o in ipairs({ player, table.unpack(bots) }) do
      if o ~= b then
        local ahead = ((o.lap * TRACK + o.z) - (b.lap * TRACK + b.z))
        if ahead > 0 and ahead < 8 * SEG and math.abs(o.x - b.x) < 0.5 and o.speed < b.speed then
          b.aim = o.x > 0 and o.x - 0.7 or o.x + 0.7
          if ahead < 2 * SEG then b.speed = math.min(b.speed, o.speed) end
        end
      end
    end
    b.aim = math.max(-0.8, math.min(0.8, b.aim))
    b.x = b.x + (b.aim - b.x) * math.min(1, dt * 1.5)
    b.z = b.z + b.speed * dt
    if b.z >= TRACK then
      b.z = b.z - TRACK
      b.lap = b.lap + 1
    end
  end
end

local function updatePlayer(dt, steer, brake)
  local seg = math.floor((player.z + PLAYER_Z) / SEG)
  local pct = player.speed / MAX_SPEED
  player.steer = steer
  player.x = player.x + steer * dt * 2 * pct - curveAt(seg) * pct * pct * dt * CENTRIFUGAL * 2
  if brake then player.speed = player.speed - MAX_SPEED * dt
  elseif state == "race" or state == "done" then player.speed = player.speed + MAX_SPEED / 5 * dt end
  if math.abs(player.x) > 1.05 and player.speed > MAX_SPEED / 4 then player.speed = player.speed - MAX_SPEED / 1.5 * dt end
  player.x = math.max(-2.2, math.min(2.2, player.x))
  -- a bump into a car ahead: you slow to its speed and bounce a little to the side
  for _, b in ipairs(bots) do
    local d = (b.lap * TRACK + b.z) - (player.lap * TRACK + player.z + PLAYER_Z)
    if d > -SEG * 0.5 and d < SEG * 0.8 and math.abs(b.x - player.x) < 0.42 and player.speed > b.speed then
      player.speed = b.speed * 0.85
      player.x = player.x + (player.x < b.x and -0.15 or 0.15)
      bumpT = 0.3
      if audio and audio.beep then pcall(audio.beep, 140, 70) end
    end
  end
  player.speed = math.max(0, math.min(MAX_SPEED, player.speed))
  player.z = player.z + player.speed * dt
  skyOffset = skyOffset + curveAt(seg) * pct * dt * 30
  if player.z >= TRACK then
    player.z = player.z - TRACK
    player.lap = player.lap + 1
    local now = sys.millis()
    lastLap = now - lapStart
    if not bestLap or lastLap < bestLap then bestLap = lastLap end
    lapStart = now
    if player.lap >= laps and state == "race" then
      state = "done"
      local order = standings({ player, table.unpack(bots) })
      for p, c in ipairs(order) do if c == player then finishPos = p end end
    end
  end
end

local function hud()
  local order = standings({ player, table.unpack(bots) })
  local pos = 1
  for p, c in ipairs(order) do if c == player then pos = p end end
  gfx.fill(0, 0, W, 11, 0x101820)
  ui.label(3, 2, "POS " .. (finishPos or pos) .. "/6", 0xffe060)
  ui.label(62, 2, "LAP " .. math.min(laps, player.lap + 1) .. "/" .. laps, 0xe8ecf4)
  local t = state == "count" and 0 or (sys.millis() - raceStart)
  ui.label(126, 2, lapTime(t), 0xe8ecf4)
  ui.label(W - 52, 2, string.format("%3d km/h", math.floor(player.speed / MAX_SPEED * 240)), 0xe8ecf4)
  if state == "count" then
    local left = 3 - (sys.millis() - countStart) // 1000
    for i = 0, 2 do gfx.disc(96 + i * 24, 34, 8, (3 - left) > i and 0xff3020 or 0x401010) end
    ui.center(48, left > 0 and tostring(left) or "GO!", 0xffffff, 2)
  elseif state == "done" then
    gfx.fill(40, 40, 160, 46, 0x101820)
    gfx.rect(40, 40, 160, 46, 0xffe060)
    ui.center(46, finishPos == 1 and "YOU WIN!" or ("FINISHED " .. finishPos .. ". OF 6"), finishPos == 1 and 0x60ff90 or 0xffe060, 1)
    if bestLap then ui.center(60, "best lap " .. lapTime(bestLap), 0xe8ecf4, 1) end
    ui.center(72, "r race again  ctrl-q quit", 0x8a94aa, 1)
  elseif lastLap and sys.millis() - lapStart < 2500 then
    ui.center(24, "lap " .. lapTime(lastLap), 0xffffff, 1)
  end
  if useTilt then ui.label(3, H - 10, "tilt", 0x8a94aa) end
end

local w, h = ui.open()
if not w then
  print("tiltracer: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local pick = ui.choose("Race: bots", { "easy bots", "normal bots", "hard bots" }, { selected = 2 })
  if not pick then return end
  level = pick
  local lapsPick = ui.choose("Race: laps", { "3 laps", "5 laps" })
  if not lapsPick then return end
  laps = lapsPick == 1 and 3 or 5
  useTilt = sys.imu ~= nil and sys.imu() ~= nil
  newRace()
  local last = sys.millis()
  while true do
    local now = sys.millis()
    local dt = math.min((now - last) / 1000, 0.1)
    last = now
    local held = key.down and key.down() or {}
    local keySteer, brake = 0, false
    for _, k in ipairs(held) do
      if k == "a" or k == "left" then keySteer = keySteer - 1 end
      if k == "d" or k == "right" then keySteer = keySteer + 1 end
      if k == "s" or k == "down" then brake = true end
    end
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "r" then newRace() end
      if k == "t" then useTilt = not useTilt end
      if not key.down then  -- without the list of held keys a press steers for a moment
        if k == "a" then keySteer = -1 elseif k == "d" then keySteer = 1 elseif k == "s" then brake = true end
      end
      k = key.poll()
    end
    local steer = keySteer
    if steer == 0 and useTilt and sys.imu then steer = steerFromSensor(sys.imu()) end
    if state == "count" and now - countStart >= 3000 then
      state, raceStart, lapStart = "race", now, now
      if audio and audio.beep then pcall(audio.beep, 880, 200) end
    end
    if state ~= "count" then
      updateBots(dt)
      updatePlayer(dt, steer, brake)
    end
    bumpT = math.max(0, bumpT - dt)
    render()
    hud()
    if bumpT > 0 then gfx.rect(0, 0, W, H, 0xff4020) end
    gfx.flush()
    sys.sleep(5)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("tiltracer: " .. tostring(problem)) end
