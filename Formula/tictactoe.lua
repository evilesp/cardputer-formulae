#!lua
-- tictactoe: noughts and crosses against a bot. You are X and move first. The bot plays perfectly
-- (minimax), so it never loses: the best you can do is a draw. Move the cursor with w a s d,
-- enter (or space) places your mark, n starts a new game, ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the rules and the bot.

local CELL = 30
local OX, OY = 16, 14
local EMPTY, PLAYER, BOT = 0, 1, 2

-- the eight lines of three squares that win; squares are numbered 1 to 9, row by row
local LINES = {
  { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },
  { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },
  { 1, 5, 9 }, { 3, 5, 7 },
}

local function newBoard()
  local b = {}
  for i = 1, 9 do b[i] = EMPTY end
  return b
end

-- the mark that has three in a row, or EMPTY when nobody has won
local function winner(b)
  for _, l in ipairs(LINES) do
    local a = b[l[1]]
    if a ~= EMPTY and a == b[l[2]] and a == b[l[3]] then return a end
  end
  return EMPTY
end

local function full(b)
  for i = 1, 9 do
    if b[i] == EMPTY then return false end
  end
  return true
end

-- score for the bot when `turn` is to move: a win counts more when it comes sooner.
-- The board is changed in place and put back, so no tables are made.
local function search(b, turn, depth, alpha, beta)
  local w = winner(b)
  if w == BOT then return 10 - depth end
  if w == PLAYER then return depth - 10 end
  if full(b) then return 0 end
  local best
  if turn == BOT then
    best = -100
    for i = 1, 9 do
      if b[i] == EMPTY then
        b[i] = BOT
        local s = search(b, PLAYER, depth + 1, alpha, beta)
        b[i] = EMPTY
        if s > best then best = s end
        if best > alpha then alpha = best end
        if alpha >= beta then break end
      end
    end
  else
    best = 100
    for i = 1, 9 do
      if b[i] == EMPTY then
        b[i] = PLAYER
        local s = search(b, BOT, depth + 1, alpha, beta)
        b[i] = EMPTY
        if s < best then best = s end
        if best < beta then beta = best end
        if alpha >= beta then break end
      end
    end
  end
  return best
end

