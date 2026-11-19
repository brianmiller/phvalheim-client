#!/usr/bin/env bash
# Compile a read-only source snapshot; all faults and mutations stay in the container.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
timeout --kill-after=5s 85s docker run --rm -i --network none --read-only \
    --tmpfs /tmp:rw,size=128m -e DOTNET_CLI_HOME=/tmp/dotnet \
    -e DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 -e DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    -v "$repo":/src:ro mcr.microsoft.com/dotnet/sdk:9.0 \
    timeout --kill-after=3s 75s bash -s <<'CONTAINER'
set -euo pipefail
mkdir /tmp/test
cp /src/FileAccessDiagnostics.cs /src/DiskSpace.cs /src/DiagnosticLog.cs /tmp/test/
cp /src/dev_tools/FileDiagnosticsHarness.cs.txt /tmp/test/Program.cs
cat > /tmp/test/test.csproj <<'PROJECT'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
PROJECT
dotnet build /tmp/test/test.csproj --nologo -v quiet
dll=/tmp/test/bin/Debug/net9.0/test.dll
baseline=0
dotnet "$dll" || baseline=$?
for mutation in low redact; do
    target="/tmp/mutant-$mutation"
    mkdir "$target"
    cp /tmp/test/*.cs /tmp/test/test.csproj "$target/"
    dotnet "$dll" mutate "$mutation" "$target"
    # A build failure must fail the suite, never count as a killed mutation.
    dotnet build "$target/test.csproj" --nologo -v quiet
    result=0
    dotnet "$target/bin/Debug/net9.0/test.dll" "check-$mutation" > "$target/result" 2>&1 || result=$?
    case "$mutation" in
        low) expected='FAIL: LOW_SPACE_REJECTS' ;;
        redact) expected='FAIL: REDACTION_SECRET_ABSENT' ;;
    esac
    if [[ "$result" != 1 ]] || ! grep -Fxq "$expected" "$target/result"; then
        echo "FAIL: $mutation mutation did not fail the required runtime assertion (exit $result)" >&2
        cat "$target/result" >&2
        exit 1
    fi
    echo "PASS: $mutation mutation compiled and failed the same assertion: $expected"
done
echo 'LIMITS: Linux .NET 9 only; Windows ACL/CFA, macOS, and old launch integration are unverified.'
if [[ "$baseline" != 0 ]]; then
    echo "FAIL: baseline helper regression suite (exit $baseline); mutation outcomes recorded above" >&2
    exit "$baseline"
fi
echo 'PASS: helper regression suite and both falsification checks'
CONTAINER
