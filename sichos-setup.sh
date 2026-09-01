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

ACCENT=$'\033[38;2;105;139;133m'  # #698b85, SichOS accent (quickshell/modules/Theme.qml)
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

STEPS=("Welcome" "Hostname" "Time & Region" "Repositories" "Option Packages" "Gaming" "Browser" "Git" "SSH" "Debug" "Finalize")
current_step=0
content_cursor=0

# Everything SichOS itself needs (wlctl, pavucontrol theme, fastfetch
# branding, Plymouth theme, SDDM, wallpaper) is core and always installed
# by install.sh — it's not configurable here. Only genuinely optional extras
# live in this list, and they all default off. A FLATPAK:<app-id> target
# means the item is only selectable when Flatpak + Flathub (below) is on.
# GFNFLATPAK:<app-id> is the same idea for GeForce NOW specifically — it
# isn't on Flathub, Nvidia ships it from their own flatpak repo instead, so
# it needs its own remote (added by install.sh, not this Flathub one) but
# still needs the flatpak binary itself, hence still gated on the same
# Flatpak + Flathub toggle.
declare -A ITEM_TARGET=(
    ["Telegram"]="SKIP_TELEGRAM"
    ["Element (Matrix client)"]="FLATPAK:im.riot.Riot"
    ["Vesktop (Discord client)"]="FLATPAK:dev.vencord.Vesktop"
    ["Signal Desktop"]="FLATPAK:org.signal.Signal"
    ["Discord"]="SKIP_DISCORD"
    ["Zoom"]="FLATPAK:us.zoom.Zoom"
    ["Steam"]="SKIP_STEAM"
    ["Heroic Games Launcher"]="FLATPAK:com.heroicgameslauncher.hgl"
    ["Lutris"]="SKIP_LUTRIS"
    ["Prism Launcher"]="FLATPAK:org.prismlauncher.PrismLauncher"
    ["RetroArch"]="FLATPAK:org.libretro.RetroArch"
    ["Dolphin Emulator"]="FLATPAK:org.DolphinEmu.dolphin-emu"
    ["PCSX2"]="FLATPAK:net.pcsx2.PCSX2"
    ["RPCS3"]="FLATPAK:net.rpcs3.RPCS3"
    ["Cemu"]="FLATPAK:info.cemu.Cemu"
    ["PPSSPP"]="FLATPAK:org.ppsspp.PPSSPP"
    ["DuckStation"]="FLATPAK:org.duckstation.DuckStation"
    ["mGBA"]="FLATPAK:io.mgba.mGBA"
    ["xemu"]="FLATPAK:app.xemu.xemu"
    ["ScummVM"]="FLATPAK:org.scummvm.ScummVM"
    ["GeForce NOW"]="GFNFLATPAK:com.nvidia.geforcenow"
    ["Spotify"]="FLATPAK:com.spotify.Client"
    ["OBS Studio"]="FLATPAK:com.obsproject.Studio"
    ["LibreOffice"]="SKIP_LIBREOFFICE"
    ["Obsidian"]="FLATPAK:md.obsidian.Obsidian"
    ["AppFlowy"]="FLATPAK:io.appflowy.AppFlowy"
    ["Joplin"]="FLATPAK:net.cozic.joplin_desktop"
    ["VS Code"]="FLATPAK:com.visualstudio.code"
    ["VSCodium"]="FLATPAK:com.vscodium.codium"
    ["Bitwarden"]="FLATPAK:com.bitwarden.desktop"
    ["Proton Pass"]="FLATPAK:me.proton.Pass"
)
declare -A ITEM_DESC=(
    ["Telegram"]="Telegram Desktop messaging app"
    ["Element (Matrix client)"]="Matrix chat client"
    ["Vesktop (Discord client)"]="Discord client with Vencord mods built in"
    ["Signal Desktop"]="Private messenger"
    ["Discord"]="Voice/video chat and messaging"
    ["Zoom"]="Video conferencing"
    ["Steam"]="Valve's game store and launcher"
    ["Heroic Games Launcher"]="Play Epic, GOG, and Amazon games"
    ["Lutris"]="Open-source game launcher for managing games from any source"
    ["Prism Launcher"]="Minecraft launcher for managing multiple instances/mod loaders"
    ["RetroArch"]="Multi-system emulator frontend (libretro cores)"
    ["Dolphin Emulator"]="GameCube and Wii emulator"
    ["PCSX2"]="PlayStation 2 emulator"
    ["RPCS3"]="PlayStation 3 emulator"
    ["Cemu"]="Wii U emulator"
    ["PPSSPP"]="PSP emulator"
    ["DuckStation"]="PlayStation 1 emulator"
    ["mGBA"]="Game Boy / Game Boy Advance emulator"
    ["xemu"]="Original Xbox emulator"
    ["ScummVM"]="Engine for classic point-and-click adventure games"
    ["GeForce NOW"]="Nvidia's cloud gaming client (own Flatpak repo, not Flathub)"
    ["Spotify"]="Music streaming"
    ["OBS Studio"]="Screen recording and streaming"
    ["LibreOffice"]="Office suite (documents, spreadsheets, slides)"
    ["Obsidian"]="Markdown notes app"
    ["AppFlowy"]="Open-source Notion alternative"
    ["Joplin"]="Open-source note-taking and to-do app"
    ["VS Code"]="Code editor"
    ["VSCodium"]="VS Code build without Microsoft telemetry/branding"
    ["Bitwarden"]="Password manager"
    ["Proton Pass"]="Proton's password manager"
)
# Groups items for display AND for a per-group "select all" row. Doesn't
# change the install logic, which still just reads SELECTED per label.
declare -A ITEM_GROUP=(
    ["Telegram"]="Messengers"
    ["Element (Matrix client)"]="Messengers"
    ["Vesktop (Discord client)"]="Messengers"
    ["Signal Desktop"]="Messengers"
    ["Discord"]="Messengers"
    ["Zoom"]="Messengers"
    ["Spotify"]="Media"
    ["OBS Studio"]="Media"
    ["LibreOffice"]="Productivity"
    ["Obsidian"]="Productivity"
    ["AppFlowy"]="Productivity"
    ["Joplin"]="Productivity"
    ["VS Code"]="Development"
    ["VSCodium"]="Development"
    ["Bitwarden"]="Security"
    ["Proton Pass"]="Security"
)
COMPONENT_ORDER=(
    "Telegram"
    "Element (Matrix client)"
    "Vesktop (Discord client)"
    "Signal Desktop"
    "Discord"
    "Zoom"
    "Spotify"
    "OBS Studio"
    "LibreOffice"
    "Obsidian"
    "AppFlowy"
    "Joplin"
    "VS Code"
    "VSCodium"
    "Bitwarden"
    "Proton Pass"
)
# "Select all" per group is a toggle, not a one-way action: pressing it
# snapshots each item's current on/off state in the group, then checks
# everything; pressing it again (a mistaken press, or just changing your
# mind) restores that exact snapshot rather than unchecking everything.
# Shared by every step with a grouped checkbox list (Option Packages,
# Gaming) — $2/$3 name which ORDER/GROUP arrays that group belongs to, via
# nameref, since group names (e.g. "Emulation") are unique across steps.
declare -A GROUP_ALL_ACTIVE=()
declare -A GROUP_SNAPSHOT=()
select_all_group() {
    local group="$1"
    local -n _order="$2" _item_group="$3"
    local label target
    if [ "${GROUP_ALL_ACTIVE[$group]:-0}" = "1" ]; then
        local i=0 vals
        IFS=' ' read -ra vals <<< "${GROUP_SNAPSHOT[$group]}"
        for label in "${_order[@]}"; do
            [ "${_item_group[$label]}" = "$group" ] || continue
            SELECTED["$label"]="${vals[$i]}"
            i=$((i+1))
        done
        GROUP_ALL_ACTIVE["$group"]=0
    else
        local snap=""
        for label in "${_order[@]}"; do
            [ "${_item_group[$label]}" = "$group" ] || continue
            snap+="${SELECTED[$label]} "
        done
        GROUP_SNAPSHOT["$group"]="${snap% }"
        for label in "${_order[@]}"; do
            [ "${_item_group[$label]}" = "$group" ] || continue
            target="${ITEM_TARGET[$label]}"
            case "$target" in
                # Leave a still-unavailable Flatpak item as-is — same rule
                # manually toggling one already follows.
                FLATPAK:*|GFNFLATPAK:*) flathub_enabled || continue ;;
            esac
            SELECTED["$label"]=1
        done
        GROUP_ALL_ACTIVE["$group"]=1
    fi
}
# Builds a "GROUP:<name>" / "ITEM:<label>" row list into the nameref'd $1
# from ORDER array $2 and its matching GROUP map $3 — one GROUP: row before
# each group's items. Shared by every step with a grouped checkbox list;
# the single source of truth content_row_count/render_content/
# activate_content_row all use so their row numbering can't drift apart.
build_grouped_rows() {
    local -n _rows="$1" _order="$2" _item_group="$3"
    _rows=()
    local label group prev_group=""
    for label in "${_order[@]}"; do
        group="${_item_group[$label]}"
        if [ "$group" != "$prev_group" ]; then
            _rows+=("GROUP:$group")
            prev_group="$group"
        fi
        _rows+=("ITEM:$label")
    done
}
OPTION_ROWS=()
GAMING_ROWS=()
declare -A SELECTED
for label in "${COMPONENT_ORDER[@]}"; do
    SELECTED["$label"]=0  # all optional extras default off
