#!/usr/bin/env bash
echo "qst! meta Todo, 1.0.2, GitanElyon, Manages a simple todo list."
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
TODO_DIR="${HOME}/.config/qst/storage/todo"
TODO_FILE="${TODO_DIR}/items.tsv"
LOCK_FILE="${TODO_DIR}/.lock"

now_stamp() {
	date -u +"%Y-%m-%d %H:%M:%S UTC"
}

ensure_store() {
	mkdir -p "$TODO_DIR"
}

sanitize_text() {
	local value="$1"
	value="${value//$'\n'/ }"
	value="${value//|/¦}"
	printf '%s' "$value"
}

b64_encode() {
	printf '%s' "$1" | base64 -w 0
}

b64_decode() {
	printf '%s' "$1" | base64 -d 2>/dev/null || true
}

quote_shell_args() {
	local arg command=""
	for arg in "$@"; do
		command+="$(printf '%q ' "$arg")"
	done
	printf '%s' "${command% }"
}

trim_leading_space() {
	local value="$1"
	while [[ "$value" == " "* ]]; do
		value="${value# }"
	done
	printf '%s' "$value"
}

read_records() {
	if [[ ! -f "$TODO_FILE" ]]; then
		return 0
	fi

	while IFS=$'\t' read -r id status urgent created updated encoded; do
		[[ -z "${id:-}" ]] && continue
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$id" "$status" "$urgent" "$created" "$updated" "$(b64_decode "$encoded")"
	done < "$TODO_FILE"
}

count_records() {
	if [[ ! -f "$TODO_FILE" ]]; then
		printf '0'
		return 0
	fi
	awk 'NF { count++ } END { print count + 0 }' "$TODO_FILE"
}

record_exists() {
	local target_id="$1"
	local id status urgent created updated text
	while IFS=$'\t' read -r id status urgent created updated text; do
		[[ -z "${id:-}" ]] && continue
		if [[ "$id" == "$target_id" ]]; then
			return 0
		fi
	done < <(read_records)
	return 1
}

get_record() {
	local target_id="$1"
	local id status urgent created updated text
	while IFS=$'\t' read -r id status urgent created updated text; do
		[[ -z "${id:-}" ]] && continue
		if [[ "$id" == "$target_id" ]]; then
			printf '%s\t%s\t%s\t%s\t%s\t%s' "$id" "$status" "$urgent" "$created" "$updated" "$text"
			return 0
		fi
	done < <(read_records)
	return 1
}

