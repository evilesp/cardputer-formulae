#!lua
-- remote: learn the buttons of an infrared remote (TV, fan, air conditioner) and send them again, one by one.
-- Each remote is saved as /home/user/remote-NAME.rem, one line per button, in the order they were learned.
--   remotes:  enter opens one, n makes a new one, p sets the pins, q quits
--   a remote: enter sends the button, a learns a new one (press the button at the receiver), r sends all
--             of them one after another, x deletes a button, b goes back, q quits
-- Sending uses the IR LED on the TX pin (44 on the Cardputer). Learning needs an IR receiver module on the RX pin.
-- Set both with p. Needs firmware v0.1.0.11(beta) or newer (the ir module).

local CONFIG = "/home/user/.remote"
local DIR = "/home/user"
local GAP_MS = 25                 -- a signal ends after 25 ms without an edge
local COLS, ROWS = term.size()
local LIST_ROWS = ROWS - 4        -- rows 2 .. ROWS-3: between the title and the message and keys rows

local FIELDS = {
  { key = "tx", label = "TX pin (sends)" },
  { key = "rx", label = "RX pin (learns)" },
  { key = "pause", label = "pause ms" },
}

local settings = { tx = 44, rx = nil, pause = 500 }
local state = {
  screen = "list",                -- "list", "remote" or "settings"
  remotes = {}, sel = 1,          -- the remote names and the cursor on them
  name = nil, buttons = {}, bsel = 1, pending = nil,   -- the open remote; pending = "delete" waits for y
  psel = 1,                       -- the cursor in settings
  message = "",
  dirty = true,
  quit = false,
}

-- ---- pure parts (checked by --selftest) ----

local function pinNumber(text)
  local n = tonumber(text)
  if math.type(n) == "integer" and n >= 0 and n <= 48 then return n end
  return nil
end

local function pauseNumber(text)
  local n = tonumber(text)
  if math.type(n) == "integer" and n >= 0 and n <= 10000 then return n end
  return nil
end

-- the settings file: tx=44, rx=5 or rx=none, pause=500
local function parseSettings(text)
  local s = { tx = 44, rx = nil, pause = 500 }
  for key, value in text:gmatch("(%w+)=([^\n]*)") do
    if key == "tx" then
      s.tx = pinNumber(value) or s.tx
    elseif key == "rx" then
      s.rx = pinNumber(value)
    elseif key == "pause" then
      s.pause = pauseNumber(value) or s.pause
    end
  end
  return s
end

local function settingsText(s)
  return string.format("tx=%d\nrx=%s\npause=%d\n", s.tx, s.rx and tostring(s.rx) or "none", s.pause)
end

-- sets one setting from typed text (the RX pin may be "none"). Returns true, or false and the reason.
local function applySetting(s, key, text)
  if key == "pause" then
    local n = pauseNumber(text)
    if not n then return false, "pause is 0 to 10000 ms" end
    s.pause = n
    return true
  end
  if key == "rx" and text == "none" then
    s.rx = nil
    return true
  end
  local n = pinNumber(text)
  if not n then return false, "a pin is a number from 0 to 48" end
  local old = s[key]
  s[key] = n
  if s.rx and s.rx == s.tx then
    s[key] = old
    return false, "TX and RX must be different pins"
  end
  return true
end

