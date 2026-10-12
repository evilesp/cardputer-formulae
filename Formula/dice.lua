#!lua
-- dice: a dice roller for board games and role-playing games. Choose the die with 1 to 7 (d4, d6, d8, d10, d12, d20, d100), the
-- number of dice with w and s, the bonus with a and d, then press space to roll: the dice tumble and settle. v switches between a
-- normal roll, advantage (the higher of two rolls) and disadvantage (the lower). t types a roll like 3d6+2. The last rolls are
-- listed. ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the rolls.

local SIDES = { 4, 6, 8, 10, 12, 20, 100 }
local MODES = { "normal", "advantage", "disadvantage" }

-- a roll of `count` dice with `sides` sides and a bonus: the values and the total
local function roll(count, sides, bonus)
  local values, total = {}, bonus
  for i = 1, count do
    values[i] = math.random(sides)
    total = total + values[i]
  end
  return values, total
end

-- a roll with advantage (mode 2) or disadvantage (mode 3): two rolls, the higher or the lower is kept
local function rollMode(count, sides, bonus, mode)
  local a, ta = roll(count, sides, bonus)
  if mode == 1 then return a, ta end
  local b, tb = roll(count, sides, bonus)
  if (mode == 2 and tb > ta) or (mode == 3 and tb < ta) then return b, tb, a, ta end
  return a, ta, b, tb
end

-- the text "3d6+2", "d20", "2d10-1" as count, sides, bonus; nil when it is not one
local function parseRoll(text)
  local s = text:gsub("%s+", ""):lower()
  local n, sides, sign, bonus = s:match("^(%d*)d(%d+)([%+%-]?)(%d*)$")
  if not sides then return nil end
  local count = n == "" and 1 or tonumber(n)
  sides = tonumber(sides)
  bonus = (bonus == "" and 0 or tonumber(bonus)) * (sign == "-" and -1 or 1)
  if count < 1 or count > 20 or sides < 2 or sides > 1000 then return nil end
  return count, sides, bonus
end

