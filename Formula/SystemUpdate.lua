#!lua
-- SystemUpdate: installs a firmware version over WiFi. The list comes from the firmware index on GitHub.
-- usage: SystemUpdate                 menu: up/down choose, Enter installs (y confirms), q quits
--        SystemUpdate list            prints the available versions
--        SystemUpdate install LABEL   installs one version after a y/N question
-- The image is checked (size and SHA-256) before the device switches to it.

local INDEX_URL = "https://raw.githubusercontent.com/evilesp/cardputer-firmware/main/index.txt"
local CURRENT = sys.version()

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
  local sel, pending, message = 1, nil, nil
  local chosen = nil
  while true do
    local k = key.poll()
    while k do
      if pending then
        if k == "y" then chosen = pending; break
        else pending = nil end
      elseif k == "q" then
        chosen = nil
        break
      elseif k == "up" then sel = math.max(1, sel - 1)
      elseif k == "down" then sel = math.min(#versions, sel + 1)
      elseif k == "enter" then
        pending = versions[sel]
        message = nil
      end
      k = key.poll()
    end
    if chosen or k == "q" then break end

    term.clear()
    term.text(0, 0, "SystemUpdate  installed: " .. CURRENT, "white")
    for i, v in ipairs(versions) do
      local marker = i == sel and "> " or "  "
      local tag = v.label == CURRENT and "  (installed)" or ""
      term.text(0, 1 + i, (marker .. v.label .. tag .. "  " .. sizeText(v.size)):sub(1, 40),
        i == sel and "white" or "text")
    end
    if pending then
      term.text(0, 15, ("install " .. pending.label .. "? y = yes, any key = no"):sub(1, 40), "warn")
    else
      term.text(0, 15, message or "up/dn choose  enter install  q quit", "dim")
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

local cmd = arg[1]
if cmd == nil then
  local entry = menu(versions)
  if entry then install(entry) end
elseif cmd == "list" then
  print("installed: " .. CURRENT)
  for _, v in ipairs(versions) do
    local tag = v.label == CURRENT and " (installed)" or ""
    print(string.format("%s  %s%s", v.label, sizeText(v.size), tag))
  end
elseif cmd == "install" then
  local wanted = table.concat(arg, " ", 2)
  local entry
  for _, v in ipairs(versions) do
    if v.label == wanted then entry = v end
  end
  if not entry then
    print("SystemUpdate: no version called '" .. wanted .. "' (see SystemUpdate list)")
    return
  end
  if askYesNo("install " .. entry.label .. "?") then install(entry) end
else
  print("usage: SystemUpdate | SystemUpdate list | SystemUpdate install LABEL")
end
