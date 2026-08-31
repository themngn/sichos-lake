#!/usr/bin/env bash
# Installs everything in this directory onto the current machine:
#   - base packages this desktop needs (packages.txt), Hyprland + quickshell
#     from the lionheartp/Hyprland COPR
#   - RPM Fusion (free + nonfree) and, by default, Flatpak + the Flathub remote
#     (Element/Vesktop, if selected, also get an org.freedesktop.secrets
#     flatpak override and a desktop-entry override — see hypr/autostart.lua
#     for why: without them, an autologin setup like this one's greetd
#     config can never unlock a real keyring, and these Electron apps show
#     a blocking dialog on every launch)
#   - the JetBrainsMono Nerd Font (not packaged by Fedora; fetched from
#     upstream nerd-fonts releases)
#   - the Hyprland Lua config (~/.config/hypr)
#   - the full quickshell config (~/.config/quickshell)
#   - HyprQuickFrame (github.com/Ronin-CK/HyprQuickFrame), a quickshell-based
#     screenshot overlay, cloned to ~/.config/quickshell/HyprQuickFrame and
#     bound to Print/SHIFT+Print/CTRL+Print in keybindings.lua, plus satty
#     (mineiro/satty COPR) for its "Edit" annotation action
#   - the kitty config (~/.config/kitty)
#   - qt6ct with a dark color scheme, so Qt6 apps (Telegram) pick up dark
#     window chrome/dialogs via QT_QPA_PLATFORMTHEME=qt6ct (set in env.lua)
#   - the "unlock" Plymouth theme (black bg, purple lock/entry, SignOS logo)
#   - the greetd autologin config (initial_session as mono + a real greeter
#     fallback, plus the missing "greeter" system user)
#   - the desktop wallpaper (wallpaper/wallpaper.jpg)
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
#
# wlctl, pavucontrol dark theme, fastfetch branding, Plymouth theme, greetd
# autologin, and the wallpaper are all core parts of this setup and always
# run — they are not configurable. Telegram is a genuinely optional extra
# app: it's opt-in via SKIP_TELEGRAM=0 (default is skipped). Flatpak +
# Flathub defaults to ON instead (SKIP_FLATPAK=1 to skip it).
# ./sichos-setup.sh sets both of these for you interactively.
#
# Firefox installs and is the default browser unless SKIP_FIREFOX=1 /
# DEFAULT_BROWSER names another one (chrome, chromium, librewolf,
# ungoogled-chromium, waterfox — see BROWSER_FLATPAK_ID below). Non-Firefox
# choices are Flatpak apps, so they also need to be in FLATHUB_APPS —
# sichos-setup.sh's Browser step keeps both in sync; set them by hand
# together if scripting install.sh directly.
#
# Git identity and SSH key setup are opt-IN (the opposite default, since
# running install.sh bare shouldn't silently touch your git config or mint a
# new SSH key): set GIT_NAME/GIT_EMAIL to configure `git config --global`,
# and SSH_KEY_MODE to one of skip (default) / existing / generate /
# generate-gh (generate + `gh ssh-key add`). SKIP_SSHD=0 installs and
# enables openssh-server (opening it in firewalld if active) — default
# skipped, since a keypair or authorized_keys are pointless for incoming
# access without it. SSHD_PASSWORD_AUTH=1 allows password login when sshd
# is enabled (default 0/key-only). GH_IMPORT_USER (blank = skip) pulls a GitHub
# username's public keys into ~/.ssh/authorized_keys via
# github.com/<user>.keys, independent of SSH_KEY_MODE — that's this
# machine's identity going out, this is who's allowed to log in. SICHOS_HOSTNAME
# overrides the default fedora->SichOS rename with a custom hostname.
# ./sichos-setup.sh sets all of these for you interactively.

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

echo "==> hostname"

