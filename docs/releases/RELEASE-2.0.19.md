**2.0.19 is a prerelease for testing**, for Windows, Linux (DEB, RPM, TGZ, Flatpak) and macOS.
It changes how the Windows client writes PhValheim's loader, config and backend files when
they are Hidden, the problem behind [issue #25](https://github.com/brianmiller/phvalheim-client/issues/25)
(not yet confirmed in real gameplay; see *What has not been tested*).

**2.0.18 is still the stable release.** The installers and "latest" links keep giving you
2.0.18; install 2.0.19 only from the downloads below.

### Already installed 2.0.19?

- **Windows:** the MSI on this page was replaced with a corrected build on 19 November at
  21:59 UTC. It has the same version and file name, so check the size: the first MSI is
  32,886,784 bytes, the corrected one 32,899,072 bytes (SHA-256 below). If you have the first
  one, download the MSI again and run it; it upgrades your installation in place.
- **Linux and macOS:** these packages were built from the corrected source and posted on
  19 November at 23:13 UTC. If you installed a 2.0.19 package before then, install it again.

## Downloads and SHA-256

Every file below is the corrected build. Each was downloaded again after publication,
without signing in, and matched these hashes and the published [SHA256SUMS](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/SHA256SUMS).

| Platform / format | Artifact | SHA-256 |
| --- | --- | --- |
| Windows MSI | [phvalheim-client-2.0.19-x86_64.msi](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-x86_64.msi) | `260c78168955438b03d7b0684a83990db76c82dcf4de59c05820abacee4e949a` |
| Linux DEB | [phvalheim-client-2.0.19-x86_64.deb](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-x86_64.deb) | `16486664a7077e13b2fcf209761bc5bab6741d0b0f2574de2d88294d8ea2f0a1` |
| Linux RPM | [phvalheim-client-2.0.19-x86_64.rpm](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-x86_64.rpm) | `85f5a70534d25411aa9dd053b96ca90c1298e37a4eae55cd221bba7ab0480806` |
| Linux TGZ | [phvalheim-client-2.0.19-universal-x86_64.tar.gz](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-universal-x86_64.tar.gz) | `f12c4c4ed9b0e8309febb82e14e954867be31c4ca64e9db4de83209960bd8768` |
| Linux Flatpak | [phvalheim-client-2.0.19-x86_64.flatpak](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-x86_64.flatpak) | `b5a3b07000d6e553f5866d5104b9abe2d63f84cfc9368bb9c7a59c82b1c1c029` |
| macOS universal TGZ (primary) | [phvalheim-client-2.0.19-macos-universal.tar.gz](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-macos-universal.tar.gz) | `5e72c58f9cc59479fb30eb47ca822b9d8c88eeddc219e2bd0731af3ec2b539db` |
| macOS universal PKG (supplementary) | [phvalheim-client-2.0.19-macos-universal.pkg](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-macos-universal.pkg) | `fc44914703b60582477d009b7d3d7cccbf492cca3eb1bf69b85311ef8cbc8ddd` |

macOS uses the shell installer plus universal TGZ as its primary installation method;
the PKG is supplementary. The [macinstall.sh release asset](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/macinstall.sh)
has SHA-256 `13c8894e2d76e0cebb1a6b097c7dbbd175a420175a134c65d2374299f748d925`.
The normal installer installs stable 2.0.18. To install 2.0.19 instead, download
the installer and the tarball into the same folder:

```bash
curl -fLO https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/macinstall.sh
curl -fLO https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-macos-universal.tar.gz
PHVALHEIM_TARBALL=./phvalheim-client-2.0.19-macos-universal.tar.gz bash ./macinstall.sh install
```

For Linux, follow the [README installation commands](https://github.com/brianmiller/phvalheim-client#installation)
with version `2.0.19`. On Windows, run the downloaded MSI.

## What changed

On Windows, the correction handles Hidden `winhttp.dll`, `doorstop_config.ini`, and
`phvalheim.backend` files while preserving Hidden attributes and existing ACLs.
Managed writes stage new contents before replacing the target; failed staging
preserves the original. ReadOnly and actual write permissions remain enforced,
reparse-point destinations are rejected, and a genuinely denied backend write
still aborts launch. The client does not change permissions, clear ReadOnly, or
request elevation. Staging does not guarantee protection against external races or power loss.

Windows loader installation copies only `winhttp.dll` and `doorstop_config.ini`,
skipping files intended for other platforms. Linux selects `libdoorstop_x64.so`
and the config; macOS copies no loader files into the signed `Valheim.app` bundle.
Ordinary macOS copies also preserve the destination's Hidden flag.

## Diagnostics and troubleshooting

Path-specific diagnostics retain the failing operation, exception type, message,
and hexadecimal HResult, plus file attributes, Windows owner/ACL observations,
and a temporary parent-directory write probe where available. Unavailable observations
remain unknown; these observations do not establish antivirus or Controlled Folder Access as the cause.

Diagnostics, persistent logs, and disk-space checks are available on all platforms:

| Platform | Normal diagnostic log |
| --- | --- |
| Windows | `%APPDATA%\PhValheim\logs\phvalheim-client.log` |
| Linux | `~/.config/PhValheim/logs/phvalheim-client.log` |
| macOS | `~/Library/Application Support/PhValheim/logs/phvalheim-client.log` |

Logs redact credentials and rotate at 1 MiB and at the start of each run, retaining
up to three archives. If the normal location fails, the client tries a temporary
fallback. Use the actual path printed in the error; if both locations fail, logging
is reported as unavailable. Review logs before sharing: local paths and usernames may remain.

Disk-space preflight checks the destination volume for downloads, archive/config
staging, loader copies, and backend writes. It reports required additional bytes
and available space where measurable; unknown sizes remain unknown, and estimates
do not guarantee an update will fit. Failed staged updates preserve the installed
world; failed download transport preserves the cached archive.

## Testing

- Corrected-source local build: 27 existing warnings, 0 errors; all **11** test suites passed.
- MSI: **78** structure/signature checks; executable: **24** argument/smoke checks; Wine: **36** installation checks passed. Wine skipped repair; native Windows covered it.
- [Native file validation 44619866045](https://github.com/brianmiller/phvalheim-client/actions/runs/44619866045): **SUCCESS**, with Windows **126**, macOS **98**, and Linux **103** assertions passed.
- [Native installer validation 44620112640](https://github.com/brianmiller/phvalheim-client/actions/runs/44620112640): all eight Windows upgrades from 2.0.12–2.0.19 passed **14 checks each**, including exact executable SHA-256, one Add/Remove Programs entry, repair, and uninstall. The wizard passed **12** checks plus **5** no-click controls; the old-payload negative control failed at the expected hash check. The workflow's only failure was its outdated Hidden-file test fixture; the real-client run below covers those files with the corrected build.
- [Real-client validation 44622099219](https://github.com/brianmiller/phvalheim-client/actions/runs/44622099219): **SUCCESS**, using the actual executable from the exact corrected MSI. Hidden loader/config/backend sentinels changed to expected bytes while Hidden stayed true and attributes stayed `34`. Foreign Hidden+ReadOnly `.so`/`.dylib` files retained bytes and attributes. The Hidden+ReadOnly `winhttp.dll` control preserved bytes/flags without Steam handoff; the original executable reproduced access denial without handoff. Tests used a disposable HTTP world and recording Steam stub.
- Linux DEB, RPM, and TGZ each passed **13 real 2.0.18 → 2.0.19 upgrade/removal checks**. Executables extracted from all three and the Flatpak staging executable matched SHA-256 `a69c8a08c97be0f2519b07e13ba8fcd97ea5acfbdbd27313bf685ee067861b73`.
- Flatpak passed **42 package**, **88 runtime/browser**, **46 native pass-through**, and **16 upgrade** checks.
- [Native macOS build/validation 44634732509](https://github.com/brianmiller/phvalheim-client/actions/runs/44634732509): **SUCCESS**. Both exact TGZ and PKG artifacts were downloaded into `builds/`. Reviewed results passed **15/15 checks in each of four candidate installation scenarios**, **7/7 URL-handler checks in each of three phases**, and exact installed-payload comparisons. Runtime validation ran on Apple Silicon; both Intel and ARM slices were signed.
- [Post-publication validation 44635781414](https://github.com/brianmiller/phvalheim-client/actions/runs/44635781414): **SUCCESS**, all **15 jobs** at `eb9e90540658aa07ed390df3b196b0e839b0e43a`. Coverage includes public macOS upgrades from 2.0.15 and 2.0.18, native macOS installation/URL handling, four Windows upgrades, the full wizard and published MSI ledger, all 11 oracle suites, bundle integrity, and the Linux-cross-built macOS executable running on actual Apple Silicon.

## What has not been tested

This evidence covers builds, prepublication candidate validation, and post-publication
verification of all nine public assets: seven packages, `macinstall.sh`, and `SHA256SUMS`.
All were downloaded without authentication; all eight checksum checks passed, and
public asset metadata hashes matched the exact candidate bytes. The Windows MSI was
not rebuilt with the Linux and macOS packages (asset ID `769423762`). Post-publication CI completed successfully with all 15 jobs passing.
No Intel Mac runtime validation was performed.

For [issue #25](https://github.com/brianmiller/phvalheim-client/issues/25), the affected
player confirmed gameplay after manually clearing Hidden flags in the original
installation. **Live gameplay with the corrected MSI has not been tested.** No actual
Valheim gameplay validation was performed; the Steam stub verifies handoff only.
The corrected MSI's resolution of that player's failure and real antivirus/Controlled
Folder Access behavior remain unverified.

## Build details

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
[Source PR #28](https://github.com/brianmiller/phvalheim-client/pull/28) remains unmerged. The numeric `2.0.19` tag remains at
[`6204fe1103f8c7f5e26bcd833e84d16e8cf2dc33`](https://github.com/brianmiller/phvalheim-client/commit/6204fe1103f8c7f5e26bcd833e84d16e8cf2dc33)
and does not identify the corrected builds.

Fresh Linux DEB/RPM/TGZ/Flatpak source is
[`2a1f673e1940c121173aea0e10e2b8e4cd4e4006`](https://github.com/brianmiller/phvalheim-client/commit/2a1f673e1940c121173aea0e10e2b8e4cd4e4006), with runtime source identical to `1d6d7c9`.
Fresh native macOS TGZ/PKG source is
[`ed63f413275d7520e7ca038d64581b86be8aef5c`](https://github.com/brianmiller/phvalheim-client/commit/ed63f413275d7520e7ca038d64581b86be8aef5c), differing from the Linux build revision only in workflow configuration.

The original MSI is preserved at immutable Git commit
[`3e63990b7877d5eade2a88ccc53e4003b7e02282/builds/phvalheim-client-2.0.19-x86_64.msi`](https://github.com/brianmiller/phvalheim-client/blob/3e63990b7877d5eade2a88ccc53e4003b7e02282/builds/phvalheim-client-2.0.19-x86_64.msi).
The corrected MSI explicitly upgrades the original ProductCode
`3783EF6D-25B9-4A61-9518-BE79B530643A` to `9ED226DE-BDBE-4D21-A0F3-C0422155FA22`.
Unknown same-version products and newer versions remain blocked. The MSI retains
the existing self-signed publisher certificate; Windows may show an unknown publisher.
