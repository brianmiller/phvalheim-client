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

### Universal Linux (.tar.gz)

```bash
tar -xzf phvalheim-client-<version>-universal-x86_64.tar.gz
sudo ./phvalheim-client-installer.sh install
xdg-mime default phvalheim-client.desktop x-scheme-handler/phvalheim
```

### macOS (.pkg)

```bash
sudo installer -pkg phvalheim-client-<version>-macos-universal.pkg -target /
```

The installer places the binary at `/usr/local/bin/phvalheim-client` and registers the `phvalheim://` URL scheme automatically via a `PhValheim Client.app` bundle in `/Applications`. No further configuration is needed.

The package is a universal binary and runs natively on both Intel and Apple Silicon Macs.

> **Note:** macOS may show a Gatekeeper warning on first launch since the package is not yet notarized. To allow it: System Settings → Privacy & Security → click "Open Anyway".

### Windows (.msi)

Run the installer. The URL scheme handler is registered automatically.

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

## Building from source

Requires [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0).

```bash
dotnet publish -c Linux-Release -r linux-x64 -p:PublishSingleFile=true --self-contained true ./phvalheim-client.csproj
```

Package builds use Docker or a remote Mac:
- **Debian .deb**: `bash builders/build_deb-outie`
- **Fedora .rpm**: `bash builders/build_rpm-outie`
- **Universal .tar.gz**: `bash builders/build_tgz-innie`
- **macOS .pkg**: `MAC_HOST=<host> MAC_USER=<user> MAC_PASS=<pass> bash builders/build_pkg-outie` (requires SSH access to a Mac)

## Related

- [phvalheim-server](https://github.com/brianmiller/phvalheim-server) — The server side of PhValheim
