#!lua
-- tetris: stack falling blocks, complete rows to clear them.
-- left/right (or a/d) move, up (or w) rotates, down (or s) drops faster, space drops at once, q quits.

local BW, BH = 10, 14          -- board size in cells (each cell is two characters wide)
local BX, BY = 1, 1            -- top-left corner of the board on screen

local SHAPES = {
  { color = "cyan",    cells = { {0,1},{1,1},{2,1},{3,1} } },        -- I
  { color = "yellow",  cells = { {1,0},{2,0},{1,1},{2,1} } },        -- O
  { color = "magenta", cells = { {1,0},{0,1},{1,1},{2,1} } },        -- T
  { color = "green",   cells = { {1,0},{2,0},{0,1},{1,1} } },        -- S
  { color = "red",     cells = { {0,0},{1,0},{1,1},{2,1} } },        -- Z
  { color = "blue",    cells = { {0,0},{0,1},{1,1},{2,1} } },        -- J
  { color = "white",   cells = { {2,0},{0,1},{1,1},{2,1} } },        -- L
}

-- rotate a piece 90 degrees clockwise inside its bounding box
local function rotate(cells)
  local out = {}
  local maxx = 0
  for _, c in ipairs(cells) do if c[1] > maxx then maxx = c[1] end end
  for _, c in ipairs(cells) do out[#out + 1] = { maxx - c[2], c[1] } end
  return out
end

local board = {}
for y = 1, BH do
  board[y] = {}
end

local score, lines, level = 0, 0, 1
local over = false

local function newPiece(kind)
  local s = SHAPES[kind]
  return { kind = kind, color = s.color, cells = s.cells, x = 3, y = 0 }
end

local function fits(cells, px, py)
  for _, c in ipairs(cells) do
    local x, y = px + c[1], py + c[2] + 1
    if x < 1 or x > BW or y > BH then return false end
    if y >= 1 and board[y][x] then return false end
  end
  return true
end

local current = newPiece(math.random(1, #SHAPES))
local nextKind = math.random(1, #SHAPES)

local function lock()
  for _, c in ipairs(current.cells) do
    local x, y = current.x + c[1], current.y + c[2] + 1
    if y >= 1 then board[y][x] = current.color end
  end
  -- clear full rows
  local cleared = 0
  local y = BH
  while y >= 1 do
    local full = true
    for x = 1, BW do
      if not board[y][x] then full = false break end
    end
    if full then
      -- drop the row and add an empty one on top; rows above move down, so check this index again
      table.remove(board, y)
      local empty = {}
      for x = 1, BW do empty[x] = false end
      table.insert(board, 1, empty)
      cleared = cleared + 1
    else
      y = y - 1
    end
  end
  if cleared > 0 then
    lines = lines + cleared
    score = score + ({ 100, 300, 500, 800 })[cleared] * level
    level = 1 + lines // 10
  end
  current = newPiece(nextKind)
  nextKind = math.random(1, #SHAPES)
  if not fits(current.cells, current.x, current.y) then over = true end
end

local function move(dx)
  if fits(current.cells, current.x + dx, current.y) then current.x = current.x + dx end
end

local function rotateCurrent()
  local r = rotate(current.cells)
  for _, kick in ipairs({ 0, -1, 1 }) do
    if fits(r, current.x + kick, current.y) then
      current.cells = r
      current.x = current.x + kick
      return
    end
  end
end

local function dropOne()
  if fits(current.cells, current.x, current.y) and fits(current.cells, current.x, current.y + 1) then
    current.y = current.y + 1
  else
    lock()
  end
end

local function draw()
  term.clear()
  -- frame around the board
  for y = 0, BH + 1 do
    term.put(BX - 1, BY + y - 1, "|", "dim")
    term.put(BX + 2 * BW, BY + y - 1, "|", "dim")
  end
  term.text(BX - 1, BY + BH, string.rep("=", 2 * BW + 2), "dim")
  for y = 1, BH do
    for x = 1, BW do
      if board[y][x] then
        term.text(BX + 2 * (x - 1), BY + y - 1, "[]", board[y][x])
      end
    end
  end
  if not over then
    for _, c in ipairs(current.cells) do
      local x, y = current.x + c[1], current.y + c[2] + 1
      if y >= 1 then
        term.text(BX + 2 * (x - 1), BY + y - 1, "[]", current.color)
      end
    end
  end
  -- side panel
  term.text(24, 1, "TETRIS", "white")
  term.text(24, 3, "score " .. score, "text")
  term.text(24, 4, "lines " .. lines, "text")
  term.text(24, 5, "level " .. level, "text")
  term.text(24, 7, "next", "dim")
  for _, c in ipairs(SHAPES[nextKind].cells) do
    term.text(24 + 2 * c[1], 8 + c[2], "[]", SHAPES[nextKind].color)
  end
  if over then
    term.text(24, 12, "GAME OVER", "red")
    term.text(24, 13, "q quit", "dim")
  else
    term.text(24, 13, "q quit", "dim")
  end
  term.flush()
end

term.fullscreen(true)
local quit = false
local tick = 0
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then
      quit = true
    elseif not over then
      if k == "left" or k == "a" then move(-1)
      elseif k == "right" or k == "d" then move(1)
      elseif k == "up" or k == "w" then rotateCurrent()
      elseif k == "down" or k == "s" then dropOne()
      elseif k == " " then
        while not over and fits(current.cells, current.x, current.y) and fits(current.cells, current.x, current.y + 1) do
          current.y = current.y + 1
        end
        lock()
      end
    end
    k = key.poll()
  end
  if quit then break end

  if not over then
    tick = tick + 1
    local every = math.max(4, 20 - 2 * level)
    if tick >= every then
      tick = 0
      dropOne()
    end
  end
  draw()
  sys.sleep(40)
end
term.fullscreen(false)
