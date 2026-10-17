#!/bin/bash
# Oracle: builders/msi_rebuild_guard.sh refuses to rebuild an already-published .msi version.
#
# WHAT THIS IS PROTECTING. <Product Id="*"> mints a new ProductCode on every build, so building
# 2.0.15 a second time produces a file Windows treats as a DIFFERENT product with the same
# version -- and it will not install over the published one. Re-uploading strands every early
# downloader. verify_msi_identity.sh notices after publication; this guard is the one that can
# still stop it.
#
# THE CASE THIS TEST EXISTS FOR, above the obvious ones: an unresolvable version. An empty
# version string matches no ledger row, so a naive guard answers "never published, go ahead" --
# it passes for the wrong reason, which is how a gate goes quietly blind. Case 5 pins that, and
# the control at the end proves cases 1, 4 and 5 actually discriminate.

set -u
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
GUARD="$REPO/builders/msi_rebuild_guard.sh"
OUTIE="$REPO/builders/build_msi-outie"

PASS=0; FAIL=0
ok(){   echo "  PASS: $1"; PASS=$((PASS+1)); }
bad(){  echo "  FAIL: $1"; [ -n "${2:-}" ] && echo "        $2"; FAIL=$((FAIL+1)); }

[ -f "$GUARD" ] || { echo "FATAL: $GUARD missing"; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

PUBLISHED_CODE='{BE3AA238-8D3E-4B4E-8885-3D85F2AA64CC}'
UPGRADE_CODE='{9799CDE9-1240-47AC-9891-AAB1F6FDB5E7}'

printf '# comment line that must not be parsed as a version\n' >  "$T/ledger.tsv"
printf '2.0.15\t%s\t%s\n' "$PUBLISHED_CODE" "$UPGRADE_CODE"     >> "$T/ledger.tsv"

mkcsproj(){ printf '<Project>\n\t<PropertyGroup>\n\t\t%s\n\t</PropertyGroup>\n</Project>\n' "$1" > "$2"; }
mkcsproj '<Version>2.0.15</Version>' "$T/published.csproj"
mkcsproj '<Version>2.0.99</Version>' "$T/fresh.csproj"
mkcsproj '<AssemblyName>phvalheim-client</AssemblyName>' "$T/noversion.csproj"

# run <guard-under-test> <expect-exit> <label> [env assignments as KEY=VAL ...] -- <args>
# Captures output so the message can be asserted too: an exit code alone cannot tell a correct
# refusal from a refusal for an unrelated reason.
runGuard(){
	local guard="$1"; shift
	local out rc
	out=$(env "$@" bash "$guard" 2>&1); rc=$?
	printf '%s' "$out" > "$T/last.out"
	return $rc
}

echo
echo "== 1. a published version is refused =="
runGuard "$GUARD" LEDGER="$T/ledger.tsv" CSPROJ="$T/published.csproj"
rc=$?
if [ "$rc" -ne 0 ]; then ok "exit $rc (non-zero) for the already-published 2.0.15"
else bad "exited 0 -- it would have rebuilt a published version" "$(cat "$T/last.out")"; fi

if grep -qF "$PUBLISHED_CODE" "$T/last.out"; then
	ok "the refusal names the published ProductCode"
else
	bad "the refusal does not name the published ProductCode" \
	    "without it the operator cannot tell which file they are about to orphan"
fi
if grep -qi 'ALLOW_MSI_REBUILD' "$T/last.out"; then
	ok "the refusal names the override"
else
	bad "the refusal does not say how to proceed deliberately"
fi

echo
echo "== 2. an unpublished version is allowed =="
runGuard "$GUARD" LEDGER="$T/ledger.tsv" CSPROJ="$T/fresh.csproj"
rc=$?
if [ "$rc" -eq 0 ]; then ok "exit 0 for 2.0.99, which has no ledger row"
else bad "refused a first build (exit $rc)" "$(cat "$T/last.out")"; fi
if grep -q -- '--record' "$T/last.out"; then
	ok "and it tells the operator to --record what they publish"
else
	bad "a first build does not mention --record" \
	    "the ledger row is what makes the NEXT rebuild fail; nothing else adds it"
fi

echo
echo "== 3. the override is honoured, and loud =="
runGuard "$GUARD" LEDGER="$T/ledger.tsv" CSPROJ="$T/published.csproj" ALLOW_MSI_REBUILD=1
rc=$?
if [ "$rc" -eq 0 ]; then ok "exit 0 with ALLOW_MSI_REBUILD=1"
else bad "the override did not work (exit $rc)" "$(cat "$T/last.out")"; fi
if grep -qi 'stranded\|will not be able to upgrade' "$T/last.out"; then
	ok "the override still spells out the consequence"
else
	bad "the override is silent about what it costs"
fi

echo
echo "== 4. a missing ledger is fatal, not permissive =="
runGuard "$GUARD" LEDGER="$T/nope.tsv" CSPROJ="$T/published.csproj"
rc=$?
if [ "$rc" -ne 0 ]; then ok "exit $rc when the ledger is absent"
else bad "exited 0 with no ledger" "with nothing to compare against it cannot know it is safe"; fi

echo
echo "== 5. THE VACUOUS CASE: an unresolvable version must refuse =="
runGuard "$GUARD" LEDGER="$T/ledger.tsv" CSPROJ="$T/noversion.csproj"
rc=$?
if [ "$rc" -ne 0 ]; then ok "exit $rc when <Version> cannot be found"
else
	bad "exited 0 on an unknown version" \
	    "an empty version matches no ledger row, so this is a PASS FOR THE WRONG REASON"
fi

echo
echo "== 6. an explicit version argument wins over the csproj =="
out=$(env LEDGER="$T/ledger.tsv" CSPROJ="$T/fresh.csproj" bash "$GUARD" 2.0.15 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then ok "refused 2.0.15 passed as an argument even though the csproj says 2.0.99"
else bad "the argument was ignored (exit 0)" "$out"; fi

echo
echo "== 7. the builder calls the guard BEFORE it does any work =="
if [ -f "$OUTIE" ]; then
	# Measure against a comment-stripped copy. Twice now a regression grep has matched my own
	# explanatory comment and reported a fix that was not there.
	grep -vE '^[[:space:]]*#' "$OUTIE" > "$T/outie.stripped"
	guardLine=$(grep -n 'msi_rebuild_guard' "$T/outie.stripped" | head -1 | cut -d: -f1)
	workLine=$(grep -nE '\$docker (build|run|image pull)' "$T/outie.stripped" | head -1 | cut -d: -f1)
	if [ -n "$guardLine" ]; then
		ok "build_msi-outie invokes the guard (line $guardLine of the stripped file)"
	else
		bad "build_msi-outie never calls msi_rebuild_guard.sh" \
		    "a guard nothing calls is documentation, not a gate"
	fi
	if [ -n "$guardLine" ] && [ -n "$workLine" ] && [ "$guardLine" -lt "$workLine" ]; then
		ok "the guard runs before the first docker step (guard $guardLine < work $workLine)"
	else
		bad "the guard does not precede the build work" \
		    "guard=$guardLine first-docker-step=$workLine"
	fi
	if grep -qE 'msi_rebuild_guard[^|]*\|\| exit 1|exit 1$' "$T/outie.stripped" \
	   && grep -q 'msi_rebuild_guard.*|| exit 1' "$T/outie.stripped"; then
		ok "the guard's refusal actually aborts the build (|| exit 1)"
	else
		bad "the guard is called but its exit status is ignored" \
		    "it would print the refusal and then build anyway"
	fi
else
	bad "build_msi-outie not found at $OUTIE"
fi

# ---------------------------------------------------------------------------
# CONTROL. A guard that just waves everything through must LOSE cases 1, 4 and 5.
# If it passes them, those cases are not testing what they claim to and the whole file is
# decoration. This is history-independent: unlike a --control diff against HEAD, it keeps
# working after the real fix is committed.
# ---------------------------------------------------------------------------
echo
echo "== control: a permissive guard must fail cases 1, 4 and 5 =="
cat > "$T/naive.sh" <<'NAIVE'
#!/bin/bash
# The guard as it would be written without thinking about it: read a version, look it up,
# and treat "not found" as permission.
set -u
version="${1:-}"
[ -z "$version" ] && version=$(grep -oE '<Version>[^<]+</Version>' "${CSPROJ:-}" 2>/dev/null | head -1 | sed -E 's|</?Version>||g')
grep -qE "^${version}	" "${LEDGER:-/nonexistent}" 2>/dev/null && { echo "already published"; exit 0; }
echo "fine, build it"
exit 0
NAIVE

controlFails=0
# case 1 equivalent
env LEDGER="$T/ledger.tsv" CSPROJ="$T/published.csproj" bash "$T/naive.sh" >/dev/null 2>&1 \
	&& controlFails=$((controlFails+1))
# case 4 equivalent
env LEDGER="$T/nope.tsv" CSPROJ="$T/published.csproj" bash "$T/naive.sh" >/dev/null 2>&1 \
	&& controlFails=$((controlFails+1))
# case 5 equivalent
env LEDGER="$T/ledger.tsv" CSPROJ="$T/noversion.csproj" bash "$T/naive.sh" >/dev/null 2>&1 \
	&& controlFails=$((controlFails+1))

if [ "$controlFails" -eq 3 ]; then
	ok "the permissive control wrongly allows all three -- the real guard's refusals are load-bearing"
else
	bad "the control was only wrong $controlFails/3 times" \
	    "at least one of cases 1/4/5 would pass against a guard that does nothing"
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
