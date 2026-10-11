#!lua
-- invaders: space invaders in pixels. The aliens march across and step down; you have three lives.
-- a and d move (tap again to keep going), space stops, f fires (up to three shots), ctrl-q quits.
-- Needs the graphics and the ui package (brew install ui). Run it with --selftest to check the rules.

local COLS_A, ROWS_A = 6, 3
local ALIEN_W, ALIEN_H = 16, 8
local PLAYER_W = 16
local SAFE_X, SAFE_Y = 4, 4

-- the alien formation of one wave: a table of { x, y, alive, row }, positions before the formation offset
local function newWave()
  local aliens = {}
  for r = 1, ROWS_A do
    for c = 1, COLS_A do
      aliens[#aliens + 1] = { x = 22 + (c - 1) * 32, y = 18 + (r - 1) * 14, alive = true, row = r }
    end
  end
  return aliens
end

-- the index of the alive alien that a shot at (bx, by) hits, given the formation offset (ox, oy), or nil
local function hitAlien(aliens, ox, oy, bx, by)
  for i, a in ipairs(aliens) do
    if a.alive then
      local x, y = a.x + ox, a.y + oy
      if bx >= x and bx < x + ALIEN_W and by >= y and by < y + ALIEN_H then return i end
    end
  end
  return nil
end

-- true when an alive alien reaches the side of the screen (the formation then turns and steps down)
local function atEdge(aliens, ox, dir, width)
  for _, a in ipairs(aliens) do
    if a.alive then
      local x = a.x + ox
      if (dir > 0 and x + ALIEN_W >= width - SAFE_X) or (dir < 0 and x <= SAFE_X) then return true end
    end
  end
  return false
end

local function lowestY(aliens, oy)
  local low = 0
  for _, a in ipairs(aliens) do
    if a.alive and a.y + oy + ALIEN_H > low then low = a.y + oy + ALIEN_H end
  end
  return low
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local a = newWave()
  check(#a == 18, "a wave has 18 aliens")
  check(hitAlien(a, 0, 0, 22, 18) == 1, "a shot inside the first alien hits it")
  check(hitAlien(a, 0, 0, 22 + ALIEN_W, 18) == nil, "a shot just beside it misses")
  check(hitAlien(a, 10, 4, 32, 22) == 1, "the formation offset moves the hit box")
  a[1].alive = false
  check(hitAlien(a, 0, 0, 22, 18) == nil, "a dead alien is not hit")
  check(atEdge(a, 0, 1, 240) == false, "the formation is not at the edge at the start")
  check(atEdge(a, 90, 1, 240), "the formation turns at the right edge")
  check(atEdge(a, -20, -1, 240), "the formation turns at the left edge")
  check(lowestY(a, 0) == 18 + 2 * 14 + ALIEN_H, "the lowest alien row is found")
  if failed == 0 then print("selftest ok") end
  return
end

local ui, uiErr
if not gfx then
  print("invaders needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("invaders: this firmware has no driver module")
  return
end
ui, uiErr = driver.load("ui")
if not ui then
  print("invaders: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local ROW_COLOR = { 0x60d060, 0xe0c040, 0xe05050 }
local PLAYER_Y = H - 14

local function newGame()
  return {
    aliens = newWave(), ox = 0, oy = 0, dir = 1, marchT = 0,
    px = W // 2 - PLAYER_W // 2, pdir = 0, shots = {}, bombs = {}, bombT = 0,
    lives = 3, score = 0, wave = 1, over = false, msg = "", msgT = 0,
  }
end

local G = newGame()

local function say(text)
  G.msg, G.msgT = text, 1.5
end

local function step(dt)
  if G.over then return end
  G.px = math.max(SAFE_X, math.min(W - SAFE_X - PLAYER_W, G.px + G.pdir * 120 * dt))
  for i = #G.shots, 1, -1 do
    local s = G.shots[i]
    s.y = s.y - 170 * dt
    local hit = hitAlien(G.aliens, G.ox, G.oy, s.x, s.y)
    if hit then
      G.aliens[hit].alive = false
      G.score = G.score + (4 - G.aliens[hit].row) * 10
      table.remove(G.shots, i)
    elseif s.y < 0 then
      table.remove(G.shots, i)
    end
  end
  G.marchT = G.marchT + dt
  local speed = 0.45 - math.min(0.3, (G.wave - 1) * 0.05)
  if G.marchT >= speed then
    G.marchT = 0
    if atEdge(G.aliens, G.ox, G.dir, W) then
      G.dir = -G.dir
      G.oy = G.oy + 6
    else
      G.ox = G.ox + G.dir * 4
    end
  end
  G.bombT = G.bombT - dt
  if G.bombT <= 0 then
    G.bombT = 1.1 - math.min(0.6, (G.wave - 1) * 0.1)
    local alive = {}
    for _, a in ipairs(G.aliens) do
      if a.alive then alive[#alive + 1] = a end
    end
    if #alive > 0 then
      local a = alive[math.random(#alive)]
      G.bombs[#G.bombs + 1] = { x = a.x + G.ox + ALIEN_W // 2, y = a.y + G.oy + ALIEN_H }
    end
  end
  for i = #G.bombs, 1, -1 do
    local b = G.bombs[i]
    b.y = b.y + 80 * dt
    if b.y >= PLAYER_Y and b.y <= PLAYER_Y + 6 and b.x >= G.px and b.x <= G.px + PLAYER_W then
      table.remove(G.bombs, i)
      G.lives = G.lives - 1
      say("hit!")
      if G.lives <= 0 then G.over = true end
    elseif b.y > H then
      table.remove(G.bombs, i)
    end
  end
  if lowestY(G.aliens, G.oy) >= PLAYER_Y then G.over = true end
  local any = false
  for _, a in ipairs(G.aliens) do
    if a.alive then any = true end
  end
  if not any then
    G.wave = G.wave + 1
    G.aliens, G.ox, G.oy, G.dir, G.marchT = newWave(), 0, 0, 1, 0
    G.bombs, G.shots = {}, {}
    say("wave " .. G.wave)
  end
  G.msgT = math.max(0, G.msgT - dt)
end

local function draw()
  gfx.clear(0x0a0c14)
  for _, a in ipairs(G.aliens) do
    if a.alive then
      local x, y = a.x + G.ox, a.y + G.oy
      gfx.fill(x, y, ALIEN_W, ALIEN_H, ROW_COLOR[a.row])
      gfx.fill(x + 3, y + 2, 2, 2, 0x000000)
      gfx.fill(x + ALIEN_W - 5, y + 2, 2, 2, 0x000000)
    end
  end
  gfx.fill(G.px, PLAYER_Y, PLAYER_W, 8, 0x40c0ff)
  gfx.fill(G.px + PLAYER_W // 2 - 1, PLAYER_Y - 3, 3, 3, 0x40c0ff)
  for _, s in ipairs(G.shots) do gfx.fill(s.x - 1, s.y, 2, 5, 0xffffff) end
  for _, b in ipairs(G.bombs) do gfx.fill(b.x - 1, b.y, 2, 5, 0xff6040) end
  ui.label(4, 2, "SCORE " .. G.score, 0xe8ecf4)
  ui.label(W - 64, 2, "LIVES " .. G.lives, 0xe8ecf4)
  if G.msgT > 0 then ui.center(60, G.msg, 0xffe060, 1) end
  if G.over then
    ui.center(54, "GAME OVER", 0xff4040, 2)
    ui.center(74, "f: play again   ctrl-q: quit", 0x8a94aa, 1)
  end
  gfx.flush()
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if #k == 1 then k = k:lower() end
  if k == "a" then G.pdir = -1
  elseif k == "d" then G.pdir = 1
  elseif k == " " then G.pdir = 0
  elseif k == "f" or k == "enter" then
    if G.over then
      G = newGame()
    elseif #G.shots < 3 then
      G.shots[#G.shots + 1] = { x = G.px + PLAYER_W // 2, y = PLAYER_Y - 4 }
    end
  end
  return true
end

local w, h = ui.open()
if not w then
  print("invaders: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local last = sys.millis()
  while true do
    local now = sys.millis()
    local dt = math.min((now - last) / 1000, 0.1)
    last = now
    local k = key.poll()
    while k do
      if not handle(k) then return end
      k = key.poll()
    end
    step(dt)
    draw()
    sys.sleep(20)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("invaders: " .. tostring(problem)) end
