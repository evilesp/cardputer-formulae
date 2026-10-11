#!lua
-- sudoku: fill the grid so every row, column and 3 x 3 box has the digits 1 to 9. Move the cursor with w a s d, type a
-- digit (1 to 9) into an empty square, 0 or backspace clears it, c checks what you have (wrong squares turn red),
-- n makes a new puzzle, ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the solver.

-- can digit v go into cell (r, c) of the board
local function canPlace(board, r, c, v)
  for i = 1, 9 do
    if board[r][i] == v or board[i][c] == v then return false end
  end
  local br, bc = (r - 1) // 3 * 3 + 1, (c - 1) // 3 * 3 + 1
  for i = br, br + 2 do
    for j = bc, bc + 2 do
      if board[i][j] == v then return false end
    end
  end
  return true
end

-- fills the empty cells (0) in order; with random = true the digits are tried in a random order. Returns true when done.
local function fill(board, random)
  for r = 1, 9 do
    for c = 1, 9 do
      if board[r][c] == 0 then
        local order = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
        if random then
          for i = 9, 2, -1 do
            local j = math.random(i)
            order[i], order[j] = order[j], order[i]
          end
        end
        for _, v in ipairs(order) do
          if canPlace(board, r, c, v) then
            board[r][c] = v
            if fill(board, random) then return true end
            board[r][c] = 0
          end
        end
        return false
      end
    end
  end
  return true
end

-- a finished grid and a puzzle made from it by clearing about the given number of squares
local function makePuzzle(clear)
  local solution = {}
  for r = 1, 9 do solution[r] = { 0, 0, 0, 0, 0, 0, 0, 0, 0 } end
  fill(solution, true)
  local puzzle = {}
  for r = 1, 9 do
    puzzle[r] = {}
    for c = 1, 9 do puzzle[r][c] = solution[r][c] end
  end
  local left = clear
  while left > 0 do
    local r, c = math.random(9), math.random(9)
    if puzzle[r][c] ~= 0 then
      puzzle[r][c] = 0
      left = left - 1
    end
  end
  return puzzle, solution
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  math.randomseed(5)
  local puzzle, solution = makePuzzle(40)
  local ok = true
  for r = 1, 9 do
    for c = 1, 9 do
      if puzzle[r][c] ~= 0 and puzzle[r][c] ~= solution[r][c] then ok = false end
    end
  end
  check(ok, "the puzzle keeps the digits of its solution")
  local rowSum = 0
  for c = 1, 9 do rowSum = rowSum + solution[1][c] end
  check(rowSum == 45, "a solved row has the digits 1 to 9")
  local empty = 0
  for r = 1, 9 do
    for c = 1, 9 do
      if puzzle[r][c] == 0 then empty = empty + 1 end
    end
  end
  check(empty == 40, "40 squares are empty")
  local board = { { 5, 3, 0, 0, 7, 0, 0, 0, 0 }, { 6, 0, 0, 1, 9, 5, 0, 0, 0 }, { 0, 9, 8, 0, 0, 0, 0, 6, 0 },
                  { 8, 0, 0, 0, 6, 0, 0, 0, 3 }, { 4, 0, 0, 8, 0, 3, 0, 0, 1 }, { 7, 0, 0, 0, 2, 0, 0, 0, 6 },
                  { 0, 6, 0, 0, 0, 0, 2, 8, 0 }, { 0, 0, 0, 4, 1, 9, 0, 0, 5 }, { 0, 0, 0, 0, 8, 0, 0, 7, 9 } }
  check(canPlace(board, 1, 3, 4) and not canPlace(board, 1, 3, 5), "a digit in a row, column or box is refused")
  check(fill(board, false), "the classic example is solved")
  check(board[1][3] == 4 and board[9][9] == 9, "the solved example has the known digits")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("sudoku needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("sudoku: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui")
if not ui then
  print("sudoku: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local CELL = 12
local OX, OY = 8, 8
local puzzle, solution, given
local cur = { r = 1, c = 1 }
local checking, won = false, false

local function newGame()
  puzzle, solution = makePuzzle(42)
  given = {}
  for r = 1, 9 do
    given[r] = {}
    for c = 1, 9 do given[r][c] = puzzle[r][c] ~= 0 end
  end
  cur = { r = 1, c = 1 }
  checking, won = false, false
end

local function solved()
  for r = 1, 9 do
    for c = 1, 9 do
      if puzzle[r][c] ~= solution[r][c] then return false end
    end
  end
  return true
end

local function draw()
  gfx.clear(0x0a0c14)
  for r = 1, 9 do
    for c = 1, 9 do
      local x, y = OX + (c - 1) * CELL + (c - 1) // 3 * 2, OY + (r - 1) * CELL + (r - 1) // 3 * 2
      local bg = ((r - 1) // 3 + (c - 1) // 3) % 2 == 0 and 0x1c2233 or 0x161b2a
      if r == cur.r and c == cur.c then bg = 0x3a5a8a end
      gfx.fill(x, y, CELL - 1, CELL - 1, bg)
      local v = puzzle[r][c]
      if v ~= 0 then
        local color = given[r][c] and 0xe8ecf4 or 0x60c8ff
        if checking and not given[r][c] and v ~= solution[r][c] then color = 0xff5050 end
        ui.center(y + 2, tostring(v), color, 1, x, x + CELL - 1)
      end
    end
  end
  local px = 118
  ui.label(px, 12, "SUDOKU", 0xe8ecf4, 2)
  ui.label(px, 40, "digits 1-9 fill", 0x8a94aa)
  ui.label(px, 50, "0 or backspace clear", 0x8a94aa)
  ui.label(px, 60, "w a s d move", 0x8a94aa)
  ui.label(px, 70, "c check", 0x8a94aa)
  ui.label(px, 80, "n new puzzle", 0x8a94aa)
  ui.label(px, 90, "ctrl-q quit", 0x8a94aa)
  if won then ui.label(px, 110, "SOLVED!", 0x60ff90, 2) end
  gfx.flush()
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if #k == 1 then k = k:lower() end
  if k == "w" then cur.r = math.max(1, cur.r - 1)
  elseif k == "s" then cur.r = math.min(9, cur.r + 1)
  elseif k == "a" then cur.c = math.max(1, cur.c - 1)
  elseif k == "d" then cur.c = math.min(9, cur.c + 1)
  elseif k == "n" then newGame()
  elseif k == "c" then checking = true
  elseif k == "backspace" or k == "0" then
    if not given[cur.r][cur.c] then puzzle[cur.r][cur.c] = 0 end
  elseif k:match("^[1-9]$") and not won then
    if not given[cur.r][cur.c] then
      puzzle[cur.r][cur.c] = tonumber(k)
      if solved() then won = true end
    end
  end
  return true
end

newGame()
local w, h = ui.open()
if not w then
  print("sudoku: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
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
if not ok and not tostring(problem):find("interrupted", 1, true) then print("sudoku: " .. tostring(problem)) end
