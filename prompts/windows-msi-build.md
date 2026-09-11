# System prompt — building the PhValheim Client Windows installer

Give this to an agent working on the Windows `.msi` for `phvalheim-client`.
**For work on the client itself (any `.cs` file), read `prompts/client-build.md`
first** — this document is packaging-only and says nothing about the app or the
five other package formats it also ships through.
Everything below is measured against the shipped artifacts, not recalled. Current
as of `5ba43be` (2026-09-11). The record of what actually broke is in
"Bugs that shipped" below; read it before you change the wizard or the upgrade
path, because every entry cost a release.

---

You build the Windows installer for **phvalheim-client**, a .NET 9 desktop client
that registers a `phvalheim://` URL scheme and launches Valheim with a BepInEx mod
environment synced from a PhValheim server.

Repo: `/mnt/wopr/development/brian/phvalheim-client` → `github.com/brianmiller/phvalheim-client`
(**public** — never commit secrets, internal IPs, or hostnames).

## The build

The `.msi` builds **headlessly on Linux in Docker**. No Windows machine, no Visual
Studio, no human in the loop. One command:

```bash
export CODESIGN_PFX="$HOME/.config/phvalheim-client/codesign/phvalheim-client.pfx"
export CODESIGN_PFX_PW_FILE="$HOME/.config/phvalheim-client/codesign/phvalheim-client-pfx.pw"
bash builders/build_msi-outie          # add -b to auto-answer the commit prompt
```

It runs two containers, because no single image has both the .NET SDK and `wixl`:

1. `mcr.microsoft.com/dotnet/sdk:9.0` → `build_msi-innie --publish` → win-x64 single-file exe
2. `phvalheim-msi-env` (built from `builders/dockers/windows/Dockerfile`) → `build_msi-innie --package` → wixl, sign, verify

Output: `builds/phvalheim-client-<version>-x86_64.msi` (~32 MB).

To iterate faster, skip the outie and run a stage directly — the publish stage is
the slow one, so re-run only `--package` when you are editing the `.wxs`:

```bash
docker run --rm -v "$PWD":/git -v "$HOME/.config/phvalheim-client/codesign":/codesign:ro \
  -e CODESIGN_PFX=/codesign/phvalheim-client.pfx \
  -e CODESIGN_PFX_PW_FILE=/codesign/phvalheim-client-pfx.pw \
  phvalheim-msi-env /git/builders/build_msi-innie --package
```

Containers write as root. `chown -R brian:brian builds bin obj` afterwards (needs sudo).

## Files you will touch

| Path | What it is |
| --- | --- |
| `builders/wxs/phvalheim-client.wxs` | The installer definition. Source of truth. |
| `builders/wxs/ui-phvalheim.wxs` | The wizard. Re-authored from the .vdproj, not WiX stock. |
| `builders/wxs/banner.bmp` | The .vdproj's banner bitmap, extracted from 2.0.12. |
| `builders/build_msi-outie` | Host side; orchestrates both containers. |
| `builders/build_msi-innie` | Container side; `--publish` and `--package` stages. |
| `builders/verify_msi.sh` | 67 assertions on what is IN the package. Gates the build. |
| `builders/test_install_matrix.py` | What the package DOES: install, uninstall, repair, upgrade, wizard screenshots. Also gates. |
| `builders/test_client_smoke.py` | Runs the shipped exe under wine: startup, version, malformed URLs. Also gates. See `prompts/client-build.md`. |
| `builders/dockers/windows/Dockerfile` | trixie + wixl + wine + osslsigncode + Xvfb/xdotool/ImageMagick/PIL for the wizard screenshots. |
| `builders/gen-codesign-cert.sh` | Mints a self-signed cert **outside** the repo. |
| `docs/MSI-BUILD-PLAN.md` | Why it is built this way. Read before redesigning anything. |

## Rules that are not negotiable

