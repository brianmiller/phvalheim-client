# PhValheim Client 2.0.18 — Linux launch reliability test build

Includes the Server 2.60 config-policy support from 2.0.17.

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

## Linux test downloads

- `phvalheim-client-2.0.18-x86_64.flatpak`
- `phvalheim-client-2.0.18-universal-x86_64.tar.gz`

Install the Flatpak with:

```sh
flatpak install --user ./phvalheim-client-2.0.18-x86_64.flatpak
```

Close the old game and old launcher windows once before testing. Launch the same world
with the same config change, check the overlay-off notice, quit, and launch again. Confirm
that the terminal closes after quitting and that a second launch click is refused while
playing. Then repeat the personal/enforced config tests for Server 2.60.

The 2.0.17 Windows installer remains unchanged. No Windows or macOS 2.0.18 package is
included in this Linux test build. Keep this release in draft until public testing is intended.

## Validation

- 42 Flatpak package checks and 53 installed runtime/browser checks passed.
- 33 native launch checks passed, including existing-game rejection before HTTP sync,
  default overlay-off environment, explicit opt-in, and opt-out precedence.
- 22 process/lock/transport checks passed, including actual cross-process lock contention,
  lock recovery after a killed process, host timeout and full stderr pipe handling.
- 16 installed upgrade checks passed from the exact 2.0.17 Flatpak to 2.0.18.
- 26 config-policy, 14 launch-window, 25 sync-display, and 10 progress checks passed.
- The unchanged 2.0.17 artifact fails the new default overlay-off and Vulkan-disable
  checks (negative control). Its packages retain their original checksums.

Runtime tests use recording Steam/Valheim stubs with real processes and a real Flatpak
sandbox; no live Unity game, GPU overlay, or Flatpak Steam session was tested. The latter
launch path receives the same overlay environment dictionary but still needs live testing.
Tests do not establish why the affected laptop intermittently hangs.
