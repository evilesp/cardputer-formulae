#!lua
-- git: a small READ-ONLY client for public GitHub repositories (there is no real git on this board).
-- clone, pull, status, diff and log work through the GitHub web API and raw.githubusercontent.com; no key, no commits, no push.

local VERSION = "git version 2.47.1"
local MAX_FILES, MAX_BYTES = 1000, 1048576
local HELP = [[
usage: git [-v | --version] [-h | --help] [-C <path>] <command> [<args>]

These are common Git commands used in various situations:

start a working area
   clone      Clone a repository into a new directory

examine the history and state
   diff       Show changes between the working tree and the last pull
   log        Show commit logs
   status     Show the working tree status

grow and tweak your common history
   branch     List the branch (read-only here)

collaborate
   pull       Fetch from and integrate with the remote repository

This is a read-only client for public GitHub repositories:
add, commit, push, merge and checkout are not available.
'git help -a' and 'git help <command>' list subcommands and concepts.]]

local function die(msg, code)
  io.stderr:write(msg .. "\n")
  os.exit(code or 128)
end

-- ---------------------------------------------------------------- JSON (just enough for the GitHub API)
local function jsonDecode(s)
  local i = 1
  local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
  local value
  local function str()
    local out, j = {}, i + 1
    while true do
      local c = s:sub(j, j)
      if c == '"' then break end
      if c == "" then error("bad json") end
      if c == "\\" then
        local n = s:sub(j + 1, j + 1)
        if n == "u" then
          local cp = tonumber(s:sub(j + 2, j + 5), 16) or 63
          out[#out + 1] = cp < 128 and string.char(cp) or utf8.char(cp)
          j = j + 6
        else
          out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[n] or n
          j = j + 2
        end
      else
        out[#out + 1] = c
        j = j + 1
      end
    end
    i = j + 1
    return table.concat(out)
  end
  function value()
    ws()
    local c = s:sub(i, i)
    if c == "{" then
      local t = {}
      i = i + 1
      ws()
      if s:sub(i, i) == "}" then i = i + 1 return t end
      while true do
        ws()
        local k = str()
        ws()
        i = i + 1 -- the colon
        t[k] = value()
        ws()
        local d = s:sub(i, i)
        i = i + 1
        if d == "}" then return t end
      end
    elseif c == "[" then
      local t = {}
      i = i + 1
      ws()
      if s:sub(i, i) == "]" then i = i + 1 return t end
      while true do
        t[#t + 1] = value()
        ws()
        local d = s:sub(i, i)
        i = i + 1
        if d == "]" then return t end
      end
    elseif c == '"' then
      return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4 return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5 return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4 return nil
    end
    local num = s:match("^-?[%d.eE+-]+", i)
    if not num then error("bad json") end
    i = i + #num
    return tonumber(num)
  end
  local ok, v = pcall(value)
  if ok then return v end
  return nil
end

-- ---------------------------------------------------------------- network
local function request(url, wantBody)
  local status, body = net.request({ url = url, maxBytes = MAX_BYTES + 65536, follow = true,
                                     headers = { ["User-Agent"] = "git/2.47.1", ["Accept"] = "application/vnd.github+json" } })
  if not status then die("fatal: unable to access '" .. url .. "': " .. tostring(body)) end
  return status, body
end

local function api(owner, repo, path)
  local url = "https://api.github.com/repos/" .. owner .. "/" .. repo .. path
  local status, body = request(url)
  if status == 404 then
    die("remote: Repository not found.\nfatal: repository 'https://github.com/" .. owner .. "/" .. repo .. "/' not found")
  elseif status == 403 or status == 429 then
    die("fatal: unable to access 'https://github.com/" .. owner .. "/" .. repo .. "/': GitHub API rate limit exceeded; try again later")
  elseif status ~= 200 then
    die("fatal: unable to access 'https://github.com/" .. owner .. "/" .. repo .. "/': The requested URL returned error: " .. status)
  end
  local data = jsonDecode(body)
  if data == nil then die("fatal: unexpected answer from github.com") end
  return data
end

local function urlEncode(path)
  return (path:gsub("[^%w%-%._~/]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- ---------------------------------------------------------------- files
local function readFile(p)
  local d = fs.read(p)
  return d
end

local function parent(p)
  return p:match("^(.*)/[^/]*$") or ""
end

local function writeFile(p, data)
  local dir = parent(p)
  if dir ~= "" and not fs.exists(dir) then fs.mkdir(dir, true) end
  local ok, e = fs.write(p, data)
  if not ok then die("error: unable to write '" .. p .. "': " .. tostring(e)) end
end

local function join(a, b)
  if a == "" or a == "." then return b end
  if a:sub(-1) == "/" then return a .. b end
  return a .. "/" .. b
end

-- a clone keeps its bookkeeping in .git/esp: remote, head, tree (sha size path per line) and orig/ (the files as downloaded)
local function metaDir(root) return join(root, ".git/esp") end

local function findRoot(start)
  local dir = start
  while true do
    if fs.exists(join(dir, ".git/esp/remote")) then return dir end
    local up = parent(dir)
    if up == dir or dir == "" or dir == "/" then return nil end
    dir = up
  end
end

local function loadMeta(root)
  local meta = { root = root }
  local line = (readFile(join(metaDir(root), "remote")) or ""):match("[^\n]+") or ""
  meta.owner, meta.repo, meta.branch = line:match("^(%S+) (%S+) (%S+)")
  meta.head = (readFile(join(metaDir(root), "head")) or ""):match("%x+") or ""
  meta.tree, meta.order = {}, {}
  for l in (readFile(join(metaDir(root), "tree")) or ""):gmatch("[^\n]+") do
    local sha, size, path = l:match("^(%x+) (%d+) (.+)$")
    if sha then
      meta.tree[path] = { sha = sha, size = tonumber(size) }
      meta.order[#meta.order + 1] = path
    end
  end
  return meta
end

local function saveMeta(meta)
  local lines = {}
  table.sort(meta.order)
  for _, p in ipairs(meta.order) do
    local e = meta.tree[p]
    lines[#lines + 1] = e.sha .. " " .. e.size .. " " .. p
  end
  local d = metaDir(meta.root)
  writeFile(join(d, "remote"), meta.owner .. " " .. meta.repo .. " " .. meta.branch .. "\n")
  writeFile(join(d, "head"), meta.head .. "\n")
  writeFile(join(d, "tree"), table.concat(lines, "\n") .. "\n")
  writeFile(join(meta.root, ".git/HEAD"), "ref: refs/heads/" .. meta.branch .. "\n")
end

-- ---------------------------------------------------------------- the remote
local function parseUrl(u)
  local o, r = u:match("^https?://github%.com/([^/]+)/([^/]+)")
  if not o then o, r = u:match("^git@github%.com:([^/]+)/([^/]+)") end
  if not o then o, r = u:match("^([%w%-_.]+)/([%w%-_.]+)$") end
  if r then r = r:gsub("%.git$", ""):gsub("[?#].*$", "") end
  return o, r
end

-- the default branch, the head commit and the list of files
local function fetchRemote(owner, repo)
  local info = api(owner, repo, "")
  local branch = info.default_branch or "main"
  local commits = api(owner, repo, "/commits?per_page=1&sha=" .. branch)
  local head = commits[1] and commits[1].sha or ""
  local tree = api(owner, repo, "/git/trees/" .. branch .. "?recursive=1")
  local files, skipped, count = {}, 0, 0
  for _, e in ipairs(tree.tree or {}) do
    if e.type == "blob" then
      count = count + 1
      if (e.size or 0) > MAX_BYTES then skipped = skipped + 1
      else files[#files + 1] = { path = e.path, sha = e.sha, size = e.size or 0 } end
    end
  end
  if count > MAX_FILES then
    die("fatal: repository has " .. count .. " files, more than the " .. MAX_FILES .. " this device takes")
  end
  return { branch = branch, head = head, files = files, skipped = skipped, truncated = tree.truncated }
end

local function fetchFile(owner, repo, branch, path)
  local url = "https://raw.githubusercontent.com/" .. owner .. "/" .. repo .. "/" .. branch .. "/" .. urlEncode(path)
  local status, body = request(url)
  if status ~= 200 then die("error: unable to download '" .. path .. "' (HTTP " .. tostring(status) .. ")") end
  return body
end

-- ---------------------------------------------------------------- a line diff (LCS), unified output
local function splitLines(s)
  local t = {}
  for l in (s .. (s:sub(-1) == "\n" and "" or "\n")):gmatch("(.-)\n") do t[#t + 1] = l end
  if s == "" then t = {} end
  return t
end

-- edit script: a list of { op = " " | "-" | "+", text = line }
local function lineDiff(a, b)
  local n, m = #a, #b
  local top = 0
  while top < n and top < m and a[top + 1] == b[top + 1] do top = top + 1 end
  local bot = 0
  while bot < n - top and bot < m - top and a[n - bot] == b[m - bot] do bot = bot + 1 end
  local ops = {}
  for i = 1, top do ops[#ops + 1] = { " ", a[i] } end
  local na, nb = n - top - bot, m - top - bot
  if na * nb > 250000 then  -- too big for the table: show the middle as replaced
    for i = 1, na do ops[#ops + 1] = { "-", a[top + i] } end
    for j = 1, nb do ops[#ops + 1] = { "+", b[top + j] } end
  else
    local L = {}
    for i = 0, na do L[i] = {} for j = 0, nb do L[i][j] = 0 end end
    for i = na - 1, 0, -1 do
      for j = nb - 1, 0, -1 do
        if a[top + i + 1] == b[top + j + 1] then L[i][j] = L[i + 1][j + 1] + 1
        else L[i][j] = math.max(L[i + 1][j], L[i][j + 1]) end
      end
    end
    local i, j = 0, 0
    while i < na or j < nb do
      if i < na and j < nb and a[top + i + 1] == b[top + j + 1] then
        ops[#ops + 1] = { " ", a[top + i + 1] }
        i, j = i + 1, j + 1
      elseif i < na and (j >= nb or L[i + 1][j] >= L[i][j + 1]) then
        ops[#ops + 1] = { "-", a[top + i + 1] }
        i = i + 1
      else
        ops[#ops + 1] = { "+", b[top + j + 1] }
        j = j + 1
      end
    end
  end
  for i = n - bot + 1, n do ops[#ops + 1] = { " ", a[i] } end
  return ops
end

local function unified(ops)
  local out, CTX = {}, 3
  local i, total = 1, #ops
  local aLine, bLine = {}, {}
  local a, b = 1, 1
  for k = 1, total do
    aLine[k], bLine[k] = a, b
    if ops[k][1] ~= "+" then a = a + 1 end
    if ops[k][1] ~= "-" then b = b + 1 end
  end
  while i <= total do
    while i <= total and ops[i][1] == " " do i = i + 1 end
    if i > total then break end
    local from = math.max(1, i - CTX)
    local last = i
    local j = i
    while j <= total do
      if ops[j][1] ~= " " then last = j end
      if j - last > 2 * CTX then break end
      j = j + 1
    end
    local to = math.min(total, last + CTX)
    local na, nb = 0, 0
    for k = from, to do
      if ops[k][1] ~= "+" then na = na + 1 end
      if ops[k][1] ~= "-" then nb = nb + 1 end
    end
    local sa = na == 0 and aLine[from] - 1 or aLine[from]
    local sb = nb == 0 and bLine[from] - 1 or bLine[from]
    out[#out + 1] = string.format("@@ -%s +%s @@", na == 1 and sa or (sa .. "," .. na), nb == 1 and sb or (sb .. "," .. nb))
    for k = from, to do out[#out + 1] = ops[k][1] .. ops[k][2] end
    i = to + 1
  end
  return out
end

local function isBinary(s) return s:find("\0", 1, true) ~= nil end

-- ---------------------------------------------------------------- the working tree against the snapshot
local function walk(root, rel, out)
  local list = fs.list(rel == "" and root or join(root, rel)) or {}
  for _, name in ipairs(list) do
    local isDir = name:sub(-1) == "/"
    name = name:gsub("/$", "")
    local p = rel == "" and name or (rel .. "/" .. name)
    if p ~= ".git" then
      if isDir then walk(root, p, out) else out[#out + 1] = p end
    end
  end
end

local function changes(meta)
  local modified, deleted, untracked = {}, {}, {}
  for _, p in ipairs(meta.order) do
    local now = readFile(join(meta.root, p))
    if now == nil then
      deleted[#deleted + 1] = p
    else
      local orig = readFile(join(metaDir(meta.root), "orig/" .. p))
      if orig ~= now then modified[#modified + 1] = p end
    end
  end
  local all = {}
  walk(meta.root, "", all)
  for _, p in ipairs(all) do
    if not meta.tree[p] then untracked[#untracked + 1] = p end
  end
  table.sort(untracked)
  return modified, deleted, untracked
end

-- ---------------------------------------------------------------- commands
local function cmdClone(args)
  local url, dir
  for _, a in ipairs(args) do
    if a:sub(1, 1) ~= "-" then
      if not url then url = a elseif not dir then dir = a end
    end
  end
  if not url then die("fatal: You must specify a repository to clone.\n\nusage: git clone [<options>] [--] <repo> [<dir>]", 129) end
  local owner, repo = parseUrl(url)
  if not owner then die("fatal: unable to access '" .. url .. "': only github.com repositories can be cloned here") end
  dir = dir or repo
  local shown = dir
  dir = fs.abspath(dir)
  if fs.exists(dir) and #(fs.list(dir) or {}) > 0 then
    die("fatal: destination path '" .. shown .. "' already exists and is not an empty directory.")
  end
  print("Cloning into '" .. shown .. "'...")
  local remote = fetchRemote(owner, repo)
  local meta = { root = dir, owner = owner, repo = repo, branch = remote.branch, head = remote.head, tree = {}, order = {} }
  fs.mkdir(dir, true)
  local bytes = 0
  for n, f in ipairs(remote.files) do
    local body = fetchFile(owner, repo, remote.branch, f.path)
    writeFile(join(dir, f.path), body)
    writeFile(join(metaDir(dir), "orig/" .. f.path), body)
    meta.tree[f.path] = { sha = f.sha, size = #body }
    meta.order[#meta.order + 1] = f.path
    bytes = bytes + #body
    if n % 10 == 0 then print(string.format("Receiving files: %d%% (%d/%d)", n * 100 // #remote.files, n, #remote.files)) end
  end
  saveMeta(meta)
  print(string.format("Receiving files: 100%% (%d/%d), %.2f KiB, done.", #remote.files, #remote.files, bytes / 1024))
  if remote.skipped > 0 then print("warning: " .. remote.skipped .. " file(s) over 1 MiB were left out") end
  if remote.truncated then print("warning: the file list from GitHub was cut short; some files are missing") end
end

local function needRoot()
  local root = findRoot(fs.cwd())
  if not root then die("fatal: not a git repository (or any of the parent directories): .git") end
  return loadMeta(root)
end

local function cmdStatus()
  local meta = needRoot()
  local modified, deleted, untracked = changes(meta)
  print("On branch " .. meta.branch)
  if #modified + #deleted + #untracked == 0 then
    print("Your branch is up to date with 'origin/" .. meta.branch .. "'.\n\nnothing to commit, working tree clean")
    return
  end
  print("Your branch is up to date with 'origin/" .. meta.branch .. "'.\n")
  if #modified + #deleted > 0 then
    print("Changes not staged for commit:")
    print("  (use \"git add <file>...\" to update what will be committed)")
    print("  (use \"git restore <file>...\" to discard changes in working directory)")
    local rows = {}
    for _, p in ipairs(modified) do rows[#rows + 1] = { p, "modified:   " .. p } end
    for _, p in ipairs(deleted) do rows[#rows + 1] = { p, "deleted:    " .. p } end
    table.sort(rows, function(x, y) return x[1] < y[1] end)
    for _, r in ipairs(rows) do print("\t" .. r[2]) end
    print("")
  end
  if #untracked > 0 then
    print("Untracked files:")
    print("  (use \"git add <file>...\" to include in what will be committed)")
    for _, p in ipairs(untracked) do print("\t" .. p) end
    print("")
    if #modified + #deleted == 0 then print("nothing added to commit but untracked files present (use \"git add\" to track)") end
  end
  if #modified + #deleted > 0 then print("no changes added to commit (use \"git add\" and/or \"git commit -a\")") end
end

local function wanted(p, filters)
  if #filters == 0 then return true end
  for _, f in ipairs(filters) do
    f = f:gsub("^%./", ""):gsub("/$", "")
    if f == "." or p == f or p:sub(1, #f + 1) == f .. "/" then return true end
  end
  return false
end

local function cmdDiff(args)
  local meta = needRoot()
  local filters = {}
  for _, a in ipairs(args) do if a:sub(1, 1) ~= "-" then filters[#filters + 1] = a end end
  local modified, deleted = changes(meta)
  local all = {}
  for _, p in ipairs(modified) do all[#all + 1] = { p, false } end
  for _, p in ipairs(deleted) do all[#all + 1] = { p, true } end
  table.sort(all, function(x, y) return x[1] < y[1] end)
  for _, e in ipairs(all) do
    local p = e[1]
    if wanted(p, filters) then
      local orig = readFile(join(metaDir(meta.root), "orig/" .. p)) or ""
      local now = e[2] and "" or (readFile(join(meta.root, p)) or "")
      print("diff --git a/" .. p .. " b/" .. p)
      if e[2] then print("deleted file mode 100644") end
      if isBinary(orig) or isBinary(now) then
        print("Binary files a/" .. p .. " and b/" .. p .. " differ")
      else
        print("--- a/" .. p)
        print("+++ " .. (e[2] and "/dev/null" or ("b/" .. p)))
        for _, l in ipairs(unified(lineDiff(splitLines(orig), splitLines(now)))) do print(l) end
      end
    end
  end
end

-- "2026-11-10T12:00:00Z" -> "Tue Nov 10 12:00:00 2026 +0000"
local function gitDate(iso)
  local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return iso end
  y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
  local yy, mm = y, mo
  if mm < 3 then yy = yy - 1 end
  local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
  local wd = (yy + yy // 4 - yy // 100 + yy // 400 + t[mo] + d) % 7
  local DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
  local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
  return string.format("%s %s %d %s:%s:%s %d +0000", DAYS[wd + 1], MONTHS[mo], d, h, mi, s, y)
end

local function cmdLog(args)
  local meta = needRoot()
  local count, oneline = 10, false
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--oneline" then oneline = true
    elseif a == "-n" then i = i + 1; count = tonumber(args[i]) or count
    elseif a:match("^%-n%d+$") then count = tonumber(a:sub(3))
    elseif a:match("^%-%d+$") then count = tonumber(a:sub(2))
    elseif a:match("^%-%-max%-count=%d+$") then count = tonumber(a:match("%d+")) end
    i = i + 1
  end
  count = math.max(1, math.min(count, 100))
  local list = api(meta.owner, meta.repo, "/commits?per_page=" .. count .. "&sha=" .. meta.branch)
  for n, c in ipairs(list) do
    local msg = (c.commit and c.commit.message) or ""
    local au = (c.commit and c.commit.author) or {}
    local tag = n == 1 and (" (HEAD -> " .. meta.branch .. ", origin/" .. meta.branch .. ")") or ""
    if oneline then
      print(c.sha:sub(1, 7) .. tag .. " " .. (msg:match("[^\n]*")))
    else
      print("commit " .. c.sha .. tag)
      print("Author: " .. (au.name or "?") .. " <" .. (au.email or "?") .. ">")
      print("Date:   " .. gitDate(au.date or ""))
      print("")
      for l in (msg .. "\n"):gmatch("(.-)\n") do print("    " .. l) end
      if n < #list then print("") end
    end
  end
end

local function cmdPull()
  local meta = needRoot()
  local remote = fetchRemote(meta.owner, meta.repo)
  if remote.head == meta.head and remote.branch == meta.branch then
    print("Already up to date.")
    return
  end
  local fresh, add, mod, del = {}, {}, {}, {}
  for _, f in ipairs(remote.files) do
    fresh[f.path] = f
    local old = meta.tree[f.path]
    if not old then add[#add + 1] = f.path
    elseif old.sha ~= f.sha then mod[#mod + 1] = f.path end
  end
  for _, p in ipairs(meta.order) do if not fresh[p] then del[#del + 1] = p end end
  -- a file that changed upstream and here too would be overwritten: stop before touching anything
  local clash = {}
  local changed = {}
  for _, p in ipairs(mod) do changed[#changed + 1] = p end
  for _, p in ipairs(del) do changed[#changed + 1] = p end
  for _, p in ipairs(changed) do
    local now = readFile(join(meta.root, p))
    local orig = readFile(join(metaDir(meta.root), "orig/" .. p))
    if now ~= orig then clash[#clash + 1] = p end
  end
  if #clash > 0 then
    local msg = { "error: Your local changes to the following files would be overwritten by merge:" }
    for _, p in ipairs(clash) do msg[#msg + 1] = "\t" .. p end
    msg[#msg + 1] = "Please undo your changes (git cannot stash here) before you merge."
    msg[#msg + 1] = "Aborting"
    die(table.concat(msg, "\n"), 1)
  end
  print("From https://github.com/" .. meta.owner .. "/" .. meta.repo)
  print(string.format("   %s..%s  %s       -> origin/%s", meta.head:sub(1, 7), remote.head:sub(1, 7), remote.branch, remote.branch))
  print("Updating " .. meta.head:sub(1, 7) .. ".." .. remote.head:sub(1, 7))
  print("Fast-forward")
  local rows, ins, dels = {}, 0, 0
  local function stat(p, old, new)
    local ops = lineDiff(splitLines(old), splitLines(new))
    local a, d = 0, 0
    for _, o in ipairs(ops) do if o[1] == "+" then a = a + 1 elseif o[1] == "-" then d = d + 1 end end
    ins, dels = ins + a, dels + d
    local bar = string.rep("+", math.min(a, 30)) .. string.rep("-", math.min(d, 30))
    rows[#rows + 1] = { p, a + d, bar }
  end
  for _, p in ipairs(add) do
    local body = fetchFile(meta.owner, meta.repo, remote.branch, p)
    writeFile(join(meta.root, p), body)
    writeFile(join(metaDir(meta.root), "orig/" .. p), body)
    meta.tree[p] = { sha = fresh[p].sha, size = #body }
    meta.order[#meta.order + 1] = p
    stat(p, "", isBinary(body) and "" or body)
  end
  for _, p in ipairs(mod) do
    local old = readFile(join(metaDir(meta.root), "orig/" .. p)) or ""
    local body = fetchFile(meta.owner, meta.repo, remote.branch, p)
    writeFile(join(meta.root, p), body)
    writeFile(join(metaDir(meta.root), "orig/" .. p), body)
    meta.tree[p] = { sha = fresh[p].sha, size = #body }
    stat(p, isBinary(old) and "" or old, isBinary(body) and "" or body)
  end
  for _, p in ipairs(del) do
    local old = readFile(join(metaDir(meta.root), "orig/" .. p)) or ""
    fs.remove(join(meta.root, p))
    fs.remove(join(metaDir(meta.root), "orig/" .. p))
    meta.tree[p] = nil
    stat(p, isBinary(old) and "" or old, "")
  end
  local order = {}
  for p in pairs(meta.tree) do order[#order + 1] = p end
  meta.order, meta.head, meta.branch = order, remote.head, remote.branch
  saveMeta(meta)
  table.sort(rows, function(x, y) return x[1] < y[1] end)
  local width = 0
  for _, r in ipairs(rows) do width = math.max(width, #r[1]) end
  for _, r in ipairs(rows) do print(string.format(" %-" .. width .. "s | %d %s", r[1], r[2], r[3])) end
  local n = #rows
  print(string.format(" %d file%s changed, %d insertion%s(+), %d deletion%s(-)", n, n == 1 and "" or "s",
                      ins, ins == 1 and "" or "s", dels, dels == 1 and "" or "s"))
  if remote.skipped > 0 then print("warning: " .. remote.skipped .. " file(s) over 1 MiB were left out") end
end

-- ---------------------------------------------------------------- main
local args = {}
for i = 1, #arg do args[i] = arg[i] end
if args[1] == "-C" and args[2] then
  local ok, e = fs.chdir(args[2])
  if not ok then die("fatal: cannot change to '" .. args[2] .. "': No such file or directory") end
  table.remove(args, 1)
  table.remove(args, 1)
end
local sub = table.remove(args, 1)
if sub == nil then
  print(HELP)
  os.exit(1)
elseif sub == "--version" or sub == "version" then
  print(VERSION)
elseif sub == "--help" or sub == "help" or sub == "-h" then
  print(HELP)
elseif sub == "clone" then cmdClone(args)
elseif sub == "pull" then cmdPull()
elseif sub == "status" then cmdStatus()
elseif sub == "diff" then cmdDiff(args)
elseif sub == "log" then cmdLog(args)
elseif sub == "branch" then
  local meta = needRoot()
  print("* " .. meta.branch)
elseif sub == "commit" or sub == "add" or sub == "push" or sub == "init" or sub == "checkout" or sub == "merge" then
  die("fatal: this git is read-only: '" .. sub .. "' is not available on this device", 128)
else
  die("git: '" .. sub .. "' is not a git command. See 'git --help'.", 1)
end
