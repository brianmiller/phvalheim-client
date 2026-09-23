# Building the macOS client without a Mac

Research + live experiments run on 37648-dev1, 2026-09-23. Nothing here is
theoretical unless it says so — the measured results were produced on that box.

> **CONFIRMED ON REAL HARDWARE 2026-09-23.** `.github/workflows/macos-verify.yml`
> now builds the client both ways and runs both on a free `macos-15` Apple
> Silicon runner. The Linux-cross-built, `rcodesign`-signed binary **executes on
> arm64** (`rc=0`, printed usage) and `codesign --verify --strict` accepts the
> signature. A Mac is not required to build a working macOS client. The native
> path passes 15/15 checks.
>
> The runner also reports `launchctl managername = Aqua` with WindowServer
> running and `screencapture` working — so the hosted runner has a real GUI
> session, and `phvalheim://` *activation* (not just registration) is testable
> there. That was an open question below; it is now answered.

## Summary

**Yes, and most of it already works.** Of the four macOS-only steps in
`builders/build_macos-innie`, three were reproduced on Linux today. The fourth
(`swiftc`) does not need to be run again at all.

| step | macOS tool | Linux answer | status |
|---|---|---|---|
| build both arch slices | `dotnet publish -r osx-{x64,arm64}` | same command, `mcr.microsoft.com/dotnet/sdk:9.0` | **proven** |
| fuse universal binary | `lipo -create` | `rcodesign macho-universal-create` | **proven** |
| ad-hoc sign | `codesign` (implicit, via `ld`) | `rcodesign sign` | **proven** |
| `.app` launcher | `swiftc -framework Cocoa` | reuse the prebuilt binary | **not solvable**, but avoidable |

## What was measured

Clean checkout of `HEAD` into a scratch tree, built in the .NET 9 SDK container:

```
dotnet publish -c macOS-Release -r osx-arm64 -p:PublishSingleFile=true \
    --self-contained true /p:PublishTrimmed=false ./phvalheim-client.csproj
```

Exit 0, 78 MB arm64 Mach-O. Same for `osx-x64`. The project is **not** NativeAOT
(no `PublishAot`), which is the only thing that would have required Apple's
linker — a plain self-contained `PublishSingleFile` build is pure IL plus a
prebuilt apphost, so the RID is just a file-selection knob.

The cross-built binary is **unsigned**, and an unsigned arm64 Mach-O is killed on
launch by Apple Silicon:

```
phvalheim-client (cross-built)   arm64  ncmds=33  LC_CODE_SIGNATURE=NO
```

`rcodesign 0.29.0` (`indygreg/apple-platform-rs`, static musl binary, no Xcode,
no Apple SDK) fixes that, and also replaces `lipo`:

```
rcodesign macho-universal-create -o universal <x64> <arm64>
rcodesign sign universal
```

Result, next to the shipped Mac-built 2.0.12 binary as a control:

```
Linux-built + rcodesign      x86_64 ncmds=33 SIG=YES   arm64 ncmds=34 SIG=YES
2.0.12 (built on a real Mac) x86_64 ncmds=33 SIG=YES   arm64 ncmds=34 SIG=YES
```

Structurally identical. Note the control matters: the same check read `SIG=NO`
before signing and `SIG=YES` after, on both the artifact and the reference, so it
is a real oracle and not a check that passes on everything.

## The one real blocker: `swiftc`

`builders/url-handler.swift` is compiled with `swiftc -framework Cocoa`. There is
no supported Swift cross-SDK targeting Darwin from Linux, and Cocoa needs headers
that ship only inside Xcode, whose licence binds the SDK to Apple hardware.
osxcross can compile **C/ObjC** against an extracted macOS SDK, but not Swift, and
extracting the SDK requires a Mac to begin with.

It does not matter, because that launcher never changes:

- 92 KB, arm64, already built and sitting in
  `builds/phvalheim-client-2.0.12-macos-universal.tar.gz`
- contains **no version string** — the only interesting literals are
  `/tmp/phvalheim-launch-` and `/usr/local/bin/phvalheim-client`
- links only OS-provided libraries (`/usr/lib/swift/*`, Cocoa, AppKit,
  Foundation), all present since macOS 10.14.4

So: extract it once, commit it as `builders/prebuilt/PhValheim Client`, and have
`build_macos-innie` copy it instead of invoking `swiftc` when `swiftc` is absent.
Rebuild it only if `url-handler.swift` is ever edited.

### Latent bug found while measuring this

The `.app` launcher shipped in 2.0.12 is **arm64-thin**, not universal, while the
main binary is a proper fat binary. On an Intel Mac the `phvalheim://` URL handler
cannot launch. Whatever path we take, the launcher should be fused universal too.

## Options that do not work

**Apple Silicon VM on x86 Linux — no.** macOS arm64 has no emulated boot path
outside Apple hardware (no OpenCore equivalent for iBoot/sepOS). Nothing
resembling a bootable Apple Silicon guest exists on non-Apple hosts.

**Intel macOS under KVM (Docker-OSX / OSX-KVM) — technically yes, practically no
here.** Xcode on Intel cross-builds arm64 slices fine, so an Intel guest would
satisfy "build for Apple Silicon" — the *host* architecture was never the
requirement. But it wants ~8 GB RAM and tens of GB of disk, and dev1 currently
reports 15 GB total with ~0 available. It is also squarely against Apple's EULA.

**osxcross — real, but the wrong tool here.** It solves C/ObjC compilation, which
is a problem we do not have, and not Swift, which is the one we do.

## Recommendation

1. **Free CI on a real Mac.** This repo is public, and GitHub-hosted **arm64
   macOS** runners (`macos-14` / `macos-15`) are free and unlimited on public
   repos. A workflow that runs `builders/build_macos-innie` and uploads the
   tarball removes the Mac problem entirely, with a genuine `swiftc` and genuine
   `codesign`, for no money. The repo has no `.github/workflows` yet.
2. **Linux fallback for when CI is not an option** — `dotnet publish` ×2 +
   `rcodesign macho-universal-create` + `rcodesign sign` + prebuilt launcher.
   Everything but the launcher is proven above.

Doing (1) first is strictly better; (2) is worth having anyway so a release is
never blocked on GitHub.

## Sources

- <https://github.com/tpoechtrager/osxcross>
- <https://crates.io/crates/apple-codesign>
- <https://gregoryszorc.com/blog/2022/08/08/achieving-a-completely-open-source-implementation-of-apple-code-signing-and-notarization/>
- <https://github.blog/changelog/2024-01-30-github-actions-introducing-the-new-m1-macos-runner-available-to-open-source/>
- <https://docs.github.com/en/billing/reference/actions-runner-pricing>
- <https://github.com/sickcodes/docker-osx>
- <https://github.com/dotnet/sdk/issues/34917>
