# PhValheim Client 2.0.19 — corrected Windows MSI public prerelease

**The corrected Windows MSI is public** on the
[2.0.19 release page](https://github.com/brianmiller/phvalheim-client/releases/tag/2.0.19).
**Existing 2.0.19 testers: [download the MSI again](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-x86_64.msi)
and install over the original 2.0.19 installation.** Native Windows testing verified
this upgrade. The version and filename are unchanged; identify the corrected MSI
by its size and SHA-256 below.

**2.0.18 remains stable and unchanged.** This prerelease contains only the Windows
MSI and checksums; no Linux, Flatpak, or macOS packages are published by this revision.
All other published packages remain unchanged.

## Corrected behavior

The correction handles Hidden `winhttp.dll`, `doorstop_config.ini`, and
`phvalheim.backend` files while preserving Hidden attributes and existing ACLs.
Managed writes stage new contents before replacing the target; failed staging
preserves the original. ReadOnly and actual write permissions remain enforced,
reparse-point destinations are rejected, and a genuinely denied backend write
still aborts launch. The client does not change permissions, clear ReadOnly, or
request elevation. Staging does not guarantee protection against external races or power loss.

Windows loader installation copies only `winhttp.dll` and `doorstop_config.ini`,
skipping files intended for other platforms. Linux selects `libdoorstop_x64.so`
and the config; macOS copies no loader files into the signed `Valheim.app` bundle.
Ordinary macOS copies also preserve the destination's Hidden flag. Cross-platform
source validation does not imply publication of packages for those platforms.

## Artifact identity and migration

Both builds use `phvalheim-client-2.0.19-x86_64.msi`:

| Field | Original MSI (superseded) | Corrected public MSI |
| --- | --- | --- |
| Size | 32,886,784 bytes | 32,899,072 bytes |
| MSI SHA-256 | `7e48a17e1b9921360ffeaab77d34cea1b7243ac3eb4e0ac0a569b4f0432dc488` | `260c78168955438b03d7b0684a83990db76c82dcf4de59c05820abacee4e949a` |
| ProductCode | `3783EF6D-25B9-4A61-9518-BE79B530643A` | `9ED226DE-BDBE-4D21-A0F3-C0422155FA22` |

The corrected executable SHA-256 is
`d692bf7312e2a6fc307af47406110e0c592fab3c3a57ea98e5bf9aa80de4fec1`.
It was built from corrected source
[`1d6d7c93c8dc4c58a6ca6d4401b3075e6837ecb7`](https://github.com/brianmiller/phvalheim-client/commit/1d6d7c93c8dc4c58a6ca6d4401b3075e6837ecb7);
source PR #28 remains unmerged. The numeric `2.0.19` tag remains at
[`6204fe1103f8c7f5e26bcd833e84d16e8cf2dc33`](https://github.com/brianmiller/phvalheim-client/commit/6204fe1103f8c7f5e26bcd833e84d16e8cf2dc33)
and does not identify the corrected build.

The original MSI is preserved at immutable Git commit
[`3e63990b7877d5eade2a88ccc53e4003b7e02282/builds/phvalheim-client-2.0.19-x86_64.msi`](https://github.com/brianmiller/phvalheim-client/blob/3e63990b7877d5eade2a88ccc53e4003b7e02282/builds/phvalheim-client-2.0.19-x86_64.msi).
The corrected MSI explicitly upgrades the original ProductCode
`3783EF6D-25B9-4A61-9518-BE79B530643A` to `9ED226DE-BDBE-4D21-A0F3-C0422155FA22`.
Unknown same-version products and newer versions remain blocked. The MSI retains
the existing self-signed publisher certificate; Windows may show an unknown publisher.

## Completed validation

- Local build: 27 existing warnings, 0 errors; all 11 test suites passed.
- MSI: 78 structural/signature checks; executable: 24 argument/smoke checks;
  Wine: 36 installation-behavior checks passed. Wine skipped repair; native Windows covered it.
- [Native file validation — 44619866045](https://github.com/brianmiller/phvalheim-client/actions/runs/44619866045):
  **SUCCESS**, with Windows 126, macOS 98, and Linux 103 assertions passed.
- [Native installer validation — 44620112640](https://github.com/brianmiller/phvalheim-client/actions/runs/44620112640):
  all eight Windows upgrade jobs from 2.0.12–2.0.19 passed 14 checks each, including
  exact installed executable SHA-256, one Add/Remove Programs entry, repair, and uninstall.
  The full wizard passed 12 checks plus five no-click control checks; the old-payload
  negative control passed by failing specifically at the executable SHA check.
  **The overall workflow failed only at the old Hidden-file fixture.** The successful
  installation jobs are distinct from that overall result; the corrected fixture passed below.
- [Final focused real-client validation — 44622099219](https://github.com/brianmiller/phvalheim-client/actions/runs/44622099219):
  **SUCCESS**, using the actual corrected executable extracted from the exact MSI.
  Hidden `winhttp.dll`, `doorstop_config.ini`, and `phvalheim.backend` sentinel contents
  changed to the expected bytes while Hidden stayed true and attributes stayed `34`.
  Foreign Hidden+ReadOnly `.so`/`.dylib` files retained their bytes and attributes.
  The ReadOnly+Hidden `winhttp.dll` control preserved bytes and flags with no Steam handoff.
  The original real executable reproduced access denial with no Steam handoff.
  Testing used a disposable local HTTP world and a recording Steam stub, not live Valheim.

## Diagnostics and troubleshooting

Path-specific diagnostics retain the failing operation, exception type, message,
and hexadecimal HResult, plus file attributes, Windows owner/ACL observations,
and a temporary parent-directory write probe where available. Unavailable observations
remain unknown; these observations do not establish antivirus or Controlled Folder Access as the cause.

The normal Windows log is `%APPDATA%\PhValheim\logs\phvalheim-client.log`.
Logs redact credentials and rotate at 1 MiB and at the start of each run, retaining
up to three archives. If the normal location fails, the client tries a temporary
fallback. Use the actual path printed in the error; if both locations fail, logging
is reported as unavailable. Review logs before sharing: local paths and usernames may remain.

Disk-space preflight checks the destination volume for downloads, archive/config
staging, loader copies, and backend writes. It reports required additional bytes
and available space where measurable; unknown sizes remain unknown, and estimates
do not guarantee an update will fit. Failed staged updates preserve the installed
world; failed download transport preserves the cached archive.

## Validation limits

For [issue #25](https://github.com/brianmiller/phvalheim-client/issues/25), the affected
player confirmed gameplay after manually clearing Hidden flags in the original
installation. **Live gameplay with the corrected MSI has not been tested.** No actual
Valheim gameplay validation was performed; the Steam stub verifies handoff only.
The corrected MSI's resolution of that player's failure and real antivirus/Controlled
Folder Access behavior remain unverified.
