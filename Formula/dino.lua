#!lua
-- dino: an endless runner in the terminal. The dinosaur runs, cacti come from the right, space (or up) jumps over
-- them. The score counts the time survived and the game speeds up. A hit ends the game: r plays again, q quits.

local COLS, ROWS = term.size()
local DINO_X = 3          -- the dinosaur's column
local GROUND_Y = 12       -- the ground line; the dinosaur stands on the row above it
local STAND_Y = GROUND_Y - 1
local JUMP = { 1, 2, 3, 3, 2, 1 }  -- its height in each tick of a jump

local cacti = {}          -- the columns of the cacti
local spawnIn = 0         -- ticks until the next cactus
local jump = 0            -- 0 on the ground, else the position in JUMP
local ticks = 0
local over = false

local function reset()
  cacti = {}
  spawnIn = 0
  jump = 0
  ticks = 0
  over = false
end

local function draw()
  term.clear()
  term.text(0, 0, string.format("dino   score %d", ticks // 2), "green")
  local h = jump > 0 and JUMP[jump] or 0
  term.text(DINO_X, STAND_Y - h, "D", "text")
  for _, x in ipairs(cacti) do term.text(x, STAND_Y, "|", "green") end
  local ground = {}
  for x = 0, COLS - 1 do ground[#ground + 1] = (x + ticks) % 5 == 0 and "_" or "-" end
  term.text(0, GROUND_Y, table.concat(ground), "dim")
  if over then
    term.text(0, 5, "game over", "red")
    term.text(0, 6, "press r to play again", "text")
  end
  term.text(0, ROWS - 2, "space or up: jump   r: restart", "dim")
  term.text(0, ROWS - 1, "q: quit", "dim")
  term.flush()
end

-- one step of the game: the cacti move, the jump goes on, and a cactus on the dinosaur ends the game
local function tick()
  local h = jump > 0 and JUMP[jump] or 0
  if jump > 0 then
    jump = jump + 1
    if jump > #JUMP then jump = 0 end
  end
  for i = #cacti, 1, -1 do
    cacti[i] = cacti[i] - 1
    if cacti[i] < 1 then table.remove(cacti, i) end
  end
  if spawnIn <= 0 then
    cacti[#cacti + 1] = COLS - 1
    spawnIn = math.random(12, 24)
  else
    spawnIn = spawnIn - 1
  end
  for _, x in ipairs(cacti) do
    if x == DINO_X and h == 0 then over = true end
  end
  ticks = ticks + 1
end

-- returns false when the player quits
local function handle(k)
  if k == "q" then return false end
  if k == "r" and over then
    reset()
  elseif (k == " " or k == "up") and not over and jump == 0 then
    jump = 1
  end
  return true
end

term.fullscreen(true)
local quit = false
while not quit do
  draw()
  local k = key.poll()
  while k do
    if not handle(k) then
      quit = true
      break
    end
    k = key.poll()
  end
  if not over and not quit then tick() end
  sys.sleep(math.max(40, 70 - (ticks // 50) * 5))
end
term.fullscreen(false)
