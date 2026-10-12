#!/bin/bash
# Phone mirror window (scrcpy) management for quickshell's PhoneMirrorState.qml.
#   open <monitor> <bar height> <controls height> <side>
#   close | collapse <side> | expand <monitor> <side> <bar height> [<w> <h>] | key [--longpress] <android keycode>
#   layout <monitor> <side> <bar height> <w> <h> [fast]
# <w> <h>: the window size PhoneMirrorState.geom wants (landscape when the
# phone is turned sideways); expand applies it off-screen before sliding in.
# <side> is "right" (default) or "left": which monitor edge it docks to.
# expand also re-docks an expanded window to the other side (an animated
# slide across, same move as expanding).
#   audio-on | audio-off | audio-status | wake | launch <package>
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

# Which phone: USB if plugged in (no Wi-Fi in the video path), else the one
# the sichlink daemon (~/Work/sichlink) keeps connected over wireless
# debugging. It has to be pinned: one phone often shows up as several adb
# entries -- USB plus wireless, and adb's own mDNS auto-connect adds another
# "adb-<serial>-xxx (N)._adb-tls-connect._tcp" entry each time wireless
# debugging is re-enabled -- and adb/scrcpy refuse to pick one by themselves.
# Exported for every adb/scrcpy below, including the audio-only scrcpy; the
# mirror window itself is launched by Hyprland, so it gets --serial instead.
if [ -z "$ANDROID_SERIAL" ]; then
    ANDROID_SERIAL=$(adb devices -l 2>/dev/null | awk '$2 == "device" && / usb:/ { print $1; exit }')
    # quickshell runs this with Hyprland's PATH, which has no ~/.local/bin.
    sichlink=$(command -v sichlink || echo "$HOME/.local/bin/sichlink")
    # `open` asks the daemon to connect right away (`sichlink connect`: dials
    # the phone, turns wireless debugging on, checks adb, tries every port it
    # knows) instead of trusting its cached serial, which could be up to its
    # 15s adb round stale -- the mirror used to fail right after wireless
    # debugging restarted. Everything else (keys, PIN relay) takes the cached
    # serial, ~5ms, and only falls back to connecting if there's none.
    if [ -z "$ANDROID_SERIAL" ] && [ -x "$sichlink" ]; then
        if [ "$1" = open ]; then
            ANDROID_SERIAL=$("$sichlink" connect --timeout 8 2>/dev/null 9>&- 8>&-)
        else
            ANDROID_SERIAL=$("$sichlink" adb-serial 2>/dev/null) ||
                ANDROID_SERIAL=$("$sichlink" connect --timeout 5 2>/dev/null 9>&- 8>&-)
        fi
    fi
    [ -n "$ANDROID_SERIAL" ] && export ANDROID_SERIAL
fi

# Nav buttons skip the lock below: each keyevent is independent and takes
# ~0.3s (adb + Android's `input` JVM startup), so locking would drop presses.
if [ "$1" = key ]; then
    shift  # [--longpress] <keycode>
    exec adb shell input keyevent "$@"
fi
# PhoneMirrorState's long-lived adb shells (PIN relay, power watch) go through
# here only to get the serial above.
if [ "$1" = shell ]; then
    shift
    exec adb shell "$@"
