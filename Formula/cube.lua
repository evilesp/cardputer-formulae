#!lua
-- cube: a spinning 3D wireframe cube drawn with perspective. The near edges are brighter, the corners are dots.
-- w and s turn it faster or slower, a and d make it smaller or bigger, space changes the colours, p pauses,
-- q quits. Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the maths.

local W, H = 240, 135
local CX, CY = W / 2, H / 2
local CAMERA = 3.0          -- distance from the eye to the centre, in units of the half-size of the cube
local SIZE_MIN, SIZE_MAX = 16, 60
local SPIN_MIN, SPIN_MAX = 0.0, 4.0

local THEMES = {
  { name = "classic", bg = 0x060a14, edge = 0x40e0ff, dot = 0xffffff },
  { name = "fire",    bg = 0x120604, edge = 0xff8020, dot = 0xffe060 },
  { name = "ice",     bg = 0x040c18, edge = 0xa0e8ff, dot = 0xffffff },
  { name = "mono",    bg = 0x0a0a0a, edge = 0xd0d0d0, dot = 0xffffff },
}

-- the 8 corners of the cube, each coordinate is -1 or 1: bit 1 is x, bit 2 is y, bit 4 is z
local CORNER_X, CORNER_Y, CORNER_Z = {}, {}, {}
for i = 0, 7 do
  CORNER_X[i + 1] = (i & 1 == 1) and 1 or -1
  CORNER_Y[i + 1] = (i & 2 == 2) and 1 or -1
  CORNER_Z[i + 1] = (i & 4 == 4) and 1 or -1
end

