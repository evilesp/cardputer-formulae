#!lua
-- whackamole: moles pop up out of nine holes and hide again. Press the digit 1 to 9 of a hole to whack the mole
-- in it, or move the cursor with w a s d and press enter (or space). A hit scores 10 points, or 15 when it comes
-- early, while the mole is still fresh. Whacking an empty hole costs 5 points. A game lasts 30 seconds and gets
-- faster as it goes; space starts a game, q or ctrl-q quits. The best score is kept while the app runs.
-- Needs the graphics and the ui package. Run it with --selftest to check the rules.

local GAME_MS = 30000
local FLASH_MS = 160

-- the time between two new moles in milliseconds, shorter as the game goes on
local function spawnGap(elapsed)
  return math.max(350, 900 - elapsed // 60)
end

-- how long a mole stays up in milliseconds, shorter as the game goes on
local function stayFor(elapsed)
  return math.max(400, 1100 - elapsed // 50)
end

-- the points for a hit: more when the mole was still up for at least half of its time
local function pointsFor(remaining, total)
  if remaining * 2 >= total then return 15 end
  return 10
end

-- the score after a missed whack, which never goes below zero
local function missed(score)
  return math.max(0, score - 5)
end

-- the row and the column of hole i, 1 to 9, row by row
local function rowOf(i) return (i - 1) // 3 + 1 end
local function colOf(i) return (i - 1) % 3 + 1 end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(spawnGap(0) == 900, "the first moles come 900 ms apart")
  check(spawnGap(30000) == 400, "the moles come 400 ms apart near the end")
  check(spawnGap(600000) == 350, "the moles never come faster than 350 ms apart")
  check(stayFor(0) == 1100, "a mole first stays up 1100 ms")
  check(stayFor(30000) == 500, "a mole stays up 500 ms near the end")
  check(stayFor(900000) == 400, "a mole never stays up less than 400 ms")
  check(pointsFor(800, 1000) == 15, "a quick hit scores 15")
  check(pointsFor(400, 1000) == 10, "a slow hit scores 10")
  check(missed(0) == 0 and missed(12) == 7, "a miss costs 5 and not below zero")
  check(rowOf(1) == 1 and colOf(1) == 1, "hole 1 is the top left")
  check(rowOf(6) == 2 and colOf(6) == 3, "hole 6 is the middle row, right")
  check(rowOf(9) == 3 and colOf(9) == 3, "hole 9 is the bottom right")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("whackamole needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("whackamole: " .. tostring(uiErr))
  return
end

-- state: "idle" (before a game), "play", "over"
local state = "idle"
local startAt, endAt, nextSpawn = 0, 0, 0
local score, best, hits, misses = 0, 0, 0, 0
local cr, cc = 2, 2
-- per hole: the time the mole leaves (0 when the hole is empty), the time it had to stay up, and when a flash ends
local upUntil, upTotal, flashUntil = {}, {}, {}
for i = 1, 9 do
  upUntil[i], upTotal[i], flashUntil[i] = 0, 0, 0
end

local function hideAll()
  for i = 1, 9 do
    upUntil[i], upTotal[i], flashUntil[i] = 0, 0, 0
  end
end

local function newGame(now)
  hideAll()
  state = "play"
  startAt, endAt = now, now + GAME_MS
  nextSpawn = now + spawnGap(0)
  score, hits, misses = 0, 0, 0
  cr, cc = 2, 2
end

-- the mole leaves holes after their time, and a new mole comes up from an empty hole
local function update(now)
  if now >= endAt then
    state = "over"
    hideAll()
    if score > best then best = score end
    return
  end
  for i = 1, 9 do
    if upUntil[i] > 0 and now >= upUntil[i] then upUntil[i] = 0 end
  end
  if now >= nextSpawn then
    local elapsed = now - startAt
    for _ = 1, 20 do
      local i = math.random(9)
      if upUntil[i] == 0 then
        upTotal[i] = stayFor(elapsed)
        upUntil[i] = now + upTotal[i]
        break
      end
    end
    nextSpawn = now + spawnGap(elapsed)
  end
end

-- whacks hole i: a hit takes the mole away, a miss on an empty hole costs points
local function whack(i, now)
  if state ~= "play" then return end
  if upUntil[i] > 0 then
    score = score + pointsFor(upUntil[i] - now, upTotal[i])
    hits = hits + 1
    upUntil[i] = 0
    flashUntil[i] = now + FLASH_MS
  else
    score = missed(score)
    misses = misses + 1
  end
end

local function drawHole(i, now)
  local cx = 30 + (colOf(i) - 1) * 38
  local cy = 36 + (rowOf(i) - 1) * 32
  gfx.disc(cx, cy + 2, 13, 0x2a1c10)
  gfx.disc(cx, cy + 2, 11, 0x0a0806)
  if upUntil[i] > 0 then
    gfx.disc(cx, cy - 4, 9, 0xb07040)
    gfx.disc(cx - 3, cy - 6, 1, 0x000000)
    gfx.disc(cx + 3, cy - 6, 1, 0x000000)
    gfx.disc(cx, cy - 2, 1, 0x000000)
  end
  if flashUntil[i] > now then
    gfx.circle(cx, cy, 15, 0xffe060, false)
  end
  if state == "play" and rowOf(i) == cr and colOf(i) == cc then
    gfx.rect(cx - 16, cy - 16, 32, 32, 0xf0d060)
  end
end

local function draw(now)
  gfx.clear(0x142a1c)
  for i = 1, 9 do
    drawHole(i, now)
  end
  ui.label(132, 4, "WHACK-A-MOLE", 0xe8ecf4)
  local left = state == "play" and math.max(0, endAt - now) // 1000 or GAME_MS // 1000
  ui.label(132, 18, "time " .. left .. " s", 0xe8ecf4)
  ui.label(132, 30, "score " .. score, 0x60ff90)
  ui.label(132, 42, "best " .. best, 0xf0d060)
  ui.label(132, 54, "hits " .. hits .. "  misses " .. misses, 0x8a94aa)
  if state == "idle" then
    ui.label(132, 72, "space starts", 0xe8ecf4)
  elseif state == "over" then
    ui.label(132, 72, "time is up!", 0xf0a060)
    ui.label(132, 84, "space plays again", 0xe8ecf4)
  else
    ui.label(132, 72, "whack the moles", 0xe8ecf4)
  end
  ui.label(132, 100, "1-9 whack a hole", 0x8a94aa)
  ui.label(132, 110, "w a s d enter", 0x8a94aa)
  ui.label(132, 120, "q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("whackamole: " .. tostring(h))
  return
end
math.randomseed(sys.millis())
local ok, problem = pcall(function()
  while true do
    local now = sys.millis()
    if state == "play" then update(now) end
    draw(now)
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      if k == "q" then return end
      local digit = tonumber(k)
      if (k == " " or k == "enter") and state ~= "play" then
        newGame(sys.millis())
      elseif state == "play" and digit and digit >= 1 and digit <= 9 then
        whack(digit, sys.millis())
      elseif state == "play" and (k == " " or k == "enter") then
        whack((cr - 1) * 3 + cc, sys.millis())
      elseif state == "play" and k == "w" then cr = math.max(1, cr - 1)
      elseif state == "play" and k == "s" then cr = math.min(3, cr + 1)
      elseif state == "play" and k == "a" then cc = math.max(1, cc - 1)
      elseif state == "play" and k == "d" then cc = math.min(3, cc + 1)
      end
      k = key.poll()
    end
    sys.sleep(20)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("whackamole: " .. tostring(problem)) end
