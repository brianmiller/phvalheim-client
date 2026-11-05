# PhValheim Client 2.0.18 — draft Flatpak

Flatpak-only test build. This release remains a draft; 2.0.17 stays the public stable release.

The Steam overlay is enabled by default for direct modded Linux launches when Steam's renderer is available. The server development UI can disable it globally or override it per world. Preferences take effect on the next client launch. The player's `PHVALHEIM_NO_OVERLAY=1` always wins; the older `PHVALHEIM_ENABLE_OVERLAY=1` is no longer necessary and cannot override an operator disable.

Windows, macOS and vanilla launches continue to use Steam's own overlay settings. Disabling the overlay is an optional troubleshooting step, not proof that it caused a hang.

Install the downloaded bundle:

```sh
flatpak install --user ./phvalheim-client-2.0.18-x86_64.flatpak
```

This command also upgrades an existing bundle installation. No Windows, macOS, Debian, RPM or tarball packages are included in this draft.

Validation uses an isolated Linux environment with recording Steam and Valheim stubs. It checks real Flatpak installation, browser/URI launch, synchronization and the environment passed to the host game. Live Valheim/GPU behavior, the cause of any hang, SteamOS, Bazzite and Flatpak Steam are not established by these checks.
