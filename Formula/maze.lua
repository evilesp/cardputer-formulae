#!lua
-- maze: a random maze drawn in pixels. Get from the top-left corner to the exit at the bottom-right. Move with w a s d
-- (one step per press), h shows the way for a moment, n makes a new maze, ctrl-q quits. Needs the graphics and the ui
-- package. Run it with --selftest to check the generator and the solver.

local COLS_M, ROWS_M = 14, 7
local CELL = 16
local OX, OY = 8, 12

-- A cell is one number: the bits of its walls (N = 1, E = 2, S = 4, W = 8, a set bit is a wall standing) and SEEN (16) while
-- the maze is made. One table per cell with four named fields filled the memory of the Cardputer; the numbers take little.
local BIT = { n = 1, e = 2, s = 4, w = 8 }
local SEEN = 16

local function walled(cell, key)
  return (cell & BIT[key]) ~= 0
end

-- a maze: cells[r][c] is the number of its walls, built by a random depth-first walk
local function newMaze(cols, rows)
  local cells = {}
  for r = 1, rows do
    cells[r] = {}
    for c = 1, cols do cells[r][c] = 15 end
  end
  local stack = { 1 * 100 + 1 }  -- a cell is r * 100 + c
  cells[1][1] = cells[1][1] | SEEN
  local dirs = { { -1, 0, "n", "s" }, { 0, 1, "e", "w" }, { 1, 0, "s", "n" }, { 0, -1, "w", "e" } }
  local options = {}  -- one list for every step, emptied in place
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
  return cells
end

-- the shortest way from (r1, c1) to (r2, c2) as a list of cells, or nil
local function solve(cells, rows, cols, r1, c1, r2, c2)
  local prev, queue, head = {}, { { r1, c1 } }, 1
  prev[r1 * 100 + c1] = true
  while head <= #queue do
    local cur = queue[head]
    head = head + 1
    if cur[1] == r2 and cur[2] == c2 then
      local path, r, c = {}, r2, c2
      while not (r == r1 and c == c1) do
        table.insert(path, 1, { r, c })
        local p = prev[r * 100 + c]
        r, c = p[1], p[2]
      end
      table.insert(path, 1, { r1, c1 })
      return path
    end
    local cell = cells[cur[1]][cur[2]]
    local moves = { { -1, 0, "n" }, { 0, 1, "e" }, { 1, 0, "s" }, { 0, -1, "w" } }
    for _, m in ipairs(moves) do
      if not walled(cell, m[3]) then
        local nr, nc = cur[1] + m[1], cur[2] + m[2]
        if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols and not prev[nr * 100 + nc] then
          prev[nr * 100 + nc] = { cur[1], cur[2] }
          queue[#queue + 1] = { nr, nc }
        end
      end
    end
  end
  return nil
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  math.randomseed(3)
  local m = newMaze(COLS_M, ROWS_M)
  -- a perfect maze: every cell is reached from the start, and the passages make a tree (cells - 1 of them)
  local passages = 0
  for r = 1, ROWS_M do
    for c = 1, COLS_M do
      if c < COLS_M and not walled(m[r][c], "e") then passages = passages + 1 end
      if r < ROWS_M and not walled(m[r][c], "s") then passages = passages + 1 end
    end
  end
  check(passages == COLS_M * ROWS_M - 1, "a perfect maze has one passage less than it has cells")
  local path = solve(m, ROWS_M, COLS_M, 1, 1, ROWS_M, COLS_M)
  check(path ~= nil and path[1][1] == 1 and path[#path][1] == ROWS_M and path[#path][2] == COLS_M, "the exit is reachable")
  -- a corridor of three cells in a 2 x 3 grid: every wall stands, then the passages are opened
  local open = {}
  for r = 1, 2 do
    open[r] = {}
    for c = 1, 3 do open[r][c] = 15 end
  end
  local function opened(r, c, key) open[r][c] = open[r][c] & ~BIT[key] end
  opened(1, 1, "e"); opened(1, 2, "w"); opened(1, 2, "e"); opened(1, 3, "w")
  opened(1, 1, "s"); opened(2, 1, "n")
  local short = solve(open, 2, 3, 1, 1, 1, 3)
  check(short ~= nil and #short == 3, "the shortest way along a corridor is three cells")
  check(solve(open, 2, 3, 1, 1, 2, 3) == nil, "a cell walled off is not reached")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("maze needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("maze: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("maze: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local maze, px, py, hintT, path, moves, won

local function newGame()
  maze = newMaze(COLS_M, ROWS_M)
  px, py = 1, 1
  hintT, path, moves, won = 0, nil, 0, false
end

local function cellXY(r, c)
  return OX + (c - 1) * CELL, OY + (r - 1) * CELL
end

local function draw()
  gfx.clear(0x0a0c14)
  for r = 1, ROWS_M do
    for c = 1, COLS_M do
      local x, y = cellXY(r, c)
      local cell = maze[r][c]
      if walled(cell, "n") then gfx.hline(x, x + CELL, y, 0x9aa6c0) end
      if walled(cell, "w") then gfx.vline(x, y, y + CELL, 0x9aa6c0) end
      if r == ROWS_M and c == COLS_M and walled(cell, "s") then gfx.hline(x, x + CELL, y + CELL, 0x9aa6c0) end
      if c == COLS_M and walled(cell, "e") then gfx.vline(x + CELL, y, y + CELL, 0x9aa6c0) end
    end
  end
  if hintT > 0 and path then
    for _, p in ipairs(path) do
      local x, y = cellXY(p[1], p[2])
      gfx.fill(x + 6, y + 6, 4, 4, 0x40a0ff)
    end
  end
  local ex, ey = cellXY(ROWS_M, COLS_M)
  gfx.fill(ex + 4, ey + 4, CELL - 8, CELL - 8, 0x60ff90)
  local x, y = cellXY(py, px)
  gfx.fill(x + 4, y + 4, CELL - 8, CELL - 8, 0xffd040)
  ui.label(4, 2, "MOVES " .. moves, 0xe8ecf4)
  ui.label(W - 110, 2, "w a s d move  h hint", 0x8a94aa)
  if won then
    ui.center(H - 14, "you got out! n for a new maze", 0x60ff90, 1)
  else
    ui.center(H - 14, "n new maze   ctrl-q quit", 0x8a94aa, 1)
  end
  gfx.flush()
end

local function tryMove(dr, dc, wallKey)
  if won or walled(maze[py][px], wallKey) then return end
  px, py = px + dc, py + dr
  moves = moves + 1
  path = nil
  if px == COLS_M and py == ROWS_M then won = true end
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if #k == 1 then k = k:lower() end
  if k == "w" then tryMove(-1, 0, "n")
  elseif k == "d" then tryMove(0, 1, "e")
  elseif k == "s" then tryMove(1, 0, "s")
  elseif k == "a" then tryMove(0, -1, "w")
  elseif k == "h" then
    path = solve(maze, ROWS_M, COLS_M, py, px, ROWS_M, COLS_M)
    hintT = 3
  elseif k == "n" then newGame()
  end
  return true
end

newGame()
local w, h = ui.open()
if not w then
  print("maze: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local last = sys.millis()
  while true do
    local now = sys.millis()
    local dt = (now - last) / 1000
    last = now
    hintT = math.max(0, hintT - dt)
    local k = key.poll()
    while k do
      if not handle(k) then return end
      k = key.poll()
    end
    draw()
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("maze: " .. tostring(problem)) end
