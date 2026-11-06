# PhValheim Client 2.0.18 — overlay controls and personal settings

Stable release for Windows, Linux and macOS, alongside PhValheim Server 2.62.

The Steam overlay is enabled by default for direct modded Linux launches when Steam's renderer is available. PhValheim Server 2.62 can disable it globally or override it per world. Preferences take effect on the next client launch. The player's `PHVALHEIM_NO_OVERLAY=1` always wins; the older `PHVALHEIM_ENABLE_OVERLAY=1` is no longer necessary and cannot override an operator disable.

Windows, macOS and vanilla launches continue to use Steam's own overlay settings. Disabling the overlay is an optional troubleshooting step, not proof that it caused a hang.

This release also applies personal mod settings saved in the server's themed **View mods** panel. Choices belong to one Steam account and world and apply at the next launch. Only published, operator-overridable keys are accepted; operator-controlled values remain enforced. **Use published default** saves the suggested value; **Use local config** stops applying a web choice and keeps its last local value. Older servers and ordinary local configuration continue to work.

Personal-setting links expire after one hour. If the client cannot retrieve your choices, reopen the world page and launch again. The read credential is scoped to your account and world and is not forwarded to the game.

Packages: Windows MSI; Linux Flatpak, DEB, RPM and tarball; macOS universal PKG and tarball (Apple Silicon and Intel). Checksums are in `SHA256SUMS`.

For the macOS tarball, download `macinstall.sh` alongside the archive and run:

```sh
PHVALHEIM_TARBALL=./phvalheim-client-2.0.18-macos-universal.tar.gz bash macinstall.sh install
```

Install the downloaded Flatpak bundle:

```sh
flatpak install --user --reinstall ./phvalheim-client-2.0.18-x86_64.flatpak
```

**Linux packages updated November 6:** if you installed a 2.0.18 candidate before then, download and install it again. Flatpak, DEB, RPM and tarball now fix the enabled Vulkan overlay being disabled by an environment variable set to `0`; enabling removes the variable entirely. Operator-off and `PHVALHEIM_NO_OVERLAY=1` still disable it. The already-tested Windows and macOS packages are unchanged; this follow-up affects direct modded Linux launches.

Brian confirmed the overlay toggle works on Bazzite in Desktop Mode using the updated Flatpak. The Flatpak passed 42 package checks and 85 browser/runtime checks; native launch checks and real Vulkan-loader tests verify environment handling. The rebuilt DEB, RPM and tarball each passed 13 real upgrade/removal checks from the published 2.0.17 packages. Recording Steam/game fixtures do not establish every graphics-driver or Steam packaging combination.

Validation covers native Windows upgrades from 2.0.12 through 2.0.17, exact installed payload, repair/uninstall and the full wizard; native Apple Silicon tarball and PKG upgrades from 2.0.17, PKG reinstall/fresh install and browser URL activation; Linux package upgrades from 2.0.17; and Flatpak installation, browser launch, synchronization and personal configuration. Linux launch tests use recording Steam and Valheim stubs.

Beyond the reported Bazzite Desktop overlay confirmation, broad live Valheim/GPU behavior, the cause of any hang, Intel Mac execution, SteamOS and Flatpak Steam are not established by these checks. Both macOS architectures are included and their signatures checked. The macOS payload uses ad-hoc signing; it is not Apple-notarized. The Windows MSI uses the project's self-signed certificate.

Package source: Linux runtime [b25eccb](https://github.com/brianmiller/phvalheim-client/commit/b25eccb), tested Flatpak [8f67065](https://github.com/brianmiller/phvalheim-client/commit/8f6706568dd6974a3c4ab5949b55017d5f7d2b68), and rebuilt native Linux packages [512f50f](https://github.com/brianmiller/phvalheim-client/commit/512f50f3929e7bab6795bee057e401b7e49190ea). Unchanged Windows/macOS package source: [0d95b03](https://github.com/brianmiller/phvalheim-client/commit/0d95b03c673fde7a639a162f323f4f61c6091729).
