#!lua
-- mastermind: guess the secret code of four colours (1 to 6). Type four digits and enter. Black marks a right colour in the
-- right place, white a right colour in the wrong place. You have ten tries. backspace deletes, n starts a new code,
-- ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the marks.

local SLOTS, COLOURS, TRIES = 4, 6, 10
local PALETTE = { 0xe04040, 0x40c040, 0x4080ff, 0xf0d040, 0xc050e0, 0x40d0d0 }

-- the marks for a guess against the code: black (right colour, right place) and white (right colour, wrong place)
local function marks(code, guess)
  local black, white = 0, 0
  local codeLeft, guessLeft = {}, {}
  for i = 1, #code do
    if code[i] == guess[i] then
      black = black + 1
    else
      codeLeft[#codeLeft + 1] = code[i]
      guessLeft[#guessLeft + 1] = guess[i]
    end
  end
  for _, g in ipairs(guessLeft) do
    for j, c in ipairs(codeLeft) do
      if c == g then
        white = white + 1
        table.remove(codeLeft, j)
        break
      end
    end
  end
  return black, white
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local b, w = marks({ 1, 2, 3, 4 }, { 1, 2, 3, 4 })
  check(b == 4 and w == 0, "the right code is four black")
  b, w = marks({ 1, 2, 3, 4 }, { 2, 1, 3, 4 })
  check(b == 2 and w == 2, "two swapped colours are two black and two white")
  b, w = marks({ 1, 1, 2, 3 }, { 1, 4, 4, 4 })
  check(b == 1 and w == 0, "a colour counts only as often as it is in the code")
  b, w = marks({ 1, 2, 3, 4 }, { 5, 6, 5, 6 })
  check(b == 0 and w == 0, "colours not in the code give no marks")
  b, w = marks({ 2, 2, 2, 2 }, { 2, 2, 5, 5 })
  check(b == 2 and w == 0, "repeated colours")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("mastermind needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("mastermind: " .. tostring(uiErr))
  return
end

local code, rows, typed, finished

local function newGame()
  code = {}
  for i = 1, SLOTS do code[i] = math.random(COLOURS) end
  rows, typed, finished = {}, {}, false
end

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "MASTERMIND", 0xe8ecf4)
  local y0 = 20
  for r = 1, TRIES do
    local y = y0 + (r - 1) * 10
    local row = rows[r]
    for s = 1, SLOTS do
      local x = 40 + (s - 1) * 14
      local colour = row and PALETTE[row.guess[s]] or 0x1c2233
      if not row and r == #rows + 1 and typed[s] then colour = PALETTE[typed[s]] end
      gfx.fill(x, y, 10, 8, colour)
    end
    if row then
      for p = 1, row.black do gfx.fill(120 + (p - 1) * 6, y + 2, 4, 4, 0xffffff) end
      for p = 1, row.white do gfx.fill(120 + (row.black + p - 1) * 6, y + 2, 4, 4, 0x505050) end
    end
  end
  local status
  if finished == "won" then status = "you cracked it!"
  elseif finished == "lost" then status = "the code was shown" 
  else status = "type 1-6, enter" end
  ui.label(160, 30, status, finished == "won" and 0x60ff90 or 0x8a94aa)
  if finished == "lost" then
    for s = 1, SLOTS do gfx.fill(160 + (s - 1) * 14, 44, 10, 10, PALETTE[code[s]]) end
  end
  ui.label(160, 70, "n new code", 0x8a94aa)
  ui.label(8, 124, "black = right place   white = wrong place", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("mastermind: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newGame()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "n" then newGame()
      elseif finished then
        -- the game is over: n starts another
      elseif k:match("^[1-6]$") and #typed < SLOTS then
        typed[#typed + 1] = tonumber(k)
      elseif k == "backspace" then
        typed[#typed] = nil
      elseif k == "enter" and #typed == SLOTS then
        local b, wh = marks(code, typed)
        rows[#rows + 1] = { guess = typed, black = b, white = wh }
        typed = {}
        if b == SLOTS then finished = "won"
        elseif #rows >= TRIES then finished = "lost" end
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("mastermind: " .. tostring(problem)) end
