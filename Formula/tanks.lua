#!lua
-- tanks: an artillery duel over ground you can dig. Pick a game: against the bot (easy, normal or hard) or two players on one
-- keyboard. On your turn you may drive a little (the tank climbs gentle slopes, and driving costs fuel), set the angle and the
-- power, and fire. The dotted line shows where the shell will fly. Wind pushes the shells and the clouds. A hit digs a crater
-- and damages the tanks near it; the first tank with no health left loses.
-- Player 1 (left): a d drive, w s angle, e q power, f or space fires.
-- Player 2 (right): j l drive, i k angle, o u power, h fires.
-- Where the firmware reports held keys (key.down, v0.1.0.18 or newer) the drive, angle and power keys work while held;
-- otherwise each press is one step. n starts a new battle, m goes back to the menu, ctrl-q quits.
-- Needs the graphics and the ui package. Run it with --selftest to check the shells, the damage and the bot.

local W, H = 240, 135
local ui                  -- the ui package, loaded below (the drawing functions use it)
local GRAVITY = 70        -- pixels a second squared
local WIND_K = 3          -- wind accelerates the shell by this many times the wind number
local DT = 1 / 30         -- the physics step; the preview and the real shot use the same one
local SPEED_K = 1.7       -- shell speed in pixels a second, per point of power
local BARREL = 12         -- length of the barrel in pixels
local DRIVE_SPEED = 26    -- pixels a second while a drive key is held
local FUEL_PER_PX = 0.35
local BLAST = 13          -- the radius of a crater in pixels
local TRAIL = 14          -- the shell's trail is this many points long
local SLOPE_MAX = 3       -- a tank does not drive up or down more than this many rows from one column to the next

