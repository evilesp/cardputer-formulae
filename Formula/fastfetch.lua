#!lua
-- fastfetch: what fastfetch prints on Arch Linux: the Arch logo, user@host, then OS, Host, Kernel ... and the colour blocks.
-- fastfetch [-l|--logo arch|arch_small|none]   (the small logo is the default: the screen is only 57 columns wide)
-- The same script is neofetch (the layout of neofetch is used when NEOFETCH is true).
local NEOFETCH = false

local BIG = {
  "                  -`                 ",
  "                 .o+`                ",
  "                `ooo/                ",
  "               `+oooo:               ",
  "              `+oooooo:              ",
  "              -+oooooo+:             ",
  "            `/:-:++oooo+:            ",
  "           `/++++/+++++++:           ",
  "          `/++++++++++++++:          ",
  "         `/+++ooooooooooooo/`        ",
  "        ./ooosssso++osssssso+`       ",
  "       .oossssso-````/ossssss+`      ",
  "      -osssssso.      :ssssssso.     ",
  "     :osssssss/        osssso+++.    ",
  "    /ossssssss/        +ssssooo/-    ",
  "  `/ossssso+/:-        -:/+osssso+-  ",
  " `+sso+:-`                 `.-/+oso: ",
  "`++:.                           `-/+/",
  ".`                                 `/",
}
local SMALL = {
  "      /\\     ",
  "     /  \\    ",
  "    /\\   \\   ",
  "   /      \\  ",
  "  /   ,,   \\ ",
  " /   |  |  -\\",
  "/_-''    ''-_\\",
}

-- ---- what the options ask for ----
local logoName = "arch_small"
do
  local i = 1
  while arg and i <= #arg do
    local a = arg[i]
    if a == "-l" or a == "--logo" or a == "--ascii_distro" then
      logoName = arg[i + 1] or logoName
      i = i + 1
    elseif a:sub(1, 7) == "--logo=" then
      logoName = a:sub(8)
    end
    i = i + 1
  end
end
logoName = logoName:lower():gsub("_old", "")
local logo = (logoName == "arch" or logoName == "arch_linux") and BIG
  or (logoName == "none" or logoName == "off") and {} or SMALL
