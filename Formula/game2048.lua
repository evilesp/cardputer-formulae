#!lua
-- 2048: slide the tiles with w a s d; equal tiles that touch merge into one with double the number. A new tile appears
-- after every move. Reach 2048 to win, or keep going. n starts a new game, ctrl-q quits. Needs the graphics and the ui
-- package. Run it with --selftest to check the rules.

-- slides one line of four numbers towards its start: equal neighbours merge once. Returns the new line and the points.
local function slideLine(line)
  local tiles = {}
  for _, v in ipairs(line) do
    if v ~= 0 then tiles[#tiles + 1] = v end
  end
  local out, points, i = {}, 0, 1
  while i <= #tiles do
    if i < #tiles and tiles[i] == tiles[i + 1] then
      out[#out + 1] = tiles[i] * 2
      points = points + tiles[i] * 2
      i = i + 2
    else
      out[#out + 1] = tiles[i]
      i = i + 1
    end
  end
  while #out < 4 do out[#out + 1] = 0 end
  return out, points
end

-- the board is a 4 x 4 table of rows; a move turns it so every move slides towards the left
local function readLine(board, k, dir)
  local line = {}
  for i = 1, 4 do
    local r, c
    if dir == "h" then r, c = k, i else r, c = i, k end
    line[i] = board[r][c]
  end
  return line
end

local function writeLine(board, k, dir, line)
  for i = 1, 4 do
    local r, c
    if dir == "h" then r, c = k, i else r, c = i, k end
    board[r][c] = line[i]
  end
end

-- moves the board: "a" left, "d" right, "w" up, "s" down. Returns the new board, the points and whether it changed.
local function move(board, key)
  local dir = (key == "a" or key == "d") and "h" or "v"
  local reverse = key == "d" or key == "s"
  local new, points, changed = {}, 0, false
  for r = 1, 4 do new[r] = { 0, 0, 0, 0 } end
  for k = 1, 4 do
    local line = readLine(board, k, dir)
    if reverse then
      local rev = {}
      for i = 1, 4 do rev[i] = line[5 - i] end
      line = rev
    end
    local slid, p = slideLine(line)
    points = points + p
    if reverse then
      local rev = {}
      for i = 1, 4 do rev[i] = slid[5 - i] end
      slid = rev
    end
    writeLine(new, k, dir, slid)
    for i = 1, 4 do
      if readLine(board, k, dir)[i] ~= slid[i] then changed = true end
    end
  end
  return new, points, changed
end

local function freeCells(board)
  local cells = {}
  for r = 1, 4 do
    for c = 1, 4 do
      if board[r][c] == 0 then cells[#cells + 1] = { r, c } end
    end
  end
  return cells
end

local function spawn(board)
  local cells = freeCells(board)
  if #cells == 0 then return false end
  local cell = cells[math.random(#cells)]
  board[cell[1]][cell[2]] = math.random() < 0.9 and 2 or 4
  return true
end

local function newBoard()
  local b = {}
  for r = 1, 4 do b[r] = { 0, 0, 0, 0 } end
  spawn(b)
  spawn(b)
  return b
end

local function canMove(board)
  if #freeCells(board) > 0 then return true end
  for r = 1, 4 do
    for c = 1, 4 do
      if c < 4 and board[r][c] == board[r][c + 1] then return true end
      if r < 4 and board[r][c] == board[r + 1][c] then return true end
    end
  end
  return false
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local function same(a, b)
    for i = 1, 4 do
      if a[i] ~= b[i] then return false end
    end
    return true
  end
  local out, p = slideLine({ 2, 2, 0, 0 })
  check(same(out, { 4, 0, 0, 0 }) and p == 4, "two twos merge into a four")
  out, p = slideLine({ 2, 0, 2, 4 })
  check(same(out, { 4, 4, 0, 0 }) and p == 4, "the first pair merges, the four stays")
  out, p = slideLine({ 4, 4, 4, 4 })
  check(same(out, { 8, 8, 0, 0 }) and p == 16, "two pairs merge once each")
  out, p = slideLine({ 0, 2, 0, 4 })
  check(same(out, { 2, 4, 0, 0 }) and p == 0, "tiles slide together without merging")
  local b = { { 2, 2, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
  local nb, pts, changed = move(b, "a")
  check(same(nb[1], { 4, 0, 0, 0 }) and pts == 4 and changed, "a moves the first row left")
  nb, pts, changed = move(b, "d")
  check(same(nb[1], { 0, 0, 0, 4 }) and changed, "d moves the first row right")
  local packed = { { 2, 4, 8, 16 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
  nb, pts, changed = move(packed, "a")
  check(not changed, "a move that changes nothing is not a move")
  local stuck = { { 2, 4, 2, 4 }, { 4, 2, 4, 2 }, { 2, 4, 2, 4 }, { 4, 2, 4, 2 } }
  check(not canMove(stuck), "a full board with no pairs is over")
  stuck[1][1] = 8
  stuck[2][1] = 8
  check(canMove(stuck), "a pair next to each other means the game goes on")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("2048 needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("2048: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("2048: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local TILE = 26
local ORIGIN_X, ORIGIN_Y = 20, 18
local COLORS = {
  [0] = 0x1a2030, [2] = 0xeee4da, [4] = 0xede0c8, [8] = 0xf2b179, [16] = 0xf59563, [32] = 0xf67c5f,
  [64] = 0xf65e3b, [128] = 0xedcf72, [256] = 0xedcc61, [512] = 0xedc850, [1024] = 0xedc53f, [2048] = 0xedc22e,
}

local board = newBoard()
local score, best, over, won = 0, 0, false, false

local function draw()
  gfx.clear(0x0a0c14)
  gfx.fill(ORIGIN_X - 4, ORIGIN_Y - 4, 4 * TILE + 5, 4 * TILE + 5, 0x3a3f50)
  for r = 1, 4 do
    for c = 1, 4 do
      local v = board[r][c]
      local x, y = ORIGIN_X + (c - 1) * TILE, ORIGIN_Y + (r - 1) * TILE
      gfx.fill(x, y, TILE - 2, TILE - 2, COLORS[v] or 0x3c3a32)
      if v > 0 then
        local s = tostring(v)
        ui.center(y + 9, s, v <= 4 and 0x776e65 or 0xf9f6f2, 1, x, x + TILE - 2)
      end
    end
  end
  local px = 128
  ui.label(px, 22, "SCORE", 0x8a94aa)
  ui.label(px, 32, tostring(score), 0xe8ecf4, 2)
  ui.label(px, 56, "BEST", 0x8a94aa)
  ui.label(px, 66, tostring(best), 0xe8ecf4, 2)
  ui.label(px, 96, "w a s d move", 0x8a94aa)
  ui.label(px, 106, "n new game", 0x8a94aa)
  ui.label(px, 116, "ctrl-q quit", 0x8a94aa)
  if won and not over then ui.center(H - 12, "2048! keep going or n", 0x60ff90, 1) end
  if over then ui.center(H - 12, "no moves left: n for a new game", 0xff6060, 1) end
  gfx.flush()
end

local function newGame()
  board = newBoard()
  score, over, won = 0, false, false
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if #k == 1 then k = k:lower() end
  if k == "n" then
    newGame()
  elseif (k == "a" or k == "d" or k == "w" or k == "s") and not over then
    local nb, points, changed = move(board, k)
    if changed then
      board = nb
      score = score + points
      if score > best then best = score end
      spawn(board)
      for r = 1, 4 do
        for c = 1, 4 do
          if board[r][c] == 2048 then won = true end
        end
      end
      if not canMove(board) then over = true end
    end
  end
  return true
end

local w, h = ui.open()
if not w then
  print("2048: " .. tostring(h))
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
if not ok and not tostring(problem):find("interrupted", 1, true) then print("2048: " .. tostring(problem)) end
