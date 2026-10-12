#!lua
-- waves: a sunset over the ocean. The sun sinks slowly, the sky changes from gold to purple to night, layers of waves roll by
-- and the sun leaves a trail of light on the water; seagulls fly across in the evening and stars come out at the end. space
-- sets the time of day back to the beginning, a and d move the sun along, w and s make the sea rougher or calmer, q quits.
-- Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the colours of the sky.

local W, H = 240, 135
local HORIZON = 62

local function mix(a, b, t)
  t = math.max(0, math.min(1, t))
  local function ch(sh) return math.floor(((a >> sh) & 255) + (((b >> sh) & 255) - ((a >> sh) & 255)) * t + 0.5) end
  return (ch(16) << 16) | (ch(8) << 8) | ch(0)
end

-- the colour of the sky at the top and at the horizon for a time of day 0 (the sun high) to 1 (night)
local SKY_TOP = { 0x2a78d0, 0x5a4a9a, 0x14103a, 0x02030c }
local SKY_LOW = { 0xa8d8f8, 0xff9048, 0x7a2858, 0x0c1430 }
local function sky(t, stops)
  local x = math.max(0, math.min(1, t)) * 3
  local i = math.min(2, math.floor(x))
  return mix(stops[i + 1], stops[i + 2], x - i)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(sky(0, SKY_TOP) == 0x2a78d0 and sky(1, SKY_TOP) == 0x02030c, "the sky runs from day to night")
  check(sky(-1, SKY_LOW) == SKY_LOW[1] and sky(2, SKY_LOW) == SKY_LOW[4], "the time is limited")
  check(mix(0, 0xffffff, 0.5) == 0x808080, "mixing")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("waves needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("waves: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local tod, rough, sunX, shown, t = 0.0, 1.0, 150, sys.millis(), 0
  local gulls = { { x = -20, y = 18, v = 0.7 }, { x = -70, y = 30, v = 0.5 } }
  local stars = {}
  for i = 1, 50 do stars[i] = { x = math.random(0, W - 1), y = math.random(0, HORIZON - 4) } end
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
    tod = math.min(1, tod + 0.0006)
    local top, low = sky(tod, SKY_TOP), sky(tod, SKY_LOW)
    for y = 0, HORIZON, 4 do gfx.fill(0, y, W, 4, mix(top, low, (y / HORIZON) ^ 1.6)) end
    if tod > 0.6 then
      for _, s in ipairs(stars) do gfx.pixel(s.x, s.y, mix(low, 0xffffff, math.min(1, (tod - 0.6) * 2.5) * (0.6 + 0.4 * math.sin(t + s.x)))) end
    end
    -- the sun: it sinks behind the horizon as the time goes
    local sunY = 24 + tod * 1.25 * (HORIZON - 24) + 6
    local glow = mix(low, 0xffe8a0, 0.35)
    for r = 26, 10, -4 do gfx.disc(sunX, math.floor(sunY), r, mix(sky(tod, SKY_LOW), 0xffb060, (26 - r) / 40 * (1 - tod * 0.5))) end
    gfx.disc(sunX, math.floor(sunY), 9, mix(0xfff4c0, 0xff7030, tod))
    -- the sea below the horizon: the sky's colour at the horizon, darker below
    local deep = mix(0x0a2848, 0x02060e, tod)
    gfx.fill(0, HORIZON, W, H - HORIZON, deep)
    gfx.fill(0, HORIZON - 1, W, 1, mix(low, 0xffffff, 0.15))
    -- the shape of the sun covered by the sea
    gfx.fill(sunX - 28, HORIZON, 56, 1, deep)
    -- the trail of light on the water: short bright strokes, narrower with the distance
    local trail = math.max(0, 1 - tod * 0.8)
    for y = HORIZON + 2, H - 1, 2 do
      local f = (y - HORIZON) / (H - HORIZON)
      local half = 4 + f * 34
      local wob = math.sin(y * 0.9 + t * 3) * (2 + f * 4)
      local c = mix(deep, mix(0xffd070, 0xff6040, tod), trail * (0.85 - f * 0.45) * (0.6 + 0.4 * math.sin(y * 2 + t * 4)))
      gfx.hline(math.floor(sunX + wob - half), math.floor(sunX + wob + half), y, c)
    end
    -- the layers of waves: the far ones small, the near ones large
    for layer = 1, 4 do
      local base = HORIZON + 8 + layer * 14
      local amp = (1 + layer * 1.2) * rough
      local colour = mix(mix(0x1a4a78, 0x04101c, tod), mix(0x06182c, 0x010308, tod), layer / 4)
      for x = 0, W - 1, 3 do
        local y = base + amp * math.sin(x * (0.05 + layer * 0.01) + t * (0.8 + layer * 0.3) + layer * 2)
          + amp * 0.4 * math.sin(x * 0.13 - t * 1.4)
        gfx.fill(x, math.floor(y), 3, H - math.floor(y), colour)
        if (x // 3 + layer) % 5 == 0 then gfx.fill(x, math.floor(y), 3, 1, mix(colour, 0xe8f0ff, 0.35 * (1 - tod))) end
      end
    end
    -- the seagulls, in the first half of the evening
    if tod < 0.7 then
      for _, g in ipairs(gulls) do
        g.x = g.x + g.v
        if g.x > W + 20 then g.x = -30 end
        local flap = math.sin(t * 5 + g.y) * 2
        local gx, gy = math.floor(g.x), math.floor(g.y + math.sin(t + g.x * 0.05) * 3)
        gfx.line(gx - 5, gy + math.floor(flap), gx, gy, 0x10141c)
        gfx.line(gx, gy, gx + 5, gy + math.floor(flap), 0x10141c)
      end
    end
    if sys.millis() - shown < 1800 then gfx.text(4, 4, "space a d w s q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("waves: " .. tostring(problem)) end
