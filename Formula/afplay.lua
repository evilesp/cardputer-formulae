#!lua
-- afplay: plays a WAV or AIFF file on the Cardputer speaker, like the afplay of macOS.
--   afplay [-v VOLUME] [--time SECONDS] FILE
--   -v VOLUME   0 to 1: a share of the current speaker volume (1 keeps it). The volume is put back afterwards.
--   --time      plays only the first SECONDS
-- The sound files of macOS (/System/Library/Sounds) are not on the Cardputer: copy a .wav or .aiff file to the SD card.
-- A file is 8 or 16 bit, mono or stereo. Ctrl+C stops the sound.

if not audio then
  print("afplay: this firmware has no audio support, update to v0.1.0.6(beta) or newer")
  return
end

local USAGE = "usage: afplay [-v VOLUME] [--time SECONDS] FILE"
local volume, seconds, path = nil, 0, nil

local i = 1
while i <= #arg do
  local a = arg[i]
  if a == "-v" then
    volume = tonumber(arg[i + 1] or "")
    if not volume or volume < 0 or volume > 1 then
      print("afplay: -v takes a value from 0 to 1")
      return
    end
    i = i + 2
  elseif a == "--time" then
    seconds = tonumber(arg[i + 1] or "")
    if not seconds or seconds <= 0 then
      print("afplay: --time takes a number of seconds")
      return
    end
    i = i + 2
  elseif a:sub(1, 1) == "-" then
    print(USAGE)
    return
  else
    path = a
    i = i + 1
  end
end
if not path then
  print(USAGE)
  return
end

local saved = audio.volume()
if volume then audio.volume(math.floor(saved * volume + 0.5)) end
local stats, err = audio.play(path, seconds)
if volume then audio.volume(saved) end
if not stats then
  print("afplay: " .. path .. ": " .. tostring(err))
end
