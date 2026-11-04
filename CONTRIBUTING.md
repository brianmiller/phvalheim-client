# Contributing to PhValheim Client

Thanks for helping. Start here to choose the setup and checks for your change. It is written for
people and for AI coding assistants alike. If something here is wrong or missing, fixing this
page is itself a welcome contribution.

## The 30-second version

1. Fork the repo and branch from `master`.
2. Make one change.
3. Build it, run the tests, and run the client against a real PhValheim server if your change
   touches anything past argument parsing.
4. Open a pull request. Fill in the checklist the template gives you.
5. The maintainer reviews, merges and releases. You never sign, package for release or publish.

## Which repo?

PhValheim is three repositories. Pick the right one before you start.

| You want to change | Repo |
| --- | --- |
| The launcher players install on Windows, Linux or macOS | **phvalheim-client** (this one) |
| The server container: admin UI, public UI, engine, mod catalogue, docs website | [phvalheim-server](https://github.com/brianmiller/phvalheim-server) |
| The in-game mod shipped with every world (join flow, player roster) | [phvalheim-companion](https://github.com/brianmiller/phvalheim-companion) |

## What the client is

A .NET 9 console app, one directory of `.cs` files at the repo root. The browser hands it a
`phvalheim://` URL, it syncs the world's mods from the server into a private game directory,
and launches Valheim through BepInEx. `prompts/client-build.md` describes each source file.

## Set up

You need the [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0), `git`, Python 3, Bash, PHP CLI, standard Linux process tools (`procps` and `util-linux`),
and Docker for the full test suite and package builders. Several tests run .NET harnesses
in Docker, so run `dev_tools/run-tests.sh` on the host with Docker available, not inside
a bare SDK container. On Ubuntu, `sudo apt-get install git python3 php-cli procps util-linux`
installs the non-.NET test prerequisites; install Docker separately.

```bash
git clone git@github.com:<you>/phvalheim-client.git
cd phvalheim-client
dotnet build phvalheim-client.csproj
```

To run what you built against a real server, use the launch URL the server's public page gives
you for a world. The README's **Usage** section shows how to hand it to the binary by hand.

## Where things live

| Path | What it is |
| --- | --- |
| `*.cs` | The client. `Main.cs` is the entry point; `Syncer.cs`, `Downloader.cs`, `Launcher.cs` do the work |
| `phvalheim-client.csproj` | The **only** place the version lives. Every package reads it from here |
| `builders/` | One `build_<format>-outie` / `-innie` pair per package: `deb`, `rpm`, `tgz`, `flatpak`, `msi`, `macos`, `pkg`. Plus the verify scripts they call |
| `dev_tools/test-*.sh` | The tests. CI runs every one of them |
| `prompts/` | Deep reference for working on the client, the Windows installer and the macOS package. Read the one for your area |
| `docs/` | Design notes and per-version release notes under `docs/releases/` |
| `builds/` | Published package artifacts the server's download menu points at. **Never edit or add to it** |

## Make a change

- **One change per pull request.**
- **Do not bump `<Version>`** in the csproj. The maintainer does that when cutting a release.
- **Remember one change ships through seven packages.** For package changes, use a disposable checkout and test on the target OS. Builders write into `builds/`; do not commit or upload those development outputs. CI builds and verifies macOS for you; the Windows `.msi` and Flatpak build
  on Linux with Docker.
- **Never rebuild a published `.msi` version.** `builders/msi_rebuild_guard.sh` refuses, on
  purpose. If you need to understand why, `prompts/windows-msi-build.md` explains it.
- **Flatpak code runs sandboxed.** Anything that touches Steam or the host must go through
  `Flatpak.cs`. `docs/FLATPAK.md` has the rules.
- **macOS: never write inside Valheim.app.** A single stray file breaks the signed bundle and
  Steam reports the game as damaged. `dev_tools/test-macos-bundle-integrity.sh` guards this.

## Test it

For docs-only changes, verify links and any changed commands. No new runtime test or game install is required. For code changes, run the checks below and record unavailable checks explicitly.

```bash
bash dev_tools/run-tests.sh   # what CI runs
dotnet run --project phvalheim-client.csproj -- --version
```

The build gates run the smoke test automatically. It covers startup, the version banner and
malformed URLs. **It does not reach the sync, download or launch logic.** If you changed those,
run the client against a real server and say so in the PR. If you did not, say that instead.

For behavior changes, add a test as `dev_tools/test-<what-it-checks>.sh`:

- **It must be able to fail.** Break the code on purpose, watch the test go red, then fix it.
- **Assert on the outcome**, the file written or the output printed, not on a summary line.
- **Carry a control.** When you assert "X is absent", also assert something that IS present.

## Open a pull request

The PR template is the checklist. In short:

- [ ] One change, described in plain words: what changes for a player.
- [ ] `dotnet build` succeeds and every `dev_tools/test-*.sh` passes.
- [ ] For behavior changes, a test that fails without the change. For docs-only changes, check links and commands; no new runtime test is required.
- [ ] No version bump. Nothing under `builds/` touched.
- [ ] No secrets, certificates, internal hostnames or IPs.
- [ ] Which packages you installed and ran, and against which server. Or "none", plainly.

Report suspected vulnerabilities privately using [SECURITY.md](SECURITY.md), before opening a public issue or PR.

## Rules that protect everyone

**This repository is public.** Before every commit:

```bash
git diff --cached | grep -E '^\+' | grep -niE \
  'password|secret|api[_-]?key|token|bearer|\.pfx|([0-9]{1,3}\.){3}[0-9]{1,3}'
```

- Never commit a code-signing certificate or its password. They live outside the repo in
  `~/.config/phvalheim-client/codesign/`. With `CODESIGN_PFX` unset, builds succeed unsigned.
- Never commit `.claude/settings.local.json`. It is gitignored. Leave it that way.

**Releases are the maintainer's job.** Do not create tags or GitHub releases, upload packages
or add to `builds/`. Release tags are bare numbers (`2.0.17`, never `v2.0.17`) and the update
check in `Version.cs` depends on that.

## Using an AI coding assistant

Claude Code reads `CLAUDE.md` automatically; Codex, Cursor and similar tools read `AGENTS.md`.
Both point here, so the assistant is working from the same rules you are. A prompt that works:

> Read CONTRIBUTING.md and follow it. Make this change: <describe it>. Add a test under
> dev_tools that fails without the change, build with `dotnet build`, run every
> `dev_tools/test-*.sh`, and tell me exactly what you did not test.

Review what it produces against the checklist above before you open the PR. You are the author.

## Where to ask

- [Discord](https://discord.gg/8RMMrJVQgy) for questions and design discussion.
- [GitHub issues](https://github.com/brianmiller/phvalheim-client/issues) for bugs and feature
  requests.

PhValheim is MIT licensed. By contributing you agree your contribution is too.
