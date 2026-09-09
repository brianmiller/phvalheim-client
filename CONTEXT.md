# phvalheim-client — Project Context

> Maintained by Skippy. Updated when significant changes are made.
> Last updated: 2026-03-18

## Overview

C# (.NET 9) desktop client for PhValheim. Syncs world mod contexts from a PhValheim Server
and launches Valheim with the correct BepInEx environment via the `phvalheim://` URL scheme.

**Flow:** `phvalheim://` URL → client → sync check → download world zip if needed → launch Valheim + BepInEx

## Current Version
**2.0.12**

## Platform Support
- **Windows:** `.msi` — URL scheme registered automatically by installer
- **Linux Debian/Ubuntu:** `.deb` — needs `xdg-mime` registration post-install
- **Linux Fedora/RHEL:** `.rpm` — needs `xdg-mime` registration post-install
- **Linux Universal:** `.tar.gz` — install via `phvalheim-client-installer.sh`
- **macOS:** `macinstall.sh` curl-bash one-liner — Intel + Apple Silicon

## Build System
- `dotnet publish` + custom shell builders, outputs go to `builds/`
- `build_deb-outie` — .deb via Docker
- `build_rpm-outie` — .rpm via Docker
- `build_tgz-innie` — .tar.gz local
- `build_macos-outie` — macOS .tar.gz via SSH to a Mac build host (M4 MacBook Pro).
  Set `MAC_HOST` / `MAC_USER` (and optionally `MAC_PASS`) in your environment; the
  builders deliberately carry no defaults, since this is a public repository.

## macOS Architecture

### URL Scheme Handling
- `.app` bundle contains a **compiled Swift binary** (not a shell script)
- Swift binary registers `NSApplicationDelegate`, receives `GetURL` Apple Event
- Forwards `phvalheim://` URL as CLI arg to the main `phvalheim-client` binary
- Shell scripts cannot receive Apple Events — Swift binary is required

### Apple Silicon / Rosetta 2 Strategy
- **Problem:** MonoMod v22 (bundled with BepInEx 5.x) cannot write detour trampolines on arm64
  due to MAP_JIT W^X hardware enforcement → SEGV crashes
- **Solution:** `lipo -thin x86_64` on Valheim's universal binary + ad-hoc `codesign` (preserving
  entitlements) forces Rosetta 2 translation. x86_64 MonoMod works correctly under Rosetta 2.
- All mods load with zero errors via this approach
- **Rule:** Only apply lipo/codesign on Apple Silicon Macs

### BepInEx arm64 Patches
- Server stages patched DLLs in `BepInEx/patches/macos_arm64/` inside the world zip
- Client swaps them in **only on Apple Silicon** before launching
- Intel Macs and other platforms use stock DLLs unchanged

### macinstall.sh
- Fetches latest release from GitHub API
- Installs binary to `/usr/local/bin/phvalheim-client`
- Installs `.app` bundle to `/Applications`, clears quarantine xattrs
- Registers `phvalheim://` URL scheme
- Supports: `install` (default), `uninstall`, `diags`

## Recent Commit History
- `da576a9` 2026-03-14: Remove obsolete macOS .pkg installer (replaced by macinstall.sh)
- `4ccc94c` 2026-03-14: Rebuild 2.0.12 packages with Rosetta 2 Apple Silicon support
- `5a2b733` 2026-03-14: Update README: replace .pkg with macinstall.sh one-liner
- `a007756` 2026-03-14: macOS Apple Silicon: run Valheim under Rosetta 2 for mod compat (lipo + codesign SEGV fix)
- `411f51a` 2026-03-13: Apply arm64 BepInEx patches only on Apple Silicon Macs
- `f9ea741` 2026-03-11: Fix macOS doorstop: use worldDir for dylib path, bundle universal fallback
- `9dc033f` 2026-03-11: Replace macOS .pkg with macinstall.sh bash script
- `129d5fb` 2026-03-09: Fix 2.0.12 universal tar.gz packaging old 2.0.11 binary
- `fecd53b` 2026-03-07: Open Terminal window on macOS URL launch for visible progress
- `c1d427a` 2026-03-07: Fix macOS phvalheim:// URL scheme (Swift binary for Apple Events)
- `790d598` 2026-03-06: Add macOS universal pkg to builds/
- `175a289` 2026-03-06: Add macOS support (Intel + Apple Silicon universal binary)
- `0790d8f`: Bump MSI installer version to 2.0.12
- `a19615e`: 2.0.12 Linux launch fixes and full package builds

## Known Issues / Watch Items
- macOS arm64 required significant work for mod compat — any BepInEx version bumps will need re-patching
- Mac build host: an M4 MacBook Pro, addressed via `MAC_HOST` / `MAC_USER` env vars
