# Plan: build the Windows `.msi` headlessly on Linux (2.0.13)

> Status: plan, not yet executed. All feasibility claims below were verified on wopr
> on 2026-09-11 against the real 72 MB `2.0.13` `win-x64` binary — see "Evidence".

## Why the current build fails

`phvalheim-client-installer/phvalheim-client-installer.vdproj` is a **Visual Studio Setup
Project**. `.vdproj` is not an MSBuild project: it can only be built by `devenv.exe` with the
*Microsoft Visual Studio Installer Projects* extension, on Windows, interactively. There is no
CLI, no Linux port, and no unattended path. `builders/post_build_vss.bat` and
`phvalheim-client-installer/scripts/post.ps1` are the Windows-only tail of that flow — post.ps1
also shells out to `scripts/signtool.exe` and `move`s the result into `builds/`.

So the `.msi` is the only artifact in the project that cannot be produced by the existing
docker `outie`/`innie` builders. It has to be re-authored in a format a Linux toolchain can build.

## What the installer actually does

The `.vdproj` is much simpler than its size suggests. Extracted in full:

| Aspect | Value |
| --- | --- |
| Payload | exactly 2 files: `phvalheim-client.exe`, `phvalheim-client.ico` |
| Install dir | `%AppData%\PhValheim\phvalheim-client\` (`AppDataFolder` → `PhValheim` → `phvalheim-client`) |
| ProductName | `PhValheim Client` |
| Manufacturer | `Phospher` |
| **UpgradeCode** | **`{9799CDE9-1240-47AC-9891-AAB1F6FDB5E7}`** — must be preserved verbatim or upgrades over 2.0.12 break |
| ProductCode | regenerated per release (`RemovePreviousVersions` = TRUE) |
| Scope | `InstallAllUsers` = TRUE → `ALLUSERS=1` |
| Platform | x64 (`TargetPlatform` = `3:1`) |
| ARP | `ARPCONTACT` = `posixone`, `ARPPRODUCTICON` = the `.ico` |
| Registry | `HKCR\phvalheim` default = `PhValheim Client`; `HKCR\phvalheim\URL Protocol` = `""`; `HKCR\phvalheim\shell\open\command` default = **REG_EXPAND_SZ** `"%appdata%\PhValheim\phvalheim-client\phvalheim-client.exe" "%1"`; plus two empty valueless keys `HKLM\Software\Phospher` and `HKCU\Software\Phospher` |
| Shortcuts | **none** |
| Custom actions | **none** (`EvaluateURLs` in the binary is a standard MSI action) |
| UI | stock VS `VsdBasicDialogs.wim` wizard — no custom dialogs |

Nothing here needs a Windows-only feature. It is a two-file, one-registry-component MSI.

## Toolchain decision

Two candidates were tested end to end:

**Rejected — WiX Toolset v5 as a `dotnet tool`.** WiX v4/v5 is .NET-based and *installs* fine on
Linux, but every invocation prints `warning WIX0000: The WiX Toolset only supports Windows …
All behavior after this point is undefined`, and the build then fails outright on ordinary
directory names (`error WIX0389: The Directory/@Name attribute's value, 'PhValheim', is not a
relative path`). Not viable, regardless of what the "cross-platform" marketing implies.

**Chosen — `wixl` from GNOME msitools.** A native C MSI writer with its own CAB compressor,
packaged in Debian. It consumes WiX **v3** schema (`http://schemas.microsoft.com/wix/2006/wi`).
It built the real installer in ~2 s.

Pin **`debian:trixie-slim` (wixl 0.106)**, not bookworm (0.101): 0.106 adds `--ext ui`, which is
what preserves an install wizard. 0.101 silently has no `UIRef` support at all.

## Plan

### Phase 1 — author `builders/wxs/phvalheim-client.wxs`
WiX v3 source reproducing the table above. Points to fix relative to the PoC:
- `Product/@Id="*"` (new ProductCode per build), `UpgradeCode` hard-coded to the value above.
- `<MajorUpgrade>` — replaces `RemovePreviousVersions` + `DetectNewerInstalledVersion`.
- Stable, hard-coded component GUIDs (never `*` for the registry component) so upgrades
  correctly replace rather than duplicate.
- Do **not** put `Platform="x64"` on `<Package>` — wixl 0.101/0.106 warns and ignores it.
  Pass `-a x64`; that is what stamps the `x64;1033` summary template.
- `Version` injected as a preprocessor variable (`-D Version=…`), **read from
  `phvalheim-client.csproj`** so csproj stays the single source of truth. (Note: the `.vdproj`
  still says `2.0.12` while the csproj says `2.0.13` — that drift is exactly what this removes.)
- Add `builders/wxs/License.rtf`. `--ext ui` requires `WixUILicenseRtf`; without it the build
  dies with `Couldn't find file License.rtf`.

### Phase 2 — `builders/build_msi-outie` + `build_msi-innie`
Mirror `build_deb-outie`/`-innie` exactly (same `gitRoot` discovery, same `docker run -v
"$gitRoot":/git` shape) so it is one more peer builder, not a special case.

