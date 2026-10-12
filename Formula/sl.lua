#!lua
-- sl: the steam locomotive of the classic Linux joke (you typed sl instead of ls). The D51 with its coal car crosses the
-- screen once, the wheels turning and the smoke rising, as in the original sl by Toyoda Masashi (its licence lets anyone
-- copy and change it). q stops it early.
-- usage: sl [-a] [-F] [-c] [-l]
--   -a  an accident: people on the train cry for help
--   -F  the train flies away
--   -c  the C51 locomotive instead of the D51
--   -l  a little locomotive
-- Run it with --selftest to check the frames.

local D51 = {
  "      ====        ________                ___________ ",
  "  _D _|  |_______/        \\__I_I_____===__|_________| ",
  "   |(_)---  |   H\\________/ |   |        =|___ ___|   ",
  "   /     |  |   H  |  |     |   |         ||_| |_||   ",
  "  |      |  |   H  |__--------------------| [___] |   ",
  "  | ________|___H__/__|_____/[][]~\\_______|       |   ",
  "  |/ |   |-----------I_____I [][] []  D   |=======|__ ",
}
-- the six positions of the wheels and the rods: three rows each
local D51_WHEELS = {
  { "__/ =| o |=-~~\\  /~~\\  /~~\\  /~~\\ ____Y___________|__ ",
    " |/-=|___|=    ||    ||    ||    |_____/~\\___/        ",
    "  \\_/      \\O=====O=====O=====O_/      \\_/            " },
  { "__/ =| o |=-~~\\  /~~\\  /~~\\  /~~\\ ____Y___________|__ ",
    " |/-=|___|=O=====O=====O=====O   |_____/~\\___/        ",
    "  \\_/      \\__/  \\__/  \\__/  \\__/      \\_/            " },
  { "__/ =| o |=-O=====O=====O=====O \\ ____Y___________|__ ",
    " |/-=|___|=    ||    ||    ||    |_____/~\\___/        ",
    "  \\_/      \\__/  \\__/  \\__/  \\__/      \\_/            " },
  { "__/ =| o |=-~O=====O=====O=====O\\ ____Y___________|__ ",
    " |/-=|___|=    ||    ||    ||    |_____/~\\___/        ",
    "  \\_/      \\__/  \\__/  \\__/  \\__/      \\_/            " },
  { "__/ =| o |=-~~\\  /~~\\  /~~\\  /~~\\ ____Y___________|__ ",
    " |/-=|___|=   O=====O=====O=====O|_____/~\\___/        ",
    "  \\_/      \\__/  \\__/  \\__/  \\__/      \\_/            " },
  { "__/ =| o |=-~~\\  /~~\\  /~~\\  /~~\\ ____Y___________|__ ",
    " |/-=|___|=    ||    ||    ||    |_____/~\\___/        ",
    "  \\_/      \\_O=====O=====O=====O/      \\_/            " },
}
local COAL = {
  "                              ",
  "                              ",
  "    _________________         ",
  "   _|                \\_____A  ",
  " =|                        |  ",
  " -|                        |  ",
  "__|________________________|_ ",
  "|__________________________|_ ",
  "   |_D__D__D_|  |_D__D__D_|   ",
  "    \\_/   \\_/    \\_/   \\_/    ",
}

