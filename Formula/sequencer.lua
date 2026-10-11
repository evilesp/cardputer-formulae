#!lua
-- sequencer: a drum machine with 8 tracks of 16 steps. Move with w a s d, enter switches a step on or off, space plays and
-- stops, b and n change the tempo, x clears the pattern, p saves the pattern to /home/user/beat.txt and l loads it, ctrl-q
-- quits. The drums are short tones from the speaker (audio.beep, firmware v0.1.0.18). Run it with --selftest to check the
-- pattern file and the timing.

local W, H = 240, 135
local TRACKS = 8
local STEPS = 16
local FILE = "/home/user/beat.txt"
local NAMES = { "kick", "snare", "hat", "clap", "tom", "rim", "cow", "bell" }
local SOUNDS = { { 60, 90 }, { 180, 70 }, { 4000, 25 }, { 1200, 40 }, { 110, 120 }, { 800, 20 }, { 540, 50 }, { 1320, 120 } }

-- the pattern as text: a tempo line, then one line of 0 and 1 for each track
local function encode(pattern, bpm)
  local lines = { "bpm " .. bpm }
  for t = 1, TRACKS do
    local row = {}
    for s = 1, STEPS do row[s] = pattern[t][s] and "1" or "0" end
    lines[#lines + 1] = table.concat(row)
  end
  return table.concat(lines, "\n") .. "\n"
end

-- the pattern and tempo from that text; nil when it is not a pattern
local function decode(text)
  local bpm = tonumber(text:match("^bpm (%d+)"))
  if not bpm or bpm < 40 or bpm > 240 then return nil end
  local pattern, t = {}, 0
  for line in text:gmatch("[^\n]+") do
    if line:match("^[01]+$") and #line == STEPS and t < TRACKS then
      t = t + 1
      pattern[t] = {}
      for s = 1, STEPS do pattern[t][s] = line:sub(s, s) == "1" end
    end
  end
  if t ~= TRACKS then return nil end
  return pattern, bpm
end

-- the time of one step in milliseconds (4 steps a beat)
local function stepMs(bpm)
  return 60000 / bpm / 4
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local p = {}
  for t = 1, TRACKS do
    p[t] = {}
    for s = 1, STEPS do p[t][s] = (t + s) % 3 == 0 end
  end
  local text = encode(p, 120)
  local back, bpm = decode(text)
  check(back ~= nil and bpm == 120, "a pattern comes back with its tempo")
  local same = true
  for t = 1, TRACKS do
    for s = 1, STEPS do same = same and (back[t][s] == p[t][s]) end
  end
  check(same, "every step comes back the same")
  check(decode("bpm 500\n" .. text:match("\n(.*)")) == nil, "a tempo out of range is refused")
  check(decode("bpm 120\n0101\n") == nil, "a short pattern is refused")
  check(decode("hello") == nil, "not a pattern at all")
  check(stepMs(120) == 125 and stepMs(60) == 250, "a step is a quarter of a beat")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("sequencer needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not audio or not audio.beep then
  print("sequencer needs firmware v0.1.0.18(beta) or newer: SystemBackUpdate")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("sequencer: " .. tostring(uiErr))
  return
end

local pattern = {}
for t = 1, TRACKS do
  pattern[t] = {}
  for s = 1, STEPS do pattern[t][s] = false end
end
local bpm = 110
local cursorT, cursorS = 1, 1
local playing, playStep, nextAt = false, 1, 0
local message = ""
local BOTTOM_Y = 122  -- the line of help at the bottom

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(4, 2, "SEQUENCER", 0xe8ecf4)
  ui.label(120, 2, string.format("%d bpm  %s", bpm, playing and "playing" or "stopped"), playing and 0x60ff90 or 0x8a94aa)
  local cellW, cellH = 12, 10
  local x0, y0 = 50, 16
  for t = 1, TRACKS do
    local y = y0 + (t - 1) * (cellH + 2)
    ui.label(4, y + 1, NAMES[t], 0x8a94aa)
    for s = 1, STEPS do
      local x = x0 + (s - 1) * (cellW + 1)
      local on = pattern[t][s]
      local playHere = playing and playStep == s
      local colour = on and (s % 4 == 1 and 0xf0a040 or 0x40c0ff) or 0x1c2233
      if playHere then colour = 0xffffff end
      gfx.fill(x, y, cellW, cellH, colour)
      if t == cursorT and s == cursorS then gfx.rect(x - 1, y - 1, cellW + 2, cellH + 2, 0xffe060) end
    end
  end
  ui.label(4, BOTTOM_Y, message ~= "" and message or "enter step  space play  b/n tempo  p save  l load  ctrl-q", 0x8a94aa)
  gfx.flush()
end

local function play(t, s)
  if pattern[t][s] then
    local sound = SOUNDS[t]
    pcall(audio.beep, sound[1], sound[2])
  end
end

local function tick(now)
  if not playing or now < nextAt then return end
  for t = 1, TRACKS do play(t, playStep) end
  playStep = playStep % STEPS + 1
  nextAt = now + stepMs(bpm)
end

local function save()
  local ok, err = fs.write(FILE, encode(pattern, bpm))
  message = ok and ("saved " .. FILE) or ("cannot save: " .. tostring(err))
end

local function load()
  local text = fs.read(FILE)
  if not text then
    message = "no saved beat yet (p saves one)"
    return
  end
  local p, b = decode(text)
  if not p then
    message = FILE .. " is not a beat"
    return
  end
  pattern, bpm = p, b
  message = "loaded " .. FILE
end

local w, h = ui.open()
if not w then
  print("sequencer: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    local now = sys.millis()
    tick(now)
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "w" then cursorT = math.max(1, cursorT - 1)
      elseif k == "s" then cursorT = math.min(TRACKS, cursorT + 1)
      elseif k == "a" then cursorS = math.max(1, cursorS - 1)
      elseif k == "d" then cursorS = math.min(STEPS, cursorS + 1)
      elseif k == "enter" then pattern[cursorT][cursorS] = not pattern[cursorT][cursorS]
      elseif k == " " then
        playing = not playing
        playStep, nextAt = 1, 0
      elseif k == "b" then bpm = math.max(40, bpm - 5)
      elseif k == "n" then bpm = math.min(240, bpm + 5)
      elseif k == "x" then
        for t = 1, TRACKS do
          for s = 1, STEPS do pattern[t][s] = false end
        end
      elseif k == "p" then save()
      elseif k == "l" then load()
      end
      k = key.poll()
    end
    draw()
    sys.sleep(15)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("sequencer: " .. tostring(problem)) end
