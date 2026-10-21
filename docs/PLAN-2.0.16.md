# PhValheim Client 2.0.16 — plan

Status (2026-10-21): items 1-3 IMPLEMENTED in the working tree, uncommitted. Local
flatpak build on 25.08 passed all three gates (42 package + 51 runtime + 27 native
checks, including the two overlay mutation controls). Test bundle for Mitch at
`/mnt/wopr/development/brian/phv-2016-test/phvalheim-client-2.0.16-test-x86_64.flatpak`
(built from this tree, still reports 2.0.15 inside; install with `--reinstall`).
Version bump is Brian's call; nothing here changes `<Version>` until he says 2.0.16.
Do NOT run `build_flatpak-outie -b` for a test build: `-b` answers yes to "commit to
GitHub", which `git add builds/*` + pushes the rebuilt bundle under the OLD version
name (happened once; reverted in fc05351).

Master is ahead of the `2.0.15` tag by nine commits, all CI/test work (msi wizard
harness, macOS screenshots, camera fixes). 2.0.16 ships from master. Before tagging,
run `git merge-base --is-ancestor <fix-commit> <tag-commit>` for every item below —
2.0.15's tag once pointed at code missing every shipped fix.

## Scope

| # | Item | Why | Size |
|---|------|-----|------|
| 1 | Steam overlay on Linux modded launches | Reported by Mitch (Bazzite, system Steam). Modded Linux launches exec `valheim.x86_64` directly, so Steam never injects its overlay. Vanilla launches go through `steam://run`, which is why they have it. | medium |
| 2 | Flatpak runtime 24.08 → 25.08 | Flathub marked `org.freedesktop.Platform 24.08` end-of-life on 2026-10-03. Bazaar shows "Stopped Receiving Core Updates" on our listing. | small |
| 3 | Document the Bazaar stale-version display | Not our bug (Bazaar's groups cache never refreshes an entry for a bundle-installed app), but it will be reported again. One paragraph in FLATPAK.md + README, one line in release notes. | tiny |

Not in 2.0.16 unless Brian pulls it in: issue #15 (resync deletes client-only mod
data), the macOS SIGHUP detach (shipped in 2.0.15, still unverified on a real Mac).

## 1. Steam overlay

### What Steam does that we don't

When Steam starts a native Linux game it sets, in the game's environment:

- `LD_PRELOAD` gets `<steamroot>/ubuntu12_32/gameoverlayrenderer.so:<steamroot>/ubuntu12_64/gameoverlayrenderer.so`
  (appended after anything already there; the wrong-ELF-class one is rejected by
  ld.so with a stderr line and ignored).
- `SteamAppId`, `SteamGameId`, `SteamOverlayGameId` = the app id (`892970`). The
  overlay refuses to attach without a game id.
- `ENABLE_VK_LAYER_VALVE_steam_overlay_1=1` for the Vulkan layer path.

None of that is documented by Valve; it is what third-party launchers (LaunchHeim,
Hydra, MetalSharp) replicate and what BepInEx-on-Steam users get for free because
`run_bepinex.sh` runs *inside* Steam's environment and does
`LD_PRELOAD="libdoorstop_x64.so:$LD_PRELOAD"`. That last fact is the important one:
doorstop-first-then-overlay is the ordering every BepInEx Linux user on Steam already
runs, so the two preloads are known to coexist in that order.

Our `Launcher.cs` builds `doorstopEnv` with `LD_PRELOAD = libdoorstop_x64.so[:existing]`.
`existing` is always empty in practice: nobody launched *us* from Steam.

### Change (Launcher.cs, Linux modded branch only)

