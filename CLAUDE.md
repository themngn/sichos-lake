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
- `install.sh` only ever copies forward — it never deletes a deployed file whose repo source was removed
  or renamed. Don't treat a file's presence under `$HOME` as proof it's still part of the current config
  — check the repo first.
- Practical workflow for a config edit: change it in the repo, then copy that same file to its deployed
  path (or re-run the relevant step of `install.sh`) so it's live immediately — Hyprland/quickshell both
  hot-reload on save, so this is the fast path to actually seeing the change, not an extra chore.
  Conversely, if a fix gets hand-tested by editing the deployed file directly first, port it back into the
  repo before considering the task done — a fix that only exists under `$HOME` is invisible to
  `install.sh` and will be lost/overwritten on the next deploy or reinstall.
- Repo path → deployed path is a flat mapping unless noted otherwise: `hypr/` → `~/.config/hypr/`,
  `quickshell/` → `~/.config/quickshell/`, `kitty/kitty.conf` → `~/.config/kitty/kitty.conf`,
  `qt6ct/qt6ct.conf` → `~/.config/qt6ct/qt6ct.conf`, `hyprquickframe/theme.toml` →
  `~/.config/hyprquickframe/theme.toml`, `fastfetch/` → `~/.config/fastfetch/`,
  `wallpaper/wallpaper.jpg` → `~/Pictures/wallpaper.jpg`. `zsh/` is the one non-flat exception:
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
  matching `install.sh` step for their real destination: `sddm/sichos/` →
  `/usr/share/sddm/themes/sichos/`, `sddm/10-theme.conf` → `/etc/sddm.conf.d/10-theme.conf`,
  `sddm/sysconfig-sddm` → `/etc/sysconfig/sddm` (XCURSOR_THEME/SIZE and WLR_NO_HARDWARE_CURSORS
  for cursor rendering). SDDM's Wayland greeter compositor is `cage` (`cage -s -d` in
  `10-theme.conf` — wlroots-based kiosk compositor with full native cursor support, replacing
  the upstream weston kiosk default which had no cursor rendering).

## Deploying / testing changes

- `./install.sh` — copies every config in this repo to its target under `$HOME` (idempotent,
  backs up any differing existing file as `<name>.bak`). System-level steps (packages,
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
  `misc`, `input`, `keybindings`, `window_rules`).
- **quickshell config** (`quickshell/`): once deployed to `~/.config/quickshell`, hot-reloads
  automatically on save.
- To manually verify a deployed change without a full reboot: `hyprctl reload` (Hyprland), or just save
  the `.qml` file (quickshell). Full-session things (SDDM/Plymouth/env vars read at Hyprland startup)
  need a reboot or `sudo systemctl restart sddm` — `install.sh`'s final output block spells out exactly
  which of its changes are already live vs. need one.
- `hyprctl eval 'hl.<call>(...)'` is how one-off Lua calls get injected into the running Hyprland
  instance from a script (see `quickshell/scripts/autostart-launch.py`) — `hyprctl dispatch exec` does
  **not** work on this Lua-config build (no bare global `exec`); only `hl.exec_cmd`/`hl.dsp.exec_cmd` do.

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

`shell.qml` is the entry point (`ShellRoot`), instantiating one `Bar {}` per screen plus singleton
top-level windows (`Launcher`, `VolumeOSD`, `Notifications`, `NowPlaying`). Everything else lives in
`quickshell/modules/`:

- **Singletons** (`pragma Singleton`): `Theme.qml` (colors/fonts, mirrors the old waybar palette),
  `ShellState.qml` (cross-window state — sunset mode/warmth, idle-inhibit — that both the per-screen
  `Bar` and the single `Launcher` need to see), `BarSettings.qml` (which right-side widgets are enabled
  and in what order, edited from the launcher's Settings > Bar Widgets folder), `AppIndex.qml`.
- **`Bar.qml`**: left section is workspaces/submap; center is the clock with sunset/idle toggles and
  weather flanking it; the right section is data-driven — `BarSettings.orderedIds()` picks which widgets
  render and in what order via a `Loader`/`Component` switch (`componentFor(id)`), so reordering/hiding a
  widget is a settings change, not a `Bar.qml` edit. Night Light (`SunsetToggle`) and Stay Awake
  (`IdleToggle`) are a fixed pair outside that system.
- **`Launcher.qml`** (942 lines, by far the largest file): the SUPER+SHIFT+Q app launcher/menu, including
  its Settings and Autostart folders.
- Python helper scripts (`quickshell/scripts/*.py`) are invoked as subprocesses by QML for anything
  better done outside JS — `list-apps.py` (enumerates installed `.desktop` entries as JSON),
  `autostart-launch.py` (launches user-selected autostart apps with each app's real "start minimized"
  CLI flag — see its own header comment for why this repo refuses compositor-side window-hiding hacks),
  `weather.py`, `claude-usage.py`, `agy-usage.py`.
- Config/state written by the launcher (e.g. `~/.config/quickshell/autostart-apps.json`) lives under the
  deployed `~/.config/quickshell` tree, not in this repo.

### Gamepad Overlay Daemon (`sichos-gamepad`)

A lightweight native C daemon (packaged via `mdukhota/test1` COPR as `sichos-gamepad`, < 2 MB RAM) that runs in the background via `hypr/autostart.lua`:
- **Guide / Home button (`BTN_MODE` or Select+Start / L3+R3)**: Toggles the Quickshell launcher overlay (`quickshell ipc call launcher toggleFull`).
- **Overlay Navigation**: While the launcher is open (tracked via `$XDG_RUNTIME_DIR/sichos-launcher.active`), grabs the gamepad (`EVIOCGRAB`) and emits virtual keystrokes via `uinput` (`KEY_UP`, `KEY_DOWN`, `KEY_LEFT`, `KEY_RIGHT`, `KEY_ENTER`, `KEY_ESC`, `KEY_PAGEUP`, `KEY_PAGEDOWN`).
- **In-Game Passthrough**: When the launcher is closed, gamepad events are released to pass through 100% untouched to games and emulators.
- **Hotplugging**: Monitors `/dev/input` via inotify to automatically detect when controllers are plugged in or connected over Bluetooth.

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
