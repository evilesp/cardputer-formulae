#!lua
-- chess: you play the white pieces against a simple computer that takes the most valuable piece it can and otherwise
-- moves at random. Move the cursor with w a s d; enter picks up one of your pieces (its moves are shown in blue) and enter
-- on a target square moves it; backspace puts the piece back. Pawns that reach the end become queens. The rules are
-- complete except castling and en passant. ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the move rules.

local VALUE = { P = 1, N = 3, B = 3, R = 5, Q = 9, K = 100 }

local function startBoard()
  local rows = { "rnbqkbnr", "pppppppp", "........", "........", "........", "........", "PPPPPPPP", "RNBQKBNR" }
  local b = {}
  for r = 1, 8 do
    b[r] = {}
    for c = 1, 8 do b[r][c] = rows[r]:sub(c, c) end
  end
  return b
end

local function isWhite(p) return p ~= "." and p:match("%u") ~= nil end
local function isBlack(p) return p ~= "." and p:match("%l") ~= nil end

local KNIGHT = { { -2, -1 }, { -2, 1 }, { -1, -2 }, { -1, 2 }, { 1, -2 }, { 1, 2 }, { 2, -1 }, { 2, 1 } }
local KING = { { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, -1 }, { 0, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 } }
local ROOK_DIRS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
local BISHOP_DIRS = { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }

