#!lua
-- clang: C and C++ for this device. The source is translated to Lua (a native compiler cannot run from the card: this firmware cannot load machine code), so a program runs
-- slower than compiled code, but it runs. C: functions, structs, unions as structs, pointers (with arithmetic), arrays, malloc, strings, stdio, string.h, stdlib.h, math.h, ctype.h, enums,
-- typedef, switch, goto, #define NAME VALUE. C++: classes with inheritance, virtual methods, constructors and destructors, operators, references, new/delete, templates (without
-- type checks), lambdas, auto, range for, std::string, vector, map, unordered_map, set, pair, stack, queue, deque, iostream, sort and friends. Not there: raw memory tricks (casting a
-- pointer to another type, int to pointer, bit layouts of a union), function-like macros with odd uses, exceptions across C code, the rest of the STL.
local C = {}
local TYPEWORDS = { int = 1, char = 1, short = 1, long = 1, float = 1, double = 1, void = 1, bool = 1, signed = 1, unsigned = 1, _Bool = 1, size_t = 1, string = 1, auto = 1,
  int8_t = 1, int16_t = 1, int32_t = 1, int64_t = 1, uint8_t = 1, uint16_t = 1, uint32_t = 1, uint64_t = 1, ssize_t = 1, ostream = 1, istream = 1, FILE = 1, time_t = 1, clock_t = 1, va_list = 1, ifstream = 1, ofstream = 1, fstream = 1, stringstream = 1, istringstream = 1, ostringstream = 1 }
local CONTAINERS = { vector = "vector", deque = "vector", list = "vector", stack = "stack", queue = "queue", priority_queue = "pqueue", map = "map", unordered_map = "umap", multimap = "map", set = "set", unordered_set = "uset", multiset = "set", pair = "pair", tuple = "tuple", array = "vector", ["function"] = "fn", initializer_list = "vector", shared_ptr = "sptr", unique_ptr = "sptr", optional = "auto" }
local CPPONLY = { ifstream = 1, ofstream = 1, fstream = 1, stringstream = 1, istringstream = 1, ostringstream = 1, string = 1, auto = 1, ostream = 1, istream = 1, bool = false }
local QUALS = { const = 1, static = 1, inline = 1, extern = 1, volatile = 1, register = 1, constexpr = 1, virtual = 1, explicit = 1, friend = 1, mutable = 1, restrict = 1, override = 1, final = 1, noexcept = 1 }
local LUAKW = {}
for w in ("and elseif end function in local nil not or repeat then until self print type pairs ipairs string math table select error pcall R_ G"):gmatch("%S+") do LUAKW[w] = true end
local function mangle(n) if LUAKW[n] then return n .. "_" end return n end
local function syntaxError(m, l) error({ syntax = m, line = l }, 0) end

-- types
local T = {}
local function base(n) local t = T[n]; if not t then t = { n = n }; T[n] = t end return t end
local INT, DOUBLE, CHAR, BOOL, VOID, STRING, CSTR, AUTO, LONG, UINT = base("int"), base("double"), base("char"), base("bool"), base("void"), base("string"), base("cstr"), base("auto"), base("long"), base("uint")
local OSTREAM, ISTREAM = base("ostream"), base("istream")
local function ptrTo(t) return { n = "ptr", to = t } end
local VOIDP = ptrTo(VOID)
local WRAP = { uint = "0xFFFFFFFF", uint8 = "0xFF", uint16 = "0xFFFF" }
local function isInt(t) local n = t.n; return n == "int" or n == "char" or n == "long" or n == "uint" or n == "uint8" or n == "uint16" or n == "ulong" or n == "enum" end
local function isFloat(t) return t.n == "double" end
local function isNum(t) return isInt(t) or isFloat(t) end
local function isPtr(t) return t.n == "ptr" end
local function isStruct(t) return t.n == "struct" end

local RET = {
  strlen = INT, strcmp = INT, strncmp = INT, atoi = INT, atol = LONG, abs = INT, labs = LONG, rand = INT, getchar = INT, putchar = INT, puts = INT, printf = INT, scanf = INT, sprintf = INT, snprintf = INT, sscanf = INT, fprintf = INT,
  toupper = CHAR, tolower = CHAR, isdigit = INT, isalpha = INT, isalnum = INT, isspace = INT, isupper = INT, islower = INT, ispunct = INT, isxdigit = INT, time = LONG, clock = LONG, fclose = INT, fputs = INT, fputc = INT, fgetc = INT, feof = INT, strtol = LONG, strtoul = LONG, stoi = INT, stol = LONG,
  sqrt = DOUBLE, pow = DOUBLE, sin = DOUBLE, cos = DOUBLE, tan = DOUBLE, asin = DOUBLE, acos = DOUBLE, atan = DOUBLE, atan2 = DOUBLE, exp = DOUBLE, log = DOUBLE, log2 = DOUBLE, log10 = DOUBLE, floor = DOUBLE, ceil = DOUBLE, fabs = DOUBLE, fmod = DOUBLE, round = DOUBLE, trunc = DOUBLE, hypot = DOUBLE, atof = DOUBLE, stod = DOUBLE, stof = DOUBLE, cbrt = DOUBLE,
  malloc = VOIDP, calloc = VOIDP, realloc = VOIDP, memset = VOIDP, memcpy = VOIDP, memmove = VOIDP, strcpy = ptrTo(CHAR), strncpy = ptrTo(CHAR), strcat = ptrTo(CHAR), strncat = ptrTo(CHAR), strchr = ptrTo(CHAR), strrchr = ptrTo(CHAR), strstr = ptrTo(CHAR), strdup = ptrTo(CHAR), fgets = ptrTo(CHAR), gets = ptrTo(CHAR), strtok = ptrTo(CHAR), to_string = STRING, fopen = VOIDP, setw = base("manip"), setprecision = base("manip"), setfill = base("manip"), getenv = ptrTo(CHAR),
}
local CONSTS = { SEEK_SET = { "0", INT }, SEEK_CUR = { "1", INT }, SEEK_END = { "2", INT }, BUFSIZ = { "8192", INT }, EXIT_SUCCESS = { "0", INT }, EXIT_FAILURE = { "1", INT }, PATH_MAX = { "4096", INT }, STDIN_FILENO = { "0", INT }, STDOUT_FILENO = { "1", INT }, STDERR_FILENO = { "2", INT }, ENOENT = { "2", INT }, EACCES = { "13", INT }, EEXIST = { "17", INT }, EINVAL = { "22", INT }, S_IFMT = { "61440", INT }, S_IFDIR = { "16384", INT }, S_IFREG = { "32768", INT }, DT_DIR = { "4", INT }, DT_REG = { "8", INT }, O_RDONLY = { "0", INT }, O_WRONLY = { "1", INT }, O_RDWR = { "2", INT }, O_CREAT = { "64", INT }, O_TRUNC = { "512", INT }, O_APPEND = { "1024", INT }, CLOCKS_PER_SEC = { "1000000", INT }, NULL = { "nil", VOIDP }, nullptr = { "nil", VOIDP }, EOF = { "-1", INT }, RAND_MAX = { "2147483647", INT }, INT_MAX = { "2147483647", INT }, INT_MIN = { "(-2147483648)", INT }, UINT_MAX = { "4294967295", LONG }, LONG_MAX = { "math.maxinteger", LONG }, LONG_MIN = { "math.mininteger", LONG }, LLONG_MAX = { "math.maxinteger", LONG }, LLONG_MIN = { "math.mininteger", LONG }, CHAR_MAX = { "127", INT }, DBL_MAX = { "1.7976931348623157e308", DOUBLE }, DBL_MIN = { "2.2250738585072014e-308", DOUBLE }, FLT_MAX = { "3.4028234663852886e38", DOUBLE }, M_PI = { "math.pi", DOUBLE }, M_E = { "2.718281828459045", DOUBLE }, EXIT_SUCCESS = { "0", INT }, EXIT_FAILURE = { "1", INT }, stdin = { "R.stdin", VOIDP }, stdout = { "R.stdout", VOIDP }, stderr = { "R.stderr", VOIDP }, CLOCKS_PER_SEC = { "1000", LONG }, BUFSIZ = { "1024", INT }, ["true"] = { "true", BOOL }, ["false"] = { "false", BOOL }, npos = { "-1", LONG }, cout = { "R.cout", OSTREAM }, cerr = { "R.cout", OSTREAM }, clog = { "R.cout", OSTREAM }, cin = { "R.cin", ISTREAM }, endl = { '"\\n"', CSTR } }

