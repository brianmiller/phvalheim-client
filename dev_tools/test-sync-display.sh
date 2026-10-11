#!/bin/sh
# Oracle for the SYNC-STATUS DISPLAY contract in Ui.cs.
#
# Why this exists, specifically:
#
# The verbose output used to print "local payload" and "server payload" as an adjacent pair of
# md5s. Nothing in the client compares those two. The server rebuilds the world zip whenever mod
# settings change, so on a perfectly synced install they differ FOREVER -- and a reader seeing two
# unequal checksums side by side under a sync heading concludes, correctly on the evidence shown
# and wrongly in fact, that the install is out of sync. Brian hit exactly that and asked why they
# were "always out of sync".
#
# So the contract is not "do the checksums get printed". It is:
#
#   1. Anything displayed as a PAIR states its own verdict (SAME / DIFFER).
#   2. A value that is NOT part of a comparison is labelled as not compared.
#   3. The regression case -- mod content equal, payload bytes unequal -- produces NO
#      "DIFFER" anywhere. This is the assertion that would have failed before the fix.
#
# Note 3 is the only one of these that is a statement about the BUG rather than about the
# formatting. A test of 1 and 2 alone would pass on the broken code, because the broken code's
# problem was an extra truthful-but-uncompared pair, not a malformed line.
#
# This drives the REAL Ui.cs -- it is copied in, not reimplemented -- so the assertions are
# about shipped behaviour. Colour is deliberately disabled (NO_COLOR) so the assertions match
# text and cannot be defeated by escape sequences landing mid-token.

REPO=$(cd "$(dirname "$0")/.." && pwd)
SDK=mcr.microsoft.com/dotnet/sdk:9.0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/t"
cp "$REPO/Ui.cs" "$WORK/t/Ui.cs"

cat > "$WORK/t/t.csproj" <<'PROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <RootNamespace>PhValheim</RootNamespace>
    <AssemblyName>t</AssemblyName>
  </PropertyGroup>
</Project>
PROJ

cat > "$WORK/t/Program.cs" <<'PROG'
using PhValheim;

class T
{
    static void Main()
    {
        // CASE A -- the regression. A synced world whose payload the server repackaged:
        // mod content identical, payload bytes different. This is Brian's report.
        Console.WriteLine("--CASE-A--");
        Ui.Compare("mod content", "whether the full payload downloads",
                   "1f1854db4888186af7a611f721b5d235", "1f1854db4888186af7a611f721b5d235");
        Ui.Reference("payload bytes", "5511377080e586144daff4639bc7ea7f",
                     "the server rebuilds the zip whenever settings change");
        Ui.Compare("mod settings", "whether the small settings update downloads",
                   "a1b2c3d4e5f60718293a4b5c6d7e8f90", "a1b2c3d4e5f60718293a4b5c6d7e8f90");

        // CASE B -- a genuine difference must still be reported as one.
        Console.WriteLine("--CASE-B--");
        Ui.Compare("mod content", "whether the full payload downloads",
                   "1f1854db4888186af7a611f721b5d235", "7c3e9a0b1d2f4856a7b8c9d0e1f20314");

        // CASE C -- no local record. "I don't know" must read as DIFFER, not as SAME, and must
        // not render as an empty value.
        Console.WriteLine("--CASE-C--");
        Ui.Compare("mod settings", "whether the small settings update downloads",
                   "", "a1b2c3d4e5f60718293a4b5c6d7e8f90");

        Console.WriteLine("--END--");
    }
}
PROG

# Run twice. The verbose gate is an ENV VAR read once into a get-only property, so the only
# faithful way to test both sides of it is two processes -- not a test-only setter, which would
# add a seam to shipped code that nothing else needs.
run() {
    docker run --rm --user "$(id -u):$(id -g)" -v "$WORK":/w -w /w/t \
      -e DOTNET_CLI_TELEMETRY_OPTOUT=1 -e DOTNET_NOLOGO=1 \
      -e HOME=/tmp -e DOTNET_CLI_HOME=/tmp -e XDG_DATA_HOME=/tmp \
      -e PHVALHEIM_VERBOSE="$1" -e NO_COLOR=1 \
      "$SDK" sh -c 'dotnet run -v q --nologo 2>&1'
}

