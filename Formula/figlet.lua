#!lua
-- figlet: large letters from the "standard" font with smushing, like FIGlet 2.2.5.
-- usage: figlet [ -cklrvIS ] [ -f font ] [ -w outputwidth ] [ message ]

local W = {}
local FLF = [==[
 $@
 $@
 $@
 $@
 $@
 $@@
 _ @
| |@
| |@
|_|@
(_)@
   @@
 _ _ @
( | )@
 V V @
     @
     @
     @@
   _  _   @
 _| || |_ @
|_  ..  _|@
|_      _|@
  |_||_|  @
          @@
  _  @
 | | @
/ __)@
\__ \@
(   /@
 |_| @@
 _   __@
(_) / /@
   / / @
  / /_ @
 /_/(_)@
       @@
  ___   @
 ( _ )  @
 / _ \/\@
| (_>  <@
 \___/\/@
        @@
 _ @
( )@
|/ @
   @
   @
   @@
  __@
 / /@
| | @
| | @
| | @
 \_\@@
__  @
\ \ @
 | |@
 | |@
 | |@
/_/ @@
     @
__/\__@
\    /@
/_  _\@
  \/  @
      @@
       @
  _    @
_| |_  @
|_   _|@
  |_|  @
       @@
   @
   @
   @
 _ @
( )@
|/ @@
       @
       @
 _____ @
|_____|@
       @
       @@
   @
   @
   @
 _ @
(_)@
   @@
    __@
   / /@
  / / @
 / /  @
/_/   @
      @@
  ___  @
 / _ \ @
| | | |@
| |_| |@
 \___/ @
       @@
 _ @
/ |@
| |@
| |@
|_|@
   @@
 ____  @
|___ \ @
  __) |@
 / __/ @
|_____|@
       @@
 _____ @
|___ / @
  |_ \ @
 ___) |@
|____/ @
       @@
 _  _   @
| || |  @
| || |_ @
|__   _|@
   |_|  @
        @@
 ____  @
| ___| @
|___ \ @
 ___) |@
|____/ @
       @@
  __   @
 / /_  @
| '_ \ @
| (_) |@
 \___/ @
       @@
 _____ @
|___  |@
   / / @
  / /  @
 /_/   @
       @@
  ___  @
 ( _ ) @
 / _ \ @
| (_) |@
 \___/ @
       @@
  ___  @
 / _ \ @
| (_) |@
 \__, |@
   /_/ @
       @@
 _ @
(_)@
   @
 _ @
(_)@
   @@
 _ @
(_)@
   @
 _ @
( )@
|/ @@
  __@
 / /@
/ / @
\ \ @
 \_\@
    @@
       @
 _____ @
|_____|@
|_____|@
       @
       @@
__  @
\ \ @
 \ \@
 / /@
/_/ @
    @@
 ___ @
|__ \@
  / /@
 |_| @
 (_) @
     @@
  ____  @
 / __ \ @
