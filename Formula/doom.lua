#!lua
-- doom 0.1.1: a Doom-like shooter with pixel graphics. Walk a level, shoot the imps and demons, pick up health and
-- ammo, and clear the level. Needs firmware v0.1.0.13(beta) (the graphics) and the packages ui, doomlevel and doomdraw:
--   brew install ui doomlevel doomdraw doom
-- The level and the picture are drivers (doomlevel.lua, doomdraw.lua): this file is only the rules, the keys and the menus.
-- Every key is a letter, so no Fn is needed, and nothing has to be held down:
--   w  walk, again for a run            s  slow down, then walk back
--   a  turn left, again for faster      d  turn right, again for faster
--   q  step left                        e  step right (the other key stops a step)
--   z  quick turn left                  c  quick turn right (for aiming)
--   f or enter  fire                    space  stop everything
--   m  the map     p  pause     ctrl-q  quit
-- A key sets how fast you go and the motion goes on by itself: tap w once and you keep walking, tap it again and you run,
-- tap s to slow down. Run it as a script with --selftest to check the game rules; doom --start skips the title.

local level, draw, ui, loadErr

local function loadDrivers()
  if not driver then return "doom needs the driver module: update the firmware" end
  local lv, e1 = driver.load("doomlevel")
  if not lv then return e1 end
  local dw, e2 = driver.load("doomdraw")
  if not dw then return e2 end
  local u, e3 = driver.load("ui")
  if not u then return e3 end
  level, draw, ui = lv, dw, u
  return nil
end
loadErr = loadDrivers()

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

-- ---- checks of the rules ----

if arg[1] == "--selftest" then
  if loadErr then
    print("doom: " .. tostring(loadErr))
    return
  end
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local MAP_TEXT, MW, MH = level.MAP_TEXT, level.MW, level.MH
  local SPAWN = level.spawn
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
      if level.wallAt(nx, ny) == 0 and not seen[nx .. "," .. ny] then
        seen[nx .. "," .. ny] = true
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  local lost = 0
  for _, s in ipairs(SPAWN.enemies) do if not seen[math.floor(s.x) .. "," .. math.floor(s.y)] then lost = lost + 1 end end
  for _, s in ipairs(SPAWN.pickups) do if not seen[math.floor(s.x) .. "," .. math.floor(s.y)] then lost = lost + 1 end end
  check(lost == 0, "every monster and pickup can be reached")

  local d, side = level.cast(2.5, 2.5, 1, 0)
  check(math.abs(d - 5.5) < 1e-9 and side == 0, "a ray east from the start hits the wall at x = 8")
  check(level.wallAt(0, 0) == 1 and level.wallAt(8, 1) == 2 and level.wallAt(16, 1) == 3 and level.wallAt(-1, 3) == 9
        and level.wallAt(2, 2) == 0, "wall kinds")
  check(level.inWall(1.1, 2.5, RADIUS) and not level.inWall(2.5, 2.5, RADIUS), "the circle stays out of walls")

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

  -- the colours
  check(draw.shade(0xff8040, 128) == 0x7f4020 and draw.shade(0x102030, 256) == 0x102030, "shade")
  check(draw.fog(0) == 256 and draw.fog(100) == 70, "fog")

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
if not gfx then
  print("doom 0.1 needs the graphics of firmware v0.1.0.13(beta): update with SystemUpdateBeta")
  return
end
if loadErr then
  print("doom: " .. tostring(loadErr))
  print("doom: install the parts with: brew install ui doomlevel doomdraw")
  return
end

local function titleBackground()
  for i = 0, 11 do gfx.fill(0, i * 12, 240, 12, draw.shade(0x601010, 60 + i * 12)) end
  ui.center(14, "DOOM", 0x400808, 6, 3, 243)
  ui.center(11, "DOOM", 0xff3020, 6)
  ui.center(62, "version 0.1.1", 0xe8c0b0, 1)
end

local function render()
  draw.render(frame(), ui)
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
        local c = ui.choose("Paused", { "Resume", "How to play", "Quit to the title" }, { background = render })
        if c == 2 then ui.message("How to play", HELP) end
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
          if ui.choose("You died", { "Try again", "Title" }, { background = render }) ~= 1 then break end
        elseif result == "won" then
          local text = string.format("Level clear in %d seconds", math.floor(G.time))
          if ui.choose(text, { "Play again", "Title" }, { background = render }) ~= 1 then break end
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
