#!lua
-- battleship: sink the enemy fleet before it sinks yours. Each side hides five ships (5, 4, 3, 3 and 2 squares long) on a 10 x 10
-- sea and shoots one square a turn; a hit lets you shoot again. Press r to place your fleet again until you like it, then enter
-- to start. Move on the enemy sea with w a s d and fire with space. The bot hunts at random and, after a hit, follows the ship.
-- n starts a new game, ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the rules.

local N = 10
local SHIPS = { 5, 4, 3, 3, 2 }

-- a sea: cells[r][c] = ship number (0 water), shots[r][c] = nil, "miss" or "hit"
local function newSea()
  local s = { ships = {}, cells = {}, shots = {} }
  for r = 1, N do
    s.cells[r], s.shots[r] = {}, {}
    for c = 1, N do s.cells[r][c] = 0 end
  end
  return s
end

local function canPlace(sea, r, c, len, horizontal)
  for i = 0, len - 1 do
    local rr, cc = r + (horizontal and 0 or i), c + (horizontal and i or 0)
    if rr < 1 or rr > N or cc < 1 or cc > N or sea.cells[rr][cc] ~= 0 then return false end
  end
  return true
end

-- puts the five ships at random places without touching the edge of another ship... (they may touch)
local function placeFleet(sea)
  sea.ships = {}
  for i, len in ipairs(SHIPS) do
    while true do
      local h = math.random(2) == 1
      local r, c = math.random(N), math.random(N)
      if canPlace(sea, r, c, len, h) then
        local cells = {}
        for k = 0, len - 1 do
          local rr, cc = r + (h and 0 or k), c + (h and k or 0)
          sea.cells[rr][cc] = i
          cells[#cells + 1] = { rr, cc }
        end
        sea.ships[i] = { len = len, cells = cells, hits = 0 }
        break
      end
    end
  end
end

-- a shot: returns "miss", "hit", "sunk" (with the ship number) or nil when the square was shot before
local function shoot(sea, r, c)
  if sea.shots[r][c] then return nil end
  local id = sea.cells[r][c]
  if id == 0 then
    sea.shots[r][c] = "miss"
    return "miss"
  end
  sea.shots[r][c] = "hit"
  local ship = sea.ships[id]
  ship.hits = ship.hits + 1
  if ship.hits == ship.len then return "sunk", id end
  return "hit"
end

local function fleetSunk(sea)
  for _, s in ipairs(sea.ships) do
    if s.hits < s.len then return false end
  end
  return true
end

local function isSunkShip(sea, r, c)
  local id = sea.cells[r][c]
  return id ~= 0 and sea.ships[id].hits == sea.ships[id].len
end

-- the bot: when it has hit a ship that is not sunk it shoots next to those hits (along the line when it knows it); else it
-- shoots a random square of the chequer pattern (every ship is at least two long, so half the squares are enough)
local function botShot(sea)
  local open = {}
  for r = 1, N do
    for c = 1, N do
      if not sea.shots[r][c] and sea.cells then open[#open + 1] = { r, c } end
    end
  end
  -- the hits of ships that still float
  local hits = {}
  for r = 1, N do
    for c = 1, N do
      if sea.shots[r][c] == "hit" and not isSunkShip(sea, r, c) then hits[#hits + 1] = { r, c } end
    end
  end
  if #hits > 0 then
    local cand = {}
    local function free(r, c) return r >= 1 and r <= N and c >= 1 and c <= N and not sea.shots[r][c] end
    local lineH, lineV = false, false
    for _, a in ipairs(hits) do
      for _, b in ipairs(hits) do
        if a[1] == b[1] and math.abs(a[2] - b[2]) == 1 then lineH = true end
        if a[2] == b[2] and math.abs(a[1] - b[1]) == 1 then lineV = true end
      end
    end
    for _, h in ipairs(hits) do
      for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
        local horizontal = d[1] == 0
        if free(h[1] + d[1], h[2] + d[2]) and not (lineH and not horizontal) and not (lineV and horizontal) then
          cand[#cand + 1] = { h[1] + d[1], h[2] + d[2] }
        end
      end
    end
    if #cand > 0 then return cand[math.random(#cand)] end
  end
  local parity = {}
  for _, p in ipairs(open) do
    if (p[1] + p[2]) % 2 == 0 then parity[#parity + 1] = p end
  end
  local pool = #parity > 0 and parity or open
  return pool[math.random(#pool)]
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  for _ = 1, 20 do
    local sea = newSea()
    placeFleet(sea)
    local total = 0
    for r = 1, N do for c = 1, N do if sea.cells[r][c] ~= 0 then total = total + 1 end end end
    check(total == 17 and #sea.ships == 5, "the fleet has 17 squares")
  end
  local sea = newSea()
  sea.ships = { { len = 2, cells = { { 1, 1 }, { 1, 2 } }, hits = 0 } }
  sea.cells[1][1], sea.cells[1][2] = 1, 1
  check(shoot(sea, 3, 3) == "miss" and shoot(sea, 3, 3) == nil, "a miss, and no second shot at a square")
  check(shoot(sea, 1, 1) == "hit", "a hit")
  local res, id = shoot(sea, 1, 2)
  check(res == "sunk" and id == 1 and fleetSunk(sea), "the last square sinks the ship")
  -- the bot finishes a whole game on a random sea, never repeating a shot, in at most 100 shots
  local good, worst = true, 0
  for _ = 1, 30 do
    local s = newSea()
    placeFleet(s)
    local shots = 0
    while not fleetSunk(s) and shots <= 100 do
      local p = botShot(s)
      if not p or s.shots[p[1]][p[2]] then good = false break end
      shoot(s, p[1], p[2])
      shots = shots + 1
    end
    worst = math.max(worst, shots)
    if shots > 100 then good = false end
  end
  check(good, "the bot finishes every game without repeating a shot (worst " .. worst .. ")")
  -- after a hit the bot shoots next to it
  local s = newSea()
  s.ships = { { len = 3, cells = { { 5, 5 }, { 5, 6 }, { 5, 7 } }, hits = 0 } }
  s.cells[5][5], s.cells[5][6], s.cells[5][7] = 1, 1, 1
  shoot(s, 5, 6)
  local near = true
  for _ = 1, 20 do
    local p = botShot(s)
    if math.abs(p[1] - 5) + math.abs(p[2] - 6) ~= 1 then near = false end
  end
  check(near, "after a hit the bot shoots next to it")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("battleship needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("battleship: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local CELL = 10
local mine, enemy, cur, phase, message, turn, wins
wins = { 0, 0 }

local function newGame()
  mine, enemy = newSea(), newSea()
  placeFleet(mine)
  placeFleet(enemy)
  cur = { r = 5, c = 5 }
  phase, message, turn = "place", "r new places, enter start", "you"
end

local function drawSea(sea, ox, oy, own)
  gfx.fill(ox - 1, oy - 1, N * CELL + 2, N * CELL + 2, 0x20304c)
  for r = 1, N do
    for c = 1, N do
      local x, y = ox + (c - 1) * CELL, oy + (r - 1) * CELL
      local shot = sea.shots[r][c]
      local id = sea.cells[r][c]
      local colour = (r + c) % 2 == 0 and 0x123860 or 0x103058
      if own and id ~= 0 then colour = 0x6a7894 end
      gfx.fill(x, y, CELL - 1, CELL - 1, colour)
      if shot == "miss" then gfx.disc(x + 4, y + 4, 1, 0xd0e0ff)
      elseif shot == "hit" then
        gfx.fill(x + 1, y + 1, CELL - 3, CELL - 3, isSunkShip(sea, r, c) and 0x802020 or 0xe84030)
        gfx.line(x + 1, y + 1, x + CELL - 3, y + CELL - 3, 0xffd0a0)
        gfx.line(x + CELL - 3, y + 1, x + 1, y + CELL - 3, 0xffd0a0)
      end
    end
  end
end

local function draw()
  gfx.clear(0x08101c)
  ui.label(4, 2, "YOUR FLEET", 0x8a94aa)
  ui.label(W - 6 * 11 - 4, 2, "ENEMY SEA", 0xe8ecf4)
  drawSea(mine, 6, 14, true)
  local ex = W - N * CELL - 6
  drawSea(enemy, ex, 14, false)
  if phase == "play" and turn == "you" then
    gfx.rect(ex + (cur.c - 1) * CELL - 1, 14 + (cur.r - 1) * CELL - 1, CELL + 1, CELL + 1, 0xffe060)
  end
  -- the ships left on each side
  local function left(sea)
    local n = 0
    for _, s in ipairs(sea.ships) do if s.hits < s.len then n = n + 1 end end
    return n
  end
  ui.label(6, 116, "ships " .. left(mine), 0x8a94aa)
  ui.label(ex, 116, "ships " .. left(enemy), 0x8a94aa)
  ui.center(H - 10, message, phase == "over" and 0x60ff90 or 0xe8ecf4, 1)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("battleship: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newGame()
  local botAt
  while true do
    draw()
    if phase == "play" and turn == "bot" and sys.millis() >= botAt then
      local p = botShot(mine)
      local res = shoot(mine, p[1], p[2])
      if res == "miss" then
        turn, message = "you", "the bot missed: your turn"
      else
        message = res == "sunk" and "the bot sank your ship!" or "the bot hit your ship"
        botAt = sys.millis() + 700
      end
      if fleetSunk(mine) then
        phase, message = "over", "you lost. n new game"
        wins[2] = wins[2] + 1
      end
    end
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      if k == "n" then newGame()
      elseif phase == "place" then
        if k == "r" then
          mine = newSea()
          placeFleet(mine)
        elseif k == "enter" or k == " " then
          phase, message = "play", "your turn: w a s d move, space fire"
        end
      elseif phase == "play" and turn == "you" then
        if k == "w" or k == "up" then cur.r = math.max(1, cur.r - 1)
        elseif k == "s" or k == "down" then cur.r = math.min(N, cur.r + 1)
        elseif k == "a" or k == "left" then cur.c = math.max(1, cur.c - 1)
        elseif k == "d" or k == "right" then cur.c = math.min(N, cur.c + 1)
        elseif k == " " or k == "enter" then
          local res = shoot(enemy, cur.r, cur.c)
          if res == nil then message = "you shot there already"
          elseif res == "miss" then
            turn, message = "bot", "a miss"
            botAt = sys.millis() + 600
          else
            message = res == "sunk" and "you sank a ship! shoot again" or "a hit! shoot again"
            if fleetSunk(enemy) then
              phase, message = "over", "you won! n new game"
              wins[1] = wins[1] + 1
            end
          end
        end
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("battleship: " .. tostring(problem)) end
