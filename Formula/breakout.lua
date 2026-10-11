#!lua
-- breakout: break the bricks with the ball. a and d move the paddle (tap again to keep going), space stops it, the ball
-- starts when you press f. You have three balls. ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the rules.

local COLS_B, ROWS_B = 10, 5
local BRICK_W, BRICK_H = 22, 7
local PADDLE_W = 36
local BALL_R = 2

-- the bricks: { x, y, alive, row }
local function newBricks()
  local bricks = {}
  for r = 1, ROWS_B do
    for c = 1, COLS_B do
      bricks[#bricks + 1] = { x = 6 + (c - 1) * (BRICK_W + 1), y = 16 + (r - 1) * (BRICK_H + 2), alive = true, row = r }
    end
  end
  return bricks
end

-- which brick a point is in, or nil
local function brickAt(bricks, x, y)
  for i, b in ipairs(bricks) do
    if b.alive and x >= b.x and x < b.x + BRICK_W and y >= b.y and y < b.y + BRICK_H then return i end
  end
  return nil
end

-- the new direction of the ball after it bounces off the paddle: the further from its middle, the sharper the bounce
local function paddleBounce(ballX, paddleX)
  local offset = (ballX - (paddleX + PADDLE_W / 2)) / (PADDLE_W / 2)
  if offset < -1 then offset = -1 elseif offset > 1 then offset = 1 end
  return offset
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local bricks = newBricks()
  check(#bricks == 50, "50 bricks")
  check(brickAt(bricks, 6, 16) == 1, "the first brick is found")
  check(brickAt(bricks, 6 + BRICK_W, 16) == nil, "the gap between bricks is empty")
  bricks[1].alive = false
  check(brickAt(bricks, 6, 16) == nil, "a broken brick is gone")
  check(paddleBounce(100, 100 - PADDLE_W / 2) == 0, "the middle of the paddle bounces straight")
  check(paddleBounce(1000, 0) == 1 and paddleBounce(-1000, 0) == -1, "the bounce is limited to -1 and 1")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("breakout needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("breakout: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui")
if not ui then
  print("breakout: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local ROW_COLOR = { 0xe05050, 0xe08040, 0xe0c040, 0x60d060, 0x40a0e0 }

local function newGame()
  return {
    bricks = newBricks(), px = W // 2 - PADDLE_W // 2, pdir = 0,
    bx = W // 2, by = H - 30, vx = 0, vy = 0, live = false,
    balls = 3, score = 0, over = false, won = false, msg = "", msgT = 0,
  }
end

local G = newGame()
local function say(text)
  G.msg, G.msgT = text, 1.2
end

local function serve()
  G.live = true
  G.vx, G.vy = 70, -95
  G.bx, G.by = G.px + PADDLE_W / 2, H - 30
end

local function step(dt)
  if G.over or G.won then return end
  G.px = math.max(2, math.min(W - 2 - PADDLE_W, G.px + G.pdir * 150 * dt))
  if not G.live then
    G.bx = G.px + PADDLE_W / 2
    return
  end
  G.bx = G.bx + G.vx * dt
  G.by = G.by + G.vy * dt
  if G.bx < BALL_R then G.bx, G.vx = BALL_R, -G.vx end
  if G.bx > W - BALL_R then G.bx, G.vx = W - BALL_R, -G.vx end
  if G.by < BALL_R + 10 then G.by, G.vy = BALL_R + 10, -G.vy end
  local hit = brickAt(G.bricks, G.bx, G.by)
  if hit then
    G.bricks[hit].alive = false
    G.score = G.score + (ROWS_B + 1 - G.bricks[hit].row) * 5
    G.vy = -G.vy
  end
  if G.vy > 0 and G.by >= H - 12 and G.by <= H - 8 and G.bx >= G.px - 2 and G.bx <= G.px + PADDLE_W + 2 then
    G.vy = -math.abs(G.vy)
    G.vx = 110 * paddleBounce(G.bx, G.px)
  end
  if G.by > H then
    G.balls = G.balls - 1
    G.live = false
    if G.balls <= 0 then
      G.over = true
    else
      say("ball lost")
    end
  end
  local left = 0
  for _, b in ipairs(G.bricks) do
    if b.alive then left = left + 1 end
  end
  if left == 0 then G.won = true end
  G.msgT = math.max(0, G.msgT - dt)
end

local function draw()
  gfx.clear(0x0a0c14)
  for _, b in ipairs(G.bricks) do
    if b.alive then gfx.fill(b.x, b.y, BRICK_W, BRICK_H, ROW_COLOR[b.row % #ROW_COLOR + 1]) end
  end
  gfx.fill(G.px, H - 10, PADDLE_W, 5, 0x40c0ff)
  if G.live then gfx.circle(math.floor(G.bx), math.floor(G.by), BALL_R, 0xffffff, true) end
  ui.label(4, 2, "SCORE " .. G.score, 0xe8ecf4)
  ui.label(W - 60, 2, "BALLS " .. G.balls, 0xe8ecf4)
  if not G.live and not G.over and not G.won then ui.center(80, "f: launch the ball", 0x8a94aa, 1) end
  if G.msgT > 0 then ui.center(96, G.msg, 0xffe060, 1) end
  if G.over then
    ui.center(56, "GAME OVER", 0xff4040, 2)
    ui.center(78, "f: play again   ctrl-q: quit", 0x8a94aa, 1)
  elseif G.won then
    ui.center(56, "YOU WIN", 0x60ff90, 2)
    ui.center(78, "f: play again   ctrl-q: quit", 0x8a94aa, 1)
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
    if G.over or G.won then G = newGame()
    elseif not G.live then serve() end
  end
  return true
end

local w, h = ui.open()
if not w then
  print("breakout: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local last = sys.millis()
  while true do
    local now = sys.millis()
    local dt = math.min((now - last) / 1000, 0.05)
    last = now
    local k = key.poll()
    while k do
      if not handle(k) then return end
      k = key.poll()
    end
    step(dt)
    draw()
    sys.sleep(15)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("breakout: " .. tostring(problem)) end
