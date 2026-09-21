#!/bin/bash
#
# Structural verification of a built .flatpak bundle.
#
# This is the counterpart of verify_msi.sh: it asserts what is IN the artifact,
# not what it does. test_flatpak_runtime.py does the doing.
#
# It works on the SHIPPED BUNDLE, not on flatpak-builder's intermediate build
# directory. Those are not the same thing -- the bundle is what a user
# installs, and a build tree can be correct while the bundle is not.
#
# usage: verify_flatpak.sh <bundle.flatpak> <expected-version>

set -u

bundle="${1:-}"
expectVersion="${2:-}"
appId="com.phvalheim.Client"

if [ -z "$bundle" ] || [ -z "$expectVersion" ]; then
	echo "usage: verify_flatpak.sh <bundle.flatpak> <expected-version>"
	exit 2
fi

checks=0
fails=0

ok() {
	checks=$((checks + 1))
	echo "  PASS  $1"
}

bad() {
	checks=$((checks + 1))
	fails=$((fails + 1))
	echo "  FAIL  $1"
	echo "        expected: $2"
	echo "        actual:   $3"
}

# Compare after stripping CR. Learned from verify_msi.sh, where CRLF made
# every string comparison fail while printing two identical-looking values.
eq() {
	local label="$1" expect="$2" actual="$3"
	actual="${actual%$'\r'}"
	if [ "$actual" = "$expect" ]; then ok "$label"; else bad "$label" "$expect" "${actual:-<empty>}"; fi
}

contains() {
	local label="$1" needle="$2" haystack="$3"
	if [[ "$haystack" == *"$needle"* ]]; then
		ok "$label"
	else
		bad "$label" "a value containing '$needle'" "${haystack:-<empty>}"
	fi
}

absent() {
	local label="$1" needle="$2" haystack="$3"
	if [[ "$haystack" != *"$needle"* ]]; then
		ok "$label"
	else
		bad "$label" "no '$needle'" "$haystack"
	fi
}

echo
echo "Verifying $(basename "$bundle") against version $expectVersion"
echo "================================================================"
echo
echo "-- the bundle file --"

if [ -s "$bundle" ]; then
	ok "bundle exists and is non-empty"
else
	bad "bundle exists and is non-empty" "a file with content" "$bundle"
	echo
	echo "FAILED: nothing to verify."
	exit 1
fi

bundleSize=$(stat -c%s "$bundle")
# A self-contained .NET 9 binary is ~70 MB and compresses to ~25 MB. Anything
# far under that means the binary did not make it into the bundle -- which is
# exactly how the first .msi shipped with no UI: a structurally valid package
# that was missing its content.
if [ "$bundleSize" -gt 10000000 ]; then
	ok "bundle is a plausible size ($bundleSize bytes)"
else
	bad "bundle is a plausible size" ">10 MB (the self-contained binary alone is ~70 MB)" "$bundleSize bytes"
fi

# Debian's `file` has no magic entry for flatpak bundles and reports plain
# "data", so it cannot tell a bundle from a corrupt download. The bundle's own
# header can: it begins with a literal "flatpak" magic followed by a GVariant
# whose "ref" field names the app.
eq "bundle carries the flatpak magic" "flatpak" "$(head -c 7 "$bundle")"

# Translate NULs to newlines rather than deleting them: GVariant packs its
# strings back to back, so deleting the separators glues the next field onto
# the branch name and the ref reads "...master" + whatever followed it.
# -a is required too, or grep prints "Binary file matches" instead of a match.
headerRef=$(head -c 512 "$bundle" | tr '\0' '\n' | grep -axo "app/$appId/x86_64/.*" | head -1)
eq "bundle header names our app ref" "app/$appId/x86_64/master" "$headerRef"

# Deploy into a scratch installation of its own, so this never sees anything
# left behind by a previous build. --no-deps keeps it from downloading the
# runtime; we are inspecting our own contents, not resolving dependencies.
#
# A named installation declared in /etc/flatpak/installations.d is the only
# scratch mechanism that works as root: --user is refused outright for any
# modifying operation when uid 0.
scratch=$(mktemp -d /tmp/flatpak-verify.XXXXXX)
instConf="/etc/flatpak/installations.d/phv-verify.conf"
mkdir -p /etc/flatpak/installations.d
printf '[Installation "phv-verify"]\nPath=%s\n' "$scratch" > "$instConf"
trap 'rm -rf "$scratch" "$instConf"' EXIT

echo
echo "-- deploying to a scratch installation --"
if flatpak install --installation=phv-verify --noninteractive --no-deps \
     "$bundle" > "$scratch/install.log" 2>&1; then
	ok "bundle installs into a clean installation"
else
	bad "bundle installs into a clean installation" "exit 0" "$(tail -3 "$scratch/install.log")"
	echo
	echo "FAILED: cannot inspect a bundle that will not deploy."
	exit 1
fi

