#!lua
-- asciiquarium: the fish tank of Asciiquarium (Perl): waves on top, a castle, seaweed, many fish, a whale, a ship, a shark
-- and a swan, bubbles from the fish. q quits (p pauses). Options: -c -t -h -v
local VERSION = "1.1"
local USAGE = "Asciiquarium " .. VERSION .. " (Perl)\n\nUsage: asciiquarium [-clt]\n"
  .. "  -c, --classic       Classic mode, only the original animals\n"
  .. "  -l, --loop          (no effect here)\n"
  .. "  -t, --transparent   Make the fish see-through\n"
  .. "  -h, --help          Show this help\n"
  .. "  -v, --version       Show the version"

local classic, transparent = false, false
for _, a in ipairs(arg) do
  if a == "-c" or a == "--classic" then classic = true
  elseif a == "-t" or a == "--transparent" then transparent = true
  elseif a == "-l" or a == "--loop" then -- accepted
  elseif a == "-h" or a == "--help" then print(USAGE) return
  elseif a == "-v" or a == "--version" then print("Asciiquarium " .. VERSION .. " (Perl)") return
  else
    print("Unknown option: " .. a:gsub("^%-+", ""))
    print(USAGE)
    if os and os.exit then os.exit(1) end
    return
  end
end

local W, H = term.size()

-- sprites face right; the left-facing copy is mirrored here (swap the characters that have a mirror image)
local MIRROR = { ["/"] = "\\", ["\\"] = "/", ["("] = ")", [")"] = "(", ["<"] = ">", [">"] = "<", ["["] = "]", ["]"] = "[",
  ["{"] = "}", ["}"] = "{", ["`"] = "'", ["'"] = "`" }
