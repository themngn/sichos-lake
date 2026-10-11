#!/bin/bash
# Phone mirror window (scrcpy) management for quickshell's PhoneMirrorState.qml.
#   open <monitor> <bar height> <controls height> <side>
#   close | collapse <side> | expand <monitor> <side> <bar height> | key <android keycode>
# <side> is "right" (default) or "left": which monitor edge it docks to.
# expand also re-docks an expanded window to the other side (an animated
# slide across, same move as expanding).
#   audio-on | audio-off | audio-status | wake
#
# The window is docked to the right edge of <monitor>, full height between
# the bar and quickshell's controls card (PhoneMirrorPanel.qml) under it.
# Collapse slides it off the right edge -- a plain absolute move, so Hyprland
# animates it with the normal `windows` spring -- and leaves it there, still
# running, so expanding is instant.
#
# Uses `hyprctl eval` (Lua) throughout: this Hyprland build's dispatch CLI
# doesn't take classic "dispatcher arg" strings, and eval never prints a Lua
# return value -- so every window/monitor lookup goes through `hyprctl -j`.
TITLE="SichOS Phone"
GAP=6

# Nav buttons skip the lock below: each keyevent is independent and takes
# ~0.3s (adb + Android's `input` JVM startup), so locking would drop presses.
if [ "$1" = key ]; then
    exec adb shell input keyevent "$2"
fi

# Wakes the phone and, if it's locked, brings up the PIN pad ("bouncer") --
# the PIN is then typed into the mirror window (scrcpy forwards the
# keyboard). The PIN itself is deliberately never stored or typed by this
# script. The pad may look black in the mirror: type blind, then Enter.
#
# Runs as one adb shell loop on the phone, for up to ~4 min or until
# unlocked: wake it if it fell asleep, re-open the pad if it isn't
# showing, and while it is, press Shift to keep the screen on. Findings this is built on (all live, via SystemUI's dumpsys --
# screenshots can't tell the pad from a black screen):
#   - with the under-display fingerprint sensor, the first dismiss-keyguard
#     often opens the fingerprint-only "alternate bouncer", not the PIN pad;
#     a second dismiss on top of it switches to the pad. So the check is
#     isPrimaryBouncerShowingOrWillBeShowing (the pad itself) --
#     isBouncerShowing() also counts the fingerprint screen and stopped the
#     retry there;
#   - a WAKEUP key while the pad is up *closes* it, so it's only sent when
#     the screen is actually off -- an earlier "WAKEUP every 3s" keep-alive
#     kept closing the very pad it was keeping alive. Shift (keycode 59)
#     counts as user activity without touching the pad: with it the pad
#     stayed up 14s+, past the lock screen's ~5s timeout;
#   - dismiss-keyguard right after waking is sometimes ignored; a short
#     settle helps, and the loop simply retries -- fast, since none of the
#     checks are slow (dumpsys power/window/SystemUI: ~50-130ms each);
#   - only one loop at a time (flock on fd 8, held until the loop exits):
#     overlapping loops from quick collapse/expand fought each other;
#   - plain grep, not -q: -q exits at the first match and dumpsys then
#     prints "Broken pipe" errors.
#   - "is the pad up" (1/0) is reported each round into $PIN_STATE, which
#     PhoneMirrorState polls to overlay a "type your PIN" hint on the
#     otherwise-black mirror.
WAKE_PID="${XDG_RUNTIME_DIR:-/tmp}/sichos-phone-wake.pid"
PIN_STATE="${XDG_RUNTIME_DIR:-/tmp}/sichos-phone-pinpad"
# Collapse/close stop a still-running wake loop -- otherwise it keeps
# re-opening the PIN pad behind the hidden/closed mirror. Killing the local
# adb client ends the loop on the phone too (checked with `ps -A` there).
stop_wake() {
    local pid
    pid=$(cat "$WAKE_PID" 2>/dev/null) || return 0
    if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'phone-mirror.sh wake'; then
        pkill -P "$pid"  # the adb + reader pipeline
        kill "$pid"
    fi
    rm -f "$WAKE_PID"
    echo 0 > "$PIN_STATE"
}
if [ "$1" = wake ]; then
    exec 8>"${XDG_RUNTIME_DIR:-/tmp}/sichos-phone-wake.lock"
    flock -n 8 || exit 0
    echo $$ > "$WAKE_PID"
    # 8>&- (and 9>&- on get-state below): if the adb server isn't running
    # yet, this adb call forks it as a long-lived daemon that inherits every
    # open fd -- including the flock fd, so the daemon held the lock forever
    # and every later call silently timed out on it (found via /proc/locks:
    # the holder was `adb ... fork-server server`).
    adb shell '
        awake() { dumpsys power | grep "mWakefulness=Awake" >/dev/null; }
        locked() { dumpsys window | grep "isKeyguardShowing=true" >/dev/null; }
        pinpad() { dumpsys activity service com.android.systemui/.SystemUIService | grep "isPrimaryBouncerShowingOrWillBeShowing=true" >/dev/null; }
        # Checked every ~0.4s throughout (the checks themselves cost ~0.2s),
        # so the pad state reported to the "type your PIN" hint, and an
        # unlock, show up promptly. Until the pad is up each round
        # re-dismisses (the first dismiss often only reaches the
        # fingerprint screen); once it is, Shift every 6th round (~2.4s)
        # keeps the screen on.
        i=0
        while [ $i -lt 600 ]; do
            awake || { input keyevent 224; sleep 0.3; }
            locked || { echo 0; exit 0; }
            if pinpad; then
                echo 1
                [ $((i % 6)) -eq 0 ] && input keyevent 59
                sleep 0.2
            else
                echo 0
                wm dismiss-keyguard
                sleep 0.25
            fi
            i=$((i + 1))
        done' 8>&- | while read -r st; do echo "$st" > "$PIN_STATE"; done
    echo 0 > "$PIN_STATE"
    rm -f "$WAKE_PID"
    exit 0
