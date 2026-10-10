#!lua
-- parrotDancing: a parrot that dances in the middle of the screen, in the spirit of the party parrot. Its wing
-- flaps, it bobs and sways, and its colour changes on every step. q quits.

local COLS, ROWS = term.size()

-- the parrot, 20 columns by 8 rows, facing right: the head with its eye (O) and beak (>) on the right
local BODY = {
  "      ####          ",
  "    ########        ",
  "   ##O#######>      ",
  "  #############     ",
  "  #############     ",
  "   ##########       ",
  "    ##     ##       ",
  "    ##     ##       ",
}

-- the wing in four positions: {row, column, character} cells drawn over the body (1-based)
local WINGS = {
  { { 2, 1, "/" }, { 3, 2, "/" }, { 3, 3, "/" }, { 3, 4, "/" } },                      -- up
  { { 4, 2, "-" }, { 4, 3, "-" }, { 4, 4, "-" }, { 4, 5, "-" }, { 4, 6, "-" } },        -- level
  { { 5, 2, "\\" }, { 5, 3, "\\" }, { 5, 4, "\\" }, { 6, 2, "\\" } },                  -- down
  { { 4, 2, "-" }, { 4, 3, "-" }, { 4, 4, "-" }, { 4, 5, "-" }, { 4, 6, "-" } },        -- level
}

local COLOURS = { "cyan", "yellow", "magenta", "green" }

-- the rows of one step: the body with the wing of that step laid over it
local function frame(step)
  local grid = {}
  for r, line in ipairs(BODY) do
    grid[r] = {}
    for c = 1, #line do grid[r][c] = line:sub(c, c) end
  end
  for _, cell in ipairs(WINGS[(step % 4) + 1]) do
    grid[cell[1]][cell[2]] = cell[3]
  end
  local rows = {}
  for r, cells in ipairs(grid) do rows[r] = table.concat(cells) end
  return rows
end

local function draw(step)
  term.clear()
  local rows = frame(step)
  -- a bob up and down on every other step, and a sway left and right every other two
  local dy = (step % 2 == 0) and 0 or 1
  local dx = ((step // 2) % 2 == 0) and 0 or 2
  local top = (ROWS - #rows) // 2 + dy
  local left = (COLS - 20) // 2 + dx
  local colour = COLOURS[(step % #COLOURS) + 1]
  for r, line in ipairs(rows) do
    term.text(left, top + r - 1, line, colour)
  end
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
  sys.sleep(150)
end
term.fullscreen(false)
