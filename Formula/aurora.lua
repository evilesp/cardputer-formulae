#!lua
-- aurora: the northern lights over a frozen lake. Curtains of thin rays sway and ripple across the sky, green at the bottom and
-- pink or violet at the top, and the lake below mirrors them; stars twinkle, a shooting star crosses now and then, and pine
-- trees stand dark against the snow. space changes the colours (green, violet, red, blue), w and s make the lights stronger or
-- weaker, q quits. Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the colours and the curtain.

local W, H = 240, 135
local HORIZON = 92   -- the shore of the lake
local LAKE = 100     -- the top of the water

-- one colour between a and b (t from 0 to 1); no closure inside: it runs hundreds of times a frame
local function mix(a, b, t)
  if t <= 0 then return a elseif t >= 1 then return b end
  local ar, ag, ab = (a >> 16) & 255, (a >> 8) & 255, a & 255
  return (math.floor(ar + (((b >> 16) & 255) - ar) * t + 0.5) << 16) | (math.floor(ag + (((b >> 8) & 255) - ag) * t + 0.5) << 8)
    | math.floor(ab + ((b & 255) - ab) * t + 0.5)
end

-- the colours of a theme: the bottom of the rays, their middle and their top
local THEMES = {
  { name = "green", 0x40ff9a, 0x30d8c0, 0xc060e0 },
  { name = "violet", 0xc070ff, 0x7080ff, 0xff70c0 },
  { name = "red", 0xff4a60, 0xff9a50, 0xb050ff },
  { name = "blue", 0x40b8ff, 0x40ffe0, 0x8060ff },
}

local function noise(n)
  local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
  return x - math.floor(x)
end

