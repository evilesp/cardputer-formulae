#!lua
-- ui: a small graphical toolkit for apps, on top of the gfx module (pixel graphics on the 240x135 screen). A driver is
-- not a program: brew installs it into /usr/local/lib/drivers, and an app loads it with driver.load("ui"). Needs firmware
-- v0.1.0.13(beta) or newer (the gfx module).
--
--   local ui = driver.load("ui")
--   ui.open()                                  -- takes the screen (ui.close() or the end of the app gives it back)
--   gfx.clear(ui.theme.bg)
--   ui.panel(10, 10, 120, 60, "Settings")      -- a window with a title bar
--   ui.label(16, 28, "Volume", ui.theme.text)
--   ui.bar(16, 40, 100, 10, 7, 10)             -- a progress bar: value 7 of 10
--   ui.button(16, 54, 50, 12, "OK", "focus")   -- a button: "normal", "focus" or "disabled"
--   gfx.flush()
--
-- Drawing is immediate: you draw every frame, then gfx.flush(). The modal helpers draw and wait for keys themselves:
--   ui.choose("Menu", {"Start", "Quit"})       -- returns the number chosen, or nil when the user backs out
--   ui.message("Done", {"All saved."})         -- a box that waits for a key
--   ui.prompt("Name", "player", 12)            -- a line of typed text, or nil
-- Keys need no Fn: w/s or the arrows move, enter or space chooses, backspace or ctrl-q backs out.
-- Colors are 0xRRGGBB numbers. Run it as a script with --selftest to check the helpers.

local ui = {}

ui.theme = {
  bg = 0x10131c, panel = 0x1c2233, light = 0x2a3350, border = 0x5870b0, title = 0x34447c,
  text = 0xe8ecf4, dim = 0x8a94aa, accent = 0x3cc878, warn = 0xe8b43c, danger = 0xe05050,
}

-- ---- colors ----

local function clamp(v, lo, hi)
  return v < lo and lo or (v > hi and hi or v)
end

function ui.rgb(r, g, b)
  return (clamp(math.floor(r), 0, 255) << 16) | (clamp(math.floor(g), 0, 255) << 8) | clamp(math.floor(b), 0, 255)
end

-- the color made brighter (f above 1) or darker (f below 1)
function ui.shade(c, f)
  return ui.rgb(((c >> 16) & 255) * f, ((c >> 8) & 255) * f, (c & 255) * f)
end

