#!lua
-- notes: short notes kept on the SD card as /home/user/note-NAME.txt. The list shows your notes and "new note". In a note
-- you type: letters are added at the end, enter starts a new line, backspace removes the last character, ctrl-s saves
-- and ctrl-q leaves (press it twice to throw away what you have not saved). A note saved empty is hidden from the list.
-- Needs the graphics and the ui package. Run it with --selftest to check the file names and the line wrapping.

local PREFIX = "/home/user/note-"

local function notePath(name)
  return PREFIX .. name .. ".txt"
end

-- the note names found in a folder listing ("note-shopping.txt" is "shopping"), sorted
local function noteNames(listing)
  local names = {}
  for _, f in ipairs(listing) do
    local n = f:match("^note%-([%w_%-]+)%.txt$")
    if n then names[#names + 1] = n end
  end
  table.sort(names)
  return names
end

local function validName(name)
  return #name >= 1 and #name <= 24 and name:match("^[%w_%-]+$") ~= nil
end

-- the text as lines of at most width characters (a newline starts a new line; a long line is wrapped)
local function wrap(text, width)
  local lines = {}
  for raw in (text .. "\n"):gmatch("(.-)\n") do
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
  local names = noteNames({ "note-b.txt", "readme.txt", "note-a_1.txt", "note-.txt", "note-x y.txt", "remote-tv.rem" })
  check(#names == 2 and names[1] == "a_1" and names[2] == "b", "only note files are listed, sorted")
  check(notePath("shop") == "/home/user/note-shop.txt", "the path of a note")
  check(validName("shop-1") and not validName("a b") and not validName("") and not validName(string.rep("x", 25)), "valid names")
  local lines = wrap("one\n\nthree four", 8)
  check(#lines == 4 and lines[1] == "one" and lines[2] == "" and lines[3] == "three fo" and lines[4] == "ur", "wrapping keeps the empty line and splits the long one")
  lines = wrap("abcdef", 4)
  check(#lines == 2 and lines[2] == "ef", "a long line wraps")
  check(#wrap("", 10) == 1 and wrap("", 10)[1] == "", "an empty note is one empty line")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("notes needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("notes: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("notes: " .. tostring(uiErr))
  return
end

local W, H = 240, 135

-- the editor for one note; returns when the user leaves
local function edit(name)
  local text = fs.read(notePath(name)) or ""
  local dirty, warned, message = false, false, ""
  while true do
    gfx.clear(0x0a0c14)
    ui.label(4, 2, name .. (dirty and " *" or ""), 0xffe060)
    local lines = wrap(text .. "_", 38)
    local first = math.max(1, #lines - 10)
    for i = 0, 10 do
      local line = lines[first + i]
      if line then ui.label(4, 14 + i * 10, line, 0xe8ecf4) end
    end
    ui.label(4, H - 18, message ~= "" and message or "ctrl-s save   ctrl-q leave", 0x8a94aa)
    gfx.flush()
    local k = key.poll()
    while k do
      if k == "ctrl-s" then
        local ok, err = fs.write(notePath(name), text)
        message = ok and "saved" or tostring(err)
        if ok then dirty, warned = false, false end
      elseif k == "ctrl-q" then
        if dirty and not warned then
          warned = true
          message = "unsaved: ctrl-q again to throw away"
        else
          return
        end
      elseif k == "enter" then
        text = text .. "\n"
        dirty, warned = true, false
      elseif k == "backspace" then
        text = text:sub(1, -2)
        dirty, warned = true, false
      elseif #k == 1 and k:byte() >= 32 and k:byte() < 127 then
        text = text .. k
        dirty, warned = true, false
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end

local function main()
  while true do
    local listing = fs.list("/home/user") or {}
    local names = noteNames(listing)
    -- notes saved empty are hidden
    local shown = {}
    for _, n in ipairs(names) do
      local t = fs.read(notePath(n))
      if t and t ~= "" then shown[#shown + 1] = n end
    end
    local items = {}
    for _, n in ipairs(shown) do items[#items + 1] = n end
    items[#items + 1] = "+ new note"
    local c = ui.choose("Notes", items)
    if not c then return end
    if c == #items then
      local name = ui.prompt("Name of the note", "", 24)
      if name and validName(name) then edit(name) end
    else
      edit(shown[c])
    end
  end
end

local w, h = ui.open()
if not w then
  print("notes: " .. tostring(h))
  return
end
local ok, problem = pcall(main)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("notes: " .. tostring(problem)) end