# A flatpak installation deploys to app/<id>/<arch>/<branch>/<commit>, with an
# "active" symlink alongside. Resolve via the symlink, and fall back to a
# search so a branch rename does not silently skip every check below.
deploy="$scratch/app/$appId/x86_64/master/active"
if [ ! -e "$deploy/metadata" ]; then
	deploy=$(find "$scratch/app/$appId" -maxdepth 4 -name metadata -printf '%h\n' 2>/dev/null | head -1)
fi

if [ -n "$deploy" ] && [ -d "$deploy" ]; then
	ok "deployed tree found"
else
	bad "deployed tree found" "a directory containing 'metadata'" "$scratch/app/$appId/x86_64"
	echo
	echo "FAILED: nothing deployed."
	exit 1
fi

echo
echo "-- app metadata and permissions --"

metadata="$deploy/metadata"
metaText=$(cat "$metadata" 2>/dev/null)

eq  "metadata declares our app id"  "$appId"  "$(sed -n 's/^name=//p' "$metadata" | head -1)"
eq  "command is the client binary"  "phvalheim-client"  "$(sed -n 's/^command=//p' "$metadata" | head -1)"
contains "runtime is org.freedesktop.Platform 24.08" "org.freedesktop.Platform/x86_64/24.08" \
	"$(sed -n 's/^runtime=//p' "$metadata" | head -1)"

sharedLine=$(sed -n 's/^shared=//p' "$metadata" | head -1)
socketLine=$(sed -n 's/^sockets=//p' "$metadata" | head -1)
fsLine=$(sed -n 's/^filesystems=//p' "$metadata" | head -1)
talkLine=$(sed -n 's/^org.freedesktop.Flatpak=//p' "$metadata" | head -1)

# Mod payloads are fetched over HTTP; without network the client can sync
# nothing and the failure looks like a dead server.
contains "network is shared" "network" "$sharedLine"

# We draw nothing, and the game inherits the host session's own display
# variables through flatpak-spawn, so no graphics socket is needed. Asserting
# their ABSENCE keeps the permission set from drifting wider on the strength
# of an assumption that was measured to be false.
absent "no x11 socket (console-only; the game gets the host's display)" "x11" "$socketLine"
absent "no wayland socket" "wayland" "$socketLine"

contains "home is readable (Steam, Valheim, ~/.config/PhValheim)" "home" "$fsLine"
contains "/run/media granted (Steam Deck SD cards)" "/run/media" "$fsLine"
contains "/media granted" "/media" "$fsLine"
contains "/mnt granted" "/mnt" "$fsLine"

# THE permission. flatpak-spawn --host is how Steam and Valheim get launched
# outside the sandbox; without this the client syncs a world and then silently
# cannot start it.
eq "org.freedesktop.Flatpak talk permission (the host escape)" "talk" "$talkLine"

# Permissions should not widen without someone noticing. These are not granted
# today and granting them is a decision, not an accident.
absent "did not quietly grant --filesystem=host" "host;" "$fsLine"
absent "did not quietly grant --device=all" "all" "$(sed -n 's/^devices=//p' "$metadata" | head -1)"

echo
echo "-- the binary --"

clientBin="$deploy/files/bin/phvalheim-client"
if [ -f "$clientBin" ]; then
	ok "client binary is installed at /app/bin/phvalheim-client"
else
	bad "client binary is installed at /app/bin/phvalheim-client" "a file" "missing"
fi

if [ -x "$clientBin" ]; then
	ok "client binary is executable"
else
	bad "client binary is executable" "mode with +x" "$(stat -c%A "$clientBin" 2>/dev/null)"
fi

binType=$(file -b "$clientBin" 2>/dev/null)
contains "client binary is an x86-64 ELF" "ELF 64-bit" "$binType"
# A single-file self-contained publish is one large ELF with the runtime
# appended. A thin wrapper script or a framework-dependent build would be tiny
# and would fail at runtime on a machine with no .NET.
binSize=$(stat -c%s "$clientBin" 2>/dev/null || echo 0)
if [ "$binSize" -gt 40000000 ]; then
	ok "client binary is self-contained ($binSize bytes)"
else
	bad "client binary is self-contained" ">40 MB (framework-dependent builds are ~200 KB)" "$binSize bytes"
fi

echo
echo "-- the desktop entry (this is the URL handler) --"

desktop="$deploy/files/share/applications/$appId.desktop"
if [ -f "$desktop" ]; then
	ok "desktop file is installed under the app id"
else
	bad "desktop file is installed under the app id" "$appId.desktop" "missing"
fi

dget() { sed -n "s/^$1=//p" "$desktop" 2>/dev/null | head -1; }

eq "desktop Type"     "Application"      "$(dget Type)"
eq "desktop Exec"     "phvalheim-client %u" "$(dget Exec)"
eq "desktop Terminal" "true"             "$(dget Terminal)"
# Must match the installed icon basename or the entry renders blank.
eq "desktop Icon matches the app id" "$appId" "$(dget Icon)"

