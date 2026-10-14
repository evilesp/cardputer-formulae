#!lua
-- hilbert: the Hilbert curve, one line that fills a square grid of cells without crossing itself, always stepping
-- to a neighbouring cell. It is drawn one segment at a time; when the curve is complete it holds for a moment and
-- starts again. a d change the size of the grid (4 x 4 up to 32 x 32), w s speed, p pauses, c starts again, q quits.
-- Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the curve.

local ORDERS = { 2, 3, 4, 5 }  -- the grid sides are 4, 8, 16 and 32 cells (2 ^ order)
local SPEEDS = { 1, 4, 16, 64 }  -- segments drawn in one frame
local BOX = 120  -- the curve fits in a 120 x 120 pixel square at the top of the screen; the bottom line is the text
local LINE, BG, TEXT = 0x40c0ff, 0x000000, 0x9aa8c0
local HOLD = 60  -- frames the complete curve stays on the screen (about 2 seconds)

-- position of point d on a grid with side n (a power of two): the classic d2xy conversion. Only locals are used,
-- so it allocates nothing and can run every frame.
local function point(n, d)
  local x, y, t = 0, 0, d
  local s = 1
  while s < n do
    local rx = 1 & (t // 2)
    local ry = 1 & (t ~ rx)
    if ry == 0 then  -- turn the square built so far, so that the next level joins up
      if rx == 1 then x, y = s - 1 - x, s - 1 - y end
      x, y = y, x
    end
    x = x + s * rx
    y = y + s * ry
    t = t // 4
    s = s * 2
  end
  return x, y
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local x, y = point(2, 0)
  check(x == 0 and y == 0, "the curve starts in the top-left cell")
  x, y = point(2, 1)
  check(x == 0 and y == 1, "the second cell is below the first")
  x, y = point(2, 2)
  check(x == 1 and y == 1, "the third cell is to the right of the second")
  x, y = point(2, 3)
  check(x == 1 and y == 0, "the curve ends in the top-right cell of the 2 x 2 grid")
  for _, n in ipairs({ 4, 8, 16 }) do
    local seen = {}
    local px, py = point(n, 0)
    seen[py * n + px] = true
    local neighbours, inside, unique = true, true, true
    for d = 1, n * n - 1 do
      x, y = point(n, d)
      if math.abs(x - px) + math.abs(y - py) ~= 1 then neighbours = false end
      if x < 0 or x >= n or y < 0 or y >= n then inside = false end
      if seen[y * n + x] then unique = false end
      seen[y * n + x] = true
      px, py = x, y
    end
    check(neighbours, "every step goes to a neighbouring cell on the " .. n .. " x " .. n .. " grid")
    check(inside, "the curve stays on the " .. n .. " x " .. n .. " grid")
    check(unique, "the curve visits every cell once on the " .. n .. " x " .. n .. " grid")
    check(px == n - 1 and py == 0, "the curve ends in the top-right corner on the " .. n .. " x " .. n .. " grid")
  end
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("hilbert needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("hilbert: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local level, speed, paused = 3, 2, false  -- ORDERS[3] is a 16 x 16 grid, 16 segments a frame to start
  local side, cell, ox, total
  local d, hold = 0, 0  -- d is the index of the last point drawn; hold counts the frames of the finished curve

  -- the grid size decides the cell size and where the curve sits; the cells are centred in the top 240 x 120 area
  local function layout()
    side = 1 << ORDERS[level]
    cell = BOX // side
    ox = (240 - side * cell) // 2
    total = side * side
  end

  local function restart()
    gfx.clear(BG)
    d, hold = 0, 0
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
        level = math.max(1, level - 1)
        layout()
        restart()
      elseif k == "d" or k == "up" then
        level = math.min(#ORDERS, level + 1)
        layout()
        restart()
      elseif k == "w" then
        speed = math.min(#SPEEDS, speed + 1)
      elseif k == "s" then
        speed = math.max(1, speed - 1)
      end
      k = key.poll()
    end
    if not paused then
      if hold > 0 then
        hold = hold - 1
        if hold == 0 then restart() end
      else
        for _ = 1, SPEEDS[speed] do
          if d >= total - 1 then
            hold = HOLD
            break
          end
          local x1, y1 = point(side, d)
          local x2, y2 = point(side, d + 1)
          gfx.line(ox + x1 * cell + cell // 2, y1 * cell + cell // 2,
                   ox + x2 * cell + cell // 2, y2 * cell + cell // 2, LINE)
          d = d + 1
        end
      end
    end
    gfx.fill(0, 122, 240, 13, BG)
    gfx.text(2, 124, side .. "x" .. side .. "  " .. (d * 100 // total) .. "%  w s speed  a d size  p pause  c new  q", TEXT, 1)
    gfx.flush()
    sys.sleep(30)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("hilbert: " .. tostring(problem)) end
