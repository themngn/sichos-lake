#!/usr/bin/env bash
# Installs everything in this directory onto the current machine:
#   - base packages this desktop needs (packages.txt), Hyprland + quickshell
#     from the lionheartp/Hyprland COPR
#   - RPM Fusion (free + nonfree) and, by default, Flatpak + the Flathub remote
#     (Element/Vesktop, if selected, also get an org.freedesktop.secrets
#     flatpak override and a desktop-entry override — see hypr/autostart.lua
#     for why: without them these Electron apps' safeStorage can't reach a
#     keyring backend and show a blocking dialog on every launch)
#   - the JetBrainsMono Nerd Font (not packaged by Fedora; fetched from
#     upstream nerd-fonts releases)
#   - the Hyprland Lua config (~/.config/hypr)
#   - the full quickshell config (~/.config/quickshell)
#   - HyprQuickFrame (github.com/Ronin-CK/HyprQuickFrame), a quickshell-based
#     screenshot overlay, cloned to ~/.config/quickshell/HyprQuickFrame and
#     bound to Print/SHIFT+Print/CTRL+Print in keybindings.lua, plus satty
#     (mineiro/satty COPR) for its "Edit" annotation action
#   - sichos-gamepad (mdukhota/test1 COPR), native controller overlay daemon
#   - the kitty config (~/.config/kitty)
#   - qt6ct with a dark color scheme, so Qt6 apps (Telegram) pick up dark
#     window chrome/dialogs via QT_QPA_PLATFORMTHEME=qt6ct (set in env.lua)
#   - the "unlock" Plymouth theme (black bg, purple lock/entry, SignOS logo)
#   - SDDM as the login screen/display manager, with the real modern Plasma 6
#     Breeze theme (sddm-breeze + kde-settings-sddm — not sddm's own bare
#     default, which is a much plainer fallback), real password login — no
#     autologin. Also disables greetd (this setup's old display manager, now
#     retired: tuigreet/qtgreet were both greetd greeters, no longer used)
#   - the desktop wallpaper (wallpaper/wallpaper.jpg)
#
# Safe to re-run: each step checks current state before changing anything.
# System-level steps (packages, theme files, SDDM) run via sudo and will
# prompt for your password in this terminal.
#
# Flags:
#   --vm   force software rendering (WLR_RENDERER=pixman, LIBGL_ALWAYS_SOFTWARE=1)
#          in env.lua. Needed on VMware/vmwgfx and similar, where accelerated
#          buffer handling breaks wlroots clients (wl_surface.attach errors).
#   --alt  swap the Hyprland main modifier from SUPER to ALT in keybindings.lua
#          (useful when the host OS/hypervisor eats the Super key).
#
# wlctl, pavucontrol dark theme, fastfetch branding, Plymouth theme, SDDM,
# and the wallpaper are all core parts of this setup and always
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
# together if scripting install.sh directly. GFN_APPS is the same idea for
# GeForce NOW (sichos-setup.sh's Gaming step): it's a Flatpak app id too,
# but installed from its own Nvidia-hosted "GeForceNOW" remote instead of
# Flathub, since Nvidia doesn't publish it there.
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
# SICHOS_TIMEZONE (an IANA zone like America/New_York), SICHOS_LANG (a
# glibc locale like en_US.UTF-8), and SICHOS_LC_NUMERIC/SICHOS_LC_MONETARY/
# SICHOS_LC_COLLATE (per-category overrides, same locale format) are all
# blank = leave unchanged by default.
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

echo "==> Time & Region"

# Also settable later from the quickshell launcher itself (Menu > Settings
# > Time & Region — TimeRegion.qml), which calls timedatectl/localectl the
# same way; both go through polkit (hyprpolkitagent, already autostarted)
# rather than needing sudo here.
CURRENT_TIMEZONE="$(timedatectl show -p Timezone --value 2>/dev/null || echo "")"
TARGET_TIMEZONE="${SICHOS_TIMEZONE:-}"
if [ -n "$TARGET_TIMEZONE" ] && [ "$TARGET_TIMEZONE" != "$CURRENT_TIMEZONE" ]; then
    # A plain file-existence check against the zoneinfo database — cheap,
    # and guards the one real crash risk here: set -e means a typo'd
    # timezone name would otherwise abort every remaining install step.
    if [ -f "/usr/share/zoneinfo/$TARGET_TIMEZONE" ]; then
        sudo timedatectl set-timezone "$TARGET_TIMEZONE"
        echo "    timezone set to $TARGET_TIMEZONE"
    else
        echo "    '$TARGET_TIMEZONE' isn't a valid zoneinfo name (see 'timedatectl list-timezones') — left as ${CURRENT_TIMEZONE:-unset}"
    fi
