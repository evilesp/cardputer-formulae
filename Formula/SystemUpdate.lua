#!lua
-- SystemUpdate: installs a firmware version over WiFi. The list comes from the firmware index on GitHub.
-- usage: SystemUpdate                   menu: w/s or ;/. choose (Fn+;/Fn+. work too), 1-9 picks, enter installs
--        SystemUpdate list              prints the available versions with their numbers
--        SystemUpdate install X         installs the version called X (label or number), after a y/N question
-- The image is checked (size and SHA-256) before the device switches to it.

local INDEX_URL = "https://raw.githubusercontent.com/evilesp/cardputer-firmware/main/index.txt"
local CURRENT = sys.version()
local VERSION = "1.0.0.2"  -- this package's own version, shown in the menu title
local LIST_ROWS = 12  -- versions shown in the menu at once (rows 1..12 of the 16-row screen)

local function loadVersions()
  if not net.connected() then return nil, "no WiFi connection (wifi connect SSID PASS)" end
  local code, body = net.fetch(INDEX_URL, 16384)
  if not code then return nil, tostring(body) end
  if code ~= 200 then return nil, "index: HTTP " .. code end
  local list = {}
  for raw in (body .. "\n"):gmatch("([^\n]*)\n") do
    local line = raw:gsub("\r", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local label, sha, size, url = line:match("^([^|]+)|([^|]+)|([^|]+)|(.+)$")
      if label then
        list[#list + 1] = { label = label, sha = sha, size = tonumber(size) or 0, url = url }
      end
    end
  end
  return list
end

local function sizeText(bytes)
  if bytes <= 0 then return "" end
  return string.format("%d KB", bytes // 1024)
end

local function tagOf(v)
  return v.label == CURRENT and " (installed)" or ""
end

local function askYesNo(question)
  term.write(question .. " [y/N] ", "warn")
  while true do
    local k = key.poll()
    if k then
      if k == "y" then
        print("y")
        return true
      end
      print("n")
      return false
    end
    sys.sleep(30)
  end
end

local function install(entry)
  print(string.format("Installing %s %s from GitHub", entry.label, sizeText(entry.size)))
  local ok, err = sys.update(entry.url, entry.sha, entry.size)
  if not ok then
    print("Update failed: " .. tostring(err))
    print("The current firmware is unchanged.")
    return
  end
  print("Update installed. The device restarts in 3 seconds.")
  sys.sleep(3000)
  sys.reboot()
end

-- the interactive list; returns the entry the user confirmed, or nil
local function menu(versions)
  term.fullscreen(true)
  local sel, top, pending = 1, 1, nil
  local chosen = nil
  local lastKey = nil  -- the last key the menu received, shown on screen
  while true do
    local quit = false
    local k = key.poll()
    while k do
      lastKey = k
      if pending then
        if k == "y" then
          chosen = pending
          break
        end
        pending = nil  -- any other key answers "no"
      elseif k == "q" then
        quit = true
        break
      elseif k == "up" or k == "w" or k == ";" then
        sel = math.max(1, sel - 1)
      elseif k == "down" or k == "s" or k == "." then
        sel = math.min(#versions, sel + 1)
      elseif k == "enter" then
        pending = versions[sel]
      elseif k:match("^[1-9]$") and versions[tonumber(k)] then
        sel = tonumber(k)
        pending = versions[sel]
      end
      k = key.poll()
    end
    if chosen or quit then break end

    -- keep the selected version inside the visible rows
    if sel < top then top = sel end
    if sel >= top + LIST_ROWS then top = sel - LIST_ROWS + 1 end

    term.clear()
    term.text(0, 0, ("SystemUpdate " .. VERSION .. "  " .. CURRENT):sub(1, 40), "white")
    for row = 0, LIST_ROWS - 1 do
      local i = top + row
      local v = versions[i]
      if v then
        local marker = i == sel and "> " or "  "
        term.text(0, 1 + row, (marker .. i .. " " .. v.label .. tagOf(v) .. "  " .. sizeText(v.size)):sub(1, 40),
          i == sel and "white" or "text")
      end
    end
    term.text(0, 13, ("last key: " .. (lastKey or "none")):sub(1, 40), "dim")
    if pending then
      term.text(0, 14, ("install " .. pending.label .. "?"):sub(1, 40), "warn")
      term.text(0, 15, "y = yes, any other key = no", "warn")
    else
      term.text(0, 14, "Fn+;/Fn+. or w/s choose, 1-9 pick", "dim")
      term.text(0, 15, "enter install   q quit", "dim")
    end
    term.flush()
    sys.sleep(60)
  end
  term.fullscreen(false)
  return chosen
end

local versions, err = loadVersions()
if not versions then
  print("SystemUpdate: " .. err)
  return
end
if #versions == 0 then
  print("SystemUpdate: the firmware index is empty")
  return
end

-- a label (v0.1.0.1) or a number from the list (1, 2, ...)
local function find(wanted)
  if wanted:match("^%d+$") then return versions[tonumber(wanted)] end
  for _, v in ipairs(versions) do
    if v.label == wanted then return v end
  end
  return nil
end

local cmd = arg[1]
if cmd == nil then
  local entry = menu(versions)
  if entry then install(entry) end
elseif cmd == "list" then
  print("installed: " .. CURRENT)
  for i, v in ipairs(versions) do
    print(string.format("%d  %s  %s%s", i, v.label, sizeText(v.size), tagOf(v)))
  end
elseif cmd == "install" then
  local wanted = table.concat(arg, " ", 2)
  local entry = find(wanted)
  if not entry then
    print("SystemUpdate: no version called '" .. wanted .. "' (see SystemUpdate list)")
    return
  end
  if askYesNo("install " .. entry.label .. "?") then install(entry) end
else
  print("usage: SystemUpdate | SystemUpdate list | SystemUpdate install LABEL|NUMBER")
end
