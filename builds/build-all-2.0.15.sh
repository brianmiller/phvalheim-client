#!/bin/bash
# Build the 2.0.15 client packages, one at a time.
#
# THREE THINGS THIS SCRIPT GETS RIGHT THAT THE OBVIOUS VERSION DID NOT:
#
# 1. A TTY. The builders run `docker run -it`, so detached they die with "the
#    input device is not a TTY" -- and still exit 0. `script` supplies a pty.
#
# 2. It gates on the ARTIFACT, not on $?. The first version trusted the exit
#    code, reported "OK tgz (4s)" three times, and produced no files at all. A
#    four-second package build should have been the tell. Every format below is
#    confirmed by a file that exists and is NEWER than this run's start.
#
# 3. VERSION is DERIVED from the csproj, not retyped. Every one of the nine
#    builders already reads <Version> from phvalheim-client.csproj, so a
#    hardcoded copy here is a second source of truth that can only ever drift --
#    and when it drifts, the artifact-existence check above fails for a reason
#    that has nothing to do with the build. The EXPECT guard below is what keeps
#    "derived" from quietly meaning "whatever happened to be in the file".
#
# macOS is deliberately absent: `build_macos-outie` needs MAC_HOST/MAC_USER and
# prompts/macos-build.md records how that tarball is produced. Do NOT copy a
# previous version's macOS asset under a 2.0.15 name -- that is exactly what went
# wrong with 2.0.13 (shipped a renamed 2.0.12 with the wrong CFBundleVersion and
# an arm64-thin launcher).

cd /mnt/wopr/development/brian/phvalheim-client || exit 1

EXPECT=2.0.15
VERSION=$(grep -m1 -oP '(?<=<Version>)[^<]+' phvalheim-client.csproj)

if [ -z "$VERSION" ]; then
    echo "FATAL: could not read <Version> from phvalheim-client.csproj"
    exit 1
fi
if [ "$VERSION" != "$EXPECT" ]; then
    # Refuse rather than build. This script is named for a release; building a
    # different one under that name is how 2.0.13 shipped 2.0.12's bits.
    echo "FATAL: csproj says $VERSION but this script is build-all-$EXPECT.sh."
    echo "       Bump the csproj, or use the script for $VERSION."
    exit 1
fi

LOGDIR=/tmp/clientbuild-$VERSION
mkdir -p "$LOGDIR"
STAMP="$LOGDIR/.start"
touch "$STAMP"

# format : glob that must exist and be newer than $STAMP for the build to count
FORMATS="tgz deb rpm msi"

artifact_glob() {
    case "$1" in
        tgz) echo "builds/phvalheim-client-$VERSION-universal-x86_64.tar.gz" ;;
        deb) echo "builds/phvalheim-client-$VERSION-x86_64.deb" ;;
        rpm) echo "builds/phvalheim-client-$VERSION-x86_64.rpm" ;;
        msi) echo "builds/phvalheim-client-$VERSION-x86_64.msi" ;;
    esac
}

echo "=== start $(date) -- building $VERSION ==="
for fmt in $FORMATS; do
    echo "--- building $fmt ---"
    start=$(date +%s)
    script -qec "./builders/build_${fmt}-outie -b" /dev/null > "$LOGDIR/$fmt.log" 2>&1
    rc=$?
    want=$(artifact_glob "$fmt")
    took=$(( $(date +%s) - start ))

    if [ -f "$want" ] && [ "$want" -nt "$STAMP" ]; then
        echo "OK   $fmt  (${took}s, exit $rc)  $(ls -l "$want" | awk '{print $5}') bytes  $want"
    elif [ -f "$want" ]; then
        echo "STALE $fmt (${took}s, exit $rc) -- $want exists but predates this run; the build did NOT produce it"
    else
        echo "FAIL $fmt  (${took}s, exit $rc) -- no $want; see $LOGDIR/$fmt.log"
    fi
done

echo "=== $VERSION artifacts present ==="
ls -la builds/ | grep "$VERSION" || echo "(none)"
echo "=== done $(date) ==="
