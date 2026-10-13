#!lua
-- langton: Langton's ant, a tiny rule that grows a complex pattern. The ant starts in the middle of a dark grid facing
-- up. On a dark cell it turns right, on a lit cell it turns left; then it flips the cell and steps forward. After about
-- 10000 steps it builds a repeating "highway". The edges wrap around. w and s change the speed, p pauses, c starts
-- again, q quits. Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the rules.

local CELL = 3
local COLS, ROWS = 80, 40  -- 80 x 40 cells of 3 px cover the top 240 x 120 pixels; the bottom line is the text
local ON, OFF, ANT = 0x40c0ff, 0x000000, 0xff3030
local SPEEDS = { 1, 4, 16, 64, 256 }  -- steps per frame
local DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }  -- up, right, down, left: clockwise order

-- a world keeps one bit per cell, so a 80 x 40 grid takes about 100 numbers
local function newWorld(cols, rows)
  local w = { cols = cols, rows = rows, bits = {}, x = cols // 2, y = rows // 2, dir = 1, steps = 0 }
  for k = 1, (cols * rows) // 32 + 1 do w.bits[k] = 0 end
  return w
end

-- cell i (counted from 0) is bit i % 32 of word i // 32 + 1
local function get(w, x, y)
  local i = y * w.cols + x
  return (w.bits[i // 32 + 1] >> (i % 32)) & 1
end

local function set(w, x, y, v)
  local i = y * w.cols + x
  local k = i // 32 + 1
  if v == 1 then
    w.bits[k] = w.bits[k] | (1 << (i % 32))
  else
    w.bits[k] = w.bits[k] & ~(1 << (i % 32))
  end
end

-- one step of the ant; returns the cell it has just left
local function step(w)
  local x, y = w.x, w.y
  local s = get(w, x, y)
  if s == 0 then w.dir = w.dir % 4 + 1 else w.dir = (w.dir + 2) % 4 + 1 end  -- right turn on dark, left turn on lit
  set(w, x, y, 1 - s)
  local d = DIRS[w.dir]
  w.x = (x + d[1]) % w.cols
  w.y = (y + d[2]) % w.rows
  w.steps = w.steps + 1
  return x, y
end

local function paint(x, y, v)
  gfx.fill(x * CELL, y * CELL, CELL, CELL, v == 1 and ON or OFF)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local w = newWorld(8, 6)
  check(w.x == 4 and w.y == 3 and w.dir == 1 and get(w, 4, 3) == 0, "a new world is dark with the ant in the middle, facing up")
  step(w)  -- dark cell: a right turn, the cell is lit and the ant moves right
  check(w.dir == 2 and w.x == 5 and w.y == 3 and get(w, 4, 3) == 1, "a dark cell turns the ant right and moves it on")
  step(w)  -- dark again: another right turn, facing down
  check(w.dir == 3 and w.x == 5 and w.y == 4 and get(w, 5, 3) == 1, "a second right turn faces down")
  set(w, 5, 4, 1)  -- lit cell: a left turn from down is right, and the cell goes dark
  step(w)
  check(w.dir == 2 and w.x == 6 and w.y == 4 and get(w, 5, 4) == 0, "a lit cell turns the ant left and clears it")
  w.x, w.y, w.dir = 0, 0, 4  -- facing left at the top-left corner: a right turn faces up and the ant wraps to the bottom
  step(w)
  check(w.dir == 1 and w.x == 0 and w.y == 5, "the ant wraps around the edges")
  check(get(w, 0, 0) == 1 and get(w, 7, 4) == 0, "cells are kept apart from their neighbours")
  set(w, 7, 5, 1)
  check(get(w, 7, 5) == 1 and get(w, 7, 4) == 0 and get(w, 0, 0) == 1, "setting one cell leaves the others alone")
  check(w.steps == 4, "every step is counted")
  local big = newWorld(COLS, ROWS)
  for _ = 1, 200 do step(big) end
  check(big.steps == 200 and big.x >= 0 and big.x < COLS and big.y >= 0 and big.y < ROWS, "the ant stays on the grid")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("langton needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("langton: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local w = newWorld(COLS, ROWS)
  local speed, paused = 4, false  -- index into SPEEDS: 64 steps a frame to start
  gfx.clear(OFF)
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == "p" then
        paused = not paused
      elseif k == "c" then
        w = newWorld(COLS, ROWS)
        gfx.clear(OFF)
      elseif k == "w" or k == "up" then
        speed = math.min(#SPEEDS, speed + 1)
      elseif k == "s" or k == "down" then
        speed = math.max(1, speed - 1)
      end
      k = key.poll()
    end
    if not paused then
      for _ = 1, SPEEDS[speed] do
        local x, y = step(w)
        paint(x, y, get(w, x, y))  -- only the cell that changed is drawn again
      end
    end
    gfx.fill(w.x * CELL, w.y * CELL, CELL, CELL, ANT)
    gfx.fill(0, 122, 240, 13, OFF)
    gfx.text(2, 124, "steps " .. w.steps .. "  w s speed  p pause  c new  q", 0x9aa8c0, 1)
    gfx.flush()
    sys.sleep(30)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("langton: " .. tostring(problem)) end
