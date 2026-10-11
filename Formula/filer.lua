#!lua
-- filer: a file manager for the SD card. w and s move in the list, enter opens a folder or shows a text file, backspace
-- goes up a folder, c copies the file under the cursor (you type the new name), ctrl-q quits. It cannot delete or rename
-- (Lua has no way to): use rm and mv in the shell. A file over 64 KB is not shown or copied, to keep the memory.
--   filer [FOLDER]      starts in FOLDER (/home/user by default)
-- Needs the graphics and the ui package. Run it with --selftest to check the path and the text wrapping.

local MAX_FILE = 65536

-- joins a folder and a name: "/home/user" and "a.txt" make "/home/user/a.txt"; "/" and "a" make "/a"
local function join(dir, name)
  if dir == "/" then return "/" .. name end
  return dir .. "/" .. name
end

-- the folder above a path: "/home/user" is "/home", "/home" is "/"
local function parent(dir)
  local up = dir:match("^(.*)/[^/]+$")
  if up == nil or up == "" then return "/" end
  return up
end

-- text cut into lines of at most width characters, long lines wrapped; tabs become spaces
local function wrap(text, width)
  local lines = {}
  for raw in (text .. "\n"):gmatch("(.-)\r?\n") do
    raw = raw:gsub("\t", "  "):gsub("[^\32-\126]", "?")
    if raw == "" then
      lines[#lines + 1] = ""
    else
      while #raw > width do
        lines[#lines + 1] = raw:sub(1, width)
        raw = raw:sub(width + 1)
      end
      lines[#lines + 1] = raw
    end
  end
  if lines[#lines] == "" then lines[#lines] = nil end
  return lines
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(join("/home/user", "a.txt") == "/home/user/a.txt", "join adds a slash")
  check(join("/", "a") == "/a", "join from the root has one slash")
  check(parent("/home/user") == "/home" and parent("/home") == "/" and parent("/") == "/", "the folder above")
  local lines = wrap("hello\nworld", 10)
  check(#lines == 2 and lines[1] == "hello" and lines[2] == "world", "two lines stay two lines")
  lines = wrap("abcdefghij", 4)
  check(#lines == 3 and lines[1] == "abcd" and lines[3] == "ij", "a long line is wrapped")
  lines = wrap("a\tb\r\nc", 10)
  check(lines[1] == "a  b" and lines[2] == "c", "tabs become spaces and CR LF is one break")
  check(#wrap("", 10) == 0, "an empty text has no lines")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("filer needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("filer: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui")
if not ui then
  print("filer: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local ROWS = 10
local dir = arg[1] or "/home/user"
local names, sel, top, message = {}, 1, 1, ""

local function load()
  local list, err = fs.list(dir)
  names = {}
  if not list then
    message = tostring(err)
    return
  end
  table.sort(list, function(a, b)
    local da, db = a:sub(-1) == "/", b:sub(-1) == "/"
    if da ~= db then return da end
    return a:lower() < b:lower()
  end)
  names = list
  sel, top = 1, 1
end

local function drawList()
  gfx.clear(0x0a0c14)
  ui.panel(2, 2, W - 4, H - 4, dir)
  if #names == 0 then ui.label(10, 24, "(empty)", 0x8a94aa) end
  if sel < top then top = sel elseif sel >= top + ROWS then top = sel - ROWS + 1 end
  for i = 0, ROWS - 1 do
    local n = names[top + i]
    if n then
      local y = 18 + i * 10
      local isDir = n:sub(-1) == "/"
      if top + i == sel then gfx.fill(4, y - 1, W - 8, 10, 0x3a5a8a) end
      ui.label(8, y, (isDir and "[" or " ") .. n:sub(1, 34), isDir and 0x60c8ff or 0xe8ecf4)
    end
  end
  ui.label(8, H - 14, message ~= "" and message or "enter open  backspace up  c copy", 0x8a94aa)
  gfx.flush()
end

-- shows a text file: w and s scroll, any other key goes back
local function view(path)
  local text, err = fs.read(path)
  if not text then
    message = tostring(err)
    return
  end
  if #text > MAX_FILE then
    message = "too big to show (over 64 KB)"
    return
  end
  local lines = wrap(text, 38)
  local first = 1
  while true do
    gfx.clear(0x0a0c14)
    for i = 0, 12 do
      local line = lines[first + i]
      if line then ui.label(4, 4 + i * 10, line, 0xe8ecf4) end
    end
    ui.label(4, H - 10, string.format("lines %d-%d of %d   w s scroll, other key: back", first, math.min(#lines, first + 12), #lines), 0x8a94aa)
    gfx.flush()
    local k = key.poll()
    while k do
      if k == "w" or k == "up" then first = math.max(1, first - 1)
      elseif k == "s" or k == "down" then first = math.min(math.max(1, #lines - 12), first + 1)
      else return end
      k = key.poll()
    end
    sys.sleep(30)
  end
end

local function copy(path, name)
  local text, err = fs.read(path)
  if not text then
    message = tostring(err)
    return
  end
  if #text > MAX_FILE then
    message = "too big to copy (over 64 KB)"
    return
  end
  local to = join(dir, name)
  if fs.exists(to) then
    message = name .. " exists"
    return
  end
  local ok, werr = fs.write(to, text)
  message = ok and ("copied to " .. name) or tostring(werr)
  if ok then load() end
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if #k == 1 then k = k:lower() end
  local a = ui.keyAction(k)
  message = ""
  if a == "up" then sel = math.max(1, sel - 1)
  elseif a == "down" then sel = math.min(#names, sel + 1)
  elseif k == "backspace" then
    dir = parent(dir)
    load()
  elseif a == "ok" and names[sel] then
    local n = names[sel]
    if n:sub(-1) == "/" then
      dir = join(dir, n:sub(1, -2))
      load()
    else
      view(join(dir, n))
    end
  elseif k == "c" and names[sel] and names[sel]:sub(-1) ~= "/" then
    local name = ui.prompt("Copy to", "copy-" .. names[sel], 30)
    if name and name ~= "" and not name:find("/", 1, true) then copy(join(dir, names[sel]), name) end
  end
  return true
end

local w, h = ui.open()
if not w then
  print("filer: " .. tostring(h))
  return
end
load()
local ok, problem = pcall(function()
  while true do
    local k = key.poll()
    while k do
      if not handle(k) then return end
      k = key.poll()
    end
    drawList()
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("filer: " .. tostring(problem)) end
