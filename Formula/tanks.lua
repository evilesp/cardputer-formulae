#!lua
-- tanks: two players on one keyboard, taking turns. Set the angle and the power of your cannon, then fire at the other tank.
-- Player 1 (left): a d angle, w s power, f fire. Player 2 (right): j l angle, i k power, h fire. Wind pushes the shells a
-- little. A hit digs a crater and damages the tanks near it; the first tank to run out of health loses. n starts a new
-- battle, ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the shells.

local W, H = 240, 135
local GRAVITY = 70       -- pixels a second squared
local BLAST = 10         -- the radius of a crater in pixels
local DT = 0.02

-- the ground: the screen row of the surface at each column (from 0 to W - 1)
local function newGround(seed)
  local p1, p2, p3 = seed * 1.3, seed * 2.1, seed * 0.7
  local ground = {}
  for x = 0, W - 1 do
    ground[x] = math.floor(96 - 12 * math.sin(x * 0.021 + p1) - 6 * math.sin(x * 0.053 + p2) - 2 * math.sin(x * 0.17 + p3))
  end
  return ground
end

-- the shell from (x, y) at an angle (degrees above the ground, 0 to 90) and power (0 to 100): where it lands on the ground
-- (the column and the row) or nil when it flies away. wind is the sideways push in pixels a second squared.
local function shell(ground, x, y, angle, power, wind)
  local speed = power * 2.2
  local rad = math.rad(angle)
  local vx, vy = math.cos(rad) * speed, -math.sin(rad) * speed
  local px, py = x + 0.0, y + 0.0
  for _ = 1, 2000 do
    vx = vx + wind * DT
    vy = vy + GRAVITY * DT
    px, py = px + vx * DT, py + vy * DT
    if px < 0 or px >= W then return nil end
    if py >= ground[math.floor(px)] then return math.floor(px), math.floor(py) end
    if py < -200 then return nil end
  end
  return nil
end