# The whole reason the Flatpak exists. If this line is wrong the app installs
# perfectly and simply never opens a phvalheim:// link.
contains "desktop registers x-scheme-handler/phvalheim" "x-scheme-handler/phvalheim" "$(dget MimeType)"

if desktop-file-validate "$desktop" > "$scratch/dfv.log" 2>&1; then
	ok "desktop-file-validate is clean"
else
	bad "desktop-file-validate is clean" "no errors" "$(head -3 "$scratch/dfv.log")"
fi

# flatpak only routes a URL to an app whose desktop file it EXPORTED. A file
# that exists in files/share but not in the installation's exports is
# invisible to the desktop: a silent, total failure of the feature that leaves
# a structurally perfect package behind.
exported="$deploy/export/share/applications/$appId.desktop"
if [ -f "$exported" ]; then
	ok "desktop file is marked for export in the deploy tree"
else
	bad "desktop file is marked for export in the deploy tree" "an exported copy" "missing"
fi

instExport="$scratch/exports/share/applications/$appId.desktop"
if [ -f "$instExport" ]; then
	ok "desktop file reaches the installation's exports directory"
else
	bad "desktop file reaches the installation's exports directory" "$instExport" "missing"
fi

# flatpak regenerates this on install; it is what associates the scheme with
# the app for anything reading the desktop database.
mimeCache="$scratch/exports/share/applications/mimeinfo.cache"
if grep -q "x-scheme-handler/phvalheim=.*$appId" "$mimeCache" 2>/dev/null; then
	ok "mimeinfo.cache maps x-scheme-handler/phvalheim to us"
else
	bad "mimeinfo.cache maps x-scheme-handler/phvalheim to us" \
		"a phvalheim scheme line naming $appId" \
		"$(grep phvalheim "$mimeCache" 2>/dev/null || echo '<no phvalheim entry>')"
fi

echo
echo "-- AppStream metadata --"

metainfo="$deploy/files/share/metainfo/$appId.metainfo.xml"
if [ -f "$metainfo" ]; then
	ok "metainfo is installed"
else
	bad "metainfo is installed" "$appId.metainfo.xml" "missing"
fi

metaXml=$(cat "$metainfo" 2>/dev/null)
contains "metainfo id matches the app id" "<id>$appId</id>" "$metaXml"
contains "metainfo launchable points at our desktop file" \
	"<launchable type=\"desktop-id\">$appId.desktop</launchable>" "$metaXml"

# The drift check. The .vdproj kept its own copy of the version, fell behind
# the csproj and shipped an installer that misreported itself.
releaseVersion=$(sed -n 's/.*<release version="\([^"]*\)".*/\1/p' "$metainfo" | head -1)
eq "metainfo release version matches the csproj" "$expectVersion" "$releaseVersion"

absent "no unsubstituted @VERSION@ placeholder" "@VERSION@" "$metaXml"
absent "no unsubstituted @DATE@ placeholder" "@DATE@" "$metaXml"

if command -v appstreamcli >/dev/null 2>&1; then
	if appstreamcli validate --no-net "$metainfo" > "$scratch/as.log" 2>&1; then
		ok "appstreamcli validate passes"
	else
		# Warnings/infos are common and not worth gating a build on; errors are.
		if grep -qE '^E:' "$scratch/as.log"; then
			bad "appstreamcli validate passes" "no E: lines" "$(grep -E '^E:' "$scratch/as.log" | head -3)"
		else
			ok "appstreamcli validate has no errors (warnings only)"
		fi
	fi
else
	echo "  NOTE  appstreamcli not present; AppStream validation skipped"
fi

echo
echo "-- icons --"

iconRoot="$deploy/files/share/icons/hicolor"
iconsFound=0
for size in 16 24 32 48 64 72 96 128 256; do
	p="$iconRoot/${size}x${size}/apps/$appId.png"
	[ -f "$p" ] && iconsFound=$((iconsFound + 1))
done
if [ "$iconsFound" -ge 5 ]; then
	ok "icons installed at $iconsFound sizes"
else
	bad "icons installed at several sizes" ">=5 sizes under hicolor" "$iconsFound"
fi

# 128x128 is the size the .deb and .rpm ship, so it is the one most likely to
# be referenced elsewhere; and an icon that is not really a PNG at the size its
# directory claims is a classic silent theme failure.
icon128="$iconRoot/128x128/apps/$appId.png"
if [ -f "$icon128" ]; then
	dims=$(python3 -c "from PIL import Image;i=Image.open('$icon128');print('%dx%d'%i.size)" 2>/dev/null)
	eq "128x128 icon really is 128x128 PNG" "128x128" "$dims"
else
	bad "128x128 icon really is 128x128 PNG" "a PNG" "missing"
fi

echo
echo "================================================================"
if [ "$fails" -eq 0 ]; then
	echo "OK: $checks flatpak package checks passed"
	exit 0
fi
echo "FAILED: $fails of $checks flatpak package checks failed"
exit 1
