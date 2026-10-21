#!/bin/bash
# Upgrade an INSTALLED PhValheim Client on Linux, for real, and read the result back.
#
# Runs INSIDE the distro container the package targets (theoriginalbrian/debian-env for
# .deb, theoriginalbrian/fedora-env for .rpm, either for the tarball), as root. The driver
# is the loop at the bottom of this file's header comment; see `--help`.
#
# WHY. Every static check we had read the package metadata; none of them asked the package
# manager to put a NEW version over an OLD one and then ran what was left. That is the only
# question a player upgrading actually asks, and it is where a renamed path, a changed
# install prefix or a package that is "already installed" to the manager shows up.
#
# The old package must be the PUBLISHED one (gh release download), never a local rebuild:
# a rebuild is provenance, not what players have.
#
# Usage: verify_linux_upgrade.sh <deb|rpm|tgz> <old-pkg> <old-version> <new-pkg> <new-version> [results-tsv]
#
# Driver, from the repo root:
#   for f in deb rpm tgz; do
#     img=theoriginalbrian/debian-env; [ $f = rpm ] && img=theoriginalbrian/fedora-env
#     docker run --rm -v "$PWD":/git:ro -v /path/to/prev:/prev:ro $img \
#       bash /git/builders/verify_linux_upgrade.sh $f /prev/<old> 2.0.15 /git/builds/<new> 2.0.16
#   done

set -u

fmt="${1:?usage: verify_linux_upgrade.sh <deb|rpm|tgz> <old-pkg> <old-version> <new-pkg> <new-version> [results-tsv]}"
oldPkg="${2:?old package path}"
oldVer="${3:?old version}"
newPkg="${4:?new package path}"
newVer="${5:?new version}"
results="${6:-}"

pass=0; failN=0
# Must return 0 with no results file, or `ok` returns 1 and every `ok ... || bad ...` fires both.
emit() { if [ -n "$results" ]; then printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$results"; fi; return 0; }
ok()   { pass=$((pass+1)); echo "  PASS  $1${2:+  ($2)}"; emit PASS "$1" "${2:-}"; }
bad()  { failN=$((failN+1)); echo "  FAIL  $1"; echo "        expected: $2"; echo "        got:      $3"; emit FAIL "$1" "expected $2, got $3"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1" "$3"; else bad "$1" "$2" "$3"; fi; }

[ -f "$oldPkg" ] || { echo "FAIL: old package not a file: $oldPkg"; exit 1; }
[ -f "$newPkg" ] || { echo "FAIL: new package not a file: $newPkg"; exit 1; }
[ -n "$results" ] && : > "$results"

# The client prints "PhValheim Client <version>" as the first line of its banner and, with
# no arguments, explains itself and exits 0 -- no network, no server. That banner is the
# only version the PLAYER ever sees, so it is the oracle; package metadata is a claim.
banner() {
	HOME=/tmp timeout 60 "$1" 2>&1 </dev/null | tr -d '\033' | grep -m1 -o 'PhValheim Client [0-9][0-9.]*' || true
}

work=$(mktemp -d /tmp/phv-upgrade.XXXXXX)
trap 'rm -rf "$work"' EXIT

case "$fmt" in
	deb)
		pkgName=phvalheim-client
		install_pkg() { dpkg -i "$1" >"$work/install.log" 2>&1 || apt-get -y -f install >>"$work/install.log" 2>&1; }
		upgrade_pkg() { install_pkg "$1"; }
		remove_pkg()  { dpkg -r "$pkgName" >"$work/remove.log" 2>&1; }
		mgr_version() { dpkg-query -W -f='${Version}' "$pkgName" 2>/dev/null; }
		mgr_files()   { dpkg -L "$pkgName" 2>/dev/null | grep -v '/$'; }
		mgr_count()   { dpkg-query -W -f='${Status}\n' "$pkgName" 2>/dev/null | grep -c 'install ok installed'; }
		;;
	rpm)
		pkgName=phvalheim-client
		install_pkg() { rpm -ivh "$1" >"$work/install.log" 2>&1; }
		# -U is what a player's `dnf install ./new.rpm` and `rpm -U` both do. A plain -i of a
		# second version leaves BOTH installed, which is a different (wrong) outcome and
		# mgr_count below is what tells the two apart.
		upgrade_pkg() { rpm -Uvh "$1" >"$work/install.log" 2>&1; }
		remove_pkg()  { rpm -e "$pkgName" >"$work/remove.log" 2>&1; }
		mgr_version() { rpm -q --qf '%{VERSION}' "$pkgName" 2>/dev/null; }
		mgr_files()   { rpm -ql "$pkgName" 2>/dev/null; }
		mgr_count()   { rpm -q "$pkgName" 2>/dev/null | grep -c "^$pkgName-"; }
		;;
	tgz)
		pkgName=phvalheim-client
		# The tarball ships its own installer; "upgrade" is running the NEW tarball's
		# installer over the old install, which is all the README tells a player to do.
		# The installer ends with `update-desktop-database -q`, so ITS exit code is that
		# command's. A desktop has it (desktop-file-utils); a minimal container does not,
		# and without this the rig would fail every tarball for a reason that is not the
		# tarball's. The stub is only ever created when the real tool is absent, and says so.
		if ! command -v update-desktop-database >/dev/null 2>&1; then
			printf '#!/bin/sh\nexit 0\n' > /usr/local/sbin/update-desktop-database
			chmod +x /usr/local/sbin/update-desktop-database
			echo "  note  update-desktop-database is not in this image; stubbed (a desktop has desktop-file-utils)"
		fi
		_tgz_run() {
			local d; d=$(mktemp -d "$work/tgz.XXXX")
			tar xzf "$1" -C "$d" || return 1
			( cd "$d" && bash ./phvalheim-client-installer.sh "$2" ) >"$work/install.log" 2>&1
		}
		install_pkg() { _tgz_run "$1" install; }
		upgrade_pkg() { _tgz_run "$1" install; }
		remove_pkg()  { _tgz_run "$newPkg" uninstall; }
		mgr_version() { echo "(tarball: no package manager record)"; }
		mgr_files()   { ls /usr/bin/phvalheim-client /usr/share/applications/phvalheim-client.desktop 2>/dev/null; }
		mgr_count()   { [ -x /usr/bin/phvalheim-client ] && echo 1 || echo 0; }
		;;
	*) echo "unknown format: $fmt"; exit 2 ;;
