#!lua
-- gpsview: shows the position from a GPS module on a UART. The module's TX goes to the pin RX (given first), and the
-- module's RX to the pin TX (-1 when the module is not wired back: it only has to send). Needs the gps driver:
-- brew install gps. Needs firmware v0.1.0.10(beta) or newer.
--   gpsview RX TX [BAUD]          e.g. gpsview 1 2      (BAUD 9600 by default)
-- Free pins on the Cardputer ADV: 1-7, 13, 15-18, 44, 47, 48. The GPS needs a view of the sky: a first fix can take a
-- few minutes outdoors. q quits, and the port is closed when the app ends.

local USAGE = "usage: gpsview RX TX [BAUD]   e.g. gpsview 1 2   (TX -1 if the module is not wired back)"

if not uart or not driver then
  print("gpsview: this firmware cannot open a UART, update to v0.1.0.10(beta) or newer")
  return
end

local rx, tx = tonumber(arg[1] or ""), tonumber(arg[2] or "")
local baud = tonumber(arg[3] or "") or 9600
if not rx or not tx or rx ~= math.floor(rx) or tx ~= math.floor(tx) then
  print(USAGE)
  return
end

local gps, gerr = driver.load("gps")
if not gps then
  print("gpsview: " .. tostring(gerr))
  return
end
local port, perr = uart.open{ rx = rx, tx = tx, baud = math.floor(baud) }
if not port then
  print("gpsview: " .. tostring(perr))
  return
end

local COLS, ROWS = term.size()

local function draw(fix)
  term.clear()
  term.text(0, 0, "GPS position", "green")
  if fix.lat then
    term.text(0, 2, string.format("lat %.5f", fix.lat), "white")
    term.text(0, 3, string.format("lon %.5f", fix.lon), "white")
  else
    term.text(0, 2, "no position yet (outdoors, 1-5 min)", "warn")
  end
  term.text(0, 5, "sats " .. tostring(fix.sats or "-") .. "   quality " .. tostring(fix.quality or "-"), "text")
  term.text(0, 6, "alt " .. (fix.alt and string.format("%.1f m", fix.alt) or "-"), "text")
  term.text(0, 7, "speed " .. (fix.speed and string.format("%.1f km/h", fix.speed) or "-"), "text")
  term.text(0, 8, "time (UTC) " .. (fix.time or "-"), "text")
  term.text(0, ROWS - 1, "q quits", "dim")
  term.flush()
end

local reader = gps.new(port)

local function loop()
  while true do
    local fix = reader:poll()
    local k = key.poll()
    while k do
      if k == "q" then return end
      k = key.poll()
    end
    draw(fix)
    sys.sleep(200)
  end
end

term.fullscreen(true)
local ok, err = pcall(loop)
port:close()  -- also after Ctrl+C, which stops the loop with an error
term.fullscreen(false)
if not ok and not tostring(err):find("interrupted", 1, true) then
  print("gpsview: " .. tostring(err))
end
