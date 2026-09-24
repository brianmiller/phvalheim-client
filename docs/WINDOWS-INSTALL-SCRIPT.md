# The Windows install script

`winstall.ps1` — a per-user Windows install, the counterpart to `macinstall.sh`.

**Status: UNTESTED on real Windows.** The static gate passes; nobody has run it
on a Windows machine yet. Do not put the one-liner in front of users until the
manual plan at the bottom of this file has been worked through.

## Why it exists

Not to replace the `.msi`. To dodge one specific screen.

Microsoft Defender SmartScreen's application-reputation check fires on files
carrying the **Mark of the Web** — the `Zone.Identifier` alternate data stream a
browser attaches to every download via `IAttachmentExecute`. Our `.msi` is
downloaded in a browser, so it always carries MOTW, so users get *"Windows
protected your PC"*.

Nothing about signing fixes that quickly. Microsoft's guidance is **"several
weeks and hundreds of clean installs from a wide audience"** — per *file hash*,
reset to zero on every release. Our numbers:

| Release | Windows installer downloads |
| --- | --- |
| 2.0.12 (6 months live) | 191 |
| 2.0.13 | 5 |
| all 2022–23 `.exe` releases | 44 |
| **lifetime** | **240** |

The best release we have ever shipped, given half a year, did not clearly clear
the bar once. The warning is effectively permanent on the browser-download path.

`Invoke-WebRequest` does not go through `IAttachmentExecute` and does not set
MOTW. A payload it fetches is unmarked, so the reputation check never runs. Same
mechanism as rustup, Scoop, Chocolatey and every other `irm … | iex` installer.

Be honest about what that is: avoidance, not trust. We are not tripping the
trigger rather than earning the reputation.

Installing per-user under `%APPDATA%` and `HKCU` needs no elevation, which also
removes the UAC *"Unknown Publisher"* prompt.

## What it does NOT fix

- **Antivirus heuristics** (issue #7). Unrelated mechanism, unaffected.
- **Smart App Control.** SAC checks every executable regardless of MOTW, so an
  unsigned binary is still blocked. On for clean Windows 11 installs only, but
  growing. Signing is the answer here, not this script.
- **The `.msi` itself.** Anyone who downloads it in a browser gets the warning
  exactly as before. This is an addition, not a replacement.

## How it works

The only Windows asset a release publishes is the `.msi`, so the script fetches
that — and never runs it. `msiexec /a` is an *administrative install*: it
unpacks the embedded cab to a directory, touches neither the live system nor the
installer database, and needs no elevation. The script then places the payload
itself.

That choice is deliberate. It means the script ships the exact binary the MSI
ships, with no second Windows build to publish and no way for the two to drift.

It reproduces, per-user, what `builders/wxs/phvalheim-client.wxs` does
per-machine:

| Thing | MSI | Script |
| --- | --- | --- |
| Payload | `%APPDATA%\PhValheim\phvalheim-client\` | same |
| URL scheme | `HKCR\phvalheim` | `HKCU\Software\Classes\phvalheim` |
| Command value type | `REG_EXPAND_SZ` | `REG_EXPAND_SZ` |
| ARP entry | Windows Installer | `HKCU\…\Uninstall\PhValheimClient` |
| Elevation | required | none |

`builders/verify_winstall.sh` asserts the first three still agree. They are a
contract with installs already on users' machines, not free choices.

### Migrating off the MSI

**The two cannot coexist.** Both write the same directory, but the MSI still
owns those files as far as Windows Installer is concerned — repairing it
overwrites the script's copy, uninstalling it deletes them and leaves the
script's registry entries pointing at nothing.

So an MSI install is **migrated, not coexisted with**: detected, removed, then
replaced. Two orderings are load-bearing and both are asserted by
`verify_winstall.sh`, because getting either wrong still reports success the
whole way through:

- The removal must happen **before** the payload is placed. The MSI's uninstall
  deletes files in that directory, so the other order removes the install that
  was just made.
- The removal must happen **after** the payload is downloaded and extracted. A
  failed download would otherwise leave the user with neither install — worse
  off than the working MSI they started with.

Removal runs `msiexec /x <ProductCode> /qn` elevated. **This is the one step
that needs administrator rights**, because the package is `InstallScope
perMachine`. It happens once, on migration only; afterwards updates and removal
need no elevation. The UAC prompt comes from Microsoft-signed `msiexec.exe`, so
it is the ordinary Windows Installer dialog rather than the "Unknown Publisher"
one the `.msi` itself raises.

The exit code is not trusted on its own — a silent uninstall that did nothing
and one that worked are indistinguishable from it, so the script re-queries the
registry and aborts if the MSI is still registered.

User data lives in the **parent** folder, `%APPDATA%\PhValheim`, and is untouched
by both the MSI uninstall and this script.

`-SkipMsiRemoval` leaves the MSI in place. That produces the broken coexistence
state on purpose and exists to test it; it is not a supported way to install.

## Usage

```powershell
# One-liner (this is the point of the whole exercise)
irm https://raw.githubusercontent.com/brianmiller/phvalheim-client/master/winstall.ps1 | iex

# With arguments — `iex` cannot take parameters, so it must become a scriptblock
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/brianmiller/phvalheim-client/master/winstall.ps1))) diags

