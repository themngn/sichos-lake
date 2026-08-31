-------------------
---- AUTOSTART ----
-------------------

local programs = require("programs")

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
hl.on("hyprland.start", function ()
  -- graphical-session.target isn't reliably activated in this setup, so the
  -- xdg-desktop-portal daemons (needed for dark-mode/appearance signalling to
  -- GTK4/libadwaita apps like Nautilus, and to waybar) are started directly here
  -- instead of relying on systemd to launch them.
  hl.exec_cmd("/usr/libexec/xdg-desktop-portal-hyprland & /usr/libexec/xdg-desktop-portal-gtk & (sleep 1; /usr/libexec/xdg-desktop-portal --replace) &")
  -- No polkit authentication agent runs by default here either (same
  -- graphical-session.target gap) — without one, polkit-gated actions like
  -- mounting a LUKS drive from Nautilus fail outright with "Not authorized"
  -- instead of prompting, since there's nothing to grant/ask.
  hl.exec_cmd("/usr/libexec/hyprpolkitagent")
  -- greetd's PAM stack has `pam_gnome_keyring.so auto_start` configured,
  -- but that's a no-op unless the gnome-keyring package (providing
  -- gnome-keyring-daemon) is actually installed — see packages.txt. Even
  -- installed, PAM's own auto-unlock never fires here: greetd's
  -- `initial_session` autologins straight into Hyprland with no password
  -- prompt at all (see /etc/greetd/config.toml), so the PAM auth stage
  -- that would normally capture a password and unlock the keyring never
  -- runs. So this starts+unlocks it directly instead, the same way PAM
  -- would: `--login` reading an empty passphrase from stdin (a blank
  -- line, NOT zero bytes — actual EOF with no bytes is read as
  -- "cancelled", not "empty password"). This must be the FIRST thing to
  -- touch org.freedesktop.secrets each boot: it's a D-Bus-activatable
  -- service (/usr/share/dbus-1/services/org.freedesktop.secrets.service),
  -- so anything that queries it first (`busctl`, a secrets client) spawns
  -- a bare `--components=secrets`-only instance via that service file,
  -- which starts locked with no login/unlock step — confirmed by testing
  -- both orders directly. `--login` also sets up SSH_AUTH_SOCK, pushed
  -- into systemd --user's environment too since systemd/D-Bus-activated
  -- apps won't otherwise see it.
  --
  -- An empty-passphrase keyring is still a real, separate encrypted
  -- secret store — not the same thing as weakening an app's own
  -- encryption (see the desktop-entry override note below) — it's just
  -- unlocked with a known blank passphrase instead of prompting nobody.
  -- Without ANY unlocked keyring, Electron apps' safeStorage can't find
  -- a supported backend and throws up a blocking "System unsupported" /
  -- "No encryption support" dialog on every launch (seen with Element).
  -- The keyring file and its "default" collection alias
  -- (~/.local/share/keyrings/{login.keyring,default}) are created once
  -- and persist; this only needs to unlock them each boot.
  hl.exec_cmd("printf '\\n' | gnome-keyring-daemon --login --components=pkcs11,secrets,ssh >/dev/null 2>&1; systemctl --user import-environment SSH_AUTH_SOCK")
  -- Even with a real keyring unlocked, Chromium's desktop-environment
  -- sniffing doesn't recognize XDG_CURRENT_DESKTOP=Hyprland and won't
  -- auto-select the libsecret backend — Element/Vesktop's desktop-entry
  -- overrides in ~/.local/share/applications/ pass
  -- --password-store=gnome-libsecret explicitly to work around that (not
  -- --password-store=basic, which is the actual weak/unencrypted fallback).
  hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
  hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'")
  hl.exec_cmd(programs.terminal)
  -- hyprpaper (this build) does not read hyprpaper.conf; the wallpaper must
  -- be set over its IPC socket after it starts up.
  hl.exec_cmd("quickshell & (hyprpaper & sleep 1; hyprctl hyprpaper wallpaper ',/home/mono/Pictures/wallpaper.jpg') & firefox")
  -- Apps toggled on in the launcher's Autostart folder (SUPER+SHIFT+Q ->
  -- Autostart) are launched with their own native "start minimized to
  -- tray" flag instead of appearing in front of you — see
  -- quickshell/scripts/autostart-launch.py.
  hl.exec_cmd("python3 \"$HOME/.config/quickshell/scripts/autostart-launch.py\"")
end)
