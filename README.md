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
| doom | Doom-podobna strzelanka z grafiką pikselową (wersja 0.1.1.3, dźwięk z firmware v0.1.0.17, wyłączenie klawiszem x): chodzenie, strzelanie, wrogowie, apteczki, minimapa; idziesz, dopóki trzymasz w s a d , / q e (puszczasz – stajesz); wymaga firmware v0.1.0.14; `brew install doom` sam dopyta o brakujące części (doomgame, doomdraw, doomlevel) |
| doomgame | zasady gry, potwory, pętla gry i ruch dla doom (driver) |
| doomdraw | rysowanie obrazu i menu dla doom (driver) |
| doomlevel | poziom i geometria dla doom (driver) |
| memcleaner | sprzątanie karty SD: puste pliki, kopie, cache, pliki tymczasowe, nieskończone pobrania i bardzo stare pliki; pyta o każdy plik (y usuwa, n zostawia, s pomija resztę); wymaga firmware v0.1.0.14 |
| invaders | Space Invaders w pikselach (a d, f strzela) |
| breakout | cegiełki i piłeczka |
| flappy | ptak lecący między rurami |
| 2048 | układanka 2048 klawiszami w a s d |
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
| setting | ustawienia graficzne: WiFi (skan, hasło, połączenie, zapis do połączenia przy starcie), jasność, głośność; wymaga firmware v0.1.0.16 |
| analogclock | zegar analogowy z datą |
| metronome | metronom z klikiem i wahadłem |
| piano | klawiatura jako pianino |
| irtv | pilot na ekranie z przyciskami nauczonymi w aplikacji remote |
| gpsmap | trasa z modułu GPS jako mapa |
| netmon | wykres szybkości odpowiedzi adresu WWW |
| ui | biblioteka graficznego interfejsu dla aplikacji: okna, przyciski, paski, menu (na module gfx) |
| uidemo | pokaz biblioteki ui i przykład aplikacji z grafiką |
| steps | licznik kroków: dziś kontra cel, ostatnie 7 dni, zerowanie; liczy w tle (firmware v0.1.0.18) |
| sleep | tryb oszczędny: godzina, data, kroki i bateria na najniższej jasności, 80 MHz, WiFi oszczędza prąd; dowolny klawisz budzi |
| deepSleep | głęboki sen: ekran wyłączony, procesor zatrzymany; klawisz albo BOOT budzi |
| off | wyłączenie: odcina baterię, jeśli płytka na to pozwala; inaczej głęboki sen do BOOT |
| tiltracer | wyścig po drodze w 3D: przechylasz, aby skręcać (czujnik ruchu) |
| tiltmaze | labirynt z kulką: przechyl Cardputer, żeby kulka dotarła do wyjścia |
| spectrum | widmo dźwięku z mikrofonu jako 16 słupków z nutą i szczytami (firmware v0.1.0.18) |
| sequencer | automat perkusyjny: 8 ścieżek po 16 kroków, tempo, zapis i odczyt rytmu na karcie SD |
| morse | alfabet Morse'a z dźwiękiem: nadawanie tekstu albo nauka rozpoznawania liter i cyfr |
| minesweeper | saper: flagi, liczby i odkrywanie pustych pól |
| sokoban | popychanie skrzyń na miejsca: trzy poziomy, własne z /home/user/sokoban.txt |
| lightsout | zgaś wszystkie światła: naciśnięcie zmienia pole i jego sąsiadów |
| mastermind | odgadnij czteroelementowy kod kolorów w dziesięciu próbach |
| pacmaze | zjadaj kropki i unikaj dwóch duchów w labiryncie: trzy życia |
| asteroids | asteroidy: skręcasz, lecisz i strzelasz, skały pękają na mniejsze |
| frogger | przejdź żabą przez ulicę i ruch, trzy życia |
| bubbles | strzelaj kolorowymi bańkami w skupisko: grupy po trzy pękają, luźne spadają |
| pomodoro | minutnik pracy i przerw: bloki po 25 minut, krótkie i długie przerwy, sygnały |
| moodlog | dziennik nastroju: ocena 1-5 i notatka dziennie, zapis na karcie, wykres |
| exchange | kursy walut NBP (tabela A, bez klucza) z przelicznikiem; wymaga sterownika json |
| countdown | dni do Twoich dat z /home/user/countdown.txt; dodawanie i usuwanie |
| cipher | szyfrowanie i odszyfrowywanie: przesunięcie Cezara i klucz Vigenère |
| rss | nagłówki kanałów RSS i Atom z listy w /home/user/rss.txt |
| worldclock | czas w kilku miastach z zasadami czasu letniego (Europa, USA) |
| tuner | stroik: nuta najbliższa dźwiękowi z mikrofonu i odchyłka w centach (firmware v0.1.0.18) |
| scope | oscyloskop na pinie analogowym (GPIO1-10): napięcie w czasie (firmware v0.1.0.18) |
| siggen | generator fali prostokątnej na pinie: buzzer, dioda, test (firmware v0.1.0.18) |
| functionplot | rysuje y = f(x) dla dowolnego wyrażenia z x: sin(x), x*x - 2, exp(-x*x) |
| tanks | pojedynek czołgów: gra z botem (łatwy, normalny, trudny) albo dla dwóch graczy; jazda, celowanie z linią lotu, wiatr, kratery |
| wifimap | sieci WiFi według kanałów: najmocniejszy sygnał i liczba sieci, najmniej zatłoczony kanał (firmware v0.1.0.18) |
| quiz | quiz z /home/user/quiz.csv (pytanie;odpowiedź) albo wbudowane pytania, z wynikiem |
| json | sterownik: czytanie JSON dla innych aplikacji (driver.load("json")) |

Są to reimplementacje dla Cardputera o tych samych nazwach (oprócz `nano`, `cal`, `calc`, `hexdump`, `httping`, `pinmon`, które są własne), nie oryginalne programy.

## Format

- `index.txt`: `nazwa|wersja|opis|ścieżka`, jedna formuła na linię. W opisie nie używaj znaku `|`.
- `Formula/NAZWA.lua`: pierwsza linia `#!lua`, API opisane w głównym README projektu.
