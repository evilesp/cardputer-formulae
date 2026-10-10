#!lua
-- fastfetch: a short summary of the device, next to a small Cardputer logo.

local LOGO = {
  "  .-----------.  ",
  " | .---------. | ",
  " | |  >_     | | ",
  " | |         | | ",
  " | '---------' | ",
  " |  [o]     o  | ",
  "  '-----------'  ",
}
local LOGO_WIDTH = 18

local function uptimeText()
  local s = math.floor(sys.uptime())
  return string.format("%dh %02dm %02ds", s // 3600, (s // 60) % 60, s % 60)
end

local function bytesText(n)
  if n >= 1000000000 then return string.format("%.1f GB", n / 1000000000) end
  if n >= 1000000 then return string.format("%.1f MB", n / 1000000) end
  return string.format("%d KB", n // 1000)
end

local user, host = sys.user(), sys.hostname()
local model, cores, mhz = sys.chip()
local free, total, psram = sys.heap()
local pct, mv, charging = sys.battery()
local sdTotal, sdUsed = sys.sd()
local packages = fs.list("/usr/local/bin") or {}

local info = {
  { "", user .. "@" .. host, "white" },
  { "", string.rep("-", #user + #host + 1), "dim" },
  { "OS", "Cardputer Linux " .. sys.version() },
  { "Host", sys.board() },
  { "CPU", string.format("%s, %d cores @ %d MHz", model, cores, mhz) },
  { "Uptime", uptimeText() },
  { "Memory", string.format("%d KB free of %d KB", free, total)
      .. (psram > 0 and string.format(" (+ %d KB PSRAM)", psram) or "") },
  { "Battery", string.format("%d%% (%d mV%s)", pct, mv, charging and ", charging" or "") },
  { "SD card", sdTotal and (bytesText(sdUsed) .. " used of " .. bytesText(sdTotal)) or "not mounted" },
  { "Network", net.connected() and (net.ssid() .. " (" .. net.ip() .. ")") or "offline" },
  { "Packages", #packages .. " in /usr/local/bin" },
}

local rows = math.max(#LOGO, #info)
for i = 1, rows do
  local logo = LOGO[i] or string.rep(" ", LOGO_WIDTH)
  term.write(logo .. "  ", "magenta")
  local line = info[i]
  if line then
    if line[1] == "" then
      term.print(line[2], line[3])
    else
      term.write(string.format("%-10s", line[1] .. ":"), "cyan")
      term.print(line[2], "text")
    end
  else
    term.print("", "text")
  end
end
