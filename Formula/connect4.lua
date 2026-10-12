#!lua
-- connect4: drop discs into the columns and get four in a row (across, up or slanting) before the other side. Play against
-- the bot (three levels) or two players on one Cardputer. a and d (or the arrows) choose the column, space or enter drops,
-- u takes back the last move against the bot, n starts again, ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the rules and the bot.

local COLS_N, ROWS_N = 7, 6
local EMPTY, RED, YELLOW = 0, 1, 2

-- the board is one list of 42 cells, row 1 at the bottom: cell (r, c) is (r - 1) * 7 + c
local function idx(r, c)
  return (r - 1) * COLS_N + c
end

local function newBoard()
  local b = {}
  for i = 1, COLS_N * ROWS_N do b[i] = EMPTY end
  return b
end

-- the row a disc dropped into column c lands on, or nil when the column is full
local function landingRow(b, c)
  for r = 1, ROWS_N do
    if b[idx(r, c)] == EMPTY then return r end
  end
  return nil
end

-- every line of four on the board, made once: { cell, cell, cell, cell }
local LINES = {}
do
  local dirs = { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }
  for r = 1, ROWS_N do
    for c = 1, COLS_N do
      for _, d in ipairs(dirs) do
        local r4, c4 = r + 3 * d[1], c + 3 * d[2]
        if r4 >= 1 and r4 <= ROWS_N and c4 >= 1 and c4 <= COLS_N then
          LINES[#LINES + 1] = { idx(r, c), idx(r + d[1], c + d[2]), idx(r + 2 * d[1], c + 2 * d[2]), idx(r4, c4) }
        end
      end
    end
  end
end

-- the winner and its four cells, or nil
local function winner(b)
  for _, l in ipairs(LINES) do
    local v = b[l[1]]
    if v ~= EMPTY and b[l[2]] == v and b[l[3]] == v and b[l[4]] == v then return v, l end
  end
  return nil
end

local function full(b)
  for c = 1, COLS_N do
    if b[idx(ROWS_N, c)] == EMPTY then return false end
  end
  return true
end

-- how good the board is for `me`: lines with three or two of mine and nothing of the other side count, the middle
-- column counts a little
local function score(b, me)
  local other = 3 - me
  local s = 0
  for _, l in ipairs(LINES) do
    local mine, theirs = 0, 0
    for k = 1, 4 do
      local v = b[l[k]]
      if v == me then mine = mine + 1 elseif v == other then theirs = theirs + 1 end
    end
    if theirs == 0 then
      if mine == 3 then s = s + 5 elseif mine == 2 then s = s + 2 end
    elseif mine == 0 then
      if theirs == 3 then s = s - 4 elseif theirs == 2 then s = s - 1 end
    end
  end
  for r = 1, ROWS_N do
    local v = b[idx(r, 4)]
    if v == me then s = s + 3 elseif v == other then s = s - 3 end
  end
  return s
end

local ORDER = { 4, 3, 5, 2, 6, 1, 7 }  -- the middle first: the search cuts more

-- negamax with alpha-beta: the value of the board for `me` to move, looking `depth` moves ahead
local function search(b, me, depth, alpha, beta)
  local w = winner(b)
  if w then return w == me and 100000 + depth or -100000 - depth end
  if depth == 0 or full(b) then return score(b, me) end
  local best = -math.huge
  for _, c in ipairs(ORDER) do
    local r = landingRow(b, c)
    if r then
      local i = idx(r, c)
      b[i] = me
      local v = -search(b, 3 - me, depth - 1, -beta, -alpha)
      b[i] = EMPTY
      if v > best then best = v end
      if v > alpha then alpha = v end
      if alpha >= beta then break end
    end
  end
  return best
end

-- the column the bot plays. Level 1 looks 2 moves ahead and sometimes plays at random, level 3 looks 5 ahead.
local DEPTH = { 2, 4, 5 }  -- 6 took seconds a move on the Cardputer
local function botMove(b, me, level)
  if level == 1 and math.random() < 0.3 then
    local free = {}
    for c = 1, COLS_N do if landingRow(b, c) then free[#free + 1] = c end end
    return free[math.random(#free)]
  end
  local bestCol, bestVal = nil, -math.huge
  for _, c in ipairs(ORDER) do
    local r = landingRow(b, c)
    if r then
      local i = idx(r, c)
      b[i] = me
      local v = -search(b, 3 - me, DEPTH[level] - 1, -math.huge, math.huge)
      b[i] = EMPTY
      if v > bestVal then bestCol, bestVal = c, v end
    end
  end
  return bestCol
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(#LINES == 69, "a board of 7 x 6 has 69 lines of four")
  local b = newBoard()
  check(landingRow(b, 1) == 1, "a disc lands at the bottom")
  for c = 1, 4 do b[idx(1, c)] = RED end
  check(winner(b) == RED, "four across win")
  b = newBoard()
  for r = 1, 4 do b[idx(r, 2)] = YELLOW end
  check(winner(b) == YELLOW, "four up win")
  b = newBoard()
  for k = 1, 4 do b[idx(k, k)] = RED end
  check(winner(b) == RED, "four slanting win")
  b = newBoard()
  for r = 1, ROWS_N do b[idx(r, 3)] = (r % 2) + 1 end
  check(landingRow(b, 3) == nil, "a full column takes no disc")
  -- the bot wins at once when it can, and blocks a three of the other side
  b = newBoard()
  for c = 1, 3 do b[idx(1, c)] = YELLOW end
  check(botMove(b, YELLOW, 2) == 4, "the bot takes a win")
  b = newBoard()
  for c = 1, 3 do b[idx(1, c)] = RED end
  b[idx(2, 1)], b[idx(2, 2)] = YELLOW, YELLOW
  check(botMove(b, YELLOW, 2) == 4, "the bot blocks four")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("connect4 needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("connect4: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local CELL = 17
local BX, BY = 6, 14  -- the top-left corner of the board
local COLOR = { [RED] = 0xe84848, [YELLOW] = 0xf0c830 }
local NAME = { [RED] = "RED", [YELLOW] = "YELLOW" }

local board, turn, cursor, mode, level, history, won, winLine, drop
local wins = { [RED] = 0, [YELLOW] = 0 }

local function newGame()
  board, turn, cursor, history, won, winLine, drop = newBoard(), RED, 4, {}, nil, nil, nil
end

local function cellXY(r, c)
  return BX + (c - 1) * CELL + CELL // 2, BY + (ROWS_N - r) * CELL + CELL // 2 + 6
end

local function disc(x, y, color)
  gfx.disc(x, y, CELL // 2 - 2, ui.shade(color, 0.6))
  gfx.disc(x, y, CELL // 2 - 3, color)
  gfx.disc(x - 2, y - 2, 2, ui.shade(color, 1.4))
end

local function draw(note)
  gfx.clear(0x0c1020)
  -- the frame of the board with its holes
  gfx.fill(BX - 2, BY + 4, COLS_N * CELL + 4, ROWS_N * CELL + 4, 0x2448a8)
  for r = 1, ROWS_N do
    for c = 1, COLS_N do
      local x, y = cellXY(r, c)
      local v = board[idx(r, c)]
      if v == EMPTY then
        gfx.disc(x, y, CELL // 2 - 3, 0x0c1020)
      else
        disc(x, y, COLOR[v])
      end
    end
  end
  if drop then disc(drop.x, drop.y, COLOR[drop.who]) end
  if winLine then
    for _, i in ipairs(winLine) do
      local r, c = (i - 1) // COLS_N + 1, (i - 1) % COLS_N + 1
      local x, y = cellXY(r, c)
      gfx.circle(x, y, CELL // 2 - 1, 0xffffff)
    end
  end
  if not won and not drop then  -- the disc over the column, waiting
    local x = BX + (cursor - 1) * CELL + CELL // 2
    disc(x, BY - 2, COLOR[turn])
  end
  -- the side panel
  local px = BX + COLS_N * CELL + 10
  ui.label(px, 4, "CONNECT 4", 0xe8ecf4, 1)
  ui.label(px, 18, mode == 1 and ("bot level " .. level) or "two players", 0x8a94aa)
  ui.label(px, 34, "RED    " .. wins[RED], COLOR[RED])
  ui.label(px, 44, "YELLOW " .. wins[YELLOW], COLOR[YELLOW])
  local status
  if won == "draw" then status = "a draw"
  elseif won then status = NAME[won] .. " wins!"
  elseif mode == 1 and turn == YELLOW then status = "bot thinks..."
  else status = NAME[turn] .. " to play" end
  ui.label(px, 62, note or status, won and 0x60ff90 or 0xe8ecf4)
  ui.label(px, 92, "a d  column", 0x8a94aa)
  ui.label(px, 102, "space drop", 0x8a94aa)
  ui.label(px, 112, mode == 1 and "u undo  n new" or "n new", 0x8a94aa)
  ui.label(px, 122, "ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

-- the disc falls to its place (a short animation), then the turn passes
local function play(c)
  local r = landingRow(board, c)
  if not r or won then return false end
  local x, yEnd = cellXY(r, c)
  local y = BY - 2
  drop = { x = x, y = y, who = turn }
  while drop.y < yEnd do
    drop.y = math.min(yEnd, drop.y + 9)
    draw()
    sys.sleep(15)
  end
  drop = nil
  board[idx(r, c)] = turn
  history[#history + 1] = idx(r, c)
  local w, line = winner(board)
  if w then
    won, winLine = w, line
    wins[w] = wins[w] + 1
  elseif full(board) then
    won = "draw"
  else
    turn = 3 - turn
  end
  return true
end

local function chooseMode()
  local pick = ui.choose("Connect 4", { "Bot: easy", "Bot: normal", "Bot: hard", "Two players" })
  if not pick then return false end
  if pick == 4 then mode = 2 else mode, level = 1, pick end
  return true
end

local w, h = ui.open()
if not w then
  print("connect4: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  if not chooseMode() then return end
  newGame()
  while true do
    if mode == 1 and turn == YELLOW and not won then
      draw()
      play(botMove(board, YELLOW, level))
    end
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      if k == "a" or k == "left" then cursor = math.max(1, cursor - 1)
      elseif k == "d" or k == "right" then cursor = math.min(COLS_N, cursor + 1)
      elseif (k == " " or k == "enter" or k == "s" or k == "down") and not won then play(cursor)
      elseif k == "n" then newGame()
      elseif k == "u" and mode == 1 and not won and #history >= 2 then
        for _ = 1, 2 do board[table.remove(history)] = EMPTY end
      elseif k:match("^[1-7]$") and not won then
        cursor = tonumber(k)
        play(cursor)
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("connect4: " .. tostring(problem)) end
