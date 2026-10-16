#!/bin/sh
# Oracle test: PhValheim never writes inside Steam's signed Valheim.app.
#
# THE BUG, reported by a macOS user:
#
#     "valheim" is damaged and can't be opened. You should move it to the Trash
#
# That message reads like a corrupt download, which is why it was never traced back here.
#
# WHAT CAUSED IT. The Apple Silicon path has to run Valheim as x86_64, because MonoMod v22
# (BepInEx 5.x) cannot write detour trampolines on arm64 under MAP_JIT W^X. It does that with
# `lipo -thin x86_64`, and up to 2.0.15 it wrote the result to
#
#     Valheim.app/Contents/MacOS/Valheim.x86_64          <-- INSIDE the signed bundle
#
# and then ran `codesign --force` on it. A signed app bundle seals a manifest of its contents
# in Contents/_CodeSignature/CodeResources; files under Contents/MacOS that are not the main
# executable are sealed as resources. An unlisted file there makes the resource envelope
# invalid, and Gatekeeper reports an invalid envelope as "damaged".
#
# So every Apple Silicon user who launched a modded world broke their own Valheim install, and
# the breakage persisted after PhValheim exited -- Steam's Valheim would not start either.
#
# THE FIX, two halves:
#   1. REPAIR. Delete the stray file. That is a complete repair and this is the precise reason:
#      CodeResources was computed over a tree that did not contain the file, so removing it
#      restores validity of Iron Gate's ORIGINAL signature. Nothing is re-signed -- ad-hoc
#      signing over their identity would be a second kind of damage and would survive a Steam
#      integrity check.
#   2. STOP DAMAGING. The thinned slice now goes into a PhValheim-owned shadow bundle under the
#      world directory, with Resources/Frameworks/PlugIns symlinked back to the real install so
#      it costs kilobytes. Valheim.app is never written to again.
#
# This file is a SOURCE oracle -- it can run on Linux and in CI without a Mac. The mechanism
# itself (that an extra file really does invalidate the seal, and that a symlinked shadow
# bundle really does launch) is proven on a real macOS runner by the
# bundle-seal / rosetta-shadow jobs in .github/workflows/macos-verify.yml.
#
# Usage:  sh dev_tools/test-macos-bundle-integrity.sh

REPO=$(cd "$(dirname "$0")/.." && pwd)
L="$REPO/Launcher.cs"

