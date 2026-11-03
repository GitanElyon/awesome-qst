#!/usr/bin/env bash
set -euo pipefail
echo "qst! meta Run Command, 1.1.0, GitanElyon, Run an arbitrary shell command."

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]:-$0}")"
RUNNER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/qst/storage/runner"
HISTORY_FILE="${RUNNER_DIR}/history"
MAX_HISTORY=100

sanitize_text() {
	local text="$1"
	text="${text//$'\n'/ }"
	text="${text//$'\t'/ }"
	text="${text//|/¦}"
	printf '%s' "$text"
}

encode_command() {
	printf '%s' "$1" | base64 -w0
}

decode_command() {
	printf '%s' "$1" | base64 -d 2>/dev/null || true
}

record_history() {
	local encoded="$1"
	local tmp
	mkdir -p "$RUNNER_DIR"
	tmp="$(mktemp "${RUNNER_DIR}/.history.XXXXXX")"

	{
		printf '%s\n' "$encoded"
		if [[ -f "$HISTORY_FILE" ]]; then
			grep -Fxv -- "$encoded" "$HISTORY_FILE" || true
		fi
	} | head -n "$MAX_HISTORY" > "$tmp" || true

	mv "$tmp" "$HISTORY_FILE"
}

run_action_encoded() {
	printf '%q _run %s' "$SCRIPT_PATH" "$1"
}

run_action() {
	run_action_encoded "$(encode_command "$1")"
}

history_label() {
	local command
	command="$(sanitize_text "$1")"
	if (( ${#command} > 120 )); then
		command="${command:0:119}…"
	fi
	printf '%s' "$command"
}

# Hidden one-shot mode used by the Execute action: record the command, then run it.
if [[ "${1:-}" == "_run" ]]; then
	encoded="${2:-}"
	command="$(decode_command "$encoded")"
	if [[ -n "$command" ]]; then
		record_history "$encoded" || true
		exec sh -lc "$command"
	fi
	exit 0
fi

QUERY="$*"
query_lower="${QUERY,,}"

history_commands=()
history_encoded=()

if [[ -f "$HISTORY_FILE" ]]; then
	while IFS= read -r encoded; do
		[[ -z "$encoded" ]] && continue
		command="$(decode_command "$encoded")"
		[[ -z "$command" ]] && continue
		history_commands+=("$command")
		history_encoded+=("$encoded")
	done < "$HISTORY_FILE"
fi

echo "qst! title Run Command "

if [[ -z "$QUERY" ]]; then
	if (( ${#history_commands[@]} == 0 )); then
		echo "qst! action None"
		echo "  Type a command to run…|"
		exit 0
	fi

	echo "qst! action Execute,ExitApp"

	for i in "${!history_commands[@]}"; do
		echo "qst! item  $(history_label "${history_commands[$i]}")|$(run_action_encoded "${history_encoded[$i]}")|Execute,ExitApp"
	done
	exit 0
fi

echo "qst! action Execute,ExitApp"
echo "qst! item  ▶  Run: $(sanitize_text "$QUERY")|$(run_action "$QUERY")|Execute,ExitApp"

for i in "${!history_commands[@]}"; do
	command="${history_commands[$i]}"
	if [[ "${command,,}" != *"$query_lower"* ]]; then
		continue
	fi
	echo "qst! item  $(history_label "$command")|$(run_action_encoded "${history_encoded[$i]}")|Execute,ExitApp"
done
