#!lua
-- moodlog: a mood diary. Press 1 to 5 for how the day is (1 very bad, 5 very good); enter then adds a note. Every entry goes
-- to /home/user/mood.csv on the SD card (date, score, note), and the graph shows the last 30 entries. ctrl-q quits.
-- Needs the graphics, the ui package and a clock (the network sets it). Run it with --selftest to check the file lines.

local FILE = "/home/user/mood.csv"

-- one line of the file: date, score (1 to 5) and the note (which may hold commas after the second one)
local function parseLine(line)
  local date, score, note = line:match("^(%d%d%d%d%-%d%d%-%d%d),(%d),(.*)$")
  if not date then return nil end
  score = tonumber(score)
  if score < 1 or score > 5 then return nil end
  return { date = date, score = score, note = note }
end

-- the line to add for an entry; the note has no line breaks and no commas (they would split the line)
local function formatLine(date, score, note)
  local clean = (note or ""):gsub("[,\r\n]", " ")
  return date .. "," .. tostring(score) .. "," .. clean .. "\n"
end

-- the average of the scores of a list of entries (nil for an empty list)
local function average(entries)
  if #entries == 0 then return nil end
  local sum = 0
  for _, e in ipairs(entries) do sum = sum + e.score end
  return sum / #entries
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local e = parseLine("2026-10-12,4,good walk")
  check(e and e.date == "2026-10-12" and e.score == 4 and e.note == "good walk", "a line is read")
  check(parseLine("2026-10-12,9,too high") == nil and parseLine("bad line") == nil, "a bad line is skipped")
  check(parseLine("2026-10-12,3,a, b, c").note == "a, b, c", "the note keeps its commas")
  check(formatLine("2026-10-12", 5, "a, b\nc") == "2026-10-12,5,a  b c\n", "a note is written without commas or line breaks")
  check(average({ { score = 2 }, { score = 4 } }) == 3 and average({}) == nil, "the average")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("moodlog needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("moodlog: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local entries = {}

local function load()
  entries = {}
  local text = fs.read(FILE)
  if not text then return end
  for line in text:gmatch("[^\n]+") do
    local e = parseLine(line)
    if e then entries[#entries + 1] = e end
  end
end

local function today()
  return sys.date("%Y-%m-%d")
end

local function draw(message)
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "MOOD LOG", 0xe8ecf4)
  local recent = {}
  for i = math.max(1, #entries - 29), #entries do recent[#recent + 1] = entries[i] end
  local bw = 6
  for i, e in ipairs(recent) do
    local x = 8 + (i - 1) * (bw + 1)
    local hgt = e.score * 16
    local colour = e.score >= 4 and 0x60ff90 or (e.score == 3 and 0xf0d040 or 0xff6060)
    gfx.fill(x, 100 - hgt, bw, hgt, colour)
  end
  gfx.hline(4, W - 5, 100, 0x3a4260)
  local avg = average(recent)
  ui.label(8, 78 - 14, avg and string.format("average %.1f of 5 (last %d)", avg, #recent) or "no entries yet", 0xe8ecf4)
  ui.label(8, 112, "1-5 log today   enter adds a note   ctrl-q quits", 0x8a94aa)
  if message then ui.label(8, 124, message, 0x60ff90) end
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("moodlog: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  load()
  local message = nil
  draw(message)
  while true do
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k:match("^[1-5]$") then
        local note = ui.prompt("note for today (enter to skip)", "", 60)
        if note ~= nil then
          local line = formatLine(today(), tonumber(k), note)
          local good, err = fs.append(FILE, line)
          if good then
            entries[#entries + 1] = parseLine(line:sub(1, -2))
            message = "saved: " .. k .. " today"
          else
            message = "cannot save: " .. tostring(err)
          end
        end
      end
      k = key.poll()
    end
    draw(message)
    sys.sleep(120)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("moodlog: " .. tostring(problem)) end