fuzzy_score() {
	local query="${1,,}"
	local target="${2,,}"
	local qlen=${#query}
	local tlen=${#target}
	local score=0
	local pattern_idx=0
	local prev_match_idx=-100
	local i t_char q_char prev_char char_score

	if (( qlen == 0 )); then
		printf '0'
		return 0
	fi

	for ((i=0; i<tlen; i++)); do
		t_char="${target:i:1}"
		q_char="${query:pattern_idx:1}"
		if [[ "$t_char" == "$q_char" ]]; then
			char_score=10
			if (( i == prev_match_idx + 1 )); then
				char_score=$((char_score + 40))
			fi
			prev_char="${target:i-1:1}"
			if (( i == 0 )) || [[ "$prev_char" == " " || "$prev_char" == "_" || "$prev_char" == "-" || "$prev_char" == "." || "$prev_char" == "/" ]]; then
				char_score=$((char_score + 20))
			fi
			[[ "$t_char" =~ [A-Z] ]] && char_score=$((char_score + 10))
			score=$((score + char_score))
			prev_match_idx=$i
			pattern_idx=$((pattern_idx + 1))
			(( pattern_idx == qlen )) && break
		fi
	done

	if (( pattern_idx == qlen )); then
		printf '%s' $((score - tlen + qlen))
		return 0
	fi

	return 1
}

render_help() {
	echo "qst! title  Todo Help "
	echo "qst! action None"
	echo "qst! item  todo               browse items and check them off|todo|None @meta:nonselectable=true"
	echo "qst! item  todo a <item>      add a new item|todo a <item>|None @meta:nonselectable=true"
	echo "qst! item  todo c <item>      fuzzy find and check the top result|todo c <item>|None @meta:nonselectable=true"
	echo "qst! item  todo r <item>      fuzzy find and remove the top result|todo r <item>|None @meta:nonselectable=true"
	echo "qst! item  todo C             clear the list|todo C|None @meta:nonselectable=true"
	echo "qst! item  todo u <item>      fuzzy find and mark urgent|todo u <item>|None @meta:nonselectable=true"
	echo "qst! item  todo e <item>      fuzzy find and edit an item|todo e <item>|None @meta:nonselectable=true"
	echo "qst! item  todo v <item>      show verbose info for an item|todo v <item>|None @meta:nonselectable=true"
	echo "qst! item  todo s <item>      fuzzy search for a specific item|todo s <item>|None @meta:nonselectable=true"
	echo "qst! item  todo h             show this help|todo h|None @meta:nonselectable=true"
}

with_lock() {
	exec 9>"$LOCK_FILE"
	flock 9
	"$@"
}

add_item() {
	local text="$1"
	[[ -z "$text" ]] && return 0

	local id created encoded
	id="$(date +%s%N)"
	created="$(now_stamp)"
	encoded="$(b64_encode "$text")"
	printf '%s\topen\t0\t%s\t%s\t%s\n' "$id" "$created" "$created" "$encoded" >> "$TODO_FILE"
}

clear_items() {
	: > "$TODO_FILE"
}

update_item() {
	local action="$1"
	local target_id="$2"
	local replacement_text="${3:-}"
	local tmp_file
	tmp_file="$(mktemp "${TODO_DIR}/.items.XXXXXX")"
	: > "$tmp_file"

	local found=0
	local id status urgent created updated text encoded
	while IFS=$'\t' read -r id status urgent created updated encoded; do
		[[ -z "${id:-}" ]] && continue
		text="$(b64_decode "$encoded")"
		if [[ "$id" == "$target_id" ]]; then
			found=1
			case "$action" in
				check)
					if [[ "$status" == "done" ]]; then
						status="open"
					else
						status="done"
					fi
					updated="$(now_stamp)"
					;;
				urgent)
					urgent="1"
					updated="$(now_stamp)"
					;;
				remove)
					continue
					;;
				edit)
					text="$replacement_text"
					encoded="$(b64_encode "$text")"
					updated="$(now_stamp)"
					;;
			esac
		fi
		printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$status" "$urgent" "$created" "$updated" "$encoded" >> "$tmp_file"
	done < "$TODO_FILE"

	mv "$tmp_file" "$TODO_FILE"
	return 0
}

item_label() {
	local status="$1"
	local urgent="$2"
	local text="$3"
	local prefix="[ ]"
	[[ "$status" == "done" ]] && prefix="[x]"
	if [[ "$urgent" == "1" ]]; then
		printf '%s ! %s' "$prefix" "$text"
	else
		printf '%s %s' "$prefix" "$text"
	fi
}

# ResetPrompt alone can reuse qst's cached script frame, so the checked/updated
# state would not appear until something else triggered a rerun. RefreshResults
# after it forces a fresh run once the Execute command has finished writing.
emit_item() {
	local title="$1"
	local value="$2"
	local action="${3:-Execute,ResetPrompt,RefreshResults}"
	local meta="${4:-}"
	title="$(sanitize_text "$title")"
	if [[ -n "$meta" ]]; then
		echo "qst! item ${title}|${value}|${action} ${meta}"
	else
		echo "qst! item ${title}|${value}|${action}"
	fi
}

emit_preview_item() {
	local title="$1"
	local value="$2"
	local action="${3:-Execute,ResetPrompt,RefreshResults}"
	emit_item "$title" "$value" "$action"
}

emit_all_items_browse() {
	echo "qst! title  Todo @meta:fuzzy=true"
	echo "qst! action Execute,ResetPrompt,RefreshResults"
	while IFS=$'\t' read -r id status urgent created updated text; do
		[[ -z "${id:-}" ]] && continue
		emit_item "$(item_label "$status" "$urgent" "$text")" "$(quote_shell_args "$SCRIPT_PATH" _apply check "$id")" "Execute,ResetPrompt,RefreshResults"
	done < <(read_records)
}

