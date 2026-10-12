#!lua
-- gomoku: five in a row. Black and white take turns putting a stone on a 15 x 15 board; the first to get five in a row (across,
-- up or slanting) wins. Play against the bot (three levels) or two players. w a s d move the cursor, space puts a stone, u takes
-- back your last move against the bot, n starts again, ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the rules and the bot.

local N = 15
local EMPTY, BLACK, WHITE = 0, 1, 2
local DIRS = { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }

local function newBoard()
  local b = {}
  for r = 1, N do
    b[r] = {}
    for c = 1, N do b[r][c] = EMPTY end
  end
  return b
end

-- the length of the line through (r, c) in direction d for `who`, and how many ends of it are open (0, 1 or 2)
local function lineAt(b, r, c, d, who)
  local len, open = 1, 0
  for sign = -1, 1, 2 do
    local rr, cc = r + sign * d[1], c + sign * d[2]
    while rr >= 1 and rr <= N and cc >= 1 and cc <= N and b[rr][cc] == who do
      len = len + 1
      rr, cc = rr + sign * d[1], cc + sign * d[2]
    end
    if rr >= 1 and rr <= N and cc >= 1 and cc <= N and b[rr][cc] == EMPTY then open = open + 1 end
  end
  return len, open
end

-- true when the stone at (r, c) makes five or more
local function wins(b, r, c)
  local who = b[r][c]
  for _, d in ipairs(DIRS) do
    if lineAt(b, r, c, d, who) >= 5 then return true end
  end
  return false
end

local function boardFull(b)
  for r = 1, N do for c = 1, N do if b[r][c] == EMPTY then return false end end end
  return true
end

-- how much a stone of `who` at (r, c) is worth: lines it would make (five, open four, four, open three, ...)
local function worth(b, r, c, who)
  local s = 0
  b[r][c] = who
  for _, d in ipairs(DIRS) do
    local len, open = lineAt(b, r, c, d, who)
    if len >= 5 then s = s + 100000
    elseif len == 4 then s = s + (open == 2 and 10000 or (open == 1 and 1000 or 0))
    elseif len == 3 then s = s + (open == 2 and 1000 or (open == 1 and 100 or 0))
    elseif len == 2 then s = s + (open == 2 and 100 or (open == 1 and 10 or 0)) end
  end
  b[r][c] = EMPTY
  return s
end

