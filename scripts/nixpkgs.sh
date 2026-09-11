#!/usr/bin/env bash
echo "qst! meta Nixpkgs, 1.0.0, GitanElyon, Searches nixpkgs with search.nixos.org typeahead."
set -euo pipefail

ES_HOST="https://nixos-search-7-1733963800.us-east-1.bonsaisearch.net"
ES_USER="aWVSALXpZv"
ES_PASS="X8gPHnzL52wFEekuxsfQ9cSh"
SCHEMA_VERSION="51"
BRANCH="nixos-unstable"
CHANNEL="unstable"
MAX_RESULTS=16
CURL_TIMEOUT=4

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

json_escape() {
	local text="$1"
	text="${text//\\/\\\\}"
	text="${text//\"/\\\"}"
	text="${text//$'\n'/ }"
	text="${text//$'\t'/ }"
	printf '%s' "$text"
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

strip_html() {
	printf '%s' "$1" | sed -e 's/<[^>]*>/ /g' -e 's/  */ /g'
}

echo "qst! title  Nixpkgs (${CHANNEL}) "

QUERY="$(trim "$RAW_QUERY")"

if ! command -v curl >/dev/null 2>&1; then
	echo "qst! action None"
	echo "  Error: curl is required for nixpkgs search| @meta:nonselectable=true"
	exit 0
fi

if [[ -z "$QUERY" ]]; then
	echo "qst! action None"
	echo "  Type 2+ characters to search nixpkgs…| @meta:nonselectable=true"
	exit 0
fi

if [[ "${#QUERY}" -lt 2 ]]; then
	echo "qst! action None"
	echo "  Keep typing… suggestions start at 2 characters| @meta:nonselectable=true"
	exit 0
fi

ESCAPED_QUERY="$(json_escape "$QUERY")"
REQUEST_BODY="$(printf '{"from":0,"size":%s,"_source":["type","package_attr_name","package_pname","package_description"],"query":{"bool":{"filter":[{"term":{"type":"package"}}],"must":[{"multi_match":{"query":"%s","type":"best_fields","operator":"and","fields":["package_attr_name.edge^4","package_pname.edge^3","package_description.edge^0.5"]}}]}}}' "$MAX_RESULTS" "$ESCAPED_QUERY")"

RESPONSE="$(curl -sf --max-time "$CURL_TIMEOUT" -u "${ES_USER}:${ES_PASS}" -H 'Content-Type: application/json' -d "$REQUEST_BODY" "${ES_HOST}/latest-${SCHEMA_VERSION}-${BRANCH}/_search" 2>/dev/null)" || RESPONSE=""

if [[ -z "$RESPONSE" ]]; then
	echo "qst! action None"
	echo "  No network access or backend unreachable| @meta:nonselectable=true"
	exit 0
fi

HITS="$(printf '%s' "$RESPONSE" | tr '\n' ' ' | awk '
		BEGIN { RS = "\"_source\"[ ]*:[ ]*\\{"; n = 0 }
		NR > 1 {
			rec = $0
			if (match(rec, /"package_attr_name"[ ]*:[ ]*"[^"]*"/)) {
				attr = substr(rec, RSTART, RLENGTH)
				sub(/.*"package_attr_name"[ ]*:[ ]*"/, "", attr)
				sub(/"$/, "", attr)
			} else { next }
			pname = ""
			if (match(rec, /"package_pname"[ ]*:[ ]*"[^"]*"/)) {
				pname = substr(rec, RSTART, RLENGTH)
				sub(/.*"package_pname"[ ]*:[ ]*"/, "", pname)
				sub(/"$/, "", pname)
			}
			desc = ""
			if (match(rec, /"package_description"[ ]*:[ ]*"[^"]*"/)) {
				desc = substr(rec, RSTART, RLENGTH)
				sub(/.*"package_description"[ ]*:[ ]*"/, "", desc)
				sub(/"$/, "", desc)
			}
			gsub(/\t/, " ", attr); gsub(/\t/, " ", pname); gsub(/\t/, " ", desc)
			print attr "\t" pname "\t" desc
			n++
			if (n >= 8) exit
		}
	')" || HITS=""

if [[ -z "$HITS" ]]; then
	echo "qst! action None"
	echo "  No packages found for: $(sanitize_text "$QUERY")| @meta:nonselectable=true"
	exit 0
fi

echo "qst! action CopyToClipboard,ExitApp"

while IFS=$'\t' read -r attr pname desc; do
	[[ -z "$attr" ]] && continue
	attr="$(trim "$attr")"
	pname="$(trim "$pname")"
	desc="$(json_unescape "$desc")"
	desc="$(strip_html "$desc")"
	desc="$(trim "$desc")"
	if [[ "${#desc}" -gt 80 ]]; then
		desc="${desc:0:80}…"
	fi

	title="$attr"
	if [[ -n "$pname" && "$pname" != "$attr" ]]; then
		title="${title} · ${pname}"
	fi
	if [[ -n "$desc" ]]; then
		title="${title} — ${desc}"
	fi

	title="$(sanitize_text "$title")"
	value="nixpkgs#${attr}"
	meta_terms="$attr"
	if [[ -n "$pname" && "$pname" != "$attr" ]]; then
		meta_terms="${meta_terms},${pname}"
	fi
	echo "qst! item  ${title}|${value} @meta:meta=${meta_terms}"
done <<< "$HITS"
