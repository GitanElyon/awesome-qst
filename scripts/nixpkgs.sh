#!/usr/bin/env bash
echo "qst! meta Nixpkgs, 1.2.0, GitanElyon, Searches nixpkgs with search.nixos.org typeahead."
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

clip_list() {
	local list="$1"
	local limit="$2"
	[[ -z "$list" ]] && return 0
	local normalized="${list//, /$'\n'}"
	local -a items=()
	mapfile -t items <<< "$normalized"
	local total="${#items[@]}"
	if (( total <= limit )); then
		printf '%s' "$list"
		return 0
	fi
	local out=""
	local i
	for (( i = 0; i < limit; i++ )); do
		[[ -n "${items[i]}" ]] || continue
		out+="${out:+, }${items[i]}"
	done
	printf '%s, +%d more' "$out" "$((total - limit))"
}

format_platforms() {
	local list="$1"
	[[ -z "$list" ]] && return 0
	local normalized="${list//, /$'\n'}"
	local -a items=()
	mapfile -t items <<< "$normalized"
	local total="${#items[@]}"
	local linux=0 darwin=0 other=0
	local p
	for p in "${items[@]}"; do
		p="$(trim "$p")"
		[[ -z "$p" ]] && continue
		case "$p" in
			*-linux) linux=$((linux + 1)) ;;
			*-darwin) darwin=$((darwin + 1)) ;;
			*) other=$((other + 1)) ;;
		esac
	done
	local parts=""
	if (( linux > 0 )); then
		parts="${linux} linux"
	fi
	if (( darwin > 0 )); then
		parts="${parts:+${parts}, }${darwin} darwin"
	fi
	if (( other > 0 )); then
		parts="${parts:+${parts}, }${other} other"
	fi
	printf '%s platforms (%s)' "$total" "$parts"
}

render_help() {
	echo "qst! title  Nixpkgs Help "
	echo "qst! action None"
	echo "  nixpkgs <query>       search packages| @meta:nonselectable=true"
	echo "  nixpkgs s <query>     show summaries| @meta:nonselectable=true"
	echo "  nixpkgs v <query>     show versions| @meta:nonselectable=true"
	echo "  nixpkgs d <query>     show dependents (reverse deps)| @meta:nonselectable=true"
	echo "  nixpkgs b <query>     show provided binaries| @meta:nonselectable=true"
	echo "  nixpkgs m <query>     show maintainers| @meta:nonselectable=true"
	echo "  nixpkgs p <query>     show platform support| @meta:nonselectable=true"
	echo "  nixpkgs l <query>     show licenses| @meta:nonselectable=true"
	echo "  nixpkgs u <query>     show homepages| @meta:nonselectable=true"
	echo "  nixpkgs h             show this help| @meta:nonselectable=true"
}

QUERY="$(trim "$RAW_QUERY")"

case "$QUERY" in
	h|help)
		render_help
		exit 0
		;;
esac