-- the squares a piece at (r, c) could move to, ignoring whether its own king is left in check. With attackOnly a pawn
-- counts only the squares it attacks (diagonals), empty or not.
local function rawMoves(b, r, c, attackOnly)
  local p = b[r][c]
  local white = isWhite(p)
  local t = p:upper()
  local out = {}
  local function add(tr, tc)
    if tr < 1 or tr > 8 or tc < 1 or tc > 8 then return false end
    local target = b[tr][tc]
    if target == "." then
      out[#out + 1] = { r, c, tr, tc }
      return true
    end
    if (white and isBlack(target)) or (not white and isWhite(target)) then
      out[#out + 1] = { r, c, tr, tc }
    end
    return false
  end
  if t == "P" then
    local dir = white and -1 or 1
    local startRow = white and 7 or 2
    if attackOnly then
      for _, dc in ipairs({ -1, 1 }) do
        if r + dir >= 1 and r + dir <= 8 and c + dc >= 1 and c + dc <= 8 then out[#out + 1] = { r, c, r + dir, c + dc } end
      end
      return out
    end
    if r + dir >= 1 and r + dir <= 8 and b[r + dir][c] == "." then
      out[#out + 1] = { r, c, r + dir, c }
      if r == startRow and b[r + 2 * dir][c] == "." then out[#out + 1] = { r, c, r + 2 * dir, c } end
    end
    for _, dc in ipairs({ -1, 1 }) do
      local tr, tc = r + dir, c + dc
      if tr >= 1 and tr <= 8 and tc >= 1 and tc <= 8 then
        local target = b[tr][tc]
        if target ~= "." and ((white and isBlack(target)) or (not white and isWhite(target))) then
          out[#out + 1] = { r, c, tr, tc }
        end
      end
    end
  elseif t == "N" then
    for _, d in ipairs(KNIGHT) do add(r + d[1], c + d[2]) end
  elseif t == "K" then
    for _, d in ipairs(KING) do add(r + d[1], c + d[2]) end
  else
    local dirs = {}
    if t == "R" or t == "Q" then for _, d in ipairs(ROOK_DIRS) do dirs[#dirs + 1] = d end end
    if t == "B" or t == "Q" then for _, d in ipairs(BISHOP_DIRS) do dirs[#dirs + 1] = d end end
    for _, d in ipairs(dirs) do
      local tr, tc = r + d[1], c + d[2]
      while add(tr, tc) do
        tr, tc = tr + d[1], tc + d[2]
      end
    end
  end
  return out
end

local function findKing(b, white)
  local k = white and "K" or "k"
  for r = 1, 8 do
    for c = 1, 8 do
      if b[r][c] == k then return r, c end
    end
  end
  return nil
end

-- true when a piece of the given colour attacks the square (tr, tc)
local function attacked(b, tr, tc, byWhite)
  for r = 1, 8 do
    for c = 1, 8 do
      local p = b[r][c]
      if p ~= "." and isWhite(p) == byWhite then
        for _, m in ipairs(rawMoves(b, r, c, true)) do
          if m[3] == tr and m[4] == tc then return true end
        end
      end
    end
  end
  return false
end

local function applyMove(b, m)
  local nb = {}
  for r = 1, 8 do nb[r] = { table.unpack(b[r]) } end
  local piece = nb[m[1]][m[2]]
  nb[m[3]][m[4]] = piece
  nb[m[1]][m[2]] = "."
  -- a pawn that reaches the far end becomes a queen
  if piece == "P" and m[3] == 1 then nb[m[3]][m[4]] = "Q" end
  if piece == "p" and m[3] == 8 then nb[m[3]][m[4]] = "q" end
  return nb
end

-- the moves of one side that do not leave its own king in check
local function legalMoves(b, white)
  local out = {}
  for r = 1, 8 do
    for c = 1, 8 do
      local p = b[r][c]
      if p ~= "." and isWhite(p) == white then
        for _, m in ipairs(rawMoves(b, r, c)) do
          local nb = applyMove(b, m)
          local kr, kc = findKing(nb, white)
          if kr and not attacked(nb, kr, kc, not white) then out[#out + 1] = m end
        end
      end
    end
  end
  return out
end

local function inCheck(b, white)
  local kr, kc = findKing(b, white)
  return kr ~= nil and attacked(b, kr, kc, not white)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local b = startBoard()
  check(#legalMoves(b, true) == 20, "white has 20 moves at the start")
  check(#legalMoves(b, false) == 20, "black has 20 moves at the start")
  local e4 = { 7, 5, 5, 5 }
  b = applyMove(b, e4)
  check(b[5][5] == "P" and b[7][5] == ".", "a pawn moves forward")
  local knightMoves = rawMoves(startBoard(), 8, 2)
  check(#knightMoves == 2, "a knight in its corner has two moves")
  local function empty()
    local e = {}
    for r = 1, 8 do e[r] = { ".", ".", ".", ".", ".", ".", ".", "." } end
    return e
  end
  -- stalemate: the black king in the corner is not attacked and has no square to go to
  local stale = empty()
  stale[1][8], stale[3][7], stale[8][5] = "k", "Q", "K"
  check(not inCheck(stale, false) and #legalMoves(stale, false) == 0, "a king with no moves and no check is a stalemate")
  -- checkmate: the queen protected by a pawn attacks the king, which cannot take it or leave
  local mate = empty()
  mate[1][8], mate[2][7], mate[3][6], mate[8][5] = "k", "Q", "P", "K"
  check(inCheck(mate, false) and #legalMoves(mate, false) == 0, "a protected queen next to the king is mate")
  -- a king may take an unprotected queen
  mate[3][6] = "."
  check(inCheck(mate, false) and #legalMoves(mate, false) == 1, "a king can take an unprotected queen")
  -- a pawn promotes to a queen
  local promo = {}
  for r = 1, 8 do promo[r] = { ".", ".", ".", ".", ".", ".", ".", "." } end
  promo[2][4] = "P"
  promo[8][8] = "k"
  promo[8][1] = "K"
  local moved = applyMove(promo, { 2, 4, 1, 4 })
  check(moved[1][4] == "Q", "a pawn that reaches the far end becomes a queen")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("chess needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("chess: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("chess: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local CELL = 15
local OX, OY = 8, 8
local board, cur, sel, targets, over, status, lastMove
local seed = 0

local function newGame()
  board = startBoard()
  cur = { r = 7, c = 5 }
  sel, targets = nil, {}
  over, status = false, "your move: white"
  lastMove = nil
end

local function finishIfOver(whiteToMove)
  local moves = legalMoves(board, whiteToMove)
  if #moves == 0 then
    over = true
    if inCheck(board, whiteToMove) then
      status = whiteToMove and "checkmate: black wins" or "checkmate: you win!"
    else
      status = "stalemate: a draw"
    end
    return true
  end
  return false
end

-- the computer: the most valuable piece it can take, otherwise a random move
local function computerMove()
  local moves = legalMoves(board, false)
  local best, bestScore = nil, -1
  for _, m in ipairs(moves) do
    local target = board[m[3]][m[4]]
    local score = target == "." and 0 or (VALUE[target:upper()] or 0)
    score = score + math.random() * 0.5
    if score > bestScore then best, bestScore = m, score end
  end
  if best then
    board = applyMove(board, best)
    lastMove = best
    status = "computer moved"
  end
  if not finishIfOver(true) then
    if inCheck(board, true) then status = "check! your move" else status = "your move: white" end
  end
end

local function humanMove(m)
  board = applyMove(board, m)
  lastMove = m
  sel, targets = nil, {}
  if finishIfOver(false) then return end
  status = "computer thinks..."
  computerMove()
end

local function pickSquare(r, c)
  if over then return end
  if sel then
    for _, t in ipairs(targets) do
      if t[3] == r and t[4] == c then
        humanMove(t)
        return
      end
    end
    sel, targets = nil, {}
    status = "not a move there"
    return
  end
  local p = board[r][c]
  if isWhite(p) then
    sel = { r, c }
    targets = {}
    for _, m in ipairs(legalMoves(board, true)) do
      if m[1] == r and m[2] == c then targets[#targets + 1] = m end
    end
    if #targets == 0 then status = "that piece cannot move" end
  else
    status = "pick one of your white pieces"
  end
end

local function draw()
  gfx.clear(0x0a0c14)
  for r = 1, 8 do
    for c = 1, 8 do
      local x, y = OX + (c - 1) * CELL, OY + (r - 1) * CELL
      local light = (r + c) % 2 == 0
      local bg = light and 0x6a7080 or 0x2a2e3c
      if lastMove and ((lastMove[1] == r and lastMove[2] == c) or (lastMove[3] == r and lastMove[4] == c)) then
        bg = light and 0x7a7a40 or 0x4a4a28
      end
      if sel and sel[1] == r and sel[2] == c then bg = 0x3a7ac8 end
      for _, t in ipairs(targets) do
        if t[3] == r and t[4] == c then bg = 0x40a0ff end
      end
      if cur.r == r and cur.c == c then bg = 0xe0c040 end
      gfx.fill(x, y, CELL, CELL, bg)
      local p = board[r][c]
      if p ~= "." then
        local color = isWhite(p) and 0xffffff or 0xff7a50  -- the black pieces are orange: dark letters vanish on the dark squares
        ui.center(y + 3, p:upper() == "N" and "N" or p:upper(), color, 1, x, x + CELL - 1)
      end
    end
  end
  ui.label(138, 10, "CHESS", 0xe8ecf4, 2)
  ui.label(138, 38, status, 0xffe060)
  ui.label(138, 60, "w a s d move", 0x8a94aa)
  ui.label(138, 70, "enter pick / move", 0x8a94aa)
  ui.label(138, 80, "backspace cancel", 0x8a94aa)
  ui.label(138, 90, "n new game", 0x8a94aa)
  ui.label(138, 100, "ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if #k == 1 then k = k:lower() end
  if k == "w" then cur.r = math.max(1, cur.r - 1)
  elseif k == "s" then cur.r = math.min(8, cur.r + 1)
  elseif k == "a" then cur.c = math.max(1, cur.c - 1)
  elseif k == "d" then cur.c = math.min(8, cur.c + 1)
  elseif k == "enter" or k == " " then pickSquare(cur.r, cur.c)
  elseif k == "backspace" then
    sel, targets = nil, {}
  elseif k == "n" then newGame()
  end
  return true
end

newGame()
local w, h = ui.open()
if not w then
  print("chess: " .. tostring(h))
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
if not ok and not tostring(problem):find("interrupted", 1, true) then print("chess: " .. tostring(problem)) end
