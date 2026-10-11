#!lua
-- countdown: the days until your dates. The list is /home/user/countdown.txt (one line each: YYYY-MM-DD name), the nearest
-- date first. a adds a date (you type the date and the name), x removes the date that is selected, w and s choose,
-- ctrl-q quits. Needs the graphics, the ui package and a clock (the network sets it). Run with --selftest to check the days.

local FILE = "/home/user/countdown.txt"

-- the number of days since 1 January 1970 for a date (proleptic Gregorian calendar)
local function daysFrom(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = y // 400
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = (153 * mp + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

-- the days from the date `today` to the date `date` (both YYYY-MM-DD); nil for a bad date
local function daysUntil(date, today)
  local y, m, d = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  local ty, tm, td = today:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y or not ty then return nil end
  return daysFrom(tonumber(y), tonumber(m), tonumber(d)) - daysFrom(tonumber(ty), tonumber(tm), tonumber(td))
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(daysFrom(1970, 1, 1) == 0 and daysFrom(1970, 1, 2) == 1, "the first day is 0")
  check(daysFrom(2000, 3, 1) - daysFrom(2000, 2, 28) == 2, "2000 was a leap year")
  check(daysFrom(2026, 1, 1) - daysFrom(2025, 1, 1) == 365, "2025 has 365 days")
  check(daysUntil("2026-10-13", "2026-10-12") == 1 and daysUntil("2026-10-12", "2026-10-12") == 0, "one day ahead")
  check(daysUntil("2027-01-01", "2026-12-31") == 1, "over the new year")
  check(daysUntil("2025-12-31", "2026-01-01") == -1, "a date in the past is negative")
  check(daysUntil("not a date", "2026-10-12") == nil, "a bad date is nil")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("countdown needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("countdown: " .. tostring(uiErr))
  return
end

local W_LINE = 232
local items = {}
local selected = 1

local function load()
  items = {}
  local text = fs.read(FILE) or ""
  local today = sys.date("%Y-%m-%d")
  for line in text:gmatch("[^\n]+") do
    local date, name = line:match("^(%d%d%d%d%-%d%d%-%d%d) (.+)$")
    local days = date and daysUntil(date, today)
    if days then items[#items + 1] = { date = date, name = name, days = days } end
  end
  table.sort(items, function(a, b)
    if a.days ~= b.days then return a.days < b.days end
    return a.name < b.name
  end)
  if selected > #items then selected = math.max(1, #items) end
end

local function save()
  local lines = {}
  for _, it in ipairs(items) do lines[#lines + 1] = it.date .. " " .. it.name .. "\n" end
  fs.write(FILE, table.concat(lines))
end

local function draw(message)
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "COUNTDOWN", 0xe8ecf4)
  if #items == 0 then ui.label(8, 30, "no dates yet: press a to add one", 0x8a94aa) end
  for i = 1, math.min(#items, 6) do
    local it = items[i]
    local y = 22 + (i - 1) * 16
    if i == selected then gfx.fill(4, y - 2, W_LINE, 14, 0x2a3350) end
    local when = it.days == 0 and "today" or (it.days > 0 and (tostring(it.days) .. " days") or ("passed " .. tostring(-it.days) .. " days"))
    ui.label(8, y, it.name:sub(1, 22), 0xe8ecf4)
    ui.label(150, y, when, it.days >= 0 and 0xf0d040 or 0x8a94aa)
  end
  ui.label(8, 118, message or "a add   x remove   w s choose   ctrl-q quit", 0x8a94aa)
  gfx.flush()
end
local w, h = ui.open()
if not w then
  print("countdown: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  load()
  local message = nil
  while true do
    draw(message)
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "w" then selected = math.max(1, selected - 1)
      elseif k == "s" then selected = math.min(math.max(1, #items), selected + 1)
      elseif k == "x" and items[selected] then
        table.remove(items, selected)
        save()
        message = "removed"
        if selected > #items then selected = math.max(1, #items) end
      elseif k == "a" then
        local date = ui.prompt("date, YYYY-MM-DD", "", 10)
        if date and daysUntil(date, sys.date("%Y-%m-%d")) then
          local name = ui.prompt("name of the day", "", 22)
          if name and name ~= "" then
            local clean = name:gsub("[\r\n]", " ")
            fs.append(FILE, date .. " " .. clean .. "\n")
            load()
            message = "added " .. name
          end
        else
          message = "that is not a date"
        end
      end
      k = key.poll()
    end
    sys.sleep(60)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("countdown: " .. tostring(problem)) end