-- the 12 edges: two corners that differ in exactly one coordinate
local EDGE_A, EDGE_B = {}, {}
for i = 0, 7 do
  for _, bit in ipairs({ 1, 2, 4 }) do
    local j = i ~ bit
    if j > i then
      EDGE_A[#EDGE_A + 1] = i + 1
      EDGE_B[#EDGE_B + 1] = j + 1
    end
  end
end

-- the projected screen position of every corner, filled in place each frame (no new tables in the loop)
local SX, SY, SZ = {}, {}, {}
for i = 1, 8 do SX[i], SY[i], SZ[i] = 0, 0, 0 end

-- a colour scaled by a brightness from 0 to 1 (the depth shading of an edge)
local function shade(colour, level)
  if level >= 1 then return colour end
  if level <= 0 then return 0 end
  local r, g, b = (colour >> 16) & 255, (colour >> 8) & 255, colour & 255
  return (math.floor(r * level) << 16) | (math.floor(g * level) << 8) | math.floor(b * level)
end

-- brightness from the depth z of a point: near points (z below 0) are bright, far ones dim, never black
local function depthLevel(z)
  local level = (1.8 - z) / 3.6
  if level < 0.3 then return 0.3 end
  if level > 1 then return 1 end
  return level
end

local function clampSize(s)
  if s < SIZE_MIN then return SIZE_MIN end
  if s > SIZE_MAX then return SIZE_MAX end
  return s
end

local function clampSpin(s)
  if s < SPIN_MIN then return SPIN_MIN end
  if s > SPIN_MAX then return SPIN_MAX end
  return s
end

-- turn the point (x, y, z) by the three angles: first round X, then Y, then Z
local function rotate(x, y, z, ax, ay, az)
  local cx, sx = math.cos(ax), math.sin(ax)
  local cy, sy = math.cos(ay), math.sin(ay)
  local cz, sz = math.cos(az), math.sin(az)
  local y1 = y * cx - z * sx
  local z1 = y * sx + z * cx
  local x2 = x * cy + z1 * sy
  local z2 = -x * sy + z1 * cy
  local x3 = x2 * cz - y1 * sz
  local y3 = x2 * sz + y1 * cz
  return x3, y3, z2
end

-- project all corners for the given angles and size, into SX, SY and SZ
local function project(ax, ay, az, size)
  for i = 1, 8 do
    local x, y, z = rotate(CORNER_X[i], CORNER_Y[i], CORNER_Z[i], ax, ay, az)
    local f = CAMERA / (CAMERA + z)
    SX[i] = CX + x * size * f
    SY[i] = CY + y * size * f
    SZ[i] = z
  end
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(#EDGE_A == 12 and #EDGE_B == 12, "a cube has 12 edges")
  local oneBit = true
  for e = 1, 12 do
    local a, b = EDGE_A[e] - 1, EDGE_B[e] - 1
    local diff = (a ~ b)
    if not (diff == 1 or diff == 2 or diff == 4) then oneBit = false end
  end
  check(oneBit, "every edge joins corners that differ in one coordinate")
  check(shade(0xffffff, 1) == 0xffffff, "a full brightness keeps the colour")
  check(shade(0xffffff, 0) == 0, "zero brightness is black")
  check(shade(0x804020, 0.5) == 0x402010, "half brightness halves each channel")
  check(depthLevel(-1.8) == 1 and depthLevel(1.8) == 0.3, "depth shading runs from the near to the far edge")
  local x, y, z = rotate(1, 1, 1, 0, 0, 0)
  check(x == 1 and y == 1 and z == 1, "no turn leaves a corner where it is")
  local rx, ry, rz = rotate(1, 0, 0, math.pi / 2, 0, 0)
  check(math.abs(rx - 1) < 1e-9 and math.abs(ry) < 1e-9 and math.abs(rz) < 1e-9, "a quarter turn round X leaves the X axis alone")
  local tx, ty, tz = rotate(0.3, -0.7, 0.5, 0.4, 1.1, 2.3)
  local before = 0.3 * 0.3 + 0.7 * 0.7 + 0.5 * 0.5
  check(math.abs(tx * tx + ty * ty + tz * tz - before) < 1e-9, "turning keeps the length of a corner")
  project(0, 0, 0, 40)
  local near = 40 * CAMERA / (CAMERA + 1)
  check(math.abs(SX[8] - (CX + near)) < 1e-9 and math.abs(SY[8] - (CY + near)) < 1e-9, "the near corner is pulled in by perspective")
  check(clampSize(1) == SIZE_MIN and clampSize(900) == SIZE_MAX and clampSize(40) == 40, "the size stays in its range")
  check(clampSpin(-1) == SPIN_MIN and clampSpin(9) == SPIN_MAX and clampSpin(1) == 1, "the speed stays in its range")
  check(#THEMES == 4 and THEMES[1].name == "classic", "themes")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("cube needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("cube: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local ax, ay, az = 0, 0, 0
  local spin, size, paused, theme = 1.0, 40, false, 1
  local shown = sys.millis()
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then theme = theme % #THEMES + 1 shown = sys.millis()
      elseif k == "p" then paused = not paused shown = sys.millis()
      elseif k == "w" or k == "up" then spin = clampSpin(spin + 0.25) shown = sys.millis()
      elseif k == "s" or k == "down" then spin = clampSpin(spin - 0.25) shown = sys.millis()
      elseif k == "a" or k == "left" then size = clampSize(size - 4) shown = sys.millis()
      elseif k == "d" or k == "right" then size = clampSize(size + 4) shown = sys.millis() end
      k = key.poll()
    end
    local t = THEMES[theme]
    gfx.clear(t.bg)
    project(ax, ay, az, size)
    for e = 1, 12 do
      local a, b = EDGE_A[e], EDGE_B[e]
      local level = depthLevel((SZ[a] + SZ[b]) / 2)
      gfx.line(math.floor(SX[a] + 0.5), math.floor(SY[a] + 0.5),
               math.floor(SX[b] + 0.5), math.floor(SY[b] + 0.5), shade(t.edge, level))
    end
    for i = 1, 8 do
      gfx.disc(math.floor(SX[i] + 0.5), math.floor(SY[i] + 0.5), 2, shade(t.dot, depthLevel(SZ[i])))
    end
    if not paused then
      ax = ax + 0.031 * spin
      ay = ay + 0.023 * spin
      az = az + 0.013 * spin
    end
    if sys.millis() - shown < 1800 then
      gfx.text(4, 4, t.name .. (paused and "  paused" or "") .. "  space w s a d q", 0xffffff, 1)
    end
    gfx.flush()
    sys.sleep(20)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("cube: " .. tostring(problem)) end