done

# Gaming gets its own step (tab) instead of living inside Option Packages —
# it's a big enough category (launchers, emulators, cloud gaming) to want
# its own screen, and it groups by sub-category the same way Option
# Packages groups by app category.
declare -A GAMING_GROUP=(
    ["Steam"]="Launchers"
    ["Heroic Games Launcher"]="Launchers"
    ["Lutris"]="Launchers"
    ["Prism Launcher"]="Launchers"
    ["RetroArch"]="Emulation"
    ["Dolphin Emulator"]="Emulation"
    ["PCSX2"]="Emulation"
    ["RPCS3"]="Emulation"
    ["Cemu"]="Emulation"
    ["PPSSPP"]="Emulation"
    ["DuckStation"]="Emulation"
    ["mGBA"]="Emulation"
    ["xemu"]="Emulation"
    ["ScummVM"]="Emulation"
    ["GeForce NOW"]="Cloud Gaming"
)
GAMING_ORDER=(
    "Steam"
    "Heroic Games Launcher"
    "Lutris"
    "Prism Launcher"
    "RetroArch"
    "Dolphin Emulator"
    "PCSX2"
    "RPCS3"
    "Cemu"
    "PPSSPP"
    "DuckStation"
    "mGBA"
    "xemu"
    "ScummVM"
    "GeForce NOW"
)
for label in "${GAMING_ORDER[@]}"; do
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