-- a remote file: "NAME|t1 t2 t3" per button. Lines that do not fit are skipped.
local function parseRemote(text)
  local buttons = {}
  for line in text:gmatch("[^\n]+") do
    local name, times = line:match("^([^|]+)|(.*)$")
    if name then
      local timings = {}
      for t in times:gmatch("%d+") do timings[#timings + 1] = tonumber(t) end
      if #timings >= 2 then buttons[#buttons + 1] = { name = name, timings = timings } end
    end
  end
  return buttons
end

local function remoteText(buttons)
  local lines = {}
  for i, b in ipairs(buttons) do
    lines[i] = b.name .. "|" .. table.concat(b.timings, " ")
  end
  return #lines > 0 and table.concat(lines, "\n") .. "\n" or ""
end

-- a button name: no | and no line breaks, no spaces at the ends, 24 characters at most
local function cleanName(text)
  local s = text:gsub("[|\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return s:sub(1, 24)
end

-- a remote name is also part of its file name: letters, digits, - and _ (20 at most)
local function validRemoteName(name)
  return #name <= 20 and name:match("^[%w_%-]+$") ~= nil
end

local function selftest()
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local s = parseSettings("tx=44\nrx=5\npause=300\n")
  check(s.tx == 44 and s.rx == 5 and s.pause == 300, "settings with all three values")
  s = parseSettings("rx=none\n")
  check(s.tx == 44 and s.rx == nil and s.pause == 500, "settings: rx none and the defaults")
  check(settingsText(parseSettings(settingsText(s))) == settingsText(s), "settings round trip")
  local buttons = parseRemote("Power|9000 4500 560\nVol+|560 560\nbroken\n|1 2\n")
  check(#buttons == 2 and buttons[1].name == "Power" and #buttons[1].timings == 3, "remote lines")
  check(buttons[2].name == "Vol+" and buttons[2].timings[2] == 560, "remote button timings")
  check(remoteText(buttons) == "Power|9000 4500 560\nVol+|560 560\n", "remote round trip")
  check(remoteText({}) == "", "an empty remote is an empty file")
  check(cleanName("  a|b  ") == "ab", "button names: no | and no spaces at the ends")
  check(cleanName(string.rep("x", 30)) == string.rep("x", 24), "button names: 24 characters")
  check(validRemoteName("tv_1-x") and not validRemoteName("tv x") and not validRemoteName(""), "remote names")
  check(validRemoteName(string.rep("a", 20)) and not validRemoteName(string.rep("a", 21)), "remote name length")
  local t = { tx = 44, rx = 5, pause = 500 }
  check(applySetting(t, "rx", "7") and t.rx == 7, "set rx")
  check(not applySetting(t, "rx", "44") and t.rx == 7, "tx and rx must differ, rx kept")
  check(not applySetting(t, "tx", "49") and t.tx == 44, "pin 49 refused")
  check(applySetting(t, "rx", "none") and t.rx == nil, "rx none")
  check(not applySetting(t, "pause", "-1") and t.pause == 500, "pause refused")
  if failed == 0 then print("selftest ok") end
  return failed == 0
end

-- ---- files ----

local function remotePath(name)
  return DIR .. "/remote-" .. name .. ".rem"
end

local function listRemotes()
  local names = {}
  for _, entry in ipairs(fs.list(DIR) or {}) do
    local name = entry:match("^remote%-([%w_%-]+)%.rem$")
    if name then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

local function loadRemote(name)
  return parseRemote(fs.read(remotePath(name)) or "")
end

-- returns true, or nil and the reason (the file could not be written)
local function saveRemote(name, buttons)
  local ok, err = fs.write(remotePath(name), remoteText(buttons))
  if not ok then return nil, err or "cannot write the file" end
  return true
end

local function saveSettings()
  local ok, err = fs.write(CONFIG, settingsText(settings))
  if not ok then return nil, err or "cannot write the settings" end
  return true
end

-- ---- screen ----

-- one whole row of the screen, padded to the width so older text is erased
local function row(y, text, color)
  term.text(0, y, (text .. string.rep(" ", COLS)):sub(1, COLS), color or "text")
end

local function drawFrame(title, keys)
  term.clear()
  row(0, title, "cyan")
  row(ROWS - 2, state.message, "text")
  row(ROWS - 1, keys, "dim")
end

-- the cursor stays on screen: the first row shown is the cursor minus the rows that fit above it
local function firstShown(sel)
  return math.max(1, sel - LIST_ROWS + 1)
end

local function drawList()
  local rx = settings.rx and tostring(settings.rx) or "none"
  drawFrame(string.format("remote   TX %d  RX %s", settings.tx, rx), "enter open  n new  p pins  q quit")
  if #state.remotes == 0 then row(2, "no remotes yet: press n to make one", "dim") end
  local first = firstShown(state.sel)
  for i = first, math.min(#state.remotes, first + LIST_ROWS - 1) do
    local sel = i == state.sel
    row(2 + i - first, (sel and "> " or "  ") .. state.remotes[i], sel and "green" or "text")
  end
end

local function drawRemote()
  drawFrame(state.name .. "   " .. #state.buttons .. " buttons", "enter send a learn r all x del b back")
  if #state.buttons == 0 then row(2, "no buttons yet: press a, then the button", "dim") end
  local first = firstShown(state.bsel)
  for i = first, math.min(#state.buttons, first + LIST_ROWS - 1) do
    local sel = i == state.bsel
    row(2 + i - first, string.format("%s%2d %s", sel and "> " or "  ", i, state.buttons[i].name), sel and "green" or "text")
  end
end

local function fieldText(key)
  if key == "rx" then return settings.rx and tostring(settings.rx) or "none" end
  return tostring(settings[key])
end

local function drawSettings()
  drawFrame("settings", "enter change  b back  q quit")
  for i, f in ipairs(FIELDS) do
    local sel = i == state.psel
    row(2 + i - 1, string.format("%s%-16s %s", sel and "> " or "  ", f.label, fieldText(f.key)), sel and "green" or "text")
  end
  row(6, "TX is the IR LED: 44 on the Cardputer.", "dim")
  row(7, "RX is the IR receiver module (for learning).", "dim")
  row(8, "pause: the wait between buttons when sending all.", "dim")
end

-- types one line on the bottom rows: enter ends it (the text, maybe empty), backspace deletes. Ctrl+C stops the script.
local function ask(label, text)
  while true do
    row(ROWS - 2, label .. text .. "_", "cyan")
    row(ROWS - 1, "enter: ok    backspace: delete", "dim")
    term.flush()
    local k = key.poll()
    if k == "enter" then
      return text
    elseif k == "backspace" then
      text = text:sub(1, -2)
    elseif k and #k == 1 and k:byte() >= 32 and k:byte() < 127 and #text < 24 then
      text = text .. k
    end
    sys.sleep(10)
  end
end

-- ---- actions ----

local function refreshRemotes()
  state.remotes = listRemotes()
  if state.sel > #state.remotes then state.sel = math.max(1, #state.remotes) end
end

local function openRemote(name)
  state.name = name
  state.buttons = loadRemote(name)
  state.bsel = 1
  state.pending = nil
  state.screen = "remote"
  state.message = ""
end

local function newRemote()
  local name = ask("new remote name: ", "")
  if name == "" then
    state.message = "cancelled"
    return
  end
  if not validRemoteName(name) then
    state.message = "use letters, digits, - and _ (20 at most)"
    return
  end
  for _, existing in ipairs(state.remotes) do
    if existing == name then
      state.message = "a remote named " .. name .. " exists"
      return
    end
  end
  local ok, err = saveRemote(name, {})
  if not ok then
    state.message = "cannot save: " .. tostring(err)
    return
  end
  refreshRemotes()
  openRemote(name)
end

local function sendButton(b)
  local ok, err = ir.send(settings.tx, b.timings)
  if ok then return true end
  state.message = "send failed: " .. tostring(err)
  return false
end

local function sendSelected()
  local b = state.buttons[state.bsel]
  if not b then
    state.message = "no button yet: press a to learn one"
    return
  end
  if sendButton(b) then state.message = "sent " .. b.name end
end

-- sends every button in the order they were learned, pause ms apart
local function sendAll()
  if #state.buttons == 0 then
    state.message = "no buttons to send"
    return
  end
  for i, b in ipairs(state.buttons) do
    row(ROWS - 2, string.format("sending %d of %d: %s", i, #state.buttons, b.name), "cyan")
    term.flush()
    if not sendButton(b) then return end
    sys.sleep(settings.pause)
  end
  state.message = "sent all " .. #state.buttons .. " buttons"
end

local function learn()
  if not settings.rx then
    state.message = "set the RX pin first: back, p"
    return
  end
  row(2, "press a button on the remote now", "cyan")
  row(3, "enter stops waiting", "dim")
  local signal
  repeat
    term.flush()
    local got, err = ir.receive(settings.rx, 200, GAP_MS)
    if not got and err ~= "timeout" then
      state.message = "receive failed: " .. tostring(err)
      return
    end
    signal = got
    -- a key is read only while nothing came: a key pressed after a signal is for the name, not for this loop
    if not signal and key.poll() == "enter" then
      state.message = "learning stopped"
      return
    end
  until signal
  row(2, string.format("got a signal of %d timings", #signal), "green")
  row(3, "name it (enter alone: button N)", "dim")
  local name = cleanName(ask("name: ", ""))
  if name == "" then name = "button " .. (#state.buttons + 1) end
  state.buttons[#state.buttons + 1] = { name = name, timings = signal }
  state.bsel = #state.buttons
  local ok, err = saveRemote(state.name, state.buttons)
  if ok then
    state.message = "saved " .. name
  else
    table.remove(state.buttons)
    state.message = "cannot save: " .. tostring(err)
  end
end

local function deleteSelected(answer)
  state.pending = nil
  if answer ~= "y" then
    state.message = "not deleted"
    return
  end
  table.remove(state.buttons, state.bsel)
  if state.bsel > #state.buttons then state.bsel = math.max(1, #state.buttons) end
  local ok, err = saveRemote(state.name, state.buttons)
  state.message = ok and "button deleted" or ("cannot save: " .. tostring(err))
end

local function editSetting()
  local f = FIELDS[state.psel]
  local text = ask(f.label .. ": ", "")
  if text == "" then
    state.message = "unchanged"
    return
  end
  local ok, why = applySetting(settings, f.key, text)
  if not ok then
    state.message = why
    return
  end
  local saved, err = saveSettings()
  state.message = saved and "saved" or ("cannot save: " .. tostring(err))
end

-- ---- keys ----

local function handleList(k)
  if k == "up" then
    state.sel = math.max(1, state.sel - 1)
  elseif k == "down" then
    state.sel = math.min(math.max(1, #state.remotes), state.sel + 1)
  elseif k == "enter" and #state.remotes > 0 then
    openRemote(state.remotes[state.sel])
  elseif k == "n" then
    newRemote()
  elseif k == "p" then
    state.screen = "settings"
    state.psel = 1
    state.message = ""
  elseif k == "q" then
    state.quit = true
  end
end

local function handleRemote(k)
  if state.pending == "delete" then
    deleteSelected(k)
    return
  end
  if k == "up" then
    state.bsel = math.max(1, state.bsel - 1)
  elseif k == "down" then
    state.bsel = math.min(math.max(1, #state.buttons), state.bsel + 1)
  elseif k == "enter" then
    sendSelected()
  elseif k == "a" then
    learn()
  elseif k == "r" then
    sendAll()
  elseif k == "x" and #state.buttons > 0 then
    state.pending = "delete"
    state.message = "delete " .. state.buttons[state.bsel].name .. "? y = yes, any key = no"
  elseif k == "b" or k == "backspace" then
    state.screen = "list"
    state.message = ""
    refreshRemotes()
  elseif k == "q" then
    state.quit = true
  end
end

local function handleSettings(k)
  if k == "up" then
    state.psel = math.max(1, state.psel - 1)
  elseif k == "down" then
    state.psel = math.min(#FIELDS, state.psel + 1)
  elseif k == "enter" then
    editSetting()
  elseif k == "b" or k == "backspace" then
    state.screen = "list"
    state.message = ""
    refreshRemotes()
  elseif k == "q" then
    state.quit = true
  end
end

local function draw()
  if state.screen == "list" then
    drawList()
  elseif state.screen == "remote" then
    drawRemote()
  else
    drawSettings()
  end
end

-- ---- main ----

if arg[1] == "--selftest" then
  selftest()
  return
end
if #arg > 0 then
  print("usage: remote   (no arguments: the list of remotes)")
  return
end
if not ir or not ir.receive then
  print("remote needs firmware v0.1.0.11(beta) or newer (the ir module)")
  return
end

settings = parseSettings(fs.read(CONFIG) or "")
refreshRemotes()
if not settings.rx then state.message = "set the RX pin to learn: p" end
term.fullscreen(true)
while not state.quit do
  if state.dirty then
    draw()
    state.dirty = false
  end
  term.flush()
  local k = key.poll()
  if k then
    if state.screen == "list" then
      handleList(k)
    elseif state.screen == "remote" then
      handleRemote(k)
    else
      handleSettings(k)
    end
    state.dirty = true
  end
  sys.sleep(10)
end
term.fullscreen(false)
