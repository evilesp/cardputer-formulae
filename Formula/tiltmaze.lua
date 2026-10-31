#!lua
-- tiltmaze: a ball rolls through a maze. Tilt the Cardputer to roll it (the motion sensor): tilt right to roll right, tilt
-- away from you to roll down. Without the sensor, the keys a d w s push it. Get the ball to the exit at the bottom-right
-- corner. n makes a new maze, r starts this maze again, ctrl-q quits. Needs the graphics, the ui package and a motion
-- sensor (the ADV board). Run it with --selftest to check the maze and the walls.

local COLS, ROWS = 12, 7
local LINE_Y = 128          -- the line of text at the bottom
local CELL = 18
local OX, OY = 12, 4
local R = 3.5               -- the radius of the ball in pixels
local PUSH = 260            -- pixels per second squared for a full tilt (1 g)
local FRICTION = 1.6        -- per second

-- a cell is a number of wall bits: N = 1, E = 2, S = 4, W = 8, and SEEN = 16 while the maze is made
local BIT = { n = 1, e = 2, s = 4, w = 8 }
local SEEN = 16

local function walled(cell, key)
  return (cell & BIT[key]) ~= 0
end

-- a maze by a random depth first walk
local function newMaze(cols, rows)
  local cells = {}
  for r = 1, rows do
    cells[r] = {}
    for c = 1, cols do cells[r][c] = 15 end
  end
  local stack = { 101 }
  cells[1][1] = cells[1][1] | SEEN
  local dirs = { { -1, 0, "n", "s" }, { 0, 1, "e", "w" }, { 1, 0, "s", "n" }, { 0, -1, "w", "e" } }
  local options = {}
  while #stack > 0 do
    local cur = stack[#stack]
    local r0, c0 = cur // 100, cur % 100
    for i = #options, 1, -1 do options[i] = nil end
    for _, d in ipairs(dirs) do
      local nr, nc = r0 + d[1], c0 + d[2]
      if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols and (cells[nr][nc] & SEEN) == 0 then options[#options + 1] = d end
    end
    if #options == 0 then
      table.remove(stack)
    else
      local d = options[math.random(#options)]
      local nr, nc = r0 + d[1], c0 + d[2]
      cells[r0][c0] = cells[r0][c0] & ~BIT[d[3]]
      cells[nr][nc] = (cells[nr][nc] & ~BIT[d[4]]) | SEEN
      stack[#stack + 1] = nr * 100 + nc
    end
  end
  for r = 1, rows do
    for c = 1, cols do cells[r][c] = cells[r][c] & 15 end
  end
  return cells
end

-- the distance from a point to a wall segment (vertical at x from y0 to y1, or horizontal at y from x0 to x1)
local function distVertical(px, py, x, y0, y1)
  local dy = py < y0 and y0 - py or (py > y1 and py - y1 or 0)
  return math.sqrt((px - x) * (px - x) + dy * dy)
end

local function distHorizontal(px, py, y, x0, x1)
  local dx = px < x0 and x0 - px or (px > x1 and px - x1 or 0)
  return math.sqrt((py - y) * (py - y) + dx * dx)
end

-- true when the ball at (x, y) touches a wall of the cell it is in (or is outside the maze, except through the exit)
local function blocked(maze, x, y)
  local c = math.floor((x - OX) / CELL) + 1
  local r = math.floor((y - OY) / CELL) + 1
  if c < 1 or c > COLS or r < 1 or r > ROWS then return true end
  local cell = maze[r][c]
  local x0, y0 = OX + (c - 1) * CELL, OY + (r - 1) * CELL
  local x1, y1 = x0 + CELL, y0 + CELL
  if walled(cell, "n") and distHorizontal(x, y, y0, x0, x1) < R then return true end
  if walled(cell, "s") and distHorizontal(x, y, y1, x0, x1) < R then return true end
  if walled(cell, "w") and distVertical(x, y, x0, y0, y1) < R then return true end
  if walled(cell, "e") and distVertical(x, y, x1, y0, y1) < R then return true end
  return false
end

-- the exit is the open bottom side of the bottom-right cell
local function atExit(x, y)
  local ex = OX + (COLS - 1) * CELL + CELL / 2
  return math.abs(x - ex) < CELL / 2 - R and y > OY + ROWS * CELL - R
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  math.randomseed(9)
  local m = newMaze(COLS, ROWS)
  local passages = 0
  for r = 1, ROWS do
    for c = 1, COLS do
      if c < COLS and not walled(m[r][c], "e") then passages = passages + 1 end
      if r < ROWS and not walled(m[r][c], "s") then passages = passages + 1 end
    end
  end
  check(passages == COLS * ROWS - 1, "a perfect maze has one passage less than it has cells")
  check(m[1][1] & SEEN == 0 and m[1][1] <= 15, "the walls are in the low four bits")
  -- a ball in the middle of a cell with no walls is free; next to a wall it is blocked
  local open = {}
  for r = 1, 1 do
    open[r] = {}
    for c = 1, 2 do open[r][c] = 0 end
  end
  check(not blocked(open, OX + 9, OY + 9), "a ball in the middle of an open cell is free")
  open[1][1] = BIT.e
  check(blocked(open, OX + CELL - 1, OY + 9), "a ball next to a wall is blocked")
  check(blocked(open, OX - 5, OY + 9), "outside the maze is blocked")
  check(atExit(OX + (COLS - 1) * CELL + CELL / 2, OY + ROWS * CELL + 2), "the exit is open at the bottom right")
  check(not atExit(OX + 10, OY + 10), "the top left is not the exit")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("tiltmaze needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("tiltmaze: " .. tostring(uiErr))
  return
end

local maze, bx, by, vx, vy, seconds, won
local function newGame(sameMaze)
  if not sameMaze then maze = newMaze(COLS, ROWS) end
  bx, by = OX + CELL / 2, OY + CELL / 2
  vx, vy, seconds, won = 0, 0, 0, false
end

local function draw()
  gfx.clear(0x0a0c14)
  for r = 1, ROWS do
    for c = 1, COLS do
      local x0, y0 = OX + (c - 1) * CELL, OY + (r - 1) * CELL
      local cell = maze[r][c]
      if walled(cell, "n") then gfx.hline(x0, x0 + CELL, y0, 0x9aa6c0) end
      if walled(cell, "w") then gfx.vline(x0, y0, y0 + CELL, 0x9aa6c0) end
      if r == ROWS and walled(cell, "s") then gfx.hline(x0, x0 + CELL, y0 + CELL, 0x9aa6c0) end
      if c == COLS and walled(cell, "e") then gfx.vline(x0 + CELL, y0, y0 + CELL, 0x9aa6c0) end
    end
  end
  local ex = OX + (COLS - 1) * CELL + CELL / 2
  gfx.fill(ex - 4, OY + ROWS * CELL - 2, 8, 4, 0x60ff90)
  gfx.disc(math.floor(bx + 0.5), math.floor(by + 0.5), math.floor(R), 0xffd040)
  ui.label(4, 2, "time " .. math.floor(seconds) .. " s", 0xe8ecf4)
  if won then
    ui.center(LINE_Y, "you got out! n for a new maze", 0x60ff90, 1)
  else
    ui.center(LINE_Y, "tilt to roll   n new maze   r again   ctrl-q", 0x8a94aa, 1)
  end
  gfx.flush()
end

local function step(dt, ax, ay)
  vx = vx + ax * PUSH * dt
  vy = vy + ay * PUSH * dt
  local damp = math.max(0, 1 - FRICTION * dt)
  vx, vy = vx * damp, vy * damp
  local nx = bx + vx * dt
  if blocked(maze, nx, by) then
    vx = 0
  else
    bx = nx
  end
  local ny = by + vy * dt
  if blocked(maze, bx, ny) then
    vy = 0
  else
    by = ny
  end
  if atExit(bx, by) then won = true end
end

local w, h = ui.open()
if not w then
  print("tiltmaze: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newGame(false)
  local last = sys.millis()
  while true do
    local now = sys.millis()
    local dt = math.min((now - last) / 1000, 0.05)
    last = now
    local ax, ay = 0, 0
    if sys.imu then
      local x, y = sys.imu()
      -- the sensor reads a tilt to the right as negative: the ball rolls the way the Cardputer is tilted
      if x then ax, ay = math.max(-1, math.min(1, -x)), math.max(-1, math.min(1, y)) end
    end
    local held = key.down and key.down() or {}
    for _, k in ipairs(held) do
      if k == "a" then ax = ax - 1 end
      if k == "d" then ax = ax + 1 end
      if k == "w" then ay = ay - 1 end
      if k == "s" then ay = ay + 1 end
    end
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "n" then newGame(false) end
      if k == "r" then newGame(true) end
      k = key.poll()
    end
    if not won then
      step(dt, ax, ay)
      seconds = seconds + dt
    end
    draw()
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("tiltmaze: " .. tostring(problem)) end