local C51 = {
  "        ___                                            ",
  "       _|_|_  _     __       __             ___________",
  "    D__/   \\_(_)___|  |__H__|  |_____I_Ii_()|_________|",
  "     | `---'   |:: `--'  H  `--'         |  |___ ___|  ",
  "    +|~~~~~~~~++::~~~~~~~H~~+=====+~~~~~~|~~||_| |_||  ",
  "    ||        | ::       H  +=====+      |  |::  ...|  ",
  "|    | _______|_::-----------------[][]-----|       |  ",
}
local C51_WHEELS = {
  { "| /~~ ||   |-----/~~~~\\  /[I_____I][][] --|||_______|__",
    "------'|oOo|==[]=-     ||      ||      |  ||=======_|__",
    "/~\\____|___|/~\\_|   O=======O=======O  |__|+-/~\\_|    ",
    "\\_/         \\_/  \\____/  \\____/  \\____/      \\_/      " },
  { "| /~~ ||   |-----/~~~~\\  /[I_____I][][] --|||_______|__",
    "------'|oOo|===[]=-    ||      ||      |  ||=======_|__",
    "/~\\____|___|/~\\_|    O=======O=======O |__|+-/~\\_|    ",
    "\\_/         \\_/  \\____/  \\____/  \\____/      \\_/      " },
  { "| /~~ ||   |-----/~~~~\\  /[I_____I][][] --|||_______|__",
    "------'|oOo|===[]=- O=======O=======O  |  ||=======_|__",
    "/~\\____|___|/~\\_|      ||      ||      |__|+-/~\\_|    ",
    "\\_/         \\_/  \\____/  \\____/  \\____/      \\_/      " },
  { "| /~~ ||   |-----/~~~~\\  /[I_____I][][] --|||_______|__",
    "------'|oOo|==[]=- O=======O=======O   |  ||=======_|__",
    "/~\\____|___|/~\\_|      ||      ||      |__|+-/~\\_|    ",
    "\\_/         \\_/  \\____/  \\____/  \\____/      \\_/      " },
  { "| /~~ ||   |-----/~~~~\\  /[I_____I][][] --|||_______|__",
    "------'|oOo|=[]=- O=======O=======O    |  ||=======_|__",
    "/~\\____|___|/~\\_|      ||      ||      |__|+-/~\\_|    ",
    "\\_/         \\_/  \\____/  \\____/  \\____/      \\_/      " },
  { "| /~~ ||   |-----/~~~~\\  /[I_____I][][] --|||_______|__",
    "------'|oOo|=[]=-      ||      ||      |  ||=======_|__",
    "/~\\____|___|/~\\_|  O=======O=======O   |__|+-/~\\_|    ",
    "\\_/         \\_/  \\____/  \\____/  \\____/      \\_/      " },
}

local LITTLE = {
  "     ++      +------ ",
  "     ||      |+-+ |  ",
  "   /---------|| | |  ",
  "  + ========  +-+ |  ",
}
local LITTLE_WHEELS = {
  { " _|--O========O~\\-+  ", "//// \\_/      \\_/    " },
  { " _|--/O========O\\-+  ", "//// \\_/      \\_/    " },
  { " _|--/~O========O-+  ", "//// \\_/      \\_/    " },
  { " _|--/~\\------/~\\-+  ", "//// \\_O========O    " },
  { " _|--/~\\------/~\\-+  ", "//// \\O========O/    " },
  { " _|--/~\\------/~\\-+  ", "//// O========O_/    " },
}
local LITTLE_COAL = {
  "____                 ",
  "|   \\@@@@@@@@@@@     ",
  "|    \\@@@@@@@@@@@@@_ ",
  "|                  | ",
  "|__________________| ",
  "   (O)       (O)     ",
}
local LITTLE_CAR = {
  "____________________ ",
  "|  ___ ___ ___ ___ | ",
  "|  |_| |_| |_| |_| | ",
  "|__________________| ",
  "|__________________| ",
  "   (O)        (O)    ",
}

