#!lua
-- frogger: get the frog across the road and the cars. Move with w a s d, one square a press. Cars run along the lanes at
-- different speeds; a car on your square costs a life. Reach the top row for a point: the cars speed up. Three lives.
-- ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the traffic.

local COLS, ROWS = 15, 9
local CELL_W, CELL_H = 16, 13
local OX, OY = 0, 14
local START_ROW = ROWS
-- lanes: rows 2 to 7 are the road; each has a direction and a speed in squares a second
local LANES = {
  [2] = { dir = -1, speed = 1.2, gap = 5, len = 2 },
  [3] = { dir = 1, speed = 0.9, gap = 4, len = 3 },
  [4] = { dir = -1, speed = 1.7, gap = 6, len = 2 },
  [5] = { dir = 1, speed = 1.1, gap = 5, len = 2 },
  [6] = { dir = -1, speed = 2.0, gap = 4, len = 3 },
  [7] = { dir = 1, speed = 1.4, gap = 7, len = 2 },
}

-- true when a car of the lane covers column c at time t (seconds); the cars are spaced by gap squares
local function carCovers(lane, offset, t, c, speedUp)
  local spec = LANES[lane]
  if not spec then return false end
  local shift = (spec.speed * speedUp * t * spec.dir) % COLS
  for k = 0, COLS // spec.gap do
    local start = (offset + k * spec.gap + shift) % COLS
    for i = 0, spec.len - 1 do
      if math.floor((start + i) % COLS) == c - 1 then return true end
    end
  end
  return false
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(COLS == 15 and ROWS == 9, "the board is 15 by 9")
  -- at time 0 the first lane has a car from column 1 to 2 (offset 0)
  check(carCovers(2, 0, 0, 1, 1) == true and carCovers(2, 0, 0, 3, 1) == false, "a car covers its squares")
  -- lane 2 goes left at 1.2 squares a second: after 2 seconds its cars cover columns 13 and 14 (and no longer 1 and 2)
  check(carCovers(2, 0, 0, 2, 1) and not carCovers(2, 0, 0, 14, 1), "at the start the cars are at columns 1 and 2")
  check(carCovers(2, 0, 2.0, 14, 1) and not carCovers(2, 0, 2.0, 2, 1), "after 2 seconds they moved left")
  check(carCovers(3, 2, 1.5, 6, 1) == carCovers(3, 2, 1.5, 6, 1), "the traffic is repeatable")
  check(carCovers(1, 0, 0, 1, 1) == false, "the grass has no cars")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("frogger needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("frogger: " .. tostring(uiErr))
  return
end

local lanesOffset = {}
local frog, lives, score, speedUp, t0, deadUntil
local function newLanes()
  for lane, spec in pairs(LANES) do lanesOffset[lane] = (math.random(COLS) - 1) end
end

local function resetFrog()
  frog = { r = START_ROW, c = 8 }
end

local function draw(t)
  gfx.clear(0x0a0c14)
  for r = 1, ROWS do
    local y = OY + (r - 1) * CELL_H
    local colour = 0x1f5f2a
    if LANES[r] then colour = 0x2a2a2a end
    if r == 1 then colour = 0x1f7f3f end
    gfx.fill(0, y, COLS * CELL_W, CELL_H - 1, colour)
    if LANES[r] then
      for c = 1, COLS do
        if carCovers(r, lanesOffset[r], t, c, speedUp) then
          gfx.fill((c - 1) * CELL_W + 1, y + 2, CELL_W - 2, CELL_H - 5, LANES[r].dir > 0 and 0xe04040 or 0xe0a040)
        end
      end
    end
  end
  gfx.disc(frog.c * CELL_W - CELL_W // 2, OY + (frog.r - 1) * CELL_H + CELL_H // 2, 5, 0x60ff60)
  ui.label(4, 2, "score " .. score, 0xe8ecf4)
  ui.label(150, 2, "lives " .. lives, 0xe8ecf4)
  ui.label(4, 124, "w a s d hop   ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("frogger: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  lives, score, speedUp = 3, 0, 1.0
  newLanes()
  resetFrog()
  local t0 = sys.millis()
  while true do
    local t = (sys.millis() - t0) / 1000
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "w" then frog.r = math.max(1, frog.r - 1)
      elseif k == "s" then frog.r = math.min(ROWS, frog.r + 1)
      elseif k == "a" then frog.c = math.max(1, frog.c - 1)
      elseif k == "d" then frog.c = math.min(COLS, frog.c + 1)
      end
      k = key.poll()
    end
    if frog.r == 1 then
      score = score + 1
      speedUp = speedUp + 0.1
      resetFrog()
    end
    if LANES[frog.r] and carCovers(frog.r, lanesOffset[frog.r], t, frog.c, speedUp) then
      lives = lives - 1
      if lives == 0 then
        draw(t)
        ui.center(60, "game over", 0xff6060, 2)
        gfx.flush()
        while true do
          if key.poll() == "ctrl-q" then return end
          sys.sleep(40)
        end
      end
      resetFrog()
      sys.sleep(300)
    end
    draw(t)
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("frogger: " .. tostring(problem)) end
