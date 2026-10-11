#!lua
-- exchange: the exchange rates of the National Bank of Poland (table A, published on working days, no key needed). The list
-- shows how many zloty one unit of each currency costs. w and s choose a currency, t types an amount of zloty to convert to
-- the chosen currency, r downloads the table again, ctrl-q quits. The rates are information only, not advice.
-- Needs the graphics, the ui package, the json driver (brew install json) and a network connection. Run it with --selftest.

local URL = "https://api.nbp.pl/api/exchangerates/tables/A/?format=json"

-- the list of { code, currency, mid } from the answer of the API, sorted by code; nil when the text is not that table
local function ratesOf(json, text)
  local data, why = json.decode(text)
  if not data then return nil, why end
  local table_ = data[1]
  if type(table_) ~= "table" or type(table_.rates) ~= "table" then return nil, "the answer is not the rates table" end
  local out = {}
  for _, r in ipairs(table_.rates) do
    if type(r.code) == "string" and type(r.mid) == "number" then
      out[#out + 1] = { code = r.code, currency = r.currency or r.code, mid = r.mid }
    end
  end
  table.sort(out, function(a, b) return a.code < b.code end)
  return out, table_.effectiveDate
end

-- zloty for an amount of a currency, or the other way round (rate is zloty per unit)
local function convert(amount, rate)
  return amount * rate
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local json = driver.load("json")
  check(json ~= nil, "the json driver is installed for the test (brew install json)")
  if not json then
    print("selftest failed: json driver missing")
    return
  end
  local sample = '[{"table":"A","no":"200/A/NBP/2026","effectiveDate":"2026-10-12","rates":[' ..
    '{"currency":"dolar amerykanski","code":"USD","mid":3.71},{"currency":"euro","code":"EUR","mid":4.25}]}]'
  local list, date = ratesOf(json, sample)
  check(list and #list == 2 and list[1].code == "EUR" and list[2].code == "USD", "the rates are read and sorted by code")
  check(date == "2026-10-12", "the date of the table")
  check(ratesOf(json, '{"error": "no"}') == nil, "an answer that is not a table is refused")
  check(ratesOf(json, "broken") == nil, "broken text is refused")
  check(math.abs(convert(100, 4.25) - 425) < 1e-9, "100 euro is 425 zloty at 4.25")
  check(json.decode('{"a": 1, "b": [true, false, "x\\ny"], "c": {"d": -2.5e1}}').c.d == -25, "json: numbers and nesting")
  check(json.decode('"\\u0141\\u00f3d\\u017a"') == "\u{141}\u{f3}d\u{17a}", "json: unicode escapes")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("exchange needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local json = driver.load("json")
if not json then
  print("exchange: the json driver is not installed (brew install json)")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("exchange: " .. tostring(uiErr))
  return
end
if not net.connected() then
  print("exchange: no WiFi connection (wifi connect SSID PASS)")
  return
end

local W, H = 240, 135
local rates, date, selected, amount, message = {}, nil, 1, nil, nil

local function download()
  message = "downloading..."
  local code, body = net.fetch(URL, 24576)
  if not code then
    message = "cannot download: " .. tostring(body)
    return
  end
  if code ~= 200 then
    message = "HTTP " .. tostring(code)
    return
  end
  local list, d = ratesOf(json, body)
  body = nil
  if not list then
    message = "the answer was not understood"
    return
  end
  rates, date = list, d
  selected = math.min(selected, math.max(1, #rates))
  message = nil
  collectgarbage()
end

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "EXCHANGE RATES (NBP)", 0xe8ecf4)
  ui.label(160, 4, date and ("table of " .. date) or "", 0x8a94aa)
  for i = 1, math.min(#rates, 6) do
    local idx = math.max(1, math.min(selected - 2, #rates - 5)) + i - 1
    local r = rates[idx]
    local y = 22 + (i - 1) * 14
    if idx == selected then gfx.fill(4, y - 2, W - 8, 13, 0x2a3350) end
    ui.label(8, y, r.code, 0xf0d040)
    ui.label(50, y, string.format("%.4f zl", r.mid), 0xe8ecf4)
    ui.label(120, y, r.currency:sub(1, 16), 0x8a94aa)
  end
  if amount and rates[selected] then
    ui.label(8, 108, string.format("%.2f zl = %.2f %s", amount, amount / rates[selected].mid, rates[selected].code), 0x60ff90)
  end
  ui.label(8, H - 10, message or "w s choose   t amount   r download   ctrl-q quit", message and 0xffe060 or 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("exchange: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  download()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "w" then selected = math.max(1, selected - 1)
      elseif k == "s" then selected = math.min(math.max(1, #rates), selected + 1)
      elseif k == "r" then download()
      elseif k == "t" then
        local typed = tonumber(ui.prompt("zloty to convert", amount and tostring(amount) or "100", 10) or "")
        if typed then amount = typed end
      end
      k = key.poll()
    end
    sys.sleep(60)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("exchange: " .. tostring(problem)) end
