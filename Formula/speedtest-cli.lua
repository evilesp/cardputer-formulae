#!lua
-- speedtest-cli: latency, download and upload speed over WiFi (Cloudflare speed test servers).
-- usage: speedtest-cli [--bytes N] [--no-upload]

local BASE = "https://speed.cloudflare.com"
local bytes = 1000000
local doUpload = true

local i = 1
while arg[i] do
  if arg[i] == "--bytes" and arg[i + 1] then
    bytes = math.floor(tonumber(arg[i + 1]) or bytes)
    i = i + 2
  elseif arg[i] == "--no-upload" then
    doUpload = false
    i = i + 1
  else
    print("usage: speedtest-cli [--bytes N] [--no-upload]")
    return
  end
end

if not net.connected() then
  print("Error: no network connection (wifi connect SSID PASS)")
  return
end

print("Testing latency to " .. BASE .. " ...")
local best = nil
for _ = 1, 3 do
  local t0 = sys.millis()
  local status, body = net.get(BASE .. "/__down?bytes=0", 16)
  local ms = sys.millis() - t0
  if not status then
    print("Error: " .. body)
    return
  end
  if best == nil or ms < best then best = ms end
end
print(string.format("Latency: %d ms (best of 3)", best))

print(string.format("Testing download speed (%d bytes) ...", bytes))
local status, got, ms = net.download(BASE .. "/__down?bytes=" .. bytes)
if not status then
  print("Error: " .. got)
  return
end
if status ~= 200 then
  print("Error: HTTP " .. status)
  return
end
ms = math.max(ms, 1)
print(string.format("Download: %.2f Mbit/s (%d bytes in %.2f s)", got * 8 / (ms / 1000) / 1000000, got, ms / 1000))

if doUpload then
  print(string.format("Testing upload speed (%d bytes) ...", bytes))
  local ustatus, ums = net.upload(BASE .. "/__up", bytes)
  if not ustatus then
    print("Error: " .. ums)
    return
  end
  if ustatus ~= 200 then
    print("Error: HTTP " .. ustatus)
    return
  end
  ums = math.max(ums, 1)
  print(string.format("Upload: %.2f Mbit/s (%d bytes in %.2f s)", bytes * 8 / (ums / 1000) / 1000000, bytes, ums / 1000))
end
