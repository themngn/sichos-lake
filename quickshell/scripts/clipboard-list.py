#!/usr/bin/env python3
"""Lists cliphist's history for the clipboard picker (Picker.qml,
SUPER+SHIFT+V), newest first.

    clipboard-list.py

Prints one JSON array: [{"line": ..., "text": ..., "image": path|"",
"info": ...}, ...]. `line` is cliphist's own "<id>\\t<preview>" line, passed
back verbatim to `cliphist decode`/`cliphist delete` on stdin -- both parse
the id from it, so the picker never has to know cliphist's id format.

Image entries only have a "[[ binary data 13 KiB png 367x33 ]]" preview, so
each is decoded once into a per-session thumbnail cache under
$XDG_RUNTIME_DIR (tmpfs, gone at logout) for the picker to show instead.
cliphist ids are never reused, so a cached file never goes stale; files for
ids that dropped out of the history get pruned here.
"""
import json
import os
import re
import subprocess
import sys

BINARY = re.compile(r"^\[\[ binary data (.+) (\w+) (\d+)x(\d+) \]\]$")
IMAGE_EXTS = {"png", "jpeg", "jpg", "gif", "bmp", "webp"}

cache = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "sichos-clipboard")
os.makedirs(cache, exist_ok=True)

try:
    out = subprocess.run(["cliphist", "list"], capture_output=True, check=True).stdout
except (OSError, subprocess.CalledProcessError):
    print("[]")
    sys.exit(0)

items = []
keep = set()
for raw in out.decode("utf-8", "replace").splitlines():
    entry_id, _, preview = raw.partition("\t")
    item = {"line": raw, "text": preview, "image": "", "info": ""}
    m = BINARY.match(preview)
    if m:
        size, ext, w, h = m.groups()
        item["info"] = f"{ext.upper()} · {w}×{h} · {size}"
        if ext.lower() in IMAGE_EXTS:
            path = os.path.join(cache, f"{entry_id}.{ext.lower()}")
            keep.add(os.path.basename(path))
            if not os.path.exists(path):
                with open(path, "wb") as f:
                    subprocess.run(["cliphist", "decode"], input=raw.encode(), stdout=f)
            item["image"] = path
    items.append(item)

for name in os.listdir(cache):
    if name not in keep:
        os.remove(os.path.join(cache, name))

json.dump(items, sys.stdout)
