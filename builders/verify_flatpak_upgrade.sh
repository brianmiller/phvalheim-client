#!/bin/bash
# Upgrade an INSTALLED PhValheim Client Flatpak, bundle over bundle, and read the result back.
#
# Runs INSIDE the phvalheim-flatpak-env container (privileged, /dev/fuse, the
# phvalheim-flatpak-cache volume on /var/lib/flatpak so both runtimes are already present):
#
#   docker run --rm --privileged --device /dev/fuse -v phvalheim-flatpak-cache:/var/lib/flatpak \
#     -v "$PWD":/git:ro -v /path/to/prev:/prev:ro phvalheim-flatpak-env \
#     bash /git/builders/verify_flatpak_upgrade.sh /prev/<old>.flatpak 2.0.15 /git/builds/<new>.flatpak 2.0.16
#
# WHY. A bundle-installed app has no remote, so `flatpak update` can never bring a player
# forward -- the only upgrade path is `flatpak install <new bundle>` over the old one. 2.0.16
# also moves the runtime (24.08 -> 25.08), which is precisely the change a same-app-id
# install-over can refuse or half-apply. verify_flatpak.sh deploys each bundle into a CLEAN
# installation; this one deploys the old bundle first and the new one on top, the way a
# player's machine actually looks.
#
# Usage: verify_flatpak_upgrade.sh <old.flatpak> <old-version> <new.flatpak> <new-version> [results-tsv]

set -u

oldBundle="${1:?usage: verify_flatpak_upgrade.sh <old.flatpak> <old-version> <new.flatpak> <new-version> [results-tsv]}"
oldVer="${2:?old version}"
newBundle="${3:?new bundle}"
newVer="${4:?new version}"
results="${5:-}"
appId=com.phvalheim.Client

