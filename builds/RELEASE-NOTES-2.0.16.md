**Pre-release.** This build is published for players who want to try the Linux changes below
before they become the recommended client. Two things follow from that: the client's own
"a newer version is available" check and your server's web page download buttons both skip
pre-releases, so nothing will nudge anyone toward this build and your server will keep
offering 2.0.15 until 2.0.16 is promoted. Get it from this page. Nothing in it needs a
particular server version.

Three things, all Linux. The Windows and macOS packages carry no code change beyond the
version number; they are published so that every platform is on one version.

## What changed

### Modded launches on Linux have the Steam overlay

A vanilla launch goes through Steam (`steam -applaunch`), so Steam sets the game up itself and
Shift+Tab works. A modded launch cannot: BepInEx has to be injected through the environment,
so the client starts `valheim.x86_64` directly, and Steam never sees the game start and never
injects its overlay. That is why the overlay worked in a vanilla world and not in a modded one,
which is what players on Bazzite reported.

Steam's injection is nothing more than environment variables, so the client now sets the same
ones on a modded launch: Steam's `gameoverlayrenderer.so` on the game's `LD_PRELOAD`, after
doorstop, and Valheim's app id in the three names the overlay looks for. Doorstop first, then
the overlay, is the order every BepInEx-on-Steam Linux user already runs, because BepInEx's own
`run_bepinex.sh` prepends doorstop to the `LD_PRELOAD` that Steam handed it.

Details that decide whether this is safe to ship on every machine:

- **The library is only named when it exists.** If `<steam root>/ubuntu12_64/gameoverlayrenderer.so`
  is not on disk the launch is exactly what 2.0.15 did, and the console says why the overlay was
  skipped. A path that does not exist must never go on `LD_PRELOAD`: the loader complains at
  exec and the game starts anyway, which is the worst kind of warning.
- **Only the 64-bit library.** Steam preloads both the 32- and 64-bit ones. Valheim is x86_64;
  the 32-bit one would print "wrong ELF class" into the console on every launch for nothing.
- **Opt-out without waiting for a release:** `PHVALHEIM_NO_OVERLAY=1` in the client's
  environment. The overlay has a history of crashing games on some Mesa and Wayland
  combinations; a player hit by that keeps playing. For the Flatpak client:
  `flatpak override --user --env=PHVALHEIM_NO_OVERLAY=1 com.phvalheim.Client`.
- **Steam must already be running**, as it always had to be. The client starts it if it is not
  and waits ten seconds; if that race is lost the overlay silently does nothing. Unchanged
  behaviour, now visible.
- The overlay hooks GLX and X11 Vulkan surfaces. Valheim runs under XWayland on a Wayland
  desktop, so it works there; a forced Wayland-native SDL would not get it.
- A Flatpak Steam uses the same code (the Steam root is under
  `~/.var/app/com.valvesoftware.Steam`), but that launch path remains untested on real
  hardware, as `docs/FLATPAK.md` has said since it was written.

The stub launch rigs that run on every Flatpak build now pin the exact `LD_PRELOAD` string
(order included) and the three Steam ids, and the native rig proves the guard by deleting the
stub library and by setting the opt-out, checking that both leave `LD_PRELOAD` as doorstop
alone and print the reason.

`PHVALHEIM_VERBOSE=1` now prints every variable the game is launched with, including the
overlay path. The old verbose list named two variables the client never set and printed
"(unset)" for them on every run.

### The Flatpak moves to the 25.08 runtime

Flathub marked `org.freedesktop.Platform 24.08` end-of-life on 2026-10-03, and Bazaar had
started showing "Stopped Receiving Core Updates" on our listing. The 2.0.16 bundle is built on
and declares 25.08. Nothing to do on your side: installing the bundle pulls 25.08 from Flathub,
and the old runtime stays until `flatpak uninstall --unused`.

### Bazaar may show an old version, and that is Bazaar

Bazzite's app store can show this app's detail page at one old version and its Library row at
another after you install a newer bundle. The bundles are correct (each of 2.0.13, 2.0.14 and
2.0.15 was unpacked and checked); Bazaar keeps its own cache of each app's AppStream entry and,
for an app installed from a bundle rather than a remote, never refreshes it. `flatpak info
com.phvalheim.Client` and Warehouse show the installed version. Bazaar's Refresh fixes the
display, or delete `~/.cache/io.github.kolunmi.Bazaar`.

## Upgrading from 2.0.15

Every package here was installed OVER the published 2.0.15 package, by the package manager a
player would use, and the result was run and read back. Each path has a control that feeds the
rig the old package as the "new" one and requires it to fail.

| Client | How to upgrade | Verified |
|---|---|---|
| Debian / Ubuntu `.deb` | `sudo dpkg -i phvalheim-client-2.0.16-x86_64.deb` | `builders/verify_linux_upgrade.sh deb`, in the Debian build image |
| Fedora `.rpm` | `sudo dnf install ./phvalheim-client-2.0.16-x86_64.rpm` (or `rpm -U`) | `builders/verify_linux_upgrade.sh rpm`, in the Fedora build image |
| Universal tarball | extract, `sudo ./phvalheim-client-installer.sh install` | `builders/verify_linux_upgrade.sh tgz` |
| Flatpak | `flatpak install phvalheim-client-2.0.16-x86_64.flatpak` — no `--reinstall` needed, the commit and runtime both move | `builders/verify_flatpak_upgrade.sh`, bundle over bundle, 24.08 → 25.08 |
| Windows `.msi` | run the installer | CI: `msiexec` upgrade from each of 2.0.12, 2.0.13, 2.0.14 and 2.0.15, plus the full wizard clicked |
| macOS | `macinstall.sh install`, or the tarball | CI: 2.0.15 installed by its own installer, then this build installed over it on Apple Silicon |

The Windows and macOS legs run against the published assets on this page, so their result
is in this release's CI run rather than in a log on a build machine.
