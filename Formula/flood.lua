#!lua
-- flood: a board of six colours. The square in the top-left corner takes the colour you press (1 to 6) and so does
-- every square of the same colour that touches it. Make the whole board one colour in as few moves as you can.
-- Press a digit to fill, n makes a new board, q or ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the fill and the boards.

local W, H = 12, 8
local COLORS = 6
local CELL = 14
local OX, OY = 6, 10
local PALETTE = { 0xe04848, 0x48c060, 0x4880e8, 0xf0d048, 0xc068e8, 0x48d8d8 }

-- a flat list of W*H colour numbers, index = row * W + column + 1 (rows and columns start at 0)
local function newBoard(w, h, colors)
  local g = {}
  for i = 1, w * h do g[i] = math.random(colors) end
  return g
end

-- every square of the board has the same colour
local function isDone(g)
  for i = 2, #g do
    if g[i] ~= g[1] then return false end
  end
  return true
end

-- a list reused by fill, so a move makes no new table
local stack = {}

-- recolours the region that holds square 1 with colour k; returns how many squares changed (0 if nothing to do)
local function fill(g, w, h, k)
  local target = g[1]
  if target == k then return 0 end
  g[1] = k
  stack[1] = 1
  local top = 1
  local changed = 1
  while top > 0 do
    local i = stack[top]
    top = top - 1
    local row = math.floor((i - 1) / w)
    local col = (i - 1) % w
    if col > 0 and g[i - 1] == target then
      g[i - 1] = k
      top = top + 1
      stack[top] = i - 1
      changed = changed + 1
    end
    if col < w - 1 and g[i + 1] == target then
      g[i + 1] = k
      top = top + 1
      stack[top] = i + 1
      changed = changed + 1
    end
    if row > 0 and g[i - w] == target then
      g[i - w] = k
      top = top + 1
      stack[top] = i - w
      changed = changed + 1
    end
    if row < h - 1 and g[i + w] == target then
      g[i + w] = k
      top = top + 1
      stack[top] = i + w
      changed = changed + 1
    end
  end
  return changed
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  -- 3 wide, 2 high:  1 1 2
  --                  2 2 1
  local g = { 1, 1, 2, 2, 2, 1 }
  check(fill(g, 3, 2, 1) == 0, "filling with the colour already there changes nothing")
  check(fill(g, 3, 2, 2) == 2, "the region of colour 1 at the corner is two squares")
  check(g[1] == 2 and g[2] == 2 and g[3] == 2 and g[4] == 2 and g[5] == 2 and g[6] == 1, "only the region changed")
  check(not isDone(g), "the board is not done yet")
  check(fill(g, 3, 2, 1) == 5, "the next fill takes the five squares of colour 2")
  check(isDone(g), "one colour on the whole board is done")
  -- a region that is only joined diagonally is not taken
  local d = { 1, 2, 2, 2, 1, 2, 2, 2, 2 }
  check(fill(d, 3, 3, 3) == 1, "a diagonal square of the same colour is not joined")
  check(d[5] == 1, "the other corner square is left alone")
  -- a row of colour 1 is taken whole, and the row below is not touched
  local e = { 1, 1, 1, 2, 2, 2 }
  check(fill(e, 3, 2, 3) == 3, "the top row of colour 1 is three squares")
  check(e[4] == 2 and e[5] == 2, "the row below stays as it was")
  math.randomseed(7)
  local b = newBoard(W, H, COLORS)
  check(#b == W * H, "a board has one colour for every square")
  local seen = {}
  local okRange = true
  for i = 1, #b do
    if b[i] < 1 or b[i] > COLORS then okRange = false end
    seen[b[i]] = true
  end
  check(okRange, "the colours are 1 to 6")
  local used = 0
  for c = 1, COLORS do
    if seen[c] then used = used + 1 end
  end
  check(used == COLORS, "a random board uses all six colours")
  -- 2 wide, 2 high:  1 2
  --                  3 1
  -- filling 2, then 3, then 1 takes the whole board in three moves
  local f = { 1, 2, 3, 1 }
  check(fill(f, 2, 2, 2) == 1, "the first move takes one square")
  check(fill(f, 2, 2, 3) == 2, "the second move takes two squares")
  check(fill(f, 2, 2, 1) == 3, "the third move takes the last three squares")
  check(isDone(f), "the board is done after three moves")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("flood needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("flood: " .. tostring(uiErr))
  return
end

local grid, moves, won
local function newGame()
  grid = newBoard(W, H, COLORS)
  while isDone(grid) do grid = newBoard(W, H, COLORS) end
  moves, won = 0, false
end

local function draw()
  gfx.clear(0x0a0c14)
  for r = 0, H - 1 do
    for c = 0, W - 1 do
      gfx.fill(OX + c * CELL, OY + r * CELL, CELL - 1, CELL - 1, PALETTE[grid[r * W + c + 1]])
    end
  end
  ui.label(182, 12, "moves", 0x8a94aa)
  ui.label(182, 24, tostring(moves), 0xe8ecf4, 2)
  for k = 1, COLORS do
    local x = 182 + ((k - 1) % 3) * 18
    local y = 58 + math.floor((k - 1) / 3) * 18
    gfx.fill(x, y, 15, 15, PALETTE[k])
    ui.label(x + 4, y + 4, tostring(k), 0x0a0c14)
  end
  if won then ui.label(182, 98, "solved", 0x60ff90) end
  ui.label(182, 110, "1-6 pick", 0x8a94aa)
  ui.label(182, 122, "n new", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("flood: " .. tostring(h))
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
      elseif not won then
        local colour = tonumber(k)
        if colour and colour >= 1 and colour <= COLORS then
          if fill(grid, W, H, colour) > 0 then
            moves = moves + 1
            won = isDone(grid)
          end
        end
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("flood: " .. tostring(problem)) end
