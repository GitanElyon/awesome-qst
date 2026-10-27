#!/usr/bin/env bash
set -euo pipefail
echo "qst! meta Hyprpaper, 1.0.0, GitanElyon, Manages wallpapers with hyprpaper: browse cycle random and fit modes."

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
QUERY="$*"
arg="$(printf '%s' "$QUERY" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
arg_lc="${arg,,}"

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

sanitize_label() {
    local label="$1"
    label="${label//|/¦}"
    printf '%s' "$label"
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

quote_set_action() {
    printf '%q __set-index %s' "$SCRIPT_PATH" "$1"
}

# Hidden one-shot actions used by rows.
case "$arg" in
    __set-index\ *)
        idx="${arg#__set-index }"
        wallpaper_dir="$(find_wallpaper_dir || true)"
        if [[ -n "$wallpaper_dir" ]]; then
            mapfile -t images < <(list_wallpapers "$wallpaper_dir")
            if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx < ${#images[@]} )); then
                set_wallpaper "${images[$idx]}" || true
            fi
        fi
        exit 0
        ;;
    __mode\ *)
        new_mode="${arg#__mode }"
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
        new_splash="${arg#__splash }"
        case "$new_splash" in
            true|false) ;;
            *) exit 0 ;;
        esac
        SPLASH="$new_splash"
        printf '%s\n' "$SPLASH" > "$SPLASH_FILE"
        if command -v hyprctl >/dev/null 2>&1; then
            ensure_hyprpaper || true
            hyprctl hyprpaper splash "$SPLASH" >/dev/null 2>&1 || true
        fi
        exit 0
        ;;
esac

echo "qst! title Hyprpaper"
echo "qst! action None"

if ! command -v hyprctl >/dev/null 2>&1; then
    echo "  hyprctl not found - install Hyprland or run this inside a Hyprland session @meta:nonselectable=true @meta:center=true|"
    exit 0
fi

if ! command -v hyprpaper >/dev/null 2>&1; then
    echo "  hyprpaper not found - install it to set wallpapers @meta:nonselectable=true @meta:center=true|"
    exit 0
fi

wallpaper_dir="$(find_wallpaper_dir || true)"

if [[ -z "$wallpaper_dir" ]]; then
    echo "  No wallpaper directory found @meta:nonselectable=true @meta:center=true|"
    echo "  Checked ~/Wallpapers ~/wallpapers ~/Images/Wallpapers ~/Images/wallpapers ~/Images @meta:nonselectable=true @meta:center=true|"
    echo "  Also ~/Pictures/Wallpapers ~/Pictures/wallpaper ~/.config/wallpapers /wallpapers @meta:nonselectable=true @meta:center=true|"
    exit 0
fi

display_dir="$(sanitize_label "${wallpaper_dir/#$HOME/~}")"

if [[ "$arg" == "-h" || "$arg" == "--help" || "$arg" == "help" ]]; then
    echo "qst! title Hyprpaper"
    echo "qst! action None"
    echo "  Type to filter wallpapers, Enter applies one @meta:nonselectable=true|"
    echo "  Random / Next / Previous rows are listed below the wallpapers @meta:nonselectable=true|"
    echo "  hyprpaper mode [fill|tile|cover|contain]   Set the fit mode @meta:nonselectable=true|"
    echo "  hyprpaper splash [true|false]              Set hyprpaper splash @meta:nonselectable=true|"
    echo "  Set HYPRPAPER_DIR to use a custom wallpaper folder @meta:nonselectable=true|"
    echo "  Wallpaper folder: ${display_dir} @meta:nonselectable=true|"
    exit 0
fi

if [[ "$arg" == "mode" || "$arg" == "mode "* ]]; then
    if [[ "$arg" == "mode "* ]]; then
        new_mode="${arg#mode }"
        case "$new_mode" in
            fill|tile|cover|contain)
                MODE="$new_mode"
                printf '%s\n' "$MODE" > "$MODE_FILE"
                last_wallpaper="$(cat "$STATE_FILE" 2>/dev/null || true)"
                if [[ -n "$last_wallpaper" && -f "$last_wallpaper" ]]; then
                    set_wallpaper "$last_wallpaper" || true
                fi
                echo "qst! title Hyprpaper - Fit Mode"
                echo "qst! action None"
                echo "  Fit mode set to ${MODE} @meta:nonselectable=true @meta:center=true|"
                echo "  Back|hyprpaper mode |SetSearchQuery @meta:nonselectable=true"
                exit 0
                ;;
        esac
    fi

    echo "qst! title Hyprpaper - Fit Mode"
    echo "qst! action None"
    for fit_mode in fill tile cover contain; do
        fit_cmd="$(printf '%q __mode %q' "$SCRIPT_PATH" "$fit_mode")"
        if [[ "$fit_mode" == "$MODE" ]]; then
            echo "qst! item  ${fit_mode} *|${fit_cmd}|Execute,RefreshResults @meta:fg=green"
        else
            echo "qst! item  ${fit_mode}|${fit_cmd}|Execute,RefreshResults"
        fi
    done
    echo "  Fit mode applies to every monitor @meta:nonselectable=true|"
    echo "  Back|hyprpaper |SetSearchQuery @meta:nonselectable=true"
    exit 0
