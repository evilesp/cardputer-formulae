#!lua
-- httping: measures how long an HTTP request takes, like httping 4.x.
-- usage: httping [-c count] [-i interval] [-g url] [-s] [-q] [-h] [-V] [URL [COUNT]]

local HELP = [[
usage: httping [-c count] [-i interval] [-t timeout] [-g url] [-s] [-q]
               [-G] [-h hostname] [-p port] [-l] [-V]
-g url         url to ping (e.g. http://example.com/)
-h hostname    hostname to ping
-p portnr      portnumber to ping (default 80)
-c count       how many times to connect (default 4 here, endless on a PC)
-i interval    delay between each connect in seconds (default 1.0)
-t timeout     timeout in seconds (default 30)
-s             show statuscodes
-G             do a GET request instead of HEAD (here every request is a GET)
-q             quiet, only returncode
-l             connect using SSL
-V             show the version]]

local url, host, port, count, interval, showStatus, quiet, ssl = nil, nil, nil, nil, 1.0, false, false, false
local rest = {}
local i = 1
while arg[i] do
  local a = arg[i]
  local function val()
    i = i + 1
    return arg[i]
  end
  if a == "-g" then url = val()
  elseif a == "-h" then
    if arg[i + 1] then host = val() else print(HELP) return end
  elseif a == "-p" then port = tonumber(val())
  elseif a == "-c" then count = tonumber(val())
  elseif a == "-i" then interval = tonumber(val()) or 1.0
  elseif a == "-t" then val()
  elseif a == "-s" then showStatus = true
  elseif a == "-q" then quiet = true
  elseif a == "-l" then ssl = true
  elseif a == "-G" or a == "-f" or a == "-b" or a == "-X" or a == "-Z" then
    -- accepted, no effect here
  elseif a == "--help" then print(HELP) return
  elseif a == "-V" or a == "--version" then
    print("HTTPing v4.3.0, (C) 2003-2025 folkert@vanheusden.com")
    return
  elseif a:sub(1, 1) == "-" and #a > 1 then
    io.stderr:write("httping: invalid option -- '" .. a:sub(2) .. "'\n")
    io.stderr:write(HELP .. "\n")
    os.exit(2)
  else rest[#rest + 1] = a end
  i = i + 1
end
-- the old form: httping URL [COUNT]
url = url or rest[1]
count = count or tonumber(rest[2]) or 4

if not url and host then url = (ssl and "https://" or "http://") .. host .. (port and (":" .. port) or "") .. "/" end
if not url then
  io.stderr:write("httping: No hostname/getrequest given\n")
  os.exit(2)
end
if not url:find("^%a+://") then url = (ssl and "https://" or "http://") .. url end

local scheme, hostport, path = url:match("^(%a+)://([^/]*)(.*)$")
if path == "" then path = "/" end
local h, p = hostport:match("^(.-):(%d+)$")
if not h then h, p = hostport, (scheme == "https" and "443" or "80") end
p = tonumber(p)

if not net.connected() then
  io.stderr:write("httping: " .. h .. ": Network is unreachable\n")
  os.exit(2)
end

if not quiet then print("PING " .. h .. ":" .. p .. " (" .. path .. "):") end

local best, worst, total, ok, tries = nil, 0, 0, 0, 0
local t00 = sys.millis()
for seq = 0, count - 1 do
  tries = tries + 1
  local t0 = sys.millis()
  local status, body = net.get(url, 16)
  local ms = sys.millis() - t0
  if status then
    ok = ok + 1
    total = total + ms
    if best == nil or ms < best then best = ms end
    if ms > worst then worst = ms end
    if not quiet then
      print(string.format("connected to %s:%d (%d bytes), seq=%d time=%7.2f ms%s", h, p, #body, seq, ms,
        showStatus and (" " .. status) or ""))
    end
  elseif not quiet then
    print(string.format("%s:%d: %s", h, p, tostring(body)))
  end
  if seq < count - 1 then sys.sleep(math.floor(interval * 1000)) end
end

if not quiet then
  print("--- " .. url .. " ping statistics ---")
  print(string.format("%d connects, %d ok, %.2f%% failed, time %dms", tries, ok, (tries - ok) * 100 / tries,
    sys.millis() - t00))
  if ok > 0 then
    print(string.format("round-trip min/avg/max = %.1f/%.1f/%.1f ms", best, total / ok, worst))
  end
end
os.exit(ok > 0 and 0 or 2)
