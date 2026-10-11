#!lua
-- doom 0.1.0: a Doom-like shooter with pixel graphics. Walk a level, shoot the imps and demons, pick up health and
-- ammo, and clear the level. Needs the graphics of firmware v0.1.0.13(beta) and the ui package (brew install ui).
-- Every key is a letter, so no Fn is needed, and nothing has to be held down:
--   w  walk, again for a run            s  slow down, then walk back
--   a  turn left, again for faster      d  turn right, again for faster
--   q  step left                        e  step right (the other key stops a step)
--   z  quick turn left                  c  quick turn right (for aiming)
--   f or enter  fire                    space  stop everything
--   m  the map     p  pause     ctrl-q  quit
-- A key sets how fast you go and the motion goes on by itself: tap w once and you keep walking, tap it again and you run,
-- tap s to slow down. Run it as a script with --selftest to check the game rules; doom --start skips the title.

local SW, SH = 240, 135            -- the screen
local HUD_H = 17                   -- the bar at the bottom
local VIEW_H = SH - HUD_H          -- the picture is the rest
local COLW = 2                     -- a ray is 2 pixels wide
local RAYS = SW // COLW
local FOV = 0.66                   -- the camera plane: about 66 degrees
local HALF = VIEW_H / 2
local RADIUS = 0.28                -- the player and the monsters do not touch a wall

-- the level: 1 2 3 4 are walls of four kinds, . is floor, P the start, E an imp, D a demon, H health, A ammo
local MAP_TEXT = {
  "111111111111111111111111",
  "1.......2.......3......1",
  "1.P.....2.....A.3......1",
  "1.......2..E....3...E..1",
  "1...............3......1",
  "1..........33...3...33.1",
  "1....3..2..33...3......1",
  "1....3..2..............1",
  "1...H...2111..11.......1",
  "1.....E.2.......3.D....1",
  "1............E..3....H.1",
  "122..2222.......3..E...1",
  "1.......2..D.A.........1",
  "1.......2.....E.3444..41",
  "1..D....2.......3......1",
  "1........4..44443....D.1",
  "1...............3......1",
  "1....E..2.......3..33A.1",
  "1.......2..............1",
  "1..33...2...33.........1",
  "1.H...A.2.......3......1",
  "1.......2...E.H.3...E..1",
  "1.......2.......3......1",
  "111111111111111111111111",
}
local MW, MH = 24, 24

local WALL = { [1] = 0xa84632, [2] = 0x8a8f9c, [3] = 0x3a6ea8, [4] = 0x4a8a56 }

local TYPES = {
  imp = { name = "imp", hp = 3, speed = 1.2, ranged = true, size = 0.85 },
  demon = { name = "demon", hp = 5, speed = 2.1, ranged = false, size = 0.95 },
}

-- how a thing looks: boxes in a unit square, u from left to right and v from the top to the bottom
local LOOKS = {
  imp = {
    { 0.30, 0.45, 0.78, 1.00, 0x502818 }, { 0.55, 0.70, 0.78, 1.00, 0x502818 },
    { 0.10, 0.22, 0.40, 0.66, 0x8a4a28 }, { 0.78, 0.90, 0.40, 0.66, 0x8a4a28 },
    { 0.22, 0.78, 0.38, 0.80, 0xa85c30 }, { 0.32, 0.68, 0.12, 0.40, 0xc07840 },
    { 0.30, 0.36, 0.04, 0.14, 0xe8e0c8 }, { 0.64, 0.70, 0.04, 0.14, 0xe8e0c8 },
    { 0.38, 0.44, 0.20, 0.26, 0xffe040 }, { 0.56, 0.62, 0.20, 0.26, 0xffe040 },
  },
  demon = {
    { 0.22, 0.42, 0.78, 1.00, 0x802050 }, { 0.58, 0.78, 0.78, 1.00, 0x802050 },
    { 0.06, 0.20, 0.38, 0.70, 0xc04878 }, { 0.80, 0.94, 0.38, 0.70, 0xc04878 },
    { 0.14, 0.86, 0.30, 0.82, 0xd05888 }, { 0.24, 0.76, 0.06, 0.38, 0xe070a0 },
    { 0.34, 0.66, 0.28, 0.34, 0xffffff }, { 0.30, 0.38, 0.14, 0.22, 0xff2020 },
    { 0.62, 0.70, 0.14, 0.22, 0xff2020 },
  },
  dead = { { 0.08, 0.92, 0.84, 1.00, 0x701818 }, { 0.30, 0.70, 0.76, 0.86, 0x902020 } },
  health = {
    { 0.22, 0.78, 0.52, 1.00, 0xf0f0f0 }, { 0.45, 0.55, 0.58, 0.94, 0xd02828 }, { 0.30, 0.70, 0.70, 0.80, 0xd02828 },
  },
  ammo = { { 0.18, 0.82, 0.60, 1.00, 0xc8a030 }, { 0.28, 0.72, 0.70, 0.80, 0x504010 } },
  ball = { { 0.15, 0.85, 0.15, 0.85, 0xff7020 }, { 0.32, 0.68, 0.32, 0.68, 0xffe060 } },
}

