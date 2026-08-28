#!/usr/bin/env python3
"""Indexes installed .desktop files for the quickshell launcher.

Emits a JSON array of {name, exec, icon, terminal} on stdout, sorted by
name. Later directories in `dirs` win over earlier ones for the same
desktop-file basename, matching XDG_DATA_HOME > XDG_DATA_DIRS precedence
(user overrides system).
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

apps = sorted(apps_by_base.values(), key=lambda a: a["name"].lower())
json.dump(apps, sys.stdout)
