#!lua
-- bubbles: shoot coloured bubbles up into the cluster. Aim with a and d, space fires. Three or more bubbles of one colour
-- that touch pop, and bubbles that hang without a link to the top fall off. Every few shots a new row comes down from
-- the top; if a bubble reaches the bottom row, the game is over. n starts again, ctrl-q quits. Needs the graphics and
-- the ui package. Run it with --selftest to check the groups and the falling bubbles.

local COLS, ROWS = 12, 6
local CELL_W, CELL_H = 20, 16
local TOP_Y = 14  -- below the line with the score
local SHOOT_X, SHOOT_Y = 120, 122
local COLOURS = { 0xe04040, 0x40c040, 0x4080ff, 0xf0d040 }

-- the bubbles of one colour that touch the bubble at (r, c), as a list of { r, c }
local function group(grid, rows, cols, r, c)
  local colour = grid[r][c]
  if colour == 0 then return {} end
  local seen, list, stack = {}, {}, { { r, c } }
  seen[r * 100 + c] = true
  while #stack > 0 do
    local cur = table.remove(stack)
    list[#list + 1] = cur
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nr, nc = cur[1] + d[1], cur[2] + d[2]
      if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols and not seen[nr * 100 + nc] and grid[nr][nc] == colour then
        seen[nr * 100 + nc] = true
        stack[#stack + 1] = { nr, nc }
      end
    end
  end
  return list
end

-- the bubbles that are not linked to the top row through other bubbles: they fall off
local function floating(grid, rows, cols)
  local linked = {}
  local stack = {}
  for c = 1, cols do
    if grid[1][c] ~= 0 then
      linked[1 * 100 + c] = true
      stack[#stack + 1] = { 1, c }
    end
  end
  while #stack > 0 do
    local cur = table.remove(stack)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nr, nc = cur[1] + d[1], cur[2] + d[2]
      if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols and not linked[nr * 100 + nc] and grid[nr][nc] ~= 0 then
        linked[nr * 100 + nc] = true
        stack[#stack + 1] = { nr, nc }
      end
    end
  end
  local out = {}
  for r = 1, rows do
    for c = 1, cols do
      if grid[r][c] ~= 0 and not linked[r * 100 + c] then out[#out + 1] = { r, c } end
    end
  end
  return out
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local g = {}
  for r = 1, 3 do
    g[r] = {}
    for c = 1, 4 do g[r][c] = 0 end
  end
  g[1][1], g[1][2], g[2][2] = 1, 1, 1
  g[3][2] = 2
  check(#group(g, 3, 4, 1, 1) == 3, "three touching bubbles of one colour make a group")
  check(#group(g, 3, 4, 3, 2) == 1, "a bubble of another colour is a group of one")
  check(#group(g, 3, 4, 1, 4) == 0, "an empty square has no group")
  check(#floating(g, 3, 4) == 0, "bubbles linked to the top do not fall")
  g[2][2] = 0
  check(#floating(g, 3, 4) == 1, "the bubble under a gap falls off")
  g[1][1] = 0
  check(#floating(g, 3, 4) == 1 and g[1][2] ~= 0, "a bubble in the top row stays, the one below it has no way up and falls")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("bubbles needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("bubbles: " .. tostring(uiErr))
  return
end

local grid, angle, shot, score, shots, over
local function newRow(r)
  grid[r] = {}
  for c = 1, COLS do grid[r][c] = math.random() < 0.8 and math.random(#COLOURS) or 0 end
end

local function newGame()
  grid = {}
  for r = 1, ROWS do newRow(r) end
  for r = ROWS - 2, ROWS do
    for c = 1, COLS do grid[r][c] = 0 end
  end
  angle, shot, score, shots, over = 0, nil, 0, 0, false
end

-- a new row comes down from the top; the others move one row down
local function addRow()
  for r = ROWS, 2, -1 do grid[r] = grid[r - 1] end
  newRow(1)
  for c = 1, COLS do
    if grid[ROWS][c] ~= 0 then over = true end
  end
end

-- the flight of the shot: it moves 3 pixels a step; it stops at the first bubble, or at the top
local function fly()
  local x = SHOOT_X + 0.0
  local y = SHOOT_Y + 0.0
  local dx, dy = math.sin(angle) * 3, -math.cos(angle) * 3
  local lastR, lastC = nil, nil
  for _ = 1, 400 do
    x, y = x + dx, y + dy
    local c = math.floor(x / CELL_W) + 1
    local r = math.floor((y - TOP_Y) / CELL_H) + 1
    if r < 1 then
      return 1, math.max(1, math.min(COLS, c))
    end
    if c < 1 or c > COLS then return nil end
    if grid[r] and grid[r][c] ~= 0 then
      return lastR, lastC
    end
    lastR, lastC = r, c
  end
  return lastR, lastC
end

local function resolve(r, c, colour)
  if not r then return end
  grid[r][c] = colour
  local g = group(grid, ROWS, COLS, r, c)
  if #g >= 3 then
    for _, cell in ipairs(g) do grid[cell[1]][cell[2]] = 0 end
    score = score + 10 * #g
  end
  for _, cell in ipairs(floating(grid, ROWS, COLS)) do
    grid[cell[1]][cell[2]] = 0
    score = score + 5
  end
end

local function draw()
  gfx.clear(0x0a0c14)
  for r = 1, ROWS do
    for c = 1, COLS do
      local colour = grid[r][c]
      if colour ~= 0 then
        local x, y = (c - 1) * CELL_W + CELL_W // 2, TOP_Y + (r - 1) * CELL_H + CELL_H // 2
        gfx.disc(x, y, 7, COLOURS[colour])
      end
    end
  end
  local tx, ty = SHOOT_X + math.sin(angle) * 22, SHOOT_Y - math.cos(angle) * 22
  gfx.line(SHOOT_X, SHOOT_Y, math.floor(tx), math.floor(ty), 0xffffff)
  gfx.disc(SHOOT_X, SHOOT_Y, 6, COLOURS[shots % #COLOURS + 1])
  ui.label(4, 2, "score " .. score, 0xe8ecf4)
  ui.label(150, 2, "rows in " .. (3 - shots % 3), 0x8a94aa)
  if over then ui.center(60, "game over. n starts again", 0xff6060, 1) end
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("bubbles: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newGame()
  while true do
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "n" then newGame()
      elseif not over then
        if k == "a" then angle = math.max(-1.25, angle - 0.1)
        elseif k == "d" then angle = math.min(1.25, angle + 0.1)
        elseif k == " " then
          local r, c = fly()
          resolve(r, c, shots % #COLOURS + 1)
          shots = shots + 1
          if shots % 3 == 0 then addRow() end
        end
      end
      k = key.poll()
    end
    draw()
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("bubbles: " .. tostring(problem)) end
