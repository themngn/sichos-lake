#!/usr/bin/env bash
# Deploys this repo's config onto the machine and keeps it in step: the one
# place that knows where every file goes. install.sh/sichos-setup.sh are for
# the *first* install of a machine only (packages, COPRs, services,
# interactive choices) and call `update.sh install` for the config files;
# after that, the git hooks in githooks/ (enabled by `git config
# core.hooksPath githooks`, which install.sh sets; off per machine with
# `git config sichos.autodeploy false`) run `update.sh` after every commit,
# amend, pull/merge, rebase and branch switch.
#
#   ./update.sh [latest]       deploy HEAD and follow it again (unpins)
#   ./update.sh switch <rev>   deploy any commit/tag/branch without checking it
#                              out, and pin it: the hooks stop following HEAD
#                              until `latest`
#   ./update.sh back           switch to the version deployed before this one
#   ./update.sh list [n]       recent commits; * = deployed, H = HEAD
#   ./update.sh status         deployed version, pin, pending system changes,
#                              parked conflicts, drift of deployed files
#   ./update.sh system         apply system-level changes (sudo): SDDM,
#                              Plymouth, polkit, kernel-install, firewalld,
#                              root's zsh files, new packages.txt entries
#   ./update.sh install        first install: deploy every user config at HEAD
#                              (a differing existing file is kept as .bak)
#   ./update.sh mark [rev]     record <rev> (default HEAD) as deployed without
#                              copying anything
#   ./update.sh system mark [rev]   same for the system files
#   ./update.sh info [--fetch] one JSON line describing the deployed version
#                              (the Control Center's Version tile); --fetch
#                              refreshes origin first if the last fetch is
#                              over 10 minutes old
#
# How it decides what to touch: it remembers the deployed commit
# (~/.local/state/sichos/deployed-rev; system files separately in
# system-rev) and diffs that against the target, so only files that changed
# between the two are looked at, a missed or failed run is caught up by the
# next one, and running it twice changes nothing. Files always come from the
# committed tree (`git show`), never the working copy, so uncommitted
# experiments are never deployed. Per changed file:
#   - deployed copy already equal to the target version: left alone
#   - equal to the deployed version's file, or missing: replaced/created
#     atomically (temp file in the same directory + rename, so a hot-reload
#     never sees a half-written file), keeping git's exec bit
#   - anything else = local edits (a fix being tested live, a deliberate
#     local change): NEVER overwritten -- the target version is parked under
#     ~/.local/state/sichos/update-conflicts/<repo path> for a manual merge
#     and reported; the parked copy is dropped once the deployed file matches
#   - deleted/renamed in the repo: the deployed copy is removed only if it's
#     unmodified (install.sh never deletes, so removed files used to linger)
#   - install.sh's per-machine edits of deployed hypr files (--alt, --vm,
#     non-Firefox browser, the hyprlock/hyprpaper $HOME expansion) and the
#     settings the shell's own UI stores inside deployed files (kitty.conf's
#     background_opacity, hyprsunset.conf's schedule times, hypridle.conf's
#     listeners) are carried over, detected from the deployed copy itself --
#     no record of install options or settings is needed
#   - system-level files need sudo, which a git hook can't prompt for: the
#     hooks only say that `./update.sh system` has something to apply
#   - monitors.lua (per-machine) is never replaced once it exists, and
#     desktop-overrides/ (and, for `system`, root's zsh files and the
#     firewalld service) only update copies install.sh actually deployed
# A file that couldn't be written leaves the recorded version where it was,
# so the next run retries it. Output is also appended to
# ~/.local/state/sichos/update.log; problems (conflicts, pending system
# changes, a failed quickshell reload) also raise a desktop notification.
#
# Test knobs: SICHOS_SYSROOT=<dir> prefixes every system path, SICHOS_SUDO=""
# runs `system` without sudo (and skips its initramfs/firewall/boot-entry
# follow-ups, which only make sense on the real system).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Hooks run with GIT_DIR/GIT_INDEX_FILE/... set for the hook's repo; git -C
# below must resolve this checkout on its own.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR
git() { command git -C "$HERE" "$@"; }

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/sichos"
STAMP="$STATE/deployed-rev"
SYS_STAMP="$STATE/system-rev"
PIN="$STATE/deployed-pinned"
HISTORY="$STATE/deploy-history"
CONFLICTS="$STATE/update-conflicts"
LOG="$STATE/update.log"
mkdir -p "$STATE"

SYSROOT="${SICHOS_SYSROOT:-}"
SUDO="${SICHOS_SUDO-sudo}"
as_root() { if [ -n "$SUDO" ]; then "$SUDO" "$@"; else "$@"; fi; }

# The quickshell reload check and notifications only make sense against the
# real session, not a test run with HOME pointed elsewhere.
REAL_HOME=0
[ "$HOME" = "$(getent passwd "$(id -u)" | cut -d: -f6)" ] && REAL_HOME=1

die() { echo "update.sh: $*" >&2; exit 1; }
resolve() { git rev-parse --verify -q "$1^{commit}"; }
short() { git rev-parse --short "$1" 2>/dev/null || echo "${1:0:7}"; }
tilde() { echo "${1/#"$HOME"/\~}"; }
# $1 stamp file -> the recorded commit; 1 = none recorded, 2 = not in repo
read_stamp() {
    local rev
    [ -s "$1" ] || return 1
    rev="$(head -n1 "$1")"
    resolve "$rev" >/dev/null || return 2
    echo "$rev"
}
deployed_rev() { read_stamp "$STAMP"; }

notify_problem() {
    [ "$REAL_HOME" -eq 1 ] && command -v notify-send >/dev/null 2>&1 && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}${XDG_RUNTIME_DIR:-}" ] \
        && notify-send -a "SichOS update" -i dialog-warning "SichOS config update" "$1" 2>/dev/null
    return 0
}