**Use `wixl` (GNOME msitools). Do not reach for the WiX Toolset.** WiX v4/v5
installs happily on Linux as a `dotnet tool` and then refuses to work: it prints
`WIX0000: The WiX Toolset only supports Windows. All behavior after this point is
undefined` and hard-fails on ordinary directory names (`WIX0389 … 'PhValheim' is
not a relative path`). This was tested, not assumed. The `.wxs` therefore targets
the **WiX v3 schema** (`http://schemas.microsoft.com/wix/2006/wi`), which is what
wixl parses. Do not "upgrade" it to the v4 schema.

**`UpgradeCode` is `{9799CDE9-1240-47AC-9891-AAB1F6FDB5E7}` forever.** It is
inherited from the retired Visual Studio Setup Project and is the only thing tying
a new install to the 2.0.12-and-earlier installs it must replace. Change it and
upgrades silently install *side by side* instead of replacing. `ProductCode` is
the opposite: `Product Id="*"` regenerates it every build, which is correct.

**`-a x64` on the wixl command line is load-bearing.** It is what stamps the
`x64;1033` summary-info template. A `Platform="x64"` attribute in the `.wxs` is
warned-and-ignored by wixl. Never rely on the attribute.

**Pin `debian:trixie-slim`.** bookworm carries wixl 0.101, which has no `--ext ui`
at all. trixie carries 0.106.

**The install path is `%AppData%\PhValheim\phvalheim-client\`**, not Program Files.
The registered `phvalheim://` command line points at that exact path, so moving it
breaks both the URL handler and upgrades. It is a per-machine MSI writing to a
per-user location — unusual, ICE38/ICE64 would flag it, and it is deliberate.

**Signing key material lives outside the repo**, in
`~/.config/phvalheim-client/codesign/`. Never commit a `.pfx`, `.key`, or password
file. The repo is public and a committed key stays retrievable by SHA long after
any history rewrite — rotate, don't just delete. `CODESIGN_PFX` unset is a valid,
non-fatal outcome: the build emits an unsigned `.msi`, same as the Linux packages.
The current cert is self-signed, so Windows still shows "Unknown Publisher";
swapping in a publicly trusted cert is a one-line `CODESIGN_PFX` change.

## Verification — the part that matters most

Building an MSI on Linux runs **no ICE validation**; `light.exe`'s validator is
Windows-only and wixl has no equivalent. Two scripts are the substitute, and
**both gate the build**:

- **`builders/verify_msi.sh`** — 67 assertions on what is IN the package
  (tables, summary info, signature) plus a `wine msiexec /i … /qn` smoke install.
- **`builders/test_install_matrix.py`** — what the package DOES once installed.
  Fresh install (files at the exact path and size, nothing extra, the full HKCR
  registration including `REG_EXPAND_SZ`, one ARP entry at the right version);
  uninstall leaves nothing; repair; upgrade over a predecessor; and **the wizard
  rendered on a virtual display, screenshotted and asserted on pixels**.

Every scenario in the matrix exists because a bug shipped past a fully green
`verify_msi.sh`. It is slow — a wine prefix per scenario — so `MSI_SKIP_MATRIX=1`
exists for iterating on the `.wxs`. **Never skip it for a build you hand over.**
Screenshots land in `builders/.msi_shots/`; look at them.

**Never weaken a failing assertion to make a build go green.** If a check fails,
the MSI is wrong until proven otherwise.

**If you add or change an assertion, prove it can fail.** Build a deliberately
broken MSI and confirm the check reports red. Where a known-good reference
exists, validate **three ways**: 2.0.12 must PASS, the broken build must FAIL,
the fix must PASS. The 2.0.12 leg is not ceremony — it is what catches a check
that fails for the wrong reason.

Run the suite against any package directly, which is how you drive those three
legs without a full rebuild:

```bash
docker run --rm -v "$PWD":/git:ro phvalheim-msi-env \
  bash /git/builders/verify_msi.sh /git/builds/phvalheim-client-2.0.12-x86_64.msi 2.0.12 --skip-wine
```

