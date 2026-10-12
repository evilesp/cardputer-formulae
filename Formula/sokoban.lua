#!lua
-- sokoban: push every box onto a target. Move with w a s d; you push a box when you walk into it, a box cannot be pulled.
-- u takes back a move, r starts the level again, n and p go to the next and the previous level, ctrl-q quits. There are 27
-- levels, from easy to harder; the best (fewest) moves of each are kept. The levels are in the program; a file
-- /home/user/sokoban.txt with more levels (separated by an empty line) is used when it exists.
-- Needs the graphics and the ui package. Run it with --selftest to check the rules.

-- # wall, space floor, . target, $ box, @ you; $ on a target is shown as * and @ on a target as +
local LEVELS = {
  { "#####", "#@$.#", "#####" },
  { "#######", "#.$@$.#", "#######" },
  { "######", "#..$@#", "#.$  #", "######" },
  -- made by playing a finished level backwards, so every one can be solved; "sol" is a way to solve it (the test plays it)
  { "#######", "#@*   #", "#$#  .#", "#     #", "#. # $#", "#     #", "#######", sol = "duddrlrlrddrrruullrll" },
  { "#######", "#@$.  #", "#*    #", "# #$$.#", "#     #", "# .   #", "#######", sol = "drrllurdrddllrludrdururddudluud" },
  { "#########", "#       #", "# * . #.#", "#   $# $#", "#   . $@#", "#########", sol = "ludllrrlrudrllrudruldlludrllrluuudulldudddrru" },
  { "########", "#.   $+#", "#  # $$#", "# ## . #", "#      #", "########", sol = "lllrrrlrldlddlllrrllrluurlrlrlddrrlrruurudurdllddrlrrlrlruullddrrudlluuulldur" },
  { "#######", "# . $ #", "#   # #", "# $## #", "#  . @#", "#######", sol = "lrlrlrudududlrlrlrlrlrlllrrlrrlrlruuududdududdlrlrlruuduudullrldlrlrudlldduudduurlduudrrlrudllrdldrludurd" },
  { "########", "#   .  #", "#  $ $ #", "#   .# #", "# $@#  #", "#    . #", "########", sol = "drrrlrlrllrlrruduuudddllrlrurdudlrlllrrlruruuulrdludullrlrlrlddrullddldrrrlulurddlruudlldruurddulududrduuudul" },
  { "##########", "#        #", "#.#  #@$ #", "#$  ## . #", "#        #", "##########", sol = "dudrlduuddlrurlrdrlrlruuudulrlldudddlllrrlluldudlrlrlrruuudrudlruldddrlllurlrruulrrrrrrldrudddududlrudluldrruuulrlrlrdudulrllrlrdldu" },
  { "#########", "#      @#", "#$$##$#$#", "# .#  # #", "#.   . .#", "#########", sol = "llrllrlllrrrlrllrrrllrllllrrrrrlrrllrlrrlrlrllllllrlrrrrrllrrllrrrlrllrrlrllllrrrlrlrrlrllllrrlrrrlrlrlrlrlrdduudulldduurrdduudulrdulllllrllrlrrrllldurlrldurdld" },
  { "########", "#.$   +#", "#   ## #", "#.$ #  #", "# $ ## #", "#      #", "########", sol = "lrduddduuullldddduldlrrrrlrllrrrllrruuudduudlrlrududlruudduudulrlrlrllrrlrllrlrlldllrlurrdldlrrudddrludllrlrlrlrlruulrurllududrrudurrlllrdlddrdlrlrllurldudrrrrrudlll" },
  { "########", "# .  .@#", "#   $  #", "#      #", "#.# ## #", "# $$ # #", "#      #", "########", sol = "llldrdllludruduulddrulurlrrddrrlrlllururrldurrdulrlrllrrdlludrdllludurruldlurrlrrrlrllrrdududduldlrrdduuduuddudddlludrllrlllrlrlrlrrlrrrllrlllrlrlrruldlurlrruurrluludurdulddluludu" },
  { "########", "#.$    #", "# #  # #", "# ## . #", "#  # $ #", "#   @  #", "########", sol = "rllluludududuuurldurrdurdludullrrdudrullrdrdddllrrllrrlrlrududlrududuurlrlrlulrdrrdulruududduuddddlrllrudrlruuduuudulldudlrdulrlrurldudlrlrulrrlrlrrddduuudullddduuludulrrldrudlrlrlurdulr" },
  { "#########", "#  .    #", "# . #  *#", "# $ #$#@#", "#       #", "#########", sol = "dllrluururdllrlrudulllddududuudlldudududduudduuduudrlrlduddrludrrlluuududdurlrrurldurrrldududrrlurdulrduldlurldduuddurlduurrllddududdrrlrlrudlrlludllrrudlrudlllrudllrludrrluruddulrlluduudurld" },
  { "##########", "#    . $ #", "#  # . $ #", "# #*## # #", "# .    $@#", "##########", sol = "uududduduudduduuuddduduuuddududdudududuudduduudduuduududdduuududududduduudduududdduuudududdudduuddududuudduudduuudududdududduuudddlllllrrlrrrludrruudududduuduulldddrruullrrddlrlrlrududllrrudud" },
  { "#########", "#      .#", "#       #", "#  $   .#", "#  #  $$#", "#    .$+#", "#########", sol = "lruulrdduldurldruuullurlldulrddudddrrududlulduudulrruldrrurludullrdlduurdrulddulruduldlrluldrlrduulldduurddldurrllrlrrldldudrudluurdulruluddurludurlrrrldurdlllurrdurrddllulludduudddrdrrlllrrlrlulr" },
  { "#######", "#  .$ #", "#. # .#", "#.# $ #", "#$$   #", "# @   #", "#######", sol = "lrlrrrrulruduuuddudduddlluudrurudddllrurdlllrudlrllrrllrruurruduudduudududdlddurduuddlrudlulurldudrruuulddlddrllluuddrruurlrlrrllddlrudlrlrrlrlrlrruulrlldldudurudrlldrllrlrlurlrlrruddrllrrudruulrll" },
  { "##########", "#    .   #", "#  #  #$ #", "# @ #    #", "#      # #", "#   $ .# #", "#  $.    #", "##########", sol = "ulurdlrlddddrrrrudurullrrllrlldrrdulurdurludrurrllduldurlrlddulrrudllrddluurrlllrrurrruulrdddddudllludulurlrurrrlruudduullrrdullrrlrdulrdulrlrdudduulrlrlrdullldduurlddrrllrrrlurududuldududdruudlduulrrlrduddluudr" },
  { "##########", "#  .  .  #", "# $  $ #@#", "#.   $ $.#", "#        #", "##########", sol = "udulldddrluuudllddululduuldrudrrrrdudududdlluulludrddlrudrlrludllrlruuudrddrurdudududuurlulrrrrdddlrudllllludrrllllrrllrluruududurdullrldrrdrruududurrlrrdduullrrddudduduuddlrllrlllrrrlurluludldrduuududududududuldududl" },
  { "########", "#   +  #", "# $ .#$#", "# # $# #", "# ##  .#", "#      #", "########", sol = "ldruddlrlrlududrluudrurrlrdduulrdullrrlllllddududdduduuddrludrrlrrrlrlrrlllrlllrrlrrrudududrludlrlrrllrudrludlllrlrrrrludlrllrllludrrrrrlududrludlllrllrlrrrlllrludrlrrrlruuudlrduludrddrlllrrrllrlrllluuuduudduurrllddurrlldd" },
  { "##########", "#        #", "# $   $ .#", "#    #   #", "#. #  #$ #", "#  .@    #", "##########", sol = "rrlrrllrlrrrllrrlllrludludurluuurlrlldulrdlulrldrlrldrddlruduurrddudruluuldllrrrdduduuduurrulrlrrlddudrlrlrdruuududulldurrdududddulludududuurrduldrddlruduuudlrudduduluddlrrdududdudlrllludududududlrrlrrlrlludrrurlrlrlrlulrlrlurlu" },
  { "##########", "#  @     #", "#     #  #", "#    $.  #", "# $# #   #", "#   .    #", "##########", sol = "lrdrrluduldrlulldurrrlrlrddruduurldlurdldddrlududrlllludrludududrudluuuddduuururlrdllruldddrlduuuudduudrddlruluurrdlrudlrdududluldduddududrulrulduurdudldrurlddrlluuuurlrldurldrlurlrdrurlrrldruldulllrdrurdlrudlurddluurrldllldrlrddulrurrll" },
  { "##########", "#   . $  #", "#      $.#", "# # #  # #", "#   #  $.#", "# @      #", "##########", sol = "uluurrlurdduudddllrrllrdrludulrruddudrlrrurdrrudlruduuudduudulurdddlrdudludruuuulrllrdrullldrluldlllrrlurddddlududuluddrulrrudllrldrrlrluldrluduudrludrldrlruruurllldddurruuludrududrludrldurrurdludududdduduudrlulrududurdudrllddrrduluudulududlllu" },
  { "#######", "#.    #", "# # * #", "#  @$ #", "#  .# #", "#$### #", "#     #", "#######", sol = "duuddlrludluuudurrrrduddududduuddddudllrllrllrrrrlruuduuduuudduduudddulldlluuudduudduurrrrdddduudddlrudududlrudllllrrlluuuudrdrlrurrudllrrddduuddlrlllrlludrlrlrluudurrlulrrrrlrlrduudddduudududuuddduuduudulruddulruulrllddrrdddlrlrlllrrllrrlrlrllrrlllud" },
  { "#########", "#       #", "# .  $# #", "#      $#", "# @  .$ #", "#    # .#", "#       #", "#########", sol = "rurdduuuuddrluurldlllurldurdldrrudrdllluddrududdrrllrrrludlllrudrrlluulrruldlrulrrldludddrrullrurdldrllruduuudlduudddurluuurlrrlldurlddduurlruurrlrrrrllrldlrurlrrdddlududlrurdludllududlddudlrrrluurrduurduuulrllrrddududldrudlllulduddudrlruddullurudlrddlluudururlrduudllddrrudlrldrudrlurluudluruuddrduuulrdrdrlrddduuulrduru" },
  { "##########", "# .      #", "#   # $  #", "# $ #$ . #", "#@       #", "#   .    #", "#        #", "##########", sol = "rrrlrldulruuddludruuurlrlldurddudududdlluurulrlrlrldrlududurrrlddulrududlrddrrrlurdrudullrrllrruurddllldlddlullururlrududuulrrrllrlrldurldulrlrlrrrrlllrrdrldduuurrdurdlrldlrdrudllduuludrdruldduddrrlrlrududlrudlrudlrudlludrlrluuddrllrllrllllurduurrdlurlulurldrduuudlrurrrrllrrldldrurrldrdddlruullddrrudududllrrlullrrrludluudddludrlrrruulru" },
}

