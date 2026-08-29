#!/usr/bin/env bash
# Hand-rolled installer TUI: a persistent left sidebar of steps with a live
# content pane beside it, like a real OS installer. This does NOT use gum —
# gum's widgets fully own their terminal rows on every redraw (confirmed by
# testing), so nothing can persist beside them; a real sidebar-next-to-live-
# content layout needs direct control over the screen, which means reading
# keys and drawing with tput ourselves.
#
# Nothing touches the system until you select Install on the Finalize step;
# it then execs install.sh with the right flags/env vars — all the actual
# work still lives there.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACCENT=$'\033[38;2;193;2;250m'  # #c102fa, SichOS accent (quickshell/modules/Theme.qml)
DIM=$'\033[38;5;240m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# ---------- terminal setup ----------

# Raw ANSI escapes instead of shelling out to tput: tput is an external
# binary, and render() below calls cursor-positioning dozens of times per
# frame — that's dozens of fork+exec's per keypress, which is what was
# actually causing the visible flicker/lag, not the screen clear itself.
cup() { printf '\033[%d;%dH' "$(($1 + 1))" "$(($2 + 1))"; }   # 0-indexed row, col
clear_to_end()  { printf '\033[J'; }
clear_line_end(){ printf '\033[K'; }
cursor_hide()   { printf '\033[?25l'; }
cursor_show()   { printf '\033[?25h'; }
alt_screen_on() { printf '\033[?1049h'; }
alt_screen_off(){ printf '\033[?1049l'; }

cleanup() {
    cursor_show
    alt_screen_off
    stty sane 2>/dev/null
}
on_int() {
    cleanup
    echo "Cancelled — nothing was changed."
    exit 0
}
trap on_int INT
trap cleanup EXIT

stty -echo -icanon min 1 time 0
alt_screen_on
cursor_hide

COLS="$(tput cols)"
LINES="$(tput lines)"
SIDEBAR_W=30
HEADER_LINES=2

# ---------- key reading ----------
# REPLY is set to one of: UP DOWN LEFT RIGHT ENTER SPACE BACKSPACE TAB
# SHIFTTAB ESC NUL or CHAR:<c> for any other single character.
read_key() {
    local key k1 k2
    IFS= read -rsN1 key
    if [[ $key == $'\x1b' ]]; then
        if IFS= read -rsN1 -t 0.05 k1; then
            if [[ $k1 == '[' ]]; then
                IFS= read -rsN1 -t 0.05 k2
                case "$k2" in
                    A) REPLY=UP ;;
                    B) REPLY=DOWN ;;
                    C) REPLY=RIGHT ;;
                    D) REPLY=LEFT ;;
                    Z) REPLY=SHIFTTAB ;;
                    *) REPLY=ESC ;;
                esac
            else
                REPLY=ESC
            fi
        else
            REPLY=ESC
        fi
    else
        case "$key" in
            $'\x7f'|$'\x08') REPLY=BACKSPACE ;;
            $'\r'|$'\n')     REPLY=ENTER ;;
            $'\t')           REPLY=TAB ;;
            ' ')             REPLY=SPACE ;;
            '')              REPLY=NUL ;;
            *)               REPLY="CHAR:$key" ;;
        esac
    fi
}

# ---------- state ----------

STEPS=("Welcome" "Hostname" "Repositories" "Option Packages" "Git" "SSH" "Debug" "Finalize")
current_step=0
content_cursor=0

# Everything SichOS itself needs (wlctl, pavucontrol theme, fastfetch
# branding, Plymouth theme, greetd, wallpaper) is core and always installed
# by install.sh — it's not configurable here. Only genuinely optional extras
# live in this list, and they all default off. A FLATPAK:<app-id> target
# means the item is only selectable when Flatpak + Flathub (below) is on.
declare -A ITEM_TARGET=(
    ["Telegram"]="SKIP_TELEGRAM"
    ["Element (Matrix client)"]="FLATPAK:im.riot.Riot"
    ["Vesktop (Discord client)"]="FLATPAK:dev.vencord.Vesktop"
)
declare -A ITEM_DESC=(
    ["Telegram"]="Telegram Desktop messaging app"
    ["Element (Matrix client)"]="Matrix chat client"
    ["Vesktop (Discord client)"]="Discord client with Vencord mods built in"
)
COMPONENT_ORDER=(
    "Telegram"
    "Element (Matrix client)"
    "Vesktop (Discord client)"
)
declare -A SELECTED
for label in "${COMPONENT_ORDER[@]}"; do
    SELECTED["$label"]=0  # all optional extras default off
