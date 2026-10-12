#!lua
-- fifteen: the sliding puzzle. Put the numbered tiles in order, with the gap in the bottom right corner. A tile next to the gap
-- slides into it: w a s d (or the arrows) move the tile in that direction, so "d" slides the tile on the left of the gap to the
-- right. Choose 3x3, 4x4 or 5x5. The puzzle is always solvable. The fewest moves of each size are kept. n shuffles again,
-- ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the rules.

local W, H = 240, 135
local BEST_FILE = "/home/user/.fifteen_best"

-- the board is a flat list n*n, 0 is the gap; the solved board is 1..n*n-1, 0
local function solvedBoard(n)
  local b = {}
  for i = 1, n * n - 1 do b[i] = i end
  b[n * n] = 0
  return b
end

local function isSolved(b)
  for i = 1, #b - 1 do
    if b[i] ~= i then return false end
  end
  return b[#b] == 0
end

-- slides the tile that is in direction (dr, dc) away from the gap... in the direction the key says: a move "d" (dc = 1) moves the tile
-- left of the gap to the right. Returns true when a tile moved.
local function slide(b, n, dr, dc)
  local gap
  for i = 1, #b do if b[i] == 0 then gap = i break end end
  local gr, gc = (gap - 1) // n, (gap - 1) % n
  local tr, tc = gr - dr, gc - dc  -- the tile that moves into the gap
  if tr < 0 or tr >= n or tc < 0 or tc >= n then return false end
  local ti = tr * n + tc + 1
  b[gap], b[ti] = b[ti], 0
  return true
end

-- shuffled by random moves from the solved board, so it can always be solved; the last move is never undone at once
local function shuffled(n)
  local b = solvedBoard(n)
  local dirs = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
  local lastDr, lastDc = 0, 0
  for _ = 1, n * n * 24 do
    local d = dirs[math.random(4)]
    if not (d[1] == -lastDr and d[2] == -lastDc) and slide(b, n, d[1], d[2]) then lastDr, lastDc = d[1], d[2] end
  end
  if isSolved(b) then slide(b, n, 0, 1) end
  return b
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local b = solvedBoard(4)
  check(isSolved(b) and b[16] == 0 and b[15] == 15, "the solved board")
  check(slide(b, 4, 0, 1) == true and b[16] == 15 and b[15] == 0, "d slides the tile on the left into the gap")
  check(slide(b, 4, 0, -1) == true and isSolved(b), "a slides it back")
  b = solvedBoard(3)
  check(slide(b, 3, 1, 0) == true and b[9] == 6, "s slides the tile above the gap down")
  check(slide(b, 3, 0, -1) == false, "a needs a tile on the right of the gap: none at the edge")
  check(slide(b, 3, 0, 1) == true and b[6] == 5, "d slides the tile on the left of the gap to the right")
  -- a shuffled board has the same tiles and is not solved
  for _, n in ipairs({ 3, 4, 5 }) do
    local s = shuffled(n)
    local seen, sum = {}, 0
    for _, v in ipairs(s) do seen[v] = true sum = sum + v end
    check(#s == n * n and sum == (n * n - 1) * (n * n) // 2 and not isSolved(s), n .. "x" .. n .. " shuffle keeps the tiles")
  end
  -- solvability: the parity of the inversions with the row of the gap decides it
  local function solvable(s, n)
    local inv = 0
    for i = 1, #s do
      for j = i + 1, #s do
        if s[i] ~= 0 and s[j] ~= 0 and s[i] > s[j] then inv = inv + 1 end
      end
    end
    local gapRow
    for i = 1, #s do if s[i] == 0 then gapRow = (i - 1) // n end end
    if n % 2 == 1 then return inv % 2 == 0 end
    return (inv + (n - gapRow)) % 2 == 1
  end
  local good = true
  for _ = 1, 20 do
    for _, n in ipairs({ 3, 4, 5 }) do if not solvable(shuffled(n), n) then good = false end end
  end
  check(good, "every shuffled board is solvable")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("fifteen needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("fifteen: " .. tostring(uiErr))
  return
end

local best = {}
do
  local text = fs.read(BEST_FILE)
  if text then for i, n in text:gmatch("(%d)=(%d+)") do best[tonumber(i)] = tonumber(n) end end
end
local function saveBest()
  local t = {}
  for i, n in pairs(best) do t[#t + 1] = i .. "=" .. n end
  fs.write(BEST_FILE, table.concat(t, "\n") .. "\n")
end

local n, board, moves, startT, finished
local function newGame()
  board, moves, startT, finished = shuffled(n), 0, sys.millis(), nil
end

local function draw()
  gfx.clear(0x0c1018)
  local cell = n == 3 and 38 or (n == 4 and 30 or 24)
  local ox, oy = 10, (H - n * cell) // 2
  gfx.fill(ox - 3, oy - 3, n * cell + 6, n * cell + 6, 0x20283c)
  for i, v in ipairs(board) do
    local r, c = (i - 1) // n, (i - 1) % n
    local x, y = ox + c * cell, oy + r * cell
    if v ~= 0 then
      local home = v == i
      gfx.fill(x + 1, y + 1, cell - 2, cell - 2, home and 0x2c8a50 or 0x3454a8)
      gfx.fill(x + 1, y + 1, cell - 2, 2, home and 0x50c880 or 0x5a7ad8)
      ui.center(y + cell // 2 - (n == 5 and 3 or 7), tostring(v), 0xffffff, n == 5 and 1 or 2, x, x + cell)
    end
  end
  local secs = ((finished or sys.millis()) - startT) // 1000
  local px = ox + n * cell + 14
  ui.label(px, 8, "FIFTEEN", 0xe8ecf4, 2)
  ui.label(px, 32, string.format("%dx%d", n, n), 0x8a94aa)
  ui.label(px, 46, "moves " .. moves, 0xe8ecf4)
  ui.label(px, 58, string.format("time  %d:%02d", secs // 60, secs % 60), 0xe8ecf4)
  if best[n] then ui.label(px, 70, "best  " .. best[n], 0x8a94aa) end
  if finished then ui.label(px, 88, "SOLVED!", 0x60ff90, 2) end
  ui.label(px, 106, "w a s d slide", 0x8a94aa)
  ui.label(px, 116, "n new  ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("fifteen: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local pick = ui.choose("Fifteen: size", { "3 x 3", "4 x 4", "5 x 5" }, { selected = 2 })
  if not pick then return end
  n = pick + 2
  newGame()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      local moved = false
      if not finished then
        if k == "w" or k == "up" then moved = slide(board, n, -1, 0)
        elseif k == "s" or k == "down" then moved = slide(board, n, 1, 0)
        elseif k == "a" or k == "left" then moved = slide(board, n, 0, -1)
        elseif k == "d" or k == "right" then moved = slide(board, n, 0, 1) end
      end
      if k == "n" then newGame() end
      if moved then
        moves = moves + 1
        if isSolved(board) then
          finished = sys.millis()
          if not best[n] or moves < best[n] then best[n] = moves saveBest() end
        end
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("fifteen: " .. tostring(problem)) end