OUT="$WORK/out.txt"
QUIET="$WORK/quiet.txt"
run 1 > "$OUT" || { echo "FAILED: the verbose harness did not build or run"; sed -n '1,40p' "$OUT"; exit 1; }
run ""  > "$QUIET" || { echo "FAILED: the non-verbose harness did not run"; sed -n '1,40p' "$QUIET"; exit 1; }

CHECKS=0
FAILS=0
chk() {
    CHECKS=$((CHECKS + 1))
    if [ "$2" = "yes" ]; then
        echo "  PASS  $1"
    else
        FAILS=$((FAILS + 1))
        echo "  FAIL  $1"
        [ -n "$3" ] && echo "        $3"
    fi
}

section() { sed -n "/^--$1--\$/,/^--/p" "$OUT" | sed '1d;$d'; }

A=$(section CASE-A)
B=$(section CASE-B)
C=$(section CASE-C)

echo "Sync-status display contract"
echo "======================================================================"

# ---- the control. If the harness printed nothing, every absence check below is vacuous
# and would report success on a completely broken build.
chk "CONTROL: the harness produced comparison output" \
    "$(test -n "$A" && echo yes)" "CASE-A section is empty"
chk "CONTROL: a verdict token exists at all" \
    "$(echo "$A" | grep -qF 'SAME' && echo yes)" "no SAME anywhere in CASE-A"

echo
echo "-- the regression: repackaged payload on a synced world --"
# THE assertion. Pre-fix this failed: the uncompared local/server payload pair was shown, and
# nothing marked it as uncompared, so the output carried an unexplained mismatch.
chk "no DIFFER appears when only the payload bytes moved" \
    "$(echo "$A" | grep -qF 'DIFFER' || echo yes)" \
    "$(echo "$A" | grep -F 'DIFFER')"
chk "mod content is reported SAME" \
    "$(echo "$A" | grep -F 'mod content' | grep -qF 'SAME' && echo yes)" \
    "$(echo "$A" | grep -F 'mod content')"
chk "the payload byte checksum is labelled not compared" \
    "$(echo "$A" | grep -qF 'not compared' && echo yes)" \
    "no 'not compared' label in CASE-A"
chk "the payload byte value is still shown (not merely hidden)" \
    "$(echo "$A" | grep -qF '5511377080e586144daff4639bc7ea7f' && echo yes)" \
    "the value was dropped rather than explained"

