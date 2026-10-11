# cardputer-formulae

Pakiety do menedżera `brew` na Cardputer Linux (M5Stack Cardputer ADV).
Każda formuła to program w Lua, który uruchamia się na urządzeniu.

## Użycie na Cardputerze

```bash
brew tap https://raw.githubusercontent.com/evilesp/cardputer-formulae/main
brew update
brew search
brew install htop nano snake
```

## Pakiety

| Nazwa | Opis |
|---|---|
| cmatrix | spadające znaki (q = wyjście) |
| fastfetch | podsumowanie urządzenia z logo |
| asciiquarium | akwarium (q = wyjście) |
| speedtest-cli | ping, pobieranie i wysyłanie |
| htop | pamięć, bateria, SD, WiFi, zużycie CPU zadań |
| nano | edytor plików na karcie (Ctrl+S, Ctrl+X) |
| snake | wąż (strzałki lub w a s d) |
| pong | pong przeciwko komputerowi |
| tetris | klocki (spacja upuszcza) |
| cowsay | krowa mówi, co podasz |
| fortune | losowa rada |
| cal | kalendarz miesiąca |
| calc | kalkulator wyrażeń |
| hexdump | plik w hex i tekście |
| httping | czas odpowiedzi HTTP |
| pinmon | stan pinów GPIO na żywo |
| figlet | duże litery z `#` |
| sl | parowóz przez ekran |
| lolcat | tekst w tęczowych kolorach |
| less | czytanie pliku po ekranie |
| clock | duży zegar cyfrowy |
| hangman | wisielec |
| base64 | kodowanie i dekodowanie base64 |
| uuidgen | losowy UUID |
| shasum | SHA-256 pliku lub tekstu |
| duckduckgo | przeglądarka tekstowa z wyszukiwarką DuckDuckGo |
| remote | piloty podczerwieni: nauka przycisków, nazwy, wysyłanie po kolei (wymaga v0.1.0.11) |
| softspi | SPI programowe na dowolnych pinach (sterownik) |
| mcp3008 | przetwornik ADC MCP3008, 8 wejść, 10 bitów (sterownik) |
| adcview | 8 wejść MCP3008 na ekranie: adcview SCK MOSI MISO CS [VREF] |
| life | Gra w życie Conwaya na ekranie (q = wyjście) |
| simon | gra pamięciowa z dźwiękiem: powtarzaj sekwencję klawiszy a s d f |
| dino | biegnący dinozaur: spacja skacze nad kaktusami |
| mandelbrot | zbiór Mandelbrota w znakach, z przybliżaniem (+ i -) |
| typetest | test szybkości i dokładności pisania (wpm, procenty) |
| timer | odliczanie dużymi cyframi: timer 25m, timer 90 |
| todo | lista zadań na karcie SD |
| passgen | losowe hasła: passgen 20 -s |
| iss | gdzie jest Międzynarodowa Stacja Kosmiczna (potrzebny WiFi) |
| rtc | zegar DS3231 na I2C: odczyt, ustawianie, synchronizacja |
| doom | Doom-podobna strzelanka z grafiką pikselową (wersja 0.1.1.2): chodzenie, strzelanie, wrogowie, apteczki, minimapa; idziesz, dopóki trzymasz w s a d , / q e (puszczasz – stajesz); wymaga firmware v0.1.0.14; `brew install doom` sam dopyta o brakujące części (doomgame, doomdraw, doomlevel) |
| doomgame | zasady gry, potwory, pętla gry i ruch dla doom (driver) |
| doomdraw | rysowanie obrazu i menu dla doom (driver) |
| doomlevel | poziom i geometria dla doom (driver) |
| memcleaner | sprzątanie karty SD: puste pliki, kopie, cache, pliki tymczasowe, nieskończone pobrania i bardzo stare pliki; pyta o każdy plik (y usuwa, n zostawia, s pomija resztę); wymaga firmware v0.1.0.14 |
| invaders | Space Invaders w pikselach (a d, f strzela) |
| breakout | cegiełki i piłeczka |
| flappy | ptak lecący między rurami |
| game2048 | układanka 2048 klawiszami w a s d |
| maze | losowy labirynt z podpowiedzią |
| sudoku | sudoku ze sprawdzaniem |
| chess | szachy z prostym komputerem (bez roszady i bicia w przelocie) |
| paint | rysowanie na ekranie i zapis na karcie |
| screensaver | wygaszacz: gwiazdy, deszcz, lampa lava |
| filer | menedżer plików na karcie SD (bez kasowania) |
| notes | notatki z prostym edytorem |
| music | odtwarzacz plików WAV i AIFF z folderu |
| plot | wykres z pliku tekstowego lub CSV |
| sensors | wykresy akcelerometru, żyroskopu i baterii na żywo; każdy odczyt zapisuje się na karcie SD (/home/user/sensors.csv); wymaga firmware v0.1.0.15 |
| analogclock | zegar analogowy z datą |
| metronome | metronom z klikiem i wahadłem |
| piano | klawiatura jako pianino |
| irtv | pilot na ekranie z przyciskami nauczonymi w aplikacji remote |
| gpsmap | trasa z modułu GPS jako mapa |
| netmon | wykres szybkości odpowiedzi adresu WWW |
| ui | biblioteka graficznego interfejsu dla aplikacji: okna, przyciski, paski, menu (na module gfx) |
| uidemo | pokaz biblioteki ui i przykład aplikacji z grafiką |

Są to reimplementacje dla Cardputera o tych samych nazwach (oprócz `nano`, `cal`, `calc`, `hexdump`, `httping`, `pinmon`, które są własne), nie oryginalne programy.

## Format

- `index.txt`: `nazwa|wersja|opis|ścieżka`, jedna formuła na linię. W opisie nie używaj znaku `|`.
- `Formula/NAZWA.lua`: pierwsza linia `#!lua`, API opisane w głównym README projektu.
