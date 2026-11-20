#!/usr/bin/env bash
# Build only disposable copies. Baseline mode intentionally exits 1 on runtime regressions.
set -euo pipefail
started=$SECONDS
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
baseline=
if [[ ${1:-} == --baseline && $# == 2 ]]; then
    baseline=$2
elif [[ $# != 0 ]]; then
    echo "Usage: $0 [--baseline COMMIT]" >&2
    exit 2
fi
scratch=$(mktemp -d "${TMPDIR:-/tmp}/phv-launch.XXXXXX")
child= watchdog=
cleanup() {
    [[ -z $watchdog ]] || kill "$watchdog" 2>/dev/null || true
    [[ -z $child ]] || kill "$child" 2>/dev/null || true
    rm -rf -- "$scratch"
}
trap cleanup EXIT
trap 'echo "FAIL: RUNNER_TIMEOUT_OR_INTERRUPT" >&2; exit 124' TERM INT
(sleep 82; kill -TERM "$$" 2>/dev/null) >/dev/null 2>&1 & watchdog=$!
mkdir "$scratch/input"
for file in PhValheimPrep Tooling Syncer Downloader ConfigPolicy Ui; do
    if [[ -n $baseline ]]; then
        git -C "$repo" show "$baseline:$file.cs" > "$scratch/input/$file.cs"
    else
        cp "$repo/$file.cs" "$scratch/input/"
    fi
done
for file in PlayerConfig DiskSpace DiagnosticLog FileAccessDiagnostics ManagedFile; do
    cp "$repo/$file.cs" "$scratch/input/"
done
cp "$repo/dev_tools/LaunchDiagnosticsHarness.cs.txt" "$scratch/input/Program.cs"
cat > "$scratch/input/test.csproj" <<'PROJECT'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <EnableNETAnalyzers>false</EnableNETAnalyzers>
  </PropertyGroup>
</Project>
PROJECT
cat > "$scratch/input/global.json" <<'SDK'
{"sdk":{"version":"9.0.100","rollForward":"latestFeature"}}
SDK
cat > "$scratch/input/NuGet.Config" <<'NUGET'
<configuration><packageSources><clear /></packageSources></configuration>
NUGET
cat > "$scratch/worker.sh" <<'WORKER'
set -euo pipefail
input=$1 work=$2 mode=$3
active=
trap '[[ -z $active ]] || kill "$active" 2>/dev/null || true; exit 124' TERM INT
execute() {
    local code=0
    "$@" & active=$!
    wait "$active" || code=$?
    active=
    return "$code"
}
mkdir -p "$work/current" "$work/dotnet-cli" "$work/packages"
cp "$input/"* "$work/current/"
native_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
export DOTNET_CLI_HOME=$(native_path "$work/dotnet-cli") NUGET_PACKAGES=$(native_path "$work/packages")
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
export PHV_TEST_ROOT=$(native_path "$work") PHVALHEIM_VERBOSE=1
export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost
cd "$work/current"
execute dotnet build test.csproj --disable-build-servers -p:UseSharedCompilation=false --nologo -v quiet
dll="$work/current/bin/Debug/net9.0/test.dll"
result=0
execute dotnet "$dll" "$mode" || result=$?
if [[ $mode == baseline ]]; then exit "$result"; fi
mkdir "$work/mutant"
cp "$work/current/"*.cs "$work/current/test.csproj" "$work/current/global.json" "$work/current/NuGet.Config" "$work/mutant/"
execute dotnet "$dll" mutate-staging "$(native_path "$work/mutant/ConfigPolicy.cs")"
cd "$work/mutant"
execute dotnet build test.csproj --disable-build-servers -p:UseSharedCompilation=false --nologo -v quiet
mutation=0
execute dotnet "$work/mutant/bin/Debug/net9.0/test.dll" policy-only > "$work/mutation.out" 2>&1 || mutation=$?
cat "$work/mutation.out"
[[ $mutation == 1 ]] || { echo "FAIL: STAGING_MUTATION_RUNTIME_EXIT ($mutation)"; exit 1; }
for assertion in ARCHIVE_LOW_REJECTS ENFORCE_LOW_REJECTS ARCHIVE_COUNTS_PERSONAL_BYTES; do
    grep -Fxq "FAIL: $assertion" "$work/mutation.out" || { echo "FAIL: MUTATION_DID_NOT_KILL_$assertion"; exit 1; }
    echo "PASS: STAGING_MUTATION_KILLED_$assertion"
done
mkdir "$work/missing"
cp "$work/current/"*.cs "$work/current/test.csproj" "$work/current/global.json" "$work/current/NuGet.Config" "$work/missing/"
execute dotnet "$dll" inject-missing-copy "$(native_path "$work/missing/Syncer.cs")"
cd "$work/missing"
execute dotnet build test.csproj --disable-build-servers -p:UseSharedCompilation=false --nologo -v quiet
execute dotnet "$work/missing/bin/Debug/net9.0/test.dll" missing-only || result=$?
exit "$result"
WORKER
mode=current
[[ -z $baseline ]] || mode=baseline
if command -v dotnet >/dev/null 2>&1 && dotnet --list-sdks | grep -q '^9\.'; then
    echo "RUN: native .NET 9 ($mode)"
    bash "$scratch/worker.sh" "$scratch/input" "$scratch/work" "$mode" & child=$!
elif [[ $(uname -s) == Linux ]] && command -v docker >/dev/null 2>&1; then
    echo "RUN: Docker .NET 9 ($mode), read-only snapshot, loopback network only"
    docker run --rm --network none --read-only --tmpfs /tmp:rw,size=256m \
        -v "$scratch":/input:ro mcr.microsoft.com/dotnet/sdk:9.0 \
        timeout --kill-after=2s 75s bash /input/worker.sh /input/input /tmp/launch "$mode" & child=$!
else
    echo 'FAIL: Install native .NET SDK 9, or use Linux with Docker SDK 9 available.' >&2
    exit 2
fi
result=0
wait "$child" || result=$?
child=
echo "RUN: completed in $((SECONDS - started))s (exit $result)"
exit "$result"
