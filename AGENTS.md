# For AI coding assistants

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) first and follow it. It is short and complete.

Then read [`CLAUDE.md`](CLAUDE.md) for the hard rules and which reference document to read for
the area you are changing. The rules are the same for every assistant: Claude Code, Codex,
Cursor, Copilot or anything else.

Three things that matter most:

- One change per pull request, with a regression test for behavior changes; docs-only changes need link and command checks.
- For code changes, `dotnet build` and `bash dev_tools/run-tests.sh` must pass before the PR is opened.
- Do not bump the version, touch `builds/`, create tags or publish packages. Releases are the
  maintainer's job.
