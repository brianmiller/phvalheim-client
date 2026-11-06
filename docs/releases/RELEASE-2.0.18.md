# PhValheim Client 2.0.18 — draft

Test builds for Windows, Linux and macOS. This release remains a draft; 2.0.17 stays the public stable release.

The Steam overlay is enabled by default for direct modded Linux launches when Steam's renderer is available. The server development UI can disable it globally or override it per world. Preferences take effect on the next client launch. The player's `PHVALHEIM_NO_OVERLAY=1` always wins; the older `PHVALHEIM_ENABLE_OVERLAY=1` is no longer necessary and cannot override an operator disable.

Windows, macOS and vanilla launches continue to use Steam's own overlay settings. Disabling the overlay is an optional troubleshooting step, not proof that it caused a hang.

The updated draft also applies personal mod settings saved in the server's themed **View mods** panel. Choices belong to one Steam account and world and apply at the next launch. Only published, operator-overridable keys are accepted; operator-controlled values remain enforced. **Use published default** saves the suggested value; **Use local config** stops applying a web choice and keeps its last local value. Older servers and ordinary local configuration continue to work.

Personal-setting links expire after one hour. If the client cannot retrieve your choices, reopen the world page and launch again. The read credential is scoped to your account and world and is not forwarded to the game.

Packages: Windows MSI; Linux Flatpak, DEB, RPM and tarball; macOS universal PKG and tarball (Apple Silicon and Intel). Checksums are in `SHA256SUMS`.

For the macOS tarball, download `macinstall.sh` alongside the archive and run:

```sh
PHVALHEIM_TARBALL=./phvalheim-client-2.0.18-macos-universal.tar.gz bash macinstall.sh install
```

Install the downloaded Flatpak bundle:

```sh
flatpak install --user ./phvalheim-client-2.0.18-x86_64.flatpak
```

This command also upgrades an existing bundle installation. The Flatpak contains the same code as the previously verified personal-settings draft; existing users of that revision do not need to reinstall.

Validation covers native Windows upgrades from 2.0.12 through 2.0.17, exact installed payload, repair/uninstall and the full wizard; native Apple Silicon tarball and PKG upgrades from 2.0.17, PKG reinstall/fresh install and browser URL activation; Linux package upgrades from 2.0.17; and Flatpak installation, browser launch, synchronization and personal configuration. Linux launch tests use recording Steam and Valheim stubs.

Live Valheim/GPU behavior, the cause of any hang, Intel Mac execution, SteamOS, Bazzite and Flatpak Steam are not established by these checks. Both macOS architectures are included and their signatures checked. The macOS payload uses ad-hoc signing; it is not Apple-notarized. The Windows MSI uses the project's self-signed certificate.