CURRENT_HOSTNAME="$(hostname)"
TARGET_HOSTNAME="${SICHOS_HOSTNAME:-}"
if [ -z "$TARGET_HOSTNAME" ] && [ "$CURRENT_HOSTNAME" = "fedora" ]; then
    TARGET_HOSTNAME="SichOS"
fi
if [ -n "$TARGET_HOSTNAME" ] && [ "$TARGET_HOSTNAME" != "$CURRENT_HOSTNAME" ]; then
    echo "    renaming hostname '$CURRENT_HOSTNAME' -> '$TARGET_HOSTNAME'"
    sudo hostnamectl set-hostname "$TARGET_HOSTNAME"
else
    echo "    hostname already set ($CURRENT_HOSTNAME), leaving as is"
fi

echo "==> RPM Fusion (free + nonfree)"

if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    echo "    enabling rpmfusion-free"
    sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
else
    echo "    rpmfusion-free already enabled"
fi
if ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
    echo "    enabling rpmfusion-nonfree"
    sudo dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
else
    echo "    rpmfusion-nonfree already enabled"
fi

echo "==> Flatpak + Flathub"

if [ "${SKIP_FLATPAK:-0}" = "1" ]; then
    echo "    skipped"
else
    if ! rpm -q flatpak >/dev/null 2>&1; then
        echo "    installing flatpak"
        sudo dnf install -y flatpak
    else
        echo "    flatpak already installed"
    fi
    if flatpak remote-list 2>/dev/null | grep -q '^flathub'; then
        echo "    flathub remote already added"
    else
        sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        echo "    added flathub remote"
    fi

    for app in ${FLATHUB_APPS:-}; do
        if flatpak info "$app" >/dev/null 2>&1; then
            echo "    $app already installed"
        else
            echo "    installing $app"
            flatpak install -y --noninteractive flathub "$app"
        fi
    done

    # Element and Vesktop are both Electron apps that need a couple of
    # keyring-related fixes applied on top of a plain flatpak install (see
    # hypr/autostart.lua for the rest of the picture) — otherwise they show
    # a blocking "No encryption support"/"System unsupported" dialog on
    # every launch. Checked by current install state rather than
    # $FLATHUB_APPS so re-running install.sh keeps this in sync even on a
    # run where the user didn't re-select these apps.
    for app in im.riot.Riot dev.vencord.Vesktop; do
        if flatpak info "$app" >/dev/null 2>&1; then
            # Neither ships org.freedesktop.secrets talk permission by
            # default, so safeStorage can never reach the keyring even
            # once one is unlocked and running.
            flatpak override --user --talk-name=org.freedesktop.secrets "$app"
            # ...and even with the keyring reachable, Chromium's
            # desktop-environment sniffing doesn't recognize
            # XDG_CURRENT_DESKTOP=Hyprland and won't auto-select the
            # libsecret backend on its own — this override adds
            # --password-store=gnome-libsecret to Exec= (not
            # --password-store=basic, the actual weak/unencrypted
            # fallback) so it applies to every launch, manual or
            # autostart. See desktop-overrides/$app.desktop.
            install_file "$HERE/desktop-overrides/$app.desktop" \
                "$HOME/.local/share/applications/$app.desktop"
            NEED_DESKTOP_DB_UPDATE=1
        fi
    done
    if [ "${NEED_DESKTOP_DB_UPDATE:-0}" = "1" ]; then
        # Without this, ~/.local/share/applications/mimeinfo.cache never
        # gets created/refreshed, so the x-scheme-handler/element and
        # x-scheme-handler/io.element.desktop entries above are invisible
        # to the xdg-desktop-portal OpenURI chooser (used when e.g. a
        # browser hands off an OAuth login callback link to Element) even
        # though `xdg-mime query default` finds them fine — that command
        # reads .desktop files directly, but the portal's own app-chooser
        # goes through this cache and shows "No Apps available" without it.
        update-desktop-database "$HOME/.local/share/applications"
    fi
fi

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

echo "==> Firefox"

