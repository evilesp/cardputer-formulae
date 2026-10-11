#!lua
-- server: a web page on the Cardputer for a phone or a laptop on the same WiFi. It has a terminal (the shell commands),
-- the files of the SD card (download and upload) and the state of the device: memory, CPU, battery, SD card, WiFi.
-- Needs firmware v0.1.0.10(beta) or newer.
--   server PORT [NAME]    the page is at http://IP:PORT; with NAME (for example cardputer) also at http://NAME.local:PORT
-- There is no password: anyone on the same WiFi can open the page and run commands. Do not forward the port to the
-- internet. A command from the page stops after 20 seconds; a program that needs the keyboard stops at once.
-- The page sends the header X-Cardputer: 1 with its changes, and a request must name the Cardputer (its address or its
-- name). A page of another site cannot send either, so it cannot run a command here.
-- q on the Cardputer stops the server.

local PAGE = [==[
<!doctype html>
<html lang="pl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cardputer</title>
<style>
:root { color-scheme: dark; }
* { box-sizing: border-box; }
body { margin: 0; font-family: system-ui, -apple-system, sans-serif; background: #111; color: #ddd; font-size: 16px; }
header { background: #1b1b1b; padding: 10px 12px; display: flex; flex-wrap: wrap; gap: 8px; align-items: center; border-bottom: 1px solid #2a2a2a; }
header b { color: #7fd17f; margin-right: auto; }
nav button { background: #272727; color: #ddd; border: 1px solid #444; border-radius: 8px; padding: 8px 12px; font-size: 15px; }
nav button.on { background: #2f5f2f; border-color: #58a058; color: #fff; }
main { padding: 12px; max-width: 900px; margin: 0 auto; }
section { display: none; }
section.on { display: block; }
pre { font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 13px; line-height: 1.35; white-space: pre-wrap; word-break: break-word; background: #0a0a0a; border: 1px solid #333; border-radius: 8px; padding: 10px; min-height: 260px; max-height: 60vh; overflow: auto; margin: 0; }
.row { display: flex; gap: 8px; margin-top: 10px; align-items: center; flex-wrap: wrap; }
input[type=text] { flex: 1; min-width: 0; background: #0a0a0a; color: #eee; border: 1px solid #444; border-radius: 8px; padding: 10px; font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 15px; }
button.act { background: #2f5f2f; color: #fff; border: 0; border-radius: 8px; padding: 10px 14px; font-size: 15px; }
button.act:disabled { opacity: .5; }
.muted { color: #888; font-size: 13px; line-height: 1.4; }
table { border-collapse: collapse; width: 100%; }
td { padding: 8px 4px; border-bottom: 1px solid #2a2a2a; vertical-align: top; }
td:first-child { color: #9a9a9a; width: 40%; }
.bar { height: 8px; background: #2a2a2a; border-radius: 4px; overflow: hidden; margin-top: 5px; }
.bar > i { display: block; height: 100%; background: #6cb36c; }
ul.files { list-style: none; padding: 0; margin: 10px 0; }
ul.files li { padding: 10px 2px; border-bottom: 1px solid #2a2a2a; display: flex; gap: 10px; align-items: center; }
ul.files .name { flex: 1; min-width: 0; word-break: break-word; }
ul.files a { color: #9fd0ff; text-decoration: none; }
ul.files .dir { color: #f0d080; cursor: pointer; }
</style>
</head>
<body>
<header>
  <b>Cardputer</b>
  <nav>
    <button data-tab="term" class="on">Terminal</button>
    <button data-tab="files">Pliki</button>
    <button data-tab="info">Sprz&#281;t</button>
  </nav>
</header>
<main>
  <section id="term" class="on">
    <pre id="out"></pre>
    <div class="row">
      <input id="cmd" type="text" placeholder="np. ls, df, uptime" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false">
      <button class="act" id="run">Wy&#347;lij</button>
    </div>
    <p class="muted">To terminal Cardputera. Polecenia, kt&#243;re wymagaj&#261; klawiatury (nano, snake, htop), zatrzymuj&#261; si&#281; od razu. Ka&#380;de polecenie dzia&#322;a najwy&#380;ej 20 sekund. Strza&#322;ki w g&#243;r&#281; i w d&#243;&#322; przewijaj&#261; histori&#281;.</p>
  </section>
  <section id="files">
    <div class="row">
      <b id="cwd" style="flex:1; word-break: break-all"></b>
      <button class="plain" id="up">W g&#243;r&#281;</button>
    </div>
    <ul class="files" id="list"></ul>
    <div class="row">
      <input id="pick" type="file">
      <button class="act" id="send">Wy&#347;lij na kart&#281;</button>
    </div>
    <p class="muted" id="fmsg"></p>
  </section>
  <section id="info">
    <table id="stats"></table>
  </section>
</main>
<script>
(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var cwd = '/home/user';
  var hist = [], hpos = 0;

  // ---- tabs
  var buttons = document.querySelectorAll('nav button');
  function show(name) {
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].className = buttons[i].getAttribute('data-tab') === name ? 'on' : '';
    }
    var secs = document.querySelectorAll('main section');
    for (var j = 0; j < secs.length; j++) {
      secs[j].className = secs[j].id === name ? 'on' : '';
    }
    if (name === 'files') listDir(cwd);
    if (name === 'info') refreshInfo();
    if (name === 'term') $('cmd').focus();
  }
  for (var k = 0; k < buttons.length; k++) {
    buttons[k].onclick = function () { show(this.getAttribute('data-tab')); };
  }

  // ---- terminal
  function say(text) {
    var out = $('out');
    out.textContent += text;
    out.scrollTop = out.scrollHeight;
  }
  function run() {
    var line = $('cmd').value;
    if (!line.trim()) return;
    hist.push(line);
    hpos = hist.length;
    $('cmd').value = '';
    say('$ ' + line + '\n');
    $('run').disabled = true;
    fetch('/api/exec', { method: 'POST', body: line, headers: { 'X-Cardputer': '1' } })
      .then(function (r) {
        var code = r.headers.get('X-Exit') || '0';
        return r.text().then(function (t) {
          if (t && t.charAt(t.length - 1) !== '\n') t += '\n';
          say(t);
          if (code !== '0') say('[exit ' + code + ']\n');
        });
      })
      .catch(function (e) { say('blad: ' + e.message + '\n'); })
      .then(function () { $('run').disabled = false; $('cmd').focus(); });
  }
  $('run').onclick = run;
  $('cmd').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') {
      e.preventDefault();
      run();
    } else if (e.key === 'ArrowUp') {
      if (hpos > 0) { hpos--; this.value = hist[hpos]; }
      e.preventDefault();
    } else if (e.key === 'ArrowDown') {
      if (hpos < hist.length) { hpos++; this.value = hpos < hist.length ? hist[hpos] : ''; }
      e.preventDefault();
    }
  });

  // ---- files
  function parent(p) {
    if (p === '/' || p === '') return '/';
    var i = p.lastIndexOf('/');
    return i <= 0 ? '/' : p.substring(0, i);
  }
  function size(n) {
    if (n < 1024) return n + ' B';
    if (n < 1048576) return (n / 1024).toFixed(1) + ' KB';
    return (n / 1048576).toFixed(2) + ' MB';
  }
  function listDir(p) {
    cwd = p;
    $('cwd').textContent = p;
    var ul = $('list');
    ul.innerHTML = '';
    fetch('/api/list?path=' + encodeURIComponent(p))
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (j) {
        if (!j.entries.length) {
          var empty = document.createElement('li');
          empty.className = 'muted';
          empty.textContent = 'pusty katalog';
          ul.appendChild(empty);
        }
        j.entries.forEach(function (e) {
          var full = (p === '/' ? '' : p) + '/' + e.name;
          var li = document.createElement('li');
          var name = document.createElement('span');
          name.className = 'name';
          if (e.dir) {
            name.className += ' dir';
            name.textContent = e.name + '/';
            name.onclick = function () { $('fmsg').textContent = ''; listDir(full); };
            li.appendChild(name);
          } else {
            var a = document.createElement('a');
            a.href = '/api/file?path=' + encodeURIComponent(full);
            a.setAttribute('download', e.name);
            a.textContent = e.name;
            name.appendChild(a);
            li.appendChild(name);
            var s = document.createElement('span');
            s.className = 'muted';
            s.textContent = size(e.size);
            li.appendChild(s);
          }
          ul.appendChild(li);
        });
      })
      .catch(function (err) {
        $('fmsg').textContent = 'Nie mog\u0119 odczyta\u0107 katalogu: ' + err.message;
      });
  }
  $('up').onclick = function () { $('fmsg').textContent = ''; listDir(parent(cwd)); };
  $('send').onclick = function () {
    var f = $('pick').files[0];
    if (!f) {
      $('fmsg').textContent = 'Najpierw wybierz plik.';
      return;
    }
    upload(f, false);
  };
  function upload(f, overwrite) {
    var target = (cwd === '/' ? '' : cwd) + '/' + f.name;
    $('fmsg').textContent = 'Wysy\u0142anie ' + f.name + ' (' + size(f.size) + ')...';
    fetch('/api/upload?path=' + encodeURIComponent(target) + (overwrite ? '&overwrite=1' : ''),
          { method: 'POST', body: f, headers: { 'X-Cardputer': '1' } })
      .then(function (r) {
        if (r.status === 409 && !overwrite) {
          if (confirm('Plik ' + f.name + ' ju\u017c istnieje. Nadpisa\u0107?')) return upload(f, true);
          $('fmsg').textContent = 'Nie wys\u0142ano.';
          return null;
        }
        return r.text().then(function (t) {
          $('fmsg').textContent = (r.ok ? '' : 'B\u0142\u0105d: ') + t.trim();
          if (r.ok) listDir(cwd);
        });
      })
      .catch(function (err) { $('fmsg').textContent = 'B\u0142\u0105d: ' + err.message; });
  }

  // ---- info
  function row(label, value, pct) {
    var tr = document.createElement('tr');
    var a = document.createElement('td');
    a.textContent = label;
    var b = document.createElement('td');
    b.textContent = value;
    if (pct !== null && pct !== undefined && !isNaN(pct)) {
      var bar = document.createElement('div');
      bar.className = 'bar';
      var i = document.createElement('i');
      i.style.width = Math.max(0, Math.min(100, pct)) + '%';
      bar.appendChild(i);
      b.appendChild(bar);
    }
    tr.appendChild(a);
    tr.appendChild(b);
    return tr;
  }
  function fmtUptime(s) {
    var d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
    return (d ? d + ' d ' : '') + h + ' h ' + m + ' min';
  }
  function renderInfo(j) {
    var t = $('stats');
    t.innerHTML = '';
    var c = j.cpu, mem = j.memory, bat = j.battery, sd = j.sd, w = j.wifi;
    t.appendChild(row('Urz\u0105dzenie', j.host + ' (' + j.board + ')'));
    t.appendChild(row('Wersja', j.version));
    t.appendChild(row('Czas dzia\u0142ania', fmtUptime(j.uptime)));
    if (j.time) t.appendChild(row('Data i godzina', j.time));
    t.appendChild(row('Procesor', c.model + ', ' + c.cores + ' rdzenie, ' + c.mhz + ' MHz'));
    t.appendChild(row('Obci\u0105\u017cenie CPU', c.load === null ? 'brak danych' : Math.round(c.load) + ' %', c.load));
    if (c.temp_c !== null) t.appendChild(row('Temperatura chipu', Math.round(c.temp_c) + ' \u00b0C'));
    var used = mem.total_kb - mem.free_kb;
    t.appendChild(row('Pami\u0119\u0107 RAM', used + ' / ' + mem.total_kb + ' KB zaj\u0119te', used * 100 / mem.total_kb));
    t.appendChild(row('Najwi\u0119kszy wolny blok', mem.largest_kb + ' KB'));
    if (bat.percent < 0) {
      t.appendChild(row('Bateria', 'brak danych'));
    } else {
      t.appendChild(row('Bateria', bat.percent + ' % (' + (bat.mv / 1000).toFixed(2) + ' V)' +
        (bat.charging ? ', \u0142aduje' : ''), bat.percent));
    }
    if (sd) {
      t.appendChild(row('Karta SD', (sd.used_kb / 1024).toFixed(1) + ' / ' + (sd.total_kb / 1024).toFixed(0) + ' MB',
        sd.total_kb ? sd.used_kb * 100 / sd.total_kb : null));
    }
    t.appendChild(row('WiFi', w.connected ?
      (w.ssid + ' (' + w.ip + ')' + (w.rssi !== null ? ', ' + w.rssi + ' dBm' : '')) :
      'brak po\u0142\u0105czenia'));
    if (j.accel) t.appendChild(row('Czujnik ruchu (g)', j.accel.join(', ')));
    t.appendChild(row('Odczyt', new Date().toLocaleTimeString()));
  }
  function refreshInfo() {
    fetch('/api/info')
      .then(function (r) { return r.json(); })
      .then(renderInfo)
      .catch(function () {});
  }
  setInterval(function () {
    if ($('info').className === 'on') refreshInfo();
  }, 2000);

  $('cmd').focus();
})();
</script>
</body>
</html>
]==]

if not httpd then
  print("server: this firmware has no web server, update to v0.1.0.10(beta) or newer")
  return
end

local port = (#arg == 1 or #arg == 2) and tonumber(arg[1]) or nil
if not port or port ~= math.floor(port) or port < 1 or port > 65535 then
  print("usage: server PORT [NAME]   e.g. server 8080 cardputer")
  return
end
local name = arg[2] or ""

local url, nameUrl = httpd.start(math.floor(port), name, PAGE)
if not url then
  print("server: " .. tostring(nameUrl))
  return
end

local COLS, ROWS = term.size()

local function draw(count)
  term.clear()
  term.text(0, 0, "server running", "green")
  term.text(0, 2, url:sub(1, COLS), "white")
  if nameUrl then term.text(0, 3, nameUrl:sub(1, COLS), "white") end
  term.text(0, 5, "requests: " .. count, "text")
  term.text(0, 7, "no password: anyone on this WiFi", "warn")
  term.text(0, 8, "can open the page and run commands", "warn")
  term.text(0, ROWS - 1, "q quits the server", "dim")
  term.flush()
end

-- the loop answers the requests and reads the keys; the screen is drawn again when the request count changes
local function loop()
  local shown = -1
  while true do
    httpd.poll()
    local k = key.poll()
    while k do
      if k == "q" then return end
      k = key.poll()
    end
    local n = httpd.requests()
    if n ~= shown then
      draw(n)
      shown = n
    else
      term.flush()
    end
    sys.sleep(20)
  end
end

term.fullscreen(true)
local ok, err = pcall(loop)
httpd.stop()  -- also after Ctrl+C, which stops the loop with an error
term.fullscreen(false)
if not ok and not tostring(err):find("interrupted", 1, true) then
  print("server: " .. tostring(err))
end
