#!lua
-- tuner: tune an instrument. It listens to the microphone and shows the note nearest to the sound and how far off it is in
-- cents (100 cents is a half step): the needle in the middle means in tune. The reading is the average of the last four
-- sounds. ctrl-q quits. Needs the graphics, the ui package and firmware v0.1.0.18(beta) (audio.listen). Run it with
-- --selftest to check the notes.

local NOTES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

-- the note nearest to a frequency: its name, its octave and how far off it is in cents (+ is sharp)
local function noteOf(hz)
  local midi = 69 + 12 * math.log(hz / 440, 2)
  local nearest = math.floor(midi + 0.5)
  local cents = (midi - nearest) * 100
  return NOTES[nearest % 12 + 1], nearest // 12 - 1, cents
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local name, octave, cents = noteOf(440)
  check(name == "A" and octave == 4 and math.abs(cents) < 0.01, "440 Hz is A4, in tune")
  name, octave, cents = noteOf(261.63)
  check(name == "C" and octave == 4 and math.abs(cents) < 1, "middle C")
  name, octave, cents = noteOf(450)
  check(name == "A" and math.abs(cents - 39.2) < 0.5, "450 Hz is A4 about 39 cents sharp")
  name, octave, cents = noteOf(110)
  check(name == "A" and octave == 2, "110 Hz is A2")
  name, octave, cents = noteOf(329.63)
  check(name == "E" and octave == 4, "E4")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("tuner needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not audio or not audio.listen then
  print("tuner needs firmware v0.1.0.18(beta) or newer: SystemBackUpdate")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("tuner: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local recent = {}

local function draw(hz)
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "TUNER", 0xe8ecf4)
  if not hz then
    ui.center(50, "play a note", 0x8a94aa, 2)
  else
    local name, octave, cents = noteOf(hz)
    ui.center(20, name .. octave, 0xffe060, 5)
    ui.center(64, string.format("%.1f Hz", hz), 0x8a94aa, 1)
    -- the gauge: -50 to +50 cents across the screen
    local cx = W // 2
    gfx.hline(20, W - 20, 96, 0x3a4260)
    gfx.vline(cx, 88, 104, 0x60ff90)
    local x = cx + math.floor(math.max(-50, math.min(50, cents)) / 50 * (W / 2 - 24))
    local colour = math.abs(cents) < 5 and 0x60ff90 or (math.abs(cents) < 20 and 0xf0d040 or 0xff6060)
    gfx.fill(x - 2, 84, 5, 18, colour)
    ui.label(8, 108, string.format("%+.0f cents", cents), colour)
  end
  ui.label(8, H - 10, "ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("tuner: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    local k = key.poll()
    if k == "ctrl-q" then return end
    local r = audio.listen()
    if r.pitch then
      recent[#recent + 1] = r.pitch
      if #recent > 4 then table.remove(recent, 1) end
    else
      recent = {}
    end
    local hz = nil
    if #recent > 0 then
      local sum = 0
      for _, v in ipairs(recent) do sum = sum + v end
      hz = sum / #recent
    end
    draw(hz)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("tuner: " .. tostring(problem)) end