`build_msi-innie` does, in order:
1. `dotnet publish -c Windows-Release -r win-x64 -p:PublishSingleFile=true --self-contained true`
   in `mcr.microsoft.com/dotnet/sdk:9.0` (the host only has SDK 8.0.130; the 9.0 image is already
   pulled on wopr). This removes the current dependency on a stale hand-built `.exe`.
2. `wixl --ext ui -a x64 -D Version=$ver -o builds/phvalheim-client-$ver-x86_64.msi` in
   `debian:trixie-slim`.
3. Optional signing — see Phase 4.

Two base images means either a two-stage `docker run`, or one small `builders/dockers/windows-msi/Dockerfile`
that layers `wixl` onto `sdk:9.0`. Prefer the Dockerfile: it matches the existing `dockers/debian`
and `dockers/fedora` pattern and keeps the innie a single container.

### Phase 3 — verification (the part that makes "without my intervention" honest)
Building an MSI on Linux means **no ICE validation runs** — `light.exe`'s validator is
Windows-only. Without a substitute, a silently malformed MSI ships. Two gates:

1. **Table assertions** (`builders/verify_msi.sh`): `msiinfo` out of the same container, asserting
   the exact shipped contract — `Template: x64;1033`; `UpgradeCode` == `{9799CDE9-…}`;
   `ALLUSERS`==1; `ARPPRODUCTICON` set; `File` table holds both files at the expected sizes;
   `Registry` table holds all three `HKCR\phvalheim` rows with the command row typed
   **expandable**. Each assertion fails the build on mismatch.
2. **Wine smoke install** — `wine msiexec /i out.msi /qn` in the container, then assert
   `drive_c/users/*/AppData/Roaming/PhValheim/phvalheim-client/phvalheim-client.exe` exists and
   the `HKCR\phvalheim\shell\open\command` value is present in wine's registry. Wine implements
   MSI for real, so it rejects a structurally broken package — this catches the class of failure
   the table assertions cannot see. It does *not* prove the client runs on real Windows; nothing
   available here does. That residual risk is stated, not hidden.

Both gates must be able to fail. Before trusting them, run each once against a deliberately
broken MSI (wrong UpgradeCode, dropped registry row) and confirm it reports red.

### Phase 4 — signing (opt-in, unchanged semantics)
`post.ps1` signed with `signtool.exe` + a PFX from `CODESIGN_PFX` / `CODESIGN_PFX_PW[_FILE]`.
On Linux the equivalent is `osslsigncode sign -in … -out …` (supports MSI). Keep the same env
var names and the same behavior: if `CODESIGN_PFX` is unset, skip signing and emit an unsigned
MSI — do not fail the build. The PFX lives on a Windows share and is not reachable from this
pipeline, so **the default headless output will be unsigned**, same as the Linux packages.
This is the one place a later decision from you is genuinely needed.

### Phase 5 — retire the dead Windows path
Only after Phase 3 passes: delete `phvalheim-client-installer/` (`.vdproj`, `post.ps1`,
`signtool.exe`, `Windows-Release/setup.exe`, `selfExtractingExe7Za/`, `Package.appxmanifest`),
drop `builders/post_build_vss.bat` and the `Windows-Release` `PostBuildEvent` from the csproj,
and update `README.md` + `CONTEXT.md` (which is still dated 2026-03-18 / v2.0.12). Keeping the
`.vdproj` around after cutover just invites the two version numbers to drift apart again.

## Evidence (measured on wopr, 2026-09-11)

Against `bin/Windows-Release/net9.0/win-x64/publish/phvalheim-client.exe` (72,145,539 bytes) and
`phvalheim-client.ico`, `wixl 0.101` produced a **33,034,240-byte** MSI in ~2 s — within 3% of the
shipped `phvalheim-client-2.0.12-x86_64.msi` (32,195,072 bytes), confirming the CAB compressor
works. Verified in the output: `Template: x64;1033`; `UpgradeCode
{9799CDE9-1240-47AC-9891-AAB1F6FDB5E7}`; auto-generated `ProductCode`; `ALLUSERS 1`;
`ARPPRODUCTICON phvalheim.ico`; `ARPCONTACT posixone`; `ProductVersion 2.0.13`; both files in the
`File` table at correct sizes; `Icon` table populated; `Upgrade` table carrying both
`WIX_UPGRADE_DETECTED` and `WIX_DOWNGRADE_DETECTED` rows; all three `HKCR\phvalheim` registry rows
at `Root 0`. `wixl 0.106` on trixie additionally accepted `--ext ui`.

## Risks

- **No ICE validation on Linux.** Mitigated by Phase 3, not eliminated.
- **No real-Windows install test exists in this pipeline.** Wine is a proxy. First 2.0.13 MSI off
  this builder should get one manual install on a real Windows box before it goes to a release —
  that is a one-time check, after which the builder is unattended.
- **UI fidelity.** `WixUI_Minimal` is not a byte-match for the VS `VsdBasicDialogs` wizard.
  Functionally equivalent (license → progress → finish), visually different. If that matters,
  `WixUI_InstallDir` is closer; if it doesn't, dropping `--ext ui` entirely gives a clean
  progress-bar-only install.
- **Per-machine MSI writing to `AppDataFolder`** is what ships today and is deliberately
  preserved. It is unusual (ICE38/ICE64 would flag it) and means the install lands in the
  installing user's roaming profile. Changing it would break upgrades from 2.0.12; out of scope.
