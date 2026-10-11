#!lua
-- doom: a Doom-like first-person maze drawn in characters. Version 0.0.1: walking and turning only, no enemies yet.
-- The keys are letters, so no Fn key is needed (the arrow keys need Fn). A key keeps its movement going until you press
-- space or another key of the same kind, so you do not have to hold anything:
--   w  walk forward        s  walk backward
--   a  turn left          d  turn right
--   q  step left          e  step right
--   space  stop everything           ctrl-q  quit
-- Walking and turning work together: w and d at once walks and turns. Walls stop you.

local COLS, ROWS = term.size()
local VIEW_H = ROWS - 2            -- the picture is rows 0 to VIEW_H-1; the last two rows are the status and the keys
local FOV = 0.66                   -- the camera plane: about 66 degrees
local MOVE_SPEED = 2.5             -- cells per second
local STRAFE_SPEED = 2.0
local TURN_SPEED = 1.8             -- radians per second
local RADIUS = 0.25                -- the player is a circle this big: it does not touch a wall
local SHADE = "#%*+=-:."           -- from the nearest wall to the farthest

-- the level: # is a wall, . is floor; every row is 16 characters
local MAP = {
  "################",
  "#..............#",
  "#..##....#.....#",
  "#..#.....#.....#",
  "#........#.....#",
  "#.....##.......#",
  "#.....##....#..#",
  "#...........#..#",
  "#..####.....#..#",
  "#..#........#..#",
  "#..#.........#.#",
  "#..............#",
  "#....###.......#",
  "#..............#",
  "#.........#....#",
  "################",
}

local px, py = 2.5, 7.5            -- the player's place, in cells
local angle = 0.0                  -- the direction it looks in, in radians (0 is east)
local move, turn, strafe = nil, nil, nil  -- the motions that keep going: move "forward"/"back", turn and strafe "left"/"right"

-- the wall at the cell (cx, cy), counted from 0; outside the map is a wall too
local function wallAt(cx, cy)
  local row = MAP[cy + 1]
  if not row or cx < 0 or cx >= #row then return true end
  return row:byte(cx + 1) == 35  -- '#'
end

-- the player is blocked when any part of the circle around (x, y) lies in a wall
local function inWall(x, y)
  local x0, x1 = math.floor(x - RADIUS), math.floor(x + RADIUS)
  local y0, y1 = math.floor(y - RADIUS), math.floor(y + RADIUS)
  return wallAt(x0, y0) or wallAt(x1, y0) or wallAt(x0, y1) or wallAt(x1, y1)
end

-- moves by (dx, dy), sliding along a wall when only one direction is blocked
local function slide(dx, dy)
  local nx, ny = px + dx, py + dy
  if not inWall(nx, py) then px = nx end
  if not inWall(px, ny) then py = ny end
end

-- the distance from (x, y) to the first wall along the ray (rdx, rdy), and whether it was a wall facing north-south
-- (side 1) or east-west (side 0): the digital differential analyser of the classic ray caster
local function cast(x, y, rdx, rdy)
  local mapX, mapY = math.floor(x), math.floor(y)
  local ddx = rdx == 0 and 1e30 or math.abs(1 / rdx)
  local ddy = rdy == 0 and 1e30 or math.abs(1 / rdy)
  local stepX, stepY, sdx, sdy
  if rdx < 0 then
    stepX, sdx = -1, (x - mapX) * ddx
  else
    stepX, sdx = 1, (mapX + 1 - x) * ddx
  end
  if rdy < 0 then
    stepY, sdy = -1, (y - mapY) * ddy
  else
    stepY, sdy = 1, (mapY + 1 - y) * ddy
  end
  local side = 0
  for _ = 1, 96 do
    if sdx < sdy then
      sdx = sdx + ddx
      mapX = mapX + stepX
      side = 0
    else
      sdy = sdy + ddy
      mapY = mapY + stepY
      side = 1
    end
    if wallAt(mapX, mapY) then break end
  end
  local dist = side == 0 and (sdx - ddx) or (sdy - ddy)
  return dist, side
end

-- one step of time: the motions that are on move the player and turn it
local function update(dt)
  local dirX, dirY = math.cos(angle), math.sin(angle)
  local rightX, rightY = -dirY, dirX  -- the camera plane points right of the direction
  local vx, vy = 0.0, 0.0
  if move == "forward" then
    vx, vy = vx + dirX * MOVE_SPEED, vy + dirY * MOVE_SPEED
  elseif move == "back" then
    vx, vy = vx - dirX * MOVE_SPEED, vy - dirY * MOVE_SPEED
  end
  if strafe == "right" then
    vx, vy = vx + rightX * STRAFE_SPEED, vy + rightY * STRAFE_SPEED
  elseif strafe == "left" then
    vx, vy = vx - rightX * STRAFE_SPEED, vy - rightY * STRAFE_SPEED
  end
  slide(vx * dt, vy * dt)
  if turn == "right" then
    angle = angle + TURN_SPEED * dt
  elseif turn == "left" then
    angle = angle - TURN_SPEED * dt
  end
