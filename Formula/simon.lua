#!lua
-- simon: the memory game. Four pads (keys a s d f) light up with a tone in a sequence that grows by one pad each round.
-- Repeat the sequence with the same keys. A wrong pad ends the game (the other keys are ignored). enter starts a new
-- game, q quits.
-- The tones need the speaker (firmware v0.1.0.6 or newer); without it the pads only light up.

local PADS = {
  { key = "a", freq = 262, x = 2 },
  { key = "s", freq = 330, x = 11 },
  { key = "d", freq = 392, x = 20 },
  { key = "f", freq = 523, x = 29 },
}
local ROWS = select(2, term.size())
local PAD_Y = 5

local sequence = {}   -- the pad numbers, in the order they must be repeated
local pos = 0         -- how many of the sequence the player has repeated so far
local phase = "idle"  -- "idle", "show", "input" or "over"
local message = "press enter to start"

local function drawPad(i, lit)
  local p = PADS[i]
  term.text(p.x, PAD_Y, "+-----+", "text")
  term.text(p.x, PAD_Y + 1, "|" .. (lit and "#####" or "     ") .. "|", lit and "green" or "text")
  term.text(p.x, PAD_Y + 2, "|  " .. p.key:upper() .. "  |", lit and "green" or "dim")
  term.text(p.x, PAD_Y + 3, "+-----+", "text")
end

-- draws the screen; lit is the pad to light up (nil for none)
local function draw(lit)
  term.clear()
  term.text(0, 0, "simon   round " .. #sequence, "green")
  for i = 1, #PADS do drawPad(i, i == lit) end
  term.text(0, 10, message, phase == "over" and "red" or "text")
  term.text(0, ROWS - 2, "a s d f repeat the pads   enter new game", "dim")
  term.text(0, ROWS - 1, "q quit", "dim")
  term.flush()
end

local function tone(i, seconds)
  if audio then audio.synth("speaker", "", "sine", PADS[i].freq, seconds, 16000) end
end

-- plays the sequence: each pad lights up and sounds in turn
local function showSequence()
  phase = "show"
  message = "watch"
  draw(nil)
  sys.sleep(400)
  for _, i in ipairs(sequence) do
    draw(i)
    tone(i, 0.25)
    draw(nil)
    sys.sleep(120)
  end
  phase = "input"
  pos = 0
  message = "your turn"
  draw(nil)
end

local function nextRound()
  sequence[#sequence + 1] = math.random(#PADS)
  showSequence()
end

local function gameOver()
  phase = "over"
  message = string.format("wrong key. score %d. enter: play again", #sequence - 1)
  draw(nil)
end

-- returns false when the player quits
local function handle(k)
  if k == "q" then return false end
  if k == "enter" and (phase == "idle" or phase == "over") then
    sequence = {}
    nextRound()
    return true
  end
  if phase ~= "input" then return true end
  for i, p in ipairs(PADS) do
    if k == p.key then
      draw(i)
      tone(i, 0.15)
      pos = pos + 1
      if sequence[pos] ~= i then
        gameOver()
      elseif pos == #sequence then
        message = "good"
        phase = "show"
        draw(nil)
        sys.sleep(500)
        nextRound()
      else
        draw(nil)
      end
      return true
    end
  end
  return true
end

term.fullscreen(true)
draw(nil)
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if not handle(k) then
      quit = true
      break
    end
    k = key.poll()
  end
  if not quit then
    draw(nil)
    sys.sleep(30)
  end
end
term.fullscreen(false)
