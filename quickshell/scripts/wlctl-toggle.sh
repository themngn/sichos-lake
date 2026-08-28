#!/bin/bash
# Ensures at most one wlctl (wifi TUI) window exists: focuses it if one is
# already open, otherwise spawns it. flock -n makes concurrent invocations
# non-blocking: if another one is mid-check, this one just gives up instead
# of queuing behind it.
#
# Uses `hyprctl eval` (Lua), not `hyprctl dispatch`: this Hyprland build's
# dispatch CLI only accepts full Lua dispatcher expressions like
# hl.dsp.window.close(), not classic "dispatcher arg" strings, so a plain
# `hyprctl dispatch focuswindow address:...` just errors out.
exec 9>/tmp/quickshell-wlctl.lock
flock -n 9 || exit 0

hyprctl eval '
local wins = hl.get_windows({ class = "wlctl" })
if #wins > 0 then
    hl.dispatch(hl.dsp.focus({ window = wins[1] }))
else
    -- confirm_os_window_close=0 is scoped to just this kitty instance (-o),
    -- so SUPER+W closes it instantly without kitty'"'"'s "still running a
    -- process" prompt, while other kitty windows keep their normal prompt.
    hl.exec_cmd("kitty -o confirm_os_window_close=0 --class wlctl -e wlctl")
end
'
