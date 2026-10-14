#!lua
-- chaos: the chaos game. Corners of a polygon are placed on the screen and a point starts in the middle. Each frame it
-- jumps part of the way towards a random corner and leaves a dot there. With three corners and a jump of half the way
-- the dots fill a Sierpinski triangle; more corners and the 2/3 jump make other shapes. a d change the corners (3 to 6),
-- r changes the jump (1/2 or 2/3), w s the speed, c starts again, p pauses, q quits. Needs the graphics (firmware
-- v0.1.0.13). Run it with --selftest to check the corners and the jump.

local MIN_CORNERS, MAX_CORNERS = 3, 6
local JUMPS = { 1 / 2, 2 / 3 }  -- the fraction of the way towards the chosen corner
local JUMP_TEXT = { "1/2", "2/3" }
local SPEEDS = { 20, 80, 320, 1280 }  -- dots a frame
local CX, CY, R = 120, 60, 54  -- the polygon is centred in the top 240 x 120 area, with a margin
local BG, TEXT, MARK = 0x000000, 0x9aa8c0, 0xffffff
local COLOURS = { 0xff4040, 0xffa030, 0xffe060, 0x40ff80, 0x40c0ff, 0xc070ff }  -- one colour for each corner

-- the positions of the corners of a polygon with n corners, the first one at the top; returns two lists
local function corners(n)
  local xs, ys = {}, {}
  for i = 0, n - 1 do
    local a = -math.pi / 2 + 2 * math.pi * i / n
    xs[i + 1] = CX + R * math.cos(a)
    ys[i + 1] = CY + R * math.sin(a)
  end
  return xs, ys
end

-- one step of the game: the point moves the fraction j of the way from (x, y) towards the corner (cx, cy)
local function jump(x, y, cx, cy, j)
  return x + (cx - x) * j, y + (cy - y) * j
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local xs, ys = corners(3)
  check(math.abs(xs[1] - 120) < 0.01 and math.abs(ys[1] - 6) < 0.01, "the first corner is at the top")
  for n = MIN_CORNERS, MAX_CORNERS do
    local px, py = corners(n)
    check(#px == n and #py == n, "there are " .. n .. " corners")
    for i = 1, n do
      check(px[i] >= 0 and px[i] < 240 and py[i] >= 0 and py[i] < 122,
        "corner " .. i .. " of " .. n .. " is on the screen")
    end
  end
  local x, y = jump(0, 0, 10, 10, 1 / 2)
  check(x == 5 and y == 5, "half way towards the corner is the middle")
  x, y = jump(0, 0, 9, 0, 2 / 3)
  check(math.abs(x - 6) < 0.001 and y == 0, "two thirds of the way is 6 of 9")
  -- the points never leave the box around the corners
  math.randomseed(7)
  xs, ys = corners(5)
  x, y = CX, CY
  local inside = true
  for _ = 1, 1000 do
    local c = math.random(5)
    x, y = jump(x, y, xs[c], ys[c], 2 / 3)
    if x < CX - R or x > CX + R or y < CY - R or y > CY + R then inside = false end
  end
  check(inside, "the points stay inside the polygon")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("chaos needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("chaos: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local corner, speed, ratio, paused = 3, 2, 1, false  -- three corners, 80 dots a frame, jump half way
  local xs, ys
  local px, py, drawn = CX, CY, 0  -- the moving point and the number of dots drawn

  local function layout()
    xs, ys = corners(corner)
  end

  local function restart()
    gfx.clear(BG)
    for i = 1, corner do
      gfx.disc(math.floor(xs[i]), math.floor(ys[i]), 2, MARK)
    end
    px, py, drawn = CX, CY, 0
  end

  layout()
  restart()
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == "p" then
        paused = not paused
      elseif k == "c" then
        restart()
      elseif k == "a" or k == "down" then
        corner = math.max(MIN_CORNERS, corner - 1)
        layout()
        restart()
      elseif k == "d" or k == "up" then
        corner = math.min(MAX_CORNERS, corner + 1)
        layout()
        restart()
      elseif k == "r" then
        ratio = ratio == 1 and 2 or 1
        restart()
      elseif k == "w" then
        speed = math.min(#SPEEDS, speed + 1)
      elseif k == "s" then
        speed = math.max(1, speed - 1)
      end
      k = key.poll()
    end
    if not paused then
      for _ = 1, SPEEDS[speed] do
        local c = math.random(corner)
        px, py = jump(px, py, xs[c], ys[c], JUMPS[ratio])
        gfx.pixel(math.floor(px), math.floor(py), COLOURS[(c - 1) % #COLOURS + 1])
        drawn = drawn + 1
      end
    end
    gfx.fill(0, 122, 240, 13, BG)
    gfx.text(2, 124, corner .. " corners  " .. JUMP_TEXT[ratio] .. "  dots " .. drawn .. "  w s speed  q quit", TEXT, 1)
    gfx.flush()
    sys.sleep(30)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("chaos: " .. tostring(problem)) end