# One flat, checkbox-style list — no separate "which to install" vs.
# "which is default" sections. Press 'd' on a row to make it the default
# (also checking it, since an uninstalled browser can't be the default);
# unchecking the current default falls back to another checked browser,
# or "" (none) if that was the last one — you can uncheck everything,
# including Firefox.
declare -A BROWSER_TARGET=(
    ["Firefox"]="SKIP_FIREFOX"
    ["Chromium"]="FLATPAK:org.chromium.Chromium"
    ["LibreWolf"]="FLATPAK:io.gitlab.librewolf-community"
    ["Google Chrome"]="FLATPAK:com.google.Chrome"
    ["Ungoogled Chromium"]="FLATPAK:io.github.ungoogled_software.ungoogled_chromium"
    ["Waterfox"]="FLATPAK:net.waterfox.waterfox"
)
declare -A BROWSER_DESC=(
    ["Firefox"]="Mozilla's web browser"
    ["Chromium"]="Open-source web browser (the project Google Chrome is built on)"
    ["LibreWolf"]="Privacy-focused Firefox fork"
    ["Google Chrome"]="Google's web browser"
    ["Ungoogled Chromium"]="Chromium with Google integration and tracking removed"
    ["Waterfox"]="Independent, privacy-focused Firefox fork"
)
# Maps a BROWSER_ORDER label to its DEFAULT_BROWSER key.
declare -A BROWSER_KEY=(
    ["Firefox"]="firefox"
    ["Chromium"]="chromium"
    ["LibreWolf"]="librewolf"
    ["Google Chrome"]="chrome"
    ["Ungoogled Chromium"]="ungoogled-chromium"
    ["Waterfox"]="waterfox"
)
declare -A DEFAULT_BROWSER_LABEL=(
    [firefox]="Firefox"
    [chromium]="Chromium"
    [librewolf]="LibreWolf"
    [chrome]="Google Chrome"
    [ungoogled-chromium]="Ungoogled Chromium"
    [waterfox]="Waterfox"
)
BROWSER_ORDER=(
    "Firefox"
    "LibreWolf"
    "Waterfox"
    "Google Chrome"
    "Chromium"
    "Ungoogled Chromium"
)
for label in "${BROWSER_ORDER[@]}"; do
    SELECTED["$label"]=0
done
SELECTED["Firefox"]=1  # installed + default out of the box
DEFAULT_BROWSER=firefox

# Sets $1 (a BROWSER_ORDER label) as the default, checking it first if
# it isn't already (a Flatpak-gated one still needs Flathub on to count).
set_default_browser() {
    local label="$1" target="${BROWSER_TARGET[$1]}"
    case "$target" in
        FLATPAK:*) flathub_enabled || return ;;
    esac
    SELECTED["$label"]=1
    DEFAULT_BROWSER="${BROWSER_KEY[$label]}"
}
# Called after unchecking $1 (a BROWSER_ORDER label) that might have been
# the default — falls back to another checked browser, or "" (no default)
# if that was the last one.
reset_default_if_unchecked() {
    local label="$1" c
    [ "$DEFAULT_BROWSER" = "${BROWSER_KEY[$label]}" ] || return
    for c in "${BROWSER_ORDER[@]}"; do
        [ "$c" = "$label" ] && continue
        if [ "${SELECTED[$c]}" = "1" ]; then
            DEFAULT_BROWSER="${BROWSER_KEY[$c]}"
            return
        fi
    done
    DEFAULT_BROWSER=""
}

