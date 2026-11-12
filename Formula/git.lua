#!lua
-- git: a small git for this device. Local repositories work for real: init, add, commit, branch, switch/checkout, merge, diff, log, show,
-- rm, mv, restore, reset, tag, stash, config, remote, clean. The .git folder is the real layout (HEAD, refs, config, index, loose objects:
-- the zlib data is stored without compression, which every git reads). Public GitHub repositories can be cloned and pulled through the
-- GitHub web API (no key); push is not possible here (no git transport).

local VERSION = "git version 2.47.1"
local MAX_FILES, MAX_BYTES = 1000, 1048576
local HELP = [[
usage: git [-v | --version] [-h | --help] [-C <path>] [-c <name>=<value>]
           <command> [<args>]

These are common Git commands used in various situations:

start a working area (see also: git help tutorial)
   clone     Clone a repository into a new directory
   init      Create an empty Git repository or reinitialize an existing one

work on the current change (see also: git help everyday)
   add       Add file contents to the index
   mv        Move or rename a file, a directory, or a symlink
   restore   Restore working tree files
   rm        Remove files from the working tree and from the index

examine the history and state (see also: git help revisions)
   diff      Show changes between commits, commit and working tree, etc
   log       Show commit logs
   show      Show various types of objects
   status    Show the working tree status

grow, mark and tweak your common history
   branch    List, create, or delete branches
   commit    Record changes to the repository
   merge     Join two or more development histories together
   reset     Reset current HEAD to the specified state
   switch    Switch branches
   tag       Create, list, delete or verify a tag object signed with GPG

collaborate (see also: git help workflows)
   fetch     Download objects and refs from another repository
   pull      Fetch from and integrate with another repository or a local branch
   push      Update remote refs along with associated objects

'git help -a' and 'git help -g' list available subcommands and some
concept guides. See 'git help <command>' or 'git help <concept>'
to read about a specific subcommand or concept.
See 'git help git' for an overview of the system.]]

local function die(msg, code)
  io.stderr:write(msg .. "\n")
  os.exit(code or 128)
end
local function eprint(msg) io.stderr:write(msg .. "\n") end
local function plural(n, w) return n .. " " .. w .. (n == 1 and "" or "s") end
local function yield(n) if n % 128 == 0 and sys and sys.yield then sys.yield() end end

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

-- ---------------------------------------------------------------- files and paths
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

