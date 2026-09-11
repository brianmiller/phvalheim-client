# System prompt — working on the PhValheim Client itself

Read this before changing any `.cs` file. For work on the Windows installer,
read `prompts/windows-msi-build.md` instead — that one is packaging-only, and
until now it was the *only* prompt in this repo, which meant client changes had
no written guidance at all.

Everything below was measured against the tree on 2026-09-11, not recalled.
Where something has not been verified, it says so.

Repo: `/mnt/wopr/development/brian/phvalheim-client` → `github.com/brianmiller/phvalheim-client`
(**public** — never commit secrets, internal IPs, or hostnames.)

## What the client is

A .NET 9 console app, ten source files at the repo root:

| File | Role |
| --- | --- |
| `Main.cs` | entry point, argument dispatch |
| `Arguments.cs` | URL parsing, and `Usage()` which prints the version banner |
| `Launcher.cs` | launches Valheim with the BepInEx environment |
| `Downloader.cs` | fetches world/mod payloads |
| `Syncer.cs` | keeps the local mod environment in step with the server |
| `PhValheimPrep.cs` | prepares the game directory |
| `Steam.cs` | locates the Steam library |
| `Platform.cs` | per-OS paths; reads `HKCU\Software\Valve\Steam` on Windows |
| `Tooling.cs` | helpers |
| `Version.cs` | compares the running version against the newest GitHub release |

It registers the `phvalheim://` URL scheme; the server hands out
`phvalheim://` links and Windows/macOS/Linux route them here.

**There are no `--version` or `--help` flags.** The only CLI shape is a single
`phvalheim://?<base64>` argument, where the base64 decodes to
`command?field?field…`. `launch` needs 7 fields (an 8th, `vanilla`, is optional
and absent means modded — a 2.40 client must still work against an older
server); `textures` needs 3. With **no** arguments it prints usage and exits.
Anything else prints "malformed phvalheim URL". Do not invent flags — check
`Arguments.argHandler` before documenting or testing one.

## The version has exactly one source of truth

`<Version>` in `phvalheim-client.csproj`. Verified: all six builders read it
out of the csproj (`build_{deb,rpm,tgz,macos,pkg,msi}-innie`), and the app
reads its own version at runtime from
`AssemblyInformationalVersionAttribute` (`Main.cs:12`, `Arguments.cs:11`),
splitting on `+` to drop the source-revision suffix.

So bumping `<Version>`/`<AssemblyVersion>`/`<FileVersion>` in the csproj is
genuinely the only edit. Do not add a version constant anywhere. The retired
`.vdproj` drifted to 2.0.12 while the csproj said 2.0.13; that is the failure
this arrangement prevents.

## Release tags must stay bare numeric

**`2.0.13`, never `v2.0.13`.** This is load-bearing, not style.

`Version.cs` does `new Version(releases[0].TagName)` on the newest GitHub
release. `System.Version` cannot parse a leading `v`, so a `v`-prefixed tag
throws `FormatException` — inside an `async void` method, where it cannot be
caught by the caller and takes the process down. Every existing tag is bare
numeric (`2.0.5` … `2.0.12`); keep it that way.

Two related sharp edges in the same method, neither fixed:

- `releases[0]` is simply the newest release, so publishing a **pre-release**
  will tell every client to upgrade to it.
- `async void` means any failure in the check — network, rate limit, parse —
  is unobservable rather than handled.

## One client change ships through SIX packages

`builders/build_<fmt>-{outie,innie}` for `deb`, `rpm`, `tgz`, `macos`, `pkg`
and `msi`. A change to any `.cs` file affects all of them.

**Only the `msi` has any verification.** Measured: `build_msi-innie` invokes
`verify_msi.sh` and `test_install_matrix.py`; the other five innies contain no
verify or test step whatsoever. So a change that builds a working `.msi` can
still ship a broken `.deb`, and nothing will say so.

The non-Windows builders have **not been audited** to the standard the msi one
now has. Do not assume they are correct because they are old. If you touch
packaging for them, verify before claiming.

## Testing: one smoke test, and a large hole

`builders/test_client_smoke.py` is the only thing that **runs the program**. It
gates the build. It drives the real shipped win-x64 exe under wine and covers:

- startup, usage output, and that the binary's reported version matches the
  csproj (the app-side equivalent of the `.vdproj` drift check)
- all four malformed-URL early returns in `Arguments.argHandler`
- **that the process does not block on stdin** — every failure path calls
  `Console.ReadLine()`, so a naive test hangs forever. Cases run with stdin
  closed and a 120s timeout, and a hang is reported as a FAIL

Both halves were proven falsifiable: a wrong expected version fails the version
check, and a well-formed URL does *not* emit "malformed", so that assertion
discriminates.

**What is still untested is most of the client.** Everything past a well-formed
launch URL — `Platform.State.init`, `PhValheimPrep`, `Downloader`, `Syncer`,
`Launcher` — needs a real server and a real Steam install. There is no coverage
of any of it, and the smoke test prints that as a COVERAGE NOTE on every run.

So: a behavioural change to `Syncer`, `Downloader` or `Launcher` is verified
only by running the client against a real server. If you did not do that, the
honest handover is "built, packaged and smoke-tested; runtime behaviour
unverified".

## Build facts worth knowing before you change the csproj

- Published **self-contained, single-file, win-x64** for Windows
  (`build_msi-innie --publish`), and `PostBuildEvent` is cleared because it
  invoked a Windows-only `.bat`.
- **Publishing on Linux produces an exe with no Win32 version resource.** wixl
  therefore writes an empty `File.Version`, which silently breaks MSI upgrades;
  the `.wxs` compensates with `DefaultVersion`. If you ever make the build
  stamp a real version resource, that is a good thing — but re-read the upgrade
  section of `prompts/windows-msi-build.md` before removing the workaround.
- The build emits pre-existing warnings: `CS8600` in `Launcher.cs:135` and four
  `CA1416` in `Platform.cs` (registry APIs are Windows-only, and that code is
  reachable on all platforms). They are noise today, but `CA1416` is pointing at
  something real — `Platform.cs` calls `Registry.CurrentUser` without an OS
  guard. Do not "fix" them by suppressing; either guard the call or leave it.

## Before you hand over a client change

- [ ] `<Version>` bumped in the csproj only, if the change ships.
- [ ] All six packages still build, not just the one you were working on.
- [ ] The msi gates are green — `verify_msi.sh` **and** `test_install_matrix.py`
      (never `MSI_SKIP_MATRIX=1` for a handover).
- [ ] The client smoke test is green (it runs automatically in `--package`).
- [ ] You actually ran the client against a real server, or you said you did not
      — the smoke test does not reach any of the sync/launch logic.
- [ ] Release tag is bare numeric.
