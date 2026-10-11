#!lua
-- memcleaner: frees room on the SD card. It looks for what nothing needs and asks about every file, one at a time:
--   y  delete this file      n  keep it      s  skip all the questions that are left      q  quit
-- It finds: empty files, copies (the same content as another file), the cache of the browser and the logs, temporary files
-- (/tmp, *.tmp, *~) and half-downloaded packages (*.part), and files nobody has touched for half a year. The system is left
-- alone: /etc, the installed programs, the settings (names that start with a dot) and the packages' own data are never offered.
--   memcleaner            scan and ask
--   memcleaner --dry      scan and ask, but delete nothing
-- Needs firmware v0.1.0.14(beta) (fs.info, fs.hash and fs.remove). Run it with --selftest to check the rules.

local DAY = 86400
local OLD_DAYS = 180                  -- a file older than this and not touched is offered
local HASH_LIMIT = 1024 * 1024        -- a bigger file is not compared with others
local MAX_FINDINGS, MAX_TRACKED, MAX_FILES, MAX_DIRS, MAX_DEPTH = 200, 250, 3000, 400, 10

-- the kinds, in the order they are asked about
local KINDS = { "empty", "dup", "cache", "temp", "part", "old" }
local TITLE = { empty = "EMPTY FILE", dup = "COPY", cache = "CACHE", temp = "TEMPORARY", part = "UNFINISHED DOWNLOAD", old = "NOT TOUCHED FOR LONG" }
local COLOR = { empty = "magenta", dup = "yellow", cache = "cyan", temp = "cyan", part = "red", old = "dim" }
local WHY = {
  empty = "It holds nothing.",
  dup = "Same content as another file.",
  cache = "Fetched again when it is needed.",
  temp = "A temporary file.",
  part = "A download that never finished.",
  old = "Nobody has written to it for ages.",
}
local ORDER = {}
for i, k in ipairs(KINDS) do ORDER[k] = i end

-- where the scan looks; the system folders are there only for the *.part files that an interrupted brew leaves
local ROOTS = { "/home", "/tmp", "/var/cache", "/var/log", "/mnt", "/usr/local/bin", "/usr/local/lib/drivers", "/var/lib/brew/index" }
local SYSTEM_TOP = { bin = true, usr = true, etc = true, home = true, tmp = true, var = true, mnt = true, dev = true, proc = true, lib = true }

local function under(path, dir)
  return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end

local function baseName(path)
  return path:match("[^/]*$")
end

-- the system and the settings: never offered (a *.part file is the one thing taken from the system folders)
local function isProtected(path)
  for _, dir in ipairs({ "/etc", "/bin", "/usr", "/dev", "/proc", "/var/lib", "/boot", "/lib" }) do
    if under(path, dir) then return true end
  end
  return baseName(path):sub(1, 1) == "."
end

-- what kind of leftover a file is, or nil when nothing about it says it can go. e is { size, mtime }; now is 0 if the clock is not set.
local function classify(path, e, now)
  local name = baseName(path)
  if name:sub(-5) == ".part" then return "part" end
  if isProtected(path) then return nil end
  if under(path, "/var/cache") or under(path, "/var/log") then return "cache" end
  if under(path, "/tmp") or name:sub(-4) == ".tmp" or name:sub(-1) == "~" then return "temp" end
  if e.size == 0 then return "empty" end
  if now > 0 and e.mtime > 0 and now - e.mtime > OLD_DAYS * DAY then return "old" end
  return nil
end

-- of two files with the same content, the one to keep: the shorter path, then the one that comes first
local function keeper(a, b)
  if #a ~= #b then return #a < #b and a or b end
  return a < b and a or b
end

local function humanSize(n)
  if n >= 1073741824 then return string.format("%.1fG", n / 1073741824) end
  if n >= 1048576 then return string.format("%.1fM", n / 1048576) end
  if n >= 1024 then return string.format("%.1fK", n / 1024) end
  return n .. "B"
end

-- a path cut in the middle to fit w columns
local function fit(path, w)
  if #path <= w then return path end
  local tail = math.floor((w - 2) * 2 / 3)
  return path:sub(1, w - 2 - tail) .. ".." .. path:sub(-tail)
end

