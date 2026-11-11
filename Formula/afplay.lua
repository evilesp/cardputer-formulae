#!lua
-- afplay: plays a WAV or AIFF file on the board speaker, like the afplay of macOS (silent on success).
--   afplay [-v VOLUME] [-t TIME] [--time TIME] FILE
--   -v VOLUME   0 to 1: a share of the current speaker volume (1 keeps it). The volume is put back afterwards.
--   -t, --time  plays only the first TIME seconds
-- The sound files of macOS (/System/Library/Sounds) are not on the board: copy a .wav or .aiff file to the SD card.
-- A file is 8 or 16 bit, mono or stereo. Ctrl+C stops the sound.

if not audio then
  print("afplay: this firmware has no audio support, update to v0.1.0.6(beta) or newer")
  return
end

local USAGE = [[Usage: afplay [options] audio_file

Options:
(-h | --help)                         Print help.
(-v | --volume) VOLUME                Set the volume for playback of the file. (0 to 1)
(-t | --time) TIME                    Play for TIME seconds.
(-r | --rate) RATE                    Playback rate: 0.5 is half speed, 2 is double speed.
(-q | --rQuality) QUALITY             Set the quality used for rate-scaled playback (default is 0 - low quality, 1 - high quality).
(-d | --debug)                        Debug print output.]]
local volume, seconds, path = nil, 0, nil

local function die(text, code)
  print(text)
  if os and os.exit then os.exit(code or 1) end
end

local i = 1
while i <= #arg do
  local a = arg[i]
  if a == "-v" or a == "--volume" then
    volume = tonumber(arg[i + 1] or "")
    if not volume or volume < 0 then return die(USAGE) end
    if volume > 1 then volume = 1 end
    i = i + 2
  elseif a == "-t" or a == "--time" then
    seconds = tonumber(arg[i + 1] or "")
    if not seconds or seconds <= 0 then return die(USAGE) end
    i = i + 2
  elseif a == "-h" or a == "--help" then
    return die(USAGE, 0)
  elseif a == "-r" or a == "--rate" or a == "-q" or a == "--rQuality" then
    i = i + 2
  elseif a == "-d" or a == "--debug" then
    i = i + 1
  elseif a:sub(1, 1) == "-" then
    return die("Unknown option: " .. a .. "\n" .. USAGE)
  else
    path = a
    i = i + 1
  end
end
if not path then return die(USAGE) end

local saved = audio.volume()
if volume then audio.volume(math.floor(saved * volume + 0.5)) end
local stats, err = audio.play(path, seconds)
if volume then audio.volume(saved) end
if not stats then
  -- afplay prints a four-letter AudioToolbox code in quotes, not the errno text
  if tostring(err):find("No such file", 1, true) then
    print("Error: AudioFileOpen failed ('wht?')")
  else
    print("Error: AudioFileOpen failed ('typ?')")
  end
  if os and os.exit then os.exit(1) end
end
