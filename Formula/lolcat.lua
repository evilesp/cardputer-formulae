#!lua
-- lolcat: rainbow colored text, like lolcat 100 (the colors follow the same sine gradient).
-- usage: lolcat [OPTION]... [FILE]...    (a word that is not a file is printed as text)

local HELP = [[
Usage:
  lolcat [OPTION]... [FILE]...

Concatenate FILE(s), or standard input, to standard output.
With no FILE, or when FILE is -, read standard input.

Examples:
  lolcat f - g      Output f's contents, then standard input, then g's contents.
  lolcat            Copy standard input to standard output.
  fortune | lolcat  Display a rainbow cookie.

Report lolcat bugs to <http://www.github.com/busyloop/lolcat/issues>
lolcat home page: <http://www.github.com/busyloop/lolcat/>]]

local OPTS = [[

Options:
  -p, --spread=<f>       Rainbow spread (default: 3.0)
  -F, --freq=<f>         Rainbow frequency (default: 0.1)
  -S, --seed=<i>         Rainbow seed, 0 = random (default: 0)
  -a, --animate          Enable psychedelics
  -d, --duration=<i>     Animation duration (default: 12)
  -s, --speed=<f>        Animation speed (default: 20.0)
  -i, --invert           Invert fg and bg
  -t, --truecolor        24-bit (truecolor)
  -f, --force            Force color even when stdout is not a tty
  -v, --version          Print version and exit
  -h, --help             Show this message]]

local spread, freq, seed, animate, speed, invert = 3.0, 0.1, 0, false, 20.0, false
local files = {}

local function die(msg)
  io.stderr:write(msg .. "\n")
  os.exit(1)
end

local function num(name, v)
  local n = tonumber(v)
  if not n then die("Error: invalid argument for " .. name .. ": " .. tostring(v)) end
  return n
end

local LONG = { spread = "p", freq = "F", seed = "S", animate = "a", duration = "d", speed = "s",
               invert = "i", truecolor = "t", force = "f", version = "v", help = "h" }
local TAKES = { p = true, F = true, S = true, d = true, s = true }

local i = 1
local rest = false
while arg[i] do
  local a = arg[i]
  if rest or a == "-" or a:sub(1, 1) ~= "-" then
    files[#files + 1] = a
  elseif a == "--" then
    rest = true
  else
    local list = {}
    if a:sub(1, 2) == "--" then
      local name, val = a:match("^%-%-([%w]+)=?(.*)$")
      local o = LONG[name]
      if not o then die("Error: unknown option '" .. a .. "'\n" .. "Try 'lolcat --help' for more information") end
      list[1] = { o, val ~= "" and val or nil }
    else
      local j = 2
      while j <= #a do
        local o = a:sub(j, j)
        if TAKES[o] then
          local v = a:sub(j + 1)
          list[#list + 1] = { o, v ~= "" and v or nil }
          j = #a
        else
          list[#list + 1] = { o }
        end
        j = j + 1
      end
    end
    for _, it in ipairs(list) do
      local o, v = it[1], it[2]
      if TAKES[o] and not v then
        i = i + 1
        v = arg[i]
        if not v then die("Error: option '-" .. o .. "' needs a parameter") end
      end
      if o == "p" then spread = num("--spread", v)
      elseif o == "F" then freq = num("--freq", v)
      elseif o == "S" then seed = num("--seed", v)
      elseif o == "d" then num("--duration", v)
      elseif o == "s" then speed = num("--speed", v)
      elseif o == "a" then animate = true
      elseif o == "i" then invert = true
      elseif o == "h" then
        print(HELP .. OPTS)
        return
      elseif o == "v" then
        print("lolcat 100.0.1")
        return
      elseif o == "t" or o == "f" then
        -- the screen has a fixed palette: these only exist for compatibility
      else
        die("Error: unknown option '-" .. o .. "'\nTry 'lolcat --help' for more information")
      end
    end
  end
  i = i + 1
end
if spread < 0.1 then die("Error: Spread must be >= 0.1") end

-- the screen palette has six hues: pick the one nearest to the sine rainbow
local NAMES = { "red", "yellow", "green", "cyan", "blue", "magenta" }
local function colorAt(pos)
  local r = math.sin(freq * pos) * 127 + 128
  local g = math.sin(freq * pos + 2 * math.pi / 3) * 127 + 128
  local b = math.sin(freq * pos + 4 * math.pi / 3) * 127 + 128
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local h = 0
  if mx - mn > 1 then
    if mx == r then h = ((g - b) / (mx - mn)) % 6
    elseif mx == g then h = (b - r) / (mx - mn) + 2
    else h = (r - g) / (mx - mn) + 4 end
  end
  return NAMES[math.floor(h + 0.5) % 6 + 1]
end

if seed == 0 then seed = math.random(0, 255) end
local os_ = seed

local function paint(text)
  for line in (text .. (text:sub(-1) == "\n" and "" or "\n")):gmatch("(.-)\n") do
    local col = 0
    for ch in line:gmatch("[\0-\127\194-\244][\128-\191]*") do
      if ch == " " or ch == "\t" then
        term.write(ch == "\t" and "    " or ch, "text")
      else
        local c = colorAt(os_ + col / spread)
        if invert then c = "inverse-" .. c end
        term.write(ch, c)
      end
      col = col + 1
    end
    term.print("", "text")
    os_ = os_ + 1
    if animate and sys.sleep then sys.sleep(math.floor(1000 / speed)) end
  end
end

local function stdin()
  if sys.piped then paint(io.read("a") or "") end
end

if #files == 0 then
  stdin()
else
  for _, f in ipairs(files) do
    if f == "-" then
      stdin()
    elseif fs.exists(f) and not fs.isdir(f) then
      local data = fs.read(f)
      paint(data or "")
    elseif fs.isdir(f) then
      io.stderr:write("Error: " .. f .. ": Is a directory @ io_fread - " .. f .. "\n")
      os.exit(1)
    else
      paint(f)
    end
  end
end
