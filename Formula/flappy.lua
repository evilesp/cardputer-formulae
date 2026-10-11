#!lua
-- flappy: keep the bird in the air and fly through the gaps between the pipes. Space (or f) flaps, the best score is
-- kept while the game runs, ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the rules.

local GAP = 40
local PIPE_W = 16
local BIRD_X = 40
local BIRD_R = 4
local GRAVITY = 380
local FLAP = -130
local SPEED = 60

-- true when the bird (at height y) is inside a pipe whose left edge is at x with its gap starting at gapY
local function hitsPipe(x, gapY, y)
  if BIRD_X + BIRD_R < x or BIRD_X - BIRD_R > x + PIPE_W then return false end
  return y - BIRD_R < gapY or y + BIRD_R > gapY + GAP
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(hitsPipe(BIRD_X, 20, 5), "the bird above the gap hits the pipe")
  check(not hitsPipe(BIRD_X, 20, 40), "the bird in the gap is safe")
  check(not hitsPipe(200, 20, 5), "a pipe far away does not hit")
  check(hitsPipe(BIRD_X + BIRD_R - 1, 20, 100), "a pipe below the gap hits the bird")
  check(not hitsPipe(0, 20, 5), "a pipe behind the bird does not hit")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("flappy needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("flappy: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("flappy: " .. tostring(uiErr))
  return
end

local W, H = 240, 135

local function newGame()
  return { y = H / 2, vy = 0, pipes = {}, nextPipe = 0, score = 0, best = 0, started = false, over = false, time = 0 }
end

local G = newGame()
local bestEver = 0

local function step(dt)
  if G.over or not G.started then return end
  G.vy = G.vy + GRAVITY * dt
  G.y = G.y + G.vy * dt
  G.time = G.time + dt
  G.nextPipe = G.nextPipe - dt
  if G.nextPipe <= 0 then
    G.pipes[#G.pipes + 1] = { x = W + 10, gapY = 20 + math.random(H - GAP - 40), passed = false }
    G.nextPipe = 1.6
  end
  for i = #G.pipes, 1, -1 do
    local p = G.pipes[i]
    p.x = p.x - SPEED * dt
    if not p.passed and p.x + PIPE_W < BIRD_X then
      p.passed = true
      G.score = G.score + 1
    end
    if p.x < -PIPE_W then table.remove(G.pipes, i) end
    if hitsPipe(p.x, p.gapY, G.y) then G.over = true end
  end
  if G.y - BIRD_R < 0 or G.y + BIRD_R > H then G.over = true end
  if G.over and G.score > bestEver then bestEver = G.score end
end

local function draw()
  gfx.clear(0x0a1a2e)
  for _, p in ipairs(G.pipes) do
    gfx.fill(p.x, 0, PIPE_W, p.gapY, 0x3a9a40)
    gfx.fill(p.x, p.gapY + GAP, PIPE_W, H - p.gapY - GAP, 0x3a9a40)
  end
  gfx.circle(BIRD_X, math.floor(G.y), BIRD_R, 0xffe040, true)
  gfx.fill(BIRD_X + 3, math.floor(G.y) - 1, 3, 2, 0xff8020)
  ui.label(4, 2, "SCORE " .. G.score, 0xe8ecf4)
  ui.label(W - 72, 2, "BEST " .. bestEver, 0xe8ecf4)
  if not G.started then ui.center(60, "space to flap, to start", 0xe8ecf4, 1) end
  if G.over then
    ui.center(54, "GAME OVER", 0xff4040, 2)
    ui.center(76, "space: play again   ctrl-q: quit", 0x8a94aa, 1)
  end
  gfx.flush()
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if k == " " or k == "f" or k == "w" or k == "enter" then
    if G.over then
      G = newGame()
      G.started = true
      G.vy = FLAP
    elseif not G.started then
      G.started = true
      G.vy = FLAP
    else
      G.vy = FLAP
    end
  end
  return true
end

local w, h = ui.open()
if not w then
  print("flappy: " .. tostring(h))
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
    sys.sleep(20)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("flappy: " .. tostring(problem)) end