emit_help_if_empty() {
	if [[ $(count_records) -eq 0 ]]; then
		render_help
		return 0
	fi
	return 1
}

emit_fuzzy_matches() {
	local mode="$1"
	local query="$2"
	local title="Todo"
	local action="Execute,ResetPrompt,RefreshResults"
	case "$mode" in
		c) title="Todo Check" ;;
		r) title="Todo Remove" ;;
		u) title="Todo Urgent" ;;
		s) title="Todo Search" ;;
		v) title="Todo Verbose" ; action="None" ;;
		e) title="Todo Edit" ; action="SetSearchQuery" ;;
	esac

	echo "qst! title  ${title} "
	echo "qst! action ${action}"

	local matches=()
	local id status urgent created updated text score display payload
	while IFS=$'\t' read -r id status urgent created updated text; do
		[[ -z "${id:-}" ]] && continue
		score="$(fuzzy_score "$query" "$(item_label "$status" "$urgent" "$text")")" || continue
		matches+=("$((1000000000 - score))|$id|$status|$urgent|$created|$updated|$text")
	done < <(read_records)

	if [[ ${#matches[@]} -eq 0 ]]; then
		echo "qst! action None"
		echo "  No matching todo items found|"
		return 0
	fi

	mapfile -t matches < <(printf '%s\n' "${matches[@]}" | sort -n -k1,1)
	for payload in "${matches[@]}"; do
		IFS='|' read -r _score id status urgent created updated text <<< "$payload"
		display="$(item_label "$status" "$urgent" "$text")"
		case "$mode" in
			c)
				emit_item "$display" "$(quote_shell_args "$SCRIPT_PATH" _apply check "$id")" "Execute,ResetPrompt,RefreshResults"
				;;
			r)
				emit_item "$display" "$(quote_shell_args "$SCRIPT_PATH" _apply remove "$id")" "Execute,ResetPrompt,RefreshResults"
				;;
			u)
				emit_item "$display" "$(quote_shell_args "$SCRIPT_PATH" _apply urgent "$id")" "Execute,ResetPrompt,RefreshResults"
				;;
			s)
				emit_item "$display" "$(quote_shell_args "$SCRIPT_PATH" _apply check "$id")" "None"
				;;
			v)
				display="${display} | created: ${created} | updated: ${updated}"
				emit_item "$display" "$(quote_shell_args "$SCRIPT_PATH" _apply check "$id")" "None"
				;;
			e)
				emit_item "$display" "todo e ${id} " "SetSearchQuery"
				;;
		esac
	done
}

emit_add_mode() {
	local item_text="$1"
	echo "qst! title  Todo Add "
	echo "qst! action Execute,ResetPrompt,RefreshResults"
	emit_preview_item "[ ] Add: $(sanitize_text "$item_text")" "$(quote_shell_args "$SCRIPT_PATH" _apply add "$(b64_encode "$item_text")")" "Execute,ResetPrompt,RefreshResults"
	while IFS=$'\t' read -r id status urgent created updated text; do
		[[ -z "${id:-}" ]] && continue
		emit_item "$(item_label "$status" "$urgent" "$text")" "$(quote_shell_args "$SCRIPT_PATH" _apply check "$id")" "Execute,ResetPrompt,RefreshResults"
	done < <(read_records)
}

emit_clear_mode() {
	echo "qst! title  Todo Clear "
	echo "qst! action Execute,ResetPrompt,RefreshResults"
	emit_preview_item "[!] Clear all todo items" "$(quote_shell_args "$SCRIPT_PATH" _apply clear)" "Execute,ResetPrompt,RefreshResults"
	while IFS=$'\t' read -r id status urgent created updated text; do
		[[ -z "${id:-}" ]] && continue
		emit_item "$(item_label "$status" "$urgent" "$text")" "$(quote_shell_args "$SCRIPT_PATH" _apply check "$id")" "Execute,ResetPrompt,RefreshResults"
	done < <(read_records)
}

