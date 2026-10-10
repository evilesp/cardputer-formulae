#!lua
-- httping: measures how long an HTTP request takes. usage: httping URL [COUNT]

local url = arg[1]
local count = tonumber(arg[2]) or 4
if not url then
  print("usage: httping URL [COUNT]")
  return
end
if not net.connected() then
  print("httping: no network connection")
  return
end

local best, worst, total, ok = nil, 0, 0, 0
for i = 1, count do
  local t0 = sys.millis()
  local status, body = net.get(url, 16)
  local ms = sys.millis() - t0
  if status then
    ok = ok + 1
    total = total + ms
    if best == nil or ms < best then best = ms end
    if ms > worst then worst = ms end
    print(string.format("reply %d from %s: status=%d time=%d ms", i, url, status, ms))
  else
    print(string.format("request %d failed: %s", i, tostring(body)))
  end
  if i < count then sys.sleep(500) end
end

if ok > 0 then
  print(string.format("--- %d ok, min/avg/max = %d/%d/%d ms", ok, best, total // ok, worst))
end
