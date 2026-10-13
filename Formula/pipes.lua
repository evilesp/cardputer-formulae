#!lua
-- pipes: the classic screensaver of coloured pipes that grow across the screen, turning now and then, until the
-- screen is full and it starts again. space clears the screen, w and s change the speed, p pauses, q quits.
-- Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the pipe moves.

local W, H = 240, 135
local CELL = 6                          -- one grid cell is 6 x 6 pixels
local COLS, ROWS = W // CELL, H // CELL -- 40 x 22 cells
local THICK = 4                         -- the pipe is 4 pixels wide
local PIPES = 4
local MAX_AGE = 100                     -- a pipe is replaced after this many cells
local BG = 0x04060c
local COLORS = { 0x30e060, 0xff4040, 0x4080ff, 0xffd040, 0xff40ff, 0x40e0e0 }
local DX = { 1, 0, -1, 0 }              -- directions: 0 right, 1 down, 2 left, 3 up
local DY = { 0, 1, 0, -1 }

-- which cells are taken, one bit per cell, packed into 32-bit words to keep the memory small
local occ = {}
for i = 0, (COLS * ROWS - 1) >> 5 do occ[i] = 0 end

local function isOcc(c)
  return (occ[c >> 5] >> (c & 31)) & 1 == 1
end

local function setOcc(c)
  occ[c >> 5] = occ[c >> 5] | (1 << (c & 31))
end

local function clearOcc()
  for i = 0, (COLS * ROWS - 1) >> 5 do occ[i] = 0 end
end

-- the direction the pipe takes next: the wanted one if the cell is free, otherwise the next free turn
local function chooseDir(x, y, pick)
  for k = 0, 3 do
    local nd = (pick + k) % 4
    local nx, ny = x + DX[nd + 1], y + DY[nd + 1]
    if nx >= 0 and nx < COLS and ny >= 0 and ny < ROWS and not isOcc(ny * COLS + nx) then
      return nd
    end
  end
  return nil
end

-- a thick line between the middles of two neighbouring cells
local function segment(x1, y1, x2, y2, col)
  local h = CELL // 2
  local cx1, cy1 = x1 * CELL + h, y1 * CELL + h
  local cx2, cy2 = x2 * CELL + h, y2 * CELL + h
  gfx.fill(math.min(cx1, cx2) - THICK // 2, math.min(cy1, cy2) - THICK // 2,
    math.abs(cx2 - cx1) + THICK, math.abs(cy2 - cy1) + THICK, col)
end

-- put a pipe on a free cell somewhere on the screen; false when no free cell is found
local function startPipe(p)
  for _ = 1, 60 do
    local x, y = math.random(0, COLS - 1), math.random(0, ROWS - 1)
    if not isOcc(y * COLS + x) then
      setOcc(y * COLS + x)
      p.x, p.y, p.d, p.age, p.alive = x, y, math.random(0, 3), 0, true
      p.col = COLORS[math.random(#COLORS)]
      gfx.fill(x * CELL + 1, y * CELL + 1, THICK, THICK, p.col)
      return true
    end
  end
  p.alive = false
  return false
end

-- one cell further; the pipe goes straight most of the time and turns now and then
local function stepPipe(p)
  local pick
  if math.random(1, 100) <= 75 then
    pick = p.d
  elseif math.random(0, 1) == 0 then
    pick = (p.d + 1) % 4
  else
    pick = (p.d + 3) % 4
  end
  local nd = chooseDir(p.x, p.y, pick)
  if not nd then return false end
  local nx, ny = p.x + DX[nd + 1], p.y + DY[nd + 1]
  setOcc(ny * COLS + nx)
  segment(p.x, p.y, nx, ny, p.col)
  p.x, p.y, p.d = nx, ny, nd
  p.age = p.age + 1
  return true
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  clearOcc()
  check(not isOcc(0) and not isOcc(COLS * ROWS - 1), "a cleared grid is free")
  setOcc(0)
  check(isOcc(0) and not isOcc(1), "one cell is taken")
  setOcc(33)
  check(isOcc(33) and not isOcc(32) and isOcc(0), "cells in another word of the bit table")
  clearOcc()
  check(not isOcc(33), "clear frees the cells again")
  check(COLS == 40 and ROWS == 22, "grid size")
  check(chooseDir(5, 5, 0) == 0, "a free cell ahead is taken")
  setOcc(5 * COLS + 6)
  check(chooseDir(5, 5, 0) == 1, "a blocked cell ahead turns down")
  check(chooseDir(0, 0, 2) == 0, "the left edge turns the pipe right")
  clearOcc()
  clearOcc()
  check(chooseDir(0, 0, 0) == 0, "the top left corner can go right")
  setOcc(1)
  check(chooseDir(0, 0, 0) == 1, "a taken cell on the right turns down")
  clearOcc()
  check(DX[2] == 0 and DY[2] == 1 and DX[3] == -1, "direction tables")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("pipes needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("pipes: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local pipes = {}
  for i = 1, PIPES do pipes[i] = { x = 0, y = 0, d = 0, col = COLORS[1], age = 0, alive = false } end

  local function clearAll()
    gfx.clear(BG)
    clearOcc()
    for i = 1, PIPES do startPipe(pipes[i]) end
  end

  local paused, speed, shown = false, 2, sys.millis()
  clearAll()
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      shown = sys.millis()
      if k == "p" then paused = not paused
      elseif k == "w" or k == "up" then speed = math.min(8, speed + 1)
      elseif k == "s" or k == "down" then speed = math.max(1, speed - 1)
      elseif k == " " then clearAll() end
      k = key.poll()
    end
    if not paused then
      for i = 1, PIPES do
        local p = pipes[i]
        for _ = 1, speed do
          if p.alive and p.age < MAX_AGE and not stepPipe(p) then p.alive = false end
          if not p.alive or p.age >= MAX_AGE then
            -- a new pipe; when there is no room left, the screen is cleared first
            if not startPipe(p) then
              clearAll()
              break
            end
          end
        end
      end
    end
    if sys.millis() - shown < 1800 then
      gfx.fill(0, 0, W, 10, BG)
      gfx.text(4, 1, "space p w s q", 0xffffff, 1)
    end
    gfx.flush()
    sys.sleep(20)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("pipes: " .. tostring(problem)) end
