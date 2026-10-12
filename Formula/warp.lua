#!lua
-- warp: a flight through a starfield at warp speed. The stars stretch into streaks as they pass. w and s change the speed,
-- a and d steer, space switches between white stars, colours and a rainbow tunnel, q quits. Needs the graphics.
-- Run it with --selftest to check the projection.

local W, H = 240, 135
local CX, CY = W / 2, H / 2
local N = 110
local DEPTH = 40

local function project(x, y, z)
  return CX + x / z * 120, CY + y / z * 120
end

local function newStar(far)
  return { x = (math.random() - 0.5) * 60, y = (math.random() - 0.5) * 40, z = far and DEPTH or (0.5 + math.random() * (DEPTH - 0.5)) }
end

local function shade(v)  -- grey from 0..1
  local g = math.max(0, math.min(255, math.floor(v * 255)))
  return (g << 16) | (g << 8) | g
end

local function hue(h, v)
  h = (h % 1) * 6
  local i, f = math.floor(h), h - math.floor(h)
  local r, g, b
  if i == 0 then r, g, b = 1, f, 0 elseif i == 1 then r, g, b = 1 - f, 1, 0 elseif i == 2 then r, g, b = 0, 1, f
  elseif i == 3 then r, g, b = 0, 1 - f, 1 elseif i == 4 then r, g, b = f, 0, 1 else r, g, b = 1, 0, 1 - f end
  return (math.floor(r * v * 255) << 16) | (math.floor(g * v * 255) << 8) | math.floor(b * v * 255)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local x, y = project(0, 0, 5)
  check(x == CX and y == CY, "a star in the middle stays in the middle")
  local x1 = project(10, 0, 20)
  local x2 = project(10, 0, 10)
  check(x2 > x1, "a nearer star is further from the centre")
  check(shade(1) == 0xffffff and shade(0) == 0 and shade(2) == 0xffffff, "grey")
  check(hue(0, 1) == 0xff0000 and hue(1 / 3, 1) == 0x00ff00, "hue")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("warp needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("warp: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local stars = {}
  for i = 1, N do stars[i] = newStar(false) end
  local speed, steerX, mode, shown = 0.35, 0, 1, sys.millis()
  local MODES = { "white", "colour", "rainbow" }
  local t = 0
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then mode = mode % 3 + 1 shown = sys.millis()
      elseif k == "w" or k == "up" then speed = math.min(1.5, speed + 0.1)
      elseif k == "s" or k == "down" then speed = math.max(0.05, speed - 0.1)
      elseif k == "a" or k == "left" then steerX = math.max(-6, steerX - 1.5)
      elseif k == "d" or k == "right" then steerX = math.min(6, steerX + 1.5) end
      k = key.poll()
    end
    t = t + 0.02
    steerX = steerX * 0.96
    gfx.clear(0x02030a)
    for i, s in ipairs(stars) do
      local x0, y0 = project(s.x, s.y, s.z)
      s.z = s.z - speed
      s.x = s.x - steerX * 0.05
      if s.z < 0.3 then
        stars[i] = newStar(true)
      else
        local x1, y1 = project(s.x, s.y, s.z)
        if x1 < -20 or x1 > W + 20 or y1 < -20 or y1 > H + 20 then
          stars[i] = newStar(true)
        else
          local near = 1 - s.z / DEPTH
          local c
          if mode == 1 then c = shade(0.25 + near * 0.9)
          elseif mode == 2 then c = hue(i / 17, 0.4 + near * 0.7)
          else c = hue(s.z / 12 + t, 0.5 + near * 0.6) end
          gfx.line(math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1), c)
          if near > 0.6 then gfx.fill(math.floor(x1), math.floor(y1), 2, 2, c) end
        end
      end
    end
    if sys.millis() - shown < 1800 then gfx.text(4, 4, MODES[mode] .. "  space w s a d q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(10)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("warp: " .. tostring(problem)) end
