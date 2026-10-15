#!/usr/bin/env bash
# Keeps the deployed config (~/.config/hypr, ~/.config/quickshell, ...) in
# step with this repo after the first install, and switches it between
# versions. install.sh/sichos-setup.sh are for the *first* install of a
# machine only (packages, COPRs, sudo/system steps, interactive choices);
# config updates go through this script, normally run by the git hooks in
# githooks/ (enabled by `git config core.hooksPath githooks`, which
# install.sh sets, and switched off per machine with
# `git config sichos.autodeploy false`).
#
#   ./update.sh [latest]     deploy HEAD and follow it again (unpins)
#   ./update.sh switch <rev> deploy any commit/tag/branch without checking it
#                            out, and pin it: the hooks stop following HEAD
#                            until `latest`
#   ./update.sh back         switch to the version deployed before this one
#   ./update.sh list [n]     recent commits; * = deployed, H = HEAD
#   ./update.sh status       deployed version, pin, parked conflicts, and
#                            deployed files that differ from it (drift)
#   ./update.sh mark [rev]   record <rev> (default HEAD) as deployed without
#                            copying anything (install.sh does this at the end)
#
# How it decides what to touch: it remembers the deployed commit
# (~/.local/state/sichos/deployed-rev) and diffs that against the target, so
# only files that changed between the two are looked at, a missed or failed
# run is caught up by the next one, and running it twice changes nothing.
# Files always come from the committed tree (`git show`), never the working
# copy, so uncommitted experiments are never deployed. Per changed file:
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
#   - system-level files (SDDM, Plymouth, polkit, packages, ...) need sudo,
#     which a git hook can't prompt for: they're listed, never deployed
#   - monitors.lua (per-machine) is never replaced once it exists, and
#     desktop-overrides/ only update overrides install.sh actually deployed
# A file that couldn't be written leaves the deployed-rev where it was, so the
# next run retries it. Output is also appended to
# ~/.local/state/sichos/update.log; problems (conflicts, sudo steps, a failed
# quickshell reload) also raise a desktop notification.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Hooks run with GIT_DIR/GIT_INDEX_FILE/... set for the hook's repo; git -C
# below must resolve this checkout on its own.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR
git() { command git -C "$HERE" "$@"; }

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/sichos"
STAMP="$STATE/deployed-rev"
PIN="$STATE/deployed-pinned"
HISTORY="$STATE/deploy-history"
CONFLICTS="$STATE/update-conflicts"
LOG="$STATE/update.log"
mkdir -p "$STATE"

# The quickshell reload check and notifications only make sense against the
# real session, not a test run with HOME pointed elsewhere.
REAL_HOME=0
[ "$HOME" = "$(getent passwd "$(id -u)" | cut -d: -f6)" ] && REAL_HOME=1

die() { echo "update.sh: $*" >&2; exit 1; }
resolve() { git rev-parse --verify -q "$1^{commit}"; }
short() { git rev-parse --short "$1" 2>/dev/null || echo "${1:0:7}"; }
deployed_rev() {
    local rev
    [ -s "$STAMP" ] || return 1
    rev="$(head -n1 "$STAMP")"
    resolve "$rev" >/dev/null || return 2
    echo "$rev"
}

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

set_stamp() {
    printf '%s\n' "$1" > "$STAMP.tmp" && mv -f "$STAMP.tmp" "$STAMP" || return 1
    # A ref keeps the deployed commit from being garbage-collected if history
    # is rewritten (rebase/force-push), so the next diff still has its base.
    git update-ref refs/sichos/deployed "$1" 2>/dev/null
    printf '%s %s\n' "$(date -Is)" "$1" >> "$HISTORY"
}

