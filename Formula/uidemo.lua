#!lua
-- uidemo: shows what the ui library draws, with pixel graphics: a window, labels, bars, buttons, a menu and a message
-- box. a and d move between the buttons, enter presses one, ctrl-q quits. Needs the ui package (brew install ui) and
-- firmware v0.1.0.13(beta) or newer. It is also a short example of an app with a graphical interface: read the code.

if not gfx or not driver then
  print("uidemo needs the graphics of firmware v0.1.0.13(beta): update with SystemUpdateBeta")
  return
end
local ui, err = driver.load("ui")
if not ui then
  print("uidemo: " .. tostring(err))
  return
end

local BUTTONS = { "Menu", "Message", "Quit" }
local focus, picked, started = 1, "nothing yet", sys.millis()

local function draw()
  local t = ui.theme
  local seconds = (sys.millis() - started) / 1000
  ui.panel(6, 6, 228, 123, "ui demo")
  ui.label(14, 24, "labels, in any color and size", t.text)
  ui.label(14, 36, "big", t.warn, 2)
  ui.label(14, 56, "bars:", t.dim)
  ui.bar(50, 54, 120, 10, 50 + 50 * math.sin(seconds), 100, t.accent)
  ui.bar(50, 68, 120, 10, 50 + 50 * math.sin(seconds * 1.7), 100, t.warn, "text inside")
  ui.bar(50, 82, 120, 10, 50 + 50 * math.sin(seconds * 2.3), 100, t.danger)
  ui.label(14, 98, "you picked: " .. picked, t.text)
  local x = 14
  for i, name in ipairs(BUTTONS) do
    local w = ui.textWidth(name) + 16
    ui.button(x, 110, w, 14, name, i == focus and "focus" or "normal")
    x = x + w + 6
  end
  ui.label(150, 112, "a/d  enter", t.dim)
end

local function run()
  while true do
    ui.frame(draw)
    local k = key.poll()
    while k do
      local a = ui.keyAction(k)
      if a == "left" then
        focus = focus > 1 and focus - 1 or #BUTTONS
      elseif a == "right" then
        focus = focus < #BUTTONS and focus + 1 or 1
      elseif a == "back" then
        return
      elseif a == "ok" then
        if focus == 1 then
          local c = ui.choose("Pick one", { "Red", "Green", "Blue" }, { background = draw })
          if c then picked = ({ "red", "green", "blue" })[c] end
        elseif focus == 2 then
          ui.message("Hello", { "This is a message box.", "Press enter to close it." }, { background = draw })
        else
          return
        end
      end
      k = key.poll()
    end
    sys.sleep(20)
  end
end

local w, h = ui.open()
if not w then
  print("uidemo: " .. tostring(h))
  return
end
local ok, problem = pcall(run)
ui.close()  -- also after Ctrl+C
if not ok and not tostring(problem):find("interrupted", 1, true) then print("uidemo: " .. tostring(problem)) end
