#!lua
-- fire: the doom fire effect, a bed of embers with flames that rise, flicker and die. space changes the colour of the fire
-- (red, blue, green, purple), w and s make it hotter or colder, a and d blow the wind, q quits. Needs the graphics.
-- The heat of every cell is packed eight to a number (8 bits each): a table with one entry per cell took about 32 KB of the
-- Cardputer's memory, and the fire ran out of memory next to the WiFi. Run it with --selftest to check the palette and the spreading.

local W, H = 240, 135
local CELL = 5
local COLS, ROWS = W // CELL, H // CELL
local LEVELS = 40  -- heat 0 (black) to 39 (white)

-- one colour between a and b (t from 0 to 1); no closure inside: it runs hundreds of times a frame
local function mix(a, b, t)
  if t <= 0 then return a elseif t >= 1 then return b end
  local ar, ag, ab = (a >> 16) & 255, (a >> 8) & 255, a & 255
  return (math.floor(ar + (((b >> 16) & 255) - ar) * t + 0.5) << 16) | (math.floor(ag + (((b >> 8) & 255) - ag) * t + 0.5) << 8)
    | math.floor(ab + ((b & 255) - ab) * t + 0.5)
end

-- the palettes: black, the main colour, a bright colour, white
local STOPS = {
  { name = "red", 0x000000, 0xc01800, 0xffb020, 0xffffff },
  { name = "blue", 0x000000, 0x0830c0, 0x40c0ff, 0xffffff },
  { name = "green", 0x000000, 0x108020, 0x70ff40, 0xffffff },
  { name = "purple", 0x000000, 0x6010a0, 0xff40e0, 0xffffff },
}
local function palette(stops)
  local p = {}
  for i = 0, LEVELS - 1 do
    local x = i / (LEVELS - 1) * 3
    local seg = math.min(2, math.floor(x))
    p[i] = mix(stops[seg + 1], stops[seg + 2], x - seg)
  end
  return p
end

-- the heat of cell i (0 .. n-1, row by row from the top), eight cells to a number
local function newHeat(n)
  local h = {}
  for w = 1, (n + 7) // 8 do h[w] = 0 end
  return h
end

local function getHeat(h, i)
  return (h[(i >> 3) + 1] >> ((i & 7) << 3)) & 255
end

local function setHeat(h, i, v)
  local w = (i >> 3) + 1
  local sh = (i & 7) << 3
  h[w] = (h[w] & ~(255 << sh)) | (v << sh)
end

-- one step of the fire: every cell takes the heat of the cell under it, a little less, and a little to the side (the
-- wind). Rows and columns count from 0; the rows are done from the second one down, so a cell moves up only once.
local function step(heat, cols, rows, decay, wind)
  for r = 1, rows - 1 do
    for c = 0, cols - 1 do
      local below = getHeat(heat, r * cols + c)
      if below > 0 then
        local to = c + math.random(0, 2) - 1 + wind
        if to < 0 then to = 0 elseif to > cols - 1 then to = cols - 1 end
        local v = below - math.random(0, decay)
        setHeat(heat, (r - 1) * cols + to, v > 0 and v or 0)
      else
        setHeat(heat, (r - 1) * cols + c, 0)
      end
    end
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
  check(mix(0, 0xffffff, 0.5) == 0x808080 and mix(0xff0000, 0xff0000, 0.3) == 0xff0000, "colour mixing")
  local p = palette(STOPS[1])
  check(p[0] == 0 and p[LEVELS - 1] == 0xffffff, "the palette runs from black to white")
  local cols, rows = 5, 4
  local heat = newHeat(cols * rows)
  for c = 0, cols - 1 do setHeat(heat, (rows - 1) * cols + c, LEVELS - 1) end
  for _ = 1, 3 do step(heat, cols, rows, 3, 0) end
  local top = 0
  for c = 0, cols - 1 do top = top + getHeat(heat, c) end
  check(top > 0, "the heat climbs from the bottom row")
  check(getHeat(heat, 0) <= LEVELS - 1 and getHeat(heat, 1) >= 0, "heat stays in its 8 bits")
  for c = 0, cols - 1 do setHeat(heat, (rows - 1) * cols + c, 0) end
  for _ = 1, 40 do step(heat, cols, rows, 3, 0) end
  local total = 0
  for i = 0, cols * rows - 1 do total = total + getHeat(heat, i) end
  check(total == 0, "the fire dies without fuel")
  local packed = newHeat(20)
  setHeat(packed, 9, 33)
  setHeat(packed, 8, 7)
  setHeat(packed, 15, 39)
  check(getHeat(packed, 9) == 33 and getHeat(packed, 8) == 7 and getHeat(packed, 15) == 39 and getHeat(packed, 10) == 0, "packed cells do not disturb their neighbours")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("fire needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("fire: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local heat = newHeat(COLS * ROWS)
  local si, pal = 1, palette(STOPS[1])
  local decay, wind, fuel, shown = 5, 0, LEVELS - 1, sys.millis()
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then
        si = si % #STOPS + 1
        pal = palette(STOPS[si])
        shown = sys.millis()
      elseif k == "w" or k == "up" then decay = math.max(1, decay - 1)
      elseif k == "s" or k == "down" then decay = math.min(8, decay + 1)
      elseif k == "a" or k == "left" then wind = math.max(-1, wind - 1)
      elseif k == "d" or k == "right" then wind = math.min(1, wind + 1) end
      k = key.poll()
    end
    for c = 0, COLS - 1 do setHeat(heat, (ROWS - 1) * COLS + c, fuel - math.random(0, 3)) end
    step(heat, COLS, ROWS, decay, wind)
    gfx.clear(0)
    for r = 0, ROWS - 1 do
      for c = 0, COLS - 1 do
        local v = getHeat(heat, r * COLS + c)
        if v > 0 then gfx.fill(c * CELL, r * CELL, CELL, CELL, pal[v]) end
      end
    end
    if sys.millis() - shown < 1800 then gfx.text(4, 4, STOPS[si].name .. "  space w s a d q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(10)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("fire: " .. tostring(problem)) end
