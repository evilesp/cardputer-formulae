#!lua
-- waves: a sunset over the open sea. The sun goes down behind the horizon, its light breaks into a glittering path on the water,
-- long swells roll in with foam on their crests, clouds glow pink from below, a sailboat crosses far away, gulls fly by and in
-- the end the stars and the moon come out. space starts the evening again, a and d move the sun, w and s make the sea rougher
-- or calmer, q quits. waves 0.5 starts later in the evening (0 is day, 1 is night). Drawn with few shapes a frame, so it runs smoothly on the Cardputer. Needs the graphics.
-- Run it with --selftest to check the colours of the sky and the perspective of the sea.

local W, H = 240, 135
local HORIZON = 64

local function mix(a, b, t)
  if t <= 0 then return a elseif t >= 1 then return b end
  local function ch(sh) return math.floor(((a >> sh) & 255) + (((b >> sh) & 255) - ((a >> sh) & 255)) * t + 0.5) end
  return (ch(16) << 16) | (ch(8) << 8) | ch(0)
end

-- the colours of the evening: time 0 the sun is high, 1 is night. Four stops for the top of the sky, the horizon and the sea.
local SKY_TOP = { 0x2c6cc0, 0x3a3c8a, 0x1a1440, 0x03040c }
local SKY_LOW = { 0xb8dcf4, 0xffa048, 0xa83a5a, 0x101834 }
local SEA_FAR = { 0x5a8cb8, 0xc87a5a, 0x5a2e4a, 0x0a1428 }
local SEA_NEAR = { 0x0e3050, 0x16304c, 0x0e1a30, 0x02050c }
local function stop(stops, t)
  local x = math.max(0, math.min(1, t)) * 3
  local i = math.min(2, math.floor(x))
  return mix(stops[i + 1], stops[i + 2], x - i)
end

-- the distance of the water at a screen row below the horizon (1 at the bottom, larger further away)
local function distanceAt(y)
  return (H - HORIZON) / math.max(1, y - HORIZON)
end

