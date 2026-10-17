#!/bin/bash
# Refuse to build an .msi for a version that has ALREADY BEEN PUBLISHED.
#
# WHY. builders/wxs/phvalheim-client.wxs declares <Product Id="*">, so wixl mints a brand new
# ProductCode on EVERY build. Two .msi files carrying the same ProductVersion are therefore
# different products to Windows: the same-version row in the Upgrade table is OnlyDetect plus a
# LaunchCondition, so installing one over the other does not upgrade -- it refuses.
#
# So a rebuilt-and-re-uploaded asset strands everyone who downloaded the first file. They cannot
# upgrade and cannot cleanly reinstall. It happened on 2026-10-17: the 2.0.15 msi was built at
# 01:24, attached to the release, then rebuilt at 04:40 and clobbered the asset.
#
# verify_msi_identity.sh catches that AFTER the fact, in CI, once the damage is published. This
# guard catches it BEFORE the build runs, on the machine doing the damage -- which is the only
# place the mistake is still free to undo.
#
# Usage:
#   msi_rebuild_guard.sh                 # version read from phvalheim-client.csproj
#   msi_rebuild_guard.sh 2.0.16          # explicit version
#   LEDGER=/path/to.tsv msi_rebuild_guard.sh 2.0.16      # for the oracle
#
# Exit 0 = go ahead.  Exit 1 = refuse.
#
# Override: ALLOW_MSI_REBUILD=1 -- for the case where a ledger row exists but the asset was
# never actually published, or you have deliberately decided to strand the early downloaders.
# It is loud on purpose. It is not a flag to reach for twice.

set -u

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LEDGER="${LEDGER:-$REPO/builders/msi-productcodes.tsv}"
CSPROJ="${CSPROJ:-$REPO/phvalheim-client.csproj}"

version="${1:-}"
if [ -z "$version" ]; then
	version=$(grep -oE '<Version>[^<]+</Version>' "$CSPROJ" 2>/dev/null \
		| head -1 | sed -E 's|</?Version>||g')
fi

# A guard that cannot work out what it is guarding must not wave the build through. An empty
# version matches no ledger row, so the "is it published" test would answer "no" for the wrong
# reason -- the exact shape that makes a gate pass vacuously.
if [ -z "$version" ]; then
	echo "FATAL: msi_rebuild_guard could not determine the version to build."
	echo "       Looked for <Version> in: $CSPROJ"
	echo "       Refusing rather than guessing -- an unknown version matches no ledger row,"
	echo "       which would look exactly like 'this version was never published'."
	exit 1
fi

if [ ! -f "$LEDGER" ]; then
	echo "FATAL: the published-identity ledger is missing: $LEDGER"
	echo "       Without it this guard cannot tell a first build from a re-upload."
	exit 1
fi

row=$(grep -E "^${version}	" "$LEDGER" | head -1)

if [ -z "$row" ]; then
	echo "msi_rebuild_guard: $version has no published identity on record -- first build, OK."
	echo
	echo "  AFTER you publish the .msi to its GitHub release, record what you shipped:"
	echo "      builders/verify_msi_identity.sh --record $version"
	echo "  That is what makes the next accidental rebuild of $version fail instead of"
	echo "  silently stranding whoever downloaded this one."
	exit 0
fi

publishedCode=$(printf '%s' "$row" | cut -f2)

if [ "${ALLOW_MSI_REBUILD:-}" = "1" ]; then
	echo "msi_rebuild_guard: $version IS already published as $publishedCode."
	echo "  ALLOW_MSI_REBUILD=1 is set, so continuing anyway."
	echo
	echo "  READ THIS: the .msi this build produces will carry a DIFFERENT ProductCode."
	echo "  Anyone holding the currently published $version file will not be able to upgrade"
	echo "  to it or cleanly reinstall. If that file ever reached a player, they are stranded"
	echo "  and their only route out is an uninstall by hand."
	echo
	echo "  If you do replace the published asset, update the ledger to match:"
	echo "      builders/verify_msi_identity.sh --record $version --replace"
	exit 0
fi

echo "REFUSING TO BUILD: version $version has already been published."
echo
echo "  published ProductCode: $publishedCode"
echo "  ledger:                $LEDGER"
echo
echo "  <Product Id=\"*\"> mints a NEW ProductCode on every build, so the .msi this would"
echo "  produce is a DIFFERENT PRODUCT to Windows even though it says $version on the tin."
echo "  Re-uploading it over the published asset strands everyone who already downloaded the"
echo "  original: Windows refuses to install one same-version product over the other."
echo
echo "  What to do instead:"
echo "    * Shipping a fix?   Bump <Version> in phvalheim-client.csproj and build that."
echo "    * Asset never published / release was deleted?  ALLOW_MSI_REBUILD=1 <command>"
echo
exit 1
