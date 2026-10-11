#!lua
-- show: shows JPEG and PNG pictures from the SD card on the screen, fitted to it. Needs firmware v0.1.0.10(beta).
--   show FILE...     (wildcards work: show /home/user/photos/*.jpg)
-- Right, space or Enter shows the next picture, left or b the previous one, q quits.
-- A picture bigger than the screen is scaled down to fit; a smaller one is shown at its own size.

local COLS, ROWS = term.size()
local AREA_W = COLS * 6        -- the screen in pixels: 6 x 8 for each character cell
local AREA_H = (ROWS - 1) * 8  -- the last row is for the file name

if #arg == 0 then
  print("usage: show FILE...   (JPEG or PNG; right or space next, left or b back, q quit)")
  return
end
if not term.imageSize then
  print("show: this firmware cannot show pictures from the SD card, update to v0.1.0.10(beta) or newer")
  return
end

-- Where a picture goes on the screen, and its scale. False with the reason when it is not a picture.
local function layout(path)
  local w, h = term.imageSize(path)  -- size and height, or nil and the reason
  if not w then return nil, h end
  local scale = math.min(1.0, AREA_W / w, AREA_H / h)
  local drawW, drawH = math.floor(w * scale), math.floor(h * scale)
  return { x = (AREA_W - drawW) // 2, y = (AREA_H - drawH) // 2, scale = scale }
end

local function nameOf(path)
  return path:match("([^/]+)$") or path
end

local files = arg
local index = 1

local function draw()
  local path = files[index]
  term.clear()
  term.text(0, ROWS - 1, string.format("%d/%d  %s", index, #files, nameOf(path)):sub(1, COLS), "dim")
  term.flush()
  local pic, err = layout(path)
  if not pic then
    term.text(0, 2, "cannot show " .. nameOf(path):sub(1, COLS - 12), "warn")
    term.text(0, 3, tostring(err):sub(1, COLS), "warn")
    term.flush()
    return
  end
  -- the picture is drawn after the flush, on top of the screen (as duckduckgo does)
  local ok, derr = term.image(path, pic.x, pic.y, pic.scale)
  if not ok then
    term.text(0, 2, tostring(derr):sub(1, COLS), "warn")
    term.flush()
  end
end

local function handleKey(k)
  if k == "q" then return "quit" end
  if (k == "right" or k == " " or k == "enter" or k == "down") and index < #files then
    index = index + 1
    return "draw"
  end
  if (k == "left" or k == "up" or k == "b") and index > 1 then
    index = index - 1
    return "draw"
  end
end

---------------------------------------------------------------- self test

local function selftest()
  local checks = 0
  local function expect(got, want)
    checks = checks + 1
    if got ~= want then error(string.format("check %d: got %q, want %q", checks, tostring(got), tostring(want))) end
  end
  expect(nameOf("/home/user/photos/cat.jpg"), "cat.jpg")
  expect(nameOf("dog.png"), "dog.png")
  print(string.format("selftest ok (%d checks)", checks))
end

if arg[1] == "--selftest" then
  selftest()
  return
end

---------------------------------------------------------------- main

term.fullscreen(true)
local dirty = true
local quit = false
while not quit do
  local k = key.poll()
  while k do
    dirty = true
    if handleKey(k) == "quit" then
      quit = true
      break
    end
    k = key.poll()
  end
  if quit then break end
  if dirty then
    draw()
    dirty = false
  else
    term.flush()  -- nothing changed: the flush only keeps the input and the screen alive
  end
  sys.sleep(50)
end
term.fullscreen(false)
