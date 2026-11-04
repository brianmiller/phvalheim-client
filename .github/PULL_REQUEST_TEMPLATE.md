<!-- Read CONTRIBUTING.md if you have not. This checklist is the whole review bar. -->

## What changes for a player

<!-- One or two plain sentences. This is copied into the release notes. -->

## Checklist

- [ ] One change. A fix and a refactor are two PRs.
- [ ] `dotnet build phvalheim-client.csproj` succeeds.
- [ ] `bash dev_tools/run-tests.sh` passes locally.
- [ ] Behavior change: regression test fails without the fix. Docs-only: links and changed commands checked (mark other checks N/A with a reason).
- [ ] No `<Version>` bump in the csproj. Nothing under `builds/` touched.
- [ ] No certificates, passwords, internal hostnames or IPs in the diff.

## What I installed and ran

<!-- Which package(s) you built and installed, on which OS, against which server. -->

## What I did NOT test

<!-- Say it plainly. The smoke test does not reach sync, download or launch. -->

## Related changes and evidence

<!-- Related PRs and tested commit IDs; attach sanitized test results. Distinguish automated, platform, and live-game checks. -->
