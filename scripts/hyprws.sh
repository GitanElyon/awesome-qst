#!/usr/bin/env bash
set -euo pipefail
echo "qst! meta Hypr Workspaces, 1.0.0, GitanElyon, Switch Hyprland workspaces."

RAW_QUERY="$*"

trim() {
	local value="$1"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "$value"
}

sanitize_text() {
	local value="$1"
	value="${value//$'\n'/ }"
	value="${value//|/¦}"
	printf '%s' "$value"
}

check_backend() {
	if ! command -v hyprctl >/dev/null 2>&1; then
		echo "qst! title  Hypr Workspaces "
		echo "qst! action None"
		echo "  hyprctl not found - install Hyprland or run this inside a Hyprland session @meta:nonselectable=true @meta:center=true|"
		return 1
	fi
	return 0
}

is_number() {
	[[ "$1" =~ ^[+-]?[0-9]+$ ]]
}

goto_cmd() {
	# Hyprland >= 0.55 uses Lua dispatchers: `dispatch` is shorthand
	# for `eval 'hl.dispatch(...)'`, so pass a dispatcher table.
	printf 'hyprctl dispatch %q' "hl.dsp.focus({ workspace = \"$1\" })"
}

ref_for() {
	local query="$1"
	if is_number "$query"; then
		printf '%s' "$query"
	else
		printf 'name:%s' "$query"
	fi
}

window_label() {
	local count="$1"
	if [[ "$count" == "1" ]]; then
		printf '1 window'
	else
		printf '%s windows' "$count"
	fi
}

WS_IDS=()
WS_NAMES=()
WS_MONITORS=()
WS_WINDOWS=()
ACTIVE_NAME=""

