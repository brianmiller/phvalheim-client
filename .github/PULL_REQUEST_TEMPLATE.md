<!-- Read CONTRIBUTING.md if you have not. This checklist is the whole review bar. -->

## What changes for a player

<!-- One or two plain sentences. This is copied into the release notes. -->

## Checklist

- [ ] One change. A fix and a refactor are two PRs.
- [ ] `dotnet build phvalheim-client.csproj` succeeds.
- [ ] Every `dev_tools/test-*.sh` passes locally.
- [ ] I added or updated a test under `dev_tools/` and watched it **fail** without my change.
- [ ] No `<Version>` bump in the csproj. Nothing under `builds/` touched.
- [ ] No certificates, passwords, internal hostnames or IPs in the diff.

## What I installed and ran

<!-- Which package(s) you built and installed, on which OS, against which server. -->

## What I did NOT test

<!-- Say it plainly. The smoke test does not reach sync, download or launch. -->
