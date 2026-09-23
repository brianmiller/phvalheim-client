# System prompt — building the PhValheim Client macOS package

Give this to an agent working on the macOS build for `phvalheim-client`.
**For work on the client itself (any `.cs` file), read `prompts/client-build.md`
first** — this document is packaging-only. For the Windows installer read
`prompts/windows-msi-build.md`; the two share a client but nothing else.

Everything below was measured against real artifacts and real runs, not recalled.
Current as of `d3a6f08` (2026-09-23). Read "Bugs that shipped" before you touch
the builder — every entry there reached users.

---

Repo: `/mnt/wopr/development/brian/phvalheim-client` → `github.com/brianmiller/phvalheim-client`
(**public** — never commit secrets, internal IPs, or hostnames).

## What actually ships

One artifact:

```
builds/phvalheim-client-<version>-macos-universal.tar.gz
```

It contains exactly two things, both universal (`x86_64` + `arm64`):

- `phvalheim-client` — the .NET single-file client, installed to `/usr/local/bin`
- `PhValheim Client.app` — a tiny Swift agent that receives `phvalheim://` via an
  Apple Event and re-launches the client inside Terminal.app so the user sees
  progress. Installed to `/Applications`.

Users install with `macinstall.sh` from the repo root, which is **itself a
release asset** and is `curl | bash`-ed from `raw.githubusercontent.com`. It
resolves `/releases/latest`, so **a release promoted to Latest without a macOS
tarball 404s every macOS install.**

**There is no `.dmg`.** Nothing in the repo references `hdiutil` or `create-dmg`.
If someone asks for one, that is new work.

`builders/build_pkg-innie` builds a `.pkg` with `pkgbuild`/`productbuild`. It has
**never shipped** — no release has ever carried a `.pkg`, nothing in CI runs it,
and `macinstall.sh` cannot install one. Treat it as dead code until someone
decides otherwise.

## The build — three paths

### 1. CI. This is the one to use.

`.github/workflows/macos-verify.yml` runs on **free, unlimited `macos-15` Apple
Silicon runners** (public repos pay nothing for standard runners). It builds,
installs through the real installer, verifies, exercises the URL handler, and
uninstalls. Four jobs, about two minutes.

```bash
gh workflow run macos-verify.yml
gh run watch <run-id>
```

Any push to `master` touching `**.cs`, the csproj, the builder, the Swift
handler, a verify script, or `macinstall.sh` triggers it automatically.

Download the built tarball from the run:

```bash
gh run download <run-id> -n macos-universal-tarball -D builds/
```

Read the result from the run's **job summary**, not the log — every check
renders as a table there. The scripts `tee`, so the log has it too.

### 2. A real Mac over SSH

```bash
export MAC_HOST=<host> MAC_USER=<user>     # MAC_PASS optional; prefer SSH keys
bash builders/build_macos-outie
```

rsyncs the tree, runs `build_macos-innie` there, copies the tarball back.
**Brian has no Mac.** This path exists but is not currently usable by him.

### 3. Linux cross-build

A Linux box can produce the **client binary**, and it genuinely runs on Apple
Silicon — proven in CI, see `docs/MACOS-BUILD-ON-LINUX.md`:

```bash
for rid in osx-x64 osx-arm64; do
  dotnet publish -c macOS-Release -r $rid -p:PublishSingleFile=true \
    --self-contained true /p:PublishTrimmed=false ./phvalheim-client.csproj
done
rcodesign macho-universal-create -o out/phvalheim-client \
  bin/macOS-Release/net9.0/osx-x64/publish/phvalheim-client \
  bin/macOS-Release/net9.0/osx-arm64/publish/phvalheim-client
rcodesign sign out/phvalheim-client
```

`rcodesign` is `indygreg/apple-platform-rs`, a static musl binary — no Xcode, no
Apple SDK, no Mac. It replaces both `lipo` and `codesign`.

This works because the project is **not NativeAOT** — a self-contained
`PublishSingleFile` build is IL plus a prebuilt apphost, so the RID is only a
file-selection knob and Apple's linker never enters the picture. If anyone ever
adds `PublishAot`, this path dies.

**What it cannot do: the `.app`.** `swiftc -framework Cocoa` has no Linux
cross-SDK and Cocoa headers ship only inside Xcode. So path 3 produces a client
binary, not a shippable tarball. If you ever need a full tarball without a Mac,
the answer is to commit a prebuilt launcher — it carries no version string, only
`/tmp/phvalheim-launch-` and `/usr/local/bin/phvalheim-client`, and links only
OS-provided libraries — but **use CI instead**, it is free and builds the real
thing.