esac

echo "=== PhValheim Client Linux upgrade: $fmt $oldVer -> $newVer ==="
echo "    old: $oldPkg"
echo "    new: $newPkg"
echo

# ── 1. The OLD release installs, and is what it says it is ───────────────────────────────
echo "-- installing $oldVer --"
if install_pkg "$oldPkg"; then ok "old $fmt installs on a clean system"
else bad "old $fmt installs on a clean system" "exit 0" "$(tail -3 "$work/install.log" | tr '\n' ' ')"; echo; echo "FAILED: nothing to upgrade from."; exit 1; fi

oldBin=$(mgr_files | grep -m1 'bin/phvalheim-client$')
[ -n "$oldBin" ] && [ -x "$oldBin" ] && ok "old binary on PATH" "$oldBin" || bad "old binary on PATH" "an executable bin/phvalheim-client" "${oldBin:-nothing listed}"

# CONTROL. If the banner oracle cannot see the OLD version it cannot see the new one
# either, and every later "version matches" below would be a check that reads itself blind.
eq "CONTROL: old banner reads $oldVer (the oracle can see versions)" "PhValheim Client $oldVer" "$(banner "$oldBin")"
oldFiles=$(mgr_files | sort)

# ── 2. The NEW package goes OVER it ───────────────────────────────────────────────────────
echo
echo "-- upgrading to $newVer --"
if upgrade_pkg "$newPkg"; then ok "new $fmt installs over $oldVer"
else bad "new $fmt installs over $oldVer" "exit 0" "$(tail -3 "$work/install.log" | tr '\n' ' ')"; fi

newBin=$(mgr_files | grep -m1 'bin/phvalheim-client$')
eq "binary path unchanged by the upgrade" "$oldBin" "$newBin"
eq "banner reads $newVer after the upgrade" "PhValheim Client $newVer" "$(banner "${newBin:-$oldBin}")"
case "$fmt" in
	tgz) ok "package-manager version" "$(mgr_version)" ;;
	*)   eq "package manager records $newVer" "$newVer" "$(mgr_version)" ;;
esac
eq "exactly one copy installed (an upgrade, not a second install)" "1" "$(mgr_count)"

# Every file the old package owned is either still owned or gone -- nothing orphaned.
newFiles=$(mgr_files | sort)
orphans=""
while IFS= read -r f; do
	[ -z "$f" ] && continue
	if ! grep -qxF "$f" <<<"$newFiles" && [ -e "$f" ]; then orphans="$orphans $f"; fi
done <<<"$oldFiles"
eq "no file from $oldVer left behind unowned" "" "$orphans"

desk=$(mgr_files | grep -m1 'applications/phvalheim-client.desktop$')
if [ -n "$desk" ] && [ -f "$desk" ]; then
	ex=$(sed -n 's/^Exec=//p' "$desk" | head -1)
	case "$ex" in
		*phvalheim-client*) ok ".desktop Exec names the client" "$ex" ;;
		*) bad ".desktop Exec names the client" "...phvalheim-client..." "$ex" ;;
	esac
	grep -q 'x-scheme-handler/phvalheim' "$desk" && ok ".desktop still claims phvalheim://" || bad ".desktop still claims phvalheim://" "MimeType with x-scheme-handler/phvalheim" "absent"
else
	bad ".desktop file installed" "a phvalheim-client.desktop" "${desk:-none listed}"
fi

# ── 3. And it comes off cleanly ───────────────────────────────────────────────────────────
echo
echo "-- removing --"
if remove_pkg; then ok "upgraded package removes"; else bad "upgraded package removes" "exit 0" "$(tail -2 "$work/remove.log" | tr '\n' ' ')"; fi
[ -e "${newBin:-$oldBin}" ] && bad "binary gone after remove" "absent" "present" || ok "binary gone after remove"

echo
echo "=== $pass passed, $failN failed ($fmt $oldVer -> $newVer) ==="
[ "$failN" -eq 0 ]
