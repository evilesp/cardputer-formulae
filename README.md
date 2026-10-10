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

Są to reimplementacje dla Cardputera o tych samych nazwach (oprócz `nano`, `cal`, `calc`, `hexdump`, `httping`, `pinmon`, które są własne), nie oryginalne programy.

## Format

- `index.txt`: `nazwa|wersja|opis|ścieżka`, jedna formuła na linię. W opisie nie używaj znaku `|`.
- `Formula/NAZWA.lua`: pierwsza linia `#!lua`, API opisane w głównym README projektu.
