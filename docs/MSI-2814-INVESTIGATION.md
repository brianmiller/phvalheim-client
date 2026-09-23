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

## REFUTED 2026-09-23: the orphan / empty-string theory is dead

`dev_tools/msi_rawtable.py` (new) parses the MSI's OLE compound document
directly — string pool, `_Columns` schema, and the column-major table blobs —
so it can print the **raw string-pool reference** of every cell. That is the one
thing `msiinfo export` cannot show: ref 0 is NULL, a non-zero ref pointing at
`""` is an empty string.

```bash
python3 dev_tools/msi_rawtable.py builds/phvalheim-client-2.0.13-x86_64.msi \
        Control Dialog_=MaintenanceForm
```

Result on the broken package: **4 NULL (ref=0), 0 empty-string.** The four
orphans were already NULL. The proposed fix ("make those cells NULL") was a
no-op against the actual bytes.

And the decisive control: **`WelcomeForm` has FIVE NULL `Control_Next` cells and
renders perfectly during a working install.** `ProgressForm` has eight. A NULL
next is normal and harmless, exactly as the MSI docs say. Orphan count was never
the variable.

## Everything else the static tables can be wrong about — all measured clean

All on 2.0.13, all reproducible with `msi_rawtable.py`:

| check | result |
|---|---|
| `Control_Next` naming a control absent from its dialog | **0** dangling, all 78 controls / 10 dialogs |
| `Dialog.Control_First` / `Control_Default` / `Control_Cancel` dangling | **0** |
| Tab cycle walked from `Control_First` closes back to it | **10 / 10 dialogs** |
| `ControlEvent` / `ControlCondition` / `EventMapping` naming a missing control | **0** |
| Font tokens `{\PhvFontNormal}` / `{\PhvFontTitle}` defined in `TextStyle` | both defined (2.0.12 actually had 2 *undefined* ones and shipped fine) |
| `RadioButtonGroup` property has `RadioButton` rows | yes, 2 rows, geometry sane |
| `MaintenanceForm_Action` has a default in `Property` | `'Repair'`, same as 2.0.12 |
| `Dialog.Attributes` (Visible/Modal/Minimize) vs 2.0.12 | byte-identical; ProgressForm modeless in both |

Two further hypotheses killed by the same data:

- **Bitmap-in-the-tab-chain.** wixl chains `BannerBmp`, which looked wrong — but
  `ProgressForm`'s chain also contains `BannerBmp` and ProgressForm renders on
  every successful install.
- **RadioButtonGroup is the odd one out.** It is the only control type unique to
  MaintenanceForm's chain, but its `Property`, `RadioButton` rows, attributes
  and geometry all match 2.0.12.

**Conclusion: no static defect in the UI tables explains 2814.** Either Windows
enforces a rule not modelled here, or the failing control is one that exists in
the table but is not *created* at runtime. Static analysis has been exhausted;
the next evidence must come from Windows.

## What will actually settle it

Error 2814's message embeds the three things we are missing — the dialog, the
control, and the name it could not resolve. One verbose log prints them:

```
msiexec /i phvalheim-client-2.0.13-x86_64.msi /l*v %USERPROFILE%\Desktop\maint.log
```

Run that on a machine where 2.0.13 is **already installed**, pick Repair or
Remove, let it fail, then search the log for `2814`. The line reads
`On the dialog <X> the control <Y> names a nonexistent control <Z>`.

Without it we are guessing; with it the fix is mechanical.

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

`MigrateFeatureStates` is a standard action wine does not implement. Re-run
2026-09-23 and measured precisely this time: `MigrateFeatureStates` is
**InstallUISequence 1200**, and `MaintenanceForm` is **1201**. Wine dies one
action *before* the dialog is created — the entire maintenance log is 23 lines,
and a subsequent `/fa` repair logs nothing at all. Wine therefore cannot observe
2814 even in principle. A clean wine run says **nothing** about this bug; do not
read one as confirmation or refutation.

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
