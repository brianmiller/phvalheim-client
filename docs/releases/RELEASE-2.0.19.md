# PhValheim Client 2.0.19 — Windows MSI diagnostic prerelease preparation

**UNRELEASED — preparation only.** Brian has authorized a Windows MSI diagnostic
prerelease so the affected user can try the file-write diagnostics and disk-space
checks for
[issue #25](https://github.com/brianmiller/phvalheim-client/issues/25).
This changeset prepares the version, notes, and Windows upgrade verification matrix;
it does not build, verify, or publish a 2.0.19 package or provide an MSI download link.
Linux and macOS packages are not being published in this release scope. The existing
macOS workflow job is unchanged and may run as additional validation.

A fix for the original access-denied report is **unconfirmed**. The diagnostic
prerelease is intended to collect evidence from the affected environment, not to
claim that its underlying cause has been resolved.

File-write failures retain the actual failing path, operation, exception type and
message, and hexadecimal HResult. Where available, diagnostics add file attributes,
Windows owner/ACL observations, and a temporary parent-directory create/write/delete
probe. These observations are evidence for troubleshooting, not an antivirus or
Controlled Folder Access diagnosis; unavailable observations are reported as unknown.

Diagnostic logs redact credentials and rotate at a 1 MiB limit and at the start of
each run, retaining up to three archives. Normal locations are:

| Platform | Diagnostic log |
| --- | --- |
| Windows | `%APPDATA%\PhValheim\logs\phvalheim-client.log` |
| Linux | `~/.config/PhValheim/logs/phvalheim-client.log` |
| macOS | `~/Library/Application Support/PhValheim/logs/phvalheim-client.log` |

If the normal location cannot be used, the client tries a temporary fallback.
Use the actual log path printed in the error when reporting a failure. If neither
location works, logging is reported as unavailable. Paths and usernames remain in
the logs; review them before sharing publicly.

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

Prior source validation for `48e265f` was reported green across all 17 workflow jobs.
That evidence predates this release-preparation changeset and does not verify a
2.0.19 MSI. The Windows predecessor matrix now includes 2.0.18 alongside 2.0.12
through 2.0.17; candidate package verification has not been run for this changeset.
No successful package build, install, upgrade, repair, uninstall, wizard check,
or served-download hash verification is claimed for a 2.0.19 MSI. Real Controlled
Folder Access/antivirus behavior and live-game behavior remain unverified.
