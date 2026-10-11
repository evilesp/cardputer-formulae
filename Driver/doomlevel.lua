#!lua
-- doomlevel: the level of doom and the geometry of its ray caster. A driver, not a program: brew installs it into
-- /usr/local/lib/drivers, and doom loads it with driver.load("doomlevel"). It holds the map, the look of the walls and of
-- the monsters, and the functions that tell what is a wall and how far it is along a ray.
--   the map: 1 2 3 4 are walls of four kinds, . is floor, P the start, E an imp, D a demon, H health, A ammo.

local level = {}

level.MAP_TEXT = {
  "111111111111111111111111",
  "1.......2.......3......1",
  "1.P.....2.....A.3......1",
  "1.......2..E....3...E..1",
  "1...............3......1",
  "1..........33...3...33.1",
  "1....3..2..33...3......1",
  "1....3..2..............1",
  "1...H...2111..11.......1",
  "1.....E.2.......3.D....1",
  "1............E..3....H.1",
  "122..2222.......3..E...1",
  "1.......2..D.A.........1",
  "1.......2.....E.3444..41",
  "1..D....2.......3......1",
  "1........4..44443....D.1",
  "1...............3......1",
  "1....E..2.......3..33A.1",
  "1.......2..............1",
  "1..33...2...33.........1",
  "1.H...A.2.......3......1",
  "1.......2...E.H.3...E..1",
  "1.......2.......3......1",
  "111111111111111111111111",
}
level.MW, level.MH = 24, 24

-- the colour of each kind of wall, 0xRRGGBB
level.WALL = { [1] = 0xa84632, [2] = 0x8a8f9c, [3] = 0x3a6ea8, [4] = 0x4a8a56 }

-- how things look: boxes in a unit square, u from left to right and v from the top to the bottom, each as
-- { u0, u1, v0, v1, colour }
level.LOOKS = {
  imp = {
    { 0.30, 0.45, 0.78, 1.00, 0x502818 }, { 0.55, 0.70, 0.78, 1.00, 0x502818 },
    { 0.10, 0.22, 0.40, 0.66, 0x8a4a28 }, { 0.78, 0.90, 0.40, 0.66, 0x8a4a28 },
    { 0.22, 0.78, 0.38, 0.80, 0xa85c30 }, { 0.32, 0.68, 0.12, 0.40, 0xc07840 },
    { 0.30, 0.36, 0.04, 0.14, 0xe8e0c8 }, { 0.64, 0.70, 0.04, 0.14, 0xe8e0c8 },
    { 0.38, 0.44, 0.20, 0.26, 0xffe040 }, { 0.56, 0.62, 0.20, 0.26, 0xffe040 },
  },
  demon = {
    { 0.22, 0.42, 0.78, 1.00, 0x802050 }, { 0.58, 0.78, 0.78, 1.00, 0x802050 },
    { 0.06, 0.20, 0.38, 0.70, 0xc04878 }, { 0.80, 0.94, 0.38, 0.70, 0xc04878 },
    { 0.14, 0.86, 0.30, 0.82, 0xd05888 }, { 0.24, 0.76, 0.06, 0.38, 0xe070a0 },
    { 0.34, 0.66, 0.28, 0.34, 0xffffff }, { 0.30, 0.38, 0.14, 0.22, 0xff2020 },
    { 0.62, 0.70, 0.14, 0.22, 0xff2020 },
  },
  dead = { { 0.08, 0.92, 0.84, 1.00, 0x701818 }, { 0.30, 0.70, 0.76, 0.86, 0x902020 } },
  health = {
    { 0.22, 0.78, 0.52, 1.00, 0xf0f0f0 }, { 0.45, 0.55, 0.58, 0.94, 0xd02828 }, { 0.30, 0.70, 0.70, 0.80, 0xd02828 },
  },
  ammo = { { 0.18, 0.82, 0.60, 1.00, 0xc8a030 }, { 0.28, 0.72, 0.70, 0.80, 0x504010 } },
  ball = { { 0.15, 0.85, 0.15, 0.85, 0xff7020 }, { 0.32, 0.68, 0.32, 0.68, 0xffe060 } },
}

-- ---- the grid and where the things start ----

-- level.rows[y + 1] is a string of digits for the row y (cells counted from 0): 0 for floor and 1 to 4 for a wall. A table of
-- numbers for every row would take ten times the memory, and the memory of the Cardputer is small.
local rows = {}
local spawn = { enemies = {}, pickups = {}, start = { x = 1.5, y = 1.5 } }
for y = 1, level.MH do
  local text = level.MAP_TEXT[y]
  local digits = {}
  for x = 1, level.MW do
    local ch = text:sub(x, x)
    local cx, cy = x - 0.5, y - 0.5
    digits[x] = tonumber(ch) and ch or "0"
    if ch == "P" then spawn.start = { x = cx, y = cy }
    elseif ch == "E" then spawn.enemies[#spawn.enemies + 1] = { kind = "imp", x = cx, y = cy }
    elseif ch == "D" then spawn.enemies[#spawn.enemies + 1] = { kind = "demon", x = cx, y = cy }
    elseif ch == "H" then spawn.pickups[#spawn.pickups + 1] = { kind = "health", x = cx, y = cy }
    elseif ch == "A" then spawn.pickups[#spawn.pickups + 1] = { kind = "ammo", x = cx, y = cy }
    end
  end
  rows[y] = table.concat(digits)
end
level.rows = rows
level.spawn = spawn

-- ---- geometry ----

-- the kind of the wall at the cell (cx, cy), counted from 0; outside the level is a wall too (kind 9)
local byte = string.byte
function level.wallAt(cx, cy)
  local row = rows[cy + 1]
  local t = row and byte(row, cx + 1)
  if t == nil or cx < 0 then return 9 end
  return t - 48
end

-- true when a circle of radius r around (x, y) reaches into a wall
function level.inWall(x, y, r)
  local x0, x1, y0, y1 = math.floor(x - r), math.floor(x + r), math.floor(y - r), math.floor(y + r)
  return level.wallAt(x0, y0) > 0 or level.wallAt(x1, y0) > 0 or level.wallAt(x0, y1) > 0 or level.wallAt(x1, y1) > 0
end

-- from (x, y) along (rdx, rdy): the distance to the first wall, the side it was hit on (0 or 1), the kind of the wall and
-- where along it (0 to 1): the digital differential analyser of the classic ray caster
function level.cast(x, y, rdx, rdy)
  local wallAt = level.wallAt
  local mapX, mapY = math.floor(x), math.floor(y)
  local ddx = rdx == 0 and 1e30 or math.abs(1 / rdx)
  local ddy = rdy == 0 and 1e30 or math.abs(1 / rdy)
  local stepX, stepY, sdx, sdy
  if rdx < 0 then stepX, sdx = -1, (x - mapX) * ddx else stepX, sdx = 1, (mapX + 1 - x) * ddx end
  if rdy < 0 then stepY, sdy = -1, (y - mapY) * ddy else stepY, sdy = 1, (mapY + 1 - y) * ddy end
  local side, kind = 0, 9
  for _ = 1, 64 do
    if sdx < sdy then
      sdx, mapX, side = sdx + ddx, mapX + stepX, 0
    else
      sdy, mapY, side = sdy + ddy, mapY + stepY, 1
    end
    kind = wallAt(mapX, mapY)
    if kind > 0 then break end
  end
  local dist = side == 0 and (sdx - ddx) or (sdy - ddy)
  local wx = side == 0 and (y + dist * rdy) or (x + dist * rdx)
  return dist, side, kind, wx - math.floor(wx)
end

return level
