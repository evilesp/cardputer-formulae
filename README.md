# cardputer-formulae

Pakiety do menedżera `brew` na [Cardputer Linux](https://github.com/) (M5Stack Cardputer ADV).
Każda formuła to program w Lua, który uruchamia się na urządzeniu.

## Użycie na Cardputerze

```bash
brew tap https://raw.githubusercontent.com/evilesp/cardputer-formulae/main
brew update
brew search
brew install cmatrix fastfetch asciiquarium speedtest-cli
```

## Pakiety

| Nazwa | Opis |
|---|---|
| cmatrix | spadające znaki (q = wyjście) |
| fastfetch | podsumowanie urządzenia z logo |
| asciiquarium | akwarium (q = wyjście) |
| speedtest-cli | ping, pobieranie i wysyłanie |

Są to reimplementacje dla Cardputera o tych samych nazwach, nie oryginalne programy.

## Format

- `index.txt`: `nazwa|wersja|opis|ścieżka`, jedna formuła na linię.
- `Formula/NAZWA.lua`: pierwsza linia `#!lua`, API opisane w głównym README projektu.
