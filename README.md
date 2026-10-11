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

Są to reimplementacje dla Cardputera o tych samych nazwach (oprócz `nano`, `cal`, `calc`, `hexdump`, `httping`, `pinmon`, które są własne), nie oryginalne programy.

## Format

- `index.txt`: `nazwa|wersja|opis|ścieżka`, jedna formuła na linię. W opisie nie używaj znaku `|`.
- `Formula/NAZWA.lua`: pierwsza linia `#!lua`, API opisane w głównym README projektu.