local cols = term.size()
local logoWidth = 0
for _, l in ipairs(logo) do logoWidth = math.max(logoWidth, #l) end
for i, l in ipairs(logo) do logo[i] = l .. string.rep(" ", logoWidth - #l) end
-- a big logo that does not leave room for the text is printed above it
local stacked = logo == BIG and logoWidth + 3 + 36 > cols

-- ---- reading the system ----
local function read(path)
  local ok, text = pcall(fs.read, path)
  if ok and type(text) == "string" and text ~= "" then return text end
end

local function run(line, pattern, default)
  local ok, out, status = pcall(sys.shell, line)
  if ok and type(out) == "string" and status == 0 then
    local v = out:match(pattern)
    if v then return v end
  end
  return default
end

local function iec(bytes)
  if bytes >= 1073741824 then return string.format("%.2f GiB", bytes / 1073741824) end
  if bytes >= 1048576 then return string.format("%.2f MiB", bytes / 1048576) end
  return string.format("%.2f KiB", bytes / 1024)
end

-- neofetch writes 1.2G and 512M
local function short(bytes)
  local t = iec(bytes):gsub(" GiB", "G"):gsub(" MiB", "M"):gsub(" KiB", "K")
  return t
end

local function uptimeText()
  local s = math.floor(sys.uptime())
  local d, h, m = s // 86400, (s // 3600) % 24, (s // 60) % 60
  local parts = {}
  if d > 0 then parts[#parts + 1] = d .. (d == 1 and " day" or " days") end
  if h > 0 then parts[#parts + 1] = h .. (h == 1 and " hour" or " hours") end
  if m > 0 then parts[#parts + 1] = m .. (m == 1 and " min" or " mins") end
  if #parts == 0 then parts[1] = s .. (s == 1 and " sec" or " secs") end
  return table.concat(parts, ", ")
end

local user, host = sys.user(), sys.hostname()
local model, cores, mhz = sys.chip()
local free, total = sys.heap()  -- KB
local pct, mv, charging = sys.battery()
local sdTotal, sdUsed = sys.sd()

local osRelease = read("/etc/os-release") or ""
local osName = osRelease:match('PRETTY_NAME="?([^"\n]*)') or "Arch ESP"
local machine = run("uname -m", "^([%w_]+)%s*$", "riscv32")
local kernel = run("uname -r", "^(%d[%w%.%-_+]*)%s*$", "6.12.1-arch1-1-esp")
-- pacman -Qq prints one package a line
local pkgOut = run("pacman -Qq", "^(.*)$", nil)
local packages = 0
if pkgOut then for _ in pkgOut:gmatch("[^\n]+") do packages = packages + 1 end end
if packages == 0 then packages = #(fs.list("/var/lib/pacman/local") or {}) end
local function env(name)
  local ok, v = pcall(sys.env, name)
  if ok then return v end
end
local bashVersion = env("BASH_VERSION") or "5.2.37"
bashVersion = bashVersion:match("^[%d%.]+") or "5.2.37"
local locale = (read("/etc/locale.conf") or ""):match("LANG=([^\n]+)") or env("LANG") or "C.UTF-8"

local info = {}
local function add(key, value) info[#info + 1] = { key = key, value = value } end

if NEOFETCH then
  local memUsed = (total - free) // 1024
  add("OS", osName .. " " .. machine)
  add("Host", sys.board())
  add("Kernel", kernel)
  add("Uptime", uptimeText())
  add("Packages", packages .. " (pacman)")
  add("Shell", "bash " .. bashVersion)
  add("Resolution", "800x480")
  add("Terminal", "tty1")
  add("CPU", string.format("%s (%d) @ %.3fGHz", model, cores, mhz / 1000))
  add("Memory", string.format("%dMiB / %dMiB", memUsed, total // 1024))
  -- neofetch shows no disk line unless the user turns it on in its config
else
  add("OS", osName .. " " .. machine)
  add("Host", sys.board())
  add("Kernel", "Linux " .. kernel)
  add("Uptime", uptimeText())
  add("Packages", packages .. " (pacman)")
  add("Shell", "bash " .. bashVersion)
  add("Display (DSI-1)", "800x480 @ 60 Hz")
  add("Terminal", "tty1")
  add("CPU", string.format("%s (%d) @ %.2f GHz", model, cores, mhz / 1000))
  local used = (total - free) * 1024
  add("Memory", string.format("%s / %s (%d%%)", iec(used), iec(total * 1024), used * 100 // math.max(total * 1024, 1)))
  add("Swap", "Disabled")
  if sdTotal then
    add("Disk (/)", string.format("%s / %s (%d%%) - vfat", iec(sdUsed), iec(sdTotal), sdUsed * 100 // sdTotal))
  end
  if net.connected() then
    local addr = run("ip -4 addr show wlan0", "inet (%d+%.%d+%.%d+%.%d+/%d+)", net.ip() .. "/24")
    add("Local IP (wlan0)", addr)
  end
  if mv and mv > 2500 then
    add("Battery (" .. sys.board():match("^%S+") .. ")", string.format("%d%% [%s]", pct, charging and "Charging" or "Discharging"))
  end
  add("Locale", locale)
end

-- ---- drawing ----
local keyColor = "blue"
local left = stacked and 0 or logoWidth + 3
local rows = {}  -- each row: a list of {text, colour}
local title = { { user, keyColor }, { "@", "text" }, { host, keyColor } }
rows[#rows + 1] = title
rows[#rows + 1] = { { string.rep("-", #user + #host + 1), "text" } }
for _, e in ipairs(info) do
  rows[#rows + 1] = { { e.key, keyColor }, { ": ", "text" }, { e.value, "text" } }
end
rows[#rows + 1] = { { "", "text" } }
local blocks1, blocks2 = {}, {}
for _, c in ipairs({ "dim", "red", "green", "yellow", "blue", "magenta", "cyan", "white" }) do
  blocks1[#blocks1 + 1] = { "   ", "inverse-" .. c }
end
for _, c in ipairs({ "text", "error", "greendim", "warn", "blue", "magenta", "cyan", "white" }) do
  blocks2[#blocks2 + 1] = { "   ", "inverse-" .. c }
end
rows[#rows + 1] = blocks1
rows[#rows + 1] = blocks2

-- a row that is longer than the screen continues on the next line, under the text
local function emit(row, pad, written)
  if not written then term.write(string.rep(" ", pad)) end
  local room = cols - 1 - pad
  for _, part in ipairs(row) do
    local text = part[1]
    while #text > room do
      term.write(text:sub(1, room), part[2])
      term.print("", "text")
      term.write(string.rep(" ", pad))
      text = text:sub(room + 1)
    end
    term.write(text, part[2])
    room = room - #text
  end
  term.print("", "text")
end

if stacked then
  for _, l in ipairs(logo) do term.print(l, keyColor) end
  term.print("", "text")
  for _, row in ipairs(rows) do emit(row, 0) end
else
  local n = math.max(#logo, #rows)
  for i = 1, n do
    local l = logo[i]
    if l then term.write(l .. "   ", keyColor) else term.write(string.rep(" ", left)) end
    emit(rows[i] or { { "", "text" } }, left, true)
  end
end
