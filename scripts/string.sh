#!/usr/bin/env bash
echo "qst! meta String Analyzer, 1.0.0, GitanElyon, Analyzes pasted text: characters, words, sentences, and more."
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
	echo "qst! title  String Analyzer Help "
	echo "qst! action None"
	echo "  string <text>   analyze pasted string| @meta:nonselectable=true"
	echo "  string h        show this help| @meta:nonselectable=true"
}

QUERY="$(trim "$RAW_QUERY")"

case "$QUERY" in
	h|help)
		render_help
		exit 0
		;;
esac

if [[ -z "$QUERY" ]]; then
	echo "qst! title  String Analyzer "
	echo "qst! action None"
	echo "  Paste a string to analyze…| @meta:nonselectable=true"
	exit 0
fi

STATS="$(printf '%s\n' "$QUERY" | awk '
	{ text = text (NR > 1 ? " " : "") $0 }
	END {
		chars = length(text)

		nospace = text
		gsub(/[[:space:]]/, "", nospace)
		chars_ns = length(nospace)

		n = split(text, parts, /[[:space:]]+/)
		nwords = 0
		for (i = 1; i <= n; i++) {
			w = parts[i]
			gsub(/^[.,;:!?"'"'"'()\[\]{}<>-]+/, "", w)
			gsub(/[.,;:!?"'"'"'()\[\]{}<>-]+$/, "", w)
			if (w == "") continue
			nwords++
			word[nwords] = w
		}

		if (nwords == 0) exit 0

		total_len = 0
		unique_count = 0
		longest = ""
		longest_len = 0
		for (i = 1; i <= nwords; i++) {
			wl = length(word[i])
			total_len += wl
			key = tolower(word[i])
			if (!(key in seen)) {
				seen[key] = 1
				unique_count++
			}
			if (wl > longest_len) {
				longest_len = wl
				longest = word[i]
			}
		}
		avg_word = total_len / nwords

		sent = text
		nsent = gsub(/[.!?]+([[:space:]]|$)/, "", sent)
		if (nsent == 0) nsent = 1
		avg_sent = nwords / nsent

		secs = int((nwords * 60 + 199) / 200)
		if (secs < 60) read_time = secs "s"
		else read_time = int(secs / 60) "m " (secs % 60) "s"

		printf "Characters\t%d\n", chars
		printf "Characters (no spaces)\t%d\n", chars_ns
		printf "Words\t%d\n", nwords
		printf "Unique words\t%d\n", unique_count
		printf "Sentences\t%d\n", nsent
		printf "Average word length\t%.1f\n", avg_word
		printf "Average sentence length\t%.1f words\n", avg_sent
		printf "Longest word\t%s (%d)\n", longest, longest_len
		printf "Reading time\t%s\n", read_time
	}
')" || STATS=""

echo "qst! title  String Analyzer "
echo "qst! action None"

if [[ -z "$STATS" ]]; then
	echo "  No words found.| @meta:nonselectable=true"
	exit 0
fi

while IFS=$'\t' read -r label value; do
	[[ -z "$label" ]] && continue
	label="$(sanitize_text "$label")"
	value="$(sanitize_text "$value")"
	printf 'qst! item  %-24s%s|%s: %s|None @meta:nonselectable=true\n' "$label" "$value" "$label" "$value"
done <<< "$STATS"
