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
TIMEOUT=120
INTERVAL=3
elapsed=0

while [ "$elapsed" -lt "$TIMEOUT" ]; do
    hyprctl eval 'hl.dispatch(hl.dsp.dpms("on"))' >/dev/null 2>&1
    sleep "$INTERVAL"
    elapsed=$((elapsed + INTERVAL))
    still_off=$(hyprctl monitors all -j 2>/dev/null | jq '[.[] | select(.dpmsStatus == false)] | length')
    if [ "$still_off" = "0" ]; then
        echo "dpms-restore-after-resume: restored after ${elapsed}s"
        exit 0
    fi
done

echo "dpms-restore-after-resume: still off after ${TIMEOUT}s, giving up"