# repo path -> deployed path (prints nothing for non-user-level files)
dest_for() {
    case "$1" in
        hypr/*/*) ;;   # install.sh only copies hypr/'s top level
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

# repo path -> where a root step of install.sh puts it (listed, not deployed)
system_dest_for() {
    case "$1" in
        plymouth/unlock/*) echo "/usr/share/plymouth/themes/unlock/${1#plymouth/unlock/}" ;;
        polkit/*) echo "/etc/polkit-1/rules.d/${1#polkit/}" ;;
        sddm/sichos/*) echo "/usr/share/sddm/themes/sichos/${1#sddm/sichos/}" ;;
        sddm/10-theme.conf) echo "/etc/sddm.conf.d/10-theme.conf" ;;
        sddm/sysconfig-sddm) echo "/etc/sysconfig/sddm" ;;
        kernel-install.d/*) echo "/etc/kernel/install.d/${1#kernel-install.d/}" ;;
        firewalld/*) echo "/etc/firewalld/services/${1#firewalld/}" ;;
        cage/*) echo "rebuild cage (install.sh's \"==> SDDM\" step)" ;;
        wallpaper/wallpaper.jpg) echo "/usr/share/sddm/themes/sichos/background.jpg" ;;
        packages.txt) echo "install the new packages with dnf" ;;
        install.sh|sichos-setup.sh) echo "a new first-install step doesn't run on this machine by itself" ;;
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

# Re-applies install.sh's deploy-time edits of hypr files to $2 (a staged copy
# of repo file $1), detecting the optional ones from $3 (the deployed copy).
# Keep in sync with install.sh's hypr and browser steps.
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

tilde() { echo "${1/#"$HOME"/\~}"; }

declare -a CHANGED=() WARN=() SYSTEM=() ERRORS=()
QS_CHANGED=0

deploy_file() {
    local rel="$1" dest new old dir tmp mode
    dest="$(dest_for "$rel")"
    [ -z "$dest" ] && return 0
    skipped "$rel" "$dest" && return 0

    new="$WORK/new"; old="$WORK/old"
    render "$TO" "$rel" "$dest" "$new" || { ERRORS+=("can't read $rel at $(short "$TO")"); return; }
    if [ -f "$dest" ] && cmp -s "$new" "$dest"; then
        rm -f "$CONFLICTS/$rel"
        return 0
    fi
    if [ -e "$dest" ]; then
        # Not in the deployed version at all = a file of the user's own sits
        # where the repo now adds one: also local, also kept.
        if ! render "$FROM" "$rel" "$dest" "$old" || ! cmp -s "$old" "$dest"; then
            mkdir -p "$CONFLICTS/$(dirname "$rel")" && cp "$new" "$CONFLICTS/$rel"
            WARN+=("$(tilde "$dest") has local edits, kept; $(short "$TO")'s version: $(tilde "$CONFLICTS/$rel")")
            return 0
        fi
    fi

    dir="$(dirname "$dest")"
    mode=644
    [ "$(git ls-tree "$TO" -- "$rel" | cut -c1-6)" = 100755 ] && mode=755
    if mkdir -p "$dir" && tmp="$(mktemp "$dir/.$(basename "$dest").sichos.XXXXXX")"; then
        if cp "$new" "$tmp" && chmod "$mode" "$tmp" && mv -f "$tmp" "$dest"; then
            rm -f "$CONFLICTS/$rel"
            CHANGED+=("$(tilde "$dest")")
            [[ "$rel" == quickshell/*.qml || "$rel" == quickshell/*.js ]] && QS_CHANGED=1
            return 0
        fi
        rm -f "$tmp"
    fi
    ERRORS+=("couldn't write $(tilde "$dest")")
}

remove_file() {
    local rel="$1" dest old="$WORK/old"
    dest="$(dest_for "$rel")"
    { [ -z "$dest" ] || [ ! -e "$dest" ]; } && return 0
    [ "$rel" = hypr/monitors.lua ] && return 0
    rm -f "$CONFLICTS/$rel"
    if render "$FROM" "$rel" "$dest" "$old" && cmp -s "$old" "$dest"; then
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

# Drops parked versions that are no longer needed: the deployed file was
# merged by hand (now equals the parked or the target version), or the file
# is gone from the target version.
sweep_conflicts() {
    local f rel dest
    [ -d "$CONFLICTS" ] || return 0
    while IFS= read -r -d '' f; do
        rel="${f#"$CONFLICTS"/}"
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
QS_LOG="" QS_MARK=0 QS_RESULT=""
qs_log_lines() { quickshell log "$QS_LOG" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'; }
qs_watch_start() {
    QS_LOG=""
    [ "$REAL_HOME" -eq 1 ] && command -v quickshell >/dev/null && pgrep -x quickshell >/dev/null 2>&1 || return 0
    # The default config's instance (`quickshell list`), not the newest log:
    # a throwaway `quickshell -p test.qml` has one too
    local id
    id="$(quickshell list 2>/dev/null | sed -n 's/^Instance \([^:]*\):.*/\1/p' | head -n1)"
    [ -n "$id" ] && [ -f "/run/user/$(id -u)/quickshell/by-id/$id/log.qslog" ] || return 0
    QS_LOG="/run/user/$(id -u)/quickshell/by-id/$id/log.qslog"
    QS_MARK="$(qs_log_lines | wc -l)"
}
# Waits (up to ~$1 s) for the reloads since QS_MARK to settle; echoes ok,
# failed:<first error line>, or nothing if no reload happened.
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
        quickshell ipc call shell reload >/dev/null 2>&1 && r="$(qs_watch_result 8)"
    fi
    case "$r" in
        ok|"") QS_RESULT=ok ;;
        failed:*) QS_RESULT="quickshell failed to reload, still running the previous config: ${r#failed:}" ;;
    esac
}

