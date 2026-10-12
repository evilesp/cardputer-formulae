#!lua
-- reversi: the board game also called Othello. Put a disc so that it closes a line of the other side's discs between it and
-- one of yours: they turn over to your colour. The side with more discs at the end wins. You play black against the bot
-- (three levels) or two players take turns. w a s d move, space or enter puts a disc, h shows the possible moves, n starts
-- again, ctrl-q quits. A side that cannot move passes by itself. Needs the graphics and the ui package.
-- Run it with --selftest to check the rules and the bot.

local N = 8
local EMPTY, BLACK, WHITE = 0, 1, 2
local DIRS = { { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, -1 }, { 0, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 } }

local function newBoard()
  local b = {}
  for r = 1, N do
    b[r] = {}
    for c = 1, N do b[r][c] = EMPTY end
  end
  b[4][4], b[5][5] = WHITE, WHITE
  b[4][5], b[5][4] = BLACK, BLACK
  return b
end

-- the discs a move at (r, c) by `me` turns over, as a list of { r, c } (empty: the move is not allowed)
local function flips(b, r, c, me)
  local out = {}
  if b[r][c] ~= EMPTY then return out end
  local other = 3 - me
  for _, d in ipairs(DIRS) do
    local rr, cc, line = r + d[1], c + d[2], {}
    while rr >= 1 and rr <= N and cc >= 1 and cc <= N and b[rr][cc] == other do
      line[#line + 1] = { rr, cc }
      rr, cc = rr + d[1], cc + d[2]
    end
    if #line > 0 and rr >= 1 and rr <= N and cc >= 1 and cc <= N and b[rr][cc] == me then
      for _, p in ipairs(line) do out[#out + 1] = p end
    end
  end
  return out
end

local function moves(b, me)
  local out = {}
  for r = 1, N do
    for c = 1, N do
      if b[r][c] == EMPTY and #flips(b, r, c, me) > 0 then out[#out + 1] = { r, c } end
    end
  end
  return out
end

-- puts the disc and turns the discs over; returns the list turned, for undoing
local function apply(b, r, c, me)
  local f = flips(b, r, c, me)
  b[r][c] = me
  for _, p in ipairs(f) do b[p[1]][p[2]] = me end
  return f
end

local function undo(b, r, c, f, me)
  b[r][c] = EMPTY
  for _, p in ipairs(f) do b[p[1]][p[2]] = 3 - me end
end

local function count(b)
  local black, white = 0, 0
  for r = 1, N do
    for c = 1, N do
      if b[r][c] == BLACK then black = black + 1 elseif b[r][c] == WHITE then white = white + 1 end
    end
  end
  return black, white
end

-- the worth of each square: corners are strong, the squares next to them weak (they give the corner away)
local WEIGHT = {
  { 100, -20, 10, 5, 5, 10, -20, 100 }, { -20, -50, -2, -2, -2, -2, -50, -20 },
  { 10, -2, 1, 1, 1, 1, -2, 10 }, { 5, -2, 1, 0, 0, 1, -2, 5 }, { 5, -2, 1, 0, 0, 1, -2, 5 },
  { 10, -2, 1, 1, 1, 1, -2, 10 }, { -20, -50, -2, -2, -2, -2, -50, -20 }, { 100, -20, 10, 5, 5, 10, -20, 100 },
}

local function evaluate(b, me)
  local s = 0
  for r = 1, N do
    for c = 1, N do
      local v = b[r][c]
      if v == me then s = s + WEIGHT[r][c] elseif v ~= EMPTY then s = s - WEIGHT[r][c] end
    end
  end
  return s + 4 * (#moves(b, me) - #moves(b, 3 - me))  -- having more choices than the other side helps
end

local function search(b, me, depth, alpha, beta)
  if depth == 0 then return evaluate(b, me) end
  local list = moves(b, me)
  if #list == 0 then
    if #moves(b, 3 - me) == 0 then  -- the game is over: the count decides
      local black, white = count(b)
      local mine = me == BLACK and black or white
      local theirs = me == BLACK and white or black
      return (mine - theirs) * 1000
    end
    return -search(b, 3 - me, depth - 1, -beta, -alpha)  -- a pass
  end
  local best = -math.huge
  for _, m in ipairs(list) do
    local f = apply(b, m[1], m[2], me)
    local v = -search(b, 3 - me, depth - 1, -beta, -alpha)
    undo(b, m[1], m[2], f, me)
    if v > best then best = v end
    if v > alpha then alpha = v end
    if alpha >= beta then break end
  end
  return best
end

-- the bot's move: level 1 takes the most discs now (greedy), levels 2 and 3 look 2 and 3 moves ahead
local function botMove(b, me, level)
  local list = moves(b, me)
  if #list == 0 then return nil end
  local best, bestVal = list[1], -math.huge
  for _, m in ipairs(list) do
    local v
    if level == 1 then
      v = #flips(b, m[1], m[2], me) + math.random() * 2
    else
      local f = apply(b, m[1], m[2], me)
      v = -search(b, 3 - me, level - 1, -math.huge, math.huge)
      undo(b, m[1], m[2], f, me)
    end
    if v > bestVal then best, bestVal = m, v end
  end
  return best
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
  check(#moves(b, BLACK) == 4, "black has four moves at the start")
  check(#flips(b, 3, 4, BLACK) == 1 and #flips(b, 1, 1, BLACK) == 0, "a move turns a disc; a far square is not allowed")
  local f = apply(b, 3, 4, BLACK)
  local black, white = count(b)
  check(black == 4 and white == 1, "after the first move 4 black and 1 white")
  undo(b, 3, 4, f, BLACK)
  black, white = count(b)
  check(black == 2 and white == 2, "undo puts it back")
  -- the bot takes a corner when it can
  b = newBoard()
  for r = 1, N do for c = 1, N do b[r][c] = EMPTY end end
  b[1][2], b[1][3] = BLACK, WHITE
  b[2][2], b[3][3] = BLACK, WHITE
  local m = botMove(b, WHITE, 2)
  check(m and m[1] == 1 and m[2] == 1, "the bot takes the corner")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("reversi needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("reversi: " .. tostring(uiErr))
  return
end

local CELL = 16
local BX, BY = 4, 3
local COLOR = { [BLACK] = 0x202428, [WHITE] = 0xf2f2ee }
local NAME = { [BLACK] = "BLACK", [WHITE] = "WHITE" }
local board, turn, cur, mode, level, hints, over, note

local function newGame()
  board, turn, cur, hints, over, note = newBoard(), BLACK, { r = 3, c = 4 }, false, false, nil
end

local function draw()
  gfx.clear(0x0c1418)
  gfx.fill(BX - 2, BY - 2, N * CELL + 4, N * CELL + 4, 0x3a2a18)
  local legal = {}
  if hints or (mode == 2) then
    for _, m in ipairs(moves(board, turn)) do legal[m[1] * 10 + m[2]] = true end
  end
  for r = 1, N do
    for c = 1, N do
      local x, y = BX + (c - 1) * CELL, BY + (r - 1) * CELL
      gfx.fill(x, y, CELL - 1, CELL - 1, (r + c) % 2 == 0 and 0x1e7a44 or 0x1b6e3d)
      local v = board[r][c]
      if v ~= EMPTY then
        gfx.disc(x + 7, y + 7, 6, v == BLACK and 0x000000 or 0xb8b8b0)
        gfx.disc(x + 7, y + 7, 5, COLOR[v])
        gfx.disc(x + 5, y + 5, 1, v == BLACK and 0x606870 or 0xffffff)
      elseif hints and legal[r * 10 + c] then
        gfx.disc(x + 7, y + 7, 2, 0x8ad8a0)
      end
      if r == cur.r and c == cur.c and not over then gfx.rect(x - 1, y - 1, CELL + 1, CELL + 1, 0xffe060) end
    end
  end
  local black, white = count(board)
  local px = BX + N * CELL + 10
  ui.label(px, 4, "REVERSI", 0xe8ecf4, 2)
  ui.label(px, 26, mode == 1 and ("bot level " .. level) or "two players", 0x8a94aa)
  gfx.disc(px + 4, 44, 4, COLOR[BLACK]); gfx.circle(px + 4, 44, 4, 0x808080)
  ui.label(px + 12, 41, tostring(black), 0xe8ecf4)
  gfx.disc(px + 50, 44, 4, COLOR[WHITE])
  ui.label(px + 58, 41, tostring(white), 0xe8ecf4)
  local status
  if over then
    status = black == white and "a draw" or ((black > white and "BLACK" or "WHITE") .. " wins!")
  elseif mode == 1 and turn == WHITE then
    status = "bot thinks..."
  else
    status = NAME[turn] .. " to play"
  end
  ui.label(px, 58, status, over and 0x60ff90 or 0xe8ecf4)
  if note then ui.label(px, 70, note, 0xffe060) end
  ui.label(px, 92, "wasd move", 0x8a94aa)
  ui.label(px, 102, "space put", 0x8a94aa)
  ui.label(px, 112, "h hints  n new", 0x8a94aa)
  ui.label(px, 122, "ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

-- after a move: the next side plays, or passes when it cannot, or the game ends
local function nextTurn()
  turn = 3 - turn
  note = nil
  if #moves(board, turn) == 0 then
    if #moves(board, 3 - turn) == 0 then
      over = true
    else
      note = NAME[turn] .. " passes"
      turn = 3 - turn
    end
  end
end

local function place(r, c)
  if over or #flips(board, r, c, turn) == 0 then return false end
  apply(board, r, c, turn)
  nextTurn()
  return true
end

local w, h = ui.open()
if not w then
  print("reversi: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local pick = ui.choose("Reversi", { "Bot: easy", "Bot: normal", "Bot: hard", "Two players" })
  if not pick then return end
  if pick == 4 then mode = 2 else mode, level = 1, pick end
  newGame()
  while true do
    if mode == 1 and turn == WHITE and not over then
      draw()
      local m = botMove(board, WHITE, level)
      if m then
        sys.sleep(250)
        place(m[1], m[2])
      end
    end
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      if k == "w" or k == "up" then cur.r = math.max(1, cur.r - 1)
      elseif k == "s" or k == "down" then cur.r = math.min(N, cur.r + 1)
      elseif k == "a" or k == "left" then cur.c = math.max(1, cur.c - 1)
      elseif k == "d" or k == "right" then cur.c = math.min(N, cur.c + 1)
      elseif k == " " or k == "enter" then
        if not (mode == 1 and turn == WHITE) and not place(cur.r, cur.c) and not over then note = "not allowed" end
      elseif k == "h" then hints = not hints
      elseif k == "n" then newGame()
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("reversi: " .. tostring(problem)) end
