#!lua
-- mancala: the Kalah game of sowing seeds. Six pits each, four seeds in every pit. Move the cursor
-- with a d, enter (or space) sows the seeds of the pit under it. The seeds go round to the right, into
-- your store on the right, and the last seed in an empty pit of yours takes the seeds opposite.
-- A last seed in your store gives another turn. The side that runs out gives the rest to the other
-- side. The bot looks two moves ahead. n starts a new game, ctrl-q (or q) quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the rules and the bot.

local SOUTH, NORTH = 1, 2 -- you and the bot
local SOUTH_STORE, NORTH_STORE = 7, 14
local CELL = 27
local OX, OY_N, OY_S = 36, 26, 72

-- board: indices 1 to 6 are your pits (left to right), 7 your store, 8 to 13 the bot's pits
-- (8 is opposite your pit 6, 13 opposite pit 1), 14 the bot's store. Pit i is opposite 14 - i.
local function newBoard()
  local b = {}
  for i = 1, 14 do b[i] = 0 end
  for i = 1, 6 do b[i] = 4; b[14 - i] = 4 end
  return b
end

local function sideSum(b, lo, hi)
  local s = 0
  for i = lo, hi do s = s + b[i] end
  return s
end

local function copyInto(dst, src)
  for i = 1, 14 do dst[i] = src[i] end
end

-- sows the seeds of one pit; returns true when the last seed lands in the own store
local function sow(b, pit, side)
  local own = side == SOUTH and SOUTH_STORE or NORTH_STORE
  local opp = side == SOUTH and NORTH_STORE or SOUTH_STORE
  local lo = side == SOUTH and 1 or 8
  local hi = side == SOUTH and 6 or 13
  local seeds, pos = b[pit], pit
  b[pit] = 0
  while seeds > 0 do
    pos = pos % 14 + 1
    if pos ~= opp then
      b[pos] = b[pos] + 1
      seeds = seeds - 1
    end
  end
  if pos == own then return true end
  -- the last seed fell into an empty pit of its own side: it and the seeds opposite go to the store
  if pos >= lo and pos <= hi and b[pos] == 1 and b[14 - pos] > 0 then
    b[own] = b[own] + b[14 - pos] + 1
    b[14 - pos] = 0
    b[pos] = 0
  end
  return false
end

-- when one side has no seeds left, the other side keeps its seeds in its store; returns true at the end
local function settle(b)
  if sideSum(b, 1, 6) == 0 then
    b[NORTH_STORE] = b[NORTH_STORE] + sideSum(b, 8, 13)
    for i = 8, 13 do b[i] = 0 end
    return true
  elseif sideSum(b, 8, 13) == 0 then
    b[SOUTH_STORE] = b[SOUTH_STORE] + sideSum(b, 1, 6)
    for i = 1, 6 do b[i] = 0 end
    return true
  end
  return false
end

-- scratch boards, made once, so the bot's search makes no new tables
local scratchA, scratchB = {}, {}