if [ "${SKIP_FIREFOX:-0}" = "1" ]; then
    echo "    skipped"
elif rpm -q firefox >/dev/null 2>&1; then
    echo "    already installed"
else
    sudo dnf install -y firefox
fi

echo "==> Default browser"

# Flatpak app IDs for every non-Firefox choice sichos-setup.sh's Browser
# step can produce as DEFAULT_BROWSER; matches BROWSER_KEY there.
declare -A BROWSER_FLATPAK_ID=(
    [chromium]="org.chromium.Chromium"
    [librewolf]="io.gitlab.librewolf-community"
    [chrome]="com.google.Chrome"
    [ungoogled-chromium]="io.github.ungoogled_software.ungoogled_chromium"
    [waterfox]="net.waterfox.waterfox"
)

# Patches the just-deployed (fresh, unmodified) copies under ~/.config/hypr
# rather than the repo's own files — same approach as the --vm/--alt
# patches above. DEFAULT_BROWSER="" (every browser unchecked) leaves
# Firefox's programs.lua/autostart.lua entries and whatever system default
# was already set alone, rather than forcing anything.
DEFAULT_BROWSER="${DEFAULT_BROWSER:-firefox}"
if [ -z "$DEFAULT_BROWSER" ]; then
    echo "    none selected — leaving Firefox's config in place"
elif [ "$DEFAULT_BROWSER" = "firefox" ]; then
    if command -v xdg-settings >/dev/null 2>&1; then
        xdg-settings set default-web-browser org.mozilla.firefox.desktop 2>/dev/null || true
    fi
    echo "    Firefox (default)"
elif [ -n "${BROWSER_FLATPAK_ID[$DEFAULT_BROWSER]:-}" ]; then
    APP_ID="${BROWSER_FLATPAK_ID[$DEFAULT_BROWSER]}"
    sed -i "s|M.browser     = \"firefox\"|M.browser     = \"flatpak run $APP_ID\"|" \
        "$HOME/.config/hypr/programs.lua"
    sed -i "s|& firefox\"|\\& flatpak run $APP_ID\"|" \
        "$HOME/.config/hypr/autostart.lua"
    if command -v xdg-settings >/dev/null 2>&1; then
        xdg-settings set default-web-browser "$APP_ID.desktop" 2>/dev/null || true
    fi
    echo "    set to $DEFAULT_BROWSER"
else
    echo "    unrecognized DEFAULT_BROWSER=$DEFAULT_BROWSER, leaving Firefox as default"
fi

echo "==> quickshell config"

while IFS= read -r -d '' f; do
    rel="${f#"$HERE"/quickshell/}"
    install_file "$f" "$HOME/.config/quickshell/$rel"
done < <(find "$HERE/quickshell" -type f -print0)
echo "    installed to ~/.config/quickshell (hot-reloads automatically)"

echo "==> HyprQuickFrame (screenshot overlay, github.com/Ronin-CK/HyprQuickFrame)"

# A sibling of our own config under ~/.config/quickshell rather than part of
# it — the "quickshell config" step above only touches files that exist in
# this repo's quickshell/ directory, so it never conflicts with this clone.
# Invoked via `quickshell -p <path>` (not `-c <name>`): our own top-level
# ~/.config/quickshell/shell.qml gets registered as quickshell's "default"
# config, which per quickshell's own docs disables scanning any
# subdirectories for named configs — `-c HyprQuickFrame` would never
# resolve while that file exists. `-p` loads the given path directly instead
# (see the comment in keybindings.lua where it's actually invoked).
HQF_DIR="$HOME/.config/quickshell/HyprQuickFrame"
if [ -d "$HQF_DIR/.git" ]; then
    echo "    updating existing clone"
    git -C "$HQF_DIR" pull --ff-only
else
    echo "    cloning to $HQF_DIR"
    git clone --depth 1 https://github.com/Ronin-CK/HyprQuickFrame "$HQF_DIR"
fi

