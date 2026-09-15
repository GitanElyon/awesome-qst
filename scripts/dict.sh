#!/usr/bin/env bash
echo "qst! meta Dictionary, 1.2.0, GitanElyon, Defines English words instantly, with local cache."
set -euo pipefail

API_BASE="https://en.wiktionary.org/api/rest_v1/page/definition"
CURL_TIMEOUT=3
MAX_ROWS=12
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/qst/dict"

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

urlencode() {
	local input="$1"
	local encoded=""
	local char
	local LC_ALL=C

	for ((index = 0; index < ${#input}; index++)); do
		char="${input:index:1}"
		case "$char" in
			[a-zA-Z0-9.~_-])
				encoded+="$char"
				;;
			' ')
				encoded+='%20'
				;;
			*)
				printf -v char '%%%02X' "'${char}"
				encoded+="$char"
				;;
		esac
	done

	printf '%s' "$encoded"
}

json_unescape() {
	local text="$1"
	text="${text//\\\"/\"}"
	text="${text//\\\//\/}"
	text="${text//\\n/ }"
	text="${text//\\t/ }"
	text="${text//\\\\/\\}"
	printf '%s' "$text"
}

decode_entities() {
	printf '%s' "$1" | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&#39;/'/g" -e 's/&nbsp;/ /g' -e 's/&amp;/\&/g'
}

strip_html() {
	printf '%s' "$1" | sed -e 's/<[^>]*>/ /g' -e 's/  */ /g' -e 's/ \([.,;:!?…)]\)/\1/g' -e 's/( */(/g'
}

fetch_with_code() {
	curl -s --max-time "$CURL_TIMEOUT" -w '\n%{http_code}' "$1" 2>/dev/null || printf '\n000'
}

# Wiktionary answers every language under one object ("en", "fr", ...).
# Slice out just the "en" array with string-aware bracket matching so
# non-English definitions never leak into the rows.
extract_english() {
	printf '%s' "$1" | tr -d '\n' | awk '
	{
		s = $0
		n = length(s)
		in_str = 0; esc = 0; brace = 0; i = 1
		start = 0
		while (i <= n) {
			c = substr(s, i, 1)
			if (in_str) {
				if (esc) esc = 0
				else if (c == "\\") esc = 1
				else if (c == "\"") in_str = 0
			} else {
				if (c == "\"") {
					if (brace == 1 && substr(s, i, 4) == "\"en\"") {
						j = i + 4
						while (j <= n && substr(s, j, 1) ~ /[ \t]/) j++
						if (substr(s, j, 1) == ":") {
							j++
							while (j <= n && substr(s, j, 1) ~ /[ \t]/) j++
							if (substr(s, j, 1) == "[") { start = j; break }
						}
					}
					in_str = 1
				}
				else if (c == "{") brace++
				else if (c == "}") brace--
			}
			i++
		}
		if (start == 0) exit 1
		depth = 0; i = start; in_str = 0; esc = 0
		while (i <= n) {
			c = substr(s, i, 1)
			if (in_str) {
				if (esc) esc = 0
				else if (c == "\\") esc = 1
				else if (c == "\"") in_str = 0
			} else {
				if (c == "\"") in_str = 1
				else if (c == "[") depth++
				else if (c == "]") {
					depth--
					if (depth == 0) { print substr(s, start, i - start + 1); exit 0 }
				}
			}
			i++
		}
		exit 1
	}'
}

QUERY="$(trim "$RAW_QUERY")"

if ! command -v curl >/dev/null 2>&1; then
	echo "qst! title  Dictionary "
	echo "qst! action None"
	echo "  Error: curl is required for dictionary lookup| @meta:nonselectable=true"
	exit 0
fi

if [[ -z "$QUERY" ]]; then
	echo "qst! title  Dictionary "
	echo "qst! action None"
	echo "  Type a word: dict hello| @meta:nonselectable=true"
	exit 0
fi