-- the pit the bot sows: its store gain now, minus the best gain you can make next; a free turn counts a little
local function botMove(b)
  local bestScore, choice, ties = -1000, nil, 0
  for pit = 8, 13 do
    if b[pit] > 0 then
      copyInto(scratchA, b)
      local extra = sow(scratchA, pit, NORTH)
      local score = scratchA[NORTH_STORE] - scratchA[SOUTH_STORE]
      local over = settle(scratchA)
      if extra and not over then
        score = score + 1
      elseif not over then
        local reply = 0
        for p = 1, 6 do
          if scratchA[p] > 0 then
            copyInto(scratchB, scratchA)
            sow(scratchB, p, SOUTH)
            local gain = scratchB[SOUTH_STORE] - scratchA[SOUTH_STORE]
            if gain > reply then reply = gain end
          end
        end
        score = score - reply
      end
      if score > bestScore then
        bestScore, choice, ties = score, pit, 1
      elseif score == bestScore then
        ties = ties + 1
        if math.random(ties) == 1 then choice = pit end
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
  local b = newBoard()
  check(sideSum(b, 1, 6) == 24 and sideSum(b, 8, 13) == 24, "every pit starts with four seeds")
  check(b[7] == 0 and b[14] == 0, "both stores start empty")
  check(sow(b, 6, SOUTH) == false and b[7] == 1 and b[8] == 5 and b[9] == 5 and b[10] == 5,
    "seeds go round to the right into the store and the bot's pits")
  b = newBoard()
  check(sow(b, 2, SOUTH) == false and b[2] == 0 and b[3] == 5 and b[6] == 5 and b[7] == 0,
    "seeds sown from a middle pit stay on your side")
  -- last seed in your store: extra turn
  b = { 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 }
  check(sow(b, 6, SOUTH) == true and b[7] == 1, "the last seed in your store gives another turn")
  -- capture: pit 2 with one seed lands in empty pit 3 and takes the seeds of pit 11 (opposite)
  b = { 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0 }
  check(sow(b, 2, SOUTH) == false and b[3] == 0 and b[11] == 0 and b[7] == 6,
    "a last seed in an empty pit takes the seeds opposite into the store")
  -- the seeds skip the bot's store when you sow
  b = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  b[13] = 9
  -- seeds go 14, 1 to 6, skip 7, then 8 and 9; the last one takes pit 5 opposite 9
  check(sow(b, 13, NORTH) == false and b[7] == 0 and b[8] == 1 and b[1] == 1 and b[6] == 1 and b[14] == 3,
    "the bot's seeds skip your store")
  b = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  b[5] = 2; b[9] = 3
  check(settle(b) == false, "a game with seeds on both sides goes on")
  b = { 0, 0, 0, 0, 0, 0, 3, 1, 2, 0, 0, 0, 0, 4 }
  check(settle(b) == true and b[7] == 3 and b[14] == 7 and b[8] == 0, "the side that runs out lets the other keep its seeds")
  b = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0 }
  check(botMove(b) == 13, "the bot plays the only pit it has")
  b = { 0, 0, 0, 0, 6, 0, 0, 1, 0, 0, 0, 0, 0, 0 }
  check(botMove(b) == 8, "the bot takes a capture")
  b = newBoard()
  local m = botMove(b)
  check(m ~= nil and m >= 8 and m <= 13 and b[m] == 4, "the bot answers a new game")
  check(sideSum(b, 1, 6) == 24 and b[14] == 0, "the bot's search leaves the board as it was")
  math.randomseed(5)
  for _ = 1, 100 do
    local g = newBoard()
    local turn = SOUTH
    local over, guard = false, 0
    while not over and guard < 2000 do
      guard = guard + 1
      local pit, extra
      if turn == SOUTH then
        repeat pit = math.random(6) until g[pit] > 0
        extra = sow(g, pit, SOUTH)
      else
        pit = botMove(g)
        extra = sow(g, pit, NORTH)
      end
      over = settle(g)
      if not extra then turn = turn == SOUTH and NORTH or SOUTH end
    end
    check(over, "a random game ends")
    check(sideSum(g, 1, 14) == 48, "no seed is lost in a game")
  end
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("mancala needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("mancala: " .. tostring(uiErr))
  return
end

local board, cursor, turn, over, status
local wins, losses, draws = 0, 0, 0
local draw -- defined below; botTurn draws while the bot sows an extra turn

local function newGame()
  board = newBoard()
  cursor = 1
  turn = SOUTH
  over = false
  status = "your turn"
end

-- ends the game and counts the result
local function endGame()
  over = true
  if board[SOUTH_STORE] > board[NORTH_STORE] then
    status, wins = "you win " .. board[SOUTH_STORE] .. " to " .. board[NORTH_STORE], wins + 1
  elseif board[SOUTH_STORE] < board[NORTH_STORE] then
    status, losses = "bot wins " .. board[NORTH_STORE] .. " to " .. board[SOUTH_STORE], losses + 1
  else
    status, draws = "a draw", draws + 1
  end
end

-- the bot's turns: it sows until its last seed does not give another turn
local function botTurn()
  repeat
    local pit = botMove(board)
    local extra = sow(board, pit, NORTH)
    if settle(board) then
      endGame()
      return
    end
    if extra then
      status = "bot again"
      draw()
      sys.sleep(500)
    end
  until not extra
  turn = SOUTH
  status = "your turn"
end

-- your move from the pit under the cursor
local function playerMove()
  if board[cursor] == 0 then
    status = "that pit is empty"
    return
  end
  local extra = sow(board, cursor, SOUTH)
  if settle(board) then
    endGame()
    return
  end
  if extra then
    status = "again: your turn"
  else
    turn = NORTH
    status = "bot is thinking"
  end
end

-- draws one pit with its seeds; y is the top edge, the number is shown in the pit
local function drawPit(x, y, n, color)
  gfx.fill(x, y, CELL - 5, 24, 0x1c2233)
  ui.label(x + 6, y + 7, tostring(n), color)
end

function draw()
  gfx.clear(0x0a0c14)
  gfx.fill(6, 20, 22, 80, 0x202a40)
  ui.label(9, 52, tostring(board[NORTH_STORE]), 0xf0a060)
  gfx.fill(212, 20, 22, 80, 0x202a40)
  ui.label(215, 52, tostring(board[SOUTH_STORE]), 0x40c0ff)
  for c = 1, 6 do
    local x = OX + (c - 1) * CELL
    drawPit(x, OY_N, board[14 - c], 0xf0a060)
    drawPit(x, OY_S, board[c], 0x40c0ff)
    if turn == SOUTH and not over and c == cursor then
      gfx.rect(x - 2, OY_S - 2, CELL + 1, 28, 0xf0d060)
    end
  end
  ui.label(4, 4, "bot", 0xf0a060)
  ui.label(210, 4, "you", 0x40c0ff)
  ui.label(62, 4, "you " .. wins .. "  bot " .. losses .. "  draws " .. draws, 0x8a94aa)
  ui.label(10, 106, status, 0x60ff90)
  ui.label(10, 118, "a d move  enter sow", 0x8a94aa)
  ui.label(10, 128, "n new  ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("mancala: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newGame()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" or k == "q" then return end
      if k == "n" then
        newGame()
      elseif over then
        if k == "enter" or k == " " then newGame() end
      elseif turn == SOUTH then
        if k == "a" then cursor = math.max(1, cursor - 1)
        elseif k == "d" then cursor = math.min(6, cursor + 1)
        elseif k == "enter" or k == " " then
          playerMove()
          if turn == NORTH and not over then
            draw()
            sys.sleep(500)
            botTurn()
          end
        end
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("mancala: " .. tostring(problem)) end
