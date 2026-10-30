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

## Prepared downloads

- Windows: signed `phvalheim-client-2.0.17-x86_64.msi`.
- Linux: `phvalheim-client-2.0.17-universal-x86_64.tar.gz`.
- Flatpak: `phvalheim-client-2.0.17-x86_64.flatpak`.
- `SHA256SUMS` records the exact tested downloads. The MSI must not be rebuilt under the
  same version: its Windows product identity has already been handed to testers.

macOS, Debian, and RPM packages remain pending. The existing Windows artifact
passed 75 verification checks, 24 executable smoke checks, and 36 MSI behavior checks.

The Linux packages were revised on 2026-10-30 while retaining the prerelease version
2.0.17. Download them again even if your installed client already reports 2.0.17;
use the current SHA256SUMS to identify this revision. The signed Windows MSI is unchanged.

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

## Validation of the revised Linux packages

The rebuilt 2.0.17 packages passed 42 Flatpak package checks, 53 runtime/browser checks,
and 33 native launch checks. Installing over the earlier 2.0.17 passed 16 checks, including
confirmation that the active Flatpak commit changed. Installing over the withdrawn 2.0.18
test build also passed 16 checks. The tarball contains the same tested published executable.

The unchanged launch implementation previously passed 22 process/lock/transport checks;
config-policy26, launch-window14, sync-display25, and progress10 also passed. Those focused
suites were not repeated for this version-only correction. Recording Steam/Valheim stubs
are used for runtime tests; live Unity/GPU overlay compatibility remains unverified.