MODE="search"
	case "$QUERY" in
	s\ *)
		MODE="summary"
		QUERY="$(trim "${QUERY#s }")"
		;;
	v\ *)
		MODE="version"
		QUERY="$(trim "${QUERY#v }")"
		;;
	d\ *)
		MODE="deps"
		QUERY="$(trim "${QUERY#d }")"
		;;
	b\ *)
		MODE="binaries"
		QUERY="$(trim "${QUERY#b }")"
		;;
	m\ *)
		MODE="maintainers"
		QUERY="$(trim "${QUERY#m }")"
		;;
	p\ *)
		MODE="platforms"
		QUERY="$(trim "${QUERY#p }")"
		;;
	l\ *)
		MODE="license"
		QUERY="$(trim "${QUERY#l }")"
		;;
	u\ *)
		MODE="homepage"
		QUERY="$(trim "${QUERY#u }")"
		;;
esac

echo "qst! title  Nixpkgs (${CHANNEL}) "

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
	echo " | @meta:nonselectable=true"
	exit 0
fi

ESCAPED_QUERY="$(json_escape "$QUERY")"
REQUEST_BODY="$(printf '{"from":0,"size":%s,"_source":["type","package_attr_name","package_pname","package_description","package_pversion","package_programs","package_maintainers_set","package_platforms","package_dep_count","package_license_set","package_homepage"],"query":{"bool":{"filter":[{"term":{"type":"package"}}],"must":[{"multi_match":{"query":"%s","type":"best_fields","operator":"and","fields":["package_attr_name.edge^4","package_pname.edge^3","package_description.edge^0.5"]}}]}}}' "$MAX_RESULTS" "$ESCAPED_QUERY")"

RESPONSE="$(curl -sf --max-time "$CURL_TIMEOUT" -u "${ES_USER}:${ES_PASS}" -H 'Content-Type: application/json' -d "$REQUEST_BODY" "${ES_HOST}/latest-${SCHEMA_VERSION}-${BRANCH}/_search" 2>/dev/null)" || RESPONSE=""

if [[ -z "$RESPONSE" ]]; then
	echo "qst! action None"
	echo "  No network access or backend unreachable| @meta:nonselectable=true"
	exit 0
fi

HITS="$(printf '%s' "$RESPONSE" | tr '\n' ' ' | awk -v max="$MAX_RESULTS" '
	function scalar(field,   pat, pos, rest) {
		pat = "\"" field "\":"
		pos = index(rec, pat)
		if (pos == 0) return ""
		rest = substr(rec, pos + length(pat))
		if (substr(rest, 1, 1) == "\"") {
			rest = substr(rest, 2)
			sub(/".*$/, "", rest)
			return rest
		}
		sub(/,.*$/, "", rest)
		return rest
	}
	function region(field,   pat, pos, start, i, n, c) {
		pat = "\"" field "\":["
		pos = index(rec, pat)
		if (pos == 0) return ""
		start = pos + length(pat)
		n = length(rec)
		i = start
		while (i <= n) {
			c = substr(rec, i, 1)
			if (c == "\"") {
				i++
				while (i <= n && substr(rec, i, 1) != "\"") i++
				i++
				continue
			}
			if (c == "]") return substr(rec, start, i - start)
			i++
		}
		return ""
	}
	function items(field,   content) {
		content = region(field)
		if (content == "") return ""
		gsub(/"/, "", content)
		gsub(/,/, ", ", content)
		return content
	}
	BEGIN { RS = "\"_source\"[ ]*:[ ]*\\{"; n = 0 }
	NR > 1 {
		rec = $0
		attr = scalar("package_attr_name")
		if (attr == "") next
		pname = scalar("package_pname")
		desc = scalar("package_description")
		ver = scalar("package_pversion")
		progs = items("package_programs")
		mains = items("package_maintainers_set")
		plats = items("package_platforms")
		deps = scalar("package_dep_count")
		lics = items("package_license_set")
		homes = items("package_homepage")
		gsub(/\t/, " ", progs); gsub(/\t/, " ", mains); gsub(/\t/, " ", plats)
		gsub(/\t/, " ", lics); gsub(/\t/, " ", homes)
		print attr "\034" pname "\034" desc "\034" ver "\034" progs "\034" mains "\034" plats "\034" deps "\034" lics "\034" homes
		n++
		if (n >= max) exit
	}
	')" || HITS=""

if [[ -z "$HITS" ]]; then
	echo "qst! action None"
	echo "  No packages found for: $(sanitize_text "$QUERY")| @meta:nonselectable=true"
	exit 0
fi

echo "qst! action CopyToClipboard,ExitApp"

while IFS=$'\034' read -r attr pname desc ver progs mains plats deps lics homes; do
	[[ -z "$attr" ]] && continue
	attr="$(trim "$attr")"
	pname="$(trim "$pname")"
	ver="$(trim "$ver")"
	deps="$(trim "$deps")"

	suffix=""
	case "$MODE" in
		summary)
			desc="$(json_unescape "$desc")"
			desc="$(strip_html "$desc")"
			desc="$(trim "$desc")"
			if [[ "${#desc}" -gt 80 ]]; then
				desc="${desc:0:80}…"
			fi
			suffix="$desc"
			;;
		version)
			suffix="$ver"
			;;
		deps)
			if [[ -n "$deps" ]]; then
				suffix="${deps} dependents"
			fi
			;;
		binaries)
			suffix="$(clip_list "$progs" 6)"
			;;
		maintainers)
			suffix="$(clip_list "$mains" 4)"
			;;
		platforms)
			suffix="$(format_platforms "$plats")"
			;;
		license)
			suffix="$(clip_list "$lics" 3)"
			;;
		homepage)
			suffix="${homes%%, *}"
			;;
		*)
			;;
	esac

	title="$attr"
	if [[ -n "$pname" && "$pname" != "$attr" ]]; then
		title="${title} · ${pname}"
	fi
	if [[ -n "$suffix" ]]; then
		title="${title} — ${suffix}"
	fi

	title="$(sanitize_text "$title")"
	value="${attr}"
	meta_terms="$attr"
	if [[ -n "$pname" && "$pname" != "$attr" ]]; then
		meta_terms="${meta_terms},${pname}"
	fi
	echo "qst! item  ${title}|${value} @meta:meta=${meta_terms}"
done <<< "$HITS"
