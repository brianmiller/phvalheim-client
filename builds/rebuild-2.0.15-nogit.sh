#!/bin/bash
# Rebuild the remaining 2.0.15 Linux/Windows packages WITHOUT the builders' git step.
#
# Why this exists. Each build_*-outie ends by committing builds/* and running `git push`, and
# with -b it answers its own prompt "y". Pushing a 31 MB binary to GitHub from this box runs at
# under 1 KB/s -- measured on the socket send queue, 12 KB in 15 seconds -- so build-all sat on
# one `git push` for fourteen minutes having produced its artifact in four. The release assets
# do not come from that push: they are uploaded with `gh release upload`, which moved 61 MB in
# seconds. So the git step is pure cost here.
#
# HOW THE PROMPT IS ANSWERED, and why the two obvious ways both fail.
#
# Each builder ends with one `read` -- "Would you like to commit to GitHub? y/n" -- and `-b`
# answers it "y" without a read at all. Feeding stdin instead does not work:
#
#   echo n   -- the `docker run -it` inside the builder reads the pty too and SWALLOWS the
#               queued "n" during the build. By the time the prompt appears there is nothing
#               left and `read` blocks on a still-open pty. Measured: deb built in 90 seconds
#               then sat at that prompt for 48 minutes.
#   yes n    -- floods the pty for the whole build; the pty echoes it, so the builder log comes
#               out as nothing but "n" lines, and the run was SIGKILLed 11 seconds in.
#
# So: `-b`, and make the push it then attempts fail instantly instead of hanging. A real push
# of a 31 MB artifact from this box runs at under 1 KB/s -- measured on the socket send queue,
# 12 KB in 15 seconds -- which is the other 14-minute stall. GIT_SSH_COMMAND=/bin/false turns
# that into an immediate failure, after the LOCAL commit the builders have always made.
#
# The failed push costs nothing: release assets are uploaded with `gh release upload`, which
# moved 61 MB in seconds, and the local commits can be kept or reset afterwards.
cd "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1

EXPECT=2.0.15
VERSION=$(grep -m1 -oP '(?<=<Version>)[^<]+' phvalheim-client.csproj)
if [ "$VERSION" != "$EXPECT" ]; then
	echo "FATAL: csproj says $VERSION but this script is for $EXPECT."
	exit 1
fi

START=$(date +%s)
echo "=== start $(date) -- rebuilding $VERSION (${FORMATS:-deb rpm msi flatpak}) ==="

declare -A ARTIFACT=(
	[deb]="builds/phvalheim-client-$VERSION-x86_64.deb"
	[rpm]="builds/phvalheim-client-$VERSION-x86_64.rpm"
	[msi]="builds/phvalheim-client-$VERSION-x86_64.msi"
	[flatpak]="builds/phvalheim-client-$VERSION-x86_64.flatpak"
)

FAILED=0
for fmt in ${FORMATS:-deb rpm msi flatpak}; do
	echo "--- building $fmt ---"
	t0=$(date +%s)
	# `script` supplies the pty the builders' `docker run -it` needs; "n" answers the commit
	# prompt, which is the builder's documented way to stop after the build.
	# Output kept, not discarded: the first version sent it to /dev/null and a SIGKILLed
	# builder left nothing to read but "Killed" -- no way to tell a crash from a refusal.
	GIT_SSH_COMMAND=/bin/false script -qec "./builders/build_${fmt}-outie -b" /dev/null \
		> "/tmp/phv-build-$fmt.log" 2>&1
	art="${ARTIFACT[$fmt]}"
	if [ -f "$art" ] && [ "$(stat -c %Y "$art")" -ge "$t0" ]; then
		echo "OK   $fmt ($(( $(date +%s) - t0 ))s, $(stat -c %s "$art") bytes)"
	else
		echo "FAIL $fmt -- no artifact newer than this step ($art)"
		FAILED=$((FAILED+1))
	fi
done

if [ "$FAILED" -eq 0 ]; then
	echo "=== done $(date) -- all 4 in $(( $(date +%s) - START ))s ==="
else
	echo "=== FAILED $(date) -- $FAILED format(s) produced nothing ==="
fi
exit $FAILED
