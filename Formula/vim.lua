#!lua
-- vim: a modal text editor in the style of Vim 9 (normal, insert, visual, command-line modes).
-- usage: vim [-R] [+N] FILE        There is no Esc key: Esc is Esc, Ctrl+G or Ctrl+C.
local COLS, ROWS = term.size()
local TEXT_ROWS = ROWS - 2            -- the last row is the command line, the one above it the status line

local path, readonly, startLine = nil, false, nil
for _, a in ipairs(arg) do
  if a == "-R" then readonly = true
  elseif a:match("^%+%d+$") then startLine = tonumber(a:sub(2))
  elseif not path then path = a end
end

local lines = {}
local modified = false
local message = ""
local function load(p)
  local content = p and fs.read(p)
  lines = {}
  if content then
    content = content:gsub("\r", "")
    for l in (content .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
    if content:sub(-1) == "\n" then lines[#lines] = nil end
    message = string.format('"%s" %dL, %dB', p, #lines, #content)
  elseif p then
    message = '"' .. p .. '" [New]'
  end
  if #lines == 0 then lines[1] = "" end
  modified = false
end
load(path)

local cy, cx, top, left = 1, 0, 1, 0
local mode = "n"                       -- n normal, i insert, v visual, V visual line, c command line
local pend = ""                        -- the unfinished normal-mode command
local cmdline, cmdtype = "", ":"
local anchorY, anchorX = 1, 0
local reg = { text = "", line = false }
local undo, redo = {}, {}
local marked = false
local lastFind, lastSearch, searchDir = nil, "", 1
local opt = { number = false, ignorecase = false }
local lastChange, curKeys, replaying = nil, {}, false
local curIsChange = false
local wantX = 0                        -- the column j and k try to keep
local quit = false

-- syntax colours by file extension -----------------------------------------------------------------------------------
local ext = path and path:match("%.([%w_]+)$") or ""
local comment = ({ lua = "--", py = "#", sh = "#", bash = "#", conf = "#", txt = nil, c = "//", h = "//", cpp = "//", js = "//",
                   go = "//", rs = "//", ino = "//", java = "//" })[ext]
local keywords = {}
for w in ([[if then else elseif end for while do function local return break in and or not nil true false def class import from
  as with pass try except finally lambda yield raise fi esac case done elif echo exit void int char long unsigned static const
  struct enum typedef include define switch default continue sizeof auto bool float double new delete this public private
  package func var let const fn mut use pub impl self]]):gmatch("%S+") do keywords[w] = true end

local function expand(s)                -- tabs become spaces (tabstop 8); returns the text and, per source index, its column
  if not s:find("\t", 1, true) then return s, nil end
  local out, map, col = {}, {}, 0
  for i = 1, #s do
    local c = s:sub(i, i)
    map[i] = col
    if c == "\t" then
      local n = 8 - col % 8
      out[#out + 1] = string.rep(" ", n)
      col = col + n
    else
      out[#out + 1] = c
      col = col + 1
    end
  end
  map[#s + 1] = col
  return table.concat(out), map
end

local function colorsFor(s)              -- one colour name per source character
  local cols, n, i = {}, #s, 1
  while i <= n do
    local c = s:sub(i, i)
    if comment and s:sub(i, i + #comment - 1) == comment then
      for j = i, n do cols[j] = "cyan" end
      break
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n and s:sub(j, j) ~= c do
        if s:sub(j, j) == "\\" then j = j + 1 end
        j = j + 1
      end
      for k = i, math.min(j, n) do cols[k] = "magenta" end
      i = j
    elseif c:match("%d") and not (s:sub(i - 1, i - 1)):match("[%w_]") then
      local j = i
      while j <= n and s:sub(j, j):match("[%w%.]") do cols[j] = "magenta"; j = j + 1 end
      i = j - 1
    elseif c:match("[%a_]") then
      local w = s:match("^[%w_]+", i)
      if keywords[w] then for k = i, i + #w - 1 do cols[k] = "yellow" end end
      i = i + #w - 1
    end
    i = i + 1
  end
  return cols
end

-- helpers -------------------------------------------------------------------------------------------------------------
local function clamp()
  if cy < 1 then cy = 1 end
  if cy > #lines then cy = #lines end
  local maxx = #lines[cy] - ((mode == "i" or mode == "v" or mode == "V") and 0 or 1)
  if mode == "v" and #lines[cy] > 0 then maxx = #lines[cy] - 1 end
  if cx > maxx then cx = maxx end
  if cx < 0 then cx = 0 end
end

local function snapshot()
  local t = {}
  for i = 1, #lines do t[i] = lines[i] end
  return { lines = t, y = cy, x = cx, mod = modified }
end
local function mark()                    -- once per command, before the first change
  if marked then return end
  marked = true
  undo[#undo + 1] = snapshot()
  if #undo > 100 then table.remove(undo, 1) end
  redo = {}
end
local function changed()
  modified = true
  curIsChange = true
end

local function numw() return opt.number and math.max(3, #tostring(#lines)) + 1 or 0 end

local function scroll()
  local tw = COLS - numw()
  if cy < top then top = cy end
  if cy >= top + TEXT_ROWS then top = cy - TEXT_ROWS + 1 end
  local _, map = expand(lines[cy])
  local dc = map and map[cx + 1] or cx
  if dc < left then left = dc end
  if dc >= left + tw then left = dc - tw + 1 end
end

local function toRegex(p)                -- a Vim pattern into a Lua pattern (what Lua can say; not alternation)
  local out, i = {}, 1
  if opt.ignorecase and not p:find("%u") then p = p:lower() end
  while i <= #p do
    local c = p:sub(i, i)
    if c == "\\" then
      local d = p:sub(i + 1, i + 1)
      i = i + 1
      if d == "+" or d == "?" then out[#out + 1] = d
      elseif d == "(" or d == ")" then out[#out + 1] = d
      elseif d == "d" then out[#out + 1] = "%d"
      elseif d == "s" then out[#out + 1] = "%s"
      elseif d == "w" then out[#out + 1] = "[%w_]"
      elseif d == "a" then out[#out + 1] = "%a"
      elseif d == "<" then out[#out + 1] = "%f[%w_]"
      elseif d == ">" then out[#out + 1] = "%f[^%w_]"
      elseif d == "t" then out[#out + 1] = "\t"
      elseif d:match("%w") then out[#out + 1] = d
      else out[#out + 1] = "%" .. d end
    elseif c == "[" then
      local j = p:find("]", i + 2, true)
      if j then out[#out + 1] = p:sub(i, j):gsub("%%", "%%%%"); i = j else out[#out + 1] = "%[" end
    elseif c == "%" or c == "(" or c == ")" or c == "+" or c == "?" or c == "-" then out[#out + 1] = "%" .. c
    else out[#out + 1] = c end
    i = i + 1
  end
  return table.concat(out)
end

local function lineFind(s, pat, init)
  if opt.ignorecase and not lastSearch:find("%u") then s = s:lower() end
  local ok, a, b = pcall(string.find, s, pat, init)
  if not ok then return nil end
  return a, b
end

local function search(pat, dir, fromY, fromX, quiet)
  if pat == "" then return nil end
  local lp = toRegex(pat)
  local n = #lines
  if dir > 0 then
    for step = 0, n do
      local y = (fromY - 1 + step) % n + 1
      local init = (step == 0) and fromX + 2 or 1
      if init <= #lines[y] + 1 then
        local a = lineFind(lines[y], lp, init)
        if a and not (step == n and a - 1 > fromX) then
          if not quiet and (y < fromY or (step > 0 and y == fromY and step == n)) then message = "search hit BOTTOM, continuing at TOP" end
          return y, a - 1
        end
      end
    end
  else
    for step = 0, n do
      local y = (fromY - 1 - step) % n + 1
      local best, init = nil, 1
      while init <= #lines[y] + 1 do
        local a = lineFind(lines[y], lp, init)
        if not a then break end
        if step > 0 or a - 1 < fromX then best = a - 1 end
        if step == 0 and a - 1 >= fromX then break end
        init = a + 1
      end
      if best then
        if not quiet and y > fromY then message = "search hit TOP, continuing at BOTTOM" end
        return y, best
      end
    end
  end
  if not quiet then message = "E486: Pattern not found: " .. pat end
  return nil
end

-- word motions --------------------------------------------------------------------------------------------------------
local function cls(ch, big)
  if ch == "" or ch == " " or ch == "\t" then return 0 end
  if big then return 1 end
  if ch:match("[%w_]") then return 1 end
  return 2
end
local function at(y, x) return lines[y]:sub(x + 1, x + 1) end
local function fwd(y, x)                 -- next position, the line end counts as one blank position; nil at the end
  if x < #lines[y] then return y, x + 1 end
  if y < #lines then return y + 1, 0 end
  return nil
end
local function back(y, x)
  if x > 0 then return y, x - 1 end
  if y > 1 then return y - 1, #lines[y - 1] end
  return nil
end

local function wordFwd(y, x, big)
  local c = cls(at(y, x), big)
  if c ~= 0 then
    while true do
      local ny, nx = fwd(y, x)
      if not ny then return y, #lines[y] end
      if ny ~= y then y, x = ny, nx; break end
      y, x = ny, nx
      if cls(at(y, x), big) ~= c then break end
    end
  else
    local ny, nx = fwd(y, x)
    if not ny then return y, x end
    y, x = ny, nx
  end
  while cls(at(y, x), big) == 0 do
    if x == 0 and #lines[y] == 0 and y > 0 then break end
    local ny, nx = fwd(y, x)
    if not ny then return y, #lines[y] end
    y, x = ny, nx
  end
  return y, x
end

local function wordEnd(y, x, big)
  local ny, nx = fwd(y, x)
  if not ny then return y, x end
  y, x = ny, nx
  while cls(at(y, x), big) == 0 do
    ny, nx = fwd(y, x)
    if not ny then return y, x end
    y, x = ny, nx
  end
  local c = cls(at(y, x), big)
  while x + 1 < #lines[y] and cls(at(y, x + 1), big) == c do x = x + 1 end
  return y, x
end

local function wordBack(y, x, big)
  local ny, nx = back(y, x)
  if not ny then return y, x end
  y, x = ny, nx
  while cls(at(y, x), big) == 0 do
    if x == 0 and #lines[y] == 0 then return y, 0 end
    ny, nx = back(y, x)
    if not ny then return y, 0 end
    y, x = ny, nx
  end
  local c = cls(at(y, x), big)
  while x > 0 and cls(at(y, x - 1), big) == c do x = x - 1 end
  return y, x
end

local function matchPair(y, x)
  local pairs_ = { ["("] = ")", ["["] = "]", ["{"] = "}", [")"] = "(", ["]"] = "[", ["}"] = "{" }
  local s = lines[y]
  local i = x + 1
  while i <= #s and not pairs_[s:sub(i, i)] do i = i + 1 end
  if i > #s then return nil end
  local open, close = s:sub(i, i), pairs_[s:sub(i, i)]
  local dir = (open == "(" or open == "[" or open == "{") and 1 or -1
  local depth, py, px = 0, y, i - 1
  while py do
    local c = at(py, px)
    if c == open then depth = depth + 1 elseif c == close then depth = depth - 1 end
    if depth == 0 then return py, px end
    if dir > 0 then py, px = fwd(py, px) else py, px = back(py, px) end
  end
  return nil
end

local function findChar(kind, ch, cnt)      -- f t F T on the current line
  local s, x = lines[cy], cx
  for _ = 1, cnt do
    if kind == "f" or kind == "t" then
      local nx = x + 1
      if kind == "t" and cnt == 1 and lastFind and lastFind.repeatT then nx = nx + 1 end
      local p = s:find(ch, nx + 1, true)
      if not p then return nil end
      x = p - 1
    else
      local nx = x - 1
      if kind == "T" and lastFind and lastFind.repeatT then nx = nx - 1 end
      local p = nil
      for j = nx, 0, -1 do if s:sub(j + 1, j + 1) == ch then p = j; break end end
      if not p then return nil end
      x = p
    end
  end
  if kind == "t" then x = x - 1 elseif kind == "T" then x = x + 1 end
  return x
end

-- motions return y, x, kind ("excl", "incl", "line") or nil ---------------------------------------------------------
local function motion(tok, cnt, hasCnt, isOp)
  local c = tok:sub(1, 1)
  local n = cnt
  if c == "h" or tok == "backspace" or tok == "left" then
    if cx == 0 then return nil end
    return cy, math.max(cx - n, 0), "excl"
  elseif c == "l" or c == " " or tok == "right" then
    local lim = #lines[cy] - (isOp and 0 or 1)
    if cx >= lim and not isOp then return nil end
    return cy, math.min(cx + n, math.max(lim, 0)), "excl"
  elseif c == "j" or tok == "down" or tok == "ctrl-n" then
    if cy + n > #lines and cy == #lines then return nil end
    return math.min(cy + n, #lines), nil, "line"
  elseif c == "k" or tok == "up" or tok == "ctrl-p" then
    if cy == 1 then return nil end
    return math.max(cy - n, 1), nil, "line"
  elseif c == "0" then return cy, 0, "excl"
  elseif c == "^" then return cy, (lines[cy]:find("%S") or #lines[cy] + 1) - 1, "excl"
  elseif c == "$" then
    local y = math.min(cy + n - 1, #lines)
    return y, math.max(#lines[y] - 1, 0), "incl"
  elseif c == "w" or c == "W" then
    local y, x = cy, cx
    for _ = 1, n do y, x = wordFwd(y, x, c == "W") end
    if isOp and y > cy and x > 0 then y, x = cy, #lines[cy] end   -- dw on the last word stops at the line end
    return y, x, "excl"
  elseif c == "b" or c == "B" then
    local y, x = cy, cx
    for _ = 1, n do y, x = wordBack(y, x, c == "B") end
    return y, x, "excl"
  elseif c == "e" or c == "E" then
    local y, x = cy, cx
    for _ = 1, n do y, x = wordEnd(y, x, c == "E") end
    return y, x, "incl"
  elseif tok == "gg" then
    return hasCnt and math.min(n, #lines) or 1, nil, "line"
  elseif c == "G" then
    return hasCnt and math.min(n, #lines) or #lines, nil, "line"
  elseif c == "f" or c == "t" or c == "F" or c == "T" then
    local ch = tok:sub(2, 2)
    lastFind = { kind = c, ch = ch }
    local x = findChar(c, ch, n)
    if not x then return nil end
    return cy, x, (c == "f" or c == "t") and "incl" or "excl"
  elseif c == ";" or c == "," then
    if not lastFind then return nil end
    local k = lastFind.kind
    if c == "," then k = ({ f = "F", F = "f", t = "T", T = "t" })[k] end
    lastFind.repeatT = true
    local x = findChar(k, lastFind.ch, n)
    lastFind.repeatT = nil
    if not x then return nil end
    return cy, x, (k == "f" or k == "t") and "incl" or "excl"
  elseif c == "%" then
    local y, x = matchPair(cy, cx)
    if not y then return nil end
    return y, x, "incl"
  elseif c == "}" then
    local y = cy
    for _ = 1, n do
      y = y + 1
      while y < #lines and lines[y] ~= "" do y = y + 1 end
    end
    y = math.min(y, #lines)
    return y, (y == #lines and lines[y] ~= "") and math.max(#lines[y] - 1, 0) or 0, "excl"
  elseif c == "{" then
    local y = cy
    for _ = 1, n do
      y = y - 1
      while y > 1 and lines[y] ~= "" do y = y - 1 end
    end
    return math.max(y, 1), 0, "excl"
  elseif c == "n" or c == "N" then
    local d = c == "n" and searchDir or -searchDir
    local y, x = search(lastSearch, d, cy, cx)
    if not y then return nil end
    return y, x, "excl"
  elseif c == "*" or c == "#" then
    local s = lines[cy]
    local i = cx + 1
    while i <= #s and not s:sub(i, i):match("[%w_]") do i = i + 1 end
    if i > #s then return nil end
    local a = i
    while a > 1 and s:sub(a - 1, a - 1):match("[%w_]") do a = a - 1 end
    local word = s:match("^[%w_]+", a)
    lastSearch = "\\<" .. word .. "\\>"
    searchDir = c == "*" and 1 or -1
    local y, x = search(lastSearch, searchDir, cy, a - 1)
    if not y then return nil end
    return y, x, "excl"
  elseif c == "H" then return top, nil, "line"
  elseif c == "L" then return math.min(top + TEXT_ROWS - 1, #lines), nil, "line"
  elseif c == "M" then return math.min(top + (TEXT_ROWS - 1) // 2, #lines), nil, "line"
  elseif c == "|" then return cy, math.min(n - 1, math.max(#lines[cy] - 1, 0)), "excl"
  elseif c == "_" then return math.min(cy + n - 1, #lines), nil, "line"
  elseif c == "+" or tok == "enter" then return math.min(cy + n, #lines), nil, "line"
  elseif c == "-" then return math.max(cy - n, 1), nil, "line"
  end
  return nil
end

-- text objects (after d c y v): iw aw i" a" i( a( i{ a{ i[ a[ ----------------------------------------------------------
local function textObject(kind, o)
  local s = lines[cy]
  if o == "w" or o == "W" then
    local big = o == "W"
    local a, b = cx, cx
    local c = cls(at(cy, cx), big)
    while a > 0 and cls(at(cy, a - 1), big) == c do a = a - 1 end
    while b + 1 < #s and cls(at(cy, b + 1), big) == c do b = b + 1 end
    if kind == "a" then
      if c ~= 0 and cls(at(cy, b + 1), big) == 0 then
        while b + 1 < #s and cls(at(cy, b + 1), big) == 0 do b = b + 1 end
      else
        while a > 0 and cls(at(cy, a - 1), big) == 0 do a = a - 1 end
      end
    end
    return cy, a, cy, b + 1
  elseif o == '"' or o == "'" or o == "`" then
    local a = nil
    for j = cx, 0, -1 do if s:sub(j + 1, j + 1) == o then a = j; break end end
    if not a then
      local f = s:find(o, cx + 1, true)
      if not f then return nil end
      a = f - 1
    end
    local b = s:find(o, a + 2, true)
    if not b then return nil end
    if kind == "i" then return cy, a + 1, cy, b - 1 end
    return cy, a, cy, b
  else
    local pairsT = { ["("] = ")", [")"] = "(", b = "(", ["{"] = "}", ["}"] = "{", B = "{", ["["] = "]", ["]"] = "[" }
    local open = pairsT[o]
    if not open then return nil end
    if o == ")" or o == "}" or o == "]" or o == "b" or o == "B" then
      open = (o == "b" or o == ")") and "(" or ((o == "B" or o == "}") and "{" or "[")
    else
      open = o
    end
    local close = ({ ["("] = ")", ["{"] = "}", ["["] = "]" })[open]
    local depth, y, x = 0, cy, cx
    if at(y, x) == close then depth = 0 end
    local oy, ox
    while y do
      local ch = at(y, x)
      if ch == close and not (y == cy and x == cx) then depth = depth + 1
      elseif ch == open then
        if depth == 0 then oy, ox = y, x; break end
        depth = depth - 1
      end
      y, x = back(y, x)
    end
    if not oy then return nil end
    local cy2, cx2 = matchPair(oy, ox)
    if not cy2 then return nil end
    if kind == "i" then return oy, ox + 1, cy2, cx2 end
    return oy, ox, cy2, cx2 + 1
  end
end

-- operators -----------------------------------------------------------------------------------------------------------
local function getRegion(y1, x1, y2, x2)     -- text from (y1,x1) up to but not including (y2,x2)
  if y1 == y2 then return lines[y1]:sub(x1 + 1, x2) end
  local t = { lines[y1]:sub(x1 + 1) }
  for y = y1 + 1, y2 - 1 do t[#t + 1] = lines[y] end
  t[#t + 1] = lines[y2]:sub(1, x2)
  return table.concat(t, "\n")
end

local function delRegion(y1, x1, y2, x2)
  local head, tail = lines[y1]:sub(1, x1), lines[y2]:sub(x2 + 1)
  for _ = y1 + 1, y2 do table.remove(lines, y1 + 1) end
  lines[y1] = head .. tail
end

local function setReg(text, line) reg = { text = text, line = line } end

local function insertMode() mode = "i" end

-- apply an operator over a region. kind: "line" or "excl"/"incl" (char positions)
local function applyOp(op, y1, x1, y2, x2, kind)
  if y2 < y1 or (y2 == y1 and x2 < x1) then y1, x1, y2, x2 = y2, x2, y1, x1 end
  if kind == "line" then
    if op == "y" then
      local t = {}
      for y = y1, y2 do t[#t + 1] = lines[y] end
      setReg(table.concat(t, "\n"), true)
      cy = y1
      if y2 > y1 then message = (y2 - y1 + 1) .. " lines yanked" end
      return
    end
    mark()
    if op == "d" or op == "c" then
      local t = {}
      for y = y1, y2 do t[#t + 1] = lines[y] end
      setReg(table.concat(t, "\n"), true)
      if op == "c" then
        for _ = y1 + 1, y2 do table.remove(lines, y1 + 1) end
        lines[y1] = ""
        cy, cx = y1, 0
        changed()
        insertMode()
        return
      end
      for _ = y1, y2 do table.remove(lines, y1) end
      if #lines == 0 then lines[1] = "" end
      cy = math.min(y1, #lines)
      cx = (lines[cy]:find("%S") or 1) - 1
      if y2 - y1 + 1 > 2 then message = (y2 - y1 + 1) .. " fewer lines" end
    elseif op == ">" or op == "<" then
      for y = y1, y2 do
        if op == ">" then
          if lines[y] ~= "" then lines[y] = "    " .. lines[y] end
        else
          local s = lines[y]
          if s:sub(1, 1) == "\t" then s = s:sub(2) else s = s:gsub("^    ", "", 1); if s == lines[y] then s = s:gsub("^ +", "", 1) end end
          lines[y] = s
        end
      end
      cy = y1
      cx = (lines[cy]:find("%S") or 1) - 1
    elseif op == "J" then
      -- handled elsewhere
    elseif op == "~" or op == "u" or op == "U" then
      for y = y1, y2 do
        lines[y] = op == "u" and lines[y]:lower() or (op == "U" and lines[y]:upper() or lines[y]:gsub("%a", function(c) return c:match("%l") and c:upper() or c:lower() end))
      end
      cy = y1
    end
    changed()
    return
  end
  if kind == "incl" then x2 = x2 + 1 end
  if kind == "excl" and y2 > y1 and x2 == 0 then
    y2 = y2 - 1
    x2 = #lines[y2]
  end
  if op == "y" then
    setReg(getRegion(y1, x1, y2, x2), false)
    cy, cx = y1, x1
    return
  end
  mark()
  if op == "d" or op == "c" then
    setReg(getRegion(y1, x1, y2, x2), false)
    delRegion(y1, x1, y2, x2)
    cy, cx = y1, x1
    changed()
    if op == "c" then insertMode() end
  elseif op == "~" or op == "u" or op == "U" then
    for y = y1, y2 do
      local a = (y == y1) and x1 or 0
      local b = (y == y2) and x2 or #lines[y]
      local mid = lines[y]:sub(a + 1, b)
      mid = op == "u" and mid:lower() or (op == "U" and mid:upper() or mid:gsub("%a", function(c) return c:match("%l") and c:upper() or c:lower() end))
      lines[y] = lines[y]:sub(1, a) .. mid .. lines[y]:sub(b + 1)
    end
    cy, cx = y1, x1
    changed()
  elseif op == ">" or op == "<" then
    applyOp(op, y1, 0, y2, 0, "line")
  end
end

local function putReg(after, cnt)
  if reg.text == "" and not reg.line then message = "E353: Nothing in register \""; return end
  mark()
  cnt = cnt or 1
  if reg.line then
    local new = {}
    for l in (reg.text .. "\n"):gmatch("(.-)\n") do new[#new + 1] = l end
    local at_ = after and cy or cy - 1
    for _ = 1, cnt do
      for i, l in ipairs(new) do table.insert(lines, at_ + 1 + (_ - 1) * #new + i - 1, l) end
    end
    cy = at_ + 1
    cx = (lines[cy]:find("%S") or 1) - 1
  else
    local text = string.rep(reg.text, cnt)
    local s = lines[cy]
    local pos = after and math.min(cx + 1, #s) or cx
    local parts = {}
    for l in (text .. "\n"):gmatch("(.-)\n") do parts[#parts + 1] = l end
    if #parts == 1 then
      lines[cy] = s:sub(1, pos) .. text .. s:sub(pos + 1)
      cx = pos + #text - 1
    else
      local tail = s:sub(pos + 1)
      lines[cy] = s:sub(1, pos) .. parts[1]
      for i = 2, #parts do table.insert(lines, cy + i - 1, parts[i]) end
      lines[cy + #parts - 1] = lines[cy + #parts - 1] .. tail
      cx = pos
    end
  end
  changed()
end

local function joinLines(cnt)
  mark()
  for _ = 1, math.max(cnt - 1, 1) do
    if cy >= #lines then break end
    local nxt = lines[cy + 1]:gsub("^%s+", "")
    local a = lines[cy]
    local sep = (a == "" or a:match("%s$") or nxt == "" or nxt:sub(1, 1) == ")") and "" or " "
    cx = #a
    lines[cy] = a .. sep .. nxt
    table.remove(lines, cy + 1)
  end
  changed()
end

-- ex commands ---------------------------------------------------------------------------------------------------------
local function writeFile(p, y1, y2)
  local t = {}
  for y = y1 or 1, y2 or #lines do t[#t + 1] = lines[y] end
  local data = table.concat(t, "\n") .. "\n"
  local ok, e = fs.write(p, data)
  if not ok then message = "E212: Can't open file for writing"; return false end
  message = string.format('"%s" %dL, %dB written', p, #t, #data)
  return true
end

local function substitute(y1, y2, pat, rep, flags)
  local lp = toRegex(pat)
  local count, lastY = 0, nil
  local global = flags:find("g", 1, true)
  local save = lastSearch
  lastSearch = pat
  for y = y1, y2 do
    local s, out, pos, did = lines[y], {}, 1, false
    while pos <= #s + 1 do
      local ok, a, b, c1, c2, c3, c4, c5, c6, c7, c8, c9 = pcall(string.find, s, lp, pos)
      if not ok or not a then break end
      if b < a and a > #s then break end
      out[#out + 1] = s:sub(pos, a - 1)
      local caps = { c1, c2, c3, c4, c5, c6, c7, c8, c9 }
      local whole = s:sub(a, b)
      local r = rep:gsub("\\(.)", function(ch)
        if ch:match("%d") then return ch == "0" and whole or (caps[tonumber(ch)] or "") end
        if ch == "&" then return "\1" end
        if ch == "n" or ch == "r" then return "\n" end
        if ch == "t" then return "\t" end
        return ch
      end):gsub("&", function() return whole end):gsub("\1", "&")
      out[#out + 1] = r
      did = true
      count = count + 1
      if b < a then
        out[#out + 1] = s:sub(a, a)
        pos = a + 1
      else
        pos = b + 1
      end
      if not global then break end
    end
    if did then
      out[#out + 1] = s:sub(pos)
      lines[y] = table.concat(out)
      lastY = y
    end
  end
  lastSearch = save ~= "" and pat or pat
  if count == 0 then message = "E486: Pattern not found: " .. pat; return end
  local joined = false
  for y = y1, #lines do
    if lines[y] and lines[y]:find("\n", 1, true) then joined = true break end
  end
  if joined then
    local i = y1
    while i <= #lines do
      if lines[i]:find("\n", 1, true) then
        local parts = {}
        for l in (lines[i] .. "\n"):gmatch("(.-)\n") do parts[#parts + 1] = l end
        lines[i] = parts[1]
        for k = 2, #parts do table.insert(lines, i + k - 1, parts[k]) end
        i = i + #parts - 1
      end
      i = i + 1
    end
  end
  changed()
  cy = lastY or cy
  cx = 0
  if count > 2 then message = count .. " substitutions on " .. (y2 - y1 + 1) .. " lines" end
end

local function runEx(cmd)
  cmd = cmd:gsub("^[%s:]+", "")
  if cmd == "" then return end
  -- the range
  local function addr(s)
    local a = s:match("^%.") and cy or nil
    if a then return a, s:sub(2) end
    a = s:match("^%$")
    if a then return #lines, s:sub(2) end
    local num = s:match("^%d+")
    if num then return tonumber(num), s:sub(#num + 1) end
    local mk = s:match("^'([<>])")
    if mk then return mk == "<" and math.min(anchorY, cy) or math.max(anchorY, cy), s:sub(3) end
    return nil, s
  end
  local y1, y2
  local rest = cmd
  if rest:sub(1, 1) == "%" then
    y1, y2, rest = 1, #lines, rest:sub(2)
  else
    local a, r = addr(rest)
    if a then
      local off = r:match("^([+-]%d+)")
      if off then a = a + tonumber(off); r = r:sub(#off + 1) end
      y1, rest = a, r
      if rest:sub(1, 1) == "," then
        local b, r2 = addr(rest:sub(2))
        local off2 = r2:match("^([+-]%d+)")
        if b and off2 then b = b + tonumber(off2); r2 = r2:sub(#off2 + 1) end
        y2, rest = b or y1, r2
      else
        y2 = y1
      end
    end
  end
  if y1 then
    y1 = math.max(1, math.min(y1, #lines)); y2 = math.max(y1, math.min(y2, #lines))
  end
  rest = rest:gsub("^%s+", "")
  local name = rest:match("^%a+") or rest:match("^[&<>!]") or ""
  local args = rest:sub(#name + 1)
  local bang = false
  if args:sub(1, 1) == "!" then bang = true; args = args:sub(2) end
  args = args:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" and y1 then cy = y1; cx = (lines[cy]:find("%S") or 1) - 1; return end
  if name == "s" or name == "substitute" or (name:match("^s$") == nil and rest:match("^s[/#,]")) then
    local body = rest:match("^s(.*)$")
    local d = body:sub(1, 1)
    local parts, cur, i = {}, {}, 2
    while i <= #body do
      local ch = body:sub(i, i)
      if ch == "\\" and body:sub(i + 1, i + 1) == d then cur[#cur + 1] = d; i = i + 1
      elseif ch == "\\" then cur[#cur + 1] = ch .. body:sub(i + 1, i + 1); i = i + 1
      elseif ch == d then parts[#parts + 1] = table.concat(cur); cur = {}
      else cur[#cur + 1] = ch end
      i = i + 1
    end
    parts[#parts + 1] = table.concat(cur)
    local pat = parts[1] ~= "" and parts[1] or lastSearch
    if readonly then message = "E45: 'readonly' option is set (add ! to override)"; return end
    mark()
    substitute(y1 or cy, y2 or cy, pat, parts[2] or "", parts[3] or "")
    return
  end
  if name == "w" or name == "write" then
    local target = args ~= "" and args or path
    if not target then message = "E32: No file name"; return end
    if readonly and not bang then message = "E45: 'readonly' option is set (add ! to override)"; return end
    if writeFile(target, y1, y2) and (not path or target == path) and not y1 then modified = false end
    if not path then path = target end
  elseif name == "q" or name == "quit" or name == "close" then
    if modified and not bang then message = "E37: No write since last change (add ! to override)"; return end
    quit = true
  elseif name == "qa" or name == "qall" or name == "cq" then
    if modified and not bang and name ~= "cq" then message = "E37: No write since last change (add ! to override)"; return end
    quit = true
  elseif name == "wq" or name == "x" or name == "xit" or name == "exit" or name == "wqa" or name == "xa" then
    local target = args ~= "" and args or path
    if not target then message = "E32: No file name"; return end
    if name ~= "x" and name ~= "xit" and name ~= "exit" or modified then
      if readonly and not bang then message = "E45: 'readonly' option is set (add ! to override)"; return end
      if not writeFile(target, nil, nil) then return end
    end
    quit = true
  elseif name == "e" or name == "edit" then
    if args == "" then
      if not path then message = "E32: No file name"; return end
      if modified and not bang then message = "E37: No write since last change (add ! to override)"; return end
      load(path)
    else
      if modified and not bang then message = "E37: No write since last change (add ! to override)"; return end
      path = args
      load(path)
      cy, cx, top, left = 1, 0, 1, 0
      undo, redo = {}, {}
    end
  elseif name == "set" or name == "se" then
    for w in args:gmatch("%S+") do
      local no, o = w:match("^(no)(%a+)$")
      if not no then o = w:match("^(%a+)$") end
      local v = not no
      if o == "number" or o == "nu" then opt.number = v
      elseif o == "nonumber" or o == "nonu" then opt.number = false
      elseif o == "ignorecase" or o == "ic" then opt.ignorecase = v
      elseif o == "hlsearch" or o == "hls" or o == "ruler" or o == "ru" or o == "wrap" or o == "syntax" or o == "list" then
      else message = "E518: Unknown option: " .. w end
    end
    if args == "nonu" then opt.number = false end
    if args == "nu" then opt.number = true end
  elseif name == "d" or name == "delete" then
    mark()
    applyOp("d", y1 or cy, 0, y2 or cy, 0, "line")
  elseif name == "y" or name == "yank" then
    applyOp("y", y1 or cy, 0, y2 or cy, 0, "line")
  elseif name == "noh" or name == "nohlsearch" or name == "syntax" or name == "redraw" then
  elseif name == ">" or name == "<" then
    mark()
    applyOp(name, y1 or cy, 0, y2 or cy, 0, "line")
  elseif name == "r" or name == "read" then
    local c = fs.read(args)
    if not c then message = "E484: Can't open file " .. args; return end
    mark()
    local at_ = y2 or cy
    local n = 0
    for l in (c:gsub("\n$", "") .. "\n"):gmatch("(.-)\n") do n = n + 1; table.insert(lines, at_ + n, l) end
    cy = at_ + 1
    changed()
  elseif name == "g" or name == "v" then
    message = "E492: Not an editor command: " .. cmd
  else
    message = "E492: Not an editor command: " .. cmd
  end
end

-- drawing -------------------------------------------------------------------------------------------------------------
local function visualRange()
  if mode ~= "v" and mode ~= "V" then return nil end
  local ay, ax, by, bx = anchorY, anchorX, cy, cx
  if ay > by or (ay == by and ax > bx) then ay, ax, by, bx = by, bx, ay, ax end
  return ay, ax, by, bx
end

local function draw()
  scroll()
  term.clear()
  local nw = numw()
  local tw = COLS - nw
  local vy1, vx1, vy2, vx2 = visualRange()
  for row = 0, TEXT_ROWS - 1 do
    local n = top + row
    local s = lines[n]
    if not s then
      term.text(0, row, "~", "blue")
    else
      if nw > 0 then term.text(0, row, string.format("%" .. (nw - 1) .. "d ", n), "yellow") end
      local shown, map = expand(s)
      local cols = colorsFor(s)
      local function colAt(i)             -- the colour of display column i (0-based)
        local src = i + 1
        if map then
          src = nil
          for j = 1, #s do if map[j] <= i and (map[j + 1] or 1e9) > i then src = j; break end end
          if not src then return "text" end
        end
        if vy1 and n >= vy1 and n <= vy2 then
          local x0 = src - 1
          if mode == "V" or ((n > vy1 or x0 >= vx1) and (n < vy2 or x0 <= vx2)) then return "inverse" end
        end
        return cols[src] or "text"
      end
      local i, last = left, math.min(#shown, left + tw)
      while i < last do
        local c = colAt(i)
        local j = i + 1
        while j < last and colAt(j) == c do j = j + 1 end
        term.text(nw + i - left, row, shown:sub(i + 1, j), c)
        i = j
      end
      if vy1 and (mode == "V" or (n >= vy1 and n < vy2)) and n >= vy1 and n <= vy2 and #s == 0 then term.put(nw, row, " ", "inverse") end
    end
  end
  -- the status line
  local name = path or "[No Name]"
  local left_ = " " .. name .. (modified and " [+]" or "") .. (readonly and " [RO]" or "")
  local pct = #lines <= TEXT_ROWS and "All" or (top == 1 and "Top" or (top + TEXT_ROWS > #lines and "Bot" or string.format("%d%%", (top - 1) * 100 // (#lines - TEXT_ROWS))))
  local _, map = expand(lines[cy])
  local vc = map and map[cx + 1] or cx
  local ruler = string.format("%d,%s  %s ", cy, (#lines[cy] == 0) and "0-1" or (vc == cx and tostring(cx + 1) or (cx + 1) .. "-" .. (vc + 1)), pct)
  if #left_ > COLS - #ruler - 1 then left_ = " <" .. left_:sub(-(COLS - #ruler - 4)) end
  local bar = left_ .. string.rep(" ", math.max(COLS - #left_ - #ruler, 1)) .. ruler
  term.text(0, ROWS - 2, string.format("%-" .. COLS .. "s", bar:sub(1, COLS)), "inverse")
  -- the command line
  local bottom
  if mode == "c" then bottom = cmdtype .. cmdline
  elseif message ~= "" then bottom = message
  elseif mode == "i" then bottom = "-- INSERT --"
  elseif mode == "v" then bottom = "-- VISUAL --"
  elseif mode == "V" then bottom = "-- VISUAL LINE --"
  else bottom = pend end
  if message == "" and mode ~= "c" and mode ~= "n" then bottom = bottom end
  term.text(0, ROWS - 1, bottom:sub(1, COLS), (message ~= "" and mode ~= "c" and message:match("^E%d")) and "red" or "white")
  if mode == "n" and message == "" and #pend > 0 then term.text(COLS - 12, ROWS - 1, pend:sub(1, 8), "white") end
  -- the cursor
  if mode == "c" then
    term.put(math.min(#cmdline + 1, COLS - 1), ROWS - 1, " ", "inverse")
  else
    local sx, sy = nw + vc - left, cy - top
    if sy >= 0 and sy < TEXT_ROWS and sx >= 0 and sx < COLS then
      local ch = lines[cy]:sub(cx + 1, cx + 1)
      if ch == "\t" then ch = " " end
      term.put(sx, sy, ch ~= "" and ch or " ", "inverse")
    end
  end
  term.flush()
end

-- command parser ------------------------------------------------------------------------------------------------------
local feed                              -- forward declaration: replays keys for the dot command
local keyQueue = {}

local function needMore(rest)           -- does this motion token still need characters?
  if rest == "" then return true end
  local c = rest:sub(1, 1)
  if (c == "g") and #rest < 2 then return true end
  if (c == "f" or c == "t" or c == "F" or c == "T") and #rest < 2 then return true end
  if (c == "i" or c == "a") and #rest < 2 then return true end
  return false
end

local function scrollBy(kind, cnt)
  local half = TEXT_ROWS // 2
  if kind == "ctrl-d" then
    cy = math.min(cy + half, #lines); top = math.min(top + half, math.max(#lines - TEXT_ROWS + 1, 1))
  elseif kind == "ctrl-u" then
    cy = math.max(cy - half, 1); top = math.max(top - half, 1)
  elseif kind == "ctrl-f" or kind == "pagedown" then
    cy = math.min(cy + TEXT_ROWS - 2, #lines); top = math.min(top + TEXT_ROWS - 2, math.max(#lines - 1, 1))
    if cy < top then cy = top end
  elseif kind == "ctrl-b" or kind == "pageup" then
    cy = math.max(cy - (TEXT_ROWS - 2), 1); top = math.max(top - (TEXT_ROWS - 2), 1)
  end
  cx = (lines[cy]:find("%S") or 1) - 1
end

local function moveTo(y, x, kind)
  cy = y
  if x then cx = x else cx = math.min(wantX, math.max(#lines[cy] - 1, 0)); end
  if kind == "line" and x == nil then
    -- j k and G keep the wanted column; gg G go to the first non blank
  end
end

local function runOperator(op, tok, cnt, hasCnt)
  -- tok is the motion (or the operator doubled for a whole line)
  if tok == op or (op == "g?" and tok == "g?") then
    local y2 = math.min(cy + cnt - 1, #lines)
    applyOp(op, cy, 0, y2, 0, "line")
    return true
  end
  local c = tok:sub(1, 1)
  if (c == "i" or c == "a") and #tok == 2 then
    local y1, x1, y2, x2 = textObject(c, tok:sub(2, 2))
    if not y1 then return false end
    applyOp(op, y1, x1, y2, x2, "excl")
    return true
  end
  if op == "c" and (tok == "w" or tok == "W") and cls(at(cy, cx), tok == "W") ~= 0 then tok = tok == "w" and "e" or "E" end
  local y, x, kind = motion(tok, cnt, hasCnt, true)
  if not y then return false end
  if kind == "line" then
    applyOp(op, cy, 0, y, 0, "line")
  else
    applyOp(op, cy, cx, y, x, kind)
  end
  return true
end

local function enterInsert(how)
  mark()
  local s = lines[cy]
  if how == "a" then cx = math.min(cx + 1, #s)
  elseif how == "A" then cx = #s
  elseif how == "I" then cx = (s:find("%S") or #s + 1) - 1
  elseif how == "o" then table.insert(lines, cy + 1, ""); cy = cy + 1; cx = 0
  elseif how == "O" then table.insert(lines, cy, ""); cx = 0
  end
  mode = "i"
  changed()
end

local ntoks = {}
local function normalKey(k)
  pend = pend .. (#k == 1 and k or ("<" .. k .. ">"))
  local raw = pend
  -- k is appended as a single token: keep the plain text form in "toks"
  local toks = ntoks
  toks[#toks + 1] = k
  local i = 1
  local function tok() return toks[i] end
  local cnt1 = nil
  local s1 = ""
  while toks[i] and toks[i]:match("^%d$") and not (s1 == "" and toks[i] == "0") do
    s1 = s1 .. toks[i]; i = i + 1
  end
  if s1 ~= "" then cnt1 = tonumber(s1) end
  if not toks[i] then return "more" end
  local c = toks[i]
  local function rest(from) return table.concat(toks, "", from) end
  local function done() pend = ""; ntoks = {}; return "done" end
  local cnt = cnt1 or 1

  -- operators
  if c == "d" or c == "c" or c == "y" or c == ">" or c == "<" or (c == "g" and (toks[i + 1] == "u" or toks[i + 1] == "U" or toks[i + 1] == "~")) then
    local op = c
    local j = i + 1
    if c == "g" then
      if not toks[j] then return "more" end
      op = toks[j]; j = j + 1
    end
    local s2 = ""
    while toks[j] and toks[j]:match("^%d$") and not (s2 == "" and toks[j] == "0") do s2 = s2 .. toks[j]; j = j + 1 end
    local total = cnt * (s2 ~= "" and tonumber(s2) or 1)
    local has = cnt1 ~= nil or s2 ~= ""
    if not toks[j] then return "more" end
    local m = rest(j)
    local first = toks[j]
    if needMore(m) then return "more" end
    if first == "i" or first == "a" or first == "f" or first == "t" or first == "F" or first == "T" or first == "g" then
      if #toks - j + 1 < 2 then return "more" end
    end
    local mm = toks[j]
    if mm == "g" or mm == "f" or mm == "t" or mm == "F" or mm == "T" or mm == "i" or mm == "a" then mm = mm .. toks[j + 1] end
    if first == "g" and mm ~= "gg" then done(); return "done" end
    if (c == "g" and mm == "g" .. op) then mm = op end
    if mm == op or (c == "g" and (mm == op)) then mm = op end
    local ok = runOperator(op, mm == (op) and op or mm, total, has)
    if not ok then message = "" end
    done()
    return "done", (op == "c" or op == "d" or op == ">" or op == "<" or op == "u" or op == "U" or op == "~")
  end

  local function simple(chg) done(); return "done", chg end
  if c == "g" then
    if not toks[i + 1] then return "more" end
    local n2 = toks[i + 1]
    if n2 == "g" then
      local y = cnt1 and math.min(cnt1, #lines) or 1
      cy = y; cx = (lines[cy]:find("%S") or 1) - 1
    elseif n2 == "J" then joinLines(cnt); return simple(true)
    elseif n2 == "p" or n2 == "P" then putReg(n2 == "p", cnt); return simple(true)
    elseif n2 == "e" or n2 == "E" then
      local y, x = cy, cx
      for _ = 1, cnt do
        local ny, nx = back(y, x)
        while ny and cls(at(ny, nx), n2 == "E") == 0 and (nx > 0 or #lines[ny] > 0) do ny, nx = back(ny, nx) end
        if ny then
          local cc = cls(at(ny, nx), n2 == "E")
          y, x = ny, nx
          local _ = cc
        end
      end
      cy, cx = y, x
    end
    return simple(false)
  end
  if c == "Z" then
    if not toks[i + 1] then return "more" end
    if toks[i + 1] == "Z" then runEx("x") elseif toks[i + 1] == "Q" then runEx("q!") end
    return simple(false)
  end
  if c == "r" then
    if not toks[i + 1] then return "more" end
    local ch = toks[i + 1]
    if #ch == 1 and #lines[cy] >= cx + cnt then
      mark()
      lines[cy] = lines[cy]:sub(1, cx) .. string.rep(ch, cnt) .. lines[cy]:sub(cx + cnt + 1)
      cx = cx + cnt - 1
      changed()
    elseif ch == "enter" and #lines[cy] > cx then
      mark()
      table.insert(lines, cy + 1, lines[cy]:sub(cx + 2))
      lines[cy] = lines[cy]:sub(1, cx)
      cy = cy + 1; cx = 0
      changed()
    end
    return simple(true)
  end
  if c == "f" or c == "t" or c == "F" or c == "T" then
    if not toks[i + 1] then return "more" end
    local y, x = motion(c .. toks[i + 1], cnt, cnt1 ~= nil, false)
    if y then cx = x end
    return simple(false)
  end
  if c == "x" or c == "delete" then
    if #lines[cy] > 0 then
      mark()
      local n = math.min(cnt, #lines[cy] - cx)
      setReg(lines[cy]:sub(cx + 1, cx + n), false)
      lines[cy] = lines[cy]:sub(1, cx) .. lines[cy]:sub(cx + n + 1)
      changed()
    end
    return simple(true)
  elseif c == "X" then
    if cx > 0 then
      mark()
      local n = math.min(cnt, cx)
      setReg(lines[cy]:sub(cx - n + 1, cx), false)
      lines[cy] = lines[cy]:sub(1, cx - n) .. lines[cy]:sub(cx + 1)
      cx = cx - n
      changed()
    end
    return simple(true)
  elseif c == "D" or c == "C" then
    mark()
    local y2 = math.min(cy + cnt - 1, #lines)
    applyOp(c == "D" and "d" or "c", cy, cx, y2, #lines[y2], "excl")
    return simple(true)
  elseif c == "s" then
    mark()
    if #lines[cy] > 0 then applyOp("c", cy, cx, cy, math.min(cx + cnt, #lines[cy]), "excl") else mode = "i" end
    return simple(true)
  elseif c == "S" then
    mark()
    applyOp("c", cy, 0, math.min(cy + cnt - 1, #lines), 0, "line")
    return simple(true)
  elseif c == "Y" then
    applyOp("y", cy, 0, math.min(cy + cnt - 1, #lines), 0, "line")
    return simple(false)
  elseif c == "p" or c == "P" then
    putReg(c == "p", cnt)
    return simple(true)
  elseif c == "J" then
    joinLines(cnt)
    return simple(true)
  elseif c == "~" then
    if #lines[cy] > 0 then
      mark()
      local n = math.min(cnt, #lines[cy] - cx)
      local mid = lines[cy]:sub(cx + 1, cx + n):gsub("%a", function(ch) return ch:match("%l") and ch:upper() or ch:lower() end)
      lines[cy] = lines[cy]:sub(1, cx) .. mid .. lines[cy]:sub(cx + n + 1)
      cx = math.min(cx + n, #lines[cy] - 1)
      changed()
    end
    return simple(true)
  elseif c == "u" then
    for _ = 1, cnt do
      local snap = table.remove(undo)
      if not snap then message = "Already at oldest change"; break end
      redo[#redo + 1] = snapshot()
      lines, cy, cx, modified = snap.lines, snap.y, snap.x, snap.mod
    end
    return simple(false)
  elseif c == "ctrl-r" then
    for _ = 1, cnt do
      local snap = table.remove(redo)
      if not snap then message = "Already at newest change"; break end
      undo[#undo + 1] = snapshot()
      lines, cy, cx, modified = snap.lines, snap.y, snap.x, snap.mod
    end
    return simple(false)
  elseif c == "." then
    done()
    if lastChange then
      local keys = lastChange
      local rep = {}
      for _ = 1, cnt do for _, kk in ipairs(keys) do rep[#rep + 1] = kk end end
      replaying = true
      feed(rep)
      replaying = false
    end
    return simple(false)
  elseif c == "i" or c == "a" or c == "A" or c == "I" or c == "o" or c == "O" then
    enterInsert(c)
    return simple(true)
  elseif c == "v" or c == "V" then
    mode = c; anchorY, anchorX = cy, cx
    return simple(false)
  elseif c == ":" then
    mode = "c"; cmdline = ""; cmdtype = ":"
    if cnt1 then cmdline = cnt1 == 1 and "." or (".,.+" .. (cnt1 - 1)) end
    return simple(false)
  elseif c == "/" or c == "?" then
    mode = "c"; cmdline = ""; cmdtype = c
    return simple(false)
  elseif c == "ctrl-d" or c == "ctrl-u" or c == "ctrl-f" or c == "ctrl-b" or c == "pagedown" or c == "pageup" then
    scrollBy(c, cnt)
    return simple(false)
  elseif c == "ctrl-e" then
    top = math.min(top + cnt, #lines); if cy < top then cy = top end
    return simple(false)
  elseif c == "ctrl-y" then
    top = math.max(top - cnt, 1); if cy >= top + TEXT_ROWS then cy = top + TEXT_ROWS - 1 end
    return simple(false)
  elseif c == "ctrl-g" or c == "esc" or c == "ctrl-c" then
    return simple(false)
  elseif c == "z" then
    if not toks[i + 1] then return "more" end
    local z = toks[i + 1]
    if z == "z" then top = math.max(cy - TEXT_ROWS // 2, 1)
    elseif z == "t" then top = cy
    elseif z == "b" then top = math.max(cy - TEXT_ROWS + 1, 1) end
    return simple(false)
  elseif c == "&" then
    return simple(false)
  end

  -- plain motions
  local m = c
  if c == "g" then m = "g" .. (toks[i + 1] or "") end
  local y, x, kind = motion(m, cnt, cnt1 ~= nil, false)
  if y then
    if kind == "line" and (c == "G") then
      cy = y; cx = (lines[cy]:find("%S") or 1) - 1; wantX = cx
    elseif kind == "line" then
      local wx = wantX
      cy = y; cx = math.min(wx, math.max(#lines[cy] - 1, 0))
    else
      cy, cx = y, x
      wantX = (c == "$") and 1e9 or cx
    end
    if kind == "excl" and c ~= "j" and c ~= "k" then wantX = cx end
  end
  return simple(false)
end

local function visualKey(k)
  if k == "esc" or k == "ctrl-g" or k == "ctrl-c" then mode = "n"; pend = ""; ntoks = {}; return end
  local isLine = mode == "V"
  if k == "v" then if mode == "v" then mode = "n" else mode = "v" end; return end
  if k == "V" then if mode == "V" then mode = "n" else mode = "V" end; return end
  if k == "o" then cy, anchorY, cx, anchorX = anchorY, cy, anchorX, cx; return end
  local y1, x1, y2, x2 = visualRange()
  local function leave() mode = "n"; cy, cx = y1, x1; clamp() end
  if k == "d" or k == "x" or k == "delete" then
    mode = "n"
    if isLine then applyOp("d", y1, 0, y2, 0, "line") else applyOp("d", y1, x1, y2, x2, "incl") end
    curIsChange = true
    return
  elseif k == "y" then
    mode = "n"
    if isLine then applyOp("y", y1, 0, y2, 0, "line") else applyOp("y", y1, x1, y2, x2, "incl") end
    return
  elseif k == "c" or k == "s" then
    mode = "n"
    if isLine then applyOp("c", y1, 0, y2, 0, "line") else applyOp("c", y1, x1, y2, x2, "incl") end
    return
  elseif k == ">" or k == "<" then
    mode = "n"; applyOp(k, y1, 0, y2, 0, "line"); return
  elseif k == "~" or k == "u" or k == "U" then
    mode = "n"
    if isLine then applyOp(k, y1, 0, y2, 0, "line") else applyOp(k, y1, x1, y2, x2, "incl") end
    return
  elseif k == "J" then
    mode = "n"; cy = y1; joinLines(y2 - y1 + 1); return
  elseif k == "p" or k == "P" then
    mode = "n"
    local saved = { text = reg.text, line = reg.line }
    if isLine then applyOp("d", y1, 0, y2, 0, "line") else applyOp("d", y1, x1, y2, x2, "incl") end
    local after = { text = reg.text, line = reg.line }
    reg = saved
    local wasLine = isLine
    if wasLine and not reg.line then cy = cy - 1; putReg(true, 1) else putReg(not wasLine or true, 1) end
    reg = after
    return
  elseif k == ":" then
    mode = "c"; cmdtype = ":"; cmdline = "'<,'>"
    -- the marks are the range of this selection
    cmdline = (y1) .. "," .. (y2)
    anchorY, cy = y1, y2
    return
  elseif k == "/" or k == "?" then
    mode = "c"; cmdtype = k; cmdline = ""; return
  end
  if k == "i" or k == "a" or k == "A" or k == "I" or k == "O" or k == "." or k == "r" or k == "ctrl-r" then return end
  -- anything else is a motion that extends the selection
  local r = normalKey(k)
  if mode ~= "v" and mode ~= "V" then return end
end

local function execSearch(text, dir)
  if text ~= "" then lastSearch = text end
  searchDir = dir
  local y, x = search(lastSearch, dir, cy, cx)
  if y then
    cy, cx = y, x
    message = (dir > 0 and "/" or "?") .. lastSearch
  end
end

local function cmdKey(k)
  if k == "enter" then
    local text = cmdline
    local t = cmdtype
    mode = (anchorY and (t == "/" or t == "?") and false) and "v" or "n"
    if t == ":" then runEx(text)
    else execSearch(text, t == "/" and 1 or -1) end
  elseif k == "esc" or k == "ctrl-g" or k == "ctrl-c" then
    mode = "n"
  elseif k == "backspace" then
    if cmdline == "" then mode = "n" else cmdline = cmdline:sub(1, -2) end
  elseif k == "ctrl-u" then
    cmdline = ""
  elseif k == "tab" then
    cmdline = cmdline .. "\t"
  elseif #k == 1 then
    cmdline = cmdline .. k
  end
end

local function insertKey(k)
  local s = lines[cy]
  if k == "esc" or k == "ctrl-g" or k == "ctrl-c" then
    mode = "n"
    if cx > 0 then cx = cx - 1 end
    wantX = cx
  elseif k == "enter" then
    local indent = s:match("^[ \t]*") or ""
    if cx < #indent then indent = indent:sub(1, cx) end
    table.insert(lines, cy + 1, indent .. s:sub(cx + 1))
    lines[cy] = s:sub(1, cx)
    cy = cy + 1; cx = #indent
    changed()
  elseif k == "backspace" then
    if cx > 0 then
      lines[cy] = s:sub(1, cx - 1) .. s:sub(cx + 1); cx = cx - 1; changed()
    elseif cy > 1 then
      local p = #lines[cy - 1]
      lines[cy - 1] = lines[cy - 1] .. s
      table.remove(lines, cy)
      cy = cy - 1; cx = p; changed()
    end
  elseif k == "delete" then
    if cx < #s then lines[cy] = s:sub(1, cx) .. s:sub(cx + 2); changed()
    elseif cy < #lines then lines[cy] = s .. lines[cy + 1]; table.remove(lines, cy + 1); changed() end
  elseif k == "tab" then
    lines[cy] = s:sub(1, cx) .. "\t" .. s:sub(cx + 1); cx = cx + 1; changed()
  elseif k == "ctrl-w" then
    local a = cx
    while a > 0 and cls(s:sub(a, a)) == 0 do a = a - 1 end
    local c = cls(s:sub(a, a))
    while a > 0 and cls(s:sub(a, a)) == c and c ~= 0 do a = a - 1 end
    lines[cy] = s:sub(1, a) .. s:sub(cx + 1); cx = a; changed()
  elseif k == "ctrl-u" then
    lines[cy] = s:sub(cx + 1); cx = 0; changed()
  elseif k == "left" then if cx > 0 then cx = cx - 1 end
  elseif k == "right" then if cx < #s then cx = cx + 1 end
  elseif k == "up" then if cy > 1 then cy = cy - 1; cx = math.min(cx, #lines[cy]) end
  elseif k == "down" then if cy < #lines then cy = cy + 1; cx = math.min(cx, #lines[cy]) end
  elseif k == "home" then cx = 0
  elseif k == "end" then cx = #s
  elseif #k == 1 then
    if readonly and false then return end
    lines[cy] = s:sub(1, cx) .. k .. s:sub(cx + 1); cx = cx + 1; changed()
  end
end

local function handle(k)
  if message ~= "" and mode ~= "c" then message = "" end
  local before = mode
  if mode == "c" then cmdKey(k)
  elseif mode == "i" then insertKey(k)
  elseif mode == "v" or mode == "V" then visualKey(k)
  else
    if readonly and (k == "x" or k == "d" or k == "i" or k == "a" or k == "o" or k == "O" or k == "p" or k == "P" or k == "c" or k == "s") and #ntoks == 0 then
      message = "W10: Warning: Changing a readonly file"
    end
    normalKey(k)
  end
  clamp()
end

-- the dot command: keys of a change are recorded from its first key until the editor is in normal mode again
local function isNormalIdle() return mode == "n" and #ntoks == 0 end

feed = function(keys)
  for _, k in ipairs(keys) do
    local startedIdle = isNormalIdle()
    if startedIdle and not replaying then curKeys = {}; curIsChange = false; marked = false end
    if not replaying then curKeys[#curKeys + 1] = k end
    if replaying and startedIdle then marked = false end
    handle(k)
    if not replaying and isNormalIdle() and curIsChange and #curKeys > 0 and curKeys[1] ~= "." then
      lastChange = curKeys
      curKeys = {}
    end
  end
end

if startLine then cy = math.min(startLine, #lines) end
term.fullscreen(true)
clamp()
while not quit do
  local k = key.poll()
  while k and not quit do
    if k == "ctrl-g" and mode == "n" and #ntoks == 0 then
      message = string.format('"%s"%s %d lines --%d%%--', path or "[No Name]", modified and " [Modified]" or "", #lines, cy * 100 // #lines)
    else
      if k == "ctrl-c" or k == "ctrl-g" then k = "esc" end
      feed({ k })
    end
    k = key.poll()
  end
  if quit then break end
  draw()
  sys.sleep(30)
end
term.fullscreen(false)
