#!/bin/bash
# Emoji picker, SUPER+PERIOD (keybindings.lua) -- same fuzzel --dmenu shape as
# the SUPER+SHIFT+V clipboard picker. The list comes from unicode-emoji's
# emoji-test.txt (packages.txt) rather than a list vendored here, so it tracks
# whatever Unicode version Fedora ships. Only "fully-qualified" entries are
# shown: the minimally-/un-qualified ones are the same emoji minus the
# variation selector, and would just be visual duplicates.
#
# The pick is copied *and* typed (wtype): typing covers the common "insert it
# here" case, the clipboard copy covers apps where wtype's virtual-keyboard
# input doesn't land (XWayland windows).
DATA=/usr/share/unicode/emoji/emoji-test.txt
if [ ! -r "$DATA" ]; then
    notify-send "Emoji picker" "unicode-emoji isn't installed ($DATA missing)"
    exit 1
fi

# "1F600 ; fully-qualified # 😀 E1.0 grinning face" -> "😀 grinning face"
choice="$(awk -F'# ' '/; fully-qualified/ {
    split($2, a, " ")
    name = $2
    sub(/^[^ ]+ E[0-9.]+ /, "", name)
    print a[1] " " name
}' "$DATA" | fuzzel --dmenu --prompt "emoji> ")" || exit 0
[ -n "$choice" ] || exit 0

emoji="${choice%% *}"
printf '%s' "$emoji" | wl-copy
command -v wtype >/dev/null 2>&1 && wtype "$emoji"
