#!lua
-- poziomica: a spirit level. Lay the Cardputer on a flat surface, or on the edge of a shelf: the bubble moves
-- towards the high side. roll is the tilt left-right and pitch the tilt forward-back, in degrees, from the
-- accelerometer (sys.imu). z sets the current position as level, q quits.

local COLS, ROWS = term.size()
local CX, CY = 20, 8        -- centre of the bubble area
local RANGE_DEG = 30        -- a tilt of this many degrees puts the bubble at the edge

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- roll and pitch in degrees from the three accelerations (in g)
local function angles(ax, ay, az)
  local roll = math.deg(math.atan(ay, az))
  local pitch = math.deg(math.atan(-ax, math.sqrt(ay * ay + az * az)))
  return roll, pitch
end

local function draw(roll, pitch, zeroRoll, zeroPitch)
  local r, p = roll - zeroRoll, pitch - zeroPitch
  local level = math.abs(r) < 1 and math.abs(p) < 1
  term.clear()
  term.text(0, 0, "poziomica  z = zero, q = quit", "cyan")
  term.text(CX - 10, CY, string.rep("-", 21), "dim")
  for y = 3, 13 do
    if y ~= CY then term.text(CX, y, "|", "dim") end
  end
  local bx = CX + math.floor(clamp(r / RANGE_DEG, -1, 1) * 10 + 0.5)
  local by = CY + math.floor(clamp(p / RANGE_DEG, -1, 1) * 4 + 0.5)
  term.text(bx, by, "O", level and "cyan" or "white")
  term.text(0, 14, string.format("roll %+.1f deg   pitch %+.1f deg", r, p):sub(1, COLS), "text")
  term.text(0, 15, (level and "level" or "tilt until the bubble is centred"):sub(1, COLS),
    level and "cyan" or "dim")
  term.flush()
end

local ax, ay, az = sys.imu()
if not ax then
  print("poziomica: this board has no motion sensor")
  return
end

term.fullscreen(true)
local zeroRoll, zeroPitch = 0, 0
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
  local roll, pitch = angles(ax, ay, az)
  if zeroRequested then
    zeroRoll, zeroPitch = roll, pitch
    zeroRequested = false
  end
  draw(roll, pitch, zeroRoll, zeroPitch)
  sys.sleep(80)
end
term.fullscreen(false)