# ~/.config/hyprquickframe/theme.toml is checked before the repo's own copy
# (see HyprQuickFrame's README) — same defaults, animations turned off.
install_file "$HERE/hyprquickframe/theme.toml" "$HOME/.config/hyprquickframe/theme.toml"
echo "    theme installed to ~/.config/hyprquickframe (animations disabled)"

echo "==> satty (HyprQuickFrame's annotationTool)"

# Not in Fedora or RPM Fusion; not available at all until this COPR is enabled.
if ! rpm -q satty >/dev/null 2>&1; then
    sudo dnf copr enable -y mineiro/satty
    sudo dnf install -y satty
else
    echo "    already installed"
fi

echo "==> kitty config"

install_file "$HERE/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
echo "    installed to ~/.config/kitty"

echo "==> pavucontrol-dark GTK4 theme"

# A *named* theme under ~/.local/share/themes, not ~/.config/gtk-4.0/gtk.css:
# the latter is a global user stylesheet applied to every GTK4 app, including
# libadwaita ones like Nautilus, which already do their own correct dark
# styling via the color-scheme portal — a global override collided with that
# and broke Nautilus. A named theme only applies to processes explicitly
# launched with GTK_THEME=pavucontrol-dark (Volume.qml, for pavucontrol only).
install_file "$HERE/themes/pavucontrol-dark/gtk-4.0/gtk.css" \
    "$HOME/.local/share/themes/pavucontrol-dark/gtk-4.0/gtk.css"
echo "    installed to ~/.local/share/themes/pavucontrol-dark"

echo "==> qt6ct (Qt app dark theme)"

# env.lua already sets QT_QPA_PLATFORMTHEME=qt6ct globally, but qt6ct itself
# wasn't installed until Qt apps actually existed in this setup (Telegram is
# the first). The runtime plugin (libqt6ct.so) reads exactly these two keys
# — confirmed via `strings` on the plugin binary — so a hand-written config
# is enough; no need to run the qt6ct GUI once to seed one.
if ! rpm -q qt6ct >/dev/null 2>&1; then
    echo "    installing qt6ct"
    sudo dnf install -y qt6ct
else
    echo "    qt6ct already installed"
fi
install_file "$HERE/qt6ct/qt6ct.conf" "$HOME/.config/qt6ct/qt6ct.conf"
echo "    installed to ~/.config/qt6ct (dark palette: darker.conf)"

echo "==> wlctl (wifi TUI, used by quickshell/scripts/wlctl-toggle.sh)"

if command -v wlctl >/dev/null 2>&1; then
    echo "    already installed"
else
    if ! command -v cargo >/dev/null 2>&1; then
        echo "    installing cargo (build dependency, not packaged on crates.io as a binary)"
        sudo dnf install -y cargo
    fi
    echo "    building via 'cargo install wlctl' (https://github.com/aashish-thapa/wlctl)"
    cargo install wlctl
    sudo install -Dm755 "$HOME/.cargo/bin/wlctl" /usr/local/bin/wlctl
    echo "    installed to /usr/local/bin/wlctl"
fi

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
if [ -f "$HOME/Pictures/wallpaper.jpg" ] && ! cmp -s "$HERE/wallpaper/wallpaper.jpg" "$HOME/Pictures/wallpaper.jpg"; then
    cp "$HOME/Pictures/wallpaper.jpg" "$HOME/Pictures/wallpaper.jpg.bak"
    echo "    backed up existing wallpaper to Pictures/wallpaper.jpg.bak"
fi
cp "$HERE/wallpaper/wallpaper.jpg" "$HOME/Pictures/wallpaper.jpg"

if pgrep -x hyprpaper >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    pkill hyprpaper
    sleep 1
    nohup hyprpaper >/tmp/hyprpaper.log 2>&1 &
    disown
    sleep 1
    hyprctl hyprpaper wallpaper ",$HOME/Pictures/wallpaper.jpg,cover" >/dev/null 2>&1 || true
    echo "    installed and reloaded live"