else
    echo "    timezone already ${CURRENT_TIMEZONE:-unset}"
fi

# "Locale" isn't one setting — LANG is the fallback every category (date/
# time, numbers, currency, sort order) uses unless it has its own explicit
# override (LC_NUMERIC/LC_MONETARY/LC_COLLATE). 12-hour vs 24-hour isn't
# one of these categories — no glibc locale is "en_US but 24-hour", so
# there's nothing proper to pick here; that's a plain on/off preference for
# the quickshell bar's own clock, set from the launcher itself (Menu >
# Settings > Time & Region — TimeRegion.use24Hour), not this installer.
# Crucially, `localectl set-locale` REPLACES the whole locale config with
# exactly the assignments it's given — it does not merge with what's
# already set — so every category that's currently configured has to be
# resent together in one call, or the ones left out would silently revert
# to the C/POSIX default. Same rule the launcher's TimeRegion.qml follows
# for live edits.
CURRENT_STATUS="$(localectl status 2>/dev/null)"
extract_locale_var() { echo "$CURRENT_STATUS" | sed -n "s/.*$1=\([^ ]*\).*/\1/p" | head -1; }
CURRENT_LANG="$(extract_locale_var LANG)"
CURRENT_LC_NUMERIC="$(extract_locale_var LC_NUMERIC)"
CURRENT_LC_MONETARY="$(extract_locale_var LC_MONETARY)"
CURRENT_LC_COLLATE="$(extract_locale_var LC_COLLATE)"

TARGET_LANG="${SICHOS_LANG:-$CURRENT_LANG}"
TARGET_LC_NUMERIC="${SICHOS_LC_NUMERIC:-$CURRENT_LC_NUMERIC}"
TARGET_LC_MONETARY="${SICHOS_LC_MONETARY:-$CURRENT_LC_MONETARY}"
TARGET_LC_COLLATE="${SICHOS_LC_COLLATE:-$CURRENT_LC_COLLATE}"

if [ "$TARGET_LANG" != "$CURRENT_LANG" ] \
    || [ "$TARGET_LC_NUMERIC" != "$CURRENT_LC_NUMERIC" ] || [ "$TARGET_LC_MONETARY" != "$CURRENT_LC_MONETARY" ] \
    || [ "$TARGET_LC_COLLATE" != "$CURRENT_LC_COLLATE" ]; then
    LOCALE_ARGS=("LANG=${TARGET_LANG:-en_US.UTF-8}")
    [ -n "$TARGET_LC_NUMERIC" ] && LOCALE_ARGS+=("LC_NUMERIC=$TARGET_LC_NUMERIC")
    [ -n "$TARGET_LC_MONETARY" ] && LOCALE_ARGS+=("LC_MONETARY=$TARGET_LC_MONETARY")
    [ -n "$TARGET_LC_COLLATE" ] && LOCALE_ARGS+=("LC_COLLATE=$TARGET_LC_COLLATE")
    sudo localectl set-locale "${LOCALE_ARGS[@]}"
    echo "    locale set: ${LOCALE_ARGS[*]} (install glibc-langpack-<xx> for any not already generated)"
else
    echo "    locale already Language=${CURRENT_LANG:-unset}, Number=${CURRENT_LC_NUMERIC:-same as Language}, Currency=${CURRENT_LC_MONETARY:-same as Language}, Sort=${CURRENT_LC_COLLATE:-same as Language}"
fi

echo "==> polkit rule: skip prompt for locale/timezone changes"

# Upstream's own default policy for org.freedesktop.locale1.set-locale and
# org.freedesktop.timedate1.set-timezone requires auth_admin_keep even for
# a fully active local session — fine for a multi-admin box, but the
# launcher's own Time & Region screen (TimeRegion.qml) calls
# timedatectl/localectl directly as a GUI action with no terminal to type
# a password into, so it'd otherwise always prompt (see
# polkit/49-sichos-timedate-locale.rules for the actual rule: scoped to
# the wheel group on an active session, not a blanket allow — a remote or
# inactive session still gets the normal prompt). polkitd watches
# rules.d and picks this up immediately, no restart needed.
sudo mkdir -p /etc/polkit-1/rules.d
RULE_DEST=/etc/polkit-1/rules.d/49-sichos-timedate-locale.rules
if ! cmp -s "$HERE/polkit/49-sichos-timedate-locale.rules" "$RULE_DEST" 2>/dev/null; then
    if [ -f "$RULE_DEST" ]; then
        sudo cp "$RULE_DEST" "$RULE_DEST.bak"
        echo "    backed up existing rule to $RULE_DEST.bak"
    fi
    sudo cp "$HERE/polkit/49-sichos-timedate-locale.rules" "$RULE_DEST"
    echo "    installed to $RULE_DEST"