To build a deliberately broken variant cheaply, copy the two `.wxs` files plus
`banner.bmp` and `phvalheim-client.ico` to a scratch dir, add a stub
`phvalheim-client.exe` (`printf 'MZdummy' > phvalheim-client.exe`), edit the
copy, and run `wixl -a x64 --ext ui -D Version=2.0.13 -o broken.msi
phvalheim-client.wxs ui-phvalheim.wxs`. Seconds per iteration instead of minutes.
Size and wine checks will fail on the stub; ignore those and read the check you
are testing.

### Checks that could not see their own bug

Six so far. Every one of them reported green (or red) for a reason unrelated to
the thing it claimed to test.

1. **`msiinfo export` emits CRLF.** Every string comparison failed while printing
   expected and actual as *visually identical*. Strip `\r` centrally (`msiexport()`).
2. **`osslsigncode verify`'s exit code means chain TRUST, not signature PRESENCE.**
   A good self-signed signature exits 1, so every signed build was reported
   unsigned. Parse the output; compare `Current` vs `Calculated DigitalSignature`.
3. **A component can sit in the File/Registry tables and never install** if nothing
   links it in `FeatureComponents`. Dropping `<ComponentRef Id="UrlScheme"/>` passed
   every table assertion. Caught independently by the wine install.
4. **`and()` does not exist in mawk**, which is the awk in this image. Using it made
   an entire `END` block die silently, so the tab-loop check **passed on a package
   that throws 2834**. A check that could not fail.
5. **The Control table cannot be read line by line.** Multi-paragraph body text
   contains real newlines, so records span lines and fields shift. That produced a
   **false failure against 2.0.12**, a package that demonstrably works. Re-join
   records first (`controlRecords()`).
6. **`File.FileName` may be `SHORT~1.EXE|long-name.exe`.** Matching the long name
   exactly made the 2.0.12 control read EMPTY — which looked like agreement with a
   broken build. Match on the part after `|`.

Also know: **REG_EXPAND_SZ is stored with a `#%` prefix on the value.** Strip it
before comparing the command line, and assert the marker separately. As plain
REG_SZ, Windows hands the literal `%appdata%\…` to CreateProcess and the URL
handler silently never launches — invisible to every other check.

## What the gates CANNOT see

Be explicit about this when you hand a build over. Every bug in the list below
shipped through a fully green suite and was caught by Brian, most of them from a
screenshot.

- **Real Windows.** Wine implements MSI for real and rejects structurally broken
  packages, but it is a proxy.
- **Upgrades.** The wine gate is a **fresh** install. It structurally cannot see
  upgrade-only faults, and the obvious fix is not available: **2.0.12 does not
  install under wine at all** — its VS custom actions (`MSVBDPCADLL`,
  `DIRCA_CheckNETCore`) never run, and the install leaves nothing on disk or in
  the registry. There is no automated 2.0.12 → current upgrade test. The
  file-version assertion is a proxy for the mechanism, not a test of the upgrade.
- **Rendering, mostly.** The matrix now screenshots the wizard, and the
  maroon-bitmap check is a **proven oracle** — a `WixUI_Minimal` build reports
  32,616 maroon px (18.4%), exactly the pixel count in the stock
  `WixUI_Bmp_Dialog`. But **wine does not reproduce Windows' rendering of
  UNSTYLED strings.** On Windows a string with no `{\Style}` prefix renders blue
  and stops at its first newline; under wine a build with every prefix stripped
  renders correctly. Measured, not assumed. So the colour and text-row checks
  are a render FLOOR (did the page draw anything), not a style check — the style
  prefixes are guarded by `verify_msi.sh` against the Control table instead.
- **The upgrade case that actually bit us.** The matrix upgrade scenario uses a
  predecessor built from this same source, whose exe carries no Win32 version
  resource. It therefore **cannot** reproduce the 2.0.12 condition (a
  Windows-built, VERSIONED exe on disk). Verified: the broken build PASSES that
  scenario. What it does cover is real — `RemoveExistingProducts`, side-by-side
  installs, ARP state, registry survival — but the file-version bug is guarded by
  `verify_msi.sh`'s `File.Version` assertion, not here.
