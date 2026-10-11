#!lua
-- pacmaze: eat every dot in the maze and avoid the two ghosts. Move with w a s d: you keep going in that direction until a
-- wall stops you. Three lives; a ghost that catches you costs one and you start again. ctrl-q quits. Needs the graphics
-- and the ui package. Run it with --selftest to check the maze and the ghosts.

local MAP = {
  "#################",
  "#.o.............#",
  "#.###.#####.##..#",
  "#.#...........#.#",
  "#.#.#.#.#.#.#...#",
  "#...#.#...#.#.#.#",
  "#.#.#.###.#.#.#.#",
  "#.#...........#.#",
  "#################",
}
local ROWS, COLS = #MAP, #MAP[1]
local CELL = 12
local OX, OY = 14, 8
local PAC_START = { r = 2, c = 2 }
local GHOST_START = { { r = 6, c = 9 }, { r = 8, c = 9 } }

local function open(map, r, c)
  local row = map[r]
  if not row or c < 1 or c > #row then return false end
  return row:sub(c, c) ~= "#"
end

-- the direction (dr, dc) that brings a ghost closest to the target, without turning back unless it must
local DIRS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
local function chase(map, from, target, back)
  local best, bestD = nil, math.huge
  for _, d in ipairs(DIRS) do
    local nr, nc = from.r + d[1], from.c + d[2]
    if open(map, nr, nc) and not (back and d[1] == -back[1] and d[2] == -back[2]) then
      local dist = math.abs(nr - target.r) + math.abs(nc - target.c)
      if dist < bestD then
        best, bestD = d, dist
      end
    end
  end
  if not best and back then return { -back[1], -back[2] } end
  return best
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(ROWS == 9 and COLS == 17, "the maze is 17 by 9")
  for _, row in ipairs(MAP) do check(#row == COLS, "every row is 17 long") end
  check(open(MAP, PAC_START.r, PAC_START.c), "you start on the floor")
  for _, g in ipairs(GHOST_START) do check(open(MAP, g.r, g.c), "the ghosts start on the floor") end
  check(not open(MAP, 1, 1), "a wall is not open")
  -- from the start, the ghost chase reaches you: a ghost moving one step at a time gets there
  local g = { r = GHOST_START[1].r, c = GHOST_START[1].c }
  local back = nil
  local steps = 0
  while (g.r ~= PAC_START.r or g.c ~= PAC_START.c) and steps < 300 do
    local d = chase(MAP, g, PAC_START, back)
    check(d ~= nil, "a ghost always has a way to move")
    if not d then break end
    g = { r = g.r + d[1], c = g.c + d[2] }
    back = d
    steps = steps + 1
  end
  check(g.r == PAC_START.r and g.c == PAC_START.c, "a ghost reaches you")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("pacmaze needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("pacmaze: " .. tostring(uiErr))
  return
end

local dots, pac, pacDir, ghosts, lives, score, ghostBack, tick
local function reset()
  dots = {}
  for r = 1, ROWS do
    dots[r] = {}
    for c = 1, COLS do dots[r][c] = MAP[r]:sub(c, c) == "." or MAP[r]:sub(c, c) == "o" end
  end
  dots[PAC_START.r][PAC_START.c] = false
  pac = { r = PAC_START.r, c = PAC_START.c }
  pacDir = nil
  ghosts = { { r = GHOST_START[1].r, c = GHOST_START[1].c, back = nil }, { r = GHOST_START[2].r, c = GHOST_START[2].c, back = nil } }
  tick = 0
end

local function dotsLeft()
  local n = 0
  for r = 1, ROWS do
    for c = 1, COLS do if dots[r][c] then n = n + 1 end end
  end
  return n
end

local function draw()
  gfx.clear(0x0a0c14)
  for r = 1, ROWS do
    for c = 1, COLS do
      local x, y = OX + (c - 1) * CELL, OY + (r - 1) * CELL
      if MAP[r]:sub(c, c) == "#" then
        gfx.fill(x, y, CELL - 1, CELL - 1, 0x2a3fa0)
      elseif dots[r][c] then
        gfx.fill(x + 5, y + 5, 2, 2, 0xf0d080)
      end
    end
  end
  gfx.disc(OX + (pac.c - 1) * CELL + 6, OY + (pac.r - 1) * CELL + 6, 4, 0xffe040)
  for i, g in ipairs(ghosts) do
    gfx.fill(OX + (g.c - 1) * CELL + 2, OY + (g.r - 1) * CELL + 2, 8, 8, i == 1 and 0xff4040 or 0x40e0ff)
  end
  ui.label(OX + 11 * CELL, 10, "score " .. score, 0xe8ecf4)
  ui.label(OX + 11 * CELL, 26, "lives " .. lives, 0xe8ecf4)
  ui.label(OX + 11 * CELL, 50, "w a s d", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("pacmaze: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  lives, score = 3, 0
  reset()
  local state = "playing"
  while true do
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "w" then pacDir = { -1, 0 }
      elseif k == "s" then pacDir = { 1, 0 }
      elseif k == "a" then pacDir = { 0, -1 }
      elseif k == "d" then pacDir = { 0, 1 } end
      k = key.poll()
    end
    tick = tick + 1
    if state == "playing" then
      if tick % 5 == 0 and pacDir and open(MAP, pac.r + pacDir[1], pac.c + pacDir[2]) then
        pac.r, pac.c = pac.r + pacDir[1], pac.c + pacDir[2]
        if dots[pac.r][pac.c] then
          dots[pac.r][pac.c] = false
          score = score + 10
        end
      end
      if tick % 8 == 0 then
        for _, g in ipairs(ghosts) do
          local d = chase(MAP, g, pac, g.back)
          if d then
            g.r, g.c = g.r + d[1], g.c + d[2]
            g.back = d
          end
        end
      end
      for _, g in ipairs(ghosts) do
        if g.r == pac.r and g.c == pac.c then
          lives = lives - 1
          if lives == 0 then
            state = "over"
          else
            pac = { r = PAC_START.r, c = PAC_START.c }
            pacDir = nil
            ghosts[1].r, ghosts[1].c, ghosts[2].r, ghosts[2].c = GHOST_START[1].r, GHOST_START[1].c, GHOST_START[2].r, GHOST_START[2].c
          end
        end
      end
      if dotsLeft() == 0 then state = "won" end
    end
    draw()
    if state ~= "playing" then
      ui.center(118, state == "won" and "you ate them all! ctrl-q" or "game over. ctrl-q quits", 0xffe060, 1)
      gfx.flush()
      while true do
        local q = key.poll()
        if q == "ctrl-q" then return end
        sys.sleep(40)
      end
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("pacmaze: " .. tostring(problem)) end
