#!/usr/bin/env python3
"""The file behind an icon-theme name, for the source cards' colour pick.

ColorQuantizer can't load image://icon/ URLs ("Failed to load image"), so a
card with no cover had no colour of its own. Looks through hicolor, the other
installed themes and pixmaps, biggest size first, in the data dirs plus
Flatpak's exports. Prints the path, or nothing.
"""
import glob
import os
import re
import sys


def size_of(path):
    m = re.search(r"/(\d+)x\d+", path)
    # A scalable icon counts as the largest; symbolic ones are monochrome.
    return 100000 if "/scalable/" in path else int(m.group(1)) if m else 0


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else ""
    if not name or "/" in name:
        return
    dirs = [os.path.expanduser("~/.local/share")]
    dirs += os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
    dirs += [os.path.expanduser("~/.local/share/flatpak/exports/share"), "/var/lib/flatpak/exports/share"]
    for theme in ("hicolor", "*"):
        hits = []
        for d in dirs:
            for ext in ("png", "svg"):
                hits += glob.glob(os.path.join(glob.escape(d), "icons", theme, "**", f"{glob.escape(name)}.{ext}"), recursive=True)
        hits = [h for h in hits if "symbolic" not in h]
        if hits:
            print(max(hits, key=size_of))
            return
    for d in dirs:
        for ext in ("png", "svg"):
            path = os.path.join(d, "pixmaps", f"{name}.{ext}")
            if os.path.exists(path):
                print(path)
                return


main()
