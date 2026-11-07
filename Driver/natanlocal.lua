#!lua
-- natanlocal: the questions of natan answered by three small language models that run on this device (llm module of the
-- firmware), one after the other, and the terminal of the device:
--   natan-intent:pl   reads what you typed (Polish or English) and says what it is about, as JSON
--   natan-cmd:pl      writes the shell command (JSON), for example {"cmd":["df -h /"]}
--   natan-reply:pl    reads what the command printed and answers in a sentence, in your language
-- A command only runs when sys.check lets it through; one that changes files asks you first. Needs firmware with sys.run and
-- the models (ollama pull natan-intent:pl natan-cmd:pl natan-reply:pl). Used by natan-local-pl and by natan.

local json = driver.load("json")
if not json then error("natanlocal needs the json driver", 0) end

local M = {}
local SEP = " \194\182 "  -- " ¶ ": the line end inside the text of the models (they were trained on that)
M.models = { intent = "natan-intent:pl", cmd = "natan-cmd:pl", reply = "natan-reply:pl" }

-- the names of the models that are not on the card yet
function M.missing()
  local have = {}
  for _, m in ipairs(llm.list()) do
    if m.where == "local" then have[m.name] = true end
  end
  local out = {}
  for _, name in pairs({ M.models.intent, M.models.cmd, M.models.reply }) do
    if not have[name] then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- one answer of a model, as text (the models stop by themselves after the JSON)
local function ask(model, prompt, max, onText)
  local text, err = llm.generate(model, prompt, { max = max, temperature = 0 }, onText)
  if not text then return nil, err end
  return trim(text)
end

-- the output of a command as the reply model learned to read it: spaces collapsed, no empty lines, 12 lines, 400 characters
local function clean(cmd, out)
  local lines = {}
  for line in (out .. "\n"):gmatch("(.-)\r?\n") do
    line = trim(line:gsub("[ \t]+", " "))
    if line ~= "" then
      lines[#lines + 1] = line
      if #lines == 12 then break end
    end
  end
  local listing = cmd:match("^ls") and not cmd:match("^ls%s+%-[a-zA-Z]*l") and not cmd:find("|", 1, true)
  local text = table.concat(lines, listing and " " or "\n")
  return text:sub(1, 400)
end

-- asks the user, with t / y for yes and n for no (or enter / ctrl-c)
local function confirm(text)
  term.print(text .. " [t/n] ")
  while true do
    local k = key.poll()
    if k == "t" or k == "y" or k == "T" or k == "Y" then
      term.print("t")
      return true
    elseif k == "n" or k == "N" or k == "enter" or k == "ctrl-c" or k == "q" then
      term.print("n")
      return false
    end
    sys.sleep(20)
  end
end

-- Prints the text of the "answer" field while the JSON is still arriving, so the sentence is written as it is made
local function answerPrinter()
  local raw, printed = "", 0
  return function(piece)
    raw = raw .. piece
    local from = raw:match('"answer"%s*:%s*"()')
    if not from then return true end
    local out, i = {}, from
    while i <= #raw do
      local c = raw:sub(i, i)
      if c == '"' then break end
      if c == "\\" then
        local n = raw:sub(i + 1, i + 1)
        if n == "" then break end
        if n == "u" then
          if #raw < i + 5 then break end
          out[#out + 1] = utf8.char(tonumber(raw:sub(i + 2, i + 5), 16) or 63)
          i = i + 6
        else
          out[#out + 1] = ({ n = "\n", t = "\t" })[n] or n
          i = i + 2
        end
      else
        out[#out + 1] = c
        i = i + 1
      end
    end
    local text = table.concat(out)
    if #text > printed then
      term.write(text:sub(printed + 1))
      printed = #text
    end
    return true
  end, function() return printed end
end

local MESSAGES = {
  pl = {
    unclear = "Nie zrozumiałem, spróbuj inaczej.",
    denied = "Tej komendy nie wykonam: ",
    cancelled = "Anulowane.",
    run = "Wykonać",
    failed = "Komenda się nie udała: ",
  },
  en = {
    unclear = "I did not understand, try another way.",
    denied = "I will not run that command: ",
    cancelled = "Cancelled.",
    run = "Run",
    failed = "The command failed: ",
  },
}

-- Answers one question: the three models, the command and the sentence. Returns the answer (also printed as it is made), or nil
-- and the reason. opts.quiet leaves out the lines that show the command.
function M.ask(question, opts)
  opts = opts or {}
  local q = "Q: " .. question

  local intentText, err = ask(M.models.intent, q .. SEP .. "J:", 40)
  if not intentText then return nil, err end
  local intent = json.decode(intentText)
  if type(intent) ~= "table" or type(intent.intent) ~= "string" then
    term.print(MESSAGES.pl.unclear)
    return nil, "intent: " .. intentText
  end
  local msg = MESSAGES[intent.lang] or MESSAGES.pl

  local cmdText, cerr = ask(M.models.cmd, q .. SEP .. "I: " .. intentText .. SEP .. "C:", 80)
  if not cmdText then return nil, cerr end
  local cmds = json.decode(cmdText)
  if type(cmds) ~= "table" or type(cmds.cmd) ~= "table" then
    term.print(msg.unclear)
    return nil, "cmd: " .. cmdText
  end

  local output = {}
  for i, line in ipairs(cmds.cmd) do
    if i > 2 then break end
    if type(line) ~= "string" then break end
    local kind, why = sys.check(line)
    if kind == "denied" then
      term.print(msg.denied .. line .. " (" .. why .. ")")
      return nil, "denied"
    end
    if kind == "confirm" and not confirm(msg.run .. ": " .. line .. "?") then
      term.print(msg.cancelled)
      return nil, "cancelled"
    end
    if not opts.quiet then term.print("  $ " .. line, "dim") end
    local out, status = sys.run(line, kind == "confirm")
    if not out then
      term.print(msg.failed .. tostring(status))
      return nil, status
    end
    output[#output + 1] = clean(line, out)
  end

  local prompt = q .. SEP .. "C: " .. cmdText .. SEP .. "O: " .. table.concat(output, "\n"):gsub("\n", SEP) .. SEP .. "A:"
  local feed, printed = answerPrinter()
  local replyText, rerr = ask(M.models.reply, prompt, 120, feed)
  if not replyText then return nil, rerr end
  local reply = json.decode(replyText)
  local answer = type(reply) == "table" and type(reply.answer) == "string" and reply.answer or nil
  if not answer then
    term.print(msg.unclear)
    return nil, "reply: " .. replyText
  end
  if printed() == 0 then term.write(answer) end
  term.print("")
  return answer
end

return M