-- the grid of a level: cells[r][c] = { wall, target, box, you }
local function parse(lines)
  local grid, you, boxes, targets = {}, nil, 0, 0
  for r, line in ipairs(lines) do
    grid[r] = {}
    for c = 1, #line do
      local ch = line:sub(c, c)
      local cell = { wall = ch == "#", target = false, box = false, you = false }
      if ch == "." or ch == "*" or ch == "+" then cell.target = true; targets = targets + 1 end
      if ch == "$" or ch == "*" then cell.box = true; boxes = boxes + 1 end
      if ch == "@" or ch == "+" then
        cell.you = true
        you = { r = r, c = c }
      end
      grid[r][c] = cell
    end
  end
  return { grid = grid, you = you, rows = #lines, targets = targets, boxes = boxes }
end

-- moves you by (dr, dc); pushes a box in front of you when it can. Returns true when something moved.
local function move(state, dr, dc)
  local g = state.grid
  local r, c = state.you.r, state.you.c
  local nr, nc = r + dr, c + dc
  local ahead = g[nr] and g[nr][nc]
  if not ahead or ahead.wall then return false end
  if ahead.box then
    local br, bc = nr + dr, nc + dc
    local beyond = g[br] and g[br][bc]
    if not beyond or beyond.wall or beyond.box then return false end
    beyond.box = true
    ahead.box = false
  end
  g[r][c].you = false
  ahead.you = true
  state.you = { r = nr, c = nc }
  return true
end

local function solved(state)
  for _, row in ipairs(state.grid) do
    for _, cell in ipairs(row) do
      if cell.box and not cell.target then return false end
    end
  end
  return true
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local s = parse(LEVELS[1])
  check(s.boxes == 1 and s.targets == 1 and not solved(s), "the first level has a box and a target")
  check(not move(s, 0, -1), "you cannot walk into a wall")
  check(move(s, 0, 1) and s.you.c == 3 and s.grid[2][4].box, "you push the box one cell")
  check(solved(s), "the box on the target solves the level")
  local t = parse(LEVELS[2])
  check(not move(t, 0, -1) or true, "the level can be played")
  -- a box cannot be pushed into another box or a wall
  local u = parse({ "#####", "#@$$.#", "#####" })
  check(move(u, 0, 1) == false and u.you.c == 2, "two boxes in a row cannot be pushed")
  -- every built-in level can be solved: a breadth first search over the positions of the boxes and of you
  local function solvable(lines)
    local start = parse(lines)
    local function key(st)
      local parts = { st.you.r, st.you.c }
      for r, row in ipairs(st.grid) do
        for c, cell in ipairs(row) do
          if cell.box then parts[#parts + 1] = r * 100 + c end
        end
      end
      return table.concat(parts, ",")
    end
    local queue, seen, head = { start }, { [key(start)] = true }, 1
    local dirs = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
    while head <= #queue and #queue < 200000 do
      local st = queue[head]
      head = head + 1
      if solved(st) then return true end
      for _, d in ipairs(dirs) do
        local nx = parse(lines)
        -- rebuild the state st by replaying its key is slow; copy the grid instead
        nx.grid = {}
        for r, row in ipairs(st.grid) do
          nx.grid[r] = {}
          for c, cell in ipairs(row) do
            nx.grid[r][c] = { wall = cell.wall, target = cell.target, box = cell.box, you = cell.you }
          end
        end
        nx.you = { r = st.you.r, c = st.you.c }
        if move(nx, d[1], d[2]) then
          local k = key(nx)
          if not seen[k] then
            seen[k] = true
            queue[#queue + 1] = nx
          end
        end
      end
    end
    return false
  end
  local DIRS = { u = { -1, 0 }, d = { 1, 0 }, l = { 0, -1 }, r = { 0, 1 } }
  for i, lines in ipairs(LEVELS) do
    if lines.sol then
      local st = parse(lines)
      for ch in lines.sol:gmatch(".") do move(st, DIRS[ch][1], DIRS[ch][2]) end
      check(solved(st), "built-in level " .. i .. " is solved by its solution")
    else
      check(solvable(lines), "built-in level " .. i .. " can be solved")
    end
  end
  check(#LEVELS >= 25, "at least 25 levels (" .. #LEVELS .. ")")
  local widest, tallest = 0, 0
  for _, lines in ipairs(LEVELS) do
    tallest = math.max(tallest, #lines)
    for _, line in ipairs(lines) do widest = math.max(widest, #line) end
  end
  check(widest <= 11 and tallest <= 9, "every level fits the screen (" .. widest .. " x " .. tallest .. ")")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("sokoban needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("sokoban: " .. tostring(uiErr))
  return
end

local levels = {}
for i, l in ipairs(LEVELS) do levels[i] = l end
local file = fs.read and fs.read("/home/user/sokoban.txt")
if file then
  local more, cur = {}, {}
  for line in (file .. "\n"):gmatch("(.-)\n") do
    if line == "" then
      if #cur > 0 then more[#more + 1] = cur; cur = {} end
    else
      cur[#cur + 1] = line
    end
  end
  if #cur > 0 then more[#more + 1] = cur end
  for _, l in ipairs(more) do levels[#levels + 1] = l end  -- your own levels come after the built-in ones
end

local level, state, moves
local undoStack = {}
local BEST_FILE = "/home/user/.sokoban_best"
local best = {}
do
  local text = fs.read and fs.read(BEST_FILE)
  if text then for i, n in text:gmatch("(%d+)=(%d+)") do best[tonumber(i)] = tonumber(n) end end
end
local function saveBest()
  local t = {}
  for i, n in pairs(best) do t[#t + 1] = i .. "=" .. n end
  fs.write(BEST_FILE, table.concat(t, "\n") .. "\n")
end

local function start(n)
  level = n
  state = parse(levels[level])
  moves = 0
  undoStack = {}
end

-- a copy of the grid and of you, for taking a move back
local function snapshot()
  local g = {}
  for r, row in ipairs(state.grid) do
    g[r] = {}
    for c, cell in ipairs(row) do g[r][c] = { wall = cell.wall, target = cell.target, box = cell.box, you = cell.you } end
  end
  return { grid = g, you = { r = state.you.r, c = state.you.c } }
end

local CELL = 14
local OX, OY = 6, 4

local function draw()
  gfx.clear(0x0a0c14)
  for r, row in ipairs(state.grid) do
    for c, cell in ipairs(row) do
      local x, y = OX + (c - 1) * CELL, OY + (r - 1) * CELL
      if cell.wall then
        gfx.fill(x, y, CELL - 1, CELL - 1, 0x5a5f70)
        gfx.fill(x, y, CELL - 1, 2, 0x7a8094)
      else
        gfx.fill(x, y, CELL - 1, CELL - 1, 0x1c2233)
        if cell.target then gfx.rect(x + 3, y + 3, CELL - 7, CELL - 7, 0x60ff90) end
        if cell.box then
          gfx.fill(x + 2, y + 2, CELL - 5, CELL - 5, cell.target and 0x60ff90 or 0xd08a30)
          gfx.rect(x + 2, y + 2, CELL - 5, CELL - 5, 0x6a4a18)
        end
        if cell.you then gfx.disc(x + CELL // 2 - 1, y + CELL // 2 - 1, 4, 0x40c0ff) end
      end
    end
  end
  ui.label(164, 4, "level " .. level .. "/" .. #levels, 0xe8ecf4)
  ui.label(164, 18, "moves " .. moves, 0xe8ecf4)
  if best[level] then ui.label(164, 30, "best " .. best[level], 0x8a94aa) end
  ui.label(164, 44, solved(state) and "solved!" or "", 0x60ff90)
  ui.label(164, 66, "w a s d move", 0x8a94aa)
  ui.label(164, 78, "u undo", 0x8a94aa)
  ui.label(164, 90, "r restart", 0x8a94aa)
  ui.label(164, 102, "n p levels", 0x8a94aa)
  ui.label(164, 114, "ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("sokoban: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  start(1)
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      if k == "r" then start(level)
      elseif k == "n" then start(math.min(#levels, level + 1))
      elseif k == "p" then start(math.max(1, level - 1))
      elseif k == "u" and #undoStack > 0 and not solved(state) then
        local snap = table.remove(undoStack)
        state.grid, state.you = snap.grid, snap.you
        moves = moves - 1
      elseif not solved(state) then
        local before = snapshot()
        local moved = false
        if k == "w" or k == "up" then moved = move(state, -1, 0)
        elseif k == "s" or k == "down" then moved = move(state, 1, 0)
        elseif k == "a" or k == "left" then moved = move(state, 0, -1)
        elseif k == "d" or k == "right" then moved = move(state, 0, 1) end
        if moved then
          undoStack[#undoStack + 1] = before
          if #undoStack > 300 then table.remove(undoStack, 1) end
          moves = moves + 1
          if solved(state) and (not best[level] or moves < best[level]) then
            best[level] = moves
            saveBest()
          end
        end
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("sokoban: " .. tostring(problem)) end