WORD="${QUERY%% *}"
WORD="${WORD,,}"
REST=""
if [[ "$QUERY" == *" "* ]]; then
	REST="$(trim "${QUERY#* }")"
fi

CACHE_KEY=""
if [[ "$WORD" =~ ^[a-z0-9-]+$ ]]; then
	CACHE_KEY="$WORD"
fi

RESPONSE=""
HTTP_CODE=""

if [[ -n "$CACHE_KEY" ]]; then
	if [[ -f "${CACHE_DIR}/${CACHE_KEY}.missing" ]]; then
		echo "qst! title  Dictionary "
		echo "qst! action None"
		echo "  No definitions found for: $(sanitize_text "$WORD")| @meta:nonselectable=true"
		exit 0
	elif [[ -s "${CACHE_DIR}/${CACHE_KEY}.json" ]]; then
		RESPONSE="$(cat "${CACHE_DIR}/${CACHE_KEY}.json")"
		HTTP_CODE="200"
	fi
fi

if [[ -z "$HTTP_CODE" ]]; then
	FETCH="$(fetch_with_code "${API_BASE}/$(urlencode "$WORD")")"
	HTTP_CODE="$(printf '%s' "$FETCH" | tail -n1)"
	BODY="$(printf '%s' "$FETCH" | sed '$d')"

	if [[ -z "$HTTP_CODE" || "$HTTP_CODE" == "000" ]]; then
		echo "qst! title  Dictionary "
		echo "qst! action None"
		echo "  No network access or backend unreachable| @meta:nonselectable=true"
		exit 0
	fi

	if [[ "$HTTP_CODE" == "404" ]]; then
		if [[ -n "$CACHE_KEY" ]]; then
			mkdir -p "$CACHE_DIR"
			: > "${CACHE_DIR}/${CACHE_KEY}.missing"
		fi
		echo "qst! title  Dictionary "
		echo "qst! action None"
		echo "  No definitions found for: $(sanitize_text "$WORD")| @meta:nonselectable=true"
		exit 0
	fi

	if [[ "$HTTP_CODE" != "200" || -z "$BODY" ]]; then
		echo "qst! title  Dictionary "
		echo "qst! action None"
		echo "  Lookup failed (HTTP ${HTTP_CODE})| @meta:nonselectable=true"
		exit 0
	fi

	RESPONSE="$(extract_english "$BODY")" || RESPONSE=""
fi

# Split on "partOfSpeech" so definitions stay associated with their POS.
# Each record is one meaning: POS name first, then its definitions in order.
PARSED="$(printf '%s' "$RESPONSE" | tr -d '\n' | awk -v max="$MAX_ROWS" '
	BEGIN { RS = "\"partOfSpeech\"[ ]*:[ ]*\""; n = 0 }
	NR == 1 { next }
	{
		pos = $0
		sub(/".*/, "", pos)
		rest = $0
		sub(/^[^"]*"/, "", rest)
		count = 0
		while (match(rest, /"definition"[ ]*:[ ]*"((\\.|[^"\\])*)"/)) {
			def = substr(rest, RSTART, RLENGTH)
			sub(/.*"definition"[ ]*:[ ]*"/, "", def)
			sub(/"$/, "", def)
			gsub(/\t/, " ", def)
			print pos "\t" def
			n++
			if (n >= max) exit
			rest = substr(rest, RSTART + RLENGTH)
			count++
			if (count > 20) break
		}
	}
')" || PARSED=""

ROWS="$PARSED"

if [[ -z "$ROWS" ]]; then
	echo "qst! title  Dictionary "
	echo "qst! action None"
	echo "  No definitions found for: $(sanitize_text "$WORD")| @meta:nonselectable=true"
	exit 0
fi

if [[ -n "$CACHE_KEY" && ! -s "${CACHE_DIR}/${CACHE_KEY}.json" ]]; then
	mkdir -p "$CACHE_DIR"
	printf '%s' "$RESPONSE" > "${CACHE_DIR}/${CACHE_KEY}.json"
fi

echo "qst! title  $(sanitize_text "$WORD") "
echo "qst! action CopyToClipboard,ExitApp"

if [[ -n "$REST" ]]; then
	echo "  Looking up first word only: $(sanitize_text "$WORD")| @meta:nonselectable=true"
fi

while IFS=$'\t' read -r pos def; do
	[[ -z "$def" ]] && continue
	pos="$(trim "${pos,,}")"
	def="$(json_unescape "$def")"
	def="$(decode_entities "$def")"
	def="$(strip_html "$def")"
	def="$(trim "$def")"
	[[ -z "$def" ]] && continue

	title="$def"
	if [[ -n "$pos" ]]; then
		title="${pos} — ${def}"
	fi
	title="$(sanitize_text "$title")"
	value="$(sanitize_text "$def")"
	echo "qst! item  ${title}|${value} @meta:meta=${WORD},${pos}"
done <<< "$ROWS"
