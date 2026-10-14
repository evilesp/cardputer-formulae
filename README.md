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
| sl | parowóz D51 jak w linuksowym `sl`, z węglarką i dymem; `-a` wypadek (Help!), `-F` lot, `-c` lokomotywa C51, `-l` mała |
| parrotDancing | papuga z parrot.live: cieniowana literami, kręci głową, co takt nowy kolor; `-s 1..5` szybkość |
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
| tiltracer | wyścig z pięcioma botami po torze 3D z zakrętami i wzniesieniami: 3 lub 5 okrążeń, pozycje, czasy okrążeń; skręt a d albo przechyłem |
| tiltmaze | labirynt z kulką: przechyl Cardputer, żeby kulka dotarła do wyjścia |
| spectrum | widmo dźwięku z mikrofonu jako 16 słupków z nutą i szczytami (firmware v0.1.0.18) |
| sequencer | automat perkusyjny: 8 ścieżek po 16 kroków, tempo, zapis i odczyt rytmu na karcie SD |
| morse | alfabet Morse'a z dźwiękiem: nadawanie tekstu albo nauka rozpoznawania liter i cyfr |
| minesweeper | saper: flagi, liczby i odkrywanie pustych pól |
| sokoban | popychanie skrzyń na miejsca: 27 poziomów, cofanie ruchu (u), licznik ruchów i najlepsze wyniki; własne poziomy z /home/user/sokoban.txt |
| lightsout | zgaś wszystkie światła: naciśnięcie zmienia pole i jego sąsiadów |
| flood | układanka z sześcioma kolorami: lewy górny róg przyjmuje kolor wciśnięty cyfrą 1–6 i pochłania sąsiednie pola tego koloru; zamaluj całą planszę jak najmniejszą liczbą ruchów, `n` nowa plansza, `q` wychodzi |
| mastermind | odgadnij czteroelementowy kod kolorów w dziesięciu próbach |
| bagels | odgadnij trzycyfrową liczbę z różnych cyfr w dziesięciu próbach; FERMI = dobra cyfra na dobrym miejscu, PICO = dobra cyfra na złym miejscu, BAGELS = żadna cyfra nie pasuje; wpisujesz trzy cyfry, enter wysyła, backspace kasuje, n to nowa liczba |
| asciitable | tabela znaków ASCII z kodami dziesiętnymi i szesnastkowymi; `asciitable A` podaje kod, `asciitable 65` znak |
| pacmaze | zjadaj kropki i unikaj dwóch duchów w labiryncie: trzy życia |
| asteroids | asteroidy: skręcasz, lecisz i strzelasz, skały pękają na mniejsze |
| frogger | przejdź żabą przez ulicę i ruch, trzy życia |
| bubbles | strzelaj kolorowymi bańkami w skupisko: grupy po trzy pękają, luźne spadają |
| pomodoro | minutnik pracy i przerw: bloki po 25 minut, krótkie i długie przerwy, sygnały |
| moodlog | dziennik nastroju: ocena 1-5 i notatka dziennie, zapis na karcie, wykres |
| exchange | kursy walut NBP (tabela A, bez klucza) z przelicznikiem; wymaga sterownika json |
| earthquakes | najnowsze trzęsienia ziemi na świecie (USGS, bez klucza); `earthquakes 2.5` pokazuje też słabsze |
| crypto | ceny kryptowalut (CoinGecko, bez klucza) w PLN, USD lub EUR ze zmianą z 24 h; tylko informacja, nie porada |
| connect4 | cztery w rzędzie z botem (3 poziomy) albo we dwoje; a/d kolumna, spacja rzut |
| reversi | reversi (Othello) z botem (3 poziomy) albo we dwoje; h pokazuje możliwe ruchy |
| units | przelicznik jednostek: `units 10 km mi`, `units 98.6 F C`, `units list` |
| joke | losowy żart z JokeAPI (bez klucza, po angielsku, tryb bezpieczny) |
| sunrise | wschód i zachód słońca, południe słoneczne i długość dnia, liczone bez internetu: `sunrise 50.06 19.94` |
| moon | faza Księżyca dla dnia: nazwa, wiek, oświetlenie, najbliższy nów i pełnia, rysunek tarczy, liczone bez internetu: `moon 2024-01-25` |
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
| quiz | 104 pytania w 7 kategoriach (odpowiedzi A–D), rundy po 10, najlepsze wyniki; własne pytania w /home/user/quiz.csv |
| json | sterownik: czytanie JSON dla innych aplikacji (driver.load("json")) |
| eng | sterownik: liczby inżynierskie dla aplikacji elektronicznych (4k7, 100nF), szeregi E (driver.load("eng")) |
| plasma | animacja: klasyczna plazma, pięć palet (spacja zmienia, w s prędkość) |
| fire | animacja: ogień jak w Doomie w czterech kolorach, wiatr (a d) i temperatura (w s) |
| warp | animacja: lot przez pole gwiazd z prędkością warp, sterowanie a d, tęczowy tunel |
| aurora | animacja: zorza polarna z ruchomych promieni nad zamarzniętym jeziorem, które ją odbija; sosny i spadające gwiazdy |
| rain | animacja: deszczowa noc w mieście — trzy warstwy deszczu, rozpryski, odbicia w mokrej ulicy, przejeżdżający samochód, pioruny i grzmot |
| fireworks | animacja: dziesięć rodzajów wybuchów (wierzba, palma, rozdzielające się, iskrzące, pierścienie, serca...), błyski, dym i dźwięk (m wyłącza) |
| lavalamp | animacja: lampa lava z łączącymi się bańkami wosku, cztery kolory |
| spirograph | animacja: spirograf rysuje kolorowe krzywe jedna po drugiej (spacja: następna) |
| snowfall | animacja: zimowa noc — chatka z bali z dymem z komina, śnieg na dachu i sosnach, światło księżyca, podmuchy wiatru |
| pipes | animacja: klasyczne rury z wygaszacza ekranu — kolorowe rury rosną i skręcają po ekranie, aż się zapełni (spacja: czyść, w s: prędkość) |
| waves | animacja: zachód słońca nad morzem — migocząca ścieżka światła, fale z pianą, chmury, żaglówka, księżyc i gwiazdy |
| memory | memory: znajdź pary sam, z uczciwym botem (łatwy, normalny, trudny — zapomina) albo we dwoje; trzy rozmiary stołu |
| fifteen | układanka z przesuwanymi płytkami 3x3, 4x4, 5x5 (zawsze do rozwiązania) |
| battleship | statki: zatop flotę wroga na planszy 10x10; bot szuka i dobija trafiony statek |
| checkers | warcaby angielskie z botem (3 poziomy) albo we dwoje: bicie obowiązkowe, damki, cofanie |
| gomoku | pięć w rzędzie na drewnianej planszy 15x15 z cieniowanymi kamieniami, z botem (3 poziomy) albo we dwoje |
| components | odczyt elementów: rezystor z paskami (3–6 pasków, w obie strony), kody SMD rezystorów, kondensatorów i dławików, dławik z paskami |
| ohm | prawo Ohma i moc: podaj dwie z wielkości V, I, R, P — pozostałe się policzą |
| divider | dzielnik napięcia: Vout, R2 dla Vout, najlepsza para wartości z E12/E24/E96 |
| ledcalc | rezystor do diody LED (także kilku w szeregu), najbliższe wartości E12/E24, prąd i moc |
| rcfilter | częstotliwość graniczna RC, rezonans LC, NE555 astabilny i monostabilny, czas ładowania |
| eseries | szeregi E: najbliższa wartość standardowa, dwa elementy szeregowo lub równolegle, listy szeregów |
| baseconv | liczby w systemie dziesiętnym, szesnastkowym, binarnym, ósemkowym i jako znak; 32 bity do przełączania |
| stopwatch | stoper z międzyczasami, najlepsze i najgorsze okrążenie |
| tipcalc | napiwek i podział rachunku: `tipcalc 85.50 15 3` (procent i liczba osób są opcjonalne) |
| loan | kredyt: miesięczna rata i koszt całkowity z odsetkami, bez klucza: `loan 20000 7.5 5` (kwota, roczne oprocentowanie w procentach, lata; `0` to kredyt bez odsetek) |
| colors | próbnik kolorów: suwaki RGB lub HSV, #RRGGBB, 0xRRGGBB dla gfx i RGB565 dla wyświetlacza |
| dice | rzut kośćmi: d4 do d100, kilka kości, premia, przewaga, własne rzuty typu 3d6+2 |
| GamePerformance | więcej pamięci dla gier: na czas gry wyłącza WiFi (zwalnia 40–50 KB), po grze WiFi wraca i łączy się w tle; `GamePerformance on`, `off` albo `auto` (samo przy każdej grze i animacji); wymaga firmware v0.1.0.23 |
| roman | zamiana liczb na cyfry rzymskie i z powrotem: `roman 1994`, `roman MMXXVI` (od 1 do 3999) |
| reaction | test refleksu: czekasz, aż ekran zrobi się zielony, i naciskasz spację; przedwczesne naciśnięcie się liczy, zapisane są najlepszy czas i średnia |
| blackjack | gra w 21 z krupierem: stawiasz żetony (w s), spacja rozdaje, h dobiera, s pasuje, d podwaja; bank 100 żetonów |
| hanoi | Wieża Hanoi: przenieś krążki na prawy słupek, klawisze a s d (słupki), cyfry 3 do 6 to liczba krążków; z pokazuje rozwiązanie komputera w najmniejszej liczbie ruchów |
| wordle | zgadnij ukryte pięcioliterowe słowo w sześciu próbach; zielony = dobra litera na dobrym miejscu, żółty = litera jest w słowie, szary = jej nie ma; wpisujesz litery, enter wysyła, backspace kasuje; po grze n to nowe słowo |
| tictactoe | kółko i krzyżyk z botem, który nigdy nie przegrywa (perfekcyjna gra): ty jesteś X i zaczynasz; w a s d przesuwają kursor, enter stawia znak, n to nowa gra, ctrl-q wychodzi; wynik gier liczy się w czasie działania |
| mancala | gra Kalah: sześć dołków po każdej stronie, w każdym po cztery ziarna; a d przesuwają kursor, enter sieje ziarna z wybranego dołka, ziarna idą w prawo do twojego magazynu; ostatnie ziarno w pustym dołku zabiera ziarna z dołka naprzeciw; bot patrzy dwa ruchy w przód; n to nowa gra, ctrl-q wychodzi |
| primes | liczby pierwsze do 1000 i rozkład liczby na czynniki pierwsze: `primes 50`, `primes factor 360` |
| bmi | wskaźnik masy ciała (BMI) z kategorią WHO i zakresem wagi dla wzrostu: `bmi 70 175` (kg i cm, albo metry, np. `bmi 70 1.75`) |
| wc | liczy wiersze, słowa i bajty tekstu albo pliku na karcie: `wc to jest tekst`, `wc -f plik.txt` |
| grep | pokazuje wiersze tekstu albo pliku z karty, w których jest szukane słowo, z numerami wierszy: `grep milk /home/user/todo.txt`; `-i` ignoruje wielkość liter, `-c` tylko liczy |
| epoch | zamiana czasu Unix (sekundy od 1970 r.) na datę UTC i z powrotem: `epoch 1700000000`, `epoch 2026-10-13 12:00`, `epoch now` |
| nim | gra w stosy: trzy kupki patyczków (3, 5 i 7); wybierz kupkę klawiszami w s a d, potem weź od 1 do 7 patyczków cyframi 1 do 7; kto weźmie ostatni patyczek, wygrywa; bot gra idealnie (nim-sum); `n` to nowa gra, `ctrl-q` wychodzi |
| sand | animacja: piasek sypie się i tworzy kopce, woda spływa z nich i wypełnia dołki, kamień zostaje tam, gdzie go postawisz (cyfry 1 piasek, 2 woda, 3 kamień, 0 gumka; w s a d kursor; spacja sypie, `p` sypie ciągle, `c` czyści, `q` wychodzi) |
| kaleidoscope | animacja: punkt wędruje po torze, a jego lustrzane kopie tworzą symetryczny kwiat z kolorowym śladem (`a` `d` zmieniają liczbę lustrzanych boków od 4 do 12, `w` `s` prędkość, spacja nowy wzór, `c` czyści ślad, `p` pauza, `q` wychodzi) |
| lander | lądowanie modułu księżycowego na płaskim lądowisku: `w` silnik główny, `a` `d` boczne dysze; paliwo się kończy, lądowanie za szybkie lub poza lądowiskiem to rozbicie, `n` następny poziom, `r` od nowa, `q` wychodzi |
| bouncelogo | animacja w stylu wygaszacza DVD: pudełko z napisem CARDPUTER odbija się od krawędzi i zmienia kolor, licznik trafień w rogi; spacja nowy kolor, `w` `s` prędkość, `c` czyści licznik, `p` pauza, `q` wychodzi |
| lissajous | animacja: krzywe Lissajous, punkt rysuje figurę dwóch falujących sygnałów z ogonem; `a` `d` częstotliwość w poziomie, `w` `s` częstotliwość w pionie, spacja faza, `p` pauza, `q` wychodzi |
| langton | animacja: mrówka Langtona, prosta reguła buduje na siatce wzór z autostradą; `w` `s` prędkość, `p` pauza, `c` zaczyna od nowa, `q` wychodzi |
| fractaltree | animacja: drzewo fraktalne rośnie gałąź po gałęzi i kołysze się na wietrze, a czubki zieleniają się; `a` `d` rozstaw odgałęzień (10–70 stopni), `w` `s` wiatr, spacja nowe drzewo, `q` wychodzi |
| whackamole | krecik wychodzi z dziewięciu dziur: uderzaj je cyframi 1–9 albo przesuwaj kursor `w` `a` `s` `d` i naciśnij enter; 30 sekund, szybkie trafienie daje więcej punktów, pudło w pustą dziurę kosztuje 5 punktów; `spacja` zaczyna grę, `q` wychodzi |
| boids | animacja: stado ptaków, które się zbiera, trzyma odstęp i leci w tę samą stronę co sąsiedzi (jak boidy Reynoldsa), a ptaki odbijają się od krawędzi; `w` `s` prędkość, spacja rozprasza stado, `p` pauza, `q` wychodzi |
| hilbert | animacja: krzywa Hilberta, jedna linia wypełnia siatkę komórek bez przecinania się; `a` `d` wielkość siatki, `w` `s` prędkość, `p` pauza, `c` zaczyna od nowa, `q` wychodzi |
| chaos | animacja: gra w chaos, kropki skaczą w stronę losowych rogów wielokąta i tworzą fraktale, np. trójkąt Sierpińskiego; `a` `d` liczba rogów 3–6, `r` długość skoku (1/2 lub 2/3), `w` `s` prędkość, `c` zaczyna od nowa, `p` pauza, `q` wychodzi |
| rps | kamień, papier, nożyce z botem: `r` kamień, `p` papier, `s` nożyce; wygrywa, kto pierwszy zdobędzie trzy rundy; bot wybiera losowo, więc nie da się go przewidzieć; `n` to nowy mecz, `q` wychodzi |
| pwcheck | ocena hasła bez sieci: długość, użyte zestawy znaków, częste hasła i wzorce oraz czas odgadnięcia; `pwcheck HASŁO` (kilka słów są łączone, więc działa też fraza); hasło nie jest zapisywane |
| helix | animacja: podwójna helisa DNA kręci się na ekranie, przednia nić jest jaśniejsza, szczeble łączą nici; `w` `s` prędkość, `a` `d` długość skrętu, spacja zmienia kolory, `p` pauza, `q` wychodzi |

Są to reimplementacje dla Cardputera o tych samych nazwach (oprócz `nano`, `cal`, `calc`, `hexdump`, `httping`, `pinmon`, które są własne), nie oryginalne programy.

## Format

- `index.txt`: `nazwa|wersja|opis|ścieżka`, jedna formuła na linię. W opisie nie używaj znaku `|`.
- `Formula/NAZWA.lua`: pierwsza linia `#!lua`, API opisane w głównym README projektu.