-- ---- the level ----

local grid = {}     -- grid[y][x] is 0 for floor and 1 to 4 for a wall (cells counted from 0)
local SPAWN = { enemies = {}, pickups = {}, start = { x = 1.5, y = 1.5 } }
for y = 1, MH do
  grid[y - 1] = {}
  for x = 1, MW do
    local ch = MAP_TEXT[y]:sub(x, x)
    local cx, cy = x - 0.5, y - 0.5
    local wall = tonumber(ch)
    grid[y - 1][x - 1] = wall or 0
    if ch == "P" then SPAWN.start = { x = cx, y = cy }
    elseif ch == "E" then SPAWN.enemies[#SPAWN.enemies + 1] = { kind = "imp", x = cx, y = cy }
    elseif ch == "D" then SPAWN.enemies[#SPAWN.enemies + 1] = { kind = "demon", x = cx, y = cy }
    elseif ch == "H" then SPAWN.pickups[#SPAWN.pickups + 1] = { kind = "health", x = cx, y = cy }
    elseif ch == "A" then SPAWN.pickups[#SPAWN.pickups + 1] = { kind = "ammo", x = cx, y = cy }
    end
  end
end

-- the kind of the wall at the cell, 0 for floor; outside the level is a wall
local function wallAt(cx, cy)
  local row = grid[cy]
  local t = row and row[cx]
  if t == nil then return 9 end
  return t
end

-- true when a circle of radius r around (x, y) reaches into a wall
local function inWall(x, y, r)
  local x0, x1, y0, y1 = math.floor(x - r), math.floor(x + r), math.floor(y - r), math.floor(y + r)
  return wallAt(x0, y0) > 0 or wallAt(x1, y0) > 0 or wallAt(x0, y1) > 0 or wallAt(x1, y1) > 0
end

-- from (x, y) along (rdx, rdy): the distance to the first wall, the side it was hit on (0 or 1), the kind of the wall and
-- where along it (0 to 1): the digital differential analyser of the classic ray caster
local function cast(x, y, rdx, rdy)
  local mapX, mapY = math.floor(x), math.floor(y)
  local ddx = rdx == 0 and 1e30 or math.abs(1 / rdx)
  local ddy = rdy == 0 and 1e30 or math.abs(1 / rdy)
  local stepX, stepY, sdx, sdy
  if rdx < 0 then stepX, sdx = -1, (x - mapX) * ddx else stepX, sdx = 1, (mapX + 1 - x) * ddx end
  if rdy < 0 then stepY, sdy = -1, (y - mapY) * ddy else stepY, sdy = 1, (mapY + 1 - y) * ddy end
  local side, kind = 0, 9
  for _ = 1, 64 do
    if sdx < sdy then
      sdx, mapX, side = sdx + ddx, mapX + stepX, 0
    else
      sdy, mapY, side = sdy + ddy, mapY + stepY, 1
    end
    kind = wallAt(mapX, mapY)
    if kind > 0 then break end
  end
  local dist = side == 0 and (sdx - ddx) or (sdy - ddy)
  local wx = side == 0 and (y + dist * rdy) or (x + dist * rdx)
  return dist, side, kind, wx - math.floor(wx)
end

-- ---- the game ----

local THROTTLE = { [-1] = -1.7, [0] = 0, [1] = 2.5, [2] = 4.2 }          -- cells per second, by speed level
local TURNING = { [-2] = -2.5, [-1] = -1.1, [0] = 0, [1] = 1.1, [2] = 2.5 }  -- radians per second, by turn level
local STEP = 2.3                   -- sideways cells per second
local ACCEL = 14.0                 -- cells per second, every second: the walk speeds up and slows down smoothly
local SNAP = 0.18                  -- a quick turn, about 10 degrees
local FIRE_EVERY = 0.34            -- seconds between shots

local P, enemies, pickups, balls, G

local function approach(v, target, maxStep)
  if v < target then return math.min(v + maxStep, target) end
  return math.max(v - maxStep, target)
end

local function newGame()
  P = { x = SPAWN.start.x, y = SPAWN.start.y, angle = 0.0, hp = 100, ammo = 36, kills = 0,
        level = 0, turn = 0, strafe = 0, vf = 0.0, vs = 0.0, cool = 0.0, flash = 0.0, hurt = 0.0, bob = 0.0, moving = 0.0 }
  enemies, pickups, balls = {}, {}, {}
  for _, s in ipairs(SPAWN.enemies) do
    local t = TYPES[s.kind]
    enemies[#enemies + 1] = { type = t, kind = s.kind, x = s.x, y = s.y, hp = t.hp, cool = 1 + math.random(), alert = false,
                              flash = 0.0, dead = false, deadT = 0.0 }
  end
  for _, s in ipairs(SPAWN.pickups) do pickups[#pickups + 1] = { kind = s.kind, x = s.x, y = s.y, taken = false } end
  G = { won = false, time = 0.0, msg = "", msgT = 0.0, winT = 0.0, map = true, aim = false }
end

local function say(text)
  G.msg, G.msgT = text, 2.0
end

local function aliveEnemyNear(x, y, r, except)
  for _, e in ipairs(enemies) do
    if not e.dead and e ~= except and (e.x - x) ^ 2 + (e.y - y) ^ 2 < r * r then return e end
  end
  return nil
end

-- moves the player by (dx, dy), sliding along a wall when only one direction is blocked
local function movePlayer(dx, dy)
  local nx, ny = P.x + dx, P.y + dy
  if not inWall(nx, P.y, RADIUS) and not aliveEnemyNear(nx, P.y, 0.55) then P.x = nx end
  if not inWall(P.x, ny, RADIUS) and not aliveEnemyNear(P.x, ny, 0.55) then P.y = ny end
end

local function updatePlayer(dt)
  P.vf = approach(P.vf, THROTTLE[P.level], ACCEL * dt)
  P.vs = approach(P.vs, P.strafe * STEP, ACCEL * dt)
  P.angle = P.angle + TURNING[P.turn] * dt
  local dirX, dirY = math.cos(P.angle), math.sin(P.angle)
  local rightX, rightY = -dirY, dirX
  movePlayer((dirX * P.vf + rightX * P.vs) * dt, (dirY * P.vf + rightY * P.vs) * dt)
  local speed = math.sqrt(P.vf * P.vf + P.vs * P.vs)
  P.moving = math.min(1.0, speed / 4.0)
  P.bob = P.bob + dt * (3 + 7 * P.moving)  -- the picture sways while you walk
  P.cool = math.max(0.0, P.cool - dt)
  P.flash = math.max(0.0, P.flash - dt)
  P.hurt = math.max(0.0, P.hurt - dt)
end

local function hurtPlayer(n)
  P.hp = P.hp - n
  P.hurt = 0.4
end

-- the monster in front of the crosshair (if one is closer than the wall), and how far it is
local function aimedAt()
  local dirX, dirY = math.cos(P.angle), math.sin(P.angle)
  local wall = cast(P.x, P.y, dirX, dirY)
  local best, bestT = nil, 1e9
  for _, e in ipairs(enemies) do
    if not e.dead then
      local ex, ey = e.x - P.x, e.y - P.y
      local along = ex * dirX + ey * dirY
      local across = math.abs(ex * dirY - ey * dirX)
      if along > 0.2 and along < wall and across < 0.42 and along < bestT then best, bestT = e, along end
    end
  end
  return best, bestT
end

local function fire()
  if P.cool > 0 then return end
  if P.ammo <= 0 then
    say("click: no ammo")
    P.cool = 0.4
    return
  end
  P.ammo = P.ammo - 1
  P.cool = FIRE_EVERY
  P.flash = 0.09
  local e = aimedAt()
  if e then
    e.hp = e.hp - 1
    e.flash = 0.12
    e.alert = true
    if e.hp <= 0 then
      e.dead = true
      P.kills = P.kills + 1
      say(e.type.name .. " down")
    end
  end
end

-- one monster: it wakes when it sees you, comes at you, and attacks
local function updateEnemy(e, dt)
  if e.dead then
    e.deadT = e.deadT + dt
    return
  end
  e.flash = math.max(0.0, e.flash - dt)
  local dx, dy = P.x - e.x, P.y - e.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 0.01 then return end
  local ux, uy = dx / dist, dy / dist
  local sees = false
  if dist < 14 then sees = (cast(e.x, e.y, ux, uy)) >= dist - 0.2 end
  if sees then e.alert = true end
  if not e.alert then return end
  e.cool = e.cool - dt
  if dist > (e.type.ranged and 3.0 or 0.85) then
    local nx, ny = e.x + ux * e.type.speed * dt, e.y + uy * e.type.speed * dt
    if not inWall(nx, e.y, 0.3) and not aliveEnemyNear(nx, e.y, 0.6, e) and (nx - P.x) ^ 2 + (e.y - P.y) ^ 2 > 0.36 then e.x = nx end
    if not inWall(e.x, ny, 0.3) and not aliveEnemyNear(e.x, ny, 0.6, e) and (e.x - P.x) ^ 2 + (ny - P.y) ^ 2 > 0.36 then e.y = ny end
  end
  if e.type.ranged then
    if sees and dist < 11 and e.cool <= 0 then
      balls[#balls + 1] = { x = e.x, y = e.y, dx = ux, dy = uy, life = 4.0 }
      e.cool = 1.7 + math.random() * 1.2
    end
  elseif dist < 1.05 and e.cool <= 0 then
    hurtPlayer(10)
    e.cool = 0.9
  end
end

local function updateBalls(dt)
  for i = #balls, 1, -1 do
    local b = balls[i]
    b.x, b.y, b.life = b.x + b.dx * 5.0 * dt, b.y + b.dy * 5.0 * dt, b.life - dt
    local gone = b.life <= 0 or wallAt(math.floor(b.x), math.floor(b.y)) > 0
    if not gone and (b.x - P.x) ^ 2 + (b.y - P.y) ^ 2 < 0.2 then
      hurtPlayer(12)
      gone = true
    end
    if gone then table.remove(balls, i) end
  end
end

local function updatePickups()
  for _, p in ipairs(pickups) do
    if not p.taken and (p.x - P.x) ^ 2 + (p.y - P.y) ^ 2 < 0.36 then
      if p.kind == "health" and P.hp < 100 then
        p.taken = true
        P.hp = math.min(100, P.hp + 25)
        say("health +25")
      elseif p.kind == "ammo" and P.ammo < 99 then
        p.taken = true
        P.ammo = math.min(99, P.ammo + 15)
        say("ammo +15")
      end
    end
  end
end

-- the whole game moves on by dt seconds (in small steps, so nothing passes through a wall)
local function step(dt)
  local n = math.max(1, math.ceil(dt / 0.03))
  local h = dt / n
  for _ = 1, n do
    updatePlayer(h)
    for _, e in ipairs(enemies) do updateEnemy(e, h) end
    updateBalls(h)
    updatePickups()
  end
  G.time = G.time + dt
  G.msgT = math.max(0.0, G.msgT - dt)
  local _, t = aimedAt()
  G.aim = t ~= nil
  local alive = 0
  for _, e in ipairs(enemies) do
    if not e.dead then alive = alive + 1 end
  end
  if alive == 0 then
    G.winT = G.winT + dt
    if G.winT > 1.2 then G.won = true end
  end
end

-- a key press; returns "quit" or "pause" when the game has to do that
local function handleKey(k)
  if k == "ctrl-q" then return "quit" end
  if #k == 1 then k = k:lower() end
  if k == "w" then
    P.level = math.min(2, P.level + 1)
  elseif k == "s" then
    P.level = math.max(-1, P.level - 1)
  elseif k == "d" then
    P.turn = math.min(2, P.turn + 1)
  elseif k == "a" then
    P.turn = math.max(-2, P.turn - 1)
  elseif k == "e" then
    P.strafe = math.min(1, P.strafe + 1)
  elseif k == "q" then
    P.strafe = math.max(-1, P.strafe - 1)
  elseif k == "z" then
    P.angle = P.angle - SNAP
  elseif k == "c" then
    P.angle = P.angle + SNAP
  elseif k == " " then
    P.level, P.turn, P.strafe = 0, 0, 0
  elseif k == "f" or k == "enter" then
    fire()
  elseif k == "m" then
    G.map = not G.map
  elseif k == "p" then
    return "pause"
  end
  return nil
end

-- ---- the picture ----

local function shade(c, f)  -- f from 0 to 256: 256 leaves the color as it is
  return ((((c >> 16) & 255) * f >> 8) << 16) | ((((c >> 8) & 255) * f >> 8) << 8) | ((c & 255) * f >> 8)
end

local function fog(dist)  -- how much of a color is left at this distance, 70 to 256
  local f = math.floor(256 / (1 + dist * 0.16))
  return f < 70 and 70 or f
end

local zbuf = {}

local function drawWorld(horizon)
  -- the ceiling and the floor in bands, darker far away
  local bands = 6
  for i = 0, bands - 1 do
    local y0, y1 = math.floor(horizon * i / bands), math.floor(horizon * (i + 1) / bands)
    gfx.fill(0, y0, SW, y1 - y0 + 1, shade(0x2c3452, 90 + i * 28))
  end
  for i = 0, bands - 1 do
    local y0 = horizon + math.floor((VIEW_H - horizon) * i / bands)
    local y1 = horizon + math.floor((VIEW_H - horizon) * (i + 1) / bands)
    gfx.fill(0, y0, SW, y1 - y0 + 1, shade(0x5a4a3a, 80 + i * 26))
  end
  local dirX, dirY = math.cos(P.angle), math.sin(P.angle)
  local planeX, planeY = -dirY * FOV, dirX * FOV
  for i = 0, RAYS - 1 do
    local cam = 2 * i / (RAYS - 1) - 1
    local dist, side, kind, wx = cast(P.x, P.y, dirX + planeX * cam, dirY + planeY * cam)
    if dist < 0.05 then dist = 0.05 end
    zbuf[i + 1] = dist
    local lineH = VIEW_H / dist
    local top = math.floor(horizon - lineH / 2)
    local bottom = math.floor(horizon + lineH / 2)
    local ya, yb = top < 0 and 0 or top, bottom >= VIEW_H and VIEW_H - 1 or bottom
    local f = fog(dist)
    if side == 1 then f = f * 3 // 4 end
    local base = WALL[kind] or 0x808080
    local px = i * COLW
    gfx.fill(px, ya, COLW, yb - ya + 1, shade(base, f))
    if lineH >= 14 then
      local dark = shade(base, f * 2 // 3)
      if kind == 1 then  -- brick: seams across, and now and then one up
        for k = 1, 3 do
          local y = math.floor(top + lineH * k / 4)
          if y >= 0 and y < VIEW_H then gfx.fill(px, y, COLW, 1, dark) end
        end
        if (wx * 5) % 1 < 0.08 then gfx.fill(px, ya, COLW, yb - ya + 1, dark) end
      elseif kind == 2 then  -- stone: panels
        if (wx * 2) % 1 < 0.06 then gfx.fill(px, ya, COLW, yb - ya + 1, dark) end
      elseif kind == 3 then  -- tech: a light strip
        local y = math.floor(top + lineH * 0.42)
        if y >= 0 and y < VIEW_H then gfx.fill(px, y, COLW, math.max(1, lineH // 14), shade(0x80d0ff, f)) end
      else  -- moss: dark patches at the top
        if math.floor(wx * 8) % 3 == 0 then gfx.fill(px, ya, COLW, math.max(1, lineH * 0.3 // 1), dark) end
      end
    end
  end
end

-- everything that stands in the level, far ones first
local function drawThings(horizon)
  local dirX, dirY = math.cos(P.angle), math.sin(P.angle)
  local planeX, planeY = -dirY * FOV, dirX * FOV
  local invDet = 1 / (planeX * dirY - dirX * planeY)
  local list = {}
  local function add(x, y, look, size, lift, flash)
    local sx, sy = x - P.x, y - P.y
    local tx = invDet * (dirY * sx - dirX * sy)
    local ty = invDet * (-planeY * sx + planeX * sy)
    if ty > 0.15 and ty < 16 then list[#list + 1] = { tx = tx, ty = ty, look = look, size = size, lift = lift, flash = flash } end
  end
  for _, p in ipairs(pickups) do
    if not p.taken then add(p.x, p.y, LOOKS[p.kind], 0.4, 0, 0) end
  end
  for _, e in ipairs(enemies) do
    if e.dead then
      if e.deadT < 6 then add(e.x, e.y, LOOKS.dead, 0.9, 0, 0) end
    else
      add(e.x, e.y, LOOKS[e.kind], e.type.size, 0, e.flash)
    end
  end
  for _, b in ipairs(balls) do add(b.x, b.y, LOOKS.ball, 0.32, 0.3, 0) end
  table.sort(list, function(a, b) return a.ty > b.ty end)
  for _, s in ipairs(list) do
    local lineH = VIEW_H / s.ty
    local h = lineH * s.size
    local wRays = h / COLW
    local center = (RAYS - 1) * (1 + s.tx / s.ty) / 2
    local left = math.floor(center - wRays / 2)
    local right = math.floor(center + wRays / 2)
    local floorY = horizon + lineH / 2 - s.lift * lineH
    local topY = floorY - h
    local f = fog(s.ty)
    local stride = wRays > 40 and 2 or 1
    local i = left < 0 and 0 or left
    while i <= right and i < RAYS do
      if s.ty < zbuf[i + 1] then
        local u = (i - left + 0.5) / (right - left + 1)
        for _, part in ipairs(s.look) do
          if u >= part[1] and u < part[2] then
            local ya = math.floor(topY + part[3] * h)
            local yb = math.floor(topY + part[4] * h)
            if ya < 0 then ya = 0 end
            if yb > VIEW_H then yb = VIEW_H end
            if yb > ya then
              local c = shade(part[5], f)
              if s.flash > 0 then c = 0xffffff end
              gfx.fill(i * COLW, ya, COLW * stride, yb - ya, c)
            end
          end
        end
      end
      i = i + stride
    end
  end
end

local function drawWeapon()
  local sway = math.floor(math.sin(P.bob) * 4 * P.moving)
  local drop = math.floor(math.abs(math.cos(P.bob)) * 3 * P.moving) + (P.flash > 0 and 5 or 0)
  local bx, by = SW // 2 + sway + 40, VIEW_H + 4 + drop
  gfx.fill(bx - 4, by - 36, 8, 26, 0x50565e)      -- barrel
  gfx.fill(bx - 9, by - 28, 18, 16, 0x7a838c)     -- slide
  gfx.fill(bx - 9, by - 28, 18, 2, 0xa8b2bc)
  gfx.fill(bx - 6, by - 14, 12, 14, 0x4a3626)     -- grip
  gfx.fill(bx - 11, by - 8, 22, 12, 0xd8a078)     -- hand
  if P.flash > 0 then
    gfx.triangle(bx - 7, by - 38, bx + 7, by - 38, bx, by - 58, 0xffb020)
    gfx.disc(bx, by - 40, 5, 0xfff0a0)
  end
end

local function drawCrosshair()
  local cx, cy = SW // 2, VIEW_H // 2
  local c = G.aim and 0xff4040 or 0xf0f0f0
  gfx.hline(cx - 5, cx - 2, cy, c)
  gfx.hline(cx + 2, cx + 5, cy, c)
  gfx.vline(cx, cy - 5, cy - 2, c)
  gfx.vline(cx, cy + 2, cy + 5, c)
end

local function drawMinimap(ui)
  local s, ox, oy = 2, SW - MW * 2 - 3, 3
  gfx.fill(ox - 1, oy - 1, MW * s + 2, MH * s + 2, 0x000000)
  for y = 0, MH - 1 do
    local x = 0
    while x < MW do
      local t = grid[y][x]
      if t > 0 then
        local x1 = x
        while x1 + 1 < MW and grid[y][x1 + 1] > 0 do x1 = x1 + 1 end
        gfx.fill(ox + x * s, oy + y * s, (x1 - x + 1) * s, s, 0x586078)
        x = x1 + 1
      else
        x = x + 1
      end
    end
  end
  for _, e in ipairs(enemies) do
    if not e.dead then gfx.fill(ox + math.floor(e.x * s) - 1, oy + math.floor(e.y * s) - 1, 2, 2, 0xff3030) end
  end
  local px, py = ox + P.x * s, oy + P.y * s
  gfx.line(math.floor(px), math.floor(py), math.floor(px + math.cos(P.angle) * 4), math.floor(py + math.sin(P.angle) * 4), 0xffff60)
  gfx.fill(math.floor(px) - 1, math.floor(py) - 1, 3, 3, 0x40ff80)
end

local function drawHud(ui)
  local t = ui.theme
  local y = VIEW_H
  gfx.fill(0, y, SW, HUD_H, t.panel)
  gfx.hline(0, SW - 1, y, t.border)
  ui.label(4, y + 5, "HP", t.dim)
  local hpColor = P.hp > 50 and t.accent or (P.hp > 25 and t.warn or t.danger)
  ui.bar(20, y + 3, 66, 11, math.max(0, P.hp), 100, hpColor, tostring(math.max(0, P.hp)))
  ui.label(96, y + 5, "AMMO", t.dim)
  ui.label(128, y + 5, tostring(P.ammo), P.ammo <= 5 and t.danger or t.text)
  local total = #enemies
  ui.label(160, y + 5, "KILLS " .. P.kills .. "/" .. total, t.text)
end

-- one picture of the game; the ui library gives the bar at the bottom
local function render(ui)
  local horizon = math.floor(HALF + math.sin(P.bob * 2) * 2.5 * P.moving)
  drawWorld(horizon)
  drawThings(horizon)
  drawWeapon()
  drawCrosshair()
  if G.map then drawMinimap(ui) end
  if G.msgT > 0 then ui.label(4, 3, G.msg, 0xffe060) end
  if P.hurt > 0 then
    for k = 0, 2 do gfx.rect(k, k, SW - 2 * k, VIEW_H - 2 * k, shade(0xff2020, math.floor(256 * math.min(1.0, P.hurt * 2.5)))) end
  end
  drawHud(ui)
end

-- ---- checks of the rules ----

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  math.randomseed(7)
  check(#MAP_TEXT == MH, "the level has 24 rows")
  for i, row in ipairs(MAP_TEXT) do
    check(#row == MW, "row " .. i .. " has 24 characters")
    check(row:sub(1, 1):match("[1-4]") and row:sub(-1):match("[1-4]"), "row " .. i .. " has walls at the edges")
  end
  check(MAP_TEXT[1]:match("^[1-4]+$") and MAP_TEXT[MH]:match("^[1-4]+$"), "the top and the bottom are walls")
  check(#SPAWN.enemies == 13 and #SPAWN.pickups == 8, "13 monsters and 8 pickups")
  check(SPAWN.start.x == 2.5 and SPAWN.start.y == 2.5, "the start is at 2.5, 2.5")
  -- everything can be reached from the start
  local seen, queue = { ["2,2"] = true }, { { 2, 2 } }
  while #queue > 0 do
    local c = table.remove(queue)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = c[1] + d[1], c[2] + d[2]
      if wallAt(nx, ny) == 0 and not seen[nx .. "," .. ny] then
        seen[nx .. "," .. ny] = true
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  local lost = 0
  for _, s in ipairs(SPAWN.enemies) do if not seen[math.floor(s.x) .. "," .. math.floor(s.y)] then lost = lost + 1 end end
  for _, s in ipairs(SPAWN.pickups) do if not seen[math.floor(s.x) .. "," .. math.floor(s.y)] then lost = lost + 1 end end
  check(lost == 0, "every monster and pickup can be reached")

  local d, side = cast(2.5, 2.5, 1, 0)
  check(math.abs(d - 5.5) < 1e-9 and side == 0, "a ray east from the start hits the wall at x = 8")
  check(wallAt(0, 0) == 1 and wallAt(8, 1) == 2 and wallAt(16, 1) == 3 and wallAt(-1, 3) == 9 and wallAt(2, 2) == 0, "wall kinds")
  check(inWall(1.1, 2.5, RADIUS) and not inWall(2.5, 2.5, RADIUS), "the circle stays out of walls")

  -- walking: w sets a speed, again a run, s slows down; the speed grows smoothly and a wall stops you
  newGame()
  check(handleKey("w") == nil and P.level == 1, "w walks")
  handleKey("w"); handleKey("w")
  check(P.level == 2, "w again runs, and no faster")
  handleKey("s")
  check(P.level == 1, "s slows down")
  handleKey("s"); handleKey("s"); handleKey("s")
  check(P.level == -1, "s again walks back, and no further")
  handleKey("w"); handleKey("w")
  check(P.level == 1, "w from walking back is a walk forward")
  step(0.03)
  check(P.vf > 0 and P.vf < THROTTLE[1], "the speed grows smoothly, not at once")
  for _ = 1, 400 do step(0.03) end
  check(P.x > 7.3 and P.x < 7.73, "a wall stops the walk before x = 8 (" .. string.format("%.2f", P.x) .. ")")
  handleKey(" ")
  check(P.level == 0 and P.turn == 0 and P.strafe == 0, "space stops every motion")
  for _ = 1, 40 do step(0.03) end
  check(math.abs(P.vf) < 1e-6, "the walk slows to a stop")

  -- turning and stepping: keys change the rate, the opposite key slows it down
  newGame()
  handleKey("d"); handleKey("d")
  check(P.turn == 2, "d twice turns fast")
  handleKey("a")
  check(P.turn == 1, "a slows the turn")
  for _ = 1, 30 do step(0.03) end
  check(P.angle > 0.8 and P.angle < 1.1, "a slow turn right for 0.9 s is about 1 radian")
  newGame()
  handleKey("z")
  check(math.abs(P.angle + SNAP) < 1e-9, "z is a quick turn left")
  handleKey("c"); handleKey("c")
  check(math.abs(P.angle - SNAP) < 1e-9, "c is a quick turn right")
  newGame()
  handleKey("e"); handleKey("e")
  check(P.strafe == 1, "e steps right, and no more")
  handleKey("q")
  check(P.strafe == 0, "q stops the step")

  -- shooting: a monster in front dies after three hits; one behind a wall is not hit; no ammo means no shot
  newGame()
  enemies = { { type = TYPES.imp, kind = "imp", x = 5.5, y = 2.5, hp = 3, cool = 9, alert = false, flash = 0, dead = false, deadT = 0 } }
  local e = enemies[1]
  check(aimedAt() == e, "the imp is in the sights")
  fire()
  check(P.ammo == 35 and e.hp == 2 and P.flash > 0, "a shot costs one bullet and one health point")
  fire()
  check(e.hp == 2, "the gun needs a moment between shots")
  for _ = 1, 3 do P.cool = 0; fire() end
  check(e.dead and P.kills == 1, "three hits kill the imp")
  check(aimedAt() == nil, "a dead monster is not a target")
  newGame()
  enemies = { { type = TYPES.imp, kind = "imp", x = 9.5, y = 2.5, hp = 3, cool = 9, alert = false, flash = 0, dead = false, deadT = 0 } }
  check(aimedAt() == nil, "a monster behind a wall cannot be hit")
  newGame()
  P.ammo = 0
  enemies = { { type = TYPES.imp, kind = "imp", x = 5.5, y = 2.5, hp = 3, cool = 9, alert = false, flash = 0, dead = false, deadT = 0 } }
  fire()
  check(enemies[1].hp == 3 and P.ammo == 0, "no ammo, no shot")
  newGame()
  enemies = { { type = TYPES.imp, kind = "imp", x = 5.5, y = 4.5, hp = 3, cool = 9, alert = false, flash = 0, dead = false, deadT = 0 } }
  check(aimedAt() == nil, "a monster to the side is missed")
  P.angle = math.atan(2.0, 3.0)
  check(aimedAt() == enemies[1], "after turning the monster is hit")

  -- monsters: a demon bites, an imp throws a fireball, a monster that cannot see you stays where it is
  newGame()
  enemies = { { type = TYPES.demon, kind = "demon", x = 3.2, y = 2.5, hp = 5, cool = 0, alert = false, flash = 0, dead = false, deadT = 0 } }
  step(0.1)
  check(enemies[1].alert and P.hp < 100, "a demon that sees you bites")
  newGame()
  enemies = { { type = TYPES.imp, kind = "imp", x = 6.5, y = 2.5, hp = 3, cool = 0, alert = false, flash = 0, dead = false, deadT = 0 } }
  step(0.1)
  check(#balls == 1, "an imp that sees you throws a fireball")
  for _ = 1, 30 do step(0.05) end
  check(P.hp < 100 and #balls == 0, "the fireball hurts and is gone")
  newGame()
  enemies = { { type = TYPES.demon, kind = "demon", x = 9.5, y = 2.5, hp = 5, cool = 0, alert = false, flash = 0, dead = false, deadT = 0 } }
  for _ = 1, 20 do step(0.05) end
  check(not enemies[1].alert and enemies[1].x == 9.5, "a monster behind a wall does not wake")

  -- pickups: health and ammo are taken, and health is not wasted when you are well
  newGame()
  pickups = { { kind = "health", x = 2.6, y = 2.5, taken = false } }
  step(0.03)
  check(not pickups[1].taken, "health is left when you are well")
  P.hp = 40
  step(0.03)
  check(pickups[1].taken and P.hp == 65, "health gives 25")
  pickups = { { kind = "ammo", x = 2.6, y = 2.5, taken = false } }
  step(0.03)
  check(pickups[1].taken and P.ammo == 51, "ammo gives 15")

  -- the level is won when every monster is dead
  newGame()
  for _, m in ipairs(enemies) do m.dead = true end
  for _ = 1, 50 do step(0.03) end
  check(G.won, "the level is won when every monster is dead")

  -- the colors
  check(shade(0xff8040, 128) == 0x7f4020 and shade(0x102030, 256) == 0x102030, "shade")
  check(fog(0) == 256 and fog(100) == 70, "fog")

  if failed == 0 then print("selftest ok") end
  return
end

-- ---- the program ----

local HELP = {
  "w / s    walk faster / slower",
  "a / d    turn left / right",
  "q / e    step left / right",
  "z / c    quick turn, to aim",
  "f or enter    fire",
  "space  stop    m  map    p  pause",
  "Tap a key again to go faster.",
  "ctrl-q quits.",
}

if #arg > 0 and arg[1] ~= "--start" then
  print("usage: doom [--start]   (--start skips the title)")
  return
end
if not gfx or not driver then
  print("doom 0.1 needs the graphics of firmware v0.1.0.13(beta): update with SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui")
if not ui then
  print("doom: " .. tostring(uiErr))
  return
end

local function titleBackground()
  for i = 0, 11 do gfx.fill(0, i * 12, SW, 12, shade(0x601010, 60 + i * 12)) end
  ui.center(14, "DOOM", 0x400808, 6, 3, SW + 3)
  ui.center(11, "DOOM", 0xff3020, 6)
  ui.center(62, "version 0.1.0", 0xe8c0b0, 1)
end

local function playLevel()
  newGame()
  local last = sys.millis()
  while true do
    local now = sys.millis()
    local dt = math.min((now - last) / 1000, 0.1)
    last = now
    local k = key.poll()
    while k do
      local r = handleKey(k)
      if r == "quit" then return "quit" end
      if r == "pause" then
        local c = ui.choose("Paused", { "Resume", "How to play", "Quit to the title" }, { background = function() render(ui) end })
        if c == 2 then ui.message("How to play", HELP) end
        if c == 3 or c == nil then return "menu" end
        last = sys.millis()
      end
      k = key.poll()
    end
    step(dt)
    render(ui)
    gfx.flush()
    if P.hp <= 0 then return "dead" end
    if G.won then return "won" end
    sys.sleep(1)
  end
end

local function main()
  local w, h = ui.open()
  if not w then
    print("doom: " .. tostring(h))
    return
  end
  local skipTitle = arg[1] == "--start"
  while true do
    local choice = skipTitle and 1 or ui.choose("Choose", { "Start game", "How to play", "Quit" }, { y = 76, background = titleBackground })
    skipTitle = false
    if choice == 1 then
      while true do
        local result = playLevel()
        if result == "dead" then
          if ui.choose("You died", { "Try again", "Title" }, { background = function() render(ui) end }) ~= 1 then break end
        elseif result == "won" then
          local text = string.format("Level clear in %d seconds", math.floor(G.time))
          if ui.choose(text, { "Play again", "Title" }, { background = function() render(ui) end }) ~= 1 then break end
        else
          if result == "quit" then return end
          break
        end
      end
    elseif choice == 2 then
      ui.message("How to play", HELP, { background = titleBackground })
    else
      return
    end
  end
end

local ok, err = pcall(main)
ui.close()  -- also after Ctrl+C, which stops the game with an error
if not ok and not tostring(err):find("interrupted", 1, true) then print("doom: " .. tostring(err)) end