fi

# Phone audio: a second, windowless audio-only scrcpy (scrcpy can't toggle
# audio on a running session, and restarting the mirror would flash its
# window). Detached and tracked by pidfile rather than run as a quickshell
# Process, so it survives a quickshell reload; PhoneMirrorState polls
# audio-status to notice it dying on its own (phone dropped, capture refused).
AUDIO_PID="${XDG_RUNTIME_DIR:-/tmp}/sichos-phone-audio.pid"
audio_alive() {
    local pid
    pid=$(cat "$AUDIO_PID" 2>/dev/null) || return 1
    # Guard against a recycled pid belonging to something else.
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q '^scrcpy --no-video'
}
case "$1" in
audio-status)
    audio_alive; exit
    ;;
audio-on)
    audio_alive && exit 0
    # $$ of the inner bash survives the exec, so the pidfile names scrcpy.
    setsid -f bash -c 'echo $$ > "$1"; exec scrcpy --no-video --no-control --no-window' _ "$AUDIO_PID" >/dev/null 2>&1
    exit 0
    ;;
audio-off)
    audio_alive && kill "$(cat "$AUDIO_PID")"
    rm -f "$AUDIO_PID"
    exit 0
    ;;
esac

# Serialized, not dropped: a quick collapse-then-expand must run both, in
# order. (Double opens are already guarded by PhoneMirrorState's `loading`.)
exec 9>/tmp/quickshell-phone-mirror.lock
flock -w 3 9 || exit 0

