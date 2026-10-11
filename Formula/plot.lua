#!lua
-- plot: draws a chart of the numbers in a text file. Each line is one point; commas, semicolons, spaces and tabs
-- separate columns, and up to three columns are drawn as three lines. A first line that is not numbers (a header) is
-- taken as the names of the columns. The scale fits the data. If there are more points than the screen is wide, a and d
-- scroll. d/a scroll, ctrl-q quits.
--   plot FILE        e.g. plot /home/user/data.csv
-- Needs the graphics and the ui package. Run it with --selftest to check the reading and the scale.

local COLORS = { 0x40d0ff, 0xffd040, 0x60e060 }

-- reads the text: returns the columns (each a list of numbers), the column names (or nil) and the number of points
local function parse(text)
  local columns, names = {}, nil
  local rows = 0
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local fields = {}
    for f in line:gmatch("[^,;%s]+") do fields[#fields + 1] = f end
    if #fields > 0 then
      local numbers, all = {}, true
      for i = 1, math.min(3, #fields) do
        local n = tonumber(fields[i])
        if n then numbers[i] = n else all = false end
      end
      if all then
        rows = rows + 1
        for i = 1, math.min(3, #fields) do
          columns[i] = columns[i] or {}
          columns[i][rows] = numbers[i]
        end
      elseif rows == 0 and not names then
        names = {}
        for i = 1, math.min(3, #fields) do names[i] = fields[i] end
      end
    end
  end
  return columns, names, rows
end

-- the smallest and the largest value of all columns, widened a little when they are equal
local function range(columns)
  local lo, hi
  for _, col in ipairs(columns) do
    for _, v in ipairs(col) do
      if not lo or v < lo then lo = v end
      if not hi or v > hi then hi = v end
    end
  end
  if not lo then return 0, 1 end
  if lo == hi then return lo - 1, hi + 1 end
  return lo, hi
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local cols, names, n = parse("t,temp\n1,20.5\n2,21\n3,19.5\n")
  check(n == 3 and #cols == 2, "three points in two columns")
  check(names and names[1] == "t" and names[2] == "temp", "the header gives the names")
  check(cols[2][1] == 20.5 and cols[2][3] == 19.5, "the values are read")
  cols, names, n = parse("1 2 3\n4 5 6\n")
  check(n == 2 and #cols == 3 and names == nil, "spaces separate columns, no header")
  cols, names, n = parse("5\n7\nabc\n9\n")
  check(n == 3 and cols[1][3] == 9, "a line that is not a number is skipped")
  local lo, hi = range({ { 3, 1, 2 }, { 10, -4 } })
  check(lo == -4 and hi == 10, "the range covers every column")
  lo, hi = range({ { 5, 5 } })
  check(lo == 4 and hi == 6, "equal values get a range around them")
  lo, hi = range({})
  check(lo == 0 and hi == 1, "no data has a default range")
  if failed == 0 then print("selftest ok") end
  return
end

if not arg[1] then
  print("usage: plot FILE   (a text file with a number per line, or columns of numbers)")
  return
end
if not gfx then
  print("plot needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("plot: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui")
if not ui then
  print("plot: " .. tostring(uiErr))
  return
end

local text, readErr = fs.read(arg[1])
if not text then
  print("plot: " .. arg[1] .. ": " .. tostring(readErr))
  return
end
local columns, names, rows = parse(text)
if rows == 0 then
  print("plot: no numbers in " .. arg[1])
  return
end

local W, H = 240, 135
local PLOT_X, PLOT_Y, PLOT_W, PLOT_H = 30, 14, 204, 100
local lo, hi = range(columns)
local first = 1
local VISIBLE = PLOT_W

local function draw()
  gfx.clear(0x0a0c14)
  gfx.rect(PLOT_X - 1, PLOT_Y - 1, PLOT_W + 2, PLOT_H + 2, 0x4a5470)
  ui.label(2, PLOT_Y - 2, string.format("%.4g", hi), 0x8a94aa)
  ui.label(2, PLOT_Y + PLOT_H - 8, string.format("%.4g", lo), 0x8a94aa)
  local shown = math.min(rows - first + 1, VISIBLE)
  for ci, col in ipairs(columns) do
    local color = COLORS[ci]
    local prevX, prevY
    for i = 0, shown - 1 do
      local v = col[first + i]
      if v then
        local x = PLOT_X + (shown > 1 and math.floor(i * (PLOT_W - 1) / (shown - 1)) or 0)
        local y = PLOT_Y + PLOT_H - 1 - math.floor((v - lo) / (hi - lo) * (PLOT_H - 1))
        if prevX then gfx.line(prevX, prevY, x, y, color) else gfx.pixel(x, y, color) end
        prevX, prevY = x, y
      end
    end
    local label = names and names[ci] or ("column " .. ci)
    ui.label(PLOT_X + (ci - 1) * 70, H - 14, label:sub(1, 11), color)
  end
  ui.label(PLOT_X, PLOT_Y + PLOT_H + 3, string.format("points %d-%d of %d", first, first + shown - 1, rows), 0x8a94aa)
  gfx.flush()
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if #k == 1 then k = k:lower() end
  if k == "d" then first = math.min(math.max(1, rows - VISIBLE + 1), first + 20)
  elseif k == "a" then first = math.max(1, first - 20) end
  return true
end

local w, h = ui.open()
if not w then
  print("plot: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    local k = key.poll()
    while k do
      if not handle(k) then return end
      k = key.poll()
    end
    draw()
    sys.sleep(60)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("plot: " .. tostring(problem)) end