flathub_enabled() { [ "${SELECTED[$FLATHUB_LABEL]}" = "1" ]; }

HOSTNAME_VALUE="$(hostname)"
TIMEZONE_VALUE="$(timedatectl show -p Timezone --value 2>/dev/null)"
[ -z "$TIMEZONE_VALUE" ] && TIMEZONE_VALUE="UTC"

# "Locale" isn't one setting — LANG is the fallback every category (date/
# time, numbers, currency, sort order) uses unless it has its own explicit
# override. LC_*_VALUE blank = inherits LANG; the picker offers a "(same
# as Language)" option to clear an override back to that. See install.sh's
# Time & Region step for why every category has to be resent together
# whenever one changes (localectl set-locale replaces, not merges).
# 12-hour vs 24-hour isn't a category here — no glibc locale is "en_US but
# 24-hour", so there's nothing proper to pick; that's a plain on/off
# preference for the quickshell bar's own clock, set from the launcher
# (Menu > Settings > Time & Region — TimeRegion.use24Hour), not this
# installer.
_LOCALECTL_STATUS="$(localectl status 2>/dev/null)"
_extract_locale_var() { echo "$_LOCALECTL_STATUS" | sed -n "s/.*$1=\([^ ]*\).*/\1/p" | head -1; }
LANG_VALUE="$(_extract_locale_var LANG)"
[ -z "$LANG_VALUE" ] && LANG_VALUE="${LANG:-en_US.UTF-8}"
LC_NUMERIC_VALUE="$(_extract_locale_var LC_NUMERIC)"
LC_MONETARY_VALUE="$(_extract_locale_var LC_MONETARY)"
LC_COLLATE_VALUE="$(_extract_locale_var LC_COLLATE)"
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
        "Time & Region")    echo 5 ;;
        Repositories)       echo "${#REPO_ORDER[@]}" ;;
        "Option Packages")  build_grouped_rows OPTION_ROWS COMPONENT_ORDER ITEM_GROUP; echo "${#OPTION_ROWS[@]}" ;;
        Gaming)             build_grouped_rows GAMING_ROWS GAMING_ORDER GAMING_GROUP; echo "${#GAMING_ROWS[@]}" ;;
        Browser)            echo "${#BROWSER_ORDER[@]}" ;;
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

