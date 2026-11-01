# Desktop packages

Plain text files for the `desktop` app. Install one with `desktop install NAME`
(for example `desktop install nord` or `desktop install matrix`), or write your own and
copy it to the folder below. No firmware update is needed.

| Type | Folder on the card | Keys |
|---|---|---|
| app (`NAME.app`) | `/usr/share/desktop/apps` | `Name=`, `Exec=` (program of `/usr/local/bin` with arguments, or a path), `Icon=` (1-2 letters), `Color=0xRRGGBB`, `Comment=` |
| theme (`NAME.theme`) | `/usr/share/desktop/themes` | `bg bar text dim accent panel title border danger wall_top wall_bottom` as `0xRRGGBB` |
| wallpaper (`NAME.wall`) | `/usr/share/desktop/wallpapers` | `top=` and `bottom=` (a gradient) |

Choose a theme and wallpaper in `/home/user/.desktop.conf`:

    theme=nord
    wallpaper=dusk
    hidden=doom,htop
