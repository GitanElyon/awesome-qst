#!/usr/bin/env bash
set -euo pipefail
echo "qst! meta Volume, 2.0.0, GitanElyon, Adjusts audio volume, switches outputs/inputs, and controls app streams."
QUERY="${1:-}"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_backend() {
    if command_exists wpctl; then
        echo "wpctl"
    elif command_exists pactl; then
        echo "pactl"
    elif command_exists amixer; then
        echo "amixer"
    else
        echo ""
    fi
}

sanitize() {
    local t="$1"
    t="${t//|/¦}"
    t="$(printf '%s' "$t" | tr '\n' ' ')"
    printf '%s' "$t"
}

lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

norm() {
    # lowercase + strip separators for fuzzy matching (hdmi-1 -> hdmi1)
    lower "$1" | sed -e 's/[^a-z0-9]//g'
}

trim() {
    local t="$1"
    t="$(printf '%s' "$t" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    printf '%s' "$t"
}

volume_bar() {
    local v="$1"
    local width=20
    if (( v < 0 )); then v=0; fi
    if (( v > 150 )); then v=150; fi
    # scale to width against 100% (overdrive shows full + marker)
    local capped="$v"
    if (( capped > 100 )); then capped=100; fi
    local filled=$(( (capped*width + 50) / 100 ))
    local empty=$(( width - filled ))
    printf '['
    if (( filled > 0 )); then
        printf '█%.0s' $(seq 1 "$filled" 2>/dev/null)
    fi
    if (( empty > 0 )); then
        printf '░%.0s' $(seq 1 "$empty" 2>/dev/null)
    fi
    printf ']'
    if (( v > 100 )); then
        printf '+'
    fi
}

# ---------- wpctl backend ----------

wp_default_sink() {
    wpctl list audio sinks 2>/dev/null | awk -F'\t' '$4 ~ /\*/ { gsub(/[^0-9]/, "", $1); print $1; exit }'
}

wp_default_source() {
    wpctl list audio sources 2>/dev/null | awk -F'\t' '$4 ~ /\*/ { gsub(/[^0-9]/, "", $1); print $1; exit }'
}

wp_node_name() {
    local id="$1"
    wpctl list audio 2>/dev/null | awk -F'\t' -v want="$id" '$1 == want { print $2; exit }'
}

wp_nick() {
    local id="$1"
    local nick
    nick="$(wpctl inspect "$id" 2>/dev/null | sed -n 's/.*node\.nick *= *"\([^"]*\)".*/\1/p' | head -n1)"
    if [[ -z "$nick" ]]; then
        nick="$(wpctl inspect "$id" 2>/dev/null | sed -n 's/.*device\.profile\.description *= *"\([^"]*\)".*/\1/p' | head -n1)"
    fi
    if [[ -z "$nick" ]]; then
        nick="$(wp_node_name "$id")"
    fi
    printf '%s' "$nick"
}

wp_desc() {
    local id="$1"
    wpctl inspect "$id" 2>/dev/null | sed -n 's/.*node\.description *= *"\([^"]*\)".*/\1/p' | head -n1
}

# echo: "<pct> <muted 0/1>"
wp_vol_mute() {
    local id="$1"
    local out raw pct muted=0
    out="$(wpctl get-volume "$id" 2>/dev/null || true)"
    if [[ "$out" =~ Volume:[[:space:]]*([0-9.]+) ]]; then
        raw="${BASH_REMATCH[1]}"
        pct="$(awk -v v="$raw" 'BEGIN { printf("%d", (v*100)+0.5) }')"
        if [[ "$out" == *"[MUTED]"* ]]; then muted=1; fi
        echo "$pct $muted"
        return
    fi
    echo "-1 -1"
}

wp_list_sinks() {
    # "<id>\t<node.name>\t<is_default 0/1>"
    wpctl list audio sinks 2>/dev/null | awk -F'\t' '{
        id=$1; gsub(/[^0-9]/, "", id);
        name=$2; gsub(/^[ \t]+|[ \t]+$/, "", name);
        def=($4 ~ /\*/) ? 1 : 0;
        if (id != "") print id "\t" name "\t" def
    }'
}

wp_list_sources() {
    wpctl list audio sources 2>/dev/null | awk -F'\t' '{
        id=$1; gsub(/[^0-9]/, "", id);
        name=$2; gsub(/^[ \t]+|[ \t]+$/, "", name);
        def=($4 ~ /\*/) ? 1 : 0;
        if (id != "") print id "\t" name "\t" def
    }'
}

wp_find_sinks() {
    # prints matching sink IDs, one per line
    local q="$1"
    local nq
    nq="$(norm "$q")"
    [[ -z "$nq" ]] && return 0
    local id name def nick desc lname lnick ldesc nname nnick
    while IFS=$'\t' read -r id name def; do
        [[ -z "$id" ]] && continue
        if [[ "$q" == "$id" ]]; then
            echo "$id"
            continue
        fi
        nick="$(wp_nick "$id")"
        desc="$(wp_desc "$id")"
        lname="$(lower "$name")"
        lnick="$(lower "$nick")"
        ldesc="$(lower "$desc")"
        nname="$(norm "$name")"
        nnick="$(norm "$nick")"
        # explicit hdmiN aliases (hdmi1 matches "HDMI / DisplayPort 1 Output")
        if [[ "$nq" =~ ^hdmi([0-9]+)$ ]] || [[ "$nq" =~ ^display([0-9]+)$ ]] || [[ "$nq" =~ ^dp([0-9]+)$ ]]; then
            local want="${BASH_REMATCH[1]}"
            if [[ "$nnick" == *"hdmi"* && "$nnick" == *"$want"* ]]; then
                echo "$id"
                continue
            fi
        fi
        case "$nq" in
            speaker|laptop|internal|builtin|builtinspeaker)
                [[ "$nnick" == *"speaker"* ]] && echo "$id" && continue
                ;;
            tv|hdmi|display|external|tv-speaker|tvspeaker)
                [[ "$nnick" == *"hdmi"* || "$nnick" == *"displayport"* ]] && echo "$id" && continue
                ;;
        esac
        if [[ "$nname" == *"$nq"* || "$nnick" == *"$nq"* || "$lname" == *"$q"* || "$lnick" == *"$q"* || "$ldesc" == *"$q"* ]]; then
            echo "$id"
        fi
    done < <(wp_list_sinks)
}

