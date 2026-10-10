#!lua
-- appstore: every formula of your brew taps on one screen. Search by name or description, read the description,
-- and see what is installed. A package cannot start a command, so to install, the screen shows the exact line
-- "brew install NAME" to type in the terminal. The list comes from the indexes that "brew update" saved.
--   type        search: names that start with the text come first, then names, then descriptions
--   up, down    choose an app             enter    details
--   backspace   delete a letter           ctrl-x   quit
--   details:    up, down scroll; i installs or updates the app (firmware v0.1.0.7(beta) or newer);
--               backspace, left or b go back
--   * installed    u installed, but the index has a newer version

local INDEX_DIR = "/var/lib/brew/index"
local INSTALLED = "/var/lib/brew/installed"
local COLS, ROWS = term.size()
local LIST_TOP = 2               -- the first list row (row 1 is the search line)
local LIST_ROWS = ROWS - 4       -- list rows: 2 .. ROWS-3, then the count row and the key row

local function trim(s)
  s = s:gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

local function split(s, sep)
  local out = {}
  for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
  return out
end

-- Every formula of every cached tap index. A name listed by two taps shows up once (the first tap wins).
local function loadApps()
  local files = fs.list(INDEX_DIR)
  if not files then return nil end
  table.sort(files)
  local apps, seen = {}, {}
  for _, file in ipairs(files) do
    if file:sub(-1) ~= "/" then
      local text = fs.read(INDEX_DIR .. "/" .. file)
      if text then
        local base = nil
        for raw in text:gmatch("[^\n]+") do
          local line = trim(raw)
          if line:sub(1, 5) == "BASE " then
            base = trim(line:sub(6))
          elseif base and line ~= "" and line:sub(1, 1) ~= "#" then
            local parts = split(line, "|")
            local name = #parts >= 4 and trim(parts[1]) or ""
            if name ~= "" and not seen[name] then
              seen[name] = true
              local desc = trim(table.concat(parts, "|", 3, #parts - 1))
              apps[#apps + 1] = {
                name = name,
                version = trim(parts[2]),
                desc = desc,
                path = trim(parts[#parts]),
                base = base,
                lname = name:lower(),
                ldesc = desc:lower(),
              }
            end
          end
        end
      end
    end
  end
  table.sort(apps, function(a, b) return a.lname < b.lname end)
  return apps
end

-- name -> installed version, from /var/lib/brew/installed ("name version" lines)
local function loadInstalled()
  local installed = {}
  local text = fs.read(INSTALLED)
  if not text then return installed end
  for line in text:gmatch("[^\n]+") do
    local name, version = line:match("^%s*(%S+)%s+(%S+)")
    if name then installed[name] = version end
  end
  return installed
end

-- The apps whose name or description holds the query, best matches first
local function search(apps, query)
  local q = query:lower()
  if q == "" then return apps end
  local startsWith, inName, inDesc = {}, {}, {}
  for _, app in ipairs(apps) do
    if app.lname:sub(1, #q) == q then startsWith[#startsWith + 1] = app
    elseif app.lname:find(q, 1, true) then inName[#inName + 1] = app
    elseif app.ldesc:find(q, 1, true) then inDesc[#inDesc + 1] = app
    end
  end
  local result = {}
  for _, group in ipairs({ startsWith, inName, inDesc }) do
    for _, app in ipairs(group) do result[#result + 1] = app end
  end
  return result
end

-- "installed 1.0", "installed 1.0, update to 1.0.0.2" or "not installed"
local function statusOf(app, installed)
  local v = installed[app.name]
  if not v then return "not installed" end
  if v == app.version then return "installed " .. v end
  return "installed " .. v .. ", update to " .. app.version
end

-- Words wrapped to the width; a word longer than a line is cut
local function wrap(text, width)
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    while #word > width do
      if line ~= "" then
        lines[#lines + 1] = line
        line = ""
      end
      lines[#lines + 1] = word:sub(1, width)
      word = word:sub(width + 1)
    end
    if line == "" then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. " " .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

local function keepVisible(sel, top)
  if sel < top then return sel end
  if sel > top + LIST_ROWS - 1 then return sel - LIST_ROWS + 1 end
  return top
end

local function drawList(apps, results, query, sel, top, installed)
  term.clear()
  term.text(0, 0, string.format("appstore  %d apps", #apps):sub(1, COLS), "cyan")
  term.text(0, 1, ("> " .. query .. "_"):sub(1, COLS), "white")
  if #results == 0 then
    term.text(0, LIST_TOP, ("no app matches '" .. query .. "'"):sub(1, COLS), "text")
  end
  for row = 0, LIST_ROWS - 1 do
    local idx = top + row
    local app = results[idx]
    if not app then break end
    local v = installed[app.name]
    local marker = " "
    if v == app.version then marker = "*" elseif v then marker = "u" end
    local text = string.format("%s %-16s %s", marker, app.name:sub(1, 16), app.desc)
    term.text(0, LIST_TOP + row, text:sub(1, COLS), idx == sel and "white" or "text")
  end
  if #results > 0 then
    term.text(0, ROWS - 2, string.format("%d of %d   enter: details", sel, #results):sub(1, COLS), "dim")
  end
  term.text(0, ROWS - 1, "* installed  u update  ctrl-x quit", "dim")
  term.flush()
end

-- The lines of the details screen: { text, color }
local function detailLines(app, installed)
  local lines = {}
  local function add(text, color)
    if text == "" then
      lines[#lines + 1] = { "", color }
      return
    end
    for _, l in ipairs(wrap(text, COLS)) do lines[#lines + 1] = { l, color } end
  end
  add(app.name .. "  " .. app.version, "cyan")
  add(string.rep("-", COLS), "dim")
  add(app.desc, "text")
  add("", "text")
  add("status: " .. statusOf(app, installed), "text")
  add("from: " .. app.base, "text")
  add("file: " .. app.path, "text")
  add("", "text")
  if brew and brew.install then
    add("press i to install or update it", "dim")
  else
    add("needs firmware v0.1.0.7(beta) or newer", "dim")
  end
  add("brew install " .. app.name, "white")
  return lines
end

-- the last line of a text, brew's final message
local function lastLine(text)
  local last = ""
  for line in text:gmatch("[^\n]+") do last = trim(line) end
  return last
end

-- the details screen; the row above the key row shows the message (the install result)
local function drawDetails(lines, dtop, message)
  term.clear()
  for row = 0, ROWS - 3 do
    local item = lines[dtop + row]
    if not item then break end
    term.text(0, row, item[1]:sub(1, COLS), item[2])
  end
  if message then term.text(0, ROWS - 2, message:sub(1, COLS), "cyan") end
  term.text(0, ROWS - 1, "up/down  i install  b back  ctrl-x", "dim")
  term.flush()
end

local apps = loadApps()
if not apps then
  print("appstore: no formula index yet. Run: brew update")
  return
end
if #apps == 0 then
  print("appstore: the taps list no formulae (see: brew tap)")
  return
end
local installed = loadInstalled()

local query, results, sel, top = "", apps, 1, 1
local view, detail, dtop = "list", nil, 1
local chosen, message = nil, nil   -- the app whose details are shown, and the line under them
local function refresh()
  results = search(apps, query)
  sel, top = 1, 1
end

-- i in the details: installs or updates the app with brew.install (firmware v0.1.0.7(beta) or newer).
-- Older firmware has no brew.install, so the screen says so and the command line stays for the terminal.
local function installChosen()
  if not (brew and brew.install) then
    message = "needs firmware v0.1.0.7(beta) or newer"
    return
  end
  drawDetails(detail, dtop, "installing " .. chosen.name .. "...")
  local ok, out = brew.install(chosen.name)
  installed = loadInstalled()
  detail = detailLines(chosen, installed)
  if ok then
    message = "installed " .. chosen.name .. " " .. chosen.version
  else
    message = "failed: " .. lastLine(out)
  end
end

term.fullscreen(true)
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if k == "ctrl-x" then
      quit = true
    elseif view == "list" then
      if k == "up" and sel > 1 then
        sel = sel - 1
      elseif k == "down" and sel < #results then
        sel = sel + 1
      elseif k == "enter" and results[sel] then
        view, chosen, message, dtop = "details", results[sel], nil, 1
        detail = detailLines(chosen, installed)
      elseif k == "backspace" then
        query = query:sub(1, -2)
        refresh()
      elseif #k == 1 then
        query = query .. k
        refresh()
      end
      top = keepVisible(sel, top)
    else
      local maxTop = math.max(1, #detail - (ROWS - 2) + 1)
      if k == "up" and dtop > 1 then
        dtop = dtop - 1
      elseif k == "down" and dtop < maxTop then
        dtop = dtop + 1
      elseif k == "i" then
        installChosen()
      elseif k == "backspace" or k == "left" or k == "b" then
        view, message = "list", nil
      end
    end
    if quit then break end
    k = key.poll()
  end
  if not quit then
    if view == "list" then
      drawList(apps, results, query, sel, top, installed)
    else
      drawDetails(detail, dtop, message)
    end
    sys.sleep(60)
  end
end
term.fullscreen(false)