window() {
    hyprctl clients -j | jq -c --arg t "$TITLE" '[.[] | select(.class == "scrcpy" and .title == $t)][0] // empty'
}
# Logical geometry: hyprctl reports physical pixels, window coords are logical.
monitor_by() {
    hyprctl monitors -j | jq -c --arg k "$1" --arg v "$2" '.[] | select((.[$k] | tostring) == $v)
        | { x, y, w: (.width / .scale | floor), h: (.height / .scale | floor), ws: .activeWorkspace.id }'
}
# Runs a Lua statement with `w` bound to the mirror window. Never dispatch
# without that binding: a window dispatcher given a nil window silently acts
# on the focused one instead.
on_window() {
    hyprctl eval "for _, w in ipairs(hl.get_windows({ class = 'scrcpy' })) do
        if w.title == '$TITLE' then $1 end
    end" >/dev/null
}

# The phone slides (collapse/expand) without the spring bounce the rest of
# the desktop's window moves have. Hyprland has no per-window animation curve
# (the window rule's `animation` is only the style), so window moves are
# switched to a plain ease-out just for the slide and the spring is put back
# once it's done -- another window moving in that half second would get the
# ease-out too. 3.2ds = 320ms; easeOutQuint is look_and_feel.lua's curve,
# and PhoneMirrorPanel's controls card uses the same bezier and duration.
# The restore value mirrors look_and_feel.lua's `windows` leaf, which
# windowsMove otherwise inherits.
SMOOTH_MOVE="hl.animation({ leaf = 'windowsMove', enabled = true, speed = 3.2, bezier = 'easeOutQuint' })"
SPRING_MOVE="hl.animation({ leaf = 'windowsMove', enabled = true, speed = 4.79, spring = 'easy' })"
restore_spring() { hyprctl eval "$SPRING_MOVE" >/dev/null; }

case "$1" in
open)
    monitor="$2" bar="${3:-24}" controls="${4:-60}" side="${5:-right}"
    [ -n "$(window)" ] && exit 0
    # scrcpy just exits (stderr lost under exec_cmd) with no device, so say why.
    # wait-for-device, not get-state: right after the adb server starts, a
    # wireless-debugging phone takes a few seconds to be rediscovered over
    # mDNS, and get-state failed in that window even with the phone ready.
    if ! timeout 6 adb wait-for-device >/dev/null 2>&1 9>&-; then
        notify-send -a "Phone" -i phone "Phone mirror" "No device connected over adb (USB or wireless debugging)."
        exit 1  # tells PhoneMirrorState.qml to drop its loading placeholder
    fi
    # scrcpy is started at its final height (--window-height; it derives the
    # width from the phone's aspect ratio itself), so only `move` is a rule.
    # A Hyprland `size` rule used to resize it right after mapping, and
    # scrcpy sometimes didn't redraw after that: the window stayed grey
    # until the mouse moved over it. rounding/border mirror Theme.qml's
    # surfaceSquircleRadius (14) and surfaceBorder (white @ 0.10, 1px);
    # rounding_power 3 approximates the squircle's cornerSmoothing (2 is a
    # plain arc). H.265 at 16 Mbit/s: the 8 Mbit/s H.264 default looked
    # soft over wireless adb; both decode through VA-API here.
    mh=$(monitor_by name "$monitor" | jq -r .h)
    h=$(( ${mh:-1080} - bar - controls - GAP * 3 ))
    # Opens just past the monitor edge; PhoneMirrorState then runs `expand`
    # as soon as the window exists, so it slides in exactly like expanding,
    # in step with the controls card -- instead of Hyprland's pop-in, which
    # never matched the card's slide.
    if [ "$side" = left ]; then x="-window_w"; else x="monitor_w"; fi
    hyprctl eval "
    hl.exec_cmd('scrcpy --window-title=\"$TITLE\" --window-height=$h --no-audio --stay-awake --video-codec=h265 --video-bit-rate=16M', {
        float = true,
        pin = true,
        monitor = '$monitor',
        rounding = 14,
        rounding_power = 3,
        border_size = 1,
        border_color = 'rgba(ffffff1a)',
        move = '$x $((bar + GAP))',
    })" >/dev/null
    ;;
close)
    stop_wake
    on_window 'hl.dispatch(hl.dsp.window.close({ window = w }))'
    "$0" audio-off
    ;;