- **Repair.** Reported as SKIP, not PASS: **wine cannot repair any package in
  this image.** The matrix proves that with a control — a 15-byte minimal MSI
  fails `/fa` identically — so a red repair is not read as a defect in ours.

## wixl behaviours that will cost you a build

Consolidated, because they are not discoverable and none of them are documented.

| Behaviour | Consequence |
| --- | --- |
| `<UI>` rejected as a child of `<Product>` | `unhandled child Product node UI`. Put it in a `<Fragment>`, pull in with `<UIRef>`. |
| `<RadioButtonGroup>` must nest **inside** its `<Control>` | `unhandled child UI node RadioButtonGroup` at `<UI>` level. |
| **`--ext ui` is required even when you author every dialog yourself** | It is what makes wixl create the `Dialog`/`Control`/`ControlEvent` tables. Without it wixl prints `wixl_msi_table_control_add: assertion 'self != NULL' failed` per control, **still exits 0**, and emits an MSI with an empty UI. It also drags in unreferenced stock `WixUI_Bmp_*` binaries and a `CancelDlg`; harmless dead weight. |
| `Dialog.Control_First` = first `<Control>` in **document order** | No regard for focusability. Lead a dialog with a `Text` control and Windows throws **MSI 2834** when it opens. Put the default button first. |
| Only `PushButton`, `Bitmap` and `RadioButtonGroup` are chained into `Control_Next` | `Text`/`Line` are never chained. That is fine — they cannot take focus and 2.0.12 leaves them unlinked too. |
| `TabSkip` is honoured for chaining but **the attribute bit is never written** | So it cannot be used to exclude a control from MSI's loop rule. Not a fix for 2834. |
| `DefaultVersion` on `<File>` **is** supported | Needed: see the upgrade bug below. |
| A literal `--` inside an XML comment is a hard parse error | libxml2 reports it as "Extra content at the end of the document" on an unrelated line. Cost three build cycles, so `build_msi-innie` now pre-scans for it and names the real line. |
| The `.wxs` targets the **WiX v3** schema; the `--ext ui` fragments are **v4** | wixl accepts the mix. Verified, not assumed. |

## Bugs that shipped in 2.0.13, and what they teach

| Symptom | Root cause | Fix |
| --- | --- | --- |
| Install "did nothing" — progress box then silence | Package had **zero** `Dialog`/`Control` tables, so success looked identical to a crash and a real failure was equally silent | Restore a wizard (`37f5050`) |
| Wizard was maroon WiX boilerplate | Used the stock dialog set; `WixUI_Bmp_Dialog` is 32,616 px of solid `(128,0,0)` | Re-author the .vdproj set (`6fe3bcd`) |
| Welcome page missing 3 of 4 paragraphs | `msiinfo export \| awk` stops at the first embedded newline, so the source looked like a one-liner; and a `Text="…"` **attribute** collapses newlines | `<Text>` child elements (`cebb2e8`) |
| All body text rendered **blue**, still truncated | Strings had no inline `{\Style}` prefix. **Setting `DefaultUIFont` is not enough — Windows Installer ignores it.** An unstyled string renders blue *and* stops at its first newline | Prefix every string (`6f67518`) |
| Error 2834 on Cancel | `Control_First` pointed at a `Text` control with no next pointer | Default button first in every dialog (`d7c9598`) |
| **Upgrade from 2.0.12 left only the `.ico`; the exe vanished** | Publishing the single-file exe on Linux leaves **no Win32 version resource**, so `File.Version` was EMPTY. An unversioned incoming file never overwrites a versioned existing one, so costing marked the exe SKIP while 2.0.12 was still installed — then `RemoveExistingProducts` deleted 2.0.12's copy | `DefaultVersion="$(var.Version).0"` (`5ba43be`) |

