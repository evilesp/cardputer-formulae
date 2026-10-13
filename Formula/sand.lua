#!lua
-- sand: falling sand. Sand piles up, water runs off the piles and fills the low places, stone stays where it is put.
-- Keys: 1 sand, 2 water, 3 stone, 0 eraser; w a s d move the cursor; space pours the material under the cursor,
-- p keeps pouring while it is on, c clears the screen, q quits. Needs the graphics (firmware v0.1.0.13).
-- Run it with --selftest to check the rules.

local W, H = 240, 135
local CELL = 4                          -- one cell is 4 x 4 pixels
local COLS, ROWS = W // CELL, H // CELL -- 60 x 33 cells
local EMPTY, SAND, WATER, STONE = 0, 1, 2, 3
local BG = 0x0a0808
local SAND_COLS = { 0xe8c060, 0xd8a848, 0xc89038 }
local WATER_COLS = { 0x2868e0, 0x3478f0 }
local STONE_COLS = { 0x707880, 0x5c646e }
local HUD_ROWS = 3                      -- the help line covers the top 3 rows (12 pixels)

-- each cell takes two bits (16 cells to a 32-bit word); moved[] has one bit per cell and marks the cells that
-- already changed in this step, so a grain does not move twice in one step
local NWORDS = (COLS * ROWS + 15) // 16
local NMOVED = (COLS * ROWS + 31) // 32
local grid, moved = {}, {}
for i = 0, NWORDS - 1 do grid[i] = 0 end
for i = 0, NMOVED - 1 do moved[i] = 0 end

local paint = nil                       -- draws a cell after it changes; nil in --selftest, when nothing is drawn
local flip = false                      -- the step scans the rows from the other side every other time

local function get(x, y)
  local c = y * COLS + x
  return (grid[c >> 4] >> ((c & 15) * 2)) & 3
end

local function put(x, y, v)
  local c = y * COLS + x
  local w, s = c >> 4, (c & 15) * 2
  grid[w] = (grid[w] & ~(3 << s)) | (v << s)
end

local function inside(x, y)
  return x >= 0 and x < COLS and y >= 0 and y < ROWS
end

local function isMoved(x, y)
  local c = y * COLS + x
  return (moved[c >> 5] >> (c & 31)) & 1 == 1
end

local function markMoved(x, y)
  local c = y * COLS + x
  moved[c >> 5] = moved[c >> 5] | (1 << (c & 31))
end

local function clearGrid()
  for i = 0, NWORDS - 1 do grid[i] = 0 end
end

local function setCell(x, y, v)
  put(x, y, v)
  if paint then paint(x, y) end
end

-- two grains (or a grain and a drop) trade places
local function swap(x1, y1, x2, y2)
  local a, b = get(x1, y1), get(x2, y2)
  put(x1, y1, b)
  put(x2, y2, a)
  markMoved(x1, y1)
  markMoved(x2, y2)
  if paint then
    paint(x1, y1)
    paint(x2, y2)
  end
end

-- sand sinks through empty cells and through water
local function sinksInto(v)
  return v == EMPTY or v == WATER
end

local function stepSand(x, y)
  if not inside(x, y + 1) then return end
  if sinksInto(get(x, y + 1)) then
    swap(x, y, x, y + 1)
    return
  end
  -- a random side first, so the piles are not symmetric
  local d = math.random(0, 1) * 2 - 1
  if inside(x + d, y + 1) and sinksInto(get(x + d, y + 1)) then
    swap(x, y, x + d, y + 1)
    return
  end
  if inside(x - d, y + 1) and sinksInto(get(x - d, y + 1)) then
    swap(x, y, x - d, y + 1)
  end
end

-- water falls into empty cells, then spreads down and to the sides
local function stepWater(x, y)
  if inside(x, y + 1) and get(x, y + 1) == EMPTY then
    swap(x, y, x, y + 1)
    return
  end
  local d = math.random(0, 1) * 2 - 1
  if inside(x + d, y + 1) and get(x + d, y + 1) == EMPTY then
    swap(x, y, x + d, y + 1)
  elseif inside(x - d, y + 1) and get(x - d, y + 1) == EMPTY then
    swap(x, y, x - d, y + 1)
  elseif inside(x + d, y) and get(x + d, y) == EMPTY then
    swap(x, y, x + d, y)
  elseif inside(x - d, y) and get(x - d, y) == EMPTY then
    swap(x, y, x - d, y)
  end
end

-- one step of the simulation: rows from the bottom up, so a grain falls at most one cell per step
local function step()
  for i = 0, NMOVED - 1 do moved[i] = 0 end
  for y = ROWS - 1, 0, -1 do
    for n = 0, COLS - 1 do
      local x = flip and (COLS - 1 - n) or n
      local v = get(x, y)
      if v == SAND and not isMoved(x, y) then
        stepSand(x, y)
      elseif v == WATER and not isMoved(x, y) then
        stepWater(x, y)
      end
    end
  end
  flip = not flip
end

