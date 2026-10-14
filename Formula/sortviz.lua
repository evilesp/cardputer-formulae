#!lua
-- sortviz: sorting algorithms drawn as bars. 40 bars of random height are sorted step by step by bubble sort,
-- insertion sort or selection sort; the bars being compared are highlighted, and the sorted bars turn green.
-- Keys: 1 bubble sort, 2 insertion sort, 3 selection sort (each starts on a new shuffle), n new shuffle,
-- w and s change the speed, p pauses, q quits. Needs the graphics (firmware v0.1.0.13).
-- Run it with --selftest to check the sorting steps.

local N = 40  -- bars
local BAR_W = 6  -- 40 bars x 6 px cover the 240 px width (one px of gap in each bar)
local BASE = 120  -- the bars stand on this line; the bottom line is the text
local BAR, HOT, DONE, OFF = 0x40c0ff, 0xff8040, 0x40ff80, 0x000000
local SPEEDS = { 1, 2, 4, 8, 16, 32 }  -- comparisons a frame
local ALGOS = { "bubble", "insertion", "selection" }
local NAMES = { bubble = "bubble sort", insertion = "insertion sort", selection = "selection sort" }

-- a small generator, so the selftest always gets the same numbers
local seed = 12345
local function random(n)  -- a number from 1 to n
  seed = (seed * 1103515245 + 12345) % 2147483648
  return (seed // 65536) % n + 1
end

-- the numbers 1 to n in a random order, kept in the same table (no new table for a new shuffle)
local function shuffle(a, n)
  for k = 1, n do a[k] = k end
  for k = n, 2, -1 do
    local r = random(k)
    a[k], a[r] = a[r], a[k]
  end
end

-- the state of one sort: every comparison is one step, the cursor positions are kept to be drawn
local function newSort(kind, n)
  local s = { kind = kind, n = n, steps = 0, hi = 0, hj = 0, done = false }
  if kind == "bubble" then
    s.i, s.j = 0, 1  -- passes finished, next pair to compare
  elseif kind == "insertion" then
    s.i, s.j = 2, 2  -- the next card to place, the position it is moving to
  else
    s.i, s.j, s.m = 1, 2, 1  -- the first unsorted position, the scan, the smallest found so far
  end
  return s
end

local function swap(a, x, y)
  a[x], a[y] = a[y], a[x]
end

-- one step: one comparison (and a swap when it is needed)
local function sortStep(s, a)
  local n = s.n
  if s.done then return end
  if s.kind == "bubble" then
    if s.j > n - 1 - s.i then  -- the pass is over: the largest bar of the unsorted part is at the end
      s.i = s.i + 1
      s.j = 1
      if s.i >= n - 1 then s.done = true return end
    end
    s.hi, s.hj = s.j, s.j + 1
    if a[s.j] > a[s.j + 1] then swap(a, s.j, s.j + 1) end
    s.j = s.j + 1
    s.steps = s.steps + 1
  elseif s.kind == "insertion" then
    if s.i > n then s.done = true return end
    if s.j > 1 then
      s.hi, s.hj = s.j - 1, s.j
      s.steps = s.steps + 1
      if a[s.j - 1] > a[s.j] then
        swap(a, s.j - 1, s.j)  -- the card moves down past the bigger one
        s.j = s.j - 1
        return
      end
    end
    s.i = s.i + 1  -- the card is in place: take the next one
    s.j = s.i
  else
    if s.i >= n then s.done = true return end
    if s.j <= n then
      s.hi, s.hj = s.j, s.m
      s.steps = s.steps + 1
      if a[s.j] < a[s.m] then s.m = s.j end
      s.j = s.j + 1
    else
      s.hi, s.hj = s.i, s.m
      swap(a, s.i, s.m)  -- the smallest of the rest goes to its place
      s.i = s.i + 1
      s.m = s.i
      s.j = s.i + 1
    end
  end
end

local function draw(a, s, paused)
  gfx.fill(0, 0, 240, BASE + 2, OFF)
  for k = 1, s.n do
    local h = a[k] * 5 // 2  -- heights from 2 px to 100 px
    local c = BAR
    if s.done then
      c = DONE
    elseif k == s.hi or k == s.hj then
      c = HOT
    end
    gfx.fill((k - 1) * BAR_W, BASE - h, BAR_W - 1, h, c)
  end
  gfx.fill(0, 122, 240, 13, OFF)
  local text = NAMES[s.kind] .. (s.done and " done in " or " ") .. s.steps .. " steps"
  if paused then text = "paused: " .. text end
  gfx.text(2, 124, text .. "  n new  q", 0x9aa8c0, 1)
  gfx.flush()
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local function run(kind, a)
    local s = newSort(kind, #a)
    local guard = 0
    while not s.done and guard < 1000 do
      sortStep(s, a)
      guard = guard + 1
    end
    return s
  end
  local function sorted(a)
    for k = 2, #a do
      if a[k - 1] > a[k] then return false end
    end
    return true
  end
  for _, kind in ipairs(ALGOS) do
    local a = { 5, 2, 9, 1, 5, 6, 3 }
    local s = run(kind, a)
    check(s.done and sorted(a), kind .. " sort puts the numbers in order")
    check(s.steps >= 6 and s.steps <= 21, kind .. " sort of 7 numbers takes 6 to 21 comparisons")
    local b = { 4 }
    check(run(kind, b).steps == 0 and b[1] == 4, kind .. " sort of one number does nothing")
  end
  local sortedIn = { 1, 2, 3, 4, 5, 6, 7 }
  check(run("insertion", sortedIn).steps == 6, "insertion sort of sorted numbers makes one comparison per card")
  local rev = { 3, 2, 1 }
  check(run("selection", rev).steps == 3 and rev[1] == 1 and rev[3] == 3, "selection sort of three numbers takes 3 comparisons")
  local big = {}
  shuffle(big, N)
  local seen, total = {}, 0
  for k = 1, N do
    seen[big[k]] = (seen[big[k]] or 0) + 1
    total = total + big[k]
  end
  local once = true
  for v = 1, N do
    if seen[v] ~= 1 then once = false end
  end
  check(once and total == N * (N + 1) // 2, "a shuffle keeps every number once")
  for _, kind in ipairs(ALGOS) do
    local a = {}
    shuffle(a, N)
    local s = run(kind, a)
    check(s.done and sorted(a), kind .. " sort of 40 bars puts them in order")
  end
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("sortviz needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("sortviz: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local a, kind = {}, "bubble"
  shuffle(a, N)
  local s = newSort(kind, N)
  local speed, paused = 3, false  -- index into SPEEDS: 4 comparisons a frame to start
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == "p" then
        paused = not paused
      elseif k == "n" then
        shuffle(a, N)
        s = newSort(kind, N)
      elseif k == "1" or k == "2" or k == "3" then
        kind = ALGOS[tonumber(k)]
        shuffle(a, N)
        s = newSort(kind, N)
      elseif k == "w" or k == "up" then
        speed = math.min(#SPEEDS, speed + 1)
      elseif k == "s" or k == "down" then
        speed = math.max(1, speed - 1)
      end
      k = key.poll()
    end
    if not paused then
      for _ = 1, SPEEDS[speed] do
        sortStep(s, a)
      end
    end
    draw(a, s, paused)
    sys.sleep(30)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("sortviz: " .. tostring(problem)) end