done

# Advanced/troubleshooting flags — kept off the main components screen.
declare -A DEBUG_TARGET=(
    ["Force software rendering (--vm)"]="FLAG:--vm"
    ["Swap SUPER to ALT (--alt)"]="FLAG:--alt"
)
declare -A DEBUG_DESC=(
    ["Force software rendering (--vm)"]="For VMware/vmwgfx VMs where accelerated rendering breaks wlroots clients"
    ["Swap SUPER to ALT (--alt)"]="Useful when the host OS/hypervisor eats the Super key"
)
DEBUG_ORDER=(
    "Force software rendering (--vm)"
    "Swap SUPER to ALT (--alt)"
)
for label in "${DEBUG_ORDER[@]}"; do
    SELECTED["$label"]=0
done

# Extra package repos beyond the ones this repo always enables (RPM Fusion,
# the lionheartp/Hyprland COPR).
FLATHUB_LABEL="Flatpak + Flathub (Recommended)"
declare -A REPO_TARGET=(
    ["$FLATHUB_LABEL"]="SKIP_FLATPAK"
)
declare -A REPO_DESC=(
    ["$FLATHUB_LABEL"]="Installs flatpak and adds the Flathub remote"
)
REPO_ORDER=(
    "$FLATHUB_LABEL"
)
for label in "${REPO_ORDER[@]}"; do
    SELECTED["$label"]=1  # on by default
done

flathub_enabled() { [ "${SELECTED[$FLATHUB_LABEL]}" = "1" ]; }

HOSTNAME_VALUE="$(hostname)"
GIT_NAME="$(git config --global user.name 2>/dev/null || true)"
GIT_EMAIL="$(git config --global user.email 2>/dev/null || true)"

SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
declare -A SSH_LABELS=(
    [existing]="Use existing key"
    [generate]="Generate a new ed25519 key"
    [generate-gh]="Generate a new key and add it to GitHub (via gh)"
    [skip]="Skip SSH setup"
)
SSH_OPTIONS=()
[ -f "$SSH_KEY_PATH" ] && SSH_OPTIONS+=("existing")
SSH_OPTIONS+=("generate" "generate-gh" "skip")
if [ -f "$SSH_KEY_PATH" ]; then SSH_KEY_MODE=existing; else SSH_KEY_MODE=generate-gh; fi

# Separate from the mode above (that's about *this machine's own* identity
# going out to GitHub) — this pulls a GitHub user's public keys IN, so they
# can log into this machine. Independent of SSH_KEY_MODE; blank = skip.
GH_IMPORT_USER=""

# Also independent: authorized_keys and a local keypair are both pointless
# for incoming access if sshd isn't actually running. Opt-in, like the
# rest of SSH/git setup — installing/enabling a network-facing service
# isn't something to do silently.
SSHD_ENABLED=0
# Only meaningful when SSHD_ENABLED is on (shown grayed out otherwise, like
# the FLATPAK: items above). Defaults to disabled (key-only) — enabling the
# server is already an opt-in step, so it should come up hardened rather
# than falling back to sshd's own permissive default.
SSHD_PASSWORD_AUTH=0

INSTALL_CONFIRMED=0

# ---------- layout helpers ----------

content_row_count() {
    case "${STEPS[$current_step]}" in
        Welcome)            echo 0 ;;
        Hostname)           echo 1 ;;
        Repositories)       echo "${#REPO_ORDER[@]}" ;;
        "Option Packages")  echo "${#COMPONENT_ORDER[@]}" ;;
        Git)                echo 2 ;;
        SSH)                echo "$((${#SSH_OPTIONS[@]} + 3))" ;;
        Debug)              echo "${#DEBUG_ORDER[@]}" ;;
        Finalize)           echo 1 ;;
    esac
}

content_col() { echo $((SIDEBAR_W + 3)); }

# ---------- rendering ----------

LEGEND="tab/shift+tab switch steps · ↑/↓ move · enter/space select · ctrl+c quit"

LAST_RENDERED_STEP=-1