collapse)
    stop_wake
    win=$(window); [ -z "$win" ] && exit 0
    # Past the outer edge (right, or left when docked left) of *every*
    # monitor, not just this one's -- so it never comes to rest on a
    # neighbour. It stays pinned: off
    # every monitor it's invisible on all workspaces anyway, and expanding
    # then needs no workspace moves. Tried and dropped: parking it on a
    # hidden special workspace (Hyprland pulls an off-screen window back
    # inside the monitor on that move and plays the workspace fade), and
    # unpinning for the slide (the window blinks out for a frame).
    read -r y ww < <(jq -r '"\(.at[1]) \(.size[0])"' <<<"$win")
    if [ "$2" = left ]; then
        x=$(( $(hyprctl monitors -j | jq '[.[] | .x] | min') - ww ))
    else
        x=$(hyprctl monitors -j | jq '[.[] | .x + (.width / .scale | floor)] | max')
    fi
    # no_focus while hidden: off-screen it would otherwise keep (or later
    # regain, via focus cycling) the keyboard. Setting it also hands focus
    # to another window on its own -- confirmed live.
    on_window "hl.dispatch(hl.dsp.window.set_prop({ window = w, prop = 'no_focus', value = '1' }))
               $SMOOTH_MOVE
               hl.dispatch(hl.dsp.window.move({ window = w, x = $x, y = $y }))"
    # Then unpinned, once the slide is done: on a workspace switch Hyprland
    # carries pinned windows along and pulls an off-screen one back onto
    # the monitor -- the mirror "uncollapsed" itself. Unpinned it just stays
    # behind, off-screen, on the workspace it was collapsed on. (Unpinning
    # blinks the window for a frame; off-screen that's invisible.)
    sleep 0.45
    [ "$(window | jq -r .pinned)" = true ] && on_window 'hl.dispatch(hl.dsp.window.pin({ window = w }))'
    # A workspace switch during that slide still carried the (then still
    # pinned) window along and pulled it back on-screen (reproduced: switch
    # 0.2s in -> stuck at x=2066 on the new workspace). Now unpinned, one
    # more slide-off sticks.
    if [ "$(window | jq -r '.at[0]')" != "$x" ]; then
        on_window "hl.dispatch(hl.dsp.window.move({ window = w, x = $x, y = $y }))"
        sleep 0.45
    fi
    restore_spring
    ;;
expand)
    win=$(window); [ -z "$win" ] && exit 0
    mon=$(monitor_by name "$2"); [ -z "$mon" ] && exit 0
    read -r mx my mw < <(jq -r '"\(.x) \(.y) \(.w)"' <<<"$mon")
    ww=$(jq -r '.size[0]' <<<"$win")
    if [ "$3" = left ]; then x=$((mx + GAP)); else x=$((mx + mw - GAP - ww)); fi
    # y from the monitor too, not the window's current y, so expanding also
    # re-docks a window that got nudged.
    wy=$((my + ${4:-24} + GAP))
    # Not focused on the way back in (that warped the cursor onto it, and
    # with follow_mouse the focus wouldn't stick anyway): the PIN hint takes
    # the keyboard itself while the pad is up.
    # Re-pinned first, still off-screen: that brings it to whatever
    # workspace is showing now without the on-screen pull a workspace move
    # does, so it then slides in normally. pin is a toggle -- only when unset.
    [ "$(jq -r .pinned <<<"$win")" = true ] || on_window 'hl.dispatch(hl.dsp.window.pin({ window = w }))'
    on_window "hl.dispatch(hl.dsp.window.set_prop({ window = w, prop = 'no_focus', value = '0' }))
               $SMOOTH_MOVE
               hl.dispatch(hl.dsp.window.move({ window = w, x = $x, y = $wy }))"
    ( sleep 0.45; restore_spring ) 9>&- &
    # Backgrounded with the lock fd closed, so it doesn't hold up the next
    # command while adb runs.
    "$0" wake 9>&- &
    ;;
esac
