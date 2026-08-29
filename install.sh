#!/usr/bin/env bash
# Installs everything in this directory onto the current machine:
#   - base packages this desktop needs (packages.txt), Hyprland + quickshell
#     from the lionheartp/Hyprland COPR
#   - the JetBrainsMono Nerd Font (not packaged by Fedora; fetched from
#     upstream nerd-fonts releases)
#   - the Hyprland Lua config (~/.config/hypr)
#   - the full quickshell config (~/.config/quickshell)
#   - the kitty config (~/.config/kitty)
#   - the "unlock" Plymouth theme (black bg, purple lock/entry, SignOS logo)
#   - the greetd autologin config (initial_session as mono + a real greeter
#     fallback, plus the missing "greeter" system user)
#   - the SignOS desktop wallpaper (same logo, centered on black)
#
# Safe to re-run: each step checks current state before changing anything.
# System-level steps (packages, greeter user, theme files, greetd config)
# run via sudo and will prompt for your password in this terminal.
#
# Flags:
#   --vm   force software rendering (WLR_RENDERER=pixman, LIBGL_ALWAYS_SOFTWARE=1)
#          in env.lua. Needed on VMware/vmwgfx and similar, where accelerated
#          buffer handling breaks wlroots clients (wl_surface.attach errors).
#   --alt  swap the Hyprland main modifier from SUPER to ALT in keybindings.lua
#          (useful when the host OS/hypervisor eats the Super key).

set -euo pipefail

VM=0
ALT=0
for arg in "$@"; do
    case "$arg" in
        --vm) VM=1 ;;
        --alt) ALT=1 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copies src to dest, backing up dest first (as dest.bak) if it already
# exists with different content. Used for every plain-file config we deploy.
install_file() {
    local src="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
        cp "$dest" "$dest.bak"
        echo "    backed up existing $(basename "$dest") to $(basename "$dest").bak"
    fi
    cp "$src" "$dest"
}

echo "==> Hyprland + quickshell packages"

if ! rpm -q hyprland >/dev/null 2>&1 || ! rpm -q quickshell >/dev/null 2>&1; then
    echo "    enabling COPR lionheartp/Hyprland"
    sudo dnf copr enable -y lionheartp/Hyprland
fi
if ! rpm -q hyprland >/dev/null 2>&1; then
    echo "    installing hyprland"
    sudo dnf install -y hyprland
else
    echo "    hyprland already installed"
fi
if ! rpm -q quickshell >/dev/null 2>&1; then
    echo "    installing quickshell"
    sudo dnf install -y quickshell
else
    echo "    quickshell already installed"
fi

echo "==> base packages (packages.txt)"

# packages.txt is a plain list with '#'-prefixed comment lines and blocks;
# anything still commented out (qt6ct, hyprshutdown, etc.) is deliberately
# skipped here. dnf no-ops on anything already installed.
mapfile -t BASE_PKGS < <(grep -v '^\s*#' "$HERE/packages.txt" | grep -v '^\s*$' | awk '{print $1}')
if [ "${#BASE_PKGS[@]}" -gt 0 ]; then
    sudo dnf install -y "${BASE_PKGS[@]}"
else
    echo "    nothing to install"
fi

echo "==> JetBrainsMono Nerd Font"

if fc-list | grep -qi "JetBrainsMono Nerd Font Mono"; then
    echo "    already installed"
else
    TMP_ZIP="$(mktemp --suffix=.zip)"
    echo "    downloading from nerd-fonts releases"
    curl -sL -o "$TMP_ZIP" \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    mkdir -p "$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
    unzip -oq "$TMP_ZIP" -d "$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
    rm -f "$TMP_ZIP"
    fc-cache -f "$HOME/.local/share/fonts/JetBrainsMonoNerdFont" >/dev/null
    echo "    installed to ~/.local/share/fonts/JetBrainsMonoNerdFont"
fi

echo "==> Hyprland config"

for f in "$HERE"/hypr/*; do
    install_file "$f" "$HOME/.config/hypr/$(basename "$f")"
done
echo "    installed to ~/.config/hypr (Hyprland reloads config automatically on save)"

if [ "$VM" -eq 1 ]; then
    ENV_LUA="$HOME/.config/hypr/env.lua"
    if ! grep -q "WLR_RENDERER" "$ENV_LUA"; then
        sed -i '/hl\.env("HYPRCURSOR_SIZE"/a hl.env("WLR_RENDERER", "pixman")\nhl.env("LIBGL_ALWAYS_SOFTWARE", "1")' "$ENV_LUA"
        echo "    --vm: added software-rendering env vars to env.lua"
    else
        echo "    --vm: software-rendering env vars already present"
    fi
fi

if [ "$ALT" -eq 1 ]; then
    KEYBINDS_LUA="$HOME/.config/hypr/keybindings.lua"
    sed -i 's/local mainMod = "SUPER"/local mainMod = "ALT"/' "$KEYBINDS_LUA"
    echo "    --alt: main modifier set to ALT in keybindings.lua"
fi

echo "==> quickshell config"

while IFS= read -r -d '' f; do
    rel="${f#"$HERE"/quickshell/}"
    install_file "$f" "$HOME/.config/quickshell/$rel"
done < <(find "$HERE/quickshell" -type f -print0)
echo "    installed to ~/.config/quickshell (hot-reloads automatically)"

echo "==> kitty config"

install_file "$HERE/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
echo "    installed to ~/.config/kitty"

echo "==> fastfetch config (SichOS branding)"

install_file "$HERE/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
install_file "$HERE/fastfetch/logo.txt" "$HOME/.config/fastfetch/logo.txt"
echo "    installed to ~/.config/fastfetch"

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

if ! rpm -q greetd >/dev/null 2>&1; then
    echo "    installing greetd"
    sudo dnf install -y greetd
else
    echo "    greetd already installed"
fi

if ! getent passwd greeter >/dev/null; then
    echo "    creating missing 'greeter' system user (greetd's default_session"
    echo "    fallback needs this account; without it greetd crash-loops)"
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin greeter
else
    echo "    'greeter' system user already exists"
fi

sudo mkdir -p /etc/greetd
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

# Installing the package alone doesn't make greetd the active display
# manager or boot into a graphical session — both have to be set
# explicitly, or a fresh machine just sits at multi-user.target forever.
sudo systemctl enable greetd
if [ "$(systemctl get-default)" != "graphical.target" ]; then
    echo "    setting default boot target to graphical.target"
    sudo systemctl set-default graphical.target
else
    echo "    default boot target already graphical.target"
fi

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
    hyprctl hyprpaper wallpaper ",$HOME/Pictures/default.png" >/dev/null 2>&1 || true
    echo "    installed and reloaded live"
else
    echo "    installed (hyprpaper not running under this session — will show on next login)"
fi

cat <<EOF

==> Done.

Nothing here restarted greetd, quickshell, or rebooted for you:
  - reboot (or \`sudo systemctl restart greetd\`) to pick up the greetd/
    Plymouth changes$([ "$VM" -eq 1 ] && echo "/env.lua render overrides (env vars are only read at Hyprland startup, and initial_session only fires once per boot, so a reboot is the reliable way)")
  - Hyprland and quickshell config changes are already live$([ "$ALT" -eq 1 ] && echo " (except the --alt modifier swap, which needs the reboot above too)")
  - restart kitty for its config change to take effect
EOF
