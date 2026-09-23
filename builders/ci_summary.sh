#!/bin/bash
#
# Render a verify_macos.sh results TSV as a markdown table into the GitHub
# Actions job summary, so the pipeline's answer is readable without opening a
# log. Falls back to stdout when run outside Actions.
#
# Usage: ci_summary.sh <section title> <results.tsv>

set -u

title="${1:?usage: ci_summary.sh <title> <results.tsv>}"
tsv="${2:?usage: ci_summary.sh <title> <results.tsv>}"
out="${GITHUB_STEP_SUMMARY:-/dev/null}"

{
	echo "## $title"
	echo

	if [ ! -s "$tsv" ]; then
		echo "_No checks ran — the step that produces them failed first._"
		echo
		exit 0
	fi

	# Headline counts first: the question is "did it work", not "what ran".
	pass=$(awk -F'\t' '$1=="PASS"' "$tsv" | wc -l | tr -d ' ')
	fail=$(awk -F'\t' '$1=="FAIL"' "$tsv" | wc -l | tr -d ' ')
	warn=$(awk -F'\t' '$1=="WARN"' "$tsv" | wc -l | tr -d ' ')

	if [ "$fail" -gt 0 ]; then
		echo "### ❌ $fail failed &nbsp;·&nbsp; $pass passed &nbsp;·&nbsp; $warn warnings"
	else
		echo "### ✅ All $pass checks passed &nbsp;·&nbsp; $warn warnings"
	fi
	echo

	echo "| | Check | Detail |"
	echo "|---|---|---|"
	# Failures at the top — the reader should not have to scan for them.
	for want in FAIL WARN PASS INFO; do
		awk -F'\t' -v want="$want" 'BEGIN{OFS=""}
			$1==want {
				icon = ($1=="PASS") ? "✅" : ($1=="FAIL") ? "❌" : ($1=="WARN") ? "⚠️" : "ℹ️"
				gsub(/\|/, "\\|", $2); gsub(/\|/, "\\|", $3)
				print "| ", icon, " | ", $2, " | ", ($3=="" ? "—" : $3), " |"
			}' "$tsv"
	done
	echo
} | tee -a "$out"
