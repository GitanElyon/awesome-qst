#!/usr/bin/env bash
echo "qst! meta Color Picker, 1.0.0, GitanElyon, Previews hex colors as colored swatches."
set -euo pipefail

RAW_QUERY="$*"

trim() {
	local value="$1"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "$value"
}

sanitize_text() {
	local text="$1"
	text="${text//$'\n'/ }"
	text="${text//$'\t'/ }"
	text="${text//|/¦}"
	printf '%s' "$text"
}

render_help() {
	echo "qst! title  Color Picker Help "
	echo "qst! action None"
	echo "  color <hex>   preview a color, e.g. color #ff8800| @meta:nonselectable=true"
	echo "  color h       show this help| @meta:nonselectable=true"
}

QUERY="$(trim "$RAW_QUERY")"

case "$QUERY" in
	h|help)
		render_help
		exit 0
		;;
esac

if [[ -z "$QUERY" ]]; then
	echo "qst! title  Color Picker "
	echo "qst! action None"
	echo "  Type a hex color| @meta:nonselectable=true"
	exit 0
fi

HEX="${QUERY#\#}"
HEX="${HEX%% *}"

if [[ "$HEX" =~ ^[0-9a-fA-F]{3}$ ]]; then
	HEX="${HEX:0:1}${HEX:0:1}${HEX:1:1}${HEX:1:1}${HEX:2:1}${HEX:2:1}"
fi

if [[ ! "$HEX" =~ ^[0-9a-fA-F]{6}$ ]]; then
	echo "qst! title  Color Picker "
	echo "qst! action None"
	echo "  Invalid hex color: $(sanitize_text "$QUERY")| @meta:nonselectable=true"
	echo "  Use 3 or 6 hex digits, e.g. #f80 or #ff8800| @meta:nonselectable=true"
	exit 0
fi

HEX="${HEX,,}"
R="$((16#${HEX:0:2}))"
G="$((16#${HEX:2:2}))"
B="$((16#${HEX:4:2}))"

HSL="$(awk -v r="$R" -v g="$G" -v b="$B" 'BEGIN {
	r /= 255; g /= 255; b /= 255
	max = r; if (g > max) max = g; if (b > max) max = b
	min = r; if (g < min) min = g; if (b < min) min = b
	l = (max + min) / 2
	d = max - min
	h = 0; s = 0
	if (d > 0) {
		denom = 1 - (l > 0.5 ? 2 * l - 1 : 1 - 2 * l)
		if (denom > 0) s = d / denom
		if (max == r) h = (g - b) / d
		else if (max == g) h = (b - r) / d + 2
		else h = (r - g) / d + 4
		h *= 60
		if (h < 0) h += 360
	}
	printf "%.0f°, %.0f%%, %.0f%%", h, s * 100, l * 100
}')"

SWATCH_WIDTH=8
SWATCH_HEIGHT=4

GRID_CELLS=""
for ((i = 0; i < SWATCH_WIDTH; i++)); do
	GRID_CELLS+="█"
done

echo "qst! title  Color #${HEX} "
echo "qst! action CopyToClipboard,ExitApp"

for ((row = 0; row < SWATCH_HEIGHT; row++)); do
	printf 'qst! item  %s|#%s @meta:fg=#%s @meta:center=true @meta:nonselectable=true\n' \
		"$GRID_CELLS" "$HEX" "$HEX"
done

printf 'qst! item  #%s|#%s @meta:fg=#%s @meta:bold=true @meta:nonselectable=true\n' "$HEX" "$HEX" "$HEX"
echo "  RGB  ${R}, ${G}, ${B}| @meta:nonselectable=true"
echo "  HSL  ${HSL}| @meta:nonselectable=true"
echo "qst! item  Copy #${HEX}|#${HEX}|CopyToClipboard,ExitApp"
