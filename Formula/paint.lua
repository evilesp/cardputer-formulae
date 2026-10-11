#!lua
-- paint: draw pictures on the screen, 60 x 30 squares of four pixels. Move the cursor with w a s d, space paints the
-- square under it, p keeps the pen down so every move paints (press p again to lift it), keys 1 to 8 choose the colour,
-- e erases, c clears, v saves the picture to /home/user/paint.txt and l loads it. ctrl-q quits.
-- Needs the graphics and the ui package. Run it with --selftest to check the saving.

local GW, GH = 60, 30
local PALETTE = { 0x000000, 0xe05050, 0xe0a040, 0xe0e050, 0x50d060, 0x40a0e0, 0x8060e0, 0xf0f0f0 }
local FILE = "/home/user/paint.txt"

-- a picture as text: one line of GW digits (0 to 7, the palette entry) per row
local function encode(grid, w, h)
  local lines = {}
  for y = 1, h do
    local row = {}
    for x = 1, w do row[x] = tostring(grid[y][x]) end
    lines[y] = table.concat(row)
  end
  return table.concat(lines, "\n") .. "\n"
end

local function decode(text, w, h)
  local grid = {}
  for y = 1, h do
    grid[y] = {}
    for x = 1, w do grid[y][x] = 0 end
  end
  local y = 1
  for line in text:gmatch("[^\n]+") do
    if y > h then break end
    for x = 1, math.min(w, #line) do
      local d = tonumber(line:sub(x, x))
      grid[y][x] = (d and d >= 0 and d <= 7) and d or 0
    end
    y = y + 1
  end
  return grid
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local g = decode("", 4, 2)
  check(#g == 2 and #g[1] == 4 and g[2][4] == 0, "an empty text is a blank picture")
  g[1][2], g[2][4] = 3, 7
  local text = encode(g, 4, 2)
  check(text == "0300\n0007\n", "the picture becomes two lines of digits")
  local back = decode(text, 4, 2)
  check(back[1][2] == 3 and back[2][4] == 7 and back[1][1] == 0, "the text becomes the same picture")
  local bad = decode("09x1\n", 4, 1)
  check(bad[1][2] == 0 and bad[1][3] == 0 and bad[1][4] == 1, "digits above 7 and other letters become blank")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("paint needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("paint: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("paint: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local CELL = 4
local grid = decode("", GW, GH)
local cx, cy, color, pen, message = 1, 1, 8, false, ""

local function cellColor(x, y)
  local v = grid[y][x]
  if v == 0 then return 0x14161e end
  return PALETTE[v]
end

local function drawCell(x, y)
  gfx.fill((x - 1) * CELL, (y - 1) * CELL, CELL, CELL, cellColor(x, y))
end

local function drawAll()
  gfx.clear(0x14161e)
  for y = 1, GH do
    for x = 1, GW do
      if grid[y][x] ~= 0 then drawCell(x, y) end
    end
  end
end

local function drawBar()
  gfx.fill(0, GH * CELL, W, H - GH * CELL, 0x1c2233)
  for i, c in ipairs(PALETTE) do
    local x = 4 + (i - 1) * 14
    gfx.fill(x, GH * CELL + 3, 11, 9, c)
    if i == color then gfx.rect(x - 1, GH * CELL + 2, 13, 11, 0xffffff) end
  end
  ui.label(122, GH * CELL + 5, pen and "pen down" or "pen up", pen and 0xffe060 or 0x8a94aa)
  ui.label(178, GH * CELL + 5, message, 0x60ff90)
end

local function paintHere()
  grid[cy][cx] = color == 9 and 0 or color
  drawCell(cx, cy)
end

local function frame(oldX, oldY)
  -- the cursor outline reaches one pixel into the neighbours, so the squares around the old place are redrawn
  for dy = -1, 1 do
    for dx = -1, 1 do
      local x, y = oldX + dx, oldY + dy
      if x >= 1 and x <= GW and y >= 1 and y <= GH then drawCell(x, y) end
    end
  end
  gfx.rect((cx - 1) * CELL - 1, (cy - 1) * CELL - 1, CELL + 2, CELL + 2, 0xffffff)
  drawBar()
  gfx.flush()
end

local function save()
  local ok, err = fs.write(FILE, encode(grid, GW, GH))
  message = ok and "saved" or "no save"
end

local function load()
  local text = fs.read(FILE)
  if text then
    grid = decode(text, GW, GH)
    drawAll()
    message = "loaded"
  else
    message = "no file"
  end
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if #k == 1 then k = k:lower() end
  local ox, oy = cx, cy
  message = ""
  if k == "w" then cy = math.max(1, cy - 1)
  elseif k == "s" then cy = math.min(GH, cy + 1)
  elseif k == "a" then cx = math.max(1, cx - 1)
  elseif k == "d" then cx = math.min(GW, cx + 1)
  elseif k == " " then paintHere()
  elseif k == "p" then pen = not pen
  elseif k == "e" then color = 9
  elseif k == "c" then
    grid = decode("", GW, GH)
    drawAll()
  elseif k == "v" then save()
  elseif k == "l" then load()
  elseif k:match("^[1-8]$") then color = tonumber(k)
  end
  if pen and (cx ~= ox or cy ~= oy) then paintHere() end
  return true, ox, oy
end

local w, h = ui.open()
if not w then
  print("paint: " .. tostring(h))
  return
end
drawAll()
frame(1, 1)
local ok, problem = pcall(function()
  while true do
    local k = key.poll()
    local oldX, oldY = cx, cy
    while k do
      local more, ox, oy = handle(k)
      if not more then return end
      k = key.poll()
    end
    frame(oldX, oldY)
    sys.sleep(25)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("paint: " .. tostring(problem)) end
