#!/bin/bash
# Build the remaining 2.0.14 client packages, one at a time.
#
# Detached and sequential on purpose: these are docker builds, and running them
# concurrently fights over the daemon and makes a failure hard to attribute. The
# flatpak is already built, so it is not in the list.
#
# Each builder's own output goes to its own log; this script's log is a summary
# so a failure can be found without reading five build transcripts.

cd /mnt/wopr/development/brian/phvalheim-client || exit 1

LOGDIR=/tmp/clientbuild-2.0.14
mkdir -p "$LOGDIR"

FORMATS="tgz deb rpm macos msi"

echo "=== start $(date) ==="
for fmt in $FORMATS; do
    echo "--- building $fmt ---"
    start=$(date +%s)
    # -b answers yes to all questions; without it the builders block on a prompt
    # and the whole detached run sits there forever looking like a slow build.
    if ./builders/build_${fmt}-outie -b > "$LOGDIR/$fmt.log" 2>&1; then
        echo "OK   $fmt  ($(( $(date +%s) - start ))s)"
    else
        echo "FAIL $fmt  (exit $?, $(( $(date +%s) - start ))s) -- see $LOGDIR/$fmt.log"
    fi
done

echo "=== artifacts ==="
ls -la builds/ | grep '2\.0\.14' || echo "(none matched 2.0.14)"
echo "=== done $(date) ==="