# Renders a GROUP:/ITEM: row list (built by build_grouped_rows) starting at
# row $2 — shared by every step with a grouped checkbox list (Option
# Packages, Gaming) so their layout/toggle-state rendering can't drift
# apart. One flat ORDER list still drives select/install logic; this just
# walks the nameref'd $1 rows, which interleave a "select all" row before
# each group's items. Install source (and, when relevant, why an item
# can't be toggled yet) is named inline in the description, e.g. "[Flatpak] ...".
render_grouped_list() {
    local -n _rows="$1"
    local row0="$2" col
    col="$(content_col)"
    local idx row_desc label mark target is_flatpak source_tag need_msg desc_text prefix r=$row0 group
    for idx in "${!_rows[@]}"; do
        row_desc="${_rows[$idx]}"
        if [ "${row_desc:0:6}" = "GROUP:" ]; then
            group="${row_desc#GROUP:}"
            mark="[ ]"
            [ "${GROUP_ALL_ACTIVE[$group]:-0}" = "1" ] && mark="[x]"
            cup "$r" "$col"
            clear_line_end
            if [ "$content_cursor" -eq "$idx" ]; then
                printf "%s%s> ── %s %s (select all) ──%s" "$BOLD" "$ACCENT" "$mark" "$group" "$RESET"
            else
                printf "%s  ── %s %s ──%s" "$DIM" "$mark" "$group" "$RESET"
            fi
            r=$((r+1))
            continue
        fi
        label="${row_desc#ITEM:}"
        target="${ITEM_TARGET[$label]}"
        is_flatpak=0
        case "$target" in
            FLATPAK:*)    is_flatpak=1; source_tag="[Flatpak]"; need_msg=" (needs Flatpak + Flathub)" ;;
            GFNFLATPAK:*) is_flatpak=1; source_tag="[Flatpak: GeForceNOW]"; need_msg=" (needs Flatpak)" ;;
            *)            source_tag="[DNF]" ;;
        esac

        mark="[ ]"
        [ "${SELECTED[$label]}" = "1" ] && mark="[x]"

        if [ "$is_flatpak" = "1" ] && ! flathub_enabled; then
            prefix="  "
            [ "$content_cursor" -eq "$idx" ] && prefix="> "
            cup "$r" "$col"
            printf "%s%s%s %s%s" "$DIM" "$prefix" "$mark" "$label" "$RESET"
        else
            render_row "$r" "$([ "$content_cursor" -eq "$idx" ] && echo 1 || echo 0)" "$mark $label"
        fi

        desc_text="$source_tag ${ITEM_DESC[$label]}"
        [ "$is_flatpak" = "1" ] && ! flathub_enabled && desc_text+="$need_msg"
        cup $((r+1)) $((col + 4))
        printf "%s%s%s" "$DIM" "$desc_text" "$RESET"
        r=$((r+2))
    done
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
            cup $((row0+7)) "$col"; printf "%sControls:%s" "$BOLD" "$RESET"
            cup $((row0+8)) "$col"; printf "%sTab / Shift+Tab%s  switch steps" "$ACCENT" "$RESET"
            cup $((row0+9)) "$col"; printf "%s↑ / ↓%s            move within a step" "$ACCENT" "$RESET"
            cup $((row0+10)) "$col"; printf "%sEnter / Space%s    select, toggle, or edit" "$ACCENT" "$RESET"
            cup $((row0+11)) "$col"; printf "%sCtrl+C%s           quit without changing anything" "$ACCENT" "$RESET"
            ;;
        Hostname)
            render_row "$row0" 1 "Hostname: $HOSTNAME_VALUE"
            ;;
        "Time & Region")
            render_row "$row0" "$([ "$content_cursor" -eq 0 ] && echo 1 || echo 0)" "Timezone: $TIMEZONE_VALUE"
            render_row $((row0+1)) "$([ "$content_cursor" -eq 1 ] && echo 1 || echo 0)" "Language: $LANG_VALUE"
            render_row $((row0+2)) "$([ "$content_cursor" -eq 2 ] && echo 1 || echo 0)" "Number Format: ${LC_NUMERIC_VALUE:-(same as Language)}"
            render_row $((row0+3)) "$([ "$content_cursor" -eq 3 ] && echo 1 || echo 0)" "Currency: ${LC_MONETARY_VALUE:-(same as Language)}"
            render_row $((row0+4)) "$([ "$content_cursor" -eq 4 ] && echo 1 || echo 0)" "Sort Order: ${LC_COLLATE_VALUE:-(same as Language)}"
            cup $((row0+6)) "$col"
            printf "%sNumber/Currency/Sort default to Language — pick one to override it%s" "$DIM" "$RESET"
            cup $((row0+7)) "$col"
            printf "%s12h/24h clock is set from the launcher itself (Menu > Settings > Time & Region)%s" "$DIM" "$RESET"
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
            build_grouped_rows OPTION_ROWS COMPONENT_ORDER ITEM_GROUP
            render_grouped_list OPTION_ROWS "$row0"
            ;;
        Gaming)
            build_grouped_rows GAMING_ROWS GAMING_ORDER GAMING_GROUP
            render_grouped_list GAMING_ROWS "$row0"
            ;;
        Browser)
            local i label mark is_flatpak desc_text prefix r=$row0
            for i in "${!BROWSER_ORDER[@]}"; do
                label="${BROWSER_ORDER[$i]}"
                is_flatpak=0
                case "${BROWSER_TARGET[$label]}" in
                    FLATPAK:*) is_flatpak=1 ;;
                esac

                mark="[ ]"
                [ "${SELECTED[$label]}" = "1" ] && mark="[x]"
                [ "${BROWSER_KEY[$label]}" = "$DEFAULT_BROWSER" ] && label+=" (default)"

                if [ "$is_flatpak" = "1" ] && ! flathub_enabled; then
                    prefix="  "
                    [ "$content_cursor" -eq "$i" ] && prefix="> "
                    cup "$r" "$col"
                    printf "%s%s%s %s%s" "$DIM" "$prefix" "$mark" "$label" "$RESET"
                else
                    render_row "$r" "$([ "$content_cursor" -eq "$i" ] && echo 1 || echo 0)" "$mark $label"
                fi

                desc_text="${BROWSER_DESC[${BROWSER_ORDER[$i]}]}"
                [ "$is_flatpak" = "1" ] && ! flathub_enabled && desc_text+=" (needs Flatpak + Flathub)"
                cup $((r+1)) $((col + 4))
                printf "%s%s%s" "$DIM" "$desc_text" "$RESET"
                r=$((r+2))
            done
            r=$((r+1))
            cup "$r" "$col"
            printf "%sd: make the highlighted browser the default (SUPER+SHIFT+Return, autostart)%s" "$DIM" "$RESET"
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
            cup "$r" "$col"; printf "%sGaming:%s" "$BOLD" "$RESET"; r=$((r+1))
            for label in "${GAMING_ORDER[@]}"; do
                mark="[ ]"
                [ "${SELECTED[$label]}" = "1" ] && mark="[x]"
                cup "$r" $((col+2)); printf "%s %s" "$mark" "$label"; r=$((r+1))
            done
            r=$((r+1))
            cup "$r" "$col"; printf "%sBrowser:%s" "$BOLD" "$RESET"; r=$((r+1))
            for label in "${BROWSER_ORDER[@]}"; do
                mark="[ ]"
                [ "${SELECTED[$label]}" = "1" ] && mark="[x]"
                cup "$r" $((col+2)); printf "%s %s" "$mark" "$label"; r=$((r+1))
            done
            cup "$r" $((col+2)); printf "Default: %s" "${DEFAULT_BROWSER_LABEL[$DEFAULT_BROWSER]}"; r=$((r+1))
            r=$((r+1))
            cup "$r" "$col"; printf "Hostname: %s" "$HOSTNAME_VALUE"; r=$((r+1))
            cup "$r" "$col"; printf "Timezone: %s" "$TIMEZONE_VALUE"; r=$((r+1))
            cup "$r" "$col"; printf "Language: %s" "$LANG_VALUE"; r=$((r+1))
            [ -n "$LC_NUMERIC_VALUE" ]  && { cup "$r" "$col"; printf "Number Format: %s" "$LC_NUMERIC_VALUE"; r=$((r+1)); }
            [ -n "$LC_MONETARY_VALUE" ] && { cup "$r" "$col"; printf "Currency: %s" "$LC_MONETARY_VALUE"; r=$((r+1)); }
            [ -n "$LC_COLLATE_VALUE" ]  && { cup "$r" "$col"; printf "Sort Order: %s" "$LC_COLLATE_VALUE"; r=$((r+1)); }
            r=$((r+1))
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

