#!lua
-- relang: a backtracking regular expression matcher, for the Python and JavaScript packages. parse(pattern) -> tree, groups, names; exec(tree, text, start, flags) -> end, captures
local function parse(p)
  local i = 1
  local groups = 0
  local names = {}
  local alt
  local function class()
    local neg = false
    local items = {}
    if p:sub(i, i) == "^" then neg = true; i = i + 1 end
    local first = true
    while i <= #p and (first or p:sub(i, i) ~= "]") do
      first = false
      local c = p:sub(i, i)
      if c == "\\" then
        local d = p:sub(i + 1, i + 1)
        i = i + 2
        if d:find("[dwsDWS]") then items[#items + 1] = { cls = d }
        else
          local map = { n = "\n", t = "\t", r = "\r" }
          local lit = map[d] or d
          items[#items + 1] = { lo = lit:byte(), hi = lit:byte() }
        end
      else
        i = i + 1
        if p:sub(i, i) == "-" and p:sub(i + 1, i + 1) ~= "]" and p:sub(i + 1, i + 1) ~= "" then
          items[#items + 1] = { lo = c:byte(), hi = p:byte(i + 1) }
          i = i + 2
        else items[#items + 1] = { lo = c:byte(), hi = c:byte() } end
      end
    end
    i = i + 1
    return { t = "set", neg = neg, items = items }
  end
  local function atom_()
    local c = p:sub(i, i)
    if c == "(" then
      i = i + 1
      local node = { t = "group" }
      if p:sub(i, i + 1) == "?:" then i = i + 2
      elseif p:sub(i, i + 1) == "?=" then i = i + 2; node.t = "look"
      elseif p:sub(i, i + 1) == "?!" then i = i + 2; node.t = "look"; node.neg = true
      elseif p:sub(i, i + 1) == "?P" then
        local n = p:match("^%?P<([%w_]+)>", i)
        i = i + #n + 4
        groups = groups + 1
        node.idx = groups
        names[n] = groups
      else
        groups = groups + 1
        node.idx = groups
      end
      node.body = alt()
      i = i + 1
      return node
    elseif c == "[" then i = i + 1; return class()
    elseif c == "." then i = i + 1; return { t = "any" }
    elseif c == "^" then i = i + 1; return { t = "bol" }
    elseif c == "$" then i = i + 1; return { t = "eol" }
    elseif c == "\\" then
      local d = p:sub(i + 1, i + 1)
      i = i + 2
      if d:find("[dwsDWS]") then return { t = "set", items = { { cls = d } } } end
      if d == "b" then return { t = "wordb" } elseif d == "B" then return { t = "nwordb" } end
      if d:find("%d") then return { t = "backref", idx = tonumber(d) } end
      local map = { n = "\n", t = "\t", r = "\r" }
      return { t = "char", c = map[d] or d }
    end
    i = i + 1
    return { t = "char", c = c }
  end
  local function seq()
    local items = {}
    while i <= #p do
      local c = p:sub(i, i)
      if c == "|" or c == ")" then break end
      local a = atom_()
      local q = p:sub(i, i)
      local lo, hi
      if q == "*" then lo, hi = 0, math.huge; i = i + 1
      elseif q == "+" then lo, hi = 1, math.huge; i = i + 1
      elseif q == "?" then lo, hi = 0, 1; i = i + 1
      elseif q == "{" then
        local a1, b1, e = p:match("^{(%d*),?(%d*)}()", i)
        if a1 then
          local hasComma = p:sub(i, e - 1):find(",", 1, true)
          lo = tonumber(a1) or 0
          hi = hasComma and (tonumber(b1) or math.huge) or lo
          i = e
        end
      end
      if lo then
        local lazy_ = p:sub(i, i) == "?"
        if lazy_ then i = i + 1 end
        a = { t = "rep", body = a, lo = lo, hi = hi, lazy = lazy_ }
      end
      items[#items + 1] = a
    end
    return { t = "seq", items = items }
  end
  alt = function()
    local opts = { seq() }
    while p:sub(i, i) == "|" do
      i = i + 1
      opts[#opts + 1] = seq()
    end
    if #opts == 1 then return opts[1] end
    return { t = "alt", opts = opts }
  end
  local tree = alt()
  return tree, groups, names
end
local function isClass(cls, b)
  local c = string.char(b)
  if cls == "d" then return c:find("%d") ~= nil
  elseif cls == "D" then return not c:find("%d")
  elseif cls == "w" then return c:find("[%w_\128-\255]") ~= nil
  elseif cls == "W" then return not c:find("[%w_\128-\255]")
  elseif cls == "s" then return c:find("%s") ~= nil
  else return not c:find("%s") end
end
local function exec(prog, s, start, flags)
  local caps = {}
  local ic = flags & 2 ~= 0
  local ml = flags & 8 ~= 0
  local da = flags & 16 ~= 0
  local run
  local function setMatch(node, b)
    local inSet = false
    local bb = b
    local alt_ = nil
    if ic then
      local ch = string.char(b)
      alt_ = (ch:lower() == ch and ch:upper() or ch:lower()):byte()
    end
    for _, it in ipairs(node.items) do
      if it.cls then
        if isClass(it.cls, bb) then inSet = true; break end
      elseif (bb >= it.lo and bb <= it.hi) or (alt_ and alt_ >= it.lo and alt_ <= it.hi) then inSet = true; break end
    end
    if node.neg then return not inSet end
    return inSet
  end
  local function isWordAt(i) local c = s:sub(i, i); return c ~= "" and c:find("[%w_]") ~= nil end
  run = function(node, i, k)
    local t = node.t
    if t == "seq" then
      local items = node.items
      local function step(idx, j)
        if idx > #items then return k(j) end
        return run(items[idx], j, function(x) return step(idx + 1, x) end)
      end
      return step(1, i)
    elseif t == "char" then
      local c = s:sub(i, i)
      if c == node.c or (ic and c ~= "" and c:lower() == node.c:lower()) then return k(i + 1) end
      return nil
    elseif t == "any" then
      local c = s:sub(i, i)
      if c ~= "" and (da or c ~= "\n") then return k(i + 1) end
      return nil
    elseif t == "set" then
      local b = s:byte(i)
      if b and setMatch(node, b) then return k(i + 1) end
      return nil
    elseif t == "alt" then
      for _, o in ipairs(node.opts) do
        local r = run(o, i, k)
        if r then return r end
      end
      return nil
    elseif t == "group" then
      if node.idx then
        local old = caps[node.idx]
        local r = run(node.body, i, function(j)
          local saved = caps[node.idx]
          caps[node.idx] = { i, j - 1 }
          local x = k(j)
          if not x then caps[node.idx] = saved end
          return x
        end)
        if not r then caps[node.idx] = old end
        return r
      end
      return run(node.body, i, k)
    elseif t == "look" then
      local r = run(node.body, i, function(j) return j end)
      if (r and not node.neg) or (not r and node.neg) then return k(i) end
      return nil
    elseif t == "rep" then
      local function more(count, j)
        if node.lazy then
          if count >= node.lo then
            local r = k(j)
            if r then return r end
          end
          if count < node.hi then
            return run(node.body, j, function(x) if x == j then return nil end return more(count + 1, x) end)
          end
          return nil
        end
        if count < node.hi then
          local r = run(node.body, j, function(x) if x == j then return nil end return more(count + 1, x) end)
          if r then return r end
        end
        if count >= node.lo then return k(j) end
        return nil
      end
      return more(0, i)
    elseif t == "bol" then
      if i == 1 or (ml and s:sub(i - 1, i - 1) == "\n") then return k(i) end
      return nil
    elseif t == "eol" then
      if i == #s + 1 or (i == #s and s:sub(i, i) == "\n") or (ml and s:sub(i, i) == "\n") then return k(i) end
      return nil
    elseif t == "wordb" or t == "nwordb" then
      local at = isWordAt(i - 1) ~= isWordAt(i)
      if at == (t == "wordb") then return k(i) end
      return nil
    elseif t == "backref" then
      local c = caps[node.idx]
      if not c then return nil end
      local text = s:sub(c[1], c[2])
      if s:sub(i, i + #text - 1) == text then return k(i + #text) end
      return nil
    end
  end
  local e = run(prog, start, function(j) return j end)
  if e then return e, caps end
end

return { parse = parse, exec = exec }
