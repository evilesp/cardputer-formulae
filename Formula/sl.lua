#!lua
-- sl: a steam locomotive crosses the screen. Press q to quit.
-- (The joke of the classic program: you typed sl instead of ls.)

local ART = [=[
      ====        ________                ___________
  _D _|  |_______/        \__I_I_____===__|_________|
   |(_)---  |   H\________/ |   |        =|___ ___|
   /     |  |   H  |  |     |   |         ||_| |_||
  |      |  |   H  |__--------------------| [___] |
  | ________|___H__/__|_____/[][]~\_______|       |
  |/ |   |-----------I_____I [][] []  D   |=======|__
__/ =| o |=-~~\  /~~\  /~~\  /~~\ ____Y___________|__
 |/-=|___|=    ||    ||    ||    |_____/~\___/
  \_/      \O=====O=====O=====O/      \_/
]=]

local lines = {}
for line in ART:gmatch("[^\n]+") do lines[#lines + 1] = line end

local COLS, ROWS = term.size()
local TOP = 4          -- screen row of the first art line
local x = COLS         -- the train enters from the right
local frame = 0
local puffs = {}       -- smoke: { x, y, age }

term.fullscreen(true)
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true end
    k = key.poll()
  end
  if quit then break end

  term.clear()
  term.text(0, ROWS - 1, "sl   q quit", "dim")
  for r, line in ipairs(lines) do
    term.text(x, TOP + r - 1, line, r >= 10 and "dim" or "white")
  end

  -- smoke from the funnel, rising and drifting right
  frame = frame + 1
  if frame % 4 == 0 then puffs[#puffs + 1] = { x = x + 6, y = TOP - 1, age = 0 } end
  local alive = {}
  for _, p in ipairs(puffs) do
    p.age = p.age + 1
    if p.age % 3 == 0 then p.y = p.y - 1 end
    p.x = p.x + (p.age % 2)
    if p.age < 14 and p.y >= 0 then
      term.text(p.x, p.y, p.age < 7 and "(  )" or "( )", "dim")
      alive[#alive + 1] = p
    end
  end
  puffs = alive

  x = x - 1
  if x < -#lines[1] then x = COLS end
  term.flush()
  sys.sleep(60)
end
term.fullscreen(false)
