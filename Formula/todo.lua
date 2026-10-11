#!lua
-- todo: a list of tasks, kept in /home/user/todo.txt (one line per task: "[ ] task" or "[x] task").
--   todo                  show the list
--   todo add TEXT...      add a task
--   todo done N           mark task N as done
--   todo undo N           mark task N as open again
--   todo rm N             remove task N
--   todo clear            remove the done tasks

local FILE = "/home/user/todo.txt"
local USAGE = "usage: todo | todo add TEXT | todo done N | todo undo N | todo rm N | todo clear"

local function load()
  local tasks = {}
  local text = fs.read(FILE)
  if not text then return tasks end
  for line in text:gmatch("[^\n]+") do
    local mark, body = line:match("^%[([ x])%] (.+)$")
    if mark then tasks[#tasks + 1] = { done = mark == "x", text = body } end
  end
  return tasks
end

local function save(tasks)
  local lines = {}
  for i, t in ipairs(tasks) do lines[i] = (t.done and "[x] " or "[ ] ") .. t.text end
  local ok, err = fs.write(FILE, #lines > 0 and table.concat(lines, "\n") .. "\n" or "")
  if not ok then
    print("todo: cannot save: " .. tostring(err))
    return false
  end
  return true
end

local function show(tasks)
  if #tasks == 0 then
    print("no tasks yet: todo add TEXT")
    return
  end
  local open = 0
  for i, t in ipairs(tasks) do
    if not t.done then open = open + 1 end
    print(string.format("%2d %s %s", i, t.done and "[x]" or "[ ]", t.text))
  end
  print(string.format("%d open, %d done", open, #tasks - open))
end

-- the number of a task, checked against the list; prints why it is wrong and returns nil
local function numberArg(tasks, text)
  local n = tonumber(text or "")
  if not n or n ~= math.floor(n) or n < 1 or n > #tasks then
    print("todo: no task " .. tostring(text) .. " (todo shows the numbers)")
    return nil
  end
  return n
end

local cmd = arg[1]
local tasks = load()

if not cmd then
  show(tasks)
elseif cmd == "add" then
  local text = table.concat(arg, " ", 2):gsub("[\r\n]", " ")
  if text == "" then
    print(USAGE)
    return
  end
  tasks[#tasks + 1] = { done = false, text = text }
  if save(tasks) then print(string.format("added %d: %s", #tasks, text)) end
elseif cmd == "done" or cmd == "undo" then
  local n = numberArg(tasks, arg[2])
  if not n then return end
  tasks[n].done = cmd == "done"
  if save(tasks) then print(string.format("%s %d: %s", cmd == "done" and "done" or "open", n, tasks[n].text)) end
elseif cmd == "rm" then
  local n = numberArg(tasks, arg[2])
  if not n then return end
  local removed = table.remove(tasks, n)
  if save(tasks) then print("removed " .. removed.text) end
elseif cmd == "clear" then
  local kept, removed = {}, 0
  for _, t in ipairs(tasks) do
    if t.done then
      removed = removed + 1
    else
      kept[#kept + 1] = t
    end
  end
  if save(kept) then print(string.format("removed %d done", removed)) end
else
  print(USAGE)
end