-- digs a crater of radius BLAST at (cx, cy): the ground under it drops
local function dig(ground, cx, cy)
  for dx = -BLAST, BLAST do
    local x = cx + dx
    if x >= 0 and x < W then
      local depth = math.floor(math.sqrt(BLAST * BLAST - dx * dx))
      local bottom = cy + depth
      if ground[x] < bottom then ground[x] = bottom end
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
  local flat = {}
  for x = 0, W - 1 do flat[x] = 100 end
  local x1 = shell(flat, 20, 90, 45, 30, 0)
  local x2 = shell(flat, 20, 90, 45, 45, 0)
  check(x1 and x2 and x2 > x1 and x1 > 20, "a stronger shot flies further")
  check(shell(flat, 20, 90, 45, 90, 0) == nil, "a very strong shot flies off the screen")
  local up = shell(flat, 100, 90, 90, 40, 0)
  check(up == nil or math.abs(up - 100) <= 2, "straight up falls back near the cannon")
  check(shell(flat, 20, 90, 45, 40, 30) > shell(flat, 20, 90, 45, 40, -30), "wind pushes the shell")
  check(shell(flat, 20, 90, 10, 1, 0) ~= nil, "a weak shot still lands on the ground")
  local g = { }
  for x = 0, W - 1 do g[x] = 100 end
  dig(g, 120, 100)
  check(g[120] > 100 and g[125] > 100 and g[120 + BLAST + 2] == 100, "a crater drops the ground near the hit only")
  local made = newGround(3)
  check(made[0] ~= nil and made[W - 1] ~= nil and made[120] >= 60 and made[120] <= 120, "the ground stays on the screen")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("tanks needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("tanks: " .. tostring(uiErr))
  return
end

local ground, tanks, turn, wind, shot, boom, winner

local function newBattle()
  ground = newGround(math.random(100))
  tanks = {
    { x = 30, angle = 45, power = 50, health = 100, colour = 0x40c0ff, keys = { a = -1, d = 1, w = 1, s = -1, fire = "f" } },
    { x = 210, angle = 135, power = 50, health = 100, colour = 0xff8040, keys = { j = -1, l = 1, i = 1, k = -1, fire = "h" } },
  }
  for _, t in ipairs(tanks) do t.y = ground[t.x] - 4 end
  turn, wind, shot, boom, winner = 1, math.random(-20, 20), nil, nil, nil
end

local function clampTank(t)
  t.angle = math.max(5, math.min(175, t.angle))
  t.power = math.max(5, math.min(100, t.power))
end

local function draw()
  gfx.clear(0x87b8e8)
  for x = 0, W - 1 do
    gfx.vline(x, ground[x], H - 1, 0x5a3a20)
    gfx.fill(x, ground[x], 1, 2, 0x3a8a2a)
  end
  for i, t in ipairs(tanks) do
    local y = ground[t.x] - 4
    t.y = y
    gfx.fill(t.x - 8, y - 2, 16, 6, t.colour)
    local rad = math.rad(t.angle)
    gfx.line(t.x, y - 2, math.floor(t.x + math.cos(rad) * 12), math.floor(y - 2 - math.sin(rad) * 12), 0x202020)
    if turn == i and not winner then
      ui.label(t.x - 14, y - 16, "v", 0xffe060)
    end
    ui.label(t.x - 16, y + 6, tostring(t.health), 0xffffff)
  end
  if shot then gfx.disc(math.floor(shot.x), math.floor(shot.y), 2, 0x101010) end
  if boom then gfx.circle(boom.x, boom.y, BLAST * (1 - boom.t / 0.5) + 2, 0xffe060, false) end
  local me = tanks[turn]
  ui.label(4, 2, "P" .. turn .. "  angle " .. me.angle .. "  power " .. me.power, 0xffffff)
  ui.label(150, 2, "wind " .. wind, 0x202020)
  if winner then ui.center(60, "player " .. winner .. " wins! n for a new battle", 0xffe060, 1) end
  ui.label(4, H - 10, "P1 a d w s f    P2 j l i k h    ctrl-q quit", 0x202020)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("tanks: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newBattle()
  local last = sys.millis()
  while true do
    local now = sys.millis()
    local dt = math.min((now - last) / 1000, 0.1)
    last = now
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "n" then newBattle()
      elseif not winner and not shot and not boom then
        local me = tanks[turn]
        for name, step in pairs(me.keys) do
          if k == name and name ~= "fire" then
            if name == "a" or name == "d" or name == "j" or name == "l" then me.angle = me.angle + 3 * step
            else me.power = me.power + 3 * step end
            clampTank(me)
          end
        end
        if k == me.keys.fire then
          local x, y = me.x, me.y - 2
          local rad = math.rad(me.angle)
          shot = { x = x, y = y, vx = math.cos(rad) * me.power * 2.2, vy = -math.sin(rad) * me.power * 2.2 }
        end
      end
      k = key.poll()
    end
    if shot then
      for _ = 1, 3 do
        shot.vx = shot.vx + wind * DT
        shot.vy = shot.vy + GRAVITY * DT
        shot.x, shot.y = shot.x + shot.vx * DT, shot.y + shot.vy * DT
        if shot.x < 0 or shot.x >= W then
          shot = nil
          turn = 3 - turn
          break
        end
        if shot.y >= ground[math.floor(shot.x)] then
          local cx, cy = math.floor(shot.x), math.floor(shot.y)
          dig(ground, cx, cy)
          boom = { x = cx, y = cy, t = 0.5 }
          for i, t in ipairs(tanks) do
            local d = math.sqrt((t.x - cx) ^ 2 + (t.y - cy) ^ 2)
            if d < BLAST + 6 then
              t.health = math.max(0, t.health - math.floor(40 * (1 - d / (BLAST + 6))) - 10)
              if t.health <= 0 then winner = 3 - i end
            end
          end
          shot = nil
          if not winner then turn = 3 - turn end
          wind = math.random(-20, 20)
          break
        end
      end
    end
    if boom then
      boom.t = boom.t - dt
      if boom.t <= 0 then boom = nil end
    end
    for _, t in ipairs(tanks) do t.y = ground[t.x] - 4 end
    draw()
    sys.sleep(20)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("tanks: " .. tostring(problem)) end
