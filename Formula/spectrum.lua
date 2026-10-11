#!lua
-- spectrum: the sound from the microphone as 16 bars, from the low notes on the left to the high ones on the right. The
-- peaks stay for a moment. p turns the peak marks off and on, ctrl-q quits. Needs the graphics, the ui package and
-- firmware v0.1.0.18(beta) (audio.listen). Run it with --selftest to check the band layout.

local W, H = 240, 135
local BANDS = 16
local BASE, TOP = 40, 124  -- the bars start at the bottom (y 124) and reach up to y 40 at the loudest

-- the frequency of a band's centre on the same log scale as the firmware (80 Hz to 6000 Hz)
local function bandHz(b)
  return 80 * (6000 / 80) ^ ((b - 1) / (BANDS - 1))
end

-- the height in pixels of a level (0 to 255)
local function barHeight(level)
  return math.floor((TOP - BASE) * math.min(255, math.max(0, level)) / 255 + 0.5)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(math.abs(bandHz(1) - 80) < 0.01 and math.abs(bandHz(BANDS) - 6000) < 0.5, "the first band is 80 Hz, the last 6000 Hz")
  check(bandHz(2) > bandHz(1) and bandHz(BANDS) > bandHz(BANDS - 1), "the bands go up")
  check(barHeight(0) == 0 and barHeight(255) == TOP - BASE and barHeight(128) > 0, "the bar heights")
  check(barHeight(999) == TOP - BASE, "a level above the top is the top")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("spectrum needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not audio or not audio.listen then
  print("spectrum needs firmware v0.1.0.18(beta) or newer: SystemBackUpdate")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("spectrum: " .. tostring(uiErr))
  return
end

local peaks = {}
for b = 1, BANDS do peaks[b] = 0 end
local showPeaks = true

local NOTES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local function noteName(hz)
  local midi = math.floor(69 + 12 * math.log(hz / 440, 2) + 0.5)
  return NOTES[midi % 12 + 1] .. tostring(midi // 12 - 1)
end

local w, h = ui.open()
if not w then
  print("spectrum: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "p" then showPeaks = not showPeaks end
      k = key.poll()
    end
    local r = audio.listen()
    gfx.clear(0x0a0c14)
    local bw = W // BANDS
    for b = 1, BANDS do
      local level = r.bands[b]
      local hgt = barHeight(level)
      if level > peaks[b] then peaks[b] = level else peaks[b] = math.max(0, peaks[b] - 6) end
      local x = (b - 1) * bw + 2
      local colour = level > 200 and 0xff5050 or (level > 130 and 0xf0c040 or 0x40c0ff)
      gfx.fill(x, TOP - hgt, bw - 4, hgt, colour)
      if showPeaks and peaks[b] > 0 then gfx.fill(x, TOP - barHeight(peaks[b]), bw - 4, 2, 0xffffff) end
    end
    gfx.hline(0, W - 1, TOP, 0x3a4260)
    local level = r.level or 0
    local pitch = r.pitch and (string.format("%.0f Hz  %s", r.pitch, noteName(r.pitch))) or "no clear note"
    ui.label(4, 4, "level " .. level .. "   " .. pitch, 0xe8ecf4)
    ui.label(4, H - 10, "80 Hz" , 0x8a94aa)
    ui.label(W - 60, H - 10, "6 kHz", 0x8a94aa)
    ui.label(W // 2 - 30, H - 10, "p peaks  ctrl-q quit", 0x8a94aa)
    gfx.flush()
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("spectrum: " .. tostring(problem)) end
