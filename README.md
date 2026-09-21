# PhValheim Client

The client-side companion to [phvalheim-server](https://github.com/brianmiller/phvalheim-server). PhValheim Client syncs world contexts from a remote PhValheim Server and launches Valheim with the correct BepInEx mod environment for that world.

## How it works

PhValheim Server registers a `phvalheim://` URL scheme handler on your desktop. When you click a world launch link from the server's web UI, PhValheim Client:

1. Connects to the PhValheim Server and checks if your local world files are in sync
2. Downloads any updated world files (mods, configs, BepInEx) if needed
3. Launches Valheim with the correct BepInEx context, server connection details, and password

## Requirements

- [Valheim](https://store.steampowered.com/app/892970/Valheim/) installed via Steam
- Steam running before launching
- A running [phvalheim-server](https://github.com/brianmiller/phvalheim-server)

## Installation

### Debian / Ubuntu (.deb)

```bash
sudo dpkg -i phvalheim-client-<version>-x86_64.deb
sudo chmod 755 /usr/bin/phvalheim-client
xdg-mime default phvalheim-client.desktop x-scheme-handler/phvalheim
```

### Fedora / RHEL (.rpm)

```bash
sudo rpm -i phvalheim-client-<version>-x86_64.rpm
xdg-mime default phvalheim-client.desktop x-scheme-handler/phvalheim
```

### SteamOS / Bazzite and other Linux (Flatpak)

```bash
flatpak install --user ./phvalheim-client-<version>-x86_64.flatpak
```

On GNOME and KDE that is the whole installation — the `phvalheim://` handler
registers itself, with no `xdg-mime` step. On Hyprland, Sway, i3 and other
bare window managers, also run this once and then **log out and back in**,
or clicking a world link will silently do nothing:

```bash
mkdir -p ~/.config/environment.d && printf 'XDG_DATA_DIRS=/usr/local/share:/usr/share:/var/lib/flatpak/exports/share:%s/.local/share/flatpak/exports/share\n' "$HOME" > ~/.config/environment.d/flatpak.conf
```

That puts Flatpak's applications directory on your session's search path. It
is safe to run on any desktop, it is needed by every Flatpak you install
rather than this one in particular, and
[there is more on it below](#if-clicking-a-world-link-does-nothing) if links
still don't open.

Synced worlds live in `~/.config/PhValheim`, the same place the `.deb` and
`.rpm` use, so switching package format keeps your worlds.

Works with a **system Steam**, which is what SteamOS and Bazzite ship. A Steam
installed as a Flatpak (`com.valvesoftware.Steam`) is also supported, though
that path is **untested** — see [Flatpak Steam](#flatpak-steam) below.

Note that this package is not meaningfully sandboxed: launching Valheim means
running host programs and reading your Steam library wherever it lives. See
[docs/FLATPAK.md](docs/FLATPAK.md) for exactly which permissions it takes and
why.

### Universal Linux (.tar.gz)

```bash
tar -xzf phvalheim-client-<version>-universal-x86_64.tar.gz
sudo ./phvalheim-client-installer.sh install
xdg-mime default phvalheim-client.desktop x-scheme-handler/phvalheim
```

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/brianmiller/phvalheim-client/master/macinstall.sh | bash
```

This downloads the latest universal binary, installs it to `/usr/local/bin/phvalheim-client`, and registers the `phvalheim://` URL scheme via a `.app` bundle in `/Applications`. Works on both Intel and Apple Silicon Macs (Apple Silicon runs Valheim under Rosetta 2 for full mod compatibility).

To uninstall or run diagnostics:

```bash
curl -fsSL https://raw.githubusercontent.com/brianmiller/phvalheim-client/master/macinstall.sh | bash -s -- uninstall
curl -fsSL https://raw.githubusercontent.com/brianmiller/phvalheim-client/master/macinstall.sh | bash -s -- diags
```

### Windows (.msi)

Run the installer. The URL scheme handler is registered automatically, and the
client is installed to `%AppData%\PhValheim\phvalheim-client\`.

The installer is currently signed with a self-signed certificate, so Windows
SmartScreen will warn about an unknown publisher. Choose **More info → Run
anyway** to proceed.

## Usage

Normally you never run the client yourself. Click a world's launch link in the
PhValheim Server web UI and your desktop hands the `phvalheim://` URL to the
client, which syncs that world and starts Valheim. Start Steam first.

Run with no arguments to print the version and usage:

```bash
phvalheim-client            # or: flatpak run com.phvalheim.Client
```

### Flatpak usage notes

The Flatpak is a normal app once installed — the launch link works the same as
every other package. A few things are specific to it:

```bash
# Hand it a launch URL by hand (what your browser does for you)
flatpak run com.phvalheim.Client 'phvalheim://?<base64>'

# See exactly what access it has
flatpak info --show-permissions com.phvalheim.Client
```

**If your Steam library is somewhere unusual**, the client will report
"Valheim not found" — it can only read paths the sandbox grants. Home,
`/run/media`, `/media` and `/mnt` are covered, which includes Steam Deck SD
cards and most second drives. For anywhere else, grant it:

```bash
flatpak override --user --filesystem=/data/games com.phvalheim.Client
```

The client prints its progress to a terminal, which your desktop opens for it.
**In Steam Deck Game Mode there is no terminal**, so a launch there runs
silently — it works, but you get no progress output.

#### Flatpak Steam

> **Untested.** This works in theory and is implemented, but nobody has run it
> against a real `com.valvesoftware.Steam` yet. If you try it, please report
> what happens on
> [issue #86](https://github.com/brianmiller/phvalheim-server/issues/86).

If you have no system Steam, the client falls back to
`com.valvesoftware.Steam` automatically — there is nothing to configure. It
reads your library from `~/.var/app/com.valvesoftware.Steam/.local/share/Steam`
and launches Valheim *inside* Steam's own sandbox, which is where the Steam
Runtime and the Steam client both live.

One grant may be needed, because `--filesystem=home` deliberately does not
reach another app's data directory. New installs have it already; if you are
upgrading in place, or the client reports that the Steam directory is not
readable:

```bash
flatpak override --user --filesystem=~/.var/app/com.valvesoftware.Steam com.phvalheim.Client
```

If a modded world launches and then exits immediately, that is the case worth
reporting — it most likely means the game could not reach the Steam client.

#### If clicking a world link does nothing

Your session isn't exposing Flatpak's applications directory, so nothing can
find the handler. This affects **every** Flatpak you install, not just this
one — GNOME and KDE set it up for you, bare Hyprland/Sway/i3 often don't.
Flatpak warns about it at install time and it scrolls past.

Copy and paste this once, then **log out and back in**:

```bash
mkdir -p ~/.config/environment.d && printf 'XDG_DATA_DIRS=/usr/local/share:/usr/share:/var/lib/flatpak/exports/share:%s/.local/share/flatpak/exports/share\n' "$HOME" > ~/.config/environment.d/flatpak.conf
```

To confirm after logging back in — this should print
`com.phvalheim.Client.desktop`:

```bash
gio mime x-scheme-handler/phvalheim
```

<details>
<summary>Didn't work, or you don't use systemd</summary>

Set the handler explicitly:

```bash
xdg-mime default com.phvalheim.Client.desktop x-scheme-handler/phvalheim
```

Without a systemd user session, add the same value to your shell profile
instead — `~/.profile` for bash/zsh, or `~/.config/fish/conf.d/flatpak.fish`
for fish, which never reads `/etc/profile.d`:

```bash
echo 'export XDG_DATA_DIRS="$XDG_DATA_DIRS:/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share"' >> ~/.profile
```

Test the whole chain in one go — this should open a terminal reading
`malformed phvalheim URL`:

```bash
gio open 'phvalheim://?bogus'
```

Note that fixing this in a terminal only fixes that terminal. Your browser
inherits the **session's** environment, so a real link click needs the change
above plus a logout.

One rarer cause: the desktop entry is `Terminal=true`, so your desktop needs
some way to open a terminal. Modern GLib uses `xdg-terminal-exec`; older
versions search a fixed list containing none of foot, Alacritty, Ghostty or
kitty. With none of `xdg-terminal-exec`, `xterm`, `gnome-terminal` or
`konsole` installed, a click can fail silently even when everything else is
correct.

</details>

#### Testing without any of that

The URL handler is only the delivery mechanism. To exercise the client itself
— sync, Steam, launching Valheim — copy a world's launch link from the server
web UI (right-click → **Copy Link Address**) and hand it over directly:

```bash
flatpak run com.phvalheim.Client '<paste the phvalheim:// link here>'
```

Same binary, same sandbox, same everything a click produces, with progress
printed in your current terminal.

## Uninstalling

### Universal Linux

```bash
sudo ./phvalheim-client-installer.sh uninstall
```

### Debian / Ubuntu

```bash
sudo dpkg -r phvalheim-client
```

### Fedora / RHEL

```bash
sudo rpm -e phvalheim-client
```

### Flatpak

```bash
flatpak uninstall --user com.phvalheim.Client
```

Synced worlds under `~/.config/PhValheim` are left in place; delete that
directory to remove them too.

## Building from source

Requires [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0).

```bash
dotnet publish -c Linux-Release -r linux-x64 -p:PublishSingleFile=true --self-contained true ./phvalheim-client.csproj
```

Package builds use Docker or a remote Mac:
- **Debian .deb**: `bash builders/build_deb-outie`
- **Fedora .rpm**: `bash builders/build_rpm-outie`
- **Universal .tar.gz**: `bash builders/build_tgz-innie`
- **Linux Flatpak**: `bash builders/build_flatpak-outie`
- **Windows .msi**: `bash builders/build_msi-outie`
- **macOS .tar.gz**: `bash builders/build_macos-outie` (requires SSH access to a Mac build host)

The Flatpak build needs only Docker; flatpak-builder and the whole test rig
live in the container. It gates on 102 checks — package structure, a real
install driven through a `phvalheim://` link clicked in a browser, and a
regression check that the non-sandboxed code path the `.deb`/`.rpm`/`.tar.gz`
share still behaves identically. See [docs/FLATPAK.md](docs/FLATPAK.md).

The Windows `.msi` builds headlessly on Linux via `wixl` — no Windows machine or
Visual Studio required. See [docs/MSI-BUILD-PLAN.md](docs/MSI-BUILD-PLAN.md) for
why, and `builders/wxs/phvalheim-client.wxs` for the installer definition.

To sign the `.msi`, mint a self-signed certificate (written outside the repo) and
point the builder at it:

```bash
bash builders/gen-codesign-cert.sh
export CODESIGN_PFX="$HOME/.config/phvalheim-client/codesign/phvalheim-client.pfx"
export CODESIGN_PFX_PW_FILE="$HOME/.config/phvalheim-client/codesign/phvalheim-client-pfx.pw"
bash builders/build_msi-outie
```

With `CODESIGN_PFX` unset the build still succeeds and emits an unsigned `.msi`.

## Related

- [phvalheim-server](https://github.com/brianmiller/phvalheim-server) — The server side of PhValheim
