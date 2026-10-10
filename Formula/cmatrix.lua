#!lua
-- cmatrix: characters falling down the screen, like the classic cmatrix. Press q to quit.

local COLS, ROWS = term.size()
local CHARS = "abcdefghijklmnopqrstuvwxyz0123456789@#$%&*+=<>?/"

local function randomChar()
  local i = math.random(#CHARS)
  return CHARS:sub(i, i)
end

local function newDrop(x, onScreen)
  return {
    x = x,
    head = onScreen and math.random(0, ROWS - 1) or -math.random(1, ROWS),
    len = math.random(4, 12),
    step = math.random(1, 3),  -- frames per row
    tick = 0,
  }
end

local drops = {}
for x = 0, COLS - 1, 2 do
  drops[#drops + 1] = newDrop(x, false)
end

local function update(d)
  d.tick = d.tick + 1
  if d.tick >= d.step then
    d.tick = 0
    d.head = d.head + 1
  end
  if d.head - d.len > ROWS then  -- fell off the bottom: start again above the screen
    d.head = -math.random(1, ROWS // 2)
    d.len = math.random(4, 12)
    d.step = math.random(1, 3)
  end
end

local function draw(d)
  for i = 0, d.len do
    local y = d.head - i
    if y >= 0 and y < ROWS then
      local color = "greendim"
      if i == 0 then
        color = "white"
      elseif i < 3 then
        color = "green"
      end
      term.put(d.x, y, randomChar(), color)
    end
  end
end

term.fullscreen(true)
term.clear()
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true end
    k = key.poll()
  end
  if quit then break end

  term.clear()
  for _, d in ipairs(drops) do
    update(d)
    draw(d)
  end
  term.flush()
  sys.sleep(60)
end
term.fullscreen(false)
