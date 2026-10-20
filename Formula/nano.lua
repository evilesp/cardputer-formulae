#!lua
-- nano: a small text editor for files on the SD card.
-- usage: nano FILE   (arrows move, Ctrl+S saves, Ctrl+X exits, Ctrl+A/Ctrl+E line start/end)

local COLS, ROWS = term.size()
local TEXT_ROWS = ROWS - 2  -- first row is the title, last row is the help line

local path = arg[1] or "untitled.txt"
local lines = {}
local content, err = fs.read(path)
if content then
  content = content:gsub("\r", "")
  for line in (content .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  if content:sub(-1) == "\n" then lines[#lines] = nil end
else
  lines[1] = ""
end
if #lines == 0 then lines[1] = "" end

local cy, cx = 1, 0        -- cursor: line and column (cx counts characters before the cursor)
local top = 1              -- first visible line
local left = 0             -- first visible column
local modified = false
local message = content and "" or ("new file: " .. path)
local quitWarned = false

local function clampCursor()
  if cy < 1 then cy = 1 end
  if cy > #lines then cy = #lines end
  if cx > #lines[cy] then cx = #lines[cy] end
  if cx < 0 then cx = 0 end
  if cy < top then top = cy end
  if cy >= top + TEXT_ROWS then top = cy - TEXT_ROWS + 1 end
  if cx < left then left = cx end
  if cx >= left + COLS then left = cx - COLS + 1 end
end

local function save()
  local data = table.concat(lines, "\n") .. "\n"
  local ok, e = fs.write(path, data)
  if ok then
    modified = false
    message = "saved " .. path
  else
    message = "save failed: " .. tostring(e)
  end
end

local function insert(ch)
  local line = lines[cy]
  lines[cy] = line:sub(1, cx) .. ch .. line:sub(cx + 1)
  cx = cx + #ch
  modified = true
end

local function newline()
  local line = lines[cy]
  table.insert(lines, cy + 1, line:sub(cx + 1))
  lines[cy] = line:sub(1, cx)
  cy = cy + 1
  cx = 0
  modified = true
end

local function backspace()
  if cx > 0 then
    local line = lines[cy]
    lines[cy] = line:sub(1, cx - 1) .. line:sub(cx + 1)
    cx = cx - 1
  elseif cy > 1 then
    local prevLen = #lines[cy - 1]
    lines[cy - 1] = lines[cy - 1] .. lines[cy]
    table.remove(lines, cy)
    cy = cy - 1
    cx = prevLen
  else
    return
  end
  modified = true
end

local function delete()
  local line = lines[cy]
  if cx < #line then
    lines[cy] = line:sub(1, cx) .. line:sub(cx + 2)
  elseif cy < #lines then
    lines[cy] = line .. lines[cy + 1]
    table.remove(lines, cy + 1)
  else
    return
  end
  modified = true
end

-- The picture is drawn with the gfx module when the firmware has it: a real block cursor (the character under it is
-- drawn inverse), which the text terminal cannot show. Without gfx the screen is text only, with a plain cursor letter.
local CELL_W, CELL_H = 6, 8
local C_TEXT, C_DIM, C_TITLE, C_BG = 0xd7d7d7, 0x828282, 0xffffff, 0x000000
local useGfx = false
if gfx then
  local w = gfx.open()
  useGfx = w ~= nil
end

local function drawGfx()
  gfx.clear(C_BG)
  local title = " " .. path .. (modified and " (modified)" or "")
  gfx.fill(0, 0, COLS * CELL_W, CELL_H, 0x202838)
  gfx.text(0, 0, title:sub(1, COLS), C_TITLE, 1)
  for row = 0, TEXT_ROWS - 1 do
    local n = top + row
    if lines[n] then
      gfx.text(0, (row + 1) * CELL_H, lines[n]:sub(left + 1, left + COLS), C_TEXT, 1)
    end
  end
  local help = message ~= "" and message or "^S save  ^X exit  ^A/^E line"
  gfx.text(0, (ROWS - 1) * CELL_H, help:sub(1, COLS), C_DIM, 1)
  local sx, sy = cx - left, cy - top + 1
  if sy >= 1 and sy <= TEXT_ROWS and sx >= 0 and sx < COLS then
    local ch = lines[cy]:sub(cx + 1, cx + 1)
    gfx.fill(sx * CELL_W, sy * CELL_H, CELL_W, CELL_H, C_TEXT)
    gfx.text(sx * CELL_W, sy * CELL_H, ch ~= "" and ch or " ", C_BG, 1)
  end
  gfx.flush()
end

local function drawText()
  term.clear()
  local title = " " .. path .. (modified and " (modified)" or "")
  term.text(0, 0, string.rep(" ", COLS), "text")
  term.text(0, 0, title:sub(1, COLS), "white")
  for row = 0, TEXT_ROWS - 1 do
    local n = top + row
    if lines[n] then
      term.text(0, row + 1, lines[n]:sub(left + 1, left + COLS), "text")
    end
  end
  term.text(0, ROWS - 1, string.rep(" ", COLS), "text")
  term.text(0, ROWS - 1, (message ~= "" and message or "^S save  ^X exit  ^A/^E line"):sub(1, COLS), "dim")
  local sx, sy = cx - left, cy - top + 1
  if sy >= 1 and sy <= TEXT_ROWS then
    local ch = lines[cy]:sub(cx + 1, cx + 1)
    term.put(sx, sy, ch ~= "" and ch or " ", "white")
  end
  term.flush()
end

local function draw()
  if useGfx then drawGfx() else drawText() end
end

if not useGfx then term.fullscreen(true) end
clampCursor()
local quit = false
while not quit do
  local k = key.poll()
  while k do
    message = (message:find("unsaved") and not k:find("ctrl%-x")) and "" or message
    if k == "up" then
      cy = cy - 1
      if cx > #lines[math.max(cy, 1)] then cx = #lines[math.max(cy, 1)] end
    elseif k == "down" then
      cy = cy + 1
    elseif k == "left" then
      if cx > 0 then cx = cx - 1 elseif cy > 1 then cy = cy - 1; cx = #lines[cy] end
    elseif k == "right" then
      if cx < #lines[cy] then cx = cx + 1 elseif cy < #lines then cy = cy + 1; cx = 0 end
    elseif k == "pageup" then
      cy = cy - TEXT_ROWS
    elseif k == "pagedown" then
      cy = cy + TEXT_ROWS
    elseif k == "enter" then
      newline()
    elseif k == "backspace" then
      backspace()
    elseif k == "tab" then
      insert("  ")
    elseif k == "ctrl-a" then
      cx = 0
    elseif k == "ctrl-e" then
      cx = #lines[cy]
    elseif k == "ctrl-s" then
      save()
    elseif k == "ctrl-x" then
      if modified and not quitWarned then
        quitWarned = true
        message = "unsaved changes: ^X again to discard, ^S to save"
      else
        quit = true
      end
    elseif #k == 1 then
      insert(k)
    end
    if k ~= "ctrl-x" then quitWarned = false end
    clampCursor()
    k = key.poll()
  end
  if quit then break end
  draw()
  sys.sleep(40)
end
if useGfx then gfx.close() else term.fullscreen(false) end
