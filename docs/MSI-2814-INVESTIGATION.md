# MSI error 2814 on Repair / Remove — open investigation

**Status: OPEN.** Install works. Repair and Remove from the wizard die with
"The installer encountered an unexpected error installing this package. This
may indicate a problem with this package. The error code is 2814."

Reported by Brian on real Windows against 2.0.13. Both features worked in
2.0.12, which was built by the retired Visual Studio Setup Project
(`phvalheim-client-installer.vdproj`). 2.0.13 is the first release built on
Linux with `wixl`, so the regression came in with that port.

This file exists because one session burned a lot of effort here and reached a
wrong fix. Read it before touching `builders/wxs/ui-phvalheim.wxs`.

---

## What 2814 actually is

From Microsoft's own error list (`MicrosoftDocs/win32`,
`desktop-src/Msi/windows-installer-error-messages.md`, the row for 2814):

> On the dialog [2] the control [3] names a nonexistent control [4] as the
> next control.

Note the exact claim: a control **names** a next control that does not exist.
It is about the `Control_Next` column of the `Control` table.

Do not take this from a search-result summary. Fetch the row:

```bash
gh api repos/MicrosoftDocs/win32/contents/desktop-src/Msi/windows-installer-error-messages.md \
  -H "Accept: application/vnd.github.raw" | grep -n "^| 2814"
```

## Established by measurement

Both MSIs are in `builds/`, so every claim below is reproducible.

1. **wixl chains only focusable controls.** It writes `Control_Next` for
   PushButton, RadioButtonGroup and Bitmap. Every `Text` and `Line` gets an
   EMPTY `Control_Next`.

2. **2.0.12 chains everything.** Its `MaintenanceForm` is one complete cycle
   over all nine controls, zero left out:

   ```
   FinishButton -> BannerText -> BannerBmp -> Line1 -> BodyText
     -> RepairRadioGroup -> Line2 -> PreviousButton -> CancelButton -> (Finish)
   ```

   2.0.13's is a five-control cycle plus four controls with an empty next.

3. **`TabSkip` cannot change this.** Measured both ways: wixl never sets the
   TABSKIP attribute bit (8) at all. Control `Attributes` come out
   byte-identical to 2.0.12's (1, 196611, 131075, 3) whether the authoring
   says `TabSkip="yes"` or `"no"`. Setting `"yes"` only drops the control out
   of the chain as well, taking MaintenanceForm from 4 orphans to 5. Strictly
   worse. The `.wxs` is back to `"no"` and should stay there.

4. **MaintenanceForm is the only dialog with a RadioButtonGroup.** That is the
   most obvious reason Repair/Remove is where it surfaces while a fresh
   install is fine, but it is a hypothesis, not a measured fact.

## What argues AGAINST the orphan theory

`builders/verify_msi.sh` already asserts *"every dialog's Control_Next forms a
single loop from Control_First"* — and that check **passes** on the broken
package. The loop reachable from `Control_First` is valid and closed; the
orphans sit outside it, unreferenced. Windows may never look at them.

So the orphans are suspicious but unproven. Treat the theory as open.

## The next thing to try

**Is `Control_Next` NULL, or an empty string?**

- NULL means "this control is not in the tab order". Legal, common, harmless.
- An empty string is a lookup for a control *named* `""` — which is precisely
  "names a nonexistent control" and would explain 2814 exactly.

`msiinfo export` renders both as a blank field, so it cannot tell them apart.
This needs the raw table bytes: read the MSI's OLE compound-document streams
and look at the `Control` table's string-reference for that column. A nonzero
string ref pointing at an empty string is very different from a zero ref.

If it turns out to be an empty string, the fix is to make those cells NULL,
and the question becomes how to do that without `msibuild`.

## Dead ends — already paid for, do not repeat

### `msibuild -i` cannot be used to rewrite the Control table

- It **segfaults (exit 139)** on any table containing an embedded newline, and
  does so *silently*: the table is left untouched. A naive round-trip check
  reports "unchanged, therefore clean", which is a false pass. Several dialogs
  here carry multi-paragraph body text with real newlines.
- Importing only the newline-free dialogs does **not** avoid it. msibuild
  rewrites the whole table even for a partial `.idt`, and the multi-paragraph
  text comes back mangled. Measured: **12 of 67 `verify_msi.sh` checks failed**,
  including `WelcomeText keeps its paragraph breaks` and
  `BodyText1 keeps its paragraph breaks`, on dialogs the script had skipped.

A post-build table rewrite therefore needs a different tool than msitools, or
must not touch `Control` at all.

### wine cannot adjudicate this bug

`wine` and `msiexec` ARE in `phvalheim-msi-env` and the maintenance path is
reachable there, but wine fails earlier with its own error:

```
DEBUG: Error 2726:  Action not found: MigrateFeatureStates
```

`MigrateFeatureStates` is a standard action wine does not implement. It only
runs on the maintenance path, so wine breaks in the same *place* Brian does,
with the same user-facing wrapper text, for an unrelated reason. Do not read a
wine run as confirmation or refutation of 2814.

Reproducing the wine run (`xauth` is missing, so drive Xvfb directly):

```bash
docker run --rm -v "$PWD/builds":/b:ro phvalheim-msi-env:latest bash -c '
export WINEPREFIX=/tmp/wp WINEDEBUG=-all XDG_RUNTIME_DIR=/tmp/xdg
mkdir -p /tmp/xdg && chmod 700 /tmp/xdg
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 & sleep 3
export DISPLAY=:99
wineboot -i >/dev/null 2>&1; wineserver -w
wine msiexec /i "Z:\\b\\phvalheim-client-2.0.13-x86_64.msi" /qn
timeout 90 wine msiexec /i "Z:\\b\\phvalheim-client-2.0.13-x86_64.msi" /l*v "C:\\ui.log"
cat /tmp/wp/drive_c/ui.log'
```

## The gate gap

`test_install_matrix.py` has a `scenario_wizard` that runs the wizard in FULL
UI on Xvfb and asserts on pixels, plus `scenario_repair` and
`scenario_uninstall`. But:

- `scenario_wizard` runs against a **fresh** prefix, so it renders
  WelcomeForm. `MaintenanceForm` needs an already-installed prefix and is
  therefore **never rendered by any check**.
- `scenario_repair` and `scenario_uninstall` use `/qn`. Silent mode never
  builds a dialog, so no UI-table defect can fail them.

That intersection is exactly where this bug lives, which is why it shipped
green. **A maintenance-wizard scenario — install, then run full UI on Xvfb and
screenshot MaintenanceForm — is the gate worth adding**, independent of the
fix. Note it will currently trip over wine's 2726 first.

## Comparing the two packages

```bash
docker run --rm -v "$PWD/builds":/b:ro phvalheim-msi-env:latest bash -c '
for v in 2.0.12 2.0.13; do
  echo "### $v MaintenanceForm: Control | Type | Attributes | next"
  msiinfo export /b/phvalheim-client-$v-x86_64.msi Control 2>/dev/null |
    awk -F"\t" "\$1==\"MaintenanceForm\"{printf \"  %-18s %-18s attr=%-10s next=%s\n\", \$2,\$3,\$8,\$11}"
done'
```

**A row is not a line.** `msiinfo export` writes real newlines inside `Text`
fields, so any parser must reassemble rows by tab count (the `Control` table
has 12 columns, so a complete row has 11 tabs). Splitting on newlines invents
fake dialogs named after fragments of body text, and that produced a whole
round of wrong numbers before it was caught.