report() {
    echo "sichos config $(date '+%F %T'): $(short "$FROM") -> $(short "$TO")${1:+ ($1)}"
    local l
    for l in "${CHANGED[@]}"; do echo "  $l"; done
    for l in "${WARN[@]}"; do echo "  ! $l"; done
    for l in "${ERRORS[@]}"; do echo "  ERROR: $l"; done
    [ -n "$QS_RESULT" ] && [ "$QS_RESULT" != ok ] && echo "  ! $QS_RESULT"
    if [ ${#SYSTEM[@]} -gt 0 ]; then
        echo "  needs a manual (sudo) step, not deployed:"
        for l in "${SYSTEM[@]}"; do echo "    $l"; done
    fi
    printf '%s\n' "${CHANGED[@]}" | grep -q 'kitty\.conf' && echo "  (restart kitty to pick up its config)"
    printf '%s\n' "${CHANGED[@]}" | grep -q 'wallpaper\.jpg' && echo "  (restart hyprpaper to show the new wallpaper)"
    [ ${#ERRORS[@]} -gt 0 ] && echo "  deployed version left at $(short "$FROM"); re-run ./update.sh to retry"
    return 0
}

# Deploys FROM -> TO (globals) and records TO as deployed unless a write failed.
apply() {
    local label="$1" status path rel problems
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
        for rel in "${added[@]}"; do
            [ "$rel" = quickshell/modules/Theme.qml ] || deploy_file "$rel"
            path="$(system_dest_for "$rel")"
            [ -n "$path" ] && SYSTEM+=("$rel -> $path")
        done
        for rel in "${deleted[@]}"; do remove_file "$rel"; done
        [ "$QS_CHANGED" -eq 1 ] && qs_check_reload
    fi

    if [ ${#ERRORS[@]} -eq 0 ] && [ "$(deployed_rev 2>/dev/null)" != "$TO" ]; then
        set_stamp "$TO" || ERRORS+=("couldn't record the deployed version")
    fi

    [ "$FROM" != "$TO" ] && report "$label" | tee -a "$LOG"
    problems=$(( ${#WARN[@]} + ${#ERRORS[@]} + ${#SYSTEM[@]} ))
    if [ -n "$QS_RESULT" ] && [ "$QS_RESULT" != ok ]; then problems=$((problems + 1)); fi
    [ "$problems" -gt 0 ] && notify_problem "$(short "$FROM") → $(short "$TO"): $problems thing(s) need a look. Details: ./update.sh status, $(tilde "$LOG")"
    [ ${#ERRORS[@]} -eq 0 ]
}

need_stamp() {
    local rc
    FROM="$(deployed_rev)"; rc=$?
    case $rc in
        0) return 0 ;;
        1) die "no deployed version recorded yet. If ~/.config already matches this checkout (e.g. right after install.sh): ./update.sh mark" ;;
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
    echo "recorded $(short "$rev") as the deployed version"
}

cmd_list() {
    local n="${1:-15}" dep head full rest m
    dep="$(deployed_rev 2>/dev/null)"; head="$(resolve HEAD)"
    git log -n "$n" --topo-order --format='%H %h %ad%d %s' --date=short "$head" ${dep:+"$dep"} |
    while read -r full rest; do
        m=" "; [ "$full" = "$dep" ] && m="*"
        h=" "; [ "$full" = "$head" ] && h="H"
        echo "$m$h $rest"
    done
}

cmd_status() {
    local dep head rel dest f n=0
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

    if [ -d "$CONFLICTS" ] && [ -n "$(find "$CONFLICTS" -type f -print -quit)" ]; then
        echo "parked versions waiting for a manual merge:"
        find "$CONFLICTS" -type f | sort | while read -r f; do
            rel="${f#"$CONFLICTS"/}"
            echo "  $(tilde "$(dest_for "$rel")")  <-  $(tilde "$f")"
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
        elif render "$dep" "$rel" "$dest" "$WORK/f" && ! cmp -s "$WORK/f" "$dest"; then
            echo "  modified  $(tilde "$dest")"; n=$((n + 1))
        fi
    done < <(git ls-tree -r -z --name-only "$dep")
    [ "$n" -eq 0 ] && echo "  none"
    return 0
}

case "${1:-latest}" in
    latest) cmd_latest ;;
    switch) cmd_switch "${2:-}" ;;
    back) cmd_back ;;
    list) cmd_list "${2:-}" ;;
    status) cmd_status ;;
    mark) cmd_mark "${2:-}" ;;
    --hook) cmd_hook ;;
    -h|--help|help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "unknown command: $1 (see ./update.sh --help)" ;;
esac