# ---------- searchable list picker ----------
# pick_from_list <row0> <col> <prompt> <array-name>
# A filter-as-you-type list, like edit_field but for picking one of a
# (potentially long — timezones run ~600) known set of values instead of
# typing one from memory. <array-name> is the variable name of a bash
# array (passed via nameref, not the array itself) to choose from. ENTER
# on a match commits into PICK_RESULT (return 0); ESC cancels (return 1,
# nothing changed). Own nested read loop, same as edit_field — the outer
# main loop and its own read_key don't run while this is active.
pick_from_list() {
    local row0="$1" col="$2" prompt="$3"
    local -n _pick_options="$4"
    local query="" cursor=0 i opt
    local -a matches
    local max_visible=$((LINES - row0 - 3))
    [ "$max_visible" -lt 3 ] && max_visible=3

    while true; do
        matches=()
        if [ -z "$query" ]; then
            matches=("${_pick_options[@]}")
        else
            for opt in "${_pick_options[@]}"; do
                case "${opt,,}" in
                    *"${query,,}"*) matches+=("$opt") ;;
                esac
            done
        fi
        [ "$cursor" -ge "${#matches[@]}" ] && cursor=$(( ${#matches[@]} > 0 ? ${#matches[@]} - 1 : 0 ))

        cup "$row0" "$col"; clear_line_end
        printf "%s%s:%s %s" "$BOLD" "$prompt" "$RESET" "$query"
        for ((i = 0; i < max_visible; i++)); do
            cup $((row0 + 1 + i)) "$col"; clear_line_end
            if [ "$i" -lt "${#matches[@]}" ]; then
                if [ "$i" -eq "$cursor" ]; then
                    printf "%s%s> %s%s" "$BOLD" "$ACCENT" "${matches[$i]}" "$RESET"
                else
                    printf "  %s" "${matches[$i]}"
                fi
            fi
        done
        cup $((row0 + 1 + max_visible)) "$col"; clear_line_end
        printf "%s%d/%d matches — type to filter, up/down move, enter select, esc cancel%s" \
            "$DIM" "${#matches[@]}" "${#_pick_options[@]}" "$RESET"

        cursor_show
        cup "$row0" $((col + ${#prompt} + 2 + ${#query}))
        read_key
        case "$REPLY" in
            ENTER)
                if [ "${#matches[@]}" -gt 0 ]; then
                    PICK_RESULT="${matches[$cursor]}"
                    cursor_hide
                    for ((i = 0; i <= max_visible + 1; i++)); do cup $((row0 + i)) "$col"; clear_line_end; done
                    return 0
                fi
                ;;
            ESC)
                cursor_hide
                for ((i = 0; i <= max_visible + 1; i++)); do cup $((row0 + i)) "$col"; clear_line_end; done
                return 1
                ;;
            UP)        [ "$cursor" -gt 0 ] && cursor=$((cursor - 1)) ;;
            DOWN)      [ $((cursor + 1)) -lt "${#matches[@]}" ] && cursor=$((cursor + 1)) ;;
            BACKSPACE) query="${query%?}"; cursor=0 ;;
            SPACE)     query+=" "; cursor=0 ;;
            CHAR:*)    query+="${REPLY#CHAR:}"; cursor=0 ;;
            *)         : ;;
        esac
    done
}

