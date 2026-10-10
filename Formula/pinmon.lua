#!lua
-- pinmon: shows the level of every GPIO pin this board exposes (and the voltage on ADC pins).
-- Connect a wire to a pin to see it change. q quits.

local PINS = gpio.pins()

local function row(y, pin)
  local level = gpio.read(pin)
  term.text(0, y, string.format("G%-3d", pin), "cyan")
  if level == 1 then
    term.text(5, y, "HIGH", "green")
  else
    term.text(5, y, "low ", "dim")
  end
  term.text(10, y, string.rep(level == 1 and "#" or ".", 12), level == 1 and "green" or "dim")
  if pin >= 1 and pin <= 10 then
    local mv = gpio.adc(pin)
    term.text(24, y, string.format("%4d mV", mv), "text")
  end
end

term.fullscreen(true)
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true end
    k = key.poll()
  end
  if quit then break end

  term.clear()
  term.text(0, 0, "pinmon  (q quits)", "white")
  term.text(0, 1, "pin  level        analog", "dim")
  for i, pin in ipairs(PINS) do
    if i + 1 < 16 then row(i + 1, pin) end
  end
  term.flush()
  sys.sleep(250)
end
term.fullscreen(false)
