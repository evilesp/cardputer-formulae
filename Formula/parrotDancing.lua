#!lua
-- parrotDancing: a parrot that dances in the middle of the screen, in the spirit of the party parrot. Its wings
-- flap, its legs step, it bobs and sways, the rainbow rolls along its body, and sparkles fly around it. q quits.

local COLS, ROWS = term.size()
local W, H = 28, 11                    -- the parrot's box, in characters
local STEP_MS = 110                    -- one step of the dance

-- the parrot facing right: the head with its eye (o) and beak (>) at the top, the tail and the legs at the bottom
local BODY = {
  "            ######",
  "         ############",
  "        ##o###########>",
  "       ################",
  "      ##################",
  "      ##################",
  "       ################",
  "        ##############",
  "         ############",
  "          ##  ##",
  "          ##  ##",
}

-- the wing in three positions, drawn on the empty cells beside the body: {row, column, character}
local WINGS = {
  up = {
    { 1, 2, "\\" }, { 1, 3, "\\" },
    { 2, 2, "\\" }, { 2, 3, "\\" }, { 2, 4, "\\" },
    { 3, 3, "\\" }, { 3, 4, "\\" }, { 3, 5, "\\" },
    { 4, 4, "-" }, { 4, 5, "-" },
  },
  mid = {
    { 4, 1, "_" }, { 4, 2, "_" }, { 4, 3, "_" }, { 4, 4, "_" }, { 4, 5, "_" }, { 4, 6, "_" },
    { 5, 1, "-" }, { 5, 2, "-" }, { 5, 3, "-" }, { 5, 4, "-" }, { 5, 5, "-" },
  },
  down = {
    { 6, 4, "/" }, { 6, 5, "/" },
    { 7, 3, "/" }, { 7, 4, "/" },
    { 8, 2, "/" }, { 8, 3, "/" },
    { 9, 1, "/" }, { 9, 2, "/" },
  },
}
-- the eye and the beak sit on row 3 of the body, and are drawn in their own colours
local EYE_COL = BODY[3]:find("o", 1, true)
local BEAK_COL = BODY[3]:find(">", 1, true)
-- the wing of each step of the dance (eight steps, then it starts again)
local WING_OF_STEP = { "up", "mid", "down", "mid", "up", "mid", "down", "mid" }

-- the legs in two steps: rows 10 and 11
local LEGS = {
  { "          ##  ##", "          ##  ##" },
  { "          ##  ##", "         ##    ##" },
}

-- the bob (rows) and the sway (columns) of each step
local BOB = { 0, 1, 0, 1, 0, 1, 0, 1 }
local SWAY = { 0, 1, 2, 2, 1, 0, -1, -2, -2, -1 }
local RAINBOW = { "red", "yellow", "green", "cyan", "blue", "magenta" }

-- the parrot as rows of characters, with the wing and the legs of this step
local function frame(step)
  local grid = {}
  for r = 1, H do
    local line = BODY[r] or ""
    grid[r] = {}
    for c = 1, W do
      grid[r][c] = line:sub(c, c) ~= "" and line:sub(c, c) or " "
    end
  end
  for _, cell in ipairs(WINGS[WING_OF_STEP[(step % #WING_OF_STEP) + 1]]) do
    local r, c = cell[1], cell[2]
    if grid[r][c] == " " then grid[r][c] = cell[3] end
  end
  local legs = LEGS[(step % 2) + 1]
  for i, line in ipairs(legs) do
    for c = 1, W do
      grid[9 + i][c] = line:sub(c, c) ~= "" and line:sub(c, c) or " "
    end
  end
  local rows = {}
  for r = 1, H do rows[r] = table.concat(grid[r]) end
  return rows
end

local function draw(step)
  term.clear()
  local rows = frame(step)
  local left = (COLS - W) // 2 + SWAY[(step % #SWAY) + 1]
  local top = (ROWS - H) // 2 + BOB[(step % #BOB) + 1]

  -- sparkles around the parrot, moving from step to step
  for k = 1, 4 do
    local sx = (step * (3 + k) + k * 11) % COLS
    local sy = 1 + (step * (2 + k) + k * 5) % (ROWS - 2)
    local inside = sx >= left and sx < left + W and sy >= top and sy < top + H
    if not inside then term.text(sx, sy, (k % 2 == 0) and "*" or "+", "yellow") end
  end

  -- the rows of the parrot, each in its own colour; the colours roll along the body from step to step
  for r, text in ipairs(rows) do
    local colour = RAINBOW[((r + step) % #RAINBOW) + 1]
    term.text(left, top + r - 1, text, colour)
  end
  -- the eye and the beak, over the body
  term.text(left + EYE_COL - 1, top + 2, "o", "white")
  term.text(left + BEAK_COL - 1, top + 2, ">", "yellow")
  term.text(0, 0, "parrotDancing   q quit", "dim")
  term.flush()
end

local quit, step = false, 0
term.fullscreen(true)
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true end
    k = key.poll()
  end
  if quit then break end
  draw(step)
  step = step + 1
  sys.sleep(STEP_MS)
end
term.fullscreen(false)