end

-- what the player is doing, for the line at the top of the picture
local function label()
  local parts = {}
  if move == "forward" then parts[#parts + 1] = "walking forward" end
  if move == "back" then parts[#parts + 1] = "walking back" end
  if turn == "left" then parts[#parts + 1] = "turning left" end
  if turn == "right" then parts[#parts + 1] = "turning right" end
  if strafe == "left" then parts[#parts + 1] = "stepping left" end
  if strafe == "right" then parts[#parts + 1] = "stepping right" end
  if #parts == 0 then return "standing still" end
  return table.concat(parts, ", ")
end

local function render()
  local dirX, dirY = math.cos(angle), math.sin(angle)
  local planeX, planeY = -dirY * FOV, dirX * FOV
  local grid = {}
  for y = 0, VIEW_H - 1 do grid[y] = {} end
  local half = VIEW_H / 2
  for col = 0, COLS - 1 do
    local cam = 2 * col / (COLS - 1) - 1  -- -1 at the left edge, +1 at the right edge
    local dist, side = cast(px, py, dirX + planeX * cam, dirY + planeY * cam)
    local height = VIEW_H / math.max(dist, 0.05)
    local top, bottom = half - height / 2, half + height / 2
    local shade = math.min(#SHADE, math.max(1, math.floor(dist * 0.9) + 1))
    if side == 1 then shade = math.min(#SHADE, shade + 1) end  -- the walls facing north-south are darker
    local wall = SHADE:sub(shade, shade)
    for y = 0, VIEW_H - 1 do
      local ch
      if y + 0.5 < top then
        ch = " "
      elseif y + 0.5 <= bottom then
        ch = wall
      else
        ch = "."
      end
      grid[y][col + 1] = ch
    end
  end
  term.clear()
  for y = 0, VIEW_H - 1 do
    term.text(0, y, table.concat(grid[y]), y < half and "text" or "dim")
  end
  term.text(0, 0, (label() .. string.rep(" ", COLS)):sub(1, COLS), "cyan")
  local degrees = math.floor((angle * 180 / math.pi) % 360)
  term.text(0, VIEW_H, string.format("x %.2f  y %.2f  face %03d", px, py, degrees), "green")
  term.text(COLS - 11, VIEW_H, "ctrl-q quit", "dim")
  term.text(0, ROWS - 1, "w/s walk  a/d turn  q/e step  spc stop", "dim")
  term.flush()
end

-- returns false when the player quits
local function handle(k)
  if k == "ctrl-q" then return false end
  if #k == 1 then k = k:lower() end
  if k == "w" then
    move = "forward"
  elseif k == "s" then
    move = "back"
  elseif k == "a" then
    turn = "left"
  elseif k == "d" then
    turn = "right"
  elseif k == "q" then
    strafe = "left"
  elseif k == "e" then
    strafe = "right"
  elseif k == " " then
    move, turn, strafe = nil, nil, nil
  end
  return true
end

-- the checks of the level and the ray caster, run with --selftest
if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  for i, row in ipairs(MAP) do
    check(#row == 16, "map row " .. i .. " has 16 characters")
  end
  check(wallAt(0, 0) and not wallAt(2, 2) and wallAt(16, 3), "walls and the outside")
  local dist, side = cast(2.5, 7.5, 1, 0)
  check(math.abs(dist - 9.5) < 1e-9 and side == 0, "a ray east from the start hits the wall at x = 12")
  dist = cast(2.5, 7.5, 0, 1)
  check(dist > 0 and dist < 8, "a ray south hits a wall")
  if failed == 0 then print("selftest ok") end
  return
end

if #arg > 0 then
  print("usage: doom   (no arguments: start the game; keys are shown on the last line)")
  return
end
for i, row in ipairs(MAP) do
  if #row ~= 16 then
    print("doom: map row " .. i .. " has " .. #row .. " characters, 16 are needed")
    return
  end
end

local quit = false
local last = sys.millis()
term.fullscreen(true)
while not quit do
  local now = sys.millis()
  local dt = math.min((now - last) / 1000, 0.25)  -- a long pause moves the player no further than a quarter second
  last = now
  local k = key.poll()
  while k do
    if not handle(k) then
      quit = true
      break
    end
    k = key.poll()
  end
  if not quit then
    update(dt)
    render()
  end
  sys.sleep(30)
end
term.fullscreen(false)