render() {
    cup 0 0
    # Only clear when the step actually changed. Clearing on every keypress
    # made pure cursor moves (arrow up/down within a step) blank the whole
    # screen before repainting it — visible as a flash for what's really
    # just a one-row change; a step switch legitimately changes all the
    # content anyway, so clearing there doesn't read as flicker.
    if [ "$current_step" -ne "$LAST_RENDERED_STEP" ]; then
        clear_to_end
        LAST_RENDERED_STEP=$current_step
    fi

    printf "%s%s SichOS setup%s\n" "$BOLD" "$ACCENT" "$RESET"
    printf "\n"

    cup $((LINES - 1)) $((COLS - ${#LEGEND} - 1))
    printf "%s%s%s" "$DIM" "$LEGEND" "$RESET"

    local row label
    for row in "${!STEPS[@]}"; do
        cup $((HEADER_LINES + row)) 0
        if [ "$row" -eq "$current_step" ]; then
            printf "%s%s> %s%s" "$BOLD" "$ACCENT" "${STEPS[$row]}" "$RESET"
        else
            printf "  %s" "${STEPS[$row]}"
        fi
    done

    local sep_col=$SIDEBAR_W r
    for ((r = 0; r < LINES - 1; r++)); do
        cup "$r" "$sep_col"
        printf "%s│%s" "$DIM" "$RESET"
    done

    render_content
}

render_row() {
    # render_row <row> <selected?> <text...>
    local row="$1" is_cursor="$2"; shift 2
    cup "$row" "$(content_col)"
    clear_line_end
    if [ "$is_cursor" = "1" ]; then
        printf "%s%s> %s%s" "$BOLD" "$ACCENT" "$*" "$RESET"
    else
        printf "  %s" "$*"
    fi
}

# A dim divider between groups of related options, optionally labeled
# (e.g. naming what the group below it depends on).
render_separator() {
    local row="$1" label="${2:-}"
    cup "$row" "$(content_col)"
    clear_line_end
    if [ -n "$label" ]; then
        printf "%s── %s ──%s" "$DIM" "$label" "$RESET"
    else
        printf "%s────────────────────────────────%s" "$DIM" "$RESET"
    fi
}

render_content() {
    local col row0=$HEADER_LINES
    col="$(content_col)"

    case "${STEPS[$current_step]}" in
        Welcome)
            cup "$row0" "$col";     printf "Welcome to SichOS setup."
            cup $((row0+2)) "$col"; printf "Pick which optional pieces to install, set your git"
            cup $((row0+3)) "$col"; printf "identity, and set up an SSH key for GitHub."
            cup $((row0+5)) "$col"; printf "%sNothing is applied until you select Install on Finalize.%s" "$DIM" "$RESET"
            ;;
        Hostname)
            render_row "$row0" 1 "Hostname: $HOSTNAME_VALUE"
            ;;
        Repositories)
            local i label mark
            for i in "${!REPO_ORDER[@]}"; do
                label="${REPO_ORDER[$i]}"
                mark="[ ]"
                [ "${SELECTED[$label]}" = "1" ] && mark="[x]"
                render_row $((row0 + i*2)) "$([ "$content_cursor" -eq "$i" ] && echo 1 || echo 0)" "$mark $label"
                cup $((row0 + i*2 + 1)) $((col + 4))
                printf "%s%s%s" "$DIM" "${REPO_DESC[$label]}" "$RESET"
            done
            ;;
        "Option Packages")
            # Flat list, not grouped by install source — the source (and,
            # when relevant, why an item can't be toggled yet) is named
            # inline in its description instead, e.g. "[Flatpak] ...".
            local i label mark target is_flatpak source_tag desc_text prefix r=$row0
            for i in "${!COMPONENT_ORDER[@]}"; do
                label="${COMPONENT_ORDER[$i]}"
                target="${ITEM_TARGET[$label]}"
                is_flatpak=0
                case "$target" in
                    FLATPAK:*) is_flatpak=1; source_tag="[Flatpak]" ;;
                    *)         source_tag="[DNF]" ;;
                esac

                mark="[ ]"
                [ "${SELECTED[$label]}" = "1" ] && mark="[x]"

                if [ "$is_flatpak" = "1" ] && ! flathub_enabled; then
                    prefix="  "
                    [ "$content_cursor" -eq "$i" ] && prefix="> "
                    cup "$r" "$col"
                    printf "%s%s%s %s%s" "$DIM" "$prefix" "$mark" "$label" "$RESET"
                else
                    render_row "$r" "$([ "$content_cursor" -eq "$i" ] && echo 1 || echo 0)" "$mark $label"
                fi

                desc_text="$source_tag ${ITEM_DESC[$label]}"
                [ "$is_flatpak" = "1" ] && ! flathub_enabled && desc_text+=" (needs Flatpak + Flathub)"
                cup $((r+1)) $((col + 4))
                printf "%s%s%s" "$DIM" "$desc_text" "$RESET"
                r=$((r+2))
            done
            ;;
        Git)
            render_row "$row0" "$([ "$content_cursor" -eq 0 ] && echo 1 || echo 0)" "Full name: ${GIT_NAME:-(skip)}"
            render_row $((row0+1)) "$([ "$content_cursor" -eq 1 ] && echo 1 || echo 0)" "Email address: ${GIT_EMAIL:-(skip)}"
            cup $((row0+3)) "$col"
            printf "%sUsed for git authentication. Leave blank to skip.%s" "$DIM" "$RESET"
            ;;
        SSH)
            local i opt mark n=${#SSH_OPTIONS[@]} r=$row0
            [ -f "$SSH_KEY_PATH" ] && { cup $((r-1)) "$col"; printf "%sFound an existing key at %s%s" "$DIM" "$SSH_KEY_PATH" "$RESET"; }
            for i in "${!SSH_OPTIONS[@]}"; do
                opt="${SSH_OPTIONS[$i]}"
                mark="( )"
                [ "$opt" = "$SSH_KEY_MODE" ] && mark="(x)"
                render_row "$r" "$([ "$content_cursor" -eq "$i" ] && echo 1 || echo 0)" "$mark ${SSH_LABELS[$opt]}"
                r=$((r+1))
            done
            r=$((r+1))
            render_separator "$r"; r=$((r+1))

            render_row "$r" "$([ "$content_cursor" -eq "$n" ] && echo 1 || echo 0)" \
                "Get public keys from GitHub: ${GH_IMPORT_USER:-(skip)}"
            r=$((r+1))
            cup "$r" $((col + 4)); printf "%sWrite a username to add their keys to authorized_keys%s" "$DIM" "$RESET"
            r=$((r+2))
            render_separator "$r"; r=$((r+1))

            local sshd_mark="[ ]"
            [ "$SSHD_ENABLED" = "1" ] && sshd_mark="[x]"
            render_row "$r" "$([ "$content_cursor" -eq "$((n + 1))" ] && echo 1 || echo 0)" \
                "$sshd_mark Enable SSH server (sshd)"
            r=$((r+1))
            cup "$r" $((col + 4)); printf "%sInstalls openssh-server, enables+starts sshd, opens it in the firewall%s" "$DIM" "$RESET"
            r=$((r+2))

            local pw_mark="[x]"
            [ "$SSHD_PASSWORD_AUTH" != "1" ] && pw_mark="[ ]"
            if [ "$SSHD_ENABLED" != "1" ]; then
                local pw_prefix="    "
                [ "$content_cursor" -eq "$((n + 2))" ] && pw_prefix="  > "
                cup "$r" "$col"
                printf "%s%s%s Allow password login (unavailable — needs SSH server enabled)%s" "$DIM" "$pw_prefix" "$pw_mark" "$RESET"
            else
                render_row "$r" "$([ "$content_cursor" -eq "$((n + 2))" ] && echo 1 || echo 0)" \
                    "  $pw_mark Allow password login"
            fi
            r=$((r+1))
            cup "$r" $((col + 6)); printf "%sOff by default (key-only) — only turn on if you understand the risk%s" "$DIM" "$RESET"
            ;;
        Debug)
            local i label mark
            for i in "${!DEBUG_ORDER[@]}"; do
                label="${DEBUG_ORDER[$i]}"
                mark="[ ]"
                [ "${SELECTED[$label]}" = "1" ] && mark="[x]"
                render_row $((row0 + i*2)) "$([ "$content_cursor" -eq "$i" ] && echo 1 || echo 0)" "$mark $label"
                cup $((row0 + i*2 + 1)) $((col + 4))
                printf "%s%s%s" "$DIM" "${DEBUG_DESC[$label]}" "$RESET"
            done
            ;;
        Finalize)
            local r=$row0
            printf ""
            cup "$r" "$col"; printf "%sRepositories:%s" "$BOLD" "$RESET"; r=$((r+1))
            local label mark
            for label in "${REPO_ORDER[@]}"; do
                mark="[ ]"
                [ "${SELECTED[$label]}" = "1" ] && mark="[x]"
                cup "$r" $((col+2)); printf "%s %s" "$mark" "$label"; r=$((r+1))
            done
            r=$((r+1))
            cup "$r" "$col"; printf "%sComponents:%s" "$BOLD" "$RESET"; r=$((r+1))
            for label in "${COMPONENT_ORDER[@]}"; do
                mark="[ ]"
                [ "${SELECTED[$label]}" = "1" ] && mark="[x]"
                cup "$r" $((col+2)); printf "%s %s" "$mark" "$label"; r=$((r+1))
            done
            r=$((r+1))
            cup "$r" "$col"; printf "Hostname: %s" "$HOSTNAME_VALUE"; r=$((r+2))
            if [ -z "$GIT_NAME" ] && [ -z "$GIT_EMAIL" ]; then
                cup "$r" "$col"; printf "Git identity: (skipped)"; r=$((r+1))
            else
                cup "$r" "$col"; printf "Git identity: %s <%s>" "${GIT_NAME:-(none)}" "${GIT_EMAIL:-none}"; r=$((r+1))
            fi
            cup "$r" "$col"; printf "SSH key: %s" "${SSH_LABELS[$SSH_KEY_MODE]}"; r=$((r+1))
            cup "$r" "$col"; printf "Public keys from GitHub: %s" "${GH_IMPORT_USER:-(skipped)}"; r=$((r+1))
            cup "$r" "$col"; printf "SSH server (sshd): %s" "$([ "$SSHD_ENABLED" = "1" ] && echo enabled || echo "(skipped)")"; r=$((r+1))
            if [ "$SSHD_ENABLED" = "1" ]; then
                cup "$r" "$col"; printf "Password login: %s" "$([ "$SSHD_PASSWORD_AUTH" = "1" ] && echo allowed || echo disabled)"; r=$((r+1))
            fi
            r=$((r+1))
            cup "$r" "$col"; printf "%sDebug:%s" "$BOLD" "$RESET"; r=$((r+1))
            for label in "${DEBUG_ORDER[@]}"; do
                mark="[ ]"
                [ "${SELECTED[$label]}" = "1" ] && mark="[x]"
                cup "$r" $((col+2)); printf "%s %s" "$mark" "$label"; r=$((r+1))
            done
            r=$((r+1))
            render_row "$r" 1 "Install"
            ;;
    esac
}

