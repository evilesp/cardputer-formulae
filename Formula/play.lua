#!lua
-- play: plays a WAV or AIFF file on the Cardputer speaker, or a tone, with SoX syntax. Same code as the sox package.
--   play FILE|-n [synth SECONDS sine|square|noise [FREQ]] [trim 0 SECONDS]
-- Effects: trim 0 SECONDS (plays only that long), stat (prints the levels), synth (a tone instead of a file).
-- Ctrl+C stops the sound. Mono 16-bit only: -c 1 and -b 16 are accepted.
-- A file is WAV or AIFF, 8 or 16 bit, mono or stereo. Ctrl+C stops a recording or a sound.

local MODE = "play"  -- rec.lua and play.lua hold the same code with MODE = "rec" and "play"

if not audio then
  print(MODE .. ": this firmware has no audio support, update to v0.1.0.6(beta) or newer")
  return
end

local USAGE = {
  sox = "usage: sox [-r RATE] INPUT OUTPUT [EFFECT...]   (INPUT and OUTPUT: FILE, -n or -d)",
  rec = "usage: rec [-r RATE] FILE|-n [trim 0 SECONDS] [stat]",
  play = "usage: play FILE|-n [synth SECONDS sine|square|noise [FREQ]] [trim 0 SECONDS]",
}

local function fail(msg)
  if msg:sub(1, 5) == "usage" then print(msg) else print(MODE .. ": " .. msg) end
end

-- Splits the arguments into files and options, and the effects after the files
local function parse(args)
  local files, rate, effects = {}, nil, {}
  local i = 1
  while i <= #args do
    local a = args[i]
    if (a == "trim" or a == "stat" or a == "synth") and #files >= 1 then
      while i <= #args do
        local name = args[i]
        if name == "trim" then
          effects.trim = { start = tonumber(args[i + 1] or ""), length = tonumber(args[i + 2] or "") }
          i = i + 3
        elseif name == "stat" then
          effects.stat = true
          i = i + 1
        elseif name == "synth" then
          local wave = args[i + 2]
          if wave == "noise" then
            effects.synth = { seconds = tonumber(args[i + 1] or ""), wave = wave, freq = 0 }
            i = i + 3
          else
            effects.synth = { seconds = tonumber(args[i + 1] or ""), wave = wave, freq = tonumber(args[i + 3] or "") }
            i = i + 4
          end
        else
          return nil, "unknown effect: " .. tostring(name)
        end
      end
      break
    elseif a == "-r" then
      rate = tonumber(args[i + 1] or "")
      if not rate or rate < 8000 or rate > 48000 then return nil, "-r takes a rate from 8000 to 48000" end
      i = i + 2
    elseif a == "-c" then
      if args[i + 1] ~= "1" then return nil, "only mono (-c 1) is supported" end
      i = i + 2
    elseif a == "-b" then
      if args[i + 1] ~= "16" then return nil, "only 16 bit samples (-b 16) are supported" end
      i = i + 2
    elseif a == "-n" then
      files[#files + 1] = { kind = "null" }
      i = i + 1
    elseif a == "-d" then
      files[#files + 1] = { kind = "device" }
      i = i + 1
    elseif a:sub(1, 1) == "-" then
      return nil, "unknown option " .. a
    else
      files[#files + 1] = { kind = "file", path = a }
      i = i + 1
    end
  end
  return { files = files, rate = rate, effects = effects }
end

-- Which file reads and which writes, from the files on the command line
local function plan(parsed)
  local files = parsed.files
  if MODE == "rec" then
    if #files ~= 1 or files[1].kind == "device" then return nil, USAGE.rec end
    return { kind = "device" }, files[1]
  elseif MODE == "play" then
    if #files ~= 1 or files[1].kind == "device" then return nil, USAGE.play end
    return files[1], { kind = "device" }
  end
  if #files ~= 2 then return nil, USAGE.sox end
  return files[1], files[2]
end

-- The measurements, in the layout of sox's stat effect
local function show(s)
  print(string.format("Samples read:      %d", s.samples))
  print(string.format("Length (seconds):  %.3f", s.seconds))
  print(string.format("Maximum amplitude: %.6f", s.peak))
  print(string.format("RMS     amplitude: %.6f", s.rms))
end

local function run(input, output, parsed)
  local fx = parsed.effects
  local rate = parsed.rate or 16000
  local trimSeconds = nil
  if fx.trim then
    if fx.trim.start ~= 0 or not fx.trim.length or fx.trim.length <= 0 then
      return fail("trim takes 0 and a length in seconds, like trim 0 5")
    end
    trimSeconds = fx.trim.length
  end

  local result, err
  if input.kind == "device" then
    if output.kind == "device" then
      return fail("the microphone cannot play directly: record to a file, then play that file")
    end
    if output.kind == "file" then
      if not trimSeconds then return fail("a file needs a length, like trim 0 5") end
      result, err = audio.record("file", output.path, trimSeconds, rate)
    else
      if not trimSeconds then print(MODE .. ": recording until Ctrl+C") end
      result, err = audio.record("null", "", trimSeconds or 0, rate)
    end
  elseif input.kind == "file" then
    if output.kind == "file" then return fail("file to file is not supported, copy the file with cp") end
    if output.kind == "device" then
      result, err = audio.play(input.path, trimSeconds or 0)
    else
      result, err = audio.stat(input.path)
    end
  else  -- nothing to read: a tone
    local syn = fx.synth
    if not syn then return fail("nothing to read: give a FILE or -d, or add synth SECONDS sine FREQ") end
    if not syn.seconds or syn.seconds <= 0 then return fail("synth needs a length in seconds, like synth 1 sine 440") end
    if syn.wave ~= "sine" and syn.wave ~= "square" and syn.wave ~= "noise" then
      return fail("synth wave must be sine, square or noise")
    end
    if syn.wave ~= "noise" and (not syn.freq or syn.freq <= 0) then
      return fail("synth needs a frequency, like synth 1 sine 440")
    end
    local length = syn.seconds
    if trimSeconds and trimSeconds < length then length = trimSeconds end
    local where = "null"
    if output.kind == "device" then where = "speaker" elseif output.kind == "file" then where = "file" end
    result, err = audio.synth(where, output.path or "", syn.wave, syn.freq, length, rate)
  end
  if not result then return fail(tostring(err)) end
  if fx.stat then show(result) end
end

if #arg == 0 then
  print(USAGE[MODE])
  return
end
local parsed, perr = parse(arg)
if not parsed then return fail(perr) end
local input, output = plan(parsed)
if not input then return fail(output) end
run(input, output, parsed)