fi

if [[ "$arg" == "splash" || "$arg" == "splash "* ]]; then
    if [[ "$arg" == "splash "* ]]; then
        new_splash="${arg#splash }"
        case "$new_splash" in
            true|false)
                SPLASH="$new_splash"
                printf '%s\n' "$SPLASH" > "$SPLASH_FILE"
                if command -v hyprctl >/dev/null 2>&1; then
                    ensure_hyprpaper || true
                    hyprctl hyprpaper splash "$SPLASH" >/dev/null 2>&1 || true
                fi
                echo "qst! title Hyprpaper - Splash"
                echo "qst! action None"
                echo "  Splash set to ${SPLASH} @meta:nonselectable=true @meta:center=true|"
                echo "  Back|hyprpaper splash |SetSearchQuery @meta:nonselectable=true"
                exit 0
                ;;
        esac
    fi

    echo "qst! title Hyprpaper - Splash"
    echo "qst! action None"
    for splash_value in true false; do
        splash_cmd="$(printf '%q __splash %q' "$SCRIPT_PATH" "$splash_value")"
        if [[ "$splash_value" == "$SPLASH" ]]; then
            echo "qst! item  ${splash_value} *|${splash_cmd}|Execute,RefreshResults @meta:fg=green"
        else
            echo "qst! item  ${splash_value}|${splash_cmd}|Execute,RefreshResults"
        fi
    done
    echo "  Splash controls the hyprpaper transition @meta:nonselectable=true|"
    echo "  Back|hyprpaper |SetSearchQuery @meta:nonselectable=true"
    exit 0
fi

mapfile -t images < <(list_wallpapers "$wallpaper_dir")

if (( ${#images[@]} == 0 )); then
    echo "qst! title Hyprpaper - ${display_dir}"
    echo "  No wallpapers found in ${display_dir} @meta:nonselectable=true @meta:center=true|"
    exit 0
fi

current_wallpaper="$(cat "$STATE_FILE" 2>/dev/null || true)"
current_index=-1

for i in "${!images[@]}"; do
    if [[ "$(realpath "${images[$i]}" 2>/dev/null || true)" == "$current_wallpaper" ]]; then
        current_index=$i
        break
    fi
done

match_indices=()
for i in "${!images[@]}"; do
    label="$(basename "${images[$i]}")"
    if [[ -n "$arg_lc" && "${label,,}" != *"$arg_lc"* ]]; then
        continue
    fi
    match_indices+=("$i")
done

echo "qst! title Hyprpaper - ${display_dir}"
echo "qst! action None"

for i in "${match_indices[@]}"; do
    path="${images[$i]}"
    label="$(sanitize_label "$(basename "$path")")"

    if [[ "$(realpath "$path" 2>/dev/null || true)" == "$current_wallpaper" ]]; then
        label="${label} *"
        echo "qst! item  ${label}|$(quote_set_action "$i")|Execute,ExitApp @meta:fg=green"
    else
        echo "qst! item  ${label}|$(quote_set_action "$i")|Execute,ExitApp"
    fi
done

if (( ${#match_indices[@]} == 0 )); then
    echo "  No wallpapers match: ${arg} @meta:nonselectable=true @meta:center=true|"
    exit 0
fi

echo "qst! item  ──────────────────────────────|──────────────────────────────|None @meta:nonselectable=true @meta:center=true"

random_index="${match_indices[$((RANDOM % ${#match_indices[@]}))]}"
echo "qst! item  Random wallpaper|$(quote_set_action "$random_index")|Execute,ExitApp"

if [[ -z "$arg" ]]; then
    image_count=${#images[@]}

    if (( current_index < 0 )); then
        next_index=0
        prev_index=$((image_count - 1))
    else
        next_index=$(((current_index + 1) % image_count))
        prev_index=$(((current_index - 1 + image_count) % image_count))
    fi

    next_label="$(sanitize_label "$(basename "${images[$next_index]}")")"
    prev_label="$(sanitize_label "$(basename "${images[$prev_index]}")")"

    echo "qst! item  Next: ${next_label}|$(quote_set_action "$next_index")|Execute,ExitApp"
    echo "qst! item  Previous: ${prev_label}|$(quote_set_action "$prev_index")|Execute,ExitApp"

    case "$SPLASH" in
        true) splash_label="on" ;;
        false) splash_label="off" ;;
        *) splash_label="default" ;;
    esac

    echo "qst! item  Fit mode: ${MODE}|hyprpaper mode |SetSearchQuery"
    echo "qst! item  Splash: ${splash_label}|hyprpaper splash |SetSearchQuery"
fi
