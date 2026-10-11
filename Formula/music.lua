#!lua
-- music: plays the WAV and AIFF files of /home/user (or of the folder you give) one after another. Choose a file to play
-- from it to the end of the list, or "play all" to start from the first. While a file plays, Ctrl+C stops the music.
--   music [FOLDER]
-- Needs the speaker (firmware v0.1.0.6 or newer), the graphics and the ui package. Run it with --selftest to check the
-- file list.

local function isAudio(name)
  local ext = name:match("%.(%w+)$")
  if not ext then return false end
  ext = ext:lower()
  return ext == "wav" or ext == "aiff" or ext == "aif"
end

-- the audio files of a folder listing (folders and other files are left out), sorted without regard to case
local function audioFiles(listing)
  local files = {}
  for _, f in ipairs(listing) do
    if f:sub(-1) ~= "/" and isAudio(f) then files[#files + 1] = f end
  end
  table.sort(files, function(a, b) return a:lower() < b:lower() end)
  return files
end

local function seconds(s)
  s = math.floor(s)
  return string.format("%d:%02d", s // 60, s % 60)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(isAudio("a.wav") and isAudio("B.AIFF") and isAudio("c.aif") and not isAudio("d.mp3") and not isAudio("wav"), "audio file names")
  local files = audioFiles({ "z.wav", "notes.txt", "B.wav", "songs/", "a.aif" })
  check(#files == 3 and files[1] == "a.aif" and files[2] == "B.wav" and files[3] == "z.wav", "the audio files are found and sorted")
  check(seconds(75) == "1:15" and seconds(5.9) == "0:05", "the time")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("music needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not audio or not driver then
  print("music needs the audio of firmware v0.1.0.6 or newer")
  return
end
local ui, uiErr = driver.load("ui")
if not ui then
  print("music: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local dir = arg[1] or "/home/user"

-- plays files[from..#files], showing which one is playing. Returns false when the user stopped the music.
local function playFrom(files, from)
  for i = from, #files do
    local path = dir .. "/" .. files[i]
    gfx.clear(0x0a0c14)
    ui.panel(10, 30, W - 20, 70, "Now playing")
    ui.center(48, files[i]:sub(1, 34), 0xe8ecf4, 1)
    ui.center(64, string.format("%d of %d", i, #files), 0x8a94aa, 1)
    ui.center(84, "Ctrl+C stops", 0x8a94aa, 1)
    gfx.flush()
    local ok, stats, err = pcall(audio.play, path, 0)
    if not ok then
      if tostring(stats):find("interrupted", 1, true) then return false end
      error(stats, 0)
    end
    if not stats and err and tostring(err):find("interrupted", 1, true) then return false end
    if not stats then
      ui.message("Cannot play", { files[i]:sub(1, 30), tostring(err):sub(1, 30) })
    end
  end
  return true
end

local function main()
  while true do
    local files = audioFiles(fs.list(dir) or {})
    if #files == 0 then
      ui.message("No music", { "No WAV or AIFF files in", dir:sub(1, 30) })
      return
    end
    local items = { "play all" }
    for _, f in ipairs(files) do items[#items + 1] = f:sub(1, 34) end
    local c = ui.choose("Music", items)
    if not c then return end
    if not playFrom(files, c == 1 and 1 or c - 1) then return end
  end
end

local w, h = ui.open()
if not w then
  print("music: " .. tostring(h))
  return
end
local ok, problem = pcall(main)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("music: " .. tostring(problem)) end
