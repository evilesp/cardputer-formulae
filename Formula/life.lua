#!lua
-- life: Conway's Game of Life on the screen. Arrows move the cursor, space turns a cell on or off, r fills the board at
-- random, c clears it, n makes one generation, p runs or pauses (a generation every 0.3 s), q quits.
-- The edges wrap around, so a glider that leaves the screen comes back from the other side.

local COLS, ROWS = term.size()
local W = COLS
local H = ROWS - 3  -- board rows 1 to H; row 0 is the title and the last two rows are the keys

local function newBoard()
  local b = {}
  for y = 1, H do
    b[y] = {}
    for x = 1, W do b[y][x] = 0 end
  end
  return b
end

local board = newBoard()
local cx, cy = 1, 1  -- the cursor
local generation = 0
local running = false

local function alive(b, x, y)
  return b[(y - 1) % H + 1][(x - 1) % W + 1]
end

local function step()
  local nb = newBoard()
  for y = 1, H do
    for x = 1, W do
      local n = 0
      for dy = -1, 1 do
        for dx = -1, 1 do
          if dx ~= 0 or dy ~= 0 then n = n + alive(board, x + dx, y + dy) end
        end
      end
      local on = board[y][x] == 1
      if n == 3 or (on and n == 2) then nb[y][x] = 1 end
    end
  end
  board = nb
  generation = generation + 1
end

local function population()
  local n = 0
  for y = 1, H do
    for x = 1, W do n = n + board[y][x] end
  end
  return n
end

local function draw()
  term.clear()
  term.text(0, 0, string.format("life   generation %d   alive %d", generation, population()), "green")
  for y = 1, H do
    local line = {}
    for x = 1, W do line[x] = board[y][x] == 1 and "#" or "." end
    term.text(0, y, table.concat(line), "text")
  end
  term.text(cx - 1, cy, board[cy][cx] == 1 and "@" or "+", "cyan")
  term.text(0, ROWS - 2, "arrows move  space toggle  r random", "dim")
  term.text(0, ROWS - 1, "c clear  n step  p run/pause  q quit", "dim")
  term.flush()
end

local function randomFill()
  for y = 1, H do
    for x = 1, W do board[y][x] = math.random() < 0.3 and 1 or 0 end
  end
  generation = 0
end

-- returns false when the player quits
local function handle(k)
  if k == "up" then
    cy = (cy - 2) % H + 1
  elseif k == "down" then
    cy = cy % H + 1
  elseif k == "left" then
    cx = (cx - 2) % W + 1
  elseif k == "right" then
    cx = cx % W + 1
  elseif k == " " then
    board[cy][cx] = 1 - board[cy][cx]
  elseif k == "r" then
    randomFill()
  elseif k == "c" then
    board = newBoard()
    generation = 0
    running = false
  elseif k == "n" then
    step()
  elseif k == "p" then
    running = not running
  elseif k == "q" then
    return false
  end
  return true
end

term.fullscreen(true)
local quit, elapsed = false, 0
while not quit do
  draw()
  local k = key.poll()
  while k do
    if not handle(k) then
      quit = true
      break
    end
    k = key.poll()
  end
  if running then
    elapsed = elapsed + 50
    if elapsed >= 300 then
      step()
      elapsed = 0
    end
  end
  sys.sleep(50)
end
term.fullscreen(false)