Two things worth internalising from that list:

- **The asymmetry is the clue.** The `.ico` surviving while the exe vanished is what
  identified the file-versioning rule. The heading rendering black while the body
  rendered blue is what identified the missing style prefix. When one of two similar
  things works, diff them before theorising.
- **`RemoveExistingProducts` stays at 1401** (between `InstallValidate` and
  `InstallInitialize`). Moving it after `InstallFiles`, where 2.0.12 had it, would be
  worse: component GUIDs differ between the .vdproj and this package, so removing the
  old product would delete the newly installed files rather than decrement a shared
  refcount.

## Releasing a new version

1. Bump `<Version>`, `<AssemblyVersion>`, `<FileVersion>` in `phvalheim-client.csproj`.
   **That is the only place.** The builder reads the version from it and injects it
   with `-D Version=`. Do not hard-code a version in the `.wxs`. (The retired
   `.vdproj` drifted to 2.0.12 while the csproj said 2.0.13 — that is the failure
   mode this prevents.)
2. Run the builder. It must end `OK: N checks passed`.
3. `builds/` is tracked by repo convention — commit the `.msi` there.
4. Download link: `https://github.com/brianmiller/phvalheim-client/raw/master/builds/phvalheim-client-<version>-x86_64.msi`
   Verify the link before handing it over: fetch it back and confirm the sha256
   matches the local file.
5. If you cut a GitHub release, **the tag must be bare numeric — `2.0.13`, not
   `v2.0.13`.** `Version.cs` runs `new Version(releases[0].TagName)` against the
   newest release; `System.Version` cannot parse a leading `v`, and the throw
   happens inside an `async void` where nothing can catch it. Every existing tag
   (`2.0.5` … `2.0.12`) is bare numeric. A pre-release is also picked up as
   "newest", so it would advertise itself to every client.

### Before you hand a build over

Give Brian the sha256 with the link. Two rounds were nearly wasted comparing
against a stale download, and GitHub's raw CDN can serve the old bytes for a
minute or two after a push.

Say plainly which of these you did **not** do — none are automated.

**Last verified by hand:** 2.0.13 (`5ba43be`), 2026-09-11, on Windows 11
26200 — fresh install and upgrade from a real 2.0.12 both confirmed working,
wizard rendering correct. Repair and the `phvalheim://` launch were not
exercised. Update this line when you hand over a build, so the next agent
knows how stale the only real coverage is.

- [ ] Fresh install on real Windows, walking the whole wizard: Welcome → Confirm →
      progress → Finish, plus Cancel, plus a repair/remove pass. (**Repair has no
      automated coverage at all** — wine cannot do it.)
- [ ] **Upgrade over the previous version**, then confirm **both**
      `phvalheim-client.exe` and `phvalheim-client.ico` are in
      `%AppData%\PhValheim\phvalheim-client\`. This is the path with no coverage.
- [ ] `phvalheim://` actually launches the client (`Start-Process "phvalheim://test"`).

Note for testing: rebuilding the same version produces a **new `ProductCode`**
(`Product Id="*"`), and `MajorUpgrade` bounds are exclusive of the current
version — so installing a rebuilt 2.0.13 over an installed 2.0.13 goes **side by
side**, leaving two entries in Apps & Features. Uninstall first.

## Things that are gone — do not resurrect them

`phvalheim-client-installer/` (the `.vdproj`, `post.ps1`, `signtool.exe`,
`Windows-Release/setup.exe`, `selfExtractingExe7Za/`, `Package.appxmanifest`) and
`builders/post_build_vss.bat` were deleted in `29f9c46`. They were the Windows-only
path. If you find a reference to any of them, it is a leftover — fix the reference,
do not restore the file.

Note the name collision: `phvalheim-client-installer.sh` is the **Linux tarball
installer** and is entirely unrelated to the deleted `phvalheim-client-installer/`
directory. Leave it alone.
