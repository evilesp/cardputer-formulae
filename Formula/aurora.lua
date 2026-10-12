#!lua
-- aurora: the northern lights over snowy mountains under a field of twinkling stars. The curtains of light wave slowly. space
-- changes the colours (green, violet, red, blue), w and s make the lights stronger or weaker, q quits. Needs the graphics.
-- Run it with --selftest to check the mixing.

local W, H = 240, 135
local HORIZON = 100

local function mix(a, b, t)
  t = math.max(0, math.min(1, t))
  local function ch(sh) return math.floor(((a >> sh) & 255) + (((b >> sh) & 255) - ((a >> sh) & 255)) * t + 0.5) end
  return (ch(16) << 16) | (ch(8) << 8) | ch(0)
end

local THEMES = {
  { name = "green", { 0x30ff90, 0x20d0b0 }, { 0x2080ff, 0x60e0ff } },
  { name = "violet", { 0xb050ff, 0xf070e0 }, { 0x4060ff, 0x30d0ff } },
  { name = "red", { 0xff3050, 0xff9040 }, { 0xa030ff, 0xff60c0 } },
  { name = "blue", { 0x30a0ff, 0x30ffe0 }, { 0x6030ff, 0x30c0ff } },
}

-- a ridge of mountains: the height above the horizon at each column, from a sum of sines
local function ridge(seed)
  local h = {}
  for x = 0, W - 1 do
    h[x] = 16 + 7 * math.sin(x * 0.045 + seed) + 5 * math.sin(x * 0.11 + seed * 2.3) + 3 * math.sin(x * 0.27 + seed * 0.7)
  end
  return h
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(mix(0, 0xffffff, 0.5) == 0x808080 and mix(0x102030, 0x102030, 1) == 0x102030, "mixing")
  check(mix(0, 0xffffff, 2) == 0xffffff and mix(0, 0xffffff, -1) == 0, "mixing is limited to the two colours")
  local r = ridge(1)
  local lo, hi = 1e9, -1e9
  for x = 0, W - 1 do
    lo, hi = math.min(lo, r[x]), math.max(hi, r[x])
  end
  check(lo > -5 and hi < 40, "the ridge stays inside the picture")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("aurora needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end

local stars = {}
for i = 1, 70 do stars[i] = { x = math.random(0, W - 1), y = math.random(0, HORIZON - 12), p = math.random() * 6.28 } end
local far, near = ridge(1.7), ridge(4.1)

if not gfx.open() then
  print("aurora: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local theme, power, t, shown = 1, 1.0, 0, sys.millis()
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then theme = theme % #THEMES + 1 shown = sys.millis()
      elseif k == "w" or k == "up" then power = math.min(1.6, power + 0.15)
      elseif k == "s" or k == "down" then power = math.max(0.3, power - 0.15) end
      k = key.poll()
    end
    t = t + 0.03
    -- the sky: dark blue at the top, a little lighter at the horizon
    for y = 0, HORIZON, 5 do gfx.fill(0, y, W, 5, mix(0x02040c, 0x0c1c34, y / HORIZON)) end
    for _, s in ipairs(stars) do
      local v = 0.45 + 0.55 * math.sin(t * 2 + s.p)
      local c = mix(0x202838, 0xffffff, v)
      gfx.pixel(s.x, s.y, c)
      if v > 0.9 then gfx.pixel(s.x + 1, s.y, c) end
    end
    -- the curtains: for each column a band of light between a top and a bottom edge that wave, fading upwards
    local th = THEMES[theme]
    for x = 0, W - 1, 2 do
      for band = 1, 2 do
        local base = 38 + band * 12
        local top = base + 14 * math.sin(x * 0.03 + t * 0.7 + band * 2) + 8 * math.sin(x * 0.09 - t * 1.1 + band)
        local height = (20 + 16 * math.sin(x * 0.05 + t * 0.5 + band * 1.7)) * power
        local strength = 0.45 + 0.45 * math.sin(x * 0.07 + t + band)
        if strength > 0.1 then
          local steps = 5
          for s = 0, steps - 1 do
            local f = s / steps
            local c = mix(th[band][1], th[band][2], f)
            local fade = (1 - f) * (1 - f) * strength * power
            gfx.fill(x, math.floor(top + height * f), 2, math.ceil(height / steps) + 1, mix(0x060c1c, c, fade * 0.85))
          end
        end
      end
    end
    -- the mountains, snow on the far ones
    for x = 0, W - 1 do
      local hf = HORIZON - far[x]
      gfx.vline(x, math.floor(hf), H, 0x1c2a40)
      gfx.pixel(x, math.floor(hf), 0xcfd8e8)
      local hn = HORIZON + 10 - near[x]
      gfx.vline(x, math.floor(hn), H, 0x070b14)
    end
    if sys.millis() - shown < 1800 then gfx.text(4, 4, THEMES[theme].name .. "  space w s q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(10)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("aurora: " .. tostring(problem)) end