else
    echo "    rule already up to date"
fi

echo "==> Bluetooth: fix HID controllers that pair then instantly disconnect"

# A well-known BlueZ/kernel L2CAP quirk: many wireless game controllers
# (reproduced live with a GuliKit Controller XW — `bluetoothctl pair`
# reports "Pairing successful" and a momentary Connected: yes, then the
# device drops straight back to Paired: no / Connected: no on its own)
# fail to complete their HID connection when BlueZ negotiates L2CAP's
# Enhanced Re-Transmission Mode with them. Disabling ERTM is the standard,
# widely-documented fix. Only touches main.conf if bluez is even installed,
# and only once (checked so a re-run doesn't pile up duplicate lines).
BT_CONF=/etc/bluetooth/main.conf
if [ -f "$BT_CONF" ]; then
    if ! grep -q "^DisableERTM" "$BT_CONF"; then
        sudo sed -i '/^\[General\]/a DisableERTM = true' "$BT_CONF"
        sudo systemctl restart bluetooth
        echo "    added DisableERTM = true to $BT_CONF and restarted bluetooth"
    else
        echo "    already configured"
    fi
else
    echo "    bluez not installed, skipped"
fi

echo "==> Bluetooth: let HID controllers connect without full bonding"

# The ERTM fix above wasn't the whole story: reproduced live with the same
# GuliKit Controller XW — even once the connection itself stopped dropping,
# it never actually became a working gamepad (no /dev/input device, no
# response in-browser at hardwaretester.com/gamepad). `busctl` introspection
# showed why: BlueZ correctly resolves an org.bluez.Input1 interface and
# ServicesResolved goes true, but Bonded stays "no" even though pairing
# succeeds and the controller explicitly negotiates "General Bonding" —
# and input.conf's ClassicBondedOnly (on by default) refuses to bring up
# HID for anything that isn't fully Bonded. Confirmed fix: flip it off.
IN_CONF=/etc/bluetooth/input.conf
if [ -f "$IN_CONF" ]; then
    if grep -q "^ClassicBondedOnly=false" "$IN_CONF"; then
        echo "    already configured"
    else
        if grep -q "^#ClassicBondedOnly=true" "$IN_CONF"; then
            sudo sed -i 's/^#ClassicBondedOnly=true/ClassicBondedOnly=false/' "$IN_CONF"
        else
            printf '\n# Added by SichOS install.sh — see comment above.\nClassicBondedOnly=false\n' | sudo tee -a "$IN_CONF" >/dev/null
        fi
        sudo systemctl restart bluetooth
        echo "    set ClassicBondedOnly=false in $IN_CONF and restarted bluetooth"
    fi
else
    echo "    bluez not installed, skipped"
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

    # GeForce NOW isn't on Flathub — Nvidia ships it from their own repo
    # instead, so it needs its own remote rather than another FLATHUB_APPS
    # entry. --user + a user remote, matching Nvidia's own install
    # instructions, rather than the sudo + system-wide remote used for
    # flathub above — nothing else here needs anything narrower than that.
    for app in ${GFN_APPS:-}; do
        if flatpak info "$app" >/dev/null 2>&1; then
            echo "    $app already installed"
        else
            if ! flatpak remote-list --user 2>/dev/null | grep -q '^GeForceNOW'; then
                flatpak remote-add --user --if-not-exists GeForceNOW https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo
                echo "    added GeForceNOW remote (user)"
            fi
            echo "    installing $app"
            flatpak install -y --noninteractive --user GeForceNOW "$app"
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

    # Flatpak apps don't install CLI binaries into $PATH by default.
    # Create wrapper scripts in ~/.local/bin for editors so `code` and
    # `codium` commands work out-of-the-box in terminals and scripts.
    mkdir -p "$HOME/.local/bin"
    if flatpak info com.visualstudio.code >/dev/null 2>&1; then
        cat << 'EOF' > "$HOME/.local/bin/code"
#!/usr/bin/env bash
exec flatpak run com.visualstudio.code "$@"
EOF
        chmod +x "$HOME/.local/bin/code"
        echo "    installed CLI wrapper ~/.local/bin/code -> com.visualstudio.code"
    fi
    if flatpak info com.vscodium.codium >/dev/null 2>&1; then
        cat << 'EOF' > "$HOME/.local/bin/codium"