local function lines(s)
  local t = {}
  for l in (s .. "\n"):gmatch("(.-)\n") do t[#t + 1] = l end
  return t
end
local function flip(rows)
  local w = 0
  for _, r in ipairs(rows) do w = math.max(w, #r) end
  local out = {}
  for i, r in ipairs(rows) do
    r = r .. string.rep(" ", w - #r)
    out[i] = r:reverse():gsub(".", MIRROR)
  end
  return out
end

-- {picture, colour, kind}: kind is set for the animals that are not in the classic tank
local DESIGNS = {
  { "    \\\n\\ /--\\\n>=  (o>\n/ \\__/\n    /", "yellow" },
  { "  ,--.\n><  o )>\n  `--'", "cyan" },
  { "><>", "green" },
  { "><(((('>", "magenta" },
  { "      _\n  ___/ \\\n >  o   )=\n  \\__/_/", "white" },
  { "    ,\n\\  /;\\\n >=  o)\n/  \\;/", "red" },
  { "   __\n><_'>\n   \"\"", "blue" },
  { "       _\n  ____/ \\_____\n /  ,      o  >\n \\__\\___/__/", "white", "shark" },
  { "   .----------:\n .'            `.\n/   o           ,)\n`--.__________,/", "blue", "whale" },
  { "   _\n  (o>\n _/ /_\n(____)", "white", "swan" },
}
local SHIP = lines("     |    |    |\n    )_)  )_)  )_)\n   )___))___))___)\\\n  )____)____)_____)\\\\\n_____|____|____|____\\\\\\__\n\\                   /")
for _, d in ipairs(DESIGNS) do
  local r = lines(d[1])
  d.right, d.left = r, flip(r)
end

local CASTLE = lines([==[
               T~~
               |
              /^\
             /   \
 _   _   _  /     \  _   _   _
[ ]_[ ]_[ ]/ _   _ \[ ]_[ ]_[ ]
|_=__-_ =_|_[ ]_[ ]_|_=-___-__|
 | _- =  | =_ = _    |= _=   |
 |= -[]  |- = _ =    |_-=_[] |
 | =_    |= - ___    | =_ =  |
 |=  []- |-  /| |\   |=_ =[] |
 |- =_   | =| | | |  |- = -  |
 |_______|__|_|_|_|__|_______|]==])

local WATER = { "~", "^^^^ ^^^^ ^^^ ^^^^", "^^^^^ ^^^^^^^ ^^^^", " ^^ ^^^^^^ ^^ ^^^^^" }
local TOP = 4  -- rows of water at the top

local bubbles, things, frame = {}, {}, 0
local pause = false
local bigOut = false  -- only one big animal (ship, whale, shark, swan) at a time

local function pick()
  local pool = {}
  for i, d in ipairs(DESIGNS) do
    if not (d[3] and (classic or bigOut)) then pool[#pool + 1] = d end
  end
  return pool[math.random(#pool)]
end

local function spawn(t)
  if t.big then bigOut = false end
  local ship = not classic and not bigOut and math.random(8) == 1
  local d = (not ship) and pick() or nil
  t.dir = math.random(0, 1) == 0 and 1 or -1
  t.rows = d and (t.dir == 1 and d.right or d.left) or (t.dir == 1 and SHIP or flip(SHIP))
  t.color = d and d[2] or "yellow"
  t.big = ship or (d and d[3])
  if t.big then bigOut = true end
  t.w = 0
  for _, r in ipairs(t.rows) do t.w = math.max(t.w, #r) end
  t.x = t.dir == 1 and -t.w or W
  local kind = d and d[3]
  if ship then t.y = 0
  elseif kind == "swan" then t.y = TOP - #t.rows + 1
  elseif kind == "whale" then t.y = TOP + 1
  else t.y = math.random(TOP + 1, math.max(TOP + 1, H - #t.rows - 2)) end
  t.delay = kind == "shark" and 1 or math.random(1, 3)
  t.tick = 0
end

local nFish = math.max(3, (W * (H - TOP - 3)) // 250)
for i = 1, nFish do
  local t = {}
  spawn(t)
  t.x = math.random(0, W - 1)
  things[i] = t
end

local weeds = {}
for x = 2, W - 3, 9 do weeds[#weeds + 1] = { x = x + math.random(0, 3), h = math.random(3, 6) } end

local function drawSprite(x, y, rows, color, solid)
  for r, row in ipairs(rows) do
    local first, last = row:find("%S"), #row:match("^(.-)%s*$")
    local py = y + r - 1
    if py >= 0 and py < H then
      for c = 1, #row do
        local ch = row:sub(c, c)
        local px = x + c - 1
        if px >= 0 and px < W and (ch ~= " " or (solid and first and c > first and c < last)) then
          term.put(px, py, ch, color)
        end
      end
    end
  end
end

local function advance(t)
  t.tick = t.tick + 1
  if t.tick >= t.delay then t.tick = 0; t.x = t.x + t.dir end
  if (t.dir == 1 and t.x > W) or (t.dir == -1 and t.x < -t.w) then spawn(t) return end
  if not t.big and frame % 12 == 0 and math.random(3) == 1 and #bubbles < 30 and t.x >= 0 and t.x < W then
    bubbles[#bubbles + 1] = { x = t.dir == 1 and t.x + t.w or t.x - 1, y = t.y }
  end
end

term.fullscreen(true)
term.clear()
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true elseif k == "p" then pause = not pause end
    k = key.poll()
  end
  if quit then break end

  if not pause then
    frame = frame + 1
    for _, t in ipairs(things) do advance(t) end
    local alive = {}
    for _, b in ipairs(bubbles) do
      if frame % 3 == 0 then b.y = b.y - 1 end
      if b.y >= TOP then alive[#alive + 1] = b end
    end
    bubbles = alive
  end

  term.clear()
  for r = 1, TOP do
    local p = WATER[r]
    local sh = frame // (r + 1)
    for x = 0, W - 1 do
      local i = (x + sh) % #p + 1
      local ch = p:sub(i, i)
      if ch ~= " " then term.put(x, r - 1, ch, "cyan") end
    end
  end
  for _, s in ipairs(weeds) do
    for row = 0, s.h - 1 do
      local left = (frame // 8 + row) % 2 == 0
      term.put(s.x + (left and 0 or 1), H - 1 - row, left and "(" or ")", "green")
    end
  end
  if W >= 50 and H >= 20 then drawSprite(W - #CASTLE[6] - 1, H - #CASTLE, CASTLE, "yellow", true) end
  for _, b in ipairs(bubbles) do term.put(b.x, b.y, (b.y % 2 == 0) and "o" or ".", "cyan") end
  for _, t in ipairs(things) do drawSprite(t.x, t.y, t.rows, t.color, not transparent) end
  term.flush()
  sys.sleep(70)
end
term.fullscreen(false)
