#!/usr/bin/env bash
# Invoked as hypridle.conf's general.after_sleep_cmd. A single hyprctl eval
# 'hl.dispatch(hl.dsp.dpms("on"))' -- even retried a handful of times a
# couple seconds apart -- isn't reliable right after a *real* suspend/
# resume: confirmed live (black-screen incident, 2026-09-07) that
# dpmsStatus can stay stuck false well past a minute after resume even
# though the command keeps returning "ok" and nothing else about the
# monitor looks wrong (not disabled, brightness/workspace state normal).
# Retries at resume+0s/+1s/+3s all failed; an identical retry at +83s,
# with nothing else touching the monitor in between, worked. So this polls
# and keeps nudging dpms on until every monitor actually confirms it, or
# gives up after a generous timeout, instead of guessing a fixed schedule.
#
# The dpms-on command itself is still only re-issued every 3s (REISSUE_TICKS
# below) -- a tighter reissue cadence is exactly what failed in the
# 2026-09-07 incident, so that part is untouched. What's new (2026-09-10) is
# that a resume was measured (via `journalctl --user -u hypridle.service`)
# taking a full two 3s cycles (6s) just to *confirm* success, because the
# old loop only checked dpmsStatus once per reissue -- a success landing at
# e.g. t=3.2s wasn't noticed until the t=6s check. Status is now polled
# separately, every POLL_INTERVAL (cheap, read-only, no state change), so a
# success is noticed within a fraction of a second of actually happening,
# without reissuing the command any more often than before.
#
# CRITICAL (found live, 2026-09-10): 'hl.dsp.dpms("on")' is a *toggle*, not
# a set-to-on command -- confirmed by direct test: calling it while
# dpmsStatus was already true flipped it to false, and calling it again
# flipped it back to true. The loop below used to check dpmsStatus *after*
# deciding whether to reissue, so on a resume where the display came back
# on its own within the first 3s reissue window, the next scheduled reissue
# would hit an already-on display and toggle it back OFF -- then the
# following reissue would toggle it back on. This produced exactly the
# "works for a second, then fades to black, then recovers" symptom a user
# reported, on a cadence matching REISSUE_TICKS. The status check now runs
# BEFORE the reissue decision each tick, so once dpmsStatus is confirmed
# true the loop exits immediately and dpms("on") is never called again --
# it should now be structurally impossible for this loop to toggle an
# already-correct display back off. (A narrow race remains: if dpms flips
# on in the sub-POLL_INTERVAL gap between a check and a same-tick reissue,
# that reissue would still toggle it off -- far smaller window than before,
# not eliminated.)
#
# Also fires the same wallpaper IPC call autostart.lua uses at login,
# backgrounded, before the loop starts: on some real resumes (confirmed
# live, 2026-09-10 -- mouse cursor visibly moving on an otherwise black
# screen before the desktop content appeared) the panel/DRM side is
# already back (the hardware cursor plane doesn't need a full scene
# composite) but hyprpaper's background layer surface doesn't repaint on
# its own, matching widely-reported Hyprland/hyprpaper behavior where a
# layer surface needs something to force a redraw after suspend/resume.
# This is a pragmatic nudge, not a root-caused fix -- this build doesn't
# log layer/damage activity, so there was nothing to confirm the exact
# mechanism against. Harmless no-op on resumes where it wasn't needed.
# Kept inside this script (backgrounded with plain bash '&', not hypridle's
# own command string) rather than chained into hypridle.conf's
# after_sleep_cmd: confirmed live that hypridle only pipes a *plain*
# command's stdout into its own journal log -- handing it a string
# containing a shell '&' instead made it log a bare "Process Created with
# pid X" and never anything else for that invocation, so there was no way
# to tell whether it even finished. hypridle.conf must stay pointed at this
# single script path.
hyprctl hyprpaper wallpaper ",$HOME/Pictures/wallpaper.jpg" >/dev/null 2>&1 &

# Before falling back to the blind poll/retry loop below, give the kernel a
# brief, bounded chance to say "the GPU's actually back" on its own: amdgpu's
# own PM timing (measured live, 2026-09-10, via pm_print_times) shows its
# pci_pm_resume callback taking ~547ms, and Hyprland's aquamarine backend
# reacts to a DRM subsystem "change" event at that point (confirmed via
# hyprland.log logging "Connector eDP-1 enabledState changed ... ->true"
# right when this fires) -- so waiting for that event, instead of firing the
# first dpms-on attempt blind at t=0 (which the loop below already knows
# reliably fails), should let the common/fast case land closer to that true
# ~0.6s floor instead of waiting out a fixed poll interval. NOT confirmed to
# reliably predict dpms readiness specifically, though -- the 2026-09-07
# incident showed dpms could stay stuck long after the connector was clearly
# already reconnected, so this is strictly a head start, capped short, with
# the proven poll/retry loop below still running unconditionally after it
# either way as the real safety net.
timeout 2 udevadm monitor --udev --subsystem-match=drm 2>/dev/null | grep -q -m1 "change"

TIMEOUT=120        # seconds; give up and leave dpms as-is past this point
POLL_INTERVAL=0.5  # seconds between dpmsStatus checks
REISSUE_TICKS=6    # re-issue dpms-on every N polls (6 * 0.5s = 3s, unchanged)
max_ticks=$(( TIMEOUT * 2 ))
tick=0

while [ "$tick" -lt "$max_ticks" ]; do
    still_off=$(hyprctl monitors all -j 2>/dev/null | jq '[.[] | select(.dpmsStatus == false)] | length')
    if [ "$still_off" = "0" ]; then
        echo "dpms-restore-after-resume: restored after $(( tick / 2 )).$(( (tick % 2) * 5 ))s"
        exit 0
    fi
    if [ $(( tick % REISSUE_TICKS )) -eq 0 ]; then
        hyprctl eval 'hl.dispatch(hl.dsp.dpms("on"))' >/dev/null 2>&1
    fi
    sleep "$POLL_INTERVAL"
    tick=$((tick + 1))
done

echo "dpms-restore-after-resume: still off after ${TIMEOUT}s, giving up"