-- the smoke: a puff shrinks as it rises and drifts away
local SMOKE = { "(   )", "(    )", "(    )", "(   )", "(  )", "(  )", "( )", "( )", "()", "()", "O", "O", "O", "O", " " }
local SMOKE_DY = { 2, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local SMOKE_DX = { -2, -1, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3 }

-- the train of the options: its rows for a frame, its width, the column of the funnel and the rows of the windows
local function trainOf(opts)
  if opts.little then
    return {
      width = 63, funnel = 4, height = 6, men = { 46, 54 },  -- the men stand in the passenger car
      rows = function(step)
        local rows = {}
        local wheels = LITTLE_WHEELS[step % #LITTLE_WHEELS + 1]
        for r = 1, 6 do
          local loco = r <= 4 and LITTLE[r] or wheels[r - 4]
          rows[r] = loco .. LITTLE_COAL[r] .. LITTLE_CAR[r]
        end
        return rows
      end,
    }
  end
  local body, wheelSets, height = D51, D51_WHEELS, 10
  local funnel = 7
  if opts.c51 then body, wheelSets, height, funnel = C51, C51_WHEELS, 11, 7 end
  return {
    width = #body[1] + #COAL[1], funnel = funnel, height = height, men = { 43, 47 },
    rows = function(step)
      local rows = {}
      local wheels = wheelSets[step % #wheelSets + 1]
      local coalTop = height - #COAL  -- the coal car stands on the same rails
      for r = 1, height do
        local loco = r <= #body and body[r] or wheels[r - #body]
        if #loco < #body[1] then loco = loco .. string.rep(" ", #body[1] - #loco) end  -- rows of one width
        local coal = COAL[r - coalTop] or string.rep(" ", #COAL[1])
        rows[r] = loco .. coal
      end
      return rows
    end,
  }
end

local function parseArgs(args)
  local opts = {}
  for _, a in ipairs(args) do
    if a:sub(1, 1) ~= "-" or #a < 2 then return nil end
    for ch in a:sub(2):gmatch(".") do
      if ch == "a" then opts.accident = true
      elseif ch == "F" then opts.fly = true
      elseif ch == "c" then opts.c51 = true
      elseif ch == "l" then opts.little = true
      else return nil end
    end
  end
  return opts
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  for _, opts in ipairs({ {}, { c51 = true }, { little = true } }) do
    local t = trainOf(opts)
    for step = 0, 5 do
      local rows = t.rows(step)
      local same = #rows == t.height
      for _, r in ipairs(rows) do
        if #r ~= #rows[1] then same = false end
      end
      check(same, "every row of a frame is as long as the first")
    end
  end
  check(trainOf({}).rows(0)[8] ~= trainOf({}).rows(1)[8] or trainOf({}).rows(0)[9] ~= trainOf({}).rows(1)[9], "the wheels turn")
  check(#SMOKE == #SMOKE_DY and #SMOKE == #SMOKE_DX, "a step of smoke for every shape")
  local o = parseArgs({ "-aF" })
  check(o and o.accident and o.fly, "options together")
  check(parseArgs({ "-x" }) == nil and parseArgs({ "ls" }) == nil, "an unknown option is refused")
  if failed == 0 then print("selftest ok") end
  return
end

local opts = parseArgs(arg)
if not opts then
  print("usage: sl [-a] [-F] [-c] [-l]")
  return
end

local COLS, ROWS = term.size()
local train = trainOf(opts)
local baseTop = ROWS - train.height - 1  -- the rails are near the bottom; the smoke rises above
local puffs = {}

local function drawSmoke(x, top, step)
  if step % 4 == 0 then puffs[#puffs + 1] = { x = x + train.funnel, y = top - 1, age = 1 } end
  local alive = {}
  for _, p in ipairs(puffs) do
    if p.age <= #SMOKE then
      term.text(p.x, p.y, SMOKE[p.age], "dim")
      p.y = p.y - SMOKE_DY[p.age]
      p.x = p.x + SMOKE_DX[p.age]
      p.age = p.age + 1
      if p.y >= 0 then alive[#alive + 1] = p end
    end
  end
  puffs = alive
end

term.fullscreen(true)
local step = 0
for x = COLS - 1, -train.width, -1 do
  local k = key.poll()
  local quit = false
  while k do
    if k == "q" or k == "ctrl-q" then quit = true end
    k = key.poll()
  end
  if quit then break end

  term.clear()
  -- flying: the train climbs a row every few steps once it is on the screen
  local top = baseTop
  if opts.fly then top = baseTop - (COLS - x) // 4 end
  local rows = train.rows(step)
  for r, line in ipairs(rows) do
    local y = top + r - 1
    if y >= 0 and y < ROWS then term.text(x, y, line, "white") end
  end
  if opts.accident then
    for i, col in ipairs(train.men) do
      local wave = (step // 2 + i) % 2 == 0
      -- in the windows of the cab (third row), with the cry above them, as in the original
      if top + 2 >= 0 then term.text(x + col, top + 2, wave and "\\O/" or "(O)", "yellow") end
      if wave and top + 1 >= 0 then term.text(x + col - 1, top + 1, "Help!", "red") end
    end
  end
  if not opts.fly then term.text(0, ROWS - 1, string.rep("=", COLS), "dim") end
  drawSmoke(x, top, step)
  term.flush()
  step = step + 1
  sys.sleep(45)
end
term.fullscreen(false)
