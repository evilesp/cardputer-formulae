#!lua
-- checkers: English draughts on an 8 x 8 board. You play red at the bottom and move up the board; the bot (or a second player)
-- plays white. Pieces move one square diagonally forward and take by jumping over an enemy piece; a jump is a must, and a piece
-- that can jump again must go on. A piece that reaches the far row becomes a king and may also move backwards. Whoever cannot
-- move loses. w a s d move the cursor, space picks a piece and then a square, u takes back a move against the bot, n starts
-- again, ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the rules and the bot.

local N = 8
-- 0 empty, 1 red man, 2 white man, 3 red king, 4 white king; -1 marks a piece taken in the middle of a jump
local function sideOf(p) return (p == 1 or p == 3) and 1 or ((p == 2 or p == 4) and 2 or 0) end
local function isKing(p) return p == 3 or p == 4 end

local function newBoard()
  local b = {}
  for r = 1, N do
    b[r] = {}
    for c = 1, N do
      local p = 0
      if (r + c) % 2 == 1 then
        if r <= 3 then p = 2 elseif r >= 6 then p = 1 end
      end
      b[r][c] = p
    end
  end
  return b
end

-- the directions a piece may move in: red goes up (row - 1), white goes down; kings both ways
local function dirsOf(p)
  if isKing(p) then return { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } end
  if sideOf(p) == 1 then return { { -1, -1 }, { -1, 1 } } end
  return { { 1, -1 }, { 1, 1 } }
end

local function inside(r, c) return r >= 1 and r <= N and c >= 1 and c <= N end

