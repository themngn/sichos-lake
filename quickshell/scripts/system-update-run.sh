#!/bin/bash
# Applies every pending dnf + Flatpak update. Run inside the floating
# "sichos-update-console" kitty window opened by the System Update bar
# widget's "Update All" button (see SystemUpdate.qml) -- kitty --hold keeps
# the window open afterward so the transaction output/exit status stays
# visible instead of the window vanishing the instant it finishes.
#
# A real script rather than a single `kitty -e ... && ...` command line:
# kitty -e execs its argv directly (no shell), so it can't run more than one
# command on its own.
set -uo pipefail

echo "==> dnf upgrade"
sudo dnf upgrade -y

echo
echo "==> flatpak update (system)"
flatpak update -y --noninteractive

echo
echo "==> flatpak update (user)"
flatpak update -y --user --noninteractive

echo
echo "All done."

# Package updates (especially a kernel/systemd bump, both routinely in the
# dnf batch) don't take effect until a reboot -- ask right here rather than
# leaving that step for the user to remember later. Defaults to No on a bare
# Enter/EOF (e.g. the pty closing early), never on an unattended timeout.
read -rp "Reboot now? [y/N] " reply
case "$reply" in
    [yY]|[yY][eE][sS])
        # exec, not a plain call: hyprshutdown closes every app and Hyprland
        # itself before running --post-cmd, so this script (and the kitty
        # window it's running in) is meant to go down as part of that, not
        # linger as a separate process after.
        exec hyprshutdown -t "Restarting..." --post-cmd "reboot"
        ;;
    *)
        echo "Not rebooting."
        ;;
esac
