#!lua
-- fireworks: rockets climb into the night over a city skyline and burst into coloured stars that fall with sparkling trails,
-- and the water below shows their reflection. space launches a rocket now (a few go by themselves), w and s change how often
-- they come, a and d move the launch place, q quits. Needs the graphics (firmware v0.1.0.13).
-- Run it with --selftest to check the bursts.

local W, H = 240, 135
local SEA = 108
local GRAVITY = 0.06

local function hue(h, v)
  h = (h % 1) * 6
  local i, f = math.floor(h), h - math.floor(h)
  local r, g, b
  if i == 0 then r, g, b = 1, f, 0 elseif i == 1 then r, g, b = 1 - f, 1, 0 elseif i == 2 then r, g, b = 0, 1, f
  elseif i == 3 then r, g, b = 0, 1 - f, 1 elseif i == 4 then r, g, b = f, 0, 1 else r, g, b = 1, 0, 1 - f end
  v = math.max(0, math.min(1, v))
  return (math.floor(r * v * 255) << 16) | (math.floor(g * v * 255) << 8) | math.floor(b * v * 255)
end

-- the stars of a burst: shape 1 is a ball, 2 a ring, 3 a heart
local function burst(x, y, shape, h)
  local out = {}
  local n = shape == 1 and 44 or 36
  for i = 1, n do
    local a = i / n * math.pi * 2
    local vx, vy, speed
    if shape == 2 then
      speed = 2.1
      vx, vy = math.cos(a) * speed, math.sin(a) * speed
    elseif shape == 3 then  -- the heart curve
      local px = 16 * math.sin(a) ^ 3
      local py = -(13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a))
      vx, vy = px * 0.15, py * 0.15
    else
      speed = 0.8 + math.random() * 1.7
      vx, vy = math.cos(a) * speed, math.sin(a) * speed
    end
    out[#out + 1] = { x = x, y = y, vx = vx, vy = vy, life = 1, h = h + math.random() * 0.06 }
  end
  return out
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(#burst(0, 0, 1, 0) == 44 and #burst(0, 0, 2, 0) == 36 and #burst(0, 0, 3, 0) == 36, "stars in each shape")
  local ring = burst(10, 10, 2, 0)
  local r = math.sqrt(ring[1].vx ^ 2 + ring[1].vy ^ 2)
  check(math.abs(r - 2.1) < 1e-9, "a ring has one speed")
  local heart = burst(0, 0, 3, 0)
  local top, bottom = 1e9, -1e9
  for _, p in ipairs(heart) do
    top, bottom = math.min(top, p.vy), math.max(bottom, p.vy)
  end
  check(top < -1.5 and bottom > 1.5, "a heart is tall")
  check(hue(0, 1) == 0xff0000 and hue(0, 2) == 0xff0000 and hue(0, -1) == 0, "colours are limited")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("fireworks needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("fireworks: cannot take the screen")
  return
end

-- the skyline, made once: building widths and heights
local skyline = {}
do
  local x = 0
  while x < W do
    local w = 10 + math.random(0, 14)
    skyline[#skyline + 1] = { x = x, w = w, h = 12 + math.random(0, 26) }
    x = x + w
  end
end

local ok, problem = pcall(function()
  local rockets, sparks, shown = {}, {}, sys.millis()
  local launchX, rate = W / 2, 1.0
  local nextAuto = sys.millis() + 700
  local function launch()
    local x = math.max(30, math.min(W - 30, launchX + math.random(-50, 50)))
    rockets[#rockets + 1] = { x = x, y = SEA, vy = -(3.4 + math.random() * 1.4), vx = (math.random() - 0.5) * 0.5, h = math.random(),
                              shape = math.random() < 0.2 and 3 or (math.random() < 0.3 and 2 or 1) }
  end
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then launch()
      elseif k == "w" or k == "up" then rate = math.min(3, rate + 0.5)
      elseif k == "s" or k == "down" then rate = math.max(0.3, rate - 0.5)
      elseif k == "a" or k == "left" then launchX = math.max(40, launchX - 25)
      elseif k == "d" or k == "right" then launchX = math.min(W - 40, launchX + 25) end
      k = key.poll()
    end
    if sys.millis() >= nextAuto then
      launch()
      nextAuto = sys.millis() + (900 + math.random(0, 1800)) / rate
    end
    -- the sky, the sea and the skyline
    gfx.clear(0x02030a)
    for y = 0, SEA, 6 do gfx.fill(0, y, W, 6, y > 60 and 0x0a0f22 or 0x040612) end
    gfx.fill(0, SEA, W, H - SEA, 0x050a18)
    for _, b in ipairs(skyline) do
      gfx.fill(b.x, SEA - b.h, b.w - 1, b.h, 0x0c101c)
      for wy = SEA - b.h + 3, SEA - 4, 6 do
        for wx = b.x + 2, b.x + b.w - 5, 5 do
          if (wx * 3 + wy * 5) % 7 < 3 then gfx.fill(wx, wy, 2, 2, 0xa88c40) end
        end
      end
    end
    -- the rockets
    local live = {}
    for _, r in ipairs(rockets) do
      r.y = r.y + r.vy
      r.x = r.x + r.vx
      r.vy = r.vy + 0.04
      if r.vy >= -0.3 or r.y < 22 then
        for _, p in ipairs(burst(r.x, r.y, r.shape, r.h)) do sparks[#sparks + 1] = p end
        gfx.fill(0, 0, W, H, 0x101830)  -- the flash of the burst
      else
        gfx.line(math.floor(r.x), math.floor(r.y), math.floor(r.x - r.vx * 3), math.floor(r.y - r.vy * 3), 0xffd890)
        live[#live + 1] = r
      end
    end
    rockets = live
    -- the stars of the bursts
    local keep = {}
    for _, p in ipairs(sparks) do
      p.vy = p.vy + GRAVITY
      p.vx = p.vx * 0.985
      p.vy = p.vy * 0.985
      p.x = p.x + p.vx
      p.y = p.y + p.vy
      p.life = p.life - 0.010
      if p.life > 0 and p.y < SEA then
        local c = hue(p.h, math.min(1, p.life * 2))
        local size = p.life > 0.45 and 3 or 2
        gfx.fill(math.floor(p.x) - 1, math.floor(p.y) - 1, size, size, c)
        gfx.line(math.floor(p.x - p.vx * 2), math.floor(p.y - p.vy * 2), math.floor(p.x), math.floor(p.y), hue(p.h, p.life * 0.7))
        -- the reflection in the water, dimmer and stretched
        if p.life > 0.15 then gfx.pixel(math.floor(p.x), SEA + (SEA - math.floor(p.y)) // 2, hue(p.h, p.life * 0.45)) end
        keep[#keep + 1] = p
      end
    end
    sparks = keep
    if #sparks > 400 then
      for _ = 1, #sparks - 400 do table.remove(sparks, 1) end
    end
    if sys.millis() - shown < 1800 then gfx.text(4, 4, "space w s a d q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("fireworks: " .. tostring(problem)) end