local function bar(frac, width)
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local n = math.floor(frac * width + 0.5)
  return string.rep("#", n) .. string.rep(".", width - n)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local now = 1800000000
  check(classify("/home/user/a.txt", { size = 0, mtime = now }, now) == "empty", "an empty file")
  check(classify("/home/user/a.txt", { size = 5, mtime = now - 200 * DAY }, now) == "old", "an old file")
  check(classify("/home/user/a.txt", { size = 5, mtime = now - 100 * DAY }, now) == nil, "a file of 100 days stays")
  check(classify("/home/user/a.txt", { size = 5, mtime = now - 999 * DAY }, 0) == nil, "no clock, no age")
  check(classify("/home/user/a.txt", { size = 5, mtime = 0 }, now) == nil, "no time on the file, no age")
  check(classify("/home/user/.profile", { size = 0, mtime = 1 }, now) == nil, "a setting is never offered")
  check(classify("/home/user/.remote", { size = 0, mtime = 1 }, now) == nil, "a dot file is protected")
  check(classify("/etc/hostname", { size = 0, mtime = 1 }, now) == nil, "/etc is protected")
  check(classify("/usr/local/bin/doom", { size = 9, mtime = 1 }, now) == nil, "a program is protected")
  check(classify("/var/lib/brew/installed", { size = 9, mtime = 1 }, now) == nil, "the brew list is protected")
  check(classify("/usr/local/bin/doom.part", { size = 9, mtime = now }, now) == "part", "an unfinished download is offered")
  check(classify("/var/lib/brew/index/tap0.txt.part", { size = 9, mtime = now }, now) == "part", "an unfinished index too")
  check(classify("/var/cache/browser/x", { size = 9, mtime = now }, now) == "cache", "cache")
  check(classify("/var/log/boot", { size = 9, mtime = now }, now) == "cache", "a log")
  check(classify("/tmp/x", { size = 9, mtime = now }, now) == "temp", "a file in /tmp")
  check(classify("/home/user/x.tmp", { size = 9, mtime = now }, now) == "temp", "a .tmp file")
  check(classify("/home/user/x~", { size = 9, mtime = now }, now) == "temp", "a backup with ~")
  check(classify("/tmpfile", { size = 9, mtime = now }, now) == nil, "/tmpfile is not in /tmp")
  check(keeper("/a/b.txt", "/a/bb.txt") == "/a/b.txt" and keeper("/a/y", "/a/x") == "/a/x", "the shorter path is kept, then the first")
  check(humanSize(0) == "0B" and humanSize(1500) == "1.5K" and humanSize(3 * 1048576) == "3.0M", "sizes")
  check(fit("/short", 20) == "/short" and #fit(string.rep("a", 60), 30) == 30, "a long path is cut to fit")
  check(bar(0.5, 10) == "#####....." and bar(2, 4) == "####" and bar(-1, 4) == "....", "the bar")
  if failed == 0 then print("selftest ok") end
  return
end

if not term or not fs.info or not fs.remove or not fs.hash then
  print("memcleaner needs firmware v0.1.0.14(beta) or newer: SystemUpdateBeta")
  return
end

local DRY = arg[1] == "--dry"
if arg[1] and not DRY then
  print("usage: memcleaner [--dry]")
  return
end

local COLS = 40
local now = sys.time()

-- ---- drawing ----

local function put(x, y, text, color)
  term.text(x, y, text, color or "text")
end

local function header(sub)
  put(1, 0, "MEMORY CLEANER", "white")
  if DRY then put(17, 0, "(dry run)", "yellow") end
  put(COLS - 1 - #sub, 0, sub, "dim")
  put(0, 1, string.rep("=", COLS), "cyan")
end

local function meters()
  local free, total = sys.heap()
  put(1, 2, "RAM", "dim")
  put(5, 2, "[" .. bar(total > 0 and (total - free) / total or 0, 12) .. "]", "green")
  put(20, 2, string.format("%d KB free", free), "text")
  local sdTotal, sdUsed = sys.sd()
  put(1, 3, "SD", "dim")
  if sdTotal then
    put(5, 3, "[" .. bar(sdUsed / sdTotal, 12) .. "]", "green")
    put(20, 3, humanSize(sdTotal - sdUsed) .. " free", "text")
  else
    put(5, 3, "no card", "red")
  end
  put(0, 4, string.rep("-", COLS), "dim")
end

local function pollQuit()
  local k = key.poll()
  while k do
    if k == "ctrl-q" or k == "q" or k == "Q" then error("quit", 0) end
    k = key.poll()
  end
end

-- ---- the scan ----

local findings = { path = {}, kind = {}, size = {}, info = {} }
local counts = { files = 0, dirs = 0, hashed = 0, capped = false }
local tracked, trackedCount = {}, 0

local function addFinding(path, kind, size, info)
  if #findings.path >= MAX_FINDINGS then
    counts.capped = true
    return
  end
  local i = #findings.path + 1
  findings.path[i], findings.kind[i], findings.size[i], findings.info[i] = path, kind, size, info or false
end

local spin = 1
local function scanScreen(label)
  term.clear()
  header("scanning")
  meters()
  put(1, 6, label, "white")
  put(1, 8, string.format("files %-6d folders %-5d", counts.files, counts.dirs), "text")
  put(1, 9, string.format("found %d", #findings.path), "green")
  put(1, 11, ("|/-\\"):sub(spin, spin) .. " looking...", "cyan")
  put(1, 15, "q quit", "dim")
  term.flush()
  spin = spin % 4 + 1
end

local function walk(root, depth, label)
  local entries = fs.info(root)
  if not entries then return end
  counts.dirs = counts.dirs + 1
  for _, e in ipairs(entries) do
    if counts.files >= MAX_FILES or counts.dirs >= MAX_DIRS then
      counts.capped = true
      return
    end
    local path = (root == "/" and "" or root) .. "/" .. e.name
    if e.dir then
      if depth < MAX_DEPTH and e.name:sub(1, 1) ~= "." then walk(path, depth + 1, label) end
    else
      counts.files = counts.files + 1
      local kind = classify(path, e, now)
      if kind then
        addFinding(path, kind, e.size, kind == "old" and string.format("not changed for %d days", (now - e.mtime) // DAY) or nil)
      elseif e.size > 0 and e.size <= HASH_LIMIT and not isProtected(path) and trackedCount < MAX_TRACKED then
        local list = tracked[e.size]
        if not list then
          list = {}
          tracked[e.size] = list
        end
        list[#list + 1] = path
        trackedCount = trackedCount + 1
      end
      if counts.files % 8 == 0 then
        pollQuit()
        scanScreen(fit(root, COLS - 2))
      end
    end
  end
end

-- the files of the same size are compared by their content
local function findCopies()
  local groups = 0
  for _, paths in pairs(tracked) do
    if #paths > 1 then groups = groups + 1 end
  end
  local done = 0
  for size, paths in pairs(tracked) do
    if #paths > 1 then
      done = done + 1
      local byHash, order = {}, {}
      for _, p in ipairs(paths) do
        pollQuit()
        scanScreen("comparing " .. done .. "/" .. groups)
        local h = fs.hash(p)
        if h then
          counts.hashed = counts.hashed + 1
          if not byHash[h] then
            byHash[h] = {}
            order[#order + 1] = h
          end
          local list = byHash[h]
          list[#list + 1] = p
        end
      end
      for _, h in ipairs(order) do
        local list = byHash[h]
        if #list > 1 then
          local keep = list[1]
          for i = 2, #list do keep = keeper(keep, list[i]) end
          for _, p in ipairs(list) do
            if p ~= keep then addFinding(p, "dup", size, "same as " .. keep) end
          end
        end
      end
    end
  end
  tracked = nil
end

local function scan()
  local tops = {}
  for _, r in ipairs(ROOTS) do tops[#tops + 1] = r end
  local rootEntries = fs.info("/") or {}
  for _, e in ipairs(rootEntries) do
    if e.dir and not SYSTEM_TOP[e.name] and e.name:sub(1, 1) ~= "." and e.name ~= "System Volume Information" then
      tops[#tops + 1] = "/" .. e.name
    elseif not e.dir then
      local path = "/" .. e.name
      counts.files = counts.files + 1
      local kind = classify(path, e, now)
      if kind then addFinding(path, kind, e.size, kind == "old" and string.format("not changed for %d days", (now - e.mtime) // DAY) or nil) end
    end
  end
  for _, r in ipairs(tops) do walk(r, 1, r) end
  findCopies()
  collectgarbage()
  -- the order of the questions: by kind, the biggest first
  local order = {}
  for i = 1, #findings.path do order[i] = i end
  table.sort(order, function(a, b)
    local ka, kb = ORDER[findings.kind[a]], ORDER[findings.kind[b]]
    if ka ~= kb then return ka < kb end
    if findings.size[a] ~= findings.size[b] then return findings.size[a] > findings.size[b] end
    return findings.path[a] < findings.path[b]
  end)
  return order
end

-- ---- the questions ----

local totals = { deleted = 0, freed = 0, kept = 0, skipped = 0, failed = 0 }

local function questionScreen(n, total, i, note)
  local kind, path, size, info = findings.kind[i], findings.path[i], findings.size[i], findings.info[i]
  term.clear()
  header(string.format("%d of %d", n, total))
  meters()
  put(1, 5, TITLE[kind], COLOR[kind])
  put(1, 6, "[" .. bar((n - 1) / total, 14) .. "]", COLOR[kind])
  put(1, 8, fit(path, COLS - 2), "white")
  put(1, 9, "size " .. humanSize(size), "text")
  if info then put(1, 10, fit(info, COLS - 2), "dim") end
  put(1, 11, WHY[kind], "dim")
  if note then put(1, 12, note, "red") end
  put(1, 13, string.format("freed %s in %d file%s", humanSize(totals.freed), totals.deleted, totals.deleted == 1 and "" or "s"), "green")
  put(0, 14, string.rep("-", COLS), "dim")
  put(1, 15, "y delete  n keep  s skip rest  q quit", "yellow")
  term.flush()
end

local function ask(order)
  local total = #order
  local n = 1
  local note
  while n <= total do
    local i = order[n]
    questionScreen(n, total, i, note)
    note = nil
    local k = key.poll()
    if k then
      k = k:lower()
      if k == "y" then
        if DRY then
          totals.deleted, totals.freed = totals.deleted + 1, totals.freed + findings.size[i]
          n = n + 1
        else
          local ok, err = fs.remove(findings.path[i])
          if ok then
            totals.deleted, totals.freed = totals.deleted + 1, totals.freed + findings.size[i]
            n = n + 1
          else
            totals.failed = totals.failed + 1
            note = "cannot delete: " .. fit(tostring(err), 22)
            n = n + 1
          end
        end
      elseif k == "n" then
        totals.kept = totals.kept + 1
        n = n + 1
      elseif k == "s" then
        totals.skipped = totals.skipped + (total - n + 1)
        return
      elseif k == "q" or k == "ctrl-q" then
        error("quit", 0)
      end
    else
      sys.sleep(20)
    end
  end
end

local function summary(count)
  term.clear()
  header("done")
  meters()
  if count == 0 then
    put(1, 6, "Nothing to clean.", "green")
    put(1, 8, "Every file has a reason to be there.", "dim")
    if now == 0 then put(1, 10, "The clock is not set: old files were not checked.", "yellow") end
  else
    put(1, 6, string.format("%s %d file%s", DRY and "Would delete" or "Deleted", totals.deleted, totals.deleted == 1 and "" or "s"), "green")
    put(1, 7, string.format("%s %s", DRY and "Would free" or "Freed", humanSize(totals.freed)), "green")
    put(1, 9, string.format("kept %d   skipped %d", totals.kept, totals.skipped), "text")
    if totals.failed > 0 then put(1, 10, string.format("%d could not be deleted", totals.failed), "red") end
    if counts.capped then put(1, 11, "The scan stopped at its limit; run it again.", "yellow") end
  end
  put(1, 15, "press a key", "dim")
  term.flush()
  while not key.poll() do
    sys.sleep(30)
    term.flush()
  end
end

-- ---- the program ----

term.fullscreen(true)
local ok, err = pcall(function()
  local order = scan()
  if #order == 0 then
    summary(0)
    return
  end
  ask(order)
  summary(#order)
end)
term.fullscreen(false)
if not ok and tostring(err) ~= "quit" and not tostring(err):find("interrupted", 1, true) then print("memcleaner: " .. tostring(err)) end
if totals.deleted > 0 then print(string.format("memcleaner: %s %d file%s, %s", DRY and "would delete" or "deleted", totals.deleted, totals.deleted == 1 and "" or "s", humanSize(totals.freed))) end