pass=0; failN=0
# Must return 0 with no results file, or `ok` returns 1 and every `ok ... || bad ...` fires both.
emit() { if [ -n "$results" ]; then printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$results"; fi; return 0; }
ok()   { pass=$((pass+1)); echo "  PASS  $1${2:+  ($2)}"; emit PASS "$1" "${2:-}"; }
bad()  { failN=$((failN+1)); echo "  FAIL  $1"; echo "        expected: $2"; echo "        got:      $3"; emit FAIL "$1" "expected $2, got $3"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1" "$3"; else bad "$1" "$2" "$3"; fi; }

[ -f "$oldBundle" ] || { echo "FAIL: old bundle not a file: $oldBundle"; exit 1; }
[ -f "$newBundle" ] || { echo "FAIL: new bundle not a file: $newBundle"; exit 1; }
[ -n "$results" ] && : > "$results"

# Same scratch-installation shape as verify_flatpak.sh, so a difference between the two
# scripts' verdicts is about the UPGRADE and not about how the app was deployed.
scratch=$(mktemp -d /tmp/flatpak-upgrade.XXXXXX)
instConf="/etc/flatpak/installations.d/phv-upgrade.conf"
mkdir -p /etc/flatpak/installations.d
printf '[Installation "phv-upgrade"]\nPath=%s\n' "$scratch" > "$instConf"
trap 'rm -rf "$scratch" "$instConf"' EXIT

deployDir() { find "$scratch/app/$appId" -maxdepth 4 -name metadata -printf '%h\n' 2>/dev/null | head -1; }
# The client's own banner, run straight from the deployed tree. It is a self-contained
# .NET binary, so it runs outside the sandbox too; with no arguments it prints
# "PhValheim Client <version>" and exits 0 without touching the network.
banner() { HOME=/tmp timeout 60 "$1/files/bin/phvalheim-client" 2>&1 </dev/null | tr -d '\033' | grep -m1 -o 'PhValheim Client [0-9][0-9.]*' || true; }
runtimeOf() { sed -n 's/^runtime=//p' "$1/metadata" | head -1; }
metaVersion() {
	local mi
	mi=$(find "$1/files/share/metainfo" "$1/files/share/appdata" -name "$appId*.xml" 2>/dev/null | head -1)
	[ -n "$mi" ] && sed -n 's/.*<release version="\([^"]*\)".*/\1/p' "$mi" | head -1
}
installedVersion() { flatpak info --installation=phv-upgrade "$appId" 2>/dev/null | sed -n 's/^ *Version: *//p' | head -1; }

echo "=== PhValheim Client Flatpak upgrade: $oldVer -> $newVer ==="
echo "    old: $oldBundle"
echo "    new: $newBundle"
echo

# ── 1. The OLD bundle deploys, and is what it says it is ─────────────────────────────────
echo "-- installing $oldVer --"
if flatpak install --installation=phv-upgrade --noninteractive "$oldBundle" >"$scratch/install-old.log" 2>&1; then
	ok "old bundle installs into a clean installation"
else
	bad "old bundle installs into a clean installation" "exit 0" "$(tail -3 "$scratch/install-old.log" | tr '\n' ' ')"
	echo; echo "FAILED: nothing to upgrade from."; exit 1
fi
oldDeploy=$(deployDir)
[ -n "$oldDeploy" ] && ok "old deployed tree found" "$oldDeploy" || { bad "old deployed tree found" "a metadata file under app/$appId" "none"; exit 1; }
oldRuntime=$(runtimeOf "$oldDeploy")
# CONTROL: the oracles must see the OLD values, or the "new" assertions below prove nothing.
eq "CONTROL: old banner reads $oldVer" "PhValheim Client $oldVer" "$(banner "$oldDeploy")"
eq "CONTROL: old metainfo release is $oldVer" "$oldVer" "$(metaVersion "$oldDeploy")"
ok "old runtime" "$oldRuntime"
oldCommit=$(flatpak info --installation=phv-upgrade "$appId" 2>/dev/null | sed -n 's/^ *Commit: *//p' | head -1)

# ── 2. The NEW bundle goes OVER it ───────────────────────────────────────────────────────
echo
echo "-- upgrading to $newVer --"
if flatpak install --installation=phv-upgrade --noninteractive "$newBundle" >"$scratch/install-new.log" 2>&1; then
	ok "new bundle installs over $oldVer"
else
	bad "new bundle installs over $oldVer" "exit 0" "$(tail -3 "$scratch/install-new.log" | tr '\n' ' ')"
fi
newDeploy=$(deployDir)
[ -n "$newDeploy" ] && ok "deployed tree found after upgrade" "$newDeploy" || { bad "deployed tree found after upgrade" "a metadata file under app/$appId" "none"; exit 1; }
newCommit=$(flatpak info --installation=phv-upgrade "$appId" 2>/dev/null | sed -n 's/^ *Commit: *//p' | head -1)
[ -n "$newCommit" ] && [ "$newCommit" != "$oldCommit" ] && ok "active commit moved" "${oldCommit:0:12} -> ${newCommit:0:12}" || bad "active commit moved" "a different commit from ${oldCommit:0:12}" "${newCommit:-none}"
eq "banner reads $newVer after the upgrade" "PhValheim Client $newVer" "$(banner "$newDeploy")"
eq "metainfo release is $newVer after the upgrade" "$newVer" "$(metaVersion "$newDeploy")"
eq "flatpak info reports $newVer" "$newVer" "$(installedVersion)"
newRuntime=$(runtimeOf "$newDeploy")
case "$newRuntime" in
	*/25.08) ok "runtime is 25.08 after the upgrade" "$newRuntime" ;;
	*) bad "runtime is 25.08 after the upgrade" "org.freedesktop.Platform/x86_64/25.08" "${newRuntime:-none}" ;;
esac
# Consecutive client releases can use the same runtime (2.0.16 and 2.0.17 both
# use 25.08). The target-runtime assertion above validates either path; requiring
# a runtime change here would reject a successful application-only upgrade.
# One app, one active deploy: the installation must not hold two versions side by side.
n=$(flatpak list --installation=phv-upgrade --app --columns=application 2>/dev/null | grep -cx "$appId")
eq "exactly one $appId installed" "1" "$n"
# The exported .desktop still claims the URL scheme -- that is how Launch reaches the client.
desk=$(find "$scratch/exports/share/applications" -name "$appId*.desktop" 2>/dev/null | head -1)
[ -n "$desk" ] && grep -q 'x-scheme-handler/phvalheim' "$desk" && ok "exported .desktop claims phvalheim://" || bad "exported .desktop claims phvalheim://" "MimeType with x-scheme-handler/phvalheim in exports/" "${desk:-no desktop export}"

# ── 3. And it comes off cleanly ───────────────────────────────────────────────────────────
echo
echo "-- removing --"
if flatpak uninstall --installation=phv-upgrade --noninteractive "$appId" >"$scratch/uninstall.log" 2>&1; then ok "upgraded app uninstalls"
else bad "upgraded app uninstalls" "exit 0" "$(tail -2 "$scratch/uninstall.log" | tr '\n' ' ')"; fi
[ -n "$(deployDir)" ] && bad "deploy gone after uninstall" "absent" "present" || ok "deploy gone after uninstall"

echo
echo "=== $pass passed, $failN failed (flatpak $oldVer -> $newVer) ==="
[ "$failN" -eq 0 ]