# ---------- inline text field editor ----------
# Overlays a live-editable line at row/col; ENTER commits into EDIT_RESULT
# (return 0), ESC cancels (return 1, value unchanged).
edit_field() {
    local row="$1" col="$2" buf="$3"
    # The TUI hides the real terminal cursor everywhere else (navigation is
    # shown via highlighting instead), but a text field needs a visible
    # insertion point — otherwise there's no way to tell where typed
    # characters will land relative to the pre-filled value.
    cursor_show
    while true; do
        cup "$row" "$col"
        clear_line_end
        printf "%s" "$buf"
        cup "$row" $((col + ${#buf}))   # end of the text, not the start
        read_key
        case "$REPLY" in
            ENTER)     EDIT_RESULT="$buf"; cursor_hide; return 0 ;;
            ESC)       cursor_hide; return 1 ;;
            BACKSPACE) buf="${buf%?}" ;;
            SPACE)     buf+=" " ;;
            CHAR:*)    buf+="${REPLY#CHAR:}" ;;
            *)         : ;;
        esac
    done
}

# ---------- activating the highlighted content row ----------

activate_content_row() {
    local col row0=$HEADER_LINES
    col="$(content_col)"

    case "${STEPS[$current_step]}" in
        Hostname)
            if edit_field "$row0" $((col + 11)) "$HOSTNAME_VALUE"; then
                HOSTNAME_VALUE="$EDIT_RESULT"
            fi
            ;;
        Repositories)
            local label="${REPO_ORDER[$content_cursor]}"
            if [ "${SELECTED[$label]}" = "1" ]; then SELECTED["$label"]=0; else SELECTED["$label"]=1; fi
            # Turning Flathub off strands any flatpak-only app selection —
            # clear those rather than leaving a checked-but-unusable state.
            if [ "$label" = "$FLATHUB_LABEL" ] && ! flathub_enabled; then
                local c
                for c in "${COMPONENT_ORDER[@]}"; do
                    case "${ITEM_TARGET[$c]}" in
                        FLATPAK:*) SELECTED["$c"]=0 ;;
                    esac
                done
            fi
            ;;
        "Option Packages")
            local label="${COMPONENT_ORDER[$content_cursor]}"
            local target="${ITEM_TARGET[$label]}"
            case "$target" in
                FLATPAK:*) flathub_enabled || return ;;
            esac
            if [ "${SELECTED[$label]}" = "1" ]; then SELECTED["$label"]=0; else SELECTED["$label"]=1; fi
            ;;
        Git)
            if [ "$content_cursor" -eq 0 ]; then
                if edit_field "$row0" $((col + 13)) "$GIT_NAME"; then GIT_NAME="$EDIT_RESULT"; fi
            else
                if edit_field $((row0 + 1)) $((col + 17)) "$GIT_EMAIL"; then GIT_EMAIL="$EDIT_RESULT"; fi
            fi
            ;;
        SSH)
            local n=${#SSH_OPTIONS[@]}
            if [ "$content_cursor" -lt "$n" ]; then
                SSH_KEY_MODE="${SSH_OPTIONS[$content_cursor]}"
            elif [ "$content_cursor" -eq "$n" ]; then
                if edit_field $((row0 + n + 1)) $((col + 42)) "$GH_IMPORT_USER"; then
                    GH_IMPORT_USER="$EDIT_RESULT"
                fi
            elif [ "$content_cursor" -eq "$((n + 1))" ]; then
                if [ "$SSHD_ENABLED" = "1" ]; then SSHD_ENABLED=0; else SSHD_ENABLED=1; fi
            else
                [ "$SSHD_ENABLED" = "1" ] || return
                if [ "$SSHD_PASSWORD_AUTH" = "1" ]; then SSHD_PASSWORD_AUTH=0; else SSHD_PASSWORD_AUTH=1; fi
            fi
            ;;
        Debug)
            local label="${DEBUG_ORDER[$content_cursor]}"
            if [ "${SELECTED[$label]}" = "1" ]; then SELECTED["$label"]=0; else SELECTED["$label"]=1; fi
            ;;
        Finalize)
            INSTALL_CONFIRMED=1
            ;;
    esac
}

