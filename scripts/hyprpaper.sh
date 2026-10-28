#!/usr/bin/env bash
set -euo pipefail
echo "qst! meta Hyprpaper, 1.1.0, GitanElyon, Manages wallpapers with hyprpaper: browse cycle random and fit modes."

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
RAW_QUERY="$*"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/qst"
STATE_FILE="$CACHE_DIR/hyprpaper_last"
MODE_FILE="$CACHE_DIR/hyprpaper_mode"
SPLASH_FILE="$CACHE_DIR/hyprpaper_splash"
mkdir -p "$CACHE_DIR"

# Wallpaper folders, in priority order. HYPRPAPER_DIR overrides the search.
SEARCH_DIRS=(
    "$HOME/Wallpapers"
    "$HOME/wallpapers"
    "$HOME/Images/Wallpapers"
    "$HOME/Images/wallpapers"
    "$HOME/Images"
    "$HOME/Pictures/Wallpapers"
    "$HOME/Pictures/wallpaper"
    "$HOME/.config/wallpapers"
    "/wallpapers"
)

MODE="fill"
if [[ -s "$MODE_FILE" ]]; then
    MODE="$(<"$MODE_FILE")"
fi
case "$MODE" in
    fill|tile|cover|contain) ;;
    *) MODE="fill" ;;
esac

SPLASH=""
if [[ -s "$SPLASH_FILE" ]]; then
    SPLASH="$(<"$SPLASH_FILE")"
fi

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

quote_shell_args() {
    local arg command=""
    for arg in "$@"; do
        command+="$(printf '%q ' "$arg")"
    done
    printf '%s' "${command% }"
}

find_wallpaper_dir() {
    if [[ -n "${HYPRPAPER_DIR:-}" ]]; then
        if [[ -d "$HYPRPAPER_DIR" ]]; then
            printf '%s\n' "$HYPRPAPER_DIR"
        fi
        return 0
    fi

    local candidate
    for candidate in "${SEARCH_DIRS[@]}"; do
        if [[ -d "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

list_wallpapers() {
    local dir="$1"
    find "$dir" -maxdepth 1 -type f \( \
        -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
        -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.bmp" \
        \) 2>/dev/null | sort || true
}

ensure_hyprpaper() {
    if ! command -v hyprpaper >/dev/null 2>&1; then
        echo "hyprpaper not found on PATH." >&2
        return 1
    fi

    if ! pgrep -x hyprpaper >/dev/null 2>&1; then
        hyprpaper >/dev/null 2>&1 &
        sleep 1
    fi
}

get_monitors() {
    local monitors=""

    if command -v jq >/dev/null 2>&1; then
        monitors="$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)"
    fi

    if [[ -z "$monitors" ]]; then
        monitors="$(hyprctl monitors 2>/dev/null | awk '/^Monitor/ { print $2 }' || true)"
    fi

    printf '%s\n' "$monitors"
}

check_backend() {
    if ! command -v hyprctl >/dev/null 2>&1; then
        echo "qst! title  Hyprpaper "
        echo "qst! action None"
        echo "  hyprctl not found - install Hyprland or run this inside a Hyprland session @meta:nonselectable=true @meta:center=true|"
        return 1
    fi

    if ! command -v hyprpaper >/dev/null 2>&1; then
        echo "qst! title  Hyprpaper "
        echo "qst! action None"
        echo "  hyprpaper not found - install it to set wallpapers @meta:nonselectable=true @meta:center=true|"
        return 1
    fi

    return 0
}

set_wallpaper() {
    local img="$1"
    local mode="${MODE:-fill}"
    local monitors monitor
    local failed=0

    if [[ ! -f "$img" ]]; then
        echo "Wallpaper not found: $img" >&2
        return 1
    fi

    if ! command -v hyprctl >/dev/null 2>&1; then
        echo "hyprctl not found. Is Hyprland installed?" >&2
        return 1
    fi

    img="$(realpath "$img")"

    case "$mode" in
        fill|tile|cover|contain) ;;
        *) mode="fill" ;;
    esac

    ensure_hyprpaper || return 1

    if [[ -n "$SPLASH" ]]; then
        hyprctl hyprpaper splash "$SPLASH" >/dev/null 2>&1 || true
    fi

    monitors="$(get_monitors)"

    if [[ -z "$monitors" ]]; then
        echo "No active monitors found via hyprctl." >&2
        return 1
    fi

    while IFS= read -r monitor; do
        [[ -z "$monitor" ]] && continue
        if ! hyprctl hyprpaper wallpaper "${monitor},${img},${mode}" >/dev/null 2>&1; then
            failed=1
        fi
    done <<< "$monitors"

    if (( failed )); then
        echo "Failed to set wallpaper with hyprpaper." >&2
        return 1
    fi

    printf '%s\n' "$img" > "$STATE_FILE"
}

set_action() {
    quote_shell_args "$SCRIPT_PATH" __set-index "$1"
}

load_images() {
    WALLPAPER_DIR="$(find_wallpaper_dir || true)"
    [[ -n "$WALLPAPER_DIR" ]] || return 1

    mapfile -t IMAGES < <(list_wallpapers "$WALLPAPER_DIR")
    CURRENT_INDEX=-1
    CURRENT_WALLPAPER="$(cat "$STATE_FILE" 2>/dev/null || true)"

    local i
    for i in "${!IMAGES[@]}"; do
        if [[ "$(realpath "${IMAGES[$i]}" 2>/dev/null || true)" == "$CURRENT_WALLPAPER" ]]; then
            CURRENT_INDEX=$i
            break
        fi
    done
}

splash_label() {
    case "$SPLASH" in
        true) printf 'on' ;;
        false) printf 'off' ;;
        *) printf 'default' ;;
    esac
}