emit_edit_prefill() {
	local target_id="$1"
	local record id status urgent created updated text
	record="$(get_record "$target_id" || true)"
	if [[ -z "$record" ]]; then
		render_help
		return 0
	fi
	IFS=$'\t' read -r id status urgent created updated text <<< "$record"
	echo "qst! title  Todo Edit "
	echo "qst! action None"
	echo "  Editing: ${text}|"
	echo "  Type a replacement after the id, then press Enter to save|"
	echo "  Current state: $(item_label "$status" "$urgent" "$text") | created: ${created} | updated: ${updated}|"
}

emit_edit_save() {
	local target_id="$1"
	local new_text="$2"
	local record id status urgent created updated old_text
	record="$(get_record "$target_id" || true)"
	if [[ -z "$record" ]]; then
		render_help
		return 0
	fi
	IFS=$'\t' read -r id status urgent created updated old_text <<< "$record"
	echo "qst! title  Todo Edit "
	echo "qst! action Execute,ResetPrompt,RefreshResults"
	echo "qst! item  Save: $(sanitize_text "$old_text") -> $(sanitize_text "$new_text")|$(quote_shell_args "$SCRIPT_PATH" _apply edit "$target_id" "$(b64_encode "$new_text")")|Execute,ResetPrompt,RefreshResults"
	echo "  Current state: $(item_label "$status" "$urgent" "$old_text") | created: ${created} | updated: ${updated}|"
}

handle_query() {
	local raw_query="${1:-}"
	local mode="browse"
	local payload="$raw_query"
	local head=""

	if [[ -z "$raw_query" ]]; then
		mode="browse"
		payload=""
	elif [[ "$raw_query" == *" "* ]]; then
		head="${raw_query%% *}"
		payload="${raw_query#* }"
		case "$head" in
			a|c|r|C|u|e|v|s|h)
				mode="$head"
				payload="$(trim_leading_space "$payload")"
				;;
			*)
				mode="browse"
				payload="$raw_query"
				;;
		esac
	else
		case "$raw_query" in
			a|c|r|C|u|e|v|s|h)
				mode="$raw_query"
				payload=""
				;;
			*)
				mode="browse"
				payload="$raw_query"
				;;
		esac
	fi

	case "$mode" in
		h)
			render_help
			;;
		C)
			if emit_help_if_empty; then
				return 0
			fi
			emit_clear_mode
			;;
		a)
			if [[ -z "$payload" ]]; then
				if emit_help_if_empty; then
					return 0
				fi
				emit_all_items_browse
			else
				emit_add_mode "$payload"
			fi
			;;
		c|r|u|s|v)
			if emit_help_if_empty; then
				return 0
			fi
			emit_fuzzy_matches "$mode" "$payload"
			;;
		e)
			if [[ -z "$payload" ]]; then
				if emit_help_if_empty; then
					return 0
				fi
				emit_all_items_browse
			elif [[ "$payload" == *" "* ]]; then
				local edit_id edit_text
				edit_id="${payload%% *}"
				edit_text="$(trim_leading_space "${payload#* }")"
				if record_exists "$edit_id" && [[ -n "$edit_text" ]]; then
					emit_edit_save "$edit_id" "$edit_text"
				elif record_exists "$edit_id"; then
					emit_edit_prefill "$edit_id"
				else
					emit_fuzzy_matches "e" "$payload"
				fi
			elif record_exists "$payload"; then
				emit_edit_prefill "$payload"
			else
				emit_fuzzy_matches "e" "$payload"
			fi
			;;
		browse)
			if emit_help_if_empty; then
				return 0
			fi
			emit_all_items_browse
			;;
		*)
			if emit_help_if_empty; then
				return 0
		fi
			emit_all_items_browse
			;;
	esac
}

if [[ "${1:-}" == "_apply" ]]; then
	shift
	action="${1:-}"
	arg1="${2:-}"
	arg2="${3:-}"
	ensure_store
	case "$action" in
		add)
			with_lock add_item "$(b64_decode "$arg1")"
			;;
		check|urgent|remove)
			with_lock update_item "$action" "$arg1"
			;;
		clear)
			with_lock clear_items
			;;
		edit)
			with_lock update_item edit "$arg1" "$(b64_decode "$arg2")"
			;;
		*)
			exit 1
			;;
	esac
	exit 0
fi

ensure_store
handle_query "${1:-}"