-- the square the bot plays: the best one, a random pick among equally good squares
local function botMove(b)
  local bestScore, choice, ties = -100, nil, 0
  for i = 1, 9 do
    if b[i] == EMPTY then
      b[i] = BOT
      local s = search(b, PLAYER, 1, -100, 100)
      b[i] = EMPTY
      if s > bestScore then
        bestScore, choice, ties = s, i, 1
      elseif s == bestScore then
        ties = ties + 1
        if math.random(ties) == 1 then choice = i end
      end
    end
  end
  return choice
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(winner({ 1, 1, 1, 0, 0, 0, 0, 0, 0 }) == PLAYER, "three in the top row win")
  check(winner({ 0, 0, 0, 2, 2, 2, 0, 0, 0 }) == BOT, "three in the middle row win")
  check(winner({ 2, 0, 0, 2, 0, 0, 2, 0, 0 }) == BOT, "three in the left column win")
  check(winner({ 1, 0, 0, 0, 1, 0, 0, 0, 1 }) == PLAYER, "three on the diagonal win")
  check(winner({ 1, 2, 1, 1, 2, 2, 2, 1, 1 }) == EMPTY, "a full board without three in a row is a draw")
  check(full({ 1, 2, 1, 1, 2, 2, 2, 1, 1 }), "a full board is recognised")
  check(botMove({ 2, 2, 0, 1, 1, 0, 0, 0, 0 }) == 3, "the bot takes a win it can make")
  check(botMove({ 1, 1, 0, 2, 0, 0, 0, 0, 0 }) == 3, "the bot blocks a win of the player")
  local b = newBoard()
  check(#b == 9 and b[5] == EMPTY, "a new board is empty")
  local m = botMove(b)
  check(m ~= nil and m >= 1 and m <= 9, "the bot answers an empty board")
  check(b[m] == EMPTY and winner(b) == EMPTY, "the search leaves the board as it was")
  math.randomseed(7)
  local lost = 0
  for _ = 1, 200 do
    local g = newBoard()
    local turn = math.random(2) == 1 and PLAYER or BOT
    while winner(g) == EMPTY and not full(g) do
      local sq
      if turn == PLAYER then
        repeat sq = math.random(9) until g[sq] == EMPTY
      else
        sq = botMove(g)
      end
      g[sq] = turn
      turn = turn == PLAYER and BOT or PLAYER
    end
    if winner(g) == PLAYER then lost = lost + 1 end
  end
  check(lost == 0, "the bot never loses to random moves")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("tictactoe needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("tictactoe: " .. tostring(uiErr))
  return
end

local board, cr, cc, over, status
local wins, losses, draws = 0, 0, 0

local function newGame()
  board = newBoard()
  cr, cc = 2, 2
  over = false
  status = "your turn"
end

-- ends the game when someone has won or the board is full; returns true when it did
local function checkEnd()
  local w = winner(board)
  if w == PLAYER then
    over, status, wins = true, "you win!", wins + 1
  elseif w == BOT then
    over, status, losses = true, "bot wins!", losses + 1
  elseif full(board) then
    over, status, draws = true, "a draw", draws + 1
  else
    return false
  end
  return true
end

-- draws a cross or a ring inside the square whose top-left corner is x, y
local function drawMark(x, y, mark)
  if mark == PLAYER then
    gfx.line(x + 7, y + 7, x + CELL - 7, y + CELL - 7, 0x40c0ff)
    gfx.line(x + 8, y + 7, x + CELL - 6, y + CELL - 7, 0x40c0ff)
    gfx.line(x + CELL - 7, y + 7, x + 7, y + CELL - 7, 0x40c0ff)
    gfx.line(x + CELL - 8, y + 7, x + 6, y + CELL - 7, 0x40c0ff)
  elseif mark == BOT then
    gfx.circle(x + CELL // 2, y + CELL // 2, 9, 0xf0a060, false)
    gfx.circle(x + CELL // 2, y + CELL // 2, 8, 0xf0a060, false)
  end
end

local function draw()
  gfx.clear(0x0a0c14)
  for i = 1, 9 do
    local r, c = (i - 1) // 3 + 1, (i - 1) % 3 + 1
    local x, y = OX + (c - 1) * CELL, OY + (r - 1) * CELL
    gfx.fill(x, y, CELL - 2, CELL - 2, 0x1c2233)
    drawMark(x, y, board[i])
    if r == cr and c == cc then gfx.rect(x - 1, y - 1, CELL, CELL, 0xf0d060) end
  end
  ui.label(124, 12, "TIC-TAC-TOE", 0xe8ecf4)
  ui.label(124, 22, "you X", 0x40c0ff)
  ui.label(124, 32, "bot O", 0xf0a060)
  ui.label(124, 46, "wins " .. wins, 0x8a94aa)
  ui.label(124, 56, "losses " .. losses, 0x8a94aa)
  ui.label(124, 66, "draws " .. draws, 0x8a94aa)
  ui.label(124, 82, status, 0x60ff90)
  ui.label(124, 96, "w a s d move", 0x8a94aa)
  ui.label(124, 106, "enter place", 0x8a94aa)
  ui.label(124, 116, "n new  ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("tictactoe: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newGame()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      local sq = (cr - 1) * 3 + cc
      if k == "n" then
        newGame()
      elseif k == "w" then cr = math.max(1, cr - 1)
      elseif k == "s" then cr = math.min(3, cr + 1)
      elseif k == "a" then cc = math.max(1, cc - 1)
      elseif k == "d" then cc = math.min(3, cc + 1)
      elseif (k == "enter" or k == " ") and over then
        newGame()
      elseif (k == "enter" or k == " ") and board[sq] == EMPTY then
        board[sq] = PLAYER
        if not checkEnd() then
          board[botMove(board)] = BOT
          if not checkEnd() then status = "your turn" end
        end
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("tictactoe: " .. tostring(problem)) end
