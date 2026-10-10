#!lua
-- spiritLevel: a spirit level. Lay the Cardputer on a flat surface, or on the edge of a shelf: the bubble moves
-- towards the high side. x tilt is the tilt sideways (the bubble moves left and right) and y tilt is the tilt
-- up and down (the bubble moves up and down), both in degrees, from the accelerometer (sys.imu).
-- z sets the current position as level, q quits.

local COLS, ROWS = term.size()
local CX, CY = 20, 8        -- centre of the bubble area
local RANGE_DEG = 30        -- a tilt of this many degrees puts the bubble at the edge

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- the x tilt and the y tilt in degrees, from the three accelerations (in g)
local function tilts(ax, ay, az)
  local xTilt = math.deg(math.atan(-ax, math.sqrt(ay * ay + az * az)))
  local yTilt = math.deg(math.atan(ay, az))
  return xTilt, yTilt
end

local function draw(xTilt, yTilt, zeroX, zeroY)
  local x, y = xTilt - zeroX, yTilt - zeroY
  local level = math.abs(x) < 1 and math.abs(y) < 1
  term.clear()
  term.text(0, 0, "spiritLevel  z = zero, q = quit", "cyan")
  term.text(CX - 10, CY, string.rep("-", 21), "dim")
  for row = 3, 13 do
    if row ~= CY then term.text(CX, row, "|", "dim") end
  end
  local bx = CX + math.floor(clamp(x / RANGE_DEG, -1, 1) * 10 + 0.5)
  local by = CY + math.floor(clamp(y / RANGE_DEG, -1, 1) * 4 + 0.5)
  term.text(bx, by, "O", level and "cyan" or "white")
  term.text(0, 14, string.format("x tilt %+.1f deg   y tilt %+.1f deg", x, y):sub(1, COLS), "text")
  term.text(0, 15, (level and "level" or "tilt until the bubble is centred"):sub(1, COLS),
    level and "cyan" or "dim")
  term.flush()
end

local ax, ay, az = sys.imu()
if not ax then
  print("spiritLevel: this board has no motion sensor")
  return
end

term.fullscreen(true)
local zeroX, zeroY = 0, 0
local zeroRequested, quit = false, false
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true
    elseif k == "z" then zeroRequested = true
    end
    k = key.poll()
  end
  if quit then break end

  ax, ay, az = sys.imu()
  if not ax then break end
  local xTilt, yTilt = tilts(ax, ay, az)
  if zeroRequested then
    zeroX, zeroY = xTilt, yTilt
    zeroRequested = false
  end
  draw(xTilt, yTilt, zeroX, zeroY)
  sys.sleep(80)
end
term.fullscreen(false)
