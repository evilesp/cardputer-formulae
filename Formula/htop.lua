#!lua
-- htop: a process viewer in the look of htop. The "processes" are the FreeRTOS tasks of the firmware.
-- keys: up/down/pageup/pagedown move, P sort by CPU%, M by stack, T by time, N by PID, < > change the sort column,
--       I reverse, / search, \ filter, k kill (tasks of the firmware cannot be killed), h help, q quit.
-- The keyboard has no F-keys: F1 h, F3 /, F4 \, F5 t, F6 < >, F9 k, F10 q.

local COLS, ROWS = term.size()
local LW = 27                       -- width of a meter on the left: "  0[" + bar + "]"
local BAR = LW - 5
local RIGHT = LW + 2                -- where the text on the right starts

local SORTS = { "PID", "CPU%", "STK", "TIME+", "Command" }
local sortCol, sortDesc = 2, true
local sel, scroll = 1, 0
local filter, search = "", ""
local mode = nil                    -- nil, "search", "filter", "help"
local input = ""
local message = ""
local tree = false

local prev, prevTotal = {}, 0
local rows, cores = {}, {}
local ncores = 2
local running = 0
local load = { 0, 0, 0 }
local nextSample = 0

local function level(pct)
  if pct >= 85 then return "red" end
  if pct >= 60 then return "yellow" end
  return "green"
end