-- pours a 3 x 2 patch of the material at the cursor; sand comes a bit thinner so it looks grainy
local function pour(cx, cy, mat)
  for dy = 0, 1 do
    for dx = -1, 1 do
      local x, y = cx + dx, cy + dy
      if inside(x, y) then
        if mat == EMPTY then
          setCell(x, y, EMPTY)
        elseif get(x, y) == EMPTY and (mat ~= SAND or math.random(1, 3) ~= 1) then
          setCell(x, y, mat)
        end
      end
    end
  end
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  clearGrid()
  check(COLS == 60 and ROWS == 33, "grid size")
  check(get(0, 0) == EMPTY and get(COLS - 1, ROWS - 1) == EMPTY, "a cleared grid is empty")
  put(0, 0, SAND)
  put(15, 0, WATER)
  put(16, 0, STONE)
  put(COLS - 1, ROWS - 1, WATER)
  check(get(0, 0) == SAND and get(15, 0) == WATER and get(16, 0) == STONE, "packed cells keep their values")
  check(get(1, 0) == EMPTY and get(14, 0) == EMPTY and get(COLS - 1, ROWS - 1) == WATER, "neighbours are not changed")
  clearGrid()
  check(get(15, 0) == EMPTY and get(16, 0) == EMPTY, "clear empties the packed cells")

  clearGrid()
  put(5, 5, SAND)
  step()
  check(get(5, 5) == EMPTY and get(5, 6) == SAND, "sand falls one cell per step")
  step()
  check(get(5, 7) == SAND, "sand keeps falling")

  clearGrid()
  put(20, 20, STONE)
  step()
  check(get(20, 20) == STONE, "stone stays put")

  clearGrid()
  put(10, 20, SAND)
  put(10, 21, STONE)
  put(9, 21, STONE)
  put(11, 21, STONE)
  step()
  check(get(10, 20) == SAND, "sand rests on stone")

  clearGrid()
  put(10, 10, WATER)
  put(10, 11, STONE)
  put(9, 11, STONE)
  put(11, 11, STONE)
  step()
  check(get(10, 10) == EMPTY and (get(9, 10) == WATER or get(11, 10) == WATER), "water runs sideways off stone")

  clearGrid()
  put(3, 3, SAND)
  put(3, 4, WATER)
  for x = 2, 4 do put(x, 5, STONE) end
  put(2, 4, STONE)
  put(4, 4, STONE)
  step()
  check(get(3, 4) == SAND and get(3, 3) == WATER, "sand sinks through water")

  clearGrid()
  put(0, ROWS - 1, SAND)
  step()
  check(get(0, ROWS - 1) == SAND, "sand on the floor stays")

  clearGrid()
  put(7, ROWS - 2, WATER)
  step()
  check(get(7, ROWS - 1) == WATER, "water falls to the floor")

  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("sand needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end

-- draws one cell from the grid; the static cells are not drawn again, the screen keeps them
local function drawCell(x, y)
  local v = get(x, y)
  local col = BG
  if v == SAND then
    col = SAND_COLS[(x * 7 + y * 13) % 3 + 1]
  elseif v == WATER then
    col = WATER_COLS[(x + y) % 2 + 1]
  elseif v == STONE then
    col = STONE_COLS[(x * 3 + y) % 2 + 1]
  end
  gfx.fill(x * CELL, y * CELL, CELL, CELL, col)
end

-- a white outline around the cell under the cursor
local function drawCursor(x, y)
  local px, py = x * CELL, y * CELL
  gfx.fill(px, py, CELL, 1, 0xffffff)
  gfx.fill(px, py + CELL - 1, CELL, 1, 0xffffff)
  gfx.fill(px, py, 1, CELL, 0xffffff)
  gfx.fill(px + CELL - 1, py, 1, CELL, 0xffffff)
end

local function drawHud()
  gfx.fill(0, 0, W, HUD_ROWS * CELL, 0x000000)
  gfx.text(4, 2, "sand 1 water 2 stone 3 space p c q", 0xffffff, 1)
end

-- when the help line goes away, the top rows of the grid are drawn again
local function hideHud()
  for y = 0, HUD_ROWS - 1 do
    for x = 0, COLS - 1 do drawCell(x, y) end
  end
end

if not gfx.open() then
  print("sand: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local cx, cy = COLS // 2, ROWS // 2
  local lastX, lastY = cx, cy
  local selected, pouring = SAND, false
  local hudOn, shown = true, sys.millis()

  paint = drawCell
  gfx.clear(BG)

  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      shown = sys.millis()
      hudOn = true
      if k == "w" then cy = math.max(0, cy - 3)
      elseif k == "s" then cy = math.min(ROWS - 1, cy + 3)
      elseif k == "a" then cx = math.max(0, cx - 3)
      elseif k == "d" then cx = math.min(COLS - 1, cx + 3)
      elseif k == "1" then selected = SAND
      elseif k == "2" then selected = WATER
      elseif k == "3" then selected = STONE
      elseif k == "0" then selected = EMPTY
      elseif k == " " then pour(cx, cy, selected)
      elseif k == "p" then pouring = not pouring
      elseif k == "c" then
        clearGrid()
        gfx.clear(BG)
      end
      k = key.poll()
    end
    if pouring then pour(cx, cy, selected) end
    step()
    if hudOn then
      if sys.millis() - shown < 1800 then
        drawHud()
      else
        hudOn = false
        hideHud()
      end
    end
    drawCell(lastX, lastY)
    drawCursor(cx, cy)
    lastX, lastY = cx, cy
    gfx.flush()
    sys.sleep(40)
  end
end)
paint = nil
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("sand: " .. tostring(problem)) end