else
    echo "    installed (hyprpaper not running under this session — will show on next login)"
fi

echo "==> Telegram"

if [ "${SKIP_TELEGRAM:-1}" = "1" ]; then
    echo "    skipped"
elif rpm -q telegram-desktop >/dev/null 2>&1; then
    echo "    already installed"
else
    sudo dnf install -y telegram-desktop
fi

echo "==> Discord"

# From rpmfusion-nonfree-updates (enabled unconditionally above) — not in
# Fedora's own repos.
if [ "${SKIP_DISCORD:-1}" = "1" ]; then
    echo "    skipped"
elif rpm -q discord >/dev/null 2>&1; then
    echo "    already installed"
else
    sudo dnf install -y discord
fi

echo "==> Steam"

# From rpmfusion-nonfree (enabled unconditionally above), not Flathub —
# native Steam wants direct access to the host's GPU drivers/Vulkan ICDs,
# udev rules (controllers), and 32-bit compat libs, which is more friction
# to get right in a Flatpak sandbox than just installing it normally.
if [ "${SKIP_STEAM:-1}" = "1" ]; then
    echo "    skipped"
elif rpm -q steam >/dev/null 2>&1; then
    echo "    already installed"
else
    sudo dnf install -y steam
fi

echo "==> Lutris"

if [ "${SKIP_LUTRIS:-1}" = "1" ]; then
    echo "    skipped"
elif rpm -q lutris >/dev/null 2>&1; then
    echo "    already installed"
else
    sudo dnf install -y lutris
fi

echo "==> LibreOffice"

if [ "${SKIP_LIBREOFFICE:-1}" = "1" ]; then
    echo "    skipped"
elif rpm -q libreoffice >/dev/null 2>&1; then
    echo "    already installed"
else
    sudo dnf install -y libreoffice
fi

if [ -z "${GIT_NAME:-}" ] && [ -z "${GIT_EMAIL:-}" ]; then
    echo "==> git identity (skipped)"
else
    echo "==> git identity"
    if [ -n "${GIT_NAME:-}" ]; then
        git config --global user.name "$GIT_NAME"
        echo "    user.name = $GIT_NAME"
    fi
    if [ -n "${GIT_EMAIL:-}" ]; then
        git config --global user.email "$GIT_EMAIL"
        echo "    user.email = $GIT_EMAIL"
    fi
fi

SSH_KEY_MODE="${SSH_KEY_MODE:-skip}"
if [ "$SSH_KEY_MODE" = "skip" ]; then
    echo "==> SSH key (skipped)"
else
    echo "==> SSH key"
    SSH_KEY="$HOME/.ssh/id_ed25519"

    if [ -f "$SSH_KEY" ]; then
        echo "    using existing $SSH_KEY"
    else
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        # No passphrase: this runs as part of an unattended-ish setup flow.
        # Add one later with 'ssh-keygen -p' if you want one.
        ssh-keygen -t ed25519 -C "${GIT_EMAIL:-$USER@$(hostname)}" -f "$SSH_KEY" -N ""
        echo "    generated $SSH_KEY"
    fi

    if [ "$SSH_KEY_MODE" = "generate-gh" ]; then
        if ! command -v gh >/dev/null 2>&1; then
            echo "    installing GitHub CLI (gh)"
            sudo dnf install -y 'dnf-command(config-manager)'
            sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null \
                || sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
            sudo dnf install -y gh
        fi
        if ! gh auth status >/dev/null 2>&1; then
            echo "    not logged in to gh — starting login flow"
            gh auth login
        fi
        KEY_FINGERPRINT="$(ssh-keygen -lf "$SSH_KEY.pub" | awk '{print $2}')"
        if gh ssh-key list 2>/dev/null | grep -qF "$KEY_FINGERPRINT"; then
            echo "    key already registered on GitHub"
        else
            gh ssh-key add "$SSH_KEY.pub" --title "$(hostname)-$(date +%Y%m%d)"
            echo "    uploaded $SSH_KEY.pub to GitHub"
        fi
    fi
