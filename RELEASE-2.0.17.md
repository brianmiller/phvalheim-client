# PhValheim Client 2.0.17 — config preferences prerelease

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
Live Unity gameplay remains an operator test. This is a draft prerelease; no public client
release has been published by this work.

## Prepared downloads

- Windows: signed `phvalheim-client-2.0.17-x86_64.msi`.
- Linux: `phvalheim-client-2.0.17-universal-x86_64.tar.gz`.
- Flatpak: `phvalheim-client-2.0.17-x86_64.flatpak`.
- `SHA256SUMS` records the exact tested downloads. The MSI must not be rebuilt under the
  same version: its Windows product identity has already been handed to testers.

macOS, Debian, and RPM packages remain pending. The existing Windows artifact
passed 75 verification checks, 24 executable smoke checks, and 36 MSI behavior checks.

The Flatpak passed 42 package checks, 51 sandbox/runtime checks, 27 native-launch
regression checks, and 16 upgrade checks
from the published 2.0.16 bundle. A control using the old bundle as the proposed update
failed as expected. Browser launch and Steam/Valheim handoff tests use recording stubs;
they do not claim a live game session or testing on SteamOS/Bazzite.

Install or upgrade the downloaded Flatpak with:

```sh
flatpak install --user ./phvalheim-client-2.0.17-x86_64.flatpak
```

Install this client before updating a test world to Server 2.60. Confirm personal settings
survive both a full mod update and a config-only update, then clear Overridable in the admin
UI and confirm the operator's value returns before launch. A mod's own runtime synchronization
can still override settings during play.

Keep this release in draft until public testing and platform availability are intended.
The current launcher compares against stable releases when checking for updates.
