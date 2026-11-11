#!lua
-- speedtest-cli: latency, download and upload speed, in the output style of speedtest-cli 2.1.
-- The measurements use the Cloudflare speed test servers.
-- usage: speedtest-cli [-h] [--no-download] [--no-upload] [--single] [--bytes] [--share]
--                      [--simple] [--csv] [--json] [--version]  (also: --bytes N for the test size)

local USAGE = [==[
usage: speedtest-cli [-h] [--no-download] [--no-upload] [--single] [--bytes]
                     [--share] [--simple] [--csv] [--csv-delimiter CSV_DELIMITER]
                     [--csv-header] [--json] [--list] [--server SERVER]
                     [--exclude EXCLUDE] [--mini MINI] [--source SOURCE]
                     [--timeout TIMEOUT] [--secure] [--no-pre-allocate]
                     [--version]]==]

local BASE = "https://speed.cloudflare.com"
local size = 1000000
local doDown, doUp, bytesUnit, simple, json, csv, share = true, true, false, false, false, false, false
local i = 1
local function bad(msg)
  io.stderr:write(USAGE .. "\n")
  io.stderr:write("speedtest-cli: error: " .. msg .. "\n")
  os.exit(2)
end
while arg[i] do
  local a = arg[i]
  if a == "-h" or a == "--help" then
    print(USAGE)
    print("\nCommand line interface for testing internet bandwidth using speedtest.net.\n")
    print("optional arguments:")
    print("  -h, --help            show this help message and exit")
    print("  --no-download         Do not perform download test")
    print("  --no-upload           Do not perform upload test")
    print("  --single              Only use a single connection (always so here)")
    print("  --bytes               Display values in bytes instead of bits")
    print("  --share               Generate and provide a URL to the speedtest.net share results image")
    print("  --simple              Suppress verbose output, only show basic information")
    print("  --csv                 Suppress verbose output, only show basic information in CSV format")
    print("  --json                Suppress verbose output, only show basic information in JSON format")
    print("  --version             Show the version number and exit")
    return
  elseif a == "--version" then
    print("speedtest-cli 2.1.3")
    print("Python 3.13.1 (main) [GCC 14.2.1 20241221]")
    return
  elseif a == "--no-download" then doDown = false
  elseif a == "--no-upload" or a == "--no-up" then doUp = false
  elseif a == "--single" or a == "--secure" or a == "--no-pre-allocate" or a == "--csv-header" or a == "--list" then
    -- accepted: one connection, always https, no server list here
  elseif a == "--bytes" then
    if arg[i + 1] and tonumber(arg[i + 1]) then
      size = math.floor(tonumber(arg[i + 1]))   -- the old form: --bytes N = size of the test
      i = i + 1
    else
      bytesUnit = true
    end
  elseif a == "--share" then share = true
  elseif a == "--simple" then simple = true
  elseif a == "--json" then json = true
  elseif a == "--csv" then csv = true
  elseif a == "--csv-delimiter" or a == "--server" or a == "--exclude" or a == "--mini" or a == "--source" or a == "--timeout" then
    i = i + 1
  else
    bad("unrecognized arguments: " .. a)
  end
  i = i + 1
end

if not net.connected() then
  io.stderr:write("ERROR: Cannot retrieve speedtest configuration\n")
  io.stderr:write("ERROR: <urlopen error [Errno -3] Temporary failure in name resolution>\n")
  os.exit(1)
end

local quiet = simple or json or csv
local function say(s) if not quiet then print(s) end end

say("Retrieving speedtest.net configuration...")
local ip = net.ip() or "0.0.0.0"
say("Testing from " .. (net.ssid() or "WiFi") .. " (" .. ip .. ")...")
say("Retrieving speedtest.net server list...")
say("Selecting best server based on ping...")
local best = nil
for _ = 1, 3 do
  local t0 = sys.millis()
  local status, body = net.get(BASE .. "/__down?bytes=0", 16)
  local ms = sys.millis() - t0
  if not status then
    io.stderr:write("ERROR: Unable to connect to servers to test latency.\n")
    os.exit(1)
  end
  if best == nil or ms < best then best = ms end
end
say(string.format("Hosted by Cloudflare (Edge): %.3f ms", best))

local function rate(n, ms)
  ms = math.max(ms, 1)
  local bits = n * 8 / (ms / 1000)
  if bytesUnit then return bits / 8 / 1000000, "Mbyte/s" end
  return bits / 1000000, "Mbit/s"
end

local down, up = 0.0, 0.0
local unit = bytesUnit and "Mbyte/s" or "Mbit/s"
if doDown then
  if not quiet then io.write("Testing download speed") print("") end
  local status, got, ms = net.download(BASE .. "/__down?bytes=" .. size)
  if not status or status ~= 200 then
    io.stderr:write("ERROR: Download test failed: " .. tostring(status and ("HTTP " .. status) or got) .. "\n")
    os.exit(1)
  end
  down, unit = rate(got, ms)
  say(string.format("Download: %.2f %s", down, unit))
end
if doUp then
  say("Testing upload speed")
  local ustatus, ums = net.upload(BASE .. "/__up", size)
  if not ustatus or ustatus ~= 200 then
    io.stderr:write("ERROR: Upload test failed: " .. tostring(ustatus and ("HTTP " .. ustatus) or ums) .. "\n")
    os.exit(1)
  end
  up, unit = rate(size, ums)
  say(string.format("Upload: %.2f %s", up, unit))
end

if share then say("Share results: http://www.speedtest.net/result/0.png (not available offline)") end
if simple then
  print(string.format("Ping: %.3f ms", best))
  print(string.format("Download: %.2f %s", down, unit))
  print(string.format("Upload: %.2f %s", up, unit))
elseif json then
  print(string.format('{"download": %.6f, "upload": %.6f, "ping": %.3f, "server": {"name": "Cloudflare", "host": "speed.cloudflare.com"}, "bytes_sent": %d, "bytes_received": %d, "share": null, "client": {"ip": "%s"}}',
    down * 1000000 * (bytesUnit and 8 or 1), up * 1000000 * (bytesUnit and 8 or 1), best, doUp and size or 0, doDown and size or 0, ip))
elseif csv then
  print(string.format('0,Cloudflare,"",%.3f,%.3f,%.6f,%.6f,,%s', 0, best, down * 1000000, up * 1000000, ip))
end