wp_find_sources() {
    local q="$1"
    local nq
    nq="$(norm "$q")"
    [[ -z "$nq" ]] && return 0
    local id name def nick lname lnick nname nnick
    while IFS=$'\t' read -r id name def; do
        [[ -z "$id" ]] && continue
        if [[ "$q" == "$id" ]]; then
            echo "$id"
            continue
        fi
        nick="$(wp_nick "$id")"
        lname="$(lower "$name")"
        lnick="$(lower "$nick")"
        nname="$(norm "$name")"
        nnick="$(norm "$nick")"
        case "$nq" in
            mic|microphone|internal|builtin|default)
                echo "$id"
                continue
                ;;
        esac
        if [[ "$nname" == *"$nq"* || "$nnick" == *"$nq"* || "$lname" == *"$q"* || "$lnick" == *"$q"* ]]; then
            echo "$id"
        fi
    done < <(wp_list_sources)
}

wp_set_vol() {
    local id="$1" pct="$2"
    echo "wpctl set-volume -l 1.5 ${id} ${pct}%"
}

wp_adj_vol() {
    local id="$1" delta="$2"
    if (( delta >= 0 )); then
        echo "wpctl set-volume -l 1.5 ${id} ${delta}%+"
    else
        echo "wpctl set-volume ${id} ${delta#-}%-"
    fi
}

wp_mute_cmd() {
    local id="$1" mode="${2:-toggle}"
    echo "wpctl set-mute ${id} ${mode}"
}

# ---------- pactl backend (fallback) ----------

pa_default_sink() {
    pactl get-default-sink 2>/dev/null || pactl info 2>/dev/null | awk '/Default Sink:/ { print $3 }'
}

pa_default_source() {
    pactl get-default-source 2>/dev/null || pactl info 2>/dev/null | awk '/Default Source:/ { print $3 }'
}

pa_list_sinks() {
    # "<name>\t<is_default>"
    local def
    def="$(pa_default_sink)"
    pactl list short sinks 2>/dev/null | awk -v d="$def" '{ name=$2; print name "\t" ((name==d)?1:0) }'
}

pa_vol_mute() {
    local name="$1"
    local vol mute=0
    vol="$(pactl get-sink-volume "$name" 2>/dev/null | sed -n 's|.* / *\([0-9]\+\)%.*|\1|p' | head -n1)"
    if pactl get-sink-mute "$name" 2>/dev/null | grep -qi "yes"; then mute=1; fi
    [[ -z "$vol" ]] && vol="-1"
    echo "$vol $mute"
}

# ---------- generic helpers ----------

default_sink_label() {
    local backend="$1"
    if [[ "$backend" == "wpctl" ]]; then
        local id nick
        id="$(wp_default_sink)"
        nick="$(wp_nick "$id")"
        printf '%s' "${nick:-$id}"
    elif [[ "$backend" == "pactl" ]]; then
        pa_default_sink
    else
        printf 'Master'
    fi
}

