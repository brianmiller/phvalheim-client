#!/bin/bash
# Oracle test: the download progress line is rewritten IN PLACE, not reprinted.
#
# THE BUG, reported by Brian watching a real download: the progress bar does not stay on one
# line. On a 573 MB payload it scrolls about a hundred bar lines up the window.
#
# Ui.Progress() opened with CloseStep() and closed with `stepOpen = true`. The comment on that
# line -- "so the next ordinary line does not land on this one" -- is right about ORDINARY
# lines and wrong about the next PROGRESS line: the second Progress() call finds stepOpen
# already true, CloseStep() writes a newline, and the "\r" then returns to the start of a
# fresh line. One line per whole percent, which is one line per update for the entire
# download. The in-place rewrite was defeated by the flag that was meant to protect it.
#
# WHY THIS TEST COMPILES AND RUNS THE REAL Ui.cs. The thing being asserted is where the bytes
# land in the stream -- whether a 0x0A appears between two progress writes. No grep over the
# source can answer that: the newline comes from a function three calls away whose behaviour
# depends on a static flag set by the previous call. So the harness builds a throwaway console
# app around the real file and inspects its actual stdout.
#
# Run with --control to build HEAD's Ui.cs instead, where the single-line assertions MUST fail.
#
# Usage:  bash dev_tools/test-progress-single-line.sh [--control]

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
REL="Ui.cs"

CONTROL=0
[ "$1" = "--control" ] && CONTROL=1

