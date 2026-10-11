#!lua
-- doomgame: the rules and the menus of doom. A driver, not a program: doom loads it with driver.load("doomgame", true) and
-- calls game.run(). It holds the player, the monsters, the shooting and the game loop; the picture and the menus are the driver
-- doomdraw, which it loads itself, and the level the driver doomlevel, which doomdraw loads. Every key is a letter, so no Fn is needed, and nothing has to be
-- held down:
--   w  walk, again for a run            s  slow down, then walk back
--   a  turn left, again for faster      d  turn right, again for faster
--   q  step left                        e  step right (the other key stops a step)
--   z  quick turn left                  c  quick turn right (for aiming)
--   f or enter  fire                    space  stop everything
--   m  the map     p  pause     ctrl-q  quit
-- A key sets how fast you go and the motion goes on by itself: tap w once and you keep walking, tap it again and you run,
-- tap s to slow down. The rules are checked by tests/lua_host/doom_rules.lua (it is not a part of the package, so it does not
-- take memory on the Cardputer).

local draw, drawErr = driver.load("doomdraw", true)  -- which loads doomlevel
if not draw then error(drawErr, 0) end
local level = draw.level

local game = {}

local RADIUS = 0.28                -- the player and the monsters do not touch a wall
local THROTTLE = { [-1] = -1.7, [0] = 0, [1] = 2.5, [2] = 4.2 }          -- cells per second, by speed level
local TURNING = { [-2] = -2.5, [-1] = -1.1, [0] = 0, [1] = 1.1, [2] = 2.5 }  -- radians per second, by turn level
local STEP = 2.3                   -- sideways cells per second
local ACCEL = 14.0                 -- cells per second, every second: the walk speeds up and slows down smoothly
local SNAP = 0.18                  -- a quick turn, about 10 degrees
local FIRE_EVERY = 0.34            -- seconds between shots

local TYPES = {
  imp = { name = "imp", hp = 3, speed = 1.2, ranged = true, size = 0.85 },
  demon = { name = "demon", hp = 5, speed = 2.1, ranged = false, size = 0.95 },
}

local P, enemies, pickups, balls, G

local function approach(v, target, maxStep)
  if v < target then return math.min(v + maxStep, target) end
  return math.max(v - maxStep, target)
end

local function newGame()
  local start = level.spawn.start
  P = { x = start.x, y = start.y, angle = 0.0, hp = 100, ammo = 36, kills = 0,
        level = 0, turn = 0, strafe = 0, vf = 0.0, vs = 0.0, cool = 0.0, flash = 0.0, hurt = 0.0, bob = 0.0, moving = 0.0 }
  enemies, pickups, balls = {}, {}, {}
  for _, s in ipairs(level.spawn.enemies) do
    local t = TYPES[s.kind]
    enemies[#enemies + 1] = { type = t, kind = s.kind, x = s.x, y = s.y, hp = t.hp, cool = 1 + math.random(), alert = false,
                              flash = 0.0, dead = false, deadT = 0.0 }
  end
  for _, s in ipairs(level.spawn.pickups) do pickups[#pickups + 1] = { kind = s.kind, x = s.x, y = s.y, taken = false } end
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
  if not level.inWall(nx, P.y, RADIUS) and not aliveEnemyNear(nx, P.y, 0.55) then P.x = nx end
  if not level.inWall(P.x, ny, RADIUS) and not aliveEnemyNear(P.x, ny, 0.55) then P.y = ny end
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
  local wall = level.cast(P.x, P.y, dirX, dirY)
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
  if dist < 14 then sees = (level.cast(e.x, e.y, ux, uy)) >= dist - 0.2 end
  if sees then e.alert = true end
  if not e.alert then return end
  e.cool = e.cool - dt
  if dist > (e.type.ranged and 3.0 or 0.85) then
    local nx, ny = e.x + ux * e.type.speed * dt, e.y + uy * e.type.speed * dt
    if not level.inWall(nx, e.y, 0.3) and not aliveEnemyNear(nx, e.y, 0.6, e) and (nx - P.x) ^ 2 + (e.y - P.y) ^ 2 > 0.36 then e.x = nx end
    if not level.inWall(e.x, ny, 0.3) and not aliveEnemyNear(e.x, ny, 0.6, e) and (e.x - P.x) ^ 2 + (ny - P.y) ^ 2 > 0.36 then e.y = ny end
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
    local gone = b.life <= 0 or level.wallAt(math.floor(b.x), math.floor(b.y)) > 0
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

local function frame()
  return { P = P, enemies = enemies, pickups = pickups, balls = balls, G = G }
end

-- for the tests
game.state, game.newGame, game.step, game.handleKey, game.fire, game.aimedAt = frame, newGame, step, handleKey, fire, aimedAt
game.const = { RADIUS = RADIUS, THROTTLE = THROTTLE, SNAP = SNAP, TYPES = TYPES }
function game.set(name, value)
  if name == "enemies" then enemies = value
  elseif name == "pickups" then pickups = value
  elseif name == "balls" then balls = value end
end

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

local function titleBackground()
  for i = 0, 11 do gfx.fill(0, i * 12, 240, 12, draw.shade(0x601010, 60 + i * 12)) end
  draw.center(14, "DOOM", 0x400808, 6, 3, 243)
  draw.center(11, "DOOM", 0xff3020, 6)
  draw.center(62, "version 0.1.1.1", 0xe8c0b0, 1)
end

local function render()
  draw.render(frame())
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
        local c = draw.choose("Paused", { "Resume", "How to play", "Quit to the title" }, { background = render })
        if c == 2 then draw.message("How to play", HELP) end
        if c == 3 or c == nil then return "menu" end
        last = sys.millis()
      end
      k = key.poll()
    end
    step(dt)
    render()
    gfx.flush()
    if P.hp <= 0 then return "dead" end
    if G.won then return "won" end
    sys.sleep(1)
  end
end

local function main(start)
  local w, h = gfx.open()
  if not w then
    print("doom: " .. tostring(h))
    return
  end
  local skipTitle = start
  while true do
    local choice = skipTitle and 1 or draw.choose("Choose", { "Start game", "How to play", "Quit" }, { y = 76, background = titleBackground })
    skipTitle = false
    if choice == 1 then
      while true do
        local result = playLevel()
        if result == "dead" then
          if draw.choose("You died", { "Try again", "Title" }, { background = render }) ~= 1 then break end
        elseif result == "won" then
          local text = string.format("Level clear in %d seconds", math.floor(G.time))
          if draw.choose(text, { "Play again", "Title" }, { background = render }) ~= 1 then break end
        else
          if result == "quit" then return end
          break
        end
      end
    elseif choice == 2 then
      draw.message("How to play", HELP, { background = titleBackground })
    else
      return
    end
  end
end

-- Plays: the title, the menus and the levels. start true skips the title. Gives the screen back at the end, and after Ctrl+C
-- (which stops the game with an error).
function game.run(start)
  local ok, err = pcall(main, start)
  gfx.close()
  if not ok and not tostring(err):find("interrupted", 1, true) then print("doom: " .. tostring(err)) end
end

return game
