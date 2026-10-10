#!lua
-- snake: eat the food and grow without hitting the walls or yourself.
-- Arrows or w a s d steer, Enter starts a new game after game over, q quits.

local X0, X1, Y0, Y1 = 1, 38, 2, 14  -- playing field (inside the border)
local STEP_FRAMES = 3                 -- one move every 3 frames
local FRAME_MS = 40

local function randomFree(body)
  while true do
    local x = math.random(X0, X1)
    local y = math.random(Y0, Y1)
    local taken = false
    for _, s in ipairs(body) do
      if s.x == x and s.y == y then taken = true break end
    end
    if not taken then return { x = x, y = y } end
  end
end

local function newGame()
  local body = { { x = 20, y = 8 }, { x = 19, y = 8 }, { x = 18, y = 8 } }
  return {
    body = body, dx = 1, dy = 0, nextDx = 1, nextDy = 0,
    food = randomFree(body), score = 0, over = false, tick = 0,
  }
end

local function step(g)
  g.dx, g.dy = g.nextDx, g.nextDy
  local head = g.body[1]
  local nx, ny = head.x + g.dx, head.y + g.dy
  if nx < X0 or nx > X1 or ny < Y0 or ny > Y1 then
    g.over = true
    return
  end
  -- the tail moves away this step, so it is not a collision unless the snake grows
  local grow = nx == g.food.x and ny == g.food.y
  local last = #g.body
  for i, s in ipairs(g.body) do
    if i < last or grow then
      if s.x == nx and s.y == ny then
        g.over = true
        return
      end
    end
  end
  table.insert(g.body, 1, { x = nx, y = ny })
  if grow then
    g.score = g.score + 1
    g.food = randomFree(g.body)
  else
    table.remove(g.body)
  end
end

local function turn(g, dx, dy)
  -- no reversing into your own neck
  if dx ~= 0 and g.dx == -dx then return end
  if dy ~= 0 and g.dy == -dy then return end
  g.nextDx, g.nextDy = dx, dy
end

local function draw(g)
  term.clear()
  term.text(0, 0, string.format(" SNAKE  score %d", g.score), "white")
  term.text(0, 1, string.rep("#", 40), "dim")
  term.text(0, 15, string.rep("#", 40), "dim")
  for y = 2, 14 do
    term.put(0, y, "#", "dim")
    term.put(39, y, "#", "dim")
  end
  term.put(g.food.x, g.food.y, "*", "yellow")
  for i, s in ipairs(g.body) do
    if i == 1 then
      term.put(s.x, s.y, "O", "white")
    else
      term.put(s.x, s.y, "o", "green")
    end
  end
  if g.over then
    term.text(12, 7, "GAME OVER", "red")
    term.text(6, 9, "enter: play again   q: quit", "dim")
  end
  term.flush()
end

term.fullscreen(true)
local game = newGame()
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then
      quit = true
    elseif k == "enter" and game.over then
      game = newGame()
    elseif k == "up" or k == "w" then
      turn(game, 0, -1)
    elseif k == "down" or k == "s" then
      turn(game, 0, 1)
    elseif k == "left" or k == "a" then
      turn(game, -1, 0)
    elseif k == "right" or k == "d" then
      turn(game, 1, 0)
    end
    k = key.poll()
  end
  if quit then break end

  if not game.over then
    game.tick = game.tick + 1
    if game.tick >= STEP_FRAMES then
      game.tick = 0
      step(game)
    end
  end
  draw(game)
  sys.sleep(FRAME_MS)
end
term.fullscreen(false)
