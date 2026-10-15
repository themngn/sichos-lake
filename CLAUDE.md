# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

"SichOS" — a personal Hyprland desktop configuration for Fedora, deployed by `install.sh`. It is not
an application with a build step; it's config files (Lua for Hyprland, QML for the status bar/launcher,
Python/bash scripts) that get copied verbatim to `~/.config/...` and read live by running daemons.
There is no compiler, package manager, or test suite — "testing a change" means deploying it and
watching the real Hyprland/quickshell session react.

**This machine is the reference dev/test environment for this repo, not just a checkout of it.** The
distro is actively developed here: the running `~/.config/hypr`, `~/.config/quickshell`, etc. on this box
*are* the live proving ground for `sichos-lake`. A config change is only done when it exists in both
places — the repo file (what `install.sh` ships to every future machine) and the deployed file under
`$HOME` (what's actually running right now). Concretely:

- The deployed copies are **plain files, not symlinks** (`install_file()` in `install.sh` just `cp`s), so
  they don't stay in sync automatically and can silently drift. `monitors.lua` is the one file expected
  to differ permanently — it's genuinely per-machine (actual connected monitor names/positions), so the
  repo's copy is just a template, not something to reconcile. Before trusting any other file, diff it
  against the other copy rather than assuming they match.
- **`install.sh` and `sichos-setup.sh` are for the first install of a machine only** (packages, COPRs,
  sudo/system steps, interactive choices) — don't re-run them to pick up config changes. `UPDATING.md`
  is the user-facing description of everything below (update flow, live testing, version switching,
  system files, the Version tile) — keep it in step when `update.sh`'s behaviour changes. Updates go
  through `update.sh`, run automatically by the git hooks in `githooks/` (enabled by `git config
  core.hooksPath githooks`; `install.sh` sets it): after every commit, amend, pull/merge, rebase and
  branch switch in the main checkout it deploys whatever changed since the last deployed commit
  (`~/.local/state/sichos/deployed-rev`). It never overwrites a deployed file with local edits (the new
  version is parked under `~/.local/state/sichos/update-conflicts/` instead), removes files deleted
  from the repo only if unmodified, and carries over `install.sh`'s per-machine `--alt`/`--vm`/browser
  edits plus settings the UI stores inside deployed files (kitty's `background_opacity`,
  `hyprsunset.conf` times, `hypridle.conf` listeners). System files (SDDM, Plymouth, polkit,
  kernel-install, firewalld, root's zsh, new `packages.txt` entries) need sudo, so a hook only says
  so: `./update.sh system` applies them, same rules, tracked in `system-rev`, with install.sh's
  follow-ups (initramfs rebuild, boot-entry retitle, firewalld reload). `./update.sh switch <rev>`
  deploys any commit/tag/branch without a checkout and pins it (hooks stop following HEAD), `back` /
  `latest` / `list` / `status` — see its header. Not run from `git worktree`s, so working in one
  doesn't touch the live config; `git config sichos.autodeploy false` turns the hooks off.
  **`update.sh` is the only place that maps repo paths to deployed paths** — `install.sh` deploys
  every user config through `update.sh install` (desktop-overrides excepted: each depends on its app
  being selected). A new config file under an already-mapped directory needs nothing; a new location
  needs a `dest_for` (or `sys_dest_for`, plus the matching `install.sh` system step) case, and a new
  deploy-time patch or UI-written setting needs a `patch_like_deployed` case, or every update after it
  shows up as a "local edit". The Control Center's Version tile (`SichosVersion.qml`) shows the deployed
  commit from `update.sh info` (one JSON line; the checkout's path is recorded in
  `~/.local/state/sichos/repo`), re-read when update.sh pokes its `sichosversion` IPC target after a
  deploy and every 30s while the Control Center is open. Test changes to it with `SICHOS_SYSROOT`/`SICHOS_SUDO` and a sandbox
  `HOME` *and* `XDG_STATE_HOME` (set on this machine, so overriding `HOME` alone writes the real state).
- `install.sh` only ever copies forward — it never deletes a deployed file whose repo source was removed
  or renamed (`update.sh` does, for removals after the install). Don't treat a file's presence under
  `$HOME` as proof it's still part of the current config — check the repo first.
- Practical workflow for a config edit: change it in the repo, then copy that same file to its deployed
  path so it's live immediately (committing it deploys it too, via the hooks) — Hyprland/quickshell both
  hot-reload on save, so this is the fast path to actually seeing the change, not an extra chore.
  Conversely, if a fix gets hand-tested by editing the deployed file directly first, port it back into the
  repo before considering the task done — a fix that only exists under `$HOME` is invisible to
  `install.sh` and will be lost/overwritten on the next deploy or reinstall.
- Repo path → deployed path (implemented in `update.sh`'s `dest_for`/`sys_dest_for`) is a flat mapping unless noted otherwise: `hypr/` → `~/.config/hypr/`,
  `quickshell/` → `~/.config/quickshell/`, `kitty/kitty.conf` → `~/.config/kitty/kitty.conf`,
  `qt6ct/qt6ct.conf` → `~/.config/qt6ct/qt6ct.conf`, `hyprquickframe/theme.toml` →
  `~/.config/hyprquickframe/theme.toml`, `fastfetch/` → `~/.config/fastfetch/`, `fontconfig/` → `~/.config/fontconfig/`,
  `wallpaper/wallpaper.jpg` → `~/Pictures/wallpaper.jpg`, `nvim/init.lua` →
  `~/.config/nvim/init.lua`, `themes/pavucontrol-dark/gtk-4.0/gtk.css` →
  `~/.local/share/themes/pavucontrol-dark/gtk-4.0/gtk.css`, `desktop-overrides/*.desktop` →
  `~/.local/share/applications/*.desktop`, `autostart-overrides/nm-applet.desktop` →
  `~/.config/autostart/nm-applet.desktop`. `zsh/` is the one non-flat exception:
  `zsh/.zshrc` → `~/.zshrc`, `zsh/.zsh_plugins.txt` → `~/.zsh_plugins.txt`, `zsh/prompt.toml` →
  `~/.config/prompt.toml` (bare file, not under a subdirectory) — antidote has no dnf/COPR
  package and is installed manually (git clone) by the "==> zsh" `install.sh` step rather than
  via `packages.txt`. oh-my-posh is installed the same manual way (official installer script,
  pinned to `~/.local/bin`) even though Fedora does now package it — that package lags badly
  behind upstream (28.10.0 vs. 31.1.2 seen on this machine), so `install.sh` checks specifically
  for `~/.local/bin/oh-my-posh` rather than `command -v oh-my-posh`, which would match the stale
  system one first if it's ever installed (`~/.local/bin` does correctly precede `/usr/bin` in
  `PATH` once populated — confirmed on this machine);
  `~/.zsh_plugins.zsh` is antidote's own generated plugin bundle/cache, not tracked here. System-level
  targets (Plymouth theme, the polkit rule, SDDM) live outside `$HOME` entirely — see the
  matching `install.sh` step for their real destination: `plymouth/unlock/*` →
  `/usr/share/plymouth/themes/unlock/`, `polkit/49-sichos-timedate-locale.rules` →
  `/etc/polkit-1/rules.d/49-sichos-timedate-locale.rules`, `sddm/sichos/` →
  `/usr/share/sddm/themes/sichos/`, `sddm/10-theme.conf` → `/etc/sddm.conf.d/10-theme.conf`,
  `sddm/sysconfig-sddm` → `/etc/sysconfig/sddm` (XCURSOR_THEME/SIZE and WLR_NO_HARDWARE_CURSORS
  for cursor rendering). SDDM's Wayland greeter compositor is `cage` (`cage -s -d` in
  `10-theme.conf` — wlroots-based kiosk compositor with full native cursor support, replacing
  the upstream weston kiosk default which had no cursor rendering). `kernel-install.d/*.install` →
  `/etc/kernel/install.d/` (GRUB boot-menu branding — see its own header comment for why this
  retitles existing BLS entries in `/boot/loader/entries` instead of renaming `/etc/os-release`).
  `firewalld/localsend.xml` → `/etc/firewalld/services/localsend.xml` (only if firewalld is active).

`TODO.md` tracks known workarounds that aren't real fixes (e.g. the bar going opaque under HDR) — check
it before "fixing" something that looks odd but is deliberately worked around.

## Deploying / testing changes

- When hand-deploying several quickshell files at once, its hot-reload can fire mid-copy and fail on a
  half-copied tree (e.g. `X is not a type` for a file that hasn't landed yet). Check the log
  (`quickshell log "$(ls -t /run/user/$(id -u)/quickshell/by-id/*/log.qslog | head -1)"`) for
  "Configuration Loaded", and `quickshell ipc call shell reload` to reload again if it failed —
  `touch`ing `shell.qml` does **not** reload (the watcher reacts to content changes only; checked live).
  When a change adds new `Theme.qml` tokens, copy `Theme.qml` *first*: a reload that picks up the
  modules before the new Theme floods the log with `Unable to assign [undefined]` warnings. Only the
  output after the last "Reloading configuration..." line reflects the current files.

- **Measuring/inspecting UI offline.** A throwaway QML file can be run as its own quickshell instance
  (`timeout 10 quickshell -p /path/to/test.qml`) alongside the live one — keep it in the scratchpad, not
  the repo. Gotchas: `console.log` output doesn't show, use `console.warn`; a `Repeater` directly under
  `ShellRoot` creates nothing (it needs an Item parent), so wrap content in a `FloatingWindow`; render,
  then `item.grabToImage(r => { r.saveToFile(...); Qt.quit() })` from a `Timer`, and analyze the PNG with
  `magick ... -threshold 25% -trim -format "%@" info:` to get real pixel bounds (this is how
  `HeaderIcon`'s `_measured` table was produced: glyph at pixelSize 100, pen origin at a known x, baseline
  at `y + baselineOffset` = y+102 for JetBrainsMono Nerd Font Mono). Nerd Font codepoints above U+FFFF
  can be written as `"\u{f0590}"` in QML strings. Run such shell loops under `bash`, not the default zsh
  — zsh doesn't word-split unquoted `$VAR`, so `for c in $LIST` silently iterates once.
- **Screenshotting a real bar popup** without hovering: there's no IPC to open one, so temporarily add an
  `IpcHandler { target: "dbgpopup"; function open(id: string, screen: string): void { root.activePopup =
  id; root.activePopupScreen = screen } }` to the *deployed* `ShellState.qml` only, then
  `quickshell ipc call dbgpopup open weather DP-2` + `grim -g "x,y wxh" out.png` (popup ids are the
  modules' `popupId` strings: calendar, hdr, ai-model-usage, idle, gamefocus, mic, bluetooth, display,
  system-update, sunset, weather, quicksettings and its pages qs-*). An IPC-opened hover popup with no
  pointer over it closes after ~300ms (the hover close check), so grab within ~0.25s; the Control Center
  doesn't (it closes only on a click outside). Restore the deployed file from the repo afterwards and confirm with
  `quickshell ipc show` that `dbgpopup` is gone.
- `./install.sh` — first install only (see above): packages, repos, services and system steps, with
  every user config deployed by `update.sh install` (backs up any differing existing file as
  `<name>.bak`, records HEAD as deployed); ends by enabling the auto-update hooks and recording the
  system files' version. Needs a git checkout. System-level steps (packages,
  Plymouth, SDDM) run via `sudo` and prompt for a password. Flags: `--vm` (force software rendering
  for VM guests), `--alt` (SUPER → ALT as main modifier). Numerous `SKIP_*`/`SICHOS_*` env vars control
  optional steps (Flatpak apps, Telegram/Discord/Steam/Lutris/LibreOffice, git identity, SSH key/server,
  hostname/timezone/locale) — see the header comment block at the top of `install.sh` for the full list.
- `./sichos-setup.sh` — an interactive full-screen TUI (hand-rolled with raw ANSI escapes, not gum —
  gum's widgets can't coexist with a persistent sidebar) that lets you pick options across a series of
  steps (Hostname, Time & Region, Repositories, Option Packages, Gaming, Browser, Git, SSH, Debug,
  Finalize) and then `exec`s `install.sh` with the right env vars/flags. Nothing touches the system until
  "Install" is pressed on the Finalize step.
- **Hyprland config** (`hypr/*.lua`): once deployed to `~/.config/hypr`, Hyprland reloads automatically
  on save — no restart needed for most changes. Uses the Lua-config build of Hyprland from the
  `lionheartp/Hyprland` COPR (not the standard `hyprland.conf` format), split into per-concern files
  required from `hyprland.lua` (`monitors`, `autostart`, `env`, `permissions`, `look_and_feel`, `layouts`,
  `misc`, `input`, `keybindings`, `workspaces`, `window_rules`). `workspaces.lua` implements a dynamic
  workspace pool (SUPER+N binds, monitor hotplug, persisted state under `~/.local/state/sichos/`) —
  read its header comment before touching workspace behavior.
- **quickshell config** (`quickshell/`): once deployed to `~/.config/quickshell`, hot-reloads
  automatically on save.
- To manually verify a deployed change without a full reboot: `hyprctl reload` (Hyprland), or just save
  the `.qml` file (quickshell). Full-session things (SDDM/Plymouth/env vars read at Hyprland startup)
  need a reboot or `sudo systemctl restart sddm` — `install.sh`'s final output block spells out exactly
  which of its changes are already live vs. need one.
- `hyprctl eval 'hl.<call>(...)'` is how one-off Lua calls get injected into the running Hyprland
  instance from a script (see `quickshell/scripts/autostart-launch.py`) — `hyprctl dispatch exec` does
  **not** work on this Lua-config build (no bare global `exec`); only `hl.exec_cmd`/`hl.dsp.exec_cmd` do.
  `eval` runs in the same Lua VM as the config, so globals a config file defines are callable from it —
  that's how quickshell reaches logic that must stay in Lua (e.g. `SichosWorkspaces.moveToMonitor(id,
  "DP-1")` in `workspaces.lua`, used by the bar's workspace right-click menu). Dispatcher argument
  tables are undocumented in `/usr/share/hypr/stubs/hl.meta.lua`; constructing one with bad args
  (`hyprctl eval 'hl.dsp.workspace.move({})'`) returns an error naming the required fields, without
  dispatching anything.

## Architecture

### Hyprland (`hypr/`)

Lua config files, each owning one concern and `require()`'d from `hyprland.lua`. The load-bearing
subtlety across this whole config used to be that **`graphical-session.target` never activated** (it
predated the SDDM switch and wasn't specific to greetd's old autologin — the session launched via the
plain `hyprland.desktop` wayland-session entry, not a `uwsm`-managed one, so nothing bridged compositor
startup to systemd's user session targets). **That's no longer unconditionally true**: SDDM's session
picker remembers the last choice, and once `hyprland-uwsm.desktop` (`Exec=uwsm start -e -D Hyprland
hyprland.desktop`, also in `/usr/share/wayland-sessions/`) gets picked, uwsm properly bridges the
session and `systemctl --user is-active graphical-session.target` reports active — confirmed live.
Whether the plain `hyprland.desktop` entry is still ever selected (fresh installs, a user picking it
manually) is unverified, so treat target activation as session-dependent, not guaranteed either way.
Given that, xdg-desktop-portal(-hyprland/-gtk), hyprpolkitagent, hyprsunset, and hypridle were migrated
off plain-background-process launches onto their packaged `systemd --user` units (portals are
`Type=dbus`, activate on demand; the other three are `systemctl --user enable`d — done by `install.sh`,
right after the Hyprland config step) — see `autostart.lua`'s opening comment for the full rationale,
and `Bar.qml`'s `onScheduleSaved`/`onSettingsSaved` handlers (`SunsetToggle`/`IdleToggle`), which now
`systemctl --user restart` those two instead of the old manual `pkill; relaunch` dance. This only
actually starts anything under the uwsm-managed session — the units gate on
`ConditionEnvironment=WAYLAND_DISPLAY` in systemd's user-manager environment, and uwsm is specifically
what exports that; under the plain `hyprland.desktop` entry these stay inactive and nothing autostarts
them at all (no manual fallback anymore) — so the plain entry is no longer fully supported by this repo
unless someone reintroduces one. What target activation DOES also affect regardless of any of this:
`systemd-xdg-autostart-generator` unconditionally processes every `/etc/xdg/autostart/*.desktop` entry
once the target's active, independent of anything `autostart.lua` does — this is why an unrelated
package install can suddenly autostart something (e.g. `xwaylandvideobridge`, since removed) that never
used to run. See the Keyring section below for a case where this actually mattered (gnome-keyring's own
XDG autostart entries racing the manual keyring unlock) before that unlock got hardened against it. Read
`autostart.lua`'s comments before "fixing" something by pointing it back at systemd.
`install.sh`/`sichos-setup.sh` patch freshly-deployed
copies under `~/.config/hypr` in place for `--vm`/`--alt`/browser selection (via `sed`), never the repo's
own files.

### quickshell (`quickshell/`)

`shell.qml` is the entry point (`ShellRoot`). It uses `Variants` to create one `Bar`, `NowPlaying` and
`IdleDimOverlay` per screen, plus single top-level windows (`Launcher`, the `*OSD`s, `Notifications`).
Everything else lives in `quickshell/modules/`:

- **Singletons** (`pragma Singleton`): `Theme.qml` (palette plus the shared surface/type tokens — see
  "UI style" below),
  `ShellState.qml` (cross-window state that both the per-screen `Bar` and the single `Launcher` need to
  see — sunset, idle-inhibit, bar-solo screen, and `activePopup`/`activePopupScreen`, which allow only one
  toggle popup open at a time and only on the screen that opened it; also hosts `IpcHandler`s for
  `quickshell ipc call ...` from keybindings), `BarSettings.qml` (which right-side widgets are enabled
  and in what order, edited from the launcher's Settings > Bar Widgets folder), `AppIndex.qml`.
- **`Bar.qml`**: left section is workspaces/submap. The center is the clock, which sits at true screen
  center. To its left is a toggle row (`*Toggle.qml`, all built on `Pill.qml`: Sunset, HDR, Idle,
  GameFocus, Transparency, BarSolo, MicMute, NotificationMute). The row collapses to zero width and is
  revealed on hover. A new toggle must be added to `anyToggleHovered`, and to `toggleRowPopupOpen` if it
  has a popup, or the row will collapse out from under it. The right section is data-driven —
  `BarSettings.orderedIds()` picks which widgets render and in what order via a `Loader`/`Component`
  switch (`componentFor(id)`), so reordering/hiding a widget is a settings change, not a `Bar.qml` edit.
  The toggle row is fixed and outside that system. `QuickSettings.qml` (the "Control Center") is one of those widgets
  standing in for Network/Bluetooth/Volume/Backlight/PowerProfile/Battery/Display/Phone (disabled by
  default, still available individually), and also repeats the toggle row's switches as tiles (same
  state calls, the row itself stays). Its bar icons are those widgets instantiated with
  `Pill.interactive: false` (`enabled: false` isn't enough: Qt 6 still delivers hover to disabled
  items, so a nested pill swallows the outer one's hover). Its Bluetooth/Display submenus are hidden
  BluetoothIndicator/DisplaySettings instances with their own `popupId` (`qs-bluetooth`/`qs-display`),
  `popupAnchor` and `backPopupId`; its Sound page (`qs-audio`) is a second MorphContent in the same
  file, its Wi-Fi page (`qs-wifi`) is `WifiMenu.qml`. All of them morph the same card. It opens on
  click only and closes only on a click outside (HyprlandFocusGrab); while open,
  `ShellState.popupLockGroup` reverts any other popup's attempt to take over on hover.
  Text entry in a bar popup (Wi-Fi password, Bluetooth PIN) can't use a TextInput — a popup surface
  never gets keyboard focus — so the field sets `ShellState.keySink`/`keySinkScreen` and that screen's
  bar takes exclusive keyboard focus and forwards keys to `keySink.handleKey(event)`. That focus change
  makes Hyprland clear the Control Center's `HyprlandFocusGrab`, which used to close the card the moment
  a field opened — so its grab is suspended (`typing`) while a keySink on its screen is set. Bluetooth pairing
  goes through `scripts/bt-agent.py` (a BlueZ agent run by the `BluetoothAgent` singleton; nothing
  else registers one here, so code-based pairing used to fail). Quickshell's `WifiNetwork.signalStrength`
  is 0..1, not a percentage. Its tiles are Android-style editable (pencil in the header: drag to
  reorder, drag the right/bottom edge or corner to resize up to 4x2, remove/add -- by badge, click,
  or dragging a tile between the grid and the spare "Add tiles" list; tiles pack first-fit,
  and what a tile shows at each size -- header lines, inline control, a 2-row tile's body -- comes from
  `tileView(id, w, h)`; its `titleTail` is a short muted note after the title, e.g. a 1-row Wi-Fi
  tile 2+ wide shows the band, "Wi-Fi 5 GHz", from `NetInfo`, so the SSID keeps the status line).
  `~/Documents/sichos/control-center-tiles.html` is a sheet of every tile at every size, rendered
  offscreen from the deployed config by `~/Documents/sichos/tiles-gen/gen.sh` (deploy first) --
  regenerate it after every Control Center change. SUPER+N toggles it on the
  focused monitor (`quickshell ipc call controlcenter toggle`). The toggle-row popups (HDR, Night Light,
  Stay Awake, Game Focus) and System Update are also its pages (`qs-hdr` etc.) — its own instances with
  `backPopupId` set. `SystemStats` (CPU/RAM/temp) only polls while its main page is open; `VpnStatus` (Proton VPN) while
  that or its VPN page is. The VPN page (`VpnPage.qml`, `qs-vpn`, the VPN tile's chevron) drives Proton's
  own CLI, which the Flatpak ships beside the GUI (`flatpak run --command=protonvpn com.protonvpn.www`,
  sharing the app's sign-in, `settings.json` and server cache): connect (= the last server, from the
  app's/CLI's logs, so ones picked in the app count; fastest if none) / profiles / favorites (a star on
  any country or server row) and recent servers (both in `~/.config/quickshell/vpn-recent.json`) / country → city → server picker with search, and the settings `config set` can change
  (the protocol isn't one -- that stays in the app). State still comes from nmcli's active "ProtonVPN
  <server>" connection, so connections made in the app show too. The app's 26 MB `serverlist.json` is
  summarised by `scripts/vpn-servers.py` (countries, then one country's servers on expand). The tile layout is the `ControlCenterTiles` singleton
  (`~/.config/quickshell/control-center.json`), a ListModel rather than a JS array so a live
  reorder moves delegates instead of rebuilding them mid-drag. Its switches persist: Stay Awake, Silence (with a
  timed mute's deadline), Night Light on/off + Follow schedule, and Bluetooth on/off (BlueZ's AutoEnable
  re-powers it every boot otherwise) in `~/.config/quickshell/shell-state.json` (`ShellState`), Game Focus in
  `game-focus.json`, Lid Close (sleep / screen off when another monitor is connected; `LidSettings`, read by
  `hypr/keybindings.lua`'s lid binds on every close) in `lid-close.json`, HDR in `hdr-monitors.json` (re-applied after every Hyprland `configreloaded`, which
  resets monitor rules); everything else is kept by its own owner (NetworkManager, WirePlumber,
  power-profiles-daemon, systemd-backlight, `hyprsunset.conf`/`hypridle.conf`, `monitors.lua`). A new
  setting needs the same. Night Light never re-sends hyprsunset's own schedule switch (that showed as a
  double toggle) -- `ShellState._syncSunset` pushes only when hyprsunset's actual temperature disagrees. A new tile = an id in its `allIds`
  plus a case in QuickSettings' `tileInfo()`/`tileToggle()`, per-size content in `tileView()` (and its glyph measured into HeaderIcon). **Bar hover popups don't own windows**: the toggle
  row's, the clock's calendar, Weather, the right-side widgets with hover popups (AI usage, Bluetooth,
  System Update, Display) and custom widgets that opt in (alert-widget) all render a `MorphContent`
  into the bar's one `MorphPopup` card. Each widget assigns its content to a property (not a child —
  `Pill`'s default property would lay it out inside the pill), sets `parent: root.popupHost` (passed
  down from `Bar.qml`; `CustomWidget` forwards `popupHost`/`screenName` to the loaded widget) and drives
  `shown`. While one is open, hovering another slides/reshapes that card into the next popup instead of
  swapping windows. Content inside it must not use `<popup>.visible`/`.screen` (it's an Item now —
  use `shown`), and coordinates map into the shared surface (`mapToItem(null, …)`). Click menus (tray,
  language, workspace) and the notification drawer still use their own windows. A new toggle-row popup
  also needs its popupId in `toggleRowPopupOpen`.
- **`Launcher.qml`** (by far the largest file): the SUPER+SHIFT+Q app launcher/menu, including
  its Settings and Autostart folders. While the paired phone is connected, the root menu has a folder
  named after it right under Apps (not inside it, so SUPER+Q's Apps view stays PC-only): the phone's launcher apps with their icons (`PhoneApps` singleton ← `sichlink apps`,
  ~5s since the phone draws every icon, so the last list is cached in `$XDG_RUNTIME_DIR` and refreshed
  on each open; searched locally inside the folder; in a global search always after every PC result, whatever
  their rank, with a phone badge on the icon). Picking one
  runs `PhoneMirrorState.launchApp`: starts or shows the mirror and `phone-mirror.sh launch <pkg>`
  (resolves the launcher activity over adb; on a locked phone it waits behind the keyguard until the
  mirror's wake loop unlocks it).
- **`ClipboardPicker.qml`** (SUPER+SHIFT+V, cliphist history with image thumbnails) and
  **`EmojiPicker.qml`** (SUPER+PERIOD, Android-style grid with category tabs, Recent and per-emoji
  remembered skin tones in `~/.config/quickshell/emoji-recent.json`) are separate windows on a shared
  `PickerWindow.qml` (the launcher's card + search field), deliberately not launcher folders. IPC
  targets `clipboard`/`emoji` (`toggle`, `close`). They replaced fuzzel pickers — fuzzel's fcft
  can't render Fedora's COLRv1 Noto Color Emoji at all.
- **`PowerMenu.qml`**: Lock/Suspend/Log Out/Reboot/Shut Down, opened by the laptop power key
  (`XF86PowerOff` bind → `quickshell ipc call power toggle`, falling back to `hyprshutdown`). The key
  only reaches Hyprland because `autostart.lua` holds a logind `handle-power-key` inhibitor
  (`systemd-inhibit … sleep infinity`) — otherwise logind's default `HandlePowerKey=poweroff` shuts
  the machine down by itself. No root/logind.conf drop-in involved.
  Log Out/Reboot/Shut Down (also the launcher's Power folder, via `quickshell ipc call power run
  <id>`) don't use hyprshutdown's UI: the card sends every window a close request, lists the ones
  still open with app icons, and runs `systemctl reboot`/`poweroff` (or `hl.dsp.exit()`) once they're
  gone or after a 3-second countdown, Esc cancelling. hyprshutdown (themed by `hypr/hyprtoolkit.conf`)
  is only the keybinding's fallback and `system-update-run.sh`'s reboot.
- **Phone mirror** (bar widget `PhoneMirror.qml`, `PhoneMirrorState.qml`, per-screen
  `PhoneMirrorPanel.qml`, `scripts/phone-mirror.sh`; SUPER+X show/hide, SUPER+SHIFT+X disconnect): a
  real scrcpy Hyprland window (pinned, docked to the left or right monitor edge, styled by spawn rules)
  plus quickshell surfaces lined up with it — loading card, controls card underneath, collapsed edge
  tab, "type your PIN" and "screen off" cards. Collapse slides the window past every monitor's outer
  edge, then unpins it: Hyprland pulls an off-screen window back on-screen whenever it moves it between
  workspaces, and pinned windows get moved on every switch (a hidden special workspace fails the same
  way). Expand re-pins it while still off-screen, then slides it in. Rendering the phone *inside*
  quickshell was also evaluated (scrcpy `--v4l2-sink` → QtMultimedia `Camera`): the video works, but
  input would need a custom scrcpy control client. A test viewer that falls back to the default camera
  opens the real webcam — always select the loopback device explicitly. The script's header comments
  record the Android-side findings (fingerprint "alternate bouncer", what keeps the PIN pad awake).
  The script pins one adb serial (USB if plugged in, else `sichlink adb-serial`) since one phone shows up
  as several adb entries; `phone-mirror.sh shell …` is how PhoneMirrorState's own long-lived `adb shell`s
  (PIN relay, power watch) get that same serial. Locked phone: the wake loop types a saved PIN once
  the PIN pad is up (login keyring, `secret-tool … sichos phone-pin`, handed over on stdin, never argv
  on the PC; saved by the PIN card's "Remember on this PC" only after it really unlocks, forgotten
  after one rejection to stay clear of Android's lockout, Forget on the Phone page), else the
  card relays typed keys. If the mirror found the phone locked, closing it (not hiding) locks it again
  (KEYCODE_SLEEP locks at once, unlike POWER). The wake loop starts with `open` (in parallel with
  scrcpy starting) and reports state 2 while unlocking: PhoneMirrorPanel's opaque lock cover hides
  the lock screen (put up early from sichlink's last lock state, so it doesn't flash by during the
  slide-in), steps PIN dots, and on unlock pops the lock open and slides off; the loop already
  counts the PIN pad closing as unlocked, ~1s before the keyguard finishes. The phone-side loop is
  one single-quoted string — an apostrophe in its comments once broke it. `open` gets its serial
  from `sichlink connect` (fresh, not the daemon's cached one). A fresh window on an awake, static
  phone stayed grey (no frame after the first); the first `expand` sends the sichlink app's NUDGE
  broadcast (invisible 1px overlay) a second in. The phone can ask for the mirror (app button / QS
  tile → `{"event":"mirror"}` on `sichlink watch` → `Sichlink._event` opens or expands it). So the phone in hand stays behind its fingerprint;
  only the mirror unlocks it — unlike Extend Unlock (below), which is the optional "always unlocked
  near this PC" mode. Controls card, left to right: side swap/collapse, PC
  audio | volume rocker | back, home, recents | power | close, collapse/swap, with dividers between the
  groups. The card is only as wide as the phone (~494px on a 1200px screen), so `buttonWidth` narrows the
  buttons to fit nine slots. In landscape (`wide`) the card is as wide as the landscape window: the volume
  rocker becomes two buttons side by side and `buttonSpacing` spreads the buttons evenly (max 48px). Volume: one slot split up/down; click = one step, hold = repeat
  (`PhoneMirrorState.startKeyRepeat`: one `adb shell` loop on the phone, killed on release — killing
  the local adb client ends the remote loop, checked with `ps` on the phone), mouse wheel = one step per
  notch. Power: click = KEYCODE_POWER (26), long press = `input keyevent --longpress 26` (power menu);
  `PhoneMirrorState.key(code, longPress)` → `phone-mirror.sh key [--longpress] <code>`. Every key is an
  `input keyevent` on the phone, ~0.3s each. Landscape apps: the power watch (one `adb shell` loop, 1s) also reads the
  display's current size (` cur=WxH` in `dumpsys window displays`; wider than tall = landscape —
  not the first `mDisplayRotation`, a config override that stayed ROTATION_0 with a game sideways); `PhoneMirrorState.geom` is the
  window size for the current orientation (portrait = full height; landscape = 60% of the screen's
  width), applied by `phone-mirror.sh layout` (resize + re-dock) or on `expand` if it turned while
  hidden, and every PhoneMirrorPanel surface sizes from it — the controls card and tab sit at
  `controlsTop`, right under the window, not anchored to the screen bottom. In landscape only (portrait always
  takes the full height), a grip on the window's inner bottom corner (its own overlay layer surface,
  frozen in place while dragged so the drag's coordinates don't move under it) scales the mirror:
  `PhoneMirrorState.setShare` stores its share of the screen width (0.3 up to edge to edge;
  double-click = `toggleMax`, largest size and back) in
  `~/.local/state/sichos/phone-size.json`; while held, `layout … fast` resizes at ~25fps with window
  animations off, and the release's normal `layout` puts the spring back.
- **Phone** (`Sichlink.qml` singleton, `PhonePage.qml` = Control Center page `qs-phone`, tile id `phone`):
  front end for the sichlink daemon — a separate repo (`~/Work/sichlink`, see its README: Android app + Rust
  `sichlink` daemon/CLI, `systemd --user` unit `sichlink`) that pairs phones over TLS, connects wireless adb
  on demand only (the mirror's `sichlink connect` turns wireless debugging on; PhoneMirrorState keeps a
  `sichlink adb-hold` running while the mirror or its audio is up; ~30s after the last hold the daemon
  disconnects and turns wireless debugging off again, unless the app's "Keep on" is set; display mode
  connects and holds it the same way — so `adb` reads `idle` most of the time, and phone-mirror.sh
  commands that don't need adb skip the serial lookup, or a status poll would bring adb up), reports the phone's lock state, and can wake/unlock it (optional
  Extend Unlock mode: the app holds an RFCOMM link so the PC counts as a connected trusted device). One
  tile for everything phone: label = the phone's name, subtitle = mirror state or `Sichlink.stateText` plus battery,
  click (or chevron) opens the page; a 2-row tile adds the state line (lock · adb ·
  Bluetooth), no buttons. The old separate "link" (Phone Link) tile id is gone —
  `ControlCenterTiles._fill` maps a saved one onto "phone". The page: header switch = the daemon
  (`systemctl --user enable/disable --now`), a card for the paired phone (a phone-shaped preview of its
  wallpaper at its real screen ratio, battery, chips;
  Unpair -- battery/wallpaper/screen size come from sichlink's `battery`/`wallpaper` messages, the
  wallpaper as a JPEG under `$XDG_RUNTIME_DIR` reloaded on `wallpaper_rev`), a Mirror section (explicit
  actions, no toggle: Start mirror, then Show/Hide + Stop; phone audio while open, saved PIN --
  Set/Change typed on the page via `ShellState.keySink`, stored by `phone-mirror.sh store-pin` without
  verification -- and Forget, dock side), a Display section (`Sichlink.setDisplay` → `sichlink
  display on|off`: the phone as an extra monitor -- a Hyprland headless output `SICHLINK-1` streamed
  to the app, touch = mouse; implemented in the sichlink repo, needs `wf-recorder`; `display on`
  blocks until the phone shows it, up to a minute while it waits to be unlocked), a Drive section
  (`Sichlink.setDrive` → `sichlink mount|unmount`: the phone's storage at `~/Phone` via sshfs over
  sichlink's own TLS, no adb, works locked; the daemon remounts it whenever the phone is back, so
  `mount`/`mounted` in the watch stream are "set up" vs. "there now"; Open runs nautilus directly,
  since `inode/directory`'s default can be anything -- VS Code had it here; needs `fuse-sshfs`), a
  Notifications section (the daemon shows the phone's notifications as ordinary ones through
  Notifications.qml's server; `sichlink notifications on|off|mute|unmute <pkg>|allow`: the
  on/off switch, an "Allow" row when the app lacks notification access -- granted over adb --, and a
  "Choose" list of every app that has sent one with a switch each, settings kept per phone by the
  daemon; a toast click invokes the "default" action = open it on the phone + the mirror), other
  phones to pair (shows the code) or unpair. Without the daemon the
  page still offers the mirror (USB). State is streamed from `sichlink watch` (JSON lines, no polling;
  retried every 3s while the Control Center is open, 30s otherwise, when the daemon is down); `{"event":
  "mirror"}` lines (the phone asked) open/expand the mirror. Not deployed by `install.sh` yet; the
  binary lives in `~/.local/bin`, which isn't on quickshell's PATH (inherited from Hyprland), so
  `Sichlink.cmd()` and `phone-mirror.sh` look there explicitly.
- Python helper scripts (`quickshell/scripts/*.py`) are invoked as subprocesses by QML for anything
  better done outside JS — `list-apps.py` (enumerates installed `.desktop` entries as JSON),
  `autostart-launch.py` (launches user-selected autostart apps with each app's real "start minimized"
  CLI flag — see its own header comment for why this repo refuses compositor-side window-hiding hacks),
  `weather.py` (IP-geolocated Open-Meteo current/8-hour/7-day forecast incl. per-hour `isDay` for
  night icons; caches to `~/.config/quickshell/weather-cache.json`, which `Weather.qml` reads on startup
  — `Weather.qml`'s "This week" range bars all share one week-wide min..max scale so days compare at a
  glance, iOS-style, with a dot for the current temperature on today's bar), `claude-usage.py`, `agy-usage.py`, `save-monitor-config.py` (writes the Display
  widget's changes, including VRR, back into the deployed `~/.config/hypr/monitors.lua`),
  `clipboard-list.py` (cliphist history as JSON, image entries decoded once into a thumbnail cache
  under `$XDG_RUNTIME_DIR/sichos-clipboard/`).
- **Custom widgets** (`CustomWidget { name: "..." }`, `modules/CustomWidget.qml`) load
  `~/.config/quickshell/custom/<name>/main.qml` — user-local, often a symlink to a dir outside this repo
  (e.g. `alert-widget` → `~/Work/alert-widget`). To use shared modules from such a file, `import
  qs.modules`: it resolves to the *same* singleton instances the shell uses (verified in a throwaway
  instance with the same symlinked layout — one `Theme` creation, same identity). A relative `import
  "../../modules"` does **not** work: `pragma Singleton` isn't honored for a URL-loaded file outside the
  config's import scan, so `Theme.*` reads `undefined`. The Loader resolves its source only once — editing
  a custom widget needs a full quickshell restart (`quickshell kill; hyprctl eval
  'hl.exec_cmd("quickshell")'`), not a hot-reload.
- Config/state written by the launcher (e.g. `~/.config/quickshell/autostart-apps.json`) lives under the
  deployed `~/.config/quickshell` tree, not in this repo.
- **Notifications** are split three ways: `Notifications.qml` is the `NotificationServer` and the live
  toasts (including grouping consecutive same-app+summary notifications into one toast while it's on
  screen) — drawn on **every screen** (a toast window per screen via `Variants`), with hidden/hover state
  shared by notification id so closing or hovering a toast on one screen applies to all; `NotificationHistory.qml` (singleton) is the persisted history in
  `~/.config/quickshell/notification-history.json`, with its own folding of consecutive repeats, plus
  a non-persisted registry of live `Notification` objects so a history entry can still invoke its
  sender's actions; `NotificationCenter.qml` is the bar bell + drawer. Clicking a toast or center entry
  runs the notification's `default` action, else `NotificationHistory.focusOrLaunchApp()`. Phone notifications (sichlink) get a
  `PhoneBadge.qml` on their icon, recognised by their app icon path under `~/.cache/sichlink/notification-icons/`. A Notification
  Center entry of one has a bell button that mutes/unmutes its app (`Sichlink.muteApp` → the phone's own list, also
  edited in the sichlink app's "Choose apps" and the Phone page).

#### UI style

Every popup, OSD, the launcher and notifications share one card style driven entirely by `Theme.qml`
tokens (`surface*`, `control*`, `hoverFill`/`selectedFill`, `track*`, `card*`, `surfacePadding`,
`sectionSpacing`, `open*`) — new UI should use those tokens, not color/radius/size literals. Surface
cards are `Squircle.qml` (continuous corners via QtQuick.Shapes; `radius: Theme.surfaceSquircleRadius`,
`Theme.cornerSmoothing`, and `borderColor`/`borderWidth` instead of `border.*`), not `Rectangle` —
controls inside them stay plain `controlRadius` Rectangles. Conventions
the existing popups follow: header = `HeaderIcon { glyph: ... }` + bold title at `fontSize` in a `Row`;
body text, buttons and checkboxes at `fontSize - 1`; section headings `fontSize - 2` in `textMuted`;
captions `fontSize - 3`. Text uses `Theme.uiFontFamily` (Inter); anything that renders Nerd Font glyphs
must keep `Theme.fontFamily` (Inter has none of them). The bar itself stays on the Nerd Font.

**Nerd Font glyph sizing/centering.** Nerd Font Mono icons don't share an ink-to-em ratio and sit on
the text baseline, so a plain `Text` at a given `pixelSize` reads smaller than adjacent text and visibly
low, and different glyphs at one `pixelSize` look different sizes. The bar solves this with
`BarIcon.qml` + `Theme.barIconInkHeight`; popup headers with `HeaderIcon.qml`, which fits each glyph's
*ink* into a `Theme.headerIconSize` box (an ink height, not a font size; width capped at 1.1×) and
centers it — for bold Inter the title's line-box middle and cap-height middle coincide within 0.25px, so
plain Row centering then lines icon and title up. Don't trust `TextMetrics.tightBoundingRect` for these
glyphs: its top is correct but its **bottom is clamped to the baseline**, so glyphs whose ink ends above
it (cloud, gamepad) get measured too tall and render small and high; its width is also just the advance
(every glyph reports 60 at 100px). `HeaderIcon` therefore carries a `_measured` table of real ink bounds
(at pixelSize 100, relative to pen origin/baseline) for every header glyph in use, falling back to
`tightBoundingRect` for unknown ones — **a new header glyph must be measured and added to that table**
(see "Measuring/inspecting UI offline" below).

Bar popups are hover-driven (`ShellState.activePopup`, one open at a time). A click-driven one (e.g.
`WorkspaceMenu.qml`) uses `HyprlandFocusGrab`, activated a tick *after* the window shows — bound
straight to `visible`, the grab can silently fail to take and the menu never closes — plus a
hover-leave close as a fallback. Open animation is `SurfaceAppear { target: <card>; shown:
<window>.visible }` inside the card; closing is deliberately instant.

### Gamepad Overlay Daemon (`sichos-gamepad`)

A lightweight native C daemon (packaged via `mdukhota/test1` COPR as `sichos-gamepad`, < 2 MB RAM) that runs in the background via `hypr/autostart.lua`:
- **Guide / Home button (`BTN_MODE` or Select+Start / L3+R3)**: Toggles the Quickshell launcher overlay (`quickshell ipc call launcher toggleFull`).
- **Overlay Navigation**: While the launcher is open (tracked via `$XDG_RUNTIME_DIR/sichos-launcher.active`), grabs the gamepad (`EVIOCGRAB`) and emits virtual keystrokes via `uinput` (`KEY_UP`, `KEY_DOWN`, `KEY_LEFT`, `KEY_RIGHT`, `KEY_ENTER`, `KEY_ESC`, `KEY_PAGEUP`, `KEY_PAGEDOWN`).
- **In-Game Passthrough**: When the launcher is closed, gamepad events are released to pass through 100% untouched to games and emulators.
- **Hotplugging**: Monitors `/dev/input` via inotify to automatically detect when controllers are plugged in or connected over Bluetooth.

### cage patch (multi-monitor SDDM login)

Stock `cage` (SDDM's Wayland greeter compositor, see above) always maximizes every client
toplevel to the *union* of every connected monitor's geometry — confirmed in its source
(`view.c`'s `view_position()`: `wlr_output_layout_get_box(layout, NULL, box)`, unconditionally,
no per-output placement exists anywhere in cage). This breaks any client that fullscreens one
toplevel per screen on its own output, which is exactly what SDDM's greeter does
(`GreeterApp::addViewForScreen`: `setScreen()` then `showFullScreen()` — confirmed via SDDM's own
source this *does* send `xdg_toplevel::set_fullscreen(output)` with that specific output). Result
on a real multi-monitor machine: the login screen gets stretched across the combined resolution of
every monitor instead of each screen showing its own correctly-cropped background — confirmed live
across a 3-monitor L-shaped layout (two side by side, laptop panel below-left,
`hypr/monitors.lua`), including a debug build that showed each of SDDM's own per-screen QML views
only ever knows about *its own* screen (`screenModel` is deliberately scoped per-view — see SDDM's
own `GreeterApp.cpp` comment — so no amount of QML/theme changes can work around this; it has to be
fixed in the compositor).

`cage/cage-fullscreen-per-output.patch` fixes this at the source — the smallest possible change
(three files: `view.h`/`view.c`/`xdg_shell.c`) that makes `set_fullscreen()` actually read and
remember the client-requested output (by name, not a cached pointer, to stay safe across output
hotplug) and use *that* output's box instead of the union. `install.sh`'s `==> SDDM` step builds
this fresh each time from whatever cage version Fedora currently ships (`dnf download --source
cage`), rather than a version pinned in this repo, so it keeps working across Fedora version
bumps without needing to be updated here — if the patch ever stops applying because upstream's
`view.c`/`xdg_shell.c` changed structurally, the build fails loudly (visible `rpmbuild` error)
rather than silently keeping an old, unpatched cage. No upstream fix exists as of this writing;
the same commit also lives on a fork for reference: https://github.com/themngn/cage, branch
`fullscreen-per-output`.

### Keyring / Electron apps

A recurring theme across `install.sh`, `autostart.lua`, and `packages.txt`: Electron apps' `safeStorage`
(Element, Vesktop) needs `org.freedesktop.secrets` reachable or they show a blocking dialog on every
launch. `autostart.lua` manually unlocks `gnome-keyring-daemon` with a blank passphrase every boot —
originally a holdover from greetd's old autologin (no password prompt, so PAM's own
`pam_gnome_keyring.so` auto-unlock never ran), it was briefly removed on the theory that SDDM's real
password login would make it redundant (`/etc/pam.d/sddm` does list `pam_gnome_keyring.so` in both its
`auth` and `session` stages). **That theory tested false against a real reboot+login**: `journalctl -b 0`
showed zero `pam_gnome_keyring` activity, and the first thing to touch `org.freedesktop.secrets`
afterward D-Bus-activated a bare daemon with nothing already running — instead of a real "login" keyring,
gnome-keyring fell back to interactively prompting for a brand-new "Default keyring" *and* rewrote the
`default` alias file to point at that instead of "login", so it kept prompting on every subsequent access
too (apps resolve the "default" alias, not the literal name "login"). PAM integration with gnome-keyring
just doesn't work under this SDDM setup — full stop, not an autologin artifact. So the manual unlock is
back for good, blank passphrase and all (the stray "Default keyring" got backed up as
`Default_keyring.keyring.bak-<timestamp>` under `~/.local/share/keyrings/`, alias reset back to "login").
The other two pieces are unrelated to any of this and always needed regardless: a `flatpak override
--talk-name=org.freedesktop.secrets` for Element/Vesktop in `install.sh`, and a desktop-entry override
(`desktop-overrides/*.desktop`) adding `--password-store=gnome-libsecret` (Chromium doesn't recognize
`XDG_CURRENT_DESKTOP=Hyprland` and won't auto-pick that backend otherwise) — touching only one of the
three reintroduces the dialog.

## Conventions

- Every non-obvious decision is explained with an inline comment at the point of change, often citing
  what was tried/observed (error text, `strings`/`busctl` output, a specific race) — match this level of
  detail when adding similarly non-obvious logic; don't add comments that just restate what the code does.
- `install_file()` (in `install.sh`) is the standard pattern for deploying any plain config file: back up
  a differing existing destination as `.bak`, then copy. Reuse it rather than hand-rolling `cp`/`cmp`.
  New config to deploy should be threaded through both `install.sh` (add an `install_file` call or extend
  an existing loop) — new interactive options additionally need `sichos-setup.sh` wiring (an `ITEM_TARGET`/
  `DEBUG_TARGET`/etc. entry and its render/activate/env-arg handling).
- New optional apps go in `sichos-setup.sh`'s `ITEM_TARGET`/`ITEM_DESC`/`ITEM_GROUP` maps (Option
  Packages) or `GAMING_*` (Gaming step) — verify the Flatpak app ID actually exists (e.g. `flatpak search`)
  before adding it rather than trusting memory. Prefer Flatpak (`FLATPAK:<app-id>`) over a new DNF
  package unless there's a concrete reason to want native (see Steam's own comment in `install.sh` for
  what that reason looks like).
- Only add an app to autostart-with-minimize (`autostart-launch.py`'s `MINIMIZE_FLAGS`) if it has a real,
  verified CLI flag for starting minimized/hidden — never a compositor-side "hide the window" workaround.
