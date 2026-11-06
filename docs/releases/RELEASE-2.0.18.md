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
flatpak install --user --reinstall ./phvalheim-client-2.0.18-x86_64.flatpak
```

**Flatpak updated November 6:** download the bundle again and reinstall even if your installed version already says 2.0.18. This Flatpak fixes the enabled Vulkan Steam overlay being disabled by an environment variable set to `0`; it now removes that variable entirely. Operator-off and `PHVALHEIM_NO_OVERLAY=1` still disable the overlay. Only the Flatpak has this follow-up fix; the other package files are unchanged.

The replacement passed 42 package checks, 85 Flatpak browser/runtime checks, 46 native launch checks and all nine standalone suites. Real Vulkan-loader tests confirm the disable-variable behavior; real Flatpak boundaries were exercised with recording game/Steam fixtures, including an inherited disable flag. A visible Steam overlay in Bazzite/Valheim remains unverified.

Validation covers native Windows upgrades from 2.0.12 through 2.0.17, exact installed payload, repair/uninstall and the full wizard; native Apple Silicon tarball and PKG upgrades from 2.0.17, PKG reinstall/fresh install and browser URL activation; Linux package upgrades from 2.0.17; and Flatpak installation, browser launch, synchronization and personal configuration. Linux launch tests use recording Steam and Valheim stubs.

Live Valheim/GPU behavior, the cause of any hang, Intel Mac execution, SteamOS, Bazzite and Flatpak Steam are not established by these checks. Both macOS architectures are included and their signatures checked. The macOS payload uses ad-hoc signing; it is not Apple-notarized. The Windows MSI uses the project's self-signed certificate.

Flatpak fix source: [8f67065 / PR #22](https://github.com/brianmiller/phvalheim-client/pull/22) (runtime change [b25eccb](https://github.com/brianmiller/phvalheim-client/commit/b25eccb)). All other package source: [0d95b03](https://github.com/brianmiller/phvalheim-client/commit/0d95b03c673fde7a639a162f323f4f61c6091729), with runtime unchanged from 9db58db. These changes remain unmerged; this release remains a draft and prerelease.