#!/usr/bin/env bash
exec flatpak run com.vscodium.codium "$@"
EOF
        chmod +x "$HOME/.local/bin/codium"
        echo "    installed CLI wrapper ~/.local/bin/codium -> com.vscodium.codium"
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
# anything still commented out (qt6ct, etc.) is deliberately skipped here.
# dnf no-ops on anything already installed.
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

# hyprpolkitagent/hyprsunset/hypridle run as their packaged systemd --user
# services rather than as plain background processes from autostart.lua —
# see that file's opening comment for the full history/rationale. Only
# takes effect if the SDDM session picked at login is the uwsm-managed
# `hyprland-uwsm.desktop` entry (uwsm is what exports WAYLAND_DISPLAY into
# systemd's user-manager environment, which these units require via
# ConditionEnvironment) — under the plain `hyprland.desktop` entry this is a
# harmless no-op, nothing starts. xdg-desktop-portal(-hyprland/-gtk) need no
# enabling here: they're Type=dbus and activate on demand.
systemctl --user enable hyprpolkitagent.service hyprsunset.service hypridle.service >/dev/null 2>&1
echo "    enabled hyprpolkitagent/hyprsunset/hypridle systemd --user services"

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

echo "==> suppressing nm-applet autostart (wlctl replaces its tray icon)"

install_file "$HERE/autostart-overrides/nm-applet.desktop" "$HOME/.config/autostart/nm-applet.desktop"
echo "    installed to ~/.config/autostart (overrides /etc/xdg/autostart/nm-applet.desktop)"

echo "==> fastfetch config (SichOS branding)"

install_file "$HERE/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
install_file "$HERE/fastfetch/logo.txt" "$HOME/.config/fastfetch/logo.txt"
echo "    installed to ~/.config/fastfetch"

echo "==> sichos-gamepad (native controller overlay daemon)"

if ! rpm -q sichos-gamepad >/dev/null 2>&1; then
    sudo dnf copr enable -y mdukhota/test1
    sudo dnf install -y sichos-gamepad
else
    echo "    already installed"
fi

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

echo "==> SDDM"

if ! rpm -q sddm >/dev/null 2>&1; then
    echo "    installing sddm"
    sudo dnf install -y sddm
else
    echo "    sddm already installed"
fi
if ! rpm -q cage >/dev/null 2>&1; then
    echo "    installing cage (SDDM Wayland compositor)"
    sudo dnf install -y cage
else
    echo "    cage already installed"
fi

# The bare sddm package's own fallback look is not particularly polished.
# Two other approaches were tried and abandoned before this one:
#   1. The *authentic* modern Plasma 6 Breeze theme (sddm-breeze +
#      kde-settings-sddm) — works, but pulls in ~195 MiB of KDE Frameworks/
#      Plasma QML runtime (plasma-workspace, baloo, kactivitymanagerd,
#      kwallet, krunner, networkmanager-qt, ...) that nothing else on this
#      Hyprland setup uses, and it's not prunable: plasma-workspace has its
#      OWN hard `Requires:` on all of that, so trimming any of it cascades
#      to removing the theme too.
#   2. A vendored third-party theme (Sugar Candy) picked for being pure
#      QtQuick with no KDE Frameworks dependency — except it's Qt5-only
#      (`import QtGraphicalEffects 1.0`), and Fedora's sddm package only
#      ships `sddm-greeter-qt6` — no Qt5 greeter exists at all here, so it
#      could never have worked regardless of which Qt5 packages got
#      installed (confirmed live: the exact "module ... is not installed"
#      error, even with those packages present — Qt5 QML plugins simply
#      cannot load in a Qt6 QQmlEngine).
# So: sddm/sichos/ is hand-written instead, built entirely on SddmComponents
# (ships with the base `sddm` package itself) and QtQuick.Effects (ships
# with qt6-qtdeclarative, sddm's own hard Qt6 Quick dependency) — genuinely
# zero packages beyond what a bare `sddm` install already requires. See
# sddm/sichos/Main.qml's own header comment for the verified SDDM QML API
# calls used (checked against upstream's own reference theme, not guessed).
if rpm -q sddm-breeze kde-settings-sddm >/dev/null 2>&1; then
    echo "    removing sddm-breeze + kde-settings-sddm (replaced by the hand-written sichos theme)"
    sudo dnf remove -y sddm-breeze kde-settings-sddm