local function label(count, sides, bonus)
  return (count > 1 and count or "") .. "d" .. sides .. (bonus > 0 and ("+" .. bonus) or (bonus < 0 and tostring(bonus) or ""))
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  math.randomseed(7)
  local seen, ok = {}, true
  for _ = 1, 600 do
    local v, total = roll(2, 6, 3)
    for _, x in ipairs(v) do
      if x < 1 or x > 6 then ok = false end
      seen[x] = true
    end
    if total ~= v[1] + v[2] + 3 then ok = false end
  end
  check(ok and #seen == 6, "dice stay between 1 and the sides, and the total adds up")
  local better, worse = 0, 0
  for _ = 1, 400 do
    local _, t = rollMode(1, 20, 0, 2)
    better = better + t
    local _, t2 = rollMode(1, 20, 0, 3)
    worse = worse + t2
  end
  check(better / 400 > 12.5 and worse / 400 < 8.5, "advantage rolls higher, disadvantage lower")
  local c, s, b = parseRoll("3d6+2")
  check(c == 3 and s == 6 and b == 2, "3d6+2")
  c, s, b = parseRoll("D20")
  check(c == 1 and s == 20 and b == 0, "d20")
  c, s, b = parseRoll("2d10 - 1")
  check(c == 2 and s == 10 and b == -1, "2d10 - 1")
  check(parseRoll("0d6") == nil and parseRoll("d1") == nil and parseRoll("hello") == nil and parseRoll("25d6") == nil, "bad rolls")
  check(label(3, 6, 2) == "3d6+2" and label(1, 20, 0) == "d20" and label(2, 10, -1) == "2d10-1", "labels")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("dice needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("dice: " .. tostring(uiErr))
  return
end

local W, H = 240, 135

-- one die drawn in a box: a d6 shows its pips, other dice show the number on a shape
local PIPS = {
  [1] = { { 2, 2 } }, [2] = { { 1, 1 }, { 3, 3 } }, [3] = { { 1, 1 }, { 2, 2 }, { 3, 3 } }, [4] = { { 1, 1 }, { 3, 1 }, { 1, 3 }, { 3, 3 } },
  [5] = { { 1, 1 }, { 3, 1 }, { 2, 2 }, { 1, 3 }, { 3, 3 } }, [6] = { { 1, 1 }, { 3, 1 }, { 1, 2 }, { 3, 2 }, { 1, 3 }, { 3, 3 } },
}
local function drawDie(x, y, size, sides, value, colour)
  if sides == 6 then
    gfx.fill(x, y, size, size, colour)
    gfx.fill(x + 1, y + 1, size - 2, 2, 0xffffff)
    local step = size // 4
    for _, p in ipairs(PIPS[value] or {}) do gfx.disc(x + p[1] * step, y + p[2] * step, math.max(1, size // 9), 0x181818) end
  else
    local cx, cy = x + size // 2, y + size // 2
    if sides == 4 then gfx.triangle(cx, y, x, y + size, x + size, y + size, colour)
    elseif sides == 20 then
      gfx.triangle(cx, y, x, y + size * 3 // 4, x + size, y + size * 3 // 4, colour)
      gfx.triangle(x, y + size // 4, x + size, y + size // 4, cx, y + size, colour)
    elseif sides == 8 or sides == 10 then
      gfx.triangle(cx, y, x, cy, x + size, cy, colour)
      gfx.triangle(x, cy, x + size, cy, cx, y + size, colour)
    else gfx.disc(cx, cy, size // 2, colour) end
    local text = tostring(value)
    ui.center(cy - 3, text, 0x101010, 1, x, x + size)
  end
end

local sideIdx, count, bonus, mode = 6, 1, 0, 1
local custom  -- a roll typed with t: { count, sides, bonus }
local history = {}
local current  -- { values, total, other, otherTotal, label }
local rolling = 0

local function currentSpec()
  if custom then return custom[1], custom[2], custom[3] end
  return count, SIDES[sideIdx], bonus
end

local function draw()
  gfx.clear(0x0a0e18)
  local c, s, b = currentSpec()
  ui.label(4, 3, "DICE  " .. label(c, s, b) .. (mode > 1 and ("  " .. MODES[mode]) or ""), 0xe8ecf4)
  -- the dice
  local values = rolling > 0 and nil or (current and current.values)
  local n = c
  local size = n <= 3 and 34 or (n <= 6 and 24 or 16)
  local perRow = math.max(1, (W - 8) // (size + 4))
  for i = 1, n do
    local row, col = (i - 1) // perRow, (i - 1) % perRow
    local x, y = 8 + col * (size + 4), 20 + row * (size + 4)
    local v = values and values[i] or math.random(s)
    local colour = 0xe8e0d0
    if values and (s == 20 and v == 20) then colour = 0x60e090 elseif values and s == 20 and v == 1 then colour = 0xff7070 end
    drawDie(x, y, size, s, v, colour)
  end
  if current and rolling == 0 then
    ui.label(150, 20, tostring(current.total), 0x60e090, 4)
    if current.other then ui.label(150, 56, "other roll " .. current.otherTotal, 0x8a94aa) end
  end
  -- the history, newest first
  for i = 1, math.min(4, #history) do
    local h = history[#history - i + 1]
    ui.label(150, 72 + (i - 1) * 10, h.label .. " = " .. h.total, i == 1 and 0xe8ecf4 or 0x8a94aa)
  end
  ui.label(4, H - 22, "1-7 die  w s count  a d bonus", 0x8a94aa)
  ui.label(4, H - 10, "space roll  v adv.  t type  ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local function doRoll()
  local c, s, b = currentSpec()
  local values, total, otherValues, otherTotal = rollMode(c, s, b, mode)
  current = { values = values, total = total, other = otherValues, otherTotal = otherTotal }
  history[#history + 1] = { label = label(c, s, b), total = total }
  rolling = 0
end

local w, h = ui.open()
if not w then
  print("dice: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    draw()
    if rolling > 0 then
      rolling = rolling - 1
      if rolling == 0 then doRoll() end
    end
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      if k:match("^[1-7]$") then sideIdx, custom = tonumber(k), nil
      elseif k == "w" or k == "up" then if custom then custom[1] = math.min(20, custom[1] + 1) else count = math.min(20, count + 1) end
      elseif k == "s" or k == "down" then if custom then custom[1] = math.max(1, custom[1] - 1) else count = math.max(1, count - 1) end
      elseif k == "d" or k == "right" then if custom then custom[3] = custom[3] + 1 else bonus = math.min(50, bonus + 1) end
      elseif k == "a" or k == "left" then if custom then custom[3] = custom[3] - 1 else bonus = math.max(-50, bonus - 1) end
      elseif k == "v" then mode = mode % 3 + 1
      elseif k == "t" then
        local text = ui.prompt("roll (3d6+2)", "", 12)
        if text then
          local c, s, b = parseRoll(text)
          if c then custom = { c, s, b } else ui.message("Not a roll", { "try 3d6+2, d20, 2d10-1" }) end
        end
      elseif k == " " or k == "enter" then rolling = 12
      end
      k = key.poll()
    end
    sys.sleep(rolling > 0 and 40 or 30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("dice: " .. tostring(problem)) end
