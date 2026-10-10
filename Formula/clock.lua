#!lua
-- clock: a big digital clock, updated every second. q quits.

local DIGITS = {
  ["0"] = { "###", "# #", "# #", "# #", "###" }, ["1"] = { " # ", "## ", " # ", " # ", "###" },
  ["2"] = { "###", "  #", "###", "#  ", "###" }, ["3"] = { "###", "  #", "###", "  #", "###" },
  ["4"] = { "# #", "# #", "###", "  #", "  #" }, ["5"] = { "###", "#  ", "###", "  #", "###" },
  ["6"] = { "###", "#  ", "###", "# #", "###" }, ["7"] = { "###", "  #", "  #", "  #", "  #" },
  ["8"] = { "###", "# #", "###", "# #", "###" }, ["9"] = { "###", "# #", "###", "  #", "###" },
  [":"] = { "   ", " # ", "   ", " # ", "   " },
}

local COLS, ROWS = term.size()

local function bigText(s)
  local rows = {}
  for r = 1, 5 do
    local parts = {}
    for c in s:gmatch(".") do parts[#parts + 1] = DIGITS[c][r] .. " " end
    rows[r] = table.concat(parts)
  end
  return rows
end

local function draw()
  term.clear()
  local now = sys.date("%H:%M:%S")
  local date = sys.date("%A %d %B %Y")
  if now then
    local rows = bigText(now)
    local width = #rows[1]
    local x0 = (COLS - width) // 2
    local y0 = (ROWS - 5) // 2
    for r, line in ipairs(rows) do term.text(x0, y0 + r - 1, line, "green") end
    term.text((COLS - #date) // 2, y0 - 2, date, "cyan")
  else
    local up = math.floor(sys.uptime())
    term.text(2, 6, "clock not set yet (connect to WiFi)", "warn")
    term.text(2, 8, string.format("uptime %02d:%02d:%02d", up // 3600, (up // 60) % 60, up % 60), "text")
  end
  term.text(0, ROWS - 1, "q quit", "dim")
  term.flush()
end

term.fullscreen(true)
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true end
    k = key.poll()
  end
  if quit then break end
  draw()
  sys.sleep(250)
end
term.fullscreen(false)
