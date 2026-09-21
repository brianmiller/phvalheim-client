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

The `phvalheim://` URL scheme is registered automatically — no `xdg-mime`
step. Synced worlds live in `~/.config/PhValheim`, the same place the `.deb`
and `.rpm` use, so switching package format keeps your worlds.

Requires a **system Steam**, which is what SteamOS and Bazzite ship. A Steam
installed as a Flatpak is not supported; the client detects it and says so.

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