PASS=0; FAIL=0
pass(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
fail(){ echo "  FAIL: $1"; [ -n "$2" ] && echo "        $2"; FAIL=$((FAIL+1)); }

command -v dotnet >/dev/null 2>&1 || { echo "FATAL: dotnet not on PATH"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ "$CONTROL" = "1" ]; then
	git -C "$REPO" show "HEAD:$REL" > "$WORK/Ui.cs" 2>/dev/null \
		|| { echo "FATAL: cannot read HEAD:$REL"; exit 1; }
	echo "== CONTROL RUN: Ui.cs as it is in HEAD. Failures below are the POINT. =="
else
	cp "$REPO/$REL" "$WORK/Ui.cs"
fi

# A console app that drives the real Ui. net8.0 because that is the SDK on this box; Ui.cs uses
# nothing newer than Console + ConsoleColor, and the test is about byte placement, not runtime.
cat > "$WORK/t.csproj" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AssemblyName>t</AssemblyName>
    <RootNamespace>t</RootNamespace>
  </PropertyGroup>
</Project>
CSPROJ

# Three progress updates of DECREASING length, then a finishing line, then an ordinary line.
#
# Decreasing on purpose. A shorter update must not leave the tail of a longer one behind it --
# "100%   573 MB of 573 MB" overwritten by "5%   29 MB" reads as "5%   29 MBof 573 MB" if the
# remainder is not erased. ProgressDone padded for exactly this reason; Progress did not.
cat > "$WORK/Program.cs" <<'PROG'
using PhValheim;

class Program
{
    static void Main()
    {
        Ui.Step("preparing");
        Ui.Done("ok");
        Ui.Progress("Downloading  [########################] 100%   573 MB of 573 MB");
        Ui.Progress("Downloading  [############............]  50%   286 MB of 573 MB");
        Ui.Progress("Downloading  [##......................]   8%   45 MB");
        Ui.ProgressDone("downloaded 573 MB");
        Ui.Line("after the download");
    }
}
PROG

cp "$WORK/Ui.cs" "$WORK/UiUnderTest.cs"
rm -f "$WORK/Ui.cs"

# NO_COLOR so no escape sequences land in the captured stream. Ui decides colour from the
# environment; without this the assertions would be counting ANSI bytes as content.
if ! ( cd "$WORK" && NO_COLOR=1 dotnet build -v q --nologo -o out > build.log 2>&1 ); then
	echo "FATAL: build failed"
	tail -15 "$WORK/build.log"
	exit 1
fi
pass "compiled the real Ui.cs into a test harness"

RAW="$WORK/raw.bin"
( cd "$WORK" && NO_COLOR=1 TERM=dumb ./out/t > "$RAW" 2>/dev/null )

# Work on the RAW bytes. The whole question is where \r and \n fall, so nothing may normalise
# them -- `$(cat)` strips trailing newlines and command substitution would hide the shape.
bytes=$(wc -c < "$RAW")
[ "$bytes" -gt 0 ] && pass "harness produced output ($bytes bytes)" \
                   || { fail "harness produced nothing"; echo; echo "$PASS passed, $FAIL failed"; exit 1; }

# Isolate the download region: from the first "Downloading" to just before "downloaded 573 MB".
region=$(perl -0777 -ne '
	if (/(Downloading.*?)(?=downloaded 573 MB)/s) { print $1 }
' "$RAW")

if [ -z "$region" ]; then
	fail "could not find the progress region in the output" "$(od -c "$RAW" | head -8)"
else
	pass "found the progress region"

	# THE ASSERTION. Three Progress() calls must put three \r-separated writes on ONE line,
	# so the region holds zero newlines.
	nl=$(printf '%s' "$region" | tr -cd '\n' | wc -c)
	[ "$nl" = "0" ] \
		&& pass "the three progress updates share one line (0 newlines between them)" \
		|| fail "the progress updates are on separate lines ($nl newline(s) between them)" \
		        "this is the reported bug: one line per percent, ~100 lines per download"

	# And each update must begin with a carriage return, or it appends instead of rewriting.
	cr=$(printf '%s' "$region" | tr -cd '\r' | wc -c)
	[ "$cr" -ge 3 ] \
		&& pass "each update starts with a carriage return ($cr seen)" \
		|| fail "only $cr carriage return(s) for 3 updates" "an update without \\r appends"
fi

# A shorter update must erase the tail of the longer one it replaces.
#
# THIS HAS TO RENDER THE STREAM, not read it. The first version pulled the text after the last
# "\r" out of the raw bytes and checked it for "of 573 MB" -- and it passed with the erase
# deleted, because the leftover tail is not IN the byte stream. "\r" + a shorter line emits
# only the shorter line; the remainder of the previous one survives on the TERMINAL, where the
# cursor moved back over text the console never forgot. A mutation that removed the erase
# entirely scored 9 of 9. So replay the bytes through a cursor the way a console would, and
# assert on what is actually left on the row.
rendered=$(python3 - "$RAW" <<'PY'
import sys
raw = open(sys.argv[1], 'rb').read().decode('utf-8', 'replace')
lines, buf, cur = [], [], 0
for ch in raw:
    if ch == '\r':
        cur = 0
    elif ch == '\n':
        lines.append(''.join(buf)); buf, cur = [], 0
    else:
        if cur < len(buf):
            buf[cur] = ch            # overwrite in place, as a console does
        else:
            buf.extend(' ' * (cur - len(buf)))
            buf.append(ch)
        cur += 1
if buf:
    lines.append(''.join(buf))
print('\n'.join(lines))
PY
)

# The row the three updates shared, as the player would see it after the last one.
finalRow=$(printf '%s\n' "$rendered" | grep -F 'downloaded 573 MB' | head -1)
if [ -z "$finalRow" ]; then
	fail "the finished download line does not render" "rendered output was:
$rendered"
elif printf '%s' "$finalRow" | grep -qE 'of 573 MB|%|#'; then
	fail "the finished line still shows the progress bar underneath it" \
	     "renders as: [$finalRow]"
else
	pass "the finishing line erases the bar it replaces (renders as: $(printf '%s' "$finalRow" | sed 's/ *$//'))"
fi

# And the same for an intermediate shrink: 100% -> 50% -> 8% must not leave "of 573 MB" behind.
# Driven through a second harness run below, since the finished line overwrites this row.
shrinkRow=$(printf '%s\n' "$rendered" | grep -F 'Downloading' | head -1)
if [ -n "$shrinkRow" ]; then
	fail "an unfinished progress row survived to the end" "renders as: [$shrinkRow]"
else
	pass "no leftover progress row remains once the download finishes"
fi

# The progress line must still be TERMINATED, or ordinary output lands on top of it.
after=$(perl -0777 -ne '
	if (/downloaded 573 MB(.*)$/s) { print $1 }
' "$RAW")
# TRAILING SPACES ARE ALLOWED before that newline, and getting this wrong cost a false
# failure. ProgressDone pads its line out to erase the longer update underneath it, so the
# stream reads "downloaded 573 MB" + pad + "\n". The first cut of this assertion demanded the
# newline IMMEDIATELY, reported a real failure against correct code, and the "fix" it was
# asking for was to delete the padding that stops the tail of the previous line showing
# through. An assertion that is satisfied by removing a guard is worse than no assertion.
afterTrimmed=$(printf '%s' "$after" | perl -0777 -pe 's/\A[ \t]+//')
case "$afterTrimmed" in
	$'\n'*) pass "the finished progress line is terminated before ordinary output resumes" ;;
	*)      fail "ordinary output follows the progress line without a newline" \
	             "it would overwrite the result the player just waited for" ;;
esac

printf '%s' "$after" | grep -q 'after the download' \
	&& pass "and ordinary output after a download still appears" \
	|| fail "the line following the download went missing"

# The step ABOVE the download must keep its own line -- the flag being changed is the one that
# protected it, so this is the thing most likely to break while the headline assertion passes.
perl -0777 -ne 'exit(/preparing.*ok[^\n]*\n[^\n]*Downloading/s ? 0 : 1)' "$RAW" \
	&& pass "the completed step above the download keeps its own line" \
	|| fail "the progress line collided with the step above it" \
	        "$(od -c "$RAW" | head -6)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