fi
if rpm -q xwaylandvideobridge >/dev/null 2>&1; then
    echo "    removing xwaylandvideobridge (unwanted plasma-workspace autostart helper)"
    sudo dnf remove -y xwaylandvideobridge
fi
if rpm -q qt5-qtgraphicaleffects qt5-qtquickcontrols2 >/dev/null 2>&1; then
    echo "    removing qt5-qtgraphicaleffects/qt5-qtquickcontrols2 (needed only by the abandoned Sugar Candy attempt)"
    sudo dnf remove -y qt5-qtgraphicaleffects qt5-qtquickcontrols2
fi

sudo mkdir -p /usr/share/sddm/themes/sichos
sudo cp -r "$HERE"/sddm/sichos/. /usr/share/sddm/themes/sichos/
# Main.qml's Background source is theme-relative — reuses the same wallpaper
# file the desktop itself uses (see the "wallpaper" step below) rather than
# vendoring a second copy of it in the repo. SDDM can't read ~/Pictures
# directly (runs as its own system user, before any login), so this has to
# be a real copy, not a symlink into $HOME.
sudo cp "$HERE/wallpaper/wallpaper.jpg" /usr/share/sddm/themes/sichos/background.jpg

sudo mkdir -p /etc/sddm.conf.d
if ! cmp -s "$HERE/sddm/10-theme.conf" /etc/sddm.conf.d/10-theme.conf 2>/dev/null; then
    sudo cp "$HERE/sddm/10-theme.conf" /etc/sddm.conf.d/10-theme.conf
    echo "    theme set to sichos (cage compositor)"
else
    echo "    theme config already up to date"
fi

# XCURSOR_THEME/SIZE as real process env vars for cage and the greeter —
# ensures proper cursor theme and software cursor fallback under wlroots.
if ! cmp -s "$HERE/sddm/sysconfig-sddm" /etc/sysconfig/sddm 2>/dev/null; then
    if [ -f /etc/sysconfig/sddm ]; then
        sudo cp /etc/sysconfig/sddm /etc/sysconfig/sddm.bak
        echo "    backed up existing /etc/sysconfig/sddm to sddm.bak"
    fi
    sudo cp "$HERE/sddm/sysconfig-sddm" /etc/sysconfig/sddm
    echo "    installed to /etc/sysconfig/sddm"
else
    echo "    /etc/sysconfig/sddm already up to date"
fi

# Retiring greetd (tuigreet/qtgreet were both greetd greeters this setup used
# previously) — disable it so it can't fight sddm over the display-manager.service
# alias. Only affects the *next* boot, same as everything else in this block;
# doesn't touch the current running session.
if systemctl is-enabled greetd >/dev/null 2>&1; then
    echo "    disabling greetd (replaced by sddm)"
    sudo systemctl disable greetd >/dev/null 2>&1 || true
fi

# No autologin. Installing the package alone doesn't make it the active
# display manager or boot into a graphical session — both have to be set
# explicitly, or a fresh machine just sits at multi-user.target forever.
sudo systemctl enable sddm
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
    # A leftover socket from the killed process can still be sitting there
    # when the new one binds (SIGTERM is asynchronous) — same race as
    # hyprsunset's restart in Bar.qml's onScheduleSaved.
    rm -f "$XDG_RUNTIME_DIR"/hypr/*/.hyprpaper.sock
    nohup hyprpaper >/tmp/hyprpaper.log 2>&1 &
    disown
    sleep 1

    # Unlike the old rendered SichOS-logo-on-black wallpaper (which needed a
    # native-resolution render per monitor to avoid GPU minification
    # aliasing on the sharp text), this is a real photo — normal GPU
    # bilinear downscaling looks fine on it, so one shared file with
    # "cover" fit (this IPC call's optional third argument:
    # [mon],[path],[fit_mode]) applied to every monitor (empty mon field)
    # is enough; no per-monitor render step needed.
    hyprctl hyprpaper wallpaper ",$HOME/Pictures/wallpaper.jpg,cover" >/dev/null 2>&1
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

Nothing here restarted sddm, quickshell, or rebooted for you:
  - reboot (or \`sudo systemctl restart sddm\`) to pick up the SDDM/
    Plymouth changes$([ "$VM" -eq 1 ] && echo "/env.lua render overrides (env vars are only read at Hyprland startup, so a reboot is the reliable way)")
  - Hyprland and quickshell config changes are already live$([ "$ALT" -eq 1 ] && echo " (except the --alt modifier swap, which needs the reboot above too)")
  - restart kitty for its config change to take effect
  - the hostname change (if applied) is live system-wide already; open a new
    terminal to see it reflected in your shell prompt and fastfetch
EOF
