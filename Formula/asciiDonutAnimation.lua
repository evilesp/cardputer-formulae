#!lua
-- asciiDonutAnimation: a spinning torus of characters, the donut of Andy Sloane's donut.c, drawn at the size of
-- the screen. The brightest side is drawn with @, the darkest with a dot. q quits.

local COLS, ROWS = term.size()
local SHADES = ".,-~:;=!*#$@"
local R1, R2 = 1, 2        -- radius of the tube and of the ring
local K2 = 5               -- distance of the donut from the viewer
local K1 = 8               -- size of the picture on the screen
local N = COLS * ROWS

local A, B = 0, 0          -- the two rotation angles
local zbuf, out = {}, {}

local function render()
  for i = 1, N do
    zbuf[i] = 0
    out[i] = " "
  end
  local cA, sA = math.cos(A), math.sin(A)
  local cB, sB = math.cos(B), math.sin(B)
  for theta = 0, 6.28, 0.08 do
    local ct, st = math.cos(theta), math.sin(theta)
    for phi = 0, 6.28, 0.05 do
      local cp, sp = math.cos(phi), math.sin(phi)
      local circleX = R2 + R1 * ct
      local circleY = R1 * st
      local x = circleX * (cB * cp + sA * sB * sp) - circleY * cA * sB
      local y = circleX * (sB * cp - sA * cB * sp) + circleY * cA * cB
      local z = K2 + cA * circleX * sp + circleY * sA
      local ooz = 1 / z
      -- x is doubled: a character is about twice as tall as it is wide
      local xp = math.floor(COLS / 2 + 2 * K1 * ooz * x)
      local yp = math.floor(ROWS / 2 - K1 * ooz * y)
      local L = cp * ct * sB - cA * ct * sp - sA * st + cB * (cA * st - ct * sA * sp)
      if L > 0 and xp >= 0 and xp < COLS and yp >= 0 and yp < ROWS then
        local idx = yp * COLS + xp + 1
        if ooz > zbuf[idx] then
          zbuf[idx] = ooz
          local shade = math.floor(L * 8) + 1
          if shade > #SHADES then shade = #SHADES end
          out[idx] = SHADES:sub(shade, shade)
        end
      end
    end
  end
end

local function draw()
  for y = 0, ROWS - 1 do
    local row = {}
    for x = 1, COLS do row[x] = out[y * COLS + x] end
    term.text(0, y, table.concat(row), "white")
  end
  term.flush()
end

local quit = false
term.fullscreen(true)
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true end
    k = key.poll()
  end
  if quit then break end
  render()
  draw()
  A = A + 0.07
  B = B + 0.03
  sys.sleep(30)
end
term.fullscreen(false)