Note: dev1 has only .NET **8** system-wide. Anything net9 runs in
`mcr.microsoft.com/dotnet/sdk:9.0`.

## Files you will touch

| File | What it is |
|---|---|
| `builders/build_macos-innie` | the packager. Runs ON macOS. |
| `builders/build_macos-outie` | rsync + ssh wrapper for a remote Mac |
| `builders/url-handler.swift` | 44 lines. The `phvalheim://` agent. |
| `builders/verify_macos.sh` | 15 post-install checks. The gate. |
| `builders/verify_macos_gui.sh` | 7 activation checks. Needs an Aqua session. |
| `builders/ci_summary.sh` | renders a results TSV as a job-summary table |
| `macinstall.sh` | the user-facing installer. Also a release asset. |
| `.github/workflows/macos-verify.yml` | the pipeline |
| `docs/MACOS-BUILD-ON-LINUX.md` | the cross-build evidence |

## Rules that are not negotiable

- **Release tags are bare numeric** — `2.0.13`, never `v2.0.13`.
- **Version bumps are Brian's call.** Do not bump `<Version>` on your own.
- **Never publish a macOS asset you did not build.** See the 2.0.13 entry below.
- **Do not promote a release to Latest without a macOS tarball in it** —
  `macinstall.sh` reads `/releases/latest` and will 404 for every Mac user.
- The `.app` and the client must **both** be universal. Not just the client.
- Public repo. No secrets, no internal hostnames, no `MAC_HOST` default.

## Verification — the part that matters most

### `builders/verify_macos.sh <version> [results.tsv]`

Runs after install, no sudo. 15 checks. The load-bearing one:

> **The client executes.** Zero args is a no-side-effect path — `Arguments.cs`
> prints usage and bails before touching Steam, the network, or the filesystem.
> So a run either prints usage or gets SIGKILLed (rc ≥ 128) by AMFI for a bad
> signature.

Nothing on Linux can answer that question. An unsigned or wrongly-signed arm64
Mach-O is killed at exec and looks **completely healthy** to every static check —
right size, right arch, right permissions, correct `Info.plist`.

The rest: universal, both slices signed, `codesign --verify --strict`, no
quarantine xattr, malformed-URL rejection, `.app` present, handler universal and
signed, `CFBundleVersion` matches, `CFBundleURLTypes` declares the scheme,
Launch Services registration, and a Gatekeeper verdict on a deliberately
quarantined copy (INFO, not a gate — ad-hoc signing is expected to be rejected,
which is exactly why `macinstall.sh` strips the xattr).

### `builders/verify_macos_gui.sh [results.tsv]`

Registration is not delivery. This drives a real URL through the whole chain and
asserts at each hop, so a failure names the hop:

```
open(1) → Launch Services → GetURL Apple Event → url-handler.swift writes
/tmp/phvalheim-launch-<pid>.sh → Terminal.app → the argv the client receives
```

It swaps the client for an argv-recording shim (restored via `trap`) because it
tests **plumbing**; whether the real binary runs is `verify_macos.sh`'s job. A
random nonce plus a negative control asserting the argv log is *absent* first is
what makes "our URL arrived" distinguishable from "a URL arrived once."

Where there is no Aqua session it WARNs and skips rather than failing — a
headless box cannot answer the question either way.

### `macinstall.sh diags` is NOT a gate

It reads the version from `Info.plist` with `defaults read` and **never execs the
binary**. It passes on a binary macOS refuses to launch. CI runs it as a second
opinion only; if it ever disagrees with `verify_macos.sh`, one of them is lying.

## What the gates CANNOT see

CI has **no Steam, no Valheim licence, and no PhValheim server**. `Platform.cs`
hardcodes `/Applications/Steam.app/Contents/MacOS/steam_osx`. Everything above is
a **packaging and install gate, not a gameplay gate**. Mod sync, doorstop
injection, and actually launching Valheim are untested by anything automated and
have to be checked by hand on a real Mac with the game installed.

Also unverified: Intel hardware. Both runners and Brian's checks are arm64. The
x86_64 slice is asserted to exist and be signed; nobody has run it.

## Traps that will cost you a build

- **A bare `swiftc` emits a THIN binary** for the build machine's own
  architecture. Build each arch with `-target <arch>-apple-macos11.0` and `lipo`
  them. This shipped broken; see below.
- **`lipo` drops the linker's per-slice ad-hoc signatures.** Re-sign with
  `codesign --force --sign -` after fusing, or the arm64 slice will not exec.
