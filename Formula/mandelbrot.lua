#!lua
-- mandelbrot: the Mandelbrot set drawn in characters, and you can zoom into it. Arrows move the view, + zooms in, -
-- zooms out, r goes back to the whole set, q quits. The darker the character, the longer a point took to leave the set;
-- @ marks the points that stay in it. A redraw takes a moment, so the picture only changes after a key.

local COLS, ROWS = term.size()
local H = ROWS - 3            -- picture rows: 1 to H (row 0 is the title, the last two rows are the info and the keys)
local PALETTE = " .:-=+*#%"
local MAX_ITER = 40
local START = { cx = -0.5, cy = 0.0, width = 3.0 }

local view = { cx = START.cx, cy = START.cy, width = START.width }

-- the picture is as tall as it is wide in pixels, and a character cell is about twice as tall as it is wide
local function heightOf(width)
  return width * (H / COLS) * 2
end

-- how many steps the point c = re + im*i takes to leave the set, or MAX_ITER when it does not leave
local function escape(re, im)
  local zr, zi = 0.0, 0.0
  for n = 0, MAX_ITER - 1 do
    local zr2, zi2 = zr * zr, zi * zi
    if zr2 + zi2 > 4 then return n end
    zi = 2 * zr * zi + im
    zr = zr2 - zi2 + re
  end
  return MAX_ITER
end

local function draw()
  term.clear()
  term.text(0, 0, "mandelbrot", "green")
  local height = heightOf(view.width)
  for row = 0, H - 1 do
    local im = view.cy + ((row + 0.5) / H - 0.5) * height
    local line = {}
    for col = 0, COLS - 1 do
      local re = view.cx + ((col + 0.5) / COLS - 0.5) * view.width
      local n = escape(re, im)
      if n >= MAX_ITER then
        line[#line + 1] = "@"
      else
        local idx = n * #PALETTE // MAX_ITER + 1
        line[#line + 1] = PALETTE:sub(idx, idx)
      end
    end
    term.text(0, row + 1, table.concat(line), "text")
  end
  term.text(0, ROWS - 2, string.format("x %.4f  y %.4f  width %.5f", view.cx, view.cy, view.width), "dim")
  term.text(0, ROWS - 1, "arrows move  +/- zoom  r reset  q quit", "dim")
  term.flush()
end

-- returns false when the player quits
local function handle(k)
  local pan = view.width / 4
  if k == "left" then
    view.cx = view.cx - pan
  elseif k == "right" then
    view.cx = view.cx + pan
  elseif k == "up" then
    view.cy = view.cy - heightOf(view.width) / 4
  elseif k == "down" then
    view.cy = view.cy + heightOf(view.width) / 4
  elseif k == "+" or k == "=" then
    view.width = view.width / 2
  elseif k == "-" then
    view.width = view.width * 2
  elseif k == "r" then
    view.cx, view.cy, view.width = START.cx, START.cy, START.width
  elseif k == "q" then
    return false
  end
  return true
end

term.fullscreen(true)
local quit, dirty = false, true
while not quit do
  if dirty then
    draw()
    dirty = false
  else
    term.flush()
  end
  local k = key.poll()
  while k do
    if not handle(k) then
      quit = true
      break
    end
    dirty = true
    k = key.poll()
  end
  sys.sleep(50)
end
term.fullscreen(false)
