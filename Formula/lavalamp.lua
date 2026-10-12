#!lua
-- lavalamp: a lava lamp. Blobs of warm wax rise, merge, split and sink in a glowing glass. space changes the colour of the wax
-- and the light, w and s make the blobs move faster or slower, q quits. Needs the graphics (firmware v0.1.0.13).
-- Run it with --selftest to check the field.

local W, H = 240, 135
local CELL = 5
local COLS, ROWS = W // CELL, H // CELL
local BLOBS = 7

local THEMES = {
  { name = "lava", bg = { 0x300818, 0x601020 }, edge = 0xff5020, core = 0xffd060 },
  { name = "toxic", bg = { 0x062010, 0x0c4020 }, edge = 0x30d050, core = 0xe0ff70 },
  { name = "ocean", bg = { 0x061030, 0x0c2060 }, edge = 0x2090ff, core = 0x90f0ff },
  { name = "candy", bg = { 0x200830, 0x401060 }, edge = 0xd040d0, core = 0xffb0f0 },
}

-- one colour between a and b (t from 0 to 1); no closure inside: it runs hundreds of times a frame
local function mix(a, b, t)
  if t <= 0 then return a elseif t >= 1 then return b end
  local ar, ag, ab = (a >> 16) & 255, (a >> 8) & 255, a & 255
  return (math.floor(ar + (((b >> 16) & 255) - ar) * t + 0.5) << 16) | (math.floor(ag + (((b >> 8) & 255) - ag) * t + 0.5) << 8)
    | math.floor(ab + ((b & 255) - ab) * t + 0.5)
end

-- the strength of the field at a point: each blob adds r^2 / d^2 (a metaball). Wax is where the sum is at least 1.
local function field(blobs, x, y)
  local s = 0
  for i = 1, #blobs do
    local b = blobs[i]
    local dx, dy = x - b.x, y - b.y
    s = s + b.r * b.r / (dx * dx + dy * dy + 1)
  end
  return s
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local one = { { x = 10, y = 10, r = 5 } }
  check(field(one, 10, 10) > 20 and field(one, 10, 20) < 0.5, "the field is strong inside and weak outside")
  check(field(one, 15, 10) > 0.9 and field(one, 16, 10) < 0.9, "the edge is about one radius out")
  local two = { { x = 10, y = 10, r = 5 }, { x = 18, y = 10, r = 5 } }
  check(field(two, 14, 10) > 1, "two near blobs join between them")
  check(mix(0, 0xffffff, 0.5) == 0x808080, "mixing")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("lavalamp needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("lavalamp: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local blobs = {}
  for i = 1, BLOBS do
    blobs[i] = { x = 75 + math.random() * 90, y = math.random() * H, r = 8 + math.random() * 7, vy = (math.random() - 0.5) * 0.8,
                 ph = math.random() * 6.28 }
  end
  local ti, speed, shown, t = 1, 1.0, sys.millis(), 0
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then ti = ti % #THEMES + 1 shown = sys.millis()
      elseif k == "w" or k == "up" then speed = math.min(3, speed + 0.4)
      elseif k == "s" or k == "down" then speed = math.max(0.2, speed - 0.4) end
      k = key.poll()
    end
    t = t + 0.02 * speed
    for _, b in ipairs(blobs) do
      -- a blob warms at the bottom and rises, cools at the top and sinks; it sways from side to side
      local warmth = (b.y / H)  -- 0 at the top, 1 at the bottom
      b.vy = b.vy + (0.5 - warmth) * 0.03 * speed
      b.vy = b.vy * 0.985
      b.y = b.y + b.vy * speed
      if b.y < 10 then b.y, b.vy = 10, math.abs(b.vy) elseif b.y > H - 10 then b.y, b.vy = H - 10, -math.abs(b.vy) end
      b.x = 120 + (b.x - 120) * 0.999 + math.sin(t + b.ph) * 0.35
      b.x = math.max(72, math.min(W - 72, b.x))
    end
    local th = THEMES[ti]
    for r = 0, ROWS - 1 do
      local y = r * CELL + CELL / 2
      local bg = mix(th.bg[1], th.bg[2], r / ROWS)
      for c = 0, COLS - 1 do
        local v = field(blobs, c * CELL + CELL / 2, y)
        local colour
        if v >= 1 then colour = mix(th.edge, th.core, (v - 1) / 2.5) else colour = mix(bg, th.edge, (v - 0.55) * 1.2) end
        if v > 0.55 or true then gfx.fill(c * CELL, r * CELL, CELL, CELL, colour) end
      end
    end
    -- the glass: dark sides, a highlight, a cap and a base
    gfx.fill(0, 0, 60, H, 0x05050a)
    gfx.fill(W - 60, 0, 60, H, 0x05050a)
    gfx.vline(60, 0, H, 0x3a3a50)
    gfx.vline(W - 61, 0, H, 0x3a3a50)
    gfx.vline(68, 6, H - 6, mix(0x05050a, 0xa0a8c0, 0.35))
    gfx.fill(60, 0, W - 120, 5, 0x20202c)
    gfx.fill(60, H - 5, W - 120, 5, 0x20202c)
    if sys.millis() - shown < 1800 then gfx.text(4, 4, THEMES[ti].name .. "  space w s q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("lavalamp: " .. tostring(problem)) end