- **macOS has no `timeout(1)`.** Use `perl -e 'alarm shift; exec @ARGV'` — the
  alarm survives `exec` and the exit status propagates. It cannot exec a shell
  function, so anything you want to bound must be an external command.
- **`tr -dc 'a-f0-9' </dev/urandom | head -c 12` HANGS on macOS.** BSD `tr`
  buffers, so it drains urandom forever trying to flush a 16-of-256 character
  class, `head` never gets its bytes, and `$( )` waits on every process in the
  pipeline. Use bash builtins (`$RANDOM`) for nonces.
- **`osascript -e 'tell application "Terminal" to quit'` is TCC-gated.** No one
  is there to click the consent dialog. Use `pkill -x Terminal`.
- **Always set `timeout-minutes`** on CI jobs and on any step that touches the
  window server. The default is **six hours**, and GitHub serves **no logs for an
  in-progress job** — an uncapped hang is both unreadable and expensive. The cap
  is what turns a hostage situation into a log that names the failing line.
- **Put a breadcrumb before every call that can block.** Two runs were spent
  locating a hang that a single `echo` would have pinned immediately.
- Hosted `macos-15` runners **do** have a GUI: `launchctl managername = Aqua`,
  WindowServer up, `screencapture` works. The widespread "hosted macOS runners
  are headless" advice is wrong for this image. Measure, do not assume — the
  `runner-probe` job exists to keep that answer current.

## Bugs that shipped, and what they teach

### The `.app` was arm64-only (through 2.0.12)

`build_macos-innie` ran a bare `swiftc`, so every build from an Apple Silicon Mac
produced an **arm64-thin URL handler next to a universal client**. On an Intel
Mac, `phvalheim://` links could not be handled at all. It survived because every
check looked at the client binary and nothing looked at the launcher, and because
all testing was on Apple Silicon.

**Lesson:** when a bundle has two binaries, assert on both. A check that covers
"the main artifact" is not coverage.

### 2.0.13's macOS tarball was a renamed 2.0.12 — FIXED 2026-09-23

When 2.0.13 was first promoted to Latest there was no Mac to build on, so
2.0.12's macOS assets were copied under 2.0.13 names to stop `macinstall.sh`
404-ing. The served asset carried **both** defects — `CFBundleVersion` read
`2.0.12` (permanent update notice) and the launcher was arm64-thin (no
`phvalheim://` on Intel).

Rebuilt from CI run `35815621719` and re-uploaded. The served asset now reads:

```
CFBundleVersion: 2.0.13
client archs:    ['x86_64', 'arm64']
launcher archs:  ['x86_64', 'arm64']
```

**Never ship a macOS asset you did not build.** CI has removed every reason to.
And note the method both times: the claim was settled by downloading what the
release actually *serves*, not by trusting what was built. Do that every time —
`gh release upload --clobber` succeeding tells you nothing about the bytes.

### The diags that could not see it

`macinstall.sh diags` was the only macOS verification for a long time and it
never executed anything. Same shape as the MSI 2814 gate gap: a check that
answers the same whether the bug is present or not. Whenever you add a macOS
check, ask what artifact would make it fail — if you cannot name one, it is not
a check.

## Releasing a new version

1. Brian bumps `<Version>` in `phvalheim-client.csproj`.
2. Push. CI builds and verifies automatically; confirm the run is green and the
   summary tables say what you expect.
3. `gh run download <run-id> -n macos-universal-tarball -D builds/`
4. Upload alongside the other formats:
   ```bash
   gh release upload <version> builds/phvalheim-client-<version>-macos-universal.tar.gz --clobber
   ```
5. **Verify what is served, not what was built** — download the release URL and
   check the version inside it before promoting anything to Latest.
6. Only then `gh release edit <version> --prerelease=false --latest`.

### Before you hand a build over

- CI green, and you have actually read the two summary tables.
- The tarball you uploaded is the one CI built, for the version you claim.
- `lipo -archs` on both binaries inside it shows `x86_64 arm64`.
- If you changed the client, say plainly that mod sync and game launch are
  **untested** — no CI gate covers them.

## Things that are gone — do not resurrect them

- **`.dmg`** — never existed here.
- **`.pkg`** — `build_pkg-innie` exists but has never shipped and is not in CI.
- **Building macOS on Linux in order to ship** — the cross-build is proven and
  worth keeping as evidence and as a fallback, but CI builds the real thing with
  a real `swiftc` for free. Reach for the cross-build only if GitHub is down.
- **An Intel macOS VM under KVM on dev1** — technically possible, against
  Apple's EULA, and dev1 does not have the RAM. An Apple Silicon guest on
  non-Apple hardware is not possible at all.