/ / _` |@
| | (_| |@
\ \__,_|@
 \____/ @@
    _    @
   / \   @
  / _ \  @
 / ___ \ @
/_/   \_\@
         @@
 ____  @
| __ ) @
|  _ \ @
| |_) |@
|____/ @
       @@
  ____ @
 / ___|@
| |    @
| |___ @
 \____|@
       @@
 ____  @
|  _ \ @
| | | |@
| |_| |@
|____/ @
       @@
 _____ @
| ____|@
|  _|  @
| |___ @
|_____|@
       @@
 _____ @
|  ___|@
| |_   @
|  _|  @
|_|    @
       @@
  ____ @
 / ___|@
| |  _ @
| |_| |@
 \____|@
       @@
 _   _ @
| | | |@
| |_| |@
|  _  |@
|_| |_|@
       @@
 ___ @
|_ _|@
 | | @
 | | @
|___|@
     @@
     _ @
    | |@
 _  | |@
| |_| |@
 \___/ @
       @@
 _  __@
| |/ /@
| ' / @
| . \ @
|_|\_\@
      @@
 _     @
| |    @
| |    @
| |___ @
|_____|@
       @@
 __  __ @
|  \/  |@
| |\/| |@
| |  | |@
|_|  |_|@
        @@
 _   _ @
| \ | |@
|  \| |@
| |\  |@
|_| \_|@
       @@
  ___  @
 / _ \ @
| | | |@
| |_| |@
 \___/ @
       @@
 ____  @
|  _ \ @
| |_) |@
|  __/ @
|_|    @
       @@
  ___  @
 / _ \ @
| | | |@
| |_| |@
 \__\_\@
       @@
 ____  @
|  _ \ @
| |_) |@
|  _ < @
|_| \_\@
       @@
 ____  @
/ ___| @
\___ \ @
 ___) |@
|____/ @
       @@
 _____ @
|_   _|@
  | |  @
  | |  @
  |_|  @
       @@
 _   _ @
| | | |@
| | | |@
| |_| |@
 \___/ @
       @@
__     __@
\ \   / /@
 \ \ / / @
  \ V /  @
   \_/   @
         @@
__        __@
\ \      / /@
 \ \ /\ / / @
  \ V  V /  @
   \_/\_/   @
            @@
__  __@
\ \/ /@
 \  / @
 /  \ @
/_/\_\@
      @@
__   __@
\ \ / /@
 \ V / @
  | |  @
  |_|  @
       @@
 _____@
|__  /@
  / / @
 / /_ @
/____|@
      @@
 __ @
| _|@
| | @
| | @
| | @
|__|@@
__    @
\ \   @
 \ \  @
  \ \ @
   \_\@
      @@
 __ @
|_ |@
 | |@
 | |@
 | |@
|__|@@
 /\ @
|/\|@
    @
    @
    @
    @@
       @
       @
       @
       @
 _____ @
|_____|@@
 _ @
( )@
 \|@
   @
   @
   @@
       @
  __ _ @
 / _` |@
| (_| |@
 \__,_|@
       @@
 _     @
| |__  @
| '_ \ @
| |_) |@
|_.__/ @
       @@
      @
  ___ @
 / __|@
