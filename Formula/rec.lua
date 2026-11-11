#!lua
-- rec: records from the board microphone, with SoX syntax. Same code as the sox package (only MODE differs).
--   rec [-r RATE] FILE|-n [trim 0 SECONDS] [stat]    records a WAV file, or -n only measures
-- Effects: trim 0 SECONDS (the length), stat (prints the levels). Ctrl+C stops a recording.
-- Mono 16-bit only: -c 1 and -b 16 are accepted.
-- A file is WAV or AIFF, 8 or 16 bit, mono or stereo. Ctrl+C stops a recording or a sound.


local MODE = "rec"  -- rec.lua and play.lua hold the same code with MODE = "rec" and "play"

if not audio then
  print(MODE .. ": this firmware has no audio support, update to v0.1.0.6(beta) or newer")
  return
end

local USAGE = {
  sox = "usage: sox [-r RATE] INPUT OUTPUT [EFFECT...]   (INPUT and OUTPUT: FILE, -n or -d)",
  rec = "usage: rec [-r RATE] FILE|-n [trim 0 SECONDS] [stat]",
  play = "usage: play FILE|-n [synth SECONDS sine|square|noise [FREQ]] [trim 0 SECONDS]",
}

local VERSION_LINE = (MODE .. ":"):format() .. string.rep(" ", 10 - #MODE - 1) .. "SoX v14.4.2"
local quiet = false

-- Errors are printed the way SoX prints them: "sox FAIL formats: can't open input file `x': ..."
local function fail(msg, where)
  if msg:sub(1, 5) == "usage" then
    print(VERSION_LINE .. "\n\n" .. msg)
  else
    print(MODE .. " FAIL " .. (where or MODE) .. ": " .. msg)
  end
  if os and os.exit then os.exit(2) end
end

local function clock(sec)
  local cs = math.floor(sec * 100 + 0.5)
  return string.format("%02d:%02d:%02d.%02d", cs // 360000, cs // 6000 % 60, cs // 100 % 60, cs % 100)
end

-- sox prints sizes as 441k, 1.23M
local function human(n)
  if n < 1000 then return string.format("%d", n) end
  local v, u = n / 1000, "k"
  if n >= 1000000 then v, u = n / 1000000, "M" end
  if v >= 100 then return string.format("%d%s", math.floor(v), u) end
  return string.format(v >= 10 and "%.1f%s" or "%.2f%s", v, u)
end

-- The "Input File" block of sox --info (and the one play prints before it starts)
local function info(path, st)
  local rate = st.seconds > 0 and math.floor(st.samples / st.seconds + 0.5) or 16000
  local size = 44 + st.samples * 2
  if fs.stat then
    local fi = fs.stat(path)
    if type(fi) == "table" and fi.size then size = fi.size end
  end
  print("")
  print(string.format("Input File     : '%s'", path))
  print("Channels       : 1")
  print(string.format("Sample Rate    : %d", rate))
  print("Precision      : 16-bit")
  print(string.format("Duration       : %s = %d samples ~ %d CDDA sectors", clock(st.seconds), st.samples, math.floor(st.seconds * 75 + 0.5)))
  print("File Size      : " .. human(size))
  print("Bit Rate       : " .. human(rate * 16))
  print("Sample Encoding: 16-bit Signed Integer PCM")
  print("")
end

-- The progress line sox leaves on the last row, then "Done."
local function finish(st)
  if quiet then return end
  print(string.format("In:100%%  %s [00:00:00.00] Out:%-5s [      |      ]        Clip:0    ", clock(st.seconds), human(st.samples)))
  print("Done.")
end

-- Splits the arguments into files and options, and the effects after the files
local function parse(args)
  local files, rate, effects = {}, nil, {}
  local infoOnly = false
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
    elseif a == "--version" then
      print(VERSION_LINE)
      if os and os.exit then os.exit(0) end
      return nil, nil
    elseif a == "-h" or a == "--help" then
      print(VERSION_LINE .. "\n\nUsage summary: [gopts] [[fopts] infile]... [fopts] outfile [effect [effopt]]...")
      if os and os.exit then os.exit(0) end
      return nil, nil
    elseif a == "--info" or a == "-i" then
      infoOnly = true
      i = i + 1
    elseif a == "-q" or a == "-S" or a == "-D" or a == "-G" or a == "--no-show-progress" or a == "--show-progress" or a:match("^%-V%d?$") then
      if a == "-q" or a == "--no-show-progress" then quiet = true end
      i = i + 1
    elseif a == "-r" then
      rate = tonumber(args[i + 1] or "")
      if not rate or rate < 8000 or rate > 48000 then return nil, "sox: invalid rate: -r takes a rate from 8000 to 48000" end
      i = i + 2
    elseif a == "-c" then
      if args[i + 1] ~= "1" then return nil, "only mono (-c 1) is supported on this device" end
      i = i + 2
    elseif a == "-b" then
      if args[i + 1] ~= "16" then return nil, "only 16 bit samples (-b 16) are supported on this device" end
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
  return { files = files, rate = rate, effects = effects, infoOnly = infoOnly }
end

-- Which file reads and which writes, from the files on the command line
local function plan(parsed)
  local files = parsed.files
  if parsed.infoOnly then return files[1] and files[1].kind == "file" and files[1] or nil, "info" end
  if MODE == "rec" then
    if #files ~= 1 or files[1].kind == "device" then return nil, USAGE.rec end
    return { kind = "device" }, files[1]
  elseif MODE == "play" then
    if #files ~= 1 or files[1].kind == "device" then return nil, USAGE.play end
    return files[1], { kind = "device" }
  end
  if #files < 2 then return nil, (#files == 0 and "Not enough input filenames specified" or "Not enough input filenames specified") end
  if #files > 2 then return nil, "can't mix more than one input file on this device" end
  return files[1], files[2]
end

-- The measurements, in the layout of sox's stat effect
local function show(s)
  local peak = s.peak
  print(string.format("Samples read:      %12d", s.samples))
  print(string.format("Length (seconds):  %12.6f", s.seconds))
  print(string.format("Scaled by:         %12.1f", 2147483647))
  print(string.format("Maximum amplitude: %12.6f", peak))
  print(string.format("Minimum amplitude: %12.6f", -peak))
  print(string.format("Midline amplitude: %12.6f", 0))
  print(string.format("RMS     amplitude: %12.6f", s.rms))
  if peak > 0 then print(string.format("Volume adjustment: %12.3f", 1 / peak)) end
end

-- A video plays on the screen, its sound on the speaker (the terminal is taken over while it plays)
local function playVideo(path)
  if not video then return fail("video needs firmware v0.1.0.10(beta) or newer", "formats") end
  local vinfo, ierr = video.info(path)
  if not vinfo then return fail(tostring(ierr), "formats") end
  term.fullscreen(true)
  local stats, perr = video.play(path)
  term.fullscreen(false)
  if not stats then return fail(tostring(perr), "formats") end
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

      result, err = audio.record("null", "", trimSeconds or 0, rate)
    end
  elseif input.kind == "file" then
    if output.kind == "file" then return fail("file to file is not supported, copy the file with cp") end
    if MODE == "play" and output.kind == "device" and input.path:lower():match("%.avi$") then
      return playVideo(input.path)
    end
    if output.kind == "device" then
      local st, serr = audio.stat(input.path)
      if not st then return fail("can't open input file `" .. input.path .. "': " .. tostring(serr), "formats") end
      if not quiet then info(input.path, st) end
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
  if not result then
    if input.kind == "file" then return fail("can't open input file `" .. input.path .. "': " .. tostring(err), "formats") end
    return fail(tostring(err), "formats")
  end
  if input.kind == "file" and output.kind ~= "device" then
    if not fx.stat then return end
  end
  if fx.stat then show(result) end
  if output.kind ~= "null" or input.kind ~= "file" then finish(result) end
end

if #arg == 0 then
  if MODE == "sox" then fail("Not enough input filenames specified", "sox") else fail("Not enough input filenames specified", MODE) end
  return
end
local parsed, perr = parse(arg)
if not parsed then
  if perr then fail(perr) end
  return
end
local input, output = plan(parsed)
if parsed.infoOnly then
  if not input then return fail("no input file given", "sox") end
  local st, serr = audio.stat(input.path)
  if not st then return fail("can't open input file `" .. input.path .. "': " .. tostring(serr), "formats") end
  return info(input.path, st)
end
if not input then return fail(output, "sox") end
run(input, output, parsed)