PASS=0; FAIL=0
pass(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
fail(){ echo "  FAIL: $1"; [ -n "$2" ] && echo "        $2"; FAIL=$((FAIL+1)); }

echo
echo "== part 1: THE REGRESSION ASSERTION -- nothing is written inside Valheim.app =="

# The exact pre-fix construction. `exec` is
# <valheimDir>/Valheim.app/Contents/MacOS/Valheim, so `exec + ".x86_64"` is a path inside the
# bundle. This single line is what broke every Apple Silicon install.
if grep -qF 'exec + ".x86_64"' "$L"; then
	fail "Launcher.cs still builds a path as exec + \".x86_64\"" \
	     "that is inside Valheim.app/Contents/MacOS -- writing there invalidates the bundle seal"
else
	pass "the 'exec + \".x86_64\"' path construction is gone"
fi

# lipo's -output must not land anywhere under the game's bundle. Check what the argument
# actually is rather than trusting the absence of one bad spelling.
lipoOut=$(awk '/"\/usr\/bin\/lipo"/{f=1} f&&/-output/{print; exit}' "$L")
if [ -z "$lipoOut" ]; then
	fail "could not find lipo's -output argument" "extraction is stale; part 1 proves nothing"
else
	echo "$lipoOut" | grep -q 'shadowExec' \
		&& pass "lipo writes to shadowExec (the PhValheim-owned bundle)" \
		|| fail "lipo's -output is not shadowExec" "$lipoOut"
fi

# The shadow path must be rooted in the world directory, not the Steam install.
grep -qF 'Path.Combine(worldDir, "rosetta", "Valheim.app")' "$L" \
	&& pass "the shadow bundle lives under the world directory" \
	|| fail "the shadow bundle is not rooted in worldDir" \
	        "anything under valheimDir is inside Steam's install"

# And codesign must only ever be pointed at our own slice.
#
# Stated POSITIVELY, which matters. The first cut searched the codesign call for the strings
# "valheimDir" or "Valheim.app" and passed when it found neither -- but the pre-fix code signed
# a variable called `x86Exec`, which matches neither pattern, so the check passed on the exact
# code it was written to catch. Verified by running it against 2.0.15: PASS. A blind check.
# So: find every codesign invocation and require its target to be shadowExec by name.
signCount=$(grep -c '"/usr/bin/codesign"' "$L")
if [ "$signCount" -eq 0 ]; then
	fail "no codesign call found at all" "lipo -thin leaves an unsigned slice; extraction may be stale"
elif [ "$signCount" -ne 1 ]; then
	fail "$signCount codesign calls" "each one needs checking by hand; this oracle assumes exactly one"
else
	# The target is the last argument of the single codesign invocation.
	signTarget=$(awk '/"\/usr\/bin\/codesign"/{f=1} f{print} f&&/\}\)\)|shadowExec \}\)/{exit}' "$L" \
		| grep -oE '[A-Za-z_][A-Za-z0-9_]*[ ]*\}\)' | tail -1 | tr -d ' })')
	[ "$signTarget" = "shadowExec" ] \
		&& pass "codesign's target is shadowExec, outside the game's bundle" \
		|| fail "codesign's target is '$signTarget', not shadowExec" \
		        "anything derived from exec/valheimDir is inside Valheim.app and re-signing it replaces Iron Gate's signature"
fi

echo
echo "== part 2: the repair, for users already broken =="

grep -q 'private static void RepairValheimBundle' "$L" \
	&& pass "RepairValheimBundle() exists" \
	|| fail "there is no repair" \
	        "a user whose bundle an older version broke stays broken: Steam's Valheim will not start either"

grep -q '^                RepairValheimBundle(valheimDir);' "$L" \
	&& pass "it is actually called on the macOS launch path" \
	|| fail "RepairValheimBundle is never called" "the method exists and nothing runs it"

# Order matters: the repair has to happen before the Rosetta block looks at the bundle.
zRepair=$(grep -n 'RepairValheimBundle(valheimDir);' "$L" | head -1 | cut -d: -f1)
zRosetta=$(grep -n 'bool useRosetta' "$L" | head -1 | cut -d: -f1)
if [ -n "$zRepair" ] && [ -n "$zRosetta" ]; then
	[ "$zRepair" -lt "$zRosetta" ] \
		&& pass "the repair runs before the Rosetta preparation ($zRepair < $zRosetta)" \
		|| fail "the repair runs after the Rosetta block ($zRepair > $zRosetta)"
else
	fail "could not locate both" "repair=$zRepair rosetta=$zRosetta"
fi

# It must delete ONLY our own leavings. A launcher that removes unrecognised files from
# someone's Steam install is worse than the bug.
grep -q 'GetFiles(macOsDir, "Valheim.x86_64")' "$L" \
	&& pass "it deletes only the file we created, by exact name" \
	|| fail "the repair is not scoped to our own filename" \
	        "deleting anything else out of Contents/MacOS would break the game for real"

# THE CONTROL on the repair: it must NOT re-sign the bundle. Removing the file is sufficient,
# and ad-hoc signing over Iron Gate's identity is a different, worse kind of damage -- it also
# survives a Steam "verify integrity", so the user has no way back.
#
# Guarded on the method EXISTING, because this is a silence assertion: with no
# RepairValheimBundle in the file the awk never enters the method, finds no codesign, and
# reports "the repair does not re-sign anything" about a repair that does not exist. Verified
# against 2.0.15, where it passed for exactly that reason.
if grep -q 'private static void RepairValheimBundle' "$L"; then
	awk '/private static void RepairValheimBundle/{f=1} f&&/codesign/{bad=1} f&&/^        \}$/{exit} END{exit !bad}' "$L" \
		&& fail "the repair re-signs something" \
		        "deleting the stray file already restores the original seal; re-signing replaces it" \
		|| pass "the repair does not re-sign anything -- it only deletes"
else
	fail "cannot judge whether the repair re-signs: there is no repair method" \
	     "this assertion is about RepairValheimBundle's body and there is no body to read"
fi

echo
echo "== part 3: the shadow bundle has the shape Unity needs =="

# Unity's macOS player finds its data via NSBundle.mainBundle as
# <bundle>/Contents/Resources/Data. A loose binary outside a bundle starts with no data at all,
# so the shadow MUST be bundle-shaped and MUST have Resources.
grep -q '"Resources", "Frameworks", "PlugIns"' "$L" \
	&& pass "Resources, Frameworks and PlugIns are all linked in" \
	|| fail "the shadow bundle does not link the game's directories"

grep -q 'Directory.CreateSymbolicLink' "$L" \
	&& pass "they are SYMLINKS, so this costs kilobytes not gigabytes" \
	|| fail "the game directories are not symlinked" \
	        "copying Resources would duplicate a multi-gigabyte install per world"

# Fail closed. A shadow bundle with no Resources would launch and find no data, which looks
# like a game crash rather than a launcher bug.
awk '/if \(!Directory.Exists\(Path.Combine\(shadowContents, "Resources"\)\)\)/{f=1} f&&/return null/{found=1} END{exit !found}' "$L" \
	&& pass "a shadow bundle without Resources returns null (falls back to arm64)" \
	|| fail "a Resources-less shadow bundle is launched anyway" \
	        "Valheim would start and find no data -- indistinguishable from a crash"

# Info.plist must be a real file, not a link: CFBundleExecutable has to name our executable.
grep -q 'File.Copy(realPlist, shadowPlist, true)' "$L" \
	&& pass "Info.plist is copied, not symlinked" \
	|| fail "Info.plist is not copied into the shadow bundle"

# A stale slice must be re-thinned after a Valheim update, or the previous build is launched
# against the current data files.
grep -q 'File.GetLastWriteTimeUtc(exec) > File.GetLastWriteTimeUtc(shadowExec)' "$L" \
	&& pass "a Valheim update invalidates the cached slice" \
	|| fail "the cached x86_64 slice is never refreshed"

echo
echo "== part 4: no hang, and no silent failure =="

# lipo on a ~1 GB binary is slow; a tool that hangs must not hang the launcher.
grep -q 'proc.WaitForExit(60000)' "$L" \
	&& pass "external tools have a timeout" \
	|| fail "no timeout on lipo/codesign" "a hung tool hangs the launcher with no output"

grep -q 'proc.Kill(true)' "$L" \
	&& pass "and a timed-out tool is killed rather than left running" \
	|| fail "a timed-out tool is left running"

# Every failure path must fall back to arm64 with a warning, never proceed silently.
n=$(awk '/private static string PrepareRosettaBundle/{f=1} f&&/return null/{c++} f&&/^        \}$/{exit} END{print c+0}' "$L")
[ "$n" -ge 3 ] \
	&& pass "PrepareRosettaBundle has $n fail-closed exits" \
	|| fail "only $n fail-closed exit(s) in PrepareRosettaBundle" "some failure proceeds silently"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
