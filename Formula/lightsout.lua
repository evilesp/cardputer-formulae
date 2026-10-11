#!lua
-- lightsout: switch off every light. A press on a square changes it and the four squares next to it. Move with w a s d,
-- enter (or space) presses a square, n makes a new puzzle, ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the rules and the puzzles.

local N = 5
local CELL = 18
local OX, OY = 60, 14

local function newGrid(n)
  local g = {}
  for r = 1, n do
    g[r] = {}
    for c = 1, n do g[r][c] = false end
  end
  return g
end

-- presses a square: it and its neighbours change (true is on)
local function press(g, n, r, c)
  local function flip(rr, cc)
    if rr >= 1 and rr <= n and cc >= 1 and cc <= n then g[rr][cc] = not g[rr][cc] end
  end
  flip(r, c)
  flip(r - 1, c)
  flip(r + 1, c)
  flip(r, c - 1)
  flip(r, c + 1)
end

local function allOff(g, n)
  for r = 1, n do
    for c = 1, n do
      if g[r][c] then return false end
    end
  end
  return true
end

-- a puzzle that can be solved: start from all off and press some squares at random
local function puzzle(n, presses)
  local g = newGrid(n)
  for _ = 1, presses do press(g, n, math.random(n), math.random(n)) end
  if allOff(g, n) then press(g, n, 1, 1) end
  return g
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local g = newGrid(3)
  press(g, 3, 2, 2)
  check(g[2][2] and g[1][2] and g[3][2] and g[2][1] and g[2][3] and not g[1][1], "a press changes the square and its four neighbours")
  press(g, 3, 2, 2)
  check(allOff(g, 3), "pressing the same square twice changes nothing")
  press(g, 3, 1, 1)
  check(g[1][1] and g[1][2] and g[2][1] and not g[3][3], "a corner press changes only the squares on the board")
  math.randomseed(12)
  local p = puzzle(N, 9)
  check(not allOff(p, N), "a new puzzle has lights on")
  -- every puzzle is solvable: pressing the same squares again switches everything off
  local q = newGrid(N)
  math.randomseed(12)
  local presses = {}
  for i = 1, 9 do presses[i] = { math.random(N), math.random(N) } end
  for _, pr in ipairs(presses) do press(q, N, pr[1], pr[2]) end
  for _, pr in ipairs(presses) do press(q, N, pr[1], pr[2]) end
  check(allOff(q, N), "the presses that made the puzzle undo it")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("lightsout needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("lightsout: " .. tostring(uiErr))
  return
end

local grid, cr, cc, moves
local function newGame()
  grid = puzzle(N, 14)
  cr, cc, moves = 3, 3, 0
end

local function draw()
  gfx.clear(0x0a0c14)
  for r = 1, N do
    for c = 1, N do
      local x, y = OX + (c - 1) * CELL, OY + (r - 1) * CELL
      local on = grid[r][c]
      gfx.fill(x, y, CELL - 2, CELL - 2, on and 0xf0d060 or 0x1c2233)
      if r == cr and c == cc then gfx.rect(x - 1, y - 1, CELL, CELL, 0x40c0ff) end
    end
  end
  ui.label(8, 12, "moves", 0x8a94aa)
  ui.label(8, 24, tostring(moves), 0xe8ecf4, 2)
  if allOff(grid, N) then ui.label(8, 60, "dark!", 0x60ff90, 2) end
  ui.label(8, 100, "w a s d", 0x8a94aa)
  ui.label(8, 112, "enter press", 0x8a94aa)
  ui.label(150, 100, "n new", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("lightsout: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newGame()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "n" then newGame()
      elseif allOff(grid, N) then
        -- solved: waits for n
      elseif k == "w" then cr = math.max(1, cr - 1)
      elseif k == "s" then cr = math.min(N, cr + 1)
      elseif k == "a" then cc = math.max(1, cc - 1)
      elseif k == "d" then cc = math.min(N, cc + 1)
      elseif k == "enter" or k == " " then
        press(grid, N, cr, cc)
        moves = moves + 1
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("lightsout: " .. tostring(problem)) end
