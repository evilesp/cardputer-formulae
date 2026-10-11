#!lua
-- piano: the keyboard is a piano. The home row is the white keys (a s d f g h j k l: C D E F G A B C D) and the row above
-- is the black keys (w e t y u o: C# D# F# G# A# C#). Press a key to play a note; a note lasts a third of a second. z and x
-- go down and up an octave, ctrl-q quits. Needs the speaker (firmware v0.1.0.6 or newer), the graphics and the ui
-- package. Run it with --selftest to check the notes.

local KEYS = {
  { key = "a", semi = 0, white = true }, { key = "s", semi = 2, white = true }, { key = "d", semi = 4, white = true },
  { key = "f", semi = 5, white = true }, { key = "g", semi = 7, white = true }, { key = "h", semi = 9, white = true },
  { key = "j", semi = 11, white = true }, { key = "k", semi = 12, white = true }, { key = "l", semi = 14, white = true },
  { key = "w", semi = 1, white = false, after = 1 }, { key = "e", semi = 3, white = false, after = 2 },
  { key = "t", semi = 6, white = false, after = 4 }, { key = "y", semi = 8, white = false, after = 5 },
  { key = "u", semi = 10, white = false, after = 6 }, { key = "o", semi = 13, white = false, after = 8 },
}
local NAMES = { [0] = "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

-- the frequency in hertz of the note `semi` semitones above C of the given octave (C4 is middle C, 261.63 Hz)
local function frequency(semi, octave)
  local fromA4 = semi - 9 + (octave - 4) * 12
  return 440 * 2 ^ (fromA4 / 12)
end

local function noteName(semi, octave)
  return NAMES[semi % 12] .. (octave + semi // 12)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(math.abs(frequency(9, 4) - 440) < 1e-9, "A4 is 440 Hz")
  check(math.abs(frequency(0, 4) - 261.6256) < 0.001, "middle C is 261.63 Hz")
  check(math.abs(frequency(0, 5) - 2 * frequency(0, 4)) < 1e-9, "an octave up doubles the frequency")
  check(noteName(0, 4) == "C4" and noteName(11, 4) == "B4" and noteName(12, 4) == "C5" and noteName(14, 4) == "D5", "note names")
  check(noteName(1, 3) == "C#3", "a sharp has its sign")
  local seen = {}
  for _, k in ipairs(KEYS) do seen[k.key] = (seen[k.key] or 0) + 1 end
  local twice = false
  for _, n in pairs(seen) do
    if n > 1 then twice = true end
  end
  check(not twice and #KEYS == 15, "15 different keys")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("piano needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not audio or not driver then
  print("piano needs the audio of firmware v0.1.0.6 or newer")
  return
end
local ui, uiErr = driver.load("ui")
if not ui then
  print("piano: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local octave = 4
local pressed, pressedUntil, lastNote = nil, 0, ""
local KEY_W, KEY_H, OX, OY = 24, 70, 12, 40

local function draw(now)
  gfx.clear(0x0a0c14)
  ui.center(8, "PIANO", 0xe8ecf4, 2)
  ui.center(28, lastNote ~= "" and lastNote or "play a note", 0xffe060, 1)
  for i, k in ipairs(KEYS) do
    if k.white then
      local x = OX + (i - 1) * KEY_W
      local on = pressed == k.key and now < pressedUntil
      gfx.fill(x, OY, KEY_W - 1, KEY_H, on and 0x60c8ff or 0xf0f0f0)
      ui.label(x + 9, OY + KEY_H - 12, k.key, 0x303030)
    end
  end
  for _, k in ipairs(KEYS) do
    if not k.white then
      local x = OX + k.after * KEY_W - 7
      local on = pressed == k.key and now < pressedUntil
      gfx.fill(x, OY, 14, 42, on and 0x3a7ac8 or 0x181818)
      ui.label(x + 4, OY + 30, k.key, 0xd0d0d0)
    end
  end
  ui.label(4, H - 12, "octave " .. octave .. "   z down  x up   ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local function play(k, now)
  local hz = frequency(k.semi, octave)
  pressed, pressedUntil = k.key, now + 250
  lastNote = noteName(k.semi, octave) .. string.format("  %.1f Hz", hz)
  audio.synth("speaker", "", "sine", hz, 0.33, 16000)
end

local function handle(key, now)
  if key == "ctrl-q" then return false end
  if #key == 1 then key = key:lower() end
  if key == "z" then octave = math.max(1, octave - 1)
  elseif key == "x" then octave = math.min(7, octave + 1)
  else
    for _, k in ipairs(KEYS) do
      if k.key == key then
        play(k, now)
        break
      end
    end
  end
  return true
end

local w, h = ui.open()
if not w then
  print("piano: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    local now = sys.millis()
    local k = key.poll()
    while k do
      if not handle(k, now) then return end
      k = key.poll()
    end
    draw(sys.millis())
    sys.sleep(20)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("piano: " .. tostring(problem)) end
