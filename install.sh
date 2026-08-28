#!/usr/bin/env bash
# Installs everything in this directory onto the current machine:
#   - the "unlock" Plymouth theme (black bg, purple lock/entry, SignOS logo)
#   - the greetd autologin config (initial_session as mono + a real greeter
#     fallback, plus the missing "greeter" system user)
#   - the quickshell Theme/Launcher/HiddenApps overrides
#   - the SignOS desktop wallpaper (same logo, centered on black)
#
# Safe to re-run: each step checks current state before changing anything.
# System-level steps (greeter user, package install, theme files, greetd
# config) run via sudo and will prompt for your password in this terminal.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QS_DIR="$HOME/.config/quickshell/modules"

echo "==> Plymouth 'unlock' theme"

if ! rpm -q plymouth-plugin-script >/dev/null 2>&1; then
    echo "    installing plymouth-plugin-script"
    sudo dnf install -y plymouth-plugin-script
else
    echo "    plymouth-plugin-script already installed"
fi

sudo mkdir -p /usr/share/plymouth/themes/unlock
sudo cp "$HERE"/plymouth/unlock/* /usr/share/plymouth/themes/unlock/
sudo plymouth-set-default-theme -R unlock
echo "    installed, initramfs rebuilt"

echo "==> greetd"

if ! getent passwd greeter >/dev/null; then
    echo "    creating missing 'greeter' system user (greetd's default_session"
    echo "    fallback needs this account; without it greetd crash-loops)"
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin greeter
else
    echo "    'greeter' system user already exists"
fi

if ! cmp -s "$HERE/greetd/config.toml" /etc/greetd/config.toml 2>/dev/null; then
    if [ -f /etc/greetd/config.toml ]; then
        sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.bak
        echo "    backed up existing config to /etc/greetd/config.toml.bak"
    fi
    sudo cp "$HERE/greetd/config.toml" /etc/greetd/config.toml
    echo "    config installed"
else
    echo "    config already up to date"
fi

echo "==> quickshell overrides"

mkdir -p "$QS_DIR"
for f in Theme.qml Launcher.qml HiddenApps.qml; do
    if [ -f "$QS_DIR/$f" ] && ! cmp -s "$HERE/quickshell/$f" "$QS_DIR/$f"; then
        cp "$QS_DIR/$f" "$QS_DIR/$f.bak"
        echo "    backed up existing $f to $f.bak"
    fi
    cp "$HERE/quickshell/$f" "$QS_DIR/$f"
done
echo "    installed (quickshell hot-reloads these automatically)"

echo "==> wallpaper"

mkdir -p "$HOME/Pictures"
if [ -f "$HOME/Pictures/default.png" ] && ! cmp -s "$HERE/wallpaper/wallpaper-signos.png" "$HOME/Pictures/default.png"; then
    cp "$HOME/Pictures/default.png" "$HOME/Pictures/default.png.bak"
    echo "    backed up existing wallpaper to Pictures/default.png.bak"
fi
cp "$HERE/wallpaper/wallpaper-signos.png" "$HOME/Pictures/wallpaper-signos.png"
cp "$HERE/wallpaper/wallpaper-signos.png" "$HOME/Pictures/default.png"

if pgrep -x hyprpaper >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    pkill hyprpaper
    sleep 1
    nohup hyprpaper >/tmp/hyprpaper.log 2>&1 &
    disown
    sleep 1
    hyprctl hyprpaper wallpaper "eDP-1,$HOME/Pictures/default.png" >/dev/null 2>&1 || true
    echo "    installed and reloaded live"
else
    echo "    installed (hyprpaper not running under this session — will show on next login)"
fi

cat <<'EOF'

==> Done.

Nothing here restarted greetd or rebooted for you, since that kills the
current graphical session:
  - reboot (or `sudo systemctl restart greetd`) to pick up the greetd/
    Plymouth changes
  - the quickshell changes should already be live
EOF
