# PhValheim Client 2.0.19 — Windows MSI diagnostic prerelease

This Windows-only diagnostic prerelease adds file-write diagnostics, persistent
logs, and disk-space preflight checks for
[issue #25](https://github.com/brianmiller/phvalheim-client/issues/25).
Its purpose is to collect evidence from the affected environment. A fix for the
original access-denied report, including the reported SmileMaster launch failure,
is **unconfirmed**.

The [2.0.19 release page](https://github.com/brianmiller/phvalheim-client/releases/tag/2.0.19)
provides the published Windows MSI,
[`phvalheim-client-2.0.19-x86_64.msi`](https://github.com/brianmiller/phvalheim-client/releases/download/2.0.19/phvalheim-client-2.0.19-x86_64.msi).
**2.0.18 remains the latest stable release.** No Linux, Flatpak, or macOS packages
are published as part of this prerelease. macOS validation or package jobs do not
imply macOS asset publication.

## Diagnostics and troubleshooting

File-write failures retain the actual failing path, operation, exception type and
message, and hexadecimal HResult. Where available, diagnostics add file attributes,
Windows owner/ACL observations, and a temporary parent-directory create/write/delete
probe. These observations are evidence for troubleshooting, not an antivirus or
Controlled Folder Access diagnosis; unavailable observations are reported as unknown.

On Windows, the normal diagnostic log is
`%APPDATA%\PhValheim\logs\phvalheim-client.log`. Logs redact credentials and rotate
at a 1 MiB limit and at the start of each run, retaining up to three archives
(`phvalheim-client.log.1` through `.3`). If the normal location cannot be used, the
client tries a temporary fallback. **Use the actual log path printed in the error**
when reporting a failure. If neither location works, logging is reported as
unavailable. Paths and usernames remain in the logs; review them before sharing
publicly.

Disk-space preflight checks the volume receiving the data, which may differ from
the operating-system volume. Downloads check known remaining bytes against available
space at their temporary destination beside the cached archive. Archive staging
accounts for uncompressed contents plus preserved personal configuration; config
staging, loader copies, and backend writes also check their actual destinations.
Diagnostics report required additional bytes and available bytes. Unknown sizes or
unavailable measurements remain unknown, and estimates do not guarantee an update
will fit.

Failed staged updates preserve the currently installed world. Failed download
transport preserves the cached archive. The existing backend policy remains unchanged:
a failed `phvalheim.backend` write aborts launch. Diagnostics do not change target
ACLs or read-only attributes, request elevation, or automatically retry that write.

## Exact MSI and source

| Field | Value |
| --- | --- |
| Asset | `phvalheim-client-2.0.19-x86_64.msi` |
| Size | 32,886,784 bytes |
| SHA-256 | `7e48a17e1b9921360ffeaab77d34cea1b7243ac3eb4e0ac0a569b4f0432dc488` |
| Runtime/build source | `6204fe1103f8c7f5e26bcd833e84d16e8cf2dc33` |

The MSI uses the existing self-signed certificate. Windows may report an unknown
publisher; this is an existing packaging characteristic, not evidence of a new
signing trust chain.

Later test/documentation commits leave all `.cs`, `.csproj`, and `.wxs` files
unchanged from the build source. Test-only commit `0078537` adjusts the smoke
assertion to expect intentional redaction of a malformed decoded launch payload.
Neither the runtime nor the MSI was rebuilt for that assertion change.

## Validation evidence

The exact MSI above passed local validation:

- 75 structural, signature, and smoke checks.
- 24 executable smoke assertions.
- 36 Wine installation-behavior checks, using the actual 2.0.18 predecessor MSI.
  Wine repair was skipped; native Windows repair coverage passed below.

The [native Windows candidate workflow](https://github.com/brianmiller/phvalheim-client/actions/runs/44605956555)
passed all seven upgrade jobs, from 2.0.12 through 2.0.18. Each job passed 14
assertions, including the exact installed executable SHA-256, a single Add/Remove
Programs entry, repair, and uninstall. The full installer wizard step also passed
in the 2.0.17 job, including its negative control and candidate installation. The
additional macOS package job passed as validation only; no macOS assets are
published as part of this Windows-only prerelease.

The [native diagnostics workflow](https://github.com/brianmiller/phvalheim-client/actions/runs/44605622061)
passed on Windows (57 diagnostics assertions plus 6 missing-copy checks)
and Linux (76 plus 6). Its macOS diagnostics job was still queued when this evidence
was recorded. Prior macOS diagnostics at `48e265f`, with the same diagnostic runtime
code, passed 76 plus 6 assertions; that is prior-source evidence, not a completed
macOS result for this run.

## Validation limits

Smoke checks cover startup, the version banner, and malformed URLs; they do not
exercise world synchronization, downloads, or a live Valheim launch. Installation
and diagnostic tests do not establish that the affected user's launch now succeeds.
Live Valheim, real Controlled Folder Access/antivirus behavior, and the reported
SmileMaster failure remain unverified. A denied backend write still stops launch.

Public download verification is complete. Release 2.0.19 (ID `451871940`) is
published with `isDraft: false` and `isPrerelease: true`; its runtime tag points to
`6204fe1`. An unauthenticated `curl` download from the direct public MSI link above
to `/tmp/phv219-public.msi` was byte-identical to the local artifact by `cmp`.
Its SHA-256, `7e48a17e1b9921360ffeaab77d34cea1b7243ac3eb4e0ac0a569b4f0432dc488`,
matches both the served `SHA256SUMS` and the GitHub asset digest.
Running `verify_msi.sh` on the downloaded file with `--skip-wine` passed all 71
checks. Release 2.0.18 (ID `435814564`) remains the latest stable release with
unchanged flags.