-- a meter: label, [|||||    text], filled to pct percent; the text is right aligned inside the brackets
local function meter(y, label, pct, text, color)
  term.text(0, y, string.format("%3s", label), "cyan")
  term.text(3, y, "[", "white")
  local n = math.floor(BAR * math.max(0, math.min(pct, 100)) / 100 + 0.5)
  local s = string.rep("|", n) .. string.rep(" ", BAR - n)
  if #text > 0 then s = s:sub(1, BAR - #text) .. text end
  local split = math.min(n, BAR - #text)
  term.text(4, y, s:sub(1, split), color or level(pct))
  term.text(4 + split, y, s:sub(split + 1), "dim")
  term.text(4 + BAR, y, "]", "white")
end

local function sizeText(kb)
  if kb >= 1048576 then return string.format("%.2fG", kb / 1048576) end
  if kb >= 1024 then return string.format("%.1fM", kb / 1024) end
  return string.format("%dK", kb)
end

local function clock(sec)
  local s = math.floor(sec)
  local d = s // 86400
  local t = string.format("%02d:%02d:%02d", (s // 3600) % 24, (s // 60) % 60, s % 60)
  if d > 0 then return string.format("%d day%s, %s", d, d == 1 and "" or "s", t) end
  return t
end

local function timePlus(sec)
  local m = math.floor(sec / 60)
  return string.format("%d:%05.2f", m, sec - m * 60)
end

local function readLoad()
  local out = sys.shell and sys.shell("uptime")
  if type(out) ~= "string" then return end
  local a, b, c = out:match("load average:%s*([%d.]+),%s*([%d.]+),%s*([%d.]+)")
  if a then load = { tonumber(a), tonumber(b), tonumber(c) } end
end

-- CPU use per task: the change of its run counter since the last sample, as a share of the elapsed counter time
local function sample()
  local tasks, total = sys.tasks()
  local dtotal = (total - prevTotal) & 0xffffffff
  local up = sys.uptime()
  local list, idle = {}, {}
  running = 0
  for i, t in ipairs(tasks) do
    local before = prev[t.name] or t.run
    local delta = (t.run - before) & 0xffffffff
    local cpu = dtotal > 0 and (delta * 100 / dtotal) or 0
    prev[t.name] = t.run
    local core = t.name:match("^IDLE(%d)$")
    if core then idle[tonumber(core)] = cpu end
    if cpu > 0.05 and not core then running = running + 1 end
    list[#list + 1] = {
      pid = i, name = t.name, prio = t.prio, stack = t.stack, cpu = cpu,
      secs = total > 0 and (t.run * up / total) or 0,
    }
  end
  prevTotal = total
  local n = 0
  for k in pairs(idle) do if k + 1 > n then n = k + 1 end end
  ncores = math.max(n, 1)
  cores = {}
  for k = 0, ncores - 1 do cores[k] = idle[k] and math.max(0, math.min(100, 100 - idle[k])) or 0 end
  rows = list
  return up
end

local function sortRows(list)
  local key = SORTS[sortCol]
  local function value(r)
    if key == "PID" then return r.pid end
    if key == "CPU%" then return r.cpu end
    if key == "STK" then return r.stack end
    if key == "TIME+" then return r.secs end
    return r.name:lower()
  end
  table.sort(list, function(a, b)
    local x, y = value(a), value(b)
    if x == y then return a.pid < b.pid end
    if sortDesc then return x > y end
    return x < y
  end)
end

local function visible()
  local list = {}
  for _, r in ipairs(rows) do
    if filter == "" or r.name:lower():find(filter:lower(), 1, true) then list[#list + 1] = r end
  end
  sortRows(list)
  return list
end

local function header(y)
  local free, total, psram = sys.heap()
  for k = 0, ncores - 1 do
    meter(y, tostring(k), cores[k], string.format("%.1f%%", cores[k]))
    y = y + 1
  end
  local used = total - free
  meter(y, "Mem", used * 100 / math.max(total, 1), sizeText(used) .. "/" .. sizeText(total), "green")
  y = y + 1
  meter(y, "Swp", 0, "0K/0K", "red")
  y = y + 1
  if psram and psram > 0 then
    meter(y, "Psr", 0, sizeText(psram), "blue")
    y = y + 1
  end
  return y
end

local function stackText(bytes)
  if bytes >= 1024 then return (bytes // 1024) .. "K" end
  return tostring(bytes)
end

local totalHeap = 1
local function draw(up)
  term.clear()
  local _, th = sys.heap()
  totalHeap = th or 1
  local y = header(0)
  -- the text next to the meters
  local n = tostring(#rows)
  term.text(RIGHT, 0, "Tasks: ", "white")
  term.text(RIGHT + 7, 0, n, "green")
  term.text(RIGHT + 7 + #n, 0, ", 0 thr, 0 kthr; ", "white")
  term.text(RIGHT + 16 + #n, 0, tostring(running), "green")
  term.text(RIGHT + 16 + #n + #tostring(running), 0, " running", "white")
  term.text(RIGHT, 1, string.format("Load average: %.2f %.2f %.2f", load[1], load[2], load[3]), "white")
  term.text(RIGHT, 2, "Uptime: " .. clock(up), "white")
  local pct, mv, charging = sys.battery()
  if pct then term.text(RIGHT, 3, string.format("Battery: %d%% %dmV%s", pct, mv, charging and " +" or ""), "white") end

  local headY = y
  term.text(0, headY, string.format("%-" .. COLS .. "s", "PID USER PRI NI VIRT  RES  SHR S CPU% MEM% TIME+  Command"), "inverse-green")
  local list = visible()
  local visibleRows = ROWS - headY - 2
  if sel > #list then sel = #list end
  if sel < 1 then sel = 1 end
  if sel <= scroll then scroll = sel - 1 end
  if sel > scroll + visibleRows then scroll = sel - visibleRows end
  for i = 1, visibleRows do
    local r = list[scroll + i]
    if not r then break end
    local cmd = (tree and "`- " or "") .. r.name
    local stk = stackText(r.stack)
    local line = string.format("%3d %-4s %3d %2d %4s %4s %4s %s %4.1f %4.1f %6s %s", r.pid, "root", 20 - r.prio, 0,
                               stk, stk, "0", r.cpu > 0.05 and "R" or "S", r.cpu, r.stack * 100 / math.max(totalHeap, 1), timePlus(r.secs), cmd)
    local yy = headY + i
    if scroll + i == sel then
      term.text(0, yy, string.format("%-" .. COLS .. "s", line:sub(1, COLS)), "inverse-cyan")
    else
      term.text(0, yy, line:sub(1, COLS), "text")
      term.text(31, yy, string.format("%4.1f", r.cpu), level(r.cpu))
    end
  end

  local bottom = ROWS - 1
  term.text(0, bottom, string.rep(" ", COLS), "text")
  if mode == "search" or mode == "filter" then
    term.text(0, bottom, (mode == "search" and "Search: " or "Filter: ") .. input .. "_", "inverse-cyan")
  elseif message ~= "" then
    term.text(0, bottom, message:sub(1, COLS), "yellow")
  else
    local keys = { { "F1", "Help  " }, { "F2", "Setup " }, { "F3", "Search" }, { "F4", "Filter" }, { "F5", "Tree  " }, { "F6", "SortBy" }, { "F7", "Nice -" }, { "F8", "Nice +" }, { "F9", "Kill  " }, { "F10", "Quit" } }
    local x = 0
    for _, k in ipairs(keys) do
      term.text(x, bottom, k[1], "white")
      term.text(x + #k[1], bottom, k[2], "inverse-cyan")
      x = x + #k[1] + #k[2]
      if x >= COLS then break end
    end
  end

  if mode == "help" then
    local text = {
      "htop 3.3.0 (arch-esp)",
      "up/down pageup/pagedown  move",
      "P M T N   sort by CPU% STK TIME+ PID",
      "< >       previous / next sort column",
      "I         reverse the order",
      "/         search   n next match",
      "\\         filter by name (empty: off)",
      "t         tree view (flat on this device)",
      "k         kill (not possible: FreeRTOS tasks)",
      "q         quit      ctrl-g leaves a prompt",
    }
    for i, l in ipairs(text) do
      term.text(2, 2 + i, string.format("%-" .. (COLS - 4) .. "s", l), i == 1 and "inverse-green" or "inverse")
    end
  end
  term.flush()
end

local function findNext(from)
  local list = visible()
  if search == "" or #list == 0 then return end
  for step = 0, #list - 1 do
    local i = (from + step - 1) % #list + 1
    if list[i].name:lower():find(search:lower(), 1, true) then
      sel = i
      return
    end
  end
  message = "no match for '" .. search .. "'"
end

local function onKey(k)
  if mode == "search" or mode == "filter" then
    if k == "enter" then
      if mode == "search" then search = input; findNext(sel) else filter = input end
      mode = nil
    elseif k == "ctrl-g" then
      mode = nil
    elseif k == "backspace" then
      input = input:sub(1, -2)
    elseif #k == 1 then
      input = input .. k
    end
    return false
  end
  if mode == "help" then
    mode = nil
    return k == "q" or k == "ctrl-c"   -- q in the help leaves htop at once, as in htop
  end
  message = ""
  -- the keyboard has no F-keys: letters stand for them (see the help), real F-key names work where they exist
  local fmap = { f1 = "h", f3 = "/", f4 = "\\", f5 = "t", f6 = "<", f9 = "k", f10 = "q", f7 = "]", f8 = "[" }
  k = fmap[k] or k
  if k == "q" or k == "ctrl-c" then return true end
  if k == "up" then sel = sel - 1
  elseif k == "down" then sel = sel + 1
  elseif k == "pageup" then sel = sel - (ROWS - 8)
  elseif k == "pagedown" then sel = sel + (ROWS - 8)
  elseif k == "P" then sortCol, sortDesc = 2, true
  elseif k == "M" then sortCol, sortDesc = 3, true
  elseif k == "T" then sortCol, sortDesc = 4, true
  elseif k == "N" then sortCol, sortDesc = 1, false
  elseif k == ">" or k == "." then sortCol = sortCol % #SORTS + 1; message = "sorted by " .. SORTS[sortCol]
  elseif k == "<" or k == "," then sortCol = (sortCol - 2) % #SORTS + 1; message = "sorted by " .. SORTS[sortCol]
  elseif k == "I" then sortDesc = not sortDesc
  elseif k == "/" then mode, input = "search", ""
  elseif k == "\\" then mode, input = "filter", filter
  elseif k == "n" then findNext(sel + 1)
  elseif k == "t" then tree = not tree
  elseif k == "h" or k == "?" then mode = "help"
  elseif k == "[" or k == "]" then
    message = "Cannot change the priority of a FreeRTOS task (Permission denied)"
  elseif k == "k" then
    local r = visible()[sel]
    message = r and ("Cannot kill " .. r.name .. ": FreeRTOS tasks are not processes (Operation not permitted)") or ""
  end
  return false
end

term.fullscreen(true)
local up = sample()
readLoad()
nextSample = sys.millis() + 1500
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if onKey(k) then quit = true break end
    k = key.poll()
  end
  if quit then break end
  if sys.millis() >= nextSample then
    up = sample()
    readLoad()
    nextSample = sys.millis() + 1500
  end
  draw(up)
  sys.sleep(120)
end
term.fullscreen(false)