-- ---- lexer with a small preprocessor ----
local OPS = { "<<=", ">>=", "...", "->*", "==", "!=", "<=", ">=", "&&", "||", "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<", ">>", "->", "::" }
local ESC = { n = 10, t = 9, r = 13, ["0"] = 0, a = 7, b = 8, f = 12, v = 11, e = 27, ["\\"] = 92, ["'"] = 39, ['"'] = 34, ["?"] = 63 }
local function lex(src)
  local toks, i, n, line = {}, 1, #src, 1
  local defines = {}
  local function push(t, v) toks[#toks + 1] = { t = t, v = v, line = line } end
  local function esc(j)
    local d = src:sub(j + 1, j + 1)
    if d == "x" then local h = src:match("^%x+", j + 2); return tonumber(h, 16) & 255, j + 2 + #h end
    if d:find("[0-7]") then local o = src:match("^[0-7]+", j + 1); return tonumber(o, 8) & 255, j + 1 + #o end
    return ESC[d] or d:byte(), j + 2
  end
  if src:sub(1, 2) == "#!" then i = src:find("\n", 1, true) or n + 1 end
  local atLineStart = true
  while i <= n do
    local c = src:sub(i, i)
    if c == "\n" then line = line + 1; i = i + 1; atLineStart = true
    elseif c == " " or c == "\t" or c == "\r" then i = i + 1
    elseif src:sub(i, i + 1) == "//" then i = src:find("\n", i, true) or n + 1
    elseif src:sub(i, i + 1) == "/*" then
      local e = src:find("*/", i + 2, true) or n
      for _ in src:sub(i, e):gmatch("\n") do line = line + 1 end
      i = e + 2
    elseif c == "#" and atLineStart then
      local e = i
      while true do
        e = src:find("\n", e, true) or n + 1
        if src:sub(e - 1, e - 1) == "\\" then e = e + 1 else break end
      end
      local dir = src:sub(i + 1, e - 1):gsub("\\\n", " ")
      local name, rest = dir:match("^%s*define%s+([%a_][%w_]*)(.*)$")
      if name and rest:sub(1, 1) == "(" then
        local params, body = rest:match("^%(([^)]*)%)%s*(.*)$")
        local plist = {}
        for p in params:gmatch("[%a_][%w_]*") do plist[#plist + 1] = p end
        defines[name] = { params = plist, body = lex(body).list }
      elseif name then
        defines[name] = { body = lex(rest).list }
      end
      for _ in src:sub(i, e - 1):gmatch("\n") do line = line + 1 end
      i = e
    elseif c:find("[%a_]") then
      local j = src:match("^[%w_]*()", i)
      local w = src:sub(i, j - 1)
      i = j
      atLineStart = false
      if w == "R" and src:sub(i, i) == '"' then
        local tag = src:match('^"([^(]*)%(', i)
        local e = src:find(")" .. tag .. '"', i, true)
        push("str", src:sub(i + #tag + 2, e - 1))
        i = e + #tag + 2
      elseif (w == "L" or w == "u8") and src:sub(i, i) == '"' then
      else
        local d = defines[w]
        if d and not d.params then
          for _, t in ipairs(d.body) do toks[#toks + 1] = { t = t.t, v = t.v, line = line } end
        elseif d and src:match("^%s*%(", i) then
          i = src:find("(", i, true) + 1
          local args, cur, depth = {}, {}, 0
          local from = i
          while true do
            local x = src:sub(i, i)
            if x == "(" then depth = depth + 1 elseif x == ")" then if depth == 0 then break end depth = depth - 1
            elseif x == "," and depth == 0 then args[#args + 1] = src:sub(from, i - 1); from = i + 1 end
            i = i + 1
          end
          args[#args + 1] = src:sub(from, i - 1)
          i = i + 1
          local map = {}
          for k, p in ipairs(d.params) do map[p] = lex(args[k] or "").list end
          for _, t in ipairs(d.body) do
            if t.t == "name" and map[t.v] then
              toks[#toks + 1] = { t = "op", v = "(", line = line }
              for _, a in ipairs(map[t.v]) do toks[#toks + 1] = { t = a.t, v = a.v, line = line } end
              toks[#toks + 1] = { t = "op", v = ")", line = line }
            else toks[#toks + 1] = { t = t.t, v = t.v, line = line } end
          end
        else push("name", w) end
      end
    elseif c:find("%d") or (c == "." and src:sub(i + 1, i + 1):find("%d")) then
      atLineStart = false
      local s = src:match("^0[xX]%x+", i) or src:match("^0[bB][01]+", i)
      if s then
        local v = s:sub(2, 2):lower() == "b" and tonumber(s:sub(3), 2) or math.tointeger(tonumber(s))
        i = i + #s
        push("int", v or tonumber(s))
      else
        s = src:match("^%d*%.?%d*[eE][+-]?%d+", i) or src:match("^%d*%.?%d*", i)
        i = i + #s
        if s:find("[%.eE]") then push("float", tonumber(s) + 0.0)
        elseif #s > 1 and s:sub(1, 1) == "0" then push("int", tonumber(s, 8))
        else push("int", math.tointeger(tonumber(s)) or tonumber(s)) end
      end
      local suf = src:match("^[uUlLfF]+", i)
      if suf then
        i = i + #suf
        if suf:find("[lL]") and toks[#toks].t == "int" then toks[#toks].long = true end
      end
    elseif c == '"' then
      atLineStart = false
      local b, j = {}, i + 1
      while true do
        local d = src:sub(j, j)
        if d == "" or d == "\n" then syntaxError("missing terminating \" character", line) end
        if d == '"' then break end
        if d == "\\" then
          local v
          v, j = esc(j)
          b[#b + 1] = string.char(v)
        else b[#b + 1] = d; j = j + 1 end
      end
      i = j + 1
      local p = toks[#toks]
      if p and p.t == "str" then p.v = p.v .. table.concat(b) else push("str", table.concat(b)) end
    elseif c == "'" then
      atLineStart = false
      local v, j
      if src:sub(i + 1, i + 1) == "\\" then v, j = esc(i + 1) else v = src:byte(i + 1); j = i + 2 end
      if v and v >= 0x80 and src:sub(j, j) ~= "'" then
        local e = src:find("'", j, true)
        v = utf8.codepoint(src:sub(i + 1, e - 1))
        j = e
      end
      push("char", v)
      i = j + 1
    else
      atLineStart = false
      local op
      for _, o in ipairs(OPS) do if src:sub(i, i + #o - 1) == o then op = o; break end end
      op = op or c
      push("op", op)
      i = i + #op
    end
  end
  return { list = toks }
end

-- ---- compiler ----
local function compile(src, isCpp)
  local toks = lex(src).list
  toks[#toks + 1] = { t = "eof", line = (toks[#toks] or { line = 1 }).line }
  if not isCpp then  -- words of C++ are plain names in C
    local CPPWORDS = { new = 1, delete = 1, class = 1, this = 1, template = 1, namespace = 1, operator = 1, typename = 1, using = 1, virtual = 1, public = 1, private = 1, protected = 1, friend = 1, explicit = 1, mutable = 1, try = 1, catch = 1, throw = 1, nullptr = 1 }
    for _, x in ipairs(toks) do
      if x.t == "name" and CPPWORDS[x.v] then x.v = x.v .. "_c" end
    end
  end
  local protoEmpty = {}  -- int f(); : the arguments are not told (C)
  local pos, tok = 1, toks[1]
  local out = {}
  local tmpN, labelN = 0, 0
  local scopes = { {} }
  local typedefs, structs, enums, funcs = {}, {}, {}, {}
  local curClass, curRet
  local loops = {}
  local templateT = {}
  local dtorScopes = {}

  local function adv() pos = pos + 1; tok = toks[pos] end
  local function peek(k) return toks[pos + (k or 1)] end
  local function isOp(v) return tok.t == "op" and tok.v == v end
  local function isName(v) return tok.t == "name" and tok.v == v end
  local function err(m) syntaxError(m or ("expected something else before '" .. tostring(tok.v or "end of file") .. "'"), tok.line) end
  local function acceptOp(v) if isOp(v) then adv(); return true end end
  local function acceptName(v) if isName(v) then adv(); return true end end
  local function expectOp(v) if not acceptOp(v) then err("expected '" .. v .. "' before '" .. tostring(tok.v or "end of file") .. "'") end end
  local function emit(s) out[#out + 1] = s end
  local function tmp() tmpN = tmpN + 1; return "_t" .. tmpN end
  local function capture(f) local s = out; out = {}; f(); local r = table.concat(out, "\n"); out = s; return r end
  local function str(s) return (string.format("%q", s):gsub("\\\n", "\\n"):gsub("\r", "\\r")) end
  local function pushScope() scopes[#scopes + 1] = {} end
  local function popScope() scopes[#scopes] = nil end
  local function bind(n, code, t) scopes[#scopes][n] = { code = code, t = t } end
  local function lookup(n)
    for i = #scopes, 1, -1 do
      local v = scopes[i][n]
      if v then return v end
    end
  end
  local function fieldOf(cls, n)
    local c = cls
    while c do
      if c.fields[n] then return c.fields[n], c end
      c = c.base and structs[c.base]
    end
  end
  local function methodOf(cls, n)
    local c = cls
    while c do
      if c.methods[n] then return c.methods[n], c end
      c = c.base and structs[c.base]
    end
  end

  -- the exception classes of the library
  do
    local whatSig = { params = {}, ret = ptrTo(CHAR), arity = 0 }
    local function libClass(n, b)
      structs[n] = { name = n, fields = {}, methods = { what = { [0] = whatSig } }, fieldList = {}, base = b,
        ctors = { [1] = { params = { { name = "m", t = STRING } }, ret = VOID, arity = 1 } } }
    end
    libClass("exception")
    libClass("runtime_error", "exception"); libClass("logic_error", "exception"); libClass("out_of_range", "logic_error"); libClass("invalid_argument", "logic_error")
    libClass("overflow_error", "runtime_error"); libClass("range_error", "runtime_error"); libClass("length_error", "logic_error"); libClass("domain_error", "logic_error"); libClass("bad_alloc", "exception")
    structs.exception.ctors[0] = { params = {}, ret = VOID, arity = 0 }
  end
  local assignExpr, expression, statement, parseType, parseDeclarator, blockBody, classBody, funcDefinition, unary, castOrUnary

  -- ---- types ----
  local function isTypeStart()
    if tok.t ~= "name" then return false end
    local v = tok.v
    if (TYPEWORDS[v] and (isCpp or not CPPONLY[v])) or typedefs[v] or (structs[v] and isCpp) or enums[v] or templateT[v] or v == "struct" or v == "union" or v == "enum" or v == "class" or v == "typename" or QUALS[v] then
      if not lookup(v) or TYPEWORDS[v] then return true end
    end
    if v == "std" and peek().v == "::" then
      local nx = peek(2)
      return TYPEWORDS[nx.v] ~= nil or CONTAINERS[nx.v] ~= nil
    end
    if isCpp and CONTAINERS[v] and not lookup(v) then return true end
    return false
  end
  local function templateArgs()
    -- after the name, at "<": a list of types (or constants, which are skipped)
    local args = {}
    if not acceptOp("<") then return args end
    local function closeOne()
      if isOp(">") then adv(); return true end
      if isOp(">>") then tok = { t = "op", v = ">", line = tok.line }; toks[pos] = tok; return true end
    end
    while true do
      if closeOne() then break end
      if isTypeStart() then args[#args + 1] = parseType() while acceptOp("*") do args[#args] = ptrTo(args[#args]) end acceptOp("&")
      else
        -- a constant, or a signature like int(int)
        if tok.t == "eof" then err() end
        adv()
      end
      if isOp("(") then
        local d = 0
        repeat
          if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
          adv()
        until d == 0
      end
      acceptOp(",")
    end
    return args
  end
  parseType = function()
    local words = {}
    local t
    while tok.t == "name" do
      local v = tok.v
      if QUALS[v] then adv()
      elseif v == "typename" then adv()
      elseif v == "std" and peek().v == "::" then adv(); adv()
      elseif v == "struct" or v == "class" or v == "union" then
        adv()
        local n = tok.t == "name" and tok.v or ("_anon" .. pos)
        if tok.t == "name" then adv() end
        if isOp("{") or isOp(":") then t = classBody(n) else t = { n = "struct", name = n } end
      elseif v == "enum" then
        adv()
        acceptName("class")
        local n = tok.t == "name" and tok.v or ("_e" .. pos)
        if tok.t == "name" then adv() end
        if isOp("{") then
          adv()
          local val = "0"
          local nv = 0
          enums[n] = true
          while not isOp("}") do
            local id = tok.v
            adv()
            if acceptOp("=") then
              local c = assignExpr()
              val = c
              nv = math.tointeger(tonumber(c)) or 0
            else val = tostring(nv) end
            scopes[1][id] = { code = val, t = INT, const = true }
            scopes[1][n .. "::" .. id] = scopes[1][id]
            nv = nv + 1
            if not acceptOp(",") then break end
          end
          expectOp("}")
        end
        enums[n] = true
        t = INT
      elseif TYPEWORDS[v] and not t then
        words[#words + 1] = v
        adv()
      elseif #words > 0 and TYPEWORDS[v] then words[#words + 1] = v; adv()
      elseif not t and #words == 0 and CONTAINERS[v] then
        adv()
        local a = templateArgs()
        local k = CONTAINERS[v]
        if k == "auto" then t = a[1] or AUTO
        elseif k == "vector" or k == "stack" or k == "queue" or k == "pqueue" or k == "set" or k == "uset" then t = { n = k, to = a[1] or AUTO }
        elseif k == "map" or k == "umap" then t = { n = k, k = a[1] or AUTO, v = a[2] or AUTO }
        elseif k == "pair" then t = { n = "pair", a = a[1] or AUTO, b = a[2] or AUTO }
        elseif k == "tuple" then t = { n = "tuple", items = a }
        elseif k == "sptr" then t = ptrTo(a[1] or AUTO)
        else t = base("fn") end
        if isOp("::") and peek().v == "iterator" or isOp("::") and peek().v == "const_iterator" then
          adv(); adv()
          t = { n = "iter", of = t }
        end
      elseif not t and #words == 0 and typedefs[v] then adv(); t = typedefs[v]; if isOp("<") then templateArgs() end
      elseif not t and #words == 0 and templateT[v] then adv(); t = AUTO
      elseif not t and #words == 0 and enums[v] then adv(); t = INT
      elseif not t and #words == 0 and structs[v] then
        adv()
        local a = isOp("<") and templateArgs()
        t = { n = "struct", name = v }
        if isOp("::") and peek().t == "name" and structs[peek().v] then adv(); t = { n = "struct", name = tok.v }; adv() end
      else break end
    end
    if not t then
      if #words == 0 then err("unknown type name '" .. tostring(tok.v) .. "'") end
      local all = " " .. table.concat(words, " ") .. " "
      if all:find(" ostream ") then t = OSTREAM
      elseif all:find(" istream ") then t = ISTREAM
      elseif all:find(" double ") or all:find(" float ") then t = DOUBLE
      elseif all:find(" void ") then t = VOID
      elseif all:find(" char ") or all:find(" int8_t ") then
        t = (all:find(" unsigned ")) and base("uint8") or CHAR
        if all:find(" int8_t ") then t = INT end
      elseif all:find(" uint8_t ") then t = base("uint8")
      elseif all:find(" uint16_t ") then t = base("uint16")
      elseif all:find(" uint32_t ") then t = UINT
      elseif all:find(" uint64_t ") or all:find(" size_t ") then t = LONG
      elseif all:find(" bool ") or all:find(" _Bool ") then t = BOOL
      elseif all:find(" string ") then t = STRING
      elseif all:find(" auto ") then t = AUTO
      elseif all:find("stream ") and not all:find(" ostream ") and not all:find(" istream ") then
        t = { n = "stream", kind = all:match("(%a+stream) ") }
      elseif all:find(" FILE ") or all:find(" va_list ") then t = VOID
      elseif all:find(" long ") or all:find(" int64_t ") or all:find(" time_t ") or all:find(" clock_t ") or all:find(" ssize_t ") then t = LONG
      elseif all:find(" unsigned ") then t = UINT
      else t = INT end
    end
    while QUALS[tok.v] and tok.t == "name" do adv() end
    return t
  end
  -- pointers, a name and array sizes: returns name, type, isRef
  local placeSet
  parseDeclarator = function(t, noName)
    local isRef = false
    while true do
      if acceptOp("*") then t = ptrTo(t)
      elseif isName("const") or isName("restrict") then adv()
      elseif isOp("&") or isOp("&&") then adv(); isRef = true
      else break end
    end
    local name
    if isOp("(") and peek().v == "*" then
      -- a pointer to a function
      adv(); adv()
      name = tok.t == "name" and tok.v
      if name then adv() end
      expectOp(")")
      local d = 0
      repeat
        if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
        adv()
      until d == 0
      return name, base("fn"), false
    end
    if tok.t == "name" and not noName then name = tok.v; adv() end
    local dims = {}
    while isOp("[") do
      adv()
      if isOp("]") then dims[#dims + 1] = false else dims[#dims + 1] = (assignExpr()) end
      expectOp("]")
    end
    for i = #dims, 1, -1 do t = { n = "arr", to = t, len = dims[i] or nil } end
    return name, t, isRef
  end

  local HANDLE = { stream = 1, vector = 1, map = 1, umap = 1, set = 1, uset = 1, stack = 1, queue = 1, pair = 1, arr = 1, pqueue = 1, ostream = 1, istream = 1, tuple = 1, ["this"] = 1 }
  local function byHandle(t) return isStruct(t) or HANDLE[t.n] end

  -- ---- conversions ----
  local function toBool(c, t)
    if t.n == "bool" then return c end
    if isPtr(t) then  -- a pointer from memset or calloc is 0, not nil
      if c:find("^[%w_]+$") then return "(" .. c .. "~=nil and " .. c .. "~=0)" end
      return "R.truth(" .. c .. ")"
    end
    if t.n == "arr" or t.n == "cstr" then return "(" .. c .. "~=nil)" end
    if t.n == "auto" then return "R.truth(" .. c .. ")" end
    if t.n == "stream" then return "R.sgood(" .. c .. ")" end
    if t.n == "string" or isStruct(t) then return "true" end
    return "(" .. c .. "~=0)"
  end
  local function toNumber(c, t)
    if t.n == "bool" then return "(" .. c .. " and 1 or 0)" end
    return c
  end
  local function decay(c, t)
    if t.n == "arr" then return "R.ptr(" .. c .. ",0)", ptrTo(t.to) end
    if t.n == "cstr" then return "R.cstr(" .. c .. ")", ptrTo(CHAR) end
    return c, t
  end
  local function zeroOf(t)
    local n = t.n
    if n == "stream" then return "R.stream(" .. str(t.kind) .. ")" end
    if isInt(t) then return "0" end
    if n == "double" then return "0.0" end
    if n == "bool" then return "false" end
    if n == "string" then return '""' end
    if n == "ptr" or n == "fn" or n == "iter" then return "nil" end
    if isStruct(t) then
      local s = structs[t.name]
      local ctor = s and s.ctors and (s.ctors[0] or s.hasNoCtor)
      if s and s.ctors and s.ctors[0] then
        local defs = {}
        for i, p in ipairs(s.ctors[0].params) do defs[i] = p.def end
        return "G." .. t.name .. "_new_" .. s.ctors[0].arity .. "(" .. table.concat(defs, ",") .. ")"
      end
      return "G." .. t.name .. "_zero()"
    end
    if n == "arr" then
      local inner = t.to
      if not t.len then return "{}" end
      if isInt(inner) or inner.n == "double" then return "R.arr(" .. t.len .. "," .. zeroOf(inner) .. ")" end
      return "R.arrf(" .. t.len .. ",function() return " .. zeroOf(inner) .. " end)"
    end
    if n == "vector" then return "R.vec()" end
    if n == "stack" or n == "queue" then return "R.vec()" end
    if n == "pqueue" then return "R.pq()" end
    if n == "map" or n == "umap" then return "R.map(" .. tostring(n == "map") .. "," .. zeroOf(t.v) .. ")" end
    if n == "set" or n == "uset" then return "R.set(" .. tostring(n == "set") .. ")" end
    if n == "pair" then return "R.pair(" .. zeroOf(t.a) .. "," .. zeroOf(t.b) .. ")" end
    if n == "auto" then return "nil" end
    return "nil"
  end
  -- makes value c of type from fit in a place of type to
  local function convert(c, from, to, isLv)
    local tn = to.n
    if tn == "double" then
      if isInt(from) then
        if tonumber(c) then return c .. ".0" end
        return "(" .. c .. "+0.0)"
      end
      if from.n == "bool" then return "(" .. c .. " and 1.0 or 0.0)" end
      return c
    end
    if isInt(to) then
      local r = c
      if from.n == "double" then r = "R.d2i(" .. c .. ")"
      elseif from.n == "bool" then r = "(" .. c .. " and 1 or 0)"
      elseif from.n == "auto" then r = c end
      if WRAP[tn] and not (tonumber(c) and tonumber(c) >= 0 and tonumber(c) <= tonumber(WRAP[tn])) then r = "((" .. r .. ")&" .. WRAP[tn] .. ")" end
      return r
    end
    if tn == "bool" then return toBool(c, from) end
    if tn == "string" then
      if from.n == "arr" then return "R.tolua(R.ptr(" .. c .. ",0))" end
      if from.n == "ptr" then return "R.tolua(" .. c .. ")" end
      if from.n == "char" then return "string.char(" .. c .. ")" end
      return c
    end
    if tn == "ptr" then
      if c == "0" or c == "(0)" then return "nil" end  -- the null pointer of C
      if from.n == "arr" or from.n == "cstr" then return (decay(c, from)) end
      if from.n == "ptr" and from.to == VOID and to.to ~= VOID then
        if isStruct(to.to) then return "R.typed(" .. c .. ",G." .. to.to.name .. "_zero)" end
        if isNum(to.to) then return c end
        return "R.typed(" .. c .. ",nil)"
      end
      return c
    end
    if isLv and (isStruct(to) or tn == "vector" or tn == "stack" or tn == "queue" or tn == "map" or tn == "umap" or tn == "set" or tn == "uset" or tn == "pair" or tn == "pqueue" or tn == "tuple" or tn == "arr") then
      return "R.copy(" .. c .. ")"
    end
    if tn == "auto" and from.n == "cstr" then return c end
    if tn == "auto" and isLv and (isStruct(from) or from.n == "vector" or from.n == "pair" or from.n == "map") then return "R.copy(" .. c .. ")" end
    return c
  end
  local function typeForAuto(t)
    if t.n == "cstr" then return ptrTo(CHAR) end
    if t.n == "arr" then return ptrTo(t.to) end
    return t
  end
  -- a pointer to an lvalue
  local function addressOf(c, t)
    -- element or field: a[i], x.f
    local proxy
    local o, i = c:match("^(.+)%[([^%[%]]*)%]$")
    if t.n == "arr" then return "R.ptr(" .. c .. ",0)" end
    if c:sub(1, 2) == "R." and c:find("^R%.load%b()$") then
      return c:match("^R%.load%((.*)%)$")
    end
    return "R.addr(function() return " .. c .. " end,function(_v) " .. c .. "=_v end)"
  end
  local function deref(p, t)
    if t.n == "ptr" then return "(" .. p .. ").a[(" .. p .. ").i]", t.to end
    return p, AUTO
  end
  local function simple(c) return c:match("^[%a_][%w_]*$") end

  -- ---- expressions ----
  local function memberAccess(c, t, n)
    -- c is the struct value, returns the field
    if t.n == "pair" then
      if n == "first" then return c .. ".first", t.a, true end
      if n == "second" then return c .. ".second", t.b, true end
    end
    if isStruct(t) then
      local s = structs[t.name]
      if s then
        local f = fieldOf(s, n)
        if f then
          if f.static then return "G." .. f.owner .. "_" .. n, f.t, true end
          return c .. "." .. mangle(n), f.t, true
        end
      end
    end
    return c .. "." .. mangle(n), AUTO, true
  end
  local function argsOf()
    -- after "(": list of {code, type, lv}
    local a = {}
    while not isOp(")") do
      local c, t, lv = assignExpr()
      a[#a + 1] = { c = c, t = t, lv = lv }
      if not acceptOp(",") then break end
    end
    expectOp(")")
    return a
  end
  local function plainArg(x)
    local c, t = x.c, x.t
    if t.n == "bool" then return c end
    if t.n == "arr" then return (decay(c, t)) end
    return c
  end
  local function callWith(sig, args, selfFirst)
    -- the arguments, converted by the parameter types
    local out_ = {}
    if selfFirst then out_[1] = selfFirst end
    local params = sig and sig.params
    for i, x in ipairs(args) do
      local p = params and params[i]
      local code
      if p then
        if p.ref and p.mut and not byHandle(p.t) then
          code = addressOf(x.c, x.t)
        elseif p.ref then
          code = x.c
          if p.t.n == "string" and (x.t.n == "ptr" or x.t.n == "cstr" or x.t.n == "arr") then code = convert(x.c, x.t, p.t, false) end
        else code = convert(x.c, x.t, p.t, x.lv) end
      else
        code = plainArg(x)
      end
      out_[#out_ + 1] = code
    end
    if params then
      for i = #args + 1, #params do
        if params[i].def then out_[#out_ + 1] = params[i].def end
      end
    end
    return table.concat(out_, ",")
  end
  local function findOverload(entry, n)
    -- entry: { [arity] = sig }, with default arguments under every arity they can take
    if not entry then return nil end
    return entry[n] or entry.any
  end
  local function constructCall(sname, args)
    local s = structs[sname]
    if not s then err("unknown type " .. sname) end
    if s.isAggregate and #args > 0 and not (s.ctors and next(s.ctors)) then
      local parts = {}
      for i, x in ipairs(args) do
        local f = s.fieldList[i]
        parts[i] = "o." .. mangle(f.name) .. "=" .. convert(x.c, x.t, f.t, x.lv)
      end
      return "(function() local o=G." .. sname .. "_zero() " .. table.concat(parts, " ") .. " return o end)()"
    end
    local sig = s.ctors and findOverload(s.ctors, #args)
    if not sig and #args == 0 then return "G." .. sname .. "_zero()" end
    if not sig then
      if #args == 1 and isStruct(args[1].t) and args[1].t.name == sname then return "R.copy(" .. args[1].c .. ")" end
      err("no matching constructor for " .. sname)
    end
    return "G." .. sname .. "_new_" .. sig.arity .. "(" .. callWith(sig, args) .. ")"
  end
  local function braceInit(t)
    -- at "{": a value of type t
    expectOp("{")
    local items = {}
    while not isOp("}") do
      local x
      if isOp("{") then
        local inner = t.n == "arr" and t.to or (t.n == "vector" and t.to) or (t.n == "set" and t.to) or (t.n == "uset" and t.to) or (isStruct(t) and (structs[t.name].fieldList[#items + 1] or {}).t) or (t.n == "map" or t.n == "umap") and { n = "pair", a = t.k, b = t.v } or AUTO
        x = { c = braceInit(inner), t = inner }
      elseif isOp(".") then
        adv()
        local fname = tok.v
        adv()
        expectOp("=")
        local c, ty, lv = assignExpr()
        x = { c = c, t = ty, lv = lv, field = fname }
      else
        local c, ty, lv = assignExpr()
        x = { c = c, t = ty, lv = lv }
      end
      items[#items + 1] = x
      if not acceptOp(",") then break end
    end
    expectOp("}")
    if t.n == "arr" then
      local inner = t.to
      if #items == 1 and items[1].t.n == "cstr" and inner.n == "char" then return "R.chararr(" .. items[1].c .. "," .. (t.len or "nil") .. ")" end
      local parts = {}
      for i, x in ipairs(items) do parts[i] = "[" .. (i - 1) .. "]=" .. convert(x.c, x.t, inner, x.lv) end
      if not t.len then t.len = tostring(#items) end
      local fill = isNum(inner) and zeroOf(inner) or nil
      if fill then return "R.arrinit(" .. t.len .. "," .. fill .. ",{" .. table.concat(parts, ",") .. "})" end
      return "R.arrinitf(" .. t.len .. ",function() return " .. zeroOf(inner) .. " end,{" .. table.concat(parts, ",") .. "})"
    end
    if t.n == "vector" or t.n == "stack" or t.n == "queue" then
      local parts = {}
      for i, x in ipairs(items) do parts[i] = convert(x.c, x.t, t.to, x.lv) end
      return "R.vecof(" .. #parts .. (#parts > 0 and "," or "") .. table.concat(parts, ",") .. ")"
    end
    if t.n == "set" or t.n == "uset" then
      local parts = {}
      for i, x in ipairs(items) do parts[i] = convert(x.c, x.t, t.to, x.lv) end
      return "R.setof(" .. tostring(t.n == "set") .. "," .. table.concat(parts, ",") .. ")"
    end
    if t.n == "map" or t.n == "umap" then
      local parts = {}
      for i, x in ipairs(items) do parts[i] = x.c end
      return "R.mapof(" .. tostring(t.n == "map") .. "," .. zeroOf(t.v) .. (#parts > 0 and "," or "") .. table.concat(parts, ",") .. ")"
    end
    if t.n == "pair" then
      return "R.pair(" .. convert(items[1].c, items[1].t, t.a) .. "," .. convert(items[2].c, items[2].t, t.b) .. ")"
    end
    if isStruct(t) then
      local s = structs[t.name]
      if s and s.ctors and next(s.ctors) then return constructCall(t.name, items) end
      local parts = {}
      for i, x in ipairs(items) do
        local f = x.field and fieldOf(s, x.field) or (s and s.fieldList[i]) or { name = "f" .. i, t = AUTO }
        parts[i] = "o." .. mangle(f.name or x.field) .. "=" .. convert(x.c, x.t, f.t, x.lv)
      end
      return "(function() local o=G." .. t.name .. "_zero() " .. table.concat(parts, " ") .. " return o end)()"
    end
    if #items == 0 then return zeroOf(t) end
    if t.n == "auto" then
      local parts = {}
      for i, x in ipairs(items) do parts[i] = x.c end
      return "R.vecof(" .. #parts .. "," .. table.concat(parts, ",") .. ")"
    end
    return convert(items[1].c, items[1].t, t, items[1].lv)
  end

  -- a string method, a vector method and the like. Returns code, type or nil when it is not known
  local function builtinMethod(c, t, n, a, lvSet)
    local tn = t.n
    local function arg(i, want)
      local x = a[i]
      if not x then return "nil" end
      if want then return convert(x.c, x.t, want, x.lv) end
      return x.c
    end
    if tn == "string" then
      if n == "size" or n == "length" then return "#" .. (simple(c) and c or ("(" .. c .. ")")), LONG end
      if n == "empty" then return "(" .. c .. '=="")', BOOL end
      if n == "c_str" or n == "data" then return "R.cstr(" .. c .. ")", ptrTo(CHAR) end
      if n == "at" then return "R.strat(" .. c .. "," .. arg(1) .. ")", CHAR end
      if n == "substr" then return "R.substr(" .. c .. "," .. arg(1) .. (a[2] and ("," .. arg(2)) or "") .. ")", STRING end
      if n == "find" then return "R.strfind(" .. c .. "," .. arg(1, STRING) .. (a[2] and ("," .. arg(2)) or "") .. ")", LONG end
      if n == "rfind" then return "R.strrfind(" .. c .. "," .. arg(1, STRING) .. ")", LONG end
      if n == "compare" then return "R.strcmp(" .. c .. "," .. arg(1, STRING) .. ")", INT end
      if n == "front" then return "(" .. c .. "):byte(1)", CHAR end
      if n == "back" then return "(" .. c .. "):byte(-1)", CHAR end
      if n == "push_back" then return "", VOID, lvSet(c .. "..string.char(" .. arg(1) .. ")") end
      if n == "pop_back" then return "", VOID, lvSet("(" .. c .. "):sub(1,-2)") end
      if n == "append" then return "", VOID, lvSet(c .. ".." .. arg(1, STRING)) end
      if n == "clear" then return "", VOID, lvSet('""') end
      if n == "erase" then return "", VOID, lvSet("R.strerase(" .. c .. "," .. arg(1) .. (a[2] and ("," .. arg(2)) or "") .. ")") end
      if n == "insert" then return "", VOID, lvSet("R.strinsert(" .. c .. "," .. arg(1) .. "," .. arg(2, STRING) .. ")") end
      if n == "replace" then return "", VOID, lvSet("R.strreplace(" .. c .. "," .. arg(1) .. "," .. arg(2) .. "," .. arg(3, STRING) .. ")") end
      if n == "begin" then return "R.striter(" .. c .. ",0)", { n = "ptr", to = CHAR } end
      if n == "end" then return "R.striter(" .. c .. ",#" .. c .. ")", { n = "ptr", to = CHAR } end
      if n == "resize" then return "", VOID, lvSet("(" .. c .. "):sub(1," .. arg(1) .. ")") end
      return nil
    end
    if tn == "vector" or tn == "stack" or tn == "queue" then
      local el = t.to
      if n == "size" then return c .. ".n", LONG end
      if n == "empty" then return "(" .. c .. ".n==0)", BOOL end
      if n == "push_back" or n == "emplace_back" or (n == "push" and tn ~= "vector") then
        return "R.vpush(" .. c .. "," .. (a[1] and convert(a[1].c, a[1].t, el, a[1].lv) or zeroOf(el)) .. ")", VOID
      end
      if n == "pop_back" or (n == "pop" and tn == "stack") then return "R.vpop(" .. c .. ")", VOID end
      if n == "pop_front" or (n == "pop" and tn == "queue") then return "R.vshift(" .. c .. ")", VOID end
      if n == "push_front" then return "R.vinsert(" .. c .. ",R.ptr(" .. c .. ",0)," .. arg(1, el) .. ")", VOID end
      if n == "back" or (n == "top" and tn == "stack") then return c .. "[" .. c .. ".n-1]", el end
      if n == "front" or (n == "top" and tn == "queue") then return c .. "[0]", el end
      if n == "at" then return "R.vat(" .. c .. "," .. arg(1) .. ")", el end
      if n == "clear" then return "R.vclear(" .. c .. ")", VOID end
      if n == "begin" or n == "cbegin" then return "R.ptr(" .. c .. ",0)", ptrTo(el) end
      if n == "end" or n == "cend" then return "R.ptr(" .. c .. "," .. c .. ".n)", ptrTo(el) end
      if n == "rbegin" then return "R.rptr(" .. c .. "," .. c .. ".n-1)", ptrTo(el) end
      if n == "rend" then return "R.rptr(" .. c .. ",-1)", ptrTo(el) end
      if n == "erase" then return "R.verase(" .. c .. "," .. arg(1) .. (a[2] and ("," .. arg(2)) or "") .. ")", ptrTo(el) end
      if n == "insert" then return "R.vinsert(" .. c .. "," .. arg(1) .. "," .. arg(2, el) .. ")", ptrTo(el) end
      if n == "resize" then return "R.vresize(" .. c .. "," .. arg(1) .. ",function() return " .. (a[2] and arg(2, el) or zeroOf(el)) .. " end)", VOID end
      if n == "assign" then return "R.vassign(" .. c .. "," .. arg(1) .. "," .. arg(2, el) .. ")", VOID end
      if n == "reserve" or n == "shrink_to_fit" then return "R.void()", VOID end
      if n == "data" then return "R.ptr(" .. c .. ",0)", ptrTo(el) end
      if n == "capacity" then return c .. ".n", LONG end
      if n == "swap" then return "R.vswap(" .. c .. "," .. arg(1) .. ")", VOID end
      return nil
    end
    if tn == "pqueue" then
      if n == "push" or n == "emplace" then return "R.pqpush(" .. c .. "," .. arg(1, t.to) .. ")", VOID end
      if n == "pop" then return "R.pqpop(" .. c .. ")", VOID end
      if n == "top" then return "R.pqtop(" .. c .. ")", t.to end
      if n == "size" then return c .. ".n", LONG end
      if n == "empty" then return "(" .. c .. ".n==0)", BOOL end
      return nil
    end
    if tn == "map" or tn == "umap" or tn == "set" or tn == "uset" then
      local pairT = (tn == "map" or tn == "umap") and { n = "pair", a = t.k, b = t.v } or t.to
      local keyT = t.k or t.to
      if n == "size" then return c .. ".n", LONG end
      if n == "empty" then return "(" .. c .. ".n==0)", BOOL end
      if n == "count" then return "R.mcount(" .. c .. "," .. arg(1, keyT) .. ")", LONG end
      if n == "contains" then return "(R.mcount(" .. c .. "," .. arg(1, keyT) .. ")>0)", BOOL end
      if n == "find" then return "R.mfind(" .. c .. "," .. arg(1, keyT) .. ")", ptrTo(pairT) end
      if n == "begin" then return "R.mbegin(" .. c .. ")", ptrTo(pairT) end
      if n == "end" then return "R.mend(" .. c .. ")", ptrTo(pairT) end
      if n == "erase" then return "R.merase(" .. c .. "," .. arg(1, a[1] and a[1].t.n == "ptr" and a[1].t or keyT) .. ")", LONG end
      if n == "clear" then return "R.mclear(" .. c .. ")", VOID end
      if n == "insert" or n == "emplace" then
        if tn == "set" or tn == "uset" then return "R.mput(" .. c .. "," .. arg(1, keyT) .. ",true)", VOID end
        if a[2] then return "R.mputnew(" .. c .. "," .. arg(1, t.k) .. "," .. arg(2, t.v) .. ")", VOID end
        return "R.mputpair(" .. c .. "," .. arg(1) .. ")", VOID
      end
      if n == "at" then return "R.mat(" .. c .. "," .. arg(1, keyT) .. ")", t.v end
      return nil
    end
    return nil
  end

  -- x = v, as a statement; *p = v goes through the pointer
  placeSet = function(a, v)
    local inner = a:match("^R%.load(%b())$")
    if inner then return "R.store(" .. inner:sub(2, -2) .. "," .. v .. ")" end
    return a .. "=" .. v
  end
  local function primary()
    local t = tok
    if t.t == "int" then adv(); return tostring(t.v), t.long and LONG or (math.abs(t.v) > 2147483647 and LONG or INT)
    elseif t.t == "float" then adv(); return string.format("%.17g", t.v):find("[%.en]") and string.format("%.17g", t.v) or (string.format("%.17g", t.v) .. ".0"), DOUBLE
    elseif t.t == "char" then adv(); return tostring(t.v), CHAR
    elseif t.t == "str" then adv(); return str(t.v), CSTR
    elseif t.t == "op" then
      if t.v == "(" then
        adv()
        local c, ty, lv = expression()
        expectOp(")")
        if lv then return c, ty, lv end  -- (x) = 1 and (*p)++ : a place stays a place
        return "(" .. c .. ")", ty, lv
      elseif t.v == "[" then
        -- a lambda
        adv()
        while not isOp("]") do adv() end
        adv()
        local params = {}
        if acceptOp("(") then
          while not isOp(")") do
            local pt = parseType()
            local n, ty, isRef = parseDeclarator(pt)
            params[#params + 1] = { name = n, t = ty, ref = isRef }
            if not acceptOp(",") then break end
          end
          expectOp(")")
        end
        while isName("mutable") do adv() end
        local retT = AUTO
        if acceptOp("->") then retT = parseType(); retT = (select(2, parseDeclarator(retT, true))) end
        pushScope()
        local plist = {}
        for i, p in ipairs(params) do
          plist[i] = mangle(p.name or ("_a" .. i))
          bind(p.name or "_", plist[i], p.t)
        end
        local savedRet, savedLoops = curRet, loops
        curRet = retT; loops = {}
        local body = capture(function() blockBody() end)
        curRet, loops = savedRet, savedLoops
        popScope()
        return "function(" .. table.concat(plist, ",") .. ")\n" .. body .. "\nend", { n = "fn", ret = retT ~= AUTO and retT or nil }
      elseif t.v == "::" then adv(); return primary()
      elseif t.v == "{" then
        return braceInit(AUTO), AUTO
      end
      err()
    elseif t.t == "name" then
      local v = t.v
      if v == "this" then adv(); return "this", { n = "this" } end
      if v == "new" then
        adv()
        local ty = parseType()
        while acceptOp("*") do ty = ptrTo(ty) end
        if isOp("[") then
          adv()
          local len = assignExpr()
          expectOp("]")
          local arrT = { n = "arr", to = ty, len = len }
          local init = zeroOf(arrT)
          if isOp("{") then adv(); while not isOp("}") do adv() end adv() end
          return "R.ptr(" .. init .. ",0)", ptrTo(ty)
        end
        local args = {}
        if isOp("(") then adv(); args = argsOf()
        elseif isOp("{") then
          local c = braceInit(ty)
          return "R.box(" .. c .. ")", ptrTo(ty)
        end
        if isStruct(ty) then return "R.box(" .. constructCall(ty.name, args) .. ")", ptrTo(ty) end
        if args[1] then return "R.box(" .. convert(args[1].c, args[1].t, ty, args[1].lv) .. ")", ptrTo(ty) end
        return "R.box(" .. zeroOf(ty) .. ")", ptrTo(ty)
      end
      if v == "sizeof" then
        adv()
        local hadParen = isOp("(")
        local function sizeOfType(ty)
          local n = ty.n
          if n == "char" or n == "bool" or n == "uint8" then return "1" end
          if n == "uint16" then return "2" end
          if n == "int" or n == "uint" or n == "enum" then return "4" end
          if n == "long" or n == "double" or n == "ptr" then return "8" end
          if n == "arr" then return "(" .. (ty.len or "0") .. "*" .. sizeOfType(ty.to) .. ")" end
          if isStruct(ty) then
            local parts = {}
            local s = structs[ty.name]
            for _, f in ipairs(s and s.fieldList or {}) do parts[#parts + 1] = sizeOfType(f.t) end
            return #parts > 0 and ("(" .. table.concat(parts, "+") .. ")") or "1"
          end
          return "8"
        end
        if hadParen then
          local save = pos
          adv()
          if isTypeStart() then
            local ty = parseType()
            local _, full = parseDeclarator(ty, true)
            expectOp(")")
            return sizeOfType(full), LONG
          end
          pos = save; tok = toks[pos]
        end
        local _, ty = unary()
        return sizeOfType(ty), LONG
      end
      if v == "static_cast" or v == "dynamic_cast" or v == "const_cast" or v == "reinterpret_cast" then
        adv()
        expectOp("<")
        local ty = parseType()
        local _, full = parseDeclarator(ty, true)
        if isOp(">>") then tok = { t = "op", v = ">", line = tok.line }; toks[pos] = tok else expectOp(">") end
        expectOp("(")
        local c, from, lv = expression()
        expectOp(")")
        if v == "dynamic_cast" and isPtr(full) and isStruct(full.to) then return "R.dyncast(" .. c .. ",G." .. full.to.name .. ")", full end
        return convert(c, from, full, lv), full
      end
      if v == "std" and peek().v == "::" then adv(); adv(); return primary() end
      if v == "delete" then
        adv()
        if acceptOp("[") then expectOp("]") end
        local c, ty = unary()
        return "R.delete(" .. c .. ")", VOID
      end
      if v == "make_pair" or v == "pair" then
        local a2 = peek()
        if a2.v == "(" or a2.v == "<" then
          adv()
          if isOp("<") then templateArgs() end
          expectOp("(")
          local a = argsOf()
          local at, bt = typeForAuto(a[1].t), typeForAuto(a[2].t)
          return "R.pair(" .. convert(a[1].c, a[1].t, at.n == "ptr" and a[1].t.n == "cstr" and STRING or at, a[1].lv) .. "," .. convert(a[2].c, a[2].t, bt.n == "ptr" and a[2].t.n == "cstr" and STRING or bt, a[2].lv) .. ")", { n = "pair", a = a[1].t.n == "cstr" and STRING or at, b = a[2].t.n == "cstr" and STRING or bt }
        end
      end
      if v == "make_shared" or v == "make_unique" then
        adv()
        local a0 = templateArgs()
        expectOp("(")
        local a = argsOf()
        local ty = a0[1] or AUTO
        if isStruct(ty) then return "R.box(" .. constructCall(ty.name, a) .. ")", ptrTo(ty) end
        return "R.box(" .. (a[1] and a[1].c or "nil") .. ")", ptrTo(ty)
      end
      -- a type used as a constructor or a cast: int(x), string("a"), Point(1, 2), vector<int>(3, 0)
      if not lookup(v) and ((TYPEWORDS[v] and (isCpp or not CPPONLY[v])) or typedefs[v] or (structs[v] and isCpp) or (isCpp and CONTAINERS[v])) and (peek().v == "(" or peek().v == "{" or peek().v == "<") then
        do
          local ty = parseType()
          if isOp("{") then return braceInit(ty), ty end
          expectOp("(")
          local a = argsOf()
          if isStruct(ty) then return constructCall(ty.name, a), ty end
          if ty.n == "vector" then
            if #a == 0 then return "R.vec()", ty end
            if a[1].t.n == "ptr" then return "R.vecrange(" .. a[1].c .. "," .. a[2].c .. ")", ty end
            if isStruct(a[1].t) or a[1].t.n == "vector" then return "R.copy(" .. a[1].c .. ")", ty end
            local fill = a[2] and convert(a[2].c, a[2].t, ty.to, a[2].lv) or zeroOf(ty.to)
            return "R.vecn(" .. a[1].c .. ",function() return " .. fill .. " end)", ty
          end
          if ty.n == "string" and #a == 2 and isInt(a[1].t) and (a[2].t.n == "char" or isInt(a[2].t)) then return "R.sfill(" .. a[1].c .. "," .. a[2].c .. ")", ty end
          if a[1] then return convert(a[1].c, a[1].t, ty, a[1].lv), ty end
          return zeroOf(ty), ty
        end
      end
      adv()
      -- qualified names: A::b
      local qualifier
      while isOp("::") do
        adv()
        qualifier = v
        if tok.t ~= "name" then err() end
        v = tok.v
        adv()
      end
      if qualifier and structs[qualifier] then
        local s = structs[qualifier]
        local f = fieldOf(s, v)
        if f and f.static then return "G." .. f.owner .. "_" .. v, f.t, true end
        local e = scopes[1][qualifier .. "::" .. v]
        if e then return e.code, e.t end
        if isOp("(") then
          local m, owner = methodOf(s, v)
          if m then
            adv()
            local a = argsOf()
            local sig = findOverload(m, #a)
            if sig.static then return "G." .. owner.name .. "." .. mangle(v) .. "_" .. sig.arity .. "(" .. callWith(sig, a) .. ")", sig.ret end
            return "G." .. owner.name .. "." .. mangle(v) .. "_" .. sig.arity .. "(" .. callWith(sig, a, "this") .. ")", sig.ret
          end
        end
      end
      local e = scopes[1][(qualifier or "") .. "::" .. v]
      if e then return e.code, e.t end
      local b = lookup(v)
      if b then
        if b.ref then return b.code, b.t, true end
        if isOp("(") and b.t.n ~= "fn" and b.t.n ~= "auto" and isStruct(b.t) then
          -- a functor
          adv()
          local a = argsOf()
          local m = methodOf(structs[b.t.name], "op_call")
          local sig = findOverload(m, #a)
          return b.code .. ":op_call_" .. sig.arity .. "(" .. callWith(sig, a) .. ")", sig.ret
        end
        return b.code, b.t, not b.const
      end
      -- a member of the class we are in
      if curClass then
        local f = fieldOf(curClass, v)
        if f then
          if f.static then return "G." .. f.owner .. "_" .. v, f.t, true end
          return "this." .. mangle(v), f.t, true
        end
        if isOp("(") then
          local m, owner = methodOf(curClass, v)
          if m then
            adv()
            local a = argsOf()
            local sig = findOverload(m, #a)
            if not sig then err("no matching member function '" .. v .. "'") end
            if sig.static then return "G." .. owner.name .. "." .. mangle(v) .. "_" .. sig.arity .. "(" .. callWith(sig, a) .. ")", sig.ret end
            return "this:" .. mangle(v) .. "_" .. sig.arity .. "(" .. callWith(sig, a) .. ")", sig.ret
          end
        end
      end
      if CONSTS[v] then return CONSTS[v][1], CONSTS[v][2] end
      if v == "ios" and isOp("::") then
        adv()
        local flag = tok.v
        adv()
        return ({ app = "1", ate = "2", binary = "4", ["in"] = "8", out = "16", trunc = "32", beg = "0", cur = "1", ["end"] = "2" })[flag] or "0", INT
      end
      if v == "errno" then return 'R.load(R.lib("__errno_location")())', INT, true end
      if v == "optarg" then return 'R.load(R.lib("__optarg")())', ptrTo(CHAR), true end
      if v == "optind" or v == "opterr" or v == "optopt" then return 'R.load(R.lib("__' .. v .. '")())', INT, true end
      if isOp("(") or isOp("<") and funcs[v] then
        if isOp("<") then templateArgs() end
        expectOp("(")
        if v == "va_start" or v == "va_copy" or v == "va_arg" or v == "va_end" then
          local c1 = assignExpr()
          local r
          if v == "va_arg" then
            expectOp(",")
            local ty = parseType()
            local _, full = parseDeclarator(ty, true)
            expectOp(")")
            return "R.vaArg(" .. c1 .. ")", full or ty
          elseif v == "va_copy" then
            expectOp(",")
            local c2 = assignExpr()
            expectOp(")")
            return "R.vaCopy(function(_v) " .. c1 .. "=_v end," .. c2 .. ")", VOID
          elseif v == "va_start" then
            if acceptOp(",") then assignExpr() end
            expectOp(")")
            return "R.vaStart(function(_v) " .. c1 .. "=_v end,...)", VOID
          end
          expectOp(")")
          return "R.void()", VOID
        end
        local a = argsOf()
        local f = funcs[v]
        if f then
          local sig = findOverload(f, #a)
          if sig then return "G." .. mangle(v) .. "_" .. sig.arity .. "(" .. callWith(sig, a) .. ")", sig.ret end
          if isCpp then err("too many arguments to function '" .. v .. "'") end
        end
        if not isCpp and (f or protoEmpty[v]) then  -- the old C: the arguments of a function are not checked
          local parts = {}
          for i, x in ipairs(a) do parts[i] = plainArg(x) end
          local ret = protoEmpty[v] or (f and f[next(f)] and f[next(f)].ret) or INT
          return "(G." .. mangle(v) .. "_" .. #a .. " or R.lib(" .. str(v) .. "))(" .. table.concat(parts, ",") .. ")", ret
        end
        -- swap, min, max and such need the places or the types
        if v == "swap" and isCpp then
          local x, y = a[1], a[2]
          return "(function() " .. x.c .. "," .. y.c .. "=" .. y.c .. "," .. x.c .. " end)()", VOID
        end
        if (v == "move" or v == "forward") and isCpp then return a[1].c, a[1].t, false end
        if (v == "min" or v == "max") and isCpp then
          local rt = isFloat(a[1].t) and DOUBLE or a[1].t
          return "R." .. v .. "(" .. a[1].c .. "," .. a[2].c .. (a[3] and ("," .. a[3].c) or "") .. ")", rt
        end
        if v == "abs" then
          return "R.abs(" .. a[1].c .. ")", a[1].t.n == "double" and DOUBLE or a[1].t
        end
        if v == "getline" and a[1] and a[1].t.n == "stream" then
          local x = a[2]
          return "R.getlinefrom(" .. a[1].c .. ",function(_v) " .. x.c .. "=_v end" .. (a[3] and ("," .. a[3].c) or "") .. ")", BOOL
        end
        if v == "getline" and isCpp and #a >= 2 then
          local x = a[2]
          return "R.getlineinto(function(_v) " .. x.c .. "=_v end)", BOOL
        end
        if v == "to_string" then
          if a[1].t.n == "double" then return 'string.format("%f",' .. a[1].c .. ")", STRING end
          return "R.tolua_num(" .. toNumber(a[1].c, a[1].t) .. ")", STRING
        end
        if v == "stoi" or v == "stol" or v == "stoll" or v == "stod" or v == "stof" then
          return "R." .. v .. "(" .. a[1].c .. ")", (v == "stod" or v == "stof") and DOUBLE or (v == "stoi" and INT or LONG)
        end
        if v == "get" then err("std::get needs a template argument") end
        local parts = {}
        for i, x in ipairs(a) do parts[i] = plainArg(x) end
        -- a library function or a variable holding a function
        return "R.lib(" .. str(v) .. ")(" .. table.concat(parts, ",") .. ")", RET[v] or AUTO
      end
      if funcs[v] then
        local f = funcs[v]
        local sig = f.any or f[next(f)]
        return "G." .. mangle(v) .. "_" .. sig.arity, { n = "fn", ret = sig.ret }
      end
      if v == "fixed" or v == "scientific" or v == "defaultfloat" or v == "boolalpha" or v == "noboolalpha" or v == "left" or v == "right" or v == "hex" or v == "dec" or v == "oct" or v == "showpoint" or v == "flush" or v == "ws" then
        return "R.manip." .. v, base("manip")
      end
      syntaxError("'" .. v .. "' was not declared in this scope", t.line)
    end
    err()
  end

  local function postfix()
    local c, t, lv = primary()
    while true do
      if isOp("[") then
        adv()
        local i, it = expression()
        expectOp("]")
        i = toNumber(i, it)
        if t.n == "arr" then c, t, lv = c .. "[" .. i .. "]", t.to, true
        elseif t.n == "vector" then c, t, lv = c .. "[" .. i .. "]", t.to, true
        elseif t.n == "ptr" then
          local p = simple(c) and c or nil
          if p then c, t, lv = p .. ".a[" .. p .. ".i+" .. i .. "]", t.to, true
          else c, t, lv = "R.load(R.padd(" .. c .. "," .. i .. "))", t.to, true end
        elseif t.n == "string" then
          c, t, lv = "R.strget(" .. c .. "," .. i .. ")", CHAR, { strset = c, idx = i }
        elseif t.n == "cstr" then c, t, lv = "(" .. c .. "):byte(" .. i .. "+1)", CHAR, false
        elseif t.n == "map" or t.n == "umap" then
          local k = convert(i, it, t.k)
          c, t, lv = "R.mslot(" .. c .. "," .. k .. ").v", t.v, true
        elseif isStruct(t) then
          local m = methodOf(structs[t.name], "op_index")
          local sig = findOverload(m, 1)
          c, t, lv = c .. ":op_index_1(" .. i .. ")", sig.ret, true
        else c, t, lv = "R.anyindex(" .. c .. "," .. i .. ")", AUTO, true end
      elseif isOp(".") or isOp("->") then
        local arrow = tok.v == "->"
        adv()
        if isOp("~") then adv() end
        local n = tok.v
        adv()
        local obj, objT = c, t
        if arrow then
          if t.n == "this" then objT = { n = "struct", name = curClass.name }
          elseif t.n == "ptr" then
            if simple(c) then obj = c .. ".a[" .. c .. ".i]" else obj = "R.load(" .. c .. ")" end
            objT = t.to
          end
        end
        if objT.n == "this" then objT = { n = "struct", name = curClass.name } end
        if isOp("(") then
          adv()
          local a = argsOf()
          local function lvSet(v) return obj .. "=" .. v end
          local bc, bt, stmt = builtinMethod(obj, objT, n, a, lvSet)
          if bc then
            lv = false
            if stmt and stmt ~= true then
              c = "(function() " .. stmt .. " end)()"
              t = VOID
            else
              c, t = bc, bt
              if lv == false and (n == "back" or n == "front" or n == "top") then lv = true end
            end
          elseif isStruct(objT) and structs[objT.name] then
            local m, owner = methodOf(structs[objT.name], n)
            if not m then
              local f = fieldOf(structs[objT.name], n)
              if f then
                local parts = {}
                for i, x in ipairs(a) do parts[i] = plainArg(x) end
                c = obj .. "." .. mangle(n) .. "(" .. table.concat(parts, ",") .. ")"; t = AUTO
              else
                syntaxError("'" .. objT.name .. "' has no member named '" .. n .. "'", tok.line)
              end
            else
              local sig = findOverload(m, #a)
              if not sig then syntaxError("no matching function for call to '" .. n .. "'", tok.line) end
              c = obj .. ":" .. mangle(n) .. "_" .. sig.arity .. "(" .. callWith(sig, a) .. ")"
              t = sig.ret
            end
            lv = false
          elseif objT.n == "stream" then
            local parts = {}
            for i, x in ipairs(a) do parts[i] = plainArg(x) end
            c = "R.smethod(" .. obj .. "," .. str(n) .. (#parts > 0 and "," or "") .. table.concat(parts, ",") .. ")"
            t = n == "str" and STRING or (n == "is_open" or n == "good" or n == "eof" or n == "fail") and BOOL or AUTO
            lv = false
          elseif objT.n == "ostream" or objT.n == "istream" then
            local parts = {}
            for i, x in ipairs(a) do parts[i] = plainArg(x) end
            c = "R.streammethod(" .. str(n) .. (#parts > 0 and "," or "") .. table.concat(parts, ",") .. ")"
            t = AUTO; lv = false
          elseif n == "get" and t.n == "ptr" then c = c; lv = false
          else
            local parts = {}
            for i, x in ipairs(a) do parts[i] = plainArg(x) end
            c = "R.anycall(" .. obj .. "," .. str(n) .. (#parts > 0 and "," or "") .. table.concat(parts, ",") .. ")"
            t = AUTO; lv = false
          end
        else
          c, t, lv = memberAccess(obj, objT, n)
        end
      elseif isOp("(") then
        adv()
        local a = argsOf()
        local parts = {}
        for i, x in ipairs(a) do parts[i] = plainArg(x) end
        if c:sub(1, 8) == "function" then c = "(" .. c .. ")" end
        c = c .. "(" .. table.concat(parts, ",") .. ")"
        t = t.ret or AUTO
        lv = false
      elseif isOp("++") or isOp("--") then
        local d = tok.v == "++" and 1 or -1
        adv()
        local s = d == 1 and "+" or "-"
        if t.n == "ptr" then
          c = "(function() local _o=" .. c .. " " .. c .. "=R.padd(_o," .. d .. ") return _o end)()"
        else
          local nv = "_o" .. s .. "1"
          if WRAP[t.n] then nv = "(" .. nv .. ")&" .. WRAP[t.n] end
          c = "(function() local _o=" .. c .. " " .. placeSet(c, nv) .. " return _o end)()"
        end
        lv = false
      else break end
    end
    return c, t, lv
  end

  local function incStmt(c, t, d)
    if t.n == "ptr" then return c .. "=R.padd(" .. c .. "," .. d .. ")" end
    local nv = c .. (d == 1 and "+1" or "-1")
    if WRAP[t.n] then nv = "(" .. nv .. ")&" .. WRAP[t.n] end
    return placeSet(c, nv)
  end

  castOrUnary = function()
    if isOp("(") then
      local save = pos
      adv()
      if isTypeStart() then
        local ty = parseType()
        local _, full = parseDeclarator(ty, true)
        if isOp(")") then
          adv()
          if isOp("{") then return braceInit(full), full end
          local c, from, lv = castOrUnary()
          if isInt(full) and from.n == "double" then return convert(c, from, full), full end
          if full.n == "ptr" and from.n == "ptr" and from.to ~= VOID then
            if isStruct(full.to) and not (isStruct(from.to) and from.to.name == full.to.name) then
              return "R.retype(" .. c .. ",G." .. full.to.name .. "_zero)", full  -- (node *)my_malloc(n): new memory takes the type
            end
            return c, full
          end
          if full.n == "void" then return "R.void(" .. c .. ")", VOID end
          return convert(c, from, full, lv), full
        end
      end
      pos = save; tok = toks[pos]
    end
    return unary()
  end
  unary = function()
    local t = tok
    if t.t == "op" then
      local v = t.v
      if v == "-" then
        adv()
        local c, ty = castOrUnary()
        if isStruct(ty) then return c .. ":op_neg_0()", ty end
        return "(-" .. toNumber(c, ty) .. ")", ty.n == "bool" and INT or (ty.n == "char" and INT or ty)
      end
      if v == "+" then adv(); local c, ty = castOrUnary(); return c, ty end
      if v == "!" then adv(); local c, ty = castOrUnary(); return "(not " .. toBool(c, ty) .. ")", BOOL end
      if v == "~" then
        adv()
        local c, ty = castOrUnary()
        if WRAP[ty.n] then return "((~" .. c .. ")&" .. WRAP[ty.n] .. ")", ty end
        return "(~" .. c .. ")", ty
      end
      if v == "*" then
        adv()
        local c, ty = castOrUnary()
        if ty.n == "this" then return "this", { n = "struct", name = curClass.name }, true end
        if ty.n == "arr" then return c .. "[0]", ty.to, true end
        if ty.n == "ptr" then
          if simple(c) then return c .. ".a[" .. c .. ".i]", ty.to, true end
          return "R.load(" .. c .. ")", ty.to, true
        end
        if ty.n == "iter" then return "R.load(" .. c .. ")", AUTO, true end
        return "R.load(" .. c .. ")", AUTO, true
      end
      if v == "&" then
        adv()
        local c, ty, lv = castOrUnary()
        if ty.n == "fn" then return c, ty end
        if isStruct(ty) then return "R.box(" .. c .. ")", ptrTo(ty) end
        local el = c:match("^(.+)%[([^%[%]]-)%]$")
        if el then
          local base_, idx = c:match("^(.+)%[([^%[%]]-)%]$")
          return "R.ptr(" .. base_ .. "," .. idx .. ")", ptrTo(ty)
        end
        return addressOf(c, ty), ptrTo(ty)
      end
      if v == "++" or v == "--" then
        adv()
        local c, ty = castOrUnary()
        local s = incStmt(c, ty, v == "++" and 1 or -1)
        return "(function() " .. s .. " return " .. c .. " end)()", ty, false, s
      end
    end
    return postfix()
  end

  local function arith(op, a, ta, b, tb)
    if isStruct(ta) then
      local names = { ["+"] = "op_add", ["-"] = "op_sub", ["*"] = "op_mul", ["/"] = "op_div", ["%"] = "op_mod", ["<"] = "op_lt", [">"] = "op_gt", ["<="] = "op_le", [">="] = "op_ge", ["=="] = "op_eq", ["!="] = "op_ne" }
      local m = methodOf(structs[ta.name], names[op])
      if m then
        local sig = findOverload(m, 1)
        return a .. ":" .. names[op] .. "_1(" .. convert(b, tb, sig.params[1].t, false) .. ")", sig.ret
      end
      local g = funcs[names[op]]
      if g then
        local sig = findOverload(g, 2)
        return "G." .. names[op] .. "_2(" .. a .. "," .. b .. ")", sig.ret
      end
      err("no match for operator " .. op)
    end
    a, b = toNumber(a, ta), toNumber(b, tb)
    if ta.n == "cstr" and tb.n == "char" then return a .. "..string.char(" .. b .. ")", STRING end
    if ta.n == "string" or tb.n == "string" or (ta.n == "cstr" and tb.n == "cstr") then
      if op == "+" then
        local sa = ta.n == "char" and ("string.char(" .. a .. ")") or (ta.n == "ptr" and ("R.tolua(" .. a .. ")") or a)
        local sb = tb.n == "char" and ("string.char(" .. b .. ")") or (tb.n == "ptr" and ("R.tolua(" .. b .. ")") or b)
        return "(" .. sa .. ".." .. sb .. ")", STRING
      end
    end
    if ta.n == "ptr" or ta.n == "arr" or tb.n == "ptr" or tb.n == "arr" or ta.n == "cstr" or tb.n == "cstr" then
      local pa, ta2 = decay(a, ta)
      local pb, tb2 = decay(b, tb)
      if ta2.n == "ptr" and tb2.n == "ptr" then return "R.pdiff(" .. pa .. "," .. pb .. ")", LONG end
      if ta2.n == "ptr" then return "R.padd(" .. pa .. "," .. (op == "-" and ("-(" .. b .. ")") or b) .. ")", ta2 end
      return "R.padd(" .. pb .. "," .. a .. ")", tb2
    end
    if ta.n == "auto" or tb.n == "auto" then
      local f = { ["+"] = "R.dadd", ["-"] = "R.dsub", ["*"] = "R.dmul", ["/"] = "R.ddiv", ["%"] = "R.dmod" }
      return f[op] .. "(" .. a .. "," .. b .. ")", (ta.n == "double" or tb.n == "double") and DOUBLE or AUTO
    end
    local isF = isFloat(ta) or isFloat(tb)
    local rt = isF and DOUBLE or ((ta.n == "long" or tb.n == "long") and LONG or ((ta.n == "uint" or tb.n == "uint") and UINT or INT))
    if op == "/" then
      if isF then return "(" .. a .. "/" .. b .. ")", DOUBLE end
      return "R.idiv(" .. a .. "," .. b .. ")", rt
    end
    if op == "%" then
      if isF then err("invalid operands to binary % (have floating point)") end
      return "R.imod(" .. a .. "," .. b .. ")", rt
    end
    local e = "(" .. a .. op .. b .. ")"
    if rt == UINT then e = "(" .. e .. "&0xFFFFFFFF)" end
    return e, rt
  end
  local function mulExpr()
    local a, ta, lv, st = castOrUnary()
    while isOp("*") or isOp("/") or isOp("%") do
      local op = tok.v
      adv()
      local b, tb = castOrUnary()
      a, ta = arith(op, a, ta, b, tb)
      lv, st = false, nil
    end
    return a, ta, lv, st
  end
  local function addExpr()
    local a, ta, lv, st = mulExpr()
    while isOp("+") or isOp("-") do
      local op = tok.v
      adv()
      local b, tb = mulExpr()
      a, ta = arith(op, a, ta, b, tb)
      lv, st = false, nil
    end
    return a, ta, lv, st
  end
  local function outputOf(c, t)
    if t.n == "char" then return "string.char(" .. c .. ")" end
    if t.n == "bool" then return "R.boolout(" .. c .. ")" end
    if t.n == "double" then return "R.dbl(" .. c .. ")" end
    if t.n == "ptr" then
      if t.to == CHAR then return "R.tolua(" .. c .. ")" end
      return "R.ptrtext(" .. c .. ")"
    end
    if t.n == "auto" then return "R.anyout(" .. c .. ")" end
    if t.n == "arr" and t.to == CHAR then return "R.tolua(R.ptr(" .. c .. ",0))" end
    return c
  end
  local function shiftExpr()
    local a, ta, lv, st = addExpr()
    while isOp("<<") or isOp(">>") do
      local op = tok.v
      adv()
      local b, tb, blv = addExpr()
      if ta.n == "ostream" or (ta.n == "stream" and op == "<<") then
        if isStruct(tb) then
          local f = funcs.op_shl
          if not f then err("no match for operator<<") end
          a = "G.op_shl_2(" .. a .. "," .. b .. ")"
        elseif tb.n == "manip" then a = "R.coutmanip(" .. a .. "," .. b .. ")"
        else a = "R.coutput(" .. a .. "," .. outputOf(b, tb) .. ")" end
      elseif ta.n == "istream" or ta.n == "stream" then
        if tb.n == "double" then a = "R.cinread(" .. a .. ',"f",function(_v) ' .. b .. "=_v end)"
        elseif tb.n == "string" then a = "R.cinread(" .. a .. ',"s",function(_v) ' .. b .. "=_v end)"
        elseif tb.n == "char" then a = "R.cinread(" .. a .. ',"c",function(_v) ' .. b .. "=_v end)"
        else a = "R.cinread(" .. a .. ',"i",function(_v) ' .. b .. "=_v end)" end
      elseif isStruct(ta) then
        local nm = op == "<<" and "op_shl" or "op_shr"
        a = a .. ":" .. nm .. "_1(" .. b .. ")"
      else
        a, b = toNumber(a, ta), toNumber(b, tb)
        if op == "<<" then
          a = "(" .. a .. "<<" .. b .. ")"
          if WRAP[ta.n] then a = "(" .. a .. "&" .. WRAP[ta.n] .. ")" end
        elseif ta.n == "uint" or ta.n == "uint8" or ta.n == "uint16" then a = "(" .. a .. ">>" .. b .. ")"
        else a = "R.sar(" .. a .. "," .. b .. ")" end
        if ta.n == "char" or ta.n == "bool" then ta = INT end
      end
      lv, st = false, nil
    end
    return a, ta, lv, st
  end
  local function compare(op, a, ta, b, tb)
    local LUA = { ["<"] = "<", [">"] = ">", ["<="] = "<=", [">="] = ">=", ["=="] = "==", ["!="] = "~=" }
    if isStruct(ta) then return arith(op, a, ta, b, tb) end
    if (ta.n == "ptr" or ta.n == "arr" or ta.n == "iter") or (tb.n == "ptr" or tb.n == "arr") then
      -- with a string literal it is the text of a char* only for strings
      local pa, pb = (decay(a, ta)), (decay(b, tb))
      if pa == "0" or pa == "(0)" then pa = "nil" end
      if pb == "0" or pb == "(0)" then pb = "nil" end
      if op == "==" then return "R.peq(" .. pa .. "," .. pb .. ")", BOOL end
      if op == "!=" then return "(not R.peq(" .. pa .. "," .. pb .. "))", BOOL end
      return "(R.pdiff(" .. pa .. "," .. pb .. ")" .. LUA[op] .. "0)", BOOL
    end
    if ta.n == "string" and tb.n == "ptr" then b = "R.tolua(" .. b .. ")" end
    if ta.n == "bool" and tb.n ~= "bool" and isNum(tb) then a = toNumber(a, ta) end
    if tb.n == "bool" and ta.n ~= "bool" and isNum(ta) then b = toNumber(b, tb) end
    if (ta.n == "bool" or tb.n == "bool") and (op ~= "==" and op ~= "!=") then a, b = toNumber(a, ta), toNumber(b, tb) end
    return "(" .. a .. LUA[op] .. b .. ")", BOOL
  end
  local function relExpr()
    local a, ta, lv, st = shiftExpr()
    while isOp("<") or isOp(">") or isOp("<=") or isOp(">=") do
      local op = tok.v
      adv()
      local b, tb = shiftExpr()
      a, ta = compare(op, a, ta, b, tb)
      lv, st = false, nil
    end
    return a, ta, lv, st
  end
  local function eqExpr()
    local a, ta, lv, st = relExpr()
    while isOp("==") or isOp("!=") do
      local op = tok.v
      adv()
      local b, tb = relExpr()
      a, ta = compare(op, a, ta, b, tb)
      lv, st = false, nil
    end
    return a, ta, lv, st
  end
  local function bitLevel(nextF, opch, luaop)
    return function()
      local a, ta, lv, st = nextF()
      while isOp(opch) do
        adv()
        local b, tb = nextF()
        if ta.n == "bool" and tb.n == "bool" then
          if opch == "&" then a = "(" .. a .. " and " .. b .. ")" elseif opch == "|" then a = "(" .. a .. " or " .. b .. ")" else a = "(" .. a .. "~=" .. b .. ")" end
        else
          a = "(" .. toNumber(a, ta) .. luaop .. toNumber(b, tb) .. ")"
          if ta.n == "char" or ta.n == "bool" then ta = (tb.n == "long" or tb.n == "uint") and tb or INT end
          if tb.n == "long" or tb.n == "uint" then ta = tb end
        end
        lv, st = false, nil
      end
      return a, ta, lv, st
    end
  end
  local bitAnd = bitLevel(eqExpr, "&", "&")
  local bitXor = bitLevel(bitAnd, "^", "~")
  local bitOr = bitLevel(bitXor, "|", "|")
  local function andExpr()
    local a, ta, lv, st = bitOr()
    while isOp("&&") do
      adv()
      local b, tb = bitOr()
      a, ta = "(" .. toBool(a, ta) .. " and " .. toBool(b, tb) .. ")", BOOL
      lv, st = false, nil
    end
    return a, ta, lv, st
  end
  local function orExpr()
    local a, ta, lv, st = andExpr()
    while isOp("||") do
      adv()
      local b, tb = andExpr()
      a, ta = "(" .. toBool(a, ta) .. " or " .. toBool(b, tb) .. ")", BOOL
      lv, st = false, nil
    end
    return a, ta, lv, st
  end
  local function condExpr()
    local c, tc, lv, st = orExpr()
    if isOp("?") then
      adv()
      local a, ta = expression()
      expectOp(":")
      local b, tb = assignExpr()
      local rt = ta
      if isFloat(ta) or isFloat(tb) then rt = DOUBLE
      elseif ta.n == "cstr" and tb.n == "string" then rt = STRING
      elseif ta.n == "char" and tb.n == "int" then rt = INT end
      if ta.n == "ptr" and tb.n == "ptr" and tb.to == VOID then rt = ta end
      if tb.n == "ptr" and ta.n == "ptr" and ta.to == VOID then rt = tb end
      return "R.iff(" .. toBool(c, tc) .. ",function() return " .. convert(a, ta, rt) .. " end,function() return " .. convert(b, tb, rt) .. " end)", rt
    end
    return c, tc, lv, st
  end
  local COMPOUND = { ["+="] = "+", ["-="] = "-", ["*="] = "*", ["/="] = "/", ["%="] = "%", ["&="] = "&", ["|="] = "|", ["^="] = "^", ["<<="] = "<<", [">>="] = ">>" }
  assignExpr = function()
    local a, ta, lv, st = condExpr()
    if tok.t == "op" then
      local op = tok.v
      if op == "=" then
        adv()
        if type(lv) == "table" and lv.strset then
          local v, tv = assignExpr()
          local s = lv.strset .. "=R.strset(" .. lv.strset .. "," .. lv.idx .. "," .. v .. ")"
          return "(function() " .. s .. " end)()", CHAR, false, s
        end
        if not lv then syntaxError("lvalue required as left operand of assignment", tok.line) end
        local v, tv, vlv
        if isOp("{") then v = braceInit(ta); tv = ta
        else v, tv, vlv = assignExpr() end
        if isStruct(ta) and (not isStruct(tv) or tv.name ~= ta.name) then
          local s = structs[ta.name]
          local m = s and methodOf(s, "op_assign")
          if not m and s and s.ctors and findOverload(s.ctors, 1) then v = constructCall(ta.name, { { c = v, t = tv, lv = vlv } }); vlv = false; tv = ta end
        end
        local value = convert(v, tv, ta, vlv)
        local s = a .. "=" .. value
        local inner = a:match("^R%.load(%b())$")
        if inner then
          s = "R.store(" .. inner:sub(2, -2) .. "," .. value .. ")"
          return s, ta, false, s
        end
        return "(function() " .. s .. " return " .. a .. " end)()", ta, false, s
      elseif COMPOUND[op] then
        adv()
        local bop = COMPOUND[op]
        if type(lv) == "table" then err() end
        if not lv then syntaxError("lvalue required as left operand of assignment", tok.line) end
        local v, tv = assignExpr()
        local nv
        if ta.n == "string" then
          if tv.n == "char" then nv = a .. "..string.char(" .. v .. ")"
          elseif tv.n == "ptr" then nv = a .. "..R.tolua(" .. v .. ")"
          else nv = a .. ".." .. v end
        elseif isStruct(ta) then
          local names = { ["+"] = "op_addeq", ["-"] = "op_subeq", ["*"] = "op_muleq", ["/"] = "op_diveq" }
          local m = methodOf(structs[ta.name], names[bop])
          if m then
            local s = a .. ":" .. names[bop] .. "_1(" .. v .. ")"
            return s, ta, false, s
          end
          nv = (arith(bop, a, ta, v, tv))
        elseif bop == "&" or bop == "|" or bop == "^" or bop == "<<" or bop == ">>" then
          if bop == "^" then nv = "(" .. a .. "~" .. toNumber(v, tv) .. ")"
          elseif bop == ">>" then nv = (ta.n == "uint" or ta.n == "uint8" or ta.n == "uint16") and ("(" .. a .. ">>" .. v .. ")") or ("R.sar(" .. a .. "," .. v .. ")")
          else nv = "(" .. a .. bop .. toNumber(v, tv) .. ")" end
          nv = convert(nv, ta, ta)
        else
          local ex, ex_t = arith(bop, a, ta, v, tv)
          nv = convert(ex, ex_t, ta)
        end
        local s = placeSet(a, nv)
        return "(function() " .. s .. " return " .. a .. " end)()", ta, false, s
      end
    end
    return a, ta, lv, st
  end
  expression = function()
    local a, ta, lv, st = assignExpr()
    if isOp(",") then
      local stmts = { st or ("local _=" .. a) }
      local last, lastT, lastSt
      while acceptOp(",") do
        if last then stmts[#stmts + 1] = lastSt or ("local _=" .. last) end
        local b, tb, _, st2 = assignExpr()
        last, lastT, lastSt = b, tb, st2
      end
      local before = table.concat(stmts, " ")
      return "(function() " .. before .. " return " .. last .. " end)()", lastT, false, before .. " " .. (lastSt or ("local _=" .. last))
    end
    return a, ta, lv, st
  end

  local function exprStatementText()
    local a, ta, lv, st = expression()
    if st then return st end
    if a == "" then return "" end
    if a:sub(-1) == ")" and not a:find("^%(") and not a:find("^%-") then return a end
    return "local _=" .. a
  end

  -- ---- declarations of variables ----
  local function declareLocal(n, t, isRef, valueOf)
    local m = mangle(n)
    bind(n, m, t)
    return m
  end
  local function hasDtor(t) return isStruct(t) and structs[t.name] and methodOf(structs[t.name], "dtor") end

  local function localDeclaration()
    local bt = parseType()
    if isOp(";") then adv(); return end
    repeat
      -- auto [a, b] = ...
      if isOp("[") then
        adv()
        local names = {}
        repeat names[#names + 1] = tok.v; adv() until not acceptOp(",")
        expectOp("]")
        expectOp("=")
        local c, ty = assignExpr()
        local t_ = tmp()
        emit("local " .. t_ .. "=" .. c)
        if ty.n == "pair" then
          emit("local " .. mangle(names[1]) .. "," .. mangle(names[2]) .. "=" .. t_ .. ".first," .. t_ .. ".second")
          bind(names[1], mangle(names[1]), ty.a); bind(names[2], mangle(names[2]), ty.b)
        else
          for i, n in ipairs(names) do
            emit("local " .. mangle(n) .. "=" .. t_ .. "[" .. (i - 1) .. "]")
            bind(n, mangle(n), AUTO)
          end
        end
        goto continue
      end
      do
        local n, t, isRef = parseDeclarator(bt)
        if not isCpp and isOp("(") and n and (peek().v == ")" or (peek().t == "name" and (TYPEWORDS[peek().v] or typedefs[peek().v] or QUALS[peek().v] or peek().v == "struct"))) then
          -- a prototype inside a function: nothing to do
          local d = 0
          repeat
            if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
            adv()
          until d == 0
          goto nextName
        end
        if not n then err() end
        local m = mangle(n)
        if isRef then
          expectOp("=")
          local c, ty, lv = assignExpr()
          if ty.n ~= "auto" and t.n == "auto" then t = ty end
          if lv and (not isStruct(t)) and t.n ~= "vector" and t.n ~= "map" and t.n ~= "umap" and t.n ~= "set" and t.n ~= "pair" then
            -- a name for the same place: the place is kept in a pointer when it has parts that could change
            if simple(c) then bind(n, c, t)
            else
              local p = tmp()
              local el, idx = c:match("^(.+)%[([^%[%]]-)%]$")
              if el then emit("local " .. p .. "=R.ptr(" .. el .. "," .. idx .. ")")
              else emit("local " .. p .. "=" .. addressOf(c, t)) end
              bind(n, p .. ".a[" .. p .. ".i]", t)
            end
          else
            emit("local " .. m .. "=" .. c)
            bind(n, m, t)
          end
        else
          local isStatic = false
          if isOp("=") then
            adv()
            if isOp("{") then
              local c = braceInit(t)
              emit("local " .. m .. "=" .. c)
              bind(n, m, t)
            else
              local c, ty, lv = assignExpr()
              if t.n == "auto" then
                t = typeForAuto(ty)
                if ty.n == "cstr" then c = (decay(c, ty)); ty = t end
              end
              if t.n == "arr" then
                if ty.n == "cstr" then
                  if not t.len then t.len = "(#" .. c .. "+1)" end
                  emit("local " .. m .. "=R.chararr(" .. c .. "," .. t.len .. ")")
                else emit("local " .. m .. "=" .. c) end
              elseif isStruct(t) and not (isStruct(ty) and ty.name == t.name) then
                emit("local " .. m .. "=" .. constructCall(t.name, { { c = c, t = ty, lv = lv } }))
              else
                emit("local " .. m .. "=" .. convert(c, ty, t, lv))
              end
              bind(n, m, t)
            end
          elseif isOp("{") then
            emit("local " .. m .. "=" .. braceInit(t))
            bind(n, m, t)
          elseif t.n == "stream" and isOp("(") then
            adv()
            local a = argsOf()
            local parts = { str(t.kind) }
            for _, x in ipairs(a) do parts[#parts + 1] = plainArg(x) end
            emit("local " .. m .. "=R.stream(" .. table.concat(parts, ",") .. ")")
            bind(n, m, t)
          elseif isOp("(") and (isStruct(t) or t.n == "vector" or t.n == "string" or isNum(t) or t.n == "pair" or t.n == "map") then
            adv()
            local a = argsOf()
            local init
            if isStruct(t) then init = constructCall(t.name, a)
            elseif t.n == "vector" then
              if a[1] and (a[1].t.n == "vector") then init = "R.copy(" .. a[1].c .. ")"
              elseif a[1] and a[1].t.n == "ptr" then init = "R.vecrange(" .. a[1].c .. "," .. a[2].c .. ")"
              elseif a[1] then
                local fill = a[2] and convert(a[2].c, a[2].t, t.to, a[2].lv) or zeroOf(t.to)
                init = "R.vecn(" .. a[1].c .. ",function() return " .. fill .. " end)"
              else init = "R.vec()" end
            elseif t.n == "string" then
              if a[2] and a[1].t.n ~= "cstr" then init = "string.rep(string.char(" .. a[2].c .. ")," .. a[1].c .. ")"
              else init = a[1] and convert(a[1].c, a[1].t, STRING) or '""' end
            elseif t.n == "pair" then init = "R.pair(" .. convert(a[1].c, a[1].t, t.a) .. "," .. convert(a[2].c, a[2].t, t.b) .. ")"
            else init = a[1] and convert(a[1].c, a[1].t, t, a[1].lv) or zeroOf(t) end
            emit("local " .. m .. "=" .. init)
            bind(n, m, t)
          else
            emit("local " .. m .. "=" .. zeroOf(t))
            bind(n, m, t)
          end
          if hasDtor(t) and dtorScopes[#dtorScopes] then
            table.insert(dtorScopes[#dtorScopes], m)
          end
        end
      end
      ::continue::
    ::nextName::
      until not acceptOp(",")
    expectOp(";")
  end

  -- the destructors of a block
  local function runDtors(fromIdx)
    for i = #dtorScopes, fromIdx, -1 do
      local d = dtorScopes[i]
      for j = #d, 1, -1 do emit(d[j] .. ":dtor_0()") end
    end
  end

  local function compoundStatement()
    expectOp("{")
    pushScope()
    dtorScopes[#dtorScopes + 1] = {}
    emit("do")
    while not isOp("}") do
      if tok.t == "eof" then err("expected '}' at end of input") end
      statement()
    end
    adv()
    local last = out[#out]
    if not (last and last:match("^do return")) then runDtors(#dtorScopes) end
    dtorScopes[#dtorScopes] = nil
    emit("end")
    popScope()
  end
  local function subStatement()
    if isOp("{") then compoundStatement()
    else
      pushScope()
      emit("do")
      statement()
      emit("end")
      popScope()
    end
  end
  blockBody = function()
    expectOp("{")
    dtorScopes[#dtorScopes + 1] = {}
    local mark = #dtorScopes
    pushScope()
    while not isOp("}") do
      if tok.t == "eof" then err("expected '}' at end of input") end
      statement()
    end
    adv()
    popScope()
    local last = out[#out]
    if not (last and last:match("^do return")) then runDtors(mark) end
    dtorScopes[#dtorScopes] = nil
  end
  local function newLabel(p) labelN = labelN + 1; return p .. labelN end

  statement = function()
    local t = tok
    if t.t == "op" then
      if t.v == "{" then return compoundStatement() end
      if t.v == ";" then adv(); return end
    elseif t.t == "name" then
      local v = t.v
      if v == "if" then
        adv()
        if isName("constexpr") then adv() end
        expectOp("(")
        local c, ty = expression()
        expectOp(")")
        emit("if " .. toBool(c, ty) .. " then")
        subStatement()
        if acceptName("else") then emit("else"); subStatement() end
        emit("end")
        return
      elseif v == "while" then
        adv()
        expectOp("(")
        local c, ty = expression()
        expectOp(")")
        local rec = { cont = newLabel("cont_"), brk = newLabel("brk_"), isLoop = true }
        loops[#loops + 1] = rec
        emit("while " .. toBool(c, ty) .. " do")
        subStatement()
        emit("::" .. rec.cont .. "::")
        emit("end")
        emit("::" .. rec.brk .. "::")
        loops[#loops] = nil
        return
      elseif v == "do" then
        adv()
        local rec = { cont = newLabel("cont_"), brk = newLabel("brk_"), isLoop = true }
        loops[#loops + 1] = rec
        emit("while true do")
        subStatement()
        emit("::" .. rec.cont .. "::")
        if not acceptName("while") then err("expected 'while'") end
        expectOp("(")
        local c, ty = expression()
        expectOp(")")
        expectOp(";")
        emit("if not " .. toBool(c, ty) .. " then break end")
        emit("end")
        emit("::" .. rec.brk .. "::")
        loops[#loops] = nil
        return
      elseif v == "for" then
        adv()
        expectOp("(")
        pushScope()
        emit("do")
        -- a range for?
        local isRange = false
        do
          local d, p, q = 0, pos, 0
          while true do
            local x = toks[p]
            if x.t == "eof" then break end
            if x.t == "op" then
              if x.v == "?" then q = q + 1
              elseif x.v == ":" and q > 0 then q = q - 1
              elseif x.v == "(" or x.v == "[" or x.v == "{" then d = d + 1
              elseif x.v == ")" or x.v == "]" or x.v == "}" then
                if d == 0 then break end
                d = d - 1
              elseif x.v == ";" and d == 0 then break
              elseif x.v == ":" and d == 0 then isRange = true; break end
            end
            p = p + 1
          end
        end
        local rec = { cont = newLabel("cont_"), brk = newLabel("brk_"), isLoop = true }
        if isRange then
          local bt = parseType()
          local names, n, ty, isRef
          if isOp("&") or isOp("&&") then adv(); isRef = true end
          if isOp("[") then
            adv()
            names = {}
            repeat names[#names + 1] = tok.v; adv() until not acceptOp(",")
            expectOp("]")
            ty = bt
          else
            local r2
            n, ty, r2 = parseDeclarator(bt)
            isRef = isRef or r2
          end
          expectOp(":")
          local c, ct = expression()
          expectOp(")")
          local el = ct.to or AUTO
          if ct.n == "map" or ct.n == "umap" then el = { n = "pair", a = ct.k, b = ct.v } end
          if ct.n == "string" or ct.n == "cstr" then el = CHAR end
          if ty.n == "auto" or (names ~= nil) then ty = el end
          local i_, src = tmp(), tmp()
          local isVec = ct.n == "vector" or ct.n == "arr"
          emit("local " .. src .. "=" .. (isVec and c or ("R.rangeOf(" .. c .. ")")))
          local len = ct.n == "arr" and ct.len or (src .. ".n")
          if not len then err("cannot range over an array of unknown size") end
          emit("for " .. i_ .. "=0," .. len .. "-1 do")
          loops[#loops + 1] = rec
          local elem = src .. "[" .. i_ .. "]"
          if names then
            emit("local " .. mangle(names[1]) .. "," .. mangle(names[2]) .. "=" .. elem .. ".first," .. elem .. ".second")
            bind(names[1], mangle(names[1]), el.a or AUTO)
            bind(names[2], mangle(names[2]), el.b or AUTO)
          elseif isRef then bind(n, elem, ty)
          else
            emit("local " .. mangle(n) .. "=" .. convert(elem, el, ty, true))
            bind(n, mangle(n), ty)
          end
          subStatement()
          loops[#loops] = nil
          emit("::" .. rec.cont .. "::")
          emit("end")
          emit("end")
          emit("::" .. rec.brk .. "::")
          popScope()
          return
        end
        if isTypeStart() then localDeclaration()
        else
          if not isOp(";") then emit(exprStatementText()) end
          expectOp(";")
        end
        local cond = "true"
        if not isOp(";") then local c, ty = expression(); cond = toBool(c, ty) end
        expectOp(";")
        local update = ""
        if not isOp(")") then
          update = capture(function()
            local a, ta, lv, st = expression()
            if st then emit(st)
            elseif a:find("^%(function") then emit("local _=" .. a)
            elseif a ~= "" then emit("local _=" .. a) end
          end)
        end
        -- i++ in the update: a plain statement
        expectOp(")")
        loops[#loops + 1] = rec
        emit("while " .. cond .. " do")
        subStatement()
        emit("::" .. rec.cont .. "::")
        emit(update)
        emit("end")
        emit("end")
        emit("::" .. rec.brk .. "::")
        loops[#loops] = nil
        popScope()
        return
      elseif v == "switch" then
        adv()
        expectOp("(")
        local c, ty = expression()
        expectOp(")")
        expectOp("{")
        local rec = { brk = newLabel("brk_"), isSwitch = true, cont = nil }
        local cases = {}
        local s = tmp()
        local base_ = labelN
        local n = 0
        pushScope()
        loops[#loops + 1] = rec
        local body = capture(function()
          while not isOp("}") do
            if isName("case") or isName("default") then
              n = n + 1
              local label = "case_" .. base_ .. "_" .. n
              if acceptName("case") then
                local cv = assignExpr()
                if acceptOp("...") then
                  local cv2 = assignExpr()
                  cases[#cases + 1] = { range = { cv, cv2 }, label = label }
                else cases[#cases + 1] = { v = cv, label = label } end
              else adv(); cases[#cases + 1] = { default = true, label = label } end
              expectOp(":")
              emit("::" .. label .. "::")
            else
              emit("do")
              statement()
              emit("end")
            end
          end
        end)
        adv()
        loops[#loops] = nil
        popScope()
        emit("do local " .. s .. "=" .. toNumber(c, ty))
        local def
        for _, x in ipairs(cases) do
          if x.default then def = x.label
          elseif x.range then emit("if " .. s .. ">=" .. x.range[1] .. " and " .. s .. "<=" .. x.range[2] .. " then goto " .. x.label .. " end")
          else emit("if " .. s .. "==" .. x.v .. " then goto " .. x.label .. " end") end
        end
        emit("goto " .. (def or rec.brk))
        emit(body)
        emit("end")
        emit("::" .. rec.brk .. "::")
        return
      elseif v == "break" then
        adv()
        expectOp(";")
        local l = loops[#loops]
        if not l then err("break statement not within loop or switch") end
        emit("goto " .. l.brk)
        return
      elseif v == "continue" then
        adv()
        expectOp(";")
        for i = #loops, 1, -1 do
          if loops[i].isLoop then emit("goto " .. loops[i].cont); return end
        end
        err("continue statement not within a loop")
      elseif v == "return" then
        adv()
        if isOp(";") then
          adv()
          runDtors(1)
          if curRet and curRet.tryDepth then end
          emit("do return end")
          return
        end
        local c, ty, lv
        if isOp("{") then c = braceInit(curRet or AUTO); ty = curRet or AUTO
        else c, ty, lv = expression() end
        expectOp(";")
        if curRet and curRet.n ~= "auto" then c = convert(c, ty, curRet, lv and not curRet.isRefRet) elseif lv and isStruct(ty) then c = "R.copy(" .. c .. ")" end
        local any = false
        for i = 1, #dtorScopes do if #dtorScopes[i] > 0 then any = true end end
        if any then
          local r = tmp()
          emit("local " .. r .. "=" .. c)
          runDtors(1)
          emit("do return " .. r .. " end")
        else
          emit("do return " .. c .. " end")
        end
        return
      elseif v == "goto" then
        adv()
        emit("goto u_" .. tok.v)
        adv()
        expectOp(";")
        return
      elseif v == "try" then
        adv()
        local ok, e, val = tmp(), tmp(), tmp()
        local body = capture(function() compoundStatement() end)
        emit("do local " .. ok .. "," .. e .. "," .. val .. "=pcall(function()\n" .. body .. "\nend)")
        emit("if not " .. ok .. " then")
        emit("local _x=R.caught(" .. e .. ")")
        local first = true
        while acceptName("catch") do
          expectOp("(")
          pushScope()
          local cond = "true"
          local nameBind
          if acceptOp("...") then
          else
            local bt = parseType()
            local n, ct = parseDeclarator(bt)
            if isStruct(ct) then cond = "R.instof(_x,G." .. ct.name .. ")"
            elseif ct.n == "string" or (ct.n == "ptr" and ct.to == CHAR) then cond = 'type(_x)=="string"'
            elseif isNum(ct) then cond = 'type(_x)=="number"' end
            if n then nameBind = n; bind(n, mangle(n), ct) end
          end
          expectOp(")")
          emit((first and "if " or "elseif ") .. cond .. " then")
          first = false
          if nameBind then emit("local " .. mangle(nameBind) .. "=_x") end
          compoundStatement()
          popScope()
        end
        emit("else error(" .. e .. ",0) end")
        emit("elseif " .. e .. '=="r" then do return ' .. val .. " end end")
        emit("end")
        return
      elseif v == "throw" then
        adv()
        local c, ty = expression()
        expectOp(";")
        if ty.n == "cstr" then emit("R.throw(" .. c .. ")") else emit("R.throw(" .. c .. ")") end
        return
      elseif v == "using" or v == "typedef" and false then
        while not isOp(";") do adv() end
        adv()
        return
      elseif v == "typedef" then
        adv()
        local bt = parseType()
        local n, ty = parseDeclarator(bt)
        typedefs[n] = ty
        expectOp(";")
        return
      elseif peek().t == "op" and peek().v == ":" and v ~= "default" and v ~= "case" and not TYPEWORDS[v] then
        adv(); adv()
        emit("::u_" .. v .. "::")
        return
      end
      if isTypeStart() then
        -- a declaration, unless it is a call like Point(1,2);
        return localDeclaration()
      end
    end
    local s = exprStatementText()
    expectOp(";")
    if s ~= "" then emit(s) end
  end

  -- ---- functions and classes ----
  local function parseParams()
    expectOp("(")
    local params = {}
    if isName("void") and peek().v == ")" then adv() end
    -- the old form: f(a, b) char *a; int b; { ... }
    if tok.t == "name" and not isTypeStart() and (peek().v == "," or peek().v == ")") then
      local names, byName = {}, {}
      while tok.t == "name" do
        names[#names + 1] = tok.v
        adv()
        if not acceptOp(",") then break end
      end
      expectOp(")")
      while not isOp("{") and not isOp(";") and tok.t ~= "eof" do
        local bt = parseType()
        repeat
          local n, ty = parseDeclarator(bt)
          if ty.n == "arr" then ty = ptrTo(ty.to) end
          byName[n] = ty
        until not acceptOp(",")
        expectOp(";")
      end
      for i, n in ipairs(names) do params[i] = { name = n, t = byName[n] or INT } end
      return params
    end
    while not isOp(")") do
      if acceptOp("...") then params.variadic = true; break end
      local isConst = isName("const")
      local bt = parseType()
      local n, ty, isRef = parseDeclarator(bt)
      if ty.n == "arr" then ty = ptrTo(ty.to) end
      local p = { name = n, t = ty, ref = isRef, mut = isRef and not isConst }
      if acceptOp("=") then
        local c, dt = assignExpr()
        p.def = convert(c, dt, ty)
      end
      params[#params + 1] = p
      if not acceptOp(",") then break end
    end
    expectOp(")")
    return params
  end
  local function addOverload(entry, sig)
    local required = 0
    for i, p in ipairs(sig.params) do if not p.def then required = i end end
    sig.arity = #sig.params
    for k = required, #sig.params do
      if not entry[k] then entry[k] = sig end
    end
    if sig.params.variadic then entry.any = sig end
  end
  local function functionBodyText(params, ret, selfParam, cls)
    pushScope()
    local names = {}
    if selfParam then names[1] = "this" end
    local prologue = {}
    for i, p in ipairs(params) do
      local m = mangle(p.name or ("_a" .. i))
      names[#names + 1] = m
      if p.name then
        if p.ref and p.mut and not byHandle(p.t) then
          bind(p.name, m .. ".a[" .. m .. ".i]", p.t)
        else
          bind(p.name, m, p.t)
        end
      end
    end
    if params.variadic then names[#names + 1] = "..." end
    local savedRet, savedLoops, savedD = curRet, loops, dtorScopes
    curRet, loops, dtorScopes = ret, {}, {}
    local body = capture(function() blockBody() end)
    curRet, loops, dtorScopes = savedRet, savedLoops, savedD
    popScope()
    return "function(" .. table.concat(names, ",") .. ")\n" .. body .. "\nend"
  end
  local OPNAMES = { ["+"] = "op_add", ["-"] = "op_sub", ["*"] = "op_mul", ["/"] = "op_div", ["%"] = "op_mod", ["=="] = "op_eq", ["!="] = "op_ne", ["<"] = "op_lt", [">"] = "op_gt", ["<="] = "op_le", [">="] = "op_ge", ["<<"] = "op_shl", [">>"] = "op_shr", ["+="] = "op_addeq", ["-="] = "op_subeq", ["*="] = "op_muleq", ["/="] = "op_diveq", ["="] = "op_assign", ["["] = "op_index", ["("] = "op_call", ["++"] = "op_inc", ["--"] = "op_dec", ["!"] = "op_not" }
  local function operatorName()
    -- after the word operator
    local v = tok.v
    adv()
    if v == "[" then expectOp("]")
    elseif v == "(" then expectOp(")") end
    return OPNAMES[v] or err("this operator is not supported")
  end
  local function templateHeader()
    if isName("template") then
      adv()
      expectOp("<")
      local d = 1
      while d > 0 do
        if isOp("<") then d = d + 1
        elseif isOp(">") then d = d - 1
        elseif isOp(">>") then d = d - 2
        elseif (isName("typename") or isName("class")) and peek().t == "name" then templateT[peek().v] = true end
        adv()
      end
    end
  end

  classBody = function(name)
    local baseName
    if acceptOp(":") then
      while not isOp("{") do
        if isName("public") or isName("private") or isName("protected") or isName("virtual") then adv()
        elseif tok.t == "name" then
          baseName = baseName or tok.v
          adv()
          if isOp("<") then templateArgs() end
        else adv() end
        acceptOp(",")
      end
    end
    if isOp(";") then return { n = "struct", name = name } end
    local s = { name = name, fields = {}, methods = {}, fieldList = {}, ctors = {}, base = baseName, isAggregate = true }
    structs[name] = s
    expectOp("{")
    local pending = {}
    local savedClass = curClass
    curClass = s
    -- first the declarations: all members are known before any body is compiled
    while not isOp("}") do
      if tok.t == "eof" then err("expected '}'") end
      if isName("public") or isName("private") or isName("protected") then
        adv(); expectOp(":")
      elseif acceptOp(";") then
      elseif isName("using") or isName("friend") and peek().v ~= "ostream" and peek(2).v ~= "ostream" and false then
        while not isOp(";") do adv() end
        adv()
      elseif isName("typedef") then
        adv()
        local bt = parseType()
        local n, ty = parseDeclarator(bt)
        typedefs[n] = ty
        expectOp(";")
      else
        local isFriend = isName("friend")
        templateHeader()
        local isStatic, isVirtual = false, false
        do
          local p = pos
          while toks[p].t == "name" and QUALS[toks[p].v] do
            if toks[p].v == "static" then isStatic = true end
            if toks[p].v == "virtual" then isVirtual = true end
            if toks[p].v == "friend" then isFriend = true end
            p = p + 1
          end
          pos = p; tok = toks[pos]
        end
        if isOp("~") then
          adv(); adv()
          expectOp("(")
          expectOp(")")
          while tok.t == "name" and QUALS[tok.v] do adv() end
          if acceptOp("=") then adv(); expectOp(";")
          elseif isOp("{") then
            local sig = { params = {}, ret = VOID, arity = 0 }
            s.methods.dtor = { [0] = sig }
            pending[#pending + 1] = { kind = "method", name = "dtor", sig = sig, bodyPos = pos }
            local d = 0
            repeat
              if isOp("{") then d = d + 1 elseif isOp("}") then d = d - 1 end
              adv()
            until d == 0
          else expectOp(";") end
        elseif isName(name) and peek().v == "(" then
          -- a constructor
          s.isAggregate = false
          adv()
          local params = parseParams()
          while tok.t == "name" and QUALS[tok.v] do adv() end
          local sig = { params = params, ret = VOID }
          addOverload(s.ctors, sig)
          if acceptOp("=") then adv(); expectOp(";")   -- = default
          elseif isOp(";") then adv()
          else
            pending[#pending + 1] = { kind = "ctor", sig = sig, bodyPos = pos }
            -- skip the initializer list and the body
            while not isOp("{") do
              if isOp("(") then
                local d = 0
                repeat
                  if isOp("(") then d = d + 1 elseif isOp(")") then d = d - 1 end
                  adv()
                until d == 0
              elseif isOp("{") then break
              else adv() end
              if tok.t == "name" and peek().v == "{" then adv(); local d = 0; repeat if isOp("{") then d = d + 1 elseif isOp("}") then d = d - 1 end adv() until d == 0 end
            end
            local d = 0
            repeat
              if isOp("{") then d = d + 1 elseif isOp("}") then d = d - 1 end
              adv()
            until d == 0
          end
        else
          local bt = parseType()
          do
            local p = pos
            while toks[p].t == "op" and (toks[p].v == "&" or toks[p].v == "*" or toks[p].v == "&&") do p = p + 1 end
            if toks[p].t == "name" and toks[p].v == "operator" then pos = p; tok = toks[pos] end
          end
          repeat
            if isName("operator") then
              adv()
              local n = operatorName()
              local params = parseParams()
              while tok.t == "name" and QUALS[tok.v] do adv() end
              local sig = { params = params, ret = bt }
              if isFriend then
                funcs[n] = funcs[n] or {}
                addOverload(funcs[n], sig)
                sig.isFriend = true
                pending[#pending + 1] = { kind = "friend", name = n, sig = sig, bodyPos = pos }
              else
                s.methods[n] = s.methods[n] or {}
                addOverload(s.methods[n], sig)
                pending[#pending + 1] = { kind = "method", name = n, sig = sig, bodyPos = pos }
              end
              if isOp("{") then
                local d = 0
                repeat
                  if isOp("{") then d = d + 1 elseif isOp("}") then d = d - 1 end
                  adv()
                until d == 0
              else expectOp(";"); pending[#pending] = nil end
              break
            end
            local n, ty, isRef = parseDeclarator(bt)
            if isOp("(") then
              local params = parseParams()
              while tok.t == "name" and QUALS[tok.v] do adv() end
              local sig = { params = params, ret = ty, static = isStatic, isRefRet = isRef }
              s.methods[n] = s.methods[n] or {}
              addOverload(s.methods[n], sig)
              if acceptOp("=") then
                adv()     -- = 0 (pure virtual), = default
                expectOp(";")
              elseif isOp(";") then adv()
              else
                pending[#pending + 1] = { kind = "method", name = n, sig = sig, bodyPos = pos }
                local d = 0
                repeat
                  if isOp("{") then d = d + 1 elseif isOp("}") then d = d - 1 end
                  adv()
                until d == 0
              end
              break
            else
              local f = { name = n, t = ty, static = isStatic, owner = name }
              if acceptOp("=") then
                local save = pos
                f.init = assignExpr()
                f.initT = select(2, nil, AUTO)
              elseif isOp("{") then f.init = braceInit(ty) end
              if acceptOp(":") then assignExpr() end  -- a bit field
              s.fields[n] = f
              if not isStatic then s.fieldList[#s.fieldList + 1] = f end
              if isStatic then emit("G." .. name .. "_" .. n .. "=" .. (f.init or zeroOf(ty))) end
            end
          until not acceptOp(",") or (isOp(";") and (adv() or true) and false)
          acceptOp(";")
        end
      end
    end
    adv()
    -- what makes a zero value
    local allFields = {}
    local zeroBody = {}
    if s.base and structs[s.base] then zeroBody[#zeroBody + 1] = "G." .. s.base .. "_fill(o)" end
    for _, f in ipairs(s.fieldList) do
      zeroBody[#zeroBody + 1] = "o." .. mangle(f.name) .. "=" .. (f.init and convert(f.init, AUTO, f.t) or zeroOf(f.t))
    end
    emit("G." .. name .. "={__index=nil,__name=" .. str(name) .. "}")
    emit("G." .. name .. ".__index=G." .. name)
    if s.base then
      if not structs[s.base] then
        -- a library base class (std::exception and such)
        emit("setmetatable(G." .. name .. ",{__index=R.baseClass(" .. str(s.base) .. ")})")
      else
        emit("setmetatable(G." .. name .. ",{__index=G." .. s.base .. "})")
        emit("G." .. name .. ".__base=G." .. s.base)
      end
    end
    -- the zero function may run before the class bodies: it is defined now, and fields refer to each other by G
    emit("G." .. name .. "_fill=function(o)\n" .. table.concat(zeroBody, "\n") .. "\nend")
    emit("G." .. name .. "_zero=function() local o=setmetatable({},G." .. name .. ") G." .. name .. "_fill(o) return o end")
    -- the bodies, now that every member is known
    local endPos = pos
    local function bodyAt(p) pos = p; tok = toks[pos] end
    -- a method's text goes where the class is declared
    for _, m in ipairs(pending) do
      bodyAt(m.bodyPos)
      local sig = m.sig
      if m.kind == "method" then
        local text = functionBodyText(sig.params, sig.ret, not sig.static, s)
        emit("G." .. name .. "." .. mangle(m.name) .. "_" .. sig.arity .. "=" .. text)
      elseif m.kind == "friend" then
        local text = functionBodyText(sig.params, sig.ret, false, s)
        emit("G." .. m.name .. "_" .. sig.arity .. "=" .. text)
      else
        -- a constructor with its initializer list
        -- parameters are visible in the initializers: compile them inside
        pos = m.bodyPos; tok = toks[pos]
        local paramsScope = {}
        pushScope()
        local names = {}
        for i, p in ipairs(sig.params) do
          local mn = mangle(p.name or ("_a" .. i))
          names[#names + 1] = mn
          if p.name then
            if p.ref and p.mut and not byHandle(p.t) then bind(p.name, mn .. ".a[" .. mn .. ".i]", p.t)
            else bind(p.name, mn, p.t) end
          end
        end
        local initText = capture(function()
          if acceptOp(":") then
            repeat
              local f = tok.v
              adv()
              if isOp("<") then templateArgs() end
              local closing = isOp("{") and "}" or ")"
              adv()
              local args = {}
              while not isOp(closing) do
                local c, ty, lv = assignExpr()
                args[#args + 1] = { c = c, t = ty, lv = lv }
                if not acceptOp(",") then break end
              end
              expectOp(closing)
              if f == s.base then
                if structs[f] then
                  local bsig = findOverload(structs[f].ctors, #args)
                  if bsig then emit("G." .. f .. "_init_" .. bsig.arity .. "(this" .. (#args > 0 and "," or "") .. callWith(bsig, args) .. ")") end
                else
                  emit("this.__what=" .. (args[1] and convert(args[1].c, args[1].t, STRING) or '""'))
                end
              else
                local fd = fieldOf(s, f)
                if fd then
                  if isStruct(fd.t) then emit("this." .. mangle(f) .. "=" .. constructCall(fd.t.name, args))
                  elseif fd.t.n == "vector" and args[1] and args[1].t.n ~= "vector" then
                    emit("this." .. mangle(f) .. "=R.vecn(" .. args[1].c .. ",function() return " .. (args[2] and args[2].c or zeroOf(fd.t.to)) .. " end)")
                  elseif args[1] then emit("this." .. mangle(f) .. "=" .. convert(args[1].c, args[1].t, fd.t, args[1].lv))
                  else emit("this." .. mangle(f) .. "=" .. zeroOf(fd.t)) end
                end
              end
            until not acceptOp(",")
          end
        end)
        local savedRet, savedLoops, savedD = curRet, loops, dtorScopes
        curRet, loops, dtorScopes = VOID, {}, {}
        local body = capture(function() blockBody() end)
        curRet, loops, dtorScopes = savedRet, savedLoops, savedD
        popScope()
        local plist = table.concat(names, ",")
        emit("G." .. name .. "_init_" .. sig.arity .. "=function(this" .. (#names > 0 and "," or "") .. plist .. ")\n" .. initText .. "\n" .. body .. "\nend")
        emit("G." .. name .. "_new_" .. sig.arity .. "=function(" .. plist .. ") local o=G." .. name .. "_zero() G." .. name .. "_init_" .. sig.arity .. "(o" .. (#names > 0 and "," or "") .. plist .. ") return o end")
      end
    end
    -- a class with a parent constructor to run by default
    pos = endPos; tok = toks[pos]
    curClass = savedClass
    s.hasNoCtor = next(s.ctors) == nil
    return { n = "struct", name = name }
  end

  -- a top-level thing
  local function topLevel()
    if acceptOp(";") then return end
    if isName("using") then
      adv()
      if tok.t == "name" and peek().v == "=" then
        local n = tok.v
        adv(); adv()
        local bt = parseType()
        local _, ty = parseDeclarator(bt, true)
        typedefs[n] = ty
        expectOp(";")
        return
      end
      while not isOp(";") do adv() end
      adv()
      return
    end
    if isName("namespace") then
      adv()
      if tok.t == "name" then adv() end
      expectOp("{")
      while not isOp("}") do topLevel() end
      adv()
      return
    end
    if isName("typedef") then
      adv()
      local bt = parseType()
      repeat
        local n, ty = parseDeclarator(bt)
        typedefs[n] = ty
        if isStruct(ty) and structs[ty.name] == nil then structs[n] = nil end
      until not acceptOp(",")
      expectOp(";")
      return
    end
    templateHeader()
    local bt = parseType()
    if acceptOp(";") then return end
    do
      local p = pos
      while toks[p].t == "op" and (toks[p].v == "&" or toks[p].v == "*" or toks[p].v == "&&") do p = p + 1 end
      if toks[p].t == "name" and toks[p].v == "operator" then pos = p; tok = toks[pos] end
    end
    repeat
      if isName("operator") then
        adv()
        local n = operatorName()
        local params = parseParams()
        funcs[n] = funcs[n] or {}
        local sig = { params = params, ret = bt }
        addOverload(funcs[n], sig)
        if isOp("{") then emit("G." .. n .. "_" .. sig.arity .. "=" .. functionBodyText(params, bt, false))
        else expectOp(";") end
        return
      end
      -- Class::method defined outside
      local isOutside = tok.t == "name" and peek().v == "::" and structs[tok.v]
      if isOutside then
        local cname = tok.v
        adv(); adv()
        local s = structs[cname]
        local saved = curClass
        curClass = s
        if isName("operator") then
          adv()
          local n = operatorName()
          local params = parseParams()
          while tok.t == "name" and QUALS[tok.v] do adv() end
          local sig = s.methods[n] and findOverload(s.methods[n], #params)
          emit("G." .. cname .. "." .. n .. "_" .. sig.arity .. "=" .. functionBodyText(params, sig.ret, true, s))
        elseif isOp("~") then
          adv(); adv()
          parseParams()
          local sig = s.methods.dtor or { [0] = { params = {}, ret = VOID, arity = 0 } }
          s.methods.dtor = sig
          emit("G." .. cname .. ".dtor_0=" .. functionBodyText({}, VOID, true, s))
        elseif isName(cname) then
          adv()
          local params = parseParams()
          local sig = findOverload(s.ctors, #params)
          if not sig then err("no such constructor declared") end
          pushScope()
          local names = {}
          for i, p in ipairs(params) do
            local mn = mangle(p.name or ("_a" .. i))
            names[#names + 1] = mn
            if p.name then
              if p.ref and p.mut and not byHandle(p.t) then bind(p.name, mn .. ".a[" .. mn .. ".i]", p.t) else bind(p.name, mn, p.t) end
            end
          end
          local initText = capture(function()
            if acceptOp(":") then
              repeat
                local f = tok.v
                adv()
                local closing = isOp("{") and "}" or ")"
                adv()
                local args = {}
                while not isOp(closing) do
                  local c, ty, lv = assignExpr()
                  args[#args + 1] = { c = c, t = ty, lv = lv }
                  if not acceptOp(",") then break end
                end
                expectOp(closing)
                if f == s.base and structs[f] then
                  local bsig = findOverload(structs[f].ctors, #args)
                  if bsig then emit("G." .. f .. "_init_" .. bsig.arity .. "(this" .. (#args > 0 and "," or "") .. callWith(bsig, args) .. ")") end
                else
                  local fd = fieldOf(s, f)
                  if fd and args[1] then emit("this." .. mangle(f) .. "=" .. convert(args[1].c, args[1].t, fd.t, args[1].lv)) end
                end
              until not acceptOp(",")
            end
          end)
          local savedRet, savedLoops, savedD = curRet, loops, dtorScopes
          curRet, loops, dtorScopes = VOID, {}, {}
          local body = capture(function() blockBody() end)
          curRet, loops, dtorScopes = savedRet, savedLoops, savedD
          popScope()
          local plist = table.concat(names, ",")
          emit("G." .. cname .. "_init_" .. sig.arity .. "=function(this" .. (#names > 0 and "," or "") .. plist .. ")\n" .. initText .. "\n" .. body .. "\nend")
          emit("G." .. cname .. "_new_" .. sig.arity .. "=function(" .. plist .. ") local o=G." .. cname .. "_zero() G." .. cname .. "_init_" .. sig.arity .. "(o" .. (#names > 0 and "," or "") .. plist .. ") return o end")
        else
          local n, ty, isRef = parseDeclarator(bt)
          if isOp("(") then
            local params = parseParams()
            while tok.t == "name" and QUALS[tok.v] do adv() end
            local sig = s.methods[n] and findOverload(s.methods[n], #params)
            if not sig then err("no declaration of " .. n) end
            emit("G." .. cname .. "." .. mangle(n) .. "_" .. sig.arity .. "=" .. functionBodyText(params, sig.ret, not sig.static, s))
          else
            -- a static field
            if acceptOp("=") then
              local c = assignExpr()
              emit("G." .. cname .. "_" .. n .. "=" .. c)
            end
            expectOp(";")
          end
        end
        curClass = saved
        return
      end
      local n, ty, isRef = parseDeclarator(bt)
      if not n then err() end
      if isOp("(") then
        local noneTold = peek().v == ")"
        local params = parseParams()
        while tok.t == "name" and QUALS[tok.v] do adv() end
        if not isCpp and noneTold and isOp(";") and not funcs[n] then
          protoEmpty[n] = ty
          adv()
          return
        end
        funcs[n] = funcs[n] or {}
        local existing = funcs[n][#params]
        local sig = existing
        if not sig then
          sig = { params = params, ret = ty, isRefRet = isRef }
          addOverload(funcs[n], sig)
        else
          sig.params = params
        end
        if isOp("{") then
          emit("G." .. mangle(n) .. "_" .. sig.arity .. "=" .. functionBodyText(params, ty, false))
        else
          expectOp(";")
        end
        return
      end
      -- a global variable
      local gn = "G." .. (isCpp and "" or "v_") .. mangle(n)
      if ty.n == "arr" and isOp("=") and peek().t == "str" then
        adv()
        local c = assignExpr()
        if not ty.len then ty.len = "(#" .. c .. "+1)" end
        emit(gn .. "=R.chararr(" .. c .. "," .. ty.len .. ")")
      elseif acceptOp("=") then
        if isOp("{") then emit(gn .. "=" .. braceInit(ty))
        else
          local c, vt, lv = assignExpr()
          if ty.n == "auto" then ty = typeForAuto(vt) end
          emit(gn .. "=" .. convert(c, vt, ty, lv))
        end
      elseif isOp("{") then emit(gn .. "=" .. braceInit(ty))
      else emit(gn .. "=" .. zeroOf(ty)) end
      scopes[1][n] = { code = gn, t = ty }
    until not acceptOp(",")
    expectOp(";")
  end

  while tok.t ~= "eof" do topLevel() end
  local mainF = funcs.main
  if not mainF then syntaxError("undefined reference to `main'", 0) end
  local sig = mainF[0] or mainF[2] or mainF[next(mainF)]
  emit("return G.main_" .. sig.arity)
  return table.concat(out, "\n")
end

C.compile = compile

function C.main(args, isCpp)
  local rt = driver.load("crt")
  local inputs, outPath, run, compileOnly = {}, nil, false, false
  local i = 1
  while args[i] do
    local a = args[i]
    if a == "-o" then outPath = args[i + 1]; i = i + 1
    elseif a == "-run" then run = true
    elseif a == "--version" or a == "-v" then
      term.write((isCpp and "g++" or "gcc") .. " (ESP Linux, translates to Lua) 13.0\n")
      return 0
    elseif a == "--selftest" then
      local src = isCpp and '#include <iostream>\nint main(){std::cout<<"c++ ok "<<6*7<<std::endl;return 0;}' or '#include <stdio.h>\nint main(void){printf("c ok %d\\n",6*7);return 0;}'
      return rt.run(compile(src, isCpp), {})
    elseif a:sub(1, 1) == "-" and #inputs > 0 and run then inputs[#inputs + 1] = a
    elseif a:sub(1, 1) == "-" then -- flags of a compiler: -Wall, -O2, -std=c++17, -lm: nothing to do
    else
      inputs[#inputs + 1] = a
      if run then
        -- the rest are the arguments of the program
        i = i + 1
        while args[i] do inputs[#inputs + 1] = args[i]; i = i + 1 end
        break
      end
    end
    i = i + 1
  end
  if #inputs == 0 then
    term.write((isCpp and "g++" or "gcc") .. ": fatal error: no input files\ncompilation terminated.\n")
    return 1
  end
  local function report(path, e)
    if type(e) == "table" and e.syntax then
      term.write(path .. ":" .. tostring(e.line) .. ": error: " .. e.syntax .. "\ncompilation terminated.\n")
    else term.write(tostring(e) .. "\n") end
    return 1
  end
  local path = inputs[1]
  local src = fs.read(path)
  if not src then
    term.write((isCpp and "g++" or "gcc") .. ": error: " .. path .. ": No such file or directory\n")
    return 1
  end
  -- more source files are joined into one program
  if not run then
    for k = 2, #inputs do
      local more = fs.read(inputs[k])
      if more then src = src .. "\n" .. more end
    end
  end
  local cpp = isCpp or path:match("%.cpp$") or path:match("%.cc$") or path:match("%.cxx$")
  local ok, text = pcall(compile, src, cpp)
  if not ok then return report(path, text) end
  if run then
    local progArgs = {}
    for k = 1, #inputs do progArgs[k] = inputs[k] end
    return rt.run(text, progArgs)
  end
  outPath = outPath or "a.out"
  local program = '#!lua\nlocal rt = driver.load("crt")\nlocal text = ' .. string.format("%q", text):gsub("\\\n", "\\n") .. "\nlocal a = {" .. string.format("%q", outPath) .. "}\nfor i, v in ipairs(arg) do a[i + 1] = v end\nrt.run(text, a)\n"
  local w, e = fs.write(outPath, program)
  if not w then
    term.write("cannot write " .. outPath .. ": " .. tostring(e) .. "\n")
    return 1
  end
  if sys and sys.shell then pcall(sys.shell, "chmod +x " .. outPath) end
  return 0
end
return C