1. Resolve the overlay library: `Path.Combine(Platform.State.SteamDir, "ubuntu12_64", "gameoverlayrenderer.so")`.
   - Native Steam: `SteamDir` is `~/.steam/steam`, which is the symlink to the real root. Fine.
   - Flatpak Steam: `SteamDir` is `~/.var/app/com.valvesoftware.Steam/.local/share/Steam`
     on the host. The same string resolves inside Steam's sandbox too, because a
     Flatpak always sees its own `~/.var/app/<id>` dir. Our own sandbox can `File.Exists`
     it because the manifest already grants `--filesystem=~/.var/app/com.valvesoftware.Steam`.
   - Only the 64-bit library. Valheim is x86_64; adding `ubuntu12_32` would print
     `wrong ELF class: ELFCLASS32` into the console window on every launch for nothing.
2. If the file exists: `LD_PRELOAD = libdoorstop_x64.so:<overlay path>` and add
   `SteamAppId`, `SteamGameId`, `SteamOverlayGameId` (all `892970`) and
   `ENABLE_VK_LAYER_VALVE_steam_overlay_1=1` to `doorstopEnv`. Because both launch
   shapes (native `HostCommand` env dict, Flatpak-Steam `flatpak run --env=`) are fed
   from that one dictionary, one edit covers both.
3. If the file does not exist: leave `LD_PRELOAD` exactly as today and `Ui.Note` that the
   overlay was skipped and why. Never put a path that does not exist into `LD_PRELOAD`:
   ld.so complains at exec and the game still starts, which is the worst kind of warning.
