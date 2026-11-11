#!lua
-- natan: tell the device what you want in plain words. A language model answers in JSON, the device runs the tools it asks for
-- (storage, memory, battery, time, network, files, GPIO, brightness) and the model says the result in a sentence, as it is
-- made. Usage: natan [--model NAME] QUESTION...      for example: natan how much free space has this device
-- With an Ollama server on your network (ollama host ADDRESS, and ollama pull on that computer, for example qwen2.5:1.5b) a
-- bigger model answers: natan takes the first model of the server, or --model, or model=NAME in /etc/natan.conf. Without a
-- server, or with --local, the three small models of this device answer (natan-local-pl: ollama pull natan-intent:pl
-- natan-cmd:pl natan-reply:pl), in Polish or English, and nothing leaves the device.
-- Needs the llm module of the firmware and the drivers json and natanlocal (installed as dependencies).

local MAX_STEPS = 6

local function usage()
  print("usage: natan QUESTION...   |   natan /set local | ollama HOST:PORT | api HOST:PORT KEY   |   natan /show   (for example: natan how much free space has this device)")
end

if not llm or not driver then
  print("natan needs the llm module of the firmware: update with SystemUpdateBeta")
  return
end
local json, jerr = driver.load("json")
if not json then
  print("natan needs the json driver: " .. tostring(jerr))
  return
end