# ---------- main loop ----------

while [ "$INSTALL_CONFIRMED" -eq 0 ]; do
    render
    read_key
    n="$(content_row_count)"
    case "$REPLY" in
        TAB)
            current_step=$(( (current_step + 1) % ${#STEPS[@]} ))
            content_cursor=0
            ;;
        SHIFTTAB)
            current_step=$(( (current_step - 1 + ${#STEPS[@]}) % ${#STEPS[@]} ))
            content_cursor=0
            ;;
        UP)   [ "$n" -gt 0 ] && content_cursor=$(( (content_cursor - 1 + n) % n )) ;;
        DOWN) [ "$n" -gt 0 ] && content_cursor=$(( (content_cursor + 1) % n )) ;;
        ENTER|SPACE) [ "$n" -gt 0 ] && activate_content_row ;;
        *) : ;;
    esac
done

# ---------- build config and hand off to install.sh ----------

ENV_ARGS=()
FLAGS=()
FLATHUB_APPS=()
for label in "${REPO_ORDER[@]}" "${COMPONENT_ORDER[@]}" "${DEBUG_ORDER[@]}"; do
    target="${REPO_TARGET[$label]:-${ITEM_TARGET[$label]:-${DEBUG_TARGET[$label]}}}"
    case "$target" in
        FLAG:*)
            [ "${SELECTED[$label]}" = "1" ] && FLAGS+=("${target#FLAG:}")
            ;;
        FLATPAK:*)
            [ "${SELECTED[$label]}" = "1" ] && flathub_enabled && FLATHUB_APPS+=("${target#FLATPAK:}")
            ;;
        *)
            if [ "${SELECTED[$label]}" = "1" ]; then
                ENV_ARGS+=("$target=0")
            else
                ENV_ARGS+=("$target=1")
            fi
            ;;
    esac
done
ENV_ARGS+=("GIT_NAME=$GIT_NAME" "GIT_EMAIL=$GIT_EMAIL" "SSH_KEY_MODE=$SSH_KEY_MODE" "SICHOS_HOSTNAME=$HOSTNAME_VALUE" "GH_IMPORT_USER=$GH_IMPORT_USER")
ENV_ARGS+=("SKIP_SSHD=$([ "$SSHD_ENABLED" = "1" ] && echo 0 || echo 1)")
ENV_ARGS+=("SSHD_PASSWORD_AUTH=$SSHD_PASSWORD_AUTH")
[ "${#FLATHUB_APPS[@]}" -gt 0 ] && ENV_ARGS+=("FLATHUB_APPS=${FLATHUB_APPS[*]}")

cleanup
trap - INT EXIT

env "${ENV_ARGS[@]}" "$HERE/install.sh" "${FLAGS[@]}"