-- squares near stones are the only ones worth looking at
local function candidates(b)
  local out, seen, any = {}, {}, false
  for r = 1, N do
    for c = 1, N do
      if b[r][c] ~= EMPTY then
        any = true
        for dr = -2, 2 do
          for dc = -2, 2 do
            local rr, cc = r + dr, c + dc
            if rr >= 1 and rr <= N and cc >= 1 and cc <= N and b[rr][cc] == EMPTY and not seen[rr * 100 + cc] then
              seen[rr * 100 + cc] = true
              out[#out + 1] = { rr, cc }
            end
          end
        end
      end
    end
  end
  if not any then out[1] = { N // 2 + 1, N // 2 + 1 } end
  return out
end

-- the bot's move. Level 1 plays its own line and blocks only an open four; level 2 values blocking as much as attacking;
-- level 3 also looks at the best reply of the other side to each of its top moves.
local function botMove(b, me, level)
  local other = 3 - me
  local list = candidates(b)
  local scored = {}
  for _, p in ipairs(list) do
    local mine = worth(b, p[1], p[2], me)
    local theirs = worth(b, p[1], p[2], other)
    local s
    if level == 1 then
      s = mine + (theirs >= 10000 and theirs or theirs * 0.2) + math.random() * 30
    else
      s = mine * 1.05 + theirs + math.random() * 5
    end
    scored[#scored + 1] = { p[1], p[2], s }
  end
  table.sort(scored, function(a, b2) return a[3] > b2[3] end)
  if level == 3 then
    -- of the best few moves choose the one after which the other side's best answer is the weakest
    local bestMove, bestVal = scored[1], -math.huge
    for i = 1, math.min(6, #scored) do
      local m = scored[i]
      b[m[1]][m[2]] = me
      local reply = 0
      if wins(b, m[1], m[2]) then
        reply = -1e9
      else
        for _, p in ipairs(candidates(b)) do
          local v = worth(b, p[1], p[2], other)
          if v > reply then reply = v end
        end
      end
      b[m[1]][m[2]] = EMPTY
      local v = m[3] - reply * 0.6
      if v > bestVal then bestMove, bestVal = m, v end
    end
    return bestMove[1], bestMove[2]
  end
  return scored[1][1], scored[1][2]
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
  for c = 3, 7 do b[8][c] = BLACK end
  check(wins(b, 8, 5), "five across win")
  b = newBoard()
  for i = 0, 3 do b[3 + i][3 + i] = WHITE end
  check(not wins(b, 4, 4), "four are not enough")
  b[7][7] = WHITE
  check(wins(b, 5, 5), "five slanting win")
  b = newBoard()
  for r = 2, 6 do b[r][10] = BLACK end
  check(wins(b, 4, 10), "five up win")
  b = newBoard()
  for i = 0, 4 do b[2 + i][12 - i] = WHITE end
  check(wins(b, 4, 10), "five on the other slant win")
  local len, open = lineAt(b, 4, 10, { 1, -1 }, WHITE)
  check(len == 5 and open == 2, "a line of five and its open ends")
  -- the bot takes a win, blocks a four, and plays in the middle first
  b = newBoard()
  for c = 3, 6 do b[8][c] = WHITE end
  local r, c = botMove(b, WHITE, 2)
  check(r == 8 and (c == 2 or c == 7), "the bot completes five")
  b = newBoard()
  for c = 3, 6 do b[8][c] = BLACK end
  b[9][5], b[9][6] = WHITE, WHITE
  for level = 1, 3 do
    r, c = botMove(b, WHITE, level)
    check(r == 8 and (c == 2 or c == 7), "level " .. level .. " blocks an open four")
  end
  r, c = botMove(newBoard(), BLACK, 3)
  check(r == 8 and c == 8, "the first stone goes to the middle")
  -- a game of bot against bot ends with a win or a full board and never plays on a stone
  local good = true
  b = newBoard()
  local who, moves, ended = BLACK, 0, false
  while moves < 225 and not ended do
    local rr, cc = botMove(b, who, 1 + moves % 2)
    if b[rr][cc] ~= EMPTY then good = false break end
    b[rr][cc] = who
    moves = moves + 1
    if wins(b, rr, cc) then ended = true end
    who = 3 - who
  end
  check(good and (ended or boardFull(b)), "a game between two bots ends (" .. moves .. " stones)")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("gomoku needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("gomoku: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local CELL = 8
local OX, OY = 10, 10
local board, turn, cur, mode, level, history, over, winLine
local score = { [BLACK] = 0, [WHITE] = 0 }

local function newGame()
  board, turn, cur, history, over, winLine = newBoard(), BLACK, { r = 8, c = 8 }, {}, nil, nil
end

-- the grain of the wooden board, made once: a line every row with its own shade
local GRAIN = {}
for i = 0, 140 do
  local wave = math.sin(i * 0.37) * 0.5 + math.sin(i * 1.7) * 0.3 + math.sin(i * 0.11) * 0.6
  GRAIN[i] = wave
end
local function wood(i)
  local v = GRAIN[i % 141] or 0
  local r = math.floor(206 + v * 14)
  local g = math.floor(160 + v * 12)
  local b = math.floor(92 + v * 10)
  return (r << 16) | (g << 8) | b
end

-- a stone: a shadow on the board, a body shaded from the edge to the middle, and a gloss up on the left
local function stoneAt(r, c, who, last)
  local x, y = OX + (c - 1) * CELL, OY + (r - 1) * CELL
  gfx.disc(x + 1, y + 1, 4, 0x7a5a30)  -- the shadow
  if who == BLACK then
    gfx.disc(x, y, 4, 0x08090c)
    gfx.disc(x - 1, y - 1, 3, 0x1c2026)
    gfx.disc(x - 1, y - 1, 2, 0x2a3038)
    gfx.pixel(x - 2, y - 2, 0x8a94a8)
    gfx.pixel(x - 1, y - 2, 0x56606e)
  else
    gfx.disc(x, y, 4, 0xa8a49a)
    gfx.disc(x, y, 3, 0xdcd8cc)
    gfx.disc(x - 1, y - 1, 2, 0xf4f2ea)
    gfx.pixel(x - 2, y - 2, 0xffffff)
    gfx.pixel(x - 1, y - 2, 0xffffff)
  end
  if last then gfx.disc(x, y, 1, 0xe84030) end
end

local function draw()
  gfx.clear(0x0c1018)
  local size = (N - 1) * CELL
  -- the board: a darker frame with a bevel, then wood with its grain
  local bx, by, bw, bh = OX - 7, OY - 7, size + 14, size + 14
  gfx.fill(bx - 2, by - 2, bw + 4, bh + 4, 0x4a2c12)
  for y = by, by + bh - 1 do gfx.hline(bx, bx + bw - 1, y, wood(y * 3 + (y // 7))) end
  for i = 0, 12 do  -- darker knots of the grain running across
    local gy = by + 4 + i * 9 + math.floor(GRAIN[i * 11 % 141] * 3)
    gfx.hline(bx + 2, bx + bw - 3, gy, 0xc49a60)
  end
  gfx.hline(bx, bx + bw - 1, by, 0xe8c48a)
  gfx.vline(bx, by, by + bh - 1, 0xe8c48a)
  gfx.hline(bx, bx + bw - 1, by + bh - 1, 0x8a5e2a)
  gfx.vline(bx + bw - 1, by, by + bh - 1, 0x8a5e2a)
  for i = 0, N - 1 do
    gfx.hline(OX, OX + size, OY + i * CELL, 0x4a3016)
    gfx.vline(OX + i * CELL, OY, OY + size, 0x4a3016)
  end
  for _, p in ipairs({ { 4, 4 }, { 4, 12 }, { 8, 8 }, { 12, 4 }, { 12, 12 } }) do gfx.disc(OX + (p[2] - 1) * CELL, OY + (p[1] - 1) * CELL, 1, 0x2a1808) end
  -- where the cursor is, a faint stone of the side to play
  if not over and board[cur.r][cur.c] == EMPTY and not (mode == 1 and turn == WHITE) then
    local x, y = OX + (cur.c - 1) * CELL, OY + (cur.r - 1) * CELL
    gfx.circle(x, y, 3, turn == BLACK and 0x2a2018 or 0xf8f0e0)
  end
  local lastIdx = history[#history]
  for r = 1, N do
    for c = 1, N do
      local v = board[r][c]
      if v ~= EMPTY then stoneAt(r, c, v, lastIdx and lastIdx[1] == r and lastIdx[2] == c) end
    end
  end
  if winLine then
    for _, p in ipairs(winLine) do gfx.circle(OX + (p[2] - 1) * CELL, OY + (p[1] - 1) * CELL, 5, 0x40ff80) end
  end
  if not over then  -- the cursor: four corners, so the stone under it stays visible
    local x, y = OX + (cur.c - 1) * CELL, OY + (cur.r - 1) * CELL
    for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
      gfx.hline(x + d[1] * 5, x + d[1] * 3, y + d[2] * 5, 0x2080ff)
      gfx.vline(x + d[1] * 5, y + d[2] * 5, y + d[2] * 3, 0x2080ff)
    end
  end
  local px = OX + size + 14
  ui.label(px, 4, "GOMOKU", 0xe8ecf4, 2)
  ui.label(px, 24, mode == 1 and ("bot level " .. level) or "two players", 0x8a94aa)
  ui.label(px, 40, "black " .. score[BLACK], 0xe8ecf4)
  ui.label(px, 50, "white " .. score[WHITE], 0xe8ecf4)
  local status
  if over == "draw" then status = "a draw"
  elseif over then status = (over == BLACK and "BLACK" or "WHITE") .. " wins!"
  elseif mode == 1 and turn == WHITE then status = "bot thinks..."
  else status = (turn == BLACK and "BLACK" or "WHITE") .. " to play" end
  ui.label(px, 68, status, over and 0x60ff90 or 0xe8ecf4)
  ui.label(px, 92, "wasd move", 0x8a94aa)
  ui.label(px, 102, "space stone", 0x8a94aa)
  ui.label(px, 112, mode == 1 and "u undo n new" or "n new", 0x8a94aa)
  ui.label(px, 122, "ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local function put(r, c)
  if over or board[r][c] ~= EMPTY then return false end
  board[r][c] = turn
  history[#history + 1] = { r, c }
  if wins(board, r, c) then
    over = turn
    score[turn] = score[turn] + 1
    winLine = {}
    for _, d in ipairs(DIRS) do
      local len = lineAt(board, r, c, d, turn)
      if len >= 5 then
        winLine = { { r, c } }
        for sign = -1, 1, 2 do
          local rr, cc = r + sign * d[1], c + sign * d[2]
          while rr >= 1 and rr <= N and cc >= 1 and cc <= N and board[rr][cc] == turn do
            winLine[#winLine + 1] = { rr, cc }
            rr, cc = rr + sign * d[1], cc + sign * d[2]
          end
        end
        break
      end
    end
  elseif boardFull(board) then
    over = "draw"
  else
    turn = 3 - turn
  end
  return true
end

local w, h = ui.open()
if not w then
  print("gomoku: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local pick = ui.choose("Gomoku", { "Bot: easy", "Bot: normal", "Bot: hard", "Two players" }, { selected = 2 })
  if not pick then return end
  if pick == 4 then mode = 2 else mode, level = 1, pick end
  newGame()
  while true do
    if mode == 1 and turn == WHITE and not over then
      draw()
      local r, c = botMove(board, WHITE, level)
      put(r, c)
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
      elseif k == " " or k == "enter" then put(cur.r, cur.c)
      elseif k == "n" then newGame()
      elseif k == "u" and mode == 1 and not over and #history >= 2 then
        for _ = 1, 2 do
          local last = table.remove(history)
          board[last[1]][last[2]] = EMPTY
        end
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("gomoku: " .. tostring(problem)) end
