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
  -- pam_gnome_keyring (session hook in /etc/pam.d/login) already started the
  -- keyring daemon and exported SSH_AUTH_SOCK/GNOME_KEYRING_CONTROL into this
  -- shell's environment; push them into systemd --user and D-Bus activation
  -- environment too, since D-Bus-activated apps (e.g. some GTK/Flatpak apps)
  -- won't otherwise see them.
  hl.exec_cmd("systemctl --user import-environment SSH_AUTH_SOCK GNOME_KEYRING_CONTROL; dbus-update-activation-environment --systemd SSH_AUTH_SOCK GNOME_KEYRING_CONTROL")
  hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
  hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'")
  hl.exec_cmd(programs.terminal)
  -- hyprpaper (this build) does not read hyprpaper.conf; the wallpaper must
  -- be set over its IPC socket after it starts up.
  hl.exec_cmd("quickshell & (hyprpaper & sleep 1; hyprctl hyprpaper wallpaper ',/home/mono/Pictures/default.png') & firefox")
end)
