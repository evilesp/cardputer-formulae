#!lua
-- minesweeper: find the mines. Move with w a s d, space opens a square, f puts a flag on a square you think has a mine.
-- The numbers count the mines around a square. n makes a new board, ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the board, the numbers and the opening of empty squares.

local ROWS, COLS, MINES = 8, 16, 20
local CELL = 12
local OX, OY = 24, 14

-- a board: cells[r][c] = { mine, near, open, flag }
local function newBoard(rows, cols)
  local b = {}
  for r = 1, rows do
    b[r] = {}
    for c = 1, cols do b[r][c] = { mine = false, near = 0, open = false, flag = false } end
  end
  return b
end

local function eachNeighbour(rows, cols, r, c, f)
  for dr = -1, 1 do
    for dc = -1, 1 do
      if not (dr == 0 and dc == 0) then
        local nr, nc = r + dr, c + dc
        if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols then f(nr, nc) end
      end
    end
  end
end

-- puts the mines at random, never on the first square opened (and not on its neighbours when there is room)
local function placeMines(b, rows, cols, mines, safeR, safeC)
  local placed = 0
  while placed < mines do
    local r, c = math.random(rows), math.random(cols)
    local nearSafe = math.abs(r - safeR) <= 1 and math.abs(c - safeC) <= 1
    if not b[r][c].mine and not (nearSafe and rows * cols - 9 > mines) then
      b[r][c].mine = true
      placed = placed + 1
    end
  end
  for r = 1, rows do
    for c = 1, cols do
      local n = 0
      eachNeighbour(rows, cols, r, c, function(nr, nc) if b[nr][nc].mine then n = n + 1 end end)
      b[r][c].near = n
    end
  end
end

-- opens a square; an empty one opens its neighbours too (a flood)
local function open(b, rows, cols, r, c)
  local cell = b[r][c]
  if cell.open or cell.flag then return end
  cell.open = true
  if cell.near == 0 and not cell.mine then
    eachNeighbour(rows, cols, r, c, function(nr, nc) open(b, rows, cols, nr, nc) end)
  end
end

local function won(b, rows, cols)
  for r = 1, rows do
    for c = 1, cols do
      if not b[r][c].mine and not b[r][c].open then return false end
    end
  end
  return true
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  math.randomseed(4)
  local b = newBoard(5, 5)
  b[2][2].mine = true
  b[4][4].mine = true
  for r = 1, 5 do
    for c = 1, 5 do
      local n = 0
      eachNeighbour(5, 5, r, c, function(nr, nc) if b[nr][nc].mine then n = n + 1 end end)
      b[r][c].near = n
    end
  end
  check(b[1][1].near == 1 and b[3][3].near == 2 and b[5][5].near == 1 and b[5][1].near == 0, "the numbers count the mines around")
  open(b, 5, 5, 5, 1)
  check(b[3][3].open and not b[2][2].open, "an empty square opens its neighbours, a mine does not")
  check(not b[1][1].open, "a square with a number is opened by its neighbour, but does not spread")
  check(not won(b, 5, 5), "not won while squares are closed")
  local full = newBoard(4, 4)
  placeMines(full, 4, 4, 3, 1, 1)
  local count = 0
  for r = 1, 4 do
    for c = 1, 4 do if full[r][c].mine then count = count + 1 end end
  end
  check(count == 3, "the right number of mines")
  check(not full[1][1].mine, "the first square is never a mine")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("minesweeper needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("minesweeper: " .. tostring(uiErr))
  return
end

local board, cr, cc, state
local function newGame()
  board = newBoard(ROWS, COLS)
  cr, cc, state = 1, 1, "playing"
  placeMines(board, ROWS, COLS, MINES, cr, cc)
end

local NUMBER_COLOURS = { 0x40c0ff, 0x60e060, 0xff6060, 0x9060ff, 0xff9030, 0x40e0e0, 0xffffff, 0x909090 }

local function draw()
  gfx.clear(0x0a0c14)
  for r = 1, ROWS do
    for c = 1, COLS do
      local x, y = OX + (c - 1) * CELL, OY + (r - 1) * CELL
      local cell = board[r][c]
      local bg = cell.open and 0x1c2233 or 0x3a4a6a
      if cell.open and cell.mine then bg = 0x802020 end
      gfx.fill(x, y, CELL - 1, CELL - 1, bg)
      if r == cr and c == cc then gfx.rect(x - 1, y - 1, CELL + 1, CELL + 1, 0xffe060) end
      if cell.flag and not cell.open then ui.label(x + 3, y + 2, "F", 0xffe060) end
      if cell.open and cell.mine then gfx.disc(x + 5, y + 5, 3, 0xffffff)
      elseif cell.open and cell.near > 0 then ui.label(x + 3, y + 2, tostring(cell.near), NUMBER_COLOURS[cell.near]) end
    end
  end
  local mark = state == "won" and "you found them all!" or (state == "lost" and "boom. n for a new board" or "w a s d  space open  f flag  n new  ctrl-q")
  ui.label(4, 118, mark, state == "won" and 0x60ff90 or 0x8a94aa)
  gfx.flush()
end


local w, h = ui.open()
if not w then
  print("minesweeper: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newGame()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "n" then newGame()
      elseif state == "playing" then
        if k == "w" then cr = math.max(1, cr - 1)
        elseif k == "s" then cr = math.min(ROWS, cr + 1)
        elseif k == "a" then cc = math.max(1, cc - 1)
        elseif k == "d" then cc = math.min(COLS, cc + 1)
        elseif k == "f" then
          if not board[cr][cc].open then board[cr][cc].flag = not board[cr][cc].flag end
        elseif k == " " or k == "enter" then
          if not board[cr][cc].flag then
            if board[cr][cc].mine then
              board[cr][cc].open = true
              state = "lost"
              for r = 1, ROWS do
                for c2 = 1, COLS do if board[r][c2].mine then board[r][c2].open = true end end
              end
            else
              open(board, ROWS, COLS, cr, cc)
              if won(board, ROWS, COLS) then state = "won" end
            end
          end
        end
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("minesweeper: " .. tostring(problem)) end
