#!/usr/bin/env python3
"""Lists immediate subdirectories of a path for the launcher's primitive
folder picker (Settings > Custom Plugins > Add Plugin > Local Folder) —
this is UI-only, stateless directory browsing, so unlike
list-custom-widgets.py it doesn't need a live QML singleton behind it.

    list-dir.py <path>

Prints one JSON object: {"entries": [{"name": ..., "hasMainQml": bool}, ...],
"selfHasMainQml": bool, "error": string|null}. `entries` covers every
visible (non-dotfile) subdirectory of <path>, sorted case-insensitively;
one that raises on stat/access (permission denied, broken symlink) is
silently skipped rather than failing the whole listing, same tolerance
list-custom-widgets.py has for a broken widget dir. `selfHasMainQml` lets
the QML caller warn before installing a folder custom-widget.py would
reject outright for lacking main.qml.
"""
import json
import os
import sys


def result(entries=None, self_has_main_qml=False, error=None):
    print(json.dumps({
        "entries": entries or [],
        "selfHasMainQml": self_has_main_qml,
        "error": error,
    }))


def main():
    if len(sys.argv) < 2:
        result(error="usage: list-dir.py <path>")
        return
    path = os.path.abspath(os.path.expanduser(sys.argv[1]))

    if not os.path.isdir(path):
        result(error=f"not a directory: {path}")
        return

    entries = []
    try:
        names = os.listdir(path)
    except OSError as e:
        result(error=str(e))
        return

    for name in names:
        if name.startswith("."):
            continue
        full = os.path.join(path, name)
        try:
            if not os.path.isdir(full):
                continue
            has_main_qml = os.path.isfile(os.path.join(full, "main.qml"))
        except OSError:
            continue
        entries.append({"name": name, "hasMainQml": has_main_qml})

    entries.sort(key=lambda e: e["name"].lower())
    self_has_main_qml = os.path.isfile(os.path.join(path, "main.qml"))
    result(entries=entries, self_has_main_qml=self_has_main_qml)


if __name__ == "__main__":
    main()