fi
# Starts an app on the phone (the launcher's phone folder) by package: its
# launcher activity, resolved on the phone. Started while the phone is still
# locked it sits behind the keyguard and is what shows once the mirror's
# wake loop unlocks it. No lock either: it doesn't touch the window.
if [ "$1" = launch ]; then
    case "$2" in ''|*[!A-Za-z0-9._]*) exit 1 ;; esac
    exec adb shell "c=\$(cmd package resolve-activity --brief -c android.intent.category.LAUNCHER '$2' | tail -n 1)
        case \$c in */*) am start -n \"\$c\" >/dev/null ;; *) monkey -p '$2' -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 ;; esac"
fi

# Wakes the phone and, if it's locked, brings up the PIN pad ("bouncer").
# If a PIN is saved (see "Saved PIN" below) it's typed once, as soon as the
# pad is up; otherwise -- or if it was rejected -- PhoneMirrorPanel's "type
# your PIN" card relays the user's keys. The pad itself shows black in the
# mirror.
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
#   - the state is reported each round into $PIN_STATE, which
#     PhoneMirrorState polls: 0 unlocked (or gave up), 2 locked and being
#     unlocked (the panel hides the lock screen behind an "Unlocking" cover),
#     1 PIN pad up waiting for the user ("type your PIN" card over the
#     otherwise-black pad), 3 the same after the saved PIN was rejected.
WAKE_PID="${XDG_RUNTIME_DIR:-/tmp}/sichos-phone-wake.pid"
PIN_STATE="${XDG_RUNTIME_DIR:-/tmp}/sichos-phone-pinpad"

# Saved PIN: the phone stays locked by its own fingerprint/PIN for anyone
# holding it; only the mirror unlocks it, by typing the PIN over adb. (Android's
# Extend Unlock/trusted devices can't do this: they keep the phone unlocked
# for anyone while the PC is near, and can't unlock an already-locked phone.)
# Kept in the login keyring (gnome-keyring, unlocked at login -- see
# autostart.lua), never in a file or on a command line: secret-tool reads it
# from stdin and the wake loop gets it on adb's stdin. On the phone it does
# end up in `input keyevent`'s argv for a moment, which only shell/root can
# see there. Saved from the "type your PIN" card ("Remember on this PC").
pin_lookup() { secret-tool lookup sichos phone-pin 2>/dev/null; }
# Set by the wake loop when it found the phone locked and the phone then got
# unlocked; close locks it again (only then -- a phone that was already
# unlocked when the mirror opened is left alone). Collapse (hide) doesn't:
# hiding it for a moment shouldn't mean unlocking it again on show.
RELOCK="${XDG_RUNTIME_DIR:-/tmp}/sichos-phone-relock"
relock() {
    [ -e "$RELOCK" ] || return 0
    rm -f "$RELOCK"
    # SLEEP, not POWER (a toggle): counts as a power-button sleep, which
    # locks at once rather than after the screen-off grace period.
    adb shell input keyevent 223 9>&- 8>&-
}
case "$1" in
pin-saved)
    [ -n "$(pin_lookup)" ]; exit
    ;;
forget-pin)
    secret-tool clear sichos phone-pin; exit 0
    ;;
store-pin)
    # PIN on stdin, typed on the Control Center's Phone page. Stored as is:
    # the phone may not even be connected, so there's nothing to check it
    # against -- a wrong one is forgotten after its first rejection by the
    # wake loop, same as a remembered one.
    read -r pin
    case "$pin" in ''|*[!0-9]*) exit 1 ;; esac
    [ "${#pin}" -ge 4 ] || exit 1
    printf '%s' "$pin" | secret-tool store --label="SichOS phone PIN" sichos phone-pin
    exit
    ;;
save-pin)
    # PIN on stdin, sent right after the user pressed Enter on the card. Only
    # kept if the phone really unlocks within a few seconds -- a typo
    # leaves the pad up and is never saved.
    read -r pin
    case "$pin" in ''|*[!0-9]*) exit 1 ;; esac
    for _ in 1 2 3 4 5 6 7 8; do
        sleep 0.5
        if adb shell dumpsys window | grep -q "isKeyguardShowing=false"; then
            printf '%s' "$pin" | secret-tool store --label="SichOS phone PIN" sichos phone-pin
            exit
        fi
    done
    exit 1
    ;;
esac
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
    # The saved PIN (if any) goes in as the first line of stdin. The phone-side
    # script is one single-quoted string: no apostrophes in its comments (one
    # broke it, and the bogus "3" it printed made the reader forget the PIN).
    pin_lookup | { cat; echo; } | adb shell '
        read -r PIN
        awake() { dumpsys power | grep "mWakefulness=Awake" >/dev/null; }
        locked() { dumpsys window | grep "isKeyguardShowing=true" >/dev/null; }
        pinpad() { dumpsys activity service com.android.systemui/.SystemUIService | grep "isPrimaryBouncerShowingOrWillBeShowing=true" >/dev/null; }
        # Checked every ~0.4s throughout (the checks themselves cost ~0.2s),
        # so the pad state reported to the "type your PIN" hint, and an
        # unlock, show up promptly. Until the pad is up each round
        # re-dismisses (the first dismiss often only reaches the
        # fingerprint screen); once it is, Shift every 6th round (~2.4s)
        # keeps the screen on.
        # The saved PIN is typed once per run, all keys in one `input` call
        # (one JVM start). A rejected one is reported as 3 and the PC side
        # forgets it: retrying on every expand would run into the
        # phone lockout after a few wrong PINs.
        i=0 was_locked=0 typed=0 st=1
        while [ $i -lt 600 ]; do
            awake || { input keyevent 224; sleep 0.3; }
            if ! locked; then
                echo 0
                [ $was_locked = 1 ] && echo unlocked
                exit 0
            fi
            was_locked=1
            if pinpad; then
                if [ -n "$PIN" ] && [ $typed = 0 ]; then
                    echo 2
                    typed=1
                    keys= s=$PIN
                    while [ -n "$s" ]; do
                        d=${s%"${s#?}"}; s=${s#?}
                        keys="$keys $((d + 7))"  # KEYCODE_0..9 = 7..16
                    done
                    input keyevent $keys 66
                    # Accepted shows first as the pad closing: the keyguard
                    # itself takes another ~1.1s (the phone plays its unlock
                    # animation) -- measured: typed at +0.08s, keyguard gone
                    # at +1.1s. So the pad closing already counts as
                    # unlocked, and the cover starts lifting while the phone
                    # finishes underneath. A wrong PIN keeps the pad up.
                    j=0
                    while [ $j -lt 10 ] && locked && pinpad; do sleep 0.1; j=$((j + 1)); done
                    if ! pinpad; then
                        echo 0
                        echo unlocked
                        exit 0
                    fi
                    st=3
                    i=$((i + 1))
                    continue
                fi
                echo $st
                [ $((i % 6)) -eq 0 ] && input keyevent 59
                sleep 0.2
            else
                echo 2
                wm dismiss-keyguard
                sleep 0.25
            fi
            i=$((i + 1))
        done' 8>&- | while read -r st; do
            case "$st" in
            unlocked) touch "$RELOCK" ;;
            3) secret-tool clear sichos phone-pin; echo 3 > "$PIN_STATE" ;;
            *) echo "$st" > "$PIN_STATE" ;;
            esac
        done
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
# Set by `open`, taken by the first `expand` (the scrcpy repaint nudge there).
FRESH="${XDG_RUNTIME_DIR:-/tmp}/sichos-phone-fresh"

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
    # Wake/unlock right away, in parallel with scrcpy starting up (~2-3s
    # until its window slides in) -- started from `expand` only, the unlock
    # began after all of that. The wake on expand still runs, and returns at
    # once if this one is still going (flock) or already done.
    "$0" wake 9>&- &
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
    touch "$FRESH"
    serial=${ANDROID_SERIAL:+--serial=\"$ANDROID_SERIAL\"}
    hyprctl eval "
    hl.exec_cmd('scrcpy $serial --window-title=\"$TITLE\" --window-height=$h --no-audio --stay-awake --video-codec=h265 --video-bit-rate=16M', {
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
    relock
    on_window 'hl.dispatch(hl.dsp.window.close({ window = w }))'
    "$0" audio-off
    ;;
layout)
    # The phone rotated (PhoneMirrorState.geom): resize the shown window and
    # re-dock it at its edge, under the bar. scrcpy letterboxes the video
    # into whatever size the window has, so this is all it takes; it may
    # also resize its window by itself on rotation, which this overrides.
    win=$(window); [ -z "$win" ] && exit 0
    [ "$(jq -r .pinned <<<"$win")" = true ] || exit 0  # collapsed: expand does it
    mon=$(monitor_by name "$2"); [ -z "$mon" ] && exit 0
    read -r mx my mw < <(jq -r '"\(.x) \(.y) \(.w)"' <<<"$mon")
    w=$5 h=$6
    if [ "$3" = left ]; then x=$((mx + GAP)); else x=$((mx + mw - GAP - w)); fi
    y=$((my + ${4:-24} + GAP))
    # fast: the corner grip being dragged (PhoneMirrorPanel), ~25 calls a
    # second -- no animation at all, so the window keeps up with the
    # pointer instead of springing after it. The release sends a normal
    # layout, which puts the spring back.
    if [ "$7" = fast ]; then
        on_window "hl.animation({ leaf = 'windowsMove', enabled = false })
                   hl.dispatch(hl.dsp.window.resize({ window = w, x = $w, y = $h }))
                   hl.dispatch(hl.dsp.window.move({ window = w, x = $x, y = $y }))"
        exit 0
    fi
    on_window "$SMOOTH_MOVE
               hl.dispatch(hl.dsp.window.resize({ window = w, x = $w, y = $h }))
               hl.dispatch(hl.dsp.window.move({ window = w, x = $x, y = $y }))"
    sleep 0.45
    restore_spring
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
    # The phone turned while it was hidden: resize while still off-screen.
    if [ -n "$5" ] && [ -n "$6" ] && [ "$(jq -r '"\(.size[0]) \(.size[1])"' <<<"$win")" != "$5 $6" ]; then
        on_window "hl.dispatch(hl.dsp.window.resize({ window = w, x = $5, y = $6 }))"
        ww=$5
    fi
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
    # First slide-in of a new connection: with the phone already awake and
    # its screen static, the window stayed plain grey (34,34,34) until
    # something changed on the phone (2 of 4 opens). The encoder only emits
    # frames on screen changes, and nothing after the first one came. A key
    # press or 1px swipe changes no pixels and a 1px window resize on this
    # side didn't help either; what works is the sichlink app's NUDGE
    # broadcast -- an invisible 1x1 overlay at alpha 1/255 for a moment
    # (~/Work/sichlink Nudge.kt; video every time in testing). It's sent
    # once the window has been up a second, so scrcpy is streaming by then.
    # Harmless without the app (the broadcast just finds no receiver).
    fresh=; [ -e "$FRESH" ] && fresh=1 && rm -f "$FRESH"
    (
        sleep 0.45
        restore_spring
        if [ -n "$fresh" ]; then
            sleep 0.6
            adb shell am broadcast -a dev.sichos.sichlink.NUDGE -n dev.sichos.sichlink/.NudgeReceiver >/dev/null 2>&1
        fi
    ) 9>&- &
    # Backgrounded with the lock fd closed, so it doesn't hold up the next
    # command while adb runs.
    "$0" wake 9>&- &
    ;;
esac