render_help() {
    echo "qst! title  Hyprpaper Help "
    echo "qst! action None"
    echo "qst! item  hyprpaper          browse wallpapers|hyprpaper|None @meta:nonselectable=true"
    echo "qst! item  hyprpaper <text>   filter wallpapers by name|hyprpaper <text>|None @meta:nonselectable=true"
    echo "qst! item  hyprpaper n        set the next wallpaper|hyprpaper n|None @meta:nonselectable=true"
    echo "qst! item  hyprpaper p        set the previous wallpaper|hyprpaper p|None @meta:nonselectable=true"
    echo "qst! item  hyprpaper r        set a random wallpaper|hyprpaper r|None @meta:nonselectable=true"
    echo "qst! item  hyprpaper m        choose the fit mode|hyprpaper m|None @meta:nonselectable=true"
    echo "qst! item  hyprpaper s        choose the splash setting|hyprpaper s|None @meta:nonselectable=true"
    echo "qst! item  hyprpaper h        show this help|hyprpaper h|None @meta:nonselectable=true"
    echo "qst! item  ← Back to wallpapers|hyprpaper|SetSearchQuery @meta:permanent=true"
}

render_mode_menu() {
    echo "qst! title  Hyprpaper Fit Mode "
    echo "qst! action None"
    echo "  Current: ${MODE} @meta:nonselectable=true @meta:center=true|"

    local fit_mode fit_action
    for fit_mode in fill tile cover contain; do
        fit_action="$(quote_shell_args "$SCRIPT_PATH" __mode "$fit_mode")"
        if [[ "$fit_mode" == "$MODE" ]]; then
            echo "qst! item  ${fit_mode} *|${fit_action}|Execute,RefreshResults @meta:fg=green"
        else
            echo "qst! item  ${fit_mode}|${fit_action}|Execute,RefreshResults"
        fi
    done

    echo "  Fit mode is applied to every monitor @meta:nonselectable=true|"
    echo "qst! item  ← Back to wallpapers|hyprpaper|SetSearchQuery @meta:permanent=true"
}