fi

# Also independent of SSH_KEY_MODE and opt-in (default skip): a local
# keypair or authorized_keys are pointless for incoming access if sshd
# isn't actually installed and running.
if [ "${SKIP_SSHD:-1}" = "1" ]; then
    echo "==> SSH server (skipped)"
else
    echo "==> SSH server"
    if ! rpm -q openssh-server >/dev/null 2>&1; then
        echo "    installing openssh-server"
        sudo dnf install -y openssh-server
    else
        echo "    openssh-server already installed"
    fi
    sudo systemctl enable --now sshd
    echo "    sshd enabled and running"

    if systemctl is-active --quiet firewalld; then
        if sudo firewall-cmd --query-service=ssh >/dev/null 2>&1; then
            echo "    firewall already allows ssh"
        else
            sudo firewall-cmd --permanent --add-service=ssh
            sudo firewall-cmd --reload
            echo "    opened ssh in firewalld"
        fi
    fi

    # A drop-in under sshd_config.d/ (included by Fedora's default
    # sshd_config) rather than editing sshd_config directly — idempotent to
    # re-run and won't fight a future openssh-server update that ships a
    # new default sshd_config.
    SSHD_PASSWORD_AUTH="${SSHD_PASSWORD_AUTH:-0}"
    PW_SETTING=$([ "$SSHD_PASSWORD_AUTH" = "1" ] && echo yes || echo no)
    sudo mkdir -p /etc/ssh/sshd_config.d
    printf 'PasswordAuthentication %s\n' "$PW_SETTING" | sudo tee /etc/ssh/sshd_config.d/99-sichos.conf >/dev/null
    sudo sshd -t
    sudo systemctl reload sshd
    echo "    password login: $PW_SETTING"
fi

# Independent of SSH_KEY_MODE above: that's this machine's own identity going
# OUT to GitHub; this pulls a GitHub user's public keys IN, via GitHub's
# public (unauthenticated) https://github.com/<user>.keys endpoint, so that
# account can log into this machine over SSH.
GH_IMPORT_USER="${GH_IMPORT_USER:-}"
if [ -z "$GH_IMPORT_USER" ]; then
    echo "==> authorize GitHub user's keys (skipped)"
else
    echo "==> authorize GitHub user's keys ($GH_IMPORT_USER)"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"

    IMPORTED_KEYS="$(curl -fsSL "https://github.com/$GH_IMPORT_USER.keys")" || IMPORTED_KEYS=""
    if [ -z "$IMPORTED_KEYS" ]; then
        echo "    no public keys found for '$GH_IMPORT_USER' (typo, or account has none)"
    else
        ADDED=0
        while IFS= read -r key; do
            [ -z "$key" ] && continue
            grep -qF "$key" "$HOME/.ssh/authorized_keys" && continue
            echo "$key" >> "$HOME/.ssh/authorized_keys"
            ADDED=$((ADDED + 1))
        done <<< "$IMPORTED_KEYS"
        echo "    added $ADDED new key(s) to ~/.ssh/authorized_keys"
    fi
fi

cat <<EOF

==> Done.

Nothing here restarted greetd, quickshell, or rebooted for you:
  - reboot (or \`sudo systemctl restart greetd\`) to pick up the greetd/
    Plymouth changes$([ "$VM" -eq 1 ] && echo "/env.lua render overrides (env vars are only read at Hyprland startup, and initial_session only fires once per boot, so a reboot is the reliable way)")
  - Hyprland and quickshell config changes are already live$([ "$ALT" -eq 1 ] && echo " (except the --alt modifier swap, which needs the reboot above too)")
  - restart kitty for its config change to take effect
  - the hostname change (if applied) is live system-wide already; open a new
    terminal to see it reflected in your shell prompt and fastfetch
EOF