# Both lists are fetched once, lazily (only if the corresponding picker is
# actually opened), and cached — they don't change during a setup run.
TIMEZONE_OPTIONS=(); TIMEZONE_OPTIONS_LOADED=0
load_timezone_options() {
    [ "$TIMEZONE_OPTIONS_LOADED" = "1" ] && return
    mapfile -t TIMEZONE_OPTIONS < <(timedatectl list-timezones 2>/dev/null)
    TIMEZONE_OPTIONS_LOADED=1
}
LOCALE_OPTIONS=(); LOCALE_OPTIONS_LOADED=0
load_locale_options() {
    [ "$LOCALE_OPTIONS_LOADED" = "1" ] && return
    mapfile -t LOCALE_OPTIONS < <(locale -a 2>/dev/null)
    LOCALE_OPTIONS_LOADED=1
}
# Real glibc-derived formatting facts per locale (decimal separator,
# currency symbol — see locale-info.sh) so Number Format/Currency can show
# a human preview ("1,234.56", "£") instead of just the bare locale code,
# same idea as TimeRegion.qml's own use of this script for the launcher's
# version of this screen. 12-hour vs 24-hour isn't included — see the
# comment above TIMEZONE_VALUE's init for why that's a launcher-only
# on/off preference, not a locale pick.
declare -A LOCALE_DECIMAL LOCALE_THOUSANDS LOCALE_CURRENCY
LOCALE_INFO_LOADED=0
load_locale_info() {
    [ "$LOCALE_INFO_LOADED" = "1" ] && return
    local loc dp ts cur
    while IFS='|' read -r loc dp ts cur; do
        [ -z "$loc" ] && continue
        LOCALE_DECIMAL["$loc"]="$dp"
        LOCALE_THOUSANDS["$loc"]="$ts"
        LOCALE_CURRENCY["$loc"]="$cur"
    done < <(bash "$HERE/quickshell/scripts/locale-info.sh" 2>/dev/null)
    LOCALE_INFO_LOADED=1
}
# Recovers the raw locale code from a "<code>  —  <preview>" display string
# built by the pickers below (a plain code, or "(same as Language)", pass
# through unchanged).
locale_code_of() { echo "${1%%  —  *}"; }

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
        "Time & Region")
            if [ "$content_cursor" -eq 0 ]; then
                load_timezone_options
                if pick_from_list $((row0 + 9)) "$col" "Search timezones" TIMEZONE_OPTIONS; then
                    TIMEZONE_VALUE="$PICK_RESULT"
                fi
            elif [ "$content_cursor" -eq 1 ]; then
                load_locale_options
                if pick_from_list $((row0 + 9)) "$col" "Search locales" LOCALE_OPTIONS; then
                    LANG_VALUE="$PICK_RESULT"
                fi
            else
                # Number/Currency/Sort Order all default to Language unless
                # overridden — offer a reset option ahead of the real
                # locale list for that. Number/Currency also get a human
                # preview per entry (Sort Order has no natural one-line
                # preview, so it stays a bare code).
                load_locale_options
                load_locale_info
                local _lc_options=("(same as Language)") loc
                for loc in "${LOCALE_OPTIONS[@]}"; do
                    case "$content_cursor" in
                        2) _lc_options+=("$loc  —  1${LOCALE_THOUSANDS[$loc]:-}234${LOCALE_DECIMAL[$loc]:-.}56") ;;
                        3) if [ -n "${LOCALE_CURRENCY[$loc]:-}" ]
                           then _lc_options+=("$loc  —  ${LOCALE_CURRENCY[$loc]}1,234.56")
                           else _lc_options+=("$loc")
                           fi ;;
                        *) _lc_options+=("$loc") ;;
                    esac
                done
                if pick_from_list $((row0 + 9)) "$col" "Search locales" _lc_options; then
                    local _picked
                    _picked="$(locale_code_of "$PICK_RESULT")"
                    [ "$_picked" = "(same as Language)" ] && _picked=""
                    case "$content_cursor" in
                        2) LC_NUMERIC_VALUE="$_picked" ;;
                        3) LC_MONETARY_VALUE="$_picked" ;;
                        4) LC_COLLATE_VALUE="$_picked" ;;
                    esac
                fi
            fi
            ;;
        Repositories)
            local label="${REPO_ORDER[$content_cursor]}"
            if [ "${SELECTED[$label]}" = "1" ]; then SELECTED["$label"]=0; else SELECTED["$label"]=1; fi
            # Turning Flathub off strands any flatpak-only app selection —
            # clear those rather than leaving a checked-but-unusable state.
            if [ "$label" = "$FLATHUB_LABEL" ] && ! flathub_enabled; then
                local c
                for c in "${COMPONENT_ORDER[@]}" "${GAMING_ORDER[@]}"; do
                    case "${ITEM_TARGET[$c]}" in
                        FLATPAK:*|GFNFLATPAK:*) SELECTED["$c"]=0 ;;
                    esac
                done
                for c in "${BROWSER_ORDER[@]}"; do
                    case "${BROWSER_TARGET[$c]}" in
                        FLATPAK:*)
                            SELECTED["$c"]=0
                            reset_default_if_unchecked "$c"
                            ;;
                    esac
                done
            fi
            ;;
        "Option Packages")
            build_grouped_rows OPTION_ROWS COMPONENT_ORDER ITEM_GROUP
            local row_desc="${OPTION_ROWS[$content_cursor]}"
            if [ "${row_desc:0:6}" = "GROUP:" ]; then
                select_all_group "${row_desc#GROUP:}" COMPONENT_ORDER ITEM_GROUP
                return
            fi
            local label="${row_desc#ITEM:}"
            local target="${ITEM_TARGET[$label]}"
            case "$target" in
                FLATPAK:*|GFNFLATPAK:*) flathub_enabled || return ;;
            esac
            if [ "${SELECTED[$label]}" = "1" ]; then SELECTED["$label"]=0; else SELECTED["$label"]=1; fi
            ;;
        Gaming)
            build_grouped_rows GAMING_ROWS GAMING_ORDER GAMING_GROUP
            local row_desc="${GAMING_ROWS[$content_cursor]}"
            if [ "${row_desc:0:6}" = "GROUP:" ]; then
                select_all_group "${row_desc#GROUP:}" GAMING_ORDER GAMING_GROUP
                return
            fi
            local label="${row_desc#ITEM:}"
            local target="${ITEM_TARGET[$label]}"
            case "$target" in
                FLATPAK:*|GFNFLATPAK:*) flathub_enabled || return ;;
            esac
            if [ "${SELECTED[$label]}" = "1" ]; then SELECTED["$label"]=0; else SELECTED["$label"]=1; fi
            ;;
        Browser)
            local label="${BROWSER_ORDER[$content_cursor]}"
            case "${BROWSER_TARGET[$label]}" in
                FLATPAK:*) flathub_enabled || return ;;
            esac
            if [ "${SELECTED[$label]}" = "1" ]; then
                SELECTED["$label"]=0
                reset_default_if_unchecked "$label"
            else
                SELECTED["$label"]=1
            fi
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
        CHAR:d|CHAR:D)
            if [ "${STEPS[$current_step]}" = "Browser" ] && [ "$n" -gt 0 ]; then
                set_default_browser "${BROWSER_ORDER[$content_cursor]}"
            fi
            ;;
        *) : ;;
    esac
