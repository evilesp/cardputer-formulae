#!lua
-- crypto: prices of popular cryptocurrencies from CoinGecko (no key), with the change over 24 hours. c switches the
-- currency (PLN, USD, EUR), r downloads now (it also refreshes every minute), q quits. The prices are information only,
-- not advice. Needs WiFi (wifi connect SSID PASS). Run it with --selftest to check the reading of the answer.

local COLS, ROWS = term.size()
local COINS = {
  { id = "bitcoin", sym = "BTC" }, { id = "ethereum", sym = "ETH" }, { id = "solana", sym = "SOL" },
  { id = "ripple", sym = "XRP" }, { id = "cardano", sym = "ADA" }, { id = "dogecoin", sym = "DOGE" },
  { id = "litecoin", sym = "LTC" }, { id = "polkadot", sym = "DOT" },
}
local CURRENCIES = { "pln", "usd", "eur" }
local REFRESH_MS = 60000

-- price and 24 h change of each coin in one currency, from the JSON of /simple/price (read with patterns: the answer
-- is flat, one object per coin, so no JSON driver is needed)
local function parsePrices(text, cur)
  local out = {}
  for _, coin in ipairs(COINS) do
    local obj = text:match('"' .. coin.id .. '"%s*:%s*(%b{})')
    if obj then
      local price = tonumber(obj:match('"' .. cur .. '"%s*:%s*([%-%d%.eE+]+)'))
      local change = tonumber(obj:match('"' .. cur .. '_24h_change"%s*:%s*([%-%d%.eE+]+)'))
      if price then out[#out + 1] = { sym = coin.sym, price = price, change = change } end
    end
  end
  return out
end

-- 326609 -> "326 609", 0.342337 -> "0.3423": big prices in whole units with spaces, small ones with 4 significant digits
local function fmtPrice(p)
  if p >= 1000 then
    local s = string.format("%d", math.floor(p + 0.5))
    local grouped = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (grouped:gsub("^ ", ""))
  elseif p >= 1 then
    return string.format("%.2f", p)
  else
    return string.format("%.4g", p)
  end
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local sample = '{"bitcoin":{"pln":326609,"pln_24h_change":0.30,"usd":83278,"usd_24h_change":-0.17},' ..
    '"dogecoin":{"pln":0.342337,"pln_24h_change":2.38,"usd":0.087289,"usd_24h_change":2.26}}'
  local pln = parsePrices(sample, "pln")
  check(#pln == 2 and pln[1].sym == "BTC" and pln[1].price == 326609 and pln[2].sym == "DOGE", "the prices are read in order")
  local usd = parsePrices(sample, "usd")
  check(usd[1].change and usd[1].change < 0 and math.abs(usd[2].price - 0.087289) < 1e-9, "another currency and its change")
  check(#parsePrices("not json", "pln") == 0, "a wrong answer gives no prices")
  check(fmtPrice(326609) == "326 609" and fmtPrice(1234.4) == "1 234", "big prices are grouped")
  check(fmtPrice(12.345) == "12.35" and fmtPrice(0.342337) == "0.3423", "small prices")
  if failed == 0 then print("selftest ok") end
  return
end

if not net.connected() then
  print("crypto: no WiFi connection (wifi connect SSID PASS)")
  return
end

local ids = {}
for _, c in ipairs(COINS) do ids[#ids + 1] = c.id end
local URL = "https://api.coingecko.com/api/v3/simple/price?ids=" .. table.concat(ids, ",") ..
  "&vs_currencies=" .. table.concat(CURRENCIES, ",") .. "&include_24hr_change=true"

local body, message, curIndex, updated = nil, "downloading...", 1, nil

local function draw()
  local cur = CURRENCIES[curIndex]
  term.clear()
  term.text(0, 0, "CRYPTO PRICES  (" .. cur:upper() .. ")", "cyan")
  if body then
    local rows = parsePrices(body, cur)
    term.text(0, 2, "coin            price      24h", "dim")
    for i, r in ipairs(rows) do
      local change = r.change and string.format("%+.1f%%", r.change) or "  -"
      term.text(0, 2 + i, string.format("%-5s %16s", r.sym, fmtPrice(r.price)), "text")
      term.text(24, 2 + i, string.format("%8s", change), (r.change or 0) >= 0 and "green" or "red")
    end
  end
  if message then
    term.text(0, ROWS - 3, message:sub(1, COLS), "warn")
  elseif updated then
    term.text(0, ROWS - 3, "updated " .. updated .. " (CoinGecko)", "dim")
  end
  term.text(0, ROWS - 2, "information only, not advice", "dim")
  term.text(0, ROWS - 1, "c currency   r refresh   q quit", "dim")
  term.flush()
end

local function download()
  message = "downloading..."
  draw()
  local code, text = net.fetch(URL, 4096)
  if not code then
    message = "cannot download: " .. tostring(text)
  elseif code == 429 then
    message = "too many requests: wait a minute"
  elseif code ~= 200 then
    message = "the server answered " .. code
  elseif #parsePrices(text, "usd") == 0 then
    message = "the answer was not understood"
  else
    body, message = text, nil
    updated = sys.date("%H:%M") or "now"
  end
end

term.fullscreen(true)
download()
local nextAt = sys.millis() + REFRESH_MS
local quit = false
while not quit do
  draw()
  local k = key.poll()
  while k do
    if k == "q" or k == "ctrl-q" then quit = true
    elseif k == "c" then curIndex = curIndex % #CURRENCIES + 1
    elseif k == "r" then nextAt = 0
    end
    k = key.poll()
  end
  if not quit and sys.millis() >= nextAt then
    download()
    nextAt = sys.millis() + REFRESH_MS
  end
  sys.sleep(150)
end
term.fullscreen(false)