local model
local forceLocal = false
local words = {}
local i = 1
while i <= #arg do
  if arg[i] == "--model" and arg[i + 1] then
    model = arg[i + 1]
    i = i + 2
  elseif arg[i] == "--local" or arg[i] == "-l" then
    forceLocal = true
    i = i + 1
  else
    words[#words + 1] = arg[i]
    i = i + 1
  end
end
if #words == 0 then
  usage()
  return
end
local question = table.concat(words, " ")

-- ---- the settings: natan /set local | ollama HOST[:PORT] | api HOST[:PORT] KEY, natan /show ----
local CONF = "/etc/natan.conf"
local LOCAL_MODELS = { "natan-intent:pl", "natan-cmd:pl", "natan-reply:pl" }
local function readConf()
  return fs.exists(CONF) and fs.read(CONF) or ""
end
if words[1] == "/show" or (words[1] == "/set" and #words == 1) then
  local mode = readConf():match("mode=([^\r\n]+)") or "auto"
  print("natan answers with: " .. (mode == "local" and "the models of this device" or mode == "auto" and "a server when one is set, else the models of this device" or mode))
  local host = llm.host()
  print("server: " .. ((host and host ~= "") and host or "none"))
  local have = {}
  for _, m in ipairs(llm.list()) do
    if m.where == "local" then have[m.name] = true end
  end
  for _, n in ipairs(LOCAL_MODELS) do print(string.format("  %-16s %s", n, have[n] and "on the card" or "not pulled yet (the first question pulls it)")) end
  return
elseif words[1] == "/set" then
  local what = words[2]
  local mode
  if what == "local" then
    mode = "local"
  elseif (what == "ollama" or what == "server") and words[3] then
    local ok, e = pcall(function() llm.host(words[3]); if llm.key then llm.key("") end end)
    if not ok then print("natan: " .. tostring(e)) return end
    mode = "ollama"
  elseif what == "api" and words[3] and words[4] then
    local ok, e = pcall(function() llm.host(words[3]); llm.key(words[4]) end)
    if not ok then print("natan: " .. tostring(e)) return end
    mode = "api"
  else
    print("usage: natan /set local | ollama HOST[:PORT] | api HOST[:PORT] KEY")
    return
  end
  local ok, e = fs.write(CONF, "mode=" .. mode .. "\n")
  if not ok then print("natan: cannot write " .. CONF .. ": " .. tostring(e)) return end
  print("natan answers with " .. (mode == "local" and "the models of this device" or mode .. " " .. llm.host()))
  return
end

-- ---- the tools ----

local function size(n)
  if n >= 1e9 then return string.format("%.1f GB", n / 1e9) end
  if n >= 1e6 then return string.format("%.1f MB", n / 1e6) end
  return string.format("%d KB", n // 1000)
end

local TOOLS = {}
local ORDER = {}
local function tool(name, args, desc, run)
  TOOLS[name] = { args = args, desc = desc, run = run }
  ORDER[#ORDER + 1] = name
end

tool("storage", "", "free and used space of the SD card and of the program flash", function()
  local out = {}
  local total, used = sys.sd()
  if total then
    out[#out + 1] = string.format("SD card: %s free of %s", size(total - used), size(total))
  else
    out[#out + 1] = "SD card: none"
  end
  if sys.flash then
    local chip, sketch, free = sys.flash()
    out[#out + 1] = string.format("flash: %s in total, the program takes %s, %s free for a new program", size(chip), size(sketch), size(free))
  end
  return table.concat(out, "; ")
end)

tool("memory", "", "free RAM and PSRAM, and what a language model takes", function()
  local free, total, psram = sys.heap()
  local out = string.format("memory: %s free of %s", size(free * 1000), size(total * 1000))
  if psram and psram > 0 then out = out .. string.format(" (PSRAM %s)", size(psram * 1000)) end
  local r = llm.ps()
  if r then out = out .. string.format("; the model %s takes %s", r.name, size(r.size)) end
  return out
end)

tool("battery", "", "battery percent, volts and whether it is charging", function()
  local pct, mv, charging = sys.battery()
  return string.format("battery %d%%, %.2f V, %s", pct, mv / 1000, charging and "charging" or "not charging")
end)

tool("time", "", "the date and time, and how long the device has been on", function()
  local s = math.floor(sys.uptime())
  return string.format("%s; on for %dh %02dm", sys.date("%Y-%m-%d %H:%M") or "the clock is not set", s // 3600, (s // 60) % 60)
end)

tool("network", "", "WiFi state, network name and IP address", function()
  if not net.connected() then return "WiFi is not connected" end
  return string.format("WiFi %s, IP %s", net.ssid(), net.ip())
end)

tool("files", "path", "list a folder of the SD card", function(a)
  local list, err = fs.info(a.path or "/")
  if not list then return "cannot list: " .. tostring(err) end
  local out = {}
  for n, e in ipairs(list) do
    if n > 25 then
      out[#out + 1] = "..."
      break
    end
    out[#out + 1] = e.name .. (e.dir and "/" or " (" .. size(e.size) .. ")")
  end
  return #out == 0 and "empty" or table.concat(out, ", ")
end)

tool("read_file", "path", "the first 600 characters of a text file", function(a)
  if type(a.path) ~= "string" then return "path is needed" end
  local st = fs.stat(a.path)
  if not st then return "no such file" end
  if st.size > 60000 then return "the file is too big (" .. size(st.size) .. ")" end
  local data, err = fs.read(a.path)
  if not data then return "cannot read: " .. tostring(err) end
  return data:sub(1, 600)
end)

tool("gpio_read", "pin", "read a pin: 0 or 1", function(a)
  local ok, v = pcall(gpio.read, tonumber(a.pin))
  return ok and ("pin " .. tostring(a.pin) .. " is " .. tostring(v)) or ("cannot read: " .. tostring(v))
end)

tool("gpio_write", "pin, value", "set a pin to 1 or 0", function(a)
  local v = tonumber(a.value) or 0
  local ok, e = pcall(gpio.write, tonumber(a.pin), v ~= 0 and 1 or 0)
  return ok and ("pin " .. tostring(a.pin) .. " set to " .. (v ~= 0 and 1 or 0)) or ("cannot write: " .. tostring(e))
end)

tool("brightness", "value (0 to 255, optional)", "read or set the screen brightness", function(a)
  if a.value ~= nil then sys.setting("brightness", math.max(0, math.min(255, tonumber(a.value) or 128))) end
  return "brightness " .. tostring(sys.setting("brightness"))
end)

local function systemPrompt()
  local lines = {
    "You are the assistant of a small computer (an ESP32 board with a screen, an SD card and pins).",
    "Reply with ONE JSON object and nothing else.",
    'To use a tool: {"tool":"NAME","args":{...}}',
    'To answer the user in one or two short sentences: {"answer":"..."}',
    "Use a tool only when the question needs the state of the device. Greetings and general questions are answered at once.",
    "Never call a tool twice. After a tool result, answer from it (never invent numbers).",
    "Tools:",
  }
  for _, name in ipairs(ORDER) do
    local t = TOOLS[name]
    lines[#lines + 1] = string.format("- %s(%s): %s", name, t.args, t.desc)
  end
  local more = {
    "Examples:",
    'User: how much battery is left -> {"tool":"battery","args":{}}',
    'Tool result: battery 80%, 3.90 V, not charging -> {"answer":"The battery is at 80% and not charging."}',
    'User: hello -> {"answer":"Hello! Ask me about this device."}',
    'User: what time is it -> {"tool":"time","args":{}}',
    'User: set the brightness to 50 -> {"tool":"brightness","args":{"value":50}}',
  }
  for _, l in ipairs(more) do lines[#lines + 1] = l end
  return table.concat(lines, "\n")
end

-- ---- the model ----

-- /etc/natan.conf (written by natan /set): mode=local (the models of this device) | ollama | api | auto (a server when one is set), model=NAME
local conf = readConf()
local mode = conf:match("mode=([^\r\n]+)") or "auto"
if mode == "local" then forceLocal = true end
if not model and not forceLocal then
  model = conf:match("model=([^\r\n]+)")
end
if not model and not forceLocal then
  for _, m in ipairs(llm.list()) do
    if m.where ~= "local" then
      model = m.name
      break
    end
  end
end
if not model then
  -- no server: the small models of this device
  local nl = sys.run and driver.load("natanlocal")
  if nl then
    local missing = nl.missing()
    if #missing > 0 and llm.pull and net.connected() then
      for _, name in ipairs(missing) do
        print("natan: pulling " .. name .. " once")
        local ok, perr = llm.pull(name)
        if not ok then
          print("natan: " .. tostring(perr))
          return
        end
      end
      missing = nl.missing()
    end
    if #missing == 0 then
      nl.ask(question)
      return
    end
    print("natan answers with models that run on this device; they are not here and there is no WiFi to pull them (nmcli device wifi connect SSID password PASSWORD), or pull them once:")
    print("  ollama pull " .. table.concat(missing, " "))
    print("or set an Ollama server on your network: natan /set ollama HOST:PORT")
    return
  end
  print("natan needs a chat model that answers in JSON. Set an Ollama server on your network:")
  print("  ollama host ADDRESS       (the computer that runs Ollama)")
  print("  and there: ollama pull qwen2.5:1.5b")
  return
end

-- Prints the text of the "answer" field while the JSON is still arriving, so the sentence is written as it is made
local function answerPrinter()
  local raw, printed = "", 0
  return function(piece)
    raw = raw .. piece
    local from = raw:match('"answer"%s*:%s*"()')
    if not from then return true end
    local out, i = {}, from
    while i <= #raw do
      local c = raw:sub(i, i)
      if c == '"' then break end
      if c == "\\" then
        local n = raw:sub(i + 1, i + 1)
        if n == "" then break end
        if n == "u" then
          if #raw < i + 5 then break end
          out[#out + 1] = utf8.char(tonumber(raw:sub(i + 2, i + 5), 16) or 63)
          i = i + 6
        else
          out[#out + 1] = ({ n = "\n", t = "\t" })[n] or n
          i = i + 2
        end
      else
        out[#out + 1] = c
        i = i + 1
      end
    end
    local text = table.concat(out)
    if #text > printed then
      term.write(text:sub(printed + 1))
      printed = #text
    end
    return true
  end, function() return printed end
end

local messages = {
  { role = "system", content = systemPrompt() },
  { role = "user", content = question },
}

local function describe(args)
  local parts = {}
  for k, v in pairs(args or {}) do parts[#parts + 1] = k .. "=" .. tostring(v) end
  table.sort(parts)
  return table.concat(parts, ", ")
end

local retries = 0
local used = {}
for step = 1, MAX_STEPS do
  local feed, printedCount = answerPrinter()
  local raw, err = llm.generate(model, messages, { json = true, max = 300, temperature = 0.1 }, feed)
  if not raw then
    print("\nnatan: " .. tostring(err))
    return
  end
  local reply = json.decode(raw)
  if type(reply) == "table" and type(reply.answer) == "string" then
    if printedCount() == 0 then term.write(reply.answer) end
    print("")
    return
  elseif type(reply) == "table" and type(reply.tool) == "string" then
    local t = TOOLS[reply.tool]
    local result
    if not t then
      result = "unknown tool " .. reply.tool
    else
      local args = type(reply.args) == "table" and reply.args or {}
      local ok, r = pcall(t.run, args)
      result = ok and tostring(r) or ("the tool failed: " .. tostring(r))
      print(string.format("  > %s(%s): %s", reply.tool, describe(args), result))
    end
    messages[#messages + 1] = { role = "assistant", content = raw }
    local hint = used[reply.tool] and " (you already called this tool: answer now)" or ""
    used[reply.tool] = true
    messages[#messages + 1] = { role = "user", content = "Tool result: " .. result .. hint .. '\nNow reply with {"answer":"..."} unless another tool is really needed.' }
  else
    retries = retries + 1
    if retries > 2 then
      print("natan: the model did not answer in JSON: " .. raw:sub(1, 80))
      return
    end
    messages[#messages + 1] = { role = "assistant", content = raw }
    messages[#messages + 1] = { role = "user", content = 'Reply with one JSON object: {"tool":...} or {"answer":...}' }
  end
end
print("natan: no answer after " .. MAX_STEPS .. " steps")