local CONTROLS = {
  [1] = { left = "a", right = "d", up = "w", down = "s", powerUp = "e", powerDown = "q", fire = { "f", " " } },
  [2] = { left = "j", right = "l", up = "i", down = "k", powerUp = "o", powerDown = "u", fire = { "h" } },
}
local SKILL = {
  [1] = { angle = 7, power = 7 },   -- easy: the bot misses by a lot
  [2] = { angle = 3, power = 3 },   -- normal
  [3] = { angle = 1, power = 1 },   -- hard
}
local MENU = {
  { "vs bot: easy", "bot", 1 },
  { "vs bot: normal", "bot", 2 },
  { "vs bot: hard", "bot", 3 },
  { "two players, one keyboard", "hot", 0 },
  { "quit" },
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function round(v)
  return math.floor(v + 0.5)
end

-- ---- the ground ----

-- the screen row of the surface at each column; the tanks start on flat ground at x = 34 and x = 206
local function newGround(seed)
  local p1, p2, p3 = seed * 1.3, seed * 2.1, seed * 0.7
  local ground = {}
  for x = 0, W - 1 do
    ground[x] = math.floor(92 - 14 * math.sin(x * 0.021 + p1) - 7 * math.sin(x * 0.053 + p2) - 3 * math.sin(x * 0.17 + p3))
  end
  for _, cx in ipairs({ 34, 206 }) do
    local base = ground[cx]
    for x = cx - 9, cx + 9 do
      if x >= 0 and x < W then ground[x] = base end
    end
  end
  return ground
end

-- digs a crater at (cx, cy): the surface under the blast drops
local function dig(ground, cx, cy)
  for dx = -BLAST, BLAST do
    local x = cx + dx
    if x >= 0 and x < W then
      local depth = math.floor(math.sqrt(BLAST * BLAST - dx * dx) * 0.7 + 0.5)
      if ground[x] < cy + depth then ground[x] = cy + depth end
    end
  end
end

-- ---- the tanks ----

-- a point of a tank in its own coordinates (x to the right, y down from the middle of its tracks) in screen coordinates
local function toWorld(tk, lx, ly)
  local ca, sa = math.cos(tk.tilt), math.sin(tk.tilt)
  return tk.x + lx * ca - ly * sa, tk.y + lx * sa + ly * ca
end

-- the middle of the turret
local function turretOf(tk)
  return toWorld(tk, 0, -10)
end

-- sets a tank on the ground: on the surface, tilted to the slope under it
local function place(tk, ground)
  local x = clamp(round(tk.x), 6, W - 7)
  tk.x = x
  local a = ground[clamp(x - 4, 0, W - 1)]
  local b = ground[clamp(x + 4, 0, W - 1)]
  tk.tilt = math.atan((b - a) / 8)
  tk.y = ground[x] - 3
end

-- drives a tank px pixels (negative to the left): a wall or a steep slope stops it, and the fuel runs out
local function driveTank(tk, ground, px)
  local dir = px > 0 and 1 or -1
  local left = math.abs(px)
  while left > 0 do
    local step = math.min(1, left)
    local nx = tk.x + dir * step
    if nx < 6 or nx > W - 7 then break end
    local here = ground[clamp(round(tk.x), 0, W - 1)]
    local there = ground[clamp(round(nx), 0, W - 1)]
    if math.abs(there - here) > SLOPE_MAX then break end
    local cost = step * FUEL_PER_PX
    if tk.fuel < cost then
      tk.fuel = 0
      break
    end
    tk.x = nx
    tk.fuel = tk.fuel - cost
    tk.phase = (tk.phase + step) % 20
    left = left - step
  end
  place(tk, ground)
end

-- ---- the shells ----

-- a new shell from the end of the barrel of a tank
local function newShell(tk, owner)
  local tx, ty = turretOf(tk)
  local a = math.rad(tk.angle)
  local sp = tk.power * SPEED_K
  return {
    x = tx + math.cos(a) * BARREL, y = ty - math.sin(a) * BARREL,
    vx = math.cos(a) * sp, vy = -math.sin(a) * sp, t = 0, owner = owner,
  }
end

-- one physics step of a shell: the wind pushes it sideways, gravity pulls it down
local function shellStep(s, wind)
  s.vx = s.vx + wind * WIND_K * DT
  s.vy = s.vy + GRAVITY * DT
  s.x = s.x + s.vx * DT
  s.y = s.y + s.vy * DT
  s.t = s.t + DT
end

-- what the shell has reached: "out" (off the screen sideways), "tank" (a tank other than the one that fired; the second
-- result is its index), "ground", or nil while it flies
local function impactOf(s, ground, tanks, owner)
  if s.x < -2 or s.x > W + 1 then return "out" end
  if s.t > 0.1 then
    for i, tk in ipairs(tanks) do
      if i ~= owner and math.abs(s.x - tk.x) < 7 and s.y > tk.y - 10 and s.y < tk.y + 4 then return "tank", i end
    end
  end
  if s.y >= ground[clamp(round(s.x), 0, W - 1)] then return "ground" end
  return nil
end

-- the whole flight of a shell, without drawing: where it lands, and (when keepPath) the points of the flight. keepPath may be
-- a list to fill again (x1, y1, x2, y2, ... flat): the preview runs every frame, and a new table for every point of every
-- frame was more garbage than the memory of the Cardputer could take.
local function simulate(ground, tanks, owner, wind, s, keepPath)
  local path = keepPath and (type(keepPath) == "table" and keepPath or {}) or nil
  local n = 0
  if path then for i = #path, 1, -1 do path[i] = nil end end
  for step = 1, 500 do
    shellStep(s, wind)
    if path and step % 2 == 0 then
      path[n + 1], path[n + 2] = s.x, s.y
      n = n + 2
    end
    local hit, who = impactOf(s, ground, tanks, owner)
    if hit then return { kind = hit, target = who, x = clamp(s.x, 0, W - 1), y = s.y, path = path } end
  end
  return { kind = "out", x = clamp(s.x, 0, W - 1), y = s.y, path = path }
end

-- the damage of a blast at distance d from a tank: 60 at the centre, none beyond BLAST + 10 pixels
local function damageAt(d)
  local v = 1 - d / (BLAST + 10)
  if v <= 0 then return 0 end
  return math.floor(v * 60 + 0.5)
end

-- the angle and the power the bot should use to land a shell on target (tank index `me` fires at tanks[target]); the
-- errors are the largest random mistakes added to the angle and the power
local function bestShot(ground, tanks, me, target, wind, errA, errP)
  local best = { err = math.huge, angle = 45, power = 50 }
  local function try(a, p)
    if a < 4 or a > 176 or p < 5 or p > 100 then return end
    local tk = { x = tanks[me].x, y = tanks[me].y, tilt = tanks[me].tilt, angle = a, power = p }
    local r = simulate(ground, tanks, me, wind, newShell(tk, me), false)
    local err = math.abs(r.x - tanks[target].x)
    if r.kind == "tank" and r.target == target then err = 0 end
    if err < best.err then best = { err = err, angle = a, power = p } end
  end
  for a = 8, 172, 12 do
    for p = 20, 100, 10 do try(a, p) end
  end
  local a0, p0 = best.angle, best.power
  for a = a0 - 12, a0 + 12, 2 do
    for p = p0 - 10, p0 + 10, 2 do try(a, p) end
  end
  local angle = clamp(best.angle + (math.random() * 2 - 1) * errA, 4, 176)
  local power = clamp(best.power + (math.random() * 2 - 1) * errP, 5, 100)
  return angle, power
end

-- ---- a battle ----

-- how far the bot drives before it aims: it keeps about 140 pixels from the player
local function botDriveAmount(g)
  local bot, human = g.tanks[2], g.tanks[1]
  local d = human.x - bot.x
  local gap = math.abs(d) - 140
  local move = clamp(gap, -40, 60)
  return (d > 0 and 1 or -1) * move
end

local function newBattle(mode, skill)
  local seed = math.random(1, 500)
  local ground = newGround(seed)
  local tanks = {
    { index = 1, name = "P1", colour = 0x40c0ff, x = 34, angle = 45, power = 55, hp = 100, fuel = 100, phase = 0 },
    { index = 2, name = mode == "bot" and "BOT" or "P2", colour = 0xff8040, x = 206, angle = 135, power = 55,
      hp = 100, fuel = 100, phase = 0 },
  }
  for _, tk in ipairs(tanks) do place(tk, ground) end
  local g = {
    mode = mode, skill = skill, ground = ground, tanks = tanks, turn = 1, phase = "aim",
    wind = math.random(-14, 14), shell = nil, trail = {}, parts = {}, acc = 0,
    msg = mode == "bot" and "your turn: drive, aim, fire" or "player 1 aims",
    winner = nil, boomT = 0, flashT = 0, clouds = { 20, 110, 180 }, botStep = nil, botT = 0, botDrive = 0, botPlan = nil,
  }
  return g
end

local function nextTurn(g)
  g.turn = 3 - g.turn
  g.shell = nil
  g.trail = {}
  if g.mode == "bot" and g.turn == 2 then
    g.phase = "bot"
    g.botStep = "drive"
    g.botT = 0
    g.botDrive = botDriveAmount(g)
    g.msg = "bot is moving"
  else
    g.phase = "aim"
    g.msg = g.mode == "bot" and "your turn: drive, aim, fire" or ("player " .. g.turn .. " aims")
  end
end

-- a little smoke left behind the shell
local function smokePuff(g, x, y)
  g.parts[#g.parts + 1] = { x = x, y = y, vx = (math.random() - 0.5) * 6, vy = -8 - math.random() * 6,
    life = 0.7, max = 0.7, smoke = true, r = 1 }
end

-- a shot leaves the barrel: the muzzle flash and the shell in the air
local function fire(g, tk, owner)
  g.shell = newShell(tk, owner)
  g.trail = {}
  g.acc = 0
  g.phase = "flight"
  g.flashT = 0.12
  g.msg = ""
end

local function addParticles(g, x, y)
  local colours = { 0xffe060, 0xff8030, 0xff3020, 0xfff0a0 }
  for _ = 1, 22 do
    local a = math.random() * math.pi * 2
    local sp = 40 + math.random() * 110
    local life = 0.5 + math.random() * 0.5
    g.parts[#g.parts + 1] = { x = x, y = y, vx = math.cos(a) * sp, vy = math.sin(a) * sp, life = life, max = life,
      colour = colours[math.random(#colours)] }
  end
  for _ = 1, 6 do
    local life = 1.2 + math.random()
    g.parts[#g.parts + 1] = { x = x + (math.random() - 0.5) * 10, y = y, vx = (math.random() - 0.5) * 10,
      vy = -15 - math.random() * 10, life = life, max = life, smoke = true, r = 3 }
  end
end

-- a shell has landed or left the screen: the crater, the damage and the message
local function resolve(g, kind, who)
  local s = g.shell
  local x, y = clamp(s.x, 0, W - 1), s.y
  if kind == "out" then
    g.msg = "missed: off the screen"
  else
    dig(g.ground, round(x), round(y))
    addParticles(g, x, y)
    g.boomT = 0.8
    g.boomX, g.boomY = x, y
    local hits = 0
    for i, tk in ipairs(g.tanks) do
      local d = math.sqrt((tk.x - x) ^ 2 + (tk.y - 4 - y) ^ 2)
      local dmg = damageAt(d)
      if kind == "tank" and i == who then dmg = math.max(dmg, 40) end
      if dmg > 0 then
        tk.hp = math.max(0, tk.hp - dmg)
        hits = hits + dmg
      end
    end
    if kind == "tank" then
      g.msg = "direct hit! " .. hits .. " damage"
    elseif hits > 0 then
      g.msg = "boom! " .. hits .. " damage"
    else
      g.msg = "splash, no damage"
    end
  end
  for _, tk in ipairs(g.tanks) do place(tk, g.ground) end
  g.phase = "boom"
  g.shell = nil
end

-- what happens after the explosion: the winner, or the other side's turn
local function endTurn(g)
  for i, tk in ipairs(g.tanks) do
    if tk.hp <= 0 then
      g.winner = 3 - i
      g.phase = "over"
      g.msg = g.tanks[3 - i].name .. " wins!"
      return
    end
  end
  nextTurn(g)
end

-- the bot: drives, then waits a moment, works out the shot, turns its barrel to it and fires
local function updateBot(g, dt)
  local tk = g.tanks[2]
  g.botT = g.botT + dt
  if g.botStep == "drive" then
    if math.abs(g.botDrive) < 0.05 or tk.fuel <= 0 then
      g.botStep = "think"
      g.botT = 0
    else
      local move = math.min(math.abs(g.botDrive), DRIVE_SPEED * dt)
      if g.botDrive < 0 then move = -move end
      driveTank(tk, g.ground, move)
      g.botDrive = g.botDrive - move
    end
  elseif g.botStep == "think" then
    if g.botT > 0.4 then
      local errA, errP = SKILL[g.skill].angle, SKILL[g.skill].power
      local a, p = bestShot(g.ground, g.tanks, 2, 1, g.wind, errA, errP)
      g.botPlan = { angle = a, power = p }
      g.botFrom = { angle = tk.angle, power = tk.power }
      g.botStep = "aim"
      g.botT = 0
      g.msg = "bot aims"
    end
  elseif g.botStep == "aim" then
    local t = clamp(g.botT / 0.7, 0, 1)
    tk.angle = g.botFrom.angle + (g.botPlan.angle - g.botFrom.angle) * t
    tk.power = g.botFrom.power + (g.botPlan.power - g.botFrom.power) * t
    if t >= 1 then
      fire(g, tk, 2)
      g.msg = "bot fires"
    end
  end
end

-- the flight of the shell, in fixed physics steps
local function updateFlight(g, dt)
  g.acc = g.acc + dt
  while g.acc >= DT do
    g.acc = g.acc - DT
    shellStep(g.shell, g.wind)
    g.trail[#g.trail + 1] = { x = g.shell.x, y = g.shell.y }
    if #g.trail > TRAIL then table.remove(g.trail, 1) end
    if #g.trail % 3 == 0 then smokePuff(g, g.shell.x, g.shell.y) end
    local hit, who = impactOf(g.shell, g.ground, g.tanks, g.turn)
    if hit then
      resolve(g, hit, who)
      return
    end
  end
end

local function updateParticles(g, dt)
  g.flashT = math.max(0, g.flashT - dt)
  for i = #g.parts, 1, -1 do
    local p = g.parts[i]
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    if not p.smoke then p.vy = p.vy + 120 * dt end
    p.life = p.life - dt
    if p.life <= 0 then table.remove(g.parts, i) end
  end
end

local function update(g, dt)
  for i = 1, #g.clouds do g.clouds[i] = (g.clouds[i] + (g.wind * 0.6 + 2) * dt) % (W + 40) end
  updateParticles(g, dt)
  if g.boomT > 0 then g.boomT = math.max(0, g.boomT - dt) end
  if g.phase == "bot" then
    updateBot(g, dt)
  elseif g.phase == "flight" then
    updateFlight(g, dt)
  elseif g.phase == "boom" and g.boomT <= 0 then
    endTurn(g)
  end
end

-- the held keys move the tank of the player whose turn it is (the firmware that reports them)
local function heldControls(g, dt, held)
  if g.phase ~= "aim" or not held then return end
  local tk = g.tanks[g.turn]
  local c = CONTROLS[g.turn]
  local down = {}
  for _, k in ipairs(held) do down[k] = true end
  if down[c.left] then driveTank(tk, g.ground, -DRIVE_SPEED * dt) end
  if down[c.right] then driveTank(tk, g.ground, DRIVE_SPEED * dt) end
  if down[c.up] then tk.angle = clamp(tk.angle + 40 * dt, 4, 176) end
  if down[c.down] then tk.angle = clamp(tk.angle - 40 * dt, 4, 176) end
  if down[c.powerUp] then tk.power = clamp(tk.power + 40 * dt, 5, 100) end
  if down[c.powerDown] then tk.power = clamp(tk.power - 40 * dt, 5, 100) end
end

-- one key press: a step of the drive, the angle or the power (without held keys), or the shot
local function pressControl(g, k, usesHeld)
  if g.phase ~= "aim" then return end
  local tk = g.tanks[g.turn]
  local c = CONTROLS[g.turn]
  for _, f in ipairs(c.fire) do
    if k == f then
      fire(g, tk, g.turn)
      return
    end
  end
  if usesHeld then return end
  if k == c.left then driveTank(tk, g.ground, -6)
  elseif k == c.right then driveTank(tk, g.ground, 6)
  elseif k == c.up then tk.angle = clamp(tk.angle + 3, 4, 176)
  elseif k == c.down then tk.angle = clamp(tk.angle - 3, 4, 176)
  elseif k == c.powerUp then tk.power = clamp(tk.power + 3, 5, 100)
  elseif k == c.powerDown then tk.power = clamp(tk.power - 3, 5, 100)
  end
end

-- ---- drawing ----

-- the points of a polygon in screen coordinates, from a list of tank coordinates
local polyBuf = {}  -- one list reused by every polygon: a new table for each of ~6 polygons per tank per frame was the garbage
local function tankPoly(tk, list)
  local out = polyBuf
  local n = #list
  for i = 1, n, 2 do
    out[i], out[i + 1] = toWorld(tk, list[i], list[i + 1])
  end
  for i = #out, n + 1, -1 do out[i] = nil end
  return out
end

-- fills a convex polygon given as a flat list of points (x1, y1, x2, y2, ...)
local function poly(p, colour)
  local n = #p // 2
  for i = 2, n - 1 do
    gfx.triangle(round(p[1]), round(p[2]), round(p[2 * i - 1]), round(p[2 * i]), round(p[2 * i + 1]), round(p[2 * i + 2]), colour)
  end
end

local skyColours  -- the colour of every row of the sky, worked out once (not 135 colours every frame)
local function drawSky()
  if not skyColours then
    skyColours = {}
    for y = 0, H - 1 do skyColours[y] = ui.mix(0x1a2f66, 0xf4a060, math.min(1, y / 75)) end
  end
  for y = 0, H - 1 do gfx.hline(0, W - 1, y, skyColours[y]) end
end

local function drawClouds(g)
  for _, cx in ipairs(g.clouds) do
    local x = cx - 20
    local y = 22 + (cx % 17)
    gfx.disc(round(x + 8), round(y), 6, 0xfff4f8)
    gfx.disc(round(x + 16), round(y - 3), 8, 0xfff4f8)
    gfx.disc(round(x + 26), round(y), 6, 0xfff4f8)
    gfx.fill(round(x + 2), round(y), 30, 6, 0xfff4f8)
  end
end

local function drawMountains()
  for x = 0, W - 1, 2 do
    local top = 58 - 16 * math.abs(math.sin(x * 0.045 + 0.8)) - 6 * math.abs(math.sin(x * 0.13))
    gfx.fill(x, round(top), 2, H - round(top), 0x3b3a6e)
    gfx.fill(x, round(top), 2, 2, 0x6a68a0)
  end
end

local function drawGround(g)
  for x = 0, W - 1 do
    local top = g.ground[x]
    gfx.fill(x, top, 1, 2, 0x5cc04a)
    gfx.fill(x, top + 2, 1, 3, 0x3f9a34)
    gfx.fill(x, top + 5, 1, H - top - 5, 0x7a5030)
    if (x * 7 + top) % 9 == 0 and top + 9 < H then gfx.fill(x, top + 9, 2, 2, 0x5a3820) end
    if top + 22 < H then gfx.fill(x, top + 22, 1, H - top - 22, 0x5c3a22) end
  end
end

-- the dotted line of the flight the shell will take, and a cross where it lands
local function drawPreview(g)
  local tk = g.tanks[g.turn]
  g.previewPath = g.previewPath or {}
  local r = simulate(g.ground, g.tanks, g.turn, g.wind, newShell(tk, g.turn), g.previewPath)
  local path = r.path
  for i = 1, #path - 1, 2 do
    gfx.pixel(round(path[i]), round(path[i + 1]), 0xe8f0ff)
    if path[i + 2] then gfx.pixel(round((path[i] + path[i + 2]) / 2), round((path[i + 1] + path[i + 3]) / 2), 0xe8f0ff) end
  end
  local lx, ly = round(r.x), round(r.y)
  gfx.line(lx - 3, ly - 3, lx + 3, ly + 3, 0xff5050)
  gfx.line(lx - 3, ly + 3, lx + 3, ly - 3, 0xff5050)
end

local function drawTrail(g)
  local n = #g.trail
  for i, p in ipairs(g.trail) do
    gfx.disc(round(p.x), round(p.y), 1, ui.mix(0x6a7aa0, 0xffffff, i / math.max(1, n)))
  end
  if g.shell then
    gfx.disc(round(g.shell.x), round(g.shell.y), 2, 0xffe060)
  end
end

-- a tank: a shaded hull with a chamfered front, tracks with turning wheels, a turret and a barrel that points where it aims
local function drawTank(tk, active, flashing)
  tk.flash = flashing and 1 or 0
  local main = tk.colour
  local dark = ui.shade(main, 0.55)
  local light = ui.shade(main, 1.3)
  gfx.fill(round(tk.x) - 13, round(tk.y) + 4, 26, 2, 0x0a0c12)
  poly(tankPoly(tk, { -13, -1, 13, -1, 13, 2, 11, 4, -11, 4, -13, 2 }), 0x262626)
  for i = 0, 4 do
    local wx, wy = toWorld(tk, -10 + ((i * 5 + tk.phase) % 20), 2)
    gfx.disc(round(wx), round(wy), 2, 0x6e6e6e)
  end
  poly(tankPoly(tk, { -12, -2, -11, -8, -7, -10, 9, -10, 12, -7, 12, -2 }), main)
  poly(tankPoly(tk, { -11, -8, -7, -10, 9, -10, 11, -8 }), light)
  poly(tankPoly(tk, { -12, -2, 12, -2, 12, -4, -12, -4 }), dark)
  local tx, ty = turretOf(tk)
  gfx.disc(round(tx), round(ty), 5, main)
  gfx.disc(round(tx) - 1, round(ty) - 2, 2, light)
  gfx.circle(round(tx), round(ty), 5, dark, false)
  local ax, ay = toWorld(tk, 3, -9)
  local bx2, by2 = toWorld(tk, 8, -17)
  gfx.line(round(ax), round(ay), round(bx2), round(by2), 0x202020)
  local a = math.rad(tk.angle)
  local bx, by = tx + math.cos(a) * BARREL, ty - math.sin(a) * BARREL
  local px, py = -math.sin(a) * 1.6, -math.cos(a) * 1.6
  poly({ tx + px, ty + py, tx - px, ty - py, bx - px, by - py, bx + px, by + py }, dark)
  gfx.disc(round(bx), round(by), 2, 0x202020)
  if tk.flash and tk.flash > 0 then
    gfx.disc(round(bx), round(by), 4, 0xffffff)
    gfx.disc(round(bx) + round(math.cos(a) * 2), round(by) - round(math.sin(a) * 2), 3, 0xffe060)
  end
  local x0, y0 = round(tx) - 12, round(ty) - 17
  gfx.fill(x0, y0, 24, 3, 0x2a0a0a)
  local colr = tk.hp > 60 and 0x40d060 or (tk.hp > 30 and 0xf0c040 or 0xe04040)
  gfx.fill(x0, y0, round(24 * tk.hp / 100), 3, colr)
  ui.label(round(tx) - 6, y0 - 9, tk.name, main)
  if active then gfx.triangle(round(tx) - 3, y0 - 17, round(tx) + 3, y0 - 17, round(tx), y0 - 12, 0xffe060) end
end

local function drawParticles(g)
  for _, p in ipairs(g.parts) do
    local f = p.life / p.max
    if p.smoke then
      gfx.disc(round(p.x), round(p.y), round(p.r * (2 - f)), ui.mix(0x2a2a34, 0x7f8aa8, 1 - f))
    else
      gfx.fill(round(p.x), round(p.y), 2, 2, p.colour)
    end
  end
  if g.boomT > 0 then
    local r = round((1 - g.boomT / 0.8) * (BLAST + 6))
    gfx.circle(round(g.boomX), round(g.boomY), r + 1, 0xffd060, false)
  end
end

local function drawHud(g)
  gfx.fill(0, 0, W, 12, 0x0b0e1a)
  local p1, p2 = g.tanks[1], g.tanks[2]
  ui.label(3, 2, p1.name .. " " .. p1.hp, p1.colour)
  local right = p2.name .. " " .. p2.hp
  ui.label(W - 3 - 6 * #right, 2, right, p2.colour)
  local cx = W // 2
  ui.label(cx - 22, 2, "wind", 0x9aa6c0)
  local len = g.wind * 1.1
  gfx.line(cx + 6, 6, round(cx + 6 + len), 6, 0xffe060)
  if g.wind ~= 0 then
    local tipX = round(cx + 6 + len)
    local d = len > 0 and -2 or 2
    gfx.line(tipX, 6, tipX + d, 4, 0xffe060)
    gfx.line(tipX, 6, tipX + d, 8, 0xffe060)
  end
  gfx.fill(0, H - 12, W, 12, 0x0b0e1a)
  local tk = g.tanks[g.turn]
  ui.label(3, H - 10, string.format("angle %d  power %d  fuel %d", round(tk.angle), round(tk.power), round(tk.fuel)), 0xe8ecf4)
  gfx.fill(W - 66, H - 9, 60, 6, 0x2a2a3a)
  local pc = tk.power > 75 and 0xe04040 or (tk.power > 45 and 0xf0c040 or 0x40d060)
  gfx.fill(W - 66, H - 9, round(60 * tk.power / 100), 6, pc)
  if g.msg ~= "" then ui.center(15, g.msg, 0xffffff, 1) end
  if g.phase == "over" then
    gfx.fill(30, 52, W - 60, 30, 0x0b0e1a)
    ui.center(56, g.msg, 0xffe060, 2)
    ui.center(72, "n new battle   m menu", 0xe8ecf4, 1)
  end
end

local function draw(g)
  gfx.clear(0x000000)
  drawSky()
  drawClouds(g)
  drawMountains()
  drawGround(g)
  if g.phase == "aim" then drawPreview(g) end
  drawTrail(g)
  for i, tk in ipairs(g.tanks) do
    drawTank(tk, i == g.turn and g.phase ~= "over", g.flashT > 0 and i == g.turn)
  end
  drawParticles(g)
  drawHud(g)
  gfx.flush()
end

-- ---- self test ----

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local flat = {}
  for x = 0, W - 1 do flat[x] = 94 end
  local function shotAt(angle, power, x, owner)
    local tk = { x = x, y = 91, tilt = 0, angle = angle, power = power }
    return simulate(flat, {}, owner or 1, 0, newShell(tk, owner or 1), false)
  end
  local near, far = shotAt(45, 30, 20), shotAt(45, 45, 20)
  check(near.kind == "ground" and far.kind == "ground" and far.x > near.x and near.x > 20, "a stronger shot lands further")
  local up = shotAt(90, 40, 100)
  check(up.kind == "ground" and math.abs(up.x - 100) < 1.5, "straight up lands where it was fired")
  check(shotAt(45, 90, 20).kind == "out", "a very strong shot flies off the screen")
  local wind = { x = 20, y = 91, tilt = 0, angle = 45, power = 40 }
  local calm = simulate(flat, {}, 1, 0, newShell(wind, 1), false)
  local blown = simulate(flat, {}, 1, 30, newShell(wind, 1), false)
  check(blown.x > calm.x, "a wind from the left pushes the shell right")
  local tk = { x = 20, y = 91, tilt = 0, angle = 45, power = 40 }
  local r = simulate(flat, {}, 1, 0, newShell(tk, 1), true)
  check(r.path and #r.path > 10 and #r.path % 2 == 0, "the preview has points of the flight, x and y")
  check(damageAt(0) == 60 and damageAt(BLAST + 10) == 0 and damageAt(20) > 0 and damageAt(20) < 60, "the damage falls with the distance")
  local g = {}
  for x = 0, W - 1 do g[x] = 94 end
  dig(g, 120, 94)
  check(g[120] > 94 and g[120 + BLAST + 2] == 94, "a crater drops the ground near the hit only")
  local made = newGround(7)
  check(made[34] == made[25] and made[206] == made[215], "the tanks start on flat ground")
  -- a wall stops a tank; the fuel runs out
  local wall = {}
  for x = 0, W - 1 do wall[x] = 94 end
  for x = 60, W - 1 do wall[x] = 60 end
  local walker = { x = 50, y = 91, tilt = 0, angle = 45, power = 50, fuel = 100, phase = 0 }
  driveTank(walker, wall, 30)
  check(walker.x < 60 and walker.x > 50, "a wall stops the tank")
  local thirsty = { x = 50, y = 91, tilt = 0, angle = 45, power = 50, fuel = 0, phase = 0 }
  driveTank(thirsty, flat, 30)
  check(thirsty.x == 50, "no fuel, no driving")
  local driver = { x = 50, y = 91, tilt = 0, angle = 45, power = 50, fuel = 100, phase = 0 }
  driveTank(driver, flat, 10)
  check(driver.x == 60 and driver.fuel < 100, "driving moves the tank and costs fuel")
  -- the bot finds a shot that lands on the player on flat ground (no mistakes)
  local tanks = {
    { index = 1, x = 34, y = 91, tilt = 0, angle = 45, power = 55, hp = 100, fuel = 100, phase = 0 },
    { index = 2, x = 206, y = 91, tilt = 0, angle = 135, power = 55, hp = 100, fuel = 100, phase = 0 },
  }
  local a, p = bestShot(flat, tanks, 2, 1, 0, 0, 0)
  local shot = { x = 206, y = 91, tilt = 0, angle = a, power = p }
  local landed = simulate(flat, tanks, 2, 0, newShell(shot, 2), false)
  check((landed.kind == "tank" and landed.target == 1) or math.abs(landed.x - 34) < 4, "the bot lands a shell on the player")
  check(a > 90, "the bot shoots to the left, at the player")
  -- the bot drives towards the player when it is far away
  local far2 = newBattle("bot", 2)
  far2.tanks[2].x = 206
  check(botDriveAmount(far2) < 0, "a far bot drives towards the player")
  check(SKILL[1].angle > SKILL[3].angle, "easy is less exact than hard")
  check(CONTROLS[1].left == "a" and CONTROLS[2].left == "j" and CONTROLS[1].fire[1] == "f", "the keys of both players")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("tanks needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local uiErr
ui, uiErr = driver.load("ui", true)
if not ui then
  print("tanks: " .. tostring(uiErr))
  return
end

local function menu()
  local items = {}
  for i, m in ipairs(MENU) do items[i] = m[1] end
  local c = ui.choose("TANKS", items)
  if not c or not MENU[c][2] then return nil end
  return MENU[c][2], MENU[c][3]
end

-- one battle until the player goes back to the menu (returns "menu") or quits (returns "quit")
local function battle(mode, skill)
  local frameNo = 0
  local g = newBattle(mode, skill)
  local last = sys.millis()
  while true do
    local now = sys.millis()
    local dt = math.min((now - last) / 1000, 0.1)
    last = now
    local held = key.down and key.down() or nil
    local usesHeld = key.down ~= nil
    local restart = false
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return "quit" end
      if k == "m" then return "menu" end
      if k == "n" then restart = true
      else pressControl(g, k, usesHeld) end
      k = key.poll()
    end
    if restart then g = newBattle(mode, skill) end
    heldControls(g, dt, held)
    update(g, dt)
    draw(g)
    frameNo = frameNo + 1
    if frameNo % 12 == 0 then collectgarbage("step", 40) end  -- keep the garbage small: the canvas leaves little memory
    sys.sleep(25)
  end
end

local w, h = ui.open()
if not w then
  print("tanks: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    local mode, skill = menu()
    if not mode then return end
    if battle(mode, skill) == "quit" then return end
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("tanks: " .. tostring(problem)) end