local function noise(n)
  local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
  return x - math.floor(x)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(stop(SKY_TOP, 0) == SKY_TOP[1] and stop(SKY_TOP, 1) == SKY_TOP[4], "the sky runs from day to night")
  check(stop(SKY_LOW, -1) == SKY_LOW[1] and stop(SKY_LOW, 2) == SKY_LOW[4], "the time is limited")
  check(mix(0, 0xffffff, 0.5) == 0x808080 and mix(1, 2, -1) == 1, "mixing")
  check(distanceAt(H) == 1 and distanceAt(HORIZON + 1) > distanceAt(HORIZON + 10), "the water is further away near the horizon")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("waves needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end

-- made once: the stars, the clouds and the rows of the sea with their distance
local stars = {}
for i = 1, 60 do stars[i] = { x = math.floor(noise(i) * W), y = math.floor(noise(i + 99) * (HORIZON - 6)), p = noise(i + 7) * 6.28 } end
local clouds = {}
for i = 1, 5 do clouds[i] = { x = noise(i * 3) * W, y = 10 + noise(i * 5) * 34, len = 30 + noise(i * 7) * 50, v = 0.05 + noise(i) * 0.08 } end
local rows = {}
for y = HORIZON + 1, H - 1 do rows[#rows + 1] = { y = y, d = distanceAt(y), f = (y - HORIZON) / (H - HORIZON) } end

if not gfx.open() then
  print("waves: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local tod, rough, sunX, t, shown = math.max(0, math.min(1, tonumber(arg[1] or "") or 0)), 1.0, 150, 0, sys.millis()
  local boatX = -20
  local gulls = { { x = -10, y = 22, v = 0.6 }, { x = -60, y = 34, v = 0.45 }, { x = -110, y = 28, v = 0.55 } }
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then tod = 0 shown = sys.millis()
      elseif k == "a" or k == "left" then sunX = math.max(40, sunX - 15)
      elseif k == "d" or k == "right" then sunX = math.min(200, sunX + 15)
      elseif k == "w" or k == "up" then rough = math.min(2.2, rough + 0.3)
      elseif k == "s" or k == "down" then rough = math.max(0.3, rough - 0.3) end
      k = key.poll()
    end
    t = t + 0.05
    tod = math.min(1, tod + 0.0005)
    local top, low = stop(SKY_TOP, tod), stop(SKY_LOW, tod)
    local seaFar, seaNear = stop(SEA_FAR, tod), stop(SEA_NEAR, tod)
    local sunY = 22 + tod * 1.35 * (HORIZON - 22)
    local sunCol = mix(0xfff6d0, 0xff6a28, math.min(1, tod * 1.6))
    local light = math.max(0, 1 - tod * 1.15)  -- how strong the sun's light still is
    -- the sky: smooth bands, warmer near the horizon and around the sun
    for y = 0, HORIZON - 1, 3 do
      gfx.fill(0, y, W, 3, mix(top, low, (y / HORIZON) ^ 1.7))
    end
    -- the stars and the moon at night
    if tod > 0.55 then
      local a = math.min(1, (tod - 0.55) * 2.5)
      for _, s in ipairs(stars) do
        gfx.pixel(s.x, s.y, mix(low, 0xffffff, a * (0.55 + 0.45 * math.sin(t * 2 + s.p))))
      end
      local my = math.floor(30 - (tod - 0.55) * 30)
      local skyMoon = mix(top, low, (my / HORIZON) ^ 1.7)
      gfx.disc(48, my, 7, mix(skyMoon, 0xe8ecd8, a))
      gfx.disc(51, my - 2, 6, skyMoon)  -- the dark part of the crescent is the sky behind it
    end
    -- the sun with its glow, setting behind the horizon (the sea is drawn over it)
    if sunY < HORIZON + 12 then
      -- the glow: soft rings that fade out as the light goes
      for r = 22, 12, -3 do
        local skyThere = mix(top, low, (math.max(0, math.min(HORIZON, sunY)) / HORIZON) ^ 1.7)
        gfx.disc(sunX, math.floor(sunY), r, mix(skyThere, sunCol, ((22 - r) / 22) * 0.45 * light))
      end
      gfx.disc(sunX, math.floor(sunY), 10, sunCol)
      gfx.disc(sunX - 2, math.floor(sunY) - 2, 6, mix(sunCol, 0xffffff, 0.35 * light))
    end
    -- long thin clouds, lit from below by the sun
    for _, c in ipairs(clouds) do
      c.x = c.x + c.v
      if c.x > W + 40 then c.x = -c.len - 20 end
      local under = mix(mix(low, 0xff8ab0, 0.5), 0x1a1830, tod * 0.9)
      local body = mix(mix(top, 0xe0d8e8, 0.35), 0x14142a, tod)
      local cx, cy = math.floor(c.x), math.floor(c.y)
      gfx.fill(cx + 6, cy - 2, math.floor(c.len * 0.6), 2, body)
      gfx.fill(cx, cy, math.floor(c.len), 2, body)
      gfx.fill(cx + 4, cy + 2, math.floor(c.len) - 8, 1, under)
    end
    -- the sea: lighter far away (the sky in it), darker near, each row its own shade
    for _, r in ipairs(rows) do
      local f = r.f
      gfx.hline(0, W - 1, r.y, mix(seaFar, seaNear, f ^ 0.6))
    end
    gfx.hline(0, W - 1, HORIZON, mix(low, 0xffffff, 0.25 * light))
    -- a headland far away on the left, and a sailboat crossing the horizon
    gfx.triangle(0, HORIZON, 0, HORIZON - 7, 46, HORIZON, mix(0x1a2030, 0x050608, tod))
    gfx.triangle(20, HORIZON, 34, HORIZON - 4, 60, HORIZON, mix(0x222838, 0x050608, tod))
    boatX = boatX + 0.08
    if boatX > W + 20 then boatX = -20 end
    local bx = math.floor(boatX)
    gfx.fill(bx - 4, HORIZON - 1, 9, 1, 0x101018)
    gfx.triangle(bx, HORIZON - 10, bx, HORIZON - 2, bx + 5, HORIZON - 2, mix(0xd8d4c8, 0x202028, tod))
    gfx.triangle(bx - 1, HORIZON - 8, bx - 1, HORIZON - 2, bx - 4, HORIZON - 2, mix(0xc0bcb0, 0x1a1a22, tod))
    -- the ripples: short light strokes that get longer and further apart closer to you, moving with the waves
    for i = 1, #rows, 2 do
      local r = rows[i]
      local len = math.floor(2 + r.f * 14)
      local gap = math.floor(18 + r.f * 40)
      local shift = math.floor((t * (6 + r.f * 20) + i * 7) % gap)
      local c = mix(mix(seaFar, seaNear, r.f ^ 0.6), mix(low, 0xc8e0f0, 0.4), 0.35 * (1 - r.f * 0.5))
      for x = -gap + shift, W, gap do
        local wob = math.floor((noise(i * 31 + x // gap) - 0.5) * gap * 0.5)
        gfx.hline(x + wob, x + wob + len, r.y, c)
      end
    end
    -- the path of the sun's light: bright glints, many and narrow far away, wider and fewer near you
    if light > 0.02 and sunY < HORIZON + 8 then
      for i = 1, #rows do
        local r = rows[i]
        local spread = 3 + r.f * 46
        local n = r.f < 0.3 and 2 or 3
        for g = 1, n do
          local seed = noise(i * 13.7 + g * 5.3 + math.floor(t * 3 + g + i * 0.5))
          if seed > 0.25 then
            local gx = sunX + (noise(i * 7.1 + g + math.floor(t * 2.5)) - 0.5) * 2 * spread
            local glen = math.floor(1 + r.f * 9 * seed)
            gfx.hline(math.floor(gx - glen / 2), math.floor(gx + glen / 2), r.y, mix(sunCol, 0xffffff, 0.3 * seed) )
          end
        end
      end
    end
    -- the near swells: dark troughs and foam on the crests
    for layer = 1, 2 do
      local base = H - 26 + layer * 10
      local amp = (2 + layer * 1.6) * rough
      local trough = mix(seaNear, 0x000000, 0.25 + layer * 0.1)
      for x = 0, W - 1, 4 do
        local y = base + amp * math.sin(x * 0.045 + t * (0.9 + layer * 0.4) + layer * 2) + amp * 0.4 * math.sin(x * 0.12 - t * 1.3)
        local yy = math.floor(y)
        gfx.fill(x, yy, 4, H - yy, trough)
        local crest = math.sin(x * 0.045 + t * (0.9 + layer * 0.4) + layer * 2)
        if crest > 0.6 then gfx.fill(x, yy, 4, 1, mix(trough, 0xe8f0f8, 0.55 * (1 - tod * 0.6))) end
      end
    end
    -- the gulls in the early evening
    if tod < 0.7 then
      for _, g in ipairs(gulls) do
        g.x = g.x + g.v
        if g.x > W + 20 then g.x = -40 end
        local flap = math.floor(math.sin(t * 5 + g.y) * 2)
        local gx, gy = math.floor(g.x), math.floor(g.y + math.sin(t + g.x * 0.05) * 3)
        gfx.line(gx - 5, gy + flap, gx - 2, gy, 0x14161e)
        gfx.line(gx - 2, gy, gx, gy + 1, 0x14161e)
        gfx.line(gx, gy + 1, gx + 2, gy, 0x14161e)
        gfx.line(gx + 2, gy, gx + 5, gy + flap, 0x14161e)
      end
    end
    if sys.millis() - shown < 1800 then gfx.text(4, 4, "space a d w s q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("waves: " .. tostring(problem)) end
