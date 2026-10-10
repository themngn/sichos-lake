#!/usr/bin/env python3
"""Print the monitor name the focused window is on if that window is a game.

One-shot, run by GameFocus.qml on every relevant Hyprland event (focus change,
window move/close, monitor focus change) while Gaming Focus is enabled.
Prints `{"monitor": "<name>"}`, or `{"monitor": ""}` when the focused window
isn't a game (or nothing is focused).

Class names alone aren't enough to spot a game: Proton titles do show up as
`steam_app_<id>`, but native Linux Steam games, Lutris (Wine or native) and
Heroic titles keep whatever class the game/engine sets. What they all do share
is the environment their launcher hands the game process, which the window's
own pid inherits -- so /proc/<pid>/environ is the primary signal:
  - SteamGameId / SteamAppId: Steam sets these for every launched title,
    including non-Steam shortcuts. The Steam client's own window doesn't carry
    them (checked live against its pid), so it isn't misdetected.
  - LUTRIS_GAME_UUID: Lutris tags every game process with this (it uses it
    itself to find the game's pids -- lutris/runners/runner.py).
  - HEROIC_APP_NAME: Heroic's launch env (strings in its app.asar).
Hyprland's own contentType == "game" (wp_content_type_v1, or a `content`
window rule) is honoured too, as the manual escape hatch for anything else.
"""
import json
import re
import subprocess

GAME_ENV_KEYS = ("SteamGameId", "SteamAppId", "LUTRIS_GAME_UUID", "HEROIC_APP_NAME")
GAME_CLASS_RE = re.compile(r"^(steam_app_\d+|gamescope)$")


def hyprctl(*args):
    out = subprocess.run(["hyprctl", *args, "-j"], capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return None


def env_marks_game(pid):
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            entries = f.read().split(b"\0")
    except OSError:
        return False
    for entry in entries:
        key, _, value = entry.decode(errors="replace").partition("=")
        # Steam leaves SteamAppId=0 in some child envs that aren't a game.
        if key in GAME_ENV_KEYS and value not in ("", "0"):
            return True
    return False


def is_game(win):
    if win.get("contentType") == "game":
        return True
    if GAME_CLASS_RE.match(win.get("class") or ""):
        return True
    pid = win.get("pid") or 0
    return pid > 0 and env_marks_game(pid)


def main():
    win = hyprctl("activewindow")
    monitor = ""
    if isinstance(win, dict) and win.get("address") and is_game(win):
        for m in hyprctl("monitors") or []:
            if m.get("id") == win.get("monitor"):
                monitor = m.get("name", "")
                break
    print(json.dumps({"monitor": monitor}))


if __name__ == "__main__":
    main()