done

# ---------- build config and hand off to install.sh ----------

ENV_ARGS=()
FLAGS=()
FLATHUB_APPS=()
GFN_APPS=()
for label in "${REPO_ORDER[@]}" "${COMPONENT_ORDER[@]}" "${GAMING_ORDER[@]}" "${DEBUG_ORDER[@]}" "${BROWSER_ORDER[@]}"; do
    target="${REPO_TARGET[$label]:-${ITEM_TARGET[$label]:-${DEBUG_TARGET[$label]:-${BROWSER_TARGET[$label]}}}}"
    case "$target" in
        FLAG:*)
            [ "${SELECTED[$label]}" = "1" ] && FLAGS+=("${target#FLAG:}")
            ;;
        FLATPAK:*)
            [ "${SELECTED[$label]}" = "1" ] && flathub_enabled && FLATHUB_APPS+=("${target#FLATPAK:}")
            ;;
        GFNFLATPAK:*)
            [ "${SELECTED[$label]}" = "1" ] && flathub_enabled && GFN_APPS+=("${target#GFNFLATPAK:}")
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
ENV_ARGS+=("SICHOS_TIMEZONE=$TIMEZONE_VALUE" "SICHOS_LANG=$LANG_VALUE")
ENV_ARGS+=("SICHOS_LC_NUMERIC=$LC_NUMERIC_VALUE")
ENV_ARGS+=("SICHOS_LC_MONETARY=$LC_MONETARY_VALUE" "SICHOS_LC_COLLATE=$LC_COLLATE_VALUE")
ENV_ARGS+=("SKIP_SSHD=$([ "$SSHD_ENABLED" = "1" ] && echo 0 || echo 1)")
ENV_ARGS+=("SSHD_PASSWORD_AUTH=$SSHD_PASSWORD_AUTH")
[ "${#FLATHUB_APPS[@]}" -gt 0 ] && ENV_ARGS+=("FLATHUB_APPS=${FLATHUB_APPS[*]}")
[ "${#GFN_APPS[@]}" -gt 0 ] && ENV_ARGS+=("GFN_APPS=${GFN_APPS[*]}")

cleanup
trap - INT EXIT

env "${ENV_ARGS[@]}" "$HERE/install.sh" "${FLAGS[@]}"
