#!lua
-- asteroids: fly the ship, shoot the rocks. a and d turn the ship, w thrusts and space fires. A big rock breaks into two
-- smaller ones, and the smallest vanish. The screen wraps around. Three lives. ctrl-q quits. Needs the graphics and the ui
-- package. Holding the keys works on firmware v0.1.0.18 (key.down); on older firmware every press turns, thrusts or fires.
-- Run it with --selftest to check the physics and the splitting.

local W, H = 240, 135
local SHIP_R = 4
local BULLET_LIFE = 1.1
local SPEED_MAX = 90

-- a coordinate that wraps around the screen of size size
local function wrap(v, size)
  return (v % size + size) % size
end

-- the children of a rock: size 3 breaks into two of size 2, size 2 into two of size 1, size 1 is gone
local function splitOf(rock)
  if rock.size <= 1 then return {} end
  local kids = {}
  for i = 1, 2 do
    local a = math.random() * 2 * math.pi
    kids[i] = { x = rock.x, y = rock.y, vx = rock.vx + math.cos(a) * 30, vy = rock.vy + math.sin(a) * 30, size = rock.size - 1 }
  end
  return kids
end

local RADIUS = { 16, 9, 5 }
local POINTS = { 20, 50, 100 }

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(wrap(-5, 240) == 235 and wrap(245, 240) == 5 and wrap(100, 240) == 100, "the screen wraps")
  local big = { x = 10, y = 10, vx = 0, vy = 0, size = 3 }
  local kids = splitOf(big)
  check(#kids == 2 and kids[1].size == 2 and kids[2].size == 2, "a big rock breaks into two medium ones")
  check(#splitOf({ x = 0, y = 0, vx = 0, vy = 0, size = 1 }) == 0, "the smallest rock is gone")
  check(RADIUS[1] > RADIUS[2] and RADIUS[2] > RADIUS[3] and POINTS[3] > POINTS[1], "bigger rocks are worth more")
  local near = math.sqrt((13 - 10) ^ 2 + (14 - 10) ^ 2)
  check(near < RADIUS[1], "a point inside a big rock hits it")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("asteroids needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("asteroids: " .. tostring(uiErr))
  return
end

local ship, bullets, rocks, lives, score, invulnerable
local function spawnShip()
  ship = { x = W / 2, y = H / 2, vx = 0, vy = 0, a = -math.pi / 2 }
  invulnerable = 2.0
end

local function newWave(n)
  rocks = {}
  for i = 1, n do
    local a = math.random() * 2 * math.pi
    rocks[#rocks + 1] = { x = math.random(W), y = math.random(H), vx = math.cos(a) * 20, vy = math.sin(a) * 20, size = 3 }
  end
end

local function draw()
  gfx.clear(0x0a0c14)
  for _, r in ipairs(rocks) do gfx.circle(math.floor(r.x), math.floor(r.y), RADIUS[4 - r.size], 0xb0b8c8, false) end
  for _, b in ipairs(bullets) do gfx.fill(math.floor(b.x), math.floor(b.y), 2, 2, 0xffe060) end
  if invulnerable <= 0 or math.floor(invulnerable * 6) % 2 == 0 then
    local nose = { x = ship.x + math.cos(ship.a) * 7, y = ship.y + math.sin(ship.a) * 7 }
    local left = { x = ship.x + math.cos(ship.a + 2.5) * 5, y = ship.y + math.sin(ship.a + 2.5) * 5 }
    local right = { x = ship.x + math.cos(ship.a - 2.5) * 5, y = ship.y + math.sin(ship.a - 2.5) * 5 }
    gfx.line(math.floor(nose.x), math.floor(nose.y), math.floor(left.x), math.floor(left.y), 0x60c8ff)
    gfx.line(math.floor(nose.x), math.floor(nose.y), math.floor(right.x), math.floor(right.y), 0x60c8ff)
    gfx.line(math.floor(left.x), math.floor(left.y), math.floor(right.x), math.floor(right.y), 0x60c8ff)
  end
  ui.label(4, 2, "score " .. score, 0xe8ecf4)
  ui.label(160, 2, "lives " .. lives, 0xe8ecf4)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("asteroids: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  lives, score, bullets = 3, 0, {}
  spawnShip()
  newWave(4)
  local last = sys.millis()
  local fireCooldown = 0
  while true do
    local now = sys.millis()
    local dt = math.min((now - last) / 1000, 0.05)
    last = now
    local turn, thrust, fire = 0, false, false
    local held = key.down and key.down() or nil
    if held then
      for _, k in ipairs(held) do
        if k == "a" then turn = turn - 1 end
        if k == "d" then turn = turn + 1 end
        if k == "w" then thrust = true end
        if k == " " then fire = true end
      end
    end
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if not held then
        if k == "a" then ship.a = ship.a - 0.3 end
        if k == "d" then ship.a = ship.a + 0.3 end
        if k == "w" then ship.vx = ship.vx + math.cos(ship.a) * 40; ship.vy = ship.vy + math.sin(ship.a) * 40 end
        if k == " " then fire = true end
      end
      k = key.poll()
    end
    ship.a = ship.a + turn * dt * 4
    if thrust then
      ship.vx = ship.vx + math.cos(ship.a) * 120 * dt
      ship.vy = ship.vy + math.sin(ship.a) * 120 * dt
    end
    local sp = math.sqrt(ship.vx * ship.vx + ship.vy * ship.vy)
    if sp > SPEED_MAX then ship.vx, ship.vy = ship.vx * SPEED_MAX / sp, ship.vy * SPEED_MAX / sp end
    ship.x, ship.y = wrap(ship.x + ship.vx * dt, W), wrap(ship.y + ship.vy * dt, H)
    invulnerable = math.max(0, invulnerable - dt)
    fireCooldown = math.max(0, fireCooldown - dt)
    if fire and fireCooldown <= 0 and #bullets < 5 then
      bullets[#bullets + 1] = { x = ship.x, y = ship.y, vx = math.cos(ship.a) * 220 + ship.vx, vy = math.sin(ship.a) * 220 + ship.vy, life = BULLET_LIFE }
      fireCooldown = 0.25
    end
    for i = #bullets, 1, -1 do
      local b = bullets[i]
      b.x, b.y = wrap(b.x + b.vx * dt, W), wrap(b.y + b.vy * dt, H)
      b.life = b.life - dt
      if b.life <= 0 then table.remove(bullets, i) end
    end
    for _, r in ipairs(rocks) do
      r.x, r.y = wrap(r.x + r.vx * dt, W), wrap(r.y + r.vy * dt, H)
    end
    -- bullets against rocks
    for i = #bullets, 1, -1 do
      local b = bullets[i]
      for j = #rocks, 1, -1 do
        local r = rocks[j]
        local rad = RADIUS[4 - r.size]
        if (b.x - r.x) ^ 2 + (b.y - r.y) ^ 2 < rad * rad then
          score = score + POINTS[4 - r.size]
          for _, kid in ipairs(splitOf(r)) do rocks[#rocks + 1] = kid end
          table.remove(rocks, j)
          table.remove(bullets, i)
          break
        end
      end
    end
    -- rocks against the ship
    if invulnerable <= 0 then
      for _, r in ipairs(rocks) do
        local rad = RADIUS[4 - r.size]
        if (ship.x - r.x) ^ 2 + (ship.y - r.y) ^ 2 < (rad + SHIP_R) ^ 2 then
          lives = lives - 1
          spawnShip()
          break
        end
      end
    end
    if #rocks == 0 then newWave(4 + score // 500) end
    if lives <= 0 then
      draw()
      ui.center(60, "game over  ctrl-q quits", 0xff6060, 1)
      gfx.flush()
      while true do
        if key.poll() == "ctrl-q" then return end
        sys.sleep(40)
      end
    end
    draw()
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("asteroids: " .. tostring(problem)) end