lock() {
    # Two hooks can fire back to back (pull --rebase: post-checkout, then
    # post-rewrite); serialize instead of interleaving copies.
    exec 9>"$STATE/update.lock"
    flock -w 60 9 || die "another update is still running"
}

# $1 stamp file, $2 rev
write_stamp() {
    printf '%s\n' "$2" > "$1.tmp" && mv -f "$1.tmp" "$1" || return 1
    # A ref keeps the recorded commit from being garbage-collected if history
    # is rewritten (rebase/force-push), so the next diff still has its base.
    git update-ref "refs/sichos/$(basename "$1")" "$2" 2>/dev/null
    return 0
}
set_stamp() {
    write_stamp "$STAMP" "$1" || return 1
    printf '%s %s\n' "$(date -Is)" "$1" >> "$HISTORY"
}

# ---------------------------------------------------------------- mapping

# repo path -> deployed path (prints nothing for non-user-level files)
dest_for() {
    case "$1" in
        hypr/*/*) ;;   # only hypr/'s top level is config
        hypr/*) echo "$HOME/.config/hypr/${1#hypr/}" ;;
        quickshell/*) echo "$HOME/.config/quickshell/${1#quickshell/}" ;;
        kitty/kitty.conf) echo "$HOME/.config/kitty/kitty.conf" ;;
        qt6ct/qt6ct.conf) echo "$HOME/.config/qt6ct/qt6ct.conf" ;;
        hyprquickframe/theme.toml) echo "$HOME/.config/hyprquickframe/theme.toml" ;;
        fastfetch/*) echo "$HOME/.config/fastfetch/${1#fastfetch/}" ;;
        fontconfig/*) echo "$HOME/.config/fontconfig/${1#fontconfig/}" ;;
        nvim/init.lua) echo "$HOME/.config/nvim/init.lua" ;;
        themes/*) echo "$HOME/.local/share/themes/${1#themes/}" ;;
        desktop-overrides/*.desktop) echo "$HOME/.local/share/applications/${1#desktop-overrides/}" ;;
        autostart-overrides/*) echo "$HOME/.config/autostart/${1#autostart-overrides/}" ;;
        zsh/.zshrc) echo "$HOME/.zshrc" ;;
        zsh/.zsh_plugins.txt) echo "$HOME/.zsh_plugins.txt" ;;
        zsh/prompt.toml) echo "$HOME/.config/prompt.toml" ;;
        wallpaper/wallpaper.jpg) echo "$HOME/Pictures/wallpaper.jpg" ;;
    esac
}

# Whether a deployed path is skipped entirely: per-machine monitors.lua once
# it exists, and desktop overrides install.sh never deployed (they're
# conditional on the app being selected).
skipped() {
    local rel="$1" dest="$2"
    [ "$rel" = hypr/monitors.lua ] && [ -e "$dest" ] && return 0
    [[ "$rel" == desktop-overrides/* ]] && [ ! -e "$dest" ] && return 0
    return 1
}

# repo path -> system path. A file can map both ways (the wallpaper is also
# SDDM's background, zsh files are also root's). Keep in sync with
# install.sh's system steps.
sys_dest_for() {
    local d=""
    case "$1" in
        plymouth/unlock/*) d="/usr/share/plymouth/themes/unlock/${1#plymouth/unlock/}" ;;
        polkit/*) d="/etc/polkit-1/rules.d/${1#polkit/}" ;;
        sddm/sichos/*) d="/usr/share/sddm/themes/sichos/${1#sddm/sichos/}" ;;
        sddm/10-theme.conf) d="/etc/sddm.conf.d/10-theme.conf" ;;
        sddm/sysconfig-sddm) d="/etc/sysconfig/sddm" ;;
        kernel-install.d/*) d="/etc/kernel/install.d/${1#kernel-install.d/}" ;;
        firewalld/*) d="/etc/firewalld/services/${1#firewalld/}" ;;
        wallpaper/wallpaper.jpg) d="/usr/share/sddm/themes/sichos/background.jpg" ;;
        zsh/.zshrc) d="/root/.zshrc" ;;
        zsh/.zsh_plugins.txt) d="/root/.zsh_plugins.txt" ;;
        zsh/prompt.toml) d="/root/.config/prompt.toml" ;;
    esac
    [ -n "$d" ] && echo "$SYSROOT$d"
}
# Only updated where install.sh deployed them: root's zsh setup, and the
# LocalSend firewalld service (only installed with LocalSend + firewalld).
sys_conditional() { [[ "$1" == zsh/* || "$1" == firewalld/* ]]; }
# Whether `system` has anything to do for this repo path
sys_relevant() {
    [ -n "$(sys_dest_for "$1")" ] || [ "$1" = packages.txt ] || [[ "$1" == cage/* ]]
}

# repo paths `system` would act on between $1 and $2, one per line
sys_changes() {
    local rel
    git diff --no-renames --name-only "$1" "$2" | while IFS= read -r rel; do
        if sys_relevant "$rel"; then echo "$rel"; fi
    done
}

# Re-applies install.sh's deploy-time edits of hypr files, and settings the
# shell's UI keeps in deployed files, to $2 (a staged copy of repo file $1),
# detecting them from $3 (the deployed copy). Keep in sync with install.sh's
# hypr/browser steps and the UI code named below.
patch_like_deployed() {
    local rel="$1" file="$2" ref="$3" id
    case "$rel" in
        hypr/hyprlock.conf|hypr/hyprpaper.conf)
            sed -i "s|\$HOME|$HOME|g" "$file" ;;
        hypr/keybindings.lua)
            if [ -f "$ref" ] && grep -q '^local mainMod = "ALT"' "$ref"; then
                sed -i 's/local mainMod = "SUPER"/local mainMod = "ALT"/' "$file"
            fi ;;
        hypr/env.lua)
            if [ -f "$ref" ] && grep -q 'WLR_RENDERER' "$ref" && ! grep -q 'WLR_RENDERER' "$file"; then
                sed -i '/hl\.env("HYPRCURSOR_SIZE"/a hl.env("WLR_RENDERER", "pixman")\nhl.env("LIBGL_ALWAYS_SOFTWARE", "1")' "$file"
            fi ;;
        kitty/kitty.conf)
            # Runtime state, not config: the bar's transparency toggle
            # (toggle-transparency.py) rewrites this line in the deployed file
            if [ -f "$ref" ]; then
                id="$(grep -m1 '^background_opacity ' "$ref")"
                [ -n "$id" ] && sed -i "s|^background_opacity .*|$id|" "$file"
            fi ;;
        hypr/hyprsunset.conf)
            # The Night Light schedule: SunsetPopup.qml rewrites the
            # "time = H:MM" values in place, in file order (day, night)
            if [ -f "$ref" ]; then
                id="$(grep -oE 'time *= *[0-9]{1,2}:[0-9]{2}' "$ref" | sed 's/.*= *//' | paste -sd' ')"
                [ -n "$id" ] && awk -v times="$id" '
                    BEGIN { n = split(times, t, " ") }
                    i < n && match($0, /time *= *[0-9]+:[0-9][0-9]/) {
                        $0 = substr($0, 1, RSTART - 1) "time = " t[++i] substr($0, RSTART + RLENGTH)
                    }
                    { print }' "$file" > "$file.tmp" && mv -f "$file.tmp" "$file"
            fi ;;
        hypr/hypridle.conf)
            # Everything from the first listener block on is owned by the idle
            # panel (IdlePopup.qml regenerates it on Save): keep the deployed one
            if [ -f "$ref" ] && grep -q '^listener *{' "$ref"; then
                { sed '/^listener *{/,$d' "$file"; sed -n '/^listener *{/,$p' "$ref"; } > "$file.tmp" && mv -f "$file.tmp" "$file"
            fi ;;
        hypr/programs.lua)
            if [ -f "$ref" ]; then
                id="$(sed -n 's/^M\.browser *= "flatpak run \([^"]*\)".*/\1/p' "$ref")"
                [ -n "$id" ] && sed -i "s|M.browser     = \"firefox\"|M.browser     = \"flatpak run $id\"|" "$file"
            fi ;;
    esac
    return 0
}

# $1 rev, $2 repo path, $3 deployed path (for patch detection), $4 output file
# -> the file as it would look deployed; fails if it doesn't exist at rev
render() {
    git cat-file -e "$1:$2" 2>/dev/null || return 1
    git show "$1:$2" > "$4" || return 1
    patch_like_deployed "$2" "$4" "$3"
}

# Whether deployed file $3 is still repo file $2 as of rev $1 (scratch file
# $4): as install.sh would have left it, or as a plain copy without its
# deploy-time edits (hand-copied files, e.g. hyprlock.conf with a literal
# $HOME, seen on a second machine).
unmodified_since() {
    local rev="$1" rel="$2" dest="$3" tmp="$4"
    render "$rev" "$rel" "$dest" "$tmp" || return 1
    cmp -s "$tmp" "$dest" && return 0
    git show "$rev:$rel" > "$tmp" && cmp -s "$tmp" "$dest"
}

file_mode() { [ "$(git ls-tree "$1" -- "$2" | cut -c1-6)" = 100755 ] && echo 755 || echo 644; }

# $1 staged file, $2 dest, $3 mode [, $4 = "root"]: temp file in the same
# directory + rename, so readers only ever see the old or the new file
write_atomic() {
    local src="$1" dest="$2" mode="$3" run=() dir tmp
    [ "${4:-}" = root ] && [ -n "$SUDO" ] && run=("$SUDO")
    dir="$(dirname "$dest")"
    "${run[@]}" mkdir -p "$dir" || return 1
    tmp="$("${run[@]}" mktemp "$dir/.$(basename "$dest").sichos.XXXXXX")" || return 1
    if "${run[@]}" cp "$src" "$tmp" && "${run[@]}" chmod "$mode" "$tmp" && "${run[@]}" mv -f "$tmp" "$dest"; then
        return 0
    fi
    "${run[@]}" rm -f "$tmp"
    return 1
}

# ------------------------------------------------------------- user files

declare -a CHANGED=() WARN=() ERRORS=() NOTES=() PROBLEMS=()
QS_CHANGED=0

deploy_file() {
    local rel="$1" dest new="$WORK/new" old="$WORK/old"
    dest="$(dest_for "$rel")"
    [ -z "$dest" ] && return 0
    skipped "$rel" "$dest" && return 0

    render "$TO" "$rel" "$dest" "$new" || { ERRORS+=("can't read $rel at $(short "$TO")"); return; }
    if [ -f "$dest" ] && cmp -s "$new" "$dest"; then
        rm -f "$CONFLICTS/$rel"
        return 0
    fi
    if [ -e "$dest" ]; then
        # Not in the deployed version at all = a file of the user's own sits
        # where the repo now adds one: also local, also kept.
        if ! unmodified_since "$FROM" "$rel" "$dest" "$old"; then
            mkdir -p "$CONFLICTS/$(dirname "$rel")" && cp "$new" "$CONFLICTS/$rel"
            WARN+=("$(tilde "$dest") has local edits, kept; $(short "$TO")'s version: $(tilde "$CONFLICTS/$rel")")
            return 0
        fi
    fi
    if write_atomic "$new" "$dest" "$(file_mode "$TO" "$rel")"; then
        rm -f "$CONFLICTS/$rel"
        CHANGED+=("$(tilde "$dest")")
        [[ "$rel" == quickshell/*.qml || "$rel" == quickshell/*.js ]] && QS_CHANGED=1
    else
        ERRORS+=("couldn't write $(tilde "$dest")")
    fi
}

remove_file() {
    local rel="$1" dest old="$WORK/old"
    dest="$(dest_for "$rel")"
    { [ -z "$dest" ] || [ ! -e "$dest" ]; } && return 0
    [ "$rel" = hypr/monitors.lua ] && return 0
    rm -f "$CONFLICTS/$rel"
    if unmodified_since "$FROM" "$rel" "$dest" "$old"; then
        if rm -f "$dest"; then
            CHANGED+=("removed $(tilde "$dest")")
            [[ "$rel" == quickshell/*.qml || "$rel" == quickshell/*.js ]] && QS_CHANGED=1
        else
            ERRORS+=("couldn't remove $(tilde "$dest")")
        fi
    else
        WARN+=("$rel is gone in $(short "$TO"), but $(tilde "$dest") has local edits; kept")
    fi
}

# Drops parked user-file versions that are no longer needed: the deployed
# file was merged by hand (now equals the parked or the target version), or
# the file is gone from the target version. (system/ is swept by `system`.)
sweep_conflicts() {
    local f rel dest
    [ -d "$CONFLICTS" ] || return 0
    while IFS= read -r -d '' f; do
        rel="${f#"$CONFLICTS"/}"
        [[ "$rel" == system/* ]] && continue
        dest="$(dest_for "$rel")"
        if [ -z "$dest" ] || ! git cat-file -e "$TO:$rel" 2>/dev/null \
            || { [ -f "$dest" ] && cmp -s "$f" "$dest"; } \
            || { render "$TO" "$rel" "$dest" "$WORK/sweep" && [ -f "$dest" ] && cmp -s "$WORK/sweep" "$dest"; }; then
            rm -f "$f"
        fi
    done < <(find "$CONFLICTS" -type f -print0)
    find "$CONFLICTS" -mindepth 1 -type d -empty -delete 2>/dev/null
    return 0
}

# quickshell hot-reloads on every content change, so the copies above
# already make it reload -- possibly mid-copy, on a half-copied tree, which
# fails; the last file landing triggers one more on the complete tree. The
# log tells whether that final reload worked ("Configuration Loaded" after
# the last "Reloading configuration..."). Touching shell.qml does NOT
# reload (no content change), hence the IPC retry (ShellState's "shell"
# target) if the final reload failed.
QS_LOG="" QS_ID="" QS_MARK=0 QS_RESULT=""
qs_log_lines() { LANG=C.UTF-8 quickshell log "$QS_LOG" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'; }
qs_watch_start() {
    QS_LOG=""
    [ "$REAL_HOME" -eq 1 ] && command -v quickshell >/dev/null && pgrep -x quickshell >/dev/null 2>&1 || return 0
    # The instance running the deployed config, not the newest log: a
    # throwaway `quickshell -p test.qml` has one too. --all because plain
    # `list` only shows instances on the caller's own Wayland display, and a
    # hook run over SSH (or from an editor's terminal) has none.
    local cfg="$HOME/.config/quickshell/shell.qml"
    QS_ID="$(LANG=C.UTF-8 quickshell list --all 2>/dev/null | awk -v cfg="$cfg" '
        /^Instance / { id = $2; sub(/:$/, "", id) }
        /^ *Config path: / { sub(/^ *Config path: /, ""); if ($0 == cfg) { print id; exit } }')"
    [ -n "$QS_ID" ] && [ -f "/run/user/$(id -u)/quickshell/by-id/$QS_ID/log.qslog" ] || return 0
    QS_LOG="/run/user/$(id -u)/quickshell/by-id/$QS_ID/log.qslog"
    QS_MARK="$(qs_log_lines | wc -l)"
}
# Waits (up to ~$1 s) for the reloads since QS_MARK to settle; echoes ok,
# failed:<cause>, or nothing if no reload happened.
qs_watch_result() {
    local i last="" out seg
    for ((i = 0; i < $1 * 2; i++)); do
        sleep 0.5
        out="$(qs_log_lines | tail -n +"$((QS_MARK + 1))")"
        grep -q 'Reloading configuration' <<< "$out" || continue
        seg="$(awk '/Reloading configuration/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' <<< "$out")"
        # Settled = the last reload has a verdict and nothing new for 0.5s
        if grep -q 'Configuration Loaded' <<< "$seg"; then
            [ "$last" = "$out" ] && { echo ok; return; }
        elif grep -q 'Failed to load configuration' <<< "$seg"; then
            # "ERROR: Failed to load configuration" + "ERROR:   caused by <file>[l:c]: <why>"
            [ "$last" = "$out" ] && { echo "failed:$(grep -m1 'caused by' <<< "$seg" | sed 's/.*caused by *//')"; return; }
        fi
        last="$out"
    done
}
qs_check_reload() {
    local r
    [ -n "$QS_LOG" ] || return 0
    r="$(qs_watch_result 8)"
    if [[ "$r" == failed:* ]]; then
        QS_MARK="$(qs_log_lines | wc -l)"
        # --any-display (selects the default config; --id excludes it): the
        # instance-on-my-display filter applies to ipc too
        LANG=C.UTF-8 quickshell ipc --any-display call shell reload >/dev/null 2>&1 && r="$(qs_watch_result 8)"
    fi
    case "$r" in
        ok|"") QS_RESULT=ok ;;
        failed:*) QS_RESULT="quickshell failed to reload, still running the previous config: ${r#failed:}" ;;
    esac
}

# $1 header; prints the collected lines
report() {
    local l
    echo "$1"
    for l in "${CHANGED[@]}"; do echo "  $l"; done
    for l in "${WARN[@]}"; do echo "  ! $l"; done
    for l in "${ERRORS[@]}"; do echo "  ERROR: $l"; done
    for l in "${NOTES[@]}"; do echo "  ($l)"; done
    return 0
}

# Deploys FROM -> TO (globals) and records TO as deployed unless a write failed.
apply() {
    local label="$1" status path rel n_sys=0
    local -a added=() deleted=()
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT

    sweep_conflicts
    if [ "$FROM" != "$TO" ]; then
        while IFS= read -r -d '' status && IFS= read -r -d '' path; do
            case "$status" in
                D) deleted+=("$path") ;;
                *) added+=("$path") ;;
            esac
        done < <(git diff --no-renames --name-status -z "$FROM" "$TO")

        # Only .qml/.js changes reload quickshell; scripts are run on demand
        printf '%s\n' "${added[@]}" "${deleted[@]}" | grep -qE '^quickshell/.*\.(qml|js)$' && qs_watch_start

        # Theme.qml first: a reload that picks up modules using new tokens
        # before the new Theme floods the log with `Unable to assign [undefined]`.
        for rel in "${added[@]}"; do [ "$rel" = quickshell/modules/Theme.qml ] && deploy_file "$rel"; done
        for rel in "${added[@]}"; do [ "$rel" = quickshell/modules/Theme.qml ] || deploy_file "$rel"; done
        for rel in "${deleted[@]}"; do remove_file "$rel"; done
        [ "$QS_CHANGED" -eq 1 ] && qs_check_reload

        for rel in "${added[@]}" "${deleted[@]}"; do sys_relevant "$rel" && n_sys=$((n_sys + 1)); done
        if printf '%s\n' "${added[@]}" "${deleted[@]}" | grep -qxE 'install\.sh|sichos-setup\.sh'; then
            NOTES+=("install.sh/sichos-setup.sh changed: first-install only, nothing to do here unless it added a step this machine wants")
        fi
        printf '%s\n' "${CHANGED[@]}" | grep -q 'kitty\.conf' && NOTES+=("restart kitty to pick up its config")
        printf '%s\n' "${CHANGED[@]}" | grep -q 'wallpaper\.jpg' && NOTES+=("restart hyprpaper to show the new wallpaper")
    fi

    if [ ${#ERRORS[@]} -eq 0 ] && [ "$(deployed_rev 2>/dev/null)" != "$TO" ]; then
        set_stamp "$TO" && poke_shell || ERRORS+=("couldn't record the deployed version")
        # System files in step with FROM and none changed: still in step at TO
        if [ "$n_sys" -eq 0 ] && [ "$(read_stamp "$SYS_STAMP" 2>/dev/null)" = "$FROM" ]; then
            write_stamp "$SYS_STAMP" "$TO"
        fi
    fi
    [ ${#ERRORS[@]} -gt 0 ] && NOTES+=("deployed version left at $(short "$FROM"); re-run ./update.sh to retry")
    if [ -n "$QS_RESULT" ] && [ "$QS_RESULT" != ok ]; then
        WARN+=("$QS_RESULT"); PROBLEMS+=("$QS_RESULT")
    fi
    # Only when this run brought them in, so pending ones don't nag on every commit
    if [ "$n_sys" -gt 0 ]; then
        WARN+=("$n_sys system-level file(s) changed: run ./update.sh system (asks for sudo)")
        PROBLEMS+=("system files changed: run ./update.sh system")
    fi

    [ "$FROM" != "$TO" ] && report "sichos config $(date '+%F %T'): $(short "$FROM") -> $(short "$TO")${label:+ ($label)}" | tee -a "$LOG"
    local n_conf
    n_conf="$(printf '%s\n' "${WARN[@]}" | grep -c 'has local edits')"
    [ "$n_conf" -gt 0 ] && PROBLEMS+=("$n_conf file(s) with local edits kept, new version parked (./update.sh status)")
    [ ${#ERRORS[@]} -gt 0 ] && PROBLEMS+=("${#ERRORS[@]} file(s) couldn't be written, will retry")
    [ ${#PROBLEMS[@]} -gt 0 ] && notify_problem "$(short "$FROM") → $(short "$TO"): $(printf '%s; ' "${PROBLEMS[@]}" | sed 's/; $//')"
    [ ${#ERRORS[@]} -eq 0 ]
}

need_stamp() {
    local rc
    FROM="$(deployed_rev)"; rc=$?
    case $rc in
        0) return 0 ;;
        1) die "no deployed version recorded yet. If ~/.config already matches this checkout: ./update.sh mark (or ./update.sh install for a full deploy)" ;;
        *) die "the recorded deployed version $(head -n1 "$STAMP") isn't in this repo. Check ./update.sh status, then ./update.sh mark <the rev it really is>" ;;
    esac
}

cmd_latest() {
    lock; need_stamp
    TO="$(resolve HEAD)" || die "no HEAD"
    rm -f "$PIN"
    apply "latest"
}

cmd_switch() {
    [ -n "${1:-}" ] || die "usage: ./update.sh switch <commit|tag|branch>"
    lock; need_stamp
    TO="$(resolve "$1")" || die "unknown revision: $1"
    if [ "$TO" = "$(resolve HEAD)" ]; then rm -f "$PIN"; else printf '%s\n' "$1" > "$PIN"; fi
    apply "switch $([[ "$1" =~ ^[0-9a-f]{40}$ ]] && short "$1" || echo "$1")" || return 1
    [ -f "$PIN" ] && echo "  pinned: hooks won't follow HEAD until ./update.sh latest"
    return 0
}

cmd_back() {
    local cur prev
    cur="$(deployed_rev)" || die "no deployed version recorded"
    # The newest history entry that isn't the current version
    prev="$(tac "$HISTORY" 2>/dev/null | awk -v cur="$cur" '$2 != cur { print $2; exit }')"
    [ -n "$prev" ] || die "no earlier deployed version in $(tilde "$HISTORY")"
    cmd_switch "$prev"
}

# Called by githooks/sichos-deploy. Never fails the git command.
cmd_hook() {
    if [ -f "$PIN" ]; then
        echo "sichos: config pinned to $(cat "$PIN"); not following HEAD (./update.sh latest to follow it again)"
        return 0
    fi
    if ! deployed_rev >/dev/null; then
        echo "sichos: no deployed version recorded, nothing auto-deployed (see ./update.sh status)"
        return 0
    fi
    cmd_latest
    return 0
}

cmd_mark() {
    local rev
    lock
    rev="$(resolve "${1:-HEAD}")" || die "unknown revision: ${1:-HEAD}"
    set_stamp "$rev" || die "couldn't write $STAMP"
    rm -f "$PIN"
    poke_shell
    echo "recorded $(short "$rev") as the deployed version"
}

# First install: every user config at HEAD, whatever is deployed. A differing
# existing file is kept as <name>.bak (it's not ours to merge yet), but the
# carry-overs still apply, so re-running it keeps --alt, Night Light times...
cmd_install() {
    local rel dest n=0 dirty
    lock
    TO="$(resolve HEAD)" || die "no HEAD"
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    while IFS= read -r -d '' rel; do
        dest="$(dest_for "$rel")"
        [ -z "$dest" ] && continue
        # Optional per-app overrides are install.sh's call (only for selected apps)
        [[ "$rel" == desktop-overrides/* ]] && continue
        skipped "$rel" "$dest" && continue
        render "$TO" "$rel" "$dest" "$WORK/new" || { ERRORS+=("can't read $rel"); continue; }
        [ -f "$dest" ] && cmp -s "$WORK/new" "$dest" && continue
        if [ -e "$dest" ]; then
            cp -p "$dest" "$dest.bak" && echo "    backed up existing $(tilde "$dest") as $(basename "$dest").bak"
        fi
        if write_atomic "$WORK/new" "$dest" "$(file_mode "$TO" "$rel")"; then
            rm -f "$CONFLICTS/$rel"; n=$((n + 1))
        else
            ERRORS+=("couldn't write $(tilde "$dest")")
        fi
    done < <(git ls-tree -r -z --name-only "$TO")
    echo "    $n file(s) installed from $(short "$TO")"
    dirty="$(git status --porcelain -- hypr quickshell kitty qt6ct hyprquickframe fastfetch fontconfig nvim themes autostart-overrides zsh wallpaper)"
    [ -n "$dirty" ] && echo "    note: uncommitted changes in the repo aren't deployed (commit them; the hook deploys them)"
    if [ ${#ERRORS[@]} -gt 0 ]; then
        printf '    ERROR: %s\n' "${ERRORS[@]}"
        return 1
    fi
    set_stamp "$TO" && rm -f "$PIN"
}

# ----------------------------------------------------------- system files

declare -A SYS_ACTIONS=()

# $1 dest -> its content into $2 (root-readable files too); 1 = doesn't exist
sys_read() {
    as_root test -e "$1" || return 1
    as_root cat "$1" > "$2"
}

sys_deploy_file() {
    local rel="$1" dest new="$WORK/new" old="$WORK/old" cur="$WORK/cur"
    dest="$(sys_dest_for "$rel")"
    [ -z "$dest" ] && return 0
    if sys_read "$dest" "$cur"; then
        git show "$TO:$rel" > "$new" || { ERRORS+=("can't read $rel at $(short "$TO")"); return; }
        if cmp -s "$new" "$cur"; then rm -f "$CONFLICTS/system/$rel"; return 0; fi
        if ! git show "$FROM:$rel" > "$old" 2>/dev/null || ! cmp -s "$old" "$cur"; then
            mkdir -p "$CONFLICTS/system/$(dirname "$rel")" && cp "$new" "$CONFLICTS/system/$rel"
            WARN+=("$dest has local edits, kept; $(short "$TO")'s version: $(tilde "$CONFLICTS/system/$rel")")
            return 0
        fi
    else
        sys_conditional "$rel" && return 0
        git show "$TO:$rel" > "$new" || { ERRORS+=("can't read $rel at $(short "$TO")"); return; }
    fi
    if write_atomic "$new" "$dest" "$(file_mode "$TO" "$rel")" root; then
        rm -f "$CONFLICTS/system/$rel"
        CHANGED+=("$dest")
        case "$rel" in
            plymouth/*) SYS_ACTIONS[plymouth]=1 ;;
            kernel-install.d/*) SYS_ACTIONS[bootentries]=1 ;;
            firewalld/*) SYS_ACTIONS[firewalld]=1 ;;
            sddm/*|wallpaper/*) SYS_ACTIONS[sddm]=1 ;;
        esac
    else
        ERRORS+=("couldn't write $dest")
    fi
}

sys_remove_file() {
    local rel="$1" dest old="$WORK/old" cur="$WORK/cur"
    dest="$(sys_dest_for "$rel")"
    [ -z "$dest" ] && return 0
    rm -f "$CONFLICTS/system/$rel"
    sys_read "$dest" "$cur" || return 0
    if git show "$FROM:$rel" > "$old" 2>/dev/null && cmp -s "$old" "$cur"; then
        if as_root rm -f "$dest"; then CHANGED+=("removed $dest"); else ERRORS+=("couldn't remove $dest"); fi
    else
        WARN+=("$rel is gone in $(short "$TO"), but $dest has local edits; kept")
    fi
}

# packages.txt entries (first word of each non-comment line) at $1
packages_at() {
    git show "$1:packages.txt" 2>/dev/null | grep -v '^\s*#' | grep -v '^\s*$' | awk '{ print $1 }' | sort -u
}

sys_packages() {
    local -a new=() gone=()
    mapfile -t new < <(comm -13 <(packages_at "$FROM") <(packages_at "$TO"))
    mapfile -t gone < <(comm -23 <(packages_at "$FROM") <(packages_at "$TO"))
    [ ${#gone[@]} -gt 0 ] && NOTES+=("dropped from packages.txt, left installed: ${gone[*]}")
    [ ${#new[@]} -eq 0 ] && return 0
    if [ -n "$SYSROOT" ]; then
        NOTES+=("would install: ${new[*]}"); return 0
    fi
    if as_root dnf install -y "${new[@]}"; then
        CHANGED+=("installed packages: ${new[*]}")
    else
        ERRORS+=("dnf install ${new[*]} failed")
    fi
}

# The follow-ups install.sh does after copying each group
sys_followups() {
    local real=1
    { [ -n "$SYSROOT" ] || [ -z "$SUDO" ]; } && real=0
    if [ -n "${SYS_ACTIONS[plymouth]:-}" ]; then
        if [ "$real" -eq 0 ]; then NOTES+=("would rebuild the initramfs (plymouth-set-default-theme -R unlock)")
        elif as_root plymouth-set-default-theme -R unlock; then CHANGED+=("Plymouth theme applied, initramfs rebuilt")
        else ERRORS+=("plymouth-set-default-theme -R unlock failed"); fi
    fi
    if [ -n "${SYS_ACTIONS[bootentries]:-}" ]; then
        # Same retitle as install.sh's GRUB branding step (see its comment
        # for why the glob has to expand inside the root shell)
        if [ "$real" -eq 0 ]; then NOTES+=("would retitle the existing boot entries")
        else
            # shellcheck disable=SC2016
            as_root bash -c '. /etc/os-release; for e in /boot/loader/entries/*.conf; do [ -f "$e" ] && sed -i "s/^title ${NAME} /title SichOS /" "$e"; done' \
                && CHANGED+=("boot entries retitled") || ERRORS+=("retitling boot entries failed")
        fi
    fi
    if [ -n "${SYS_ACTIONS[firewalld]:-}" ] && [ "$real" -eq 1 ] && systemctl is-active --quiet firewalld; then
        as_root firewall-cmd --reload >/dev/null && CHANGED+=("firewalld reloaded") || ERRORS+=("firewall-cmd --reload failed")
    fi
    [ -n "${SYS_ACTIONS[sddm]:-}" ] && NOTES+=("the login screen picks this up at the next login (or sudo systemctl restart sddm)")
    return 0
}

cmd_system() {
    local rel status path rc
    local -a added=() deleted=()
    if [ "${1:-}" = mark ]; then
        lock
        rel="$(resolve "${2:-HEAD}")" || die "unknown revision: ${2:-HEAD}"
        write_stamp "$SYS_STAMP" "$rel" || die "couldn't write $SYS_STAMP"
        echo "recorded $(short "$rel") as the system files' version"
        return 0
    fi
    lock
    need_stamp; TO="$FROM"   # system files follow the deployed config version
    FROM="$(read_stamp "$SYS_STAMP")"; rc=$?
    [ $rc -eq 1 ] && die "no system version recorded yet. If the system files match a commit (e.g. right after install.sh): ./update.sh system mark [rev]"
    [ $rc -ne 0 ] && die "the recorded system version isn't in this repo: ./update.sh system mark <the rev it really is>"
    if [ -z "$(sys_changes "$FROM" "$TO")" ]; then
        # Nothing system-level between the two: just move the version along
        [ "$FROM" = "$TO" ] || write_stamp "$SYS_STAMP" "$TO"
        echo "system files are up to date ($(short "$TO"))"; return 0
    fi
    if [ -n "$SUDO" ]; then "$SUDO" -v || die "needs sudo"; fi
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

    while IFS= read -r -d '' status && IFS= read -r -d '' path; do
        case "$status" in D) deleted+=("$path") ;; *) added+=("$path") ;; esac
    done < <(git diff --no-renames --name-status -z "$FROM" "$TO")
    for rel in "${added[@]}"; do sys_deploy_file "$rel"; done
    for rel in "${deleted[@]}"; do sys_remove_file "$rel"; done
    printf '%s\n' "${added[@]}" "${deleted[@]}" | grep -qx packages.txt && sys_packages
    printf '%s\n' "${added[@]}" "${deleted[@]}" | grep -q '^cage/' \
        && NOTES+=("cage/ changed: the patched cage comes from the mdukhota/test1 COPR -- rebuild it there")
    sys_followups

    if [ ${#ERRORS[@]} -eq 0 ]; then
        write_stamp "$SYS_STAMP" "$TO" && poke_shell || ERRORS+=("couldn't record the system version")
    fi
    [ ${#ERRORS[@]} -gt 0 ] && NOTES+=("system version left at $(short "$FROM"); re-run ./update.sh system to retry")
    report "sichos system $(date '+%F %T'): $(short "$FROM") -> $(short "$TO")" | tee -a "$LOG"
    [ ${#ERRORS[@]} -eq 0 ]
}

# ------------------------------------------------------------- read-only

# Tells a running Control Center to re-read `info` (SichosVersion.qml): its
# FileViews can't see the stamps change, they're replaced by rename.
poke_shell() {
    [ "$REAL_HOME" -eq 1 ] && command -v quickshell >/dev/null || return 0
    (LANG=C.UTF-8 timeout 3 quickshell ipc --any-display call sichosversion refresh >/dev/null 2>&1 &)
    return 0
}

cmd_info() {
    local head dep sys branch upstream ab="" ahead="" behind="" fetched=0 n_conf=0 sys_pending="" hooks=1 deployed_at="" tag=""
    local fh
    fh="$(git rev-parse --git-path FETCH_HEAD)"; [[ "$fh" = /* ]] || fh="$HERE/$fh"
    if [ "${1:-}" = --fetch ] && git rev-parse -q --verify '@{u}' >/dev/null; then
        if [ ! -f "$fh" ] || [ $(( $(date +%s) - $(stat -c %Y "$fh") )) -gt 600 ]; then
            # Background-safe: no hooks run on fetch, and a dead network just times out
            GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5" \
                timeout 20 command git -C "$HERE" fetch -q 2>/dev/null
        fi
    fi
    head="$(resolve HEAD)"
    dep="$(deployed_rev 2>/dev/null)"
    sys="$(read_stamp "$SYS_STAMP" 2>/dev/null)"
    branch="$(git symbolic-ref --short -q HEAD)"
    upstream="$(git rev-parse --abbrev-ref -q '@{u}' 2>/dev/null)"
    if [ -n "$upstream" ]; then
        ab="$(git rev-list --left-right --count "HEAD...@{u}" 2>/dev/null)"
        ahead="${ab%%[[:space:]]*}"; behind="${ab##*[[:space:]]}"
    fi
    [ -f "$fh" ] && fetched="$(stat -c %Y "$fh")"
    [ -d "$CONFLICTS" ] && n_conf="$(find "$CONFLICTS" -type f | wc -l)"
    [ -n "$sys" ] && [ -n "$dep" ] && sys_pending="$(sys_changes "$sys" "$dep" | wc -l)"
    { [ "$(git config core.hooksPath)" = githooks ] && [ "$(git config --bool sichos.autodeploy)" != false ]; } || hooks=0
    [ -n "$dep" ] && deployed_at="$(awk -v r="$dep" '$2 == r { t = $1 } END { print t }' "$HISTORY" 2>/dev/null)"
    [ -n "$dep" ] && tag="$(git describe --tags --exact-match "$dep" 2>/dev/null)"
    python3 -c 'import json, sys; a = sys.argv[1:]; print(json.dumps(dict(zip(a[0::2], a[1::2]))))' \
        repo "$HERE" host "$(hostname)" branch "$branch" \
        head "$(short "$head")" head_subject "$(git log -1 --format=%s "$head")" \
        deployed "${dep:+$(short "$dep")}" \
        deployed_subject "${dep:+$(git log -1 --format=%s "$dep")}" \
        deployed_date "${dep:+$(git log -1 --format=%cI "$dep")}" \
        deployed_at "$deployed_at" tag "$tag" \
        deployed_branches "${dep:+$(git branch --format='%(refname:short)' --contains "$dep" 2>/dev/null | paste -sd' ')}" \
        pinned "$(cat "$PIN" 2>/dev/null)" \
        behind_head "${dep:+$(git rev-list --count "$dep..$head" 2>/dev/null)}" \
        upstream "$upstream" ahead "$ahead" behind "$behind" fetched "$fetched" \
        dirty "$(git status --porcelain 2>/dev/null | wc -l)" \
        conflicts "$n_conf" system "${sys:+$(short "$sys")}" system_pending "$sys_pending" hooks "$hooks"
}

cmd_list() {
    local n="${1:-15}" dep head full rest m h
    dep="$(deployed_rev 2>/dev/null)"; head="$(resolve HEAD)"
    git log -n "$n" --topo-order --format='%H %h %ad%d %s' --date=short "$head" ${dep:+"$dep"} |
    while read -r full rest; do
        m=" "; [ "$full" = "$dep" ] && m="*"
        h=" "; [ "$full" = "$head" ] && h="H"
        echo "$m$h $rest"
    done
}

cmd_status() {
    local dep sys head rel dest f n=0
    head="$(resolve HEAD)"
    if dep="$(deployed_rev)"; then
        echo "deployed: $(git log -1 --format='%h %ad %s' --date=short "$dep")"
    else
        dep=""
        echo "deployed: unknown (./update.sh mark <rev> once ~/.config matches a commit)"
    fi
    echo "HEAD:     $(git log -1 --format='%h %ad %s' --date=short "$head")"
    if [ -f "$PIN" ]; then echo "pinned to $(cat "$PIN") (hooks don't follow HEAD)"
    elif [ -n "$dep" ] && [ "$dep" != "$head" ]; then echo "not at HEAD (./update.sh to deploy it)"; fi
    [ "$(git config core.hooksPath)" = githooks ] || echo "auto-deploy hooks: not enabled (git config core.hooksPath githooks)"
    [ "$(git config --bool sichos.autodeploy)" = false ] && echo "auto-deploy hooks: off (git config sichos.autodeploy)"

    if sys="$(read_stamp "$SYS_STAMP")"; then
        if [ -n "$dep" ] && [ "$sys" != "$dep" ]; then
            f="$(sys_changes "$sys" "$dep")"
            if [ -n "$f" ]; then
                echo "system files at $(short "$sys"); changed since:"
                sed 's/^/  /' <<< "$f"
                echo "  -> ./update.sh system"
            fi
        fi
    else
        echo "system files: no version recorded (./update.sh system mark <rev> once they match a commit)"
    fi

    if [ -d "$CONFLICTS" ] && [ -n "$(find "$CONFLICTS" -type f -print -quit)" ]; then
        echo "parked versions waiting for a manual merge:"
        find "$CONFLICTS" -type f | sort | while read -r f; do
            rel="${f#"$CONFLICTS"/}"
            if [[ "$rel" == system/* ]]; then dest="$(sys_dest_for "${rel#system/}")"; else dest="$(tilde "$(dest_for "$rel")")"; fi
            echo "  $dest  <-  $(tilde "$f")"
        done
    fi

    [ -n "$dep" ] || return 0
    WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
    echo "deployed files that differ from $(short "$dep"):"
    while IFS= read -r -d '' rel; do
        dest="$(dest_for "$rel")"
        [ -z "$dest" ] && continue
        skipped "$rel" "$dest" && continue
        if [ ! -e "$dest" ]; then
            echo "  missing   $(tilde "$dest")"; n=$((n + 1))
        elif git cat-file -e "$dep:$rel" 2>/dev/null && ! unmodified_since "$dep" "$rel" "$dest" "$WORK/f"; then
            echo "  modified  $(tilde "$dest")"; n=$((n + 1))
        fi
    done < <(git ls-tree -r -z --name-only "$dep")
    [ "$n" -eq 0 ] && echo "  none"
    return 0
}

# Lets the Version tile find this checkout (the deployed config doesn't
# know where its repo lives). Main checkout only, never a worktree's copy.
if [ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ] \
    && [ "$(cat "$STATE/repo" 2>/dev/null)" != "$HERE" ]; then
    printf '%s\n' "$HERE" > "$STATE/repo"
fi

case "${1:-latest}" in
    latest) cmd_latest ;;
    switch) cmd_switch "${2:-}" ;;
    back) cmd_back ;;
    list) cmd_list "${2:-}" ;;
    status) cmd_status ;;
    system) cmd_system "${2:-}" "${3:-}" ;;
    install) cmd_install ;;
    info) cmd_info "${2:-}" ;;
    mark) cmd_mark "${2:-}" ;;
    --hook) cmd_hook ;;
    -h|--help|help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "unknown command: $1 (see ./update.sh --help)" ;;
esac
