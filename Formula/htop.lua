#!lua
-- htop: live view of memory, battery, storage, network and FreeRTOS tasks with CPU use. Press q to quit.

local COLS, ROWS = term.size()
local BAR = 20

local function level(pct)
  if pct >= 85 then return "red" end
  if pct >= 60 then return "yellow" end
  return "green"
end

local function bar(pct)
  local n = math.floor(BAR * math.min(pct, 100) / 100 + 0.5)
  return "[" .. string.rep("|", n) .. string.rep(" ", BAR - n) .. "]", level(pct)
end

local function uptimeText()
  local s = math.floor(sys.uptime())
  return string.format("%02d:%02d:%02d", s // 3600, (s // 60) % 60, s % 60)
end

local prev, prevTotal = {}, 0

-- CPU use per task: the change of its run counter since the last sample, as a share of all CPU time
local function sample()
  local tasks, total = sys.tasks()
  local dtotal = (total - prevTotal) & 0xffffffff
  local rows = {}
  for _, t in ipairs(tasks) do
    local before = prev[t.name] or t.run
    local delta = (t.run - before) & 0xffffffff
    local cpu = dtotal > 0 and (delta * 100 / dtotal) or 0
    rows[#rows + 1] = { name = t.name, prio = t.prio, stack = t.stack, cpu = cpu }
    prev[t.name] = t.run
  end
  prevTotal = total
  table.sort(rows, function(a, b) return a.cpu > b.cpu end)
  return rows
end

local function drawLine(y, label, pct, text)
  local b, color = bar(pct)
  term.text(0, y, string.format("%-6s", label), "cyan")
  term.text(6, y, b, color)
  term.text(6 + #b + 1, y, text, "text")
end

local function draw(rows)
  term.clear()
  local free, total, psram = sys.heap()
  local used = total - free
  local pct, mv, charging = sys.battery()
  local sdTotal, sdUsed = sys.sd()

  term.text(0, 0, "htop", "white")
  term.text(5, 0, "up " .. uptimeText() .. "  " .. sys.user() .. "@" .. sys.hostname(), "dim")

  drawLine(1, "Mem", used * 100 / total, string.format("%d/%dK", used, total))
  drawLine(2, "Batt", pct, string.format("%d%% %dmV%s", pct, mv, charging and " +" or ""))
  if sdTotal then
    local p = sdUsed * 100 / sdTotal
    drawLine(3, "SD", p, string.format("%.1f/%.1fG", sdUsed / 1e9, sdTotal / 1e9))
  else
    term.text(0, 3, "SD     no card", "warn")
  end
  term.text(0, 4, "PSRAM", "cyan")
  term.text(6, 4, psram > 0 and (psram .. " KB total") or "none", "text")
  if net.connected() then
    term.text(0, 5, "Net", "cyan")
    term.text(6, 5, net.ssid() .. " " .. net.ip(), "green")
  else
    term.text(0, 5, "Net", "cyan")
    term.text(6, 5, "offline", "red")
  end

  term.text(0, 7, " #  TASK              PR  STK  CPU", "white")
  local y = 8
  for i, r in ipairs(rows) do
    if y > ROWS - 2 then break end
    local cpuColor = level(r.cpu)
    term.text(0, y, string.format("%2d  %-16s %3d %4d", i, r.name:sub(1, 16), r.prio, r.stack), "text")
    term.text(35, y, string.format("%4.1f", r.cpu), cpuColor)
    y = y + 1
  end
  term.text(0, ROWS - 1, "q quit", "dim")
  term.flush()
end

term.fullscreen(true)
local quit = false
local rows = sample()
local nextSample = sys.millis() + 1000
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true end
    k = key.poll()
  end
  if quit then break end
  if sys.millis() >= nextSample then
    rows = sample()
    nextSample = sys.millis() + 1000
  end
  draw(rows)
  sys.sleep(200)
end
term.fullscreen(false)