load_workspaces() {
	WS_IDS=()
	WS_NAMES=()
	WS_MONITORS=()
	WS_WINDOWS=()
	ACTIVE_NAME=""

	local lines=""
	if command -v jq >/dev/null 2>&1; then
		local json
		json="$(hyprctl workspaces -j 2>/dev/null || true)"
		[[ -n "$json" ]] || return 1
		lines="$(printf '%s' "$json" | jq -r '[.[] | select(.type=="normal")] | sort_by(.id)[] | "\(.id)\t\(.name)\t\(.monitor)\t\(.windows)"' 2>/dev/null || true)"
		ACTIVE_NAME="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true)"
	else
		local text
		text="$(hyprctl workspaces 2>/dev/null || true)"
		[[ -n "$text" ]] || return 1
		lines="$(printf '%s\n' "$text" | awk '
			/^workspace / {
				name=$2; id=$3; mon=$6
				gsub(/[()]/, "", id)
				gsub(/:$/, "", mon)
				if (name ~ /^special:/) { skip=1; next }
				skip=0
				next
			}
			skip { next }
			/^[[:space:]]*windows:/ { print id "\t" name "\t" mon "\t" $2 }
		' | sort -n -k1,1 || true)"
		ACTIVE_NAME="$(hyprctl activeworkspace 2>/dev/null | awk 'NR==1 { print $2 }' || true)"
	fi

	[[ -n "$lines" ]] || return 1

	local id name monitor windows
	while IFS=$'\t' read -r id name monitor windows; do
		[[ -z "${id:-}" || -z "${name:-}" ]] && continue
		WS_IDS+=("$id")
		WS_NAMES+=("$name")
		WS_MONITORS+=("$monitor")
		WS_WINDOWS+=("$windows")
	done <<< "$lines"

	(( ${#WS_IDS[@]} > 0 ))
}

CLIENT_LABELS=()

load_clients() {
	CLIENT_LABELS=()
	local target="$1"
	[[ "$target" =~ ^[0-9]+$ ]] || return 0

	local entries=""
	if command -v jq >/dev/null 2>&1; then
		local json
		json="$(hyprctl clients -j 2>/dev/null || true)"
		[[ -n "$json" ]] || return 0
		entries="$(printf '%s' "$json" | jq -r --argjson id "$target" '.[] | select(.workspace.id == $id) | "\(.class)\t\(.title)"' 2>/dev/null || true)"
	else
		local text
		text="$(hyprctl clients 2>/dev/null || true)"
		[[ -n "$text" ]] || return 0
		entries="$(printf '%s\n' "$text" | awk -v target="$target" '
			/^Window / { class=""; wsid=""; title=""; next }
			/^\tworkspace: / { line=$0; sub(/.*\(/, "", line); sub(/\).*/, "", line); wsid=line; next }
			/^\tclass: / { class=$0; sub(/^\tclass: /, "", class); next }
			/^\ttitle: / { title=$0; sub(/^\ttitle: /, "", title); if (wsid == target) print class "\t" title }
		' || true)"
	fi

	[[ -n "$entries" ]] || return 0

	local class title label
	while IFS=$'\t' read -r class title; do
		[[ -z "${class:-}${title:-}" ]] && continue
		if [[ -n "$title" && "$title" != "$class" ]]; then
			label="${class} — ${title}"
		else
			label="$class"
		fi
		label="$(sanitize_text "$label")"
		if (( ${#label} > 100 )); then
			label="${label:0:99}…"
		fi
		CLIENT_LABELS+=("$label")
	done <<< "$entries"
}

load_or_empty() {
	if ! check_backend; then
		return 1
	fi

	if ! load_workspaces; then
		echo "qst! title  Hypr Workspaces "
		echo "qst! action None"
		echo "  Could not list workspaces - are you running Hyprland? @meta:nonselectable=true @meta:center=true|"
		return 1
	fi

	return 0
}

render_browse() {
	load_or_empty || return 0

	echo "qst! title  Hypr Workspaces "
	echo "qst! action None"
	echo "  ${#WS_IDS[@]} workspaces · active $(sanitize_text "${ACTIVE_NAME:-?}") @meta:nonselectable=true @meta:center=true|"

	local i label ref
	for i in "${!WS_IDS[@]}"; do
		label="$(sanitize_text "${WS_NAMES[$i]} · ${WS_MONITORS[$i]} · $(window_label "${WS_WINDOWS[$i]}")")"
		ref="$(ref_for "${WS_NAMES[$i]}")"
		if [[ "${WS_NAMES[$i]}" == "$ACTIVE_NAME" ]]; then
			echo "qst! item  ${label} *|$(goto_cmd "$ref")|Execute,ExitApp @meta:fg=green"
		else
			echo "qst! item  ${label}|$(goto_cmd "$ref")|Execute,ExitApp"
		fi
	done

	echo "qst! item  ──────────────────────────────|──────────────────────────────|None @meta:nonselectable=true @meta:center=true"
	echo "qst! item  Next workspace|$(goto_cmd "+1")|Execute,ExitApp"
	echo "qst! item  Previous workspace|$(goto_cmd "-1")|Execute,ExitApp"
	echo "  Type a number to switch workspaces @meta:nonselectable=true @meta:center=true|"
	echo "  Type text to filter · n next · p previous @meta:nonselectable=true @meta:center=true|"
}

render_filter() {
	local filter="$1"
	local filter_lc="${filter,,}"

	load_or_empty || return 0

	echo "qst! title  Hypr Workspaces "
	echo "qst! action None"

	local -a matches=()
	local i haystack
	for i in "${!WS_IDS[@]}"; do
		haystack="${WS_IDS[$i]} ${WS_NAMES[$i]} ${WS_MONITORS[$i]}"
		if [[ "${haystack,,}" == *"$filter_lc"* ]]; then
			matches+=("$i")
		fi
	done

	if (( ${#matches[@]} == 0 )); then
		echo "  No workspaces match: $(sanitize_text "$filter") @meta:nonselectable=true @meta:center=true|"
		echo "qst! item  ← Clear filter|hyprws|SetSearchQuery @meta:permanent=true"
		return 0
	fi

	local label ref
	for i in "${matches[@]}"; do
		label="$(sanitize_text "${WS_NAMES[$i]} · ${WS_MONITORS[$i]} · $(window_label "${WS_WINDOWS[$i]}")")"
		ref="$(ref_for "${WS_NAMES[$i]}")"
		if [[ "${WS_NAMES[$i]}" == "$ACTIVE_NAME" ]]; then
			echo "qst! item  ${label} *|$(goto_cmd "$ref")|Execute,ExitApp @meta:fg=green"
		else
			echo "qst! item  ${label}|$(goto_cmd "$ref")|Execute,ExitApp"
		fi
	done
}

render_goto() {
	local ws="$1"
	local label
	label="$(sanitize_text "$ws")"

	load_or_empty || return 0
	load_clients "$ws" || true

	echo "qst! title  Hypr Workspaces - ${label} "
	echo "qst! action Execute,ExitApp"
	echo "qst! item  Go to workspace ${label}|$(goto_cmd "$ws")|Execute,ExitApp"

	if (( ${#CLIENT_LABELS[@]} > 0 )); then
		echo "  ${#CLIENT_LABELS[@]} window(s) on workspace ${label} @meta:nonselectable=true @meta:center=true|"
		local window_label_text
		for window_label_text in "${CLIENT_LABELS[@]}"; do
			echo "qst! item  ${window_label_text}|${window_label_text}|None @meta:nonselectable=true"
		done
	else
		echo "  No windows on workspace ${label} @meta:nonselectable=true @meta:center=true|"
	fi

	echo "qst! item  ← Back to workspaces|hyprws|SetSearchQuery @meta:permanent=true"
}

render_step() {
	local direction="$1"
	local label="$2"
	local ref="$3"

	echo "qst! title  Hypr Workspaces - ${label} "
	echo "qst! action Execute,ExitApp"
	echo "qst! item  Go to ${label,,} workspace|$(goto_cmd "$ref")|Execute,ExitApp"
	echo "qst! item  ← Back to workspaces|hyprws|SetSearchQuery @meta:permanent=true"
}

INPUT="$(trim "$RAW_QUERY")"
normalized="$INPUT"

if [[ -z "$normalized" ]]; then
	render_browse
	exit 0
fi

cmd="${normalized%% *}"

case "$cmd" in
	n|next)
		render_step "next" "Next" "+1"
		;;
	p|prev|previous)
		render_step "previous" "Previous" "-1"
		;;
	*)
		if is_number "$normalized"; then
			render_goto "$normalized"
		else
			render_filter "$normalized"
		fi
		;;
esac