echo
echo "-- every pair carries its own verdict --"
# Walk each [compare] line and require a verdict on it. A pair of checksums with no verdict is
# the exact shape of the original defect, whatever the label says.
NOVERDICT=$(echo "$A
$B
$C" | grep -F '[compare]' | grep -vE 'SAME|DIFFER' || true)
chk "no [compare] line lacks SAME or DIFFER" \
    "$(test -z "$NOVERDICT" && echo yes)" "$NOVERDICT"
chk "each compare names the decision it drives" \
    "$(test "$(echo "$A$B$C" | grep -cF 'decides')" -ge 4 && echo yes)" \
    "found $(echo "$A$B$C" | grep -cF 'decides') 'decides' lines, want >= 4"

echo
echo "-- a real difference is still reported --"
chk "differing mod content reports DIFFER" \
    "$(echo "$B" | grep -F 'mod content' | grep -qF 'DIFFER' && echo yes)" "$B"
chk "and does NOT report SAME" \
    "$(echo "$B" | grep -qF 'SAME' || echo yes)" "$B"

echo
echo "-- an unknown local value is a difference, not a match --"
chk "missing local checksum reports DIFFER" \
    "$(echo "$C" | grep -qF 'DIFFER' && echo yes)" "$C"
chk "missing local checksum renders as a stated absence" \
    "$(echo "$C" | grep -qF '(none recorded)' && echo yes)" "$C"
chk "no blank-looking value is printed for it" \
    "$(echo "$C" | grep -qE 'yours +$' || echo yes)" "an empty 'yours' line was printed"

echo
echo "-- none of this reaches a non-verbose run --"
chk "Compare prints nothing when not verbose" \
    "$(grep -qF '[compare]' "$QUIET" || echo yes)" "$(grep -F '[compare]' "$QUIET")"
chk "Reference prints nothing when not verbose" \
    "$(grep -qF '[value]' "$QUIET" || echo yes)" "$(grep -F '[value]' "$QUIET")"
chk "no checksum leaks to a player" \
    "$(grep -qF '1f1854db4888186af7a611f721b5d235' "$QUIET" || echo yes)" \
    "a checksum appeared in the non-verbose run"
# Without this, every absence check above passes on a run that crashed before printing.
chk "CONTROL: the non-verbose run reached the end" \
    "$(grep -qF -- '--END--' "$QUIET" && echo yes)" "the non-verbose program did not complete"
chk "CONTROL: the verbose run reached the end" \
    "$(grep -qF -- '--END--' "$OUT" && echo yes)" "the verbose program did not complete"

echo
echo "-- Syncer actually uses it: the pre-fix defect cannot come back --"
# THE pre-fix oracle. Everything above drives Ui.cs through this script's own driver, so on the
# broken code it would not have failed -- Ui.Compare did not exist, the harness simply would not
# compile. Those checks guard the primitive's behaviour; they do not prove the CALLER is right.
#
# The defect was in Syncer.cs: it printed "local payload" and "server payload" as two adjacent
# Ui.Detail lines, an uncompared pair that reads as a verdict. These assertions are statements
# about that call sequence, and they fail on the pre-fix file. Verified by running this suite
# against git HEAD~ -- see the note in the commit.
S="$REPO/Syncer.cs"
chk "CONTROL: Syncer.cs was found and is non-trivial" \
    "$(test "$(wc -l < "$S")" -gt 100 && echo yes)" "Syncer.cs missing or truncated"
chk "Syncer no longer prints a 'local payload' detail line" \
    "$(grep -qF 'Ui.Detail("local payload"' "$S" || echo yes)" \
    "$(grep -nF 'Ui.Detail("local payload"' "$S")"
chk "Syncer no longer prints a 'server payload' detail line" \
    "$(grep -qF 'Ui.Detail("server payload"' "$S" || echo yes)" \
    "$(grep -nF 'Ui.Detail("server payload"' "$S")"
chk "Syncer no longer prints bare 'local mods' / 'server mods' details" \
    "$(grep -qE 'Ui\.Detail\("(local|server) mods"' "$S" || echo yes)" \
    "$(grep -nE 'Ui\.Detail\("(local|server) mods"' "$S")"
chk "Syncer states the download decision through Ui.Compare" \
    "$(test "$(grep -cF 'Ui.Compare(' "$S")" -ge 3 && echo yes)" \
    "found $(grep -cF 'Ui.Compare(' "$S") Ui.Compare calls, want >= 3"
chk "Syncer labels the uncompared payload checksum via Ui.Reference" \
    "$(grep -qF 'Ui.Reference(' "$S" && echo yes)" "no Ui.Reference call in Syncer.cs"
# The settings comparison must be taken against what we HOLD after the payload step. Comparing
# the pre-download value would print DIFFER immediately before the download resolves it --
# a different flavour of the same "shows a difference that isn't one" bug.
chk "the settings compare uses the post-payload held value" \
    "$(grep -A3 'Ui.Compare("mod settings"' "$S" | grep -qF 'heldConfigMD5' && echo yes)" \
    "$(grep -A3 'Ui.Compare("mod settings"' "$S")"

echo
echo "======================================================================"
if [ "$FAILS" -eq 0 ]; then
    echo "OK: $CHECKS sync-display checks passed"
    exit 0
fi
echo "FAILED: $FAILS of $CHECKS sync-display checks failed"
exit 1
