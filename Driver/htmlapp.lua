#!lua
-- htmlapp: the program of the html player (html, webplay, htmlplay) as a driver, so the three names share it.
-- html: a small web player for local apps and simple pages. It shows FILE.html (or a web address) on the screen with its CSS and runs its
-- JavaScript (through the node translator) with a DOM, events, timers, <canvas>, fetch and localStorage. It is not a full browser.
--   html FILE.html | URL          the page; tap or Tab + Enter follows links, Backspace (or b) goes back, Ctrl+Q quits
--   html --console FILE           the console of the page is printed to the terminal when the program ends
--   html --dump FILE              no screen: the page is laid out for 800x480 and its boxes and console are printed
-- Keys: arrows / PageUp / PageDown / space scroll, Tab moves the focus, Ctrl+O shows the console of the page, Ctrl+R loads it again.
local M = {}
function M.main(arg, name)
  local NAME = name or "html"
  local function usage()
    print("usage: " .. NAME .. " [--console] [--dump] FILE.html|URL")
    print("  a page with CSS and JavaScript on the screen (Ctrl+Q quits, Backspace goes back, Ctrl+O console)")
  end
  local opts, target = {}, nil
  for _, a in ipairs(arg or {}) do
    if a == "--console" then opts.console = true
    elseif a == "--dump" then opts.dump = true
    elseif a == "--help" or a == "-h" then usage() return
    elseif a == "--version" then print(NAME .. " 1.0.0.0 (html player for arch-esp)") return
    elseif a:sub(1, 2) == "--" then print(NAME .. ": unrecognized option '" .. a .. "'"); usage(); if os and os.exit then os.exit(2) end return
    else target = target or a end
  end
  if not target then usage() if os and os.exit then os.exit(2) end return end

  local H, err = driver.load("htmljs")
  if H then rawset(_G, "HTML_DRIVERS", rawget(_G, "HTML_DRIVERS") or {}); HTML_DRIVERS.htmljs = H end
  if not H then print(NAME .. ": " .. tostring(err)) return end

  -- ---------------------------------------------------------------- files and the network
  local function absPath(p)
    if p:find("^%a[%w+.-]*://") then return p end
    if p:sub(1, 1) ~= "/" and fs and fs.abspath then local ok, a = pcall(fs.abspath, p); if ok and a then return a end end
    if p:sub(1, 1) ~= "/" and fs and fs.cwd then local ok, c = pcall(fs.cwd); if ok and c then return (c == "/" and "" or c) .. "/" .. p end end
    return p
  end
  local function request(url, method, body, headers)
    if not (net and (net.request or net.fetch)) then return nil, nil, "no network module" end
    if net.connected and not net.connected() then return nil, nil, "no network (connect to Wi-Fi first)" end
    if net.request then
      local ok, status, data = pcall(net.request, { url = url, method = method or "GET", body = body, headers = headers, maxBytes = 1024 * 1024, follow = true,
        agent = "Mozilla/5.0 (arch-esp; ESP32-P4) html-player/1.0" })
      if ok and status then return data or "", status end
      if ok then return nil, nil, data end
    end
    local status, data = net.fetch(url, 1024 * 1024)
    if status then return data or "", status end
    return nil, nil, data
  end
  local function readUrl(url)
    if url:find("^https?://") then
      local body, status, e = request(url)
      if not body then return nil, e or "the request failed" end
      if status >= 400 then return nil, "HTTP " .. status end
      return body
    end
    if url:find("^data:") then
      local data = url:match("^data:[^,]*,(.*)$")
      return data and data:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end) or nil
    end
    local path = url:gsub("[?#].*$", "")
    local text = fs and fs.read and fs.read(path)
    if not text then return nil, path .. ": No such file or directory" end
    return text
  end
  local HOME = (os and os.getenv and os.getenv("HOME")) or "/home/user"
  local function storagePath(origin)
    local name = (origin or "file"):gsub("[^%w%.%-]", "_")
    return HOME .. "/.local/share/html/" .. name .. ".storage"
  end
  local function writeFile(path, text)
    if not (fs and fs.write) then return end
    if not fs.write(path, text) and fs.mkdir then
      pcall(fs.mkdir, path:match("^(.*)/[^/]*$"), true)
      fs.write(path, text)
    end
  end

  -- ---------------------------------------------------------------- fonts
  local gfxOpen = false
  local smooth = false
  local fontsDrv
  local FONTDIR = "/usr/share/fonts/vlw/"
  local SIZES_R, SIZES_B, SIZES_L = { 12, 14, 16, 18, 20, 24 }, { 12, 14, 16, 18, 20, 24, 32, 44, 64 }, { 32, 44, 64 }
  local function nearest(list, px)
    local best = list[1]
    for _, s in ipairs(list) do if math.abs(s - px) < math.abs(best - px) then best = s end end
    return best
  end
  local function monoSize(px) return px < 15 and 1 or px < 26 and 2 or px < 38 and 3 or 4 end
  local function fontOf(cs)
    local px = cs.fs or 16
    if cs.mono or not smooth then return "m" .. monoSize(px) end
    if cs.bold then return "b" .. nearest(SIZES_B, px) end
    if px > 28 then return "l" .. nearest(SIZES_L, px) end
    return "r" .. nearest(SIZES_R, px)
  end
  local curFont
  local function setFont(key)
    if key == curFont then return end
    curFont = key
    if key:sub(1, 1) == "m" then gfx.font(""); return end
    local kind, size = key:sub(1, 1), key:sub(2)
    local file = FONTDIR .. (kind == "b" and "lato-bold-" or kind == "l" and "lato-light-" or "lato-") .. size .. ".vlw"
    if not gfx.font(file) then gfx.font(""); curFont = "m" .. monoSize(tonumber(size) or 16) end
  end
  local function monoOf(key) return key:sub(1, 1) == "m" and tonumber(key:sub(2)) or nil end
  local headless = {}
  local function measure(s, key)
    if not gfxOpen then
      local m = monoOf(key)
      local px = m and m * 6 or (tonumber(key:sub(2)) or 16) * 0.5
      return #s * px
    end
    setFont(key)
    local m = monoOf(curFont)
    if m then return gfx.textWidth(s, m) end
    return gfx.textWidth(s)
  end
  local function fontHeight(key)
    if not gfxOpen then local m = monoOf(key); return m and m * 8 or (tonumber(key:sub(2)) or 16) * 1.2 end
    setFont(key)
    local m = monoOf(curFont)
    if m then return 8 * m end
    return gfx.fontHeight()
  end

  -- the size of a picture: from the card, or unknown for a web picture that has not come yet
  local sizeCache = {}
  local function intrinsic(n, url)
    if not url or url == "" then return nil end
    local c = sizeCache[url]
    if c ~= nil then if c then return c[1], c[2] end return nil end
    local w, h
    if not url:find("^%a+://") and term and term.imageSize then
      local ok, a, b = pcall(term.imageSize, url)
      if ok and a then w, h = a, b end
    end
    if not w and url:find("^https?://") then
      if term and term.imageStatus and term.imageStatus(url) ~= "ready" then return 160, 120 end
      w, h = 160, 120
    end
    sizeCache[url] = w and { w, h } or false
    return w, h
  end

  -- ---------------------------------------------------------------- the console of the page
  local consoleLines = {}
  local function hostLog(line, isError)
    consoleLines[#consoleLines + 1] = line
    if #consoleLines > 500 then table.remove(consoleLines, 1) end
    if opts.dump then print(line) end
  end

  -- ---------------------------------------------------------------- headless dump
  local W, H_ = 800, 480
  local alertHandler
  local function newPage(url)
    local page = H.new({ vw = W, vh = H_, read = readUrl, request = request, log = hostLog, fontOf = fontOf, measure = measure, fontHeight = fontHeight,
      intrinsic = intrinsic, storage = storagePath, readFile = function(p) return fs and fs.read and fs.read(p) end, writeFile = writeFile,
      now = function() return sys and sys.millis and sys.millis() or 0 end,
      alert = function(kind, text, value) return alertHandler(kind, text, value) end })
    page:load(url)
    return page
  end

  if opts.dump then
    alertHandler = function(kind, text, value) print("[" .. kind .. "] " .. text); if kind == "prompt" then return value end return kind == "confirm" end
    local page = newPage(absPath(target))
    for _ = 1, 5 do page:tick((sys and sys.millis and sys.millis() or 0) + 1000) end
    page:layout()
    local D = (HTML_DRIVERS and HTML_DRIVERS.htmldom or driver.load("htmldom"))
    local t = D.byTag(page.doc, "title")[1]
    print("title: " .. (t and D.textOf(t) or ""))
    print(string.format("page: %dx%d", W, math.floor(page.docH or 0)))
    local function dump(b, ind)
      local n = b.n
      local tag = n and (n.tag or n.type) or "?"
      if b.anon then tag = "(text)" end
      local id = n and n.attrs and n.attrs.id and ("#" .. n.attrs.id) or ""
      print(string.format("%s%s%s %d,%d %dx%d", ind, tag, id, math.floor(b.x + 0.5), math.floor(b.y + 0.5), math.floor(b.w + 0.5), math.floor(b.h + 0.5)))
      local line = {}
      for _, t in ipairs(b.texts) do line[#line + 1] = t.s end
      if #line > 0 then print(ind .. "  \"" .. table.concat(line, " "):sub(1, 120) .. "\"") end
      for _, k in ipairs(b.kids) do dump(k, ind .. "  ") end
    end
    dump(page.root, "")
    return
  end

  -- ---------------------------------------------------------------- the screen
  if not (gfx and gfx.open) then print(NAME .. ": this program needs the screen (gfx)") return end
  local gw, gh = gfx.open("native")
  if not gw then print(NAME .. ": " .. tostring(gh)) return end
  gfxOpen = true
  W, H_ = gw, gh
  if W < 100 then W, H_ = 800, 480 end
  -- smooth fonts when they are on the card (or can be fetched once)
  do
    local ok, drv = pcall(driver.load, "fonts")
    fontsDrv = ok and drv or nil
    local need = { "lato-12", "lato-14", "lato-16", "lato-18", "lato-20", "lato-24", "lato-bold-12", "lato-bold-14", "lato-bold-16", "lato-bold-18",
      "lato-bold-20", "lato-bold-24", "lato-bold-32", "lato-light-32", "lato-light-44" }
    if fontsDrv then
      FONTDIR = fontsDrv.dir or FONTDIR
      local missing = false
      for _, f in ipairs(need) do if not fontsDrv.have(f) then missing = true end end
      if missing and net and net.connected and net.connected() then
        gfx.clear(0xffffff)
        gfx.text(20, 20, "Fetching the fonts of the html player...", 0x000000, 2)
        gfx.flush()
        pcall(fontsDrv.ensure, need)
        missing = false
        for _, f in ipairs(need) do if not fontsDrv.have(f) then missing = true end end
      end
      smooth = not missing
    end
    if smooth and not gfx.font(FONTDIR .. "lato-16.vlw") then smooth = false end
    gfx.font("")
    curFont = nil
  end

  local api = {
    fill = function(x, y, w, h, c) gfx.fill(x, y, w, h, c) end,
    rect = function(x, y, w, h, c) gfx.rect(x, y, w, h, c) end,
    round = function(x, y, w, h, r, c) if gfx.round then gfx.round(x, y, w, h, math.floor(r), c) else gfx.fill(x, y, w, h, c) end end,
    alpha = function(x, y, w, h, c, a) if gfx.alpha then gfx.alpha(x, y, w, h, c, a) end end,
    line = function(x1, y1, x2, y2, c) gfx.line(x1, y1, x2, y2, c) end,
    triangle = function(a, b, c, d, e, f, col) gfx.triangle(a, b, c, d, e, f, col) end,
    disc = function(x, y, r, c) gfx.disc(x, y, r, c) end,
    circle = function(x, y, r, c) gfx.circle(x, y, r, c) end,
    gradient = function(x, y, w, h, c1, c2, horiz) if gfx.gradient then gfx.gradient(x, y, w, h, c1, c2, horiz and "h" or nil) else gfx.fill(x, y, w, h, c1) end end,
    clip = function(x, y, w, h) if not gfx.clip then return end if x then gfx.clip(x, y, w, h) else gfx.clip() end end,
    tw = function(s, font) return measure(s, font) end,
    fh = function(font) return fontHeight(font) end,
    text = function(x, y, s, c, font)
      local fh = fontHeight(font)
      -- the firmware moves a text that hangs below the screen up into it: such a line is left out instead
      if y + fh > H_ or y < -fh then return end
      setFont(font)
      gfx.text(x, y, s, c, monoOf(curFont) or 1)
    end,
    image = function(src, x, y, w, h, cover)
      if not gfx.image or w < 1 or h < 1 then return false end
      if src:find("^https?://") then
        local st = term and term.imageStatus and term.imageStatus(src)
        if st ~= "ready" then
          if st ~= "failed" and term.imageFetch then term.imageFetch(src) end
          return false
        end
      end
      local ok, r = pcall(gfx.image, src, x, y, w, h, cover and "cover" or nil)
      return ok and r
    end,
  }

  -- ---------------------------------------------------------------- dialogs (alert, confirm, prompt) and the console
  local function wrapText(s, maxw, font)
    local lines = {}
    for para in (s .. "\n"):gmatch("([^\n]*)\n") do
      local line = ""
      for word in para:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if measure(try, font) > maxw and line ~= "" then lines[#lines + 1] = line; line = word else line = try end
      end
      lines[#lines + 1] = line
    end
    return lines
  end
  local page
  local function readKey()
    local k = key.poll()
    if k then return k end
    if touch and touch.read then
      local ok, x, y = pcall(touch.read)
      if ok and type(x) == "number" then
        -- wait for the finger to go up: the tap is the answer
        repeat sys.sleep(15); ok, x = pcall(touch.read) until not (ok and type(x) == "number")
        return "tap"
      end
    end
    return nil
  end
  alertHandler = function(kind, text, value)
    local font = smooth and "r18" or "m2"
    local bold = smooth and "b18" or "m2"
    local bw = 560
    local lines = wrapText(text, bw - 40, font)
    local fh = fontHeight(font)
    local input = value or ""
    local answer
    local frame = 0
    while true do
      page:paint(api, nil, false)
      local bh = 70 + #lines * (fh + 4) + (kind == "prompt" and fh + 16 or 0)
      local bx, by = math.floor((W - bw) / 2), math.floor((H_ - bh) / 2)
      gfx.alpha(0, 0, W, H_, 0x000000, 110)
      api.round(bx, by, bw, bh, 10, 0xffffff)
      local y = by + 16
      for _, l in ipairs(lines) do api.text(bx + 20, y, l, 0x202020, font); y = y + fh + 4 end
      if kind == "prompt" then
        api.round(bx + 20, y + 4, bw - 40, fh + 8, 4, 0xeeeeee)
        api.text(bx + 26, y + 8, input .. ((frame // 15) % 2 == 0 and "|" or ""), 0x000000, font)
      end
      local hint = kind == "alert" and "OK (Enter)" or "OK (Enter)   Cancel (Esc)"
      api.text(bx + bw - 20 - measure(hint, bold), by + bh - fh - 12, hint, 0x1a73e8, bold)
      gfx.flush()
      local k = readKey()
      if k == "enter" or k == "tap" then answer = kind == "prompt" and input or true; break end
      if k == "esc" or k == "ctrl-q" or k == "ctrl-c" then answer = kind == "prompt" and nil or false; break end
      if kind == "prompt" and k then
        if k == "backspace" then input = input:sub(1, (utf8.offset(input, -1) or 1) - 1)
        elseif #k == 1 or utf8.len(k) == 1 then input = input .. k end
      elseif kind == "confirm" and (k == "y" or k == "n") then answer = k == "y"; break end
      frame = frame + 1
      sys.sleep(30)
    end
    page.needPaint = true
    return answer
  end
  local showConsole = false
  local function drawConsole()
    local font = "m1"
    local n = 14
    local y0 = H_ - n * 12 - 10
    gfx.alpha(0, y0, W, H_ - y0, 0x000000, 200)
    local lines = page.logLines
    local first = math.max(1, #lines - n + 1)
    local y = y0 + 6
    for i = first, #lines do
      local l = lines[i]
      local c = l:find("^%[script error") and 0xff6060 or l:find("^error:") and 0xff6060 or l:find("^warning:") and 0xffd060 or 0xe0e0e0
      setFont(font)
      gfx.text(6, y, l:sub(1, 130), c, 1)
      y = y + 12
    end
    setFont(font)
    gfx.text(W - 210, y0 + 6, "console (Ctrl+O hides it)", 0x9090ff, 1)
  end
  local function drawToast(text, color)
    local font = smooth and "r14" or "m1"
    local fh = fontHeight(font)
    local w = math.min(W - 20, measure(text, font) + 20)
    gfx.alpha(10, H_ - fh - 18, w, fh + 10, 0x000000, 200)
    api.clip(10, H_ - fh - 18, w, fh + 10)
    api.text(20, H_ - fh - 13, text, color or 0xffffff, font)
    api.clip()
  end

  -- ---------------------------------------------------------------- the loop
  local history = {}
  page = newPage(absPath(target))
  local quit = false
  local lastPaint, lastFlush = 0, 0
  local touchDown, tx0, ty0 = false, 0, 0
  local caretOn, caretAt = true, 0
  local toastUntil = 0
  local function goTo(nav)
    if nav.quit then quit = true return end
    local url
    if nav.back then
      url = table.remove(history)
      if not url then page.toast = "no page to go back to"; return end
    else
      if not nav.reload then history[#history + 1] = page.url end
      url = nav.url
    end
    consoleLines[#consoleLines + 1] = "-- " .. url
    gfx.fill(0, 0, W, 3, 0x1a73e8)
    gfx.flush()
    page = newPage(url)
    page.needPaint = true
  end
  while not quit do
    local now = sys.millis()
    -- keys
    local k = key.poll()
    local guard = 0
    while k and guard < 20 do
      guard = guard + 1
      if k == "ctrl-q" then quit = true; break
      elseif k == "ctrl-o" then showConsole = not showConsole; page.needPaint = true
      elseif k == "ctrl-r" then page.navTo = { url = page.url, reload = true }
      else
        local r = page:key(k)
        if r == "back" then page.navTo = page.navTo or { back = true }
        elseif r == "quit" then quit = true; break end
      end
      if page.navTo then break end
      k = key.poll()
    end
    if quit then break end
    -- the finger
    if touch and touch.read then
      local ok, x, y = pcall(touch.read)
      if ok and type(x) == "table" then local p = x[1] or x; x, y = p.x or p[1], p.y or p[2] end
      if ok and type(x) == "number" and type(y) == "number" then
        if not touchDown then touchDown = true; tx0, ty0 = x, y; page:down(x, y)
        elseif x ~= tx0 or y ~= ty0 then page:move(x, y); tx0, ty0 = x, y end
      elseif touchDown then
        touchDown = false
        page:up(tx0, ty0)
      end
    end
    -- timers, animation frames, requests
    page:tick(now)
    if page.navTo then
      local nav = page.navTo
      page.navTo = nil
      goTo(nav)
    end
    if quit then break end
    -- the caret of a text field blinks
    if page:isEditing() and now - caretAt > 500 then caretOn = not caretOn; caretAt = now; page.needPaint = true end
    if page.lastError and page.lastErrorAt and page.lastErrorAt >= toastUntil - 4000 and now < (page.lastErrorAt + 4000) then toastUntil = page.lastErrorAt + 4000 end
    -- pictures from the web that have arrived
    if page.needImages then
      page.needImages = false
      local D = (HTML_DRIVERS and HTML_DRIVERS.htmldom or driver.load("htmldom"))
      for _, img in ipairs(D.byTag(page.doc, "img")) do
        local src = img.attrs.src
        if src and src ~= "" then
          local u = page:abs(src)
          if u:find("^https?://") and term and term.imageFetch then term.imageFetch(u) end
          if u:find("^https?://") then page.waitImages = page.waitImages or {}; page.waitImages[u] = true end
        end
      end
    end
    if page.waitImages and now - (page.imgCheck or 0) > 300 then
      page.imgCheck = now
      for u in pairs(page.waitImages) do
        local st = term and term.imageStatus and term.imageStatus(u)
        if st == "ready" or st == "failed" or st == nil then page.waitImages[u] = nil; page.needPaint = true end
      end
    end
    local rect, any = page:dirtyRect()
    if any then
      if showConsole or (now < toastUntil) or page.toast then rect = nil end
      page:paint(api, rect, caretOn)
      if showConsole then drawConsole() end
      if page.toast then drawToast(page.toast); toastUntil = math.max(toastUntil, now + 2500); page.lastToast = page.toast; page.toast = nil
      elseif now < toastUntil then drawToast(page.lastError or page.lastToast or "", page.lastError and 0xff8080 or nil) end
      gfx.flush()
      lastPaint, lastFlush = now, now
    elseif now - lastFlush > 250 then
      -- a toast that ran out, and the screen kept alive
      if toastUntil > 0 and now >= toastUntil then toastUntil = 0; page.lastError = nil; page.needPaint = true end
      gfx.flush()
      lastFlush = now
    end
    -- about 30 frames a second while the page animates, less when it waits
    local due = page:nextDue(sys.millis())
    local wait = 33 - (sys.millis() - now)
    if due and due > wait and not touchDown then wait = math.min(due, 60) end
    if not page:busy() and not touchDown then wait = 30 end
    if wait < 1 then wait = 1 end
    sys.sleep(math.floor(wait))
  end
  gfx.close()
  if opts.console then
    for _, l in ipairs(consoleLines) do print(l) end
  end
end
return M
