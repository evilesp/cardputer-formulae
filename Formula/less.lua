#!lua
-- less: read a file one screen at a time. usage: less FILE
-- up/down, pageup/pagedown, left/right (sideways), g = top, G = end, q = quit

local ROWS_TEXT = 15
local COLS = 40

local path = arg[1]
if not path then
  print("usage: less FILE")
  return
end
local data, err = fs.read(path)
if not data then
  print("less: " .. path .. ": " .. tostring(err))
  return
end

local lines = {}
for line in (data:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
if #lines > 0 and lines[#lines] == "" then lines[#lines] = nil end

local top, side = 1, 0
local function clamp()
  local maxTop = math.max(1, #lines - ROWS_TEXT + 1)
  if top > maxTop then top = maxTop end
  if top < 1 then top = 1 end
  if side < 0 then side = 0 end
end

local function draw()
  term.clear()
  for row = 0, ROWS_TEXT - 1 do
    local line = lines[top + row]
    if line then term.text(0, row, line:sub(side + 1, side + COLS), "text") end
  end
  local last = math.min(top + ROWS_TEXT - 1, #lines)
  term.text(0, 15, string.format("%s  %d-%d/%d  q quit", path:sub(-14), top, last, #lines), "dim")
  term.flush()
end

term.fullscreen(true)
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true
    elseif k == "down" then top = top + 1
    elseif k == "up" then top = top - 1
    elseif k == "pagedown" or k == " " then top = top + ROWS_TEXT - 1
    elseif k == "pageup" then top = top - (ROWS_TEXT - 1)
    elseif k == "right" then side = side + 8
    elseif k == "left" then side = side - 8
    elseif k == "g" then top = 1
    elseif k == "G" then top = #lines
    end
    clamp()
    k = key.poll()
  end
  if quit then break end
  draw()
  sys.sleep(50)
end
term.fullscreen(false)
