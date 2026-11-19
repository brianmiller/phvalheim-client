# PhValheim Client 2.0.19 — file-write diagnostics and disk-space checks

**UNRELEASED.** Upcoming changes; implementation is under review for
[issue #25](https://github.com/brianmiller/phvalheim-client/issues/25).
These notes do not announce publication. Package formats and the prerelease decision
remain Brian's responsibility.

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

Final validation evidence is not yet complete. Native Windows and macOS validation
will be recorded in the PR. Real Controlled Folder Access/antivirus behavior and
live-game behavior remain unverified. These notes make no claim of green CI,
completed platform validation, or successful package builds.