-- the jumps of the piece at (r, c): a list of moves { from, path (the squares landed on), taken (the pieces jumped) }.
-- The piece leaves its square while it jumps (it may pass over it), the pieces taken stay as -1 until the move is done.
local function jumpsFrom(b, r0, c0)
  local piece = b[r0][c0]
  local me = sideOf(piece)
  local out = {}
  b[r0][c0] = 0
  local function go(r, c, king, path, taken)
    local found = false
    local dirs = king and dirsOf(3) or dirsOf(piece)
    for _, d in ipairs(dirs) do
      local mr, mc, lr, lc = r + d[1], c + d[2], r + 2 * d[1], c + 2 * d[2]
      if inside(lr, lc) and b[lr][lc] == 0 then
        local over = b[mr][mc]
        if over > 0 and sideOf(over) ~= me then
          found = true
          b[mr][mc] = -1
          path[#path + 1] = { lr, lc }
          taken[#taken + 1] = { mr, mc, over }
          local becomesKing = king or (me == 1 and lr == 1) or (me == 2 and lr == N)
          if becomesKing and not king then
            -- a man that reaches the far row stops there
            local p, t = {}, {}
            for i, v in ipairs(path) do p[i] = v end
            for i, v in ipairs(taken) do t[i] = v end
            out[#out + 1] = { from = { r0, c0 }, path = p, taken = t }
          else
            go(lr, lc, king, path, taken)
          end
          table.remove(path)
          table.remove(taken)
          b[mr][mc] = over
        end
      end
    end
    if not found and #path > 0 then
      local p, t = {}, {}
      for i, v in ipairs(path) do p[i] = v end
      for i, v in ipairs(taken) do t[i] = v end
      out[#out + 1] = { from = { r0, c0 }, path = p, taken = t }
    end
  end
  go(r0, c0, isKing(piece), {}, {})
  b[r0][c0] = piece
  return out
end

-- every legal move of a side: the jumps when there are any (a must), else the simple steps
local function legalMoves(b, side)
  local jumps, steps = {}, {}
  for r = 1, N do
    for c = 1, N do
      local p = b[r][c]
      if p > 0 and sideOf(p) == side then
        for _, m in ipairs(jumpsFrom(b, r, c)) do jumps[#jumps + 1] = m end
        if #jumps == 0 then
          for _, d in ipairs(dirsOf(p)) do
            local nr, nc = r + d[1], c + d[2]
            if inside(nr, nc) and b[nr][nc] == 0 then steps[#steps + 1] = { from = { r, c }, path = { { nr, nc } }, taken = {} } end
          end
        end
      end
    end
  end
  if #jumps > 0 then return jumps, true end
  return steps, false
end

-- makes a move and returns what is needed to take it back
local function apply(b, m)
  local fr, fc = m.from[1], m.from[2]
  local piece = b[fr][fc]
  local last = m.path[#m.path]
  b[fr][fc] = 0
  for _, t in ipairs(m.taken) do b[t[1]][t[2]] = 0 end
  local landed = piece
  if piece == 1 and last[1] == 1 then landed = 3 elseif piece == 2 and last[1] == N then landed = 4 end
  b[last[1]][last[2]] = landed
  return { m = m, piece = piece }
end

local function undo(b, u)
  local m = u.m
  local last = m.path[#m.path]
  b[last[1]][last[2]] = 0
  for _, t in ipairs(m.taken) do b[t[1]][t[2]] = t[3] end
  b[m.from[1]][m.from[2]] = u.piece
end

-- the worth of the board for `me`: men 100 and kings 160, a man gains by getting forward, the middle is good, the back row is a guard
local function evaluate(b, me)
  local s = 0
  for r = 1, N do
    for c = 1, N do
      local p = b[r][c]
      if p > 0 then
        local v = isKing(p) and 160 or 100
        if not isKing(p) then
          local adv = sideOf(p) == 1 and (N - r) or (r - 1)
          v = v + adv * 3
          if (sideOf(p) == 1 and r == N) or (sideOf(p) == 2 and r == 1) then v = v + 6 end
        end
        if c >= 3 and c <= 6 and r >= 3 and r <= 6 then v = v + 3 end
        s = s + (sideOf(p) == me and v or -v)
      end
    end
  end
  return s
end

local function search(b, me, depth, alpha, beta)
  local moves = legalMoves(b, me)
  if #moves == 0 then return -100000 - depth end
  if depth == 0 then return evaluate(b, me) end
  local best = -math.huge
  for _, m in ipairs(moves) do
    local u = apply(b, m)
    local v = -search(b, 3 - me, depth - 1, -beta, -alpha)
    undo(b, u)
    if v > best then best = v end
    if v > alpha then alpha = v end
    if alpha >= beta then break end
  end
  return best
end

local DEPTH = { 1, 4, 7 }
local function botMove(b, me, level)
  local moves = legalMoves(b, me)
  if #moves == 0 then return nil end
  local best, bestVal = {}, -math.huge
  for _, m in ipairs(moves) do
    local u = apply(b, m)
    local v = -search(b, 3 - me, DEPTH[level] - 1, -math.huge, math.huge)
    undo(b, u)
    v = v + math.random() * (level == 1 and 60 or 1)
    if v > bestVal then best, bestVal = { m }, v
    elseif v == bestVal then best[#best + 1] = m end
  end
  return best[math.random(#best)]
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local function empty()
    local b = {}
    for r = 1, N do b[r] = {} for c = 1, N do b[r][c] = 0 end end
    return b
  end
  local b = newBoard()
  local m1, mustJump = legalMoves(b, 1)
  local m2 = legalMoves(b, 2)
  check(#m1 == 7 and #m2 == 7 and not mustJump, "seven moves for each side at the start")
  local count1, count2 = 0, 0
  for r = 1, N do for c = 1, N do if b[r][c] == 1 then count1 = count1 + 1 elseif b[r][c] == 2 then count2 = count2 + 1 end end end
  check(count1 == 12 and count2 == 12, "twelve pieces each")
  -- a jump is a must
  b = empty()
  b[5][4], b[4][5], b[6][3] = 1, 2, 1
  local moves, forced = legalMoves(b, 1)
  check(forced and #moves == 1 and moves[1].path[1][1] == 3 and moves[1].path[1][2] == 6, "the only move is the jump")
  -- a double jump must go on
  b = empty()
  b[7][2], b[6][3], b[4][5] = 1, 2, 2
  moves = legalMoves(b, 1)
  check(#moves == 1 and #moves[1].path == 2 and #moves[1].taken == 2, "a double jump is one move")
  local u = apply(b, moves[1])
  check(b[3][6] == 1 and b[6][3] == 0 and b[4][5] == 0 and b[7][2] == 0, "both pieces are taken")
  undo(b, u)
  check(b[7][2] == 1 and b[6][3] == 2 and b[4][5] == 2 and b[3][6] == 0, "undo puts it back")
  -- a man cannot move or jump backwards, a king can
  b = empty()
  b[4][3], b[5][4] = 1, 2
  moves = legalMoves(b, 1)
  check(#moves == 2 and #moves[1].taken == 0 and #moves[2].taken == 0, "a man does not jump backwards: it has two steps")
  b = empty()
  b[4][3], b[5][4] = 3, 2
  moves = legalMoves(b, 1)
  local back = false
  for _, m in ipairs(moves) do if m.path[1][1] == 6 then back = true end end
  check(back, "a king jumps backwards")
  -- promotion
  b = empty()
  b[2][3] = 1
  moves = legalMoves(b, 1)
  apply(b, moves[1])
  check(b[1][2] == 3 or b[1][4] == 3, "a man that reaches the far row becomes a king")
  -- a man that reaches the far row by a jump stops there
  b = empty()
  b[3][4], b[2][3] = 1, 2
  b[2][5] = 2
  b[4][5] = 2
  moves = legalMoves(b, 1)
  check(#moves >= 1 and #moves[1].path == 1, "the jump to the far row ends there")
  -- no moves means a lost game
  b = empty()
  b[8][1] = 2
  b[7][2], b[6][3] = 1, 1
  check(#legalMoves(b, 2) == 0, "a blocked piece has no move")
  -- the bot takes a free piece, and plays a whole game against itself
  b = empty()
  b[5][4], b[4][5], b[8][1] = 1, 2, 2
  local bm = botMove(b, 1, 3)
  check(bm and #bm.taken == 1, "the bot takes the piece")
  b = newBoard()
  local side, plies, good = 1, 0, true
  while plies < 200 do
    local m = botMove(b, side, 1 + plies % 2)
    if not m then break end
    apply(b, m)
    side = 3 - side
    plies = plies + 1
  end
  check(good and plies > 10, "a game between two bots runs (" .. plies .. " moves)")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("checkers needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("checkers: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local CELL = 15
local OX, OY = 6, 7
local board, turn, cur, picked, targets, mode, level, history, over, lastMove, quiet
local score = { 0, 0 }

local function newGame()
  board, turn, cur, picked, targets, history, over, lastMove, quiet = newBoard(), 1, { r = 6, c = 2 }, nil, nil, {}, nil, nil, 0
end

local function drawPiece(r, c, p)
  local x, y = OX + (c - 1) * CELL + CELL // 2, OY + (r - 1) * CELL + CELL // 2
  local red = sideOf(p) == 1
  gfx.disc(x, y + 1, 6, 0x000000)
  gfx.disc(x, y, 6, red and 0xa81818 or 0xc8c8c0)
  gfx.disc(x, y, 4, red and 0xe03838 or 0xf4f4ee)
  if isKing(p) then
    gfx.fill(x - 3, y - 1, 7, 3, 0xffd040)
    gfx.fill(x - 3, y - 3, 1, 2, 0xffd040)
    gfx.fill(x, y - 3, 1, 2, 0xffd040)
    gfx.fill(x + 3, y - 3, 1, 2, 0xffd040)
  end
end

local function draw()
  gfx.clear(0x0c1018)
  gfx.fill(OX - 3, OY - 3, N * CELL + 6, N * CELL + 6, 0x3a2a18)
  for r = 1, N do
    for c = 1, N do
      local x, y = OX + (c - 1) * CELL, OY + (r - 1) * CELL
      gfx.fill(x, y, CELL, CELL, (r + c) % 2 == 1 and 0x4a2e1a or 0xd8c090)
    end
  end
  if lastMove then
    for _, p in ipairs({ lastMove.from, lastMove.path[#lastMove.path] }) do
      gfx.rect(OX + (p[2] - 1) * CELL, OY + (p[1] - 1) * CELL, CELL, CELL, 0xd0a030)
    end
  end
  if targets then
    for _, m in ipairs(targets) do
      local p = m.path[#m.path]
      gfx.disc(OX + (p[2] - 1) * CELL + CELL // 2, OY + (p[1] - 1) * CELL + CELL // 2, 3, 0x60e080)
    end
  end
  for r = 1, N do
    for c = 1, N do
      if board[r][c] > 0 then drawPiece(r, c, board[r][c]) end
    end
  end
  if picked then gfx.rect(OX + (picked.c - 1) * CELL, OY + (picked.r - 1) * CELL, CELL, CELL, 0x60e080) end
  if not over then gfx.rect(OX + (cur.c - 1) * CELL - 1, OY + (cur.r - 1) * CELL - 1, CELL + 2, CELL + 2, 0x40a0ff) end
  local px = OX + N * CELL + 14
  ui.label(px, 4, "CHECKERS", 0xe8ecf4, 2)
  ui.label(px, 24, mode == 1 and ("bot level " .. level) or "two players", 0x8a94aa)
  ui.label(px, 38, "red   " .. score[1], 0xe05050)
  ui.label(px, 48, "white " .. score[2], 0xe8ecf4)
  local status
  if over == "draw" then status = "a draw"
  elseif over then status = (over == 1 and "RED" or "WHITE") .. " wins!"
  elseif mode == 1 and turn == 2 then status = "bot thinks..."
  else
    local _, must = legalMoves(board, turn)
    status = (turn == 1 and "RED" or "WHITE") .. (must and " must jump" or " to play")
  end
  ui.label(px, 64, status, over and 0x60ff90 or 0xe8ecf4)
  ui.label(px, 92, "wasd move", 0x8a94aa)
  ui.label(px, 102, "space pick/go", 0x8a94aa)
  ui.label(px, 112, mode == 1 and "u undo  n new" or "n new", 0x8a94aa)
  ui.label(px, 122, "ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

-- plays a move, then looks at the result: the next side, a win (no move left) or a draw (40 moves without progress)
local function play(m)
  local piece = board[m.from[1]][m.from[2]]
  history[#history + 1] = { m = apply(board, m), board = nil }
  lastMove = m
  quiet = (#m.taken > 0 or not isKing(piece)) and 0 or quiet + 1
  picked, targets = nil, nil
  turn = 3 - turn
  local moves = legalMoves(board, turn)
  if #moves == 0 then
    over = 3 - turn
    score[over] = score[over] + 1
  elseif quiet >= 40 then
    over = "draw"
  end
end

local w, h = ui.open()
if not w then
  print("checkers: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local pick = ui.choose("Checkers", { "Bot: easy", "Bot: normal", "Bot: hard", "Two players" }, { selected = 2 })
  if not pick then return end
  if pick == 4 then mode = 2 else mode, level = 1, pick end
  newGame()
  while true do
    if mode == 1 and turn == 2 and not over then
      draw()
      local m = botMove(board, 2, level)
      if m then play(m) end
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
      elseif k == "n" then newGame()
      elseif k == "u" and mode == 1 and not over and #history >= 2 then
        for _ = 1, 2 do undo(board, table.remove(history).m) end
        turn, picked, targets, lastMove = 1, nil, nil, nil
      elseif (k == " " or k == "enter") and not over and not (mode == 1 and turn == 2) then
        local p = board[cur.r][cur.c]
        if picked then
          local chosen
          for _, m in ipairs(targets) do
            local last = m.path[#m.path]
            if last[1] == cur.r and last[2] == cur.c then chosen = m break end
          end
          if chosen then play(chosen)
          elseif p > 0 and sideOf(p) == turn then picked = nil targets = nil
          else picked, targets = nil, nil end
        end
        if not picked and not over and p > 0 and sideOf(p) == turn then
          local all = legalMoves(board, turn)
          local mine = {}
          for _, m in ipairs(all) do
            if m.from[1] == cur.r and m.from[2] == cur.c then mine[#mine + 1] = m end
          end
          if #mine > 0 then picked, targets = { r = cur.r, c = cur.c }, mine end
        end
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("checkers: " .. tostring(problem)) end
