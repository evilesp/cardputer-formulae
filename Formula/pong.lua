#!lua
-- pong: you (left paddle) against the computer. Up/down or w/s move the paddle, q quits.

local X0, X1, Y0, Y1 = 1, 38, 2, 14
local PADDLE = 3
local LEFT_X, RIGHT_X = 2, 37
local FRAME_MS = 45

local function newBall(towardsYou)
  return {
    x = 19.5, y = 8.0,
    vx = towardsYou and -0.6 or 0.6,
    vy = (math.random(0, 1) == 0 and -0.35 or 0.35),
  }
end

local g = {
  ball = newBall(math.random(0, 1) == 0),
  you = 8.0, cpu = 8.0,
  youScore = 0, cpuScore = 0,
  pause = 0,
}

local function clampPaddle(p)
  if p < Y0 + 1 then return Y0 + 1 end
  if p > Y1 - 1 then return Y1 - 1 end
  return p
end

local function hitPaddle(paddleY, by)
  return math.abs(by - paddleY) <= PADDLE / 2 + 0.5
end

local function update()
  if g.pause > 0 then
    g.pause = g.pause - 1
    return
  end
  local b = g.ball
  b.x = b.x + b.vx
  b.y = b.y + b.vy

  -- top and bottom walls
  if b.y < Y0 then b.y = Y0 + (Y0 - b.y); b.vy = -b.vy end
  if b.y > Y1 then b.y = Y1 - (b.y - Y1); b.vy = -b.vy end

  -- paddles: bounce, and the hit position changes the angle
  if b.vx < 0 and b.x <= LEFT_X + 0.5 and hitPaddle(g.you, b.y) then
    b.x = LEFT_X + 0.5
    b.vx = -b.vx
    b.vy = b.vy + (b.y - g.you) * 0.15
  elseif b.vx > 0 and b.x >= RIGHT_X - 0.5 and hitPaddle(g.cpu, b.y) then
    b.x = RIGHT_X - 0.5
    b.vx = -b.vx
    b.vy = b.vy + (b.y - g.cpu) * 0.15
  end

  -- a point is scored when the ball leaves the field
  if b.x < X0 then
    g.cpuScore = g.cpuScore + 1
    g.ball = newBall(false)
    g.pause = 30
  elseif b.x > X1 then
    g.youScore = g.youScore + 1
    g.ball = newBall(true)
    g.pause = 30
  end

  -- the computer paddle follows the ball, with a speed limit
  local diff = g.ball.y - g.cpu
  if diff > 0.45 then g.cpu = g.cpu + 0.45 elseif diff < -0.45 then g.cpu = g.cpu - 0.45 end
  g.cpu = clampPaddle(g.cpu)
end

local function draw()
  term.clear()
  term.text(0, 0, string.format("PONG   you %d : %d cpu", g.youScore, g.cpuScore), "white")
  term.text(0, 1, string.rep("-", 40), "dim")
  term.text(0, 15, string.rep("-", 40), "dim")
  for y = Y0, Y1 do
    if math.abs(y - g.you) <= PADDLE / 2 then term.put(LEFT_X, y, "|", "cyan") end
    if math.abs(y - g.cpu) <= PADDLE / 2 then term.put(RIGHT_X, y, "|", "magenta") end
    term.put(19, y, ":", "dim")
  end
  term.put(math.floor(g.ball.x + 0.5), math.floor(g.ball.y + 0.5), "O", "yellow")
  term.text(12, 15, "w/s or up/down   q quit", "dim")
  term.flush()
end

term.fullscreen(true)
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true
    elseif k == "up" or k == "w" then g.you = clampPaddle(g.you - 1.5)
    elseif k == "down" or k == "s" then g.you = clampPaddle(g.you + 1.5)
    end
    k = key.poll()
  end
  if quit then break end
  update()
  draw()
  sys.sleep(FRAME_MS)
end
term.fullscreen(false)
