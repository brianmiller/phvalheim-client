# MSI error 2814 on Repair / Remove — SOLVED

**Status: root cause found and fixed 2026-09-23.** Install always worked;
Repair and Remove from the wizard died with "The installer encountered an
unexpected error installing this package... The error code is 2814."

Keep this file. Most of the effort here went into theories that were wrong, and
the way they were wrong is the useful part.

---

## Root cause

The dialogs were scheduled **relatively** in `builders/wxs/ui-phvalheim.wxs`:

```xml
<Show Dialog="WelcomeForm"     Before="ProgressForm"  Condition="NOT Installed" />
<Show Dialog="MaintenanceForm" Before="ProgressForm"  Condition="Installed AND ..." />
<Show Dialog="ProgressForm"    Before="ExecuteAction" />
```

**wixl's relative-sequence resolver is not stable.** From byte-identical
authoring it produced two completely different orderings on two builds:

| action | 09-21 build (2814) | 09-22 23:44 build (works) |
|---|---|---|
| WelcomeForm | **1** | 1202 |
| MaintenanceForm | **2** | 1201 |
| ProgressForm | **3** | 1203 |

At 1/2/3 every dialog runs *before* `CostInitialize` (800), `FileCost` (900),
`CostFinalize` (1000) and `MigrateFeatureStates` (1200).

A fresh install tolerates that, which is why install was never affected. The
maintenance path cannot: `MaintenanceForm` sets `Reinstall`, `Remove` and
`ReinstallMode`, and with costing scheduled *after* the dialog those properties
land on a product whose feature states have not been migrated or costed.

## The fix

1. **Absolute sequence numbers, pinned** in `ui-phvalheim.wxs` — 1201 / 1202 /
   1203, which keeps all three dialogs between `MigrateFeatureStates` and
   `ExecuteAction` no matter how wixl resolves things on a given day. wixl
   honours `Sequence=` on `<Show>`; verified in the rebuilt package.
2. **A gate in `builders/verify_msi.sh`** asserting each dialog's sequence is
   greater than `CostFinalize` and `MigrateFeatureStates` and less than
   `ExecuteAction`.

The gate was tested against the known-bad package **first**: 3 FAILs on the
09-21 MSI, 3 PASSes on the working one. A check that passes on both proves
nothing, and that is exactly how this shipped green.

## How it was found

Not by reasoning about 2814 — by **diffing a broken package against a working
one**. `builds/*.msi` is tracked in git, so every historical revision is
retrievable:

```bash
git log --oneline -- builds/phvalheim-client-2.0.13-x86_64.msi
git show <sha>:builds/phvalheim-client-2.0.13-x86_64.msi > /tmp/old.msi
```

Comparing all 43 tables, only four differed: `File` and `MsiFileHash` (the exe
changed), `Property` (a new `ProductCode`), and **`InstallUISequence`**. The
new `ProductCode` GUID is the likely reason wixl's resolution order shifted.

**Have a known-good and a known-bad artifact and diff them.** That took one
command and beat two sessions of reading the spec.

## Wrong theories — all measured, all dead

Every one of these was checked against the actual bytes with
`dev_tools/msi_rawtable.py`, which parses the MSI OLE compound document
directly (string pool, `_Columns` schema, column-major blobs) and can print a
cell's **raw string-pool reference** — the one thing `msiinfo export` cannot
show, since it renders NULL and `""` identically.

- **Orphan / empty-string `Control_Next`.** MaintenanceForm's four orphans are
  genuine NULL (ref=0), zero empty strings. The queued "make them NULL" fix was
  a no-op against the bytes. And `WelcomeForm` carries **five** NULL nexts while
  rendering fine on every install, so NULL was never the variable.
- **`TabSkip`.** wixl never sets the TABSKIP bit either way; setting it made
  things worse. The `.wxs` stays at `"no"`.
- **Bitmap in the tab chain.** `ProgressForm`'s working chain also contains
  `BannerBmp`.
- **RadioButtonGroup.** Property default, RadioButton rows, attributes and
  geometry all match 2.0.12.
- **Everything else:** 0 dangling `Control_Next` across 78 controls / 10
  dialogs; 0 dangling `Control_First`/`Default`/`Cancel`; all 10 tab cycles
  close back to `Control_First`; 0 dangling refs from ControlEvent /
  ControlCondition / EventMapping; both font tokens defined in `TextStyle`;
  `Dialog.Attributes` identical to 2.0.12.

**The Control and Dialog tables were byte-identical between the package that
produced 2814 and the package that works.** Every static theory above was
chasing something that never differed.

The lesson: 2814's documented text ("the control names a nonexistent control as
the next control") pointed hard at `Control_Next`, and that was a blind alley.
The error surfaced in a dialog, but the defect was in *when the dialog ran*.

## Dead ends — do not repeat

### `msibuild -i` cannot rewrite the Control table

It **segfaults (exit 139)** on any table with an embedded newline, and does so
*silently* — the table is left untouched, so a round-trip check reports
"unchanged, therefore clean". That is a false pass; a no-op and a success look
identical to any check that only asserts sameness. Importing only the
newline-free dialogs rewrites the whole table anyway and mangles the
multi-paragraph text: 12 of 67 verify checks failed.

### wine cannot observe this bug at all

`MigrateFeatureStates` is **InstallUISequence 1200** and `MaintenanceForm` is
**1201**. Wine dies at 1200 with its own `Error 2726: Action not found:
MigrateFeatureStates` — one action *before* the dialog is ever created. The
whole maintenance log is 23 lines and a `/fa` repair logs nothing. A clean wine
run says nothing here. (`xauth` is missing, so drive `Xvfb :99` directly, not
`xvfb-run`.)

## The gate gap that let it ship

`test_install_matrix.py` has a full-UI `scenario_wizard` on Xvfb, but it runs
against a **fresh** prefix, so it renders WelcomeForm — `MaintenanceForm` is
never rendered by any check. `scenario_repair` and `scenario_uninstall` use
`/qn`, and silent mode never builds a dialog. The new sequence gate covers the
specific defect; a maintenance-wizard scenario is still worth adding, and will
trip over wine's 2726 first.

## Parsing notes

- `msiinfo export` puts **real newlines inside `Text` fields**, so a row is not
  a line. Reassemble by tab count (`Control` has 12 columns / 11 tabs) or you
  invent fake dialogs named after fragments of body text.
- MSI stream names are mangled into U+3800..U+484F. **U+4840 is the
  table-stream marker and is not in the 64-char alphabet** — strip it or every
  lookup misses.
