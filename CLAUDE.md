# CLAUDE.md

**Merge approval is mandatory:** Brian Miller (`@brianmiller`) must explicitly approve
any change before it enters `main` or `master`. Prepare and test a PR, then wait.
Implementation requests, green CI, another reviewer's approval, and access to Brian's
credentials are not merge authorization. New changes require renewed approval.
Do not merge, enable auto-merge, push directly, or bypass protections without his
explicit authorization. Never submit an approval as Brian or impersonate his review.
See [the approval procedure](CONTRIBUTING.md#brian-must-approve-every-merge).

Guidance for Claude Code when working in this repository.

**Contributing a change? Read [`CONTRIBUTING.md`](CONTRIBUTING.md) first and follow it.** It is
the short, complete procedure: set up, change, test, open a PR.

## What this is

The PhValheim Client: a .NET 9 console app that receives a `phvalheim://` URL from the browser,
syncs a world's mods from a PhValheim server, and launches Valheim through BepInEx. It ships as
seven packages (`deb`, `rpm`, `tgz`, `flatpak`, `msi`, `macos` tarball, `pkg`) built by the
`builders/build_<format>-{outie,innie}` pairs.

## Read the reference for your area before editing

| Working on | Read |
| --- | --- |
| Any `.cs` file | `prompts/client-build.md` |
| The Windows `.msi` | `prompts/windows-msi-build.md` |
| The macOS tarball, `.pkg` or `macinstall.sh` | `prompts/macos-build.md` |
| The Flatpak | `docs/FLATPAK.md` |

Each one was measured against real artifacts and lists the bugs that actually reached users.
Do not re-derive what they already answer.

## Hard rules

- `<Version>` in `phvalheim-client.csproj` is the only version. Never add another constant.
- Release tags are bare numeric (`2.0.17`). `Version.cs` parses them.
- Never rebuild a published `.msi` version. `builders/msi_rebuild_guard.sh` enforces it and the
  `UpgradeCode` in `builders/wxs/phvalheim-client.wxs` must never change.
- Never write inside Steam's signed `Valheim.app` on macOS.
- Nothing under `builds/` is edited by hand. The maintainer publishes there at release time.
- The smoke test does not reach sync, download or launch. Say so when you hand over.
- Code-signing material lives outside the repo. Never commit a `.pfx` or its password.

## Tests

```bash
bash dev_tools/run-tests.sh
```

CI (`.github/workflows/macos-verify.yml`) runs every one of them, builds the macOS package on a
real Apple Silicon runner, and verifies installs over previously published versions.
