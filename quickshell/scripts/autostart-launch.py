#!/usr/bin/env python3
"""Launches the apps toggled on in the launcher's Autostart folder
(~/.config/quickshell/autostart-apps.json, written by AutostartApps.qml).

Run from hypr/autostart.lua on Hyprland startup. Each app is launched with
its own native "start minimized to tray" flag (checked against each app's
--help output) rather than a generic Hyprland-side "hide the window"
trick — a real minimize looks/behaves right (tray icon, no taskbar/dock
flash) where forcing the window onto a hidden special workspace would
just be a blunt compositor-side hack.
"""
import json
import os
import subprocess
import sys

HOME = os.path.expanduser("~")
CONFIG_PATH = os.path.join(HOME, ".config", "quickshell", "autostart-apps.json")
LIST_APPS = os.path.join(HOME, ".config", "quickshell", "scripts", "list-apps.py")

# Verified via each app's own --help/docs: Telegram and Steam take a
# single-dash flag, Element/Vesktop/Discord (all Electron) take
# double-dash flags.
#
# The --password-store=gnome-libsecret keyring fix (Chromium doesn't
# recognize XDG_CURRENT_DESKTOP=Hyprland, so it needs the backend named
# explicitly even once a real keyring service is running) is NOT here —
# it's baked into each app's own desktop entry override in
# ~/.local/share/applications/ instead, so it also applies to a normal
# manual launch from the app grid, not just this autostart path.
MINIMIZE_FLAGS = {
    "Telegram": "-startintray",
    "Element": "--hidden",
    "Vesktop": "--start-minimized",
    "Discord": "--start-minimized",
    "Steam": "-silent",
}


def with_minimize_flag(exec_, flag):
    if not flag:
        return exec_
    # Flatpak-exported desktop entries wrap the file/URL argument in
    # "@@u ... @@" (flatpak-run(1), desktop-file-forwarding) — splice the
    # flag in before that marker so it reaches the sandboxed app as a
    # real argument instead of landing inside the forwarding block.
    if " @@u " in exec_:
        return exec_.replace(" @@u ", f" {flag} @@u ", 1)
    # Native (non-flatpak) desktop entries here end in a bare "--"
    # separator; splice the flag in before it for the same reason.
    if exec_.endswith(" --"):
        return exec_[: -len(" --")] + f" {flag} --"
    return f"{exec_} {flag}"


def lua_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


try:
    with open(CONFIG_PATH, encoding="utf-8") as f:
        enabled = set(json.load(f).get("enabled", []))
except (FileNotFoundError, json.JSONDecodeError):
    enabled = set()

if not enabled:
    sys.exit(0)

try:
    apps = json.loads(
        subprocess.run(
            [sys.executable, LIST_APPS], capture_output=True, text=True, check=True
        ).stdout
    )
except (subprocess.CalledProcessError, json.JSONDecodeError):
    sys.exit(0)

for app in apps:
    if app["name"] not in enabled:
        continue
    exec_ = with_minimize_flag(app["exec"], MINIMIZE_FLAGS.get(app["name"]))
    cmd = f"kitty -e {exec_}" if app["terminal"] else exec_
    # hyprctl dispatch exec doesn't work on this Lua-config Hyprland build:
    # `hyprctl dispatch <name> <args>` evaluates as `hl.dispatch(<name>
    # <args>)`, and there's no bare global `exec` for it to resolve to
    # (only `hl.dsp.exec_cmd`/`hl.exec_cmd`) — confirmed via
    # `hyprctl dispatch exec "..."` failing with "attempt to call a nil
    # value (global 'exec')". `hyprctl eval 'hl.exec_cmd("...")'` works.
    subprocess.Popen(["hyprctl", "eval", f"hl.exec_cmd({lua_quote(cmd)})"])
