**2.0.19 is a prerelease for testing**, for Windows, Linux (DEB, RPM, TGZ, Flatpak) and macOS.
This broader revision handles Hidden mod configuration, player-setting preservation
and sync records as well as loader/backend files, addressing
[issue #25](https://github.com/brianmiller/phvalheim-client/issues/25).
Live Valheim gameplay with this revision remains unverified.

**PUBLISHED — broader revision, November 20, 2026.** Seven packages were replaced;
`macinstall.sh` is unchanged. All nine public downloads, fetched without authentication,
are byte-identical to the release files, including `SHA256SUMS`; all eight checksum
entries passed.
**2.0.18 remains stable**, including normal installer and “latest” links.

### Already installed 2.0.19?

**Redownload and reinstall your 2.0.19 package on every platform**. The version and
filenames are unchanged. Verify SHA-256 against the table
below before installing: the new and previous MSIs are both **32,899,072 bytes**, so
size cannot distinguish them. Native upgrades from both earlier 2.0.19 ProductCodes
are verified for this exact MSI.

For an existing RPM installation, explicitly replace the same-version package:

```bash
sudo rpm -Uvh --replacepkgs ./phvalheim-client-2.0.19-x86_64.rpm
```

## Downloads and SHA-256

These are the **published broader revision** sizes and hashes. All eight entries in the release
[SHA256SUMS](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/SHA256SUMS)
passed against the unauthenticated public downloads, which match the release files byte for byte.

| Platform / format | Artifact | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| Windows MSI | [phvalheim-client-2.0.19-x86_64.msi](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-x86_64.msi) | 32,899,072 | `6816a959190a3a4eedbd5fbe4cab15348c9fc10c8345699f9c098d8e8b611ab5` |
| Linux DEB | [phvalheim-client-2.0.19-x86_64.deb](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-x86_64.deb) | 23,605,832 | `7d4e2233a124702c54c6fb31feaea22b205bfad6ae8586f2471a9e49d2ad1740` |
| Linux RPM | [phvalheim-client-2.0.19-x86_64.rpm](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-x86_64.rpm) | 25,715,981 | `af17b34c63a1c242345f1674b09e58c0574aeac3c29a546aeb0463a0ce9fe1b9` |
| Linux TGZ | [phvalheim-client-2.0.19-universal-x86_64.tar.gz](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-universal-x86_64.tar.gz) | 31,442,762 | `3f956daa86f0c0a4b1b59545bf600afdf8c4245be6fd029aeb9601a9cc42d77a` |
| Linux Flatpak | [phvalheim-client-2.0.19-x86_64.flatpak](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-x86_64.flatpak) | 23,330,920 | `4356e8698004915512403cc6bd61a9085bb1b417e1d77c1b49460c07a80fe2d5` |
| macOS universal TGZ (primary) | [phvalheim-client-2.0.19-macos-universal.tar.gz](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-macos-universal.tar.gz) | 61,777,898 | `d0279d41ccaa7aea0f80d2e5a64449be77f6af1f5f10677be2a9df86c58fc24b` |
| macOS universal PKG (supplementary) | [phvalheim-client-2.0.19-macos-universal.pkg](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-macos-universal.pkg) | 61,781,848 | `b62d282b165030b5a424e8e5752ca1ea8d6bb6d1643e73850863c0c2e65bbdb3` |
| macOS shell installer | [macinstall.sh](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/macinstall.sh) | 9,355 | `13c8894e2d76e0cebb1a6b097c7dbbd175a420175a134c65d2374299f748d925` |

macOS uses the shell installer plus universal TGZ as its primary installation method;
the PKG is supplementary. The normal installer selects stable 2.0.18.
Download the installer and tarball into the same folder, verify their hashes above,
and explicitly select the 2.0.19 tarball:

```bash
curl -fLO https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/macinstall.sh
curl -fLO https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-macos-universal.tar.gz
PHVALHEIM_TARBALL=./phvalheim-client-2.0.19-macos-universal.tar.gz bash ./macinstall.sh install
```

For Linux DEB and TGZ, follow the [README installation commands](https://github.com/brianmiller/phvalheim-client#installation)
with version `2.0.19`; for RPM use the replacement command above. For Flatpak:

```bash
flatpak install --user --reinstall ./phvalheim-client-2.0.19-x86_64.flatpak
```

On Windows, run the downloaded MSI.

## What changed

Windows managed writes now handle Hidden files during mod-config policy enforcement,
personal-setting application and preservation, and sync-record updates, in addition to
`winhttp.dll`, `doorstop_config.ini` and `phvalheim.backend`. Existing-file overwrites
preserve Hidden attributes and existing ACLs. Personal config retains Hidden through
staged updates; sync records and game-directory loader files also retain Hidden.
A full world regeneration recreates cache/backend files with fresh metadata, so their
previous Hidden flags are not expected to survive that lifecycle.

The client does not scan for and unhide files, reset permissions, clear ReadOnly, or
request elevation. ReadOnly still aborts protected updates; a genuinely denied backend
write still aborts launch. Reparse-point destinations are rejected. Managed writes stage
contents before replacement; failed staging preserves the original. Staging does not
guarantee protection against external races or power loss.

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

## Published revision validation

- [Native actual-client source validation 44643769336](https://github.com/brianmiller/phvalheim-client/actions/runs/44643769336): **SUCCESS**. All **11** Hidden-file targets passed, with a published-executable negative control and a ReadOnly control. This is source validation, not validation of the new MSI.
- [Full source CI 44648623221](https://github.com/brianmiller/phvalheim-client/actions/runs/44648623221): **all 15 jobs succeeded**.
- Published MSI local validation: **81 structural**, **24 executable smoke**, and **36 Wine behavior** checks passed. Wine repair was **SKIPPED**; native Windows repair **PASSED**.
- [Exact packaged Windows validation 44647729127](https://github.com/brianmiller/phvalheim-client/actions/runs/44647729127): the [11-target Hidden-file actual-client fixture](https://github.com/brianmiller/phvalheim-client/actions/runs/44647729127/job/135994488959) and [previous-correction 2.0.19 migration, 14 checks](https://github.com/brianmiller/phvalheim-client/actions/runs/44647729127/job/135994489071) both **SUCCEEDED**. Upgrades from **2.0.12 through 2.0.18**, native repair, the wizard and negative control also **SUCCEEDED**. The initial workflow **failed overall only in the original 2.0.19 migration job**, because of a COM test-harness bug.
- [Targeted native Windows rerun 44649449411](https://github.com/brianmiller/phvalheim-client/actions/runs/44649449411) at `47790c96adac024cb7f2d6f66bf49e2795c5fcd5`: **SUCCESS**, with **14 original-2.0.19 migration checks** and **20 installer-condition cases**. It tested the same unchanged MSI (`6816a959…`), completing the native Windows gate and verifying migration from both known 2.0.19 predecessors.
- Linux DEB, RPM and TGZ each passed **13 upgrade/removal checks from stable 2.0.18**. Same-version 2.0.19 DEB and TGZ reinstalls each passed **13** checks; RPM reinstall with `--replacepkgs` passed exact-binary verification.
- Flatpak passed **42 package**, **88 runtime/browser**, **46 native pass-through**, **16 stable-2.0.18 upgrade**, and **16 prior-2.0.19 upgrade** checks.
- [Native macOS validation 44646602998](https://github.com/brianmiller/phvalheim-client/actions/runs/44646602998): **SUCCESS**, with **15 checks in each of four candidate installation scenarios** and **7 URL-handler checks in each of three phases**. Native execution was **Apple Silicon only**.

## Validation limits

No Intel Mac runtime validation or actual Valheim gameplay validation was performed.
No Bazzite-specific validation is claimed.
Recording Steam/game stubs establish handoff only, not live gameplay or graphics behavior.
The affected player's earlier gameplay confirmation followed manually clearing Hidden
flags; it does not establish that this revision resolves their failure. Real antivirus
and Controlled Folder Access behavior remain unverified.

## Build provenance and superseded candidates

The version remains **2.0.19**. Runtime source is
[`9d4c1fbb8db2cf1a4476f6cb05c113764c1fefe5`](https://github.com/brianmiller/phvalheim-client/commit/9d4c1fbb8db2cf1a4476f6cb05c113764c1fefe5).
Windows, Linux and macOS binaries were built from
[`4314ddedcea800e1faea9be330f401c66c8d3490`](https://github.com/brianmiller/phvalheim-client/commit/4314ddedcea800e1faea9be330f401c66c8d3490),
whose runtime source is identical to `9d4c1fb`. MSI packaging source is
[`c821d1f0b29aab59c16ca440a0e74e82588bc70c`](https://github.com/brianmiller/phvalheim-client/commit/c821d1f0b29aab59c16ca440a0e74e82588bc70c).
The new packaged executable SHA-256 is
`72e717f34381ea04246fdd695e8e6119dba1c16eaf9ab2972072683507017ca8`.

[Source PR #28](https://github.com/brianmiller/phvalheim-client/pull/28) remains unmerged.
The numeric `2.0.19` tag is unchanged at
[`6204fe1103f8c7f5e26bcd833e84d16e8cf2dc33`](https://github.com/brianmiller/phvalheim-client/commit/6204fe1103f8c7f5e26bcd833e84d16e8cf2dc33)
and does not identify the replacement builds. Stable 2.0.18 and `master` are unchanged.

All three MSI candidates use `phvalheim-client-2.0.19-x86_64.msi`:

| Candidate | Bytes | ProductCode | MSI SHA-256 |
| --- | ---: | --- | --- |
| Original (superseded) | 32,886,784 | `3783EF6D-25B9-4A61-9518-BE79B530643A` | `7e48a17e1b9921360ffeaab77d34cea1b7243ac3eb4e0ac0a569b4f0432dc488` |
| Previous correction (superseded) | 32,899,072 | `9ED226DE-BDBE-4D21-A0F3-C0422155FA22` | `260c78168955438b03d7b0684a83990db76c82dcf4de59c05820abacee4e949a` |
| Broader revision (published November 20) | 32,899,072 | `1C3D3C32-C803-499D-ABAD-1DEB717AFED3` | `6816a959190a3a4eedbd5fbe4cab15348c9fc10c8345699f9c098d8e8b611ab5` |

Immutable copies: [original MSI at 3e63990](https://github.com/brianmiller/phvalheim-client/blob/3e63990b7877d5eade2a88ccc53e4003b7e02282/builds/phvalheim-client-2.0.19-x86_64.msi)
and [previous MSI at 2a1f673](https://github.com/brianmiller/phvalheim-client/blob/2a1f673e1940c121173aea0e10e2b8e4cd4e4006/builds/phvalheim-client-2.0.19-x86_64.msi).
The published MSI retains ProductCode `1C3D3C32-C803-499D-ABAD-1DEB717AFED3`;
native upgrades from both superseded ProductCodes passed with this exact package.
Unknown same-version products and newer versions remain blocked. It retains the
existing self-signed publisher certificate; Windows may show an unknown publisher.

The previous correction's executable SHA-256 was
`d692bf7312e2a6fc307af47406110e0c592fab3c3a57ea98e5bf9aa80de4fec1`,
built from [`1d6d7c93c8dc4c58a6ca6d4401b3075e6837ecb7`](https://github.com/brianmiller/phvalheim-client/commit/1d6d7c93c8dc4c58a6ca6d4401b3075e6837ecb7).
Its Linux packages came from
[`2a1f673e1940c121173aea0e10e2b8e4cd4e4006`](https://github.com/brianmiller/phvalheim-client/commit/2a1f673e1940c121173aea0e10e2b8e4cd4e4006)
with identical runtime source; its native macOS packages came from
[`ed63f413275d7520e7ca038d64581b86be8aef5c`](https://github.com/brianmiller/phvalheim-client/commit/ed63f413275d7520e7ca038d64581b86be8aef5c),
differing only in workflow configuration. Historical
[native file validation 44619866045](https://github.com/brianmiller/phvalheim-client/actions/runs/44619866045),
[installer validation 44620112640](https://github.com/brianmiller/phvalheim-client/actions/runs/44620112640),
[actual-client validation 44622099219](https://github.com/brianmiller/phvalheim-client/actions/runs/44622099219),
[native macOS validation 44634732509](https://github.com/brianmiller/phvalheim-client/actions/runs/44634732509)
and [post-publication validation 44635781414](https://github.com/brianmiller/phvalheim-client/actions/runs/44635781414)
refer to those superseded packages, not this broader revision. The old installer run
had a failing Hidden-file fixture; the later actual-client run covered its corrected
loader/backend payload.
