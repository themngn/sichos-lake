#!/usr/bin/env python3
"""Indexes installed .desktop files for the quickshell launcher.

Emits a JSON array of {name, exec, icon, terminal} on stdout, sorted by
name. Later directories in `dirs` win over earlier ones for the same
desktop-file basename, matching XDG_DATA_HOME > XDG_DATA_DIRS precedence
(user overrides system).

Also appends installed Steam games (read straight from Steam's own
appmanifest_*.acf files, not .desktop entries — Steam doesn't generate one
per game unless the user manually asks for a desktop shortcut) with
`"steam": true` so the launcher's Games folder can find them.
"""
import configparser
import glob
import json
import os
import re
import sys

dirs = [
    "/usr/share/applications",
    "/usr/local/share/applications",
    "/var/lib/flatpak/exports/share/applications",
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
    os.path.expanduser("~/.local/share/applications"),
]

field_code = re.compile(r"%[a-zA-Z%]")
apps_by_base = {}

for d in dirs:
    for path in sorted(glob.glob(os.path.join(d, "*.desktop"))):
        base = os.path.basename(path)
        cp = configparser.RawConfigParser(strict=False)
        try:
            cp.read(path, encoding="utf-8")
        except Exception:
            continue
        if "Desktop Entry" not in cp:
            continue
        e = cp["Desktop Entry"]
        if e.get("Type", "Application") != "Application":
            continue
        if e.getboolean("NoDisplay", fallback=False):
            continue
        if e.getboolean("Hidden", fallback=False):
            continue
        name = e.get("Name", "")
        exec_ = e.get("Exec", "")
        if not name or not exec_:
            continue
        exec_ = field_code.sub("", exec_).strip()
        apps_by_base[base] = {
            "name": name,
            "exec": exec_,
            "icon": e.get("Icon", ""),
            "terminal": e.getboolean("Terminal", fallback=False),
        }


# Steam library discovery: appmanifest_*.acf files exist for every
# installed app id under each library's steamapps/ dir, games and Valve's
# own compat tools alike (Proton builds, the Steam Linux Runtime) — there's
# no offline, parseable field that cleanly tells them apart, so those few
# known non-game names are just skipped by name. Anything else that slips
# through can still be sent to the launcher's existing Hidden folder.
_STEAM_TOOL_PREFIXES = ("Proton ", "Steam Linux Runtime", "Steamworks Common Redistributables")


def _steam_root():
    for candidate in (
        os.path.expanduser("~/.local/share/Steam"),
        os.path.expanduser("~/.steam/steam"),
        os.path.expanduser("~/.var/app/com.valvesoftware.Steam/.local/share/Steam"),
    ):
        if os.path.isdir(os.path.join(candidate, "steamapps")):
            return candidate
    return None


def _steam_library_paths(root):
    libs = [root]
    vdf_path = os.path.join(root, "steamapps", "libraryfolders.vdf")
    try:
        with open(vdf_path, encoding="utf-8") as f:
            content = f.read()
        for m in re.finditer(r'"path"\s+"([^"]+)"', content):
            path = m.group(1).replace("\\\\", "/")
            if path not in libs:
                libs.append(path)
    except OSError:
        pass
    return libs


_STEAM_EXEC_APPID = re.compile(r"(?:rungameid/|-applaunch\s+)(\d+)")


def _steam_appids():
    """appid -> a real .desktop entry already covering it (Steam itself, or
    the user, creates one under ~/.local/share/applications for a game
    that's been run/pinned at least once) — its Icon is a genuine
    icon-theme name Quickshell can resolve, unlike anything this script
    could guess at from Steam's own cache, so an existing entry always
    wins over adding a synthetic one for the same game."""
    result = {}
    for entry in apps_by_base.values():
        m = _STEAM_EXEC_APPID.search(entry["exec"])
        if m:
            result[m.group(1)] = entry
    return result


def _steam_games():
    root = _steam_root()
    if not root:
        return []
    existing = _steam_appids()
    games = []
    seen = set()
    for lib in _steam_library_paths(root):
        for manifest in sorted(glob.glob(os.path.join(lib, "steamapps", "appmanifest_*.acf"))):
            try:
                with open(manifest, encoding="utf-8") as f:
                    content = f.read()
            except OSError:
                continue
            appid_m = re.search(r'"appid"\s+"(\d+)"', content)
            name_m = re.search(r'"name"\s+"([^"]*)"', content)
            if not appid_m or not name_m:
                continue
            appid, name = appid_m.group(1), name_m.group(1)
            if not name or appid in seen or name.startswith(_STEAM_TOOL_PREFIXES):
                continue
            seen.add(appid)
            if appid in existing:
                # Tag the real .desktop entry in place instead of adding a
                # second, worse-iconed row for the same game.
                existing[appid]["steam"] = True
                continue
            entry = {
                "name": name,
                "exec": f"steam steam://rungameid/{appid}",
                "icon": "",
                "terminal": False,
                "steam": True,
            }
            # Steam's library-view cache has no fixed icon filename (the
            # actual small icon is a per-install content-hash .jpg/.ico), so
            # this settles for the one predictably-named image in there —
            # not a true icon, but recognizable, and better than nothing.
            logo_path = os.path.join(root, "appcache", "librarycache", appid, "logo.png")
            if os.path.isfile(logo_path):
                entry["iconFile"] = logo_path
            games.append(entry)
    return games


new_games = _steam_games()
apps = sorted(list(apps_by_base.values()) + new_games, key=lambda a: a["name"].lower())
json.dump(apps, sys.stdout)