4. Opt-out: `PHVALHEIM_NO_OVERLAY=1` skips step 2. Steam's overlay has a history of
   crashing games on some Mesa/Wayland combinations (steam-for-linux #9586); a user hit
   by that must still be able to play without waiting for a release.
5. Verbose output: add the three Steam vars and the overlay path to the existing
   `if (Ui.Verbose)` block.

Windows is untouched (`-applaunch` already goes through Steam, overlay present).
macOS is untouched in this release.

### Known limits, to state in release notes

- The overlay hooks GLX and X11 Vulkan surfaces. Valheim runs under XWayland on a
  Wayland desktop, so it works there; a forced Wayland-native SDL would not get it.
- Steam must be running. We already start it if it is not and sleep 10 s; the overlay
  silently does nothing if that race is lost. Unchanged behaviour, now visible.

### Oracles

Both stub rigs record the COMPLETE environment the stub `valheim.x86_64` received
(`builders/test_flatpak_runtime.py` `assert_valheim_env`, reused by
`builders/test_native_passthrough.py`). Extend them; both run in CI already.

- Stub Steam root grows `ubuntu12_64/gameoverlayrenderer.so` (an empty file is enough;
  the loader never runs in the stub).
- Assert the STIMULUS: `LD_PRELOAD` equals `libdoorstop_x64.so:<stub root>/ubuntu12_64/gameoverlayrenderer.so`
  exactly (order matters, assert the whole string, not `contains`), and
  `SteamOverlayGameId == SteamGameId == SteamAppId == 892970`.
- Mutation control 1: delete the stub overlay file → `LD_PRELOAD == libdoorstop_x64.so`
  and the Note is printed. This is the check that proves the guard exists.
- Mutation control 2: `PHVALHEIM_NO_OVERLAY=1` → same as control 1, Note differs.
- Flatpak-Steam shape is still not exercisable by the stub rig (documented in
  FLATPAK.md). The env goes through `--env=` from the same dictionary, so the native
  assertion covers the composition; it does not cover the path resolving inside
  Steam's sandbox.

### Real-world verification (the only proof that counts)

The stub cannot show an overlay. Before promoting:

1. Mitch, Bazzite, system Steam: Shift+Tab in a modded world. He is the reporter and
   has offered to test.
2. Mitch again with Flatpak Steam, if he is willing to switch: this is also the first
   time anyone will have run the Flatpak-Steam launch path at all (FLATPAK.md marks it
   UNTESTED). Two findings for one tester.
3. Ask for `PHVALHEIM_VERBOSE=1` output on the first run so the resolved path and vars
   are in the report, not inferred.

Ship as a pre-release first? No: the in-app download button skips pre-releases, so
Mitch would get 2.0.15 again (we have been bitten by this). Ship a real release, or
hand him the .flatpak asset URL directly for the test build.

## 2. Freedesktop runtime 25.08

Three places pin 24.08; change all three together or the verify fails the build:

- `builders/flatpak/com.phvalheim.Client.yml` `runtime-version: '24.08'`
- `builders/build_flatpak-innie` line 156, the `flatpak install ... //24.08` of Platform+Sdk
- `builders/verify_flatpak.sh` line 156, the marker `runtime is org.freedesktop.Platform 24.08`

Then run `builders/test_flatpak_runtime.py` against the new bundle: the .NET 9
self-contained binary needs the runtime's glibc/ICU/libssl to still satisfy it. 25.08
is newer in every respect so a break is unlikely, but the smoke run is the check,
not the reasoning. The outie's named docker volume `phvalheim-flatpak-cache` holds the
24.08 runtime; the innie's `--or-update` install will add 25.08 beside it. Nothing
to purge.

Users: nothing to do. `flatpak install` of the 2.0.16 bundle pulls 25.08 from Flathub
via the bundled `--runtime-repo`. The old runtime stays until `flatpak uninstall --unused`.

## 3. Bazaar version display

Facts established 2026-10-21 by unpacking all three shipped bundles:

- The 2.0.13, 2.0.14 and 2.0.15 bundles each carry their own version in the metainfo,
  the composed AppStream XML, and the ostree commit. Nothing stale ships.
- Bazaar persists a groups cache under `~/.cache/io.github.kolunmi.Bazaar` holding
  each app's AppStream entry and its installed-versions string. On start it only
  reconciles the installed *flag* against libflatpak. A bundle-installed app has no
  remote, so nothing ever rewrites the entry. Detail page shows the first version
  Bazaar ever saw (2.0.13), the Library row shows the last install it noticed
  (2.0.14). Warehouse asks libflatpak and is right.
- Remedy: Bazaar's Refresh, or delete that cache dir.

Add a "Bazaar shows an old version" entry under known issues in `docs/FLATPAK.md`
and the README's Flatpak section, and a line in RELEASE-2.0.16.md. The only code fix
on our side would be publishing a real Flatpak remote (then Bazaar would resync
appstream from it); that is a separate project and not planned.

## Release mechanics

Follow `prompts/client-build.md`. Reminders that bit us before:

- `build-all` git-pushes each artifact; a slow first format is a push backlog.
- `tgz`/`deb`/`rpm` outies ignore their innie's exit code: call those innies directly
  and check `builds/` yourself.
- macOS: `gh workflow run macos-verify.yml` builds it in CI; no Mac needed.
- `.msi`: `builders/msi_rebuild_guard.sh` refuses a rebuilt .msi under an already
  published version. Bump first, build once.
- Unpack EVERY artifact and check its version (the inspect approach from the Bazaar
  investigation works for the .flatpak: `ostree init --mode=bare-user-only`, set
  `core.min-free-space-percent 0`, `flatpak build-import-bundle`, checkout, grep).
- GitHub release as Latest, not pre-release. Server-side the Client Download fallback
  reads Latest.
- `CONTEXT.md` still says "Current Version 2.0.13"; update it.

## Order of work

1. Runtime bump (item 2) and verify marker, rebuild flatpak locally, run the runtime
   smoke test. Independent of everything else; do it first so the overlay work is
   tested on the runtime that will ship.
2. Overlay (item 1): code, then stub-rig assertions + controls, run native and flatpak
   rigs locally.
3. Docs (item 3), RELEASE-2.0.16.md, CONTEXT.md.
4. Hand Mitch a test bundle. Wait for Shift+Tab.
5. Brian calls the version. Build the set, verify every artifact, tag, release.