-- the curtain at column x and time t: the height of its lower edge, how long its rays are and how bright (0 .. 1)
local function curtain(x, t, layer)
  local edge = 44 + layer * 8 + 9 * math.sin(x * 0.025 + t * 0.35 + layer) + 5 * math.sin(x * 0.07 - t * 0.6 + layer * 2)
  local length = 24 + 12 * math.sin(x * 0.04 + t * 0.25 + layer * 1.3)
  -- the folds: bright where the curtain turns towards you, with fine rays moving sideways
  local fold = 0.5 + 0.5 * math.sin(x * 0.05 + t * 0.4 + layer * 3)
  local ray = math.min(1, 0.35 + 0.65 * math.abs(math.sin(x * 0.9 + t * 1.7) * math.sin(x * 0.23 - t * 0.8) + 0.3 * math.sin(x * 2.3 + t)))
  return edge, length, math.max(0, math.min(1, fold * 0.8 + 0.2)) * ray
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(mix(0, 0xffffff, 0.5) == 0x808080 and mix(0x102030, 0x405060, 0) == 0x102030, "mixing")
  local lowest, highest, okBright = 1e9, -1e9, true
  for x = 0, W - 1 do
    for _, t in ipairs({ 0, 3.3, 17 }) do
      local e, l, b = curtain(x, t, 1)
      lowest, highest = math.min(lowest, e), math.max(highest, e - l)
      if b < 0 or b > 1 then okBright = false end
    end
  end
  check(lowest > 20 and lowest < HORIZON and highest > 0, "the curtain stays in the sky")
  check(okBright, "the brightness is 0 to 1")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("aurora needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end

-- made once: the stars, the far mountains with snow, and the trees on the shore
local stars = {}
for i = 1, 90 do
  stars[i] = { x = math.floor(noise(i) * W), y = math.floor(noise(i + 50) * (HORIZON - 30)), p = noise(i + 9) * 6.28,
               c = ({ 0xffffff, 0xcfe0ff, 0xfff0d0 })[i % 3 + 1], big = noise(i + 3) > 0.9 }
end
local ridge = {}
for x = 0, W - 1 do
  ridge[x] = math.floor(HORIZON - 7 - 6 * math.sin(x * 0.03 + 1.2) - 4 * math.sin(x * 0.09 + 0.4) - 2 * math.abs(math.sin(x * 0.21)))
end
local trees = {}
for i = 1, 22 do trees[i] = { x = math.floor(noise(i * 1.7) * W), h = 8 + math.floor(noise(i * 2.3) * 12) } end

if not gfx.open() then
  print("aurora: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local theme, power, t, shown = 1, 1.0, 0, sys.millis()
  local shooting, nextShoot = nil, sys.millis() + 4000
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then theme = theme % #THEMES + 1 shown = sys.millis()
      elseif k == "w" or k == "up" then power = math.min(1.6, power + 0.15)
      elseif k == "s" or k == "down" then power = math.max(0.3, power - 0.15) end
      k = key.poll()
    end
    t = t + 0.04
    local th = THEMES[theme]
    -- the night sky, a little lighter at the horizon and tinted by the lights
    local glow = mix(0x0a1424, th[1], 0.08 * power)
    for y = 0, HORIZON, 4 do gfx.fill(0, y, W, 4, mix(0x02040a, glow, (y / HORIZON) ^ 1.5)) end
    for _, s in ipairs(stars) do
      local v = 0.5 + 0.5 * math.sin(t * 3 + s.p)
      gfx.pixel(s.x, s.y, mix(0x10182a, s.c, v))
      if s.big and v > 0.8 then
        gfx.pixel(s.x - 1, s.y, mix(0x10182a, s.c, 0.4))
        gfx.pixel(s.x + 1, s.y, mix(0x10182a, s.c, 0.4))
      end
    end
    -- a shooting star now and then
    if not shooting and sys.millis() > nextShoot then
      shooting = { x = 30 + noise(t) * 150, y = 8 + noise(t + 1) * 20, life = 1 }
      nextShoot = sys.millis() + 5000 + math.floor(noise(t + 2) * 9000)
    end
    if shooting then
      shooting.x, shooting.y, shooting.life = shooting.x + 5, shooting.y + 2, shooting.life - 0.07
      if shooting.life <= 0 then shooting = nil else
        gfx.line(math.floor(shooting.x - 14), math.floor(shooting.y - 6), math.floor(shooting.x), math.floor(shooting.y), mix(0x101828, 0xffffff, shooting.life))
      end
    end
    -- the curtains: thin rays, bright at their lower edge and fading upwards through the theme's colours
    for layer = 2, 1, -1 do
      local strength = (layer == 1 and 1 or 0.55) * power
      for x = 0, W - 1, 2 do
        local edge, length, bright = curtain(x, t, layer)
        local b = bright * strength
        if b > 0.06 then
          local top = edge - length
          local seg = length / 4
          for i = 0, 3 do
            local f = i / 3
            local colour = f < 0.5 and mix(th[1], th[2], f * 2) or mix(th[2], th[3], (f - 0.5) * 2)
            local fade = b * (1 - f) ^ 1.4 * 1.25
            local y = math.floor(edge - (i + 1) * seg)
            gfx.fill(x, y, 2, math.ceil(seg) + 1, mix(glow, colour, math.min(1, fade)))
          end
          gfx.fill(x, math.floor(edge) - 1, 2, 2, mix(glow, mix(th[1], 0xffffff, 0.3), math.min(1, b)))  -- the bright lower edge
        end
      end
    end
    -- the mountains with snow on their tops
    for x = 0, W - 1 do
      gfx.vline(x, ridge[x], LAKE, 0x141c2c)
      gfx.pixel(x, ridge[x], 0xb8c8dc)
      gfx.pixel(x, ridge[x] + 1, 0x8898b0)
    end
    -- the snowy shore and the frozen lake that mirrors the sky: rows of the curtain, upside down and dimmer
    gfx.fill(0, HORIZON, W, LAKE - HORIZON, 0xc0cce0)
    gfx.fill(0, LAKE, W, H - LAKE, 0x060a14)
    for y = LAKE + 1, H - 1, 2 do
      local mirror = LAKE - (y - LAKE) * 2  -- the row of the sky seen in the water there
      for x = 0, W - 1, 6 do
        local edge, length, bright = curtain(x, t, 1)
        if mirror < edge and mirror > edge - length then
          local f = (edge - mirror) / length
          local colour = f < 0.5 and mix(th[1], th[2], f * 2) or mix(th[2], th[3], (f - 0.5) * 2)
          local wob = math.floor(math.sin(y * 0.8 + t * 2) * 2)
          gfx.hline(x + wob, x + wob + 4, y, mix(0x060a14, colour, math.min(1, bright * power * 0.7 * (1 - f) ^ 1.4)))
        end
      end
    end
    -- the pines on the shore, dark against the snow
    for _, tr in ipairs(trees) do
      local bx, by = tr.x, HORIZON + 4
      gfx.triangle(bx, by - tr.h, bx - tr.h // 3, by, bx + tr.h // 3, by, 0x050a0c)
      gfx.triangle(bx, by - tr.h - 3, bx - tr.h // 5, by - tr.h // 2, bx + tr.h // 5, by - tr.h // 2, 0x050a0c)
    end
    if sys.millis() - shown < 1800 then gfx.text(4, 4, THEMES[theme].name .. "  space w s q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("aurora: " .. tostring(problem)) end
