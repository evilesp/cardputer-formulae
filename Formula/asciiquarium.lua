#!lua
-- asciiquarium: a small fish tank with bubbles and seaweed. Press q to quit.

local W, H = term.size()

local FISH = {
  { right = "><(((*>", left = "<*)))><", color = "yellow" },
  { right = "><>", left = "<><", color = "cyan" },
  { right = "><((>", left = "<))><", color = "magenta" },
  { right = "<'))))>", left = "<((((>", color = "white" },
}

local function spawnFish(f)
  local kind = FISH[math.random(#FISH)]
  local dir = math.random(0, 1) == 0 and 1 or -1
  f.kind = kind
  f.dir = dir
  f.sprite = dir == 1 and kind.right or kind.left
  f.x = dir == 1 and -#f.sprite or W
  f.y = math.random(3, H - 4)
  f.delay = math.random(1, 3)  -- frames per column
  f.tick = 0
end

local fishes = {}
for i = 1, 6 do
  local f = {}
  spawnFish(f)
  f.x = math.random(0, W - 8)  -- start somewhere on screen
  fishes[i] = f
end

local bubbles = {}
local SEAWEED = { { x = 4, h = 4 }, { x = 13, h = 6 }, { x = 23, h = 5 }, { x = 33, h = 3 } }

local frame = 0

local function moveFish(f)
  f.tick = f.tick + 1
  if f.tick >= f.delay then
    f.tick = 0
    f.x = f.x + f.dir
  end
  if (f.dir == 1 and f.x > W) or (f.dir == -1 and f.x < -#f.sprite) then
    spawnFish(f)
  end
  if frame % 9 == 0 and f.x >= 0 and f.x < W and #bubbles < 24 then
    local bx = f.dir == 1 and f.x + #f.sprite or f.x - 1
    if bx >= 0 and bx < W then
      bubbles[#bubbles + 1] = { x = bx, y = f.y - 1 }
    end
  end
end

local function drawFish(f)
  for i = 1, #f.sprite do
    local x = f.x + i - 1
    if x >= 0 and x < W then
      term.put(x, f.y, f.sprite:sub(i, i), f.kind.color)
    end
  end
end

local function moveBubbles()
  local alive = {}
  for _, b in ipairs(bubbles) do
    if frame % 3 == 0 then b.y = b.y - 1 end
    if b.y > 0 then alive[#alive + 1] = b end
  end
  bubbles = alive
end

local function drawScene()
  -- waves on the surface
  for x = 0, W - 1 do
    term.put(x, 0, ((x + frame // 2) % 6 < 3) and "~" or "-", "cyan")
  end
  -- seaweed that sways
  for _, s in ipairs(SEAWEED) do
    for row = 0, s.h - 1 do
      local y = H - 2 - row
      local ch = ((frame // 6 + row) % 2 == 0) and "(" or ")"
      term.put(s.x, y, ch, "greendim")
    end
  end
  -- sea floor
  for x = 0, W - 1 do
    term.put(x, H - 1, "_", "dim")
  end
  for _, b in ipairs(bubbles) do
    term.put(b.x, b.y, (b.y % 2 == 0) and "o" or ".", "cyan")
  end
  for _, f in ipairs(fishes) do
    drawFish(f)
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

  frame = frame + 1
  term.clear()
  for _, f in ipairs(fishes) do moveFish(f) end
  moveBubbles()
  drawScene()
  term.flush()
  sys.sleep(90)
end
term.fullscreen(false)
