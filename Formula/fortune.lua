#!lua
-- fortune: prints a random saying, like fortune-mod (categories, -f list, -m pattern, -s/-l/-n, -e, -c, -a/-o).
-- usage: fortune [-acefilosw] [-n length] [ -m pattern] [[#%] file/dir/all]

local USAGE = "Usage: fortune [-acefilosw] [-n length] [ -m pattern] [[#%] file/dir/all]"

-- classic public-domain sayings, short attributed quotations and pieces of advice written for this package.
-- a line is "text" or "text|author"; the categories are the "files" of the list
local CATS = {
  computers = {
    "Beware of bugs in the above code; I have only proved it correct, not tried it.|Donald Knuth",
    "Premature optimization is the root of all evil.|Donald Knuth",
    "Simplicity is prerequisite for reliability.|Edsger W. Dijkstra",
    "There are only two hard things in computer science: cache invalidation and naming things.|Phil Karlton",
    "The best way to predict the future is to invent it.|Alan Kay",
    "Debugging is twice as hard as writing the code in the first place. Therefore, if you write the code as cleverly as possible, you are, by definition, not smart enough to debug it.|Brian W. Kernighan",
    "Talk is cheap. Show me the code.|Linus Torvalds",
    "Unix is simple. It just takes a genius to understand its simplicity.|Dennis Ritchie",
    "Make it work, make it right, make it fast.|Kent Beck",
    "The only way to learn a new programming language is by writing programs in it.|Dennis Ritchie",
    "Software is like entropy: it is difficult to grasp, weighs nothing, and obeys the Second Law of Thermodynamics; i.e., it always increases.|Norman Augustine",
    "The first 90 percent of the code accounts for the first 90 percent of the development time. The remaining 10 percent of the code accounts for the other 90 percent of the development time.|Tom Cargill",
    "Programs must be written for people to read, and only incidentally for machines to execute.|Harold Abelson",
    "The function of good software is to make the complex appear to be simple.|Grady Booch",
    "Controlling complexity is the essence of computer programming.|Brian W. Kernighan",
    "One of my most productive days was throwing away 1000 lines of code.|Ken Thompson",
    "When in doubt, use brute force.|Ken Thompson",
    "A program that has not been tested does not work.|Bjarne Stroustrup",
    "Walking on water and developing software from a specification are easy if both are frozen.|Edward V. Berard",
    "The most effective debugging tool is still careful thought, coupled with judiciously placed print statements.|Brian W. Kernighan",
    "Computer science is no more about computers than astronomy is about telescopes.|Edsger W. Dijkstra",
    "Program testing can be used to show the presence of bugs, but never to show their absence.|Edsger W. Dijkstra",
    "The competent programmer is fully aware of the strictly limited size of his own skull.|Edsger W. Dijkstra",
    "Deleted code is debugged code.|Jeff Sickel",
    "It's easier to ask forgiveness than it is to get permission.|Grace Hopper",
    "The most dangerous phrase in the language is: we've always done it this way.|Grace Hopper",
    "A ship in port is safe, but that is not what ships are for.|Grace Hopper",
    "Perfection is achieved, not when there is nothing more to add, but when there is nothing left to take away.|Antoine de Saint-Exupery",
    "Always code as if the guy who ends up maintaining your code will be a violent psychopath who knows where you live.|John Woods",
    "Any sufficiently advanced technology is indistinguishable from magic.|Arthur C. Clarke",
    "Fancy algorithms are slow when n is small, and n is usually small.|Rob Pike",
    "Data dominates. If you've chosen the right data structures and organized things well, the algorithms will almost always be self-evident.|Rob Pike",
    "You can't tell where a program is going to spend its time. Bottlenecks occur in surprising places.|Rob Pike",
    "Adding manpower to a late software project makes it later.|Fred Brooks",
    "The bearing of a child takes nine months, no matter how many women are assigned.|Fred Brooks",
    "Plan to throw one away; you will, anyhow.|Fred Brooks",
    "The cheapest, fastest, and most reliable components are those that aren't there.|Gordon Bell",
    "UNIX was not designed to stop its users from doing stupid things, as that would also stop them from doing clever things.|Doug Gwyn",
    "A language that doesn't affect the way you think about programming is not worth knowing.|Alan Perlis",
    "First, solve the problem. Then, write the code.|John Johnson",
    "Code never lies, comments sometimes do.|Ron Jeffries",
    "A computer lets you make more mistakes faster than any other invention with the possible exception of handguns and tequila.|Mitch Ratcliffe",
    "To err is human; to really foul things up requires a computer.",
    "Keep it simple, stupid.",
    "Measure first. Your guess about the slow part is probably wrong.",
    "Short functions are easy to test. Long ones are easy to forget.",
    "Name things for what they do, not for how they are built.",
    "Every program is a list of decisions. Write the reasons down.",
    "Simple solutions age better than clever ones.",
    "Read the error message. All of it. The answer is often in the middle.",
    "A bug that reproduces every time is a gift. Enjoy it briefly.",
    "Commit early, commit often, and read the diff before you push.",
    "The best time to back up your SD card was yesterday.",
    "There are 10 kinds of people: those who understand binary and those who don't.",
    "It works on my machine.",
    "The compiler is not your enemy. It is the only colleague who always reads your code.",
    "Weeks of coding can save you hours of planning.",
    "A comment that repeats the code is noise. A comment that explains the reason is gold.",
    "If you cannot explain the bug to a rubber duck, you do not understand the bug yet.",
    "Off-by-one errors are the second most common bug. The first is off-by-one errors.",
    "Hardware fails, networks drop, disks fill up. Write the code for Tuesday, not for the demo.",
    "Do not trust input. Not even your own, three weeks from now.",
    "Zero is a number, empty is a value, and null is a problem.",
    "The cache is hot, the logs are cold, and the bug is somewhere in between.",
    "Every global variable is a promise that nobody will ever change it. Somebody will.",
    "Tabs or spaces? Whichever the file already uses.",
    "Naming is design. If the name is hard, the idea is not clear yet.",
    "When the build fails at 5 pm, it is never the last change. It is the one before.",
    "Delete the clever line. Write the obvious two.",
    "Make the common case fast and the rare case correct.",
    "A good test fails for exactly one reason.",
    "The second system is the most dangerous one you will ever design.",
    "Reboot is not a fix. It is a postponement with a good reputation.",
    "RTFM: the manual was written by someone who also hit that wall.",
    "An embedded program has no time to be elegant, only to be on time.",
    "A watchdog is the gentlest way a machine can say: I do not believe you.",
    "Interrupts should be short, like good news and bad apologies.",
    "Floating point numbers are approximate. So are deadlines.",
    "A pull-up resistor is a small, cheap act of optimism.",
    "The logic analyzer knows what happened. The oscilloscope knows why.",
    "Volatile does not mean faster. It means: I do not trust you.",
    "Voltage is opinion. Current is fact.",
    "Compile with warnings on. They are free reviews.",
  },
  linux = {
    "In Unix, everything is a file, except the things that are processes, and the things that are sockets.",
    "Write programs that do one thing and do it well. Write programs to work together.|Doug McIlroy",
    "Those who don't understand Unix are condemned to reinvent it, poorly.|Henry Spencer",
    "Real programmers use cat > file.",
    "rm -rf is forever. Think, then press Enter.",
    "The man page is short. The answer is in the third paragraph, under OPTIONS.",
    "sudo: with great power comes great typing of your password.",
    "There is no place like 127.0.0.1.",
    "Pipes are the duct tape of civilization.",
    "grep is a tool. awk is a language. sed is a mood.",
    "If it has a manual page, it can be fixed. If it has an info page, it can be explained.",
    "A shell script that works is a shell script that has not met a filename with a space in it.",
    "chmod 777 is not a solution. It is a cry for help.",
    "Always quote your variables. Always.",
    "The kernel panics so you do not have to.",
    "ls is the first command you type and the last you understand.",
    "tail -f is the closest thing an administrator has to television.",
    "Backups are like parachutes: you only need them once, and then you really need them.",
    "Read the logs. They are the only honest part of the system.",
    "Everything is a file. Even the file you are looking for.",
    "A daemon is just a process with a good excuse.",
    "kill -9 is not a signal. It is a verdict.",
    "The cron job that is not logged is the one that fails.",
    "Segmentation fault (core dumped): the computer's way of telling you that it, too, is lost.",
    "Permission denied is the shortest sentence in the Unix language.",
    "A good command line is a conversation. A bad one is a monologue with no end.",
    "cd .. is the most useful two-word phrase in the shell.",
    "ssh: because the data center is always farther than it looks.",
    "If the filesystem is full, delete the logs. If the logs are the problem, delete the filesystem.",
    "A package manager is a promise that dependencies are somebody else's problem.",
    "Arch users will tell you they use Arch. The package list will tell you the rest.",
    "yes is the simplest program that never stops being useful.",
    "pacman -Syu on a Friday evening is a decision, not a habit.",
    "An init system is just a polite way to start a lot of things at the same time.",
    "To iterate is human, to recurse divine.|L. Peter Deutsch",
    "The beauty of Unix is that you can combine small tools into something nobody planned.",
    "The shell is a very fast way to be very wrong.",
    "Mount it read-only first. You will thank yourself.",
    "The best configuration file is the one you never had to open.",
    "A Linux box that has been up for 400 days is not stable. It is untested.",
    "Do not pipe curl into sh. At least read it first. Then pipe it into sh.",
  },
  wisdom = {
    "A journey of a thousand miles begins with a single step.|Lao Tzu",
    "Early to bed and early to rise makes a man healthy, wealthy and wise.|Benjamin Franklin",
    "Well done is better than well said.|Benjamin Franklin",
    "An investment in knowledge pays the best interest.|Benjamin Franklin",
    "We must all hang together, or assuredly we shall all hang separately.|Benjamin Franklin",
    "The unexamined life is not worth living.|Socrates",
    "I think, therefore I am.|Rene Descartes",
    "Fall seven times, stand up eight.|Japanese proverb",
    "A watched pot never boils.",
    "Measure twice, cut once.",
    "Know thyself.|inscription at Delphi",
    "It does not matter how slowly you go as long as you do not stop.|Confucius",
    "He who knows that enough is enough will always have enough.|Lao Tzu",
    "Knowing others is intelligence; knowing yourself is true wisdom.|Lao Tzu",
    "You have power over your mind, not outside events. Realize this, and you will find strength.|Marcus Aurelius",
    "The happiness of your life depends upon the quality of your thoughts.|Marcus Aurelius",
    "Waste no more time arguing about what a good man should be. Be one.|Marcus Aurelius",
    "We suffer more often in imagination than in reality.|Seneca",
    "It is not that we have a short time to live, but that we waste a lot of it.|Seneca",
    "No man ever steps in the same river twice, for it is not the same river and he is not the same man.|Heraclitus",
    "Well begun is half done.|Aristotle",
    "The man who moves a mountain begins by carrying away small stones.|Confucius",
    "Lost time is never found again.|Benjamin Franklin",
    "God helps them that help themselves.|Benjamin Franklin",
    "Never leave that till tomorrow which you can do today.|Benjamin Franklin",
    "Tell me and I forget. Teach me and I remember. Involve me and I learn.|Benjamin Franklin",
    "A smooth sea never made a skilled sailor.|English proverb",
    "Rome was not built in a day.",
    "A rolling stone gathers no moss.",
    "Look before you leap.",
    "Do not count your chickens before they hatch.",
    "Many hands make light work.",
    "Practice makes perfect.",
    "A stitch in time saves nine.",
    "Actions speak louder than words.",
    "All that glitters is not gold.|William Shakespeare",
    "To thine own self be true.|William Shakespeare",
    "The better part of valour is discretion.|William Shakespeare",
    "Brevity is the soul of wit.|William Shakespeare",
    "Better three hours too soon than a minute too late.|William Shakespeare",
    "If at first you don't succeed, try again. Then quit. There's no use being a damn fool about it.|W. C. Fields",
    "Never put off until tomorrow what you can avoid altogether.",
    "The early bird gets the worm, but the second mouse gets the cheese.",
    "Good, fast, cheap: pick any two.",
    "If it ain't broke, don't fix it.",
    "Take a walk. The problem will still be there, and so will you, refreshed.",
    "Be kind. Everyone you meet is fighting a harder battle than you know.",
    "Sleep on it. Decisions look different at 7 am.",
    "The quiet person in the room has usually noticed something.",
    "Do the hard thing first; the rest of the day will feel like a holiday.",
    "Courage is resistance to fear, mastery of fear, not absence of fear.|Mark Twain",
    "The best revenge is to be unlike him who performed the injury.|Marcus Aurelius",
    "Fortune favours the bold.|Latin proverb",
    "Carpe diem.|Horace",
    "Vita brevis, ars longa.|Hippocrates",
  },
  science = {
    "The first principle is that you must not fool yourself, and you are the easiest person to fool.|Richard P. Feynman",
    "If I have seen further it is by standing on the shoulders of giants.|Isaac Newton",
    "Nothing in life is to be feared, it is only to be understood.|Marie Curie",
    "The important thing is not to stop questioning.|Albert Einstein",
    "Imagination is more important than knowledge.|Albert Einstein",
    "The most incomprehensible thing about the universe is that it is comprehensible.|Albert Einstein",
    "Somewhere, something incredible is waiting to be known.|Carl Sagan",
    "If you wish to make an apple pie from scratch, you must first invent the universe.|Carl Sagan",
    "What I cannot create, I do not understand.|Richard P. Feynman",
    "An expert is a person who has made all the mistakes that can be made in a very narrow field.|Niels Bohr",
    "Prediction is very difficult, especially if it's about the future.|Niels Bohr",
    "Chance favours only the prepared mind.|Louis Pasteur",
    "Mathematics is the language in which God has written the universe.|Galileo Galilei",
    "And yet it moves.|Galileo Galilei",
    "A hypothesis is a guess. An experiment is the question you ask of it.",
    "The speed of light is the speed limit of the universe, and the speed of the bus is the speed limit of Tuesday.",
    "Entropy: the reason your desk, your cables and your code get worse unless you do something.",
    "A theory is not true because it is beautiful. It is beautiful because it survived the data.",
    "Every measurement has an error. The honest ones say how big.",
    "Correlation is not causation, but it is a very good reason to look.",
    "Gravity is a habit. The orbit is the lazy way of keeping it.",
    "Absence of evidence is not evidence of absence, but it is a reason to look harder.",
    "The plural of anecdote is not data.",
    "A good experiment answers one question. A great one raises the next.",
    "Nature does not hurry, yet everything is accomplished.|Lao Tzu",
    "Two wrongs don't make a right, but three lefts do.",
    "Seeing is believing; measuring is knowing.",
    "A calibrated instrument beats a confident guess.",
    "The lab notebook is the only witness that does not forget.",
    "In theory there is no difference between theory and practice. In practice there is.|attributed to Yogi Berra",
  },
  humorists = {
    "Anything that can go wrong will go wrong.|Murphy's law",
    "Whatever you want to do, you need to do something else first.|Murphy's corollary",
    "Nothing is as easy as it looks.|Murphy's corollary",
    "Everything takes longer than you think.|Murphy's corollary",
    "Hofstadter's law: it always takes longer than you expect, even when you take into account Hofstadter's law.",
    "The light at the end of the tunnel is usually a train.",
    "I can resist everything except temptation.|Oscar Wilde",
    "Always forgive your enemies; nothing annoys them so much.|Oscar Wilde",
    "Experience is simply the name we give our mistakes.|Oscar Wilde",
    "Get your facts first, and then you can distort them as you please.|Mark Twain",
    "The secret of getting ahead is getting started.|Mark Twain",
    "The reports of my death are greatly exaggerated.|Mark Twain",
    "I have never let my schooling interfere with my education.|Mark Twain",
    "When in doubt, tell the truth.|Mark Twain",
    "Always do right. This will gratify some people and astonish the rest.|Mark Twain",
    "A man who carries a cat by the tail learns something he can learn in no other way.|Mark Twain",
    "Whenever you find yourself on the side of the majority, it is time to pause and reflect.|Mark Twain",
    "He who laughs last has not yet heard the bad news.",
    "Nothing is impossible for the man who does not have to do it himself.",
    "The meeting could have been an email. The email could have been silence.",
    "If you want to make God laugh, tell him your plans.|Woody Allen",
    "Procrastination is the art of keeping up with yesterday.|Don Marquis",
    "A clear conscience is usually the sign of a bad memory.|Steven Wright",
    "Cheer up, the worst is yet to come.|Philander Johnson",
    "If at first you don't succeed, skydiving is not for you.",
    "I'm not lazy, I'm on energy-saving mode.",
    "Coffee: because the sunrise is not a good enough reason.",
    "The probability of a thing going wrong is directly proportional to how much you need it to work.",
    "Good judgment comes from experience, and experience comes from bad judgment.|Rita Mae Brown",
    "Success is going from failure to failure without losing enthusiasm.|Winston Churchill",
    "I have not failed. I've just found 10,000 ways that won't work.|Thomas Edison",
    "The cat sat on the mat, and the mat never recovered.",
    "A diplomat is a man who always remembers a woman's birthday but never her age.|Robert Frost",
    "Hard work pays off eventually, but laziness pays off right now.",
    "It's not a bug, it's an undocumented feature.",
    "The nice thing about standards is that there are so many of them to choose from.|Andrew S. Tanenbaum",
    "I always pass on good advice. It is the only thing to do with it. It is never any use to oneself.|Oscar Wilde",
    "Better to remain silent and be thought a fool than to speak and remove all doubt.|attributed to Abraham Lincoln",
  },
  literature = {
    "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.|Jane Austen",
    "Call me Ishmael.|Herman Melville",
    "All happy families are alike; each unhappy family is unhappy in its own way.|Leo Tolstoy",
    "It was the best of times, it was the worst of times.|Charles Dickens",
    "To be, or not to be, that is the question.|William Shakespeare",
    "All the world's a stage, and all the men and women merely players.|William Shakespeare",
    "Some are born great, some achieve greatness, and some have greatness thrust upon them.|William Shakespeare",
    "Hope is the thing with feathers that perches in the soul.|Emily Dickinson",
    "I wandered lonely as a cloud.|William Wordsworth",
    "Not all those who wander are lost.|J. R. R. Tolkien",
    "Curiouser and curiouser!|Lewis Carroll",
    "The road to hell is paved with good intentions.|proverb",
    "Whatever you do, do it with all your heart.|proverb",
    "A room without books is like a body without a soul.|Marcus Tullius Cicero",
    "Reading maketh a full man; conference a ready man; and writing an exact man.|Francis Bacon",
    "Knowledge is power.|Francis Bacon",
    "The pen is mightier than the sword.|Edward Bulwer-Lytton",
    "Life is what happens while you are busy making other plans.|John Lennon",
    "If you can keep your head when all about you are losing theirs, you'll be a man, my son.|Rudyard Kipling",
    "Tomorrow, and tomorrow, and tomorrow, creeps in this petty pace from day to day.|William Shakespeare",
    "There is no frigate like a book to take us lands away.|Emily Dickinson",
    "Festina lente: make haste slowly.|Augustus",
    "The course of true love never did run smooth.|William Shakespeare",
    "Though she be but little, she is fierce.|William Shakespeare",
    "Cowards die many times before their deaths; the valiant never taste of death but once.|William Shakespeare",
    "I took the one less traveled by, and that has made all the difference.|Robert Frost",
    "Do I contradict myself? Very well then I contradict myself.|Walt Whitman",
    "The only way to get rid of a temptation is to yield to it.|Oscar Wilde",
    "Some books are to be tasted, others to be swallowed, and some few to be chewed and digested.|Francis Bacon",
    "We are such stuff as dreams are made on.|William Shakespeare",
  },
}

local ORDER = { "computers", "humorists", "linux", "literature", "science", "wisdom" }

-- every fortune: { text, category }
local ALL = {}
local COUNT = {}
for _, name in ipairs(ORDER) do
  COUNT[name] = #CATS[name]
  for _, line in ipairs(CATS[name]) do
    local text, author = line:match("^(.-)|(.*)$")
    if text then line = text .. "\n\t\t-- " .. author end
    ALL[#ALL + 1] = { text = line, cat = name }
  end
end

-- options
local only, short, long, equal, minLen, showFile, pattern, ignoreCase, offensive = false, false, false, false, 160, false, nil, false, false
local files = {}
local i = 1
local function bad(msg)
  io.stderr:write(msg .. "\n")
  io.stderr:write(USAGE .. "\n")
  os.exit(1)
end
while arg[i] do
  local a = arg[i]
  if a:sub(1, 1) == "-" and #a > 1 then
    local j = 2
    while j <= #a do
      local o = a:sub(j, j)
      if o == "s" then short = true
      elseif o == "l" then long = true
      elseif o == "a" then offensive = false
      elseif o == "o" then offensive = true
      elseif o == "e" then equal = true
      elseif o == "i" then ignoreCase = true
      elseif o == "w" then
        -- wait after the fortune: nothing to wait for here
      elseif o == "c" then showFile = true
      elseif o == "f" then only = true
      elseif o == "n" or o == "m" then
        local val = a:sub(j + 1)
        if val == "" then
          i = i + 1
          val = arg[i]
        end
        if not val then bad("fortune: option requires an argument -- '" .. o .. "'") end
        if o == "n" then
          minLen = tonumber(val)
          if not minLen then
            io.stderr:write("fortune: invalid number: " .. val .. "\n")
            os.exit(1)
          end
        else pattern = val end
        j = #a
      else
        bad("fortune: invalid option -- '" .. o .. "'")
      end
      j = j + 1
    end
  else
    files[#files + 1] = a
  end
  i = i + 1
end

-- the files named on the command line: [N%] name ... ; "all" or none means everything
local want = nil   -- cat -> true or a percentage (nil = all)
do
  local pct
  for _, f in ipairs(files) do
    local n = f:match("^(%d+)%%$")
    if n then pct = tonumber(n)
    else
      local name = f:gsub("^/usr/share/fortune/?", ""):gsub("/$", "")
      if name ~= "all" and name ~= "" and name ~= "fortunes" then
        if not CATS[name] then
          io.stderr:write(f .. " not a fortune file or directory\n")
          os.exit(1)
        end
        want = want or {}
        want[name] = pct or true
      end
      pct = nil
    end
  end
end

if only then
  -- the list of files with their share of the fortunes (fortune-mod writes it to stderr)
  io.stderr:write(string.format("%6.2f%% %s\n", 100, "/usr/share/fortune"))
  if not offensive then
    local names, sum = {}, 0
    for _, name in ipairs(ORDER) do
      if not want or want[name] then
        names[#names + 1] = name
        sum = sum + (equal and 1 or COUNT[name])
      end
    end
    for _, name in ipairs(names) do
      io.stderr:write(string.format("     %6.2f%% %s\n", (equal and 1 or COUNT[name]) * 100 / sum, name))
    end
  end
  return
end

if offensive then
  io.stderr:write("No fortunes found\n")
  os.exit(1)
end

local pool = {}
local function matches(t)
  if not pattern then return true end
  if ignoreCase then return t.text:lower():find(pattern:lower(), 1, true) ~= nil end
  return t.text:find(pattern, 1, true) ~= nil
end
for _, t in ipairs(ALL) do
  local isShort = #t.text < minLen
  if (not want or want[t.cat])
     and (not short and not long or (short and isShort) or (long and not isShort))
     and matches(t) then
    pool[#pool + 1] = t
  end
end
if #pool == 0 then
  io.stderr:write("No fortunes found\n")
  os.exit(1)
end

local function show(t)
  -- the screen is 57 columns wide: wrap the saying, keep the author line as it is
  local body, rest = t.text:match("^(.-)(\n.*)$")
  body = body or t.text
  local cur = ""
  for word in body:gmatch("%S+") do
    if cur == "" then cur = word
    elseif #cur + 1 + #word <= 56 then cur = cur .. " " .. word
    else print(cur); cur = word end
  end
  if cur ~= "" then print(cur) end
  if rest then print((rest:gsub("^\n", ""))) end
end

if pattern then
  -- -m: every fortune that matches; the file name of each group goes to stderr
  local last
  for _, t in ipairs(pool) do
    if t.cat ~= last then
      io.stderr:write("(" .. t.cat .. ")\n%\n")
      last = t.cat
    end
    show(t)
    print("%")
  end
  return
end

math.randomseed(sys.millis and sys.millis() or os.time())
local pick
if equal then
  -- -e: every file has the same chance, whatever its size
  local byCat, names = {}, {}
  for _, t in ipairs(pool) do
    if not byCat[t.cat] then byCat[t.cat] = {}; names[#names + 1] = t.cat end
    table.insert(byCat[t.cat], t)
  end
  local c = byCat[names[math.random(#names)]]
  pick = c[math.random(#c)]
else
  -- "N% name": that file gets N percent of the draws, the others share the rest by size
  local r, acc, chosen = math.random() * 100, 0, nil
  if want then
    for _, name in ipairs(ORDER) do
      if type(want[name]) == "number" then
        acc = acc + want[name]
        if r < acc and not chosen then chosen = name end
      end
    end
  end
  local sub = {}
  for _, t in ipairs(pool) do
    if (chosen and t.cat == chosen) or (not chosen and (not want or type(want[t.cat]) ~= "number" or acc == 0)) then sub[#sub + 1] = t end
  end
  if #sub == 0 then sub = pool end
  pick = sub[math.random(#sub)]
end
if showFile then print("(" .. pick.cat .. ")") print("%") end
show(pick)