| (__ @
 \___|@
      @@
     _ @
  __| |@
 / _` |@
| (_| |@
 \__,_|@
       @@
       @
  ___  @
 / _ \ @
|  __/ @
 \___| @
       @@
  __ @
 / _|@
| |_ @
|  _|@
|_|  @
     @@
       @
  __ _ @
 / _` |@
| (_| |@
 \__, |@
 |___/ @@
 _     @
| |__  @
| '_ \ @
| | | |@
|_| |_|@
       @@
 _ @
(_)@
| |@
| |@
|_|@
   @@
   _ @
  (_)@
  | |@
  | |@
 _/ |@
|__/ @@
 _    @
| | __@
| |/ /@
|   < @
|_|\_\@
      @@
 _ @
| |@
| |@
| |@
|_|@
   @@
           @
 _ __ ___  @
| '_ ` _ \ @
| | | | | |@
|_| |_| |_|@
           @@
       @
 _ __  @
| '_ \ @
| | | |@
|_| |_|@
       @@
       @
  ___  @
 / _ \ @
| (_) |@
 \___/ @
       @@
       @
 _ __  @
| '_ \ @
| |_) |@
| .__/ @
|_|    @@
       @
  __ _ @
 / _` |@
| (_| |@
 \__, |@
    |_|@@
       @
 _ __  @
| '__| @
| |    @
|_|    @
       @@
     @
 ___ @
/ __|@
\__ \@
|___/@
     @@
 _   @
| |_ @
| __|@
| |_ @
 \__|@
     @@
       @
 _   _ @
| | | |@
| |_| |@
 \__,_|@
       @@
       @
__   __@
\ \ / /@
 \ V / @
  \_/  @
       @@
          @
__      __@
\ \ /\ / /@
 \ V  V / @
  \_/\_/  @
          @@
      @
__  __@
\ \/ /@
 >  < @
/_/\_\@
      @@
       @
 _   _ @
| | | |@
| |_| |@
 \__, |@
 |___/ @@
     @
 ____@
|_  /@
 / / @
/___|@
     @@
   __@
  / /@
 | | @
< <  @
 | | @
  \_\@@
 _ @
| |@
| |@
| |@
| |@
|_|@@
__   @
\ \  @
 | | @
  > >@
 | | @
/_/  @@
 /\/|@
|/\/ @
     @
     @
     @
     @@
]==]

local G = {}
do
  local code, rows = 32, {}
  for line in FLF:gmatch("[^\n]+") do
    local body, last = line:match("^(.-)@(@?)$")
    rows[#rows + 1] = body:gsub("%$", "\1")
    if last == "@" then
      local w = 0
      for _, r in ipairs(rows) do if #r > w then w = #r end end
      for i, r in ipairs(rows) do rows[i] = r .. string.rep(" ", w - #r) end
      G[code] = { rows = rows, w = w }
      code, rows = code + 1, {}
    end
  end
end

local FONTS = { standard = true }
local VERSION = "FIGlet Copyright (C) 1991-2012 Glenn Chappell, Ian Chai, John Cowan,\nChristiaan Keet and Claudio Matsuoka\nInternet: <info@figlet.org> Version: 2.2.5, date: 31 May 2012"
local USAGE = "Usage: figlet [ -cklnoprstvxDELNRSWX ] [ -d fontdirectory ]\n              [ -f fontfile ] [ -m smushmode ] [ -w outputwidth ]\n              [ -C controlfile ] [ -I infocode ] [ message ]"

local HIER = { ["|"] = 1, ["/"] = 2, ["\\"] = 2, ["["] = 3, ["]"] = 3, ["{"] = 4, ["}"] = 4, ["("] = 5, [")"] = 5, ["<"] = 6, [">"] = 6 }
local HARD = "\1"

-- smush two touching characters (rules 1-4 of the standard font); nil when they cannot merge
local function smush(l, r)
  if l == " " then return r end
  if r == " " then return l end
  if l == HARD or r == HARD then return nil end
  if l == r then return l end
  if l == "_" and HIER[r] then return r end
  if r == "_" and HIER[l] then return l end
  local a, b = HIER[l], HIER[r]
  if a and b and a ~= b then return a > b and l or r end
  if (l == "[" and r == "]") or (l == "]" and r == "[") or (l == "{" and r == "}") or (l == "}" and r == "{")
     or (l == "(" and r == ")") or (l == ")" and r == "(") then return "|" end
  return nil
end

local function usage(code)
  io.stderr:write(USAGE .. "\n")
  os.exit(code)
end

-- options
local width, align, kern, font, info = 57, "l", false, "standard", nil
local words = {}
local i = 1
local noMoreOpts = false
while arg[i] do
  local a = arg[i]
  if noMoreOpts or a:sub(1, 1) ~= "-" or a == "-" then
    words[#words + 1] = a
  elseif a == "--" then
    noMoreOpts = true
  elseif a == "--help" then
    usage(0)
  else
    local j = 2
    while j <= #a do
      local o = a:sub(j, j)
      if o == "c" then align = "c"
      elseif o == "l" then align = "l"
      elseif o == "r" then align = "r"
      elseif o == "k" then kern = true
      elseif o == "S" then kern = false
      elseif o == "s" or o == "o" or o == "t" or o == "n" or o == "p" or o == "x" or o == "D" or o == "E" or o == "X" or o == "L" or o == "R" or o == "N" then
        -- accepted: no effect on a single left-to-right font
      elseif o == "v" then
        print(VERSION)
        return
      elseif o == "f" or o == "w" or o == "I" or o == "d" or o == "m" or o == "C" then
        local val = a:sub(j + 1)
        if val == "" then
          i = i + 1
          val = arg[i]
        end
        if not val then
          io.stderr:write("figlet: option requires an argument -- '" .. o .. "'\n")
          usage(1)
        end
        if o == "f" then font = val:gsub("%.flf$", "")
        elseif o == "w" then
          width = math.floor(tonumber(val) or 57)
          if width < 1 then width = 57 end
        elseif o == "I" then info = tonumber(val) or 0 end
        j = #a
      else
        io.stderr:write("figlet: invalid option -- '" .. o .. "'\n")
        usage(1)
      end
      j = j + 1
    end
  end
  i = i + 1
end

if info then
  if info == 1 then print("20205")
  elseif info == 2 then print("/usr/share/figlet")
  elseif info == 3 then print(font)
  elseif info == 4 then print(tostring(width))
  elseif info == 0 then print(VERSION)
  else print("") end
  return
end

if not FONTS[font] then
  io.stderr:write("figlet: unable to open font file " .. font .. ".flf\n")
  os.exit(1)
end

-- the input: the words of the command line, or the lines of stdin
local lines = {}
if #words > 0 then
  lines[1] = table.concat(words, " ")
elseif sys.piped then
  local data = io.read("a") or ""
  for l in (data .. (data:sub(-1) == "\n" and "" or "\n")):gmatch("(.-)\n") do lines[#lines + 1] = l end
end

local out = {}
local function emit(rows, len)
  local pad = 0
  if align == "c" then pad = (width - len) // 2
  elseif align == "r" then pad = width - len end
  if pad < 0 then pad = 0 end
  for r = 1, 6 do
    out[#out + 1] = (string.rep(" ", pad) .. rows[r]):gsub(HARD, " ")
  end
end

-- how many columns the next glyph can slide into the line
local function overlap(cur, curw, g)
  local amt = g.w
  for r = 1, 6 do
    local line, row = cur[r], g.rows[r]
    local lb = #line
    while lb > 0 and line:sub(lb, lb) == " " do lb = lb - 1 end
    if lb == 0 then lb = 1 end
    local cb = 1
    while cb <= #row and row:sub(cb, cb) == " " do cb = cb + 1 end
    local a = (cb - 1) + (curw - lb)
    local c1 = line:sub(lb, lb)
    if c1 == "" then c1 = " " end
    local c2 = cb <= #row and row:sub(cb, cb) or nil
    if c1 == " " then a = a + 1
    elseif c2 and smush(c1, c2) then a = a + 1 end
    if a < amt then amt = a end
  end
  return amt
end

local function add(cur, curw, g)
  local amt = kern and 0 or overlap(cur, curw, g)
  if kern then
    -- -k: touching letters, no merging (only the blank space is shared)
    amt = g.w
    for r = 1, 6 do
      local line, row = cur[r], g.rows[r]
      local lb = #line
      while lb > 0 and line:sub(lb, lb) == " " do lb = lb - 1 end
      if lb == 0 then lb = 1 end
      local cb = 1
      while cb <= #row and row:sub(cb, cb) == " " do cb = cb + 1 end
      local a = (cb - 1) + (curw - lb)
      if a < amt then amt = a end
    end
  end
  local nw = curw + g.w - amt
  local res = {}
  for r = 1, 6 do
    local line = cur[r] .. string.rep(" ", math.max(0, curw - #cur[r]))
    local row = g.rows[r]
    local head = line:sub(1, curw - amt)
    local mid = {}
    for k = 1, amt do
      local lc = line:sub(curw - amt + k, curw - amt + k)
      local rc = row:sub(k, k)
      if kern then mid[k] = (lc ~= " ") and lc or rc else mid[k] = smush(lc, rc) or rc end
    end
    res[r] = head .. table.concat(mid) .. row:sub(amt + 1)
  end
  return res, nw
end

local function blankRows() return { "", "", "", "", "", "" } end

for _, text in ipairs(lines) do
  local cur, curw = blankRows(), 0
  local n = 1
  -- split into words (letters) and blanks so lines break at spaces
  while n <= #text do
    local s, e = text:find("^[^ ]+", n)
    if not s then s, e = text:find("^ +", n) end
    local piece = text:sub(s, e)
    local isSpace = piece:sub(1, 1) == " "
    local snap, snapw = cur, curw
    local ok = true
    for k = 1, #piece do
      local b = piece:byte(k)
      local g = isSpace and G[32] or G[b]
      if g then
        local nr, nw = add(cur, curw, g)
        if nw > width and curw > 0 then
          ok = false
          break
        end
        cur, curw = nr, nw
      end
    end
    if not ok then
      if isSpace then
        -- trailing blanks at a break are dropped
        cur, curw = snap, snapw
      else
        if snapw > 0 then
          emit(snap, snapw)
          cur, curw = blankRows(), 0
        else
          cur, curw = snap, snapw
        end
        -- a word that is wider than the line is cut where it no longer fits
        for k = 1, #piece do
          local g = G[piece:byte(k)]
          if g then
            local nr, nw = add(cur, curw, g)
            if nw > width and curw > 0 then
              emit(cur, curw)
              cur, curw = blankRows(), 0
              nr, nw = add(cur, curw, g)
            end
            cur, curw = nr, nw
          end
        end
      end
    end
    n = e + 1
  end
  emit(cur, curw)
end

for _, l in ipairs(out) do print(l) end