backend="$(detect_backend)"
if [[ -z "$backend" ]]; then
    echo "qst! title  Volume "
    echo "qst! action None"
    echo "qst! item  No audio backend found (requires wpctl, pactl, or amixer)|No backend|None @meta:nonselectable=true @meta:center=true"
    exit 0
fi

raw_arg="$(trim "${QUERY# }")"
arg="$(lower "$raw_arg")"

if [[ "$arg" == "-h" || "$arg" == "--help" || "$arg" == "help" ]]; then
    echo "qst! title  Volume Help "
    echo "qst! action None"
    echo "qst! item  volume               Volume status + quick controls|volume|None @meta:nonselectable=true"
    echo "qst! item  volume +N / -N       Adjust by N% (e.g. volume +10)|volume +N|None @meta:nonselectable=true"
    echo "qst! item  volume N             Set to N% 0-150 (e.g. volume 75)|volume N|None @meta:nonselectable=true"
    echo "qst! item  volume mute          Toggle mute|volume mute|None @meta:nonselectable=true"
    echo "qst! item  volume out           List output speakers|volume out|None @meta:nonselectable=true"
    echo "qst! item  volume out <name>    Output detail (vol, switch)|volume out speaker|None @meta:nonselectable=true"
    echo "qst! item  volume use <name>    Switch output now (e.g. volume use tv)|volume use tv|None @meta:nonselectable=true"
    echo "qst! item  volume in            List input mics|volume in|None @meta:nonselectable=true"
    echo "qst! item  volume apps          Per-app stream volumes|volume apps|None @meta:nonselectable=true"
    exit 0
fi

# ---------- mute / volume shortcuts (default sink) ----------

if [[ "$backend" == "wpctl" ]]; then
    DEF_SINK="$(wp_default_sink)"
    DEF_SOURCE="$(wp_default_source)"
    read -r CUR_VOL CUR_MUTE < <(wp_vol_mute "@DEFAULT_AUDIO_SINK@")
    DEF_NICK="$(wp_nick "$DEF_SINK")"
else
    DEF_SINK="$(pa_default_sink)"
    DEF_SOURCE="$(pa_default_source)"
    read -r CUR_VOL CUR_MUTE < <(pa_vol_mute "$DEF_SINK")
    DEF_NICK="$DEF_SINK"
fi
if [[ "$backend" == "amixer" ]]; then
    out="$(amixer get Master 2>/dev/null || true)"
    CUR_VOL="$(printf '%s' "$out" | sed -n 's|.*\[\([0-9]\+\)%\].*|\1|p' | head -n1)"
    [[ -z "$CUR_VOL" ]] && CUR_VOL="-1"
    if printf '%s' "$out" | grep -q "\[off\]"; then CUR_MUTE=1; else CUR_MUTE=0; fi
    DEF_NICK="Master"
fi

if [[ "$arg" == "mute" || "$arg" == "m" || "$arg" == "toggle" ]]; then
    echo "qst! title  Volume "
    echo "qst! action Execute,RefreshResults"
    if [[ "$backend" == "wpctl" ]]; then
        cmd="$(wp_mute_cmd "@DEFAULT_AUDIO_SINK@" toggle)"
    elif [[ "$backend" == "pactl" ]]; then
        cmd="pactl set-sink-mute $DEF_SINK toggle"
    else
        cmd="amixer set Master toggle"
    fi
    if [[ "$CUR_MUTE" == "1" ]]; then
        echo "qst! item  Unmute (${DEF_NICK})|${cmd}|Execute,RefreshResults"
    else
        echo "qst! item  Mute (${DEF_NICK})|${cmd}|Execute,RefreshResults"
    fi
    exit 0
fi

if [[ "$arg" == "unmute" || "$arg" == "um" ]]; then
    echo "qst! title  Volume "
    echo "qst! action Execute,RefreshResults"
    if [[ "$backend" == "wpctl" ]]; then
        echo "qst! item  Unmute (${DEF_NICK})|$(wp_mute_cmd "@DEFAULT_AUDIO_SINK@" 0)|Execute,RefreshResults"
    elif [[ "$backend" == "pactl" ]]; then
        echo "qst! item  Unmute (${DEF_NICK})|pactl set-sink-mute $DEF_SINK 0|Execute,RefreshResults"
    else
        echo "qst! item  Unmute|amixer set Master unmute|Execute,RefreshResults"
    fi
    exit 0
fi

if [[ "$arg" =~ ^\+([0-9]+)$ ]]; then
    delta="${BASH_REMATCH[1]}"
    echo "qst! title  Volume "
    if [[ "$backend" == "wpctl" ]]; then
        echo "qst! item  Increase ${DEF_NICK} by ${delta}%|$(wp_adj_vol "@DEFAULT_AUDIO_SINK@" "$delta")|Execute,RefreshResults"
    elif [[ "$backend" == "pactl" ]]; then
        echo "qst! item  Increase by ${delta}%|pactl set-sink-volume $DEF_SINK +${delta}%|Execute,RefreshResults"
    else
        echo "qst! item  Increase by ${delta}%|amixer set Master ${delta}%+|Execute,RefreshResults"
    fi
    exit 0
fi

if [[ "$arg" =~ ^-([0-9]+)$ ]]; then
    delta="${BASH_REMATCH[1]}"
    echo "qst! title  Volume "
    if [[ "$backend" == "wpctl" ]]; then
        echo "qst! item  Decrease ${DEF_NICK} by ${delta}%|$(wp_adj_vol "@DEFAULT_AUDIO_SINK@" "-$delta")|Execute,RefreshResults"
    elif [[ "$backend" == "pactl" ]]; then
        echo "qst! item  Decrease by ${delta}%|pactl set-sink-volume $DEF_SINK -${delta}%|Execute,RefreshResults"
    else
        echo "qst! item  Decrease by ${delta}%|amixer set Master ${delta}%-|Execute,RefreshResults"
    fi
    exit 0
fi

if [[ "$arg" =~ ^([0-9]+)$ ]]; then
    target="${BASH_REMATCH[1]}"
    if (( target > 150 )); then target=150; fi
    echo "qst! title  Volume "
    if [[ "$backend" == "wpctl" ]]; then
        echo "qst! item  Set ${DEF_NICK} to ${target}%|$(wp_set_vol "@DEFAULT_AUDIO_SINK@" "$target")|Execute,RefreshResults"
    elif [[ "$backend" == "pactl" ]]; then
        echo "qst! item  Set to ${target}%|pactl set-sink-volume $DEF_SINK ${target}%|Execute,RefreshResults"
    else
        echo "qst! item  Set to ${target}%|amixer set Master ${target}%|Execute,RefreshResults"
    fi
    exit 0
fi

# ---------- output (speaker) switching ----------

show_sink_detail_wp() {
    local id="$1"
    local nick desc vol mute
    nick="$(sanitize "$(wp_nick "$id")")"
    desc="$(sanitize "$(wp_desc "$id")")"
    read -r vol mute < <(wp_vol_mute "$id")
    local is_def=0
    [[ "$id" == "$(wp_default_sink)" ]] && is_def=1

    echo "qst! title  Volume - ${nick} "
    if (( is_def )); then
        echo "qst! item  [DEFAULT OUTPUT] ${vol}% $(if [[ "$mute" == "1" ]]; then printf '[MUTED]'; fi)|default|None @meta:nonselectable=true @meta:active=true @meta:center=true"
    else
        echo "qst! item  ${vol}% $(if [[ "$mute" == "1" ]]; then printf '[MUTED]'; fi) ${desc}|vol|None @meta:nonselectable=true @meta:center=true"
    fi
    if [[ "$vol" != "-1" ]]; then
        bar="$(volume_bar "$vol")"
        if [[ "$mute" == "1" ]]; then
            echo "qst! item  ${vol}% ${bar} [MUTED]|bar|None @meta:nonselectable=true @meta:urgent=true @meta:center=true"
        else
            echo "qst! item  ${vol}% ${bar}|bar|None @meta:nonselectable=true @meta:active=true @meta:center=true"
        fi
    fi
    if (( ! is_def )); then
        echo "qst! item  Switch to ${nick}|wpctl set-default ${id}|Execute,RefreshResults @meta:bold=true"
    fi
    echo "qst! item  +5%|$(wp_adj_vol "$id" 5)|Execute,RefreshResults"
    echo "qst! item  -5%|$(wp_adj_vol "$id" -5)|Execute,RefreshResults"
    echo "qst! item  +1%|$(wp_adj_vol "$id" 1)|Execute,RefreshResults"
    echo "qst! item  -1%|$(wp_adj_vol "$id" -1)|Execute,RefreshResults"
    if [[ "$mute" == "1" ]]; then
        echo "qst! item  Unmute|$(wp_mute_cmd "$id" 0)|Execute,RefreshResults"
    else
        echo "qst! item  Mute|$(wp_mute_cmd "$id" toggle)|Execute,RefreshResults"
    fi
    for p in 25 50 75 100; do
        echo "qst! item  Set to ${p}%|$(wp_set_vol "$id" "$p")|Execute,RefreshResults"
    done
    echo "qst! item  Set to 125% (boost)|$(wp_set_vol "$id" 125)|Execute,RefreshResults"
    echo "qst! item  Set to 150% (max boost)|$(wp_set_vol "$id" 150)|Execute,RefreshResults"
    echo "qst! item  <- Back to outputs|<- Back to outputs|PopLastToken @meta:permanent=true"
}

list_sinks_wp() {
    echo "qst! title  Volume - Outputs @meta:fuzzy=true"
    echo "qst! item  <- Back to volume|<- Back to volume|PopLastToken @meta:permanent=true"
    local count=0
    local id name def nick vol mute meta label
    while IFS=$'\t' read -r id name def; do
        if [[ -z "$id" ]]; then continue; fi
        nick="$(wp_nick "$id")"
        read -r vol mute < <(wp_vol_mute "$id")
        meta=""
        label="$(sanitize "$nick")"
        if [[ "$def" == "1" ]]; then
            meta=" @meta:active=true"
            label="${label}  * [${vol}%$(if [[ "$mute" == "1" ]]; then printf ', MUTED'; fi)]"
        else
            label="${label}  [${vol}%$(if [[ "$mute" == "1" ]]; then printf ', MUTED'; fi)]"
        fi
        echo "qst! item  ${label}|${id} |AppendToQuery @meta:meta=audio,sink${meta}"
        count=$((count+1))
    done < <(wp_list_sinks)
    if (( count == 0 )); then
        echo "qst! item  No output devices found|noop|None @meta:nonselectable=true @meta:center=true"
    else
        echo "qst! item  Tip: type use <name> to switch in one step (e.g. use tv)|tip|None @meta:nonselectable=true @meta:dim=true @meta:center=true"
    fi
}

if [[ "$arg" == "out" || "$arg" == "output" || "$arg" == "outputs" || "$arg" == "devices" || "$arg" == "d" || "$arg" == "speakers" ]]; then
    if [[ "$backend" == "wpctl" ]]; then
        list_sinks_wp
    elif [[ "$backend" == "pactl" ]]; then
        echo "qst! title  Volume - Outputs "
        echo "qst! item  <- Back to volume|<- Back to volume|PopLastToken @meta:permanent=true"
        while IFS=$'\t' read -r name def; do
            [[ -z "$name" ]] && continue
            read -r vol mute < <(pa_vol_mute "$name")
            if [[ "$def" == "1" ]]; then
                echo "qst! item  ${name} * [${vol}%]|pactl set-default-sink ${name}|Execute,RefreshResults @meta:active=true"
            else
                echo "qst! item  ${name} [${vol}%]|pactl set-default-sink ${name}|Execute,RefreshResults"
            fi
        done < <(pa_list_sinks)
    else
        echo "qst! title  Volume - Outputs "
        echo "qst! action None"
        echo "qst! item  Output switching needs wpctl or pactl|noop|None @meta:nonselectable=true @meta:center=true"
    fi
    exit 0
fi

if [[ "$arg" =~ ^(out|output|devices|d|speakers?)[[:space:]]+(.+)$ ]]; then
    target="$(trim "${BASH_REMATCH[2]}")"
    if [[ "$backend" != "wpctl" ]]; then
        echo "qst! title  Volume - Outputs "
        echo "qst! item  Per-output detail needs wpctl|noop|None @meta:nonselectable=true @meta:center=true"
        exit 0
    fi
    mapfile -t matches < <(wp_find_sinks "$(lower "$target")")
    if (( ${#matches[@]} == 0 )); then
        echo "qst! title  Volume - Outputs "
        echo "qst! item  No output matches '${target}'|noop|None @meta:nonselectable=true @meta:center=true"
        echo "qst! item  <- Back to outputs|<- Back to outputs|PopLastToken @meta:permanent=true"
        exit 0
    elif (( ${#matches[@]} == 1 )); then
        show_sink_detail_wp "${matches[0]}"
        exit 0
    else
        echo "qst! title  Volume - Outputs "
        echo "qst! item  Multiple matches, pick one|noop|None @meta:nonselectable=true @meta:center=true"
        for m in "${matches[@]}"; do
            nick="$(sanitize "$(wp_nick "$m")")"
            echo "qst! item  ${nick}|${m}|ReplaceLastToken"
        done
        exit 0
    fi
fi

if [[ "$arg" =~ ^(use|switch)[[:space:]]+(.+)$ ]]; then
    target="$(trim "${BASH_REMATCH[2]}")"
    if [[ "$backend" == "wpctl" ]]; then
        mapfile -t matches < <(wp_find_sinks "$(lower "$target")")
        echo "qst! title  Volume "
        if (( ${#matches[@]} == 0 )); then
            echo "qst! item  No output matches '${target}'|noop|None @meta:nonselectable=true @meta:center=true"
        elif (( ${#matches[@]} == 1 )); then
            nick="$(sanitize "$(wp_nick "${matches[0]}")")"
            echo "qst! item  Switch to ${nick}|wpctl set-default ${matches[0]}|Execute,RefreshResults @meta:bold=true"
        else
            echo "qst! item  Multiple matches for '${target}'|noop|None @meta:nonselectable=true @meta:center=true"
            for m in "${matches[@]}"; do
                nick="$(sanitize "$(wp_nick "$m")")"
                echo "qst! item  Switch to ${nick}|wpctl set-default ${m}|Execute,RefreshResults"
            done
        fi
    elif [[ "$backend" == "pactl" ]]; then
        echo "qst! title  Volume "
        echo "qst! item  Switch to ${target}|pactl set-default-sink ${target}|Execute,RefreshResults"
    else
        echo "qst! title  Volume "
        echo "qst! item  Output switching needs wpctl or pactl|noop|None @meta:nonselectable=true @meta:center=true"
    fi
    exit 0
fi

# ---------- inputs / mics ----------

show_source_detail_wp() {
    local id="$1"
    local nick vol mute is_def=0
    nick="$(sanitize "$(wp_nick "$id")")"
    read -r vol mute < <(wp_vol_mute "$id")
    [[ "$id" == "$(wp_default_source)" ]] && is_def=1
    echo "qst! title  Volume - ${nick} (input) "
    if (( is_def )); then
        echo "qst! item  [DEFAULT INPUT] ${vol}%|default|None @meta:nonselectable=true @meta:active=true @meta:center=true"
    else
        echo "qst! item  Input ${vol}%|vol|None @meta:nonselectable=true @meta:center=true"
    fi
    if (( ! is_def )); then
        echo "qst! item  Use as default input|wpctl set-default ${id}|Execute,RefreshResults @meta:bold=true"
    fi
    echo "qst! item  +5%|$(wp_adj_vol "$id" 5)|Execute,RefreshResults"
    echo "qst! item  -5%|$(wp_adj_vol "$id" -5)|Execute,RefreshResults"
    if [[ "$mute" == "1" ]]; then
        echo "qst! item  Unmute input|$(wp_mute_cmd "$id" 0)|Execute,RefreshResults"
    else
        echo "qst! item  Mute input|$(wp_mute_cmd "$id" toggle)|Execute,RefreshResults @meta:urgent=true"
    fi
    for p in 25 50 75 100; do
        echo "qst! item  Set input to ${p}%|$(wp_set_vol "$id" "$p")|Execute,RefreshResults"
    done
    echo "qst! item  <- Back to inputs|<- Back to inputs|PopLastToken @meta:permanent=true"
}

list_sources_wp() {
    echo "qst! title  Volume - Inputs @meta:fuzzy=true"
    echo "qst! item  <- Back to volume|<- Back to volume|PopLastToken @meta:permanent=true"
    local id name def nick vol mute label
    while IFS=$'\t' read -r id name def; do
        if [[ -z "$id" ]]; then continue; fi
        nick="$(sanitize "$(wp_nick "$id")")"
        read -r vol mute < <(wp_vol_mute "$id")
        label="${nick}  [${vol}%$(if [[ "$mute" == "1" ]]; then printf ', MUTED'; fi)]"
        if [[ "$def" == "1" ]]; then
            label="${label}  *"
            echo "qst! item  ${label}|${id} |AppendToQuery @meta:active=true @meta:meta=audio,source"
        else
            echo "qst! item  ${label}|${id} |AppendToQuery @meta:meta=audio,source"
        fi
    done < <(wp_list_sources)
}

if [[ "$arg" == "in" || "$arg" == "input" || "$arg" == "inputs" || "$arg" == "mic" || "$arg" == "mics" || "$arg" == "microphone" ]]; then
    if [[ "$backend" != "wpctl" ]]; then
        echo "qst! title  Volume - Inputs "
        echo "qst! item  Input switching needs wpctl|noop|None @meta:nonselectable=true @meta:center=true"
        exit 0
    fi
    list_sources_wp
    exit 0
fi

if [[ "$arg" =~ ^(in|input|mic)[[:space:]]+(.+)$ ]]; then
    target="$(trim "${BASH_REMATCH[2]}")"
    if [[ "$backend" != "wpctl" ]]; then
        echo "qst! title  Volume - Inputs "
        echo "qst! item  Input detail needs wpctl|noop|None @meta:nonselectable=true @meta:center=true"
        exit 0
    fi
    mapfile -t matches < <(wp_find_sources "$(lower "$target")")
    if (( ${#matches[@]} == 0 )); then
        echo "qst! title  Volume - Inputs "
        echo "qst! item  No input matches '${target}'|noop|None @meta:nonselectable=true @meta:center=true"
        exit 0
    elif (( ${#matches[@]} == 1 )); then
        show_source_detail_wp "${matches[0]}"
        exit 0
    else
        echo "qst! title  Volume - Inputs "
        for m in "${matches[@]}"; do
            nick="$(sanitize "$(wp_nick "$m")")"
            echo "qst! item  ${nick}|${m}|ReplaceLastToken"
        done
        exit 0
    fi
fi

# ---------- per-app streams ----------

if [[ "$arg" == "apps" || "$arg" == "streams" || "$arg" == "playback" || "$arg" == "app" ]]; then
    echo "qst! title  Volume - Apps @meta:fuzzy=true"
    echo "qst! item  <- Back to volume|<- Back to volume|PopLastToken @meta:permanent=true"
    if [[ "$backend" != "wpctl" ]]; then
        echo "qst! item  Per-app volume needs wpctl|noop|None @meta:nonselectable=true @meta:center=true"
        exit 0
    fi
    if ! command_exists pw-dump || ! command_exists jq; then
        echo "qst! item  Per-app view needs pw-dump + jq|noop|None @meta:nonselectable=true @meta:center=true"
        exit 0
    fi
    found=0
    while IFS=$'\t' read -r sid app desc; do
        if [[ -z "$sid" ]]; then continue; fi
        read -r vol mute < <(wp_vol_mute "$sid")
        [[ "$vol" == "-1" ]] && vol="?"
        label="$(sanitize "${app:-unknown} - ${desc:-$sid}")"
        if [[ "$mute" == "1" ]]; then
            label="${label}  [${vol}% MUTED]"
        else
            label="${label}  [${vol}%]"
        fi
        echo "qst! item  ${label}|${sid} |AppendToQuery @meta:meta=audio,stream"
        found=1
    done < <(pw-dump 2>/dev/null | jq -r '.[] | select(.type=="PipeWire:Interface:Node") | select(.info.props["media.class"]=="Audio/Stream" or .info.props["media.class"]=="Stream/Output/Audio") | "\(.id)\t\(.info.props["application.name"] // "?")\t\(.info.props["node.description"] // .info.props["media.name"] // "?")"' 2>/dev/null)
    if (( found == 0 )); then
        echo "qst! item  No app streams playing|noop|None @meta:nonselectable=true @meta:center=true"
    fi
    exit 0
fi

if [[ "$arg" =~ ^(app|apps)[[:space:]]+([0-9]+)$ ]]; then
    sid="${BASH_REMATCH[2]}"
    info="$(pw-dump "$sid" 2>/dev/null | jq -r '.[] | select(.id=='"$sid"') | "\(.info.props["application.name"] // "?") | \(.info.props["node.description"] // .info.props["media.name"] // "?")"' 2>/dev/null | head -n1)"
    read -r vol mute < <(wp_vol_mute "$sid")
    echo "qst! title  Volume - App ${sid} "
    echo "qst! item  $(sanitize "${info:-stream $sid}") ${vol}%|info|None @meta:nonselectable=true @meta:center=true"
    echo "qst! item  +5%|$(wp_adj_vol "$sid" 5)|Execute,RefreshResults"
    echo "qst! item  -5%|$(wp_adj_vol "$sid" -5)|Execute,RefreshResults"
    if [[ "$mute" == "1" ]]; then
        echo "qst! item  Unmute app|$(wp_mute_cmd "$sid" 0)|Execute,RefreshResults"
    else
        echo "qst! item  Mute app|$(wp_mute_cmd "$sid" toggle)|Execute,RefreshResults"
    fi
    for p in 25 50 75 100 150; do
        echo "qst! item  Set app to ${p}%|$(wp_set_vol "$sid" "$p")|Execute,RefreshResults"
    done
    echo "qst! item  <- Back to apps|<- Back to apps|PopLastToken @meta:permanent=true"
    exit 0
fi

# ---------- bare sink/source name shortcut: `volume speaker`, `volume tv` ----------

if [[ "$backend" == "wpctl" && -n "$arg" ]]; then
    mapfile -t s_matches < <(wp_find_sinks "$arg")
    mapfile -t src_matches < <(wp_find_sources "$arg")
    if (( ${#s_matches[@]} == 1 )) && (( ${#src_matches[@]} == 0 )); then
        show_sink_detail_wp "${s_matches[0]}"
        exit 0
    elif (( ${#s_matches[@]} == 0 )) && (( ${#src_matches[@]} == 1 )); then
        show_source_detail_wp "${src_matches[0]}"
        exit 0
    elif (( ${#s_matches[@]} > 1 )); then
        echo "qst! title  Volume - Outputs "
        for m in "${s_matches[@]}"; do
            nick="$(sanitize "$(wp_nick "$m")")"
            echo "qst! item  ${nick}|out ${m}|ReplaceLastToken"
        done
        exit 0
    fi
fi

# ---------- main menu ----------

if [[ "$CUR_VOL" == "-1" ]]; then
    title=" Volume "
else
    if [[ "$CUR_MUTE" == "1" ]]; then
        title=" Volume ${CUR_VOL}% [MUTED] - $(sanitize "$DEF_NICK") "
    else
        title=" Volume ${CUR_VOL}% - $(sanitize "$DEF_NICK") "
    fi
fi

echo "qst! title ${title} @meta:fuzzy=true"

if [[ "$CUR_VOL" == "-1" ]]; then
    echo "qst! item  Volume status unavailable|noop|None @meta:nonselectable=true @meta:center=true"
else
    bar="$(volume_bar "$CUR_VOL")"
    if [[ "$CUR_MUTE" == "1" ]]; then
        echo "qst! item  ${CUR_VOL}% ${bar} [MUTED] - $(sanitize "$DEF_NICK")|noop|None @meta:nonselectable=true @meta:urgent=true @meta:center=true"
    else
        echo "qst! item  ${CUR_VOL}% ${bar} - $(sanitize "$DEF_NICK")|noop|None @meta:nonselectable=true @meta:active=true @meta:center=true"
    fi
fi

if [[ "$backend" == "wpctl" ]]; then
    echo "qst! item  Volume Up (+5%)|$(wp_adj_vol "@DEFAULT_AUDIO_SINK@" 5)|Execute,RefreshResults"
    echo "qst! item  Volume Down (-5%)|$(wp_adj_vol "@DEFAULT_AUDIO_SINK@" -5)|Execute,RefreshResults"
    echo "qst! item  Volume Up (+1% fine)|$(wp_adj_vol "@DEFAULT_AUDIO_SINK@" 1)|Execute,RefreshResults"
    echo "qst! item  Volume Down (-1% fine)|$(wp_adj_vol "@DEFAULT_AUDIO_SINK@" -1)|Execute,RefreshResults"
    if [[ "$CUR_MUTE" == "1" ]]; then
        echo "qst! item  Unmute|$(wp_mute_cmd "@DEFAULT_AUDIO_SINK@" 0)|Execute,RefreshResults"
    else
        echo "qst! item  Mute|$(wp_mute_cmd "@DEFAULT_AUDIO_SINK@" toggle)|Execute,RefreshResults"
    fi
    for p in 25 50 75 100; do
        echo "qst! item  Set to ${p}%|$(wp_set_vol "@DEFAULT_AUDIO_SINK@" "$p")|Execute,RefreshResults"
    done
    echo "qst! item  Set to 150% (boost)|$(wp_set_vol "@DEFAULT_AUDIO_SINK@" 150)|Execute,RefreshResults"
    echo "qst! item  Outputs / Switch speakers|out |AppendToQuery @meta:permanent=true"
    echo "qst! item  Inputs / Mics|in |AppendToQuery @meta:permanent=true"
    echo "qst! item  App volumes|apps |AppendToQuery @meta:permanent=true"
elif [[ "$backend" == "pactl" ]]; then
    echo "qst! item  Volume Up (+5%)|pactl set-sink-volume $DEF_SINK +5%|Execute,RefreshResults"
    echo "qst! item  Volume Down (-5%)|pactl set-sink-volume $DEF_SINK -5%|Execute,RefreshResults"
    if [[ "$CUR_MUTE" == "1" ]]; then
        echo "qst! item  Unmute|pactl set-sink-mute $DEF_SINK 0|Execute,RefreshResults"
    else
        echo "qst! item  Mute|pactl set-sink-mute $DEF_SINK toggle|Execute,RefreshResults"
    fi
    for p in 25 50 75 100; do
        echo "qst! item  Set to ${p}%|pactl set-sink-volume $DEF_SINK ${p}%|Execute,RefreshResults"
    done
    echo "qst! item  Outputs / Switch speakers|out |AppendToQuery @meta:permanent=true"
else
    echo "qst! item  Volume Up (+5%)|amixer set Master 5%+|Execute,RefreshResults"
    echo "qst! item  Volume Down (-5%)|amixer set Master 5%-|Execute,RefreshResults"
    echo "qst! item  Mute toggle|amixer set Master toggle|Execute,RefreshResults"
    for p in 25 50 75 100; do
        echo "qst! item  Set to ${p}%|amixer set Master ${p}%|Execute,RefreshResults"
    done
fi