# From a checkout
powershell -ExecutionPolicy Bypass -File winstall.ps1 install
powershell -ExecutionPolicy Bypass -File winstall.ps1 -Msi C:\path\to\phvalheim-client-2.0.13-x86_64.msi
powershell -ExecutionPolicy Bypass -File winstall.ps1 diags
powershell -ExecutionPolicy Bypass -File winstall.ps1 uninstall
```

`-Msi` is the local-testing hook, mirroring `macinstall.sh`'s
`PHVALHEIM_TARBALL`: everything after the extract is the code the real installer
runs, so a test exercises the shipped path rather than a test-only
reimplementation that drifts away from it.

## The static gate

```bash
bash builders/verify_winstall.sh
```

Runs in a `mcr.microsoft.com/powershell` container. Checks:

1. The script parses.
2. **The uninstaller the script generates parses.** That body is a here-string,
   invisible to check 1 — a quoting mistake there yields a perfectly valid
   `winstall.ps1` that writes a broken uninstaller, discovered only when someone
   tries to remove the product.
3. A negative control, so check 2 can be shown to be capable of failing.
4. PSScriptAnalyzer clean at Error/Warning.
5. No drift from the `.wxs` on install path, value type and the scheme command.

### What the gate cannot see

Everything that requires Windows. It has never executed a single line of the
install path. Specifically unverified: `msiexec /a` extraction, every registry
write, whether `phvalheim://` actually activates, the ARP entry's appearance,
the self-deleting uninstaller, and MOTW behaviour itself.

## Manual test plan

Needs a real Windows box with Steam and Valheim. Work top to bottom.

1. **Baseline the thing we are fixing.** Download the 2.0.13 `.msi` in Edge and
   run it. Confirm "Windows protected your PC" appears. Screenshot it. Without
   this, a later "no warning" proves nothing — it could just be a machine that
   never warns.
2. **Clean state.** Uninstall any existing PhValheim Client. Confirm
   `%APPDATA%\PhValheim\phvalheim-client` is gone and `HKCU\Software\Classes\phvalheim`
   is absent.
3. **Install from a local MSI** — `-Msi <path>`. Fastest way to find breakage
   without the network in the loop.
4. **`diags`.** Every line should be `[OK]`. It asserts the command value is
   `REG_EXPAND_SZ`, that the registered target exists, and that the client
   actually executes.
5. **Activate the scheme.** Click a real `phvalheim://` link from the server, and
   run `start phvalheim://test` from cmd. The client should receive the argument.
   This is the one the MSI has historically got wrong.
6. **ARP.** Settings → Apps → Installed apps. Name, version, publisher and icon
   present; Modify/Repair absent.
7. **Uninstall from ARP.** Confirm the directory, both registry trees, and the
   ARP row are all gone. Nothing orphaned.
8. **The one-liner, in anger.** Fresh machine or fresh user profile. Run the
   `irm | iex` form. **Confirm no SmartScreen prompt appears at any point** —
   this is the entire deliverable, and step 1 is what makes the result mean
   something.
9. **Upgrade.** Install, then install again over the top. Should succeed and
   leave one ARP row, not two.
10. **Migration — the big one.** Install the 2.0.13 `.msi` normally, confirm it
    works and that `phvalheim://` opens it. Then run the script. It should:
    - report the detected MSI version before doing anything,
    - raise exactly one UAC prompt, from Windows Installer,
    - remove the MSI (gone from Settings → Apps),
    - install the scripted copy and say it migrated,
    - leave `phvalheim://` working afterwards — **test the link again**, this is
      where a botched handover shows up,
    - leave any existing `%APPDATA%\PhValheim` config intact.
11. **Migration, rehearsed.** Run with `-WhatIf` against an MSI install first and
    confirm it reports what it would remove without removing it.
12. **Migration, declined.** Run the migration and click **No** on the UAC
    prompt. The MSI must still be installed and working, and the script must say
    clearly that nothing changed.
13. **Locked file.** Launch the client, leave it running, re-run install. It
    should name the running process, not emit an opaque sharing violation.

Record results here when done, including anything that failed.

## Open items

- Not wired into any CI. There is no Windows runner in this project; GitHub
  provides free `windows-latest` runners on public repos, so a workflow
  mirroring `macos-verify.yml` is possible and not yet written.
- The phvalheim.com download page is untouched by design — the script is not
  offered to users yet.
- No checksum verification of the downloaded `.msi` beyond HTTPS. Releases do
  not publish digests today; if they start to, verify one here.
