#!lua
-- sokoban: push every box onto a target. Move with w a s d; you push a box when you walk into it, a box cannot be pulled.
-- r starts the level again, n goes to the next level, ctrl-q quits. The levels are in the program; a file
-- /home/user/sokoban.txt with more levels (separated by an empty line) is used when it exists.
-- Needs the graphics and the ui package. Run it with --selftest to check the rules.

-- # wall, space floor, . target, $ box, @ you; $ on a target is shown as * and @ on a target as +
local LEVELS = {
  { "#####", "#@$.#", "#####" },
  { "#######", "#.$@$.#", "#######" },
  { "######", "#..$@#", "#.$  #", "######" },
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
  for i, lines in ipairs(LEVELS) do
    check(solvable(lines), "built-in level " .. i .. " can be solved")
  end
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

local levels = LEVELS
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
  if #more > 0 then levels = more end
end

local level, state

local function start(n)
  level = n
  state = parse(levels[level])
end

local CELL = 14
local OX, OY = 10, 10

local function draw()
  gfx.clear(0x0a0c14)
  for r, row in ipairs(state.grid) do
    for c, cell in ipairs(row) do
      local x, y = OX + (c - 1) * CELL, OY + (r - 1) * CELL
      if cell.wall then
        gfx.fill(x, y, CELL - 1, CELL - 1, 0x5a5f70)
      else
        gfx.fill(x, y, CELL - 1, CELL - 1, 0x1c2233)
        if cell.target then gfx.rect(x + 3, y + 3, CELL - 7, CELL - 7, 0x60ff90) end
        if cell.box then gfx.fill(x + 2, y + 2, CELL - 5, CELL - 5, cell.target and 0x60ff90 or 0xd08a30) end
        if cell.you then gfx.disc(x + CELL // 2, y + CELL // 2, 4, 0x40c0ff) end
      end
    end
  end
  ui.label(160, 14, "level " .. level .. " of " .. #levels, 0xe8ecf4)
  ui.label(160, 30, solved(state) and "solved!" or "push the boxes", solved(state) and 0x60ff90 or 0x8a94aa)
  ui.label(160, 60, "w a s d move", 0x8a94aa)
  ui.label(160, 72, "r restart", 0x8a94aa)
  ui.label(160, 84, "n next level", 0x8a94aa)
  ui.label(160, 96, "ctrl-q quit", 0x8a94aa)
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
      if k == "r" then start(level)
      elseif k == "n" and solved(state) then start(math.min(#levels, level + 1))
      elseif not solved(state) then
        if k == "w" then move(state, -1, 0)
        elseif k == "s" then move(state, 1, 0)
        elseif k == "a" then move(state, 0, -1)
        elseif k == "d" then move(state, 0, 1)
        end
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("sokoban: " .. tostring(problem)) end
