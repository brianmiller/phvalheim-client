# The Linux Flatpak

Requested in [phvalheim-server#86](https://github.com/brianmiller/phvalheim-server/issues/86):
a client that installs on SteamOS, Bazzite and other immutable gaming distros
where a `.deb` or `.rpm` is awkward or impossible.

The issue anticipated the hard part correctly — *"Possible issue: Flatpak apps
are sandboxed by default."* Most of this document is about that.

## Build it

```
builders/build_flatpak-outie          # -b to answer yes to the commit prompt
```

Nothing but Docker is needed on the host. Output:

```
builds/phvalheim-client-<version>-x86_64.flatpak
```

A single-file bundle, the counterpart of the `.deb`/`.rpm`/`.msi`. Users
install it with no remote configured:

```
flatpak install --user ./phvalheim-client-<version>-x86_64.flatpak
```

`FLATPAK_SKIP_RUNTIME_TESTS=1` skips the slow behavioural gate while iterating
on the manifest. Never for a build you hand over.

## Why this application cannot really be sandboxed

The client is not an application so much as an orchestrator. Everything it
does is about the host:

| Step | What it touches |
| --- | --- |
| find Steam | the host's `PATH` and `~/.steam` |
| find Valheim | `libraryfolders.vdf`, and a library that may be on any drive |
| sync a world | `~/.config/PhValheim`, shared with the `.deb`/`.rpm` installs |
| install doorstop | writes into the Valheim game directory |
| launch | execs `valheim.x86_64` on the host with a doorstop environment |

Running Valheim *inside* our sandbox would give it our runtime's libraries,
no GPU driver stack matched to the host, and no reachable Steam client. So the
sandbox is something to step out of, not to work within.

`flatpak-spawn --host` is the supported way out, and it requires
`--talk-name=org.freedesktop.Flatpak`. That permission is, by itself,
unrestricted host access. Combined with `--filesystem=home` this package is
honestly described as unsandboxed. It is not pretending otherwise, and the
manifest says so in a comment next to the permission.

## How the escape is implemented

`Flatpak.cs` is the whole of it. `Flatpak.HostCommand()` returns a
`ProcessStartInfo` that runs a command on the host when sandboxed and directly
when not, so **there is one code path**: the `.deb`, `.rpm` and `.tar.gz`
builds execute exactly the code they always did, and the Flatpak cannot drift
away from the packages already known to work.

Three call sites changed:

- `Platform.cs` — `command -v steam` must be answered by the host. The sandbox
  has its own `PATH` and its own `/usr`, so asked from inside it the answer is
  always "Steam is not installed".
- `Launcher.cs` — "is Steam already running?" Flatpak unshares the PID
  namespace, so `Process.GetProcessesByName` sees only us and always answers
  no. Left alone, a Flatpak would start a second Steam and sleep ten seconds
  on every single launch.
- `Launcher.cs` — the Valheim exec itself, plus the `gsettings` mutter tweak,
  which would otherwise write to the sandbox's own dconf where no compositor
  would ever read it.

### The environment is the subtle part

A command run through `flatpak-spawn --host` **does not inherit the sandbox's
environment**. It inherits the environment of the host's flatpak session
helper — the user's real session — plus whatever we pass explicitly with
`--env=`. This was measured, not assumed; getting it backwards is what led to
an early draft granting `--socket=x11` so `DISPLAY` could be "forwarded",
which was unnecessary. The game already gets the session's own `DISPLAY`,
`WAYLAND_DISPLAY` and `XAUTHORITY`, and those are the correct ones — our
copies are rewritten to sandbox-only paths and would be worse than nothing.

So the client passes **only the doorstop variables** and leaves everything
else alone.

That is a correction to an earlier design here, and the reasoning is worth
keeping because the instinct runs the other way. The worry was real enough:

> Inside the sandbox, `XDG_CONFIG_HOME` is `~/.var/app/com.phvalheim.Client/config`.
> **Valheim stores characters and worlds under `XDG_CONFIG_HOME`.** If that
> reached the game, every save a player made through the Flatpak would land
> inside our app directory — invisible to Valheim started any other way, and
> deleted when the Flatpak is uninstalled.

So an earlier version scrubbed `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `PATH`,
`XDG_DATA_DIRS`, the GLib module paths and `FLATPAK_ID` back to stock values.
Then the probe above showed the sandbox environment never arrives in the first
place — and that the scrub was **strictly worse than doing nothing**: it would
have overwritten the settings of anyone who deliberately relocates
`XDG_DATA_HOME` to another disk, silently moving where Valheim keeps its data.

The scrub is gone. `test_flatpak_runtime.py` asserts the *mechanism* directly
— that a variable set in the sandbox does not reach a host command — so that
if flatpak ever changes, the check fails and says the scrub is needed again,
rather than the leak reappearing silently.

Two traps this created in the *test rig*, both of which looked like product
bugs until measured:

- **Flatpak gives every app a private `/tmp`.** A fake Steam library placed
  there is invisible to the client, and `ValheimGetter` reports "Valheim not
  found". The test library now lives under `/run/media`, which also makes the
  Steam Deck SD-card permission a tested one rather than an assumed one.
- **`DISPLAY` must be exported before `dbus-run-session`.** The session
  helper is D-Bus activated with the bus daemon's activation environment,
  fixed when the bus starts. Export it later and the game launches with no
  display.

Two traps this created in the *test rig*, both of which looked like product
bugs until measured:

- **Flatpak gives every app a private `/tmp`.** A fake Steam library placed
  there is invisible to the client, and `ValheimGetter` reports "Valheim not
  found". The test library now lives under `/run/media`, which also makes the
  Steam Deck SD-card permission a tested one rather than an assumed one.
- **`DISPLAY` must be exported before `dbus-run-session`.** The session
  helper is D-Bus activated with the bus daemon's activation environment,
  fixed when the bus starts. Export it later and the game launches with no
  display.

`test_flatpak_runtime.py` asserts every one of these on the real environment a
stub Valheim receives, because this is exactly the class of bug that produces
no error message.

### Two flatpak-spawn details that cost time

- **`--directory=`, not `psi.WorkingDirectory`.** Setting the latter changes
  the directory of `flatpak-spawn` inside the sandbox, where the game path
  usually does not exist at all.
- **`--` before the command is load-bearing.** `flatpak-spawn` parses with
  GOption, which permutes arguments, so Valheim's `-console` is otherwise read
  as a `flatpak-spawn` flag and the spawn fails.

## Known limitations

- **A Flatpak Steam is detected and refused, not supported.** Its game files
  live inside its own sandbox and Valheim would have to be launched within
  that sandbox to get the Steam Runtime and a reachable client. The client
  prints a specific message naming `com.valvesoftware.Steam` and telling the
  user to install a system Steam, rather than failing as "Steam isn't
  installed". SteamOS and Bazzite both ship a system Steam, which is the
  configuration this targets.
- **The host's `LD_PRELOAD` is not read.** On the other packages the client
  appends doorstop to any existing `LD_PRELOAD`. From inside the sandbox there
  is no way to see the host session's value — a shell spawned through
  `flatpak-spawn` inherits *our* environment, not the host's. So a
  host-level `LD_PRELOAD` (a MangoHud or gamescope wrapper, say) is dropped
  for the Valheim process. Deliberate: the alternative was a fix that looks
  like it works and does not.
- **No LICENSE file exists in this repository**, so the AppStream metadata
  declares `LicenseRef-proprietary`, which is the only accurate value.
  **This blocks a Flathub submission**, which requires a real open-source
  licence. Add a `LICENSE` and change `project_license` together.
- The app id is `com.phvalheim.Client`. Flathub would accept that only with
  control of `phvalheim.com` demonstrated; otherwise it wants
  `io.github.brianmiller.*`. Renaming later is disruptive — it changes the
  desktop file name, the icon names and the `~/.var/app` directory — so it is
  worth settling before publishing anywhere.

## What the gates cover

`build_flatpak-innie --package` runs three, and its exit status is gated on
all of them.

**`verify_flatpak.sh`** — what is IN the bundle. Deploys it to a scratch
installation and asserts the app id, runtime, command, every granted
permission (including that `org.freedesktop.Flatpak` talk name and that
permissions have not silently widened to `--filesystem=host`), the binary is a
self-contained ELF, the desktop entry's `Exec`/`Icon`/`MimeType`, that the
desktop file is **exported** and not merely installed, the AppStream version
against the csproj, and the icons.

**`test_flatpak_runtime.py`** — what it DOES. Installs the bundle for real,
then:

- checks the exported `Exec` line, and that `gio` and `xdg-mime` both resolve
  `x-scheme-handler/phvalheim` to us
- runs the app in the runtime and matches its reported version to the csproj
- proves `flatpak-spawn --host` reaches the host, **and** that the sandbox is
  real — the host has a stub `steam` on `PATH` and the sandbox must not see it
- opens a **vanilla** world through `gio open` and asserts the stub Steam was
  invoked with `-applaunch 892970 +connect <host>:<port>`
- opens a **modded** world by **clicking the link in a real browser** under
  Xvfb, then asserts the world was downloaded and extracted, the companion
  backend file written, doorstop installed into the game directory, and the
  stub Valheim executed in the right directory with the right doorstop
  environment and no leaked runtime paths
- uninstalls, and asserts the scheme is no longer handled by us

**`test_native_passthrough.py`** — the *other* Linux packages. `Flatpak.cs` is
shared code, so a mistake in the non-sandboxed pass-through breaks the `.deb`,
`.rpm` and `.tar.gz`, none of which have gates of their own. It runs the same
published binary those ship, with no flatpak anywhere, against the same stubs,
and asserts the same launch outcomes for both world types.

A real click, not `location.href` — Chromium treats an external-protocol
navigation without a user gesture differently and can block it outright, so a
scripted navigation would be testing something a user never does. The browser
is driven with a managed-policy file that auto-allows the `phvalheim` scheme;
without it the only observable outcome is that a confirmation dialog appeared.

### What the gates CANNOT see

- **No real Steam, Valheim or GPU.** The stubs prove the client hands the host
  the right command, in the right directory, with the right environment. They
  cannot prove Valheim then starts. That gap is now closed by hand rather than
  by the gates — see the real-hardware section below — but it is still not
  something a build can check.
- **Nothing runs on SteamOS or Bazzite.** The tests run in a Debian trixie
  container. Game Mode on a Steam Deck in particular has no terminal emulator,
  and the desktop entry is `Terminal=true` to match the other Linux packages —
  so a Deck user in Game Mode will see no progress output at all. Untested and
  unaddressed. **Arch/Hyprland is confirmed working; the Deck is not.**
- **The tests install with `--system`, users install with `--user`.** flatpak
  refuses every modifying `--user` operation as root, and the container is
  root. Only the install location differs; export and URL registration are
  identical. The innie picks the scope by uid and hands it to the tests.
- **A Flatpak Steam is refused, and that refusal is not tested** — only the
  system-Steam path is exercised.
- **The test rig sets up its own session.** It exports `XDG_DATA_DIRS` with
  the Flatpak exports directory on it before anything runs, because otherwise
  nothing could resolve the handler. A real user's session may not — see
  below, which is exactly what the first real-hardware run hit.

### Confirmed working on real hardware (Omarchy / Arch + Hyprland, 2026-09-21)

**A modded world ran end to end: synced, installed BepInEx, launched Valheim,
and every mod loaded correctly.** That is the one thing no harness here can
reach — the stubs prove the right command goes to the host, not that the game
starts — so treat this as the real verification and the 102 checks as the
regression net.

Still unconfirmed on SteamOS and Bazzite, which are the distros the feature
request actually named.

#### What that run found on the way (the package was fine, the session was not)

Everything in the package was correct: the desktop file was exported, the
permissions matched the manifest exactly, the app ran and reported 2.0.13,
and `gio open 'phvalheim://?bogus'` produced the expected `malformed
phvalheim URL` through `xdg-terminal-exec` → `foot`. **One thing was wrong,
and it was in the session, not the package:**

```
XDG_DATA_DIRS = /usr/local/share:/usr/share
```

No `~/.local/share/flatpak/exports/share`. Flatpak warns about this at
install time and the warning scrolls past. With it missing, nothing can
resolve `x-scheme-handler/phvalheim` and **clicking a world link does
absolutely nothing, silently** — which is indistinguishable from a broken
package. GNOME and KDE set the variable; bare Hyprland and Sway often do not.

This cannot be fixed from inside the Flatpak: an application cannot edit its
own session's environment, and Flatpak has no post-install hooks by design.
It is a documentation problem, and the README now carries both the fix and a
troubleshooting section.

**When triaging any "the Flatpak doesn't work" report, ask for
`echo $XDG_DATA_DIRS` first.** The one-command fix the README gives:

```bash
mkdir -p ~/.config/environment.d && printf 'XDG_DATA_DIRS=/usr/local/share:/usr/share:/var/lib/flatpak/exports/share:%s/.local/share/flatpak/exports/share\n' "$HOME" > ~/.config/environment.d/flatpak.conf
```

`~/.config/environment.d/` is deliberate. It is read by
`systemd-environment-d-generator`, so it applies to the whole systemd user
session — GNOME, KDE, uwsm-launched Hyprland — and it is shell-agnostic,
which a `~/.profile` line is not (fish never reads `/etc/profile.d` or
`~/.profile`). `$HOME` is expanded at write time rather than relying on the
generator's variable substitution.

Two related traps for whoever tests this next:

- **Fixing it in a shell does not fix it for the browser.** The browser
  inherits the session environment, so the shell-level `export` proves the
  chain works but says nothing about a real click. The session fix plus a
  re-login is the only thing that tests what a user does.
- **`Terminal=true` survived contact with a terminal-less-looking desktop**,
  but only because `xdg-terminal-exec` was installed. Modern GLib prefers it;
  older GLib searches a fixed list containing none of foot, Alacritty,
  Ghostty or kitty. Still unverified on a desktop with none of those.

### The negative controls that were actually run

Every assertion above can be written in a form that passes no matter what.
Two deliberate breaks were run to check these are not that:

| Break | What failed |
| --- | --- |
| remove `--talk-name=org.freedesktop.Flatpak` | the verify permission check, the escape check, **and both launch tests** — so the browser click is a real oracle |
| remove the `XDG_CONFIG_HOME` fixup (before it was deleted for good) | exactly one check, the right one |

The first is the important one: it proves the browser-click test fails when
the package is broken, rather than passing on a stale artifact.

Two checks are **guards, not verified oracles**, and are labelled as such
here because nothing in this environment can currently make them fail: the
`.var/app` / `/app/` absence assertions on the launched game's environment.
They exist to catch flatpak changing its environment behaviour, which the
"sandbox environment does not reach host commands" check watches directly.

## Before you hand over a Flatpak change

- [ ] `builders/build_flatpak-outie` green, with the runtime tests **not**
      skipped.
- [ ] If you touched `Flatpak.cs`, the other five packages still build — it is
      shared code, not Flatpak-only code. Gate 3 covers their behaviour; it
      does not cover their packaging.
- [ ] If you touched permissions in the manifest, say which and why. The
      verify gate will catch a widening to `--filesystem=host`, but it cannot
      judge a new one.
- [ ] You said plainly that it has not run on real hardware, if it has not.