local function normalize(p)
  local parts = {}
  for seg in p:gmatch("[^/]+") do
    if seg == ".." then parts[#parts] = nil elseif seg ~= "." then parts[#parts + 1] = seg end
  end
  return "/" .. table.concat(parts, "/")
end

-- the content of a file in the working tree, nil when it is not there (fs.read alone may answer for a missing one)
local function readWork(p)
  if not fs.exists(p) or fs.isdir(p) then return nil end
  return fs.read(p)
end

local function sortedKeys(t)
  local k = {}
  for p in pairs(t) do k[#k + 1] = p end
  table.sort(k)
  return k
end

-- remove empty folders from the file upwards, up to (not including) the stop folder
local function pruneDirs(dir, stop)
  while dir ~= stop and #dir > #stop do
    local l = fs.list(dir)
    if l and #l == 0 and fs.rmdir then fs.rmdir(dir) else break end
    dir = parent(dir)
  end
end

-- ---------------------------------------------------------------- SHA-1, adler32 and stored zlib
local M32 = 0xffffffff
local function rotl32(x, n) return ((x << n) | (x >> (32 - n))) & M32 end
local function sha1(msg)
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
  local len = #msg
  msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64) .. string.pack(">I8", len * 8)
  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do w[i] = string.unpack(">I4", msg, chunk + i * 4) end
    for i = 16, 79 do w[i] = rotl32(w[i - 3] ~ w[i - 8] ~ w[i - 14] ~ w[i - 16], 1) end
    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i < 20 then f, k = (b & c) | ((~b) & d), 0x5A827999
      elseif i < 40 then f, k = b ~ c ~ d, 0x6ED9EBA1
      elseif i < 60 then f, k = (b & c) | (b & d) | (c & d), 0x8F1BBCDC
      else f, k = b ~ c ~ d, 0xCA62C1D6 end
      local t = (rotl32(a, 5) + (f & M32) + e + k + w[i]) & M32
      e, d, c, b, a = d, c, rotl32(b, 30), a, t
    end
    h0, h1, h2, h3, h4 = (h0 + a) & M32, (h1 + b) & M32, (h2 + c) & M32, (h3 + d) & M32, (h4 + e) & M32
    yield(chunk // 64 + 1)
  end
  return string.format("%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4)
end

local function tobin(hex) return (hex:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)) end
local function tohex(bin) return (bin:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end

local function adler32(s)
  local a, b, i, n = 1, 0, 1, #s
  while i <= n do
    local j = math.min(i + 2047, n)
    for _, c in ipairs({ s:byte(i, j) }) do a = a + c; b = b + a end
    a, b = a % 65521, b % 65521
    i = j + 1
    yield(i // 2048)
  end
  return b * 65536 + a
end

local function deflateStored(s)
  local parts, pos = { "\120\1" }, 1
  repeat
    local chunk = s:sub(pos, pos + 65534)
    local final = pos + 65535 > #s
    parts[#parts + 1] = string.char(final and 1 or 0) .. string.pack("<I2I2", #chunk, (~#chunk) & 0xffff) .. chunk
    pos = pos + 65535
  until final
  parts[#parts + 1] = string.pack(">I4", adler32(s))
  return table.concat(parts)
end

local function inflateStored(z)
  if #z < 6 or (z:byte(1) & 15) ~= 8 then return nil end
  local pos, out = 3, {}
  while true do
    local b = z:byte(pos)
    if not b or ((b >> 1) & 3) ~= 0 then return nil end
    local len = string.unpack("<I2", z, pos + 1)
    out[#out + 1] = z:sub(pos + 5, pos + 4 + len)
    pos = pos + 5 + len
    if b & 1 == 1 then break end
  end
  return table.concat(out)
end

local function hashBlob(data) return sha1("blob " .. #data .. "\0" .. data) end
local function abbrev(sha) return sha:sub(1, 7) end
local function isBinary(s) return s:find("\0", 1, true) ~= nil end

-- ---------------------------------------------------------------- the repository
local R = nil          -- { root = "/home/user/x", gd = "/home/user/x/.git" }
local fetchHook = {}   -- sha -> path of a blob that is still to be downloaded (pull)
local objCache = {}
local fetchBlobFile    -- set below, downloads from GitHub

local function objPath(sha) return R.gd .. "/objects/" .. sha:sub(1, 2) .. "/" .. sha:sub(3) end

local function getObject(sha)
  if not sha or #sha < 4 then return nil end
  local c = objCache[sha]
  if c then return c[1], c[2] end
  local z = fs.exists(objPath(sha)) and readFile(objPath(sha)) or nil
  if not z then return nil end
  local raw = inflateStored(z)
  if not raw then die("error: object file " .. objPath(sha) .. " is compressed; this device reads only objects it wrote itself", 128) end
  local typ, size, nul = raw:match("^(%a+) (%d+)()\0")
  if not typ then die("fatal: loose object " .. sha .. " is corrupt") end
  local data = raw:sub(nul + 1)
  if #data < 4096 then objCache[sha] = { typ, data } end
  return typ, data
end

local function putObject(typ, data)
  local raw = typ .. " " .. #data .. "\0" .. data
  local sha = sha1(raw)
  local p = objPath(sha)
  if not fs.exists(p) then writeFile(p, deflateStored(raw)) end
  return sha
end

local function putBlobKnown(sha, data)
  local p = objPath(sha)
  if not fs.exists(p) then writeFile(p, deflateStored("blob " .. #data .. "\0" .. data)) end
end

local function getBlob(sha)
  local typ, data = getObject(sha)
  if typ == "blob" then return data end
  if not typ and fetchHook[sha] then
    local body = fetchBlobFile(fetchHook[sha])
    putBlobKnown(sha, body)
    return body
  end
  return nil
end

-- tree objects
local function parseTree(data)
  local t, i = {}, 1
  while i <= #data do
    local sp = data:find(" ", i, true)
    local nul = data:find("\0", sp, true)
    t[#t + 1] = { mode = data:sub(i, sp - 1), name = data:sub(sp + 1, nul - 1), sha = tohex(data:sub(nul + 1, nul + 20)) }
    i = nul + 21
  end
  return t
end

local function flatten(treeSha, prefix, out)
  local typ, data = getObject(treeSha)
  if typ ~= "tree" then return out end
  for _, e in ipairs(parseTree(data)) do
    if e.mode == "40000" then flatten(e.sha, prefix .. e.name .. "/", out)
    else out[prefix .. e.name] = { sha = e.sha, mode = e.mode } end
  end
  return out
end

local function buildTree(entries)  -- entries: path -> { sha, mode }
  local root = { dirs = {}, files = {} }
  for _, p in ipairs(sortedKeys(entries)) do
    local node, parts = root, {}
    for seg in p:gmatch("[^/]+") do parts[#parts + 1] = seg end
    for i = 1, #parts - 1 do
      node.dirs[parts[i]] = node.dirs[parts[i]] or { dirs = {}, files = {} }
      node = node.dirs[parts[i]]
    end
    node.files[parts[#parts]] = entries[p]
  end
  local function write(node)
    local items = {}
    for name, e in pairs(node.files) do items[#items + 1] = { key = name, name = name, mode = e.mode, sha = e.sha } end
    for name, child in pairs(node.dirs) do items[#items + 1] = { key = name .. "/", name = name, mode = "40000", sha = write(child) } end
    table.sort(items, function(a, b) return a.key < b.key end)
    local parts = {}
    for _, it in ipairs(items) do parts[#parts + 1] = it.mode .. " " .. it.name .. "\0" .. tobin(it.sha) end
    return putObject("tree", table.concat(parts))
  end
  return write(root)
end

-- commits
local function parseCommit(sha, data)
  local head, msg = data:match("^(.-)\n\n(.*)$")
  if not head then head, msg = data, "" end
  local c = { sha = sha, parents = {}, msg = msg }
  for line in (head .. "\n"):gmatch("(.-)\n") do
    local k, v = line:match("^(%S+) (.*)$")
    if k == "tree" then c.tree = v
    elseif k == "parent" then c.parents[#c.parents + 1] = v
    elseif k == "author" then c.author = v
    elseif k == "committer" then c.committer = v end
  end
  local who, ts, tz = (c.author or ""):match("^(.-) (%d+) ([+-]%d+)$")
  c.who, c.ts, c.tz = who or (c.author or "?"), tonumber(ts) or 0, tz or "+0000"
  local cts = (c.committer or ""):match(" (%d+) [+-]%d+$")
  c.cts = tonumber(cts) or c.ts
  return c
end

local commitCache = {}
local function getCommit(sha)
  if not sha then return nil end
  if commitCache[sha] then return commitCache[sha] end
  local typ, data = getObject(sha)
  if typ == "tag" then
    local o = data:match("^object (%x+)")
    return getCommit(o)
  end
  if typ ~= "commit" then return nil end
  local c = parseCommit(sha, data)
  commitCache[sha] = c
  return c
end
local function subject(c) return (c.msg:match("^[^\n]*")) end

-- ---------------------------------------------------------------- the esp bookkeeping of a clone (the commit objects of GitHub are not here)
local function metaDir() return join(R.gd, "esp") end
local metaCache
local function loadMeta()
  if metaCache then return metaCache end
  local meta = { tree = {}, order = {} }
  local line = (readFile(join(metaDir(), "remote")) or ""):match("[^\n]+") or ""
  meta.owner, meta.repo, meta.branch = line:match("^(%S+) (%S+) (%S+)")
  meta.head = (readFile(join(metaDir(), "head")) or ""):match("%x+") or ""
  for l in (readFile(join(metaDir(), "tree")) or ""):gmatch("[^\n]+") do
    local sha, size, path = l:match("^(%x+) (%d+) (.+)$")
    if sha then
      meta.tree[path] = { sha = sha, size = tonumber(size) }
      meta.order[#meta.order + 1] = path
    end
  end
  metaCache = meta
  return meta
end

local function saveMeta(meta)
  local lines = {}
  table.sort(meta.order)
  for _, p in ipairs(meta.order) do
    local e = meta.tree[p]
    lines[#lines + 1] = e.sha .. " " .. e.size .. " " .. p
  end
  local d = metaDir()
  writeFile(join(d, "remote"), meta.owner .. " " .. meta.repo .. " " .. meta.branch .. "\n")
  writeFile(join(d, "head"), meta.head .. "\n")
  writeFile(join(d, "tree"), table.concat(lines, "\n") .. "\n")
  metaCache = meta
end

local function metaFlat()
  local out = {}
  for p, e in pairs(loadMeta().tree) do out[p] = { sha = e.sha, mode = "100644" } end
  return out
end

-- the files of a commit: path -> { sha, mode }
local flatCache = {}
local function commitFlat(sha)
  if not sha then return {} end
  if flatCache[sha] then return flatCache[sha] end
  local c = getCommit(sha)
  local out
  if c then out = flatten(c.tree, "", {})
  elseif fs.exists(join(metaDir(), "head")) and loadMeta().head == sha then out = metaFlat()
  else return nil end
  flatCache[sha] = out
  return out
end

-- ---------------------------------------------------------------- the index (real format, version 2)
local function loadIndex()
  local d = fs.exists(R.gd .. "/index") and readFile(R.gd .. "/index") or nil
  local idx = {}
  if not d or #d < 32 or d:sub(1, 4) ~= "DIRC" then return idx end
  local count = string.unpack(">I4", d, 9)
  local pos = 13
  for _ = 1, count do
    local mode = string.unpack(">I4", d, pos + 24)
    local size = string.unpack(">I4", d, pos + 36)
    local sha = tohex(d:sub(pos + 40, pos + 59))
    local flags = string.unpack(">I2", d, pos + 60)
    local nlen = flags & 0xfff
    local name = nlen == 0xfff and d:match("^[^\0]*", pos + 62) or d:sub(pos + 62, pos + 61 + nlen)
    idx[name] = { sha = sha, mode = string.format("%o", mode), size = size }
    pos = pos + ((62 + #name + 8) // 8) * 8
  end
  return idx
end

local function saveIndex(idx)
  local names = sortedKeys(idx)
  local parts = { "DIRC" .. string.pack(">I4I4", 2, #names) }
  for _, name in ipairs(names) do
    local e = idx[name]
    local mode = tonumber(e.mode, 8) or 33188
    local len = (62 + #name + 8) // 8 * 8
    parts[#parts + 1] = string.pack(">I4I4I4I4I4I4I4I4I4I4", 0, 0, 0, 0, 0, 0, mode, 0, 0, e.size or 0) .. tobin(e.sha) ..
        string.pack(">I2", math.min(#name, 0xfff)) .. name .. string.rep("\0", len - 62 - #name)
  end
  local body = table.concat(parts)
  writeFile(R.gd .. "/index", body .. tobin(sha1(body)))
end

-- ---------------------------------------------------------------- config
local function parseConfig(text)
  local list, sec, sub = {}, nil, nil
  for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
    local s, q = line:match('^%s*%[([%w%.%-]+)%s+"(.*)"%]')
    if not s then s = line:match("^%s*%[([%w%.%-]+)%]") end
    if s then sec, sub = s:lower(), q
    else
      local k, v = line:match("^%s*([%w%-]+)%s*=%s*(.-)%s*$")
      if k and sec then list[#list + 1] = { sec = sec, sub = sub, key = k:lower(), val = v }
      else
        k = line:match("^%s*([%w%-]+)%s*$")
        if k and sec then list[#list + 1] = { sec = sec, sub = sub, key = k:lower(), val = "true" } end
      end
    end
  end
  return list
end

local function serializeConfig(list)
  local out, seen = {}, {}
  for _, e in ipairs(list) do
    local id = e.sec .. "\0" .. (e.sub or "")
    if not seen[id] then
      seen[id] = true
      out[#out + 1] = e.sub and ('[' .. e.sec .. ' "' .. e.sub .. '"]') or ("[" .. e.sec .. "]")
      for _, f in ipairs(list) do
        if f.sec == e.sec and f.sub == e.sub then out[#out + 1] = "\t" .. f.key .. " = " .. f.val end
      end
    end
  end
  return table.concat(out, "\n") .. (#out > 0 and "\n" or "")
end

local GLOBAL_CFG = "/home/user/.gitconfig"
local function cfgFile(global) return global and GLOBAL_CFG or (R.gd .. "/config") end
local function loadCfg(global)
  local p = cfgFile(global)
  return parseConfig(fs.exists(p) and readFile(p) or "")
end
local function splitKey(key)
  local sec, rest = key:match("^([^.]+)%.(.+)$")
  if not sec then return nil end
  local sub, k = rest:match("^(.*)%.([^.]+)$")
  if not sub then return sec:lower(), nil, rest:lower() end
  return sec:lower(), sub, k:lower()
end
local function cfgGetIn(list, key)
  local sec, sub, k = splitKey(key)
  local val
  for _, e in ipairs(list) do if e.sec == sec and e.sub == sub and e.key == k then val = e.val end end
  return val
end
local function cfgGet(key)
  local v
  if R then v = cfgGetIn(loadCfg(false), key) end
  if v == nil then v = cfgGetIn(loadCfg(true), key) end
  return v
end
local function cfgSet(key, val, global, add)
  local list = loadCfg(global)
  local sec, sub, k = splitKey(key)
  local done = false
  if not add then
    for _, e in ipairs(list) do if e.sec == sec and e.sub == sub and e.key == k then e.val = val; done = true end end
  end
  if not done then list[#list + 1] = { sec = sec, sub = sub, key = k, val = val } end
  writeFile(cfgFile(global), serializeConfig(list))
end
local function cfgUnset(key, global)
  local list, out, found = loadCfg(global), {}, false
  local sec, sub, k = splitKey(key)
  for _, e in ipairs(list) do
    if e.sec == sec and e.sub == sub and e.key == k then found = true else out[#out + 1] = e end
  end
  if found then writeFile(cfgFile(global), serializeConfig(out)) end
  return found
end
local function cfgRemoveSection(sec, sub)
  local out = {}
  for _, e in ipairs(loadCfg(false)) do
    if not (e.sec == sec and e.sub == sub) then out[#out + 1] = e end
  end
  writeFile(cfgFile(false), serializeConfig(out))
end

-- ---------------------------------------------------------------- refs
local function refSha(name)
  local p = R.gd .. "/" .. name
  local d = fs.exists(p) and readFile(p) or nil
  return d and d:match("^%x+")
end
local function setRef(name, sha) writeFile(R.gd .. "/" .. name, sha .. "\n") end
local function delRef(name) fs.remove(R.gd .. "/" .. name) end

local function listRefs(prefix, out, rel)
  out = out or {}
  rel = rel or ""
  local dir = R.gd .. "/" .. prefix .. (rel ~= "" and ("/" .. rel) or "")
  for _, name in ipairs(fs.list(dir) or {}) do
    if name:sub(-1) == "/" then listRefs(prefix, out, (rel ~= "" and (rel .. "/") or "") .. name:sub(1, -2))
    else
      local full = (rel ~= "" and (rel .. "/") or "") .. name
      local sha = refSha(prefix .. "/" .. full)
      if sha then out[full] = sha end
    end
  end
  return out
end

-- the current branch (nil when detached) and the commit HEAD points to (nil before the first commit)
local function readHead()
  local h = readFile(R.gd .. "/HEAD") or ""
  local br = h:match("^ref: refs/heads/(%S+)")
  if br then return br, refSha("refs/heads/" .. br) end
  return nil, h:match("^%x+")
end
local function headSha() local _, s = readHead() return s end
local function moveHead(sha)
  local br = readHead()
  if br then setRef("refs/heads/" .. br, sha) else writeFile(R.gd .. "/HEAD", sha .. "\n") end
end

local function peel(sha)
  local c = getCommit(sha)
  if c then return c.sha end
  return sha
end

local function prefixLookup(h)
  if #h < 4 or h:find("%X") then return nil end
  local found
  for _, name in ipairs(fs.list(R.gd .. "/objects/" .. h:sub(1, 2)) or {}) do
    if (h:sub(1, 2) .. name):sub(1, #h) == h then
      if found then return nil, true end
      found = h:sub(1, 2) .. name
    end
  end
  if not found and fs.exists(join(metaDir(), "head")) and loadMeta().head:sub(1, #h) == h then found = loadMeta().head end
  return found
end

-- a name -> a commit (or tag object) sha; "main", "v1", "origin/main", "HEAD~2", "abc1234", "HEAD^"
local function resolve(rev)
  local base, suffix = rev:match("^(.-)([~^][~^%d]*)$")
  if not base or base == "" then base, suffix = rev, "" end
  local sha
  if base == "HEAD" or base == "@" then sha = headSha()
  elseif base:match("^%x+$") and #base == 40 then sha = base
  else
    sha = refSha("refs/heads/" .. base) or refSha("refs/tags/" .. base) or refSha("refs/remotes/" .. base) or refSha(base)
    if not sha then sha = prefixLookup(base) end
  end
  if not sha then return nil end
  sha = peel(sha)
  for op, n in suffix:gmatch("([~^])(%d*)") do
    local c = getCommit(sha)
    if not c then return nil end
    if op == "~" then
      for _ = 1, tonumber(n) or 1 do
        c = getCommit(sha)
        if not c or not c.parents[1] then return nil end
        sha = c.parents[1]
      end
    else
      local k = n == "" and 1 or tonumber(n)
      if k == 0 then sha = c.sha else
        if not c.parents[k] then return nil end
        sha = c.parents[k]
      end
    end
  end
  return sha
end

-- the commits behind a sha, newest first (by commit time); a commit whose object is missing ends the walk as { sha, missing = true }
local function history(starts, limit)
  local out, seen, frontier = {}, {}, {}
  local order = 0
  local function push(sha)
    if sha and not seen[sha] then
      seen[sha] = true
      order = order + 1
      frontier[#frontier + 1] = { sha = sha, c = getCommit(sha), ord = order }
    end
  end
  for _, s in ipairs(starts) do push(s) end
  while #frontier > 0 and (not limit or #out < limit) do
    local best = 1
    for i = 2, #frontier do
      local a, b = frontier[i], frontier[best]
      local ta, tb = a.c and a.c.cts or 0, b.c and b.c.cts or 0
      if ta > tb or (ta == tb and a.ord < b.ord) then best = i end
    end
    local e = table.remove(frontier, best)
    if e.c then
      out[#out + 1] = e.c
      for _, p in ipairs(e.c.parents) do push(p) end
    else
      out[#out + 1] = { sha = e.sha, missing = true }
    end
  end
  return out
end

local function ancestors(sha)
  local set, stack = {}, { sha }
  while #stack > 0 do
    local s = table.remove(stack)
    if s and not set[s] then
      set[s] = true
      local c = getCommit(s)
      if c then for _, p in ipairs(c.parents) do stack[#stack + 1] = p end end
    end
  end
  return set
end

local function mergeBase(a, b)
  local set = ancestors(a)
  local queue, seen = { b }, {}
  local i = 1
  while queue[i] do
    local s = queue[i]
    i = i + 1
    if not seen[s] then
      seen[s] = true
      if set[s] then return s end
      local c = getCommit(s)
      if c then for _, p in ipairs(c.parents) do queue[#queue + 1] = p end end
    end
  end
  return nil
end

-- ---------------------------------------------------------------- dates and the committer
local function civil(days)
  days = days + 719468
  local era = days // 146097
  local doe = days - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  if m <= 2 then y = y + 1 end
  return y, m, d
end

-- "Tue Nov 10 12:00:00 2026 +0000"
local function epochDate(ts, tz)
  tz = tz or "+0000"
  local sign, hh, mm = tz:match("^([+-])(%d%d)(%d%d)$")
  local off = sign and ((tonumber(hh) * 3600 + tonumber(mm) * 60) * (sign == "-" and -1 or 1)) or 0
  local t = ts + off
  local days, secs = t // 86400, t % 86400
  local y, m, d = civil(days)
  local DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
  local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
  return string.format("%s %s %d %02d:%02d:%02d %d %s", DAYS[(days + 4) % 7 + 1], MONTHS[m], d, secs // 3600, secs % 3600 // 60, secs % 60, y, tz)
end

local function now()
  local t = sys and sys.time and sys.time() or 0
  if not t or t == 0 then t = os.time() end
  return t
end

local function hostName() return (sys and sys.hostname and sys.hostname()) or "arch-esp" end
local function userName() return (sys and sys.user and sys.user()) or "user" end

local function identity()
  local name, email = cfgGet("user.name"), cfgGet("user.email")
  if not email or email == "" then
    die("Author identity unknown\n\n*** Please tell me who you are.\n\nRun\n\n  git config --global user.email \"you@example.com\"\n" ..
        "  git config --global user.name \"Your Name\"\n\nto set your account's default identity.\nOmit --global to set the identity only in this repository.\n\n" ..
        "fatal: unable to auto-detect email address (got '" .. userName() .. "@" .. hostName() .. ".(none)')")
  end
  if not name or name == "" then name = userName() end
  return name .. " <" .. email .. ">"
end

local function writeCommit(treeSha, parents, msg, authorLine)
  local who = identity()
  local ts = now()
  local lines = { "tree " .. treeSha }
  for _, p in ipairs(parents) do lines[#lines + 1] = "parent " .. p end
  lines[#lines + 1] = "author " .. (authorLine or (who .. " " .. ts .. " +0000"))
  lines[#lines + 1] = "committer " .. who .. " " .. ts .. " +0000"
  lines[#lines + 1] = ""
  if msg:sub(-1) ~= "\n" then msg = msg .. "\n" end
  return putObject("commit", table.concat(lines, "\n") .. "\n" .. msg)
end

-- ---------------------------------------------------------------- repository discovery and paths
local function findRepo(start)
  local dir = normalize(start)
  while true do
    if fs.exists(join(dir, ".git/HEAD")) or fs.exists(join(dir, ".git/esp/remote")) then return dir end
    if dir == "/" or dir == "" then return nil end
    dir = parent(dir)
    if dir == "" then dir = "/" end
  end
end

local function ensureIndexFromOld()
  -- a clone made by the first version of this package has no objects and no index: build them from its copies
  if fs.exists(R.gd .. "/index") or not fs.exists(join(metaDir(), "remote")) then return end
  local meta = loadMeta()
  local idx = {}
  for _, p in ipairs(meta.order) do
    local body = readFile(join(metaDir(), "orig/" .. p)) or readFile(join(R.root, p)) or ""
    putBlobKnown(meta.tree[p].sha, body)
    idx[p] = { sha = meta.tree[p].sha, mode = "100644", size = #body }
  end
  saveIndex(idx)
  setRef("refs/heads/" .. meta.branch, meta.head)
  setRef("refs/remotes/origin/" .. meta.branch, meta.head)
  writeFile(R.gd .. "/HEAD", "ref: refs/heads/" .. meta.branch .. "\n")
  if not fs.exists(R.gd .. "/config") then
    writeFile(R.gd .. "/config", "[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = false\n" ..
      '[remote "origin"]\n\turl = https://github.com/' .. meta.owner .. "/" .. meta.repo .. ".git\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n" ..
      '[branch "' .. meta.branch .. '"]\n\tremote = origin\n\tmerge = refs/heads/' .. meta.branch .. "\n")
  end
end

local function needRepo()
  local root = findRepo(fs.cwd())
  if not root then die("fatal: not a git repository (or any of the parent directories): .git") end
  R = { root = root, gd = join(root, ".git") }
  ensureIndexFromOld()
  return R
end

local function relPath(arg)
  local abs = normalize(fs.abspath(arg))
  if abs == R.root then return "" end
  if abs:sub(1, #R.root + 1) == R.root .. "/" then return abs:sub(#R.root + 2) end
  die("fatal: " .. arg .. ": '" .. arg .. "' is outside repository at '" .. R.root .. "'")
end

-- a pathspec -> a function telling whether a repository path matches it
local function specMatcher(spec)
  local rel = relPath(spec)
  if rel == "" then return function() return true end end
  if spec:find("[%*%?]") then
    local pat = "^" .. rel:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0"):gsub("%*", ".*"):gsub("%?", "[^/]") .. "$"
    return function(p) return p:match(pat) ~= nil end
  end
  return function(p) return p == rel or p:sub(1, #rel + 1) == rel .. "/" end
end

local function matchAny(p, matchers)
  if #matchers == 0 then return true end
  for _, m in ipairs(matchers) do if m(p) then return true end end
  return false
end

-- ---------------------------------------------------------------- .gitignore
local ignoreRules
local function globToPattern(g)
  local out = {}
  local i = 1
  while i <= #g do
    local c = g:sub(i, i)
    if c == "*" then
      if g:sub(i, i + 1) == "**" then out[#out + 1] = ".*"; i = i + 1 else out[#out + 1] = "[^/]*" end
    elseif c == "?" then out[#out + 1] = "[^/]"
    elseif c:find("[%^%$%(%)%%%.%[%]%+%-]") then out[#out + 1] = "%" .. c
    else out[#out + 1] = c end
    i = i + 1
  end
  return table.concat(out)
end

local function loadIgnore()
  if ignoreRules then return ignoreRules end
  ignoreRules = {}
  for _, f in ipairs({ R.gd .. "/info/exclude", join(R.root, ".gitignore") }) do
    local text = fs.exists(f) and readFile(f) or nil
    for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
      line = line:gsub("%s+$", "")
      if line ~= "" and line:sub(1, 1) ~= "#" then
        local r = { neg = false }
        if line:sub(1, 1) == "!" then r.neg = true; line = line:sub(2) end
        if line:sub(-1) == "/" then r.dirOnly = true; line = line:sub(1, -2) end
        r.anchored = line:find("/", 1, true) ~= nil
        line = line:gsub("^/", "")
        r.pat = "^" .. globToPattern(line) .. "$"
        ignoreRules[#ignoreRules + 1] = r
      end
    end
  end
  return ignoreRules
end

local function ruleHits(p, isDir)
  local hit
  for _, r in ipairs(loadIgnore()) do
    if not (r.dirOnly and not isDir) then
      local subject = r.anchored and p or (p:match("[^/]*$"))
      if subject:match(r.pat) then hit = not r.neg end
    end
  end
  return hit
end

local function isIgnored(p, isDir)
  local acc = ""
  local parts = {}
  for seg in p:gmatch("[^/]+") do parts[#parts + 1] = seg end
  for i = 1, #parts - 1 do
    acc = acc == "" and parts[i] or (acc .. "/" .. parts[i])
    if ruleHits(acc, true) then return true end
  end
  return ruleHits(p, isDir) == true
end

-- every file of the working tree (not .git); ignored ones are skipped unless all is true
local function walkTree(rel, out, all)
  local dir = rel == "" and R.root or join(R.root, rel)
  for _, name in ipairs(fs.list(dir) or {}) do
    local isDir = name:sub(-1) == "/"
    name = name:gsub("/$", "")
    local p = rel == "" and name or (rel .. "/" .. name)
    if p ~= ".git" and name ~= ".git" then
      if all or not isIgnored(p, isDir) then
        if isDir then walkTree(p, out, all) else out[#out + 1] = p end
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------- the line diff (LCS) and unified output
local function splitLines(s)
  if s == "" then return {} end
  local t = {}
  for l in s:gmatch("([^\n]*)\n") do t[#t + 1] = l end
  if s:sub(-1) ~= "\n" then t[#t + 1] = s:match("[^\n]*$") .. "\0NONL" end
  return t
end
local function lineText(l) return (l:gsub("\0NONL$", "")) end

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
      yield(i)
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
    local func = ""
    for k = from - 1, 1, -1 do
      if ops[k][1] ~= "+" and ops[k][2]:match("^[%a_$]") then func = " " .. lineText(ops[k][2]):sub(1, 80) break end
    end
    out[#out + 1] = string.format("@@ -%s +%s @@%s", na == 1 and sa or (sa .. "," .. na), nb == 1 and sb or (sb .. "," .. nb), func)
    for k = from, to do
      out[#out + 1] = ops[k][1] .. lineText(ops[k][2])
      if ops[k][2]:sub(-5) == "\0NONL" then out[#out + 1] = "\\ No newline at end of file" end
    end
    i = to + 1
  end
  return out
end

local function countOps(ops)
  local ins, del = 0, 0
  for _, o in ipairs(ops) do
    if o[1] == "+" then ins = ins + 1 elseif o[1] == "-" then del = del + 1 end
  end
  return ins, del
end

-- ---------------------------------------------------------------- changes between two file maps (path -> { sha, mode, data? })
local function entryData(e)
  if not e then return "" end
  if e.data then return e.data end
  return getBlob(e.sha) or ""
end

-- the list of changes, sorted, with exact renames joined: { path, old, new, from (rename source) }
local function changeList(a, b, filter)
  local list, dels, adds = {}, {}, {}
  for _, p in ipairs(sortedKeys(a)) do
    if not filter or filter(p) then
      if not b[p] then list[#list + 1] = { path = p, old = a[p] }; dels[#dels + 1] = #list
      elseif a[p].sha ~= b[p].sha or a[p].mode ~= b[p].mode then list[#list + 1] = { path = p, old = a[p], new = b[p] } end
    end
  end
  for _, p in ipairs(sortedKeys(b)) do
    if (not filter or filter(p)) and not a[p] then list[#list + 1] = { path = p, new = b[p] }; adds[#adds + 1] = #list end
  end
  -- exact renames
  local usedDel = {}
  for _, ai in ipairs(adds) do
    for _, di in ipairs(dels) do
      if not usedDel[di] and list[di].old.sha == list[ai].new.sha then
        list[ai].old, list[ai].from = list[di].old, list[di].path
        list[di].dead, usedDel[di] = true, true
        break
      end
    end
  end
  local out = {}
  for _, c in ipairs(list) do if not c.dead then out[#out + 1] = c end end
  table.sort(out, function(x, y) return x.path < y.path end)
  return out
end

local function shaOf(e)
  if not e then return string.rep("0", 40) end
  if not e.sha and e.data then e.sha = hashBlob(e.data) end
  return e.sha
end

local function patchOf(ch)
  local pa, pb = ch.from or ch.path, ch.path
  local out = { "diff --git a/" .. pa .. " b/" .. pb }
  local o, n = ch.old, ch.new
  if ch.from then
    out[#out + 1] = "similarity index 100%"
    out[#out + 1] = "rename from " .. pa
    out[#out + 1] = "rename to " .. pb
    if o.mode == n.mode then return out end
  end
  if not o then out[#out + 1] = "new file mode " .. n.mode
  elseif not n then out[#out + 1] = "deleted file mode " .. o.mode
  elseif o.mode ~= n.mode then
    out[#out + 1] = "old mode " .. o.mode
    out[#out + 1] = "new mode " .. n.mode
  end
  local od, nd = entryData(o), entryData(n)
  local idxLine = "index " .. abbrev(shaOf(o)) .. ".." .. abbrev(shaOf(n))
  if o and n and o.mode == n.mode then idxLine = idxLine .. " " .. o.mode end
  if shaOf(o) == shaOf(n) then return out end
  out[#out + 1] = idxLine
  if isBinary(od) or isBinary(nd) then
    out[#out + 1] = "Binary files " .. (o and ("a/" .. pa) or "/dev/null") .. " and " .. (n and ("b/" .. pb) or "/dev/null") .. " differ"
    return out
  end
  local hunks = unified(lineDiff(splitLines(od), splitLines(nd)))
  if #hunks == 0 then return out end
  out[#out + 1] = "--- " .. (o and ("a/" .. pa) or "/dev/null")
  out[#out + 1] = "+++ " .. (n and ("b/" .. pb) or "/dev/null")
  for _, l in ipairs(hunks) do out[#out + 1] = l end
  return out
end

-- the --stat rows and the summary line
local function renameName(from, to)
  local pre = 0
  for i = 1, math.min(#from, #to) do
    if from:sub(i, i) ~= to:sub(i, i) then break end
    if from:sub(i, i) == "/" then pre = i end
  end
  local suf = 0
  local fi, ti = #from, #to
  while fi > pre and ti > pre and from:sub(fi, fi) == to:sub(ti, ti) do
    if from:sub(fi, fi) == "/" then suf = #from - fi + 1 end
    fi, ti = fi - 1, ti - 1
  end
  if pre == 0 and suf == 0 then return from .. " => " .. to end
  return from:sub(1, pre) .. "{" .. from:sub(pre + 1, #from - suf) .. " => " .. to:sub(pre + 1, #to - suf) .. "}" .. from:sub(#from - suf + 1)
end

local function statRows(changes)
  local rows, ins, del = {}, 0, 0
  for _, ch in ipairs(changes) do
    local od, nd = entryData(ch.old), entryData(ch.new)
    local name = ch.from and renameName(ch.from, ch.path) or ch.path
    if isBinary(od) or isBinary(nd) then
      rows[#rows + 1] = { name = name, bin = true, add = 0, del = 0 }
    else
      local a, d = 0, 0
      if shaOf(ch.old) ~= shaOf(ch.new) then a, d = countOps(lineDiff(splitLines(od), splitLines(nd))) end
      rows[#rows + 1] = { name = name, add = a, del = d }
      ins, del = ins + a, del + d
    end
  end
  return rows, ins, del
end

local function summaryLine(n, ins, del)
  local s = " " .. plural(n, "file") .. " changed"
  if ins > 0 or del == 0 then s = s .. ", " .. plural(ins, "insertion") .. "(+)" end
  if del > 0 or ins == 0 then s = s .. ", " .. plural(del, "deletion") .. "(-)" end
  return s
end

local function printStat(changes, withModes, short)
  if #changes == 0 then return end
  local rows, ins, del = statRows(changes)
  local namew, maxc = 0, 0
  for _, r in ipairs(rows) do
    namew = math.max(namew, #r.name)
    maxc = math.max(maxc, r.add + r.del)
  end
  local numw = #tostring(maxc)
  local graphw = math.max(6, 80 - namew - numw - 6)
  local function scale(x) return x == 0 and 0 or (1 + (x * (graphw - 1)) // maxc) end
  for _, r in ipairs(short and {} or rows) do
    if r.bin then print(string.format(" %-" .. namew .. "s | Bin", r.name))
    else
      local a, d = r.add, r.del
      if graphw <= maxc then
        local total = scale(a + d)
        if total < 2 and a > 0 and d > 0 then total = 2 end
        if a < d then a = scale(a); d = total - a else d = scale(d); a = total - d end
      end
      print(string.format(" %-" .. namew .. "s | %" .. numw .. "d %s%s", r.name, r.add + r.del, string.rep("+", a), string.rep("-", d)))
    end
  end
  print(summaryLine(#rows, ins, del))
  if withModes then
    for _, ch in ipairs(changes) do
      if ch.from then print(" rename " .. renameName(ch.from, ch.path) .. " (100%)")
      elseif not ch.old then print(" create mode " .. ch.new.mode .. " " .. ch.path)
      elseif not ch.new then print(" delete mode " .. ch.old.mode .. " " .. ch.path)
      elseif ch.old.mode ~= ch.new.mode then print(" mode change " .. ch.old.mode .. " => " .. ch.new.mode .. " " .. ch.path) end
    end
  end
end

-- ---------------------------------------------------------------- the state of the index and the working tree
local function unmergedList()
  local t = {}
  local d = fs.exists(join(metaDir(), "unmerged")) and readFile(join(metaDir(), "unmerged")) or ""
  for l in d:gmatch("[^\n]+") do t[l] = true end
  return t
end
local function saveUnmerged(set)
  local keys = sortedKeys(set)
  if #keys == 0 then if fs.exists(join(metaDir(), "unmerged")) then fs.remove(join(metaDir(), "unmerged")) end
  else writeFile(join(metaDir(), "unmerged"), table.concat(keys, "\n") .. "\n") end
end

-- what differs: staged (index against HEAD) and unstaged (working tree against the index)
local function computeStatus(idx, headFlat)
  idx = idx or loadIndex()
  headFlat = headFlat or commitFlat(headSha()) or {}
  local unmerged = unmergedList()
  local staged, unstaged = {}, {}
  for p, e in pairs(idx) do
    if not unmerged[p] then
      local h = headFlat[p]
      if not h then staged[p] = "A"
      elseif h.sha ~= e.sha or h.mode ~= e.mode then staged[p] = "M" end
    end
  end
  for p in pairs(headFlat) do if not idx[p] and not unmerged[p] then staged[p] = "D" end end
  local k = 0
  for p, e in pairs(idx) do
    if not unmerged[p] then
      local now = readWork(join(R.root, p))
      if now == nil then unstaged[p] = "D"
      else
        local blob = getBlob(e.sha)
        if blob ~= now then unstaged[p] = "M" end
      end
    end
    k = k + 1
    yield(k)
  end
  return staged, unstaged, unmerged
end

local function untrackedList(idx)
  idx = idx or loadIndex()
  local trackedDirs = {}
  for p in pairs(idx) do
    local acc = ""
    for seg in p:gmatch("[^/]+/") do
      acc = acc .. seg
      trackedDirs[acc] = true
    end
  end
  local files = walkTree("", {}, false)
  local out, seen = {}, {}
  for _, p in ipairs(files) do
    if not idx[p] then
      local shown = p
      local acc = ""
      for seg in p:gmatch("[^/]+/") do
        acc = acc .. seg
        if not trackedDirs[acc] then shown = acc break end
      end
      if not seen[shown] then seen[shown] = true; out[#out + 1] = shown end
    end
  end
  table.sort(out)
  return out
end

-- "Your branch is up to date with 'origin/main'." lines for a branch with an upstream
local function trackingLines(branch, sha)
  local remote, merge = cfgGet("branch." .. branch .. ".remote"), cfgGet("branch." .. branch .. ".merge")
  if not remote or not merge then return {} end
  local up = merge:gsub("^refs/heads/", "")
  local upName = remote .. "/" .. up
  local upSha = refSha("refs/remotes/" .. upName)
  if not upSha then return {} end
  if upSha == sha then return { "Your branch is up to date with '" .. upName .. "'." } end
  local ahead = 0
  for _, c in ipairs(history({ sha })) do
    if c.sha == upSha or c.missing then break end
    ahead = ahead + 1
  end
  if ahead > 0 and ancestors(sha)[upSha] then
    return { "Your branch is ahead of '" .. upName .. "' by " .. plural(ahead, "commit") .. ".", '  (use "git push" to publish your local commits)' }
  end
  return {}
end

-- ---------------------------------------------------------------- option parsing
-- valued: set of option names (short letters or long names) that take a value
local function parseOpts(args, valued)
  local r = { f = {}, v = {}, pos = {}, dd = {}, hasDD = false }
  local i, n = 1, #args
  local function val(name, v)
    r.v[name] = r.v[name] or {}
    table.insert(r.v[name], v)
    r.f[name] = true
  end
  while i <= n do
    local a = args[i]
    if r.hasDD then r.dd[#r.dd + 1] = a
    elseif a == "--" then r.hasDD = true
    elseif a:sub(1, 2) == "--" then
      local name, v = a:match("^%-%-([^=]+)=(.*)$")
      if name then val(name, v)
      else
        name = a:sub(3)
        if valued[name] then i = i + 1; val(name, args[i] or "") else r.f[name] = true end
      end
    elseif a:sub(1, 1) == "-" and #a > 1 then
      if a:match("^%-%d+$") then r.num = tonumber(a:sub(2))
      else
        local j = 2
        while j <= #a do
          local c = a:sub(j, j)
          if valued[c] then
            local v = a:sub(j + 1)
            if v == "" then i = i + 1; v = args[i] or "" end
            val(c, v)
            break
          else r.f[c] = true end
          j = j + 1
        end
      end
    else r.pos[#r.pos + 1] = a end
    i = i + 1
  end
  return r
end

-- positional arguments and those after "--"
local function allPaths(o)
  local t = {}
  for _, p in ipairs(o.pos) do t[#t + 1] = p end
  for _, p in ipairs(o.dd) do t[#t + 1] = p end
  return t
end

local function pathMatchers(list)
  local m = {}
  for _, s in ipairs(list) do m[#m + 1] = specMatcher(s) end
  return m
end

local function subjectOf(sha)
  local c = getCommit(sha)
  return c and subject(c) or ""
end

local C = {}   -- the commands

-- ---------------------------------------------------------------- status
local function stagedChanges(idx, headFlat, unmerged)
  local flat = {}
  for p, e in pairs(idx) do if not unmerged[p] then flat[p] = { sha = e.sha, mode = e.mode } end end
  local h = {}
  for p, e in pairs(headFlat) do if not unmerged[p] then h[p] = e end end
  return changeList(h, flat)
end

local function statusText(short)
  local branch, sha = readHead()
  local idx = loadIndex()
  local headFlat = (sha and commitFlat(sha)) or {}
  local staged, unstaged, unmerged = computeStatus(idx, headFlat)
  local untracked = untrackedList(idx)
  local changes = stagedChanges(idx, headFlat, unmerged)
  local nUnstaged, delUnstaged, nUnmerged = 0, false, 0
  for _, v in pairs(unstaged) do nUnstaged = nUnstaged + 1; if v == "D" then delUnstaged = true end end
  for _ in pairs(unmerged) do nUnmerged = nUnmerged + 1 end
  local merging = fs.exists(R.gd .. "/MERGE_HEAD")
  local out = {}
  if short then
    if short == "branch" then
      local line = "## " .. (branch or "HEAD (no branch)")
      if not sha and branch then line = "## No commits yet on " .. branch end
      out[#out + 1] = line
    end
    local rows = {}
    for _, ch in ipairs(changes) do
      local xy = ch.from and "R " or (not ch.old and "A ") or (not ch.new and "D ") or "M "
      local u = unstaged[ch.path]
      if u then xy = xy:sub(1, 1) .. u end
      rows[#rows + 1] = { ch.path, xy .. " " .. (ch.from and (ch.from .. " -> ") or "") .. ch.path }
    end
    for _, p in ipairs(sortedKeys(unstaged)) do
      local isStaged = false
      for _, ch in ipairs(changes) do if ch.path == p then isStaged = true end end
      if not isStaged then rows[#rows + 1] = { p, " " .. unstaged[p] .. " " .. p } end
    end
    for p in pairs(unmerged) do rows[#rows + 1] = { p, "UU " .. p } end
    table.sort(rows, function(a, b) return a[1] < b[1] end)
    for _, r in ipairs(rows) do out[#out + 1] = r[2] end
    for _, p in ipairs(untracked) do out[#out + 1] = "?? " .. p end
    return out
  end
  out[#out + 1] = branch and ("On branch " .. branch) or ("HEAD detached at " .. abbrev(sha or ""))
  local tl = branch and sha and trackingLines(branch, sha) or {}
  for _, l in ipairs(tl) do out[#out + 1] = l end
  if #tl > 0 then out[#out + 1] = "" end
  if not sha then
    out[#out + 1] = ""
    out[#out + 1] = "No commits yet"
    out[#out + 1] = ""
  end
  if merging and nUnmerged > 0 then
    out[#out + 1] = "You have unmerged paths."
    out[#out + 1] = '  (fix conflicts and run "git commit")'
    out[#out + 1] = '  (use "git merge --abort" to abort the merge)'
    out[#out + 1] = ""
  elseif merging then
    out[#out + 1] = "All conflicts fixed but you are still merging."
    out[#out + 1] = '  (use "git commit" to conclude merge)'
    out[#out + 1] = ""
  end
  if #changes > 0 then
    out[#out + 1] = "Changes to be committed:"
    out[#out + 1] = sha and '  (use "git restore --staged <file>..." to unstage)' or '  (use "git rm --cached <file>..." to unstage)'
    for _, ch in ipairs(changes) do
      local label = ch.from and ("renamed:    " .. ch.from .. " -> " .. ch.path) or (not ch.old and ("new file:   " .. ch.path)) or
                    (not ch.new and ("deleted:    " .. ch.path)) or ("modified:   " .. ch.path)
      out[#out + 1] = "\t" .. label
    end
    out[#out + 1] = ""
  end
  if nUnmerged > 0 then
    out[#out + 1] = "Unmerged paths:"
    out[#out + 1] = '  (use "git add <file>..." to mark resolution)'
    for _, p in ipairs(sortedKeys(unmerged)) do out[#out + 1] = "\tboth modified:   " .. p end
    out[#out + 1] = ""
  end
  if nUnstaged > 0 then
    out[#out + 1] = "Changes not staged for commit:"
    out[#out + 1] = delUnstaged and '  (use "git add/rm <file>..." to update what will be committed)' or '  (use "git add <file>..." to update what will be committed)'
    out[#out + 1] = '  (use "git restore <file>..." to discard changes in working directory)'
    for _, p in ipairs(sortedKeys(unstaged)) do out[#out + 1] = "\t" .. (unstaged[p] == "D" and "deleted:    " or "modified:   ") .. p end
    out[#out + 1] = ""
  end
  if #untracked > 0 then
    out[#out + 1] = "Untracked files:"
    out[#out + 1] = '  (use "git add <file>..." to include in what will be committed)'
    for _, p in ipairs(untracked) do out[#out + 1] = "\t" .. p end
    out[#out + 1] = ""
  end
  if #changes == 0 then
    if nUnstaged > 0 or nUnmerged > 0 then
      out[#out + 1] = 'no changes added to commit (use "git add" and/or "git commit -a")'
    elseif #untracked > 0 then
      out[#out + 1] = 'nothing added to commit but untracked files present (use "git add" to track)'
    elseif not sha then
      out[#out + 1] = 'nothing to commit (create/copy files and use "git add" to track)'
    else
      out[#out + 1] = "nothing to commit, working tree clean"
    end
  end
  return out, #changes, nUnstaged, #untracked
end

C.status = function(args)
  needRepo()
  local o = parseOpts(args, { u = true, ["untracked-files"] = true })
  local short = (o.f.s or o.f.short or o.f.porcelain) and ((o.f.b or o.f.branch) and "branch" or true) or nil
  for _, l in ipairs(statusText(short)) do print(l) end
end

-- ---------------------------------------------------------------- add
local function stageFile(idx, p)
  local data = readWork(join(R.root, p))
  if data == nil then return false end
  local cur = idx[p]
  if cur and getBlob(cur.sha) == data then return true end
  idx[p] = { sha = putObject("blob", data), mode = cur and cur.mode or "100644", size = #data }
  return true
end

C.add = function(args)
  needRepo()
  local o = parseOpts(args, {})
  local all, update, force = o.f.A or o.f.all, o.f.u or o.f.update, o.f.f or o.f.force
  local specs = allPaths(o)
  if #specs == 0 and not all and not update then
    eprint("Nothing specified, nothing added.\nhint: Maybe you wanted to say 'git add .'?\nhint: Turn this message off by running\nhint: \"git config advice.addEmptyPathspec false\"")
    return
  end
  local idx = loadIndex()
  local matchers = #specs == 0 and {} or pathMatchers(specs)
  if #specs == 0 then matchers = { function() return true end } end
  local files = walkTree("", {}, force)
  local fileSet = {}
  for _, p in ipairs(files) do fileSet[p] = true end
  -- every spec has to match something
  local ignoredHit = {}
  for k, spec in ipairs(specs) do
    local m = matchers[k]
    local hit = false
    for p in pairs(idx) do if m(p) then hit = true break end end
    if not hit then for _, p in ipairs(files) do if m(p) then hit = true break end end end
    if not hit then
      local rel = relPath(spec)
      if rel ~= "" and fs.exists(join(R.root, rel)) and (fs.isdir(join(R.root, rel)) and false or isIgnored(rel, fs.isdir(join(R.root, rel)))) and not idx[rel] then
        ignoredHit[#ignoredHit + 1] = rel
      else
        die("fatal: pathspec '" .. spec .. "' did not match any files")
      end
    end
  end
  if #ignoredHit > 0 then
    die("The following paths are ignored by one of your .gitignore files:\n" .. table.concat(ignoredHit, "\n") ..
        "\nhint: Use -f if you really want to add them.\nhint: Disable this message with \"git config set advice.addIgnoredFile false\"", 1)
  end
  local unmerged = unmergedList()
  for _, p in ipairs(sortedKeys(idx)) do
    if matchAny(p, matchers) and not fileSet[p] and not readWork(join(R.root, p)) then idx[p] = nil; unmerged[p] = nil end
  end
  if not update or #specs > 0 then
    for _, p in ipairs(files) do
      if matchAny(p, matchers) and (not update or idx[p]) then
        stageFile(idx, p)
        unmerged[p] = nil
      end
    end
  end
  -- tracked files that are ignored now still count (git add -u); modified ones were staged above only when listed
  for p in pairs(idx) do
    if matchAny(p, matchers) and not fileSet[p] and readWork(join(R.root, p)) then stageFile(idx, p); unmerged[p] = nil end
  end
  saveIndex(idx)
  saveUnmerged(unmerged)
end

-- ---------------------------------------------------------------- commit
local function commitMessage(o)
  local msgs = o.v.m or o.v.message
  if msgs then return table.concat(msgs, "\n\n") end
  local f = o.v.F or o.v.file
  if f then return readFile(fs.abspath(f[1])) or die("fatal: could not read log file '" .. f[1] .. "': No such file or directory") end
  return nil
end

local function stageTracked(idx)
  local k = 0
  for _, p in ipairs(sortedKeys(idx)) do
    local data = readWork(join(R.root, p))
    if data == nil then idx[p] = nil
    else stageFile(idx, p) end
    k = k + 1
    yield(k)
  end
end

C.commit = function(args)
  needRepo()
  local o = parseOpts(args, { m = true, message = true, F = true, file = true, author = true, C = true, c = true, date = true })
  local branch, headS = readHead()
  local idx = loadIndex()
  if o.f.a or o.f.all then stageTracked(idx) end
  local unmerged = unmergedList()
  if next(unmerged) then
    die("error: Committing is not possible because you have unmerged files.\nhint: Fix them up in the work tree, and then use 'git add/rm <file>'\nhint: as appropriate to mark resolution and make a commit.\nfatal: Exiting because of an unresolved conflict.", 128)
  end
  local merging = fs.exists(R.gd .. "/MERGE_HEAD") and (readFile(R.gd .. "/MERGE_HEAD") or ""):match("%x+") or nil
  local amend = o.f.amend
  local msg = commitMessage(o)
  local parents, authorLine
  if amend then
    local c = headS and getCommit(headS)
    if not c then die("fatal: You have nothing to amend.") end
    parents = {}
    for _, p in ipairs(c.parents) do parents[#parents + 1] = p end
    authorLine = c.author
    if not msg then msg = c.msg end
    headS = c.parents[1]
  else
    parents = headS and { headS } or {}
    if merging then parents[#parents + 1] = merging end
  end
  if not msg and merging then msg = (readFile(R.gd .. "/MERGE_MSG") or ""):gsub("\n+$", "") end
  local headFlat = (headS and commitFlat(headS)) or {}
  local flat = {}
  for p, e in pairs(idx) do flat[p] = { sha = e.sha, mode = e.mode } end
  local treeSha = buildTree(flat)
  local parentTree = headS and getCommit(headS) and getCommit(headS).tree
  local same = parentTree == treeSha
  if headS and not getCommit(headS) then
    -- the synthetic head of a clone: its tree is known only as a file list
    local hf = commitFlat(headS)
    same = true
    for p, e in pairs(flat) do if not hf[p] or hf[p].sha ~= e.sha or hf[p].mode ~= e.mode then same = false end end
    for p in pairs(hf) do if not flat[p] then same = false end end
  end
  if same and not o.f["allow-empty"] and not merging and not amend then
    for _, l in ipairs(statusText(false)) do print(l) end
    os.exit(1)
  end
  if not msg or msg:match("^%s*$") then
    if not msg then
      eprint("hint: Waiting for your editor to close the file...")
      die("error: There was a problem with the editor 'vi'.\nPlease supply the message using either -m or -F option.", 1)
    end
    die("Aborting commit due to empty commit message.", 1)
  end
  msg = msg:gsub("^\n+", "")
  local sha = writeCommit(treeSha, parents, msg, authorLine)
  moveHead(sha)
  if o.f.a or o.f.all then saveIndex(idx) end
  if merging then
    fs.remove(R.gd .. "/MERGE_HEAD")
    if fs.exists(R.gd .. "/MERGE_MSG") then fs.remove(R.gd .. "/MERGE_MSG") end
  end
  if not o.f.q and not o.f.quiet then
    local label = branch or "detached HEAD"
    if not headS and not amend then label = label .. " (root-commit)" end
    print("[" .. label .. " " .. abbrev(sha) .. "] " .. subject(getCommit(sha)))
    local made = getCommit(sha)
    if amend and made.ts ~= made.cts then print(" Date: " .. epochDate(made.ts, made.tz)) end
    printStat(changeList(headFlat, flat), true, true)
  end
end

-- ---------------------------------------------------------------- moving between trees
local function checkoutTree(oldF, newF, force, verb)
  local idx = loadIndex()
  local changed = {}
  for p, e in pairs(newF) do
    local o = oldF[p]
    if not o or o.sha ~= e.sha or o.mode ~= e.mode then changed[#changed + 1] = p end
  end
  for p in pairs(oldF) do if not newF[p] then changed[#changed + 1] = p end end
  table.sort(changed)
  if not force then
    local dirty, untr = {}, {}
    for _, p in ipairs(changed) do
      local ie = idx[p]
      local w = readWork(join(R.root, p))
      if ie then
        local o, n = oldF[p], newF[p]
        local stagedDiff = not o or o.sha ~= ie.sha
        local wdiff = w == nil or w ~= getBlob(ie.sha)
        if (stagedDiff or wdiff) and not (n and n.sha == ie.sha and not wdiff) then dirty[#dirty + 1] = p end
      elseif w ~= nil and newF[p] then
        untr[#untr + 1] = p
      end
    end
    local tail = verb == "merge" and "merge" or "switch branches"
    if #dirty > 0 then
      die("error: Your local changes to the following files would be overwritten by " .. verb .. ":\n\t" .. table.concat(dirty, "\n\t") ..
          "\nPlease commit your changes or stash them before you " .. tail .. ".\nAborting", 1)
    end
    if #untr > 0 then
      die("error: The following untracked working tree files would be overwritten by " .. verb .. ":\n\t" .. table.concat(untr, "\n\t") ..
          "\nPlease move or remove them before you " .. tail .. ".\nAborting", 1)
    end
  end
  for k, p in ipairs(changed) do
    local n = newF[p]
    local full = join(R.root, p)
    if n then
      local data = getBlob(n.sha) or ""
      writeFile(full, data)
      idx[p] = { sha = n.sha, mode = n.mode, size = #data }
    else
      fs.remove(full)
      idx[p] = nil
      pruneDirs(parent(full), R.root)
    end
    yield(k)
  end
  saveIndex(idx)
end

local function savePrev(from)
  if from then writeFile(join(metaDir(), "prev"), from .. "\n") end
end

-- lines "M\tfile" for the local changes that went along with a switch
local function carriedChanges()
  local idx = loadIndex()
  local headFlat = commitFlat(headSha()) or {}
  local staged, unstaged = computeStatus(idx, headFlat)
  local rows, seen = {}, {}
  for p, v in pairs(staged) do rows[p] = v; seen[p] = true end
  for p, v in pairs(unstaged) do if not rows[p] then rows[p] = v end end
  local out = {}
  for _, p in ipairs(sortedKeys(rows)) do out[#out + 1] = rows[p] .. "\t" .. p end
  return out
end

local DETACHED = [[
Note: switching to '%s'.

You are in 'detached HEAD' state. You can look around, make experimental
changes and commit them, and you can discard any commits you make in this
state without impacting any branches by switching back to a branch.

If you want to create a new branch to retain commits you create, you may
do so (now or later) by using -c with the switch command. Example:

  git switch -c <new-branch-name>

Or undo this operation with:

  git switch -

Turn off this advice by setting config variable advice.detachedHead to false
]]

local function validBranchName(n)
  return n ~= "" and not n:find("[%s~%^:%?%*%[\\]") and not n:find("%.%.") and n:sub(1, 1) ~= "-" and n:sub(-5) ~= ".lock" and
         n:sub(-1) ~= "/" and n:sub(1, 1) ~= "/" and n:sub(-1) ~= "."
end

-- switch to a branch (name) or detach at a commit; create: make the branch first from start
local function switchTo(target, opts)
  local curBranch, curSha = readHead()
  local oldFlat = (curSha and commitFlat(curSha)) or {}
  local newSha, newBranch = opts.sha, opts.branch
  local newFlat = commitFlat(newSha)
  if not newFlat then die("fatal: reference is not a tree: " .. tostring(target)) end
  checkoutTree(oldFlat, newFlat, opts.force, "checkout")
  if not curBranch and curSha and curSha ~= newSha then
    eprint("Previous HEAD position was " .. abbrev(curSha) .. " " .. subjectOf(curSha))
  end
  if opts.create then setRef("refs/heads/" .. newBranch, newSha) end
  savePrev(curBranch or curSha)
  if newBranch then writeFile(R.gd .. "/HEAD", "ref: refs/heads/" .. newBranch .. "\n")
  else writeFile(R.gd .. "/HEAD", newSha .. "\n") end
  -- a switch keeps the merge state out of the way
  if opts.carry then for _, l in ipairs(carriedChanges()) do print(l) end end
  if newBranch then
    print((opts.create and "Switched to a new branch '" or "Switched to branch '") .. newBranch .. "'")
    for _, l in ipairs(trackingLines(newBranch, newSha)) do print(l) end
  else
    if curBranch then eprint((DETACHED:format(target))) end
    print("HEAD is now at " .. abbrev(newSha) .. " " .. subjectOf(newSha))
  end
end

local function restorePaths(source, specs, staged, worktree)
  -- source: a commit sha, or nil for the index
  local idx = loadIndex()
  local srcFlat
  if source then srcFlat = commitFlat(source) or {} end
  local matchers = pathMatchers(specs)
  local n = 0
  local seen = {}
  local pool = {}
  if source then for p in pairs(srcFlat) do pool[p] = true end end
  for p in pairs(idx) do pool[p] = true end
  for _, m in ipairs(matchers) do
    local hit = false
    for p in pairs(pool) do if m(p) then hit = true break end end
    if not hit then die("error: pathspec '" .. specs[1] .. "' did not match any file(s) known to git", 1) end
  end
  for _, p in ipairs(sortedKeys(pool)) do
    if matchAny(p, matchers) and not seen[p] then
      seen[p] = true
      local e = source and srcFlat[p] or (not source and idx[p])
      local counted = false
      if staged then
        local old = idx[p]
        if e then idx[p] = { sha = e.sha, mode = e.mode, size = #(getBlob(e.sha) or "") } else idx[p] = nil end
        if (old and old.sha) ~= (e and e.sha) then counted = true end
      end
      if worktree then
        local we = e
        if staged and not source then we = idx[p] end
        local full = join(R.root, p)
        local cur = readWork(full)
        if we then
          local data = getBlob(we.sha) or ""
          if cur ~= data then writeFile(full, data); counted = true end
        elseif cur then fs.remove(full); pruneDirs(parent(full), R.root); counted = true end
      end
      if counted then n = n + 1 end
    end
  end
  saveIndex(idx)
  return n
end

local function doSwitch(args, isSwitch)
  needRepo()
  local o = parseOpts(args, { b = true, B = true, c = true, C = true, ["start-point"] = true })
  local create = (o.v.b and o.v.b[1]) or (o.v.c and o.v.c[1]) or (o.v.B and o.v.B[1]) or (o.v.C and o.v.C[1])
  local forceCreate = o.v.B or o.v.C
  local force = o.f.f or o.f.force or o.f["discard-changes"]
  local pos = o.pos
  local curBranch, curSha = readHead()
  if create then
    if not validBranchName(create) then die("fatal: '" .. create .. "' is not a valid branch name") end
    if refSha("refs/heads/" .. create) and not forceCreate then die("fatal: a branch named '" .. create .. "' already exists") end
    local startRev = pos[1] or "HEAD"
    local sha = resolve(startRev)
    if not sha then
      if not curSha and startRev == "HEAD" then
        -- a branch on an unborn HEAD: only the name changes
        writeFile(R.gd .. "/HEAD", "ref: refs/heads/" .. create .. "\n")
        print("Switched to a new branch '" .. create .. "'")
        return
      end
      die("fatal: " .. (isSwitch and "invalid reference: " or "not a valid object name: '") .. startRev .. (isSwitch and "" or "'"))
    end
    switchTo(startRev, { sha = sha, branch = create, create = true, force = force, carry = not isSwitch })
    return
  end
  if o.f.detach or o.f.d then
    local sha = resolve(pos[1] or "HEAD") or die("fatal: invalid reference: " .. tostring(pos[1]))
    switchTo(pos[1] or "HEAD", { sha = sha, force = force, carry = not isSwitch })
    return
  end
  local target = pos[1]
  if not target then
    if isSwitch then die("fatal: missing branch or commit argument") end
    if o.hasDD then
      restorePaths(nil, allPaths(o), false, true)
      return
    end
    for _, l in ipairs(statusText(true)) do print(l) end
    return
  end
  if target == "-" then
    local prev = (readFile(join(metaDir(), "prev")) or ""):match("%S+")
    if not prev or not (refSha("refs/heads/" .. prev) or resolve(prev)) then die("fatal: invalid reference: @{-1}") end
    target = prev
  end
  -- a path (checkout [rev] -- paths) ?
  if not isSwitch and (o.hasDD or (#pos > 1)) then
    local src = resolve(target)
    local specs = allPaths(o)
    if o.hasDD then
      -- checkout REV -- paths, or checkout -- paths
      if #pos == 0 then src = nil end
    else
      table.remove(specs, 1)
      if not src then src = nil; specs = allPaths(o) end
    end
    local n = restorePaths(src, specs, true, true)
    if not o.hasDD then eprint("Updated " .. plural(n, "path") .. " from " .. (src and abbrev(src) or "the index")) end
    return
  end
  local branchSha = refSha("refs/heads/" .. target)
  if branchSha then
    if curBranch == target then
      print("Already on '" .. target .. "'")
      for _, l in ipairs(trackingLines(target, branchSha)) do print(l) end
      return
    end
    switchTo(target, { sha = branchSha, branch = target, force = force, carry = not isSwitch })
    return
  end
  -- origin/NAME exists: make a tracking branch
  for remoteName in pairs(listRefs("refs/remotes")) do
    local rn, br = remoteName:match("^([^/]+)/(.+)$")
    if br == target then
      local sha = refSha("refs/remotes/" .. remoteName)
      setRef("refs/heads/" .. target, sha)
      cfgSet("branch." .. target .. ".remote", rn)
      cfgSet("branch." .. target .. ".merge", "refs/heads/" .. target)
      print("branch '" .. target .. "' set up to track '" .. remoteName .. "'.")
      switchTo(target, { sha = sha, branch = target, force = force, carry = not isSwitch })
      return
    end
  end
  local sha = resolve(target)
  if sha and not isSwitch and commitFlat(sha) then
    switchTo(target, { sha = sha, force = force, carry = true })
    return
  end
  if isSwitch then
    if sha then die("fatal: a branch is expected, got commit '" .. target .. "'\nhint: If you want to detach HEAD at the commit, try again with the --detach option.") end
    die("fatal: invalid reference: " .. target)
  end
  -- a file in the working tree or the index
  local rel = relPath(target)
  local idx = loadIndex()
  local known = idx[rel]
  if not known then for p in pairs(idx) do if p:sub(1, #rel + 1) == rel .. "/" then known = true break end end end
  if known then
    local n = restorePaths(nil, { target }, false, true)
    eprint("Updated " .. plural(n, "path") .. " from the index")
    return
  end
  die("error: pathspec '" .. target .. "' did not match any file(s) known to git", 1)
end

C.checkout = function(args) doSwitch(args, false) end
C.switch = function(args) doSwitch(args, true) end

-- ---------------------------------------------------------------- branch
C.branch = function(args)
  needRepo()
  local o = parseOpts(args, { u = true, ["set-upstream-to"] = true })
  local cur, curSha = readHead()
  local pos = o.pos
  if o.f["show-current"] then if cur then print(cur) end return end
  local up = (o.v.u and o.v.u[1]) or (o.v["set-upstream-to"] and o.v["set-upstream-to"][1])
  if up then
    local name = pos[1] or cur
    if not refSha("refs/heads/" .. name) then die("fatal: branch '" .. name .. "' does not exist") end
    local rn, br = up:match("^([^/]+)/(.+)$")
    if not rn or not refSha("refs/remotes/" .. up) then die("fatal: the requested upstream branch '" .. up .. "' does not exist") end
    cfgSet("branch." .. name .. ".remote", rn)
    cfgSet("branch." .. name .. ".merge", "refs/heads/" .. br)
    print("branch '" .. name .. "' set up to track '" .. up .. "'.")
    return
  end
  if o.f.d or o.f.D or o.f.delete then
    local force = o.f.D or (o.f.force and (o.f.d or o.f.delete))
    if #pos == 0 then die("fatal: branch name required") end
    local failed = false
    for _, name in ipairs(pos) do
      local isRemote = o.f.r
      local ref = (isRemote and "refs/remotes/" or "refs/heads/") .. name
      local sha = refSha(ref)
      if not sha then
        eprint("error: " .. (isRemote and "remote-tracking branch" or "branch") .. " '" .. name .. "' not found")
        failed = true
      elseif name == cur and not isRemote then
        eprint("error: cannot delete branch '" .. name .. "' used by worktree at '" .. R.root .. "'")
        failed = true
      elseif not force and not isRemote and curSha and not ancestors(curSha)[sha] then
        eprint("error: the branch '" .. name .. "' is not fully merged.\nhint: If you are sure you want to delete it, run 'git branch -D " .. name .. "'")
        failed = true
      else
        delRef(ref)
        print("Deleted " .. (isRemote and "remote-tracking branch " or "branch ") .. name .. " (was " .. abbrev(sha) .. ").")
      end
    end
    if failed then os.exit(1) end
    return
  end
  if o.f.m or o.f.M or o.f.move then
    local old, new = pos[1], pos[2]
    if not new then old, new = cur, pos[1] end
    if not new or not old then die("fatal: branch name required") end
    if not validBranchName(new) then die("fatal: '" .. new .. "' is not a valid branch name") end
    local sha = refSha("refs/heads/" .. old)
    if not sha then
      if old == cur and not curSha then
        writeFile(R.gd .. "/HEAD", "ref: refs/heads/" .. new .. "\n")
        return
      end
      die("error: refname refs/heads/" .. old .. " not found\nfatal: Branch rename failed", 128)
    end
    if refSha("refs/heads/" .. new) and not o.f.M then die("fatal: a branch named '" .. new .. "' already exists") end
    setRef("refs/heads/" .. new, sha)
    delRef("refs/heads/" .. old)
    if cur == old then writeFile(R.gd .. "/HEAD", "ref: refs/heads/" .. new .. "\n") end
    return
  end
  if #pos >= 1 and not (o.f.l or o.f.list) then
    local name = pos[1]
    if not validBranchName(name) then die("fatal: '" .. name .. "' is not a valid branch name") end
    if refSha("refs/heads/" .. name) then die("fatal: a branch named '" .. name .. "' already exists") end
    local startRev = pos[2] or "HEAD"
    local sha = resolve(startRev)
    if not sha then
      if startRev == "HEAD" and not curSha then die("fatal: not a valid object name: '" .. (cur or "HEAD") .. "'") end
      die("fatal: not a valid object name: '" .. startRev .. "'")
    end
    setRef("refs/heads/" .. name, sha)
    return
  end
  -- the list
  local rows = {}
  if not o.f.r then
    for name, sha in pairs(listRefs("refs/heads")) do rows[#rows + 1] = { name = name, sha = sha, cur = name == cur } end
  end
  if o.f.a or o.f.r or o.f.all or o.f.remotes then
    for name, sha in pairs(listRefs("refs/remotes")) do
      rows[#rows + 1] = { name = o.f.r and name or ("remotes/" .. name), sha = sha }
    end
  end
  table.sort(rows, function(a, b) return a.name < b.name end)
  if not cur and curSha and not o.f.r then table.insert(rows, 1, { name = "(HEAD detached at " .. abbrev(curSha) .. ")", sha = curSha, cur = true }) end
  local width = 0
  for _, r in ipairs(rows) do width = math.max(width, #r.name) end
  for _, r in ipairs(rows) do
    local line = (r.cur and "* " or "  ") .. r.name
    if o.f.v or o.f.verbose or o.f.vv then
      line = (r.cur and "* " or "  ") .. string.format("%-" .. width .. "s %s %s", r.name, abbrev(r.sha), subjectOf(r.sha))
    end
    print(line)
  end
end

-- ---------------------------------------------------------------- merge
local function joinLines(lines)
  if #lines == 0 then return "" end
  local last = lines[#lines]
  local body = {}
  for i, l in ipairs(lines) do body[i] = lineText(l) end
  local text = table.concat(body, "\n")
  if last:sub(-5) == "\0NONL" then return text end
  return text .. "\n"
end

local function hunksOf(base, other)
  local hs, bi, cur = {}, 0, nil
  for _, op in ipairs(lineDiff(base, other)) do
    if op[1] == " " then cur = nil; bi = bi + 1
    else
      if not cur then cur = { s = bi, e = bi, lines = {} }; hs[#hs + 1] = cur end
      if op[1] == "-" then bi = bi + 1; cur.e = bi else cur.lines[#cur.lines + 1] = op[2] end
    end
  end
  return hs
end

-- a three-way merge of text: returns the merged text and whether there were conflicts
local function merge3(baseText, oursText, theirsText, labelO, labelT)
  local base, ours, theirs = splitLines(baseText), splitLines(oursText), splitLines(theirsText)
  local ha, hb = hunksOf(base, ours), hunksOf(base, theirs)
  local out, pos, i, j, conflict = {}, 0, 1, 1, false
  local function emitBase(upto) for k = pos + 1, upto do out[#out + 1] = base[k] end pos = math.max(pos, upto) end
  local function overlap(a, b) return (a.s < b.e and b.s < a.e) or a.s == b.s end
  local function apply(hunks, s, e)
    local lines, p = {}, s
    for _, h in ipairs(hunks) do
      for k = p + 1, h.s do lines[#lines + 1] = base[k] end
      for _, l in ipairs(h.lines) do lines[#lines + 1] = l end
      p = h.e
    end
    for k = p + 1, e do lines[#lines + 1] = base[k] end
    return lines
  end
  while i <= #ha or j <= #hb do
    local a, b = ha[i], hb[j]
    if a and (not b or (not overlap(a, b) and a.s < b.s)) then
      emitBase(a.s)
      for _, l in ipairs(a.lines) do out[#out + 1] = l end
      pos = math.max(pos, a.e)
      i = i + 1
    elseif b and (not a or not overlap(a, b)) then
      emitBase(b.s)
      for _, l in ipairs(b.lines) do out[#out + 1] = l end
      pos = math.max(pos, b.e)
      j = j + 1
    else
      local s, e = math.min(a.s, b.s), math.max(a.e, b.e)
      local ca, cb = { a }, { b }
      i, j = i + 1, j + 1
      local grew = true
      while grew do
        grew = false
        if ha[i] and ha[i].s < e then ca[#ca + 1] = ha[i]; e = math.max(e, ha[i].e); i = i + 1; grew = true end
        if hb[j] and hb[j].s < e then cb[#cb + 1] = hb[j]; e = math.max(e, hb[j].e); j = j + 1; grew = true end
      end
      emitBase(s)
      local lo, lt = apply(ca, s, e), apply(cb, s, e)
      if table.concat(lo, "\n") == table.concat(lt, "\n") then
        for _, l in ipairs(lo) do out[#out + 1] = l end
      else
        conflict = true
        out[#out + 1] = "<<<<<<< " .. labelO
        for _, l in ipairs(lo) do out[#out + 1] = lineText(l) end
        out[#out + 1] = "======="
        for _, l in ipairs(lt) do out[#out + 1] = lineText(l) end
        out[#out + 1] = ">>>>>>> " .. labelT
      end
      pos = math.max(pos, e)
    end
  end
  emitBase(#base)
  return joinLines(out), conflict
end

local function sameEntry(x, y)
  return (x == nil and y == nil) or (x ~= nil and y ~= nil and x.sha == y.sha and x.mode == y.mode)
end

-- the three trees -> the merged files, the conflicts { path, data, kind } and printed notes
local function mergeFlats(base, ours, theirs, labelO, labelT)
  local result, conflicts = {}, {}
  local paths = {}
  for _, t in ipairs({ base, ours, theirs }) do for p in pairs(t) do paths[p] = true end end
  for _, p in ipairs(sortedKeys(paths)) do
    local b, o, t = base[p], ours[p], theirs[p]
    if sameEntry(o, t) then result[p] = o
    elseif sameEntry(b, o) then result[p] = t
    elseif sameEntry(b, t) then result[p] = o
    elseif o and t then
      local od, td, bd = entryData(o), entryData(t), entryData(b)
      if isBinary(od) or isBinary(td) or isBinary(bd) then
        print("warning: Cannot merge binary files: " .. p .. " (" .. labelO .. " vs. " .. labelT .. ")")
        print("CONFLICT (content): Merge conflict in " .. p)
        result[p] = o
        conflicts[#conflicts + 1] = { path = p }
      else
        print("Auto-merging " .. p)
        local text, conf = merge3(bd, od, td, labelO, labelT)
        if conf then
          result[p] = o
          conflicts[#conflicts + 1] = { path = p, data = text }
          print("CONFLICT (" .. (b and "content" or "add/add") .. "): Merge conflict in " .. p)
        else
          result[p] = { sha = putObject("blob", text), mode = o.mode, size = #text }
        end
      end
    else
      result[p] = o or t
      conflicts[#conflicts + 1] = { path = p }
      if o then print("CONFLICT (modify/delete): " .. p .. " deleted in " .. labelT .. " and modified in " .. labelO .. ".  Version " .. labelO .. " of " .. p .. " left in tree.")
      else print("CONFLICT (modify/delete): " .. p .. " deleted in " .. labelO .. " and modified in " .. labelT .. ".  Version " .. labelT .. " of " .. p .. " left in tree.") end
    end
  end
  return result, conflicts
end

-- lands the merge of theirsSha into HEAD (base = a file map); message for the merge commit
local function applyMerge(oursSha, theirsSha, baseFlat, theirsFlat, labelO, labelT, msg)
  local oursFlat = commitFlat(oursSha) or {}
  local result, conflicts = mergeFlats(baseFlat, oursFlat, theirsFlat, labelO, labelT)
  checkoutTree(oursFlat, result, false, "merge")
  if #conflicts > 0 then
    local set = {}
    for _, c in ipairs(conflicts) do
      set[c.path] = true
      if c.data then writeFile(join(R.root, c.path), c.data) end
    end
    saveUnmerged(set)
    writeFile(R.gd .. "/MERGE_HEAD", theirsSha .. "\n")
    writeFile(R.gd .. "/MERGE_MSG", msg .. "\n")
    print("Automatic merge failed; fix conflicts and then commit the result.")
    os.exit(1)
  end
  local idx = loadIndex()
  local flat = {}
  for p, e in pairs(idx) do flat[p] = { sha = e.sha, mode = e.mode } end
  local sha = writeCommit(buildTree(flat), { oursSha, theirsSha }, msg)
  moveHead(sha)
  print("Merge made by the 'ort' strategy.")
  printStat(changeList(oursFlat, flat), true)
end

local function mergeLabel(name)
  if refSha("refs/heads/" .. name) then return "branch '" .. name .. "'" end
  if refSha("refs/tags/" .. name) then return "tag '" .. name .. "'" end
  if refSha("refs/remotes/" .. name) then return "remote-tracking branch '" .. name .. "'" end
  return "commit '" .. name .. "'"
end

C.merge = function(args)
  needRepo()
  local o = parseOpts(args, { m = true, message = true, s = true, strategy = true, X = true })
  local branch, headS = readHead()
  if o.f.abort then
    if not fs.exists(R.gd .. "/MERGE_HEAD") then die("fatal: There is no merge to abort (MERGE_HEAD missing).") end
    local flat = commitFlat(headS) or {}
    for p in pairs(loadIndex()) do
      if not flat[p] and readWork(join(R.root, p)) then fs.remove(join(R.root, p)); pruneDirs(parent(join(R.root, p)), R.root) end
    end
    local out = {}
    for p, e in pairs(flat) do
      local data = getBlob(e.sha) or ""
      writeFile(join(R.root, p), data)
      out[p] = { sha = e.sha, mode = e.mode, size = #data }
    end
    saveIndex(out)
    fs.remove(R.gd .. "/MERGE_HEAD")
    if fs.exists(R.gd .. "/MERGE_MSG") then fs.remove(R.gd .. "/MERGE_MSG") end
    saveUnmerged({})
    return
  end
  local name = o.pos[1]
  if not name then die("fatal: No remote for the current branch.") end
  if fs.exists(R.gd .. "/MERGE_HEAD") then
    die("fatal: You have not concluded your merge (MERGE_HEAD exists).\nPlease, commit your changes before you merge.")
  end
  local theirs = resolve(name)
  if not theirs then die("merge: " .. name .. " - not something we can merge", 1) end
  if not headS then die("fatal: Cannot merge into an unborn branch with this git; commit something first.") end
  if theirs == headS or ancestors(headS)[theirs] then print("Already up to date.") return end
  local m = o.v.m or o.v.message
  local text = m and table.concat(m, "\n\n") or ("Merge " .. mergeLabel(name) .. ((branch and branch ~= "main" and branch ~= "master") and (" into " .. branch) or ""))
  local canFF = ancestors(theirs)[headS]
  if canFF and not o.f["no-ff"] then
    local oldFlat, newFlat = commitFlat(headS) or {}, commitFlat(theirs) or {}
    print("Updating " .. abbrev(headS) .. ".." .. abbrev(theirs))
    checkoutTree(oldFlat, newFlat, false, "merge")
    moveHead(theirs)
    print("Fast-forward")
    printStat(changeList(oldFlat, newFlat), true)
    return
  end
  if o.f["ff-only"] then die("fatal: Not possible to fast-forward, aborting.") end
  local base = mergeBase(headS, theirs)
  local baseFlat = base and commitFlat(base) or {}
  applyMerge(headS, theirs, baseFlat, commitFlat(theirs) or {}, "HEAD", name, text)
end

-- ---------------------------------------------------------------- init
local CONFIG_NEW = "[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = false\n\tlogallrefupdates = true\n"
local function makeRepo(dir, branch)
  local gd = join(dir, ".git")
  fs.mkdir(dir, true)
  for _, d in ipairs({ "", "/objects", "/objects/info", "/objects/pack", "/refs", "/refs/heads", "/refs/tags", "/info", "/hooks", "/branches" }) do
    if not fs.exists(gd .. d) then fs.mkdir(gd .. d, true) end
  end
  writeFile(gd .. "/HEAD", "ref: refs/heads/" .. branch .. "\n")
  writeFile(gd .. "/config", CONFIG_NEW)
  writeFile(gd .. "/description", "Unnamed repository; edit this file 'description' to name the repository.\n")
  writeFile(gd .. "/info/exclude", "# git ls-files --others --exclude-from=.git/info/exclude\n# Lines that start with '#' are comments.\n")
end

C.init = function(args)
  local o = parseOpts(args, { b = true, ["initial-branch"] = true, ["template"] = true })
  local branch = (o.v.b and o.v.b[1]) or (o.v["initial-branch"] and o.v["initial-branch"][1]) or "main"
  local target = o.pos[1] or "."
  local dir = normalize(fs.abspath(target))
  local again = fs.exists(join(dir, ".git/HEAD"))
  if again then
    print("Reinitialized existing Git repository in " .. dir .. "/.git/")
    return
  end
  makeRepo(dir, branch)
  if not o.f.q and not o.f.quiet then print("Initialized empty Git repository in " .. dir .. "/.git/") end
end

-- ---------------------------------------------------------------- diff, log, show
local function patchHeaderPrint(changes)
  for _, ch in ipairs(changes) do
    for _, l in ipairs(patchOf(ch)) do print(l) end
  end
end

local function indexFlat(idx)
  local f = {}
  for p, e in pairs(idx) do f[p] = { sha = e.sha, mode = e.mode } end
  return f
end

-- the tracked files as they are in the working tree
local function workFlat(idx)
  local f = {}
  local unmerged = unmergedList()
  for p, e in pairs(idx) do
    local data = readWork(join(R.root, p))
    if data ~= nil then
      if data == getBlob(e.sha) then f[p] = { sha = e.sha, mode = e.mode, data = data }
      else f[p] = { data = data, mode = e.mode } end
    end
  end
  return f
end

local function revOrDie(rev)
  local sha = resolve(rev)
  if not sha then
    die("fatal: ambiguous argument '" .. rev .. "': unknown revision or path not in the working tree.\nUse '--' to separate paths from revisions, like this:\n'git <command> [<revision>...] -- [<file>...]'")
  end
  return sha
end

C.diff = function(args)
  needRepo()
  local o = parseOpts(args, { U = true, ["unified"] = true })
  local idx = loadIndex()
  local specs, revs = {}, {}
  for _, p in ipairs(o.pos) do
    if not o.hasDD and resolve(p) and not fs.exists(join(R.root, relPath(p))) then revs[#revs + 1] = p
    elseif not o.hasDD and #revs < 2 and resolve(p) and not idx[relPath(p)] then revs[#revs + 1] = p
    else specs[#specs + 1] = p end
  end
  for _, p in ipairs(o.dd) do specs[#specs + 1] = p end
  local filter = #specs > 0 and (function() local m = pathMatchers(specs) return function(p) return matchAny(p, m) end end)() or nil
  local a, b
  local cached = o.f.cached or o.f.staged
  if #revs == 0 then
    if cached then a, b = commitFlat(headSha()) or {}, indexFlat(idx)
    else a, b = indexFlat(idx), workFlat(idx) end
  elseif #revs == 1 then
    local base = commitFlat(revOrDie(revs[1])) or {}
    a, b = base, cached and indexFlat(idx) or workFlat(idx)
  else
    a, b = commitFlat(revOrDie(revs[1])) or {}, commitFlat(revOrDie(revs[2])) or {}
  end
  if #revs == 0 and not cached then
    -- unmerged and unchanged paths are not shown
    local u = unmergedList()
    for p in pairs(u) do a[p] = nil; b[p] = nil end
  end
  local changes = changeList(a, b, filter)
  if o.f["name-only"] then for _, ch in ipairs(changes) do print(ch.path) end return end
  if o.f["name-status"] then
    for _, ch in ipairs(changes) do print((ch.from and "R100\t" .. ch.from .. "\t" or (not ch.old and "A\t") or (not ch.new and "D\t") or "M\t") .. ch.path) end
    return
  end
  if o.f.stat or o.f.shortstat then printStat(changes, false) return end
  if o.f.quiet or o.f.q then os.exit(#changes > 0 and 1 or 0) end
  patchHeaderPrint(changes)
  if o.f["exit-code"] and #changes > 0 then os.exit(1) end
end

local function decorations()
  local d = {}
  local branch, headS = readHead()
  local function add(sha, text) d[sha] = d[sha] or {}; table.insert(d[sha], text) end
  if headS then add(headS, branch and ("HEAD -> " .. branch) or "HEAD") end
  local tags = listRefs("refs/tags")
  local remotes = listRefs("refs/remotes")
  local heads = listRefs("refs/heads")
  local function rev(t, fn)
    local keys = sortedKeys(t)
    for i = #keys, 1, -1 do fn(keys[i], t[keys[i]]) end
  end
  rev(tags, function(n, sha) add(peel(sha), "tag: " .. n) end)
  rev(remotes, function(n, sha) add(sha, n) end)
  rev(heads, function(n, sha) if n ~= branch then add(sha, n) end end)
  return d
end

local function printCommit(c, o, deco, graph, last)
  local pre = graph and "| " or ""
  local function p(s) print(pre .. s) end
  local dec = deco[c.sha] and (" (" .. table.concat(deco[c.sha], ", ") .. ")") or ""
  local msg = c.msg:gsub("\n+$", "")
  if o.format then
    local text = o.format:gsub("%%(%a%a?)", function(k)
      if k == "H" then return c.sha elseif k == "h" then return abbrev(c.sha)
      elseif k == "s" then return subject(c)
      elseif k == "an" or k == "cn" then return (c.who:match("^(.-) <") or c.who)
      elseif k == "ae" or k == "ce" then return (c.who:match("<(.-)>") or "")
      elseif k == "ad" or k == "cd" then return epochDate(c.ts, c.tz)
      elseif k == "ai" or k == "ci" then return os.date and "" or ""
      elseif k == "d" then return dec
      elseif k == "T" then return c.tree or ""
      elseif k == "P" then return table.concat(c.parents, " ")
      elseif k == "p" then local t = {} for _, x in ipairs(c.parents) do t[#t + 1] = abbrev(x) end return table.concat(t, " ")
      elseif k == "b" then return (msg:match("\n\n(.*)$") or "")
      elseif k == "n" then return "\n" end
      return "%" .. k
    end):gsub("%%%%", "%%")
    print((graph and "* " or "") .. text)
    return
  end
  if o.oneline then
    print((graph and "* " or "") .. abbrev(c.sha) .. dec .. " " .. (c.subjectOverride or subject(c)))
    return
  end
  print((graph and "* " or "") .. "commit " .. c.sha .. dec)
  if #c.parents > 1 then
    local t = {}
    for _, x in ipairs(c.parents) do t[#t + 1] = abbrev(x) end
    p("Merge: " .. table.concat(t, " "))
  end
  p("Author: " .. c.who)
  p("Date:   " .. (c.dateStr or epochDate(c.ts, c.tz)))
  p("")
  for l in (msg .. "\n"):gmatch("(.-)\n") do p("    " .. l) end
  if not last then print(graph and "|" or "") end
end

C.log = function(args)
  needRepo()
  local o = parseOpts(args, { n = true, ["max-count"] = true, format = true, pretty = true, author = true, grep = true, since = true, skip = true })
  local count = o.num or tonumber(o.v.n and o.v.n[1] or o.v["max-count"] and o.v["max-count"][1] or "") or nil
  local fmt = o.v.format and o.v.format[1] or o.v.pretty and o.v.pretty[1]
  local opts = { oneline = o.f.oneline }
  if fmt then
    if fmt == "oneline" then opts.oneline = true
    elseif fmt:match("^format:") or fmt:match("^tformat:") then opts.format = fmt:gsub("^t?format:", "")
    elseif fmt ~= "medium" and fmt ~= "full" and fmt ~= "fuller" then opts.format = fmt end
  end
  local starts, stops, specs = {}, {}, {}
  local function addRev(r)
    local x, y = r:match("^(.-)%.%.(.+)$")
    if x then
      stops[#stops + 1] = revOrDie(x == "" and "HEAD" or x)
      starts[#starts + 1] = revOrDie(y)
    elseif r:sub(1, 1) == "^" then stops[#stops + 1] = revOrDie(r:sub(2))
    else starts[#starts + 1] = revOrDie(r) end
  end
  for _, p in ipairs(o.pos) do
    if not o.hasDD and (resolve(p:gsub("%.%..*$", "")) or p:find("%.%.") or p:sub(1, 1) == "^") then addRev(p) else specs[#specs + 1] = p end
  end
  for _, p in ipairs(o.dd) do specs[#specs + 1] = p end
  if o.f.all then
    for _, t in ipairs({ "refs/heads", "refs/tags", "refs/remotes" }) do for _, sha in pairs(listRefs(t)) do starts[#starts + 1] = peel(sha) end end
  end
  if #starts == 0 then
    local h = headSha()
    if not h then
      local br = readHead()
      die("fatal: your current branch '" .. (br or "HEAD") .. "' does not have any commits yet")
    end
    starts[1] = h
  end
  local hide = {}
  for _, s in ipairs(stops) do for k in pairs(ancestors(s)) do hide[k] = true end end
  local list = history(starts, nil)
  local shown = {}
  local filter = #specs > 0 and pathMatchers(specs) or nil
  local author, grep = o.v.author and o.v.author[1], o.v.grep and o.v.grep[1]
  local skip = tonumber(o.v.skip and o.v.skip[1] or "0") or 0
  for _, c in ipairs(list) do
    local ok = not hide[c.sha]
    if ok and not c.missing then
      if author and not c.who:find(author, 1, true) then ok = false end
      if grep and not c.msg:find(grep, 1, true) then ok = false end
      if ok and filter then
        local pf = c.parents[1] and commitFlat(c.parents[1]) or {}
        local fl = commitFlat(c.sha) or {}
        ok = #changeList(pf or {}, fl, function(p) return matchAny(p, filter) end) > 0
      end
    end
    if ok then
      if skip > 0 then skip = skip - 1 else shown[#shown + 1] = c end
    end
    if count and #shown >= count then break end
  end
  -- the walk ended at a commit this device does not have: the rest comes from GitHub
  local tail = shown[#shown]
  if tail and tail.missing then
    shown[#shown] = nil
    local meta = fs.exists(join(metaDir(), "remote")) and loadMeta() or nil
    if meta and meta.owner and not filter then
      local want = count and (count - #shown) or 10
      if want > 0 then
        local list2 = api(meta.owner, meta.repo, "/commits?per_page=" .. math.max(1, math.min(want, 100)) .. "&sha=" .. tail.sha)
        for _, rc in ipairs(list2) do
          local au = (rc.commit and rc.commit.author) or {}
          local mm = (rc.commit and rc.commit.message) or ""
          local fake = { sha = rc.sha, parents = {}, msg = mm, who = (au.name or "?") .. " <" .. (au.email or "?") .. ">",
                         ts = 0, tz = "+0000", dateStr = gitDate(au.date or "") }
          shown[#shown + 1] = fake
        end
      end
    end
  end
  local deco = decorations()
  if o.f["no-decorate"] then deco = {} end
  if o.f.reverse then
    local r = {}
    for i = #shown, 1, -1 do r[#r + 1] = shown[i] end
    shown = r
  end
  for k, c in ipairs(shown) do
    printCommit(c, opts, deco, o.f.graph, k == #shown)
    if (o.f.p or o.f.patch or o.f.stat) and not c.dateStr then
      local pf = c.parents[1] and commitFlat(c.parents[1]) or {}
      local ch = changeList(pf or {}, commitFlat(c.sha) or {})
      if o.f.stat then printStat(ch, false) else print(""); patchHeaderPrint(ch) end
      if k < #shown then print("") end
    end
  end
end

C.show = function(args)
  needRepo()
  local o = parseOpts(args, { format = true, pretty = true })
  local rev = o.pos[1] or "HEAD"
  if rev:find(":", 1, true) then
    local r, path = rev:match("^(.-):(.*)$")
    local sha = revOrDie(r == "" and "HEAD" or r)
    local e = (commitFlat(sha) or {})[path]
    if not e then die("fatal: path '" .. path .. "' does not exist in '" .. r .. "'") end
    io.stdout:write(getBlob(e.sha) or "")
    return
  end
  local sha = resolve(rev)
  if not sha then
    die("fatal: ambiguous argument '" .. rev .. "': unknown revision or path not in the working tree.\nUse '--' to separate paths from revisions, like this:\n'git <command> [<revision>...] -- [<file>...]'")
  end
  local c = getCommit(sha)
  if not c then die("fatal: bad object " .. rev) end
  local fmt = o.v.format and o.v.format[1] or o.v.pretty and o.v.pretty[1]
  local opts = { oneline = o.f.oneline or fmt == "oneline" }
  if fmt and fmt ~= "oneline" then opts.format = fmt:gsub("^t?format:", "") end
  printCommit(c, opts, decorations(), false, true)
  if opts.format or o.f.quiet or o.f.s then return end
  local pf = c.parents[1] and commitFlat(c.parents[1]) or {}
  local ch = changeList(pf or {}, commitFlat(c.sha) or {})
  if o.f.stat then print(""); printStat(ch, false) return end
  if #c.parents > 1 then return end
  print("")
  patchHeaderPrint(ch)
end

-- ---------------------------------------------------------------- rm, mv, restore, reset, clean
C.rm = function(args)
  needRepo()
  local o = parseOpts(args, {})
  local specs = allPaths(o)
  if #specs == 0 then die("usage: git rm [<options>] [--] <file>...", 129) end
  local idx = loadIndex()
  local headFlat = commitFlat(headSha()) or {}
  local cached, force, recursive = o.f.cached, o.f.f or o.f.force, o.f.r
  local victims = {}
  for _, spec in ipairs(specs) do
    local m = specMatcher(spec)
    local hit = false
    for _, p in ipairs(sortedKeys(idx)) do
      if m(p) then
        hit = true
        local rel = relPath(spec)
        if p ~= rel and not recursive and not spec:find("[%*%?]") then
          die("fatal: not removing '" .. spec .. "' recursively without -r")
        end
        victims[p] = true
      end
    end
    if not hit then die("fatal: pathspec '" .. spec .. "' did not match any files") end
  end
  if not force then
    local modified, stagedChg = {}, {}
    for p in pairs(victims) do
      local e = idx[p]
      local w = readWork(join(R.root, p))
      local h = headFlat[p]
      local indexDiffers = not h or h.sha ~= e.sha
      local workDiffers = w ~= nil and w ~= getBlob(e.sha)
      if indexDiffers and workDiffers then modified[#modified + 1] = p
      elseif not cached and workDiffers then modified[#modified + 1] = p
      elseif not cached and indexDiffers then stagedChg[#stagedChg + 1] = p
      elseif cached and indexDiffers and h then stagedChg[#stagedChg + 1] = p end
    end
    table.sort(modified); table.sort(stagedChg)
    if #modified > 0 then
      die("error: the following " .. (#modified == 1 and "file has" or "files have") .. " local modifications:\n    " .. table.concat(modified, "\n    ") ..
          "\n(use --cached to keep the file, or -f to force removal)", 1)
    end
    if #stagedChg > 0 then
      die("error: the following " .. (#stagedChg == 1 and "file has" or "files have") .. " changes staged in the index:\n    " .. table.concat(stagedChg, "\n    ") ..
          "\n(use --cached to keep the file, or -f to force removal)", 1)
    end
  end
  for _, p in ipairs(sortedKeys(victims)) do
    if not o.f.q and not o.f.quiet then print("rm '" .. p .. "'") end
    idx[p] = nil
    if not cached then
      fs.remove(join(R.root, p))
      pruneDirs(parent(join(R.root, p)), R.root)
    end
  end
  saveIndex(idx)
end

C.mv = function(args)
  needRepo()
  local o = parseOpts(args, {})
  local list = allPaths(o)
  if #list < 2 then die("usage: git mv [<options>] <source>... <destination>", 129) end
  local idx = loadIndex()
  local dest = table.remove(list)
  local destRel = relPath(dest)
  local destIsDir = fs.isdir(join(R.root, destRel)) and true or false
  if not destIsDir then for p in pairs(idx) do if p:sub(1, #destRel + 1) == destRel .. "/" then destIsDir = true break end end end
  if #list > 1 and not destIsDir then die("fatal: destination '" .. dest .. "' is not a directory") end
  for _, src in ipairs(list) do
    local s = relPath(src)
    local t = destIsDir and (destRel .. "/" .. (s:match("[^/]*$"))) or destRel
    local moves = {}
    if idx[s] then moves[s] = t
    else
      for p in pairs(idx) do if p:sub(1, #s + 1) == s .. "/" then moves[p] = t .. p:sub(#s + 1) end end
    end
    if next(moves) == nil then die("fatal: bad source, source=" .. src .. ", destination=" .. dest) end
    for from, to in pairs(moves) do
      if (idx[to] or fs.exists(join(R.root, to))) and not (o.f.f or o.f.force) then
        die("fatal: destination exists, source=" .. src .. ", destination=" .. dest)
      end
    end
    for from, to in pairs(moves) do
      local data = readWork(join(R.root, from))
      if data ~= nil then
        writeFile(join(R.root, to), data)
        fs.remove(join(R.root, from))
        pruneDirs(parent(join(R.root, from)), R.root)
      end
      idx[to] = idx[from]
      idx[from] = nil
    end
  end
  saveIndex(idx)
end

C.restore = function(args)
  needRepo()
  local o = parseOpts(args, { s = true, source = true })
  local specs = allPaths(o)
  if #specs == 0 then die("fatal: you must specify path(s) to restore", 128) end
  local staged, worktree = o.f.S or o.f.staged, o.f.W or o.f.worktree
  if not staged and not worktree then worktree = true end
  local src = o.v.s and o.v.s[1] or o.v.source and o.v.source[1]
  local sha
  if src then sha = revOrDie(src)
  elseif staged then sha = headSha() end
  if staged and not sha then
    die("fatal: could not resolve 'HEAD'")
  end
  if src and worktree and not staged then
    restorePaths(sha, specs, false, true)
    return
  end
  restorePaths(staged and sha or nil, specs, staged and true or false, worktree and true or false)
end

C.reset = function(args)
  needRepo()
  local o = parseOpts(args, {})
  local branch, headS = readHead()
  local mode = o.f.hard and "hard" or o.f.soft and "soft" or o.f.mixed and "mixed" or "mixed"
  local rev, specs = nil, {}
  for _, p in ipairs(o.pos) do
    if not rev and not o.hasDD and resolve(p) then rev = p else specs[#specs + 1] = p end
  end
  for _, p in ipairs(o.dd) do specs[#specs + 1] = p end
  if #specs > 0 then
    -- unstage paths
    local sha = rev and revOrDie(rev) or headS
    local idx = loadIndex()
    local flat = sha and commitFlat(sha) or {}
    local m = pathMatchers(specs)
    local pool = {}
    for p in pairs(idx) do pool[p] = true end
    for p in pairs(flat) do pool[p] = true end
    local any = false
    for p in pairs(pool) do
      if matchAny(p, m) then
        any = true
        local e = flat[p]
        idx[p] = e and { sha = e.sha, mode = e.mode, size = #(getBlob(e.sha) or "") } or nil
      end
    end
    if not any then die("fatal: ambiguous argument '" .. specs[1] .. "': unknown revision or path not in the working tree.\nUse '--' to separate paths from revisions, like this:\n'git <command> [<revision>...] -- [<file>...]'") end
    saveIndex(idx)
    local _, unstaged = computeStatus(idx, flat)
    local rows = {}
    for _, p in ipairs(sortedKeys(unstaged)) do if matchAny(p, m) then rows[#rows + 1] = unstaged[p] .. "\t" .. p end end
    if #rows > 0 then print("Unstaged changes after reset:"); for _, r in ipairs(rows) do print(r) end end
    return
  end
  local target = rev and revOrDie(rev) or headS
  if not target then
    if rev then die("fatal: ambiguous argument '" .. rev .. "': unknown revision or path not in the working tree.") end
    saveIndex({})
    return
  end
  if not getCommit(target) and not commitFlat(target) then die("fatal: Could not parse object '" .. tostring(rev) .. "'.") end
  local newFlat = commitFlat(target) or {}
  if mode ~= "soft" then
    local idx = loadIndex()
    if mode == "hard" then
      local oldFlat = {}
      for p, e in pairs(idx) do oldFlat[p] = e end
      for p, e in pairs(commitFlat(headS) or {}) do oldFlat[p] = oldFlat[p] or e end
      -- every tracked file goes back to the commit; untracked files stay
      local out = {}
      for p, e in pairs(newFlat) do
        local data = getBlob(e.sha) or ""
        if readWork(join(R.root, p)) ~= data then writeFile(join(R.root, p), data) end
        out[p] = { sha = e.sha, mode = e.mode, size = #data }
      end
      for p in pairs(oldFlat) do
        if not newFlat[p] and readWork(join(R.root, p)) then
          fs.remove(join(R.root, p))
          pruneDirs(parent(join(R.root, p)), R.root)
        end
      end
      saveIndex(out)
      for _, f in ipairs({ "MERGE_HEAD", "MERGE_MSG" }) do if fs.exists(R.gd .. "/" .. f) then fs.remove(R.gd .. "/" .. f) end end
      saveUnmerged({})
    else
      local out = {}
      for p, e in pairs(newFlat) do out[p] = { sha = e.sha, mode = e.mode, size = #(getBlob(e.sha) or "") } end
      saveIndex(out)
    end
  end
  if target ~= headS then moveHead(target) end
  if mode == "hard" then
    print("HEAD is now at " .. abbrev(target) .. " " .. subjectOf(target))
  elseif mode == "mixed" then
    local _, unstaged = computeStatus(nil, newFlat)
    local rows = {}
    for _, p in ipairs(sortedKeys(unstaged)) do rows[#rows + 1] = unstaged[p] .. "\t" .. p end
    if #rows > 0 then print("Unstaged changes after reset:"); for _, r in ipairs(rows) do print(r) end end
  end
end

C.clean = function(args)
  needRepo()
  local o = parseOpts(args, {})
  local dry = o.f.n or o.f["dry-run"]
  if not dry and not o.f.f and not o.f.force then
    die("fatal: clean.requireForce defaults to true and neither -i, -n, nor -f given; refusing to clean", 128)
  end
  local idx = loadIndex()
  local list = untrackedList(idx)
  local m = #allPaths(o) > 0 and pathMatchers(allPaths(o)) or {}
  for _, p in ipairs(list) do
    local isDir = p:sub(-1) == "/"
    if (not isDir or o.f.d) and matchAny((p:gsub("/$", "")), m) then
      print((dry and "Would remove " or "Removing ") .. p)
      if not dry then
        if isDir then
          local files = walkTree(p:sub(1, -2), {}, true)
          for _, f in ipairs(files) do fs.remove(join(R.root, f)) end
          pruneDirs(join(R.root, p:sub(1, -2)), R.root)
        else
          fs.remove(join(R.root, p))
          pruneDirs(parent(join(R.root, p)), R.root)
        end
      end
    elseif isDir then
      print((dry and "Would skip repository " or "Skipping ") .. p)
    end
  end
end

-- ---------------------------------------------------------------- tag
C.tag = function(args)
  needRepo()
  local o = parseOpts(args, { m = true, message = true, F = true, n = false })
  local tags = listRefs("refs/tags")
  local pos = o.pos
  if o.f.d or o.f.delete then
    local failed = false
    for _, name in ipairs(pos) do
      local sha = tags[name]
      if not sha then eprint("error: tag '" .. name .. "' not found."); failed = true
      else delRef("refs/tags/" .. name); print("Deleted tag '" .. name .. "' (was " .. abbrev(sha) .. ")") end
    end
    if failed then os.exit(1) end
    return
  end
  if #pos == 0 or o.f.l or o.f.list then
    local pat = pos[1]
    for _, name in ipairs(sortedKeys(tags)) do
      if not pat or name:match("^" .. globToPattern(pat) .. "$") then
        if o.f.n then print(string.format("%-15s %s", name, subjectOf(peel(tags[name])))) else print(name) end
      end
    end
    return
  end
  local name = pos[1]
  if not validBranchName(name) then die("fatal: '" .. name .. "' is not a valid tag name.") end
  if tags[name] and not (o.f.f or o.f.force) then die("fatal: tag '" .. name .. "' already exists") end
  local target = pos[2] or "HEAD"
  local sha = resolve(target)
  if not sha then die("fatal: Failed to resolve '" .. target .. "' as a valid ref.") end
  local msg = o.v.m and table.concat(o.v.m, "\n\n") or o.v.message and table.concat(o.v.message, "\n\n")
  if o.f.a or o.f.annotate or msg then
    if not msg then
      eprint("hint: Waiting for your editor to close the file...")
      die("error: There was a problem with the editor 'vi'.\nPlease supply the message using either -m or -F option.", 1)
    end
    local who = identity()
    local data = "object " .. sha .. "\ntype commit\ntag " .. name .. "\ntagger " .. who .. " " .. now() .. " +0000\n\n" .. msg .. "\n"
    sha = putObject("tag", data)
  end
  setRef("refs/tags/" .. name, sha)
end

-- ---------------------------------------------------------------- config
C.config = function(args)
  local o = parseOpts(args, { file = true, f = true })
  local global = o.f.global or o.f.system
  if not global then
    local root = findRepo(fs.cwd())
    if root then R = { root = root, gd = join(root, ".git") }
    else die("fatal: --local can only be used inside a git repository", 128) end
  end
  local pos = o.pos
  local function show(list, pre)
    for _, e in ipairs(list) do print(e.sec .. (e.sub and ("." .. e.sub) or "") .. "." .. e.key .. "=" .. e.val) end
  end
  if o.f.l or o.f.list then
    if global then show(loadCfg(true)) else show(loadCfg(true)); show(loadCfg(false)) end
    return
  end
  if o.f.unset or o["unset-all"] then
    if not pos[1] then die("error: wrong number of arguments, should be 1", 129) end
    if not cfgUnset(pos[1], global) then os.exit(5) end
    return
  end
  if o.f.get or (#pos == 1 and not o.f.add) then
    local key = pos[1]
    if not key or not splitKey(key) then die("error: key does not contain a section: " .. tostring(key), 1) end
    local v = global and cfgGetIn(loadCfg(true), key) or cfgGet(key)
    if v == nil then os.exit(1) end
    print(v)
    return
  end
  if o.f["get-all"] then
    for _, e in ipairs(global and loadCfg(true) or loadCfg(false)) do
      local k = e.sec .. (e.sub and ("." .. e.sub) or "") .. "." .. e.key
      if k:lower() == pos[1]:lower() then print(e.val) end
    end
    return
  end
  if #pos >= 2 then
    if not splitKey(pos[1]) then die("error: key does not contain a section: " .. pos[1], 1) end
    cfgSet(pos[1], pos[2], global, o.f.add)
    return
  end
  die("usage: git config [<options>]", 129)
end

-- ---------------------------------------------------------------- remote
C.remote = function(args)
  needRepo()
  local o = parseOpts(args, {})
  local pos = o.pos
  local cfg = loadCfg(false)
  local remotes = {}
  for _, e in ipairs(cfg) do
    if e.sec == "remote" and e.sub then remotes[e.sub] = remotes[e.sub] or {}; remotes[e.sub][e.key] = e.val end
  end
  local sub = pos[1]
  if not sub then
    for _, name in ipairs(sortedKeys(remotes)) do
      if o.f.v or o.f.verbose then
        print(name .. "\t" .. (remotes[name].url or "") .. " (fetch)")
        print(name .. "\t" .. (remotes[name].url or "") .. " (push)")
      else print(name) end
    end
    return
  end
  if sub == "add" then
    if not pos[2] or not pos[3] then die("usage: git remote add [<options>] <name> <url>", 129) end
    if remotes[pos[2]] then die("error: remote " .. pos[2] .. " already exists.", 3) end
    cfgSet("remote." .. pos[2] .. ".url", pos[3])
    cfgSet("remote." .. pos[2] .. ".fetch", "+refs/heads/*:refs/remotes/" .. pos[2] .. "/*")
  elseif sub == "remove" or sub == "rm" then
    if not remotes[pos[2] or ""] then die("error: No such remote: '" .. tostring(pos[2]) .. "'", 2) end
    cfgRemoveSection("remote", pos[2])
    for n in pairs(listRefs("refs/remotes/" .. pos[2])) do delRef("refs/remotes/" .. pos[2] .. "/" .. n) end
  elseif sub == "rename" then
    if not remotes[pos[2] or ""] then die("error: No such remote: '" .. tostring(pos[2]) .. "'", 2) end
    if remotes[pos[3] or ""] then die("error: remote " .. pos[3] .. " already exists.", 3) end
    local list = loadCfg(false)
    for _, e in ipairs(list) do if e.sec == "remote" and e.sub == pos[2] then e.sub = pos[3] end end
    writeFile(cfgFile(false), serializeConfig(list))
    for n, sha in pairs(listRefs("refs/remotes/" .. pos[2])) do
      setRef("refs/remotes/" .. pos[3] .. "/" .. n, sha)
      delRef("refs/remotes/" .. pos[2] .. "/" .. n)
    end
  elseif sub == "get-url" then
    if not remotes[pos[2] or ""] then die("error: No such remote '" .. tostring(pos[2]) .. "'", 2) end
    print(remotes[pos[2]].url or "")
  elseif sub == "set-url" then
    if not remotes[pos[2] or ""] then die("error: No such remote '" .. tostring(pos[2]) .. "'", 2) end
    cfgSet("remote." .. pos[2] .. ".url", pos[3] or "")
  elseif sub == "show" then
    if not remotes[pos[2] or ""] then die("fatal: '" .. tostring(pos[2]) .. "' does not appear to be a git repository\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.", 128) end
    print("* remote " .. pos[2])
    print("  Fetch URL: " .. (remotes[pos[2]].url or ""))
    print("  Push  URL: " .. (remotes[pos[2]].url or ""))
  else
    die("error: Unknown subcommand: " .. sub, 129)
  end
end

-- ---------------------------------------------------------------- push and fetch (no git transport here)
C.push = function(args)
  needRepo()
  local o = parseOpts(args, { o = true, ["push-option"] = true })
  local cfg = loadCfg(false)
  local urls = {}
  for _, e in ipairs(cfg) do if e.sec == "remote" and e.key == "url" then urls[e.sub] = e.val end end
  local name = o.pos[1]
  local br = readHead()
  local upstream = br and cfgGet("branch." .. br .. ".remote")
  if not name or (#o.pos == 1 and not upstream and (urls[name] or not name:find("[:/@]"))) then
    name = name or upstream or (urls.origin and "origin") or nil
    if name and not upstream and br then
      die("fatal: The current branch " .. br .. " has no upstream branch.\nTo push the current branch and set the remote as upstream, use\n\n    git push --set-upstream " .. name .. " " .. br ..
          "\n\nTo have this happen automatically for branches without a tracking\nupstream, see 'push.autoSetupRemote' in 'git help config'.\n", 128)
    end
    if not name then
      die("fatal: No configured push destination.\nEither specify the URL from the command-line or configure a remote repository using\n\n    git remote add <name> <url>\n\nand then push using the remote name\n\n    git push <name>\n", 128)
    end
  end
  local url = urls[name]
  if not url then
    if name:find("://", 1, true) or name:find("^git@") then url = name
    else die("fatal: '" .. name .. "' does not appear to be a git repository\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.", 128) end
  end
  die("fatal: unable to access '" .. url .. "': this device cannot push (no git transport; clone and pull work through the GitHub web API)", 128)
end

C.fetch = function(args)
  needRepo()
  local o = parseOpts(args, {})
  local cfg = loadCfg(false)
  local urls, count = {}, 0
  for _, e in ipairs(cfg) do if e.sec == "remote" and e.key == "url" then urls[e.sub] = e.val; count = count + 1 end end
  local name = o.pos[1]
  if not name and count == 0 then
    die("fatal: No remote repository specified.  Please, specify either a URL or a\nremote name from which new revisions should be fetched.", 128)
  end
  name = name or "origin"
  if not urls[name] then
    die("fatal: '" .. name .. "' does not appear to be a git repository\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.", 128)
  end
  if not fs.exists(join(metaDir(), "remote")) then
    die("fatal: unable to access '" .. urls[name] .. "': this device cannot fetch from it (only github.com repositories cloned here are supported)", 128)
  end
  local meta = loadMeta()
  local remote = fetchRemote(meta.owner, meta.repo)
  if remote.head == meta.head then return end
  print("From https://github.com/" .. meta.owner .. "/" .. meta.repo)
  print(string.format("   %s..%s  %s       -> origin/%s", meta.head:sub(1, 7), remote.head:sub(1, 7), remote.branch, remote.branch))
  setRef("refs/remotes/origin/" .. remote.branch, remote.head)
end

-- ---------------------------------------------------------------- stash
local function stashList()
  local t = {}
  for l in (fs.exists(join(metaDir(), "stash")) and readFile(join(metaDir(), "stash")) or ""):gmatch("[^\n]+") do t[#t + 1] = l end
  return t
end
local function saveStash(t)
  if #t == 0 then if fs.exists(join(metaDir(), "stash")) then fs.remove(join(metaDir(), "stash")) end
  else writeFile(join(metaDir(), "stash"), table.concat(t, "\n") .. "\n") end
end
local function stashIndexArg(a)
  local n = (a or "stash@{0}"):match("^stash@{(%d+)}$")
  return tonumber(n or "0") or 0
end

local function hardReset(sha)
  local flat = commitFlat(sha) or {}
  local idx = loadIndex()
  local out = {}
  for p, e in pairs(flat) do
    local data = getBlob(e.sha) or ""
    if readWork(join(R.root, p)) ~= data then writeFile(join(R.root, p), data) end
    out[p] = { sha = e.sha, mode = e.mode, size = #data }
  end
  for p in pairs(idx) do
    if not flat[p] and readWork(join(R.root, p)) then fs.remove(join(R.root, p)); pruneDirs(parent(join(R.root, p)), R.root) end
  end
  saveIndex(out)
end

C.stash = function(args)
  needRepo()
  local o = parseOpts(args, { m = true, message = true })
  local sub = o.pos[1]
  if sub == "push" then table.remove(o.pos, 1); sub = nil
  elseif sub and sub ~= "list" and sub ~= "pop" and sub ~= "apply" and sub ~= "drop" and sub ~= "clear" and sub ~= "show" then
    die("error: unknown subcommand: " .. sub, 129)
  end
  local list = stashList()
  if sub == "list" then
    for i, sha in ipairs(list) do
      local c = getCommit(sha)
      print("stash@{" .. (i - 1) .. "}: " .. (c and subject(c) or sha))
    end
    return
  end
  if sub == "clear" then saveStash({}) return end
  if sub == "drop" or sub == "pop" or sub == "apply" or sub == "show" then
    local n = stashIndexArg(o.pos[2])
    local sha = list[n + 1]
    if not sha then die("error: " .. (o.pos[2] or "stash@{0}") .. " is not a valid reference", 1) end
    local c = getCommit(sha)
    local base = commitFlat(c.parents[1]) or {}
    local snap = commitFlat(sha) or {}
    if sub == "show" then
      local ch = changeList(base, snap)
      if o.f.p or o.f.patch then patchHeaderPrint(ch) else printStat(ch, false) end
      return
    end
    if sub ~= "drop" then
      local idx = loadIndex()
      local blocked = {}
      for _, p in ipairs(sortedKeys(snap)) do
        local b = base[p]
        if not b or b.sha ~= snap[p].sha then
          local w = readWork(join(R.root, p))
          local ie = idx[p]
          if (ie and w ~= getBlob(ie.sha)) or (not ie and w ~= nil) then blocked[#blocked + 1] = p end
        end
      end
      for p in pairs(base) do
        if not snap[p] and idx[p] and readWork(join(R.root, p)) ~= getBlob(idx[p].sha) then blocked[#blocked + 1] = p end
      end
      if #blocked > 0 then
        die("error: Your local changes to the following files would be overwritten by merge:\n\t" .. table.concat(blocked, "\n\t") ..
            "\nPlease commit your changes or stash them before you merge.\nAborting\nThe stash entry is kept in case you need it again.", 1)
      end
      for _, p in ipairs(sortedKeys(snap)) do
        local b = base[p]
        if not b or b.sha ~= snap[p].sha then
          local data = getBlob(snap[p].sha) or ""
          writeFile(join(R.root, p), data)
          if not b then idx[p] = { sha = snap[p].sha, mode = snap[p].mode, size = #data } end
        end
      end
      for p in pairs(base) do
        if not snap[p] then fs.remove(join(R.root, p)); idx[p] = nil; pruneDirs(parent(join(R.root, p)), R.root) end
      end
      saveIndex(idx)
      for _, l in ipairs(statusText(false)) do print(l) end
    end
    if sub ~= "apply" then
      table.remove(list, n + 1)
      saveStash(list)
      print("Dropped refs/stash@{" .. n .. "} (" .. sha .. ")")
    end
    return
  end
  -- push
  local branch, headS = readHead()
  if not headS then die("You do not have the initial commit yet", 1) end
  local idx = loadIndex()
  local staged, unstaged = computeStatus(idx, commitFlat(headS) or {})
  if next(staged) == nil and next(unstaged) == nil then
    print("No local changes to save")
    return
  end
  local snap = {}
  for p, e in pairs(idx) do
    local w = readWork(join(R.root, p))
    if w ~= nil then
      if w == getBlob(e.sha) then snap[p] = { sha = e.sha, mode = e.mode }
      else snap[p] = { sha = putObject("blob", w), mode = e.mode } end
    end
  end
  local m = o.v.m and o.v.m[1] or o.v.message and o.v.message[1]
  local text = m and ("On " .. (branch or "(no branch)") .. ": " .. m) or ("WIP on " .. (branch or "(no branch)") .. ": " .. abbrev(headS) .. " " .. subjectOf(headS))
  local sha = writeCommit(buildTree(snap), { headS }, text)
  table.insert(list, 1, sha)
  saveStash(list)
  hardReset(headS)
  print("Saved working directory and index state " .. text)
end

-- ---------------------------------------------------------------- plumbing: rev-parse, cat-file, ls-files
C["rev-parse"] = function(args)
  local o = parseOpts(args, {})
  if o.f["show-toplevel"] or o.f["git-dir"] or o.f["is-inside-work-tree"] or o.f["show-prefix"] or true then needRepo() end
  if o.f["show-toplevel"] then print(R.root) return end
  if o.f["git-dir"] then print(".git") return end
  if o.f["is-inside-work-tree"] then print("true") return end
  if o.f["is-bare-repository"] then print("false") return end
  if o.f["show-prefix"] then
    local rel = relPath(".")
    print(rel == "" and "" or (rel .. "/"))
    return
  end
  for _, rev in ipairs(o.pos) do
    if o.f["abbrev-ref"] then
      if rev == "HEAD" then
        local br = readHead()
        print(br or "HEAD")
      else print(rev) end
    else
      local sha = resolve(rev)
      if not sha then
        die("fatal: ambiguous argument '" .. rev .. "': unknown revision or path not in the working tree.\nUse '--' to separate paths from revisions, like this:\n'git <command> [<revision>...] -- [<file>...]'")
      end
      print((o.f.short and abbrev(sha)) or sha)
    end
  end
end

C["cat-file"] = function(args)
  needRepo()
  local o = parseOpts(args, {})
  local rev = o.pos[#o.pos]
  local sha = rev and resolve(rev)
  if not sha then die("fatal: Not a valid object name " .. tostring(rev)) end
  local typ, data = getObject(sha)
  if not typ then die("fatal: git cat-file: could not get object info") end
  if o.f.t then print(typ) elseif o.f.s then print(#data)
  elseif o.f.p then
    if typ == "tree" then
      for _, e in ipairs(parseTree(data)) do
        print(string.format("%06d %s %s\t%s", tonumber(e.mode), e.mode == "40000" and "tree" or "blob", e.sha, e.name))
      end
    else io.stdout:write(data) end
  else die("usage: git cat-file (-t | -s | -p) <object>", 129) end
end

C["ls-files"] = function(args)
  needRepo()
  local o = parseOpts(args, {})
  local idx = loadIndex()
  local m = pathMatchers(allPaths(o))
  for _, p in ipairs(sortedKeys(idx)) do
    if matchAny(p, m) then
      if o.f.s or o.f.stage then print(string.format("%s %s 0\t%s", idx[p].mode, idx[p].sha, p)) else print(p) end
    end
  end
end

-- ---------------------------------------------------------------- clone and pull (GitHub)
local pullCtx = {}
fetchBlobFile = function(path) return fetchFile(pullCtx.owner, pullCtx.repo, pullCtx.branch, path) end

C.clone = function(args)
  local o = parseOpts(args, { b = true, branch = true, depth = true, o = true })
  local url, dir = o.pos[1], o.pos[2]
  if not url then die("fatal: You must specify a repository to clone.\n\nusage: git clone [<options>] [--] <repo> [<dir>]", 129) end
  local owner, repo = parseUrl(url)
  if not owner then die("fatal: unable to access '" .. url .. "': only github.com repositories can be cloned here") end
  dir = dir or repo
  local shown = dir
  dir = normalize(fs.abspath(dir))
  if fs.exists(dir) and #(fs.list(dir) or {}) > 0 then
    die("fatal: destination path '" .. shown .. "' already exists and is not an empty directory.")
  end
  print("Cloning into '" .. shown .. "'...")
  local remote = fetchRemote(owner, repo)
  makeRepo(dir, remote.branch)
  R = { root = dir, gd = join(dir, ".git") }
  local meta = { owner = owner, repo = repo, branch = remote.branch, head = remote.head, tree = {}, order = {} }
  local idx, bytes = {}, 0
  for n, f in ipairs(remote.files) do
    local body = fetchFile(owner, repo, remote.branch, f.path)
    writeFile(join(dir, f.path), body)
    local sha = f.sha
    if not sha or #sha ~= 40 or sha:find("%X") then sha = putObject("blob", body) else putBlobKnown(sha, body) end
    meta.tree[f.path] = { sha = sha, size = #body }
    meta.order[#meta.order + 1] = f.path
    idx[f.path] = { sha = sha, mode = "100644", size = #body }
    bytes = bytes + #body
    if n % 10 == 0 then print(string.format("Receiving files: %d%% (%d/%d)", n * 100 // #remote.files, n, #remote.files)) end
  end
  saveIndex(idx)
  saveMeta(meta)
  local b = remote.branch
  if remote.head ~= "" then
    setRef("refs/heads/" .. b, remote.head)
    setRef("refs/remotes/origin/" .. b, remote.head)
  end
  writeFile(R.gd .. "/config", CONFIG_NEW .. '[remote "origin"]\n\turl = https://github.com/' .. owner .. "/" .. repo .. ".git\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n" ..
    '[branch "' .. b .. '"]\n\tremote = origin\n\tmerge = refs/heads/' .. b .. "\n")
  print(string.format("Receiving files: 100%% (%d/%d), %.2f KiB, done.", #remote.files, #remote.files, bytes / 1024))
  if remote.skipped > 0 then print("warning: " .. remote.skipped .. " file(s) over 1 MiB were left out") end
  if remote.truncated then print("warning: the file list from GitHub was cut short; some files are missing") end
end

C.pull = function(args)
  needRepo()
  local meta = fs.exists(join(metaDir(), "remote")) and loadMeta() or nil
  if not meta or not meta.owner then
    local n = 0
    for _, e in ipairs(loadCfg(false)) do if e.sec == "remote" and e.key == "url" then n = n + 1 end end
    local br = readHead() or "HEAD"
    die("There is no tracking information for the current branch.\nPlease specify which branch you want to merge with.\nSee git-pull(1) for details.\n\n    git pull <remote> <branch>\n\n" ..
        "If you wish to set tracking information for this branch you can do so with:\n\n    git branch --set-upstream-to=<remote>/<branch> " .. br, 1)
  end
  local remote = fetchRemote(meta.owner, meta.repo)
  local branch, headS = readHead()
  if remote.head == meta.head and remote.branch == meta.branch then
    print("Already up to date.")
    return
  end
  pullCtx = { owner = meta.owner, repo = meta.repo, branch = remote.branch }
  local theirs = {}
  for _, f in ipairs(remote.files) do
    theirs[f.path] = { sha = f.sha, mode = "100644" }
    if not fs.exists(objPath(f.sha)) then fetchHook[f.sha] = f.path end
  end
  print("From https://github.com/" .. meta.owner .. "/" .. meta.repo)
  print(string.format("   %s..%s  %s       -> origin/%s", meta.head:sub(1, 7), remote.head:sub(1, 7), remote.branch, remote.branch))
  local oldRemote = metaFlat()
  local newMeta = { owner = meta.owner, repo = meta.repo, branch = remote.branch, head = remote.head, tree = {}, order = {} }
  for _, f in ipairs(remote.files) do
    newMeta.tree[f.path] = { sha = f.sha, size = f.size }
    newMeta.order[#newMeta.order + 1] = f.path
  end
  if headS == meta.head then
    print("Updating " .. meta.head:sub(1, 7) .. ".." .. remote.head:sub(1, 7))
    local oldFlat = commitFlat(headS) or {}
    checkoutTree(oldFlat, theirs, false, "merge")
    print("Fast-forward")
    printStat(changeList(oldFlat, theirs), true)
    if branch then setRef("refs/heads/" .. branch, remote.head) else writeFile(R.gd .. "/HEAD", remote.head .. "\n") end
  else
    setRef("refs/remotes/origin/" .. remote.branch, remote.head)
    saveMeta(newMeta)
    flatCache = {}
    applyMerge(headS, remote.head, oldRemote, theirs, "HEAD", "origin/" .. remote.branch,
               "Merge branch '" .. remote.branch .. "' of https://github.com/" .. meta.owner .. "/" .. meta.repo)
  end
  setRef("refs/remotes/origin/" .. remote.branch, remote.head)
  saveMeta(newMeta)
  flatCache = {}
  if remote.skipped > 0 then print("warning: " .. remote.skipped .. " file(s) over 1 MiB were left out") end
end

-- ---------------------------------------------------------------- main
local args = {}
for i = 1, #arg do args[i] = arg[i] end
while args[1] and args[1]:sub(1, 1) == "-" do
  local a = args[1]
  if a == "-C" and args[2] then
    local ok = fs.chdir(args[2])
    if not ok then die("fatal: cannot change to '" .. args[2] .. "': No such file or directory") end
    table.remove(args, 1)
    table.remove(args, 1)
  elseif a == "-c" and args[2] then
    table.remove(args, 1)
    table.remove(args, 1)
  elseif a == "--no-pager" or a == "-P" or a == "-p" or a == "--paginate" or a:match("^%-%-git%-dir=") or a == "--no-optional-locks" or a == "--no-advice" then
    table.remove(args, 1)
  else
    break
  end
end
local sub = table.remove(args, 1)
if sub == nil then
  print(HELP)
  os.exit(1)
elseif sub == "--version" or sub == "version" or sub == "-v" then
  print(VERSION)
elseif sub == "--help" or sub == "-h" then
  print(HELP)
elseif sub == "help" then
  if args[1] == nil then print(HELP)
  else die("No manual entry for git-" .. args[1] .. "\nSee 'man 7 undocumented' for help when manual pages are not available.", 16) end
elseif C[sub] then
  C[sub](args)
else
  die("git: '" .. sub .. "' is not a git command. See 'git --help'.", 1)
end
