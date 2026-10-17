#!/bin/bash
# Take a screenshot. macOS and Linux. FOR A HUMAN TO LOOK AT.
#
# These are not assertions and they gate nothing. A screenshot passes no matter how wrong the
# pixels are, so treating one as proof would be the same trap as a test that measures nothing.
# Every failure path here exits 0 on purpose: a broken camera must not turn a good build red.
#
# Usage:
#   shot.sh <label>                 capture the screen into $SHOT_DIR
#   SHOT_DIR=screens shot.sh boot   explicit directory (default: ./screens)
#
# Each file is numbered in capture order via a counter file, so the artifact reads as a
# sequence rather than a bag of names. An INDEX.txt is appended alongside, because a pile of
# numbered pngs explains nothing six months later.

SHOT_DIR="${SHOT_DIR:-screens}"
label="${1:-shot}"
mkdir -p "$SHOT_DIR" 2>/dev/null

ctr="$SHOT_DIR/.counter"
n=$(cat "$ctr" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$ctr"

safe=$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '_')
out=$(printf '%s/%02d-%s.png' "$SHOT_DIR" "$n" "$safe")

captured=""
if [ "$(uname -s)" = "Darwin" ]; then
	# -x suppresses the capture sound. Without -o the shadow is included, which on a window
	# capture doubles the margin for no information.
	if screencapture -x "$out" 2>/dev/null; then captured="screencapture"; fi
else
	# ImageMagick's import against the X display. The display must already exist -- this does
	# not start Xvfb, because a shot of a display nobody ran the app on is worse than none.
	if [ -z "${DISPLAY:-}" ]; then
		echo "  [shot] no DISPLAY set, nothing to capture for '$label'"
		exit 0
	fi
	if command -v import >/dev/null 2>&1; then
		if import -display "$DISPLAY" -window root "$out" 2>/dev/null; then captured="import"; fi
	elif command -v xwd >/dev/null 2>&1 && command -v convert >/dev/null 2>&1; then
		if xwd -display "$DISPLAY" -root 2>/dev/null | convert xwd:- "$out" 2>/dev/null; then
			captured="xwd"
		fi
	else
		echo "  [shot] no import/xwd available, cannot capture '$label'"
		exit 0
	fi
fi

if [ -z "$captured" ] || [ ! -s "$out" ]; then
	# A zero-byte png is worse than no png: it looks like a capture happened. Remove it and
	# say so.
	rm -f "$out" 2>/dev/null
	echo "  [shot] capture FAILED for '$label' (tool ran, no image)"
	exit 0
fi

# SHOT_TRIM=1 crops the uniform border away. On a virtual display the app occupies a corner of
# a 1280x800 root window and the rest is dead black, which makes the thing you actually wanted
# to look at a small patch in the top-left. -trim crops to the content's bounding box;
# +repage discards the offset it would otherwise record, so the png is genuinely smaller
# rather than merely cropped on paper.
#
# Guarded: a trim that eats the whole image (uniform frame, nothing drawn yet) leaves a 1x1
# png, which is worse than the original. Keep the trimmed copy only if it still has substance.
if [ "${SHOT_TRIM:-0}" = "1" ] && command -v convert >/dev/null 2>&1; then
	if convert "$out" -bordercolor black -border 10 -trim +repage "$out.trim" 2>/dev/null; then
		tw=$(identify -format '%w' "$out.trim" 2>/dev/null || echo 0)
		th=$(identify -format '%h' "$out.trim" 2>/dev/null || echo 0)
		if [ "${tw:-0}" -ge 120 ] && [ "${th:-0}" -ge 60 ]; then
			mv "$out.trim" "$out"
		else
			echo "  [shot] trim produced ${tw}x${th}, keeping the untrimmed frame"
			rm -f "$out.trim"
		fi
	else
		rm -f "$out.trim" 2>/dev/null
	fi
fi

size=$(du -k "$out" 2>/dev/null | cut -f1)
dims=""
if command -v identify >/dev/null 2>&1; then
	dims=$(identify -format '%wx%h' "$out" 2>/dev/null)
elif [ "$(uname -s)" = "Darwin" ]; then
	dims=$(sips -g pixelWidth -g pixelHeight "$out" 2>/dev/null \
		| awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{if (w) print w "x" h}')
fi

echo "  [shot] $(basename "$out")  ($captured${dims:+, $dims}, ${size:-?} KB)"
printf '%s\t%s\t%s\n' "$(basename "$out")" "$label" "${dims:-unknown}" >> "$SHOT_DIR/INDEX.txt"
exit 0
