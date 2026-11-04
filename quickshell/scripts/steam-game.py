#!/usr/bin/env python3
"""Which Steam game a stream belongs to, as one JSON line: {"name", "art"}, or {}.

Takes a PID, or client:<id> for the stream's PipeWire client: a stream through
pipewire-pulse (ffplay's checked, and wine's Pulse output goes the same way)
carries no application.process.id on its node, only on its client, which
Quickshell doesn't expose -- so wpctl reads it here.

A game's audio stream says little about it -- under Proton application.name can
be anything the game or wine picked -- but Steam sets SteamAppId in the
environment of everything it launches, so that's what identifies it. Looked up
by AudioInfo.qml for the Control Center's source cards. A process in another
PID namespace (a Flatpak Steam) doesn't resolve here and shows as a plain app.
"""
import glob
import json
import os
import re
import subprocess
import sys

ROOTS = ("~/.local/share/Steam", "~/.steam/steam", "~/.var/app/com.valvesoftware.Steam/.local/share/Steam")


def env_of(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        return dict(e.split(b"=", 1) for e in f.read().split(b"\0") if b"=" in e)


def parent_of(pid):
    with open(f"/proc/{pid}/stat", encoding="utf-8", errors="replace") as f:
        # The name in brackets can hold spaces: ppid is the 2nd field after it.
        return int(f.read().rsplit(")", 1)[1].split()[1])


def app_id(pid):
    # The stream's process is usually the game itself, but a launcher's child
    # can have dropped it: look a few parents up.
    for _ in range(6):
        if pid <= 1:
            return None
        try:
            env = env_of(pid)
            for key in (b"SteamAppId", b"SteamGameId"):
                value = env.get(key, b"")
                if value.isdigit() and value != b"0":
                    return value.decode()
            pid = parent_of(pid)
        except (OSError, ValueError, IndexError):
            return None
    return None


def pid_of(arg):
    if arg.isdigit():
        return int(arg)
    if arg.startswith("client:") and arg[7:].isdigit():
        out = subprocess.run(["wpctl", "inspect", arg[7:]], capture_output=True, text=True).stdout
        m = re.search(r'application\.process\.id = "(\d+)"', out)
        return int(m.group(1)) if m else None
    return None


def main():
    pid = pid_of(sys.argv[1]) if len(sys.argv) > 1 else None
    appid = app_id(pid) if pid else None
    if not appid:
        print("{}")
        return
    for root in map(os.path.expanduser, ROOTS):
        libs = [root]
        try:
            with open(os.path.join(root, "steamapps", "libraryfolders.vdf"), encoding="utf-8") as f:
                libs += [m.group(1) for m in re.finditer(r'"path"\s+"([^"]+)"', f.read())]
        except OSError:
            continue
        name = ""
        for lib in libs:
            try:
                with open(os.path.join(lib, "steamapps", f"appmanifest_{appid}.acf"), encoding="utf-8") as f:
                    m = re.search(r'"name"\s+"([^"]+)"', f.read())
                    name = m.group(1) if m else ""
                    break
            except OSError:
                continue
        # Directly in the app's folder for some games, a hash folder down for others.
        cache = os.path.join(root, "appcache", "librarycache", appid)
        art = sorted(glob.glob(os.path.join(cache, "**", "header.jpg"), recursive=True))
        print(json.dumps({"name": name, "art": art[0] if art else ""}))
        return
    print("{}")


main()
