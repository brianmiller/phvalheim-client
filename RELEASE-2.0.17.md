# PhValheim Client 2.0.17 — config preferences and Linux launch reliability prerelease

Supports PhValheim Server 2.60 config delivery. Personal config files survive both full mod
updates and small settings updates. Overridable values fill missing settings only; enforced
values are reapplied before every launch, even when there is nothing to download. Retired
rules release their unchanged enforced values so the mod can regenerate defaults.

Updates extract and merge into a temporary folder before swapping it into place. Failure
keeps the working install. A missing extracted world restores from the cached archive and
then fetches current settings, even when a prior config-only update was newer than that zip.
Older servers retain the previous synchronization contract.

Testing uses real archives, HTTP downloads and the shipped Syncer, with failure and recovery
cases. The actual Syncer harness passed 26 checks, and six archive-to-client checks passed.
Live Unity gameplay remains an operator test. This is a prerelease for testing.

## Linux launch reliability

- Direct modded Linux launches no longer inject Steam's overlay automatically. BepInEx
  remains enabled. Opt in with `PHVALHEIM_ENABLE_OVERLAY=1`; the existing
  `PHVALHEIM_NO_OVERLAY=1` still takes precedence. Overlay-off launches remove inherited
  Steam renderer preload entries and disable the implicit Vulkan overlay layer.
- The Flatpak checks the host process list, so its terminal can close when the game exits.
- A per-user launch lock rejects duplicate clicks before prep or sync. A game already
  running outside PhValheim also blocks sync and launch. No queued automatic relaunch.
- Failed host inspection is reported, not treated as proof the game stopped. Host queries
  drain both output pipes and have an enforced timeout. Unobservable post-launch sessions
  show a warning and close their launcher after 30 seconds without terminating the game.

This addresses launcher defects found while investigating a user-reported Steam overlay
hang. The original machine's raw stacks have not been inspected; the claimed Steam semaphore
cycle and exact root cause are unconfirmed. No live Steam/Unity gameplay fix is claimed.
Disabling our overlay injection removes that integration path; enabling it can still hang.
Vanilla launches remain managed by Steam.

The Vulkan layer opt-out follows the [Khronos troubleshooting guidance](https://github.khronos.org/Vulkan-Site/tutorial/latest/90_FAQ.html).

## Downloads

- Windows: `phvalheim-client-2.0.17-x86_64.msi`.
- Linux: universal x86_64 tarball, Debian `.deb`, Fedora `.rpm`, and Flatpak.
- macOS: universal Intel/Apple Silicon tarball and `.pkg`, plus `macinstall.sh`.
- `SHA256SUMS` identifies the exact revision of every download.

These packages are revisions of the **2.0.17 prerelease**. Redownload the appropriate
package even if your installed client already reports 2.0.17. The Windows revision
explicitly supports upgrading the original 2.0.17 MSI, while preserving protection
against newer versions and unrecognized same-version packages. The Mac `.pkg` uses
the same universal client and URL handler as the tarball.

Install or upgrade the downloaded Flatpak with:

```sh
flatpak install --user ./phvalheim-client-2.0.17-x86_64.flatpak
```

Install this client before updating a test world to Server 2.60. Confirm personal settings
survive both a full mod update and a config-only update, then clear Overridable in the admin
UI and confirm the operator's value returns before launch. A mod's own runtime synchronization
can still override settings during play.

The current launcher compares against stable releases when checking for updates.

Close the old game and launcher windows once before testing this Linux revision. Launch
with the same changed config, confirm the overlay-off notice, quit, and launch again.
The launcher should close after the game exits and reject a second click while playing.

## Earlier Linux revision validation (2026-10-30)

The rebuilt 2.0.17 packages passed 42 Flatpak package checks, 53 runtime/browser checks,
and 33 native launch checks. Installing over the earlier 2.0.17 passed 16 checks, including
confirmation that the active Flatpak commit changed. Installing over the withdrawn 2.0.18
test build also passed 16 checks. The tarball contains the same tested published executable.

The unchanged launch implementation previously passed 22 process/lock/transport checks;
config-policy26, launch-window14, sync-display25, and progress10 also passed. Those focused
suites were not repeated for this version-only correction. Recording Steam/Valheim stubs
are used for runtime tests; live Unity/GPU overlay compatibility remains unverified.

## Full package refresh (2026-10-31)

All seven package formats are now built and tested. The release remains a prerelease.
Runtime source is unchanged from `7ae44e0`; packaging and test improvements are in
[`e087519`](https://github.com/brianmiller/phvalheim-client/commit/e087519951ef7d0de34abac7f1d2213c2f2100da).
The original `2.0.17` git tag is retained; use that source link for this revised package set.

- Debian, RPM and Linux tarball: each passed 13 real install/upgrade/removal checks
  from the published 2.0.16 package.
- Flatpak: 42 package, 53 runtime/browser, 33 native launch checks, plus 16 checks
  installing over the earlier 2.0.17 Flatpak, including active commit replacement.
- Windows: 78 package checks, 24 executable smoke checks, and 36 Wine behavior checks.
  Native Windows passed 14 original-to-revised 2.0.17 upgrade/repair/removal checks
  and 12 full-wizard checks. The installed executable matched the candidate SHA256.
  An old-package negative control failed specifically on that hash check.
- macOS: both universal architectures checked; native Apple Silicon verified tarball
  install, PKG-over-tarball, PKG reinstall, fresh PKG install, and URL activation.
  Fresh PKG installation registers links in the desktop user's Launch Services database.

Native installer evidence: [package validation run](https://github.com/brianmiller/phvalheim-client/actions/runs/41149946862).
These are packaging/launcher checks; live Steam/Valheim gameplay remains unverified.

For the macOS tarball, download it and `macinstall.sh` from this prerelease, then run:

```sh
PHVALHEIM_TARBALL=./phvalheim-client-2.0.17-macos-universal.tar.gz bash ./macinstall.sh install
```

Running `macinstall.sh` without that override installs the latest stable release.
Alternatively, use the included universal `.pkg`.