-- t = 0 is color a, t = 1 is color b
function ui.mix(a, b, t)
  local ar, ag, ab = (a >> 16) & 255, (a >> 8) & 255, a & 255
  local br, bg, bb = (b >> 16) & 255, (b >> 8) & 255, b & 255
  return ui.rgb(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end

-- ---- the screen ----

-- Takes the screen. Returns its width and height, or nil and the reason (an old firmware has no gfx module).
function ui.open()
  if not gfx then return nil, "no graphics: update the firmware to v0.1.0.13(beta) or newer" end
  local w, h, depth = gfx.open()
  if not w then return nil, h end
  ui.w, ui.h, ui.depth = w, h, depth  -- depth is 16 bits, or 8 when the memory is short (firmware v0.1.0.14): coarser colours
  return w, h
end

function ui.close()
  if gfx then gfx.close() end
end

function ui.textWidth(s, size)
  return #s * 6 * (size or 1)
end

-- ---- widgets ----

-- A window: a filled box with a border, and a title bar when there is a title. The room inside starts 14 pixels down.
function ui.panel(x, y, w, h, title)
  local t = ui.theme
  gfx.fill(x, y, w, h, t.panel)
  gfx.rect(x, y, w, h, t.border)
  if title then
    gfx.fill(x + 1, y + 1, w - 2, 11, t.title)
    gfx.text(x + 4, y + 2, title, t.text, 1)
    gfx.hline(x + 1, x + w - 2, y + 12, t.border)
  end
end

function ui.label(x, y, text, color, size)
  gfx.text(x, y, text, color or ui.theme.text, size or 1)
end

-- Text centred between x0 and x1 (the whole width by default)
function ui.center(y, text, color, size, x0, x1)
  x0, x1 = x0 or 0, x1 or ui.w or 240
  size = size or 1
  gfx.text(x0 + (x1 - x0 - ui.textWidth(text, size)) // 2, y, text, color or ui.theme.text, size)
end

-- A button; state is "normal", "focus" (the chosen one) or "disabled"
function ui.button(x, y, w, h, text, state)
  local t = ui.theme
  local fill = state == "focus" and t.accent or t.light
  local ink = state == "disabled" and t.dim or (state == "focus" and t.bg or t.text)
  gfx.fill(x, y, w, h, fill)
  gfx.rect(x, y, w, h, state == "focus" and t.text or t.border)
  gfx.text(x + (w - ui.textWidth(text)) // 2, y + (h - 8) // 2, text, ink, 1)
end

-- A bar that is filled to value / max. text, if given, is written in the middle.
function ui.bar(x, y, w, h, value, max, color, text)
  local t = ui.theme
  gfx.fill(x, y, w, h, t.bg)
  local part = max > 0 and clamp(value / max, 0, 1) or 0
  local n = math.floor((w - 2) * part)
  if n > 0 then gfx.fill(x + 1, y + 1, n, h - 2, color or t.accent) end
  gfx.rect(x, y, w, h, t.border)
  if text then gfx.text(x + (w - ui.textWidth(text)) // 2, y + (h - 8) // 2, text, t.text, 1) end
end

-- A column of choices, the chosen one highlighted. Returns the y below the last row.
function ui.list(x, y, w, items, selected, rowH)
  local t = ui.theme
  rowH = rowH or 12
  for i, item in ipairs(items) do
    local top = y + (i - 1) * rowH
    if i == selected then
      gfx.fill(x, top, w, rowH - 1, t.accent)
      gfx.text(x + 4, top + (rowH - 9) // 2, item, t.bg, 1)
    else
      gfx.text(x + 4, top + (rowH - 9) // 2, item, t.text, 1)
    end
  end
  return y + #items * rowH
end

-- A box in the middle of the screen with a title, lines of text and a row of buttons; selected is the button in focus
function ui.dialog(title, lines, buttons, selected)
  local t = ui.theme
  buttons = buttons or {}
  local wide = ui.textWidth(title) + 16
  for _, line in ipairs(lines) do wide = math.max(wide, ui.textWidth(line) + 16) end
  local row = 0
  for _, b in ipairs(buttons) do row = row + ui.textWidth(b) + 20 end
  wide = math.min(math.max(wide, row + 8, 100), (ui.w or 240) - 8)
  local high = 18 + #lines * 10 + (#buttons > 0 and 22 or 4)
  local x, y = ((ui.w or 240) - wide) // 2, ((ui.h or 135) - high) // 2
  ui.panel(x, y, wide, high, title)
  for i, line in ipairs(lines) do gfx.text(x + 8, y + 18 + (i - 1) * 10, line, t.text, 1) end
  local bx = x + (wide - row + 4) // 2
  for i, b in ipairs(buttons) do
    local bw = ui.textWidth(b) + 16
    ui.button(bx, y + high - 18, bw, 13, b, i == selected and "focus" or "normal")
    bx = bx + bw + 4
  end
end

-- ---- keys and modal helpers ----

-- A key as one of "up", "down", "left", "right", "ok", "back", or nil. Letters work, so no Fn is needed.
function ui.keyAction(k)
  if k == "up" or k == "w" then return "up" end
  if k == "down" or k == "s" then return "down" end
  if k == "left" or k == "a" then return "left" end
  if k == "right" or k == "d" then return "right" end
  if k == "enter" or k == " " then return "ok" end
  if k == "backspace" or k == "ctrl-q" then return "back" end
  return nil
end

-- draws one frame: clears to the background, runs draw(), shows it
function ui.frame(draw)
  gfx.clear(ui.theme.bg)
  draw()
  gfx.flush()
end

-- A menu in a window. Returns the number chosen, or nil when the user backs out. opts.background (a function) draws
-- behind the window each frame; opts.selected is the first choice; opts.y puts the window higher or lower.
function ui.choose(title, items, opts)
  opts = opts or {}
  local sel = opts.selected or 1
  local wide = ui.textWidth(title) + 16
  for _, item in ipairs(items) do wide = math.max(wide, ui.textWidth(item) + 16) end
  wide = math.max(wide, 90)
  local high = 18 + #items * 12 + 4
  local x = ((ui.w or 240) - wide) // 2
  local y = opts.y or ((ui.h or 135) - high) // 2
  while true do
    gfx.clear(ui.theme.bg)
    if opts.background then opts.background() end
    ui.panel(x, y, wide, high, title)
    ui.list(x + 2, y + 15, wide - 4, items, sel)
    gfx.flush()
    local k = key.poll()
    while k do
      local a = ui.keyAction(k)
      if a == "up" then
        sel = sel > 1 and sel - 1 or #items
      elseif a == "down" then
        sel = sel < #items and sel + 1 or 1
      elseif a == "ok" then
        return sel
      elseif a == "back" then
        return nil
      end
      k = key.poll()
    end
    sys.sleep(25)
  end
end

-- A box with lines of text and an OK button; waits for enter, space or backspace. opts.background draws behind it.
function ui.message(title, lines, opts)
  opts = opts or {}
  while true do
    gfx.clear(ui.theme.bg)
    if opts.background then opts.background() end
    ui.dialog(title, lines, { "OK" }, 1)
    gfx.flush()
    local k = key.poll()
    while k do
      local a = ui.keyAction(k)
      if a == "ok" or a == "back" then return end
      k = key.poll()
    end
    sys.sleep(25)
  end
end

-- A line of text typed by the user: enter accepts it, ctrl-q cancels (nil). Every letter goes into the text.
function ui.prompt(title, initial, maxLen)
  local text = initial or ""
  maxLen = maxLen or 24
  while true do
    gfx.clear(ui.theme.bg)
    ui.dialog(title, { text .. "_" }, { "enter: OK" }, 1)
    gfx.flush()
    local k = key.poll()
    while k do
      if k == "enter" then
        return text
      elseif k == "ctrl-q" then
        return nil
      elseif k == "backspace" then
        text = text:sub(1, -2)
      elseif #k == 1 and k:byte() >= 32 and k:byte() < 127 and #text < maxLen then
        text = text .. k
      end
      k = key.poll()
    end
    sys.sleep(25)
  end
end

if arg and arg[1] == "--selftest" then
  local checks = 0
  local function expect(cond, what)
    checks = checks + 1
    if not cond then error("check " .. checks .. ": " .. what) end
  end
  expect(ui.rgb(255, 128, 0) == 0xFF8000, "rgb packs the channels")
  expect(ui.rgb(300, -5, 1.9) == 0xFF0001, "rgb clamps")
  expect(ui.shade(0xFF8040, 0.5) == 0x7F4020, "shade halves the channels")
  expect(ui.shade(0x808080, 4) == 0xFFFFFF, "shade stops at white")
  expect(ui.mix(0x000000, 0xFF8000, 0.5) == 0x7F4000, "mix halfway")
  expect(ui.mix(0x102030, 0x405060, 0) == 0x102030 and ui.mix(0x102030, 0x405060, 1) == 0x405060, "mix ends")
  expect(ui.textWidth("abcd") == 24 and ui.textWidth("ab", 2) == 24, "text width")
  expect(ui.keyAction("w") == "up" and ui.keyAction("down") == "down" and ui.keyAction("d") == "right", "keys move")
  expect(ui.keyAction("enter") == "ok" and ui.keyAction(" ") == "ok" and ui.keyAction("ctrl-q") == "back", "keys choose")
  expect(ui.keyAction("x") == nil, "other keys are nothing")
  local w, h = ui.open()
  expect(w == 240 and h == 135, "the screen is 240 x 135")
  ui.frame(function()
    ui.panel(10, 10, 120, 60, "Settings")
    ui.label(16, 28, "Volume", ui.theme.text)
    ui.bar(16, 40, 100, 10, 7, 10, nil, "70%")
    ui.button(16, 54, 50, 12, "OK", "focus")
    ui.list(140, 10, 90, { "One", "Two" }, 2)
    ui.center(100, "centred", ui.theme.warn, 2)
    ui.dialog("Quit?", { "Really?" }, { "Yes", "No" }, 2)
  end)
  ui.close()
  print(string.format("selftest ok (%d checks)", checks))
end

-- (no return above: when doom loads this driver with --selftest in its arguments, the module must still come back)
return ui