render_splash_menu() {
    echo "qst! title  Hyprpaper Splash "
    echo "qst! action None"
    echo "  Current: $(splash_label) @meta:nonselectable=true @meta:center=true|"

    local splash_value label splash_action
    for splash_value in on off; do
        label="$splash_value"
        if [[ "$splash_value" == "on" && "$SPLASH" == "true" ]] || [[ "$splash_value" == "off" && "$SPLASH" == "false" ]]; then
            splash_action="$(quote_shell_args "$SCRIPT_PATH" __splash "$splash_value")"
            echo "qst! item  ${label} *|${splash_action}|Execute,RefreshResults @meta:fg=green"
        else
            splash_action="$(quote_shell_args "$SCRIPT_PATH" __splash "$splash_value")"
            echo "qst! item  ${label}|${splash_action}|Execute,RefreshResults"
        fi
    done

    echo "  Splash controls the hyprpaper transition @meta:nonselectable=true|"
    echo "qst! item  ← Back to wallpapers|hyprpaper|SetSearchQuery @meta:permanent=true"
}

render_filter() {
    local filter="$1"
    local filter_lc="${filter,,}"
    local -a matches=()
    local i label

    if ! check_backend; then
        return 0
    fi

    load_images || {
        echo "qst! title  Hyprpaper "
        echo "qst! action None"
        echo "  No wallpaper directory found @meta:nonselectable=true @meta:center=true|"
        echo "  Set HYPRPAPER_DIR or create ~/Wallpapers @meta:nonselectable=true @meta:center=true|"
        return 0
    }

    if (( ${#IMAGES[@]} == 0 )); then
        echo "qst! title  Hyprpaper "
        echo "qst! action None"
        echo "  No wallpapers found in ${WALLPAPER_DIR/#$HOME/~} @meta:nonselectable=true @meta:center=true|"
        return 0
    fi

    for i in "${!IMAGES[@]}"; do
        label="$(basename "${IMAGES[$i]}")"
        if [[ -n "$filter_lc" && "${label,,}" != *"$filter_lc"* ]]; then
            continue
        fi
        matches+=("$i")
    done

    echo "qst! title  Hyprpaper - ${WALLPAPER_DIR/#$HOME/~} "
    echo "qst! action None"

    if (( ${#matches[@]} == 0 )); then
        echo "  No wallpapers match: ${filter} @meta:nonselectable=true @meta:center=true|"
        echo "qst! item  ← Clear filter|hyprpaper|SetSearchQuery @meta:permanent=true"
        return 0
    fi

    echo "  ${#matches[@]} wallpapers · ${MODE} · splash $(splash_label) @meta:nonselectable=true @meta:center=true|"

    for i in "${matches[@]}"; do
        label="$(sanitize_text "$(basename "${IMAGES[$i]}")")"
        if [[ "$i" == "$CURRENT_INDEX" ]]; then
            echo "qst! item  ${label} *|$(set_action "$i")|Execute,ExitApp @meta:fg=green"
        else
            echo "qst! item  ${label}|$(set_action "$i")|Execute,ExitApp"
        fi
    done

    local random_index="${matches[$((RANDOM % ${#matches[@]}))]}"
    echo "qst! item  ──────────────────────────────|──────────────────────────────|None @meta:nonselectable=true @meta:center=true"
    echo "qst! item  Random from matches|$(set_action "$random_index")|Execute,ExitApp"

    if [[ -z "$filter" ]]; then
        local image_count=${#IMAGES[@]}
        local next_index prev_index next_label prev_label

        if (( CURRENT_INDEX < 0 )); then
            next_index=0
            prev_index=$((image_count - 1))
        else
            next_index=$(((CURRENT_INDEX + 1) % image_count))
            prev_index=$(((CURRENT_INDEX - 1 + image_count) % image_count))
        fi

        next_label="$(sanitize_text "$(basename "${IMAGES[$next_index]}")")"
        prev_label="$(sanitize_text "$(basename "${IMAGES[$prev_index]}")")"

        echo "qst! item  Next: ${next_label}|$(set_action "$next_index")|Execute,ExitApp"
        echo "qst! item  Previous: ${prev_label}|$(set_action "$prev_index")|Execute,ExitApp"
        echo "qst! item  Fit mode: ${MODE}|hyprpaper m|SetSearchQuery"
        echo "qst! item  Splash: $(splash_label)|hyprpaper s|SetSearchQuery"
        echo "qst! item  Help|hyprpaper h|SetSearchQuery @meta:permanent=true"
    fi
}

render_cycle() {
    local kind="$1"
    local index label

    if ! check_backend; then
        return 0
    fi

    load_images || {
        echo "qst! title  Hyprpaper "
        echo "qst! action None"
        echo "  No wallpaper directory found @meta:nonselectable=true @meta:center=true|"
        return 0
    }

    if (( ${#IMAGES[@]} == 0 )); then
        echo "qst! title  Hyprpaper "
        echo "qst! action None"
        echo "  No wallpapers found in ${WALLPAPER_DIR/#$HOME/~} @meta:nonselectable=true @meta:center=true|"
        return 0
    fi

    case "$kind" in
        next)
            if (( CURRENT_INDEX < 0 )); then
                index=0
            else
                index=$(((CURRENT_INDEX + 1) % ${#IMAGES[@]}))
            fi
            label="Next"
            ;;
        prev)
            if (( CURRENT_INDEX < 0 )); then
                index=$((${#IMAGES[@]} - 1))
            else
                index=$(((CURRENT_INDEX - 1 + ${#IMAGES[@]}) % ${#IMAGES[@]}))
            fi
            label="Previous"
            ;;
        *)
            index=$((RANDOM % ${#IMAGES[@]}))
            label="Random"
            ;;
    esac

    echo "qst! title  Hyprpaper ${label} "
    echo "qst! action Execute,ExitApp"
    echo "qst! item  Set ${label,,} wallpaper: $(sanitize_text "$(basename "${IMAGES[$index]}")")|$(set_action "$index")|Execute,ExitApp"
    echo "qst! item  ← Back to wallpapers|hyprpaper|SetSearchQuery @meta:permanent=true"
}

INPUT="$(trim "$RAW_QUERY")"

# Hidden one-shot actions used by rows. qst runs these through Execute.
case "$INPUT" in
    __set-index\ *)
        idx="$(trim "${INPUT#__set-index }")"
        if load_images; then
            if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx < ${#IMAGES[@]} )); then
                set_wallpaper "${IMAGES[$idx]}" || true
            fi
        fi
        exit 0
        ;;
    __mode\ *)
        new_mode="$(trim "${INPUT#__mode }")"
        case "$new_mode" in
            fill|tile|cover|contain) ;;
            *) exit 0 ;;
        esac
        MODE="$new_mode"
        printf '%s\n' "$MODE" > "$MODE_FILE"
        last_wallpaper="$(cat "$STATE_FILE" 2>/dev/null || true)"
        if [[ -n "$last_wallpaper" && -f "$last_wallpaper" ]]; then
            set_wallpaper "$last_wallpaper" || true
        fi
        exit 0
        ;;
    __splash\ *)
        new_splash="$(trim "${INPUT#__splash }")"
        case "$new_splash" in
            on|true) SPLASH="true" ;;
            off|false) SPLASH="false" ;;
            *) exit 0 ;;
        esac
        printf '%s\n' "$SPLASH" > "$SPLASH_FILE"
        if command -v hyprctl >/dev/null 2>&1; then
            ensure_hyprpaper || true
            hyprctl hyprpaper splash "$SPLASH" >/dev/null 2>&1 || true
        fi
        exit 0
        ;;
esac

normalized="$INPUT"

if [[ -z "$normalized" ]]; then
    render_filter ""
    exit 0
fi

cmd="${normalized%% *}"

case "$cmd" in
    h|help|-h|--help)
        render_help
        ;;
    n|next)
        render_cycle next
        ;;
    p|prev|previous)
        render_cycle prev
        ;;
    r|random)
        render_cycle random
        ;;
    m|mode|fit)
        render_mode_menu
        ;;
    s|splash)
        render_splash_menu
        ;;
    *)
        render_filter "$normalized"
        ;;
esac
